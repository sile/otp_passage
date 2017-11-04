%% @copyright 2017 Takeru Ohta <phjgt308@gmail.com>
%%
%% @doc `gen_server' wrapper module for providing tracing facility.
%%
%% The tracing facility is based on <a href="https://github.com/sile/passage">passage</a>.
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
-export([safe_call/3, safe_call/4]).
-export([safe_cast/3]).
-export([reply/2]).
-export([process_span/0]).
-export([with_process_span/1]).

-export_type([start_option/0, start_options/0]).
-export_type([start_result/0]).
-export_type([server_name/0]).
-export_type([server_ref/0]).

%%------------------------------------------------------------------------------
%% 'gen_server' Callback API
%%------------------------------------------------------------------------------
-export([init/1, handle_call/3, handle_cast/2, handle_info/2]).
-export([terminate/2, code_change/3, format_status/2]).

%%------------------------------------------------------------------------------
%% Macros & Records
%%------------------------------------------------------------------------------
-define(PROCESS_SPAN_KEY, gen_server_passage_process_span).
-define(SPAN_TAG, 'WithSpan').

-define(CONTEXT, ?MODULE).

-record(?CONTEXT,
        {
          module          :: module(),
          state           :: term(),
          inspect = false :: boolean()
        }).

%%------------------------------------------------------------------------------
%% Exported Types
%%------------------------------------------------------------------------------
-type start_options() :: [start_option()].

-type start_option() :: {span, passage:maybe_span()}
                      | {trace_process_lifecycle, passage:start_span_options()}
                      | {inspect, boolean()}
                      | (GenServerOptions :: term()).
%% <ul>
%%   <li>`span': The parent span that starting this process. The default value is `passage_pb:current_span()'.</li>
%%   <li>`trace_process_lifecycle': If this option is specified, the started process has a span including from the start of the process to the end of it. The span can be retrieved from the running process by calling {@link process_span/0}.</li>
%%   <li>`insepct': If `true', spans for {@link init/1}, {@link handle_call/3} and {@link handle_cast/2} are inserted. The default value is `false'.</li>
%% </ul>
%%
%% `GenServerOptions' are options handled by the `gen_server' functions
%% (e.g., <a href="http://erlang.org/doc/man/gen_server.html#start_link-3">gen_server:start_link/3</a>).

-type start_result() :: {ok, pid()}
                      | ignore
                      | {error, {already_started, pid()} | term()}.
%% The result of a process startup.
%%
%% See the documentation of <a href="http://erlang.org/doc/man/gen_server.html">gen_server</a> module for more details.

-type server_name() :: {local, atom()}
                     | {global, term()}
                     | {via, module(), term()}.
%% The name of a `gen_server' process.
%%
%% See the documentation of <a href="http://erlang.org/doc/man/gen_server.html">gen_server</a> module for more details.

-type server_ref() :: pid()
                    | atom()
                    | {atom(), node()}
                    | {global, term()}
                    | {via, module(), term()}.
%% A reference to a `gen_server' process.
%%
%% See the documentation of <a href="http://erlang.org/doc/man/gen_server.html">gen_server</a> module for more details.

%%------------------------------------------------------------------------------
%% Exported Functions
%%------------------------------------------------------------------------------

%% @doc Traceable variant of <a href="http://erlang.org/doc/man/gen_server.html#start-3">gen_server:start/3</a>.
-spec start(module(), term(), start_options()) -> start_result().
start(Module, Args, Options0) ->
    ok = otp_passage_capability_table:register_capable_server(Module),
    {ProcessSpan, Span, Inspect, Options1} =
        init_options(undefined, Module, Options0, {undefined, passage_pd:current_span(), false, []}),
    gen_server:start(?MODULE, {Module, Args, ProcessSpan, Span, Inspect}, Options1).

