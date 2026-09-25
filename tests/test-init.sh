#!/usr/bin/env bash
set -uo pipefail
cd "$(dirname "$0")/.."
. tests/lib.sh
ROOT="$(pwd)"

md5_of() { md5 -q "$1" 2>/dev/null || md5sum "$1" | awk '{print $1}'; }

# ---------- fresh repository, default memory dir ----------
repo="$(sandbox)"
rmdir "$repo/.floppy" 2>/dev/null || true   # sandbox() pre-creates .floppy/; init.sh must not depend on that

bash scripts/init.sh --repo "$repo" --memory-dir .agent-memory --language en >/dev/null

# 0.26.0: init writes data into the repository and no code. The runner it used
# to copy here is gone, and its absence is asserted rather than assumed — a
# `cp` left in by accident would otherwise pass every other check in this file.
assert_eq "no runner placed" "1" "$([[ -f "$repo/.floppy/run" ]] && echo 0 || echo 1)"
assert_eq "config placed"  "0" "$([[ -f "$repo/.floppy/config" ]] && echo 0 || echo 1)"
assert_eq "router placed"  "0" "$([[ -f "$repo/.agent-memory/MEMORY.md" ]] && echo 0 || echo 1)"
assert_eq "no quota.lock"  "1" "$([[ -f "$repo/.agent-memory/quota.lock" ]] && echo 0 || echo 1)"

# IMPORTANT 4: without this, the first `start` on a freshly initialized
# repository has nothing to read and the first `wrap` has nothing to
# update — a dead end that looks broken rather than a fresh repository.
assert_eq "current-state file placed" "0" "$([[ -f "$repo/docs/statuses/NOW.md" ]] && echo 0 || echo 1)"
now_content="$(cat "$repo/docs/statuses/NOW.md")"
assert_contains "current-state file names \`init\`" "\`init\`" "$now_content"
# Generated content lands in a consumer's own repository, read through
# whichever harness they use — Cursor does not namespace skills by plugin
# name, so a floppy:-prefixed reference here would name a skill that does
# not exist there.
case "$now_content" in
  *"floppy:"*) fail "current-state file has no floppy: prefixed skill reference" "no floppy:*" "$now_content" ;;
  *) ok "current-state file has no floppy: prefixed skill reference" ;;
esac

assert_contains "config carries memory_dir"      "memory_dir=.agent-memory" "$(cat "$repo/.floppy/config")"
assert_contains "config carries memory_language" "memory_language=en"      "$(cat "$repo/.floppy/config")"
live_workplace_line="$(grep -v '^[[:space:]]*#' "$repo/.floppy/config" | grep '^private_repo=' || true)"
assert_eq "private_repo not given a live default (uncommented)" "" "$live_workplace_line"

assert_contains "gitignore has the private scope without a trailing slash" "/.agent-memory/private" "$(cat "$repo/.gitignore")"
case "$(cat "$repo/.gitignore")" in
  *"/.agent-memory/private/"*) fail "gitignore line has no trailing slash" "absent" "with slash" ;;
  *) ok "gitignore line has no trailing slash" ;;
esac
# exact-line assertion: a substring check would pass whether or not the slash is there
gi_line="$(grep -x '/.agent-memory/private' "$repo/.gitignore")"
assert_eq "gitignore line matches exactly" "/.agent-memory/private" "$gi_line"
# The leaf has to be the name memory-workplace.sh creates. It was "local" — the
# pre-0.6.0 name that the same script now migrates away from — until 2026-09-05,
# so the ignore guarded a path nothing creates and the real symlink came out
# untracked. A wrong name here is invisible: the file looks configured.
case "$(cat "$repo/.gitignore")" in
  *"/.agent-memory/local"*) fail "gitignore does not name the pre-0.6.0 scope" "private" "local" ;;
  *) ok "gitignore does not name the pre-0.6.0 scope" ;;
esac

agents_content="$(cat "$repo/AGENTS.md")"
assert_contains "AGENTS.md names .floppy/"             ".floppy/"      "$agents_content"
assert_contains "AGENTS.md points at \`agent-memory\`"   "\`agent-memory\`" "$agents_content"
# Same reasoning as the current-state file above: this section is read by a
# stranger in their own repository, in whichever harness they use. The
# agents-section marker (floppy:agents-section) is exempt — it's an
# idempotency marker, not a skill reference.
case "$(printf '%s\n' "$agents_content" | grep -v 'floppy:agents-section')" in
  *"floppy:"*) fail "AGENTS.md section has no floppy: prefixed skill reference" "no floppy:*" "$agents_content" ;;
  *) ok "AGENTS.md section has no floppy: prefixed skill reference" ;;
