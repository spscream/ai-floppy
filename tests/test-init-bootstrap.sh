#!/usr/bin/env bash
# CRITICAL 1 regression: skills/init/SKILL.md step 2 tells the agent to run a
# small bash snippet that locates the plugin root before .floppy/run exists
# to do it. That snippet is not sourced from anywhere (see shim/run's comment
# on the duplication) — it is copied by hand into the markdown, so nothing
# guards it from drifting out of sync or being wrong in the first place.
#
# This test extracts the literal fenced code block from the skill file and
# runs it for real, in the five situations the search has to cover: the dev
# override, the Claude plugin-cache fallback with CLAUDE_PLUGIN_ROOT unset (the
# scenario CRITICAL 1 was filed about), Cursor's local symlink, Cursor's
# SHA-named cache, and nothing resolving at all. Testing the extracted block —
# not a hand-copied third version of the same nine lines — is what makes this
# catch drift instead of just agreeing with itself.
#
# The two Cursor cases were added 2026-09-09, after an audit found the block
# had been carrying four of the shim's six branches for as long as it had
# existed: it stopped at the Claude cache. A Cursor user whose harness had not
# exported CURSOR_PLUGIN_ROOT was told "plugin not found" by `init` for a
# plugin `.floppy/run` resolves through cursor_local — the branch that answers
# on the owner's machine, where the Cursor cache directory exists and is empty.
# Nothing failed, because the three cases here never entered a Cursor layout.
set -uo pipefail
cd "$(dirname "$0")/.."
. tests/lib.sh
ROOT="$(pwd)"

skill="skills/init/SKILL.md"
block="$(sed -n '/^```bash$/,/^```$/p' "$skill" | sed '1d;$d')"
assert_eq "extracted a non-empty snippet from $skill" "0" "$([[ -n "$block" ]] && echo 0 || echo 1)"
assert_contains "snippet contains the harness variables"  "CLAUDE_PLUGIN_ROOT" "$block"
assert_contains "snippet contains the cache fallback"      "plugins/cache" "$block"
# Named branches, not just the string "plugins/cache": both Cursor layouts are
# reachable only through these two variables, and their absence is exactly the
# drift this file exists to catch.
assert_contains "snippet reaches Cursor's local symlink"  "cursor_local" "$block"
assert_contains "snippet reaches Cursor's cache"          "cursor_cache" "$block"

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

# ---------- 3. Cursor's local symlink, with no Claude cache in reach ----------
# Symlinked rather than copied, unlike case 2: the copy there is what proves a
# real cache directory with real files resolves, and repeating it twice more
# would only repeat the cost. A symlink to this checkout is enough to prove the
# branch is entered at all, which is what was missing.
cursor_home="$(mktemp -d)"
mkdir -p "$cursor_home/.cursor/plugins/local"
ln -s "$ROOT" "$cursor_home/.cursor/plugins/local/floppy"

repo4="$(sandbox)"; rmdir "$repo4/.floppy" 2>/dev/null || true
out4="$(cd "$repo4" && HOME="$cursor_home" AI_FLOPPY_HOME= CLAUDE_PLUGIN_ROOT= CURSOR_PLUGIN_ROOT= eval "$filled" 2>&1)"; rc4=$?
assert_rc       "cursor local branch: exits 0"           0 "$rc4"
assert_eq       "cursor local branch: shim placed"       "0" "$([[ -f "$repo4/.floppy/run" ]] && echo 0 || echo 1)"
rm -rf "$repo4" "$cursor_home"

# ---------- 4. Cursor's cache, whose last segment is a commit SHA ----------
cursor_home2="$(mktemp -d)"
mkdir -p "$cursor_home2/.cursor/plugins/cache/floppy/floppy"
ln -s "$ROOT" "$cursor_home2/.cursor/plugins/cache/floppy/floppy/ed18232fd3b616d570a707fb8464b678b8542dbf"

repo5="$(sandbox)"; rmdir "$repo5/.floppy" 2>/dev/null || true
out5="$(cd "$repo5" && HOME="$cursor_home2" AI_FLOPPY_HOME= CLAUDE_PLUGIN_ROOT= CURSOR_PLUGIN_ROOT= eval "$filled" 2>&1)"; rc5=$?
assert_rc       "cursor cache branch: exits 0"           0 "$rc5"
assert_eq       "cursor cache branch: shim placed"       "0" "$([[ -f "$repo5/.floppy/run" ]] && echo 0 || echo 1)"
rm -rf "$repo5" "$cursor_home2"

# ---------- 5. nothing resolves: loud failure naming the install command ----------
empty_home="$(mktemp -d)"
repo3="$(sandbox)"; rmdir "$repo3/.floppy" 2>/dev/null || true
out3="$(cd "$repo3" && HOME="$empty_home" AI_FLOPPY_HOME= CLAUDE_PLUGIN_ROOT= eval "$filled" 2>&1)"; rc3=$?
assert_rc       "nothing resolves: exits nonzero"        1 "$rc3"
assert_contains "nothing resolves: names the install command" "plugin install floppy" "$out3"
assert_eq       "nothing resolves: does not create .floppy/run" "1" "$([[ -f "$repo3/.floppy/run" ]] && echo 0 || echo 1)"
rm -rf "$repo3" "$empty_home"

summary
