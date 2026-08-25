#!/usr/bin/env bash
# Check the invariants of the agent memory: index, frontmatter, links.
#
# Why a script: the memory layout rests on conventions, and conventions drift
# in silence. Rename a note and the pointer in its index dangles. Add a note
# and forget the index line, and nobody opens it again. Link from committed
# memory into local/ and the link is dead on the second machine. None of this
# is visible to the eye, and no code test covers it.
#
# The script prints problems only. A silent section means that section is clean.
# Output is English on purpose: the tool is reusable, the memory is not.
#
#   bash tools/memory-lint.sh
set -uo pipefail
cd "${FLOPPY_REPO:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
repo="$(pwd)"

MEM="${FLOPPY_MEMORY_DIR:-.agent-memory}"
IDX="$MEM/MEMORY.md"
fail=0

err() { printf '  x %s\n' "$1"; fail=1; }
warn() { printf '  ! %s\n' "$1"; }
hr() { printf '%s\n' "-- $1"; }

# Characters, not bytes: the memory is Russian, so a byte count runs ~1.55x
# ahead of what a reader (or the session loader) counts. LC_ALL=C keeps awk on
# bytes and the UTF-8 continuation bytes (0x80-0xBF) are subtracted. This
# behaves the same in BSD awk (macOS) and gawk, while `wc -m` would need a
# UTF-8 locale that a cron or CI shell does not always have.
chars_of() {
  LC_ALL=C awk '{ n += length($0) + 1; c += gsub(/[\200-\277]/, "", $0) } END { print n - c }' "$@"
}

# Naming the path, not just "no $IDX": this is the message a person gets when
# the wrong project is active in a harness that can have several open at
# once (Cursor especially), and without the path it reads as "your setup is
# broken" rather than "you are in the wrong place".
[[ -f "$IDX" ]] || { echo "no $IDX in $repo — this repository does not use this memory layout"; exit 2; }

# Committed notes: everything except local/ and the index itself.
#
# `find -L`, not plain `find`: the memory directory is a SYMLINK whenever it is
# hosted in another repository, and find does not descend into a symlinked
# starting point unless told to. Without -L that layout made every loop below
# iterate over nothing and the run print "clean: 0 notes" — green because it
# checked nothing, which is the one failure mode worse than red. Measured
# 2026-08-25 on the layout the day it shipped. -L also follows local/, but
# every query here excludes it by path, so nothing changes for it.
#
# No `mapfile`/`declare -A` anywhere in this script: macOS still ships bash 3.2
# (frozen at the GPLv2 version), where both are missing. The script used them
# and died on a Mac with "declare: -A: invalid option" — a memory check that
# cannot run on half the machines is worse than none.
notes=()
while IFS= read -r __line; do notes+=("$__line"); done < <(
  find -L "$MEM" -name '*.md' -not -path "$MEM/local/*" -not -name 'MEMORY.md' -not -name 'INDEX.md' | sort
)

