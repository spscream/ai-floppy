# Russian documentation, PR 1 — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Land the machinery that makes an outdated Russian translation visible,
proven end to end by translating the smallest document.

**Architecture:** Translations are siblings with a language suffix
(`docs/memory-model.ru.md`). Line 1 of each carries an HTML-comment marker
recording the git blob sha of the source it was made from. A dependency-free
python script recomputes that sha and reports drift; it never fails a run. The
site build learns about parent pages so the Russian pages sit under one
navigation group.

**Tech Stack:** bash 3.2, python3 standard library, Jekyll + just-the-docs.

**Spec:** `docs/specs/2026-09-06-russian-documentation-design.md`

## Global Constraints

- **bash 3.2.57.** The macOS CI job runs `/bin/bash` 3.2.57. No associative
  arrays (`declare -A`), no `mapfile`, no `${var^^}`. Verify locally with
  `bash tests/run.sh <fragment>`.
- **python3 standard library only.** No third-party imports. Must run under the
  system python3 on macOS.
- **The check never exits non-zero.** Frozen decision: a gate on freshness turns
  every typo fix into bilingual work and teaches whoever is in a hurry to bump
  the record without re-reading the source.
- **`ru` appears nowhere in `scripts/translation-check.py`.** The language is
  discovered from file names. This script is the first place a specific language
  could leak into the plugin, and it must not.
- **No AI attribution in commit messages.** The message is the description of
  the change and nothing else.
- **The whole suite must stay green:** `bash tests/run.sh`. It is 689 assertions
  before this work starts.
- **Everything lands on the existing local branch `russian-docs-design`.** It is
  not pushed; the pull request opens when this plan is finished.

## Out of scope for this pull request

Named here so their absence does not read as a gap against the spec. Each is one
table row and one document:

- `README.ru.md` and its `ru-index.md` page, with the spec's `quota.lock`
  assertion proving the whole README came through — PR 3.
- `docs/lessons.ru.md` and its `ru-lessons.md` page — PR 2.

---

### Task 1: The check script and its positive controls

**Files:**
- Create: `scripts/translation-check.py`
- Create: `tests/test-translations.sh`

**Interfaces:**
- Consumes: nothing from earlier tasks.
- Produces:
  - `python3 scripts/translation-check.py [--root DIR] [--json] [--stamp PATH]`,
    always exit code 0. `--root` defaults to the repository the script lives in;
    `--stamp` takes a path relative to the root.
  - Marker grammar, relied on by Tasks 2, 3 and 4:
    `<!-- floppy:translation of=<source path> blob=<40 hex> on=<ISO date> -->`
    on line 1 of a translation.
  - Report headings, matched literally by tests: `-- contract problems`,
    `-- behind the source`, `-- untranslated`, and the clean line
    `clean: every translation names its source and matches it.`

**Why `--root` exists**, when `knowledge-rot-check.py` has no equivalent: the
knowledge checkers are tested by planting probe files in the real repository.
The same trick here would plant a file in `docs/`, and `tests/test-site.sh`
requires a site page for every `docs/*.md` — the two files run in parallel under
`tests/run.sh`, so the probe would fail an unrelated test at random. `--root`
also turns out to be required in Task 4: in a consumer's repository the script
lives in the plugin cache and the documents do not.

- [ ] **Step 1: Write the failing test**

Create `tests/test-translations.sh`:

