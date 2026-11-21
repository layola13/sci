import re
lines = open("src/cli.zig").read().split("\n")

def find_fn(name):
    for i, l in enumerate(lines):
        if l.startswith("fn " + name + "(") or l.startswith("pub fn " + name + "("):
            return i
    return None

def find_decl(name):
    for i, l in enumerate(lines):
        if l.startswith("const " + name + " =") or l.startswith("pub const " + name + " ="):
            return i
    return None

def find_end(start_idx):
    for j in range(start_idx + 1, len(lines)):
        l = lines[j]
        if l.startswith("fn ") or l.startswith("pub fn ") or l.startswith("const ") or l.startswith("pub const ") or l.startswith("test "):
            return j
    return len(lines)

def extract_fn(name):
    fi = find_fn(name)
    assert fi is not None, name
    s = fi
    while s > 0 and lines[s-1].startswith("///"):
        s -= 1
    e = find_end(fi)
    last = None
    for j in range(e - 1, fi, -1):
        if lines[j] == "}" or lines[j] == "};":
            last = j
            break
    assert last is not None, name
    block = lines[s:last+1]
    for idx, l in enumerate(block):
        if l.startswith("fn " + name + "("):
            block[idx] = "pub " + l
            break
    return (s, last, block)

def extract_type(name):
    fi = find_decl(name)
    assert fi is not None, name
    s = fi
    while s > 0 and lines[s-1].startswith("///"):
        s -= 1
    e = None
    for j in range(fi, len(lines)):
        if lines[j] == "};" or lines[j] == "}":
            e = j
            break
    assert e is not None, name
    block = lines[s:e+1]
    for idx, l in enumerate(block):
        if l.startswith("const " + name + " =") or l.startswith("pub const " + name + " ="):
            if not l.startswith("pub "):
                block[idx] = "pub " + l
            break
    return (s, e, block)

# --- types: BuildCacheKind, BuildCacheMetrics ---
tblocks = {}
for n in ["BuildCacheKind", "BuildCacheMetrics"]:
    tblocks[n] = extract_type(n)
    print(f"TYPE {n}: lines {tblocks[n][0]+1}..{tblocks[n][1]+1}")
tz = open("src/cli/types.zig").read()
if not tz.endswith("\n"):
    tz += "\n"
for name, (s, e, block) in sorted(tblocks.items(), key=lambda kv: kv[1][0]):
    tz += "\n" + "\n".join(block) + "\n"
tzl = tz.split("\n")
if not any(l.startswith("const sio = ") for l in tzl):
    tzl[0:0] = ['const sio = @import("sio");']
    tz = "\n".join(tzl)
open("src/cli/types.zig", "w").write(tz)
print(f"types.zig now {tz.count(chr(10))} lines")

# --- compile.zig: recordMetricMemoryAfterEmit, pruneSabFlatToSelectedTests, projectSumPath, writeMemoryDelta ---
cblocks = {}
for n in ["recordMetricMemoryAfterEmit", "pruneSabFlatToSelectedTests", "projectSumPath", "writeMemoryDelta"]:
    cblocks[n] = extract_fn(n)
    print(f"COMPILE {n}: lines {cblocks[n][0]+1}..{cblocks[n][1]+1}")
cz = open("src/cli/compile.zig").read()
if not cz.endswith("\n"):
    cz += "\n"
for name, (s, e, block) in sorted(cblocks.items(), key=lambda kv: kv[1][0]):
    cz += "\n" + "\n".join(block) + "\n"
czl = cz.split("\n")
adds = []
for n, imp in [("common_upstream", 'const common_upstream = @import("../common/upstream.zig");'),
               ("manifest", 'const manifest = @import("../pkg/manifest.zig");'),
               ("builtin", 'const builtin = @import("builtin");'),
               ("BuildCacheKind", 'const BuildCacheKind = @import("types.zig").BuildCacheKind;')]:
    if not any(l.startswith(f"const {n} = ") for l in czl):
        adds.append(imp)
for i, l in enumerate(czl):
    if l.startswith("const std = "):
        czl[i+1:i+1] = adds
        break
cz = "\n".join(czl)
open("src/cli/compile.zig", "w").write(cz)
print(f"compile.zig now {cz.count(chr(10))} lines")
assert cz.count("\n") <= 700, "compile.zig too big!"

# --- build_lib.zig: generateLibGlueSa ---
gblock = extract_fn("generateLibGlueSa")
print(f"LIB generateLibGlueSa: lines {gblock[0]+1}..{gblock[1]+1}")
bl = open("src/cli/build_lib.zig").read()
if not bl.endswith("\n"):
    bl += "\n"
bl += "\n" + "\n".join(gblock[2]) + "\n"
open("src/cli/build_lib.zig", "w").write(bl)
print(f"build_lib.zig now {bl.count(chr(10))} lines")

# --- Replace in cli.zig (descending order) ---
all_blocks = {}
for n, v in tblocks.items():
    all_blocks[n] = (v[0], v[1], "types.zig")
for n, v in cblocks.items():
    all_blocks[n] = (v[0], v[1], "compile.zig")
all_blocks["generateLibGlueSa"] = (gblock[0], gblock[1], "build_lib.zig")
removals = sorted(all_blocks.items(), key=lambda kv: -kv[1][0])
for name, (s, e, fname) in removals:
    lines[s:e+1] = [f'const {name} = @import("cli/{fname}").{name};']
    print(f"replaced {name} (lines {s+1}..{e+1}) with import from {fname}")
open("src/cli.zig", "w").write("\n".join(lines))

# --- build_exe.zig: add imports ---
be = open("src/cli/build_exe.zig").read().split("\n")
adds = []
for n, src in [("intermediateArtifactPath", "build_lib.zig"), ("recordMetricMemoryAfterEmit", "compile.zig")]:
    if not any(l.startswith(f"const {n} = ") for l in be):
        adds.append(f'const {n} = @import("{src}").{n};')
for i, l in enumerate(be):
    if l.startswith("const std = "):
        be[i+1:i+1] = adds
        break
open("src/cli/build_exe.zig", "w").write("\n".join(be))
print("added imports to build_exe.zig:", adds)
print("done")
