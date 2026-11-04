#!/usr/bin/env bash

# SPDX-FileCopyrightText: 2026 Kaito Udagawa <umireon@kaito.tokyo>
#
# SPDX-License-Identifier: Apache-2.0

# Render the checked-out draft to HTML with cxxdraft-htmlgen.
#
# usage: build_draft.sh BUILD_DIR
#
# Inputs  BUILD_DIR/draft-src, BUILD_DIR/htmlgen-src   (from fetch_inputs.py)
# Output  BUILD_DIR/draft-html/                       (one .html file per section)
#
# Stage 1 compiles htmlgen with the GHC and cabal on PATH (or $GHC / $CABAL),
#         unless HTMLGEN_BIN points at an existing binary.
# Stage 2 runs the binary on the host, which needs: git, node + npm, graphviz (dot).
set -euo pipefail

build=$(realpath "$1")
here=$(cd "$(dirname "$0")" && pwd)

# ghcup's bin directory, when present, is searched for ghc and cabal.
[ -d "$HOME/.ghcup/bin" ] && export PATH="$HOME/.ghcup/bin:$PATH"
need() { command -v "$1" >/dev/null || { echo "build_draft.sh: '$1' not found${2:+ ($2)}" >&2; exit 1; }; }

src="$build/htmlgen-src"
draft="$build/draft-src"
htmlgen_commit=$(git -C "$src" rev-parse HEAD)
draft_commit=$(git -C "$draft" rev-parse HEAD)

out="$build/draft-html"
out_stamp="$out.stamp"

need git; need node "Node.js"; need npm; need dot "Graphviz"

# --- Stage 1: htmlgen binary -------------------------------------------------
bin="${HTMLGEN_BIN:-$build/bin/cxxdraft-htmlgen}"
stamp="$build/bin/cxxdraft-htmlgen.stamp"
if [ -z "${HTMLGEN_BIN:-}" ]; then
  ghc=$(command -v "${GHC:-ghc}") || { echo "build_draft.sh: GHC (${GHC:-ghc}) not found" >&2; exit 1; }
  cabal=$(command -v "${CABAL:-cabal}") || { echo "build_draft.sh: cabal (${CABAL:-cabal}) not found" >&2; exit 1; }
  ghc_version=$("$ghc" --numeric-version)
  cabal_version=$("$cabal" --numeric-version)
  want_stamp="$htmlgen_commit ghc-$ghc_version cabal-$cabal_version"
else
  want_stamp="external $HTMLGEN_BIN"
fi
want_out_stamp="$draft_commit $want_stamp $(sha256sum < "$here/package-lock.json" | cut -c1-64)"
if [ -d "$out" ] && [ "$(cat "$out_stamp" 2>/dev/null)" = "$want_out_stamp" ] && [ -z "${FORCE:-}" ]; then
  echo "draft-html: up to date (FORCE=1 to rebuild)"
  exit 0
fi

if [ -z "${HTMLGEN_BIN:-}" ] && { [ ! -x "$bin" ] || [ "$(cat "$stamp" 2>/dev/null)" != "$want_stamp" ]; }; then
  # Keep cabal's package store and index under BUILD_DIR, away from ~/.cabal.
  export CABAL_DIR="$build/cabal-home"
  work="$build/htmlgen-build"
  mkdir -p "$build/bin" "$CABAL_DIR" "$work"
  # Build from a clean export; dist-newstyle/ in $work is reused between runs.
  find "$work" -mindepth 1 -maxdepth 1 ! -name dist-newstyle -exec rm -rf {} +
  git -C "$src" archive HEAD | tar -x -C "$work"
  echo "== compiling cxxdraft-htmlgen with GHC $ghc_version, cabal $cabal_version"
  (cd "$work" &&
    "$cabal" update >/dev/null &&
    "$cabal" build -v1 -w "$ghc" exe:cxxdraft-htmlgen &&
    install -m 755 "$("$cabal" list-bin -w "$ghc" exe:cxxdraft-htmlgen)" "$build/bin/cxxdraft-htmlgen")
  echo "$want_stamp" > "$stamp"
fi
[ -x "$bin" ] || { echo "build_draft.sh: no htmlgen binary at $bin" >&2; exit 1; }

# --- Stage 2: node dependencies of mathjax-batch ----------------------------
node_dir="$build/node"
mkdir -p "$node_dir"
if ! cmp -s "$here/package-lock.json" "$node_dir/package-lock.json" || [ ! -d "$node_dir/node_modules" ]; then
  cp "$here/package.json" "$here/package-lock.json" "$node_dir/"
  (cd "$node_dir" && npm ci --silent --no-audit --no-fund)
fi

# --- Stage 3: render ---------------------------------------------------------
# htmlgen reads its CSS/macros and runs ./mathjax-batch from the working
# directory, and writes to ./14882/, so run it in a scratch copy.
run="$build/htmlgen-run"
rm -rf "$run" && mkdir -p "$run"
git -C "$src" archive HEAD | tar -x -C "$run"
echo "== rendering draft $draft_commit"
(cd "$run" && LC_ALL=C.UTF-8 LANG=C.UTF-8 NODE_PATH="$node_dir/node_modules" PATH="$node_dir/node_modules/.bin:$PATH" "$bin" "$draft" WithExtension)

rm -rf "$out" "$out_stamp"
mv "$run/14882" "$out"
rm -rf "$run"

# Determinism: htmlgen stamps the build date into the table of contents.
# Replace it with the committer date of the draft commit.
draft_date=$(TZ=UTC git -C "$draft" log -1 --date=format-local:%F --format=%cd)
grep -rlE --include='*.html' '\(Generated on [0-9]{4}-[0-9]{2}-[0-9]{2} ' "$out" | LC_ALL=C sort |
  xargs -r sed -i -E "s/\(Generated on [0-9]{4}-[0-9]{2}-[0-9]{2} /(Generated on $draft_date /"

echo "$want_out_stamp" > "$out_stamp"
echo "== wrote $(find "$out" -type f | wc -l) files to $out"
