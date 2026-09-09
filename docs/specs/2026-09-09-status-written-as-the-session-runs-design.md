# Writing the memory as the session runs: design

Written 2026-09-09 against 0.20.0. Decided with the owner in the session that
followed #60, from the open item carried in `docs/statuses/NOW.md` since
2026-09-08.

This document is in English for the reason the two specs before it give: the
language of a document, of the memory, and of a reply to a human are three
separate choices.

## The finding this starts from

`wrap` fires at the one moment in a session when everything is at its most
expensive. The window is at its largest, the accumulated change at its biggest,
and the rite then spends several turns *collecting* — re-reading the session to
decide which facts earned a note, writing them, reconciling the status file,
updating the index.

What is actually measured, and what is not, matters here more than usual,
because the whole proposal rests on the difference.

**Measured** (2026-09-05, over 35 `/wrap` runs in one project, confirmed on 13
in another, counting a turn as one API request): the rite costs **25 turns per
run**. Of those, **5.1 turns — 23%** go to shim verbs called on top of `check`,
and **2.6 turns** to editing the status file. Turns that call no tool at all are
5.6%, and every one is the closing report.

**Not measured**: how the remaining ~17 turns divide between selecting facts,
writing notes, and everything else. The open item's "$0.20–0.25 per turn at
400–500k context" is arithmetic over published cache-read pricing, not a count.

So the honest statement of the premise is: *a session's bill is roughly turns ×
window size, the window only grows, and fact-selection is known to happen at the
maximum of that curve.* How much it costs there is unattributed. This design is
built on the shape of the curve, not on a number, and nothing below should be
read as claiming otherwise.

## What moves, and what must not

`wrap` does five things. Only two of them can move.

| what wrap does | moves? | why |
|---|---|---|
| takes the lock | no | it serialises the whole rite |
| selects which facts earn a note | **yes** | the judgement is *better* at the moment the fact appears, and cheaper |
| writes the notes and their pointers | **yes** | a note collides with nothing; an anchored pointer insert merges |
| reconciles the status file | **no** | it is rewritten whole, which is exactly what the lock exists for |
| `check` and `commit` | no | they are the closing itself |

The status file staying put is not conservatism. 0.18.0 split the personal half
out of it precisely because a whole-file rewrite is the one artefact two
overlapping sessions cannot both survive; rewriting it repeatedly through a
session re-creates that collision on every repetition instead of once. And its
hardest content — what is unfinished, what is waiting on the human — is only
knowable at the end.

## The seam: why mid-session writing needs no lock

This is the load-bearing mechanical argument, and it must be stated in the
skill rather than assumed.

- **A note file collides with nothing.** Its name is unique by construction;
  two sessions writing two notes write two files.
- **A pointer is a one-line anchored insert.** An edit anchored on a line
  applies against whatever the index holds *at that moment*, so two sessions
  inserting different pointer lines both land. This is the opposite of the
  status file, where a second writer silently drops the first writer's prose.
- **What stays forbidden mid-session is the whole-file rewrite** — of an index,
  and of either status file. Those belong to `wrap`, under the lock.

The pointer cannot be deferred to `wrap`. A note with no pointer in its index is
a **hard error**, not a warning: `scripts/memory-lint.sh:419` — *"nobody will
find this note"*. So a mid-session note carries its pointer in the same breath.

That constraint also supplies the failure mode. If a session rewrites an index
whole and drops somebody's pointer, the orphaned note reddens the next `check`
loudly, in a message that names the file. The failure is detected, not lost —
which is the property the status file does not have, and the reason the two are
treated differently.

## Where the rule lives, and why it cannot live in `wrap`

A rule fires only if it is already in the session when the moment arrives.

- `wrap` is loaded at the end. Too late by definition.
- `agent-memory` says "load this before writing a note" — circular, because the
  rule is the thing that tells a session a note is due.
