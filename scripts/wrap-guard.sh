#!/usr/bin/env bash
# Check that a session commits only what it wrote itself.
#
# Why: `git add .agent-memory docs` stages everything under those paths,
# including a half-written note from a session running in parallel and the
# human's own edits. Asking the agent to be careful is not a mechanism. This is.
#
# Pass the files this session wrote. The script reports:
#   - changed files under the watched paths that are NOT in your list — other
#     work in flight, do not stage them;
#   - files in your list that are not changed at all — a wrong path;
#   - files in your list outside the watched paths — /wrap must not commit
#     product code.
#
# The watched set is memory, docs, and the session procedure itself: the
# commands, the root guidance file, and the session scripts in tools/. A
# session that edits the procedure has nowhere else to put its work, and
# leaving those paths out made the guard reject its own kind of change.
#
# Exit code 0 means the list matches reality and staging it is safe.
#
#   bash .floppy/run guard .agent-memory/foo.md docs/statuses/2026-08-20_status.md
#   printf '%s\n' "${files[@]}" | bash .floppy/run guard
set -uo pipefail
cd "${FLOPPY_REPO:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"

mem_dir="${FLOPPY_MEMORY_DIR:-.agent-memory}"
now_file="${FLOPPY_STATUSES_NOW:-docs/statuses/NOW.md}"
now_chars_max="${FLOPPY_STATUSES_NOW_CHARS_MAX:-12000}"
statuses_dir="${now_file%/*}"

# Directories: everything below them counts. The memory directory is watched
# always; everything else comes from config (watched_dirs), so a project can
# add its own without editing this script.
WATCHED_DIRS=("$mem_dir")
_IFS_SAVE="$IFS"; IFS=','
for d in ${FLOPPY_WATCHED_DIRS:-docs}; do WATCHED_DIRS+=("$d"); done
# Single files and patterns: an exact match only. A directory prefix here would
# pull in unrelated neighbours. Also from config (watched_files).
WATCHED_FILES=()
for f in ${FLOPPY_WATCHED_FILES:-AGENTS.md}; do WATCHED_FILES+=("$f"); done
IFS="$_IFS_SAVE"
WATCHED=("${WATCHED_DIRS[@]}" "${WATCHED_FILES[@]}")
fail=0

err() { printf '  x %s\n' "$1"; fail=1; }
hr() { printf '%s\n' "-- $1"; }

