%%%-------------------------------------------------------------------
%%% @doc Monitor registry using pg process groups.
%%%
%%% Maps `gen_server` identities (PIDs or global names) to their monitor
%%% processes. Uses a custom pg scope for distributed lookups.
%%% -------------------------------------------------------------------

-module(mon_reg).

-export([ensure_started/0, is_registered/1, set_mon/2, unset_mon/1]).

-define(PG_SCOPE, mon_reg_scope).

%%%===================================================================
%%% API functions
%%%===================================================================

%% @doc Ensure the pg scope is running. Idempotent — safe to call multiple times.
-spec ensure_started() -> ok.
ensure_started() ->
    case pg:start(?PG_SCOPE) of
        {ok, _} -> ok;
        {error, {already_started, _}} -> ok
    end.

%% @doc Check if a process identified by the key is a registered (ddmon) proxy monitor.
-spec is_registered(term()) -> pid() | boolean().
is_registered(Key) ->
    case resolve_target(Key) of
        Pid when is_pid(Pid) ->
            case pg:get_members(?PG_SCOPE, Pid) of
                [_ | _] -> true;
                [] -> false
            end;
        undefined -> false
    end.

%% @doc Register a (ddmon) proxy monitor for a key.
-spec set_mon(term(), pid()) -> ok | {error, already_registered}.
set_mon(Key, MonPid) ->
    Callback =
        fun() ->
                case pg:get_members(?PG_SCOPE, Key) of
                    [] ->
                        pg:join(?PG_SCOPE, Key, MonPid),
                        ok;
                    [_ | _] ->
                        {error, already_registered}
                end
        end,
    %% It seems that pg reqiures this to be run on the same node as MonPid
    exec_on_pid_node(MonPid, Callback).

%% @doc Unregister a (ddmon) proxy monitor for a key.
-spec unset_mon(term()) -> ok.
unset_mon(Key) ->
    case pg:get_members(?PG_SCOPE, Key) of
        [MonPid | _] -> pg:leave(?PG_SCOPE, Key, MonPid), ok;
        [] -> ok
    end.

%%%===================================================================
%%% Helper functions
%%%===================================================================

%% @doc Executes a function on the node of the specified PID (either locally or
%% via RPC).
-spec exec_on_pid_node(pid(), fun(() -> T)) -> T.
exec_on_pid_node(Pid, Fun) when is_pid(Pid), is_function(Fun, 0) ->
    Node = node(Pid),
    case Node of
        N when N =:= node() ->
            Fun();
        N ->
            rpc:call(N, erlang, apply, [Fun, []])
    end.

%% @doc Resolves standard OTP destination types to a local PID.
-spec resolve_target(term()) -> pid() | undefined.
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
