#!/usr/bin/env bash
# CRITICAL: the rite has to close from a git worktree that NOBODY WIRED.
#
# This is the case the tool is actually used in and the one every other test
# file missed. Tooling (fleet, thurbox, a person in a hurry) cuts a worktree per
# task with `git worktree add`; the agent arrives in a finished tree, is given a
# task, and runs no wiring verb — those appear in no brief and no hook. So a
# fixture that creates the memory symlink by hand, as tests/test-wrap-lock.sh
# did until 0.26.0, tests a state that exists on no machine.
#
# Measured 2026-09-25 on a worktree of this plugin's own repository, before the
# change this file guards: `lint` exited 2 with "this repository does not use
# this memory layout", `check` printed MEMORY LINT COULD NOT RUN, `link` called
# the right repository the wrong one, and `commit` stopped at "memory lint is
# red". The rite could not be closed from a worktree at all, and this
# repository's own corpus took its last note on 2026-09-09 while a git-tracked
# corpus on the same machine kept growing through the same fortnight.
#
# Every case below starts from `git worktree add` and touches nothing after it.
set -uo pipefail
cd "$(dirname "$0")/.."
ROOT="$(pwd -P)"
. tests/lib.sh

GC=(-c user.email=t@t.invalid -c user.name=t)

# A store remote with this project's scope already in it, as a machine that has
# run `store` once would have.
store_remote="$(cd "$(mktemp -d)" && pwd -P)/store.git"
git init -q --bare -b main "$store_remote"
seed="$(cd "$(mktemp -d)" && pwd -P)"
git init -q -b main "$seed"
mkdir -p "$seed/public/projects/acme"
printf '# Memory index\n\n- [A fact](a-fact.md) — pointer\n' > "$seed/public/projects/acme/MEMORY.md"
printf -- '---\nname: a-fact\ndescription: a fact\nmetadata:\n  type: project\n  evidence: read\n---\nBody.\n' \
  > "$seed/public/projects/acme/a-fact.md"
git -C "$seed" add -A
git -C "$seed" "${GC[@]}" commit -qm seed
git -C "$seed" remote add origin "$store_remote"
git -C "$seed" push -q -u origin main
rm -rf "$seed"

# The machine: one HOME, one agents_memory under it.
H="$(cd "$(mktemp -d)" && pwd -P)/home"
mkdir -p "$H/.claude/projects"

# The consumer repository, wired once on this machine by the human who set it
# up — which is the ONLY wiring anybody does.
repo="$(cd "$(mktemp -d)" && pwd -P)/code"
git init -q -b main "$repo"
mkdir -p "$repo/.floppy" "$repo/docs/statuses"
cat > "$repo/.floppy/config" <<EOF
memory_dir=.agent-memory
public_repo=$store_remote
project_key=acme
agents_memory_dir=$H/agents_memory
watched_dirs=docs/statuses
EOF
printf '| Notes | 1 | 2 | up |\n' > "$repo/docs/statuses/NOW.md"
# In the repository's own config, not on the command line: the `commit` verb
# runs git itself, and HOME here is a bare fixture with no ~/.gitconfig in it.
git -C "$repo" config user.email t@t.invalid
git -C "$repo" config user.name t
git -C "$repo" add -A
git -C "$repo" "${GC[@]}" commit -qm base

run_in() { # dir verb...
  local d="$1"; shift
  OUT="$(cd "$d" && HOME="$H" bash "$ROOT/scripts/run" "$@" 2>&1)"
  RC=$?
}

run_in "$repo" store
assert_rc "the machine is wired once, in the checkout" 0 "$RC"

# ---------- a worktree, cut and left exactly as it lands ----------
wt="$(cd "$(mktemp -d)" && pwd -P)/wt"
git -C "$repo" worktree add -q "$wt" -b task 2>/dev/null

