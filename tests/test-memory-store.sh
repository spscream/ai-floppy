#!/usr/bin/env bash
# `store`: the wiring for memory hosted in another repository, and `init`'s
# flags for setting it up in one go.
#
# The layout itself is covered by test-external-memory.sh — that file asks
# whether the rite works once wired. This one asks whether getting wired is
# something a machine can do without a human performing four steps correctly,
# and whether the half-done state is caught rather than lived with.
set -uo pipefail
cd "$(dirname "$0")/.."
ROOT="$(pwd -P)"
. tests/lib.sh

# A store repository with a remote, as a machine would clone it.
make_store_remote() {
  local bare wt
  bare="$(cd "$(mktemp -d)" && pwd -P)"; git init -q --bare -b main "$bare"
  wt="$(cd "$(mktemp -d)" && pwd -P)"
  git init -q -b main "$wt"
  printf 'store\n' > "$wt/README.md"
  git -C "$wt" add -A
  git -C "$wt" -c user.email=t@t -c user.name=t commit -qm base
  git -C "$wt" remote add origin "$bare"
  git -C "$wt" push -q -u origin main
  rm -rf "$wt"
  printf '%s\n' "$bare"
}

run_store() { # repo, then args
  local r="$1"; shift
  OUT="$(cd "$r" && AI_FLOPPY_HOME="$ROOT" bash .floppy/run store "$@" 2>&1)"
  RC=$?
}

# ---------- refuses without a destination ----------
# Half a configuration is not a layout. A store with no scope has nowhere to
# put this project's notes, and defaulting one would write them into whatever
# repository happened to be configured.
repo="$(sandbox)"; cp shim/run "$repo/.floppy/run"
printf 'memory_dir=.agent-memory\n' > "$repo/.floppy/config"
run_store "$repo"
assert_eq       "no store configured: refuses"       "2" "$RC"
assert_contains "and says both keys are needed"      "project_key" "$OUT"
assert_contains "and says who does not need this"    "does not need this verb" "$OUT"

# ---------- wires a machine from nothing ----------
views="$(cd "$(mktemp -d)" && pwd -P)/views"
remote="$(make_store_remote)"
checkout="$(cd "$(mktemp -d)" && pwd -P)/store"
cat > "$repo/.floppy/config" <<EOF
memory_dir=.agent-memory
public_repo=$remote
memory_project_key=acme
memory_repo_dir=$checkout
agents_memory_dir=$views
EOF
run_store "$repo"
assert_eq       "wiring succeeds (rc)"                "0" "$RC"
assert_contains "it clones the store"                 "cloning" "$OUT"
assert_contains "it links the memory"                 "linked" "$OUT"
assert_contains "it adds the ignore line"             ".gitignore" "$OUT"
# The step that actually proves the wiring: everything else can look right
# while a write lands somewhere other than the store.
assert_contains "it verifies a write reaches the store" "lands in the store" "$OUT"
[[ -L "$repo/.agent-memory" ]] && ok "the memory is a symlink" || fail "the memory is a symlink" "symlink" "not a symlink"
assert_eq "it points into the project's own scope" "$checkout/public/projects/acme" \
  "$(cd "$repo/.agent-memory" && pwd -P)"
assert_eq "the code repository ignores it" "0" \
  "$(cd "$repo" && git check-ignore -q -- .agent-memory; echo $?)"
# The shim must now derive the external layout from that symlink alone.
env_out="$(cd "$repo" && AI_FLOPPY_HOME="$ROOT" bash .floppy/run env 2>&1)"
assert_contains "the shim derives the external layout" "FLOPPY_MEMORY_EXTERNAL=1" "$env_out"

# ---------- idempotent ----------
run_store "$repo"
assert_eq       "a second run succeeds"    "0" "$RC"
assert_contains "and changes nothing"      "already wired" "$OUT"
assert_eq "the ignore line is not duplicated" "1" \
  "$(grep -c '^/.agent-memory$' "$repo/.gitignore")"

# ---------- --check reports without changing ----------
run_store "$repo" --check
assert_eq       "--check passes on a wired machine" "0" "$RC"
assert_contains "and names the link target"         "public/projects/acme" "$OUT"

# ---------- it never decides the fate of memory somebody wrote ----------
# A real directory where the symlink belongs is the lagging-machine case, and
# those notes may be the only copies in existence.
repo2="$(sandbox)"; cp shim/run "$repo2/.floppy/run"
cat > "$repo2/.floppy/config" <<EOF
memory_dir=.agent-memory
public_repo=$remote
memory_project_key=acme
memory_repo_dir=$checkout
agents_memory_dir=$views
EOF
mkdir -p "$repo2/.agent-memory"
printf 'a note\n' > "$repo2/.agent-memory/note.md"
run_store "$repo2"
assert_eq       "a real directory in the way stops it" "1" "$RC"
assert_contains "it counts what is at risk"            "1 memory file" "$OUT"
assert_contains "and states plainly that it moved nothing" "nothing was moved or deleted" "$(printf '%s' "$OUT" | tr 'A-Z' 'a-z')"
assert_eq "the notes are untouched" "a note" "$(cat "$repo2/.agent-memory/note.md")"

