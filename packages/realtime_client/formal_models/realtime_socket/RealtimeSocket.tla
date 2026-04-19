-------------------------- MODULE RealtimeSocket --------------------------
(*
 * TLA+ model of the RealtimeClient WebSocket lifecycle.
 *
 * Dart source:
 *   packages/realtime_client/lib/src/realtime_client.dart
 *     connect()       ~207–262
 *     disconnect()    ~266–299
 *     removeChannel / removeAllChannels  ~306–319
 *     sendHeartbeat() ~433–453
 *     _onConnOpen()   ~382–396
 *     _onConnClose()  ~399–413
 *     _onConnError()  ~415–421
 *     onConnMessage() ~327–362  (heartbeat reply matching)
 *     push()          ~340–352  (sendBuffer branch)
 *     _flushSendBuffer() ~425–431
 *   packages/realtime_client/lib/src/retry_timer.dart
 *     RetryTimer.scheduleTimeout / reset
 *
 * ═══════════════════════════════════════════════════════════════════════
 *                       DESIGN (INTENDED BEHAVIOR)
 * ═══════════════════════════════════════════════════════════════════════
 *
 *   SocketStates (constants.dart):
 *
 *     Null          (initial; no socket object)
 *     Connecting    (connect() in flight; awaiting `conn.ready`)
 *     Open          (ready completed; messages can flow)
 *     Disconnecting (user disconnect() in flight)
 *     Disconnected  (closed by user)
 *     Closed        (closed NOT by user → reconnect should be attempted)
 *
 *   Classification matters: disconnect() called by the application must
 *   NOT trigger automatic reconnect; any other close (server drop,
 *   heartbeat timeout, ready-error) MUST.
 *
 *   Concurrency hazard #1 — the `await conn.ready` yield in connect().
 *   Between starting the await and resuming, three things can happen:
 *     (1) the user calls disconnect(),
 *     (2) the reconnect timer fires and runs disconnect+connect,
 *     (3) the server closes the not-yet-ready socket.
 *   connect() guards post-await with
 *     if (conn != localConn || connState != connecting) return;
 *
 *   Concurrency hazard #2 — synchronous-throw in connect() before the
 *   conn field is assigned.  The outer try/catch at lines 212+259
 *   catches any synchronous exception from `transport(endPointURL,
 *   headers)` at line 216.  connState has already been set to
 *   connecting at line 215; conn has NOT been set (line 217 never
 *   runs).  The function silently returns with a non-recoverable
 *   (connState=connecting ∧ this.conn=null).  Modelled here under the
 *   MODEL CONSTANT `AllowSyncTransportThrow`.
 *
 *   Concurrency hazard #3 — `pendingHeartbeatRef` persistence.  No
 *   lifecycle event (connect, disconnect, onDone, onError) clears
 *   pendingHeartbeatRef — only the heartbeat itself clears it
 *   (either via onConnMessage matching the ref, or via sendHeartbeat
 *   when it discovers a pending ref and closes the socket).  So if
 *   a session ends with pendingHeartbeatRef != null (e.g. ServerClose
 *   before a heartbeat reply arrives), the stale ref carries into
 *   the next session and the first heartbeat tick on the fresh
 *   socket immediately closes it as a heartbeat-timeout.
 *
 *   Heartbeat timer runs while Open.  On tick:
 *     • if pendingHeartbeatRef != null → null the ref and close the
 *       socket (triggers onDone → state=Closed, reconnect scheduled)
 *     • else → mint a ref, set pendingHeartbeatRef, push heartbeat.
 *
 *   Reconnect timer: armed by ready-error branch (line 233) and by
 *   _onConnClose when state=Closed (line 406).  Disarmed by
 *   _onConnOpen (line 386, reconnectTimer.reset()) and by the
 *   shouldCloseSink branch of disconnect() (line 292, reconnectTimer.
 *   reset()).  When it fires the callback is
 *     async () => { await disconnect(); await connect(); }
 *
 * ═══════════════════════════════════════════════════════════════════════
 *                       SAFETY INVARIANTS (what we check)
 * ═══════════════════════════════════════════════════════════════════════
 *
 *   StateConsistency
 *       connState ∈ {Connecting, Open, Disconnecting} ⇒ thisConn ≠ 0
 *
 *       Violated by SyncTransportThrow — that path leaves
 *       connState=Connecting, thisConn=0.  Positive config runs with
 *       AllowSyncTransportThrow = FALSE so this invariant holds;
 *       dedicated counterexample config RealtimeSocket_SyncTransportThrow.cfg
 *       enables the action and expects a violation.
 *
 *   OpenImpliesHeartbeat
 *       connState = Open ⇒ heartbeatTimerOn
 *
 *   HeartbeatTimerDomain
 *       heartbeatTimerOn ⇒ connState ∈ {Open, Disconnecting}
 *
 *   DisconnectedIsStable
 *       connState = Disconnected ⇒ ¬reconnectScheduled ∧ thisConn = 0
 *
 *   AtMostOneOpen
 *       At any time at most one socket is Open.
 *
 *   NoStalePromotion
 *       Successful ready-resume never promotes a stale localConn.
 *
 *   NoReconnectWithoutConn   (EXPECTED TO FAIL)
 *       thisConn = 0 ∧ ¬connectInflight ∧ ¬disconnectInflight
 *         ⇒ ¬reconnectScheduled
 *       Stronger form of NoReconnectAfterUserDisconnect — covers both
 *       user-initiated (disconnect() called directly) AND library-
 *       initiated (removeChannel / removeAllChannels → disconnect())
 *       paths.  See RealtimeSocket_ReconnectLeak.cfg.
 *
 *   FreshOpenNoStalePendingHeartbeat   (EXPECTED TO FAIL)
 *       On the step that transitions connState to Open, pendingHeartbeat
 *       should be FALSE.  The reconnect path can produce (Open,
 *       pendingHeartbeat=TRUE) when the prior session closed while a
 *       heartbeat was outstanding.  See RealtimeSocket_StaleHeartbeat.cfg.
 *
 * ═══════════════════════════════════════════════════════════════════════
 *                       OUT OF SCOPE
 * ═══════════════════════════════════════════════════════════════════════
 *
 *   • sendBuffer (List<Function>) accumulation and flushing — mostly a
 *     queuing concern; no concurrency hazard beyond heartbeat
 *     coupling.  Worth revisiting if Finding #1 is fixed and the
 *     question "do buffered pushes still flush on auto-reconnect
 *     after user disconnect?" becomes interesting.
 *   • setAuth / access-token propagation across channels.
 *   • Per-channel state (modelled separately in ../realtime_channel).
 *)

