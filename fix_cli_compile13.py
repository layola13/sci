#!/usr/bin/env python3
"""fix_cli_compile13.py — third wave of the cli-split fix (13 errors).

Moves (cli.zig -> submodule, pub fn, alias left in cli.zig):
  tripleIsWindows, saStdArchivePath, saStdArchivePathForTarget -> cli/compile.zig
  wasmStdArchivePath -> cli/build_exe.zig (only caller; already imports
    WasmTarget + will import saStdArchivePathForTarget from compile.zig)
  estimateBackendIrMetrics, attachBackendIrMetrics -> cli/compile.zig
  pruneSabVtableConsts, projectCacheDir, projectCacheTestMetadataPath -> cli/cache.zig
  writeMetricsJson, writeOptionalJsonU64, writeOptionalJsonU64Field -> cli/errors.zig
Pure import additions (incl. pre-empting errors masked by Zig's one-error-per-fn rule):
  compile.zig: build_options, BackendIrMetrics (types.zig), pkg_resolver (../pkg/resolver.zig)
  build_exe.zig: stdRootFromEnv (cache.zig), saStdArchivePathForTarget (compile.zig)
  build_lib.zig: stdRootFromEnv (cache.zig), saStdArchivePathForTarget (compile.zig)
  cache.zig: DceMode (../emit_options.zig)
  errors.zig: writeMemoryAmount (compile.zig)
Run from /content/sa_all/sci2.
"""
from fix_cli_compile11 import move_fn, add_import

def main():
    cli = "src/cli.zig"
    move_fn(cli, "tripleIsWindows", "src/cli/compile.zig", "cli/compile.zig")
    move_fn(cli, "saStdArchivePath", "src/cli/compile.zig", "cli/compile.zig")
    move_fn(cli, "saStdArchivePathForTarget", "src/cli/compile.zig", "cli/compile.zig")
    move_fn(cli, "wasmStdArchivePath", "src/cli/build_exe.zig", "cli/build_exe.zig")
    move_fn(cli, "estimateBackendIrMetrics", "src/cli/compile.zig", "cli/compile.zig")
    move_fn(cli, "attachBackendIrMetrics", "src/cli/compile.zig", "cli/compile.zig")
    move_fn(cli, "pruneSabVtableConsts", "src/cli/cache.zig", "cli/cache.zig")
    move_fn(cli, "projectCacheDir", "src/cli/cache.zig", "cli/cache.zig")
    move_fn(cli, "projectCacheTestMetadataPath", "src/cli/cache.zig", "cli/cache.zig")
    for name in ("writeMetricsJson", "writeOptionalJsonU64", "writeOptionalJsonU64Field"):
        move_fn(cli, name, "src/cli/errors.zig", "cli/errors.zig")
    add_import("src/cli/compile.zig", 'const build_options = @import("build_options");')
    add_import("src/cli/compile.zig", 'const BackendIrMetrics = @import("types.zig").BackendIrMetrics;')
    add_import("src/cli/compile.zig", 'const pkg_resolver = @import("../pkg/resolver.zig");')
    add_import("src/cli/build_exe.zig", 'const stdRootFromEnv = @import("cache.zig").stdRootFromEnv;')
    add_import("src/cli/build_exe.zig", 'const saStdArchivePathForTarget = @import("compile.zig").saStdArchivePathForTarget;')
    add_import("src/cli/build_lib.zig", 'const stdRootFromEnv = @import("cache.zig").stdRootFromEnv;')
    add_import("src/cli/build_lib.zig", 'const saStdArchivePathForTarget = @import("compile.zig").saStdArchivePathForTarget;')
    add_import("src/cli/cache.zig", 'const DceMode = @import("../emit_options.zig").DceMode;')
    add_import("src/cli/errors.zig", 'const writeMemoryAmount = @import("compile.zig").writeMemoryAmount;')
    print("done")

if __name__ == "__main__":
    main()
