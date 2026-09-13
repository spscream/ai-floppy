---
name: consolidate
description: Merge, rewrite, and prune the memory one half at a time — proposes each change with its evidence and applies only what the human approves. Use when lint warns a ceiling is near, before raising any quota.lock number, or when the user asks to consolidate, tidy, or prune the memory.
---

# Consolidate

The quota ratchet knows two answers when a ceiling nears: raise the number or
prune what went stale. This rite is the third answer — several near notes
becoming one better note — and it exists because the other two measurably run
out. In the week of 2026-09-05..09 this plugin's own corpus raised `chars_max`
three times, and before the last raise the pruning question was asked honestly
and found nothing: every note was live. A corpus that grows live never offers
anything to *drop*; what it offers is overlap, and overlap is found by
reading, not by dates.

This is a **proposer, never a gate**. Nothing here deletes, merges, or
rewrites on its own authority: every change is proposed with its evidence and
waits for the human's yes. The one thing the rite is allowed to conclude on
its own is that there is nothing to do — and that is a real outcome, not a
failure (it is what an honest pass said on 2026-09-09, and the ceiling was
raised by the ratchet rule instead).

## When to run

- `lint` printed the 96% warning on the corpus or on a half — the moment the
  fix is still small and still belongs to the session that grew the memory;
- a `quota.lock` number is about to be raised — run this first, so the raise
  commit can honestly say pruning and merging were tried;
- the human asked for it.

Prefer a session of its own, and a cheap one: the rite reads a whole half,
which is exactly the bulk read a working session's context should not carry,
and the judgement is selection over known material, not fresh design. This is
the sleep-time shape — maintenance moved out of the expensive window — and
the reason it is not part of `wrap`: closing is the costliest place to think.

## The pass

1. **Pick one half.** The one `lint` warned about, or the largest in its
   by-half breakdown. One half is a bounded read and a bounded diff; "the
   whole memory" is how a consolidation session becomes the bloat it was
   meant to remove. Load `agent-memory` before touching anything — its rules
   (one fact per file, pointer with the note, evidence and `as_of`) are the
   frame every proposal below must fit.

2. **Read the half whole**: its `INDEX.md` (and sub-indexes), then every note
   it points to. Log the reads honestly — `bash .floppy/run heat <slugs...>`
   in one call — this rite is the one reader for which "I opened everything"
   is true.

3. **Gather the evidence per note**, three columns:
   - `as_of` and what the note claims — is the claim still describing a live
     mechanism, or one that moved?
   - heat — the cold list from `lint`'s note-heat section, remembering both
     honesty rules: the log under-counts, and cold-but-correct notes written
     for rare failures are earning their keep by existing;
   - overlap — notes linked by `[[wikilinks]]` or circling one subject. The
     write-time rule ("a new note pulls a revision of its neighbours") caught
     what it could; this is where its escapes surface.

4. **Propose, in chat, a numbered list.** Every item is one of three shapes,
   and every item carries its reason as a number or a date, not a feeling:

   - **merge** — which notes fold into which surviving slug, and what the
     merged note will say. The survivor keeps the strongest evidence rank of
     its parts, never a better one; `measured` absorbed into `read` is how a
     guess becomes a fact.
   - **rewrite in place** — the claim is superseded; the note is rewritten,
     `as_of` moves to the evidence's date. Never a second note beside the
     old one.
   - **delete** — the subject no longer exists. The commit message names
     what replaced it. Cold alone is not a reason; cold plus gone is.

   Then stop. The human answers per item or for the list; silence is not
   approval.

5. **Apply what was approved**, by the standing rules: one fact per file;
   the index pointer moves in the same edit as its note; `[[links]]` to a
   merged-away slug are re-pointed at the survivor; the whole-index rewrite
   happens under the wrap lock (`bash .floppy/run lock acquire consolidate`,
   release after), because an index rewrite is where a second writer
   silently loses work.

6. **Re-run `bash .floppy/run lint`.** If the corpus now fits its ceiling,
   the ceiling stays where it is — a successful consolidation that still
   ends in a raise is two contradictory claims in one commit. If nothing
   fit-worthy was found and the ceiling still binds, the raise follows the
   ratchet rule: same commit as the material that needs the room, reason in
   the message, this rite's empty-handed pass named in it.

7. **Close through the shim** — `check`, then `commit` — the same as any
   session that touched the memory. In a store layout the notes move with
   the store section, and a clean `git status` here proves nothing.

## What this rite does not do

It does not touch the private or `common/` scopes (the quota does not reach
them, and `common/` is written by several projects — its consolidation
belongs to a session that owns that store). It does not restructure the
index tree — a half that outgrew its pointer budget splits into sub-indexes,
which is `agent-memory`'s routing rule, not a consolidation. And it does not
run on a schedule by itself: the trigger is a warning or a human, because a
merge nobody reviews is how two facts become one wrong one.
