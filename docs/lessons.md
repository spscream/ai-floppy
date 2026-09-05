# Lessons

Things this plugin learned the expensive way. Each one is a decision or a
failure that shaped the code, written down so the next change does not repeat
it. The design these refer to is in [memory-model.md](memory-model.md).

**What is here and what is not.** These are lessons about *floppy* — a reader
who does not use it has no use for them. A lesson that turns out to hold
regardless of floppy belongs in the knowledge base instead
([knowledge/README.md](knowledge/README.md)), which carries a verification
contract this file does not: a date, the environment, and a way to re-check.
Two lessons moved there on 2026-09-05 — `find` not following a symlinked root,
and the test suite hanging on an unclosed stdin. Neither was about this plugin;
both were about the ground it stands on.

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

## Folding calls removed the turns it aimed at, and wrap still doubled

Measured 2026-09-05 over **48 `/wrap` runs** in two consumer repositories,
classifying every assistant turn by the tools it used — then recounted the same
day, because the first pass counted the wrong unit. A turn is one request to the
model; in the JSONL it is several entries sharing a `requestId` and one `usage`
block, so text, reasoning and a tool call from one reply are three entries and
one paid turn. Counting entries inflates by 1.6x. Everything below is by
`requestId`, with the entry counts beside it because the first version of this
lesson shipped with those.

| median turns per wrap run | by `requestId` | by transcript entry |
|---|---|---|
| before 2026-08-25 | **12** | 20 |
| after | **25** | 41 |
| the other consumer, after | 29 | 49 |

**What survived the recount** is the lesson itself, and it never depended on the
unit. The fold of ten commands into `check` and `commit` did what it set out to
do — calls to the pre-plugin `tools/*.sh` were **29% of turns before 2026-08-25
and zero after** — and the total doubled anyway on the unit that is billed. Not
the fold's doing: a lot landed on the same day, as memory moved into a second
repository, the state file split from the journal, and indexes became a tree.
Wrap acquired work rather than shedding it.

**What the recount overturned**, both times in the direction of "the cheap thing
is not the cheap thing":

- *"The verbs that replaced the scripts are 3.6% of all turns, so the mechanical
  half of wrap is nearly free."* On the billed unit, `.floppy/run` verbs are
  **5.1 turns per run — 23% of all turns**, the largest single category, ahead of
  note edits (3.9), other `Bash` (4.0) and state-file edits (2.6). About half of
  it is redundant: runs call `lint`, `guard` and `status` **on top of** `check`,
  which has already run all three. One run recorded `check`×4 and `lint`×3.
- *"17% of turns call no tool at all — narration, the cheapest turn to remove."*
  On the billed unit that is **5.6%** (34 of 608), and all 34 are the **last**
  turn of a run: the report to the human. Mid-run there are none. Of the 389
  entries carrying no tool call, 267 carry no text either — they are reasoning
  blocks of turns already counted. There is nothing there to cut.

**Unaffected by the recount:** delegating the mechanical half of wrap to a
subagent still does not pay. Dispatching one and reading its report is two turns
in the large window in exchange for two turns that print almost nothing — an
argument about turn arithmetic, not about the size of the mechanical half, so
the 3.6% → 23% correction does not revive it.

Three things follow:

- **the unit to count is the turn, and a turn is a `requestId`, not a transcript
  line.** "We folded ten calls into two" was true and did not make wrap cheaper,
  because nobody re-measured the total afterwards. A fold that hits its target
  while the total doubles is indistinguishable, from the bill, from no fold at
  all — but only when the total is measured in the unit that is billed;
- **the reduction to make is verbs beyond `check`**, not narration. `check`
  already runs `lint`, `guard` and `status`; a skill that calls them again pays
  for each one. Independent calls belong in a single block, and the state file
  should be written once rather than repaired line by line;
- **a written-down trap does not protect whoever counts around the fixed tool.**
  The 1.6x entry-doubling was already known and already fixed — in a consumer's
  own cost script, weeks earlier. The first pass here re-derived the bug with an
  ad-hoc script that did not carry the fix.

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

## A test that recomputes the rule agrees with any rule, including a wrong one

The general form of this is old and in every book about testing. What is
written down here is not the maxim — it is that this repository **argued its
way into the exception, in writing, in the same release that fixed the same
class of bug**, and paid for it twice within a day.

`tests/test-memory-link.sh` needed to know where Claude Code puts a project's
memory directory, so it computed the answer the way the script computes it:

```sh
enc="$(printf '%s' "$repo2" | tr '/.' '--')"
```

**2026-09-05, first bite.** 0.16.1 fixed `link` for a checkout path containing
`_`, which the harness folds like `/` and `.` and the script did not. Nothing
had been red. The script created the directory it had computed and reported
success, `--check` agreed because it asked the same line, and `status` reported
the wiring as present — while two of one machine's three consumers wrote memory
into a directory the harness never opens, one of them across fifteen sessions.
The test agreed throughout, because it derived its expectation by performing the
subject's transformation.

The regression test for that release asserted the **result** instead — a
hardcoded directory name — and its comment said so, explicitly, while excusing
the line above it:

> line 30 above still does exactly that, deliberately — it only needs to agree
> with the script, not to judge it

**2026-09-05, second bite.** That reasoning survived nine hours. macOS CI began
failing and passing on the same commit: its `TMPDIR` is
`/var/folders/<random>/T/`, the random component carries `_` some of the time,
and on those runs the test's pre-created directory landed where `--check` no
longer looked. Linux never showed it — `TMPDIR` there is `/tmp`. A red `main`,
and a job that reads as flaky when it is perfectly deterministic on an input
nobody was looking at.

Why the excuse was wrong. "It only needs to agree with the script" is true and
useless: agreement is exactly what a wrong rule also produces. A check derived
from its subject has no opinion about the subject. It reports whether the code
is self-consistent, which it always is, and the moment the rule moves the check
moves with it — silently, in the same commit, with no diff to review, because
the two copies of the rule are in different files and only one of them was
edited.

**Rule: build the state, do not address it.** The fix wires the repository, asks
the filesystem which directory the script actually made, and replaces it with a
directory. The test no longer contains the encoding rule in any form, so it
cannot hold a stale copy of one.

Three things follow:

- **a test may not re-derive the value it is checking.** Assert a literal, or
  read the artefact back out of the world. If the expected value is expensive to
  write down, that cost is the test doing its job;
- **"it only needs to agree" is the sound the trap makes.** The same sentence
  fits every tautological check ever written, which is why it convinces. Treat
  a written justification for recomputation as a defect report, not as a comment;
- **falsify the replacement.** Both fixes on 2026-09-05 were checked by putting
  the defect back and confirming the test went red. Replacing a check that
  agreed with anything by a check that passes for a different wrong reason is
  the same bug with new spelling, and nothing else in a green run distinguishes
  them.

This is the same blindness as `form-checks-cannot-see-false` in the
[knowledge base](knowledge/README.md), one level down: there a linter sees a
note's shape and not its truth, here a test sees the code's self-consistency and
not its correctness. Both stay green by construction.
