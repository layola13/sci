const BuildCtx = @import("ctx.zig").BuildCtx;
const targetSaStdSyncPath = @import("paths.zig").targetSaStdSyncPath;
const addHostThreadShimToModule = @import("llvm.zig").addHostThreadShimToModule;
const addTaskCtxToModule = @import("llvm.zig").addTaskCtxToModule;
const addB64SwizzleToModule = @import("llvm.zig").addB64SwizzleToModule;

/// build.zig lines 135-220.
pub fn buildSaStd(ctx: *BuildCtx) void {
    const b = ctx.b;
    const target = ctx.target;
    const optimize = ctx.optimize;
    const sio_module = ctx.sio_module;
    const sa_net_primitives_module = ctx.sa_net_primitives_module;
    const sa_ws_stream_module = ctx.sa_ws_stream_module;
    const sa_std_root = ctx.sa_std_root;

    const sa_std_static_module = b.createModule(.{
        .root_source_file = b.path(sa_std_root),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
        // The wasm sa_std archive is a single 8009-function object built in
        // Debug mode; ~4.4 MB (32%) of its 14 MB is DWARF that consumers never
        // use (a program's own debug info lives in its .sa.bc, emitted
        // separately). Stripping at build time keeps the runtime object small
        // so `sa build-wasm`'s link step does not have to parse/relocate it.
        // Native archives keep debug info for debugger-friendly dev builds.
        .strip = if (target.result.os.tag == .wasi) true else null,
    });
    sa_std_static_module.addImport("sio", sio_module);
    sa_std_static_module.addImport("sa_net_primitives", sa_net_primitives_module);
    sa_std_static_module.addImport("sa_ws_stream", sa_ws_stream_module);
    addHostThreadShimToModule(b, sa_std_static_module, target.result.os.tag);
    addB64SwizzleToModule(b, sa_std_static_module);
    addTaskCtxToModule(b, sa_std_static_module, target.result);
    if (target.result.os.tag == .linux) {
        // Unicode normalization (ICU) for sa_unicode_normalize.
        sa_std_static_module.linkSystemLibrary("icuuc", .{});
        sa_std_static_module.linkSystemLibrary("icudata", .{});
    }
    const sa_std_static = b.addLibrary(.{
        .name = "sa_std",
        .root_module = sa_std_static_module,
        .linkage = .static,
    });
    ctx.sa_std_static = sa_std_static;
    // The runtime compiles as a single compilation-unit object; without
    // per-function/per-data sections, one anchor reference (every program
    // main calls sa_install_sigpipe_ignore) forces the linker to take the
    // entire runtime object into every executable. Section splitting lets
    // --gc-sections executable links keep only the reachable runtime.
    sa_std_static.link_function_sections = true;
    sa_std_static.link_data_sections = true;
    const install_sa_std_static = b.addInstallArtifact(sa_std_static, .{});
    ctx.install_sa_std_static = install_sa_std_static;
    const sync_sa_std_artifact = b.addUpdateSourceFiles();
    ctx.sync_sa_std_artifact = sync_sa_std_artifact;
    sync_sa_std_artifact.addCopyFileToSource(sa_std_static.getEmittedBin(), targetSaStdSyncPath(b, target));

    const sa_std_shared_module = b.createModule(.{
        .root_source_file = b.path(sa_std_root),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    sa_std_shared_module.addImport("sio", sio_module);
    sa_std_shared_module.addImport("sa_net_primitives", sa_net_primitives_module);
    sa_std_shared_module.addImport("sa_ws_stream", sa_ws_stream_module);
    addHostThreadShimToModule(b, sa_std_shared_module, target.result.os.tag);
    addB64SwizzleToModule(b, sa_std_shared_module);
    addTaskCtxToModule(b, sa_std_shared_module, target.result);
    if (target.result.os.tag == .linux) {
        // Unicode normalization (ICU) for sa_unicode_normalize.
        sa_std_shared_module.linkSystemLibrary("icuuc", .{});
        sa_std_shared_module.linkSystemLibrary("icudata", .{});
    }
    const sa_std_shared = b.addLibrary(.{
        .name = "sa_std",
        .root_module = sa_std_shared_module,
        .linkage = .dynamic,
    });
    const install_sa_std_shared = b.addInstallArtifact(sa_std_shared, .{});

    const install_sa_std_header = b.addInstallHeaderFile(b.path("src/runtime/sa_std.h"), "sa_std.h");
    ctx.install_sa_std_header = install_sa_std_header;
    // Install the static runtime and public header for both supported hosts.
    // Windows is a bootstrap runtime today, but its .lib is still required by
    // native build-exe and release packaging. The shared runtime remains a
    // Linux artifact until the Windows DLL ABI is promoted beyond bootstrap.
    b.getInstallStep().dependOn(&install_sa_std_static.step);
    b.getInstallStep().dependOn(&sync_sa_std_artifact.step);
    b.getInstallStep().dependOn(&install_sa_std_header.step);
    if (target.result.os.tag != .windows) {
        b.getInstallStep().dependOn(&install_sa_std_shared.step);
    }

    const sa_std_static_step = b.step("sa-std-static", "Build and install the static SA standard runtime library");
    sa_std_static_step.dependOn(&install_sa_std_static.step);
    sa_std_static_step.dependOn(&sync_sa_std_artifact.step);
    sa_std_static_step.dependOn(&install_sa_std_header.step);

    const sa_std_shared_step = b.step("sa-std-shared", "Build and install the shared SA standard runtime library");
    sa_std_shared_step.dependOn(&install_sa_std_shared.step);
    sa_std_shared_step.dependOn(&install_sa_std_header.step);

    const test_step = b.step("test", "Run unit tests");
    ctx.test_step = test_step;
}
