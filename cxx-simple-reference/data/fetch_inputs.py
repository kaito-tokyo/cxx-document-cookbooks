#!/usr/bin/env python3
"""Check out the pinned git inputs (draft, htmlgen) into the build directory.

usage: fetch_inputs.py LOCK BUILD_DIR          fetch / verify checkouts
       fetch_inputs.py LOCK BUILD_DIR --bump   repin to upstream heads, then fetch
"""

import argparse
import subprocess
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import lockfile  # noqa: E402

CHECKOUTS = {
    # lock prefix -> (directory under BUILD_DIR, branch used by --bump)
    "draft": ("draft-src", "main"),
    "htmlgen": ("htmlgen-src", "master"),
}


def git(*args, cwd=None, capture=False):
    r = subprocess.run(["git", *args], cwd=cwd, check=True, text=True,
                       stdout=subprocess.PIPE if capture else None)
    return r.stdout.strip() if capture else None


def remote_head(repo, branch):
    out = git("ls-remote", repo, f"refs/heads/{branch}", capture=True)
    if not out:
        sys.exit(f"{repo}: branch {branch} not found")
    return out.split()[0]


def checkout(repo, commit, dest):
    if (dest / ".git").is_dir():
        if git("rev-parse", "HEAD", cwd=dest, capture=True) == commit:
            print(f"{dest.name}: at {commit}")
            return
    else:
        dest.mkdir(parents=True, exist_ok=True)
        git("init", "-q", cwd=dest)
        # cxxdraft-htmlgen derives its commit link from a remote URL ending in .git.
        url = repo if repo.endswith(".git") else repo + ".git"
        git("remote", "add", "origin", url, cwd=dest)
    git("fetch", "-q", "--depth", "1", "origin", commit, cwd=dest)
    git("checkout", "-q", "--force", "--detach", "FETCH_HEAD", cwd=dest)
    git("clean", "-q", "-fdx", cwd=dest)
    head = git("rev-parse", "HEAD", cwd=dest, capture=True)
    if head != commit:
        sys.exit(f"{dest.name}: expected {commit}, got {head}")
    print(f"{dest.name}: checked out {commit}")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("lock")
    ap.add_argument("build")
    ap.add_argument("--bump", action="store_true")
    args = ap.parse_args()

    entries = lockfile.read(args.lock)
    if args.bump:
        changes = {}
        for prefix, (_, branch) in CHECKOUTS.items():
            (repo,) = lockfile.require(entries, f"{prefix}_repo", path=args.lock)
            changes[f"{prefix}_commit"] = remote_head(repo, branch)
        lockfile.update(args.lock, **changes)
        entries = lockfile.read(args.lock)
        for k, v in changes.items():
            print(f"{k} = {v}")

    build = Path(args.build)
    for prefix, (subdir, _) in CHECKOUTS.items():
        repo, commit = lockfile.require(entries, f"{prefix}_repo", f"{prefix}_commit",
                                        path=args.lock)
        if len(commit) != 40:
            sys.exit(f"{args.lock}: {prefix}_commit must be a full 40-character SHA")
        checkout(repo, commit, build / subdir)


if __name__ == "__main__":
    main()
