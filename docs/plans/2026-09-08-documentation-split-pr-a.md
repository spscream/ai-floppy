# Documentation split, PR A: extract the guide — implementation plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Move installation, the config reference and the skills prose out of
`README.md` into `docs/guide/`, leaving a ~400-word landing page, with every
guard rebound to the file that now holds each answer.

**Architecture:** No new content and no rewriting — the change is three cuts in
`README.md` and the same three cuts in `README.ru.md`, made at verified line
boundaries. The site's page table gains six rows; the skills page keeps its
generated half through a placeholder that `site-build.sh` substitutes.
`tests/test-docs.sh` stops asking "is this in the README" and starts asking "is
this where it belongs".

**Tech Stack:** bash 3.2, `python3` (stdlib only) for the translation stamper,
Jekyll/just-the-docs on the site (CI only — no Ruby is needed to work on this).

**Spec:** `docs/specs/2026-09-07-documentation-split-design.md`

## Global Constraints

- **bash 3.2.57 is the floor.** No `mapfile`, no `declare -A`, no `wait -n`, no
  `stat -c`, no GNU-only flags. The macOS CI job runs `/bin/bash tests/run.sh`.
- **`main` is protected.** Branch, push, open a PR. Never push to `main`.
- **No AI attribution in commits or PRs.** No trailers, no "generated with".
- **Script and test output is English**, always.
- **No new prose except the two landing pages.** Every other sentence in this PR
  already exists in a tracked file and is moved verbatim. A reshuffle that also
  rewrites cannot be reviewed, because the diff stops showing what moved.
- **`README.md` line 1 stays `# floppy`** — `tests/test-site.sh` asserts the
  source carries no Jekyll front matter by checking that exact first line.
- **Never restore a falsified file with `git checkout <file>`.** On a file that
  is modified but not yet committed, that silently discards the edit — it once
  took the real fix with it here, and the "restored" run stayed red, which is
  the only reason anyone noticed. Copy to a `mktemp -d` first and restore from
  the copy.

## Verified boundaries

These line numbers were checked against the working tree on 2026-09-08 and are
what every cut below refers to. **Re-verify them before cutting** — if an earlier
step in this plan has already edited the file, they have moved.

| file | section | first line |
|---|---|---|
| `README.md` (493 lines) | `## Requirements` | 17 |
| | `## The five skills` | 154 |
| | `` ## `.floppy/config` `` | 185 |
| | `## The memory model` | 458 |
| `README.ru.md` (498 lines) | `## Требования` | 18 |
| | `## Пять скиллов` | 159 |
| | `` ## `.floppy/config` `` | 189 |
| | `## Модель памяти` | 463 |

Re-verify with:

```bash
grep -n '^## ' README.md | sed -n '1p;5p;6p;9p'
grep -n '^## ' README.ru.md | sed -n '1p;5p;6p;9p'
```

## File structure

**Created:**
- `docs/guide/install.md` — requirements, both harnesses' install, the two stale
  copies, `init`. From `README.md:17-153`.
- `docs/guide/config.md` — the `.floppy/config` key table, checkout layout, the
  external-memory layout, `quota.lock`. From `README.md:185-457`.
- `docs/guide/skills.md` — the five skills as prose, plus the generated
  descriptions. From `README.md:154-184` plus a placeholder line.
- `docs/guide/install.ru.md`, `docs/guide/config.ru.md`,
  `docs/guide/skills.ru.md` — the same cuts of `README.ru.md`.

**Modified:**
- `README.md` — reduced to the landing page.
- `README.ru.md` — the same, re-stamped.
- `scripts/site-build.sh` — six table rows; the skills page becomes a source
  file with a substituted block instead of a wholly generated page.
- `tests/test-docs.sh` — assertions rebound per file.
- `tests/test-site.sh` — `docs_list` covers `docs/guide/`; a guard proves it
  does; the "whole README" assertion is rebound.
- `.floppy/config` — `watched_dirs=docs` becomes `docs/statuses`.
- `docs/statuses/NOW.md` — the frozen entry, dated.
- `CLAUDE.md` — the sentence about adding a file under `docs/`.

**Not touched:** `CHANGELOG.md`, `knowledge/`, `skills/*/SKILL.md`,
`docs/lessons.md`, `docs/memory-model.md`. The last two move in PR B.

---

### Task 1: Rebind the guards, and watch them fail

The tests change first and go red naming exactly what is missing. Nothing in
this task creates a document — that is Task 2's job, and the red output here is
the specification it satisfies.

