#!/usr/bin/env python3
"""fix_cli_compile20.py — tenth wave of the cli-split fix (6 errors).

Moves (cli.zig -> submodule, pub fn, alias left in cli.zig):
  collectExternalSymbolNames -> cli/build_exe.zig
  generateLibExportedSymbolsList -> cli/build_lib.zig
  projectFileMaybeHash, isHexCacheKey -> cli/cache.zig
  reportPluginImportDiagnostic -> cli/compile.zig
Pure import additions:
  build_exe.zig: projectPathExists (cache.zig), referee (../referee.zig,
    for collectExternalSymbolNames' VerifyOk param)
Run from /content/sa_all/sci2.
"""
from fix_cli_compile11 import move_fn, add_import

def main():
    cli = "src/cli.zig"
    move_fn(cli, "collectExternalSymbolNames", "src/cli/build_exe.zig", "cli/build_exe.zig")
    move_fn(cli, "generateLibExportedSymbolsList", "src/cli/build_lib.zig", "cli/build_lib.zig")
    move_fn(cli, "projectFileMaybeHash", "src/cli/cache.zig", "cli/cache.zig")
    move_fn(cli, "isHexCacheKey", "src/cli/cache.zig", "cli/cache.zig")
    move_fn(cli, "reportPluginImportDiagnostic", "src/cli/compile.zig", "cli/compile.zig")
    add_import("src/cli/build_exe.zig", 'const projectPathExists = @import("cache.zig").projectPathExists;')
    add_import("src/cli/build_exe.zig", 'const referee = @import("../referee.zig");')
    print("done")

if __name__ == "__main__":
    main()
