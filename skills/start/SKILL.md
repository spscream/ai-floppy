---
name: start
description: Orient a fresh session before touching any file — read the current-state file, the relevant half's own guidance, and that half's memory index, then verify live facts with `bash .floppy/run status` instead of trusting the documents. Use at the start of a session, when picking up a new task or branch of work, or when the user asks to start, orient, or "what's next".
---

# Start

Orienting, not working. Do not edit code or memory during this — the job is
to find out where things stand and agree what happens next, and a clean
session has no conversation history to fall back on, only what this skill
reads.

See `agent-memory` for what a note, an index, and evidence mean; this skill
only says which of them to open and in what order.

## Order

1. **Identify the half the task belongs to.** Halves are directories under
   the configured memory directory (`memory_dir` in `.floppy/config`) — this
   skill does not hardcode their names. Which words route to which half is
   the consumer's own knowledge, kept in their own `AGENTS.md` (or
   equivalent), not here. If the task doesn't name a half clearly, ask which
   one in a single short question rather than guessing.

2. **Read the current-state file whole.** Its path is `statuses_now` in
   `.floppy/config` (a repository default such as `docs/statuses/NOW.md`).
   This is the one status document read in full; it is rewritten in place, so
   it answers "what's true right now" without needing history. If it points
   at a dated journal entry for a detail, open only that section, and only if
   the task needs it — not the whole journal.

3. **Read the half's own guidance** — its `AGENTS.md` or whatever document
   the consumer's routing table names for it.

4. **Open that half's memory index** (`<memory_dir>/<half>/INDEX.md`, or a
   sub-index within it), not the whole memory tree. Read the one or two notes
   that plainly relate to this task; skip the rest.

5. **Check live facts instead of trusting the documents:**

   ```bash
   bash .floppy/run status
   ```

   Documents can be stale in a way that looks identical to being current — a
   rewritten current-state file carries no sign of its own age. The command
   reports what is actually true right now: git state, divergence from the
   remote, background work, memory wiring. If it disagrees with what the
   documents said, the command wins, and say so out loud rather than quietly
   answering from the documents.

   When the task is on the process/tooling half itself, this step is
   **replaced** by, not performed in addition to, the flag that reports the
   same live facts plus that half's own state — memory lint, the wrap lock,
   worktrees, recent process edits:

   ```bash
   bash .floppy/run status --flow
   ```

   Run one or the other, never both: `--flow` is the plain report with the
   process-half section appended, so a plain `run status` right after it
   would just repeat what it already printed.

## Answering

Give the answer before making any edit, in four short parts:

- **Where we are** — from the current-state file and the memory just opened,
  with pointers to the files, not a restatement of their content.
- **What's frozen** — thresholds, artifacts, or decisions on this half that
  cannot move without a dated, deliberate change.
- **What I propose** — an ordered list, marking which items need a decision
  from the human and which don't.
- **What's missing** — unknown numbers, open decisions, external
  dependencies that block a confident answer.

If the current-state file and `run status` disagree — for instance the
command reports the branch is behind its remote — resolve that first (a
`git pull --rebase` before anything else) rather than answering against state
that no longer holds.
