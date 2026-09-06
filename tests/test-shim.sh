#!/usr/bin/env bash
set -uo pipefail
cd "$(dirname "$0")/.."
. tests/lib.sh
ROOT="$(pwd)"

# A directory that resolves as an installed plugin, for the resolution cases
# below. Since 0.14.0 the shim only locates the plugin and execs its
# `scripts/run`, so a root holding scripts/*.sh and nothing else is an install
# too old to dispatch — every case here would then fail on that instead of on
# the question it asks. The dispatcher is a stand-in that reports the one fact
# these cases are about: which root the shim resolved.
fake_root() { # dir
  mkdir -p "$1/scripts"
  touch "$1/scripts/x.sh"
  printf '#!/usr/bin/env bash\nprintf "FLOPPY_ROOT=%%s\\n" "$FLOPPY_ROOT"\n' > "$1/scripts/run"
}

repo="$(sandbox)"
cp shim/run "$repo/.floppy/run"
cat > "$repo/.floppy/config" <<'EOF'
memory_dir=brain
memory_language=en
statuses_now_chars_max=9000
watched_dirs=docs,.floppy
EOF

out="$(cd "$repo" && AI_FLOPPY_HOME="$ROOT" bash .floppy/run env 2>&1)"
assert_contains "memory_dir read from config"      "FLOPPY_MEMORY_DIR=brain"        "$out"
assert_contains "default applied when key absent"  "FLOPPY_WORKPLACE_PROJECT_KEY="  "$out"
assert_contains "repo root resolved"               "FLOPPY_REPO=$repo"              "$out"
assert_contains "numeric key passes through"       "FLOPPY_STATUSES_NOW_CHARS_MAX=9000" "$out"

# The personal status path is DERIVED, not defaulted to a constant (#19): it
# has to land inside the private scope of the configured memory dir, under the
# machine's own name, or two machines write the same path and the whole point
# of the split is lost. Asserted against this config's memory_dir, so a
# hardcoded ".agent-memory/..." would fail here.
sp="$(printf '%s\n' "$out" | sed -n 's/^FLOPPY_STATUSES_PERSONAL=//p')"
assert_contains "personal status is inside the configured memory dir" \
  "brain/private/machines/" "$sp"
# The machine part is asserted as shape, not as this runner's hostname:
# re-deriving the name here would be a test that agrees with whatever the
# script does. The exact naming is pinned by the machine_key case below,
# where the expected value is a constant.
assert_eq "and ends at a per-machine NOW.md" "NOW.md" "${sp##*/}"
case "${sp%/NOW.md}" in
  */machines/?*) ok   "with a non-empty machine name in the path" ;;
  *)             fail "with a non-empty machine name in the path" "machines/<name>" "$sp" ;;
esac

# machine_key overrides the hostname, the same way it does for a note's
# validity path — a hostname is not always a name a human chose.
repoM="$(sandbox)"; cp shim/run "$repoM/.floppy/run"
printf 'machine_key=laptop\n' > "$repoM/.floppy/config"
outM="$(cd "$repoM" && AI_FLOPPY_HOME="$ROOT" bash .floppy/run env 2>&1 | sed -n 's/^FLOPPY_STATUSES_PERSONAL=//p')"
assert_eq "machine_key names the personal status directory" \
  ".agent-memory/private/machines/laptop/NOW.md" "$outM"

# And an explicit key wins over the derivation entirely: a consumer whose
# layout does not have a private scope at all still needs somewhere to put it.
repoP="$(sandbox)"; cp shim/run "$repoP/.floppy/run"
printf 'statuses_personal=state/mine.md\n' > "$repoP/.floppy/config"
outP="$(cd "$repoP" && AI_FLOPPY_HOME="$ROOT" bash .floppy/run env 2>&1 | sed -n 's/^FLOPPY_STATUSES_PERSONAL=//p')"
assert_eq "an explicit statuses_personal is honoured" "state/mine.md" "$outP"
rm -rf "$repoM" "$repoP"

# default when there is no config at all
repo2="$(sandbox)"; cp shim/run "$repo2/.floppy/run"
out2="$(cd "$repo2" && AI_FLOPPY_HOME="$ROOT" bash .floppy/run env 2>&1)"
assert_contains "memory_dir defaults" "FLOPPY_MEMORY_DIR=.agent-memory" "$out2"

