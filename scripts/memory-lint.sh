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
# The machine-local scope inside the memory: written here, never committed here.
# Its NAME is a consumer's choice, so it comes from config rather than being
# spelled into the checks below. Getting this wrong is not cosmetic: the check
# that committed memory must not link into it is the one protecting against
# links that are dead on a second machine, and with a name it does not
# recognize that check silently applies to nothing.
# The pre-0.6.0 variable name is read as a fallback, and the final default
# matches memory-workplace.sh. They disagreed (`local` here, `private` there),
# so under an unrefreshed shim the rule "committed memory must not link into
# the private scope" guarded a directory that no longer existed — the same
# way of applying to nothing that 0.4.0 introduced this variable to prevent.
LOCAL_DIR="${FLOPPY_MEMORY_PRIVATE_DIR:-${FLOPPY_MEMORY_LOCAL_DIR:-private}}"
fail=0

err() { printf '  x %s\n' "$1"; fail=1; }
warn() { printf '  ! %s\n' "$1"; }
hr() { printf '%s\n' "-- $1"; }

# The fraction of a ceiling at which this script starts saying so, shared by
# every ceiling it checks: the index, the corpus, one half, one note, one
# index's pointers. Derived rather than configured, for the reason the index
# section states below — two numbers that must be kept in a fixed relation are
# two chances to set them wrong — and shared rather than per-ceiling for the
# same reason multiplied by five.
#
# Why a band and not just a cap. A ceiling that only fails stops whoever
# CROSSES it, and that is routinely not whoever filled it: the halves grow on
# different machines, and the ratchet rule says a ceiling may be raised only in
# the same commit as the notes that needed the room. So the session that trips
# a hard stop has to either raise a number it did not fill or prune a half it
# did not write — and pruning a neighbouring session's notes is the one thing
# the wrap procedure forbids outright. The band is what lets the session that
# IS filling a ceiling see that happening, while the fix is still its own work.
#
# Measured on a consumer corpus 2026-09-05, and this is what the band is for:
# a half budget set that day at +10% over a 68311-character measurement stood
# at 72694 of 75000 — 96.9% — four commits later the same day. 66% of the
# headroom went in one day, and every run in between printed `clean`.
#
# pointer_line_max is deliberately not in this list. It bounds one line, and a
# line at 165 of 170 characters is not approaching anything — it is a line that
# fits. The other five bound something that accumulates.
WARN_PCT=96

# Characters, not bytes: the memory is Russian, so a byte count runs ~1.55x
# ahead of what a reader (or the session loader) counts. LC_ALL=C keeps awk on
# bytes and the UTF-8 continuation bytes (0x80-0xBF) are subtracted. This
# behaves the same in BSD awk (macOS) and gawk, while `wc -m` would need a
# UTF-8 locale that a cron or CI shell does not always have.
chars_of() {
  LC_ALL=C awk '{ n += length($0) + 1; c += gsub(/[\200-\277]/, "", $0) } END { print n - c }' "$@"
}

# Interpolated into grep patterns and find globs, so it must be an ordinary
# path segment. A name with regex metacharacters would not fail loudly — it
# would match the wrong thing, which is the failure mode this whole file exists
# to remove.
case "$LOCAL_DIR" in
  ''|*[!A-Za-z0-9._-]*)
    echo "x memory_private_dir is '$LOCAL_DIR': use a plain name (letters, digits, dot, dash, underscore)" >&2
    exit 2 ;;
esac

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
  find -L "$MEM" -name '*.md' -not -path "$MEM/$LOCAL_DIR/*" -not -name 'MEMORY.md' -not -name 'INDEX.md' | sort
)

