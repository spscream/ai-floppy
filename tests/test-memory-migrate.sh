#!/usr/bin/env bash
# `store --migrate`: the one operation in this plugin that moves memory.
#
# 0.26.0 changed where the memory is. A machine wired before it may hold real
# notes at <repo>/<memory_dir> — written while the symlink was missing, or by an
# agent following a skill that names that path — and after the change nothing
# reads them: every reader resolves the memory to the cache. Those notes are not
# lost, they are invisible, which is worse, because the corpus stays green while
# it stops growing.
#
# The migration is therefore mandatory and deliberately NOT automatic. Nothing
# calls this flag: not a verb, not a rite, not `init`. What this file asserts is
# the shape that makes it safe to type — every file named before it moves, a
# collision stopping everything, and nothing ever deleted.
set -uo pipefail
cd "$(dirname "$0")/.."
ROOT="$(pwd -P)"
. tests/lib.sh

GC=(-c user.email=t@t.invalid -c user.name=t)

mk_store_remote() { # -> bare path
  local bare seed
  bare="$(cd "$(mktemp -d)" && pwd -P)/store.git"
  git init -q --bare -b main "$bare"
  seed="$(cd "$(mktemp -d)" && pwd -P)"
  git init -q -b main "$seed"
  printf 'store\n' > "$seed/README.md"
  git -C "$seed" add -A
  git -C "$seed" "${GC[@]}" commit -qm seed
  git -C "$seed" remote add origin "$bare"
  git -C "$seed" push -q -u origin main
  rm -rf "$seed"
  printf '%s\n' "$bare"
}

H="$(cd "$(mktemp -d)" && pwd -P)/home"
mkdir -p "$H"
remote="$(mk_store_remote)"

mk_repo() { # -> repo path
  local d
  d="$(cd "$(mktemp -d)" && pwd -P)/code"
  git init -q -b main "$d"
  mkdir -p "$d/.floppy"
  cat > "$d/.floppy/config" <<EOF
memory_dir=.agent-memory
public_repo=$remote
project_key=acme
agents_memory_dir=$H/agents_memory
EOF
  printf 'x\n' > "$d/README.md"
  git -C "$d" add -A
  git -C "$d" "${GC[@]}" commit -qm base
  printf '%s\n' "$d"
}

run_in() { # dir args...
  local d="$1"; shift
  OUT="$(cd "$d" && HOME="$H" bash "$ROOT/scripts/run" store "$@" 2>&1)"
  RC=$?
}

# ---------- nothing to migrate is not a failure ----------
repo="$(mk_repo)"
run_in "$repo"
assert_rc "the machine is wired" 0 "$RC"
view="$H/agents_memory/acme/shared"

run_in "$repo" --migrate
assert_rc       "an empty working copy migrates cleanly" 0 "$RC"
assert_contains "and says there was nothing to do"       "nothing to migrate" "$OUT"

# A symlink left by an earlier release is not a directory of notes: it already
# resolves into the store, so there is nothing to carry across.
ln -s "$view" "$repo/.agent-memory"
run_in "$repo" --migrate
assert_rc       "a leftover symlink is nothing to migrate" 0 "$RC"
assert_contains "and it says why"                          "already resolves into" "$OUT"
assert_eq "and the symlink is still there" "0" \
  "$([[ -L "$repo/.agent-memory" ]] && echo 0 || echo 1)"
rm -f "$repo/.agent-memory"

# ---------- the real case: notes stranded in the working tree ----------
repo2="$(mk_repo)"
run_in "$repo2"
assert_rc "the second machine is wired" 0 "$RC"
mkdir -p "$repo2/.agent-memory/half"
printf 'one\n'   > "$repo2/.agent-memory/stranded.md"
printf 'two\n'   > "$repo2/.agent-memory/half/nested.md"
printf 'index\n' > "$repo2/.agent-memory/MEMORY.md"

