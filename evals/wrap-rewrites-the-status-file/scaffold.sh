#!/usr/bin/env bash
# Fixture for wrap-rewrites-the-status-file.
#
# Runs with the eval's working directory as cwd, a temporary HOME, and no
# network. It builds the smallest consumer repository the wrap rite needs: a
# current-state file long enough that patching it looks like the cheaper
# option, and a stand-in `.floppy/run` so `lock`, `check` and `commit` answer
# without the real plugin being resolvable from this temporary HOME.
#
# The stand-in is deliberate. What this case measures is how the status file
# gets written, and the shim verbs do not touch that — but a rite whose first
# call dies takes the run with it, and the case would then be measuring the
# fixture instead of the rule.
#
# Portable to macOS /bin/bash 3.2, like everything else in this repository.
set -uo pipefail

mkdir -p docs/statuses .floppy

cat > .floppy/config <<'CONFIG'
memory_dir=.agent-memory
memory_language=en
project_key=demo
statuses_now=docs/statuses/NOW.md
watched_dirs=docs/statuses
watched_files=AGENTS.md,.floppy/run,.floppy/config
statuses_regress_marks=worse
CONFIG

cat > docs/statuses/NOW.md <<'NOW'
# Current state

What `start` reads in full, rewritten in place rather than appended to. This
is the project's half only; one person's thread of work belongs in the
personal status file, in the private scope.

## Where things stand

**The lock is still per-checkout** (2026-09-02). `lock acquire` serialises two
sessions writing the same memory, but a lock left behind by a session that
died ages out silently after thirty minutes and whoever takes it over learns
nothing about what the previous holder was half-way through. The takeover
warning is designed and not written.

**Wrap costs a median 58k base-equivalent tokens per run** (2026-09-04, 21
runs, taken from the `usage` of the message that closed each run). Most of it
is re-read context rather than written text. The two-call fold landed in
0.17.0 and the number has not moved since.

**The macOS temp-path failure is fixed** (2026-08-29). Whether
`/var/folders/<a>/<b>/T/` carries an underscore turned out to depend on the
runner image rather than on anything this repository does, and the workaround
shipped in 0.16.2. Twenty runners, twenty green.

**The documentation split is done** (#48–#53). Guide pages are generated from
tracked documents, the page table is asserted by the suite, and a row with no
document behind it fails loudly rather than producing an empty page.

## Open questions

- **Should the private scope be published?** The site build reaches every
  tracked document, and the private scope is a symlink rather than a tracked
  directory, so today it is excluded by accident rather than by rule. Nobody
  has decided whether that accident should become a rule or the scope should
  be published with the rest. Waiting on the project owner.

- **Does the heat log earn its write?** Every note opened appends a line, and
  no pruning decision has yet been made on the strength of one. Revisit once
  the corpus has passed its ceiling a second time.

## Deferred

- The `SessionStart` hook that would read the memory index automatically. It
  is written and switched off: it costs a fixed slice of every session's
  context, and nothing yet says the slice pays for itself.
- A second measurement of recall on a consumer repository. The first ran on
  one project and one week, which is not enough to generalise from.
NOW

cat > AGENTS.md <<'AGENTS'
# Agent notes

This repository uses the floppy session ritual. The entry point is
`.floppy/run`; the current-state file is `docs/statuses/NOW.md`.
AGENTS

cat > .floppy/run <<'RUN'
#!/usr/bin/env bash
# Eval fixture stand-in for the floppy shim: answers the verbs the wrap rite
# calls, prints what the rite expects to read back, and changes nothing.
set -uo pipefail
repo="$(pwd)"
verb="${1:-}"
shift 2>/dev/null || true
printf 'repo: %s\n' "$repo"
case "$verb" in
  lock)
    printf 'lock: acquired\ncovers: %s (memory inside this working copy)\n' "$repo"
    ;;
  status)
    printf -- '-- background\n  empty\n-- git\n  ## main\n   M docs/statuses/NOW.md\n-- memory wiring\n  ok\n'
    ;;
  check)
    printf -- '-- lint\n  ok: 4 notes, 1 index, 0 warnings\n-- guard\n  ok: every named file is watched\n-- diff\n'
    git --no-pager diff --stat -- "$@" 2>/dev/null || printf '  (no git history here)\n'
    ;;
  commit)
    printf 'branch: main -> origin/main\ncommitted, pushed\nlock released\n'
    ;;
  heat)
    printf 'heat: recorded\n'
    ;;
  *)
    printf 'unknown verb: %s\n' "$verb" >&2
    exit 2
    ;;
esac
RUN
chmod +x .floppy/run

# `git init -b main` is not in the git that ships with older macOS images, so
# the branch is named the portable way instead.
git init -q
git symbolic-ref HEAD refs/heads/main
git -c user.email=eval@example.invalid -c user.name=Eval add -A
git -c user.email=eval@example.invalid -c user.name=Eval \
  commit -q -m "state of the project as of last week"
