const BuildCtx = @import("ctx.zig").BuildCtx;
const addLlvmcSupportToModule = @import("llvm.zig").addLlvmcSupportToModule;
const addLlvmBinDirToRun = @import("llvm.zig").addLlvmBinDirToRun;

/// build.zig lines 221-347.
pub fn buildSmokeTests(ctx: *BuildCtx) void {
    const b = ctx.b;
    const target = ctx.target;
    const optimize = ctx.optimize;
    const is_windows = ctx.is_windows;
    const enable_llvm = ctx.enable_llvm;
    const llvm_include_dir = ctx.llvm_include_dir;
    const llvm_lib_dir = ctx.llvm_lib_dir;
    const llvm_lib_name = ctx.llvm_lib_name;
    const llvmc_test_filter = ctx.llvmc_test_filter;
    const repo_root_lazy = ctx.repo_root_lazy;
    const build_options = ctx.build_options;
    const sio_module = ctx.sio_module;
    const lib_module = ctx.lib_module;
    const test_step = ctx.test_step;
    const sync_sa_std_artifact = ctx.sync_sa_std_artifact;

    const lib_root_smoke_module = b.createModule(.{
        .root_source_file = b.path("tests/lib_root_smoke.zig"),
        .target = target,
        .optimize = optimize,
    });
    lib_root_smoke_module.addImport("sio", sio_module);
    lib_root_smoke_module.addImport("saasm", lib_module);
    lib_root_smoke_module.addOptions("build_options", build_options);
    const lib_root_smoke = b.addTest(.{
        .root_module = lib_root_smoke_module,
    });
    const run_lib_root_smoke = b.addRunArtifact(lib_root_smoke);
    ctx.run_lib_root_smoke = run_lib_root_smoke;
    run_lib_root_smoke.setCwd(repo_root_lazy);
    addLlvmBinDirToRun(b, run_lib_root_smoke, enable_llvm, llvm_lib_dir, target.result.os.tag);
    test_step.dependOn(&run_lib_root_smoke.step);
    const lib_root_smoke_step = b.step("lib-root-smoke", "Run public library root and CLI help smoke tests");
    lib_root_smoke_step.dependOn(&run_lib_root_smoke.step);

    const plugin_host_smoke_module = b.createModule(.{
        .root_source_file = b.path("tests/plugin_host_smoke.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    plugin_host_smoke_module.addImport("sio", sio_module);
    plugin_host_smoke_module.addImport("saasm", lib_module);
    plugin_host_smoke_module.addOptions("build_options", build_options);
    const plugin_host_smoke = b.addTest(.{
        .root_module = plugin_host_smoke_module,
    });
    const run_plugin_host_smoke = b.addRunArtifact(plugin_host_smoke);
    ctx.run_plugin_host_smoke = run_plugin_host_smoke;
    run_plugin_host_smoke.setCwd(repo_root_lazy);
    addLlvmBinDirToRun(b, run_plugin_host_smoke, enable_llvm, llvm_lib_dir, target.result.os.tag);
    test_step.dependOn(&run_plugin_host_smoke.step);
    const plugin_host_smoke_step = b.step("plugin-host-smoke", "Run runtime plugin host smoke tests");
    plugin_host_smoke_step.dependOn(&run_plugin_host_smoke.step);

    const llvmc_test_module = b.createModule(.{
        .root_source_file = b.path("src/emit_llvm_llvmc.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    llvmc_test_module.addImport("sio", sio_module);
    addLlvmcSupportToModule(b, llvmc_test_module, enable_llvm, llvm_include_dir, llvm_lib_dir, llvm_lib_name);
    llvmc_test_module.addOptions("build_options", build_options);
    const llvmc_tests = b.addTest(.{
        .root_module = llvmc_test_module,
        .filters = if (llvmc_test_filter) |filter| &.{filter} else &.{},
    });
    const run_llvmc_tests = b.addRunArtifact(llvmc_tests);
    run_llvmc_tests.setCwd(repo_root_lazy);
    addLlvmBinDirToRun(b, run_llvmc_tests, enable_llvm, llvm_lib_dir, target.result.os.tag);
    const llvmc_test_step = b.step("llvmc-test", "Run LLVM-C backend tests");
    llvmc_test_step.dependOn(&run_llvmc_tests.step);

    const windows_llvm_smoke_module = b.createModule(.{
        .root_source_file = b.path("tests/cli_smoke.zig"),
        .target = target,
        .optimize = optimize,
    });
    windows_llvm_smoke_module.addImport("sio", sio_module);
    windows_llvm_smoke_module.addImport("saasm", lib_module);
    windows_llvm_smoke_module.addOptions("build_options", build_options);
    const windows_llvm_smoke = b.addTest(.{
        .root_module = windows_llvm_smoke_module,
        .filters = &.{"windows llvm builds and runs hello world executable"},
    });
    const run_windows_llvm_smoke = b.addRunArtifact(windows_llvm_smoke);
    run_windows_llvm_smoke.setCwd(repo_root_lazy);
    if (is_windows and enable_llvm) {
        addLlvmBinDirToRun(b, run_windows_llvm_smoke, enable_llvm, llvm_lib_dir, target.result.os.tag);
        run_windows_llvm_smoke.step.dependOn(&sync_sa_std_artifact.step);
    }
    const windows_llvm_smoke_step = b.step("windows-llvm-smoke", "Build and run a native Windows executable through LLVM-C");
    if (is_windows and enable_llvm) windows_llvm_smoke_step.dependOn(&run_windows_llvm_smoke.step);

    const pkg_core_tests_module = b.createModule(.{
        .root_source_file = b.path("src/pkg_core_tests_root.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    pkg_core_tests_module.addImport("sio", sio_module);
    pkg_core_tests_module.addOptions("build_options", build_options);
    const pkg_core_tests = b.addTest(.{
        .root_module = pkg_core_tests_module,
    });
    const run_pkg_core_tests = b.addRunArtifact(pkg_core_tests);
    ctx.run_pkg_core_tests = run_pkg_core_tests;
    run_pkg_core_tests.setCwd(repo_root_lazy);
    test_step.dependOn(&run_pkg_core_tests.step);
    const pkg_core_test_step = b.step("pkg-core-test", "Run package core module tests");
    pkg_core_test_step.dependOn(&run_pkg_core_tests.step);

    const pkg_sum_perf_tests_module = b.createModule(.{
        .root_source_file = b.path("src/pkg/sum_perf_test.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    pkg_sum_perf_tests_module.addImport("sio", sio_module);
    const pkg_sum_perf_tests = b.addTest(.{
        .root_module = pkg_sum_perf_tests_module,
        .filters = &.{"sum flattens one hundred transitive dependencies within budget"},
    });
    const run_pkg_sum_perf_tests = b.addRunArtifact(pkg_sum_perf_tests);
    run_pkg_sum_perf_tests.setCwd(repo_root_lazy);
    const pkg_sum_perf_test_step = b.step("pkg-sum-perf-test", "Run sa.sum 100 dependency performance test");
    pkg_sum_perf_test_step.dependOn(&run_pkg_sum_perf_tests.step);

    const pkg_audit_perf_tests_module = b.createModule(.{
        .root_source_file = b.path("src/pkg/audit_perf_test.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    pkg_audit_perf_tests_module.addImport("sio", sio_module);
    const pkg_audit_perf_tests = b.addTest(.{
        .root_module = pkg_audit_perf_tests_module,
        .filters = &.{"audit scans synthesized package within fifty milliseconds"},
    });
    const run_pkg_audit_perf_tests = b.addRunArtifact(pkg_audit_perf_tests);
    run_pkg_audit_perf_tests.setCwd(repo_root_lazy);
    const pkg_audit_perf_test_step = b.step("pkg-audit-perf-test", "Run package audit 50ms performance test");
    pkg_audit_perf_test_step.dependOn(&run_pkg_audit_perf_tests.step);
}
