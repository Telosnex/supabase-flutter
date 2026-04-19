# realtime_client formal models

TLA+ models of the concurrency-heavy parts of the Supabase Realtime Dart client.

The goal is coverage, not cosmetic modelling. Every file the package exposes is either explicitly modelled here or explicitly listed under "Out of scope" with a reason. The model checker (TLC) enumerates every reachable interleaving within the configured bounds.

## Coverage map

| Dart file | Modelled in | Covered actions / properties |
|---|---|---|
| `lib/src/realtime_client.dart` | `realtime_socket/RealtimeSocket.tla` | `connect`, `disconnect`, `sendHeartbeat`, `_onConnOpen`, `_onConnClose`, `_onConnError`, `onConnMessage` (heartbeat reply), `removeChannel`/`removeAllChannels` auto-disconnect, `RetryTimer` callback |
| `lib/src/realtime_channel.dart` | `realtime_channel/RealtimeChannel.tla` | `subscribe`, `rejoin`, `rejoinUntilConnected`, `unsubscribe` (atomic synchronous cascade), `_onClose`/`_onError`, joinPush replies, push/pushBuffer, `_triggerChanError` cascade |
| `lib/src/push.dart` | `realtime_push/Push.tla` | `send`, `resend`, `startTimeout`, `trigger`, `destroy`, `_matchReceive`, `_cancelRefEvent`, `_cancelTimeout`, the reply-vs-timeout race |
| `lib/src/retry_timer.dart` | `realtime_retry/RetryTimer.tla` | `scheduleTimeout`, `reset`, Timer fire, `_tries` accounting |
| `lib/src/constants.dart` | used by all | `SocketStates`, `ChannelStates`, `ChannelEvents` enums |
| `lib/src/types.dart` | used by all | `Binding`, `ChannelFilter`, `RealtimeChannelConfig` (data only — no state machine) |
| `lib/src/message.dart` | n/a | Pure data (`toJson`) |
| `lib/src/realtime_presence.dart` | **out of scope (see below)** | |
| `lib/src/transformers.dart` | n/a | Pure helpers |
| `lib/src/version.dart`, `websocket/*.dart` | n/a | Dispatch only |

### Explicitly out of scope

- **`RealtimePresence`** — presence sync / diff / pendingDiffs / joinRef gating. Largely data transformation; the only concurrency concern is that `syncDiff` is buffered while `inPendingSyncState()` and flushed on sync. Self-contained enough that it would be a separate small model but does not interact with any of the invariants checked here.
- **`RealtimeClient.setAuth`** — token rotation across channels. It iterates channels, calls `updateJoinPayload` and pushes `accessToken` event. It is also invoked from `sendHeartbeat` after every successful heartbeat. No new concurrency hazards beyond those already covered.
- **`subscribe()` postgres_changes binding reconciliation** (realtime_channel.dart:174–217) — synchronous data plumbing between client-registered filters and server-assigned IDs inside the `joinPush.receive('ok')` handler. Does not change the state machine.
- **`httpSend` / `send` REST-fallback** (realtime_channel.dart:538–675) — pure request/response; independent of the subscription state machine beyond reading `canPush`.

## Layout

```
formal_models/
├── realtime_socket/
│   ├── RealtimeSocket.tla
│   ├── RealtimeSocket.cfg                           ← positive, all PASS
│   ├── RealtimeSocket_UserDisconnectBug.cfg         ← Finding #1 (user)
│   ├── RealtimeSocket_ReconnectLeak.cfg             ← Finding #1 (generalised)
│   ├── RealtimeSocket_SyncTransportThrow.cfg        ← Finding #3
│   └── RealtimeSocket_StaleHeartbeat.cfg            ← Finding #4
├── realtime_channel/
│   ├── RealtimeChannel.tla
│   └── RealtimeChannel.cfg                          ← positive, all PASS
├── realtime_push/
│   ├── Push.tla
│   ├── Push.cfg                                     ← positive, all PASS
│   └── Push_DuplicateSend.cfg                       ← Finding #5
└── realtime_retry/
    ├── RetryTimer.tla
    └── RetryTimer.cfg                               ← positive, all PASS
```

## How to run

```bash
cd formal_models/<model>
java -XX:+UseParallelGC \
  -cp "/Applications/TLA+ Toolbox.app/Contents/Eclipse/tla2tools.jar" \
  tlc2.TLC <Module>.tla -config <Config>.cfg -workers auto -deadlock
```

