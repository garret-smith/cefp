
% CEFP - complex event-flow processing

-module(cefp).

-behaviour(gen_server).

% public API
-export([
        empty_flow/0,
        new_flow/2,
        new_chain_flow/1,
        add_rule/2,
        rule/3,
        add_edge/3,
        edges_out/2,
        start_flow/1,
        start_link_flow/1,
        stop_flow/1,
        send_event/2,
        call_rule/3,
        call_nested_rule/3,
        reply/2
    ]).

%% gen_server callbacks
-export([
        init/1,
        handle_call/3,
        handle_cast/2,
        handle_info/2,
        terminate/2,
        code_change/3
    ]).

-export([
        rec_apply/3,
        timer_rule/2,
        timer_delivery/2,
        start_stop_timers/1
    ]).

-export_type([
        rule/0,
        flow/0
    ]).

-record(cefp_rule, {
        name      :: term(),
        callback  :: module(),
        state     :: term()
    }).

-record(cefp_flow, {
        rules :: orddict:orddict(), % vertices
        edges :: [{From :: term(), To :: term()}],
        timers :: [{reference(), RuleName :: term(), Value :: term()}]
    }).

-opaque rule() :: #cefp_rule{}.
-opaque flow() :: #cefp_flow{}.

-type timer_return() :: {start_timer, non_neg_integer(), term()} | {cancel_timer, term()} .
-type event_return() :: {event, term()} | {events, [term()]} .
-type state_return() :: {state, term()} .
-type callback_return() :: timer_return() | event_return() | state_return() .
-type reply_return() :: {reply, term()} .

-type from() :: {pid(), term()} .

-callback handle_event(
        Event :: term(),
        State :: term()
        ) -> [callback_return()] .
-callback handle_call(
        Call :: term(),
        From :: from(),
        State :: term()
        ) -> [reply_return() | callback_return()].
        % should a call be able to return events or timers?
-callback handle_timeout(
        TimerValue :: term(),
        State :: term()
        ) -> [callback_return()] .

%%%===================================================================
%%% Public API functions
%%%===================================================================

empty_flow() ->
    #cefp_flow{rules = orddict:new(), edges = [], timers = []}
    .

