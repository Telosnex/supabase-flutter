-------------------------- MODULE RealtimeChannel --------------------------
(*
 * TLA+ model of the RealtimeChannel state machine.
 *
 * Dart source:
 *   packages/realtime_client/lib/src/realtime_channel.dart
 *     subscribe() (lines ~133–244), rejoin() (~751–760),
 *     rejoinUntilConnected() (~100–105), unsubscribe() (~695–733),
 *     _onClose() (~693–697), _onError() (~699–703),
 *     joinPush receive hooks (~57–89), push() (~493–507), trigger() (~760–833)
 *   packages/realtime_client/lib/src/realtime_client.dart
 *     _triggerChanError() (~438–442) — cascades socket error to every channel
 *
 * ═══════════════════════════════════════════════════════════════════════
 *                       DESIGN (INTENDED BEHAVIOR)
 * ═══════════════════════════════════════════════════════════════════════
 *
 *   State machine (ChannelStates in constants.dart):
 *
 *         closed ──subscribe──▶ joining ──ok──▶ joined
 *                                 │               │
 *                                 │ timeout       │ socket-drop
 *                                 ▼               ▼
 *                               errored ◀─────────┘
 *                                 │ rejoinTimer fires
 *                                 │ (socket connected)
 *                                 ▼
 *                               joining  …
 *
 *         {closed, joining, joined, errored} ──unsubscribe──▶ closed
 *                                                   (atomic)
 *
 *   ╭──────────────────────────────────────────────────────────────────╮
 *   │ Why unsubscribe collapses to ONE atomic step in this model:      │
 *   │                                                                  │
 *   │   unsubscribe() sets _state = leaving (line 696), then does      │
 *   │   leavePush.send() (line 726).  Because _state = leaving makes   │
 *   │   isJoined = false, canPush = socket.isConnected && isJoined is  │
 *   │   ALWAYS false at line 728, so leavePush.trigger('ok', {}) at    │
 *   │   line 729 ALWAYS fires.  That trigger synchronously cascades    │
 *   │   through the refEvent binding registered by startTimeout,       │
 *   │   through _matchReceive('ok'), through the onClose() hook, into  │
 *   │   channel.trigger('phx_close'), into the constructor-registered  │
 *   │   _onClose handler at lines 66–71 which calls                    │
 *   │     _rejoinTimer.reset();                                        │
 *   │     _state = closed;                                             │
 *   │     socket.remove(this);                                         │
 *   │   All synchronously, in one Dart event-loop frame, before        │
 *   │   unsubscribe() returns.  No Timer can fire in the gap; no       │
 *   │   other microtask can observe _state = leaving.                  │
 *   │                                                                  │
 *   │   Therefore the model does NOT expose `leaving` as a reachable   │
 *   │   state.  (A prior version of this file split Unsubscribe and    │
 *   │   LeaveComplete into two actions; audit revealed that to be a    │
 *   │   spurious interleaving.)                                        │
 *   ╰──────────────────────────────────────────────────────────────────╯
 *
 *   `joinedOnce` is a one-shot latch.  subscribe() throws on a second
 *   call (line 141).
 *
 *   Push buffer: push() at line 493–507 — while !canPush, Push objects
 *   accumulate in _pushBuffer; they are flushed by the joinPush 'ok'
 *   handler at lines 57–64.
 *
 *   RejoinTimer: scheduled by _onError (line 79) and joinPush-timeout
 *   (line 88).  Its callback, rejoinUntilConnected() at 100–105,
 *   re-schedules itself and, if the socket is connected, calls
 *   rejoin() (line 753) which sets _state = joining.  The timer is
 *   reset by:
 *     • joinPush.receive('ok') line 59 — join succeeded,
 *     • _onClose handler line 67    — channel is gone.
 *
 *   Socket-drop cascade: realtime_client._triggerChanError() fires an
 *   error event on every channel; channel._onError (lines 73–80)
 *   converts that into state=errored + rejoinTimer, provided state
 *   ∉ {leaving, closed}.
 *
 * ═══════════════════════════════════════════════════════════════════════
 *                       SAFETY INVARIANTS
 * ═══════════════════════════════════════════════════════════════════════
 *
 *   SubscribeOnce / JoinedOnceIsMonotone
 *       joinedOnce transitions FALSE → TRUE exactly once.
 *
 *   ClosedIsTerminal
 *       Once (state = closed ∧ joinedOnce), state never changes again
 *       without a (disallowed) second subscribe.
 *
 *   RejoinBookkeeping
 *       rejoinScheduled ⇒ state ∈ {errored, joining}.
 *       Because unsubscribe is now atomic, the weaker variant
 *       admitting `leaving` is no longer required — the strict form
 *       holds.  (See the old RealtimeChannel_TimerLeakOnLeave.cfg:
 *       that counterexample was a model artifact, now eliminated.)
 *
 *   JoinOkFlushesBuffer
 *       Entering joined forces pushBuffer = 0.
 *
 *   JoinedClearsRejoinTimer
 *       Entering joined clears rejoinScheduled.
 *
 *   PushBufferOnlyAfterJoined
 *       pushBuffer > 0 ⇒ joinedOnce.  Pushes are impossible before
 *       subscribe (Dart throws at line 496).
 *
 *   UnsubscribeLeadsToClosed
 *       After Unsubscribe the state is closed with no rejoin armed.
 *
 * ═══════════════════════════════════════════════════════════════════════
 *                       OUT OF SCOPE
 * ═══════════════════════════════════════════════════════════════════════
 *
 *   • postgres_changes binding reconciliation inside the subscribe 'ok'
 *     handler (lines 174–217).  That is a data-layer concern and
 *     happens synchronously before any reachable action.
 *   • Presence state sync — modelled separately (future).
 *   • Individual Push state machine — modelled in ../realtime_push/Push.tla
 *   • RetryTimer internals — modelled in ../realtime_retry/RetryTimer.tla
 *
 * How to run:
 *   tlc RealtimeChannel.tla -config RealtimeChannel.cfg -workers auto
 *)

