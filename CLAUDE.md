# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repository is

`floppy` is a **plugin** for Claude Code and Cursor — bash scripts plus prose
skills. There is no build step, no package manager, no compiled artifact. The
deliverable is what git tracks.

Two consequences that shape everything below:

- **The product is a session ritual, so this repository dogfoods itself.** The
  `.floppy/`, `.agent-memory/` and `docs/statuses/NOW.md` here are floppy in
  use, not fixtures. When running the rites *in* this repository, they act on
  the plugin's own memory.
- **Everything must run on macOS `/bin/bash` 3.2.57.** No `mapfile`, no
  `declare -A`, no `wait -n`, no `stat -c`, no `ps --no-headers`, no `ss`, no
  bare `timeout`, no GNU-only flags. CI runs the whole suite on that bash and
  it has already killed three scripts that were green on Linux.

## Commands

```bash
bash tests/run.sh                  # whole suite, parallel (one job per core)
bash tests/run.sh wrap             # only tests/test-*wrap*.sh
FLOPPY_TEST_JOBS=1 bash tests/run.sh wrap-lock   # serial, live output — use while chasing one failure
/bin/bash tests/run.sh             # what the macOS CI job runs; NEVER a bare `bash` for this

python3 scripts/knowledge-recheck.py       # gate: runs the executable half of knowledge notes
python3 scripts/knowledge-rot-check.py     # reports aged/off-contract notes, never exits non-zero
python3 scripts/translation-check.py       # reports stale translations, never exits non-zero
python3 scripts/translation-check.py --stamp docs/x.ru.md   # re-record a translation against its source

bash scripts/site-build.sh .site   # assemble the Jekyll sources (CI does this; Ruby is CI-only)
```

`tests/run.sh` propagates `$BASH` — the interpreter it was itself started with —
to every test file, because a bare `bash` resolves through PATH where a Homebrew
bash 5 sits ahead of `/bin/bash`. Preserve that when touching the runner.

Each test file builds its own sandbox under `mktemp -d`, overrides `HOME`, and
touches nothing outside it. That independence is what allows the parallel run;
keep it.

### Running the plugin's own verbs against this checkout

```bash
bash scripts/run status
```

The dispatcher roots itself in its own path (0.26.0), so the copy that answers
is always the one you called — this checkout, not the installed plugin cache.
That was the point of the change: `AI_FLOPPY_HOME` existed because a run could
otherwise land in a different copy of the same repository and report a script
you had just fixed as still broken. `shim/run` still honours the variable, for
the consumers who still call through a copy.

## Architecture

### Two layers, and where the third one went

```
<plugin>/scripts/run  →  scripts/<verb>.sh
  dispatcher + lib-config.sh     the work
```

Since 0.26.0 there is no layer in the consumer's repository. A skill is handed
its own base directory when the harness loads it (`Base directory for this
skill: <plugin>/skills/<name>`, measured 2026-09-22), so the caller knows where
the plugin is and calls `<plugin>/scripts/run` directly; `scripts/run` derives
`FLOPPY_ROOT` from `${BASH_SOURCE[0]}`. `init` writes `.floppy/config` and no
code. What the consumer carries is data.

- **`shim/run`** is what that layer used to be, copied into a consumer as
  `.floppy/run` by every `init` before 0.26.0. It still ships, for the
  repositories that already carry a copy — and it is deliberately left
  byte-identical, because it `cmp`s itself against the plugin's copy and any
  edit here would tell every one of those repositories that their copy is
  stale. It does one thing: **find the plugin**. Resolution order is
  `CLAUDE_PLUGIN_ROOT` → `CURSOR_PLUGIN_ROOT` → `AI_FLOPPY_HOME` → Claude cache
  (`sort -V`, version-named) → Cursor local symlink → Cursor cache (`ls -dt`,
  SHA-named, so mtime not lexical order). A candidate counts only if it holds
  `scripts/*.sh`. The shim also `cmp`s itself against `$FLOPPY_ROOT/shim/run`
  and prints the `cp` to refresh.
- **`scripts/run`** holds the verb table, and **`scripts/lib-config.sh`** the
  single config parser. Both moved out of the shim in 0.14.0 so a new verb, key
  or default reaches every consumer with `plugin update` alone. Add verbs here,
  never in the shim.
- **`scripts/*.sh`** are the verbs. Every one reads its settings from exported
  `FLOPPY_*` variables and acts on `FLOPPY_REPO` (the git toplevel, resolved
  once in `scripts/run`, loud failure outside a repository).

Verbs: `env lint link workplace store guard heat lock status check commit`.
`lib-checkout.sh` is shared by `store`/`workplace` and is not a verb.

`skills/init/SKILL.md` carried a hand copy of that search until 0.26.0, because
`init` ran before `.floppy/run` existed; the harness states the base directory
instead, so the copy and the test that executed it
(`tests/test-init-bootstrap.sh`) are both gone. What replaced them is in
`tests/test-skills.sh`: no `SKILL.md` may name `.floppy/run`, a skill using the
`<plugin>` placeholder has to say where it comes from and how far above the
base directory the plugin sits, and every `<plugin>/…` path it names is
resolved against this checkout — which is as close to executing prose as the
guard gets. `tests/test-dispatcher.sh` holds the other half: that `scripts/run`
roots itself, ignores an inherited `FLOPPY_ROOT`, survives an exported
`CDPATH`, and hands the verbs a hint that can be pasted back.

