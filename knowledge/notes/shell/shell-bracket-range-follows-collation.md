---
name: shell-bracket-range-follows-collation
description: A [a-z] range in a shell pattern is matched through LC_COLLATE and on macOS it catches uppercase, while [a-z] in a Python regex is a codepoint range no locale touches — so the same rule written in both languages agrees on Linux under every locale and disagrees on macOS
area: shell
verified_on: 2026-09-06
verified_against: "bash 5.1.16 and glibc 2.35 on Linux 6.18 (WSL2), under C.UTF-8 and a localedef-generated en_US.UTF-8; Python 3.12.3; the macOS half on GitHub macos-latest, job macos-bash-3-2 of spscream/ai-floppy — as a test failure under /bin/bash 3.2.57 in PR #36, and under the pinned locale in run 34060322874"
recheck: "LC_ALL=en_US.UTF-8 bash -c 'case RU in [a-z][a-z]) echo matches;; *) echo skips;; esac' — prints matches on macOS, skips on glibc. Compare with python3 -c 'import re; print(bool(re.match(r\"^[a-z]{2}$\", \"RU\")))', which prints False everywhere."
invalidated_by: "macOS adopts a collation implementation that resolves ranges by codepoint, as glibc did in 2.28"
platforms: macos
recheck_cmd: LC_ALL=en_US.UTF-8 bash -c 'case RU in [a-z][a-z]) printf shell-matches;; *) printf shell-skips;; esac'; printf ' '; python3 -c 'import re; print("python-matches" if re.match(r"^[a-z]{2}$", "RU") else "python-skips")'
expect: shell-matches python-skips
---

# `[a-z]` in a shell pattern is a collation range, and on macOS it covers uppercase

## The fact

A bracket **range** in a shell pattern — a glob, a `case` label, a BSD `sed`
expression — is resolved through `LC_COLLATE`, not through codepoints. On macOS the
collation interleaves case, so `[a-z]` matches `R` and `guide.RU.md` matches
`*.[a-z][a-z].md`. `[a-z]` in a Python `re` pattern is a literal codepoint range and no
locale reaches it, so the same rule expressed in Python rejects `RU` on every platform.

The two idioms therefore agree on Linux and disagree on macOS. The fix is an
enumeration, not a range: `[abcdefghijklmnopqrstuvwxyz]` has no endpoints for collation
to reorder. `[[:lower:]]` is not a substitute — in a UTF-8 locale it also matches `я`,
which the Python side does not.

## Why it is not obvious

The failure cannot be reproduced by setting a locale on Linux, which is where the rule
gets debugged. glibc resolves range endpoints by codepoint regardless of the locale — a
generated `en_US.UTF-8` behaves exactly like `C.UTF-8` here — so a Linux machine calls
the broken pattern correct under every locale you can reach for. Meanwhile the two
spellings read as synonyms: `[a-z]{2}` in a regex and `[a-z][a-z]` in a glob are the
same three characters expressing the same intent, and nothing in either language marks
one as locale-dependent.

The other half of the surprise is where it lands. `LC_ALL=C` in front of the command
fixes `sed` and does nothing for a glob, because a glob is matched by the shell that
already parsed the line, not by the command being run.

## Evidence

**MEASURED**, 2026-09-06, on Linux (bash 5.1.16, glibc 2.35, Python 3.12.3):

| pattern | locale | `RU` |
|---|---|---|
| `case RU in [a-z][a-z])` | `C.UTF-8` | skips |
| `case RU in [a-z][a-z])` | `en_US.UTF-8` (localedef-generated, via `LOCPATH`) | skips |
| `re.match(r"^[a-z]{2}$", "RU")` | either | `None` |
| `case RU in [abcdefghijklmnopqrstuvwxyz][abcdefghijklmnopqrstuvwxyz])` | either | skips |

`AA`, `ZZ` and `Ab` skip as well, so this is not an artifact of where `R` and `U` sit in
the alphabet. That the generated locale was genuinely in effect was checked separately:
`case "яя" in [[:lower:]][[:lower:]])` matches under it and does not under `C.UTF-8`,
which is also the measurement behind the `[[:lower:]]` sentence above.

**MEASURED** on macOS, in CI rather than by hand: the same rule written as a glob and as
a Python regex was asserted against a fixture named `guide.RU.md` in PR #36 of
`spscream/ai-floppy`. Every Linux job passed; job `macos-bash-3-2` failed with `FAIL an
uppercase language tag is not a translation`. That is the effect under the runner's
ambient locale. The `LC_ALL=en_US.UTF-8` form in `recheck_cmd` above isolates the
mechanism from the image's `LANG`, and it has run there: green on `macos-bash-3-2` in
run 34060322874, which is the assertion `shell-matches python-skips` passing on macOS.
It cannot pass by being skipped — the platform matches and there is no `requires` — and
`tests/test-knowledge.sh` gates on `0 failed`, so every push re-measures it.

**READ, not measured:** that glibc's behaviour here dates from its 2.28 collation
rewrite. The behaviour itself is measured; the version that introduced it is not.

## How to re-check

`recheck_cmd` runs on macOS and is skipped on Linux — "not asserted here" rather than
"false here", since the whole claim is that Linux cannot show it. It pins
`LC_ALL=en_US.UTF-8` deliberately: the runner's ambient `LANG` is a property of the
image, and a check that reads it would go red on an image change without the fact having
moved. There is no `requires` probe for that locale on purpose — a macOS without
`en_US.UTF-8` should be a red check somebody looks at, not a silent skip.

The claim is about libc, not about the shell, so it does not matter whether the check
runs under macOS's `/bin/bash` 3.2.57 or a newer bash earlier in `PATH`.

## What it costs you not to know

One rule written in two languages, one of them a shell — a file-naming convention, a
branch-name check, a language-tag validator. It agrees with itself on every machine you
own and on the Linux leg of CI, and rejects on macOS what it accepts everywhere else, or
accepts what it should reject. In the case measured here an uppercase language tag was
treated as a valid translation on exactly one platform, and the fix that made the two
agree could not be verified on the machine where it was written.

## See also

- [[macos-ci-does-not-test-bash32]] — the other way a macOS-only difference stays
  invisible until it reaches the right runner
- [[macos-tmpdir-can-contain-underscore]] — a second value that is a property of the
  runner image rather than of the code
