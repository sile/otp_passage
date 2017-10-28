%% @copyright 2017 Takeru Ohta <phjgt308@gmail.com>
-module(gen_server_passage).

-behaviour(gen_server).

-include_lib("passage/include/opentracing.hrl").

%%------------------------------------------------------------------------------
%% Exported API
%%------------------------------------------------------------------------------
-export([start/3, start/4]).
-export([start_link/3, start_link/4]).
-export([stop/1, stop/3]).
-export([call/2, call/3]).
-export([cast/2]).
-export([reply/2]).
-export([process_span/0]).
-export([with_process_span/1]).

-export_type([start_option/0, start_options/0]).

%%------------------------------------------------------------------------------
%% 'gen_server' Callback API
%%------------------------------------------------------------------------------
-export([init/1, handle_call/3, handle_cast/2, handle_info/2]).
-export([terminate/2, code_change/3, format_status/2]).

%%------------------------------------------------------------------------------
%% Macros & Records
%%------------------------------------------------------------------------------
-define(PROCESS_SPAN_KEY, gen_server_passage_process_span).

-define(CONTEXT, ?MODULE).

-record(?CONTEXT,
        {
          application :: atom(),
          module      :: module(),
          state       :: term()
        }).

%%------------------------------------------------------------------------------
%% Exported Types
%%------------------------------------------------------------------------------
-type start_options() :: [start_option()].

-type start_option() :: {span, passage:maybe_span()}
                      | {trace_process_lifecycle, passage:start_span_options()}
                      | (GenServerOption :: term()).

%%------------------------------------------------------------------------------
%% Exported Functions
%%------------------------------------------------------------------------------
-spec start(module(), term(), list()) -> term().
start(Module, Args, Options0) ->
    {ProcessSpan, Span, Options1} =
        init_spans(undefined, Module, Options0, {undefined, undefined, []}),
    gen_server:start(?MODULE, {ProcessSpan, Span, Module, Args}, Options1).

-spec start(term(), module(), term(), list()) -> term().
start(ServerName, Module, Args, Options0) ->
    {ProcessSpan, Span, Options1} =
        init_spans(ServerName, Module, Options0, {undefined, undefined, []}),
    gen_server:start(ServerName, ?MODULE, {ProcessSpan, Span, Module, Args}, Options1).

-spec start_link(module(), term(), list()) -> term().
start_link(Module, Args, Options0) ->
    {ProcessSpan, Span, Options1} =
        init_spans(undefined, Module, Options0, {undefined, undefined, []}),
    gen_server:start_link(?MODULE, {ProcessSpan, Span, Module, Args}, Options1).

-spec start_link(term(), module(), term(), start_options()) -> term().
start_link(ServerName, Module, Args, Options0) ->
    {ProcessSpan, Span, Options1} =
        init_spans(ServerName, Module, Options0, {undefined, undefined, []}),
    gen_server:start_link(ServerName, ?MODULE, {ProcessSpan, Span, Module, Args}, Options1).

-spec stop(term()) -> ok.
stop(ServerRef) ->
    gen_server:stop(ServerRef).

-spec stop(term(), term(), timeout()) -> ok.
stop(ServerRef, Reason, Timeout) ->
    gen_server:stop(ServerRef, Reason, Timeout).

%% @equiv Call(Name, Request, 5000)
-spec call(term(), term()) -> term().
call(Name, Request) ->
    call(Name, Request, 5000).

-spec call(term(), term(), non_neg_integer()) -> term().
call(Name, Request, Timeout) ->
    Span = passage_pd:current_span(),
    gen_server:call(Name, {Span, Request}, Timeout).

-spec cast(term(), term()) -> ok.
cast(Name, Request) ->
    Span = passage_pd:current_span(),
    gen_server:cast(Name, {Span, Request}).

-spec reply(term(), term()) -> term().
reply(Client, Reply) ->
    gen_server:reply(Client, Reply).

-spec process_span() -> passage:maybe_span().
process_span() ->
    get(?PROCESS_SPAN_KEY).

-spec with_process_span(Fun) -> Result when
      Fun    :: fun (() -> Result),
      Result :: term().
