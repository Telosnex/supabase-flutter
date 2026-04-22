#!/usr/bin/env bash
#
# tools/telosnex-resync.sh
#
# Rebase every telosnex fix branch onto upstream/main and rebuild
# telosnex/integration from scratch.
#
# Usage:
#   ./tools/telosnex-resync.sh             # rebase fixes, rebuild integration, push all
#   ./tools/telosnex-resync.sh --no-push   # local rebuild only; skip all force-pushes
#   ./tools/telosnex-resync.sh --no-test   # skip dart test + dart analyze
#
# Adding a new fix branch:
#   1. git checkout upstream/main && git checkout -b fix/new-thing
#   2. commit the fix + its test, push to origin
#   3. append "fix/new-thing" to FIX_BRANCHES below
#   4. commit & push this file on telosnex/tooling
#   5. run ./tools/telosnex-resync.sh
#
# Removing a fix branch (e.g. upstream merged your PR):
#   Delete its entry from FIX_BRANCHES, commit on telosnex/tooling, re-run.
#
# Design note: this script lives on telosnex/tooling (NOT on integration
# directly) because the rebuild step does `git reset --hard upstream/main`,
# which would remove the script from disk mid-execution. Merging the tooling
# branch first restores it in the rebuilt working tree.

set -euo pipefail

# ------------------------------------------------------------------- config --

FIX_BRANCHES=(
  fix/push-resend-stale-timer
  fix/heartbeat-custom-access-token
  fix/delete-null-old-record
  fix/presence-transform-mutation
  # The three below were derived from the TLA+ models in
  # packages/realtime_client/formal_models/ and each has a dedicated
  # Dart regression test verified red on upstream/main before the fix.
  fix/disconnect-leak-reconnect-timer
  fix/stale-pending-heartbeat-ref
  fix/connect-sync-transport-throw
  # Diagnosed from a field log showing "Invalid JWTToken: Token has expired
  # 29380 seconds ago" on iOS app resume after 8h suspension. Missing
  # joinPush.receive('error', …) handler in RealtimeChannel constructor
  # left channels stuck in `joining` forever after a server-side join
  # rejection. The fix mirrors supabase-js / Phoenix JS exactly.
  fix/channel-stuck-on-join-error
  # Discovered via the debug-sim menu entry (Supa.debugSimulateLongSleep
  # Resume) after the channel-stuck-on-join-error fix was verified: the
  # channel's `_rejoinTimer` callback auto-rescheduled itself at the top
  # of `rejoinUntilConnected`, causing the timer to fire again on the
  # *next* backoff interval regardless of whether the first rejoin was
  # still awaiting a server reply. Modern supabase-js (delegating to
  # @supabase/phoenix) and canonical Phoenix JS both do NOT
  # auto-reschedule. The pre-phoenix supabase-js that this Dart port
  # was derived from did — it was carried over verbatim and has been
  # latent ever since.
  fix/rejoin-timer-no-auto-reschedule
  # Belt-and-suspenders for the above: `RealtimeChannel.rejoin()` also
  # called `socket.leaveOpenTopic(topic)` which, with no identity check,
  # could match the calling channel itself (when in joining/joined) and
  # unsubscribe it. The doc-comment on `forceRejoin` already documented
  # this hazard and worked around it for its own path; we extend the
  # same protection to `rejoin()` via an `except:` parameter. Fires
  # only if the auto-reschedule regresses or if external code drives
  # rejoin() manually while the channel is live.
  fix/rejoin-self-unsubscribe
  # Field repro: on iOS app resume after long background suspension,
  # `WebSocketChannelException: HandshakeException: Connection terminated
  # during handshake` fired once per channel, then silence — no recovery
  # until app relaunch. connect()'s *inner* `await localConn.ready` catch
  # already armed `reconnectTimer.scheduleTimeout()`; the *outer* catch
  # (synchronous throws from transport() or anything else before the
  # .ready await) did not. Completes what `fix/connect-sync-transport-
  # throw`'s commit message explicitly deferred ("Conservative scope: no
  # new reconnect scheduling here"). Same connState guard as the inner
  # catch, and also moves `_onConnError(e)` inside the guard so a
  # user-initiated disconnect mid-connect doesn't surface a spurious
  # error to listeners.
  fix/connect-sync-throw-schedule-reconnect
  # Field repro: turning wifi off while the socket was connected
  # produced a flat ~1024ms retry cadence forever (378 errors over
  # ~40s in the captured log; no exponential backoff). Caused by an
  # interaction between the earlier `fix/disconnect-leak-reconnect-
  # timer` (which moved reconnectTimer.reset() to always fire in
  # disconnect()) and the reconnect timer's callback, which called
  # disconnect() before connect() on every tick — zeroing _tries each
  # retry so scheduleTimeout() always computed `reconnectAfterMs(1)
  # = firstDelay`.
  #
  # Fix: retry callback nulls `conn` directly and calls connect(),
  # bypassing disconnect() entirely. Stacks cleanly with the earlier
  # disconnect-leak fix; either branch alone also works, only
  # together do they yield both invariants (user disconnect cancels
  # armed reconnect AND retry callback preserves backoff).
  fix/retry-callback-preserves-backoff-tries
)

