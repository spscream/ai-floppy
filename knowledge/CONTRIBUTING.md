# How to write a note

One note, one fact. If you find yourself writing "and also", you have two notes.

## Before writing: the admission test

All three must hold, or the note belongs somewhere else.

1. **True outside one repository.** → otherwise: that repo's agent memory.
2. **Cost real work to learn.** Not a restatement of the vendor docs. → otherwise:
   link the docs, do not copy them.
3. **Checkable.** You can name the version it holds for and a way to re-test it.
   → otherwise: it is folklore, and folklore is how a knowledge base turns harmful.

A useful sharpener for condition 2: *would a competent person derive this in a week of
normal use?* "Delegate mechanical work to a cheaper model" — yes, in a day. "The
subagent restriction comes from the Opus 5 prompt bundle and is gated on a remote flag" —
no, that took reading a 320 MB binary.

## The file

Copy [`_template.md`](_template.md) into `notes/<area>/<slug>.md`. Areas are `harness`,
`memory`, `shell`, `practice`; add one only when three notes are waiting for it.

### Frontmatter — every field is required except `invalidated_by`

```yaml
---
name: opus5-subagent-prompt-line
description: One line. This is what the router shows; make it say the finding, not the topic.
area: harness
verified_on: 2026-09-05
verified_against: "Claude Code 2.1.232, Linux 6.18 (WSL2), Opus 5"
recheck: "grep -ac 'Do not call the AgentTool' ~/.local/share/claude/versions/<v>"
invalidated_by: "Anthropic ships the tengu_heron_brook flag with a non-empty value"
---
```

`verified_against` is not decoration. "True in Claude Code" is a claim nobody can falsify;
"true in 2.1.232 on Linux" is a claim the next reader can test in thirty seconds.

`recheck` must be executable or a two-line procedure. "Read the docs again" is not a
recheck — say *which page* and *what sentence you are looking for*.

### Body — five sections, in this order

1. **The fact.** Two to five sentences. Lead with the finding, not the story.
2. **Why it is not obvious.** If it is obvious, delete the note.
3. **Evidence.** How it was established, and explicitly whether each claim was
   **measured** or **read**. Mixing the two is the most common way a confident note turns
   out to be wrong: the measured half survives, the read half rots, and the reader cannot
   tell which was which.
4. **How to re-check.** Expand `recheck` if it needs more than one line.
5. **What it costs you not to know.** A concrete failure: inputs or situation → wrong
   outcome. Without this the note is trivia.

### Size

**10 000 characters per note.** A note over the cap is a note that should have been two.
This is the same number the `floppy` memory linter enforces, and for the same reason: a
dump is where an overturned conclusion survives unnoticed.

### Making the check run itself

`recheck` is prose for a person and stays required. When the claim reduces to a command
with one deterministic line of output, add the machine-checkable half as well:

```yaml
platforms: linux, macos     # where the claim is asserted to hold; omit for anywhere
requires: command -v claude >/dev/null 2>&1   # optional probe
recheck_cmd: <the check, run under bash from the repository root>
expect: 0 2 2               # exact stdout, whitespace-trimmed
```

Then `python3 scripts/knowledge-recheck.py` proves the note rather than a person
remembering to. Three things to get right:

- **make the output a single deterministic line.** Reduce a count to a number, an exit
  code to `echo $?`, a presence question to `present`/`absent`. A check whose output
  drifts between machines will be silenced within a month;
- **use `requires` for anything environment-dependent.** A check that goes red simply
  because a tool is absent trains everyone to ignore the runner. A skip is honest; a
  false red is not;
- **name `platforms` when the claim is platform-bound.** On a platform outside the list
  the check is skipped, not failed — "false here" and "not asserted here" are different
  claims, and the matrix exists to keep them apart.

Both fields or neither: `recheck_cmd` without `expect` runs, produces output and proves
nothing. `knowledge-rot-check.py` refuses that combination.

Most notes will never have this half. A claim read from vendor documentation has nothing
to execute, and the report counts it as *not machine-checkable* rather than as a skip —
a fact about the note, not a defect.

## After writing

Nothing. There is no index to update: the site page is generated from your front matter
by `scripts/site-build.sh`, so `description` is the pointer line — write it as the
finding, not as the topic. On GitHub the directory listing is the index.

## Keeping it honest

Run `python3 scripts/knowledge-rot-check.py` from the repository root before you touch
anything. It lists notes whose `verified_on` has aged past the threshold (90 days by
default — this field moves fast) and notes that break the contract above.

**It reports; it does not gate.** Old and wrong are different things, and only a person
who knows the area can tell them apart. Three outcomes for an aged note, all legitimate:

- re-verified → bump `verified_on`, say nothing else;
- still true but the environment moved → update `verified_against` and the evidence;
- no longer true → **rewrite it in place**, do not leave the old claim standing beside
  its replacement. A superseded note that survives is worse than no note.

Deleting is allowed and under-used. A note whose subject no longer exists should go, and
the deletion commit should say what replaced it.

## What never goes in

- Secrets, tokens, hostnames, customer names, internal URLs. Not "redacted" — absent.
  Say where a thing is obtained, never the thing.
- Anything true of exactly one private codebase.
- Speculation about a vendor's intent. Record behaviour; leave motive alone.
