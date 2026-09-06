#!/usr/bin/env bash
# Translations keep their contract, and the checker can go red.
#
# Structural, like test-docs.sh and test-knowledge.sh: nothing here asserts what
# a translation says, only that the machinery around it works. The positive
# controls are the point of the file — a checker that cannot report a problem is
# indistinguishable from one that was never wired up.
#
# What this file must NEVER assert: that the translations in this repository are
# up to date. Freshness is reported and never gated (see the spec, decision 4),
# and a structural test that drifted into checking it would be that gate
# arriving by the back door.
set -uo pipefail
cd "$(dirname "$0")/.."
. tests/lib.sh

py=python3
command -v "$py" >/dev/null 2>&1 || { printf '  skip python3 not available\n'; exit 0; }

sb="$(cd "$(mktemp -d)" && pwd -P)"
trap 'rm -rf "$sb"' EXIT
mkdir -p "$sb/docs"
printf '# Home\n\nbody\n'    > "$sb/README.md"
printf '# Lessons\n\nbody\n' > "$sb/docs/lessons.md"

marker() { # blob date  -> a translation file with that marker
  printf '<!-- floppy:translation of=docs/lessons.md blob=%s on=%s -->\n\n# Уроки\n\ntext\n' \
    "$1" "$2" > "$sb/docs/lessons.ru.md"
}

# ---------- 1. a translation behind its source is reported, and the run is green ----------
# Zeroes are a blob sha no content produces, so this is "behind" by construction.
marker 0000000000000000000000000000000000000000 2026-01-01
out="$("$py" scripts/translation-check.py --root "$sb" 2>&1)"; rc=$?
assert_rc "the check exits 0 even when a translation is behind" 0 "$rc"
assert_contains "and it reports the drift"        "behind the source"    "$out"
assert_contains "and names the translation"       "docs/lessons.ru.md"   "$out"
assert_contains "and prints the diff recipe"      "git cat-file blob"    "$out"
assert_contains "and names the untranslated doc"  "README.md"            "$out"

# ---------- 2. --stamp records the sha git itself would ----------
# The identity the whole design rests on: the recorded value is a git blob sha,
# so it is a pointer into history and `git cat-file` can resolve it. Asserted
# against git's own answer, not against a second copy of our implementation.
"$py" scripts/translation-check.py --root "$sb" --stamp docs/lessons.ru.md >/dev/null 2>&1
stamped="$(sed -n '1s/.*blob=\([0-9a-f]*\).*/\1/p' "$sb/docs/lessons.ru.md")"
assert_eq "--stamp records the blob sha git computes" \
  "$(git hash-object "$sb/docs/lessons.md")" "$stamped"

out2="$("$py" scripts/translation-check.py --root "$sb" 2>&1)"
# The case below passes on empty output too — which is what a script that does
# not run produces. So assert first that the script actually said something.
assert_contains "the check still reports on the rest of the corpus" "untranslated" "$out2"
case "$out2" in
  *"behind the source"*) fail "a stamped translation is not reported as behind" "no drift" "$out2" ;;
  *) ok "a stamped translation is not reported as behind" ;;
esac

# ---------- 3. positive controls: each contract problem is caught ----------
rm -f "$sb/docs/lessons.ru.md"
printf '# Уроки\n\ntext\n' > "$sb/docs/lessons.ru.md"
out3="$("$py" scripts/translation-check.py --root "$sb" 2>&1)"
assert_contains "a file shaped like a translation with no marker is caught" \
  "no floppy:translation marker" "$out3"

marker deadbeef 2026-09-06
out4="$("$py" scripts/translation-check.py --root "$sb" 2>&1)"
assert_contains "a blob that is not 40 hex is caught" "is not a git blob sha" "$out4"

marker "$(git hash-object "$sb/docs/lessons.md")" not-a-date
out5="$("$py" scripts/translation-check.py --root "$sb" 2>&1)"
assert_contains "a non-ISO date is caught" "not an ISO date" "$out5"

# One day of slack, not politeness: an evening at UTC+3 is already tomorrow for
# the runners. The same rule is frozen for metadata.as_of.
marker "$(git hash-object "$sb/docs/lessons.md")" 2099-01-01
out6="$("$py" scripts/translation-check.py --root "$sb" 2>&1)"
assert_contains "a date far in the future is caught" "in the future" "$out6"

printf '<!-- floppy:translation of=docs/nope.md blob=%s on=2026-09-06 -->\n\n# Уроки\n' \
  "$(git hash-object "$sb/docs/lessons.md")" > "$sb/docs/lessons.ru.md"
out7="$("$py" scripts/translation-check.py --root "$sb" 2>&1)"
assert_contains "an \`of\` that disagrees with the file name is caught" \
  "does not name its sibling" "$out7"

# ---------- 4. the script runs on this repository ----------
real="$("$py" scripts/translation-check.py 2>&1)"; real_rc=$?
assert_rc "the check exits 0 on this repository" 0 "$real_rc"

# ---------- 5. no input makes the checker exit non-zero ----------
# The one rule it may never break, and every line here crashed an earlier version.
mkdir -p "$sb/docs/broken.ru.md"
out8="$("$py" scripts/translation-check.py --root "$sb" 2>&1)"; rc8=$?
rmdir "$sb/docs/broken.ru.md"
assert_rc "a directory named like a translation does not crash it" 0 "$rc8"

"$py" scripts/translation-check.py --root "$sb" --stamp README.md >/dev/null 2>&1
assert_rc "--stamp on a path that is not a translation exits 0" 0 "$?"

