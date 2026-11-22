const BuildCtx = @import("ctx.zig").BuildCtx;
const addHostThreadShimToModule = @import("llvm.zig").addHostThreadShimToModule;
const addTaskCtxToModule = @import("llvm.zig").addTaskCtxToModule;
const addB64SwizzleToModule = @import("llvm.zig").addB64SwizzleToModule;

/// build.zig lines 1213-1390.
pub fn buildNetTests(ctx: *BuildCtx) void {
    const b = ctx.b;
    const target = ctx.target;
    const optimize = ctx.optimize;
    const is_linux = ctx.is_linux;
    const repo_root_lazy = ctx.repo_root_lazy;
    const build_options = ctx.build_options;
    const sio_module = ctx.sio_module;
    const sa_net_primitives_module = ctx.sa_net_primitives_module;
    const sa_ws_stream_module = ctx.sa_ws_stream_module;
    const test_step = ctx.test_step;

    const sa_net_uring_module = b.createModule(.{
        .root_source_file = b.path("src/runtime/sa_net_uring.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    sa_net_uring_module.addImport("sio", sio_module);
    sa_net_uring_module.addOptions("build_options", build_options);
    sa_net_uring_module.addImport("sa_net_primitives", sa_net_primitives_module);
    sa_net_uring_module.addImport("sa_ws_stream", sa_ws_stream_module);
    if (target.result.os.tag == .linux) {
        // Unicode normalization (ICU) for sa_unicode_normalize, reached
        // through the sa_std.zig graph (same wiring as sa_std_unit_module).
        sa_net_uring_module.linkSystemLibrary("icuuc", .{});
        sa_net_uring_module.linkSystemLibrary("icudata", .{});
    }
    // NOTE: imports sa_std.zig (swizzle/pthread C shims); link them here too.
    addHostThreadShimToModule(b, sa_net_uring_module, target.result.os.tag);
    addB64SwizzleToModule(b, sa_net_uring_module);
    addTaskCtxToModule(b, sa_net_uring_module, target.result);
    const sa_net_uring_tests = b.addTest(.{
        .root_module = sa_net_uring_module,
    });
    const run_sa_net_uring_tests = b.addRunArtifact(sa_net_uring_tests);
    ctx.run_sa_net_uring_tests = run_sa_net_uring_tests;
    run_sa_net_uring_tests.setCwd(repo_root_lazy);
    if (is_linux) test_step.dependOn(&run_sa_net_uring_tests.step);
    const sa_net_uring_test_step = b.step("sa-net-uring-test", "Run io_uring network runtime tests");
    sa_net_uring_test_step.dependOn(&run_sa_net_uring_tests.step);
    const sa_http2_module = b.createModule(.{
        .root_source_file = b.path("src/runtime/sa_http2.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    sa_http2_module.addImport("sio", sio_module);
    sa_http2_module.addOptions("build_options", build_options);
    const sa_http2_tests = b.addTest(.{
        .root_module = sa_http2_module,
    });
    const run_sa_http2_tests = b.addRunArtifact(sa_http2_tests);
    ctx.run_sa_http2_tests = run_sa_http2_tests;
    run_sa_http2_tests.setCwd(repo_root_lazy);
    if (is_linux) test_step.dependOn(&run_sa_http2_tests.step);
    const sa_http2_test_step = b.step("sa-http2-test", "Run HTTP/2 (libnghttp2) runtime tests");
    sa_http2_test_step.dependOn(&run_sa_http2_tests.step);
    const sa_tls_server_module = b.createModule(.{
        .root_source_file = b.path("src/runtime/sa_tls_server.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    sa_tls_server_module.addImport("sio", sio_module);
    sa_tls_server_module.addOptions("build_options", build_options);
    const sa_tls_server_tests = b.addTest(.{
        .root_module = sa_tls_server_module,
    });
    const run_sa_tls_server_tests = b.addRunArtifact(sa_tls_server_tests);
    ctx.run_sa_tls_server_tests = run_sa_tls_server_tests;
    run_sa_tls_server_tests.setCwd(repo_root_lazy);
    if (is_linux) test_step.dependOn(&run_sa_tls_server_tests.step);
    const sa_tls_server_test_step = b.step("sa-tls-server-test", "Run TLS-server (OpenSSL) runtime tests");
    sa_tls_server_test_step.dependOn(&run_sa_tls_server_tests.step);
    const sa_tls_client_module = b.createModule(.{
        .root_source_file = b.path("src/runtime/sa_tls_client.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    sa_tls_client_module.addImport("sio", sio_module);
    sa_tls_client_module.addOptions("build_options", build_options);
    const sa_tls_client_tests = b.addTest(.{
        .root_module = sa_tls_client_module,
    });
    const run_sa_tls_client_tests = b.addRunArtifact(sa_tls_client_tests);
    ctx.run_sa_tls_client_tests = run_sa_tls_client_tests;
    run_sa_tls_client_tests.setCwd(repo_root_lazy);
    if (is_linux) test_step.dependOn(&run_sa_tls_client_tests.step);
    const sa_tls_client_test_step = b.step("sa-tls-client-test", "Run TLS-client (std.crypto.tls) runtime tests");
    sa_tls_client_test_step.dependOn(&run_sa_tls_client_tests.step);
    const sa_ws_client_module = b.createModule(.{
        .root_source_file = b.path("src/runtime/sa_ws_client.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    sa_ws_client_module.addImport("sio", sio_module);
    sa_ws_client_module.addOptions("build_options", build_options);
    sa_ws_client_module.addImport("sa_net_primitives", sa_net_primitives_module);
    const sa_ws_client_tests = b.addTest(.{
        .root_module = sa_ws_client_module,
    });
    const run_sa_ws_client_tests = b.addRunArtifact(sa_ws_client_tests);
    run_sa_ws_client_tests.setCwd(repo_root_lazy);
    if (is_linux) test_step.dependOn(&run_sa_ws_client_tests.step);
    const sa_ws_client_test_step = b.step("sa-ws-client-test", "Run WebSocket-client (pure Zig RFC 6455) runtime tests");
    sa_ws_client_test_step.dependOn(&run_sa_ws_client_tests.step);
    const sa_thread_local_module = b.createModule(.{
        .root_source_file = b.path("src/runtime/sa_thread_local.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    sa_thread_local_module.addImport("sio", sio_module);
    sa_thread_local_module.addOptions("build_options", build_options);
    const sa_thread_local_tests = b.addTest(.{
        .root_module = sa_thread_local_module,
    });
    const run_sa_thread_local_tests = b.addRunArtifact(sa_thread_local_tests);
    ctx.run_sa_thread_local_tests = run_sa_thread_local_tests;
    run_sa_thread_local_tests.setCwd(repo_root_lazy);
    if (is_linux) test_step.dependOn(&run_sa_thread_local_tests.step);
    const sa_thread_local_test_step = b.step("sa-thread-local-test", "Run thread-local storage runtime tests");
    sa_thread_local_test_step.dependOn(&run_sa_thread_local_tests.step);
    const sa_dtls_module = b.createModule(.{
        .root_source_file = b.path("src/runtime/sa_dtls.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    sa_dtls_module.addImport("sio", sio_module);
    sa_dtls_module.addOptions("build_options", build_options);
    const sa_dtls_tests = b.addTest(.{
        .root_module = sa_dtls_module,
    });
    const run_sa_dtls_tests = b.addRunArtifact(sa_dtls_tests);
    ctx.run_sa_dtls_tests = run_sa_dtls_tests;
    run_sa_dtls_tests.setCwd(repo_root_lazy);
    if (is_linux) test_step.dependOn(&run_sa_dtls_tests.step);
    const sa_dtls_test_step = b.step("sa-dtls-test", "Run DTLS (OpenSSL) runtime tests");
    sa_dtls_test_step.dependOn(&run_sa_dtls_tests.step);
    const sa_quic_module = b.createModule(.{
        .root_source_file = b.path("src/runtime/sa_quic.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    sa_quic_module.addImport("sio", sio_module);
    sa_quic_module.addOptions("build_options", build_options);
    const sa_quic_tests = b.addTest(.{
        .root_module = sa_quic_module,
    });
    const run_sa_quic_tests = b.addRunArtifact(sa_quic_tests);
    ctx.run_sa_quic_tests = run_sa_quic_tests;
    run_sa_quic_tests.setCwd(repo_root_lazy);
    if (is_linux) test_step.dependOn(&run_sa_quic_tests.step);
    const sa_quic_test_step = b.step("sa-quic-test", "Run QUIC/HTTP3 runtime capability tests");
    sa_quic_test_step.dependOn(&run_sa_quic_tests.step);

    const sa_term_runtime_module = b.createModule(.{
        .root_source_file = b.path("tests/sa_term_runtime.zig"),
        .target = target,
        .optimize = optimize,
        // NOTE: spawns subprocesses via sio.Child (live-env snapshot needs libc).
        .link_libc = true,
    });
    sa_term_runtime_module.addImport("sio", sio_module);
    sa_term_runtime_module.addOptions("build_options", build_options);
    const sa_term_runtime = b.addTest(.{
        .root_module = sa_term_runtime_module,
    });
    const run_sa_term_runtime = b.addRunArtifact(sa_term_runtime);
    ctx.run_sa_term_runtime = run_sa_term_runtime;
    run_sa_term_runtime.setCwd(repo_root_lazy);
    if (is_linux) test_step.dependOn(&run_sa_term_runtime.step);
    const sa_term_runtime_step = b.step("sa-term-runtime", "Run terminal runtime tests");
    sa_term_runtime_step.dependOn(&run_sa_term_runtime.step);

    const native_sys_runtime_module = b.createModule(.{
        .root_source_file = b.path("tests/native_sys_runtime.zig"),
        .target = target,
        .optimize = optimize,
        // NOTE: spawns subprocesses via sio.Child (live-env snapshot needs libc).
        .link_libc = true,
    });
    native_sys_runtime_module.addImport("sio", sio_module);
    native_sys_runtime_module.addOptions("build_options", build_options);
    const native_sys_runtime = b.addTest(.{
        .root_module = native_sys_runtime_module,
    });
    const run_native_sys_runtime = b.addRunArtifact(native_sys_runtime);
    ctx.run_native_sys_runtime = run_native_sys_runtime;
    run_native_sys_runtime.setCwd(repo_root_lazy);
    test_step.dependOn(&run_native_sys_runtime.step);
    const native_sys_runtime_step = b.step("native-sys-runtime", "Run native system runtime tests");
    native_sys_runtime_step.dependOn(&run_native_sys_runtime.step);
}
