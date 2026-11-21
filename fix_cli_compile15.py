#!/usr/bin/env python3
"""fix_cli_compile15.py — fifth wave of the cli-split fix (8 errors).

Moves (cli.zig -> submodule, pub fn, alias left in cli.zig):
  buildIncrementalObject -> cli/build_exe.zig (only caller; ~119 lines,
    build_exe.zig will temporarily exceed 700 — split it in the endgame)
  freeFlatLocEntry, cacheBytes -> cli/cache.zig
  projectCacheManifestValid + its helper cluster
    (projectCacheManifestPath, jsonGetObject, jsonStringEquals, jsonIntEquals,
     projectCacheArtifactMatchesManifest, readTextFileAlloc) -> cli/cache.zig
  dirExistsAbsolute, defaultStableImportRoots -> cli/compile.zig
Pure import additions (missed in wave 4):
  build_exe.zig: cguSeqShardCount, recordMetricMemoryAfterLink (compile.zig)
  build_lib.zig: emitOptLevel (build_exe.zig)
Run from /content/sa_all/sci2.
"""
from fix_cli_compile11 import move_fn, add_import

def main():
    cli = "src/cli.zig"
    move_fn(cli, "buildIncrementalObject", "src/cli/build_exe.zig", "cli/build_exe.zig")
    move_fn(cli, "freeFlatLocEntry", "src/cli/cache.zig", "cli/cache.zig")
    move_fn(cli, "cacheBytes", "src/cli/cache.zig", "cli/cache.zig")
    for name in ("projectCacheManifestValid", "projectCacheManifestPath",
                 "jsonGetObject", "jsonStringEquals", "jsonIntEquals",
                 "projectCacheArtifactMatchesManifest", "readTextFileAlloc"):
        move_fn(cli, name, "src/cli/cache.zig", "cli/cache.zig")
    move_fn(cli, "dirExistsAbsolute", "src/cli/compile.zig", "cli/compile.zig")
    move_fn(cli, "defaultStableImportRoots", "src/cli/compile.zig", "cli/compile.zig")
    add_import("src/cli/build_exe.zig", 'const cguSeqShardCount = @import("compile.zig").cguSeqShardCount;')
    add_import("src/cli/build_exe.zig", 'const recordMetricMemoryAfterLink = @import("compile.zig").recordMetricMemoryAfterLink;')
    add_import("src/cli/build_lib.zig", 'const emitOptLevel = @import("build_exe.zig").emitOptLevel;')
    print("done")

if __name__ == "__main__":
    main()
