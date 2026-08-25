#!/usr/bin/env bash
set -uo pipefail
cd "$(dirname "$0")/.."
. tests/lib.sh
ROOT="$(pwd)"

repo="$(sandbox)"; cp shim/run "$repo/.floppy/run"
cat > "$repo/.floppy/config" <<'EOF'
memory_dir=brain
statuses_now=state/NOW.md
statuses_now_chars_max=200
watched_dirs=state,.floppy
EOF
mkdir -p "$repo/brain" "$repo/state"
printf '| Notes | 1 | 2 | up |\n' > "$repo/state/NOW.md"
printf 'journal\n' > "$repo/state/2026-01-01_status.md"
git -C "$repo" add -A && git -C "$repo" -c user.email=t@t -c user.name=t commit -qm base

# 1. journal touched, NOW.md not in the list
printf 'more\n' >> "$repo/state/2026-01-01_status.md"
out="$(cd "$repo" && AI_FLOPPY_HOME="$ROOT" bash .floppy/run guard state/2026-01-01_status.md 2>&1)"
# Check the configured path itself, not the bare "NOW.md" substring: the
# section header "-- journal without NOW.md" always contains that substring,
# even when the guard fails to catch anything, so a weaker check would pass
# against a version that ignores statuses_now from config.
assert_contains "journal without NOW is caught" "state/NOW.md is not in your list" "$out"

# 2. a trend row disappeared
printf '' > "$repo/state/NOW.md"
out2="$(cd "$repo" && AI_FLOPPY_HOME="$ROOT" bash .floppy/run guard state/NOW.md state/2026-01-01_status.md 2>&1)"
assert_contains "dropped trend row is caught" "Notes" "$out2"

# 3. the cap, and it comes from config not from a constant
printf '| Notes | 1 | 2 | up |\n' > "$repo/state/NOW.md"
head -c 400 /dev/zero | tr '\0' 'x' >> "$repo/state/NOW.md"
out3="$(cd "$repo" && AI_FLOPPY_HOME="$ROOT" bash .floppy/run guard state/NOW.md 2>&1)"
assert_contains "cap is read from config" "200" "$out3"

# 4. a claimed file outside every watched path
out4="$(cd "$repo" && AI_FLOPPY_HOME="$ROOT" bash .floppy/run guard outside/file.txt 2>&1)"; rc4=$?
assert_rc       "outside-watch file is refused (rc)"   1 "$rc4"
assert_contains "outside-watch file is named"           "outside/file.txt" "$out4"

# 5. a claimed file that was not actually modified
printf '| Notes | 1 | 2 | up |\n' > "$repo/state/NOW.md"
git -C "$repo" add -A && git -C "$repo" -c user.email=t@t -c user.name=t commit -qm settle
out5="$(cd "$repo" && AI_FLOPPY_HOME="$ROOT" bash .floppy/run guard state/NOW.md 2>&1)"; rc5=$?
assert_rc       "unchanged claimed file is refused (rc)" 1 "$rc5"
assert_contains "unchanged claimed file is named"         "not changed" "$out5"

rm -rf "$repo"
summary
