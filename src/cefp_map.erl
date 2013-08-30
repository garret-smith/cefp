
-module(cefp_map).

-behaviour(cefp).

-export(
  [
    create/2,
    handle_event/2,
    handle_timeout/3,
    handle_call/3
  ]).

-record(cefp_map_state,
  {
    ev_map
  }).

-define(S, cefp_map_state).

-spec create(term(), fun((cefp:event()) -> {event, term()})) -> cefp:rule() .
create(Name, EvFun) when is_function(EvFun, 1) ->
  cefp:rule(Name, ?MODULE, #?S{ev_map = EvFun})
  .

handle_event(Ev, State = #?S{ev_map = EvFun}) ->
  NewEv = EvFun(cefp:event_data(Ev)),
  {event, NewEv, State}
  .

handle_timeout(_Ref, _Msg, State) ->
  {noevent, State}
  .

handle_call(Msg, _From, State) ->
  io:fwrite("unexpected call: ~p~n", [Msg]),
  {noreply, State}
  .
