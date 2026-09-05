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

# IMPORTANT 7: this script wires Claude Code's own memory path specifically
# and does nothing for any other harness the plugin ships to — it must say
# so rather than run silently as if it were harness-agnostic.
assert_contains "wiring says it is Claude-Code-specific" "Cursor" "$out2"

out3="$(cd "$repo" && HOME="$home" AI_FLOPPY_HOME="$ROOT" bash .floppy/run link --check 2>&1)"; rc3=$?
assert_rc       "wired machine passes"        0 "$rc3"

# forked memory: a real directory where the symlink belongs
#
# The state is BUILT, not addressed: wire the repository, find the link the
# script made by looking for it, then replace it with a directory. Nothing
# here restates the encoding rule.
#
# Until 2026-09-05 this block computed the harness's project directory itself,
# with `tr '/.' '--'` — two characters, while the script has folded three since
# 0.16.1. On any sandbox path containing `_` the directory therefore landed
# where `--check` never looks: no fork was found, the message never appeared,
# and this assertion failed. That is the whole of #2, and the reason macOS CI
# was red at random — its TMPDIR is /var/folders/<a>/<b>/T, and <b> is not
# alphanumeric: both failing runs printed one containing `_`, which is why Linux
# (/tmp) never showed it. See
# knowledge/notes/shell/macos-tmpdir-can-contain-underscore.md, which also says
# what was measured and what was inferred.
#
# The comment at the bottom of this file called the recomputation deliberate,
# on the grounds that it "only needs to agree with the script". It stopped
# agreeing, silently, in the one release that changed the rule.
repo2="$(sandbox)"; cp shim/run "$repo2/.floppy/run"; mkdir -p "$repo2/.agent-memory"
home2="$(mktemp -d)"
(cd "$repo2" && HOME="$home2" AI_FLOPPY_HOME="$ROOT" bash .floppy/run link >/dev/null 2>&1)
proj2="$(ls "$home2/.claude/projects" 2>/dev/null)"
assert_eq "the fork setup wired exactly one project directory" \
  "1" "$(printf '%s\n' "$proj2" | grep -c .)"
fork="$home2/.claude/projects/$proj2/memory"
rm -f "$fork"; mkdir -p "$fork"
out4="$(cd "$repo2" && HOME="$home2" AI_FLOPPY_HOME="$ROOT" bash .floppy/run link --check 2>&1)"; rc4=$?
assert_rc       "forked memory fails"         1 "$rc4"
assert_contains "forked memory is named"      "real directory" "$out4"

rm -rf "$repo" "$repo2" "$home" "$home2"

# ---------- the path encoding, for a checkout whose name has an underscore ----------
# Claude Code folds `_` into `-` exactly as it folds `/` and `.`, and this script
# encoded only the latter two. The result is not a failure anywhere: the script
# creates the directory it computed, reports success, and the session writes its
# memory into a project directory the harness never opens. Measured 2026-09-05
# from the harness's own transcripts, which record the real cwd:
#
#   -home-amalaev-work-agents-harness   cwd=/home/amalaev/work/agents_harness
#   -home-amalaev-work-ai-floppy        cwd=/home/amalaev/work/ai_floppy
#   -home-amalaev--local-bin            cwd=/home/amalaev/.local/bin
#
# Two of that machine's three floppy consumers were unwired this way, one of
# them across fifteen sessions, with `status` reporting the wiring as present.
#
# This asserts the RESULT, not the rule: recomputing the encoding here with the
# same `tr` the script uses would agree with any rule the script happened to
# have, which is how the rule was wrong and green at the same time. No block in
# this file encodes the path itself any more — the two that did were changed in
# #2, after one of them spent a release disagreeing with the script and turned
# macOS CI red at random. Case is not folded: `/tmp/consensus-5Ob9Z2` keeps its
# capitals in the harness's own directory name.
repoU="$(mktemp -d)/my_project"
mkdir -p "$repoU/.floppy" "$repoU/brain"
git -C "$(dirname "$repoU")" init -q -b main "$repoU" 2>/dev/null || git init -q -b main "$repoU"
cp shim/run "$repoU/.floppy/run"
echo "memory_dir=brain" > "$repoU/.floppy/config"
homeU="$(mktemp -d)"

