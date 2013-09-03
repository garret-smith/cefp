
-module(cefp_flow).

-behaviour(cefp).

-export(
  [
    create/2,
    handle_event/2,
    handle_timeout/2,
    handle_call/3
  ]).

-record(cefp_flow_state,
  {
    name,
    flow
  }).

-define(S, cefp_flow_state).

-spec create(term(), cefp:flow()) -> cefp:rule() .
create(Name, Flow) ->
  cefp:rule(Name, ?MODULE, #?S{name = Name, flow = Flow})
  .

handle_event(Ev, State = #?S{name = Name, flow = Flow}) ->
  RuleEv = [{Rule,Ev} || Rule <- cefp:edges_out(start, Flow)],
  {Flow1, Results} = cefp:rec_apply(RuleEv, Flow, []),
  {TimerActions, Events} = lists:partition(
      fun
        ({deliver_timer, _, _}) -> true;
        ({undeliver_timer, _, _}) -> true;
        (_) -> false
      end,
      Results),
  {[], Flow2} = cefp:timer_delivery(TimerActions, Flow1),
  UpdatedTimerActions = lists:map(
      fun
        ({deliver_timer, TRef, _}) -> {deliver_timer, TRef, Name};
        ({undeliver_timer, TRef, _}) -> {undeliver_timer, TRef, Name}
      end,
      TimerActions),
  io:fwrite("updated: ~p~n", [UpdatedTimerActions]),
  [{events, Events}, {state, State#?S{flow = Flow2}}] ++ UpdatedTimerActions
  .

handle_timeout(Msg, _State) ->
  io:fwrite("cefp_flow timer: ~p~n", [Msg]),
  []
  .

handle_call(Msg, _From, _State) ->
  io:fwrite("unexpected call: ~p~n", [Msg]),
  []
  .