# The fact the whole change rests on. .floppy/config is tracked so it arrives;
# the memory is not tracked and cannot arrive. No test may paper over this with
# an `ln -s`, because no tool on any machine performs one.
assert_eq "the worktree carries .floppy/config" "0" \
  "$([[ -f "$wt/.floppy/config" ]] && echo 0 || echo 1)"
assert_eq "and carries no memory of any kind" "absent" \
  "$([[ -e "$wt/.agent-memory" || -L "$wt/.agent-memory" ]] && echo present || echo absent)"

# ---------- and the memory is reachable anyway ----------
run_in "$wt" env
mem="$(printf '%s\n' "$OUT" | sed -n 's/^FLOPPY_MEMORY_REAL=//p')"
# FULLY resolved, symlinks and all: FLOPPY_MEMORY_REAL is what every gate
# compares real paths against, so it is the store clone itself and not the view
# that points at it. The view is the address; this is the place.
assert_eq "the worktree resolves the memory to the machine's cache" \
  "$(cd "$H/agents_memory/acme/shared" && pwd -P)" "$mem"
assert_contains "and knows it is external" "FLOPPY_MEMORY_EXTERNAL=1" "$OUT"

# Same answer from the checkout, which is what "addressed by repository" means:
# two working copies, one memory, and no per-copy step to get there.
run_in "$repo" env
assert_eq "the checkout resolves it to the same place" \
  "$mem" "$(printf '%s\n' "$OUT" | sed -n 's/^FLOPPY_MEMORY_REAL=//p')"

# ---------- the rite closes from there ----------
run_in "$wt" lint
assert_rc       "lint is green in the worktree (rc)" 0 "$RC"
assert_contains "and it read the real corpus"        "1 notes" "$OUT"

printf '| Notes | 2 | 3 | up |\n' >> "$wt/docs/statuses/NOW.md"
run_in "$wt" check docs/statuses/NOW.md
assert_rc       "check is green in the worktree (rc)" 0 "$RC"
assert_contains "and says so in the words commit wants" "ready:" "$OUT"
case "$OUT" in
  *"MEMORY LINT COULD NOT RUN"*) fail "and never claims the memory is unreadable" "no such line" "$OUT" ;;
  *)                             ok   "and never claims the memory is unreadable" ;;
esac

run_in "$wt" guard docs/statuses/NOW.md
assert_rc "guard is green in the worktree (rc)" 0 "$RC"

run_in "$wt" commit --no-push -m "a note from a worktree" docs/statuses/NOW.md
assert_rc       "commit closes the rite from the worktree (rc)" 0 "$RC"
assert_contains "and passed the file-list gate, not stopped before it" \
  "memory clean, file list matches" "$OUT"

# ---------- a note written in the worktree is in the store ----------
# The measurement that matters: not that a path resolves, but that a write
# through it lands where `commit` will publish it from.
printf -- '---\nname: from-worktree\ndescription: written in a worktree\nmetadata:\n  type: project\n  evidence: read\n---\nBody.\n' \
  > "$mem/from-worktree.md"
clone="$H/agents_memory/.clones/store"
assert_eq "a note written through the worktree's memory is in the store clone" "0" \
  "$([[ -f "$clone/public/projects/acme/from-worktree.md" ]] && echo 0 || echo 1)"
rm -f "$mem/from-worktree.md"

# ---------- the harness pointer, which is still per working directory ----------
# The memory is addressed by repository; the harness's own session loader is
# not — it reads <config>/projects/<encoded cwd>/memory, one per working
# directory, and that path is the harness's to choose, not this plugin's. So
# this half cannot be solved by addressing, and is made automatically instead,
# by the config parser, on any verb. A step nobody runs is a step that does not
# happen.
enc="$(printf '%s' "$wt" | tr '/._' '---')"
assert_eq "the harness pointer for the worktree was made without anybody asking" "0" \
  "$([[ -L "$H/.claude/projects/$enc/memory" ]] && echo 0 || echo 1)"
assert_eq "and it points at the memory, not at a second copy" "$mem" \
  "$(cd "$H/.claude/projects/$enc/memory" 2>/dev/null && pwd -P)"
