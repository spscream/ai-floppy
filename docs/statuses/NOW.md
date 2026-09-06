# Current state

What `start` reads in full, rewritten in place rather than appended to — see
`agent-memory` for how that differs from a dated journal entry. Since 0.18.0
this file is the **project's** half only; one person's thread of work belongs
in `statuses_personal`, in the private scope.

## Where things stand

**0.18.0 is released** — tagged `v0.18.0`, GitHub release published, all three
manifests agree, and the site rebuilt from the push. It closes the three issues
opened on 2026-09-05, all of which were found while closing a single session on
the day the pull-request model went in. That model is what turned each of them
from an edge case into the ordinary path.

- **`commit` survives a fresh branch** (#17 → #23). The tail ended with
  `pull --rebase` then `push`; on a branch with no upstream the pull has
  nothing to rebase against and took the whole tail with it — which, with
  `main` protected, was every close. With no upstream the pull is skipped and
  the push is `-u origin HEAD`. A push refused by a branch rule is now told
  apart from a network failure and prints the branch-and-pull-request recipe
  instead of "retry", which could not work.
- **The wrap lock follows the memory, not the clone** (#18 → #24). Measured:
  a linked worktree's `--git-dir` really is its own, but in the store layout
  "each worktree carries its own memory copy" is false — two worktrees took two
  locks over the same notes. The lock now lives in the store's git directory,
  named for the project key, and `acquire`/`status` print what it covers.
- **The status is two files** (#19 → #26), option C of the three in the issue.
  `statuses_now` keeps project state; `statuses_personal` takes one person's
  thread of work into the private scope under `machines/<name>/`, where no
  other machine writes. The path is derived, never written live by `init`.

The suite is 629 assertions and green on both CI jobs. This repository has no
personal status file yet: nothing was left mid-way to hand over.

## What is frozen

- **`watched_dirs` / `watched_files` stay narrow** — `docs` plus `AGENTS.md`,
  `.floppy/run`, `.floppy/config`. In this repository the session procedure is
  the product: `skills/`, `scripts/`, `shim/` and `tests/` belong in reviewed
  commits, never in a closing rite. Widening this needs a deliberate decision.
- **Branch protection is symmetric, and must stay so** — no bypass actors, not
  even for the owner. Both sessions writing here are the same git principal, so
  a bypass exempts both.
- **`strict` is off for required status checks** — a branch need not be up to
  date with `main` before merging. On a repository this quiet that would cost a
  rebase per pull request and buy very little.
- **`commit` does not create a branch of its own** (decided 2026-09-06, #17).
  On a protected branch it commits, attempts the push, and prints the recipe.
  These scripts decline to guess, and moving someone off the branch they were
  on is a guess. Revisit only with a real wrap that the message failed to help.
- **`statuses_personal` is derived, not written live by `init`** — a literal
  value in `.floppy/config` would put one machine's path into a file every
  machine reads. `init` writes it commented, with that reason beside it.
- **The wrap lock does not cover the private scope** — one lock per rite,
  following the memory every wrap writes, not one per repository the rite can
  touch. And it does not cover two machines at all; nothing does.
- **`store` reports the redundant `.gitignore` line rather than removing it.**
  That file belongs to the consumer and a line in it may be hand-written; one
  line removed by hand is cheaper than a rule for when a script may delete from
  a file it does not own.
- **No `quota.lock`** — the memory is six notes old. A ceiling invented for a
  corpus this small bounds nothing; `lint` warns about the absence and that
  warning stays correct until there is something to measure.

## Open, waiting on the owner

- **Whether the macOS job should print `$TMPDIR` on every run.** One line in
  `tests.yml`. Today the path reaches the log only when an assertion fails, so
  "the component carries `_` only sometimes" cannot be measured — it is the
  explanation that fits two failures, not an observation. A month of runs with
  that line would settle it. Nothing depends on the answer; the actionable half
  of the note (never assume a character class for a temp path) holds either way.

## What is not true here

No open issues and no open pull requests — checked against `gh`, not recalled,
after the release merged. `main` is in sync with the remote, the tree is clean,
and both memory stores are pushed.

**A caution the previous version of this file earned.** It once closed with the
same "nothing is open" claim while three issues had been filed minutes earlier.
A current-state file carries no sign of its own age, which is why `start`
checks the live facts instead of trusting it — and why the sentence above says
where the answer came from.
