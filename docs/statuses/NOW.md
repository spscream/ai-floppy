# Current state

What `start` reads in full, rewritten in place rather than appended to — see
`agent-memory` for how that differs from a dated journal entry. Since 0.18.0
this file is the **project's** half only; one person's thread of work belongs
in `statuses_personal`, in the private scope.

## Where things stand

**0.21.0 is released** (2026-09-09) — tagged, published, three manifests agree.
Its subject is the rite, not the code: **a note is written at the moment the
fact appears, not collected at `wrap`** (#61, #62). Minor rather than patch
because the ritual behaves differently, though no verb, key or path moved and
a memory written the old way stays correct. **Refresh `.floppy/run`: no** —
the shim is untouched. The previous release, 0.20.0 (2026-09-08), is the one
that said **yes**, the first since 0.14.0, and said why it was a small yes:
#52 changed the shim's last line to `exec "${BASH:-bash}"`, so an
un-refreshed copy still works except where somebody names an interpreter.

**The documentation was audited against the code** (2026-09-09) — README and
both language sets, the guide, the skills, `memory-model`, `lessons`, the
knowledge contract, `CHANGELOG` and the manifests, each claim checked against
the script that implements it. Six divergences, all now fixed in one pull
request; what they were and what each cost is in
`a-check-can-pass-while-testing-something-adjacent`. The largest was not in a document at
all: `skills/init/SKILL.md` carried **four of the shim's six** plugin-search
branches, so `init` told a Cursor user "plugin not found" for a plugin
`.floppy/run` resolves — reproduced with the old block, and the two Cursor
branches now have cases in `tests/test-init-bootstrap.sh`.

**The memory index is split into three halves** (2026-09-09). `MEMORY.md` is a
router now — two always-read notes plus one link each to `memory/` (the model,
the scopes, what the memory earns), `product/` (scripts, shim, tests, site,
knowledge) and `delivery/` (branches, PRs, workflows). The routing words are in
`AGENTS.md`, where a consumer's own knowledge belongs; `quota.lock` carries the
measurement and the reason there are no per-half budgets.

**The cross-project scope is wired** (#55, #56), **the documentation split is
finished** (#48–#53), and **drift is watched with the Russian hub list derived**
(#58). All three closed; their frozen consequences are below, and the four
guard defects the split exposed are in
`one-directory-level-broke-four-guards`,
`a-table-row-with-no-document-is-invisible` and
`macos-runner-carries-one-bash-and-it-is-3-2`.

**The macOS temp path is measured** (#29/#30, 2026-09-06) and is still live.
`<b>` in `/var/folders/<a>/<b>/T/` is **fixed by the runner image**, not drawn
per machine: twenty runners returned two components, each tied to a kernel
version 20 out of 20 — 25.5.0 with `_` (6 runners), 25.6.0 without (14), so the
same commit passes or fails by which image it lands on. 2100 `mktemp` suffixes
carried no non-alphanumeric character. The 30% is a rollout mix on one day and
goes to zero when 25.5.0 retires — **leaving the defect intact and the tests
green**. Do not quote the rate without both kernel versions.

## What is frozen

- **`.floppy/run` stays a committed copy, not a generated file** (decided by
  the owner 2026-09-13, closing the question asked 2026-09-09). The deciding
  risk: a gitignored shim is absent from a fresh clone and from CI, and only an
  agent with the plugin installed can restore it. The full trade and the
  reversing condition are in `shim-is-committed-rather-than-generated`.
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
  `chars_max` is the measured corpus plus a tenth — 65000 since 2026-09-09,
  against a measured 58303. It stood at 61000 for a day with no comment and no
  commit, which is the edit the ratchet exists to expose.
  `note_chars_max=5000`, **not** the convention's 10000: the longest note here
  is 4248 and the mean 2332, so 10000 would never fire and the rule it enforces
  would be decorative. `pointers_max=25` is where a flat index makes splitting
  into halves cheaper than reading past it, and on 2026-09-09 it did: the index
  hit 25 exactly and was **split into `memory/`, `product/` and `delivery/`**
  rather than raised — the largest index is 11 pointers now. A half that fills
  splits again into sub-indexes; three levels is the floor of the tree, not a
  budget. No `half_chars_max` keys: one machine writes all three halves, so a
  per-half ceiling would fire when the corpus one does. Raise a number only in
  the same commit as the notes that need the room.
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

- **`translation-check.py` has no gate for the contract half outside the
  suite**, by design, but nothing runs it on a *consumer's* repository either:
  `workstatus.sh` reports it and `status --flow` is the only place it surfaces.
- **Two deviations from #48's spec, recorded rather than fixed.** `quota.lock`'s
  justification shipped uncondensed, so 22% of the config page is argument; and
  the site's positive control is a reach guard rather than a planted document,
  measured to be the stronger of the two.

## What is not true here

No open issues and no open pull requests before this one — checked against `gh`
on 2026-09-09, not recalled. `main` was at `95a2f75` (0.21.0) when the audit
started, local in sync, working tree clean. Both memory stores are committed and
pushed, including the four notes and the `quota.lock` raise this audit found
sitting uncommitted.

**The cross-project home is decided** (2026-09-08). `basic-memory` is denied
here — `.claude/settings.json` carries a `permissions.deny` rule and a
`deniedMcpServers` entry, so the server does not connect in this repository
while staying untouched everywhere else. Ten notes were carried over first,
eight into `knowledge/notes/` and one into `common/private`. The argument, the
breakdown and the condition for revisiting are in
`basic-memory-is-off-in-this-repository`, which `MEMORY.md` loads every session.

The corpus stands at 25 notes and 25 pointers, 58303 characters against a
ceiling of 65000. The 15 notes in `common/` carry no `metadata.as_of` and `lint`
says so as a warning every run — that is the field behaving as designed, not
something to fix by dating them from guesswork.

**A caution this file earned twice.** It once closed with "nothing is open"
while three issues had been filed minutes earlier, and it once spent a whole
session describing a state four merges out of date — because the wrap that
would have corrected it was left in an unmerged pull request. A current-state
file carries no sign of its own age, which is why `start` checks `run status`
instead of trusting it.
