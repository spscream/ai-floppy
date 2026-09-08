# Current state

What `start` reads in full, rewritten in place rather than appended to — see
`agent-memory` for how that differs from a dated journal entry. Since 0.18.0
this file is the **project's** half only; one person's thread of work belongs
in `statuses_personal`, in the private scope.

## Where things stand

**The documentation is split by audience** (#48, merged 2026-09-08). Installation,
the config reference and the skills prose left `README.md` for `docs/guide/`, in
both languages; the front page is a landing with the two install commands still
on it. Nothing was rewritten — review verified all 441 moved lines byte-for-byte,
and the Russian half was the same three cuts, its outline having matched the
English 22 headings to 22.

**The guards changed more than the documents did.** `tests/test-docs.sh` used to
ask "is this somewhere in README.md?"; it now asks whether each answer is in the
file that should hold it, which is stricter — a key documented in the wrong place
used to pass. Four one-level-deep assumptions broke on the new directory and were
fixed: the site glob, the translation checker's scan, `workstatus`'s pre-gate,
and the site's link rewriter. The fourth shipped two live 404s past six per-task
reviews, because the guard written for that class was blind to its own form; a
four-lens whole-branch review caught it, two lenses independently. Verified on the
deployed site afterwards, not only locally: ten pages 200, zero URLs containing
`..`, and the six new pages carry 49 fragments in the search index.

**0.19.0 is released** (2026-09-06) — tagged, published, all three manifests
agree. It brought `--prune` to `status`'s fetch, so a branch deleted on merge
stops being listed as live, and `metadata.as_of` with `note_stale_days`. 0.18.0
closed the three issues a protected default branch turned from edge cases into
the ordinary path. Details in `CHANGELOG.md`; what they froze is below.

**The macOS temp path is measured** (#29/#30, 2026-09-06) and this one is still
live. `<b>` in `/var/folders/<a>/<b>/T/` is **fixed by the runner image**, not
drawn per machine: twenty runners returned two components, each tied to a kernel
version 20 out of 20 — 25.5.0 with `_` (6 runners), 25.6.0 without (14). The
same commit passes or fails by which image it lands on. 2100 `mktemp` suffixes
carried no non-alphanumeric character.

The 30% is a rollout mix on one day, not a property of macOS, and it goes to zero
when 25.5.0 is retired — **leaving the defect intact and the tests green**. Do
not quote the rate without both kernel versions.

## What is frozen

- **`watched_dirs` is `docs/statuses`, and documentation is product**
  (narrowed 2026-09-08). The closing rite may write the status file and
  nothing else; `docs/guide/`, `docs/lessons.md` and `docs/memory-model.md`
  go through review like `skills/`, `scripts/`, `shim/` and `tests/`. The
  earlier entry kept `docs` whole, which was never a decision that
  documentation belonged to the rite — while `docs/` held only working
  documents the question did not arise. It does now, and this is the answer.
  `watched_files` is unchanged: `AGENTS.md`, `.floppy/run`, `.floppy/config`.
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
- **`quota.lock` holds measured numbers, and raising one is a defended edit**
  (written 2026-09-06, replacing the earlier decision to have no such file —
  that one set its own expiry at "something to measure", and a dozen notes met
  it). `chars_max=40000` is the measured 32159 plus a tenth, rounded the way
  `init` rounds. `note_chars_max=5000`, **not** the convention's 10000: the
  longest note here is 3223 and the mean 2297, so 10000 would never fire and
  the rule it enforces — a note over the cap is two notes written as one —
  would be decorative. `pointers_max=25` is where a flat index of ~4000
  characters, loaded by every session, makes splitting into halves cheaper than
  reading past it. Raise a number only in the same commit as the notes that
  need the room.

## The Russian documentation thread is closed

Five pull requests on 2026-09-06 (#40–#44) finished it: the three documents, the
search over them, and the two defects they deferred. The measurements that thread
produced live in memory rather than here — `site-search-broke-on-the-trimmer-not-the-tokenizer`,
`served-page-collapses-inline-scripts`, `lunr-languages-is-mpl-1-1`. Search on the
live site answers Russian queries with stemming; every English count was unchanged.
What stays unverified is a browser: everything from the served script through the
built index and the query is measured, the DOM is not.

## What this thread froze

- **The injected script in `site/_includes/head_custom.html` uses block
  comments and explicit semicolons.** Not style: the page it becomes has no
  newlines, and either omission makes the whole script dead or invalid. Two
  asserts enforce it and the file says why at the top.
- **The vendored search plugins are MPL-1.1, and their notice lives with the
  code** (decided 2026-09-06 by the owner). `lunr-languages@1.14.0` is MPL-1.1,
  not MIT — checked in `package.json`, in its `LICENSE` and in the file
  headers. The three files are vendored verbatim with a `NOTICE.md` and a copy
  of the licence beside them; the site footer carries nothing, because MPL asks
  for headers and available source, not a page-visible notice, and a footer
  line would be a second place to keep in step. `site/` only — the plugin is
  MIT and untouched.
- **`translation-check.py --list` is the only expression of what a translation
  is.** The gate in `workstatus.sh` keeps a deliberately *loose* pre-gate whose
  only job is deciding whether to start python — `?`, never a bracket range, so
  the collation trap cannot return through it — and the section prints only
  when the checker actually lists something.
- **The sibling rule stays hand-written in `tests/test-translations.sh`.** It is
  a different rule, and that loop is the only thing in CI that can redden a
  hand-written marker, since the checker reports and never fails. Deriving its
  expectation from the checker would let a checker bug agree with itself.

## Open, and none of it waits on a person

Nothing is blocked on a decision. What follows is work, in the order it earns:

- **PR B, the other half of the split.** Three incidents move out of the guide
  pages into `docs/lessons.md` — the plugin-cache post-mortem, the 0.5.0 rename
  history, the 0.4.2 two-repositories incident — two of them into lessons that
  already exist. Plus the "Behind it" navigation parent over the memory model and
  the lessons. Described in `docs/specs/2026-09-07-documentation-split-design.md`.
- **A page-table row whose document is gone is invisible.** Measured: delete
  `docs/lessons.md`, keep its row and inbound links, and the suite reports 79
  passed 0 failed while the home page links to a page never built. The loop is
  glob-driven, so it fails in one direction only. Note:
  `a-table-row-with-no-document-is-invisible`.
- **The macOS job runs bash 5 for every script a test invokes.** `run.sh` hands
  `$BASH` to each test file; the test files then call the script under test with
  a bare `bash`. Note: `macos-job-runs-bash5-for-scripts-tests-invoke`.
- **`wrap-guard.sh:205` advises `bash .floppy/run store` unconditionally**, in a
  message that also fires where `public_repo` is unset and `store` therefore
  cannot run. A consumer repository followed that half on 2026-09-08, reached a
  dead end, and reported the tool as inapplicable; the correct fix there was the
  other half of the same sentence. The message should branch on the config.
- **`common/` is documented and not wired** — note
  `common-scope-is-documented-but-not-wired`. Either wire it beside `private`,
  or correct the status line in `docs/memory-model.md`, which currently calls
  the subject level implemented when half of it is.

Two smaller things, recorded so they are not rediscovered: `translation-check.py`
runs in no workflow at all, so a stale translation is noticed by a person and
never by CI; and the Russian hub loop in `tests/test-site.sh` is still a
hand-written list, so page seven will have the hole page four had.

**Two deviations from the spec, recorded rather than fixed.** `quota.lock`'s
justification was to be condensed on its way into the config reference and
shipped byte-identical, so 22% of that page is argument — the load-bearing
reason survives and is guarded, and the spec's named fallback (move it whole to
`lessons.md`) was never taken. And the spec asked for the site's positive control
to plant a document under the new directory; what shipped instead is a separate
reach guard, which was measured to be stronger — an unregistered page under
`docs/guide/` does redden the suite.

## What is not true here

No open issues and no open pull requests — checked against `gh` after #48
merged, not recalled. `main` is in sync with the remote and the working tree is
clean apart from an untracked `.claude/` that predates this work. Both memory
stores are pushed. `quota.lock`'s `chars_max` was raised from 40000 to 55000 in
the same commit as the five notes that needed the room, by the rule `init` uses
to seed it.

**A caution this file earned twice.** It once closed with "nothing is open"
while three issues had been filed minutes earlier, and it spent this session
describing a state four merges out of date. A current-state file carries no sign
of its own age, which is why `start` checks `run status` instead of trusting it.
