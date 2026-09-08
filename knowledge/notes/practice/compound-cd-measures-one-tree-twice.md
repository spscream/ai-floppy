---
name: compound-cd-measures-one-tree-twice
description: a compound `cd A && … ; cd B && …` in one tool call does not measure two trees — the working directory resets between calls and the second cd may not run at all, so both halves report the same tree
area: practice
verified_on: 2026-09-08
verified_against: "Claude Code Bash tool, two repositories side by side; paid four times, twice on the day the note was written"
recheck: "Run `cd A && pwd ; cd B && pwd` in one tool call, then run the same two commands as two separate calls, and compare the four paths"
invalidated_by: "The tool shell starts preserving the working directory across calls and within a compound command"
---

# A compound `cd` measures one tree twice and reports it as two

## The fact

`cd A && … ; cd B && …` inside a single tool call does not do what it reads. The working
directory resets between tool calls, and within one call the second `cd` may not execute at
all. A comparison of two trees then measures **one** tree, twice, and the numbers agree
because they are the same numbers.

## Why it is not obvious

The command is one line of ordinary shell that would work in a terminal. The output is two
blocks of plausible results, in the right order, with the right labels — the shape of a
comparison. Nothing about it announces that both halves came from the same directory.

The failure mode is also the most convincing one: the two trees *agree*, and agreement reads
as a finding.

## Evidence

**MEASURED**, paid at least four times in one project, the last two on 2026-09-08 with this
rule already written down. Two concrete false results:

- "parity in code volume between two repositories" — there was none;
- "the messaging test suite has 751 cases" — it has 1558; 751 was a second run of the other
  repository's suite.

## How to re-check

Run `cd A && pwd ; cd B && pwd` as one call, then as two calls, and compare. The cheap tell in
real work is arithmetic: a number that matches neither a previous measurement nor a file count.

## What it costs you not to know

A measurement that is wrong by a factor of two and reads as a discovery — "751 against 1558"
was nearly written up as a discrepancy between the brief and the repository, rather than as a
broken measurement.

The habits that remove it:

- **One tree, one tool call.** Or use `git -C <path>` and absolute paths, which need no `cd`
  at all.
- **Name the full path inside the command** for anything that runs in a directory — a test
  runner, a build.
- **Check the number against something independent** before writing it down.

## See also

- [[two-dot-diff-counts-other-commits-as-deletions]] — the other confident number about the
  wrong thing.
