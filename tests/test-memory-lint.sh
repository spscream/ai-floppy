#!/usr/bin/env bash
set -uo pipefail
cd "$(dirname "$0")/.."
. tests/lib.sh
ROOT="$(pwd)"

# memory in a non-default directory, to catch any surviving ".agent-memory"
repo="$(sandbox)"; cp shim/run "$repo/.floppy/run"
echo "memory_dir=brain" > "$repo/.floppy/config"
mkdir -p "$repo/brain/half"
cat > "$repo/brain/MEMORY.md" <<'EOF'
# Index
- [Half](half/INDEX.md) — pointer
EOF
cat > "$repo/brain/half/INDEX.md" <<'EOF'
# Half
- [A note](a-note.md) — pointer
EOF
cat > "$repo/brain/half/a-note.md" <<'EOF'
---
name: a-note
description: a note
metadata:
  type: project
  evidence: read
---
Body.
EOF
printf 'notes_max=10\nchars_max=100000\nnote_chars_max=10000\npointers_max=40\ngrandfathered=\n' > "$repo/brain/quota.lock"

out="$(cd "$repo" && AI_FLOPPY_HOME="$ROOT" bash .floppy/run lint 2>&1)"; rc=$?
assert_rc       "clean memory in a custom dir passes" 0 "$rc"
assert_contains "counts are reported"                 "1 notes"     "$out"
case "$out" in *".agent-memory"*) fail "no hardcoded .agent-memory" "absent" "$out";; *) ok "no hardcoded .agent-memory";; esac

# positive control: a note nobody points at must be caught
cp "$repo/brain/half/a-note.md" "$repo/brain/half/orphan.md"
sed -i.bak 's/^name: a-note/name: orphan/' "$repo/brain/half/orphan.md" && rm -f "$repo/brain/half/orphan.md.bak"
out2="$(cd "$repo" && AI_FLOPPY_HOME="$ROOT" bash .floppy/run lint 2>&1)"; rc2=$?
assert_rc       "orphan note fails the run"  1 "$rc2"
assert_contains "orphan note is named"       "orphan.md" "$out2"

rm -rf "$repo"

# ---------- three-level index tree ----------
# The index became a three-level tree on 2026-08-25 (root -> half -> sub-index
# -> note), after sdk/ hit the 60-pointer cap and the ratchet said to split the
# half rather than raise the number. A clean tree at that depth must pass.
repo3="$(sandbox)"; cp shim/run "$repo3/.floppy/run"
echo "memory_dir=brain" > "$repo3/.floppy/config"
mkdir -p "$repo3/brain/half/sub"
cat > "$repo3/brain/MEMORY.md" <<'EOF'
# Index
- [Half](half/INDEX.md) — pointer
EOF
cat > "$repo3/brain/half/INDEX.md" <<'EOF'
# Half
- [Sub](sub/INDEX.md) — pointer
EOF
cat > "$repo3/brain/half/sub/INDEX.md" <<'EOF'
# Sub
- [A note](note.md) — pointer
EOF
cat > "$repo3/brain/half/sub/note.md" <<'EOF'
---
name: note
description: a note three levels deep
metadata:
  type: project
  evidence: read
---
Body.
EOF
printf 'chars_max=100000\nnote_chars_max=10000\npointers_max=40\ngrandfathered=\n' > "$repo3/brain/quota.lock"

out3="$(cd "$repo3" && AI_FLOPPY_HOME="$ROOT" bash .floppy/run lint 2>&1)"; rc3=$?
assert_rc       "three-level tree passes clean"  0 "$rc3"
assert_contains "three indexes are counted"       "3 indexes" "$out3"

