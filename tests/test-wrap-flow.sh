#!/usr/bin/env bash
set -uo pipefail
cd "$(dirname "$0")/.."
. tests/lib.sh
ROOT="$(pwd)"

# A minimal clean memory tree, for sandboxes built after the first one: every
# `commit` call re-runs memory-lint.sh as its first gate, and a memory dir
# with no MEMORY.md, or no notes at all, fails that gate before the commit
# machinery is even reached.
write_clean_memory() { # $1 = repo path
  mkdir -p "$1/brain/half"
  cat > "$1/brain/MEMORY.md" <<'EOFM'
# Index
- [Half](half/INDEX.md) — pointer
EOFM
  cat > "$1/brain/half/INDEX.md" <<'EOFM'
# Half
- [A note](a-note.md) — pointer
EOFM
  cat > "$1/brain/half/a-note.md" <<'EOFM'
---
name: a-note
description: a note
metadata:
  type: project
  evidence: read
---
Body.
EOFM
  printf 'notes_max=10\nchars_max=100000\nnote_chars_max=10000\npointers_max=40\ngrandfathered=\n' > "$1/brain/quota.lock"
}

# A bare repository stands in for the remote. Never a real one: this script
# pushes, and a test that reaches a real remote is a test that publishes.
remote="$(cd "$(mktemp -d)" && pwd -P)"; git init -q --bare -b main "$remote"
repo="$(sandbox)"; cp shim/run "$repo/.floppy/run"
cat > "$repo/.floppy/config" <<'EOF2'
memory_dir=brain
statuses_now=state/NOW.md
statuses_now_chars_max=4000
watched_dirs=state,.floppy
EOF2
mkdir -p "$repo/brain/half" "$repo/state"
printf '| Notes | 1 | 2 | up |\n' > "$repo/state/NOW.md"
# A minimal clean memory tree: wrap-commit.sh re-runs memory-lint.sh as its
# first gate, and a memory dir with no MEMORY.md, or no notes at all, fails
# that gate before the commit machinery is even reached.
cat > "$repo/brain/MEMORY.md" <<'EOF2b'
# Index
- [Half](half/INDEX.md) — pointer
EOF2b
cat > "$repo/brain/half/INDEX.md" <<'EOF2c'
# Half
- [A note](a-note.md) — pointer
EOF2c
cat > "$repo/brain/half/a-note.md" <<'EOF2d'
---
name: a-note
description: a note
metadata:
  type: project
  evidence: read
---
Body.
EOF2d
printf 'notes_max=10\nchars_max=100000\nnote_chars_max=10000\npointers_max=40\ngrandfathered=\n' > "$repo/brain/quota.lock"
git -C "$repo" add -A
git -C "$repo" -c user.email=t@t -c user.name=t commit -qm base
git -C "$repo" remote add origin "$remote"
git -C "$repo" push -q -u origin main
remote_before="$(git -C "$remote" rev-parse refs/heads/main)"

# check is READ-ONLY: it must not stage, commit or push anything, even on a
# repository where everything is otherwise in order.
printf 'edit\n' >> "$repo/state/NOW.md"
before="$(git -C "$repo" rev-parse HEAD)"
out="$(cd "$repo" && AI_FLOPPY_HOME="$ROOT" bash .floppy/run check state/NOW.md 2>&1)"; rc1=$?
after="$(git -C "$repo" rev-parse HEAD)"
assert_rc       "check succeeds"               0         "$rc1"
assert_eq       "check does not commit"        "$before" "$after"
assert_eq       "check does not stage"         ""        "$(git -C "$repo" diff --cached --name-only)"
assert_eq       "check does not push"          "$remote_before" "$(git -C "$remote" rev-parse refs/heads/main)"
assert_contains "check reports the file list"  "NOW.md"  "$out"

# IMPORTANT 4: no private_repo in this repo's config — wrap-check.sh must
# skip the "workplace memory" section entirely rather than nudge "bash
# .floppy/run workplace", which then dead-ends on a missing project key.
case "$out" in
  *"-- workplace memory"*) fail "check: no workplace section without private_repo" "section absent" "$out" ;;
  *)                       ok   "check: no workplace section without private_repo" ;;
esac

