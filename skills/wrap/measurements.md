# What the rules in `wrap` stand on

Read this when a rule in `SKILL.md` looks arbitrary, when you are about to
change one, or when a later measurement contradicts it. Executing the rite does
not need any of it.

## The turn is the unit, not the tool call

Measured over 48 `/start` and `/wrap` runs: reasoning costs about 649 tokens per
turn, and parallel calls issued together in one block cost as one turn. So
wrapping calls in a script pays off only where it removes a *turn* — four
independent reads already issued in a single block save nothing at all.

That is exactly what `check` and `commit` do. The steps they replace were not
independent: each one's result decided whether the next should run, so the model
had to stop, read, and choose between them — four separate turns before anything
was written, and six more after. Folding them removes those stopping points. A
skill that expands `check` and `commit` back into their individual `git status` /
`git diff` / lint calls puts every one of them back.

The larger arithmetic is worth knowing, because it is not intuitive: every turn
resends the whole window, so a session's bill is roughly turns × window size, and
the window only grows. The cost is quadratic in session length — which is why the
answer to a long session is to end it, not to economise inside it.

## The fold worked and the rite still doubled

Measured 2026-09-05 over 35 `/wrap` runs in one project, and confirmed on 13 in
another. Counting a turn as one API request — several transcript entries share
one `requestId` and one usage record, and counting entries instead inflates every
number here by about 1.6× — the rite went from 12 turns per run before the fold
to 25 after. The `tools/*.sh` calls it replaced are gone entirely, but the shim
verbs that replaced them cost **5.1 turns per run, 23% of the total**, because
runs call `lint`, `guard` and `status` *on top of* `check`, which already runs
all three. That is where the three habits in §5 come from.

## The price of patching the current-state file

Measured 2.6 edit turns per run on that one file, and 2.7 when re-measured a week
later across five repositories — the rule has never held, in either direction of
the capture convention. It is standing practice, not a regression.

A turn editing this file has a median price of **32k base-equivalent tokens**
(p90 44k, max 62k; taken from the `usage` of the message that made the edit,
deduplicated by `message.id`), almost all of it re-reading the context rather
than writing the text. Two patching turns cost 64k where one full rewrite costs
49k, the file's entire content in its output included; at the p90 of six turns
the gap is 143k.

A first pass measured *characters* instead and concluded the reverse — patching
"cheaper" in 28 runs out of 29. Wrong unit: the file is 12 KB, the context is
hundreds of thousands of tokens.

## There is nothing to cut in the narration

Turns that call no tool at all are 5.6% of the total, and every single one of
them was the last turn of the run — the report to the human. A count over
transcript entries puts them at 17–38% and points at a saving that does not
exist: the text and thinking blocks of a turn that did call a tool are separate
entries, and they are already paid for.

## A superseded explanation, kept so it is not re-derived

An earlier version of §5 explained the fold by "reasoning happens before every
tool call", citing 7.5k tokens across six calls. That framing was superseded by
the 48-run measurement above: it counted calls where it should have counted
turns. The conclusion held; the reason did not.
