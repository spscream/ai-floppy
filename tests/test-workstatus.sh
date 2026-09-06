#!/usr/bin/env bash
set -uo pipefail
cd "$(dirname "$0")/.."
. tests/lib.sh
ROOT="$(pwd)"

repo="$(sandbox)"; cp shim/run "$repo/.floppy/run"
: > "$repo/.floppy/config"

# 1. no hook: generic sections print, no project section appears.
out="$(cd "$repo" && AI_FLOPPY_HOME="$ROOT" bash .floppy/run status 2>&1)"
assert_contains "core sections are printed" "-- git" "$out"
assert_contains "origin section is printed" "-- origin" "$out"
assert_contains "status slice section is printed" "-- status slice" "$out"
case "$out" in *"project"*) fail "no project section without a hook" "absent" "$out";; *) ok "no project section without a hook";; esac

# IMPORTANT 4: no private_repo configured — the whole "workplace memory"
# section is skipped, not printed with a "not wired" nudge that then
# dead-ends into "set workplace_project_key in .floppy/config"
# (memory-workplace.sh requires both keys).
case "$out" in
  *"-- workplace memory"*) fail "no workplace section without private_repo" "section absent" "$out" ;;
  *)                       ok   "no workplace section without private_repo" ;;
esac

# 2. a hook that prints something has its output included.
cat > "$repo/.floppy/workstatus-project.sh" <<'EOF'
#!/usr/bin/env bash
echo "  corpora: 3"
EOF
chmod +x "$repo/.floppy/workstatus-project.sh"
out2="$(cd "$repo" && AI_FLOPPY_HOME="$ROOT" bash .floppy/run status 2>&1)"
assert_contains "hook section header prints" "-- project" "$out2"
assert_contains "hook output is included" "corpora: 3" "$out2"

# 3. a hook that exits nonzero is reported as failing, and the report still
# succeeds overall — a status command that dies tells you nothing about the
# state it was asked about.
cat > "$repo/.floppy/workstatus-project.sh" <<'EOF'
#!/usr/bin/env bash
echo "  partial output before the crash"
exit 3
EOF
chmod +x "$repo/.floppy/workstatus-project.sh"
out3="$(cd "$repo" && AI_FLOPPY_HOME="$ROOT" bash .floppy/run status 2>&1)"; rc3=$?
assert_rc       "broken hook does not fail the report" 0 "$rc3"
assert_contains "broken hook's partial output still shows" "partial output before the crash" "$out3"
# Both halves of the warning, not the sentence. The reader's next move is to run
# that file, so the path has to be in it; the exit status is what says whether the
# hook meant it. `3` is this fixture's own code, and asserting the number is what
# would catch a report printing a fixed "nonzero" whatever the hook returned.
assert_contains "broken hook is reported by path"      ".floppy/workstatus-project.sh" "$out3"
assert_contains "broken hook's exit status is named"   "exited 3" "$out3"

# 4. a hook that exists but is not executable must not silently vanish: it is
# reported, and — this is the point of the check — it is NOT run. A marker
# string proves the file was never executed, only stat'd.
cat > "$repo/.floppy/workstatus-project.sh" <<'EOF'
#!/usr/bin/env bash
echo "MARKER-SHOULD-NOT-RUN"
EOF
# The previous step left this same path executable via chmod +x, and `cat >`
# only rewrites content, not permissions — so the exec bit must be dropped
# explicitly, not just "not added", or this step silently tests the wrong thing.
chmod -x "$repo/.floppy/workstatus-project.sh"
out4="$(cd "$repo" && AI_FLOPPY_HOME="$ROOT" bash .floppy/run status 2>&1)"; rc4=$?
assert_rc       "non-executable hook does not fail the report" 0 "$rc4"
assert_contains "non-executable hook is reported"      "not executable" "$out4"
case "$out4" in
  *"MARKER-SHOULD-NOT-RUN"*) fail "non-executable hook is not actually run" "no marker" "$out4" ;;
  *)                         ok   "non-executable hook is not actually run" ;;
esac
rm -f "$repo/.floppy/workstatus-project.sh"

# 5. --flow prints the process-half block; the default run does not.
out5="$(cd "$repo" && AI_FLOPPY_HOME="$ROOT" bash .floppy/run status 2>&1)"
case "$out5" in *"-- process:"*) fail "default run has no process-half block" "absent" "$out5";; *) ok "default run has no process-half block";; esac

