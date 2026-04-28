%% Debug logging macros. Enable with a Config entry:
%% config :ddmon,
%%  ddm_debug: "1"
%%
%% Usage: ?DDM_DBG_PROBE("format string ~p", [Args]).

-ifdef(DDM_DEBUG).
-define(DDM_DBG_PROBE(Fmt, Args),
    logger:debug("[PROBE] " ++ Fmt, Args, #{module => ?MODULE, subsystem => ddmon})).
-define(DDM_DBG_STATE(Fmt, Args),
    logger:debug("[STATE] " ++ Fmt, Args, #{module => ?MODULE, subsystem => ddmon})).
-define(DDM_DBG_ALIEN(Fmt, Args),
    logger:debug("[ALIEN] " ++ Fmt, Args, #{module => ?MODULE, subsystem => ddmon})).
-define(DDM_DBG_DDMON(Fmt, Args),
    logger:debug("[DDMON] " ++ Fmt, Args, #{module => ?MODULE, subsystem => ddmon})).
-else.
-define(DDM_DBG_PROBE(_Fmt, _Args), ok).
-define(DDM_DBG_STATE(_Fmt, _Args), ok).
-define(DDM_DBG_ALIEN(_Fmt, _Args), ok).
-define(DDM_DBG_DDMON(_Fmt, _Args), ok).
-endif.

-if(defined(DDM_DEBUG) orelse defined(DDM_REPORT)).
-define(DDM_WARN_DEADLOCK(Fmt, Args),
    logger:warning("[DEADLOCK] (!) " ++ Fmt, Args, #{module => ?MODULE, subsystem => ddmon})).
-else.
-define(DDM_WARN_DEADLOCK(_Fmt, _Args), ok).
-endif.

-define(MON_PID, '$gen_monitored_pid').
-define(WORKER_MODULE, '$gen_worker_module').
-define(CALLBACK_MOD, '$gen_monitored_mod').
-define(PROBE, '$gen_monitored_probe').
-define(DEADLOCK, '$ddmon_deadlock_spread').
-define(MONITORED_CALL, '$ddmon_monitored_call').
-define(SCHEDULED_PROBE, '$ddmon_probe_scheduled').
-define(DL_SUBSCRIBE, '$ddmon_dl_subscribe').
-define(GET_CHILD, '$get_child').

-define(LOG_INDENT_SIZE, '$log_indent_size').