# ---------- orphan sub-index ----------
# A sub-index that its own half never links to used to pass silently: the old
# port only checked each half index against the root MEMORY.md, never against
# its immediate parent. Add a sibling under half/ with its own INDEX.md and
# never link it from half/INDEX.md.
mkdir -p "$repo3/brain/half/orphan-sub"
cat > "$repo3/brain/half/orphan-sub/INDEX.md" <<'EOF'
# Orphan
- [Ghost](ghost.md) — pointer
EOF
cat > "$repo3/brain/half/orphan-sub/ghost.md" <<'EOF'
---
name: ghost
description: a note under an unreachable sub-index
metadata:
  type: project
  evidence: read
---
Body.
EOF

out4="$(cd "$repo3" && AI_FLOPPY_HOME="$ROOT" bash .floppy/run lint 2>&1)"; rc4=$?
assert_rc       "orphan sub-index fails the run"        1 "$rc4"
assert_contains "orphan sub-index is named"              "half/orphan-sub/INDEX.md" "$out4"
assert_contains "orphan sub-index names its own parent"  "not linked from half/INDEX.md" "$out4"

rm -rf "$repo3"

# ---------- note nested past three levels ----------
repo5="$(sandbox)"; cp shim/run "$repo5/.floppy/run"
echo "memory_dir=brain" > "$repo5/.floppy/config"
mkdir -p "$repo5/brain/half/sub/toodeep"
cat > "$repo5/brain/MEMORY.md" <<'EOF'
# Index
- [Half](half/INDEX.md) — pointer
EOF
cat > "$repo5/brain/half/INDEX.md" <<'EOF'
# Half
- [Sub](sub/INDEX.md) — pointer
EOF
cat > "$repo5/brain/half/sub/INDEX.md" <<'EOF'
# Sub
- [A note](note.md) — pointer
EOF
cat > "$repo5/brain/half/sub/note.md" <<'EOF'
---
name: note
description: a note three levels deep
metadata:
  type: project
  evidence: read
---
Body.
EOF
cat > "$repo5/brain/half/sub/toodeep/deep-note.md" <<'EOF'
---
name: deep-note
description: a note nested one level too deep
metadata:
  type: project
  evidence: read
---
Body.
EOF
printf 'chars_max=100000\nnote_chars_max=10000\npointers_max=40\ngrandfathered=\n' > "$repo5/brain/quota.lock"

out5="$(cd "$repo5" && AI_FLOPPY_HOME="$ROOT" bash .floppy/run lint 2>&1)"; rc5=$?
assert_rc       "note past three levels fails the run" 1 "$rc5"
assert_contains "deep note is named"                    "half/sub/toodeep/deep-note.md" "$out5"
assert_contains "depth-limit message"                   "index tree stops at three levels" "$out5"

rm -rf "$repo5"

# ---------- non-numeric quota value ----------
# Previously an unguarded non-numeric value in quota.lock printed its own
# message but also let later comparisons run on the bad value, spilling raw
# bash diagnostics ahead of it. The current script validates before using.
repo6="$(sandbox)"; cp shim/run "$repo6/.floppy/run"
echo "memory_dir=brain" > "$repo6/.floppy/config"
mkdir -p "$repo6/brain/half"
cat > "$repo6/brain/MEMORY.md" <<'EOF'
# Index
- [Half](half/INDEX.md) — pointer
EOF
cat > "$repo6/brain/half/INDEX.md" <<'EOF'
# Half
- [A note](note.md) — pointer
EOF
cat > "$repo6/brain/half/note.md" <<'EOF'
---
name: note
description: a note
metadata:
  type: project
  evidence: read
---
Body.
EOF
printf 'chars_max=abc\nnote_chars_max=10000\npointers_max=40\ngrandfathered=\n' > "$repo6/brain/quota.lock"

out6="$(cd "$repo6" && AI_FLOPPY_HOME="$ROOT" bash .floppy/run lint 2>&1)"; rc6=$?
assert_rc       "non-numeric quota value fails the run" 1 "$rc6"
assert_contains "non-numeric value is named"             "chars_max is 'abc'" "$out6"
case "$out6" in
  *"operand expected"*|*": line "*) fail "no raw bash noise ahead of the message" "absent" "$out6" ;;
  *) ok "no raw bash noise ahead of the message" ;;