# ---------- the half-done state is caught by the guard, not lived with ----------
# Ignore line added, symlink never created: notes are written and read normally,
# git cannot show them because it was told not to, and nothing publishes them.
# This is the state `store` exists to avoid and the guard exists to name.
repo3="$(sandbox)"; cp shim/run "$repo3/.floppy/run"
printf 'memory_dir=.agent-memory\nwatched_dirs=docs\n' > "$repo3/.floppy/config"
printf '/.agent-memory\n' > "$repo3/.gitignore"
mkdir -p "$repo3/.agent-memory" "$repo3/docs"
printf 'x\n' > "$repo3/docs/a.md"
git -C "$repo3" add -- .gitignore .floppy docs
git -C "$repo3" -c user.email=t@t -c user.name=t commit -qm base
printf 'y\n' >> "$repo3/docs/a.md"
guard_out="$(cd "$repo3" && AI_FLOPPY_HOME="$ROOT" bash .floppy/run guard docs/a.md 2>&1)"
guard_rc=$?
assert_eq       "ignored-but-not-external fails the guard" "1" "$guard_rc"
assert_contains "and names the real cause"   "nothing will ever commit these notes" "$guard_out"
assert_contains "and points at the fix"      "run store" "$guard_out"

# A memory that is neither ignored nor external — the ordinary layout — must
# not trip it. Without this the check above could be passing on everything.
rm -f "$repo3/.gitignore"
guard_out="$(cd "$repo3" && AI_FLOPPY_HOME="$ROOT" bash .floppy/run guard docs/a.md 2>&1)"
case "$guard_out" in
  *"nothing will ever commit these notes"*) fail "the ordinary layout is not flagged" "no such error" "$guard_out" ;;
  *) ok "the ordinary layout is not flagged" ;;
esac

# ---------- init sets the whole thing up in one call ----------
repo4="$(cd "$(mktemp -d)" && pwd -P)"; git init -q -b main "$repo4"
checkout2="$(cd "$(mktemp -d)" && pwd -P)/store2"
init_out="$(bash scripts/init.sh --repo "$repo4" \
  --memory-repo "$remote" --memory-key beta --memory-repo-dir "$checkout2" \
  --agents-memory-dir "$views" 2>&1)"
init_rc=$?
assert_eq       "init with a store succeeds"        "0" "$init_rc"
assert_contains "it wires the store"                "linked" "$init_out"
[[ -L "$repo4/.agent-memory" ]] && ok "init leaves a symlink" || fail "init leaves a symlink" "symlink" "not a symlink"
# MEMORY.md must be created THROUGH the link, so it lands in the store rather
# than in a directory that would have blocked the symlink.
assert_eq "the index landed in the store" "0" \
  "$([[ -f "$checkout2/public/projects/beta/MEMORY.md" ]] && echo 0 || echo 1)"
assert_contains "the config records where the store is" "public_repo=$remote" "$(cat "$repo4/.floppy/config")"
assert_contains "and the scope"                         "memory_project_key=beta" "$(cat "$repo4/.floppy/config")"

# Half a pair is refused rather than half-applied.
repo5="$(cd "$(mktemp -d)" && pwd -P)"; git init -q -b main "$repo5"
half_out="$(bash scripts/init.sh --repo "$repo5" --memory-repo "$remote" 2>&1)"; half_rc=$?
assert_eq       "init refuses a store with no scope" "2" "$half_rc"
assert_contains "and says why"                       "nowhere to put" "$half_out"
assert_eq "and created nothing" "1" "$([[ -e "$repo5/.floppy" ]] && echo 0 || echo 1)"

# ---------- without the flags nothing changes ----------
# The generated config must mention the option without turning it on: a project
# pointed at a store it never chose would write its notes into somebody else's
# repository.
repo6="$(cd "$(mktemp -d)" && pwd -P)"; git init -q -b main "$repo6"
bash scripts/init.sh --repo "$repo6" >/dev/null 2>&1
cfg6="$(cat "$repo6/.floppy/config")"
assert_contains "a plain init documents the option" "# public_repo=" "$cfg6"
case "$cfg6" in
  *$'\n'public_repo=*) fail "a plain init does not enable it" "commented out" "$cfg6" ;;
  *) ok "a plain init does not enable it" ;;
esac
[[ -L "$repo6/.agent-memory" ]] && fail "a plain init keeps memory in the repository" "real dir" "symlink" \
  || ok "a plain init keeps memory in the repository"

rm -rf "$views" "$repo" "$repo2" "$repo3" "$repo4" "$repo5" "$repo6" "$remote" "$checkout" "$checkout2"
summary