```bash
#!/usr/bin/env bash
# Translations keep their contract, and the checker can go red.
#
# Structural, like test-docs.sh and test-knowledge.sh: nothing here asserts what
# a translation says, only that the machinery around it works. The positive
# controls are the point of the file — a checker that cannot report a problem is
# indistinguishable from one that was never wired up.
#
# What this file must NEVER assert: that the translations in this repository are
# up to date. Freshness is reported and never gated (see the spec, decision 4),
# and a structural test that drifted into checking it would be that gate
# arriving by the back door.
set -uo pipefail
cd "$(dirname "$0")/.."
. tests/lib.sh

py=python3
command -v "$py" >/dev/null 2>&1 || { printf '  skip python3 not available\n'; exit 0; }

sb="$(cd "$(mktemp -d)" && pwd -P)"
trap 'rm -rf "$sb"' EXIT
mkdir -p "$sb/docs"
printf '# Home\n\nbody\n'    > "$sb/README.md"
printf '# Lessons\n\nbody\n' > "$sb/docs/lessons.md"

marker() { # blob date  -> a translation file with that marker
  printf '<!-- floppy:translation of=docs/lessons.md blob=%s on=%s -->\n\n# Уроки\n\ntext\n' \
    "$1" "$2" > "$sb/docs/lessons.ru.md"
}

# ---------- 1. a translation behind its source is reported, and the run is green ----------
# Zeroes are a blob sha no content produces, so this is "behind" by construction.
marker 0000000000000000000000000000000000000000 2026-01-01
out="$("$py" scripts/translation-check.py --root "$sb" 2>&1)"; rc=$?
assert_rc "the check exits 0 even when a translation is behind" 0 "$rc"
assert_contains "and it reports the drift"        "behind the source"    "$out"
assert_contains "and names the translation"       "docs/lessons.ru.md"   "$out"
assert_contains "and prints the diff recipe"      "git cat-file blob"    "$out"
assert_contains "and names the untranslated doc"  "README.md"            "$out"

# ---------- 2. --stamp records the sha git itself would ----------
# The identity the whole design rests on: the recorded value is a git blob sha,
# so it is a pointer into history and `git cat-file` can resolve it. Asserted
# against git's own answer, not against a second copy of our implementation.
"$py" scripts/translation-check.py --root "$sb" --stamp docs/lessons.ru.md >/dev/null 2>&1
stamped="$(sed -n '1s/.*blob=\([0-9a-f]*\).*/\1/p' "$sb/docs/lessons.ru.md")"
assert_eq "--stamp records the blob sha git computes" \
  "$(git hash-object "$sb/docs/lessons.md")" "$stamped"

out2="$("$py" scripts/translation-check.py --root "$sb" 2>&1)"
case "$out2" in
  *"behind the source"*) fail "a stamped translation is not reported as behind" "no drift" "$out2" ;;
  *) ok "a stamped translation is not reported as behind" ;;
esac

# ---------- 3. positive controls: each contract problem is caught ----------
rm -f "$sb/docs/lessons.ru.md"
printf '# Уроки\n\ntext\n' > "$sb/docs/lessons.ru.md"
out3="$("$py" scripts/translation-check.py --root "$sb" 2>&1)"
assert_contains "a file shaped like a translation with no marker is caught" \
  "no floppy:translation marker" "$out3"

marker deadbeef 2026-09-06
out4="$("$py" scripts/translation-check.py --root "$sb" 2>&1)"
assert_contains "a blob that is not 40 hex is caught" "is not a git blob sha" "$out4"

marker "$(git hash-object "$sb/docs/lessons.md")" not-a-date
out5="$("$py" scripts/translation-check.py --root "$sb" 2>&1)"
assert_contains "a non-ISO date is caught" "not an ISO date" "$out5"

# One day of slack, not politeness: an evening at UTC+3 is already tomorrow for
# the runners. The same rule is frozen for metadata.as_of.
marker "$(git hash-object "$sb/docs/lessons.md")" 2099-01-01
out6="$("$py" scripts/translation-check.py --root "$sb" 2>&1)"
assert_contains "a date far in the future is caught" "in the future" "$out6"

printf '<!-- floppy:translation of=docs/nope.md blob=%s on=2026-09-06 -->\n\n# Уроки\n' \
  "$(git hash-object "$sb/docs/lessons.md")" > "$sb/docs/lessons.ru.md"
out7="$("$py" scripts/translation-check.py --root "$sb" 2>&1)"
assert_contains "an \`of\` that disagrees with the file name is caught" \
  "does not name its sibling" "$out7"

# ---------- 4. the script runs on this repository ----------
real="$("$py" scripts/translation-check.py 2>&1)"; real_rc=$?
assert_rc "the check exits 0 on this repository" 0 "$real_rc"

summary
```

- [ ] **Step 2: Run it to make sure it fails**

