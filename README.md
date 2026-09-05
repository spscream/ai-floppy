# floppy

floppy is a plugin for Claude Code and Cursor. It gives a coding agent two
things: a memory that stays in your repository, and two procedures that use
that memory.

- The `start` procedure tells the agent where the last session stopped.
- The `wrap` procedure saves what this session learned.
- Three checks keep the procedures correct: a file-list check, a memory
  linter, and a session lock.

The memory is a set of markdown files. Git holds them with your code. A second
machine gets the memory with one clone.

## Requirements

- **Claude Code or Cursor.** floppy is a plugin. It is not a separate program.
- **`bash`, `git`, and a git repository.** Each command finds its paths from
  the repository root. Outside a repository, each command stops with an error.
  It does not guess.
- **macOS or Linux.** CI runs the tests on both systems. The macOS job uses
  `/bin/bash` version 3.2.57. All scripts must work with that version.
- **Nothing more.** The scripts need no other program. They use the network
  only for the `git` commands that you can read in the source.

For Windows, use WSL. WSL is a Linux shell for these scripts. No test uses a
native Windows shell.

## Install

### Claude Code

```
claude plugin marketplace add spscream/ai-floppy
claude plugin install floppy@floppy
```

You can do the same in a session. Use `/plugin marketplace add
spscream/ai-floppy`, then `/plugin install floppy@floppy`.

The name `floppy` occurs two times in the second command. The marketplace has
this name. The plugin inside the marketplace has the same name.

### Cursor, from the repository

1. Open Dashboard → Plugins → Add Marketplace → Import from Repo.
2. Enter `spscream/ai-floppy`.
3. Open Customize in the sidebar.
4. Find `floppy` and install it.

Cursor must be able to read the repository. If the repository is private, sign
in to Cursor with an account that has access to it.

### Cursor, from a local copy

Use this method during development of the plugin. You can also use it to try
the plugin without a marketplace.

```
mkdir -p ~/.cursor/plugins/local
ln -s /path/to/ai-floppy ~/.cursor/plugins/local/floppy
```

Then start Cursor again. Cursor reads `.cursor-plugin/plugin.json` and the
`skills/` directory from that location.

During development you can also set `AI_FLOPPY_HOME` to your local copy.

After the install, prepare your repository with the `init` skill. See below.

### Cursor and more than one project

Cursor can have more than one project open. A skill runs its shell commands in
one of these projects. The skill does not select the project.

Each procedure prints the repository as the first line of its output
(`repo: /path/to/it`). Read this line first. Read it before `wrap` runs its
`commit` step, because that step stages, commits, and pushes files.

## Two stale copies that cause no error message

### 1. The plugin cache

`claude plugin update` compares version numbers. If the version number is the
same, the command copies no files. It then reports "already at the latest
version".

The result is an installed copy that is some days old. Measured on 2026-08-25:
the cached copy contained an empty `scripts/` directory.

To correct this, do one of these steps:

- Increase the version number in `.claude-plugin/plugin.json`.
- Remove the plugin, then install it again.

`.floppy/run` refuses a cache directory that contains no `scripts/*.sh` file.
This gives a clear message instead of a later "No such file or directory".

### 2. The shim file in your repository

`.floppy/run` is a copy of a file in the plugin. It is not a link. A plugin
update does not change it. Git moves it with your repository.

Thus `.floppy/run` can be older than the plugin. On a second machine it can
also be newer than the plugin.

Since 0.14.0 this matters much less. The file does one thing: it finds the
plugin and gives the call to it. The commands and the configuration keys are
in the plugin. A new command, a new key or a new default reaches your
repository with a plugin update alone. You do not copy the file again for them.

One thing still travels in the copy: the search for the plugin. If that search
changes, an old copy can fail to find a plugin that is there. This failure is
loud. It says `floppy plugin not found` and names the install commands.

At each call, `.floppy/run` compares itself with the file in the plugin. If the
two files are different, it prints one line on stderr. That line contains the
`cp` command that corrects the copy.

The correction is a `cp` command, not a floppy command. This is deliberate. A
shim file that is old enough to need a correction does not know the new
commands.

**Caution:** a plugin older than the copy is now a full stop, not a partial
one. A plugin from before 0.14.0 has no dispatcher, so no command runs against
it. The message says so and names the plugin directory it used.

## `init`

Run `init` one time in each repository.

`init` asks two questions:

1. The memory directory. The default is `.agent-memory`.
2. The language of the memory notes.

`init` then does all of these steps:

- copies the shim file to `.floppy/run`. This is the only file that the plugin
  puts in your repository.
