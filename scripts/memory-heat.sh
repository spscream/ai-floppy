#!/usr/bin/env bash
# Log that a session opened a memory note: one `YYYY-MM-DD <slug>` line per
# note, appended to .floppy/heat.log (issue #70).
#
# Why a log at all: the one time note usage was counted — the 2026-09-09
# benchmark, 83 questions over 19 sessions — fourteen of twenty project notes
# had never been opened, and that count had to be assembled by hand from
# transcripts. Pruning and consolidation choose candidates by date and by
# wikilink adjacency, which are proxies; "was this ever read" is the direct
# signal, and it exists at read time only to be thrown away.
#
# Why self-report and not a harness hook: a hook is accurate but couples to
# one harness and needs per-consumer setup. The rites calling this verb works
# everywhere the shim works. The same benchmark measured that self-reported
# file usage UNDER-counts, so the log is a floor, never a census — a reporter
# reading it must not treat absence as proof of cold.
#
# The log is machine-local working data, not memory: it is gitignored (this
# script keeps the ignore line present), excluded from quotas, and two
# machines keep two honest tallies — aggregation is explicitly a non-goal.
#
# UTC date, same as metadata.as_of: a local-evening stamp is tomorrow for the
# CI that reads it, and the memory already paid for that lesson once.
set -uo pipefail
cd "${FLOPPY_REPO:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"

LOG=".floppy/heat.log"
# Rotation, so the log cannot become its own quota problem: past MAX_LINES
# the oldest lines go. 5000 lines is ~18 months of a heavy corpus (the
# 2026-09 measurement saw ~21 opens per 83-question benchmark run); the trim
# keeps the newest KEEP_LINES so consecutive calls do not re-trim.
MAX_LINES=5000
KEEP_LINES=4000

if [[ $# -eq 0 ]]; then
  echo "usage: bash .floppy/run heat <note-slug> [<note-slug>...]" >&2
  echo "  Call it when a note is actually opened, with the note's slug" >&2
  echo "  (the filename without .md). The log feeds lint's cold-note report." >&2
  exit 2
fi

# The ignore line rides with the first write rather than waiting for init:
# the verb arrives by `plugin update` into repositories that ran init long
# ago, and a log that starts life tracked would churn every commit with reads.
if ! grep -qxF "$LOG" .gitignore 2>/dev/null; then
  printf '%s\n' "$LOG" >> .gitignore
  echo "ok added $LOG to .gitignore"
fi

stamp="$(date -u +%Y-%m-%d)"
for slug in "$@"; do
  printf '%s %s\n' "$stamp" "$slug"
done >> "$LOG"

lines="$(wc -l < "$LOG" | tr -d ' ')"
if [[ "$lines" -gt "$MAX_LINES" ]]; then
  tail -n "$KEEP_LINES" "$LOG" > "$LOG.tmp" && mv "$LOG.tmp" "$LOG"
fi

echo "ok heat: logged $# note(s)"
