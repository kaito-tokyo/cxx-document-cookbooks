#!/usr/bin/env python3

# SPDX-FileCopyrightText: 2026 Kaito Udagawa <umireon@kaito.tokyo>
#
# SPDX-License-Identifier: Apache-2.0

"""Extract the data tables from the rendered draft (build/draft-html/).

usage: extract_tables.py BUILD_DIR [--out DIR]

Writes DIR/*.json (default BUILD_DIR/data/) and BUILD_DIR/db.sqlite.
The tables and their meaning are specified in data/CONTRACT.md.
"""

import argparse
import json
import os
import re
import sqlite3
import subprocess
import sys
import urllib.parse
from pathlib import Path

import lxml.html

CONTRACT_VERSION = 1

INDEX_PAGES = {
    "libraryindex": "library",
    "headerindex": "header",
    "generalindex": "general",
    "grammarindex": "grammar",
    "conceptindex": "concept",
    "impldefindex": "impldef",
}
TOC_PAGES = {"index": "toc", "fulltoc": "toc", "full": "full",
             "footnotes": "list", "tab": "list", "fig": "list"}
PREFIX_KINDS = {"tab:": "table", "fig:": "figure", "ub:": "ub", "ifndr:": "ifndr"}
HEADINGS = ("h1", "h2", "h3", "h4", "h5", "h6")
WS = re.compile(r"\s+")


def text(el):
    return WS.sub(" ", el.text_content()).strip()


def parse(path):
    return lxml.html.parse(str(path)).getroot()


def heading_parts(h):
    """(number, title, abbr_ref element) of a TOC/breadcrumb heading."""
    num = h.find_class("secnum")
    ref = h.find_class("abbr_ref")
    number = text(num[0]) if num else ""
    number = re.sub(r"^Annex\s+", "", number).strip()
    pieces = [h.text or ""]
    for child in h:
        cls = child.get("class") or ""
        if cls not in ("secnum", "abbr_ref", "folded_abbr_ref", "unfolded_abbr_ref") \
                and child.tag != "div":
            pieces.append(child.text_content())
        pieces.append(child.tail or "")
    title = WS.sub(" ", "".join(pieces)).strip()
    return number, title, (ref[0] if ref else None)


def split_href(href):
    """'x.html#a' -> ('x.html', 'x', 'a'). Links into the TOC ('index.html#x') name x."""
    page, _, anchor = href.partition("#")
    stable = page[:-5] if page.endswith(".html") else page
    if stable == "index" and anchor:
        stable = anchor
    return page, stable, anchor


# --- sections ---------------------------------------------------------------

def toc_sections(html_dir):
    root = parse(html_dir / "fulltoc.html")
    rows = []
    for div in root.iter("div"):
        sid = div.get("id")
        h = next((c for c in div if c.tag in HEADINGS), None)
        if not sid or h is None:
            continue
        number, title, _ = heading_parts(h)
        parent = next((a.get("id") for a in div.iterancestors("div") if a.get("id")), None)
        rows.append({"stable_name": sid, "number": number, "title": title,
                     "parent": parent, "path": f"{sid}.html"})
    by_name = {r["stable_name"]: r for r in rows}
    for r in rows:
        depth, p = 0, r["parent"]
        while p:
            depth, p = depth + 1, by_name[p]["parent"]
        r["depth"] = depth
        if not r["number"]:
            r["kind"] = "unnumbered"
        elif depth == 0:
            r["kind"] = "annex" if r["number"][0].isalpha() else "clause"
        else:
            r["kind"] = "subclause"
    return rows


def item_page(root):
    """Breadcrumb-style page for a single item (definition, ub, ifndr, table, figure).

    Returns (number, title, parent stable name, parent anchor) from its last heading.
    """
    heads = [h for h in root.iter(*HEADINGS)]
    if not heads:
        return None
    number, title, ref = heading_parts(heads[-1])
    parent = None
    for h in reversed(heads[:-1]):
        _, _, pref = heading_parts(h)
        if pref is not None and pref.get("href"):
            parent = split_href(pref.get("href"))[1]
            break
    return number, title, parent


# --- pages ------------------------------------------------------------------

XREF_BODY = re.compile(r"^(Subclause \[[^\]]+\] was removed\.|See .*\.)$")


