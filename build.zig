const std = @import("std");

const BuildCtx = @import("build/ctx.zig").BuildCtx;
const steps_options = @import("build/steps_options.zig");
const steps_lib = @import("build/steps_lib.zig");
const steps_sastd = @import("build/steps_sastd.zig");
const steps_smoke = @import("build/steps_smoke.zig");
const steps_cli = @import("build/steps_cli.zig");
const steps_matrix = @import("build/steps_matrix.zig");
const steps_cli_smoke = @import("build/steps_cli_smoke.zig");
const steps_std = @import("build/steps_std.zig");
const steps_windows = @import("build/steps_windows.zig");
const steps_net = @import("build/steps_net.zig");
const steps_aggregate = @import("build/steps_aggregate.zig");
const steps_demos = @import("build/steps_demos.zig");
const steps_bench = @import("build/steps_bench.zig");

/// Build entry point. The implementation lives in build/steps_*.zig,
/// one step function per section of the original build.zig body,
/// sharing state through BuildCtx (build/ctx.zig). Helpers live in
/// build/{version,paths,sastd_mirror,llvm}.zig.
pub fn build(b: *std.Build) void {
    var ctx: BuildCtx = .{ .b = b };
    steps_options.buildOptions(&ctx);
    steps_lib.buildLib(&ctx);
    steps_sastd.buildSaStd(&ctx);
    steps_smoke.buildSmokeTests(&ctx);
    steps_cli.buildCli(&ctx);
    steps_matrix.buildMatrixTests(&ctx);
    steps_cli_smoke.buildCliSmokeTests(&ctx);
    steps_std.buildStdTests(&ctx);
    steps_windows.buildWindowsTests(&ctx);
    steps_net.buildNetTests(&ctx);
    steps_aggregate.buildAggregateSteps(&ctx);
    steps_demos.buildDemos(&ctx);
    steps_bench.buildBench(&ctx);
}
