#!/usr/bin/env bash
set -uo pipefail
cd "$(dirname "$0")/.."
. tests/lib.sh
ROOT="$(pwd)"

# memory in a non-default directory, to catch any surviving ".agent-memory"
repo="$(sandbox)"; cp shim/run "$repo/.floppy/run"
echo "memory_dir=brain" > "$repo/.floppy/config"
mkdir -p "$repo/brain/half"
cat > "$repo/brain/MEMORY.md" <<'EOF'
# Index
- [Half](half/INDEX.md) — pointer
EOF
cat > "$repo/brain/half/INDEX.md" <<'EOF'
# Half
- [A note](a-note.md) — pointer
EOF
cat > "$repo/brain/half/a-note.md" <<'EOF'
---
name: a-note
description: a note
metadata:
  type: project
  evidence: read
---
Body.
EOF
printf 'notes_max=10\nchars_max=100000\nnote_chars_max=10000\npointers_max=40\ngrandfathered=\n' > "$repo/brain/quota.lock"

out="$(cd "$repo" && AI_FLOPPY_HOME="$ROOT" bash .floppy/run lint 2>&1)"; rc=$?
assert_rc       "clean memory in a custom dir passes" 0 "$rc"
assert_contains "counts are reported"                 "1 notes"     "$out"
case "$out" in *".agent-memory"*) fail "no hardcoded .agent-memory" "absent" "$out";; *) ok "no hardcoded .agent-memory";; esac

# positive control: a note nobody points at must be caught
cp "$repo/brain/half/a-note.md" "$repo/brain/half/orphan.md"
sed -i.bak 's/^name: a-note/name: orphan/' "$repo/brain/half/orphan.md" && rm -f "$repo/brain/half/orphan.md.bak"
out2="$(cd "$repo" && AI_FLOPPY_HOME="$ROOT" bash .floppy/run lint 2>&1)"; rc2=$?
assert_rc       "orphan note fails the run"  1 "$rc2"
assert_contains "orphan note is named"       "orphan.md" "$out2"

rm -rf "$repo"

# ---------- three-level index tree ----------
# The index became a three-level tree on 2026-08-25 (root -> half -> sub-index
# -> note), after sdk/ hit the 60-pointer cap and the ratchet said to split the
# half rather than raise the number. A clean tree at that depth must pass.
repo3="$(sandbox)"; cp shim/run "$repo3/.floppy/run"
echo "memory_dir=brain" > "$repo3/.floppy/config"
mkdir -p "$repo3/brain/half/sub"
cat > "$repo3/brain/MEMORY.md" <<'EOF'
# Index
- [Half](half/INDEX.md) — pointer
EOF
cat > "$repo3/brain/half/INDEX.md" <<'EOF'
# Half
- [Sub](sub/INDEX.md) — pointer
EOF
cat > "$repo3/brain/half/sub/INDEX.md" <<'EOF'
# Sub
- [A note](note.md) — pointer
EOF
cat > "$repo3/brain/half/sub/note.md" <<'EOF'
---
name: note
description: a note three levels deep
metadata:
  type: project
  evidence: read
---
Body.
EOF
printf 'chars_max=100000\nnote_chars_max=10000\npointers_max=40\ngrandfathered=\n' > "$repo3/brain/quota.lock"

out3="$(cd "$repo3" && AI_FLOPPY_HOME="$ROOT" bash .floppy/run lint 2>&1)"; rc3=$?
assert_rc       "three-level tree passes clean"  0 "$rc3"
assert_contains "three indexes are counted"       "3 indexes" "$out3"

# ---------- orphan sub-index ----------
# A sub-index that its own half never links to used to pass silently: the old
# port only checked each half index against the root MEMORY.md, never against
# its immediate parent. Add a sibling under half/ with its own INDEX.md and
# never link it from half/INDEX.md.
mkdir -p "$repo3/brain/half/orphan-sub"
cat > "$repo3/brain/half/orphan-sub/INDEX.md" <<'EOF'
# Orphan
- [Ghost](ghost.md) — pointer
EOF
cat > "$repo3/brain/half/orphan-sub/ghost.md" <<'EOF'
---
name: ghost
description: a note under an unreachable sub-index
metadata:
  type: project
  evidence: read