Positive configs should print `Model checking completed. No error has been found.`
Counterexample configs print `Error: Invariant … is violated.` followed by the trace; that trace IS the finding.

Quick all-green scan:

```bash
for dir in realtime_socket realtime_channel realtime_push realtime_retry; do
  for cfg in $dir/*.cfg; do
    name=$(basename "$cfg" .cfg)
    module=$(ls $dir/*.tla | xargs basename | sed 's/\.tla//')
    echo "=== $dir :: $name ==="
    (cd $dir && java -XX:+UseParallelGC \
      -cp "/Applications/TLA+ Toolbox.app/Contents/Eclipse/tla2tools.jar" \
      tlc2.TLC $module.tla -config $name.cfg -workers auto -deadlock 2>&1 \
      | grep -E "(completed|violat|Error:|states found)" | head -3)
  done
done
```

## Findings

### Finding #1 (REAL) — `disconnect()` leaks the reconnect timer when called from `Closed`

Configs: `RealtimeSocket_UserDisconnectBug.cfg` (user path) and `RealtimeSocket_ReconnectLeak.cfg` (generalised, covers the library `removeChannel`/`removeAllChannels` path too).

TLC counterexample (4 actions):

1. `UserConnect` → `connState = Connecting`.
2. `ConnectReadyError` → `connState = Closed`, `reconnectTimer.scheduleTimeout()`.
3. `UserDisconnect` — or `LibraryAutoDisconnect` from `removeChannel` — sees `oldState == Closed`, so `shouldCloseSink = FALSE`. The only `reconnectTimer.reset()` site (realtime_client.dart:292) is inside `if (shouldCloseSink)` and is therefore skipped.
4. `FinishDisconnect` runs `this.conn = null` unconditionally (line 295) and cancels the heartbeat (line 298), but `reconnectScheduled` remains `TRUE`.

Later the timer fires, runs `await disconnect(); await connect();`, and re-establishes a socket against user intent.

**Triggered by**:
- Direct user call to `disconnect()` after ready-error, server drop, or heartbeat timeout.
- Library code: `removeChannel` / `removeAllChannels` when the last channel is removed (realtime_client.dart:306–319).

**Suggested diagnosis (do not auto-apply)**: move `reconnectTimer.reset()` out of the `if (shouldCloseSink)` branch in `disconnect()`, or call it unconditionally when `conn != null`.

### Finding #2 (RETIRED — was a model artifact)

Earlier the channel model split `unsubscribe()` into two actions (`Unsubscribe` + `LeaveComplete`), which let TLC interleave a `rejoinScheduled = TRUE` state between them. The security audit refuted this: `unsubscribe()` drives `_state` synchronously from `leaving` back to `closed` within one Dart event-loop frame via `leavePush.trigger('ok', {})` (line 729, always fires because `_state = leaving` forces `canPush = false`). No `Timer` can fire in that gap.

The current `RealtimeChannel.tla` folds the cascade into a single `UnsubscribeSync` action, with a code-commented proof of the zero-window claim (see the header of that file). The stricter invariant `rejoinScheduled ⇒ state ∈ {errored, joining}` now holds in the positive config; the old counterexample config has been retired.

### Finding #3 (REAL, narrow) — synchronous transport throw leaves `connState = Connecting ∧ conn = null`

Config: `RealtimeSocket_SyncTransportThrow.cfg` (gated by `AllowSyncTransportThrow = TRUE`).

Path:

- `connect()` line 215 sets `connState = SocketStates.connecting`.
- Line 216 `final WebSocketChannel localConn = transport(endPointURL, headers);` **throws synchronously**.
- Line 217 (`conn = localConn`) never runs.
- The outer `catch (e)` at line 259 calls `_onConnError(e)` — which does NOT touch `connState`.
- Function returns.

Resulting state: `connState = Connecting` and `this.conn = null`. Violates `StateConsistency`. The socket is wedged: a subsequent `disconnect()` sees `conn == null` and returns at line 268 (no state change). Only a later successful `connect()` can recover.

Reachability in practice depends on whether `transport(endPointURL, headers)` can throw synchronously rather than returning a Future that errors asynchronously. The default `WebSocketChannel` path tends to fail asynchronously; injected transports (tests, custom platforms) could trip this.

### Finding #4 (REAL) — `pendingHeartbeatRef` persists across sessions → fresh reconnect self-closes

Config: `RealtimeSocket_StaleHeartbeat.cfg` — checks the property `FreshOpenNoStalePendingHeartbeat` (entering `Open` implies `~pendingHeartbeat`).

