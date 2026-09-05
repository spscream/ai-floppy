# Changelog

Why this file exists, in one line: **`plugin update` compares version strings
and copies nothing while the version is unchanged**, so the version here is
load-bearing, and a consumer needs to know whether an update is worth taking.

One column matters more than the rest and is called out per release:

> **Refresh `.floppy/run`?** — `.floppy/run` is a *copy* in your repository,
> not a link, and no plugin update ever touches it. When a release changes the
> shim, updating the plugin is only half the job:
> `cp "$FLOPPY_ROOT/shim/run" .floppy/run`. Since 0.2.1 the shim notices this
> itself and prints the command; before that it was silent.
>
> Since 0.14.0 the answer is usually **no**. The copy holds only the search for
> the plugin; verbs, config keys and defaults live in the plugin and arrive with
> `plugin update`. A release says **yes** here only when that search changes.

Dates are the day the version was tagged in `.claude-plugin/plugin.json`.

## 0.16.2 — 2026-09-05

**Refresh `.floppy/run`: no.** The fix is in `link`, again — the same file as
0.16.1, a different defect, found by standing the external layout up rather
than by reading it.

`link` compared one resolved path against one unresolved one. It took
`readlink -f` of the harness symlink — fully resolved — and compared it to
`memory_dir` as written. In the ordinary layout those agree, because
`memory_dir` is a real directory. **With `store` it is a symlink into another
repository**, so the two could never be equal, and the entire external layout
had:

- `link` refusing, with "the symlink points elsewhere", the machine it had
  just wired itself;
- `link --check` that could never go green;
- `status` reporting `memory is not wired on this machine` against wiring that
  worked — a write through it reached the store, which is the thing that
  actually matters and the thing nobody was checking.

Both sides are resolved now. `cd && pwd -P` rather than `readlink -f`, matching
the rest of these scripts and not depending on a `readlink` that only grew `-f`
on recent macOS; a dangling link falls back to `readlink` and is still
reported rather than crashing. A link pointing at a genuinely different
directory is still refused — resolving both sides is not the same as comparing
nothing, and there is a test for exactly that.

Two of this release's regression tests are for the second run rather than the
first. `store` ends by printing `next: bash .floppy/run link`, and `status`
asks the same question afterwards, so the second call is the one a consumer
actually makes — and it was the one that failed.

## 0.16.1 — 2026-09-05

**Refresh `.floppy/run`: no.** The fix is in `link`.

`link` encoded the checkout path as `tr '/.' '--'`, and Claude Code folds a
third character the same way: **`_`**. So a repository whose directory name
carries an underscore got a project directory of its own that the harness never
opens.

Nothing failed. `link` created the directory it had computed and reported
success; `--check` agreed, because it asks this same line; `status` reported
the wiring as present. This is precisely the second silent failure mode the
script's own header names — "the project directory is computed correctly, but
Claude Code encodes the path differently, same result" — and it had been live
against that description the whole time.

Measured 2026-09-05 from the harness's own transcripts, which record the `cwd`
a session actually ran in:

```
-home-amalaev-work-agents-harness   cwd=/home/amalaev/work/agents_harness
-home-amalaev-work-ai-floppy        cwd=/home/amalaev/work/ai_floppy
-home-amalaev--local-bin            cwd=/home/amalaev/.local/bin
```

Two of that machine's three consumers were affected, one across fifteen
sessions. Case is **not** folded — `/tmp/consensus-5Ob9Z2` keeps its capitals
in the harness's own directory name — so this stays a `tr` of three characters
rather than becoming a general slug.

What it costs in practice is the memory not reaching the session, not notes
being lost: writes go through the repository, and the stray directory only
holds wiring. On the machine this was found on, one project had an empty
directory there and the other had a hand-written stub saying "the memory moved
into the repository, do not write here" — someone had hit this and worked
around it without the cause being named.

**If your checkout path contains `_`,** re-run `bash .floppy/run link` after
updating. It will refuse if a real directory stands where the symlink belongs
— that is the guard working; look at what is in that directory, move anything
real, then run it again. The stale directory under `~/.claude/projects` with
the underscore in its name can be removed once the new one is wired.

The regression test asserts the resulting directory name rather than
recomputing the rule. The existing test at `tests/test-memory-link.sh:30`
recomputes it on purpose — it only needs to agree with the script — and that is
exactly why nothing here was red: a check that restates the rule agrees with
any rule, including a wrong one.

## 0.16.0 — 2026-09-05

**Refresh `.floppy/run`: no.** The change is entirely inside the plugin.

Every ceiling `memory-lint` enforces now **warns at 96% before it refuses at
100%**. Until this release exactly one of them did — the index, through a
derived `IDX_WARN` — and `chars_max`, `half_chars_max.<half>`, `note_chars_max`
and `pointers_max` went from silence straight to a failed run.

