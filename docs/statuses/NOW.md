# Current state

What `start` reads in full, rewritten in place rather than appended to — see
`agent-memory` for how that differs from a dated journal entry.

## Where things stand

**0.17.0 is still the released version.** 2026-09-06 shipped no release: two
pull requests landed on top of it, both about what the repository claims rather
than what it does.

- **The macOS temp-path fact is published** (#20):
  `knowledge/notes/shell/macos-tmpdir-can-contain-underscore.md`. On GitHub's
  macOS runners `mktemp -d` returns `/var/folders/<a>/<b>/T/…`, and `<b>` is not
  alphanumeric — the measured one carries `_`. The base is now 13 notes and the
  weekly recheck executes 4 of them across the matrix: macOS 4 passed / 1
  skipped / 8 not machine-checkable, Linux 2 / 3 / 8. See
  [[knowledge-schedule-covers-the-executable-minority]], and
  [[green-suite-hides-which-rechecks-ran]] for why the ordinary suite cannot
  show which four.
- **Two documents stopped overstating their evidence.** `docs/lessons.md` and
  the comment in `tests/test-memory-link.sh` both stated "the random component
  carries `_` some of the time" as measured. Only a *failing* run prints a temp
  path, so the six passing runs in that window were never recorded; the split
  between what was measured and what was inferred is now written down in all
  three places.
- **A stray `.pyc` is out and `__pycache__` is ignored** (#21). It arrived
  through `git add -A` during this session. The rule that refuses that command
  already existed in the owner's global `bash-guard.py` and had never been
  switched on; it was enabled and verified the same day, so staging by named
  path is now enforced from outside this repository.

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
- **No `quota.lock`** — the memory is five notes old. A ceiling invented for a
  corpus this small bounds nothing; `lint` warns about the absence and that
  warning stays correct until there is something to measure.

## Open, waiting on the owner

- **Whether the macOS job should print `$TMPDIR` on every run.** One line in
  `tests.yml`. Today the path reaches the log only when an assertion fails, so
  "the component carries `_` only sometimes" cannot be measured — it is the
  explanation that fits two failures, not an observation. A month of runs with
  that line would settle it. Nothing depends on the answer; the actionable half
  of the note (never assume a character class for a temp path) holds either way.
- **Three issues opened 2026-09-05 and untouched**, all about the closing rite
  itself: #17 (wrap's `commit` cannot sync on a fresh branch — which the
  pull-request model now makes *every* wrap), #18 (the wrap lock is per-clone
  and does not travel between machines), #19 (this file conflates personal
  working state with project state). #17 is the one that bites during a wrap.

## What is not true here

The suite is green on both CI jobs including the macOS bash 3.2 one, `main` is
in sync with the remote, and there are no open pull requests.

**Correction to the previous version of this file.** It ended with "there are no
open issues and no open pull requests — the first time today that all three have
been true at once." That was already false as it was written: #17, #18 and #19
were opened between eight and nineteen minutes earlier. A current-state file
carries no sign of its own age, which is exactly why `start` checks the live
facts instead of trusting it.
