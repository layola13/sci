#!/usr/bin/env python3
"""fix_cli_compile23.py — thirteenth wave of the cli-split fix (4 errors).

Moves (cli.zig -> submodule, pub fn, alias left in cli.zig):
  libDupeZ -> cli/build_lib.zig
  writeVerifierMemoryStage, reportVerifierMemoryStage -> cli/compile.zig
    (deps currentRssBytes + MemoryStageReporterContext already in types.zig;
     elapsedNs/writeMemoryAmount/writeMemoryDelta already in compile.zig)
Pure import additions:
  build_exe.zig: writeJsonString (json.zig)
  cache.zig: manifestDependencies (compile.zig; moved in wave 8)
Run from /content/sa_all/sci2.
"""
from fix_cli_compile11 import move_fn, add_import

def main():
    cli = "src/cli.zig"
    move_fn(cli, "libDupeZ", "src/cli/build_lib.zig", "cli/build_lib.zig")
    move_fn(cli, "writeVerifierMemoryStage", "src/cli/compile.zig", "cli/compile.zig")
    move_fn(cli, "reportVerifierMemoryStage", "src/cli/compile.zig", "cli/compile.zig")
    add_import("src/cli/build_exe.zig", 'const writeJsonString = @import("json.zig").writeJsonString;')
    add_import("src/cli/cache.zig", 'const manifestDependencies = @import("compile.zig").manifestDependencies;')
    print("done")

if __name__ == "__main__":
    main()
