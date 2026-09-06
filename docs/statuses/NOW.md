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

## Russian documentation: done and merged

**Both pull requests are on `main`** (2026-09-06): #36 `3da8fdc` carried the
machinery and the first document, #37 `4427b70` the remaining two. All three
documents the design scopes are translated, and
`python3 scripts/translation-check.py` reports `clean` — until #37 it always
listed something under `-- untranslated`, so its silence now means something.
The suite is 741 assertions, green on both platforms.

The design is `docs/specs/2026-09-06-russian-documentation-design.md`. Four
decisions the owner took, which any later change has to argue against rather
than around:

1. `README.md` and `docs/` get Russian; `skills/*/SKILL.md` deliberately do
   not, because those are read by a model and their wording is behaviour.
2. Both languages side by side, English the source.
3. An outdated translation must be detectable.
4. The check **reports and never fails a run** — the same reasoning frozen for
   `metadata.as_of`.

**How it works, in one paragraph.** A translation is a sibling with a language
suffix, carrying an HTML comment on line 1 that records the git blob sha of the
English source it was made from. The blob sha rather than a plain hash, so the
record is a pointer into history and `git cat-file blob` answers "what changed
since this was translated". `scripts/translation-check.py` never exits
non-zero; `status --flow` shows drift only in a repository that has
translations.

**Deviation from the design, taken deliberately in #37:** Russian pages link to
Russian pages. The design says links keep their targets and only link text is
translated — a rule written when no Russian document existed, which now would
send a Russian reader to the English page. Links out to `knowledge/`,
`CHANGELOG.md` and `LICENSE` stay English, since nothing translates those.

## Open, waiting on the owner

**Cyrillic search on the site is still unmeasured.** The design assigned this
measurement to the first pull request and it was not made: ruby and jekyll are
not available in the session that produced the work. `site/_config.yml` sets
`tokenizer_separator: /[\s/]+/`, chosen for Latin text and paths. The deploy
from these merges is the first thing that can answer it. If search over the
three Russian pages is broken, it is a one-line change in that file.

**"What is a translation" is written out five times.** In
`scripts/translation-check.py` (authoritative), in the gate in
`scripts/workstatus.sh`, in `count_translations()` and the corpus loop in
`tests/test-translations.sh`, and in a `sed` deriving the sibling path. Four
consecutive fix rounds on #36 turned on those copies disagreeing, and the fifth
copy was found while fixing the fourth. They agree today, each checked against
a fixture rather than against each other. **The architectural answer is to make
the checker the single authority and have the shell ask it** — not attempted,
because #36 was open and red at the time and a minimal fix was worth more than
a restructure. This is a debt, not a closed question.

**A sixth expression, of a different rule:** what a *marker* is. The checker's
regex tolerates any whitespace after `floppy:translation`; the site build's
strip rule requires exactly one space. A marker written without the space is
valid to the checker and is not stripped from the page. `tests/test-site.sh`
catches it.

**Deferred, each with its reason recorded in the pull requests:** a dotfile
translation is matched by the checker's regex and invisible to the shell globs;
the `on=` field is validated for digit shape only, so a calendar-impossible
date that sorts before tomorrow (`2026-02-30`) passes; `bash tests/test-site.sh
--selftest` with no second argument aborts with a raw unbound-variable error.

**A `knowledge/` note is owed and cannot be written by `wrap`.** The
locale-dependent `[a-z]` finding is a fact about shells and macOS, true whether
or not anyone uses floppy — exactly what `knowledge/` is for. `wrap` may not
commit there: `watched_dirs` is `docs` only, deliberately. It needs its own
pull request.

## What is not true here

No open issues and no open pull requests — checked against `gh`, not recalled,
after #36 and #37 merged. Both memory stores are pushed.

`main` is in sync with the remote and the working tree is on it, clean apart
from an untracked `.claude/` that predates this work. Nothing is unpushed.

An earlier version of this file claimed 14 commits existed only on this machine.
That was true when written and stopped being true at the merge — which is the
whole reason `start` checks `run status` instead of trusting this file.

**A caution the previous version of this file earned.** It once closed with the
same "nothing is open" claim while three issues had been filed minutes earlier.
A current-state file carries no sign of its own age, which is why `start`
checks the live facts instead of trusting it — and why the sentence above says
where the answer came from.
