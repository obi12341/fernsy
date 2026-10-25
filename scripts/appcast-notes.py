#!/usr/bin/env python3
"""Adds English release notes to an appcast written by generate_appcast.

    scripts/appcast-notes.py appcast.xml notes-en.html

generate_appcast embeds one notes file per archive (the German one) and ignores localized
files, so its <description> is marked xml:lang="de" and an English one is added next to it.
Sparkle shows the description matching the preferred languages, otherwise the first.
The appcast itself is unsigned (only the DMG has an EdDSA signature), so editing it is safe;
everything except the descriptions stays byte for byte.
"""
import re
import sys
import xml.etree.ElementTree as ET

path, notes_path = sys.argv[1], sys.argv[2]
text = open(path, encoding="utf-8").read()
english = open(notes_path, encoding="utf-8").read().strip().replace("]]>", "]]]]><![CDATA[>")

matches = list(re.finditer(r"([ \t]*)<description>(.*?)</description>", text, re.S))
if len(matches) != 1:
    sys.exit(f"expected one <description> in {path}, found {len(matches)}")
m = matches[0]
indent = m.group(1)
replacement = (f'{indent}<description xml:lang="de">{m.group(2)}</description>\n'
               f'{indent}<description xml:lang="en"><![CDATA[{english}\n]]></description>')
result = text[:m.start()] + replacement + text[m.end():]

# Still well-formed, both languages present, the download signature untouched.
root = ET.fromstring(result.encode("utf-8"))
lang = "{http://www.w3.org/XML/1998/namespace}lang"
langs = [d.get(lang) for d in root.iter("description")]
if langs != ["de", "en"]:
    sys.exit(f"unexpected descriptions after editing: {langs}")
signature = re.findall(r'sparkle:edSignature="[^"]*"', text)
if not signature or signature != re.findall(r'sparkle:edSignature="[^"]*"', result):
    sys.exit("the enclosure signature is missing or changed")

open(path, "w", encoding="utf-8").write(result)
