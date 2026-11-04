#!/bin/sh
# SPDX-FileCopyrightText: 2026 Kaito Udagawa <umireon@kaito.tokyo>
#
# SPDX-License-Identifier: Apache-2.0

# usage: run.sh DRAFT_SOURCE_DIR OUTPUT.jsonl [CHAPTER...]
#
# Runs LuaLaTeX on a copy of the draft's source directory with prelude.tex
# read first, and writes the token stream to OUTPUT.jsonl. CHAPTERs (file
# names such as "basic") restrict the run with \includeonly.
set -eu
here=$(cd "$(dirname "$0")" && pwd)
src=$(cd "$1" && pwd)
out=$(realpath -m "$2")
shift 2
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
cp -R "$src"/. "$work"
only=""
if [ $# -gt 0 ]; then only="\\includeonly{$(echo "$@" | tr ' ' ,)}"; fi
cd "$work"
if ! lualatex -interaction=nonstopmode -halt-on-error --jobname=std \
    "\\input{$here/prelude}$only\\input{std}" > /dev/null; then
  tail -n 30 std.log >&2
  exit 1
fi
mv std.tokens.jsonl "$out"
