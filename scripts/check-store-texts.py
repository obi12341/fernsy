#!/usr/bin/env python3
"""Checks the App Store texts in docs/app-store.md against App Store Connect's limits.

Every '### Title (limit)' heading is followed by the text up to the next heading.
Keywords are counted in UTF-8 bytes, like App Store Connect does.
"""
import os, re, sys

path = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "docs", "app-store.md")
text = open(path, encoding="utf-8").read()
ok = True
for m in re.finditer(r"^### (.+?) \((\d+)\)\n(.*?)(?=^#{2,3} |\Z)", text, re.S | re.M):
    title, limit, body = m.group(1), int(m.group(2)), m.group(3).strip().rstrip("-").strip()
    is_keywords = "Keywords" in title or "Schlüsselwörter" in title
    length = len(body.encode("utf-8")) if is_keywords else len(body)
    status = "OK " if length <= limit else "TOO LONG"
    if length > limit: ok = False
    print(f"{status} {length:5}/{limit:<5} {title}")
sys.exit(0 if ok else 1)
