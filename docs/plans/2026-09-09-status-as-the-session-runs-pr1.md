# Writing the memory as the session runs — implementation plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Move the selection and writing of memory notes out of `wrap` and into
the moment the fact appears, leaving `wrap` with the leftovers, the status file,
`check` and `commit`.

**Architecture:** Four prose edits and no code. `agent-memory` gains the
convention (when a note is written, and why mid-session writing needs no lock);
`start` plants the trigger, because it is the only rite loaded early enough to
be read before the first note-moment arrives; `wrap` §1 is reframed from "select
what's worth memory" to "select what is left"; the skills guide and its Russian
translation stop describing selection as something that happens at `wrap`.

**Tech Stack:** Markdown only. `python3` (stdlib) for `translation-check.py`;
bash 3.2 for the suite that must stay green.

**Spec:** `docs/specs/2026-09-09-status-written-as-the-session-runs-design.md`

## Global Constraints

- **`main` is protected.** Branch, push the branch, open a PR (`gh pr create
  --fill`). Self-merge is fine. A `GH013` on push is the rule working.
- **No AI attribution in commits or PRs.** No trailers, no "generated with".
- **`skills/` and `docs/guide/` are product here.** This does not go through
  `wrap`; `watched_dirs` is `docs/statuses` alone.
- **Skills carry no `allowed-tools` key** and `name:` must match the directory.
  `tests/test-skills.sh` enforces both — do not add frontmatter keys.
- **Script and skill output is English**, always. Only `*.ru.md` is Russian.
- **A translation is re-stamped, never hand-edited into agreement.** After
  editing `docs/guide/skills.md`, translate the same change into
  `docs/guide/skills.ru.md` and then run `--stamp`. Stamping without
  translating records a lie the drift checker will believe.
- **Nothing in the suite tests this change.** Every gate stays green whether or
  not the prose is correct — see the spec's Testing section. The suite is run at
  each task to prove nothing *broke*, not to prove the change works.

## Boundaries verified 2026-09-09

Checked against the working tree at `3c31700`. **Re-verify before each cut** —
an earlier task in this plan moves the later line numbers.

| file | anchor | line |
|---|---|---|
| `skills/agent-memory/SKILL.md` (293 lines) | `## The `quota.lock` ratchet` | 136 |
| `skills/start/SKILL.md` (112 lines) | `## Answering` | 96 |
| `skills/wrap/SKILL.md` (303 lines) | `## 1. Select what's worth memory` | 45 |
| | `## Report to the human` | 288 |
| `docs/guide/skills.md` (41 lines) | `- **`wrap`** — closes a session.` | 26 |
| `docs/guide/skills.ru.md` (41 lines) | `- **`wrap`** — закрывает сессию.` | 26 |

Re-verify with:

```bash
grep -n '^## ' skills/agent-memory/SKILL.md skills/start/SKILL.md skills/wrap/SKILL.md
grep -n 'wrap' docs/guide/skills.md docs/guide/skills.ru.md
```

---

### Task 0: Branch

**Files:** none.

- [ ] **Step 1: Confirm the tree is clean and in sync**

```bash
cd /home/amalaev/work/ai_floppy
AI_FLOPPY_HOME=$(pwd) bash .floppy/run status
```

Expected: `tree is clean`, `in sync with origin/main`. If the spec from the
brainstorming session is still uncommitted, that is expected — it is committed
in Task 1 together with the first edit.

- [ ] **Step 2: Branch**

```bash
git switch -c notes-written-when-they-appear
```

---

### Task 1: `agent-memory` carries the convention

**Files:**
- Modify: `skills/agent-memory/SKILL.md` — frontmatter `description`, and a new
  section inserted immediately before `## The `quota.lock` ratchet`
- Also commit: `docs/specs/2026-09-09-status-written-as-the-session-runs-design.md`

**Interfaces:**
- Produces: the section title **"When a note gets written: at the moment, not
  at the end"** and the five triggers. Tasks 2, 3 and 4 refer to this section by
  that title and must not restate its content.

