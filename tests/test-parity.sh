#!/usr/bin/env bash
# parity.sh: localized command files against the English skills.
#
# The fixtures below are minimal on purpose — a skill and a command reduced to
# the two things the script actually reads. Testing it against this
# repository's real skills would pass for the wrong reason: they are correct
# today, so a script that compared nothing at all would look just as green.
set -uo pipefail
cd "$(dirname "$0")/.."
ROOT="$(pwd -P)"
. tests/lib.sh

# A sandbox with a fake plugin root (skills/) and a commands dir, so the
# fixtures can diverge in one direction at a time.
#
# `start` and `workstatus` are laid down as trivially matching pairs even
# though every test here is about `wrap`: parity treats a rite localized while
# its siblings are not as a defect in itself, so without them every fixture
# would be red for a reason no test meant to exercise.
make_pair() { # dir skill_body command_body
  local d="$1" r
  mkdir -p "$d/.claude/commands"
  for r in start workstatus; do
    mkdir -p "$d/skills/$r"
    printf '## 0. Step\n' > "$d/skills/$r/SKILL.md"
    printf '## 0. Шаг\n'  > "$d/.claude/commands/$r.md"
  done
  mkdir -p "$d/skills/wrap"
  printf '%s\n' "$2" > "$d/skills/wrap/SKILL.md"
  printf '%s\n' "$3" > "$d/.claude/commands/wrap.md"
}

# Sets OUT and RC as globals rather than echoing: RC assigned inside a command
# substitution dies with the subshell, and every assertion here needs both.
run_parity() { # dir
  local d="$1"
  OUT="$(cd "$d" && FLOPPY_REPO="$d" FLOPPY_ROOT="$d" bash "$ROOT/scripts/parity.sh" 2>&1)"
  RC=$?
}

SKILL_OK='## 0. Lock
```bash
bash .floppy/run lock acquire "<thread>"
```
## 1. Check
```bash
bash .floppy/run check <file>
```'
CMD_OK='## 0. Замок
```bash
bash .floppy/run lock acquire "<ветка работы>"
```
## 1. Проверь
```bash
bash .floppy/run check <файлы>
```'

# ---------- matching pair ----------
d="$(sandbox)"
make_pair "$d" "$SKILL_OK" "$CMD_OK"
run_parity "$d"
assert_eq       "matching pair passes (rc)"          "0" "$RC"
assert_contains "matching pair reports clean"        "clean: 3 localized rite" "$OUT"

# The command is in another language and shaped differently everywhere except
# the two compared invariants — that must not be flagged, or nobody localizes.
d="$(sandbox)"
make_pair "$d" "$SKILL_OK
## Extra section only in English
Prose, a table, an example — none of it compared." "$CMD_OK"
run_parity "$d"
assert_eq       "unnumbered extra section is not a divergence (rc)" "0" "$RC"

# ---------- the measured defect: a call present on one side only ----------
d="$(sandbox)"
make_pair "$d" "$SKILL_OK
Also: \`bash .floppy/run status --flow\` when the task is about the process." "$CMD_OK"
run_parity "$d"
assert_eq       "call missing from the command fails (rc)" "1" "$RC"
assert_contains "the missing call is named"    "in the skill, not in the command: bash .floppy/run status --flow" "$OUT"
assert_contains "the rite is named"            "-- wrap" "$OUT"
assert_contains "the skill is named the source of truth" "source of truth" "$OUT"

# A flag is part of the call, not decoration: `status` alone must NOT satisfy
# `status --flow`. This is the exact shape of the drift found on 2026-08-25.
d="$(sandbox)"
make_pair "$d" "$SKILL_OK
\`bash .floppy/run status --flow\`" "$CMD_OK
\`bash .floppy/run status\`"
run_parity "$d"
assert_eq       "a bare verb does not satisfy verb+flag (rc)" "1" "$RC"
assert_contains "both sides of the flag divergence are named" "status --flow" "$OUT"

# ---------- the reverse direction ----------
d="$(sandbox)"
make_pair "$d" "$SKILL_OK" "$CMD_OK
\`bash .floppy/run guard <файлы>\`"
run_parity "$d"
assert_eq       "call missing from the skill fails (rc)" "1" "$RC"
assert_contains "the reverse direction is named"  "in the command, not in the skill: bash .floppy/run guard" "$OUT"

# ---------- numbered steps ----------
d="$(sandbox)"
make_pair "$d" "$SKILL_OK" '## 0. Замок
```bash
bash .floppy/run lock acquire "<ветка>"
```
```bash
bash .floppy/run check <файлы>
```'
run_parity "$d"
assert_eq       "a dropped numbered step fails (rc)" "1" "$RC"
assert_contains "both step sequences are printed"    "skill [0 1] command [0]" "$OUT"

# A `###` under a step is a sub-point a translation may add or drop freely.
d="$(sandbox)"
make_pair "$d" "$SKILL_OK" "$CMD_OK
### Подпункт, которого нет в скилле"
run_parity "$d"
assert_eq "a h3 sub-point is not a step (rc)" "0" "$RC"

