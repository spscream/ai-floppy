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

# 2. the log and its rotation temp file are gitignored, once
if (cd "$repo" && git check-ignore -q .floppy/heat.log); then ok "the log is gitignored"; else fail "the log is gitignored" "ignored" "not ignored"; fi
if (cd "$repo" && git check-ignore -q .floppy/heat.log.tmp); then ok "the rotation temp file is gitignored too"; else fail "the rotation temp file is gitignored too" "ignored" "not ignored"; fi
(cd "$repo" && AI_FLOPPY_HOME="$ROOT" bash .floppy/run heat my-note >/dev/null 2>&1)
ignores2="$(grep -c '\.floppy/heat\.log' "$repo/.gitignore" 2>/dev/null)"
assert_eq       "a second call does not duplicate the ignore line" "1" "$ignores2"

# 3. appending must not weld onto a .gitignore with no trailing newline —
# that would silently disable the consumer's own last rule (review finding 1)
repo_nl="$(sandbox)"; cp shim/run "$repo_nl/.floppy/run"
printf 'node_modules\n.env' > "$repo_nl/.gitignore"
(cd "$repo_nl" && AI_FLOPPY_HOME="$ROOT" bash .floppy/run heat my-note >/dev/null 2>&1)
if (cd "$repo_nl" && git check-ignore -q .env); then ok "a no-final-newline .gitignore keeps its last rule"; else fail "a no-final-newline .gitignore keeps its last rule" ".env still ignored" "$(cat "$repo_nl/.gitignore")"; fi
if (cd "$repo_nl" && git check-ignore -q .floppy/heat.log); then ok "and the log is ignored there as well"; else fail "and the log is ignored there as well" "ignored" "not ignored"; fi

# 4. a .gitignore that already covers the log gets no redundant line
repo_bp="$(sandbox)"; cp shim/run "$repo_bp/.floppy/run"
printf '*.log\n' > "$repo_bp/.gitignore"
(cd "$repo_bp" && AI_FLOPPY_HOME="$ROOT" bash .floppy/run heat my-note >/dev/null 2>&1)
extra="$(grep -c '\.floppy/heat\.log' "$repo_bp/.gitignore")"
assert_eq       "a broader ignore pattern is left alone" "0" "$extra"
log="$(cat "$repo_bp/.floppy/heat.log" 2>/dev/null)"
assert_contains "the log is still written under a broader pattern" "$today my-note" "$log"

# 5. several slugs in one call — one line each; paths and .md are normalized
# to the bare slug, because the caller is an agent that just read a filename
(cd "$repo" && AI_FLOPPY_HOME="$ROOT" bash .floppy/run heat note-a half/note-b.md >/dev/null 2>&1)
log="$(cat "$repo/.floppy/heat.log")"
assert_contains "a bare slug is logged as itself"   "$today note-a" "$log"
assert_contains "a path with .md is logged as its slug" "$today note-b" "$log"

# 6. no arguments is a loud usage error, not a silent no-op
out="$(cd "$repo" && AI_FLOPPY_HOME="$ROOT" bash .floppy/run heat 2>&1)"; rc=$?
assert_rc       "bare heat refuses"                 2 "$rc"
assert_contains "bare heat names its usage"         "usage" "$out"

# 7. a failed write is an error, not an `ok` (review finding 2)
repo_ro="$(sandbox)"; cp shim/run "$repo_ro/.floppy/run"
mkdir "$repo_ro/.floppy/heat.log"   # a directory: appending fails even as root
out="$(cd "$repo_ro" && AI_FLOPPY_HOME="$ROOT" bash .floppy/run heat my-note 2>&1)"; rc=$?
assert_rc       "an unwritable log fails the verb"  1 "$rc"
assert_contains "the failure is named, not ok'd"    "could not write" "$out"
case "$out" in
  *"ok heat"*) fail "no success line on failure" "no 'ok heat'" "$out" ;;
  *)           ok   "no success line on failure" ;;
esac

# 8. rotation: the log cannot become its own quota problem
i=0
while [[ $i -lt 5100 ]]; do printf '2026-01-01 filler-%d\n' "$i"; i=$((i+1)); done >> "$repo/.floppy/heat.log"
(cd "$repo" && AI_FLOPPY_HOME="$ROOT" bash .floppy/run heat my-note >/dev/null 2>&1)
lines="$(wc -l < "$repo/.floppy/heat.log" | tr -d ' ')"
if [[ "$lines" -le 4001 ]]; then ok "an oversized log is trimmed ($lines lines)"; else fail "an oversized log is trimmed" "<= 4001 lines" "$lines lines"; fi
tail1="$(tail -n1 "$repo/.floppy/heat.log")"
assert_eq       "the trim keeps the newest end"     "$today my-note" "$tail1"

# ---------- the lint reporter ----------
# A memory with three notes; one logged as opened, one cold, one cold with a
# regex metacharacter in its name. lint names the cold ones, does not name the
# hot one, and does not fail over any of it.
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
- [Dotted note](a.b-note.md) — pointer
EOF
for n in hot-note cold-note a.b-note; do
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

# an empty log (touch, the obvious opt-in) is reported as such, not "since :"
: > "$repo2/.floppy/heat.log"
out="$(cd "$repo2" && AI_FLOPPY_HOME="$ROOT" bash .floppy/run lint 2>&1)"; rc=$?
assert_rc       "lint with an empty heat log passes" 0 "$rc"
assert_contains "an empty log is named as the reason" "heat log is empty" "$out"

# with a log that has seen only hot-note, plus a line matching a.b-note only
# as a regex (aXb-note): both cold notes named, run still green
(cd "$repo2" && AI_FLOPPY_HOME="$ROOT" bash .floppy/run heat hot-note >/dev/null 2>&1)
printf '%s aXb-note\n' "$today" >> "$repo2/.floppy/heat.log"
out="$(cd "$repo2" && AI_FLOPPY_HOME="$ROOT" bash .floppy/run lint 2>&1)"; rc=$?
assert_rc       "lint with a heat log still passes"  0 "$rc"
assert_contains "the cold note is named"             "cold-note" "$out"
assert_contains "a dot in a slug is not a regex dot" "a.b-note" "$out"
assert_contains "the count of unopened notes is reported" "2 of 3 notes never opened" "$out"
case "$out" in
  *"hot-note"*) fail "the hot note is not listed as cold" "hot-note absent" "$out" ;;
  *)            ok   "the hot note is not listed as cold" ;;
esac

summary
