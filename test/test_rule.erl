
-module(test_rule).

-behaviour(cefp).

-export(
  [
    create/1,
    handle_event/2,
    handle_timeout/2,
    handle_call/3
  ]).

create(Name) ->
  cefp:rule(Name, ?MODULE, nostate)
  .

handle_event(Ev, _State) ->
  [{event, Ev},{start_timer, 50, timeout}]
  .

handle_timeout(Msg, _State) ->
  [{event, Msg}]
  .

handle_call(Msg, _From, State) ->
  [{reply, State}, {state, Msg}, {event, Msg}, {start_timer, 50, {call, Msg}}]
  .