%% @doc Traceable variant of <a href="http://erlang.org/doc/man/gen_server.html#start-4">gen_server:start/4</a>.
-spec start(server_name(), module(), term(), start_options()) -> start_result().
start(ServerName, Module, Args, Options0) ->
    ok = otp_passage_capability_table:register_capable_server(Module),
    {ProcessSpan, Span, Inspect, Options1} =
        init_options(ServerName, Module, Options0, {undefined, passage_pd:current_span(), false, []}),
    gen_server:start(ServerName, ?MODULE, {Module, Args, ProcessSpan, Span, Inspect}, Options1).

%% @doc Traceable variant of <a href="http://erlang.org/doc/man/gen_server.html#start_link-3">gen_server:start_link/3</a>.
-spec start_link(module(), term(), start_options()) -> start_result().
start_link(Module, Args, Options0) ->
    ok = otp_passage_capability_table:register_capable_server(Module),
    {ProcessSpan, Span, Inspect, Options1} =
        init_options(undefined, Module, Options0, {undefined, passage_pd:current_span(), false, []}),
    gen_server:start_link(?MODULE, {Module, Args, ProcessSpan, Span, Inspect}, Options1).

%% @doc Traceable variant of <a href="http://erlang.org/doc/man/gen_server.html#start_link-4">gen_server:start_link/4</a>.
-spec start_link(server_name(), module(), term(), start_options()) -> start_result().
start_link(ServerName, Module, Args, Options0) ->
    ok = otp_passage_capability_table:register_capable_server(Module),
    {ProcessSpan, Span, Inspect, Options1} =
        init_options(ServerName, Module, Options0, {undefined, passage_pd:current_span(), false, []}),
    gen_server:start_link(ServerName, ?MODULE, {Module, Args, ProcessSpan, Span, Inspect}, Options1).

%% @equiv gen_server:stop/1
-spec stop(server_ref()) -> ok.
stop(ServerRef) ->
    gen_server:stop(ServerRef).

%% @equiv gen_server:stop/3
-spec stop(server_ref(), term(), timeout()) -> ok.
stop(ServerRef, Reason, Timeout) ->
    gen_server:stop(ServerRef, Reason, Timeout).

%% @equiv call(ServerRef, Request, 5000)
-spec call(server_ref(), term()) -> Reply :: term().
call(ServerRef, Request) ->
    call(ServerRef, Request, 5000).

%% @doc Traceable variant of <a href="http://erlang.org/doc/man/gen_server.html#call-3">gen_server:call/3</a>.
%%
%% This piggybacks the current span which retrieved by {@link passage_pd:current_span/1} when sending `Request' to `ServerRef'.
%% The span will be handled by `{@module}:handle_call/3' transparently for the `gen_server' implementation module.
%%
%% Note that it is prefered to use {@link safe_call/4} in a distributed environment where multiple nodes constitute an erlang cluster.
-spec call(server_ref(), term(), timeout()) -> Reply :: term().
call(ServerRef, Request, Timeout) ->
    case passage:strip_span(passage_pd:current_span()) of
        undefined -> gen_server:call(ServerRef, Request, Timeout);
        Span      -> gen_server:call(ServerRef, {Request, ?SPAN_TAG, Span}, Timeout)
    end.

%% @equiv safe_call(Module, ServerRef, Request, 500)
-spec safe_call(module(), server_ref(), term()) -> Reply :: term().
safe_call(CallbackModule, ServerRef, Request) ->
    safe_call(CallbackModule, ServerRef, Request, 5000).

%% @doc A variant of {@link call/3} that is safe even in a multiple nodes environment.
%%
%% This function checks if the server process for `CallbackModule' in `Node'
%% has the capability to handle tracing.
%% If it has no capability,
%% this will switch to the ordinary `gen_server:call/3' function internally.
%%
%% The checking result is cached in the local ETS.
%% So normally, the cost between {@link call/3} and {@link safe_call/4} is negligible.
-spec safe_call(module(), server_ref(), term(), timeout()) -> Reply :: term().
safe_call(CallbackModule, ServerRef, Request, Timeout) ->
    case is_capable_server(ServerRef, CallbackModule) of
        false -> gen_server:call(ServerRef, Request, Timeout);
        true  -> call(ServerRef, Request, Timeout)
    end.

%% @doc Traceable variant of <a href="http://erlang.org/doc/man/gen_server.html#cast-2">gen_server:cast/2</a>.
%%
%% This piggybacks the current span which retrieved by {@link passage_pd:current_span/1} when sending `Request' to `ServerRef'.
%% The span will be handled by `{@module}:handle_cast/2' transparently for the `gen_server' implementation module.
%%
%% Note that it is prefered to use {@link safe_cast/3} in a distributed environment where multiple nodes constitute an erlang cluster.
-spec cast(server_ref(), term()) -> ok.
cast(ServerRef, Request) ->
    case passage:strip_span(passage_pd:current_span()) of
        undefined -> gen_server:cast(ServerRef, Request);
        Span      -> gen_server:cast(ServerRef, {Request, ?SPAN_TAG, Span})
    end.

