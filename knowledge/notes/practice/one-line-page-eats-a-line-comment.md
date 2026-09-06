---
name: one-line-page-eats-a-line-comment
description: A template that serves HTML as a single line deletes every newline inside an inline <script>, so one // comment silences the whole script and automatic semicolon insertion stops working — the file stays correct, the page does nothing, and file-reading tests stay green
area: practice
verified_on: 2026-09-06
verified_against: "Jekyll 4.4.1 with just-the-docs 0.12.0 on GitHub Pages; the JavaScript half is language behaviour, checked on Node 18.14.2"
recheck: "Fetch a page the template serves and count newlines inside its inline <script>: `curl -s <url> | node -e 'let h=\"\";process.stdin.on(\"data\",d=>h+=d).on(\"end\",()=>{const m=h.match(/<script>([\\s\\S]*?)<\\/script>/);console.log((m[1].match(/\\n/g)||[]).length)})'` — zero means the collapse is happening."
invalidated_by: "The template stops compressing whitespace, or the script moves to an external file with its own newlines"
requires: command -v node >/dev/null 2>&1
recheck_cmd: node -e 'var x=0; (0,eval)("// c\nx=1;".replace(/\n/g," ")); var a=[x===0?"comment-ate-it":"ran"]; try { new Function("a.b = function(){}  a.c();"); a.push("asi-ok"); } catch(e) { a.push("asi-fails"); } console.log(a.join(" "));'
expect: comment-ate-it asi-fails
---

# An inline script served on one line is one `//` away from doing nothing

## The fact

Some site generators and themes serve HTML with the whitespace collapsed — the
whole page arrives as a single line. Every newline inside an inline `<script>`
goes with it, and two things break that are correct in the source file:

- **a `//` comment swallows the rest of the script.** Everything after it on
  that line is comment, and the line is now the entire file.
- **automatic semicolon insertion stops working.** ASI needs a line terminator,
  so `a.b = function () {}` followed by `a.c()` — legal across two lines —
  becomes `SyntaxError: Unexpected identifier`.

The failure is silent in the first case: the browser parses a file that
contains nothing, reports no error, and the page behaves as if the script were
never added.

## Why it is not obvious

Nothing at authoring time hints at it. The file on disk is correct, a linter
reads it as correct, and any test that reads the file finds exactly what it
expects. The transformation happens in the template layer, between the file and
the reader, and it is normally invisible because HTML does not care about
newlines — only JavaScript does, in exactly these two places.

It also survives review. A reviewer reads the source file, where the comment
sits on its own line above the code it describes, which is what good code looks
like.

## Evidence

**MEASURED**, 2026-09-06, on a Jekyll 4.4.1 + just-the-docs 0.12.0 site served
from GitHub Pages. A script added through `_includes/head_custom.html` was
merged and deployed, and did nothing. On the served page the script was present
and contained **0 newlines**; the state it was supposed to change was
unchanged. Turning the `//` comments into a block comment produced the second
defect immediately: the collapsed script was a syntax error until every
statement was given an explicit `;`.

**MEASURED**, same day, for the language half — the two behaviours reduced to
one command, which is `recheck_cmd` above:

```
$ node -e 'var x=0; (0,eval)("// c\nx=1;".replace(/\n/g," ")); ...'
comment-ate-it asi-fails
```

**READ, not measured:** which generators compress this way and which do not.
Only the one above was checked.

## How to re-check

`recheck_cmd` proves the JavaScript half anywhere node exists, and is skipped
otherwise. For the template half — whether *your* pages arrive collapsed — the
`recheck` line fetches a page and counts the newlines inside its inline script.
Zero means every rule above applies to you.

## What it costs you not to know

An analytics snippet, a polyfill, a search-index tweak: merged, reviewed,
deployed, and inert. Tests that assert the file contains the code stay green,
because it does. The bug is invisible to every check that does not look at the
served artifact, and the usual first suspicion — that the code is wrong — is
false, which costs a second round of debugging on code that was always correct.

## See also

- [[form-checks-cannot-see-false]] — a check that reads the shape of a thing
  rather than its behaviour
- [[guard-must-refuse-when-blind]] — the same shape of failure: a check that
  cannot see its subject should not report success
