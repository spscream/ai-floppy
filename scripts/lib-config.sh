#!/usr/bin/env bash
# The configuration of one repository, parsed once, exported as FLOPPY_*.
#
# Sourced by scripts/run with FLOPPY_REPO already resolved. It lives in the
# PLUGIN, not in the shim the plugin copies into a consumer repository, and
# that placement is the point: from 0.14.0 a change to a key or a default
# reaches every repository with `plugin update` alone. Before, it reached them
# only when a human remembered to re-copy `.floppy/run` — and a stale parser is
# the silent kind of stale, the kind that keeps answering with the old default
# instead of failing.
#
# Every script here reads its settings from the environment, so there is
# exactly one parser and one search order for the whole plugin.
#
# Runs on macOS bash 3.2: no mapfile, no declare -A, no GNU-only flags.

# Flat key=value, like quota.lock. Nested YAML cannot be parsed by bash 3.2
# without a hand-rolled parser, and a hand-rolled config parser fails quietly.
cfg="$FLOPPY_REPO/.floppy/config"
cfg_get() { # key default
  local line="" v=""
  [[ -f "$cfg" ]] && line="$(grep -m1 "^[[:space:]]*$1[[:space:]]*=" "$cfg" 2>/dev/null || true)"
  if [[ -z "$line" ]]; then printf '%s' "$2"; return; fi
  v="${line#*=}"
  v="${v#"${v%%[![:space:]]*}"}"   # leading
  v="${v%"${v##*[![:space:]]}"}"   # trailing
  printf '%s' "$v"
}

# memory_language is deliberately not exported: it governs the language a
# note's prose is written in, which is a convention the agent reads out of
# .floppy/config directly (see floppy:agent-memory) — no script here acts on
# it. An env var nothing consumes is worse than no var: it looks wired.
export FLOPPY_MEMORY_DIR="$(cfg_get memory_dir .agent-memory)"

# Is the memory inside this repository, or hosted in another one?
#
# Some consumers cannot commit memory next to the code — a client's checkout
# they do not own, or a policy against agent notes in the code repository. For
# those, memory_dir is a symlink (or an absolute path) into a separate git
# repository, and the whole rite has to close two repositories instead of one.
#
# DERIVED, never configured. A boolean in .floppy/config would be a second
# source of truth about a thing the filesystem already knows, and the two would
# disagree exactly when it matters: a symlink that failed to get created reads
# as "external" in the config while every write lands in an ordinary directory
# inside the repository, where the ignore rule then hides it. Resolving the
# path cannot be wrong about where a write goes.
#
# `cd && pwd -P` rather than `realpath`/`readlink -f`: macOS ships neither in
# the form used here (BSD readlink has no -f), and this must run on bash 3.2.
case "$FLOPPY_MEMORY_DIR" in
  /*) _mem_abs="$FLOPPY_MEMORY_DIR" ;;
  *)  _mem_abs="$FLOPPY_REPO/$FLOPPY_MEMORY_DIR" ;;
esac
if [[ -d "$_mem_abs" ]]; then _mem_real="$(cd "$_mem_abs" && pwd -P)"; else _mem_real="$_mem_abs"; fi
_repo_real="$(cd "$FLOPPY_REPO" && pwd -P)"
case "$_mem_real/" in
  "$_repo_real"/*) FLOPPY_MEMORY_EXTERNAL=0 ;;
  *)               FLOPPY_MEMORY_EXTERNAL=1 ;;
esac
# The store's own git root, not the memory directory: a memory hosted at
# projects/<key>/memory inside a bigger repository is committed at that
# repository's root. Empty when the memory is internal, and empty too when the
# resolved path is outside this repository but not in any git repository at
# all — which is a real setup (a plain directory in $HOME) that the rite must
# report rather than pretend it can push.
FLOPPY_MEMORY_STORE=""
if [[ "$FLOPPY_MEMORY_EXTERNAL" == "1" && -d "$_mem_real" ]]; then
  FLOPPY_MEMORY_STORE="$(git -C "$_mem_real" rev-parse --show-toplevel 2>/dev/null || true)"
fi
export FLOPPY_MEMORY_EXTERNAL FLOPPY_MEMORY_STORE
export FLOPPY_MEMORY_REAL="$_mem_real"
# private_repo/public_repo, 0.7.0. The names they replaced paired an audience
# with a validity value and made two independent questions look like one axis:
# `memory_repo` meant "public, but not in the code repository", and
# `workplace_repo` meant "private" — neither name said so. They are gone rather
# than kept as a fallback: nothing outside this repository was ever configured
# with them, so the compatibility would have documented a key nobody has.
export FLOPPY_PRIVATE_REPO="$(cfg_get private_repo '')"
export FLOPPY_WORKPLACE_REPO="$FLOPPY_PRIVATE_REPO"
# One key names this project in every memory repository it uses, and it is
# also the directory a human opens under agents_memory_dir. The two older,
# per-purpose keys stay as overrides, for the project whose scope really is
# named differently in the two repositories — that case exists, which is why
# they are not simply deleted, but it is not the common one and it should not
# be what a fresh config asks about.
export FLOPPY_PROJECT_KEY="$(cfg_get project_key '')"
# Where a note is true, as two names a human chose. `hostname` cannot serve:
# on one of these machines it is WIN-GVR0V5UPOD7, which no note should have to
# carry. Both are optional — a validity directory is only created when a note
# needs it, and most notes are true everywhere.
export FLOPPY_MACHINE_KEY="$(cfg_get machine_key '')"
export FLOPPY_WORKPLACE_KEY="$(cfg_get workplace_key '')"
export FLOPPY_WORKPLACE_PROJECT_KEY="$(cfg_get workplace_project_key "$FLOPPY_PROJECT_KEY")"

# ---------- where a memory checkout lives ----------
# One PARENT directory holds one checkout per repository URL, and the checkout
# directory is derived from the URL rather than configured.
#
# It used to be configured, once per purpose: memory_repo_dir for the store and
# workplace_memory_dir for the workplace repository, both defaulting to
# $HOME/agents_memory. Two keys with one default is a collision waiting for
# somebody to configure both, and the collision was silent — measured
# 2026-08-25: the first verb cloned its repository there, the second found a
# .git, skipped its clone, never compared the remote, and reported "a write
# through the link lands in the workplace repository" while the notes were
# landing in the store and would have been pushed there.
#
# Deriving the directory from the URL removes the class rather than the case:
# two URLs cannot name one directory, and one URL used for both purposes
# deliberately shares a checkout, which is correct — two checkouts of one
# repository on one machine fight over pulls instead.
FLOPPY_AGENTS_MEMORY_DIR="$(cfg_get agents_memory_dir "$HOME/agents_memory")"
export FLOPPY_AGENTS_MEMORY_DIR

_origin_of() { git -C "$1" remote get-url origin 2>/dev/null || true; }

# url, then the value of the legacy per-purpose key (empty if unset).
_checkout_dir() {
  _cd_url="$1"; _cd_explicit="$2"
  # An explicit key still wins, exactly as before: a machine that already
  # names its checkout must not be moved by an upgrade.
  if [[ -n "$_cd_explicit" ]]; then printf '%s\n' "$_cd_explicit"; return; fi
  # Nothing configured: the parent is the honest answer, and the verbs refuse
  # on the missing URL rather than on a path.
  if [[ -z "$_cd_url" ]]; then printf '%s\n' "$FLOPPY_AGENTS_MEMORY_DIR"; return; fi
  # Name the directory after the repository in the URL. The colon strip is for
  # the scp-style form with no path segment (git@host:repo.git), where cutting
  # at the last slash alone would leave "git@host:repo" as a directory name.
  _cd_slug="${_cd_url%/}"; _cd_slug="${_cd_slug##*/}"; _cd_slug="${_cd_slug##*:}"
  _cd_slug="${_cd_slug%.git}"
  # Clones live under .clones/ so that the parent holds one alphabet only —
  # project keys, which is what a human looks for there. A flat parent mixed
  # project names with repository names, and telling them apart needed the
  # config open beside the terminal.
  _cd_derived="$FLOPPY_AGENTS_MEMORY_DIR/.clones/$_cd_slug"
  if [[ -d "$_cd_derived/.git" ]]; then printf '%s\n' "$_cd_derived"; return; fi
  # Two older layouts, adopted rather than re-cloned, and each only when its
  # origin proves it is this very repository. Anything less than that proof
  # would be the silent adoption these checks exist to stop: a directory
  # holding some other repository falls through to the derived path, where the
  # verb's own origin check has the last word.
  #   0.4.2: one checkout per URL, directly under the parent.
  if [[ -d "$FLOPPY_AGENTS_MEMORY_DIR/$_cd_slug/.git" ]] \
     && [[ "$(_origin_of "$FLOPPY_AGENTS_MEMORY_DIR/$_cd_slug")" == "$_cd_url" ]]; then
    printf '%s\n' "$FLOPPY_AGENTS_MEMORY_DIR/$_cd_slug"; return
  fi
  #   before 0.4.2: one checkout, at the parent itself.
  if [[ -d "$FLOPPY_AGENTS_MEMORY_DIR/.git" ]] \
     && [[ "$(_origin_of "$FLOPPY_AGENTS_MEMORY_DIR")" == "$_cd_url" ]]; then
    printf '%s\n' "$FLOPPY_AGENTS_MEMORY_DIR"; return
  fi
  printf '%s\n' "$_cd_derived"
}

