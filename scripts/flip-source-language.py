#!/usr/bin/env python3
"""One-time tool of the change fernsy-core-package (design K): makes English the source
language of Fernsy's UI.

  scripts/flip-source-language.py            # dry run: report only
  scripts/flip-source-language.py --write    # rewrite Swift literals and the string catalogs

For every key of the catalogs it finds the Swift string literals that produce it (exact text,
or text segments around interpolations), replaces them with the English value (interpolations
reordered as the English positional placeholders say) and rebuilds the catalog with English as
source and the old German text as German translation.
"""
import json
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
SOURCES = sorted((ROOT / "Fernsy").rglob("*.swift"))
CATALOGS = [ROOT / "Fernsy/Localizable.xcstrings", ROOT / "Fernsy/AppShortcuts.xcstrings"]
WRITE = "--write" in sys.argv

PRINTF = re.compile(r"%(?:(\d+)\$)?([-+ #0]*\d*(?:\.\d+)?(?:ll|l|h|hh|z|t|j|L|q)?[@dDiuUxXoOfeEgGcCsSpaA])")
SHORTCUT = re.compile(r"\$\{([A-Za-z]+)\}")
# German texts whose English value collides with another key's: they get their own English.
ENGLISH = {
    "%lld Kanäle": "%lld audio channels",
    "Einblenden": "Unhide",
    "Wiedergabe": "Playback",
    "Zeitpuffer": "Timeshift buffer",
    "Netz": "Net",
}
# German texts merged into another key with the same meaning (German wording of the other wins).
MERGE = {"Live-TV": "Live TV"}
# Calls that show a literal to the user; other lines with a rewritten literal are listed for review.
UI_MARKERS = re.compile(r"Text\(|Button\(|Label\(|help\(|String\(localized|Toggle\(|Picker\(|Section\(|Menu\(|"
                        r"navigationTitle|navigationSubtitle|title:|Title|Window\(|tabItem|accessibilityLabel|"
                        r"LocalizedStringResource|LocalizedStringKey|Summary\(|dialog|placeholder|prompt|"
                        r"legend\(|row\(|Link\(|confirmationDialog|alert\(|ContentUnavailableView|DisplayRepresentation")


# MARK: Swift literal scanner

class Literal:
    """A single-line, non-raw string literal: alternating text (unescaped) and interpolations."""

    def __init__(self, path, start, end, parts):
        self.path, self.start, self.end, self.parts = path, start, end, parts

    @property
    def texts(self):
        return [p for i, p in enumerate(self.parts) if i % 2 == 0]

    @property
    def exprs(self):
        return [p for i, p in enumerate(self.parts) if i % 2 == 1]


ESCAPES = {"n": "\n", "t": "\t", "r": "\r", "0": "\0", '"': '"', "'": "'", "\\": "\\"}


def scan(path, src):
    """Yields the string literals of a Swift file, skipping comments, raw and multi-line strings."""
    i, n = 0, len(src)
    while i < n:
        c = src[i]
        if src.startswith("//", i):
            i = src.find("\n", i)
            i = n if i < 0 else i
        elif src.startswith("/*", i):
            depth, i = 1, i + 2
            while i < n and depth:
                if src.startswith("/*", i):
                    depth, i = depth + 1, i + 2
                elif src.startswith("*/", i):
                    depth, i = depth - 1, i + 2
                else:
                    i += 1
        elif src.startswith('"""', i) or src.startswith('#"', i):
            # Multi-line and raw strings hold no UI texts in Fernsy; skip to their end.
            close = '"""' if src.startswith('"""', i) else '"#'
            j = src.find(close, i + 3 if close == '"""' else i + 2)
            i = n if j < 0 else j + len(close)
        elif c == '"':
            lit, i = read_literal(path, src, i)
            if lit:
                yield lit
        else:
            i += 1