esac

out="$(cd "$repo" && bash "$ROOT/scripts/run" lint 2>&1)"; rc=$?
assert_rc       "lint is green on empty memory"        0 "$rc"
assert_contains "missing ratchet warns, not fails"      "quota.lock" "$out"
case "$out" in
  *"! quota.lock"*) ok "missing ratchet is a warning line, not an x error" ;;
  *) fail "missing ratchet is a warning line, not an x error" "! quota.lock is missing..." "$out" ;;
esac

# git-init the repo so `status` below has a HEAD to read git/origin state
# from — it must not need that to find the current-state file it was seeded.
git -C "$repo" add -A && git -C "$repo" -c user.email=t@t -c user.name=t commit -qm seed
status_out="$(cd "$repo" && bash "$ROOT/scripts/run" status 2>&1)"
case "$status_out" in
  *"nothing for /start to read"*)
    fail "status finds the seeded current-state file" "no 'nothing for /start to read'" "$status_out" ;;
  *) ok "status finds the seeded current-state file" ;;
esac

# ---------- idempotence: full status + checksums of every touched file ----------
touched="$repo/.floppy/config $repo/.agent-memory/MEMORY.md $repo/.gitignore $repo/AGENTS.md $repo/docs/statuses/NOW.md"
before_status="$(cd "$repo" && git status --porcelain)"
before_sums=""
for f in $touched; do before_sums="$before_sums$(md5_of "$f")"; done

bash scripts/init.sh --repo "$repo" --memory-dir .agent-memory --language en >/dev/null

after_status="$(cd "$repo" && git status --porcelain)"
after_sums=""
for f in $touched; do after_sums="$after_sums$(md5_of "$f")"; done

assert_eq "second run: git status unchanged" "$before_status" "$after_status"
assert_eq "second run: checksums of touched files unchanged" "$before_sums" "$after_sums"

rm -rf "$repo"

# ---------- existing AGENTS.md with content: no duplication, no destruction ----------
repo2="$(sandbox)"
rmdir "$repo2/.floppy" 2>/dev/null || true
cat > "$repo2/AGENTS.md" <<'EOF'
# AGENTS.md

This repository has its own conventions before floppy ever touched it.

## Existing section

Do not delete this. It predates the plugin.
EOF

bash scripts/init.sh --repo "$repo2" --memory-dir .agent-memory --language en >/dev/null
bash scripts/init.sh --repo "$repo2" --memory-dir .agent-memory --language en >/dev/null

content="$(cat "$repo2/AGENTS.md")"
assert_contains "pre-existing heading survives"   "This repository has its own conventions" "$content"
assert_contains "pre-existing section survives"   "Do not delete this. It predates the plugin." "$content"

marker_count="$(grep -c 'floppy:agents-section' "$repo2/AGENTS.md" 2>/dev/null || true)"
[[ -z "$marker_count" ]] && marker_count=0
assert_eq "floppy section appended exactly once, not duplicated" "1" "$marker_count"

rm -rf "$repo2"

# ---------- non-default memory directory, end to end ----------
repo3="$(sandbox)"
rmdir "$repo3/.floppy" 2>/dev/null || true

bash scripts/init.sh --repo "$repo3" --memory-dir brain --language ru >/dev/null

assert_eq "custom dir: router placed"  "0" "$([[ -f "$repo3/brain/MEMORY.md" ]] && echo 0 || echo 1)"
assert_eq "custom dir: no default dir" "1" "$([[ -e "$repo3/.agent-memory" ]] && echo 0 || echo 1)"
assert_contains "custom dir: config carries brain"     "memory_dir=brain"    "$(cat "$repo3/.floppy/config")"
assert_contains "custom dir: config carries language"  "memory_language=ru" "$(cat "$repo3/.floppy/config")"
assert_contains "custom dir: gitignore uses brain"     "/brain/private"      "$(cat "$repo3/.gitignore")"

out3="$(cd "$repo3" && bash "$ROOT/scripts/run" lint 2>&1)"; rc3=$?
assert_rc "custom dir: lint is green" 0 "$rc3"

rm -rf "$repo3"

# ---------- adopting a repository that already has notes ----------
# The case the "no quota.lock" assert near the top deliberately does NOT cover: an
# empty corpus has nothing to measure, one that already exists has. Everything
# here is about measuring it and reporting what the linter thinks — never about
# rewriting a note somebody wrote under other conventions.
repo4="$(sandbox)"
rmdir "$repo4/.floppy" 2>/dev/null || true
mkdir -p "$repo4/.agent-memory"

