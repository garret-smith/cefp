
% CEFP - complex event flow processing
-module(cefp).


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
        event/1,
        event/2,
        event_data/1,
        event_time/1,
        event_source/1,
        start_loop/1,
        loop/1,
        start_timer/2,
        cancel_timer/1
    ]).

-record(cefp_rule, {
        name      :: term(),
        callback  :: atom(),
        state     :: term()
    }).

-type cefp_rule() :: #cefp_rule{}.

-record(cefp_flow, {
        rules :: orddict:orddict(), % vertices
        edges :: [{From :: term(), To :: term()}]
    }).

-record(cefp_event, {
        data,  % the actual event data
        ts,    % timestamp of the event
        source % name of the rule the event came from
    }).

-type cefp_event() :: #cefp_event{}.

-export_type([
        cefp_event/0,
        cefp_rule/0
    ]).

-callback handle_event(cefp_event(), term()) -> {ok, term()} | {event, term(), term()} .
-callback handle_call(term(), term(), term()) -> {noreply, term()} | {event, term(), term()} .

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
    spawn(?MODULE, start_loop, [Flow])
    .

start_link_flow(Flow) ->
    spawn_link(?MODULE, start_loop, [Flow])
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
    Pid ! {event, event(Ev)}
    .

send_timed_event(Pid, Ev, Time) ->
    Pid ! {event, event(Ev, Time)}
    .

start_loop(Flow) ->
    put(rule_name, []),
    % rule_name is a stack to support nested flows.
    % Used to know which rule is running if a rule calls various
    % cefp functions like start_timer()
    loop(Flow)
    .

loop(Flow) ->
    receive
        {event, Ev} ->
            RuleEv = [{Rule,Ev} || Rule <- edges_out(start, Flow)],
            {NewFlow, _Results} = rec_apply(RuleEv, Flow, []),
            loop(NewFlow)
            ;
        %{timeout, TRef, {rule_timeout, RuleName, Ev}} ->
        %    % Should handle this differently if RuleName is a list vs an atom?
        %    % Have to handle this differently, since the nested context is required
        %    % before the event can be applied and properly "bubble out" of the nesting.
        %    {NewFlow, _Results} = rec_apply({RuleName, {timeout, TRef, Ev}}, Flow, []),
        %    loop(NewFlow)
        %    ;
        shutdown ->
            shutdown
            ;
        Msg ->
            io:fwrite("unexpected message: ~p~n", [Msg]),
            loop(Flow)
    end
    .

rec_apply([], Flow, Results) ->
    {Flow, Results}
    ;
rec_apply(RuleEv, FlowGraph, PrevResults) ->
    {NextEvs, NewFlow, NewResults} = lists:foldr(
        fun({RuleName, Ev = #cefp_event{}}, {NextEv, Flow, Results}) ->
                case run_rule(Ev, get_rule(RuleName, Flow)) of
                    {ok, NewRule} ->
                        {NextEv, update_rule(NewRule, Flow), Results}
                        ;
                    {event, OutEv, NewRule} ->
                        case edges_out(RuleName, Flow) of
                            [] ->
                                {NextEv, update_rule(NewRule, Flow), [OutEv | Results]};
                            OutRules ->
                                {[{OutRule, OutEv} || OutRule <- OutRules] ++ NextEv, update_rule(NewRule, Flow), Results}
                        end
                    % what about a rule returning multiple events?  Used especially for nesting.
                end
        end,
        {[], FlowGraph, []},
        RuleEv),
    rec_apply(NextEvs, NewFlow, NewResults ++ PrevResults)
    .

get_rule(RuleName, #cefp_flow{rules = Rules}) ->
    orddict:fetch(RuleName, Rules)
    .

update_rule(NewRule = #cefp_rule{name = RuleName}, Flow = #cefp_flow{rules = Rules}) ->
    Flow#cefp_flow{rules = orddict:store(RuleName, NewRule, Rules)}
    .

-spec run_rule(#cefp_event{}, #cefp_rule{}) -> {ok, #cefp_rule{}} | {event, #cefp_event{}, #cefp_rule{}} .
run_rule(Ev = #cefp_event{}, Rule = #cefp_rule{name = Name, callback = Cb, state = S}) ->
    put(rule_name, [Name | get(rule_name)]),
    Result = case Cb:handle_event(Ev, S) of
        {ok, S1} ->
            {ok, Rule#cefp_rule{state = S1}};
        {event, NewEv = #cefp_event{}, S1} ->
            {event, NewEv, Rule#cefp_rule{state = S1}};
        {event, NewEv, S1} ->
            {event, event(NewEv), Rule#cefp_rule{state = S1}}
    end,
    put(rule_name, tl(get(rule_name))),
    Result
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


