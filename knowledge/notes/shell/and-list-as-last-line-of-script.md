---
name: and-list-as-last-line-of-script
description: A false `[[ cond ]] && cmd` as the last line makes the whole script exit 1, so hook runners report failure on success
area: shell
verified_on: 2026-09-05
verified_against: "bash 5.x on Linux 6.18 (WSL2); behaviour is POSIX and holds on bash 3.2 / macOS"
recheck: "printf '%s\\n' '#!/usr/bin/env bash' 'f=1' '[[ $f -eq 0 ]] && echo x' > /tmp/r.sh; bash /tmp/r.sh; echo $?"
platforms: linux, macos
recheck_cmd: d=$(mktemp -d) && printf '%s\n' '#!/usr/bin/env bash' 'f=1' '[[ $f -eq 0 ]] && echo nothing' > "$d/r.sh"; bash "$d/r.sh" >/dev/null 2>&1; echo $?; rm -rf "$d"; true
expect: 1
---

# A guard clause on the last line silently becomes the script's exit code

## The fact

A script's exit status is the status of its last command. When that last command is an
`&&` list whose left side is false, the list returns 1 — so the script fails:

```bash
#!/usr/bin/env bash
found=1
[[ $found -eq 0 ]] && echo "nothing found"     # ← last line
```

exits **1**, on the path where everything worked. It exits 0 only in the branch where
something was *not* found. `set -e` does not help — the condition is part of an `&&` list,
so `-e` does not trigger, and the exit code is still 1.

The fix is an explicit final `exit 0`, or writing the guard as `if … fi`.

## Why it is not obvious

`[[ cond ]] && cmd` reads as a statement, not an expression, and everywhere else in the
script it behaves like one. The failure only appears at the boundary — when something
*reads* the exit code. Inside a terminal nobody looks, so the bug can live for months and
surface the day the script is wired into a hook, a CI step or a health check.

The reported symptom is also misleading. A harness that runs the script prints something
like "hook exited nonzero — its output above may be partial", which sends you looking for
truncated output. There is none: the output is complete and the status is a lie.

Note the inversion, which is what makes it expensive: **the alarm fires on the success
path**. On the quiet path — nothing found, the `echo` runs — the script exits 0 and looks
healthy. So the warning appears exactly when the script has work to report, and people
learn to ignore it.

## Evidence

**MEASURED**, three runs:

```
$ bash repro-bad.sh;  echo "exit=$?"        # [[ false ]] && echo   as last line
exit=1
$ bash repro-good.sh; echo "exit=$?"        # same logic as if/fi, plus explicit exit 0
exit=0
$ bash repro-e.sh;    echo "exit=$?"        # identical to repro-bad.sh but with set -e
exit=1
```

**READ.** The rule is POSIX: the exit status of a script is that of the last command
executed, and an `AND` list returns the status of the last command it actually ran. This
is not a bash quirk and not version-dependent.

## How to re-check

The one-liner in `recheck` reproduces it in three lines. To audit a tree for the pattern:

```bash
for f in $(git ls-files '*.sh'); do
  tail -n 1 "$f" | grep -qE '^\s*(\[\[|\[|test ).*\]\]?\s*&&' && echo "$f"
done
```

Not exhaustive — it misses a guard clause followed by comments or a blank line — but it
finds the common shape.

## What it costs you not to know

A status script wired into a session-start report exits 1 whenever it finds a running
server. Every session opens with a warning that its own status output may be incomplete.
The output is fine. After a week the warning is background noise, and when a *real*
partial report happens nobody looks.

Two general lessons that outlive the specific bug, both worth applying to any script a
machine reads:

- **End such a script with an explicit `exit 0`.** State the intended status; do not let
  it be inherited from whatever the last conditional happened to evaluate to.
- **A green or red exit code deserves the same scepticism as a green test suite.** Ask
  what the code is the status *of*. In a pipeline it is the last stage, not the command
  you care about — `cmd | tee log` succeeds when `cmd` fails, unless `set -o pipefail`
  or `${PIPESTATUS[0]}` says otherwise.

## See also

- [[opus5-subagent-prompt-line]] — the other kind of harness surprise: behaviour with no
  configuration surface at all.
