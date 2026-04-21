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
