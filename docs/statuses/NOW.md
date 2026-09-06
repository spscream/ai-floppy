# Current state

What `start` reads in full, rewritten in place rather than appended to — see
`agent-memory` for how that differs from a dated journal entry. Since 0.18.0
this file is the **project's** half only; one person's thread of work belongs
in `statuses_personal`, in the private scope.

## Where things stand

**0.19.0 is released** (2026-09-06) — tagged `v0.19.0`, GitHub release
published, all three manifests agree, site rebuilt from the push. Two changes
reach consumers, neither needing a migration and neither touching the shim:

- **`status` stopped naming branches that were already deleted.** The
  `-- origin` section reads remote-tracking refs and the fetch had no
  `--prune`, so it learned what appeared and never what went away. Measured
  minutes after two pull requests merged with `--delete-branch`: both branches
  still listed as live. Where a protected default branch makes
  pull-request-and-delete the ordinary path, that is wrong after every merge,
  in the direction that invents work.
- **A note can say *when* it was true.** `metadata.as_of` is the date a note's
  evidence is from, with `note_stale_days` (180) as the threshold and a
  `-- note dates` section in `lint`. The practice comes from `knowledge/LINKS.md`
  §5; the memory note on that survey says why it cannot be read as a to-do list.
  This repository's own nine notes are dated from the evidence in their bodies.

**0.18.0** (same day) closed the three issues the pull-request model turned from
edge cases into the ordinary path: `commit` on a branch with no upstream, the
wrap lock following the memory rather than the clone, and the status splitting
into two files. Details in `CHANGELOG.md`; the decisions they froze are below.

**The macOS temp path is measured** (#29/#30, 2026-09-06) and this one is still
live. `<b>` in `/var/folders/<a>/<b>/T/` is **fixed by the runner image**, not
drawn per machine: twenty runners returned two components, each tied to a kernel
version 20 out of 20 — 25.5.0 with `_` (6 runners), 25.6.0 without (14). The
same commit passes or fails by which image it lands on. 2100 `mktemp` suffixes
carried no non-alphanumeric character.

The 30% is a rollout mix on one day, not a property of macOS, and it goes to zero
when 25.5.0 is retired — **leaving the defect intact and the tests green**. Do
not quote the rate without both kernel versions.

The suite is 689 assertions and green on both CI jobs.

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
- **`metadata.as_of` is optional and `lint` never fails on age** (decided
  2026-09-06, #32). Undated notes are counted in one line, not named; an aged
  note is named and the run still passes. Two reasons, and both have to hold
  for the field to survive: the check lands in corpora that already exist on
  machines whose owners did not ask for it, and one that reddens their memory
  on plugin-update day gets switched off — taking the four earning checks with
  it; and a gate on age teaches people to bump the date without re-checking,
  which destroys the only signal the field carries. A future date more than one
  day out is still a hard failure — that day of slack is the UTC+3 evening
  measured in the note, not politeness.
- **`statuses_personal` is derived, not written live by `init`** — a literal
  value in `.floppy/config` would put one machine's path into a file every
  machine reads. `init` writes it commented, with that reason beside it. The
  same argument rules out setting `machine_key` here: this machine's directory
  is `machines/WIN-GVR0V5UPOD7/`, an ugly name from `hostname`, and correct,
  because a hand-picked one in the shared config would rename the *other*
  machine too.
- **The wrap lock does not cover the private scope** — one lock per rite,
  following the memory every wrap writes, not one per repository the rite can
  touch. And it does not cover two machines at all; nothing does.
- **`store` reports the redundant `.gitignore` line rather than removing it.**
  That file belongs to the consumer and a line in it may be hand-written; one
  line removed by hand is cheaper than a rule for when a script may delete from
  a file it does not own.
- **No `quota.lock`** — the memory is nine notes old. A ceiling invented for a
  corpus this small bounds nothing; `lint` warns about the absence and that
  warning stays correct until there is something to measure.

## Open, waiting on the owner

**Russian documentation: wanted, and the approach is undecided.** The owner
asked for it on 2026-09-06 and explicitly wants the design thought through
before anything is written. Nothing has been chosen; what follows is scope, not
a plan.

Four surfaces, and they are not the same problem:

- `README.md` and `docs/` — read by humans, published to the site;
- `skills/*/SKILL.md` — read by a **model**, and their language changes agent
  behaviour rather than only readability;
- `knowledge/` — a cross-project base whose contract (`verified_on`, `recheck`)
  is enforced by two scripts that assume one file per note;
- `CHANGELOG.md` — read by a consumer deciding whether to take an update.

Three things already settled that constrain any answer, so re-deriving them is
waste: `memory_language` already governs the language of memory notes and is
`en` here; `agent-memory` states plainly that the language of the skills, of the
memory, and of the reply to a human are **three separate choices** and warns a
future session against wiring them together; and the site is generated from
these files by `scripts/site-build.sh`, with `test-site.sh` and `test-docs.sh`
asserting structure — so a second language is a build question, not only a
translation one.

## What is not true here

No open issues and no open pull requests — checked against `gh`, not recalled,
after 0.19.0 was published. `main` is in sync with the remote, the tree is
clean, and both memory stores are pushed.

**A caution the previous version of this file earned.** It once closed with the
same "nothing is open" claim while three issues had been filed minutes earlier.
A current-state file carries no sign of its own age, which is why `start`
checks the live facts instead of trusting it — and why the sentence above says
where the answer came from.
