#!/usr/bin/env python3
"""Restore the 12 test helpers for sa_tls_shaped from the backup into
sa_tls_shaped_test.zig, and remove the circular imports."""
import re

bak = open("/tmp/sa_tls_shaped.zig.bak").read().split("\n")
ranges = [
    ("sslAvailable", 1411, 1415),
    ("makeCert", 1446, 1465),
    ("freePort", 1467, 1475),
    ("spawnServer", 1477, 1490),
    ("connectRetry", 1492, 1503),
    ("negotiatedJson", 1505, 1514),
    ("testDirSetup", 1516, 1524),
    ("profileJson", 1666, 1671),
    ("connectRetryProfile", 1673, 1683),
    ("shapedEcho", 1685, 1700),
    ("shapedServerRoundTrip", 1704, 1723),
    ("opensslX509Field", 1850, 1868),
]
blocks = []
for name, s, e in ranges:
    block = bak[s - 1:e]
    blocks.append("\n".join(block))
    print(f"{name}: {s}..{e} ({len(block)} lines)")

test_path = "src/runtime/sa_tls_shaped_test.zig"
lines = open(test_path).read().split("\n")
names = {n for n, _, _ in ranges}
new_lines = []
for ln in lines:
    m = re.match(r'^const (\w+) = @import\("sa_tls_shaped\.zig"\)\.\w+;$', ln)
    if m and m.group(1) in names:
        continue
    new_lines.append(ln)
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
