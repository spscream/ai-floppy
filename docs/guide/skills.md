# The six skills


Claude Code and Cursor show the names differently. Claude Code adds the plugin
name, for example `floppy:start`. Cursor shows the short name, for example
`/start`, and shows the plugin as "Created by Floppy". This document uses the
short name. Only the short name is correct in both applications.

- **`init`** — the setup. See [Install & init](install.md).
- **`agent-memory`** — the rules for the memory. This skill has no steps. The
  other skills obey these rules. One note contains one fact. Each note has the
  field `metadata.evidence` with one of these values: `measured`, `read`,
  `decided`, `sourced`. The index has three levels: `MEMORY.md`, then
  `<half>/INDEX.md`, then `<half>/<group>/INDEX.md`. The file `quota.lock`
  holds the size limits. Each fact belongs to one scope: project,
  cross-project, workplace, or machine. A fact true for more than one project
  goes to the cross-project scope, `common/`, which the memory links once per
  audience. A note is written at the moment the fact appears, not collected at
  the end of the session.
- **`start`** — prepares a new session, before the first edit. The agent reads
  the state file. The agent then finds the half of the memory for this task,
  and reads the guidance and the index of that half. If the repository has no
  memory yet, the agent omits this step. The agent then runs
  `bash .floppy/run status`, because live facts are more reliable than the
  documents.
- **`workstatus`** — reports the state during a session: git state, difference
  from the remote, background jobs, memory configuration, the workplace memory
  repository, and the age of the state file.
- **`wrap`** — closes a session. The agent takes the lock. Most facts are notes
  already, written when they appeared; here the agent adds only what is left,
  updates the state file, and records the unfinished work. The agent then runs
  `bash .floppy/run check`, which changes nothing and shows the lint result,
  the file-list check, and the diff. Last, the agent runs
  `bash .floppy/run commit`, which stages, commits, pushes, and releases the
  lock.
- **`consolidate`** — merges and prunes the memory when a size warning fires,
  or before a limit in `quota.lock` is raised. The agent reads one half of
  the memory, proposes merges, rewrites, and deletions, each with its reason,
  and applies only what the human approves. If the memory then fits its
  limit, the limit stays where it is. An empty result is a valid result: it
  is what the raise commit then records.


## What each skill says about itself

The block below is generated at build time from each `skills/<name>/SKILL.md`'s
own `description` field — the same text the harness reads when it decides
whether a skill applies. This page therefore cannot describe a skill
differently from the way the agent sees it.

<!-- floppy:generated skills-list -->