Run: `bash tests/run.sh translations`
Expected: FAIL — every assertion, because `scripts/translation-check.py` does
not exist yet and python3 reports `can't open file`.

- [ ] **Step 3: Write the script**

Create `scripts/translation-check.py`:

```python
#!/usr/bin/env python3
"""Report translations that have fallen behind their source, or break the contract.

    python3 scripts/translation-check.py
    python3 scripts/translation-check.py --json
    python3 scripts/translation-check.py --stamp docs/memory-model.ru.md

It REPORTS. It never fails the run, and that is deliberate: gating on freshness
would turn every typo fix in an English document into bilingual work, and would
teach whoever is in a hurry to bump the record without re-reading the source —
destroying the only signal the record carries. The same reasoning is frozen for
`metadata.as_of` in the memory linter.

The language is never named here. A translation is discovered by its file name
(`<stem>.<two letters>.md`) and confirmed by its marker, so this file does not
become the first place a specific language leaks into the plugin.

No third-party dependencies on purpose — this has to run on a fresh machine and
on macOS with the system python3.
"""

import argparse
import datetime as dt
import hashlib
import json
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

# `<stem>.<lang>.md`. The shape is the candidate filter; the marker below is the
# confirmation. A file matching the shape without a marker is reported rather
# than ignored — silently ignoring it is how a translation whose marker was lost
# disappears from the report.
TRANSLATION_NAME = re.compile(r"^(?P<stem>.+)\.(?P<lang>[a-z]{2})\.md$")
MARKER = re.compile(r"^<!--\s*floppy:translation\s+(?P<fields>.*?)\s*-->\s*$")
FIELD = re.compile(r"(\w+)=(\S+)")
BLOB = re.compile(r"^[0-9a-f]{40}$")

# CHANGELOG.md is deliberately absent: the owner scoped the translation to
# README.md and docs/ (spec, decision 1). Without this comment a later reader
# would read the omission as an oversight and "fix" it.
SOURCE_ROOTS = ("README.md", "docs")

# An evening at UTC+3 is already tomorrow for the runners. One day of slack, and
# the same rule the memory linter freezes for `metadata.as_of`.
FUTURE_SLACK_DAYS = 1


def blob_sha(data):
    """The git blob sha of these bytes — a pure function of content, no git needed.

    Recorded instead of a plain sha256 because it is a pointer into history:
    `git cat-file blob <sha>` resolves it, so "what changed since this was
    translated" has an answer.
    """
    header = ("blob %d\0" % len(data)).encode()
    return hashlib.sha1(header + data).hexdigest()


def read_bytes(path):
    with open(path, "rb") as fh:
        return fh.read()


def sources(root):
    """The English documents that should have a translation."""
    out = []
    readme = os.path.join(root, "README.md")
    if os.path.isfile(readme):
        out.append("README.md")
    docs = os.path.join(root, "docs")
    if os.path.isdir(docs):
        for fn in sorted(os.listdir(docs)):
            # Subdirectories are skipped: docs/statuses/ is the project's working
            # state and docs/specs/ and docs/plans/ are design records.
            if not fn.endswith(".md") or TRANSLATION_NAME.match(fn):
                continue
            out.append(os.path.join("docs", fn))
    return out


def translations(root):
    """Every file whose name is shaped like a translation, in the same two places."""
    out = []
    for fn in sorted(os.listdir(root)):
        if TRANSLATION_NAME.match(fn) and fn.endswith(".md"):
            out.append(fn)
    docs = os.path.join(root, "docs")
    if os.path.isdir(docs):
        for fn in sorted(os.listdir(docs)):
            if TRANSLATION_NAME.match(fn):
                out.append(os.path.join("docs", fn))
    return out


def parse_marker(text):
    line = text.split("\n", 1)[0]
    m = MARKER.match(line)
    if not m:
        return None
    return dict(FIELD.findall(m.group("fields")))


def sibling_source(rel):
    """`docs/lessons.ru.md` -> `docs/lessons.md`."""
    name = os.path.basename(rel)
    m = TRANSLATION_NAME.match(name)
    return os.path.join(os.path.dirname(rel), m.group("stem") + ".md")


def audit(root):
    today = dt.date.today()
    broken, behind = [], []
    translated_sources = set()

    for rel in translations(root):
        path = os.path.join(root, rel)
        problems = []
        front = parse_marker(read_bytes(path).decode("utf-8", "replace"))

        if front is None:
            broken.append({"path": rel, "problems": ["no floppy:translation marker on line 1"]})
            continue

        expected_source = sibling_source(rel)
        source = front.get("of", "")
        if source != expected_source:
            problems.append(
                "`of` is `%s` — it does not name its sibling `%s`" % (source, expected_source)
            )
        translated_sources.add(source)

        recorded = front.get("blob", "")
        if not BLOB.match(recorded):
            problems.append("`blob` is `%s` — that is not a git blob sha" % recorded)

        raw = front.get("on", "")
        try:
            made = dt.date.fromisoformat(raw)
        except ValueError:
            problems.append("`on` is not an ISO date: %r" % raw)
        else:
            if (made - today).days > FUTURE_SLACK_DAYS:
                problems.append("`on` is in the future (%s)" % raw)

        source_path = os.path.join(root, source)
        if not os.path.isfile(source_path):
            problems.append("`of` names `%s`, which does not exist" % source)
        elif BLOB.match(recorded):
            current = blob_sha(read_bytes(source_path))
            if current != recorded:
                behind.append(
                    {"path": rel, "source": source, "recorded": recorded,
                     "current": current, "on": raw}
                )

        if problems:
            broken.append({"path": rel, "problems": problems})

    untranslated = [s for s in sources(root) if s not in translated_sources]
    return broken, behind, untranslated


def stamp(root, rel):
    """Rewrite a translation's marker to the source's current blob and today's date."""
    path = os.path.join(root, rel)
    text = read_bytes(path).decode("utf-8")
    previous = parse_marker(text)
    source = sibling_source(rel)
    current = blob_sha(read_bytes(os.path.join(root, source)))
    line = "<!-- floppy:translation of=%s blob=%s on=%s -->" % (
        source, current, dt.date.today().isoformat()
    )
    rest = text.split("\n", 1)[1] if previous else text
    with open(path, "w", encoding="utf-8") as fh:
        fh.write(line + "\n" + rest)
    print("stamped %s against %s (%s)" % (rel, source, current))
    if previous and BLOB.match(previous.get("blob", "")):
        # Printed on success, not only on failure: stamping without reading what
        # changed is the failure this whole arrangement exists to make visible,
        # and the affordance should not be quieter than the thing it can hide.
        print("what changed since the previous stamp:")
        print("  git cat-file blob %s | diff - %s" % (previous["blob"], source))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--root", default=ROOT, help="repository to check, default: this one")
    ap.add_argument("--json", action="store_true")
    ap.add_argument("--stamp", metavar="PATH", help="re-record a translation against its source")
    args = ap.parse_args()

    if args.stamp:
        stamp(args.root, args.stamp)
        return

    broken, behind, untranslated = audit(args.root)

    if args.json:
        json.dump(
            {"broken": broken, "behind": behind, "untranslated": untranslated},
            sys.stdout, ensure_ascii=False, indent=2,
        )
        print()
        return

    if broken:
        print("-- contract problems (%d)" % len(broken))
        for item in broken:
            print("  %s" % item["path"])
            for problem in item["problems"]:
                print("      %s" % problem)
        print()

    if behind:
        print("-- behind the source (%d)" % len(behind))
        print("   The source changed after the translation was made. Read what changed,")
        print("   bring the translation up to it, then re-stamp.\n")
        for item in behind:
            print("  %s  (stamped %s against %s)" % (item["path"], item["on"], item["recorded"][:12]))
            print("      git cat-file blob %s | diff - %s" % (item["recorded"], item["source"]))
            print("      then: python3 scripts/translation-check.py --stamp %s" % item["path"])
        print()

    if untranslated:
        print("-- untranslated (%d)" % len(untranslated))
        for path in untranslated:
            print("  %s" % path)
        print()

    if not broken and not behind and not untranslated:
        print("clean: every translation names its source and matches it.")


if __name__ == "__main__":
    main()
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `bash tests/run.sh translations`
Expected: PASS, 0 failed.

- [ ] **Step 5: Run the whole suite**

Run: `bash tests/run.sh`
Expected: 0 failed. Nothing else reads these files yet, so a failure here means
the new test file itself broke something — most likely by leaving a file behind.

- [ ] **Step 6: Commit**

```bash
git add scripts/translation-check.py tests/test-translations.sh
git commit -m "a translation can say which version of its source it was made from"
```

---

### Task 2: Translate the memory model, and guard the real corpus

**Files:**
- Create: `docs/memory-model.ru.md`
- Modify: `docs/memory-model.md` (one line added under the H1)
- Modify: `tests/test-translations.sh` (append before `summary`)

**Interfaces:**
- Consumes: the marker grammar and `--stamp` from Task 1.
- Produces: `docs/memory-model.ru.md`, the first real translation. Task 3's page
  table row depends on this file existing — the site build fails loudly on a
  missing source, which is the correct behaviour and the reason for this order.

**Order matters inside this task.** The cross-link is added to
`docs/memory-model.md` *before* the translation is stamped. Stamping first and
editing the English file afterwards leaves the translation behind by one line
the moment it is committed.

- [ ] **Step 1: Add the cross-link to the English document**

In `docs/memory-model.md`, immediately after the H1 line
`# The memory model: two namespaces, two axes`, insert a blank line and:

```markdown
*[Русская версия](memory-model.ru.md)*
```

The bare file name, not `docs/memory-model.ru.md`: the document links to its
sibling the way `docs/lessons.md` already links to `memory-model.md`, and
`site-build.sh` rewrites both spellings.

- [ ] **Step 2: Write the translation**

Create `docs/memory-model.ru.md`. Line 1 is a placeholder marker — Step 4
replaces it with the real one:

```markdown
<!-- floppy:translation of=docs/memory-model.md blob=0000000000000000000000000000000000000000 on=2026-01-01 -->

# Модель памяти: два пространства имён, две оси

*[In English](memory-model.md)*

...
```

Translate all 150 lines of `docs/memory-model.md`, including the table. Rules:

- **Code identifiers, paths and file names are never translated** —
  `memory-store.sh`, `projects/<key>`, `workplaces/`, `machines/`,
  `quota.lock`. They are what the reader will type.
- **Keep the heading structure identical.** Same number of headings, same
  nesting, same order. The site's search index and every cross-reference depend
  on it, and a reader comparing the two languages should not have to hunt.
- **Keep the dates and version numbers exactly as they are.** They are claims
  about when something was measured, not prose.
- **Markdown links keep their targets**, only the link text is translated.

- [ ] **Step 3: Verify the check sees it as behind**

