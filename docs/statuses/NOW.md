# Current state

What `start` reads in full, rewritten in place rather than appended to — see
`agent-memory` for how that differs from a dated journal entry.

## Where things stand

**0.17.0 is out** (2026-09-06), and unlike the five versions before it, it is a
release rather than a commit: tag, GitHub release, and all three manifests
moved together. The gap it closes is described in its own changelog entry —
between 0.14.0 and 0.16.2 only `.claude-plugin/plugin.json` was ever bumped, so
`plugin update` had nothing to copy and the two `link` fixes reached nobody
until 0.16.2 was released by hand on 2026-09-05.

Two guards now make that failure loud instead of silent: `tests/test-release.sh`
pins the three manifest versions to each other, and `test-site.sh` already
required the changelog to cover the shipped version. Both fired correctly while
cutting 0.17.0.

Also in this release:

- **`main` is protected.** Changes land through pull requests, checked on Linux
  and macOS before merge, with no bypass for anyone. See
  [[agents-share-one-git-identity]] before touching the ruleset.
- **The knowledge base is re-checked weekly** on both platforms, and a failure
  opens an issue. What it does and does not cover is measured in
  [[knowledge-schedule-covers-three-of-twelve-notes]] — three of twelve.
- **`init` writes `project_key`**, the umbrella key, and no longer writes an
  ignore rule the store layout already covers.
- **The macOS job stopped being red at random**, which was never flakiness. The
  test recomputed the path rule from a stale copy; the lesson is in
  `docs/lessons.md`.

## What is frozen

- **`watched_dirs` / `watched_files` stay narrow** — `docs` plus `AGENTS.md`,
  `.floppy/run`, `.floppy/config`. In this repository the session procedure is
  the product: `skills/`, `scripts/`, `shim/` and `tests/` belong in reviewed
  commits, never in a closing rite. Widening this needs a deliberate decision.
- **Branch protection is symmetric, and must stay so** — no bypass actors, not
  even for the owner. The reason is not strictness; both sessions writing here
  are the same git principal, so a bypass exempts both.
- **`strict` is off for required status checks** — a branch need not be up to
  date with `main` before merging. On a repository this quiet that would cost a
  rebase per pull request and buy very little.
- **`store` reports the redundant `.gitignore` line rather than removing it.**
  That file belongs to the consumer and a line in it may be hand-written; one
  line removed by hand is cheaper than a rule for when a script may delete from
  a file it does not own.
- **No `quota.lock`** — the memory is three notes old. A ceiling invented for a
  corpus this small bounds nothing; `lint` warns about the absence and that
  warning stays correct until there is something to measure.

## Open, waiting on the owner

- Whether the general fact behind the macOS incident — **GitHub's macOS runners
  use `/var/folders/<random>/T/` as `TMPDIR`, and that random component carries
  `_` some of the time** — belongs in `knowledge/`. It is true outside this
  repository and it is genuinely checkable, which is more than the lesson filed
  in `docs/lessons.md` could claim. `knowledge/` publishes to the site, so this
  is a publication decision and not one to take without asking.

## What is not true here

Nothing is red. The suite is green on both CI jobs including the macOS bash 3.2
one, `main` is in sync with the remote, and there are no open issues and no open
pull requests — the first time today that all three have been true at once.
