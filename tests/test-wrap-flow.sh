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

# ---------- a file this session deleted with `git rm` ----------
# Reported from a second session. `git rm` stages the deletion, so the path is
# in neither the worktree nor the index; `git add -- <that path>` then fails
# with "did not match any files" and takes the whole commit down. Measured on
# this machine's git: `git add -A -- <path>` fails identically, so widening the
# add is not the fix. A deletion staged by `git rm` needs no staging at all.
repoD="$(sandbox)"; cp shim/run "$repoD/.floppy/run"
cat > "$repoD/.floppy/config" <<'EOFD'
memory_dir=brain
statuses_now=state/NOW.md
statuses_now_chars_max=4000
watched_dirs=state,.floppy
commit_push=never
EOFD
mkdir -p "$repoD/state"
printf '| Notes | 1 | 2 | up |\n' > "$repoD/state/NOW.md"
printf 'superseded by a later measurement\n' > "$repoD/state/OLD.md"
write_clean_memory "$repoD"
git -C "$repoD" add -A
git -C "$repoD" -c user.email=t@t -c user.name=t commit -qm base

git -C "$repoD" rm -q state/OLD.md
outD="$(cd "$repoD" && AI_FLOPPY_HOME="$ROOT" bash .floppy/run commit -m "drop the superseded note" state/OLD.md 2>&1)"; rcD=$?
assert_rc       "git rm: the commit goes through (rc)"  0 "$rcD"
case "$outD" in
  *"git add failed"*) fail "git rm: staging does not fail on the deleted path" "no add failure" "$outD" ;;
  *)                  ok   "git rm: staging does not fail on the deleted path" ;;
esac
assert_eq       "git rm: the deletion is gone from HEAD's tree" "" \
  "$(git -C "$repoD" ls-tree -r --name-only HEAD -- state/OLD.md)"
assert_contains "git rm: and it is this session's commit that did it" \
  "drop the superseded note" "$(git -C "$repoD" log -1 --format=%s)"
assert_eq       "git rm: nothing left uncommitted"           "" \
  "$(git -C "$repoD" status --porcelain)"

# A path that never existed must still fail — the skip is for a staged
# deletion, not a blanket "ignore what git cannot find".
printf 'x\n' > "$repoD/state/NEW.md"
outD2="$(cd "$repoD" && AI_FLOPPY_HOME="$ROOT" bash .floppy/run commit -m "typo in the list" state/NEW.md state/nosuch.md 2>&1)"; rcD2=$?
assert_rc       "git rm: a typo in the file list still fails (rc)" 1 "$rcD2"
rm -rf "$repoD"

# ---------- a branch the remote has never seen ----------
# Measured while closing the session that protected `main` (#17). `commit`
# ended with `pull --rebase` then `push`; on a branch with no upstream the
# pull has nothing to rebase against, fails with "no tracking information",
# and takes the whole tail down. It used to be an edge case because wrap ran
# on `main`, which has an upstream. With `main` protected, every wrap runs on
# a branch created for it, and such a branch never has an upstream on its
# first commit — so this is now every close, not an occasional one.
remoteB="$(cd "$(mktemp -d)" && pwd -P)"; git init -q --bare -b main "$remoteB"
repoB="$(sandbox)"; cp shim/run "$repoB/.floppy/run"
cat > "$repoB/.floppy/config" <<'EOFB'
memory_dir=brain
statuses_now=state/NOW.md
statuses_now_chars_max=4000
watched_dirs=state,.floppy
EOFB
mkdir -p "$repoB/state"
printf '| Notes | 1 | 2 | up |\n' > "$repoB/state/NOW.md"
write_clean_memory "$repoB"
git -C "$repoB" add -A
git -C "$repoB" -c user.email=t@t -c user.name=t commit -qm base
git -C "$repoB" remote add origin "$remoteB"
git -C "$repoB" push -q -u origin main

# the wrap branch: created here, unknown to the remote, no upstream
git -C "$repoB" switch -q -c wrap-branch
printf 'edit\n' >> "$repoB/state/NOW.md"
outB="$(cd "$repoB" && AI_FLOPPY_HOME="$ROOT" bash .floppy/run commit -m "close on a fresh branch" state/NOW.md 2>&1)"; rcB=$?
assert_rc       "fresh branch: the whole tail succeeds (rc)" 0 "$rcB"
assert_eq       "fresh branch: the remote received it" \
  "$(git -C "$repoB" rev-parse HEAD)" "$(git -C "$remoteB" rev-parse refs/heads/wrap-branch 2>/dev/null)"
assert_eq       "fresh branch: and the upstream is now set" "origin/wrap-branch" \
  "$(git -C "$repoB" rev-parse --abbrev-ref --symbolic-full-name '@{upstream}' 2>/dev/null)"
# The pull is skipped, not merely survived: there is nothing to rebase
# against, and attempting it is what produced the failure in the first place.
case "$outB" in
  *"pull --rebase failed"*) fail "fresh branch: the pull is not attempted" "no pull failure" "$outB" ;;
  *)                        ok   "fresh branch: the pull is not attempted" ;;
esac

# Where an upstream does exist the behaviour must not change: the
# pull-before-push there is what guards the two-machine case, and this fix
# must not be a way of skipping it. Second commit on the same branch — the
# upstream is set now, so the pull runs again.
printf 'more\n' >> "$repoB/state/NOW.md"
outB2="$(cd "$repoB" && AI_FLOPPY_HOME="$ROOT" bash .floppy/run commit -m "second close" state/NOW.md 2>&1)"; rcB2=$?
assert_rc       "upstream exists: still succeeds (rc)" 0 "$rcB2"
assert_eq       "upstream exists: the remote received it too" \
  "$(git -C "$repoB" rev-parse HEAD)" "$(git -C "$remoteB" rev-parse refs/heads/wrap-branch 2>/dev/null)"
