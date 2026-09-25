---
name: init
description: Lay the floppy memory out in this repository — write .floppy/config, create the memory skeleton, gitignore the local scope, and point AGENTS.md at agent-memory. Idempotent, safe to run again. Use once per repository, when setting the plugin up for the first time, or when the user asks to init, set up, or bootstrap floppy here.
---

# Init

A thin wrapper. All the work is in `scripts/init.sh`; this skill exists to
ask the two questions the script cannot answer for itself, then run it.

## 1. Ask

Ask the human, in one short message, for:

- **the memory directory** — where this repository's durable memory lives.
  Suggest `.agent-memory` if they have no reason to want something else.
- **the memory language** — the language notes get written in. This is
  independent of the language the agent replies in (see `agent-memory`);
  suggest `en` if they have no preference.

Do not guess either value silently — a wrong memory directory is annoying to
move later, and this only needs one short question.

## 2. Run the script

Before running it — this is the writing half, it lays files into `--repo .`
— confirm that directory is the repository the human meant to set up.
Several projects can be open in the same harness at once (Cursor especially),
and the shell a skill runs in is not necessarily the one the human was
talking about. One line naming it is enough.

The script is in the plugin, which is where this skill itself came from. The
harness states this skill's own base directory when it loads it — `Base
directory for this skill: <plugin>/skills/init` — so the plugin root is two
directories above that, and the script is `<plugin>/scripts/init.sh`. Write
that absolute path:

```bash
bash <plugin>/scripts/init.sh \
  --repo . --memory-dir <their answer> --language <their answer>
```

Until 0.26.0 this step carried a 33-line hand copy of the shim's six-way
search for the plugin, on the grounds that `init` runs before the repository
has anything that could do the finding. Measured 2026-09-22: the harness hands
the path over in-band at skill load, so the root is two directories up from a
string that is already on screen — no cache glob, no `sort -V`, no Cursor SHA
ordering to get right. The copy had been wrong once before it was removed
(four branches of six, for as long as it had existed; found 2026-09-09).

If the base directory is genuinely not stated — a harness that does not print
it — do not guess a cache path: say so and stop. `$CLAUDE_PLUGIN_ROOT` and
`$CURSOR_PLUGIN_ROOT` are worth trying first, and a checkout the human can
name is worth asking for; both beat a search whose failure mode is running the
wrong copy of the plugin.

## 3. Report

Read the script's own output back in short form: what was created, and what
was already there and left untouched (the script says so per file). Running
this again later, on the same repository, changes nothing — that's by
design, not a limitation worth apologizing for.

Point out explicitly that `quota.lock` was **not** created — see
`agent-memory` for why, and mention it will need a real measurement once
there is a corpus worth measuring, not before.
