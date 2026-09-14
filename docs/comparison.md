# Floppy among the memory systems

An honest comparison of floppy's memory with the main agent-memory systems:
what they do well, what floppy already has, what was taken from them — and
what the measurements say about quota limits and the note-saturation ceiling.

Reference point: floppy's own benchmark (83 questions, 2026-09-09). External
data: a web survey from 2026-09-13, sources at the bottom. Adoption statuses
checked against the code of 0.24.1 (2026-09-14). An earlier survey of
*adjacent* practice — subagent memory, team sync, the git-as-brain pattern,
with a short section on three of the backends below — is
[knowledge/LINKS.md](https://github.com/spscream/ai-floppy/blob/main/knowledge/LINKS.md);
it carries its own hand-written verification table, dated 2026-09-05.

## The verdict, short

**The field is moving towards us, not we towards it.** Letta — the most
research-driven system of the eight — moved to git-versioned markdown files
("MemFS") in 2026; Anthropic documented index-plus-leaves as the auto-memory
convention. Files + git + a small hot index is mainstream doctrine now, not
this project's eccentricity.

**Floppy's unique parts held up.** Selection at write time ("what deserves a
note"), the quota ratchet, and `evidence`/`as_of` per note exist in none of
the systems surveyed. Mem0 v3's retreat (dropping the LLM judge on the write
path) and practitioners' "mush of fragmented facts" are direct confirmation
that automatic capture without selection does not work.

**The consolidation gap is closed since 0.22.0–0.23.0.** In the first version
of this survey it was the one class of mechanism floppy lacked entirely; now
all three exist: merge-at-write (an `agent-memory` rule, 0.22.0), the
`consolidate` rite and the heat log of note reads (0.23.0). The first consolidate pass ran
on 2026-09-13: −4.1k characters without raising a quota.

**The saturation ceiling is real and measured** (context rot, memory
saturation) — but for name-based routing it shows up as index capacity, not
corpus capacity. The scarce resource is characters loaded every session, not
characters on disk.

**Our own benchmark says the bottleneck is capture** — not storage and not
retrieval. All 12 failed questions were never written down; not one was
written and then missed. Work on quotas and indexes will not move the 43%;
the habit of writing at the moment of the event will.

## The reference point: what we know about our own memory

Floppy is file memory: one-fact-per-file markdown notes with frontmatter
(`type`, `evidence`, `as_of`), a three-level index tree (router → half →
sub-index), scopes for *where a fact is true* (project / workplace / machine /
common), a `quota.lock` with a ratchet rule, and the start / workstatus / wrap
rites where an agent with a human in the loop does the selection. Storage is
git; reading is navigation by name, no embeddings. 0.23.0 added two mechanisms
this survey originally found missing: **heat** — a machine log of notes
actually opened (`date slug` lines in `.floppy/heat.log`, with `lint` naming
the never-opened on top of it), and the **consolidate** rite — a pass over one
half of the corpus that proposes merges, rewrites and deletions from collected
evidence (`as_of`, the cold list from heat, wikilink overlap); a human
approves each change, and an empty pass is a valid outcome.

On 2026-09-09 we ran the only first-party benchmark in this comparison:
83 questions from 19 real sessions, golds from the transcripts, two arms
(a clone without the memory and a clone with it), a blinded judge.

