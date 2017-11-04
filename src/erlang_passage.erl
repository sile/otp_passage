%% @copyright 2017 Takeru Ohta <phjgt308@gmail.com>
%%
%% @doc `erlang' module wrapper for providing tracing facility.
%%
%% The tracing facility is based on <a href="https://github.com/sile/passage">passage</a>.
-module(erlang_passage).

%%------------------------------------------------------------------------------
%% Exported API
%%------------------------------------------------------------------------------
-export([spawn/1, spawn/2, spawn/3, spawn/4]).
-export([spawn_link/1, spawn_link/2, spawn_link/3, spawn_link/4]).
-export([spawn_monitor/1, spawn_monitor/3]).
-export([spawn_opt/2, spawn_opt/3, spawn_opt/4, spawn_opt/5]).

-export_type([spawn_options/0, spawn_option/0]).

%%------------------------------------------------------------------------------
%% Exported Types
%%------------------------------------------------------------------------------
-type spawn_options() :: [spawn_option()].
%% Options for `spawn_opt' functions.

-type spawn_option() :: {span, passage:maybe_span()}
                      | {span_reference_type, passage:ref_type()}
                      | {start_span, passage:operation_name()}
                      | {start_span_options, passage:start_span_options()}
                      | (ErlangSpawnOption :: term()).
%% <ul>
%%   <li>`span': The current span. This is used as the parent span of the spawned process. The default value is `passage:maybe_span()'.</li>
%%   <li>`span_reference_type': The span reference type between the current span and the span of the spawned process. The default value is `follows_from'.</li>
%%   <li>`start_span': If this option presents, a new span will be automatically started in the spawned process.</li>
%%   <li>`start_span_options': Options for the starting span in the spawned process. If `start_span' option is absent, this will be ignored. The default value is `[]'.</li>
%%   <li>`ErlangSpawnOption': Other options defined in `erlang' module. See the description of <a href="http://erlang.org/doc/man/erlang.html#spawn_opt-4">erlang:spawn_opt/4</a> for more details.</li>
%% </ul>

%%------------------------------------------------------------------------------
%% Exported Fun
%%------------------------------------------------------------------------------
%% @equiv spawn_opt(Fun, [])
-spec spawn(function()) -> pid().
spawn(Fun) ->
    ?MODULE:spawn_opt(Fun, []).

%% @equiv spawn_opt(Node, Fun, [])
-spec spawn(node(), function()) -> pid().
spawn(Node, Fun) ->
    ?MODULE:spawn_opt(Node, Fun, []).

%% @equiv spawn_opt(Module, Function, Args, [])
-spec spawn(module(), atom(), [term()]) -> pid().
spawn(Module, Function, Args) ->
    ?MODULE:spawn_opt(Module, Function, Args, []).

%% @equiv spawn_opt(Node, Module, Function, Args, [])
-spec spawn(node(), module(), atom(), [term()]) -> pid().
spawn(Node, Module, Function, Args) ->
    ?MODULE:spawn_opt(Node, Module, Function, Args, []).

%% @equiv spawn_opt(Fun, [link])
-spec spawn_link(function()) -> pid().
spawn_link(Fun) ->
    ?MODULE:spawn_opt(Fun, [link]).

%% @equiv spawn_opt(Node, Fun, [link])
-spec spawn_link(node(), function()) -> pid().
spawn_link(Node, Fun) ->
    ?MODULE:spawn_opt(Node, Fun, [link]).

%% @equiv spawn_opt(Module, Function, Args, [link])
-spec spawn_link(module(), atom(), [term()]) -> pid().
spawn_link(Module, Function, Args) ->
    ?MODULE:spawn_opt(Module, Function, Args, [link]).

%% @equiv spawn_opt(Node, Module, Function, Args, [link])
-spec spawn_link(node(), module(), atom(), [term()]) -> pid().
spawn_link(Node, Module, Function, Args) ->
    ?MODULE:spawn_opt(Node, Module, Function, Args, [link]).