Run: `python3 scripts/translation-check.py`
Expected: `-- behind the source (1)` naming `docs/memory-model.ru.md`, because
the marker still holds the placeholder blob. This is the positive control on the
real file: if it prints anything else, the marker is malformed and the report
will say which field.

- [ ] **Step 4: Stamp it**

```bash
python3 scripts/translation-check.py --stamp docs/memory-model.ru.md
python3 scripts/translation-check.py
```
Expected from the second command: `-- untranslated (2)` listing `README.md` and
`docs/lessons.md`, and no `behind` or `contract problems` section. Those two are
the honest state until PRs 2 and 3.

- [ ] **Step 5: Add the real-corpus assertions to the test**

Append to `tests/test-translations.sh`, immediately before the final
`summary` line:

```bash
# ---------- 5. the real corpus keeps the contract ----------
# The loop below is worthless if it iterates over nothing — the empty-loop trap
# this repository has already paid for twice. So the count is asserted first.
real_n="$(ls docs/*.*.md README.*.md 2>/dev/null | wc -l | tr -d ' ')"
assert_eq "there is at least one translation to check" "0" \
  "$([[ "$real_n" -ge 1 ]] && echo 0 || echo 1)"

for f in docs/*.*.md README.*.md; do
  [[ -f "$f" ]] || continue
  line1="$(head -1 "$f")"
  assert_contains "$f carries a marker on line 1" "floppy:translation" "$line1"
  src="$(printf '%s' "$line1" | sed -n 's/.*of=\([^ ]*\).*/\1/p')"
  assert_eq "$f names a source that exists" "0" \
    "$([[ -f "$src" ]] && echo 0 || echo 1)"
  sha="$(printf '%s' "$line1" | sed -n 's/.*blob=\([0-9a-f]*\).*/\1/p')"
  assert_eq "$f records a 40-character blob sha" "40" "${#sha}"
done

# Deliberately absent: any assertion that these files are up to date. See the
# header of this file.
```

