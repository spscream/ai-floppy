# Sourced by lib-config.sh, memory-link.sh, workstatus.sh and wrap-check.sh.
# Not a verb: the shim dispatches on scripts/<verb>.sh, and nothing dispatches
# here.
#
# Three things that have to be said in exactly one place, and were said in two
# or three each until 0.27.0.
#
# 1. HOW THE HARNESS NAMES A WORKING DIRECTORY. Claude Code keeps its
#    per-project memory at <config>/projects/<encoded cwd>/memory, and the
#    encoding is a fold of three characters. It lived in memory-link.sh alone,
#    with a comment saying a checker must call that script rather than repeat
#    the rule — which is true and is why the rule moved here instead of being
#    copied: the parser now needs it too, to make the pointer appear without
#    anybody running a verb.
#
# 2. WHETHER THE MEMORY IS REACHABLE FROM THIS WORKING COPY, asked by the
#    read-out and by the gate. It used to be two copies and they had already
#    drifted: `status` carried an arm for "the private scope is not a symlink"
#    that `wrap-check.sh` never had. Measured 2026-09-25 in a git worktree of
#    this plugin's own repository, one second apart:
#
#      status: repository exists, but .agent-memory/private is not a symlink
#      check:  clean and pushed
#
#    The gate was the optimistic one of the pair, which is the wrong way round
#    for a gate.
#
# 3. THE ORDER THE WIRING VERBS HAVE TO RUN IN. Nothing said it, and the order
#    the tool suggested bricked the tree — see wiring_advice.
#
# Runs on macOS bash 3.2: no mapfile, no declare -A, no GNU-only flags.

# harness_project_dir <absolute working directory>
# Echoes the harness's project directory for it. `_` belongs in the folded set
# as much as `/` and `.` do: Claude Code folds all three into `-`, and an
# earlier copy of this rule encoded only the first two — so a checkout whose
# name carries an underscore got a project directory of its own that the
# harness never opens. Nothing failed: the link was created where it was
# computed, `--check` agreed because it asked this same line, and the session's
# memory went to a second copy. Measured 2026-09-05 from the harness's own
# transcripts, which record the cwd a session actually ran in:
#
#   -home-amalaev-work-agents-harness   cwd=/home/amalaev/work/agents_harness
#   -home-amalaev-work-ai-floppy        cwd=/home/amalaev/work/ai_floppy
#   -home-amalaev--local-bin            cwd=/home/amalaev/.local/bin
#
# Two of that machine's three consumers were unwired this way, one across
# fifteen sessions. Case is NOT folded — `/tmp/consensus-5Ob9Z2` keeps its
# capitals in the harness's directory name — so this stays a `tr` of three
# characters and not a general slug.
harness_project_dir() {
  printf '%s\n' "$HOME/.claude/projects/$(printf '%s' "$1" | tr '/._' '---')"
}