# One of the three notes is deliberately over the 10000-character cap, so the
# grandfathered branch has something to catch. Without it that branch would be
# asserted by nothing and could rot green.
printf -- '---\nname: small-one\ndescription: d\nmetadata:\n  type: project\n---\n\nbody\n' \
  > "$repo4/.agent-memory/small-one.md"
printf -- '---\nname: small-two\ndescription: d\nmetadata:\n  type: project\n---\n\nbody\n' \
  > "$repo4/.agent-memory/small-two.md"
{ printf -- '---\nname: fat-one\ndescription: d\nmetadata:\n  type: project\n---\n\n'
  i=0; while [[ $i -lt 1200 ]]; do printf 'ten chars.\n'; i=$((i+1)); done; } \
  > "$repo4/.agent-memory/fat-one.md"
printf -- '- [Small one](small-one.md) — a\n- [Small two](small-two.md) — b\n- [Fat one](fat-one.md) — c\n' \
  > "$repo4/.agent-memory/MEMORY.md"

out4="$(bash scripts/init.sh --repo "$repo4" --memory-dir .agent-memory --language en 2>&1)"

assert_contains "adopt: existing notes are counted" "3 note(s) were already here" "$out4"
assert_eq "adopt: quota.lock seeded" "0" \
  "$([[ -f "$repo4/.agent-memory/quota.lock" ]] && echo 0 || echo 1)"

lock4="$(cat "$repo4/.agent-memory/quota.lock" 2>/dev/null || true)"
# The number, not merely the key. A lock seeded from a constant would carry the
# key too, and this corpus sits nowhere near any plausible imported default.
seeded="$(printf '%s\n' "$lock4" | grep '^chars_max=' | cut -d= -f2)"
measured="$(cat "$repo4/.agent-memory"/*.md | wc -m | tr -d ' ')"
assert_eq "adopt: chars_max is above the measured corpus" "0" \
  "$([[ "${seeded:-0}" -gt "$measured" ]] && echo 0 || echo 1)"
assert_eq "adopt: chars_max is not an imported default" "0" \
  "$([[ "${seeded:-0}" -lt $((measured * 2)) ]] && echo 0 || echo 1)"
assert_contains "adopt: the over-cap note is grandfathered, not failed" "fat-one.md" "$lock4"
assert_contains "adopt: lock records what it was seeded from" "notes," "$lock4"
assert_contains "adopt: the linter's verdict is reported" "memory-lint" "$out4"

# Idempotent on this path too. Reseeding a lock that already exists is exactly how
# a ratchet turns into a rubber band.
out4b="$(bash scripts/init.sh --repo "$repo4" --memory-dir .agent-memory --language en 2>&1)"
assert_contains "adopt: second run leaves quota.lock alone" "quota.lock already exists" "$out4b"
assert_eq "adopt: second run did not change the lock" "$lock4" "$(cat "$repo4/.agent-memory/quota.lock")"

rm -rf "$repo4"

# ---------- adoption reports the warnings, not only the verdict ----------
# "clean" means nothing is wrong, which is not the same report as "nothing to
# do": a ceiling inside its warning band passes the run and still asks for work.
# The case that makes this load-bearing is the one adoption creates itself —
# pointers_max is seeded at the longest index found, so that index sits at 100%
# of its own ceiling from the first run. A note grandfathered over the note cap
# is the same shape and far cheaper to build, so it is what this pins down.
repo5="$(sandbox)"
rmdir "$repo5/.floppy" 2>/dev/null || true
mkdir -p "$repo5/.agent-memory"
note5() { # $1 name, $2 how many body lines
  { printf -- '---\nname: %s\ndescription: d\nmetadata:\n  type: project\n  evidence: read\n---\n\n' "$1"
    i=0; while [[ $i -lt "$2" ]]; do printf 'ten chars.\n'; i=$((i+1)); done; }
}
note5 small-one 1  > "$repo5/.agent-memory/small-one.md"
note5 fat-one   1200 > "$repo5/.agent-memory/fat-one.md"
printf -- '- [Small one](small-one.md) — a\n- [Fat one](fat-one.md) — b\n' \
  > "$repo5/.agent-memory/MEMORY.md"

out5="$(bash scripts/init.sh --repo "$repo5" --memory-dir .agent-memory --language en 2>&1)"
assert_contains "adopt: an otherwise clean corpus is reported clean" \
  "memory-lint is clean" "$out5"
assert_contains "adopt: and the warning is printed beside the verdict" \
  "grandfathered in quota.lock" "$out5"
