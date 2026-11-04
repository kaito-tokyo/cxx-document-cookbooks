#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 Kaito Udagawa <umireon@kaito.tokyo>
#
# SPDX-License-Identifier: Apache-2.0

"""Build a static site from a token stream of tokens/run.sh.

usage: build_site.py TOKENS.jsonl OUTPUT_DIR

Writes one page per clause or annex (\\rSec0), one per unnumbered part of
the back matter (bibliography, cross-references, indexes) and index.html,
a table of contents. Formulas are typeset into SVG by MathJax 3 for Node
(render-math.js; Ubuntu: nodejs and node-mathjax-full), so the pages need
no script. The front matter (cover, foreword, contents) is left out.
"""

import html
import json
import os
import re
import subprocess
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent

def read_tokens(path):
    with open(path, encoding="utf-8") as f:
        return [json.loads(line) for line in f if line.strip()]


def split_pages(tokens):
    """Return [(start, end, name)] for the pages, and the start of main matter."""
    starts = [i for i, t in enumerate(tokens) if t.get("mark", "").startswith("section 0 ")]
    if not starts:
        raise SystemExit("build_site.py: no \\rSec0 in the token stream")
    pages = []
    for k, i in enumerate(starts):
        pages.append([i, None, tokens[i]["mark"].split()[2]])
    # Back matter: each part (bibliography, cross-references, an index) has
    # a "part" mark after the last clause. Each part starts a new page, and
    # its title and prologue may come before the mark (they are set above
    # the columns), so the part starts at the page destination before it.
    back = 0
    last_page = None
    for i in range(starts[-1] + 1, len(tokens)):
        t = tokens[i]
        if t.get("anchor", "").startswith("page."):
            last_page = i
        elif t.get("mark") == "part":
            start = last_page if last_page is not None and last_page >= pages[-1][0] else i
            if start <= pages[-1][0] and back:
                continue  # a second mark for the same part
            start = max(start, pages[-1][0] + 1)
            back += 1
            pages.append([start, None, f"back{back}"])
    for k in range(len(pages) - 1):
        pages[k][1] = pages[k + 1][0]
    pages[-1][1] = len(tokens)
    return [tuple(p) for p in pages], starts[0]


