
-module(cefp_flow).

-behaviour(cefp).

-export(
  [
    create/2,
    handle_event/2,
    handle_timeout/3,
    handle_call/3
  ]).

-record(cefp_flow_state,
  {
    flow
  }).

-define(S, cefp_flow_state).

-spec create(term(), cefp:flow()) -> cefp:rule() .
create(Name, Flow) ->
  cefp:rule(Name, ?MODULE, #?S{flow = Flow})
  .

handle_event(Ev, State = #?S{flow = Flow}) ->
  RuleEv = [{Rule,Ev} || Rule <- cefp:edges_out(start, Flow)],
  {NewFlow, Results} = cefp:rec_apply(RuleEv, Flow, []),
  {events, Results, State#?S{flow = NewFlow}}
  .

handle_timeout(_Ref, _Msg, State) ->
  {noevent, State}
  .

handle_call(Msg, _From, State) ->
  io:fwrite("unexpected call: ~p~n", [Msg]),
  {noreply, State}
  .
