---
name: guard-must-refuse-when-blind
description: A check that cannot establish its own condition has to fail closed — that default is never written as a decision, and when it points the wrong way the broken guard reports "clean"
area: practice
verified_on: 2026-09-05
verified_against: "floppy 0.15.1 — scripts/wrap-lock.sh, scripts/wrap-guard.sh, shim/run; the original failure on macOS arm64 under /bin/bash 3.2.57"
recheck: "Give a guard an input on which it cannot compute its own condition — a stat spelling the platform lacks, an unreadable file, an empty config key — and read the verdict, not the exit code. It should refuse."
invalidated_by: "A guard whose false refusal costs more than a false pass — then the default flips, and the reason belongs next to it in the code"
---

# A guard that cannot see must refuse, not pass

## The fact

Every check has a branch nobody designs: what it answers when it **cannot
establish its own condition**. Not when the condition is false — when the check
cannot tell. The direction of that default decides whether a broken guard is
loud or silent, and it is almost never written down as a decision.

Point it the wrong way and the guard reports "clean" while checking nothing.
That is worse than having no guard at all: a missing guard is visible in the
code, a blind one is visible only in the incident it failed to stop.

The rule: **cannot establish the condition → refuse.** And the practical
corollary — prefer a formulation with no fallback at all over a correct
fallback, because a fallback is a branch someone has to keep correct.

## Why it is not obvious

The wrong default rarely arrives as a decision. It arrives as **robustness**:
`|| echo 0` so the script does not die, `2>/dev/null` so a stderr line does not
alarm anyone, an unset variable read as empty. Every one of those is good
practice in a program that computes something. In a program that *permits*
something, each one converts "I don't know" into "go ahead".

The second reason is that the failure is invisible along the happy path. A
guard that passes is what a guard looks like when everything is fine, so a
guard that always passes looks like a codebase that is always fine. Nothing
about the output distinguishes them — and the guard is precisely the component
nobody watches, because its whole promise is that you don't have to.

## Evidence

**MEASURED — the lock that never held.** A wrap lock serialises two sessions in
one checkout so the second does not overwrite the first's writes to shared
files. It decided whether a lock was abandoned by computing the lock file's age
as `stat -c %Y` — the GNU spelling, which macOS does not have — and falling into
its own `|| echo 0`. Age then came out as "now minus zero": about **fifty-seven
years**, always past the thirty-minute threshold, so every lock read as
abandoned and was taken.

On that machine the lock **never held, for a week**. Measured directly: session
A acquires, session B acquires immediately, report
`29793710 min old (older than 30)`. Nothing else in the run looked wrong.

The defect is not the spelling. The spelling is only why the check could not
establish its condition. The defect is where it fell:

> could not determine the age → assume abandoned → **take the lock**

**READ (2026-09-05), the fix, and why it is better than a corrected fallback.**
The repair did not fix the spelling; it removed the arithmetic:

```bash
[[ -n "$(find "$owner" -mmin +"$MAX_AGE_MIN" 2>/dev/null)" ]]
```

`find -mmin` answers exactly the question being asked, in one POSIX call, with
no platform branch. Look at what happens when it fails for any reason at all:
it prints nothing, the test is false, the lock is reported **not stale** — held.
The safe direction is now **structural**. Nobody has to maintain it, and no
future edit to a fallback can silently reverse it. That is the strongest form
of this rule: make the blind case fall on the safe side by construction rather
than by a branch.

**READ — the same codebase gets it right elsewhere, deliberately.** A guard
that refuses deletion of "regression" rows in a rewritten status file learns
which rows those are from a config key. When the key is unset it cannot tell:

```bash
[[ -z "$regress_marks" ]] && return 0    # 0 = protected
```

Unknown marks → **every** row protected. The cost is named in the
documentation rather than hidden: a rewritten file then grows like an
append-only one, because a one-off "done" row can never leave. That is the
trade being made consciously — safe and annoying, instead of quiet and useless.

**READ — the nuance: not every unknown deserves the same answer.** The same
project's shim resolves its plugin root from two environment variables and
treats them differently, with the reason in a comment. `AI_FLOPPY_HOME` is set
by a human and by nothing else, so a value pointing at no plugin is a mistake:
the shim **stops**. `CLAUDE_PLUGIN_ROOT` is set by the harness per plugin, and
a call made from inside another plugin's skill can carry that other plugin's
root through nobody's fault: that one **warns, names the root it used, and
continues**.

Behind the first half is its own measured incident: `AI_FLOPPY_HOME` once
pointed at a directory holding no scripts, the search fell through to a cache,
an older copy answered, and a script that had just been fixed was reported as
still broken — with nothing in the output naming which copy had run.

So the usable heuristic for the direction is **who supplied the input**:

- **a human named it explicitly** → a bad value is an error. Stop. Falling
  through to a guess produces work done against the wrong thing while the
  output describes the right thing;
- **a machine supplied it by its own rules** → it may legitimately be noise.
  Warn, say what was used instead, continue.

## How to re-check

Take any guard and give it an input on which it cannot compute its condition,
then read **the verdict, not the exit code**:

- replace a tool it shells out to with one that rejects the flag it uses (a
  `stat` that refuses `-c` reproduces the whole incident above);
- make the file it inspects unreadable, or point it at a path that does not
  exist;
- empty the config key it derives its rule from.

Three answers, and only one is acceptable: it refuses, it reports something a
human must resolve, or — the bug — it passes. Do this once per guard when it is
written; it takes a minute and it is the only moment the blind branch is
observable, because after that the guard is the thing nobody looks at.

A cheap static tell while reading code: every `|| <default>`, `2>/dev/null` and
`${VAR:-}` inside a guard is a candidate. Ask of each one what it makes the
guard answer when it fires.

## What it costs you not to know

A week of two sessions writing over each other with the serialiser installed,
green and reporting normally. The concrete shape: two agents close their work
at the same time, both append to the same index and the same status file, the
second write wins, and the loss is a note nobody knows was written. The lock
existed the whole time; it had simply been answering "abandoned" to a question
it could not evaluate.

The generalisation is worth more than the incident. **A guard is not "code that
checks"; it is code whose value lives entirely in what it does on the bad
path** — and the bad path includes the guard's own failure. Reviewing one
against its happy path proves nothing, because the happy path is the one where
it is not needed.

## See also

- [[find-does-not-follow-symlinked-root]] — the adjacent failure: not "could
  not establish the condition" but "established it over an empty set", and
  reported `clean: 0 notes` for a corpus it never reached.
- [[form-checks-cannot-see-false]] — a guard that works perfectly and answers a
  question other than the one you needed.