- [ ] **Step 1: Run the suite first, so a later failure is attributable**

```bash
bash tests/run.sh
```

Expected: all green. If anything is already red, stop and report — do not start
editing on top of a red suite.

- [ ] **Step 2: Widen the description**

The `description` is what the harness reads to decide whether the skill
applies, so the new content has to be named in it or it will not be loaded at
the moment it is needed.

Replace, in the frontmatter, `one fact per file, note frontmatter` with:

```
one fact per file, the moment a note gets written, note frontmatter
```

- [ ] **Step 3: Insert the new section**

Insert immediately **before** the line `## The `quota.lock` ratchet`:

```markdown
## When a note gets written: at the moment, not at the end

A note is written **when the fact appears**, not collected at the end of the
session. Five moments produce notes:

- an option or a hypothesis is **rejected** — the reason is exact now and
  reconstructed later;
- a **measurement lands** — the number, and what it was measured against;
- a number **turns out to mean something other than it looked like**;
- a **tool or platform trap** bites;
- a **decision is frozen** — a choice that constrains later work.

Not moments: finishing a task, making a commit, a green suite. Those are in the
git log, and a list of what got done is the least valuable thing a memory can
hold.

Two reasons, different in kind.

**The reasoning is only intact now.** A rejected option carries its argument
for as long as the conversation holds it. What survives a summary is the
decision, not the argument — so the next session proposes the same option again
and pays for the same refusal twice.

**The end of a session is the most expensive place to think.** Every turn
resends the whole window, the window only grows, and closing is where it is
largest, so the same judgement costs more there than anywhere else. That is
arithmetic over the turn measurement in `wrap`, not a measurement of its own:
what nobody has counted is how many of a wrap's turns go to selecting facts
rather than to checking and committing.

**What is safe to write mid-session, and what is not.** A note file collides
with nothing — its name is unique, so two sessions writing two notes write two
files. Its pointer is a single anchored line, and an insert applies against
whatever the index holds at that moment, so two sessions inserting different
pointers both land. Neither needs the lock.

The whole-file rewrite is the opposite, and it stays in `wrap` under the lock:
rewriting an index, or either status file, is where a second writer silently
drops the first one's work.

**The pointer is written with the note, never after it.** A note no index
points at is a hard `lint` error, not a warning — nobody will find it. Write
both or neither.
```

- [ ] **Step 4: Verify the guards still pass**

```bash
bash tests/run.sh skills
python3 scripts/translation-check.py
```

Expected: green, and `clean: every translation names its source and matches
it.` — `skills/*/SKILL.md` has no translation, so the checker must not have
moved.

- [ ] **Step 5: Verify the site still builds with the new description**

The skills guide embeds each `description` verbatim through a generated block,
so a description change reaches the site.

```bash
bash scripts/site-build.sh /tmp/floppy-site-check && bash tests/run.sh site
```

Expected: build succeeds and the site tests are green.

- [ ] **Step 6: Commit**

```bash
git add skills/agent-memory/SKILL.md docs/specs/2026-09-09-status-written-as-the-session-runs-design.md
git commit -m "agent-memory: a note is written when the fact appears, not at wrap"
```

---

### Task 2: `start` plants the trigger

**Files:**
- Modify: `skills/start/SKILL.md` — a new final section appended after the
  `## Answering` section

**Interfaces:**
- Consumes: the five triggers from Task 1, named in short form only. `start`
  must not restate the argument — it points at `agent-memory`.

- [ ] **Step 1: Re-verify the file's end**

```bash
tail -5 skills/start/SKILL.md
```

Expected: the paragraph ending `…rather than answering against state that no
longer holds.`

- [ ] **Step 2: Append the section**

Append to the end of the file:

