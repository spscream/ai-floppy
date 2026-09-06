#!/usr/bin/env bash
# Sample ONE machine's temp directory: what `mktemp -d` hands back here, and
# which characters the parts of that path are made of.
#
# Serves knowledge/notes/shell/macos-tmpdir-can-contain-underscore.md. That note
# measured two macOS runners whose temp path carried `_` in the `<b>` component
# of /var/folders/<a>/<b>/T/, and was explicit that it could not say how often
# that happens — only a failing run ever printed its path, so the six passing
# runs' paths were never recorded.
#
# A loop on one machine cannot answer that either, and saying so is half of why
# this script exists. On Darwin `<b>` comes from confstr(_CS_DARWIN_USER_TEMP_DIR)
# and is derived per user and per boot session, NOT per mktemp call: N iterations
# here return N different suffixes under exactly ONE parent directory. The
# frequency question is answered by many machines running this once
# (.github/workflows/tmpdir-probe.yml), never by one machine running it many
# times. `distinct_parent_dirs` below is the number that demonstrates this rather
# than asserting it.
#
# What the loop DOES settle is the note's other half. It claimed mktemp's own
# suffix is alphanumeric on the strength of two samples (`e4GeiSlama`,
# `u5m1u5oq8Z`). N samples is a measurement.
#
# Output is key=value lines, one per line, so the workflow can tally them
# without parsing prose. This script REPORTS and always exits 0 — it is not a
# gate, and a machine whose temp path is unusual is the finding, not a failure.
#
# Runs on macOS bash 3.2: no mapfile, no declare -A, no GNU-only flags.
set -uo pipefail

iterations="${TMPDIR_PROBE_ITERATIONS:-100}"
case "$iterations" in ''|*[!0-9]*|0) iterations=100 ;; esac

# The alphabet is spelled out rather than written `[A-Za-z0-9]` on purpose.
# A bracket range in `case` is collation-dependent, so under some locales it
# matches accented characters too — and a probe whose answer depends on the
# runner's LC_COLLATE would measure the locale instead of the path.
ALNUM='abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789'

# The one place in this repository allowed to take a path apart character by
# character. Measuring the alphabet is the whole job here; everywhere else the
# note's rule stands — never let a path from mktemp meet a class assumption.
non_alnum() { # string -> its distinct non-alphanumeric characters, in order
  local s="${1:-}" i=0 c out=""
  while [[ $i -lt ${#s} ]]; do
    c="${s:$i:1}"
    case "$ALNUM" in
      *"$c"*) ;;
      *) case "$out" in *"$c"*) ;; *) out="$out$c" ;; esac ;;
    esac
    i=$((i + 1))
  done
  printf '%s' "$out"
}

emit() { printf '%s=%s\n' "$1" "${2:-}"; }

# ---------- what this machine says before anything is created ----------
emit probe_version 1
emit uname_s "$(uname -s 2>/dev/null)"
emit uname_r "$(uname -r 2>/dev/null)"
# The distinction matters: an unset TMPDIR means mktemp chose the path itself
# (/tmp on Linux), a set one means the environment did. On macOS the login
# session sets it, which is why the value differs between machines at all.
if [[ -n "${TMPDIR-}" ]]; then
  emit tmpdir_source env
  emit tmpdir "$TMPDIR"
else
  emit tmpdir_source unset
  emit tmpdir ""
fi

# ---------- N samples ----------
# Parents go to a file and through `sort -u` rather than into a shell variable
# compared pairwise: bash 3.2 has no associative array to dedupe with, and the
# file makes the count trivially right for any N.
parents="$(mktemp)"
suffix_odd_chars=""
suffix_odd_count=0
first_sample=""
i=0
while [[ $i -lt $iterations ]]; do
  d="$(mktemp -d)" || break
  [[ -n "$first_sample" ]] || first_sample="$d"
  printf '%s\n' "${d%/*}" >> "$parents"

  # The basename minus mktemp's own `tmp.` prefix, when it has one. Stripped
  # with a literal, not a class, so a template that ever changes shape shows up
  # as an odd character rather than being silently mis-parsed.
  base="${d##*/}"
  case "$base" in tmp.*) suffix="${base#tmp.}" ;; *) suffix="$base" ;; esac
  odd="$(non_alnum "$suffix")"
  if [[ -n "$odd" ]]; then
    suffix_odd_count=$((suffix_odd_count + 1))
    case "$suffix_odd_chars" in *"$odd"*) ;; *) suffix_odd_chars="$suffix_odd_chars$odd" ;; esac
  fi

  rmdir "$d" 2>/dev/null
  i=$((i + 1))
done
emit iterations "$i"

distinct_parents="$(sort -u "$parents" 2>/dev/null | grep -c . | tr -d ' ')"
rm -f "$parents"
emit distinct_parent_dirs "${distinct_parents:-0}"
emit suffix_non_alnum_count "$suffix_odd_count"
emit suffix_non_alnum_chars "$suffix_odd_chars"
emit sample_path "$first_sample"

# ---------- the fixed part, which is the part that varies between machines ----------
parent="${first_sample%/*}"
emit mktemp_parent "$parent"

# Read out of the sample mktemp actually produced, not out of $TMPDIR: they can
# disagree (a trailing slash, a symlinked root), and the one that decides what a
# test sees is the one mktemp returned.
darwin_a=""
darwin_b=""
case "$parent" in
  /var/folders/*)
    rest="${parent#/var/folders/}"
    darwin_a="${rest%%/*}"
    rest="${rest#*/}"
    darwin_b="${rest%%/*}"
    ;;
esac
emit darwin_a "$darwin_a"
emit darwin_b "$darwin_b"

# `varying_component` is the field the tally counts. On Darwin it is <b>; on any
# other platform there is no such component and the field is empty, so a tally
# run over Linux samples reports nothing rather than inventing a distribution.
emit varying_component "$darwin_b"
if [[ -n "$darwin_b" ]]; then
  emit varying_component_non_alnum "$(non_alnum "$darwin_b")"
  case "$darwin_b" in
    *_*) emit varying_component_has_underscore yes ;;
    *)   emit varying_component_has_underscore no ;;
  esac
else
  emit varying_component_non_alnum ""
  emit varying_component_has_underscore n/a
fi

# /var is a symlink to /private/var on macOS, so the path a test reads back out
# of the filesystem is one component longer than the one mktemp printed. Recorded
# because that difference has broken a check in this repository before.
resolved=""
if [[ -n "$parent" && -d "$parent" ]]; then
  resolved="$(cd "$parent" 2>/dev/null && pwd -P)"
fi
emit mktemp_parent_resolved "$resolved"
case "$resolved" in
  "$parent") emit parent_is_symlinked no ;;
  "")        emit parent_is_symlinked unknown ;;
  *)         emit parent_is_symlinked yes ;;
esac

exit 0
