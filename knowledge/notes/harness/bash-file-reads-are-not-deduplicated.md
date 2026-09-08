---
name: bash-file-reads-are-not-deduplicated
description: The harness tracks files opened with Read and deduplicates them; a file pulled in with cat or sed through Bash arrives in full every single time, and editing one outside Edit re-injects the whole file
area: harness
verified_on: 2026-08-29
verified_against: "Claude Code, one finished slice of work in a multi-repository project: 3 repositories, 7 commits, 4 review rounds; message content measured from the session transcript"
recheck: "Read the same file twice with the Read tool and then twice with cat through Bash, and compare the input token counts on the four turns"
invalidated_by: "The harness starts tracking file content pulled through Bash, or stops re-injecting externally modified files"
---

# `cat` through Bash is not the same read as `Read`

## The fact

The harness keeps a state table of files opened with the **`Read`** tool. That table is what
lets it deduplicate a second read and warn about editing a file that was never read. A
`cat`, `sed` or `grep` invocation through **Bash** goes past that bookkeeping entirely — to
the harness it is just command output, so a second read of the same file arrives in full
again.

The same mechanism has a second face: **editing a file with `perl -pi` or a Python heredoc
counts as an external modification, and the harness injects the entire file back as a system
reminder.** `Edit` does not do this.

## Why it is not obvious

Both readings produce the same text on screen, and the Bash one often looks cheaper — one
line, no tool ceremony, and you can pipe it. The cost difference is invisible at the moment
you pay it and only shows up as a context that filled faster than the work justified.

## Evidence

**MEASURED**, 2026-08-29, one finished slice of work — three repositories, seven commits,
four review rounds — by attributing every message's content in the transcript:

| item | share of session content |
|---|---:|
| sources pulled in by `cat` / `sed` / `grep` through Bash — 83 calls | **35%** |
| bodies of `Edit` and `Write` | 20% |
| test runs, 31 of them | 8% |
| four reviewer subagents in full | 3% |
| project memory files | 3%, flat |

**Half of that first row is repeats.** 34 files arrived two or more times; the repeats alone
were about a quarter of all session content. One 300-line file was pulled five times, another
ten times. In the same slice, three files of 200–400 lines were re-injected in full because
they had been edited outside the `Edit` tool.

Two hypotheses the measurement killed: test start-up noise is **not** the problem (4% of Bash
output — `| tail -N` already handles it), and memory files are **not** the problem (3%, and
flat). Tidying either optimises single digits while 35% sits untouched.

The estimate "characters ÷ 3.5" understates Cyrillic, which tokenises at roughly 2–2.5
characters per token against 3.5–4 for Latin text and code, so the prose share is about half
again as large as shown. The order of the table does not change — the top two rows are code.
One slice, one project.

## How to re-check

Read a file twice with `Read`, then twice with `cat` through Bash, and compare input tokens
across the four turns. The two `Read` turns differ; the two `cat` turns do not.

## What it costs you not to know

Context fills with the same file five times over, and every later turn re-reads all of it at
the full rate. The three habits that follow:

- **`Read` for anything that might be needed twice.** `cat`/`sed` for things that are not
  files: counters, diffs, command output.
- **`grep -n` to find *where*, then one `Read` with `offset`/`limit`.** Not `grep -A 30`.
- **`Edit`/`Write` to change code**; scripts for loops and counting.

## See also

- [[subagent-cache-starts-cold]] — the entry price that decides whether moving a large read
  out to a subagent pays.