%% @doc A variant of {@link call/3} that is safe even in a multiple nodes environment.
%%
%% This function checks if the server process for `CallbackModule' in `Node'
%% has the capability to handle tracing.
%% If it has no capability,
%% this will switch to the ordinary `gen_server:cast/2' function internally.
%%
%% The checking result is cached in the local ETS.
%% So normally, the cost between {@link cast/2} and {@link safe_cast/3} is negligible.
-spec safe_cast(module(), server_ref(), term()) -> ok.
safe_cast(CallbackModule, ServerRef, Request) ->
    case is_capable_server(ServerRef, CallbackModule) of
        false -> gen_server:cast(ServerRef, Request);
        true  -> cast(ServerRef, Request)
    end.

%% @equiv gen_server:reply/2
-spec reply(term(), term()) -> term().
reply(Client, Reply) ->
    gen_server:reply(Client, Reply).

%% @doc Returns the process scope span.
%%
%% See also: `trace_process_lifecycle' option of {@type start_option()}.
-spec process_span() -> passage:maybe_span().
process_span() ->
    get(?PROCESS_SPAN_KEY).

%% @doc Executes `Fun' within the process scope span.
%%
%% See also: `trace_process_lifecycle' option of {@type start_option()}.
-spec with_process_span(Fun) -> Result when
      Fun    :: fun (() -> Result),
      Result :: term().
with_process_span(Fun) ->
    passage_pd:with_parent_span({child_of, process_span()}, Fun).

