#!/usr/bin/env bash
# CRITICAL 2: README.md and LICENSE exist and cover what they're required to.
# Structural, like test-skills.sh — there is no behaviour to run, only shape
# to guard: the required sections stay named, and every config key the shim
# actually reads (shim/run's cfg_get calls) is documented in the README, not
# just some of them.
set -uo pipefail
cd "$(dirname "$0")/.."
. tests/lib.sh

assert_eq "README.md exists" "0" "$([[ -f README.md ]] && echo 0 || echo 1)"
assert_eq "LICENSE exists"   "0" "$([[ -f LICENSE   ]] && echo 0 || echo 1)"

readme="$(cat README.md 2>/dev/null || true)"
license="$(cat LICENSE 2>/dev/null || true)"

assert_contains "LICENSE is MIT"                 "MIT License" "$license"
assert_contains "README states the license"      "MIT"         "$readme"

assert_contains "README covers install: marketplace add" "plugin marketplace add" "$readme"
assert_contains "README covers install: plugin install"  "plugin install"        "$readme"
assert_contains "README covers the Cursor equivalent"    "Cursor"                "$readme"
assert_contains "README covers floppy:init"               "floppy:init"           "$readme"

for skill in init agent-memory start workstatus wrap; do
  assert_contains "README names skill floppy:$skill" "floppy:$skill" "$readme"
done

# Every key shim/run's cfg_get resolves must be documented — a key read but
# never documented is exactly the class of defect this fix wave was about.
keys="$(grep -oE 'cfg_get [a-z_]+' shim/run | awk '{print $2}' | sort -u)"
while IFS= read -r key; do
  [[ -z "$key" ]] && continue
  assert_contains "README documents config key: $key" "\`$key\`" "$readme"
done <<< "$keys"

assert_contains "README explains quota.lock is measured per project" "measur" "$readme"
case "$readme" in
  *"never copied"*) ok "README states quota.lock is never copied between projects" ;;
  *) fail "README states quota.lock is never copied between projects" "never copied" "$readme" ;;
esac

summary
