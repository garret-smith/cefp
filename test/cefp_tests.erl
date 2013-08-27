
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

    P = cefp:start_link_flow(F0),

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

id_match(MatchId) ->
    fun(#reading{id = Id}) -> Id =:= MatchId end
    .

readings_avg(Readings) ->
    lists:sum([R#reading.value || R <- Readings]) / length(Readings)
    .

