-module(gsm_monitored).
-behaviour(gen_statem).

-include("ddmon.hrl").

%% API
-export([start_link/3]).

%% gen_statem Callbacks
-export([init/1, callback_mode/0, handle_event/4, terminate/3, code_change/4]).

%% Start the server
start_link(Module, Args0, Options) ->
    Args1 = [{monitor, self()}, {module, Module} | Args0],
    gen_statem:start_link(?MODULE, Args1, Options).

init([{monitor, Monitor}, {module, Module}|Args]) ->
    put(?MON_PID, Monitor),
    put(?CALLBACK_MOD, Module),
    put(?WORKER_MODULE, gen_statem),

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
        _ -> ok
    end,

    Module:init(Args).

callback_mode() ->
    Module = get(?CALLBACK_MOD),
    UnderlyingMode = Module:callback_mode(),
    WantsStateEnter = is_list(UnderlyingMode) andalso lists:member(state_enter, UnderlyingMode),

    %% We always route through handle_event, but we have to respect state_enter if the module requests it!
    case WantsStateEnter of
        true -> [handle_event_function, state_enter];
        false -> handle_event_function
    end.

%% Generic event router
handle_event(EventType, EventContent, State, Data) ->
    Module = get(?CALLBACK_MOD),
    Modes = Module:callback_mode(),
    
    %% Standardize to a list for easier checking
    ModeList = if is_list(Modes) -> Modes; true -> [Modes] end,

    case lists:member(handle_event_function, ModeList) of
        true -> Module:handle_event(EventType, EventContent, State, Data);
        false -> 
            %% Assume state_functions if not handle_event_function
            Module:State(EventType, EventContent, Data)
    end.

terminate(Reason, State, Data) ->
    Module = get(?CALLBACK_MOD),
    case erlang:function_exported(Module, terminate, 3) of
        true -> Module:terminate(Reason, State, Data);
        false -> ok
    end.

code_change(OldVsn, State, Data, Extra) ->
    Module = get(?CALLBACK_MOD),
    case erlang:function_exported(Module, code_change, 4) of
        true -> Module:code_change(OldVsn, State, Data, Extra);
        false -> {ok, State, Data}
    end.