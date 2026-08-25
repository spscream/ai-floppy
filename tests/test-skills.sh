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

summary
