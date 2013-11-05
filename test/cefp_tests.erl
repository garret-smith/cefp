
-module(cefp_tests).

-include_lib("eunit/include/eunit.hrl").

edges_out_test() ->
    Self = self(),

    F0 = cefp:new_flow(
        [
            cefp_window:create(
                sw,
                3,
                fun(Id) -> Id =:= 1 end,
                fun(Readings) -> lists:sum(Readings) / length(Readings) end,
                slide
            ),
            cefp_sink:create(sink, fun(Ev) -> Self ! Ev end)
        ],
        [{start, sw}, {sw, sink}]
    ),
    ?assertMatch([sw], cefp:edges_out(start, F0)),
    ?assertMatch([sink], cefp:edges_out(sw, F0))
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

multipath_test() ->
    Self = self(),

    F0 = cefp:new_flow(
            [
                cefp_map:create(map_times, fun(X) -> X * 2 end),
                cefp_map:create(map_plus1, fun(X) -> X + 1 end),
                cefp_map:create(map_plus2, fun(X) -> X + 2 end),
                cefp_sink:create(deliver, fun(X) -> Self ! X end)
            ],
            [{start, map_times}, {map_times, map_plus1}, {map_times, map_plus2}, {map_plus1, deliver}, {map_plus2, deliver}]
        ),

    {ok, P} = cefp:start_link_flow(F0),
    cefp:send_event(P, 1),

    ?assertEqual(4, next_msg(100)),
    ?assertEqual(3, next_msg(100)),

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

redirect_flow_test() ->
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
    ?assertEqual(14, next_msg(100)),

    ok = cefp:redirect_flow(P, fun(Flow) ->
                Fl1 = cefp:remove_edge(map_times, sink, Flow),
                Fl2 = cefp:add_rule(cefp_map:create(map_plusagain, fun(X) -> X + 1 end), Fl1),
                Fl3 = cefp:add_edge(map_times, map_plusagain, Fl2),
                Fl4 = cefp:add_edge(map_plusagain, sink, Fl3),
                Fl4
        end),

    cefp:send_event(P, 1),
    ?assertEqual(15, next_msg(100)),

    unlink(P),
    ok = cefp:stop_flow(P)
    .

deep_nest_test() ->
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
            cefp_map:create(map_times, fun(X) -> X * 2 end)
        ],
        [{start, map_plus}, {map_plus, nested}, {nested, map_times}]
    ),

    F2 = cefp:new_flow(
        [
            cefp_flow:create(nested, F1),
            cefp_map:create(map_plus, fun(X) -> X + 1 end),
            cefp_sink:create(sink, fun(Ev) -> Self ! Ev end)
        ],
        [{start, nested}, {nested, map_plus}, {map_plus, sink}]
    ),

    {ok, P} = cefp:start_link_flow(F2),

    cefp:send_event(P, 1),

    N = next_msg(100),

    ?assertEqual(15, N),

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

    FS = cefp:snapshot(P),
    ?assertEqual([], cefp:timers(FS)),

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
    %% just exercise more of the nesting internals like
    %% handle_call can return events and timers
    N1 = next_msg(100),
    ?assertEqual(newstate, N1),
    N2 = next_msg(100),
    ?assertEqual(nostate, N2),

    N3 = next_msg(100),
    ?assertEqual({call, newstate}, N3),
    N4 = next_msg(100),
    ?assertEqual({call, nostate}, N4),

    FS = cefp:snapshot(P),
    ?assertEqual([], cefp:timers(FS)),

    ok = cefp:stop_flow(P)
    .

reset_timer_test() ->
    % move a pending timer further into the future
    Self = self(),

    T = 1000,
    Wait = 800,

    F0 = cefp:new_chain_flow([
        cefp_fun:create(a, [
            {timeout, fun(Ev) -> Self ! Ev, [{start_timer, T, timeout}] end},
            {event, fun
                    (start) -> [{start_timer, T, timeout}];
                    (stop) -> [{cancel_timer, timeout}]
                end
            }
        ])
    ]),

    {ok, P} = cefp:start_flow(F0),

    cefp:send_event(P, start),

    timer:sleep(Wait),

    cefp:send_event(P, start),

    ?assertEqual(nada, next_msg(Wait)),

    cefp:send_event(P, start),

    ?assertEqual(nada, next_msg(Wait)),

    cefp:send_event(P, stop),

    ?assertEqual(nada, next_msg(Wait)),

    FS = cefp:snapshot(P),
    ?assertEqual([], cefp:timers(FS)),

    ok = cefp:stop_flow(P)
    .

