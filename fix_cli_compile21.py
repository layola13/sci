#!/usr/bin/env python3
"""fix_cli_compile21.py — eleventh wave of the cli-split fix (6 errors).

Moves (cli.zig -> submodule, pub fn, alias left in cli.zig):
  appendNativePluginLinkInputs -> cli/build_exe.zig
  generateLibDefFile -> cli/build_lib.zig
  cacheDirTreeSize -> cli/cache.zig
Pure import additions:
  build_exe.zig: nativeSizeBits (compile.zig; already pub there),
    plugins (../plugins.zig, for appendNativePluginLinkInputs)
  cache.zig: pkg_resolver (../pkg/resolver.zig)
  compile.zig: trapFromFlattenError (trap_errors.zig; already pub there)
Run from /content/sa_all/sci2.
"""
from fix_cli_compile11 import move_fn, add_import

def main():
    cli = "src/cli.zig"
    move_fn(cli, "appendNativePluginLinkInputs", "src/cli/build_exe.zig", "cli/build_exe.zig")
    move_fn(cli, "generateLibDefFile", "src/cli/build_lib.zig", "cli/build_lib.zig")
    move_fn(cli, "cacheDirTreeSize", "src/cli/cache.zig", "cli/cache.zig")
    add_import("src/cli/build_exe.zig", 'const nativeSizeBits = @import("compile.zig").nativeSizeBits;')
    add_import("src/cli/build_exe.zig", 'const plugins = @import("../plugins.zig");')
    add_import("src/cli/cache.zig", 'const pkg_resolver = @import("../pkg/resolver.zig");')
    add_import("src/cli/compile.zig", 'const trapFromFlattenError = @import("trap_errors.zig").trapFromFlattenError;')
    print("done")

if __name__ == "__main__":
    main()
