const BuildCtx = @import("ctx.zig").BuildCtx;

/// build.zig lines 1570-1596.
pub fn buildBench(ctx: *BuildCtx) void {
    const b = ctx.b;
    const target = ctx.target;
    const optimize = ctx.optimize;
    const repo_root_lazy = ctx.repo_root_lazy;
    const build_options = ctx.build_options;
    const sio_module = ctx.sio_module;
    const exe = ctx.exe;

    const bench_module = b.createModule(.{
        .root_source_file = b.path("bench/task_6_26.zig"),
        .target = target,
        .optimize = optimize,
    });
    bench_module.addImport("sio", sio_module);
    bench_module.addOptions("build_options", build_options);
    const bench_exe = b.addExecutable(.{
        .name = "saasm-bench-task-6-26",
        .root_module = bench_module,
    });
    const sa_bench_step = b.addRunArtifact(bench_exe);
    sa_bench_step.addArgs(&.{ "--lines", "64" });
    sa_bench_step.setCwd(repo_root_lazy);
    const bench_step = b.step("bench", "Run benchmark checks");
    bench_step.dependOn(&sa_bench_step.step);

    const bench_compare = b.step("bench-compare", "Run Rust vs SA benchmark comparison");

    const bench_compare_sa = b.addSystemCommand(&.{ "bash", "demos/compare/run_sa_bench.sh" });
    bench_compare_sa.setCwd(repo_root_lazy);
    bench_compare_sa.step.dependOn(&exe.step);
    bench_compare.dependOn(&bench_compare_sa.step);

    const bench_compare_rust = b.addSystemCommand(&.{ "bash", "demos/compare/run_rust_bench.sh" });
    bench_compare_rust.setCwd(repo_root_lazy);
    bench_compare.dependOn(&bench_compare_rust.step);
}