export FLOPPY_WORKPLACE_MEMORY_DIR="$(_checkout_dir "$FLOPPY_WORKPLACE_REPO" "$(cfg_get workplace_memory_dir '')")"
# A fact about the harness, not about this project: its session loader
# truncates the memory index past a size of its own and says nothing about the
# tail it dropped. Shipped with the number measured on Claude Code and
# overridden by a consumer whose harness cuts elsewhere. The per-corpus caps
# (how many pointers, how long a pointer line, how big the memory) live in
# quota.lock instead, inside the memory itself — see the memory-lint header.
# The private scope inside the memory: facts about this project that the code
# repository must not carry — somebody else's checkout, an access note, a
# reading of a client's source. It is NOT machine-local, which is what its old
# name `local` said and what it stopped being when it became a symlink into a
# shared repository. Machine facts live in machines/<name>/ of that repository
# instead, where the other machine can read them.
#
# Only the NAME is configurable; the rule that committed memory must not link
# into this scope is not. The pre-0.6.0 key `memory_local_dir` is not read.
export FLOPPY_MEMORY_PRIVATE_DIR="$(cfg_get memory_private_dir private)"
# The old variable name, for a plugin script or a project hook still reading it.
export FLOPPY_MEMORY_LOCAL_DIR="$FLOPPY_MEMORY_PRIVATE_DIR"