# ---------- the list this session claims ----------
declare -a claimed=()
if [[ $# -gt 0 ]]; then
  claimed=("$@")
elif [[ ! -t 0 ]]; then
  while IFS= read -r line; do
    [[ -n "$line" ]] && claimed+=("$line")
  done
fi

if [[ ${#claimed[@]} -eq 0 ]]; then
  echo "no files given: pass the files this session wrote, as arguments or on stdin"
  echo "(a session that wrote nothing has nothing to commit)"
  exit 2
fi

# Newline-delimited sets instead of `declare -A`: macOS ships bash 3.2, where
# associative arrays do not exist. `memory-lint.sh` died there with
# "declare: -A: invalid option", and this script would have died the same way
# the first time /wrap ran on a Mac.
claimed_set=""
for f in "${claimed[@]}"; do
  claimed_set="$claimed_set${f#./}
"
done
# `--` is not decoration: the needle used to be a file path, which never starts
# with a dash, but trend row names from NOW.md are written by a human and can.
# grep would swallow such a name as options and answer about the wrong thing.
in_set() { printf '%s' "$2" | grep -qxF -- "$1"; }

# ---------- what actually changed ----------
changed_set=""
while IFS= read -r line; do
  [[ -z "$line" ]] && continue
  path="${line:3}"
  # A rename prints "old -> new"; the new path is the one that gets committed.
  [[ "$path" == *" -> "* ]] && path="${path##* -> }"
  path="${path%\"}"; path="${path#\"}"
  changed_set="$changed_set$path
"
done < <(git status --porcelain --untracked-files=all -- "${WATCHED[@]}" 2>/dev/null)

# ---------- other people's work in flight ----------
hr "changed but not yours"
while IFS= read -r path; do
  [[ -z "$path" ]] && continue
  in_set "$path" "$claimed_set" || err "$path — not in your list: another session or the human. Do not stage it."
done < <(printf '%s' "$changed_set")

# ---------- paths that do not hold up ----------
hr "your list"
for f in "${claimed[@]}"; do
  f="${f#./}"
  in_watched=0
  for w in "${WATCHED_DIRS[@]}"; do
    [[ "$f" == "$w"/* ]] && in_watched=1
  done
  for w in "${WATCHED_FILES[@]}"; do
    # Unquoted on purpose: the entry may be a pattern, and it must match as one.
    [[ "$f" == $w ]] && in_watched=1
  done
  if [[ $in_watched -eq 0 ]]; then
    err "$f — outside ${WATCHED[*]}: /wrap commits memory, docs and the session procedure, leave product code to the human"
    continue
  fi
  in_set "$f" "$changed_set" || err "$f — not changed: wrong path, or the edit was lost"
done

# ---------- journal written, current state left stale ----------
# docs/statuses/NOW.md is what /start reads; a dated *_status.md entry is the
# append-only journal. Writing the journal without updating NOW.md leaves the
# thing /start trusts unrevised — a week of that and NOW.md is the stalest
# file in the repo, and it reads as current because nothing marks it stale.
# The reverse is fine: NOW.md can be rewritten with no journal entry that day.
hr "journal without NOW.md"
journal_touched=0
for f in "${claimed[@]}"; do
  case "${f#./}" in
    "$statuses_dir"/*_status.md) journal_touched=1 ;;
  esac
done
if [[ $journal_touched -eq 1 ]] && ! in_set "$now_file" "$claimed_set"; then
  err "journal entry staged but $now_file is not in your list: /start reads NOW.md, not the journal — update it too"
fi

# ---------- a trend row vanished from NOW.md ----------
# Trim a markdown table cell: strip leading/trailing whitespace. Bash 3.2 has
# no better built-in for this, and pulling in sed just for trimming would be
# one more external tool this script otherwise avoids.
trim() {
  local s="$1"
  s="${s#"${s%%[![:space:]]*}"}"
  s="${s%"${s##*[![:space:]]}"}"
  printf '%s' "$s"
}

# A markdown table row -> its metric name: first cell, trimmed, bold markers
# stripped. Empty cells and the `---`/`:---:` separator row are not metric
# names; the header row is filtered out by trend_row_names below, structurally
# rather than by matching a word, so the caller only has those two to skip
# itself.
trend_row_name() {
  local cell
  cell="$(trim "${1#|}")"
  cell="${cell%%|*}"
  cell="$(trim "${cell//\*\*/}")"
  printf '%s' "$cell"
}

# All metric names in a trend table, one per line, read from stdin.
#
# The header row is not recognized by its text (it used to be, matching the
# literal word "показатель" — one project's table-header word, so an English
# consumer's header cell became a phantom trend row, and renaming their
# column fired a false "trend row dropped"). A markdown table's header row is
# structural instead: it is whatever row immediately precedes a separator
# row. Detecting that needs one row of lookback, since a row only reveals
# itself as a header once the next line turns out to be the separator — so
# each candidate name is held for one iteration before being emitted, and is
# dropped instead if the very next row is a separator.
trend_row_names() {
  local line name have_prev=0 prev=""
  while IFS= read -r line; do
    [[ "$line" == '|'* ]] || continue
    name="$(trend_row_name "$line")"
    [[ -z "$name" ]] && continue
    if [[ "$name" =~ ^[-:]+$ ]]; then
      # Separator row: whatever was held is this table's header, not a
      # metric — discard it rather than emitting it.
      have_prev=0
      continue
    fi
    [[ $have_prev -eq 1 ]] && printf '%s\n' "$prev"
    prev="$name"
    have_prev=1
  done
  [[ $have_prev -eq 1 ]] && printf '%s\n' "$prev"
}

hr "NOW.md trend rows"
if [[ -f "$now_file" ]] && git cat-file -e HEAD:"$now_file" 2>/dev/null; then
  old_names="$(git show HEAD:"$now_file" | trend_row_names)"
  new_names="$(trend_row_names < "$now_file")"
  while IFS= read -r name; do
    [[ -z "$name" ]] && continue
    # docs/statuses/README.md names a disappeared trend row as the way a
    # regression hides. The append-only journal kept that guarantee for
    # free — nothing could remove a past line. A rewritten NOW.md has no
    # such guarantee, so this is the only thing left enforcing it. A
    # changed *value* for a row that is still there is not this: only a
    # row whose name is gone counts.
    in_set "$name" "$new_names" || err "trend row \"$name\" dropped from NOW.md — changing a value is fine, deleting the row hides a regression"
  done <<< "$old_names"
fi

# ---------- NOW.md outgrowing its genre ----------
# A ratchet, not a style rule, and the same idea as .agent-memory/quota.lock:
# the number is measured off the file, and growing past it has to be a
# deliberate act visible in a diff. NOW.md was 6284 characters the day it was
# split out of the journal; the cap is roughly double that. Without a ceiling
# the file drifts back into being a second journal, which is the exact failure
# the split fixed — and it would drift silently, because a long NOW.md looks
# thorough. Detail belongs in the dated journal, which has no ceiling at all.
if [[ -f "$now_file" ]]; then
  now_chars=$(wc -m < "$now_file" | tr -d ' ')
  if [[ "$now_chars" -gt $now_chars_max ]]; then
    err "NOW.md is $now_chars characters, over the $now_chars_max cap — move detail into the dated journal, or raise statuses_now_chars_max in .floppy/config and say why"
  fi
fi

# ---------- summary ----------
printf '\n'
if [[ $fail -eq 0 ]]; then
  printf 'safe to stage: %d files, nothing else changed under %s\n' "${#claimed[@]}" "${WATCHED[*]}"
  printf '  git add --'
  for f in "${claimed[@]}"; do printf ' %q' "${f#./}"; done
  printf '\n'
else
  # No command is printed on failure on purpose: a command built from a list
  # that does not hold up is an invitation to run it anyway.
  printf 'fix the list above, then run this again. Never fall back to staging a directory.\n'
fi
exit $fail
