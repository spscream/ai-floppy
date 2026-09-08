---
name: interactive-aliases-make-cp-a-silent-no-op
description: The tool shell is initialised from the user profile, so cp/mv/rm may be aliased to -i; with no terminal on stdin the prompt goes unanswered and the file is not overwritten, while the exit code says either 0 or 1 depending on the coreutils version
area: shell
verified_on: 2026-09-06
verified_against: "Claude Code Bash tool on Linux 6.18 (WSL2), profile aliasing cp to cp -i; GNU coreutils 8.32 locally and a GitHub-hosted ubuntu runner"
recheck: "type cp — then run cp -i over an existing file with </dev/null and read the destination: it still holds the old content. Check the exit code too, and expect it to differ between coreutils versions"
platforms: linux
recheck_cmd: d=$(mktemp -d) && printf new > "$d/src" && printf old > "$d/dst" && cp -i "$d/src" "$d/dst" </dev/null 2>/dev/null; printf '%s\n' "$(cat "$d/dst")"; rm -rf "$d"; true
expect: old
---

# An aliased `cp` declines to overwrite and still reports success

## The fact

The shell behind the tool is initialised from the user's profile, and a profile that carries
`alias cp='cp -i'` applies to non-interactive tool calls too. Copying **over an existing file**
then does three things at once:

1. the prompt is printed, and nobody can answer it — stdin is not a terminal;
2. the destination keeps its old content, and whatever runs next honestly measures the old file;
3. **the exit code does not reliably say so.** GNU coreutils 8.32 returns **0** here — so
   `cp … && next-step` proceeds as if the copy had happened — while a newer coreutils on a
   GitHub-hosted ubuntu runner returns **1** for the identical command. Neither code can be
   read as "the file is now what I copied".

The practical symptom: "I restored the new version of the file and ran the tests — the numbers
are the same as before." The numbers are the same because the file is the same.

## Why it is not obvious

Every mental model of `cp` comes from the bare utility, and the alias is invisible at the call
site. The failure also mimics a real result rather than an error: a green exit code, a plausible
number, and a conclusion about *the code* drawn from a measurement of the wrong file.

## Evidence

**MEASURED**, 2026-09-06, in the tool shell on a working machine:

```
$ type cp
cp is an alias for cp -i

$ cp "$d/src" "$d/dst" </dev/null
cp: overwrite '/tmp/…/dst'?      rc=0        # GNU coreutils 8.32
dst now: old
```

**MEASURED again, 2026-09-08**, by this note's own check running in CI: on a GitHub-hosted
ubuntu runner the identical command returned **1** instead of 0, with the destination still
holding `old`. The exit code is therefore implementation-dependent and the *content* is the
invariant — which is what the check now asserts. The first version of this note asserted
`0 old` and went red on the first machine that was not the one it was written on.

The executable check runs `cp -i` explicitly, which is the same mechanism without depending on
any particular profile. It is asserted on Linux, where both measurements were made.

**Cost paid**, same day: a test meant to exercise new code ran against the old file, and the
unchanged numbers were nearly written up as "the fix does not work".

## How to re-check

`type cp` in the tool shell says whether the alias is there. The `recheck_cmd` demonstrates the
mechanism itself: the destination is unchanged. Print `$?` beside it to see which of the two
exit codes your coreutils gives.

## What it costs you not to know

A false negative in a measurement, which is the expensive direction: the work looks done, the
numbers look real, and the conclusion is about code that never ran. Guarding with `&&` does not
save you where the exit code is 0, and where it is 1 the script stops with an error that names
a prompt nobody saw.

How to copy when it matters:

```bash
command cp -f src dst     # bypass the alias
\cp -f src dst            # same, shorter
install -m 644 src dst    # when the mode matters
```

Better still, do not copy: restoring a file version is `git checkout -- <path>` or
`git stash pop`, and writing content is the `Write` tool, which has no shell in between.

The same trap sits behind any default-interactive alias from a profile — `mv -i`, `rm -i`.
Check with `type <cmd>` rather than assuming the bare utility's behaviour.

## See also

- [[and-list-as-last-line-of-script]] — the other way a shell reports the wrong colour.
