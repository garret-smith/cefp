
-module(cefp_sliding_window).

-behaviour(cefp).

-export([
  create/4,
  handle_event/2,
  handle_timeout/3,
  handle_call/3
  ]).

-record(cefp_sliding_window_state, {
    window_data,
    window_size,
    pred_fun,
    agg_fun
    }).

-define(S, cefp_sliding_window_state).

-spec create(term(), non_neg_integer(), fun((cefp:cefp_event()) -> boolean()), fun(([term()]) -> term())) -> cefp:cefp_rule() .
create(Name, WindowSize, PredFun, AggFun)
    when is_function(PredFun, 1), is_function(AggFun, 1) ->
  cefp:rule(Name, ?MODULE, #?S{
      window_data = queue:new(),
      window_size = WindowSize,
      pred_fun = PredFun,
      agg_fun = AggFun
    }
  )
  .

handle_event(Ev, State = #?S{pred_fun = PredFun, agg_fun = AggFun, window_size = WinSz, window_data = Data}) ->
  EvData = cefp:event_data(Ev),
  case PredFun(EvData) of
    true ->
      NewWindow = insert_trunc(EvData, Data, WinSz),
      case queue:len(NewWindow) == WinSz of
        true -> {event, AggFun(queue:to_list(NewWindow)), State#?S{window_data = NewWindow}};
        false -> {noevent, State#?S{window_data = NewWindow}}
      end;
    false ->
      {noevent, State}
  end
  .

handle_timeout(_Ref, _Msg, State) ->
  {noevent, State}
  .

handle_call(Msg, _From, State) ->
  io:fwrite("unexpected call: ~p~n", [Msg]),
  {noreply, State}
  .

insert_trunc(Ev, Q, Sz) ->
    Q1 = queue:in(Ev, Q),
    case queue:len(Q1) > Sz of
        true -> {{value, _}, Q2} = queue:out(Q1), Q2;
        false -> Q1
    end
    .

