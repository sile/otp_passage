%% @copyright 2017 Takeru Ohta <phjgt308@gmail.com>
%%
%% ```
%% > jaeger_passage:start_tracer(example_tracer, passage_sampler_all:new()).
%% ok
%%
%% > gen_server_passage_example:start_link().
%% {ok, <0.352.0>}
%%
%% > gen_server_passage_example:ping().
%% pong
%%
%% > exit(normal).
%% ** exception exit: normal
%% '''
%%
%% @private
-module(gen_server_passage_example).

-compile({parse_transform, passage_transform}).

%%------------------------------------------------------------------------------
%% Exported API
%%------------------------------------------------------------------------------
-export([start_link/0]).
-export([ping/0, safe_ping/0]).

%%------------------------------------------------------------------------------
%% 'gen_server' Callback API
%%------------------------------------------------------------------------------
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2, code_change/3]).

%%------------------------------------------------------------------------------
%% Exported Functions
%%------------------------------------------------------------------------------
-spec start_link() -> {ok, pid()} | {error, Reason :: term()}.
start_link() ->
    gen_server_passage:start_link(
      {local, ?MODULE}, ?MODULE, [],
      [{inspect, true},
       {trace_process_lifecycle, [{tracer, example_tracer}]}]).

-passage_trace([{tracer, "example_tracer"}]).
-spec ping() -> pong.
ping() ->
    gen_server_passage:call(?MODULE, ping).

-passage_trace([{tracer, "example_tracer"}]).
-spec safe_ping() -> pong.
safe_ping() ->
    gen_server_passage:safe_call(?MODULE, ?MODULE, ping).

%%------------------------------------------------------------------------------
%% 'gen_server' Callback API
%%------------------------------------------------------------------------------
%% @private
init([]) ->
    {ok, []}.

%% @private
handle_call(ping, _From, State) ->
    Pong = gen_server_passage:with_process_span(fun() -> handle_ping() end),
    {reply, Pong, State}.

%% @private
handle_cast(_Request, State) ->
    {noreply, State}.

%% @private
handle_info(_Info, State) ->
    {noreply, State}.

%% @private
terminate(_Reason, _State) ->
    ok.

%% @private
code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

%%------------------------------------------------------------------------------
%% Internal Functions
%%------------------------------------------------------------------------------
-passage_trace([]).
-spec handle_ping() -> pong.
handle_ping() ->
    pong.
