#!/usr/bin/env bash
# The knowledge base keeps its contract, and both of its checkers can go red.
#
# Structural, like test-docs.sh: nothing here asserts what a note says, only that the
# machinery around it works. Two of the assertions are positive controls, and they are
# the point of the file — a checker that cannot fail is indistinguishable from one that
# was never wired up, and this repository has paid for that twice (docs/lessons.md, and
# the note this base carries about `find`).
set -uo pipefail
cd "$(dirname "$0")/.."
. tests/lib.sh

py=python3
command -v "$py" >/dev/null 2>&1 || { printf '  skip python3 not available\n'; exit 0; }

# ---------- 1. both checkers run clean on the committed base ----------
rot="$($py scripts/knowledge-rot-check.py 2>&1)"; rot_rc=$?
assert_rc "rot-check exits 0 on a clean base" 0 "$rot_rc"
assert_contains "rot-check reports the base as clean" "clean:" "$rot"

run="$($py scripts/knowledge-recheck.py 2>&1)"; run_rc=$?
assert_rc "recheck exits 0 when nothing failed" 0 "$run_rc"
assert_contains "recheck reports zero failures" "0 failed" "$run"

# The count, not the colour. A runner that looked at nothing also prints "0 failed".
notes="$(find -L knowledge/notes -name '*.md' -not -name '_*' | wc -l | tr -d ' ')"
counted="$($py scripts/knowledge-recheck.py --json 2>/dev/null \
  | tr ',' '\n' | grep -c '"path"')"
assert_eq "recheck looked at every note ($notes)" "$notes" "$counted"

# Skips are never folded into passes: all four numbers are always printed.
for word in passed failed skipped "not machine-checkable"; do
  assert_contains "report names '$word'" "$word" "$run"
done

# ---------- 2. positive control: a broken contract goes red ----------
# Not `_`-prefixed: both scripts skip files starting with `_`, so a probe named that
# way would prove nothing — it has to be a file they actually look at.
probe=knowledge/notes/practice/zz-probe-broken.md
cleanup() { rm -f "$probe"; }
trap cleanup EXIT
printf -- '---\nname: wrong-name\narea: nope\nverified_on: not-a-date\nrecheck_cmd: echo hi\n---\n\nbody\n' > "$probe"
out="$($py scripts/knowledge-rot-check.py 2>&1)"
assert_contains "rot-check catches a name that is not the filename" "wrong-name" "$out"
assert_contains "rot-check catches an unknown area"                 "unknown area" "$out"
assert_contains "rot-check catches a non-ISO date"                  "not an ISO date" "$out"
assert_contains "rot-check catches recheck_cmd with no expect"      "nothing to compare" "$out"
rm -f "$probe"

# ---------- 3. positive control: a failing check goes red ----------
probe2=knowledge/notes/practice/zz-probe-failing.md
printf -- '---\nname: zz-probe-failing\ndescription: a check that must fail\narea: practice\nverified_on: 2026-09-05\nverified_against: this test\nrecheck: n/a\nrecheck_cmd: echo actual\nexpect: something-else\n---\n\nbody\n' > "$probe2"
out2="$($py scripts/knowledge-recheck.py --only zz-probe-failing 2>&1)"; rc2=$?
rm -f "$probe2"
assert_rc "recheck exits 1 when a check fails" 1 "$rc2"
assert_contains "recheck names the mismatch" "something-else" "$out2"

# ---------- 4. the site page carries the notes ----------
out_dir="$(mktemp -d)"; trap 'rm -rf "$out_dir"; cleanup' EXIT
bash scripts/site-build.sh "$out_dir" >/dev/null 2>&1
page="$(cat "$out_dir/knowledge.md" 2>/dev/null || true)"
assert_contains "knowledge page exists and carries the README's heading" "# The knowledge base" "$page"
quoted_tail=0
for f in $(find -L knowledge/notes -name '*.md' -not -name '_*'); do
  desc="$(awk 'index($0, "description: ") == 1 { sub(/^description: /, ""); print; exit }' "$f")"
  assert_contains "page carries $(basename "$f")" "$desc" "$page"
  # A value that ENDS in a quote without starting with one — `reports "clean"` —
  # is the shape that broke the front-matter reader: it stripped each end
  # independently and ate the final character.
  case "$desc" in '"'*) ;; *'"') quoted_tail=1 ;; esac
done

# Coverage guard, not a style rule. The repair above is exercised only while
# some note actually has that shape, and nothing would say so on the day
# somebody rewords the one that does — the loop would simply stop testing it.
assert_eq "a note still exercises a description ending in a quoted word" 1 "$quoted_tail"

summary
