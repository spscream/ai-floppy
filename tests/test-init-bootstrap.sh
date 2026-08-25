#!/usr/bin/env bash
# CRITICAL 1 regression: skills/init/SKILL.md step 2 tells the agent to run a
# small bash snippet that locates the plugin root before .floppy/run exists
# to do it. That snippet is not sourced from anywhere (see shim/run's comment
# on the duplication) — it is copied by hand into the markdown, so nothing
# guards it from drifting out of sync or being wrong in the first place.
#
# This test extracts the literal fenced code block from the skill file and
# runs it for real, in the three situations the search has to cover: the dev
# override, the plugin-cache fallback with CLAUDE_PLUGIN_ROOT unset (the
# scenario CRITICAL 1 was filed about), and nothing resolving at all. Testing
# the extracted block — not a hand-copied third version of the same nine
# lines — is what makes this catch drift instead of just agreeing with itself.
set -uo pipefail
cd "$(dirname "$0")/.."
. tests/lib.sh
ROOT="$(pwd)"

skill="skills/init/SKILL.md"
block="$(sed -n '/^```bash$/,/^```$/p' "$skill" | sed '1d;$d')"
assert_eq "extracted a non-empty snippet from $skill" "0" "$([[ -n "$block" ]] && echo 0 || echo 1)"
assert_contains "snippet contains the three-branch search" "CLAUDE_PLUGIN_ROOT" "$block"
assert_contains "snippet contains the cache fallback"      "plugins/cache" "$block"

# Fill in the two placeholders the way the agent would after asking the
# human, positionally (they need distinct values: a dir, then a language).
# Two plain (non-"g") substitutions piped in sequence, each eating the next
# remaining occurrence — `0,/re/` addressing is a GNU sed extension the
# macOS /usr/bin/sed target of this repo does not have.
filled="$(printf '%s\n' "$block" \
  | sed 's/<their answer>/.agent-memory/' \
  | sed 's/<their answer>/en/')"

# ---------- 1. AI_FLOPPY_HOME set, CLAUDE_PLUGIN_ROOT unset ----------
repo1="$(sandbox)"; rmdir "$repo1/.floppy" 2>/dev/null || true
out1="$(cd "$repo1" && CLAUDE_PLUGIN_ROOT= AI_FLOPPY_HOME="$ROOT" eval "$filled" 2>&1)"; rc1=$?
assert_rc       "AI_FLOPPY_HOME branch: exits 0"        0 "$rc1"
assert_eq       "AI_FLOPPY_HOME branch: shim placed"    "0" "$([[ -f "$repo1/.floppy/run" ]] && echo 0 || echo 1)"
rm -rf "$repo1"

# ---------- 2. neither var set, only the plugin cache has a checkout ----------
# This is the exact scenario CRITICAL 1 is about: a normal install, no dev
# override, and (per the finding) no guarantee CLAUDE_PLUGIN_ROOT is set
# while a skill runs.
fake_home="$(mktemp -d)"
cache_dir="$fake_home/.claude/plugins/cache/example/floppy/0.1.0"
mkdir -p "$cache_dir"
cp -R "$ROOT"/. "$cache_dir"/ 2>/dev/null
rm -rf "$cache_dir/.git"

repo2="$(sandbox)"; rmdir "$repo2/.floppy" 2>/dev/null || true
out2="$(cd "$repo2" && HOME="$fake_home" AI_FLOPPY_HOME= CLAUDE_PLUGIN_ROOT= eval "$filled" 2>&1)"; rc2=$?
assert_rc       "cache-only branch: exits 0"             0 "$rc2"
assert_eq       "cache-only branch: shim placed"         "0" "$([[ -f "$repo2/.floppy/run" ]] && echo 0 || echo 1)"
rm -rf "$repo2" "$fake_home"

# ---------- 3. nothing resolves: loud failure naming the install command ----------
empty_home="$(mktemp -d)"
repo3="$(sandbox)"; rmdir "$repo3/.floppy" 2>/dev/null || true
out3="$(cd "$repo3" && HOME="$empty_home" AI_FLOPPY_HOME= CLAUDE_PLUGIN_ROOT= eval "$filled" 2>&1)"; rc3=$?
assert_rc       "nothing resolves: exits nonzero"        1 "$rc3"
assert_contains "nothing resolves: names the install command" "plugin install floppy" "$out3"
assert_eq       "nothing resolves: does not create .floppy/run" "1" "$([[ -f "$repo3/.floppy/run" ]] && echo 0 || echo 1)"
rm -rf "$repo3" "$empty_home"

summary
