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
summary
