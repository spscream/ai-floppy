#!/usr/bin/env bash
set -uo pipefail
cd "$(dirname "$0")/.."
. tests/lib.sh
ROOT="$(pwd)"

repo="$(sandbox)"; cp shim/run "$repo/.floppy/run"

# 1. acquire, then immediately try to acquire again from the same sandbox:
# the second attempt must refuse, and must not claim the lock is abandoned.
# This is the assertion that failed against the pre-fix stat -c script (see
# report): a lock acquired one instant earlier read as ~57 years old there,
# because `stat -c %Y` does not exist on macOS and the `|| echo 0` fallback
# made every mtime read as the epoch.
out1="$(cd "$repo" && AI_FLOPPY_HOME="$ROOT" bash .floppy/run lock acquire "first" 2>&1)"; rc1=$?
assert_rc       "first acquire succeeds"            0 "$rc1"
assert_contains "first acquire reports ok"           "ok lock acquired" "$out1"

out2="$(cd "$repo" && AI_FLOPPY_HOME="$ROOT" bash .floppy/run lock acquire "second" 2>&1)"; rc2=$?
assert_rc       "second immediate acquire refuses"  1 "$rc2"
assert_contains "second acquire names the holder"    "another session holds the wrap lock" "$out2"
case "$out2" in
  *abandoned*) fail "second acquire does not claim abandoned" "no 'abandoned'" "$out2" ;;
  *)           ok   "second acquire does not claim abandoned" ;;
esac

# 2. status on a fresh lock reports it as held, not as abandoned.
out3="$(cd "$repo" && AI_FLOPPY_HOME="$ROOT" bash .floppy/run lock status 2>&1)"; rc3=$?
assert_rc       "status on fresh lock reports held (rc)" 1 "$rc3"
assert_contains "status on fresh lock says held"          "held, younger than" "$out3"
case "$out3" in
  *abandoned*) fail "status on fresh lock does not say abandoned" "no 'abandoned'" "$out3" ;;
  *)           ok   "status on fresh lock does not say abandoned" ;;
esac

out4="$(cd "$repo" && AI_FLOPPY_HOME="$ROOT" bash .floppy/run lock release 2>&1)"
assert_contains "release clears the lock" "ok lock released" "$out4"

# 3. a lock whose owner file is genuinely old IS taken over, and the takeover
# is announced. Backdate with touch -t rather than sleeping.
out5="$(cd "$repo" && AI_FLOPPY_HOME="$ROOT" bash .floppy/run lock acquire "stale-owner" 2>&1)"
assert_contains "setup: stale-owner lock acquired" "ok lock acquired" "$out5"
gitdir="$(cd "$repo" && git rev-parse --absolute-git-dir)"
owner="$gitdir/wrap.lock/owner"
old_stamp="$(date -v-60M +%Y%m%d%H%M.%S 2>/dev/null || date -d '60 minutes ago' +%Y%m%d%H%M.%S)"
touch -t "$old_stamp" "$owner"

out6="$(cd "$repo" && AI_FLOPPY_HOME="$ROOT" bash .floppy/run lock acquire "new-owner" 2>&1)"; rc6=$?
assert_rc       "stale lock is taken over (rc)"     0 "$rc6"
assert_contains "takeover is announced"              "Taking it over" "$out6"
assert_contains "takeover names the previous owner"  "was: owner=stale-owner" "$out6"

out7="$(cd "$repo" && AI_FLOPPY_HOME="$ROOT" bash .floppy/run lock status 2>&1)"
assert_contains "status after takeover names the new owner" "owner=new-owner" "$out7"

out8="$(cd "$repo" && AI_FLOPPY_HOME="$ROOT" bash .floppy/run lock status 2>&1)"
assert_contains "status names what the lock covers" "covers:" "$out8"
assert_contains "memory inside the repository: the scope is this working copy" \
  "this working copy only" "$out8"

rm -rf "$repo"

# ---------- the store layout: the lock follows the memory, not the clone ----------
# #18. The lock used to live in `git rev-parse --git-dir` unconditionally,
# because "each worktree carries its own memory copy". Measured 2026-09-06:
# with memory_dir a gitignored symlink into a store, it does not — every
# checkout on the machine points at the same notes, while each took a lock of
# its own. Two worktrees of one clone are the cheapest way to reproduce it.
storeS="$(cd "$(mktemp -d)" && pwd -P)"
git init -q -b main "$storeS"
mkdir -p "$storeS/projects/acme/memory" "$storeS/projects/other/memory"
git -C "$storeS" commit -q --allow-empty -m base

