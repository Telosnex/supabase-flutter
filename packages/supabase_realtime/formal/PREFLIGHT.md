# Supabase Realtime formal preflight

This document records the pre-model evidence and constraints that were
reviewed before implementation. The model, reducer, oracle, mutants, and gate
now live beside it; see `README.md` for current commands and baselines.

## Pinned implementation targets

| Role | Package | Revision |
|---|---|---|
| Primary | `supabase_realtime 3.0.0-dev.1` | `07345bf9568a0ba495f1e34cb6ba542eddecc7e9` |
| Production compatibility | `realtime_client 2.13.0` plus Telosnex fixes | `1444084fa5c09866c7d0781172ec00ff3d8d2075` |

The primary revision is the last Realtime-changing commit reachable from the
selected upstream head. Do not silently move this pin. Rebase only at an
explicit milestone, rerun the baseline, and update the matrix below.

## Abstraction contract

The specification describes a version-neutral lifecycle protocol. Dart names
and callback or stream APIs are adapter details.

### Environment assumptions

- Frames are ordered within one WebSocket connection generation.
- Delivery across different generations has no ordering guarantee.
- A callback from an old generation can arrive after a newer generation opens.
- Connecting, sending, receiving, closing, token lookup, and server replies can
  fail.
- A timer can fire nondeterministically only while it is armed.
- Canceling a timer prevents its callback unless that callback already began.
- One user action can overlap asynchronous library work.
- Explicit disconnect intent dominates automatic reconnect intent.
- No fairness assumption is used to establish a safety property.
- Weak fairness can be enabled for selected environment actions when checking a
  liveness property. Every such assumption must be named in its model config.

### State hidden behind adapters

- WebSocket objects become monotonically increasing connection generations.
- Timer objects become named armed or disarmed obligations.
- Callback and stream delivery become typed lifecycle events.
- Tokens become monotonically increasing token generations.
- Payload bodies, serialization, SQL data, and the Realtime server internals
  remain out of scope unless a lifecycle property needs them.

## v3 regression baseline

The historical v2.13 regressions compile unchanged in meaning against the
pinned v3 API. The baseline run produced 31 passes, 11 assertion failures, and
5 errors. These 16 non-passing cases mean the historical defects remain
observable. They are expected at this stage.

| ID | Historical defect | v2.13 fork | v3 baseline | Candidate property |
|---|---|---|---|---|
| R01 | `Push.resend` retains the stale timeout timer | fixed | 2 assertion failures | Resend owns one fresh ref and timer |
| R02 | Heartbeat bypasses `customAccessToken` | fixed | 1 assertion failure | Each normal heartbeat requests the current token source once |
| R03 | Null or missing Postgres record fields crash | fixed | 4 errors | Payload conversion is total |
| R04 | Presence sync mutates its input | fixed | 2 assertion failures | Presence input is immutable |
| R05 | A fresh socket inherits a pending heartbeat | fixed | 1 assertion failure | Fresh generation has no old heartbeat debt |
| R06 | Synchronous transport throw leaves `connecting` | fixed | 1 assertion failure | Connection phase matches owned transport |
| R07 | Join `phx_error` does not schedule rejoin | fixed | 1 assertion failure, 1 error | Join rejection enters retryable error state |
| R08 | Rejoin timer auto-reschedules while work is active | fixed | 1 assertion failure | At most one rejoin obligation exists |
| R09 | Rejoin evicts its own channel | fixed | 1 assertion failure | Duplicate eviction excludes the caller |
| R10 | Connect outer catch does not schedule reconnect | fixed | 1 assertion failure | Failed connect honors reconnect intent |

R03 and R04 are deterministic data properties. Keep their Dart regressions,
but do not force them into a lifecycle state-machine model.

Baseline command:

```bash
cd packages/supabase_realtime
dart test \
  test/push_resend_test.dart \
  test/heartbeat_test.dart \
  test/transformers_test.dart \
  test/realtime_presence_test.dart \
  test/heartbeat_lifecycle_test.dart \
  test/sync_transport_throw_test.dart \
  test/join_error_rejoin_test.dart \
  test/channel_rejoin_timer_test.dart \
  test/channel_self_unsubscribe_test.dart \
  test/socket_outer_catch_reconnect_test.dart
```

