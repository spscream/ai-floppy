---
name: compaction-keeps-only-the-stable-prefix
description: After a compaction boundary only the stable prefix — 15–31k tokens of system prompt, tools and rules — is read from cache; everything else is written again, so delaying a compact to protect the cache protects nothing
area: harness
verified_on: 2026-09-08
verified_against: "Claude Code, 12 compaction boundaries across every project on one machine; message.usage read on the turns either side of each subtype: compact_boundary record"
recheck: "grep the session transcripts for records with subtype compact_boundary, then compare cache_read_input_tokens on the turn before and the turn after each one"
invalidated_by: "The harness begins carrying the post-compaction context as a cached prefix rather than rewriting it"
---

# Compaction does not carry the cache across the boundary

## The fact

After a compaction boundary the next turn reads only the **stable prefix** from cache —
system prompt, tools, rules, everything up to the first break point, measured at **15–31k
tokens**. The compaction summary and everything after it is written as new cache creation.

This is the documented, correct behaviour rather than a defect: Anthropic's server-side
compaction beta describes putting `cache_control` on the system prompt separately so that
"only the compaction summary needs to be written as a new cache entry". Claude Code does
that. There is nothing to fix.

## Why it is not obvious

The instinct is to postpone a compact — the context is expensive, the cache is warm, why
throw it away. But the cache is not thrown away *by* the compact; it does not survive one
under any strategy. Meanwhile the delay is paid on every turn, at full context.

## Evidence

**MEASURED**, 2026-09-08, twelve boundaries across every project on disk:

```
project                    trigger      pre   read before  read after  write after
work-janus                 auto   1,008,114      834,441      18,465      281,798
work-messaging             manual   953,367      952,445      19,866       34,038
service-vps-inventory      manual   793,275      790,746      15,458       39,186
work-agents-harness        manual   250,330      247,335      30,720       45,081
work-agents-harness        manual    96,696       93,611      30,720       45,375
```

Two boundaries in one session returned an identical `read` of 30 720 — that is the unchanging
prefix, visible twice. Two of the twelve returned `read = 0`: the cache TTL expired between
the call and the continuation. The normal 125–130 s a compact takes fits inside the TTL.

The two `auto` boundaries with a much larger write after (282k, 403k) are not a property of
the mode — a large skill injection landed in the retained tail.

## How to re-check

Find the `subtype: compact_boundary` records in `~/.claude/projects/*/*.jsonl` and read
`message.usage` on the turns either side. Note that an `isCompactSummary` record is written
as a pair with it; counting both doubles your boundary count.

## What it costs you not to know

Two decisions come out wrong.

**Delaying a compact to protect the cache** buys nothing and costs the difference between a
full-context read and a small one on every turn until you give in. At the measured rates a
compact costs roughly $0.5 on Opus — the write, the summarisation read, and about 5k of
output — against ~$0.12 per turn just to read a 250k context. It pays for itself in about
five turns, and on a 950k session in under two.

**Reasoning about a session's cost from the cache-write column** also goes wrong, for the
same reason the numbers above are read per turn rather than summed.

## See also

- [[subagent-cache-starts-cold]] — the same prefix rule at the other boundary the harness
  draws.
