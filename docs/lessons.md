# Lessons

Things this plugin learned the expensive way. Each one is a decision or a
failure that shaped the code, written down so the next change does not repeat
it. The design these refer to is in [memory-model.md](memory-model.md).

## Renaming a scope in live memory costs a migration

On 2026-08-25 the memory layout was renamed **four times in one day**:
`projects/<key>` → `projects/<key>/memory`, `/local` → `/shared`, `/private` →
`public/projects/<key>` and `private/projects/<key>`. Every name corrected the
one before it, and every one was derived from the situation rather than from a
written model.

The cause: each name glued two independent axes together. `local` said "about
this machine" but meant "private to a project, shared between machines".
`workplace_repo` named an audience with a word from the "where is it true"
axis. While the model existed only in the head of the person editing, every
next name failed in the same direction.

What it costs. A rename in live memory is not a string edit, it is a
migration: `git mv` in the memory repository, a repointed symlink on **every**
machine, index pointers rewritten (three pointers stayed broken for a day —
`git mv` renamed the directory but not the text that referred to it), and the
layout description fixed in two READMEs and in the consuming project's docs.
Add the window where the machines disagree: one writes the old path while the
other reads the new one, and the memory quietly forks.

**Rule: write the model before renaming anything in live memory** — which axes
exist, which cell is expressed by what — and have a human read it. Writing
`memory-model.md` after the fourth rename immediately caught a fifth mistake:
its first draft allowed a namespace at the repository root, and with one URL
serving both roles the scopes would have collided.

What worked in practice: a verb that **refuses on the old layout and prints
the `git mv` to run**, instead of migrating by itself. Migrating by itself is a
fork on the other machine; printing the command is cheap. The verb does repair
the links, because there is no content behind them.

## Derived state beats a config flag

Designing the "memory outside the code repository" layout, a boolean key in the
config suggested itself: `external = yes/no`. It was rejected. The mode is
**derived** from where the memory directory path resolves to.

A flag would be a second source of truth about something the filesystem
already knows, and the two would diverge **precisely in the dangerous case**:
the symlink was not created, the config still says "external", writes land in
an ordinary directory inside the code repository, and the ignore rule hides
them there. Resolving a path cannot be wrong about where a write will go.

Applying it:

- if state can be read from the world (a path, a symlink, a file's existence, a
  binary's version) — read it, do not ask the config. Config carries what the
  world does not have: the address of a store, the name of a scope, a ceiling;
- "derived" does not remove the need for a guard. Every branch of the
  derivation needs one for the state that no correct mode expresses. Here that
  is "memory directory ignored **and** inside the code repository" — broken
  under any layout, and exactly the shape of a half-finished setup;
- the derivation must be cheap and portable. Here it is `cd && pwd -P`, because
  `realpath` and `readlink -f` on macOS are not the ones you want.

## `find` does not follow a symlinked root

Measured 2026-08-25: `find <symlink-to-dir> -name '*.md'` yields **0**,
`find <real path>` yields 2, `find -L <symlink>` yields 2. There is no error.
An empty result is indistinguishable from "nothing to find".

The incident: the memory linter walked the directory with a plain `find`, and
in the layout where memory is moved into another repository that directory is a
symlink. Every loop ran over an empty list and the run printed `clean: 0
notes`. That linter is the **first commit gate**, so the entire quality check
on memory was dead in that layout while staying green.

Applying it:

- walking a tree a symlink can reach (memory, an external store) — use
  `find -L`. `-not -path` exclusions keep working: paths are built from the
  starting point;
- **assert the number found, not the colour**: `clean: N notes`, with N
  expected. An assertion on `rc=0` passes for a check that looked at nothing;
- keep a positive control next to it — a deliberately broken file that must go
  red;
- the same holds for `grep -r` and any walk: a symlink is not expanded by
  default.

## The test suite hangs without a closed stdin

`bash tests/run.sh` hangs forever if stdin is not closed. Measured 2026-08-25:
the process lived nine minutes without moving; the process tree showed
`tests/test-shim.sh` → `scripts/wrap-guard.sh`. In the same session another
such process from an earlier run was found, hung for 4.7 hours.

The mechanism: `test-shim.sh` loops over every verb and takes `head -1` of the
output. `guard` with no arguments reads its file list from stdin. Under an
agent's tool runner stdin is a pipe that never closes, so `guard` waits for
input forever and `head` waits for `guard`.

Run it as:

```
bash tests/run.sh </dev/null
```

CI does not show this: there stdin gives EOF at once and the jobs are green.
A green CI says nothing about this failure — it is about the calling
environment, not about the code.

Stopping a hung run: only by PID taken from `ps`. `pkill -f` in such an
environment matches the caller's own shell and kills it.