# auto_harness_link <absolute working directory> <resolved memory path>
# Makes the harness's pointer to the memory exist for THIS working directory,
# and says so once.
#
# Why automatic. The memory itself is now addressed by repository (see
# lib-config.sh), so a worktree needs no wiring to read or write it — but the
# harness's own session loader is addressed by CWD, reading
# <config>/projects/<encoded cwd>/memory/MEMORY.md, and that path is the
# harness's to choose, not this plugin's. One pointer per working directory is
# therefore unavoidable, and the working directories that need it are cut by
# tooling for an agent that arrives in a finished tree and calls no wiring verb
# at all. A step nobody runs is a step that does not happen.
#
# What it will not do is anything but create a symlink where there is nothing:
# no clone, no pull, no delete, no move, and no touching of a real directory or
# a link pointing elsewhere. Those are the states the `link` verb refuses by
# hand, and they stay refusals — a real directory there is a forked memory, and
# whose copy wins is not a decision a config parser gets to make.
auto_harness_link() {
  ahl_cwd="$1"; ahl_mem="$2"
  # A verb that promised to change nothing. scripts/run sets this for any call
  # carrying --check, because a reporting flag that quietly creates a symlink in
  # somebody's configuration directory is a reporting flag nobody can trust.
  [[ "${FLOPPY_AUTOLINK:-1}" == "0" ]] && return 0
  [[ -n "$ahl_mem" && -d "$ahl_mem" ]] || return 0
  # Only where this harness is actually installed. The directory is the
  # harness's own, created by it; its absence means either another harness
  # (Cursor, which has no equivalent to wire and which `link` says so about) or
  # no harness at all — a CI runner, a test sandbox with its own HOME. Creating
  # a project tree for Claude Code on a machine that does not run it would be
  # this plugin inventing state in somebody else's configuration directory.
  [[ -d "$HOME/.claude/projects" ]] || return 0
  ahl_proj="$(harness_project_dir "$ahl_cwd")"
  ahl_link="$ahl_proj/memory"
  # A DANGLING link is this plugin's own wiring with nothing behind it to lose,
  # and it is repointed rather than stepped around. The state is reachable by
  # following this tool's own advice: a machine wired before 0.27.0 has a
  # pointer at <repo>/<memory_dir>, `store` now says "removing it is yours to
  # do", and the moment somebody does, the harness pointer dangles. Nothing was
  # then red anywhere — the session simply read an empty memory — which is the
  # silent second copy `link` exists to prevent, arrived at from the other
  # direction. Same reasoning as view_link's dangling branch in lib-checkout.sh.
  if [[ -L "$ahl_link" && ! -e "$ahl_link" ]]; then
    rm -f "$ahl_link"
    if ln -s "$ahl_mem" "$ahl_link" 2>/dev/null; then
      echo "ok repointed the dangling memory pointer: $ahl_link -> $ahl_mem" >&2
    else
      echo "! the memory pointer $ahl_link dangles and could not be repointed — run the link verb" >&2
    fi
    return 0
  fi
  # Anything else already there — a good link, a link that RESOLVES somewhere
  # else, a real directory — is somebody's, and this returns silently. `link`
  # reports on all three; this only fills a hole.
  [[ -e "$ahl_link" || -L "$ahl_link" ]] && return 0
  mkdir -p "$ahl_proj" 2>/dev/null || return 0
  # stderr, not stdout: `env` pipes this file's effect through `grep FLOPPY_`,
  # and several verbs capture each other's stdout. Announced rather than done
  # in silence — a pointer that appears with nobody told is the silent wiring
  # this plugin exists to argue against — and announced exactly once, because
  # the next run finds the link already there.
  if ln -s "$ahl_mem" "$ahl_link" 2>/dev/null; then
    echo "ok memory pointer created for this working directory: $ahl_link -> $ahl_mem" >&2
  else
    echo "! could not create the memory pointer $ahl_link — run the link verb" >&2
  fi
  return 0
}

# wiring_state <workplace-checkout> <memory-path> <private-leaf>
# Echoes one word. The order of the tests is the order the states have to be
# repaired in, so the first one that answers is also the next thing to do.
wiring_state() {
  # No memory at the resolved path is the state a machine that has never run
  # `store` is in — and, before 0.27.0, the state every git worktree started
  # in. Asked first because every scope below it is a path inside it: without
  # this arm both callers went on to ask whether a symlink exists inside a
  # directory that does not, answered "not a symlink", and sent the reader to
  # the one verb that bricks the tree.
  [[ -d "$2" ]]      || { printf 'no-memory\n';   return; }
  [[ -d "$1/.git" ]] || { printf 'no-checkout\n'; return; }
  [[ -L "$2/$3" ]]   || { printf 'no-link\n';     return; }
  printf 'wired\n'
}

# wiring_advice <state> <workplace-checkout> <memory-path> <private-leaf>
# The body of the section, indented two spaces — the shape both callers print.
#
# Verbs are named as verbs and not as a path to a runner: how a verb is invoked
# is the shim's business and has changed once already.
#
# `store` FIRST is the load-bearing word. Measured 2026-09-25: `workplace` run
# before `store` creates a real memory directory to hold its symlinks, and
# `store` then refuses — correctly, by its own design — to delete a directory
# that may be somebody's only copy of their notes. Nothing in the tool said the
# order, and the order it did suggest left the tree behind a manual `rm`.
wiring_advice() {
  case "$1" in
    no-memory)
      echo "  no memory at $3 — this machine has no copy of it yet"
      if [[ -n "${FLOPPY_MEMORY_REPO:-}" ]]; then
        echo "  run the store verb: it clones the store and lays the cache out. Then workplace"
        echo "  (the private scope), and store FIRST — in the other order workplace creates a"
        echo "  real directory where the memory belongs, and store then refuses to remove it."
      else
        echo "  the memory is laid out by init; nothing in this report creates it"
      fi
      ;;
    no-checkout)
      echo "  not wired: no $2 — run the workplace verb"
      ;;
    no-link)
      echo "  the workplace repository is here, but $3/$4 is not a symlink into it — run the workplace verb"
      ;;
  esac
}