# ---------- placeholders are arguments, not part of the call ----------
# `check <file>` and `check <файлы, которые писал сам>` are the same call.
# Without this the check would go red on every translated argument name, which
# is how a check gets ignored.
d="$(sandbox)"
make_pair "$d" '## 0. A
```bash
bash .floppy/run commit -m "<what the facts are>" <the same files>
```' '## 0. А
```bash
bash .floppy/run commit -m "<про суть фактов>" <те же файлы>
```'
run_parity "$d"
assert_eq       "translated argument placeholders do not diverge (rc)" "0" "$RC"

# ---------- no localized commands at all ----------
d="$(sandbox)"
mkdir -p "$d/skills/wrap"
printf '%s\n' "$SKILL_OK" > "$d/skills/wrap/SKILL.md"
run_parity "$d"
assert_eq       "a repository with no commands dir passes (rc)" "0" "$RC"
assert_contains "and says why there is nothing to compare" "nothing to compare" "$OUT"

# ---------- a partially localized rite set ----------
# One rite localized and another not is the loudest form of the defect: the
# reader has a rite that does not exist in their language and nothing says so.
d="$(sandbox)"
make_pair "$d" "$SKILL_OK" "$CMD_OK"
rm "$d/.claude/commands/start.md"
run_parity "$d"
assert_eq       "a half-localized rite set fails (rc)" "1" "$RC"
assert_contains "the un-localized rite is named"  "no .claude/commands/start.md" "$OUT"

# ---------- commands_dir is configurable ----------
d="$(sandbox)"
make_pair "$d" "$SKILL_OK" "$CMD_OK"
mkdir -p "$d/other"
mv "$d/.claude/commands" "$d/other/commands"
OUT="$(cd "$d" && FLOPPY_REPO="$d" FLOPPY_ROOT="$d" FLOPPY_COMMANDS_DIR=other/commands \
  bash "$ROOT/scripts/parity.sh" 2>&1)"
RC=$?
assert_eq       "FLOPPY_COMMANDS_DIR is honoured (rc)" "0" "$RC"
assert_contains "and it compared the rite there"       "clean: 3 localized rite" "$OUT"
# Guard against the assertion above passing on a stale default: with the
# default path the same sandbox has no commands at all any more.
run_parity "$d"
assert_contains "the default path really is empty now" "nothing to compare" "$OUT"

# ---------- the rite list does not silently fall behind skills/ ----------
# RITES is spelled out in the script so that a new skill is not auto-enrolled.
# The cost of that is a list that can rot: a rite added as a skill and never
# added here would be exempt from parity forever, silently. init and agent-
# memory are excluded on purpose — neither is ever a command file.
rites_in_script="$(grep -m1 '^RITES=' scripts/parity.sh | sed 's/^RITES="//; s/"$//' | tr ' ' '\n' | sort | tr '\n' ' ')"
rites_in_skills="$(find skills -mindepth 1 -maxdepth 1 -type d \
  | sed 's|^skills/||' | grep -vE '^(init|agent-memory)$' | sort | tr '\n' ' ')"
assert_eq "RITES matches skills/ minus init and agent-memory" "$rites_in_skills" "$rites_in_script"

