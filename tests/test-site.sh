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
# Absolute and captured BEFORE the cd: the positive control at the end re-runs
# this file, and $0 is only whatever path the caller happened to use — which
# stops resolving the moment the cd below moves us to the repository root.
self="$(cd "$(dirname "$0")" && pwd)/$(basename "$0")"
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

# The search fix for non-Latin text is a Jekyll include, and Jekyll only sees
# an include that is in the root it was handed. Left in site/ and not copied,
# it would be a file that exists in the repository, passes review, and is
# absent from every deployed page. What these three asserts cannot check is the
# half that lives in the theme's gem and in a browser: that lunr still trims
# tokens the way it was measured to, and that the theme still includes this
# file at all. Both are pinned — just-the-docs 0.12.0 in the Gemfile — and
# neither is reachable from a suite that runs without Ruby or a network.
head_custom="$out/_includes/head_custom.html"
# The stemmer plugins are vendored (MPL-1.1 — see the NOTICE beside them) and
# loaded by that include. Copied but unreferenced is dead weight; referenced but
# uncopied is a 404 and a search that silently loses its Russian stemming, so
# both directions are asserted.
for v in lunr.stemmer.support.js lunr.ru.js lunr.multi.js NOTICE.md LICENSE.lunr-languages.txt; do
  assert_eq "build copies assets/js/vendor/$v" "0" \
    "$([[ -f "$out/assets/js/vendor/$v" ]] && echo 0 || echo 1)"
done
for v in lunr.stemmer.support.js lunr.ru.js lunr.multi.js; do
  assert_contains "the include loads $v" "$v" "$(cat "$out/_includes/head_custom.html" 2>/dev/null)"
done
assert_eq "build copies _includes/head_custom.html" "0" "$([[ -f "$head_custom" ]] && echo 0 || echo 1)"
assert_contains "the include replaces lunr's trimmer" \
  "lunr.trimmer =" "$(cat "$head_custom" 2>/dev/null)"
assert_contains "and re-registers it under the pipeline label" \
  "registerFunction(lunr.trimmer, 'trimmer')" "$(cat "$head_custom" 2>/dev/null)"

# And the half those three miss, which cost a merged-and-inert deploy: the
# theme serves the page as ONE line, so a `//` comment inside the script
# swallows every statement after it. The file was correct, the asserts above
# were green, and the override never ran in a browser.
script_body="$(sed -n '/<script>/,/<\/script>/p' "$head_custom" 2>/dev/null)"
assert_eq "the include's script carries no // comment" "0" \
  "$(printf '%s\n' "$script_body" | grep -c '^[[:space:]]*//')"
# Stronger, when the tool is here: collapse the script to one line exactly as
# the page does, and ask node whether it still parses. A skip is honest — this
# repository requires bash and git and nothing else.
if command -v node >/dev/null 2>&1; then
  # Two literal substitutions rather than one pattern with `\?`: that is a GNU
  # extension and BSD sed on the macOS runner does not read it, which would
  # leave the tags in and fail this check for the wrong reason.
  one_line="$(printf '%s\n' "$script_body" | sed -e 's,<script>,,' -e 's,</script>,,' | tr '\n' ' ')"
  printf '%s' "$one_line" > "$log.js"
  node --check "$log.js" >/dev/null 2>&1
  assert_rc "and still parses once the page collapses it to one line" "0" "$?"

  # The wrapper's own behaviour, against a stub lunr. The theme's real lunr
  # ships inside the gem and is not here, so what is proved is the half this
  # repository owns: that the wrapper installs itself, carries the statics the
  # theme reads, injects exactly one `use`, and still runs the config the theme
  # passed. A wrapper that swallowed that config would leave the site with no
  # index at all, and nothing else in CI would notice.
  cat > "$log.stub.js" <<'NODE'
