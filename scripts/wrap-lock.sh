#!/usr/bin/env bash
# Serialize the closing part of /wrap between parallel sessions.
#
# Why: two sessions in one checkout both append to .agent-memory/MEMORY.md and
# both touch today's status snapshot. Nothing in git mediates that — the second
# write simply overwrites what the first one added. A lock turns a silent
# overwrite into a wait.
#
# Staleness is measured by AGE, not by a live process. The holder is a session,
# not a process: the shell that runs `acquire` exits immediately, so probing its
# PID would always report "dead" and the lock would never hold. The PID in the
# lock file is information for a human, nothing more.
#
# The lock lives in the git directory: never committed, and each worktree has
# its own — which is right, because each worktree carries its own memory copy.
#
#   bash .floppy/run lock acquire "denoise eval"   # 0 = taken, 1 = held
#   bash .floppy/run lock release
#   bash .floppy/run lock status
#
# WRAP_LOCK_MAX_AGE_MIN (default 30) — after this age the lock is considered
# abandoned and can be taken over. A /wrap takes minutes, not half an hour.
set -uo pipefail
cd "${FLOPPY_REPO:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"

MAX_AGE_MIN="${WRAP_LOCK_MAX_AGE_MIN:-30}"

gitdir="$(git rev-parse --git-dir 2>/dev/null)" || { echo "not a git repository"; exit 2; }
lock="$gitdir/wrap.lock"          # a directory: mkdir is atomic
owner="$lock/owner"

# Is the owner file older than MAX_AGE_MIN minutes? A yes/no question, and
# `find -mmin` answers it directly and portably. This used to compute an exact
# age via `stat -c %Y`, which is GNU-only: macOS ships BSD stat, has no such
# flag, and the `|| echo 0` fallback made every lock on this machine read as
# ~57 years old — so it was always "abandoned" and never actually held. No
# owner file at all counts as stale too, the same as the old 9999-minute answer.
is_stale() {
  [[ -f "$owner" ]] || return 0
  [[ -n "$(find "$owner" -mmin +"$MAX_AGE_MIN" 2>/dev/null)" ]]
}

write_owner() {
  printf 'owner=%s\nsince=%s\npid=%s\nhost=%s\n' \
    "$1" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$$" "$(hostname 2>/dev/null || echo '?')" > "$owner"
}

case "${1:-}" in
  acquire)
    label="${2:-session}"
    if mkdir "$lock" 2>/dev/null; then
      write_owner "$label"
      echo "ok lock acquired by '$label'"
      exit 0
    fi

    if ! is_stale; then
      echo "x another session holds the wrap lock (younger than ${MAX_AGE_MIN} min):"
      sed 's/^/    /' "$owner" 2>/dev/null
      echo "  Wait for it to finish, then run acquire again."
      echo "  Do not remove $lock by hand: that session is writing memory right now."
      exit 1
    fi

    echo "! the lock is older than ${MAX_AGE_MIN} min. Taking it over."
    echo "  A /wrap does not take that long, so that session was abandoned."
    echo "  Check MEMORY.md and today's status snapshot for a half-written entry"
    echo "  before you commit."
    sed 's/^/    was: /' "$owner" 2>/dev/null
    write_owner "$label"
    exit 0
    ;;

  release)
    if [[ ! -d "$lock" ]]; then
      echo "ok nothing to release"
      exit 0
    fi
    rm -f "$owner"
    rmdir "$lock" 2>/dev/null && echo "ok lock released" || { echo "x could not release $lock"; exit 1; }
    exit 0
    ;;

  status)
    if [[ -d "$lock" ]]; then
      if is_stale; then
        echo "held but abandoned (older than ${MAX_AGE_MIN} min):"
      else
        echo "held, younger than ${MAX_AGE_MIN} min:"
      fi
      sed 's/^/    /' "$owner" 2>/dev/null
      exit 1
    fi
    echo "free"
    exit 0
    ;;

  *)
    echo "usage: wrap-lock.sh acquire [label] | release | status"
    exit 2
    ;;
esac