# a missing plugin must fail loudly, not silently. HOME is pointed at an
# empty directory so this does not depend on whether the real machine happens
# to have a floppy plugin cached (it does, on this one).
empty_home="$(mktemp -d)"
# AI_FLOPPY_HOME is emptied rather than pointed at /nonexistent: a set-but-
# empty-handed value is now a refusal in its own right (below), and this case
# is about nothing being installed anywhere.
out3="$(cd "$repo2" && HOME="$empty_home" AI_FLOPPY_HOME= CLAUDE_PLUGIN_ROOT= bash .floppy/run lint 2>&1)"; rc3=$?
assert_rc       "missing plugin exits nonzero" 1 "$rc3"
assert_contains "missing plugin names the fix" "plugin install floppy" "$out3"
# With nothing installed under either harness, the failure has to name both
# routes, not just Claude Code's — a Cursor install route led nowhere before.
assert_contains "missing plugin also names Cursor's install route" "Cursor" "$out3"
assert_contains "missing plugin also names the AI_FLOPPY_HOME escape hatch" "AI_FLOPPY_HOME" "$out3"
rm -rf "$empty_home"

# finding 1: an explicitly empty value must not fall back to the default.
# private_repo's own default is already '', which would not distinguish the
# bug from the fix, so this uses memory_dir (default .agent-memory) instead.
repo4="$(sandbox)"; cp shim/run "$repo4/.floppy/run"
printf 'memory_dir=\n' > "$repo4/.floppy/config"
out4="$(cd "$repo4" && AI_FLOPPY_HOME="$ROOT" bash .floppy/run env 2>&1 | sed -n 's/^FLOPPY_MEMORY_DIR=//p')"
assert_eq "explicit empty value stays empty, not the default" "" "$out4"

# finding 2a: spaces around "=" must still be recognized as the key.
repo5="$(sandbox)"; cp shim/run "$repo5/.floppy/run"
printf 'memory_dir = brain\n' > "$repo5/.floppy/config"
out5="$(cd "$repo5" && AI_FLOPPY_HOME="$ROOT" bash .floppy/run env 2>&1)"
assert_contains "key with spaces around '=' is read, not defaulted" "FLOPPY_MEMORY_DIR=brain" "$out5"

# finding 2b: trailing whitespace in the value must be trimmed, not exported
# verbatim into a path five later tasks read. Exact match, not substring.
repo6="$(sandbox)"; cp shim/run "$repo6/.floppy/run"
printf 'memory_dir=brain \n' > "$repo6/.floppy/config"
out6="$(cd "$repo6" && AI_FLOPPY_HOME="$ROOT" bash .floppy/run env 2>&1 | sed -n 's/^FLOPPY_MEMORY_DIR=//p')"
assert_eq "trailing space in config value is trimmed" "brain" "$out6"

# finding 3: the plugin-cache fallback must pick the newest version, and
# lexicographic sort gets that wrong once a double-digit version exists
# (0.10.0 sorts before 0.9.0). Build a fake cache under a fake HOME, with a
# scripts/ dir in each version so the existence guard is satisfied either way.
repo7="$(sandbox)"; cp shim/run "$repo7/.floppy/run"
fake_home="$(mktemp -d)"
fake_root "$fake_home/.claude/plugins/cache/example/floppy/0.9.0"
fake_root "$fake_home/.claude/plugins/cache/example/floppy/0.10.0"
out7="$(cd "$repo7" && HOME="$fake_home" AI_FLOPPY_HOME= CLAUDE_PLUGIN_ROOT= bash .floppy/run env 2>&1)"
assert_contains "cache fallback picks 0.10.0, not lexicographically-later 0.9.0" \
  "FLOPPY_ROOT=$fake_home/.claude/plugins/cache/example/floppy/0.10.0" "$out7"
rm -rf "$fake_home"

# ---------- Cursor: cache path with a SHA-named directory ----------
# Cursor's own layout, measured on the owner's machine — not Claude Code's:
#   ~/.cursor/plugins/cache/<marketplace>/<plugin>/<git-sha>
repoCu1="$(sandbox)"; cp shim/run "$repoCu1/.floppy/run"
home_cu1="$(mktemp -d)"
sha="ed18232fd3b616d570a707fb8464b678b8542dbf"
fake_root "$home_cu1/.cursor/plugins/cache/floppy/floppy/$sha"
out_cu1="$(cd "$repoCu1" && HOME="$home_cu1" AI_FLOPPY_HOME= CLAUDE_PLUGIN_ROOT= bash .floppy/run env 2>&1)"
assert_contains "Cursor cache: a SHA-named directory resolves" \
  "FLOPPY_ROOT=$home_cu1/.cursor/plugins/cache/floppy/floppy/$sha" "$out_cu1"