Reported from a consumer corpus of 158 notes across four halves ([#1]). Its
`flow` half sat at **72694 of 75000 — 96.9%** while `lint` printed
`clean: 158 notes, 166 pointers across 8 indexes`. The budget had been set the
same day at +10% over a 68311-character measurement: 66% of that headroom went
in one day, four commits, with nothing said.

The band is not cosmetic, because of who a bare refusal lands on. It stops
whichever session *crosses* a ceiling, and on a memory written from several
machines that is routinely not the session that filled it. The ratchet says a
number may be raised only in the same commit as the notes that needed the room
— so that session must either raise a ceiling it did not fill, or prune a half
it did not write, and pruning a neighbouring session's notes is the one thing
the wrap rite forbids outright. A warning reaches the session doing the
filling, while trimming is still its own work.

- One fraction, shared by all five ceilings and derived from each, rather than
  a knob per ceiling: the argument the index section already made — two numbers
  kept in a fixed relation are two chances to set them wrong — does not get
  better when repeated five times.
- The per-half breakdown now prints with the corpus **warning** as well as the
  corpus failure. Naming which half grew is the whole point of the per-half
  tally, and "the memory is nearly full" without it sends the reader to measure
  by hand.
- `pointer_line_max` deliberately has no band. It bounds one line, and a line
  at 165 of 170 characters is not approaching anything — it is a line that
  fits. The other five bound something that accumulates.

Warnings do not fail a run: every `x` in this release's output was an `x`
before it, and rc is unchanged for every corpus that was passing or failing.
What changes is that a passing run can now be talkative. Two cases are worth
expecting on the first run after the update:

- A corpus seeded by `init` has `pointers_max` at the longest index it found,
  which is 100% of that ceiling by construction — so the index that set the
  number now says so. That is accurate: the next pointer added to that half
  fails. Plan the sub-index split, or raise the number deliberately.
- `chars_max` seeded by `init` carries a tenth of headroom, so a freshly
  adopted corpus sits at ~91% and stays quiet.

And because of the first of those, `init` now prints the linter's `!` lines
beside its verdict instead of only the verdict. It reported `memory-lint is
clean` and dropped them — true, and not the same report as "nothing to do".
The warning that adoption itself creates was landing on the one run an adopter
reads line by line, and being swallowed there.

[#1]: https://github.com/spscream/ai-floppy/issues/1

## 0.15.1 — 2026-09-05

**Refresh `.floppy/run`: no.** The shim is unchanged; the fix is in `init`.

- `init` wrote the wrong name into `.gitignore`. The line it appended was
  `/<memory_dir>/local` — the name the private scope carried **before 0.6.0**,
  and the one `memory-workplace.sh` now migrates away from — while the symlink
  that script actually creates is `/<memory_dir>/<memory_private_dir>`, default
  `private`. So a freshly initialised repository ignored a path nothing
  creates, and on the first `workplace` the real symlink came out untracked:
  either committed into the code repository, which is the one thing the ignore
  exists to prevent, or tripping over the guard on every wrap.

  Nothing reported it, in either direction. The `.gitignore` looks configured,
  and the test suite asserted the wrong name back — with an exact-line
  assertion, which made it look rigorous. `init` now takes the leaf from
  `memory_private_dir` when the config already carries the key and defaults to
  `private` otherwise, and a regression test refuses the pre-0.6.0 name
  outright.

  A repository initialised before this release has the wrong line already.
  Re-running `init` does not remove it — `init` never deletes: fix it by hand,
  or add the right line beside it. Check with
  `git check-ignore -v <memory_dir>/private`; on effectssdk, the first consumer,
  the line had already been corrected by hand.

- README said `init` "adds the machine-local memory directory to
  `.gitignore`". Nothing about that scope is machine-local — a hundred lines
  below, the same file explains that this is exactly why the name was dropped
  in 0.7.0.

## 0.15.0 — 2026-09-05

**Refresh `.floppy/run`: no.** The change is entirely inside the plugin.

`memory-lint` now tallies the corpus **by half**, and `quota.lock` accepts
optional `half_chars_max.<half>=N` keys (`half_chars_max.root` for notes sitting
directly in the memory directory). A half with no key is unbounded, so a corpus
that sets none behaves exactly as before; when the corpus-wide `chars_max`
trips, the failure now prints the breakdown beside it whether or not any
per-half key is set.

What prompted it was a measurement that also says what **not** to build. On a
consumer repository, across 42 sessions of transcripts, a session reads the root
index (7 336 characters, loaded every time), one half index (3 311–7 010), and a
median of **8 notes** — about 40 000 characters of a 485 000-character corpus.
The rest never enters the window. So the corpus-wide cap is not a proxy for
context cost: the index tree already keeps cold notes out for free, and a "cold
storage tier" underneath it would save nothing that is being paid.

What the cap does do is force pruning — and that is where a single number fails.
That corpus is worked from two machines, its halves were 3.4x apart in size, and
the half that grows is not the one whose session hits the ceiling: the cap was
raised three times in eleven days, each time by a session adding a legitimate
note to a different half. A per-half budget puts the ceiling where the growth is.

One caution from the same measurement, worth repeating because it nearly became
an argument for the tier that is not being built: 49 of that corpus's 156 notes
had never been opened in any local transcript, which reads as a third of the
memory being dead weight. Forty of the forty-nine belonged to the half worked on
the *other* machine, whose transcripts are not on the machine doing the counting.
**"Never used" measured on one machine is a question about coverage, not a fact
about the corpus.**

No new knob for the always-loaded index: `index_chars_max` in `.floppy/config`
already caps it, and that number is a fact about the harness rather than about
any corpus.

## 0.14.0 — 2026-08-26

**Refresh `.floppy/run`: yes, once — and much less often after that.** The shim
in a consumer repository is now a stub: it finds the plugin and execs it. The
verb table and the config parser moved into the plugin
(`scripts/run`, `scripts/lib-config.sh`), where `plugin update` delivers them.

Asked what the shim is even for, the honest answer had two halves and only one
of them justified a copy in someone else's repository. Measured over the 24
commits that have touched `shim/run`: 14 changed the config parser, 12 the
plugin resolver, 6 the verb table — and **at least 7 of the 24 changed only the
parser or the table**. Every one of those obliged every consumer to re-copy a
file for something a plugin update could have carried. Worse, that class is the
silent one: a stale parser does not announce itself, it keeps applying the old
default. The resolver cannot move — code that finds the plugin cannot live in
the plugin — but its failures are loud, and now it is all that travels.

The staleness therefore reverses direction, and improves:

- **A new verb needs no refresh anywhere.** It appears in the plugin, and every
  repository that has ever run `init` can call it. This was the case that
  motivated the unknown-verb message in the first place, back when `parity` was
  added; it cannot happen again.
- **A new config key or default needs no refresh either.**
- **A plugin older than the stub is now a full stop, not a partial one.** A
  pre-0.14.0 plugin has no dispatcher, so no verb runs against it, including
  verbs whose scripts it does have. Before, only the missing verb failed. The
  refusal names what is missing, which side is old, and the resolved plugin
  root. This is the release's one deliberate loss, and it is asserted in
  `tests/test-shim.sh` rather than left to be discovered.

Also, from the same measurement session:

- **`CURSOR_PLUGIN_ROOT` is now consulted**, right after `CLAUDE_PLUGIN_ROOT`
  and before any cache guess. Cursor exports it the way Claude Code exports its
  own (measured 2026-08-26 against a cross-harness plugin that branches on the
  two by name); floppy never tried it. On the owner's machine
  `~/.cursor/plugins/cache/floppy/floppy/` exists and is **empty**, so the cache
  branch resolves nothing there and only the local symlink saves the run — an
  answer from the harness beats three guesses. `init`'s bootstrap search learns
  the same variable.
- The stale-copy hint now names this file by its own absolute path rather than
  one derived from the repository root, which the stub no longer resolves.

`tests/test-docs.sh` read the config keys out of `shim/run` to check the README
documents them. After the move that grep matched nothing and the loop asserted
nothing — green, and checking nothing. It reads `scripts/lib-config.sh` now and
fails if the key list ever comes back empty.

482 asserts, up from 479.

## 0.13.0 — 2026-08-26

**Refresh `.floppy/run`: yes** (the verb table lost an entry and the config
parser lost a key). **`parity` is gone, with everything around it** — the
`--scaffold` generator that 0.12.0 added the same day, the `commands_dir`
config key, and the `localized commands` section of `check`.

The feature was built on an assumption nobody had checked. The premise was
that a team which works in its own language needs the rite in that language,
so the plugin must guard two copies of every procedure against drift. Asked
what part of a command file a person actually reads, the answer turned out to
be: the command name, the `description` in the picker, and `argument-hint`.
The body is a prompt. It is loaded into the model's context on invocation and
is never shown to anyone. Claude Code's own documentation also states that
custom commands and skills are now the same thing: `.claude/commands/wrap.md`
and `.claude/skills/wrap/SKILL.md` both produce `/wrap` and behave alike.

So the work the plugin was automating — translating hundreds of lines of prose
— produced no text a user would ever see, and created the second copy that
`parity` then existed to police. Removing the copy removes the drift, the
check, and the generator together.

- `bash .floppy/run parity` is no longer a verb. An old shim that still has it
  will report a missing script rather than fail obscurely; refresh the copy.
- `commands_dir` is no longer read from `.floppy/config`. A line left in the
  file is ignored, as any unknown key is.
- `check` no longer has a `localized commands` section, and the `wrap` skill no
  longer lists a drifted command among the things to fix before committing.
- `scripts/parity.sh` and `tests/test-parity.sh` are deleted. The two shim
  tests that used `parity` as their example verb now use `status`.

If localized rites are ever wanted again, the cheap version is the one this
release did not have to build: translate `description` and `argument-hint`,
which is the whole of what a person sees, and leave the body alone.

479 asserts, down from 536.

## 0.12.0 — 2026-08-26

**Refresh `.floppy/run`: no** (the shim is unchanged; the new behaviour is a
flag on a verb it already dispatches). **`parity` can now write the files it
checks**, and the README says how to write them by hand.

Asked how to create `.claude/commands/wrap.md`, this repository had no answer.
`parity` had guarded localized command files since 0.9.0 and the README
explained the check at length, but nothing anywhere described the artifact: a
repository was told its two copies must not drift, and never told how to make
the second copy. The only working example lived in `tests/test-parity.sh`.

- `bash .floppy/run parity --scaffold` writes one skeleton per rite into
  `commands_dir`: the numbered headings and every `bash .floppy/run` call,
  verbatim, with the English prose replaced by a marker that says how many
  lines were dropped and where to read them. It never writes over a file that
  exists — a translation of `wrap.md` is hours of work and lives in exactly
  the path the generator wants.
- The generator is in `scripts/parity.sh`, next to the checker, not beside it.
  The two have to agree on one thing — what in a rite is load-bearing — and two
  files that must agree are the arrangement `parity` exists to police.
- Calls that appear only inline in prose are the case that makes this more than
  a copy: dropping that paragraph would drop the call. They are re-emitted
  under the step whose prose mentioned them; calls outside any step get a
  section of their own.
- The generated file passes `parity` before a word of it is translated, and the
  test asserts exactly that round trip. A generator whose output starts red
  teaches its reader that the check is wrong.
- README: a new subsection on making the command files — all three rites, not
  one; the numbers of the `## N.` headings and the `bash .floppy/run` lines
  survive translation, the titles and the argument placeholders do not.
  `tests/test-docs.sh` now asserts the subsection is there.

Also: the site test now checks the changelog against the version in
`plugin.json`, so a release that moves the version and forgets this file goes
red instead of publishing a site whose newest entry is the release before it.

536 asserts, up from 481.

## 0.11.0 — 2026-08-25

**Refresh `.floppy/run`: yes** (the shim derives one more path). **`commit` now
closes a third repository** — the workplace one — where before it refused to
commit into it at all.

Reported from a Linux machine: `/wrap` could not commit a note written into the
private memory. Reproduced here, in both `commit_push` modes, so the mode was
never the cause:

    x .agent-memory/private/private-fact.md — not changed: wrong path, or the
      edit was lost
    (a parallel session may have written between check and commit)

- The gates knew two shapes and this was the third. `FLOPPY_MEMORY_EXTERNAL`
  covers the whole memory being foreign; the common shape is the memory living
  in the code repository with only `<memory_dir>/<private_dir>` symlinked into
  the workplace repository. Neither `wrap-guard.sh` nor `wrap-commit.sh`
  contained the word. So the guard asked THIS repository's `git status` about a
  path this repository ignores by design, was told nothing had changed, and
  refused — while the note sat on disk and `workplace` had just reported that a
  write through the link lands in the workplace repository.
- The diagnosis it printed was wrong twice over: the path was right, the edit
  was not lost, and no parallel session was involved. A gate that refuses is
  fine; a gate that refuses with a false reason sends the next hour somewhere
  else.
- `commit` now stages, commits and pushes those files in the workplace
  repository, the way it already did for a store, and leaves the code
  repository untouched. A call naming files of both kinds closes both.
- The `check` line that said workplace changes must be committed "there
  separately" now says to name them in the file list instead. It was true until
  this release and would have sent the human to commit by hand what the next
  call does — including notes this session never claimed.

481 asserts, up from 466.

## 0.10.0 — 2026-08-25

**Refresh `.floppy/run`: yes** (the shim now refuses a variable that names a
plugin which is not there). **Expect a red `lint`** on the first run in a
project that has a workplace memory repository: notes there have never been
checked, and now they are.

- The shim stops instead of searching on when `AI_FLOPPY_HOME` is set to a
  directory holding no `scripts/*.sh`. A cache path is a guess and skipping a
  wrong guess in silence is right; a variable somebody set is a statement about
  where the plugin is, and skipping THAT in silence is how a call ends up
  against another copy. Measured while fixing 0.9.1: the variable was pointed
  at a directory with no plugin, the search fell through to the Claude Code
  cache, an older copy answered, and a script that had just been fixed was
  reported as still broken — with nothing in the output naming the copy that
  ran. `CLAUDE_PLUGIN_ROOT` is treated differently on purpose: the harness sets
  it per plugin, so a call from inside another plugin's skill can carry that
  plugin's root through nobody's mistake. That one warns, names the root used
  instead, and carries on.
- The memory linter reaches the private scope — the symlink into the workplace
  repository, which every one of its queries used to exclude by path. It gets
  the per-note invariants: frontmatter, `name`/`description`, `metadata.type`,
  `metadata.evidence`, slug uniqueness, `[[link]]` resolution. Measured on the
  first consumer's store the moment it ran: three notes, three with no
  `metadata.evidence`, invisible because nothing reached them.
- What the private scope deliberately does NOT get: the index rules, because
  the scope is flat by design and its README is prose rather than pointers —
  demanding `MEMORY.md` and `INDEX.md` there would report every note an orphan
  on the first run; and the quota, because those numbers live in the committed
  memory's `quota.lock` and are facts about that corpus. Borrowing them here is
  the same borrowed cap this project refuses elsewhere.

466 asserts, up from 452.

## 0.9.1 — 2026-08-25

**Refresh `.floppy/run`: no.** The shim is unchanged; the fixes are in the
scripts it calls.

- `check` no longer reports a red memory linter with no reason. The linter has
  three outcomes, and the code knew two: exit 2 is a refusal *before* any
  checking — no memory layout in this repository, or a scope name it cannot
  use — and it prints a sentence rather than `  x` lines. Those lines were what
  got counted, so the human saw `MEMORY LINT IS RED, 0 problem(s)` and nothing
  else. It stays red, because a wrap that cannot read the memory should not
  proceed quietly, but it now prints the linter's own sentence. This is the
  message a person meets when the wrong project is active in a harness holding
  several, so throwing it away was expensive.
- `commit` no longer dies on a file this session deleted with `git rm`.
  Reported from a second session. `git rm` stages the deletion, which takes the
  path out of both the worktree and the index, and `git add -- <that path>`
  then fails with "did not match any files" — killing the whole commit.
  Measured while fixing: `git add -A -- <path>` fails identically, so widening
  the add is not the fix. An already-staged deletion is simply left alone; it
  is in the index already, which is what the add was for. A path that matches
  nothing anywhere stays in the list and still fails, so a typo in the file
  list is as loud as before.
- `tests/run.sh` runs the files in parallel, one job per core by default.
  Measured on a 12-core mac: 71.8s serially, 20.7s parallel, identical results
  and identical output order. Sixteen jobs measured slower than twelve, so the
  default is the core count and not more. `FLOPPY_TEST_JOBS=1` restores the
  serial run, whose output streams live — which is what you want while chasing
  one failure.

452 asserts, nine of them added here.

## 0.9.0 — 2026-08-25

**Refresh `.floppy/run`: yes.** The shim reads one new config key.

`statuses_regress_marks` — the words that mark a regression in the direction
cell of a trend table, in the consumer's own language. With the key set,
`wrap-guard` protects only the rows carrying one of those words; any other row
may be deleted.

Why: the guard was stricter than the rule it enforces. Both `AGENTS.md` and
`docs/statuses/README.md` of the first consumer say "a metric marked *worse* is
not deleted", and the reason given is that a vanished bad number is how a
regression hides. The guard protected every row instead, which made each one
immortal — including one-time "done" facts that can never move again. A
rewritten state file then grows exactly like the append-only journal it was
split away from: the first consumer hit its character cap with 24 of 40 process
rows being finished facts rather than live indicators.

An unset key keeps the old behaviour, so no consumer loses a guard by updating.
The words are configured rather than built in because this file already learned
that matching one language's word breaks every other consumer.

## 0.8.0 — 2026-08-25

**Refresh `.floppy/run`: yes** (the config parser no longer reads three keys).
**Breaking, in name only:** a config that still spells a key the old way is now
read as if the key were absent.

- The compatibility fallbacks for `memory_repo`, `workplace_repo`, and
  `memory_local_dir` are gone. `public_repo`, `private_repo`, and
  `memory_private_dir` are the keys. The fallbacks were kept so that a config
  written before 0.6.0 or 0.7.0 would keep working; checked before removing
  them, and the only `.floppy/config` outside this repository already spells
  every key the new way, so the compatibility was documenting keys nobody has.
- The messages that named a removed key now name the current one: `store`
  asks for `public_repo`, `workplace` asks for `private_repo`, and the linter's
  refusal of a scope name with regex metacharacters says `memory_private_dir`.
  A message that names a key the parser ignores is worse than no message.
- The config template that `init` writes offers the current names too.
- README: the key table had a blank line inside it, which split it in two and
  left everything from `workplace_project_key` down rendering as raw pipes
  rather than a table. The paired keys sit next to each other again.
- README: the `project_key` row described the scopes as `projects/<key>/shared`
  and `projects/<key>/private`, which 0.7.0 replaced; and the example config,
  the checkout tree, and two sentences still used the pre-0.7.0 repository key
  names.

437 asserts, down from 440: the three that vanished asserted README documents
`memory_repo`, `workplace_repo`, and `memory_local_dir`.

## 0.7.1 — 2026-08-25

**Refresh `.floppy/run`: no.** Needed while migrating to 0.7.0.

- A **view** left pointing at a scope that a release moved is repointed, not
  refused. 0.5.1 did this for the link inside the consumer repository and
  stopped there; the view is the same kind of thing — a symlink this verb
  created, with nothing behind it once the scope moved — and refusing it made
  the 0.7.0 migration wait on a manual `rm` on every machine. Found one command
  into that migration. A view that still resolves somewhere else is refused as
  before, because that one may belong to another store.

440 asserts, up from 434.

## 0.7.0 — 2026-08-25

**Refresh `.floppy/run`: yes** (four new keys). **The scopes moved under a
namespace directory — the old ones are refused with the `git mv` printed.**

The model is written down now: [docs/memory-model.md](docs/memory-model.md).
Three questions per note, independent — who may read it (a repository
boundary), what it is about (`projects/<key>` or `common`), and where it is
true (everywhere, one workplace, one machine). The layout had been renamed
three times in a day because that model existed only in whoever was editing.

- **Scopes are `public/projects/<key>` and `private/projects/<key>`.** The leaf
  that repeated the audience (`shared`, `private`) is gone. The namespace
  directory is always present, including in a repository that holds only one:
  the alternative makes the path depend on whether two config URLs are equal.
- **New keys `public_repo` and `private_repo`,** replacing `memory_repo` and
  `workplace_repo`, which are still read. The old pair named an audience with a
  validity word and made two independent questions look like one axis.
- **New keys `machine_key` and `workplace_key`.** They name the validity
  directories `machines/<machine>/` and `workplaces/<place>/` inside a scope,
  for a note that is not true everywhere — the cell no earlier layout could
  express. Both are optional and nothing creates the directories yet.
- Migration is refused, not performed, exactly as in 0.5.0 and 0.6.0: the verb
  prints the `git mv`. Wiring left pointing at an earlier scope is repointed
  without a manual `rm`.

## 0.6.2 — 2026-08-25

**Refresh `.floppy/run`: no.** Take it on any machine that has migrated to
`private`, or `status` lies to it on every call.

- **`status` spelled the private scope in, and 0.6.0 turned that into a
  permanent false alarm.** The section looked for `<memory_dir>/local` while
  the wiring, correctly, was `<memory_dir>/private`: a properly wired machine
  was told to run `workplace` on every call, and a genuinely broken link under
  the new name printed nothing at all. Found by reading the report on a machine
  that had just migrated — no test failed, because no test asserted the section
  against a wired repository. The name now comes from the environment, with the
  pre-0.6.0 variable read as a fallback so a repository sitting behind an
  unrefreshed shim is judged by the name that shim actually uses.
- The linter's fallback for the same variable said `local` where
  `memory-workplace.sh` said `private`. Under an unrefreshed shim the rule
  "committed memory must not link into the private scope" therefore guarded a
  directory that no longer existed — the way of applying to nothing that this
  variable was introduced in 0.4.0 to prevent. Both now end in `private`.

430 asserts, up from 423. The first draft of the new ones passed against the
unfixed code: the sandbox had no `.floppy/run`, so every "does not say X"
assert was satisfied by a run that died before printing anything. They now
assert the section printed before asserting what it says.

## 0.6.1 — 2026-08-25

**Refresh `.floppy/run`: no.**

- The rename left the old `local` link behind, pointing at a path the `git mv`
  had emptied — two links in the memory directory, one of them broken, on every
  machine that migrates. `workplace` now removes it, but only while it dangles:
  there is nothing behind a dangling symlink this verb created itself. A link
  under the old name that still resolves points at something real and is left
  alone.
- The refusal named the layout by the version it predates ("before 0.5.0")
  while refusing a 0.5.1 layout, and the commit line it suggested still spelled
  the old scope. Both were read on a live migration a minute after the release
  that made them wrong.

423 asserts, up from 415.

## 0.6.0 — 2026-08-25

**Refresh `.floppy/run`: yes** (new key name). **The private scope is renamed —
migrate it the same way as 0.5.0, and read why first.**

- **`local` became `private`,** in the scope (`projects/<key>/private`), in the
  link inside your repository (`<memory_dir>/private`), in the view, and in the
  config key (`memory_private_dir`; `memory_local_dir` still works).
  The name was left over from the days when that directory really was
  machine-local and gitignored. It has been neither since it became a symlink
  into a repository shared by a workplace's machines — and the name kept saying
  otherwise, convincingly enough that the owner of the corpus read it as "facts
  about this machine" and asked where those go. They go to `machines/<name>/`
  of the workplace repository, which is synced like everything else: that scope
  answers "where is this true", not "who may see it".
- The old scope is refused with the `git mv` printed, exactly as in 0.5.0 and
  for the same reason. A link left pointing at any earlier scope of the same
  repository is repointed without a manual `rm` (0.5.1).

415 asserts, up from 414.

## 0.5.1 — 2026-08-25

**Refresh `.floppy/run`: no.** Take it before migrating a second machine.

- **Wiring left by a pre-0.5.0 run is repointed, not refused.** After the scope
  move, `<memory_dir>/local` still pointed at the old scope of the same
  repository, and the verb stopped with "the symlink points elsewhere" — so
  every machine needed a manual `rm` before it could be rewired. That link is
  wiring: it holds no content, and this verb recreates it on each machine
  anyway. A link into a *different* repository is still refused, because that
  one may be another workplace and this verb does not guess.
- `readlink -f` left `memory-workplace.sh`. BSD readlink on macOS has no `-f`,
  so that comparison had never worked there — it was reached only when the link
  already disagreed, which is why no test and no machine had shown it.

414 asserts, up from 406.

## 0.5.0 — 2026-08-25

**Refresh `.floppy/run`: yes** (new key, and the shim resolves the new layout).
**Scope names changed — read the migration note below before updating.**

The layout is now keyed by project, not by repository. What a person opens is
`agents_memory_dir/<key>/`, holding `shared` and `local`; the clones moved into
`agents_memory_dir/.clones/<repository>/`, one per URL as before. A flat parent
mixed two alphabets — project names beside repository names — and telling them
apart needed the config open beside the terminal.

- **New key `project_key`.** One key names this project in every memory
  repository it uses and names its directory in the view.
  `memory_project_key` and `workplace_project_key` stay as overrides, for the
  project whose scope really is named differently in two repositories.
- **The scopes are siblings now:** `projects/<key>/shared` in the store,
  `projects/<key>/local` in the workplace repository. They were
  `projects/<key>/memory` and `projects/<key>` itself, so with one repository
  serving both roles the second contained the first — private notes and shared
  memory in one tree, and `--migrate-local` walking a corpus that was not its
  own. N projects were already separated by `<key>`; what confused them was the
  nesting.
- **The old scope names are refused, not migrated.** The verb stops and prints
  the `git mv` commands. Moving somebody's notes unasked is what this plugin
  refuses to do everywhere else, and doing it on ONE machine is worse than not
  doing it: until the other machine also runs 0.5.0, one writes the old path
  while the other reads the new one and the memory forks with nothing red
  anywhere. Update every machine first, then move the scopes once.
- `<memory_dir>` and `<memory_dir>/local` point at the view, not into a clone,
  so a repository URL can change without rewiring every worktree. The write
  probe at the end of each verb proves the whole chain, so the extra hop is
  checked rather than trusted.
- The view links are relative when the clone sits under the same parent:
  `agents_memory_dir` can be moved as one directory. They are never committed —
  in the adopted legacy layout, where the parent itself is a checkout, the
  containing repository is told to ignore them.
- `init` learned `--agents-memory-dir`, and now wires the store by calling the
  shim rather than the store script with a hand-built environment. That copy of
  the path resolution had already fallen behind the shim's.
- The nesting refusal walks up to the nearest existing ancestor. With clones
  under `.clones/`, testing only the immediate parent would have missed the
  case and cloned into the repository below it.

406 asserts, up from 405.

## 0.4.2 — 2026-08-25

**Refresh `.floppy/run`: yes** (the shim resolves the checkout paths, and one
new config key).

Two defects, both found by asking what happens when `memory_repo_dir` and
`workplace_memory_dir` name one directory, and both measured before they were
fixed.

- **Notes could be published to the wrong repository, with `ok` on every
  line.** The configured URL was read only on the clone path. With a checkout
  already at that directory, the second verb skipped its clone, never compared
  the remote, wired the link, and reported "a write through the link lands in
  the workplace repository" — while the notes landed in the store, where
  `commit` would have pushed them. Now: the checkout directory is **derived
  from the URL** under one parent (`agents_memory_dir`), so two repositories
  cannot collide; and any existing checkout has its `origin` compared with the
  configured URL, with a refusal naming both. That second check also catches an
  unrelated repository sitting at the path, which never needed a collision.
- **The wiring symlink was committed into the store.** With a store, `local/`
  is created inside the store's working tree, holding an absolute path: on a
  machine whose checkout lives elsewhere it is a dangling link, and the path
  `projects/<key>/memory/local/memory/local/...` recurses without limit. It is
  per-machine wiring, and every machine runs the verb anyway, so the store is
  now told to ignore it.
- New key `agents_memory_dir` (default `$HOME/agents_memory`), with a worked
  example of the resulting tree in the README — the layout was described in
  words only, and "the parent" named nothing a reader could point at. `memory_repo_dir`
  and `workplace_memory_dir` remain as per-machine overrides. **Nothing to
  migrate:** a checkout already sitting at the parent is adopted once its
  `origin` matches, and the verb says so.
- A clone that would land inside another checkout is refused, with the two
  commands that undo the nesting. `scripts/lib-checkout.sh` now holds the half
  of the two verbs that was duplicated — and had already drifted.

405 asserts, up from 377.

## 0.4.1 — 2026-08-25

**Refresh `.floppy/run`: yes** (the install hints it prints name the
repository, and the repository was renamed).

- The repository is `spscream/ai-floppy`, was `spscream/ai_floppy`. GitHub
  redirects the old name for both git and the web, so an existing marketplace
  entry and any command someone already wrote keep working; what would not
  have kept working is the hint a failing shim prints, which would have named
  a repository nobody can find. Nothing else moved: the plugin and the
  marketplace are still both `floppy`, `floppy@floppy` installs as before, and
  `AI_FLOPPY_HOME` keeps its underscore — it names an environment variable,
  not the repository.
- No behaviour changed anywhere. This version exists so that `plugin update`
  copies the corrected shim at all: it compares version strings, and under an
  unchanged one it would report "already at the latest version" over a shim
  still printing the old name.

## 0.4.0 — 2026-08-25

**Refresh `.floppy/run`: yes** (new verb, four new config keys).

- New verb `store`: wires memory hosted in another repository — clone or pull,
  link, add the ignore line, and then the step that actually proves it, writing
  through the link and confirming the file appears in the store. Idempotent,
  per machine and per worktree, `--check` reports without changing. It refuses
  rather than guesses when a real directory sits where the symlink belongs:
  those notes may be the only copies of something.
- `init` learned `--memory-repo` / `--memory-key` / `--memory-repo-dir`, and
  writes the index *through* the new symlink so it lands in the store. Half the
  pair is refused rather than half-applied. Without the flags nothing changes:
  the generated config documents the option commented out, because a project
  pointed at a store it never chose would write its notes into somebody else's
  repository.
- **New guard, and it catches a state that was comfortable to live in:** a
  memory directory that is gitignored *and* inside this repository. That is the
  shape a half-done external setup takes — ignore line added, symlink never
  created — and in it notes are written and read normally while nothing will
  ever commit them. Previously the failure surfaced at the end of the session
  wearing the wrong name ("not changed: wrong path, or the edit was lost").
- `memory_local_dir` (default `local`) names the machine-local scope instead of
  the linter spelling it in. Not cosmetic: the rule "committed memory must not
  link into that scope" is what protects against links dead on a second
  machine, and under any other name it had been silently applying to nothing.
  A name with regex metacharacters is refused rather than matched wrongly.

377 asserts, up from 328.

## 0.3.0 — 2026-08-25

**Refresh `.floppy/run`: yes** (new config key).

- The memory size caps left `memory-lint.sh`, into **two** homes rather than
  one. `index_chars_max` is a fact about the *harness* — its session loader
  truncates the memory index past a limit of its own, measured at ~24986
  characters on Claude Code — so it is a `.floppy/config` key with the number
  shipped as a default. `pointer_line_max` is a fact about *your corpus*, the
  same kind as `pointers_max` beside it, so it joins `quota.lock` (default 170).
  Asking a project to measure the first one would be asking it to measure
  somebody else's tool.
- The index-size *warning* threshold is no longer configurable at all. It had
  to stay in a fixed relation to the cap, which is two chances to set it wrong;
  derived at 96%.
- Both new values are rejected by name when non-numeric, and fall back to the
  default rather than comparing against garbage.

## 0.2.3 — 2026-08-25

**Refresh `.floppy/run`: no.** But if your memory is external (0.2.2), take
this release: without it the memory gate silently passes.

- **Fixed, and it was serious:** `memory-lint.sh` walked the memory with plain
  `find`, which does not descend into a symlinked starting point. With memory
  hosted in another repository the memory directory *is* a symlink, so every
  check iterated over nothing and reported `clean: 0 notes` — and that lint is
  `wrap-commit`'s first gate, so the whole memory gate was dead in that layout.
- `tests/run.sh` dispatched each test through a bare `bash`, resolved via PATH.
  On macOS a newer bash normally sits ahead of `/bin/bash`, so a run meant to
  prove bash 3.2 compatibility re-tested bash 5. It now uses `$BASH` and prints
  which interpreter it is using.
- CI added: the suite runs on ubuntu (bash 5) and on macOS with `/bin/bash`
  explicitly, which is the job that actually earns its minutes.

## 0.2.2 — 2026-08-25

**Refresh `.floppy/run`: yes** (the shim derives the new layout).

- **Memory can live in a repository other than the code's** — for a checkout
  you do not own, or a policy keeping notes and code apart. Point `memory_dir`
  at a symlink into another git repository and gitignore it; `guard` asks that
  repository what changed and answers in the paths you typed, `check` shows the
  notes going out, `commit` commits and pushes both from one file list, and
  `status` reports the store so a clean tree stops meaning "nothing pending".
- The layout is **derived** from where `memory_dir` resolves, never declared:
  a flag in the config would disagree with the filesystem exactly when a
  symlink failed to be created.
- A store that cannot be pushed fails `commit` loudly instead of printing
  "session closed" over unpublished notes. A `memory_dir` outside git
  altogether is named as such — it reads and writes fine and publishes nothing.
- Setup is still manual (clone, symlink, ignore line). `init` does not do it yet.

## 0.2.1 — 2026-08-25

**Refresh `.floppy/run`: yes — and this is the release that makes future
refreshes visible.**

- The shim compares itself against the plugin's copy on every call and prints
  one line on stderr when they differ, with a ready `cp`. Most of the ways a
  shim goes stale are silent: a corrected config parser or search order just
  keeps doing the old thing.
- A warning, not a gate — an old shim usually still works, and refusing to run
  would turn a nudge into an outage on whichever machine pulled first.
- The hint is a plain `cp` and not a `refresh` verb, because a shim old enough
  to need refreshing is too old to know the verb that would do it. For the same
  reason this guard only starts working *after* one manual refresh.

## 0.2.0 — 2026-08-25

**Refresh `.floppy/run`: yes** (new verb).

- New verb `parity`: compares localized command files against the English
  skills they translate — the set of `bash .floppy/run <verb>` calls and the
  sequence of numbered headings, and deliberately nothing about wording,
  section titles or length. `wrap`'s `check` gates on it.
- Both stale-copy failures around the shim used to be mute and now name which
  side is behind: an unknown verb (this copy is old) and a verb whose script is
  missing (this machine's plugin is old).
- New config key `commands_dir` (default `.claude/commands`).

## 0.1.1 — 2026-08-25

**Refresh `.floppy/run`: yes.**

- The shim refuses to resolve into a plugin directory that holds no
  `scripts/*.sh`. A cache from a moment when `scripts/` was empty was being
  treated as an install, and every verb died with "No such file or directory"
  pointing inside the cache.
- Version bumped for its own sake as well: `plugin update` had been reporting
  "already at the latest version" and copying nothing.

## 0.1.0 — 2026-08-25

First release. The session rite extracted from the project it grew in: the
shim, eight verbs, five skills, memory conventions, and the guards — file-list
gate, memory linter, per-session lock — that keep the rite honest.
