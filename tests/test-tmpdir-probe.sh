#!/usr/bin/env bash
# The temp-directory probe reports, the tally counts, and both are wired to a
# workflow that actually runs them.
#
# Structural, like test-docs.sh: nothing here asserts what a macOS temp path
# looks like — that is the measurement, and this suite runs on Linux more often
# than not. What it asserts is that the sampler emits the fields the tally reads,
# that the tally arrives at the right numbers from known input, and that the two
# workflows still call them. A probe nobody dispatches produces no samples and
# looks exactly like one that does.
set -uo pipefail
cd "$(dirname "$0")/.."
. tests/lib.sh

probe=knowledge/probes/tmpdir-probe.sh
tally=knowledge/probes/tmpdir-tally.sh

# ---------- 1. the probe runs anywhere and reports rather than gates ----------
out="$(TMPDIR_PROBE_ITERATIONS=5 bash "$probe" 2>&1)"; rc=$?
assert_rc "probe exits 0" 0 "$rc"

for k in probe_version uname_s tmpdir_source tmpdir iterations \
         distinct_parent_dirs suffix_non_alnum_count suffix_non_alnum_chars \
         sample_path mktemp_parent darwin_a darwin_b varying_component \
         varying_component_non_alnum varying_component_has_underscore \
         mktemp_parent_resolved parent_is_symlinked; do
  # Anchored on the line start: `tmpdir=` must not be satisfied by the
  # `tmpdir_source=` line, which is exactly the near-miss the tally would then
  # read as an empty value.
  case "
$out" in *"
$k="*) ok "probe emits $k" ;; *) fail "probe emits $k" "a line starting $k=" "$out" ;; esac
done

it="$(printf '%s\n' "$out" | awk 'index($0, "iterations=") == 1 { print substr($0, 12) }')"
assert_eq "probe honours the iteration count" "5" "$it"

# The assertion that carries the argument. If a loop on one machine could see
# more than one parent directory, sampling by iteration would answer the
# frequency question and the twenty-runner fan-out would be waste. It cannot:
# the parent is per user and per boot session on Darwin, and fixed at /tmp on
# Linux. This is the line that would go red if that stopped being true.
dp="$(printf '%s\n' "$out" | awk 'index($0, "distinct_parent_dirs=") == 1 { print substr($0, 22) }')"
assert_eq "N iterations on one machine see exactly one parent directory" "1" "$dp"

# The probe must clean up after itself: it creates a directory per iteration, and
# a step that runs on every macOS push is a bad place to leak them.
#
# Counted inside a TMPDIR of this test's own, never in the shared one. The first
# version of this assertion counted `tmp.*` under /tmp and passed alone and
# failed in the suite, because tests/run.sh runs nineteen files at once and every
# one of them builds its sandbox there — it was measuring the machine, not the
# probe. A count is only evidence about the thing under test when nothing else
# can write to what is being counted.
iso="$(mktemp -d)"
TMPDIR="$iso" TMPDIR_PROBE_ITERATIONS=5 bash "$probe" >/dev/null 2>&1
left="$(find "$iso" -mindepth 1 2>/dev/null | grep -c . | tr -d ' ')"
assert_eq "probe leaves nothing behind in its own TMPDIR" "0" "$left"
rm -rf "$iso"

# ---------- 2. the tally, from input whose answer is known by hand ----------
# Hand-written samples, not probe output: a tally checked against the thing it
# reads would agree with any bug the two happen to share, which is precisely how
# the defect behind the note stayed hidden.
d="$(mktemp -d)"
mk() { # file, component, iterations, odd-suffix-count
  printf 'probe_version=1\nuname_s=Darwin\nvarying_component=%s\niterations=%s\nsuffix_non_alnum_count=%s\nsuffix_non_alnum_chars=\n' \
    "$2" "$3" "$4" > "$d/$1"
}
mk probe-1.txt aaa_bbb 10 0
mk probe-2.txt aaa_bbb 10 0
mk probe-3.txt cccddd  10 0
printf 'probe_version=1\nuname_s=Linux\nvarying_component=\niterations=10\nsuffix_non_alnum_count=0\nsuffix_non_alnum_chars=\n' \
  > "$d/probe-linux.txt"

t="$(bash "$tally" "$d" 2>&1)"; trc=$?
assert_rc "tally exits 0" 0 "$trc"
assert_contains "tally counts every file it read"        "probe files read: **4**"  "$t"
assert_contains "and only the Darwin ones in the sample" "component: **3**"         "$t"
assert_contains "distinct components"                    "components across those runners: **2**" "$t"
assert_contains "and the underscore share"               "**2 of 3 (66%)**"         "$t"
assert_contains "the table names a component"            '| `aaa_bbb` | 2 | yes |'  "$t"
assert_contains "and marks one without an underscore"    '| `cccddd` | 1 | no |'    "$t"
assert_contains "suffixes are summed across machines"    "sampled in total: **40**" "$t"
# Without this the run produces a percentage with nothing attached, and a
# percentage travels further than the sentence that qualifies it.
assert_contains "the tally states what its rate is a rate of" "across machines at one moment" "$t"

# A directory with no samples is a fact about the runner queue, not a crash.
empty="$(mktemp -d)"
e="$(bash "$tally" "$empty" 2>&1)"; erc=$?
assert_rc "tally exits 0 on an empty directory" 0 "$erc"
assert_contains "and says so" "No probe files" "$e"

# A macOS-free set must not print a distribution over zero machines.
onlylinux="$(mktemp -d)"
cp "$d/probe-linux.txt" "$onlylinux/"
l="$(bash "$tally" "$onlylinux" 2>&1)"
assert_contains "tally invents no distribution without a macOS sample" "no macOS sample" "$l"

# Missing arguments are a usage error, not a silent tally of nothing.
bash "$tally" >/dev/null 2>&1; urc=$?
assert_rc "tally refuses to run without a directory" 2 "$urc"

rm -rf "$d" "$empty" "$onlylinux"

# ---------- 3. the workflows are wired to the scripts ----------
# Same reasoning as the schedule assertions in test-knowledge.sh and
# test-site.sh: a workflow that stopped calling the script would keep running,
# keep going green, and say nothing. Here the loss is silent in a second way —
# no samples accumulate, and the absence of data reads as "not measured yet"
# rather than as a break.
tw="$(cat .github/workflows/tests.yml 2>/dev/null || true)"
assert_contains "the suite workflow samples the temp path on every macOS run" "$probe" "$tw"

pw="$(cat .github/workflows/tmpdir-probe.yml 2>/dev/null || true)"
assert_contains "the probe workflow runs the sampler" "$probe" "$pw"
assert_contains "and the tally"                       "$tally" "$pw"
# The fan-out is the whole design: the sampling unit is the machine, so a
# workflow that lost its matrix would sample one runner and report a
# distribution over it.
assert_contains "and fans out over a matrix of runners" "fromJSON(needs.plan.outputs.matrix)" "$pw"
assert_contains "on macOS, where the varying component exists" "macos-latest" "$pw"
# The Linux control is what makes "Linux has no such component" measured here
# rather than assumed.
assert_contains "with a Linux control"                 "control-linux" "$pw"
# Dispatch-only. A schedule here would spend macOS runners re-measuring a fact
# that moves only when GitHub rotates the image.
assert_contains "and is dispatched, never scheduled"   "workflow_dispatch" "$pw"
case "$pw" in *"cron"*) fail "the probe workflow has no schedule" "no cron" "$pw" ;; *) ok "the probe workflow has no schedule" ;; esac

summary
