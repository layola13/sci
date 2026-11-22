#!/usr/bin/env python3
"""Static @import resolution check for SA std Phase 1 domain C (collections/string/text/encoding).
Resolves every @import in sa_std/ (relative to the importing file, or sa_std/ prefix
against the std root), follows 1-line @import shim chains, and reports dangling refs.
Also checks sibling (.sai/.sal) parity for renamed files and repo-wide refs to deleted paths.
Usage: python3 check_imports.py (run from the repo root; no build, no tests).
"""
import os, re, subprocess, sys

ROOT = "/content/kit-work/sci2-agentS1C"
STD = os.path.join(ROOT, "sa_std")
IMPORT_RE = re.compile(r'@import\s+"([^"]+)"')

def git_out(args):
    return subprocess.check_output(["git"] + args, cwd=ROOT, text=True)

HEAD = set(git_out(["ls-files"]).split())

def resolve(importer_abs, imp):
    if imp.startswith("sa_std/"):
        return os.path.normpath(os.path.join(STD, imp[len("sa_std/"):])), "std"
    if imp.startswith("sa:") or imp.startswith("pkg:"):
        return None, "pkg"
    return os.path.normpath(os.path.join(os.path.dirname(importer_abs), imp)), "rel"

def shim_target(path):
    """If file is a 1-line @import shim (ignoring // comments/blank lines), return its target string."""
    try:
        with open(path, encoding="utf-8", errors="replace") as f:
            lines = [l.strip() for l in f.read().splitlines()
                     if l.strip() and not l.strip().startswith("//")]
    except FileNotFoundError:
        return None
    if len(lines) == 1:
        m = IMPORT_RE.match(lines[0])
        if m:
            return m.group(1)
    return None

all_files = []
for dp, dn, fn in os.walk(STD):
    dn.sort()
    for x in sorted(fn):
        all_files.append(os.path.join(dp, x))

dangling, shim_uses, checked, pkg_skipped = [], {}, 0, 0
domain_checked = 0
DOMAIN_DIRS = ("collections", "string", "text", "encoding", "alloc")
for p in all_files:
    if not p.endswith((".sa", ".sal", ".sai", ".sla")):
        continue
    rel = os.path.relpath(p, ROOT)
    in_domain = os.path.relpath(p, STD).split(os.sep)[0] in DOMAIN_DIRS or rel in (
        "sa_std/prelude.sa", "sa_std/prelude.sal")
    with open(p, encoding="utf-8", errors="replace") as f:
        text = f.read()
    for m in IMPORT_RE.finditer(text):
        imp = m.group(1)
        checked += 1
        if in_domain:
            domain_checked += 1
        tgt, kind = resolve(p, imp)
        if tgt is None:
            pkg_skipped += 1
            continue
        if not os.path.exists(tgt):
            dangling.append((rel, imp, "MISSING (in HEAD: %s)" % (os.path.relpath(tgt, ROOT) in HEAD)))
            continue
        chain = [os.path.relpath(tgt, ROOT)]
        cur, depth = tgt, 0
        while True:
            s = shim_target(cur)
            if s is None:
                break
            t2, _ = resolve(cur, s)
            chain.append(os.path.relpath(t2, ROOT))
            if not os.path.exists(t2):
                dangling.append((rel, imp, "SHIM TARGET MISSING: " + " -> ".join(chain)))
                break
            cur, depth = t2, depth + 1
            if depth > 5:
                dangling.append((rel, imp, "SHIM CHAIN TOO DEEP: " + " -> ".join(chain)))
                break
        if len(chain) > 1:
            shim_uses.setdefault(rel, []).append(" -> ".join(chain))

print("files scanned under sa_std: %d" % len(all_files))
print("@import occurrences checked (sa_std): %d (domain scope incl. root prelude: %d; pkg:/sa: skipped: %d)" % (checked, domain_checked, pkg_skipped))
print("imports resolved through a shim: %d" % sum(len(v) for v in shim_uses.values()))
print("DANGLING: %d" % len(dangling))
for d in dangling:
    print("  DANGLING", d)

renames = []
for line in git_out(["diff", "--cached", "--name-status", "--find-renames", "--diff-filter=R"]).splitlines():
    parts = line.split("\t")
    if len(parts) == 3:
        renames.append((parts[1], parts[2]))
print("\nstaged renames: %d" % len(renames))
sib_problems = []
for old, new in renames:
    if not new.startswith("sa_std/"):
        continue
    old_dir = os.path.dirname(os.path.join(ROOT, old))
    new_path = os.path.join(ROOT, new)
    if not new.endswith(".sa"):
        continue
    stem = os.path.basename(new)[:-3]
    for ext in (".sai", ".sal"):
        old_sib_rel = os.path.relpath(os.path.join(old_dir, stem + ext), ROOT)
        new_sib = os.path.join(os.path.dirname(new_path), stem + ext)
        had = old_sib_rel in HEAD
        has = os.path.exists(new_sib)
        if had and not has:
            sib_problems.append((new, ext, "sibling existed at old location, missing at new location"))
print("sibling-parity problems: %d" % len(sib_problems))
for s in sib_problems:
    print("  SIBLING", s)

deleted = ["collections/hashmap.sa", "collections/hashset.sa", "collections/btree_map.sa",
           "collections/btree_set.sa", "collections/binary_heap.sa", "collections/vec_deque.sa"]
print("\nrefs to deleted shim paths (must be 0):")
for d in deleted:
    out = subprocess.run(["grep", "-rn", "--include=*.sa", "--include=*.sal", "--include=*.sla",
                          "--include=*.sai", "--include=*.zig", "--include=*.md",
                          '@import "%s"' % d, ROOT],
                         capture_output=True, text=True)
    hits = [l for l in out.stdout.splitlines() if ".git/" not in l and ".zig-cache/" not in l]
    print("  %s: %d" % (d, len(hits)))
    for h in hits:
        print("    ", h)

print("\nold-path shim audit:")
for old, new in renames:
    if os.path.exists(os.path.join(ROOT, old)):
        st = shim_target(os.path.join(ROOT, old))
        print("  %s: still exists; shim -> %r" % (old, st))
    else:
        print("  %s: gone (deleted without shim)" % old)

print("\nRESULT:", "FAIL" if (dangling or sib_problems) else "PASS")
sys.exit(1 if (dangling or sib_problems) else 0)
