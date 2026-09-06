# Third-party code in this directory

Vendored rather than fetched at page load: a documentation site that reaches a
CDN on every visit acquires a runtime dependency and hands the reader's browser
to a third party. The versions are pinned for the same reason the Gemfile pins
the theme.

## lunr-languages 1.14.0

Files: `lunr.stemmer.support.js`, `lunr.ru.js`, `lunr.multi.js`, copied
unmodified from `https://unpkg.com/lunr-languages@1.14.0/`.

**License: MPL-1.1**, not MIT. The package's `package.json` declares
`"license": "MPL-1.1"` and its `LICENSE` file is the Mozilla Public License
1.1; the file headers name Mihai Valentin (lunr-languages) and Oleg Mazko
(the Snowball stemmer support) and point at `mozilla.org/MPL`. Checked against
those sources on 2026-09-06 rather than taken from a summary.

What that means here. MPL-1.1 is per-file copyleft: these three files stay
under it, keep their headers, and may be distributed inside a larger work under
other terms. The rest of this repository — the plugin itself, its skills,
scripts and shim — is MIT and unaffected; nothing outside `site/` uses them.
MPL-1.1 is not GPL-compatible, which matters only to someone redistributing
these files onward.

The full licence text is beside them in `LICENSE.lunr-languages.txt`, copied
from the same package — §3.7 lets a larger work be distributed as one product
"In such a case, You must make sure the requirements of this License are
fulfilled for the Covered Code", and shipping the text with the unmodified
source is what fulfilling them looks like.

They are used by `site/_includes/head_custom.html`, which is the only place
that loads them.

The site itself carries no licence notice for them, and does not need one: what
MPL-1.1 asks for is that these files keep their headers and that their source
stays available, which vendoring them unmodified into a public repository does.
A footer line would be a second place to keep in step with this one.
