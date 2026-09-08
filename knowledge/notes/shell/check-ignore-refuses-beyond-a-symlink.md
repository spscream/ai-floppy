---
name: check-ignore-refuses-beyond-a-symlink
description: git check-ignore exits 128 for a path that traverses a symlink — a refusal to answer, which the two-valued idiom `if ! git check-ignore -q` reads as "not ignored" and acts on
area: shell
verified_on: 2026-09-08
verified_against: "git on Linux 6.18 (WSL2); measured in this plugin while wiring a scope whose container sits under a symlinked directory"
recheck: "In a repository, symlink a directory and ask about a path underneath the link: git check-ignore -q -- link/file, then echo $?"
platforms: linux, macos
requires: command -v git
recheck_cmd: d=$(mktemp -d) && git -C "$d" init -q && mkdir -p "$d/real" && : > "$d/real/f" && ln -s real "$d/link" && printf "/real\n" > "$d/.gitignore" && cd "$d" && git check-ignore -q -- link/f 2>/dev/null; a=$?; git check-ignore -q -- real/f; b=$?; printf "%s %s\n" "$a" "$b"; rm -rf "$d"; true
expect: 128 0
---

# `git check-ignore` has three exit codes, and scripts treat it as two

## The fact

`git check-ignore` answers with three exit codes:

- `0` — the path is ignored;
- `1` — it is not;
- `128` — git could not answer at all.

A path that traverses a symlink is the third case, not the second:

```
$ git check-ignore -v -- .agent-memory/common
fatal: pathspec '.agent-memory/common' is beyond a symbolic link
$ echo $?
128

$ git check-ignore -v -- .agent-memory        # the symlink itself is fine
.gitignore:14:/.agent-memory	.agent-memory
```

## Why it is not obvious

The command reads as a yes/no question, and shell makes a yes/no test the natural way to ask
it. A refusal to answer has no place in that shape, so it is silently converted into "no" —
and "no" is the branch that writes.

## Evidence

**MEASURED**, 2026-09-08, in this plugin. The memory directory is a symlink into another
repository, and `/.agent-memory` in `.gitignore` already covered everything beneath it.
Asking about a path *under* the link returned 128; asking about the link itself returned a
normal answer naming the rule and its line.

**Incident**, same day: the idiom `if ! git check-ignore -q -- "$p"; then add_rule; fi` read
128 as "not ignored" and appended an ignore rule that was already covered — once per verb
that called the function, so two identical blocks in a file neither verb should have touched.
Nothing failed. The repository was simply left dirty, and only a test asserting the file was
untouched caught it.

## How to re-check

The `recheck_cmd` builds a repository with a symlinked directory and asks twice: once beyond
the link (128), once at a real path (0).

## What it costs you not to know

A boolean test turns a refusal into a confident "no", and the code takes the action the "no"
implies — here, writing to a file that should not have been touched, in a layout where
everything else was already correct.

Three things follow:

- **Ask about a path git can resolve** — the real directory, or the symlink itself — not
  something underneath the link.
- **Distinguish 128 from 1 whenever the answer drives a write**:
  `git check-ignore -q -- "$p"; rc=$?` and branch on all three.
- The same shape applies to any git plumbing taking a pathspec. "beyond a symbolic link" is a
  refusal, and every two-valued test converts a refusal into an answer.

## See also

- [[find-does-not-follow-symlinked-root]] — the same layout, the other tool that goes quiet
  on it.
