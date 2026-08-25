# Changelog

Why this file exists, in one line: **`plugin update` compares version strings
and copies nothing while the version is unchanged**, so the version here is
load-bearing, and a consumer needs to know whether an update is worth taking.

One column matters more than the rest and is called out per release:

> **Refresh `.floppy/run`?** — `.floppy/run` is a *copy* in your repository,
> not a link, and no plugin update ever touches it. When a release changes the
> shim, updating the plugin is only half the job:
> `cp "$FLOPPY_ROOT/shim/run" .floppy/run`. Since 0.2.1 the shim notices this
> itself and prints the command; before that it was silent.

Dates are the day the version was tagged in `.claude-plugin/plugin.json`.

## 0.4.0 — 2026-08-25

**Refresh `.floppy/run`: yes** (new verb, four new config keys).

- New verb `store`: wires memory hosted in another repository — clone or pull,
  link, add the ignore line, and then the step that actually proves it, writing
  through the link and confirming the file appears in the store. Idempotent,
  per machine and per worktree, `--check` reports without changing. It refuses
  rather than guesses when a real directory sits where the symlink belongs:
  those notes may be the only copies of something.
- `init` learned `--memory-repo` / `--memory-key` / `--memory-repo-dir`, and
  writes the index *through* the new symlink so it lands in the store. Half the
  pair is refused rather than half-applied. Without the flags nothing changes:
  the generated config documents the option commented out, because a project
  pointed at a store it never chose would write its notes into somebody else's
  repository.
- **New guard, and it catches a state that was comfortable to live in:** a
  memory directory that is gitignored *and* inside this repository. That is the
  shape a half-done external setup takes — ignore line added, symlink never
  created — and in it notes are written and read normally while nothing will
  ever commit them. Previously the failure surfaced at the end of the session
  wearing the wrong name ("not changed: wrong path, or the edit was lost").
- `memory_local_dir` (default `local`) names the machine-local scope instead of
  the linter spelling it in. Not cosmetic: the rule "committed memory must not
  link into that scope" is what protects against links dead on a second
  machine, and under any other name it had been silently applying to nothing.
  A name with regex metacharacters is refused rather than matched wrongly.

377 asserts, up from 328.

## 0.3.0 — 2026-08-25

**Refresh `.floppy/run`: yes** (new config key).

- The memory size caps left `memory-lint.sh`, into **two** homes rather than
  one. `index_chars_max` is a fact about the *harness* — its session loader
  truncates the memory index past a limit of its own, measured at ~24986
  characters on Claude Code — so it is a `.floppy/config` key with the number
  shipped as a default. `pointer_line_max` is a fact about *your corpus*, the
  same kind as `pointers_max` beside it, so it joins `quota.lock` (default 170).
  Asking a project to measure the first one would be asking it to measure
  somebody else's tool.
- The index-size *warning* threshold is no longer configurable at all. It had
  to stay in a fixed relation to the cap, which is two chances to set it wrong;
  derived at 96%.
- Both new values are rejected by name when non-numeric, and fall back to the
  default rather than comparing against garbage.

## 0.2.3 — 2026-08-25

**Refresh `.floppy/run`: no.** But if your memory is external (0.2.2), take
this release: without it the memory gate silently passes.

- **Fixed, and it was serious:** `memory-lint.sh` walked the memory with plain
  `find`, which does not descend into a symlinked starting point. With memory
  hosted in another repository the memory directory *is* a symlink, so every
  check iterated over nothing and reported `clean: 0 notes` — and that lint is
  `wrap-commit`'s first gate, so the whole memory gate was dead in that layout.
- `tests/run.sh` dispatched each test through a bare `bash`, resolved via PATH.
  On macOS a newer bash normally sits ahead of `/bin/bash`, so a run meant to
  prove bash 3.2 compatibility re-tested bash 5. It now uses `$BASH` and prints
  which interpreter it is using.
- CI added: the suite runs on ubuntu (bash 5) and on macOS with `/bin/bash`
  explicitly, which is the job that actually earns its minutes.

## 0.2.2 — 2026-08-25

**Refresh `.floppy/run`: yes** (the shim derives the new layout).

- **Memory can live in a repository other than the code's** — for a checkout
  you do not own, or a policy keeping notes and code apart. Point `memory_dir`
  at a symlink into another git repository and gitignore it; `guard` asks that
  repository what changed and answers in the paths you typed, `check` shows the
  notes going out, `commit` commits and pushes both from one file list, and
  `status` reports the store so a clean tree stops meaning "nothing pending".
- The layout is **derived** from where `memory_dir` resolves, never declared:
  a flag in the config would disagree with the filesystem exactly when a
  symlink failed to be created.
- A store that cannot be pushed fails `commit` loudly instead of printing
  "session closed" over unpublished notes. A `memory_dir` outside git
  altogether is named as such — it reads and writes fine and publishes nothing.
- Setup is still manual (clone, symlink, ignore line). `init` does not do it yet.

## 0.2.1 — 2026-08-25

**Refresh `.floppy/run`: yes — and this is the release that makes future
refreshes visible.**

- The shim compares itself against the plugin's copy on every call and prints
  one line on stderr when they differ, with a ready `cp`. Most of the ways a
  shim goes stale are silent: a corrected config parser or search order just
  keeps doing the old thing.
- A warning, not a gate — an old shim usually still works, and refusing to run
  would turn a nudge into an outage on whichever machine pulled first.
- The hint is a plain `cp` and not a `refresh` verb, because a shim old enough
  to need refreshing is too old to know the verb that would do it. For the same
  reason this guard only starts working *after* one manual refresh.

## 0.2.0 — 2026-08-25

**Refresh `.floppy/run`: yes** (new verb).

- New verb `parity`: compares localized command files against the English
  skills they translate — the set of `bash .floppy/run <verb>` calls and the
  sequence of numbered headings, and deliberately nothing about wording,
  section titles or length. `wrap`'s `check` gates on it.
- Both stale-copy failures around the shim used to be mute and now name which
  side is behind: an unknown verb (this copy is old) and a verb whose script is
  missing (this machine's plugin is old).
- New config key `commands_dir` (default `.claude/commands`).

## 0.1.1 — 2026-08-25

**Refresh `.floppy/run`: yes.**

- The shim refuses to resolve into a plugin directory that holds no
  `scripts/*.sh`. A cache from a moment when `scripts/` was empty was being
  treated as an install, and every verb died with "No such file or directory"
  pointing inside the cache.
- Version bumped for its own sake as well: `plugin update` had been reporting
  "already at the latest version" and copying nothing.

## 0.1.0 — 2026-08-25

First release. The session rite extracted from the project it grew in: the
shim, eight verbs, five skills, memory conventions, and the guards — file-list
gate, memory linter, per-session lock — that keep the rite honest.
