
-module(cefp_tests).

-include_lib("eunit/include/eunit.hrl").

-export(
    [
        readings_avg/1
    ]).

-record(reading,
    {
        id,
        value
    }).

edges_out_test() ->
    Self = self(),

    F0 = cefp:new_flow(
        [
            cefp_sliding_window:create(
                sw,
                3,
                id_match(1),
                fun(Readings) -> lists:sum([R#reading.value || R <- Readings]) / length(Readings) end
            ),
            cefp_sink:create(sink, fun(Ev) -> Self ! Ev end)
        ],
        [{start, sw}, {sw, sink}]
    ),
    ?assertMatch([sw], cefp:edges_out(start, F0)),
    ?assertMatch([sink], cefp:edges_out(sw, F0))
    .

sliding_window_test() ->
    Self = self(),

    F0 = cefp:new_flow(
        [
            cefp_sliding_window:create(
                sw,
                3,
                id_match(1),
                fun(Readings) -> lists:sum([R#reading.value || R <- Readings]) / length(Readings) end
            ),
            cefp_sink:create(sink, fun(Ev) -> Self ! {avg, Ev} end)
        ],
        [{start, sw}, {sw, sink}]
    ),

    {ok, P} = cefp:start_link_flow(F0),

    cefp:send_event(P, #reading{id  = 2, value = 3}),
    cefp:send_event(P, #reading{id  = 2, value = 3}),
    cefp:send_event(P, #reading{id  = 1, value = 3}),
    cefp:send_event(P, #reading{id  = 1, value = 3}),
    cefp:send_event(P, #reading{id  = 2, value = 3}),

    Nada = receive {avg, V} -> V after 10 -> nada end,

    cefp:send_event(P, #reading{id  = 1, value = 3}),

    Val = receive {avg, V1} -> V1 after 10 -> nada end,

    ?assertEqual(nada, Nada),
    ?assertEqual(3.0, Val)
    .

timer_test() ->
    Self = self(),

    F0 = cefp:new_flow(
        [
            test_rule:create(timer_test),
            cefp_sink:create(sink, fun(Ev) -> io:fwrite("~p", [Ev]), Self ! Ev end)
        ],
        [{start, timer_test}, {timer_test, sink}]
    ),

    {ok, P} = cefp:start_link_flow(F0),

    cefp:send_event(P, ev1),

    M = next_msg(1000),

    ?assertEqual(ev1, M),

    timer:sleep(1000),

    M2 = next_msg(1000),

    ?assertEqual(timeout, M2)
    .

call_test() ->
    Self = self(),

    F0 = cefp:new_flow(
        [
            test_rule:create(call_test),
            cefp_sink:create(sink, fun(Ev) -> io:fwrite("~p", [Ev]), Self ! Ev end)
        ],
        [{start, call_test}, {call_test, sink}]
    ),

    {ok, P} = cefp:start_link_flow(F0),

    ?assertEqual(nostate, cefp:call_rule(P, call_test, newstate)),
    ?assertEqual(newstate, cefp:call_rule(P, call_test, nostate))
    .

next_msg(Timeout) ->
    receive X -> X after Timeout -> nada end
    .

id_match(MatchId) ->
    fun(#reading{id = Id}) -> Id =:= MatchId end
    .

readings_avg(Readings) ->
    lists:sum([R#reading.value || R <- Readings]) / length(Readings)
    .

