#!/usr/bin/env bash
set -uo pipefail
cd "$(dirname "$0")/.."
. tests/lib.sh
ROOT="$(pwd)"

repo="$(sandbox)"
cp shim/run "$repo/.floppy/run"
cat > "$repo/.floppy/config" <<'EOF'
memory_dir=brain
memory_language=en
statuses_now_chars_max=9000
watched_dirs=docs,.floppy
EOF

out="$(cd "$repo" && AI_FLOPPY_HOME="$ROOT" bash .floppy/run env 2>&1)"
assert_contains "memory_dir read from config"      "FLOPPY_MEMORY_DIR=brain"        "$out"
assert_contains "default applied when key absent"  "FLOPPY_WORKPLACE_PROJECT_KEY="  "$out"
assert_contains "repo root resolved"               "FLOPPY_REPO=$repo"              "$out"
assert_contains "numeric key passes through"       "FLOPPY_STATUSES_NOW_CHARS_MAX=9000" "$out"

# default when there is no config at all
repo2="$(sandbox)"; cp shim/run "$repo2/.floppy/run"
out2="$(cd "$repo2" && AI_FLOPPY_HOME="$ROOT" bash .floppy/run env 2>&1)"
assert_contains "memory_dir defaults" "FLOPPY_MEMORY_DIR=.agent-memory" "$out2"

# a missing plugin must fail loudly, not silently
out3="$(cd "$repo2" && AI_FLOPPY_HOME=/nonexistent CLAUDE_PLUGIN_ROOT= bash .floppy/run lint 2>&1)"; rc3=$?
assert_rc       "missing plugin exits nonzero" 1 "$rc3"
assert_contains "missing plugin names the fix" "plugin install floppy" "$out3"

rm -rf "$repo" "$repo2"
summary
