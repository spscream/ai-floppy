#!/usr/bin/env bash
# CRITICAL 1: where a memory checkout lands, and what happens when two of them
# want the same directory.
#
# The defect this file exists for was measured, not imagined: with
# memory_repo_dir and workplace_memory_dir pointing at one directory, the
# second verb found a .git there, skipped the clone, never looked at the
# remote, and reported "a write through the link lands in the workplace
# repository" over notes that were landing in the store repository — and would
# have been pushed there by `commit`. Every line said ok.
#
# The fix has two halves and both are tested here:
#   1. one parent directory (agents_memory_dir) with one checkout per URL under
#      it, so two different repositories cannot collide by construction;
#   2. an origin check whenever the checkout already exists, so a directory
#      holding some other repository is refused instead of adopted silently.
set -uo pipefail
cd "$(dirname "$0")/.."
ROOT="$(pwd -P)"
. tests/lib.sh

GC=(-c user.email=t@t.invalid -c user.name=t)

# A bare remote with one commit whose WHICH.txt names it. The marker is what
# lets an assert say which repository a directory actually came from — the
# path alone cannot, which is the whole point of this file.
mk_remote() { # bare-path name
  git init --bare -q -b main "$1"
  local s; s="$(mktemp -d)"
  git init -q -b main "$s"
  printf '%s\n' "$2" > "$s/WHICH.txt"
  git -C "$s" add -A
  git -C "$s" "${GC[@]}" commit -qm "seed $2"
  git -C "$s" remote add origin "$1"
  git -C "$s" push -q origin main
  rm -rf "$s"
}

# A consumer repository carrying the shim and a config body. Echoes its path.
mk_consumer() { # config-body
  local d; d="$(sandbox)"
  cp "$ROOT/shim/run" "$d/.floppy/run"
  printf '%s\n' "$1" > "$d/.floppy/config"
  printf 'x\n' > "$d/README.md"
  git -C "$d" add -A
  git -C "$d" "${GC[@]}" commit -qm init >/dev/null
  printf '%s\n' "$d"
}

run_verb() { # repo home verb...
  local r="$1" h="$2"; shift 2
  OUT="$(cd "$r" && HOME="$h" AI_FLOPPY_HOME="$ROOT" CLAUDE_PLUGIN_ROOT= \
    git_author=t bash .floppy/run "$@" 2>&1)"
  RC=$?
}

# ---------- 1. two URLs, one parent: no collision ----------
W1="$(mktemp -d)"; H1="$W1/home"; mkdir -p "$H1"
mk_remote "$W1/store.git" store
mk_remote "$W1/wp.git" workplace
repo1="$(mk_consumer "memory_dir=.agent-memory
agents_memory_dir=$H1/agents_memory
memory_repo=$W1/store.git
memory_project_key=acme
workplace_repo=$W1/wp.git
workplace_project_key=acme")"

run_verb "$repo1" "$H1" store
assert_rc       "store: wires up"                    0 "$RC"
run_verb "$repo1" "$H1" workplace
assert_rc       "workplace: wires up beside it"      0 "$RC"

s_dir="$H1/agents_memory/.clones/store"
w_dir="$H1/agents_memory/.clones/wp"
assert_eq "store checkout is under the parent, named for its URL" "0" \
  "$([[ -d "$s_dir/.git" ]] && echo 0 || echo 1)"
assert_eq "workplace checkout is a separate directory"            "0" \
  "$([[ -d "$w_dir/.git" ]] && echo 0 || echo 1)"
assert_eq "store checkout really is the store repository"     "store" \
  "$(cat "$s_dir/WHICH.txt" 2>/dev/null)"
assert_eq "workplace checkout really is the workplace repository" "workplace" \
  "$(cat "$w_dir/WHICH.txt" 2>/dev/null)"

# The measurement that matters: a note written to the workplace scope must be
# in the workplace repository, not merely in some directory that exists.
printf 'private\n' > "$repo1/.agent-memory/private/note.md"
assert_eq "a note in private/ lands in the workplace checkout" "0" \
  "$([[ -f "$w_dir/projects/acme/private/note.md" ]] && echo 0 || echo 1)"
