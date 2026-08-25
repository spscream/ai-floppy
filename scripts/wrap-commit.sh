#!/usr/bin/env bash
# The tail of /wrap in one call: gate, stage, commit, pull, push, unlock.
#
# Why a script. Two reasons, and the second one matters more.
#
# 1. Fewer points where the model stops and decides. These five steps always
#    run together, in this order, and never mean anything separately.
# 2. The order itself is a trap that was measured, and prose did not keep it.
#    `pull` comes AFTER the commit, not before: with no commits of your own the
#    pull takes the merge path, walks past rebase.autoStash, and refuses on any
#    file the other machine touched. And "push straight after the commit" is a
#    rule that two machines break in silence — an unpushed batch becomes a
#    divergence the next session has to untangle. A rule that rests on
#    discipline is the case this project writes scripts for.
#
# The human has already seen what goes out: wrap-check.sh printed the diff.
# This script re-runs the gates anyway, because between the two calls a
# parallel session may have written.
#
# Output is English on purpose: the wrap-* scripts are portable.
#
#   bash .floppy/run commit -m "message" <file> [file...]
#   bash .floppy/run commit -m "message" --no-push <file> [file...]
#
# Runs on macOS bash 3.2: no mapfile, no declare -A, no GNU-only flags.
set -uo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
cd "${FLOPPY_REPO:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"

# An array, not a string: a path with a space in it would otherwise split into
# two arguments and stage something nobody named. bash 3.2 has ordinary arrays;
# only the associative ones are missing.
msg=""
push=1
files=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    -m) msg="${2:-}"; shift 2 ;;
    --no-push) push=0; shift ;;
    -*) echo "unknown flag: $1"; exit 2 ;;
    *) files+=("$1"); shift ;;
  esac
done

if [[ -z "$msg" ]]; then
  echo "no message: bash .floppy/run commit -m \"message\" <file> [file...]"
  echo "  the message is about the substance of the facts, not \"updated memory\""
  exit 2
fi
if [[ ${#files[@]} -eq 0 ]]; then
  echo "no files: pass the files this session wrote, never a directory"
  echo "  git add .agent-memory docs would stage a parallel session's half-written note"
  exit 2
fi

hr() { printf '%s\n' "-- $1"; }
# Released via a trap on EXIT, not by calling unlock at each exit path: a lock
# left behind by a finished session makes the next one wait half an hour for a
# stale entry, and an explicit call at every exit is exactly the shape that
# already went missing once — four early gate/stage/commit failures skipped
# it. A trap cannot be forgotten by a later edit that adds a fifth. Idempotent:
# wrap-lock.sh release on an already-released lock is a no-op, so the visible
# release printed at the end of a successful run and the trap's silent
# safety-net call never conflict.
unlock() { bash "$here/wrap-lock.sh" release >/dev/null 2>&1; }
trap unlock EXIT

# ---------- gates ----------
hr "gates"
if ! bash "$here/memory-lint.sh" >/dev/null 2>&1; then
  echo "  memory lint is red — run bash .floppy/run check with your file list"
  exit 1
fi
guard_out="$(bash "$here/wrap-guard.sh" "${files[@]}" 2>&1)"
if [[ $? -ne 0 ]]; then
  echo "  the file list no longer matches the tree:"
  echo "$guard_out" | grep -E '^  x' | head -8
  echo "  (a parallel session may have written between check and commit)"
  exit 1
fi
echo "  memory clean, file list matches"

# ---------- stage ----------
# Enumerated, never a directory, and never `git add -A`: this tree holds nested
# repositories and other people's working copies.
hr "stage"
git add -- "${files[@]}" || { echo "  git add failed"; exit 1; }
n=$(git diff --cached --name-only | wc -l | tr -d ' ')
echo "  staged $n file(s)"

# ---------- commit ----------
hr "commit"
if ! git commit -q -m "$msg"; then
  echo "  git commit failed — if it was .git/index.lock, another session is committing:"
  echo "  wait, retry once, and hand it to the human rather than breaking the lock"
  exit 1
fi
git log --oneline -1 | sed 's/^/  /'

# ---------- pull, then push ----------
# In this order deliberately: see the header. With a commit of our own the pull
# takes the rebase path and autoStash applies.
hr "sync"
if ! git pull --rebase --quiet; then
  echo "  pull --rebase failed or conflicted. The commit is made and safe locally."
  echo "  Resolve it by hand, then push. Not pushing now."
  exit 1
fi
if [[ $push -eq 0 ]]; then
  echo "  --no-push: commit stays local. Two machines read master, so push soon."
  exit 0
fi
if ! git push --quiet; then
  echo "  push failed (network/VPN?). The commit is local; the second machine cannot see it."
  echo "  Retry: git push"
  exit 1
fi
echo "  pushed to $(git rev-parse --abbrev-ref --symbolic-full-name '@{upstream}' 2>/dev/null)"

# ---------- unlock ----------
hr "lock"
bash "$here/wrap-lock.sh" release | sed 's/^/  /'

printf '\nsession closed. Memory, slice and procedure are committed and pushed.\n'