class Page:
    """Turns the tokens of one page into HTML."""

    def __init__(self, anchor_page, math_html):
        self.anchor_page = anchor_page  # anchor -> page file
        self.math_html = math_html  # (tex, display) -> typeset HTML
        self.out = []
        self.blocks = []  # open block elements: ("section", level) / ("div", None)
        self.inline = []  # open inline end tags
        self.in_p = False
        self.in_pre = False
        self.pre_started = False
        self.heading = None  # while a section heading is read
        self.toc = []  # (level, id, number, title)

    def write(self, s):
        (self.heading["buf"] if self.heading and self.heading["state"] == "title" else self.out).append(s)

    # Blocks.
    def open_p(self):
        if not self.in_p and not self.in_pre and not self.heading:
            self.out.append("<p>")
            self.in_p = True

    def close_inline(self):
        while self.inline:
            self.write(self.inline.pop())

    def close_p(self):
        if self.in_p:
            self.close_inline()
            self.out.append("</p>\n")
            self.in_p = False

    def close_pre(self):
        if self.in_pre:
            self.close_inline()
            self.out.append("</code></pre>\n")
            self.in_pre = False

    def close_blocks(self, until=None):
        self.close_p()
        self.close_pre()
        while self.blocks:
            kind, level = self.blocks[-1]
            if until is not None and kind == "section" and level < until:
                break
            self.blocks.pop()
            self.out.append("</section>\n" if kind == "section" else "</div>\n")

    # Inline.
    def open_inline(self, start, end):
        if not self.in_pre:
            self.open_p()
        self.write(start)
        self.inline.append(end)

    def close_inline_tag(self, end):
        if end in self.inline:
            while self.inline:
                e = self.inline.pop()
                self.write(e)
                if e == end:
                    break

    def href(self, target):
        if re.match(r"[a-z]+:", target):
            return target
        page = self.anchor_page.get(target)
        if page is None:
            return None
        return f"{page}#{target}"

    def text(self, s):
        if self.heading:
            if self.heading["state"] == "number":
                self.heading["number"] += s
            elif self.heading["state"] == "title":
                self.heading["buf"].append(html.escape(s, quote=False))
            return
        if not self.in_pre:
            self.open_p()
        self.write(html.escape(s, quote=False))

    def finish_heading(self):
        h = self.heading
        self.heading = None
        level = h["level"]
        number = h["number"].strip()
        title = "".join(h["buf"])
        tag = f"h{min(level + 1, 6)}"
        self.out.append(f"<{tag}>{html.escape(number)} {title} <small>[{html.escape(h['id'])}]</small></{tag}>\n")
        self.toc.append((level, h["id"], number, re.sub(r"<[^>]*>", "", title)))

    def token(self, t):
        if "text" in t:
            self.text(t["text"])
        elif "nl" in t:
            if self.heading and self.heading["state"] == "after":
                self.finish_heading()
            elif self.in_pre:
                pass
            elif self.in_p:
                self.write(" ")
        elif "par" in t:
            if self.heading:
                return
            if self.in_pre:
                if self.pre_started:
                    self.write("\n")
                self.pre_started = True
            else:
                self.close_p()
        elif "anchor" in t:
            a = html.escape(t["anchor"])
            if self.heading:
                self.out.append(f'<span id="{a}"></span>')
            else:
                self.write(f'<span id="{a}"></span>')
        elif "link" in t:
            href = self.href(t["link"])
            if href is None:
                self.open_inline('<span class="link">', "</span>")
            else:
                self.open_inline(f'<a href="{html.escape(href)}">', "</a>")
        elif "endlink" in t:
            if "</a>" in self.inline:
                self.close_inline_tag("</a>")
            else:
                self.close_inline_tag("</span>")
        elif "math" in t:
            if not self.in_pre:
                self.open_p()
            self.write(self.math_html[(t["math"], False)])
        elif "displaymath" in t:
            self.close_p()
            self.out.append(f'<div class="math">{self.math_html[(t["displaymath"], True)]}</div>\n')
        elif "mark" in t:
            self.mark(t["mark"])

    def mark(self, m):
        words = m.split()
        if words[0] == "section":
            level, ident = int(words[1]), words[2]
            self.close_blocks(until=level)
            self.out.append(f'<section id="{html.escape(ident)}">\n')
            self.blocks.append(("section", level))
            self.heading = {"level": level, "id": ident, "state": "number", "number": "", "buf": []}
        elif m == "begin title" and self.heading:
            self.heading["state"] = "title"
        elif m == "end title" and self.heading:
            while self.inline:
                self.heading["buf"].append(self.inline.pop())
            self.heading["state"] = "after"
        elif self.heading and self.heading["state"] == "after":
            pass
        elif m in ("begin note", "begin example"):
            self.close_p()
            self.close_pre()
            self.out.append(f'<div class="{words[1]}">\n')
            self.blocks.append(("div", None))
        elif m in ("end note", "end example"):
            self.close_p()
            self.close_pre()
            for k in range(len(self.blocks) - 1, -1, -1):
                if self.blocks[k][0] == "div":
                    while len(self.blocks) > k:
                        kind, _ = self.blocks.pop()
                        self.out.append("</section>\n" if kind == "section" else "</div>\n")
                    break
        elif m == "begin codeblock":
            self.close_p()
            self.out.append("<pre><code>")
            self.in_pre = True
            self.pre_started = False
        elif m == "end codeblock":
            self.close_pre()
        elif m == "begin tcode":
            self.open_inline("<code>", "</code>")
        elif m == "end tcode":
            self.close_inline_tag("</code>")
        elif m == "begin grammarterm":
            self.open_inline('<i class="grammarterm">', "</i>")
        elif m == "end grammarterm":
            self.close_inline_tag("</i>")
        elif m == "begin defn":
            self.open_inline("<dfn>", "</dfn>")
        elif m == "end defn":
            self.close_inline_tag("</dfn>")

    def html(self):
        if self.heading:
            self.finish_heading()
        self.close_blocks()
        return "".join(self.out)


