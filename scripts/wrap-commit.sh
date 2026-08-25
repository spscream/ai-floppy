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
# commit_push in .floppy/config (default "auto") picks what happens after the
# commit: "auto" pulls --rebase then pushes, same as always; "never" skips
# both — for a repository with no remote configured, "auto" fails the pull
# every time (there is nothing to pull against), forever, with no way to
# reach the push step at all. --no-push still works as a per-call override:
# it skips only the push, not the pull, because it exists for the two-machine
# workflow this was ported from, where staying in sync is wanted even on a
# call that doesn't push yet.
#
# Runs on macOS bash 3.2: no mapfile, no declare -A, no GNU-only flags.
set -uo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
cd "${FLOPPY_REPO:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
mem_dir="${FLOPPY_MEMORY_DIR:-.agent-memory}"

# sync governs the whole pull+push tail; push governs only the push half of
# it, and --no-push below overrides push alone, never sync — see the header.
sync=1; push=1
if [[ "${FLOPPY_COMMIT_PUSH:-auto}" == "never" ]]; then
  sync=0; push=0
fi

# An array, not a string: a path with a space in it would otherwise split into
# two arguments and stage something nobody named. bash 3.2 has ordinary arrays;
# only the associative ones are missing.
msg=""
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
  echo "  git add $mem_dir docs would stage a parallel session's half-written note"
  exit 2
fi

hr() { printf '%s\n' "-- $1"; }

# ---------- where this lands ----------
# This is the dangerous verb: it stages, commits, and pushes. The rite's
# existing principle is that the human sees the diff before anything is
# written (wrap-check.sh); this extends it to seeing WHERE it will be
# written, before the gates below get a chance to run — a gate that refuses
# for an unrelated reason (an unwatched file, a red memory lint) would
# otherwise teach nothing about which repository was actually targeted.
hr "target"
repo="$(pwd)"
branch="$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo '?')"
push_target="$(git rev-parse --abbrev-ref --symbolic-full-name '@{upstream}' 2>/dev/null)"
echo "  repo:   $repo"
echo "  branch: $branch"
if [[ -n "$push_target" ]]; then
  echo "  push:   $push_target"
else
  echo "  push:   no upstream configured"
fi

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
guard_rc=$?
if [[ $guard_rc -ge 126 ]]; then
  # 126/127 is bash's own "could not run the script at all" (missing,
  # unreadable, not executable) — a broken installation, not a finding about
  # the file list. Reported measured: with wrap-guard.sh absent, the message
  # below used to print anyway, sending a human hunting for a session that
  # never existed.
  echo "  wrap-guard.sh could not run (exit $guard_rc) — the file list was not checked:"
  echo "$guard_out" | sed 's/^/    /'
  echo "  this is a broken plugin installation, not a parallel session"
  exit 1
elif [[ $guard_rc -ne 0 ]]; then
  echo "  the file list no longer matches the tree:"
  echo "$guard_out" | grep -E '^  x' | head -8
  echo "  (a parallel session may have written between check and commit)"
  exit 1
fi
echo "  memory clean, file list matches"

# ---------- memory hosted in another repository ----------
# When memory_dir resolves outside this repository, the session wrote into two
# git repositories and closing one of them is not closing the session: an
# unpushed note in the store blinds the next machine exactly as an unpushed
# commit here would, and this repository's `git status` says nothing about it.
#
# The list is split rather than asked for twice. The caller passes the files it
# wrote, in the paths it wrote them — `.agent-memory/flow/x.md` — and this
# translates the memory half into the store's own vocabulary. Requiring two
# lists would mean the rite's text has to know which layout the consumer chose.
# A file this session deleted with `git rm` is already staged, and its path is
# then in neither the worktree nor the index — `git add -- <it>` fails with
# "did not match any files" and takes the whole commit with it. Measured: `git
# add -A -- <path>` fails identically, so widening the add is not the fix.
# Dropping such a path from the add list is not a widening either: the deletion
# is already in the index, which is exactly what the add was for. A path that
# matches nothing anywhere is left in the list, so a typo still fails loudly.
needs_staging() { # $1 = repo dir ("" for this repository), $2 = path
  ns_dir="$1"; ns_path="$2"
  [[ -e "${ns_dir:+$ns_dir/}$ns_path" ]] && return 0
  # Spelled out per repository rather than as ${ns_dir:+-C "$ns_dir"}: that
  # form word-splits and would break on a checkout path containing a space.
  if [[ -n "$ns_dir" ]]; then
    ns_staged="$(git -C "$ns_dir" diff --cached --name-only --diff-filter=D -- "$ns_path" 2>/dev/null)"
  else
    ns_staged="$(git diff --cached --name-only --diff-filter=D -- "$ns_path" 2>/dev/null)"
  fi
  [[ -z "$ns_staged" ]]
}