rm -rf "$repoCu1" "$home_cu1"

# ---------- Cursor: local development checkout ----------
# ~/.cursor/plugins/local/<name> — a single fixed path (the docs have the
# human symlink it there by hand), nothing to pick among.
repoCu2="$(sandbox)"; cp shim/run "$repoCu2/.floppy/run"
home_cu2="$(mktemp -d)"
fake_root "$home_cu2/.cursor/plugins/local/floppy"
out_cu2="$(cd "$repoCu2" && HOME="$home_cu2" AI_FLOPPY_HOME= CLAUDE_PLUGIN_ROOT= bash .floppy/run env 2>&1)"
assert_contains "Cursor local dev checkout resolves" \
  "FLOPPY_ROOT=$home_cu2/.cursor/plugins/local/floppy" "$out_cu2"
rm -rf "$repoCu2" "$home_cu2"

# ---------- Cursor: cache picks newest by MTIME, not by sorting the SHA ----------
# The trap this discriminates: Cursor's cache directory names are git SHAs,
# not versions, so sort -V (correct for Claude Code's semver dirs) orders
# them by hash value — unrelated to recency. Build two candidates whose
# alphabetical order is the OPPOSITE of their actual modification order, and
# backdate with `touch -t` rather than sleeping between them. If the code
# under test reached for sort -V here, it would pick the alphabetically-last
# name ("zzz...") — which this deliberately makes the OLDER one — instead of
# the actually-newest "aaa..." one.
repoCu3="$(sandbox)"; cp shim/run "$repoCu3/.floppy/run"
home_cu3="$(mktemp -d)"
older="$home_cu3/.cursor/plugins/cache/mp/floppy/zzz-alphabetically-last"
newer="$home_cu3/.cursor/plugins/cache/mp/floppy/aaa-alphabetically-first"
fake_root "$older"
fake_root "$newer"
touch -t 202001010000 "$older"
touch -t 202401010000 "$newer"
out_cu3="$(cd "$repoCu3" && HOME="$home_cu3" AI_FLOPPY_HOME= CLAUDE_PLUGIN_ROOT= bash .floppy/run env 2>&1)"
assert_contains "Cursor cache: newest by mtime wins, even sorting alphabetically first" \
  "FLOPPY_ROOT=$newer" "$out_cu3"
case "$out_cu3" in
  *"zzz-alphabetically-last"*) fail "Cursor cache: does not fall for sort -V on SHA-like names" "aaa-alphabetically-first only" "$out_cu3" ;;
  *) ok "Cursor cache: does not fall for sort -V on SHA-like names" ;;
esac
rm -rf "$repoCu3" "$home_cu3"

# MINOR 8: a run outside any git repository must fail loudly, not silently
# fall back to `pwd` and derive every downstream path from the wrong place.
# Discriminates against the old code: `FLOPPY_REPO="$(git rev-parse
# --show-toplevel 2>/dev/null || pwd)"` never fails, so the old shim would
# print FLOPPY_REPO=<the plain dir> here with rc 0 instead of refusing.
plain="$(mktemp -d)"; mkdir -p "$plain/.floppy"; cp shim/run "$plain/.floppy/run"
out8="$(cd "$plain" && AI_FLOPPY_HOME="$ROOT" bash .floppy/run env 2>&1)"; rc8=$?
assert_rc       "outside a git repo: exits nonzero"      1 "$rc8"
assert_contains "outside a git repo: names the problem"  "not inside a git repository" "$out8"
case "$out8" in
  *"FLOPPY_REPO="*) fail "outside a git repo: does not fall back to pwd" "no FLOPPY_REPO= line" "$out8" ;;
  *) ok "outside a git repo: does not fall back to pwd" ;;
esac
rm -rf "$plain"

rm -rf "$repo" "$repo2" "$repo4" "$repo5" "$repo6" "$repo7"

# ---------- every verb names the resolved repository as its first line ----------
# The gap this closes: several projects can be open in the same harness at
# once (Cursor especially), and a skill's shell commands run in whichever one
# the harness landed it in with nothing telling the human which that was. The
# shim already resolves FLOPPY_REPO before dispatching, so printing it as the
# first line of every real verb's output costs nothing. sandbox() uses
# mktemp -d, so this repository's own path is distinctive per run — a
# hardcoded "repo: ..." string cannot pass this the way it could pass against
# a fixed fixture path.
repoV="$(sandbox)"; cp shim/run "$repoV/.floppy/run"
mkdir -p "$repoV/.agent-memory"
printf '# Index\n' > "$repoV/.agent-memory/MEMORY.md"

