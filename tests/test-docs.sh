#!/usr/bin/env bash
# CRITICAL 2: the user documentation covers what it is required to, in the file
# that is supposed to cover it. Structural, like test-skills.sh — there is no
# behaviour to run, only shape to guard: every config key the plugin actually
# reads (scripts/lib-config.sh's cfg_get calls) is documented on the config
# page, the install commands are on the install page, and the landing page
# keeps enough to install without leaving GitHub.
set -uo pipefail
cd "$(dirname "$0")/.."
. tests/lib.sh

assert_eq "README.md exists" "0" "$([[ -f README.md ]] && echo 0 || echo 1)"
assert_eq "LICENSE exists"   "0" "$([[ -f LICENSE   ]] && echo 0 || echo 1)"

readme="$(cat README.md 2>/dev/null || true)"
license="$(cat LICENSE 2>/dev/null || true)"

# Each answer is asserted against the file that now holds it, not against the
# documentation as a whole. A key documented in the wrong place used to pass;
# it no longer does, because where an answer lives is what a reader depends on.
install_doc="$(cat docs/guide/install.md 2>/dev/null || true)"
config_doc="$(cat docs/guide/config.md  2>/dev/null || true)"
skills_doc="$(cat docs/guide/skills.md  2>/dev/null || true)"

# A missing file makes every `assert_contains` against it fail, which is correct
# but reports the same defect three times over. Named once, here.
for f in docs/guide/install.md docs/guide/config.md docs/guide/skills.md; do
  assert_eq "$f exists" "0" "$([[ -f "$f" ]] && echo 0 || echo 1)"
done

assert_contains "LICENSE is MIT"            "MIT License" "$license"
assert_contains "README states the license" "MIT"         "$readme"

assert_contains "install page covers: marketplace add" "plugin marketplace add" "$install_doc"
assert_contains "install page covers: plugin install"  "plugin install"        "$install_doc"
assert_contains "install page covers the Cursor equivalent" "Cursor"           "$install_doc"

# The landing page keeps a quick start, so the two commands appear there too.
# Asserted separately: they serve different readers, and one of the two copies
# going missing is a defect either way.
assert_contains "README quick start keeps: marketplace add" "plugin marketplace add" "$readme"
assert_contains "README quick start keeps: plugin install"  "plugin install"        "$readme"

for skill in init agent-memory start workstatus wrap; do
  assert_contains "skills page names skill \`$skill\`" "\`$skill\`" "$skills_doc"
  assert_contains "README names skill \`$skill\`"      "\`$skill\`" "$readme"
done

# Claude Code namespaces skills by plugin name (floppy:start); Cursor lists
# them flat (/start). The difference is stated exactly once, on the skills
# page — everywhere else the bare name, since that's the only form true in
# both harnesses. Counted across both files: moving the explanation from one
# to the other must not be able to produce two copies of it.
floppy_prefixed_count="$(grep -hoE 'floppy:(init|agent-memory|start|workstatus|wrap)' \
  README.md docs/guide/skills.md 2>/dev/null | wc -l | tr -d ' ')"
assert_eq "the floppy: prefix form appears exactly once (the explanation)" "1" "$floppy_prefixed_count"

# Every key the config parser resolves must be documented — a key read but
# never documented is exactly the class of defect this fix wave was about.
# The parser moved into the plugin in 0.14.0 (scripts/lib-config.sh); reading
# it from shim/run still "passed" for a while afterwards, silently, because an
# empty key list makes this loop assert nothing at all.
keys="$(grep -oE 'cfg_get [a-z_]+' scripts/lib-config.sh | awk '{print $2}' | sort -u)"
assert_eq "the config parser is where this test thinks it is" "0" \
  "$([[ -n "$keys" ]] && echo 0 || echo 1)"
while IFS= read -r key; do
  [[ -z "$key" ]] && continue
  assert_contains "config page documents key: $key" "\`$key\`" "$config_doc"
done <<< "$keys"

assert_contains "config page explains quota.lock is measured per project" "measur" "$config_doc"
case "$config_doc" in
  *"never copied"*) ok "config page states quota.lock is never copied between projects" ;;
  *) fail "config page states quota.lock is never copied between projects" "never copied" "$config_doc" ;;
esac

summary