def read_literal(path, src, start):
    """Reads the literal at `start` (a quote). Returns (Literal or None, index after it)."""
    i, parts, text = start + 1, [], []
    while i < len(src):
        c = src[i]
        if c == '"':
            parts.append("".join(text))
            return Literal(path, start, i + 1, parts), i + 1
        if c == "\n":
            return None, i
        if c == "\\":
            nxt = src[i + 1]
            if nxt == "(":
                parts.append("".join(text))
                text = []
                j, depth = i + 2, 1
                while depth:
                    ch = src[j]
                    if ch == '"':
                        inner, j = read_literal(path, src, j)
                        continue
                    depth += ch == "("
                    depth -= ch == ")"
                    j += 1
                parts.append(src[i + 2:j - 1])
                i = j
                continue
            if nxt == "u":
                close = src.index("}", i)
                text.append(chr(int(src[i + 3:close], 16)))
                i = close + 1
                continue
            text.append(ESCAPES.get(nxt, nxt))
            i += 2
            continue
        text.append(c)
        i += 1
    return None, i


def escape(text):
    return text.replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n").replace("\t", "\\t")


# MARK: Keys

def split_key(key, shortcuts):
    """Text segments and placeholders of a catalog key."""
    if shortcuts:
        pieces = SHORTCUT.split(key)
        return pieces[0::2], [("name", p) for p in pieces[1::2]]
    texts, holders, last = [], [], 0
    for m in PRINTF.finditer(key):
        texts.append(key[last:m.start()].replace("%%", "%"))
        holders.append((m.group(1), m.group(2)))
        last = m.end()
    texts.append(key[last:].replace("%%", "%"))
    return texts, holders


def english_value(entry):
    en = entry.get("localizations", {}).get("en", {})
    unit = en.get("stringUnit")
    if unit:
        return unit["value"]
    plural = en.get("variations", {}).get("plural")
    if plural:
        return plural.get("other", {}).get("stringUnit", {}).get("value")
    return None


def shortcut_name(expr):
    """`.applicationName` → applicationName, `\\.$channel` → channel."""
    return re.sub(r"^[\\.$]+", "", expr.strip()).split(".")[-1].lstrip("$")


