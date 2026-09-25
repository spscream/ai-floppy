#!/usr/bin/env bash
# Attach .agent-memory to the Claude Code memory directory ON THIS MACHINE.
#
# This script is Claude-Code-only, and says so: it wires a path under
# ~/.claude/projects specifically, and does nothing for any other harness
# this plugin ships to — Cursor, named in .cursor-plugin/plugin.json, reads
# skills straight out of the repository and has no equivalent per-project
# memory directory of its own to wire. Run it under Cursor and it still
# succeeds (it only ever touches ~/.claude), but succeeding is not the same
# as doing something useful there — the memory is exactly as visible to a
# Cursor session with or without this having run.
#
# Why a script, for the harness it does apply to: the memory directory path
# is encoded from the checkout location, so it differs on every machine. As
# prose it had two silent failure modes. First: the incantation runs in the
# wrong directory — the agent does not see the memory and starts a second
# copy, without a word. Second: the project directory is computed correctly,
# but Claude Code encodes the path differently — same result.
#
# The script is idempotent: a second run on a configured machine changes nothing.
# Output is English on purpose: the tool is reusable, the memory is not.
#
#   bash <plugin>/scripts/run link                wire it up (idempotent)
#   bash <plugin>/scripts/run link --check        report only, change nothing
#
# --check exists so that a status report can ask the question without being
# able to answer it. This is the one wiring step whose absence is silent: an
# unwired checkout does not fail, it writes the session's memory into a second
# copy under ~/.claude and nobody is told. The encoding of the path is computed
# in exactly one place — here — so a checker must call this script rather than
# repeat the rule and drift from it.
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

check_only=0
[[ "${1:-}" == "--check" ]] && check_only=1

repo="$(pwd)"
mem_dir="${FLOPPY_MEMORY_DIR:-.agent-memory}"
# The RESOLVED memory, not a path in the working tree. Since 0.27.0 a
# store-hosted memory is addressed by repository and lives in the cache, with
# nothing at all standing at $mem_dir here — so composing the target out of the
# tree would wire the harness to a path that does not exist, in exactly the
# working copies (worktrees) that need this verb most.
mem="${FLOPPY_MEMORY_REAL:-$repo/$mem_dir}"
# The encoding of the harness's project directory moved to lib-wiring.sh in
# 0.27.0, unchanged, because the config parser needs it too — it makes this
# pointer appear without anybody running this verb. It is still defined once;
# this file is now a reader of that definition rather than its home.
_lib="$(dirname "$0")/lib-wiring.sh"
[[ -f "$_lib" ]] || _lib="${FLOPPY_ROOT:-}/scripts/lib-wiring.sh"
. "$_lib"
# And the checked `ln`, shared with the two store verbs.
_libc="$(dirname "$0")/lib-checkout.sh"
[[ -f "$_libc" ]] || _libc="${FLOPPY_ROOT:-}/scripts/lib-checkout.sh"
. "$_libc"
proj="$(harness_project_dir "$repo")"
link="$proj/memory"

# The repository itself is already the shim's own first line (see
# shim/run:name_repo) — not repeated here, so the two "which repo" lines a
# reader sees are one shape, not two.
if [[ $check_only -eq 0 ]]; then
  echo "project directory: $proj"
  echo "(this wires Claude Code's per-project memory only — Cursor has no equivalent to wire)"
  echo
fi

# "wrong repository" is what a git worktree of the RIGHT repository used to be
# told here, and it was wrong on the facts, not merely blunt: the repository
# was correct and the memory simply had no copy on this machine, or none this
# working copy could see. Measured 2026-09-25 in a worktree of this plugin's
# own repository, which printed `x no <wt>/.agent-memory — wrong repository`
# and exited 2. The refusal now names what is actually missing and the verb
# that produces it.
if [[ ! -d "$mem" ]]; then
  echo "x no memory at $mem — there is nothing on this machine to point the harness at"
  if [[ -n "${FLOPPY_MEMORY_REPO:-}" ]]; then
    echo "  This project keeps its memory in a store, addressed by repository rather than"
    echo "  by working copy. Run the store verb first: it clones the store and lays out"
    echo "  the cache this path names. Then run this verb again."
  else
    echo "  Either this repository has no floppy memory laid out yet (init does that),"
    echo "  or $mem_dir was removed. Nothing was created here: this verb only wires."
  fi
  exit 2
