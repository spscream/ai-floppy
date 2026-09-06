#!/usr/bin/env bash
# CRITICAL 2: the documentation site is generated from the documents, never
# written a second time by hand. Structural, like test-docs.sh — there is no
# behaviour to run, only shape to guard, and the shape that matters is that no
# page on the site is a copy someone has to remember to update.
#
# The three things that can rot here, in the order they will:
#   1. a new file lands in docs/ and nothing puts it on the site;
#   2. a link that reads fine on GitHub (`docs/lessons.md`) ships to the site
#      unrewritten and 404s, because on the site there is no docs/ directory;
#   3. the workflow stops calling the build script, and the site keeps
#      deploying whatever it built last — green, and months out of date.
# One assert each, below.
set -uo pipefail
cd "$(dirname "$0")/.."
. tests/lib.sh

out="$(cd "$(mktemp -d)" && pwd -P)/site"
log="$(mktemp)"
trap 'rm -rf "$out" "$log"' EXIT

bash scripts/site-build.sh "$out" > "$log" 2>&1
assert_rc "site-build.sh succeeds" "0" "$?"

# The Jekyll build needs both of these in the assembled root; the workflow
# never copies them itself.
assert_eq "build copies _config.yml" "0" "$([[ -f "$out/_config.yml" ]] && echo 0 || echo 1)"
assert_eq "build copies Gemfile"     "0" "$([[ -f "$out/Gemfile"     ]] && echo 0 || echo 1)"

# ---------- 1. every document reaches the site ----------
# Matched on the document's own first heading rather than on the build
# script's table: a table that lists a file it no longer copies would pass a
# table-reading test. A new docs/*.md with no page fails this loop.
for src in docs/*.md; do
  # The first heading, not the first line: a translation's first line is the
  # marker, and the marker is stripped from the page.
  h1="$(grep -m1 '^# ' "$src")"
  # An empty needle would make `grep -qF` below match any non-empty line, and
  # the document would "reach the site" with nothing actually checked. A
  # docs/*.md with no `# ` heading is therefore a failure here, not a pass:
  # this loop is the guard against a document nobody publishes, and a guard
  # that cannot fail is indistinguishable from one that was never wired up.
  assert_eq "$src has a top-level heading to match on" "0" \
    "$([[ -n "$h1" ]] && echo 0 || echo 1)"
  found=1
  for page in "$out"/*.md; do
    if grep -qF "$h1" "$page"; then found=0; break; fi
  done
  assert_eq "site carries $src" "0" "$found"
done

index="$(cat "$out/index.md" 2>/dev/null || true)"
assert_contains "index is the README"          "$(head -1 README.md)" "$index"
assert_contains "index carries the whole README" "## \`quota.lock\`"   "$index"
# Against the version the plugin actually ships, not a version spelled out
# here: a release that moves plugin.json and forgets the changelog publishes a
# site whose newest entry is the release before it, and nothing says so.
version="$(grep -m1 '"version"' .claude-plugin/plugin.json | sed 's/.*: *"//; s/".*//')"
assert_contains "changelog page covers the shipped version ($version)" "## $version" \
  "$(cat "$out/changelog.md" 2>/dev/null || true)"

# The README stays a README: Jekyll front matter in it would render as a table
# at the top of the repository's front page. The site's copy gets the front
# matter; the source never does.
assert_eq "README.md has no front matter" "# floppy" "$(head -1 README.md)"

# ---------- 2. no link survives that only works on GitHub ----------
# `[^):]*` skips absolute URLs — no repository-relative path contains a colon,
# every http link does.
assert_eq "no page links to a .md file" "" \
  "$(grep -hoE '\]\([^):]*\.md\)' "$out"/*.md | sort -u | tr '\n' ' ' | sed 's/ *$//')"

