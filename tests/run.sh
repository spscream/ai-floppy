#!/usr/bin/env bash
# Run every tests/test-*.sh under the bash this runner was itself started with.
# Usage: bash tests/run.sh [name-fragment]
#
# `$BASH`, not a bare `bash`: the whole point of running this on macOS is to
# exercise bash 3.2, and a bare `bash` resolves through PATH — where a Homebrew
# bash 5 normally sits ahead of /bin/bash. So `/bin/bash tests/run.sh` handed
# every test to bash 5 anyway, and a run meant to prove portability proved
# nothing. $BASH is the path of the interpreter actually executing this file,
# so the choice made on the command line propagates to each test.
set -uo pipefail
cd "$(dirname "$0")/.."
BASH_UNDER_TEST="${BASH:-bash}"
printf 'bash: %s (%s)\n\n' "$BASH_UNDER_TEST" "${BASH_VERSION:-?}"
rc=0
for t in tests/test-*.sh; do
  case "${1:-}" in "") ;; *) case "$t" in *"$1"*) ;; *) continue;; esac;; esac
  printf '== %s\n' "$(basename "$t")"
  "$BASH_UNDER_TEST" "$t" || rc=1
done
exit $rc