def main():
    files = {p: p.read_text() for p in SOURCES}
    literals = [lit for p, s in files.items() for lit in scan(p, s)]
    edits = {}            # path -> [(start, end, new literal source)]
    report = {"missing": [], "collisions": [], "busy": [], "review": []}
    new_catalogs = {}

    for catalog in CATALOGS:
        data = json.loads(catalog.read_text())
        old = data["strings"]
        new = {}
        origin = {}
        for key, entry in old.items():
            en = ENGLISH.get(key) or english_value(entry)
            if en is None or not entry.get("localizations") or entry.get("shouldTranslate") is False:
                new[key] = entry          # same in every language ("", "%lld", names)
                continue
            shortcuts = "${" in key
            if key in MERGE:
                en = english_value(old[MERGE[key]])
            texts, holders = split_key(key, shortcuts)
            en_texts, en_holders = split_key(en, shortcuts)
            if len(holders) != len(en_holders):
                report["missing"].append((catalog.name, key, "placeholder count differs from English"))
                continue
            # Order of the German arguments in the English text.
            if shortcuts:
                order = [ [h for _, h in holders].index(h) for _, h in en_holders ]
            elif all(h[0] for h in en_holders):
                order = [int(h[0]) - 1 for h in en_holders]
            else:
                order = list(range(len(holders)))
            matches = [lit for lit in literals if len(lit.texts) == len(texts) and lit.texts == texts]
            if not matches and holders:
                # A format string without interpolation, e.g. String(format: String(localized: "%.0f ms")).
                exact = [lit for lit in literals if lit.parts == [key]]
                if exact:
                    for lit in exact:
                        edits.setdefault(lit.path, []).append((lit.start, lit.end, '"' + escape(en) + '"'))
                        note_suspicious(report, files, lit, key, en)
                    item = {k: v for k, v in entry.items() if k != "localizations"}
                    de_unit = entry.get("localizations", {}).get("de", {}).get("stringUnit", {}).get("value", key)
                    item["localizations"] = {"de": {"stringUnit": {"state": "translated", "value": de_unit}}}
                    add(report, new, origin, catalog, en, key, item)
                    continue
            if shortcuts:
                matches = [lit for lit in matches if [shortcut_name(e) for e in lit.exprs] == [h for _, h in holders]]
            if not matches:
                report["missing"].append((catalog.name, key, "no literal in the code"))
                continue
            if len(matches) > 3:
                report["busy"].append((catalog.name, key, len(matches)))
            for lit in matches:
                note_suspicious(report, files, lit, key, en)
                exprs = lit.exprs
                parts = []
                for k, text in enumerate(en_texts):
                    parts.append(escape(text))
                    if k < len(order):
                        parts.append("\\(" + exprs[order[k]] + ")")
                edits.setdefault(lit.path, []).append((lit.start, lit.end, '"' + "".join(parts) + '"'))
            # The compiler's key for the new literal: English text, placeholders in code order with
            # the German key's types.
            if shortcuts:
                new_key = en
            else:
                new_key = "".join(
                    en_texts[k].replace("%", "%%") + ("%" + holders[order[k]][1] if k < len(order) else "")
                    for k in range(len(en_texts))) if holders else en
            # German: the old text, its placeholders renumbered to the new argument order.
            de_unit = entry.get("localizations", {}).get("de", {}).get("stringUnit", {}).get("value", key)
            de_value = renumber(de_unit, order, shortcuts) if holders and order != list(range(len(order))) else de_unit
            item = {k: v for k, v in entry.items() if k != "localizations"}
            localizations = {}
            de_entry = entry["localizations"].get("de")
            if de_entry and "variations" in de_entry:
                localizations["de"] = de_entry
            else:
                localizations["de"] = {"stringUnit": {"state": "translated", "value": de_value}}
            en_entry = entry["localizations"].get("en", {})
            if "variations" in en_entry:
                localizations["en"] = en_entry
            item["localizations"] = localizations
            if key in MERGE:
                continue          # the other key's entry carries the translation
            add(report, new, origin, catalog, new_key, key, item)
        data["sourceLanguage"] = "en"
        data["strings"] = dict(sorted(new.items()))
        new_catalogs[catalog] = data

    for kind, rows in report.items():
        print(f"== {kind}: {len(rows)}")
        for row in rows:
            print("  ", " | ".join(str(x) for x in row))
    print(f"== literals to rewrite: {sum(len(v) for v in edits.values())} in {len(edits)} files")
    if not WRITE:
        return
    for path, items in edits.items():
        src = files[path]
        for start, end, text in sorted(set(items), reverse=True):
            src = src[:start] + text + src[end:]
        path.write_text(src)
    for catalog, data in new_catalogs.items():
        catalog.write_text(json.dumps(data, indent=2, ensure_ascii=False) + "\n")


def add(report, new, origin, catalog, new_key, key, item):
    if new_key in new and new_key not in origin:
        report["collisions"].append((catalog.name, new_key, "<unchanged key>", key))
    elif new_key in origin and origin[new_key] != key:
        report["collisions"].append((catalog.name, new_key, origin[new_key], key))
    origin[new_key] = key
    new[new_key] = item


def note_suspicious(report, files, lit, key, en):
    """A rewritten literal on a line that does not look like UI code."""
    if key == en:
        return
    src = files[lit.path]
    line_start = src.rfind("\n", 0, lit.start) + 1
    line_end = src.find("\n", lit.end)
    line = src[line_start:line_end].strip()
    if not UI_MARKERS.search(line):
        number = src.count("\n", 0, lit.start) + 1
        report["review"].append((f"{lit.path.relative_to(ROOT)}:{number}", key, line[:110]))


def renumber(text, order, shortcuts):
    """German placeholders, numbered by their argument's position in the new code order."""
    if shortcuts:
        return text
    position = {old: new for new, old in enumerate(order)}
    count = iter(range(len(order)))

    def sub(m):
        index = int(m.group(1)) - 1 if m.group(1) else next(count)
        return f"%{position[index] + 1}${m.group(2)}"
    return PRINTF.sub(sub, text)


if __name__ == "__main__":
    main()
