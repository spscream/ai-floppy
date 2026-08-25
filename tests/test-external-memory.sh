#!/usr/bin/env bash
# Memory hosted in a repository other than the code's.
#
# The layout a consumer reaches for when it cannot commit agent notes next to
# the code — a checkout it does not own, or a policy. memory_dir is a symlink
# into a separate git repository, gitignored here.
#
# Everything below is about ONE risk: this layout fails silently. Notes keep
# being written and read on the machine that has the symlink, so the setup
# looks healthy right up to the moment a second machine, or a second week,
# finds nothing. Each test names the silence it removes.
set -uo pipefail
cd "$(dirname "$0")/.."
ROOT="$(pwd -P)"
. tests/lib.sh

# A memory tree that passes memory-lint: the wrap gates run it first, and a
# memory with no index fails there before any of this is reached.
seed_memory() { # dir
  mkdir -p "$1/half"
  printf '# Index\n- [Half](half/INDEX.md) — pointer\n' > "$1/MEMORY.md"
  printf '# Half\n- [A note](a-note.md) — pointer\n' > "$1/half/INDEX.md"
  printf -- '---\nname: a-note\ndescription: a note\nmetadata:\n  type: project\n  evidence: read\n---\nBody.\n' > "$1/half/a-note.md"
  printf 'chars_max=100000\nnote_chars_max=10000\npointers_max=40\ngrandfathered=\n' > "$1/quota.lock"
}

# The whole layout: a code repository with a remote, a store repository with
# its own remote, and the symlink between them. Echoes "repo store storeremote".
build() {
  local coderemote store storeremote repo
  coderemote="$(cd "$(mktemp -d)" && pwd -P)"; git init -q --bare -b main "$coderemote"
  storeremote="$(cd "$(mktemp -d)" && pwd -P)"; git init -q --bare -b main "$storeremote"

  # The store keeps this project's memory under projects/<key>/memory — a
  # subdirectory, not the root, because one store usually holds several
  # projects. Everything downstream has to translate between that path and the
  # `.agent-memory/...` path the session actually types.
  store="$(cd "$(mktemp -d)" && pwd -P)"
  git init -q -b main "$store"
  mkdir -p "$store/projects/acme/memory"
  seed_memory "$store/projects/acme/memory"
  git -C "$store" add -A
  git -C "$store" -c user.email=t@t -c user.name=t commit -qm base
  git -C "$store" remote add origin "$storeremote"
  git -C "$store" push -q -u origin main

  repo="$(sandbox)"; cp shim/run "$repo/.floppy/run"
  cat > "$repo/.floppy/config" <<EOF
memory_dir=.agent-memory
statuses_now=state/NOW.md
statuses_now_chars_max=4000
watched_dirs=state
EOF
  mkdir -p "$repo/state"
  printf '| Notes | 1 | 2 | up |\n' > "$repo/state/NOW.md"
  printf '/.agent-memory\n' > "$repo/.gitignore"
  ln -s "$store/projects/acme/memory" "$repo/.agent-memory"
  git -C "$repo" add -- .gitignore .floppy state
  git -C "$repo" -c user.email=t@t -c user.name=t commit -qm base
  git -C "$repo" remote add origin "$coderemote"
  git -C "$repo" push -q -u origin main
  printf '%s %s %s\n' "$repo" "$store" "$storeremote"
}

run_in() { # repo, then args
  local r="$1"; shift
  # Identity via the environment, not `git -c`: `git -c k=v bash …` makes git
  # try to run `bash` as one of its own subcommands, which is how the first
  # version of this helper turned every assertion below into the same
  # unrelated failure.
  OUT="$(cd "$r" && AI_FLOPPY_HOME="$ROOT" \
    GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t \
    GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t \
    bash .floppy/run "$@" 2>&1)"
  RC=$?
}

set -- $(build); repo="$1"; store="$2"; storeremote="$3"

