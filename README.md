# floppy

A session ritual for coding agents: durable, git-committed memory for a
repository, a `start` rite that orients a fresh session, a `wrap` rite that
closes one, and the guards that keep both honest (a file-list gate, a memory
linter, a per-session lock). Ships as a plugin for both Claude Code and
Cursor.

## Requirements

- **A harness that loads plugins** — Claude Code or Cursor. Nothing here is a
  standalone tool: the rites are skills, and the scripts exist to be called by
  them.
- **`bash` and `git`, and a git repository.** Every verb derives its paths from
  the repository root and refuses to run outside one rather than guessing.
- **macOS or Linux.** The suite runs on both in CI, and the macOS job is
  pinned to `/bin/bash` — 3.2.57 — because the scripts are required to work
  there: no `mapfile`, no `declare -A`, no GNU-only flags. Windows is used only
  through WSL, which is a Linux shell as far as these scripts are concerned;
  nothing is tested against a native Windows one.
- Nothing else. No runtime beyond the shell, no network access except the
  `git` calls you can read in the scripts.

## Install

Claude Code:

```
claude plugin marketplace add spscream/ai-floppy
claude plugin install floppy@floppy
```

(equivalently, inside a session: `/plugin marketplace add spscream/ai-floppy`
then `/plugin install floppy@floppy` — the marketplace and the plugin inside
it are both named `floppy`, hence the repeated name)

Cursor, from the repository: Dashboard → Plugins → Add Marketplace → Import
from Repo, pointing at `spscream/ai-floppy`; then Customize (sidebar) → find
`floppy` → Install. This needs Cursor to be able to read the repository, so a
private one has to be reachable by whatever account Cursor is signed in as.

Cursor, from a local checkout — the documented way to try a plugin without a
marketplace at all, and the one to use while developing:

```
mkdir -p ~/.cursor/plugins/local
ln -s /path/to/ai-floppy ~/.cursor/plugins/local/floppy
```

Restart Cursor afterwards. Nothing else is needed: the manifest at
`.cursor-plugin/plugin.json` is found from there, and `skills/` with it.

Cursor can have several projects open at once, and a skill invoked there runs
its shell commands in whichever one the harness happens to land it in — the
skill itself has no say. Every rite names that repository as the first line
of its output (`repo: /path/to/it`), so check it before trusting the rest,
especially before `wrap`'s `commit`, which stages, commits, and pushes.

A cache that never refreshes is the trap to know about: `claude plugin
update` compares version strings, so while `version` in
`.claude-plugin/plugin.json` is unchanged it reports "already at the latest
version" and copies nothing — a plugin installed from a directory marketplace
mid-development can sit on a snapshot days old. Measured on 2026-08-25: the
cached copy had an empty `scripts/`. Bump the version, or uninstall and
install again. `.floppy/run` refuses to resolve into a cache directory with no
`scripts/*.sh` rather than dying later with a confusing "No such file".

The mirror of that trap is `.floppy/run` itself. It is a **copy** in the
consumer repository, not a link, and `plugin update` never touches it: it
travels with that repository's git instead, so on a second machine it can
arrive *ahead* of the plugin rather than behind it. Both directions used to be
mute — a missing verb read as a typo, and a verb the plugin was too old for
died with a bare "No such file or directory" pointing into a cache. Each now
names which side is behind, and every call compares this copy against the
plugin's and says one line on stderr when they differ, because most of the ways
a shim goes stale are silent: a corrected config parser or search order just
keeps doing the old thing. Refresh it with a plain `cp` (the hint says which) —
deliberately not a verb, since a shim old enough to need refreshing is too old
to know the verb that would do it.

Once installed, set the plugin up in a target repository with the `init`
skill (below). If you're developing the plugin itself rather than installing it,
point `AI_FLOPPY_HOME` at your checkout instead of relying on the harness.

## `init`

Run once per repository. Asks two questions — the memory directory
(`.agent-memory` unless you want something else) and the memory's language —
then lays out everything else on its own: copies the shim to `.floppy/run`
(the only file this plugin puts in your repository), writes `.floppy/config`,
creates an empty memory router (`<memory_dir>/MEMORY.md`) and a seeded
current-state file (`docs/statuses/NOW.md`), gitignores the machine-local
memory scope, and points your `AGENTS.md` at `agent-memory`.
Idempotent — safe to run again, changes nothing on a repository already set
up.

