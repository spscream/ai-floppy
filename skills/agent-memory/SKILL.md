---
name: agent-memory
description: Conventions for the durable session memory this toolkit keeps — one fact per file, note frontmatter and metadata.evidence, the three-level index tree, the quota.lock ratchet, and which of project/workplace/machine scope a fact belongs to. Load this before writing, moving, or reorganizing a memory note, or whenever start/workstatus/wrap need the ground rules — they assume these conventions rather than restate them.
---

# Agent memory

This is not a rite like `start`, `workstatus`, or `wrap`. It has no steps of
its own and nothing runs at the end of it. It is the set of conventions the
other three assume: what a note looks like, where it lives, and how a session
knows it can trust one.

The memory lives under one configured directory — `memory_dir` in
`.floppy/config`, a repository default such as `.agent-memory`. Everything
below calls that directory "the memory directory" rather than naming it,
because the name is the consumer's choice, not this plugin's.

## One fact per file

A memory note holds exactly one fact. A refinement of an existing fact edits
the file that already states it — it does not add a second file next to it.
Before writing a new note, check whether one already covers the ground.

## Note frontmatter

Every note opens with:

```
---
name: <slug, matches the filename without .md>
description: <one line, what the note is about>
metadata:
  type: user | feedback | project | reference
  evidence: measured | read | decided | sourced
---
```

`name` is the slug `[[wikilink]]`-style references resolve by, not the file
path — so moving a note between directories does not break links to it, as
long as the slug stays put and stays unique across the whole memory.

## `metadata.evidence`: four values, chosen on purpose

`evidence` records where a claim came from, not how important it is:

| value | when it applies |
|---|---|
| `measured` | verified against reality — a run, a profile, an incident that happened |
| `read` | taken from code, a spec, or docs — true until something runs and says otherwise |
| `decided` | a choice or an agreement; evidence does not apply, a date and an author do |
| `sourced` | an outside claim checked against its primary source, quoted and dated |

**If unsure, write `read`, and say in the note's body what a measurement
would need to confirm it.** The expensive mistake runs the other way: marking
`measured` something that was in fact only read turns a guess into a fact for
whichever session reads it next, and nothing downstream can tell the
difference once it's written down.

## The index is a tree, three levels deep

```
<memory_dir>/MEMORY.md                    root router
<memory_dir>/<half>/INDEX.md              half index
<memory_dir>/<half>/<group>/INDEX.md      sub-index
```

The root file (`MEMORY.md`) is a **router**, not a table of contents: it
holds only the notes worth reading in every task, plus one link per half. It
stays small on purpose. The session loader that pulls it into every fresh
session truncates it past a size limit and does not say so — a note past the
cut is not read, and every other check can pass while that happens. Keeping
`MEMORY.md` thin is the only defense; there is no error to catch the loss
after the fact.

A half opens its own `INDEX.md` as a second step, only when the task belongs
to that half. A half that outgrows its pointer budget splits into
sub-indexes rather than growing a longer index — that split is the third
level, and it is the last one. Depth stops at three levels not because of a
technical ceiling, but because three is the number of files a session opens
before it reaches a note (router → half → note, or router → half → sub-index
→ note), and a fourth hop has never been measured to still get read. A note
nested deeper than a sub-index can reach is unreachable in practice, whatever
the file tree says.

## The `quota.lock` ratchet

The memory directory can hold a `quota.lock` — plain `key=value` numbers
(a total character budget, a per-note character cap, a pointers-per-index
cap) that bound how large the memory is allowed to get before something has
to give.

**This file is not shipped by the plugin and not copied from one project to
another.** Its numbers come from measuring the consumer's own corpus — a
ceiling copied from a different project is that project's ceiling, which is
the same as having none at all: it bounds nothing about the memory actually
in front of you.

Raising a number is allowed, but only in the same commit as the notes that
needed the extra room, with the reason written into the commit message. A
ratchet edited on its own, "to make the check pass," defeats the reason the
file exists.

## Scope: where the fact is true, not whether it is secret

A fact belongs to one of three places, and the test is **where it is true**:

- **the repository's own memory** (`memory_dir`) — true about this project,
  travels with `git clone`, read by anyone with the repo;
- **a workplace-wide private store** — true across the machines of one
  workplace but not committed to this repository: another project's memory,
  or a fact private to this project that still needs to reach a second
  machine (someone's checkout path, a branch, an access note);
- **machine-bound** — true on one machine only (a local port, a disk name, a
  path that differs elsewhere) and never committed anywhere.

Confusing "private" with "machine-bound" is the mistake this scope exists to
prevent: a fact can be private to a workplace and still need to sync between
that workplace's machines, which a plain `.gitignore`'d local directory
cannot do.

## Two status genres — and why they stay two files

A repository following this convention keeps two documents about its current
state, deliberately not merged into one:

- a **current-state file** that a session start reads whole — rewritten in
  place, so it always answers "what's true right now" without a reader
  needing to reconstruct it from history;
- an **append-only dated journal** — grows one section at a time, holds the
  why and the numbers behind a change, and is opened only for the section a
  session was pointed at.

They stay separate because they want opposite things from a writer: the
current-state file wants to be overwritten so a stale claim cannot survive
in it, while the journal wants every entry preserved so a past number or a
rejected hypothesis is never lost to a later edit. A single file trying to
satisfy both ends up serving neither — the cost of starting a session would
then depend on how much got written into yesterday's entry, and a big day
would tax every session after it.

## Language

Everything this plugin ships — scripts, shim output, these skills — is
English, because it is meant to travel between projects unmodified. The
memory notes it manages are not: their language is the consumer's own
choice, set once as `memory_language` in `.floppy/config`. Neither of those
settings decides the language a session answers its human in — that follows
the human, in every session, and is not configured anywhere. State this
plainly so a future session does not "fix" it by wiring a language setting
to the reply language; there is nothing to wire.
