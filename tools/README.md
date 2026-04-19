# telosnex fork tooling

Telosnex maintains a small set of fixes to `supabase-flutter` that haven't
landed upstream yet. This directory contains the scripts and conventions
that keep the fork cheap to live on.

The per-script usage, flags, and add/remove commands are documented in the
script headers themselves (e.g. `tools/telosnex-resync.sh --help`). This
README is the *context* — what the branches are for, why the structure is
shaped this way, and how your app consumes it.

## Branch topology

```
upstream/main      (supabase/supabase-flutter — we never commit here)
│
├── fix/<slug>                  one topic branch per upstream-PR candidate,
│                               each one commit off upstream/main, each
│                               containing the fix + its regression test
│
├── telosnex/tooling            holds this README and tools/*.sh
│
└── telosnex/integration        disposable merge artifact — consumed by
                                app pubspecs via `ref: telosnex/integration`
                                rebuilt from scratch on every resync
```

**Rules that keep it working:**

1. `fix/*` branches always fork from `upstream/main`, never from each other.
   That's what makes them independent — a maintainer can cherry-pick any
   one without pulling the others.
2. Each `fix/*` branch contains exactly one fix + one test for that fix.
   No cross-contamination.
3. `telosnex/integration` never receives direct commits. It's rebuilt by
   `tools/telosnex-resync.sh` whenever upstream moves or the fix set
   changes.
4. `telosnex/tooling` is merged into integration first, before any fix
   branch, so the scripts are always present in the rebuilt working tree.

**Why not stacked branches?** Tempting to have `fix/2` branch off `fix/1`
so integration is a simple fast-forward. Don't — the moment upstream
merges PR #2 before PR #1 you're untangling rebases forever. Independent
topic branches + disposable integration branch is boring and robust.

## Day-to-day

All three workflows run the same script at the end; only the prep
differs.

### Upstream just released

```bash
./tools/telosnex-resync.sh
```

That's it. The script rebases every fix branch onto the new
`upstream/main`, force-pushes each, then rebuilds and force-pushes
`telosnex/integration`.

### Adding a new fix

```bash
git checkout upstream/main
git checkout -b fix/new-thing
# edit, test, commit
git push -u origin fix/new-thing

# register it with the resync script
git checkout telosnex/tooling
# edit tools/telosnex-resync.sh: append "fix/new-thing" to FIX_BRANCHES
git commit -am "chore(telosnex): register fix/new-thing"
git push

./tools/telosnex-resync.sh
```

### Retiring a fix (upstream merged your PR 🎉)

```bash
git checkout telosnex/tooling
# edit tools/telosnex-resync.sh: remove "fix/foo" from FIX_BRANCHES
git commit -am "chore(telosnex): retire fix/foo (merged upstream as #NNNN)"
git push

./tools/telosnex-resync.sh

# Optional cleanup
git branch -D fix/foo
git push origin :fix/foo
```

## Consuming from your app

`pubspec.yaml`:

```yaml
dependency_overrides:
  realtime_client:
    git:
      url: https://github.com/telosnex/supabase-flutter.git
      path: packages/realtime_client
      ref: telosnex/integration    # branch, not SHA
```

Then in your app repo:

```bash
flutter pub get                    # first time
flutter pub upgrade realtime_client  # after each fork resync
```

Tracking the **branch** (not a SHA) means `pubspec.yaml` never needs to be
touched after a resync. `pubspec.lock` will still pin to an exact commit
(the `resolved-ref` field), so builds are reproducible — `flutter pub
upgrade realtime_client` is the deliberate "adopt latest" step.

If you need to override other packages (`supabase`, `supabase_flutter`)
at the same monorepo SHA, add matching entries pointing at the same
`ref` and the corresponding `path:`. Usually unnecessary — overriding
`realtime_client` alone flows through the transitive deps.

## Filing upstream PRs

Each `fix/*` branch is already one clean commit. Open each as its own PR
against `supabase/supabase-flutter:main`:

```
https://github.com/supabase/supabase-flutter/compare/main...telosnex:fix/<slug>
```

When one gets merged, retire it per the workflow above.

## Troubleshooting

**Rebase conflict on a fix branch.** Upstream probably touched the same
file you did. Resolve it, `git rebase --continue`, `git push --force-
with-lease`, then re-run the script. If it's a semantic merge (upstream
re-worked the area your fix touches), consider whether the fix is still
needed.

**`--force-with-lease` rejected.** Someone (or CI) pushed to the remote
branch after you last pulled. `git fetch origin`, inspect the delta,
decide whether to incorporate it.

**Dirty working tree.** The script refuses to run. `git stash` or
`commit` first; the script will reset-hard during rebuild and happily
throw away anything uncommitted.

**Test fails on integration but not on the fix branch alone.** Two fixes
interact in a way neither exposed individually. Time for a combined
regression test. Add it to whichever fix branch is more naturally its
home, or split it out into a new `fix/` branch.

**Script deleted itself mid-run.** Shouldn't happen — `telosnex/tooling`
is merged into integration before the `reset --hard`. If it does, your
`FIX_BRANCHES` list probably lists `telosnex/tooling` after some fix
branches, or `TOOLING_BRANCH` is mis-set. Check the script's merge
loop ordering.
