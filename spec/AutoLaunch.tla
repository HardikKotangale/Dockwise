------------------------------ MODULE AutoLaunch ------------------------------
(***************************************************************************)
(* PlusCal model of the auto-launch feature: how StandbyService decides to *)
(* open Dockwise when the phone is docked, and how MainActivity closes it  *)
(* again when the charger is unplugged.                                    *)
(*                                                                         *)
(*   StandbyService.setCharging / onSensorChanged / openApp / notifyToOpen *)
(*   MainActivity.launchedByAuto / onNewIntent / exitReceiver              *)
(*                                                                         *)
(* The posture debounce itself (PostureLogic) is specified separately in   *)
(* PostureLogic.tla; here its output is just "the posture became active"  *)
(* or "inactive" (PostureChange).                                          *)
(*                                                                         *)
(* Everything runs as ONE process that picks the next event, because every *)
(* Android callback here (broadcast receiver, sensor callback, handler     *)
(* message, activity lifecycle, user tap) runs atomically on one of two    *)
(* looper threads and they interleave arbitrarily.                         *)
(*                                                                         *)
(* THE REQUIREMENTS (what the feature promises in the README):             *)
(*  R1  Unplugging never closes a screen the USER is looking at and       *)
(*      opened or took over themselves.                                    *)
(*  R2  Nothing the watcher opened is left open after the charger is out.  *)
(*  R3  When docked and charging, the user is eventually either shown      *)
(*      Dockwise or offered a "tap to open" notification.                  *)
(*                                                                         *)
(* FIX SWITCHES (FALSE = the code as it was, TRUE = the fix):              *)
(*  FixNewIntent  onNewIntent must not claim a screen already visible      *)
(*  FixLeave      leaving the app (Home) ends the "opened by auto" claim   *)
(*  FixRace       unplugging cancels a launch still waiting in postDelayed *)
(*  FixWatchdog   a launch that silently did nothing is noticed and the    *)
(*                notification is posted instead                           *)
(***************************************************************************)
EXTENDS Naturals, TLC

CONSTANTS FixNewIntent, FixLeave, FixRace, FixWatchdog,
          AllowUser, AllowUnplug, AllowPostureOff

ASSUME /\ FixNewIntent \in BOOLEAN /\ FixLeave \in BOOLEAN
       /\ FixRace \in BOOLEAN /\ FixWatchdog \in BOOLEAN
       /\ AllowUser \in BOOLEAN /\ AllowUnplug \in BOOLEAN
       /\ AllowPostureOff \in BOOLEAN