---
Body.
EOF

out4="$(cd "$repo3" && AI_FLOPPY_HOME="$ROOT" bash .floppy/run lint 2>&1)"; rc4=$?
assert_rc       "orphan sub-index fails the run"        1 "$rc4"
assert_contains "orphan sub-index is named"              "half/orphan-sub/INDEX.md" "$out4"
assert_contains "orphan sub-index names its own parent"  "not linked from half/INDEX.md" "$out4"

rm -rf "$repo3"

# ---------- note nested past three levels ----------
repo5="$(sandbox)"; cp shim/run "$repo5/.floppy/run"
echo "memory_dir=brain" > "$repo5/.floppy/config"
mkdir -p "$repo5/brain/half/sub/toodeep"
cat > "$repo5/brain/MEMORY.md" <<'EOF'
# Index
- [Half](half/INDEX.md) — pointer
EOF
cat > "$repo5/brain/half/INDEX.md" <<'EOF'
# Half
- [Sub](sub/INDEX.md) — pointer
EOF
cat > "$repo5/brain/half/sub/INDEX.md" <<'EOF'
# Sub
- [A note](note.md) — pointer
EOF
cat > "$repo5/brain/half/sub/note.md" <<'EOF'
---
name: note
description: a note three levels deep
metadata:
  type: project
  evidence: read
---
Body.
EOF
cat > "$repo5/brain/half/sub/toodeep/deep-note.md" <<'EOF'
---
name: deep-note
description: a note nested one level too deep
metadata:
  type: project
  evidence: read
---
Body.
EOF
printf 'chars_max=100000\nnote_chars_max=10000\npointers_max=40\ngrandfathered=\n' > "$repo5/brain/quota.lock"

out5="$(cd "$repo5" && AI_FLOPPY_HOME="$ROOT" bash .floppy/run lint 2>&1)"; rc5=$?
assert_rc       "note past three levels fails the run" 1 "$rc5"
assert_contains "deep note is named"                    "half/sub/toodeep/deep-note.md" "$out5"
assert_contains "depth-limit message"                   "index tree stops at three levels" "$out5"

rm -rf "$repo5"

# ---------- non-numeric quota value ----------
# Previously an unguarded non-numeric value in quota.lock printed its own
# message but also let later comparisons run on the bad value, spilling raw
# bash diagnostics ahead of it. The current script validates before using.
repo6="$(sandbox)"; cp shim/run "$repo6/.floppy/run"
echo "memory_dir=brain" > "$repo6/.floppy/config"
mkdir -p "$repo6/brain/half"
cat > "$repo6/brain/MEMORY.md" <<'EOF'
# Index
- [Half](half/INDEX.md) — pointer
EOF
cat > "$repo6/brain/half/INDEX.md" <<'EOF'
# Half
- [A note](note.md) — pointer
EOF
cat > "$repo6/brain/half/note.md" <<'EOF'
---
name: note
description: a note
metadata:
  type: project
  evidence: read
---
Body.
EOF
printf 'chars_max=abc\nnote_chars_max=10000\npointers_max=40\ngrandfathered=\n' > "$repo6/brain/quota.lock"

out6="$(cd "$repo6" && AI_FLOPPY_HOME="$ROOT" bash .floppy/run lint 2>&1)"; rc6=$?
assert_rc       "non-numeric quota value fails the run" 1 "$rc6"
assert_contains "non-numeric value is named"             "chars_max is 'abc'" "$out6"
case "$out6" in
  *"operand expected"*|*": line "*) fail "no raw bash noise ahead of the message" "absent" "$out6" ;;
  *) ok "no raw bash noise ahead of the message" ;;
