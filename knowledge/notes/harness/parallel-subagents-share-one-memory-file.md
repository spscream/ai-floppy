---
name: parallel-subagents-share-one-memory-file
description: Subagents of one type write to one memory directory, so two lenses launched together overwrite each other's note — and the survivor may report a finding as a duplicate of something the reader never saw
area: harness
verified_on: 2026-09-06
verified_against: "Claude Code, two subagents of the same reviewer type launched in one message, writing under .claude/agent-memory/<type>/"
recheck: "Launch two subagents of one type in the same message, each told to write a memory note about its own findings, then list .claude/agent-memory/<type>/ and compare against what each reported"
invalidated_by: "The harness gives each concurrent subagent instance its own memory namespace"
---

# Two subagents of one type write to the same memory file

## The fact

Subagent memory is keyed by **type**, not by instance: every agent of a type writes into
`.claude/agent-memory/<type>/`. Two lenses of the same type launched in the same message
therefore write the **same file**, and the second overwrites the first.

The failure is not confined to a lost file. A subagent that reads that memory sees a
neighbour's note as its own past work, and can report a genuinely new finding as "a repeat of
an earlier round".

## Why it is not obvious

Parallel subagents are otherwise well isolated — separate context, separate transcript,
separate tool history — and memory reads as part of that per-agent state. Nothing in the
launch names a file, so nothing suggests two instances are sharing one.

Worse, the damage is quiet in exactly the direction that matters: the surviving note is
plausible and complete, just not the one the other agent wrote.

## Evidence

**OBSERVED**, 2026-09-06, with two review lenses running concurrently. Both wrote to one file
under `.claude/agent-memory/<type>/`; the second overwrote the first. The report survived only
because the agent noticed the overwrite itself, reconstructed the content from its index line,
and flagged two of its findings as "possibly a repeat". Had it not noticed, those two findings
would have read as already-known.

## How to re-check

Launch two subagents of one type in a single message, each instructed to write a memory note
naming itself. List the type's memory directory afterwards: one file, one author.

## What it costs you not to know

A finding marked "repeat of a previous round" by an agent that ran in parallel may mean
"repeat of my neighbour", not "already known". **Verify such a finding as if it were new.** In
a review fan-out that mark is exactly the one a reader skips.

The general shape: any per-type state shared by concurrent instances — memory, a scratch file,
a lock — turns parallelism into a silent last-writer-wins. If two instances must run together,
give them distinct output paths in the brief rather than trusting the default.

## See also

- [[subagent-memory-grants-write]] — the other surprise in the same memory feature.