assert_eq "and not in the store checkout" "1" \
  "$([[ -f "$s_dir/projects/acme/private/note.md" ]] && echo 0 || echo 1)"

# ---------- 2. a checkout of the wrong repository is refused ----------
W2="$(mktemp -d)"; H2="$W2/home"; mkdir -p "$H2/agents_memory"
mk_remote "$W2/store.git" store
mk_remote "$W2/wp.git" workplace
# Somebody else's repository already sitting exactly where wp is expected.
mkdir -p "$H2/agents_memory/.clones"; git clone -q "$W2/store.git" "$H2/agents_memory/.clones/wp"
repo2="$(mk_consumer "memory_dir=.agent-memory
agents_memory_dir=$H2/agents_memory
workplace_repo=$W2/wp.git
workplace_project_key=acme")"
# `init` would have created it; `store` is the only verb that wants it absent.
mkdir -p "$repo2/.agent-memory"

run_verb "$repo2" "$H2" workplace
assert_eq       "workplace: refuses a checkout of another repository (rc)" "1" "$([[ $RC -ne 0 ]] && echo 1 || echo 0)"
assert_contains "the refusal names the configured URL"   "$W2/wp.git"    "$OUT"
assert_contains "the refusal names what is actually there" "$W2/store.git" "$OUT"
assert_eq "nothing was linked into the wrong repository" "1" \
  "$([[ -e "$repo2/.agent-memory/private" ]] && echo 0 || echo 1)"

# ---------- 3. the layout from before this change is adopted, not re-cloned ----------
# One checkout directly at the parent, which is what every machine wired
# before agents_memory_dir existed. It must keep working with no manual move:
# the alternative is a silent second clone and notes split across two copies.
W3="$(mktemp -d)"; H3="$W3/home"; mkdir -p "$H3"
mk_remote "$W3/wp.git" workplace
git clone -q "$W3/wp.git" "$H3/agents_memory"
repo3="$(mk_consumer "memory_dir=.agent-memory
agents_memory_dir=$H3/agents_memory
workplace_repo=$W3/wp.git
workplace_project_key=acme")"
mkdir -p "$repo3/.agent-memory"

run_verb "$repo3" "$H3" workplace
assert_rc       "legacy layout: still wires up"            0 "$RC"
assert_contains "and says the checkout was adopted"  "adopt" "$OUT"
assert_eq "no second checkout was cloned underneath" "1" \
  "$([[ -d "$H3/agents_memory/.clones/wp/.git" ]] && echo 0 || echo 1)"
printf 'private\n' > "$repo3/.agent-memory/private/note.md"
assert_eq "the note lands in the adopted checkout" "0" \
  "$([[ -f "$H3/agents_memory/projects/acme/private/note.md" ]] && echo 0 || echo 1)"

# ---------- 4. a clone that would nest inside a checkout is refused ----------
# The hybrid of the two layouts above: the parent is itself a checkout, and a
# second URL wants a subdirectory of it. Cloning there would put a repository
# inside a repository, which is the shape that makes `git add -A` swallow a
# gitlink and the notes vanish from both.
W4="$(mktemp -d)"; H4="$W4/home"; mkdir -p "$H4"
mk_remote "$W4/wp.git" workplace
mk_remote "$W4/store.git" store
git clone -q "$W4/wp.git" "$H4/agents_memory"
repo4="$(mk_consumer "memory_dir=.agent-memory
agents_memory_dir=$H4/agents_memory
memory_repo=$W4/store.git
memory_project_key=acme")"

run_verb "$repo4" "$H4" store
assert_eq       "store: refuses to clone inside a checkout (rc)" "1" "$([[ $RC -ne 0 ]] && echo 1 || echo 0)"
assert_contains "the refusal says the parent is a repository" "repositor" "$OUT"
assert_eq "nothing was cloned" "1" \
  "$([[ -e "$H4/agents_memory/.clones/store" ]] && echo 0 || echo 1)"

