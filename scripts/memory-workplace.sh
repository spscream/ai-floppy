#!/usr/bin/env bash
# Attach <memory_dir>/private to the workplace memory repository.
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
project_key="${FLOPPY_WORKPLACE_PROJECT_KEY:?set project_key in .floppy/config (or workplace_project_key to override it)}"
url="${FLOPPY_WORKPLACE_REPO:?set workplace_repo in .floppy/config}"
dir="${FLOPPY_WORKPLACE_MEMORY_DIR:-$HOME/agents_memory}"
# 0.7.0: the audience is a namespace directory at the top of the memory
# repository, and the scope below it answers only "what is this about". The
# leaf that used to repeat the audience (`local`, then `private`) is gone: it
# existed because one repository could serve both roles, which the namespace
# now expresses without making the path depend on whether two URLs are equal.
priv="${FLOPPY_MEMORY_PRIVATE_DIR:-private}"
scope="private/projects/$project_key"
target="$dir/$scope"
view="${FLOPPY_AGENTS_MEMORY_DIR:-$HOME/agents_memory}/$project_key/$priv"
mem_dir="${FLOPPY_MEMORY_DIR:-.agent-memory}"
link="$repo/$mem_dir/$priv"

echo "workplace memory: $dir"
echo "project scope:    $scope"
echo "view:             $view"
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

# Before 0.5.0 this scope was projects/<key> itself. Notes sitting directly in
# it are that layout: the move is a human's, once, on one machine — see
# refuse_old_scope for why doing it here would be worse than refusing.
if [[ -d "$dir/projects/$project_key" ]]; then
  stray="$(find "$dir/projects/$project_key" -maxdepth 1 -type f 2>/dev/null | wc -l | tr -d ' ')"
  if [[ "$stray" != "0" ]]; then
    refuse_old_scope "$dir" "projects/$project_key (${stray} file(s) directly in it)" "$scope" \
      "git -C \"$dir\" mv \"projects/$project_key\" \"projects/$project_key.moving\"" \
      "mkdir -p \"$dir/projects/$project_key\"" \
      "git -C \"$dir\" mv \"projects/$project_key.moving\" \"$scope\""
    exit 1
  fi
fi

# 0.5.0 and 0.5.1 called this scope leaf `local`, from the days when the
# directory really was machine-local and gitignored. It has not been either
# since it became a symlink into a shared repository, and the name kept
# saying otherwise — the owner read it as "facts about this machine" and
# asked where those go. They go to machines/<name>/ of the same repository.
for old in "projects/$project_key/local" "projects/$project_key/private"; do
  [[ -d "$dir/$old" ]] || continue
  refuse_old_scope "$dir" "$old" "$scope" \
    "mkdir -p \"$dir/private/projects\"" \
    "git -C \"$dir\" mv \"$old\" \"$scope\""
  exit 1
done

mkdir -p "$target"
view_link "$project_key" "$dir" "$scope" "$priv" || exit 1

# ---------- the symlink ----------
if [[ -L "$link" ]]; then
  # `cd && pwd -P`, not `readlink -f`: BSD readlink on macOS has no -f, and
  # every other resolution in this plugin already uses the portable form.
  if [[ -d "$link" ]]; then cur="$(cd "$link" && pwd -P)"; else cur="$(readlink "$link")"; fi
  want="$(cd "$target" && pwd -P)"
  old_scope="$(cd "$dir" && pwd -P)/projects/$project_key"
  old_leaf="$old_scope/local"
  old_view="${FLOPPY_AGENTS_MEMORY_DIR:-$HOME/agents_memory}/$project_key/local"
  if [[ "$cur" == "$want" ]]; then
    echo "ok already configured: $mem_dir/$priv -> $target"
  elif [[ "$cur" == "$old_scope" || "$cur" == "$old_leaf" || "$cur" == "$old_view" ]]; then
    # Wiring left by a pre-0.5.0 run of this same verb, pointing at the scope
    # this project used to have in this same repository. The notes moved; this
    # link did not. Repointing it is this verb's job: it is wiring, it holds no
    # content, and every machine recreates it anyway. The refusal below still
    # covers the case that is genuinely ambiguous — a link into some other
    # repository, which may be another workplace.
    rm -f "$link"
    ln -s "$view" "$link"
    echo "ok repointed $mem_dir/$priv from an earlier scope to $view"
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
  echo "-- migrating $mem_dir/$priv -> $target"
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
  ln -s "$view" "$link"
  echo "ok linked: $mem_dir/$priv -> $view"
else
  ln -s "$view" "$link"
  echo "ok linked: $mem_dir/$priv -> $view"
fi

# ---------- wiring left under an earlier name ----------
# The rename left two links where one is broken: this verb created the old one
# under the name the scope had then, and after the move it points at a path
# that no longer exists. Removing a DANGLING symlink is not deciding the fate
# of memory — there is nothing behind it, and this verb made it. A link that
# still resolves is left alone: it points at something real, and what that is
# is not this script's call.
for legacy_name in local; do
  [[ "$legacy_name" == "$priv" ]] && continue
  for legacy_path in "$repo/$mem_dir/$legacy_name" \
                     "${FLOPPY_AGENTS_MEMORY_DIR:-$HOME/agents_memory}/$project_key/$legacy_name"; do
    if [[ -L "$legacy_path" && ! -e "$legacy_path" ]]; then
      rm -f "$legacy_path"
      echo "ok removed the dangling $legacy_name link left by the rename: $legacy_path"
    fi
  done
done

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
