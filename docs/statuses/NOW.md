# Current state

What `start` reads in full, rewritten in place rather than appended to — see
`agent-memory` for how that differs from a dated journal entry.

## Where things stand

Three releases went out on 2026-09-05, all from one thread of work that began
with issue #1.

- **0.16.0** — every ceiling `memory-lint` enforces now warns at 96% before it
  refuses at 100%: the corpus, one half, one note, one index's pointers, and
  the index size that already had a band. `pointer_line_max` deliberately has
  none. Reported from a consumer corpus whose half sat at 96.9% while the run
  printed `clean`.
- **0.16.1** — `link` encoded the checkout path without folding `_`, so a
  repository with an underscore in its name got a project directory the
  harness never opens. Measured from the harness's own transcripts, which
  record the `cwd` a session ran in.
- **0.16.2** — `link` compared a resolved path against an unresolved one, so
  the whole external-store layout read as unwired while working. Found by
  standing that layout up here, not by reading the file.

This repository now uses floppy itself. `.agent-memory` is a symlink into the
store `ai_floppy_memory`; the private scope under it points into a second store
entirely. Both directions were verified by a write probe, not by inspection.

## What is frozen

- **`watched_dirs` / `watched_files` stay narrow** — `docs` plus `AGENTS.md`,
  `.floppy/run`, `.floppy/config`. In this repository the session procedure is
  the product: `skills/`, `scripts/`, `shim/` and `tests/` belong in reviewed
  commits, never in a closing rite. Widening this needs a deliberate decision.
- **No `quota.lock`** — the memory is one note old. A ceiling invented for an
  empty corpus bounds nothing; `lint` warns about the absence and that warning
  is correct until there is something to measure.
- **`project_key`, not `memory_project_key`** — one key names this project in
  both stores. `init` writes the narrow one when given `--memory-key`.

## Open, waiting on the owner

- Two small unfixed findings, no issues filed: `init` writes
  `memory_project_key` rather than `project_key`, and in the store layout it
  appends a second `.gitignore` line for the private scope that does nothing,
  the parent already being ignored.
- Whether the session's general lesson — a check that restates the rule it is
  checking agrees with any rule, including a wrong one — belongs in
  `knowledge/`. That directory is published to the site, so it is a
  publication decision.
- `.cursor-plugin/plugin.json` is at 0.14.0 while the Claude plugin is at
  0.16.2. Three releases have not moved it; nothing in the tests looks at it.

## What is not true here

Nothing is red. The suite is green on both CI jobs, including the macOS
bash 3.2 one, and the tree is in sync with the remote.
