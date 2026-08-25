#!/usr/bin/env bash
set -uo pipefail
cd "$(dirname "$0")/.."
. tests/lib.sh
ROOT="$(pwd)"

md5_of() { md5 -q "$1" 2>/dev/null || md5sum "$1" | awk '{print $1}'; }

# ---------- fresh repository, default memory dir ----------
repo="$(sandbox)"
rmdir "$repo/.floppy" 2>/dev/null || true   # sandbox() pre-creates .floppy/; init.sh must not depend on that

bash scripts/init.sh --repo "$repo" --memory-dir .agent-memory --language en >/dev/null

assert_eq "shim placed"    "0" "$([[ -f "$repo/.floppy/run" ]] && echo 0 || echo 1)"
assert_eq "config placed"  "0" "$([[ -f "$repo/.floppy/config" ]] && echo 0 || echo 1)"
assert_eq "router placed"  "0" "$([[ -f "$repo/.agent-memory/MEMORY.md" ]] && echo 0 || echo 1)"
assert_eq "no quota.lock"  "1" "$([[ -f "$repo/.agent-memory/quota.lock" ]] && echo 0 || echo 1)"

assert_contains "config carries memory_dir"      "memory_dir=.agent-memory" "$(cat "$repo/.floppy/config")"
assert_contains "config carries memory_language" "memory_language=en"      "$(cat "$repo/.floppy/config")"
live_workplace_line="$(grep -v '^[[:space:]]*#' "$repo/.floppy/config" | grep '^workplace_repo=' || true)"
assert_eq "workplace_repo not given a live default (uncommented)" "" "$live_workplace_line"

assert_contains "gitignore has local without a trailing slash" "/.agent-memory/local" "$(cat "$repo/.gitignore")"
case "$(cat "$repo/.gitignore")" in
  *"/.agent-memory/local/"*) fail "gitignore line has no trailing slash" "absent" "with slash" ;;
  *) ok "gitignore line has no trailing slash" ;;
esac
# exact-line assertion: a substring check would pass whether or not the slash is there
gi_line="$(grep -x '/.agent-memory/local' "$repo/.gitignore")"
assert_eq "gitignore line matches exactly" "/.agent-memory/local" "$gi_line"

assert_contains "AGENTS.md names .floppy/"             ".floppy/"            "$(cat "$repo/AGENTS.md")"
assert_contains "AGENTS.md points at agent-memory"     "floppy:agent-memory" "$(cat "$repo/AGENTS.md")"

out="$(cd "$repo" && AI_FLOPPY_HOME="$ROOT" bash .floppy/run lint 2>&1)"; rc=$?
assert_rc       "lint is green on empty memory"        0 "$rc"
assert_contains "missing ratchet warns, not fails"      "quota.lock" "$out"
case "$out" in
  *"! quota.lock"*) ok "missing ratchet is a warning line, not an x error" ;;
  *) fail "missing ratchet is a warning line, not an x error" "! quota.lock is missing..." "$out" ;;
esac

# ---------- idempotence: full status + checksums of every touched file ----------
touched="$repo/.floppy/run $repo/.floppy/config $repo/.agent-memory/MEMORY.md $repo/.gitignore $repo/AGENTS.md"
before_status="$(cd "$repo" && git status --porcelain)"
before_sums=""
for f in $touched; do before_sums="$before_sums$(md5_of "$f")"; done

bash scripts/init.sh --repo "$repo" --memory-dir .agent-memory --language en >/dev/null

after_status="$(cd "$repo" && git status --porcelain)"
after_sums=""
for f in $touched; do after_sums="$after_sums$(md5_of "$f")"; done

assert_eq "second run: git status unchanged" "$before_status" "$after_status"
assert_eq "second run: checksums of touched files unchanged" "$before_sums" "$after_sums"

rm -rf "$repo"

# ---------- existing AGENTS.md with content: no duplication, no destruction ----------
repo2="$(sandbox)"
rmdir "$repo2/.floppy" 2>/dev/null || true
cat > "$repo2/AGENTS.md" <<'EOF'
# AGENTS.md

This repository has its own conventions before floppy ever touched it.

## Existing section

Do not delete this. It predates the plugin.
EOF

bash scripts/init.sh --repo "$repo2" --memory-dir .agent-memory --language en >/dev/null
bash scripts/init.sh --repo "$repo2" --memory-dir .agent-memory --language en >/dev/null

content="$(cat "$repo2/AGENTS.md")"
assert_contains "pre-existing heading survives"   "This repository has its own conventions" "$content"
assert_contains "pre-existing section survives"   "Do not delete this. It predates the plugin." "$content"

marker_count="$(grep -c 'floppy:agents-section' "$repo2/AGENTS.md" 2>/dev/null || true)"
[[ -z "$marker_count" ]] && marker_count=0
assert_eq "floppy section appended exactly once, not duplicated" "1" "$marker_count"

rm -rf "$repo2"

# ---------- non-default memory directory, end to end ----------
repo3="$(sandbox)"
rmdir "$repo3/.floppy" 2>/dev/null || true

bash scripts/init.sh --repo "$repo3" --memory-dir brain --language ru >/dev/null

assert_eq "custom dir: router placed"  "0" "$([[ -f "$repo3/brain/MEMORY.md" ]] && echo 0 || echo 1)"
assert_eq "custom dir: no default dir" "1" "$([[ -e "$repo3/.agent-memory" ]] && echo 0 || echo 1)"
assert_contains "custom dir: config carries brain"     "memory_dir=brain"    "$(cat "$repo3/.floppy/config")"
assert_contains "custom dir: config carries language"  "memory_language=ru" "$(cat "$repo3/.floppy/config")"
assert_contains "custom dir: gitignore uses brain"     "/brain/local"        "$(cat "$repo3/.gitignore")"

out3="$(cd "$repo3" && AI_FLOPPY_HOME="$ROOT" bash .floppy/run lint 2>&1)"; rc3=$?
assert_rc "custom dir: lint is green" 0 "$rc3"

rm -rf "$repo3"

summary
