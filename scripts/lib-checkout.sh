# Sourced by memory-store.sh and memory-workplace.sh. Not a verb: the shim
# dispatches on scripts/<verb>.sh, and nothing dispatches here.
#
# Both verbs need the same four things from a memory checkout — refuse a
# directory holding somebody else's repository, refuse to clone inside another
# repository, clone or pull, enable the secret hook — and they used to carry
# two copies of it. The copies had already drifted (one said "check the ssh key
# for the GitLab host" while the other said "that host"), and the defect this
# file was written for lived in the half neither copy had: the URL was read
# only on the clone path, so an existing directory was adopted whatever it
# contained.
#
# One function, two callers, and the messages differ only by a label naming
# which of the two stores is being wired.

# ensure_checkout <url> <dir> <label>
# Leaves a usable checkout of <url> at <dir>, or prints why not and returns 1.
ensure_checkout() {
  ec_url="$1"; ec_dir="$2"; ec_label="$3"

  if [[ -d "$ec_dir/.git" ]]; then
    # The check the old code did not have. `origin` is what a push follows, so
    # it — not the path, and not the fact that a clone once succeeded here —
    # decides whether this directory is the configured repository.
    ec_have="$(git -C "$ec_dir" remote get-url origin 2>/dev/null || true)"
    if [[ -n "$ec_have" && "$ec_have" != "$ec_url" ]]; then
      echo "x $ec_dir holds a different repository than the $ec_label"
      echo "    configured: $ec_url"
      echo "    found here: $ec_have"
      echo "  Nothing was linked or written. Wiring this up would send notes to"
      echo "  the repository above, and every message would still say ok."
      echo "  Move that checkout aside, or set agents_memory_dir to another parent."
      return 1
    fi
    if [[ -z "$ec_have" ]]; then
      echo "! $ec_dir has no origin — cannot confirm it is the $ec_label"
    fi
    # The pre-agents_memory_dir layout: the checkout sits directly at the
    # parent instead of in a directory named for its URL. Its origin has just
    # proved it is the right repository, so adopt it and say so. Cloning a
    # second copy under it would split the notes across two working trees.
    if [[ "$ec_dir" == "${FLOPPY_AGENTS_MEMORY_DIR:-}" ]]; then
      echo "ok adopted the checkout at $ec_dir (origin matches; layout predates agents_memory_dir)"
    fi
    ec_dirty="$(git -C "$ec_dir" status --porcelain | wc -l | tr -d ' ')"
    if [[ "$ec_dirty" != "0" ]]; then
      echo "! $ec_dirty uncommitted change(s) in the $ec_label — pull skipped, commit them first"
    elif git -C "$ec_dir" pull --rebase --quiet 2>/dev/null; then
      echo "ok pulled"
    else
      echo "! pull failed (offline, or the remote refused) — working with the local copy"
    fi
  else
    if [[ -e "$ec_dir" ]]; then
      echo "x $ec_dir exists but is not a git repository — sort this out by hand"
      return 1
    fi
    # A checkout inside another checkout is the shape that makes `git add -A`
    # record a gitlink instead of the notes, and the notes then belong to
    # neither repository. It happens when the parent is itself the adopted
    # legacy checkout and a second URL wants a directory under it.
    # Walk up to the nearest ancestor that exists: the clone path now has a
    # .clones/ segment that git would create on the way, so testing only the
    # immediate parent would miss the case entirely and clone into the
    # repository below it.
    ec_parent="$(dirname "$ec_dir")"
    while [[ ! -d "$ec_parent" && "$ec_parent" != "/" && "$ec_parent" != "." ]]; do
      ec_parent="$(dirname "$ec_parent")"
    done
    if [[ -d "$ec_parent" ]] && ec_top="$(git -C "$ec_parent" rev-parse --show-toplevel 2>/dev/null)"; then
      ec_parent="$ec_top"
      echo "x $ec_parent is itself a git repository, so $ec_dir would be a repository inside a repository"
      echo "  That is the layout from before agents_memory_dir: one checkout at the parent."
      echo "  Give the parent a directory of its own, then run this again:"
      echo "      mv \"$ec_parent\" \"$ec_parent.moving\" && mkdir -p \"$ec_parent\" \\"
      echo "        && mv \"$ec_parent.moving\" \"$ec_parent/$(basename "$ec_parent")\""
      echo "  Nothing was cloned."
      return 1
    fi
    echo "cloning $ec_url"
    if ! git clone "$ec_url" "$ec_dir"; then
      echo "x clone failed — check the ssh key for that host"
      return 1
    fi
  fi

  # A repository can ship .githooks/pre-commit, git does not enable it on
  # clone, and a hook nobody enabled is a rule nobody enforces.
  if [[ -x "$ec_dir/.githooks/pre-commit" ]]; then
    if [[ "$(git -C "$ec_dir" config core.hooksPath || true)" == ".githooks" ]]; then
      echo "ok secret hook enabled"
    else
      git -C "$ec_dir" config core.hooksPath .githooks && echo "ok secret hook enabled: core.hooksPath=.githooks"
    fi
  else
    echo "! no executable .githooks/pre-commit in $ec_dir — secrets are guarded by nothing but the human"
  fi
  return 0
}

