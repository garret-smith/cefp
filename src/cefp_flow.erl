
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
  [{state, State#?S{flow = Flow1}} | rewrite_actions(Results, Name)]
  .

handle_timeout(_Msg = {Rule, Term}, State = #?S{name = Name, flow = Flow}) ->
  {Flow1, Results} = cefp:rec_apply([{Rule, {rule_timeout, Term}}], Flow, []),
  [{state, State#?S{flow = Flow1}} | rewrite_actions(Results, Name)]
  .

handle_call({call, RuleName, Msg}, From, State = #?S{name = Name, flow = Flow}) ->
  {Flow1, Results} = cefp:rec_apply([{RuleName, {call, From, Msg}}], Flow, []),
  [{state, State#?S{flow = Flow1}} | rewrite_actions(Results, Name)]
  .

rewrite_actions(Actions, MyName) ->
  % Results could have {deliver_timer, TRef, RuleName, Term} and {cancel_timer, RuleName, Term} directives
  UpdatedTimerActions = lists:map(
      fun
        ({deliver_timer, TRef, Rule, Term}) -> {deliver_timer, TRef, MyName, {Rule, Term}};
        ({cancel_timer, Rule, Term}) -> {cancel_timer, MyName, {Rule, Term}};
%        ({event, E}) -> {event, E};
%        ({events, E}) -> {events, E};
        (E) -> {event, E}
      end,
      Actions),
  UpdatedTimerActions
  .