def classify(html_dir, toc_names):
    pages, definitions, behaviors, floats, xrefs = [], [], [], [], []
    for name in sorted(os.listdir(html_dir)):
        path = html_dir / name
        if not name.endswith(".html"):
            pages.append({"path": name, "kind": "asset", "stable_name": None})
            continue
        base = name[:-5]
        kind, stable = None, None
        if base in TOC_PAGES:
            kind = TOC_PAGES[base]
        elif base in INDEX_PAGES:
            kind = "index"
        elif base in toc_names:
            kind, stable = "section", base
        else:
            prefix = next((p for p in PREFIX_KINDS if base.startswith(p)), None)
            root = parse(path)
            wrapper = root.find_class("wrapper")
            body = text(wrapper[0]) if wrapper else ""
            if prefix:
                kind = PREFIX_KINDS[prefix]
                info = item_page(root)
                ident = base[len(prefix):]
                if kind in ("ub", "ifndr"):
                    spec = root.find_class("behaviorspecifiedin")
                    href = spec[0].find(".//a").get("href") if spec else None
                    behaviors.append({
                        "id": base, "kind": kind, "number": info[0] if info else "",
                        "parent": info[2] if info else None,
                        "specified_in": split_href(href)[1] if href else None,
                        "specified_anchor": split_href(href)[2] if href else None,
                        "path": name})
                else:
                    # The last heading is the section that contains the float.
                    href = next((r.get("href") for h in reversed(list(root.iter(*HEADINGS)))
                                 for r in h.find_class("abbr_ref") if r.get("href")), None)
                    cap = re.search(r"(Table|Figure)\s+(\d+)\s+—\s+(.*?)\s*\[(tab|fig):", body)
                    floats.append({
                        "id": base, "kind": kind,
                        "number": cap.group(2) if cap else "",
                        "caption": cap.group(3) if cap else "",
                        "section": split_href(href)[1] if href else None,
                        "anchor": ident, "path": name})
            elif XREF_BODY.match(body) and not root.find_class("para"):
                kind, stable = "xref", base
                targets = [split_href(a.get("href"))[1]
                           for a in wrapper[0].iter("a") if a.get("href")]
                xrefs.append({"stable_name": base, "targets": targets})
            else:
                info = item_page(root)
                heads = list(root.iter(*HEADINGS))
                last_ref = heads[-1].find_class("abbr_ref") if heads else []
                if (info and last_ref and not last_ref[0].get("href")
                        and text(last_ref[0]) == f"[{base}]"):
                    kind, stable = "definition", base
                    definitions.append({
                        "stable_name": base, "number": info[0], "title": info[1],
                        "parent": info[2], "path": name, "kind": "definition"})
                else:
                    kind = "unknown"
        pages.append({"path": name, "kind": kind, "stable_name": stable})
    return pages, definitions, behaviors, floats, xrefs


# --- code -------------------------------------------------------------------

def code_blocks(html_dir, sections):
    """Code that belongs directly to each section: itemdecls and code blocks.

    A section page is flat: breadcrumb headings, the section's own content,
    then headings and content of its subsections. Only code between the
    section's own heading and the next heading is attributed to it, and
    anchors are taken from that page (ids differ on enclosing pages).
    """
    rows = []
    for sec in sections:
        if sec["kind"] == "definition":
            continue
        name = sec["stable_name"]
        root = parse(html_dir / sec["path"])
        inside, n = False, 0
        for el in root.iter():
            if el.tag in HEADINGS:
                ref = el.find_class("abbr_ref")
                inside = bool(ref) and text(ref[0]).strip("[]") == name
                continue
            classes = (el.get("class") or "").split()
            if not inside or not ({"itemdecl", "codeblock"} & set(classes)):
                continue
            ancestors = list(el.iterancestors())
            if any("codeblock" in (a.get("class") or "").split() for a in ancestors):
                continue
            if "itemdecl" in classes:
                kind = "itemdecl"
                link = el.find_class("itemDeclLink")
                anchor = link[0].get("href", "").lstrip("#") if link else None
                code_el = (el.find_class("itemdeclcode") or [el])[0]
            else:
                if any("itemdecl" in (a.get("class") or "").split() for a in ancestors):
                    continue
                kind = "codeblock"
                anchor = next((a.get("id") for a in ancestors if a.get("id")), None)
                code_el = el
            n += 1
            rows.append({
                "section": name, "n": n, "kind": kind, "anchor": anchor,
                "in_example": any((a.get("class") or "").split()[:1] == ["example"]
                                  for a in ancestors),
                "code": code_el.text_content().strip()})
    for i, r in enumerate(rows):
        r["ord"] = i
    return rows