# ...and none of them resolves by leaving the site. The builder's last rule
# sends anything it does not recognise to the file on GitHub, so a page-link
# rule that stops working does not break a link — it silently degrades into a
# working link to the wrong place, and the reader leaves mid-sentence. Found by
# deleting that rule and watching the assert above stay green.
assert_eq "no page sends the reader to GitHub for a document the site carries" "" \
  "$(grep -hoE '\]\(https://github\.com/[^)]*/blob/main/(README\.md|CHANGELOG\.md|docs/[^)]*)\)' "$out"/*.md \
     | sort -u | tr '\n' ' ' | sed 's/ *$//')"

# Front matter present and orderable on every page: a missing nav_order sorts
# a page to the end of the sidebar silently, a repeated one orders two pages by
# title instead of by intent.
pages_n="$(ls "$out"/*.md | wc -l | tr -d ' ')"
assert_eq "every page has a title"     "$pages_n" "$(grep -hc '^title: '     "$out"/*.md | awk '{s+=$1} END {print s+0}')"
assert_eq "every page has a nav_order" "$pages_n" "$(grep -hc '^nav_order: ' "$out"/*.md | awk '{s+=$1} END {print s+0}')"
# Uniqueness is per parent, not global. That changed when pages got children:
# just-the-docs orders children within their parent, so the Russian pages'
# 1-2-3 legitimately repeats the top level's. Same guard, correct group.
dupes="$(for page in "$out"/*.md; do
  p="$(awk -F': ' '/^parent: /{print $2; exit}' "$page")"
  n="$(awk -F': ' '/^nav_order: /{print $2; exit}' "$page")"
  printf '%s\t%s\n' "${p:-<top level>}" "$n"
done | sort | uniq -d | tr '\n' ' ' | sed 's/ *$//')"
assert_eq "nav_order values are unique within each parent" "" "$dupes"

# ---------- the skills page is generated, not typed ----------
# Asserted on each skill's own description text, not on its name: a hand-typed
# list would carry the names and drift on the descriptions, which is exactly
# the failure this page exists to prevent.
skills="$(cat "$out/skills.md" 2>/dev/null || true)"
for f in skills/*/SKILL.md; do
  name="$(awk '/^name: /{sub(/^name: /,""); print; exit}' "$f")"
  desc="$(awk '/^description: /{sub(/^description: /,""); print; exit}' "$f")"
  assert_contains "skills page names \`$name\`"            "$name"                  "$skills"
  assert_contains "skills page carries $name's description" "${desc:0:60}"          "$skills"
done

# ---------- 3. the deploy actually runs the build ----------
# Testing the path, not the script: everything above passes just as well when
# the workflow builds some other directory and the site never changes again.
wf="$(cat .github/workflows/pages.yml 2>/dev/null || true)"
assert_contains "pages workflow runs the build script" "scripts/site-build.sh" "$wf"
assert_contains "pages workflow deploys what it built" "actions/deploy-pages" "$wf"
assert_contains "pages workflow builds the assembled root" ".site" "$wf"

# The build directory is a build directory: committing it would put a second,
# stale copy of every document into the repository — the one thing this whole
# arrangement exists to avoid.
assert_contains "the build directory is ignored" ".site/" "$(cat .gitignore)"

# ---------- the Russian pages sit under one navigation group ----------
# The hub is built before there is anything under it. That is deliberate: the
# machinery lands here, the first document lands in the next commit, and neither
# commit leaves the suite red.
hub="$(cat "$out/ru.md" 2>/dev/null || true)"
assert_contains "the Russian hub exists"       "title: Русский"     "$hub"
assert_contains "and declares itself a parent" "has_children: true" "$hub"

# The marker is an implementation detail of the repository, not of the site.
assert_eq "no page carries a translation marker" "" \
  "$(grep -l 'floppy:translation' "$out"/*.md 2>/dev/null | tr '\n' ' ' | sed 's/ *$//')"

# ---------- the heading guard can actually go red ----------
# A positive control on the loop above. Without it, the fix is a line of code
# nobody has ever seen fail — the same class of thing it was added to prevent.
probe=docs/zz-probe-no-heading.md
printf '## Only a subheading\n\nbody\n' > "$probe"
probe_h1="$(grep -m1 '^# ' "$probe")"
rm -f "$probe"
assert_eq "a document with no top-level heading yields an empty needle" "" "$probe_h1"

summary