- writes `.floppy/config`.
- creates the memory index `<memory_dir>/MEMORY.md`.
- creates the state file `docs/statuses/NOW.md`.
- adds the private memory scope to `.gitignore`. That path becomes a symlink
  into the private memory repository, and the code repository must not carry
  it. The name is `memory_private_dir`, so it matches what `workplace` creates.
- adds a pointer to `agent-memory` in your `AGENTS.md`.

`init` is idempotent. If the repository is already prepared, a second run
changes nothing.

## The five skills

Claude Code and Cursor show the names differently. Claude Code adds the plugin
name, for example `floppy:start`. Cursor shows the short name, for example
`/start`, and shows the plugin as "Created by Floppy". This document uses the
short name. Only the short name is correct in both applications.

- **`init`** — the setup. See above.
- **`agent-memory`** — the rules for the memory. This skill has no steps. The
  other skills obey these rules. One note contains one fact. Each note has the
  field `metadata.evidence` with one of these values: `measured`, `read`,
  `decided`, `sourced`. The index has three levels: `MEMORY.md`, then
  `<half>/INDEX.md`, then `<half>/<group>/INDEX.md`. The file `quota.lock`
  holds the size limits. Each fact belongs to one scope: project, workplace, or
  machine.
- **`start`** — prepares a new session, before the first edit. The agent reads
  the state file. The agent then finds the half of the memory for this task,
  and reads the guidance and the index of that half. If the repository has no
  memory yet, the agent omits this step. The agent then runs
  `bash .floppy/run status`, because live facts are more reliable than the
  documents.
- **`workstatus`** — reports the state during a session: git state, difference
  from the remote, background jobs, memory configuration, the workplace memory
  repository, and the age of the state file.
- **`wrap`** — closes a session. The agent takes the lock. The agent selects
  the facts that are worth a note, updates the state file, and records the
  unfinished work. The agent then runs `bash .floppy/run check`, which changes
  nothing and shows the lint result, the file-list check, and the diff. Last,
  the agent runs `bash .floppy/run commit`, which stages, commits, pushes, and
  releases the lock.

## `.floppy/config`

The file contains one `key=value` line for each setting. The shim file
(`.floppy/run`) reads it, and exports each value as a `FLOPPY_*` variable for
the scripts.

All keys are optional. The table shows the value that each key has if the file
does not contain it.

| key | default | what it controls |
|---|---|---|
| `memory_dir` | `.agent-memory` | the directory of the memory of this repository |
| `memory_private_dir` | `private` | the name of the private scope in the memory: facts about this project that the code repository must not carry, such as somebody else's checkout or an access note. The workplace repository holds them, so **other machines do read them**. Facts about one machine go to `machines/<name>/` of that repository instead. Only the name is a setting; the rule is not — committed memory must not link into this scope, and the check uses this key |
| `public_repo` | *(not set)* | the git URL of the repository that holds this project's **public** memory when the code repository cannot. Set `project_key` also. Then run `bash .floppy/run store` one time for each machine and each worktree |
| `private_repo` | *(not set)* | the git URL of the repository that holds this project's **private** memory: facts the team must not get. `bash .floppy/run workplace` wires it |
| `machine_key` | *(not set)* | the name of this machine in the memory repositories, chosen by you. `hostname` is not used: on one of the author's machines it is `WIN-GVR0V5UPOD7`. Only needed for a note that is true on one machine |
| `workplace_key` | *(not set)* | the name of this workplace, when one private repository serves several of them. Only needed for a note that is true at one workplace |
| `project_key` | *(not set)* | the name of this project in every memory repository it uses, and the name of its directory in `agents_memory_dir`. The scopes are `public/projects/<key>` (in `public_repo`) and `private/projects/<key>` (in `private_repo`) |
| `memory_project_key` | *(the value of `project_key`)* | use a different key in `public_repo` only. Needed when the same project has two names in two repositories |
| `workplace_project_key` | *(the value of `project_key`)* | the same, for `private_repo` |
| `agents_memory_dir` | `$HOME/agents_memory` | holds one directory for each project, and the clones in `.clones/`. Each repository URL gets one clone. The name of the clone comes from the URL. floppy derives it; you do not set it. Two different repositories thus cannot use one clone directory. A clone from an earlier layout — under the parent directly, or at the parent itself — is used as it is, but only if its `origin` is the configured URL. See the example above |
| `memory_repo_dir` | *(derived)* | replaces the derived checkout path of `public_repo` on this machine. Set it only if that checkout cannot be below the parent directory |
| `workplace_memory_dir` | *(derived)* | the same replacement, for `private_repo` |
| `memory_language` | `en` | the language of the memory notes. No script uses this key. A session reads it from this file. It does not control the language of the answers to a human |
| `index_chars_max` | `24500` | the maximum number of characters in the memory index. The value comes from the session loader of the agent application. That loader removes text above a limit and does not report the removed section. This is a fact about the application, not about your project. The limits for the corpus are in `quota.lock` |
| `statuses_now` | `docs/statuses/NOW.md` | the state file. `start` reads all of it. `wrap` keeps it correct |
| `statuses_now_chars_max` | `12000` | the maximum number of characters in the state file. `wrap-guard` refuses a commit above this limit |
| `statuses_regress_marks` | *(empty)* | the words that mark a regression in the direction cell of a trend table, in your own language. Use a comma between them. `wrap-guard` then refuses to delete only the rows carrying one of these words. While the key is empty, no trend row may be deleted at all — safe, but it makes a rewritten file grow like an append-only one, because a one-time "done" row can never leave |
| `watched_dirs` | `docs` | the directories, in addition to `memory_dir`, that `wrap` can commit. Use a comma between the names |
| `watched_files` | `AGENTS.md` | the single files that `wrap` can commit. Patterns are permitted. Use a comma between the names |
| `commit_push` | `auto` | the action after each commit. `auto` runs `git pull --rebase`, then pushes. `never` omits both. Use `never` if the repository has no remote, because `auto` fails there. To omit the push one time only, use `--no-push` |

