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
    ec_parent="$(dirname "$ec_dir")"
    if [[ -d "$ec_parent" ]] && git -C "$ec_parent" rev-parse --show-toplevel >/dev/null 2>&1; then
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