external="${FLOPPY_MEMORY_EXTERNAL:-0}"
store="${FLOPPY_MEMORY_STORE:-}"
mem_real="${FLOPPY_MEMORY_REAL:-}"
store_files=()
proj_files=()
if [[ "$external" == "1" ]]; then
  mem_prefix=""
  [[ -n "$store" && "$mem_real" != "$store" ]] && mem_prefix="${mem_real#"$store"/}"
  for f in "${files[@]}"; do
    f="${f#./}"
    case "$f" in
      "$mem_dir"/*) rel="${f#"$mem_dir"/}"
                    store_files+=("${mem_prefix:+$mem_prefix/}$rel") ;;
      *)            proj_files+=("$f") ;;
    esac
  done
else
  proj_files=("${files[@]}")
fi

store_unpushed=0
if [[ ${#store_files[@]} -gt 0 ]]; then
  hr "memory store"
  if [[ -z "$store" ]]; then
    echo "  $mem_dir is outside this repository but in no git repository at all."
    echo "  Those notes cannot be published by anything. Nothing was committed."
    exit 1
  fi
  echo "  repo:   $store"
  store_add=()
  for f in "${store_files[@]}"; do
    needs_staging "$store" "$f" && store_add+=("$f")
  done
  if [[ ${#store_add[@]} -gt 0 ]]; then
    git -C "$store" add -- "${store_add[@]}" || { echo "  git add failed in the store"; exit 1; }
  fi
  sn=$(git -C "$store" diff --cached --name-only | wc -l | tr -d ' ')
  if [[ "$sn" == "0" ]]; then
    echo "  nothing to commit there (already committed by a parallel session?)"
  elif ! git -C "$store" commit -q -m "$msg"; then
    echo "  commit failed in the store — nothing committed here either"
    exit 1
  else
    echo "  staged $sn file(s), $(git -C "$store" log --oneline -1)"
  fi
  # Pushed BEFORE this repository's commit is even made, for the same reason
  # the project's own pull comes after its commit: a rebase wants local commits
  # to replay. A failure here is loud but not fatal — the notes are committed
  # and safe, and stopping the whole rite would leave the session half closed
  # for a network problem.
  if [[ $sync -eq 1 ]]; then
    if git -C "$store" pull --rebase --quiet && { [[ $push -eq 0 ]] || git -C "$store" push --quiet; }; then
      [[ $push -eq 1 ]] && echo "  pushed" || echo "  --no-push: memory commit stays local"
    else
      store_unpushed=1
      echo "  ! sync failed — the memory is committed in $store but NOT pushed."
      echo "    The next machine will not see these notes: git -C $store push"
    fi
  fi
fi

if [[ ${#proj_files[@]} -eq 0 ]]; then
  hr "this repository"
  echo "  nothing outside the memory was written — no commit here"
  hr "lock"
  bash "$here/wrap-lock.sh" release | sed 's/^/  /'
  [[ $store_unpushed -eq 1 ]] && { printf '\nsession closed, but the memory store is NOT pushed.\n'; exit 1; }
  printf '\nsession closed. Memory is committed and pushed in %s.\n' "$store"
  exit 0
fi
set -- "${proj_files[@]}"
files=("$@")

# ---------- stage ----------
# Enumerated, never a directory, and never `git add -A`: this tree holds nested
# repositories and other people's working copies.
hr "stage"
to_add=()
for f in "${files[@]}"; do
  needs_staging "" "$f" && to_add+=("$f")
done
if [[ ${#to_add[@]} -gt 0 ]]; then
  git add -- "${to_add[@]}" || { echo "  git add failed"; exit 1; }
fi
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
if [[ $sync -eq 0 ]]; then
  echo "  commit_push=never in .floppy/config: no remote configured, staying local."
  exit 0
fi
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

if [[ $store_unpushed -eq 1 ]]; then
  printf '\nthis repository is closed, but the memory store is NOT pushed: git -C %s push\n' "$store"
  exit 1
fi
printf '\nsession closed. Memory, slice and procedure are committed and pushed.\n'