```markdown

## What carries into the session

This rite ends here, but one rule outlives it. From now on a fact worth keeping
is written **when it appears**, not collected at the end. The moments that
produce a note are in `agent-memory`; the short form is that an option was
rejected, a measurement landed, a number turned out to mean something else, a
tool trap bit, or a decision was frozen.

Nothing is written now — `start` reads. The rule is stated here because this is
the only place early enough to be read before the first of those moments
arrives: `wrap` is loaded at the end, and `agent-memory` is loaded when a note
is already being written, which is too late to be the thing that prompts one.
```

- [ ] **Step 3: Verify**

```bash
bash tests/run.sh skills
```

Expected: green. `tests/test-skills.sh` checks that `name:` still matches the
directory and that no `allowed-tools` key was introduced.

- [ ] **Step 4: Commit**

```bash
git add skills/start/SKILL.md
git commit -m "start: plant the note-moment trigger, the only rite loaded early enough"
```

---

### Task 3: `wrap` keeps the leftovers

**Files:**
- Modify: `skills/wrap/SKILL.md` — §1 heading and opening; part 1 of the closing
  report

**Interfaces:**
- Consumes: the section title from Task 1 and `agent-memory`'s existing
  refinement/deletion rules, referred to by name rather than restated.

- [ ] **Step 1: Re-verify both anchors**

```bash
grep -n "^## 1\. Select\|^## Report to the human" skills/wrap/SKILL.md
```

Expected: two lines. Their numbers may have shifted only if this file was
edited; it has not been by Tasks 1–2.

- [ ] **Step 2: Reframe §1**

Replace exactly these three lines:

```markdown
## 1. Select what's worth memory

A candidate earns a note only if it passes all three:
```

with:

```markdown
## 1. Select what is left

Most of this session's facts should already be notes — a fact is written when
it appears, not collected here; `agent-memory` holds the moments that produce
one. What is left for this step is whatever became clear only at the end: a
conclusion about the shape of the whole session, an approach whose rejection
made sense only in hindsight.

**Do not re-open what the session already wrote.** Those notes stand as
written. A refinement edits the file that already states the fact, and a note
that stopped being true is rewritten in place or deleted — both are
`agent-memory`'s rules, and neither is a review pass run at the single most
expensive moment of the session.

A candidate earns a note only if it passes all three:
```

Everything below that line — the three criteria, what is explicitly not saved,
and what is usually lost — is unchanged. It is the admission test, and it
applies at the moment of capture exactly as it applied here.

- [ ] **Step 3: Make part 1 of the report cover both halves**

Replace:

```markdown
1. **What got recorded** — one line per fact, with its file path.
```

with:

```markdown
1. **What got recorded** — one line per fact, with its file path. Both halves:
   what was written during the session, and what this rite added. A report that
   lists only the second understates the session's memory, and part 2 is
   worthless when part 1 is incomplete.
```

- [ ] **Step 4: Verify no other passage still claims selection happens here**

Three separate greps, not one. A single pattern will not find the guide: its
bullet wraps the line immediately after "selects", so `"selects the facts"`
matches nothing there and a clean result would read as "nothing left to fix".
`docs/specs/` and `docs/plans/` are excluded because they quote the old wording
on purpose.

```bash
grep -rn "Select what's worth" skills/
grep -rn "selects" docs/guide/skills.md README.md
grep -rn "отбирает факты" docs/guide/skills.ru.md README.ru.md
```

Expected: the first returns nothing at all. The second and third still hit
`docs/guide/skills.md:26` and `docs/guide/skills.ru.md:26` — those are Task 4's
job. A hit in `README.md` or `README.ru.md` is a passage this plan missed: fix
it in this task and say so in the commit message.

- [ ] **Step 5: Verify**

```bash
bash tests/run.sh
```

Expected: the whole suite green.

- [ ] **Step 6: Commit**

```bash
git add skills/wrap/SKILL.md
git commit -m "wrap: select what is left, and report both halves of what was recorded"
```

---

### Task 4: The guide, and its translation

**Files:**
- Modify: `docs/guide/skills.md` — the `agent-memory` bullet and the `wrap`
  bullet
