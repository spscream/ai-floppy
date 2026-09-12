# floppy

[![tests](https://github.com/spscream/ai-floppy/actions/workflows/tests.yml/badge.svg)](https://github.com/spscream/ai-floppy/actions/workflows/tests.yml)
[![version](https://img.shields.io/github/v/tag/spscream/ai-floppy?label=version)](CHANGELOG.md)
[![license](https://img.shields.io/github/license/spscream/ai-floppy)](https://github.com/spscream/ai-floppy/blob/main/LICENSE)

*[Русская версия](README.ru.md)*

floppy is a plugin for Claude Code and Cursor. It gives a coding agent two
things: a memory that stays in your repository, and two procedures that use
that memory.

- The `start` procedure tells the agent where the last session stopped.
- The `wrap` procedure saves what this session learned.
- Three checks keep the procedures correct: a file-list check, a memory
  linter, and a session lock.

The memory is a set of markdown files. Git holds them with your code. A second
machine gets the memory with one clone.

## Install

```
claude plugin marketplace add spscream/ai-floppy
claude plugin install floppy@floppy
```

Cursor, a local checkout, and what to do when an update copies nothing:
[Install and init](docs/guide/install.md).

## Then

Run `init` once in each repository. It writes `.floppy/run` and
`.floppy/config`, creates the memory index and the state file, and points your
`AGENTS.md` at the conventions.

Five skills: `init`, `agent-memory`, `start`, `workstatus`, `wrap`.
What each one does: [The five skills](docs/guide/skills.md).

## Documentation

- [Install and init](docs/guide/install.md) — both harnesses, and the two
  stale copies that cause no error message
- [Config reference](docs/guide/config.md) — every `.floppy/config` key, the
  checkout layout, memory in a separate repository, `quota.lock`
- [The five skills](docs/guide/skills.md)
- [The memory model](docs/memory-model.md) — two namespaces, two axes
- [Lessons](docs/lessons.md) — what this plugin learned the expensive way
- [The knowledge base](knowledge/README.md) — findings about the harness
  itself, true whether or not you use floppy

## The memory model

[docs/memory-model.md](docs/memory-model.md) — the design the paths are moving
towards: two namespaces (who may read it), and two independent axes below them
(what it is about, where it is true). **It is a design, not the current state.**
Read it before changing any path in the scripts. It exists because the layout
was renamed three times in one day, and each rename corrected a model that
nobody had written down.

[docs/lessons.md](docs/lessons.md) — what those renames cost, and why the
external layout is derived from the filesystem instead of a config flag. These
are lessons about *floppy*.

## The knowledge base

[knowledge/README.md](knowledge/README.md) — findings about the coding harness
itself, true whether or not you use floppy: why a linter walked an empty tree
and stayed green, why a suite hangs on an open stdin, where the ban on
subagents actually comes from, what `/rewind` does not restore.

It is separate from `docs/lessons.md` by audience, and it carries a contract
that file does not: every note names the date and environment it was verified
against and a command to re-check it, because nobody re-reads a note about
somebody else's tool until it has already burned them.
`python3 scripts/knowledge-rot-check.py` lists the ones that have aged out — it
reports, it does not gate.

## Releases

See [CHANGELOG.md](CHANGELOG.md). For each release it answers one question that
you cannot answer without it: does this update also need a new copy of the shim
file? `.floppy/run` is a copy, and no plugin update changes it.

## License

MIT. See [LICENSE](LICENSE).
