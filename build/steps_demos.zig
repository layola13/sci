const BuildCtx = @import("ctx.zig").BuildCtx;
const addLlvmBinDirToRun = @import("llvm.zig").addLlvmBinDirToRun;

/// build.zig lines 1475-1569.
pub fn buildDemos(ctx: *BuildCtx) void {
    const b = ctx.b;
    const target = ctx.target;
    const optimize = ctx.optimize;
    const is_windows = ctx.is_windows;
    const is_linux = ctx.is_linux;
    const enable_llvm = ctx.enable_llvm;
    const llvm_lib_dir = ctx.llvm_lib_dir;
    const repo_root_lazy = ctx.repo_root_lazy;
    const build_options = ctx.build_options;
    const sio_module = ctx.sio_module;
    const lib_module = ctx.lib_module;
    const test_step = ctx.test_step;
    const run_plugin_host_smoke = ctx.run_plugin_host_smoke;
    const run_pkg_core_tests = ctx.run_pkg_core_tests;
    const run_wasm_matrix = ctx.run_wasm_matrix;
    const run_trap_baseline = ctx.run_trap_baseline;
    const run_std_smoke_core = ctx.run_std_smoke_core;
    const run_std_smoke_containers = ctx.run_std_smoke_containers;
    const run_unit_framework = ctx.run_unit_framework;
    const run_native_sys_runtime = ctx.run_native_sys_runtime;
    const run_smoke = ctx.run_smoke;
    const windows_runtime_step = ctx.windows_runtime_step;
    const linux_runtime_step = ctx.linux_runtime_step;
    const runtime_abi_step = ctx.runtime_abi_step;
    const std_step = ctx.std_step;

    const scope_demo_module = b.createModule(.{
        .root_source_file = b.path("tests/libsa_scope_demo.zig"),
        .target = target,
        .optimize = optimize,
        // NOTE: spawns subprocesses via sio.Child (live-env snapshot needs libc).
        .link_libc = true,
    });
    scope_demo_module.addImport("sio", sio_module);
    const scope_demo = b.addTest(.{
        .root_module = scope_demo_module,
    });
    scope_demo.root_module.addOptions("build_options", build_options);
    const run_scope_demo = b.addRunArtifact(scope_demo);
    ctx.run_scope_demo = run_scope_demo;
    run_scope_demo.setCwd(repo_root_lazy);
    test_step.dependOn(&run_scope_demo.step);
    const scope_demo_step = b.step("scope-demo", "Run libsa scope demo tests");
    scope_demo_step.dependOn(&run_scope_demo.step);

    const ffi_handle_demo_module = b.createModule(.{
        .root_source_file = b.path("tests/integration/ffi_handle_demo.zig"),
        .target = target,
        .optimize = optimize,
    });
    ffi_handle_demo_module.addImport("sio", sio_module);
    ffi_handle_demo_module.addImport("saasm", lib_module);
    ffi_handle_demo_module.addOptions("build_options", build_options);
    const ffi_handle_demo = b.addTest(.{
        .root_module = ffi_handle_demo_module,
    });
    const run_ffi_handle_demo = b.addRunArtifact(ffi_handle_demo);
    ctx.run_ffi_handle_demo = run_ffi_handle_demo;
    run_ffi_handle_demo.setCwd(repo_root_lazy);
    addLlvmBinDirToRun(b, run_ffi_handle_demo, enable_llvm, llvm_lib_dir, target.result.os.tag);
    if (enable_llvm) test_step.dependOn(&run_ffi_handle_demo.step);
    const ffi_handle_demo_step = b.step("ffi-handle-demo", "Run FFI handle integration demo tests");
    ffi_handle_demo_step.dependOn(&run_ffi_handle_demo.step);

    const hubproxy_module = b.createModule(.{
        .root_source_file = b.path("examples/hubproxy/main.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    hubproxy_module.addImport("sio", sio_module);
    hubproxy_module.addImport("saasm", lib_module);
    hubproxy_module.addOptions("build_options", build_options);
    const hubproxy_tests = b.addTest(.{
        .root_module = hubproxy_module,
    });
    const run_hubproxy_tests = b.addRunArtifact(hubproxy_tests);
    ctx.run_hubproxy_tests = run_hubproxy_tests;
    run_hubproxy_tests.setCwd(repo_root_lazy);
    addLlvmBinDirToRun(b, run_hubproxy_tests, enable_llvm, llvm_lib_dir, target.result.os.tag);
    test_step.dependOn(&run_hubproxy_tests.step);
    const hubproxy_test_step = b.step("hubproxy-test", "Run hubproxy example tests");
    hubproxy_test_step.dependOn(&run_hubproxy_tests.step);

    const hubproxy_exe = b.addExecutable(.{
        .name = "hubproxy",
        .root_module = hubproxy_module,
    });
    const install_hubproxy_exe = b.addInstallArtifact(hubproxy_exe, .{});
    b.getInstallStep().dependOn(&install_hubproxy_exe.step);

    const referee_loc_lint = b.addSystemCommand(&.{ "zig", "run", "tools/referee_loc_lint.zig" });
    ctx.referee_loc_lint = referee_loc_lint;
    referee_loc_lint.setCwd(repo_root_lazy);
    const referee_loc_lint_step = b.step("referee-loc-lint", "Run referee line-count lint");
    referee_loc_lint_step.dependOn(&referee_loc_lint.step);

    const ci_step = b.step("ci", "Run the v0.1 CI gate");
    ci_step.dependOn(&run_trap_baseline.step);
    ci_step.dependOn(&run_std_smoke_core.step);
    ci_step.dependOn(&run_std_smoke_containers.step);
    if (enable_llvm) ci_step.dependOn(&run_unit_framework.step);
    if (is_linux) {
        ci_step.dependOn(linux_runtime_step);
    } else {
        ci_step.dependOn(&run_native_sys_runtime.step);
    }
    ci_step.dependOn(runtime_abi_step);
    ci_step.dependOn(&run_smoke.step);
    ci_step.dependOn(&run_scope_demo.step);
    if (enable_llvm) ci_step.dependOn(&run_ffi_handle_demo.step);
    ci_step.dependOn(&run_hubproxy_tests.step);
    ci_step.dependOn(&run_pkg_core_tests.step);
    ci_step.dependOn(&run_plugin_host_smoke.step);
    ci_step.dependOn(&referee_loc_lint.step);
    ci_step.dependOn(&run_wasm_matrix.step);
    if (is_windows) ci_step.dependOn(windows_runtime_step);

    if (is_windows) {
        std_step.dependOn(windows_runtime_step);
    }

    const pre_push_step = b.step("pre-push", "Run the pre-push gate");
    pre_push_step.dependOn(ci_step);
}