**Files:**
- Modify: `tests/test-docs.sh:14-52`
- Modify: `tests/test-site.sh:137-139`, `tests/test-site.sh:161`

**Interfaces:**
- Produces: three paths that Task 2 must create — `docs/guide/install.md`,
  `docs/guide/config.md`, `docs/guide/skills.md` — and the exact strings each
  must contain, listed in the assertions below.

- [ ] **Step 1: Branch**

```bash
git switch -c docs-split-guide
```

- [ ] **Step 2: Rebind `tests/test-docs.sh`**

Replace lines 14–52 (from `readme="$(cat README.md ...` through the `esac` that
closes the `quota.lock` check) with:

```bash
readme="$(cat README.md 2>/dev/null || true)"
license="$(cat LICENSE 2>/dev/null || true)"

# Each answer is asserted against the file that now holds it, not against the
# documentation as a whole. A key documented in the wrong place used to pass;
# it no longer does, because where an answer lives is what a reader depends on.
install_doc="$(cat docs/guide/install.md 2>/dev/null || true)"
config_doc="$(cat docs/guide/config.md  2>/dev/null || true)"
skills_doc="$(cat docs/guide/skills.md  2>/dev/null || true)"

# A missing file makes every `assert_contains` against it fail, which is correct
# but reports the same defect three times over. Named once, here.
for f in docs/guide/install.md docs/guide/config.md docs/guide/skills.md; do
  assert_eq "$f exists" "0" "$([[ -f "$f" ]] && echo 0 || echo 1)"
done

assert_contains "LICENSE is MIT"            "MIT License" "$license"
assert_contains "README states the license" "MIT"         "$readme"

assert_contains "install page covers: marketplace add" "plugin marketplace add" "$install_doc"
assert_contains "install page covers: plugin install"  "plugin install"        "$install_doc"
assert_contains "install page covers the Cursor equivalent" "Cursor"           "$install_doc"

# The landing page keeps a quick start, so the two commands appear there too.
# Asserted separately: they serve different readers, and one of the two copies
# going missing is a defect either way.
assert_contains "README quick start keeps: marketplace add" "plugin marketplace add" "$readme"
assert_contains "README quick start keeps: plugin install"  "plugin install"        "$readme"

for skill in init agent-memory start workstatus wrap; do
  assert_contains "skills page names skill \`$skill\`" "\`$skill\`" "$skills_doc"
  assert_contains "README names skill \`$skill\`"      "\`$skill\`" "$readme"
done

# Claude Code namespaces skills by plugin name (floppy:start); Cursor lists
# them flat (/start). The difference is stated exactly once, on the skills
# page — everywhere else the bare name, since that's the only form true in
# both harnesses. Counted across both files: moving the explanation from one
# to the other must not be able to produce two copies of it.
floppy_prefixed_count="$(grep -hoE 'floppy:(init|agent-memory|start|workstatus|wrap)' \
  README.md docs/guide/skills.md 2>/dev/null | wc -l | tr -d ' ')"
assert_eq "the floppy: prefix form appears exactly once (the explanation)" "1" "$floppy_prefixed_count"

# Every key the config parser resolves must be documented — a key read but
# never documented is exactly the class of defect this fix wave was about.
# The parser moved into the plugin in 0.14.0 (scripts/lib-config.sh); reading
# it from shim/run still "passed" for a while afterwards, silently, because an
# empty key list makes this loop assert nothing at all.
keys="$(grep -oE 'cfg_get [a-z_]+' scripts/lib-config.sh | awk '{print $2}' | sort -u)"
assert_eq "the config parser is where this test thinks it is" "0" \
  "$([[ -n "$keys" ]] && echo 0 || echo 1)"
while IFS= read -r key; do
  [[ -z "$key" ]] && continue
  assert_contains "config page documents key: $key" "\`$key\`" "$config_doc"
done <<< "$keys"

assert_contains "config page explains quota.lock is measured per project" "measur" "$config_doc"
case "$config_doc" in
  *"never copied"*) ok "config page states quota.lock is never copied between projects" ;;
  *) fail "config page states quota.lock is never copied between projects" "never copied" "$config_doc" ;;
esac
```

Also update the file's header comment (lines 2–6) to say what it now guards:

```bash
# CRITICAL 2: the user documentation covers what it is required to, in the file
# that is supposed to cover it. Structural, like test-skills.sh — there is no
# behaviour to run, only shape to guard: every config key the plugin actually
# reads (scripts/lib-config.sh's cfg_get calls) is documented on the config
# page, the install commands are on the install page, and the landing page
# keeps enough to install without leaving GitHub.
```

