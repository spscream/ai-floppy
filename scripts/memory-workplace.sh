#!/usr/bin/env bash
# Attach .agent-memory/local to the workplace memory repository.
#
# Why a script: `local/` used to be a plain gitignored directory, and that
# quietly conflated two different things — "true only on this machine" and
# "invisible to the other machine". Of the four notes it held, one was machine
# bound; the rest were simply lost to the second machine. The workplace
# repository fixes the scope, and this script does the wiring that otherwise
# lives as prose: clone, pull, symlink, and a write test through the link.
#
# It is idempotent: a second run on a configured machine changes nothing. It
# never deletes a real directory standing where the symlink belongs — that is
# a forked memory and a human sorts it out.
#
# Offline is not a failure: the pull is skipped with a warning, because the
# link and the notes work without the network.
#
# Output is English on purpose: the tool is reusable, the memory is not.
#
#   bash .floppy/run workplace                     wire it up (idempotent)
#   bash .floppy/run workplace --migrate-local     plan the migration, change nothing
#   bash .floppy/run workplace --migrate-local --apply    carry the plan out
#
# --migrate-local exists for the machine that lagged behind: there `local/` is
# still a real directory of notes, written before the workplace repository
# existed. The plain run refuses to touch it on purpose — those may be the only
# copies of some facts — and the refusal used to hand the whole job to a human.
#
# What the migration does NOT decide is the scope. `local/` was, by definition,
# "private facts about this project", which is exactly projects/<key>/, so that
# is where everything goes. Re-filing a note into workplace/, machines/<host>/
# or cross/ is a judgement about where the fact is true, and a script that
# guessed it would file things where nobody looks for them.
set -uo pipefail
cd "${FLOPPY_REPO:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"

migrate=0
apply=0
for a in "$@"; do
  case "$a" in
    --migrate-local) migrate=1 ;;
    --apply) apply=1 ;;
    *) echo "x unknown argument: $a"; exit 2 ;;
  esac
done
[[ $apply -eq 1 && $migrate -eq 0 ]] && { echo "x --apply means nothing without --migrate-local"; exit 2; }

repo="$(pwd)"
# The scope directory inside the workplace repository, and the repository URL
# itself, are both required: this plugin has no project of its own to default
# to, and a default here would mean a consuming project silently writes into
# somebody else's private memory. Set workplace_project_key and workplace_repo
# in .floppy/config.
project_key="${FLOPPY_WORKPLACE_PROJECT_KEY:?set workplace_project_key in .floppy/config}"
url="${FLOPPY_WORKPLACE_REPO:?set workplace_repo in .floppy/config}"
dir="${FLOPPY_WORKPLACE_MEMORY_DIR:-$HOME/agents_memory}"
target="$dir/projects/$project_key"
mem_dir="${FLOPPY_MEMORY_DIR:-.agent-memory}"
link="$repo/$mem_dir/local"

echo "workplace memory: $dir"
echo "project scope:    projects/$project_key"
echo

# ---------- the repository itself ----------
# Refusals, clone or pull, and the secret hook are shared with `store`:
# scripts/lib-checkout.sh. The origin check inside it is what keeps this verb
# from wiring notes meant for a private workplace repository into whatever
# repository happens to sit at that path.
_lib="$(dirname "$0")/lib-checkout.sh"
[[ -f "$_lib" ]] || _lib="${FLOPPY_ROOT:-}/scripts/lib-checkout.sh"
. "$_lib"
ensure_checkout "$url" "$dir" "workplace memory" || exit 1

mkdir -p "$target"

# ---------- the symlink ----------
if [[ -L "$link" ]]; then
  cur="$(readlink -f "$link")"
  if [[ "$cur" == "$(readlink -f "$target")" ]]; then
    echo "ok already configured: $mem_dir/local -> $target"
  else
    echo "x the symlink points elsewhere: $link -> $cur"
    echo "  expected $target. Sort this out by hand: it may be another workplace."
    exit 1
  fi
elif [[ -e "$link" ]]; then
  n="$(find "$link" -name '*.md' 2>/dev/null | wc -l | tr -d ' ')"
  if [[ $migrate -eq 0 ]]; then
    echo "x a real directory sits where the symlink belongs. Memory files in it: $n."
    echo "  This is the lagging-machine case. To see what a migration would do:"
    echo "      bash .floppy/run workplace --migrate-local"
    echo "  Nothing is moved until you add --apply."
    exit 1
  fi

  # ---------- the migration ----------
  # Two passes on purpose. The first only classifies; the second acts, and only
  # if the first found no conflict. A single pass that moved as it went left a
  # half-migrated directory whenever a conflict appeared late in the list — and
  # printed "nothing was deleted" while saying it. Content decides, not names:
  # a file already in the scope byte for byte came from another machine
  # earlier, and the copy here is redundant.
  echo "-- migrating $mem_dir/local -> $target"
  [[ $apply -eq 0 ]] && echo "   (plan only — nothing is moved without --apply)"
  echo
  plan=""
  moved=0; dup=0; conflict=0
  while IFS= read -r src; do
    rel="${src#"$link"/}"
    case "$rel" in
      .write-probe-*|.link-probe) continue ;;
    esac
    dst="$target/$rel"
    if [[ ! -e "$dst" ]]; then
      echo "   move      $rel"
      plan="${plan}move	$rel
