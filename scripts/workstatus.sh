#!/usr/bin/env bash
# Live state of the work in one call: background jobs, git, divergence from
# origin, the memory wiring on this machine, the workplace memory repository,
# and the status slice.
#
# Why a script, not a handful of commands in the prompt: tokens are not spent
# on the commands, they are spent on the OUTPUT. A bare `ps` prints dozens of
# lines when three matter; a naive divergence check prints every value instead
# of the one that changed. The script returns an answer, not raw material.
#
# Filtering principle: cut the noise, print the unexpected as it is. Filter
# too hard and the report stops catching the thing it exists for — a stuck
# process, a divergence from origin, a stray hook.
#
#   bash .floppy/run status
#   bash .floppy/run status --flow   # plus the state of the process half
#
# The project half of this report — anything that names this particular
# project's data or stands (servers, corpora, a build system) — is not here.
# It lives behind a hook in the consumer repository: see "project hook" below.
#
# Runs on macOS bash 3.2 as well as GNU/Linux bash: no `stat -c`,
# `ps --no-headers`, `ss`, or `timeout` without a fallback — all GNU-only, and
# on a Mac the report would otherwise turn silently into a wall of errors.
set -uo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
cd "${FLOPPY_REPO:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
repo="$(pwd)"

# Config values resolved once, used everywhere below — including message
# strings, so a message never drifts from the value it describes.
mem_dir="${FLOPPY_MEMORY_DIR:-.agent-memory}"
now_file="${FLOPPY_STATUSES_NOW:-docs/statuses/NOW.md}"
statuses_dir="${now_file%/*}"
hook="$repo/.floppy/workstatus-project.sh"