run_in "$repo2" --migrate
assert_rc "migrating three files succeeds" 0 "$RC"
# Every file named, not a count. A person running this is watching a corpus
# move; "3 files" is not something they can check afterwards.
assert_contains "it names the flat note"    "moved .agent-memory/stranded.md" "$OUT"
assert_contains "it names the nested one"   "moved .agent-memory/half/nested.md" "$OUT"
assert_contains "it names the index"        "moved .agent-memory/MEMORY.md" "$OUT"

assert_eq "the flat note is in the store"   "one" "$(cat "$view/stranded.md" 2>/dev/null)"
assert_eq "the layout under it is kept"     "two" "$(cat "$view/half/nested.md" 2>/dev/null)"
assert_eq "and the index came too"          "index" "$(cat "$view/MEMORY.md" 2>/dev/null)"
assert_eq "nothing is left behind in the working copy" "0" \
  "$(find "$repo2/.agent-memory" -type f 2>/dev/null | wc -l | tr -d ' ')"

# It empties the directory and stops there. Removing anything that carries the
# memory's name is the human's act, here as everywhere else in this plugin.
assert_eq       "the emptied directory is left standing" "0" \
  "$([[ -d "$repo2/.agent-memory" ]] && echo 0 || echo 1)"
assert_contains "and it says whose job removing it is"   "removing it is yours to do" "$OUT"

# ---------- a name that exists on both sides stops everything ----------
# Two notes of the same name are two notes, and which one wins is not a question
# a script may answer. The whole run must be refused, not the one file: a
# half-migrated corpus is the state this plugin refuses everywhere else.
repo3="$(mk_repo)"
run_in "$repo3"
mkdir -p "$repo3/.agent-memory"
printf 'mine\n'  > "$repo3/.agent-memory/stranded.md"
printf 'fresh\n' > "$repo3/.agent-memory/only-here.md"

run_in "$repo3" --migrate
assert_rc       "a collision refuses the run" 1 "$RC"
assert_contains "and names the file"          "already in the store: stranded.md" "$OUT"
assert_contains "and says nothing was moved"  "Nothing was moved" "$OUT"
assert_eq "the colliding note is untouched in the working copy" "mine" \
  "$(cat "$repo3/.agent-memory/stranded.md" 2>/dev/null)"
assert_eq "the store's copy is untouched too" "one" \
  "$(cat "$view/stranded.md" 2>/dev/null)"
# The file that had no collision did NOT sneak across: refusing "the run" and
# refusing "that file" are different promises, and the message makes the first.
assert_eq "and the file that could have moved did not" "0" \
  "$([[ -f "$repo3/.agent-memory/only-here.md" ]] && echo 0 || echo 1)"
assert_eq "nor arrived in the store" "1" \
  "$([[ -f "$view/only-here.md" ]] && echo 0 || echo 1)"

# ---------- the private scope is not this verb's to move ----------
# The leak this refusal exists for, found in review 2026-09-25. `$view` is the
# PUBLIC store's scope. A walk that does not look at scope moved
# `<memory_dir>/private/` into `public/projects/<key>/private/` of the public
# clone — where the very next `commit` pushes it to a public remote — and said
# "will be committed from there" over it, with no line naming what had just
# changed sides. `common/` is the same shape: its two halves live in two
# repositories, and which one a stranded file belonged to is not recoverable
# from its path in a working copy.
repo5="$(mk_repo)"
run_in "$repo5"
mkdir -p "$repo5/.agent-memory/private"
printf 'secret\n' > "$repo5/.agent-memory/private/secret.md"
printf 'fine\n'   > "$repo5/.agent-memory/public-note.md"

run_in "$repo5" --migrate
assert_rc       "a real private scope refuses the run"  1 "$RC"
assert_contains "and names the scope"                   ".agent-memory/private is a real directory" "$OUT"
assert_contains "and says the destination is public"    "PUBLIC store only" "$OUT"
assert_contains "and says nothing moved"                "Nothing was moved" "$OUT"
assert_eq "the private note never left the working copy" "secret" \
  "$(cat "$repo5/.agent-memory/private/secret.md" 2>/dev/null)"