EXTENDS Naturals, FiniteSets

CONSTANTS
    MaxAttempts,              \* Bound on total connect() starts
    MaxRef,                   \* Bound on the localConn ref counter
    AllowSyncTransportThrow   \* BOOLEAN: enable the sync-throw action

\* =====================================================================
\* Variables
\* =====================================================================

VARIABLES
    connState,              \* Current SocketState
    thisConn,               \* Ref in `this.conn` (0 = null)
    connectInflight,        \* TRUE while a connect() is awaiting ready
    connectLocal,           \* localConn ref captured by the in-flight connect
    disconnectInflight,     \* TRUE while a disconnect() is awaiting/closing
    disconnectShouldClose,  \* shouldCloseSink captured by disconnect()
    disconnectOldConn,      \* oldConn captured by disconnect()
    disconnectIsUser,       \* TRUE if in-flight disconnect was user-initiated
    pendingHeartbeat,       \* Is a heartbeat awaiting reply?
    heartbeatTimerOn,       \* Is the periodic heartbeat timer running?
    reconnectScheduled,     \* Is the RetryTimer armed?
    userDisconnected,       \* Has the user called disconnect since last Open?
    nextRef,                \* Counter for minting new conn refs
    attempts                \* Total connect() starts (state-space cap)

vars == <<connState, thisConn, connectInflight, connectLocal,
          disconnectInflight, disconnectShouldClose, disconnectOldConn,
          disconnectIsUser, pendingHeartbeat, heartbeatTimerOn,
          reconnectScheduled, userDisconnected, nextRef, attempts>>