fi

# Both sides of every comparison below are resolved, not one of them.
#
# With `store`, memory_dir is ITSELF a symlink into another repository, so
# `readlink -f` of the harness link — fully resolved, ending in the store
# checkout — could never equal the literal $mem. The whole external layout
# therefore had a `link` that refused the machine it had just wired, a
# `--check` that never went green, and a `status` reporting "not wired" against
# working wiring. Measured 2026-09-05 while standing the layout up.
#
# `cd && pwd -P` rather than `readlink -f` for the directory case: it is what
# the rest of these scripts use, and it does not depend on a `readlink` that
# only got -f in recent macOS. The fallback covers a dangling link, which has
# no directory to cd into and still has to be reported rather than crash.
resolve() {
  if [[ -d "$1" ]]; then (cd "$1" && pwd -P)
  else readlink -f "$1" 2>/dev/null || printf '%s\n' "$1"
  fi
}
mem_real="$(resolve "$mem")"

# In --check mode every branch below reports and stops; nothing is created.
if [[ $check_only -eq 1 ]]; then
  if [[ -L "$link" ]] && [[ "$(resolve "$link")" == "$mem_real" ]]; then
    echo "ok memory link: $link -> $mem_dir"
    exit 0
  elif [[ -L "$link" ]]; then
    echo "x memory link points elsewhere: $link -> $(resolve "$link")"
    exit 1
  elif [[ -e "$link" ]]; then
    echo "x a real directory sits where the memory symlink belongs ($link) — forked memory, sort it out by hand"
    exit 1
  else
    echo "x memory is not wired on this machine — run: $floppy_run link"
    exit 1
  fi
fi

# ---------- already configured? ----------
if [[ -L "$link" ]]; then
  cur="$(resolve "$link")"
  if [[ "$cur" == "$mem_real" ]]; then
    echo "ok already configured: $link -> $mem"
  else
    echo "x the symlink points elsewhere: $link -> $cur"
    echo "  expected $mem. Sort this out by hand: it may be another checkout's memory."
    exit 1
  fi
elif [[ -e "$link" ]]; then
  # A real directory in the symlink's place means the memory already forked.
  n="$(find "$link" -name '*.md' 2>/dev/null | wc -l)"
  echo "x a real directory sits where the symlink belongs. Memory files in it: $n."
  echo "  This is a second copy: something wrote it while the symlink was absent."
  echo "  Move what you need into $mem by hand, delete $link, then run this again."
  echo "  Nothing is deleted here: those may be the only copies of some facts."
  exit 1
else
  mkdir -p "$proj"
  link_or_fail "$mem" "$link" || exit 1
  echo "ok symlink created: $link -> $mem"
fi

# ---------- does a write really land? ----------
probe="$link/.link-probe"
if printf 'probe\n' > "$probe" 2>/dev/null && [[ -f "$mem/.link-probe" ]]; then
  rm -f "$mem/.link-probe"
  echo "ok a write through the symlink reaches the repository"
else
  rm -f "$probe" 2>/dev/null
  echo "x a write through the symlink does not reach $mem — the symlink is broken"
  exit 1
fi

# ---------- is this the right path encoding? ----------
# If Claude Code has worked in this directory, session transcripts sit next to
# the memory. Their absence means either no agent ran here yet, or the path
# encoding changed and the agent writes somewhere else. The second is a silent
# failure.
sessions="$(find "$proj" -maxdepth 1 -name '*.jsonl' 2>/dev/null | wc -l)"
if [[ "$sessions" -gt 0 ]]; then
  echo "ok path encoding confirmed: $sessions session transcripts alongside"
else
  echo
  echo "! no session transcript in the project directory."
  echo "  Either no Claude Code session ran in this checkout yet — then all is well,"
  echo "  check again after the first one. Or the encoding differs and the agent"
  echo "  writes past this directory. Verify by eye:"
  echo "      ls ~/.claude/projects | grep -i \"$(basename "$repo")\""
fi