`pendingHeartbeatRef` (field declared at realtime_client.dart:97) is **only cleared** by:

- `onConnMessage` (line 347) when the incoming `ref` matches.
- `sendHeartbeat` (line 441) when it discovers the field is non-null — it nulls it, then closes the socket as a heartbeat timeout.

Crucially, **no lifecycle event clears it**: neither `_onConnOpen` (382–396), nor `_onConnClose` (399–413), nor `disconnect()` (266–299) touch the field.

TLC finds the minimal trace:

1. `UserConnect` → `Open`.
2. `HeartbeatSend` → `pendingHeartbeat = TRUE`.
3. `ServerClose` → `Closed` (reconnect scheduled). `pendingHeartbeat` stays `TRUE`.
4. `ReconnectTimerFires` → auto disconnect begins.
5. `FinishDisconnect` → `thisConn = 0`. `pendingHeartbeat` still `TRUE`.
6. `AutoConnect` → fresh `Connecting`.
7. `ConnectReadySuccess` → **fresh `Open` with `pendingHeartbeat = TRUE`**.

At step 7, the next heartbeat tick (`HeartbeatTimeout` guard: `pendingHeartbeat`) fires immediately and closes the brand-new session. The user-facing symptom: repeated immediate post-reconnect drops on a flaky network.

### Finding #5 (LATENT, convention-only) — `Push.send()` can re-arm after receiving `'ok'` / `'error'`

Config: `Push_DuplicateSend.cfg` (gated by `AllowDuplicateSend = TRUE`).

`push.dart:58` guards `Push.send()` with `if (_hasReceived('timeout')) return;` — the check is specific to `'timeout'`. An `'ok'` or `'error'` reply does NOT block a subsequent `send()`. A literal second invocation therefore:

- Runs `startTimeout()` (since `_timeoutTimer` was nulled in the binding callback, the early-return doesn't trigger).
- Mints a new `_ref`, registers a new binding, arms a new timer.
- Leaves `_receivedResp` (i.e. `receivedStatus` in the model) carrying the OLD status.

Net state: `active = TRUE ∧ receivedStatus = 'ok'`. Violates the "single-shot" invariant that the callers informally rely on (new `Push` per message, or `Resend` which clears `_receivedResp`).

This is not currently exploitable because the call sites obey the convention. It is logged as a tightening opportunity: `send()` could guard on `receivedStatus != 'none'` (or `resend()` could be the only path back to `active`).

## Model sizes (state space, positive configs)

| Model | States | Max depth |
|---|---|---|
| RealtimeSocket | 250 | 13 |
| RealtimeChannel | 90 | 11 |
| Push | 21 | 4 |
| RetryTimer | 8 | 3 |

Counterexample configs explore 80–200 states before hitting the violation.

## Notes on modelling choices

- `thisConn` is an integer ref counter that replaces Dart object identity. This is enough for the post-await guard `conn != localConn` because the only comparison that matters is "are these the same instance".
- A single in-flight `connect()` and a single in-flight `disconnect()` are permitted simultaneously, mirroring Dart's async interleaving. Two concurrent connects are prevented structurally by `if (conn != null) return;` in Dart and by the same guard in the model.
- The channel model abstracts the socket's `Open`/`Closed` as a boolean. The socket model abstracts per-channel concerns into the `_triggerChanError` cascade (which is what the library's socket-close path actually does).
- The Push model folds the `(bindingRegistered, timerArmed)` pair into a single `active` Boolean because Dart's `_cancelRefEvent` and `_cancelTimeout` are always called together. The `_refEvent` string field is tracked separately because it is only nulled by `resend`, not by cancellation.
- `pendingHeartbeatRef` in the socket model is NOT zeroed by lifecycle events — matching Dart exactly — which is what lets TLC find Finding #4.
- Action guards correspond to Dart control-flow predicates, not to wishful thinking. For example `StartDisconnect` does NOT guard on `connState` because Dart's `disconnect()` does not — this is load-bearing for Finding #1 (disconnecting from `Closed`).

## What to do with a finding

Each numbered finding above gives:
- a minimal TLC trace,
- the exact Dart line reference,
- a diagnosis (what the code currently does),
- a suggested source change (optional — not applied in this commit).

The TLA+ models are the normative description. If Dart changes in a way that affects a state machine modelled here, the model should be updated first and re-checked; only then should Dart changes be reviewed against the model.