# view_link <key> <clone> <scope-subpath> <name>
# Builds the human-facing view: agents_memory_dir/<key>/<name> points at the
# scope inside the clone. The clones are named after repositories and the view
# is named after projects, which is what a person looks for; keeping both
# alphabets in one directory is what this separates.
#
# The link is RELATIVE whenever the clone sits under the same parent, so moving
# agents_memory_dir as a whole keeps every view working. It is never committed
# anywhere: the view lives outside any repository by construction.
view_link() {
  vl_key="$1"; vl_clone="$2"; vl_sub="$3"; vl_name="$4"
  vl_parent="${FLOPPY_AGENTS_MEMORY_DIR:-$HOME/agents_memory}"
  vl_view="$vl_parent/$vl_key"
  vl_path="$vl_view/$vl_name"
  mkdir -p "$vl_view"
  # The view sits at <parent>/<key>/, so ".." is the parent itself. The
  # clone-is-the-parent branch is the adopted legacy layout, where stripping a
  # "<parent>/" prefix that is not there would have produced "../<absolute
  # path>" — a link that resolves nowhere and fails only at the write probe.
  if [[ "$vl_clone" == "$vl_parent" ]]; then
    vl_target="../$vl_sub"
  elif [[ "$vl_clone" == "$vl_parent"/* ]]; then
    vl_target="../${vl_clone#"$vl_parent"/}/$vl_sub"
  else
    vl_target="$vl_clone/$vl_sub"
  fi
  if [[ -L "$vl_path" ]]; then
    if [[ -d "$vl_path" ]] && [[ "$(cd "$vl_path" && pwd -P)" == "$(cd "$vl_clone/$vl_sub" && pwd -P)" ]]; then
      echo "ok view already wired: $vl_path"
      return 0
    fi
    # Dangling: this verb made it, under a scope name that a later release
    # moved, and there is nothing behind it to lose. Same reasoning as the
    # consumer-side link in 0.5.1 — wiring is ours to repair. A view that
    # still RESOLVES somewhere else is a different matter and is refused.
    if [[ ! -e "$vl_path" ]]; then
      rm -f "$vl_path"
      ln -s "$vl_target" "$vl_path"
      echo "ok repointed the dangling view: $vl_path -> $vl_target"
      ignore_wiring_link "$vl_path"
      return 0
    fi
    echo "x $vl_path points at $(readlink "$vl_path"), not $vl_target"
    echo "  It may belong to another store. Remove it by hand and run this again."
    return 1
  fi
  if [[ -e "$vl_path" ]]; then
    echo "x $vl_path is a real directory, not a view into a memory repository"
    echo "  Nothing was moved or deleted: this script does not decide the fate of memory."
    return 1
  fi
  ln -s "$vl_target" "$vl_path"
  echo "ok view: $vl_path -> $vl_target"
  # In the adopted legacy layout the parent IS a checkout, so the view lands
  # inside it. A view is wiring like any other link here, and wiring does not
  # belong in anybody's history.
  ignore_wiring_link "$vl_path"
  return 0
}

# refuse_old_scope <clone> <old-relative> <new-relative> [recipe-line...]
# The scope names have changed twice (0.5.0, 0.6.0). Migrating them behind the
# human's back is
# exactly what this plugin refuses to do with memory, and doing it on ONE
# machine is worse than not doing it: until the other machine also runs 0.5.0,
# one writes the old path while the other reads the new one, and the memory
# forks with nothing red anywhere. So: refuse, and print the commands.
refuse_old_scope() {
  ro_clone="$1"; ro_old="$2"; ro_new="$3"; shift 3
  echo "x $ro_clone still uses an earlier scope layout"
  echo "    found:    $ro_old"
  echo "    expected: $ro_new"
  echo "  Update every machine that writes this repository FIRST. A half-migrated"
  echo "  pair of machines writes two scopes and neither one is complete."
  echo "  Then, once, on any of them:"
  for ro_line in "$@"; do echo "      $ro_line"; done
  echo "      git -C \"$ro_clone\" commit -m 'memory scope: $ro_new'"
  echo "      git -C \"$ro_clone\" push"
  echo "  Nothing was changed here."
  return 1
}

# ignore_wiring_link <link-path>
# A symlink that lands inside a git repository which is not the consumer's own
# is per-machine wiring, not memory: it holds an absolute path, so committed it
# dangles on every machine whose checkout lives elsewhere. Make that repository
# ignore it. Silent when the link is not inside another repository.
ignore_wiring_link() {
  iw_link="$1"
  iw_dir="$(dirname "$iw_link")"
  [[ -d "$iw_dir" ]] || return 0
  iw_top="$(git -C "$iw_dir" rev-parse --show-toplevel 2>/dev/null || true)"
  [[ -n "$iw_top" ]] || return 0
  [[ "$iw_top" != "$(cd "${FLOPPY_REPO:-.}" && pwd -P)" ]] || return 0
  iw_real_dir="$(cd "$iw_dir" && pwd -P)"
  iw_rel="${iw_real_dir#"$iw_top"/}/$(basename "$iw_link")"
  if git -C "$iw_top" check-ignore -q -- "$iw_rel" 2>/dev/null; then
    echo "ok $(basename "$iw_top") already ignores the wiring link $iw_rel"
  else
    printf '\n# per-machine wiring, not memory: an absolute symlink that is\n# recreated by "floppy workplace" on each machine\n/%s\n' "$iw_rel" \
      >> "$iw_top/.gitignore"
    echo "ok told $(basename "$iw_top") to ignore the wiring link $iw_rel (commit its .gitignore)"
  fi
}
