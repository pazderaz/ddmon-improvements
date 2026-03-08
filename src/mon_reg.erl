-module(mon_reg).
-behaviour(gen_server).

-include("ddmon.hrl").

%% API
-export([start_link/0, register_monitor/1, is_monitored/1, child_spec/1]).

%% gen_server callbacks
-export([init/1, handle_call/3, handle_cast/2, handle_info/2]).

-define(TABLE, ?MODULE).

%%%======================
%%% API
%%%======================

start_link() ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).

%% Called by ddmon inside init/1
register_monitor(Pid) ->
    try
        gen_server:call(?MODULE, {register, Pid})
    catch _:_ ->
        ?DDM_DBG_MON_REG("~p: failed to register itself to the monitoring registry. Monitor registry is probably offline!", [Pid]),
        false
    end.

is_monitored(Target) ->
    case resolve_target(Target) of
        Pid when is_pid(Pid) ->
            try 
                ets:member(?TABLE, Pid)
            catch _:_ -> 
                ?DDM_DBG_MON_REG("~p failed to check if '~p' is monitored. Monitor registry is probably offline!", [self(), Target]),
                false
            end;
        _ ->
            false
    end.

child_spec(_Opts) ->
    #{ id => ?MODULE,
       start => {?MODULE, start_link, []},
       restart => permanent,
       shutdown => 5000,
       type => worker,
       modules => [?MODULE] }.

%%%======================
%%% Helpers
%%%======================

%% Resolves standard OTP destination types to a local PID
resolve_target(Pid) when is_pid(Pid) -> 
    Pid;
resolve_target(Name) when is_atom(Name) -> 
    whereis(Name);
resolve_target({global, Name}) -> 
    global:whereis_name(Name);
resolve_target({via, Module, Name}) -> 
    Module:whereis_name(Name);
resolve_target({Name, Node}) when Node =:= node() -> 
    whereis(Name);
resolve_target(_) -> 
    undefined. %% Remote nodes or invalid targets

%%%======================
%%% Callbacks
%%%======================

init([]) ->
    %% read_concurrency: optimizes simultaneous reads
    ets:new(?TABLE, [named_table, protected, set, {read_concurrency, true}]),
    {ok, #{}}. %% State is a Map of MonitorRef => {Pid}

handle_call({register, Pid}, _From, State) ->
    %% Monitor the process so we know if it dies
    MRef = erlang:monitor(process, Pid),
    
    %% Insert the PID into ETS
    ets:insert(?TABLE, {Pid}),

    {reply, ok, State#{MRef => {Pid}}}.

handle_cast(_Msg, State) ->
    {noreply, State}.

handle_info({'DOWN', MRef, process, _Pid, _Reason}, State) ->
    case maps:take(MRef, State) of
        {{DeadPid}, NewState} ->
            ets:delete(?TABLE, DeadPid),
            {noreply, NewState};
        error ->
            {noreply, State}
    end;

handle_info(_Info, State) ->
    {noreply, State}.
