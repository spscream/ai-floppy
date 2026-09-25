#!/usr/bin/env bash
# The heat log: `heat <slug>...` appends one dated line per note opened, so
# pruning and consolidation can lean on data instead of dates (issue #70).
# The log is machine-local (.floppy/heat.log, ignored via .git/info/exclude —
# never by editing the consumer's .gitignore, review 2026-09-13) and lint
# reports cold notes from it without ever failing — reporters, not gates.
set -uo pipefail
cd "$(dirname "$0")/.."
. tests/lib.sh
ROOT="$(pwd)"

repo="$(sandbox)"
today="$(date -u +%Y-%m-%d)"

# 1. logging one note appends a dated line and succeeds
out="$(cd "$repo" && bash "$ROOT/scripts/run" heat my-note 2>&1)"; rc=$?
assert_rc       "heat with one slug succeeds"       0 "$rc"
log="$(cat "$repo/.floppy/heat.log" 2>/dev/null)"
assert_contains "the line carries the UTC date"     "$today my-note" "$log"

# 2. the log and its rotation temp file are ignored via .git/info/exclude,
# and the consumer's .gitignore is never touched: the first call used to edit
# it, which left the tree permanently dirty on a file wrap's guard refuses to
# commit (review 2026-09-13, finding 1)
if (cd "$repo" && git check-ignore -q .floppy/heat.log); then ok "the log is ignored"; else fail "the log is ignored" "ignored" "not ignored"; fi
if (cd "$repo" && git check-ignore -q .floppy/heat.log.tmp); then ok "the rotation temp file is ignored too"; else fail "the rotation temp file is ignored too" "ignored" "not ignored"; fi
if [[ -f "$repo/.gitignore" ]]; then fail "heat does not create a .gitignore" "no .gitignore" "$(cat "$repo/.gitignore")"; else ok "heat does not create a .gitignore"; fi
(cd "$repo" && bash "$ROOT/scripts/run" heat my-note >/dev/null 2>&1)
ignores2="$(grep -c '\.floppy/heat\.log' "$repo/.git/info/exclude" 2>/dev/null)"
assert_eq       "a second call does not duplicate the exclude line" "1" "$ignores2"

# 3. appending must not weld onto an exclude file with no trailing newline —
# that would silently disable its last rule (same defect class as review
# finding 1 had for .gitignore)
repo_nl="$(sandbox)"
printf '# local rules\nsecret.txt' > "$repo_nl/.git/info/exclude"
(cd "$repo_nl" && bash "$ROOT/scripts/run" heat my-note >/dev/null 2>&1)
if (cd "$repo_nl" && git check-ignore -q secret.txt); then ok "a no-final-newline exclude keeps its last rule"; else fail "a no-final-newline exclude keeps its last rule" "secret.txt still ignored" "$(cat "$repo_nl/.git/info/exclude")"; fi
if (cd "$repo_nl" && git check-ignore -q .floppy/heat.log); then ok "and the log is ignored there as well"; else fail "and the log is ignored there as well" "ignored" "not ignored"; fi

# 4. a consumer whose .gitignore has `*.log` covers the log but NOT the
# rotation temp file (basename heat.log.tmp does not match). The exclude line
# is still written so the temp file is covered, and the .gitignore stays
# untouched (review finding 9).
repo_bp="$(sandbox)"
printf '*.log\n' > "$repo_bp/.gitignore"
(cd "$repo_bp" && bash "$ROOT/scripts/run" heat my-note >/dev/null 2>&1)
extra="$(grep -c '\.floppy/heat\.log' "$repo_bp/.gitignore")"
assert_eq       "the consumer's .gitignore is left alone" "0" "$extra"
if (cd "$repo_bp" && git check-ignore -q .floppy/heat.log.tmp); then ok "the temp file is covered despite the broader pattern"; else fail "the temp file is covered despite the broader pattern" "ignored" "not ignored"; fi
log="$(cat "$repo_bp/.floppy/heat.log" 2>/dev/null)"
assert_contains "the log is still written under a broader pattern" "$today my-note" "$log"

# 5. several slugs in one call — one line each; paths and .md are normalized
# to the bare slug, because the caller is an agent that just read a filename
(cd "$repo" && bash "$ROOT/scripts/run" heat note-a half/note-b.md >/dev/null 2>&1)
log="$(cat "$repo/.floppy/heat.log")"
assert_contains "a bare slug is logged as itself"   "$today note-a" "$log"
assert_contains "a path with .md is logged as its slug" "$today note-b" "$log"

# 5b. a slug with whitespace or a leading dash is rejected loudly, never
# logged: lint matches the second field of a line, so a two-word slug would be
# permanently cold with both ends reporting ok (review finding 7); `--help`
# would land in the log as data on GNU and as an error on BSD (finding 5)
out="$(cd "$repo" && bash "$ROOT/scripts/run" heat good-note "two words" 2>&1)"; rc=$?
assert_rc       "a rejected slug fails the call"    1 "$rc"
assert_contains "the rejected slug is named"        "not a note slug" "$out"
log="$(cat "$repo/.floppy/heat.log")"
assert_contains "the good slug in the same call is still logged" "$today good-note" "$log"
case "$log" in
  *"two words"*) fail "the whitespace slug never reaches the log" "no 'two words' line" "$log" ;;
  *)             ok   "the whitespace slug never reaches the log" ;;
esac
out="$(cd "$repo" && bash "$ROOT/scripts/run" heat --help 2>&1)"; rc=$?
assert_rc       "a dash-leading argument is rejected" 1 "$rc"
case "$(cat "$repo/.floppy/heat.log")" in
  *" --help"*) fail "--help never reaches the log" "no --help line" "tail: $(tail -n2 "$repo/.floppy/heat.log")" ;;
  *)           ok   "--help never reaches the log" ;;
