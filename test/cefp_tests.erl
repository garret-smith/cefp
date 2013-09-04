
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
    ?assertEqual(3.0, Val),

    unlink(P),
    ok = cefp:stop_flow(P)
    .

timer_test() ->
    Self = self(),

    F0 = cefp:new_flow(
        [
            test_rule:create(timer_test),
            cefp_sink:create(sink, fun(Ev) -> Self ! Ev end)
        ],
        [{start, timer_test}, {timer_test, sink}]
    ),

    {ok, P} = cefp:start_link_flow(F0),

    cefp:send_event(P, ev1),

    M = next_msg(100),

    ?assertEqual(ev1, M),

    timer:sleep(10),

    M2 = next_msg(100),

    ?assertEqual(timeout, M2),

    unlink(P),
    ok = cefp:stop_flow(P)
    .

call_test() ->
    Self = self(),

    F0 = cefp:new_flow(
        [
            test_rule:create(call_test),
            cefp_sink:create(sink, fun(Ev) -> Self ! Ev end)
        ],
        [{start, call_test}, {call_test, sink}]
    ),

    {ok, P} = cefp:start_link_flow(F0),

    ?assertEqual(nostate, cefp:call_rule(P, call_test, newstate)),
    timer:sleep(1),
    ?assertEqual(newstate, cefp:call_rule(P, call_test, nostate)),

    N1 = next_msg(100),
    ?assertEqual(newstate, N1),
    N2 = next_msg(100),
    ?assertEqual(nostate, N2),

    N3 = next_msg(100),
    ?assertEqual({call, newstate}, N3),
    N4 = next_msg(100),
    ?assertEqual({call, nostate}, N4),

    unlink(P),
    ok = cefp:stop_flow(P)
    .

nested_flow_test() ->
    Self = self(),

    F0 = cefp:new_flow(
        [
            cefp_map:create(map_times, fun(X) -> X * 2 end),
            cefp_map:create(map_plus, fun(X) -> X + 3 end)
        ],
        [{start, map_times}, {map_times, map_plus}]
    ),

    F1 = cefp:new_flow(
        [
            cefp_map:create(map_plus, fun(X) -> X + 1 end),
            cefp_flow:create(nested, F0),
            cefp_map:create(map_times, fun(X) -> X * 2 end),
            cefp_sink:create(sink, fun(Ev) -> Self ! Ev end)
        ],
        [{start, map_plus}, {map_plus, nested}, {nested, map_times}, {map_times, sink}]
    ),

    {ok, P} = cefp:start_link_flow(F1),

    cefp:send_event(P, 1),

    N = next_msg(100),

    ?assertEqual(14, N),

    unlink(P),
    ok = cefp:stop_flow(P)
    .

rule_fail_test() ->
    F0 = cefp:new_chain_flow([
        cefp_map:create(should_fail, fun(X) -> X + a end)
    ]),
    {ok, P} = cefp:start_flow(F0),
    Mref = monitor(process, P),
    cefp:send_event(P, 1),

    Died = receive
        {'DOWN', Mref, process, P, _Reason} -> dead
    after
        1000 -> alive
    end,

    ?assertEqual(dead, Died)
    .

nested_timer_test() ->
    Self = self(),

    F0 = cefp:new_chain_flow([
        test_rule:create(timer_test)
    ]),

    F1 = cefp:new_chain_flow([
        cefp_flow:create(nested, F0),
        cefp_sink:create(sink, fun(Ev) -> Self ! Ev end)
    ]),

    {ok, P} = cefp:start_flow(F1),

    cefp:send_event(P, 1),

    N = next_msg(100),

    ?assertEqual(1, N),

    N2 = next_msg(100),

    ?assertEqual(timeout, N2),

    ok = cefp:stop_flow(P)
    .

call_nested_rule_test() ->
    Self = self(),

    F0 = cefp:new_chain_flow([
        test_rule:create(c)
    ]),

    F1 = cefp:new_chain_flow([
        cefp_flow:create(b, F0)
    ]),

    F2 = cefp:new_chain_flow([
        cefp_flow:create(a, F1),
        cefp_sink:create(sink, fun(Ev) -> Self ! Ev end)
    ]),

    {ok, P} = cefp:start_flow(F2),

    ?assertEqual(nostate, cefp:call_nested_rule(P, [a, b, c], newstate)),
    timer:sleep(1),
    ?assertEqual(newstate, cefp:call_nested_rule(P, [a, b, c], nostate)),

    %% Not really part of the test, but these asserts
    %% just exercise more of the nesting internals,
    %% and the handle_call can return events and timers
    N1 = next_msg(100),
    ?assertEqual(newstate, N1),
    N2 = next_msg(100),
    ?assertEqual(nostate, N2),

    N3 = next_msg(100),
    ?assertEqual({call, newstate}, N3),
    N4 = next_msg(100),
    ?assertEqual({call, nostate}, N4),

    ok = cefp:stop_flow(P)
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

