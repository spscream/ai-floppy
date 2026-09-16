---
name: opus5-subagent-prompt-line
description: The "do not use the Agent tool" line is a built-in default of the Opus 5 prompt bundle, not anything in your config
area: harness
verified_on: 2026-09-17
verified_against: "Claude Code 2.1.267 (native binary), Linux 6.18 (WSL2), model claude-opus-5"
recheck: "grep -ac 'tool, workflows, or deep-research unless the user' \"$(command -v claude)\""
invalidated_by: "The model loses the opus_5_prompt_bundle capability, Anthropic ships tengu_fennel_godwit true or tengu_slate_bittern false, or a non-empty tengu_heron_brook already carries the same sentence"
requires: command -v claude >/dev/null 2>&1
recheck_cmd: n=$(grep -ac 'tool, workflows, or deep-research unless the user' "$(command -v claude)" 2>/dev/null || true); [ "${n:-0}" -gt 0 ] && echo present || echo absent
expect: present
---

# Sessions refuse to spawn subagents because of a line no configuration file contains

## The fact

On Opus 5 models, Claude Code appends a sentence to the system prompt:

```
Do not use the Agent tool, workflows, or deep-research unless the user, a CLAUDE.md file, or a skill asks for it
```

It is a compiled-in default of the CLI, assembled in a prompt section named
`opus5_reduced_delegation` and gated on the model carrying the `opus_5_prompt_bundle`
capability. **Sessions on any other model do not receive it.** No settings file, output
style, memory file, managed policy or process argument turns it on or off. Remote feature
flags can suppress it, but when they are absent — the ordinary case — the built-in default
applies.

The wording is not stable across releases. Claude Code 2.1.232 shipped two sentences
beginning `Do not call the AgentTool unless the user requested it`; 2.1.267 ships the one
above, built from a template whose `${mt}` resolves to the tool's own name. Grep for the
sentence's middle, never for a whole literal.

## Why it is not obvious

The line reads exactly like a project rule, so the first move is to search the
configuration for it. That search returns nothing at every level, on every machine, and
the natural conclusion — "I must be looking in the wrong place" — is wrong. There is no
place. Worse, the behaviour looks capricious: the same repository delegates freely one day
and refuses the next, because the model changed.

## Evidence

**MEASURED.** The current phrasing is present twice in the 2.1.267 binary, and the 2.1.232
phrasing is gone from it entirely:

```
$ B=$(command -v claude); grep -ac 'tool, workflows, or deep-research unless the user' "$B"
2
$ grep -ac 'Do not call the AgentTool unless the user requested it' "$B"
0
```

**READ.** Decompiling the bundle gives the literal, the section and the whole gate
(identifiers are minified and will differ between builds):

```js
var ISr = `Do not use the ${mt} tool, workflows, or deep-research unless the user, a CLAUDE.md file, or a skill asks for it`,
    MEs = "Do not call the AgentTool unless the user";       // the 2.1.232 wording, kept only to detect itself

My("opus5_reduced_delegation", () => {
  if (!Z8t(d)) return null;                                   // the capability gate, below
  if (!I("tengu_slate_bittern", !0)) return null;             // kill switch, default true
  let _e = OSr()?.value;                                      // whatever tengu_heron_brook holds
  if (_e?.includes(ISr) || _e?.includes(MEs)) return null;    // don't say it twice
  return ISr;
})

function Z8t(e){
  if (e === undefined) return false;
  if (dm(Be(e), "opus_5_prompt_bundle", e) !== true) return false;  // the entire gate
  return !I(of, false);                                             // of = "tengu_fennel_godwit"
}
```

**MEASURED.** Of every model in the 2.1.267 model table, exactly one carries
`opus_5_prompt_bundle` in its `capabilities` array: `claude-opus-5`. That is why a Sonnet
session delegates and an Opus session does not.

**READ.** `tengu_heron_brook` no longer replaces this text. In 2.1.267 it is a section of
its own, and it only suppresses this one when its value already contains the same
sentence. A second, unrelated key — `tengu_brook_heron`, note the swapped words — carries a
per-model, per-effort map of prompt text pushed from the server.

**READ, the opposite case.** A neighbouring section, `subagent_steer_delegation`, is
selected when delegation steering is set to `counter_steer`, and appends a long
`## Delegating to subagents` passage arguing the cost of subagents instead. A session can
therefore be discouraged from delegating by either of two quite different texts.

**MEASURED, negative control (2026-09-05, still the basis for this paragraph).** An
exhaustive search of `settings.json` at both levels, `~/.claude.json`, output styles,
`~/.claude/CLAUDE.md`, `~/.claude/rules/`, `/etc/claude-code/` and the process arguments
returned zero matches — twice, on two different days.

## How to re-check

```bash
B=$(command -v claude)
grep -ac 'tool, workflows, or deep-research unless the user' "$B"
```

A non-zero count means the built-in default is still what your Opus 5 sessions get. Read
the `cachedGrowthBookFeatures` map in `~/.claude.json` for keys containing `bittern`,
`godwit` or `heron` to confirm no flag is overriding it; absent keys are the ordinary
case.

If the count is zero, read the phrasing out of the binary before concluding the line is
gone — that is how this note's own check failed on 2026-09-17, while the behaviour it
describes had not changed at all:

```bash
python3 - <<'PY'
import re
b = open("/path/to/claude", "rb").read().decode("latin-1")
print(*re.findall(r"Do not (?:call|use)[^`\"]{0,120}", b), sep="\n")
PY
```

## What it costs you not to know

You lose subagent delegation silently and pay for it. A session on Opus at high effort
reads the line, concludes it may not spawn helpers, and runs the whole mechanical block —
test suites, builds, bulk renames — itself, at the expensive model's rate. Nothing warns
you; the work simply costs several times what it should, and the session that could have
told you why instead apologises and gets on with it.

The line ends with `unless the user, a CLAUDE.md file, or a skill asks for it`, and since
2.1.267 it says so outright: a standing instruction in a file that loads every session
**is** such a request. One paragraph in `~/.claude/CLAUDE.md` or an always-loaded rules
file removes the restriction permanently, which is a far better answer than granting
permission by hand in every conversation.

## See also

- [[rewind-does-not-restore-everything]] — another case of harness behaviour that no
  configuration file describes.
