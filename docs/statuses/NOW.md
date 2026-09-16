# Current state

What `start` reads in full, rewritten in place rather than appended to — see
`agent-memory` for how that differs from a dated journal. Since 0.18.0 this is
the **project's** half only; one person's thread of work belongs in
`statuses_personal`, in the private scope.

## Where things stand

**Capture is measured, and the mid-session convention works** (2026-09-17;
131 sessions across the five repositories carrying floppy, 68 calling `wrap`).
Notes written *during* the session rather than at `wrap`: **39% before
2026-09-09 → 51% after** (110 of 281, then 21 of 41) — 0.21.0 (#61) does what
it was built for, on a sample that indicates rather than proves. Sessions that
skipped `start` captured **more**, not less (57% vs 44%), so the design's
self-named weakest joint does not show as a failure: **the `SessionStart` hook
stays deferred on evidence now, not on caution**, and the dated answer closes
`docs/specs/2026-09-09-status-written-as-the-session-runs-design.md`. Caveats
there too — skipping `start` correlates with the kind of session, and the
compact-boundary hypothesis decided nothing. Note:
`capture-works-and-does-not-hang-on-start`; method in
`~/projects/paned-agents/measure-capture/`.

**The memory's effect is re-measured on the consumer repositories**
(2026-09-14; 196 questions over 41 sessions of effectssdk and agents_harness,
method identical to 09-09). effectssdk **+27.9pp at p=1.0e-7** (C 34.9% → M
62.8%), agents_harness +11.9pp, arm M at 62.7–66.3% in all three measurements
— the ceiling is capture, and what varies is how much the repository says
about itself unaided (effectssdk is 47% repo-silent). Two 09-09 conclusions
revised: the confirmed slice lifts too, and the corpus carries answers, not
just NOW.md (43 files cited). Note:
`the-lift-scales-with-what-the-repo-does-not-say`; tables in the artifact
«Перезамер памяти floppy».

**0.24.0 and 0.24.1 are released** (2026-09-14, #79, #81). The measured
failure: projects sharing one clone of the private store share its tree state,
and one project's dirty file killed another's wrap at `git pull --rebase`. All
three sync sites now pull with `-c rebase.autoStash=true`, `check` counts a
shared clone's dirt in two piles (this project's scope vs another's, left
alone), `workplace_memory_dir` is the tested opt-out, and 0.24.1 expands a
leading `~/` or `$HOME/` in `cfg_get`. **Refresh `.floppy/run`: no.**

**Shipped and still standing**: the comparison page (#83, eight systems
verified against 0.24.1), `heat` and `consolidate` in 0.23.0 (#69, #70), the
2026-09-09 documentation audit and the three-half index split, the
cross-project scope (#55, #56), the documentation split (#48–#53) and drift
watching (#58). **Releases release themselves** since #76 — `release.yml` tags
and publishes on every push to `main`, body from `CHANGELOG.md`, a bump with
no entry failing loudly. The guard defects the split exposed are in
`one-directory-level-broke-four-guards`,
`a-table-row-with-no-document-is-invisible` and
`macos-runner-carries-one-bash-and-it-is-3-2`; the audit's cost is in
`a-check-can-pass-while-testing-something-adjacent`.

**The macOS temp path defect is still live** (#29/#30, 2026-09-06): whether
`/var/folders/<a>/<b>/T/` carries a `_` is **fixed by the runner image**
(kernel 25.5.0 yes, 25.6.0 no; 20 of 20 runners), so the same commit passes or
fails by image — and the rate goes to zero when 25.5.0 retires, leaving the
defect intact and the tests green. Never quote the 30% without both kernels.

## What is frozen

- **`.floppy/run` stays a committed copy, not a generated file** (owner,
  2026-09-13): a gitignored shim is absent from a fresh clone and from CI. Full
  trade and reversing condition in `shim-is-committed-rather-than-generated`.
- **`watched_dirs` is `docs/statuses`, and documentation is product**
  (narrowed 2026-09-08). The closing rite writes the status file and nothing
  else; `docs/guide/`, `docs/lessons.md` and `docs/memory-model.md` go through
  review like `skills/`, `scripts/`, `shim/` and `tests/`.
- **Drift is reported to a person, never gated on a branch** (2026-09-08,
  #58). `translations.yml` files one issue, updates it while the condition
  holds, closes it when clean — proven end-to-end by #80. It must not move to
  `pull_request`: gating freshness teaches re-stamping without reading. The
  contract half *is* gated in `tests/test-translations.sh`; that workflow needs
  a full checkout — a shallow clone lacks the marker's blob sha.
- **The suite pins its interpreter in PATH, not at every call site** (#52).
  `tests/run.sh` fronts PATH with a directory holding one `bash` — a symlink to
  the interpreter it was started with — covering ~180 bare `bash` call sites at
  once. Do not "fix" those one by one; the two dispatcher execs already carry
  `"${BASH:-bash}"` because they run outside the suite too.
- **`common/` gets no view under `agents_memory_dir`, unlike every other
  scope** (#55): the symmetric shape assumes one store per namespace and the
  public one has many. Read `one-common-view-collides-across-stores` before
  "fixing" the asymmetry.
- **Branch protection is symmetric, and must stay so** — no bypass actors, not
  even for the owner: both sessions writing here are the same git principal, so
  a bypass exempts both. **`strict` is off** for required checks — on a
  repository this quiet it would cost a rebase per pull request.
- **`commit` does not create a branch of its own** (#17). On a protected branch
  it commits, attempts the push, prints the recipe. Moving someone off the
  branch they were on is a guess, and these scripts decline to guess.
- **`metadata.as_of` is optional and `lint` never fails on age** (#32): a check
  that reddens a corpus on plugin-update day gets switched off, and a gate on
  age teaches date-bumping without re-checking. A future date over a day out is
  still a hard failure — the slack is the measured UTC+3 evening.
- **`statuses_personal` is derived, not written live by `init`** — a literal
  value would put one machine's path into a file every machine reads. The same
  argument rules out setting `machine_key` here: `machines/WIN-GVR0V5UPOD7/` is
  ugly and correct, because a hand-picked name renames the *other* machine.
- **The private store stays one repository per person, and the shared-clone
  default stays** (owner, 2026-09-14). Isolation is opt-in per project via
  `workplace_memory_dir`; per-project repositories were rejected in
  `private-store-stays-one-repo-per-person`. Flipping the derived-clone default
  is ruled out at `_checkout_dir` in `lib-config.sh`: an upgrade must not move
  a machine's existing checkout.
- **The wrap lock does not cover the private scope** — one lock per rite,
  following the memory every wrap writes. It does not cover two machines;
  nothing does.
- **`store` reports the redundant `.gitignore` line rather than removing it** —
  that file belongs to the consumer and a line in it may be hand-written.
- **`quota.lock` holds measured numbers, and raising one is a defended edit** —
  in the same commit as the notes that need the room. `chars_max=75000` (it
  once stood raised for a day with no comment, the edit the ratchet exists to
  expose), `note_chars_max=5000`, `pointers_max=25` — when the flat index hit
  that it was split, not raised. No `half_chars_max`: one machine writes all
  three halves. Same shape for this file: `statuses_now_chars_max=12000` is
  condensed against, not raised.
- **The injected script in `site/_includes/head_custom.html` uses block
  comments and explicit semicolons.** Not style: the page it becomes has no
  newlines, and either omission makes the script dead or invalid. Two asserts
  enforce it.
- **The vendored search plugins are MPL-1.1** (`lunr-languages@1.14.0`;
  2026-09-06), verbatim with `NOTICE.md` and the licence beside them; the site
  footer carries nothing — MPL asks for headers and available source. `site/`
  only, the plugin itself is MIT.
- **`translation-check.py --list` is the only expression of what a translation
  is.** `workstatus.sh` keeps a deliberately *loose* pre-gate whose only job is
  deciding whether to start python — `?`, never a bracket range, so the
  collation trap cannot come back through it.
- **The sibling rule stays hand-written in `tests/test-translations.sh`** —
  deriving its expectation from the checker would let a checker bug agree with
  itself. The site's Russian hub loop *is* derived, from the page table, with a
  **literal count** beside it as the thing derivation cannot fake: the first
  derivation dropped `ru-lessons` in silence.

## Open

- **This file is patched, not rewritten, and the rule against that is already
  written** (measured 2026-09-17). Edits per `wrap` run: **1.6 before
  2026-09-09 → 4.1 after** (92 over 58 runs, then 41 over 10; over just the
  runs that touched it, 3.2 → 5.1). `skills/wrap/SKILL.md` **§5** says word for
  word *"rewrite the current-state file once, don't patch it"*, off a 2.6-edit
  measurement over the same denominator — a written rule that is not obeyed,
  with the trend running away from it. Levels still do not compare (2.6 counted
  turns in one project, this counts write events in five); the direction does. It is patching's expensive instance: this file is the
  memory's most-read artefact, 17 of 21 citations, patched at the session's
  most expensive turn — and it stood at 11745 of its 12000 cap before these
  entries, condensed to hold them with nothing dropped
  (`the-status-file-is-patched-not-rewritten`). A stronger rule, a check or
  dropping it is the owner's call.
- **`translation-check.py` has no gate for the contract half outside the
  suite**, by design, but nothing runs it on a *consumer's* repository either:
  `workstatus.sh` reports it, and `status --flow` is where it surfaces.
- **Two deviations from #48's spec, recorded rather than fixed:**
  `quota.lock`'s justification shipped uncondensed (22% of the config page is
  argument), and the site's positive control is a reach guard rather than a
  planted document, measured the stronger of the two.
- **The README Documentation lists are unpinned** (measured 2026-09-13):
  deleting both rows leaves `test-docs` at 49 passed and `test-site` at 103,
  only the translation reporter noticing. Recorded so the hole is chosen, not
  unknown; pin or accept it in a reviewed change.
- **The corpus is at its ceiling** — the two 09-17 notes put it at 74996 of
  75000. The next `consolidate` pass is not due but overdue; `memory/` is the
  half that grew twice, and `lint` names 17 cold notes as merge candidates.

## What is not true here

No open pull requests — #83 and #84 merged 2026-09-14. The translation drift
issue #80 **closed itself** once the checker ran clean on `main`: the reporter
loop worked end-to-end for the first time — file, update, auto-close.

**The cross-project home is decided** (2026-09-08): `basic-memory` is denied
here via `.claude/settings.json`, untouched everywhere else — argument and
revisit condition in `basic-memory-is-off-in-this-repository`, which `MEMORY.md`
loads every session.

The corpus stands at 33 notes and 36 pointers across 4 indexes. The first
`consolidate` pass ran on `product/` (2026-09-13, store commit `e9c2f7c`): one
merge, one delete with its replacement named, two rewrites, one declined merge
in `served-page-collapses-inline-scripts`; no `quota.lock` number moved. The
`common/` notes carry no `metadata.as_of` and `lint` warns every run — the
field behaving as designed, not something to fix by guessing dates.

**A caution this file earned twice.** It once closed with "nothing is open"
while three issues had been filed minutes earlier, and it once described a
state four merges out of date because the wrap that would have fixed it sat in
an unmerged pull request. A current-state file carries no sign of its own age —
which is why `start` checks `run status` instead of trusting it.
