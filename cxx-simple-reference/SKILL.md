# cppref-local — build specification

A personal, offline C++ reference whose source of truth is the ISO C++ working
draft. Every page is generated from primary sources by scripts; no hand-written
explanatory text exists anywhere in the output. Reached by symbol name and
stable section name, never through a search engine.

This file is the task for a Claude Code cloud session. It is not a Claude Code
skill; it is copied into the target repository as `docs/spec.md`.
Section 0 is for the human operator. Sections 1 onward are instructions to the
agent.

## 0. Operator setup (human, before starting the session)

1. Create a private GitHub repository (e.g. `cppref-local`), commit this file
   as `docs/spec.md`, push.
2. Cloud environment (claude.ai/code → environment selector → new environment):
   * Network access: Custom, "Also include default list of common package
     managers" checked, plus these lines:

     ```
     en.cppreference.com
     upload.cppreference.com
     ```

   * Environment variables:

     ```
     BASH_DEFAULT_TIMEOUT_MS=600000
     BASH_MAX_TIMEOUT_MS=1800000
     ```

   * Setup script (must finish in < 5 min so the snapshot is cached; do the
     heavy build inside the session, not here):

     ```bash
     docker pull haskell:9.6 &
     pip install --break-system-packages beautifulsoup4 lxml &
     wait
     ```

3. Commit `.claude/settings.json` that disables commit and PR attribution.
   Check the current key name in the Claude Code settings reference: older
   versions use `"includeCoAuthoredBy": false`; newer versions use an
   `attribution` object, e.g.

   ```json
   { "attribution": { "commit": "", "pr": "" } }
   ```

4. Commit a `CLAUDE.md` at the repository root containing:

   ```
   Follow docs/spec.md exactly.
   Do not add Co-Authored-By or any other trailer to commits.
   Do not add any prose documentation to the generated site.
   Stop at every "STOP" marker in docs/spec.md and open a PR.
   ```

5. Start the session with the prompt:
   `Read docs/spec.md and execute it from Phase 1. Stop at the first STOP marker.`

## 1. Requirements (normative for the whole project)

* **R1 Source of truth.** The only authoritative text is the C++ working draft
  from `github.com/cplusplus/draft`, rendered to HTML. Everything else is an
  annotation attached to a draft section and visibly labelled as such.
* **R2 No authored prose.** The repository contains scripts, configuration,
  and this spec. The generated site contains only (a) draft HTML, (b) indices
  derived mechanically from the draft, (c) cppreference pages reproduced from
  the official offline archive, unmodified except for link rewriting and the
  single injected block defined in Phase 3. The agent must not write
  explanatory text, summaries, tips, or notes into the output.
* **R3 English only.** No translation layer. No Japanese anywhere in the
  repository or the output.
* **R4 Direct reach.** Every library symbol and every stable section name must
  be reachable by typing it: a local symbol index (JSON + SQLite), a Zeal
  docset, and in-page search. The site must work from `file://` and from a
  plain static file server with no backend. Because browsers block `fetch()`
  on `file://`, data the page needs at runtime is shipped as `.js` files that
  assign a global (e.g. `symbols.js`), loaded with `<script src>`.
* **R5 Reproducible.** `inputs.lock` pins the exact draft commit, htmlgen
  commit, and cppreference archive filename + SHA-256. `make all` from a clean
  checkout with those inputs reproduces `site/` and `docset/` byte-for-byte.
  No timestamps, build hosts, or absolute paths are embedded in any output;
  JSON and SQLite rows are written in a deterministic order.
* **R6 Auditable joins.** Every link from a cppreference page to a draft
  section records how it was derived. Pages that could not be joined are
  listed, never silently dropped.
* **R7 Licensing.** cppreference content is licensed CC BY-SA 3.0 (and GFDL,
  as stated on the site): keep its attribution and license notice on every
  reproduced page and in `NOTICE`. The draft sources carry ISO copyright; the
  repository stays private and the site is not published. Record both facts in
  `NOTICE`.
* **R8 Commits.** Small, single-purpose commits with plain messages. No
  trailers of any kind. One branch for the whole task; one PR per phase.

