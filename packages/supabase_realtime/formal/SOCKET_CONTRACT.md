# Socket lifecycle contract

Status: reviewed contract implemented by `SocketTransitions.tla` and the Dart
socket kernel. This file remains the prose semantic boundary rather than a
second transition relation.

Implementation pin:
`07345bf9568a0ba495f1e34cb6ba542eddecc7e9`.

## Purpose

The first slice models one Realtime socket, its three socket-owned timers, and
one in-flight heartbeat. It also models connection generations, retry policy,
and the token refresh request made by a normal heartbeat cycle.

It describes the desired fixed protocol. The pinned v3 implementation is an
input and later conformance target, not the source of desired behavior.

## Source evidence

| Concern | Pinned v3 source | Regression or existing test |
|---|---|---|
| Connect and ready race | `lib/src/realtime_client.dart`, `connect()` | `test/socket_test.dart`, connect/disconnect race group |
| Synchronous transport throw | `connect()` outer catch | `test/sync_transport_throw_test.dart` |
| Retry after synchronous throw | `connect()` outer catch | `test/socket_outer_catch_reconnect_test.dart` |
| Explicit disconnect dominates retry | `disconnect()` | `test/socket_test.dart`, pending reconnect test |
| Retry ordinal | `RetryTimer` and `_reconnect()` | `test/socket_test.dart`, growing backoff test |
| Heartbeat generation ownership | `sendHeartbeat()` and connection callbacks | `test/heartbeat_lifecycle_test.dart` |
| Heartbeat token refresh | `sendHeartbeat()` and `setAccessToken()` | `test/heartbeat_test.dart` |
| Deferred empty-channel disconnect | `remove()`, `channel()`, pending timer helpers | `test/socket_test.dart`, deferred disconnect group |

Historical `telosnex/formal-models` socket files are prior art only. They use the
old six-value `SocketState` as model state, omit token refresh, and encode known
bugs in the main relation. This contract instead separates user intent from
transport phase and puts each defect in a mutant.

## Kernel boundary

The pure kernel has this total deterministic shape:

```text
step(ModelState, Event) -> TransitionResult
TransitionResult = (disposition, action, postState, effects)
```

A disposition is:

- `applied` when the event causes its declared transition.
- `ignored` for a legal duplicate, irrelevant, or stale event.
- `rejected` when the event violates the shell-to-kernel contract. Conformance
  tests treat rejection as a failure.

All nondeterminism is outside `step`. The shell converts a user call, transport
outcome, timer callback, or decoded heartbeat reply into one event. The kernel
returns an ordered effect list. The shell executes those effects and reports
outcomes as later events.

## State vocabulary

The TLA+ model uses one `state` record. The Dart kernel later uses one immutable
`ModelState` with the same fields.

| Field | Domain | Meaning |
|---|---|---|
| `intent` | `up`, `down` | Last explicit connect or disconnect intent |
| `phase` | `idle`, `connecting`, `open`, `closing` | Current transport phase only |
| `closeKind` | `none`, `user`, `recovery` | Origin of the close that owns `closing` |
| `afterClose` | `none`, `idle`, `connectNow`, `backoff` | Required work after the current close terminates |
| `activeGeneration` | optional generation | Generation owned by `connecting`, `open`, or `closing` |
| `nextGeneration` | positive integer | Next transport generation to allocate |
| `retryCount` | natural number | Number of reconnect timer callbacks consumed since the last successful open or explicit intent reset |
| `reconnectTimer` | timer obligation | One-shot reconnect timer and its delay ordinal |
| `heartbeatTimer` | generation timer obligation | Periodic heartbeat timer owned by the open generation |
| `disconnectTimer` | timer obligation | One-shot empty-channel grace timer |
| `nextTimerId` | positive integer | Next timer identity to allocate |
| `pendingHeartbeat` | optional heartbeat debt | Outstanding ref and owning connection generation |
| `nextHeartbeatRef` | positive integer | Next heartbeat ref to allocate |
| `hasChannelDemand` | Boolean | Whether at least one channel currently exists |
| `started` | Boolean | Whether a connect intent has ever been accepted |

A timer obligation contains `armed` and `id`. `reconnectTimer` also contains
`delayOrdinal`. `heartbeatTimer` also contains `connectionGeneration`.
Disarming a timer clears its payload fields. A callback event retains the ID of
the timer instance that created it.

A heartbeat debt contains `connectionGeneration` and `ref`. It is not a bare
Boolean. This makes generation ownership directly checkable.

