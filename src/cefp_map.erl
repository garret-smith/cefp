
-module(cefp_map).

-behaviour(cefp).

-export(
  [
    create/2,
    handle_event/2,
    handle_timeout/2,
    handle_call/3
  ]).

-spec create(term(), fun((term()) -> term())) -> cefp:rule() .
create(Name, EvFun) when is_function(EvFun, 1) ->
  cefp:rule(Name, ?MODULE, EvFun)
  .

handle_event(Ev, EvFun) ->
  NewEv = EvFun(Ev),
  [{event, NewEv}]
  .

handle_timeout(_Msg, _State) ->
  []
  .

handle_call(Msg, _From, _State) ->
  io:fwrite("unexpected call: ~p~n", [Msg]),
  []
  .