# The private scope, which every query above deliberately skips. It is a
# symlink into the workplace repository, so it is a different corpus in a
# different git repository — and until now nothing checked it at all. Measured
# 2026-08-25 on the first consumer's store: three notes, three without
# metadata.evidence, invisible because no query reached them.
#
# What it gets and what it does not:
#   yes - the per-note invariants: frontmatter, name/description, type,
#         evidence, slug uniqueness, and [[link]] resolution. Those are
#         properties of a note, true wherever the note lives.
#   no  - the index tree. The scope is flat by design, with a README that is
#         prose rather than pointers; demanding MEMORY.md and INDEX.md there
#         would report every note an orphan on the first run.
#   no  - the quota. Those numbers live in the committed memory's quota.lock
#         and are facts about THAT corpus. Applying them here is exactly the
#         borrowed cap this project refuses elsewhere; the private scope needs
#         its own measurement before it can have its own numbers.
#
# README.md is excluded the way MEMORY.md and INDEX.md are above: in this
# scope it is the file that introduces the directory, not a note in it.
#
# So is the personal status file (statuses_personal, #19), which lives at
# machines/<name>/ inside this scope and is a status document, not a note: it
# has no frontmatter and is not supposed to. Excluded by PATH — the basename
# in any machines/<...>/ directory — rather than by the one resolved path,
# because a memory synced from a second machine carries that machine's copy
# too, and this machine cannot resolve a path it does not name. A note that
# genuinely belongs to a machine still lints: only this one filename is
# skipped, not the directory, which is the blind spot this scope was given a
# lint pass to remove in the first place.
sp_leaf="${FLOPPY_STATUSES_PERSONAL:-}"; sp_leaf="${sp_leaf##*/}"
[[ -n "$sp_leaf" ]] || sp_leaf="NOW.md"
private_notes=()
if [[ -d "$MEM/$LOCAL_DIR" ]]; then
  while IFS= read -r __line; do private_notes+=("$__line"); done < <(
    find -L "$MEM/$LOCAL_DIR" -name '*.md' \
      -not -name 'MEMORY.md' -not -name 'INDEX.md' -not -name 'README.md' \
      -not -path "*/machines/*/$sp_leaf" | sort
  )
fi

# Every note whose own invariants are checked, wherever it lives.
all_notes=("${notes[@]+"${notes[@]}"}" "${private_notes[@]+"${private_notes[@]}"}")

# ---------- frontmatter ----------
hr "frontmatter"
# Slug -> file, as newline-delimited "slug<TAB>file" records instead of an
# associative array (see the bash 3.2 note above).
slug_records=""
slug_file() {  # $1 = slug; prints the file that claimed it, empty if free
  printf '%s\n' "$slug_records" | awk -F'\t' -v s="$1" '$1 == s { print $2; exit }'
}
for f in "${all_notes[@]+"${all_notes[@]}"}"; do
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
  find -L "$MEM" -mindepth 2 -maxdepth 3 -name 'INDEX.md' -not -path "$MEM/$LOCAL_DIR/*" | sort
)

# Notes may not sit deeper than the deepest index that could list them.
while IFS= read -r __deep; do
  [[ -z "$__deep" ]] && continue
  err "${__deep#"$MEM"/}: nested deeper than a sub-index can reach — the index tree stops at three levels"
done < <(find -L "$MEM" -mindepth 4 -name '*.md' -not -path "$MEM/$LOCAL_DIR/*" | sort)

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

# Two numbers, two homes, and the split is not tidiness — it is the same
# question this project asks of a memory note: WHAT IS THIS A FACT ABOUT.
#
#   index_chars_max  is a fact about the HARNESS. Its session loader truncates
#                    the index past a limit of its own; measured on Claude Code
#                    2026-08-24, it cut in at ~24986 characters while reporting
#                    "26.5KB (limit: 24.4KB)". That number is the same for every
#                    project running in that harness and belongs to none of
#                    them, so it ships as the plugin's default and is overridden
#                    in .floppy/config by a consumer whose harness differs.
#   pointer_line_max is a fact about THIS PROJECT's writing convention, the same
#                    kind as pointers_max, so it lives beside it in quota.lock
#                    and is measured off this corpus.
#
# The warning threshold is derived, not a third knob: two numbers that must be
# kept in a fixed relation are two chances to set them wrong, and nobody has a
# reason to want a warning at some other fraction.
IDX_MAX="${FLOPPY_INDEX_CHARS_MAX:-24500}"
case "$IDX_MAX" in
  ''|*[!0-9]*) err "index_chars_max is '$IDX_MAX' in .floppy/config, expected a number — falling back to 24500"
               IDX_MAX=24500 ;;