out6="$(cd "$repo" && AI_FLOPPY_HOME="$ROOT" bash .floppy/run status --flow 2>&1)"
assert_contains "--flow prints the memory sub-section"      "-- process: memory" "$out6"
assert_contains "--flow prints the lock/worktree sub-section" "-- process: lock and worktrees" "$out6"
assert_contains "--flow prints the recent-edits sub-section"  "-- process: recent edits" "$out6"

# 6. private_repo configured: the section reappears (even unwired).
printf 'private_repo=git@example.com:workplace/agents-memory.git\nworkplace_project_key=test\n' > "$repo/.floppy/config"
out7="$(cd "$repo" && AI_FLOPPY_HOME="$ROOT" bash .floppy/run status 2>&1)"
assert_contains "workplace section appears once private_repo is set" "-- workplace memory" "$out7"

rm -rf "$repo"

# ---------- the private scope is read from the config, not spelled in ----------
# Regression, measured on a live migration: after 0.6.0 renamed the scope,
# this section still looked for `<memory_dir>/local`. On a correctly wired
# repository it printed "not a symlink — run workplace" forever, and a broken
# link under the new name printed nothing. Both directions are asserted here.
#
# Every case below first asserts that the section PRINTED. Without that, a run
# that dies before reaching it satisfies every "does not say X" check for the
# worst possible reason — which is exactly what the first draft of this block
# did, having forgotten to copy the shim into the sandbox.
repoP="$(sandbox)"; cp shim/run "$repoP/.floppy/run"
# The checkout path is derived, not given: agents_memory_dir/.clones/<repo>.
# Building it by hand here (rather than passing a directory) keeps the test
# honest about the layout the verb actually wires.
homeP="$(cd "$(mktemp -d)" && pwd -P)"
wpP="$homeP/agents_memory/.clones/agents-memory"
mkdir -p "$wpP"; git init -q -b main "$wpP"
printf 'private_repo=git@example.com:workplace/agents-memory.git\nproject_key=test\nagents_memory_dir=%s\n' \
  "$homeP/agents_memory" > "$repoP/.floppy/config"
mkdir -p "$repoP/.agent-memory"
ln -s "$wpP" "$repoP/.agent-memory/private"
outP="$(cd "$repoP" && AI_FLOPPY_HOME="$ROOT" bash .floppy/run status 2>&1)"
assert_contains "wired private scope: the section runs at all" "-- workplace memory" "$outP"
case "$outP" in
  *"is not a symlink"*) fail "wired private scope is not reported as unwired" "no nudge" "$outP" ;;
  *)                    ok   "wired private scope is not reported as unwired" ;;
esac

# The nudge still appears when the link genuinely is missing, and it names the
# configured directory rather than the old one.
rm "$repoP/.agent-memory/private"
outP2="$(cd "$repoP" && AI_FLOPPY_HOME="$ROOT" bash .floppy/run status 2>&1)"
assert_contains "missing private link is still reported" "is not a symlink" "$outP2"
assert_contains "the nudge names the private scope" ".agent-memory/private" "$outP2"
case "$outP2" in
  *".agent-memory/local"*) fail "the nudge does not name the pre-0.6.0 scope" "private only" "$outP2" ;;
  *)                       ok   "the nudge does not name the pre-0.6.0 scope" ;;
esac

# An unrefreshed shim exports only the pre-0.6.0 variable; the section must
# follow it rather than fall back to the new default and cry wolf.
#
# The script is called directly here, with the environment such a shim would
# leave. Going through `.floppy/run` cannot express this: the shim recomputes
# both variables from the config and overwrites whatever the caller exported,
# so the case it is meant to reproduce — an OLD shim in front of NEW scripts —
# is unreachable through it.
ln -s "$wpP" "$repoP/.agent-memory/local"
outP3="$(cd "$repoP" && FLOPPY_REPO="$repoP" FLOPPY_MEMORY_DIR=.agent-memory \
  FLOPPY_WORKPLACE_REPO=git@example.com:workplace/agents-memory.git \
  FLOPPY_WORKPLACE_MEMORY_DIR="$wpP" FLOPPY_MEMORY_LOCAL_DIR=local \
  bash "$ROOT/scripts/workstatus.sh" 2>&1)"
assert_contains "pre-0.6.0 name: the section runs at all" "-- workplace memory" "$outP3"
case "$outP3" in
  *"is not a symlink"*) fail "pre-0.6.0 scope name is honoured when that is what is exported" "no nudge" "$outP3" ;;
  *)                    ok   "pre-0.6.0 scope name is honoured when that is what is exported" ;;
esac
rm -rf "$repoP" "$homeP"

