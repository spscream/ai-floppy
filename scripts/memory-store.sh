#!/usr/bin/env bash
# Put this machine's copy of this project's memory in place, for the layout
# where the code repository cannot hold agent notes at all.
#
# Not the same thing as `workplace`, though the machinery rhymes. That one
# attaches the PRIVATE scope — facts true across a workplace's machines — as a
# leaf inside the memory. This one lays out the memory itself: the clone of the
# store under <agents_memory_dir>/.clones/, and the view
# <agents_memory_dir>/<key>/shared into this project's scope in it.
#
# SINCE 0.27.0 IT PUTS NOTHING IN THE CODE REPOSITORY. <memory_dir> is the name
# a person types and every report prints, and it resolves to that view; no file
# or symlink of that name is created in a working copy at all. The reason is
# `git worktree`: a symlink there is gitignored by design, git never carries it
# into a worktree, so a worktree of a correctly wired repository arrived with no
# memory and every verb in it said the project had none. The address is computed
# from `project_key`, which git does carry.
#
# So this runs ONCE PER MACHINE, not once per working copy, and a worktree needs
# no step of its own. Skipping it is silent in a specific way: every path
# resolves, `lint` and `check` are quiet because there is nothing there to be
# loud about, and the session reads an empty memory. `wrap-guard` catches that
# state and names this verb; `--check` answers the same question in one line.
#
# Idempotent: a second run on a wired machine changes nothing. It never deletes
# a symlink or a real directory left at <memory_dir> by an earlier release —
# that is memory somebody wrote, and a human decides what happens to it. This
# script does not decide the fate of memory.
#
#   bash <plugin>/scripts/run store            lay the memory out on this machine
#   bash <plugin>/scripts/run store --check    report only, change nothing
#   bash <plugin>/scripts/run store --migrate  move notes stranded in the working
#                                              tree into the store, printing every
#                                              one before it moves any
#
# Requires public_repo and memory_project_key in .floppy/config. Neither has a
# default: a repository that never opted in must not silently write into
# somebody else's store.
set -uo pipefail

# How a hint spells a floppy command. The consumer's repository holds no runner
# of its own since 0.26.0, so a message names this plugin's dispatcher by its
# absolute path — pasteable from wherever the reader is standing. scripts/run
# exports FLOPPY_RUN; a direct call (the tests make them) derives the same
# value from this script's own location.
unset CDPATH   # see scripts/run: it would print into the substitutions below
floppy_run="${FLOPPY_RUN:-}"
# Quoted unconditionally, where scripts/run quotes only a path that needs it:
# this branch is reached only by a direct call, and there quotes are cheaper
# than the broken command an unquoted path with a space in it produces.
[[ -n "$floppy_run" ]] || floppy_run="bash \"$(cd "$(dirname "$0")" && pwd)/run\""
cd "${FLOPPY_REPO:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
repo="$(pwd)"

check_only=0
migrate=0
for a in "$@"; do
  case "$a" in
    --check)   check_only=1 ;;
    --migrate) migrate=1 ;;
    *) echo "x unknown argument: $a"; exit 2 ;;
  esac
done
if [[ $check_only -eq 1 && $migrate -eq 1 ]]; then
  echo "x --check and --migrate are opposites: one reports, the other moves files"
  exit 2
fi

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