esac

rm -rf "$repo6"

# ---------- "does not use this memory layout" names the path ----------
# This is exactly the message a human gets when the wrong project is active
# in a harness that can have several open at once (Cursor especially). In its
# old form it read as "your setup is broken"; naming the repository turns it
# into "you are in the wrong place".
repo7="$(sandbox)"; cp shim/run "$repo7/.floppy/run"
out7="$(cd "$repo7" && AI_FLOPPY_HOME="$ROOT" bash .floppy/run lint 2>&1)"; rc7=$?
assert_rc       "no memory layout: exits 2"                    2 "$rc7"
assert_contains "no memory layout: message names the repository path" "$repo7" "$out7"
assert_contains "no memory layout: still explains what's missing" \
  "this repository does not use this memory layout" "$out7"
rm -rf "$repo7"

# ---------- the size caps come from two places, on purpose ----------
# index_chars_max is a fact about the harness's session loader — the same for
# every project running in it — so it lives in .floppy/config. pointer_line_max
# is a fact about this corpus's writing convention, like pointers_max beside
# it, so it lives in quota.lock. Merging them into one file would make every
# project re-measure somebody else's tool.
repo8="$(sandbox)"; cp shim/run "$repo8/.floppy/run"
echo "memory_dir=brain" > "$repo8/.floppy/config"
mkdir -p "$repo8/brain/half"
cat > "$repo8/brain/half/a-note.md" <<'EOFN'
---
name: a-note
description: a note
metadata:
  type: project
  evidence: read
---
Body.
EOFN
printf '# Half\n- [A note](a-note.md) — pointer\n' > "$repo8/brain/half/INDEX.md"
# A pointer line of 200 ASCII characters: over the 170 default, under a raised cap.
long_line="- [x](half/INDEX.md) $(printf 'y%.0s' $(seq 1 179))"
printf '# Index\n%s\n' "$long_line" > "$repo8/brain/MEMORY.md"

lint8() { OUT8="$(cd "$repo8" && AI_FLOPPY_HOME="$ROOT" bash .floppy/run lint 2>&1)"; RC8=$?; }

lint8
assert_rc       "default pointer_line_max catches a long line" 1 "$RC8"
assert_contains "and says how long it is"  "over 170" "$OUT8"

# Raised in quota.lock — the same line must now pass. Without this the check
# above would also pass on a linter that simply never read the file.
printf 'chars_max=100000\nnote_chars_max=10000\npointers_max=40\npointer_line_max=250\ngrandfathered=\n' > "$repo8/brain/quota.lock"
lint8
assert_rc       "pointer_line_max from quota.lock is honoured" 0 "$RC8"

printf 'chars_max=100000\nnote_chars_max=10000\npointers_max=40\npointer_line_max=nope\ngrandfathered=\n' > "$repo8/brain/quota.lock"
lint8
assert_contains "a non-numeric pointer_line_max is named, not silently used" "pointer_line_max is 'nope'" "$OUT8"
printf 'chars_max=100000\nnote_chars_max=10000\npointers_max=40\ngrandfathered=\n' > "$repo8/brain/quota.lock"

# index_chars_max from .floppy/config. A tiny cap must fail the index; the
# warning threshold is derived from it rather than being a second key.
printf 'memory_dir=brain\nindex_chars_max=50\n' > "$repo8/.floppy/config"
lint8
assert_rc       "index_chars_max from the config is honoured" 1 "$RC8"
assert_contains "and the message quotes the configured cap" "over the 50 cap" "$OUT8"

printf 'memory_dir=brain\nindex_chars_max=oops\n' > "$repo8/.floppy/config"
lint8
assert_contains "a non-numeric index_chars_max is named" "index_chars_max is 'oops'" "$OUT8"
assert_contains "and it falls back to the shipped default" "24500" "$OUT8"
rm -rf "$repo8"


summary
