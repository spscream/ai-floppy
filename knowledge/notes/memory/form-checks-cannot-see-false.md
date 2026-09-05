---
name: form-checks-cannot-see-false
description: A memory linter that checks form reports a corpus clean while fifteen of its notes state something that has stopped being true, and an existence check does not close the gap
area: memory
verified_on: 2026-09-05
verified_against: "floppy 0.15.0 memory linter; a 157-note, 489 012-character agent-memory corpus grown over five weeks by two machines"
recheck: "Take a memory corpus that has run for a month, run the linter (expect clean), then read every note against the current repository and count the notes whose claims no longer hold"
invalidated_by: "A linter check that compares a note's claims against the repository rather than against the note's own shape"
---

# A clean memory linter says nothing about whether the memory is true

## The fact

Everything a memory linter enforces is **form**: unique slugs, no dangling pointers, every
note reachable from an index, index under the loader's ceiling, corpus under its quota.
None of it touches whether a note is *true*.

Measured on a corpus that had run five weeks: the linter reported
`clean: 157 notes, 166 pointers across 8 indexes`, and a full revision of the same corpus
found **fifteen notes asserting something that had stopped being true**. Zero notes were
deletable. Zero notes duplicated another. The corpus came out of the audit ~3 000
characters *bigger* than it went in.

Five classes, in descending cost:

1. **A reference to a mechanism that does not exist.** The memory said divergence between
   the repository's commands and the plugin's skills was caught by a `parity` verb, "and it
   is the gate inside `check`". No such verb — it had been removed ten days earlier, in the
   release that withdrew the whole idea it guarded. The memory of it outlived it and read
   as a live guarantee. The same line carried a second error, found only later: it named
   the day *the consumer noticed* as the day the check was withdrawn. **A date of
   observation recorded as a date of event** is its own trap — it looks precise to the day
   and is wrong by exactly the length of the gap.
2. **The description contradicts its own body.** One note's `description` said the
   repository had no git remote; the first line of its body said a remote had existed
   since a date two weeks earlier. The description is the half that gets read.
3. **A withdrawn caveat outlives its withdrawal inside one file.** A section introduced a
   counter; a later section in the same note still said no such counter existed.
4. **A frozen growing counter.** "76 runs, 174 000 measurements" against an actual
   120 / 641 393; "30 e2e tests" against 32. A number that grows on its own goes stale by
   construction, with no edit anywhere near it.
5. **A rename that did not propagate.** A directory renamed in the root router was still
   named the old way in three notes — in one of them together with the selection criterion
   that the rename had replaced.

## Why it is not obvious

The only pressure a memory corpus exerts is **size**. The quota ratchet fires, a ceiling
gets raised, somebody schedules an audit — and "audit" then means "find what to delete".
That is the wrong instrument for the actual damage: growth is loud and bounded, falsity is
silent and unbounded.

The second reason is that a green linter *feels* like a verdict on the memory. It is a
verdict on the filing.

## Evidence

**MEASURED**, one full revision, 157 notes, 2026-09-05.

Linter before and after: `clean`, both times. All fifteen false notes were green
throughout — none of them violates any rule the linter has.

**MEASURED, and it is the negative result that matters: an existence check does not fix
this.** The obvious repair is to verify that paths and verbs named in the memory still
exist. Run over the same corpus, extracting backticked tokens:

| filter | candidates |
|---|---|
| any token containing `/` that looks like a path | 105 |
| minus globs, `<placeholders>`, URLs, absolute and `~` paths; restricted to tokens starting with a real top-level directory of the repository | 13 |
| of those 13, genuinely pointing at something absent | **2** |
| of those 2, mentioned deliberately as history | **2** |

The eleven false positives are all legitimate: build artefacts absent until a build runs,
paths relative to another repository, paths inside a data corpus that is not checked out,
a path carrying a `:137` line suffix. The two true hits were sentences of the form
"this used to live at X" — which is exactly what memory is for.

The same holds for the narrower version with a closed vocabulary. Grepping the corpus for
floppy verbs after the fix, `parity` still appears twice — in the two notes that now
*document its absence*.

**READ**, from the corpus itself: this is structural, not a matter of a better regex.
Memory records that things stopped existing. "Asserts X exists" and "records that X was
removed" are the same tokens in different sentences, so an existence checker cannot tell
them apart without reading the sentence.

What the greps *are* good for is narrowing: they turned 157 notes into 13 lines to look
at. The verdict stays with whoever reads the line.

## How to re-check

On any corpus older than a month: run the linter and record its verdict. Then take each
note and ask only "is this still true?" against the current repository — not "is it well
filed?". Count the two results separately. The claim here is that the second number is
large while the first says clean.

Cheap partial re-check of the sharpest class: grep the corpus for invocations of your own
tooling (`<shim> <verb>`, script paths) and compare against what the tooling actually
offers today. Expect true hits and legitimate historical mentions in the same list.

## What it costs you not to know

A memory that asserts a guard exists when it does not. The concrete failure: a session
reads "divergence between the commands and the skills is caught by `run parity`, and it is
the gate inside `check`", concludes the comparison is automated, and skips it. The
comparison had not been automated for ten days. Nothing goes red, because there is
nothing to go red — the guarantee exists only in the memory.

There is a sharper version of this, found the same day. The memory's *justification* can
expire while every fact in it stays true: the reason the consumer kept those command files
at all had been measured false upstream, in a CHANGELOG entry nobody downstream read. No
broken link, no wrong number, nothing a sweep of any kind would surface — the premise had
gone, not the reference. The cheap prophylactic is to read a dependency's changelog for
the ideas it **withdrew**, not only the features it added.

The general shape: form checks make a corpus *navigable*, and navigability is easy to
mistake for correctness. Budget a revision that reads for truth, on a schedule, and do not
let a quota breach be the thing that triggers it — the quota answers a different question
and will keep sending you to prune a corpus that is not fat.

## See also

- [[find-does-not-follow-symlinked-root]] — the neighbouring failure: a check that passes
  because it examined nothing at all.
