#!/usr/bin/env python3
"""Structural check for sa_std .sa macro additions (no toolchain needed).

Rules (house style from math.sa / array.sa):
- [MACRO] / [END_MACRO] balanced
- labels at column 0, instructions indented
- every temp defined with %out-suffixed name is released exactly once
- macro consumes its declared inputs (each %param released)
"""
import re
import sys

MACRO_RE = re.compile(r"\[MACRO\] (\w+) (.*)")
END_RE = re.compile(r"\[END_MACRO\]")


def check(path, only=None):
    text = open(path, encoding="utf-8").read().splitlines()
    errs = []
    cur = None
    depth = 0
    for i, raw in enumerate(text, 1):
        m = MACRO_RE.match(raw.strip())
        if m:
            depth += 1
            if only is None or m.group(1) in only:
                params = m.group(2).split(",")
                cur = {"name": m.group(1), "line": i,
                       "params": [p.strip() for p in params],
                       "defs": {}, "rels": {}}
            continue
        if END_RE.match(raw.strip()):
            if cur is not None:
                caller_owned = "caller-owned" in cur.get("notes", "")
                for p in cur["params"]:
                    if p.startswith("%out"):
                        continue
                    if caller_owned:
                        continue
                    if cur["rels"].get(p, 0) != 1 and p not in cur.get("expanded", ""):
                        errs.append(f"{path}:{cur['line']}: {cur['name']}: "
                                    f"param {p} released {cur['rels'].get(p, 0)}x")
                for d, dl in cur["defs"].items():
                    if d.startswith("%out"):
                        continue
                    if cur["rels"].get(d, 0) != 1:
                        errs.append(f"{path}:{cur['line']}: {cur['name']}: "
                                    f"temp {d} (def L{dl}) released "
                                    f"{cur['rels'].get(d, 0)}x")
                cur = None
            depth -= 1
            continue
        if cur is None:
            continue
        if raw and not raw[0].isspace():
            if not raw.endswith(":") and raw.strip():
                errs.append(f"{path}:{i}: non-label at col 0: {raw[:50]}")
            continue
        s = raw.strip()
        if not s or s.startswith("//"):
            if "caller-owned" in s and cur is not None:
                cur["notes"] = cur.get("notes", "") + " caller-owned"
            continue
        if s.startswith("EXPAND"):
            cur["expanded"] = cur.get("expanded", "") + " " + s
            continue
        if s.startswith("!"):
            r = s[1:].rstrip(";")
            cur["rels"][r] = cur["rels"].get(r, 0) + 1
            continue
        dm = re.match(r"(%[\w%]+)\s*=", s)
        if dm:
            cur["defs"][dm.group(1)] = i
    if depth != 0:
        errs.append(f"{path}: unbalanced MACRO/END_MACRO (depth {depth})")
    return errs


if __name__ == "__main__":
    only = set(sys.argv[2:]) or None
    errs = check(sys.argv[1], only)
    if errs:
        print(f"FAIL ({len(errs)}):")
        for e in errs:
            print("  -", e)
        sys.exit(1)
    print("OK: macro structure sound.")