# check refuses a file outside the watched paths, and refuses loudly
printf 'x\n' > "$repo/stray.txt"
out2="$(cd "$repo" && AI_FLOPPY_HOME="$ROOT" bash .floppy/run check stray.txt 2>&1)"; rc2=$?
assert_rc       "check refuses an unwatched file" 1 "$rc2"

# commit refuses too, when the guard rejects the file list: nothing staged,
# nothing committed, nothing pushed. This is the whole point of re-running
# the gate inside wrap-commit.sh rather than trusting wrap-check.sh's earlier
# pass — a parallel session may have written in between, and an unresolvable
# sibling script must fail loudly here rather than let the commit through
# ungated.
before_gate="$(git -C "$repo" rev-parse HEAD)"
out_gate="$(cd "$repo" && AI_FLOPPY_HOME="$ROOT" bash .floppy/run commit -m "should not land" stray.txt 2>&1)"; rc_gate=$?
after_gate="$(git -C "$repo" rev-parse HEAD)"
assert_rc "commit refuses a file the guard rejects (rc)" 1 "$rc_gate"
assert_eq "gate failure: nothing committed" "$before_gate" "$after_gate"
assert_eq "gate failure: nothing staged"    ""             "$(git -C "$repo" diff --cached --name-only)"
assert_eq "gate failure: nothing pushed"    "$remote_before" "$(git -C "$remote" rev-parse refs/heads/main)"
rm -f "$repo/stray.txt"

# commit does the whole tail, and the remote actually receives it. The rc and
# "moved past base" checks matter as much as the equality: without them this
# assertion would pass just as well if the command failed outright and left
# both sides sitting at the unchanged base commit.
out3="$(cd "$repo" && AI_FLOPPY_HOME="$ROOT" bash .floppy/run commit -m "note update" state/NOW.md 2>&1)"; rc3=$?
after_commit="$(git -C "$repo" rev-parse HEAD)"
assert_rc "commit succeeds"                 0 "$rc3"
case "$after_commit" in
  "$before_gate") fail "commit actually moved HEAD" "a new commit" "$after_commit (unchanged)" ;;
  *)               ok   "commit actually moved HEAD" ;;
esac
assert_eq "remote received the commit" \
  "$after_commit" "$(git -C "$remote" rev-parse refs/heads/main)"

rm -rf "$repo" "$remote"

# ---------- pull comes AFTER the commit, not before ----------
# The measured trap, straight from the script's own header: with no commits
# of its own, `git pull --rebase` on a repository whose working tree already
# holds an uncommitted edit to the very file the incoming fast-forward would
# touch refuses outright — the fast-forward path never reaches
# rebase.autoStash. Reordering "sync" ahead of "stage"/"commit" reproduces
# exactly that shape, so this scenario fails loudly if the order regresses:
# two machines edit different lines of the same file, the other one pushes
# first, and this session's edit is still sitting uncommitted when `commit`
# runs.
remote2="$(cd "$(mktemp -d)" && pwd -P)"; git init -q --bare -b main "$remote2"
repoA="$(sandbox)"; cp shim/run "$repoA/.floppy/run"
cat > "$repoA/.floppy/config" <<'EOF3'
memory_dir=brain
statuses_now=state/NOW.md
statuses_now_chars_max=4000
watched_dirs=state,.floppy
EOF3
mkdir -p "$repoA/brain/half" "$repoA/state"
printf 'line1\nline2\nline3\n' > "$repoA/state/NOW.md"
cat > "$repoA/brain/MEMORY.md" <<'EOF3b'
# Index
- [Half](half/INDEX.md) — pointer
EOF3b
cat > "$repoA/brain/half/INDEX.md" <<'EOF3c'
# Half
- [A note](a-note.md) — pointer
EOF3c
cat > "$repoA/brain/half/a-note.md" <<'EOF3d'
---
name: a-note
description: a note
metadata:
  type: project
  evidence: read
---
Body.
EOF3d
printf 'notes_max=10\nchars_max=100000\nnote_chars_max=10000\npointers_max=40\ngrandfathered=\n' > "$repoA/brain/quota.lock"
git -C "$repoA" add -A
git -C "$repoA" -c user.email=t@t -c user.name=t commit -qm base
git -C "$repoA" remote add origin "$remote2"
git -C "$repoA" push -q -u origin main

