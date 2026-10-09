------------------------------ MODULE PostureLogic ------------------------------
(***************************************************************************)
(* PlusCal model of  PostureLogic.onSample / reset  (PostureLogic.kt).     *)
(*                                                                         *)
(* The Kotlin class turns noisy gravity samples into one stable boolean,   *)
(* `active` = "the phone has been propped up like a bedside clock".  It    *)
(* uses two timestamps (goodSince, badSince) and two dwell times:          *)
(*   - start only after the posture was held  enterDwellMs  (1500 ms)      *)
(*   - stop  only after it was lost           exitDwellMs   (4000 ms)      *)
(* with hysteresis (a looser test while already active).                   *)
(*                                                                         *)
(* ABSTRACTION                                                             *)
(*  * Time is counted in sample periods (the sensor runs at ~5 Hz, so one  *)
(*    period ~ 200 ms; 1500 ms ~ EnterDwell, 4000 ms ~ ExitDwell).         *)
(*  * Kotlin stores absolute timestamps and only ever uses DIFFERENCES     *)
(*    (nowMs - since).  So the model stores the AGE of each timestamp      *)
(*    (goodAge = nowMs - goodSince), saturated at the largest dwell: ages  *)
(*    beyond it behave identically.  This keeps the state space finite    *)
(*    while behaviours stay infinite, which is what liveness needs.        *)
(*  * A sample is one of four kinds, from reading() and matches():         *)
(*      "match"   strict posture (lean >= 40, landscape)                   *)
(*      "band"    only the hysteresis-relaxed test passes (30..40 deg)     *)
(*      "nomatch" fails even the relaxed test                              *)
(*      "free"    free fall: reading() == null, the sample is ignored      *)
(*  * dt = number of sample periods since the previous sample.  The Kotlin *)
(*    code assumes dt = 1 always.  MaxGap > 1 lets the environment skip    *)
(*    samples (sensor throttled, CPU asleep, OEM batching...).             *)
(*                                                                         *)
(* GHOST VARIABLES (gLen, hLen, activatedWith, exitedWith) are not part   *)
(* of the implementation; they record the evidence the REQUIREMENT talks  *)
(* about, so the properties can be stated independently of the code.      *)
(*                                                                         *)
(* CONSTANTS                                                               *)
(*   EnterDwell, ExitDwell  dwell times in sample periods                  *)
(*   MaxGap      largest dt the environment may produce (1 = no gaps)      *)
(*   GapLimit    a gap longer than this is "no evidence" (requirement)     *)
(*   FixGaps     TRUE = the implementation clears its timers on such a gap *)
(*   AllowReset  TRUE = the environment may call reset() (unplug)          *)
(*   Obs         kinds of sample the environment may produce               *)
(*   InitActive  start state (to check the exit side of the liveness)      *)
(***************************************************************************)
EXTENDS Integers, TLC

CONSTANTS EnterDwell, ExitDwell, MaxGap, GapLimit, FixGaps, AllowReset, Obs, InitActive

ASSUME /\ EnterDwell \in 1..20 /\ ExitDwell \in 1..20
       /\ MaxGap \in 1..10 /\ GapLimit \in 1..10
       /\ FixGaps \in BOOLEAN /\ AllowReset \in BOOLEAN /\ InitActive \in BOOLEAN
       /\ Obs \subseteq {"match", "band", "nomatch", "free"}

NIL == -1                               \* a null timestamp (goodSince == null)
Max2(a, b) == IF a > b THEN a ELSE b
M == Max2(EnterDwell, ExitDwell)
Sat(x) == IF x > M THEN M ELSE x        \* ages saturate: beyond M nothing changes
Age(a, d) == IF a = NIL THEN NIL ELSE Sat(a + d)

RelaxOK(o)  == o \in {"match", "band"}  \* matches(r, relax = true)
StrictOK(o) == o = "match"              \* matches(r, relax = false)

