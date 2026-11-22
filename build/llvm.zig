const std = @import("std");
const pathExists = @import("paths.zig").pathExists;

pub fn defaultLlvmIncludeDir(os_tag: std.Target.Os.Tag) []const u8 {
    return switch (os_tag) {
        .windows => "C:/LLVM-14/include",
        else => "/usr/lib/llvm-14/include",
    };
}

pub fn defaultLlvmLibDir(os_tag: std.Target.Os.Tag) []const u8 {
    return switch (os_tag) {
        .windows => "C:/LLVM-14/lib",
        else => "/usr/lib/llvm-14/lib",
    };
}

pub fn defaultLlvmLibName(os_tag: std.Target.Os.Tag) []const u8 {
    return switch (os_tag) {
        .windows => "LLVM-C",
        else => "LLVM-14",
    };
}

pub fn validateLlvmConfig(
    b: *std.Build,
    os_tag: std.Target.Os.Tag,
    enable_llvm: bool,
    include_dir: []const u8,
    lib_dir: []const u8,
    lib_name: []const u8,
) void {
    if (!enable_llvm) return;

    const io = b.graph.io;
    const core_header = std.fs.path.join(b.allocator, &.{ include_dir, "llvm-c", "Core.h" }) catch |err| {
        failLlvmConfig("failed to construct LLVM include path: {s}", .{@errorName(err)});
    };
    defer b.allocator.free(core_header);
    if (!pathExists(io, core_header)) {
        failLlvmConfig(
            "LLVM-C header not found: {s}\n  pass -Dllvm-include-dir=<path-to-llvm-include> or use -Dllvm=false for the bootstrap compiler",
            .{core_header},
        );
    }

    if (!pathExists(io, lib_dir)) {
        failLlvmConfig(
            "LLVM library directory not found: {s}\n  pass -Dllvm-lib-dir=<path-to-llvm-lib> or use -Dllvm=false for the bootstrap compiler",
            .{lib_dir},
        );
    }

    if (!llvmLibraryExists(b, os_tag, lib_dir, lib_name)) {
        switch (os_tag) {
            .windows => failLlvmConfig(
                "LLVM import library not found in {s} for -Dllvm-lib-name={s}\n  checked common Windows candidates such as {s}.lib and lib{s}.dll.a\n  use the library name provided by your LLVM package, for example -Dllvm-lib-name=LLVM-C or -Dllvm-lib-name=LLVM, or use -Dllvm=false for the bootstrap compiler",
                .{ lib_dir, lib_name, lib_name, lib_name },
            ),
            .linux => failLlvmConfig(
                "LLVM library not found in {s} for -Dllvm-lib-name={s}\n  Linux defaults expect LLVM 14 at /usr/lib/llvm-14; pass explicit LLVM paths or use -Dllvm=false for the bootstrap compiler",
                .{ lib_dir, lib_name },
            ),
            else => failLlvmConfig(
                "LLVM library not found in {s} for -Dllvm-lib-name={s}\n  pass explicit LLVM paths for this target or use -Dllvm=false for the bootstrap compiler",
                .{ lib_dir, lib_name },
            ),
        }
    }
}

pub fn failLlvmConfig(comptime fmt: []const u8, args: anytype) noreturn {
    std.debug.print("error: LLVM-C backend configuration failed\n  " ++ fmt ++ "\n", args);
    std.process.exit(1);
}

pub fn llvmLibraryExists(b: *std.Build, os_tag: std.Target.Os.Tag, lib_dir: []const u8, lib_name: []const u8) bool {
    const candidates = [_][]const u8{
        lib_name,
        b.fmt("{s}.lib", .{lib_name}),
        b.fmt("lib{s}.dll.a", .{lib_name}),
        b.fmt("lib{s}.a", .{lib_name}),
        b.fmt("lib{s}.so", .{lib_name}),
        b.fmt("lib{s}.dylib", .{lib_name}),
    };

    for (candidates) |candidate| {
        if (!llvmLibraryCandidateApplies(os_tag, candidate)) continue;
        const path = std.fs.path.join(b.allocator, &.{ lib_dir, candidate }) catch continue;
        defer b.allocator.free(path);
        if (!pathExists(b.graph.io, path)) continue;
        return true;
    }
    if (os_tag == .linux or os_tag == .macos) {
        if (versionedSharedLibraryExists(b.allocator, b.graph.io, os_tag, lib_dir, lib_name)) return true;
    }
    return false;
}