new_flow(Rules, Edges) ->
    #cefp_flow{
        rules = orddict:from_list([{Name, Rule} || Rule = #cefp_rule{name = Name} <- Rules]),
        edges = Edges,
        timers = []
    }
    .

new_chain_flow(Rules) ->
    Names = [Name || #cefp_rule{name=Name} <- Rules],
    Start = [start | lists:reverse(tl(lists:reverse(Names)))],
    Edges = lists:zip(Start, Names),
    new_flow(Rules, Edges)
    .

add_rule(Rule, Flow = #cefp_flow{rules = Rules}) ->
    Flow#cefp_flow{
        rules = orddict:append(Rule#cefp_rule.name, Rule, Rules)
    }
    .

rule(Name, CallbackModule, InitialState) ->
    #cefp_rule{name = Name, callback = CallbackModule, state = InitialState}
    .

add_edge(From, To, Flow = #cefp_flow{edges = Edges}) ->
    Flow#cefp_flow{
        edges = [{From, To} | Edges]
    }
    .

edges_out(WantFrom, #cefp_flow{edges = Edges}) ->
    [To || {From, To} <- Edges, From == WantFrom]
    .

start_flow(Flow) ->
    gen_server:start(?MODULE, [Flow], [])
    .

start_link_flow(Flow) ->
    gen_server:start_link(?MODULE, [Flow], [])
    .

stop_flow(Flow) ->
    gen_server:call(Flow, stop)
    .

send_event(Pid, Ev) ->
    gen_server:cast(Pid, {event, Ev})
    .

%% Call nested rules like [a, b, c] will call rule 'c' which is
%% inside flow 'b' which is inside flow 'a', which is running as Pid
call_nested_rule(Pid, FlowPath, Msg) ->
    Call = make_nest(lists:reverse(FlowPath), Msg),
    gen_server:call(Pid, Call)
    .

make_nest([], Msg) -> Msg;
make_nest([Rule | RuleNames], Msg) -> make_nest(RuleNames, {call, Rule, Msg}) .

call_rule(Pid, RuleName, Msg) ->
    gen_server:call(Pid, {call, RuleName, Msg})
    .


%%%===================================================================
%%% gen_server callbacks
%%%===================================================================

init([Flow]) ->
    put(rule_name, []),
    {ok, Flow}
    .

handle_call({call, RuleName, Msg}, From, Flow) ->
    try rec_apply([{RuleName, {call, From, Msg}}], Flow, []) of
        {Flow1, Results} ->
            {[], Flow2} = timer_delivery(Results, Flow1),
            {noreply, Flow2}
    catch
        throw:{rule_error, FailedRule, FailedCall, Reason} ->
            Err = {rule_error, FailedRule, FailedCall, Reason},
            {stop, Err, Err, Flow}
    end
    ;

handle_call(stop, _From, Flow) ->
    {stop, normal, ok, Flow}
    .

handle_cast({event, Ev}, Flow) ->
    RuleEv = [{Rule,Ev} || Rule <- edges_out(start, Flow)],
    try rec_apply(RuleEv, Flow, []) of
        {Flow1, Results} ->
            {[], Flow2} = timer_delivery(Results, Flow1),
            {noreply, Flow2}
    catch
        throw:{rule_error, FailedRule, FailedCall, Reason} ->
            {stop, {rule_error, FailedRule, FailedCall, Reason}, Flow}
    end
    .

handle_info({timeout, TRef, rule_timeout}, Flow) ->
    {{RuleName, Term}, Flow1} = timer_rule(TRef, Flow),
    try rec_apply([{RuleName, {rule_timeout, Term}}], Flow1, []) of
        {Flow2, Results} ->
            {[], Flow3} = timer_delivery(Results, Flow2),
            {noreply, Flow3}
    catch
        throw:{rule_error, FailedRule, FailedCall, Reason} ->
            {stop, {rule_error, FailedRule, FailedCall, Reason}, Flow1}
    end
    .

terminate(_Reason, _State) ->
    ok
    .

code_change(_OldVsn, State, _Extra) ->
    {ok, State}
    .


%%%===================================================================
%%% Internal functions
%%%===================================================================

rec_apply([], Flow, Results) ->
    {Flow, Results}
    ;
rec_apply(RuleEv, FlowGraph, PrevResults) ->
    {NextEvs, NewFlow, NewResults} = lists:foldr(
            fun rec_apply_fold/2,
            {[], FlowGraph, []},
            RuleEv),
    rec_apply(NextEvs, NewFlow, NewResults ++ PrevResults)
    .

rec_apply_fold({RuleName, Ev}, {NextEvs, Flow, Results}) ->
    {RuleReturn, NewRule} = do_call_rule(get_rule(RuleName, Flow), Ev),
    {OutEvs, OtherResults} = consolidate_events(RuleReturn),
    case edges_out(RuleName, Flow) of
        [] ->
            {NextEvs, update_rule(NewRule, Flow), OutEvs ++ OtherResults ++ Results};
        OutRules ->
            {[{OutRule, OutEv} || OutRule <- OutRules, OutEv <- OutEvs] ++ NextEvs, update_rule(NewRule, Flow), OtherResults ++ Results}
    end
    .

get_rule(RuleName, #cefp_flow{rules = Rules}) ->
    orddict:fetch(RuleName, Rules)
    .

update_rule(NewRule = #cefp_rule{name = RuleName}, Flow = #cefp_flow{rules = Rules}) ->
    Flow#cefp_flow{rules = orddict:store(RuleName, NewRule, Rules)}
    .

timer_rule(TRef, Flow = #cefp_flow{timers = Timers}) ->
    {value, {TRef, RuleName, Value}, NewTimers} = lists:keytake(TRef, 1, Timers),
    {{RuleName, Value}, Flow#cefp_flow{timers = NewTimers}}
    .

do_call_rule(R = #cefp_rule{callback = Cb, state = S}, {rule_timeout, Term}) ->
    try
        handle_rule_return({Cb:handle_timeout(Term, S), R})
    catch
        _Type:Reason -> throw({rule_error, R, {handle_timeout, [Term, S]}, Reason})
    end
    ;
do_call_rule(R = #cefp_rule{callback = Cb, state = S}, {call, From, Msg}) ->
    try
        handle_rule_return({Cb:handle_call(Msg, From, S), R}, From)
    catch
        _Type:Reason -> throw({rule_error, R, {handle_call, [Msg, From, S]}, Reason})
    end
    ;
do_call_rule(R = #cefp_rule{callback = Cb, state = S}, Ev) ->
    try
        handle_rule_return({Cb:handle_event(Ev, S), R})
    catch
        _Type:Reason -> throw({rule_error, R, {handle_event, [Ev, S]}, Reason})
    end
    .

handle_rule_return({Return, Rule}) ->
    start_stop_timers(update_rule_state({Return, Rule}))
    .

handle_rule_return({Return, Rule}, From) ->
    handle_rule_return(handle_reply({Return, Rule}, From))
    .

% Pull any {state, S} tuple out of the rule return
% and update the #cefp_rule{} record with it
update_rule_state({RuleReturn, Rule}) ->
    case lists:keytake(state, 1, RuleReturn) of
        false ->
            {RuleReturn, Rule};
        {value, {state, NewState}, RuleReturn2} ->
            {RuleReturn2, Rule#cefp_rule{state = NewState}}
    end
    .

% Pull any {reply, R} tuple out of the rule return
% and send the reply
handle_reply({RuleReturn, Rule}, From) ->
    case lists:keytake(reply, 1, RuleReturn) of
        false ->
            {RuleReturn, Rule};
        {value, {reply, Term}, RuleReturn2} ->
            reply(From, Term),
            {RuleReturn2, Rule}
    end
    .

% Split out events from other return info
consolidate_events(RuleReturn) ->
    {Events, Rest} = lists:foldr(
        fun
            ({event, E}, {Events, Remaining}) -> {[E | Events], Remaining};
            ({events, Evs}, {Events, Remaining}) -> {Evs ++ Events, Remaining};
            (Other, {Events, Remaining}) -> {Events, [Other | Remaining]}
        end,
        {[], []},
        RuleReturn),
    {Events, Rest}
    .

timer_delivery(TimerActions, F) ->
    {NewFlow, Actions} = lists:foldr(
        fun({deliver_timer, TRef, RuleName, Term}, {Flow = #cefp_flow{timers = Timers}, Evs}) ->
                {Flow#cefp_flow{timers = [{TRef, RuleName, Term} | cancel_if_running(RuleName, Term, Timers)]}, Evs};
            ({cancel_timer, Term}, {Flow = #cefp_flow{timers = Timers}, Evs}) ->
                {value, {TRef, _RuleName, Term}, NewTimers} = lists:keytake(Term, 3, Timers),
                erlang:cancel_timer(TRef),
                {Flow#cefp_flow{timers = NewTimers}, Evs};
            (Ev, {Flow, Evs}) ->
                {Flow, [Ev | Evs]}
        end,
        {F, []},
        TimerActions
    ),
    {Actions, NewFlow}
    .

cancel_if_running(RuleName, Term, Timers) ->
    case [TRef || {TRef, R, T} <- Timers, R == RuleName, T == Term] of
        [] -> Timers;
        [CancelRef] ->
            erlang:cancel_timer(CancelRef),
            {value, _, NewTimers} = lists:keytake(CancelRef, 1, Timers),
            NewTimers
    end
    .

start_stop_timers({RuleReturn, R = #cefp_rule{name = Name}}) ->
    {NewRule, NewReturn} = lists:foldr(
        fun({start_timer, Time, Term}, {Rule, Evs}) ->
                TRef = erlang:start_timer(Time, self(), rule_timeout),
                {Rule, [{deliver_timer, TRef, Name, Term} | Evs]};
            (Ev, {Rule, Evs}) ->
                {Rule, [Ev | Evs]}
        end,
        {R, []},
        RuleReturn
    ),
    {NewReturn, NewRule}
    .

reply(From, Reply) ->
    gen:reply(From, Reply)
    .

