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
docs/guide/install.md|install.md|Install & init|2
docs/guide/config.md|config.md|Config reference|3
docs/guide/skills.md|skills.md|The six skills|4
|knowledge.md|The knowledge base|5
|behind.md|Behind it|6
docs/memory-model.md|memory-model.md|The memory model|1|Behind it
docs/lessons.md|lessons.md|Lessons|2|Behind it
CHANGELOG.md|changelog.md|Changelog|7
|ru.md|Русский|8
README.ru.md|ru-index.md|floppy по-русски|1|Русский
docs/guide/install.ru.md|ru-install.md|Установка и init|2|Русский
docs/guide/config.ru.md|ru-config.md|Справочник конфигурации|3|Русский
docs/guide/skills.ru.md|ru-skills.md|Шесть скиллов|4|Русский
docs/memory-model.ru.md|ru-memory-model.md|Модель памяти|5|Русский
docs/lessons.ru.md|ru-lessons.md|Уроки|6|Русский'

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
  # A page under docs/guide/ has to climb out to reach a sibling written at the
  # repository root — `../memory-model.md` — and the bare-basename rule above
  # did not recognise the climbed form, so the link fell through to the
  # catch-all and left for GitHub with an unnormalised `..` in the URL
  # (measured on docs/guide/config.md, both languages). `(\.\./)*` accepts any
  # number of leading climbs, including zero.
  rewrite+=(-e "s,\]\((\.\./)*$base\),]($html),g")
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
# The includes travel too. Jekyll reads _includes/ from the root it is
# handed, and this root is assembled from scratch on every build, so an
# include left behind in site/ is one the deployed site does not have.
cp -R site/_includes "$out/"
# Same for the vendored search plugins under assets/ — see NOTICE.md there.
cp -R site/assets "$out/"

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
  # A row whose document is gone used to print `ok` for a page it never wrote.
  # Measured 2026-09-08 by deleting docs/guide/config.md and keeping its row:
  # the redirect below failed on stderr, `set -e` is deliberately not on here,
  # the loop carried on, this line claimed the copy, the build exited 0 — and
  # the whole suite stayed green at 88 passed, 0 failed while the home page
  # linked to a config.html nobody had written. Same refusal the skills block
  # below already makes, for the same reason.
  [[ -f "$src" ]] || { printf 'missing %s — the page table lists it\n' "$src" >&2; exit 1; }
  emit "$tgt" "$title" "$order" "$parent" < "$src"
  printf 'ok %s -> %s\n' "$src" "$tgt"
done <<EOF
$pages
EOF

# ---------- the skills page: prose from the guide, descriptions generated ----------
# The descriptions are each SKILL.md's own `description` field, read at build
# time, so the site cannot describe a skill differently from the way the harness
# reads it. That property predates the guide page and has to survive it, so the
# page is a source document with one placeholder rather than a generated page:
# a generated page with no source row would fall out of test-site.sh's "every
# document reaches the site" loop.
skills_block="$(
  for name in init agent-memory start workstatus wrap consolidate; do
    f="skills/$name/SKILL.md"
    [[ -f "$f" ]] || { printf 'missing %s\n' "$f" >&2; exit 1; }
    desc="$(awk '/^description: /{sub(/^description: /,""); print; exit}' "$f")"
    printf '### `%s`\n\n%s\n\n[SKILL.md on GitHub](%s/%s)\n\n' \
      "$name" "$desc" "$blob" "$f"
  done
)" || exit 1
# Written to a file and spliced with `r`, not passed through sed's replacement
# text: the descriptions contain `&`, `/` and newlines, all of which a
# replacement string would eat or mangle.
printf '%s\n' "$skills_block" > "$out/.skills-block"
for page in skills.md ru-skills.md; do
  [[ -f "$out/$page" ]] || continue
  sed -e '/<!-- floppy:generated skills-list -->/{r '"$out"'/.skills-block' -e 'd;}' \
    "$out/$page" > "$out/$page.tmp" && \mv -f "$out/$page.tmp" "$out/$page"
done
rm -f "$out/.skills-block"
printf 'ok skills/*/SKILL.md -> skills.md, ru-skills.md\n'

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
} | emit knowledge.md "The knowledge base" 5
printf 'ok knowledge/notes/**/*.md -> knowledge.md\n'

# ---------- the "Behind it" hub ----------
# Two documents a user does not need to install or run floppy, and does need
# before changing it: the model the paths are moving towards, and what the
# mistakes behind them cost. They sat at the top level until 2026-09-08, next
# to the reference, which is where a reader looking for the reference found
# them first. Generated by filtering the table on `parent`, for the reason the
# Russian hub gives: a hand-written child list is a second copy of the table.
{
  printf '# Behind it\n\n'
  printf 'Why floppy is shaped this way. Neither page is needed to use the\n'
  printf 'plugin; both are needed to change it without repeating something\n'
  printf 'that has already been paid for once.\n\n'
  while IFS='|' read -r _src tgt title _order parent; do
    [[ "$parent" == "Behind it" ]] || continue
    printf -- '- [%s](%s)\n' "$title" "${tgt%.md}.html"
  done <<EOF
$pages
EOF
} | emit behind.md "Behind it" 6 "" 1
printf 'ok the page table -> behind.md\n'

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
} | emit ru.md "Русский" 8 "" 1
printf 'ok the page table -> ru.md\n'

printf '\nsite assembled in %s\n' "$out"
