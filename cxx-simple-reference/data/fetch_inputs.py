#!/usr/bin/env python3

# SPDX-FileCopyrightText: 2026 Kaito Udagawa <umireon@kaito.tokyo>
#
# SPDX-License-Identifier: Apache-2.0

"""Check out the upstream heads of the git inputs (draft, htmlgen) into the build directory.

usage: fetch_inputs.py BUILD_DIR
"""

import argparse
import subprocess
from pathlib import Path

CHECKOUTS = {
    # directory under BUILD_DIR -> (repository, branch)
    "draft-src": ("https://github.com/cplusplus/draft.git", "main"),
    # cxxdraft-htmlgen derives its commit link from a remote URL ending in .git.
    "htmlgen-src": ("https://github.com/Eelis/cxxdraft-htmlgen.git", "master"),
}


def git(*args, cwd=None, capture=False):
    r = subprocess.run(["git", *args], cwd=cwd, check=True, text=True,
                       stdout=subprocess.PIPE if capture else None)
    return r.stdout.strip() if capture else None


def checkout(repo, branch, dest):
    if not (dest / ".git").is_dir():
        dest.mkdir(parents=True, exist_ok=True)
        git("init", "-q", cwd=dest)
        git("remote", "add", "origin", repo, cwd=dest)
    git("fetch", "-q", "--depth", "1", "origin", branch, cwd=dest)
    git("checkout", "-q", "--force", "--detach", "FETCH_HEAD", cwd=dest)
    git("clean", "-q", "-fdx", cwd=dest)
    print(f"{dest.name}: {git('rev-parse', 'HEAD', cwd=dest, capture=True)}")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("build")
    args = ap.parse_args()
    build = Path(args.build)
    for subdir, (repo, branch) in CHECKOUTS.items():
        checkout(repo, branch, build / subdir)


if __name__ == "__main__":
    main()
