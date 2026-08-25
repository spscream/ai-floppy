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

## 0.7.0 — 2026-08-25

**Refresh `.floppy/run`: yes** (four new keys). **The scopes moved under a
namespace directory — the old ones are refused with the `git mv` printed.**

The model is written down now: [docs/memory-model.md](docs/memory-model.md).
Three questions per note, independent — who may read it (a repository
boundary), what it is about (`projects/<key>` or `common`), and where it is
true (everywhere, one workplace, one machine). The layout had been renamed
three times in a day because that model existed only in whoever was editing.

- **Scopes are `public/projects/<key>` and `private/projects/<key>`.** The leaf
  that repeated the audience (`shared`, `private`) is gone. The namespace
  directory is always present, including in a repository that holds only one:
  the alternative makes the path depend on whether two config URLs are equal.
- **New keys `public_repo` and `private_repo`,** replacing `memory_repo` and
  `workplace_repo`, which are still read. The old pair named an audience with a
  validity word and made two independent questions look like one axis.
- **New keys `machine_key` and `workplace_key`.** They name the validity
  directories `machines/<machine>/` and `workplaces/<place>/` inside a scope,
  for a note that is not true everywhere — the cell no earlier layout could
  express. Both are optional and nothing creates the directories yet.
- Migration is refused, not performed, exactly as in 0.5.0 and 0.6.0: the verb
  prints the `git mv`. Wiring left pointing at an earlier scope is repointed
  without a manual `rm`.

## 0.6.2 — 2026-08-25

**Refresh `.floppy/run`: no.** Take it on any machine that has migrated to
`private`, or `status` lies to it on every call.

- **`status` spelled the private scope in, and 0.6.0 turned that into a
  permanent false alarm.** The section looked for `<memory_dir>/local` while
  the wiring, correctly, was `<memory_dir>/private`: a properly wired machine
  was told to run `workplace` on every call, and a genuinely broken link under
  the new name printed nothing at all. Found by reading the report on a machine
  that had just migrated — no test failed, because no test asserted the section
  against a wired repository. The name now comes from the environment, with the
  pre-0.6.0 variable read as a fallback so a repository sitting behind an
  unrefreshed shim is judged by the name that shim actually uses.
- The linter's fallback for the same variable said `local` where
  `memory-workplace.sh` said `private`. Under an unrefreshed shim the rule
  "committed memory must not link into the private scope" therefore guarded a
  directory that no longer existed — the way of applying to nothing that this
  variable was introduced in 0.4.0 to prevent. Both now end in `private`.

430 asserts, up from 423. The first draft of the new ones passed against the
unfixed code: the sandbox had no `.floppy/run`, so every "does not say X"
assert was satisfied by a run that died before printing anything. They now
assert the section printed before asserting what it says.

## 0.6.1 — 2026-08-25

**Refresh `.floppy/run`: no.**

- The rename left the old `local` link behind, pointing at a path the `git mv`
  had emptied — two links in the memory directory, one of them broken, on every
  machine that migrates. `workplace` now removes it, but only while it dangles:
  there is nothing behind a dangling symlink this verb created itself. A link
  under the old name that still resolves points at something real and is left
  alone.
- The refusal named the layout by the version it predates ("before 0.5.0")
  while refusing a 0.5.1 layout, and the commit line it suggested still spelled
  the old scope. Both were read on a live migration a minute after the release
  that made them wrong.

423 asserts, up from 415.

## 0.6.0 — 2026-08-25

**Refresh `.floppy/run`: yes** (new key name). **The private scope is renamed —
migrate it the same way as 0.5.0, and read why first.**

- **`local` became `private`,** in the scope (`projects/<key>/private`), in the
  link inside your repository (`<memory_dir>/private`), in the view, and in the
  config key (`memory_private_dir`; `memory_local_dir` still works).
  The name was left over from the days when that directory really was
  machine-local and gitignored. It has been neither since it became a symlink
  into a repository shared by a workplace's machines — and the name kept saying
  otherwise, convincingly enough that the owner of the corpus read it as "facts
  about this machine" and asked where those go. They go to `machines/<name>/`
  of the workplace repository, which is synced like everything else: that scope
  answers "where is this true", not "who may see it".
- The old scope is refused with the `git mv` printed, exactly as in 0.5.0 and
  for the same reason. A link left pointing at any earlier scope of the same
  repository is repointed without a manual `rm` (0.5.1).

415 asserts, up from 414.

## 0.5.1 — 2026-08-25

**Refresh `.floppy/run`: no.** Take it before migrating a second machine.

- **Wiring left by a pre-0.5.0 run is repointed, not refused.** After the scope
  move, `<memory_dir>/local` still pointed at the old scope of the same
  repository, and the verb stopped with "the symlink points elsewhere" — so
  every machine needed a manual `rm` before it could be rewired. That link is
  wiring: it holds no content, and this verb recreates it on each machine
  anyway. A link into a *different* repository is still refused, because that
  one may be another workplace and this verb does not guess.
- `readlink -f` left `memory-workplace.sh`. BSD readlink on macOS has no `-f`,
  so that comparison had never worked there — it was reached only when the link
  already disagreed, which is why no test and no machine had shown it.