# ---------- no personal status is the ordinary state, not a fault ----------
# #19. The project status file gets "! ... is missing — nothing for /start to
# read" when absent, because /start genuinely needs it. The personal one is
# optional: a repository nobody has left a working note in has nothing to
# report, and a warning there would read as a step somebody skipped.
repoN="$(sandbox)"; cp shim/run "$repoN/.floppy/run"
printf 'memory_dir=brain\nstatuses_now=state/NOW.md\n' > "$repoN/.floppy/config"
mkdir -p "$repoN/state" "$repoN/brain"
printf '| Notes | 1 | 2 | up |\n' > "$repoN/state/NOW.md"
git -C "$repoN" add -A
git -C "$repoN" -c user.email=t@t -c user.name=t commit -qm base
outN="$(cd "$repoN" && AI_FLOPPY_HOME="$ROOT" bash .floppy/run status 2>&1)"; rcN=$?
assert_rc "an absent personal status does not fail the report" 0 "$rcN"
case "$outN" in
  *personal*) fail "an absent personal status is not mentioned at all" "no 'personal' line" "$outN" ;;
  *)          ok   "an absent personal status is not mentioned at all" ;;
esac
assert_contains "and the project status is still reported" "state/NOW.md" "$outN"
rm -rf "$repoN"

# ---------- a branch deleted on the remote stops being reported ----------
# Measured here, not imagined: after PRs #29 and #30 merged with
# --delete-branch, `run status` still listed both branches as "other branch,
# newest commit: ... 10 minutes ago". They had been gone from the remote for
# ten minutes; what the report was reading were this checkout's own stale
# remote-tracking refs, which a plain `git fetch` never removes.
#
# That is not a cosmetic wart in a repository whose every change lands as a
# pull request that deletes its branch on merge: it means the section is wrong
# after every single merge, and it is wrong in the direction that invents work
# — a branch named there reads as something still open.
#
# The test runs against a real remote because that is the only place the bug
# lives. A sandbox with no origin can never distinguish a fetch that prunes
# from one that does not.
tmpB="$(cd "$(mktemp -d)" && pwd -P)"
originB="$tmpB/origin.git"
git init -q --bare -b main "$originB"
seedB="$tmpB/seed"
git init -q -b main "$seedB"
: > "$seedB/README"
git -C "$seedB" add -A
git -C "$seedB" -c user.email=t@t -c user.name=t commit -qm base
git -C "$seedB" remote add origin "$originB"
git -C "$seedB" push -q -u origin main
# Two branches, so the assertions can tell "pruned correctly" apart from
# "printed nothing because the report died before this section".
for b in live-branch gone-branch; do
  git -C "$seedB" switch -q -c "$b" main
  git -C "$seedB" -c user.email=t@t -c user.name=t commit -q --allow-empty -m "$b"
  git -C "$seedB" push -q -u origin "$b"
done

repoB="$tmpB/work"
git clone -q "$originB" "$repoB"
mkdir -p "$repoB/.floppy"; cp shim/run "$repoB/.floppy/run"
: > "$repoB/.floppy/config"

# The clone has both remote-tracking refs. Now one branch goes away on the
# remote — exactly what `gh pr merge --delete-branch` does.
git -C "$seedB" push -q origin --delete gone-branch

outB="$(cd "$repoB" && AI_FLOPPY_HOME="$ROOT" bash .floppy/run status 2>&1)"
assert_contains "deleted-branch case: the origin section runs at all" "-- origin" "$outB"
assert_contains "a branch still on the remote is reported" "live-branch" "$outB"
case "$outB" in
  *gone-branch*) fail "a branch deleted on the remote is not reported" "no gone-branch" "$outB" ;;
  *)             ok   "a branch deleted on the remote is not reported" ;;
esac
rm -rf "$tmpB"

# ---------- translations ----------
# The negative control costs nothing: out6 is a --flow run captured earlier from
# a sandbox with no translations in it. A consumer who never translated anything
# should not get an empty heading about a feature they do not use — the same
# rule the worktree line follows.
case "$out6" in
  *"process: translations"*) fail "no translations, no section" "no section" "$out6" ;;
  *) ok "no translations, no section" ;;
esac

# A name with two dots is not a translation. The gate and translation-check.py
# have to agree on that: docs/CHANGELOG.old.md in a repository that never
# translated anything used to raise the whole section.
repoF="$(sandbox)"; cp shim/run "$repoF/.floppy/run"
: > "$repoF/.floppy/config"
mkdir -p "$repoF/docs"
printf '# Changelog\n\nv1\n' > "$repoF/docs/CHANGELOG.old.md"
outF="$(cd "$repoF" && AI_FLOPPY_HOME="$ROOT" bash .floppy/run status --flow 2>&1)"
rm -rf "$repoF"
case "$outF" in
  *"process: translations"*) fail "a two-dot name that is not a translation raises no section" "no section" "$outF" ;;
  *) ok "a two-dot name that is not a translation raises no section" ;;
