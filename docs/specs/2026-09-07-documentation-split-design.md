# Splitting the documentation by audience: design

Written 2026-09-07 against 0.19.0. Decided with the owner in the session that
merged #47, from an observation he made directly: `docs/lessons.md` sits in the
user-facing documentation, and a user has no use for it.

This document is in English for the reason the previous spec gives: the
language of a document, of the memory, and of a reply to a human are three
separate choices.

## The finding this starts from

The owner's observation is correct and the boundary is drawn on the wrong axis.
This repository already sorts documents by "useful to someone who uses floppy"
versus "useful to everyone" — that is the line between `docs/lessons.md` and
`knowledge/`. There is no line at all between **using** floppy and **working on**
it. All four lessons are about why floppy's own code is shaped the way it is:
the scope migration, the turn arithmetic of `wrap`, derived state versus a
config flag, a test that recomputes its own rule. A person installing the
plugin needs none of it.

The overload is larger than that file. Measured on 2026-09-07:

| document | chars | words |
|---|---|---|
| `README.md` | 26229 | 4302 |
| `README.ru.md` | 43672 | 3720 |
| `docs/lessons.md` | 11940 | 2023 |
| `docs/memory-model.md` | 8204 | 1273 |

Of `README.md`, **4915 characters — 18% — are archaeology**: "Two stale copies
that cause no error message" (2075, a post-mortem of a plugin cache measured
2026-08-25), "The scope names changed in 0.5.0" and "Two memory repositories on
one machine" (2840 together, a rename history and a step-by-step incident from
0.4.2). A further 3823 characters under `quota.lock` are roughly half reference
and half justification. So a reader who came to install a plugin reads other
people's incident reports before reaching the table of config keys.

Every one of those sections is two documents wedged together:

| section | the standing rule | the incident behind it |
|---|---|---|
| Two stale copies | `.floppy/run` is a copy; here is the refresh command | what the cache did on 2026-08-25 |
| Scope names changed in 0.5.0 | on an old layout the verb prints the `git mv` | four renames in one day |
| Two memory repositories | the checkout is derived from the URL; `origin` is compared | the 0.4.2 incident, step by step |
| `quota.lock` | four ceilings, and where the file lives | why 96%, why it is never copied |

**The seam is the same every time: the rule belongs in the guide, the measured
incident that produced it belongs in the lessons.** Everything below follows
from applying that one cut.

## What was decided

Four decisions, taken by the owner in the session of 2026-09-07:

1. **A full revision, not a trim.** `README.md` becomes a landing page;
   installation, the config reference and the skills each get a page of their
   own. The alternative considered and rejected was to move the archaeology and
   leave the navigation alone — it would have left a 3400-word front page still
   carrying the whole reference.
2. **The new pages live in `docs/guide/`, and `watched_dirs` narrows to
   `docs/statuses`.** This keeps the frozen decision literally true: the closing
   rite touches only the status file, and documentation goes through review like
   the rest of the product.
3. **`README.md` keeps a quick start.** What it is (~250 words), the two install
   commands, one line about `init`, the five skill names without descriptions, and
   a map of the documentation — about 400 words. A reader can install the plugin
   without leaving GitHub, and no third copy of the skill descriptions is created.
4. **The archaeology goes into `docs/lessons.md`**, partly into lessons that
   already exist, and no new document is created for it.

## Non-goals

- **No new content.** Every sentence that survives this change already exists in
  a tracked file. The only text written from scratch is the landing page, in two
  languages. A documentation reshuffle that also rewrites the documentation
  cannot be reviewed, because the diff stops showing what moved.
- **`CHANGELOG.md`, `knowledge/` and `skills/*/SKILL.md` are untouched.** The
  last one for the reason the previous spec gives: those files are read by a
  model, and their wording is behaviour.
- **No third language, and no new translated surface.** The six Russian pages
  below are the three that exist, cut along the same seams as their sources.
- **`docs/specs/`, `docs/plans/` and `docs/statuses/` stay off the site.** They
  are working documents; nothing here changes that.

## A prior decision this revisits

`docs/specs/2026-09-06-russian-documentation-design.md`, under "Layout",
rejected a subdirectory beneath `docs/` and said why:

> Files under `docs/ru/` would not be seen by that glob at all, and the guard
> would quietly stop guarding anything new — the "what stays green if this is
> not wired?" failure this repository keeps finding.

