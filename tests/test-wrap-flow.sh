#!/usr/bin/env bash
set -uo pipefail
cd "$(dirname "$0")/.."
. tests/lib.sh
ROOT="$(pwd)"

# A bare repository stands in for the remote. Never a real one: this script
# pushes, and a test that reaches a real remote is a test that publishes.
remote="$(cd "$(mktemp -d)" && pwd -P)"; git init -q --bare "$remote"
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
out="$(cd "$repo" && AI_FLOPPY_HOME="$ROOT" bash .floppy/run check state/NOW.md 2>&1)"
after="$(git -C "$repo" rev-parse HEAD)"
assert_eq       "check does not commit"        "$before" "$after"
assert_eq       "check does not stage"         ""        "$(git -C "$repo" diff --cached --name-only)"
assert_eq       "check does not push"          "$remote_before" "$(git -C "$remote" rev-parse refs/heads/main)"
assert_contains "check reports the file list"  "NOW.md"  "$out"

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
remote2="$(cd "$(mktemp -d)" && pwd -P)"; git init -q --bare "$remote2"
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
summary
