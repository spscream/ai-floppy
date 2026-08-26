#!/usr/bin/env bash
# The shim notices that it is not the same file as the plugin's own copy.
#
# Kept out of test-shim.sh because it is about a different question: that file
# asks where the plugin is resolved from, this one asks whether the copy doing
# the resolving is current. They fail for unrelated reasons.
set -uo pipefail
cd "$(dirname "$0")/.."
ROOT="$(pwd -P)"
. tests/lib.sh

# A plugin root that is a faithful copy of this checkout's shim and scripts —
# what an up-to-date install looks like.
#
# Since 0.14.0 that means the dispatcher and the config parser too: the shim
# only locates the plugin and execs `scripts/run`, so a fake root without one
# is not an install at all and every case below would fail for that reason
# instead of the one it is about.
fake_plugin() { # -> path
  local p; p="$(cd "$(mktemp -d)" && pwd -P)"
  mkdir -p "$p/scripts" "$p/shim"
  cp scripts/memory-lint.sh scripts/run scripts/lib-config.sh "$p/scripts/"
  cp shim/run "$p/shim/run"
  printf '%s\n' "$p"
}

# ---------- an identical copy says nothing ----------
# The common case, and the one a noisy check would ruin: a warning printed on
# every call of a correctly installed repository is a warning nobody reads.
plug="$(fake_plugin)"
repo="$(sandbox)"
cp shim/run "$repo/.floppy/run"
out="$(cd "$repo" && AI_FLOPPY_HOME="$plug" CLAUDE_PLUGIN_ROOT= bash .floppy/run env 2>&1)"
case "$out" in
  *"differs from the installed plugin"*) fail "identical copy is silent" "no warning" "$out" ;;
  *) ok "identical copy is silent" ;;
esac

# ---------- a copy that drifted is named, and the verb still runs ----------
# A warning, not a gate: an old shim usually still works, and refusing to run
# would turn a nudge into an outage on the machine that pulled first.
printf '\n# a local edit that the plugin does not have\n' >> "$repo/.floppy/run"
out="$(cd "$repo" && AI_FLOPPY_HOME="$plug" CLAUDE_PLUGIN_ROOT= bash .floppy/run env 2>&1)"
rc=$?
assert_contains "a drifted copy is named"          "differs from the installed plugin" "$out"
assert_contains "the hint is a bare cp"            "cp \"$plug/shim/run\"" "$out"
assert_contains "the hint names this repository"   "$repo/.floppy/run"     "$out"
assert_contains "the verb still produced its output" "FLOPPY_REPO=$repo"   "$out"
assert_eq       "a drifted copy does not fail the call" "0" "$rc"

# The warning goes to stderr: stdout of a verb is read by other things, and a
# nudge must not land in the middle of a report.
stdout_only="$(cd "$repo" && AI_FLOPPY_HOME="$plug" CLAUDE_PLUGIN_ROOT= bash .floppy/run env 2>/dev/null)"
case "$stdout_only" in
  *"differs from the installed plugin"*) fail "the warning is on stderr" "not on stdout" "$stdout_only" ;;
  *) ok "the warning is on stderr" ;;
esac

# ---------- nothing to compare against is not a warning ----------
# An install layout that flattens shim/ away must not produce a permanent
# false alarm — a check that cries wolf on a healthy install gets muted.
noshim="$(cd "$(mktemp -d)" && pwd -P)"
mkdir -p "$noshim/scripts"
cp scripts/memory-lint.sh "$noshim/scripts/"
out="$(cd "$repo" && AI_FLOPPY_HOME="$noshim" CLAUDE_PLUGIN_ROOT= bash .floppy/run env 2>&1)"
case "$out" in
  *"differs from the installed plugin"*) fail "a plugin with no shim/ is silent" "no warning" "$out" ;;
  *) ok "a plugin with no shim/ is silent" ;;
esac

# ---------- the plugin's own copy does not warn about itself ----------
# True while developing the plugin, where the shim being run IS the source.
selfrepo="$(sandbox)"
cp shim/run "$selfrepo/.floppy/run"
out="$(cd "$selfrepo" && AI_FLOPPY_HOME="$ROOT" CLAUDE_PLUGIN_ROOT= bash .floppy/run env 2>&1)"
case "$out" in
  *"differs from the installed plugin"*) fail "the checkout's own shim is silent" "no warning" "$out" ;;
  *) ok "the checkout's own shim is silent" ;;
esac

rm -rf "$plug" "$repo" "$noshim" "$selfrepo"
summary