# --- index entries ----------------------------------------------------------

def index_entries(html_dir):
    rows = []
    for page, category in INDEX_PAGES.items():
        root = parse(html_dir / f"{page}.html")
        for div in root.iter("div"):
            items = div.find("div[@class='indexitems']") if div.get("id") else None
            if items is None:
                continue
            node = div.get("id")
            parent_div = div.getparent().getparent()
            parent = parent_div.get("id") if parent_div is not None and \
                parent_div.find("div[@class='indexitems']") is not None else None
            # Display text of this node: everything before its first link,
            # "see" marker, or child node.
            pieces = [items.text or ""]
            links, see = [], None
            for child in items:
                if child.tag in ("a", "div", "i"):
                    break
                pieces.append(child.text_content())
                pieces.append(child.tail or "")
            term = WS.sub(" ", "".join(pieces)).strip().rstrip(",").strip()
            for child in items:
                if child.tag == "i" and text(child) in ("see", "see also"):
                    see = text(child)
                elif child.tag == "a" and child.get("href"):
                    href = child.get("href")
                    if href.startswith("#"):
                        links.append({"see": see or "see",
                                      "see_target": urllib.parse.unquote(href[1:])})
                    else:
                        _, stable, anchor = split_href(href)
                        links.append({"section": stable, "anchor": anchor, "href": href,
                                      "definition": child.find("b") is not None})
            rows.append({"category": category, "node": node, "parent": parent,
                         "term": term, "links": links})
    # Resolve paths (sequence of terms from the root) and flatten.
    by_node = {(r["category"], r["node"]): r for r in rows}
    out = []
    for ord_, r in enumerate(rows):
        path, p = [], r
        while p is not None:
            path.append(p["term"])
            p = by_node.get((r["category"], p["parent"])) if p["parent"] else None
        path.reverse()
        base = {"category": r["category"], "node": r["node"], "parent": r["parent"],
                "depth": len(path) - 1, "path": path, "term": r["term"]}
        if not r["links"]:
            out.append({**base, "section": None, "anchor": None, "href": None,
                        "definition": False, "see": None, "see_target": None})
        for link in r["links"]:
            out.append({**base, "section": link.get("section"), "anchor": link.get("anchor"),
                        "href": link.get("href"), "definition": link.get("definition", False),
                        "see": link.get("see"), "see_target": link.get("see_target")})
    for i, row in enumerate(out):
        row["ord"] = i
    return out


# --- output -----------------------------------------------------------------

SCHEMA = {
    "sections": [("stable_name", "TEXT PRIMARY KEY"), ("kind", "TEXT"), ("number", "TEXT"),
                 ("title", "TEXT"), ("parent", "TEXT"), ("depth", "INTEGER"),
                 ("ord", "INTEGER"), ("path", "TEXT")],
    "index_entries": [("ord", "INTEGER PRIMARY KEY"), ("category", "TEXT"), ("node", "TEXT"),
                      ("parent", "TEXT"), ("depth", "INTEGER"), ("path", "TEXT"),
                      ("term", "TEXT"), ("section", "TEXT"), ("anchor", "TEXT"),
                      ("href", "TEXT"), ("definition", "INTEGER"), ("see", "TEXT"),
                      ("see_target", "TEXT")],
    "code": [("ord", "INTEGER PRIMARY KEY"), ("section", "TEXT"), ("n", "INTEGER"),
             ("kind", "TEXT"), ("anchor", "TEXT"), ("in_example", "INTEGER"), ("code", "TEXT")],
    "xrefs": [("stable_name", "TEXT PRIMARY KEY"), ("targets", "TEXT")],
    "behaviors": [("id", "TEXT PRIMARY KEY"), ("kind", "TEXT"), ("number", "TEXT"),
                  ("parent", "TEXT"), ("specified_in", "TEXT"), ("specified_anchor", "TEXT"),
                  ("path", "TEXT")],
    "floats": [("id", "TEXT PRIMARY KEY"), ("kind", "TEXT"), ("number", "TEXT"),
               ("caption", "TEXT"), ("section", "TEXT"), ("anchor", "TEXT"), ("path", "TEXT")],
    "pages": [("path", "TEXT PRIMARY KEY"), ("kind", "TEXT"), ("stable_name", "TEXT")],
    "inputs": [("key", "TEXT PRIMARY KEY"), ("value", "TEXT")],
}