(* --algorithm PostureLogic {
  variables
    \* ---- implementation state (the fields of PostureLogic.kt) ----
    goodAge = NIL,          \* nowMs - goodSince      (NIL = goodSince == null)
    badAge  = NIL,          \* nowMs - badSince
    active  = InitActive,   \* var active
    \* ---- environment: the last sample ----
    obs = "none", dt = 1, wasActive = InitActive,
    \* ---- ghost variables, used only by the properties ----
    gLen = NIL,             \* length of the unbroken run of observed strict "match" samples
    hLen = NIL,             \* length of the unbroken run of observed "nomatch" samples
    activatedWith = NIL,    \* gLen at the moment `active` last became TRUE
    exitedWith = NIL;       \* hLen at the moment `active` last became FALSE

  fair process (Sensor = 1)
  {
    Tick:
    while (TRUE) {
      either {
        \* ---- the environment delivers a sample, dt periods after the last ----
        with (d \in 1..MaxGap, o \in Obs) {
          dt := d;
          obs := o;
          \* The timers are timestamps, so they age with the clock.  The fix
          \* (FixGaps) clears them when the data has a hole in it: a gap is
          \* "unknown", not evidence that the posture was held / lost.
          goodAge := IF FixGaps /\ d > GapLimit THEN NIL ELSE Age(goodAge, d);
          badAge  := IF FixGaps /\ d > GapLimit THEN NIL ELSE Age(badAge, d);
        };
        OnSample:
        \* ---- PostureLogic.onSample, line for line ----
        wasActive := active;
        if (obs = "free") {
          skip;                                   \* val r = reading(..) ?: return active
        } else if (IF active THEN RelaxOK(obs) ELSE StrictOK(obs)) {
          \* if (matches(r, relax = active)) {
          badAge := NIL;                          \*   badSince = null
          if (~active) {                          \*   if (!active) {
            with (since = IF goodAge = NIL THEN 0 ELSE goodAge) {
              goodAge := since;                   \*     val since = goodSince ?: nowMs.also{..}
              if (since >= EnterDwell) {          \*     if (nowMs - since >= enterDwellMs)
                active := TRUE;                   \*        active = true
              };
            };
          };
        } else {
          goodAge := NIL;                         \*   goodSince = null
          if (active) {                           \*   if (active) {
            with (since = IF badAge = NIL THEN 0 ELSE badAge) {
              if (since >= ExitDwell) {           \*     if (nowMs - since >= exitDwellMs)
                active := FALSE;                  \*        active = false
                badAge := NIL;                    \*        badSince = null
              } else {
                badAge := since;                  \*     badSince = since
              };
            };
          };
        };
        Ghost:
        \* ---- bookkeeping for the properties (not part of the code) ----
        with (gb = IF dt > GapLimit THEN NIL ELSE gLen,
              hb = IF dt > GapLimit THEN NIL ELSE hLen,
              g  = IF obs = "match" THEN (IF gb = NIL THEN 0 ELSE Sat(gb + dt))
                   ELSE IF obs = "free" THEN (IF gb = NIL THEN NIL ELSE Sat(gb + dt))
                   ELSE NIL,
              h  = IF obs = "nomatch" THEN (IF hb = NIL THEN 0 ELSE Sat(hb + dt))
                   ELSE IF obs = "free" THEN (IF hb = NIL THEN NIL ELSE Sat(hb + dt))
                   ELSE NIL) {
          gLen := g;
          hLen := h;
          if (~wasActive /\ active) { activatedWith := g; };
          if (wasActive /\ ~active) { exitedWith := h; };
        };
      } or {
        \* ---- reset() : the charger was unplugged ----
        await AllowReset;
        active := FALSE; goodAge := NIL; badAge := NIL; wasActive := FALSE;
        gLen := NIL; hLen := NIL; activatedWith := NIL; exitedWith := NIL;
      };
    };
  }
} *)
\* BEGIN TRANSLATION (chksum(pcal) = "d32073" /\ chksum(tla) = "764ce3c5")
VARIABLES goodAge, badAge, active, obs, dt, wasActive, gLen, hLen, 
          activatedWith, exitedWith, pc

vars == << goodAge, badAge, active, obs, dt, wasActive, gLen, hLen, 
           activatedWith, exitedWith, pc >>

ProcSet == {1}

Init == (* Global variables *)
        /\ goodAge = NIL
        /\ badAge = NIL
        /\ active = InitActive
        /\ obs = "none"
        /\ dt = 1
        /\ wasActive = InitActive
        /\ gLen = NIL
        /\ hLen = NIL
        /\ activatedWith = NIL
        /\ exitedWith = NIL
        /\ pc = [self \in ProcSet |-> "Tick"]

Tick == /\ pc[1] = "Tick"
        /\ \/ /\ \E d \in 1..MaxGap:
                   \E o \in Obs:
                     /\ dt' = d
                     /\ obs' = o
                     /\ goodAge' = (IF FixGaps /\ d > GapLimit THEN NIL ELSE Age(goodAge, d))
                     /\ badAge' = (IF FixGaps /\ d > GapLimit THEN NIL ELSE Age(badAge, d))
              /\ pc' = [pc EXCEPT ![1] = "OnSample"]
              /\ UNCHANGED <<active, wasActive, gLen, hLen, activatedWith, exitedWith>>
           \/ /\ AllowReset
              /\ active' = FALSE
              /\ goodAge' = NIL
              /\ badAge' = NIL
              /\ wasActive' = FALSE
              /\ gLen' = NIL
              /\ hLen' = NIL
              /\ activatedWith' = NIL
              /\ exitedWith' = NIL
              /\ pc' = [pc EXCEPT ![1] = "Tick"]
              /\ UNCHANGED <<obs, dt>>

OnSample == /\ pc[1] = "OnSample"
            /\ wasActive' = active
            /\ IF obs = "free"
                  THEN /\ TRUE
                       /\ UNCHANGED << goodAge, badAge, active >>
                  ELSE /\ IF IF active THEN RelaxOK(obs) ELSE StrictOK(obs)
                             THEN /\ badAge' = NIL
                                  /\ IF ~active
                                        THEN /\ LET since == IF goodAge = NIL THEN 0 ELSE goodAge IN
                                                  /\ goodAge' = since
                                                  /\ IF since >= EnterDwell
                                                        THEN /\ active' = TRUE
                                                        ELSE /\ TRUE
                                                             /\ UNCHANGED active
                                        ELSE /\ TRUE
                                             /\ UNCHANGED << goodAge, active >>
                             ELSE /\ goodAge' = NIL
                                  /\ IF active
                                        THEN /\ LET since == IF badAge = NIL THEN 0 ELSE badAge IN
                                                  IF since >= ExitDwell
                                                     THEN /\ active' = FALSE
                                                          /\ badAge' = NIL
                                                     ELSE /\ badAge' = since
                                                          /\ UNCHANGED active
                                        ELSE /\ TRUE
                                             /\ UNCHANGED << badAge, active >>
            /\ pc' = [pc EXCEPT ![1] = "Ghost"]
            /\ UNCHANGED << obs, dt, gLen, hLen, activatedWith, exitedWith >>

Ghost == /\ pc[1] = "Ghost"
         /\ LET gb == IF dt > GapLimit THEN NIL ELSE gLen IN
              LET hb == IF dt > GapLimit THEN NIL ELSE hLen IN
                LET g == IF obs = "match" THEN (IF gb = NIL THEN 0 ELSE Sat(gb + dt))
                         ELSE IF obs = "free" THEN (IF gb = NIL THEN NIL ELSE Sat(gb + dt))
                         ELSE NIL IN
                  LET h == IF obs = "nomatch" THEN (IF hb = NIL THEN 0 ELSE Sat(hb + dt))
                           ELSE IF obs = "free" THEN (IF hb = NIL THEN NIL ELSE Sat(hb + dt))
                           ELSE NIL IN
                    /\ gLen' = g
                    /\ hLen' = h
                    /\ IF ~wasActive /\ active
                          THEN /\ activatedWith' = g
                          ELSE /\ TRUE
                               /\ UNCHANGED activatedWith
                    /\ IF wasActive /\ ~active
                          THEN /\ exitedWith' = h
                          ELSE /\ TRUE
                               /\ UNCHANGED exitedWith
         /\ pc' = [pc EXCEPT ![1] = "Tick"]
         /\ UNCHANGED << goodAge, badAge, active, obs, dt, wasActive >>

Sensor == Tick \/ OnSample \/ Ghost

Next == Sensor

Spec == /\ Init /\ [][Next]_vars
        /\ WF_vars(Sensor)

\* END TRANSLATION

-----------------------------------------------------------------------------
(* PROPERTIES                                                              *)

\* States between steps; invariants are checked here, not in the middle of
\* one onSample call (which is a single atomic callback on Android).
Quiescent == pc[1] = "Tick"

TypeOK ==
  /\ goodAge \in {NIL} \cup 0..M /\ badAge \in {NIL} \cup 0..M
  /\ active \in BOOLEAN /\ wasActive \in BOOLEAN
  /\ gLen \in {NIL} \cup 0..M /\ hLen \in {NIL} \cup 0..M
  /\ activatedWith \in {NIL} \cup 0..M /\ exitedWith \in {NIL} \cup 0..M

\* R1  Start only after the posture was really held.  `active` may be TRUE
\*     only if, when it turned on, the phone had been seen in the strict
\*     posture for at least EnterDwell with no hole in the data.
EnterSound ==
  Quiescent /\ active => (activatedWith # NIL /\ activatedWith >= EnterDwell)

\* R2  Stop only after the posture was really lost for ExitDwell.
ExitSound ==
  Quiescent /\ ~active /\ exitedWith # NIL => exitedWith >= ExitDwell

\* R3  Hysteresis: a sample that still passes the relaxed test never turns
\*     an active posture off.
HysteresisKeepsActive ==
  pc[1] = "Ghost" => ((wasActive /\ RelaxOK(obs)) => active)

\* R4  A free-fall sample is ignored: it changes nothing.
FreeFallIgnored ==
  pc[1] = "Ghost" => (obs = "free" => active = wasActive)

\* R5  No flapping: active can only turn on from a state that was off, and
\*     only turn off from a state that was on (a trivially true sanity check
\*     that the ghost bookkeeping is consistent).
GhostConsistent ==
  Quiescent => ~(activatedWith # NIL /\ active /\ activatedWith < EnterDwell)

\* L1  If the phone is held in the strict posture from some point on, the
\*     posture becomes active (run with Obs = {"match"}, MaxGap = 1).
EnterLive == <>active

\* L2  If it is lost from some point on, active turns off (run with
\*     Obs = {"nomatch"}, InitActive = TRUE).
ExitLive == <>(~active)

=============================================================================
