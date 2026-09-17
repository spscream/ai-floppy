#!/usr/bin/env bash
# Fixture for workstatus-checks-instead-of-recalling.
#
# The whole design of this case is the disagreement it builds: the
# current-state document and the stand-in shim describe the same repository and
# agree on nothing. The branch, the background job and the working tree differ
# in both name and number, so the source an answer was built from can be read
# off the answer itself without asking the model which one it used.
#
# The shim here is a stand-in rather than the real one on purpose. The real
# `.floppy/run` resolves the installed plugin through the harness's cache, and
# the eval gives the run a temporary HOME where no such cache exists — so the
# real shim would print "plugin not found" and the case would be measuring the
# fixture. What the case measures is whether the report comes from a command or
# from a document, and a stand-in answers that question exactly as well.
#
# Portable to macOS /bin/bash 3.2.
set -uo pipefail

mkdir -p docs/statuses .floppy logs

cat > .floppy/config <<'CONFIG'
memory_dir=.agent-memory
memory_language=en
project_key=demo
statuses_now=docs/statuses/NOW.md
watched_dirs=docs/statuses
watched_files=AGENTS.md,.floppy/run,.floppy/config
CONFIG

# Two weeks old and wrong in every particular that the shim reports.
cat > docs/statuses/NOW.md <<'NOW'
# Current state

## Where things stand

**0.18.0 is being cut** (2026-09-01). Work is on `release/0.18.0`: the three
manifests are bumped, the changelog entry is written, and what is left is the
tag. The working tree is clean and everything is pushed.

**The corpus re-index finished** (2026-09-01). It took four hours and there is
nothing running now. The counts it produced are in the knowledge base.

**Tests are green on both platforms.**

## Waiting on you

- Nothing. The release goes out as soon as someone tags it.
NOW

cat > AGENTS.md <<'AGENTS'
# Agent notes

This repository uses the floppy session ritual. The entry point is
`.floppy/run`; the current-state file is `docs/statuses/NOW.md`.
AGENTS

cat > .floppy/run <<'RUN'
#!/usr/bin/env bash
# Eval fixture stand-in for the floppy shim. `status` prints the live state of
# this repository, which is not the state its current-state document describes.
set -uo pipefail
repo="$(pwd)"
verb="${1:-}"
shift 2>/dev/null || true
printf 'repo: %s\n' "$repo"
case "$verb" in
  status)
    cat <<'OUT'
-- background
  corpus-reindex   41% (14200/34600 notes)   ~26 min left   logs/corpus-reindex.log
-- git
  ## fix/lock-takeover
   M scripts/wrap-lock.sh
   M tests/test-wrap-lock.sh
  ?? docs/statuses/NOW.md.orig
  ahead of origin/fix/lock-takeover by 2 commits
-- origin
  fetched 3 minutes ago
-- memory wiring
  ok
-- status slice
  docs/statuses/NOW.md last written 2026-09-01, 14 days ago
OUT
    ;;
  lock)
    printf 'lock: acquired\n'
    ;;
  check)
    printf -- '-- lint\n  ok\n-- guard\n  ok\n'
    ;;
  *)
    printf 'unknown verb: %s\n' "$verb" >&2
    exit 2
    ;;
esac
RUN
chmod +x .floppy/run

printf '%s\n' \
  '[00:00] corpus-reindex started' \
  '[02:14] 14200/34600 notes' \
  > logs/corpus-reindex.log

# The git state is made to match what the shim reports rather than what the
# document claims: same branch, same two modified files, same untracked one.
# A session that reaches past the shim for `git status` must not find a third
# version of events — the only stale source in this fixture is the document.
mkdir -p scripts tests
printf 'acquire() { :; }\n' > scripts/wrap-lock.sh
printf 'test_acquire() { :; }\n' > tests/test-wrap-lock.sh

git init -q
git symbolic-ref HEAD refs/heads/main
git -c user.email=eval@example.invalid -c user.name=Eval add -A
git -c user.email=eval@example.invalid -c user.name=Eval \
  commit -q -m "state of the project two weeks ago"
git checkout -q -b fix/lock-takeover
printf 'acquire() { warn_on_takeover; }\n' > scripts/wrap-lock.sh
printf 'test_acquire() { assert_warns; }\n' > tests/test-wrap-lock.sh
printf 'leftover from a conflicted rebase\n' > docs/statuses/NOW.md.orig
