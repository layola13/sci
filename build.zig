const std = @import("std");

const LlvmSettings = struct {
    include_dir: []const u8,
    lib_dir: []const u8,
    lib_name: []const u8,
};

fn environmentValue(allocator: std.mem.Allocator, name: []const u8) ?[]const u8 {
    return std.process.getEnvVarOwned(allocator, name) catch null;
}

fn llvmLibraryName(allocator: std.mem.Allocator, filename: []const u8) ?[]const u8 {
    var name = std.fs.path.basename(filename);
    if (std.mem.startsWith(u8, name, "lib")) name = name[3..];
    const suffixes = [_][]const u8{ ".so", ".dylib", ".dll", ".lib", ".a" };
    for (suffixes) |suffix| {
        if (std.mem.indexOf(u8, name, suffix)) |index| {
            name = name[0..index];
            break;
        }
    }
    if (name.len == 0) return null;
    return allocator.dupe(u8, name) catch null;
}

fn queryLlvmConfig(allocator: std.mem.Allocator, executable: []const u8) ?LlvmSettings {
    const result = std.process.Child.run(.{
        .allocator = allocator,
        .argv = &.{ executable, "--includedir", "--libdir", "--link-shared", "--libnames" },
    }) catch return null;
    defer allocator.free(result.stdout);
    defer allocator.free(result.stderr);

    switch (result.term) {
        .Exited => |code| if (code != 0) return null,
        else => return null,
    }

    var lines = std.mem.tokenizeAny(u8, result.stdout, "\r\n");
    const include_dir = lines.next() orelse return null;
    const lib_dir = lines.next() orelse return null;
    const lib_names = lines.next() orelse return null;
    var names = std.mem.tokenizeAny(u8, lib_names, " \t");
    const lib_name = llvmLibraryName(allocator, names.next() orelse return null) orelse return null;
    return .{
        .include_dir = allocator.dupe(u8, include_dir) catch return null,
        .lib_dir = allocator.dupe(u8, lib_dir) catch return null,
        .lib_name = lib_name,
    };
}

fn discoverLlvm(b: *std.Build, target: std.Build.ResolvedTarget) LlvmSettings {
    const option_include = b.option([]const u8, "llvm-include-dir", "LLVM C API include directory.");
    const option_lib = b.option([]const u8, "llvm-lib-dir", "LLVM library directory.");
    const option_name = b.option([]const u8, "llvm-lib-name", "LLVM system library name.");
    const env_include = environmentValue(b.allocator, "LLVM_INCLUDE_DIR");
    const env_lib = environmentValue(b.allocator, "LLVM_LIB_DIR");
    const env_name = environmentValue(b.allocator, "LLVM_LIB_NAME");

    var detected: ?LlvmSettings = null;
    if (environmentValue(b.allocator, "LLVM_CONFIG")) |llvm_config| {
        detected = queryLlvmConfig(b.allocator, llvm_config);
    } else if (target.result.os.tag == b.graph.host.result.os.tag and
        target.result.cpu.arch == b.graph.host.result.cpu.arch)
    {
        const candidates = [_][]const u8{
            "llvm-config",
            "llvm-config-20",
            "llvm-config-19",
            "llvm-config-18",
            "llvm-config-17",
            "llvm-config-16",
            "llvm-config-15",
            "llvm-config-14",
        };
        for (candidates) |candidate| {
            detected = queryLlvmConfig(b.allocator, candidate);
            if (detected != null) break;
        }
    }

    const fallback: LlvmSettings = switch (target.result.os.tag) {
        .macos => if (target.result.cpu.arch == .aarch64) .{
            .include_dir = "/opt/homebrew/opt/llvm/include",
            .lib_dir = "/opt/homebrew/opt/llvm/lib",
            .lib_name = "LLVM",
        } else .{
            .include_dir = "/usr/local/opt/llvm/include",
            .lib_dir = "/usr/local/opt/llvm/lib",
            .lib_name = "LLVM",
        },
        .windows => .{
            .include_dir = "C:\\Program Files\\LLVM\\include",
            .lib_dir = "C:\\Program Files\\LLVM\\lib",
            .lib_name = "LLVM-C",
        },
        else => .{
            .include_dir = "/usr/lib/llvm-14/include",
            .lib_dir = "/usr/lib/llvm-14/lib",
            .lib_name = "LLVM-14",
        },
    };
    return .{
        .include_dir = option_include orelse env_include orelse if (detected) |settings| settings.include_dir else fallback.include_dir,
        .lib_dir = option_lib orelse env_lib orelse if (detected) |settings| settings.lib_dir else fallback.lib_dir,
        .lib_name = option_name orelse env_name orelse if (detected) |settings| settings.lib_name else fallback.lib_name,
    };
}