- [ ] **Step 3: Extend the document list in `tests/test-site.sh`**

Replace line 138 (`  docs_list="docs/*.md"`, the `else` branch) with:

```bash
  docs_list="docs/*.md docs/guide/*.md"
```

- [ ] **Step 4: Guard that the new half of the list is reached**

The positive control at the end of the file passes its document explicitly
through `--selftest`, so it proves the heading guard fires — it does **not**
prove the glob reaches `docs/guide/`. Without the guard below, reverting Step 3
would delete the guide pages' assertions silently and the run would stay green.
This is the same shape as the empty-key-list guard in `tests/test-docs.sh`.

Insert immediately after the `for src in $docs_list; do ... done` loop
(after the `done` that closes it, around line 158):

```bash
# The loop above asserts nothing about a directory its glob does not reach, and
# says nothing when that happens. `docs/guide/` was added to the list in the
# same change that created it; if the list is ever narrowed back, the guide
# pages stop being checked and every remaining assertion still passes. A check
# that quietly stops checking is the failure this file exists to prevent.
# Skipped under --selftest, where the list is one named document by design.
if [[ "${1:-}" != "--selftest" ]]; then
  guide_seen=0
  for src in $docs_list; do
    case "$src" in docs/guide/*.md) [[ -f "$src" ]] && guide_seen=1 ;; esac
  done
  assert_eq "the document list reaches docs/guide/" "1" "$guide_seen"
fi
```

- [ ] **Step 5: Rebind the "whole README" assertion**

Line 161 asserts the index page carries `` ## `quota.lock` ``, which is moving
out of the README. Replace that one line with an assertion against something the
landing page keeps:

```bash
assert_contains "index carries the whole README" "## Documentation" "$index"
```

- [ ] **Step 6: Run the two files and confirm they fail for the right reasons**

```bash
FLOPPY_TEST_JOBS=1 bash tests/run.sh test-docs
FLOPPY_TEST_JOBS=1 bash tests/run.sh test-site
```

Expected in `test-docs`: `FAIL docs/guide/install.md exists`, the same for
`config.md` and `skills.md`, then every assertion against those three documents
failing. Expected in `test-site`, **three** failures:
`FAIL the document list reaches docs/guide/`, `FAIL index carries the whole
README`, and `FAIL docs/guide/*.md has a top-level heading to match on`.

That third one is the existing heading guard working correctly, not a defect.
`docs/guide/` does not exist yet, no `nullglob` is set anywhere in this suite,
so bash passes the unmatched pattern through literally and `h1` comes back
empty — which is precisely what that guard was built to fail on. It disappears
in Task 2. **Do not add `shopt -s nullglob` to silence it:** that would make a
genuinely deleted or emptied `docs/` produce a silently empty loop, which is the
"check that quietly stops checking" failure this file exists to prevent.

**Read the failures.** If anything fails that is not on that list, the edit is
wrong — fix it before continuing. A guard that is red for an unintended reason
proves nothing when it later turns green.

- [ ] **Step 7: Commit**

```bash
git add tests/test-docs.sh tests/test-site.sh
git commit -m "Guards ask where an answer lives, not just whether it exists

Red until the guide pages exist. test-docs.sh asserted every config key
against README.md as a whole, so a key documented in the wrong section
passed; it now names the file that has to carry each answer. test-site.sh
covers docs/guide/ and carries a guard proving the list reaches it — the
positive control passes its document explicitly, so it can only prove the
heading guard fires, never that the glob arrived anywhere."
```

---

### Task 2: Create the English guide pages

**Files:**
- Create: `docs/guide/install.md`, `docs/guide/config.md`, `docs/guide/skills.md`
- Modify: `README.md`

**Interfaces:**
- Consumes: the three paths and required strings from Task 1.
- Produces: `docs/guide/skills.md` containing the literal line
  `<!-- floppy:generated skills-list -->`, which Task 3 substitutes.

- [ ] **Step 1: Re-verify the boundaries**

```bash
grep -n '^## ' README.md | sed -n '1p;5p;6p;9p'
```

Expected: `17:## Requirements`, `154:## The five skills`,
`` 185:## `.floppy/config` ``, `458:## The memory model`. If they differ, use
what this prints — the ranges below are relative to these four numbers.

- [ ] **Step 2: Cut the three pages out**

