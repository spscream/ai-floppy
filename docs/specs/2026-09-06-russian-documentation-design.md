# Russian documentation: design

Written 2026-09-06 against 0.19.0. Decided with the owner in the session that
opened after 0.19.0 shipped; the questions it answers were left open in
`docs/statuses/NOW.md` under "Open, waiting on the owner".

This document is in English because every other document in this repository is,
and because the language of a document, the language of the memory, and the
language of a reply to a human are three separate choices — the same rule
`agent-memory` states and warns a future session against wiring together.

## What was decided

Four decisions, taken by the owner, that everything below follows from:

1. **Which surfaces get Russian:** `README.md` and `docs/`. Not `CHANGELOG.md`,
   not `knowledge/`, not `skills/*/SKILL.md`. The last one matters most: those
   files are read by a model, and their wording is behaviour rather than
   readability.
2. **Two languages side by side, English is the source.** This is a public
   plugin; replacing English narrows its audience.
3. **Staleness must be detectable**, in the shape this repository already built
   for `knowledge/` — a record of what a document was made against, and a
   script that reports drift.
4. **The check reports and never fails.** A gate on freshness would turn every
   typo fix in `README.md` into bilingual work, and would teach whoever is in a
   hurry to bump the record without re-reading the source. That is the exact
   failure the frozen decision on `metadata.as_of` names.

## Non-goals

- **Not a released plugin feature.** The script below ships, in the sense that
  everything under `scripts/` ships, and it is written language-agnostic so it
  is not the first place a specific language leaks into the plugin. But it is
  not documented in `README.md` as a capability, `init.sh` does not write
  anything for it, and no config key governs it. It is machinery for this
  repository's own documents. Presenting it as a feature is a separate decision
  with its own scope.
- **No third language.** The layout below is chosen for two. If a third is ever
  wanted, the suffix scheme still works, but the site navigation would want
  revisiting.
- **`docs/statuses/NOW.md` is not translated.** It is the project's working
  state, and `memory_language` already settles its language as `en`.

## Layout

Translations are siblings of their sources, distinguished by a language suffix:

| source | translation |
|---|---|
| `README.md` | `README.ru.md` |
| `docs/memory-model.md` | `docs/memory-model.ru.md` |
| `docs/lessons.md` | `docs/lessons.ru.md` |

**Why siblings and not `docs/ru/`.** `tests/test-site.sh` already iterates
`for src in docs/*.md` and asserts that every one of them reaches the site. A
suffixed sibling falls into that loop by itself, so a translated document with
no page fails an existing test. Files under `docs/ru/` would not be seen by
that glob at all, and the guard would quietly stop guarding anything new — the
"what stays green if this is not wired?" failure this repository keeps finding.

The cost is that the scheme does not scale past a few languages and that the
repository root carries one more file. Both are acceptable at two languages.

## The marker

Line 1 of every translated file, flat `key=value` pairs in the same style as
`.floppy/config`:

```
<!-- floppy:translation of=docs/lessons.md blob=<40 hex> on=2026-09-06 -->
```

An HTML comment, so it is invisible both on GitHub and on the built site, and
`scripts/site-build.sh` strips the line from the page anyway. The record travels
with the file rather than living in a manifest: a manifest can name a file that
no longer exists and drift from the tree silently, and a marker cannot.

Fields:

- `of` — the source path, repository-relative. Redundant with the file name by
  construction, and checked against it: a disagreement is a contract problem,
  not a fallback.
- `blob` — the **git blob sha of the source** as it stood when the translation
  was made. Not a sha256, and the difference is the point: a blob sha is a
  pointer into git history, so "what changed since this was translated" has an
  answer. It is a pure function of content — `sha1("blob " + len + "\0" + bytes)`
  — so the check computes it with `hashlib` and needs no git at all.
- `on` — the ISO date the translation was made or last re-checked. Reported,
  never gated, for the reasons in decision 4 above.

**Reading the drift.** When a translation is behind, the check prints the
recipe rather than running it:

```
git cat-file blob <blob> | diff - docs/lessons.md
```

The same habit as `commit` printing the push recipe on a protected branch.
If the object is missing from the local database — a shallow clone, a rewritten
history — the recipe fails, and the check itself is unaffected: it compares
hashes and computes the working file's hash locally.

## The site

`scripts/site-build.sh` gains a fifth field in its page table, the parent:

```
README.md|index.md|Home|1
docs/memory-model.md|memory-model.md|The memory model|2
docs/lessons.md|lessons.md|Lessons|3
|knowledge.md|The knowledge base|4
|skills.md|The five skills|5
CHANGELOG.md|changelog.md|Changelog|6
|ru.md|Русский|7
README.ru.md|ru-index.md|floppy по-русски|1|Русский
docs/memory-model.ru.md|ru-memory-model.md|Модель памяти|2|Русский
docs/lessons.ru.md|ru-lessons.md|Уроки|3|Русский
```

Existing rows need no trailing separator: `read -r src tgt title order parent`
leaves `parent` empty when a row has four fields. The rewrite loop's positional
throwaways gain a fifth so the order field is not handed the remainder.