`private_repo` and `workplace_project_key` have no default value. This is
deliberate. With a default, a repository could write into the private memory of
a different person.

### Where the checkouts are

`agents_memory_dir` contains two things: one directory for each project, and a
hidden `.clones/` with one clone for each memory repository.

You open the project directories. floppy makes the clones.

An example. The configuration of one project is four lines:

```
project_key=acme
public_repo=git@example.com:team/notes-store.git
private_repo=git@example.com:workplace/agents-memory.git
agents_memory_dir=$HOME/agents_memory
```

The result on disk is:

```
~/agents_memory/
   acme/                      <- the project, named by project_key
      shared  -> ../.clones/notes-store/public/projects/acme
      private -> ../.clones/agents-memory/private/projects/acme
   .clones/
      notes-store/            <- clone of public_repo
      agents-memory/          <- clone of private_repo
```

`shared` and `private` are symlinks. floppy makes them on each machine, and no
repository contains them. They are relative, so you can move
`agents_memory_dir` as one directory.

`<memory_dir>` in your repository points at `~/agents_memory/acme/shared`, and
`<memory_dir>/private` points at `~/agents_memory/acme/private`. These two
addresses stay the same if a repository URL changes.

A second project uses the same two repositories in the same way. It gets its
own directory `~/agents_memory/<other key>/`, and its own scopes
`public/projects/<other key>` and `private/projects/<other key>` inside the same
two clones. There is one clone for each repository, never one for each project.

If `public_repo` and `private_repo` hold the same URL, there is one clone,
and both scopes are in it, beside each other.

### The scope names changed in 0.5.0

The scopes are now two directories beside each other:

```
public/projects/<key>      in public_repo
private/projects/<key>     in private_repo
```

Below either of them, a note that is **not** true everywhere goes one level
deeper: `workplaces/<workplace_key>/` or `machines/<machine_key>/`. A note that
is true everywhere sits directly in the scope, which is the common case.

Before 0.5.0 they were `projects/<key>/memory` and `projects/<key>` itself. The
second one contained the first whenever one repository served both, so the
private notes and the shared memory were in one tree. In 0.5.0 and 0.5.1 the
second one was `projects/<key>/local`; 0.6.0 renamed it to `private`, because
that name says "machine-local" and the scope is nothing of the sort. 0.7.0
moved the audience to a namespace directory at the top and dropped the leaf
that repeated it — see [docs/memory-model.md](docs/memory-model.md). It is private to the
project and every machine of the workplace reads it. Facts about ONE machine
go to `machines/<name>/` of the workplace repository.

If your repository still uses the old names, the verb stops and prints the
`git mv` commands. It does not move the notes itself. Two reasons: these notes
can be the only copies, and a move done on one machine while the other machine
still writes the old path forks the memory with no message anywhere. Update
every machine first, then move the scopes one time.

### Two memory repositories on one machine

A project can use `store` and `workplace` together. `store` moves all of the
memory into a different repository. `workplace` attaches a shared scope at
`<memory_dir>/private`. These can be two different repositories.

Before version 0.4.2, each of the two had its own directory key, and the two
keys had the same default value. If you set both keys, they gave one directory.
No message told you.