run_in "$wt" link --check
assert_rc "and the link verb agrees the working directory is wired" 0 "$RC"

# It is per working directory, so the checkout has its own — and neither was
# created by a person.
enc_repo="$(printf '%s' "$repo" | tr '/._' '---')"
assert_eq "the checkout has its own pointer, to the same memory" "$mem" \
  "$(cd "$H/.claude/projects/$enc_repo/memory" 2>/dev/null && pwd -P)"

# Announced once, on stderr, and not again: a pointer that appears with nobody
# told is the silent wiring this plugin argues against, and one announced on
# every verb is noise in the middle of a rite.
run_in "$wt" env
case "$OUT" in
  *"memory pointer created"*) fail "and says nothing on the second run" "silence" "$OUT" ;;
  *)                          ok   "and says nothing on the second run" ;;
esac

# ---------- a stray directory does not take the address back ----------
# The trap the first draft of this change walked into, found in review
# 2026-09-25. Resolution was conditional on the path being ABSENT, which reads
# as caution and is not: the skills of this same plugin still tell an agent to
# write `.agent-memory/<file>`, so ONE note from an agent that followed them
# recreated the directory, took the address back, and put the repository
# straight into the state this release removes — `lint` exit 2, `check` printing
# MEMORY LINT COULD NOT RUN, the whole store corpus invisible.
#
# The configuration decides now. A repository wired to a store resolves into
# that store, and whatever stands in a working copy is not an address.
mkdir -p "$wt/.agent-memory"
printf -- '---\nname: stray\ndescription: written by an agent following a skill\nmetadata:\n  type: project\n  evidence: read\n---\nBody.\n' \
  > "$wt/.agent-memory/stray.md"
run_in "$wt" env
assert_eq "a stray directory does not move the memory" "$mem" \
  "$(printf '%s\n' "$OUT" | sed -n 's/^FLOPPY_MEMORY_REAL=//p')"
run_in "$wt" lint
assert_rc "and lint still reads the store" 0 "$RC"
run_in "$wt" check docs/statuses/NOW.md
case "$OUT" in
  *"MEMORY LINT COULD NOT RUN"*) fail "and check does not go blind" "no such line" "$OUT" ;;
  *)                             ok   "and check does not go blind" ;;
esac
# Not silently, though. A fork of the corpus that nothing reads is what a gate
# is for, and this is the only place it can be caught: the path is ignored, so
# git says nothing, and `lint` is green over the store.
run_in "$wt" guard docs/statuses/NOW.md
assert_rc       "but the guard refuses while it stands (rc)"  1 "$RC"
assert_contains "and names it as unread"                      "nothing reads it" "$OUT"
assert_contains "and names the verb that moves it"            "store --migrate" "$OUT"
rm -rf "$wt/.agent-memory"

# ---------- a reporting flag reports ----------
# `--check` promises to change nothing, and the harness pointer is made by the
# config parser on any verb — so without an exemption, the one call a person
# makes precisely because they want nothing touched was the call that wrote into
# their configuration directory. Found in review 2026-09-25.
enc_probe="$(printf '%s' "$repo" | tr '/._' '---')"
rm -rf "$H/.claude/projects/$enc_probe"
run_in "$repo" store --check
assert_rc "store --check passes on a wired machine" 0 "$RC"
assert_eq "and created no pointer, because it promised to change nothing" "1" \
  "$([[ -e "$H/.claude/projects/$enc_probe" ]] && echo 0 || echo 1)"
# And an ordinary verb in the same directory still makes it.
run_in "$repo" env
assert_eq "an ordinary verb makes it again" "0" \
  "$([[ -L "$H/.claude/projects/$enc_probe/memory" ]] && echo 0 || echo 1)"