EXTENDS Naturals

CONSTANTS
    MaxPushes        \* Bound on total push() calls made in a behavior

VARIABLES
    state,              \* ChannelStates (never exposes "leaving"; see header)
    joinedOnce,         \* BOOLEAN — has subscribe() been called?
    pushBuffer,         \* Nat — size of _pushBuffer
    rejoinScheduled,    \* BOOLEAN — is _rejoinTimer armed?
    socketConnected,    \* BOOLEAN — abstract: socket is Open
    totalPushes         \* Nat — total push() calls (state-space cap)

vars == <<state, joinedOnce, pushBuffer, rejoinScheduled,
          socketConnected, totalPushes>>

\* Full ChannelStates enum — "leaving" is defined for documentation
\* but unreachable in this model.  See header comment.
States == {"closed", "joining", "joined", "errored", "leaving"}
ReachableStates == States \ {"leaving"}

TypeOK ==
    /\ state           \in States
    /\ state           \in ReachableStates      \* stricter: never leaving
    /\ joinedOnce      \in BOOLEAN
    /\ pushBuffer      \in 0..MaxPushes
    /\ rejoinScheduled \in BOOLEAN
    /\ socketConnected \in BOOLEAN
    /\ totalPushes     \in 0..MaxPushes

Init ==
    /\ state           = "closed"
    /\ joinedOnce      = FALSE
    /\ pushBuffer      = 0
    /\ rejoinScheduled = FALSE
    /\ socketConnected = FALSE
    /\ totalPushes     = 0

\* Derived predicate.  Dart: `canPush => socket.isConnected && isJoined`.
CanPush == socketConnected /\ state = "joined"

\* =====================================================================
\* Socket-level events (abstracted)
\* =====================================================================

SocketConnect ==
    /\ ~socketConnected
    /\ socketConnected' = TRUE
    /\ UNCHANGED <<state, joinedOnce, pushBuffer, rejoinScheduled, totalPushes>>

\* Clean socket close — does NOT cascade an error to channels.  Corresponds
\* to realtime_client.connState transitioning to Disconnected via user
\* disconnect() (shouldCloseSink branch sets state=disconnected, which
\* is distinct from "closed" and does NOT run _triggerChanError).
SocketDisconnectClean ==
    /\ socketConnected
    /\ socketConnected' = FALSE
    /\ UNCHANGED <<state, joinedOnce, pushBuffer, rejoinScheduled, totalPushes>>