- [ ] **Step 6: Run the tests**

Run: `bash tests/run.sh translations`
Expected: PASS, 0 failed.

- [ ] **Step 7: Commit**

```bash
git add docs/memory-model.md docs/memory-model.ru.md tests/test-translations.sh
git commit -m "the memory model, in Russian, stamped against the version it was made from"
```

---

### Task 3: The site carries the Russian pages under one navigation group

**Files:**
- Modify: `scripts/site-build.sh` (page table, both read loops, `emit`, rewrite
  array, one new generated page)
- Modify: `tests/test-site.sh` (two existing assertions, four new ones)

**Interfaces:**
- Consumes: `docs/memory-model.ru.md` from Task 2, and the marker grammar from
  Task 1 (the build strips the marker line).
- Produces: the page table's fifth field, `parent`, and the pages `ru.md` and
  `ru-memory-model.md`. PRs 2 and 3 add one table row each; nothing else in the
  build changes for them.

- [ ] **Step 1: Write the failing test**

In `tests/test-site.sh`, replace the `nav_order` uniqueness assertion (the block
ending `assert_eq "nav_order values are unique" ...`) with:

```bash
# Uniqueness is per parent, not global. That changed when pages got children:
# just-the-docs orders children within their parent, so the Russian pages'
# 1-2-3 legitimately repeats the top level's. Same guard, correct group.
dupes="$(for page in "$out"/*.md; do
  p="$(awk -F': ' '/^parent: /{print $2; exit}' "$page")"
  n="$(awk -F': ' '/^nav_order: /{print $2; exit}' "$page")"
  printf '%s\t%s\n' "${p:-<top level>}" "$n"
done | sort | uniq -d | tr '\n' ' ' | sed 's/ *$//')"
assert_eq "nav_order values are unique within each parent" "" "$dupes"
```

Replace the "every document reaches the site" loop's first line
(`h1="$(head -1 "$src")"`) with:

```bash
  # The first heading, not the first line: a translation's first line is the
  # marker, and the marker is stripped from the page.
  h1="$(grep -m1 '^# ' "$src")"
```

And append, immediately before `summary`:

```bash
# ---------- the Russian pages sit under one navigation group ----------
hub="$(cat "$out/ru.md" 2>/dev/null || true)"
assert_contains "the Russian hub exists"            "title: Русский"    "$hub"
assert_contains "and declares itself a parent"      "has_children: true" "$hub"
assert_contains "and links to the Russian page"     "ru-memory-model.html" "$hub"
assert_contains "the Russian page names its parent" "parent: Русский" \
  "$(cat "$out/ru-memory-model.md" 2>/dev/null || true)"

# The marker is an implementation detail of the repository, not of the site.
assert_eq "no page carries a translation marker" "" \
  "$(grep -l 'floppy:translation' "$out"/*.md 2>/dev/null | tr '\n' ' ' | sed 's/ *$//')"
```

- [ ] **Step 2: Run it to make sure it fails**

Run: `bash tests/run.sh site`
Expected: FAIL — `the Russian hub exists`, `and declares itself a parent`,
`and links to the Russian page` and `the Russian page names its parent` all fail
because those pages are not built yet. The two rewritten assertions should
already pass.

- [ ] **Step 3: Add the parent field to the page table**

In `scripts/site-build.sh`, replace the `pages='...'` block with:

```bash
pages='README.md|index.md|Home|1
docs/memory-model.md|memory-model.md|The memory model|2
docs/lessons.md|lessons.md|Lessons|3
|knowledge.md|The knowledge base|4
|skills.md|The five skills|5
CHANGELOG.md|changelog.md|Changelog|6
|ru.md|Русский|7
docs/memory-model.ru.md|ru-memory-model.md|Модель памяти|2|Русский'
```