States == {"Null", "Connecting", "Open", "Disconnecting", "Disconnected", "Closed"}

TypeOK ==
    /\ connState             \in States
    /\ thisConn              \in 0..MaxRef
    /\ connectInflight       \in BOOLEAN
    /\ connectLocal          \in 0..MaxRef
    /\ disconnectInflight    \in BOOLEAN
    /\ disconnectShouldClose \in BOOLEAN
    /\ disconnectOldConn     \in 0..MaxRef
    /\ disconnectIsUser      \in BOOLEAN
    /\ pendingHeartbeat      \in BOOLEAN
    /\ heartbeatTimerOn      \in BOOLEAN
    /\ reconnectScheduled    \in BOOLEAN
    /\ userDisconnected      \in BOOLEAN
    /\ nextRef               \in 1..(MaxRef + 1)
    /\ attempts              \in 0..MaxAttempts

\* =====================================================================
\* Initial state
\* =====================================================================

Init ==
    /\ connState             = "Null"
    /\ thisConn              = 0
    /\ connectInflight       = FALSE
    /\ connectLocal          = 0
    /\ disconnectInflight    = FALSE
    /\ disconnectShouldClose = FALSE
    /\ disconnectOldConn     = 0
    /\ disconnectIsUser      = FALSE
    /\ pendingHeartbeat      = FALSE
    /\ heartbeatTimerOn      = FALSE
    /\ reconnectScheduled    = FALSE
    /\ userDisconnected      = FALSE
    /\ nextRef               = 1
    /\ attempts              = 0

\* =====================================================================
\* connect()    — realtime_client.dart:207–262
\* =====================================================================

\* Start a new connect() call (user, library, or reconnect timer) up to
\* the yield at `await localConn.ready`.  Models the synchronous
\* preamble: guard, state=connecting, transport() creates conn,
\* this.conn = localConn.
StartConnect(isUser) ==
    /\ ~connectInflight
    /\ thisConn = 0                   \* guard: if (conn != null) return
    /\ attempts < MaxAttempts
    /\ nextRef <= MaxRef
    /\ connState'       = "Connecting"
    /\ thisConn'        = nextRef
    /\ connectLocal'    = nextRef
    /\ connectInflight' = TRUE
    /\ nextRef'         = nextRef + 1
    /\ attempts'        = attempts + 1
    /\ IF isUser THEN userDisconnected' = FALSE
                 ELSE UNCHANGED userDisconnected
    /\ UNCHANGED <<disconnectInflight, disconnectShouldClose,
                   disconnectOldConn, disconnectIsUser,
                   pendingHeartbeat, heartbeatTimerOn, reconnectScheduled>>

UserConnect        == StartConnect(TRUE)
AutoConnect        == StartConnect(FALSE)    \* from reconnect timer

\* Outer try/catch path: transport() threw synchronously at line 216.
\* connState was set to connecting at line 215 but conn never assigned.
\* The catch at line 259 calls _onConnError (which does NOT touch
\* connState) and the function returns.
\*
\* Gated by AllowSyncTransportThrow so the positive config is unaffected.
SyncTransportThrow ==
    /\ AllowSyncTransportThrow
    /\ ~connectInflight
    /\ thisConn = 0                   \* guard at line 208 passes
    /\ attempts < MaxAttempts
    /\ connState'       = "Connecting"
    /\ attempts'        = attempts + 1
    /\ UNCHANGED <<thisConn, connectInflight, connectLocal,
                   disconnectInflight, disconnectShouldClose,
                   disconnectOldConn, disconnectIsUser,
                   pendingHeartbeat, heartbeatTimerOn, reconnectScheduled,
                   userDisconnected, nextRef>>

