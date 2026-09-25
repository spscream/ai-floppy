# Install and init

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

A cached copy with no `scripts/*.sh` file in it is a broken install. Until
0.26.0 the copy in your repository searched for the plugin and refused such a
directory with a clear message. A call that uses the path the harness states
checks nothing first, so the error is `No such file or directory` on
`<plugin>/scripts/run`. The answer is the same: install the plugin again.

### 2. How a command is run

Since 0.26.0 your repository holds no runner. The commands live in the plugin
and are called by path:

```bash
bash <plugin>/scripts/run status
```

`<plugin>` is the plugin directory. The agent is told it: when a harness loads
a floppy skill, it states the base directory of that skill above the skill
text — `Base directory for this skill: <plugin>/skills/workstatus`. The plugin
directory is two levels above that. Measured in Claude Code on 2026-09-22, for
this plugin and for one other.

The dispatcher finds its own directory from its own path, so the call needs no
variable and no file in your repository.

**A repository from before 0.26.0 still works.** The plugin still ships
`shim/run`, and a `.floppy/run` that an older `init` copied there still finds
the plugin and runs the command. Nothing in the plugin calls it any more. To
remove it:

```bash
git rm .floppy/run
```

In the same commit, correct your `AGENTS.md` if it names `.floppy/run` as the
entry point. A later `init` prints a reminder when it sees that line.

**Caution:** a plugin older than the copy is a full stop. A plugin from before
0.14.0 has no dispatcher, so no command runs against it. The message says so
and names the plugin directory it used.

## `init`

Run `init` one time in each repository.

`init` asks two questions:

1. The memory directory. The default is `.agent-memory`.
2. The language of the memory notes.

`init` then does all of these steps:

- writes `.floppy/config`. It is the only file `init` puts there, and the
  only one you commit; `heat` later writes a `.floppy/heat.log` that
  `.gitignore` covers. Your repository carries data, not code.
- creates the memory index `<memory_dir>/MEMORY.md`.
- creates the state file `docs/statuses/NOW.md`.
- adds the private memory scope to `.gitignore`. That path becomes a symlink
  into the private memory repository, and the code repository must not carry
  it. The name is `memory_private_dir`, so it matches what `workplace` creates.
- adds a pointer to `agent-memory` in your `AGENTS.md`.

`init` is idempotent. If the repository is already prepared, a second run
changes nothing.

