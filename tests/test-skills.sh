#!/usr/bin/env bash
# Structural check for skills/*/SKILL.md. Skills are prose, so there is
# nothing to assert about behaviour — this only guards the shape: valid
# frontmatter with name and description, name matching the directory, and no
# `allowed-tools` key anywhere. That last one is a regression guard: a probe
# skill carrying that key failed to load ("Execute skill" with no detail),
# removing it fixed loading, and putting it back broke it again with the
# plugin cache held constant. allowed-tools belongs to commands, not skills.
set -uo pipefail
cd "$(dirname "$0")/.."
. tests/lib.sh

skills=()
while IFS= read -r __f; do skills+=("$__f"); done < <(find skills -mindepth 2 -maxdepth 2 -name 'SKILL.md' | sort)

assert_eq "at least one skill found" "0" "$([[ ${#skills[@]} -gt 0 ]] && echo 0 || echo 1)"

for f in "${skills[@]}"; do
  dir="$(dirname "$f")"
  base="$(basename "$dir")"

  first="$(head -n1 "$f")"
  assert_eq "$f: starts with frontmatter fence" "---" "$first"

  fm="$(sed -n '2,/^---$/p' "$f")"

  name_val="$(printf '%s\n' "$fm" | sed -n 's/^name:[[:space:]]*//p' | head -n1)"
  desc_val="$(printf '%s\n' "$fm" | sed -n 's/^description:[[:space:]]*//p' | head -n1)"

  assert_eq "$f: name matches its directory" "$base" "$name_val"
  assert_eq "$f: description is present" "0" "$([[ -n "$desc_val" ]] && echo 0 || echo 1)"
done

# Regression guard: allowed-tools is a commands-only key. Any occurrence in
# skills/ (frontmatter or body) means a skill will fail to load.
hits="$(grep -rln 'allowed-tools' skills/ 2>/dev/null || true)"
assert_eq "no file in skills/ contains allowed-tools" "" "$hits"

# ---------- how a skill spells the dispatcher (0.26.0) ----------
# `.floppy/run` is no longer written into a consumer repository, so a skill
# that names it sends the agent at a file that exists only where an older
# `init` has been run. The call is the plugin's own dispatcher, reached from
# the base directory the harness states when it loads the skill.
#
# This is the guard that replaced tests/test-init-bootstrap.sh, which used to
# extract the init skill's hand copy of the plugin search and run it. That copy
# is gone (skills/init/SKILL.md §2), and what is left to protect is the
# spelling: a skill that names the old path, or one that uses the `<plugin>`
# placeholder without ever saying where it comes from, both leave the agent
# with a path it cannot resolve.
run_hits="$(grep -rln '\.floppy/run' skills/ 2>/dev/null || true)"
assert_eq "no skill names the consumer's .floppy/run" "" "$run_hits"

# Newlines folded to spaces before the match: the quoted line is prose and
# wraps at the file's margin, so the phrase is regularly split across two
# lines and a plain grep for it finds nothing.
#
# Three things are asserted of a skill that uses the placeholder, because two
# of them were measured as mutations the suite did not notice (2026-09-25):
# `<plugin>/run` instead of `<plugin>/scripts/run`, and "one directory above"
# instead of "two", each of which sends the agent at a path that does not
# exist while every test stays green. Resolving the placeholder against this
# checkout is as close to executing the instruction as prose allows.
for f in "${skills[@]}"; do
  case "$(cat "$f")" in
    *'<plugin>'*) ;;
    *) continue ;;
  esac
  folded="$(tr '\n' ' ' < "$f")"

  case "$folded" in
    *'Base directory for this skill'*)
      ok "$f: says where <plugin> comes from" ;;
    *)
      fail "$f: says where <plugin> comes from" \
        "the base-directory line the harness prints" "no such line" ;;
  esac

  case "$folded" in
    *'two directories above'*|*'two directories up'*)
      ok "$f: says how far above the base directory the plugin is" ;;
    *)
      fail "$f: says how far above the base directory the plugin is" \
        "two directories" "$(printf '%s' "$folded" | grep -o '[a-z]* director[a-z]* \(above\|up\)' | head -n1)" ;;
  esac

  missing=""
  while IFS= read -r ref; do
    [[ -n "$ref" ]] || continue
    rel="${ref#<plugin>/}"
    rel="${rel%.}"
    [[ -e "$rel" ]] || missing="$missing $ref"
  done < <(grep -o '<plugin>/[A-Za-z0-9_./-]*' "$f" | sort -u)
  assert_eq "$f: every <plugin>/… path it names exists in the plugin" "" "$missing"
done

summary
