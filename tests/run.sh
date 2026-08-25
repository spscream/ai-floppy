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

# ---------- how many files run at once ----------
# Measured 2026-08-25, this suite on a mac: 69.5s of wall time serially across
# 16 files, and three of them — memory-dirs 15.3s, wrap-flow 13.3s,
# external-memory 10.6s — are 56% of that. Each sits at 42-78% CPU: they are
# waiting on `git init`, `clone` and `push` spawning, not computing. Files are
# independent by construction (every one builds its own sandbox under
# `mktemp -d` and overrides HOME before any verb that clones), so running them
# side by side changes no result.
#
# The floor is the slowest single file, so no job count takes this below ~15s.
# Set FLOPPY_TEST_JOBS=1 to get the serial run back: output then streams live
# in file order, which is what you want while chasing one failure.
njobs="${FLOPPY_TEST_JOBS:-}"
if [[ -z "$njobs" ]]; then
  njobs="$( { sysctl -n hw.ncpu 2>/dev/null || nproc 2>/dev/null; } | head -1 )"
  case "$njobs" in ''|*[!0-9]*) njobs=4 ;; esac
fi

selected=()
for t in tests/test-*.sh; do
  case "${1:-}" in "") ;; *) case "$t" in *"$1"*) ;; *) continue;; esac;; esac
  selected+=("$t")
done
if [[ ${#selected[@]} -eq 0 ]]; then
  printf 'no test file matches %s\n' "${1:-*}" >&2
  exit 2
fi

# After the selection, not before: one file selected runs serially whatever the
# job count says, and a header claiming twelve jobs for one file is a small lie
# in the first line of every filtered run.
[[ ${#selected[@]} -lt "$njobs" ]] && njobs=${#selected[@]}
printf 'bash: %s (%s), %s job(s)\n\n' "$BASH_UNDER_TEST" "${BASH_VERSION:-?}" "$njobs"

rc=0

# ---------- serial: one file at a time, output as it happens ----------
if [[ "$njobs" -le 1 || ${#selected[@]} -eq 1 ]]; then
  for t in "${selected[@]}"; do
    printf '== %s\n' "$(basename "$t")"
    "$BASH_UNDER_TEST" "$t" || rc=1
  done
  exit $rc
fi

# ---------- parallel: launch up to njobs, print in file order ----------
# Output goes to one file per test and is printed after the fact, in the order
# the files were selected. Interleaved live output would be unreadable, and an
# order that depends on which test happened to finish first would make two runs
# of a green suite produce different text.
#
# No `wait -n` and no associative arrays: this runner is itself executed by
# bash 3.2 on the macOS job, where neither exists.
outdir="$(mktemp -d)"
trap 'rm -rf "$outdir"' EXIT

pids=()
i=0
for t in "${selected[@]}"; do
  # Block before launching, not after, so the cap is a cap rather than a cap+1.
  while [[ "$( jobs -pr | wc -l | tr -d ' ' )" -ge "$njobs" ]]; do sleep 0.05; done
  "$BASH_UNDER_TEST" "$t" > "$outdir/$i.out" 2>&1 &
  pids[$i]=$!
  i=$((i + 1))
done

i=0
while [[ $i -lt ${#selected[@]} ]]; do
  wait "${pids[$i]}" || rc=1
  printf '== %s\n' "$(basename "${selected[$i]}")"
  cat "$outdir/$i.out"
  i=$((i + 1))
done

exit $rc
