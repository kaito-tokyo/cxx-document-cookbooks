# Data contract (version 1)

This file is normative. It describes everything the data layer puts in
`build/` and the guarantees the presentation layer may rely on. The
presentation layer reads nothing else. `inputs.json` carries
`contract_version`; a change that breaks any statement here bumps it.

## Layout

```
build/
  draft-src/            pinned cplusplus/draft checkout          (internal)
  htmlgen-src/          pinned cxxdraft-htmlgen checkout          (internal)
  bin/, cabal-home/, node/                                        (internal)
  draft-html/           the rendered draft                        (public)
  draft-html.stamp                                                (internal)
  data/*.json           the tables, canonical form                (public)
  db.sqlite             the same tables as SQLite                 (public)
  cppref/               cppreference archive, unpacked as-is      (public, optional)
  downloads/, cppref.stamp                                        (internal)
```

"Internal" paths are implementation details of the data layer and may change
without notice. The presentation layer uses only the public ones.

## `draft-html/`

The output of cxxdraft-htmlgen in `WithExtension` mode for the pinned draft
commit, with exactly one post-processing step: the build date in the
"(Generated on YYYY-MM-DD …)" line of `index.html` and `fulltoc.html` is
replaced by the UTC committer date of the draft commit. Nothing else is
changed, so the files are byte-identical across builds.

Properties the presentation layer must take into account:

* Every page is a complete HTML document that links `14882.css` and the
  three alternate stylesheets in the same directory, and the PNG icons.
* Network resources: every page links Google Fonts
  (`https://fonts.googleapis.com/...`) in `<head>`, and `14882.css` loads
  MathJax fonts from `cdn.mathjax.org` (a defunct host). Nothing else is
  loaded from the network. Outbound hyperlinks (not resources) go to
  github.com (source links) and a handful of standards bodies.
* Links between pages are relative (`basic.life.html#3`). Pages link back
  to the table of contents as `index.html#<stable_name>`.
* Each paragraph carries a "source" link to `github.com/cplusplus/draft` at
  the pinned commit.
* Content is UTF-8 and contains non-ASCII characters.
* Some text is produced by htmlgen rather than the draft: the header of
  `index.html`/`fulltoc.html`, redirect pages (see `xrefs`), and labels such
  as "Specified in:". It is part of the rendered draft and is reproduced
  like the rest.

Page kinds are listed in the `pages` table.

## Tables

Each table is `data/<name>.json` (a JSON array of objects, UTF-8, keys
sorted, rows in the order stated below) and a table of the same name in
`db.sqlite`. In SQLite, lists are stored as JSON text and booleans as 0/1.
Paths are relative to `draft-html/`. "Stable name" is the draft's section
label such as `basic.life`.

### `sections`

Every clause, annex, subclause, and term definition, in document order.

| column        | type    | meaning |
|---------------|---------|---------|
| `stable_name` | text PK | e.g. `vector.modifiers`, `defns.access` |
| `kind`        | text    | `clause`, `annex`, `subclause`, `definition`, `unnumbered` (Foreword, Introduction, Bibliography) |
| `number`      | text    | as printed: `23.3.13.5`, `A.2`, `3.1`; annexes are `A`, `B`, …; empty for `unnumbered` |
| `title`       | text    | heading text, whitespace-normalised; for a definition, the defined term |
| `parent`      | text    | stable name of the enclosing section; null at the top level |
| `depth`       | int     | 0 for clauses/annexes |
| `ord`         | int     | position in document order |
| `path`        | text    | page of this section, `<stable_name>.html` |

Guarantees: every `path` exists; every `parent` is a row; every numbered
subclause's number extends its parent's number; numbers are unique; at
least 2000 rows; `basic.life`, `container.reqmts`, `vector.modifiers` exist.
Numbers are specific to the pinned draft; stable names are the durable key.

### `index_entries`

The six indices of the draft (`libraryindex`, `headerindex`, `generalindex`,
`grammarindex`, `conceptindex`, `impldefindex`), flattened. One row per
link of an index node; a node without links (a pure grouping node) has one
row with null link columns. Rows are in index page order.

| column        | type    | meaning |
|---------------|---------|---------|
| `ord`         | int PK  | row number |
| `category`    | text    | `library`, `header`, `general`, `grammar`, `concept`, `impldef` |
| `node`        | text    | id of the index node on its index page (e.g. `lib:vector,emplace_back`) |
| `parent`      | text    | `node` of the parent index node; null at the top level |
| `depth`       | int     | 0 for top-level terms |
| `path`        | list    | display text of each level, top first: `["emplace_back", "inplace_vector"]` |
| `term`        | text    | last element of `path` |
| `section`     | text    | target stable name, or null |
| `anchor`      | text    | target anchor as it appears in the link (URL-encoded), or null |
| `href`        | text    | target link exactly as on the index page, or null |
| `definition`  | bool    | the link is the defining occurrence (bold in the index) |
| `see`         | text    | `see` / `see also` for cross-references inside the index, else null |
| `see_target`  | text    | `node` the cross-reference points to (same category), else null |

