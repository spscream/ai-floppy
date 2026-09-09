# Config reference


The file contains one `key=value` line for each setting. The shim file
(`.floppy/run`) reads it, and exports each value as a `FLOPPY_*` variable for
the scripts.

All keys are optional. The table shows the value that each key has if the file
does not contain it.

| key | default | what it controls |
|---|---|---|
| `memory_dir` | `.agent-memory` | the directory of the memory of this repository |
| `memory_private_dir` | `private` | the name of the private scope in the memory: facts about this project that the code repository must not carry, such as somebody else's checkout or an access note. The workplace repository holds them, so **other machines do read them**. Facts about one machine go to `machines/<name>/` of that repository instead. Only the name is a setting; the rule is not — committed memory must not link into this scope, and the check uses this key. The same rule covers `common/`, whose name is fixed rather than configurable: it is written into the store paths themselves, and a name settable in one of the two places would be a name that drifts |
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
| `note_stale_days` | `180` | how long a note's `metadata.as_of` may stand before `lint` names it. It warns and never fails: old and wrong are different things, and only a person who knows the area can tell them apart. Notes with no `as_of` are counted, not listed, so the field can arrive into a corpus that already exists. Lower it if your memory is mostly about a fast-moving dependency. The knowledge base in this repository ages a note after 90 days, but by a different mechanism: `scripts/knowledge-rot-check.py --days`, which never reads this file |
| `statuses_now` | `docs/statuses/NOW.md` | the state file. `start` reads all of it. `wrap` keeps it correct |
| `statuses_now_chars_max` | `12000` | the maximum number of characters in the state file. `wrap-guard` refuses a commit above this limit |
| `statuses_personal` | `<memory_dir>/<memory_private_dir>/machines/<machine>/NOW.md` | the second state file: one person's thread of work on one machine — what is half-done, where to resume. `start` reads it when it exists, `wrap` writes it. It is inside the memory, so `commit` sends it to the private store and never to this repository. The machine part comes from `machine_key`, or from `hostname` when that is not set. Leave the key unset unless the derived path is wrong: writing it here puts one machine's path into a file every machine reads. It has no character limit, unlike `statuses_now`, because only the session that wrote it reads it |
| `statuses_regress_marks` | *(empty)* | the words that mark a regression in the direction cell of a trend table, in your own language. Use a comma between them. `wrap-guard` then refuses to delete only the rows carrying one of these words. While the key is empty, no trend row may be deleted at all — safe, but it makes a rewritten file grow like an append-only one, because a one-time "done" row can never leave |
| `watched_dirs` | `docs` | the directories, in addition to `memory_dir`, that `wrap` can commit. Use a comma between the names |
| `watched_files` | `AGENTS.md` | the single files that `wrap` can commit. Patterns are permitted. Use a comma between the names |
| `commit_push` | `auto` | the action after each commit. `auto` runs `git pull --rebase`, then pushes. `never` omits both. Use `never` if the repository has no remote, because `auto` fails there. To omit the push one time only, use `--no-push` |

`private_repo` and `workplace_project_key` have no default value. This is
deliberate. With a default, a repository could write into the private memory of
a different person.

## Where the checkouts are

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

## Where the scopes are

The scopes are two directories beside each other:

```
public/projects/<key>      in public_repo
private/projects/<key>     in private_repo
public/common              in public_repo    — about no single project
private/common             in private_repo   — about no single project
```

Below any of them, a note that is **not** true everywhere goes one level
deeper: `workplaces/<workplace_key>/` or `machines/<machine_key>/`. A note that
is true everywhere sits directly in the scope, which is the common case.

The two `common` scopes are the sibling of `projects/<key>`, for facts that are
about no single project — an outside tool that was evaluated, a shell trap,
what one machine has installed. `store` and `workplace` wire them beside the
project's own, as `<memory_dir>/common/shared` and `<memory_dir>/common/private`;
a machine that ran only one of the two verbs gets only that half. Nothing in
the committed index may point into them, for the same reason nothing may point
into the private scope: the link is per machine, so it is dead for anyone who
has not wired it. `start` names the scope instead, and `lint` fails on such a
link.

The private scope is private to the project, and every machine of the workplace
reads it — see [docs/memory-model.md](../memory-model.md). Facts about ONE
machine go to `machines/<name>/` of the workplace repository.

These names are the current set and not the first. What the renames before
them cost is in [the lessons](../lessons.md).

If your repository still uses the old names, the verb stops and prints the
`git mv` commands. It does not move the notes itself. Two reasons: these notes
can be the only copies, and a move done on one machine while the other machine
still writes the old path forks the memory with no message anywhere. Update
every machine first, then move the scopes one time.

## Two memory repositories on one machine

A project can use `store` and `workplace` together. `store` moves all of the
memory into a different repository. `workplace` attaches a shared scope at
`<memory_dir>/private`. These can be two different repositories.

Two changes keep the two repositories apart:

- The checkout directory comes from the URL. Thus two URLs cannot give one
  directory.
- If a checkout is already there, the verb compares its `origin` with the
  configured URL. If the two are different, the verb stops, and shows both.

The second change also finds a different problem: an unrelated repository at
that path. Before 0.4.2 neither check existed, and the two verbs shared one
directory in silence — [the lessons](../lessons.md) have the measurement.

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

A fifth is optional and written once per half: `half_chars_max.<half>` bounds
one half of the tree on its own, and `half_chars_max.root` covers the notes
that sit directly in the memory directory. A half with no key of its own is not
bounded, so a corpus that sets none behaves exactly as it did before the keys
existed.

All of them are facts about **this** corpus. Thus they stay with the memory, and
not in `.floppy/config`. One size limit is a fact about the agent application
instead: `index_chars_max`, in the table above.

**Every one of these ceilings warns before it refuses.** At 96% of a ceiling
`lint` prints a `!` line naming it — the run still passes — and the corpus
ceiling brings the per-half breakdown with it, so the line says which half
grew. The exception is `pointer_line_max`: it bounds one line, and a line at
165 of 170 characters is not approaching anything, it is a line that fits.

The band exists because of who a hard stop lands on. A ceiling that only
refuses stops whoever crosses it, and on a memory written from several machines
that is routinely not whoever filled it. The ratchet below says a number may be
raised only in the same commit as the notes that needed the room — so a session
that meets a bare refusal has to either raise a ceiling it did not fill, or
prune a half it did not write, and pruning another session's notes is the one
thing the wrap rite forbids outright. The warning reaches the session that is
doing the filling, while the work of trimming is still its own.

The 96% is derived from each ceiling, not configured. Two numbers that have to
be kept in a fixed relation are two chances to set them wrong, and nobody has a
reason to want the warning at some other fraction.

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
report, not a report. It rewrites no note. A clean verdict comes with the
linter's warnings printed under it, because "nothing is wrong" and "nothing to
do" are different reports — and one warning is created by adoption itself:
`pointers_max` is seeded at the longest index found, which leaves that index at
100% of its own ceiling from the first run.

While the file is absent, `bash .floppy/run lint` gives a warning. It does not
fail.