\* Unexpected socket close — realtime_client._onConnClose (closed path)
\* invokes _triggerChanError which fires 'phx_error' on every channel;
\* channel._onError (lines 73–80) maps that to state=errored + rejoinTimer
\* unless state ∈ {leaving, closed}.
SocketDropCascade ==
    /\ socketConnected
    /\ socketConnected' = FALSE
    /\ IF state = "closed"
       THEN UNCHANGED <<state, rejoinScheduled>>
       ELSE /\ state' = "errored"
            /\ rejoinScheduled' = TRUE
    /\ UNCHANGED <<joinedOnce, pushBuffer, totalPushes>>

\* =====================================================================
\* subscribe()  — realtime_channel.dart:133–244
\* =====================================================================
\*
\*   if (!socket.isConnected) socket.connect();   // line 137–138
\*   if (joinedOnce) throw ...;                   // line 140–141
\*   joinedOnce = true;                           // line 171
\*   rejoin(timeout ?? _timeout);                 // line 172

Subscribe ==
    /\ state = "closed"
    /\ ~joinedOnce
    /\ joinedOnce' = TRUE
    /\ state'      = "joining"
    /\ UNCHANGED <<pushBuffer, rejoinScheduled, socketConnected, totalPushes>>

\* =====================================================================
\* joinPush receive hooks
\* =====================================================================

\* joinPush.receive('ok') at lines 57–64.
\* Dart:
\*   _state = ChannelStates.joined;
\*   _rejoinTimer.reset();
\*   for (pushEvent in _pushBuffer) send();
\*   _pushBuffer = [];
JoinOk ==
    /\ state = "joining"
    /\ socketConnected        \* an 'ok' arrives only via a live socket
    /\ state'           = "joined"
    /\ rejoinScheduled' = FALSE
    /\ pushBuffer'      = 0   \* flush
    /\ UNCHANGED <<joinedOnce, socketConnected, totalPushes>>

\* joinPush.receive('timeout') at lines 82–89.
\* Dart:
\*   if (!isJoining) return;
\*   _state = ChannelStates.errored;
\*   _rejoinTimer.scheduleTimeout();
\*
\* Note: there is NO symmetric joinPush.receive('error') in the channel
\* constructor.  The subscribe() user-callback hooks an 'error' at line
\* 229 but it does not mutate _state.  The only other entry into
\* `errored` is SocketDropCascade via _onError.
JoinTimeout ==
    /\ state = "joining"
    /\ state'           = "errored"
    /\ rejoinScheduled' = TRUE
    /\ UNCHANGED <<joinedOnce, pushBuffer, socketConnected, totalPushes>>

\* =====================================================================
\* Rejoin timer firing  — realtime_channel.dart:100–105
\* =====================================================================
\*
\*   rejoinUntilConnected() {
\*     _rejoinTimer.scheduleTimeout();   // reschedule tail
\*     if (socket.isConnected) rejoin();
\*   }
\*   rejoin() {
\*     if (isLeaving) return;            // unreachable in this model
\*     socket.leaveOpenTopic(topic);
\*     _state = ChannelStates.joining;
\*     joinPush.resend(timeout);
\*   }
\*
\* Modelled only for the effective-transition case (errored → joining).
\* No-op re-schedules are stutters and would bloat the state space.
RejoinTimerFires ==
    /\ rejoinScheduled
    /\ state = "errored"
    /\ socketConnected
    /\ state' = "joining"
    /\ UNCHANGED <<joinedOnce, pushBuffer, rejoinScheduled,
                   socketConnected, totalPushes>>

\* =====================================================================
\* push()  — realtime_channel.dart:493–507
\* =====================================================================
\*
\*   if (!joinedOnce) throw ...;
\*   final pushEvent = Push(this, event, payload, timeout);
\*   if (canPush) pushEvent.send();
\*   else { pushEvent.startTimeout(); _pushBuffer.add(pushEvent); }

