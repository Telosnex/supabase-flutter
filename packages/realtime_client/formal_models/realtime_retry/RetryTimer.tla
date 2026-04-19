-------------------------- MODULE RetryTimer --------------------------
(*
 * TLA+ model of RetryTimer — the exponential-backoff scheduler used
 * by RealtimeClient (`reconnectTimer`) and by every RealtimeChannel
 * (`_rejoinTimer`).
 *
 * Dart source: packages/realtime_client/lib/src/retry_timer.dart
 *
 *   class RetryTimer {
 *     Timer? _timer;
 *     int _tries = 0;
 *
 *     void reset() {
 *       _tries = 0;
 *       if (_timer != null) _timer!.cancel();
 *     }
 *
 *     void scheduleTimeout() {
 *       if (_timer != null) _timer!.cancel();
 *       _timer = Timer(Duration(milliseconds: timerCalc(_tries + 1)),
 *                      () {
 *         _tries = _tries + 1;
 *         callback();
 *       });
 *     }
 *
 *     static TimerCalculation createRetryFunction({
 *       int firstDelay = 1000,
 *       int maxDelay   = 10000,
 *     }) {
 *       return (int tries) {
 *         final shiftAmount = (tries - 1) > maxShift ? maxShift : tries - 1;
 *         final delay = firstDelay << shiftAmount;
 *         return delay > maxDelay ? maxDelay : delay;
 *       };
 *     }
 *   }
 *
 * ═══════════════════════════════════════════════════════════════════════
 *                       DESIGN
 * ═══════════════════════════════════════════════════════════════════════
 *
 *   Two Boolean/natural state variables:
 *     tries  — the _tries field (monotone within a reset epoch)
 *     armed  — _timer is non-null AND will fire
 *
 *   Actions:
 *     ScheduleTimeout — cancel any pending timer, arm a new one.
 *                       tries unchanged.
 *     Fire            — the armed timer's callback runs.  tries += 1;
 *                       armed → FALSE.
 *     Reset           — cancel pending, set tries = 0, armed = FALSE.
 *
 *   Key guarantee: at most ONE timer is ever alive.  A call to
 *   scheduleTimeout while armed cancels the previous timer — the
 *   callback of the cancelled timer will NOT fire, because Dart
 *   Timer.cancel() prevents a cancelled Timer from invoking its
 *   callback.
 *
 *   Liveness (not checked by default): ScheduleTimeout eventually
 *   leads to Fire unless Reset / another ScheduleTimeout preempts.
 *
 * ═══════════════════════════════════════════════════════════════════════
 *                       INVARIANTS
 * ═══════════════════════════════════════════════════════════════════════
 *
 *   AtMostOneArmed
 *       `armed` is Boolean — there is no way to arm two timers.
 *
 *   TriesBounded
 *       tries ≤ MaxTries (state-space cap).  Fire is guarded to
 *       preserve this.
 *
 *   ResetDisarms         (two-state)
 *       A step that clears tries to zero also clears armed.
 *
 *   FireIncreasesTries   (two-state)
 *       A step that transitions armed TRUE → FALSE and increases
 *       tries must be a Fire: tries' = tries + 1.
 *
 *   ScheduleDoesNotChangeTries   (two-state)
 *       A step that transitions ~armed → armed (pure schedule) must
 *       leave tries unchanged.
 *
 *   NoFireWithoutArmed   (two-state)
 *       tries can only increase while armed is TRUE.
 *
 *   NoDoubleFireWithoutReschedule  (two-state)
 *       Two consecutive tries increments require an intervening
 *       ScheduleTimeout.  Encoded by Fire's `armed` guard and
 *       armed' = FALSE postcondition.
 *
 * How to run:
 *   tlc RetryTimer.tla -config RetryTimer.cfg -workers auto -deadlock
 *)

EXTENDS Naturals

CONSTANTS
    MaxTries       \* Bound on _tries (state-space cap)

VARIABLES
    tries,         \* Nat — _tries
    armed          \* BOOLEAN — _timer armed

vars == <<tries, armed>>

TypeOK ==
    /\ tries \in 0..MaxTries
    /\ armed \in BOOLEAN

Init ==
    /\ tries = 0
    /\ armed = FALSE

\* scheduleTimeout(): cancel previous (no-op if none), arm a new timer.
\* Modelled so that scheduling while already armed is permitted (the
\* Dart code cancels the prior Timer first) — armed stays TRUE.
ScheduleTimeout ==
    /\ armed' = TRUE
    /\ UNCHANGED tries

\* The armed timer fires: callback runs and _tries increments.
Fire ==
    /\ armed
    /\ tries < MaxTries
    /\ armed' = FALSE
    /\ tries' = tries + 1

\* reset(): cancel pending + zero the tries counter.
Reset ==
    /\ tries' = 0
    /\ armed' = FALSE

Next == ScheduleTimeout \/ Fire \/ Reset

Spec == Init /\ [][Next]_vars

\* =====================================================================
\* Safety invariants
\* =====================================================================

\* Structural — `armed` is a Boolean.
AtMostOneArmed == armed \in BOOLEAN

TriesBounded == tries \in 0..MaxTries

\* =====================================================================
\* Two-state (temporal) properties
\* =====================================================================

\* A step that clears tries to zero also disarms.  Encoded so that
\* "the only action that zeroes a positive tries value is Reset".
ResetDisarms ==
    [][ (tries > 0 /\ tries' = 0) => armed' = FALSE ]_vars

\* Fire is the only action that increments tries by exactly 1 while
\* disarming.  Equivalent: "tries increased and armed went T→F" ⇒
\* tries' = tries + 1.
FireIncreasesTries ==
    [][ (tries' > tries /\ armed /\ ~armed') => tries' = tries + 1 ]_vars

\* A pure schedule (~armed → armed) never changes tries.
ScheduleDoesNotChangeTries ==
    [][ (~armed /\ armed') => tries' = tries ]_vars

\* tries can only increase while the timer was armed at the start
\* of the step.
NoFireWithoutArmed ==
    [][ tries' > tries => armed ]_vars

\* After Fire disarms, a second tries-increment requires an
\* intervening ScheduleTimeout (armed must be re-set first).
\* Implicit in Fire's `armed` guard; two consecutive Fires require
\* intermediate ScheduleTimeout.
NoDoubleFireWithoutReschedule ==
    [][ (~armed /\ tries' > tries) => FALSE ]_vars

=========================================================================
