<!--
SPDX-FileCopyrightText: 2026 Kaito Udagawa <umireon@kaito.tokyo>

SPDX-License-Identifier: Apache-2.0
-->

# tokens

Runs the C++ draft through LuaLaTeX, unchanged, and writes what it
typesets as a stream of tokens, with marks where the draft's macros were
used. Nothing is rendered: fonts are dummies and pages are discarded.

## Requirements (Ubuntu 24.04)

```
apt-get install --no-install-recommends texlive-luatex texlive-latex-base \
  texlive-latex-recommended texlive-latex-extra texlive-plain-generic lmodern
```

## Usage

```
./run.sh path/to/draft/source out.jsonl            # whole draft
./run.sh path/to/draft/source out.jsonl basic      # \includeonly{basic}
```

For draft `d4d6f381` the whole run takes about 2.5 minutes and writes
about 16 MB.

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

Marks:

| Mark                                   | Placed by                                  |
|----------------------------------------|--------------------------------------------|
| `section LEVEL ABBR`                   | `\rSec`, followed by `begin title` … `end title` |
| `pnum`                                 | `\pnum`                                     |
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
and written back as TeX that MathJax reads: characters in Unicode, `_{}`
and `^{}`, `\frac`, `\genfrac`, `\sqrt`, accents, `\left` / `\right`,
`\bigl` / `\bigr`, `\mathrm` / `\mathsf` / `\mathtt` / `\mathit` for text
fonts, `\text{...}` / `\texttt{...}` for boxes, and `array` for alignments
(`cases`, matrices). The formula itself is not typeset. A `tabular` is also
a formula to TeX (an `\halign` in a `\vcenter` or `\vtop`); one whose cells
hold text is recognised and typeset as usual.

Since the run is single-pass, references print as `??`; marks such as
`iref` carry the labels instead.

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
  the page into the token stream before the page is discarded.
  Hyphenation and running heads are switched off.