"$py" scripts/translation-check.py --root "$sb" --stamp docs/nope.ru.md >/dev/null 2>&1
assert_rc "--stamp on a file that does not exist exits 0" 0 "$?"

"$py" scripts/translation-check.py --root "$sb/no-such-directory" >/dev/null 2>&1
assert_rc "--root pointing nowhere exits 0" 0 "$?"

# ---------- 6. a misnamed source does not hide an untranslated document ----------
printf '# Other\n' > "$sb/docs/other.md"
printf '<!-- floppy:translation of=docs/other.md blob=%s on=2026-09-06 -->\n\n# т\n' \
  "$(git hash-object "$sb/docs/other.md")" > "$sb/docs/lessons.ru.md"
out9="$("$py" scripts/translation-check.py --root "$sb" 2>&1)"
assert_contains "a marker naming the wrong source is still a contract problem" \
  "does not name its sibling" "$out9"
assert_contains "and the document it wrongly claims is still listed as untranslated" \
  "docs/other.md" "$out9"
rm -f "$sb/docs/other.md" "$sb/docs/lessons.ru.md"

# ---------- 7. the real corpus keeps the contract ----------
# The loop below is worthless if it iterates over nothing — the empty-loop trap
# this repository has already paid for twice. So the count is asserted first.
# The rule lives in scripts/translation-check.py --list and nowhere else. It was
# written out five times — here, twice more in this file, in the gate in
# scripts/workstatus.sh, and in a sed deriving the sibling — and four
# consecutive rounds of fixes on #36 turned on those copies disagreeing. So this
# asks the authority instead of restating it, and the probes below became
# positive controls ON that authority rather than on a private copy of it.
count_translations() { # root -> count
  "$py" scripts/translation-check.py --root "$1" --list | grep -c . || true
}

# A positive control on the rule above, in a temp directory — never in the live
# docs/, which a parallel test file would see.
probe_root="$(mktemp -d)"
mkdir -p "$probe_root/docs/zz.ru.md"
printf 'x\n' > "$probe_root/docs/zz.ru.md/a.md"
assert_eq "a directory named like a translation is not counted" "0" \
  "$(count_translations "$probe_root")"
printf 'x\n' > "$probe_root/docs/real.ru.md"
assert_eq "and a regular file is counted" "1" "$(count_translations "$probe_root")"
printf 'x\n' > "$probe_root/CHANGELOG.old.md"
assert_eq "and a two-dot name that is not a translation is not" "1" \
  "$(count_translations "$probe_root")"
printf 'x\n' > "$probe_root/guide.md"
printf 'x\n' > "$probe_root/guide.RU.md"
assert_eq "and an uppercase language tag is not" "1" "$(count_translations "$probe_root")"
rm -rf "$probe_root"

real_n="$(count_translations .)"
assert_eq "there is at least one translation to check" "0" \
  "$([[ "$real_n" -ge 1 ]] && echo 0 || echo 1)"

# The same authority names the corpus. What stays hand-written below is the
# SIBLING rule, and deliberately: the checker reports and never fails, so this
# loop is the only thing in CI that can redden a hand-written marker. Deriving
# the expectation from the checker would let a checker bug agree with itself.
while IFS= read -r f; do
  [[ -f "$f" ]] || continue
  line1="$(head -1 "$f")"
  assert_contains "$f carries a marker on line 1" "floppy:translation" "$line1"
  src="$(printf '%s' "$line1" | sed -n 's/.*of=\([^ ]*\).*/\1/p')"
  assert_eq "$f names a source that exists" "0" \
    "$([[ -f "$src" ]] && echo 0 || echo 1)"
  sha="$(printf '%s' "$line1" | sed -n 's/.*blob=\([0-9a-f]*\).*/\1/p')"
  assert_eq "$f records a 40-character blob sha" "40" "${#sha}"

  # `of` must name the sibling, not merely some file that exists. The checker
  # reports this and never fails, so this loop is the only thing that can make a
  # hand-written marker red in CI.
  expected_src="$(printf '%s' "$f" | LC_ALL=C sed -E 's/\.[a-z]{2}\.md$/.md/')"
  assert_eq "$f names its own sibling as the source" "$expected_src" "$src"

  # And the date has to be a date. One day of slack, not politeness: an evening
  # at UTC+3 is already tomorrow for the runners, which is the same rule frozen
  # for metadata.as_of.
  on="$(printf '%s' "$line1" | sed -n 's/.*on=\([^ ]*\).*/\1/p')"
  # A real date, not the shape of one. The regex this replaces accepted
  # 2026-02-30 — four digits, two, two — and that date also sorts before
  # tomorrow, so it passed both halves of this check. The checker rejects it,
  # but the checker reports and never fails, so nothing in CI went red.
  # A parser, not the checker: this loop is the independent second opinion on a
  # hand-written marker, and asking the tool under test would end that.
  "$py" -c 'import datetime,sys; datetime.date.fromisoformat(sys.argv[1])' "$on" 2>/dev/null
  assert_rc "$f records a real calendar date" "0" "$?"
  tomorrow="$("$py" -c 'import datetime as d; print((d.date.today()+d.timedelta(days=1)).isoformat())')"
  assert_eq "$f is not stamped more than a day in the future" "0" \
    "$([[ "$on" > "$tomorrow" ]] && echo 1 || echo 0)"
done < <("$py" scripts/translation-check.py --list)

# Deliberately absent: any assertion that these files are up to date. See the
# header of this file.

summary
