#!/usr/bin/env bash
# Tally the key=value files that tmpdir-probe.sh produced on many machines.
# Usage: bash knowledge/probes/tmpdir-tally.sh <dir-of-probe-files>
#
# One machine's probe answers "what does this path look like here". Only a
# collection answers the question the note left open — does the varying
# component differ between runners at all, and how often does it carry `_`.
#
# Output is markdown, which reads as plain text in a terminal and renders in
# $GITHUB_STEP_SUMMARY. Exits 0 with an empty tally rather than failing: a
# dispatch where every macOS job was cancelled is a fact about the runner queue,
# not a broken script.
#
# Runs on macOS bash 3.2: no mapfile, no declare -A, no GNU-only flags.
set -uo pipefail

dir="${1:-}"
if [[ -z "$dir" || ! -d "$dir" ]]; then
  echo "usage: bash knowledge/probes/tmpdir-tally.sh <dir-of-probe-files>" >&2
  exit 2
fi

# One concatenation up front, via -exec + rather than a shell loop over a
# newline list: a directory whose name contains a space would otherwise be split
# into two paths that do not exist, and the tally would silently read nothing.
all="$(mktemp)"
trap 'rm -f "$all"' EXIT
find "$dir" -type f -name '*.txt' -exec cat {} + > "$all" 2>/dev/null

nfiles="$(find "$dir" -type f -name '*.txt' | grep -c '' | tr -d ' ')"
if [[ "${nfiles:-0}" -eq 0 ]]; then
  printf '## temp directory tally\n\nNo probe files under `%s`.\n' "$dir"
  exit 0
fi

# awk with index(), the shape used elsewhere in this repository: the value is
# everything after the first `=`, so nothing is re-split on a character the path
# might legitimately contain.
value_of() { # key
  awk -v k="$1=" 'index($0, k) == 1 { print substr($0, length(k) + 1) }' "$all"
}

# Only samples that actually named a Darwin component take part in the
# distribution. A Linux control leaves the field empty and is counted separately
# rather than diluting the percentage.
comp_list="$(value_of varying_component | grep .)"
darwin="$(printf '%s\n' "$comp_list" | grep -c . | tr -d ' ')"
underscored="$(printf '%s\n' "$comp_list" | grep -c '_' | tr -d ' ')"
distinct="$(printf '%s\n' "$comp_list" | grep . | sort -u | grep -c . | tr -d ' ')"

printf '## temp directory tally\n\n'
printf -- '- probe files read: **%s**\n' "$nfiles"
printf -- '- of them naming a Darwin `<b>` component: **%s**\n' "$darwin"

if [[ "${darwin:-0}" -eq 0 ]]; then
  printf -- '- no macOS sample in this set, so there is no distribution to report.\n'
  exit 0
fi

pct=$((100 * underscored / darwin))
printf -- '- distinct `<b>` components across those runners: **%s**\n' "$distinct"
printf -- '- carrying `_`: **%s of %s (%s%%)**\n\n' "$underscored" "$darwin" "$pct"

printf '| `<b>` component | runners | has `_` |\n'
printf '|---|---|---|\n'
printf '%s\n' "$comp_list" | sort | uniq -c | while read -r n c; do
  has=no
  case "$c" in *_*) has=yes ;; esac
  printf '| `%s` | %s | %s |\n' "$c" "$n" "$has"
done

# The suffix half of the note, summed over every iteration on every machine.
iters="$(value_of iterations | awk '{s += $1} END {print s + 0}')"
odd="$(value_of suffix_non_alnum_count | awk '{s += $1} END {print s + 0}')"
chars="$(value_of suffix_non_alnum_chars | grep . | sort -u | tr -d '\n')"
printf '\n### mktemp suffixes\n\n'
printf -- '- suffixes sampled in total: **%s**\n' "$iters"
printf -- '- containing a character outside `[A-Za-z0-9]`: **%s**\n' "$odd"
[[ -n "$chars" ]] && printf -- '- those characters: `%s`\n' "$chars"

# Whoever reads this next will want to quote a rate. What it is a rate OF has to
# travel with it, or the note picks up a number stronger than its evidence —
# which is the mistake the note itself was careful not to make.
printf '\n### what this is a rate of\n\n'
printf 'All %s macOS samples were drawn in one dispatch, from one runner pool,\n' "$darwin"
printf 'within minutes of each other. That measures how the components are\n'
printf 'distributed **across machines at one moment**. It does not measure them\n'
printf 'across time: a runner image rotation can move the whole distribution, and\n'
printf 'this run cannot see that. Quote the number with its date and the runner\n'
printf 'label, never on its own.\n'
exit 0