global.window = global;
var fs = require('fs');
var base = function (config) {
  var builder = { used: [], theirs: false, use: function (x) { this.used.push(x); } };
  config.call(builder);
  return builder;
};
base.multiLanguage = function () { return function () {}; };
base.tokenizer = { separator: null };
base.Pipeline = { registerFunction: function () {} };
base.Query = { wildcard: { TRAILING: 2 } };
base.trimmer = function (t) { return t; };
global.lunr = base;
(0, eval)(fs.readFileSync(process.argv[2], 'utf8'));
var L = global.lunr;
function die(why) { console.log(why); process.exit(1); }
if (L === base) { die('the wrapper did not install itself'); }
if (!L.tokenizer || !L.Query || !L.Pipeline) { die('a static the theme reads was lost'); }
var built = L(function () { this.theirs = true; });
if (built.used.length !== 1) { die('expected exactly one use(), got ' + built.used.length); }
if (!built.theirs) { die("the theme's own config never ran"); }
NODE
  node "$log.stub.js" "$log.js" >/dev/null 2>&1
  assert_rc "the wrapper installs, keeps the statics and keeps the theme's config" "0" "$?"
  rm -f "$log.js" "$log.stub.js"
else
  printf '  skip node not available: the one-line parse check\n'
fi

# ---------- 1. every document reaches the site ----------
# Matched on the document's own first heading rather than on the build
# script's table: a table that lists a file it no longer copies would pass a
# table-reading test. A new docs/*.md with no page fails this loop.
# The document list is overridable only through this file's own self-invocation,
# which marks itself with an argument — see the positive control at the end. An
# environment variable was tried first and was wrong: one left over in a shell
# silently narrowed a normal run to a single document and still reported green,
# and a test that passes while checking less than it claims is worse than one
# that fails. An argument cannot arrive from the environment.
if [[ "${1:-}" == "--selftest" ]]; then
  docs_list="$2"
else
  docs_list="docs/*.md"
fi
# Unquoted on purpose: the default has to stay a glob.
for src in $docs_list; do
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
for ru_page in ru-index ru-memory-model ru-lessons; do
  assert_contains "the hub links to $ru_page"        "$ru_page.html" "$hub"
  assert_contains "$ru_page names its parent"        "parent: Русский" \
    "$(cat "$out/$ru_page.md" 2>/dev/null || true)"
done

# The same probe index.md gets, and for the same reason: a code identifier
# survives translation, so it proves the whole README came through rather than
# a truncated prefix of it.
assert_contains "the Russian index carries the whole README" "## \`quota.lock\`" \
  "$(cat "$out/ru-index.md" 2>/dev/null || true)"

# The marker is an implementation detail of the repository, not of the site.
assert_eq "no page carries a translation marker" "" \
  "$(grep -l 'floppy:translation' "$out"/*.md 2>/dev/null | tr '\n' ' ' | sed 's/ *$//')"

# ---------- positive control: the heading guard can go red ----------
# The guard lives inside this file, so unlike tests/test-knowledge.sh — which
# exercises its checkers by running them as separate programs — this file has to
# run ITSELF to prove the guard fires. The first version of this control only
# asserted that `grep -m1 '^# '` prints nothing for a headingless file, which is
# a fact about grep: it passed with the guard deleted, and it was found that way.
#
# The planted document goes in a temp directory, never in the live docs/. Two
# reasons: tests/run.sh runs test files in parallel, so a stray docs/*.md is
# visible to whatever else is running; and a signal landing between creating and
# deleting it would leave debris inside a tracked directory.
if [[ "${1:-}" != "--selftest" ]]; then
  probe_dir="$(mktemp -d)"
  probe_doc="$probe_dir/zz-no-heading.md"
  printf '## Only a subheading\n\nbody\n' > "$probe_doc"
  # $BASH, not a bare `bash`: same reason tests/run.sh gives — on macOS the
  # point is to exercise 3.2, and a bare `bash` resolves through PATH.
  probe_out="$("${BASH:-bash}" "$self" --selftest "$probe_doc" 2>&1)"
  probe_rc=$?
  rm -rf "$probe_dir"
  assert_eq "the heading guard fails a document with no heading" "1" "$probe_rc"
  # The needle spans FAIL and the document's own path. The assertion's name
  # alone would not do: it prints on the `ok` line too, so a guard that had been
  # made unfailable rather than deleted could still match it.
  assert_contains "and the failure names the guard" \
    "FAIL $probe_doc has a top-level heading to match on" "$probe_out"
fi

summary