On average the memory adds nothing (+3.6 pp, p=0.61) — but on the quarter of
questions where the repository is silent it is the only source: **10% → 43%**
(p=0.016). Inside the memory the status file does the work: `NOW.md` was cited
17 times, six notes once each, fourteen never. All 12 failures were facts
nobody wrote; zero were "written and not found". (One run, sonnet answering
and judging — a lower bound, not a precise number. The notes:
`floppy-memory-lifts-only-where-the-repo-is-silent`,
`the-status-file-carries-the-memory-not-the-notes`,
`the-ceiling-is-capture-not-retrieval` in this repository's `memory/` half.)

Quotas as of 2026-09-14: `chars_max=75000` (raised three times over the week
of 09-05..09-09, each time by the rule "corpus + 10%, in the same commit as
the notes that needed the room"; at the last raise an honest pruning pass
found nothing to drop), `pointers_max=25` — when the flat index reached it,
the index was split into three halves rather than raised. Since then the
ratchet has a third answer between raising and pruning: the first consolidate
pass over `product/` (2026-09-13) produced one merge, one deletion with its
replacement named, two rewrites in place and one declined merge recorded with
its reason; the corpus went 71649 → 67545 against 75000, and no `quota.lock`
number moved.

## The field: eight systems

### Letta (ex-MemGPT) — agent runtime, tiered memory

Three tiers: *core memory* — small blocks pinned into the context, edited by
the agent itself; *recall* — the whole history in Postgres; *archival* —
pgvector, read through tool calls. Sleep-time agents rewrite the blocks in the
background (~5× less inference compute — vendor's number). Then the early-2026
turn: V1 archived, the new Letta Code stores memory as git-versioned markdown
("MemFS").

Strong: the best transparency of the eight — the context is visible and
editable in full; their own debunking benchmark — an agent with plain files
scores 74% on LoCoMo, above the vector systems; background consolidation as a
shipped, working mechanism.

Weak: memory quality is hostage to tool-calling reliability; archival has no
deduplication or consolidation (their issue #3116 admits duplicates
accumulate); the V1 → Letta Code platform change is a real risk for
integrations.

Floppy already has: the tiering (`MEMORY.md` as core, notes as archival),
in-place edits, git-markdown — they arrived at our format, not the reverse.

Taken, in 0.23.0: the sleep-time idea became the consolidate rite —
consolidation moved out of the end of a working session into a separate pass.
The deliberate difference from Letta: not a background agent but a session
triggered by the 96% quota warning, and a human approves every change.

### Mem0 — fact extraction, vectors

An LLM extracts short facts from the dialogue; the 2025 paper has a comparison
phase (ADD/UPDATE/DELETE/NOOP against existing memories). OSS v3 (2026)
dropped it: ADD only, MD5 dedup of exact duplicates, conflicts left to ranking
at search time. The graph, consolidation ("Dream"), decay and expiration are
platform-only ($249/month).

Strong: the simplest integration (add/search) and the widest distribution
(~65k stars, the exclusive memory of the AWS Agent SDK); cheap at read time —
~90% token savings against full context.

Weak: the most disputed benchmarks in the field — their LoCoMo "SOTA" was
taken apart by Zep and Letta, and full context beats Mem0 in their own setup;
practitioners describe the fact base as a mush of fragmented, invalid
sentences, with wrong facts injected into answers; v3 dropping UPDATE/DELETE
is an admission that the LLM judge on the write path did not survive
production.

Floppy already has: exactly what they lack — selection *before* writing. Our
note on their benchmarks (they measure recall, not selection) stands.

Not taking: automatic capture without selection — this system's main lesson is
negative.

### Zep / Graphiti — temporal knowledge graph

Episodes → entities and fact edges with `valid_at`/`invalid_at`: a
contradicting fact invalidates the old edge without deleting it, so the graph
answers "what was believed true, and when". Reads need no LLM calls and are
sub-second; writes cost several LLM calls per episode. Consolidation is
community nodes (entity clusters). Self-hosted Zep was wound down in 2025;
what remains is Zep Cloud and Graphiti (Apache-2.0, ~31k stars) plus your own
Neo4j/FalkorDB.

Strong: the only *mechanical* answer to facts changing — supersession with
history, not an LLM's judgement; fast deterministic reads.

Weak: the graph grows monotonically, there is no forgetting, and loading "at
scale becomes very expensive" (their own issue); not files — Cypher queries
instead of `git diff`, nothing to fix by hand; also a combatant of the
benchmark wars (84% → 58% → 75% on the same LoCoMo).

Floppy already has: the same validity idea as `as_of` + "rewrite in place",
with git blame keeping the belief history for free.

Taken, in 0.23.0: the discipline of explicit invalidation is now a step of the
rite, not a habit — consolidate proposes a deletion together with the name of
its replacement (the first pass deleted the collation note exactly that way;
the graduated note in `knowledge/` became the replacement). There is still no
mechanical check, deliberately: a gate on prose would teach writing the
replacement in without reading it.

### basic-memory — markdown + local search

Markdown as the source of truth, SQLite as a derived index rebuilt by a file
watcher; wikilinks and observation lines form a graph; an MCP server serves
any client. Hybrid search: FTS + local embeddings (FastEmbed) + an optional
reranker.

Strong: the closest system to floppy in spirit — git-friendly, human-readable,
zero LLM cost at write time; one memory shared by several tools (Claude Code,
Cursor, Desktop) over MCP; search is local, nothing leaves the machine.

Weak: no consolidation and no ceilings of any kind — growth is unbounded and
curation is entirely on the human; AGPL-3.0 and pre-1.0 (~v0.23) with a small
team; graph quality depends on how carefully the LLM writes the syntax, and
nothing checks it.

Floppy already has: the files, wikilinks, frontmatter and indexes; the quotas
and `lint` are what they lack.

To take, later: the derived-index-with-search mechanic — as an option for a
corpus that has outgrown routing by name (our recorded revisit mark: ~150
files).

### LangMem (LangChain) — SDK, memory taxonomy

An SDK, not a store: semantic / episodic / procedural memory as JSON documents
in a LangGraph BaseStore with vector search. A background memory manager runs
over transcript batches — extracts, merges the similar, invalidates the
contradicting; debounced so a burst of messages produces one consolidation
pass.

Strong: a clean taxonomy of memory types; a well-thought-out deferred
background-consolidation pattern.

Weak: effectively frozen — v0.0.30, last release October 2025, the team's
attention moved to LangGraph; JSON in a database — not files, not git — and
practically tied to LangGraph.

Taken, in 0.23.0: the "manager over a batch" shape, applied to the corpus
rather than to transcripts — consolidate reads one half whole per pass and
decides over all its notes at once, not note by note.

### Cognee — graph + vectors, pipeline

An ECL pipeline: LLM extraction of entities and relations → a graph
(Neo4j/Kuzu) + a vector store; ~14 read modes from flat RAG to multi-hop graph
traversal. Apache-2.0, ~31k stars, active development on seed funding.

Strong: the only one offering structural queries across documents — entity
relations, multi-hop.

Weak: the GraphRAG tax — every write costs LLM + embedding calls, on heavy
infrastructure of three stores; not human-readable, an audit is a graph query;
pruning embryonic.

Not taking: for memory at the scale of "dozens of notes per repository" the
price of structure does not pay off — useful as the opposite end of the
spectrum to steer by.

### Claude Code native: CLAUDE.md, auto-memory, the memory tool

`CLAUDE.md` (Anthropic's guidance: up to ~200 lines, longer hurts adherence);
auto-memory: a `MEMORY.md` index of which only the first 200 lines / 25KB are
loaded (silent truncation past that) plus leaf files read on demand, with the
harness itself pressing for consolidation near the limit. The API memory tool
(`memory_20250818`) exposes file commands against your own store. Anthropic's
doctrine is one piece: a small always-loaded core + just-in-time reading.

Strong: index-plus-leaves is now a documented convention — floppy stands on
the primary source; everything is editable markdown.

Weak: no search anywhere — recall rides entirely on index quality; auto-memory
is machine-local, nothing moves between machines; the silent index truncation
is a trap we have hit.

Floppy already has: floppy *is* a superstructure over this pattern, adding
what it lacks — scopes, quotas with a ratchet, evidence, the rites, sync
through git.

### Editor memories, briefly: Cursor · Windsurf · Copilot

Cursor Memories: a sidecar model watches the chats and proposes memories, a
human approves; stored in Cursor's settings — not in git, not portable.
Windsurf Cascade: short auto-cards under `~/.codeium/…`, local and
non-portable. Copilot instructions: hand-written only
(`.github/copilot-instructions.md`, `AGENTS.md`) — fully git-native, but
nothing accumulates by itself.

Floppy already has: Cursor's "a human approves the memory" principle is our
wrap with the human in the loop — and since 0.23.0 also consolidate, where
every merge waits for a yes; Copilot's git-nativeness is our base layer.

## The summary table

| System | Store | Read path | Growth / consolidation | Git-readable | Selection at write |
|---|---|---|---|---|---|
| floppy 0.24.x | markdown + git | index → name, no search | quota ratchet + consolidate rite (human approves) + merge-at-write + heat log | full | **yes — the only one** |
| Letta | blocks + Postgres/pgvector → MemFS (git markdown) | tool calls, vector | sleep-time block rewriting; archival accumulates duplicates | was none → becoming full | no (the LLM writes) |
| Mem0 OSS v3 | facts in a vector DB | semantic search | ADD only + MD5 dedup; decay/consolidation are paid | none | no |
| Zep / Graphiti | temporal graph | hybrid, no LLM, fast | invalidation instead of deletion; grows monotonically | none | no |
| basic-memory | markdown + derived SQLite | FTS + local vectors | none — grows freely | full | no |
| LangMem | JSON in BaseStore | vector | background manager: merge/invalidate (project frozen) | none | no |
| Cognee | graph + vectors + relational | 14 modes, up to multi-hop | memify enriches; pruning embryonic | none | no |
| Claude Code auto-memory | markdown, local | index (200 lines) → file | consolidation pressure near the index limit | files yes, no sync | partial (the model decides) |

Every vendor benchmark behind this table is marketing until reproduced: the
same Zep on the same LoCoMo scores 84% in its own paper, 58% in Mem0's, 75%
after corrections — and Letta's flat-files agent beats both.

## The saturation ceiling: what the field has measured

The feeling that "there is some ceiling of note saturation" is not an
illusion; both of its halves are confirmed by independent measurements.

**Loaded context hurts long before the window limit.** Chroma's "Context Rot"
(2025, 18 models): quality degrades with input length even on trivial tasks; a
single distractor measurably lowers accuracy, and distractors add up. A
focused prompt of ~300 tokens answers better than the full ~113k-token history
on the same LongMemEval questions. (LongMemEval itself, ICLR 2025: −30% for
assistants on long histories, up to −60% on temporal questions.)

**Accumulated memories hurt retrieval.** "Memory saturation" is a named
phenomenon in the 2026 literature: semantically similar records drown
retrieval in near-duplicates; raising the number of injected memories from
small values to 5–10 lowers quality (context dilution). The effect is shown
for vector search; for name-based routing the analogue is index length.

**Age-based forgetting forgets the wrong things.** The 2026 follow-up to
MemoryBank (Ebbinghaus decay): the forgetting curve "effectively bounds memory
size and search time, but leads to a substantial drop in task quality". The
field converged on invalidation-by-contradiction, not by date — which is
literally our "old and wrong are different things" and reporters-not-gates.
(Those who ship invalidation: Zep — bi-temporal edges; Mem0 — a DELETE op, in
the paid platform.)

**The optimal index size is published nowhere.** The known points: limits by
fiat (Anthropic's 200 lines / 25KB), Claude Projects switching "small — load
everything, large — RAG", and Chroma's degradation long before the window. Our
25 pointers ≈ 4000 characters per index is one of the few *measured* points on
this question at all. The field's answer to saturation is the same everywhere:
not a bigger index but a smaller hot tier plus reading on demand.

## Living with the quotas — and the architectural way past the ceiling

**Diagnosis first.** Our quotas fire not because of garbage: the corpus grows
by live notes, and the ratchet arithmetic "corpus + 10%" guarantees every
growth spurt meets the ceiling. That is the mechanism working, not failing.
What hurt was "no third answer between raising and pruning"; since 0.23.0
there is one, and the first consolidate pass showed that a corpus where
"pruning finds nothing" still gives back 4.1k characters through merges and
rewrites — there was nothing to delete, but there was something to compress.

**The key distinction, confirmed by the field:** the expensive characters are
the ones loaded every session (`MEMORY.md`, the indexes: `pointers_max`).
Corpus characters on disk are nearly free under name-based reading — our own
benchmark showed retrieval at 49 files is not the bottleneck. Different limits
deserve different strictness.

**Now: hold the hot tier hard, raise the corpus tier calmly.** While
consolidation honestly answers "nothing to compress", raising `chars_max` by
the rule is the normal path, not a defeat. The first version of this survey
proposed softening the step to "corpus + 20%" — not taken: a softer step would
make raises rarer by weakening the ratchet, while consolidate makes them rarer
by returning space (first pass: 5.7% of the corpus) and keeps every raise a
defended act. The index limits (`pointers_max`, a thin `MEMORY.md`) stay
untouched: they protect what is measurably expensive.

**Now: invest in `NOW.md`, not in note count.** Measured: the status file was
cited 17 times against six notes once each. Writing it as the session goes
(the open item about writing status before wrap) earns more than any work on
quotas.

**Adopted in 0.22.0 — merge-at-write** (A-Mem's "memory evolution"). The rule
"a new note pulls a revision of its wikilink neighbours" is now the second
half of the one-fact-per-file check in `agent-memory`: before saving, open the
notes the new one links to, and merge/rewrite rather than put a sibling next
to them. Cheap precisely because it happens while the context still holds the
whole picture.

**Adopted in 0.23.0 — the consolidate rite.** Shipped as `consolidate`: on the
96% quota warning it reads one half whole (logging reads through heat),
collects evidence per note and proposes a numbered list of merges, rewrites
and deletions — a proposer, never a gate: every change waits for the human's
yes (Cursor's principle), and an empty pass is a valid outcome the next quota
raise can cite. First pass over `product/` (2026-09-13): 1 merge, 1 deletion
with its replacement named, 2 rewrites, 1 declined merge recorded; corpus
71649 → 67545.

**Adopted in 0.23.0 — read accounting (heat).** Shipped as the `heat` verb:
`start` tells the session to log every note actually opened, and `lint` gained
a "note heat" section naming the never-opened — a reporter, not a gate: the
log is a self-reported lower bound (the 09-09 benchmark measured the
undercount), and a cold-but-true note earns its place by existing. The log is
machine-local, outside the quotas, ignored via `.git/info/exclude` — the first
version of the rule wrote to `.gitignore` and was caught by review the same
day: it left the tree permanently dirty on a path the guard refuses to commit.

**Later: a threshold for switching the read mode.** Like Claude Projects:
below the threshold load the index, above it search. Our recorded revisit mark
is ~150 files; at that point add a derived local index with search
(basic-memory's mechanic; FTS without embeddings is enough to start). Building
it earlier has no grounds: retrieval is not the bottleneck now, and that is
measured.

**Not doing.** Automatic capture without selection (Mem0's lesson: the mush of
facts); age-based forgetting (MemoryBank's lesson: saves space at the price of
quality); a fourth index level (our convention: nobody reads past three);
embeddings for their own sake on a corpus smaller than a single LoCoMo
conversation.

## The bottom line

Architecturally floppy stands on the side the field is drifting to by itself:
files, git, a thin index, a human in the loop. Its unique parts — selection at
write, the ratchet, evidence — are still matched by nothing in 2026, and the
failures of automatic capture keep confirming them. The one class of mechanism
that needed catching up — consolidation — was caught up in 0.22.0–0.23.0
(merge-at-write, the consolidate rite, heat), and the quota has already fired
as designed: not as a wall but as the trigger for tending the corpus. Two
fronts stay open, and neither is consolidation mechanics: **capture** (all 12
benchmark failures were unwritten facts; only the habit of writing at the
moment of the event moves that) and the deferred **~150-file mark**, past
which name-based reading gets a derived local search.

## Verification

| what | how it was established | date |
|---|---|---|
| floppy's own numbers: benchmark, quota history, consolidate first pass | this repository's `memory/` half, `quota.lock`, `CHANGELOG.md` 0.22.0–0.23.0 | 2026-09-13 |
| adoption statuses ("floppy already has", "taken in …") | checked against the code, 0.24.1 | 2026-09-14 |
| everything about the other eight systems | secondary sources below, not independently reproduced | 2026-09-13 |

Key sources (vendor numbers are self-reported): Chroma "Context Rot" —
trychroma.com/research/context-rot · LongMemEval — arxiv.org/abs/2410.10813 ·
Letta: MemFS turn — letta.com/blog/our-next-phase, "Is a Filesystem All You
Need?" — letta.com/blog/benchmarking-ai-agent-memory, sleep-time —
letta.com/blog/sleep-time-compute · Mem0 — arxiv.org/abs/2504.19413, v2→v3
migration — docs.mem0.ai/migration/oss-v2-to-v3, Zep's rebuttal —
blog.getzep.com ("Is Mem0 Really SOTA?") · Zep/Graphiti —
arxiv.org/abs/2501.13956, github.com/getzep/graphiti · A-Mem (note evolution)
— arxiv.org/abs/2502.12110 · MemoryOS (heat) — arxiv.org/abs/2506.06326 ·
decay hurts — dl.acm.org/doi/full/10.1145/3803291.3803294 · memory saturation
— arxiv.org/html/2603.07670 · Anthropic — code.claude.com/docs/en/memory,
anthropic.com/engineering/effective-context-engineering-for-ai-agents ·
basic-memory — github.com/basicmachines-co/basic-memory · LangMem —
langchain-ai.github.io/langmem

Re-check this page when a survey entry's system ships a major version, and
re-run the comparison's own numbers when the memory's benchmark is repeated;
the "taken" statuses age with this repository's releases, not with the field.
