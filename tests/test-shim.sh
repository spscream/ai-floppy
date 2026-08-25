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

# a missing plugin must fail loudly, not silently. HOME is pointed at an
# empty directory so this does not depend on whether the real machine happens
# to have a floppy plugin cached (it does, on this one).
empty_home="$(mktemp -d)"
out3="$(cd "$repo2" && HOME="$empty_home" AI_FLOPPY_HOME=/nonexistent CLAUDE_PLUGIN_ROOT= bash .floppy/run lint 2>&1)"; rc3=$?
assert_rc       "missing plugin exits nonzero" 1 "$rc3"
assert_contains "missing plugin names the fix" "plugin install floppy" "$out3"
rm -rf "$empty_home"

# finding 1: an explicitly empty value must not fall back to the default.
# workplace_repo's own default is already '', which would not distinguish the
# bug from the fix, so this uses memory_dir (default .agent-memory) instead.
repo4="$(sandbox)"; cp shim/run "$repo4/.floppy/run"
printf 'memory_dir=\n' > "$repo4/.floppy/config"
out4="$(cd "$repo4" && AI_FLOPPY_HOME="$ROOT" bash .floppy/run env 2>&1 | sed -n 's/^FLOPPY_MEMORY_DIR=//p')"
assert_eq "explicit empty value stays empty, not the default" "" "$out4"

# finding 2a: spaces around "=" must still be recognized as the key.
repo5="$(sandbox)"; cp shim/run "$repo5/.floppy/run"
printf 'memory_dir = brain\n' > "$repo5/.floppy/config"
out5="$(cd "$repo5" && AI_FLOPPY_HOME="$ROOT" bash .floppy/run env 2>&1)"
assert_contains "key with spaces around '=' is read, not defaulted" "FLOPPY_MEMORY_DIR=brain" "$out5"

# finding 2b: trailing whitespace in the value must be trimmed, not exported
# verbatim into a path five later tasks read. Exact match, not substring.
repo6="$(sandbox)"; cp shim/run "$repo6/.floppy/run"
printf 'memory_dir=brain \n' > "$repo6/.floppy/config"
out6="$(cd "$repo6" && AI_FLOPPY_HOME="$ROOT" bash .floppy/run env 2>&1 | sed -n 's/^FLOPPY_MEMORY_DIR=//p')"
assert_eq "trailing space in config value is trimmed" "brain" "$out6"

# finding 3: the plugin-cache fallback must pick the newest version, and
# lexicographic sort gets that wrong once a double-digit version exists
# (0.10.0 sorts before 0.9.0). Build a fake cache under a fake HOME, with a
# scripts/ dir in each version so the existence guard is satisfied either way.
repo7="$(sandbox)"; cp shim/run "$repo7/.floppy/run"
fake_home="$(mktemp -d)"
mkdir -p "$fake_home/.claude/plugins/cache/example/floppy/0.9.0/scripts"
mkdir -p "$fake_home/.claude/plugins/cache/example/floppy/0.10.0/scripts"
out7="$(cd "$repo7" && HOME="$fake_home" AI_FLOPPY_HOME= CLAUDE_PLUGIN_ROOT= bash .floppy/run env 2>&1)"
assert_contains "cache fallback picks 0.10.0, not lexicographically-later 0.9.0" \
  "FLOPPY_ROOT=$fake_home/.claude/plugins/cache/example/floppy/0.10.0" "$out7"
rm -rf "$fake_home"

# MINOR 8: a run outside any git repository must fail loudly, not silently
# fall back to `pwd` and derive every downstream path from the wrong place.
# Discriminates against the old code: `FLOPPY_REPO="$(git rev-parse
# --show-toplevel 2>/dev/null || pwd)"` never fails, so the old shim would
# print FLOPPY_REPO=<the plain dir> here with rc 0 instead of refusing.
plain="$(mktemp -d)"; mkdir -p "$plain/.floppy"; cp shim/run "$plain/.floppy/run"
out8="$(cd "$plain" && AI_FLOPPY_HOME="$ROOT" bash .floppy/run env 2>&1)"; rc8=$?
assert_rc       "outside a git repo: exits nonzero"      1 "$rc8"
assert_contains "outside a git repo: names the problem"  "not inside a git repository" "$out8"
case "$out8" in
  *"FLOPPY_REPO="*) fail "outside a git repo: does not fall back to pwd" "no FLOPPY_REPO= line" "$out8" ;;
  *) ok "outside a git repo: does not fall back to pwd" ;;
esac
rm -rf "$plain"

rm -rf "$repo" "$repo2" "$repo4" "$repo5" "$repo6" "$repo7"
summary