# ---------- frontmatter ----------
hr "frontmatter"
# Slug -> file, as newline-delimited "slug<TAB>file" records instead of an
# associative array (see the bash 3.2 note above).
slug_records=""
slug_file() {  # $1 = slug; prints the file that claimed it, empty if free
  printf '%s\n' "$slug_records" | awk -F'\t' -v s="$1" '$1 == s { print $2; exit }'
}
for f in "${notes[@]+"${notes[@]}"}"; do
  rel="${f#"$MEM"/}"
  if [[ "$(head -n1 "$f")" != "---" ]]; then
    err "$rel: no frontmatter"
    continue
  fi
  fm="$(sed -n '2,/^---$/p' "$f")"
  name="$(printf '%s' "$fm" | sed -n 's/^name:[[:space:]]*//p' | head -n1)"
  desc="$(printf '%s' "$fm" | sed -n 's/^description:[[:space:]]*//p' | head -n1)"
  type="$(printf '%s' "$fm" | sed -n 's/^[[:space:]][[:space:]]*type:[[:space:]]*//p' | head -n1)"
  evidence="$(printf '%s' "$fm" | sed -n 's/^[[:space:]][[:space:]]*evidence:[[:space:]]*//p' | head -n1)"

  [[ -n "$name" ]] || err "$rel: field 'name' is missing"
  [[ -n "$desc" ]] || err "$rel: field 'description' is missing"

  case "$type" in
    user|feedback|project|reference) ;;
    "") err "$rel: metadata.type is missing" ;;
    *) err "$rel: metadata.type='$type', expected user|feedback|project|reference" ;;
  esac

  # Where the note's claim comes from. The project rule is that conclusions
  # come from measurements, not from reading code, and that a report says
  # plainly which is which. A note that does not say loses that distinction
  # the moment the session that wrote it ends, and the next session treats a
  # guess and a benchmark as the same kind of fact.
  #
  #   measured - checked against reality: a run, a profile, an incident that
  #              actually happened. The strongest of the four.
  #   read     - taken from source, a spec or a doc, ours or somebody else's.
  #              True until something runs and says otherwise.
  #   decided  - a choice by the owner or an agreement between us. Evidence
  #              does not apply to it; a date and an author do.
  #   sourced  - an outside claim checked against its primary source, quoted
  #              and dated. Never a search summary or a README retelling.
  #
  # On this corpus the split came out 92 measured / 22 decided / 14 read /
  # 6 sourced, which is the shape the project's own rule asks for. A memory
  # drifting towards 'read' is a memory of guesses.
  case "$evidence" in
    measured|read|decided|sourced) ;;
    "") err "$rel: metadata.evidence is missing — say whether this was measured, read, decided or sourced" ;;
    *) err "$rel: metadata.evidence='$evidence', expected measured|read|decided|sourced" ;;
  esac

  base="$(basename "$f" .md)"
  if [[ -n "$name" && "$name" != "$base" ]]; then
    err "$rel: name='$name' does not match the file name '$base' — a [[$name]] link resolves elsewhere"
  fi
  if [[ -n "$name" ]]; then
    taken="$(slug_file "$name")"
    if [[ -n "$taken" ]]; then
      err "$rel: slug '$name' is already taken by $taken"
    else
      slug_records="$slug_records$name	$rel
"
    fi
  fi
done

# ---------- index ----------
# The index is a tree since 2026-08-25: MEMORY.md is loaded into every session
# and holds only the always-read notes plus a link to each half's INDEX.md; the
# pointers of a half live in that half's index and are opened on the second
# step. Links inside an index are relative to its own directory, so they
# resolve from the file a session actually opens.
#
# A third level was added the same day, when sdk/ hit the 60-pointer cap and
# quota.lock said what to do about it: split the half, do not raise the number.
# Depth is capped at 3 on purpose. It is not a technical limit — it is the
# number of files a session opens before it reaches a note, and nobody has
# measured that a fourth hop still gets read.
hr "index"
indexes=("$IDX")
while IFS= read -r __line; do indexes+=("$__line"); done < <(
  find -L "$MEM" -mindepth 2 -maxdepth 3 -name 'INDEX.md' -not -path "$MEM/local/*" | sort
)

# Notes may not sit deeper than the deepest index that could list them.
while IFS= read -r __deep; do
  [[ -z "$__deep" ]] && continue
  err "${__deep#"$MEM"/}: nested deeper than a sub-index can reach — the index tree stops at three levels"
done < <(find -L "$MEM" -mindepth 4 -name '*.md' -not -path "$MEM/local/*" | sort)

idx_pointers=0
for f in "${indexes[@]}"; do
  dir="$(dirname "$f")"
  rel="${f#"$MEM"/}"
  while IFS= read -r link; do
    [[ -z "$link" || "$link" == http* ]] && continue
    idx_pointers=$((idx_pointers + 1))
    [[ -f "$dir/$link" ]] || err "$rel: pointer to a file that does not exist: '$link'"
  done < <(grep -o '](\([^)]*\.md\))' "$f" | sed 's/^](//; s/)$//' | sort -u)
done

# An index nobody links to is a branch nobody opens. Every index is reached
# from the one directly above it: a half from MEMORY.md, a sub-index from its
# half. Checking against MEMORY.md alone would have let the third level in
# unguarded, which is exactly how an unread branch appears — the sub-index
# exists, the linter is quiet, and no session ever opens the file.
for f in "${indexes[@]}"; do
  [[ "$f" == "$IDX" ]] && continue
  dir="$(dirname "$f")"
  up="$(dirname "$dir")"
  if [[ "$up" == "$MEM" ]]; then
    parent="$IDX"
    parent_rel="MEMORY.md"
  else
    parent="$up/INDEX.md"
    parent_rel="${up#"$MEM"/}/INDEX.md"
  fi
  link="${f#"$up"/}"
  if [[ ! -f "$parent" ]]; then
    err "${f#"$MEM"/}: its parent index $parent_rel does not exist — nothing above it can be opened"
  elif ! grep -qF "]($link)" "$parent"; then
    err "${f#"$MEM"/}: not linked from $parent_rel — a session never reaches this branch"
  fi
