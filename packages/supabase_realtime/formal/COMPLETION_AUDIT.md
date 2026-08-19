# ADR 013 completion audit

Objective: deliver the lifecycle refactor described by
`telosnex/lib/features/sync/docs/ADR_013_SUPABASE_REALTIME_FORMAL_REFACTOR.md`
on the pinned v3 branch without pushing code.

Audit date: August 18, 2026. Every `Met` row below has repository and command
evidence; model checking is not treated as proof of platform or server code.

## Goals and invariant catalog

| Requirement | Evidence | Status |
|---|---|---|
| G1/G2: named properties and enforcement | S1–S6/T1–T6 in `SocketTransitions.tla`; C1–C4/P1–P2 in `ChannelPushTransitions.tla`; L1–L4 in separate liveness modules/configs | Met |
| G3: every historical defect has a detector | Ten TLA+ mutants, ten lifecycle Dart patches, two data Dart patches | Met |
| G4: upstream-shaped work on pinned v3 | Manifest pin `07345bf...`; v3 public package API retained | Met |
| Socket S1–S6 | Positive TLC config, six model mutants, 99,800-row Dart oracle | Met |
| Channel C1–C4 | Composed TLC config, three model mutants, 3,712-row Dart oracle | Met |
| Push P1–P2 | Composed TLC config, push mutant, 285-row Dart oracle | Met |
| L1–L4 | `SocketLiveness.*` and `ChannelPushLiveness.*`, with named weak fairness | Met |

## Layer 1: models

| ADR requirement | Evidence | Status |
|---|---|---|
| Version-neutral socket, channel, push models | `SocketTransitions.tla`, `ChannelPushTransitions.tla` | Met |
| Safety separated from liveness/fairness | Four positive configs; no fairness in safety specs | Met |
| Two-channel finite composition | `ChannelPushSafety.cfg`: two channels, refs/epochs/timers bounded to three | Met |
| Environment outcomes explicit | Success, sync/async error, stream/server close, timeout, stale callbacks, and replies are generated events | Met |
| Ten lifecycle model mutants | M01, M02, M05–M12 under `mutants/tla` | Met |
| Data boundary validated outside TLA+ | Null payload and presence-purity property tests plus D03/D04 Dart patches | Met |
| Metrics recorded | `.dart_tool/realtime_formal/gate/report.json`; baselines in `README.md` | Met |

## Layer 2: explicit machines

| ADR requirement | Evidence | Status |
|---|---|---|
| Intent split from socket phase | Generated `SocketModelState`; public `SocketState` is derived | Met |
| Pure total reducer per machine | `RealtimeSocketKernel`, `RealtimeChannelKernel`, `RealtimePushKernel` | Met |
| Explicit serial event queues | FIFO `Queue` in each driver; transitions run synchronously before effects | Met |
| Await outcomes become later events | Transport readiness/close/error, timers, heartbeat, channel replies, and push replies dispatch generated events | Met |
| Owned timer/ref/epoch obligations | Generated obligation records, ID-tagged shell handles, stale-event isolation, post-batch representation assertions | Met |
| Public v3 API unchanged | Full package tests and both protocol integration suites pass | Met |
| v2.13 compatibility mapping | `realtime_v2_13_adapter.dart`; 13 clauses checked against pin `1444084...` | Met |

## Layer 3: conformance

| ADR §9 requirement | Evidence | Status |
|---|---|---|
| Applied/ignored/rejected deterministic `Step` | All three TLA+ and Dart reducers | Met |
| One generated vocabulary | `manifest.json` emits `KernelSchema.tla` and `model_schema.dart`; byte check in gate | Met |
| Model state is code state | Only drivers assign successor state; architecture test forbids shell `copyWith`/state assignment | Met |
| Representation assertions | Driver validators check model-owned transport/timer/ref/epoch handles after quiescent effect batches | Met |
| Complete finite equivalence | Socket 99,800; channel 3,712; push 285 rows, field/effect order compared | Met |
| Shortest initial prefixes | Socket depth 18; channel 7; push 5; real reducers replay every oracle pre-state | Met |
| Runtime trace replay | Multi-machine `LifecycleTraceValidation.tla` with `-loadTrace json` | Met |
| Larger-scope randomized trace | 600 seeded fake-clock events, 200 per machine, TLC accepted | Met |
| Every finite action covered | 55 oracle action IDs; 52 accepted actions emitted in 147 prefix trace entries; three rejection actions covered by oracle | Met |
| Every invariant evaluated | Positive configs list every declared safety/liveness property | Met |
| TLA+ reinjection | Ten mutants fail exactly their expected property | Met |
| Dart reinjection in worktrees | Twelve patches copied/applied in temporary Git worktree; every detector fails | Met |
| Ordered deterministic gate | `formal/tool/run_tlc.dart` implements tool pin, schemas, models, mutants, oracles, prefixes, traces, random walk, and mutation audit | Met |

## Property, package, and integration gates

| Requirement | Evidence | Status |
|---|---|---|
| Presence transform does not mutate input | `realtime_presence_test.dart`; D04 mutation caught | Met |
| Missing/null payload conversion is total | `transformers_test.dart`; D03 mutation caught | Met |
| Serializer finite round trip | `serializer_property_test.dart`: 720 text-frame combinations | Met |
| Seeded random walk/fake clock | `generate_random_trace.dart`; 600 entries accepted by TLC | Met |
| Historical regressions | 47/47 targeted historical tests pass | Met |
| Full package unit suite | `dart test -x integration`: 222/222 pass | Met |
| Real-server suite | Local Supabase stack: 22/22 pass across protocol 1.0 and 2.0 | Met |
| Real-server trace soak | Integration test captures actual socket/channel/push behavior and TLC accepts it for both protocols | Met |
| Static/generated checks | `dart analyze`, schema check, model-hash check, v2 adapter check | Met |

## Artifact mapping

The ADR's planned names were adapted without weakening the boundary:

- `realtime_kernel.dart` is split by machine into three reducer files.
- `effect_executor.dart` is represented by typed executors in three drivers and
  exhaustive shell switches.
- `test/formal/*` equivalents live under `test/kernel/*` plus the integration
  trace test.
- Generated finite socket oracle is checked in compressed form; channel/push
  dumps are generated under `.dart_tool`, as required for transient artifacts.

## Honest limits

- Finite equivalence is scoped to the declared bounds; it is not an unbounded
  proof.
- TLC does not verify Dart's timer implementation, `web_socket_channel`, the
  Realtime server, or platform scheduling.
- Representation assertions and real-server traces reduce shell drift but do
  not constitute a refinement proof.
- Liveness transfers only under the named weak-fairness assumptions.
- The v2 adapter checks the pinned fork's source/event seams; Telosnex remains
  on v2 and is not migrated by this work.

## Final command evidence

```text
dart run formal/tool/run_tlc.dart --update-oracle  PASS
dart analyze                                  PASS
dart test -x integration                      222 PASS
dart test -j 1 test/realtime_integration_test.dart  22 PASS
```

The local Supabase stack was stopped after the integration run. No code was
pushed to a remote.
