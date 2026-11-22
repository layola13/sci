const BuildCtx = @import("ctx.zig").BuildCtx;
const defaultUnitFileJobs = @import("paths.zig").defaultUnitFileJobs;
const pathFromRoot = @import("paths.zig").pathFromRoot;
const addHostThreadShimToModule = @import("llvm.zig").addHostThreadShimToModule;
const addTaskCtxToModule = @import("llvm.zig").addTaskCtxToModule;
const addB64SwizzleToModule = @import("llvm.zig").addB64SwizzleToModule;
const addLlvmBinDirToRun = @import("llvm.zig").addLlvmBinDirToRun;

/// build.zig lines 911-1052.
pub fn buildStdTests(ctx: *BuildCtx) void {
    const b = ctx.b;
    const target = ctx.target;
    const optimize = ctx.optimize;
    const is_windows = ctx.is_windows;
    const is_linux = ctx.is_linux;
    const enable_llvm = ctx.enable_llvm;
    const llvm_lib_dir = ctx.llvm_lib_dir;
    const repo_root_lazy = ctx.repo_root_lazy;
    const build_options = ctx.build_options;
    const test_build_options = ctx.test_build_options;
    const sio_module = ctx.sio_module;
    const sa_net_primitives_module = ctx.sa_net_primitives_module;
    const sa_ws_stream_module = ctx.sa_ws_stream_module;
    const lib_module = ctx.lib_module;
    const test_step = ctx.test_step;
    const sync_sa_std_artifact = ctx.sync_sa_std_artifact;
    const install_sa_exe = ctx.install_sa_exe;

    const std_smoke_core_module = b.createModule(.{
        .root_source_file = b.path("tests/std_smoke_core.zig"),
        .target = target,
        .optimize = optimize,
    });
    std_smoke_core_module.addImport("sio", sio_module);
    std_smoke_core_module.addImport("saasm", lib_module);
    std_smoke_core_module.addOptions("build_options", build_options);
    std_smoke_core_module.addOptions("test_build_options", test_build_options);
    const std_smoke_core = b.addTest(.{
        .root_module = std_smoke_core_module,
        .filters = &.{
            "sa_std core primitives are concrete and verifiable",
            "sa_std package manifest parses as an empty package boundary",
            "sa_std io and process interfaces match native resource ABI",
            "sa_std rust core helpers are concrete and verifiable",
        },
    });

    const std_smoke_containers_module = b.createModule(.{
        .root_source_file = b.path("tests/std_smoke_containers.zig"),
        .target = target,
        .optimize = optimize,
    });
    std_smoke_containers_module.addImport("sio", sio_module);
    std_smoke_containers_module.addImport("saasm", lib_module);
    std_smoke_containers_module.addOptions("build_options", build_options);
    std_smoke_containers_module.addOptions("test_build_options", test_build_options);
    const std_smoke_containers = b.addTest(.{
        .root_module = std_smoke_containers_module,
    });

    const run_std_smoke_core = b.addRunArtifact(std_smoke_core);
    ctx.run_std_smoke_core = run_std_smoke_core;
    run_std_smoke_core.setCwd(repo_root_lazy);
    addLlvmBinDirToRun(b, run_std_smoke_core, enable_llvm, llvm_lib_dir, target.result.os.tag);
    test_step.dependOn(&run_std_smoke_core.step);

    const run_std_smoke_containers = b.addRunArtifact(std_smoke_containers);
    ctx.run_std_smoke_containers = run_std_smoke_containers;
    run_std_smoke_containers.setCwd(repo_root_lazy);
    addLlvmBinDirToRun(b, run_std_smoke_containers, enable_llvm, llvm_lib_dir, target.result.os.tag);
    test_step.dependOn(&run_std_smoke_containers.step);

    const unit_framework_module = b.createModule(.{
        .root_source_file = b.path("tests/unit_framework/runner.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    unit_framework_module.addImport("sio", sio_module);
    unit_framework_module.addImport("saasm", lib_module);
    unit_framework_module.addOptions("build_options", build_options);
    const unit_framework = b.addTest(.{
        .root_module = unit_framework_module,
    });
    const run_unit_framework = b.addRunArtifact(unit_framework);
    ctx.run_unit_framework = run_unit_framework;
    run_unit_framework.setCwd(repo_root_lazy);
    addLlvmBinDirToRun(b, run_unit_framework, enable_llvm, llvm_lib_dir, target.result.os.tag);
    run_unit_framework.step.dependOn(&install_sa_exe.step);
    run_unit_framework.step.dependOn(&sync_sa_std_artifact.step);
    run_unit_framework.setEnvironmentVariable("SA_STD_DIR", pathFromRoot(b, "sa_std"));
    // NOTE(Zig 0.17): the install prefix is only known at make time and the
    // default test runner rejects unknown `--sa-bin=` argv, so pass the
    // just-built `sa` via SA_BIN (which the runner already honors) instead.
    // This matches the 0.14 behavior for the default `zig-out` prefix.
    run_unit_framework.setEnvironmentVariable("SA_BIN", pathFromRoot(b, if (is_windows) "zig-out/bin/sa.exe" else "zig-out/bin/sa"));
    // Multithreaded unit-test execution: SA_UNIT_FILE_JOBS>1 makes the runner
    // queue suites and verify them via external `sa` processes with a worker
    // thread pool instead of slow serial in-process runs. Defaults to the
    // host CPU count (capped at 8); override with -Dunit-file-jobs=<n>
    // (1 keeps the serial in-process mode).
    run_unit_framework.setEnvironmentVariable("SA_UNIT_FILE_JOBS", b.fmt("{d}", .{b.option(u32, "unit-file-jobs", "Parallel external file jobs for the native SA unit framework suites.") orelse defaultUnitFileJobs()}));
    if (enable_llvm) test_step.dependOn(&run_unit_framework.step);
    const unit_framework_step = b.step("unit-framework", "Run native SA unit framework suites");
    if (enable_llvm) unit_framework_step.dependOn(&run_unit_framework.step);

    const sa_std_unit_module = b.createModule(.{
        .root_source_file = b.path("src/runtime/sa_std.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    sa_std_unit_module.addImport("sio", sio_module);
    sa_std_unit_module.addImport("sa_net_primitives", sa_net_primitives_module);
    sa_std_unit_module.addImport("sa_ws_stream", sa_ws_stream_module);
    sa_std_unit_module.addOptions("build_options", build_options);
    // NOTE: sa_std.zig references the swizzle/pthread C shims; test roots
    // compiling it directly must link them (like the sa_std lib modules).
    addHostThreadShimToModule(b, sa_std_unit_module, target.result.os.tag);
    addB64SwizzleToModule(b, sa_std_unit_module);
    addTaskCtxToModule(b, sa_std_unit_module, target.result);
    if (target.result.os.tag == .linux) {
        // Unicode normalization (ICU) for sa_unicode_normalize.
        sa_std_unit_module.linkSystemLibrary("icuuc", .{});
        sa_std_unit_module.linkSystemLibrary("icudata", .{});
    }
    const sa_std_unit = b.addTest(.{
        .root_module = sa_std_unit_module,
    });
    const run_sa_std_unit = b.addRunArtifact(sa_std_unit);
    ctx.run_sa_std_unit = run_sa_std_unit;
    run_sa_std_unit.setCwd(repo_root_lazy);
    if (is_linux) test_step.dependOn(&run_sa_std_unit.step);
    const sa_std_unit_step = b.step("sa-std-unit", "Run Zig unit tests for the SA standard runtime");
    sa_std_unit_step.dependOn(&run_sa_std_unit.step);

    const sa_std_runtime_module = b.createModule(.{
        .root_source_file = b.path("tests/sa_std_runtime.zig"),
        .target = target,
        .optimize = optimize,
        // NOTE: spawns subprocesses via sio.Child (live-env snapshot needs libc).
        .link_libc = true,
    });
    sa_std_runtime_module.addImport("sio", sio_module);
    sa_std_runtime_module.addOptions("build_options", build_options);
    const sa_std_runtime = b.addTest(.{
        .root_module = sa_std_runtime_module,
    });
    const run_sa_std_runtime = b.addRunArtifact(sa_std_runtime);
    ctx.run_sa_std_runtime = run_sa_std_runtime;
    run_sa_std_runtime.setCwd(repo_root_lazy);
    run_sa_std_runtime.step.dependOn(&sync_sa_std_artifact.step);
    if (is_linux) test_step.dependOn(&run_sa_std_runtime.step);
    const sa_std_runtime_step = b.step("sa-std-runtime", "Run SA standard runtime integration tests");
    sa_std_runtime_step.dependOn(&run_sa_std_runtime.step);

    const sa_std_windows_runtime_module = b.createModule(.{
        .root_source_file = b.path("tests/sa_std_windows_runtime.zig"),
        .target = target,
        .optimize = optimize,
    });
    sa_std_windows_runtime_module.addImport("sio", sio_module);
    sa_std_windows_runtime_module.addOptions("build_options", build_options);
    const sa_std_windows_runtime = b.addTest(.{
        .root_module = sa_std_windows_runtime_module,
    });
    const run_sa_std_windows_runtime = b.addRunArtifact(sa_std_windows_runtime);
    run_sa_std_windows_runtime.setCwd(repo_root_lazy);
    run_sa_std_windows_runtime.step.dependOn(&sync_sa_std_artifact.step);
    const windows_runtime_step = b.step("windows-runtime", "Run Windows SA standard runtime bootstrap checks");
    ctx.windows_runtime_step = windows_runtime_step;
    if (target.result.os.tag == .windows) {
        windows_runtime_step.dependOn(&run_sa_std_windows_runtime.step);
        test_step.dependOn(windows_runtime_step);
    }
}
