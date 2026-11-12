#!/usr/bin/env python3
"""Extract L10n.t call sites and L10n.swift locale dictionaries.

The call-site scanner is a small Swift lexical scanner (comments, strings,
escapes, interpolation). It is intentionally conservative: anything that is
not a literal first argument is reported as UNRESOLVED.
"""
from __future__ import annotations
import json, re, sys
from pathlib import Path

LOCALES = ["zh-Hans", "zh-Hant", "en", "ja", "ko"]
ROOT = Path(__file__).resolve().parents[1]
SRC = ROOT / "Sources/DeviceCapturePrototype"

def strip_and_scan_calls(path: Path):
    text = path.read_text(encoding="utf-8")
    calls, unresolved = [], []
    i, line, col, n = 0, 1, 1, len(text)
    def advance(a, b):
        nonlocal line, col
        for ch in text[a:b]:
            if ch == "\n": line += 1; col = 1
            else: col += 1
    while i < n:
        c = text[i]
        if text.startswith("//", i):
            j = text.find("\n", i); j = n if j < 0 else j; advance(i,j); i=j; continue
        if text.startswith("/*", i):
            j = text.find("*/", i+2); j = n if j < 0 else j+2; advance(i,j); i=j; continue
        if c == '"':
            start_line, start_col = line, col
            j = i+1; has_interp = False
            while j < n:
                if text[j] == "\\":
                    if text.startswith("\\(", j): has_interp = True
                    j += 2; continue
                if text[j] == '"': break
                j += 1
            raw = text[i:j+1]
            # detect L10n.t("...") immediately before this string
            prefix_start = max(0, i-64)
            prefix = text[prefix_start:i]
            m = re.search(r'L10n\.t\(\s*$', prefix)
            if m:
                call_pos = prefix_start + m.start()
                rel = str(path.relative_to(ROOT)) if path.is_relative_to(ROOT) else path.name
                if has_interp:
                    unresolved.append({"file": rel, "line": start_line, "column": start_col, "expression": raw, "reason": "interpolated string"})
                else:
                    # decode the common Swift escapes needed for reporting keys
                    key = raw[1:-1].replace('\\"','"').replace('\\n','\n').replace('\\\\','\\')
                    calls.append({"key": key, "file": rel, "line": start_line, "column": start_col})
            advance(i, j+1); i = j+1; continue
        i += 1; col += 1
    return calls, unresolved

def parse_locales():
    text = (SRC / "L10n.swift").read_text(encoding="utf-8")
    current = None
    entries = {loc: {} for loc in LOCALES}
    # Locale dictionary heads: "en": [ ... ], etc.
    for line in text.splitlines():
        m = re.match(r'\s*"(zh-Hans|zh-Hant|en|ja|ko)"\s*:\s*\[(.*)$', line)
        if m:
            current = m.group(1)
            line = m.group(2)
        if not current:
            continue
        for k, v in re.findall(r'"((?:[^"\\]|\\.)*)"\s*:\s*"((?:[^"\\]|\\.)*)"', line):
            k = k.replace('\\"','"').replace('\\n','\n').replace('\\\\','\\')
            v = v.replace('\\"','"').replace('\\n','\n').replace('\\\\','\\')
            entries[current].setdefault(k, []).append(v)
    return entries

def placeholders(s):
    return sorted(re.findall(r'\\\(([^)]*)\)', s))

def main():
    all_calls, unresolved = [], []
    for path in sorted(SRC.glob("*.swift")):
        c, u = strip_and_scan_calls(path); all_calls += c; unresolved += u
    locales = parse_locales()
    by_key = {}
    for c in all_calls:
        by_key.setdefault(c["key"], []).append(c)
    rows = []
    for key, uses in sorted(by_key.items()):
        status = {}
        missing = []
        for loc in LOCALES:
            if loc == "zh-Hans":
                status[loc] = True
            else:
                vals = locales[loc].get(key)
                status[loc] = bool(vals)
                if not vals: missing.append(loc)
        values = [locales[loc].get(key, [""])[0] for loc in LOCALES if loc != "zh-Hans"]
        ph = placeholders(key)
        ph_bad = [loc for loc, v in zip([l for l in LOCALES if l != "zh-Hans"], values) if placeholders(v) != ph]
        rows.append({"key": key, "uses": uses, "coverage": status, "missing": missing,
                     "placeholders": ph, "placeholder_mismatch": ph_bad,
                     "chinese_fallback": bool(re.search(r'[\u4e00-\u9fff]', key)) and any(
                         v == key for loc, v in zip([l for l in LOCALES if l != "zh-Hans"], values)
                         if loc in ("en", "ko"))})
    out = {"locales": LOCALES, "unique_keys": len(rows), "call_sites": len(all_calls),
           "unresolved": unresolved, "rows": rows,
           "stats": {loc: sum(1 for r in rows if r["coverage"][loc]) for loc in LOCALES},
           "missing_keys": sum(1 for r in rows if r["missing"]),
           "chinese_fallback_keys": sum(1 for r in rows if r["chinese_fallback"]),
           "placeholder_mismatch_keys": sum(1 for r in rows if r["placeholder_mismatch"])}
    outpath = ROOT / "_t532/l10n-extract-1770.json"
    outpath.parent.mkdir(exist_ok=True)
    outpath.write_text(json.dumps(out, ensure_ascii=False, indent=2), encoding="utf-8")
    print(f"unique_keys={out['unique_keys']} calls={out['call_sites']} unresolved={len(unresolved)}")
    for loc in LOCALES: print(f"{loc}={out['stats'][loc]}")
    print(f"missing_keys={out['missing_keys']} chinese_fallback_keys={out['chinese_fallback_keys']} placeholder_mismatch_keys={out['placeholder_mismatch_keys']}")
    print(f"report={outpath}")
    return 0

if __name__ == "__main__":
    sys.exit(main())
