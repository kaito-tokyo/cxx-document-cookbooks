<!--
SPDX-FileCopyrightText: 2026 Kaito Udagawa <umireon@kaito.tokyo>

SPDX-License-Identifier: MIT
-->

# cxxdraft-xml

`cxxdraft-xml` loads the draft exactly like `cxxdraft-htmlgen` and writes
the loaded document structure (the `Draft` value of `Document.hs`) as XML,
without rendering anything.

```
cd path/to/cxxdraft-htmlgen-ghc9        # macros.tex is read from here
LC_ALL=C.UTF-8 cxxdraft-xml path/to/draft draft.xml
```

Like `cxxdraft-htmlgen`, it needs `git` (for the commit URL) and Graphviz
`dot` (figures are converted to SVG while loading). For draft `d4d6f381`
it takes about 40 seconds and writes about 107 MB.

## Encoding

The XML follows the Haskell types one to one; `Document.hs` and
`LaTeXBase.hs` are its schema.

| Haskell value                      | XML                                                  |
|------------------------------------|------------------------------------------------------|
| constructor `C a b`                | `<C>` with one child per argument, in order          |
| record constructor `C {f :: a}`    | `<C><f>…</f></C>`, one element per field             |
| `Text`, `String`, `Int`, `Char`    | `<Text>…</Text>`, `<String>…</String>`, …            |
| list                               | `<List>` with one child per item                     |
| tuple                              | `<Tuple>` with one child per component               |
| `Map`, `IntMap`                    | `<Map>` / `<IntMap>` holding a `<List>` of `<Tuple>`s |
| `Maybe`, `Bool`                    | `<Nothing/>`, `<Just>…</Just>`, `<True/>`, `<False/>` |

htmlgen's index parsing (`unescapeIndexPath` in `Load14882.hs`) replaces
makeindex's `!` (level separator) and `@` (separator between sort key and
shown key) with the control characters U+0001 and U+0003, which XML 1.0
does not allow. Where they occur in a `Text`, they are written as
`<IndexLevelSeparator/>` and `<IndexSortKeySeparator/>`. Any other
character that XML 1.0 does not allow stops `cxxdraft-xml` with an error.
The text of the current draft has none of them; they occur only in the
derived index data, which is not written.

Example: `TeXComm "tcode" "" [(FixArg, [TeXRaw "x"])]` is

```xml
<TeXComm><String>tcode</String><String/><List><Tuple><FixArg/><List><TeXRaw><Text>x</Text></TeXRaw></List></Tuple></List></TeXComm>
```

### Section references

Fields that point back to an enclosing section hold the section's
abbreviation instead of the section: `Section.parents`,
`Paragraph.paraSection`, `Table.tableSection`, `Figure.figureSection`,
`Formula.formulaSection`.

```xml
<paraSection><SectionRef>basic.scope</SectionRef></paraSection>
```

## What is written

```
Draft
  commitUrl   Text                    the draft commit
  chapters    [Section]               the text, as a tree of sections
  xrefDelta   [(Abbreviation, [LaTeX])]
              stable names of earlier standards that were moved, removed
              or deprecated (read from the draft's xrefdelta.tex), each with
              where it went; an empty list means removed
```

Inside `chapters`, a `Section` holds its `paragraphs`, `sectionFootnotes`
and nested `subsections`. A `Paragraph` holds `TeXPara`s, which hold
`Sentence`s, which hold `Element`s (`LatexElement`, `Enumerated`, `Bnf`,
`TableElement`, `Tabbing`, `FigureElement`, `FormulaElement`, `Codeblock`,
`Itemdescr`, `NoteElement`, `ExampleElement`, `HtmlElement`). Running text is
`LaTeX`, a list of `LaTeXUnit`s (`TeXRaw`, `TeXComm`, `TeXEnv`, `TeXMath`,
`TeXLineBreak`, `TeXBraces`), with the draft's commands still in place.
`Render.hs` shows how `cxxdraft-htmlgen` turns each of them into HTML.

## What is left out, and how to derive it

htmlgen also keeps data that it computes from the text. It is not
written; a converter that needs it computes it from `chapters`. The
functions named below are where htmlgen does the same.

### `Paragraph.allParaElems`

All elements of the paragraph, flattened (`allElements` in `Document.hs`).
For each element of each sentence of each `TeXPara` in `paraElems`, emit
the element, then recurse into:

* `Enumerated`: each item's `itemInlineContent`, then its `itemBlockContent`;
* `TableElement`: the `TeXPara`s of every cell of `tableBody`;
* `NoteElement` / `ExampleElement`: `noteContent` / `exampleContent`;
* `Codeblock x`, `Tabbing x`, `Bnf _ x`: `x` as `LatexElement`s.

### Index entries

Every index entry is an `index` command in the text:

```
TeXComm "index" _ [ (FixArg, [TeXRaw "<number>"])   -- added by htmlgen
                  , (OptArg, [TeXRaw "<category>"]) -- generalindex, libraryindex, …
                  , (FixArg, <makeindex key>) ]
```

The number is assigned by htmlgen in document order and identifies the
entry (`indexEntryNr`). The key uses makeindex syntax (`parseIndex` in
`Load14882.hs`):

* `"` quotes the next character (`"!`, `"@`, `"|`, `""`);
* `!` separates levels of the index path;
* in a level, `sort@shown` gives a sort key and the shown key;
* a trailing `|(` / `|)` opens / closes a page range, `|see{…}` and
  `|seealso{…}` make a cross reference, `|idxbfpage` marks the defining
  occurrence.

The entries of a section are the `index` commands in the paragraphs and
footnotes of the section and of all its subsections
(`sectionIndexEntries`). From them htmlgen builds:

* `Section.secIndexEntries`: those entries by number;
* `Section.secIndexEntriesByPath`: the same, grouped by index path
  (`reverseIndexEntryMap`);
* `Draft.indexEntryMap` / `Draft.indexEntriesByPath`: the same over all
  chapters;
* `Draft.index`: per category, a tree whose nodes are index path
  components; each node lists the entries whose path ends there
  (`toIndex`, `mergeIndices`).

### `Draft.labels`

`label` commands (`TeXComm "label" _ [(FixArg, [TeXRaw name])]`) in the
paragraphs and footnotes of a section map that name to the section
(`sectionLabels`).

### `Draft.abbrMap`

Abbreviation to item: sections by `abbreviation`, tables by `tableAbbr`,
figures by `figureAbbr`, formulas by `formulaAbbr` (`makeAbbrMap`).

## Math

`TeXMath` holds the formula as `LaTeX`. A converter can turn it back into
TeX source (`renderLaTeX` in `LaTeXBase.hs` does this) and typeset it with
MathJax in the browser.