# The private scope can be a symlink into the workplace repository while the
# rest of the memory sits in this one — the common shape, and a SECOND foreign
# repository. Nothing derived it before, so the gates asked this repository's
# `git status` about a path this repository ignores by design, were told
# "unchanged", and refused the commit as "wrong path, or the edit was lost".
#
# Derived, never configured, for the same reason FLOPPY_MEMORY_EXTERNAL is: a
# key in a file would disagree with the filesystem exactly when the symlink is
# the thing that failed to be created.
FLOPPY_PRIVATE_REAL=""
FLOPPY_PRIVATE_STORE=""
_priv="$FLOPPY_MEMORY_REAL/$FLOPPY_MEMORY_PRIVATE_DIR"
if [[ -d "$_priv" ]]; then
  FLOPPY_PRIVATE_REAL="$(cd "$_priv" && pwd -P)"
  _priv_top="$(git -C "$FLOPPY_PRIVATE_REAL" rev-parse --show-toplevel 2>/dev/null || true)"
  # Only a DIFFERENT repository counts. A plain private/ directory inside the
  # committed memory is this repository's own business, already covered by
  # every gate here, and giving it a second one would double-report it.
  if [[ -n "$_priv_top" && "$_priv_top" != "$_repo_real" && "$_priv_top" != "$FLOPPY_MEMORY_STORE" ]]; then
    FLOPPY_PRIVATE_STORE="$_priv_top"
  fi
