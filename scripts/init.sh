#!/usr/bin/env bash
# Lay the floppy memory out in a fresh (or already-partly-set-up) repository.
#
#   bash scripts/init.sh --repo <path> --memory-dir <dir> --language <lang>
#
# What it creates in the target repository:
#   .floppy/run              copied from this checkout — the ONLY file copied
#   .floppy/config            flat key=value, memory_dir/memory_language set
#   <memory_dir>/MEMORY.md    the empty router, so `lint` is green immediately
#   .gitignore                gains "/<memory_dir>/local" (no trailing slash:
#                              that path is a symlink, and a slash-terminated
#                              rule matches directories only, so the symlink
#                              would not be ignored and would get committed)
#   AGENTS.md                 gains a section naming .floppy/ and pointing at
#                              floppy:agent-memory
#
# What it deliberately does NOT create: <memory_dir>/quota.lock. On an empty
# corpus there is nothing to measure, and a ceiling copied from another
# project is that project's ceiling, which is the same as no ceiling at all.
# `memory-lint.sh` warns about the missing ratchet rather than failing.
#
# Idempotent: every step here checks whether it is already done before doing
# it, so a second run with the same flags changes nothing — not one touched
# file, not one appended duplicate line.
#
# bash 3.2 (macOS) target: no mapfile, no declare -A, arguments parsed
# through $#, not "$@" (that expands to an unbound-variable error under
# `set -u` with zero positional parameters on 3.2). Zero dependencies beyond
# sed/awk/grep/git.
set -uo pipefail

usage() {
  echo "usage: bash scripts/init.sh --repo <path> [--memory-dir <dir>] [--language <lang>]" >&2
}

repo_arg=""
mem_dir=".agent-memory"
language="en"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo)        repo_arg="${2:-}"; shift 2 ;;
    --memory-dir)  mem_dir="${2:-}";  shift 2 ;;
    --language)    language="${2:-}"; shift 2 ;;
    -h|--help)     usage; exit 0 ;;
    *) echo "x unknown argument: $1" >&2; usage; exit 2 ;;
  esac
done

if [[ -z "$repo_arg" ]]; then
  echo "x --repo is required" >&2
  usage
  exit 2
fi
[[ -d "$repo_arg" ]] || { echo "x no such directory: $repo_arg" >&2; exit 2; }
[[ -n "$mem_dir" ]] || { echo "x --memory-dir must not be empty" >&2; exit 2; }
[[ -n "$language" ]] || { echo "x --language must not be empty" >&2; exit 2; }

repo="$(cd "$repo_arg" && pwd)"

# Where this script itself lives, i.e. the plugin checkout — one level above
# scripts/. This is how the shim source is found: whoever calls this script
# (the init skill, or a test with AI_FLOPPY_HOME) passes a $0 that already
# points at the right checkout, so no further search is needed here.
self_dir="$(cd "$(dirname "$0")" && pwd)"
plugin_root="$(cd "$self_dir/.." && pwd)"
shim_src="$plugin_root/shim/run"
[[ -f "$shim_src" ]] || { echo "x no shim at $shim_src — is this run from a floppy checkout?" >&2; exit 2; }

echo "repository:  $repo"
echo "memory_dir:  $mem_dir"
echo "language:    $language"
echo

# ---------- .floppy/run ----------
# The one file this plugin copies. Always refreshed from the plugin's own
# copy: it's meant to track the plugin, and an unchanged source produces an
# unchanged file, which is what idempotence actually requires.
mkdir -p "$repo/.floppy"
cp "$shim_src" "$repo/.floppy/run"
chmod +x "$repo/.floppy/run"
echo "ok .floppy/run"

# ---------- .floppy/config ----------
cfg="$repo/.floppy/config"
if [[ -f "$cfg" ]]; then
  echo "ok .floppy/config already exists, left untouched"
else
  cat > "$cfg" <<EOF
# floppy config — flat key=value, one per line. See floppy:agent-memory for
# what each key governs.
memory_dir=$mem_dir
memory_language=$language

# workplace_repo and workplace_project_key have no default on purpose: a
# fresh project must not silently write into somebody else's private memory.
# Set both to use "bash .floppy/run workplace".
# workplace_repo=git@example.com:workplace/agents-memory.git
# workplace_project_key=your-project-key

# statuses_now=docs/statuses/NOW.md
# statuses_now_chars_max=12000
# watched_dirs=docs
# watched_files=AGENTS.md
EOF
  echo "ok .floppy/config"
fi

# ---------- memory skeleton ----------
mem="$repo/$mem_dir"
mkdir -p "$mem"
idx="$mem/MEMORY.md"
if [[ -f "$idx" ]]; then
  echo "ok $mem_dir/MEMORY.md already exists, left untouched"
else
  cat > "$idx" <<EOF
# Memory index

Router for this repository's durable memory — loaded at the start of every
session, so it stays small on purpose. See \`floppy:agent-memory\` for what a
note, an index, and \`metadata.evidence\` mean.

This index is empty. Add one pointer line per note as they are written.
EOF
  echo "ok $mem_dir/MEMORY.md"
fi
# quota.lock is deliberately never created here — see the header comment.

# ---------- .gitignore ----------
gi="$repo/.gitignore"
# No trailing slash: this path becomes a symlink once memory-link/workplace
# wire it up, and a slash-terminated gitignore rule matches directories only
# — it would not match the symlink, which would then get committed.
ignore_line="/$mem_dir/local"
touch "$gi"
if grep -qxF "$ignore_line" "$gi"; then
  echo "ok .gitignore already has $ignore_line"
else
  # Ensure a trailing newline before appending, so the new block does not
  # land glued onto whatever the last existing line was.
  if [[ -s "$gi" ]] && [[ "$(tail -c1 "$gi")" != "" ]]; then
    printf '\n' >> "$gi"
  fi
  printf '\n# floppy: machine-bound memory scope, never committed (see floppy:agent-memory)\n%s\n' \
    "$ignore_line" >> "$gi"
  echo "ok .gitignore: $ignore_line"
fi

# ---------- AGENTS.md section ----------
agents="$repo/AGENTS.md"
marker="<!-- floppy:agents-section -->"
touch "$agents"
if grep -qF "$marker" "$agents"; then
  echo "ok AGENTS.md already has the floppy section, left untouched"
else
  if [[ -s "$agents" ]] && [[ "$(tail -c1 "$agents")" != "" ]]; then
    printf '\n' >> "$agents"
  fi
  cat >> "$agents" <<EOF

$marker
## Agent memory

This repository uses the \`floppy\` plugin for its session ritual and its
durable memory. The entry point is \`.floppy/run\` — see \`floppy:agent-memory\`
for what a note looks like and how the memory is laid out, and
\`floppy:start\` / \`floppy:workstatus\` / \`floppy:wrap\` for the three rites
built on top of it. Settings live in \`.floppy/config\`; the memory itself is
under \`$mem_dir\`.
EOF
  echo "ok AGENTS.md: floppy section added"
fi

echo
echo "done"