rm -rf "$repo5"

# ---------- an ignore rule that is already covered ----------
# In the store layout memory_dir is ignored whole, so a rule for a path
# underneath it adds nothing — git refuses the subtree either way. Writing it
# anyway leaves two blocks that read as two protections when there is one.
#
# The sibling defect fixed with this one — init writing the narrow
# memory_project_key instead of the umbrella project_key — is asserted in
# test-memory-store.sh, which already has a local store remote to point init
# at. Repeating it here would mean either a second remote or a real clone
# attempt against the network, and this suite touches nothing outside $TMPDIR.
repoI="$(sandbox)"
rmdir "$repoI/.floppy" 2>/dev/null || true
printf '# memory lives in the store repository, not here\n/.agent-memory\n' > "$repoI/.gitignore"

outI="$(bash scripts/init.sh --repo "$repoI" 2>&1)"
case "$(cat "$repoI/.gitignore")" in
  */.agent-memory/private*)
    fail "no private rule under an already-ignored memory_dir" "absent" "$(cat "$repoI/.gitignore")" ;;
  *) ok "no private rule under an already-ignored memory_dir" ;;
esac
assert_contains "and init says why it wrote nothing" "already ignored whole" "$outI"
# The other half of the same branch — the ordinary layout, where memory_dir is
# tracked and the private scope is the only thing the rule protects — is pinned
# by the exact-line assertion near the top of this file, against $repo.
rm -rf "$repoI"

# ---------- a repository initialized before 0.26.0 ----------
# Both reminders are promised in prose — docs/guide/install.md for the stale
# AGENTS.md line, the changelog for the leftover file — and neither had a test,
# so either could stop printing without anything going red. init also has to
# leave the file alone: it is committed, and something of the reader's may
# still call it.
repoM="$(sandbox)"
rmdir "$repoM/.floppy" 2>/dev/null || true
mkdir -p "$repoM/.floppy"
printf '#!/usr/bin/env bash\n' > "$repoM/.floppy/run"
printf '%s\n' '<!-- floppy:agents-section -->' '## Agent memory' \
  'The entry point is `.floppy/run`.' > "$repoM/AGENTS.md"

outM="$(bash scripts/init.sh --repo "$repoM" 2>&1)"
assert_contains "a leftover runner is named"          ".floppy/run is left over" "$outM"
assert_contains "and the command that drops it"       "git rm .floppy/run"       "$outM"
assert_contains "a stale AGENTS.md line is named"     "AGENTS.md still names .floppy/run" "$outM"
assert_contains "and the call to write in its place"  "bash <plugin>/scripts/run <verb>"  "$outM"
assert_eq "init leaves the leftover file where it is" "0" \
  "$([[ -f "$repoM/.floppy/run" ]] && echo 0 || echo 1)"
rm -rf "$repoM"

# ---------- a watch list that names the runner ----------
# A hand-written entry, not something an init ever wrote: every released
# version writes watched_files commented out and without the runner in it. So
# what is asserted here is that the reminder reads the config the way the
# parser does, and that its ADVICE follows the file — dropping the entry while
# .floppy/run is still tracked takes guard coverage off a tracked file.
#
# The runner is gone: the entry names nothing, and dropping it is safe.
repoW="$(sandbox)"
printf '%s\n' 'memory_dir=.agent-memory' 'memory_language=en' \
  'watched_files=AGENTS.md,.floppy/run,.floppy/config' > "$repoW/.floppy/config"
cfg_before="$(cat "$repoW/.floppy/config")"

outW="$(bash scripts/init.sh --repo "$repoW" 2>&1)"
assert_contains "a watched_files entry for the runner is named" \
  "lists .floppy/run under watched_files" "$outW"
assert_contains "with no runner there, the entry names a file that is gone" \
  "names a file that is gone" "$outW"
assert_contains "and dropping it is what is advised" "Drop that one entry" "$outW"
assert_eq "and init edits nobody's config" "$cfg_before" "$(cat "$repoW/.floppy/config")"
rm -rf "$repoW"

# The runner is still there: the entry is not stale, it is the only reason
# `wrap` may commit an edit to that file. Measured 2026-09-26 — drop it alone
# and `guard .floppy/run` goes from rc 0 to rc 1 — so the advice must not be
# "drop that one entry" in this state.
repoY="$(sandbox)"
printf '%s\n' 'memory_dir=.agent-memory' 'watched_files=AGENTS.md,.floppy/run' \
  > "$repoY/.floppy/config"