fi
export FLOPPY_PRIVATE_REAL FLOPPY_PRIVATE_STORE
# Where this project's memory is hosted when it cannot live in this repository.
# No defaults, deliberately: a project that never opted in must not be pointed
# at somebody else's store. Read by `store`; the rest of the rite derives the
# layout from the filesystem instead.
export FLOPPY_PUBLIC_REPO="$(cfg_get public_repo '')"
export FLOPPY_MEMORY_REPO="$FLOPPY_PUBLIC_REPO"
export FLOPPY_MEMORY_PROJECT_KEY="$(cfg_get memory_project_key "$FLOPPY_PROJECT_KEY")"
export FLOPPY_MEMORY_REPO_DIR="$(_checkout_dir "$FLOPPY_MEMORY_REPO" "$(cfg_get memory_repo_dir '')")"
export FLOPPY_INDEX_CHARS_MAX="$(cfg_get index_chars_max 24500)"
# How long a note's metadata.as_of may stand before `lint` says so. It warns; it
# never fails, so this number costs nothing to get slightly wrong and is not a
# ratchet — see the memory-lint section for why "old" is not "wrong".
#
# 180 rather than the 90 the knowledge base uses, because the two corpora rot at
# different speeds. knowledge/ holds facts about a harness that ships monthly, so
# a claim there is suspect within a quarter. Agent memory holds facts about one
# repository — its decisions, its layout, why a thing is the way it is — and
# those outlive several harness releases. A consumer whose memory is mostly about
# a fast-moving dependency should lower it; that is the point of it being a key.
export FLOPPY_NOTE_STALE_DAYS="$(cfg_get note_stale_days 180)"
export FLOPPY_STATUSES_NOW="$(cfg_get statuses_now docs/statuses/NOW.md)"
export FLOPPY_STATUSES_NOW_CHARS_MAX="$(cfg_get statuses_now_chars_max 12000)"
# The second status, and the reason there are two (#19). statuses_now is the
# only artefact in the system that every wrap rewrites WHOLE, so two sessions
# overlapping in it conflict — while a note collides with nothing by
# construction and an index merges. The fix is the split the memory already
# made: give the two kinds of fact different homes.
#
#   statuses_now      - true about the PROJECT: frozen decisions, what is red,
#                       what waits on the owner, metrics with their regression
#                       marks. Committed here, read by anyone, changes rarely,
#                       and therefore rarely contended.
#   statuses_personal - true about ONE PERSON'S thread of work on ONE machine:
#                       what they are mid-way through, what is unfinished,
#                       where to pick it up. Changes every session and is
#                       shared with nobody, so it never needs merging at all.
#
# The default puts it inside the private scope under machines/<name>/, which
# makes the no-collision property structural rather than a convention anyone
# has to keep: no other machine writes that path. It follows the person to
# their second machine only if they configure the same machine_key there,
# which is the honest default — working state usually does not transfer.
#
# `hostname` is the fallback and machine_key overrides it, for the reason
# given where machine_key is read: on one of these machines the hostname is
# WIN-GVR0V5UPOD7. Here it only names a directory nobody publishes, so it is
# good enough to derive from, unlike in a note's validity path.
_sp_machine="$FLOPPY_MACHINE_KEY"
[[ -n "$_sp_machine" ]] || _sp_machine="$(hostname 2>/dev/null || echo unknown)"
_sp_machine="${_sp_machine%%.*}"          # the short name; a FQDN is noise here
_sp_machine="${_sp_machine//\//-}"        # never a path separator
export FLOPPY_STATUSES_PERSONAL="$(cfg_get statuses_personal \
  "$FLOPPY_MEMORY_DIR/$FLOPPY_MEMORY_PRIVATE_DIR/machines/$_sp_machine/NOW.md")"
# No character cap for it, unlike statuses_now. That cap exists because every
# session pays to read the project status; this one is read by the session
# that wrote it, on the machine that wrote it. A ceiling with nothing measured
# behind it is the borrowed number this project refuses elsewhere.
# Words that mark a regression in a trend table's direction cell, comma
# separated and in the project's own language. Unset means every trend row is
# protected from deletion, which is what the guard did before this key existed.
export FLOPPY_STATUSES_REGRESS_MARKS="$(cfg_get statuses_regress_marks '')"
export FLOPPY_WATCHED_DIRS="$(cfg_get watched_dirs docs)"
export FLOPPY_WATCHED_FILES="$(cfg_get watched_files AGENTS.md)"
# auto: pull --rebase then push, same as always. never: wrap-commit stays
# local — commits but does not touch a remote at all. For a repository with
# no upstream configured, "auto" fails the sync step every time (there is
# nothing to pull or push against), so that repository sets commit_push=never.
export FLOPPY_COMMIT_PUSH="$(cfg_get commit_push auto)"