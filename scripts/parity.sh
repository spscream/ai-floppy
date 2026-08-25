#!/usr/bin/env bash
# Compare a repository's localized command files against this plugin's English
# skills, which are the source of truth for the rite.
#
# Why: a project may keep the rite as command files in its own language
# (.claude/commands/wrap.md next to skills/wrap/SKILL.md). Those two copies
# drift, and they drift silently — what is lost is not meaning but a STEP.
# Measured on 2026-08-25, before this script existed: the `workstatus` skill
# documented `bash .floppy/run status --flow` and when to reach for it; the
# Russian `/workstatus` command of the same repository did not mention the flag
# at all. Nothing anywhere went red. A human reading only the command would
# never learn the flag exists.
#
# What is compared, and why only this. Two things survive translation and
# nothing else does:
#
#   1. the set of `bash .floppy/run <verb> …` invocations. A call that exists
#      on one side and not the other IS the lost step, in the only form a
#      script can see without reading prose.
#   2. the sequence of numbered headings (`## N.`). A rite written as numbered
#      steps keeps its numbering across languages; a missing number means a
#      step was dropped or two were merged.
#
# Deliberately NOT compared: heading count, section titles, length, wording.
# Those differ legitimately — a translation folds a tail section into the last
# step, adds a project-specific placement table, drops an example. Asserting
# them would produce red that is fixed by reshaping prose, which trains people
# to ignore the check. (Decided with the consumer project's owner, 2026-08-25:
# heading count was on the table and rejected for exactly this reason.)
#
#   bash .floppy/run parity
#
# Exit 0 when every localized rite matches, 1 on any divergence, 0 with a note
# when the repository has no localized commands at all — using the English
# skills directly is the normal case, not a defect.
#
# Runs on macOS bash 3.2: no mapfile, no declare -A, no GNU-only flags.
set -uo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
cd "${FLOPPY_REPO:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"

skills_dir="${FLOPPY_ROOT:-$here/..}/skills"
commands_dir="${FLOPPY_COMMANDS_DIR:-.claude/commands}"

# The rites, and only the rites. `init` runs once per repository and `agent-
# memory` is a conventions reference with no steps — neither is ever a command,
# so neither has a localized counterpart to diverge from. The list is spelled
# out rather than derived from skills/ so that adding a skill does not silently
# enrol it here; tests/test-parity.sh asserts the two stay in step.
RITES="start workstatus wrap"

# Every `bash .floppy/run <verb> [sub|flag]` invocation in a file, normalized
# and deduplicated. The trailing token is taken only when it is a bare word or
# a flag, which is what distinguishes a real part of the call (`lock acquire`,
# `status --flow`, `commit -m`) from an argument placeholder (`check <file>`,
# `commit -m "<message>"`): a placeholder starts with `<`, a quote or `$` and
# stops the match. Cyrillic prose after a verb stops it too, since the class is
# ASCII — which is the whole reason this works on a translated file.
invocations() {
  grep -ohE '\.floppy/run[[:space:]]+[a-z][a-z-]*([[:space:]]+(--?[a-z][a-z-]*|[a-z][a-z-]*))?' "$1" 2>/dev/null \
    | sed -e 's|^.*\.floppy/run[[:space:]]*||' -e 's|[[:space:]][[:space:]]*| |g' \
    | sort -u
}

# `## 3.` -> `3`. Only `##`: a `###` under a step is a sub-point, and a
# translation is free to add or drop those.
steps() {
  grep -oE '^##[[:space:]]+[0-9]+\.' "$1" 2>/dev/null \
    | grep -oE '[0-9]+' \
    | tr '\n' ' '
}

rc=0
compared=0
missing_cmds=""
present_cmds=""

for rite in $RITES; do
  if [[ -f "$commands_dir/$rite.md" ]]; then
    present_cmds="$present_cmds $rite"
  else
    missing_cmds="$missing_cmds $rite"
  fi
done

if [[ -z "$present_cmds" ]]; then
  echo "no localized commands in $commands_dir — nothing to compare"
  echo "  (a repository that invokes the English skills directly is the normal case)"
  exit 0
fi

# A partially localized rite set is the loudest form of the defect this script
# exists for: whoever reads the commands has a rite that simply does not exist
# in their language, and no error anywhere says so.
if [[ -n "$missing_cmds" ]]; then
  rc=1
  echo "-- missing"
  for rite in $missing_cmds; do
    echo "  x no $commands_dir/$rite.md, but the other rites are localized"
  done
fi

for rite in $present_cmds; do
  skill="$skills_dir/$rite/SKILL.md"
  cmd="$commands_dir/$rite.md"

  if [[ ! -f "$skill" ]]; then
    rc=1
    echo "-- $rite"
    echo "  x $cmd has no skill to compare against at $skill"
    continue
  fi

  compared=$((compared + 1))
  problems=""

  # comm(1) needs sorted input, which invocations() already guarantees.
  only_skill="$(comm -23 <(invocations "$skill") <(invocations "$cmd"))"
  only_cmd="$(comm -13 <(invocations "$skill") <(invocations "$cmd"))"

  while IFS= read -r inv; do
    [[ -z "$inv" ]] && continue
    problems="$problems  x in the skill, not in the command: bash .floppy/run $inv
"
  done <<< "$only_skill"

  while IFS= read -r inv; do
    [[ -z "$inv" ]] && continue
    problems="$problems  x in the command, not in the skill: bash .floppy/run $inv
"
  done <<< "$only_cmd"

  skill_steps="$(steps "$skill")"
  cmd_steps="$(steps "$cmd")"
  if [[ "$skill_steps" != "$cmd_steps" ]]; then
    problems="$problems  x numbered steps differ: skill [${skill_steps% }] command [${cmd_steps% }]
"
  fi

  if [[ -n "$problems" ]]; then
    rc=1
    echo "-- $rite"
    printf '%s' "$problems"
  fi
done

if [[ $rc -eq 0 ]]; then
  echo "clean: $compared localized rite(s) match the skills — same calls, same numbered steps"
else
  echo
  echo "the English skill is the source of truth: fix the command, not the skill"
  echo "  (unless the skill is what is actually missing the step)"
fi
exit $rc