# ---------- 5. store + workplace together: the wiring link is not committed ----------
# With a store, memory_dir is itself a symlink, so local/ is created INSIDE the
# store checkout. That symlink is per-machine wiring, and it holds an absolute
# path: committed, it dangles on every machine whose checkout lives elsewhere.
W5="$(mktemp -d)"; H5="$W5/home"; mkdir -p "$H5"
mk_remote "$W5/store.git" store
mk_remote "$W5/wp.git" workplace
repo5="$(mk_consumer "memory_dir=.agent-memory
agents_memory_dir=$H5/agents_memory
memory_repo=$W5/store.git
memory_project_key=acme
workplace_repo=$W5/wp.git
workplace_project_key=acme")"

run_verb "$repo5" "$H5" store
assert_rc "combined: store wires up"     0 "$RC"
run_verb "$repo5" "$H5" workplace
assert_rc "combined: workplace wires up" 0 "$RC"

s5="$H5/agents_memory/.clones/store"
assert_eq "the private/ link was created inside the store checkout" "0" \
  "$([[ -L "$s5/projects/acme/shared/private" ]] && echo 0 || echo 1)"
untracked="$(git -C "$s5" status --porcelain -uall 2>/dev/null | grep -c 'memory/local' | tr -d ' ')"
assert_eq "the store repository ignores that link rather than committing it" "0" "$untracked"
printf 'private\n' > "$repo5/.agent-memory/private/note.md"
assert_eq "a note through it still reaches the workplace repository" "0" \
  "$([[ -f "$H5/agents_memory/.clones/wp/projects/acme/private/note.md" ]] && echo 0 || echo 1)"

# ---------- 6. the directory name comes from the repository, not the URL ----------
# Resolution only: `env` prints what the shim derived and clones nothing, so
# this can use URL shapes no test could clone — including the scp-style form
# with no path segment, where cutting at the last slash alone would name the
# directory "git@example.com:repo".
W6="$(mktemp -d)"; H6="$W6/home"; mkdir -p "$H6"
for u in "git@example.com:team/notes-store.git=notes-store" \
         "https://example.com/team/notes-store=notes-store" \
         "git@example.com:repo.git=repo"; do
  url="${u%=*}"; want="${u#*=}"
  r="$(mk_consumer "memory_dir=.agent-memory
agents_memory_dir=$H6/agents_memory
workplace_repo=$url
workplace_project_key=acme")"
  got="$(cd "$r" && HOME="$H6" AI_FLOPPY_HOME="$ROOT" CLAUDE_PLUGIN_ROOT= \
    bash .floppy/run env 2>/dev/null | sed -n 's/^FLOPPY_WORKPLACE_MEMORY_DIR=//p')"
  assert_eq "checkout for $url is named $want" "$H6/agents_memory/.clones/$want" "$got"
done


# ---------- 7. wiring left by a pre-0.5.0 run is repointed, not refused ----------
# The scope names moved in 0.5.0, and the human moved the notes with git mv.
# What is left is a symlink into the old scope of the SAME repository: wiring,
# holding no content, recreated by this verb on every machine. Refusing it sent
# every machine through a manual rm; a link into a DIFFERENT repository is a
# separate case and still refused.
W7="$(mktemp -d)"; H7="$W7/home"; mkdir -p "$H7"
mk_remote "$W7/wp.git" workplace
repo7="$(mk_consumer "memory_dir=.agent-memory
agents_memory_dir=$H7/agents_memory
project_key=acme
workplace_repo=$W7/wp.git")"
mkdir -p "$repo7/.agent-memory"
run_verb "$repo7" "$H7" workplace
assert_rc "fresh wiring succeeds" 0 "$RC"