PushDirect ==
    /\ joinedOnce
    /\ CanPush
    /\ totalPushes < MaxPushes
    /\ totalPushes' = totalPushes + 1
    /\ UNCHANGED <<state, joinedOnce, pushBuffer,
                   rejoinScheduled, socketConnected>>

PushBuffered ==
    /\ joinedOnce
    /\ ~CanPush
    /\ totalPushes < MaxPushes
    /\ pushBuffer  < MaxPushes
    /\ totalPushes' = totalPushes + 1
    /\ pushBuffer'  = pushBuffer + 1
    /\ UNCHANGED <<state, joinedOnce, rejoinScheduled, socketConnected>>

\* =====================================================================
\* unsubscribe()  — realtime_channel.dart:695–733
\* =====================================================================
\*
\* Verified by audit to execute synchronously from state=leaving back
\* to state=closed before returning.  See header "Why unsubscribe
\* collapses to ONE atomic step".  Therefore:
\*
\*   UnsubscribeSync atomically:
\*     - cancels any pending rejoin (_rejoinTimer.reset())
\*     - transitions state to closed
\*     - does NOT expose the transient `leaving` value to any other
\*       reachable action (no event-loop turn occurs)
\*
\* Unsubscribe has NO state guard in Dart — it can be called from any
\* state, including closed.  We permit it broadly here.

UnsubscribeSync ==
    /\ state'           = "closed"
    /\ rejoinScheduled' = FALSE           \* _rejoinTimer.reset()
    /\ UNCHANGED <<joinedOnce, pushBuffer, socketConnected, totalPushes>>

\* =====================================================================
\* Next-state relation
\* =====================================================================

Next ==
    \/ SocketConnect
    \/ SocketDisconnectClean
    \/ SocketDropCascade
    \/ Subscribe
    \/ JoinOk
    \/ JoinTimeout
    \/ RejoinTimerFires
    \/ PushDirect
    \/ PushBuffered
    \/ UnsubscribeSync

Spec == Init /\ [][Next]_vars

\* =====================================================================
\* Safety invariants
\* =====================================================================

\* `rejoinScheduled` is set only at lines 79, 88 (both require live
\* pre-state ∈ {joining, errored}) and cleared at line 59 (entering
\* joined) / line 67 (entering closed).  It can persist across
\* errored → joining (via RejoinTimerFires).  `leaving` is unreachable
\* in this model, so the strict form holds.
RejoinBookkeeping ==
    rejoinScheduled => state \in {"errored", "joining"}

\* Pushes cannot exist before subscribe — Dart throws at line 496.
PushBufferOnlyAfterJoined ==
    pushBuffer > 0 => joinedOnce

\* Once closed AND joinedOnce, the channel is terminal.  Re-subscribe
\* is disallowed by the throw at line 141 (here: Subscribe is guarded
\* on ~joinedOnce).  socket.remove(this) at line 70 also drops the
\* channel from the socket registry.
ClosedIsStable ==
    (state = "closed" /\ joinedOnce) => rejoinScheduled = FALSE

\* =====================================================================
\* Two-state (temporal) properties
\* =====================================================================

\* Once closed AND joinedOnce, state never changes.
ClosedIsTerminal ==
    [][ (state = "closed" /\ joinedOnce) => (state' = "closed") ]_vars

\* joinedOnce is monotone.
JoinedOnceIsMonotone ==
    [][ joinedOnce => joinedOnce' ]_vars

\* Entering joined flushes pushBuffer.
JoinOkFlushesBuffer ==
    [][ (state # "joined" /\ state' = "joined") => pushBuffer' = 0 ]_vars

\* Entering joined clears rejoinScheduled.
JoinedClearsRejoinTimer ==
    [][ (state' = "joined" /\ state # "joined") => rejoinScheduled' = FALSE ]_vars

\* The step following UnsubscribeSync (state' = closed via this action)
\* also clears rejoinScheduled.  Covered by action definition;
\* encoded here for visibility.
UnsubscribeLeadsToClosed ==
    [][ \* If state' = closed and the previous state was not closed,
        \* rejoinScheduled must have been cleared as part of the step.
        (state' = "closed" /\ state # "closed") => rejoinScheduled' = FALSE
    ]_vars

=========================================================================
