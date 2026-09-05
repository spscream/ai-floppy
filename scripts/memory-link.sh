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
#   bash .floppy/run link                wire it up (idempotent)
#   bash .floppy/run link --check        report only, change nothing
#
# --check exists so that a status report can ask the question without being
# able to answer it. This is the one wiring step whose absence is silent: an
# unwired checkout does not fail, it writes the session's memory into a second
# copy under ~/.claude and nobody is told. The encoding of the path is computed
# in exactly one place — here — so a checker must call this script rather than
# repeat the rule and drift from it.
set -uo pipefail
cd "${FLOPPY_REPO:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"

check_only=0
[[ "${1:-}" == "--check" ]] && check_only=1

repo="$(pwd)"
mem_dir="${FLOPPY_MEMORY_DIR:-.agent-memory}"
mem="$repo/$mem_dir"
# `_` belongs in this set as much as `/` and `.` do. Claude Code folds all
# three into `-`, and this encoded only the first two — so a checkout whose
# name carries an underscore got a project directory of its own that the
# harness never opens. Nothing failed: the script created what it computed and
# reported success, `--check` agreed with it because it asks this same line,
# and the session's memory went to a second copy. That is the exact failure
# this file's header describes as its second silent mode, and it was live.
#
# Measured 2026-09-05 from the harness's own transcripts, which record the cwd
# a session actually ran in:
#
#   -home-amalaev-work-agents-harness   cwd=/home/amalaev/work/agents_harness
#   -home-amalaev-work-ai-floppy        cwd=/home/amalaev/work/ai_floppy
#   -home-amalaev--local-bin            cwd=/home/amalaev/.local/bin
#
# Two of that machine's three consumers were unwired this way, one across
# fifteen sessions. Case is NOT folded — `/tmp/consensus-5Ob9Z2` keeps its
# capitals in the harness's directory name — so this stays a `tr` of three
# characters and not a general slug.
enc="$(printf '%s' "$repo" | tr '/._' '---')"
proj="$HOME/.claude/projects/$enc"
link="$proj/memory"

# The repository itself is already the shim's own first line (see
# shim/run:name_repo) — not repeated here, so the two "which repo" lines a
# reader sees are one shape, not two.
if [[ $check_only -eq 0 ]]; then
  echo "project directory: $proj"
  echo "(this wires Claude Code's per-project memory only — Cursor has no equivalent to wire)"
  echo
fi

[[ -d "$mem" ]] || { echo "x no $mem — wrong repository"; exit 2; }

# In --check mode every branch below reports and stops; nothing is created.
if [[ $check_only -eq 1 ]]; then
  if [[ -L "$link" ]] && [[ "$(readlink -f "$link")" == "$mem" ]]; then
    echo "ok memory link: $link -> $mem_dir"
    exit 0
  elif [[ -L "$link" ]]; then
    echo "x memory link points elsewhere: $link -> $(readlink -f "$link")"
    exit 1
  elif [[ -e "$link" ]]; then
    echo "x a real directory sits where the memory symlink belongs ($link) — forked memory, sort it out by hand"
    exit 1
  else
    echo "x memory is not wired on this machine — run: bash .floppy/run link"
    exit 1
  fi
fi

# ---------- already configured? ----------
if [[ -L "$link" ]]; then
  cur="$(readlink -f "$link")"
  if [[ "$cur" == "$mem" ]]; then
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
  ln -s "$mem" "$link"
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