\* await localConn.ready resolves successfully.
\* Dart: guard `if (conn != localConn || connState != connecting)
\*       return;` then connState=open; _onConnOpen() — which calls
\* _flushSendBuffer(), reconnectTimer.reset(), starts heartbeatTimer.
\*
\* pendingHeartbeat is INTENTIONALLY NOT cleared here — _onConnOpen in
\* Dart does not touch pendingHeartbeatRef.  This reflects the
\* Dart-accurate behaviour used to surface hazard #3.
ConnectReadySuccess ==
    /\ connectInflight
    /\ IF thisConn # connectLocal \/ connState # "Connecting"
       THEN \* bail: another connect started or disconnect ran
            /\ connectInflight' = FALSE
            /\ UNCHANGED <<connState, thisConn, connectLocal,
                           disconnectInflight, disconnectShouldClose,
                           disconnectOldConn, disconnectIsUser,
                           pendingHeartbeat, heartbeatTimerOn,
                           reconnectScheduled, userDisconnected,
                           nextRef, attempts>>
       ELSE /\ connState'          = "Open"
            /\ heartbeatTimerOn'   = TRUE
            /\ reconnectScheduled' = FALSE     \* reconnectTimer.reset()
            /\ connectInflight'    = FALSE
            /\ UNCHANGED <<thisConn, connectLocal,
                           disconnectInflight, disconnectShouldClose,
                           disconnectOldConn, disconnectIsUser,
                           pendingHeartbeat,                 \* NOT cleared — hazard #3
                           userDisconnected, nextRef, attempts>>

\* await localConn.ready throws.  realtime_client.dart:223–235.
ConnectReadyError ==
    /\ connectInflight
    /\ IF thisConn # connectLocal
       THEN /\ connectInflight' = FALSE
            /\ UNCHANGED <<connState, thisConn, connectLocal,
                           disconnectInflight, disconnectShouldClose,
                           disconnectOldConn, disconnectIsUser,
                           pendingHeartbeat, heartbeatTimerOn,
                           reconnectScheduled, userDisconnected,
                           nextRef, attempts>>
       ELSE IF connState \in {"Disconnected", "Disconnecting"}
            THEN /\ connectInflight' = FALSE
                 /\ UNCHANGED <<connState, thisConn, connectLocal,
                                disconnectInflight, disconnectShouldClose,
                                disconnectOldConn, disconnectIsUser,
                                pendingHeartbeat, heartbeatTimerOn,
                                reconnectScheduled, userDisconnected,
                                nextRef, attempts>>
            ELSE /\ connState'          = "Closed"
                 /\ reconnectScheduled' = TRUE
                 /\ connectInflight'    = FALSE
                 /\ UNCHANGED <<thisConn, connectLocal,
                                disconnectInflight, disconnectShouldClose,
                                disconnectOldConn, disconnectIsUser,
                                pendingHeartbeat, heartbeatTimerOn,
                                userDisconnected, nextRef, attempts>>

\* =====================================================================
\* disconnect()    — realtime_client.dart:266–299
\* =====================================================================

\* Start disconnect() up to the first yield.  Atomic w.r.t. capturing
\* oldState / shouldCloseSink / setting connState = disconnecting.
\*
\* isUser = TRUE           → application called disconnect() directly
\* isUser = FALSE          → library callers:
\*                             reconnectTimer callback (line 197–200)
\*                             removeChannel (line ~307) if last channel
\*                             removeAllChannels (line ~314) always
StartDisconnect(isUser) ==
    /\ ~disconnectInflight
    /\ thisConn # 0                           \* guard: if (conn != null)
    /\ LET old == connState
           shouldClose == old \in {"Open", "Connecting"}
       IN  /\ disconnectOldConn'     = thisConn
           /\ disconnectShouldClose' = shouldClose
           /\ disconnectIsUser'      = isUser
           /\ IF shouldClose THEN connState' = "Disconnecting"
                              ELSE UNCHANGED connState
           /\ disconnectInflight'    = TRUE
           /\ IF isUser THEN userDisconnected' = TRUE
                        ELSE UNCHANGED userDisconnected
           /\ UNCHANGED <<thisConn, connectInflight, connectLocal,
                          pendingHeartbeat, heartbeatTimerOn,
                          reconnectScheduled, nextRef, attempts>>

