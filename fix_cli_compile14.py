#!/usr/bin/env python3
"""fix_cli_compile14.py — fourth wave of the cli-split fix (10 errors).

Moves (cli.zig -> submodule, pub fn, alias left in cli.zig):
  cguSeqShardCount, recordMetricMemoryAfterLink, freeOwnedStringSlice -> cli/compile.zig
  emitOptLevel -> cli/build_exe.zig (only caller; already imports driver)
  freeFlatInstructionMetadata, cacheKeyNormalizedPath,
  projectCacheArtifactExistsNonEmpty -> cli/cache.zig
Pure import additions:
  build_exe.zig: attachBackendIrMetrics (compile.zig; missed in wave 3)
  build_lib.zig: sizeBitsForTriple (compile.zig; already pub there)
  errors.zig: writeMemoryDelta (compile.zig; already pub there)
Run from /content/sa_all/sci2.
"""
from fix_cli_compile11 import move_fn, add_import

def main():
    cli = "src/cli.zig"
    move_fn(cli, "cguSeqShardCount", "src/cli/compile.zig", "cli/compile.zig")
    move_fn(cli, "recordMetricMemoryAfterLink", "src/cli/compile.zig", "cli/compile.zig")
    move_fn(cli, "freeOwnedStringSlice", "src/cli/compile.zig", "cli/compile.zig")
    move_fn(cli, "emitOptLevel", "src/cli/build_exe.zig", "cli/build_exe.zig")
    move_fn(cli, "freeFlatInstructionMetadata", "src/cli/cache.zig", "cli/cache.zig")
    move_fn(cli, "cacheKeyNormalizedPath", "src/cli/cache.zig", "cli/cache.zig")
    move_fn(cli, "projectCacheArtifactExistsNonEmpty", "src/cli/cache.zig", "cli/cache.zig")
    add_import("src/cli/build_exe.zig", 'const attachBackendIrMetrics = @import("compile.zig").attachBackendIrMetrics;')
    add_import("src/cli/build_lib.zig", 'const sizeBitsForTriple = @import("compile.zig").sizeBitsForTriple;')
    add_import("src/cli/errors.zig", 'const writeMemoryDelta = @import("compile.zig").writeMemoryDelta;')
    print("done")

if __name__ == "__main__":
    main()
