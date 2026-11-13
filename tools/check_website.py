#!/usr/bin/env python3
"""Smoke-check website-dist after tools/build_website.py."""

from __future__ import annotations

import json
import os
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "website-dist"


def main() -> int:
    problems = []
    for name in ("index.html", "app.js", "style.css", "catalog.json", "favicon.svg", "notices.txt"):
        if not (OUT / name).exists():
            problems.append("missing " + name)
    cat = json.loads((OUT / "catalog.json").read_text(encoding="utf-8"))
    meta = cat["metadata"]
    # Cross-check against live rules count
    rules = 0
    for f in (ROOT / "rules").glob("*.json"):
        if f.name == "algorithms.json":
            continue
        rules += len(json.loads(f.read_text(encoding="utf-8"))["rules"])
    if meta["rule_count_total"] != rules:
        problems.append("catalog rule_count_total %s != rules on disk %s" % (meta["rule_count_total"], rules))
    if meta["full_identifier_count"] + meta["component_or_routing_count"] != meta["rule_count_total"]:
        problems.append("full+component != total")
    html = (OUT / "index.html").read_text(encoding="utf-8")
    if "PII Atlas" not in html:
        problems.append("index missing brand")
    if "__RULE_COUNT__" in html:
        problems.append("index placeholders not substituted")
    js = (OUT / "app.js").read_text(encoding="utf-8")
    if "fetch(\"catalog.json\"" not in js and "fetch('catalog.json'" not in js:
        problems.append("app.js does not load catalog.json")
    # No live validation endpoint hooks
    for bad in ("/validate", "navigator.sendBeacon", "gtag(", "analytics"):
        if bad in js.lower() and bad == "analytics" and "No analytics" in (OUT / "notices.txt").read_text():
            continue
        if bad in ("/validate", "navigator.sendBeacon") and bad in js:
            problems.append("forbidden pattern in app.js: " + bad)
    print("website-dist rules=%d full=%d components=%d" % (
        meta["rule_count_total"], meta["full_identifier_count"], meta["component_or_routing_count"]))
    if problems:
        print("%d problem(s):" % len(problems))
        for p in problems:
            print(" -", p)
        return 1
    print("check_website: OK")
    return 0


if __name__ == "__main__":
    sys.exit(main())