(* --algorithm AutoLaunch {
  variables
    \* ---- StandbyService ----
    charging = FALSE,        \* var charging
    wasActive = FALSE,       \* var wasActive (the edge detector)
    pendingLaunch = FALSE,   \* main.postDelayed({ startActivity(..) }, 700) is queued
    notified = FALSE,        \* the "tap to open" notification is showing
    \* ---- MainActivity ----
    appTask = FALSE,         \* the activity exists (task is alive)
    visible = FALSE,         \* it is on screen (resumed)
    launchedByAuto = FALSE,  \* var launchedByAuto
    \* ---- ghost variables (for the requirements only) ----
    userOwned = FALSE,              \* the user opened it / is using it themselves
    closedWhileUserVisible = FALSE; \* an unplug closed a screen the user was looking at

  fair process (World = 1)
  {
    Step:
    while (TRUE) {
      either {
        \* ---- ACTION_POWER_CONNECTED : setCharging(true) ----
        await ~charging;
        charging := TRUE;
      } or {
        \* ---- ACTION_POWER_DISCONNECTED : setCharging(false) ----
        await charging /\ AllowUnplug;
        charging := FALSE;
        wasActive := FALSE;                         \* logic.reset(); wasActive = false
        if (FixRace) { pendingLaunch := FALSE; };   \* main.removeCallbacks(launch)
        \* sendBroadcast(ACTION_EXIT); the activity's exitReceiver:
        \*     if (launchedByAuto) finishAndRemoveTask()
        if (appTask /\ launchedByAuto) {
          closedWhileUserVisible := closedWhileUserVisible \/ (visible /\ userOwned);
          appTask := FALSE; visible := FALSE; launchedByAuto := FALSE; userOwned := FALSE;
        };
      } or {
        \* ---- onSensorChanged : the posture's debounced result changed ----
        await charging;                              \* sensors only run while charging
        with (p \in IF AllowPostureOff THEN BOOLEAN ELSE {TRUE}) {
          \* NB: PlusCal runs a step's statements in order, so the edge test must
          \* come BEFORE `wasActive := p`, or it would read the new value.
          if (p /\ ~wasActive) {
            \* if (active && !wasActive && charging) openApp()
            with (path \in {"overlay", "notify"}) {
              if (path = "overlay") { pendingLaunch := TRUE; }   \* overlay added, launch in 700 ms
              else { notified := TRUE; };                        \* notifyToOpen()
            };
          };
          wasActive := p;                                        \* wasActive = active
        };
      } or {
        \* ---- the postDelayed(.., 700) fires: startActivity(appIntent()) ----
        await pendingLaunch;
        pendingLaunch := FALSE;
        with (res \in {"ok", "silent"}) {
          if (res = "ok") {
            if (~appTask) {
              \* onCreate: launchedByAuto = intent.getBooleanExtra("auto")
              appTask := TRUE; launchedByAuto := TRUE; userOwned := FALSE;
            } else {
              \* onNewIntent: if (extra auto) launchedByAuto = true
              if (~FixNewIntent \/ ~visible) { launchedByAuto := TRUE; };
              if (~visible) { userOwned := FALSE; };
            };
            visible := TRUE;
          } else {
            \* Android refused to start it from the background (BAL_BLOCK) and said
            \* nothing: startActivity() returns normally, no exception, no callback.
            if (FixWatchdog /\ ~visible) { notified := TRUE; };
          };
        };
      } or {
        \* ---- the user taps the launcher icon ----
        \* (only possible when Dockwise is NOT on screen: the launcher is)
        await AllowUser /\ ~visible;
        if (~appTask) { appTask := TRUE; launchedByAuto := FALSE; };   \* onCreate, no extra
        visible := TRUE; userOwned := TRUE;
      } or {
        \* ---- the user presses Home (onUserLeaveHint) ----
        await AllowUser /\ visible;
        visible := FALSE;
        if (FixLeave) { launchedByAuto := FALSE; };
      } or {
        \* ---- the user swipes the app away ----
        await AllowUser /\ appTask;
        appTask := FALSE; visible := FALSE; launchedByAuto := FALSE; userOwned := FALSE;
      };
    };
  }
} *)
\* BEGIN TRANSLATION
VARIABLES charging, wasActive, pendingLaunch, notified, appTask, visible, 
          launchedByAuto, userOwned, closedWhileUserVisible

vars == << charging, wasActive, pendingLaunch, notified, appTask, visible, 
           launchedByAuto, userOwned, closedWhileUserVisible >>

ProcSet == {1}

Init == (* Global variables *)
        /\ charging = FALSE
        /\ wasActive = FALSE
        /\ pendingLaunch = FALSE
        /\ notified = FALSE
        /\ appTask = FALSE
        /\ visible = FALSE
        /\ launchedByAuto = FALSE
        /\ userOwned = FALSE
        /\ closedWhileUserVisible = FALSE

