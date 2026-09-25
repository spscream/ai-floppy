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
# The log is per-checkout working data, not memory: it is kept out of git and
# excluded from quotas. Two machines keep two honest tallies, and so do two
# worktrees sharing one store-hosted memory — aggregation is explicitly a
# non-goal, which is one more reason the report reading this must call
# absence a hint, not proof.
#
# UTC date, same as metadata.as_of: a local-evening stamp is tomorrow for the
# CI that reads it, and the memory already paid for that lesson once.
set -uo pipefail

# How a hint spells a floppy command. The consumer's repository holds no runner
# of its own since 0.26.0, so a message names this plugin's dispatcher by its
# absolute path — pasteable from wherever the reader is standing. scripts/run
# exports FLOPPY_RUN; a direct call (the tests make them) derives the same
# value from this script's own location.
floppy_run="${FLOPPY_RUN:-}"
[[ -n "$floppy_run" ]] || floppy_run="bash $(cd "$(dirname "$0")" && pwd)/run"
# The cd is guarded because this script writes: a stale FLOPPY_REPO landing
# in `pwd` would append the log into whatever repository the shell happens to
# sit in, with rc 0 (review 2026-09-13, finding 8).
cd "${FLOPPY_REPO:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}" || {
  echo "x FLOPPY_REPO points nowhere: ${FLOPPY_REPO:-}" >&2
  exit 1
}

LOG=".floppy/heat.log"
# Rotation, so the log cannot become its own quota problem: past MAX_LINES
# the oldest lines go. 5000 lines is ~18 months of a heavy corpus (the
# 2026-09 measurement saw ~21 opens per 83-question benchmark run); the trim
# keeps the newest KEEP_LINES so consecutive calls do not re-trim.
MAX_LINES=5000
KEEP_LINES=4000

if [[ $# -eq 0 ]]; then
  echo "usage: $floppy_run heat <note-slug> [<note-slug>...]" >&2
  echo "  Call it when a note is actually opened, with the note's slug" >&2
  echo "  (the filename without .md). The log feeds lint's cold-note report." >&2
  exit 2
fi

# The ignore line goes into .git/info/exclude, never the consumer's
# .gitignore: the first release of this verb edited .gitignore, and the first
# call left the tree permanently dirty on a file wrap's guard refuses to
# commit — `guard .gitignore` exits 1, so every wrap after the first
# read "won't commit: .gitignore" forever (review 2026-09-13,
# finding 1). The exclude file is machine-local like the log itself, which is
# also why writing it needs no one's review. The check is per-file — the log
# AND the rotation temp file — because a consumer's own `*.log` covers the
# first and not the second (finding 9); the pattern ends in `*` so one line
# covers both.
if ! git check-ignore -q "$LOG" 2>/dev/null || ! git check-ignore -q "$LOG.tmp" 2>/dev/null; then
  excl="$(git rev-parse --git-common-dir 2>/dev/null || git rev-parse --git-dir)/info/exclude"
  mkdir -p "${excl%/*}" 2>/dev/null
  {
    # An exclude file with no final newline would weld the pattern onto its
    # last rule, silently disabling it (measured on a hand-edited .gitignore,
    # review 2026-09-13). One byte of prevention:
    if [[ -s "$excl" ]] && [[ -n "$(tail -c1 "$excl")" ]]; then
      printf '\n' >> "$excl"
    fi
    printf '%s*\n' "$LOG" >> "$excl"
  } 2>/dev/null || echo "! could not write $excl — the log will show as untracked" >&2
fi

# Normalize each argument to the bare slug: the caller is an agent that just
# read `half/note.md` off the filesystem, and a path or a filename logged
# verbatim is a line no report can ever match — both ends would say ok while
# the feature quietly degrades to noise. Parameter expansion, not basename:
# BSD and GNU basename disagree on a leading dash (`--help`), and expansion
# has no option parsing to disagree about (finding 5).
#
# A slug with whitespace is refused for the same both-ends-say-ok reason:
# lint matches the second field of a line, so `my note` would log fine and
# read as permanently cold (finding 7). A leading dash is refused as an
# obvious non-slug. The rejection is loud and the call fails, because the
# mismatch is at the caller and stays until the caller fixes it.
stamp="$(date -u +%Y-%m-%d)"
payload=""
logged=0
rejected=0
for slug in "$@"; do
  s="${slug%.md}"
  s="${s##*/}"
  case "$s" in
    ""|-*|*[[:space:]]*)
      echo "x '$slug' is not a note slug — skipped (a slug is the filename without .md, one word)" >&2
      rejected=1
      continue
      ;;
  esac
  payload="$payload$stamp $s
"
  logged=$((logged+1))
done

if [[ "$logged" -gt 0 ]]; then
  if ! printf '%s' "$payload" >> "$LOG" 2>/dev/null; then
    echo "x could not write $LOG — the open goes unrecorded" >&2
    exit 1
  fi
fi

lines="$(wc -l < "$LOG" 2>/dev/null | tr -d ' ')"
if [[ "${lines:-0}" -gt "$MAX_LINES" ]]; then
  # A trim that cannot complete is named, not swallowed: silent here means
  # the log grows past its cap forever and nobody learns why (finding 6).
  # The append above already landed, so this is a warning, not a failure.
  if ! { tail -n "$KEEP_LINES" "$LOG" > "$LOG.tmp" && mv "$LOG.tmp" "$LOG"; } 2>/dev/null; then
    echo "! could not rotate $LOG — it stays whole and keeps growing until this is fixed" >&2
  fi
fi

[[ "$logged" -gt 0 ]] && echo "ok heat: logged $logged note(s)"
[[ "$rejected" -eq 0 ]] || exit 1
exit 0
