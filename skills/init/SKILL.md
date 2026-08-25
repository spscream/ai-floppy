---
name: init
description: Lay the floppy memory out in this repository — copy the shim to .floppy/run, write .floppy/config, create the memory skeleton, gitignore the local scope, and point AGENTS.md at floppy:agent-memory. Idempotent, safe to run again. Use once per repository, when setting the plugin up for the first time, or when the user asks to init, set up, or bootstrap floppy here.
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

Locate the plugin root from `CLAUDE_PLUGIN_ROOT` (set by the harness while
this skill runs), or `AI_FLOPPY_HOME` during development, and run:

```bash
bash "${CLAUDE_PLUGIN_ROOT:-$AI_FLOPPY_HOME}/scripts/init.sh" \
  --repo . --memory-dir <their answer> --language <their answer>
```

This can only run this way — through the script directly, not through
`.floppy/run` — because `.floppy/run` does not exist yet in this repository;
creating it is the first thing the script does.

## 3. Report

Read the script's own output back in short form: what was created, and what
was already there and left untouched (the script says so per file). Running
this again later, on the same repository, changes nothing — that's by
design, not a limitation worth apologizing for.

Point out explicitly that `quota.lock` was **not** created — see
`agent-memory` for why, and mention it will need a real measurement once
there is a corpus worth measuring, not before.
