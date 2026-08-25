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

s_dir="$H1/agents_memory/store"
w_dir="$H1/agents_memory/wp"
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
printf 'private\n' > "$repo1/.agent-memory/local/note.md"
assert_eq "a note in local/ lands in the workplace checkout" "0" \
  "$([[ -f "$w_dir/projects/acme/note.md" ]] && echo 0 || echo 1)"
assert_eq "and not in the store checkout" "1" \
  "$([[ -f "$s_dir/projects/acme/note.md" ]] && echo 0 || echo 1)"

# ---------- 2. a checkout of the wrong repository is refused ----------
W2="$(mktemp -d)"; H2="$W2/home"; mkdir -p "$H2/agents_memory"
mk_remote "$W2/store.git" store
mk_remote "$W2/wp.git" workplace
# Somebody else's repository already sitting exactly where wp is expected.
git clone -q "$W2/store.git" "$H2/agents_memory/wp"
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
  "$([[ -e "$repo2/.agent-memory/local" ]] && echo 0 || echo 1)"

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
  "$([[ -d "$H3/agents_memory/wp/.git" ]] && echo 0 || echo 1)"
printf 'private\n' > "$repo3/.agent-memory/local/note.md"
assert_eq "the note lands in the adopted checkout" "0" \
  "$([[ -f "$H3/agents_memory/projects/acme/note.md" ]] && echo 0 || echo 1)"

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
  "$([[ -e "$H4/agents_memory/store" ]] && echo 0 || echo 1)"

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

s5="$H5/agents_memory/store"
assert_eq "the local/ link was created inside the store checkout" "0" \
  "$([[ -L "$s5/projects/acme/memory/local" ]] && echo 0 || echo 1)"
untracked="$(git -C "$s5" status --porcelain -uall 2>/dev/null | grep -c 'memory/local' | tr -d ' ')"
assert_eq "the store repository ignores that link rather than committing it" "0" "$untracked"
printf 'private\n' > "$repo5/.agent-memory/local/note.md"
assert_eq "a note through it still reaches the workplace repository" "0" \
  "$([[ -f "$H5/agents_memory/wp/projects/acme/note.md" ]] && echo 0 || echo 1)"

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
  assert_eq "checkout for $url is named $want" "$H6/agents_memory/$want" "$got"
done

rm -rf "$W1" "$W2" "$W3" "$W4" "$W5" "$W6"
summary
