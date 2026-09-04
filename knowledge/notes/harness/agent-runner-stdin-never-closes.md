---
name: agent-runner-stdin-never-closes
description: Under an agent's tool runner stdin is a pipe that never reaches EOF, so any command that reads it hangs forever while CI stays green
area: harness
verified_on: 2026-08-25
verified_against: "Claude Code tool runner on Linux; original measurement by the floppy author, not re-run since"
recheck: "Run a script that reads stdin without redirection through the agent's shell tool; it should not return. Then repeat with `</dev/null`."
invalidated_by: "A harness that closes stdin for tool invocations"
---

# A command that reads stdin hangs forever under an agent, and CI never shows it

## The fact

When a coding agent runs a shell command, stdin is typically a pipe that is never closed.
A command that reads stdin therefore waits for input that will never arrive, and anything
downstream of it in the pipeline waits too. There is no error and no timeout; the process
simply lives.

The fix at the call site is one redirection:

```bash
bash tests/run.sh </dev/null
```

## Why it is not obvious

**CI cannot reproduce it.** In a CI job stdin gives EOF immediately, so the same suite is
green there forever. The failure is a property of the *calling environment*, not of the
code, which means a passing pipeline says nothing at all about it.

It also does not look like a hang from inside: the command that blocks is usually several
layers down, and what you observe is a top-level runner that has stopped producing output.

## Evidence

**MEASURED by the floppy author, 2026-08-25** — not re-run since, and marked so
deliberately. `bash tests/run.sh` lived nine minutes without moving; the process tree
showed `tests/test-shim.sh` → `scripts/wrap-guard.sh`. In the same session another such
process from an earlier run was found, hung for **4.7 hours**.

**READ**, the mechanism: `test-shim.sh` loops over every verb and takes `head -1` of the
output. The `guard` verb with no arguments reads its file list from stdin. Stdin never
closes, so `guard` waits for input and `head` waits for `guard`.

## How to re-check

Run any script that reads stdin without redirection through the agent's shell tool and
watch it not return; repeat with `</dev/null` and watch it finish. A cheaper synthetic
version is a script whose last line is `cat` with no argument.

## What it costs you not to know

An agent session that appears to be working and is not, for hours, plus orphaned
processes that outlive the session and are found only by accident.

Two lessons that outlive this instance:

- **A tool that can read stdin should not read it implicitly.** Make the file list an
  argument, or require an explicit `-` to mean "from stdin". A verb whose behaviour
  changes with the shape of its caller's stdin is a verb that behaves differently under
  an agent than under a person.
- **Stopping a hung run: take the PID from `ps`.** `pkill -f` in this environment matches
  the calling shell's own command line and kills it, taking the rest of the compound
  command with it.

## See also

- [[find-does-not-follow-symlinked-root]] — the other failure this plugin's test suite
  learned to distrust green over.
