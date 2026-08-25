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
summary