esac

# 6. no arguments is a loud usage error, not a silent no-op
out="$(cd "$repo" && bash "$ROOT/scripts/run" heat 2>&1)"; rc=$?
assert_rc       "bare heat refuses"                 2 "$rc"
assert_contains "bare heat names its usage"         "usage" "$out"

# 7. a failed write is an error, not an `ok` (review finding 2)
repo_ro="$(sandbox)"
mkdir "$repo_ro/.floppy/heat.log"   # a directory: appending fails even as root
out="$(cd "$repo_ro" && bash "$ROOT/scripts/run" heat my-note 2>&1)"; rc=$?
assert_rc       "an unwritable log fails the verb"  1 "$rc"
assert_contains "the failure is named, not ok'd"    "could not write" "$out"
case "$out" in
  *"ok heat"*) fail "no success line on failure" "no 'ok heat'" "$out" ;;
  *)           ok   "no success line on failure" ;;
esac

# 7b. a stale FLOPPY_REPO must be a loud error, not a log written into
# whatever directory the shell happens to be in (review finding 8)
repo_st="$(sandbox)"
out="$(cd "$repo_st" && FLOPPY_REPO="$repo_st/nowhere" bash "$ROOT/scripts/memory-heat.sh" my-note 2>&1)"; rc=$?
assert_rc       "a stale FLOPPY_REPO fails the verb" 1 "$rc"
if [[ -f "$repo_st/.floppy/heat.log" ]]; then fail "nothing is written outside the named repo" "no heat.log" "$(cat "$repo_st/.floppy/heat.log")"; else ok "nothing is written outside the named repo"; fi

# 8. rotation: the log cannot become its own quota problem
i=0
while [[ $i -lt 5100 ]]; do printf '2026-01-01 filler-%d\n' "$i"; i=$((i+1)); done >> "$repo/.floppy/heat.log"
(cd "$repo" && bash "$ROOT/scripts/run" heat my-note >/dev/null 2>&1)
lines="$(wc -l < "$repo/.floppy/heat.log" | tr -d ' ')"
if [[ "$lines" -le 4001 ]]; then ok "an oversized log is trimmed ($lines lines)"; else fail "an oversized log is trimmed" "<= 4001 lines" "$lines lines"; fi
tail1="$(tail -n1 "$repo/.floppy/heat.log")"
assert_eq       "the trim keeps the newest end"     "$today my-note" "$tail1"

# 8b. a rotation that cannot complete is named, not swallowed — a silent
# failure here means the log grows past its cap forever (review finding 6)
repo_rf="$(sandbox)"
mkdir "$repo_rf/.floppy/heat.log.tmp"   # a directory: the trim's redirect fails
i=0
while [[ $i -lt 5100 ]]; do printf '2026-01-01 filler-%d\n' "$i"; i=$((i+1)); done >> "$repo_rf/.floppy/heat.log"
out="$(cd "$repo_rf" && bash "$ROOT/scripts/run" heat my-note 2>&1)"; rc=$?
assert_rc       "the open is still recorded when only rotation fails" 0 "$rc"
assert_contains "the failed rotation is named"      "could not rotate" "$out"
tail1="$(tail -n1 "$repo_rf/.floppy/heat.log")"
assert_eq       "the append preceded the failed trim" "$today my-note" "$tail1"

# ---------- the lint reporter ----------
# A memory with three notes; one logged as opened, one cold, one cold with a
# regex metacharacter in its name. lint names the cold ones, does not name the
# hot one, and does not fail over any of it.
repo2="$(sandbox)"
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
out="$(cd "$repo2" && bash "$ROOT/scripts/run" lint 2>&1)"; rc=$?
assert_rc "lint without a heat log passes" 0 "$rc"
case "$out" in
  *"heat"*) fail "lint without a heat log says nothing about heat" "no heat section" "$out" ;;
  *)        ok   "lint without a heat log says nothing about heat" ;;
esac

# an empty log (touch, the obvious opt-in) is reported as such, not "since :"
: > "$repo2/.floppy/heat.log"
out="$(cd "$repo2" && bash "$ROOT/scripts/run" lint 2>&1)"; rc=$?
assert_rc       "lint with an empty heat log passes" 0 "$rc"
assert_contains "an empty log is named as the reason" "heat log is empty" "$out"

# a log holding only a blank line is empty in the same sense: `! -s` misses
# it and the report would again stand on "since :" (review sub-finding)
printf '\n' > "$repo2/.floppy/heat.log"
out="$(cd "$repo2" && bash "$ROOT/scripts/run" lint 2>&1)"; rc=$?
assert_rc       "lint with a blank-line heat log passes" 0 "$rc"
assert_contains "a blank-line log counts as empty" "heat log is empty" "$out"

# with a log that has seen only hot-note, plus a line matching a.b-note only
# as a regex (aXb-note): both cold notes named, run still green
: > "$repo2/.floppy/heat.log"
(cd "$repo2" && bash "$ROOT/scripts/run" heat hot-note >/dev/null 2>&1)
printf '%s aXb-note\n' "$today" >> "$repo2/.floppy/heat.log"
out="$(cd "$repo2" && bash "$ROOT/scripts/run" lint 2>&1)"; rc=$?
assert_rc       "lint with a heat log still passes"  0 "$rc"
assert_contains "the cold note is named"             "cold-note" "$out"
assert_contains "a dot in a slug is not a regex dot" "a.b-note" "$out"
assert_contains "the count of unopened notes is reported" "2 of 3 notes never opened" "$out"
case "$out" in
  *"hot-note"*) fail "the hot note is not listed as cold" "hot-note absent" "$out" ;;
  *)            ok   "the hot note is not listed as cold" ;;
esac

summary