outU="$(cd "$repoU" && HOME="$homeU" AI_FLOPPY_HOME="$ROOT" bash .floppy/run link 2>&1)"
assert_contains "an underscore path wires without complaint" "ok" "$outU"

projU="$(ls "$homeU/.claude/projects" 2>/dev/null)"
assert_eq "exactly one project directory is created" "1" "$(printf '%s\n' "$projU" | grep -c .)"
case "$projU" in
  *_*) fail "the encoded directory carries no underscore" "no _ in '$projU'" "$projU" ;;
  *)   ok   "the encoded directory carries no underscore" ;;
esac
case "$projU" in
  *-my-project) ok "the underscore became a dash, as the harness encodes it" ;;
  *) fail "the underscore became a dash, as the harness encodes it" "ends with -my-project" "$projU" ;;
esac

# And the checker agrees with what was just made — the report is the half that
# was lying, not the link.
outU2="$(cd "$repoU" && HOME="$homeU" AI_FLOPPY_HOME="$ROOT" bash .floppy/run link --check 2>&1)"; rcU=$?
assert_rc "the checker sees the link it just made" 0 "$rcU"

rm -rf "$(dirname "$repoU")" "$homeU"

# ---------- the store layout: memory_dir is itself a symlink ----------
# With `store`, memory_dir is a symlink into another repository. This script
# compared `readlink -f` of the harness link — fully resolved — against $mem,
# which is that symlink and not its target, so the two could never be equal:
# `link` refused a machine it had just wired correctly, `--check` never went
# green, and `status` reported "not wired" for the whole external layout. Both
# sides have to be resolved; in the ordinary layout $mem is a real directory
# and resolving it changes nothing, which is what the assertions above keep
# pinned.
repoS="$(sandbox)"; cp shim/run "$repoS/.floppy/run"
echo "memory_dir=brain" > "$repoS/.floppy/config"
storeS="$(mktemp -d)/store"; mkdir -p "$storeS"
ln -s "$storeS" "$repoS/brain"
homeS="$(mktemp -d)"

outS="$(cd "$repoS" && HOME="$homeS" AI_FLOPPY_HOME="$ROOT" bash .floppy/run link 2>&1)"; rcS=$?
assert_rc       "a symlinked memory_dir wires"        0 "$rcS"
assert_contains "and reports the link it created"     "symlink created" "$outS"

outS2="$(cd "$repoS" && HOME="$homeS" AI_FLOPPY_HOME="$ROOT" bash .floppy/run link --check 2>&1)"; rcS2=$?
assert_rc       "and the checker calls it wired"      0 "$rcS2"
case "$outS2" in
  *"points elsewhere"*) fail "and does not call its own link foreign" "no 'points elsewhere'" "$outS2" ;;
  *)                    ok   "and does not call its own link foreign" ;;
esac

# Running it twice is the case a consumer actually hits, since `store` prints
# `next: bash .floppy/run link` and `status` asks the same question afterwards.
outS3="$(cd "$repoS" && HOME="$homeS" AI_FLOPPY_HOME="$ROOT" bash .floppy/run link 2>&1)"; rcS3=$?
assert_rc       "a second run is idempotent, not a refusal" 0 "$rcS3"
assert_contains "and says it was already configured"        "already configured" "$outS3"

# A link into somebody else's memory must still be refused: resolving both
# sides is not the same as comparing nothing.
#
# The link to repoint is found by looking, for the reason given at the top of
# the underscore block. This one folded all three characters and was correct on
# the day #2 was filed — it is changed anyway, because "correct today" is what
# the block above was too, right up to the release that moved the rule.
elsewhere="$(mktemp -d)"
projS="$(ls "$homeS/.claude/projects" 2>/dev/null)"
assert_eq "the store layout wired exactly one project directory" \
  "1" "$(printf '%s\n' "$projS" | grep -c .)"
ln -sfn "$elsewhere" "$homeS/.claude/projects/$projS/memory"
outS4="$(cd "$repoS" && HOME="$homeS" AI_FLOPPY_HOME="$ROOT" bash .floppy/run link --check 2>&1)"; rcS4=$?
assert_rc       "a link to another directory is still refused" 1 "$rcS4"
assert_contains "and says where it actually points"           "points elsewhere" "$outS4"

