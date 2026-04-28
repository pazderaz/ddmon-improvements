-module(ddmon).
-behaviour(gen_statem).

-include("ddmon.hrl").

-define(PROBE_DELAY, '$ddmon_probe_delay').

%% API
-export([ start/2, start/3, start/4
        , start_link/2, start_link/3, start_link/4
        ]).

%% gen_server interface
-export([ call/2, call/3
        , cast/2, stop/3
        , send_request/2, send_request/4
        , receive_response/1, receive_response/2, receive_response/3
        , wait_response/1, wait_response/2, wait_response/3
        ]).

%% Helper API
-export([ public_self/0, call_report/2, call_report/3
        , send_request_report/2, send_request_report/4
        , wait_response_report/2, wait_response_report/3
        , subscribe_deadlocks/1
        ]).

%% gen_statem callbacks
-export([init/1, callback_mode/0, terminate/3]).

%% States
-export([unlocked/3, locked/3, deadlocked/3]).

%% Internal state queries
-export([ state_get_worker/1, state_get_req_tag/1, state_get_req_id/1, state_get_waitees/1
        , deadstate_get_worker/1, deadstate_get_deadlock/1, deadstate_is_foreign/1
        ]).

%%%======================
%%% DDMon Types
%%%======================

-record(state,
        { worker :: pid()
        , req_tag :: gen_server:reply_tag() | undefined
        , req_id :: gen_statem:request_id() | undefined
        , waitees :: gen_server:request_id_collection()
        , deadlock_subscribers :: list(pid())
        }).

-record(deadstate,
        { worker :: pid()
        , deadlock :: list(pid())
        , req_id :: gen_statem:request_id()
        , foreign = false :: boolean()
        , deadlock_subscribers :: list(pid())
        }).

