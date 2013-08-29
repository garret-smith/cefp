
-module(timer_test).

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

handle_event(Ev, nostate) ->
  cefp:start_timer(timeout, 10),
  {event, Ev, nostate}
  .

handle_timeout(_Ref, Msg, nostate) ->
  {event, Msg, nostate}
  .

handle_call(Msg, _From, State) ->
  io:fwrite("unexpected call: ~p~n", [Msg]),
  {noreply, State}
  .
