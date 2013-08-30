
-module(cefp_sink).

-behaviour(cefp).

-export(
  [ create/2,
    handle_event/2,
    handle_timeout/3,
    handle_call/3
  ]).

-spec create(term(), fun((cefp:event()) -> term())) -> cefp:rule() .
create(Name, EvFun) when is_function(EvFun, 1) ->
  cefp:rule(Name, ?MODULE, EvFun)
  .

handle_event(Ev, EvFun) when is_function(EvFun, 1) ->
  EvData = cefp:event_data(Ev),
  EvFun(EvData),
  {noevent, EvFun}
  .

handle_timeout(_Ref, _Msg, State) ->
  {noevent, State}
  .

handle_call(Msg, _From, State) ->
  io:fwrite("unexpected call: ~p~n", [Msg]),
  {noreply, State}
  .

