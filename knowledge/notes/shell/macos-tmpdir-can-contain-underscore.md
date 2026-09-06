---
name: macos-tmpdir-can-contain-underscore
description: A macOS runner's temp directory is /var/folders/<a>/<b>/T/, and <b> is not alphanumeric — it can contain `_`. Measured, it is fixed by the runner IMAGE, not drawn per machine, so while the pool serves two images the same commit passes on one and fails on the other and the split reads as flakiness
area: shell
verified_on: 2026-09-06
verified_against: "GitHub-hosted macos-latest (arm64); the split measured 2026-09-06 over 20 runners in one dispatch, run 34028462447 of spscream/ai-floppy; first observed 2026-09-05 in runs 33988970539 and 33989864363"
recheck: "On a mac or a macOS runner: `d=$(mktemp -d); echo $d` — expect /var/folders/<a>/<b>/T/tmp.XXXXXXXX. For the underscore and its frequency, dispatch .github/workflows/tmpdir-probe.yml, which runs knowledge/probes/tmpdir-probe.sh on 20 runners at once and tallies the components."
invalidated_by: "GitHub sets TMPDIR to a fixed path on macOS runners, or Darwin stops deriving it from confstr(_CS_DARWIN_USER_TEMP_DIR)"
platforms: macos
recheck_cmd: d="$(mktemp -d)"; case "$d" in /var/folders/*/T/*) echo match ;; *) echo "$d" ;; esac; rmdir "$d"
expect: match
---

# On macOS the temp directory is per-user and its name is not alphanumeric

## The fact

`mktemp -d` on macOS does not hand you a path under `/tmp`. It hands you one under the
per-user temp directory Darwin derives from `confstr(_CS_DARWIN_USER_TEMP_DIR)`, which
looks like:

```
/var/folders/df/djsxfhc17x95674wsm_g8s980000gn/T/tmp.e4GeiSlama
```

Two properties matter and neither holds on Linux. The `<b>` component is **not
alphanumeric** — the one measured here contains `_` — and it **differs between machines**,
so the same code meets a different character set on a different runner. `/var` is itself a
symlink to `/private/var`, so `pwd -P` on that directory returns a path one component
longer than the one `mktemp` printed.

The consequence is a failure mode with no failing commit: a job that treats a temp path as
`[A-Za-z0-9/.-]`, or that transforms a path character-class-wise, is correct on some
runners and wrong on others, and both outcomes come from the same source tree.

## Why it is not obvious

Everything about a temp directory advertises that its content is random and its *shape* is
not. On Linux it genuinely is not — `TMPDIR` is `/tmp`, and every path below it differs
only in `mktemp`'s own suffix, which is alphanumeric. So the mental model "the fixed part
is boring, the random part is `[A-Za-z0-9]`" is correct everywhere you develop and wrong
on the platform where you do not.

It then hides behind the word *flaky*. The variable that decides the outcome is chosen by
the runner before the job starts and never printed, so what CI shows is one commit that
failed and passed. Nothing distinguishes that from a race, and a job that is deterministic
in an input nobody can see is the most expensive kind to have.

## Evidence

**MEASURED**, 2026-09-05, on the macOS leg of `tests.yml` in this repository, over a
45-minute window between two commits (`9525716` and `f32348c`) in which a test computed a
path transformation that folded `/` and `.` but not `_`:

| leg | runs in the window | failed |
|---|---|---|
| macos-latest | 8 | 2 |
| ubuntu-latest | 8 | 0 |

Two commits ran twice each and produced **both outcomes on the same SHA**, one job apart:

| SHA | passed | failed |
|---|---|---|
| `396849e3` | 33988974473 | 33988970539 |
| `96f8ef32` | 33989866019 | 33989864363 |

**MEASURED**, the path: both failing runs printed the same prefix,
`/var/folders/df/djsxfhc17x95674wsm_g8s980000gn/`, with the failing assertion's own
output showing it resolved — `repo: /private/var/folders/df/.../T/tmp.e4GeiSlama`. The
`_` is in the `<b>` component. `mktemp`'s suffixes in the two samples (`e4GeiSlama`,
`u5m1u5oq8Z`) contain none, so the underscore does not come from there.

**MEASURED**, 2026-09-06, run 34028462447 — the split, and the mechanism behind it. Twenty
`macos-latest` runners in one dispatch printed their own temp path
(`knowledge/probes/tmpdir-probe.sh`). Two distinct components came back, and each one goes
exactly with a kernel version, 20 samples out of 20:

| `uname -r` | `<a>/<b>` | runners | carries `_` |
|---|---|---|---|
| 25.5.0 | `df/djsxfhc17x95674wsm_g8s980000gn` | 6 | yes |
| 25.6.0 | `d8/hvxvltxn0fl4rmnd52sncbth0000gn` | 14 | no |

So the component is **not drawn per machine — it is baked into the runner image**, and the
pool was serving two images at once. `df/djsxfhc17x95674wsm_g8s980000gn` is the same value
the two failures of 2026-09-05 printed, which settles what was inference then: the passing
runs were landing on the other image.

**The 30% is a property of a rollout, not of macOS.** It was the mix on one day, and it
goes to zero the moment GitHub retires 25.5.0 — at which point the same code is green
forever and the defect is still there, waiting for the next image whose `<b>` has an `_`.
Quote this number only with its date and both kernel versions, or not at all. What does
not expire is the shape: `<b>` is not alphanumeric, and which one you get is decided
before your job starts.

**MEASURED**, same run — the suffix. 2100 `mktemp -d` samples across the 21 machines
(20 macOS, 1 Linux control) produced **zero** characters outside `[A-Za-z0-9]` in
mktemp's own suffix. The note previously called the suffix alphanumeric on the strength of
two samples; it now rests on 2100. The Linux control reported no `<a>/<b>` component at
all, so "this is a Darwin property" is measured here rather than assumed.

**READ**: the `_CS_DARWIN_USER_TEMP_DIR` mechanism, from Darwin's `confstr(3)`. Note that
the measurement above does not confirm the *mechanism* — it shows the value tracks the
image, which is equally consistent with the directory being created once when the image
was built and simply shipped inside it. Nothing here establishes the alphabet `<b>` is
drawn from; two values are two values.

## How to re-check

The shape, in five seconds on any mac — this is what `recheck_cmd` above runs, and it is
skipped on every platform but macOS:

```bash
d="$(mktemp -d)"; echo "$d"; cd "$d" && pwd -P; cd - >/dev/null; rmdir "$d"
# /var/folders/<a>/<b>/T/tmp.XXXXXXXX
# /private/var/folders/<a>/<b>/T/tmp.XXXXXXXX
```

The underscore half cannot be re-checked from a note, because it is a property of the
machine you land on and not of macOS. To sample it, print `$TMPDIR` in the job itself and
read the second component; across several runners you will see whether yours vary.

`knowledge/probes/tmpdir-probe.sh` does that reading, in `key=value` lines, and this
repository runs it in two places: one sample per push, in the macOS leg of `tests.yml`,
and twenty samples at once from `.github/workflows/tmpdir-probe.yml`, which is dispatched
by hand and tallies the result with `knowledge/probes/tmpdir-tally.sh`. Note what the
probe cannot do, because it is the reason the second one fans out over machines: `<b>` is
fixed for the whole job, so N iterations *inside one job* return N suffixes under one
parent and say nothing about the distribution. The sampling unit is the machine — the
probe's own `distinct_parent_dirs` field reports 1 on every run, which is that fact stated
by the measurement rather than by this paragraph.

Re-run the dispatch when the numbers matter again. The split above is dated, and the thing
it measures is a rollout: a tally taken after 25.5.0 leaves the pool will read 0%, and that
is a true measurement of a different day, not a refutation of this one.

## What it costs you not to know

You get a red job that is not flaky and will not be reproduced by re-running it, and the
cheapest available diagnosis — "CI is flaky on macOS" — is both wrong and stable, so it
survives. In this repository the same input first hid a real defect: a check that
transformed the temp path the same wrong way its subject did, agreed with it, and reported
success while two of a machine's three consumers wrote their memory into a directory
nothing ever read.

The operational form: **never let a path from `mktemp` reach a character-class assumption**
— not in a `tr`, not in a `sed` class, not in a regexp anchored on `[A-Za-z0-9]`, and not
in a comparison against a path you built yourself instead of reading back out of the
filesystem. If your test needs to know where something landed, ask the filesystem, so the
answer carries whatever characters the runner chose.

## See also

- [[macos-ci-does-not-test-bash32]] — the other reason a macOS job means less than it looks
  like it means.
- [[find-does-not-follow-symlinked-root]] — `/var` → `/private/var` is exactly the kind of
  symlinked root that changes what a traversal sees.
