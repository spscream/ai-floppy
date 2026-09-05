#!/usr/bin/env bash
# What a release has to keep in step, and did not.
#
# Between 0.14.0 and 0.16.2 five versions — 0.15.0, 0.15.1, 0.16.0, 0.16.1,
# 0.16.2 — bumped .claude-plugin/plugin.json and nothing else. No tag, no
# release, and both marketplace manifests plus the Cursor plugin manifest sat
# at 0.14.0 the whole time. Since the marketplace manifest is what an update
# compares, `plugin update` had nothing to copy: the two `link` fixes those
# releases were written for never reached a consumer.
#
# Nothing was red, and nothing could have been. Each commit looked complete on
# its own — the omission is only visible against the other files, which is
# exactly the shape a test can see and a reviewer cannot. Review would not have
# caught this; there was a reviewer, and it did not.
#
# Structural, like test-docs.sh: no behaviour to run, only agreement to hold.
#
# bash 3.2 (macOS) target: no mapfile, no declare -A.
set -uo pipefail
cd "$(dirname "$0")/.."
. tests/lib.sh

# The only "version" key in each of these files, so the first match is it. A
# real JSON parser is not a dependency this suite has, or needs: these are
# files this repository writes and controls the shape of.
ver_of() { # file
  grep -m1 '"version"' "$1" 2>/dev/null | sed 's/.*: *"//; s/".*//'
}

shipped="$(ver_of .claude-plugin/plugin.json)"

assert_eq "the plugin manifest carries a version" "0" \
  "$([[ -n "$shipped" ]] && echo 0 || echo 1)"

# The manifest an update actually compares. It lagging behind plugin.json is
# not a cosmetic mismatch — it is the release not happening.
assert_eq "the Claude marketplace manifest ships $shipped" \
  "$shipped" "$(ver_of .claude-plugin/marketplace.json)"

assert_eq "the Cursor plugin manifest ships $shipped" \
  "$shipped" "$(ver_of .cursor-plugin/plugin.json)"

# .cursor-plugin/marketplace.json has never carried a version of its own, and
# is not required to grow one. Asserted conditionally rather than either way:
# demanding its absence would fail the commit that legitimately adds it, and
# ignoring it would let a third stale number appear with nothing watching.
cursor_market="$(ver_of .cursor-plugin/marketplace.json)"
if [[ -n "$cursor_market" ]]; then
  assert_eq "the Cursor marketplace manifest, having a version, ships $shipped" \
    "$shipped" "$cursor_market"
else
  ok "the Cursor marketplace manifest carries no version of its own, as before"
fi

# The changelog entry for the shipped version is asserted in test-site.sh,
# against the built site rather than the source — a release that moves
# plugin.json and forgets the changelog publishes a page whose newest entry is
# the release before it. Not repeated here.

summary
