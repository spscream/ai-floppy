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

# 6. header-row detection is structural, not lexical: renaming an English
# header cell must not read as a dropped trend row, and an actual data row
# disappearing must still be caught even though the header line also sits
# right above a separator row.
printf '| Metric | before | after |\n|---|---|---|\n| Latency | 10ms | 8ms |\n| Errors | 3 | 1 |\n' > "$repo/state/NOW.md"
git -C "$repo" add -A && git -C "$repo" -c user.email=t@t -c user.name=t commit -qm "table base"

printf '| KPI | before | after |\n|---|---|---|\n| Latency | 10ms | 8ms |\n| Errors | 3 | 1 |\n' > "$repo/state/NOW.md"
out6="$(cd "$repo" && AI_FLOPPY_HOME="$ROOT" bash .floppy/run guard state/NOW.md 2>&1)"; rc6=$?
assert_rc       "renamed header column is not flagged (rc)"        0 "$rc6"
case "$out6" in
  *"dropped from NOW.md"*) fail "renamed header column is not flagged" "no dropped-row error" "$out6" ;;
  *) ok "renamed header column is not flagged" ;;
esac

printf '| KPI | before | after |\n|---|---|---|\n| Latency | 10ms | 8ms |\n' > "$repo/state/NOW.md"
out7="$(cd "$repo" && AI_FLOPPY_HOME="$ROOT" bash .floppy/run guard state/NOW.md 2>&1)"; rc7=$?
assert_rc       "actual dropped data row is still caught (rc)" 1 "$rc7"
assert_contains "actual dropped data row is named"              "Errors" "$out7"

# 7. statuses_regress_marks: only a row marked as a regression is immortal.
# Without the key every row stays protected (checked by cases 2 and 6 above),
# so this block sets it and then asserts both directions.
cat >> "$repo/.floppy/config" <<'EOF'
statuses_regress_marks=worse,хуже
EOF
printf '| KPI | before | after | dir |\n|---|---|---|---|\n| Latency | 10ms | 8ms | better |\n| Errors | 1 | 3 | worse |\n| Shipped | no | yes | done |\n' > "$repo/state/NOW.md"
git -C "$repo" add -A && git -C "$repo" -c user.email=t@t -c user.name=t commit -qm "marked table"

# an improved row and a one-time "done" row may both go
printf '| KPI | before | after | dir |\n|---|---|---|---|\n| Errors | 1 | 3 | worse |\n' > "$repo/state/NOW.md"
out8="$(cd "$repo" && AI_FLOPPY_HOME="$ROOT" bash .floppy/run guard state/NOW.md 2>&1)"; rc8=$?
assert_rc "unmarked rows may be dropped (rc)" 0 "$rc8"
case "$out8" in
  *"dropped from NOW.md"*) fail "unmarked rows may be dropped" "no dropped-row error" "$out8" ;;
  *) ok "unmarked rows may be dropped" ;;
esac

# the row marked as a regression may not, and the guard still names it
printf '| KPI | before | after | dir |\n|---|---|---|---|\n| Latency | 10ms | 8ms | better |\n| Shipped | no | yes | done |\n' > "$repo/state/NOW.md"
out9="$(cd "$repo" && AI_FLOPPY_HOME="$ROOT" bash .floppy/run guard state/NOW.md 2>&1)"; rc9=$?
assert_rc       "dropped regression row is still caught (rc)" 1 "$rc9"
assert_contains "dropped regression row is named"              "Errors" "$out9"

# a row that stopped being a regression counts as present, not as dropped:
# the new side is unfiltered on purpose
printf '| KPI | before | after | dir |\n|---|---|---|---|\n| Errors | 3 | 1 | better |\n' > "$repo/state/NOW.md"
out10="$(cd "$repo" && AI_FLOPPY_HOME="$ROOT" bash .floppy/run guard state/NOW.md 2>&1)"; rc10=$?
assert_rc "recovered row is not read as dropped (rc)" 0 "$rc10"

rm -rf "$repo"
summary