pub fn versionedSharedLibraryExists(allocator: std.mem.Allocator, io: std.Io, os_tag: std.Target.Os.Tag, lib_dir: []const u8, lib_name: []const u8) bool {
    var dir = if (std.fs.path.isAbsolute(lib_dir))
        std.Io.Dir.openDirAbsolute(io, lib_dir, .{ .iterate = true }) catch return false
    else
        std.Io.Dir.cwd().openDir(io, lib_dir, .{ .iterate = true }) catch return false;
    defer dir.close(io);
    const prefix = switch (os_tag) {
        .linux => std.fmt.allocPrint(allocator, "lib{s}.so.", .{lib_name}) catch return false,
        .macos => std.fmt.allocPrint(allocator, "lib{s}.", .{lib_name}) catch return false,
        else => return false,
    };
    defer allocator.free(prefix);
    var it = dir.iterate();
    while (it.next(io) catch null) |entry| {
        if (entry.kind == .file or entry.kind == .sym_link) {
            if (std.mem.startsWith(u8, entry.name, prefix)) return true;
        }
    }
    return false;
}

pub fn llvmLibraryCandidateApplies(os_tag: std.Target.Os.Tag, candidate: []const u8) bool {
    return switch (os_tag) {
        .windows => std.mem.endsWith(u8, candidate, ".lib") or std.mem.endsWith(u8, candidate, ".dll.a") or !std.mem.containsAtLeast(u8, candidate, 1, "."),
        .linux => std.mem.endsWith(u8, candidate, ".so") or std.mem.endsWith(u8, candidate, ".a") or !std.mem.containsAtLeast(u8, candidate, 1, "."),
        .macos => std.mem.endsWith(u8, candidate, ".dylib") or std.mem.endsWith(u8, candidate, ".a") or !std.mem.containsAtLeast(u8, candidate, 1, "."),
        else => true,
    };
}

pub fn addLlvmcSupportToModule(
    b: *std.Build,
    module: *std.Build.Module,
    enable_llvm: bool,
    include_dir: []const u8,
    lib_dir: []const u8,
    lib_name: []const u8,
) void {
    if (enable_llvm) {
        module.addCSourceFile(.{ .file = b.path("src/emit_llvm_llvmc_shim.c"), .flags = &.{} });
        // DEF-RF-DSE: hand-written release pipeline (PMB transcription minus
        // DSE) lives in C++ -- the legacy C API cannot express several of
        // its passes/options (threshold inliner, SimplifyCFG options, AA
        // wrappers). The one stdlib-crossing factory is bridged inside the
        // TU itself (see emit_llvm_pipeline.cpp), so a plain libc++ link is
        // all the build needs.
        module.addCSourceFile(.{ .file = b.path("src/emit_llvm_pipeline.cpp"), .flags = &.{"-std=c++17"} });
        module.link_libcpp = true;
        linkLLVMToModule(module, include_dir, lib_dir, lib_name);
    } else {
        module.addCSourceFile(.{ .file = b.path("src/emit_llvm_llvmc_stub.c"), .flags = &.{"-fno-sanitize=all"} });
    }
}

pub fn addHostThreadShimToModule(b: *std.Build, module: *std.Build.Module, os_tag: std.Target.Os.Tag) void {
    switch (os_tag) {
        .windows => {},
        else => module.addCSourceFile(.{ .file = b.path("src/runtime/sa_pthread_host.c"), .flags = &.{"-fno-sanitize=all"} }),
    }
}

