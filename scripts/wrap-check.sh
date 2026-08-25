#!/usr/bin/env bash
# Everything /wrap has to look at before it commits, in one call.
#
# Why a script: not to shorten the output — it was already short — but to cut
# the number of points where the model stops and decides. Reasoning happens
# before every tool call, and on a measured /start run it came to ~7.5k tokens
# across six calls. /wrap prescribed four separate read-only commands here
# (memory-lint, wrap-guard, git status, git diff --stat) plus a look at the
# workplace memory repository. They always run together and always in this
# order, so they are one question, not five.
#
# Read-only on purpose. Staging and committing live in wrap-commit.sh: the
# human is supposed to SEE this output before anything is written.
#
# Output is English on purpose: the wrap-* and memory-* scripts are portable
# and will one day leave for a project of their own. The memory is not.
#
#   bash .floppy/run check <file> [file...]
#
# Exit 0 only when the memory is clean AND the file list survives the guard.
# Runs on macOS bash 3.2: no mapfile, no declare -A, no GNU-only flags.
set -uo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
cd "${FLOPPY_REPO:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"

if [[ $# -eq 0 ]]; then
  echo "no files given: pass the files this session wrote"
  echo "  bash .floppy/run check <file> [file...]"
  exit 2
fi

hr() { printf '%s\n' "-- $1"; }
rc=0

# ---------- memory invariants ----------
hr "memory"
lint_out="$(bash "$here/memory-lint.sh" 2>&1)"
if [[ $? -eq 0 ]]; then
  echo "$lint_out" | grep -E '^clean:' | sed 's/^/  /'
else
  rc=1
  lint_n=$(echo "$lint_out" | grep -cE '^  x')
  echo "  MEMORY LINT IS RED, $lint_n problem(s) — fix yours, name someone else's and leave it"
  echo "$lint_out" | grep -E '^  x' | head -8
  [[ "$lint_n" -gt 8 ]] && echo "    ... and $((lint_n - 8)) more: bash .floppy/run lint"
fi
# Warnings print in both branches: a note over the cap is a fact about the
# memory, not a consequence of an error, and it would vanish with the green
# branch otherwise.
echo "$lint_out" | grep -E '^  !' | sed 's/^  !/  warning:/'

# ---------- does the list match what actually changed ----------
hr "file list"
guard_out="$(bash "$here/wrap-guard.sh" "$@" 2>&1)"
if [[ $? -ne 0 ]]; then
  rc=1
  echo "$guard_out" | grep -E '^  x' | head -10
  echo "  (full report: bash .floppy/run guard <your files>)"
else
  echo "$guard_out" | grep -E '^safe to stage' | sed 's/^/  /'
fi

# ---------- what is actually going out ----------
# The commit closes the session, which is the moment the human has already
# turned away. So the file list and the size of the change belong in the
# conversation, not only in git history.
hr "going out"
git status --short -- "$@" | sed 's/^/  /'
echo
git diff --stat -- "$@" | tail -20 | sed 's/^/  /'
staged=$(git diff --cached --numstat -- "$@" | wc -l | tr -d ' ')
[[ "${staged:-0}" != "0" ]] && echo "  note: $staged file(s) are already staged"

# ---------- the second repository ----------
# .agent-memory/local is a symlink into ~/agents_memory, and this project's git
# does not look there at all: `git status` here stays clean even when a note
# was written. An unpushed note there blinds the second machine exactly like an
# unpushed commit here.
hr "workplace memory"
wp="${WORKPLACE_MEMORY_DIR:-$HOME/agents_memory}"
if [[ ! -d "$wp/.git" ]]; then
  echo "  not wired: no $wp — bash .floppy/run workplace"
else
  wp_dirty=$(git -C "$wp" status --porcelain | wc -l | tr -d ' ')
  wp_ahead=$(git -C "$wp" rev-list --count '@{u}..HEAD' 2>/dev/null || echo '?')
  if [[ "$wp_dirty" == "0" && "$wp_ahead" == "0" ]]; then
    echo "  clean and pushed"
  else
    [[ "$wp_dirty" != "0" ]] && echo "  $wp_dirty uncommitted change(s) in $wp — commit them there separately"
    [[ "$wp_ahead" != "0" && "$wp_ahead" != "?" ]] && echo "  $wp_ahead commit(s) unpushed — the second machine cannot see them"
  fi
fi

printf '\n'
if [[ $rc -eq 0 ]]; then
  echo "ready: bash .floppy/run commit -m \"<message>\" <the same files>"
else
  echo "not ready: fix the red sections above, then run this again"
fi
exit $rc