esac

# An uppercase language tag is not a translation, and this fixture is also how
# the macOS CI job answers a question we cannot answer here: `[a-z]` in a shell
# bracket expression depends on LC_COLLATE, while `[a-z]` in the checker's
# python regex is a literal codepoint range that no locale affects. If a
# collation ever makes the two disagree, this goes red on the runner that
# disagrees.
repoU="$(sandbox)"; cp shim/run "$repoU/.floppy/run"
: > "$repoU/.floppy/config"
printf '# Guide\n\nbody\n' > "$repoU/guide.md"
printf '# Guide\n\nbody\n' > "$repoU/guide.RU.md"
outU="$(cd "$repoU" && AI_FLOPPY_HOME="$ROOT" bash .floppy/run status --flow 2>&1)"
rm -rf "$repoU"
case "$outU" in
  *"process: translations"*) fail "an uppercase language tag is not a translation" "no section" "$outU" ;;
  *) ok "an uppercase language tag is not a translation" ;;
esac

# A directory wearing a translation's name is not a translation either. `ls`
# lists a directory's contents, so this used to open the section.
repoD="$(sandbox)"; cp shim/run "$repoD/.floppy/run"
: > "$repoD/.floppy/config"
mkdir -p "$repoD/docs/x.ru.md"
printf 'hi\n' > "$repoD/docs/x.ru.md/a.md"
outD="$(cd "$repoD" && AI_FLOPPY_HOME="$ROOT" bash .floppy/run status --flow 2>&1)"
rm -rf "$repoD"
case "$outD" in
  *"process: translations"*) fail "a directory named like a translation is not a translation" "no section" "$outD" ;;
  *) ok "a directory named like a translation is not a translation" ;;
esac

# And a translation at the repository root is found, not only one under docs/.
# translation-check.py scans both places, so a gate that scans one of them
# reports nothing for a document that really has fallen behind.
repoR="$(sandbox)"; cp shim/run "$repoR/.floppy/run"
: > "$repoR/.floppy/config"
printf '# Guide\n\nbody\n' > "$repoR/guide.md"
printf '<!-- floppy:translation of=guide.md blob=%s on=2026-01-01 -->\n\n# Гид\n' \
  0000000000000000000000000000000000000000 > "$repoR/guide.ru.md"
outR="$(cd "$repoR" && AI_FLOPPY_HOME="$ROOT" bash .floppy/run status --flow 2>&1)"
rm -rf "$repoR"
if command -v python3 >/dev/null 2>&1; then
  # Two assertions, and the first is the one that reproduces the defect: with a
  # gate that only looks under docs/, this section is not printed at all for a
  # root-level translation.
  assert_contains "a translation at the repository root raises the section" \
    "-- process: translations" "$outR"
  # Sliced from the section header, because the untracked `guide.ru.md` also
  # appears in the `-- git` listing far above — a whole-output search would pass
  # whether or not the checker ever saw the file.
  assert_contains "and the root translation is named inside that section" \
    "guide.ru.md" "$(printf '%s\n' "$outR" | sed -n '/-- process: translations/,$p')"
fi

# The positive control gets a sandbox of its own. The one out6 came from is
# deleted at line 89, and reviving it would stretch a single fixture across
# every unrelated section in between. Built here rather than read out of this
# repository, so the test says the wiring works rather than that this repository
# happens to contain a translation.
repoT="$(sandbox)"; cp shim/run "$repoT/.floppy/run"
: > "$repoT/.floppy/config"
mkdir -p "$repoT/docs"
printf '# Doc\n\nbody\n' > "$repoT/docs/x.md"
# A blob sha no content produces, so the translation is behind by construction.
printf '<!-- floppy:translation of=docs/x.md blob=%s on=2026-01-01 -->\n\n# Док\n' \
  0000000000000000000000000000000000000000 > "$repoT/docs/x.ru.md"
outT="$(cd "$repoT" && AI_FLOPPY_HOME="$ROOT" bash .floppy/run status --flow 2>&1)"
rm -rf "$repoT"
if command -v python3 >/dev/null 2>&1; then
  assert_contains "--flow prints the translations sub-section" "-- process: translations" "$outT"
  assert_contains "and names the translation that is behind" "docs/x.ru.md" \
    "$(printf '%s\n' "$outT" | sed -n '/-- process: translations/,$p')"
else
  printf '  skip python3 not available\n'
fi

summary