## 2. Repository layout (target)

```
cppref-local/
  CLAUDE.md
  NOTICE
  .claude/settings.json
  docs/spec.md                 # this file
  inputs.lock                  # pinned inputs (see §3)
  Makefile                     # all / fetch / draft / sections / index / cppref /
                               # join / site / docset / check / serve / clean
  tools/
    fetch_inputs.py            # clones/downloads per inputs.lock, verifies hashes
    build_draft.sh             # runs cxxdraft-htmlgen inside docker
    extract_sections.py        # draft HTML -> sections table
    extract_indices.py         # draft index pages -> symbols table
    fetch_cppref.py            # downloads + unpacks the offline archive
    join_cppref.py             # cppreference pages -> draft sections (R6)
    render_site.py             # assembles site/ from the tables
    search.js                  # copied into site/ by render_site.py
    build_docset.py            # site/ -> Zeal/Dash docset
    check.py                   # all verifications (§8)
  build/                       # ignored by git
    draft-src/                 # cplusplus/draft checkout
    htmlgen-src/               # cxxdraft-htmlgen checkout
    draft-html/                # htmlgen output
    cppref-archive/            # unpacked archive
    db.sqlite                  # sections, symbols, joins, unjoined
  site/                        # ignored by git; the deliverable
  docset/                      # ignored by git; the deliverable
```

Scripts are Python 3 (stdlib + `beautifulsoup4` + `lxml`) and Bash. No other
runtime dependencies on the host. Whatever cxxdraft-htmlgen's README requires
(Haskell packages, Graphviz, Node-based math rendering, etc.) is installed
inside the `haskell:9.6` container by `tools/build_draft.sh`, never on the
host. The site uses no JavaScript framework; one hand-written `search.js`
(< 300 lines) is permitted because it is code, not prose.

## 3. Inputs and `inputs.lock`

```
draft_repo      = https://github.com/cplusplus/draft
draft_commit    = <full SHA, chosen in Phase 1: latest commit on main>
htmlgen_repo    = https://github.com/Eelis/cxxdraft-htmlgen
htmlgen_commit  = <full SHA, latest on master>
cppref_archive  = <filename, e.g. html-book-YYYYMMDD.zip>
cppref_sha256   = <hex>
cppref_source   = https://en.cppreference.com/w/Cppreference:Archives
```

`tools/fetch_inputs.py` must refuse to run if a field needed by the requested
target is empty, and must fail if a commit or hash does not match. Phase 1
fills the draft and htmlgen fields; Phase 3 fills the cppreference fields.

## 4. Phase 1 — Draft HTML

Goal: `build/draft-html/` containing the working draft as one HTML file per
section with the same stable-name anchors as eel.is/c++draft.

1. Clone `draft_repo` at `draft_commit` and `htmlgen_repo` at
   `htmlgen_commit`.
2. Read `cxxdraft-htmlgen`'s README. Build and run it inside the `haskell:9.6`
   container (mount both checkouts). Choose the output mode that produces one
   file per section with an `.html` extension (so it works from `file://`).
   Record the exact command, including every package installed in the
   container, in `tools/build_draft.sh`. If Docker is not available in the
   session, STOP and report instead of working around it.
3. Confirm the output contains: a table of contents, every clause and
   subclause, the index pages (general index, library index, header index,
   grammar index, concept index, implementation-defined index — use whatever
   names htmlgen emits), and that stable names such as `basic.life`,
   `container.reqmts`, `vector.modifiers` resolve to files/anchors.
4. `tools/extract_sections.py` → table
   `sections(stable_name TEXT PRIMARY KEY, number TEXT, title TEXT, parent TEXT, path TEXT)`.
   `number` is the clause number as printed (e.g. `24.3.11.5`); it is specific
   to this draft commit. `path` is relative to `site/draft/` and includes the
   anchor when the section is not the top of its file.
5. Commit: `inputs.lock` (draft + htmlgen fields), `.gitignore`,
   `tools/fetch_inputs.py`, `tools/build_draft.sh`,
   `tools/extract_sections.py`, `Makefile` targets `fetch`, `draft`,
   `sections`, `clean`.

