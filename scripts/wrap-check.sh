#!/usr/bin/env bash
# Everything /wrap has to look at before it commits, in one call.
#
# Why a script: not to shorten the output — it was already short — but to cut
# the number of TURNS. Reasoning is billed per turn, ~649 tokens of it over 48
# measured runs, and parallel calls issued in one block cost as one turn — so
# folding pays only where it removes a turn. It does here: each step's result
# decided whether the next should run, so the model had to stop and choose
# between them. (An earlier version of this header explained the fold by
# "reasoning happens before every tool call, ~7.5k tokens across six calls".
# That was re-measured and came out three times smaller, with the turn as the
# unit. The conclusion held; the reason did not — see skills/wrap/SKILL.md.)
# /wrap prescribed four separate read-only commands here
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
lint_out="$(bash "$here/memory-lint.sh" 2>&1)"; lint_rc=$?
# Three outcomes, not two. Exit 2 is the linter refusing to check anything at
# all — no memory layout here, or a scope name it cannot use — and it prints a
# sentence rather than "  x" lines. Counting those lines gave "RED, 0
# problem(s)" and nothing else: red with the reason thrown away, which is the
# state a person meets when the wrong project is active in a harness that holds
# several. It stays red, because a wrap whose memory cannot be read is not a
# wrap that should proceed quietly, but it now says why.
if [[ $lint_rc -eq 0 ]]; then
  echo "$lint_out" | grep -E '^clean:' | sed 's/^/  /'
elif [[ $lint_rc -eq 2 ]]; then
  rc=1
  echo "  MEMORY LINT COULD NOT RUN — it refused before checking anything:"
  echo "$lint_out" | sed 's/^/    /'
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

# ---------- localized commands against the skills ----------
# Only for a repository that keeps the rite in its own language as well. The
# section is a gate, not a note: a command that lost a step is this
# repository's own file and fixable in this same wrap, unlike a neighbouring
# session's half-written memory note. Silence was the whole defect — parity was
# held by eye, and an eye does not run on every close.
parity_out="$(bash "$here/parity.sh" 2>&1)"
parity_rc=$?
case "$parity_out" in
  "no localized commands"*) : ;;   # English skills used directly: no section
  *)
    hr "localized commands"
    if [[ $parity_rc -eq 0 ]]; then
      echo "$parity_out" | grep -E '^clean:' | sed 's/^/  /'
    else
      rc=1
      echo "  LOCALIZED COMMANDS HAVE DRIFTED from the skills they translate"
      echo "$parity_out" | grep -E '^(--|  x)' | head -10
      echo "  (full report: bash .floppy/run parity)"
    fi
    ;;
esac

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

# ---------- the memory's own repository, when it is not this one ----------
# Distinct from the workplace section below: that one is a store SHARED across
# projects, this one is this project's own memory, merely hosted elsewhere.
# Reported unconditionally in that layout, because `going out` above is
# structurally blind to it — the memory path is gitignored here, so the diff
# the human is shown before committing would otherwise omit every note the
# session wrote.
if [[ "${FLOPPY_MEMORY_EXTERNAL:-0}" == "1" ]]; then
  hr "memory store"
  st="${FLOPPY_MEMORY_STORE:-}"
  if [[ -z "$st" ]]; then
    rc=1
    echo "  x ${FLOPPY_MEMORY_DIR:-.agent-memory} resolves outside this repository and outside any git repository"
    echo "    (${FLOPPY_MEMORY_REAL:-?}) — nothing can publish these notes"
  else
    echo "  $st"
    git -C "$st" status --short | head -20 | sed 's/^/  /'
    st_ahead=$(git -C "$st" rev-list --count '@{u}..HEAD' 2>/dev/null || echo '?')
    [[ "$st_ahead" != "0" && "$st_ahead" != "?" ]] && echo "  $st_ahead commit(s) unpushed there"
    # `commit` closes it too, so this is information, not a chore for the human.
    echo "  (bash .floppy/run commit closes this store as well as this repository)"
  fi
fi

# ---------- the second repository ----------
# <mem_dir>/local is a symlink into the workplace memory repository, and this
# project's git does not look there at all: `git status` here stays clean
# even when a note was written. An unpushed note there blinds the second
# machine exactly like an unpushed commit here.
#
# Only shown when private_repo is actually configured: on a project that
# never opted into a workplace store, printing "not wired" every time is a
# dead end, not a nudge — following it fails immediately with "set
# workplace_project_key in .floppy/config" (memory-workplace.sh requires
# both keys). No configured repo means no workplace section, not a red flag.
if [[ -n "${FLOPPY_WORKPLACE_REPO:-}" ]]; then
  hr "workplace memory"
  wp="${FLOPPY_WORKPLACE_MEMORY_DIR:-$HOME/agents_memory}"
  if [[ ! -d "$wp/.git" ]]; then
    echo "  not wired: no $wp — bash .floppy/run workplace"
  else
    wp_dirty=$(git -C "$wp" status --porcelain | wc -l | tr -d ' ')
    wp_ahead=$(git -C "$wp" rev-list --count '@{u}..HEAD' 2>/dev/null || echo '?')
    if [[ "$wp_dirty" == "0" && "$wp_ahead" == "0" ]]; then
      echo "  clean and pushed"
    else
      # "separately" was true until commit learned to close this repository
      # too; leaving it would send the human to do by hand what the next call
      # does for them — and, worse, to commit notes this session never claimed.
      [[ "$wp_dirty" != "0" ]] && echo "  $wp_dirty uncommitted change(s) in $wp — name them in your file list and commit closes them too"
      [[ "$wp_ahead" != "0" && "$wp_ahead" != "?" ]] && echo "  $wp_ahead commit(s) unpushed — the second machine cannot see them"
    fi
  fi
fi

printf '\n'
if [[ $rc -eq 0 ]]; then
  echo "ready: bash .floppy/run commit -m \"<message>\" <the same files>"
else
  echo "not ready: fix the red sections above, then run this again"
fi
exit $rc