414 asserts, up from 406.

## 0.5.0 — 2026-08-25

**Refresh `.floppy/run`: yes** (new key, and the shim resolves the new layout).
**Scope names changed — read the migration note below before updating.**

The layout is now keyed by project, not by repository. What a person opens is
`agents_memory_dir/<key>/`, holding `shared` and `local`; the clones moved into
`agents_memory_dir/.clones/<repository>/`, one per URL as before. A flat parent
mixed two alphabets — project names beside repository names — and telling them
apart needed the config open beside the terminal.

- **New key `project_key`.** One key names this project in every memory
  repository it uses and names its directory in the view.
  `memory_project_key` and `workplace_project_key` stay as overrides, for the
  project whose scope really is named differently in two repositories.
- **The scopes are siblings now:** `projects/<key>/shared` in the store,
  `projects/<key>/local` in the workplace repository. They were
  `projects/<key>/memory` and `projects/<key>` itself, so with one repository
  serving both roles the second contained the first — private notes and shared
  memory in one tree, and `--migrate-local` walking a corpus that was not its
  own. N projects were already separated by `<key>`; what confused them was the
  nesting.
- **The old scope names are refused, not migrated.** The verb stops and prints
  the `git mv` commands. Moving somebody's notes unasked is what this plugin
  refuses to do everywhere else, and doing it on ONE machine is worse than not
  doing it: until the other machine also runs 0.5.0, one writes the old path
  while the other reads the new one and the memory forks with nothing red
  anywhere. Update every machine first, then move the scopes once.
- `<memory_dir>` and `<memory_dir>/local` point at the view, not into a clone,
  so a repository URL can change without rewiring every worktree. The write
  probe at the end of each verb proves the whole chain, so the extra hop is
  checked rather than trusted.
- The view links are relative when the clone sits under the same parent:
  `agents_memory_dir` can be moved as one directory. They are never committed —
  in the adopted legacy layout, where the parent itself is a checkout, the
  containing repository is told to ignore them.
- `init` learned `--agents-memory-dir`, and now wires the store by calling the
  shim rather than the store script with a hand-built environment. That copy of
  the path resolution had already fallen behind the shim's.
- The nesting refusal walks up to the nearest existing ancestor. With clones
  under `.clones/`, testing only the immediate parent would have missed the
  case and cloned into the repository below it.

406 asserts, up from 405.

## 0.4.2 — 2026-08-25

**Refresh `.floppy/run`: yes** (the shim resolves the checkout paths, and one
new config key).

Two defects, both found by asking what happens when `memory_repo_dir` and
`workplace_memory_dir` name one directory, and both measured before they were
fixed.

- **Notes could be published to the wrong repository, with `ok` on every
  line.** The configured URL was read only on the clone path. With a checkout
  already at that directory, the second verb skipped its clone, never compared
  the remote, wired the link, and reported "a write through the link lands in
  the workplace repository" — while the notes landed in the store, where
  `commit` would have pushed them. Now: the checkout directory is **derived
  from the URL** under one parent (`agents_memory_dir`), so two repositories
  cannot collide; and any existing checkout has its `origin` compared with the
  configured URL, with a refusal naming both. That second check also catches an
  unrelated repository sitting at the path, which never needed a collision.
- **The wiring symlink was committed into the store.** With a store, `local/`
  is created inside the store's working tree, holding an absolute path: on a
  machine whose checkout lives elsewhere it is a dangling link, and the path
  `projects/<key>/memory/local/memory/local/...` recurses without limit. It is
  per-machine wiring, and every machine runs the verb anyway, so the store is
  now told to ignore it.
- New key `agents_memory_dir` (default `$HOME/agents_memory`), with a worked
  example of the resulting tree in the README — the layout was described in
  words only, and "the parent" named nothing a reader could point at. `memory_repo_dir`
  and `workplace_memory_dir` remain as per-machine overrides. **Nothing to
  migrate:** a checkout already sitting at the parent is adopted once its
  `origin` matches, and the verb says so.
- A clone that would land inside another checkout is refused, with the two
  commands that undo the nesting. `scripts/lib-checkout.sh` now holds the half
  of the two verbs that was duplicated — and had already drifted.

405 asserts, up from 377.

## 0.4.1 — 2026-08-25

**Refresh `.floppy/run`: yes** (the install hints it prints name the
repository, and the repository was renamed).

- The repository is `spscream/ai-floppy`, was `spscream/ai_floppy`. GitHub
  redirects the old name for both git and the web, so an existing marketplace
  entry and any command someone already wrote keep working; what would not
  have kept working is the hint a failing shim prints, which would have named
  a repository nobody can find. Nothing else moved: the plugin and the
  marketplace are still both `floppy`, `floppy@floppy` installs as before, and
  `AI_FLOPPY_HOME` keeps its underscore — it names an environment variable,
  not the repository.
- No behaviour changed anywhere. This version exists so that `plugin update`
  copies the corrected shim at all: it compares version strings, and under an
  unchanged one it would report "already at the latest version" over a shim
  still printing the old name.

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
