<!--
SPDX-FileCopyrightText: 2026 Kaito Udagawa <umireon@kaito.tokyo>

SPDX-License-Identifier: Apache-2.0
-->

# site

A first, simple static site built from the token stream of `../tokens`.

## Requirements (Ubuntu 24.04)

```
apt-get install --no-install-recommends python3 nodejs node-mathjax-full
```

## Usage

```
../tokens/run.sh path/to/draft/source tokens.jsonl
./build_site.py tokens.jsonl out/
python3 -m http.server -d out/
```

## What it makes

* one page per clause or annex (`\rSec0`), named after its stable name
  (`basic.html`), with `<section id="STABLE.NAME">` for each subclause;
* one page per part of the back matter (`back1.html`, …: bibliography,
  cross-references, the indexes), split at the `part` marks;
* `index.html`, the clauses and annexes with their first-level subclauses.

The front matter (cover, foreword, table of contents) is left out.

Tokens become HTML as follows: `par` starts a paragraph, `nl` is a space
(a line break in code blocks), notes and examples are `<div>`s, code blocks
`<pre><code>`, `tcode` `<code>`, `grammarterm` `<i>`, `defn` `<dfn>`,
anchors empty `<span id>`s, links `<a>` to the page holding the anchor.

Formulas are typeset into SVG at build time by MathJax 3 for Node
(`render-math.js`), the same TeX input as `../tokens/check-math.js`, so the
pages need no script. (The browser build of MathJax in Ubuntu's
`node-mathjax-full`, `es5/`, fails in the browser with "Class constructor
cannot be invoked without 'new'".)

For draft `d4d6f381` the build takes about 5 seconds and writes 42 pages,
29 MB in all.

## Known gaps

Everything the token stream does not mark is plain text: list items,
tables, footnotes (placed where TeX put them, at the foot of a page),
library item declarations and descriptions, grammar productions. Typeset
decorations (paragraph and list numbers, `[Note 1:`, `---end note]`, section
numbers in the text) are kept as they are, and `---` is not turned into a
dash.