World == \/ /\ ~charging
            /\ charging' = TRUE
            /\ UNCHANGED <<wasActive, pendingLaunch, notified, appTask, visible, launchedByAuto, userOwned, closedWhileUserVisible>>
         \/ /\ charging /\ AllowUnplug
            /\ charging' = FALSE
            /\ wasActive' = FALSE
            /\ IF FixRace
                  THEN /\ pendingLaunch' = FALSE
                  ELSE /\ TRUE
                       /\ UNCHANGED pendingLaunch
            /\ IF appTask /\ launchedByAuto
                  THEN /\ closedWhileUserVisible' = (closedWhileUserVisible \/ (visible /\ userOwned))
                       /\ appTask' = FALSE
                       /\ visible' = FALSE
                       /\ launchedByAuto' = FALSE
                       /\ userOwned' = FALSE
                  ELSE /\ TRUE
                       /\ UNCHANGED << appTask, visible, launchedByAuto, 
                                       userOwned, closedWhileUserVisible >>
            /\ UNCHANGED notified
         \/ /\ charging
            /\ \E p \in IF AllowPostureOff THEN BOOLEAN ELSE {TRUE}:
                 /\ IF p /\ ~wasActive
                       THEN /\ \E path \in {"overlay", "notify"}:
                                 IF path = "overlay"
                                    THEN /\ pendingLaunch' = TRUE
                                         /\ UNCHANGED notified
                                    ELSE /\ notified' = TRUE
                                         /\ UNCHANGED pendingLaunch
                       ELSE /\ TRUE
                            /\ UNCHANGED << pendingLaunch, notified >>
                 /\ wasActive' = p
            /\ UNCHANGED <<charging, appTask, visible, launchedByAuto, userOwned, closedWhileUserVisible>>
         \/ /\ pendingLaunch
            /\ pendingLaunch' = FALSE
            /\ \E res \in {"ok", "silent"}:
                 IF res = "ok"
                    THEN /\ IF ~appTask
                               THEN /\ appTask' = TRUE
                                    /\ launchedByAuto' = TRUE
                                    /\ userOwned' = FALSE
                               ELSE /\ IF ~FixNewIntent \/ ~visible
                                          THEN /\ launchedByAuto' = TRUE
                                          ELSE /\ TRUE
                                               /\ UNCHANGED launchedByAuto
                                    /\ IF ~visible
                                          THEN /\ userOwned' = FALSE
                                          ELSE /\ TRUE
                                               /\ UNCHANGED userOwned
                                    /\ UNCHANGED appTask
                         /\ visible' = TRUE
                         /\ UNCHANGED notified
                    ELSE /\ IF FixWatchdog /\ ~visible
                               THEN /\ notified' = TRUE
                               ELSE /\ TRUE
                                    /\ UNCHANGED notified
                         /\ UNCHANGED << appTask, visible, launchedByAuto, 
                                         userOwned >>
            /\ UNCHANGED <<charging, wasActive, closedWhileUserVisible>>
         \/ /\ AllowUser /\ ~visible
            /\ IF ~appTask
                  THEN /\ appTask' = TRUE
                       /\ launchedByAuto' = FALSE
                  ELSE /\ TRUE
                       /\ UNCHANGED << appTask, launchedByAuto >>
            /\ visible' = TRUE
            /\ userOwned' = TRUE
            /\ UNCHANGED <<charging, wasActive, pendingLaunch, notified, closedWhileUserVisible>>
         \/ /\ AllowUser /\ visible
            /\ visible' = FALSE
            /\ IF FixLeave
                  THEN /\ launchedByAuto' = FALSE
                  ELSE /\ TRUE
                       /\ UNCHANGED launchedByAuto
            /\ UNCHANGED <<charging, wasActive, pendingLaunch, notified, appTask, userOwned, closedWhileUserVisible>>
         \/ /\ AllowUser /\ appTask
            /\ appTask' = FALSE
            /\ visible' = FALSE
            /\ launchedByAuto' = FALSE
            /\ userOwned' = FALSE
            /\ UNCHANGED <<charging, wasActive, pendingLaunch, notified, closedWhileUserVisible>>

Next == World

Spec == /\ Init /\ [][Next]_vars
        /\ WF_vars(World)

\* END TRANSLATION

-----------------------------------------------------------------------------
(* PROPERTIES                                                              *)

TypeOK ==
  /\ {charging, wasActive, pendingLaunch, notified, appTask, visible,
      launchedByAuto, userOwned, closedWhileUserVisible} \subseteq BOOLEAN

\* R1  never close a screen the user is looking at and owns
NoSurpriseClose == ~closedWhileUserVisible

\* R2  once the charger is out, nothing the watcher opened is left open
UnplugLeavesNothingAutoOpened == ~charging => ~(appTask /\ launchedByAuto)

\* consistency of the bookkeeping itself
FlagOnlyWithTask == launchedByAuto => appTask
WasActiveImpliesCharging == wasActive => charging

\* R3  docked and charging: the user is eventually shown the app or offered it
\*     (checked with the user and the charger left alone: AllowUser = AllowUnplug
\*      = AllowPostureOff = FALSE)
EventuallyOffered == <>(visible \/ notified)

=============================================================================