`started` exists only to preserve the nullable public connection-state view.
It does not control lifecycle decisions.

## Derived public connection state

The existing public `SocketState?` remains an adapter view. It is never an input
to the kernel.

| Kernel state | Public view |
|---|---|
| `started = FALSE` | `null` |
| `phase = connecting` | `connecting` |
| `phase = open` | `open` |
| `phase = closing` and `closeKind = user` | `disconnecting` |
| `phase = closing` and `closeKind = recovery` | Retain `open` until the terminal close event |
| `phase = idle` and `intent = up` | `closed` |
| `phase = idle` and `intent = down` | `disconnected` |

`closeKind` and `afterClose` are independent. A connect request during a user
close changes `afterClose` to `connectNow` but leaves the public view at
`disconnecting`. An explicit disconnect during a recovery close changes
`closeKind` to `user` and `afterClose` to `idle`.

Status-stream emissions are explicit effects and do not depend on polling this
view.

## Events

Every event carries only immutable scalar or generated value data.

### User and channel events

| Event | Payload | Meaning |
|---|---|---|
| `ConnectRequested` | none | Set intent up and connect now when no transport owns the phase |
| `DisconnectRequested` | none | Set intent down and quiesce all socket resources |
| `ChannelDemandAppeared` | none | Record nonempty demand and cancel empty-channel disconnect |
| `ChannelDemandDisappeared` | `grace` | Record empty demand and disconnect now or after the configured grace |

`DisconnectRequested` covers the public disconnect and immediate
`removeAllChannels` path. An automatic recovery never emits this event because
it must not change user intent.

### Transport events

| Event | Payload | Meaning |
|---|---|---|
| `TransportOpened` | `generation` | The open effect for this generation completed successfully |
| `TransportOpenFailed` | `generation`, `kind` | Construction threw synchronously or readiness failed asynchronously |
| `TransportErrorObserved` | `generation`, `kind` | The stream reported an error without a terminal close yet |
| `TransportClosed` | `generation`, `kind` | The current or stale transport terminated |
| `TransportCloseFailed` | `generation`, `kind` | An explicit close failed or timed out and must still finalize |
| `HeartbeatSendFailed` | `generation`, `ref`, `kind` | Sending the current heartbeat failed synchronously or asynchronously |

`kind` is diagnostic. Synchronous and asynchronous open failure have identical
lifecycle semantics. Every callback carries its registration generation. A
callback from an old generation remains legal and must be ignored.

### Timer events

| Event | Payload | Meaning |
|---|---|---|
| `ReconnectTimerFired` | `timerId` | A one-shot reconnect timer callback began |
| `HeartbeatTimerFired` | `timerId` | A periodic heartbeat timer tick began |
| `DisconnectTimerFired` | `timerId` | The empty-channel grace callback began |

A timer callback is current only when its ID equals the armed obligation ID.
Any other ID is stale and has disposition `ignored` with no effects.

### Server events

| Event | Payload | Meaning |
|---|---|---|
| `HeartbeatReplyReceived` | `generation`, `ref`, `status` | A decoded reply may satisfy current heartbeat debt |

`status` is `ok` or `error`. A reply with a stale generation or nonmatching ref
is ignored.

Token provider completion and channel token propagation do not change socket
lifecycle state in this slice. They remain shell work. The lifecycle-visible
contract is the `ResolveCurrentToken` effect below.

## Action vocabulary

`TransitionResult.action` uses one stable semantic branch identifier. Event
names are not reused as actions because one event can have different legal
outcomes by state.

