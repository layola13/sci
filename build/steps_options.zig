const BuildCtx = @import("ctx.zig").BuildCtx;
const latestGitTag = @import("version.zig").latestGitTag;
const pathFromRoot = @import("paths.zig").pathFromRoot;
const targetSaStdArchivePath = @import("paths.zig").targetSaStdArchivePath;
const targetSaStdRoot = @import("paths.zig").targetSaStdRoot;
const defaultLlvmIncludeDir = @import("llvm.zig").defaultLlvmIncludeDir;
const defaultLlvmLibDir = @import("llvm.zig").defaultLlvmLibDir;
const defaultLlvmLibName = @import("llvm.zig").defaultLlvmLibName;
const validateLlvmConfig = @import("llvm.zig").validateLlvmConfig;

/// build.zig lines 48-108.
pub fn buildOptions(ctx: *BuildCtx) void {
    const b = ctx.b;

    const target = b.standardTargetOptions(.{});
    ctx.target = target;
    // NOTE(Zig 0.17): the global `b.sysroot` / `b.libc_file` overrides were
    // removed from std.Build, and Zig 0.17 bundles FreeBSD libc, so the old
    // -Dsysroot/-Dlibc cross-compilation options are obsolete. Plain
    // `-Dtarget=<triple>` now works (see tools/build_freebsd.sh).
    const is_windows = target.result.os.tag == .windows;
    ctx.is_windows = is_windows;
    const is_linux = target.result.os.tag == .linux;
    ctx.is_linux = is_linux;
    const release_safe = b.option(bool, "release-safe", "Build all artifacts with ReleaseSafe optimization.") orelse false;
    const release_small = b.option(bool, "release-small", "Build all artifacts with ReleaseSmall optimization.") orelse false;
    const enable_llvm_default = target.result.os.tag != .windows;
    const enable_llvm = b.option(bool, "llvm", "Enable LLVM-C native backend integration.") orelse enable_llvm_default;
    ctx.enable_llvm = enable_llvm;
    const version = b.option([]const u8, "version", "SA toolchain semantic version.") orelse latestGitTag(b.allocator, b.graph.io) orelse "0.0.1";
    const llvm_include_dir = b.option([]const u8, "llvm-include-dir", "LLVM C API include directory.") orelse defaultLlvmIncludeDir(target.result.os.tag);
    ctx.llvm_include_dir = llvm_include_dir;
    const llvm_lib_dir = b.option([]const u8, "llvm-lib-dir", "LLVM library directory.") orelse defaultLlvmLibDir(target.result.os.tag);
    ctx.llvm_lib_dir = llvm_lib_dir;
    const llvm_lib_name = b.option([]const u8, "llvm-lib-name", "LLVM system library name.") orelse defaultLlvmLibName(target.result.os.tag);
    ctx.llvm_lib_name = llvm_lib_name;
    const llvmc_test_filter = b.option([]const u8, "llvmc-test-filter", "Run only LLVM-C tests whose names contain this text.");
    ctx.llvmc_test_filter = llvmc_test_filter;
    var optimize = b.standardOptimizeOption(.{});
    if (release_safe) optimize = .ReleaseSafe;
    if (release_small) optimize = .ReleaseSmall;
    ctx.optimize = optimize;
    const repo_root = pathFromRoot(b, ".");
    const repo_root_lazy = b.path(".");
    ctx.repo_root_lazy = repo_root_lazy;
    const build_options = b.addOptions();
    ctx.build_options = build_options;
    const test_build_options = b.addOptions();
    ctx.test_build_options = test_build_options;
    // NOTE(Zig 0.17): modules are rooted at their root_source_file's directory,
    // so cross-directory `@import("../...")` is rejected ("import of file
    // outside module path"). The I/O compat layer is therefore exposed as the
    // named import "sio" (source: src/sa_io.zig); every module below registers
    // it via `addImport("sio", sio_module)` and sources use
    // `const sio = @import("sio");`.
    const sio_module = b.createModule(.{
        .root_source_file = b.path("src/sa_io.zig"),
        .target = target,
        .optimize = optimize,
    });
    ctx.sio_module = sio_module;
    // The net primitives and the WebSocket stream layer are shared by the
    // HTTP client/server cores, the WS client and the io_uring layer. Like
    // "sio" above they are exposed as named imports: as plain relative
    // imports the same file would land in two modules whenever a consumer
    // (e.g. a plugin) compiles the client and server cores side by side,
    // which Zig rejects ("file exists in modules ...").
    const sa_net_primitives_module = b.createModule(.{
        .root_source_file = b.path("src/runtime/sa_net_primitives.zig"),
        .target = target,
        .optimize = optimize,
    });
    ctx.sa_net_primitives_module = sa_net_primitives_module;
    const sa_ws_stream_module = b.createModule(.{
        .root_source_file = b.path("src/runtime/sa_ws_stream.zig"),
        .target = target,
        .optimize = optimize,
    });
    ctx.sa_ws_stream_module = sa_ws_stream_module;
    sa_ws_stream_module.addImport("sa_net_primitives", sa_net_primitives_module);

    const sa_std_archive_rel = targetSaStdArchivePath(target.result.os.tag);
    const sa_std_root = targetSaStdRoot(target.result.os.tag);
    ctx.sa_std_root = sa_std_root;
    validateLlvmConfig(b, target.result.os.tag, enable_llvm, llvm_include_dir, llvm_lib_dir, llvm_lib_name);
    build_options.addOption([]const u8, "sa_std_archive_path", pathFromRoot(b, sa_std_archive_rel));
    build_options.addOption(bool, "llvm_enabled", enable_llvm);
    build_options.addOption([]const u8, "repo_root", repo_root);
    build_options.addOption([]const u8, "version", version);
    test_build_options.addOption([]const u8, "repo_root", repo_root);
}
