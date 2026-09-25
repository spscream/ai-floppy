# Behavioural evals

`tests/` guards the *shape* of this plugin — frontmatter, directory names,
manifests in step. It says so about itself, in `tests/test-skills.sh`:

> Skills are prose, so there is nothing to assert about behaviour — this only
> guards the shape.

This directory is the other half: three cases that each ask whether a skill
**changed what an agent did**. They are run by `claude plugin eval`, whose
`--ablation with-without` arm runs every case twice — once with the plugin and
once without — so a case reports a delta rather than a score the model would
have scored unaided.

## The three cases

| case | the rule it measures | where the rule is written |
|---|---|---|
| `wrap-rewrites-the-status-file` | the current-state file is rewritten once, not patched | `skills/wrap/SKILL.md` §5 |
| `workstatus-checks-instead-of-recalling` | live state is reported from floppy's `status` verb, never from the documents | `skills/workstatus/SKILL.md` |
| `a-fact-becomes-one-note-with-an-index-line` | one fact per file, one pointer line, never the note's text in the index | `skills/agent-memory/SKILL.md` |

The first is the one worth having. The rewrite-once rule was measured at 2.6
edit turns per run and again at 2.7 a week later across five repositories — it
has never been obeyed, and the price in `skills/wrap/measurements.md` (two
patching turns cost 64k base-equivalent tokens where one rewrite costs 49k) was
added because the bare count had moved nobody. The case is what can tell us
whether the price moved it.

## Nothing here has been run

**No case in this directory has been executed.** `claude plugin eval` is in
early access, enabled per organization, and it is not enabled for the account
that authored these:

```
$ claude plugin eval . --case wrap-rewrites-the-status-file --runs 1 --ablation none
`plugin eval` is currently in early access
$ echo $?
1
```

Both `eval` and `eval init` exit 1 with that line and do nothing else, so the
cases were hand-written rather than generated.

**The decision is to leave them unrun** (2026-09-17). The enablement comes from
an Anthropic contact and the CLI's own text forbids guessing its name; asking
for it buys nothing until there is work that needs the runner. These cases wait
for early access to widen.

Their *shape* has been checked without the runner, and that is all that has
been checked. Claude Code carries the schema it validates `case.yaml` against
inside its own binary, so all three were validated against it directly:
`schema_version` is compared on the major only, every grader object is strict,
and `arm` accepts `with-only` or `both` and nothing else. What no such check
can reach is whether an `input_match` fires on a real trace — treat every
grader below as untested in that sense. Nothing in `tests/run.sh` covers this
directory either, deliberately: a guard here would assert a schema this
repository cannot execute.

## Running them

Once the command is enabled, from the repository root:

```bash
claude plugin eval . \
  --case wrap-rewrites-the-status-file \
  --runs 1 \
  --ablation none \
  --max-cost-usd 1.00 \
  --scaffold \
  --allow-tools Bash Write Edit
```

`--scaffold` is required: each case builds its fixture with a `scaffold.sh` that
the runner will not execute without it, and the flag is a grant, not a default,
because a scaffold is author-supplied bash that runs as you. These three were
authored in this repository; read them before granting it, as you would for any
case file arriving from elsewhere.

Drop `--ablation none` to get the with/without delta, which is the number the
suite exists for — it costs two arms instead of one. Drop `--case` to run all
three. `--runs` defaults to 3, which is what each `case.yaml` asks for; the `1`
above is a budget, not a recommendation, and a single run of a behavioural case
says very little.

## How a case is written

Each case is a directory holding a `case.yaml` and the `scaffold.sh` it names.
`case.yaml` carries the prompt (`execution.prompt`), the fixture
(`context.scaffold_script`), and the graders inline. The alternative form —
`prompt.md` with a `graders/` directory beside it — cannot carry
`context.scaffold_script`, and all three cases need a fixture repository to act
on, so all three are written as `case.yaml`.

The graders used here:

- **`tool_used`** — counts calls to one tool whose serialised input matches
  `input_match`, against `min`/`max`. `min: 0, max: 0` is "must not call". This
  is what makes the rewrite-once rule mechanically checkable: one `Write` of the
  status file, zero `Edit`s of it.
- **`regex`** — matches a pattern against `last_message`, `trace`, `files` (the
  paths the run changed), or the contents of one produced file
  (`target: {source: file, path: …}`). `match: count:N` asserts an exact number
  of matches; the `g` flag is set explicitly wherever a count is asked for.
- **`file_exists`** — a glob over the files the run changed.
- **`llm`** — a judge reads `criteria` against `last_message`, `trace`, or one
  file, for the half of each rule no pattern can see.

Every case also carries a `tool_used: Skill` grader marked `arm: with-only`.
Under `--ablation with-without` that one is an indicator rather than part of the
score — it answers "did the skill fire at all", which the no-plugin arm cannot
do by construction.

## What these graders cannot see

Worth knowing before a red score gets read as a broken skill.

- **A file written through `Bash` is invisible to a `tool_used: Write`
  grader.** A session that writes a note with a heredoc has obeyed the rule and
  will still lose that grader's weight. Every `input_match` here is anchored to
  the tool input's own key (`"file_path"`, `"command"`) so that a path appearing
  in a file's *contents* is not counted as a call, but nothing anchors the
  choice of tool.
- **The index grader counts pointer lines, not new ones.** It asserts the half's
  `INDEX.md` ends at four `- [` lines, which is one more than the fixture seeds.
  Change the seeded notes and `count:4` has to move with them.
- **`--ablation none` produces a score, not a delta.** A case that passes in the
  with-plugin arm alone has not yet shown the skill did anything the model would
  not have done unaided. That is what the second arm is for.

## A note on the fixtures

Each `scaffold.sh` writes a stand-in runner at `.floppy/run` rather than wiring
up the real one. Two reasons, and only the first went away in 0.26.0. The shim
resolved the installed plugin through the harness's cache, and an eval run gets
a temporary `HOME` where no such cache exists — so the real shim printed
"plugin not found" and every case measured its own fixture. The second reason
stands: a stand-in is an **oracle**. It answers the verbs its rite calls with
the invented state the case is built around — a background job at 41%, a branch
that is two commits ahead — which a real dispatcher, pointed at a scratch
directory, would correctly refuse to say.

**What 0.26.0 left open here.** Skills now call the plugin's own
`<plugin>/scripts/run`, so a model following them lands on the real dispatcher
and never reaches the stand-in at `.floppy/run`. These cases are unrun by
decision (2026-09-17, above), so nothing turned red; what is true is that the
oracle now sits at a path the skills no longer name.
Putting it back in the path of the call is the fixture work the first real run
will have to start with: the supported seam is the repository's own
`.floppy/workstatus-project.sh` hook, which the real `status` executes and
prints, and which the fixture can therefore use to state an invented fact the
scratch directory cannot produce on its own.