Expected baseline: exit 1 with 31 passes, 11 assertion failures, and 5 errors.
Any different result requires review before modeling or refactoring.

## Implemented formal gate

The model, finite configurations, and runner implement this fixed contract:

1. Verify the pinned `tla2tools.jar` SHA-256 before execution.
2. Parse every pristine model and run every positive finite configuration.
3. Require all named safety invariants to pass.
4. Run each historical mutant and require its expected invariant to fail.
5. Record generated states, distinct states, queue depth, and search depth.
6. Fail when a mutant unexpectedly passes or its expected violation disappears.
7. Keep safety and liveness profiles separate.
8. Use fixed worker and seed settings in the reproducible profile.
9. Permit a larger local exploration profile without making it the review gate.

State counts are baselines, not proofs. Review count changes with the model diff
instead of requiring exact equality forever.

## Toolchain inventory

Required command-line toolchain:

- Java 21 or newer.
- TLA+ tools release `v1.8.0`.
- `tla2tools.jar` SHA-256
  `ab323b79802aedc3203b3f9af37c6aca3ed43f4e0225b36f2aa77b26de46c05f`.
- Download URL:
  `https://github.com/tlaplus/tlaplus/releases/download/v1.8.0/tla2tools.jar`.

Local discovery found Java 21 at the Android Studio JBR and TLA+ Toolbox 2.19.
The reproducible gate will use the pinned standalone jar, not the Toolbox jar.
Apalache is not installed and is not required for the first loop.

Example verification only:

```bash
shasum -a 256 /path/to/tla2tools.jar
java -cp /path/to/tla2tools.jar tlc2.TLC -help
```

## Conformance design

The model and the Dart kernel stay locked together by mechanism, not by review
discipline. The locks, in gate order:

1. `formal/manifest.json` names every state field, event, action, effect, and
   trace encoding. A generator emits both the TLA+ schema and Dart schema. A
   check-mode regeneration fails on any byte difference. Finite TLC bounds
   remain in configs so production refs and generations are not bounded.
2. The kernel owns one immutable `ModelState` with exactly the manifest fields.
   A total deterministic `step(ModelState, Event)` returns disposition, action,
   post-state, and ordered effects. Every environment choice is an event value.
3. For finite scope B, TLC exports every reachable state `R_B`, every event
   `E_B`, and one transition-oracle row for every pair in `R_B × E_B`. A Dart
   test compares the real kernel with every row, field by field. Missing rows or
   two results for one pair fail. This proves both finite inclusions.
4. Every kernel step emits a schema-hashed trace. TLC `-loadTrace json`
   validation rejects any observed step outside the model at larger scopes.
5. An action and invariant coverage check fails on missing fields, events,
   oracle rows, traces, invariant evaluations, or expected mutant failures.
6. The ten lifecycle defects (#1, #2, #5–#12 in the ADR) become TLA+ mutants and
   Dart patches under `formal/mutants/`. The formal harness must catch each
   without its handwritten regression. Property tests catch mutant forms of
   the two data defects (#3 and #4), which remain outside the lifecycle model.

The shell classifies external outcomes into events but cannot mutate
`ModelState` or choose lifecycle policy. An architecture test enforces that
boundary. Timer and transport handles retain the identities allocated by model
effects.

Change protocol: a contract change touches the spec, kernel, and tests in one
commit, plus the manifest and generated schemas when vocabulary changes. A Dart
correction can leave the model untouched when it makes divergent code conform
to that model. A pure refactor lands alone only when finite oracle equivalence
and runtime trace validation show no modeled behavior changed. The reserved
paths landed with the model and kernel work.

## Branch and review policy

- Develop on `telosnex/realtime-v3-formal` from the pinned upstream revision.
- Keep formal assets free of Telosnex application dependencies and vocabulary.
- Separate baseline tests, model and tooling, instrumentation, and behavior
  changes into reviewable commits.
- Establish a contract change in the model before or atomically with its Dart
  implementation. Never change both independently and reconcile them later.
- Do not adopt v3 in the Telosnex application as part of this work.