state_get_worker(#state{worker = Worker}) ->
    Worker;
state_get_worker(#deadstate{worker = Worker}) ->
    Worker.

state_get_req_tag(State) ->
    State#state.req_tag.

state_get_req_id(State) ->
    State#state.req_id.

state_get_waitees(State) ->
    State#state.waitees.

deadstate_get_worker(State) ->
    State#deadstate.worker.

deadstate_get_deadlock(State) ->
    State#deadstate.deadlock.

deadstate_is_foreign(State) ->
    State#deadstate.foreign.

%%%======================
%%% External helpers
%%%======================

public_self() ->
    case get(?MON_PID) of
        undefined -> self();
        MonPid -> MonPid
    end.

%%%======================
%%% API Functions
%%%======================

start(Module, Args) ->
    start(Module, Args, []).

start(Module, Args, Options) ->
    %% We allow running unmonitored systems via options
    DdmonOpts = proplists:get_value(ddmon_opts, Options, []),
    case proplists:get_value(unmonitored, DdmonOpts, false) of
        true ->
            WorkerType = proplists:get_value(worker_type, DdmonOpts, gen_server),
            WorkerType:start(Module, Args, Options);
        false ->
            %% Elixir compat
            ChildOptions = proplists:delete(name, Options),
            case proplists:get_value(name, Options) of
                undefined ->
                    gen_statem:start(?MODULE, {Module, Args, ChildOptions}, Options);
                Name when is_atom(Name) ->
                    gen_statem:start({local, Name}, ?MODULE, {Module, Args, ChildOptions}, Options);
                Name ->
                    gen_statem:start(Name, ?MODULE, {Module, Args, ChildOptions}, Options)
            end
    end.

start(ServerName, Module, Args, Options) ->
    %% We allow running unmonitored systems via options
    DdmonOpts = proplists:get_value(ddmon_opts, Options, []),
    case proplists:get_value(unmonitored, DdmonOpts, false) of
        true ->
            WorkerType = proplists:get_value(worker_type, DdmonOpts, gen_server),
            WorkerType:start(ServerName, Module, Args, Options);
        false ->
            gen_statem:start(ServerName, ?MODULE, {Module, Args, Options}, Options)
    end.


start_link(Module, Args) ->
    start_link(Module, Args, []).

start_link(Module, Args, Options) ->
    %% We allow running unmonitored systems via options
    DdmonOpts = proplists:get_value(ddmon_opts, Options, []),
    case proplists:get_value(unmonitored, DdmonOpts, false) of
        true ->
            WorkerType = proplists:get_value(worker_type, DdmonOpts, gen_server),
            WorkerType:start_link(Module, Args, Options);
        false ->
            %% Elixir compat
            ChildOptions = proplists:delete(name, Options),
            case proplists:get_value(name, Options) of
                undefined ->
                    gen_statem:start_link(?MODULE, {Module, Args, ChildOptions}, Options);
                Name when is_atom(Name) ->
                    gen_statem:start_link({local, Name}, ?MODULE, {Module, Args, ChildOptions}, Options);
                Name ->
                    gen_statem:start_link(Name, ?MODULE, {Module, Args, ChildOptions}, Options)
            end
    end.

start_link(ServerName, Module, Args, Options) ->
    %% We allow running unmonitored systems via options
    DdmonOpts = proplists:get_value(ddmon_opts, Options, []),
    case proplists:get_value(unmonitored, DdmonOpts, false) of
        true ->
            WorkerType = proplists:get_value(worker_type, DdmonOpts, gen_server),
            WorkerType:start_link(ServerName, Module, Args, Options);
        false ->
            gen_statem:start_link(ServerName, ?MODULE, {Module, Args, Options}, Options)
    end.

%%%======================
%%% gen_server interface
%%%======================

call(Server, Request) ->
    call(Server, Request, 5000).

call(Server, Request, Timeout) ->
    case get(?MON_PID) of
        undefined ->
            gen_server:call(Server, Request, Timeout);
        Mon ->
            ExpectedModule = case get(?WORKER_MODULE) of
                undefined -> gen_server;
                ModType   -> ModType
            end,

            %% Intercept the proxy's response
            try gen_statem:call(Mon, {Request, Server}, Timeout) of
                {'$ddmon_target_died', Reason} ->
                    %% Recreate exact OTP crash behavior using the expected module
                    exit({Reason, {ExpectedModule, call, [Server, Request, Timeout]}});
                NormalReply ->
                    NormalReply
            catch
                % In case of a timeout, replicate it transparently using the worker module
                exit:{timeout, {gen_statem, call, _}} ->
                    %% Rewrite timeout exception to match the caller's domain
                    exit({timeout, {ExpectedModule, call, [Server, Request, Timeout]}})
            end
    end.


%% `call` variant that makes the caller receive probes and deadlock
%% notifications.
call_report(Server, Request) ->
    call(Server, {?MONITORED_CALL, Request}).

call_report(Server, Request, Timeout) ->
    call(Server, {?MONITORED_CALL, Request}, Timeout).


send_request(Server, Request) ->
    gen_statem:send_request(Server, Request).

send_request(Server, Request, Label, ReqIdCollection) ->
    gen_statem:send_request(Server, Request, Label, ReqIdCollection).

send_request_report(Server, Request) ->
    gen_statem:send_request(Server, {?MONITORED_CALL, Request}).

send_request_report(Server, Request, Label, ReqIdCollection) ->
    gen_statem:send_request(Server, {?MONITORED_CALL, Request}, Label, ReqIdCollection).


receive_response(ReqId) ->
    gen_statem:receive_response(ReqId).

receive_response(ReqId, Timeout) ->
    gen_statem:receive_response(ReqId, Timeout).

receive_response(ReqIdCollection, Timeout, Delete) ->
    gen_statem:receive_response(ReqIdCollection, Timeout, Delete).


wait_response(ReqId) ->
    gen_statem:receive_response(ReqId).

wait_response(ReqId, Timeout) ->
    gen_statem:receive_response(ReqId, Timeout).

wait_response(ReqIdCollection, Timeout, Delete) ->
    gen_statem:receive_response(ReqIdCollection, Timeout, Delete).

-define(DL_CHECK, 100).
wait_response_report(ReqId, Timeout) ->
    Loop = fun Rec(TO) when TO < 0 ->
                   timeout;
               Rec(TO) ->
                   case gen_statem:wait_response(ReqId, ?DL_CHECK) of
                       timeout ->
                           receive
                               {?DEADLOCK, DL} -> {?DEADLOCK, DL}
                           after 0 ->
                                   TO1 = if is_integer(TO) -> TO - ?DL_CHECK; true -> TO end,
                                   Rec(TO1)
                           end;
                       no_request -> no_request;
                       R = {Res, _} when Res =:= reply orelse Res =:= error ->
                           R
                   end
           end,
    Loop(Timeout).

wait_response_report(ReqIdCollection, Timeout, Delete) ->
    Loop = fun Rec(TO) when TO < 0 ->
                   timeout;
               Rec(TO) ->
                   case gen_statem:wait_response(ReqIdCollection, ?DL_CHECK, Delete) of
                       timeout ->
                           receive
                               {?DEADLOCK, DL} -> {?DEADLOCK, DL}
                           after 0 ->
                                   TO1 = if is_integer(TO) -> TO - ?DL_CHECK; true -> TO end,
                                   Rec(TO1)
                           end;
                       no_request -> no_request;
                       R = {{Res, _}, _, _} when Res =:= reply orelse Res =:= error ->
                           R
                   end
           end,
    Loop(Timeout).


cast(Server, Message) ->
    gen_server:cast(Server, Message).


stop(Server, Reason, Timeout) ->
    gen_server:stop(Server, Reason, Timeout).


subscribe_deadlocks(Server) ->
    gen_statem:cast(Server, {?DL_SUBSCRIBE, self()}).

%%%======================
%%% Internal Helpers
%%%======================

forward_external_exit(ExitMsg = {'EXIT', _From, Reason}, Worker) ->
    case erlang:process_info(Worker, trap_exit) of
        {trap_exit, true} ->
            %% Worker traps exits. Forward as a raw message.
            Worker ! ExitMsg;
        {trap_exit, false} ->
            %% Worker doesn't trap exits. Emulate standard BEAM behavior.
            case Reason of
                normal -> ok;
                _ -> exit(Worker, Reason)
            end;
        undefined ->
            ok
    end.

do_teardown(Worker, Reason, State, Data) ->
    case is_process_alive(Worker) of
        true ->
            exit(Worker, Reason),
            await_worker_exit(Worker, State, Data);
        false ->
            ok
    end.

await_worker_exit(Worker, State, Data) ->
    receive 
        {'EXIT', Worker, _WorkerReason} -> 
            ok;
        RawMsg ->
            %% Convert the raw mailbox message into a gen_statem event
            {EventType, EventContent} =
                case RawMsg of
                    {'$gen_cast', CastMsg} -> 
                        {cast, CastMsg};
                    {'$gen_call', From, CallMsg} -> 
                        {{call, From}, CallMsg};
                    InfoMsg -> 
                        {info, InfoMsg}
                end,

            %% Feed it back into ddmon's current state callback
            %% e.g., ddmon:unlocked(cast, {:sync, ...}, Data)
            Result = ?MODULE:State(EventType, EventContent, Data),

            %% Parse the result to update our loop's state
            {NextState, NextData} = apply_state_transition(State, Data, Result),

            %% Loop again until the worker is dead
            await_worker_exit(Worker, NextState, NextData)
    after 5000 -> %% Failsafe timeout
            %% Consider killing the process uncleanly.
            ok
    end.

%% Helper to unpack gen_statem return values
apply_state_transition(OldState, OldData, Result) ->
    case Result of
        {next_state, NewState, NewData} -> 
            {NewState, NewData};
        {next_state, NewState, NewData, Actions} ->
            execute_actions(Actions),
            {NewState, NewData};
        {keep_state, NewData} -> 
            {OldState, NewData};
        {keep_state, NewData, Actions} -> 
            execute_actions(Actions),
            {OldState, NewData};
        keep_state_and_data -> 
            {OldState, OldData};
        {keep_state_and_data, Actions} ->
            execute_actions(Actions),
            {OldState, OldData};
        _Other -> 
            %% If it returns stop, we just keep the old state and wait for death
            {OldState, OldData}
    end.

%% Execute actions (replies so clients don't hang)
%% TODO: support more action types if needed
execute_actions(Actions) when is_list(Actions) ->
    lists:foreach(fun
        ({reply, From, Msg}) -> gen_statem:reply(From, Msg);
        (_) -> ok
    end, Actions);

execute_actions(Action) -> 
    execute_actions([Action]).

%%%======================
%%% gen_statem Callbacks
%%%======================

init({Module, Args, Options}) ->
    process_flag(trap_exit, true),

    DlsOpts = proplists:get_value(ddmon_opts, Options, []),
    ProcOpts = proplists:delete(ddmon_opts, proplists:delete(name, Options)),

    %% Check options to see if we should wrap a statem or a server
    WorkerType = proplists:get_value(worker_type, DlsOpts, gen_server),
    StartRes = case WorkerType of
        gen_statem -> gsm_monitored:start_link(Module, Args, ProcOpts);
        gen_server -> gs_monitored:start_link(Module, Args, ProcOpts)
    end,

    case StartRes of
        {ok, Pid} ->
            State =
                #state{worker = Pid,
                       waitees = gen_server:reqids_new(),
                       req_tag = undefined,
                       req_id = undefined,
                       deadlock_subscribers = []
                      },

            mon_reg:ensure_started(),
            mon_reg:set_mon(self(), self()),
            
            ProbeDelay = proplists:get_value(probe_delay, DlsOpts, ?DEFAULT_PROBE_DELAY),
            put(?PROBE_DELAY, ProbeDelay),

            logger:info("[DDMON] Started monitor ~p for process ~p (~p). Probe delay: ~p", [self(), Pid, Module, ProbeDelay], #{subsystem => ddmon}),
            {ok, unlocked, State};
        E -> E
    end.

terminate(Reason, State, Data) ->
    Worker = state_get_worker(Data),
    do_teardown(Worker, Reason, State, Data).

callback_mode() ->
    [state_functions, state_enter].

unlocked(enter, _, _) ->
    keep_state_and_data;

unlocked(cast, {?DL_SUBSCRIBE, Who}, State = #state{deadlock_subscribers = Subs}) ->
    {keep_state, State#state{deadlock_subscribers = [Who|Subs]}};

unlocked({call, From}, ?GET_CHILD, #state{worker = Worker}) ->
    {keep_state_and_data, {reply, From, Worker}};


%% Our service wants a call to itself (either directly or the monitor)
unlocked({call, {Worker, PTag}}, {_Msg, Server}, _State = #state{worker = Worker
                                                                , waitees = Waitees
                                                                , deadlock_subscribers = Subs
                                                                })
  when Server =:= Worker orelse Server =:= self() ->
    [ begin
          gen_statem:reply(W, {?DEADLOCK, [self(), self()]})
      end
      || {_, #{from := W, monitored := true}} <- gen_statem:reqids_to_list(Waitees)
    ],
    ?DDM_WARN_DEADLOCK("~p: Attempted a call to itself!", [Worker]),
    {next_state, deadlocked,
     #deadstate{ worker = Worker
               , deadlock = [self(), self()]
               , req_id = PTag
               , deadlock_subscribers = Subs
               }
    };

%% Our service wants a call
unlocked({call, {Worker, PTag}}, {Msg, Server}, State = #state{worker = Worker}) ->
    FinalMsg = case mon_reg:is_registered(Server) of
        true -> %% Target is monitored. Wrap it so the monitors can track it.
            {?MONITORED_CALL, Msg};
        false -> %% Target is a standard gen_server. Leave it unwrapped so it doesn't crash.
            ?DDM_DBG_ALIEN("~p: Calling unmonitored process '~p'", [self(), Server]),
            Msg
    end,

    %% Forward the request as `call` asynchronously
    ExtTag = gen_statem:send_request(Server, FinalMsg),

    ?DDM_DBG_STATE("(unlocked -> locked) ~p: Calling process '~p'", [Worker, Server]),
    {next_state, locked,
     State#state{
       req_tag = PTag,
       req_id = ExtTag
      }
    };

%% Incoming external call
unlocked({call, From}, Msg, State = #state{waitees = Waitees0}) ->
    {Monitored, RawMsg} =
        case Msg of
            {?MONITORED_CALL, RMsg} -> {true, RMsg};
            _ ->
                ?DDM_DBG_ALIEN("~p: Received unmonitored call from '~p'", [self(), From]),
                {false, Msg}
        end,

    %% Forward to the process
    ReqId = gen_server:send_request(State#state.worker, RawMsg),

    %% Register the request
    Waitees1 = gen_server:reqids_add(ReqId, #{from => From, monitored => Monitored}, Waitees0),

    {keep_state,
     State#state{waitees = Waitees1}
    };

%% Probe while unlocked --- ignore
unlocked(cast, {probe, _Probe}, _) ->
    keep_state_and_data;

%% Unknown cast
unlocked(cast, Msg, #state{worker = Worker}) ->
    gen_server:cast(Worker, Msg),
    keep_state_and_data;

%% Scheduled probe
unlocked(cast, {?SCHEDULED_PROBE, _To, _Probe}, _State) ->
    keep_state_and_data;

%% Worker process exited 
unlocked(info, {'EXIT', Worker, Reason}, #state{worker=Worker}) ->
    ?DDM_DBG_DDMON("~p: Monitored process ~p exited with reason ~p. Stopping the monitor.", [self(), Worker, Reason]),
    {stop, Reason};

%% Someone wants to terminate us.
unlocked(info, ExitMsg = {'EXIT', _From, _Reason}, #state{worker=Worker}) ->
    forward_external_exit(ExitMsg, Worker),
    keep_state_and_data;

%% Process sent a reply (or not)
unlocked(info, Msg, State = #state{waitees = Waitees0, worker = Worker}) ->
    case gen_server:check_response(Msg, Waitees0, _Delete = true) of
        no_request ->
            %% Unknown info (waitees empty). Let the process handle it.
            Worker ! Msg,
            keep_state_and_data;

        no_reply ->
            %% Unknown info. Let the process handle it.
            Worker ! Msg,
            keep_state_and_data;

        {{reply, Reply}, #{from := From}, Waitees1} ->
            %% It's a reply from the process. Forward it.
            {keep_state,
             State#state{waitees = Waitees1},
             {reply, From, Reply}
            };

        {{error, {Reason, _ServerRef}}, #{from := From}, Waitees1} ->
            %% Forward the exact error tuple back to the caller.
            {keep_state,
             State#state{waitees = Waitees1},
             {reply, From, {'$ddmon_target_died', Reason}}
            }
    end.


locked(enter, _, _) ->
    keep_state_and_data;

locked(cast, {?DL_SUBSCRIBE, Who}, State = #state{deadlock_subscribers = Subs}) ->
    {keep_state, State#state{deadlock_subscribers = [Who|Subs]}};

locked({call, From}, ?GET_CHILD, #state{worker = Worker}) ->
    {keep_state_and_data, {reply, From, Worker}};

%% Incoming external call
locked({call, From}, Msg, State = #state{req_tag = PTag, waitees = Waitees0}) ->
    {Monitored, RawMsg} =
        case Msg of
            {?MONITORED_CALL, RMsg} -> {true, RMsg};
            _ ->
                ?DDM_DBG_ALIEN("~p: Received unmonitored call from '~p'", [self(), From]),
                {false, Msg}
        end,

    %% Forward to the process
    ReqId = gen_server:send_request(State#state.worker, RawMsg),

    %% Register the request
    Waitees1 = gen_server:reqids_add(ReqId, #{from => From, monitored => Monitored}, Waitees0),

    if Monitored ->
            case get(?PROBE_DELAY) of
                -1 ->
                    %% Send a probe
                    gen_statem:cast(element(1, From), {?PROBE, PTag, [self()]});
                N when is_integer(N) ->
                    %% Schedule a delayed probe
                    Self = self(),
                    spawn_link(
                      fun() ->
                              timer:sleep(N),
                              gen_statem:cast(Self, { ?SCHEDULED_PROBE
                                                    , _To = element(1, From)
                                                    , _Probe = {?PROBE, PTag, [Self]}
                                                    })
                      end)
            end;
       true -> ok
    end,

    {keep_state,
     State#state{waitees = Waitees1}
    };

%% Worker process exited 
locked(info, {'EXIT', Worker, Reason}, #state{worker=Worker}) ->
    ?DDM_DBG_DDMON("~p: Monitored process ~p exited with reason ~p. Stopping the monitor.", [self(), Worker, Reason]),
    {stop, Reason};

%% Someone wants to terminate us.
locked(info, ExitMsg = {'EXIT', _From, _Reason}, #state{worker=Worker}) ->
    forward_external_exit(ExitMsg, Worker),
    keep_state_and_data;

%% Incoming reply
locked(info, Msg, State = #state{ worker = Worker
                                , req_tag = PTag
                                , req_id = ReqId
                                , waitees = Waitees
                                , deadlock_subscribers = Subs
                                }) ->
    case gen_statem:check_response(Msg, ReqId) of
        no_reply ->
            %% Unknown info. Let the process handle it.
            Worker ! Msg,
            keep_state_and_data;

        {reply, {?DEADLOCK, DL}} ->
            %% Deadlock information
            [ begin
                  PassDL =
                      case lists:member(self(), DL) of
                          true -> DL;
                          false -> [self() | DL]
                      end,
                  gen_statem:reply(W, {?DEADLOCK, PassDL})
              end
              || {_, #{from := W, monitored := true}} <- gen_statem:reqids_to_list(Waitees)
            ],
            
            ?DDM_WARN_DEADLOCK("~p: Awaited reply from a deadlocked process!", [Worker]),
            {next_state, deadlocked, #deadstate{foreign = true
                                               , worker = Worker
                                               , deadlock = [self() | DL]
                                               , req_id = ReqId
                                               , deadlock_subscribers = Subs
                                               }};

        {reply, Reply} ->
            ?DDM_DBG_STATE("(locked -> unlocked) ~p: Replied.", [Worker]),
            %% Pass the reply to the process. We are unlocked now.
            {next_state, unlocked,
             State,
             {reply, {Worker, PTag}, Reply}
            };

        {error, {Reason, _ServerRef}} ->
            %% Pass the exact error tuple back to the waiting worker and unlock.
            ?DDM_DBG_STATE("(locked -> unlocked) ~p: Target died, passing error through.", [Worker]),
            {next_state, unlocked,
             State,
             {reply, {Worker, PTag}, {'$ddmon_target_died', Reason}}
            }
    end;

%% Incoming own probe. Alarm! Panic!
locked(cast, {?PROBE, PTag, Chain}, #state{ worker = Worker
                                          , req_tag = PTag
                                          , req_id = ReqId
                                          , waitees = Waitees
                                          , deadlock_subscribers = Subs
                                          }) ->
    DL = [self() | Chain],

    [ begin
          gen_statem:reply(W, {?DEADLOCK, DL})
      end
      || {_, #{from := W, monitored := true}} <- gen_statem:reqids_to_list(Waitees)
    ],
    ?DDM_WARN_DEADLOCK("~p: Received own probe! Formed a locked chain: ~p", [Worker, DL]),
    {next_state, deadlocked, #deadstate{ worker = Worker
                                       , deadlock = [self() | Chain]
                                       , req_id = ReqId
                                       , deadlock_subscribers = Subs
                                       }};

%% Incoming probe
locked(cast, {?PROBE, Probe, Chain}, #state{waitees = Waitees}) ->
    %% Propagate the probe to all waitees.
    [ begin
          gen_statem:cast(W, {?PROBE, Probe, [self()|Chain]})
      end
      || {_, #{from := {W, _}, monitored := true}} <- gen_statem:reqids_to_list(Waitees)
    ],
    keep_state_and_data;

%% Scheduled probe
locked(cast, {?SCHEDULED_PROBE, To, Probe = {?PROBE, PTagProbe, _}}, #state{req_tag = PTag}) ->
    case PTagProbe =:= PTag of
        true ->
            gen_statem:cast(To, Probe);
        false ->
            ok
    end,
    keep_state_and_data;

%% Unknown cast
locked(cast, Msg, #state{worker = Worker}) ->
    gen_server:cast(Worker, Msg),
    keep_state_and_data.

%% We are fffrankly in a bit of a trouble
deadlocked(enter, _OldState, _State = #deadstate{deadlock = DL, deadlock_subscribers = Subs}) ->
    [ begin
          Who ! {?DEADLOCK, DL}
      end
      || Who <- Subs
    ],
    keep_state_and_data;

%% Someone subscribes to deadlocks — well, it just so happens that we have one
deadlocked(cast, {?DL_SUBSCRIBE, Who}, _State = #deadstate{deadlock = DL}) ->
    Who ! {?DEADLOCK, DL},
    keep_state_and_data;

deadlocked({call, From}, ?GET_CHILD, #deadstate{worker = Worker}) ->
    {keep_state_and_data, {reply, From, Worker}};

%% Incoming external call. We just tell them about the deadlock.
deadlocked({call, From}, Msg, State = #deadstate{deadlock = DL}) ->
    {Monitored, RawMsg} =
        case Msg of
            {?MONITORED_CALL, RMsg} -> {true, RMsg};
            _ ->
                ?DDM_DBG_ALIEN("~p: Received unmonitored call from '~p'", [self(), From]),
                {false, Msg}
        end,

    %% Forward to the process just in case
    gen_server:send_request(State#deadstate.worker, RawMsg),

    if Monitored ->
            {keep_state_and_data, {reply, From, {?DEADLOCK, DL}}};
       true ->
            keep_state_and_data
    end;

deadlocked({call, _From}, Msg, State) ->
    RawMsg =
        case Msg of
            {?MONITORED_CALL, RMsg} -> RMsg;
            _ -> Msg
        end,

    %% Forward to the process, who cares
    gen_server:send_request(State#deadstate.worker, RawMsg),
    keep_state_and_data;

%% Probe
deadlocked(cast, {?PROBE, _, _}, _State) ->
    keep_state_and_data;

%% Scheduled probe
deadlocked(cast, {?SCHEDULED_PROBE, _To, _Probe}, _State) ->
    keep_state_and_data;

%% Unknown cast
deadlocked(cast, Msg, #deadstate{worker = Worker}) ->
    gen_server:cast(Worker, Msg),
    keep_state_and_data;

%% Worker process exited 
deadlocked(info, {'EXIT', Worker, Reason}, #deadstate{worker=Worker}) ->
    ?DDM_DBG_DDMON("~p: Monitored process ~p exited with reason ~p. Stopping the monitor.", [self(), Worker, Reason]),
    {stop, Reason};

%% Someone wants to terminate us.
deadlocked(info, ExitMsg = {'EXIT', _From, _Reason}, #deadstate{worker=Worker}) ->
    forward_external_exit(ExitMsg, Worker),
    keep_state_and_data;

%% Incoming random message
deadlocked(info, Msg, #deadstate{worker = Worker, req_id = ReqId}) ->
    case gen_statem:check_response(Msg, ReqId) of
        no_reply ->
            %% Forward to the process, who cares
            Worker ! Msg,
            keep_state_and_data;
        {reply, {?DEADLOCK, _}} ->
            keep_state_and_data;
        {reply, Reply} ->
            %% A reply after deadlock?!
            error({'REPLY_AFTER_DEADLOCK', Reply});
        {error, {_Reason, _ServerRef}} ->
            %% Target died while we were deadlocked.
            keep_state_and_data
    end.
