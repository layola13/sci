#!/usr/bin/env python3
"""fix_cli_compile24.py — fourteenth wave: move the source-tree-hash subsystem
out of cli.zig into its own module + make CompileMemoryMetrics methods pub.

1) New module src/cli/source_tree.zig gets the whole memoized source-tree
   subsystem (std-tree digest + resolved-tree hash cache): types, globals,
   and all fns. cli.zig keeps an alias per moved decl; cache.zig imports
   hashResolvedSourceTree + stdTreeDigest from source_tree.zig instead.
2) CompileMemoryMetrics methods in types.zig were private; external callers
   (compile.zig recordStart, writeVerifierMemoryStage recordVerifierStage,
   recordAfterLink/AfterEmit...) need them pub -> make all `fn` inside the
   struct `pub fn`.
Run from /content/sa_all/sci2.
"""
import re
from fix_cli_compile11 import move_fn, add_import, find_fn_end
from fix_cli_compile19 import move_type

def move_var(src_path, name, dst_path, dst_import_from_src):
    lines = open(src_path).read().split("\n")
    idx = None
    for i, l in enumerate(lines):
        if re.match(r"^var " + re.escape(name) + r"\b", l):
            idx = i
            break
    assert idx is not None, f"var {name} not found in {src_path}"
    line = lines[idx]
    assert line.rstrip().endswith(";"), f"multi-line var not supported: {line}"
    pub_line = "pub " + line
    dst = open(dst_path).read()
    if not dst.endswith("\n"):
        dst += "\n"
    dst += "\n" + pub_line + "\n"
    open(dst_path, "w").write(dst)
    alias = f"const {name} = @import(\"{dst_import_from_src}\").{name};"
    lines[idx] = alias
    open(src_path, "w").write("\n".join(lines))
    print(f"moved var {name}: {src_path} line {idx+1} -> {dst_path}")

def pub_struct_methods(path, struct_name):
    lines = open(path).read().split("\n")
    start = None
    for i, l in enumerate(lines):
        if re.match(r"^pub const " + re.escape(struct_name) + r" = (struct|enum) \{", l):
            start = i
            break
    assert start is not None, struct_name
    end = find_fn_end(lines, start)
    changed = 0
    for i in range(start, end + 1):
        if re.match(r"^    fn ", lines[i]):
            lines[i] = "    pub " + lines[i]
            changed += 1
    open(path, "w").write("\n".join(lines))
    print(f"made {changed} methods pub in {struct_name} ({path} lines {start+1}..{end+1})")

def main():
    cli = "src/cli.zig"
    dst = "src/cli/source_tree.zig"
    # create the new module with its base imports
    header = (
        "const std = @import(\"std\");\n"
        "const builtin = @import(\"builtin\");\n"
        "const sio = @import(\"sio\");\n"
        "const pkg_resolver = @import(\"../pkg/resolver.zig\");\n"
        "const cacheBytes = @import(\"cache.zig\").cacheBytes;\n"
        "const cacheCompilerVersion = @import(\"cache.zig\").cacheCompilerVersion;\n"
        "const cacheKeyNormalizedPath = @import(\"cache.zig\").cacheKeyNormalizedPath;\n"
        "const projectFileMaybeHash = @import(\"cache.zig\").projectFileMaybeHash;\n"
    )
    open(dst, "w").write(header)
    print(f"created {dst}")
    # types + globals first
    move_type(cli, "StdTreeDigestEntry", dst, "cli/source_tree.zig")
    move_var(cli, "std_tree_digest_mutex", dst, "cli/source_tree.zig")
    move_var(cli, "std_tree_digest_cache", dst, "cli/source_tree.zig")
    move_type(cli, "SourceTreeFileStat", dst, "cli/source_tree.zig")
    move_type(cli, "SourceTreeHashCacheEntry", dst, "cli/source_tree.zig")
    move_var(cli, "source_tree_hash_cache_mutex", dst, "cli/source_tree.zig")
    move_var(cli, "source_tree_hash_cache", dst, "cli/source_tree.zig")
    move_var(cli, "source_tree_hash_cache_tick", dst, "cli/source_tree.zig")
    move_var(cli, "test_source_tree_hash_cache_max_entries", dst, "cli/source_tree.zig")
    # fns (order irrelevant; each move re-reads cli.zig)
    for name in ("cacheKeyTreePath", "stdTreeDigestCacheMap", "lockStdTreeDigestCache",
                 "freeStdTreeDigestEntry", "stdTreeScratchDir", "stdTreeArchiveName",
                 "hashFileContentsInto", "collectStdTreeFiles", "stdTreeStatLessThan",
                 "stdTreeDigest", "stdTreeFileListsEqual", "sourceTreeHashCacheMap",
                 "freeSourceTreeHashCacheEntry", "sourceTreeHashCacheMaxEntries",
                 "nextSourceTreeHashCacheTickLocked", "buildSourceTreeHashCacheKey",
                 "appendCacheKeyBytes", "sourceTreeHashCacheHit",
                 "storeSourceTreeHashCacheEntry", "evictSourceTreeHashCacheIfNeeded",
                 "addSourceTreeDigestToHasher", "hashResolvedSourceTreeUncached",
                 "hashResolvedSourceTree"):
        move_fn(cli, name, dst, "cli/source_tree.zig")
    # cache.zig: re-point stdTreeDigest + add hashResolvedSourceTree
    text = open("src/cli/cache.zig").read()
    text = text.replace(
        'const stdTreeDigest = @import("../cli.zig").stdTreeDigest;',
        'const stdTreeDigest = @import("source_tree.zig").stdTreeDigest;')
    open("src/cli/cache.zig", "w").write(text)
    print("re-pointed stdTreeDigest import in cache.zig")
    add_import("src/cli/cache.zig", 'const hashResolvedSourceTree = @import("source_tree.zig").hashResolvedSourceTree;')
    # CompileMemoryMetrics methods -> pub
    pub_struct_methods("src/cli/types.zig", "CompileMemoryMetrics")
    print("done")

if __name__ == "__main__":
    main()