fn latestGitTag(allocator: std.mem.Allocator) ?[]const u8 {
    const argv = [_][]const u8{ "git", "tag", "--sort=-v:refname" };
    const result = std.process.Child.run(.{
        .allocator = allocator,
        .argv = argv[0..],
    }) catch return null;
    defer allocator.free(result.stderr);

    switch (result.term) {
        .Exited => |code| if (code != 0) {
            allocator.free(result.stdout);
            return null;
        },
        else => {
            allocator.free(result.stdout);
            return null;
        },
    }

    const trimmed = std.mem.trim(u8, result.stdout, " \t\r\n");
    if (trimmed.len == 0) {
        allocator.free(result.stdout);
        return null;
    }
    const first_line = if (std.mem.indexOfScalar(u8, trimmed, '\n')) |idx| trimmed[0..idx] else trimmed;
    const owned = allocator.dupe(u8, first_line) catch {
        allocator.free(result.stdout);
        return null;
    };
    allocator.free(result.stdout);
    return owned;
}

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const release_safe = b.option(bool, "release-safe", "Build all artifacts with ReleaseSafe optimization.") orelse false;
    const release_small = b.option(bool, "release-small", "Build all artifacts with ReleaseSmall optimization.") orelse false;
    const version = b.option([]const u8, "version", "SA toolchain semantic version.") orelse latestGitTag(b.allocator) orelse "0.0.1";
    const llvm = discoverLlvm(b, target);
    var optimize = b.standardOptimizeOption(.{});
    if (release_safe) optimize = .ReleaseSafe;
    if (release_small) optimize = .ReleaseSmall;
    const repo_root = b.pathFromRoot(".");
    const repo_root_lazy = b.path(".");
    const build_options = b.addOptions();
    const portable_build_options = b.addOptions();
    const test_build_options = b.addOptions();
    build_options.addOption([]const u8, "repo_root", repo_root);
    build_options.addOption([]const u8, "version", version);
    portable_build_options.addOption([]const u8, "repo_root", repo_root);
    portable_build_options.addOption([]const u8, "version", version);
    test_build_options.addOption([]const u8, "repo_root", repo_root);

    const lib_module = b.createModule(.{
        .root_source_file = b.path("src/lib.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    addLlvmcShimToModule(b, lib_module);
    linkLLVMToModule(lib_module, llvm.include_dir, llvm.lib_dir, llvm.lib_name);
    lib_module.addOptions("build_options", build_options);
    if (target.result.os.tag == .linux) {
        lib_module.linkSystemLibrary("dl", .{});
    }

    const lib = b.addLibrary(.{
        .name = "sa_asm",
        .root_module = lib_module,
        .linkage = .static,
    });
    b.installArtifact(lib);

    const sa_std_static_module = b.createModule(.{
        .root_source_file = b.path("src/runtime/sa_std.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    addPthreadHostShimToModule(b, sa_std_static_module, target.result.os.tag);
    const sa_std_static = b.addLibrary(.{
        .name = "sa_std",
        .root_module = sa_std_static_module,
        .linkage = .static,
    });
    build_options.addOptionPath("test_sa_std_archive_path", sa_std_static.getEmittedBin());
    const install_sa_std_static = b.addInstallArtifact(sa_std_static, .{});
    b.getInstallStep().dependOn(&install_sa_std_static.step);
    const sa_std_shared_module = b.createModule(.{
        .root_source_file = b.path("src/runtime/sa_std.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    addPthreadHostShimToModule(b, sa_std_shared_module, target.result.os.tag);
    const sa_std_shared = b.addLibrary(.{
        .name = "sa_std",
        .root_module = sa_std_shared_module,
        .linkage = .dynamic,
    });
    const install_sa_std_shared = b.addInstallArtifact(sa_std_shared, .{});
    b.getInstallStep().dependOn(&install_sa_std_shared.step);

    const install_sa_std_header = b.addInstallHeaderFile(b.path("src/runtime/sa_std.h"), "sa_std.h");
    b.getInstallStep().dependOn(&install_sa_std_header.step);

    const sa_std_static_step = b.step("sa-std-static", "Build and install the static SA standard runtime library");
    sa_std_static_step.dependOn(&install_sa_std_static.step);
    sa_std_static_step.dependOn(&install_sa_std_header.step);

    const sa_std_shared_step = b.step("sa-std-shared", "Build and install the shared SA standard runtime library");
    sa_std_shared_step.dependOn(&install_sa_std_shared.step);
    sa_std_shared_step.dependOn(&install_sa_std_header.step);

    const test_step = b.step("test", "Run unit tests");

    const sa_std_abi_contract = b.addSystemCommand(&.{
        b.graph.zig_exe,
        "test",
        "tests/sa_std_abi.zig",
    });
    sa_std_abi_contract.setCwd(repo_root_lazy);
    test_step.dependOn(&sa_std_abi_contract.step);
    const sa_std_abi_layout = b.addSystemCommand(&.{
        b.graph.zig_exe,
        "test",
        "-I",
        "src/runtime",
        "-lc",
        "tests/sa_std_abi_layout.zig",
    });
    sa_std_abi_layout.setCwd(repo_root_lazy);
    test_step.dependOn(&sa_std_abi_layout.step);
    const sa_std_artifact_abi_unit = b.addSystemCommand(&.{
        b.graph.zig_exe,
        "test",
        "tests/sa_std_artifact_abi.zig",
    });
    sa_std_artifact_abi_unit.setCwd(repo_root_lazy);
    test_step.dependOn(&sa_std_artifact_abi_unit.step);

    const sa_std_abi_step = b.step("sa-std-abi", "Check SA runtime source and data-layout ABI contracts");
    sa_std_abi_step.dependOn(&sa_std_abi_contract.step);
    sa_std_abi_step.dependOn(&sa_std_abi_layout.step);
    sa_std_abi_step.dependOn(&sa_std_artifact_abi_unit.step);

    for ([_][]const u8{ "x86_64-macos", "x86_64-windows-gnu" }) |abi_target| {
        const abi_layout_typecheck = b.addSystemCommand(&.{
            b.graph.zig_exe,
            "test",
            "-target",
            abi_target,
            "-I",
            "src/runtime",
            "-lc",
            "-fno-emit-bin",
            "tests/sa_std_abi_layout.zig",
        });
        abi_layout_typecheck.setCwd(repo_root_lazy);
        sa_std_abi_step.dependOn(&abi_layout_typecheck.step);
        test_step.dependOn(&abi_layout_typecheck.step);
    }

    for ([_][]const u8{ "x86_64-linux-gnu", "x86_64-macos", "x86_64-windows-gnu" }) |abi_target| {
        const abi_header_typecheck = b.addSystemCommand(&.{
            b.graph.zig_exe,
            "cc",
            "-target",
            abi_target,
            "-I",
            "src/runtime",
            "-std=c11",
            "-c",
        });
        abi_header_typecheck.addFileArg(b.path("tests/abi/sa_std_header_smoke.c"));
        abi_header_typecheck.addArg("-o");
        _ = abi_header_typecheck.addOutputFileArg(b.fmt("sa_std_header_smoke-{s}.o", .{abi_target}));
        abi_header_typecheck.setCwd(repo_root_lazy);
        sa_std_abi_step.dependOn(&abi_header_typecheck.step);
        test_step.dependOn(&abi_header_typecheck.step);
    }

    const abi_nm = b.option([]const u8, "abi-nm", "nm-compatible symbol reader for the sa_std artifact ABI gate") orelse
        environmentValue(b.allocator, "LLVM_NM") orelse
        environmentValue(b.allocator, "NM") orelse
        "nm";
    const abi_checker_module = b.createModule(.{
        .root_source_file = b.path("tests/sa_std_artifact_abi.zig"),
        .target = b.graph.host,
        .optimize = .ReleaseSafe,
    });
    const abi_checker = b.addExecutable(.{
        .name = "sa_std_artifact_abi_check",
        .root_module = abi_checker_module,
    });

    const abi_linux_target = b.resolveTargetQuery(.{
        .cpu_arch = .x86_64,
        .os_tag = .linux,
        .abi = .gnu,
    });
    const abi_linux_static_module = b.createModule(.{
        .root_source_file = b.path("src/runtime/sa_std.zig"),
        .target = abi_linux_target,
        .optimize = optimize,
        .link_libc = true,
    });
    addPthreadHostShimToModule(b, abi_linux_static_module, .linux);
    const abi_linux_static = b.addLibrary(.{
        .name = "sa_std_abi_linux",
        .root_module = abi_linux_static_module,
        .linkage = .static,
    });

    const abi_linux_shared_module = b.createModule(.{
        .root_source_file = b.path("src/runtime/sa_std.zig"),
        .target = abi_linux_target,
        .optimize = optimize,
        .link_libc = true,
    });
    addPthreadHostShimToModule(b, abi_linux_shared_module, .linux);
    const abi_linux_shared = b.addLibrary(.{
        .name = "sa_std_abi_linux",
        .root_module = abi_linux_shared_module,
        .linkage = .dynamic,
    });

    const abi_windows_target = b.resolveTargetQuery(.{
        .cpu_arch = .x86_64,
        .os_tag = .windows,
        .abi = .gnu,
    });
    const abi_windows_module = b.createModule(.{
        .root_source_file = b.path("src/runtime/sa_std.zig"),
        .target = abi_windows_target,
        .optimize = optimize,
        .link_libc = true,
    });
    const abi_windows_shared = b.addLibrary(.{
        .name = "sa_std_abi_windows",
        .root_module = abi_windows_module,
        .linkage = .dynamic,
    });

    const abi_common_baseline = b.path("tests/abi/sa_std_symbols_v1.txt");
    const abi_thread_baseline = b.path("tests/abi/sa_std_symbols_thread_v1.txt");
    const abi_posix_baseline = b.path("tests/abi/sa_std_symbols_posix_v1.txt");
    const check_linux_static = b.addRunArtifact(abi_checker);
    check_linux_static.addArgs(&.{ abi_nm, "archive" });
    check_linux_static.addFileArg(abi_linux_static.getEmittedBin());
    check_linux_static.addFileArg(abi_common_baseline);
    check_linux_static.addFileArg(abi_thread_baseline);
    check_linux_static.addFileArg(abi_posix_baseline);
    const check_linux_shared = b.addRunArtifact(abi_checker);
    check_linux_shared.addArgs(&.{ abi_nm, "elf-shared" });
    check_linux_shared.addFileArg(abi_linux_shared.getEmittedBin());
    check_linux_shared.addFileArg(abi_common_baseline);
    check_linux_shared.addFileArg(abi_thread_baseline);
    check_linux_shared.addFileArg(abi_posix_baseline);
    const check_windows_shared = b.addRunArtifact(abi_checker);
    check_windows_shared.addArgs(&.{ abi_nm, "coff-archive" });
    _ = abi_windows_shared.getEmittedBin();
    check_windows_shared.addFileArg(abi_windows_shared.getEmittedImplib());
    check_windows_shared.addFileArg(abi_common_baseline);
    check_windows_shared.addFileArg(abi_thread_baseline);

    const sa_std_artifact_abi_step = b.step("sa-std-artifact-abi", "Check Linux ELF/archive and Windows COFF sa_std exports");
    sa_std_artifact_abi_step.dependOn(&check_linux_static.step);
    sa_std_artifact_abi_step.dependOn(&check_linux_shared.step);
    sa_std_artifact_abi_step.dependOn(&check_windows_shared.step);

    const release_contract_tests = b.addSystemCommand(&.{
        b.graph.zig_exe,
        "test",
        "tests/release_contract.zig",
    });
    release_contract_tests.setCwd(repo_root_lazy);
    test_step.dependOn(&release_contract_tests.step);
    const release_contract_step = b.step("release-contract", "Check release archive, checksum, workflow, and installer contracts");
    release_contract_step.dependOn(&release_contract_tests.step);

    const portable_host_typecheck = b.step("portable-host-typecheck", "Type-check host CLI and package code for macOS and Windows");
    const portable_targets = [_][]const u8{ "x86_64-macos", "x86_64-windows-gnu" };
    for (portable_targets) |portable_target| {
        const cli_typecheck = b.addSystemCommand(&.{
            b.graph.zig_exe,
            "build-exe",
            "-target",
            portable_target,
            "-fno-emit-bin",
            "-lc",
            "--dep",
            "build_options",
            "-Mroot=src/main.zig",
        });
        cli_typecheck.addPrefixedFileArg("-Mbuild_options=", portable_build_options.getOutput());
        cli_typecheck.setCwd(repo_root_lazy);
        portable_host_typecheck.dependOn(&cli_typecheck.step);

        for ([_][]const u8{ "src/pkg/fetch.zig", "src/pkg/resolver.zig" }) |root_source| {
            const package_typecheck = b.addSystemCommand(&.{
                b.graph.zig_exe,
                "test",
                "-target",
                portable_target,
                "-fno-emit-bin",
                root_source,
            });
            package_typecheck.setCwd(repo_root_lazy);
            portable_host_typecheck.dependOn(&package_typecheck.step);
        }
    }

    const lib_root_smoke_module = b.createModule(.{
        .root_source_file = b.path("tests/lib_root_smoke.zig"),
        .target = target,
        .optimize = optimize,
    });
    lib_root_smoke_module.addImport("saasm", lib_module);
    lib_root_smoke_module.addOptions("build_options", build_options);
    const lib_root_smoke = b.addTest(.{
        .root_module = lib_root_smoke_module,
    });
    const run_lib_root_smoke = b.addRunArtifact(lib_root_smoke);
    run_lib_root_smoke.setCwd(repo_root_lazy);
    test_step.dependOn(&run_lib_root_smoke.step);
    const lib_root_smoke_step = b.step("lib-root-smoke", "Run public library root and CLI help smoke tests");
    lib_root_smoke_step.dependOn(&run_lib_root_smoke.step);

    const plugin_host_smoke_module = b.createModule(.{
        .root_source_file = b.path("tests/plugin_host_smoke.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    plugin_host_smoke_module.addImport("saasm", lib_module);
    plugin_host_smoke_module.addOptions("build_options", build_options);
    const plugin_host_smoke = b.addTest(.{
        .root_module = plugin_host_smoke_module,
    });
    const run_plugin_host_smoke = b.addRunArtifact(plugin_host_smoke);
    run_plugin_host_smoke.setCwd(repo_root_lazy);
    test_step.dependOn(&run_plugin_host_smoke.step);
    const plugin_host_smoke_step = b.step("plugin-host-smoke", "Run runtime plugin host smoke tests");
    plugin_host_smoke_step.dependOn(&run_plugin_host_smoke.step);

    const llvmc_test_module = b.createModule(.{
        .root_source_file = b.path("src/emit_llvm_llvmc.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    addLlvmcShimToModule(b, llvmc_test_module);
    llvmc_test_module.addOptions("build_options", build_options);
    linkLLVMToModule(llvmc_test_module, llvm.include_dir, llvm.lib_dir, llvm.lib_name);
    const llvmc_tests = b.addTest(.{
        .root_module = llvmc_test_module,
    });
    const run_llvmc_tests = b.addRunArtifact(llvmc_tests);
    run_llvmc_tests.setCwd(repo_root_lazy);
    const llvmc_test_step = b.step("llvmc-test", "Run LLVM-C backend tests");
    llvmc_test_step.dependOn(&run_llvmc_tests.step);

    const pkg_core_tests_module = b.createModule(.{
        .root_source_file = b.path("src/pkg/pkg_core_tests.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    pkg_core_tests_module.addOptions("build_options", build_options);
    const pkg_core_tests = b.addTest(.{
        .root_module = pkg_core_tests_module,
    });
    const run_pkg_core_tests = b.addRunArtifact(pkg_core_tests);
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
    const pkg_audit_perf_tests = b.addTest(.{
        .root_module = pkg_audit_perf_tests_module,
        .filters = &.{"audit scans synthesized package within fifty milliseconds"},
    });
    const run_pkg_audit_perf_tests = b.addRunArtifact(pkg_audit_perf_tests);
    run_pkg_audit_perf_tests.setCwd(repo_root_lazy);
    const pkg_audit_perf_test_step = b.step("pkg-audit-perf-test", "Run package audit 50ms performance test");
    pkg_audit_perf_test_step.dependOn(&run_pkg_audit_perf_tests.step);

    const cli_module = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    addLlvmcShimToModule(b, cli_module);
    linkLLVMToModule(cli_module, llvm.include_dir, llvm.lib_dir, llvm.lib_name);
    cli_module.addOptions("build_options", build_options);
    const exe = b.addExecutable(.{
        .name = "sa",
        .root_module = cli_module,
    });
    const install_sa_exe = b.addInstallArtifact(exe, .{});
    b.getInstallStep().dependOn(&install_sa_exe.step);
    const release_artifacts_step = b.step("release-artifacts", "Build and install the compiler and static runtime release payload");
    release_artifacts_step.dependOn(&install_sa_exe.step);
    release_artifacts_step.dependOn(&install_sa_std_static.step);
    release_artifacts_step.dependOn(&install_sa_std_header.step);

    const wasm_matrix_module = b.createModule(.{
        .root_source_file = b.path("tests/wasm_matrix_smoke.zig"),
        .target = target,
        .optimize = optimize,
    });
    wasm_matrix_module.addImport("saasm", lib_module);
    wasm_matrix_module.addOptions("build_options", build_options);
    const wasm_matrix = b.addTest(.{
        .root_module = wasm_matrix_module,
    });
    const run_wasm_matrix = b.addRunArtifact(wasm_matrix);
    run_wasm_matrix.setCwd(repo_root_lazy);
    run_wasm_matrix.step.name = "wasm-matrix";
    test_step.dependOn(&run_wasm_matrix.step);
    const wasm_matrix_step = b.step("wasm-matrix", "Run LLVM-C native/wasm32 demo equivalence matrix");
    wasm_matrix_step.dependOn(&run_wasm_matrix.step);

    const cli_smoke_module = b.createModule(.{
        .root_source_file = b.path("tests/cli_smoke.zig"),
        .target = target,
        .optimize = optimize,
    });
    cli_smoke_module.addImport("saasm", lib_module);
    cli_smoke_module.addOptions("build_options", build_options);
    const cli_smoke = b.addTest(.{
        .root_module = cli_smoke_module,
        .filters = &.{
            "bc2sa translates real llvm bitcode",
            "bc2sa translates clang cmake bitcode demo",
            "cli build-exe prunes unused imported functions before llvm emission",
        },
    });
    const run_cli_smoke = b.addRunArtifact(cli_smoke);
    run_cli_smoke.setCwd(repo_root_lazy);
    test_step.dependOn(&run_cli_smoke.step);
    const cli_smoke_step = b.step("bc2sa-smoke", "Run the bc2sa real bitcode smoke tests");
    cli_smoke_step.dependOn(&run_cli_smoke.step);

    const cli_skills_smoke_module = b.createModule(.{
        .root_source_file = b.path("tests/cli_smoke.zig"),
        .target = target,
        .optimize = optimize,
    });
    cli_skills_smoke_module.addImport("saasm", lib_module);
    cli_skills_smoke_module.addOptions("build_options", build_options);
    const cli_skills_smoke = b.addTest(.{
        .root_module = cli_skills_smoke_module,
        .filters = &.{
            "agent-first cli commands print explain fix and skills outputs",
            "sa skills writes Codex and Claude skill files for current project",
        },
    });
    const run_cli_skills_smoke = b.addRunArtifact(cli_skills_smoke);
    run_cli_skills_smoke.setCwd(repo_root_lazy);
    const cli_skills_smoke_step = b.step("cli-skills-smoke", "Run the sa skills focused CLI smoke tests");
    cli_skills_smoke_step.dependOn(&run_cli_skills_smoke.step);

    const workspace_smoke_module = b.createModule(.{
        .root_source_file = b.path("tests/cli_smoke.zig"),
        .target = target,
        .optimize = optimize,
    });
    workspace_smoke_module.addImport("saasm", lib_module);
    workspace_smoke_module.addOptions("build_options", build_options);
    const workspace_smoke = b.addTest(.{
        .root_module = workspace_smoke_module,
        .filters = &.{"workspace install aggregates member manifests at root and pkg install falls back to builtin workspace flow"},
    });
    const run_workspace_smoke = b.addRunArtifact(workspace_smoke);
    run_workspace_smoke.setCwd(repo_root_lazy);
    test_step.dependOn(&run_workspace_smoke.step);
    const workspace_smoke_step = b.step("workspace-smoke", "Run workspace package-management smoke tests");
    workspace_smoke_step.dependOn(&run_workspace_smoke.step);

    const pthread_vtable_smoke_module = b.createModule(.{
        .root_source_file = b.path("tests/cli_smoke.zig"),
        .target = target,
        .optimize = optimize,
    });
    pthread_vtable_smoke_module.addImport("saasm", lib_module);
    pthread_vtable_smoke_module.addOptions("build_options", build_options);
    const pthread_vtable_smoke = b.addTest(.{
        .root_module = pthread_vtable_smoke_module,
        .filters = &.{"pthread vtable worker stores survive native join"},
    });
    const run_pthread_vtable_smoke = b.addRunArtifact(pthread_vtable_smoke);
    run_pthread_vtable_smoke.setCwd(repo_root_lazy);
    const pthread_vtable_smoke_step = b.step("pthread-vtable-smoke", "Run pthread vtable native codegen regression test");
    pthread_vtable_smoke_step.dependOn(&run_pthread_vtable_smoke.step);

    const trap_baseline_module = b.createModule(.{
        .root_source_file = b.path("tests/golden/trap_baseline.zig"),
        .target = target,
        .optimize = optimize,
    });
    trap_baseline_module.addImport("saasm", lib_module);
    trap_baseline_module.addOptions("build_options", build_options);
    const trap_baseline = b.addTest(.{
        .root_module = trap_baseline_module,
    });
    const run_trap_baseline = b.addRunArtifact(trap_baseline);
    run_trap_baseline.setCwd(repo_root_lazy);
    test_step.dependOn(&run_trap_baseline.step);
    const trap_baseline_step = b.step("trap-baseline", "Run golden trap diagnostic baseline tests");
    trap_baseline_step.dependOn(&run_trap_baseline.step);

    const std_smoke_core_module = b.createModule(.{
        .root_source_file = b.path("tests/std_smoke_core.zig"),
        .target = target,
        .optimize = optimize,
    });
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
    std_smoke_containers_module.addImport("saasm", lib_module);
    std_smoke_containers_module.addOptions("build_options", build_options);
    std_smoke_containers_module.addOptions("test_build_options", test_build_options);
    const std_smoke_containers = b.addTest(.{
        .root_module = std_smoke_containers_module,
    });

    const run_std_smoke_core = b.addRunArtifact(std_smoke_core);
    run_std_smoke_core.setCwd(repo_root_lazy);
    test_step.dependOn(&run_std_smoke_core.step);

    const run_std_smoke_containers = b.addRunArtifact(std_smoke_containers);
    run_std_smoke_containers.setCwd(repo_root_lazy);
    test_step.dependOn(&run_std_smoke_containers.step);

    const unit_framework_module = b.createModule(.{
        .root_source_file = b.path("tests/unit_framework/runner.zig"),
        .target = target,
        .optimize = optimize,
    });
    unit_framework_module.addImport("saasm", lib_module);
    unit_framework_module.addOptions("build_options", build_options);
    const unit_framework = b.addTest(.{
        .root_module = unit_framework_module,
    });
    const run_unit_framework = b.addRunArtifact(unit_framework);
    run_unit_framework.setCwd(repo_root_lazy);
    run_unit_framework.step.dependOn(&install_sa_exe.step);
    run_unit_framework.setEnvironmentVariable("SA_STD_DIR", b.pathFromRoot("sa_std"));
    run_unit_framework.setEnvironmentVariable("SA_BIN", b.getInstallPath(.bin, "sa"));
    test_step.dependOn(&run_unit_framework.step);
    const unit_framework_step = b.step("unit-framework", "Run native SA unit framework suites");
    unit_framework_step.dependOn(&run_unit_framework.step);

    const sa_std_unit_module = b.createModule(.{
        .root_source_file = b.path("src/runtime/sa_std.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    sa_std_unit_module.addOptions("build_options", build_options);
    const sa_std_unit = b.addTest(.{
        .root_module = sa_std_unit_module,
    });
    const run_sa_std_unit = b.addRunArtifact(sa_std_unit);
    run_sa_std_unit.setCwd(repo_root_lazy);
    test_step.dependOn(&run_sa_std_unit.step);
    const sa_std_unit_step = b.step("sa-std-unit", "Run Zig unit tests for the SA standard runtime");
    sa_std_unit_step.dependOn(&run_sa_std_unit.step);

    const sa_std_runtime_module = b.createModule(.{
        .root_source_file = b.path("tests/sa_std_runtime.zig"),
        .target = target,
        .optimize = optimize,
    });
    sa_std_runtime_module.addOptions("build_options", build_options);
    const sa_std_runtime = b.addTest(.{
        .root_module = sa_std_runtime_module,
    });
    const run_sa_std_runtime = b.addRunArtifact(sa_std_runtime);
    run_sa_std_runtime.setCwd(repo_root_lazy);
    test_step.dependOn(&run_sa_std_runtime.step);
    const sa_std_runtime_step = b.step("sa-std-runtime", "Run SA standard runtime integration tests");
    sa_std_runtime_step.dependOn(&run_sa_std_runtime.step);

    const sa_net_uring_module = b.createModule(.{
        .root_source_file = b.path("src/runtime/sa_net_uring.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    sa_net_uring_module.addOptions("build_options", build_options);
    const sa_net_uring_tests = b.addTest(.{
        .root_module = sa_net_uring_module,
    });
    const run_sa_net_uring_tests = b.addRunArtifact(sa_net_uring_tests);
    run_sa_net_uring_tests.setCwd(repo_root_lazy);
    test_step.dependOn(&run_sa_net_uring_tests.step);
    const sa_net_uring_test_step = b.step("sa-net-uring-test", "Run io_uring network runtime tests");
    sa_net_uring_test_step.dependOn(&run_sa_net_uring_tests.step);
    const sa_http2_module = b.createModule(.{
        .root_source_file = b.path("src/runtime/sa_http2.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    sa_http2_module.addOptions("build_options", build_options);
    const sa_http2_tests = b.addTest(.{
        .root_module = sa_http2_module,
    });
    const run_sa_http2_tests = b.addRunArtifact(sa_http2_tests);
    run_sa_http2_tests.setCwd(repo_root_lazy);
    test_step.dependOn(&run_sa_http2_tests.step);
    const sa_http2_test_step = b.step("sa-http2-test", "Run HTTP/2 (libnghttp2) runtime tests");
    sa_http2_test_step.dependOn(&run_sa_http2_tests.step);
    const sa_tls_server_module = b.createModule(.{
        .root_source_file = b.path("src/runtime/sa_tls_server.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    sa_tls_server_module.addOptions("build_options", build_options);
    const sa_tls_server_tests = b.addTest(.{
        .root_module = sa_tls_server_module,
    });
    const run_sa_tls_server_tests = b.addRunArtifact(sa_tls_server_tests);
    run_sa_tls_server_tests.setCwd(repo_root_lazy);
    test_step.dependOn(&run_sa_tls_server_tests.step);
    const sa_tls_server_test_step = b.step("sa-tls-server-test", "Run TLS-server (OpenSSL) runtime tests");
    sa_tls_server_test_step.dependOn(&run_sa_tls_server_tests.step);
    const sa_dtls_module = b.createModule(.{
        .root_source_file = b.path("src/runtime/sa_dtls.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    sa_dtls_module.addOptions("build_options", build_options);
    const sa_dtls_tests = b.addTest(.{
        .root_module = sa_dtls_module,
    });
    const run_sa_dtls_tests = b.addRunArtifact(sa_dtls_tests);
    run_sa_dtls_tests.setCwd(repo_root_lazy);
    test_step.dependOn(&run_sa_dtls_tests.step);
    const sa_dtls_test_step = b.step("sa-dtls-test", "Run DTLS (OpenSSL) runtime tests");
    sa_dtls_test_step.dependOn(&run_sa_dtls_tests.step);
    const sa_quic_module = b.createModule(.{
        .root_source_file = b.path("src/runtime/sa_quic.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    sa_quic_module.addOptions("build_options", build_options);
    const sa_quic_tests = b.addTest(.{
        .root_module = sa_quic_module,
    });
    const run_sa_quic_tests = b.addRunArtifact(sa_quic_tests);
    run_sa_quic_tests.setCwd(repo_root_lazy);
    test_step.dependOn(&run_sa_quic_tests.step);
    const sa_quic_test_step = b.step("sa-quic-test", "Run QUIC/HTTP3 runtime capability tests");
    sa_quic_test_step.dependOn(&run_sa_quic_tests.step);

    const sa_term_runtime_module = b.createModule(.{
        .root_source_file = b.path("tests/sa_term_runtime.zig"),
        .target = target,
        .optimize = optimize,
    });
    sa_term_runtime_module.addOptions("build_options", build_options);
    const sa_term_runtime = b.addTest(.{
        .root_module = sa_term_runtime_module,
    });
    const run_sa_term_runtime = b.addRunArtifact(sa_term_runtime);
    run_sa_term_runtime.setCwd(repo_root_lazy);
    test_step.dependOn(&run_sa_term_runtime.step);
    const sa_term_runtime_step = b.step("sa-term-runtime", "Run terminal runtime tests");
    sa_term_runtime_step.dependOn(&run_sa_term_runtime.step);

    const native_sys_runtime_module = b.createModule(.{
        .root_source_file = b.path("tests/native_sys_runtime.zig"),
        .target = target,
        .optimize = optimize,
    });
    native_sys_runtime_module.addOptions("build_options", build_options);
    const native_sys_runtime = b.addTest(.{
        .root_module = native_sys_runtime_module,
    });
    const run_native_sys_runtime = b.addRunArtifact(native_sys_runtime);
    run_native_sys_runtime.setCwd(repo_root_lazy);
    test_step.dependOn(&run_native_sys_runtime.step);
    const native_sys_runtime_step = b.step("native-sys-runtime", "Run native system runtime tests");
    native_sys_runtime_step.dependOn(&run_native_sys_runtime.step);

    const std_smoke_step = b.step("std-smoke", "Run the SA standard library smoke tests");
    std_smoke_step.dependOn(&run_std_smoke_core.step);
    std_smoke_step.dependOn(&run_std_smoke_containers.step);

    const std_step = b.step("std", "Run the SA standard library and runtime checks");
    std_step.dependOn(&run_std_smoke_core.step);
    std_step.dependOn(&run_std_smoke_containers.step);
    std_step.dependOn(&run_sa_std_unit.step);
    std_step.dependOn(&run_sa_std_runtime.step);
    std_step.dependOn(&run_sa_net_uring_tests.step);
    std_step.dependOn(&run_sa_term_runtime.step);
    std_step.dependOn(&run_native_sys_runtime.step);

    const smoke = b.addTest(.{
        .root_source_file = b.path("tests/smoke/whitepaper_lint.zig"),
        .target = target,
        .optimize = optimize,
    });
    smoke.root_module.addOptions("build_options", build_options);
    const run_smoke = b.addRunArtifact(smoke);
    run_smoke.setCwd(repo_root_lazy);
    const smoke_step = b.step("smoke", "Run smoke tests");
    smoke_step.dependOn(&run_smoke.step);
    smoke_step.dependOn(&run_std_smoke_core.step);
    smoke_step.dependOn(&run_std_smoke_containers.step);
    test_step.dependOn(&run_smoke.step);

    const whitepaper_lint_step = b.step("whitepaper-lint", "Run whitepaper smoke lint without std smoke reruns");
    whitepaper_lint_step.dependOn(&run_smoke.step);

    const scope_demo = b.addTest(.{
        .root_source_file = b.path("tests/libsa_scope_demo.zig"),
        .target = target,
        .optimize = optimize,
    });
    scope_demo.root_module.addOptions("build_options", build_options);
    const run_scope_demo = b.addRunArtifact(scope_demo);
    run_scope_demo.setCwd(repo_root_lazy);
    test_step.dependOn(&run_scope_demo.step);
    const scope_demo_step = b.step("scope-demo", "Run libsa scope demo tests");
    scope_demo_step.dependOn(&run_scope_demo.step);

    const ffi_handle_demo_module = b.createModule(.{
        .root_source_file = b.path("tests/integration/ffi_handle_demo.zig"),
        .target = target,
        .optimize = optimize,
    });
    ffi_handle_demo_module.addImport("saasm", lib_module);
    ffi_handle_demo_module.addOptions("build_options", build_options);
    const ffi_handle_demo = b.addTest(.{
        .root_module = ffi_handle_demo_module,
    });
    const run_ffi_handle_demo = b.addRunArtifact(ffi_handle_demo);
    run_ffi_handle_demo.setCwd(repo_root_lazy);
    test_step.dependOn(&run_ffi_handle_demo.step);
    const ffi_handle_demo_step = b.step("ffi-handle-demo", "Run FFI handle integration demo tests");
    ffi_handle_demo_step.dependOn(&run_ffi_handle_demo.step);

    const hubproxy_module = b.createModule(.{
        .root_source_file = b.path("examples/hubproxy/main.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    hubproxy_module.addImport("saasm", lib_module);
    hubproxy_module.addOptions("build_options", build_options);
    const hubproxy_tests = b.addTest(.{
        .root_module = hubproxy_module,
    });
    const run_hubproxy_tests = b.addRunArtifact(hubproxy_tests);
    run_hubproxy_tests.setCwd(repo_root_lazy);
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
    referee_loc_lint.setCwd(repo_root_lazy);
    const referee_loc_lint_step = b.step("referee-loc-lint", "Run referee line-count lint");
    referee_loc_lint_step.dependOn(&referee_loc_lint.step);
    const ci_step = b.step("ci", "Run the v0.1 CI gate");
    ci_step.dependOn(&run_trap_baseline.step);
    ci_step.dependOn(&run_std_smoke_core.step);
    ci_step.dependOn(&run_std_smoke_containers.step);
    ci_step.dependOn(&run_unit_framework.step);
    ci_step.dependOn(&run_sa_std_unit.step);
    ci_step.dependOn(&run_sa_std_runtime.step);
    ci_step.dependOn(&run_sa_net_uring_tests.step);
    ci_step.dependOn(&run_sa_term_runtime.step);
    ci_step.dependOn(&run_native_sys_runtime.step);
    ci_step.dependOn(&run_smoke.step);
    ci_step.dependOn(&run_scope_demo.step);
    ci_step.dependOn(&run_ffi_handle_demo.step);
    ci_step.dependOn(&run_hubproxy_tests.step);
    ci_step.dependOn(&run_pkg_core_tests.step);
    ci_step.dependOn(&run_plugin_host_smoke.step);
    ci_step.dependOn(&referee_loc_lint.step);
    ci_step.dependOn(&run_wasm_matrix.step);
    ci_step.dependOn(&release_contract_tests.step);

    const pre_push_step = b.step("pre-push", "Run the pre-push gate");
    pre_push_step.dependOn(ci_step);

    const bench_module = b.createModule(.{
        .root_source_file = b.path("bench/task_6_26.zig"),
        .target = target,
        .optimize = optimize,
    });
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

fn addLlvmcShimToModule(b: *std.Build, module: *std.Build.Module) void {
    module.addCSourceFile(.{ .file = b.path("src/emit_llvm_llvmc_shim.c"), .flags = &.{} });
}

fn addPthreadHostShimToModule(b: *std.Build, module: *std.Build.Module, os_tag: std.Target.Os.Tag) void {
    if (os_tag == .linux) {
        module.addCSourceFile(.{ .file = b.path("src/runtime/sa_pthread_host.c"), .flags = &.{} });
    } else if (os_tag == .macos) {
        module.addCSourceFile(.{ .file = b.path("src/runtime/sa_pthread_host_darwin.c"), .flags = &.{} });
    }
}

fn linkLLVMToModule(module: *std.Build.Module, include_dir: []const u8, lib_dir: []const u8, lib_name: []const u8) void {
    module.addSystemIncludePath(.{ .cwd_relative = include_dir });
    module.addLibraryPath(.{ .cwd_relative = lib_dir });
    module.linkSystemLibrary(lib_name, .{});
}