# The refusal is the WHOLE RUN, not that file: a corpus half in the store and
# half in a working copy is the state this plugin refuses everywhere else, and
# the person would have been told "ok" over it.
assert_eq "and the public note beside it did not move either" "0" \
  "$([[ -f "$repo5/.agent-memory/public-note.md" ]] && echo 0 || echo 1)"
assert_eq "nothing private arrived in the public store" "1" \
  "$([[ -e "$view/private" ]] && echo 0 || echo 1)"

# The same for common/, which is refused for a different reason and must say so
# just as loudly.
rm -rf "$repo5/.agent-memory/private"
mkdir -p "$repo5/.agent-memory/common"
printf 'shared\n' > "$repo5/.agent-memory/common/note.md"
run_in "$repo5" --migrate
assert_rc       "a real common scope refuses too" 1 "$RC"
assert_contains "and names that one"              ".agent-memory/common is a real directory" "$OUT"
rm -rf "$repo5/.agent-memory"

# A SYMLINKED scope is somebody's wiring into the right repository already, and
# is not a directory of stranded notes. It is left where it is, and the walk
# does not descend into it: `find -type f` without `-L`.
ln -s "$(mktemp -d)" "$repo5/.agent-memory"
run_in "$repo5" --migrate
assert_rc "a symlinked memory_dir is still nothing to migrate" 0 "$RC"
rm -f "$repo5/.agent-memory"

# ---------- a directory with no files in it says so ----------
# repo2 above was migrated: its .agent-memory still stands, holding the empty
# `half/` and no files at all. That is exactly the state a finished migration
# leaves behind, and running the verb again must be quiet about it.
#
# It was not. The loop was fed by a heredoc, and `$(find …)` matching nothing is
# one EMPTY line there, so the body ran once with `f=""`, `[[ -e "$view/" ]]`
# was true, and it printed `x already in the store: ` — a person told to compare
# a file with no name. Measured 2026-09-25 in review; the branch below was
# unreachable. `-print0` through a process substitution is what fixed it.
assert_eq "setup: repo2's memory directory still stands, with no files in it" "0" \
  "$([[ -d "$repo2/.agent-memory" ]] && echo 0 || echo 1)"
run_in "$repo2" --migrate
assert_rc       "an emptied directory is not a collision" 0 "$RC"
assert_contains "and it says what it found"               "holds no files" "$OUT"
assert_contains "and whose job the directory is"          "yours to remove" "$OUT"

# A name a shell would break on travels intact. The same loop split one file
# into two iterations when a newline was in its name, and aborted the run.
repo6="$(mk_repo)"
run_in "$repo6"
mkdir -p "$repo6/.agent-memory/a dir"
printf 'spaced\n' > "$repo6/.agent-memory/a dir/two words.md"
run_in "$repo6" --migrate
assert_rc       "a name with spaces migrates"  0 "$RC"
assert_contains "and is named in full"         "a dir/two words.md" "$OUT"
assert_eq "and arrived whole"  "spaced" "$(cat "$view/a dir/two words.md" 2>/dev/null)"

# ---------- it cannot run before there is a store ----------
# A project key of its own, so the view genuinely does not exist: the fixtures
# above share one agents_memory, and asking this of them would only prove that
# some OTHER project had already been wired.
repo4="$(mk_repo)"
sed -i.bak 's/^project_key=acme$/project_key=nostore/' "$repo4/.floppy/config"
rm -f "$repo4/.floppy/config.bak"
mkdir -p "$repo4/.agent-memory"
printf 'x\n' > "$repo4/.agent-memory/a.md"
run_in "$repo4" --migrate
assert_rc       "no store on the machine refuses" 1 "$RC"
assert_contains "and says to wire it first"       "with no arguments first" "$OUT"

# ---------- the flag is not a reporter ----------
run_in "$repo2" --check --migrate
assert_rc       "--check and --migrate together are refused" 2 "$RC"
assert_contains "and it says why"                            "opposites" "$OUT"

summary
