---
name: workstatus
description: Report what is true right now, checked live rather than recalled — retells `bash .floppy/run status` and names what is waiting on the human. Use mid-session for "where are we", a live status check, before answering a question about current state, or when the user asks for workstatus.
---

# Workstatus

Not `start`. `start` orients a clean session from documents; this reports
**live state**, mid-session, by running a command and describing what it
printed. Its whole point is narrower than it sounds: report what was seen,
not what is remembered.

**Rule that matters more than the format below: never answer from
conversation memory.** Anything checkable gets checked with a command first.
"The run is probably still going" without looking at its log is exactly the
kind of guess this report exists to rule out.

## What to run

```bash
bash .floppy/run status
```

One call collects background jobs, git state (divergence from the remote,
uncommitted files), and the memory wiring, and prints an answer rather than
raw material — a bare `ps` or `git status -uall` costs far more to read for
three lines that matter.

If the repository defines a project-specific hook
(`.floppy/workstatus-project.sh` — servers, corpora, anything specific to
this project's own data), the command runs it automatically; nothing extra
to call for that.

A repository split into halves (see `agent-memory`) may also support a
`--flow` flag for the state of the process half itself (memory lint,
wrap-lock, worktrees, recent process edits):

```bash
bash .floppy/run status --flow
```

Use it only when the task is about the process itself — on any other branch
of work that half's state is someone else's business, not news.

Beyond the command: pull a background job's log tail directly only if the
report flagged something odd, and check `git log origin/HEAD..HEAD --oneline`
only if the report flagged divergence. Don't gather more than the report
already pointed at.

## Format

Five short blocks. Say "empty" for a block with nothing in it — don't
manufacture content to fill it; a report that is always equally full stops
getting read.

1. **Where we are** — one line: which half, which thread of work.
2. **Background** — a table: job, progress as a number, how long to wait,
   where its log is. If nothing is running, say so.
3. **On the agenda** — an ordered list of what's next, marking what doesn't
   need the human.
4. **Waiting on you** — decisions only the human can make. One line each,
   with the cost of waiting: what specifically can't proceed until they
   answer.
5. **Risks right now** — uncommitted work, divergence from the remote, stale
   background jobs, red tests, a half-finished edit left in the tree.

If the current-state file is older than what `run status` just showed — for
instance the git history moved past what it describes — say that plainly
rather than reporting the file's version of events.