```bash
mkdir -p docs/guide
{ printf '# Install and init\n\n'; sed -n '17,153p' README.md; } > docs/guide/install.md
{ printf '# The five skills\n\n'; sed -n '154,184p' README.md; } > docs/guide/skills.md
{ printf '# Config reference\n\n'; sed -n '185,457p' README.md; } > docs/guide/config.md
```

Each page needs a `# ` heading of its own: `tests/test-site.sh` matches a
document to its page by the first heading, and fails a document that has none.

- [ ] **Step 3: Fix the headings that are now one level too deep**

Each page's own title is now the `# ` heading, so the old heading that repeated
it goes:

- `skills.md` — delete the `## The five skills` line.
- `config.md` — delete the `` ## `.floppy/config` `` line. That leaves three
  `### ` headings (`Where the checkouts are`, `The scope names changed in
  0.5.0`, `Two memory repositories on one machine`) hanging directly under the
  `# ` with no `## ` above them, because they used to be children of the
  deleted line. Promote those three to `## `; the two that already are `## `
  (`Memory in a different repository`, `` `quota.lock` ``) stay.
- `install.md` — nothing to delete. `## Requirements`, `## Install` and
  `## Two stale copies…` were already top-level sections, and their `### `
  children stay `### `.

Verify with `grep -n '^#\{1,3\} ' docs/guide/*.md`: every file starts with one
`# `, and no `### ` appears before the first `## `.

- [ ] **Step 4: Add the placeholder to the skills page**

In `docs/guide/skills.md`, after the prose and before the end of the file, add:

```markdown
## What each skill says about itself

The block below is generated at build time from each `skills/<name>/SKILL.md`'s
own `description` field — the same text the harness reads when it decides
whether a skill applies. This page therefore cannot describe a skill
differently from the way the agent sees it.

<!-- floppy:generated skills-list -->
```

- [ ] **Step 5: Fix relative links inside the moved text**

The moved sections contain links written from the repository root, such as
`[docs/lessons.md](docs/lessons.md)` and `[LICENSE](LICENSE)`. From
`docs/guide/` those resolve one directory too low on GitHub.

```bash
grep -n '](\(docs/\|knowledge/\|LICENSE\|CHANGELOG\)' docs/guide/*.md
```

Rewrite each hit to climb out: `](../lessons.md)`, `](../../knowledge/README.md)`,
`](../../LICENSE)`, `](../../CHANGELOG.md)`. Leave `http` links alone. The site
build rewrites these again for the site; this step is about GitHub.

- [ ] **Step 6: Reduce `README.md` to the landing page**

Keep lines 1–16 (title, the Russian link, the opening description) and 458–493
(the memory model pointer, the knowledge base pointer, Releases, License).
Between them, write the quick start and the documentation map. The result is
about 400 words and must contain, per Task 1's assertions: `plugin marketplace
add`, `plugin install`, all five skill names in backticks, `MIT`, and a
`## Documentation` heading.

```markdown
## Install

```
claude plugin marketplace add spscream/ai-floppy
claude plugin install floppy@floppy
```

Cursor, a local checkout, and what to do when an update copies nothing:
[Install and init](docs/guide/install.md).

## Then

Run `init` once in each repository. It writes `.floppy/run` and
`.floppy/config`, creates the memory index and the state file, and points your
`AGENTS.md` at the conventions.

Five skills: `init`, `agent-memory`, `start`, `workstatus`, `wrap`.
What each one does: [The five skills](docs/guide/skills.md).

## Documentation

- [Install and init](docs/guide/install.md) — both harnesses, and the two
  stale copies that cause no error message
- [Config reference](docs/guide/config.md) — every `.floppy/config` key, the
  checkout layout, memory in a separate repository, `quota.lock`
- [The five skills](docs/guide/skills.md)
- [The memory model](docs/memory-model.md) — two namespaces, two axes
- [Lessons](docs/lessons.md) — what this plugin learned the expensive way
- [The knowledge base](knowledge/README.md) — findings about the harness
  itself, true whether or not you use floppy
```

Note the `## Documentation` heading is what Task 1 Step 5 rebound the site
assertion to. Do not rename it without changing that line too.

- [ ] **Step 7: Run the docs guard**

```bash
FLOPPY_TEST_JOBS=1 bash tests/run.sh test-docs
```

Expected: `0 failed`. If a config key is reported missing, it was in a part of
the README that did not make it into `config.md` — find it and move it, do not
add new prose for it.

- [ ] **Step 8: Falsify the rebinding**

