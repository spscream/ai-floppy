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

# IMPORTANT 4: no workplace_repo configured — the whole "workplace memory"
# section is skipped, not printed with a "not wired" nudge that then
# dead-ends into "set workplace_project_key in .floppy/config"
# (memory-workplace.sh requires both keys).
case "$out" in
  *"-- workplace memory"*) fail "no workplace section without workplace_repo" "section absent" "$out" ;;
  *)                       ok   "no workplace section without workplace_repo" ;;
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
assert_contains "broken hook is reported"              "project hook exited nonzero" "$out3"

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

# 6. workplace_repo configured: the section reappears (even unwired).
printf 'workplace_repo=git@example.com:workplace/agents-memory.git\nworkplace_project_key=test\n' > "$repo/.floppy/config"
out7="$(cd "$repo" && AI_FLOPPY_HOME="$ROOT" bash .floppy/run status 2>&1)"
assert_contains "workplace section appears once workplace_repo is set" "-- workplace memory" "$out7"

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
printf 'workplace_repo=git@example.com:workplace/agents-memory.git\nproject_key=test\nagents_memory_dir=%s\n' \
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

summary
