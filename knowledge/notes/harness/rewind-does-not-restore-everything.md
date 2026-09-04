---
name: rewind-does-not-restore-everything
description: Checkpoints cover only file-editing-tool edits — bash changes, background subagent edits and symlinked paths survive a rewind
area: harness
verified_on: 2026-09-05
verified_against: "Claude Code 2.1.232; docs at code.claude.com/docs/en/checkpointing"
recheck: "Read code.claude.com/docs/en/checkpointing, section 'Limitations'; confirm the four exclusions are still listed"
invalidated_by: "Checkpointing starts tracking bash-side effects or following symlinks"
---

# `/rewind` restores less than the word suggests, and says so only afterwards

## The fact

Claude Code snapshots the working tree before every user prompt and `/rewind` (or double
`Esc` on an empty prompt) rolls back to any of them. Four categories are **not** covered:

1. **Files changed by bash.** `mv`, `rm`, `cp`, a build script, a generator — none of it
   is tracked. Only edits made through the file-editing tools are.
2. **Edits by background subagents**, including background forked skills and
   `/code-review --fix`. A *foreground* forked skill is the one exception.
3. **Symlinked and hard-linked paths.** These are skipped, with a
   `Restored the code, but skipped N files` warning after the fact.
4. **Changes made outside the session** — your own editor, another concurrent session.

## Why it is not obvious

The menu offers "Restore code and conversation", which reads as a full undo, and in a
session dominated by Edit calls it behaves like one. The gap only appears in a session
that produced files by running things — which is exactly the session you most want to
undo. The symlink case is worse than silent: it warns *after* restoring, when the
half-restored tree already exists.

## Evidence

**READ**, primary source: the [checkpointing documentation](https://code.claude.com/docs/en/checkpointing),
section *Limitations*. Quoting the first: "Checkpointing does not track files modified by
bash commands… These file modifications cannot be undone through rewind."

**MEASURED**, indirectly: in one 30-day sample of a repository whose work is
script-driven, `Bash` accounted for 8 215 of 13 676 tool calls against 2 345 `Edit` and
605 `Write`. The proportion of mutations outside checkpoint coverage is not a corner case
in that kind of repository; it is the majority of the activity.

## How to re-check

Open the docs page and confirm the four exclusions are still under *Limitations*. For the
symlink case specifically, turn on `/debug` before restoring: the debug log at
`~/.claude/debug/<session-id>.txt` names every path the restore skipped.

## What it costs you not to know

You treat `/rewind` as an undo and stop taking commits. Then a session that produced half
its output through scripts goes wrong, you rewind, and you are left with a tree that is
part old and part new — the tool-edited files rolled back, the script-written ones not.
That state is worse than either endpoint, and nothing on screen says you are in it.

Two specific traps worth stating plainly:

- **Rewind is one-way.** It is not a substitute for `git stash` when you want to set a
  change aside and get it back. Use it to abandon a direction, not to A/B one.
- **Repositories that symlink configuration or memory directories into the tree** — a
  dotfile manager, a shared memory checkout, pnpm's hard links — will have exactly those
  paths skipped, and those are often the files carrying the session's conclusions.

## See also

- [[opus5-subagent-prompt-line]] — harness behaviour with no configuration surface.
