
-module(cefp_window_test).

-include_lib("eunit/include/eunit.hrl").

-record(reading,
    {
        id,
        value
    }).

sliding_window_test() ->
    Self = self(),

    F0 = cefp:new_flow(
        [
            cefp_window:create(
                sw,
                3,
                fun(#reading{id = Id}) -> Id =:= 1 end,
                fun(Readings) -> lists:sum([R#reading.value || R <- Readings]) / length(Readings) end,
                slide
            ),
            cefp_sink:create(sink, fun(Ev) -> Self ! Ev end)
        ],
        [{start, sw}, {sw, sink}]
    ),

    {ok, P} = cefp:start_link_flow(F0),

    cefp:send_event(P, #reading{id  = 2, value = 3}),
    cefp:send_event(P, #reading{id  = 2, value = 3}),
    cefp:send_event(P, #reading{id  = 1, value = 3}),
    cefp:send_event(P, #reading{id  = 1, value = 3}),
    cefp:send_event(P, #reading{id  = 2, value = 3}),

    ?assertEqual(nada, next_msg(10)),

    cefp:send_event(P, #reading{id  = 1, value = 3}),
    ?assertEqual(3.0, next_msg(10)),

    cefp:send_event(P, #reading{id  = 1, value = 4}),
    cefp:send_event(P, #reading{id  = 2, value = 5}),
    ?assertEqual(3.3333333333333333, next_msg(10)),

    unlink(P),
    ok = cefp:stop_flow(P),

    next_msg(0)
    .

tumbling_window_test() ->
    Self = self(),

    F0 = cefp:new_flow(
        [
            cefp_window:create(
                sw,
                3,
                fun(#reading{id = Id}) -> Id =:= 1 end,
                fun(Readings) -> lists:sum([R#reading.value || R <- Readings]) / length(Readings) end,
                tumble
            ),
            cefp_sink:create(sink, fun(Ev) -> Self ! Ev end)
        ],
        [{start, sw}, {sw, sink}]
    ),

    {ok, P} = cefp:start_link_flow(F0),

    cefp:send_event(P, #reading{id  = 2, value = 3}),
    cefp:send_event(P, #reading{id  = 2, value = 3}),
    cefp:send_event(P, #reading{id  = 1, value = 3}),
    cefp:send_event(P, #reading{id  = 1, value = 3}),
    cefp:send_event(P, #reading{id  = 2, value = 3}),

    ?assertEqual(nada, next_msg(10)),

    cefp:send_event(P, #reading{id  = 1, value = 3}),
    ?assertEqual(3.0, next_msg(10)),

    cefp:send_event(P, #reading{id  = 1, value = 4}),
    cefp:send_event(P, #reading{id  = 2, value = 4}),
    ?assertEqual(nada, next_msg(10)),

    cefp:send_event(P, #reading{id  = 1, value = 4}),
    cefp:send_event(P, #reading{id  = 2, value = 40}),
    cefp:send_event(P, #reading{id  = 1, value = 40}),

    ?assertEqual(16.0, next_msg(10)),

    unlink(P),
    ok = cefp:stop_flow(P),

    next_msg(0)
    .

next_msg(Timeout) ->
    receive X -> X after Timeout -> nada end
    .