esac

rm -rf "$repo6"

# ---------- "does not use this memory layout" names the path ----------
# This is exactly the message a human gets when the wrong project is active
# in a harness that can have several open at once (Cursor especially). In its
# old form it read as "your setup is broken"; naming the repository turns it
# into "you are in the wrong place".
repo7="$(sandbox)"; cp shim/run "$repo7/.floppy/run"
out7="$(cd "$repo7" && AI_FLOPPY_HOME="$ROOT" bash .floppy/run lint 2>&1)"; rc7=$?
assert_rc       "no memory layout: exits 2"                    2 "$rc7"
assert_contains "no memory layout: message names the repository path" "$repo7" "$out7"
assert_contains "no memory layout: still explains what's missing" \
  "this repository does not use this memory layout" "$out7"
rm -rf "$repo7"

# ---------- the size caps come from two places, on purpose ----------
# index_chars_max is a fact about the harness's session loader — the same for
# every project running in it — so it lives in .floppy/config. pointer_line_max
# is a fact about this corpus's writing convention, like pointers_max beside
# it, so it lives in quota.lock. Merging them into one file would make every
# project re-measure somebody else's tool.
repo8="$(sandbox)"; cp shim/run "$repo8/.floppy/run"
echo "memory_dir=brain" > "$repo8/.floppy/config"
mkdir -p "$repo8/brain/half"
cat > "$repo8/brain/half/a-note.md" <<'EOFN'
---
name: a-note
description: a note
metadata:
  type: project
  evidence: read
---
Body.
EOFN
printf '# Half\n- [A note](a-note.md) — pointer\n' > "$repo8/brain/half/INDEX.md"
# A pointer line of 200 ASCII characters: over the 170 default, under a raised cap.
long_line="- [x](half/INDEX.md) $(printf 'y%.0s' $(seq 1 179))"
printf '# Index\n%s\n' "$long_line" > "$repo8/brain/MEMORY.md"

lint8() { OUT8="$(cd "$repo8" && AI_FLOPPY_HOME="$ROOT" bash .floppy/run lint 2>&1)"; RC8=$?; }

lint8
assert_rc       "default pointer_line_max catches a long line" 1 "$RC8"
assert_contains "and says how long it is"  "over 170" "$OUT8"

# Raised in quota.lock — the same line must now pass. Without this the check
# above would also pass on a linter that simply never read the file.
printf 'chars_max=100000\nnote_chars_max=10000\npointers_max=40\npointer_line_max=250\ngrandfathered=\n' > "$repo8/brain/quota.lock"
lint8
assert_rc       "pointer_line_max from quota.lock is honoured" 0 "$RC8"

printf 'chars_max=100000\nnote_chars_max=10000\npointers_max=40\npointer_line_max=nope\ngrandfathered=\n' > "$repo8/brain/quota.lock"
lint8
assert_contains "a non-numeric pointer_line_max is named, not silently used" "pointer_line_max is 'nope'" "$OUT8"
printf 'chars_max=100000\nnote_chars_max=10000\npointers_max=40\ngrandfathered=\n' > "$repo8/brain/quota.lock"

# index_chars_max from .floppy/config. A tiny cap must fail the index; the
# warning threshold is derived from it rather than being a second key.
printf 'memory_dir=brain\nindex_chars_max=50\n' > "$repo8/.floppy/config"
lint8
assert_rc       "index_chars_max from the config is honoured" 1 "$RC8"
assert_contains "and the message quotes the configured cap" "over the 50 cap" "$OUT8"

printf 'memory_dir=brain\nindex_chars_max=oops\n' > "$repo8/.floppy/config"
lint8
assert_contains "a non-numeric index_chars_max is named" "index_chars_max is 'oops'" "$OUT8"
assert_contains "and it falls back to the shipped default" "24500" "$OUT8"
rm -rf "$repo8"


