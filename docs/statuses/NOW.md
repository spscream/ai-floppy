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

**0.18.0** (2026-09-06) closed the three issues the pull-request model turned
from edge cases into the ordinary path: `commit` on a branch with no upstream, the
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
- **No `quota.lock`** — decided when the memory was nine notes old: a ceiling
  invented for a corpus that small bounds nothing, and `lint`'s warning stays
  correct until there is something to measure. **That condition is now met** —
  14 notes — so this freeze has expired on its own terms and is listed below as
  waiting on the owner, not as settled.

## Russian documentation: done, and its search now works

**Five pull requests on 2026-09-06 closed this thread** (#40–#44). The three
documents were already translated and merged (#36, #37); what landed since is
the search over them, the debt they left, and the defects they deferred.

**The one measurement the design asked for was made, and the design's own
prediction was wrong.** Search over the Russian pages returned nothing, and
`search.tokenizer_separator` — named in the spec as the suspect and as a
one-line fix — was never involved. `lunr.trimmer` strips `\W` from both ends of
every token, JavaScript's `\w` is ASCII-only, so a Cyrillic word trimmed to the
empty string: 1855 terms with two containing Cyrillic, and one empty-string term
holding 124 postings. Measured against the deployed index, not a local build.
The spec records the answer under its own "Known unknown"; the memory note is
`site-search-broke-on-the-trimmer-not-the-tokenizer`.

**The first fix shipped inert and the suite stayed green.** The theme serves a
page as one line, so the `//` comments in the injected script swallowed it.
Under that, a second defect: automatic semicolon insertion needs a line
terminator. Both are guarded now, by two checks that collapse the script the way
the page does and that deliberately do not overlap — a fully commented-out
script parses. Note: `served-page-collapses-inline-scripts`.

**Where the search stands, measured on the live site after the last deploy:**
`сессия` and `сессии` both 9 hits, `заметка` and `заметки` both 14, `память` 12,
`памяти` 17. Every English count unchanged (`memory` 71, `wrap` 30, `floppy`
81). What remains unverified is a browser: everything from the served script
text through the built index and the query is measured, the DOM is not.

The suite is 778 assertions across 27 files, green on both CI jobs.

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

## Open, waiting on the owner

**`quota.lock` is now owed a decision.** The freeze below says a ceiling was not
worth inventing while the memory was nine notes old, and that `lint`'s warning
stays correct "until there is something to measure". The memory is **14 notes**
today, so that condition has been met and the freeze has expired on its own
terms. Either measure the corpus and write the file, or restate why not.

**Nothing else is.** The three facts this thread owed the cross-project base
have all landed there: `shell-bracket-range-follows-collation` (#39), and
`one-line-page-eats-a-line-comment` plus `lunr-trimmer-drops-non-latin-tokens`
in this same change, at the owner's instruction — a deliberate pull request,
which is the only way `knowledge/` can be written, since `watched_dirs` keeps
`wrap` inside `docs`.

Both new notes carry a machine-checkable half that needs nothing but node, so
the base now proves 5 of its 16 notes rather than 3. Each was checked for
discrimination rather than assumed: the same commands run against the *fixed*
forms print `ran asi-ok` and `память memory`, the opposite of what they
assert.

## What is not true here

No open issues and no open pull requests — checked against `gh` after #44
merged, not recalled. `main` is in sync with the remote and the working tree is
clean apart from an untracked `.claude/` that predates this work. Both memory
stores are pushed.

**A caution this file earned twice.** It once closed with "nothing is open"
while three issues had been filed minutes earlier, and it spent this session
describing a state four merges out of date. A current-state file carries no sign
of its own age, which is why `start` checks `run status` instead of trusting it.
