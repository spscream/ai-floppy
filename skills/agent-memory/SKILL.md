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
(`chars_max` for the whole corpus, `note_chars_max` for one note,
`pointers_max` for one index, `pointer_line_max` for one pointer line) that
bound how large the memory is allowed to get before something has to give.

A fifth is optional and per-half: `half_chars_max.<half>=N` bounds one half of
the tree on its own (`half_chars_max.root` covers the notes sitting directly in
the memory directory). A half with no key is not bounded, so setting none keeps
the old behaviour exactly. Reach for these when the corpus cap keeps tripping on
sessions that did not fill it: on a repository worked from two machines, the
half that grew and the session that hits the ceiling routinely belong to
different people, and one number for the whole corpus cannot say which is which.
When the corpus cap does trip, the linter now prints the per-half breakdown
beside it, whether or not any per-half key is set.

**Every ceiling warns at 96% before it refuses at 100%.** The run still passes;
`lint` prints a `!` line naming the ceiling and, for the corpus one, the
breakdown by half. This is what you act on: at a warning the fix is still small
and still yours — drop what went stale, split the note you are writing, plan
the sub-index. Wait for the refusal and it lands on whichever session crosses
the line, which on a memory written from two machines is routinely not the one
that filled it, and that session may not raise the ceiling (the ratchet below)
nor prune a neighbour's notes (the wrap rite). `pointer_line_max` has no band:
it bounds one line, and a line near the limit is a line that fits.

All of them are facts about **this** corpus, which is why they live with the
memory. The one size limit that is not — the ceiling on the index the harness
loads into every session, which it truncates in silence — is a fact about the
harness and lives in `.floppy/config` as `index_chars_max`, with a default
shipped by the plugin. Asking a project to measure that one would be asking it
to measure somebody else's tool.

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

## The memory may not live in this repository at all

Where `memory_dir` points is a layout decision, not something to assume. Some
repositories cannot hold agent notes — a checkout the team does not own, or a
policy separating notes from code — so `memory_dir` is a symlink into a
separate git repository and is gitignored here. The first scope above is then
hosted elsewhere; it is still this project's memory, not the workplace store.

Wiring that up is `bash .floppy/run store`, once per machine and per worktree;
`init --memory-repo … --memory-key …` does it at setup time. The state to know
about is the half-done one — the ignore line added, the symlink never created —
because it is comfortable: notes are written and read normally while nothing
will ever commit them. `guard` fails on that combination by name.

Nothing about writing a note changes: same paths, same index, same frontmatter.
Two things about **closing** a session do, and the shim handles both — `check`
prints a `memory store` section, because this repository's own diff cannot see
the notes, and `commit` commits and pushes that store from the same file list.
What you must not do is conclude from a clean `git status` here that the
session left nothing behind: in this layout that is exactly what a clean status
looks like while every note is still uncommitted.

## Three status genres — and why they stay three files

A repository following this convention keeps three documents about its current
state, deliberately not merged into one:

- a **project current-state file** (`statuses_now`) that a session start reads
  whole — rewritten in place, so it always answers "what's true right now"
  without a reader needing to reconstruct it from history. What is true about
  the project: frozen decisions, what is red, what waits on the human, metrics
  with their regression marks;
- a **personal current-state file** (`statuses_personal`) — the same shape, one
  scope narrower: the working state of one person on one machine, what they
  were mid-way through and where to resume. It defaults into the private scope
  under `machines/<name>/`, so no other machine writes that path;
- an **append-only dated journal** — grows one section at a time, holds the
  why and the numbers behind a change, and is opened only for the section a
  session was pointed at.

The first two split for a reason the memory learned earlier. A current-state
file is the one artefact rewritten *whole* on every wrap, so two sessions
overlapping in it conflict, while a note collides with nothing by construction
and an index merges. Most of what forced those rewrites was personal — a
thread of work that changes every session and is shared with nobody. Separated,
it never needs merging; what stays in the shared file changes rarely enough
that two sessions rarely meet in it. The split is structural, not a matter of
tidiness: a private working note written back into the shared file re-creates
the collision, on the document a stranger reads first.

The journal stays separate from both because it wants the opposite thing from
a writer: a current-state file wants to be overwritten so a stale claim cannot
survive in it, while the journal wants every entry preserved so a past number
or a rejected hypothesis is never lost to a later edit. A single file trying to
satisfy both ends up serving neither — the cost of starting a session would
then depend on how much got written into yesterday's entry, and a big day
would tax every session after it.

None of the three covers two people wrapping at the same moment on two
machines. The wrap lock serialises one machine, and across machines git hands
back a merge conflict rather than arbitrating silently. Splitting the personal
half out shrinks how often that happens — it does not close it.

## Language

Everything this plugin ships — scripts, shim output, these skills — is
English, because it is meant to travel between projects unmodified. The
memory notes it manages are not: their language is the consumer's own
choice, set once as `memory_language` in `.floppy/config`. Neither of those
settings decides the language a session answers its human in — that follows
the human, in every session, and is not configured anywhere. State this
plainly so a future session does not "fix" it by wiring a language setting
to the reply language; there is nothing to wire.
