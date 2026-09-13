#!/usr/bin/env bash
# scripts/changelog-extract.sh: prints the CHANGELOG section for one version —
# the body a GitHub release carries. The release workflow calls it on every
# push to main, so a version bump whose changelog entry is missing fails the
# release loudly instead of publishing an empty page. The releases page sat at
# 0.20.0 while the manifests shipped 0.23.0 (noticed 2026-09-13): tags and
# releases were a by-hand step, and by-hand steps stop happening.
set -uo pipefail
cd "$(dirname "$0")/.."
. tests/lib.sh
ROOT="$(pwd)"

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
cat > "$work/CHANGELOG.md" <<'EOF'
# Changelog

Prose about the file itself, which no extraction may return.

## 1.2.0 — 2026-09-13

**Refresh `.floppy/run`: no.**

The newest entry, two paragraphs long.

Second paragraph of 1.2.0.

## 1.1.0 — 2026-09-10

The older entry, which must never leak into 1.2.0's notes.
EOF

# 1. the newest section comes out whole: both paragraphs, no heading of its
# own (the release title already carries the version), nothing of the intro
# above it and nothing of the entry below it
out="$(bash scripts/changelog-extract.sh 1.2.0 "$work/CHANGELOG.md" 2>&1)"; rc=$?
assert_rc       "extracting a present version succeeds"    0 "$rc"
assert_contains "the section's first paragraph is there"   "Refresh" "$out"
assert_contains "the section's second paragraph is there"  "Second paragraph of 1.2.0" "$out"
case "$out" in
  *"## 1.2.0"*)   fail "the version heading itself is not repeated" "no '## 1.2.0' line" "$out" ;;
  *)              ok   "the version heading itself is not repeated" ;;
esac
case "$out" in
  *"older entry"*) fail "the next entry does not leak in" "no 1.1.0 text" "$out" ;;
  *)               ok   "the next entry does not leak in" ;;
esac
case "$out" in
  *"Prose about"*) fail "the file intro does not leak in" "no intro text" "$out" ;;
  *)               ok   "the file intro does not leak in" ;;
esac

# 2. an inner section extracts too — the workflow may backfill an old version
out="$(bash scripts/changelog-extract.sh 1.1.0 "$work/CHANGELOG.md" 2>&1)"; rc=$?
assert_rc       "extracting an older version succeeds"     0 "$rc"
assert_contains "the older section comes out"              "older entry" "$out"

# 3. a version with no entry is a loud failure, not empty release notes
out="$(bash scripts/changelog-extract.sh 9.9.9 "$work/CHANGELOG.md" 2>&1)"; rc=$?
assert_rc       "a missing version fails"                  1 "$rc"
assert_contains "and names what is missing"                "no changelog entry for 9.9.9" "$out"

# 4. no arguments is a usage error
out="$(bash scripts/changelog-extract.sh 2>&1)"; rc=$?
assert_rc       "bare call refuses"                        2 "$rc"
assert_contains "bare call names its usage"                "usage" "$out"

# 5. the real CHANGELOG carries an entry for the version the manifests ship —
# this is the agreement the release workflow depends on, checked where a
# contributor sees it before CI does
shipped="$(grep -m1 '"version"' .claude-plugin/plugin.json | sed 's/.*: *"//; s/".*//')"
out="$(bash scripts/changelog-extract.sh "$shipped" 2>&1)"; rc=$?
assert_rc       "the shipped version $shipped has a changelog entry" 0 "$rc"
assert_contains "and the entry answers the shim question"  "Refresh" "$out"

summary
