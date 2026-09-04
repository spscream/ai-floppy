---
name: find-does-not-follow-symlinked-root
description: find over a symlinked directory returns nothing and exits 0, so a checker that walks one passes while looking at zero files
area: shell
verified_on: 2026-09-05
verified_against: "GNU findutils on Linux 6.18 (WSL2); POSIX behaviour, holds on macOS"
recheck: "mkdir -p /tmp/r/real && touch /tmp/r/real/{a,b}.md && ln -s /tmp/r/real /tmp/r/link && find /tmp/r/link -name '*.md' | wc -l"
platforms: linux, macos
recheck_cmd: d=$(mktemp -d) && mkdir -p "$d/real" && : > "$d/real/a.md" && : > "$d/real/b.md" && ln -s "$d/real" "$d/link" && printf '%s %s %s\n' "$(find "$d/link" -name '*.md' | wc -l | tr -d ' ')" "$(find "$d/real" -name '*.md' | wc -l | tr -d ' ')" "$(find -L "$d/link" -name '*.md' | wc -l | tr -d ' ')"; rm -rf "$d"; true
expect: 0 2 2
---

# A checker that walks a symlinked directory sees nothing and calls it clean

## The fact

`find <symlink-to-dir>` does not descend into the target. It yields nothing, prints no
error and exits **0**. `find -L <symlink>` descends. The same holds for `grep -r`, for
`os.walk` in Python, and for any walk that does not opt in.

An empty result is therefore indistinguishable from "there was nothing to find", and any
check built on the walk reports success.

## Why it is not obvious

Every other tool in the pipeline follows the symlink: `cd`, `cat`, `ls`, the editor. The
walk is the one that does not, and it fails by being quiet rather than by erroring. The
setup where it bites — a directory moved into another repository and symlinked back into
place — is also the setup where the walk matters most.

## Evidence

**MEASURED**, 2026-09-05, four probes against a directory holding two `.md` files:

```
find <symlink>      -> 0
find <real path>    -> 2
find -L <symlink>   -> 2
exit code of the first probe -> 0
```

**Incident**, measured 2026-08-25 in this plugin: the memory linter walked its directory
with a plain `find`. In the layout where memory lives in another repository that
directory is a symlink, so every loop ran over an empty list and the run printed
`clean: 0 notes`. That linter is the **first commit gate**, so the whole quality check on
memory was dead in that layout while staying green.

## How to re-check

The one-liner in `recheck` reproduces it in four commands. Expect `0`; then repeat with
`find -L` and expect `2`.

## What it costs you not to know

Not a wrong answer — a *missing* one, wearing the colour of success. Everything that
depends on the walk silently stops working, and nothing anywhere goes red.

Three things follow, and they generalise past `find`:

- **walking a tree a symlink can reach — use `find -L`.** `-not -path` exclusions keep
  working: paths are built from the starting point. In Python, `os.walk(..., followlinks=True)`.
- **assert the number found, not the colour.** `clean: N notes` with N expected. An
  assertion on `rc=0` passes for a check that looked at nothing.
- **keep a positive control beside it** — a deliberately broken file that must go red.
  Without one, "green" and "did not run" are the same observation.

## See also

- [[and-list-as-last-line-of-script]] — the other way a shell check reports the wrong
  colour.
