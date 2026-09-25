# Current state

What `start` reads in full, rewritten in place rather than appended to. Since
0.18.0 this is the **project's** half only; a person's thread of work belongs
in `statuses_personal`, in the private scope.

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
in the note — `capture-works-and-does-not-hang-on-start`; method in
`~/projects/paned-agents/measure-capture/`.

**The memory's effect is re-measured on the consumer repositories**
(2026-09-14; 196 questions over 41 sessions of effectssdk and agents_harness,
method identical to 09-09). effectssdk **+27.9pp at p=1.0e-7** (C 34.9% → M
62.8%), agents_harness +11.9pp, arm M at 62.7–66.3% in all three measurements
— the ceiling is capture, and what varies is how much the repository says
about itself unaided (effectssdk is 47% repo-silent). Two 09-09 conclusions
revised: the confirmed slice lifts too, and the corpus carries answers, not
just NOW.md. Note: `the-lift-scales-with-what-the-repo-does-not-say`; tables in
the artifact «Перезамер памяти floppy».

**0.25.0 and 0.25.1 are released** (2026-09-18, #92 and #93). 0.25.0 shipped a
backlog of ten commits that had reached no consumer — the manifests sat at
0.24.1 since 09-14, so `plugin update` had nothing to copy. In it: `wrap`'s
skill a tenth shorter, its ~750 words of measurement moved to
`skills/wrap/measurements.md` and read only when a rule is questioned; the
rewrite-once rule given a price (a median 32k base-equivalent tokens per
patching turn); the UTC slack for `knowledge-rot-check.py`.

0.25.1 is a defect reported from a consumer checkout. With `public_repo` and
`private_repo` naming **one** repository — the only layout open to a project
whose own checkout may hold no notes — every file in the private scope came
back from `guard` as *"not changed: wrong path, or the edit was lost"*, the
message for a typo. Coverage of a scope is decided by **containment, not by
repository identity**: the memory scan reaches what lies under the memory
scope, and a sibling prefix does not. With the fix: one repository is one
commit rather than two carrying one message; an unscanned scope says so
instead of wearing the typo message; and a bash condition in a note is no
longer read as a `[[link]]` — a hard error that took `check` and the commit
with it. Verified on the reporting checkout. **Refresh `.floppy/run`: no**,
for either release.

**Shipped and still standing**: 0.24.0/0.24.1 (#79, #81 — autostash at all
three sync sites, `check`'s two-pile count of a shared clone,
`workplace_memory_dir` as the tested opt-out, `~`/`$HOME` expanded in
`cfg_get`), the comparison page (#83, eight systems verified against 0.24.1),
`heat` and `consolidate` in 0.23.0 (#69, #70), the three-half index split, the
cross-project scope (#55, #56), the documentation split (#48–#53) and drift
watching (#58). **Releases release
themselves** since #76 — `release.yml` tags and publishes on every push to
`main`, body from `CHANGELOG.md`, a bump with no entry failing loudly. The
guard defects the split exposed have notes of their own in `product/`.

**The macOS temp path defect is still live** (#29/#30, 2026-09-06): whether
`/var/folders/<a>/<b>/T/` carries a `_` is **fixed by the runner image**
(kernel 25.5.0 yes, 25.6.0 no; 20 of 20 runners), so the same commit passes or
fails by image — and the rate goes to zero when 25.5.0 retires, leaving the
defect intact and the tests green.

## What is frozen

- **A runner in the consumer's repository is either committed or absent —
  never gitignored** (owner, 2026-09-13; carried out 2026-09-25): a gitignored
  shim is absent from a fresh clone, from CI and from every new worktree. The
  committed copy went the other way in 0.26.0: the skills call
  `<plugin>/scripts/run`, `init` writes `.floppy/config` alone, and `shim/run`
  still ships for the repositories that already carry a copy. The note
  `shim-is-committed-rather-than-generated` states the older half of this and
  needs the second half written into it.
- **`watched_dirs` is `docs/statuses`, and documentation is product**
  (narrowed 2026-09-08). The closing rite writes the status file and nothing
  else; `docs/guide/`, `docs/lessons.md` and `docs/memory-model.md` go through
  review like `skills/`, `scripts/`, `shim/` and `tests/`.
- **Drift is reported to a person, never gated on a branch** (2026-09-08,
  #58). `translations.yml` files one issue, updates it, closes it when clean —
  proven end-to-end by #80. It must not move to `pull_request`: gating
  freshness teaches re-stamping without reading. The contract half *is* gated
  in `tests/test-translations.sh`; that workflow needs a full checkout — a
  shallow clone lacks the marker's blob sha.
- **The suite pins its interpreter in PATH, not at every call site** (#52).
  `tests/run.sh` fronts PATH with one `bash` — a symlink to the interpreter it
  was started with — covering ~180 bare call sites at once. Do not "fix" those
  one by one; the two dispatcher execs carry `"${BASH:-bash}"` already, because
  they run outside the suite too.
- **`common/` gets no view under `agents_memory_dir`, unlike every other
  scope** (#55): the symmetric shape assumes one store per namespace and the
  public one has many. Read `one-common-view-collides-across-stores` before
  "fixing" the asymmetry.
- **Branch protection is symmetric, and must stay so** — no bypass actors, not
  even for the owner: both sessions writing here are the same git principal, so
  a bypass exempts both. **`strict` is off** for required checks — on a
  repository this quiet it would cost a rebase per pull request.
- **`commit` does not create a branch of its own** (#17). On a protected branch
  it commits, attempts the push, prints the recipe: moving someone off the
  branch they were on is a guess.
- **`metadata.as_of` is optional and `lint` never fails on age** (#32): a check
  that reddens a corpus on plugin-update day gets switched off, and a gate on
  age teaches date-bumping without re-checking. A future date over a day out
  stays a hard failure — the slack is the measured UTC+3 evening.
- **`statuses_personal` is derived, not written live by `init`** — a literal
  value would put one machine's path into a file every machine reads. Same
  argument against setting `machine_key`: a hand-picked name renames the
  *other* machine.
- **The private store stays one repository per person, and the shared-clone
  default stays** (owner, 2026-09-14). Isolation is opt-in per project via
  `workplace_memory_dir`; per-project repositories were rejected in
  `private-store-stays-one-repo-per-person`. Flipping the derived-clone default
  is ruled out at `_checkout_dir`: an upgrade must not move an existing
  checkout.
- **The wrap lock does not cover the private scope** — one lock per rite,
  following the memory. It does not cover two machines; nothing does.
- **`store` reports the redundant `.gitignore` line rather than removing it**:
  that file belongs to the consumer and a line in it may be hand-written.
- **`quota.lock` holds measured numbers, and raising one is a defended edit** —
  in the same commit as the notes that need the room. `chars_max=75000` (it
  once stood raised for a day with no comment, the edit the ratchet exists to
  expose), `note_chars_max=5000`, `pointers_max=25` — when the flat index hit
  that it was split, not raised. Same shape for this file:
  `statuses_now_chars_max=12000` is condensed against, not raised.
- **The injected script in `site/_includes/head_custom.html` uses block
  comments and explicit semicolons.** Not style: the page it becomes has no
  newlines, and either omission makes the script dead or invalid. Two asserts
  enforce it.
- **The vendored search plugins are MPL-1.1** (`lunr-languages@1.14.0`;
  2026-09-06), verbatim with `NOTICE.md` and the licence beside them; the site
  footer carries nothing — MPL asks for headers and available source.
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

- **The corpus is AT its ceiling** — 74995 of 75000, with `memory/` the half
  that grew twice (23809). `consolidate` on that half is overdue, and until it
  runs **no note can be written**: this session had one to write and could not.
  `lint` names the cold candidates; `product/` was done 2026-09-13.
- **This file is patched, not rewritten, and the rule against that is already
  written** (measured 2026-09-17). Edits per `wrap` run: **1.6 before
  2026-09-09 → 4.1 after**; `skills/wrap/SKILL.md` §5 says word for word
  *"rewrite the current-state file once, don't patch it"*. A written rule that
  is not obeyed, with the trend running away from it, on the memory's most-read
  artefact at the session's most expensive turn. Numbers, denominators and the
  caveat that the levels do not compare are in
  `the-status-file-is-patched-not-rewritten`. A stronger rule, a check or
  dropping it is the owner's call.
- **The one-repository layout is fixed and tested but not documented.**
  `docs/guide/config.md` gives no recipe for `public_repo == private_repo`,
  so the layout a consumer reached for unaided is still discoverable only from
  `CHANGELOG.md`. Deliberately out of 0.25.1's scope, not forgotten.
- **`translation-check.py` has no gate for the contract half outside the
  suite**, by design, but nothing runs it on a *consumer's* repository either:
  `workstatus.sh` reports it, and `status --flow` is where it surfaces.
- **Two deviations from #48's spec, recorded not fixed:** `quota.lock`'s
  justification shipped uncondensed, and the site's positive control is a reach
  guard, not a planted document.
- **The README Documentation lists are unpinned** (measured 2026-09-13):
  deleting both rows leaves both docs gates green, only the translation
  reporter noticing. Recorded so the hole is chosen; pin or accept it in a
  reviewed change.

## What is not true here

No open pull requests — #92 and #93 merged 2026-09-18, #83 and #84 on 09-14.
The translation drift issue #80 **closed itself** once the checker ran clean on
`main`: the reporter loop worked end-to-end for the first time.

**The cross-project home is decided** (2026-09-08): `basic-memory` is denied
here via `.claude/settings.json`, untouched everywhere else — argument and
revisit condition in `basic-memory-is-off-in-this-repository`, which `MEMORY.md`
loads every session.

The corpus stands at 33 notes and 36 pointers across 4 indexes. The first
`consolidate` pass ran on `product/` (2026-09-13, store commit `e9c2f7c`): one
merge, one delete, two rewrites, one declined merge; no `quota.lock` number
moved. The `common/` notes carry no `metadata.as_of` and `lint` warns every
run — the field behaving as designed, not something to fix by guessing dates.

**A caution this file earned twice.** It once closed with "nothing is open"
minutes after three issues were filed, and once described a state four merges
old because the wrap that would have fixed it sat in an unmerged pull request.
A current-state file carries no sign of its own age — which is why `start`
checks `run status` instead of trusting it.
