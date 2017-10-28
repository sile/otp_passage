%% @copyright 2017 Takeru Ohta <phjgt308@gmail.com>
-module(gen_server_passage_tests).

-include_lib("eunit/include/eunit.hrl").

%%------------------------------------------------------------------------------
%% Test Cases
%%------------------------------------------------------------------------------
basic_test() ->
    {ok, _} = application:ensure_all_started(otp_passage),

    ok = start_tracer(example_tracer),

    {ok, Pid} = gen_server_passage_example:start_link(),
    unlink(Pid),

    pong = gen_server_passage_example:ping(),
    ?assertMatch([_, _], finished_spans()),

    exit(Pid, kill),
    monitor(process, Pid),
    receive {'DOWN', _, _, Pid, _} -> ok end,
    timer:sleep(1),

    ?assertMatch([_], finished_spans()),

    ok = application:stop(otp_passage).

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