esac
IDX_WARN=$(( IDX_MAX * WARN_PCT / 100 ))

# Read before the quota section below, because it is used here. Absent
# quota.lock is normal on a fresh memory, so the default has to stand on its
# own rather than turn the check off.
LOCK="$MEM/quota.lock"
lock_val() { sed -n "s/^$1=//p" "$LOCK" | head -n1; }
LINE_MAX=170
if [[ -f "$LOCK" ]]; then
  __plm="$(lock_val pointer_line_max)"
  case "$__plm" in
    "") ;;
    *[!0-9]*) err "quota.lock: pointer_line_max is '$__plm', expected a number — using $LINE_MAX" ;;
    *) LINE_MAX="$__plm" ;;
  esac
fi

for f in "${indexes[@]}"; do
  rel="${f#"$MEM"/}"
  chars="$(chars_of "$f")"
  bytes="$(LC_ALL=C awk '{ n += length($0) + 1 } END { print n }' "$f")"
  if [[ "$chars" -le 0 || "$chars" -gt "$bytes" ]]; then
    err "$rel: character count came out as '$chars' over $bytes bytes — awk counted something else, fix the counter before trusting this section"
  elif [[ "$f" == "$IDX" && "$chars" -gt "$IDX_MAX" ]]; then
    err "$rel: $chars characters, over the $IDX_MAX cap — the session loader truncates the tail and nobody is told which section it dropped"
  elif [[ "$chars" -gt "$IDX_WARN" ]]; then
    warn "$rel: $chars characters, approaching the $IDX_MAX cap — shorten pointer lines or split the half"
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
# LOCK and lock_val are defined in the index-size section above: pointer_line_max
# is needed there, and one definition read from two sections beats two
# definitions that can drift apart.

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
  #
  # The band matters most here of all the ceilings, because a note is written
  # in one sitting: the session inside the band is the very session that is
  # about to cross it, and it is holding the material to split. A session that
  # opens the file later and finds it already over has to reconstruct which two
  # facts it was.
  note_warn=$(( note_chars_max * WARN_PCT / 100 ))
  for f in "${notes[@]+"${notes[@]}"}"; do
    rel="${f#"$MEM"/}"
    c="$(chars_of "$f")"
    [[ "$c" -le "$note_warn" ]] && continue
    if [[ "$c" -le "$note_chars_max" ]]; then
      warn "$rel: $c characters, approaching the $note_chars_max cap — the next paragraph makes it a second note, not a longer one"
      continue
    fi
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
  #
  # The same pass tallies each half, because a corpus-wide number says the
  # memory is too big without saying whose. Measured on one consumer 2026-09-05:
  # the halves were 3.4x apart in size and grew on different machines, so the
  # session that trips the ceiling is routinely not the one that filled it.
  # Root-level notes are their own group, keyed `root`; a half directory
  # literally named `root` would share that budget, and renaming it is the fix.
  total_chars=0
  half_tally=""
  for f in "${notes[@]+"${notes[@]}"}"; do
    __c="$(chars_of "$f")"
    total_chars=$((total_chars + __c))
    __rel="${f#"$MEM"/}"
    case "$__rel" in
      */*) __half="${__rel%%/*}" ;;
      *)   __half="root" ;;
    esac
    half_tally="$half_tally$__half $__c
"
  done
  halves="$(printf '%s' "$half_tally" | awk 'NF { n[$1] += $2 } END { for (h in n) printf "%s %d\n", h, n[h] }' | sort -k2,2nr)"

  # Printed with the corpus line and nowhere else: this script says nothing when
  # clean, and a breakdown nobody asked for is the kind of line that trains
  # people to skim. It goes with the warning as well as the failure, because
  # "the memory is nearly full" without "and this half is why" leaves the reader
  # to measure the corpus by hand — which is the work the tally already did.
  by_half() {
    printf '    by half: %s\n' "$(printf '%s\n' "$halves" | awk 'NF { printf "%s%s %s", (c++ ? ", " : ""), $1, $2 } END { print "" }')"
  }

  if [[ "$total_chars" -gt "$chars_max" ]]; then
    err "$total_chars characters, over the $chars_max in quota.lock — raise chars_max in the same commit and say why, or drop what went stale"
    by_half
  elif [[ "$total_chars" -gt $(( chars_max * WARN_PCT / 100 )) ]]; then
    warn "$total_chars characters, approaching the $chars_max in quota.lock — drop what went stale now, while this is still the session that grew it"
    by_half
  fi

  # Optional per-half budgets: `half_chars_max.<half>=N`. A half with no key is
  # not bounded, so this is inert until a consumer measures its own halves —
  # one number for all of them would be set to the largest half and would bound
  # none of the others, which is the same as having none.
  while read -r __h __c; do
    [[ -z "$__h" ]] && continue
    __hm="$(lock_val "half_chars_max.$__h")"
    case "$__hm" in
      "") continue ;;
      *[!0-9]*)
        err "quota.lock: half_chars_max.$__h is '$__hm', expected a number — that half is not bounded"
        continue ;;
    esac
    if [[ "$__c" -gt "$__hm" ]]; then
      err "$__h: $__c characters, over the $__hm for that half in quota.lock — prune the half that grew rather than the corpus that did not"
    elif [[ "$__c" -gt $(( __hm * WARN_PCT / 100 )) ]]; then
      warn "$__h: $__c characters, approaching the $__hm for that half in quota.lock — prune it in this session, which is the one adding to it"
    fi
  done <<EOF
$halves
EOF

  # One index. Past a point a half index stops being a router and becomes a
  # list nobody reads to the end; the fix is sub-indexes, not a bigger number.
  # Splitting a half is the largest of the fixes this script asks for, so it is
  # the one that least wants to be discovered by a session that came to write
  # one note — hence the band here too. An index sitting exactly at the cap is
  # inside it by definition: full, and refusing the next note.
  ptr_warn=$(( pointers_max * WARN_PCT / 100 ))
  for f in "${indexes[@]}"; do
    rel="${f#"$MEM"/}"
    n="$(grep -c '^- \[' "$f")"
    if [[ "$n" -gt "$pointers_max" ]]; then
      err "$rel: $n pointer lines, over the $pointers_max in quota.lock — split the half into sub-indexes"
    elif [[ "$n" -gt "$ptr_warn" ]]; then
      warn "$rel: $n pointer lines, approaching the $pointers_max in quota.lock — plan the sub-index split before the cap forces it"
    fi
  done
fi

# ---------- links into local/ ----------
hr "links into $LOCAL_DIR/"
# Committed memory must not link into the machine-local scope: a fresh clone
# does not have it.
for f in "${indexes[@]}" "${notes[@]+"${notes[@]}"}"; do
  rel="${f#"$MEM"/}"
  if grep -o "](\($LOCAL_DIR/[^)]*\))" "$f" >/dev/null 2>&1; then
    err "$rel: link into $LOCAL_DIR/ — dead on a second machine, refer to it by meaning instead"
  fi
done

# ---------- [[slug]] links ----------
hr "[[slug]] links"
for f in "${all_notes[@]+"${all_notes[@]}"}"; do
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
