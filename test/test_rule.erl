
-module(test_rule).

-behaviour(cefp).

-export(
  [
    create/1,
    handle_event/2,
    handle_timeout/3,
    handle_call/3
  ]).

create(Name) ->
  cefp:rule(Name, ?MODULE, nostate)
  .

handle_event(Ev, State) ->
  cefp:start_timer(timeout, 10),
  {event, Ev, State}
  .

handle_timeout(_Ref, Msg, State) ->
  {event, Msg, State}
  .

handle_call(Msg, _From, State) ->
  {reply, State, Msg}
  .