Measured on 2026-08-25, in that condition:

- The first verb cloned its repository into the directory.
- The second verb found a `.git` directory there, and did not clone.
- The second verb did not compare the remote with the configured URL.
- The second verb reported "ok a write through the link lands in the workplace
  repository".
- The notes went into the store repository instead. `commit` would have pushed
  them there.

Two changes prevent this condition:

- The checkout directory comes from the URL. Thus two URLs cannot give one
  directory.
- If a checkout is already there, the verb compares its `origin` with the
  configured URL. If the two are different, the verb stops, and shows both.

The second change also finds a different problem: an unrelated repository at
that path.

You do not need to move anything. If a checkout is already at the parent
directory, floppy continues to use it, and the verb tells you so.

## Memory in a different repository

Some repositories cannot hold agent notes with the code. Examples are a
customer checkout that you do not own, and a policy that keeps the two apart.

In that condition, the memory goes into a store repository. Your code
repository keeps two files only: `.floppy/run` and `.floppy/config`. Together
they are approximately 110 lines. A review of them takes one minute.

To set this up during `init`, use the flags:

```
--memory-repo git@example.com:workplace/agents-memory.git --memory-key acme
```

To set it up later, put `public_repo` and `project_key` in `.floppy/config`.
Then run:

```
bash .floppy/run store    # clone or pull, link, ignore, and verify a write
bash .floppy/run link     # then the memory directory of the agent application
```

`store` runs one time for each machine and each worktree. It is idempotent. To
see the result without a change, run `bash .floppy/run store --check`.

If a directory is in the position of the symbolic link, `store` stops. It does
not delete the directory. Those notes can be the only copies.

The last step of `store` is the important one. It writes a file through the
link, and confirms that the file is in the store. All other steps can look
correct while a write goes to a location that nobody publishes.

The configuration contains no key for "external" or "internal". The layout
comes from the location of `memory_dir`. A key in a file could disagree with
the file system. It would disagree exactly in the dangerous condition: a
symbolic link that was not created, and notes that go into an ignored directory
in the code repository.

With a store, the `wrap` procedure closes two repositories:

- `guard` asks the store for its changes, and reports them with the paths that
  you use.
- `check` shows the notes that go out. The diff of the code repository cannot
  show them.
- `commit` commits and pushes both repositories from one file list. If the
  store refuses the push, `commit` fails. It does not report "session closed"
  above notes that are not published.
- If `memory_dir` is outside git, `status` reports this condition. The memory
  then works for reading and writing, but nothing publishes it.

Know one disadvantage before you select this layout. Nobody reviews the memory
with the code. In the in-repository layout, that review is free.

**Caution:** the incomplete condition is comfortable, and thus dangerous. The
ignore line is present, but the symbolic link is absent. Notes are written and
read correctly. `git status` cannot show them, because it was told to ignore
them. Nothing publishes them. `guard` fails on this combination, and names it.
`status` reports the store in a section of its own, and thus shows a machine
that omitted the setup.

## `quota.lock`

This file is in the memory directory. It contains four limits:

- `chars_max` — the total number of characters.
- `note_chars_max` — the characters in one note.
- `pointers_max` — the pointers in one index.
- `pointer_line_max` — the characters in one pointer line. The default is 170.

All four are facts about **this** corpus. Thus they stay with the memory, and
not in `.floppy/config`. One size limit is a fact about the agent application
instead: `index_chars_max`, in the table above.

The plugin does not supply a `quota.lock` file, and the file is **never copied**
from one project to a different project. Its numbers must come from a
measurement of the corpus of this project. A limit from a different project
describes that project, and controls nothing here.

`init` therefore creates it in exactly one case: the repository **already had
notes** when floppy arrived. Then there is a corpus to measure, and the numbers
are this project's own — `chars_max` at the measured total plus a tenth,
`pointers_max` at the longest index found, and any note already over
`note_chars_max` listed in `grandfathered` rather than failing the first run. On
an empty memory `init` creates nothing: there is nothing to measure, and a
ceiling invented for an empty directory bounds nothing.

Seeding at adoption is what a ratchet is for. It does not say how big this
memory should be — it says how big it was on the day floppy arrived, so that
every increase afterwards is a deliberate act visible in a diff. A project
arriving already over some imported default would go red on its first run, and a
linter that is red on day one is a linter that gets switched off.

`init` also prints what `lint` makes of an inherited corpus, grouped by kind with
a count in front of each: ninety-four identical lines are the raw material of a
report, not a report. It rewrites no note.

While the file is absent, `bash .floppy/run lint` gives a warning. It does not
fail.

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