with_process_span(Fun) ->
    passage_pd:with_parent_span(process_span(), Fun).

%%------------------------------------------------------------------------------
%% 'gen_server' Callback Functions
%%------------------------------------------------------------------------------
%% @private
init({ProcessSpan0, undefined, Module, Args}) ->
    ProcessSpan1 = passage:set_tags(ProcessSpan0, #{pid => self()}),
    passage:finish_span(ProcessSpan1, [{lifetime, self()}]),
    save_process_span(ProcessSpan1),

    App = get_application(Module),
    Context = #?CONTEXT{application = App, module = Module},
    do_init(Args, Context);
init({ProcessSpan0, Span, Module, Args}) ->
    ProcessSpan1 = passage:set_tags(ProcessSpan0, #{pid => self()}),
    passage:finish_span(ProcessSpan1, [{lifetime, self()}]),
    save_process_span(ProcessSpan1),

    App = get_application(Module),
    Context = #?CONTEXT{application = App, module = Module},
    passage_pd:with_span(
      'gen_server_passage:init/1',
      [{child_of, Span}, {tags, tags(Context)}, error_if_exception],
      fun () ->
              Result = do_init(Args, Context),
              case Result of
                  ignore         -> passage_pd:log(#{?LOG_FIELD_EVENT => ignore});
                  {stop, Reason} -> handle_stop(Reason);
                  _              -> ok
              end,
              Result
      end).

-spec handle_stop(term()) -> ok.
handle_stop(normal) ->
    passage_pd:log(#{?LOG_FIELD_EVENT => stop, ?LOG_FIELD_MESSAGE => normal});
handle_stop(shutdown) ->
    passage_pd:log(#{?LOG_FIELD_EVENT => stop, ?LOG_FIELD_MESSAGE => shutdown});
handle_stop({shutdown, Reason}) ->
    passage_pd:log(#{?LOG_FIELD_EVENT => stop, ?LOG_FIELD_MESSAGE => {shutdown, Reason}});
handle_stop(Error) ->
    passage_pd:log(#{?LOG_FIELD_MESSAGE => Error}, [error]).

%% @private
handle_call({undefined, Request}, From, Context) ->
    do_handle_call(Request, From, Context);
handle_call({Span, Request}, From, Context) ->
    passage_pd:with_span(
      'gen_server_passage:handle_call/3',
      [{child_of, Span}, {tags, tags(Context)}, error_if_exception],
      fun () ->
              Result = do_handle_call(Request, From, Context),
              case Result of
                  {stop, Reason, _}    -> handle_stop(Reason);
                  {stop, _, Reason, _} -> handle_stop(Reason);
                  _                    -> ok
              end,
              Result
      end).

%% @private
handle_cast({undefined, Request}, Context) ->
    do_handle_cast(Request, Context);
handle_cast({Span, Request}, Context) ->
    passage_pd:with_span(
      'gen_server_passage:handle_cast/2',
      [{follows_from, Span}, {tags, tags(Context)}, error_if_exception],
      fun () ->
              Result = do_handle_cast(Request, Context),
              case Result of
                  {stop, Reason, _} -> handle_stop(Reason);
                  _                 -> ok
              end,
              Result
      end).

%% @private
handle_info(Info, Context) ->
    case erlang:function_exported(Context#?CONTEXT.module, handle_info, 2) of
        false -> {noreply, Context};
        true  -> do_handle_info(Info, Context)
    end.

%% @private
terminate(Reason, Context) ->
    case erlang:function_exported(Context#?CONTEXT.module, terminate, 2) of
        false -> ok;
        true  -> do_terminate(Reason, Context)
    end.

%% @private
code_change(OldVsn, Context, Extra) ->
    passage_pd:with_span(
      'gen_server_passage:code_change/3',
      [{child_of, process_span()}, {tags, tags(Context)}, error_if_exception],
      fun () ->
              do_code_change(OldVsn, Context, Extra)
      end).

%% @private
format_status(Opt, [PDict, #?CONTEXT{module = Module, state = State}]) ->
    case erlang:function_exported(Module, format_status, 2) of
        false -> State;
        true  -> Module:format_status(Opt, [PDict, State])
    end.

%%------------------------------------------------------------------------------
%% Internal Functions
%%------------------------------------------------------------------------------
-spec tags(#?CONTEXT{}) -> passage:tags().
tags(#?CONTEXT{application = App, module = Module}) ->
    #{?TAG_COMPONENT => gen_server,
      node => node(),
      pid => self(),
      application => App,
      module => Module}.

-spec get_application(module()) -> atom().
get_application(Module) ->
    case application:get_application(Module) of
        undefined -> undefined;
        {ok, App} -> App
    end.

-spec do_init(term(), #?CONTEXT{}) -> term().
do_init(Args, Context = #?CONTEXT{module = Module}) ->
    case Module:init(Args) of
        {ok, State} ->
            {ok, Context#?CONTEXT{state = State}};
        {ok, State, Ext} ->
            {ok, Context#?CONTEXT{state = State}, Ext};
        Other ->
            Other
    end.

-spec do_handle_call(term(), term(), #?CONTEXT{}) -> term().
do_handle_call(Request, From, Context0 = #?CONTEXT{module = Module, state = State0}) ->
    Result = Module:handle_call(Request, From, State0),
    StateIndex =
        case element(1, Result) of
            reply   -> 3;
            noreply -> 2;
            stop    -> tuple_size(Result)
        end,
    Context1 = Context0#?CONTEXT{state = element(StateIndex, Result)},
    setelement(StateIndex, Result, Context1).

-spec do_handle_cast(term(), #?CONTEXT{}) -> term().
do_handle_cast(Request, Context0 = #?CONTEXT{module = Module, state = State0}) ->
    Result = Module:handle_cast(Request, State0),
    StateIndex =
        case element(1, Result) of
            noreply -> 2;
            stop    -> 3
        end,
    Context1 = Context0#?CONTEXT{state = element(StateIndex, Result)},
    setelement(StateIndex, Result, Context1).

-spec do_handle_info(term(), #?CONTEXT{}) -> term().
do_handle_info(Info, Context0 = #?CONTEXT{module = Module, state = State0}) ->
    Result = Module:handle_ifo(Info, State0),
    StateIndex =
        case element(1, Result) of
            noreply -> 2;
            stop    -> 3
        end,
    Context1 = Context0#?CONTEXT{state = element(StateIndex, Result)},
    setelement(StateIndex, Result, Context1).

-spec do_terminate(term(), #?CONTEXT{}) -> term().
do_terminate(Reason, #?CONTEXT{module = Module, state = State}) ->
    Module:terminate(Reason, State).

-spec do_code_change(term(), #?CONTEXT{}, term()) -> term().
do_code_change(OldVsn, Context = #?CONTEXT{module = Module, state = State0}, Extra) ->
    case Module:code_change(OldVsn, State0, Extra) of
        {ok, State1}    -> {ok, Context#?CONTEXT{state = State1}};
        {error, Reason} -> {error, Reason}
    end.

-spec init_spans(term(), module(), start_options(), Acc) -> Result when
      Acc    :: {passage:maybe_span(), passage:maybe_span(), list()},
      Result :: Acc.
init_spans(_, _, [], Acc) ->
    Acc;
init_spans(Name, Module, [{span, Span} | Options], Acc) ->
    init_spans(Name, Module, Options, setelement(2, Acc, Span));
init_spans(Name, Module, [{trace_process_lifecycle, StartSpanOptions} | Options], Acc) ->
    ProcessSpan0 = passage:start_span(trace_process_lifecycle, StartSpanOptions),
    ProcessSpan1 =
        passage:set_tags(
          ProcessSpan0,
          #{?TAG_COMPONENT => gen_server,
            process_name => Name,
            node => node(),
            application => get_application(Module),
            module => Module}),
    init_spans(Name, Module, Options, setelement(1, Acc, ProcessSpan1));
init_spans(Name, Module, [O | Options], Acc = {_, _, Os}) ->
    init_spans(Name, Module, Options, setelement(3, Acc, [O | Os])).

-spec save_process_span(passage:maybe_span()) -> ok.
save_process_span(Span) ->
    put(?PROCESS_SPAN_KEY, passage:strip_span(Span)),
    ok.