for verb in lint status check guard; do
  firstline="$(cd "$repoV" && AI_FLOPPY_HOME="$ROOT" bash .floppy/run "$verb" 2>&1 | head -1)"
  assert_eq "$verb: first line names the resolved repository" "repo: $repoV" "$firstline"
done

# commit too, even though it fails immediately for lack of -m/files: the
# naming is printed by the shim before wrap-commit.sh even starts.
firstline_commit="$(cd "$repoV" && AI_FLOPPY_HOME="$ROOT" bash .floppy/run commit 2>&1 | head -1)"
assert_eq "commit: first line names the resolved repository" "repo: $repoV" "$firstline_commit"

rm -rf "$repoV"


# ---------- a cache directory with no scripts is not a plugin ----------
# Measured on 2026-08-25: Claude Code held a floppy cache whose scripts/ held
# only .gitkeep — a snapshot taken minutes after install, before the scripts
# existed — and `claude plugin update` reported "already at the latest version
# (0.1.0)" because the version string had not moved. The old guard tested for
# the DIRECTORY, which was there, so the shim resolved into it happily and
# every verb died with "No such file or directory" pointing inside the plugin
# cache. A user reading that has no way to tell it from a bug in the verb.
repoStale="$(sandbox)"; cp shim/run "$repoStale/.floppy/run"
home_stale="$(mktemp -d)"
mkdir -p "$home_stale/.claude/plugins/cache/mp/floppy/0.1.0/scripts"
touch "$home_stale/.claude/plugins/cache/mp/floppy/0.1.0/scripts/.gitkeep"
out_stale="$(cd "$repoStale" && HOME="$home_stale" AI_FLOPPY_HOME= CLAUDE_PLUGIN_ROOT= bash .floppy/run env 2>&1)"
rc_stale=$?
assert_eq "empty cache: the run fails instead of resolving into it" "1" "$rc_stale"
assert_contains "empty cache: names the install path" "floppy plugin not found" "$out_stale"
assert_contains "empty cache: says update is a no-op on an unchanged version" "no-op" "$out_stale"
case "$out_stale" in
  *"FLOPPY_ROOT=$home_stale"*) fail "empty cache: does not resolve into a scriptless cache" "no FLOPPY_ROOT" "$out_stale" ;;
  *) ok "empty cache: does not resolve into a scriptless cache" ;;
esac

# The same directory becomes valid the moment it holds a real script: the
# guard must gate on content, not punish the layout.
fake_root "$home_stale/.claude/plugins/cache/mp/floppy/0.1.0"
out_filled="$(cd "$repoStale" && HOME="$home_stale" AI_FLOPPY_HOME= CLAUDE_PLUGIN_ROOT= bash .floppy/run env 2>&1)"
assert_contains "cache with one script resolves" \
  "FLOPPY_ROOT=$home_stale/.claude/plugins/cache/mp/floppy/0.1.0" "$out_filled"
rm -rf "$repoStale" "$home_stale"


# ---------- an unknown verb points at the likeliest cause ----------
# Until 0.14.0 the verb table lived in the consumer's copy of the shim, so an
# unknown verb was as likely to mean a stale copy as a typo — measured when
# `parity` was added: the plugin was current, the repository's shim was not,
# and "unknown verb" alone sent the reader looking in the wrong place. The
# table is in the plugin now, so a verb added upstream needs no refresh
# anywhere, and the only remaining causes are a typo and a plugin too old.
repoU="$(sandbox)"
cp shim/run "$repoU/.floppy/run"
unknown="$(cd "$repoU" && AI_FLOPPY_HOME="$ROOT" bash .floppy/run nosuchverb 2>&1)"
assert_contains "unknown verb names the verb"            "unknown verb: nosuchverb" "$unknown"
assert_contains "unknown verb lists the known ones"      "status"                   "$unknown"
assert_contains "unknown verb names the remaining cause" "plugin is behind"         "$unknown"
assert_contains "unknown verb names the root it used"    "$ROOT"                    "$unknown"
# The advice it must NOT give any more: refreshing the copy cannot add a verb
# to a table the copy no longer holds.
case "$unknown" in
  *"copy, not a link"*) fail "unknown verb no longer blames the shim copy" "no shim-refresh advice" "$unknown" ;;
  *) ok "unknown verb no longer blames the shim copy" ;;
