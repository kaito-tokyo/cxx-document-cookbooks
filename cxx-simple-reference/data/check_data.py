#!/usr/bin/env python3
"""Verify build/ against data/CONTRACT.md and print a summary.

usage: check_data.py BUILD_DIR
"""

import argparse
import collections
import html
import json
import re
import sqlite3
import subprocess
import sys
import tempfile
import urllib.parse
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import extract_tables  # noqa: E402

REQUIRED_SECTIONS = ["basic.life", "container.reqmts", "vector.modifiers"]
MIN_SECTIONS = 2000
MIN_INDEX_ENTRIES = 10000
ID_ATTR = re.compile(r"""\bid=(?:'([^']*)'|"([^"]*)")""")


class Checks:
    def __init__(self):
        self.results = []

    def check(self, name, problems, warn=False):
        """warn=True: defects in the upstream rendering, reported but not fatal."""
        problems = list(problems)
        self.results.append((name, problems, warn))
        return not problems

    @property
    def ok(self):
        return all(not p or w for _, p, w in self.results)


class Ids:
    """Lazily collected id attributes per HTML file."""

    def __init__(self, root):
        self.root, self.cache = root, {}

    def __call__(self, page):
        if page not in self.cache:
            path = self.root / page
            ids = set()
            if path.is_file():
                for m in ID_ATTR.finditer(path.read_text(encoding="utf-8")):
                    ids.add(html.unescape(m.group(1) if m.group(1) is not None else m.group(2)))
            self.cache[page] = ids if path.is_file() else None
        return self.cache[page]


def anchor_ok(ids, page, anchor):
    found = ids(page)
    if found is None:
        return False
    return not anchor or urllib.parse.unquote(html.unescape(anchor)) in found or anchor in found


