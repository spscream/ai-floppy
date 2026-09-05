---
name: subagent-memory-grants-write
description: Adding `memory:` to a subagent grants it Write and Edit over the whole workspace, whatever its `tools:` list says
area: harness
verified_on: 2026-09-05
verified_against: "Claude Code 2.1.232, Linux 6.18 (WSL2), subagent with memory: project"
recheck: "Give a subagent `tools: Read, Bash` plus `memory: project`, ask it to Write a file outside its memory directory, and compare md5 before and after"
invalidated_by: "The harness confines memory-granted Write/Edit to the memory directory"
---

# A read-only subagent stops being read-only the moment you give it memory

## The fact

Setting `memory:` in a subagent's front matter **automatically enables Read, Write and
Edit**, even when the `tools:` list omits them. The granted write access is **not confined
to the memory directory**: the subagent can overwrite any file its permissions allow. The
documentation is explicit that the confinement is *behavioral* — the system prompt tells
the agent to use the tools for memory — and not technical.

So an agent designed as read-only, with writing tools deliberately withheld, silently
becomes a writing agent when you add memory to it.

A `PreToolUse` hook in the same front matter restores the boundary for `Write` and `Edit`.
It does not cover `Bash`, which can write with a redirect and needs no tool at all.

## Why it is not obvious

The withheld tool list reads like a guarantee, and for a while it is one. Memory looks
like an orthogonal feature — a place to keep notes — so nothing about adding it suggests
a change in what the agent may touch. Both halves of the surprise are quiet: no warning
when the capability appears, and the agent's own brief keeps asserting the old promise
until somebody rewrites it.

## Evidence

**MEASURED**, three probes in one session, each with md5 before and after.

Declared `tools: Read, Grep, Glob, Bash` plus `memory: project`. The agent's actual tool
list came back as `Read, Bash, Write, Edit`.

Three files inside the workspace, one per method — every one overwritten, no refusal:

| method | md5 before | md5 after |
|---|---|---|
| `Write` | `d16f60c9…` | `ce033178…` |
| `Edit` | `64f89e57…` | `79780e49…` |
| `Bash` (`printf >>`) | `8dfe8829…` | `2cf5c238…` |

After adding a `PreToolUse` hook on `Write|Edit|MultiEdit|NotebookEdit` that denies paths
outside the memory directory, the same `Write` was refused with the hook's own text and
md5 was unchanged. The hook's invocation log showed one denial for the repository file
and two passes for files inside the memory directory — so it fired and discriminated,
rather than the agent simply changing its mind.

**READ**, primary source: the [subagents documentation](https://code.claude.com/docs/en/sub-agents)
— "Read, Write, and Edit tools are automatically enabled", and the restriction "is
behavioral … rather than technical".

**Negative control, MEASURED.** The same probes showed `Grep` and `Glob` missing from the
agent's tools, which looked like memory replacing the declared list. A `general-purpose`
agent with `tools: *` and no memory at all was asked the same question and also lacked
them. Their absence is a property of subagents in this version, not of memory. Without
that control this note would have carried a second claim that is false.

## How to re-check

Declare a subagent with `tools: Read, Bash` and `memory: project`, ask it to `Write` a
scratch file outside its memory directory, and compare md5 before and after. Ask it to
list its own tools in the same run: `Write` and `Edit` appear there without being
declared.

One operational detail seen but not explained: the hook did not take effect on the first
invocation after it was added, and did on a later one. Treat a fresh session as the
reliable way to know whether a front-matter hook is active.

## What it costs you not to know

An agent you built to be incapable of changing the code can change the code. The specific
shape: a reviewer given `Bash` so it can measure rather than guess, then given memory so
it can accumulate what it found, is by construction able to rewrite the repository it is
reviewing — while its own brief tells it, and you, that it cannot.

Nothing warns you, and the failure mode is not a refusal but an edit you did not ask for
in a run you were not watching.

Two things follow:

- **`tools:` is not a sandbox.** It is the list the model is offered, and other front
  matter can extend it. If a restriction matters, enforce it with a hook and test that
  the hook fires — the log of an invocation is the evidence, not the absence of damage.
- **A guard that omits `Bash` should say so where it is declared.** A boundary described
  more broadly than it holds is worse than no boundary: people plan around the description.

## See also

- [[opus5-subagent-prompt-line]] — the other subagent behaviour that no configuration
  file describes.
