%% @copyright 2017 Takeru Ohta <phjgt308@gmail.com>
%%
%% @doc `erlang' wrapper module for providing tracing facility.
%%
%% The tracing facility is based on <a href="https://github.com/sile/passage">passage</a>.
-module(erlang_passage).

%%------------------------------------------------------------------------------
%% Exported API
%%------------------------------------------------------------------------------
-export([spawn_opt/2, spawn_opt/4]).

%%------------------------------------------------------------------------------
%% Exported Fun
%%------------------------------------------------------------------------------
spawn_opt(Fun, Options) ->
    ParentSpan =
        proplists:get_value(
          parent_span, Options, {follows_from, passage_pd:current_span()}),
    erlang:spawn(
      fun () -> passage_pd:with_parent_span(ParentSpan, Fun) end).

spawn_opt(Module, Function, Args, Options) ->
    ?MODULE:spawn_opt(fun () -> apply(Module, Function, Args) end, Options).
