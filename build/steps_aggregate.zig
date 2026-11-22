const BuildCtx = @import("ctx.zig").BuildCtx;

/// build.zig lines 1391-1474.
pub fn buildAggregateSteps(ctx: *BuildCtx) void {
    const b = ctx.b;
    const target = ctx.target;
    const optimize = ctx.optimize;
    const is_linux = ctx.is_linux;
    const repo_root_lazy = ctx.repo_root_lazy;
    const build_options = ctx.build_options;
    const sio_module = ctx.sio_module;
    const test_step = ctx.test_step;
    const run_lib_root_smoke = ctx.run_lib_root_smoke;
    const run_cli_host_basic = ctx.run_cli_host_basic;
    const run_trap_baseline = ctx.run_trap_baseline;
    const run_std_smoke_core = ctx.run_std_smoke_core;
    const run_std_smoke_containers = ctx.run_std_smoke_containers;
    const run_sa_std_unit = ctx.run_sa_std_unit;
    const run_sa_std_runtime = ctx.run_sa_std_runtime;
    const run_sa_net_uring_tests = ctx.run_sa_net_uring_tests;
    const run_sa_http2_tests = ctx.run_sa_http2_tests;
    const run_sa_tls_server_tests = ctx.run_sa_tls_server_tests;
    const run_sa_tls_client_tests = ctx.run_sa_tls_client_tests;
    const run_sa_thread_local_tests = ctx.run_sa_thread_local_tests;
    const run_sa_dtls_tests = ctx.run_sa_dtls_tests;
    const run_sa_quic_tests = ctx.run_sa_quic_tests;
    const run_sa_term_runtime = ctx.run_sa_term_runtime;
    const run_native_sys_runtime = ctx.run_native_sys_runtime;
    const windows_runtime_step = ctx.windows_runtime_step;

    const runtime_abi = b.addSystemCommand(&.{
        "zig",
        "run",
        "tools/runtime_abi_check.zig",
        "--",
        "--platform",
        "both",
    });
    runtime_abi.setCwd(repo_root_lazy);
    const runtime_abi_step = b.step("runtime-abi-check", "Validate the shared sa_std header contract on Linux and Windows");
    ctx.runtime_abi_step = runtime_abi_step;
    runtime_abi_step.dependOn(&runtime_abi.step);
    test_step.dependOn(runtime_abi_step);

    const linux_runtime_step = b.step("linux-runtime", "Run Linux-only runtime and kernel integration checks");
    ctx.linux_runtime_step = linux_runtime_step;
    if (is_linux) {
        linux_runtime_step.dependOn(&run_native_sys_runtime.step);
        linux_runtime_step.dependOn(&run_sa_std_unit.step);
        linux_runtime_step.dependOn(&run_sa_std_runtime.step);
        linux_runtime_step.dependOn(&run_sa_net_uring_tests.step);
        linux_runtime_step.dependOn(&run_sa_http2_tests.step);
        linux_runtime_step.dependOn(&run_sa_tls_server_tests.step);
        linux_runtime_step.dependOn(&run_sa_tls_client_tests.step);
        linux_runtime_step.dependOn(&run_sa_dtls_tests.step);
        linux_runtime_step.dependOn(&run_sa_thread_local_tests.step);
        linux_runtime_step.dependOn(&run_sa_quic_tests.step);
        linux_runtime_step.dependOn(&run_sa_term_runtime.step);
    }

    const std_smoke_step = b.step("std-smoke", "Run the SA standard library smoke tests");
    std_smoke_step.dependOn(&run_std_smoke_core.step);
    std_smoke_step.dependOn(&run_std_smoke_containers.step);

    const std_step = b.step("std", "Run the SA standard library and runtime checks");
    ctx.std_step = std_step;
    std_step.dependOn(&run_std_smoke_core.step);
    std_step.dependOn(&run_std_smoke_containers.step);
    if (is_linux) {
        std_step.dependOn(linux_runtime_step);
    } else {
        std_step.dependOn(runtime_abi_step);
        std_step.dependOn(&run_native_sys_runtime.step);
    }

    const smoke_module = b.createModule(.{
        .root_source_file = b.path("tests/smoke/whitepaper_lint.zig"),
        .target = target,
        .optimize = optimize,
    });
    smoke_module.addImport("sio", sio_module);
    const smoke = b.addTest(.{
        .root_module = smoke_module,
    });
    smoke.root_module.addOptions("build_options", build_options);
    const run_smoke = b.addRunArtifact(smoke);
    ctx.run_smoke = run_smoke;
    run_smoke.setCwd(repo_root_lazy);
    const smoke_step = b.step("smoke", "Run smoke tests");
    smoke_step.dependOn(&run_smoke.step);
    smoke_step.dependOn(&run_std_smoke_core.step);
    smoke_step.dependOn(&run_std_smoke_containers.step);
    test_step.dependOn(&run_smoke.step);

    const whitepaper_lint_step = b.step("whitepaper-lint", "Run whitepaper smoke lint without std smoke reruns");
    whitepaper_lint_step.dependOn(&run_smoke.step);

    const core_step = b.step("core", "Run cross-platform core compiler checks");
    core_step.dependOn(&run_lib_root_smoke.step);
    core_step.dependOn(&run_trap_baseline.step);
    core_step.dependOn(&run_smoke.step);

    const runtime_basic_step = b.step("runtime-basic", "Run cross-platform basic runtime checks");
    runtime_basic_step.dependOn(runtime_abi_step);
    runtime_basic_step.dependOn(&run_native_sys_runtime.step);
    if (target.result.os.tag == .windows) {
        runtime_basic_step.dependOn(windows_runtime_step);
    } else {
        runtime_basic_step.dependOn(&run_sa_std_unit.step);
    }

    const host_basic_step = b.step("host-basic", "Run host-portable compiler and runtime baseline checks");
    host_basic_step.dependOn(core_step);
    host_basic_step.dependOn(&run_cli_host_basic.step);
    if (target.result.os.tag != .windows) {
        host_basic_step.dependOn(runtime_basic_step);
    }
}
