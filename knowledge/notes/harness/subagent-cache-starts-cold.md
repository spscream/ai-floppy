---
name: subagent-cache-starts-cold
description: A subagent's first turn reads zero tokens from cache — it cannot use the parent's prefix and pays to build its own, so delegation only pays back above that entry price
area: harness
verified_on: 2026-08-21
verified_against: "Claude Code, one general-purpose subagent on Sonnet, four turns; usage fields read per turn from the subagent transcript"
recheck: "Run any subagent, open ~/.claude/projects/<checkout>/<session>/subagents/agent-<id>.jsonl, and read message.usage on the first assistant turn: cache_read_input_tokens is 0 and cache_creation_input_tokens is the whole prefix"
invalidated_by: "The harness starts sharing a cached prefix across the parent/subagent boundary"
---

# A subagent's first turn reads nothing from cache

## The fact

Prompt caching is prefix matching, and the prefix is assembled in one order: `tools` →
`system` → `messages`. A subagent differs from its parent in all three — its own agent
definition, its own narrowed tool list, often its own model — and one differing byte
invalidates everything after it. So the subagent builds its own cache from scratch and
reads **zero** from the parent's.

From the second turn on it reads its own prefix and writes only the new tail. The parent's
cache is not damaged: the subagent is a separate call chain, and its report arrives back as
an ordinary suffix.

## Why it is not obvious

Everything else about a subagent is presented as being *inside* the session — it inherits
the working directory, it appears in the same transcript view, its report lands in the
conversation. Nothing about it suggests a separate billing prefix, and the cost is invisible
in the parent's own usage numbers.

## Evidence

**MEASURED**, 2026-08-21. One `general-purpose` subagent on Sonnet, four turns, numbers read
from the `usage` field of each turn:

| turn | cache write | cache read |
|---:|---:|---:|
| 1 | 26 553 | **0** |
| 2 | 3 828 | 26 553 |
| 3 | 1 034 | 30 381 |
| 4 | 1 230 | 31 415 |

**READ**, Anthropic's caching documentation: a side call — summarisation, compaction, a
subagent — misses the parent's cache when it rebuilds `system`, `tools` or `model` with any
difference at all.

Two traps that cost a wrong conclusion on the way to this number:

- **Subagent turns are not in the parent's file.** They live in
  `~/.claude/projects/<checkout>/<session>/subagents/agent-<id>.jsonl`. Searching the parent
  transcript for `isSidechain` finds nothing *even in sessions where subagents ran* — the
  first attempt concluded "no subagents" from that zero while the `subagents/` directory sat
  beside it. Detect by directory, not by flag.
- **Do not sum `cache_creation_input_tokens` across turns** as a cost estimate. It overstates
  roughly fivefold, because a moved cache point rewrites the same prefix. The table above
  reads each turn separately.

## How to re-check

Run one subagent, find its `agent-<id>.jsonl`, and read `message.usage` on the first
assistant turn. `cache_read_input_tokens: 0` with a large `cache_creation_input_tokens` is
the whole claim.

## What it costs you not to know

Entering a subagent costs a full prefix write at the 1.25× rate — about 27k tokens for the
type measured, so roughly $0.17 on Opus pricing. Delegating a *small* read is therefore a
loss: you pay the entry price to save a few thousand tokens in the parent. Delegation pays
when the subagent will read substantially more than its own entry price, or when its output
would otherwise sit in the parent's context and be re-read by every later turn.

The number is one run of one subagent type. 26.5k is that type's prefix, not a constant.

## See also

- [[bash-file-reads-are-not-deduplicated]] — the other half of the same budget: what actually
  fills a parent's context.
- [[compaction-keeps-only-the-stable-prefix]] — the same prefix rule seen from the compaction
  boundary.
