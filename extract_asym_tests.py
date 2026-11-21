#!/usr/bin/env python3
"""Extract lines 1072..1452 (test section: 5 small tests + fx_ consts + openssl tests)
from sa_crypto_asym.zig into sa_crypto_asym_test.zig by exact line numbers."""
src = "src/runtime/sa_crypto_asym.zig"
dst = "src/runtime/sa_crypto_asym_test.zig"
lines = open(src).read().split("\n")
# lines are 0-indexed; 1072..1451 1-based => indices 1071..1450
start, end = 1071, 1450
assert lines[start].startswith('test "der: ecdsa signature'), f"start mismatch: {lines[start]!r}"
assert lines[end].strip() == "}", f"end mismatch: {lines[end]!r}"
block = lines[start:end + 1]
del lines[start:end + 1]
open(src, "w").write("\n".join(lines))
header = 'const std = @import("std");\n'
open(dst, "w").write(header + "\n".join(block) + "\n")
print(f"moved {len(block)} lines; src now {len(lines)} lines")