| Action | Branch represented |
|---|---|
| `startConnect` | Allocate and open a generation now |
| `connectAlreadySatisfied` | Idempotent connect while connecting or open |
| `connectAfterCurrentClose` | Retarget current close to open immediately afterward |
| `beginUserClose` | Start an explicit quiescing close |
| `retargetCloseToIdle` | Explicit disconnect takes ownership of an existing recovery close |
| `quiesceWithoutTransport` | Apply down intent while already idle |
| `recordChannelDemand` | Record nonempty demand without a pending timer |
| `recordEmptyDemandWithoutTimer` | Record empty demand while intent is already down |
| `cancelDeferredDisconnect` | Record demand and cancel its grace timer |
| `scheduleDeferredDisconnect` | Record empty demand and arm its grace timer |
| `disconnectEmptyDemandNow` | Zero grace applies down intent immediately |
| `channelDemandAlreadyRecorded` | Idempotent demand event |
| `acceptTransportOpen` | Current generation reaches open |
| `recoverOpenFailure` | Current open attempt fails under up intent |
| `reportTransportError` | Current generation reports a nonterminal stream error |
| `settleCloseIdle` | Current close reaches idle with no follow-up |
| `settleCloseAndConnect` | Current close completes and opens immediately |
| `settleCloseAndBackoff` | Current close completes and arms retry |
| `recoverUnexpectedClose` | Current open transport drops under up intent |
| `startReconnectAttempt` | Current reconnect timer opens a generation |
| `sendHeartbeat` | Current heartbeat tick creates fresh debt and sends |
| `timeoutHeartbeat` | Current tick finds debt and starts recovery close |
| `acceptHeartbeatReply` | Current matching reply clears debt |
| `recoverHeartbeatSendFailure` | Current heartbeat send fails and starts recovery close |
| `fireDeferredDisconnect` | Current grace timer applies down intent |
| `ignoreStaleTransportEvent` | Generation does not match the active generation |
| `ignoreSupersededOperationEvent` | Identity matches, but a later event made the outcome irrelevant |
| `ignoreStaleTimerEvent` | Timer identity does not match its armed obligation |
| `ignoreHeartbeatReply` | Generation or ref does not match current debt |
| `rejectContractViolation` | Shell supplied an impossible current event |

The manifest must contain exactly these first-slice action IDs. A later slice
adds IDs rather than overloading an existing action with new semantics.

## Effects

| Effect | Payload | Shell obligation |
|---|---|---|
| `OpenTransport` | `generation` | Create one transport and tag every callback with this generation |
| `CloseTransport` | `generation`, `reason` | Request closure and report one terminal close outcome |
| `ArmReconnectTimer` | `timerId`, `delayOrdinal` | Arm one one-shot retry timer |
| `CancelReconnectTimer` | `timerId` | Cancel that concrete timer instance |
| `ArmHeartbeatTimer` | `timerId`, `generation` | Arm one periodic timer for the open generation |
| `CancelHeartbeatTimer` | `timerId` | Cancel that concrete timer instance |
| `ArmDisconnectTimer` | `timerId` | Arm the empty-channel grace timer |
| `CancelDisconnectTimer` | `timerId` | Cancel that concrete timer instance |
| `SendHeartbeat` | `generation`, `ref` | Send one heartbeat on the matching open transport |
| `ResolveCurrentToken` | `reason`, no token override | Invoke the configured provider with cached-token fallback |
| `EmitConnectionOpen` | none | Add one open status event |
| `EmitConnectionClosed` | close metadata | Add one closed status event |
| `EmitConnectionError` | failure metadata | Add one status-stream error |
| `EmitHeartbeat` | `sent`, `ok`, `error`, or `timeout` | Add one heartbeat status event |
| `NotifyChannelsOfTransportError` | failure metadata | Deliver the connection failure to channels |

The shell may branch only to classify an external outcome into an event. It may
not read `ModelState`, choose retry policy, or mutate lifecycle state.

`SendHeartbeat` must report `HeartbeatSendFailed` when the platform reports a
send failure. A successful send has no completion event because the matching
server reply is already explicit.

### Observable-effect matrix

| Accepted outcome | Required observable effects |
|---|---|
| Current transport opens | `EmitConnectionOpen` |
| Current open attempt fails | `EmitConnectionError`, `NotifyChannelsOfTransportError` |
| Current transport reports a nonterminal error | `EmitConnectionError`, `NotifyChannelsOfTransportError` |
| Current transport closes during user close | `EmitConnectionClosed` |
| Current transport closes unexpectedly or during recovery | `NotifyChannelsOfTransportError`, `EmitConnectionClosed` |
| Current heartbeat send fails | `EmitHeartbeat(error)`, `EmitConnectionError`, `NotifyChannelsOfTransportError` |
| Current heartbeat reply | `EmitHeartbeat(ok)` or `EmitHeartbeat(error)` |
| Current heartbeat times out | `EmitHeartbeat(timeout)` immediately, then close effects on terminal close |

Each accepted transport generation emits at most one open status and one
terminal closed status. Stale outcomes emit no status.

## Required transition obligations

These obligations constrain the later TLA+ `Step` operator. They are listed
here to remove semantic choices before syntax work starts.

### Connect intent

1. `ConnectRequested` sets `intent = up`, sets `started = TRUE`, cancels a
   pending empty-channel timer, and resets `retryCount` only when the prior
   intent was down.
2. From `idle`, it cancels a pending reconnect timer, allocates one fresh
   connection generation, enters `connecting`, and emits `OpenTransport`.
