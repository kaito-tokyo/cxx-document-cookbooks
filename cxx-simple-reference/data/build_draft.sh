#!/usr/bin/env bash
# Render the pinned draft to HTML with cxxdraft-htmlgen.
#
# usage: build_draft.sh LOCK BUILD_DIR
#
# Inputs  BUILD_DIR/draft-src, BUILD_DIR/htmlgen-src   (from fetch_inputs.py)
# Output  BUILD_DIR/draft-html/                       (one .html file per section)
#         or $DRAFT_HTML_OUT when set (used by the reproducibility check)
#
# Stage 1 compiles htmlgen with the pinned GHC and cabal, installed through
#         ghcup, unless HTMLGEN_BIN points at an existing binary.
#         GHC / CABAL may name existing binaries instead of ghcup; their
#         versions must still match the pins.
# Stage 2 runs the binary on the host, which needs: git, node + npm, graphviz (dot).
set -euo pipefail

lock=$(realpath "$1")
build=$(realpath "$2")
here=$(cd "$(dirname "$0")" && pwd)

lockval() { sed -n "s/^$1[[:space:]]*=[[:space:]]*\([^#]*\).*/\1/p" "$lock" | sed 's/[[:space:]]*$//'; }
need() { command -v "$1" >/dev/null || { echo "build_draft.sh: '$1' not found${2:+ ($2)}" >&2; exit 1; }; }

htmlgen_commit=$(lockval htmlgen_commit)
ghc_version=$(lockval htmlgen_ghc)
cabal_version=$(lockval htmlgen_cabal)
index_state=$(lockval htmlgen_index_state)
draft_commit=$(lockval draft_commit)
for v in htmlgen_commit ghc_version cabal_version index_state draft_commit; do
  [ -n "${!v}" ] || { echo "build_draft.sh: $v is empty in $lock" >&2; exit 1; }
done

src="$build/htmlgen-src"
draft="$build/draft-src"
[ "$(git -C "$src" rev-parse HEAD)" = "$htmlgen_commit" ] || { echo "htmlgen-src is not at the pinned commit; run fetch_inputs.py" >&2; exit 1; }
[ "$(git -C "$draft" rev-parse HEAD)" = "$draft_commit" ] || { echo "draft-src is not at the pinned commit; run fetch_inputs.py" >&2; exit 1; }

out="${DRAFT_HTML_OUT:-$build/draft-html}"
mkdir -p "$(dirname "$out")"
out=$(realpath -m "$out")
out_stamp="$out.stamp"
want_out_stamp="$draft_commit $htmlgen_commit ghc-$ghc_version cabal-$cabal_version $index_state $(sha256sum < "$here/package-lock.json" | cut -c1-64)"
if [ -d "$out" ] && [ "$(cat "$out_stamp" 2>/dev/null)" = "$want_out_stamp" ] && [ -z "${FORCE:-}" ]; then
  echo "draft-html: up to date (FORCE=1 to rebuild)"
  exit 0
fi

need git; need node "Node.js"; need npm; need dot "Graphviz"

# --- Stage 1: htmlgen binary -------------------------------------------------
bin="${HTMLGEN_BIN:-$build/bin/cxxdraft-htmlgen}"
stamp="$build/bin/cxxdraft-htmlgen.stamp"
want_stamp="$htmlgen_commit ghc-$ghc_version cabal-$cabal_version $index_state"
if [ -z "${HTMLGEN_BIN:-}" ] && { [ ! -x "$bin" ] || [ "$(cat "$stamp" 2>/dev/null)" != "$want_stamp" ]; }; then
  if [ -n "${GHC:-}" ] && [ -n "${CABAL:-}" ]; then
    ghc=$(command -v "$GHC") || { echo "build_draft.sh: GHC=$GHC not found" >&2; exit 1; }
    cabal=$(command -v "$CABAL") || { echo "build_draft.sh: CABAL=$CABAL not found" >&2; exit 1; }
  else
    need ghcup "https://www.haskell.org/ghcup/"
    ghcup install ghc "$ghc_version"
    ghcup install cabal "$cabal_version"
    ghc=$(ghcup whereis ghc "$ghc_version")
    cabal=$(ghcup whereis cabal "$cabal_version")
  fi
  [ "$("$ghc" --numeric-version)" = "$ghc_version" ] ||
    { echo "build_draft.sh: $ghc is not GHC $ghc_version" >&2; exit 1; }
  [ "$("$cabal" --numeric-version)" = "$cabal_version" ] ||
    { echo "build_draft.sh: $cabal is not cabal $cabal_version" >&2; exit 1; }

  # Keep cabal's package store and index under BUILD_DIR, away from ~/.cabal.
  export CABAL_DIR="$build/cabal-home"
  work="$build/htmlgen-build"
  mkdir -p "$build/bin" "$CABAL_DIR" "$work"
  # Build from a clean export; dist-newstyle/ in $work is reused between runs.
  find "$work" -mindepth 1 -maxdepth 1 ! -name dist-newstyle -exec rm -rf {} +
  git -C "$src" archive HEAD | tar -x -C "$work"
  echo "== compiling cxxdraft-htmlgen with GHC $ghc_version, cabal $cabal_version"
  # regex-compat-tdfa-0.95.1.4 (the only release) declares base<4.15, which
  # excludes every GHC >= 9.0; it compiles unchanged against newer base.
  cabal_flags=(-w "$ghc" --index-state="$index_state" --allow-newer=regex-compat-tdfa:base)
  (cd "$work" &&
    "$cabal" update --index-state="$index_state" >/dev/null &&
    "$cabal" build -v1 "${cabal_flags[@]}" exe:cxxdraft-htmlgen &&
    install -m 755 "$("$cabal" list-bin "${cabal_flags[@]}" exe:cxxdraft-htmlgen)" "$build/bin/cxxdraft-htmlgen")
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
# Replace it with the committer date of the pinned draft commit.
draft_date=$(TZ=UTC git -C "$draft" log -1 --date=format-local:%F --format=%cd)
grep -rlE --include='*.html' '\(Generated on [0-9]{4}-[0-9]{2}-[0-9]{2} ' "$out" | LC_ALL=C sort |
  xargs -r sed -i -E "s/\(Generated on [0-9]{4}-[0-9]{2}-[0-9]{2} /(Generated on $draft_date /"

echo "$want_out_stamp" > "$out_stamp"
echo "== wrote $(find "$out" -type f | wc -l) files to $out"
