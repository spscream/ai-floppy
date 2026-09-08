# Current state

What `start` reads in full, rewritten in place rather than appended to — see
`agent-memory` for how that differs from a dated journal entry. Since 0.18.0
this file is the **project's** half only; one person's thread of work belongs
in `statuses_personal`, in the private scope.

## Where things stand

**The cross-project scope is wired** (#55, merged 2026-09-08). `common/` — the
subject-level sibling of `projects/<key>`, for facts about no single project —
was documented from 0.7.0 and created, linked or read by no verb until now;
fifteen notes sat in one private store where no session could reach them.
`store` and `workplace` wire it as `<memory_dir>/common/shared` and
`<memory_dir>/common/private`, either verb alone leaving a usable half. Three
gates had to be taught it as well, because each routes by path under its own
pathspec — the details, and how the tests were falsified, are in
`wiring-a-scope-is-more-than-its-symlink`. The 15 notes are now linted: 8 were
missing `metadata.evidence` and one had a `name` that did not match its file;
all nine are fixed in the private store.

**The documentation split is finished** (#48, #50, merged 2026-09-08). The
guide, the config reference and the skills prose left `README.md` for
`docs/guide/` in both languages; the front page is a landing with the two
install commands. The archaeology then left the guide for `docs/lessons.md`,
and the memory model and the lessons got a "Behind it" navigation parent.
Nothing was rewritten in either half; review verified the moved lines
byte-for-byte.

**Four guard defects that the split exposed are all closed** (#49, #51, #52,
#53, merged 2026-09-08). Four one-level-deep assumptions broke on the new
directory; the site guard now also asserts that every page-table row has a
document; the interpreter is pinned once (see the freeze below); and
`wrap-guard.sh` no longer advises a command that would refuse. What each one
cost is in `one-directory-level-broke-four-guards`,
`a-table-row-with-no-document-is-invisible` and
`macos-runner-carries-one-bash-and-it-is-3-2`.

**0.19.0 is released** (2026-09-06) — tagged, published, all three manifests
agree. It brought `--prune` to `status`'s fetch and `metadata.as_of` with
`note_stale_days`. Details in `CHANGELOG.md`; what it froze is below.

**The macOS temp path is measured** (#29/#30, 2026-09-06) and this one is still
live. `<b>` in `/var/folders/<a>/<b>/T/` is **fixed by the runner image**, not
drawn per machine: twenty runners returned two components, each tied to a kernel
version 20 out of 20 — 25.5.0 with `_` (6 runners), 25.6.0 without (14). The
same commit passes or fails by which image it lands on, and 2100 `mktemp`
suffixes carried no non-alphanumeric character. The 30% is a rollout mix on one
day, not a property of macOS, and it goes to zero when 25.5.0 is retired —
**leaving the defect intact and the tests green**. Do not quote the rate
without both kernel versions.

## What is frozen

- **`watched_dirs` is `docs/statuses`, and documentation is product**
  (narrowed 2026-09-08). The closing rite may write the status file and
  nothing else; `docs/guide/`, `docs/lessons.md` and `docs/memory-model.md`
  go through review like `skills/`, `scripts/`, `shim/` and `tests/`. The
  earlier entry kept `docs` whole, which was never a decision that
  documentation belonged to the rite — while `docs/` held only working
  documents the question did not arise. It does now, and this is the answer.
  `watched_files` is unchanged: `AGENTS.md`, `.floppy/run`, `.floppy/config`.
- **The suite pins its interpreter in PATH, not at every call site** (shipped
  2026-09-08, #52). `tests/run.sh` puts a directory holding one `bash` — a
  symlink to the interpreter it was itself started with — at the front of PATH.
  That covers the ~180 bare-`bash` call sites across 19 test files and anything
  added later, in one place instead of 180. Do not "fix" those call sites one
  by one; the two dispatcher execs are the exception and already carry
  `"${BASH:-bash}"`, because they run outside the suite too.
- **`common/` gets no view under `agents_memory_dir`, unlike every other
  scope** (decided 2026-09-08, #55). The symmetric shape — one `<views>/common/`
  holding `shared` and `private` — assumes one store per namespace, and the
  public namespace has one store per project. The suite's own two-store fixture
  failed on it. The links go straight into each clone; see
  `one-common-view-collides-across-stores` before "fixing" the asymmetry.
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
  2026-09-06, #32). Undated notes are counted, not named; an aged note is named
  and the run still passes. Two reasons, both load-bearing: a check that reddens
  an existing corpus on plugin-update day gets switched off, taking the four
  earning checks with it; and a gate on age teaches people to bump the date
  without re-checking, destroying the only signal the field carries. A future
  date more than one day out is still a hard failure — that day of slack is the
  UTC+3 evening measured in the note, not politeness.
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
  it). `chars_max` is the measured corpus plus a tenth, rounded the way `init`
  rounds — 55000 since 2026-09-08. `note_chars_max=5000`, **not** the
  convention's 10000: the
  longest note here is 3223 and the mean 2297, so 10000 would never fire and
  the rule it enforces — a note over the cap is two notes written as one —
  would be decorative. `pointers_max=25` is where a flat index of ~4000
  characters, loaded by every session, makes splitting into halves cheaper than
  reading past it. Raise a number only in the same commit as the notes that
  need the room.

## The Russian documentation thread is closed

Five pull requests on 2026-09-06 (#40–#44) finished it. The measurements live in
memory rather than here — `site-search-broke-on-the-trimmer-not-the-tokenizer`,
`served-page-collapses-inline-scripts`, `lunr-languages-is-mpl-1-1`. What stays
unverified is a browser: everything from the served script through the built
index and the query is measured, the DOM is not.

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

## Open

One item waits on a decision; the rest is work, in the order it earns:

- **0.20.0 is due and has not been cut.** Six merges have landed since 0.19.0
  (#48–#55) with no changelog entry, which is this repository's habit — entries
  are written at release. #55 is the one that makes a release owed rather than
  optional: it adds a capability and a second `.gitignore` rule that `init`
  now writes. Cutting it means the three manifests together plus the entry, and
  that entry answers **"Refresh `.floppy/run`?" with no** — the shim is
  untouched. **Waits on the owner**, who decides when a version ships.

Two smaller things, recorded so they are not rediscovered: `translation-check.py`
runs in no workflow at all, so a stale translation is noticed by a person and
never by CI; and the Russian hub loop in `tests/test-site.sh` is still a
hand-written list, so page seven will have the hole page four had.

**Two deviations from #48's spec, recorded rather than fixed.** `quota.lock`'s
justification shipped byte-identical instead of condensed, so 22% of the config
page is argument — the load-bearing reason survives and is guarded. And the
site's positive control is a separate reach guard rather than a planted
document, which was measured to be the stronger of the two.

## What is not true here

No open issues and no open pull requests — checked against `gh` after #55
merged, not recalled. `main` is at `0ef2cd3`, local is in sync, and the branch
that pull request used is deleted on both sides. The working tree is clean
apart from an untracked `.claude/` that predates this work. Both memory stores
are committed and pushed, including the nine note fixes in the private one.

`quota.lock` is unchanged: one note was retired as false and two written, so the
corpus stands at 20 notes and 20 pointers against a ceiling of 25, inside the
band. The 15 notes in `common/` carry no `metadata.as_of` and `lint` says so as
a warning every run — that is the field behaving as designed (counted, never
named, never a failure), not something to fix by dating them from guesswork.

**A caution this file earned twice.** It once closed with "nothing is open"
while three issues had been filed minutes earlier, and it spent this session
describing a state four merges out of date. A current-state file carries no sign
of its own age, which is why `start` checks `run status` instead of trusting it.
