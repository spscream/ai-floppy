#!/usr/bin/env bash
# Fixture for a-fact-becomes-one-note-with-an-index-line.
#
# A memory with one half, so where the note belongs is not a judgement call and
# the case measures shape rather than routing. The half's index is seeded with
# exactly three pointer lines — that number is what the case's index grader
# counts against, so changing the seeded notes means changing `count:4` in
# case.yaml with it.
#
# Portable to macOS /bin/bash 3.2.
set -uo pipefail

mkdir -p .agent-memory/product docs/statuses .floppy

cat > .floppy/config <<'CONFIG'
memory_dir=.agent-memory
memory_language=en
project_key=demo
statuses_now=docs/statuses/NOW.md
watched_dirs=docs/statuses,.agent-memory
watched_files=AGENTS.md,.floppy/run,.floppy/config
CONFIG

cat > .agent-memory/quota.lock <<'QUOTA'
chars_max=75000
note_chars_max=6000
pointers_max=25
pointer_line_max=160
QUOTA

cat > .agent-memory/MEMORY.md <<'ROUTER'
# Memory index

Router for this repository's durable memory — loaded at the start of every
session, so it stays small on purpose. It holds only what is read in every
task, plus one link per half.

## The halves

- [Product](product/INDEX.md) — the scripts, the shim, the test suite and the
  generated site: what a change to the tool itself touches.
ROUTER

cat > .agent-memory/product/INDEX.md <<'INDEX'
# Product

What a change to the tool itself touches: the scripts, the shim, the test
suite, the generated site.

- [The suite's runner passes its own interpreter down](the-runner-passes-its-interpreter-down.md) — a bare `bash` in a test file resolves through PATH
- [A table row with no document is invisible](a-table-row-with-no-document-is-invisible.md) — the site build skipped it silently until a guard was added
- [The guard matches watched paths by prefix](the-guard-matches-watched-paths-by-prefix.md) — a nested path needs no code change
INDEX

cat > .agent-memory/product/the-runner-passes-its-interpreter-down.md <<'NOTE'
---
name: the-runner-passes-its-interpreter-down
description: tests/run.sh exports the interpreter it was started with to every test file
metadata:
  type: project
  evidence: read
  as_of: 2026-09-05
---

`tests/run.sh` passes `$BASH` — the interpreter it was itself started with — to
every test file it runs. Without that, a test file's own shebang or a bare
`bash` inside it picks whatever PATH resolves first.
NOTE

cat > .agent-memory/product/a-table-row-with-no-document-is-invisible.md <<'NOTE'
---
name: a-table-row-with-no-document-is-invisible
description: the site build skipped a page table row whose document was gone, and said nothing
metadata:
  type: project
  evidence: measured
  as_of: 2026-09-08
---

Measured by deleting a guide document and keeping its row in the page table:
the build produced a site with one page missing and exited zero. The guard that
now fails on it was written from that run.
NOTE

cat > .agent-memory/product/the-guard-matches-watched-paths-by-prefix.md <<'NOTE'
---
name: the-guard-matches-watched-paths-by-prefix
description: the wrap guard matches watched_dirs by prefix, so a nested path is already covered
metadata:
  type: project
  evidence: read
  as_of: 2026-09-08
---

`watched_dirs` entries are matched by prefix, so a document one level deeper
than the configured directory is already inside the guard's reach and adding it
separately changes nothing.
NOTE

cat > docs/statuses/NOW.md <<'NOW'
# Current state

## Where things stand

**The suite runs on both platforms.** Nothing is red and nothing is deferred.
NOW

cat > AGENTS.md <<'AGENTS'
# Agent notes

This repository uses the floppy session ritual, and its durable memory lives
in `.agent-memory`. The memory has one half:

| the task is about | half | words that route to it |
|---|---|---|
| `scripts/`, `shim/`, the test suite, the generated site | `product/` | verb, shim, guard, test, suite, bash, site, lint |
AGENTS

cat > .floppy/run <<'RUN'
#!/usr/bin/env bash
# Eval fixture stand-in for the floppy shim.
set -uo pipefail
repo="$(pwd)"
verb="${1:-}"
shift 2>/dev/null || true
printf 'repo: %s\n' "$repo"
case "$verb" in
  status)
    printf -- '-- background\n  empty\n-- git\n  ## main\n-- memory wiring\n  .agent-memory inside this working copy\n'
    ;;
  lock)
    printf 'lock: acquired\n'
    ;;
  check)
    printf -- '-- lint\n  ok: 3 notes, 2 indexes, 0 warnings\n-- guard\n  ok\n'
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

git init -q
git symbolic-ref HEAD refs/heads/main
git -c user.email=eval@example.invalid -c user.name=Eval add -A
git -c user.email=eval@example.invalid -c user.name=Eval \
  commit -q -m "the memory as it stands"
