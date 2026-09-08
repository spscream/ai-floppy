# Current state

What `start` reads in full, rewritten in place rather than appended to — see
`agent-memory` for how that differs from a dated journal entry. Since 0.18.0
this file is the **project's** half only; one person's thread of work belongs
in `statuses_personal`, in the private scope.

## Where things stand

**0.20.0 is released** (2026-09-08) — tagged, published, three manifests agree.
It carries ten merges that had piled up behind 0.19.0. Its headline is one
consumers have not seen since 0.14.0: **"Refresh `.floppy/run`" is yes**, and
the entry says why it is a *small* yes — #52 changed the shim's last line to
`exec "${BASH:-bash}"`, so an un-refreshed copy still finds the plugin and
works, and the refresh matters only where somebody names an interpreter
(`/bin/bash .floppy/run`). Minor rather than patch for `common/`, not for a
config key: no key was added since 0.19.0.

**The cross-project scope is wired** (#55, #56). `common/` — the subject-level
sibling of `projects/<key>` — was documented from 0.7.0 and created, linked or
read by no verb; fifteen notes sat where no session could reach them. `store`
and `workplace` wire it as `common/shared` and `common/private`, either verb
alone leaving a usable half. Three gates had to be taught it separately, each
routing by path under its own pathspec — see
`wiring-a-scope-is-more-than-its-symlink`. The 15 notes are linted now; 8 were
missing `metadata.evidence` and one had a `name` that did not match its file.

**The documentation split is finished** (#48, #50). The guide, config reference
and skills prose left `README.md` for `docs/guide/` in both languages, the
archaeology left the guide for `docs/lessons.md`, and review verified the moved
lines byte-for-byte. **The four guard defects it exposed are closed** (#49,
#51, #52, #53): four one-level-deep assumptions, a page-table row whose
document was never built, the interpreter pinned once, and a guard that advised
a command which would refuse. What each cost is in
`one-directory-level-broke-four-guards`,
`a-table-row-with-no-document-is-invisible` and
`macos-runner-carries-one-bash-and-it-is-3-2`.

**Drift is watched, and the Russian hub list is derived** (#58). Both were
recorded here as "not to be rediscovered" and both are now closed. See the
freeze below for the shape the drift workflow had to take.

**The macOS temp path is measured** (#29/#30, 2026-09-06) and is still live.
`<b>` in `/var/folders/<a>/<b>/T/` is **fixed by the runner image**, not drawn
per machine: twenty runners returned two components, each tied to a kernel
version 20 out of 20 — 25.5.0 with `_` (6 runners), 25.6.0 without (14), so the
same commit passes or fails by which image it lands on. 2100 `mktemp` suffixes
carried no non-alphanumeric character. The 30% is a rollout mix on one day and
goes to zero when 25.5.0 retires — **leaving the defect intact and the tests
green**. Do not quote the rate without both kernel versions.

## What is frozen

- **`watched_dirs` is `docs/statuses`, and documentation is product**
  (narrowed 2026-09-08). The closing rite may write the status file and nothing
  else; `docs/guide/`, `docs/lessons.md` and `docs/memory-model.md` go through
  review like `skills/`, `scripts/`, `shim/` and `tests/`. While `docs/` held
  only working documents the question did not arise; it does now, and this is
  the answer. `watched_files` is unchanged.
- **Drift is reported to a person, never gated on a branch** (decided
  2026-09-08, #58). `translations.yml` runs on a push to `main` and files one
  issue, updated while the condition holds and **closed automatically** when the
  checker is clean. It must not move to `pull_request`: gating freshness turns a
  typo fix in an English document into bilingual work, and teaches whoever is in
  a hurry to re-stamp without reading — which converts a stale translation into
  a fresh-looking one and destroys the only signal the record carries. The
  contract half is a different rule and *is* gated, by the hand-written loop in
  `tests/test-translations.sh`. The workflow needs a full checkout: the checker
  resolves the blob sha its marker recorded, and a shallow clone lacks that
  object, so every translation would report behind on a repository that is fine.
- **The suite pins its interpreter in PATH, not at every call site** (#52).
  `tests/run.sh` puts a directory holding one `bash` — a symlink to the
  interpreter it was started with — at the front of PATH, covering ~180 bare
  `bash` call sites in one place. Do not "fix" those one by one; the two
  dispatcher execs already carry `"${BASH:-bash}"` because they run outside the
  suite too.
- **`common/` gets no view under `agents_memory_dir`, unlike every other scope**
  (#55). The symmetric shape assumes one store per namespace, and the public
  namespace has one store per project; the suite's own two-store fixture failed
  on it. See `one-common-view-collides-across-stores` before "fixing" the
  asymmetry.
- **Branch protection is symmetric, and must stay so** — no bypass actors, not
  even for the owner. Both sessions writing here are the same git principal, so
  a bypass exempts both. **`strict` is off** for required checks: on a
  repository this quiet it would cost a rebase per pull request.
- **`commit` does not create a branch of its own** (#17). On a protected branch
  it commits, attempts the push, and prints the recipe. Moving someone off the
  branch they were on is a guess, and these scripts decline to guess.
- **`metadata.as_of` is optional and `lint` never fails on age** (#32). Undated
  notes are counted, not named; an aged note is named and the run still passes.
  Both reasons are load-bearing: a check that reddens an existing corpus on
  plugin-update day gets switched off, taking the four earning checks with it;
  and a gate on age teaches people to bump the date without re-checking. A
  future date more than one day out is still a hard failure — that day of slack
  is the measured UTC+3 evening, not politeness.
- **`statuses_personal` is derived, not written live by `init`** — a literal
  value would put one machine's path into a file every machine reads. The same
  argument rules out setting `machine_key` here: `machines/WIN-GVR0V5UPOD7/` is
  ugly and correct, because a hand-picked name would rename the *other* machine.
- **The wrap lock does not cover the private scope** — one lock per rite,
  following the memory every wrap writes. It does not cover two machines at all;
  nothing does.
- **`store` reports the redundant `.gitignore` line rather than removing it.**
  That file belongs to the consumer and a line in it may be hand-written.
- **`quota.lock` holds measured numbers, and raising one is a defended edit.**
  `chars_max` is the measured corpus plus a tenth — 55000 since 2026-09-08.
  `note_chars_max=5000`, **not** the convention's 10000: the longest note here
  is 3223 and the mean 2297, so 10000 would never fire and the rule it enforces
  would be decorative. `pointers_max=25` is where a flat index makes splitting
  into halves cheaper than reading past it. Raise a number only in the same
  commit as the notes that need the room.
- **The injected script in `site/_includes/head_custom.html` uses block comments
  and explicit semicolons.** Not style: the page it becomes has no newlines, and
  either omission makes the whole script dead or invalid. Two asserts enforce it.
- **The vendored search plugins are MPL-1.1, and their notice lives with the
  code** (decided 2026-09-06 by the owner). `lunr-languages@1.14.0` is MPL-1.1,
  not MIT. The three files are vendored verbatim with a `NOTICE.md` and the
  licence beside them; the site footer carries nothing, because MPL asks for
  headers and available source, and a footer line would be a second place to
  keep in step. `site/` only — the plugin is MIT.
- **`translation-check.py --list` is the only expression of what a translation
  is.** `workstatus.sh` keeps a deliberately *loose* pre-gate whose only job is
  deciding whether to start python — `?`, never a bracket range, so the
  collation trap cannot return through it.
- **The sibling rule stays hand-written in `tests/test-translations.sh`**, and
  deriving its expectation from the checker would let a checker bug agree with
  itself. The same reasoning now shapes the site's Russian hub loop the other
  way: that list *is* derived from the page table, so a new page is covered on
  the commit that adds it, and a **literal count** sits beside it as the thing
  derivation cannot fake. The count earned its place immediately — the table's
  closing quote is glued to its last row, and the first derivation dropped
  `ru-lessons` in silence.

## Open

- **The status could be written as the session runs, not at `wrap`.** `wrap`
  fires where context is largest and the accumulated change is biggest — a turn
  at 400–500k context costs $0.20–0.25 in cache reads alone, and a wrap spends
  several of them collecting facts, reconciling the status, writing the index.
  Selecting facts *when they appear* would leave wrap with checking and
  committing. It belongs in the plugin (`wrap` / `workstatus` and their
  conventions), not in a per-project rule, because the plugin already owns both
  the status format and the moment it is written. The same principle is already
  in force for rejected options, which are recorded at the moment of refusal
  because a compaction leaves nothing to recover the reasoning from. Not
  designed, not scheduled — brought here 2026-09-08 from the store where it was
  written and could not be seen.
- **`translation-check.py` has no gate for the contract half outside the
  suite**, by design, but nothing runs it on a *consumer's* repository either:
  `workstatus.sh` reports it and `status --flow` is the only place it surfaces.
- **Two deviations from #48's spec, recorded rather than fixed.** `quota.lock`'s
  justification shipped byte-identical instead of condensed, so 22% of the
  config page is argument — the load-bearing reason survives and is guarded. And
  the site's positive control is a separate reach guard rather than a planted
  document, which was measured to be the stronger of the two.

## What is not true here

No open issues and no open pull requests — checked against `gh` after #58
merged, not recalled. `main` is at `79872c5`, local is in sync, and every branch
those three pull requests used is deleted on both sides. The working tree is
clean apart from an untracked `.claude/` that predates this work. Both memory
stores are committed and pushed.

**The cross-project home is decided** (2026-09-08). `basic-memory` is denied in
this repository — `.claude/settings.json` carries both a `permissions.deny` rule
and a `deniedMcpServers` entry, so the server does not even connect here, while
staying untouched for the projects that use it. Ten notes were carried over
first: eight into `knowledge/notes/` (five harness, three shell, two practice —
counting by area, the two practice notes are the git/measurement pair) and one
into `common/private`; two candidates were dropped as duplicates of notes this
memory already holds. Four of the new notes carry an executable `recheck_cmd`,
which took the machine-checkable half of the base from five notes to nine. The
argument and the condition for revisiting are in
`basic-memory-is-off-in-this-repository`.

`quota.lock` is unchanged this session: no note was written, so the corpus
stands at 20 notes and 20 pointers against a ceiling of 25. The 15 notes in
`common/` carry no `metadata.as_of` and `lint` says so as a warning every run —
that is the field behaving as designed, not something to fix by dating them
from guesswork.

**A caution this file earned twice.** It once closed with "nothing is open"
while three issues had been filed minutes earlier, and it once spent a whole
session describing a state four merges out of date — because the wrap that
would have corrected it was left in an unmerged pull request. A current-state
file carries no sign of its own age, which is why `start` checks `run status`
instead of trusting it.
