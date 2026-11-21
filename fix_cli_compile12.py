#!/usr/bin/env python3
"""fix_cli_compile12.py — second wave of the cli-split fix (14 errors).

Moves (cli.zig -> submodule, pub fn, alias left in cli.zig):
  finishProfileMetrics, printStageTiming -> cli/types.zig (pure CompileMetrics)
  writeSuccessJson, writeMemoryStageLine,
  writeMemoryReportText, writeSuccessDiagnostics -> cli/errors.zig (diagnostics cluster)
  rejectNpmBindsUnlessJs -> cli/compile.zig (flattener guard)
  sabReferenceName -> cli/cache.zig (pure std.mem)
Pure import additions:
  cache.zig: sio, builtin, WasmTarget, ProjectCacheKey (types.zig),
             common_upstream (../common/upstream_loc.zig)
  compile.zig: stdRootFromEnv (cache.zig)
  daemon.zig: elapsedNs (compile.zig)
  build_exe.zig: finishProfileMetrics, printStageTiming (types.zig),
                 writeSuccessDiagnostics (errors.zig), rejectNpmBindsUnlessJs (compile.zig)
  build_lib.zig: rejectNpmBindsUnlessJs (compile.zig)
  errors.zig: CompileMetrics, CompileMemoryMetrics, memoryEndPrevious (types.zig)
Run from /content/sa_all/sci2.
"""
from fix_cli_compile11 import move_fn, add_import

def main():
    cli = "src/cli.zig"
    move_fn(cli, "finishProfileMetrics", "src/cli/types.zig", "cli/types.zig")
    move_fn(cli, "printStageTiming", "src/cli/types.zig", "cli/types.zig")
    for name in ("writeSuccessJson", "writeMemoryStageLine",
                 "writeMemoryReportText", "writeSuccessDiagnostics"):
        move_fn(cli, name, "src/cli/errors.zig", "cli/errors.zig")
    move_fn(cli, "rejectNpmBindsUnlessJs", "src/cli/compile.zig", "cli/compile.zig")
    move_fn(cli, "sabReferenceName", "src/cli/cache.zig", "cli/cache.zig")
    # errors.zig needs the metrics types for the moved diagnostics cluster
    add_import("src/cli/errors.zig", 'const CompileMetrics = @import("types.zig").CompileMetrics;')
    add_import("src/cli/errors.zig", 'const CompileMemoryMetrics = @import("types.zig").CompileMemoryMetrics;')
    add_import("src/cli/errors.zig", 'const memoryEndPrevious = @import("types.zig").memoryEndPrevious;')
    # cache.zig basic imports
    add_import("src/cli/cache.zig", 'const sio = @import("sio");')
    add_import("src/cli/cache.zig", 'const builtin = @import("builtin");')
    add_import("src/cli/cache.zig", 'const WasmTarget = @import("types.zig").WasmTarget;')
    add_import("src/cli/cache.zig", 'const ProjectCacheKey = @import("types.zig").ProjectCacheKey;')
    add_import("src/cli/cache.zig", 'const common_upstream = @import("../common/upstream_loc.zig");')
    add_import("src/cli/compile.zig", 'const stdRootFromEnv = @import("cache.zig").stdRootFromEnv;')
    add_import("src/cli/daemon.zig", 'const elapsedNs = @import("compile.zig").elapsedNs;')
    add_import("src/cli/build_exe.zig", 'const finishProfileMetrics = @import("types.zig").finishProfileMetrics;')
    add_import("src/cli/build_exe.zig", 'const printStageTiming = @import("types.zig").printStageTiming;')
    add_import("src/cli/build_exe.zig", 'const writeSuccessDiagnostics = @import("errors.zig").writeSuccessDiagnostics;')
    add_import("src/cli/build_exe.zig", 'const rejectNpmBindsUnlessJs = @import("compile.zig").rejectNpmBindsUnlessJs;')
    add_import("src/cli/build_lib.zig", 'const rejectNpmBindsUnlessJs = @import("compile.zig").rejectNpmBindsUnlessJs;')
    print("done")

if __name__ == "__main__":
    main()
