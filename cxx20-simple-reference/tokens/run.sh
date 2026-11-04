#!/bin/sh
# SPDX-FileCopyrightText: 2026 Kaito Udagawa <umireon@kaito.tokyo>
#
# SPDX-License-Identifier: Apache-2.0

# usage: run.sh DRAFT_SOURCE_DIR OUTPUT.jsonl [CHAPTER...]
#
# Typesets a copy of the draft's source directory twice with LuaLaTeX and
# prelude.tex read first, running splitindex and makeindex in between as the
# draft's latexmkrc does, and writes the token stream of the second run to
# OUTPUT.jsonl and its log to OUTPUT.jsonl.log. CHAPTERs (file names such as
# "basic") restrict both runs with \includeonly.
set -eu
here=$(cd "$(dirname "$0")" && pwd)
src=$(cd "$1" && pwd)
out=$(cd "$(dirname "$2")" && pwd)/$(basename "$2")
shift 2
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
cp -R "$src"/. "$work"
only=""
if [ $# -gt 0 ]; then only="\\includeonly{$(echo "$@" | tr ' ' ,)}"; fi
cd "$work"

typeset() {
  if ! lualatex -interaction=nonstopmode -halt-on-error --jobname=std \
      "\\input{$here/prelude}$only\\input{std}" > /dev/null; then
    cp std.log "$out.log"
    tail -n 30 std.log >&2
    exit 1
  fi
}

# First run: .aux, .idx, .glo, .out and std-gram.ext.
typeset

# Indexes and glossaries. Recent drafts use imakeidx with splitindex: all
# entries go to std.idx, to be split into std-NAME.idx. Older ones (N4861)
# use memoir's \makeindex[NAME], writing NAME.idx. Either way NAME.ist, if
# present, is the index style, as in the draft's latexmkrc.
if [ -f std.idx ]; then splitindex -m "" std.idx > /dev/null; fi
for idx in *.idx; do
  [ -f "$idx" ] && [ "$idx" != std.idx ] || continue
  stem=${idx%.idx}
  name=${stem#std-}
  style=""
  if [ -f "$name.ist" ]; then style="-s $name.ist"; fi
  # shellcheck disable=SC2086
  makeindex -q $style -o "$stem.ind" "$idx"
done
for glo in *.glo; do
  [ -f "$glo" ] || continue
  makeindex -q -s basic.gst -o "${glo%.glo}.gls" "$glo"
done

# Second run, writing the token stream (inside the working directory, as
# recent LuaTeX applies openout_any to Lua's io.open).
CXXTOKENS_OUT=std.tokens.jsonl typeset
mv std.tokens.jsonl "$out"
cp std.log "$out.log"
