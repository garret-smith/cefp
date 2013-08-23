
-module(cefp_tests).

-include_lib("eunit/include/eunit.hrl").

-export(
    [ readings_avg/1
    , runner/1
    ]).

-record(reading,
    { id
    , value
    }).


sliding_window_test() ->
    F = cefp:sliding_window
        ( id_match(1)
        , reply_avg()
        , 3
        )

    , P = spawn(fun() -> runner(F) end)

    , P ! #reading{id  = 2, value = 3}
    , P ! #reading{id  = 2, value = 3}
    , P ! #reading{id  = 1, value = 3}
    , P ! #reading{id  = 1, value = 3}
    , P ! #reading{id  = 2, value = 3}

    , Nada = receive {avg, V} -> V after 10 -> nada end

    , P ! #reading{id  = 1, value = 3}

    , Val = receive {avg, V1} -> V1 after 10 -> nada end

    , ?assertEqual(nada, Nada)
    , ?assertEqual(3.0, Val)
    .

id_match(MatchId) ->
    fun(#reading{id = Id}) -> Id =:= MatchId end
    .

readings_avg(Readings) ->
    lists:sum([R#reading.value || R <- Readings]) / length(Readings)
    .

reply_avg() ->
    Self = self()
    , fun(Readings) -> Self ! {avg, lists:sum([R#reading.value || R <- Readings]) / length(Readings)} end
    .

runner({Fun, State}) ->
    receive
        quit ->
            quit;
        Ev ->
            case Fun(Ev, State) of
                {ok, NewState} ->
                    runner({Fun, NewState});
                {value, V, NewState} ->
                    io:fwrite("~p~n", [V]),
                    runner({Fun, NewState})
            end
    end
    .