pub fn addTaskCtxToModule(b: *std.Build, module: *std.Build.Module, target: std.Target) void {
    // Goroutine context primitives (sa_task_ctx.s) exist only for
    // x86_64 Linux in this phase (goroutine scope ruling S5);
    // sa_task reports UNSUPPORTED on other targets and its code
    // paths to these symbols are not exercised there.
    if (target.cpu.arch == .x86_64 and target.os.tag == .linux) {
        module.addAssemblyFile(b.path("src/runtime/sa_task_ctx.s"));
    }
}

pub fn addB64SwizzleToModule(b: *std.Build, module: *std.Build.Module) void {
    // AVX2 base64 kernel with Apache-2.0 attribution in-file; non-x86_64
    // compiles to stubs (Zig falls back to the portable Mula path), so
    // this is unconditional and needs no per-file -mavx2 flag (the kernel
    // carries function-level target("avx2") attributes instead).
    module.addCSourceFile(.{ .file = b.path("src/runtime/sa_b64_swizzle.c"), .flags = &.{"-fno-sanitize=all"} });
}

pub fn linkLLVMToModule(module: *std.Build.Module, include_dir: []const u8, lib_dir: []const u8, lib_name: []const u8) void {
    module.addSystemIncludePath(.{ .cwd_relative = include_dir });
    module.addLibraryPath(.{ .cwd_relative = lib_dir });
    module.linkSystemLibrary(lib_name, .{});
}

pub fn linkLLVMToCompile(compile: *std.Build.Step.Compile, enable_llvm: bool, include_dir: []const u8, lib_dir: []const u8, lib_name: []const u8) void {
    if (!enable_llvm) return;
    compile.root_module.addSystemIncludePath(.{ .cwd_relative = include_dir });
    compile.root_module.addLibraryPath(.{ .cwd_relative = lib_dir });
    compile.root_module.linkSystemLibrary(lib_name, .{});
}

pub fn addLlvmBinDirToRun(
    b: *std.Build,
    run: *std.Build.Step.Run,
    enable_llvm: bool,
    lib_dir: []const u8,
    os_tag: std.Target.Os.Tag,
) void {
    if (!enable_llvm or os_tag != .windows) return;
    const llvm_root_dir = std.fs.path.dirname(lib_dir) orelse lib_dir;
    // NOTE(Zig 0.17): Step.Run.addPathDir was removed; prepend via PATH instead.
    const llvm_bin = b.pathJoin(&.{ llvm_root_dir, "bin" });
    const prev_path = b.graph.environ_map.get("PATH") orelse "";
    const new_path = if (prev_path.len == 0) llvm_bin else b.fmt("{s};{s}", .{ llvm_bin, prev_path });
    run.setEnvironmentVariable("PATH", new_path);
}

/// On Windows, `sa.exe` is linked against the LLVM-C import library but the
/// runtime DLL lives in `<llvm-lib-dir-父>/bin/LLVM-C.dll`. Without it next to
/// the executable the binary fails to start in any environment that does not
/// already have that LLVM install on PATH (e.g. a fresh clone, the distributable
/// zip produced by `tools/make_windows_dist.bat`, or CI). This step installs the
/// DLL alongside `sa.exe` so the install prefix is self-contained.
pub fn installLlvmCDll(
    b: *std.Build,
    lib_dir: []const u8,
    os_tag: std.Target.Os.Tag,
) void {
    if (os_tag != .windows) return;
    const llvm_root_dir = std.fs.path.dirname(lib_dir) orelse lib_dir;
    const dll_path = b.pathJoin(&.{ llvm_root_dir, "bin", "LLVM-C.dll" });
    const install_dll = b.addInstallBinFile(.{ .cwd_relative = dll_path }, "LLVM-C.dll");
    b.getInstallStep().dependOn(&install_dll.step);
}

pub fn linkWindowsNetworkingToCompile(compile: *std.Build.Step.Compile, os_tag: std.Target.Os.Tag) void {
    if (os_tag != .windows) return;
    compile.root_module.linkSystemLibrary("ws2_32", .{});
    compile.root_module.linkSystemLibrary("iphlpapi", .{});
}