Existing rows need no trailing separator: `read -r ... order parent` leaves
`parent` empty when a row has four fields.

- [ ] **Step 4: Widen both read loops and `emit`**

Change the rewrite loop's header from
`while IFS='|' read -r src tgt _title _order; do` to:

```bash
while IFS='|' read -r src tgt _title _order _parent; do
```

Change the copy loop's header from
`while IFS='|' read -r src tgt title order; do` to:

```bash
while IFS='|' read -r src tgt title order parent; do
```

and its `emit` call to `emit "$tgt" "$title" "$order" "$parent"`.

Replace `emit` with:

```bash
emit() { # target title nav_order [parent] [has_children]  — body on stdin
  {
    printf -- '---\nlayout: default\ntitle: %s\nnav_order: %s\n' "$2" "$3"
    [[ -n "${4:-}" ]] && printf 'parent: %s\n' "$4"
    [[ -n "${5:-}" ]] && printf 'has_children: true\n'
    printf -- '---\n\n'
    sed -E "${rewrite[@]}"
  } > "$out/$1"
}
```

- [ ] **Step 5: Strip the marker from every page**

After the last `rewrite+=(...)` line, add:

```bash
# The marker records which version of the English file a translation was made
# from. That is a fact about the repository, and it has no business on a page.
rewrite+=(-e '/^<!-- floppy:translation /d')
```

- [ ] **Step 6: Generate the hub page**

After the knowledge base block, before the final `printf '\nsite assembled...'`,
add:

```bash
# ---------- the Russian hub ----------
# Generated from the table for the same reason every other page is: a
# hand-written list of the Russian pages would be a second copy of the table,
# and the two would differ the first time a page was added.
{
  printf '# Русский\n\n'
  printf 'Документация floppy на русском языке. Английские файлы в репозитории —\n'
  printf 'источник: перевод сделан от конкретной их версии и помнит, от какой.\n'
  printf 'Если источник ушёл вперёд, это видно `scripts/translation-check.py`.\n\n'
  while IFS='|' read -r _src tgt title _order parent; do
    [[ "$parent" == "Русский" ]] || continue
    printf -- '- [%s](%s)\n' "$title" "${tgt%.md}.html"
  done <<EOF
$pages
EOF
} | emit ru.md "Русский" 7 "" 1
printf 'ok the page table -> ru.md\n'
```

- [ ] **Step 7: Run the site test**

Run: `bash tests/run.sh site`
Expected: PASS, 0 failed.

- [ ] **Step 8: Build the site and look at the Cyrillic search index**

```bash
bash scripts/site-build.sh /tmp/floppy-site
grep -c 'Модель памяти' /tmp/floppy-site/ru-memory-model.md
```
Expected: at least 1. This is the known unknown from the spec — if the
just-the-docs search over Cyrillic headings turns out broken when the site is
served, the fix is `tokenizer_separator` in `site/_config.yml`. Record what you
observe; do not guess at a fix that has not been measured.

- [ ] **Step 9: Run the whole suite**

Run: `bash tests/run.sh`
Expected: 0 failed.

- [ ] **Step 10: Commit**

```bash
git add scripts/site-build.sh tests/test-site.sh
git commit -m "the site groups the Russian pages under one parent, generated from the table"
```

---

### Task 4: The status reports drift, and only where there is any

**Files:**
- Modify: `scripts/workstatus.sh` (one block inside the `if [[ $FLOW -eq 1 ]]`
  section, after `process: memory`)
- Modify: `tests/test-workstatus.sh` (append before `summary`)

**Interfaces:**
- Consumes: `python3 scripts/translation-check.py --root <repo>` from Task 1.
- Produces: a `-- process: translations` section in `bash .floppy/run status --flow`.

`$repo` and `$here` already exist in `workstatus.sh` (lines 26-28): `$here` is
the plugin's `scripts/` directory, `$repo` the repository being reported on.
Both are needed — in a consumer's repository the script and the documents are
not in the same tree.

- [ ] **Step 1: Write the failing test**