# ---------- the shim exposes it ----------
repo="$(sandbox)"
cp shim/run "$repo/.floppy/run"
usage="$(cd "$repo" && AI_FLOPPY_HOME="$ROOT" bash .floppy/run help 2>&1)"
assert_contains "the shim's usage lists parity" "parity" "$usage"
first="$(cd "$repo" && AI_FLOPPY_HOME="$ROOT" bash .floppy/run parity 2>&1 | head -1)"
assert_eq "parity names the resolved repository first" "repo: $repo" "$first"

# ---------- wrap-check gates on it ----------
# A verb nobody runs is not a guard. check is what runs on every close, so the
# divergence has to be able to turn that red — and has to stay invisible for a
# repository with no localized commands at all.
repo="$(sandbox)"
mkdir -p "$repo/.agent-memory" "$repo/.claude/commands" "$repo/skills/wrap"
printf 'router\n' > "$repo/.agent-memory/MEMORY.md"
printf '%s\n' "$SKILL_OK
\`bash .floppy/run status --flow\`" > "$repo/skills/wrap/SKILL.md"
printf '%s\n' "$CMD_OK" > "$repo/.claude/commands/wrap.md"
git -C "$repo" add -A >/dev/null 2>&1
git -C "$repo" -c user.email=t@t -c user.name=t commit -qm init >/dev/null 2>&1
printf 'changed\n' >> "$repo/.agent-memory/MEMORY.md"
check_out="$(cd "$repo" && FLOPPY_REPO="$repo" FLOPPY_ROOT="$repo" \
  bash "$ROOT/scripts/wrap-check.sh" .agent-memory/MEMORY.md 2>&1)"
check_rc=$?
assert_contains "check reports the localized-commands section" "localized commands" "$check_out"
assert_contains "check names the drifted call"                 "status --flow"      "$check_out"
assert_eq       "check is red on a drifted command"            "1" "$check_rc"

rm -rf "$repo/.claude"
check_out="$(cd "$repo" && FLOPPY_REPO="$repo" FLOPPY_ROOT="$repo" \
  bash "$ROOT/scripts/wrap-check.sh" .agent-memory/MEMORY.md 2>&1)"
case "$check_out" in
  *"localized commands"*) fail "no section without localized commands" "no such section" "$check_out" ;;
  *) ok "no section without localized commands" ;;
esac

# ---------- --scaffold ----------
# The verb that produces the files every test above compares. It exists because
# the README documented the check for months and never documented the artifact:
# a repository was told its command files must not drift, and never told how to
# write one.
#
# A skill with everything the generator has to survive: frontmatter, prose
# before the first step, a call that appears only inline in prose (never in a
# fence), a fenced call, and an unnumbered section.
SKILL_RICH='---
name: wrap
description: Close the session and save what it learned. Use at the end of a session.
---

Intro prose, before any step, mentioning `bash .floppy/run status` in passing.

## 0. Lock

Prose explaining in English why the lock comes first.

```bash
bash .floppy/run lock acquire "<thread>"
```

## 1. Check

Prose that mentions `bash .floppy/run status --flow` inline and nowhere else.

```bash
bash .floppy/run check <file>
```

## Write for a stranger

An unnumbered section: meaning, no steps.'

# `env`, not a bare assignment prefix: bash decides what is an assignment
# before it expands anything, so an expanded `${SCAFFOLD_ENV}` would land in
# the command-name position and the test would fail with 127 while the script
# under test was never run.
scaffold() { # dir — extra environment via SCAFFOLD_ENV
  local d="$1"
  OUT="$(cd "$d" && env FLOPPY_REPO="$d" FLOPPY_ROOT="$d" ${SCAFFOLD_ENV:-} \
    bash "$ROOT/scripts/parity.sh" --scaffold 2>&1)"
  RC=$?
}

d="$(sandbox)"
mkdir -p "$d/skills/wrap"
printf '%s\n' "$SKILL_RICH" > "$d/skills/wrap/SKILL.md"
for r in start workstatus; do
  mkdir -p "$d/skills/$r"
  printf '## 0. Step\n' > "$d/skills/$r/SKILL.md"
done
skill_before="$(cat "$d/skills/wrap/SKILL.md")"
scaffold "$d"
assert_eq       "scaffold succeeds (rc)"        "0" "$RC"
assert_contains "scaffold names what it wrote"  ".claude/commands/wrap.md" "$OUT"
for r in start workstatus wrap; do
  assert_eq "scaffold wrote $r.md" "0" "$([[ -f "$d/.claude/commands/$r.md" ]] && echo 0 || echo 1)"
done

# THE test. A generator whose output does not pass the checker in the same file
# is worse than no generator: it hands a human a file that goes red before they
# have typed anything, and the first thing they learn about parity is that it
# is wrong.
run_parity "$d"
assert_eq       "scaffolded commands pass parity untranslated (rc)" "0" "$RC"
assert_contains "and parity says so"                "clean: 3 localized rite" "$OUT"

cmd="$(cat "$d/.claude/commands/wrap.md")"
assert_eq       "the file opens with frontmatter, so the harness parses it" "---" "$(head -1 "$d/.claude/commands/wrap.md")"
assert_contains "numbered headings survive verbatim"    "## 0. Lock"      "$cmd"
assert_contains "so does the second one"                "## 1. Check"     "$cmd"
assert_contains "fenced calls survive verbatim"         'bash .floppy/run lock acquire "<thread>"' "$cmd"
# The two that are easy to lose: a call written inline in prose that is dropped,
# and a call that appears before the first step. Both would leave a file that
# fails parity the moment it is written.
assert_contains "a call inline in prose is carried over"     "status --flow"   "$cmd"
assert_contains "a call before the first step is carried over" "run status"    "$cmd"
assert_contains "the prose is not carried over"         "translate"       "$cmd"
case "$cmd" in
  *"Prose explaining in English"*) fail "English prose is left out of the skeleton" "no prose" "$cmd" ;;
  *) ok "English prose is left out of the skeleton" ;;
esac
# Unnumbered sections are not steps and are not generated, but dropping one has
# to be a decision: the skeleton names them.
assert_contains "sections left out are named"           "Write for a stranger" "$cmd"
assert_contains "the skeleton says how to check itself" "parity"          "$cmd"
assert_eq       "the skill itself is untouched"         "$skill_before"   "$(cat "$d/skills/wrap/SKILL.md")"

# ---------- a file that already exists is never overwritten ----------
# The scaffold writes into someone's repository. A translation of wrap.md is
# hours of work and lives in exactly the path the generator wants.
d="$(sandbox)"
mkdir -p "$d/skills/wrap" "$d/.claude/commands"
printf '%s\n' "$SKILL_RICH" > "$d/skills/wrap/SKILL.md"
for r in start workstatus; do
  mkdir -p "$d/skills/$r"; printf '## 0. Step\n' > "$d/skills/$r/SKILL.md"
done
printf 'ПЕРЕВЕДЁННЫЙ ВРУЧНУЮ ФАЙЛ\n' > "$d/.claude/commands/wrap.md"
scaffold "$d"
assert_eq       "scaffold over an existing file still succeeds (rc)" "0" "$RC"
assert_eq       "the existing file is untouched" "ПЕРЕВЕДЁННЫЙ ВРУЧНУЮ ФАЙЛ" "$(cat "$d/.claude/commands/wrap.md")"
assert_contains "and it says it kept it"         "kept"  "$OUT"
assert_eq       "the missing siblings are still written" "0" \
  "$([[ -f "$d/.claude/commands/start.md" && -f "$d/.claude/commands/workstatus.md" ]] && echo 0 || echo 1)"

# ---------- it writes where commands_dir says, creating it ----------
d="$(sandbox)"
for r in start workstatus wrap; do
  mkdir -p "$d/skills/$r"; printf '## 0. Step\n' > "$d/skills/$r/SKILL.md"
done
SCAFFOLD_ENV="FLOPPY_COMMANDS_DIR=.cursor/commands" scaffold "$d"
unset SCAFFOLD_ENV
assert_eq       "scaffold honours commands_dir (rc)" "0" "$RC"
assert_eq       "and creates the directory"          "0" \
  "$([[ -f "$d/.cursor/commands/wrap.md" ]] && echo 0 || echo 1)"
assert_eq       "nothing lands in the default path"  "1" \
  "$([[ -d "$d/.claude/commands" ]] && echo 0 || echo 1)"

summary