# Parse arguments through $#: in bash 3.2 on macOS, expanding "$@" with zero
# positional parameters under `set -u` raises "unbound variable", and the
# script would die on the ordinary call with no flags at all.
FLOW=0
if [[ $# -gt 0 ]]; then
  for __a in "$@"; do [[ "$__a" == "--flow" ]] && FLOW=1; done
fi

hr() { printf '%s\n' "-- $1"; }

# mtime in epoch seconds: GNU stat, else BSD (macOS).
mtime() { stat -c %Y "$1" 2>/dev/null || stat -f %m "$1" 2>/dev/null; }
# same, human-readable
mtime_h() {
  stat -c %y "$1" 2>/dev/null | cut -c1-16 \
    || stat -f '%Sm' -t '%Y-%m-%d %H:%M' "$1" 2>/dev/null
}

# ---------- background jobs ----------
hr "background"
found=0
while read -r pid etime cmd; do
  [[ -z "${pid:-}" ]] && continue
  found=1
  short=$(echo "$cmd" | cut -c1-70)
  printf '  [%s] %s\n' "$etime" "$short"
done < <(ps -eo pid,etime,args 2>/dev/null \
  | grep -E "gradlew|cargo |xcodebuild|swift test|npm run|yarn |pnpm |make |pytest|go test|docker (build|compose)|mvn " \
  | grep -vE "grep|/bin/zsh -c|shell-snapshots" \
  | awk '{print $1, $2, substr($0, index($0,$3))}')
[[ $found -eq 0 ]] && echo "  empty"

# ---------- git ----------
hr "git"
echo "  $(git status -sb | head -1)"
dirty=$(git status --short | head -8)
if [[ -n "$dirty" ]]; then echo "$dirty" | sed 's/^/  /'; else echo "  tree is clean"; fi
git log --oneline -3 2>/dev/null | sed 's/^/  /'

# ---------- origin ----------
# A fresh `git fetch` before comparing: without it a local check only answers
# for what this checkout already knew about, and a push made elsewhere is
# invisible until something else happens to fetch. The network may be down;
# fetch is best-effort, and the report still prints, saying plainly that the
# numbers below are stale.
hr "origin"
fetch_ok=0
if command -v timeout >/dev/null 2>&1; then
  timeout 15 git fetch --quiet --no-tags origin 2>/dev/null && fetch_ok=1
elif command -v gtimeout >/dev/null 2>&1; then
  gtimeout 15 git fetch --quiet --no-tags origin 2>/dev/null && fetch_ok=1
else
  git fetch --quiet --no-tags origin 2>/dev/null && fetch_ok=1
fi
[[ $fetch_ok -eq 0 ]] && echo "  fetch did not go through (network/VPN) — the numbers below are stale"
up=$(git rev-parse --abbrev-ref --symbolic-full-name '@{upstream}' 2>/dev/null)
if [[ -n "${up:-}" ]]; then
  set -- $(git rev-list --left-right --count "$up...HEAD" 2>/dev/null)
  behind=${1:-0}; ahead=${2:-0}
  if [[ "$behind" -eq 0 && "$ahead" -eq 0 ]]; then
    echo "  in sync with $up"
  else
    [[ "$behind" -gt 0 ]] && printf '  BEHIND %s: %s commit(s) — pull --rebase before you write\n' "$up" "$behind"
    [[ "$ahead" -gt 0 ]] && printf '  ahead of %s: %s commit(s) not pushed\n' "$up" "$ahead"
    git log --oneline -2 "$up" 2>/dev/null | sed 's/^/    origin: /'
  fi
else
  echo "  branch has no upstream"
fi
# Sorted by the tip commit's committer date, which is when it was made, not
# when it reached the remote — so this names the branch, not "recently
# pushed", which the sort does not actually establish.
other=$(git branch -r --sort=-committerdate --format='%(refname:short) %(committerdate:relative)' 2>/dev/null \
  | awk -v up="$up" '$1 != up && $1 !~ /HEAD/' | head -2)
[[ -n "$other" ]] && echo "$other" | sed 's/^/  other branch, newest commit: /'

# ---------- memory wiring on this machine ----------
# The one wiring step whose absence is silent: without it a session writes
# memory into a second copy under ~/.claude and nobody is told. The encoding
# of the path is computed in exactly one place, memory-link.sh, so this asks
# it rather than repeating the rule and drifting from it.
hr "memory wiring"
link_out="$(bash "$here/memory-link.sh" --check 2>&1)"
if [[ $? -eq 0 ]]; then
  echo "  wired to the Claude Code memory directory"
else
  echo "  ${link_out#x }"
fi

# ---------- memory hosted in another repository ----------
# The "git" section above cannot see it: the memory path is gitignored here on
# purpose. Without this section /start reports a clean tree while the session's
# notes sit uncommitted somewhere else — the exact blindness the section exists
# to remove.
if [[ "${FLOPPY_MEMORY_EXTERNAL:-0}" == "1" ]]; then
  hr "memory store"
  st="${FLOPPY_MEMORY_STORE:-}"
  if [[ -z "$st" ]]; then
    echo "  $mem_dir -> ${FLOPPY_MEMORY_REAL:-?}, which is in no git repository — notes cannot be published"
  else
    st_dirty=$(git -C "$st" status --porcelain | wc -l | tr -d ' ')
    st_ahead=$(git -C "$st" rev-list --count '@{u}..HEAD' 2>/dev/null || echo '?')
    if [[ "$st_dirty" == "0" && "$st_ahead" == "0" ]]; then
      echo "  $st — clean and pushed"
    else
      [[ "$st_dirty" != "0" ]] && echo "  $st_dirty uncommitted in $st"
      [[ "$st_ahead" != "0" && "$st_ahead" != "?" ]] && echo "  $st_ahead unpushed in $st — the next machine cannot see them"
    fi
  fi
fi

# ---------- workplace memory ----------
# A second repository this project's git does not see at all: $mem_dir/local
# is a symlink into it. An unpushed note there blinds a second machine the
# same way an unpushed commit here does, but the "git" section above says
# nothing about it.
#
# Only shown when workplace_repo is configured — see wrap-check.sh's comment
# on the same condition. A project that never opted in gets no section here,
# not a "not wired" nudge that dead-ends into a config error.
if [[ -n "${FLOPPY_WORKPLACE_REPO:-}" ]]; then
  hr "workplace memory"
  wp="${FLOPPY_WORKPLACE_MEMORY_DIR:-$HOME/agents_memory}"
  if [[ ! -d "$wp/.git" ]]; then
    echo "  not wired: no $wp — bash .floppy/run workplace"
  elif [[ ! -L "$mem_dir/local" ]]; then
    echo "  repository exists, but $mem_dir/local is not a symlink — bash .floppy/run workplace"
  else
    wp_dirty=$(git -C "$wp" status --porcelain | wc -l | tr -d ' ')
    wp_ahead=$(git -C "$wp" rev-list --count '@{u}..HEAD' 2>/dev/null || echo '?')
    [[ "$wp_dirty" == "0" && "$wp_ahead" == "0" ]] && echo "  clean and pushed"
    [[ "$wp_dirty" != "0" ]] && echo "  $wp_dirty uncommitted change(s) ($wp)"
    [[ "$wp_ahead" != "0" && "$wp_ahead" != "?" ]] && echo "  $wp_ahead commit(s) not pushed — a second machine cannot see them"
    [[ "$wp_ahead" == "?" ]] && echo "  the memory branch has no upstream"
  fi
fi

# ---------- status slice ----------
# Shows the current-state file, not the newest journal entry: /start reads the
# former. The journal matters here for exactly one thing — if it is newer,
# someone wrote history and did not update the current state, and the current
# state now lies about being up to date.
hr "status slice"
last=$(ls -t "$statuses_dir"/*_status.md 2>/dev/null | head -1)
if [[ -f "$now_file" ]]; then
  echo "  $now_file (modified $(mtime_h "$now_file"))"
  if [[ -n "$last" ]] && [[ $(mtime "$last") -gt $(mtime "$now_file") ]]; then
    echo "  ! journal entry $last is newer — the current state may not have been updated"
  fi
else
  echo "  ! $now_file is missing — nothing for /start to read"
fi
[[ -n "$last" ]] && echo "  journal: $last"
echo "  last commit: $(git log -1 --format=%cd --date=format:'%Y-%m-%d %H:%M' 2>/dev/null)"

# ---------- project hook ----------
# The project half of this report lives in the consumer repository: servers,
# corpora, whatever this project cares about. A broken hook must not take the
# generic report down with it — a status command that dies tells you nothing
# about the state it was asked about. A hook that exists but is not marked
# executable is reported too, not silently skipped: a chmod that never
# happened should not look like "this project has no project section".
if [[ -x "$hook" ]]; then
  hr "project"
  bash "$hook" || echo "  ! project hook exited nonzero — its output above may be partial"
elif [[ -e "$hook" ]]; then
  hr "project"
  echo "  ! project hook exists but is not executable — chmod +x ${hook#"$repo"/}"
fi

# ---------- state of the process half (--flow) ----------
# Added in place of four separate commands run back to back — and the honest
# accounting is narrower than the first version of this comment claimed. A
# session is billed per TURN (~649 tokens of reasoning over 48 measured runs),
# and parallel calls issued in one block cost as one turn. These four are
# independent reads: a model may well issue them together, in which case no
# turn is removed at all. What the fold does buy is one prepared answer instead
# of four raw outputs, and one line in the prompt instead of four.
# (The superseded framing said "the model reasons before every tool call,
# ~7.5k tokens across six calls"; re-measured it was 2.6k, and the unit is the
# turn. wrap-check/wrap-commit are unaffected: their steps were sequential
# decisions, so folding them does remove turns.)
#
# Printed only behind the flag: on a branch working on something else, this is
# somebody else's half, and its state there is noise.
if [[ $FLOW -eq 1 ]]; then
  hr "process: memory"
  lint_out="$(bash "$here/memory-lint.sh" 2>&1)"
  lint_rc=$?
  if [[ $lint_rc -eq 0 ]]; then
    echo "$lint_out" | grep -E '^clean:' | sed 's/^/  /'
  else
    # First eight and a count of the rest: forty near-identical lines is the
    # raw material this script exists to cut down. The full list is one call
    # away, and the line below says so.
    lint_n=$(echo "$lint_out" | grep -cE '^  x')
    echo "  MEMORY LINT IS RED, $lint_n problem(s) — fix before touching memory further"
    echo "$lint_out" | grep -E '^  x' | head -8 | sed 's/^/  /'
    [[ "$lint_n" -gt 8 ]] && echo "    ... and $((lint_n - 8)) more: bash .floppy/run lint"
  fi
  # Warnings print in both branches: on a red run they would otherwise vanish
  # along with the green branch, and a note over its cap is a fact about the
  # memory, not a consequence of the lint failing.
  echo "$lint_out" | grep -E '^  !' | sed 's/^ */  warning: /'

  hr "process: lock and worktrees"
  echo "  wrap lock: $(bash "$here/wrap-lock.sh" status 2>&1 | head -1)"
  # An extra worktree is a separate memory directory, and without its own
  # bash .floppy/run link a session there writes memory past the repository,
  # silently. So the list prints only when there is more than one — a single
  # worktree is the normal case, not news.
  wt_n=$(git worktree list 2>/dev/null | wc -l | tr -d ' ')
  if [[ "${wt_n:-1}" -gt 1 ]]; then
    echo "  worktrees: $wt_n — each one needs its own bash .floppy/run link"
    git worktree list | sed 's/^/    /'
  else
    echo "  worktrees: one, none extra"
  fi

  hr "process: recent edits"
  git log --oneline -4 -- .floppy "$mem_dir" 2>/dev/null | sed 's/^/  /'
fi
