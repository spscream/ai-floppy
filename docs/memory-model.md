# The memory model: two namespaces, two axes

*[Русская версия](memory-model.ru.md)*

**Status: implemented in 0.7.0** for the namespace and subject levels; the
validity level (`workplaces/`, `machines/`) is directories only — no verb
creates or reads them yet. Written 2026-08-25 against 0.6.1, revised on
implementation. It exists because the layout
was renamed three times in one day — `projects/<key>`, then `/memory` and
`/local`, then `/shared` and `/private` — and each rename was a correction to a
model nobody had written down. The names kept saying the wrong thing because
the thing itself was never stated.

Read this before changing any path in `memory-store.sh`, `memory-workplace.sh`
or the shim's resolution.

## What a note has to answer

Three questions, and they are independent. Every layout that mixed two of them
into one directory name has been wrong.

| question | values | decided by |
|---|---|---|
| **Who may read it?** | the team, or one person | the git repository it is in |
| **What is it about?** | one project, or no single project | the `projects/<key>/` or `common/` directory |
| **Where is it true?** | everywhere, one workplace, one machine | the validity directory below that |

The first question is answered by a repository boundary, not by a directory and
not by a field in the frontmatter. A directory is a hint to a human; a
repository is the access control. A note that must not reach the team has to be
in a repository the team cannot clone — anything weaker is a convention, and a
convention does not survive `git add -A`.

The other two questions are directories, because a human navigates them and git
moves them.

## The grammar

```
<namespace>/<subject>/[<validity>/]<note>.md
```

```
private/                            one repository per person
  projects/<key>/                   about this project, true everywhere
      workplaces/<place>/           about this project, true at this workplace only
      machines/<machine>/           about this project, true on this machine only
  common/                           about no single project, true everywhere
      workplaces/<place>/           about no single project, this workplace only
      machines/<machine>/           about no single project, this machine only

public/                             the project's own repository, or a shared one
  projects/<key>/  ...              the same six cells
  common/          ...
```

Three decisions inside that shape, each with its reason:

1. **Subject above validity.** The reverse (`workplaces/<place>/projects/<key>/`)
   forces a session working on one project to visit `1 + N places + N machines`
   directories, which is the common read. It also splits a project's notes, so
   handing a project over — or deleting it — stops being one `git mv`.
2. **"True everywhere" has no directory of its own.** Those notes sit directly
   in `projects/<key>/` or `common/`. It is the most frequent case and it should
   not cost a level. This is also what the current layout already does.
3. **`public/` and `private/` are always directories.** The first draft said a
   single-namespace repository could keep its scopes at the root, and
   implementing it showed why not: the plugin blesses one URL serving both
   roles, and then both scopes would be `projects/<key>` and collide. Making
   the level conditional on "are the two URLs equal" would mean the path
   changes when a config line changes. One level always, no condition. The
   ordinary case is untouched: the public half of a project that can hold its
   own memory is `.agent-memory/` in the project's repository, and this grammar
   only governs memory kept in a repository of its own.

## The six cells, with real examples

Taken from a live corpus, not invented.

| cell | path | example |
|---|---|---|
| private · project · everywhere | `private/projects/effectssdk/` | which branch of the client's checkout we changed, and how to undo it |
| private · project · workplace | `private/projects/effectssdk/workplaces/home/` | the office stand is reachable from here, the client's GitLab is not |
| private · project · machine | `private/projects/effectssdk/machines/mac/` | the Xcode "Missing package product" diagnosis, which needs Xcode |
| private · common · everywhere | `private/common/` | an evaluation of an outside tool; a shell trap |
| private · common · workplace | `private/common/workplaces/home/` | where the calls backend is checked out, and on which machine |
| private · common · machine | `private/common/machines/linux/` | this machine's GPU, what is installed on it |

The third row is the one no current layout can express. Today that note lives
in the project scope and loses "only true on the mac", or in the machine scope
and loses "about this project". It was filed both ways in the same corpus.

## Which repository holds what

**Chosen, 2026-08-25: one private repository per person, workplaces as a
directory.** A person's own conventions, tool evaluations and shell traps stay
in one place instead of being copied between per-workplace repositories.

The alternative — one repository per workplace — is not wrong, and the grammar
supports it unchanged (the `workplaces/` level simply stays unused). Choose it
when a "workplace" is an employer rather than a room: then the repository
boundary is a containment boundary, and notes about one client's checkout
cannot end up beside another's even by accident.

Public memory keeps its current rule: it lives in the project's own repository
(`.agent-memory/`) unless the project cannot hold it, in which case it goes to a
shared repository under `public/projects/<key>/`.

## How a session reads it

A session always knows three coordinates: the project, the workplace, and the
machine. It reads, in order:

1. `<namespace>/projects/<key>/` — the index, then the notes it points to.
2. `<namespace>/projects/<key>/workplaces/<this place>/` and
   `machines/<this machine>/` — only the two that match. The others are not
   just irrelevant, they are **false here**, which is worse.
3. `<namespace>/common/` and its two matching validity directories, when the
   task is not about the project alone.

Six cells is more than a session should open one by one, so the index does the
routing: **one index per subject directory** (`projects/<key>/INDEX.md`,
`common/INDEX.md`), listing every note under it including those in the validity
directories, each pointer marked with where it is true. One file to read, and
the pointer says whether the note applies here.

## What the configuration needs

| key | state | why |
|---|---|---|
| `project_key` | exists | names the project in every memory repository |
| `machine_key` | **new** | `hostname` is unusable as a name: on one of these machines it is `WIN-GVR0V5UPOD7`. The directories are hand-named (`linux-wsl-alexander`) and should stay that way |
| `workplace_key` | **new** | only needed when one repository serves several workplaces, which is the chosen deployment |
| `public_repo` | rename of `memory_repo` | today's name says "memory", which is both halves |
| `private_repo` | rename of `workplace_repo` | today's name says "workplace", which is one of three validity values, not an audience |

The last two renames matter more than they look. `memory_repo` and
`workplace_repo` are the pair that made two different questions look like one
axis, and that is the mistake this document exists to stop.

## Deliberately not decided here

- **Whether the leaf `shared`/`private` survives.** In this grammar the
  namespace directory carries the audience, so a leaf repeating it is
  redundant. It exists today only because one repository could play both roles.
- **How `machines/<machine>/` gets wired into a project.** Today no verb
  creates that link; the notes are written straight into the checkout. Adding a
  link is one more entity in every project for a rare case, and the case has
  three notes in it so far.
- **The migration.** Six cells is a bigger move than the three renames that
  preceded it, and none of them should be started before this document has been
  read by a human and disagreed with.