# ---------- migration, which is a person's decision and nobody else's ----------
# The one operation in this file that MOVES memory, and the only way to reach it
# is to type the flag. No verb calls it, no rite calls it, `init` does not call
# it: a corpus being relocated is a thing its owner should be watching happen.
#
# It exists because 0.27.0 changes where the memory is, and a machine wired
# before it may hold notes at <repo>/<memory_dir> as a real directory — written
# there while the symlink was missing, or by an agent following a skill. Those
# notes are now invisible: every reader resolves the memory to the cache, and
# nothing looks in the working tree. Telling people to move them by hand is
# fine advice and is what the refusal below prints; this is the same act done
# once, correctly, with every file named as it goes.
#
# Three rules, and the first two are why this is safe to run:
#   - it PRINTS EVERY FILE before moving any of them, source and destination;
#   - a destination that already exists stops the whole thing, with nothing
#     moved — two notes of the same name are two notes, and which one wins is
#     not a question a script may answer;
#   - it deletes nothing, not even the directory it empties. Removing something
#     that carries the memory's name stays the human's act, here as everywhere
#     else in this file.
if [[ $migrate -eq 1 ]]; then
  if [[ ! -d "$view" ]]; then
    echo "x no memory on this machine yet: $view does not exist"
    echo "  Run this verb with no arguments first — there is nowhere to move anything to."
    exit 1
  fi
  if [[ -L "$link" ]]; then
    echo "ok $mem_dir is a symlink, not a directory of notes: it already resolves into"
    echo "   the store and there is nothing to move. Removing the link is yours to do."
    exit 0
  fi
  if [[ ! -d "$link" ]]; then
    echo "ok nothing at $mem_dir in this working copy: nothing to migrate"
    exit 0
  fi

  # THE PRIVATE SCOPE IS NOT THIS VERB'S TO MOVE, and getting that wrong was a
  # leak, not an inconvenience. `$view` is the PUBLIC store's scope; a real
  # `<memory_dir>/<private>/` directory in a working copy holds notes that were
  # written for the private repository. A walk that does not look at scope moved
  # them into `public/projects/<key>/private/` of the public clone, where the
  # very next `commit` would have pushed them to a public remote, with no line
  # of output saying a private scope had just become public. Measured
  # 2026-09-25 in review, on a fixture, before this refusal existed.
  #
  # The same holds for `common/`: its two namespaces live in two different
  # repositories, and which one a stranded file belonged to is not recoverable
  # from its path in a working copy.
  #
  # Refused rather than skipped. Moving the public half and silently leaving the
  # private half is a half-migrated corpus, which is the state this plugin
  # refuses everywhere else, and the person would be told "ok" over it.
  priv="${FLOPPY_MEMORY_PRIVATE_DIR:-${FLOPPY_MEMORY_LOCAL_DIR:-private}}"
  reserved=0
  for scope_dir in "$priv" common; do
    if [[ -d "$link/$scope_dir" && ! -L "$link/$scope_dir" ]]; then
      echo "x $mem_dir/$scope_dir is a real directory here, and this verb moves into the PUBLIC store only"
      reserved=$((reserved+1))
    fi
  done
  if [[ "$reserved" -gt 0 ]]; then
    echo
    echo "  Nothing was moved. Those notes were written for another repository, and"
    echo "  this verb's destination is $target — moving them there would publish them."
    echo "  Move that scope by hand, to the repository it belongs to, and run this again."
    exit 1
  fi

  # Relative paths, so the layout under the memory directory is carried across
  # unchanged: a note in half/ lands in half/. NUL-separated, and read through a
  # process substitution rather than a heredoc: `$(find …)` in a heredoc is one
  # empty line when nothing matches, so the loop ran once with an empty name and
  # reported a collision against `$view/` itself — measured 2026-09-25 in review,
  # on a directory holding no ordinary files, which is exactly the state a
  # finished migration leaves behind. A newline in a filename broke the same
  # loop in two. `find`, not a glob, because the scopes nest and bash 3.2 has no
  # globstar; `-type f` and no `-L`, so a symlinked scope is not descended into.
  n=0; clash=0
  while IFS= read -r -d '' f; do
    rel="${f#"$link"/}"
    [[ -e "$view/$rel" ]] && { echo "x already in the store: $rel"; clash=$((clash+1)); }
    n=$((n+1))
  done < <(find "$link" -type f -print0 2>/dev/null)

  if [[ "$n" -eq 0 ]]; then
    echo "ok $mem_dir holds no files: nothing to migrate"
    echo "   The empty directory is yours to remove: rm -r $mem_dir"
    exit 0
  fi
  if [[ "$clash" -gt 0 ]]; then
    echo
    echo "x $clash of $n file(s) already exist in the store under the same name."
    echo "  Nothing was moved. Compare them yourself and rename or delete one side;"
    echo "  a script cannot know which copy is the one you meant to keep."
    exit 1
  fi

  echo "-- moving $n file(s) from $mem_dir into the store"
  moved=0
  while IFS= read -r -d '' f; do
    rel="${f#"$link"/}"
    mkdir -p "$view/$(dirname "$rel")" 2>/dev/null
    if mv "$f" "$view/$rel"; then
      echo "  moved $mem_dir/$rel -> $view/$rel"
      moved=$((moved+1))
    else
      echo "  x FAILED to move $mem_dir/$rel — the reason is on the line above"
      echo "    $moved file(s) were already moved. Nothing is deleted; run this again"
      echo "    once the cause is fixed and it will carry on with what is left."
      exit 1
    fi
  done < <(find "$link" -type f -print0 2>/dev/null)

  echo
  echo "ok $moved file(s) are now in the store and will be committed from there."
  echo "   $mem_dir still stands in this working copy, now empty of files. Nothing"
  echo "   reads it and nothing writes to it; removing it is yours to do:"
  echo "     rm -r $mem_dir"
  echo "   The moved notes are ordinary memory now — the next check verb sees them"
  echo "   under $mem_dir/ as it sees every other note."
  exit 0
