#!/usr/bin/env python3
"""Download, verify, and unpack the pinned cppreference offline archive.

usage: fetch_cppref.py LOCK BUILD_DIR             fetch per cppref_url / cppref_sha256
       fetch_cppref.py LOCK BUILD_DIR --pin URL   download URL, write its hash to LOCK

Output: BUILD_DIR/cppref/  (archive contents, unmodified)
        BUILD_DIR/cppref.stamp
The archive itself is kept at BUILD_DIR/downloads/<filename>.
"""

import argparse
import hashlib
import shutil
import sys
import tarfile
import urllib.parse
import urllib.request
import zipfile
from pathlib import Path, PurePosixPath

sys.path.insert(0, str(Path(__file__).resolve().parent))
import lockfile  # noqa: E402


def sha256(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


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
    ap.add_argument("lock")
    ap.add_argument("build")
    ap.add_argument("--pin", metavar="URL")
    args = ap.parse_args()
    build = Path(args.build)

    if args.pin:
        name = PurePosixPath(urllib.parse.urlparse(args.pin).path).name
        archive = build / "downloads" / name
        download(args.pin, archive)
        lockfile.update(args.lock, cppref_url=args.pin, cppref_sha256=sha256(archive))
        print(f"pinned {args.pin}")

    entries = lockfile.read(args.lock)
    url, digest = lockfile.require(entries, "cppref_url", "cppref_sha256", path=args.lock)
    name = PurePosixPath(urllib.parse.urlparse(url).path).name
    archive = build / "downloads" / name
    stamp = build / "cppref.stamp"
    out = build / "cppref"

    if out.is_dir() and stamp.is_file() and stamp.read_text().strip() == digest:
        print("cppref: up to date")
        return
    if not archive.is_file() or sha256(archive) != digest:
        download(url, archive)
    actual = sha256(archive)
    if actual != digest:
        sys.exit(f"{name}: sha256 mismatch: lock has {digest}, downloaded {actual}")
    unpack(archive, out)
    stamp.write_text(digest + "\n")
    print(f"cppref: unpacked {name} to {out}")


if __name__ == "__main__":
    main()
