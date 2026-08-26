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

# `--scaffold` writes the skeletons this script exists to compare. It lives in
# this file rather than beside it because the generator and the checker have to
# agree on one thing — what in a rite is load-bearing — and two files that must
# agree are the exact arrangement `parity` was written to police.
mode="check"
case "${1:-}" in
  --scaffold) mode="scaffold" ;;
  "")         ;;
  *)          echo "usage: bash .floppy/run parity [--scaffold]" >&2; exit 2 ;;
esac

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

# ---------- the generator ----------
# One skeleton, on stdout, from one skill. What it keeps is exactly what this
# script compares, and it keeps it verbatim: the numbered headings with their
# numbers, and every `.floppy/run` call. What it drops is the English prose,
# which is the whole point — a translator who is handed a copy translates a
# copy, and the steps survive by luck.
#
# A call written inline in prose (`… run \`bash .floppy/run status --flow\` when
# …`) is the case that makes this more than `grep`: dropping that paragraph
# would drop the call, and the file would be red before its author had typed a
# word. Such calls are re-emitted under the step whose prose mentioned them, and
# the ones outside any step go into a section of their own at the end.
#
# Everything is buffered and printed in END so the header can name the sections
# that were left out, which is only known after the whole file has been read.
# $2 is how the skill is named in the generated text, not where it is read
# from: the absolute path of a plugin checkout is one machine's detail, and it
# would be committed into someone's repository on every line that points back
# at the source.
scaffold_one() { # skill_path display_name
  awk -v skill="$2" '
    # One scanner, two jobs. what == "note" files a call under the section that
    # mentions it; what == "emitted" marks it as already present in the text
    # being generated, so it is not repeated. The regex is the one invocations()
    # uses above, and it has to stay that one: it is the whole of what the
    # generator and the checker agree on.
    function scan(line, what,   rest, call) {
      rest = line
      while (match(rest, /\.floppy\/run[ \t]+[a-z][a-z-]*([ \t]+(--?[a-z][a-z-]*|[a-z][a-z-]*))?/)) {
        call = substr(rest, RSTART, RLENGTH)
        sub(/^\.floppy\/run[ \t]+/, "", call)
        gsub(/[ \t]+/, " ", call)
        if (what == "emitted") emitted[call] = 1
        # Ordered lists, not just maps: `for (k in a)` has no defined order in
        # awk, and a generator whose output moves between runs cannot be read
        # as a diff.
        else if (sec == 1) { if (!(call in secseen)) { secseen[call] = 1; seclist[++nsec] = call } }
        else               { if (!(call in preseen)) { preseen[call] = 1; prelist[++npre] = call } }
        rest = substr(rest, RSTART + RLENGTH)
      }
    }
    function out(s) { body = body s "\n" }
    function flush(   i, n) {
      if (sec != 1) return
      out(heading); out("")
      out("<!-- " prose " line(s) of prose here in " skill " — translate them -->")
      out("")
      for (i = 1; i <= nkeep; i++) out(keep[i])
      n = 0
      for (i = 1; i <= nsec; i++) if (!(seclist[i] in emitted)) n++
      if (n > 0) {
        out("<!-- calls this step mentions in its prose — keep them, they are compared -->")
        out("```bash")
        for (i = 1; i <= nsec; i++) if (!(seclist[i] in emitted)) {
          out("bash .floppy/run " seclist[i]); emitted[seclist[i]] = 1
        }
        out("```"); out("")
      }
    }
    function reset() { sec=1; prose=0; nkeep=0; split("", keep); nsec=0; split("", seclist); split("", secseen) }

    NR == 1 && $0 == "---" { fm = 1; next }
    fm == 1 && $0 == "---" { fm = 0; next }
    fm == 1 { if ($0 ~ /^description:[ \t]/) desc = substr($0, index($0, ":") + 2); next }

    # A fence is copied whole or not at all, and only when it carries a call: a
    # fence of example output is prose in a code font and belongs to whoever
    # writes the translation.
    /^```/ {
      if (infence == 0) {
        infence = 1; nf = 0; split("", fbuf); fhas = 0
        fbuf[++nf] = $0; scan($0, "note")
        next
      }
      infence = 0
      fbuf[++nf] = $0
      if (fhas && sec == 1) {
        for (i = 1; i <= nf; i++) { keep[++nkeep] = fbuf[i]; scan(fbuf[i], "emitted") }
        keep[++nkeep] = ""
      }
      next
    }
    infence == 1 {
      fbuf[++nf] = $0
      if ($0 ~ /\.floppy\/run/) fhas = 1
      scan($0, "note")
      next
    }

    /^## / {
      flush()
      if ($0 ~ /^##[ \t]+[0-9]+\./) { reset(); heading = $0 }
      else { sec = 2; unnum[++nun] = substr($0, 4) }
      next
    }

    { if (sec == 1 && $0 ~ /[^ \t]/) prose++; scan($0, "note") }

    END {
      flush()
      # Calls from the preamble and from unnumbered sections have no step to
      # belong to, and a section of their own is honest about that.
      n = 0
      for (i = 1; i <= npre; i++) if (!(prelist[i] in emitted)) n++
      if (n > 0) {
        out("## Calls outside the numbered steps")
        out("")
        out("<!-- from prose that is not part of a step — keep them, they are compared -->")
        out("```bash")
        for (i = 1; i <= npre; i++) if (!(prelist[i] in emitted)) {
          out("bash .floppy/run " prelist[i]); emitted[prelist[i]] = 1
        }
        out("```")
      }

      # Frontmatter first, before any comment: a harness reads it only at the
      # very top of the file.
      print "---"
      print "description: <translate> " desc
      print "---"
      print ""
      print "<!--"
      print "Localized copy of " skill ", generated by the scaffold verb of this"
      print "plugin and then translated by a human. The English skill stays the"
      print "source of truth: where the two differ, the command file is what gets"
      print "fixed."
      print ""
      print "Translate the prose. Two things have to survive the translation exactly:"
      print "  * the numbers of the `## N.` headings — the titles are yours;"
      print "  * every `.floppy/run` line, in ASCII. Argument placeholders — whatever"
      print "    follows `<`, a quote or `$` — are yours to translate."
      print ""
      print "Check the result with the parity verb; the check step of the wrap rite"
      print "runs it on every close."
      if (nun > 0) {
        print ""
        print "Left out, because they are not steps and are not compared. They carry"
        print "meaning: dropping one is a decision, not an oversight."
        for (i = 1; i <= nun; i++) print "  * " unnum[i]
      }
      print "-->"
      print ""
      printf "%s", body
    }
  ' "$1"
}