3. From `connecting` or `open`, it is idempotent.
4. From `closing`, it sets `afterClose = connectNow`. No second transport opens
   before the current generation terminates. It does not change `closeKind`.

### Disconnect intent

1. `DisconnectRequested` sets `intent = down`, resets `retryCount`, cancels all
   three socket timers, and clears heartbeat debt.
2. From `connecting` or `open`, it enters `closing`, sets
   `closeKind = user`, sets `afterClose = idle`, and emits one `CloseTransport`
   for the active generation.
3. From `closing`, it changes `closeKind` to `user` and `afterClose` to `idle`
   without issuing a duplicate close.
4. From `idle`, it remains idle with no active generation and no armed timer.

### Open outcomes

1. A current `TransportOpened` is accepted only in `connecting` for the same
   active generation.
2. It enters `open`, resets `retryCount`, clears heartbeat debt, arms a fresh
   generation-owned heartbeat timer, and emits `EmitConnectionOpen`.
3. A current `TransportOpenFailed` leaves no active generation and enters
   `idle`.
4. Open failure with `intent = up` arms one reconnect timer at
   `nextDelayOrdinal(retryCount)`. Open failure with `intent = down` arms none.
5. Synchronous and asynchronous failure follow the same branch.
6. A stale generation outcome is ignored with no effects.
7. A current nonterminal `TransportErrorObserved` preserves lifecycle state and
   emits connection and channel errors. Its later terminal close remains a
   separate event.

### Close outcomes

1. A current terminal close first captures its follow-up plan. It cancels the
   heartbeat timer, clears heartbeat debt and the active generation, resets
   `closeKind` and `afterClose`, and reaches `idle` before follow-up work.
2. If `intent = down` or `afterClose = idle`, no reconnect is armed.
3. `afterClose = connectNow` allocates and opens a fresh generation immediately.
4. `afterClose = backoff` arms one reconnect timer at
   `nextDelayOrdinal(retryCount)`.
5. An unexpected close from `open` behaves as `backoff` when intent is up and as
   `idle` when intent is down.
6. `TransportCloseFailed` has the same lifecycle finalization as
   `TransportClosed`. A failed close cannot wedge `closing`.

### Reconnect timer

1. A current reconnect timer fire disarms that obligation.
2. With `intent = up` and `phase = idle`, it increments `retryCount`, allocates a
   fresh generation, enters `connecting`, and emits `OpenTransport`.
3. With intent down, it has no open effect. This state is unreachable in the
   pristine model but remains total.
4. Scheduling delay ordinal is always `nextDelayOrdinal(retryCount)`. The
   function follows the configured schedule and saturates only where that
   schedule caps. Internal recovery never resets the count. Successful open or
   a new explicit intent cycle resets it.

### Heartbeat

1. A current heartbeat tick is accepted only for the open generation.
2. With no heartbeat debt, it allocates a ref, records debt for the active
   generation, and emits these ordered effects exactly once:
   `SendHeartbeat`, `EmitHeartbeat(sent)`, `ResolveCurrentToken(heartbeat)`.
3. `ResolveCurrentToken` carries no explicit token override. This requires the
   provider path instead of short-circuiting on the cached token.
4. With current debt already present, the tick clears debt, cancels the
   heartbeat timer, enters `closing`, sets `closeKind = recovery` and
   `afterClose = backoff`, and emits `EmitHeartbeat(timeout)` followed by
   `CloseTransport`.
5. A matching current-generation reply clears debt and emits exactly one `ok`
   or `error` status.
6. A matching `HeartbeatSendFailed` clears debt, cancels the heartbeat timer,
   enters recovery closing, and emits heartbeat error, connection error,
   channel error, and close effects.
7. Stale timer IDs, generations, and refs are ignored with no effects.

### Empty-channel grace

1. `ChannelDemandDisappeared` changes demand to empty. A zero grace behaves as
   `DisconnectRequested`. A nonzero grace arms one fresh disconnect timer.
2. `ChannelDemandAppeared` changes demand to present and cancels the current
   disconnect timer.
3. A current disconnect timer fire with demand still empty disarms itself and
   performs the disconnect-intent obligations.
4. A stale timer callback cannot change intent or close a transport.

## Safety properties for the first slice

