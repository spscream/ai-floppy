#!/usr/bin/env bash
# CRITICAL 1: the interpreter this suite claims to test is the one the scripts
# actually run on. The macOS job is named macos-bash-3-2 and its whole purpose
# is bash 3.2.57; until 2026-09-08 it tested 3.2 for the test files and bash 5
# for every script they invoked, and the badge could not tell the difference.
#
# Four levels of indirection stand between the command line and a verb:
#   1. the workflow calls /bin/bash tests/run.sh          — always was pinned
#   2. run.sh hands each test file "$BASH"                 — pinned since 0.16
#   3. a test file calls `bash .floppy/run ...`            — ~180 call sites
#   4. shim/run and scripts/run `exec bash` the next file  — in the product
# Levels 3 and 4 are covered by run.sh putting a `bash` that IS the interpreter
# under test at the front of PATH, and by both execs using "$BASH". This file
# is what notices when either stops holding.
set -uo pipefail
cd "$(dirname "$0")/.."
. tests/lib.sh

# ---------- level 3: a bare `bash` is the interpreter under test ----------
# $BASH_VERSION here is the interpreter running THIS file, which run.sh chose.
# `bash -c` resolves through PATH. Equal means the pin took.
#
# Run directly rather than through tests/run.sh there is no pin, and on a mac
# with Homebrew ahead of /bin/bash this fails — correctly, and with both
# versions named. It is deliberately not gated on a marker from run.sh: a check
# that skips itself when its own setup is missing is a check that can stop
# checking without anyone noticing, which is the whole defect this file exists
# for.
via_path="$(bash -c 'printf %s "${BASH_VERSION:-none}"')"
assert_eq "a bare \`bash\` resolves to the interpreter under test" \
  "${BASH_VERSION:-none}" "$via_path"

# ---------- level 4: both dispatchers pass their interpreter on ----------
# Behavioural, not textual: build a plugin whose `lint` verb reports the
# interpreter it was given, then call the shim with a SECOND bash and require
# the verb to report that second one. A dispatcher that says `exec bash` sends
# back whatever PATH offers, which is the pinned one, and the assert fails.
#
# It needs two different bashes on the machine. The macOS runner has exactly
# that — /bin/bash 3.2 and Homebrew 5.x — which is the environment the defect
# lived in. Where only one exists the check says so rather than pretending.
# The inventory goes in the log, not in an assumption — the knowledge note this
# work started from asks for exactly that, and this file is where it belongs.
# What it is for: "no second bash was found" and "the second bash was not
# looked for" read identically in a skip line, and only one of them is a
# reason to trust the run.
printf '  bash on this machine:\n'
for cand in /bin/bash /usr/bin/bash /usr/local/bin/bash /opt/homebrew/bin/bash; do
  if [[ -x "$cand" ]]; then
    printf '    %s -> %s\n' "$cand" "$("$cand" -c 'printf %s "$BASH_VERSION"' 2>/dev/null || echo '?')"
  else
    printf '    %s -> absent\n' "$cand"
  fi
done
printf '    PATH ahead of the pin: %s\n' "${PATH#*:}" | cut -c1-200

other=""
for cand in /bin/bash /usr/bin/bash /usr/local/bin/bash /opt/homebrew/bin/bash; do
  [[ -x "$cand" ]] || continue
  v="$("$cand" -c 'printf %s "$BASH_VERSION"' 2>/dev/null)"
  [[ -n "$v" && "$v" != "${BASH_VERSION:-}" ]] && { other="$cand"; other_v="$v"; break; }
done

if [[ -z "$other" ]]; then
  printf '  skip only one bash on this machine: the two-hop interpreter check\n'
else
  plug="$(mktemp -d)"; repo="$(mktemp -d)"
  trap 'rm -rf "$plug" "$repo"' EXIT
  mkdir -p "$plug/scripts"
  # The real dispatcher and config parser, so the hops under test are the ones
  # that ship — only the verb at the end is a stub.
  cp scripts/run scripts/lib-config.sh "$plug/scripts/"
  printf '#!/usr/bin/env bash\nprintf "verb-ran-on %%s\\n" "${BASH_VERSION:-none}"\n' \
    > "$plug/scripts/memory-lint.sh"
  ( cd "$repo" && git init -q . && mkdir -p .floppy && printf 'memory_dir=.agent-memory\n' > .floppy/config )
  cp shim/run "$repo/.floppy/run"

  out="$(cd "$repo" && AI_FLOPPY_HOME="$plug" CLAUDE_PLUGIN_ROOT= "$other" .floppy/run lint 2>&1)"
  assert_contains "the shim and the dispatcher pass \`$other\` through to the verb" \
    "verb-ran-on $other_v" "$out"
fi

summary