TOOLING_BRANCH="telosnex/tooling"
INTEGRATION_BRANCH="telosnex/integration"
UPSTREAM_REMOTE="upstream"
UPSTREAM_BRANCH="main"
ORIGIN_REMOTE="origin"

# Paths to run dart test + dart analyze against. Add more as fixes land in
# other packages.
TEST_PACKAGES=(
  packages/realtime_client
)

# ------------------------------------------------------------------- flags ---

PUSH=1
RUN_TESTS=1
for arg in "$@"; do
  case "$arg" in
    --no-push) PUSH=0 ;;
    --no-test) RUN_TESTS=0 ;;
    -h|--help)
      sed -n '2,30p' "$0"
      exit 0
      ;;
    *)
      echo "unknown flag: $arg" >&2
      exit 2
      ;;
  esac
done

# --------------------------------------------------------------------- run ---

REPO_ROOT="$(git rev-parse --show-toplevel)"
cd "$REPO_ROOT"

# Refuse to run on a dirty tree — rebases and resets would eat local work.
if ! git diff --quiet || ! git diff --cached --quiet; then
  echo "✗ working tree has uncommitted changes. commit or stash first." >&2
  exit 1
fi

echo "==> Fetching $UPSTREAM_REMOTE"
git fetch "$UPSTREAM_REMOTE" --quiet

echo "==> Rebasing ${#FIX_BRANCHES[@]} fix branch(es) + tooling onto $UPSTREAM_REMOTE/$UPSTREAM_BRANCH"
for b in "$TOOLING_BRANCH" "${FIX_BRANCHES[@]}"; do
  echo "  - $b"
  git checkout --quiet "$b"
  git rebase "$UPSTREAM_REMOTE/$UPSTREAM_BRANCH"
  if [[ $PUSH -eq 1 ]]; then
    git push "$ORIGIN_REMOTE" "$b" --force-with-lease
  fi
done

echo "==> Rebuilding $INTEGRATION_BRANCH from $UPSTREAM_REMOTE/$UPSTREAM_BRANCH"
git checkout --quiet "$INTEGRATION_BRANCH"
git reset --hard "$UPSTREAM_REMOTE/$UPSTREAM_BRANCH"

# Merge tooling FIRST so this script and its siblings are present in the
# rebuilt working tree (handy for anyone inspecting the integration branch).
for b in "$TOOLING_BRANCH" "${FIX_BRANCHES[@]}"; do
  echo "  merging $b"
  git merge --no-ff "$b" -m "merge: $b"
done

if [[ $RUN_TESTS -eq 1 ]]; then
  echo "==> Running tests + analyzer"
  for pkg in "${TEST_PACKAGES[@]}"; do
    echo "  - $pkg"
    ( cd "$pkg" && dart test && dart analyze --fatal-infos )
  done
fi

if [[ $PUSH -eq 1 ]]; then
  echo "==> Pushing $INTEGRATION_BRANCH"
  git push "$ORIGIN_REMOTE" "$INTEGRATION_BRANCH" --force-with-lease
fi

echo ""
echo "✓ $INTEGRATION_BRANCH rebuilt from $(git rev-parse --short "$UPSTREAM_REMOTE/$UPSTREAM_BRANCH") + ${#FIX_BRANCHES[@]} fix(es) + tooling."
echo "  Consumers on 'ref: $INTEGRATION_BRANCH' pick this up via:"
echo "      flutter pub upgrade realtime_client"