Guarantees: every `href` resolves to an existing page and id. Cross-reference
targets resolve except for defects in the upstream sources, which `check`
reports as warnings.

Facts about the draft that the presentation layer must not paper over:

* Index text is the draft's: library entries are unqualified names with
  sub-entries, e.g. `["emplace_back", "inplace_vector"]` and
  `["inplace_vector", "emplace_back"]`. The draft does not print
  `vector::emplace_back`, and its LaTeX macros do not reliably say which
  level is the class and which the member.
* The index is incomplete with respect to declarations. Example: there is no
  index entry for `vector`'s `emplace_back`; it appears only in the
  declarations of `vector.overview` and `vector.modifiers` (see `code`).

### `code`

Code that belongs directly to a section, in document order: declaration
blocks (`itemdecl`, the "signature" lines that open a specification) and
code blocks (synopses, examples, grammar-like code).

| column       | type   | meaning |
|--------------|--------|---------|
| `ord`        | int PK | row number |
| `section`    | text   | stable name of the section the code appears in (not its ancestors) |
| `n`          | int    | 1-based position within that section |
| `kind`       | text   | `itemdecl` or `codeblock` |
| `anchor`     | text   | id on the section's page: the itemdecl's link target, or the nearest enclosing element id of a code block (a paragraph or example); may be null |
| `in_example` | bool   | the block is inside an example |
| `code`       | text   | plain text of the code, as rendered |

Guarantees: `section` is a row of `sections`; a non-null `anchor` exists on
the section's page. The number of `itemdecl` rows equals the number of
`itemdecl` environments in the LaTeX sources.

### `xrefs`

Redirect pages htmlgen generates for stable names of earlier standards
(from the draft's `xrefdelta`).

| column        | type    | meaning |
|---------------|---------|---------|
| `stable_name` | text PK | the old name, e.g. `class.copy`; its page is `<stable_name>.html` |
| `targets`     | list    | current stable names it maps to; empty if the subclause was removed |

Guarantee: every target is a row of `sections`.

### `behaviors`

Items of the "Core undefined behavior" and "Ill-formed, no diagnostic
required" annexes.

| column             | type    | meaning |
|--------------------|---------|---------|
| `id`               | text PK | e.g. `ub:expr.add.out.of.bounds` |
| `kind`             | text    | `ub` or `ifndr` |
| `number`           | text    | e.g. `F.3.30` |
| `parent`           | text    | annex subclause it is listed in (e.g. `ub.expr`) |
| `specified_in`     | text    | stable name of the normative section |
| `specified_anchor` | text    | id in that section's page |
| `path`             | text    | `<id>.html` |

### `floats`

Numbered tables and figures.

| column    | type    | meaning |
|-----------|---------|---------|
| `id`      | text PK | `tab:<label>` or `fig:<label>` |
| `kind`    | text    | `table` or `figure` |
| `number`  | text    | `47` |
| `caption` | text    | caption text |
| `section` | text    | stable name of the section containing it |
| `anchor`  | text    | id within the section's page (`<label>`) |
| `path`    | text    | `<id>.html` (a page showing only the float) |

### `pages`

Every file in `draft-html/`, sorted by name.

| column        | type    | meaning |
|---------------|---------|---------|
| `path`        | text PK | file name |
| `kind`        | text    | see below |
| `stable_name` | text    | for `section`, `definition`, `xref`; else null |

Kinds: `section`, `definition`, `xref`, `table`, `figure`, `ub`, `ifndr`,
`index` (the six index pages), `toc` (`index.html` = table of contents,
`fulltoc.html` = expanded), `full` (`full.html`, the whole document on one
page, ~50 MB), `list` (`footnotes.html`, `tab.html`, `fig.html`), `asset`
(CSS and icons). No other kind occurs; an unrecognised page fails `check`.

### `inputs`

Key/value provenance: the pinned fields of `inputs.lock` (except
cppreference fields), `draft_commit_date` (ISO 8601 committer date), and
`contract_version`.

## `cppref/` (optional)

Present only after `make -C data cppref` with a pinned archive: the archive's
contents, unpacked unmodified (expected to contain `reference/en/cpp/…`).
Not yet part of this contract: a `joins` table mapping cppreference pages to
draft sections and an `unjoined` table. They belong to the data layer and
will be added in contract version 2; until then presentation.md P4 is
blocked.

## Verification

`make -C data check` verifies every guarantee above and that re-extracting
the tables gives byte-identical files. `make -C data repro` additionally
re-renders the draft and requires `draft-html/` to be byte-identical.