esac


# ---------- a plugin too old to dispatch at all ----------
# The shim is committed in the consumer repository and reaches a second machine
# with `git pull`; the plugin there is installed per machine and does not. From
# 0.14.0 the mismatch is coarser than it was: the shim carries no verb table to
# fall back on, so a pre-0.14.0 plugin cannot serve ANY verb, not just the new
# ones. That is a deliberate trade — the alternative is keeping the table in the
# copy, which is the whole cost this release removes — and it is only defensible
# while the refusal says exactly which side is old and how to fix it.
oldroot="$(cd "$(mktemp -d)" && pwd -P)"
mkdir -p "$oldroot/scripts"
cp scripts/memory-lint.sh scripts/workstatus.sh "$oldroot/scripts/"   # resolves as a plugin, has no dispatcher
repoO="$(sandbox)"
cp shim/run "$repoO/.floppy/run"
behind="$(cd "$repoO" && AI_FLOPPY_HOME="$oldroot" CLAUDE_PLUGIN_ROOT= bash .floppy/run status 2>&1)"
behind_rc=$?
assert_eq       "old plugin: the verb fails"                "1" "$behind_rc"
assert_contains "old plugin: names what is missing"         "scripts/run"        "$behind"
assert_contains "old plugin: says which side is old"        "predates"           "$behind"
assert_contains "old plugin: names the resolved root"       "$oldroot"           "$behind"
assert_contains "old plugin: says update is version-gated"  "no-op"              "$behind"
# The deliberate loss, asserted rather than left to be discovered: a verb whose
# script the old plugin does have is refused too, because nothing can dispatch
# it. Before 0.14.0 this one still ran.
also="$(cd "$repoO" && AI_FLOPPY_HOME="$oldroot" CLAUDE_PLUGIN_ROOT= bash .floppy/run lint 2>&1)"
assert_contains "old plugin: even a verb it has is refused" "predates" "$also"
rm -rf "$oldroot" "$repoO"

# ---------- a variable that names the plugin, pointed at no plugin ----------
# Measured 2026-08-25, and it cost a wrong conclusion: AI_FLOPPY_HOME was set
# to a directory holding no plugin, the search fell through to the Claude Code
# cache, an older copy answered, and a script that had just been fixed was
# reported as still broken. Nothing in the output named the copy that ran.
# A cache is a guess and may be skipped in silence; a variable somebody set is
# a statement, and must not be.
repoE="$(sandbox)"; cp shim/run "$repoE/.floppy/run"
homeE="$(mktemp -d)"
# A WORKING cache under the fake HOME, so a pass here proves refusal rather
# than the absence of anywhere to fall through to.
fake_root "$homeE/.claude/plugins/cache/example/floppy/9.9.9"
emptyE="$(mktemp -d)"

outE="$(cd "$repoE" && HOME="$homeE" AI_FLOPPY_HOME="$emptyE" CLAUDE_PLUGIN_ROOT= bash .floppy/run env 2>&1)"; rcE=$?
assert_rc       "AI_FLOPPY_HOME with no plugin refuses (rc)" 1 "$rcE"
assert_contains "and names the variable"                     "AI_FLOPPY_HOME is set to" "$outE"
assert_contains "and names the path it was given"            "$emptyE" "$outE"
case "$outE" in
  *"9.9.9"*) fail "does not fall through to the cache instead" "no cache root" "$outE" ;;
  *)         ok   "does not fall through to the cache instead" ;;
esac

# CLAUDE_PLUGIN_ROOT is the harness's variable, not floppy's: a call made from
# inside another plugin's skill can carry that plugin's root with no mistake by
# anyone. So this one warns and carries on, naming what it used instead.
outC="$(cd "$repoE" && HOME="$homeE" AI_FLOPPY_HOME= CLAUDE_PLUGIN_ROOT="$emptyE" bash .floppy/run env 2>&1)"; rcC=$?
assert_rc       "CLAUDE_PLUGIN_ROOT with no plugin does not stop the run (rc)" 0 "$rcC"
assert_contains "but says it is being ignored"    "CLAUDE_PLUGIN_ROOT is set to" "$outC"
assert_contains "and names the root used instead" "9.9.9" "$outC"
rm -rf "$repoE" "$homeE" "$emptyE"

summary