# ---------- the machine-local scope is named by config, not by the script ----------
# The name was spelled into the checks, and the cost of that is not cosmetic:
# the rule "committed memory must not link into the local scope" is what
# protects against links that are dead on a second machine, and under any other
# name it silently applied to nothing.
repo9="$(sandbox)"; cp shim/run "$repo9/.floppy/run"
printf 'memory_dir=brain\nmemory_private_dir=mine\n' > "$repo9/.floppy/config"
mkdir -p "$repo9/brain/half" "$repo9/brain/mine"
printf '# Index\n- [Half](half/INDEX.md) — pointer\n' > "$repo9/brain/MEMORY.md"
printf '# Half\n- [A note](a-note.md) — pointer\n' > "$repo9/brain/half/INDEX.md"
cat > "$repo9/brain/half/a-note.md" <<'EOFN'
---
name: a-note
description: a note
metadata:
  type: project
  evidence: read
---
Body.
EOFN
# A VALID note in the private scope. It has to be valid, because the scope is
# no longer skipped wholesale: the per-note invariants reach it, and only the
# index rules do not. Recognised as the private scope this file passes; read as
# an ordinary half it is an orphan with no pointer line anywhere — which is
# what makes the control below discriminate.
cat > "$repo9/brain/mine/scratch.md" <<'EOFP'
---
name: scratch
description: a private note
metadata:
  type: project
  evidence: read
---
Body.
EOFP

lint9() { OUT9="$(cd "$repo9" && AI_FLOPPY_HOME="$ROOT" bash .floppy/run lint 2>&1)"; RC9=$?; }
lint9
assert_rc       "a renamed private scope is not held to the index rules" 0 "$RC9"
assert_contains "and only the committed note is counted"                 "1 notes" "$OUT9"

# Positive control on the same input: with the default name the scope is not
# recognised, the file becomes an ordinary note in a half, and the index rules
# it was spared now apply to it.
printf 'memory_dir=brain\n' > "$repo9/.floppy/config"
lint9
assert_rc       "under the default name the same file IS held to them" 1 "$RC9"
assert_contains "and it is the scratch file that fails"                "mine/scratch.md" "$OUT9"

# ---------- the per-note invariants DO reach the private scope ----------
# Reported by the owner: nothing ever linted the workplace memory repository.
# Measured 2026-08-25 on the first consumer's store the moment this ran: three
# notes, three without metadata.evidence, invisible until now.
printf 'memory_dir=brain\nmemory_private_dir=mine\n' > "$repo9/.floppy/config"
cat > "$repo9/brain/mine/broken.md" <<'EOFB'
---
name: broken
description: a private note that never says where its claim came from
metadata:
  type: project
---
Body.
EOFB
lint9
assert_rc       "a private note missing evidence turns the run red" 1 "$RC9"
assert_contains "and is named with its configured scope prefix" \
  "mine/broken.md: metadata.evidence is missing" "$OUT9"
# ...but the index rules still do not apply to it: no orphan complaint.
case "$OUT9" in
  *"mine/broken.md: no pointer line"*)
    fail "a private note is still not reported as an orphan" "no orphan line" "$OUT9" ;;
  *) ok "a private note is still not reported as an orphan" ;;
esac
# A dangling [[link]] is a property of the note, so it is caught there too.
printf 'See [[nothing-here]].\n' >> "$repo9/brain/mine/broken.md"
lint9
assert_contains "a dangling [[link]] in a private note is caught" \
  "link [[nothing-here]] resolves to nothing" "$OUT9"
rm -f "$repo9/brain/mine/broken.md"

# README.md introduces the scope, it is not a note in it.
printf '# the private scope of this project\n\nProse, no frontmatter.\n' > "$repo9/brain/mine/README.md"
lint9
assert_rc "a README in the private scope is not linted as a note" 0 "$RC9"
rm -f "$repo9/brain/mine/README.md"