done

# Every note is listed in the index of its own half, root notes in MEMORY.md.
for f in "${notes[@]+"${notes[@]}"}"; do
  rel="${f#"$MEM"/}"
  dir="$(dirname "$f")"
  base="$(basename "$f")"
  # Its own half index is the normal home of the pointer; MEMORY.md is allowed
  # too, and is the right place for a note that is read in every task whatever
  # half it belongs to (flow/model-effort-feedback is the standing example).
  if grep -qF "]($rel)" "$IDX"; then
    :
  elif [[ "$dir" != "$MEM" && -f "$dir/INDEX.md" ]] && grep -qF "]($base)" "$dir/INDEX.md"; then
    :
  else
    err "$rel: no pointer line in ${dir#"$MEM"/}/INDEX.md nor in MEMORY.md — nobody will find this note"
  fi
done

# ---------- index size ----------
# The auto-loader pulls MEMORY.md into every session and truncates it in
# silence past a limit it reports in "KB" of characters: on 2026-08-24 it
# warned "26.5KB (limit: 24.4KB)" over a 27112-character index, and the tail
# — the whole flow/ section — never reached the session. Every other check in
# this script passed at the time, because nothing in the memory was wrong.
#
# Only MEMORY.md meets that cut, so only it fails the run. A half index is
# opened on demand, still costs context, and gets a warning at the same size.
#
# Characters, not bytes: the memory is Russian, so a byte count runs ~1.55x
# ahead of what the loader counts. LC_ALL=C keeps awk counting bytes and the
# UTF-8 continuation bytes (0x80-0xBF) are subtracted to get characters. That
# behaves the same in BSD awk (macOS) and gawk, while `wc -m` would need a
# UTF-8 locale that a cron or CI shell does not always have.
hr "index size"
IDX_MAX=24500      # the loader cut in at ~24986 characters; stay below it
IDX_WARN=23500     # trim or split the index before it reaches the cut
LINE_MAX=170       # one pointer line; the cap is what keeps the total down

for f in "${indexes[@]}"; do
  rel="${f#"$MEM"/}"
  chars="$(chars_of "$f")"
  bytes="$(LC_ALL=C awk '{ n += length($0) + 1 } END { print n }' "$f")"
  if [[ "$chars" -le 0 || "$chars" -gt "$bytes" ]]; then
    err "$rel: character count came out as '$chars' over $bytes bytes — awk counted something else, fix the counter before trusting this section"
  elif [[ "$f" == "$IDX" && "$chars" -gt "$IDX_MAX" ]]; then
    err "$rel: $chars characters, over the $IDX_MAX cap — the session loader truncates the tail and nobody is told which section it dropped"
  elif [[ "$chars" -gt "$IDX_WARN" ]]; then
    printf '  ! %s\n' "$rel: $chars characters, approaching the $IDX_MAX cap — shorten pointer lines or split the half"
  fi

  while IFS= read -r __long; do
    [[ -z "$__long" ]] && continue
    err "$rel:$__long"
  done < <(LC_ALL=C awk -v max="$LINE_MAX" '
    substr($0, 1, 3) == "- [" {
      s = $0; b = length(s); c = gsub(/[\200-\277]/, "", s)
      if (b - c > max) printf "%d: pointer line is %d characters, over %d — the index is a router, put the detail in the note\n", NR, b - c, max
    }' "$f")
done

# ---------- quota ----------
# A ratchet, borrowed from OwnMem after the 2026-08-25 trial: the numbers are
# measured off the corpus and kept in the memory directory's quota.lock, so growing past
# them is an edit somebody has to make and defend in the same commit.
#
# Every other check in this script asks "is this note wired up correctly". This
# one asks "is there too much of it". Nothing in the memory has to be wrong for
# it to fail, and that is the point: the memory grew by 16-43 notes a day, the
# session loader started truncating the index in silence, and no invariant was
# violated at any moment along the way.
hr "quota"
LOCK="$MEM/quota.lock"
lock_val() { sed -n "s/^$1=//p" "$LOCK" | head -n1; }

if [[ ! -f "$LOCK" ]]; then
  # Not an error: a fresh memory has nothing to measure yet, and a ceiling
  # copied from another project's corpus would bound nothing about this one.
  # This is the one check in this script that a clean run is expected to
  # print, not silence.
  warn "quota.lock is missing — measure the numbers once the first dozen notes exist, not before"
else
  chars_max="$(lock_val chars_max)"
  note_chars_max="$(lock_val note_chars_max)"
  pointers_max="$(lock_val pointers_max)"
  grandfathered=",$(lock_val grandfathered),"

  # A non-numeric value here is checked before anything uses it. Without the
  # flag the run still reported the problem, but printed eight bash "operand
  # expected" errors ahead of its own message, because the comparisons below
  # went on using the bad value — the reader saw a broken script rather than a
  # broken lock file.
  lock_ok=1
  for __k in chars_max note_chars_max pointers_max; do
    eval "__v=\$$__k"
    case "$__v" in
      ''|*[!0-9]*)
        err "quota.lock: $__k is '$__v', expected a number — the ratchet is not enforcing anything"
        lock_ok=0
        ;;
    esac
  done
