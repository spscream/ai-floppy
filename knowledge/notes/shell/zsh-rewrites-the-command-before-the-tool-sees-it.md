---
name: zsh-rewrites-the-command-before-the-tool-sees-it
description: Under zsh an unquoted --include=*.ext aborts the command with "no matches found" and $b:path is read as a history modifier, so the measurement returns nothing rather than something wrong
area: shell
verified_on: 2026-09-08
verified_against: "zsh 5.9 on Linux 6.18 (WSL2), commands issued through a tool whose shell is zsh"
recheck: "Run zsh -c 'b=Feature; print -- ${b:l}' — it prints `feature`, proving :l is a modifier — and run grep -r --include=*.ext in a directory with no such file at the top level"
platforms: linux, macos
requires: command -v zsh
recheck_cmd: x=$(zsh -c "b=Feature; print -- \${b:l}"); y=$(cd "$(mktemp -d)" && zsh -c "echo --include=*.zzz" 2>&1 | grep -c "no matches"); printf "%s %s\n" "$x" "$y"; true
expect: feature 1
---

# zsh edits the command before the tool ever runs it

## The fact

Two rewrites happen in the shell, not in the program being called, and both fail by producing
**nothing** rather than something wrong.

**1. `grep -r --include=*.ex` aborts.** The glob is expanded by the shell, not by grep. In a
directory with no matching file at the top level, zsh finds no match and refuses to run the
command at all: `no matches found`. Quote it: `--include='*.ex'`.

**2. `git show "$b:path"` is a history modifier.** In zsh `:l` means "lowercase", and `:h`,
`:t`, `:r` are modifiers too. The command fails on a mangled branch-plus-path. Write
`git show "${b}:path"`.

## Why it is not obvious

Both idioms are correct in bash, and both appear in documentation and in one's own muscle
memory as portable. The shell's rewrite is invisible: the command that failed is not the
command you wrote, and the error message talks about matches or about a bad object rather than
about quoting.

## Evidence

**MEASURED**, 2026-09-08. `zsh -c 'b=Feature; print -- "${b:l}"'` prints `feature` — the
modifier is real and applies to an ordinary parameter. `echo --include=*.zzz` in an empty
directory returns `zsh:1: no matches found: --include=*.zzz` with a non-zero status and no
command run.

**Cost paid**: the second form gave three empty measurements in a row across three branches
before the modifier was recognised; the first gave an empty grep in a tree where the files
certainly existed.

## How to re-check

The `recheck_cmd` runs both halves: the modifier expansion, and the refusal count from the
unquoted glob.

## What it costs you not to know

Not a wrong answer — **no answer, wearing the shape of one**. An empty grep reads as "this
symbol is not used anywhere", and an empty `git show` reads as "that file is not on that
branch". Both are conclusions, both are false, and neither run happened.

So: check that the command *ran*, not just what it returned. **If a measurement comes back
empty, repeat it under `bash -c` before believing it.**

## See also

- [[interactive-aliases-make-cp-a-silent-no-op]] — the same class: the profile shell changes
  what a command does before the tool sees it.