UserDisconnect          == StartDisconnect(TRUE)

\* removeChannel / removeAllChannels → socket.disconnect() when the
\* channel list becomes empty.  Library-initiated, NOT user-initiated.
LibraryAutoDisconnect   == StartDisconnect(FALSE)

\* After the (possible) `await conn.ready.catchError((_){})` at line
\* 282 and `await conn.sink.close()` at line 287/289, run the tail.
\*
\* Dart: pendingHeartbeatRef is NOT cleared here either.
FinishDisconnect ==
    /\ disconnectInflight
    /\ IF disconnectShouldClose
       THEN /\ connState'          = "Disconnected"
            /\ reconnectScheduled' = FALSE      \* reconnectTimer.reset()
       ELSE UNCHANGED <<connState, reconnectScheduled>>
    /\ thisConn'            = 0
    /\ heartbeatTimerOn'    = FALSE
    /\ disconnectInflight'  = FALSE
    /\ UNCHANGED <<connectInflight, connectLocal,
                   disconnectShouldClose, disconnectOldConn, disconnectIsUser,
                   pendingHeartbeat,                        \* NOT cleared — hazard #3
                   userDisconnected, nextRef, attempts>>

\* =====================================================================
\* Server-side close / onDone — realtime_client.dart:250–257, 399–413
\* =====================================================================

\* Unexpected close: state → Closed, reconnect scheduled, heartbeat off.
\* Dart's onDone does not clear pendingHeartbeatRef.
ServerClose ==
    /\ connState = "Open"
    /\ connState'          = "Closed"
    /\ reconnectScheduled' = TRUE
    /\ heartbeatTimerOn'   = FALSE
    /\ UNCHANGED <<thisConn, connectInflight, connectLocal,
                   disconnectInflight, disconnectShouldClose,
                   disconnectOldConn, disconnectIsUser,
                   pendingHeartbeat,                        \* NOT cleared — hazard #3
                   userDisconnected, nextRef, attempts>>

\* =====================================================================
\* Heartbeat    — realtime_client.dart:433–453
\* =====================================================================

