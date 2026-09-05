
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

<!-- floppy:agents-section -->
## Agent memory

This repository uses the `floppy` plugin for its session ritual and its
durable memory. The entry point is `.floppy/run` — see `agent-memory`
for what a note looks like and how the memory is laid out, and
`start` / `workstatus` / `wrap` for the three rites
built on top of it. Settings live in `.floppy/config`; the memory itself is
under `.agent-memory`.