# ---------- a dangling pointer is repaired, not stepped around ----------
# Reachable by following this tool's own advice: `store` says removing a
# leftover symlink is yours to do, and the moment somebody does, a pointer made
# to it dangles. Nothing was red then — the session simply read an empty memory,
# which is the silent second copy `link` exists to prevent, arrived at from the
# other side.
rm -f "$H/.claude/projects/$enc_probe/memory"
ln -s "$repo/.agent-memory-that-is-gone" "$H/.claude/projects/$enc_probe/memory"
run_in "$repo" env
assert_eq "the dangling pointer now leads to the memory" "$mem" \
  "$(cd "$H/.claude/projects/$enc_probe/memory" 2>/dev/null && pwd -P)"

# ---------- what already stands in a working copy is never touched ----------
# The pre-0.26.0 symlink still resolves and everything follows it. Removing
# anything that carries the memory's name is not this plugin's act.
ln -s "$mem" "$repo/.agent-memory"
run_in "$repo" env
assert_eq "a symlink left by an earlier release is still followed" "$mem" \
  "$(printf '%s\n' "$OUT" | sed -n 's/^FLOPPY_MEMORY_REAL=//p')"
run_in "$repo" store --check
assert_rc       "store reports it rather than removing it" 0 "$RC"
assert_contains "and says whose decision that is"  "Removing it is yours to do" "$OUT"
assert_eq "and it is still there afterwards" "0" \
  "$([[ -L "$repo/.agent-memory" ]] && echo 0 || echo 1)"
rm -f "$repo/.agent-memory"

# ---------- the layout nobody configured for a cache ----------
# A repository wired by hand before 0.26.0 has no public_repo to compose a
# cache path from, and the human who would re-run `store` is the human who is
# not there. Its worktrees fall back to the symlink in the MAIN working tree,
# which every worktree of a clone shares by definition.
legacy_store="$(cd "$(mktemp -d)" && pwd -P)/notes"
mkdir -p "$legacy_store"
printf '# Memory index\n' > "$legacy_store/MEMORY.md"
legacy="$(cd "$(mktemp -d)" && pwd -P)/legacy"
git init -q -b main "$legacy"
mkdir -p "$legacy/.floppy"
printf 'memory_dir=.agent-memory\nproject_key=legacy\n' > "$legacy/.floppy/config"
printf '/.agent-memory\n' > "$legacy/.gitignore"
git -C "$legacy" add -A
git -C "$legacy" "${GC[@]}" commit -qm base
ln -s "$legacy_store" "$legacy/.agent-memory"
legacy_wt="$(cd "$(mktemp -d)" && pwd -P)/lwt"
git -C "$legacy" worktree add -q "$legacy_wt" -b lt 2>/dev/null
run_in "$legacy_wt" env
assert_eq "a hand-wired repository's worktree finds the memory through the main tree" \
  "$(cd "$legacy_store" && pwd -P)" \
  "$(printf '%s\n' "$OUT" | sed -n 's/^FLOPPY_MEMORY_REAL=//p')"

# And an ORDINARY repository is not dragged into that: two worktrees of a
# repository whose memory is a real directory are two checkouts that each carry
# their own, which is exactly what git already does for tracked files.
plain="$(cd "$(mktemp -d)" && pwd -P)/plain"
git init -q -b main "$plain"
mkdir -p "$plain/.floppy" "$plain/.agent-memory"
printf 'memory_dir=.agent-memory\nproject_key=plain\n' > "$plain/.floppy/config"
printf '# Memory index\n' > "$plain/.agent-memory/MEMORY.md"
git -C "$plain" add -A
git -C "$plain" "${GC[@]}" commit -qm base
plain_wt="$(cd "$(mktemp -d)" && pwd -P)/pwt"
git -C "$plain" worktree add -q "$plain_wt" -b pt 2>/dev/null
run_in "$plain_wt" env
assert_eq "an ordinary repository's worktree keeps its own memory" \
  "$plain_wt/.agent-memory" \
  "$(printf '%s\n' "$OUT" | sed -n 's/^FLOPPY_MEMORY_REAL=//p')"
assert_contains "and it is not called external" "FLOPPY_MEMORY_EXTERNAL=0" "$OUT"

summary
