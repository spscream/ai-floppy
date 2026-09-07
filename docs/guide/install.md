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