| ID | Property |
|---|---|
| `TypeOK` | Every field and nested record is in its declared domain |
| `S1_NoWorkAgainstDownIntent` | A transition whose post-intent is down has no reconnect obligation and emits no `OpenTransport` |
| `S2_FailureSchedulesRecovery` | A current open-attempt failure under up intent leaves one reconnect obligation. A recovery close records a backoff follow-up |
| `S3_PhaseOwnsTransport` | `connecting`, `open`, and `closing` own exactly one active generation. `idle` owns none |
| `S4_HeartbeatOwnedByGeneration` | Heartbeat timer and debt, when present, belong to the active open generation |
| `S5_BackoffOrdinal` | Every reconnect arm uses `nextDelayOrdinal(retryCount)`, and only a timer fire consumes an ordinal |
| `S6_HeartbeatRefreshesTokenSource` | Every normal heartbeat transition emits exactly one no-override `ResolveCurrentToken` effect |
| `T1_OneTimerPerPurpose` | Each timer purpose has at most one armed concrete identity |
| `T2_StaleEventIsolation` | A stale connection generation, timer ID, or heartbeat ref has no state-changing effects |
| `T3_FreshOpenHasNoDebt` | Entry into open has no heartbeat debt from an older generation |
| `T4_OneTransportEffect` | No transition emits two `OpenTransport` or two `CloseTransport` effects |
| `T5_DownQuiescence` | Idle down state has no active generation, heartbeat debt, or armed socket timer |
| `T6_CloseMetadataConsistent` | `closing` has a non-`none` close kind and follow-up plan. Every other phase has neither |

`S1` through `S6` retain the stable ADR names. `T1` through `T6` are structural
properties needed for conformance and vacuity checks.

## Finite review scope

The first deterministic review config uses:

| Bound | Value | Reason |
|---|---|---|
| Connection generations | 3 | One current and two stale generations |
| Timer identities | 4 | Current, canceled, and multiple stale callbacks |
| Heartbeat refs | 3 | Matching and two nonmatching refs |
| Retry count | 2 | Delay ordinals 1, 2, and capped continuation |
| Channel demand | Boolean | Empty-channel timer cancellation race |
| Failure kinds | sync, async | Both must have identical lifecycle semantics |

Policy counters use the schedule's explicit capped bucket. Identity counters
never wrap or reuse an ID because that could turn an old callback into a
current one. At the identity bound, the safety model takes a visible
TLC-only `ScopeExhausted` terminal action. Oracle export excludes that action.
The runner reports how many boundary states it reached and repeats with a
larger local profile.

## First-slice mutant matrix

These are the six socket defects applicable before channel and push composition.
Mutants are separate operators or modules, never dormant switches in the
pristine relation.

| Mutant | Defect reintroduced | Expected failure |
|---|---|---|
| `M02_BypassTokenProvider` | Omit or override the heartbeat token-resolution effect | `S6_HeartbeatRefreshesTokenSource` |
| `M05_CarryHeartbeatDebt` | Preserve debt when a generation terminates or a new one opens | `S4_HeartbeatOwnedByGeneration` or `T3_FreshOpenHasNoDebt` |
| `M06_WedgeConnectingOnSyncThrow` | Remove transport ownership while retaining `connecting` | `S3_PhaseOwnsTransport` |
| `M10_NoRetryOnSyncThrow` | Treat synchronous open failure without recovery | `S2_FailureSchedulesRecovery` |
| `M11_KeepRetryAfterDisconnect` | Leave reconnect armed when intent goes down | `S1_NoWorkAgainstDownIntent` or `T5_DownQuiescence` |
| `M12_ResetRetryDuringRecovery` | Reset `retryCount` before each internal reconnect | `S5_BackoffOrdinal` |

The runner must confirm the named invariant fails for each mutant. A different
failure does not satisfy the mutant expectation unless the manifest is reviewed
and updated.

## Exclusions from the first slice

- Channel join, leave, rejoin, and duplicate-topic policy.
- Push refs and push timeout ownership other than the heartbeat ref.
- Send-buffer contents and payload serialization.
- Token value propagation to joined channels and token-provider completion
  ordering. The model checks the lifecycle-visible provider request only.
- Presence and Postgres payload conversion.
- Platform-specific WebSocket exception types.

Each exclusion has either a later composed model, a property test, or an adapter
integration test in the ADR delivery plan.

## Review gate before TLA+ syntax

Model writing starts only after review confirms all of these:

- The state fields are sufficient to make `step` deterministic.
- Every asynchronous callback carries a generation or timer identity.
- Every in-scope current v3 await outcome maps to one listed event.
- Every shell operation maps to one listed effect.
- S1 through S6 match the intended public behavior.
- The six mutant rows represent the historical socket defects.
- No excluded concern can alter a first-slice safety property.
