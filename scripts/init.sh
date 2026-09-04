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
#                              agent-memory
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
  echo "       [--memory-repo <git-url> --memory-key <scope>] [--memory-repo-dir <path>]" >&2
  echo "       [--agents-memory-dir <path>]" >&2
  echo "  --memory-repo/--memory-key host the memory in another repository, for a" >&2
  echo "  code repository that cannot hold agent notes. Both or neither." >&2
}

repo_arg=""
mem_dir=".agent-memory"
language="en"
public_repo=""
memory_key=""
memory_repo_dir=""
agents_memory_dir=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo)        repo_arg="${2:-}"; shift 2 ;;
    --memory-dir)  mem_dir="${2:-}";  shift 2 ;;
    --language)    language="${2:-}"; shift 2 ;;
    --memory-repo)     public_repo="${2:-}";     shift 2 ;;
    --memory-key)      memory_key="${2:-}";      shift 2 ;;
    --memory-repo-dir) memory_repo_dir="${2:-}"; shift 2 ;;
    --agents-memory-dir) agents_memory_dir="${2:-}"; shift 2 ;;
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
# Half of this pair is not a layout, it is a broken one: a URL with no scope
# has nowhere to write, and a scope with no URL has nothing to write into.
if [[ -n "$public_repo" && -z "$memory_key" ]] || [[ -z "$public_repo" && -n "$memory_key" ]]; then
  echo "x --memory-repo and --memory-key go together: a store without a scope has nowhere to put this project's notes" >&2
  exit 2
fi

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
# Written into the generated config only when asked for, and commented out
# otherwise: a project pointed at a store it never chose would write this
# project's notes into somebody else's repository.
if [[ -n "$public_repo" ]]; then
  store_cfg="
# This repository does not hold its own memory: memory_dir is a symlink into
# the store below. Wire it on each machine with \"bash .floppy/run store\".
public_repo=$public_repo
memory_project_key=$memory_key"
  [[ -n "$memory_repo_dir" ]] && store_cfg="$store_cfg
memory_repo_dir=$memory_repo_dir"
else
  store_cfg="
# public_repo/memory_project_key host the memory in ANOTHER repository, for a
# code repository that cannot hold agent notes at all. Set both, then run
# \"bash .floppy/run store\" once per machine and per worktree.
# public_repo=git@example.com:workplace/agents-memory.git
# memory_project_key=your-project-key
# memory_repo_dir overrides the derived checkout path (agents_memory_dir/<repo name>)"
fi

cfg="$repo/.floppy/config"
if [[ -f "$cfg" ]]; then
  echo "ok .floppy/config already exists, left untouched"
else
  cat > "$cfg" <<EOF
# floppy config — flat key=value, one per line. See the agent-memory skill
# for what each key governs.
memory_dir=$mem_dir
memory_language=$language${agents_memory_dir:+
agents_memory_dir=$agents_memory_dir}
$store_cfg
# private_repo and workplace_project_key have no default on purpose: a
# fresh project must not silently write into somebody else's private memory.
# Set both to use "bash .floppy/run workplace".
# private_repo=git@example.com:workplace/agents-memory.git
# workplace_project_key=your-project-key
# Checkout paths are derived: agents_memory_dir (default $HOME/agents_memory)
# holds one checkout per repository URL. workplace_memory_dir overrides that
# for this repository only, and is rarely needed.
# workplace_memory_dir=/path/to/your/workplace-memory-checkout

# commit_push controls what "bash .floppy/run commit" does after committing:
# auto (default) pulls --rebase then pushes, same as always. A repository
# with no upstream configured fails that every time — set commit_push=never
# to keep every commit local instead (the --no-push flag does this per call).
# commit_push=never

# statuses_now=docs/statuses/NOW.md
# statuses_now_chars_max=12000
# watched_dirs=docs
# watched_files=AGENTS.md
EOF
  echo "ok .floppy/config"
fi

# ---------- the store, when the memory is hosted elsewhere ----------
# Before the skeleton below on purpose: once the symlink exists, MEMORY.md is
# written through it and lands in the store, which is where it belongs. The
# other order would create a real directory in the way and make `store` refuse
# — correctly, since it never decides the fate of files somebody wrote.
if [[ -n "$public_repo" ]]; then
  echo
  # A subshell with the target repository as the working directory: the shim
  # derives FLOPPY_REPO from `git rev-parse`, and init's own cwd is the plugin
  # checkout, so a bare call would wire the plugin instead of the consumer.
  if ( cd "$repo" && AI_FLOPPY_HOME="${AI_FLOPPY_HOME:-$(cd "$self_dir/.." && pwd)}" \
       bash "$repo/.floppy/run" store ); then
    echo
  else
    echo "x wiring the store failed — nothing else was created" >&2
    exit 1
  fi
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
session, so it stays small on purpose. See \`agent-memory\` for what a
note, an index, and \`metadata.evidence\` mean.

This index is empty. Add one pointer line per note as they are written.
EOF
  echo "ok $mem_dir/MEMORY.md"
fi
# quota.lock is deliberately never created here — see the header comment.

# ---------- current-state file ----------
# Seeded at the default statuses_now path (docs/statuses/NOW.md), not a flag
# of its own: it is the same default the generated config above already
# documents, so there is nothing to ask the human that init doesn't already
# know. Without this, the first `start` on a freshly initialized
# repository finds nothing to read (`workstatus` reports "! ... is
# missing — nothing for /start to read") and the first `wrap` has
# nothing to update — a dead end that looks like something is broken.
now_file="$repo/docs/statuses/NOW.md"
if [[ -f "$now_file" ]]; then
  echo "ok docs/statuses/NOW.md already exists, left untouched"
else
  mkdir -p "$(dirname "$now_file")"
  cat > "$now_file" <<EOF
# Current state

This is what \`start\` reads in full, rewritten in place rather than
appended to — see \`agent-memory\` for how that differs from a dated
journal entry.

This repository was just set up with \`init\`. There is nothing to
report yet: the first session that does real work here should replace this
paragraph with what's actually true — where things stand, what's frozen,
what's proposed, what's missing.
EOF
  echo "ok docs/statuses/NOW.md"
fi

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
  printf '\n# floppy: machine-bound memory scope, never committed (see agent-memory)\n%s\n' \
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
durable memory. The entry point is \`.floppy/run\` — see \`agent-memory\`
for what a note looks like and how the memory is laid out, and
\`start\` / \`workstatus\` / \`wrap\` for the three rites
built on top of it. Settings live in \`.floppy/config\`; the memory itself is
under \`$mem_dir\`.
EOF
  echo "ok AGENTS.md: floppy section added"
fi

# ---------- what this machine still owes ----------
# Everything above is a file, and a file arrives with `git pull`. The memory link
# does not: its path is encoded from the checkout location, so it is per machine
# and per worktree, and skipping it is the one failure here that is completely
# silent — the session writes its memory into a second copy under ~/.claude, the
# working copy looks correct, and nothing says otherwise until someone notices
# the repository never got a note.
#
# So init does not end on the word "done". It ends by asking the same checker
# `status` asks, and naming the command if the answer is no. Adopting several
# repositories in a loop is what makes this matter: one unwired checkout is
# noticed, ten are not.
echo
if (cd "$repo" && bash "$self_dir/memory-link.sh" --check) >/dev/null 2>&1; then
  echo "ok memory wiring on this machine is in place"
else
  echo "!  not wired on this machine yet — memory would land in a second copy"
  echo "   under ~/.claude, silently. From $repo run:"
  echo "     bash .floppy/run link"
fi

echo
echo "done"
