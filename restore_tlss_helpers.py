#!/usr/bin/env python3
"""Restore the 8 test helpers (tlsPeerRead, makeCertPair, serverTmpSetup,
AcceptProbe, copyBufferJson, acceptProbeRun, runSClient, startProbe) from the
backup into sa_tls_server_test.zig, and remove the circular imports."""
import re

bak = open("/tmp/sa_tls_server.zig.bak").read().split("\n")
# Original line ranges (1-based) from the move_prefixes output:
ranges = [
    ("tlsPeerRead", 1194, 1208),
    ("makeCertPair", 1262, 1283),
    ("serverTmpSetup", 1285, 1292),
    ("AcceptProbe", 1294, 1310),
    ("copyBufferJson", 1312, 1321),
    ("acceptProbeRun", 1323, 1339),
    ("runSClient", 1343, 1367),
    ("startProbe", 1369, 1374),
]
blocks = []
for name, s, e in ranges:
    block = bak[s - 1:e]
    blocks.append("\n".join(block))
    print(f"{name}: {s}..{e} ({len(block)} lines)")

test_path = "src/runtime/sa_tls_server_test.zig"
lines = open(test_path).read().split("\n")
# Remove the circular const imports for the 8 helpers.
names = {n for n, _, _ in ranges}
new_lines = []
for ln in lines:
    m = re.match(r'^const (\w+) = @import\("sa_tls_server\.zig"\)\.\w+;$', ln)
    if m and m.group(1) in names:
        continue
    new_lines.append(ln)
# Make the restored decls pub (they are referenced via pub aliases in sa_tls_server.zig).
pub_blocks = []
for b in blocks:
    b2 = re.sub(r'^(const|fn|var) ', r'pub \1 ', b, count=1, flags=re.M)
    pub_blocks.append(b2)
text = "\n".join(new_lines)
if not text.endswith("\n"):
    text += "\n"
text += "\n" + "\n\n".join(pub_blocks) + "\n"
open(test_path, "w").write(text)
print("restored; test file now", len(text.split("\n")), "lines")
