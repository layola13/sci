#!/usr/bin/env python3
"""fix_cli_compile24b.py — resume of fix_cli_compile24.py (died at stdTreeDigest
because extract_fn only matched `^fn `, not `^pub fn `; regex now patched).

Remaining moves + tail steps of fix24.
Run from /content/sa_all/sci2.
"""
from fix_cli_compile11 import move_fn, add_import
from fix_cli_compile24 import pub_struct_methods

def main():
    cli = "src/cli.zig"
    dst = "src/cli/source_tree.zig"
    for name in ("stdTreeDigest", "stdTreeFileListsEqual", "sourceTreeHashCacheMap",
                 "freeSourceTreeHashCacheEntry", "sourceTreeHashCacheMaxEntries",
                 "nextSourceTreeHashCacheTickLocked", "buildSourceTreeHashCacheKey",
                 "appendCacheKeyBytes", "sourceTreeHashCacheHit",
                 "storeSourceTreeHashCacheEntry", "evictSourceTreeHashCacheIfNeeded",
                 "addSourceTreeDigestToHasher", "hashResolvedSourceTreeUncached",
                 "hashResolvedSourceTree"):
        move_fn(cli, name, dst, "cli/source_tree.zig")
    text = open("src/cli/cache.zig").read()
    text = text.replace(
        'const stdTreeDigest = @import("../cli.zig").stdTreeDigest;',
        'const stdTreeDigest = @import("source_tree.zig").stdTreeDigest;')
    open("src/cli/cache.zig", "w").write(text)
    print("re-pointed stdTreeDigest import in cache.zig")
    add_import("src/cli/cache.zig", 'const hashResolvedSourceTree = @import("source_tree.zig").hashResolvedSourceTree;')
    pub_struct_methods("src/cli/types.zig", "CompileMemoryMetrics")
    print("done")

if __name__ == "__main__":
    main()
