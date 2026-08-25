#!/usr/bin/env bash
# Wire this repository's memory to a store repository, for the layout where
# the code repository cannot hold agent notes at all.
#
# Not the same thing as `workplace`, though the machinery rhymes. That one
# attaches a SHARED scope (<memory_dir>/local) for facts true across a
# workplace's machines. This one moves THIS PROJECT's whole memory out: after
# it runs, <memory_dir> is a symlink into <store>/projects/<key>/memory and the
# code repository ignores it.
#
# Why a script rather than four commands in a document: those four commands are
# per machine and per worktree, and the failure of skipping them is silent in a
# very specific way. Add the ignore line, skip the symlink, and <memory_dir> is
# an ordinary ignored directory inside the code repository — notes are written
# and read normally, `git status` cannot show them because it was told not to,
# and nothing ever publishes them. (wrap-guard now catches exactly that state;
# this script is how you avoid reaching it.)
#
# Idempotent: a second run on a wired machine changes nothing. It never deletes
# a real directory standing where the symlink belongs — that is memory somebody
# wrote, and a human decides what happens to it.
#
#   bash .floppy/run store            wire it up (idempotent)
#   bash .floppy/run store --check    report only, change nothing
#
# Requires public_repo and memory_project_key in .floppy/config. Neither has a
# default: a repository that never opted in must not silently write into
# somebody else's store.
set -uo pipefail
cd "${FLOPPY_REPO:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
repo="$(pwd)"

check_only=0
for a in "$@"; do
  case "$a" in
    --check) check_only=1 ;;
    *) echo "x unknown argument: $a"; exit 2 ;;
  esac
done

mem_dir="${FLOPPY_MEMORY_DIR:-.agent-memory}"
url="${FLOPPY_MEMORY_REPO:-}"
key="${FLOPPY_MEMORY_PROJECT_KEY:-}"
dir="${FLOPPY_MEMORY_REPO_DIR:-$HOME/agents_memory}"

if [[ -z "$url" || -z "$key" ]]; then
  echo "x public_repo and project_key are both required in .floppy/config"
  echo "  This verb moves the memory out of the code repository; without a"
  echo "  destination and a scope there is nowhere to move it to."
  echo "  A project that keeps memory in its own repository does not need this verb."
  exit 2
fi

scope="public/projects/$key"
target="$dir/$scope"
view="${FLOPPY_AGENTS_MEMORY_DIR:-$HOME/agents_memory}/$key/shared"
link="$repo/$mem_dir"

echo "store:      $dir"
echo "scope:      $scope"
echo "view:       $view"
echo "memory_dir: $mem_dir"
echo

# ---------- report ----------
if [[ $check_only -eq 1 ]]; then
  if [[ -L "$link" ]]; then
    echo "ok $mem_dir -> $(readlink "$link")"
  elif [[ -e "$link" ]]; then
    echo "x $mem_dir is a real directory, not a symlink into the store"
    exit 1
  else
    echo "x $mem_dir does not exist — not wired on this machine"
    exit 1
  fi
  git check-ignore -q -- "$mem_dir" 2>/dev/null \
    && echo "ok $mem_dir is ignored by this repository" \
    || { echo "x $mem_dir is NOT ignored: this repository can still stage the memory"; exit 1; }
  exit 0
fi

# ---------- the store itself ----------
# Refusals, clone or pull, and the secret hook are shared with `workplace`:
# scripts/lib-checkout.sh. The origin check inside it is the one that stops a
# directory holding another repository from being adopted in silence.
_lib="$(dirname "$0")/lib-checkout.sh"
[[ -f "$_lib" ]] || _lib="${FLOPPY_ROOT:-}/scripts/lib-checkout.sh"
. "$_lib"
ensure_checkout "$url" "$dir" "store" || exit 1

# Before 0.5.0 this project's corpus was projects/<key>/memory, and the
# workplace scope was projects/<key> itself — so with one repository serving
# both, the second contained the first. Siblings end that, but the notes have
# to be moved by a human on one machine, once.
for old in "projects/$key/memory" "projects/$key/shared"; do
  [[ -e "$dir/$old" ]] || continue
  refuse_old_scope "$dir" "$old" "$scope" \
    "mkdir -p \"$dir/public/projects\"" \
    "git -C \"$dir\" mv \"$old\" \"$scope\""
  exit 1
done

mkdir -p "$target"
view_link "$key" "$dir" "$scope" shared || exit 1

# ---------- the symlink ----------
if [[ -L "$link" ]]; then
  if [[ -d "$link" ]]; then cur="$(cd "$link" && pwd -P)"; else cur="$(readlink "$link")"; fi
  old_scope="$(cd "$dir" && pwd -P)/projects/$key/shared"
  if [[ "$cur" == "$(cd "$target" && pwd -P)" ]]; then
    echo "ok already wired: $mem_dir -> $target"
  elif [[ "$cur" == "$old_scope" ]]; then
    # The same repointing as in memory-workplace.sh, for the same reason: this
    # is wiring left by an earlier version of this verb, not memory.
    rm -f "$link"
    ln -s "$view" "$link"
    echo "ok repointed $mem_dir from the pre-0.5.0 scope to $view"
  else
    echo "x $mem_dir points elsewhere: $cur"
    echo "  expected $target. Sort this out by hand — it may be another store."
    exit 1
  fi
elif [[ -e "$link" ]]; then
  n="$(find "$link" -name '*.md' 2>/dev/null | wc -l | tr -d ' ')"
  echo "x a real directory sits where the symlink belongs, with $n memory file(s) in it."
  echo "  Those notes may be the only copies. Move them into $target yourself,"
  echo "  check nothing is left, remove the directory, and run this again."
  echo "  Nothing was moved or deleted: this script does not decide the fate of memory."
  exit 1
else
  # Through the view, not straight into the clone: the view is the stable
  # address of this project's memory, and it survives the store moving to
  # another URL. The write probe below proves the whole chain either way, so
  # the extra hop is checked rather than trusted.
  ln -s "$view" "$link"
  echo "ok linked: $mem_dir -> $view"
fi

# ---------- the ignore line ----------
# No trailing slash: with one, git does not match a symlink, and the memory
# would be stageable here after all — the one thing this layout prevents.
if git check-ignore -q -- "$mem_dir" 2>/dev/null; then
  echo "ok $mem_dir is ignored by this repository"
else
  printf '\n# memory lives in the store repository, not here\n/%s\n' "$mem_dir" >> "$repo/.gitignore"
  echo "ok added /$mem_dir to .gitignore (commit it)"
fi

# ---------- does a write reach the store? ----------
# The step that actually proves the wiring. Everything above can look right
# while a write lands somewhere else.
probe="$link/.write-probe-$$"
if echo "probe" > "$probe" 2>/dev/null && [[ -f "$target/.write-probe-$$" ]]; then
  rm -f "$probe"
  echo "ok a write through the link lands in the store"
else
  rm -f "$probe"
  echo "x a write through the link does not reach $target"
  exit 1
fi

# ---------- what is not pushed ----------
ahead="$(git -C "$dir" rev-list --count '@{u}..HEAD' 2>/dev/null || echo '?')"
dirty="$(git -C "$dir" status --porcelain | wc -l | tr -d ' ')"
[[ "$dirty" != "0" ]] && echo "! $dirty uncommitted change(s) in $dir — bash .floppy/run commit closes them"
[[ "$ahead" != "0" && "$ahead" != "?" ]] && echo "! $ahead commit(s) not pushed in $dir — the next machine cannot see them"
echo
echo "next: bash .floppy/run link   (the harness's memory directory, per machine and per worktree)"
exit 0