Prove the new assertions can go red, and that each looks at the file it names.
**Restore from the scratchpad copy, never with `git checkout`** — on a modified,
uncommitted file that discards the edit.

```bash
SP="$(mktemp -d)"
cp docs/guide/config.md "$SP/config.md.bak"
grep -v '`memory_dir`' docs/guide/config.md > "$SP/config.tmp" && mv "$SP/config.tmp" docs/guide/config.md
FLOPPY_TEST_JOBS=1 bash tests/run.sh test-docs | grep 'memory_dir'
cp "$SP/config.md.bak" docs/guide/config.md
rm -rf "$SP"
```

Expected: a `FAIL config page documents key: memory_dir` line. Then confirm the
restore is clean with `bash tests/run.sh test-docs` reporting `0 failed`.

- [ ] **Step 9: Commit**

```bash
git add docs/guide README.md
git commit -m "The guide leaves the front page: install, config, skills

README.md was 4302 words, 18% of it archaeology, and a reader who came to
install a plugin met other people's incident reports before the table of
config keys. The three reference sections move verbatim into docs/guide/ —
no sentence is rewritten, so the diff still shows what moved — and the front
page becomes a landing with the two install commands on it."
```

---

### Task 3: Put the pages on the site

**Files:**
- Modify: `scripts/site-build.sh` — the page table (lines 32–42) and the skills
  page generator (lines 114–130)

**Interfaces:**
- Consumes: `docs/guide/skills.md` and its `<!-- floppy:generated skills-list -->`
  line from Task 2.

- [ ] **Step 1: Add the English table rows**

The Russian rows come in Task 4, with the files they point at. Adding them now
would make the copy loop redirect from files that do not exist: the redirect
fails, no page is written, and the `printf 'ok ...'` on the next line still
claims one was.

Replace the `pages='...'` block with:

```bash
pages='README.md|index.md|Home|1
docs/guide/install.md|install.md|Install & init|2
docs/guide/config.md|config.md|Config reference|3
docs/guide/skills.md|skills.md|The five skills|4
|knowledge.md|The knowledge base|5
docs/memory-model.md|memory-model.md|The memory model|6
docs/lessons.md|lessons.md|Lessons|7
CHANGELOG.md|changelog.md|Changelog|8
|ru.md|Русский|9
README.ru.md|ru-index.md|floppy по-русски|1|Русский
docs/memory-model.ru.md|ru-memory-model.md|Модель памяти|2|Русский
docs/lessons.ru.md|ru-lessons.md|Уроки|3|Русский'
```

The last two rows are **carried over unchanged, at the nav_order they already
have**. They are existing pages with existing passing assertions (`the hub links
to ru-memory-model`, `ru-memory-model names its parent`, and the two for
ru-lessons); dropping them here would regress four green tests for a task that
has nothing to do with them. Task 4 renumbers them to 5 and 6 in the same edit
that inserts the guide rows at 2-4, so they never collide.

`memory-model` and `lessons` stay top-level here and move under a parent in PR B.

- [ ] **Step 2: Fix the two nav_orders that are not read from the table**

The table is documentation for two of these pages, not their source: `emit` is
called for them with a literal number. Left alone, `knowledge.md` stays at 4 and
collides with the skills page's new 4 — and `test-site.sh` asserts nav_order is
unique per parent, so this goes red rather than merely looking wrong.

- `scripts/site-build.sh:170` — `emit knowledge.md "The knowledge base" 4`
  becomes `... 5`
- `scripts/site-build.sh:188` — `emit ru.md "Русский" 7 "" 1`
  becomes `... 9 "" 1`

- [ ] **Step 3: Make the skills page a source file with a substituted block**

The page is generated whole today. `docs/guide/skills.md` is now an ordinary row
in the table, so the main copy loop writes `$out/skills.md` from it; the block
below then splices the generated descriptions into that copy. Delete the old
generator (`{ printf '# The five skills\n\n' ... } | emit skills.md ... 5`, lines
114–130) and put this in its place:

```bash
# ---------- the skills page: prose from the guide, descriptions generated ----------
# The descriptions are each SKILL.md's own `description` field, read at build
# time, so the site cannot describe a skill differently from the way the harness
# reads it. That property predates the guide page and has to survive it, so the
# page is a source document with one placeholder rather than a generated page:
# a generated page with no source row would fall out of test-site.sh's "every
# document reaches the site" loop.
skills_block="$(
  for name in init agent-memory start workstatus wrap; do
    f="skills/$name/SKILL.md"
    [[ -f "$f" ]] || { printf 'missing %s\n' "$f" >&2; exit 1; }
    desc="$(awk '/^description: /{sub(/^description: /,""); print; exit}' "$f")"
    printf '### `%s`\n\n%s\n\n[SKILL.md on GitHub](%s/%s)\n\n' \
      "$name" "$desc" "$blob" "$f"
  done
)" || exit 1
# Written to a file and spliced with `r`, not passed through sed's replacement
# text: the descriptions contain `&`, `/` and newlines, all of which a
# replacement string would eat or mangle.
printf '%s\n' "$skills_block" > "$out/.skills-block"
for page in skills.md ru-skills.md; do
  [[ -f "$out/$page" ]] || continue
  sed -e '/<!-- floppy:generated skills-list -->/{r '"$out"'/.skills-block' -e 'd;}' \
    "$out/$page" > "$out/$page.tmp" && mv "$out/$page.tmp" "$out/$page"
done
rm -f "$out/.skills-block"
printf 'ok skills/*/SKILL.md -> skills.md, ru-skills.md\n'
```

This block must run **after** the main copy loop, since it edits the copies the
loop produced.

- [ ] **Step 4: Build the site and look at the result**

