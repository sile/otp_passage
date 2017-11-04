%% @copyright 2017 Takeru Ohta <phjgt308@gmail.com>
%%
%% @private
-module(otp_passage_capability_table).

-behaviour(gen_server).

%%------------------------------------------------------------------------------
%% Application Internal API
%%------------------------------------------------------------------------------
-export([start_link/0]).
-export([is_capable_node/1]).
-export([is_capable_server/1, is_capable_server/2]).
-export([register_capable_server/1]).

%%------------------------------------------------------------------------------
%% 'gen_server' Callback API
%%------------------------------------------------------------------------------
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2, code_change/3]).

%%------------------------------------------------------------------------------
%% Macros & Records
%%------------------------------------------------------------------------------
-define(TABLE, ?MODULE).
-define(STATE, ?MODULE).

-record(?STATE,
        {
          node_to_servers = #{} :: #{node() => [module()]}
        }).

%%------------------------------------------------------------------------------
%% Application Internal Functions
%%------------------------------------------------------------------------------
-spec start_link() -> {ok, pid()} | {error, Reason :: term()}.
start_link() ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).

-spec is_capable_node(node()) -> boolean().
is_capable_node(Node) when Node =:= node() ->
    true;
is_capable_node(Node) ->
    case ets:lookup(?TABLE, {node, Node}) of
        [{_, IsCapable}] -> IsCapable;
        _                -> false
    end.

-spec is_capable_server(module()) -> boolean().
is_capable_server(Module) ->
    is_capable_server(node(), Module).

-spec is_capable_server(node(), module()) -> boolean().
is_capable_server(Node, Module) ->
    case ets:lookup(?TABLE, {gen_server, Node, Module}) of
        [{_, IsCapable}] -> IsCapable;
        []               -> gen_server:call(?MODULE, {is_capable_server, Node, Module})
    end.

-spec register_capable_server(module()) -> ok.
register_capable_server(Module) ->
    case ets:lookup(?TABLE, {gen_server, node(), Module}) of
        [{_, true}] -> ok;
        _           -> gen_server:cast(?MODULE, {register_capable_server, Module})
    end.

%%------------------------------------------------------------------------------
%% 'gen_server' Callback Functions
%%------------------------------------------------------------------------------
%% @private
init([]) ->
    _ = ets:new(?TABLE, [named_table, protected, {read_concurrency, true}]),
    ok = net_kernel:monitor_nodes(true, [{node_type, all}]),
    {ok, #?STATE{}}.

%% @private
handle_call({is_capable_server, Node, Module}, _From, State) ->
    handle_is_capable_server(Node, Module, State);
handle_call(_Request, _From, State) ->
    {noreply, State}.

%% @private
handle_cast({register_capable_server, Module}, State) ->
    handle_register_capable_server(Module, State);
handle_cast(_Request, State) ->
    {noreply, State}.

%% @private
handle_info({nodeup, Node}, State) ->
    handle_nodeup(Node, State);
handle_info({nodedown, Node}, State) ->
    handle_nodedown(Node, State);
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
-spec handle_nodeup(node(), #?STATE{}) -> {noreply, #?STATE{}}.
handle_nodeup(Node, State) ->
    case catch rpc:call(Node, erlang, module_loaded, [?MODULE], 1000) of
        true ->
            ets:insert(?TABLE, {{node, Node}, true}),
            {noreply, State};
        false ->
            {noreply, State};
        Error ->
            error_logger:error_msg("[~p:~p] RPC failed: node=~p, reason=~1024p\n",
                                   [?MODULE, ?LINE, Node, Error]),
            {noreply, State}
    end.

-spec handle_nodedown(node(), #?STATE{}) -> {noreply, #?STATE{}}.
handle_nodedown(Node, State0) ->
    ets:delete(?TABLE, {node, Node}),
    Servers0 = State0#?STATE.node_to_servers,
    Servers1 =
        case Servers0 of
            #{Node := ServerModules} ->
                Delete = fun (Module) -> ets:delete(?TABLE, {gen_server, Node, Module}) end,
                lists:foreach(Delete, ServerModules),
                maps:remove(Node, Servers0);
            _ ->
                Servers0
        end,
    State1 = State0#?STATE{node_to_servers = Servers1},
    {noreply, State1}.

-spec handle_register_capable_server(module(), #?STATE{}) -> {noreply, #?STATE{}}.
handle_register_capable_server(Module, State) ->
    Servers0 = maps:get(node(), State#?STATE.node_to_servers, #{}),
    Servers1 = maps:put(node(), Module, Servers0),
    ets:insert(?TABLE, {{gen_server, node(), Module}, true}),
    {noreply, State#?STATE{node_to_servers = Servers1}}.

-spec handle_is_capable_server(node(), module(), #?STATE{}) -> {reply, boolean(), #?STATE{}}.
handle_is_capable_server(Node, Module, State) ->
    IsCapable =
        is_capable_node(Node) andalso
        case catch rpc:call(Node, ?MODULE, is_capable_server, [Module], 1000) of
            true  -> true;
            false -> false;
            Error ->
                error_logger:error_msg(
                  "[~p:~p] RPC failed: node=~p, module=~p, reason=~1024p\n",
                  [?MODULE, ?LINE, Node, Module, Error]),
                false
        end,
    ets:insert(?TABLE, {{gen_server, Node, Module}, IsCapable}),
    Servers = maps:put(Node, Module, State#?STATE.node_to_servers),
    {reply, IsCapable, State#?STATE{node_to_servers = Servers}}.
