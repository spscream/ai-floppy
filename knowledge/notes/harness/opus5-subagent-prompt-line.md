---
name: opus5-subagent-prompt-line
description: The "do not call the AgentTool" line is a built-in default of the Opus 5 prompt bundle, not anything in your config
area: harness
verified_on: 2026-09-05
verified_against: "Claude Code 2.1.232 (native binary), Linux 6.18 (WSL2), model opus[1m]"
recheck: "grep -ac 'Do not call the AgentTool unless the user requested it' ~/.local/share/claude/versions/<version>"
invalidated_by: "Anthropic ships a non-empty tengu_heron_brook flag, or the gate stops keying on the Opus 5 prompt bundle"
requires: command -v claude >/dev/null 2>&1
recheck_cmd: n=$(grep -ac 'Do not call the AgentTool unless the user requested it' "$(command -v claude)" 2>/dev/null || true); [ "${n:-0}" -gt 0 ] && echo present || echo absent
expect: present
---

# Sessions refuse to spawn subagents because of a line no configuration file contains

## The fact

On Opus 5 models, Claude Code appends two sentences to the system prompt:

```
Do not call the AgentTool unless the user requested it
Do not use workflows or deep-research unless the user requested it
```

They are a compiled-in default of the CLI, gated on the model belonging to the
`opus_5_prompt_bundle` capability. **Sessions on Sonnet do not receive them.** No settings
file, output style, memory file, managed policy or process argument turns them on or off.
A remote feature flag (`tengu_heron_brook`, delivered through GrowthBook) can replace the
text, but when the flag is absent — the ordinary case — the built-in default applies.

## Why it is not obvious

The line reads exactly like a project rule, so the first move is to search the
configuration for it. That search returns nothing at every level, on every machine, and
the natural conclusion — "I must be looking in the wrong place" — is wrong. There is no
place. Worse, the behaviour looks capricious: the same repository delegates freely one day
and refuses the next, because the model changed.

## Evidence

**MEASURED.** The literal is present three times in the 2.1.232 binary:

```
$ grep -aoc 'Do not call the AgentTool unless the user requested it' \
    ~/.local/share/claude/versions/2.1.232
3
```

**READ.** Decompiling the surrounding bundle text gives the construction and its gate
(identifiers are minified and will differ between builds):

```js
LYf = ["Do not call the AgentTool unless the user requested it",
       "Do not use workflows or deep-research unless the user requested it"].join("\n");

function jCS(e){
  let t = Gx()?.tengu_heron_brook;      // value pushed from the server
  if (t) return t;
  let r = rt("tengu_heron_brook", "");  // GrowthBook feature flag
  if (r) return r;
  if (lNo(e)) return LYf;               // built-in default
  return null;
}

function lNo(e){
  if (e === undefined) return false;
  if (c1(Uo(e), "opus_5_prompt_bundle") !== true) return false;   // the entire gate
  return !rt(QD_, false);
}
```

**MEASURED.** `tengu_heron_brook` was absent from the 502 flags cached in
`~/.claude.json` under `cachedGrowthBookFeatures`, so the third branch is the live one.

**MEASURED, negative control.** An exhaustive search of `settings.json` at both levels,
`~/.claude.json`, output styles, `~/.claude/CLAUDE.md`, `~/.claude/rules/`,
`/etc/claude-code/` and the process arguments returned zero matches — twice, on two
different days.

## How to re-check

```bash
V=$(readlink ~/.local/bin/claude)          # or wherever the launcher points
grep -ac 'Do not call the AgentTool unless the user requested it' "$V"
python3 -c "import json;d=json.load(open('$HOME/.claude.json'));\
print({k:v for k,v in d.get('cachedGrowthBookFeatures',{}).items() if 'heron_brook' in k})"
```

A non-zero count plus an empty flag dictionary means the built-in default is still what
your Opus 5 sessions get.

## What it costs you not to know

You lose subagent delegation silently and pay for it. A session on Opus at high effort
reads the line, concludes it may not spawn helpers, and runs the whole mechanical block —
test suites, builds, bulk renames — itself, at the expensive model's rate. Nothing warns
you; the work simply costs several times what it should, and the session that could have
told you why instead apologises and gets on with it.

The line ends with `unless the user requested it`, and a standing instruction in a file
that loads every session **is** such a request. One paragraph in `~/.claude/CLAUDE.md` or
an always-loaded rules file removes the restriction permanently, which is a far better
answer than granting permission by hand in every conversation.

## See also

- [[rewind-does-not-restore-everything]] — another case of harness behaviour that no
  configuration file describes.