```bash
bash scripts/site-build.sh .site
grep -c '^### `' .site/skills.md
grep -h '^nav_order: ' .site/*.md | sort | uniq -c
head -30 .site/install.md
```

Expected: `5` for the description count; no top-level `nav_order` appearing
twice except where a `parent:` separates them; and `install.md` starting with
front matter, then `# Install and init`.

- [ ] **Step 5: Run the site guard**

```bash
FLOPPY_TEST_JOBS=1 bash tests/run.sh test-site
```

Expected: `0 failed`, including `the document list reaches docs/guide/` and
`site carries docs/guide/install.md`. The Russian guide pages do not exist yet
and have no rows yet; Task 4 adds both together.

- [ ] **Step 6: Falsify the glob guard**

```bash
sed -i.bak 's|docs_list="docs/\*.md docs/guide/\*.md"|docs_list="docs/*.md"|' tests/test-site.sh
FLOPPY_TEST_JOBS=1 bash tests/run.sh test-site | grep 'reaches docs/guide'
mv tests/test-site.sh.bak tests/test-site.sh
```

Expected: `FAIL the document list reaches docs/guide/`. On macOS `sed -i` needs
the backup suffix, which is why it is written this way; the `mv` restores the
original.

- [ ] **Step 7: Commit**

```bash
git add scripts/site-build.sh
git commit -m "The site carries the guide, and the skills page keeps its generated half

Six table rows, and the skills page stops being generated whole: it is now a
source document with one placeholder, because a generated page has no source
row and would fall out of the loop that asserts every document reaches the
site. The descriptions are still each SKILL.md's own field, spliced with
sed's r command rather than a replacement string — they contain & and / and
newlines."
```

---

### Task 4: Cut the Russian half

**Files:**
- Create: `docs/guide/install.ru.md`, `docs/guide/config.ru.md`,
  `docs/guide/skills.ru.md`
- Modify: `README.ru.md`, `scripts/site-build.sh` (the Russian table rows),
  `tests/test-site.sh:246` (the Russian "whole README" assertion)

**Interfaces:**
- Consumes: the English table and the splice loop from Task 3. The splice loop
  already names `ru-skills.md` and skips it while it does not exist, so it
  starts working the moment this task creates the file.

- [ ] **Step 1: Re-verify the Russian boundaries**

```bash
grep -n '^## ' README.ru.md | sed -n '1p;5p;6p;9p'
```

Expected: `18:## Требования`, `159:## Пять скиллов`,
`` 189:## `.floppy/config` ``, `463:## Модель памяти`.

- [ ] **Step 2: Cut the three pages out**

Line 1 of `README.ru.md` is the translation marker and must not be copied into
the new files — each gets its own in Step 6.

```bash
{ printf '# Установка и init\n\n'; sed -n '18,158p' README.ru.md; } > docs/guide/install.ru.md
{ printf '# Пять скиллов\n\n';    sed -n '159,188p' README.ru.md; } > docs/guide/skills.ru.md
{ printf '# Справочник конфигурации\n\n'; sed -n '189,462p' README.ru.md; } > docs/guide/config.ru.md
```

- [ ] **Step 3: Mirror every structural edit from Task 2**

Delete the duplicated own-title headings (`## Пять скиллов`,
`` ## `.floppy/config` ``), fix the relative links the same way
(`](../lessons.ru.md)`, `](../../knowledge/README.md)`), and add the same
placeholder to `docs/guide/skills.ru.md` with a Russian lead-in that says the
descriptions stay English because `SKILL.md` is read by a model:

```markdown
## Что каждый скилл говорит о себе

Блок ниже собирается при сборке сайта из поля `description` файла
`skills/<name>/SKILL.md`. Он остаётся английским: эти файлы читает модель, и
их формулировки — это поведение, а не текст для чтения. Поэтому страница не
может описать скилл иначе, чем его видит агент.

<!-- floppy:generated skills-list -->
```

Then reduce `README.ru.md` to the landing page: keep lines 1–17 and 463–498, and
translate the quick start and documentation map written in Task 2 Step 6.

- [ ] **Step 4: Add the Russian table rows**

Now that the three files exist, append to the `pages='...'` block in
`scripts/site-build.sh`, after the `README.ru.md` row:

```
docs/guide/install.ru.md|ru-install.md|Установка и init|2|Русский
docs/guide/config.ru.md|ru-config.md|Справочник конфигурации|3|Русский
docs/guide/skills.ru.md|ru-skills.md|Пять скиллов|4|Русский
docs/memory-model.ru.md|ru-memory-model.md|Модель памяти|5|Русский
docs/lessons.ru.md|ru-lessons.md|Уроки|6|Русский
```

The last two rows already exist in the table — move them below the new ones so
the order in the file matches the sidebar, and renumber as shown. The Russian
hub page is generated by filtering this table on `parent`, so no list of these
pages is written anywhere by hand.

- [ ] **Step 5: Rebind the Russian "whole README" assertion**

`tests/test-site.sh:246` asserts `the Russian index carries the whole README`
against `` ## `quota.lock` `` in `ru-index.md` — the mirror of the English one
Task 1 rebound. It is left alone until now on purpose: it stays true, and green,
right up until this task reduces `README.ru.md`. Fix it in the same task that
invalidates it:

```bash
assert_contains "the Russian index carries the whole README" "## Документация" \
  "$(cat "$out/ru-index.md" 2>/dev/null || true)"
```

The needle must match the heading actually used in the Russian landing page's
documentation map from Step 3. If you named it differently there, use that name.

- [ ] **Step 6: Stamp all four translations**

```bash
python3 scripts/translation-check.py --stamp docs/guide/install.ru.md
python3 scripts/translation-check.py --stamp docs/guide/config.ru.md
python3 scripts/translation-check.py --stamp docs/guide/skills.ru.md
python3 scripts/translation-check.py --stamp README.ru.md
```

- [ ] **Step 7: Check the stamps and the dates**

```bash
python3 scripts/translation-check.py
head -1 docs/guide/install.ru.md
```

Expected: the checker reports every translation naming its source and matching
it. **Check the date in the marker**: the stamper writes today's date, and a
date more than one day ahead of the runners' UTC clock is a hard failure
elsewhere in this repository. If it is a late evening in UTC+3, confirm the
stamped date is not already tomorrow in UTC.

- [ ] **Step 8: Run the two guards that cover this**

```bash
FLOPPY_TEST_JOBS=1 bash tests/run.sh test-translations
FLOPPY_TEST_JOBS=1 bash tests/run.sh test-site
```

Expected: `0 failed` from both. `test-site` now also asserts
`site carries docs/guide/install.ru.md` and the two others.

- [ ] **Step 9: Commit**

```bash
git add docs/guide README.ru.md scripts/site-build.sh tests/test-site.sh
git commit -m "The Russian half is cut at the same seams

README.ru.md matched the English outline heading for heading, 22 against 22,
so this is the same three cuts rather than a translation job. The only new
Russian prose is the landing page. The skills page keeps English
descriptions and says why: SKILL.md is read by a model, and its wording is
behaviour."
```

---

### Task 5: Narrow what the closing rite may commit

**Files:**
- Modify: `.floppy/config`, `docs/statuses/NOW.md`, `CLAUDE.md`

- [ ] **Step 1: Narrow `watched_dirs`**

In `.floppy/config`, replace `watched_dirs=docs` with `watched_dirs=docs/statuses`
and rewrite the comment above it:

```
# What wrap may commit here. Deliberately narrow: in THIS repository the
# session procedure is the product — skills/, scripts/, shim/, tests/ are the
# tool itself, and they belong in ordinary reviewed commits, not in a closing
# rite. Since 2026-09-08 the user documentation is on that same side: docs/guide
# and the two lesson documents go through review like the code, and the rite
# may write only the status file. wrap-guard matches these by prefix, so a
# nested path needs no code change.
watched_dirs=docs/statuses
```

- [ ] **Step 2: Confirm the guard actually narrowed**

```bash
AI_FLOPPY_HOME=$(pwd) bash .floppy/run guard docs/guide/install.md
```

Expected: a refusal naming `docs/guide/install.md` as outside the watched paths.
This is the point of the change — if it is accepted, the config edit did not take.

- [ ] **Step 3: Record the frozen decision**

In `docs/statuses/NOW.md`, under "What is frozen", replace the
`watched_dirs` / `watched_files` entry with:

```markdown
- **`watched_dirs` is `docs/statuses`, and documentation is product**
  (narrowed 2026-09-08). The closing rite may write the status file and
  nothing else; `docs/guide/`, `docs/lessons.md` and `docs/memory-model.md`
  go through review like `skills/`, `scripts/`, `shim/` and `tests/`. The
  earlier entry kept `docs` whole, which was never a decision that
  documentation belonged to the rite — while `docs/` held only working
  documents the question did not arise. It does now, and this is the answer.
  `watched_files` is unchanged: `AGENTS.md`, `.floppy/run`, `.floppy/config`.
```

- [ ] **Step 4: Update `CLAUDE.md`**

The bullet under "Constraints that tests enforce" says adding a file under
`docs/` means adding a row to the page table. Replace that sentence with:

```markdown
  `CHANGELOG.md`. Adding a file under `docs/` **or `docs/guide/`** means adding
  a row to the page table in `scripts/site-build.sh`; `tests/test-site.sh` fails
  otherwise, and carries a separate guard asserting its document list still
  reaches `docs/guide/` at all.
```

And in the same file, the `wrap` bullet: `watched_dirs`/`watched_files` now
permit only `docs/statuses`, `AGENTS.md`, `.floppy/run`, `.floppy/config`.

- [ ] **Step 5: Run the whole suite on both interpreters available here**

```bash
bash tests/run.sh
```

Expected: `0 failed` across every file. This is the first run of the complete
suite in this PR; everything before it ran two or three files.

- [ ] **Step 6: Commit**

```bash
git add .floppy/config docs/statuses/NOW.md CLAUDE.md
git commit -m "Documentation is product: the rite may write only the status file

watched_dirs narrows from docs to docs/statuses. The frozen entry already
said the session procedure is the product and belongs in reviewed commits;
what it never had to decide, while docs/ held only working documents, is
which side documentation falls on. It falls on the product side."
```

---

### Task 6: Open the pull request

- [ ] **Step 1: Add the spec**

The spec has not been committed yet — by the precedent of #36 it travels with
the first implementation PR.

```bash
git add docs/specs/2026-09-07-documentation-split-design.md \
        docs/plans/2026-09-08-documentation-split-pr-a.md
git commit -m "The design and the plan behind the documentation split"
```

- [ ] **Step 2: Push and open**

```bash
git push -u origin HEAD
gh pr create --title "The guide leaves the front page, and the guards learn where an answer lives" --fill-verbose
```

The body must state: what moved and that nothing was rewritten; that
`test-docs.sh` is now stricter than what it replaces; that the glob guard exists
because the positive control cannot prove the glob; and that PR B still owes the
archaeology and the "Behind it" nav section.

- [ ] **Step 3: Wait for both CI jobs**

```bash
gh pr checks --watch
```

Both `linux` and `macos-bash-3-2` must pass. The macOS job is the one that
matters here: `sed -i`, `grep -h` and the `r` splice in Task 3 all behave
differently under BSD tools.

---

## What PR B still owes

PR B is **not planned here, and deliberately so**: it moves incidents *out of the
guide pages this PR creates*, into `docs/lessons.md`. Writing line-level steps
for that before those pages exist would mean planning against text whose final
position is not yet known. Its plan gets written after PR A merges, covering:

1. The three incidents out of `docs/guide/install.md` and `docs/guide/config.md`
   into `docs/lessons.md` — the 0.5.0 rename history into the existing migration
   lesson, the 0.4.2 incident into the derived-state lesson, and the 2026-08-25
   plugin cache as a new lesson about a copy that goes stale in silence.
2. The same in `docs/lessons.ru.md`, re-stamped.
3. The "Behind it" parent page, generated by filtering the page table on
   `parent` exactly as the Russian hub already is, with `memory-model` and
   `lessons` moved under it.
