#!/usr/bin/env bash
set -uo pipefail
cd "$(dirname "$0")/.."
. tests/lib.sh
ROOT="$(pwd)"

repo="$(sandbox)"; cp shim/run "$repo/.floppy/run"

# 1. acquire, then immediately try to acquire again from the same sandbox:
# the second attempt must refuse, and must not claim the lock is abandoned.
# This is the assertion that failed against the pre-fix stat -c script (see
# report): a lock acquired one instant earlier read as ~57 years old there,
# because `stat -c %Y` does not exist on macOS and the `|| echo 0` fallback
# made every mtime read as the epoch.
out1="$(cd "$repo" && AI_FLOPPY_HOME="$ROOT" bash .floppy/run lock acquire "first" 2>&1)"; rc1=$?
assert_rc       "first acquire succeeds"            0 "$rc1"
assert_contains "first acquire reports ok"           "ok lock acquired" "$out1"

out2="$(cd "$repo" && AI_FLOPPY_HOME="$ROOT" bash .floppy/run lock acquire "second" 2>&1)"; rc2=$?
assert_rc       "second immediate acquire refuses"  1 "$rc2"
assert_contains "second acquire names the holder"    "another session holds the wrap lock" "$out2"
case "$out2" in
  *abandoned*) fail "second acquire does not claim abandoned" "no 'abandoned'" "$out2" ;;
  *)           ok   "second acquire does not claim abandoned" ;;
esac

# 2. status on a fresh lock reports it as held, not as abandoned.
out3="$(cd "$repo" && AI_FLOPPY_HOME="$ROOT" bash .floppy/run lock status 2>&1)"; rc3=$?
assert_rc       "status on fresh lock reports held (rc)" 1 "$rc3"
assert_contains "status on fresh lock says held"          "held, younger than" "$out3"
case "$out3" in
  *abandoned*) fail "status on fresh lock does not say abandoned" "no 'abandoned'" "$out3" ;;
  *)           ok   "status on fresh lock does not say abandoned" ;;
esac

out4="$(cd "$repo" && AI_FLOPPY_HOME="$ROOT" bash .floppy/run lock release 2>&1)"
assert_contains "release clears the lock" "ok lock released" "$out4"

# 3. a lock whose owner file is genuinely old IS taken over, and the takeover
# is announced. Backdate with touch -t rather than sleeping.
out5="$(cd "$repo" && AI_FLOPPY_HOME="$ROOT" bash .floppy/run lock acquire "stale-owner" 2>&1)"
assert_contains "setup: stale-owner lock acquired" "ok lock acquired" "$out5"
gitdir="$(cd "$repo" && git rev-parse --absolute-git-dir)"
owner="$gitdir/wrap.lock/owner"
old_stamp="$(date -v-60M +%Y%m%d%H%M.%S 2>/dev/null || date -d '60 minutes ago' +%Y%m%d%H%M.%S)"
touch -t "$old_stamp" "$owner"

out6="$(cd "$repo" && AI_FLOPPY_HOME="$ROOT" bash .floppy/run lock acquire "new-owner" 2>&1)"; rc6=$?
assert_rc       "stale lock is taken over (rc)"     0 "$rc6"
assert_contains "takeover is announced"              "Taking it over" "$out6"
assert_contains "takeover names the previous owner"  "was: owner=stale-owner" "$out6"

out7="$(cd "$repo" && AI_FLOPPY_HOME="$ROOT" bash .floppy/run lock status 2>&1)"
assert_contains "status after takeover names the new owner" "owner=new-owner" "$out7"

rm -rf "$repo"
summary