fi

# ---------- report ----------
# Asked of the CACHE, not of the working tree. Until 0.27.0 this verb's answer
# was "is there a symlink at <repo>/<memory_dir>", and a git worktree never has
# one — git carries tracked files and the symlink is gitignored by design — so
# every worktree of a correctly wired repository was told `x .agent-memory does
# not exist — not wired on this machine` while the memory sat on that machine,
# complete. Measured 2026-09-25. The memory is addressed by repository now, and
# the question is whether THIS MACHINE holds it.
if [[ $check_only -eq 1 ]]; then
  if [[ -d "$view" ]]; then
    # WHERE IT ACTUALLY GOES, read off the disk, not recomposed from the config
    # that was just read. A report whose right-hand side is computed from the
    # same three keys as its left cannot disagree with anything, so it cannot
    # find anything either — and the assertion that read it passed no matter
    # what the view pointed at. Measured 2026-09-25 in review: with the view
    # repointed at an unrelated directory by hand, this line still named the
    # store clone and exited 0.
    actual="$(cd "$view" && pwd -P)"
    if [[ "$actual" == "$(cd "$target" 2>/dev/null && pwd -P)" ]]; then
      echo "ok memory on this machine: $view -> $actual"
    else
      echo "x $view does not lead to this project's scope in the store"
      echo "    it leads to:  $actual"
      echo "    expected:     $target"
      echo "  It may belong to another store. Nothing was changed; sort it out by hand."
      exit 1
    fi
  elif [[ -e "$view" || -L "$view" ]]; then
    echo "x $view exists but does not resolve to a directory — the store may be half-cloned"
    exit 1
  else
    echo "x no memory on this machine yet: $view does not exist — run this verb without --check"
    exit 1
  fi
  # Wiring left in the working tree by a pre-0.27.0 run of this verb. It still
  # works — everything below follows it — but it is no longer made, and it is
  # what a worktree cannot have. Reported, never removed: it is a symlink this
  # verb created, but removing anything under the memory's name is the one act
  # this script does not perform. The ignore line matters only while it is
  # there, so both are asked together.
  if [[ -e "$link" || -L "$link" ]]; then
    echo "note $mem_dir still stands in this working copy — left by an earlier release,"
    echo "     harmless, and no longer created. Removing it is yours to do."
    git check-ignore -q -- "$mem_dir" 2>/dev/null \
      && echo "ok   and this repository ignores it" \
      || { echo "x    and this repository does NOT ignore it: git here can still stage the memory"; exit 1; }
  fi
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

# ---------- nothing goes into the working tree ----------
# Until 0.27.0 this is where <repo>/<memory_dir> was made a symlink into the
# view, and that symlink was the whole reason a git worktree had no memory: git
# carries tracked files, the symlink is gitignored by design, so a worktree
# inherited nothing and every verb that reads memory refused there. The memory
# is addressed by repository now (see lib-config.sh), and no working copy needs
# a representation of it.
#
# The ignore line stays, and stays unconditional. Nothing this plugin runs
# creates the path any more, but the skills still name `.agent-memory/<file>`
# as the place to write a note, and an agent following them makes a real
# directory here. Ignored, that is a fork of the memory and wrap-guard names it;
# un-ignored, it is a memory this repository can COMMIT, which is the one thing
# the store layout exists to prevent. One line of insurance against a path we
# no longer control. No trailing slash — with one, git does not match a symlink.
if git check-ignore -q -- "$mem_dir" 2>/dev/null; then
  :
else
  printf '\n# memory lives in the store repository, not here\n/%s\n' "$mem_dir" >> "$repo/.gitignore"
  echo "ok added /$mem_dir to .gitignore, because this repository could otherwise stage it (commit it)"
