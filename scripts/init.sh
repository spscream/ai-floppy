#!/usr/bin/env bash
# Lay the floppy memory out in a fresh (or already-partly-set-up) repository.
#
#   bash scripts/init.sh --repo <path> --memory-dir <dir> --language <lang>
#
# What it creates in the target repository:
#   .floppy/run              copied from this checkout — the ONLY file copied
#   .floppy/config            flat key=value, memory_dir/memory_language set
#   <memory_dir>/MEMORY.md    the empty router, so `lint` is green immediately
#   .gitignore                gains "/<memory_dir>/<memory_private_dir>" (no
#                              trailing slash: that path is a symlink, and a
#                              slash-terminated rule matches directories only,
#                              so the symlink would not be ignored and would
#                              get committed). The leaf must be the name
#                              memory-workplace.sh actually creates, or the
#                              ignore guards nothing — it was hardcoded to
#                              "local", the pre-0.6.0 name, until 2026-09-05
#   AGENTS.md                 gains a section naming .floppy/ and pointing at
#                              agent-memory
#
# What it deliberately does NOT create on an EMPTY memory: <memory_dir>/quota.lock.
# There is nothing to measure, and a ceiling copied from another project is that
# project's ceiling, which is the same as no ceiling at all. `memory-lint.sh`
# warns about the missing ratchet rather than failing.
#
# On a memory that ALREADY has notes — a repository adopting floppy after keeping
# its notes some other way — the opposite holds: there is something to measure, and
# the numbers are this project's own. So init seeds the ratchet from the corpus in
# front of it and reports what the linter makes of that corpus, grouped by kind.
# It rewrites no note. See "an existing corpus" near the end.
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
# One key, not two: project_key is the default of both memory_project_key and
# workplace_project_key, so this project is named the same in every store it
# uses. Writing the narrow memory_project_key here would leave the workplace
# scope needing a second key of its own, free to drift from this one.
project_key=$memory_key"
  [[ -n "$memory_repo_dir" ]] && store_cfg="$store_cfg
memory_repo_dir=$memory_repo_dir"
else
  store_cfg="
# public_repo/project_key host the memory in ANOTHER repository, for a
# code repository that cannot hold agent notes at all. Set both, then run
# \"bash .floppy/run store\" once per machine and per worktree.
# public_repo=git@example.com:workplace/agents-memory.git
# project_key names this project in every store it uses; memory_project_key and
# workplace_project_key override it per scope, and are rarely needed.
# project_key=your-project-key
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
#
# The leaf must be the name memory-workplace.sh actually creates, which is
# memory_private_dir (default "private"). Until 2026-09-05 it was hardcoded to
# "local" — the name the scope carried before 0.6.0, which the same script now
# migrates away — so a freshly initialised repository ignored a path nothing
# creates, and the real symlink came out untracked on the first `workplace`.
# Read the key when the config already carries it, so a repository that
# renamed the scope is covered too.
priv_dir="$(sed -n 's/^memory_private_dir=//p' "$repo/.floppy/config" 2>/dev/null | head -n1)"
[[ -n "$priv_dir" ]] || priv_dir="private"
ignore_line="/$mem_dir/$priv_dir"
touch "$gi"
# In the store layout memory_dir is itself ignored, and a rule for a path
# underneath it adds nothing — git already refuses the whole subtree. Writing
# it anyway leaves a fresh repository with two ignore blocks that read as two
# protections when there is one. Ask git rather than re-derive the answer:
# `store` may have put that line there, or a person may have.
if git -C "$repo" check-ignore -q -- "$mem_dir" 2>/dev/null; then
  echo "ok .gitignore: $mem_dir is already ignored whole, so $ignore_line is not needed"
elif grep -qxF "$ignore_line" "$gi"; then
  echo "ok .gitignore already has $ignore_line"
else
  # Ensure a trailing newline before appending, so the new block does not
  # land glued onto whatever the last existing line was.
  if [[ -s "$gi" ]] && [[ "$(tail -c1 "$gi")" != "" ]]; then
    printf '\n' >> "$gi"
  fi
  printf '\n# floppy: the private memory scope — a symlink into the private memory\n# repository, never committed here (see agent-memory)\n%s\n' \
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

# ---------- an existing corpus: measure it, never rewrite it ----------
# The counterpart to the header's rule about quota.lock, for the adoption case.
#
# Seeding the ratchet at adoption is what a ratchet is for: it does not retrofit
# an ideal size, it freezes today's and makes every increase afterwards a
# deliberate act visible in a diff. A project arriving already over some imported
# default would go red on its first run, and a linter that is red on day one is a
# linter that gets switched off.
#
# `find -L`, not `find`: memory_dir is a symlink in the external layout, and a
# plain walk of it yields nothing while exiting 0 — docs/lessons.md records what
# that cost the linter itself.
mem_abs="$repo/$mem_dir"
existing_notes="$(find -L "$mem_abs" -type f -name '*.md' \
  ! -name 'MEMORY.md' ! -name 'INDEX.md' 2>/dev/null | wc -l | tr -d ' ')"

