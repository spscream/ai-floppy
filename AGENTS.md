
## Changes land through pull requests

`main` is protected and refuses a direct push — from every session, including
the one that owns this repository. If your push comes back with `GH013:
Repository rule violations found`, nothing is wrong: branch, push the branch,
open a pull request.

```bash
git switch -c <topic>
git push -u origin HEAD
gh pr create --fill
```

No approval is required — a PR here can be self-merged. What the rule buys is
not a second person, it is that `tests.yml` runs on `pull_request`, so both
platforms are checked **before** the change is on `main`, and that a change
arriving from outside the session working on this repository is visible as a
change rather than as history.

That last case is ordinary here, not an incident. `knowledge/` is a
cross-project base by design: an agent working in another repository that
learns something worth keeping is *expected* to contribute a note. It is also
the surface with the least automation behind it — most notes carry nothing
executable, so `knowledge-recheck.py` cannot see them, and `knowledge-rot-check.py`
measures age, which says nothing about a claim that was wrong on the day it was
written. Review is the only check those notes get.

## The cross-project memory layer here is `common/`, not `basic-memory`

`.claude/settings.json` denies the `basic-memory` MCP server in this repository,
and `deniedMcpServers` keeps it from connecting at all. This **overrides the
global rule that names that server as the cross-project memory layer**, for this
repository only — the server stays connected and unchanged everywhere else.

Where a cross-project fact goes here instead:

- **`knowledge/notes/`** — a verified finding about harnesses, shell or git that
  passes the three admission criteria in `knowledge/README.md`. Public, English,
  published to the site, reviewed through a pull request.
- **`.agent-memory/common/private`** — cross-project but personal: a measured
  setting, an evaluation of an external tool, a trick that lives outside any
  checkout.

Why, in one line: `basic-memory`'s store is local-only and not under git, so it
does not travel between machines — which is the one thing a cross-project layer
exists for — while `common/` is wired by `store`/`workplace` and read by `start`.
The full argument, with what moved and when to revisit, is in the memory note
`basic-memory-is-off-in-this-repository`.

## Which half of the memory a task belongs to

`MEMORY.md` is a router: two always-read notes and one link per half. `start`
opens the half the task belongs to and leaves the other two closed, so the
routing has to be answerable before reading any of them. It is written here
because which words point where is this repository's knowledge, not the
plugin's.

| the task is about | half | words that route to it |
|---|---|---|
| notes, scopes, stores, `quota.lock`, the status files, another project's memory, whether any of it pays | `memory/` | note, index, scope, store, `common/`, `NOW.md`, recall, benchmark |
| `scripts/`, `shim/`, `skills/`, `tests/`, the generated site, `knowledge/` | `product/` | verb, shim, guard, test, suite, bash 3.2, site, search, lint |
| branches, pull requests, the protected `main`, the workflows that run on them | `delivery/` | branch, push, PR, merge, release, workflow, CI |

Split on 2026-09-09 from one flat index that had reached `pointers_max=25`.
The frozen rule is that a full index splits and the number stays, so if a half
fills up it splits again into sub-indexes — three levels is the floor of the
tree, not a budget to raise.

Two things the table cannot decide, and both go to `memory/`: a fact about the
memory *of another project* (this repository's product is that memory, so its
own memory is where the subject is studied), and a fact that is not about this
project at all — the latter belongs in `common/`, which no index links to and
`start` reaches by name.

<!-- floppy:agents-section -->
## Agent memory

This repository uses the `floppy` plugin for its session ritual and its
durable memory. The entry point is `.floppy/run` — see `agent-memory`
for what a note looks like and how the memory is laid out, and
`start` / `workstatus` / `wrap` for the three rites
built on top of it. Settings live in `.floppy/config`; the memory itself is
under `.agent-memory`.