### The wrap rite

`check` (read-only: lint + guard + diff) → human reads it → `commit` (re-runs
the gates, stages, commits, pulls `--rebase`, pushes, unlocks). Both are single
scripts to remove *turns*, not output: each step's result used to decide whether
the next should run. `wrap-lock.sh` follows the **memory**, not the clone —
with a store layout, several worktrees share one memory.

### Memory layout

Config lives in `.floppy/config` (flat `key=value`; nested YAML is unparseable
in bash 3.2). Scopes are `public/projects/<key>` in `public_repo` and
`private/projects/<key>` in `private_repo`, with `workplaces/<k>/` and
`machines/<k>/` one level deeper for facts that are not true everywhere.
`docs/memory-model.md` is the **design** the paths are moving towards — read it
before changing any path in the scripts. Every config key and its default is
documented in the `docs/guide/config.md` table, and `tests/test-docs.sh`
asserts that every `cfg_get` call in `lib-config.sh` appears there.

Here, `memory_dir` is a **symlink into a store repository**, and the private
scope under it is a symlink again — this repository is public and its documents
are published. Both `.agent-memory/private` and
`.agent-memory/common/private` are those symlinks, gitignored and personal:
nothing under either belongs in the site, the knowledge corpus or a pull
request.

## Constraints that tests enforce

- **`main` is protected.** Branch, push, open a PR (`gh pr create --fill`);
  self-merge is fine. `GH013` on push is the rule, not a bug. See `AGENTS.md`.
- **A release bumps three manifests together**: `.claude-plugin/plugin.json`,
  `.claude-plugin/marketplace.json`, `.cursor-plugin/plugin.json`, plus a
  `CHANGELOG.md` entry for that version. The *marketplace* manifest is what
  `plugin update` compares — five releases once shipped nothing because only
  `plugin.json` moved. Every changelog entry up to 0.26.0 answers **"Refresh
  `.floppy/run`?"**; the question retires with the copy, and
  `tests/test-changelog.sh` still requires the word "Refresh" in the entry for
  the shipped version.
- **The documentation site is generated, never hand-written.** Pages come from
  `README*.md`, `docs/*.md`, `skills/*/SKILL.md`, `knowledge/` and
  `CHANGELOG.md`. Adding a file to `docs/*.md` **or `docs/guide/*.md`** means
  adding a row to the page table in `scripts/site-build.sh`; `tests/test-site.sh`
  fails otherwise, and carries a separate guard asserting its document list still
  reaches `docs/guide/` at all. Those two globs are the whole of it — the guard's
  list is literally `docs/*.md docs/guide/*.md`, so a document one level deeper
  (`docs/plans/`, `docs/specs/`) neither needs a row nor gets one, and is not
  published. Say the globs, not "under `docs/`": the loose phrasing described a
  rule wider than the guard, which is how a wrong rule survives a green suite.
- **`wrap` here may only commit `docs/statuses`, `AGENTS.md`,
  `.floppy/config`** (`watched_dirs`/`watched_files`). `skills/`, `scripts/`,
  `shim/` and `tests/` are the product and belong in reviewed commits — a
  `knowledge/` note from this repository needs a deliberate PR.
- **Skills carry no `allowed-tools` key** — it silently breaks loading.
  `name:` must match the directory. Guarded by `tests/test-skills.sh`.
- **Knowledge notes obey a contract**: `name, description, area, verified_on,
  verified_against, recheck` required; the optional `platforms / requires /
  recheck_cmd / expect` half is what `knowledge-recheck.py` can execute. See
  `knowledge/_template.md` and `knowledge/README.md` for the three admission
  criteria.
- **A translation is `<stem>.<lang>.md` with a `<!-- floppy:translation
  of=… blob=… on=… -->` marker on line 1.** `translation-check.py --list` is
  the single authority on what counts as one; `workstatus.sh`'s pre-gate is
  deliberately loose (`?`, never a bracket range — `[a-z]` follows the locale
  and matches uppercase on macOS).

## Conventions

- **Reporters vs gates is a deliberate distinction.** `rot-check`,
  `translation-check` and the age checks in `memory-lint` report and never fail:
  "old" and "wrong" are different, and a gate on freshness teaches people to
  bump the date without re-reading. Where a failure *should* stop something, the
  decision lives in the workflow (`knowledge.yml`), not in the script.
- **Script output is English**, always, even where the memory is another
  language. The scripts are reusable; the memory is not.
- **Comments carry the measurement.** Headers in this repository explain *why*
  a mechanism exists, usually with a date and a number. When you change a
  mechanism, update the reasoning with it rather than leaving a comment that
  describes the old one.
- **No AI attribution in commits or PRs.**