# the other machine: a plain clone of the same remote, edits line 1, pushes.
repoB="$(cd "$(mktemp -d)" && pwd -P)"
git clone -q "$remote2" "$repoB"
printf 'line1-from-other-machine\nline2\nline3\n' > "$repoB/state/NOW.md"
git -C "$repoB" -c user.email=o@o -c user.name=o add -A
git -C "$repoB" -c user.email=o@o -c user.name=o commit -qm "other machine edit"
git -C "$repoB" push -q origin main

# this session: repoA is still on the old base (has not fetched), and now
# carries an uncommitted edit to line 3 of the same file — no commit of its
# own yet, exactly the shape the trap needs.
printf 'line1\nline2\nline3-from-this-session\n' > "$repoA/state/NOW.md"

out4="$(cd "$repoA" && AI_FLOPPY_HOME="$ROOT" bash .floppy/run commit -m "this session's edit" state/NOW.md 2>&1)"; rc4=$?
assert_rc "pull-after-commit: commit succeeds despite the remote having diverged" 0 "$rc4"
assert_eq "pull-after-commit: local head reaches the remote" \
  "$(git -C "$repoA" rev-parse HEAD)" "$(git -C "$remote2" rev-parse refs/heads/main)"
final="$(cat "$repoA/state/NOW.md")"
assert_contains "pull-after-commit: the other machine's edit survived" "line1-from-other-machine" "$final"
assert_contains "pull-after-commit: this session's edit survived"      "line3-from-this-session"   "$final"

rm -rf "$repoA" "$repoB" "$remote2"

# ---------- the lock is released on every exit path, not just three of seven ----------
# wrap-commit.sh used to call `unlock` only from the pull/push tail: a
# memory-lint failure, a guard failure, a failed `git add` or a failed
# `git commit` all skipped it, leaving a lock a finished session never
# cleaned up. That gap was invisible while wrap-lock.sh's staleness check was
# broken on macOS (fixed in Task 5a) — every leftover lock read as abandoned
# and the next acquire just took it over. Fixing that check turned a dormant
# leak into a real 30-minute block on every failed gate. Assert on the actual
# `lock status` text, not just on exit code: a test that only checks rc would
# not have caught this.
repoL="$(sandbox)"; cp shim/run "$repoL/.floppy/run"
cat > "$repoL/.floppy/config" <<'EOFLa'
memory_dir=brain
statuses_now=state/NOW.md
statuses_now_chars_max=4000
watched_dirs=state,.floppy
EOFLa
mkdir -p "$repoL/state"
printf '| Notes | 1 | 2 | up |\n' > "$repoL/state/NOW.md"
write_clean_memory "$repoL"
git -C "$repoL" add -A
git -C "$repoL" -c user.email=t@t -c user.name=t commit -qm base

# 1. guard-red path: an unwatched file makes wrap-guard.sh fail.
acqL1="$(cd "$repoL" && AI_FLOPPY_HOME="$ROOT" bash .floppy/run lock acquire "guard-red-test" 2>&1)"
assert_contains "lock-release setup: lock acquired before guard-red run" "ok lock acquired" "$acqL1"

printf 'x\n' > "$repoL/stray.txt"
outL1="$(cd "$repoL" && AI_FLOPPY_HOME="$ROOT" bash .floppy/run commit -m "should fail" stray.txt 2>&1)"; rcL1=$?
assert_rc "guard-red commit fails" 1 "$rcL1"
statusL1="$(cd "$repoL" && AI_FLOPPY_HOME="$ROOT" bash .floppy/run lock status 2>&1)"
assert_contains "guard-red path: lock is free afterwards" "free" "$statusL1"
rm -f "$repoL/stray.txt"

# 2. memory-lint-red path: an index pointer to a note that no longer exists.
rm -f "$repoL/brain/half/a-note.md"
acqL2="$(cd "$repoL" && AI_FLOPPY_HOME="$ROOT" bash .floppy/run lock acquire "lint-red-test" 2>&1)"
assert_contains "lock-release setup: lock acquired before lint-red run" "ok lock acquired" "$acqL2"