That reasoning is correct and applies unchanged to `docs/guide/`.
`tests/test-site.sh:138` reads `docs_list="docs/*.md"`, which is one level deep,
so a page added under `docs/guide/` would reach the site only for as long as
somebody remembered to add it, with nothing red when they did not.

The decision is revisited rather than contradicted, because the objection was to
an **unguarded** subdirectory, not to the directory. `docs_list` gains
`docs/guide/*.md`, and the existing positive control — planting a document with
no page and asserting the loop goes red — is extended to plant one in the new
directory too. Without both halves of that, decision 2 above should be reversed
and the pages kept flat in `docs/`; the subdirectory is worth having only for
the separation from `specs/`, `plans/` and `statuses/`, and that is not worth a
hole in a guard.

## What moves where

```
README.md
├── what it is, requirements                → README.md            (stays, ~250 words)
├── Install: Claude Code, Cursor ×3         → docs/guide/install.md
├── init                                    → docs/guide/install.md
├── Two stale copies — the rule             → docs/guide/install.md
├── Two stale copies — the 2026-08-25 case  → docs/lessons.md      (new lesson)
├── The five skills (prose)                 → docs/guide/skills.md
├── .floppy/config — the key table          → docs/guide/config.md
├── Where the checkouts are                 → docs/guide/config.md
├── Scope names changed in 0.5.0 — rule     → docs/guide/config.md
├── Scope names changed in 0.5.0 — history  → docs/lessons.md      (into the migration lesson)
├── Two memory repositories — rule          → docs/guide/config.md
├── Two memory repositories — incident      → docs/lessons.md      (into the derived-state lesson)
├── Memory in a different repository        → docs/guide/config.md
├── quota.lock — the four ceilings          → docs/guide/config.md
├── quota.lock — the justification          → docs/guide/config.md, condensed
└── Releases, License                       → README.md            (stay)
```

`README.ru.md` is cut along the same seams. Its outline matches the English one
heading for heading, in the same order — 22 against 22, verified 2026-09-07 — so
this is a cut of both files at the same places, not a translation job. The only
new Russian prose is the landing page.

## The site

The page table in `scripts/site-build.sh` becomes:

| nav | page | source |
|---|---|---|
| 1 | Home | `README.md` |
| 2 | Install & init | `docs/guide/install.md` |
| 3 | Config reference | `docs/guide/config.md` |
| 4 | The five skills | `docs/guide/skills.md` + generated |
| 5 | The knowledge base | generated |
| 6 | Behind it | generated, `has_children` |
| 6.1 | The memory model | `docs/memory-model.md` |
| 6.2 | Lessons | `docs/lessons.md` |
| 7 | Changelog | `CHANGELOG.md` |
| 8 | Русский | generated, `has_children` |
| 8.1–8.6 | the six Russian pages | the `.ru.md` siblings |

**"Behind it" is generated the way the Russian hub already is** — by filtering
the table on `parent`. A hand-written list of its children would be a second
copy of the table, and the two would differ the first time a page was added.
This is the existing mechanism, used once more, not a new one.

**The skills page keeps its generated half.** Today that page is generated
entirely, from each `SKILL.md`'s own `description` field, so the site cannot
describe a skill differently from the way the harness reads it. That property
must survive. So `docs/guide/skills.md` carries the prose and one placeholder
line:

```
<!-- floppy:generated skills-list -->
```

which `site-build.sh` replaces with the generated block. The page is then an
ordinary table row, which is what keeps it inside `test-site.sh`'s "every
document reaches the site" loop; a generated page with no source row would fall
out of it.

The Russian skills page carries the same placeholder and receives the **same
English block**, because `skills/*/SKILL.md` is deliberately untranslated. The
page says so in one line above it rather than leaving the reader to wonder.

## Tests

### `test-docs.sh` is rebound per file

It currently asks "does `README.md` contain this?" for every config key, both
install commands, all five skill names, the `floppy:` prefix form exactly once,
and the two `quota.lock` claims. With the content spread across pages, the same
questions have to name where each answer belongs:

| assertion | now | after |
|---|---|---|
| every `cfg_get` key is documented | `README.md` | `docs/guide/config.md` |
| `plugin marketplace add`, `plugin install` | `README.md` | `docs/guide/install.md` |
| Cursor is covered | `README.md` | `docs/guide/install.md` |
| all five skill names in backticks | `README.md` | `docs/guide/skills.md` |
| `floppy:` prefix form exactly once | `README.md` | `docs/guide/skills.md` |
| `quota.lock` is measured, never copied | `README.md` | `docs/guide/config.md` |
| the licence is MIT | `README.md` | `README.md` |

