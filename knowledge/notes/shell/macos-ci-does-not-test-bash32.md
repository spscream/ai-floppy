---
name: macos-ci-does-not-test-bash32
description: A green macOS job proves nothing about bash 3.2 compatibility — `bash` in PATH is 5.x, and calling `/bin/bash run.sh` still hands every test back to 5.x unless the runner passes the same interpreter down
area: shell
verified_on: 2026-08-25
verified_against: "macOS on arm64 (darwin25); /bin/bash 3.2.57(1)-release against 5.x from Homebrew earlier in PATH"
recheck: "On a mac: `bash --version | head -1` and `/bin/bash --version | head -1` — the first says 5.x, the second 3.2.57. Then run your test suite under /bin/bash and print the interpreter from inside one test."
invalidated_by: "Apple ships a bash newer than 3.2, or the runner is guaranteed to have no other bash in PATH"
platforms: macos
recheck_cmd: /bin/bash -c 'echo ${BASH_VERSINFO[0]}'
expect: 3
---

# Adding a macOS job does not mean your scripts are tested on bash 3.2

## The fact

macOS ships **bash 3.2.57** at `/bin/bash` — the last release under GPLv2, frozen there
for over a decade — while nearly every developer machine and CI runner has **bash 5.x
earlier in PATH**, from Homebrew or from the image's own tooling. So a job that runs
`bash script.sh` on macOS tests bash 5, not the interpreter your users have.

Pinning the entry point is not enough either. Calling `/bin/bash run.sh` fixes only the
outer shell: if `run.sh` invokes each test with a bare `bash`, every test resolves through
PATH again and runs under 5.x. Two things must hold together:

1. the job calls `/bin/bash` explicitly, and
2. the test runner hands the *same* interpreter to each test — `"$BASH"`, not `bash`.

Make the suite print its interpreter version once, so the answer is in the log rather than
in an assumption.

## Why it is not obvious

The job is green, and it is genuinely running on macOS: the platform coverage you added is
real. What silently did not get covered is the *interpreter*, which is the thing bash 3.2
compatibility is about. Nothing in the output distinguishes "ran on macOS under bash 5"
from "ran on macOS under bash 3.2", so the badge means what you hoped it meant until the
day somebody runs the script on a clean machine.

The second half is quieter still, because pinning `/bin/bash` at the entry point *feels*
like the whole fix — and it is, right up until the runner spawns children.

## Evidence

**MEASURED**, on the mac, 2026-08-23 and 2026-08-25, during the first deployment of a
repository to a second machine.

Three shell tools broke there and every one of them broke silently:

- two used `mapfile` and `declare -A`, both bash 4 builtins — the memory check did not run
  at all on that machine, and the failure scrolled past inside another command's output;
- one used GNU-only `stat -c`, `ps --no-headers` and `ss`, so the step that reconciles a
  session with reality did not execute;
- one read a file's age as `stat -c %Y` and fell into its own `|| echo 0`. Every lock came
  out about fifty-seven years old, so **the lock never held on that machine for a week**.
  Measured directly: capture by "session A", immediate capture by "session B", report
  `29793710 min old (older than 30)`.

A fourth defect was found by a BSD/GNU difference rather than a version one: `\+` in `sed`
is a GNU extension, and BSD `sed` reads it as a literal plus. That one produces no error at
all — it silently extracts nothing.

**MEASURED**, the fix: once the job invoked `/bin/bash` and the runner passed `$BASH` to
each test, the suite printed
`GNU bash, version 3.2.57(1)-release (arm64-apple-darwin25)`. Before the second half of
the change, `/bin/bash run.sh` alone still reported 5.x from inside the tests.

**Not re-run on 2026-09-05**, when this note was written: the machine at hand was Linux,
where the claim is not asserted. The `recheck_cmd` above is skipped off macOS by design.

## How to re-check

On a mac, thirty seconds:

```bash
bash --version | head -1        # expect 5.x if Homebrew's bash is installed
/bin/bash --version | head -1   # expect GNU bash, version 3.2.57(1)-release
```

Then the half that matters: run your suite the way CI runs it and have one test print
`$BASH` and `${BASH_VERSINFO[0]}`. If that line says 5, the suite is not testing 3.2 no
matter what the job's first line says.

## What it costs you not to know

You believe a whole class of portability defect is covered by CI, and it is not — so the
defects land on the second machine instead, where they are found by a person rather than a
run. The expensive shape is not the loud one: `mapfile` fails immediately and gets fixed
the same day. The costly ones are the silent substitutions — a GNU-only `stat` spelling
falling into a default, a BSD `sed` matching a literal — which leave the script exiting
zero while doing nothing, or doing the opposite of its purpose.

A guard is the worst place for this. The lock above did not merely stop working; it
answered "this lock is stale, take it" every single time, which is the wrong direction to
fail in. If you take one operational rule from this: a check that cannot establish its own
condition must refuse, not pass.

## See also

- [[and-list-as-last-line-of-script]] — another way a shell script reports success it did
  not earn.