fi

if [[ -f "$LOCK" && "${lock_ok:-0}" -eq 1 ]]; then
  # One note. A note over the cap is not a long note, it is two notes that were
  # written as one; on this corpus the cap caught exactly the pair that
  # flow/memory-hygiene-lessons already calls a session dump.
  for f in "${notes[@]+"${notes[@]}"}"; do
    rel="${f#"$MEM"/}"
    c="$(chars_of "$f")"
    [[ "$c" -le "$note_chars_max" ]] && continue
    case "$grandfathered" in
      *",$rel,"*) warn "$rel: $c characters, over the $note_chars_max cap — grandfathered in quota.lock, still worth splitting" ;;
      *) err "$rel: $c characters, over the $note_chars_max cap — split it into one fact per file instead of raising the cap" ;;
    esac
  done

  # Whole corpus, in characters. There is deliberately no cap on the NUMBER of
  # notes: it was dropped on 2026-08-25 by the owner's decision, because it
  # measured the wrong thing. Splitting two session dumps into six notes that
  # day cost 4 of the 5 remaining slots while making the memory 6169 characters
  # SMALLER — the count punished the one kind of work that lowers what a
  # session pays. What the count was supposed to protect is covered already:
  # routing by pointers_max, context cost by chars_max, dumps by
  # note_chars_max.
  total_chars=0
  for f in "${notes[@]+"${notes[@]}"}"; do total_chars=$((total_chars + $(chars_of "$f"))); done
  if [[ "$total_chars" -gt "$chars_max" ]]; then
    err "$total_chars characters, over the $chars_max in quota.lock — raise chars_max in the same commit and say why, or drop what went stale"
  fi

  # One index. Past a point a half index stops being a router and becomes a
  # list nobody reads to the end; the fix is sub-indexes, not a bigger number.
  for f in "${indexes[@]}"; do
    rel="${f#"$MEM"/}"
    n="$(grep -c '^- \[' "$f")"
    [[ "$n" -gt "$pointers_max" ]] && err "$rel: $n pointer lines, over the $pointers_max in quota.lock — split the half into sub-indexes"
  done
fi

# ---------- links into local/ ----------
hr "links into local/"
# Committed memory must not link into local/: a fresh clone does not have it.
for f in "${indexes[@]}" "${notes[@]+"${notes[@]}"}"; do
  rel="${f#"$MEM"/}"
  if grep -o '](\(local/[^)]*\))' "$f" >/dev/null 2>&1; then
    err "$rel: link into local/ — dead on a second machine, refer to it by meaning instead"
  fi
done

# ---------- [[slug]] links ----------
hr "[[slug]] links"
for f in "${notes[@]+"${notes[@]}"}"; do
  rel="${f#"$MEM"/}"
  while IFS= read -r slug; do
    [[ -z "$slug" ]] && continue
    [[ -n "$(slug_file "$slug")" ]] || err "$rel: link [[$slug]] resolves to nothing"
  done < <(grep -o '\[\[[^]]*\]\]' "$f" | sed 's/^\[\[//; s/\]\]$//' | sort -u)
done

# ---------- summary ----------
printf '\n'
if [[ $fail -eq 0 ]]; then
  printf 'clean: %d notes, %d pointers across %d indexes\n' "${#notes[@]}" "$idx_pointers" "${#indexes[@]}"
else
  printf 'problems found: %d notes checked\n' "${#notes[@]}"
fi
exit $fail