repoS="$(sandbox)"; cp shim/run "$repoS/.floppy/run"
cat > "$repoS/.floppy/config" <<EOFS
memory_dir=.agent-memory
project_key=acme
EOFS
printf '/.agent-memory\n' > "$repoS/.gitignore"
ln -s "$storeS/projects/acme/memory" "$repoS/.agent-memory"
git -C "$repoS" add -- .gitignore .floppy
git -C "$repoS" -c user.email=t@t -c user.name=t commit -qm base

outS1="$(cd "$repoS" && AI_FLOPPY_HOME="$ROOT" bash .floppy/run lock acquire "session A" 2>&1)"; rcS1=$?
assert_rc       "store layout: acquire succeeds"  0 "$rcS1"
assert_contains "store layout: the scope is the store, not the clone" \
  "every session on this machine writing $storeS" "$outS1"
assert_eq       "store layout: the lock is in the store's git dir, named for the project" \
  "0" "$([[ -d "$storeS/.git/wrap-acme.lock" ]] && echo 0 || echo 1)"
assert_eq       "store layout: and NOT in this repository's git dir" \
  "1" "$([[ -d "$repoS/.git/wrap.lock" ]] && echo 0 || echo 1)"

# The regression itself: a second worktree of the same clone. .floppy/ is
# tracked so it arrives with the checkout; the memory symlink is gitignored and
# is created per worktree, exactly as `bash .floppy/run store` does.
wtS="$(cd "$(mktemp -d)" && pwd -P)/wt"
git -C "$repoS" worktree add -q "$wtS" -b second 2>/dev/null
ln -s "$storeS/projects/acme/memory" "$wtS/.agent-memory"
assert_eq "setup: the two worktrees really do have different git dirs" "1" \
  "$([[ "$(cd "$repoS" && git rev-parse --absolute-git-dir)" == "$(cd "$wtS" && git rev-parse --absolute-git-dir)" ]] && echo 0 || echo 1)"

outS2="$(cd "$wtS" && AI_FLOPPY_HOME="$ROOT" bash .floppy/run lock acquire "session B" 2>&1)"; rcS2=$?
assert_rc       "store layout: a second worktree is refused (rc)" 1 "$rcS2"
assert_contains "store layout: and told which session holds it" "owner=session A" "$outS2"

# One store holds many projects, and wrapping one must not block the others:
# the lock is named for the project key.
repoO="$(sandbox)"; cp shim/run "$repoO/.floppy/run"
cat > "$repoO/.floppy/config" <<EOFO
memory_dir=.agent-memory
project_key=other
EOFO
printf '/.agent-memory\n' > "$repoO/.gitignore"
ln -s "$storeS/projects/other/memory" "$repoO/.agent-memory"
git -C "$repoO" add -- .gitignore .floppy
git -C "$repoO" -c user.email=t@t -c user.name=t commit -qm base

outO="$(cd "$repoO" && AI_FLOPPY_HOME="$ROOT" bash .floppy/run lock acquire "other project" 2>&1)"; rcO=$?
assert_rc       "store layout: another project in the same store is not blocked" 0 "$rcO"
assert_eq       "store layout: it takes a lock of its own" "0" \
  "$([[ -d "$storeS/.git/wrap-other.lock" ]] && echo 0 || echo 1)"

# Releasing from the second worktree releases the one lock they share — the
# same-resource claim has to hold in both directions, or "covers" is a story.
outR="$(cd "$wtS" && AI_FLOPPY_HOME="$ROOT" bash .floppy/run lock release 2>&1)"
assert_contains "store layout: the other worktree can release the shared lock" \
  "ok lock released" "$outR"
assert_eq       "store layout: and the lock is gone from the store" "1" \
  "$([[ -d "$storeS/.git/wrap-acme.lock" ]] && echo 0 || echo 1)"

git -C "$repoS" worktree remove --force "$wtS" 2>/dev/null
rm -rf "$repoS" "$repoO" "$storeS" "$(dirname "$wtS")"

summary
