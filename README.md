# floppy

A session ritual for coding agents: durable, git-committed memory for a
repository, a `start` rite that orients a fresh session, a `wrap` rite that
closes one, and the guards that keep both honest (a file-list gate, a memory
linter, a per-session lock). Ships as a plugin for both Claude Code and
Cursor.

## Install

Claude Code:

```
claude plugin marketplace add spscream/ai_floppy
claude plugin install floppy@floppy
```

(equivalently, inside a session: `/plugin marketplace add spscream/ai_floppy`
then `/plugin install floppy@floppy` — the marketplace and the plugin inside
it are both named `floppy`, hence the repeated name)

Cursor, from the repository: Dashboard → Plugins → Add Marketplace → Import
from Repo, pointing at `spscream/ai_floppy`; then Customize (sidebar) → find
`floppy` → Install. This needs Cursor to be able to read the repository, so a
private one has to be reachable by whatever account Cursor is signed in as.

Cursor, from a local checkout — the documented way to try a plugin without a
marketplace at all, and the one to use while developing:

```
mkdir -p ~/.cursor/plugins/local
ln -s /path/to/ai_floppy ~/.cursor/plugins/local/floppy
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
| `memory_language` | `en` | the language memory notes are written in — a convention read from this file directly, not something any script acts on. Independent of the language a session replies to its human in, which is never configured here |
| `workplace_repo` | *(unset)* | git URL of a workplace-wide private memory repository; both this and `workplace_project_key` must be set to use `bash .floppy/run workplace` |
| `workplace_project_key` | *(unset)* | this project's scope directory (`projects/<key>`) inside the workplace repository |
| `workplace_memory_dir` | `$HOME/agents_memory` | where the workplace repository is (or should be) checked out on this machine |
| `statuses_now` | `docs/statuses/NOW.md` | the current-state file `start` reads in full and `wrap` keeps up to date |
| `statuses_now_chars_max` | `12000` | character ceiling on the current-state file; `wrap-guard` refuses a commit that pushes it over |
| `watched_dirs` | `docs` | comma-separated directories, besides `memory_dir`, that `wrap` is allowed to commit |
| `watched_files` | `AGENTS.md` | comma-separated single files (exact match, patterns allowed) `wrap` is allowed to commit |
| `commands_dir` | `.claude/commands` | where a repository keeps the rite as command files in its own language, if it keeps them at all; read only by `bash .floppy/run parity` |
| `commit_push` | `auto` | `auto` pulls `--rebase` then pushes after every commit, same as always; `never` skips that whole tail — set this on a repository with no remote configured, since `auto` would fail the pull every time there. A single call can skip just the push with `--no-push` without changing this default |

`workplace_repo` and `workplace_project_key` are deliberately never given a
live default: a repository that never opted in must not silently write into
somebody else's private memory.

## `quota.lock`

A ratchet inside the memory directory — a total character budget, a
per-note cap, a pointers-per-index cap — that bounds how large the memory is
allowed to get. **It is not shipped by this plugin and never copied from one
project to another.** `init` deliberately does not create one: its
numbers have to come from measuring *this* project's own corpus, and a
ceiling copied from a different project is that project's ceiling, which
bounds nothing about the memory actually in front of you. `bash .floppy/run
lint` warns, rather than fails, while it's missing.

## License

MIT — see [LICENSE](LICENSE).
