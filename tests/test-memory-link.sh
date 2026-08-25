#!/usr/bin/env bash
set -uo pipefail
cd "$(dirname "$0")/.."
. tests/lib.sh
ROOT="$(pwd)"

repo="$(sandbox)"; cp shim/run "$repo/.floppy/run"
echo "memory_dir=brain" > "$repo/.floppy/config"
mkdir -p "$repo/brain"
home="$(mktemp -d)"

out="$(cd "$repo" && HOME="$home" AI_FLOPPY_HOME="$ROOT" bash .floppy/run link --check 2>&1)"; rc=$?
assert_rc       "unwired machine fails"       1 "$rc"
assert_contains "unwired names the fix"       "run link" "$out"

out2="$(cd "$repo" && HOME="$home" AI_FLOPPY_HOME="$ROOT" bash .floppy/run link 2>&1)"
assert_contains "wiring reports success"      "ok" "$out2"

out3="$(cd "$repo" && HOME="$home" AI_FLOPPY_HOME="$ROOT" bash .floppy/run link --check 2>&1)"; rc3=$?
assert_rc       "wired machine passes"        0 "$rc3"

# forked memory: a real directory where the symlink belongs
repo2="$(sandbox)"; cp shim/run "$repo2/.floppy/run"; mkdir -p "$repo2/.agent-memory"
home2="$(mktemp -d)"
enc="$(printf '%s' "$repo2" | tr '/.' '--')"
mkdir -p "$home2/.claude/projects/$enc/memory"
out4="$(cd "$repo2" && HOME="$home2" AI_FLOPPY_HOME="$ROOT" bash .floppy/run link --check 2>&1)"; rc4=$?
assert_rc       "forked memory fails"         1 "$rc4"
assert_contains "forked memory is named"      "real directory" "$out4"

rm -rf "$repo" "$repo2" "$home" "$home2"

# workplace: no project defaults left. An unset workplace_project_key must
# refuse loudly before anything is cloned, symlinked, or moved — a check that
# fires after a side effect is worse than none.
repo3="$(sandbox)"; cp shim/run "$repo3/.floppy/run"
mkdir -p "$repo3/.agent-memory"
home3="$(mktemp -d)"

out5="$(cd "$repo3" && HOME="$home3" AI_FLOPPY_HOME="$ROOT" bash .floppy/run workplace 2>&1)"; rc5=$?
assert_rc       "workplace refuses without project key" 1 "$rc5"
assert_contains "refusal names the config key"           "workplace_project_key" "$out5"
assert_eq       "nothing cloned before the refusal"      "absent" "$([[ -e "$home3/agents_memory" ]] && echo exists || echo absent)"
assert_eq       "no local symlink created either"        "absent" "$([[ -e "$repo3/.agent-memory/local" ]] && echo exists || echo absent)"

# even with a project key, an unset repository URL must also refuse before
# any clone — the second required value guards a different side effect.
echo "workplace_project_key=test-project" > "$repo3/.floppy/config"
out6="$(cd "$repo3" && HOME="$home3" AI_FLOPPY_HOME="$ROOT" bash .floppy/run workplace 2>&1)"; rc6=$?
assert_rc       "workplace refuses without repo url"     1 "$rc6"
assert_contains "refusal names the repo config key"      "workplace_repo" "$out6"
assert_eq       "still nothing cloned"                    "absent" "$([[ -e "$home3/agents_memory" ]] && echo exists || echo absent)"

rm -rf "$repo3" "$home3"
summary