outL2="$(cd "$repoL" && AI_FLOPPY_HOME="$ROOT" bash .floppy/run commit -m "should fail" state/NOW.md 2>&1)"; rcL2=$?
assert_rc "memory-lint-red commit fails" 1 "$rcL2"
statusL2="$(cd "$repoL" && AI_FLOPPY_HOME="$ROOT" bash .floppy/run lock status 2>&1)"
assert_contains "memory-lint-red path: lock is free afterwards" "free" "$statusL2"

rm -rf "$repoL"

# 3. the success path still releases exactly once, and still tells the human.
remoteL="$(cd "$(mktemp -d)" && pwd -P)"; git init -q --bare -b main "$remoteL"
repoL2="$(sandbox)"; cp shim/run "$repoL2/.floppy/run"
cat > "$repoL2/.floppy/config" <<'EOFLb'
memory_dir=brain
statuses_now=state/NOW.md
statuses_now_chars_max=4000
watched_dirs=state,.floppy
EOFLb
mkdir -p "$repoL2/state"
printf '| Notes | 1 | 2 | up |\n' > "$repoL2/state/NOW.md"
write_clean_memory "$repoL2"
git -C "$repoL2" add -A
git -C "$repoL2" -c user.email=t@t -c user.name=t commit -qm base
git -C "$repoL2" remote add origin "$remoteL"
git -C "$repoL2" push -q -u origin main

printf 'edit\n' >> "$repoL2/state/NOW.md"
acqL3="$(cd "$repoL2" && AI_FLOPPY_HOME="$ROOT" bash .floppy/run lock acquire "success-test" 2>&1)"
assert_contains "lock-release setup: lock acquired before success run" "ok lock acquired" "$acqL3"

outL3="$(cd "$repoL2" && AI_FLOPPY_HOME="$ROOT" bash .floppy/run commit -m "ok" state/NOW.md 2>&1)"; rcL3=$?
assert_rc "success path commit succeeds" 0 "$rcL3"
n_reports="$(printf '%s\n' "$outL3" | grep -c 'ok lock released')"
assert_eq "success path reports the release exactly once" "1" "$n_reports"
statusL3="$(cd "$repoL2" && AI_FLOPPY_HOME="$ROOT" bash .floppy/run lock status 2>&1)"
assert_contains "success path: lock is free afterwards" "free" "$statusL3"

rm -rf "$repoL2" "$remoteL"

# ---------- MINOR 9: a guard that could not run is not "a parallel session" ----------
# wrap-guard.sh missing entirely used to print the exact same "the file list
# no longer matches the tree... a parallel session may have written" message
# as an actual guard rejection — measured by removing the script. Point
# AI_FLOPPY_HOME at a private copy of the plugin checkout with wrap-guard.sh
# deleted, so the real plugin every other test in this file uses is untouched.
fake_plugin="$(mktemp -d)"
cp -R "$ROOT"/. "$fake_plugin"/ 2>/dev/null
rm -rf "$fake_plugin/.git"
rm -f "$fake_plugin/scripts/wrap-guard.sh"

repoG="$(sandbox)"; cp shim/run "$repoG/.floppy/run"
cat > "$repoG/.floppy/config" <<'EOFG'
memory_dir=brain
statuses_now=state/NOW.md
statuses_now_chars_max=4000
watched_dirs=state,.floppy
EOFG
mkdir -p "$repoG/state"
printf '| Notes | 1 | 2 | up |\n' > "$repoG/state/NOW.md"
write_clean_memory "$repoG"
git -C "$repoG" add -A
git -C "$repoG" -c user.email=t@t -c user.name=t commit -qm base

printf 'edit\n' >> "$repoG/state/NOW.md"
outG="$(cd "$repoG" && AI_FLOPPY_HOME="$fake_plugin" bash .floppy/run commit -m "should fail" state/NOW.md 2>&1)"; rcG=$?
assert_rc       "missing wrap-guard.sh: commit refuses (rc)" 1 "$rcG"
assert_contains "missing wrap-guard.sh: names it as a broken installation" \
  "broken plugin installation" "$outG"
case "$outG" in
  *"a parallel session may have written"*)
    fail "missing wrap-guard.sh: does not blame a parallel session" "no such message" "$outG" ;;
  *) ok "missing wrap-guard.sh: does not blame a parallel session" ;;
