---
name: macos-tmpdir-can-contain-underscore
description: A macOS runner's temp directory is /var/folders/<a>/<b>/T/, and <b> is not alphanumeric — it can contain `_`, so code that assumes a clean temp path fails on some runners and passes on others, which reads as flakiness
area: shell
verified_on: 2026-09-05
verified_against: "GitHub-hosted macos-latest (arm64), 2026-09-05; runs 33988970539 and 33989864363 of spscream/ai_floppy"
recheck: "On a mac or a macOS runner: `d=$(mktemp -d); echo $d` — expect /var/folders/<a>/<b>/T/tmp.XXXXXXXX. For the underscore itself you need that machine's own path: echo $TMPDIR in the job and read the second component."
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

**READ, not measured — the frequency.** Only a failing run printed a path: the assertion
that echoed it is the one that fired. All fifteen macOS job logs sampled for
`/var/folders/` yielded exactly one distinct prefix, from the two failures, so *the six
passing runs' temp paths were never recorded.* That the passing runs got a `<b>` without
`_` is the explanation that fits — the transformation is deterministic given the path —
but it is inference, and an image or account difference producing the same split is not
excluded by anything measured here. **What is measured is that the path varies enough to
change the outcome, and that one real value contains `_`.** Do not quote a rate.

**READ**: the `_CS_DARWIN_USER_TEMP_DIR` mechanism, from Darwin's `confstr(3)`; the
alphabet of the `<b>` component was not established from any source and is not claimed
here beyond the one observed value.

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