%%------------------------------------------------------------------------------
%% 'gen_server' Callback Functions
%%------------------------------------------------------------------------------
%% @private
init({Module, Args, ProcessSpan0, undefined, Inspect}) ->
    ProcessSpan1 = passage:set_tags(ProcessSpan0, #{pid => self()}),
    passage:finish_span(ProcessSpan1, [{lifetime, self()}]),
    save_process_span(ProcessSpan1),

    Context = #?CONTEXT{module = Module, inspect = Inspect},
    do_init(Args, Context);
init({Module, Args, ProcessSpan0, Span, false}) ->
    ProcessSpan1 = passage:set_tags(ProcessSpan0, #{pid => self()}),
    passage:finish_span(ProcessSpan1, [{lifetime, self()}]),
    save_process_span(ProcessSpan1),

    Context = #?CONTEXT{module = Module},
    passage_pd:with_parent_span(
      {child_of, Span},
      fun () -> do_init(Args, Context) end);
init({Module, Args, ProcessSpan0, Span, true}) ->
    ProcessSpan1 = passage:set_tags(ProcessSpan0, #{pid => self()}),
    passage:finish_span(ProcessSpan1, [{lifetime, self()}]),
    save_process_span(ProcessSpan1),

    Context = #?CONTEXT{module = Module, inspect = true},
    passage_pd:with_span(
      'gen_server_passage:init/1',
      [{child_of, Span}, {tags, tags(Context)}],
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
handle_call({Request, ?SPAN_TAG, Span}, From, Context = #?CONTEXT{inspect = false}) ->
    passage_pd:with_parent_span(
      {child_of, Span},
      fun () -> do_handle_call(Request, From, Context) end);
handle_call({Request, ?SPAN_TAG, Span}, From, Context) ->
    passage_pd:with_span(
      'gen_server_passage:handle_call/3',
      [{child_of, Span}, {tags, tags(Context)}],
      fun () ->
              Result = do_handle_call(Request, From, Context),
              case Result of
                  {stop, Reason, _}    -> handle_stop(Reason);
                  {stop, _, Reason, _} -> handle_stop(Reason);
                  _                    -> ok
              end,
              Result
      end);
handle_call(Request, From, Context) ->
    do_handle_call(Request, From, Context).

%% @private
handle_cast({Request, ?SPAN_TAG, Span}, Context = #?CONTEXT{inspect = false}) ->
    passage_pd:with_parent_span(
      {follows_from, Span},
      fun () -> do_handle_cast(Request, Context) end);
handle_cast({Request, ?SPAN_TAG, Span}, Context) ->
    passage_pd:with_span(
      'gen_server_passage:handle_cast/2',
      [{follows_from, Span}, {tags, tags(Context)}],
      fun () ->
              Result = do_handle_cast(Request, Context),
              case Result of
                  {stop, Reason, _} -> handle_stop(Reason);
                  _                 -> ok
              end,
              Result
      end);
handle_cast(Request, Context) ->
    do_handle_cast(Request, Context).

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
      [{child_of, process_span()}, {tags, tags(Context)}],
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
tags(#?CONTEXT{module = Module}) ->
    #{?TAG_COMPONENT => gen_server,
      'location.pid' => self(),
      'gen_server.module' => Module}.

-spec do_init(term(), #?CONTEXT{}) -> term().
do_init(Args, Context = #?CONTEXT{module = Module}) ->
    case Module:init(Args) of
        {ok, State}      -> {ok, Context#?CONTEXT{state = State}};
        {ok, State, Ext} -> {ok, Context#?CONTEXT{state = State}, Ext};
        Other            -> Other
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
    Result = Module:handle_info(Info, State0),
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

-spec init_options(term(), module(), start_options(), Acc) -> Result when
      Acc    :: {passage:maybe_span(), passage:maybe_span(), boolean(), list()},
      Result :: Acc.
init_options(_, _, [], Acc) ->
    Acc;
init_options(Name, Module, [{span, Span} | Options], Acc) ->
    init_options(Name, Module, Options, setelement(2, Acc, Span));
init_options(Name, Module, [{trace_process_lifecycle, StartSpanOptions} | Options], Acc) ->
    ProcessSpan0 = passage:start_span(trace_process_lifecycle, StartSpanOptions),
    ProcessSpan1 =
        passage:set_tags(
          ProcessSpan0,
          #{?TAG_COMPONENT => gen_server,
            'gen_server.name' => Name,
            'gen_server.module'=> Module}),
    init_options(Name, Module, Options, setelement(1, Acc, ProcessSpan1));
init_options(Name, Module, [{inspect, V} | Options], Acc) ->
    init_options(Name, Module, Options, setelement(3, Acc, V));
init_options(Name, Module, [O | Options], Acc = {_, _, _, Os}) ->
    init_options(Name, Module, Options, setelement(4, Acc, [O | Os])).

-spec save_process_span(passage:maybe_span()) -> ok.
save_process_span(Span) ->
    put(?PROCESS_SPAN_KEY, passage:strip_span(Span)),
    ok.

-spec is_capable_server(server_ref(), module()) -> boolean().
is_capable_server(ServerRef, Module) ->
    case server_node(ServerRef) of
        undefined -> false;
        Node      -> otp_passage_capability_table:is_capable_server(Node, Module)
    end.

-spec server_node(server_ref()) -> node().
server_node(Pid) when is_pid(Pid) ->
    node(Pid);
server_node({_Name, Node}) ->
    Node;
server_node(Name) when is_atom(Name) ->
    node();
server_node({global, Name}) ->
    case global:whereis_name(Name) of
        undefined -> undefined;
        Pid       -> node(Pid)
    end;
server_node({via, Module, Name}) ->
    case catch Module:whereis_name(Name) of
        Pid when is_pid(Pid) -> node(Pid);
        _                    -> undefined
    end.
