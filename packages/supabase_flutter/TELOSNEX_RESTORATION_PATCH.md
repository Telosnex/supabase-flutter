# Telosnex session-restoration patch

Base: upstream `supabase_flutter-v2.17.2` (`d343292`). No Auth/core/Realtime
package behavior or dependency versions are changed by this patch.

`Supabase.sessionRestorationComplete` is a read-only `Future<void>` for the
current initialization lifecycle. It observes the existing initial restore and
background recovery, including awaited refresh. Successful completion asserts
quiescence of that startup operation only, not signed-in/signed-out status or
durability of asynchronous event-listener persistence. Recheck current identity
and operation ownership after awaiting it.

Failures (including initial parsing failure) and disposal before completion
produce a fixed `SessionRestorationException` with no original credential-bearing
cause. Unobserved background failure is handled; a later await still receives it.
Custom `accessToken` mode completes normally since it does not restore Auth.
There is no polling, timeout, second recovery coordinator or alternate storage.
`Supabase.initialize` remains nonblocking with respect to background recovery.

A cancelled `CancelableOperation` does not stop its underlying IO. Therefore
this future is not based on `.value` (which can hang after cancellation).
Disposal rejects waiters. Reads are fenced before dispatching Auth recovery,
and the Auth client is retained rather than looked up again after storage IO.
A late old read cannot reach a newly initialized singleton. An ordinary sign-out
while storage is pending fences that read; during refresh, the existing pinned
GoTrue session-version guard discards stale responses. No new refresh algorithm
or persistence writer was introduced.

Tests: `test/session_restoration_test.dart` covers empty/stored initialSession,
delayed storage, refresh, failure, sign-out at storage and network boundaries,
disposal/reinitialization, initial-stage disposal, and custom accessToken mode.
Run alongside `initialization_test.dart`, `dispose_test.dart`, and `auth_test.dart`.
These are controlled native Flutter tests, not proof of browser-tab coordination.
