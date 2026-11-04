<!--
SPDX-FileCopyrightText: 2026 Kaito Udagawa <umireon@kaito.tokyo>

SPDX-License-Identifier: Apache-2.0
-->

# Operator setup (human, once)

1. Create a private GitHub repository (e.g. `cppref-local`) and copy the
   contents of this directory to its root (`SKILL.md`,
   `presentation.md`, `.gitignore`, `data/`). The data layer always builds
   the current upstream heads of the draft and htmlgen.
2. Add `CLAUDE.md` at the repository root:

   ```
   Follow SKILL.md. Stop at every STOP marker and open a PR.
   Do not add Co-Authored-By or any other trailer to commits.
   Do not write prose into the generated site.
   ```

3. Add `.claude/settings.json` that disables attribution. Check the key name
   in the current Claude Code settings reference; at the time of writing:

   ```json
   { "attribution": { "commit": "", "pr": "" } }
   ```

4. Cloud environment (claude.ai/code → environment selector → new
   environment):
   * Network access: Custom, with "Also include default list of common
     package managers" checked (covers Hackage and npm), plus:

     ```
     get-ghcup.haskell.org
     downloads.haskell.org
     raw.githubusercontent.com
     hackage.haskell.org
     en.cppreference.com
     upload.cppreference.com
     ```

     ghcup is installed from `get-ghcup.haskell.org`, reads its metadata
     from `raw.githubusercontent.com`, and downloads GHC and cabal from
     `downloads.haskell.org`. `build_draft.sh` uses the `ghc` and `cabal`
     that the setup script selects with `ghcup set`.
   * Environment variables:

     ```
     BASH_DEFAULT_TIMEOUT_MS=600000
     BASH_MAX_TIMEOUT_MS=1800000
     ```
   * Setup script (keep it under 5 minutes so the snapshot is cached; the
     htmlgen build itself happens in the session):

     ```bash
     set -e
     apt-get update
     apt-get install -y -q graphviz libgmp-dev
     pip install --break-system-packages lxml
     curl --proto '=https' --tlsv1.2 -sSf https://get-ghcup.haskell.org |
       BOOTSTRAP_HASKELL_NONINTERACTIVE=1 BOOTSTRAP_HASKELL_MINIMAL=1 sh
     ln -sf /root/.ghcup/bin/ghcup /usr/local/bin/ghcup
     ghcup install ghc 8.10.7
     ghcup install cabal 3.14.2.0
     ghcup set ghc 8.10.7
     ghcup set cabal 3.14.2.0
     ```

5. Start the session with: `Read SKILL.md and follow its procedure. Stop at the first STOP marker.`

Expected first-run cost in a cloud session: about 15 minutes to compile
htmlgen and its dependencies, then the render time of the draft. Both are
cached in `build/` for later runs in the same container.
