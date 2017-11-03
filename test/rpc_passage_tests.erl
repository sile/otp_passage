%% @copyright 2017 Takeru Ohta <phjgt308@gmail.com>
-module(rpc_passage_tests).

-include_lib("eunit/include/eunit.hrl").

%%------------------------------------------------------------------------------
%% Test Cases
%%------------------------------------------------------------------------------
basic_test_() ->
    {foreach,
     fun () -> {ok, Apps} = application:ensure_all_started(otp_passage), Apps end,
     fun (Apps) -> lists:foreach(fun application:stop/1, Apps) end,
     [fun () ->
              ok = start_tracer(example_tracer),
              passage_pd:with_span(
                root, [{tracer, example_tracer}],
                fun () ->
                        rpc_passage:call(node(), passage_pd, with_span,
                                         [child, fun () -> ok end])
                end),
              timer:sleep(10),
              ?assertMatch([_, _], finished_spans())
      end]}.

%%------------------------------------------------------------------------------
%% Internal Functions
%%------------------------------------------------------------------------------
-spec start_tracer(passage:tracer_id()) -> ok.
start_tracer(TracerId) ->
    Context = passage_span_context_null,
    Sampler = passage_sampler_all:new(),
    Reporter = passage_reporter_process:new(self(), span),
    ok = passage_tracer_registry:register(TracerId, Context, Sampler, Reporter).

-spec finished_spans() -> [passage_span:span()].
finished_spans() ->
    receive
        {span, Span} -> [Span] ++ finished_spans()
    after 0 ->
            []
    end.
