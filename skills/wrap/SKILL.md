---
name: wrap
description: Close a session — select the facts worth keeping into memory, update the current-state file, name what's left unfinished, then check and commit through the shim. Use when a session is ending, context is about to be cleared, or the user asks to wrap up.
---

# Wrap

The session is ending and context is about to go away. The job is making
sure the next session doesn't start from zero — and that means **selecting**
what to keep, not dumping the transcript into memory. A memory buried in
detail is worse than a short one.

See `agent-memory` for what a note, an index, and `evidence` mean; this skill
is about which facts earn a place in them and how the session closes.

## 0. Take the lock

```bash
bash .floppy/run lock acquire "<the thread of work, one phrase>"
```

A parallel session writes into the same current-state file and the same
memory index. Git does not arbitrate that — the second write simply
overwrites the first. If the lock is held, write nothing: wait a minute, try
once more, and if it's still held, tell the human another session is closing
and leave the decision to them. Release it at the end of this skill; an
abandoned lock ages out on its own after about thirty minutes, and whoever
takes it over then gets a warning that the previous session may have left a
half-written entry — that warning is the point of the takeover, not a
side effect: it tells you to go look before trusting what's already there.

## 1. Select what's worth memory

A candidate earns a note only if it passes all three:

- **it cost work** — a measurement, an investigation, a rejected hypothesis,
  a tool trap. Not something readable out of the code in a minute.
- **it outlives the session** — useful in a week to someone who wasn't in
  this conversation.
- **it isn't derivable from the repository** — not code structure, not git
  history, not a retelling of what's already written in the docs.