This is **stricter** than what it replaces. Today a config key documented in the
wrong section still passes; afterwards the check also says where the answer has
to be, which is the thing a reader actually depends on.

The loop that derives the key list from `lib-config.sh`'s `cfg_get` calls is
kept exactly as it is, including its guard against an empty key list making the
loop assert nothing.

### `test-site.sh` gains the new directory

`docs_list` becomes `docs/*.md docs/guide/*.md`. The existing positive control
plants a document with no page and asserts the loop reddens; it is extended to
plant one under `docs/guide/` as well, so the new half of the glob is proven to
be wired rather than assumed. Both plants stay in a temp directory, for the
reason the file already gives: the suite runs in parallel and a stray
`docs/*.md` would be seen by other tests.

### Falsify each rebinding

Every assertion moved above is checked by breaking it once and watching it go
red — remove a config key from `config.md`, drop a skill name from `skills.md` —
before the change is proposed. A rebinding that passes because it is looking at
the wrong file is indistinguishable, in a green run, from one that works.

## Translations

Six `.ru.md` files instead of three. Each new one is a cut of `README.ru.md`
plus a marker, written by the tool rather than by hand:

```bash
python3 scripts/translation-check.py --stamp docs/guide/install.ru.md
```

`README.ru.md` shrinks to the landing page and is re-stamped the same way.
`tests/test-translations.sh` needs no change: its sibling rule is written by
hand against whatever `--list` reports, and six pairs satisfy it exactly as
three did.

## The freeze this changes

`watched_dirs=docs` becomes `watched_dirs=docs/statuses` in `.floppy/config`.
`wrap-guard.sh:179` matches watched directories by prefix (`"$f" == "$w"/*`), so
a nested path needs no code change — verified 2026-09-07.

`docs/statuses/NOW.md` records it under "What is frozen", dated, replacing the
current entry: the closing rite may now commit only the status file, and all
documentation goes through review. The direction is a narrowing, which is the
direction that entry already argues for: it says the session procedure is the
product here and belongs in reviewed commits. What it did not have to decide,
while `docs/` held only working documents, is which side documentation itself
falls on. This change puts user documentation on the product side and says so.

`CLAUDE.md` says a file added under `docs/` needs a row in the page table; that
sentence now has to name `docs/guide/` too.

## Order of work

Two pull requests. Each is green on its own, and neither leaves the
documentation in a state with dangling links.

**PR A — extract the guide.**
1. Create `docs/guide/{install,config,skills}.md` by moving text out of
   `README.md`; add the `skills-list` placeholder.
2. Cut `README.ru.md` at the same seams into the three `.ru.md` siblings.
3. Reduce both READMEs to the landing page.
4. Add the six table rows; teach `site-build.sh` the placeholder substitution.
5. Rebind `test-docs.sh`; extend `test-site.sh`'s glob and its positive control.
6. `watched_dirs`, `NOW.md`, `CLAUDE.md`.
7. Stamp every new translation.

**PR B — move the archaeology.**
1. Move the three incidents out of the guide pages into `docs/lessons.md`: two
   into lessons that already exist, one as a new lesson about a copy that goes
   stale in silence.
2. Same in `docs/lessons.ru.md`; re-stamp.
3. Add the "Behind it" parent and move `memory-model` and `lessons` under it.

Splitting the other way round does not work: extracting the pages without
rebinding the tests reddens `test-docs.sh` inside PR A.

## Known unknowns

- **Whether the landing page is the right length.** 400 words is a judgement,
  not a measurement, and the only way to check it is to read the rendered page.
  It is cheap to change afterwards and nothing else depends on it.
- **Whether `quota.lock`'s justification survives condensing.** The section is
  half reference and half argument, and the argument is load-bearing — it is why
  the ceilings are per-project rather than defaults. If condensing it turns out
  to lose the reason, the fallback is to move the whole argument into
  `docs/lessons.md` and leave only the four ceilings in the reference. That is a
  decision to take while writing, with the diff visible, not now.
- **Nothing here is measured about readers.** The claim that the current front
  page overloads a newcomer rests on its size and on what the sections are, not
  on anyone having watched a newcomer read it.