# The quota belongs to the committed corpus, and is not borrowed for this one:
# quota.lock is measured on the memory in THIS repository.
repoQ="$(sandbox)"; cp shim/run "$repoQ/.floppy/run"
printf 'memory_dir=brain\nmemory_private_dir=mine\n' > "$repoQ/.floppy/config"
mkdir -p "$repoQ/brain/half" "$repoQ/brain/mine"
printf '# Index\n- [Half](half/INDEX.md) — pointer\n' > "$repoQ/brain/MEMORY.md"
printf '# Half\n- [A note](a-note.md) — pointer\n' > "$repoQ/brain/half/INDEX.md"
printf -- '---\nname: a-note\ndescription: a note\nmetadata:\n  type: project\n  evidence: read\n---\nshort.\n' \
  > "$repoQ/brain/half/a-note.md"
printf 'notes_max=10\nchars_max=100000\nnote_chars_max=120\npointers_max=40\ngrandfathered=\n' > "$repoQ/brain/quota.lock"
{ printf -- '---\nname: big\ndescription: a long private note\nmetadata:\n  type: project\n  evidence: read\n---\n'
  for i in 1 2 3 4 5 6 7 8; do printf 'padding padding padding padding\n'; done; } > "$repoQ/brain/mine/big.md"
outQ="$(cd "$repoQ" && AI_FLOPPY_HOME="$ROOT" bash .floppy/run lint 2>&1)"; rcQ=$?
assert_rc "the committed corpus's note cap is not applied to the private scope" 0 "$rcQ"
case "$outQ" in
  *"mine/big.md"*) fail "and the private note is not named by the quota section" "not named" "$outQ" ;;
  *)               ok   "and the private note is not named by the quota section" ;;
esac
rm -rf "$repoQ"

# The link rule follows the configured name too.
printf 'memory_dir=brain\nmemory_private_dir=mine\n' > "$repo9/.floppy/config"
printf 'See [that](mine/scratch.md).\n' >> "$repo9/brain/half/a-note.md"
lint9
assert_rc       "a link into the renamed scope is caught"  1 "$RC9"
assert_contains "and names the scope as configured"        "link into mine/" "$OUT9"

# A name that would be read as a regex must be refused, not matched wrongly.
printf 'memory_dir=brain\nmemory_private_dir=.*\n' > "$repo9/.floppy/config"
lint9
assert_rc       "a name with metacharacters is refused" 2 "$RC9"
assert_contains "and says what is allowed"              "plain name" "$OUT9"
rm -rf "$repo9"


# ---------- per-half budgets, and the breakdown when the corpus cap trips ----------
# A corpus-wide number says the memory is too big without saying whose half it
# is, and on a repository worked from two machines those are different people.
# The per-half keys are optional: a corpus that sets none must behave exactly as
# it did before, which is what the first assertion here pins down.
repoH="$(sandbox)"; cp shim/run "$repoH/.floppy/run"
echo "memory_dir=brain" > "$repoH/.floppy/config"
mkdir -p "$repoH/brain/alpha" "$repoH/brain/beta"
printf '# Index\n- [Alpha](alpha/INDEX.md) — pointer\n- [Beta](beta/INDEX.md) — pointer\n- [Root note](root-note.md) — pointer\n' > "$repoH/brain/MEMORY.md"
printf '# Alpha\n- [Big](big.md) — pointer\n' > "$repoH/brain/alpha/INDEX.md"
printf '# Beta\n- [Small](small.md) — pointer\n' > "$repoH/brain/beta/INDEX.md"
note_body() { # $1 name, $2 how many padding characters in the body
  printf -- '---\nname: %s\ndescription: a note\nmetadata:\n  type: project\n  evidence: read\n---\n%s\n' \
    "$1" "$(printf 'x%.0s' $(seq 1 "$2"))"
}
note_body big 2000     > "$repoH/brain/alpha/big.md"
note_body small 50     > "$repoH/brain/beta/small.md"
note_body root-note 50 > "$repoH/brain/root-note.md"
printf 'chars_max=100000\nnote_chars_max=10000\npointers_max=40\ngrandfathered=\n' > "$repoH/brain/quota.lock"