reset_nested_timer_test() ->
    % move a pending timer further into the future
    Self = self(),

    T = 1000,
    Wait = 800,

    F0 = cefp:new_chain_flow([
        cefp_fun:create(a, [
            {timeout, fun(Ev) -> Self ! Ev, [{start_timer, T, timeout}] end},
            {event, fun
                    (start) -> [{start_timer, T, timeout}];
                    (stop) -> [{cancel_timer, timeout}]
                end
            }
        ])
    ]),

    F1 = cefp:new_chain_flow([
        cefp_flow:create(b, F0)
    ]),

    {ok, P} = cefp:start_flow(F1),

    cefp:send_event(P, start),

    timer:sleep(Wait),

    cefp:send_event(P, start),

    ?assertEqual(nada, next_msg(Wait)),

    cefp:send_event(P, start),

    ?assertEqual(nada, next_msg(Wait)),

    cefp:send_event(P, stop),

    ?assertEqual(nada, next_msg(Wait)),

    FS = cefp:snapshot(P),
    ?assertEqual([], cefp:timers(FS)),

    ok = cefp:stop_flow(P)
    .

chained_timer_cancel_test() ->
    % timeouts schedule more timers
    Self = self(),

    T = 10,

    F = cefp:new_chain_flow([
        cefp_fun:create(a, [
            {timeout, fun(Ev) -> Self ! Ev, [{start_timer, T, timeout}] end},
            {event, fun
                    (start) -> [{start_timer, T, timeout}];
                    (stop) -> [{cancel_timer, timeout}]
                end
            }
        ])
    ]),

    {ok, P} = cefp:start_flow(F),

    cefp:send_event(P, start),

    timer:sleep(T),

    ?assertEqual(timeout, next_msg(2*T)),
    ?assertEqual(timeout, next_msg(2*T)),
    ?assertEqual(timeout, next_msg(2*T)),

    cefp:send_event(P, stop),

    ?assertEqual(nada, next_msg(4*T)),

    ok = cefp:stop_flow(P)
    .

timer_spacing_test() ->
    Self = self(),

    T = 5,

    F = cefp:new_chain_flow([
        cefp_fun:create(a, [
            {timeout, fun(_) -> Self ! os:timestamp(), [{start_timer, T, timeout}] end},
            {event, fun
                    (start) -> [{start_timer, T, timeout}];
                    (stop) -> [{cancel_timer, timeout}]
                end
            }
        ])
    ]),

    {ok, P} = cefp:start_flow(F),

    cefp:send_event(P, start),

    FirstT = next_msg(2*T),

    Spacings = timer_spacing(FirstT, [], 10),

    ?debugFmt("T: ~p, timer spacings: ~p", [T, Spacings]),
    Jitter = [S - (T * 1000) || S <- Spacings],

    ?debugFmt("timer jitter: ~p", [Jitter]),

    ok = cefp:stop_flow(P)
    .

proc_timer_test() ->
    Self = self(),
    T = 0,

    P = spawn(fun() -> timer_looper(Self, T) end),

    FirstT = next_msg(2*T + 5),
    Spacings = timer_spacing(FirstT, [], 10),
    ?debugFmt("T: ~p, timer spacings: ~p", [T, Spacings]),
    Jitter = [S - (T * 1000) || S <- Spacings],

    ?debugFmt("timer jitter: ~p", [Jitter]),

    P ! stop
    .

timer_looper(SendTo, T) ->
    SendTo ! os:timestamp(),
    erlang:send_after(T, self(), timeout),
    receive
        timeout ->
            timer_looper(SendTo, T);
        stop ->
            ok
    end
    .

timer_spacing(_, Diffs, 0) ->
    Diffs;
timer_spacing(PrevTime, Diffs, N) ->
    T = next_msg(1000),
    Diff = timer:now_diff(T, PrevTime),
    timer_spacing(T, [Diff | Diffs], N-1)
    .

next_msg(Timeout) ->
    receive X -> X after Timeout -> nada end
    .