"
      moved=$((moved + 1))
    elif cmp -s "$src" "$dst"; then
      echo "   identical $rel — already in the scope, the local copy is redundant"
      plan="${plan}dup	$rel
"
      dup=$((dup + 1))
    else
      echo "x  CONFLICT  $rel — differs from the file already in the scope"
      conflict=$((conflict + 1))
    fi
  done < <(find "$link" -type f | sort)

  echo
  echo "   to move: $moved, already there: $dup, conflicts: $conflict"
  if [[ $conflict -gt 0 ]]; then
    echo
    echo "x conflicts stop the migration: two machines wrote the same note differently."
    echo "  Merge each one by hand in $target, delete the local copy, run again."
    echo "  Nothing was moved or deleted — this run only looked."
    exit 1
  fi
  if [[ $apply -eq 0 ]]; then
    echo
    echo "   to carry this out: bash .floppy/run workplace --migrate-local --apply"
    echo
    echo "   'move' is not the end of the job. Everything lands in projects/<key>/"
    echo "   because that is what local/ was; deciding that a note actually belongs"
    echo "   in workplace/, machines/<host>/ or cross/ — or that it is stale and"
    echo "   should go — is yours. The one real migration of this kind moved 1 of 6"
    echo "   objects as-is: one was merged into a better note written meanwhile on"
    echo "   the other machine, three were deleted. Read them, do not just file them."
    exit 0
  fi

  # ---------- second pass: act ----------
  echo
  # IFS is a tab, not the default: a note whose name contains a space would
  # otherwise be split and the wrong file moved.
  while IFS=$'\t' read -r verdict rel; do
    [[ -z "$rel" ]] && continue
    src="$link/$rel"
    dst="$target/$rel"
    if [[ "$verdict" == "move" ]]; then
      mkdir -p "$(dirname "$dst")"
      # Copy, verify byte for byte, only then drop the source. A move that half
      # succeeds on a full disk would otherwise destroy the only copy.
      cp -p "$src" "$dst" || { echo "x copy failed: $rel — source left in place"; exit 1; }
      cmp -s "$src" "$dst" || { echo "x the copy differs from the source: $rel — nothing deleted"; exit 1; }
      rm -f "$src"
    else
      rm -f "$src"
    fi
  done <<< "$plan"
  echo "ok $moved moved, $dup redundant copies dropped"

  # Empty directories left by the moves, then the directory itself. rmdir-style
  # deletion, not rm -r: anything unexpected still in there fails loudly.
  find "$link" -type d -empty -delete 2>/dev/null
  if [[ -e "$link" ]]; then
    echo "x $link is not empty after the migration — look at what is left, nothing deleted"
    exit 1
  fi
  echo "ok local/ migrated and removed"
  ln -s "$target" "$link"
  echo "ok linked: $mem_dir/local -> $target"
else
  ln -s "$target" "$link"
  echo "ok linked: $mem_dir/local -> $target"
fi

# ---------- the link itself must not be committed ----------
# With a store (`bash .floppy/run store`), memory_dir is already a symlink, so
# this link is created INSIDE the store's working tree. It holds an absolute
# path, and committed it dangles on any machine whose checkout lives at another
# path — measured 2026-08-25, together with the recursion it opens
# (projects/<key>/memory/local/memory/local/...). It is wiring, and wiring is
# per machine: every machine runs this verb anyway. Silent in the ordinary
# layout, where the link sits in the consumer repository and its own .gitignore
# already covers it.
ignore_wiring_link "$link"

# ---------- does a write reach the repository? ----------
probe="$link/.write-probe-$$"
if echo "probe" > "$probe" 2>/dev/null && [[ -f "$target/.write-probe-$$" ]]; then
  rm -f "$probe"
  echo "ok a write through the link lands in the workplace repository"
else
  rm -f "$probe"
  echo "x a write through the link does not reach $target"
  exit 1
fi

# ---------- what is not pushed ----------
ahead="$(git -C "$dir" rev-list --count @{u}..HEAD 2>/dev/null || echo '?')"
dirty="$(git -C "$dir" status --porcelain | wc -l | tr -d ' ')"
[[ "$dirty" != "0" ]] && echo "! $dirty uncommitted change(s) in $dir — /wrap commits and pushes them"
[[ "$ahead" != "0" && "$ahead" != "?" ]] && echo "! $ahead commit(s) not pushed in $dir — the other machine cannot see them"
exit 0
