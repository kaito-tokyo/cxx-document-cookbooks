# cxx-simple-reference

A cookbook for building a personal, offline C++ reference whose source of
truth is the ISO C++ working draft. It is an application recipe, not a
Claude Code skill: copy this directory into a new repository and let an agent
build the reference from it.

The recipe is split into two layers with different rules.

| Layer        | Expressed as                      | Who changes it                   |
|--------------|-----------------------------------|----------------------------------|
| Data         | code in `data/`                   | fixed; extended only on request  |
| Presentation | requirements in `presentation.md` | designed and built by the agent  |

The data layer fetches the primary sources, renders the draft, and turns it
into documented, verified tables under `build/`. The format of
`build/` is the contract between the layers: [`data/CONTRACT.md`](data/CONTRACT.md).
The presentation layer is deliberately not written: the agent designs and
implements the site from [`presentation.md`](presentation.md), using only
what the contract provides.

## Files

```
SKILL.md             this file: layer rules and procedure for the agent
presentation.md      requirements of the presentation layer (natural language)
operator.md          one-time setup for the human (repository, cloud environment)
data/
  CONTRACT.md        normative description of build/
  Makefile           fetch / draft / tables / check / cppref / clean
  fetch_inputs.py    check out the upstream heads of the draft and htmlgen
  build_draft.sh     compile cxxdraft-htmlgen with the GHC on PATH, render the draft
  package.json       pinned Node dependencies of htmlgen's MathJax step
  package-lock.json
  extract_tables.py  draft-html/ -> data/*.json + db.sqlite
  fetch_cppref.py    download and unpack the cppreference archive
  check_data.py      verify build/ against CONTRACT.md, print a summary
```

Host requirements of the data layer: Python 3 with `lxml`, git, GHC and
cabal on PATH (installed by the environment's setup script), Node.js + npm,
Graphviz (`dot`). Network: github.com, Hackage (htmlgen build), the npm
registry, and cppreference.com (archive).

## Rules for the agent

1. **Run the data layer, do not reimplement it.** `make -C data all`
   produces `build/`. The presentation layer reads only the public parts of
   `build/` listed in CONTRACT.md.
2. **Do not change the contract on your own.** If the presentation needs data
   that CONTRACT.md does not describe, stop and report what is missing.
   Fixes inside `data/` that keep every statement of CONTRACT.md true are
   fine; say so in the commit message.
3. **Presentation is yours.** Choose the structure, code, and styling that
   satisfy presentation.md. Prefer small, dependency-free code.
4. **No authored prose in the output** (presentation.md P1). Code,
   configuration, and commit messages are fine; explanations in `site/` are
   not.
5. **English only** in every file you add.
6. **Commits**: small, single-purpose, plain messages, no trailers.

## Procedure

1. `make -C data all`. The first run compiles htmlgen (about 15 minutes);
   later runs reuse `build/`. Read the summary `check_data.py` prints. A
   `FAIL` line stops the procedure: fix the cause inside the contract or
   report it. `warn` lines are upstream defects; mention them in the PR.
2. Read `data/CONTRACT.md` and `presentation.md` in full.
3. Build the presentation layer with the targets of presentation.md P6.2.
4. Verify the acceptance items of presentation.md P7 by script.

**STOP.** Open a PR titled `Reference site from the data layer`. Put the
data-layer summary and the `make check` summary in the PR body.

## Requirements for both layers

* **Source of truth.** The only authoritative text is the working draft from
  `github.com/cplusplus/draft`, rendered by cxxdraft-htmlgen. Everything else
  is an annotation attached to a draft section and labelled as such.
* **Deterministic.** Given the same `build/` checkouts, each layer produces
  byte-identical output. No timestamps, host names, or absolute paths in
  outputs.
* **Licensing.** The draft sources carry ISO copyright: the repository stays
  private and the site is not published. cxxdraft-htmlgen is public domain.
  cppreference content is CC BY-SA 3.0 (and GFDL); its attribution stays on
  every reproduced page. Record these facts and the `inputs` table
  (commits used) in a `NOTICE` file.

## Status

* Data contract version 1: draft HTML, sections, index entries, code,
  xrefs, behaviors, floats, pages. Verified against draft
  `d4d6f381` / htmlgen `e91ccb55`.
* Planned for contract version 2: cppreference `joins` / `unjoined` tables
  (needs an archive URL passed as `CPPREF_URL`; `fetch_cppref.py` already
  downloads and unpacks it).
