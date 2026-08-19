# Supabase Realtime lifecycle formal model

This directory contains the version-neutral socket, channel, and push lifecycle
contract; TLA+ models; pure Dart reducers; generated schemas; defect mutants;
and model/code conformance tooling. The models describe desired behavior.
Historical defects exist only in isolated mutant artifacts.

## Reproducible gate

From `packages/supabase_realtime`:

```bash
dart run formal/tool/run_tlc.dart
```

The command uses one worker, seed 1, and fingerprint polynomial 0. It:

1. verifies Java 21+, the pinned TLA+ 1.8.0 jar SHA-256, generated schemas,
   model hash, and the pinned v2.13 adapter clauses;
2. checks pristine socket and channel/push safety configurations;
3. checks separate weak-fairness liveness profiles for L1–L4;
4. requires all ten lifecycle TLA+ mutants to fail exactly their assigned
   invariant;
5. exports complete finite transition oracles and compares every field and
   ordered effect with the production Dart reducers;
6. generates and replays shortest initial prefixes to every finite oracle
   pre-state;
7. generates accepted Dart traces covering all 52 non-rejected action IDs and
   validates them with TLC `-loadTrace json`;
8. applies ten lifecycle and two data Dart patches in a temporary Git worktree,
   requiring an oracle or property-test failure for each;
9. validates a three-machine sample trace and a 600-event seeded fake-clock
   random walk with TLC.

Use `--jar PATH` to select the pinned jar. A reviewed model/schema change makes
the committed socket oracle stale; regenerate explicitly with:

```bash
dart run formal/tool/run_tlc.dart --update-oracle
```

TLC dumps, metadata, generated traces, mutation worktrees, and `report.json`
stay under `.dart_tool/realtime_formal/` or the system temporary directory.

## Deterministic review baselines

### Socket

`SocketSafety.cfg` bounds generations to 3, timer IDs to 4, heartbeat refs to
3, and retry count to 2. IDs never wrap. Allocation at a bound records a
TLC-only `ScopeExhausted` terminal state.

- safety: 42,066 generated / 2,370 distinct states, depth 23;
- protocol states: 1,684, including 686 boundary-marker counterparts;
- oracle: 998 pre-states × 100 events = 99,800 rows;
- all 30 action IDs covered (29 accepted, one contract rejection);
- shortest accepted prefix depth: 18;
- liveness abstraction: 79 generated / 24 distinct states, depth 9.

### Channel and push

`ChannelPushSafety.cfg` uses two channel identities, three join epochs, three
timer IDs, and three push refs.

- composed safety: 93,594 generated / 9,216 distinct states, depth 15;
- unique protocol states: 208 channel and 28 push states;
- channel oracle: 128 pre-states × 29 events = 3,712 rows;
- push oracle: 19 pre-states × 15 events = 285 rows;
- all 25 action IDs covered (23 accepted, two contract rejections);
- shortest prefix depths: channel 7, push 5;
- liveness abstraction: 131 generated / 36 distinct states, depth 14.

Counts are review evidence, not unbounded proofs. `SocketSafetyLocal.cfg`
provides a larger optional socket profile and is not part of the normal gate.

## Properties

- Socket: S1–S6 plus structural T1–T6.
- Channel: C1 rejected/timeout joins recover; C2 rejoin timer ownership; C3
  duplicate eviction excludes its requester; C4 old join epochs are isolated.
- Push: P1 every send owns a nonempty ref and timer; P2 at most one terminal
  delivery.
- Liveness: L1 healed subscribed channels join; L2 pushes terminate; L3 down
  sockets quiesce; L4 healed up sockets open.

Safety uses no fairness. Liveness files name each weak-fairness assumption.

## Production architecture

`RealtimeSocketKernel`, `RealtimeChannelKernel`, and `RealtimePushKernel` are
pure total reducers. Their drivers are the sole state owners and contain
explicit FIFO event queues. Public calls and asynchronous callbacks enqueue
generated events. State changes before ordered effects execute. Effects perform
transport, timer, token, stream, and reply-binding work and post outcomes as
later events.

The existing v3 constructors, methods, status streams, transport injection,
`SocketState`, channel API, and push behavior remain adapters over the kernels.
Debug representation checks tie model obligations to concrete transport,
timer, epoch, and ref handles after quiescent effect batches.

`realtime_v2_13_adapter.dart` maps the callback-oriented v2.13 surface to the
same generated event vocabulary. `verify_v2_adapter.dart` checks its clauses
against Git commit `1444084fa5c09866c7d0781172ec00ff3d8d2075`.

## Runtime traces

Every transition records:

- schema and model hashes;
- machine and instance identity;
- per-instance sequence number;
- event, action, disposition;
- complete pre/post state;
- ordered effects.

`RealtimeClient.logger` receives socket traces as `formal/socket_transition`
and channel/push traces as `formal/lifecycle_transition`. Store one trace map
per JSON line, then run:

```bash
dart run formal/tool/validate_trace.dart path/to/trace.ndjson
```

The validator groups machine instances, injectively preserves runtime IDs,
requires an initial state and contiguous sequence, derives sufficient numeric
bounds, and asks TLC to replay every labeled step. The real-server integration
suite performs this check for both protocol 1.0 and 2.0.

## Main artifacts

- `manifest.json`: shared socket/channel/push state, event, action, effect, and
  trace vocabulary.
- `SocketTransitions.tla`, `RealtimeSocket.tla`: socket reducer and safety.
- `ChannelPushTransitions.tla`, `RealtimeChannelPush.tla`: channel/push
  reducers and composed safety.
- `SocketLiveness.tla`, `ChannelPushLiveness.tla`: separate liveness models.
- `SocketOracle.tla`, `ChannelOracle.tla`, `PushOracle.tla`: finite oracle
  evaluators.
- `LifecycleTraceValidation.tla`: concrete multi-machine trace replay.
- `mutants/tla/`: ten isolated lifecycle model mutants.
- `mutants/dart/`: ten lifecycle and two data reinjection patches.
- `oracle/socket_transition_oracle.json.gz`: deterministic compressed socket
  oracle; channel/push oracle dumps remain transient.
- `tool/run_tlc.dart`: the complete deterministic gate.
