%% @copyright 2017 Takeru Ohta <phjgt308@gmail.com>
-module(gen_server_passage).

-behaviour(gen_server).

-include_lib("passage/include/opentracing.hrl").

%%------------------------------------------------------------------------------
%% Exported API
%%------------------------------------------------------------------------------
-export([start_link/3, start_link/4]).
-export([call/2, call/3]).
-export([cast/2]).

%%------------------------------------------------------------------------------
%% 'gen_serer' Callback API
%%------------------------------------------------------------------------------
-export([init/1, handle_call/3, handle_cast/2, handle_info/2]).
-export([terminate/2, code_change/3, format_status/2]).

%%------------------------------------------------------------------------------
%% Macros & Records
%%------------------------------------------------------------------------------
-define(CONTEXT, ?MODULE).

-record(?CONTEXT,
        {
          %% TODO(?): Add `span` field
          application :: atom(),
          module      :: module(),
          state       :: term()
        }).

%%------------------------------------------------------------------------------
%% Exported Functions
%%------------------------------------------------------------------------------
-spec start_link(module(), term(), list()) -> term().
start_link(Module, Args, Options) ->
    Span = proplists:get_value(span, Options, passage_pd:current_span()),
    gen_server:start_link(?MODULE, {Span, Module, Args}, Options).

-spec start_link(term(), module(), term(), list()) -> term().
start_link(ServerName, Module, Args, Options) ->
    Span = proplists:get_value(span, Options, passage_pd:current_span()),
    gen_server:start_link(ServerName, ?MODULE, {Span, Module, Args}, Options).

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

%%------------------------------------------------------------------------------
%% 'gen_serer' Callback Functions
%%------------------------------------------------------------------------------
%% @private
init({undefined, Module, Args}) ->
    App = get_application(Module),
    do_init(App, Module, Args);
init({Span, Module, Args}) ->
    try
        App = get_application(Module),
        passage_pd:start_span(
          'gen_server_passage:init/1',
          [{child_of, Span},
           {tags, #{?TAG_COMPONENT => gen_server, % TODO
                    pid => self(),
                    application => App,
                    module => Module}}]),
        Result = do_init(App, Module, Args),
        case Result of
            ignore         -> passage_pd:set_tags(#{ignore => true});
            {stop, Reason} ->
                %% TODO: filter `normal', `shutown', `{shutdown, _}'
                passage_pd:log(#{?LOG_FIELD_MESSAGE => Reason}, [error]);
            _              -> ok
        end,
        Result
    catch
        Class:ExReason ->
            %% TODO: move to `passage` (passage:with_span(.., [error_if_exception], ..))
            Stack = erlang:get_stacktrace(),
            passage_pd:log(#{?LOG_FIELD_ERROR_KIND => Class,
                             ?LOG_FIELD_ERROR_KIND => ExReason,
                             ?LOG_FIELD_STACK => Stack},
                           [error]),
            erlang:raise(Class, ExReason, Stack)
    after
        passage_pd:finish_span()
    end.

%% @private
handle_call({undefined, Request}, From, Context) ->
    do_handle_call(Request, From, Context);
handle_call({Span, Request}, From, Context) ->
    try
        passage_pd:start_span(
          'gen_server_passage:handle_call/3',
          [{child_of, Span}, {tags, tags(Context)}]),
        do_handle_call(Request, From, Context)
    catch
        Class:ExReason ->
            %% TODO: move to `passage` (passage:with_span(.., [error_if_exception], ..))
            Stack = erlang:get_stacktrace(),
            passage_pd:log(#{?LOG_FIELD_ERROR_KIND => Class,
                             ?LOG_FIELD_ERROR_KIND => ExReason,
                             ?LOG_FIELD_STACK => Stack},
                           [error]),
            erlang:raise(Class, ExReason, Stack)
    after
        passage_pd:finish_span()
    end.

%% @private
handle_cast({undefined, Request}, ontext) ->
    do_handle_cast(Request, Context);
handle_cast({Span, Request}, Context) ->
    try
        passage_pd:start_span(
          'gen_server_passage:handle_cast/2',
          [{follows_from, Span}, {tags, tags(Context)}]),
        do_handle_cast(Request, From, Context)
    catch
        Class:ExReason ->
            %% TODO: move to `passage` (passage:with_span(.., [error_if_exception], ..))
            Stack = erlang:get_stacktrace(),
            passage_pd:log(#{?LOG_FIELD_ERROR_KIND => Class,
                             ?LOG_FIELD_ERROR_KIND => ExReason,
                             ?LOG_FIELD_STACK => Stack},
                           [error]),
            erlang:raise(Class, ExReason, Stack)
    after
        passage_pd:finish_span()
    end.

%%------------------------------------------------------------------------------
%% Internal Functions
%%------------------------------------------------------------------------------
-spec tags(#?CONTEXT{}) -> passage:tags().
tags(#?CONTEXT{application = App, module = Module}) ->
    #{?TAG_COMPONENT => gen_server,
      pid => self(),
      application => App,
      module => Module}.

-spec get_application(module()) -> atom().
get_application(Module) ->
    case application:get_application(Module) of
        undefined -> undefined;
        {ok, App} -> App
    end.

-spec do_init(atom(), module(), term()) -> term().
do_init(App, Module, Args) ->
    case Module:init(Args) of
        {ok, State} ->
            {ok, #?CONTEXT{application = App, module = Module, state = State}};
        {ok, State, Ext} ->
            {ok, #?CONTEXT{application = App, module = Module, state = State}, Ext};
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
do_handle_call(Request, Context0 = #?CONTEXT{module = Module, state = State0}) ->
    Result = Module:handle_cast(Request, State0),
    StateIndex =
        case element(1, Result) of
            noreply -> 2;
            stop    -> 3
        end,
    Context1 = Context0#?CONTEXT{state = element(StateIndex, Result)},
    setelement(StateIndex, Result, Context1).