- `start` is the only rite guaranteed loaded early, and every session opens with
  it.

So the change splits: **`agent-memory` carries the convention** — it is a
convention, and that skill is where the other three go for conventions — and
**`start` plants the trigger**, as a short closing paragraph framed as *what
carries into the session after this rite*.

`start` opens with "Orienting, not working. Do not edit code or memory during
this." The addition survives that reading because it governs what happens after
`start` rather than during it, and it must be written so the distinction is
visible on the page. It is the most debatable single edit in this design and is
recorded as such.

## What counts as a note-moment

Five triggers, drawn from what `wrap` already names as the most valuable things
to survive a session, plus the rejected-options rule already in force:

- an option or hypothesis is **rejected** — the reason is exact now and
  reconstructed later;
- a **measurement lands** — the number, and what it was measured against;
- a number **turns out to mean something other than it looked like**;
- a **tool or platform trap** bites;
- a **decision is frozen** — a choice that constrains later work.

Explicitly not triggers: finishing a task, making a commit, a green suite. Those
are in the git log, and `wrap` already says the list of what got done is the
least valuable thing to record.

## What `wrap` becomes

§1 stays and shrinks. It asks **what is left unrecorded**, not what the session
produced — some facts only crystallise at the end: a conclusion about the
session's whole shape, an approach whose rejection became clear only later. A
rite that noticed such a fact must have somewhere to put it.

`wrap` does **not** re-open what was captured during the session. Two existing
rules already cover a mis-capture: a refinement edits the file that already
states the fact, and deletion is the fourth answer to a note that stopped being
true.

One consequence that is easy to miss: **the closing report's part 1 must list
both** — what was captured during the session and what was captured at `wrap`.
Otherwise the report silently under-reports the session's own memory, and the
human loses the chance to object that §2 of the report exists to give them.

§0, §3, §4 and §5 are untouched.

## Rejected, with reasons

Recorded here rather than in a session note, because they were rejected during
the design and the design is the document that survives.

- **A new verb or a mid-session rite** (`keep`, `note`). Writing a note is
  already one file write plus one anchored line; the expensive part is the
  *judgement*, which no script can take over. The cost is not zero: a verb adds
  a row to `scripts/run`, a script, tests, a `docs/guide` mention and possibly a
  site page-table row — for no saved turn. Revisit if capture turns out to be
  skipped for mechanical friction rather than for judgement.
- **A pruning pass at `wrap`.** Better selection — capture-time judgement has no
  hindsight, and one of the three admission criteria is "it outlives the
  session", which cannot be fully known at the moment. Rejected because it
  re-introduces a read-and-decide pass at maximum context, which is the exact
  cost being removed. Revisit if the corpus starts accumulating notes that fail
  the criteria.
- **Writing the status file incrementally.** Rejected on the collision argument
  above.
- **`workstatus` as the checkpoint** — one line asking "is a note owed?".
  Rejected: it turns a report into a chore, and the trigger already lives in
  `start`. The rite's own rule is that a report which is always equally full
  stops being read.

## Evidence discipline in the prose itself

The new text must mark its own justification as **arithmetic over an existing
measurement, not a new measurement**, and name what a real measurement would
need: attributing `wrap`'s ~25 turns per run between fact-selection and the
rest. A skill that teaches the `measured` / `read` distinction cannot break it
in its own reasoning.

## What this design depends on

The trigger lives in `start`, so it is planted only in sessions that run
`start`. That is a real dependency and the weakest joint in this design. A
session that skips the rite gets the convention only if something else loads
`agent-memory` — and the circularity above says nothing will. It is named here
rather than left implicit because the failure is silent: no note is written, no
check reddens, and the session closes looking exactly like one that had nothing
to record.

## Hooks: checked, and not used

Checked 2026-09-09 against the Claude Code hooks reference, the plugin
reference, and Cursor's third-party-hooks page.

What is true:

- **A plugin can ship hooks** — `hooks/hooks.json` at the plugin root, or inline
  under a `hooks` key in `plugin.json`. The mechanism is available to floppy
  itself, not only to a consumer's settings.
- **Four events can inject text the model sees**: `SessionStart`,
  `UserPromptSubmit`, `PreToolUse`, `PostToolUse`, through
  `hookSpecificOutput.additionalContext`.
- **`PreCompact` cannot.** It can *block* compaction and nothing else; the
  request to let it inject context is issue #50682, closed as not planned.
- **`Stop` cannot either.** It can block with `decision: "block"` and a
  `reason`, and that reason is shown to the human in the transcript.
- **Cursor's hooks are not drop-in**: camelCase event names, `permission` in
  place of `permissionDecision`, a flat output shape accepted beside the nested
  one, and some events absent entirely.

`SubagentStop`'s behaviour is **not documented** and was not tested; nothing
here rests on it.

Why none of this becomes a mechanism:

- **A hook can guarantee a reminder; it cannot guarantee the judgement.** No
  deterministic code can tell that a fact worth keeping just appeared. A hook
  fires on an event or a schedule — and a reminder on every tool call is the
  definition of the check that gets switched off, which is this repository's own
  stated reason for keeping reporters separate from gates.
- **The one event that matches the problem cannot help.** Compaction is exactly
  the moment the reasoning is about to be lost, and it is an event rather than a
  judgement — but `PreCompact` cannot inject context, and blocking compaction
  does not cause a note to be written.
- **A hook could read `transcript_path` and classify.** That is a heuristic in
  `/bin/bash` 3.2 over a growing JSONL, in a repository whose suite cannot
  simulate a harness at all, and its false positives would land in every
  consumer's session.
- **Portability.** floppy puts exactly one file into a consumer repository. A
  hook set would be a second surface, behaving differently in the two harnesses
  the plugin supports.

**Deferred rather than rejected outright:** a `SessionStart` hook injecting the
five triggers is the only thing that would close the dependency named in the
section above, because it fires whether or not the human runs `start`. It would
cost those tokens in every session of every consumer, forever, to cover the case
where the rite was skipped. Revisit if capture is observed to fail in sessions
that skipped `start` — not before, because the cost is certain and the failure
is not.

## Files changed

| file | change |
|---|---|
| `skills/agent-memory/SKILL.md` | new section: when a note gets written, the five triggers, the collision seam |
| `skills/start/SKILL.md` | closing paragraph planting the trigger |
| `skills/wrap/SKILL.md` | §1 reframed to the leftovers; report part 1 lists both sources |
| `docs/guide/skills.md` | the `wrap` bullet says the agent selects facts at wrap; that becomes false |
| `docs/guide/skills.ru.md` | translated and re-stamped with `translation-check.py --stamp` |

`skills/` is product in this repository, so this lands through a pull request,
not through `wrap`. `docs/guide/` is on the same side since 2026-09-08.

## Testing

**Nothing in the suite covers this, and that is the price of the chosen scope,
not an oversight.** `tests/test-skills.sh` checks the `name:` field and the
absence of `allowed-tools`; `tests/test-docs.sh` checks that every `cfg_get`
appears in the config table; `tests/test-site.sh` needs a page-table row only
for a new document under `docs/*.md` or `docs/guide/*.md`. No new file, no new
key, no new verb — so no gate moves, and every one of them stays green whether
or not this change is wired.

Re-stamping `docs/guide/skills.ru.md` is the one mechanical step with a check
behind it: `python3 scripts/translation-check.py` must report clean afterwards,
or the drift workflow files an issue about a drift this change created on
purpose.

## Release

A patch bump across the three manifests, with a `CHANGELOG.md` entry whose
**"Refresh `.floppy/run`?"** answer is **no** — the shim is untouched. Timing is
the owner's call and is deliberately not folded into this work.
