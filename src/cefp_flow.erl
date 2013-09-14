
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
  {UpdatedActions, Flow2} = apply_actions(Results, Flow1, Name),
  [{state, State#?S{flow = Flow2}} | UpdatedActions]
  .

handle_timeout(Msg, State = #?S{name = Name, flow = Flow}) ->
  {{RuleName, Term}, Flow1} = cefp:timer_rule(Msg, Flow),
  {Flow2, Results} = cefp:rec_apply([{RuleName, {rule_timeout, Term}}], Flow1, []),
  {UpdatedActions, Flow3} = apply_actions(Results, Flow2, Name),
  [{state, State#?S{flow = Flow3}} | UpdatedActions]
  .

handle_call({call, RuleName, Msg}, From, State = #?S{name = Name, flow = Flow}) ->
  {Flow1, Results} = cefp:rec_apply([{RuleName, {call, From, Msg}}], Flow, []),
  {UpdatedActions, Flow2} = apply_actions(Results, Flow1, Name),
  [{state, State#?S{flow = Flow2}} | UpdatedActions]
  .

apply_actions(Actions, Flow, MyName) ->
  % Results could have {deliver_timer, TRef, RuleName, Term} and {cancel_timer, RuleName, Term} directives
  {TimerActions, Events} = lists:partition(
      fun
        ({deliver_timer, _, _, _}) -> true;
        ({cancel_timer, _, _}) -> true;
        (_) -> false
      end,
      Actions),
  UpdatedTimerActions = lists:map(
      fun
        ({deliver_timer, TRef, _, _Term}) -> {deliver_timer, TRef, MyName, TRef};
        ({cancel_timer, _, Term}) -> {cancel_timer, MyName, Term}
      end,
      TimerActions),
  {[], Flow1} = cefp:timer_delivery(TimerActions, Flow),
  {[{events, Events} | UpdatedTimerActions], Flow1}
  .

