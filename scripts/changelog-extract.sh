#!/usr/bin/env bash
# Print one version's CHANGELOG section — the body of its GitHub release.
# Usage: bash scripts/changelog-extract.sh <version> [changelog-file]
#
# Exists for the release workflow (.github/workflows/release.yml): tags and
# the releases page were a by-hand step after each version bump, and by-hand
# steps stop happening — the page sat at 0.20.0 while the manifests shipped
# 0.23.0 (noticed 2026-09-13; between 0.14.0 and 0.16.2 the same gap had
# already eaten five releases the other way round, see tests/test-release.sh).
# The workflow needs the entry as a file, and the extraction is here rather
# than inline in YAML so the suite can test it on the bash the workflow does
# not run: macOS /bin/bash 3.2.
#
# The heading itself is not printed — the release title already carries the
# version. A missing entry is a loud rc-1 failure, never empty output: empty
# release notes would ship and nobody would look back.
set -uo pipefail

ver="${1:-}"
file="${2:-CHANGELOG.md}"

if [[ -z "$ver" ]]; then
  echo "usage: bash scripts/changelog-extract.sh <version> [changelog-file]" >&2
  exit 2
fi

[[ -f "$file" ]] || { echo "x no changelog at $file" >&2; exit 1; }

# Sections open with `## <version> — <date>`; $2 of that line is the version,
# compared whole — a BRE would let 0.2.0 match 0.2.0.1's heading.
if ! awk -v v="$ver" '
  /^## / { if (found) exit; if ($2 == v) { found = 1; next } }
  found  { print }
  END    { exit found ? 0 : 1 }
' "$file"; then
  echo "x no changelog entry for $ver in $file" >&2
  exit 1
fi