HEAD = """<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>{title}</title>
<link rel="stylesheet" href="style.css">
</head>
<body>
<nav><a href="index.html">Contents</a></nav>
"""

TAIL = "</body>\n</html>\n"


def page_title(page):
    if page.toc:
        level, ident, number, title = page.toc[0]
        return f"{number} {title} [{ident}]".strip()
    return None


def typeset_math(tokens):
    """Typeset every distinct formula once with render-math.js."""
    keys = []
    seen = set()
    for t in tokens:
        for kind, display in (("math", False), ("displaymath", True)):
            if kind in t and (t[kind], display) not in seen:
                seen.add((t[kind], display))
                keys.append((t[kind], display))
    request = json.dumps([{"tex": tex, "display": display} for tex, display in keys])
    # Ubuntu's node-mathjax-full lives in /usr/share/nodejs, which only
    # Ubuntu's own node searches by default.
    env = dict(os.environ)
    env["NODE_PATH"] = os.pathsep.join(p for p in (env.get("NODE_PATH"), "/usr/share/nodejs") if p)
    result = subprocess.run(["node", str(HERE / "render-math.js")], input=request,
                            capture_output=True, text=True, check=True, env=env)
    reply = json.loads(result.stdout)
    return dict(zip(keys, reply["html"])), reply["css"]


def main():
    tokens_path, out_dir = sys.argv[1], Path(sys.argv[2])
    tokens = read_tokens(tokens_path)
    pages, _ = split_pages(tokens)
    math_html, math_css = typeset_math(tokens)

    anchor_page = {}
    for start, end, name in pages:
        for t in tokens[start:end]:
            if "anchor" in t:
                anchor_page.setdefault(t["anchor"], f"{name}.html")

    out_dir.mkdir(parents=True, exist_ok=True)
    contents = []
    # A part of the back matter with no text at all (an empty glossary, such
    # as the cross-references from the previous standard in N4861) is left out.
    pages = [p for p in pages if not p[2].startswith("back")
             or any(t.get("text", "").strip() for t in tokens[p[0]:p[1]])]
    for start, end, name in pages:
        page = Page(anchor_page, math_html)
        for t in tokens[start:end]:
            page.token(t)
        body = page.html()
        title = page_title(page)
        if title is None:
            first = next((t["text"] for t in tokens[start:end] if t.get("text", "").strip()), name)
            title = first.strip()
        (out_dir / f"{name}.html").write_text(HEAD.format(title=html.escape(title)) + body + TAIL, encoding="utf-8")
        contents.append((name, title, [e for e in page.toc if e[0] == 1]))

    items = []
    for name, title, subs in contents:
        items.append(f'<li><a href="{name}.html">{html.escape(title)}</a>')
        if subs:
            items.append("<ul>")
            items += [f'<li><a href="{name}.html#{html.escape(i)}">{html.escape(n)} {html.escape(t)}</a></li>'
                      for _, i, n, t in subs]
            items.append("</ul>")
        items.append("</li>")
    index = HEAD.format(title="Contents") + "<h1>Contents</h1>\n<ul>\n" + "\n".join(items) + "\n</ul>\n" + TAIL
    (out_dir / "index.html").write_text(index, encoding="utf-8")

    style = ".note, .example { margin-left: 2em; }\npre { margin-left: 1em; }\n"
    (out_dir / "style.css").write_text(style + math_css, encoding="utf-8")
    print(f"wrote {len(pages)} pages to {out_dir}")


if __name__ == "__main__":
    main()
