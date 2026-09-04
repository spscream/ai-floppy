# The knowledge base

Verified findings about **AI coding harnesses** — Claude Code and its neighbours —
written down so the next person does not pay for them again.

## How this differs from `docs/lessons.md`

Both hold things learned the expensive way. The line between them is the audience:

- **`docs/lessons.md`** — what *this plugin* learned. Decisions and failures that shaped
  floppy's own code. A reader who does not use floppy has no use for them.
- **here** — what is true *regardless of floppy*: behaviour of the harness, traps in
  shell and git, how agent memory rots. A reader who does not use floppy is exactly the
  audience.

When a lesson turns out to hold outside this plugin it moves here, and `lessons.md`
stops carrying it. Two did, on 2026-09-05.

## What belongs here

A note is admitted only if **all three** hold:

1. **True outside one repository.** A fact about your own codebase belongs in that
   codebase's agent memory, not here.
2. **Cost real work to learn.** Reading it in the vendor documentation does not count.
   Finding it by disassembling a binary, by a failed run, or by a measurement does.
3. **Checkable.** The note carries a date, the version or environment it was verified
   against, and a concrete way to re-verify it. A claim nobody can re-test is folklore.

Anything failing one of the three is not wrong, it is somebody else's file. Advice
("delegate mechanical work to a cheaper model") fails condition 2: anyone derives it in
a week. A measurement of *what the harness does*, and how you confirmed it, does not.

## Why the checkable clause is load-bearing

A project's own memory is exercised every session. A stale note there gets in the way,
somebody notices, somebody fixes it. **A shared knowledge base has no such pressure.**
Nobody re-reads a note about somebody else's tool until they are already burned by it,
so a wrong entry rots quietly and then actively misleads. Bases like this do not usually
die of emptiness; they die of confident, out-of-date entries.

So every note carries `verified_on` and `recheck`, and

```bash
python3 scripts/knowledge-rot-check.py
```

lists the ones that have aged out. **It reports, it does not gate** — old and wrong are
different things, and only a person who knows the area can tell them apart.

## Layout

```
knowledge/
  README.md          you are here — what belongs, and why
  CONTRIBUTING.md    how to write a note: the contract and its required fields
  LINKS.md           existing practice in this space, with an assessment of each
  _template.md       copy this to start a note
  notes/
    harness/         behaviour of the coding harness itself
    memory/          how agent memory is organised, selected, kept from rotting
    shell/           shell, git and OS traps that reproduce anywhere
    practice/        ways of working that are measured, not merely recommended
```

There is deliberately **no index file**. The page on the documentation site is generated
from the notes' own front matter by `scripts/site-build.sh`, the same way the skills page
is generated from `skills/*/SKILL.md`; a hand-written index would be a second copy of it,
and the two would differ within a month. On GitHub the directory listing is the index.
