"""Read and rewrite inputs.lock (shared by the data-layer scripts)."""

import re
import sys
from pathlib import Path

LINE = re.compile(r"^(?P<key>[a-z0-9_]+)\s*=\s*(?P<value>.*?)\s*$")


def read(path):
    entries = {}
    for raw in Path(path).read_text(encoding="utf-8").splitlines():
        line = raw.split("#", 1)[0].strip()
        if not line:
            continue
        m = LINE.match(line)
        if not m:
            sys.exit(f"{path}: malformed line: {raw!r}")
        entries[m["key"]] = m["value"]
    return entries


def require(entries, *keys, path="inputs.lock"):
    missing = [k for k in keys if not entries.get(k)]
    if missing:
        sys.exit(f"{path}: required field(s) empty: {', '.join(missing)}")
    return [entries[k] for k in keys]


def update(path, **changes):
    """Rewrite values in place, keeping comments and layout."""
    path = Path(path)
    out = []
    pending = dict(changes)
    for raw in path.read_text(encoding="utf-8").splitlines():
        m = LINE.match(raw.split("#", 1)[0].rstrip())
        if m and m["key"] in pending:
            prefix = raw[: raw.index("=") + 1]
            raw = f"{prefix} {pending.pop(m['key'])}"
        out.append(raw)
    if pending:
        sys.exit(f"{path}: unknown field(s): {', '.join(pending)}")
    path.write_text("\n".join(out) + "\n", encoding="utf-8")
