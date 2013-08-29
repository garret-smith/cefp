
% CEFP - complex event-flow processing

-module(cefp).

-behaviour(gen_server).

% public API
-export([
        empty_flow/0,
        new_flow/2,
        add_rule/2,
        rule/3,
        add_edge/3,
        edges_out/2,
        start_flow/1,
        start_link_flow/1,
        send_event/2,
        send_timed_event/3,
        call_rule/3,
        event/1,
        event/2,
        event_data/1,
        event_time/1,
        event_source/1,
        start_timer/2,
        cancel_timer/1,
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

-export_type([
        cefp_event/0,
        cefp_rule/0
    ]).

-record(cefp_rule, {
        name      :: term(),
        callback  :: atom(),
        state     :: term()
    }).

-record(cefp_flow, {
        rules :: orddict:orddict(), % vertices
        edges :: [{From :: term(), To :: term()}]
    }).

-record(cefp_event, {
        data,  % the actual event data
        ts,    % timestamp of the event
        source % name of the rule the event came from
    }).

-opaque cefp_rule() :: #cefp_rule{}.
-opaque cefp_event() :: #cefp_event{}.

-callback handle_event(cefp_event(), term()) -> {noevent, term()} | {event, term(), term()} | {events, [term()], term()} .
-callback handle_call(term(), term(), term()) -> {reply, term(), term()} | {noreply, term()} .
-callback handle_timeout(reference(), term(), term()) -> {noevent, term()} | {event, term(), term()} | {events, [term()], term()} .

%%%===================================================================
%%% Public API functions
%%%===================================================================

empty_flow() ->
    #cefp_flow{rules = orddict:new(), edges = []}
    .

new_flow(Rules, Edges) ->
    #cefp_flow{
        rules = orddict:from_list([{Name, Rule} || Rule = #cefp_rule{name = Name} <- Rules]),
        edges = Edges
    }
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

event(Data) ->
    event(Data, os:timestamp())
    .

event(Data, Ts) when is_tuple(Ts) ->
    Source = case get(rule_name) of
        undefined -> start;
        [] -> start;
        RuleStack -> hd(RuleStack)
    end,
    #cefp_event{data = Data, ts = Ts, source = Source}
    .

event_data(#cefp_event{data = Data}) -> Data .
event_time(#cefp_event{ts = Ts}) -> Ts .
event_source(#cefp_event{source = Source}) -> Source .

send_event(Pid, Ev) ->
    gen_server:cast(Pid, {event, event(Ev)})
    .

send_timed_event(Pid, Ev, Time) ->
    gen_server:cast(Pid, {event, event(Ev, Time)})
    .

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
    Rule = get_rule(RuleName, Flow),
    {[], NewRule} = run_rule({call, From, Msg}, Rule),
    NewFlow = update_rule(NewRule, Flow),
    {noreply, NewFlow}
    .

handle_cast({event, Ev}, Flow) ->
    RuleEv = [{Rule,Ev} || Rule <- edges_out(start, Flow)],
    {NewFlow, _Results} = rec_apply(RuleEv, Flow, []),
    {noreply, NewFlow}
    .

handle_info({timeout, TRef, {rule_timeout, RuleName, Ev}}, Flow) ->
    % Should handle this differently if RuleName is a list vs an atom?
    % Have to handle this differently, since the nested context is required
    % before the event can be applied and properly "bubble out" of the nesting.
    %
    % what about handling this like a rule call (above) but handling the result
    % differently, ie applying the result like an event?
    {NewFlow, _Results} = rec_apply([{RuleName, {timeout, TRef, Ev}}], Flow, []),
    {noreply, NewFlow}
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
    {OutEvs, NewRule} = run_rule(Ev, get_rule(RuleName, Flow)),
    case edges_out(RuleName, Flow) of
        [] ->
            {NextEvs, update_rule(NewRule, Flow), OutEvs ++ Results};
        OutRules ->
            {[{OutRule, OutEv} || OutRule <- OutRules, OutEv <- OutEvs] ++ NextEvs, update_rule(NewRule, Flow), Results}
    end
    % what about a rule returning multiple events?  Used especially for nesting.
    .

get_rule(RuleName, #cefp_flow{rules = Rules}) ->
    orddict:fetch(RuleName, Rules)
    .

update_rule(NewRule = #cefp_rule{name = RuleName}, Flow = #cefp_flow{rules = Rules}) ->
    Flow#cefp_flow{rules = orddict:store(RuleName, NewRule, Rules)}
    .

%-spec run_rule(#cefp_event{} | {timeout, reference(), term()}, #cefp_rule{}) -> {ok, #cefp_rule{}} | {event, #cefp_event{}, #cefp_rule{}} .
run_rule(Ev = #cefp_event{}, Rule = #cefp_rule{name = Name, callback = Cb, state = S}) ->
    handle_reply(call_rule_cb(Name, Cb, handle_event, [Ev, S]), {none, none}, Rule)
    ;
run_rule({timeout, Ref, Msg}, Rule = #cefp_rule{name = Name, callback = Cb, state = S}) ->
    handle_reply(call_rule_cb(Name, Cb, handle_timeout, [Ref, Msg, S]), {none, none}, Rule)
    ;
run_rule({call, From, Msg}, Rule = #cefp_rule{name = Name, callback = Cb, state = S}) ->
    handle_reply(call_rule_cb(Name, Cb, handle_call, [Msg, From, S]), From, Rule)
    .

call_rule_cb(RuleName, M, F, A) ->
    put(rule_name, [RuleName | get(rule_name)]),
    Result = apply(M, F, A),
    put(rule_name, tl(get(rule_name))),
    Result
    .

handle_reply(RuleReply, From, Rule) ->
    case RuleReply of
        {noevent, S1} ->
            {[], Rule#cefp_rule{state = S1}};
        {event, NewEv = #cefp_event{}, S1} ->
            {[NewEv], Rule#cefp_rule{state = S1}};
        {event, NewEv, S1} ->
            {[event(NewEv)], Rule#cefp_rule{state = S1}};
        {events, NewEvs, S1} ->
            {NewEvs, Rule#cefp_rule{state = S1}};
        {noreply, S1} ->
            {[], Rule#cefp_rule{state = S1}};
        {reply, Reply, S1} ->
            reply(From, Reply),
            {[], Rule#cefp_rule{state = S1}}
    end
    .

reply(From, Reply) ->
    gen:reply(From, Reply)
    .

start_timer(Msg, Time) ->
    % need to handle nesting here by changing event.
    erlang:start_timer(Time, self(), {rule_timeout, hd(get(rule_name)), Msg})
    .

cancel_timer(Ref) ->
    erlang:cancel_timer(Ref),
    receive
        {timeout, Ref, _} -> ok
    after
        0 -> ok
    end
    .


