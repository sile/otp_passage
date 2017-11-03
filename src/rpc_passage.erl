%% @copyright 2017 Takeru Ohta <phjgt308@gmail.com>
%%
%% @doc `rpc' module wrapper for providing tracing facility.
%%
%% The tracing facility is based on <a href="https://github.com/sile/passage">passage</a>.
-module(rpc_passage).

%%------------------------------------------------------------------------------
%% Exported API
%%------------------------------------------------------------------------------
-export([call/4, call/5]).

%%------------------------------------------------------------------------------
%% Application Internal API
%%------------------------------------------------------------------------------
-export([call_trampoline/4]).

%%------------------------------------------------------------------------------
%% Exported Function
%%------------------------------------------------------------------------------
%% @doc The same as <a href="http://erlang.org/doc/man/rpc.html#call-4">rpc:call/4</a> except for propagating the current span to the spawned process.
%%
%% The propagated span is saved in the process dictionary of the RPC executing process.
%% So the functions of {@link passage_pd} module can be used in the process.
-spec call(node(), module(), atom(), [term()]) -> Res | {badrpc, Reason} when
      Res :: term(),
      Reason :: term().
call(Node, Module, Function, Args) ->
    Span = passage_pd:current_span(),
    rpc:call(Node, ?MODULE, call_trampoline, [Span, Module, Function, Args]).

%% @doc The same as <a href="http://erlang.org/doc/man/rpc.html#call-5">rpc:call/5</a> except for propagating the current span to the spawned process.
%%
%% The propagated span is saved in the process dictionary of the RPC executing process.
%% So the functions of {@link passage_pd} module can be used in the process.
-spec call(node(), module(), atom(), [term()], timeout()) -> Res | {badrpc, Reason} when
      Res :: term(),
      Reason :: term().
call(Node, Module, Function, Args, Timeout) ->
    Span = passage_pd:current_span(),
    rpc:call(Node, ?MODULE, call_trampoline, [Span, Module, Function, Args], Timeout).

%%------------------------------------------------------------------------------
%% Application Internal Function
%%------------------------------------------------------------------------------
%% @private
-spec call_trampoline(passage:maybe_span(), module(), atom(), [term()])->
    term() | {badrpc, term()}.
call_trampoline(Span, Module, Function, Args) ->
    passage_pd:with_parent_span(
      {child_of, Span},
      fun () -> apply(Module, Function,Args) end).
