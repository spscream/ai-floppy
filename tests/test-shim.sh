#!/usr/bin/env bash
set -uo pipefail
cd "$(dirname "$0")/.."
. tests/lib.sh
ROOT="$(pwd)"

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

# default when there is no config at all
repo2="$(sandbox)"; cp shim/run "$repo2/.floppy/run"
out2="$(cd "$repo2" && AI_FLOPPY_HOME="$ROOT" bash .floppy/run env 2>&1)"
assert_contains "memory_dir defaults" "FLOPPY_MEMORY_DIR=.agent-memory" "$out2"

# a missing plugin must fail loudly, not silently. HOME is pointed at an
# empty directory so this does not depend on whether the real machine happens
# to have a floppy plugin cached (it does, on this one).
empty_home="$(mktemp -d)"
out3="$(cd "$repo2" && HOME="$empty_home" AI_FLOPPY_HOME=/nonexistent CLAUDE_PLUGIN_ROOT= bash .floppy/run lint 2>&1)"; rc3=$?
assert_rc       "missing plugin exits nonzero" 1 "$rc3"
assert_contains "missing plugin names the fix" "plugin install floppy" "$out3"
# With nothing installed under either harness, the failure has to name both
# routes, not just Claude Code's — a Cursor install route led nowhere before.
assert_contains "missing plugin also names Cursor's install route" "Cursor" "$out3"
assert_contains "missing plugin also names the AI_FLOPPY_HOME escape hatch" "AI_FLOPPY_HOME" "$out3"
rm -rf "$empty_home"

# finding 1: an explicitly empty value must not fall back to the default.
# workplace_repo's own default is already '', which would not distinguish the
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
mkdir -p "$fake_home/.claude/plugins/cache/example/floppy/0.9.0/scripts"
mkdir -p "$fake_home/.claude/plugins/cache/example/floppy/0.10.0/scripts"
touch "$fake_home/.claude/plugins/cache/example/floppy/0.9.0/scripts/x.sh"
touch "$fake_home/.claude/plugins/cache/example/floppy/0.10.0/scripts/x.sh"
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
mkdir -p "$home_cu1/.cursor/plugins/cache/floppy/floppy/$sha/scripts"
touch "$home_cu1/.cursor/plugins/cache/floppy/floppy/$sha/scripts/x.sh"
out_cu1="$(cd "$repoCu1" && HOME="$home_cu1" AI_FLOPPY_HOME= CLAUDE_PLUGIN_ROOT= bash .floppy/run env 2>&1)"
assert_contains "Cursor cache: a SHA-named directory resolves" \
  "FLOPPY_ROOT=$home_cu1/.cursor/plugins/cache/floppy/floppy/$sha" "$out_cu1"
rm -rf "$repoCu1" "$home_cu1"

# ---------- Cursor: local development checkout ----------
# ~/.cursor/plugins/local/<name> — a single fixed path (the docs have the
# human symlink it there by hand), nothing to pick among.
repoCu2="$(sandbox)"; cp shim/run "$repoCu2/.floppy/run"
home_cu2="$(mktemp -d)"
mkdir -p "$home_cu2/.cursor/plugins/local/floppy/scripts"
touch "$home_cu2/.cursor/plugins/local/floppy/scripts/x.sh"
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
mkdir -p "$older/scripts" "$newer/scripts"
touch "$older/scripts/x.sh" "$newer/scripts/x.sh"
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
touch "$home_stale/.claude/plugins/cache/mp/floppy/0.1.0/scripts/workstatus.sh"
out_filled="$(cd "$repoStale" && HOME="$home_stale" AI_FLOPPY_HOME= CLAUDE_PLUGIN_ROOT= bash .floppy/run env 2>&1)"
assert_contains "cache with one script resolves" \
  "FLOPPY_ROOT=$home_stale/.claude/plugins/cache/mp/floppy/0.1.0" "$out_filled"
rm -rf "$repoStale" "$home_stale"


# ---------- an unknown verb points at the likeliest cause ----------
# The shim is a COPY in the consumer repository, so a verb added upstream is
# unreachable until that copy is refreshed — and from inside the shim a stale
# copy and a typo are the same event. Measured when `parity` was added: the
# plugin was current, the repository's shim was not, and "unknown verb" alone
# sent the reader looking in the wrong place.
repoU="$(sandbox)"
cp shim/run "$repoU/.floppy/run"
unknown="$(cd "$repoU" && AI_FLOPPY_HOME="$ROOT" bash .floppy/run nosuchverb 2>&1)"
assert_contains "unknown verb names the verb"            "unknown verb: nosuchverb" "$unknown"
assert_contains "unknown verb lists the known ones"      "parity"                   "$unknown"
assert_contains "unknown verb names the stale-copy case" "copy, not a link"         "$unknown"
assert_contains "unknown verb says how to refresh"       "cp "                      "$unknown"


# ---------- a verb the installed plugin is too old for ----------
# The reverse of the case above, and it travels the other way: the shim is
# committed in the consumer repository, so `git pull` carries a new verb to a
# second machine while the plugin there — installed per machine — stays behind.
# `exec` alone reported that as "No such file or directory" naming a path
# inside a plugin cache, which reads as a broken install rather than an
# un-updated one.
oldroot="$(cd "$(mktemp -d)" && pwd -P)"
mkdir -p "$oldroot/scripts"
cp scripts/memory-lint.sh "$oldroot/scripts/"   # enough to resolve as a plugin
repoO="$(sandbox)"
cp shim/run "$repoO/.floppy/run"
behind="$(cd "$repoO" && AI_FLOPPY_HOME="$oldroot" CLAUDE_PLUGIN_ROOT= bash .floppy/run parity 2>&1)"
behind_rc=$?
assert_eq       "old plugin: the verb fails"                "1" "$behind_rc"
assert_contains "old plugin: names the missing script"      "parity.sh"          "$behind"
assert_contains "old plugin: says which side is behind"     "plugin is behind"   "$behind"
assert_contains "old plugin: names the resolved root"       "$oldroot"           "$behind"
# A verb the old plugin DOES have must still work — the guard is per script,
# not a blanket refusal on a version mismatch it has no way to detect.
still="$(cd "$repoO" && AI_FLOPPY_HOME="$oldroot" CLAUDE_PLUGIN_ROOT= bash .floppy/run lint 2>&1; echo "rc=$?")"
assert_contains "old plugin: a verb it does have still runs" "repo: $repoO" "$still"
rm -rf "$oldroot" "$repoO"

summary