## The five skills

The two harnesses name these differently: Claude Code namespaces plugin
skills by plugin name, so `start` is invoked as `floppy:start`; Cursor lists
skills flat, as `/start`, and credits the plugin separately ("Created by
Floppy") instead of folding its name into the skill name. Everywhere else —
including the rest of this document — a skill is named by its bare name,
`start`, since that's the only form true in both harnesses.

- **`init`** — one-time setup, described above.
- **`agent-memory`** — not a rite, has no steps of its own. The
  conventions the other three assume: what a memory note looks like (one
  fact per file, `metadata.evidence` chosen from `measured` / `read` /
  `decided` / `sourced`), the three-level index tree
  (`MEMORY.md` → `<half>/INDEX.md` → `<half>/<group>/INDEX.md`), the
  `quota.lock` ratchet, and which of project / workplace / machine scope a
  fact belongs to.
- **`start`** — orients a fresh session before any edit: read the
  current-state file, identify which half of the memory the task belongs to
  (skip this if the repository has none yet), read that half's guidance and
  memory index, then verify live facts with `bash .floppy/run status`
  instead of trusting the documents.
- **`workstatus`** — a live status check mid-session: git state,
  divergence from the remote, background jobs, memory wiring, the workplace
  memory repository if configured, and the current-state file's freshness.
- **`wrap`** — closes a session: take the lock, select which facts
  are worth a memory note, update the current-state file, name what's left
  unfinished, then `bash .floppy/run check` (read-only: lint + file-list
  guard + diff) followed by `bash .floppy/run commit` (stage, commit, sync,
  release the lock).

## `parity` — when the rite is also kept in another language

A repository may keep the rite twice: these skills in English, and command
files in the language its people actually read (`.claude/commands/wrap.md`
beside `skills/wrap/SKILL.md`). Two copies of a procedure drift, and they
drift silently — what gets lost is not meaning but a **step**.

```
bash .floppy/run parity
```

It compares only what survives translation: the set of
`bash .floppy/run <verb>` calls each file makes, and the sequence of numbered
headings. Nothing about wording, section titles, or length — a translation
legitimately folds a tail section into the last step or adds a
project-specific table, and asserting that would produce red nobody acts on.
The English skill is the source of truth; a divergence means the command
needs the step, not the other way round.

`wrap`'s `check` runs this automatically and goes red on a divergence, so the
drift surfaces when a session closes rather than when someone happens to look.
A repository with no such command files gets no such section — using the
skills directly is the normal case.

The measurement that motivated it, on the project this plugin was extracted
from: the `workstatus` skill documented `bash .floppy/run status --flow` and
when to use it, while the same repository's `/workstatus` command never
mentioned the flag. Nothing was red anywhere.

## `.floppy/config`

Flat `key=value`, one per line, read by the shim (`.floppy/run`) and
exported as `FLOPPY_*` for every script downstream. Everything is optional;
these are the defaults when a key is absent.

| key | default | what it controls |
|---|---|---|
| `memory_dir` | `.agent-memory` | where this repository's durable memory lives |
| `memory_local_dir` | `local` | name of the machine-local scope inside the memory — written on one machine, never committed. Only the name is configurable; the rule is not, and the check that committed memory must never link into it follows this key |
| `memory_repo` | *(unset)* | git URL of the store that holds this project's memory when the code repository cannot; set with `memory_project_key`, then run `bash .floppy/run store` once per machine and worktree |
| `memory_project_key` | *(unset)* | this project's scope inside that store (`projects/<key>/memory`) |
| `memory_repo_dir` | `$HOME/agents_memory` | where that store is (or should be) checked out on this machine |
| `memory_language` | `en` | the language memory notes are written in — a convention read from this file directly, not something any script acts on. Independent of the language a session replies to its human in, which is never configured here |
| `workplace_repo` | *(unset)* | git URL of a workplace-wide private memory repository; both this and `workplace_project_key` must be set to use `bash .floppy/run workplace` |
| `workplace_project_key` | *(unset)* | this project's scope directory (`projects/<key>`) inside the workplace repository |
| `workplace_memory_dir` | `$HOME/agents_memory` | where the workplace repository is (or should be) checked out on this machine |
| `index_chars_max` | `24500` | character ceiling on the memory index, measured off the harness's session loader — it truncates past a limit of its own and never says which section it dropped. A fact about the harness, not this project: the per-corpus caps live in `quota.lock` instead |
| `statuses_now` | `docs/statuses/NOW.md` | the current-state file `start` reads in full and `wrap` keeps up to date |
| `statuses_now_chars_max` | `12000` | character ceiling on the current-state file; `wrap-guard` refuses a commit that pushes it over |
| `watched_dirs` | `docs` | comma-separated directories, besides `memory_dir`, that `wrap` is allowed to commit |
| `watched_files` | `AGENTS.md` | comma-separated single files (exact match, patterns allowed) `wrap` is allowed to commit |
| `commands_dir` | `.claude/commands` | where a repository keeps the rite as command files in its own language, if it keeps them at all; read only by `bash .floppy/run parity` |
| `commit_push` | `auto` | `auto` pulls `--rebase` then pushes after every commit, same as always; `never` skips that whole tail — set this on a repository with no remote configured, since `auto` would fail the pull every time there. A single call can skip just the push with `--no-push` without changing this default |

`workplace_repo` and `workplace_project_key` are deliberately never given a
live default: a repository that never opted in must not silently write into
somebody else's private memory.

## Memory in a repository other than the code's

Some consumers cannot commit agent notes next to the code: a client's checkout
they do not own, or a policy that keeps them apart. The memory then lives in a store repository and the code repository carries only
`.floppy/run` and `.floppy/config`, about 110 lines that review in a minute.

Set it up when initializing:

```
--memory-repo git@example.com:workplace/agents-memory.git --memory-key acme
```

or on an already-initialized repository, by setting `memory_repo` and
`memory_project_key` in `.floppy/config` and running:

```
bash .floppy/run store    # clone or pull, link, ignore, verify a write lands there
bash .floppy/run link     # then the harness's memory directory, as always
```

`store` is per machine and per worktree, idempotent, and refuses rather than
guesses when a real directory sits where the symlink belongs — those notes may
be the only copies. `bash .floppy/run store --check` reports without changing
anything. The step that matters most is the last one it performs: writing
through the link and confirming the file appears in the store. Everything else
can look correct while a write lands somewhere nobody publishes.

Nothing has to be declared in the config. The layout is **derived** from where
`memory_dir` resolves to, because a boolean in a config file would disagree
with the filesystem exactly when it matters — a symlink that failed to be
created would still read as "external" while every write landed in an ignored
directory inside the code repository, where nothing would ever publish it.

From there the rite closes two repositories instead of one:
`guard` asks the store what changed and answers in the paths you typed,
`check` shows the notes going out (this repository's diff is blind to them by
construction), and `commit` commits and pushes both from one file list. A store
that cannot be pushed makes `commit` fail loudly rather than print "session
closed" over unpublished notes, and a `memory_dir` that resolves outside git
altogether is named as such — it works for reading and writing and publishes
nothing.

One cost is worth knowing before choosing this: the memory stops being reviewed
alongside the code, which in the in-repo layout is free.

The half-done state — ignore line added, symlink never created — is the one to
know about, because it is comfortable: notes are written and read normally,
`git status` cannot show them since it was told not to, and nothing publishes
them. `guard` fails on exactly that combination (ignored, but inside this
repository) and names it, and `status` reports the store in its own section so
a machine that skipped the wiring is visible rather than quietly writing into a
directory nobody reads.

## `quota.lock`

A ratchet inside the memory directory — `chars_max` (total character budget),
`note_chars_max` (one note), `pointers_max` (pointers in one index) and
`pointer_line_max` (one pointer line, default 170) — bounding how large the
memory is allowed to get. All four are facts about *this* corpus, which is why
they live with the memory rather than in `.floppy/config`; the one size limit
that is a fact about the harness instead, `index_chars_max`, is in the config
table above. **It is not shipped by this plugin and never copied from one
project to another.** `init` deliberately does not create one: its
numbers have to come from measuring *this* project's own corpus, and a
ceiling copied from a different project is that project's ceiling, which
bounds nothing about the memory actually in front of you. `bash .floppy/run
lint` warns, rather than fails, while it's missing.

## Releases

[CHANGELOG.md](CHANGELOG.md) — what changed, and per release the one thing a
consumer cannot work out for itself: whether the update also requires copying
the shim into the repository again (`.floppy/run` is a copy, and no plugin
update touches it).

## License

MIT — see [LICENSE](LICENSE).