fi

# What already stands in the working copy is two different situations.
#
# A SYMLINK is this verb's own work from an earlier release. It still resolves,
# everything still follows it, and removing anything that carries the memory's
# name is not this script's act — the same rule that refuses to delete a real
# directory of notes covers a link this verb made. Reported and left alone.
#
# A REAL DIRECTORY is somebody's notes, and under this layout nothing reads them
# any more: they are a fork of the memory, invisible to every other checkout of
# this repository. That is the migration case, and it stops the verb. Not
# because it blocks anything — nothing needs the path now — but because moving
# memory is a human's decision and a silent "ok" over notes nobody will ever
# read again is how a corpus gets lost. The files are counted and named; nothing
# is moved.
if [[ -L "$link" ]]; then
  echo "note $mem_dir is a symlink left by an earlier release. Harmless and no longer"
  echo "     made: the memory is found through the cache above, not through this tree."
  echo "     Removing it is yours to do; nothing here touches it."
elif [[ -e "$link" ]]; then
  n="$(find "$link" -name '*.md' 2>/dev/null | wc -l | tr -d ' ')"
  echo "x a real $mem_dir directory stands in this working copy, with $n memory file(s) in it."
  echo "  Nothing reads it any more: this project's memory is $target, reached"
  echo "  through $view. Those notes may be the only copies — move what you want"
  echo "  into the store yourself, then remove the directory and run this again."
  echo "  Nothing was moved or deleted: this script does not decide the fate of memory."
  exit 1
fi

# ---------- the cross-project scope ----------
# public/common, the subject-level sibling of public/projects/<key>: facts
# about no single project that the team may read. Wired here rather than by a
# verb of its own — see link_common_scope for why.
#
# AFTER the ignore line above, not before, and the order is load-bearing: the
# container it creates sits under a memory directory this repository has just
# been told to ignore whole, and it asks git whether that is so. Run first, it
# gets "no" and writes a second rule for a path already covered — measured
# 2026-09-08, in this plugin's own checkout, twice over.
#
# It is not fatal on its own. A store that wires but whose common scope refuses
# (a real directory in the way, a link to somewhere else) has still moved this
# project's memory, and saying so beats undoing it.
# Through the VIEW, not through the working tree: the view is the stable
# address of this project's memory and survives the store moving to another
# URL, and since 0.27.0 it is the only address there is.
link_common_scope "$dir" public shared "$view" || common_failed=1

# ---------- does a write reach the store? ----------
# The step that actually proves the wiring. Everything above can look right
# while a write lands somewhere else. Written through the view, which is what
# every reader now resolves the memory to.
probe="$view/.write-probe-$$"
if echo "probe" > "$probe" 2>/dev/null && [[ -f "$target/.write-probe-$$" ]]; then
  rm -f "$probe"
  echo "ok a write through the view lands in the store"
else
  rm -f "$probe"
  echo "x a write through $view does not reach $target"
  exit 1
fi

# ---------- what is not pushed ----------
ahead="$(git -C "$dir" rev-list --count '@{u}..HEAD' 2>/dev/null || echo '?')"
dirty="$(git -C "$dir" status --porcelain | wc -l | tr -d ' ')"
[[ "$dirty" != "0" ]] && echo "! $dirty uncommitted change(s) in $dir — $floppy_run commit closes them"
[[ "$ahead" != "0" && "$ahead" != "?" ]] && echo "! $ahead commit(s) not pushed in $dir — the next machine cannot see them"
echo
# `link` used to be named here as the next step a human takes, "per machine and
# per worktree". It is still per working directory — the harness addresses its
# own project directory by cwd, which this plugin does not choose — but it is
# no longer anybody's step: the config parser makes that pointer on any verb,
# once, and says so. What is left to name is the scope this verb does not wire.
if [[ -n "${FLOPPY_WORKPLACE_REPO:-}" ]]; then
  echo "next: $floppy_run workplace, for the private scope. The harness's own pointer"
  echo "      to this memory is made automatically, per working directory, on first use."
else
  echo "next: nothing. The harness's pointer to this memory is made automatically,"
  echo "      per working directory, on first use."
fi
# The project scope is wired and proven above; a common scope that refused is
# reported by its own message and carried out in the exit code, so a script
# calling this verb does not read "ok" over a half-wired memory.
exit "${common_failed:-0}"
