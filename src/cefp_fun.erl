
-module(cefp_fun).

-behaviour(cefp).

%%
%% Create a rule out of funs, with a lot of flexibility
%%  * Handle only the callbacks you need
%%  * Handle state only if required
%%

-export(
  [
    create/2,
    handle_event/2,
    handle_timeout/2,
    handle_call/3
  ]).

-record(cefp_fun_state,
  {
    ev_fun,
    timeout_fun,
    call_fun,
    state
  }).

-define(S, cefp_fun_state).

-type option() :: {state, term()} | {event, fun()} | {timeout, fun()} | {call, fun()} .
-spec create(term(), [option()]) -> cefp:rule() .

create(Name, Options) ->
  S = proc_opts(Options, #?S{}),
  cefp:rule(Name, ?MODULE, S)
  .

proc_opts([], S) -> S;
proc_opts([{state, State} | Opts], S) -> proc_opts(Opts, S#?S{state = State}) ;
proc_opts([{event, Fun} | Opts], S) when is_function(Fun) -> proc_opts(Opts, S#?S{ev_fun = Fun}) ;
proc_opts([{timeout, Fun} | Opts], S) when is_function(Fun) -> proc_opts(Opts, S#?S{timeout_fun = Fun}) ;
proc_opts([{call, Fun} | Opts], S) when is_function(Fun) -> proc_opts(Opts, S#?S{call_fun = Fun}) .

handle_event(_Ev, #?S{ev_fun = EvFun}) when EvFun == undefined ->
  []
  ;
handle_event(Ev, S = #?S{ev_fun = EvFun}) when is_function(EvFun, 1) ->
  transform_state(EvFun(Ev), S)
  ;
handle_event(Ev, S = #?S{ev_fun = EvFun, state = State}) when is_function(EvFun, 2) ->
  transform_state(EvFun(Ev, State), S)
  .

handle_timeout(_Msg, #?S{timeout_fun = ToFun}) when ToFun == undefined ->
  []
  ;
handle_timeout(Msg, S = #?S{timeout_fun = ToFun}) when is_function(ToFun, 1) ->
  transform_state(ToFun(Msg), S)
  ;
handle_timeout(Msg, S = #?S{timeout_fun = ToFun, state = State}) when is_function(ToFun, 2) ->
  transform_state(ToFun(Msg, State), S)
  .

handle_call(_Msg, _From, #?S{call_fun = CallFun}) when CallFun == undefined ->
  []
  ;
handle_call(Msg, _From, S = #?S{call_fun = CallFun}) when is_function(CallFun, 1) ->
  transform_state(CallFun(Msg), S)
  ;
handle_call(Msg, _From, S = #?S{call_fun = CallFun, state = State}) when is_function(CallFun, 2) ->
  transform_state(CallFun(Msg, State), S)
  .

transform_state(Return, S) ->
  case lists:keytake(state, 1, Return) of
    false -> Return;
    {value, {state, NewState}, Rest} ->
      [{state, S#?S{state = NewState}} | Rest]
  end
  .

