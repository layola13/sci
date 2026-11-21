#!/usr/bin/env python3
"""fix_cli_compile22.py — twelfth wave of the cli-split fix (5 errors).

Moves (cli.zig -> submodule, pub, alias left in cli.zig):
  projectFunctionCacheManifestPath, cacheEntryLastUsedNs -> cli/cache.zig
  MemoryStageReporterContext (struct) -> cli/types.zig
Pure import additions:
  build_exe.zig: projectFunctionCacheManifestPath (cache.zig)
  build_lib.zig: dynlib_compat (../dynlib_compat.zig)
  cache.zig: freeOwnedStringSlice (compile.zig; already pub there)
  compile.zig: MemoryStageReporterContext (types.zig)
Run from /content/sa_all/sci2.
"""
from fix_cli_compile11 import move_fn, add_import
from fix_cli_compile19 import move_type

def main():
    cli = "src/cli.zig"
    move_fn(cli, "projectFunctionCacheManifestPath", "src/cli/cache.zig", "cli/cache.zig")
    move_fn(cli, "cacheEntryLastUsedNs", "src/cli/cache.zig", "cli/cache.zig")
    move_type(cli, "MemoryStageReporterContext", "src/cli/types.zig", "cli/types.zig")
    add_import("src/cli/build_exe.zig", 'const projectFunctionCacheManifestPath = @import("cache.zig").projectFunctionCacheManifestPath;')
    add_import("src/cli/build_lib.zig", 'const dynlib_compat = @import("../dynlib_compat.zig");')
    add_import("src/cli/cache.zig", 'const freeOwnedStringSlice = @import("compile.zig").freeOwnedStringSlice;')
    add_import("src/cli/compile.zig", 'const MemoryStageReporterContext = @import("types.zig").MemoryStageReporterContext;')
    print("done")

if __name__ == "__main__":
    main()
