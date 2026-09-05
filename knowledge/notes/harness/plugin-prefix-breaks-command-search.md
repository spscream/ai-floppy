---
name: plugin-prefix-breaks-command-search
description: A command that moves into a plugin is recorded in the transcript as `/plugin:name`, so any tool searching for the bare `/name` silently measures only the pre-plugin era while still printing a full table of history
area: harness
verified_on: 2026-09-05
verified_against: "Claude Code 2.1.232, transcripts under ~/.claude/projects/<encoded-cwd>/*.jsonl, a repository whose /start and /wrap moved into a plugin"
recheck: "grep -oh '<command-name>[^<]*' ~/.claude/projects/*/*.jsonl | sort | uniq -c — runs from before the move appear as /name, runs after as /plugin:name"
invalidated_by: "A release that records the bare command name alongside the prefixed one, or that stops prefixing plugin-owned commands"
---

# Moving a command into a plugin renames it in every transcript

## The fact

The harness records a slash command invocation as `<command-name>/wrap` while the
command file lives in the repository, and as `<command-name>/floppy:wrap` once a plugin
owns it. The names do not overlap: a substring search for `<command-name>/wrap` matches
none of the prefixed runs.

Any transcript analysis keyed on the bare name therefore keeps working, keeps printing
rows, and measures only the era before the move.

## Why it is not obvious

The failure has no error state and no empty output. The tool prints a full table — of
history — and every number in it is correct. Nothing distinguishes "this command has not
been run since Tuesday" from "this command has been renamed and I can no longer see it",
because both look like a table that stops at the same date.

It is also invisible at exactly the moment it is introduced: the move into a plugin is
celebrated as removing a duplicate, and the measurement tooling is not part of that
diff.

## Evidence

MEASURED. In one repository's transcripts, on the day the ritual moved into a plugin:

```
$ grep -oh '<command-name>[^<]*' ~/.claude/projects/<repo>/*.jsonl | sort | uniq -c
     45 <command-name>/start
     35 <command-name>/wrap
      1 <command-name>/floppy:start
```

The single prefixed entry is the first invocation after the move. A cost tool searching
`/start` returned the 45 and not the 1, and reported no error.

MEASURED, after changing the matcher to accept an optional `<plugin>:` segment: the same
tool returned the prefixed run too, with its own row of measurements.

## How to re-check

Run the `uniq -c` above on any project whose commands have moved into a plugin. Both
spellings will be present, split at the date of the move.

## What it costs you not to know

You keep measuring the thing you changed, using a tool that can no longer see the change.
Worse, the numbers stay plausible, so the tool is trusted: the median it reports is the
median of the old regime, and it will be quoted as the current one.

The fix is one line — accept `/(?:[\w.-]+:)?name` rather than `/name` — and the reason to
write it down is that nobody looks for this bug. It is found by noticing that a run you
just performed is missing from a table you just printed.

## See also

[[prometheus-metrics-need-a-second-request]] — the other half of "measure the session":
what telemetry can and cannot replace here.
