#!/usr/bin/env python3
"""Checks that every UI string in App/ has an English translation in
App/Resources/Localizable.xcstrings (ROADMAP D9). Finds string literals in
LocalizedStringKey and String(localized:) positions, like Xcode's extraction, and
turns interpolations into format specifiers (%lld for counts, %@ otherwise).

Usage: scripts/check-localization.py            (from the CopyPal folder)
       scripts/check-localization.py --list     print the extracted keys
       scripts/check-localization.py --fix      sort and format the catalog like Xcode
"""

import re, sys, json, pathlib

root = pathlib.Path(__file__).resolve().parent.parent / "App"
files = sorted(root.rglob("*.swift"))

# Calls whose first (unlabeled) string literal argument is a LocalizedStringKey.
positional = r"(?:Text|Button|Toggle|Picker|Label|TextField|Menu|SectionBlock|StatusTag|switchLabel|LocalizedStringKey|\.alert|\.help|explanationRow\(\"[^\"]*\",|shortcutCaption)"
labeled = r"(?:title|subtitle|detail|label|text|help)"

def literal_at(src, i):
    """Parse a Swift string literal starting at src[i] == '"'. Returns (content_raw, end)."""
    assert src[i] == '"'
    j = i + 1
    out = ""
    while j < len(src):
        c = src[j]
        if c == "\\":
            if src[j+1] == "(":
                depth = 1
                k = j + 2
                while depth:
                    if src[k] == "(": depth += 1
                    elif src[k] == ")": depth -= 1
                    k += 1
                out += "\\(" + src[j+2:k-1] + ")"
                j = k
                continue
            out += src[j:j+2]
            j += 2
            continue
        if c == '"':
            return out, j + 1
        out += c
        j += 1
    raise ValueError("unterminated")

int_names = re.compile(r"(count|index|number|Count|days|seconds|offsetDays|rawValue \+ 1|value|width|height|changeCount)$")

INT_HINTS = re.compile(r"(\.count|Count|count|days|Days|seconds|\.width|\.height|rawValue|rawValue \+ 1|offsetDays|allCases\.count|^value)$")

def to_key(raw):
    out = ""
    i = 0
    while i < len(raw):
        if raw.startswith("\\(", i):
            depth = 1
            k = i + 2
            while depth:
                if raw[k] == "(": depth += 1
                elif raw[k] == ")": depth -= 1
                k += 1
            expr = raw[i+2:k-1].strip()
            out += "%lld" if INT_HINTS.search(expr) else "%@"
            i = k
            continue
        if raw.startswith('\\"', i):
            out += '"'; i += 2; continue
        if raw.startswith("\\n", i):
            out += "\n"; i += 2; continue
        out += raw[i]
        i += 1
    return out

keys = {}
for f in files:
    src = f.read_text()
    if "#if DEBUG" in src and f.name in ("LabView.swift", "LabModel.swift", "LabWindowController.swift", "SelfTestRunner.swift"):
        continue
    for m in re.finditer(r'String\(localized:\s*"', src):
        raw, _ = literal_at(src, m.end() - 1)
        keys.setdefault(to_key(raw), set()).add(f.name)
    for m in re.finditer(positional + r'\(\s*"', src):
        raw, _ = literal_at(src, m.end() - 1)
        keys.setdefault(to_key(raw), set()).add(f.name)
    for m in re.finditer(r'\b' + labeled + r':\s*"', src):
        raw, _ = literal_at(src, m.end() - 1)
        keys.setdefault(to_key(raw), set()).add(f.name)
    # Literals returned from LocalizedStringKey-typed computed properties / switch cases.
    for block in re.finditer(r'(?:var|func) \w+[^{]*-> LocalizedStringKey \{|: LocalizedStringKey \{', src):
        start = block.end()
        depth = 1
        k = start
        while depth:
            if src[k] == "{": depth += 1
            elif src[k] == "}": depth -= 1
            k += 1
        body = src[start:k]
        for lm in re.finditer(r'"', body):
            pass
        idx = 0
        while True:
            q = body.find('"', idx)
            if q < 0: break
            raw, end = literal_at(body, q)
            keys.setdefault(to_key(raw), set()).add(f.name)
            idx = end
    # Ternaries of LocalizedStringKey("…")
for drop in ["", "doc.on.doc", "trash"]:
    keys.pop(drop, None)

if "--list" in sys.argv:
    for k in sorted(keys):
        print(json.dumps(k, ensure_ascii=False))
    sys.exit(0)

catalog_path = root / "Resources" / "Localizable.xcstrings"
catalog_text = catalog_path.read_text()
catalog_data = json.loads(catalog_text)
catalog = catalog_data["strings"]
missing = sorted(k for k in keys if not catalog.get(k, {}).get("localizations", {}).get("en"))
unused = sorted(k for k in catalog if k not in keys)
for key in missing:
    print(f"Ohne englische Übersetzung: {json.dumps(key, ensure_ascii=False)} ({', '.join(sorted(keys[key]))})")
for key in unused:
    print(f"Hinweis – nicht mehr verwendet: {json.dumps(key, ensure_ascii=False)}")
if missing:
    print(f"::error::{len(missing)} Text(e) ohne englische Übersetzung in App/Resources/Localizable.xcstrings")
    sys.exit(1)

# The file is kept exactly as Xcode's xcstringstool writes it: keys in code point
# order, 2-space indent, " : ", no newline at the end. Xcode itself does not rewrite
# it (SWIFT_EMIT_LOC_STRINGS = NO, see Config/Base.xcconfig), so a pull never
# collides with a local build.
canonical = dict(catalog_data, strings=dict(sorted(catalog.items())))
expected = json.dumps(canonical, indent=2, separators=(",", " : "), ensure_ascii=False)
if catalog_text != expected:
    if "--fix" in sys.argv:
        catalog_path.write_text(expected)
        print("Localizable.xcstrings neu geschrieben (Reihenfolge und Format wie Xcode).")
    else:
        print("::error::Localizable.xcstrings ist nicht sortiert oder anders formatiert – scripts/check-localization.py --fix")
        sys.exit(1)
print(f"Alle {len(keys)} Texte übersetzt.")
