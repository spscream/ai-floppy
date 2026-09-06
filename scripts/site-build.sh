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
# source|target|title|nav_order[|parent] — an empty source means the page is generated
# further down rather than copied. The order is the order of the sidebar, and
# it is the reading order: what the thing is, then the model behind it, then
# what the model cost to get right, then the reference, then the releases.
pages='README.md|index.md|Home|1
docs/memory-model.md|memory-model.md|The memory model|2
docs/lessons.md|lessons.md|Lessons|3
|knowledge.md|The knowledge base|4
|skills.md|The five skills|5
CHANGELOG.md|changelog.md|Changelog|6
|ru.md|Русский|7
docs/memory-model.ru.md|ru-memory-model.md|Модель памяти|2|Русский'

# ---------- link rewriting ----------
# Built from the table, so a page added above is linkable from every other page
# without a second edit here. Both spellings of each source are covered: the
# README links to `docs/lessons.md`, and docs/lessons.md links to its sibling
# as `memory-model.md`.
rewrite=()
while IFS='|' read -r src tgt _title _order _parent; do
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
# The knowledge base has a page but no source row: its page is generated from
# knowledge/README.md plus the notes, so the loop above cannot derive this. Without
# it a document linking to the base would be sent to GitHub for something the site
# already carries.
rewrite+=(-e "s,\]\(knowledge/README\.md\),](knowledge.html),g")
rewrite+=(-e "s,\]\(LICENSE\),](${blob}/LICENSE),g")
rewrite+=(-e "s,\]\(([^):]*\.md)\),](${blob}/\1),g")

# The marker records which version of the English file a translation was made
# from. That is a fact about the repository, and it has no business on a page.
rewrite+=(-e '/^<!-- floppy:translation /d')

# ---------- assemble ----------
rm -rf "$out"
mkdir -p "$out"
cp site/_config.yml site/Gemfile "$out/"

emit() { # target title nav_order [parent] [has_children]  — body on stdin
  {
    printf -- '---\nlayout: default\ntitle: %s\nnav_order: %s\n' "$2" "$3"
    [[ -n "${4:-}" ]] && printf 'parent: %s\n' "$4"
    [[ -n "${5:-}" ]] && printf 'has_children: true\n'
    printf -- '---\n\n'
    sed -E "${rewrite[@]}"
  } > "$out/$1"
}

while IFS='|' read -r src tgt title order parent; do
  [[ -z "$src" ]] && continue
  emit "$tgt" "$title" "$order" "$parent" < "$src"
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
} | emit skills.md "The five skills" 5
printf 'ok skills/*/SKILL.md -> skills.md\n'

# ---------- the knowledge base page ----------
# Same shape as the skills page and for the same reason: the note list is the
# notes' own front matter, read at build time, so the site cannot describe a
# note differently from the file. knowledge/README.md carries the prose; there
# is no hand-written index anywhere to drift from this.
#
# The notes live outside docs/ deliberately. A page that links to a docs/ file
# with no page of its own degrades into a GitHub link, and tests/test-site.sh
# fails exactly that — the reader would leave the site mid-sentence.
# Strip the YAML quotes only when they wrap the WHOLE value. Stripping each end
# independently mangles a value that legitimately ends in a quoted word: a
# description closing on `reports "clean"` lost its final quote, and the only
# symptom was the page test failing to find the text it had just been handed.
front() { awk -v k="$2: " 'index($0, k) == 1 { sub("^" k, ""); if ($0 ~ /^".*"$/) { sub(/^"/, ""); sub(/"$/, "") } print; exit }' "$1"; }
{
  cat knowledge/README.md
  printf '\n## The notes\n\n'
  printf 'Each entry is generated from the note'"'"'s own front matter: what it claims,\n'
  printf 'what it was verified against, and how to check it is still true.\n\n'
  for area in harness memory shell practice; do
    listed=0
    for f in knowledge/notes/"$area"/*.md; do
      [[ -f "$f" ]] || continue
      if [[ $listed -eq 0 ]]; then printf '### %s\n\n' "$area"; listed=1; fi
      printf '**%s**\n\n' "$(front "$f" description)"
      printf -- '- verified %s against %s\n' "$(front "$f" verified_on)" "$(front "$f" verified_against)"
      printf -- '- recheck: `%s`\n' "$(front "$f" recheck)"
      # Whether a person or a machine stands behind the claim is the first thing a
      # reader wants and the last thing such a list usually says.
      if [[ -n "$(front "$f" recheck_cmd)" ]]; then
        where="$(front "$f" platforms)"; [[ -n "$where" ]] || where="any platform"
        printf -- '- checked by machine on %s — `scripts/knowledge-recheck.py`\n' "$where"
      else
        printf -- '- confirmed by a person, not by a runnable check\n'
      fi
      printf -- '- [the note on GitHub](%s/%s)\n\n' "$blob" "$f"
    done
  done
} | emit knowledge.md "The knowledge base" 4
printf 'ok knowledge/notes/**/*.md -> knowledge.md\n'

# ---------- the Russian hub ----------
# Generated from the table for the same reason every other page is: a
# hand-written list of the Russian pages would be a second copy of the table,
# and the two would differ the first time a page was added.
{
  printf '# Русский\n\n'
  printf 'Документация floppy на русском языке. Английские файлы в репозитории —\n'
  printf 'источник: перевод сделан от конкретной их версии и помнит, от какой.\n'
  printf 'Если источник ушёл вперёд, это видно `scripts/translation-check.py`.\n\n'
  while IFS='|' read -r _src tgt title _order parent; do
    [[ "$parent" == "Русский" ]] || continue
    printf -- '- [%s](%s)\n' "$title" "${tgt%.md}.html"
  done <<EOF
$pages
EOF
} | emit ru.md "Русский" 7 "" 1
printf 'ok the page table -> ru.md\n'

printf '\nsite assembled in %s\n' "$out"