lintH() { OUTH="$(cd "$repoH" && AI_FLOPPY_HOME="$ROOT" bash .floppy/run lint 2>&1)"; RCH=$?; }

lintH
assert_rc "a corpus with no per-half keys is unaffected" 0 "$RCH"
case "$OUTH" in
  *"by half"*) fail "no breakdown on a clean run" "silence" "$OUTH" ;;
  *)           ok   "no breakdown on a clean run" ;;
esac

# One half over its own budget, while the corpus cap is nowhere near.
printf 'chars_max=100000\nnote_chars_max=10000\npointers_max=40\nhalf_chars_max.alpha=500\ngrandfathered=\n' > "$repoH/brain/quota.lock"
lintH
assert_rc       "a half over its own budget fails the run" 1 "$RCH"
assert_contains "and the half that grew is named"          "alpha:" "$OUTH"
assert_contains "and the message quotes that half's cap"   "over the 500 for that half" "$OUTH"
case "$OUTH" in
  *"beta:"*) fail "a half with no key stays unbounded" "beta unmentioned" "$OUTH" ;;
  *)         ok   "a half with no key stays unbounded" ;;
esac

# Root-level notes are their own group, keyed `root` — otherwise the notes that
# every session reads would be the one part of the corpus nobody can bound.
printf 'chars_max=100000\nnote_chars_max=10000\npointers_max=40\nhalf_chars_max.root=10\ngrandfathered=\n' > "$repoH/brain/quota.lock"
lintH
assert_rc       "root-level notes can be budgeted too" 1 "$RCH"
assert_contains "and the root group is named"          "root:" "$OUTH"

# Same treatment as every other lock value: named, not silently applied.
printf 'chars_max=100000\nnote_chars_max=10000\npointers_max=40\nhalf_chars_max.alpha=nope\ngrandfathered=\n' > "$repoH/brain/quota.lock"
lintH
assert_contains "a non-numeric per-half value is named" "half_chars_max.alpha is 'nope'" "$OUTH"

# The corpus cap still fires on its own, and now says where the weight sits.
printf 'chars_max=100\nnote_chars_max=10000\npointers_max=40\ngrandfathered=\n' > "$repoH/brain/quota.lock"
lintH
assert_rc       "the corpus cap still fails on its own" 1 "$RCH"
assert_contains "and the breakdown names the largest half first" "by half: alpha" "$OUTH"
rm -rf "$repoH"


# ---------- the warning band on every ceiling ----------
# A ceiling that only fails stops whoever CROSSES it, and that is routinely not
# whoever filled it: the halves grow on different machines, and the ratchet says
# a number may be raised only in the same commit as the notes that needed the
# room. So the session that trips a hard stop must either raise a ceiling it did
# not fill or prune a half it did not write. The band is what lets the session
# that IS filling one see it happening.
#
# The numbers below are exact character counts, not estimates: note_body writes
# 79 + length(name) + padding characters, so big is 2082 and small is 134, and
# the pair is 2216. A band assertion is only worth anything if the corpus really
# sits inside the band, so these are placed by arithmetic rather than by eye.
repoW="$(sandbox)"; cp shim/run "$repoW/.floppy/run"
echo "memory_dir=brain" > "$repoW/.floppy/config"
mkdir -p "$repoW/brain/alpha" "$repoW/brain/beta"
printf '# Index\n- [Alpha](alpha/INDEX.md) — pointer\n- [Beta](beta/INDEX.md) — pointer\n' > "$repoW/brain/MEMORY.md"
printf '# Alpha\n- [Big](big.md) — pointer\n' > "$repoW/brain/alpha/INDEX.md"
printf '# Beta\n- [Small](small.md) — pointer\n' > "$repoW/brain/beta/INDEX.md"
note_body big 2000 > "$repoW/brain/alpha/big.md"   # 2082 characters
note_body small 50 > "$repoW/brain/beta/small.md"  #  134 characters

