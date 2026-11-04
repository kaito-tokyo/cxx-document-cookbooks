<!--
SPDX-FileCopyrightText: 2026 Kaito Udagawa <umireon@kaito.tokyo>

SPDX-License-Identifier: Apache-2.0
-->

# tokens

Runs the C++ draft through LuaLaTeX, unchanged, and writes what it
typesets as a stream of tokens, with marks where the draft's macros were
used, and hyperref's destinations and links. Nothing is rendered: fonts
are dummies and the shipped-out pages are empty.

## Requirements (Ubuntu 24.04)

```
apt-get install --no-install-recommends texlive-luatex texlive-latex-base \
  texlive-latex-recommended texlive-latex-extra texlive-plain-generic lmodern
```

## Usage

The draft is the submodule `../.deps/draft` (github.com/cplusplus/draft),
pinned at the commit this was checked against; any checkout of the draft
works too.

```
git submodule update --init ../.deps/draft          # the draft, at d4d6f381
./run.sh ../.deps/draft/source out.jsonl           # whole draft
./run.sh ../.deps/draft/source out.jsonl basic     # \includeonly{basic}
```

`run.sh` typesets the draft twice, with `splitindex` and `makeindex` in
between as the draft's `latexmkrc` does, so that references, the indexes,
the cross-references from earlier standards and the grammar summary are
complete. The token stream is written by the second run, and its log
next to it (`out.jsonl.log`). For draft `d4d6f381` this takes about 5.5
minutes and writes about 21 MB.

## Output

One JSON object per line, in typesetting order:

| Token                | Meaning                                              |
|----------------------|------------------------------------------------------|
| `{"text": "..."}`    | typeset text; interword glue is a space               |
| `{"nl": true}`       | end of a typeset line                                 |
| `{"par": true}`      | start of a paragraph (each line of a code block is one) |
| `{"mark": "..."}`    | a mark placed by a hook in `prelude.tex`              |
| `{"math": "..."}`    | an inline formula, as TeX for MathJax                 |
| `{"displaymath": "..."}` | a display formula, as TeX for MathJax             |
| `{"anchor": "..."}`  | a hyperref destination (`section.6.1`, `page.33`, …) |
| `{"link": "..."}` … `{"endlink": true}` | a link: a destination name or a URI |

Marks:

| Mark                                   | Placed by                                  |
|----------------------------------------|--------------------------------------------|
| `section LEVEL ABBR`                   | `\rSec`, followed by `begin title` … `end title` |
| `pnum`                                 | `\pnum`                                     |
| `part`                                 | `thebibliography`, `\printglossary`, `\printindex` |
| `begin note` / `end note`              | `note` environment                          |
| `begin example` / `end example`        | `example` environment                       |
| `begin codeblock` / `end codeblock`    | `codeblock` environment                     |
| `begin tcode` / `end tcode`            | `\tcode`                                    |
| `begin grammarterm` / `end grammarterm`| `\grammarterm`                              |
| `begin defn` / `end defn`              | `\defnx` (and so `\defn`)                   |
| `iref LABELS`                          | `\iref`                                     |

Glyphs are turned back into Unicode with TeX Live's own data: `pdftex.map`
gives the encoding file of each font, the `.enc` file the glyph name of each
slot, and the Adobe glyph lists the Unicode text of each name. A glyph that
cannot be decoded is written as `\x{FONT:SLOT}` (a few large math
delimiters).

Formulas are taken in `mlist_to_hlist`, after all macros are expanded,
and written back as TeX for MathJax 3 in its default configuration (the
`base` and `ams` packages; not `textmacros`, which would read the contents
of `\text` as TeX): characters in Unicode, `_{}` and `^{}`, `\frac`,
`\genfrac`, `\sqrt`, accents, `\left` / `\right` and `\bigl` / `\bigr` with
named delimiters, `\mathrm` / `\mathsf` / `\mathtt` / `\mathit` for text
fonts, `\text{...}` / `\texttt{...}` for boxes (only `{`, `}` and `$`
escaped), and `array` for alignments (`cases`, matrices). The formula itself is not typeset. A `tabular` is also
a formula to TeX (an `\halign` in a `\vcenter` or `\vtop`); one whose cells
hold text is recognised and typeset as usual.

Every reference hyperref makes (`\ref`, `\iref`, `\tref`, `\cite`, the
table of contents, index page numbers, URLs) is a link, and every internal
link target is an anchor in the stream. Page numbers come from the dummy
fonts' layout and differ from the real draft.

`check-math.js` converts every distinct formula of a stream with MathJax
and reports the ones that fail (Ubuntu: `apt-get install node-mathjax-full`):

```
node check-math.js out.jsonl
```

For draft `d4d6f381`, all 1554 distinct formulas (9826 in all) convert.

## How it works

`prelude.tex` is read before `std.tex`:

* `luatex85`, `\pdfshellescape` and a dummy `\includegraphics` let the
  pdfLaTeX-only parts of the draft run under LuaLaTeX;
* `dummy-fonts.lua` answers every font request with a font of 256
  fixed-size characters, so no font file is read;
* hooks (`\AddToHook{cmd/...}`, `\AddToHook{env/...}`, wrapped `\rSec` and
  `\iref`) put `\cxxmark{...}`, a user-defined whatsit node, where the
  draft's macros are used;
* `cxxtokens.lua` marks the start of each paragraph and, at shipout, walks
  the page into the token stream, then empties the page of everything but
  its `\write` nodes and destinations: `\label`, `\index` and hyperref's
  bookmarks write at shipout, so the page must still be shipped out.
  Hyphenation and running heads are switched off, and marks are not made
  while the table of contents is typeset;
* the stream is written only when `CXXTOKENS_OUT` names a file (the second
  run of `run.sh`);
* amsmath typesets an equation number several times and keeps a copy
  without hyperref's destination, so the end of each `equation` names it
  again as an anchor.
