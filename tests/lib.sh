# Test helpers. bash 3.2, no dependencies: no bats, no python.

# The suite must test THIS checkout, and every test file says so by passing
# AI_FLOPPY_HOME="$ROOT" to the calls it makes. That is not enough on a
# developer's machine: init.sh passes ${AI_FLOPPY_HOME:-<its own root>} down to
# the store verb it invokes, so an AI_FLOPPY_HOME exported in the shell — which
# is how a person points the plugin at a working checkout — wins inside that
# subcall and the init-with-store cases silently exercise the OTHER checkout.
# Measured 2026-09-25 in a git worktree of this repository: `init leaves a
# symlink` passed against code that no longer creates one, because the symlink
# was created by the plugin the environment named. Inherited environment is not
# an input to this suite.
unset AI_FLOPPY_HOME CLAUDE_PLUGIN_ROOT CURSOR_PLUGIN_ROOT

_pass=0; _fail=0

ok()   { _pass=$((_pass+1)); printf '  ok   %s\n' "$1"; }
fail() { _fail=$((_fail+1)); printf '  FAIL %s\n     expected: %s\n     actual:   %s\n' "$1" "$2" "$3"; }

assert_eq() { # name expected actual
  if [[ "$2" == "$3" ]]; then ok "$1"; else fail "$1" "$2" "$3"; fi
}
assert_contains() { # name needle haystack
  case "$3" in *"$2"*) ok "$1";; *) fail "$1" "contains: $2" "$3";; esac
}
assert_rc() { # name expected_rc actual_rc
  assert_eq "$1" "$2" "$3"
}

# A throwaway git repository with a .floppy/ in it. Echoes its path.
sandbox() {
  local d; d="$(cd "$(mktemp -d)" && pwd -P)"
  git -C "$d" init -q -b main
  mkdir -p "$d/.floppy"
  printf '%s\n' "$d"
}

summary() {
  printf '\n%d passed, %d failed\n' "$_pass" "$_fail"
  [[ "$_fail" -eq 0 ]]
}