clone7="$H7/agents_memory/.clones/wp"
# Put the machine back into the pre-0.5.0 shape: notes in the old scope, and
# the link pointing at it.
mkdir -p "$clone7/projects/acme"
printf 'old\n' > "$clone7/projects/acme/note.md"
rm -f "$repo7/.agent-memory/private"
ln -s "$clone7/projects/acme" "$repo7/.agent-memory/private"
# The verb must refuse while the notes are still in the old scope...
run_verb "$repo7" "$H7" workplace
assert_eq       "notes still in the old scope: refuses" "1" "$([[ $RC -ne 0 ]] && echo 1 || echo 0)"
assert_contains "and prints the move recipe"            "projects/acme.moving"  "$OUT"
# ...and repoint the link once the notes have moved, without a manual rm.
mkdir -p "$clone7/projects/acme/private"
mv "$clone7/projects/acme/note.md" "$clone7/projects/acme/private/note.md"
run_verb "$repo7" "$H7" workplace
assert_rc       "after the move: wires up"              0 "$RC"
assert_contains "and says it repointed the wiring" "repointed" "$OUT"
assert_eq "the note is readable through the link again" "old" \
  "$(cat "$repo7/.agent-memory/private/note.md" 2>/dev/null)"

# A link into another repository is still refused: that one may be a workplace
# somebody else's machine wired, and this verb does not guess.
mk_remote "$W7/other.git" other
git clone -q "$W7/other.git" "$W7/other"
mkdir -p "$W7/other/projects/acme/private"
rm -f "$repo7/.agent-memory/private"
ln -s "$W7/other/projects/acme/private" "$repo7/.agent-memory/private"
run_verb "$repo7" "$H7" workplace
assert_eq       "a link into another repository is refused" "1" "$([[ $RC -ne 0 ]] && echo 1 || echo 0)"
assert_contains "and says so"                    "points elsewhere" "$OUT"

rm -rf "$W7"


# ---------- 8. wiring left under the pre-0.6.0 name is removed when it dangles ----------
# The rename from `local` to `private` leaves the old link behind, pointing at
# a path the git mv emptied. Two links where one is broken is a puzzle for
# whoever opens the directory next; a dangling symlink this verb created has
# nothing behind it to lose.
W8="$(mktemp -d)"; H8="$W8/home"; mkdir -p "$H8"
mk_remote "$W8/wp.git" workplace
repo8="$(mk_consumer "memory_dir=.agent-memory
agents_memory_dir=$H8/agents_memory
project_key=acme
workplace_repo=$W8/wp.git")"
mkdir -p "$repo8/.agent-memory"
run_verb "$repo8" "$H8" workplace
assert_rc "wires up under the new name" 0 "$RC"

# The two links a 0.5.x machine would have, both now pointing nowhere.
ln -s "$H8/agents_memory/.clones/wp/projects/acme/local" "$repo8/.agent-memory/local"
ln -s "../.clones/wp/projects/acme/local" "$H8/agents_memory/acme/local"
assert_eq "setup: the old links dangle" "2" \
  "$(( $([[ -L "$repo8/.agent-memory/local" && ! -e "$repo8/.agent-memory/local" ]] && echo 1 || echo 0) + $([[ -L "$H8/agents_memory/acme/local" && ! -e "$H8/agents_memory/acme/local" ]] && echo 1 || echo 0) ))"

run_verb "$repo8" "$H8" workplace
assert_rc       "a second run still succeeds"        0 "$RC"
assert_contains "and says it removed them" "removed the dangling" "$OUT"
assert_eq "the old link in the repository is gone" "1" \
  "$([[ -e "$repo8/.agent-memory/local" || -L "$repo8/.agent-memory/local" ]] && echo 0 || echo 1)"
assert_eq "the old link in the view is gone"       "1" \
  "$([[ -e "$H8/agents_memory/acme/local" || -L "$H8/agents_memory/acme/local" ]] && echo 0 || echo 1)"
assert_eq "the new link still works"          "0" \
  "$([[ -d "$repo8/.agent-memory/private" ]] && echo 0 || echo 1)"

# A link under the old name that still RESOLVES is not touched: it points at
# something real, and this verb does not decide what that is.
mkdir -p "$W8/somewhere"
ln -s "$W8/somewhere" "$repo8/.agent-memory/local"
run_verb "$repo8" "$H8" workplace
assert_eq "a live link under the old name is left alone" "0" \
  "$([[ -L "$repo8/.agent-memory/local" ]] && echo 0 || echo 1)"

rm -rf "$W8"

rm -rf "$W1" "$W2" "$W3" "$W4" "$W5" "$W6"
summary