if [[ "$mode" == "scaffold" ]]; then
  rc=0
  mkdir -p "$commands_dir" || exit 1
  for rite in $RITES; do
    skill="$skills_dir/$rite/SKILL.md"
    cmd="$commands_dir/$rite.md"
    if [[ ! -f "$skill" ]]; then
      echo "  x no skill at $skill — nothing to generate from"
      rc=1
      continue
    fi
    # Never over an existing file. A translation of wrap.md is hours of work and
    # lives in exactly the path this would write.
    if [[ -f "$cmd" ]]; then
      echo "  kept $cmd — already there, not overwritten"
      continue
    fi
    scaffold_one "$skill" "skills/$rite/SKILL.md" > "$cmd"
    # The generator is held to the checker in the same run: a skeleton that
    # cannot pass parity untranslated would teach its reader that the check is
    # wrong, which is the one lesson this whole arrangement cannot afford.
    if [[ -n "$(comm -3 <(invocations "$skill") <(invocations "$cmd"))" ]] \
       || [[ "$(steps "$skill")" != "$(steps "$cmd")" ]]; then
      echo "  x $cmd was generated but does not match $skill — this is a bug in --scaffold"
      rc=1
      continue
    fi
    echo "  wrote $cmd"
  done
  echo
  if [[ $rc -eq 0 ]]; then
    echo "translate the prose, keep the numbers and the calls, then: bash .floppy/run parity"
  fi
  exit $rc
fi

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