if [[ "${existing_notes:-0}" -gt 0 ]]; then
  echo
  echo "-- existing memory: $existing_notes note(s) were already here"

  lock="$mem_abs/quota.lock"
  if [[ -f "$lock" ]]; then
    echo "ok quota.lock already exists, left untouched"
  else
    note_cap=10000
    total=0; grand=""
    while IFS= read -r f; do
      c="$(wc -m < "$f" | tr -d ' ')"
      total=$((total + c))
      if [[ "$c" -gt "$note_cap" ]]; then
        rel="${f#"$mem_abs"/}"
        grand="${grand:+$grand,}$rel"
      fi
    done < <(find -L "$mem_abs" -type f -name '*.md' ! -name 'MEMORY.md' ! -name 'INDEX.md')

    ptr=0
    while IFS= read -r idx; do
      n="$(grep -c '^- \[' "$idx" 2>/dev/null)"
      [[ "${n:-0}" -gt "$ptr" ]] && ptr="$n"
    done < <(find -L "$mem_abs" -type f \( -name 'MEMORY.md' -o -name 'INDEX.md' \))
    [[ "$ptr" -lt 40 ]] && ptr=40

    # A tenth of headroom, rounded up to the next 5000. Enough that the next
    # session does not trip the ceiling on its first note; small enough that a
    # month of growth is a decision rather than a drift.
    chars_cap=$(( (total * 11 / 10 + 4999) / 5000 * 5000 ))

    cat > "$lock" <<EOF
# Quota ratchet for the agent memory. Read by \`bash .floppy/run lint\`.
#
# Seeded by \`init\` on $(date +%Y-%m-%d), from the corpus that was already here:
# $existing_notes notes, $total characters, longest index $ptr pointers.
#
# These numbers are a ratchet, not a style preference. They are not an opinion
# about how big this memory should be — they are how big it was on the day floppy
# arrived. Growth past them has to be a deliberate act that shows up in a diff.
#
# Raising a number is allowed. Raise it in the SAME commit as the notes that need
# the room, and say in the commit message why the memory deserves to be bigger.
# Editing this file to turn a red run green, in its own commit, is the failure
# mode this file exists to make visible.

# Total characters across the notes. Seeded at the measured $total plus a tenth.
chars_max=$chars_cap

# One note. A note over the cap is not a long note, it is two notes written as
# one. This number is the convention's, not a measurement of this corpus.
note_chars_max=$note_cap

# Notes that were already over the cap when floppy arrived. They warn, they do not
# fail, and the list is meant to shrink. Do not add to it: a new note over the cap
# is a note that should have been two.
grandfathered=$grand

# Pointer lines in one index. Seeded at the longest index found here. An index
# that outgrows this splits into sub-indexes; it does not raise the number.
pointers_max=$ptr
EOF
    echo "ok quota.lock seeded from this corpus: chars_max=$chars_cap, pointers_max=$ptr"
    [[ -n "$grand" ]] && echo "   grandfathered over the $note_cap-character note cap: $grand"
  fi

  # What the linter makes of a corpus written under other conventions, grouped by
  # kind. Ninety-four identical lines are not a report — they are the raw material
  # a report is made from, and the shape of the gap is what decides whether
  # adoption is an afternoon or a week.
  lint_raw="$(cd "$repo" && bash "$self_dir/memory-lint.sh" 2>&1)"
  if printf '%s\n' "$lint_raw" | grep -q '^clean:'; then
    echo "ok memory-lint is clean on this corpus under the seeded ratchet"
    # Clean means nothing is WRONG, not that nothing needs doing, and the two
    # are not the same report. A ceiling inside its warning band passes the run
    # and still asks for work — and `pointers_max` is seeded at the longest
    # index found here, which puts that index at 100% of its own ceiling by
    # construction: the next pointer added to that half fails. Printing the
    # verdict and dropping the `!` lines would hide, on the one run an adopter
    # reads line by line, exactly the warning that exists to be read early.
    printf '%s\n' "$lint_raw" | grep '^  !' | sed 's/^  !/   !/'
  else
    echo "!  memory-lint has findings on the notes that were already here."
    echo "   Nothing was rewritten. Grouped by kind, count first:"
    printf '%s\n' "$lint_raw" | grep '^  x' | sed 's/.*: //' \
      | sed 's/[0-9][0-9]*/N/g' | sort | uniq -c | sort -rn | sed 's/^/     /'
    echo "   full list: bash .floppy/run lint"
  fi
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