case "$outB2" in
  *"no upstream yet"*) fail "upstream exists: does not take the first-push path" "no such message" "$outB2" ;;
  *)                   ok   "upstream exists: does not take the first-push path" ;;
esac

rm -rf "$repoB" "$remoteB"

# ---------- a push refused by a branch rule ----------
# The other half of #17. On a repository whose default branch is protected the
# push comes back with GH013, which is not a network problem and not something
# a retry fixes — the commit has to move to a branch and arrive as a pull
# request. `commit` used to print "push failed (network/VPN?)  Retry: git
# push", which is advice that cannot work. A pre-receive hook stands in for
# the branch rule: this test must never reach a real remote.
remoteP="$(cd "$(mktemp -d)" && pwd -P)"; git init -q --bare -b main "$remoteP"
repoP="$(sandbox)"; cp shim/run "$repoP/.floppy/run"
cat > "$repoP/.floppy/config" <<'EOFP'
memory_dir=brain
statuses_now=state/NOW.md
statuses_now_chars_max=4000
watched_dirs=state,.floppy
EOFP
mkdir -p "$repoP/state"
printf '| Notes | 1 | 2 | up |\n' > "$repoP/state/NOW.md"
write_clean_memory "$repoP"
git -C "$repoP" add -A
git -C "$repoP" -c user.email=t@t -c user.name=t commit -qm base
git -C "$repoP" remote add origin "$remoteP"
git -C "$repoP" push -q -u origin main
cat > "$remoteP/hooks/pre-receive" <<'EOFPH'
#!/bin/sh
echo "GH013: Repository rule violations found for refs/heads/main." >&2
exit 1
EOFPH
chmod +x "$remoteP/hooks/pre-receive"

printf 'edit\n' >> "$repoP/state/NOW.md"
outP="$(cd "$repoP" && AI_FLOPPY_HOME="$ROOT" bash .floppy/run commit -m "refused by the rule" state/NOW.md 2>&1)"; rcP=$?
assert_rc       "branch rule: the call still fails (rc)" 1 "$rcP"
assert_contains "branch rule: names the rule, not the network" "branch rule" "$outP"
assert_contains "branch rule: names the branch that is protected" "main is protected" "$outP"
assert_contains "branch rule: says the commit is safe" "safe locally" "$outP"
assert_contains "branch rule: gives the branch recipe" "git switch -c" "$outP"
assert_contains "branch rule: and the pull request that follows it" "gh pr create" "$outP"
# The commit itself must still be there: the push is what failed.
assert_contains "branch rule: the commit was made" "refused by the rule" \
  "$(git -C "$repoP" log -1 --format=%s)"
case "$outP" in
  *"network/VPN"*) fail "branch rule: does not blame the network" "no network message" "$outP" ;;
  *)               ok   "branch rule: does not blame the network" ;;
esac

# An ordinary push failure must still read as one: with the hook rejecting
# without a rule-violation message, the generic advice is the correct advice.
cat > "$remoteP/hooks/pre-receive" <<'EOFPH2'
#!/bin/sh
echo "fatal: the remote end hung up unexpectedly" >&2
exit 1
EOFPH2
chmod +x "$remoteP/hooks/pre-receive"
printf 'again\n' >> "$repoP/state/NOW.md"
outP2="$(cd "$repoP" && AI_FLOPPY_HOME="$ROOT" bash .floppy/run commit -m "refused for another reason" state/NOW.md 2>&1)"; rcP2=$?
assert_rc       "ordinary push failure: still fails (rc)" 1 "$rcP2"
assert_contains "ordinary push failure: keeps the generic advice" "Retry: git push" "$outP2"
case "$outP2" in
  *"gh pr create"*) fail "ordinary push failure: no branch-rule recipe" "no PR recipe" "$outP2" ;;
  *)                ok   "ordinary push failure: no branch-rule recipe" ;;
esac

rm -rf "$repoP" "$remoteP"

# ---------- the linter refusing to run is not "0 problems" ----------
# memory-lint.sh exits 2 when it cannot check anything at all: the memory
# layout is absent, or the configured scope name is unusable. wrap-check.sh
# mapped every non-zero code to its problem-counting branch, and since a
# refusal prints no "  x" lines the human got "MEMORY LINT IS RED, 0
# problem(s)" and nothing else — red with no reason given.
repoR="$(sandbox)"; cp shim/run "$repoR/.floppy/run"
cat > "$repoR/.floppy/config" <<'EOFR'
memory_dir=brain
statuses_now=state/NOW.md
watched_dirs=state,.floppy
EOFR
mkdir -p "$repoR/state"
printf '| Notes | 1 | 2 | up |\n' > "$repoR/state/NOW.md"
git -C "$repoR" add -A
git -C "$repoR" -c user.email=t@t -c user.name=t commit -qm base
printf '| Notes | 1 | 3 | up |\n' > "$repoR/state/NOW.md"

outR="$(cd "$repoR" && AI_FLOPPY_HOME="$ROOT" bash .floppy/run check state/NOW.md 2>&1)"; rcR=$?
assert_rc       "lint refusal: check is still red (rc)" 1 "$rcR"
assert_contains "lint refusal: the linter's own reason is shown" \
  "does not use this memory layout" "$outR"
case "$outR" in
  *"0 problem(s)"*) fail "lint refusal: not reported as zero problems" "no '0 problem(s)'" "$outR" ;;
  *)                ok   "lint refusal: not reported as zero problems" ;;
esac
rm -rf "$repoR"

summary