# ---------- the shim knows which layout it is in ----------
# Derived from the resolved path, never configured: a boolean in the config
# would disagree with reality precisely when the symlink failed to be created.
run_in "$repo" env
assert_contains "external memory is detected"      "FLOPPY_MEMORY_EXTERNAL=1" "$OUT"
assert_contains "the store's git root is resolved" "FLOPPY_MEMORY_STORE=$store" "$OUT"

# ---------- and does not misfire on the ordinary layout ----------
plain="$(sandbox)"; cp shim/run "$plain/.floppy/run"
mkdir -p "$plain/.agent-memory"
run_in "$plain" env
assert_contains "in-repo memory is not called external" "FLOPPY_MEMORY_EXTERNAL=0" "$OUT"
assert_contains "and has no store"                      "FLOPPY_MEMORY_STORE=" "$OUT"

# ---------- status: the code repo is clean and that is not the whole truth ----------
# `git status` here is structurally blind to the notes. Without this section
# /start reports a clean tree while the session's memory sits uncommitted.
printf -- '---\nname: fresh\ndescription: fresh\nmetadata:\n  type: project\n  evidence: read\n---\nNew.\n' > "$repo/.agent-memory/half/fresh.md"
printf -- '- [Fresh](fresh.md) — pointer\n' >> "$repo/.agent-memory/half/INDEX.md"
run_in "$repo" status
assert_contains "status names the memory store"        "memory store" "$OUT"
assert_contains "status counts what is uncommitted there" "uncommitted in $store" "$OUT"

# ---------- guard: a change in the store counts as a change ----------
# The invariant is unchanged — your list must match what actually changed — but
# half of it now has to be asked of the other repository.
run_in "$repo" guard state/NOW.md
assert_eq       "an unclaimed note in the store is caught (rc)" "1" "$RC"
assert_contains "and is named in the path the session typed"    ".agent-memory/half/fresh.md" "$OUT"

run_in "$repo" guard .agent-memory/half/fresh.md .agent-memory/half/INDEX.md
assert_eq       "claiming the store's files satisfies the guard (rc)" "0" "$RC"

# ---------- guard: the ignore rule is verified, not assumed ----------
# Added by hand at setup, therefore skipped at setup. Without it this
# repository can still stage the memory — the one thing the layout prevents.
mv "$repo/.gitignore" "$repo/.gitignore.off"
run_in "$repo" guard .agent-memory/half/fresh.md .agent-memory/half/INDEX.md
assert_eq       "an un-ignored memory path fails the guard (rc)" "1" "$RC"
assert_contains "and the fix is spelled out"        "add \"/.agent-memory\" to .gitignore" "$OUT"
mv "$repo/.gitignore.off" "$repo/.gitignore"

# ---------- check: the diff the human sees includes the notes ----------
printf 'edit\n' >> "$repo/state/NOW.md"
run_in "$repo" check .agent-memory/half/fresh.md .agent-memory/half/INDEX.md state/NOW.md
assert_contains "check reports the store"          "memory store" "$OUT"
assert_contains "check shows what is going out there" "fresh.md" "$OUT"
assert_contains "check says commit closes it too"  "closes this store" "$OUT"
assert_eq       "check is green on a correct layout (rc)" "0" "$RC"

# ---------- commit: two repositories, one call ----------
store_before="$(git -C "$store" rev-parse HEAD)"
run_in "$repo" commit -m "notes and slice" .agent-memory/half/fresh.md .agent-memory/half/INDEX.md state/NOW.md
assert_eq       "commit succeeds across both repositories (rc)" "0" "$RC"
assert_contains "it names the store"          "$store" "$OUT"
[[ "$(git -C "$store" rev-parse HEAD)" != "$store_before" ]] \
  && ok "the store got a commit" || fail "the store got a commit" "new HEAD" "unchanged"
assert_eq "the note is committed in the store" "projects/acme/memory/half/fresh.md" \
  "$(git -C "$store" show --name-only --format= HEAD | grep fresh || true)"
