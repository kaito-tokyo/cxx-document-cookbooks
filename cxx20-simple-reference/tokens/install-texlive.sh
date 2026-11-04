#!/bin/sh
# SPDX-FileCopyrightText: 2026 Kaito Udagawa <umireon@kaito.tokyo>
#
# SPDX-License-Identifier: Apache-2.0

# usage: install-texlive.sh PREFIX [REPOSITORY]
#
# Installs the current TeX Live into PREFIX with scheme-basic, no
# documentation or sources, and only the packages the drafts need (about
# 170 MB), leaving the system's TeX alone. Then run run.sh with
# PREFIX/bin/<platform> first in PATH. REPOSITORY is a CTAN tlnet URL; the
# default is the University of Utah's mirror, which serves a complete
# certificate chain on ftp.math.utah.edu.
set -eu
prefix=$1
repo=${2:-https://ftp.math.utah.edu/pub/ctan/tex-archive/systems/texlive/tlnet}

# Packages beyond scheme-basic that N4861 and recent drafts load.
packages="memoir listings extract isodate babel-english relsize textcase
  substr xpatch enumitem underscore ulem caption booktabs microtype lm
  jknapltx luatex85 xkeyval etoolbox epstopdf-pkg refcount stringenc
  firstaid parskip glyphlist xstring environ trimspaces imakeidx splitindex
  xcolor"

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
cd "$work"
curl -sSfL -o install-tl-unx.tar.gz "$repo/install-tl-unx.tar.gz"
curl -sSfL -o install-tl-unx.tar.gz.sha512 "$repo/install-tl-unx.tar.gz.sha512"
sha512sum -c install-tl-unx.tar.gz.sha512 > /dev/null
tar -xzf install-tl-unx.tar.gz
cat > texlive.profile <<EOF
selected_scheme scheme-basic
TEXDIR $prefix
TEXMFLOCAL $prefix/texmf-local
TEXMFSYSCONFIG $prefix/texmf-config
TEXMFSYSVAR $prefix/texmf-var
TEXMFHOME $prefix/texmf-home
TEXMFCONFIG $prefix/texmf-user-config
TEXMFVAR $prefix/texmf-user-var
instopt_adjustpath 0
instopt_adjustrepo 0
instopt_letter 0
instopt_write18_restricted 1
tlpdbopt_autobackup 0
tlpdbopt_install_docfiles 0
tlpdbopt_install_srcfiles 0
EOF
TEXLIVE_INSTALL_ENV_NOCHECK=1 perl install-tl-*/install-tl -profile texlive.profile -repository "$repo" > install.log
bin=$(ls -d "$prefix"/bin/*)
# shellcheck disable=SC2086
"$bin/tlmgr" install $packages > tlmgr.log
echo "installed $("$bin/lualatex" --version | head -n 1); add $bin to PATH"