`emit` takes two more optional arguments, parent and has-children, and writes
`parent:` and `has_children: true` into the front matter when they are given.

The hub page `ru.md` has no source and is generated, the same way `skills.md`
and `knowledge.md` are: a few sentences of Russian derived from the table, and
the list of Russian pages. Nothing on the site is authored twice.

The rewrite array gains one deletion rule, `/^<!-- floppy:translation /d`, so
no page carries a marker.

**Link rewriting needs no special case.** The rules are derived from the table,
so `README.ru.md` and `docs/lessons.ru.md` get theirs like any other source.
The patterns do not collide: `](lessons.md)` is not a substring of
`](lessons.ru.md)`, in either direction. This is what lets each document carry a
one-line link to its counterpart — "Русская версия" and "In English" — without
the existing assert about links that leave the site coming true.

## Two changes to existing tests

Both are in `tests/test-site.sh`, and both are named here because weakening a
test in this repository is a deliberate act.

1. **`nav_order` uniqueness becomes per-parent.** The assert is currently global
   across every page. Once pages have children that is the wrong invariant:
   just-the-docs orders children within their parent, so the Russian pages'
   1-2-3 legitimately repeats the top level's. The assert becomes uniqueness
   within each `(parent, nav_order)` group — the same guard on the correct
   group, not a removed one.

2. **"every document reaches the site" matches the first `^# ` heading**, not
   `head -1`. A translation's first line is the marker, and the marker is
   stripped from the page, so the current form would fail on a correct file.
   Matching the first heading is also more accurate for the English documents
   it already covers.

New asserts in the same file: each Russian page carries `parent: Русский`, the
hub carries `has_children: true`, and no page carries a translation marker.
`ru-index.md` is asserted to carry `quota.lock` — a code identifier survives
translation, so it is a stable probe that the whole README came through. It is
the same role the heading `quota.lock` already plays for `index.md`, where the
existing assert uses it to prove the README arrived whole rather than truncated.

## The check

`scripts/translation-check.py`, modelled on `scripts/knowledge-rot-check.py`:
no third-party dependencies, runs under the system python3 on macOS, `--json`,
and **it never exits non-zero**.

- **Pairs are discovered, not listed.** Any `*.<lang>.md` where `<lang>` is two
  letters is a translation; the source is the path with the suffix removed.
  Discovery keeps the language out of the code: `ru` appears nowhere in it.
- **Three reports**, in the shape rot-check already uses:
  `-- contract problems` (marker absent, unparseable, `of` disagreeing with the
  file name, `blob` not 40 hex, `on` not an ISO date), `-- behind the source`
  (recorded blob differs from the source's current blob, with the diff recipe),
  and `-- untranslated` (a source document in the set with no counterpart).
- **The set of source documents** is `README.md` plus `docs/*.md`, excluding
  translations, excluding subdirectories. `CHANGELOG.md` is excluded by
  decision 1 and the exclusion carries that reason in a comment, so a later
  reader does not read it as an oversight.
- **`--stamp <translation>`** rewrites the marker to the source's current blob
  and today's date, and prints the diff recipe in its output. Stamping is a
  deliberate act that should be preceded by reading what changed; printing the
  recipe is what keeps the affordance honest.

## Where the report surfaces

One section in `scripts/workstatus.sh`, behind `--flow`, printed **only when at
least one `*.<lang>.md` exists**. The same conditional habit as the worktree
line a few lines above it, and for the same reason: in a consumer's repository
with no translations, an empty section is noise about a feature they do not use.

## The structural test

`tests/test-translations.sh`, structural in the style of `test-docs.sh`:

- every `*.<lang>.md` has a parseable marker on line 1;
- its `of` names an existing file, and that file is the suffix-stripped sibling;
- `blob` is 40 hex characters; `on` is an ISO date no more than one day in the
  future — the same day of slack already frozen for `metadata.as_of`, which
  exists because an evening at UTC+3 is tomorrow for the runners;
- **the report-only contract holds on the path, not in the module**: the test
  builds a deliberately stale translation in a sandbox, runs the script, and
  asserts both that it exited 0 and that it named that file. A test that only
  called the audit function would pass just as well if the script were wired to
  fail the run.

It never asserts the freshness of the real files. That is the whole point of
decision 4, and a structural test that drifted into checking it would be the
gate arriving by the back door.

## Order of work

Three pull requests, since `main` is protected and refuses a direct push:

1. **Machinery plus `docs/memory-model.ru.md`.** The smallest document (150
   lines) is the cheapest way to run the entire path end to end — marker, page,
   navigation, check, test.
2. **`docs/lessons.ru.md`** (209 lines).
3. **`README.ru.md`** (491 lines), the largest and the landing page.

The translation itself stays with a model chosen for judgement rather than
throughput: the voice of these documents is a decision per paragraph, not
mechanical substitution.

## Known unknown

How just-the-docs indexes Cyrillic headings for search. `site/_config.yml` sets
`tokenizer_separator: /[\s/]+/`, which was chosen for Latin text and paths. If
search over the Russian pages turns out broken, it is a one-line change in that
file. Measured on the first pull request, where a Russian page exists for the
first time — not guessed here.