%% @equiv spawn_opt(Fun, [monitor])
-spec spawn_monitor(function()) -> {pid(), reference()}.
spawn_monitor(Fun) ->
    ?MODULE:spawn_opt(Fun, [monitor]).

%% @equiv spawn_opt(Module, Function, Args, [monitor])
-spec spawn_monitor(module(), atom(), [term()]) -> {pid(), reference()}.
spawn_monitor(Module, Function, Args) ->
    ?MODULE:spawn_opt(Module, Function, Args, [monitor]).

%% @doc The same as <a href="http://erlang.org/doc/man/erlang.html#spawn_opt-2">erlang:spawn_opt/2</a> except for propagating the current span to the spawned process.
%%
%% The propagated span is saved in the process dictionary of the spawned process.
%% So the functions of {@link passage_pd} module can be used in the process.
-spec spawn_opt(function(), spawn_options()) -> pid() | {pid(), reference()}.
spawn_opt(Fun, Options) ->
    SpawnFun = make_spawn_fun(Fun, Options),
    erlang:spawn_opt(SpawnFun, remove_passage_options(Options)).

%% @doc The same as <a href="http://erlang.org/doc/man/erlang.html#spawn_opt-3">erlang:spawn_opt/3</a> except for propagating the current span to the spawned process.
%%
%% The propagated span is saved in the process dictionary of the spawned process.
%% So the functions of {@link passage_pd} module can be used in the process.
%%
%% If `Node' has no capability to handle tracing,
%% this will switch to the ordinary `erlang:spawn_opt/3' function internally.
-spec spawn_opt(node(), function(), spawn_options()) -> pid() | {pid(), reference()}.
spawn_opt(Node, Fun, Options) ->
    SpawnFun =
        case otp_passage_capability_table:is_capable_node(Node) of
            false -> Fun;
            true  -> make_spawn_fun(Fun, Options)
        end,
    erlang:spawn_opt(Node, SpawnFun, remove_passage_options(Options)).

%% @equiv spawn_opt(fun () -> apply(Module, Function, Args) end, Options)
-spec spawn_opt(module(), atom(), [term()], spawn_options()) -> pid() | {pid(), reference()}.
spawn_opt(Module, Function, Args, Options) ->
    ?MODULE:spawn_opt(fun () -> apply(Module, Function, Args) end, Options).

%% @equiv spawn_opt(Node, fun () -> apply(Module, Function, Args) end, Options)
-spec spawn_opt(node(), module(), atom(), [term()], spawn_options()) ->
                       pid() | {pid(), reference()}.
spawn_opt(Node, Module, Function, Args, Options) ->
    ?MODULE:spawn_opt(Node, fun () -> apply(Module, Function, Args) end, Options).

%%------------------------------------------------------------------------------
%% Internal Functions
%%------------------------------------------------------------------------------
-spec make_spawn_fun(function(), spawn_options()) -> function().
make_spawn_fun(Fun, Options) ->
    RefType = proplists:get_value(span_reference_type, Options, follows_from),
    Span = proplists:get_value(span, Options, passage_pd:current_span()),
    case lists:keyfind(start_span, 1, Options) of
        false ->
            fun () ->
                    passage_pd:with_parent_span({RefType, Span}, Fun)
            end;
        {_, OperationName} ->
            StartSpanOptions = proplists:get_value(start_span_options, Options, []),
            fun () ->
                    passage_pd:with_span(
                      OperationName,
                      [{RefType, Span} | StartSpanOptions],
                      Fun)
            end
    end.

-spec remove_passage_options(spawn_options()) -> list().
remove_passage_options(Options) ->
    lists:filter(fun ({span, _})                -> false;
                     ({span_reference_type, _}) -> false;
                     ({start_span, _})          -> false;
                     ({start_span_options, _})  -> false;
                     (_)                        -> true
                 end,
                 Options).
