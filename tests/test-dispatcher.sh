#!/usr/bin/env bash
# `scripts/run` became the entry point in 0.26.0, and two things it does had
# nothing watching them. It derives FLOPPY_ROOT from its own path — the whole
# reason a skill can call it without a variable — and it hands every verb the
# string their hints paste back at the reader (FLOPPY_RUN). The rest of the
# suite calls the dispatcher by an absolute path and never reads either, so
# "what stays green if this is not wired?" answered "all of it".
#
# Two of the cases below are regressions, not inventions: an exported CDPATH
# made `cd` print its target into the command substitution and FLOPPY_ROOT
# came out two lines long (measured 2026-09-25, 3/3), and a plugin under a
# path with a space printed a hint that could not be pasted back.
set -uo pipefail
cd "$(dirname "$0")/.."
. tests/lib.sh
ROOT="$(pwd)"

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

repo="$(sandbox)"

# ---------- 1. no variable is needed, and none is believed ----------
out="$(cd "$repo" && env -u FLOPPY_ROOT -u FLOPPY_RUN bash "$ROOT/scripts/run" env 2>&1)"; rc=$?
assert_rc       "env runs with FLOPPY_ROOT unset"          0 "$rc"
assert_contains "and roots itself where it was called from" \
  "FLOPPY_ROOT=$ROOT" "$out"
assert_contains "FLOPPY_RUN names the dispatcher that answered" \
  "FLOPPY_RUN=bash $ROOT/scripts/run" "$out"

# A FLOPPY_ROOT naming another copy must not win: the verbs would run out of
# that copy while this one dispatches — shim/run's "a script that had just
# been fixed was reported as still broken".
out="$(cd "$repo" && FLOPPY_ROOT=/nonexistent bash "$ROOT/scripts/run" env 2>&1)"
assert_contains "an inherited FLOPPY_ROOT is overridden, not honoured" \
  "FLOPPY_ROOT=$ROOT" "$out"

# ---------- 2. CDPATH does not leak into the derived root ----------
# CLAUDE.md documents the relative form `bash scripts/run status`, and CDPATH
# is only consulted for a path that is neither absolute nor ./-prefixed — so
# this is the one spelling that was exposed.
out="$(cd "$ROOT" && CDPATH=".:$work" bash scripts/run env 2>&1)"; rc=$?
assert_rc       "a relative call under CDPATH still runs"  0 "$rc"
assert_contains "and its root is one line, not two"        "FLOPPY_ROOT=$ROOT" "$out"
case "$out" in
  *"No such file or directory"*)
    fail "CDPATH does not break the config parser" "no such error" "$out" ;;
  *)
    ok   "CDPATH does not break the config parser" ;;
esac

# ---------- 3. a hint is pasteable from a path with a space ----------
plugin="$work/pl ugin"
mkdir -p "$plugin"
cp -R "$ROOT/scripts" "$plugin/scripts"

out="$(cd "$repo" && bash "$plugin/scripts/run" env 2>&1)"
assert_contains "a spaced plugin path is quoted in FLOPPY_RUN" \
  "FLOPPY_RUN=bash \"$plugin/scripts/run\"" "$out"

# ---------- 4. a verb reached directly still names a real file ----------
# The fallback in each verb, for the calls that do not come through the
# dispatcher. It is what prints when a test — or a person — runs the file.
# Quoted unconditionally here, unlike the dispatcher's own hint: this branch
# is only reached by a direct call, and there the noise costs less than a hint
# that cannot be pasted back.
out="$(cd "$repo" && env -u FLOPPY_RUN bash "$ROOT/scripts/memory-heat.sh" 2>&1)"
assert_contains "a direct verb call names the dispatcher by path" \
  "bash \"$ROOT/scripts/run\" heat" "$out"

out="$(cd "$repo" && env -u FLOPPY_RUN bash "$plugin/scripts/memory-heat.sh" 2>&1)"
assert_contains "and the path with a space is still one argument" \
  "bash \"$plugin/scripts/run\" heat" "$out"

# The wrap rite prints the largest group of these hints, and a hint with an
# empty $floppy_run in it reads as `  check <file>` — a line that looks like a
# command and is not one. Measured 2026-09-25: blanking floppy_run in all
# eight verbs turned only two assertions red, both about memory wiring.
out="$(cd "$repo" && bash "$ROOT/scripts/run" check 2>&1)"
assert_contains "the wrap hint carries a runnable command" \
  "bash $ROOT/scripts/run check <file>" "$out"

summary