- Modify: `docs/guide/skills.ru.md` — the same two bullets
- Re-stamp: `docs/guide/skills.ru.md` line 1

**Interfaces:**
- Consumes: Tasks 1 and 3. The guide describes the rites; it must not disagree
  with the skills after those tasks.

- [ ] **Step 1: Edit the English guide — the `agent-memory` bullet**

That bullet currently ends `Each fact belongs to one scope: project, workplace,
or machine.` Extend it so it ends:

```markdown
  holds the size limits. Each fact belongs to one scope: project, workplace, or
  machine. A note is written at the moment the fact appears, not collected at
  the end of the session.
```

- [ ] **Step 2: Edit the English guide — the `wrap` bullet**

Replace:

```markdown
- **`wrap`** — closes a session. The agent takes the lock. The agent selects
  the facts that are worth a note, updates the state file, and records the
  unfinished work.
```

with:

```markdown
- **`wrap`** — closes a session. The agent takes the lock. Most facts are notes
  already, written when they appeared; here the agent adds only what is left,
  updates the state file, and records the unfinished work.
```

The remainder of the bullet — `check`, then `commit` — is unchanged.

- [ ] **Step 3: Translate the same two changes into `docs/guide/skills.ru.md`**

The `agent-memory` bullet gains:

```markdown
Заметка пишется в момент появления факта, а не собирается в конце сессии.
```

And the `wrap` bullet's first sentences become:

```markdown
- **`wrap`** — закрывает сессию. Агент берёт замок. Большая часть фактов уже
  записана заметками в момент их появления; здесь агент добавляет только то,
  что осталось, обновляет файл состояния и записывает незавершённую работу.
```

The remainder of the Russian bullet — `check`, then `commit` — is unchanged.

- [ ] **Step 4: Confirm the checker sees the drift before stamping**

```bash
python3 scripts/translation-check.py
```

Expected: it reports `docs/guide/skills.ru.md` as behind its source. **This step
exists to prove the stamp in Step 5 is doing something.** If the checker is
already clean here, the edit did not land — go back to Step 1.

- [ ] **Step 5: Re-stamp**

```bash
python3 scripts/translation-check.py --stamp docs/guide/skills.ru.md
python3 scripts/translation-check.py
```

Expected: `clean: every translation names its source and matches it.`

- [ ] **Step 6: Verify the site**

```bash
bash tests/run.sh
```

Expected: the whole suite green, including `test-site.sh`'s Russian hub loop
and its literal count.

- [ ] **Step 7: Commit**

```bash
git add docs/guide/skills.md docs/guide/skills.ru.md
git commit -m "guide: selection is not a wrap step, in both languages"
```

---

### Task 5: Pull request

**Files:** none.

- [ ] **Step 1: Push**

```bash
git push -u origin HEAD
```

- [ ] **Step 2: Open the PR**

```bash
gh pr create --fill
```

- [ ] **Step 3: Confirm CI is green on both platforms**

```bash
gh pr checks --watch
```

Expected: the Linux and macOS `tests.yml` jobs both pass. The macOS job is the
one that runs `/bin/bash tests/run.sh` against bash 3.2 — a green Linux run
alone does not stand in for it.

- [ ] **Step 4: Report to the owner and stop**

Do not self-merge without saying what landed. Name in the report: the four
prose edits, that no test covers the change, and that the release bump is
deliberately not in this PR.

---

## What this plan deliberately does not do

- **No new verb, script, config key or hook.** All four were considered and
  rejected or deferred in the spec; see its "Rejected, with reasons" and
  "Hooks: checked, and not used" sections before re-proposing any of them.
- **No release.** The three manifests and `CHANGELOG.md` are untouched. When the
  owner wants it, the entry's **"Refresh `.floppy/run`?"** answer is **no**.
- **No change to `workstatus`.** Rejected in the spec: it would turn a report
  into a chore, and the trigger already lives in `start`.