esac

rm -rf "$repoG" "$fake_plugin"

# ---------- IMPORTANT 6: commit_push=never skips the sync tail entirely ----------
# Old code ran `git pull --rebase` unconditionally right after every commit,
# so a repository with no remote configured at all failed that step on every
# single call, regardless of --no-push (which only ever skipped the push
# half). commit_push=never in .floppy/config opts a repository like that out
# of the whole pull+push tail. Deliberately no `git remote add` here — this
# is the "no upstream" repository the finding was about.
repoNR="$(sandbox)"; cp shim/run "$repoNR/.floppy/run"
cat > "$repoNR/.floppy/config" <<'EOFNR'
memory_dir=brain
statuses_now=state/NOW.md
statuses_now_chars_max=4000
watched_dirs=state,.floppy
commit_push=never
EOFNR
mkdir -p "$repoNR/state"
printf '| Notes | 1 | 2 | up |\n' > "$repoNR/state/NOW.md"
write_clean_memory "$repoNR"
git -C "$repoNR" add -A
git -C "$repoNR" -c user.email=t@t -c user.name=t commit -qm base

printf 'edit\n' >> "$repoNR/state/NOW.md"
before_nr="$(git -C "$repoNR" rev-parse HEAD)"
outNR="$(cd "$repoNR" && AI_FLOPPY_HOME="$ROOT" bash .floppy/run commit -m "local only" state/NOW.md 2>&1)"; rcNR=$?
after_nr="$(git -C "$repoNR" rev-parse HEAD)"
assert_rc "commit_push=never: commit succeeds with no remote at all" 0 "$rcNR"
case "$after_nr" in
  "$before_nr") fail "commit_push=never: commit actually moved HEAD" "a new commit" "$after_nr (unchanged)" ;;
  *)            ok   "commit_push=never: commit actually moved HEAD" ;;
esac
assert_contains "commit_push=never: says it is staying local" "staying local" "$outNR"

rm -rf "$repoNR"

# ---------- commit names repo/branch/push before any gate runs ----------
# `commit` is the dangerous verb: it stages, commits, and pushes. The naming
# has to survive a gate rejection — a gate that refuses for an unrelated
# reason (here, a file outside the watched paths) must not swallow it, or a
# human reading only the failure learns nothing about which repository it was
# about to touch. Assert on ORDER, not just presence: the "-- target" section
# must come before "-- gates" in the actual output.
repoT="$(sandbox)"; cp shim/run "$repoT/.floppy/run"
cat > "$repoT/.floppy/config" <<'EOFT'
memory_dir=brain
statuses_now=state/NOW.md
statuses_now_chars_max=4000
watched_dirs=state,.floppy
EOFT
mkdir -p "$repoT/state"
printf '| Notes | 1 | 2 | up |\n' > "$repoT/state/NOW.md"
write_clean_memory "$repoT"
git -C "$repoT" add -A
git -C "$repoT" -c user.email=t@t -c user.name=t commit -qm base

printf 'x\n' > "$repoT/stray.txt"
outT="$(cd "$repoT" && AI_FLOPPY_HOME="$ROOT" bash .floppy/run commit -m "should fail" stray.txt 2>&1)"; rcT=$?
assert_rc       "target-naming: the gate still rejects the commit (rc)" 1 "$rcT"
assert_contains "target-naming: names the resolved repository" "repo:   $repoT" "$outT"
assert_contains "target-naming: names the branch"               "branch: main" "$outT"
assert_contains "target-naming: names the push target (no remote configured)" \
  "push:   no upstream configured" "$outT"

target_line=$(printf '%s\n' "$outT" | grep -n '^-- target$' | head -1 | cut -d: -f1)
gates_line=$(printf '%s\n' "$outT" | grep -n '^-- gates$' | head -1 | cut -d: -f1)
if [[ -n "${target_line:-}" && -n "${gates_line:-}" && "$target_line" -lt "$gates_line" ]]; then
  ok "target-naming: appears before the gates section, not after"
else
  fail "target-naming: appears before the gates section, not after" \
    "target line before gates line" "target=${target_line:-missing} gates=${gates_line:-missing}"
fi

rm -f "$repoT/stray.txt"
rm -rf "$repoT"

summary
