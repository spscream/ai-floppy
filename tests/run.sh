#!/usr/bin/env bash
# Run every tests/test-*.sh under the bash that ships with this machine.
# Usage: bash tests/run.sh [name-fragment]
set -uo pipefail
cd "$(dirname "$0")/.."
rc=0
for t in tests/test-*.sh; do
  case "${1:-}" in "") ;; *) case "$t" in *"$1"*) ;; *) continue;; esac;; esac
  printf '== %s\n' "$(basename "$t")"
  bash "$t" || rc=1
done
exit $rc
