# Presentation layer — specification

The presentation layer turns the data layer's output (`build/`, described in
[`data/CONTRACT.md`](data/CONTRACT.md)) into a browsable reference. Nothing in
this layer is pre-written: the agent designs and implements it from the
requirements below. Requirements use MUST / SHOULD / MAY in the RFC 2119 sense.
Anything not stated here is the agent's choice.

## P0. Boundary

* P0.1 The only input is `build/` as defined by the data contract. The
  presentation layer MUST NOT read `build/draft-src/`, parse LaTeX, or fetch
  anything from the network.
* P0.2 If a requirement needs data the contract does not provide, the agent
  MUST NOT work around it by scraping or guessing. It stops and reports which
  field is missing, so the data layer can be extended first.
* P0.3 Output goes to `site/` (and `docset/` for P5). Both are build products
  and are never committed.

## P1. Content rules

* P1.1 No authored prose. The output contains only: draft HTML from
  `build/draft-html/`, values taken from the data tables, cppreference pages
  from `build/cppref/` (when present), and UI chrome. UI chrome means
  controls and labels of at most a few words (`Search`, `Contents`, a version
  name, a method tag such as `[symbol]`); it never contains sentences,
  explanations, summaries, tips, or examples.
* P1.2 Draft HTML is reproduced unmodified, except for (a) rewriting links so
  they resolve inside `site/`, (b) removing or localising the network
  resources listed in CONTRACT.md (P2.2), and (c) inserting UI chrome and the
  annotation block of P4. Every insertion carries a marker attribute
  (e.g. `data-ref-ui`) so a check can find all of them.
* P1.3 English only. Outside the reproduced draft and cppreference content,
  `site/` MUST be ASCII.
* P1.4 Every reproduced cppreference page keeps its attribution and license
  notice.

## P2. Delivery

* P2.1 `site/` MUST work when opened from `file://` and when served by a plain
  static file server. No backend, no service worker requirement.
* P2.2 No network access at view time: every script, stylesheet, font, and
  image the pages use resolves inside `site/`. The draft pages reference
  Google Fonts and `14882.css` references MathJax fonts on a CDN (see
  CONTRACT.md); these references MUST be removed or replaced by local system
  font stacks without changing the text. Outbound hyperlinks (e.g. the
  per-paragraph source links to github.com) MAY stay.
* P2.3 Browsers block `fetch()` and `XMLHttpRequest` on `file://`. Data needed
  at runtime is therefore shipped as script files that assign a global, loaded
  with `<script src>`.
* P2.4 Hand-written JavaScript is allowed and SHOULD stay small and framework
  free. Build-time tooling is free, but MUST be pinned and MUST NOT require the
  network once `make fetch` of the data layer has run.

## P3. Direct reach

* P3.1 A single entry page (`site/index.html`) with one search input.
* P3.2 The input accepts, and Enter jumps directly to:
  * a stable name (`basic.life`), including the old names in `xrefs`
    (which land on their current target);
  * a section number (`6.7.3`, `A.2`);
  * an index term, at any level (`emplace_back`, `<vector>`,
    `ill-formed program`);
  * a qualified library name, with or without a leading `std::`
    (`vector::emplace_back`, `ranges::views::zip`).
* P3.3 Qualified names are not printed by the draft (CONTRACT.md,
  `index_entries`). Candidates for them MUST be derived mechanically from the
  data tables, e.g. by matching the components against the levels of a
  library index entry in either order, or against the declarations in `code`
  of a section whose stable name matches the qualifier. Each candidate shows
  how it was derived (`[index]`, `[decl]`, …), and the rules are documented
  in the code, not on the site.
* P3.4 While typing, the input shows matching candidates (exact before
  prefix before substring); each candidate shows its kind and the target's
  stable name.
* P3.5 Every section page offers the same search input.
* P3.6 Every row of `sections` and `xrefs`, and every row of
  `index_entries` with a target, is reachable through P3.2.

## P4. cppreference annotations (blocked until data contract version 2)

Requires the `joins` and `unjoined` tables, which the data layer does not
provide yet (CONTRACT.md, `cppref/`). Do not implement P4 against the raw
archive.

* P4.1 Direction is draft → cppreference. A draft section page lists the
  cppreference pages joined to it (from the `joins` table), after the section
  body, inside one block labelled `cppreference (CC BY-SA 3.0)`.
* P4.2 Each listed link shows its join method tag (`[refsection]`,
  `[symbol]`, …) so the reader sees how it was derived.
* P4.3 Each reproduced cppreference page carries one block at the top that
  names it as an annotation reproduced under CC BY-SA 3.0 and links back to
  its joined draft sections.
* P4.4 One generated page lists every row of `unjoined` as a table. Nothing
  else is on that page.

## P5. Docset

* P5.1 `docset/<name>.docset/` in Dash format, loadable by Zeal:
  `Contents/Info.plist`, `Contents/Resources/docSet.dsidx`,
  `Contents/Resources/Documents/` (a copy of `site/`).
* P5.2 `docSet.dsidx` uses exactly
  `CREATE TABLE searchIndex(id INTEGER PRIMARY KEY, name TEXT, type TEXT, path TEXT);`
  `CREATE UNIQUE INDEX anchor ON searchIndex (name, type, path);`
* P5.3 Types: `sections` and `xrefs` → `Section`; `index_entries` by
  category: `header` → `Header`, `library`/`concept`/`impldef` → `Entry`,
  `grammar`/`general` → `Keyword`. Do not infer finer types.

## P6. Reproducibility and checks

* P6.1 Building twice from the same `build/` produces byte-identical `site/`
  and `docset/`. No timestamps, host names, or absolute paths in the output.
* P6.2 `make site` builds the site, `make docset` the docset, `make check`
  runs all checks, `make serve` runs `python3 -m http.server -d site`. These
  sit next to the data layer's targets; the agent chooses where the code
  lives.
* P6.3 `make check` fails the build unless all of the following hold:
  * every link in `site/` that points inside `site/` resolves to an existing
    file and anchor;
  * P3.6 holds (checked against the runtime search data);
  * P1.2 holds: diffing each draft page against its source in
    `build/draft-html/` shows only marked insertions and link rewrites;
  * P1.3 holds;
  * P5.2 holds and the docset row count matches the rows it was built from;
  * P6.1 holds (build into two directories and compare);
  * `site/` contains no file that the build did not intend to write
    (compare against a manifest the build emits).
* P6.4 `make check` ends with a one-screen summary: counts from the data
  layer, counts of what was rendered, and pass/fail per check.

## P7. Acceptance

* From `file://` in a headless browser: typing `vector::emplace_back`,
  `basic.life`, and `6.7.3` and pressing Enter each lands on the right
  section and anchor (scripted).
* `make check` passes.
* The docset schema and plist are verified by script; loading it in Zeal is
  the operator's manual check.
