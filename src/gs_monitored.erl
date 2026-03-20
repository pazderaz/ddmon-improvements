-module(gs_monitored).
-behaviour(gen_server).

-include("ddmon.hrl").

%% API
-export([start_link/3]).

%% gen_server Callbacks
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2, code_change/3]).

%% Start the server
start_link(Module, Args0, Options) ->
    Args1 = [{monitor, self()}, {module, Module} | Args0],
    gen_server:start_link(?MODULE, Args1, Options).

%% gen_server callbacks

init([{monitor, Monitor}, {module, Module}|Args]) ->
    put(?MON_PID, Monitor),
    put(?CALLBACK_MOD, Module),

    %% --- ELIXIR COMPATIBILITY ---
    %% Elixir testing tools (like Mox and Ecto.Adapters.SQL.Sandbox) rely on a hidden
    %% process dictionary key called '$callers' to trace ownership back to the test process.
    %% Erlang wrappers drop this key. By copying the built-in '$ancestors' list 
    %% (which contains the test process PID) to '$callers', we restore the link for Elixir.
    case get('$callers') of
        undefined ->
            case get('$ancestors') of
                undefined -> ok;
                Ancestors -> put('$callers', Ancestors)
            end;
        _ -> 
            ok
    end,
    %% -----------------------------

    Module:init(Args).


handle_call(Msg, From, State) ->
    Module = get(?CALLBACK_MOD),
    Module:handle_call(Msg, From, State).


handle_cast(Msg, State) ->
    Module = get(?CALLBACK_MOD),
    Module:handle_cast(Msg, State).


handle_info(Info, State) ->
    Module = get(?CALLBACK_MOD),
    case erlang:function_exported(Module, handle_info, 2) of
        true -> Module:handle_info(Info, State);
        false ->
            logger:warning("~p: unexpected message: ~p", [?CALLBACK_MOD, Info], #{subsystem => ddmon}), 
            {noreply, State}
    end.


terminate(Reason, State) ->
    Module = get(?CALLBACK_MOD),
    case erlang:function_exported(Module, terminate, 2) of
        true -> Module:terminate(Reason, State);
        false -> ok
    end.


code_change(OldVsn, State, Extra) ->
    Module = get(?CALLBACK_MOD),
    case erlang:function_exported(Module, code_change, 3) of
        true -> Module:code_change(OldVsn, State, Extra);
        false -> {ok, State}
    end.