printf '#!/usr/bin/env bash\n' > "$repoY/.floppy/run"
outY="$(bash scripts/init.sh --repo "$repoY" 2>&1)"
assert_contains "with the runner present, the entry is said to still cover it" \
  "still covers it" "$outY"
case "$outY" in
  *"Drop that one entry"*)
    fail "and dropping the entry alone is not advised" "no bare drop advice" "$outY" ;;
  *)
    ok   "and dropping the entry alone is not advised" ;;
esac
rm -rf "$repoY"

# Read like the parser, not with a looser grep. cfg_get takes the first
# `^[[:space:]]*key[[:space:]]*=` line, so both spellings below are live
# settings; `.floppy/runner.md` is a different file and must not be reported.
# All three were measured against a `^watched_files=.*\.floppy/run` grep on
# 2026-09-26: two misses and one false positive.
for wf_case in 'watched_files = AGENTS.md,.floppy/run' \
               '  watched_files=AGENTS.md, .floppy/run' \
               'watched_files=AGENTS.md,.floppy/runner.md'; do
  repoZ="$(sandbox)"
  printf '%s\n%s\n' 'memory_dir=.agent-memory' "$wf_case" > "$repoZ/.floppy/config"
  outZ="$(bash scripts/init.sh --repo "$repoZ" 2>&1)"
  case "$wf_case" in
    *runner.md)
      case "$outZ" in
        *"under watched_files"*) fail "a different file is not reported: $wf_case" "no reminder" "$outZ" ;;
        *)                       ok   "a different file is not reported: $wf_case" ;;
      esac ;;
    *)
      assert_contains "a spelling the parser accepts is seen: $wf_case" \
        "under watched_files" "$outZ" ;;
  esac
  rm -rf "$repoZ"
done

# And a config with no such entry stays quiet: a reminder that prints for
# everyone is a reminder nobody reads.
repoX="$(sandbox)"
printf '%s\n' 'memory_dir=.agent-memory' 'watched_files=AGENTS.md,.floppy/config' \
  > "$repoX/.floppy/config"
outX="$(bash scripts/init.sh --repo "$repoX" 2>&1)"
case "$outX" in
  *"under watched_files"*)
    fail "a clean watch list is not warned about" "no reminder" "$outX" ;;
  *)
    ok   "a clean watch list is not warned about" ;;
esac
rm -rf "$repoX"

# The AGENTS.md reminder does not hang off the section marker: a repository
# whose stale mention sits anywhere else in the file gets a fresh section
# appended and still carries the old instruction above it.
repoN="$(sandbox)"
rmdir "$repoN/.floppy" 2>/dev/null || true
printf '%s\n' '# Notes' 'Run `bash .floppy/run status` first.' > "$repoN/AGENTS.md"
outN="$(bash scripts/init.sh --repo "$repoN" 2>&1)"
assert_contains "a mention outside the floppy section is caught too" \
  "AGENTS.md still names .floppy/run" "$outN"
rm -rf "$repoN"

# ---------- a relative --repo under an exported CDPATH ----------
# CDPATH with a relative entry in it makes `cd` print the directory it found,
# and that print lands inside the command substitution that resolves --repo.
# Measured 2026-09-25 (review of PR #95, finding 1): $repo came out two lines
# long, init created a directory whose name ends in a newline BESIDE the
# target, printed `ok` at every step and exited 0, and the repository it had
# been pointed at kept nothing but its .git.
#
# Two conditions have to meet, which is why nothing else in this file catches
# it: the CDPATH entry has to be relative, and the --repo spelling has to be
# one `cd` consults — neither absolute (every other call here) nor `.`.
parentC="$(cd "$(mktemp -d)" && pwd -P)"
mkdir -p "$parentC/target"
git -C "$parentC/target" init -q -b main

outC="$(cd "$parentC" && CDPATH=".:$parentC" bash "$ROOT/scripts/init.sh" --repo target 2>&1)"; rcC=$?
assert_rc "a relative --repo under CDPATH succeeds"  0 "$rcC"
assert_eq "and the header names one path, not two" \
  "memory_dir:  .agent-memory" "$(printf '%s\n' "$outC" | sed -n 2p)"
assert_eq "the config lands in the repository that was named" "0" \
  "$([[ -f "$parentC/target/.floppy/config" ]] && echo 0 || echo 1)"
# The newline-named sibling is what `ok` on every step was hiding, so count
# what is there rather than trust the report: two entries means the work went
# somewhere nobody asked for.
assert_eq "and nothing is created beside it" "1" \
  "$(ls -1 "$parentC" | wc -l | tr -d ' ')"
rm -rf "$parentC"

summary
