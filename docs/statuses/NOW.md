# Current state

What `start` reads in full, rewritten in place rather than appended to — see
`agent-memory` for how that differs from a dated journal entry. Since 0.18.0
this file is the **project's** half only; one person's thread of work belongs
in `statuses_personal`, in the private scope.

## Where things stand

**The memory's effect is re-measured, on the consumer repositories this time**
(2026-09-14). 196 questions from 41 recorded sessions of effectssdk and
agents_harness, methodology identical to the 09-09 run. effectssdk: C 34.9% →
M 62.8%, **+27.9pp at p=1.0e-7**; agents_harness: +11.9pp; arm M lands at
62.7–66.3% in all three measurements — the ceiling is capture, what varies is
how much the repository says about itself without the memory (effectssdk
squashed its history and is 47% repo-silent). Two 09-09 conclusions are
revised — the confirmed slice lifts too, and the corpus carries answers, not
just NOW.md (43 files cited). The note is
`the-lift-scales-with-what-the-repo-does-not-say` in `memory/`; full tables in
the claude.ai artifact «Перезамер памяти floppy».

**The comparison page is published** (#83, 2026-09-14): `docs/comparison.md`
and its Russian sibling under the "Behind it" hub — eight systems, each with
what floppy already has, what was taken in which version, and what is not
being taken; sourced from the survey artifact, verified against 0.24.1.

**0.24.0 and 0.24.1 are released** (2026-09-14, #79 and #81). The measured
failure: projects sharing one clone of the private store share its tree
state, and one project's dirty file killed another's wrap at
`git pull --rebase`. Now all three sync sites pull with
`-c rebase.autoStash=true`, `check` counts a shared clone's dirt in two
piles (this project's scope vs another's, which it says to leave), and
`workplace_memory_dir` is the tested opt-out for a clone of one's own.
0.24.1: `cfg_get` expands a leading `~/` or `$HOME/`. **Refresh
`.floppy/run`: no** for both.

**0.23.0 shipped `heat` and the `consolidate` rite** (2026-09-13, #69, #70),
the pre-release review's ten findings fixed in the same version. **Releases
release themselves** since #76: `release.yml` tags and publishes on every
push to `main`, body from `CHANGELOG.md` — a bump without an entry fails
loudly.

**The documentation was audited against the code** (2026-09-09): six
divergences fixed in one pull request; what each cost is in
`a-check-can-pass-while-testing-something-adjacent`.

**The memory index is split into three halves** (2026-09-09). `MEMORY.md` is
a router — two always-read notes plus one link each to `memory/`, `product/`
and `delivery/`. The routing words are in `AGENTS.md`; `quota.lock` carries
the measurement and the reason there are no per-half budgets.

**The cross-project scope is wired** (#55, #56), **the documentation split is
finished** (#48–#53), and **drift is watched with the Russian hub list derived**
(#58). Their frozen consequences are below; the guard defects the split
exposed are in `one-directory-level-broke-four-guards`,
`a-table-row-with-no-document-is-invisible` and
`macos-runner-carries-one-bash-and-it-is-3-2`.

**The macOS temp path defect is still live** (#29/#30, 2026-09-06): whether
`/var/folders/<a>/<b>/T/` carries a `_` is **fixed by the runner image**
(kernel 25.5.0 yes, 25.6.0 no; 20 of 20 runners), so the same commit passes
or fails by image — and the rate goes to zero when 25.5.0 retires, leaving
the defect intact and the tests green. Do not quote the 30% rate without
both kernel versions.

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
- **Drift is reported to a person, never gated on a branch** (2026-09-08,
  #58). `translations.yml` files one issue, updates it while the condition
  holds, closes it when clean — proven end-to-end by #80. It must not move to
  `pull_request`: gating freshness teaches re-stamping without reading. The
  contract half *is* gated in `tests/test-translations.sh`; the workflow needs
  a full checkout (a shallow clone lacks the marker's blob sha).
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
- **`metadata.as_of` is optional and `lint` never fails on age** (#32): a
  check that reddens a corpus on plugin-update day gets switched off, and a
  gate on age teaches date-bumping without re-checking. A future date more
  than one day out is still a hard failure — the slack is the measured UTC+3
  evening.
- **`statuses_personal` is derived, not written live by `init`** — a literal
  value would put one machine's path into a file every machine reads. The same
  argument rules out setting `machine_key` here: `machines/WIN-GVR0V5UPOD7/` is
  ugly and correct, because a hand-picked name would rename the *other* machine.
- **The private store stays one repository per person, and the shared-clone
  default stays** (decided by the owner 2026-09-14). Isolation is opt-in per
  project via `workplace_memory_dir`; splitting the store into per-project
  repositories was rejected — `common/private` still needs a shared
  repository, so the split keeps the collision and adds fragmentation. The
  argument is in `private-store-stays-one-repo-per-person`; flipping the
  derived-clone default is ruled out at `_checkout_dir` in `lib-config.sh`
  (an upgrade must not move a machine's existing checkout).
- **The wrap lock does not cover the private scope** — one lock per rite,
  following the memory every wrap writes. It does not cover two machines at all;
  nothing does.
- **`store` reports the redundant `.gitignore` line rather than removing it.**
  That file belongs to the consumer and a line in it may be hand-written.
- **`quota.lock` holds measured numbers, and raising one is a defended edit**
  — in the same commit as the notes that need the room. `chars_max=75000`
  (it once stood raised for a day with no comment, the edit the ratchet
  exists to expose), `note_chars_max=5000`, `pointers_max=25` — when the flat
  index hit that, it was split, not raised. No `half_chars_max`: one machine
  writes all three halves.
- **The injected script in `site/_includes/head_custom.html` uses block comments
  and explicit semicolons.** Not style: the page it becomes has no newlines, and
  either omission makes the whole script dead or invalid. Two asserts enforce it.
- **The vendored search plugins are MPL-1.1** (`lunr-languages@1.14.0`;
  decided 2026-09-06). Vendored verbatim with `NOTICE.md` and the licence
  beside them; the site footer carries nothing — MPL asks for headers and
  available source. `site/` only, the plugin itself is MIT.
- **`translation-check.py --list` is the only expression of what a translation
  is.** `workstatus.sh` keeps a deliberately *loose* pre-gate whose only job is
  deciding whether to start python — `?`, never a bracket range, so the
  collation trap cannot return through it.
- **The sibling rule stays hand-written in `tests/test-translations.sh`** —
  deriving its expectation from the checker would let a checker bug agree with
  itself. The site's Russian hub loop *is* derived, from the page table, with a
  **literal count** beside it as the thing derivation cannot fake — the first
  derivation dropped `ru-lessons` in silence.

## Open

- **`translation-check.py` has no gate for the contract half outside the
  suite**, by design, but nothing runs it on a *consumer's* repository either:
  `workstatus.sh` reports it and `status --flow` is the only place it surfaces.
- **Two deviations from #48's spec, recorded rather than fixed.** `quota.lock`'s
  justification shipped uncondensed, so 22% of the config page is argument; and
  the site's positive control is a reach guard rather than a planted document,
  measured to be the stronger of the two.
- **The README Documentation lists are unpinned** (measured 2026-09-13):
  deleting both rows leaves `test-docs` at 49 passed and `test-site` at 103 —
  only the translation reporter would notice. Recorded so the hole is chosen,
  not unknown; pin it or accept it in a reviewed change.
- **The corpus is in the 96% band** — the re-measurement note pushed it to
  72216 of 75000. The next `consolidate` pass is due; `memory/` is the half
  that grew, and `lint` names 15 cold notes as merge candidates.

## What is not true here

No open pull requests — #83 (comparison page) and #84 (`config.ru.md`
catch-up) merged 2026-09-14. The translation drift issue #80 **closed
itself** once the checker ran clean on `main`: the reporter loop worked
end-to-end for the first time — file, update while behind, auto-close.

**The cross-project home is decided** (2026-09-08): `basic-memory` is denied
here via `.claude/settings.json`, untouched everywhere else. The argument and
the revisit condition are in `basic-memory-is-off-in-this-repository`, which
`MEMORY.md` loads every session.

The corpus stands at 31 notes and 34 pointers across 4 indexes, 72216
characters against a ceiling of 75000 — inside the 96% band since the
re-measurement note landed (see Open). The first `consolidate` pass ran on `product/` (2026-09-13, store
commit `e9c2f7c`): one merge, one delete with its replacement named, two
rewrites, one declined merge recorded in
`served-page-collapses-inline-scripts`; no `quota.lock` number moved. The
`common/` notes carry no `metadata.as_of` and `lint` warns so every run —
the field behaving as designed, not something to fix by dating them from
guesswork.

**A caution this file earned twice.** It once closed with "nothing is open"
while three issues had been filed minutes earlier, and it once spent a whole
session describing a state four merges out of date — because the wrap that
would have corrected it was left in an unmerged pull request. A current-state
file carries no sign of its own age, which is why `start` checks `run status`
instead of trusting it.
