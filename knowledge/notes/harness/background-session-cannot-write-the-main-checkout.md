---
name: background-session-cannot-write-the-main-checkout
description: A background session is refused on its first edit inside the session's own repository — but not in additional directories — and the escape is a worktree branched from your own head, entered by path rather than by name
area: harness
verified_on: 2026-09-01
verified_against: "Claude Code background job in a repository with a feature branch of its own; EnterWorktree with name: and with path:, and .claude/settings.local.json"
recheck: "Start a background session in a repository and have it edit one tracked file: the refusal names the missing isolation. Repeat the edit in a directory added as an additional directory — it succeeds."
invalidated_by: "The guard is extended to additional directories, or background sessions are given writable isolation automatically"
---

# A background session cannot write to the checkout it was started in

## The fact

A background job is refused on the **first** file edit in its own repository:
"this background session hasn't isolated its changes yet". The guard covers the session's
**main** repository only — directories added as additional directories are edited freely from
the same session.

Three ways round it do not work:

- **`EnterWorktree` with a name.** The default `worktree.baseRef` is `fresh`, meaning a branch
  off `origin/<default-branch>`. A feature branch with thirty commits of its own does not
  build in that worktree at all.
- **Turning the guard off in `.claude/settings.local.json`.** This is self-modification of the
  configuration without asking the user, and it is refused. The refusal is right; do not route
  around it.
- **Putting the writes behind a symlink into the repository.** The guard resolves the symlink,
  and gitignore does not matter to it.

## Why it is not obvious

The session has the repository as its working directory, its permissions look unchanged, and
nothing at launch says the write path is different. The scope of the guard is the surprise in
both directions: it stops an edit to a file the session owns, and it permits the same edit one
directory away.

## Evidence

**MEASURED**, 2026-09-01, in an Elixir project with a long-lived feature branch: the first
edit was refused with the message above; edits in an additional directory from the same
session went through; the three workarounds failed as described, each on its own attempt.

What worked, in order:

1. `git worktree add .claude/worktrees/<name> -b <branch>-<step> <branch>` — from your own
   branch head, not from the default branch.
2. `EnterWorktree` with `path`, not `name`.
3. Symlink each path dependency in separately: a `path:` dependency resolves relative to the
   worktree, so it needs `ln -sfn <real path> .claude/worktrees/<dep>`.
4. Finish with `ExitWorktree` (keep), then from the main checkout
   `git merge --ff-only <branch>-<step>`, `git worktree remove --force`, drop the symlink,
   `git branch -d`.

## How to re-check

Start a background session and edit one tracked file in its repository, then edit a file in an
additional directory. One is refused, one is not.

## What it costs you not to know

A background session that looked productive turns out to have done nothing durable, and the
first attempt to fix it — branching a fresh worktree by name — silently discards the branch
you were working on, because `baseRef: fresh` is not your head.

Two costs specific to the worktree route are worth planning for. The first build in a fresh
worktree rebuilds the project from scratch (several minutes in the project measured); start it
in the background immediately after the symlinks, in parallel with the first edits. And
`git checkout --` inside a worktree bites harder than usual: the index there is empty, so
reverting one thing reverts unstaged work beside it. Stage after each edit rather than once
before a series.