def write_json(path, rows):
    path.write_text(json.dumps(rows, ensure_ascii=False, indent=1, sort_keys=True) + "\n",
                    encoding="utf-8")


def write_sqlite(path, tables):
    tmp = path.with_suffix(".tmp")
    tmp.unlink(missing_ok=True)
    db = sqlite3.connect(tmp)
    for name, cols in SCHEMA.items():
        db.execute(f"CREATE TABLE {name} ({', '.join(f'{c} {t}' for c, t in cols)})")
        keys = [c for c, _ in cols]
        values = []
        for row in tables[name]:
            v = [row.get(k) for k in keys]
            v = [json.dumps(x, ensure_ascii=False) if isinstance(x, list) else
                 int(x) if isinstance(x, bool) else x for x in v]
            values.append(v)
        db.executemany(f"INSERT INTO {name} VALUES ({', '.join('?' * len(keys))})", values)
    db.commit()
    db.execute("VACUUM")
    db.close()
    tmp.replace(path)


def git_out(path, *args):
    return subprocess.run(["git", "-C", str(path), *args],
                          check=True, text=True, capture_output=True).stdout.strip()


def provenance(build):
    """The commits and toolchain the rendered draft was built from."""
    inputs = {}
    for prefix, subdir in (("draft", "draft-src"), ("htmlgen", "htmlgen-src")):
        inputs[f"{prefix}_repo"] = git_out(build / subdir, "remote", "get-url", "origin")
        inputs[f"{prefix}_commit"] = git_out(build / subdir, "rev-parse", "HEAD")
    stamp = build / "bin" / "cxxdraft-htmlgen.stamp"
    fields = stamp.read_text().split() if stamp.is_file() else []
    for f in fields:
        for tool in ("ghc", "cabal"):
            if f.startswith(tool + "-"):
                inputs[f"htmlgen_{tool}"] = f[len(tool) + 1:]
    inputs["draft_commit_date"] = git_out(build / "draft-src", "log", "-1", "--format=%cI")
    inputs["contract_version"] = str(CONTRACT_VERSION)
    return [{"key": k, "value": v} for k, v in sorted(inputs.items())]


def extract(build, out_dir, db_path):
    html_dir = build / "draft-html"
    if not (html_dir / "fulltoc.html").is_file():
        sys.exit(f"{html_dir}: not rendered; run build_draft.sh first")

    toc = toc_sections(html_dir)
    toc_names = {r["stable_name"] for r in toc}
    pages, definitions, behaviors, floats, xrefs = classify(html_dir, toc_names)

    sections = toc + definitions
    order = {r["stable_name"]: i for i, r in enumerate(toc)}
    # Definitions follow their parent section in document order.
    sections.sort(key=lambda r: (order.get(r["stable_name"], order.get(r["parent"], -1) + 0.5),
                                 [int(x) if x.isdigit() else x for x in r["number"].split(".")]))
    by_name = {}
    for i, r in enumerate(sections):
        r["ord"] = i
        if r["kind"] == "definition":
            r["depth"] = by_name[r["parent"]]["depth"] + 1
        by_name[r["stable_name"]] = r

    inputs = provenance(build)

    tables = {
        "sections": sections,
        "index_entries": index_entries(html_dir),
        "code": code_blocks(html_dir, sections),
        "xrefs": xrefs,
        "behaviors": behaviors,
        "floats": floats,
        "pages": pages,
        "inputs": inputs,
    }
    out_dir.mkdir(parents=True, exist_ok=True)
    for stale in out_dir.glob("*.json"):
        stale.unlink()
    for name, rows in tables.items():
        write_json(out_dir / f"{name}.json", rows)
    if db_path:
        write_sqlite(db_path, tables)
    return tables


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("build")
    ap.add_argument("--out", help="JSON output directory (default BUILD/data); skips db.sqlite")
    args = ap.parse_args()
    build = Path(args.build)
    out = Path(args.out) if args.out else build / "data"
    tables = extract(build, out, None if args.out else build / "db.sqlite")
    for name, rows in tables.items():
        print(f"{name}: {len(rows)}")


if __name__ == "__main__":
    main()
