#!/usr/bin/env bash
# Assemble the Jekyll sources for the documentation site into one directory.
# Usage: bash scripts/site-build.sh [outdir]        (default: .site)
#
# Why a build step instead of a docs/ folder Jekyll serves directly: every page
# of the site already exists as a document in this repository, and the moment a
# page is a second copy of one, the two start to differ — the README is guarded
# by tests/test-docs.sh, a hand-written landing page would be guarded by
# nothing. So nothing here is authored; each page is a document plus front
# matter, and tests/test-site.sh fails if a document has no page.
#
# Two things the copy needs that the source must not have:
#
#   Front matter. GitHub renders YAML front matter in README.md as a table at
#   the top of the repository's front page, so it cannot live in the file. It
#   is prepended here, to the copy.
#
#   Rewritten links. `[docs/lessons.md](docs/lessons.md)` resolves on GitHub
#   and 404s on the site, where there is no docs/ directory and pages are
#   .html. Every relative link is rewritten below: to a page, if the target has
#   one, and to the file on GitHub otherwise.
set -uo pipefail
cd "$(dirname "$0")/.."

out="${1:-.site}"
repo="https://github.com/spscream/ai-floppy"
blob="$repo/blob/main"

# ---------- the page table ----------
# source|target|title|nav_order — an empty source means the page is generated
# further down rather than copied. The order is the order of the sidebar, and
# it is the reading order: what the thing is, then the model behind it, then
# what the model cost to get right, then the reference, then the releases.
pages='README.md|index.md|Home|1
docs/memory-model.md|memory-model.md|The memory model|2
docs/lessons.md|lessons.md|Lessons|3
|skills.md|The five skills|4
CHANGELOG.md|changelog.md|Changelog|5'

# ---------- link rewriting ----------
# Built from the table, so a page added above is linkable from every other page
# without a second edit here. Both spellings of each source are covered: the
# README links to `docs/lessons.md`, and docs/lessons.md links to its sibling
# as `memory-model.md`.
rewrite=()
while IFS='|' read -r src tgt _title _order; do
  [[ -z "$src" ]] && continue
  html="${tgt%.md}.html"
  esc="${src//./\\.}"
  base="$(basename "$src")"; base="${base//./\\.}"
  # Relative, not rooted: the site is served under a baseurl (/ai-floppy), and
  # `/memory-model.html` would resolve above it. Every page sits in the same
  # directory, so the bare file name is both correct and baseurl-agnostic.
  rewrite+=(-e "s,\]\($esc\),]($html),g")
  rewrite+=(-e "s,\]\($base\),]($html),g")
done <<EOF
$pages
EOF
# Whatever is left pointing into the repository goes to GitHub. `[^):]*` is
# what keeps absolute URLs out of it: no repository-relative path contains a
# colon, and every http link does.
rewrite+=(-e "s,\]\(LICENSE\),](${blob}/LICENSE),g")
rewrite+=(-e "s,\]\(([^):]*\.md)\),](${blob}/\1),g")

# ---------- assemble ----------
rm -rf "$out"
mkdir -p "$out"
cp site/_config.yml site/Gemfile "$out/"

emit() { # target title nav_order  — body on stdin
  {
    printf -- '---\nlayout: default\ntitle: %s\nnav_order: %s\n---\n\n' "$2" "$3"
    sed -E "${rewrite[@]}"
  } > "$out/$1"
}

while IFS='|' read -r src tgt title order; do
  [[ -z "$src" ]] && continue
  emit "$tgt" "$title" "$order" < "$src"
  printf 'ok %s -> %s\n' "$src" "$tgt"
done <<EOF
$pages
EOF

# ---------- the generated page ----------
# The five skills, from the front matter each SKILL.md already carries — the
# same text the harness shows when it decides whether to invoke one. Listed in
# the order a session uses them, not alphabetically: `init` sets a repository
# up, `agent-memory` is the standing instruction, and the other three are the
# rites of one session.
{
  printf '# The five skills\n\n'
  printf 'Every entry below is the skill'"'"'s own `description` field, copied at\n'
  printf 'build time from `skills/<name>/SKILL.md`. That field is what the harness\n'
  printf 'reads when it decides whether a skill applies, so this page cannot describe\n'
  printf 'a skill differently from the way the agent sees it.\n\n'
  printf 'In Claude Code the names are namespaced by the plugin (`floppy:start`); in\n'
  printf 'Cursor they are flat (`/start`).\n\n'
  for name in init agent-memory start workstatus wrap; do
    f="skills/$name/SKILL.md"
    [[ -f "$f" ]] || { printf 'missing %s\n' "$f" >&2; exit 1; }
    desc="$(awk '/^description: /{sub(/^description: /,""); print; exit}' "$f")"
    printf '## `%s`\n\n%s\n\n[SKILL.md on GitHub](%s/%s)\n\n' \
      "$name" "$desc" "$blob" "$f"
  done
} | emit skills.md "The five skills" 4
printf 'ok skills/*/SKILL.md -> skills.md\n'

printf '\nsite assembled in %s\n' "$out"