Explicitly **not** saved: the reasoning trail, intermediate attempts ("tried
this, then that"), a retelling of the commits.

What's usually lost, and worth the most when it survives: **rejected
hypotheses with their reason** ("this doesn't work because…"), and **numbers
that turned out to mean something other than they first seemed**. Both of
those are more valuable than a list of what got done — the list is already
in the git log.

## 2. Evidence, chosen on purpose

Every note's `metadata.evidence` is one of four values, and they describe
where the claim came from, not how important it is:

| value | when it applies |
|---|---|
| `measured` | verified against reality — a run, a profile, an incident that happened |
| `read` | taken from code, a spec, or docs — true until something runs and says otherwise |
| `decided` | a choice or an agreement; evidence does not apply, a date and an author do |
| `sourced` | an outside claim checked against its primary source, quoted and dated |

**If unsure, write `read`**, and say in the note what a measurement would
need. Marking `measured` something that was actually only read is the
expensive mistake here — it hands the next session a guess dressed as fact.

A note that trips the consumer's own per-note cap
(`note_chars_max` in their `quota.lock` — in the project this convention
was ported from, that cap was measured at ten thousand characters, which is
a fact about that project's corpus, not a rule to inherit) is not a long
note. It's two notes written as one. Split it into one fact per file; do
not raise the cap to make it fit.

## Write for a stranger

Memory gets committed, and it will be read by someone who wasn't in this
conversation and may not even know who was. Write the **role** ("the
project owner"), not a name — and don't lean on conversation context:
"as discussed above" means nothing to a reader who wasn't there. If a fact
only makes sense with the discussion attached, the discussion belongs in
the note.

## 3. Update the current-state file, and journal only if there's something to journal

Update the current-state file (`statuses_now` in `.floppy/config`) if this
session changed anything that belongs in it — a metric, a freeze, a decision,
a red or deferred item. A metric that got worse stays in, marked worse: a
disappearing line is how a regression hides in a file that's rewritten rather
than appended.

Only add a dated journal entry when the session produced numbers or an
analysis worth reconstructing a month from now. A small doc fix needs no
journal entry — that would be noise — but may still need the current-state
file updated on its own (a decision or a question taken off the table
carries no number). Re-read both files immediately before editing: another
session may have written to them since this one started.

## 4. Name what's unfinished — more important than what's done

State explicitly, in memory or the current-state file:

- background jobs and uncommitted work (`bash .floppy/run status` gives
  both in one call);
- what's waiting on the human versus what can proceed without them;
- what's broken or deferred — if it stays red, say so plainly.

## 5. Check, see the diff, commit — two calls, not ten

```bash
bash .floppy/run check <files you wrote>
```

Both calls print the repository they resolved as their first line
(`repo: /path/to/it`) — `commit` also prints the branch and push target,
above its gates. Before running `commit`, the writing half that stages,
commits, and pushes, confirm that repository is the one the human actually
meant to close: several projects can sit open in the same harness at once
(Cursor especially), and a `wrap` aimed at "this session" can land in
whichever one the shell happened to be in rather than the one the human was
talking about. One line is enough — name it, don't turn it into a ceremony.

```bash
bash .floppy/run commit -m "<what the facts are, not 'updated memory'>" <same files>
```

`commit` pulls `--rebase` and pushes after committing, by default — that
default is `commit_push=auto` in `.floppy/config`. A repository with no
remote configured at all sets `commit_push=never` there instead, so this
call stays entirely local rather than failing on the pull every time. For a
single call that should sync but not yet push, pass `--no-push`.

The whole read-only half of closing a session is that first call; the whole
writing half is the second. Each one used to be several separate commands —
the memory linter, a guard comparing the file list to what actually changed,
`git status`, `git diff --stat`, then staging, committing, pulling, pushing,
and releasing the lock. They were folded into two calls not to shorten the
output, which was already short, but because of what a session is actually
billed for.

**The turn is the unit, not the tool call.** Measured over 48 `/start` and
`/wrap` runs: reasoning costs about 649 tokens per turn, and parallel calls
issued together in one block cost as one turn. So wrapping calls in a script
pays off only where it removes a *turn* — four independent reads already
issued in a single block save nothing at all.

That is exactly what these two do. The steps they replace were not
independent: each one's result decided whether the next should run, so the
model had to stop, read, and choose between them — four separate turns before
anything was written, and six more after. Folding them removes those stopping
points. A skill that expands `check` and `commit` back into their individual
`git status` / `git diff` / lint calls puts every one of them back.

The larger arithmetic is worth knowing, because it is not intuitive: every
turn resends the whole window, so a session's bill is roughly turns × window
size, and the window only grows. The cost is quadratic in session length —
which is why the answer to a long session is to end it, not to economise
inside it.

(An earlier version of this passage explained the fold by "reasoning happens
before every tool call", citing 7.5k tokens across six calls. That framing was
superseded by the 48-run measurement above: it counted calls where it should
have counted turns. The conclusion held; the reason did not.)

The diff prints before the commit on purpose: closing happens right when the
human has stopped watching closely, so the file list and the size of the
change need to be visible in the conversation, not only in git history
afterward.

What a red `check` means:

- **quota** — not a bug, the memory grew past the ceiling in `quota.lock`.
  Raising the number is fine, but only in the same commit as the notes that
  needed the room, with the reason in the commit message. Before raising it,
  check whether something should be dropped instead — a note superseded by a
  later measurement should go, not sit next to its replacement.
- **someone else's note** — the linter reads the whole memory on disk, so it
  goes red on a neighboring session's unfinished write too. **Fix only what
  this session wrote.** Someone else's half-finished note is not yours to
  repair blind — name it in the report and leave it exactly as found.
- **this session's own file** — stop and fix it. The next session will not
  find a note that never got written correctly.
`git add -A` is never used — the tree can hold nested repositories and other
people's working copies; stage by naming the files.

## What wrap commits, and what it never touches

This rite commits **memory, docs, the current-state file, and the session
procedure itself** — nothing else. `guard` enforces this against a watched
path list, but the enforcement being in a script is not a reason to leave it
unsaid here: a limit only a script knows about is a limit nobody can reason
about ahead of the call that hits it. If the session also touched product
code, that stays uncommitted — name it in the report to the human and leave
it for them, don't fold it into this commit because it happened to be open
in the same session.

## Workplace memory is a second repository

If any of what got written lives in a workplace-wide private store (see
`agent-memory` — facts private to this project but shared across a
workplace's machines), that store is a **separate git repository**, and this
project's own `git status` says nothing about it at all. `check` reports its
state; commit and push it on its own, the same way as this repository — an
unpushed note there blinds the other machine exactly as an unpushed commit
here would, silently, with nothing in this repository's status to reveal it.

A workplace-wide store like this should carry a `pre-commit` hook that
refuses a commit containing a secret — check whether this one does before
assuming it; not every workplace repository has set that up. Where it
exists, take a refusal as correct, not as an obstacle: remove the value and
leave a pointer to where it actually lives instead of the value itself.
Never answer it with `--no-verify` — the hook exists for exactly the commit
it just stopped. Where it doesn't exist, be the guard yourself: read what
you are about to commit for anything that looks like a secret before it
goes in.

## Report to the human

Four short parts:

1. **What got recorded** — one line per fact, with its file path.
2. **What was deliberately not recorded**, and why — so they can object.
3. **What's left unfinished** — background jobs, anything uncommitted,
   anything waiting on a decision.
4. **Where the next session should start** — one phrase, in `start` terms.

If something looks like a scope decision — what can be shared, published, or
shown outside this project — **ask, don't decide it here**: that call
belongs to the project's owner. This isn't caution for its own sake: a rule
in this area that got decided out of caution, without asking, once had to be
rewritten together with the history it had already produced. Guessing at a
sharing boundary is not free to undo.
