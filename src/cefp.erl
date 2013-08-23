
% CEFP - complex event flow processing
-module(cefp).


-export([
        sliding_window/3
    ]).


sliding_window(Pred, Reduce, WindowSz) ->
    F = fun(Ev, Q) ->
            case Pred(Ev) of
                true ->
                    Q2 = queue_fill_sz(Q, Ev, WindowSz),
                    case queue:len(Q2) == WindowSz of
                        true -> {value, Reduce(queue:to_list(Q2)), Q2}
                        ; false -> {ok, Q2}
                    end
                ; false ->
                    {ok, Q}
            end
    end
    , {F, queue:new()}
    .

queue_fill_sz(Q, Ev, Sz) ->
    Q1 = queue:in(Ev, Q)
    , case queue:len(Q1) > Sz of
        true -> {{value, _}, Q2} = queue:out(Q1), Q2
        ; false -> Q1
    end
    .

