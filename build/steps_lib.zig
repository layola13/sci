const BuildCtx = @import("ctx.zig").BuildCtx;
const addLlvmcSupportToModule = @import("llvm.zig").addLlvmcSupportToModule;
const addHostThreadShimToModule = @import("llvm.zig").addHostThreadShimToModule;
const addTaskCtxToModule = @import("llvm.zig").addTaskCtxToModule;
const addB64SwizzleToModule = @import("llvm.zig").addB64SwizzleToModule;

/// build.zig lines 109-134.
pub fn buildLib(ctx: *BuildCtx) void {
    const b = ctx.b;
    const target = ctx.target;
    const optimize = ctx.optimize;
    const enable_llvm = ctx.enable_llvm;
    const llvm_include_dir = ctx.llvm_include_dir;
    const llvm_lib_dir = ctx.llvm_lib_dir;
    const llvm_lib_name = ctx.llvm_lib_name;
    const build_options = ctx.build_options;
    const sio_module = ctx.sio_module;
    const sa_net_primitives_module = ctx.sa_net_primitives_module;
    const sa_ws_stream_module = ctx.sa_ws_stream_module;

    const lib_module = b.createModule(.{
        .root_source_file = b.path("src/lib.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    ctx.lib_module = lib_module;
    lib_module.addImport("sio", sio_module);
    lib_module.addImport("sa_net_primitives", sa_net_primitives_module);
    lib_module.addImport("sa_ws_stream", sa_ws_stream_module);
    addLlvmcSupportToModule(b, lib_module, enable_llvm, llvm_include_dir, llvm_lib_dir, llvm_lib_name);
    lib_module.addOptions("build_options", build_options);
    // NOTE: lib re-exports runtime/sa_std.zig (swizzle/pthread C shims).
    addHostThreadShimToModule(b, lib_module, target.result.os.tag);
    addB64SwizzleToModule(b, lib_module);
    addTaskCtxToModule(b, lib_module, target.result);
    if (target.result.os.tag == .linux) {
        lib_module.linkSystemLibrary("dl", .{});
    }

    const lib = b.addLibrary(.{
        .name = "sa_asm",
        .root_module = lib_module,
        .linkage = .static,
    });
    b.installArtifact(lib);
}