Acceptance: `make draft sections` from clean succeeds; `sections` has
≥ 2,000 rows; the three stable names above resolve.

## 5. Phase 2 — Symbol index and site skeleton

Goal: type a symbol or stable name, land on the draft section.

1. `tools/extract_indices.py` parses the draft's own index pages into
   `symbols(name TEXT, name_norm TEXT, kind TEXT, stable_name TEXT, anchor TEXT, source TEXT)`
   where `kind ∈ {library, header, general, grammar, concept, impldef}` and
   `source` names the index page it came from. `name` is stored exactly as the
   draft prints it (e.g. `vector::emplace_back`, `std::ranges::views::zip`);
   `name_norm` is lowercase with a leading `std::` stripped, for matching.
   Also create an FTS5 virtual table over `name`.
2. `tools/render_site.py` produces `site/`:
   * `site/draft/…` — the htmlgen output copied verbatim.
   * `site/index.html` — one search box. Typing filters the symbol list
     client-side with prefix and substring match; Enter opens the top hit.
     Also accepts a stable name (`basic.life`) and a clause number (`6.7.3`)
     and jumps directly.
   * `site/symbols.json` (`[name, kind, url]` triples) and
     `site/sections.json` (`[stable_name, number, title, url]`), plus
     `site/symbols.js` and `site/sections.js` carrying the same data as a
     global for `file://` use (R4).
   * `site/search.js`.
   * `site/manifest.txt` — sorted list of every file the renderer wrote.
   * No other pages. No "about". No prose.
3. `tools/build_docset.py` produces `docset/cppref-local.docset/` per the Dash
   docset format:
   * `Contents/Info.plist` (`CFBundleIdentifier`, `CFBundleName`,
     `DocSetPlatformFamily`, `isDashDocset`, `dashIndexFilePath=index.html`).
   * `Contents/Resources/docSet.dsidx` — SQLite with exactly
     `CREATE TABLE searchIndex(id INTEGER PRIMARY KEY, name TEXT, type TEXT, path TEXT);`
     and `CREATE UNIQUE INDEX anchor ON searchIndex (name, type, path);`.
   * `Contents/Resources/Documents/` = a copy of `site/`.

   Map `kind` to Dash types: library symbols cannot be split into
   `Function`/`Class` reliably from the index alone, so use `Entry` for
   library, concept and impldef symbols, `Section` for stable names, `Keyword`
   for grammar/general, `Header` for headers. Do not guess finer types.
4. Makefile targets `index`, `site`, `docset`, `serve`
   (`python3 -m http.server -d site`); `make all` runs everything built so far.

