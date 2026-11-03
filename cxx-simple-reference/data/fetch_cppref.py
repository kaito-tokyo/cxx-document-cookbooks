#!/usr/bin/env python3
"""Download and unpack a cppreference offline archive.

usage: fetch_cppref.py BUILD_DIR URL

Output: BUILD_DIR/cppref/  (archive contents, unmodified)
        BUILD_DIR/cppref.stamp
The archive itself is kept at BUILD_DIR/downloads/<filename>.
"""

import argparse
import shutil
import sys
import tarfile
import urllib.parse
import urllib.request
import zipfile
from pathlib import Path, PurePosixPath


def download(url, dest):
    dest.parent.mkdir(parents=True, exist_ok=True)
    tmp = dest.with_suffix(dest.suffix + ".part")
    req = urllib.request.Request(url, headers={"User-Agent": "cxx-simple-reference"})
    with urllib.request.urlopen(req) as r, open(tmp, "wb") as f:
        shutil.copyfileobj(r, f)
    tmp.replace(dest)


def safe_name(name):
    p = PurePosixPath(name)
    if p.is_absolute() or ".." in p.parts:
        sys.exit(f"archive entry escapes the target directory: {name!r}")
    return p


def unpack(archive, dest):
    if dest.exists():
        shutil.rmtree(dest)
    dest.mkdir(parents=True)
    if zipfile.is_zipfile(archive):
        with zipfile.ZipFile(archive) as z:
            for info in z.infolist():
                safe_name(info.filename)
            z.extractall(dest)
    elif tarfile.is_tarfile(archive):
        with tarfile.open(archive) as t:
            for m in t.getmembers():
                safe_name(m.name)
                if not (m.isfile() or m.isdir()):
                    sys.exit(f"archive entry is not a regular file or directory: {m.name!r}")
            t.extractall(dest, filter="data")
    else:
        sys.exit(f"{archive}: not a zip or tar archive")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("build")
    ap.add_argument("url")
    args = ap.parse_args()
    build = Path(args.build)
    url = args.url
    name = PurePosixPath(urllib.parse.urlparse(url).path).name
    archive = build / "downloads" / name
    stamp = build / "cppref.stamp"
    out = build / "cppref"

    if out.is_dir() and stamp.is_file() and stamp.read_text().strip() == url:
        print("cppref: up to date")
        return
    if not archive.is_file():
        download(url, archive)
    unpack(archive, out)
    stamp.write_text(url + "\n")
    print(f"cppref: unpacked {name} to {out}")


if __name__ == "__main__":
    main()
