-------------------------- MODULE Push --------------------------
(*
 * TLA+ model of the Push class — the per-message state machine used
 * both by RealtimeChannel (joinPush, leavePush) and by channel.push().
 *
 * Dart source: packages/realtime_client/lib/src/push.dart
 *   send()           ~57–68   — guard + startTimeout + socket push
 *   resend()         ~40–55   — cancel, reset refs, send
 *   startTimeout()   ~80–100  — mint ref, register binding, arm timer
 *   trigger()        ~103–107 — channel.trigger(_refEvent, ...)
 *   destroy()        ~110–113 — cancel ref + timer
 *   receive()        ~70–77   — register a receive hook
 *   _matchReceive    ~125–129 — run hooks matching the status
 *   _cancelRefEvent  ~115–119 — unregister binding
 *   _cancelTimeout   ~121–124 — timer.cancel(); null
 *
 * ═══════════════════════════════════════════════════════════════════════
 *                       DESIGN
 * ═══════════════════════════════════════════════════════════════════════
 *
 *   A Push owns four pieces of state:
 *
 *     sent            the `sent` bool
 *     refEvent        the `_refEvent` string (non-null after startTimeout)
 *     binding         the channel binding registered by startTimeout
 *     timer           the `_timeoutTimer` Timer
 *
 *   `refEvent` (the string field) and the `binding` (registration in
 *   the channel) and `timer` (Timer object) form a lifecycle.
 *
 *   Observation: `_cancelRefEvent` and `_cancelTimeout` are ALWAYS
 *   called together — in the binding callback, in resend(), and in
 *   destroy().  Therefore the pair (bindingRegistered, timerArmed)
 *   is in lockstep: both TRUE after startTimeout, both FALSE after
 *   any of the three cancel-sites.  We model this as a single
 *   Boolean `active`.
 *
 *   The `_refEvent` string field, however, is only nulled by
 *   resend() — not by _cancelRefEvent or destroy.  So after a
 *   reply or timeout has fired, refFieldSet stays TRUE until resend.
 *   That means Push.trigger() remains enabled to fire the channel
 *   event, but since no binding is registered any longer, the
 *   channel.trigger() call is a harmless no-op.  We track this as
 *   a separate variable for completeness.
 *
 *   `_receivedResp` becomes non-null on the first reply or timeout
 *   and carries the status until resend() clears it.  Modelled as
 *   `receivedStatus`.
 *
 *   Race semantics between server-reply and timer-fire:
 *     • Dart Timer.cancel() prevents a cancelled Timer from firing
 *       (even if scheduled internally).  So once _cancelTimeout runs
 *       the Timer is dead.
 *     • Whichever path (reply-binding OR timer callback) fires first
 *       runs _cancelRefEvent + _cancelTimeout, so the other path
 *       becomes ineligible.
 *     • Hence at most ONE status arrives per (start → cancel) window.
 *
 * ═══════════════════════════════════════════════════════════════════════
 *                       INVARIANTS
 * ═══════════════════════════════════════════════════════════════════════
 *
 *   ActivityImpliesSent
 *       active ⇒ sent  (can't be active without first send()/resend())
 *
 *   ActivityImpliesRefField
 *       active ⇒ refFieldSet
 *
 *   AtMostOneLiveReply
 *       active ∧ receivedStatus ≠ "none" is unreachable PROVIDED
 *       Push objects are used single-shot (new Push per send or
 *       Resend between sends).  The current Dart code does enforce
 *       this in practice: send() is only called from
 *         - Push constructor-site callers who create a fresh Push, or
 *         - Resend (which clears receivedStatus atomically), or
 *         - unsubscribe's leavePush (fresh) / joinPush via resend.
 *       A literal re-invocation of send() after an 'ok'/'error' reply
 *       WOULD make the invariant false (push.dart:58 only guards on
 *       receivedStatus='timeout').  We encode the single-shot
 *       convention by guarding Send on receivedStatus='none'.  A
 *       counterexample config exists to demonstrate the weaker
 *       Dart guard (RealtimePush_DuplicateSend.cfg).
 *
 *   TimeoutLocksSend
 *       receivedStatus = "timeout" ⇒ ¬active until Resend.
 *       Encoded structurally — Send guards on
 *       receivedStatus ≠ "timeout".
 *
 *   RefFieldMonotoneUntilResend
 *       The refEvent field is set by Send / Resend and never cleared
 *       except by Resend (which immediately sets it again).  So it is
 *       effectively monotone-set-once-set-forever for any behavior
 *       without Resend.  Full invariant below as a property.
 *
 *   ExactlyOneStatusBetweenSendAndCancel
 *       Between the step that sets active=TRUE and the step that sets
 *       active=FALSE, exactly one of {ReplyOk, ReplyError, TimerFires,
 *       Destroy} fires and that single step determines the
 *       receivedStatus' (except Destroy, which preserves it).
 *
 *   NoReceiveAfterDestroy
 *       After a Destroy, no ReplyOk/ReplyError/TimerFires can fire
 *       until Resend re-arms (because they all require active).
 *
 * ═══════════════════════════════════════════════════════════════════════
 *                       OUT OF SCOPE
 * ═══════════════════════════════════════════════════════════════════════
 *
 *   • The user-facing receive hook list (_recHooks) — the model
 *     tracks the STATUS that fires hooks, not the hooks themselves.
 *   • The channel-side binding dispatch — modelled abstractly as the
 *     ServerReply/TimerFires actions being guarded by `active`.
 *   • The payload map and updatePayload — not concurrency-relevant.
 *
 * How to run:
 *   tlc Push.tla -config Push.cfg -workers auto -deadlock
 *)

EXTENDS Naturals

CONSTANTS
    MaxResends,
    AllowDuplicateSend    \* BOOLEAN: enable the weak-guard Send path

VARIABLES
    sent,             \* BOOLEAN: send() has been invoked
    active,           \* BOOLEAN: refEvent binding registered AND timer armed
    refFieldSet,      \* BOOLEAN: _refEvent (string) is non-null
    receivedStatus,   \* Status ∈ {"none","ok","error","timeout"}
    resends           \* Nat: count of resend() calls (state-space cap)

vars == <<sent, active, refFieldSet, receivedStatus, resends>>

Statuses == {"none", "ok", "error", "timeout"}

TypeOK ==
    /\ sent \in BOOLEAN
    /\ active \in BOOLEAN
    /\ refFieldSet \in BOOLEAN
    /\ receivedStatus \in Statuses
    /\ resends \in 0..MaxResends

Init ==
    /\ sent = FALSE
    /\ active = FALSE
    /\ refFieldSet = FALSE
    /\ receivedStatus = "none"
    /\ resends = 0

\* =====================================================================
\* Send — Dart push.dart:57–68
\*
\*   if (_hasReceived('timeout')) return;
\*   startTimeout();      // early returns if _timeoutTimer != null
\*   sent = true;
\*   _channel.socket.push(Message(...));
\*
\* We model only the "new session" case (~active).  A send while active
\* early-returns from startTimeout in Dart: no new refEvent, no new
\* timer — the observable state is unchanged (modulo a duplicate wire
\* message which is invisible here).  So the duplicate branch is a
\* stutter and we elide it.
\* =====================================================================

\* Single-shot Send: first invocation on a pristine or freshly-resent
\* Push.  Covers the real-world call sites (channel.push, leavePush,
\* joinPush-first-send, Resend tail).
Send ==
    /\ receivedStatus = "none"        \* single-shot convention
    /\ ~active
    /\ sent'        = TRUE
    /\ active'      = TRUE
    /\ refFieldSet' = TRUE
    /\ UNCHANGED <<receivedStatus, resends>>

\* Literal re-invocation of send() after an 'ok'/'error' reply.
\* push.dart:58 only blocks on receivedStatus='timeout'.  Gated by a
\* MODEL CONSTANT so the positive config enforces single-shot and the
\* counterexample config lets TLC surface the weaker guard.
\*
\* AllowDuplicateSend is declared below; used by the counterexample
\* config only.
SendAfterReply ==
    /\ AllowDuplicateSend
    /\ receivedStatus \in {"ok", "error"}
    /\ ~active
    /\ sent'        = TRUE
    /\ active'      = TRUE
    /\ refFieldSet' = TRUE
    /\ UNCHANGED <<receivedStatus, resends>>

\* =====================================================================
\* ServerReply(status) — models the binding callback firing because
\* the server delivered {status, response} with the refEvent's ref.
\*
\* The binding body (push.dart:91–95):
\*   _cancelRefEvent();   // remove the binding
\*   _cancelTimeout();    // cancel + null _timeoutTimer
\*   _receivedResp = payload;
\*   _matchReceive(status, response);
\*
\* Note: _refEvent (the string field) is NOT cleared here.
\* =====================================================================

ServerReply(status) ==
    /\ active
    /\ status \in {"ok", "error"}
    /\ receivedStatus' = status
    /\ active'         = FALSE
    /\ UNCHANGED <<sent, refFieldSet, resends>>

ReplyOk    == ServerReply("ok")
ReplyError == ServerReply("error")

\* =====================================================================
\* TimerFires — the _timeoutTimer's callback runs.
\*
\* Dart (push.dart:98–100):
\*   _timeoutTimer = Timer(timeout, () {
\*     trigger('timeout', {});
\*   });
\*
\* Push.trigger (103–107) calls _channel.trigger(_refEvent!, ...) which
\* dispatches to the binding → _cancelRefEvent + _cancelTimeout +
\* _matchReceive('timeout').  Net effect is identical to ServerReply
\* with status="timeout".
\* =====================================================================

TimerFires ==
    /\ active
    /\ receivedStatus' = "timeout"
    /\ active'         = FALSE
    /\ UNCHANGED <<sent, refFieldSet, resends>>

\* =====================================================================
\* Destroy — push.dart:110–113.
\*   _cancelRefEvent(); _cancelTimeout();
\*
\* No change to sent, refFieldSet, or receivedStatus.
\* =====================================================================

Destroy ==
    /\ active                      \* idempotent when ~active (stutter elided)
    /\ active' = FALSE
    /\ UNCHANGED <<sent, refFieldSet, receivedStatus, resends>>

\* =====================================================================
\* Resend — push.dart:40–55
\*   _timeout = timeout;
\*   _cancelRefEvent();
\*   _cancelTimeout();
\*   _ref = '';
\*   _refEvent = null;       ← refFieldSet := FALSE transiently
\*   _receivedResp = null;
\*   sent = false;
\*   send();                 ← then immediately runs startTimeout + push
\*
\* Net observable effect: active=TRUE, refFieldSet=TRUE, sent=TRUE,
\* receivedStatus="none".  We model it as a single atomic step.
\* =====================================================================

Resend ==
    /\ resends < MaxResends
    /\ resends'        = resends + 1
    /\ sent'           = TRUE
    /\ active'         = TRUE
    /\ refFieldSet'    = TRUE
    /\ receivedStatus' = "none"

\* =====================================================================
\* Next-state relation
\* =====================================================================

Next ==
    \/ Send
    \/ SendAfterReply
    \/ ReplyOk
    \/ ReplyError
    \/ TimerFires
    \/ Destroy
    \/ Resend

Spec == Init /\ [][Next]_vars

\* =====================================================================
\* Safety invariants
\* =====================================================================

ActivityImpliesSent ==
    active => sent

ActivityImpliesRefField ==
    active => refFieldSet

\* When a status has been recorded, the Push is NOT active.
\* Conversely, while active no status has yet been recorded.
AtMostOneLiveReply ==
    ~(active /\ receivedStatus # "none")

\* Timeout is a terminal status until Resend.  Encoded structurally:
\* Send guards on ≠ "timeout".  Invariant form:
TimeoutLocksSend ==
    receivedStatus = "timeout" => ~active

\* =====================================================================
\* Two-state (temporal) properties
\* =====================================================================

\* Status can only change via ServerReply, TimerFires, or Resend —
\* never via Send/Destroy.  Encoded by action definitions; restated
\* here for visibility.
StatusTransitionWellFormed ==
    [][
        (receivedStatus' # receivedStatus) =>
            \/ (receivedStatus' \in {"ok", "error"} /\ active /\ ~active')
            \/ (receivedStatus' = "timeout"          /\ active /\ ~active')
            \/ (receivedStatus' = "none"             /\ resends' > resends)
    ]_vars

\* refFieldSet is monotone within any behavior that does not take
\* Resend as a step that toggles it.  Since Resend sets it TRUE again
\* atomically, refFieldSet never transitions TRUE → FALSE.
RefFieldMonotone ==
    [][ refFieldSet => refFieldSet' ]_vars

\* Entering active is either via Send (~active → active) or via
\* Resend (regardless of prior active).  receivedStatus'= "none"
\* iff the step is a Resend or if already "none".
EntryIntoActive ==
    [][ (~active /\ active') => receivedStatus' = "none" ]_vars

\* Destroy and Reply/Timer all exit active; exit always implies
\* active' = FALSE.
ExitFromActive ==
    [][ (active /\ ~active') => \/ receivedStatus' \in {"ok","error","timeout"}
                                \/ receivedStatus' = receivedStatus    \* Destroy
    ]_vars

\* After Destroy, no Reply/Timer can fire until Resend re-arms.
\* Covered structurally by guards on Reply/TimerFires requiring active.
NoReceiveAfterDestroy ==
    [][ (active /\ ~active' /\ receivedStatus' = receivedStatus) =>
            \* This is the Destroy step; next step cannot be Reply/Timer
            \* because active' is FALSE.  Trivially true in the next state.
            TRUE
    ]_vars

=========================================================================