def git_head(path):
    r = subprocess.run(["git", "-C", str(path), "rev-parse", "HEAD"],
                       text=True, capture_output=True)
    return r.stdout.strip() if r.returncode == 0 else None


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("build")
    args = ap.parse_args()
    build = Path(args.build)
    data = build / "data"
    html_dir = build / "draft-html"
    c = Checks()

    # Inputs -------------------------------------------------------------
    heads = {d: git_head(build / d) for d in ("draft-src", "htmlgen-src")}
    c.check("inputs: checkouts present", [d for d, h in heads.items() if not h])
    stamp = (build / "draft-html.stamp")
    c.check("inputs: draft-html rendered from the checkouts", [] if stamp.is_file() and
            stamp.read_text().split()[:2] == [heads["draft-src"], heads["htmlgen-src"]]
            else ["draft-html.stamp missing or stale"])

    tables = {}
    for name in extract_tables.SCHEMA:
        p = data / f"{name}.json"
        if not p.is_file():
            sys.exit(f"{p}: missing; run extract_tables.py")
        tables[name] = json.loads(p.read_text(encoding="utf-8"))
    sections = {r["stable_name"]: r for r in tables["sections"]}
    ids = Ids(html_dir)

    # Pages ---------------------------------------------------------------
    on_disk = sorted(p.name for p in html_dir.iterdir())
    c.check("pages: every file listed once", [] if on_disk == [p["path"] for p in tables["pages"]]
            else ["pages.json does not match the files in draft-html/"])
    c.check("pages: every page classified",
            [p["path"] for p in tables["pages"] if p["kind"] == "unknown"])

    # Sections ------------------------------------------------------------
    c.check(f"sections: at least {MIN_SECTIONS}",
            [] if len(sections) >= MIN_SECTIONS else [f"only {len(sections)}"])
    c.check("sections: required stable names", [n for n in REQUIRED_SECTIONS if n not in sections])
    c.check("sections: page exists", [s["stable_name"] for s in sections.values()
                                      if not (html_dir / s["path"]).is_file()])
    c.check("sections: parent exists", [s["stable_name"] for s in sections.values()
                                        if s["parent"] and s["parent"] not in sections])
    c.check("sections: number extends parent number", [
        s["stable_name"] for s in sections.values()
        if s["kind"] in ("subclause", "definition")
        and not s["number"].startswith(sections[s["parent"]]["number"] + ".")])
    numbers = collections.Counter(s["number"] for s in sections.values() if s["number"])
    c.check("sections: numbers unique", [n for n, k in numbers.items() if k > 1])
    c.check("sections: anchor in TOC", [s["stable_name"] for s in sections.values()
                                        if s["kind"] != "definition"
                                        and s["stable_name"] not in ids("fulltoc.html")])

    # Index entries -------------------------------------------------------
    entries = tables["index_entries"]
    c.check(f"index_entries: at least {MIN_INDEX_ENTRIES}",
            [] if len(entries) >= MIN_INDEX_ENTRIES else [f"only {len(entries)}"])
    c.check("index_entries: targets resolve", [
        f"{e['category']}:{e['node']} -> {e['href']}" for e in entries
        if e["href"] and not anchor_ok(ids, e["href"].partition("#")[0], e["anchor"])])
    nodes = {(e["category"], e["node"]) for e in entries}
    c.check("index_entries: see-references resolve (upstream)", [
        f"{e['category']}:{e['node']} -> {e['see_target']}" for e in entries
        if e["see_target"] and (e["category"], e["see_target"]) not in nodes], warn=True)

    # Other tables --------------------------------------------------------
    c.check("code: section exists and anchor resolves", [
        f"{d['section']}#{d['anchor']}" for d in tables["code"]
        if d["section"] not in sections
        or not anchor_ok(ids, sections[d["section"]]["path"], d["anchor"])])
    c.check("xrefs: targets exist", [
        f"{x['stable_name']} -> {t}" for x in tables["xrefs"] for t in x["targets"]
        if t not in sections])
    c.check("behaviors: specified_in resolves", [
        b["id"] for b in tables["behaviors"]
        if b["specified_in"] not in sections
        or not anchor_ok(ids, sections[b["specified_in"]]["path"], b["specified_anchor"])])
    c.check("floats: section exists", [f["id"] for f in tables["floats"]
                                       if f["section"] not in sections])

    # SQLite mirrors JSON -------------------------------------------------
    db = sqlite3.connect(build / "db.sqlite")
    c.check("db.sqlite: row counts match JSON", [
        f"{n}: {db.execute(f'SELECT count(*) FROM {n}').fetchone()[0]} != {len(rows)}"
        for n, rows in tables.items()
        if db.execute(f"SELECT count(*) FROM {n}").fetchone()[0] != len(rows)])
    db.close()

    # Determinism ---------------------------------------------------------
    with tempfile.TemporaryDirectory(dir=build) as tmp:
        extract_tables.extract(build, Path(tmp), Path(tmp) / "db.sqlite")
        diffs = [n for n in sorted(p.name for p in data.iterdir())
                 if (data / n).read_bytes() != (Path(tmp) / n).read_bytes()]
        diffs += [] if (build / "db.sqlite").read_bytes() == (Path(tmp) / "db.sqlite").read_bytes() \
            else ["db.sqlite"]
        c.check("tables: re-extract identically", diffs)

    # Summary ---------------------------------------------------------------
    print(f"draft   {heads['draft-src']}")
    print(f"htmlgen {heads['htmlgen-src']}")
    kinds = collections.Counter(s["kind"] for s in sections.values())
    print(f"sections      {len(sections):6}  " + " ".join(f"{k}={v}" for k, v in sorted(kinds.items())))
    cats = collections.Counter(e["category"] for e in entries)
    print(f"index_entries {len(entries):6}  " + " ".join(f"{k}={v}" for k, v in sorted(cats.items())))
    ck = collections.Counter(d["kind"] for d in tables["code"])
    print(f"{'code':13} {len(tables['code']):6}  " + " ".join(f"{k}={v}" for k, v in sorted(ck.items())))
    for n in ("xrefs", "behaviors", "floats", "pages"):
        print(f"{n:13} {len(tables[n]):6}")
    if (build / "cppref").is_dir():
        print(f"cppref        {sum(1 for _ in (build / 'cppref').rglob('*.html')):6} html files")
    print()
    for name, problems, warn in c.results:
        print(f"{'ok  ' if not problems else 'warn' if warn else 'FAIL'} {name}" +
              (f"  ({len(problems)}: {', '.join(map(str, problems[:5]))}"
               f"{', ...' if len(problems) > 5 else ''})" if problems else ""))
    sys.exit(0 if c.ok else 1)


if __name__ == "__main__":
    main()