rm -rf "$repoS" "$(dirname "$storeS")" "$homeS" "$elsewhere"

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
assert_eq       "no local symlink created either"        "absent" "$([[ -e "$repo3/.agent-memory/private" ]] && echo exists || echo absent)"

# even with a project key, an unset repository URL must also refuse before
# any clone — the second required value guards a different side effect.
echo "workplace_project_key=test-project" > "$repo3/.floppy/config"
out6="$(cd "$repo3" && HOME="$home3" AI_FLOPPY_HOME="$ROOT" bash .floppy/run workplace 2>&1)"; rc6=$?
assert_rc       "workplace refuses without repo url"     1 "$rc6"
assert_contains "refusal names the repo config key"      "private_repo" "$out6"
assert_eq       "still nothing cloned"                    "absent" "$([[ -e "$home3/agents_memory" ]] && echo exists || echo absent)"

rm -rf "$repo3" "$home3"

# direct invocation (not through the shim): FLOPPY_MEMORY_DIR unset must not
# crash under `set -u`. mem= and link= already fall back to .agent-memory via
# ${FLOPPY_MEMORY_DIR:-.agent-memory}; a bare $FLOPPY_MEMORY_DIR in a message
# string does not get that fallback and aborts with "unbound variable" the
# moment the code path that prints it is reached — a failure mode the vendor
# originals never had, because they had a literal string there.
unset FLOPPY_MEMORY_DIR 2>/dev/null || true

repo4="$(sandbox)"; mkdir -p "$repo4/.agent-memory"
home4="$(mktemp -d)"

out7="$(cd "$repo4" && HOME="$home4" FLOPPY_REPO="$repo4" bash "$ROOT/scripts/memory-link.sh" 2>&1)"; rc7=$?
assert_rc       "direct memory-link wires without the var"     0 "$rc7"
assert_contains "direct memory-link reports the symlink"       "ok symlink created" "$out7"

out8="$(cd "$repo4" && HOME="$home4" FLOPPY_REPO="$repo4" bash "$ROOT/scripts/memory-link.sh" --check 2>&1)"; rc8=$?
assert_rc       "direct memory-link --check passes without the var" 0 "$rc8"
assert_contains "direct memory-link --check names .agent-memory"    "-> .agent-memory" "$out8"
case "$out8" in
  *"unbound variable"*) fail "direct memory-link --check does not abort" "no 'unbound variable'" "$out8" ;;
  *) ok "direct memory-link --check does not abort" ;;
esac

rm -rf "$repo4" "$home4"

# same check for memory-workplace.sh, which needs a real git remote to clone.
wrepo="$(mktemp -d)"
git init -q --bare -b main "$wrepo/remote.git"
seed="$(mktemp -d)"
git -C "$seed" init -q -b main
git -C "$seed" -c user.email=a@b.c -c user.name=a commit -q --allow-empty -m init
git -C "$seed" remote add origin "$wrepo/remote.git"
git -C "$seed" push -q origin main >/dev/null 2>&1
rm -rf "$seed"

repo5="$(sandbox)"; mkdir -p "$repo5/.agent-memory"
home5="$(mktemp -d)"

out9="$(cd "$repo5" && HOME="$home5" FLOPPY_REPO="$repo5" \
  FLOPPY_WORKPLACE_PROJECT_KEY="direct-test" FLOPPY_WORKPLACE_REPO="$wrepo/remote.git" \
  bash "$ROOT/scripts/memory-workplace.sh" 2>&1)"; rc9=$?
assert_rc       "direct memory-workplace wires without the var" 0 "$rc9"
assert_contains "direct memory-workplace names .agent-memory"   "ok linked: .agent-memory/private -> " "$out9"
case "$out9" in
  *"unbound variable"*) fail "direct memory-workplace does not abort" "no 'unbound variable'" "$out9" ;;
  *) ok "direct memory-workplace does not abort" ;;
esac

rm -rf "$wrepo" "$repo5" "$home5"
summary