assert_eq "the store is pushed" "0" \
  "$(git -C "$store" rev-list --count '@{u}..HEAD' 2>/dev/null)"
assert_eq "the code repository is pushed too" "0" \
  "$(git -C "$repo" rev-list --count '@{u}..HEAD' 2>/dev/null)"
# The memory must not have leaked into the code repository — that is the point.
assert_eq "no memory file landed in the code repository" "" \
  "$(git -C "$repo" ls-files | grep agent-memory || true)"
assert_eq "the lock is released" "free" "$(cd "$repo" && AI_FLOPPY_HOME="$ROOT" bash .floppy/run lock status)"

# ---------- a session that wrote only memory still closes ----------
# Nothing changed in the code repository, so `git add` there would have nothing
# to stage and `git commit` would fail — the rite must not report an error for
# a session that did exactly what it was supposed to.
printf -- '---\nname: second\ndescription: second\nmetadata:\n  type: project\n  evidence: read\n---\nMore.\n' > "$repo/.agent-memory/half/second.md"
printf -- '- [Second](second.md) — pointer\n' >> "$repo/.agent-memory/half/INDEX.md"
run_in "$repo" commit -m "memory only" .agent-memory/half/second.md .agent-memory/half/INDEX.md
assert_eq       "a memory-only session closes cleanly (rc)" "0" "$RC"
assert_contains "and says nothing was written here"  "no commit here" "$OUT"
assert_eq "the store is still pushed" "0" \
  "$(git -C "$store" rev-list --count '@{u}..HEAD' 2>/dev/null)"

# ---------- an unpushable store is loud, not silent ----------
# The failure this whole layout risks: notes committed where nothing publishes
# them. The rite must not print "session closed" over it.
git -C "$store" remote set-url origin /nonexistent/remote.git
printf -- '---\nname: third\ndescription: third\nmetadata:\n  type: project\n  evidence: read\n---\nX.\n' > "$repo/.agent-memory/half/third.md"
printf -- '- [Third](third.md) — pointer\n' >> "$repo/.agent-memory/half/INDEX.md"
printf 'edit2\n' >> "$repo/state/NOW.md"
run_in "$repo" commit -m "third" .agent-memory/half/third.md .agent-memory/half/INDEX.md state/NOW.md
assert_eq       "an unpushable store fails the call (rc)" "1" "$RC"
assert_contains "and says the notes are not published"  "NOT pushed" "$OUT"
case "$OUT" in
  *"session closed. Memory, slice and procedure are committed and pushed"*)
    fail "it does not claim a clean close" "no such claim" "$OUT" ;;
  *) ok "it does not claim a clean close" ;;
esac

# ---------- memory outside git entirely ----------
# A plain directory in $HOME is a real thing people do. It works for writing
# and reading, and publishes nothing — so it must be named, not treated as a
# store that merely happens to be quiet.
loose="$(cd "$(mktemp -d)" && pwd -P)"
seed_memory "$loose"
repo2="$(sandbox)"; cp shim/run "$repo2/.floppy/run"
printf 'memory_dir=.agent-memory\n' > "$repo2/.floppy/config"
printf '/.agent-memory\n' > "$repo2/.gitignore"
ln -s "$loose" "$repo2/.agent-memory"
git -C "$repo2" add -- .gitignore .floppy
git -C "$repo2" -c user.email=t@t -c user.name=t commit -qm base
run_in "$repo2" env
assert_contains "outside git: still detected as external" "FLOPPY_MEMORY_EXTERNAL=1" "$OUT"
assert_contains "outside git: no store is claimed"        "FLOPPY_MEMORY_STORE=" "$OUT"
run_in "$repo2" status
assert_contains "status says nothing can publish it" "no git repository" "$OUT"

rm -rf "$repo" "$store" "$storeremote" "$plain" "$loose" "$repo2"
summary