lintW() { OUTW="$(cd "$repoW" && AI_FLOPPY_HOME="$ROOT" bash .floppy/run lint 2>&1)"; RCW=$?; }

# Far below every ceiling: still silent. Without this the assertions after it
# would pass just as well on a script that warns about everything always.
printf 'chars_max=100000\nnote_chars_max=10000\npointers_max=40\ngrandfathered=\n' > "$repoW/brain/quota.lock"
lintW
assert_rc "a corpus well under its ceilings passes" 0 "$RCW"
case "$OUTW" in
  *approaching*) fail "and says nothing about approaching anything" "silence" "$OUTW" ;;
  *)             ok   "and says nothing about approaching anything" ;;
esac

# The corpus, at 2216 of 2250 — 98.5%, inside the band, under the cap.
printf 'chars_max=2250\nnote_chars_max=10000\npointers_max=40\ngrandfathered=\n' > "$repoW/brain/quota.lock"
lintW
assert_rc       "a corpus inside the band does not fail the run" 0 "$RCW"
assert_contains "and the corpus cap is named as approaching" "approaching the 2250" "$OUTW"
# Naming which half grew is the whole point of the per-half tally, and a
# warning that omits it sends the reader to measure the corpus by hand.
assert_contains "and the breakdown comes with the warning too" "by half: alpha" "$OUTW"

# One half, at 2082 of 2100 — 99.1%. The corpus cap is nowhere near, so nothing
# but the half can be the source of this line.
printf 'chars_max=100000\nnote_chars_max=10000\npointers_max=40\nhalf_chars_max.alpha=2100\ngrandfathered=\n' > "$repoW/brain/quota.lock"
lintW
assert_rc       "a half inside its band does not fail the run" 0 "$RCW"
assert_contains "and the half that is filling up is named" "alpha: 2082 characters, approaching" "$OUTW"
case "$OUTW" in
  *"beta:"*) fail "and a half with no key is still unbounded" "beta unmentioned" "$OUTW" ;;
  *)         ok   "and a half with no key is still unbounded" ;;
esac

# One note, at 2082 of 2100. A note approaching the cap is a note about to
# become two, and the band is when splitting it is still cheap.
printf 'chars_max=100000\nnote_chars_max=2100\npointers_max=40\ngrandfathered=\n' > "$repoW/brain/quota.lock"
lintW
assert_rc       "a note inside its band does not fail the run" 0 "$RCW"
assert_contains "and the note is named"  "alpha/big.md: 2082 characters, approaching" "$OUTW"
case "$OUTW" in
  *"beta/small.md"*) fail "and a small note is not mentioned" "small unmentioned" "$OUTW" ;;
  *)                 ok   "and a small note is not mentioned" ;;
esac

# Pointers, at 2 of 2 in MEMORY.md: full is inside the band by definition, and
# the fix — split the half — is the same one the failure asks for, only while
# there is still room to do it calmly.
printf 'chars_max=100000\nnote_chars_max=10000\npointers_max=2\ngrandfathered=\n' > "$repoW/brain/quota.lock"
lintW
assert_rc       "an index inside its pointer band does not fail the run" 0 "$RCW"
assert_contains "and the index is named" "MEMORY.md: 2 pointer lines, approaching" "$OUTW"

# Over is still over: the band must not have turned a failure into a hint.
printf 'chars_max=100\nnote_chars_max=10000\npointers_max=40\ngrandfathered=\n' > "$repoW/brain/quota.lock"
lintW
assert_rc "a corpus over its cap still fails" 1 "$RCW"
rm -rf "$repoW"


summary
