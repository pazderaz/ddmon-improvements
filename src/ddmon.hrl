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
-define(DDM_DBG_MON_REG(Fmt, Args),
    logger:warning("[MON_REG] " ++ Fmt, Args, #{module => ?MODULE, subsystem => ddmon})).
-else.
-define(DDM_DBG_PROBE(_Fmt, _Args), ok).
-define(DDM_DBG_STATE(_Fmt, _Args), ok).
-define(DDM_DBG_MON_REG(_Fmt, _Args), ok).
-endif.

-if(defined(DDM_DEBUG) orelse defined(DDM_REPORT)).
-define(DDM_WARN_DEADLOCK(Fmt, Args),
    logger:warning("[DEADLOCK] (!) " ++ Fmt, Args, #{module => ?MODULE, subsystem => ddmon})).
-else.
-define(DDM_WARN_DEADLOCK(_Fmt, _Args), ok).
-endif.

-define(MON_PID, '$gen_monitored_pid').
-define(CALLBACK_MOD, '$gen_monitored_mod').
-define(PROBE, '$gen_monitored_probe').
-define(DEADLOCK, '$ddmon_deadlock_spread').
-define(MONITORED_CALL, '$ddmon_monitored_call').
-define(SCHEDULED_PROBE, '$ddmon_probe_scheduled').
-define(DL_SUBSCRIBE, '$ddmon_dl_subscribe').

-define(LOG_INDENT_SIZE, '$log_indent_size').