Acceptance: `symbols` has ≥ 10,000 rows; `vector::emplace_back`, `basic.life`
and `6.7.3` each resolve in a headless browser from `file://` (verify with a
script); the docset schema and plist are verified by script (the manual Zeal
check is the operator's).

**STOP.** Open a PR titled `Phase 1–2: draft HTML, symbol index, docset`. Do
not start Phase 3 in the same session unless told to.

## 6. Phase 3 — cppreference as annotation

Goal: for each draft section, a list of cppreference pages that document it,
attached under the section, labelled "cppreference (CC BY-SA 3.0)". The
direction is draft → cppreference, never the reverse.

1. `tools/fetch_cppref.py` downloads the archive from the archives page
   (pick the newest `html-book-*.zip`), verifies SHA-256, unpacks to
   `build/cppref-archive/`. Fill `cppref_archive` and `cppref_sha256` into the
   lock in this phase.
2. `tools/join_cppref.py` scans every page under the archive's
   `reference/en/cpp/` tree and produces
   `joins(page_path TEXT, stable_name TEXT, method TEXT, evidence TEXT)` using
   these methods, applied in order, all matches kept:
   * `refsection`: the page's "References" section lists standard versions
     with clause numbers and titles. Map the latest listed standard's clause
     number to `sections.number` of the pinned draft only if the title also
     matches after normalisation; otherwise map by title alone and record
     `method='reftitle'`. (Clause numbers drift between standards; the title
     is the stable part.)
   * `symbol`: the page's title (e.g. `std::vector<T,Allocator>::emplace_back`)
     with template parameter lists removed and normalised like `name_norm`
     (→ `vector::emplace_back`) matches `symbols.name_norm`.
   * `header`: the page is a header page (`cpp/header/<name>`) and the draft
     header index has `<name>`.
   * Pages with no match go to `unjoined(page_path TEXT, title TEXT)`.

   `evidence` stores the exact string that matched (reference line, title, or
   header name).
3. `tools/render_site.py` (extended): copy the archive's pages into
   `site/cppreference/` verbatim, rewrite internal links so they work under
   `site/`, and inject a single block at the top of every reproduced page:
   `This page is reproduced from cppreference.com (CC BY-SA 3.0) and is an annotation. Draft sections: <links>`
   — the links come from `joins`. Into every draft section page with ≥ 1 join
   inject, after the section body, a block
   `cppreference (CC BY-SA 3.0): <list of joined page titles with method tags>`.
   The method tag is shown (`[refsection]`, `[symbol]`, …) so the reader sees
   how the link was derived (R6). Both blocks carry a fixed marker attribute
   (e.g. `data-cppref-local="annotation"`) so `check.py` can find them.
4. `site/unjoined.html` — generated table of unjoined pages. This is the only
   page besides `index.html` that is not draft or cppreference content, and it
   contains only the table.
5. `NOTICE` updated with the cppreference license text and the archive
   filename.
6. Makefile targets `cppref`, `join`.

Acceptance: ≥ 85 % of `reference/en/cpp/` pages joined by at least one method
(report the actual number in the PR; do not tune heuristics to hit the number
— if lower, report why); every joined page's injected links resolve; every
draft section with ≥ 1 join shows its block.

**STOP.** PR titled `Phase 3: cppreference annotations`.

## 7. Phase 4 (optional, only on request) — Standard versions

Using `github.com/timsong-cpp/cppwp`'s per-standard tags (or the draft repo's
own tags `n4861`, `n4950`, …), run Phase 1 for each requested version into
`site/draft-<version>/`, extend `sections` with a `version` column, and add a
version switch on each section page that resolves by stable name (falling back
to "not present in this version"). No diffs, no prose.

## 8. Verification (`tools/check.py`, run by `make check`)

All checks are scripts; a failing check fails the build.

* Every row in `sections` resolves to an existing file + anchor.
* Every row in `symbols` resolves to an existing section/anchor.
* Every URL in `symbols.json`, `sections.json`, and every injected link
  resolves within `site/`.
* `site/` contains exactly the files listed in `site/manifest.txt`.
* The injected block markers appear only in the places the spec allows; no
  non-ASCII text appears in `site/` outside `site/draft/` and
  `site/cppreference/` (R3).
* `docSet.dsidx` has the exact schema above and its row count equals the
  number of distinct `(name, type, path)` rows derived from `symbols` plus
  `sections`.
* `inputs.lock` commits and hashes match the checkouts and files in `build/`.
* Render `site/` twice into separate directories from the same `build/`;
  `diff -r` of the two trees is empty, and the two `docSet.dsidx` files are
  byte-identical (R5).

Print a one-screen summary: sections, symbols by kind, joins by method,
unjoined count, check results.

## 9. Things the agent must not do

* Write any explanatory text, examples, or notes into `site/` or `docset/`.
* Modify cppreference page content beyond link rewriting and the one injected
  block.
* Add dependencies beyond Python stdlib, beautifulsoup4, lxml, Docker, and the
  toolchain inside the container.
* Add CI workflows, caching layers, or a web server. `python3 -m http.server`
  in the `Makefile` target `serve` is the only serving method. No README.
* Add any commit trailer. Add any file in Japanese.
* Continue past a STOP marker.
* Fetch from any host other than github.com, Docker Hub and hackage.haskell.org
  (via the container build), en.cppreference.com, upload.cppreference.com,
  and the package registries on the default allowlist.
