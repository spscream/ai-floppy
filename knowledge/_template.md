---
name: <kebab-case-slug-matching-the-filename>
description: <one line stating the finding itself, not its topic — this is what the router shows>
area: <harness | memory | shell | practice>
verified_on: <YYYY-MM-DD>
verified_against: <tool and version, OS, model — whatever the claim actually depends on>
recheck: <an executable command, or a two-line procedure naming the page and the sentence>
invalidated_by: <the change that would make this false — optional, but write it if you can name it>
# The machine-checkable half — optional, and most notes will not have it. Add it when
# the claim can be reduced to a command with one deterministic line of output; then
# scripts/knowledge-recheck.py proves the note instead of a person remembering to.
platforms: <linux, macos, windows — where the claim is asserted to hold; omit for anywhere>
requires: <probe command; a non-zero exit means "cannot run here" and the check is skipped, not failed>
recheck_cmd: <the check, run under bash from the repository root>
expect: <the exact stdout of recheck_cmd, whitespace-trimmed>
---

# <Title: the finding as a sentence>

## The fact

<Two to five sentences. Lead with what is true. No preamble, no story yet.>

## Why it is not obvious

<What a reasonable person would expect instead, and why. If nothing goes here, this note
does not belong in the knowledge base.>

## Evidence

<How this was established. Mark every claim: MEASURED (you ran it — give the command and
the output) or READ (it follows from source, docs, or code you looked at but did not
execute). Do not blur the two.>

## How to re-check

<Expand `recheck` if one line was not enough. Someone should be able to confirm or refute
this in a few minutes without your context.>

## What it costs you not to know

<A concrete failure: specific inputs or situation → specific wrong outcome. This is the
section that makes the note worth its place.>

## See also

<Links to related notes as [[slug]]. A slug with no file yet is fine — it marks something
worth writing, not an error.>
