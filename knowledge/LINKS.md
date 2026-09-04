# Existing practice: agent memory and shared knowledge bases

A survey of what already exists, so this repository does not rebuild it. Assembled
**2026-09-05** from a web search plus the official Claude Code documentation. Each entry
says what the thing actually is and where it stops being useful — the second half is the
point, since the reason to catalogue prior art is to find the hole.

Everything below is a secondary source unless marked otherwise. Re-check before relying
on a version number: this field moves monthly.

---

## 1. Native: per-subagent memory in Claude Code

Since **v2.1.33** (February 2026) a subagent definition may carry a `memory:` frontmatter
field with scope `user`, `project` or `local`. Claude Code then provisions a persistent
markdown directory — `~/.claude/agent-memory/<name>/` for user scope,
`.claude/agent-memory/<name>/` for project scope — and injects the first 200 lines of its
`MEMORY.md` into that agent's system prompt on every invocation. The agent gets
Read/Write/Edit inside it, so it curates its own notes.

Primary source: the [subagents documentation](https://code.claude.com/docs/en/sub-agents).

**Where it stops.** The store is per-agent, so a `code-reviewer`'s memory is invisible to
a `security-auditor` and vice versa. Sibling agents re-derive each other's findings, and
sequential agents re-derive their predecessor's. The problem has a name in the community
now — [subagent memory siloing](https://hindsight.vectorize.io/blog/2026/05/06/claude-code-subagents-shared-memory).

**Relevance here.** This is storage for what *one agent* learns about *one project*. It
is not a place for findings that outlive either.

---

## 2. Native: team memory sync

A repository-scoped, server-synced key-value store shared by authenticated users of an
organisation working in the same repo. A [teardown of the implementation](https://jakegoldsborough.com/blog/2026/inside-claude-codes-team-memory-sync/)
describes roughly 800 lines of TypeScript: sync engine, file watcher, secret scanner,
path validator, prompt integration. Writes propagate to other people's sessions. The
model routes content by kind — user preferences stay private, project patterns go to the
team.

**Where it stops.** Scoped per repository and per organisation. Good for "how *we* build
*this*", useless for "how the tool behaves".

**Worth stealing:** the secret scanner. Any shared memory needs one, and the failure it
prevents is unrecoverable — a leaked credential does not un-leak after `git rm`.

---

## 3. Pattern: a git repository as the shared brain

Point every agent and every tool at one dedicated repository holding architecture
decision records, prompt libraries, harness definitions and active project context.
Described at [The Git-Backed Brain](https://kidakaka.com/2026/05/31/the-git-backed-brain/).
The argument for git specifically is that agent memory *evolves*: you want history,
blame, and review on it, not a database row that silently changes.

**Where it stops.** The pattern says where to put the bytes and stops there. There is no
admission test, no expiry, no answer to "this note is fourteen months old, is it still
true". That gap is the reason for this repository's three-condition rule and
`bin/rot-check.py`.

---

## 4. Pattern: the LLM wiki (Karpathy, January 2026)

Have the model incrementally maintain a cross-referenced markdown wiki sitting between
raw sources and the agent, so that synthesis **accumulates** instead of being re-derived
per query. Explicitly positioned against RAG, which recomputes context every time and
therefore never gets smarter. Implementations are collected under the GitHub topic
[`claude-code-memory`](https://github.com/topics/claude-code-memory), including
local-first knowledge-graph builders.

**Where it stops.** Accumulation without pruning is the failure mode, not the goal. A
wiki the model appends to forever becomes a corpus nobody can route through, and the
model pays to read it every session. Any use of this pattern needs a ceiling and a
deletion rule attached from day one.

---

## 5. Third-party memory backends

- **Mem0** — vector embeddings plus optional knowledge graph, with an official MCP
  server; described in 2026 surveys as the most mature of the three.
- **Zep / Graphiti** — memory as a *temporal* knowledge graph, facts carrying validity
  windows. The closest existing thing to the rot problem: it models "this was true then".
- **Letta** — the agent manages its own memory through explicit tools rather than a
  framework doing it behind the agent's back.

**Where they stop.** All three are infrastructure. They answer storage and retrieval; the
question of what deserves to be stored is left to you, and it is the expensive question.

---

## 6. Emerging: publishing the harness itself

An [arXiv paper on personal AI agent harnesses](https://arxiv.org/pdf/2604.11548) notes a
shift toward publishing a whole working configuration — identity file, memory
organisation, skill loadout, scheduled tasks — as a template others instantiate and
personalise. The unit of sharing becomes the harness, not the snippet.

**Relevance here.** This is the closest existing form to what this repository is. The
difference is scope: a template is "here is my setup"; this is "here is a fact about the
tool, with the evidence, so you can check it against yours".

---

## 7. Background reading

- [Building a Persistent Knowledge Base for Claude Code](https://puvaan.dev/posts/building-a-persistent-knowledge-base-for-claude-code/)
  — one practitioner's build, session amnesia to compounding context.
- [How to Build a Persistent Memory System for Claude Code Agents](https://www.mindstudio.ai/blog/persistent-memory-system-claude-code-agents)
  — vendor-adjacent overview.
- [claude-code-best-practice / claude-agent-memory.md](https://github.com/shanraisshan/claude-code-best-practice/blob/main/reports/claude-agent-memory.md)
  — community notes on agent memory.

---

## What is missing from all of it

Every entry above answers **where the bytes live**. Not one of them answers:

- **what earns a place** — an admission test, applied before writing, not after the
  store is full;
- **what a note must carry to stay checkable** — the version it was verified against and
  the command that re-verifies it;
- **how the store is kept from growing past what a session can afford to read** — a
  ceiling, a per-note cap, and the rule that raising either is a deliberate, reviewable
  act rather than a fix for a red check;
- **what to do with a note that is old** — since "old" and "wrong" are different things
  and only a human can tell them apart.

Those four are the contribution. See [CONTRIBUTING.md](CONTRIBUTING.md).

---

## Verification

| what | how it was established | date |
|---|---|---|
| subagent `memory:` field, scopes, 200-line injection | official docs, primary | 2026-09-05 |
| everything in §2–§7 | secondary sources, listed above, not independently reproduced | 2026-09-05 |

Re-check the whole file when a Claude Code minor version lands; §1 is the entry most
likely to have moved.
