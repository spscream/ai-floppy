#!/usr/bin/env bash
# The heat log: `heat <slug>...` appends one dated line per note opened, so
# pruning and consolidation can lean on data instead of dates (issue #70).
# The log is machine-local (.floppy/heat.log, gitignored) and lint reports
# cold notes from it without ever failing — reporters, not gates.
set -uo pipefail
cd "$(dirname "$0")/.."
. tests/lib.sh
ROOT="$(pwd)"

repo="$(sandbox)"; cp shim/run "$repo/.floppy/run"
today="$(date -u +%Y-%m-%d)"

# 1. logging one note appends a dated line and succeeds
out="$(cd "$repo" && AI_FLOPPY_HOME="$ROOT" bash .floppy/run heat my-note 2>&1)"; rc=$?
assert_rc       "heat with one slug succeeds"       0 "$rc"
log="$(cat "$repo/.floppy/heat.log" 2>/dev/null)"
assert_contains "the line carries the UTC date"     "$today my-note" "$log"

# 2. the log is gitignored, and the ignore line is added exactly once
ignores="$(grep -c '^\.floppy/heat\.log$' "$repo/.gitignore" 2>/dev/null)"
assert_eq       "gitignore carries the log once"    "1" "$ignores"
(cd "$repo" && AI_FLOPPY_HOME="$ROOT" bash .floppy/run heat my-note >/dev/null 2>&1)
ignores2="$(grep -c '^\.floppy/heat\.log$' "$repo/.gitignore" 2>/dev/null)"
assert_eq       "a second call does not duplicate the ignore line" "1" "$ignores2"

# 3. several slugs in one call — one line each
(cd "$repo" && AI_FLOPPY_HOME="$ROOT" bash .floppy/run heat note-a note-b >/dev/null 2>&1)
log="$(cat "$repo/.floppy/heat.log")"
assert_contains "first of two slugs is logged"      "$today note-a" "$log"
assert_contains "second of two slugs is logged"     "$today note-b" "$log"

# 4. no arguments is a loud usage error, not a silent no-op
out="$(cd "$repo" && AI_FLOPPY_HOME="$ROOT" bash .floppy/run heat 2>&1)"; rc=$?
assert_rc       "bare heat refuses"                 2 "$rc"
assert_contains "bare heat names its usage"         "usage" "$out"

# 5. rotation: the log cannot become its own quota problem
i=0
while [[ $i -lt 5100 ]]; do printf '2026-01-01 filler-%d\n' "$i"; i=$((i+1)); done >> "$repo/.floppy/heat.log"
(cd "$repo" && AI_FLOPPY_HOME="$ROOT" bash .floppy/run heat my-note >/dev/null 2>&1)
lines="$(wc -l < "$repo/.floppy/heat.log" | tr -d ' ')"
if [[ "$lines" -le 4001 ]]; then ok "an oversized log is trimmed ($lines lines)"; else fail "an oversized log is trimmed" "<= 4001 lines" "$lines lines"; fi
tail1="$(tail -n1 "$repo/.floppy/heat.log")"
assert_eq       "the trim keeps the newest end"     "$today my-note" "$tail1"

# ---------- the lint reporter ----------
# A memory with two notes; only one of them ever logged as opened. lint names
# the cold one, does not name the hot one as cold, and does not fail over it.
repo2="$(sandbox)"; cp shim/run "$repo2/.floppy/run"
echo "memory_dir=brain" > "$repo2/.floppy/config"
mkdir -p "$repo2/brain/half"
cat > "$repo2/brain/MEMORY.md" <<'EOF'
# Index
- [Half](half/INDEX.md) — pointer
EOF
cat > "$repo2/brain/half/INDEX.md" <<'EOF'
# Half
- [Hot note](hot-note.md) — pointer
- [Cold note](cold-note.md) — pointer
EOF
for n in hot-note cold-note; do
cat > "$repo2/brain/half/$n.md" <<EOF
---
name: $n
description: a note
metadata:
  type: project
  evidence: read
---
Body.
EOF
done
printf 'chars_max=100000\nnote_chars_max=10000\npointers_max=40\ngrandfathered=\n' > "$repo2/brain/quota.lock"

# no heat.log yet: lint stays silent about heat and stays green
out="$(cd "$repo2" && AI_FLOPPY_HOME="$ROOT" bash .floppy/run lint 2>&1)"; rc=$?
assert_rc "lint without a heat log passes" 0 "$rc"
case "$out" in
  *"heat"*) fail "lint without a heat log says nothing about heat" "no heat section" "$out" ;;
  *)        ok   "lint without a heat log says nothing about heat" ;;
esac

# with a log that has seen only hot-note: the cold one is named, run still green
(cd "$repo2" && AI_FLOPPY_HOME="$ROOT" bash .floppy/run heat hot-note >/dev/null 2>&1)
out="$(cd "$repo2" && AI_FLOPPY_HOME="$ROOT" bash .floppy/run lint 2>&1)"; rc=$?
assert_rc       "lint with a heat log still passes"  0 "$rc"
assert_contains "the cold note is named"             "cold-note" "$out"
assert_contains "the count of unopened notes is reported" "1 of 2 notes never opened" "$out"
case "$out" in
  *"hot-note"*) fail "the hot note is not listed as cold" "hot-note absent" "$out" ;;
  *)            ok   "the hot note is not listed as cold" ;;
esac

summary
