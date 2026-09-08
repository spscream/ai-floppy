---
name: two-dot-diff-counts-other-commits-as-deletions
description: After a fetch, git diff main..branch shows everything other people added as deletions by your branch; what a branch contributes is the three-dot diff, counted from the merge base
area: practice
verified_on: 2026-09-08
verified_against: "git on Linux 6.18 (WSL2); reproduced in a scratch repository with one commit on each side"
recheck: "In a scratch repository commit one file on a branch and a different file on the base, then compare git diff --name-only base..branch with base...branch"
platforms: linux, macos
requires: command -v git
recheck_cmd: d=$(mktemp -d) && cd "$d" && git init -q && git config user.email t@e && git config user.name t && : > base && git add base && git commit -qm base && git switch -qc topic && printf mine > mine.txt && git add mine.txt && git commit -qm mine && git switch -q - && printf theirs > theirs.txt && git add theirs.txt && git commit -qm theirs && printf "%s %s\n" "$(git diff --name-only HEAD..topic | wc -l | tr -d " ")" "$(git diff --name-only HEAD...topic | wc -l | tr -d " ")"; rm -rf "$d"; true
expect: 2 1
---

# A two-dot diff answers a different question than "what did my branch change"

## The fact

`git diff A..B` compares two tips. After a fetch brings other people's commits into `A`,
everything those commits added appears in the diff as a **deletion by your branch**. The
branch has not deleted anything; it simply does not have those files.

What a branch *contributes* is the three-dot diff, `git diff A...B`, which counts from the
merge base.

## Why it is not obvious

The two-dot form is the one that reads like plain English — "the difference between main and
my branch" — and it is right whenever the base has not moved. It stops being right silently,
at a fetch, which is an action nobody associates with changing the meaning of a diff.

The output is also plausible: a list of files, with plus and minus lines, in the shape you
expected. Only the size is wrong.

## Evidence

**MEASURED**, 2026-09-08, while preparing a library release: a branch that changed **one** file
appeared to change three, exactly because the base had moved underneath it. Reproduced in a
scratch repository — one commit on the branch, one different commit on the base — where the
two-dot diff names two files and the three-dot diff names one.

## How to re-check

The `recheck_cmd` builds that scratch repository and prints both counts: `2 1`.

## What it costs you not to know

A review scoped from the wrong diff reads someone else's addition as your deletion, and a
release note counts files that were never touched. The failure survives review, because the
diff itself looks entirely normal.

Two neighbouring habits from the same day:

- **Whether a merge conflicts is measured with `git merge-tree`**, not argued from dates.
- **Switch rerere off while measuring a merge or rebase** — `git -c rerere.enabled=false` —
  or a previously recorded resolution answers the question for you.

## See also

- [[compound-cd-measures-one-tree-twice]] — the other measurement that returns a confident
  number about the wrong thing.