\* Heartbeat fires with a previous heartbeat still pending.
\* Dart: pendingHeartbeatRef = null; conn.sink.close(1000, 'heartbeat
\* timeout');  → onDone → state=Closed, reconnect scheduled.
HeartbeatTimeout ==
    /\ heartbeatTimerOn
    /\ connState = "Open"
    /\ pendingHeartbeat
    /\ connState'          = "Closed"
    /\ reconnectScheduled' = TRUE
    /\ heartbeatTimerOn'   = FALSE
    /\ pendingHeartbeat'   = FALSE             \* line 441: ref = null
    /\ UNCHANGED <<thisConn, connectInflight, connectLocal,
                   disconnectInflight, disconnectShouldClose,
                   disconnectOldConn, disconnectIsUser,
                   userDisconnected, nextRef, attempts>>

\* Normal heartbeat tick: push heartbeat, pending until reply.
HeartbeatSend ==
    /\ heartbeatTimerOn
    /\ connState = "Open"
    /\ ~pendingHeartbeat
    /\ pendingHeartbeat' = TRUE
    /\ UNCHANGED <<connState, thisConn, connectInflight, connectLocal,
                   disconnectInflight, disconnectShouldClose,
                   disconnectOldConn, disconnectIsUser,
                   heartbeatTimerOn, reconnectScheduled,
                   userDisconnected, nextRef, attempts>>

\* Server reply.  realtime_client.onConnMessage:
\*   if (ref == pendingHeartbeatRef) pendingHeartbeatRef = null;
\* Only fires when Open and a heartbeat is pending.
HeartbeatReply ==
    /\ heartbeatTimerOn
    /\ connState = "Open"
    /\ pendingHeartbeat
    /\ pendingHeartbeat' = FALSE
    /\ UNCHANGED <<connState, thisConn, connectInflight, connectLocal,
                   disconnectInflight, disconnectShouldClose,
                   disconnectOldConn, disconnectIsUser,
                   heartbeatTimerOn, reconnectScheduled,
                   userDisconnected, nextRef, attempts>>

\* =====================================================================
\* Reconnect timer firing — realtime_client.dart:197–200
\* =====================================================================

ReconnectTimerFires ==
    /\ reconnectScheduled
    /\ ~connectInflight
    /\ ~disconnectInflight
    /\ reconnectScheduled' = FALSE
    /\ IF thisConn # 0
       THEN \* simulate `await disconnect()` — non-user
            /\ disconnectOldConn'     = thisConn
            /\ disconnectShouldClose' = (connState \in {"Open", "Connecting"})
            /\ disconnectIsUser'      = FALSE
            /\ disconnectInflight'    = TRUE
            /\ IF connState \in {"Open", "Connecting"}
               THEN connState' = "Disconnecting"
               ELSE UNCHANGED connState
            /\ UNCHANGED <<thisConn, connectInflight, connectLocal,
                           pendingHeartbeat, heartbeatTimerOn,
                           userDisconnected, nextRef, attempts>>
       ELSE \* conn already null → go straight to connect()
            /\ attempts < MaxAttempts
            /\ nextRef <= MaxRef
            /\ connState'       = "Connecting"
            /\ thisConn'        = nextRef
            /\ connectLocal'    = nextRef
            /\ connectInflight' = TRUE
            /\ nextRef'         = nextRef + 1
            /\ attempts'        = attempts + 1
            /\ UNCHANGED <<disconnectInflight, disconnectShouldClose,
                           disconnectOldConn, disconnectIsUser,
                           pendingHeartbeat, heartbeatTimerOn,
                           userDisconnected>>

\* =====================================================================
\* Next-state relation
\* =====================================================================

Next ==
    \/ UserConnect
    \/ AutoConnect
    \/ SyncTransportThrow
    \/ ConnectReadySuccess
    \/ ConnectReadyError
    \/ UserDisconnect
    \/ LibraryAutoDisconnect
    \/ FinishDisconnect
    \/ ServerClose
    \/ HeartbeatSend
    \/ HeartbeatReply
    \/ HeartbeatTimeout
    \/ ReconnectTimerFires

Spec == Init /\ [][Next]_vars

\* =====================================================================
\* Safety invariants
\* =====================================================================

StateConsistency ==
    connState \in {"Connecting", "Open", "Disconnecting"} => thisConn # 0

OpenImpliesHeartbeat ==
    connState = "Open" => heartbeatTimerOn

HeartbeatTimerDomain ==
    heartbeatTimerOn => connState \in {"Open", "Disconnecting"}

DisconnectedIsStable ==
    connState = "Disconnected" =>
        /\ ~reconnectScheduled
        /\ thisConn = 0
        /\ ~heartbeatTimerOn

\* Old finding: user disconnect from Closed state leaks the reconnect
\* timer.  Retained for the historical counterexample config.
NoReconnectAfterUserDisconnect ==
    (userDisconnected /\ ~disconnectInflight /\ thisConn = 0)
        => ~reconnectScheduled

\* Stronger form: covers user AND library-initiated disconnects.
\* Any time there is no conn and no async operation in flight, there
\* must not be a scheduled reconnect (unless the disconnect happened
\* to land us in Closed — which is EXACTLY the bug).
NoReconnectWithoutConn ==
    (thisConn = 0 /\ ~connectInflight /\ ~disconnectInflight)
        => ~reconnectScheduled

AtMostOneOpen ==
    connState = "Open" => thisConn # 0

NoStalePromotion ==
    (connState = "Open" /\ ~connectInflight) => thisConn # 0

\* =====================================================================
\* Two-state (temporal) properties
\* =====================================================================

\* Entering Open must find pendingHeartbeat cleared, else the first
\* heartbeat tick on the fresh session will self-close.
\* EXPECTED TO FAIL in the current Dart code because no lifecycle
\* event clears pendingHeartbeatRef between sessions.
FreshOpenNoStalePendingHeartbeat ==
    [][ (connState' = "Open" /\ connState # "Open") => ~pendingHeartbeat' ]_vars

=========================================================================