Append to `tests/test-workstatus.sh`, before `summary`. It reuses what the file
already has: `$repo` is the sandbox created on line 7 with the shim copied into
it, `$ROOT` points `AI_FLOPPY_HOME` at this checkout, and `$out6` on line 79 is
already a `--flow` run of that sandbox — which at that point has no
translations, so it is the negative control for free.

```bash
# ---------- translations ----------
# The negative control first, and it costs nothing: out6 is a --flow run of a
# sandbox with no translations in it. A consumer who never translated anything
# should not get an empty heading about a feature they do not use — the same
# rule the worktree line follows.
case "$out6" in
  *"process: translations"*) fail "no translations, no section" "no section" "$out6" ;;
  *) ok "no translations, no section" ;;
esac

# And the section appears once there is something to report. Built in the
# sandbox rather than read out of this repository, so the test says the wiring
# works rather than that this repository happens to contain a translation.
mkdir -p "$repo/docs"
printf '# Doc\n\nbody\n' > "$repo/docs/x.md"
printf '<!-- floppy:translation of=docs/x.md blob=%s on=2026-01-01 -->\n\n# Док\n' \
  0000000000000000000000000000000000000000 > "$repo/docs/x.ru.md"
out7="$(cd "$repo" && AI_FLOPPY_HOME="$ROOT" bash .floppy/run status --flow 2>&1)"
rm -f "$repo/docs/x.md" "$repo/docs/x.ru.md"
if command -v python3 >/dev/null 2>&1; then
  assert_contains "--flow prints the translations sub-section" "-- process: translations" "$out7"
  assert_contains "and names the translation that is behind"   "docs/x.ru.md"              "$out7"
else
  printf '  skip python3 not available\n'
fi
```

- [ ] **Step 2: Run it to make sure it fails**

Run: `bash tests/run.sh workstatus`
Expected: FAIL on `--flow prints the translations sub-section` and
`and names the translation that is behind`. The negative control passes — which
is exactly why it is not the only assertion here.

- [ ] **Step 3: Add the section**

In `scripts/workstatus.sh`, after the `process: memory` block (after the line
`echo "$lint_out" | grep -E '^  !' | sed 's/^ */  warning: /'`), insert:

```bash
  # Only where translations exist. In a repository with none this section would
  # be an empty heading about a feature nobody here uses — the same reasoning as
  # the worktree line below, which prints only when there is more than one.
  # --root is not optional: in a consumer's repository this script runs from the
  # plugin cache and the documents are somewhere else entirely.
  if [[ -n "$(ls "$repo"/docs/*.*.md "$repo"/README.*.md 2>/dev/null)" ]]; then
    hr "process: translations"
    if command -v python3 >/dev/null 2>&1; then
      tr_out="$(python3 "$here/translation-check.py" --root "$repo" 2>&1)"
      if [[ -n "$tr_out" ]]; then
        echo "$tr_out" | sed 's/^/  /'
      else
        echo "  clean"
      fi
    else
      echo "  python3 not available — skipped"
    fi
  fi
```

- [ ] **Step 4: Run the test**

Run: `bash tests/run.sh workstatus`
Expected: PASS, 0 failed.

- [ ] **Step 5: Look at the real output**

Run: `bash .floppy/run status --flow`
Expected: a `-- process: translations` section listing `README.md` and
`docs/lessons.md` as untranslated, and nothing behind or broken.

- [ ] **Step 6: Run the whole suite**

Run: `bash tests/run.sh`
Expected: 0 failed, and the assertion count is above the 689 this work started
from.

- [ ] **Step 7: Commit**

```bash
git add scripts/workstatus.sh tests/test-workstatus.sh
git commit -m "status names a translation that fell behind, where there are translations"
```

---

## Finishing

- [ ] **Update `docs/statuses/NOW.md`** — the "Open, waiting on the owner"
  section says the approach is undecided. It is decided now: point it at
  `docs/specs/2026-09-06-russian-documentation-design.md`, say that PR 1 landed
  the machinery and the first document, and that `README.md` and
  `docs/lessons.md` are the remaining two.

- [ ] **Do not open the pull request without asking.** The owner decided the
  branch stays local until the implementation is ready; opening it is their
  call, not this plan's.
