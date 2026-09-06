---
name: lunr-trimmer-drops-non-latin-tokens
description: lunr indexes every non-Latin word as the empty string, because its trimmer strips \W from both ends of a token and JavaScript's \w is ASCII-only — the tokenizer is not involved, so tokenizer_separator is the wrong place to look
area: practice
verified_on: 2026-09-06
verified_against: "lunr 2.3.9 as shipped by just-the-docs 0.12.0; measured against a deployed site with Russian pages; Node 18.14.2"
recheck: "In a page with lunr loaded: `lunr.trimmer(new lunr.Token('память')).toString()` returns ''. Against a whole site, rebuild its index from the served search-data.json and count how many terms of `Object.keys(idx.invertedIndex)` contain non-Latin characters."
invalidated_by: "lunr changes its default trimmer to a Unicode-aware one, or the site adds lunr-languages, which replaces the pipeline"
requires: command -v node >/dev/null 2>&1
recheck_cmd: node -e 'var trim=function(s){return s.replace(/^\W+/,"").replace(/\W+$/,"")}; console.log((trim("память")===""?"empty":trim("память")) + " " + trim("memory"))'
expect: empty memory
---

# lunr indexes a Russian word as the empty string

## The fact

`lunr.trimmer` is the last step of lunr's **indexing** pipeline, and it strips
`/^\W+/` and `/\W+$/` from every token. In JavaScript `\w` means
`[A-Za-z0-9_]` — ASCII only — so a word written entirely in a non-Latin script
is `\W` from end to end and trims to `""`. Every such word lands under one
empty-string term, and searching for any of them returns nothing.

The tokenizer is **not** involved: it splits `память сессии` into two tokens
correctly. A site whose search fails on non-Latin text is therefore not fixed by
changing `lunr.tokenizer.separator`, which is where the setting with the obvious
name lives.

## Why it is not obvious

Search failing on one alphabet reads as a tokenizer problem — that is the
component whose job is deciding where words begin, and in most search engines it
is the locale-dependent part. lunr's tokenizer is locale-independent and fine.
The pipeline step that breaks is named for trimming punctuation, which sounds
like it could not possibly delete a word.

The evidence is also misleading at a glance: the index data is intact. The
documents are there, their text is there, the term count looks plausible. The
loss happens between the tokenizer and the inverted index, and only shows up if
you list the terms.

## Evidence

**MEASURED**, 2026-09-06, against a deployed just-the-docs site with three
Russian pages, by re-running the site's own index construction and query code
over its served `search-data.json`:

| | as served | with a Unicode-aware trimmer |
|---|---|---|
| terms in the index | 1855 | 3675 |
| terms containing Cyrillic | **2** | 1827 |
| `память` / `сессия` / `заметка` | 0 / 0 / 0 hits | 13 / 5 / 9 |
| `memory` / `wrap` | 71 / 30 | 71 / 30 |

The two surviving Cyrillic terms were URL values carrying ASCII alongside the
Cyrillic, which is why trimming the ends left them alone. One empty-string term
held 124 postings. All 38 Russian index entries carried their full text.

**MEASURED** for the language half, and the whole mechanism in one line — the
`recheck_cmd` above trims both words the way lunr does and prints `empty
memory`: the Russian word is gone, the English one is untouched.

**READ, not measured:** that `lunr.trimmer` is in the default indexing pipeline
— from lunr's source, where `lunr()` adds `lunr.trimmer`, `lunr.stopWordFilter`
and `lunr.stemmer` to the builder.

## How to re-check

The one-liner above proves the mechanism. To find out whether a particular site
suffers from it, fetch its `search-data.json` and its `lunr.min.js`, rebuild the
index the way the site's own code does, and count the terms containing
characters outside ASCII. A site whose content is non-Latin and whose index has
almost none has this bug.

## What it costs you not to know

A documentation site with content in Russian, Greek, Hebrew, Arabic, Japanese
or Chinese ships a search box that silently returns nothing for its own text,
while working perfectly for the English words scattered through it — which is
what the author will type when testing. Both fixes are small once the cause is
known: replace the trimmer with `\p{L}\p{N}` (Unicode property escapes), or add
`lunr-languages`, which replaces the pipeline outright and adds stemming. The
expensive part is looking in the tokenizer for a week.

## See also

- [[one-line-page-eats-a-line-comment]] — how the first fix for this shipped
  inert and stayed green
