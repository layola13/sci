const std = @import("std");

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
    const is_windows = target.result.os.tag == .windows;
    const is_linux = target.result.os.tag == .linux;
    const release_safe = b.option(bool, "release-safe", "Build all artifacts with ReleaseSafe optimization.") orelse false;
    const release_small = b.option(bool, "release-small", "Build all artifacts with ReleaseSmall optimization.") orelse false;
    const enable_llvm_default = target.result.os.tag != .windows;
    const enable_llvm = b.option(bool, "llvm", "Enable LLVM-C native backend integration.") orelse enable_llvm_default;
    const version = b.option([]const u8, "version", "SA toolchain semantic version.") orelse latestGitTag(b.allocator) orelse "0.0.1";
    const llvm_include_dir = b.option([]const u8, "llvm-include-dir", "LLVM C API include directory.") orelse defaultLlvmIncludeDir(target.result.os.tag);
    const llvm_lib_dir = b.option([]const u8, "llvm-lib-dir", "LLVM library directory.") orelse defaultLlvmLibDir(target.result.os.tag);
    const llvm_lib_name = b.option([]const u8, "llvm-lib-name", "LLVM system library name.") orelse defaultLlvmLibName(target.result.os.tag);
    const llvmc_test_filter = b.option([]const u8, "llvmc-test-filter", "Run only LLVM-C tests whose names contain this text.");
    var optimize = b.standardOptimizeOption(.{});
    if (release_safe) optimize = .ReleaseSafe;
    if (release_small) optimize = .ReleaseSmall;
    const repo_root = b.pathFromRoot(".");
    const repo_root_lazy = b.path(".");
    const build_options = b.addOptions();
    const test_build_options = b.addOptions();
    const sa_std_archive_rel = targetSaStdArchivePath(target.result.os.tag);
    const sa_std_root = targetSaStdRoot(target.result.os.tag);
    validateLlvmConfig(b, target.result.os.tag, enable_llvm, llvm_include_dir, llvm_lib_dir, llvm_lib_name);
    build_options.addOption([]const u8, "sa_std_archive_path", b.pathFromRoot(sa_std_archive_rel));
    build_options.addOption(bool, "llvm_enabled", enable_llvm);
    build_options.addOption([]const u8, "repo_root", repo_root);
    build_options.addOption([]const u8, "version", version);
    test_build_options.addOption([]const u8, "repo_root", repo_root);

    const lib_module = b.createModule(.{
        .root_source_file = b.path("src/lib.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    addLlvmcSupportToModule(b, lib_module, enable_llvm, llvm_include_dir, llvm_lib_dir, llvm_lib_name);
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
        .root_source_file = b.path(sa_std_root),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    addHostThreadShimToModule(b, sa_std_static_module, target.result.os.tag);
    const sa_std_static = b.addLibrary(.{
        .name = "sa_std",
        .root_module = sa_std_static_module,
        .linkage = .static,
    });
    const install_sa_std_static = b.addInstallArtifact(sa_std_static, .{});
    const sync_sa_std_artifact = b.addUpdateSourceFiles();
    sync_sa_std_artifact.addCopyFileToSource(sa_std_static.getEmittedBin(), sa_std_archive_rel);

    const sa_std_shared_module = b.createModule(.{
        .root_source_file = b.path(sa_std_root),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    addHostThreadShimToModule(b, sa_std_shared_module, target.result.os.tag);
    const sa_std_shared = b.addLibrary(.{
        .name = "sa_std",
        .root_module = sa_std_shared_module,
        .linkage = .dynamic,
    });
    const install_sa_std_shared = b.addInstallArtifact(sa_std_shared, .{});

    const install_sa_std_header = b.addInstallHeaderFile(b.path("src/runtime/sa_std.h"), "sa_std.h");
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
    plugin_host_smoke_module.addImport("saasm", lib_module);
    plugin_host_smoke_module.addOptions("build_options", build_options);
    const plugin_host_smoke = b.addTest(.{
        .root_module = plugin_host_smoke_module,
    });
    const run_plugin_host_smoke = b.addRunArtifact(plugin_host_smoke);
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
    addLlvmcSupportToModule(b, cli_module, enable_llvm, llvm_include_dir, llvm_lib_dir, llvm_lib_name);
    cli_module.addOptions("build_options", build_options);
    const exe = b.addExecutable(.{
        .name = "sa",
        .root_module = cli_module,
    });
    linkLLVMToCompile(exe, enable_llvm, llvm_include_dir, llvm_lib_dir, llvm_lib_name);
    const install_sa_exe = b.addInstallArtifact(exe, .{});
    b.getInstallStep().dependOn(&install_sa_exe.step);
    if (enable_llvm) installLlvmCDll(b, llvm_lib_dir, target.result.os.tag);

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
    addLlvmBinDirToRun(b, run_wasm_matrix, enable_llvm, llvm_lib_dir, target.result.os.tag);
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
            "extern i32 fallible return uses ABI-aligned payload offset",
        },
    });
    const run_cli_smoke = b.addRunArtifact(cli_smoke);
    run_cli_smoke.setCwd(repo_root_lazy);
    addLlvmBinDirToRun(b, run_cli_smoke, enable_llvm, llvm_lib_dir, target.result.os.tag);
    run_cli_smoke.step.dependOn(&sync_sa_std_artifact.step);
    if (enable_llvm) test_step.dependOn(&run_cli_smoke.step);
    const cli_smoke_step = b.step("bc2sa-smoke", "Run the bc2sa real bitcode smoke tests");
    cli_smoke_step.dependOn(&run_cli_smoke.step);

    const cli_json_debug_smoke_module = b.createModule(.{
        .root_source_file = b.path("tests/cli_smoke.zig"),
        .target = target,
        .optimize = optimize,
    });
    cli_json_debug_smoke_module.addImport("saasm", lib_module);
    cli_json_debug_smoke_module.addOptions("build_options", build_options);
    const cli_json_debug_smoke = b.addTest(.{
        .root_module = cli_json_debug_smoke_module,
        .filters = &.{"json extern build-exe does not inject debug prints"},
    });
    const run_cli_json_debug_smoke = b.addRunArtifact(cli_json_debug_smoke);
    run_cli_json_debug_smoke.setCwd(repo_root_lazy);
    addLlvmBinDirToRun(b, run_cli_json_debug_smoke, enable_llvm, llvm_lib_dir, target.result.os.tag);
    run_cli_json_debug_smoke.step.dependOn(&sync_sa_std_artifact.step);
    const cli_json_debug_smoke_step = b.step("llvmc-json-debug-smoke", "Run the LLVM-C JSON debug-print regression smoke test");
    if (enable_llvm) cli_json_debug_smoke_step.dependOn(&run_cli_json_debug_smoke.step);

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
    addLlvmBinDirToRun(b, run_cli_skills_smoke, enable_llvm, llvm_lib_dir, target.result.os.tag);
    const cli_skills_smoke_step = b.step("cli-skills-smoke", "Run the sa skills focused CLI smoke tests");
    cli_skills_smoke_step.dependOn(&run_cli_skills_smoke.step);

    const cli_host_basic_module = b.createModule(.{
        .root_source_file = b.path("tests/cli_smoke.zig"),
        .target = target,
        .optimize = optimize,
    });
    cli_host_basic_module.addImport("saasm", lib_module);
    cli_host_basic_module.addOptions("build_options", build_options);
    const cli_host_basic = b.addTest(.{
        .root_module = cli_host_basic_module,
        .filters = &.{
            "cli default executable suffix is target aware",
            "llvm disabled build-exe reports backend diagnostic",
        },
    });
    const run_cli_host_basic = b.addRunArtifact(cli_host_basic);
    run_cli_host_basic.setCwd(repo_root_lazy);
    addLlvmBinDirToRun(b, run_cli_host_basic, enable_llvm, llvm_lib_dir, target.result.os.tag);
    const cli_host_basic_step = b.step("cli-host-basic", "Run host-portable CLI compatibility smoke tests");
    cli_host_basic_step.dependOn(&run_cli_host_basic.step);

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
    addLlvmBinDirToRun(b, run_workspace_smoke, enable_llvm, llvm_lib_dir, target.result.os.tag);
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
    addLlvmBinDirToRun(b, run_pthread_vtable_smoke, enable_llvm, llvm_lib_dir, target.result.os.tag);
    run_pthread_vtable_smoke.step.dependOn(&sync_sa_std_artifact.step);
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
    addLlvmBinDirToRun(b, run_trap_baseline, enable_llvm, llvm_lib_dir, target.result.os.tag);
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
    addLlvmBinDirToRun(b, run_std_smoke_core, enable_llvm, llvm_lib_dir, target.result.os.tag);
    test_step.dependOn(&run_std_smoke_core.step);

    const run_std_smoke_containers = b.addRunArtifact(std_smoke_containers);
    run_std_smoke_containers.setCwd(repo_root_lazy);
    addLlvmBinDirToRun(b, run_std_smoke_containers, enable_llvm, llvm_lib_dir, target.result.os.tag);
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
    addLlvmBinDirToRun(b, run_unit_framework, enable_llvm, llvm_lib_dir, target.result.os.tag);
    run_unit_framework.step.dependOn(&install_sa_exe.step);
    run_unit_framework.step.dependOn(&sync_sa_std_artifact.step);
    run_unit_framework.setEnvironmentVariable("SA_STD_DIR", b.pathFromRoot("sa_std"));
    run_unit_framework.setEnvironmentVariable("SA_BIN", b.getInstallPath(.bin, "sa"));
    if (enable_llvm) test_step.dependOn(&run_unit_framework.step);
    const unit_framework_step = b.step("unit-framework", "Run native SA unit framework suites");
    if (enable_llvm) unit_framework_step.dependOn(&run_unit_framework.step);

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
    if (is_linux) test_step.dependOn(&run_sa_std_unit.step);
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
    run_sa_std_runtime.step.dependOn(&sync_sa_std_artifact.step);
    if (is_linux) test_step.dependOn(&run_sa_std_runtime.step);
    const sa_std_runtime_step = b.step("sa-std-runtime", "Run SA standard runtime integration tests");
    sa_std_runtime_step.dependOn(&run_sa_std_runtime.step);

    const sa_std_windows_runtime_module = b.createModule(.{
        .root_source_file = b.path("tests/sa_std_windows_runtime.zig"),
        .target = target,
        .optimize = optimize,
    });
    sa_std_windows_runtime_module.addOptions("build_options", build_options);
    const sa_std_windows_runtime = b.addTest(.{
        .root_module = sa_std_windows_runtime_module,
    });
    const run_sa_std_windows_runtime = b.addRunArtifact(sa_std_windows_runtime);
    run_sa_std_windows_runtime.setCwd(repo_root_lazy);
    run_sa_std_windows_runtime.step.dependOn(&sync_sa_std_artifact.step);
    const windows_runtime_step = b.step("windows-runtime", "Run Windows SA standard runtime bootstrap checks");
    if (target.result.os.tag == .windows) {
        windows_runtime_step.dependOn(&run_sa_std_windows_runtime.step);
        test_step.dependOn(windows_runtime_step);
    }

    const windows_first_slice_step = b.step("windows-first-slice", "Compile and run the Windows-first C ABI smoke test");
    if (is_windows) {
        windows_first_slice_step.dependOn(&sync_sa_std_artifact.step);
        windows_first_slice_step.dependOn(&install_sa_std_header.step);

        const windows_first_slice_module = b.createModule(.{
            .target = target,
            .optimize = optimize,
            .link_libc = true,
        });
        windows_first_slice_module.addIncludePath(b.path("src/runtime"));
        windows_first_slice_module.addCSourceFile(.{
            .file = b.path("tests/sa_std_windows_first_slice.c"),
            .flags = &.{},
        });
        windows_first_slice_module.addObjectFile(sa_std_static.getEmittedBin());

        const windows_first_slice = b.addExecutable(.{
            .name = "sa_std_windows_first_slice",
            .root_module = windows_first_slice_module,
        });
        linkWindowsNetworkingToCompile(windows_first_slice, target.result.os.tag);
        const run_windows_first_slice = b.addRunArtifact(windows_first_slice);
        run_windows_first_slice.setCwd(repo_root_lazy);
        windows_first_slice_step.dependOn(&run_windows_first_slice.step);
    }

    const windows_native_address_step = b.step(
        "windows-native-address",
        "Compile and run the Windows address conversion ABI smoke test",
    );
    if (is_windows) {
        windows_native_address_step.dependOn(&sync_sa_std_artifact.step);
        windows_native_address_step.dependOn(&install_sa_std_header.step);

        const windows_native_address_module = b.createModule(.{
            .target = target,
            .optimize = optimize,
            .link_libc = true,
        });
        windows_native_address_module.addIncludePath(b.path("src/runtime"));
        windows_native_address_module.addCSourceFile(.{
            .file = b.path("tests/sa_std_windows_address.c"),
            .flags = &.{},
        });
        windows_native_address_module.addObjectFile(sa_std_static.getEmittedBin());

        const windows_native_address = b.addExecutable(.{
            .name = "sa_std_windows_address",
            .root_module = windows_native_address_module,
        });
        linkWindowsNetworkingToCompile(windows_native_address, target.result.os.tag);
        const run_windows_native_address = b.addRunArtifact(windows_native_address);
        run_windows_native_address.setCwd(repo_root_lazy);
        windows_native_address_step.dependOn(&run_windows_native_address.step);
    }

    const windows_native_tcp_step = b.step(
        "windows-native-tcp",
        "Compile and run the Windows TCP ABI smoke test",
    );
    if (is_windows) {
        windows_native_tcp_step.dependOn(&sync_sa_std_artifact.step);
        windows_native_tcp_step.dependOn(&install_sa_std_header.step);

        const windows_native_tcp_module = b.createModule(.{
            .target = target,
            .optimize = optimize,
            .link_libc = true,
        });
        windows_native_tcp_module.addIncludePath(b.path("src/runtime"));
        windows_native_tcp_module.addCSourceFile(.{
            .file = b.path("tests/sa_std_windows_tcp.c"),
            .flags = &.{"-DSA_WINDOWS_TCP_EXPECT_SUPPORTED=1"},
        });
        windows_native_tcp_module.addObjectFile(sa_std_static.getEmittedBin());

        const windows_native_tcp = b.addExecutable(.{
            .name = "sa_std_windows_tcp",
            .root_module = windows_native_tcp_module,
        });
        linkWindowsNetworkingToCompile(windows_native_tcp, target.result.os.tag);
        const run_windows_native_tcp = b.addRunArtifact(windows_native_tcp);
        run_windows_native_tcp.setCwd(repo_root_lazy);
        windows_native_tcp_step.dependOn(&run_windows_native_tcp.step);
    }

    const windows_native_udp_step = b.step(
        "windows-native-udp",
        "Compile and run the Windows UDP ABI smoke test",
    );
    if (is_windows) {
        windows_native_udp_step.dependOn(&sync_sa_std_artifact.step);
        windows_native_udp_step.dependOn(&install_sa_std_header.step);

        const windows_native_udp_module = b.createModule(.{
            .target = target,
            .optimize = optimize,
            .link_libc = true,
        });
        windows_native_udp_module.addIncludePath(b.path("src/runtime"));
        windows_native_udp_module.addCSourceFile(.{
            .file = b.path("tests/sa_std_windows_udp.c"),
            .flags = &.{"-DSA_STD_WINDOWS_UDP_SUPPORTED=1"},
        });
        windows_native_udp_module.addObjectFile(sa_std_static.getEmittedBin());

        const windows_native_udp = b.addExecutable(.{
            .name = "sa_std_windows_udp",
            .root_module = windows_native_udp_module,
        });
        linkWindowsNetworkingToCompile(windows_native_udp, target.result.os.tag);
        const run_windows_native_udp = b.addRunArtifact(windows_native_udp);
        run_windows_native_udp.setCwd(repo_root_lazy);
        windows_native_udp_step.dependOn(&run_windows_native_udp.step);
    }

    const windows_native_process_terminal_step = b.step(
        "windows-native-process-terminal",
        "Compile and run the Windows process and terminal ABI smoke test",
    );
    if (is_windows) {
        windows_native_process_terminal_step.dependOn(&sync_sa_std_artifact.step);
        windows_native_process_terminal_step.dependOn(&install_sa_std_header.step);

        const windows_native_process_terminal_module = b.createModule(.{
            .target = target,
            .optimize = optimize,
            .link_libc = true,
        });
        windows_native_process_terminal_module.addIncludePath(b.path("src/runtime"));
        windows_native_process_terminal_module.addCSourceFile(.{
            .file = b.path("tests/sa_std_windows_process_terminal.c"),
            .flags = &.{},
        });
        windows_native_process_terminal_module.addObjectFile(sa_std_static.getEmittedBin());

        const windows_native_process_terminal = b.addExecutable(.{
            .name = "sa_std_windows_process_terminal",
            .root_module = windows_native_process_terminal_module,
        });
        linkWindowsNetworkingToCompile(windows_native_process_terminal, target.result.os.tag);
        const run_windows_native_process_terminal = b.addRunArtifact(windows_native_process_terminal);
        run_windows_native_process_terminal.setCwd(repo_root_lazy);
        windows_native_process_terminal_step.dependOn(&run_windows_native_process_terminal.step);
    }

    if (is_windows) {
        windows_runtime_step.dependOn(windows_first_slice_step);
        windows_runtime_step.dependOn(windows_native_address_step);
        windows_runtime_step.dependOn(windows_native_process_terminal_step);
        windows_runtime_step.dependOn(windows_native_tcp_step);
        windows_runtime_step.dependOn(windows_native_udp_step);
    }

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
    if (is_linux) test_step.dependOn(&run_sa_net_uring_tests.step);
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
    if (is_linux) test_step.dependOn(&run_sa_http2_tests.step);
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
    if (is_linux) test_step.dependOn(&run_sa_tls_server_tests.step);
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
    if (is_linux) test_step.dependOn(&run_sa_dtls_tests.step);
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
    if (is_linux) test_step.dependOn(&run_sa_quic_tests.step);
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
    if (is_linux) test_step.dependOn(&run_sa_term_runtime.step);
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
    runtime_abi_step.dependOn(&runtime_abi.step);
    test_step.dependOn(runtime_abi_step);

    const linux_runtime_step = b.step("linux-runtime", "Run Linux-only runtime and kernel integration checks");
    if (is_linux) {
        linux_runtime_step.dependOn(&run_native_sys_runtime.step);
        linux_runtime_step.dependOn(&run_sa_std_unit.step);
        linux_runtime_step.dependOn(&run_sa_std_runtime.step);
        linux_runtime_step.dependOn(&run_sa_net_uring_tests.step);
        linux_runtime_step.dependOn(&run_sa_http2_tests.step);
        linux_runtime_step.dependOn(&run_sa_tls_server_tests.step);
        linux_runtime_step.dependOn(&run_sa_dtls_tests.step);
        linux_runtime_step.dependOn(&run_sa_quic_tests.step);
        linux_runtime_step.dependOn(&run_sa_term_runtime.step);
    }

    const std_smoke_step = b.step("std-smoke", "Run the SA standard library smoke tests");
    std_smoke_step.dependOn(&run_std_smoke_core.step);
    std_smoke_step.dependOn(&run_std_smoke_containers.step);

    const std_step = b.step("std", "Run the SA standard library and runtime checks");
    std_step.dependOn(&run_std_smoke_core.step);
    std_step.dependOn(&run_std_smoke_containers.step);
    if (is_linux) {
        std_step.dependOn(linux_runtime_step);
    } else {
        std_step.dependOn(runtime_abi_step);
        std_step.dependOn(&run_native_sys_runtime.step);
    }

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
    hubproxy_module.addImport("saasm", lib_module);
    hubproxy_module.addOptions("build_options", build_options);
    const hubproxy_tests = b.addTest(.{
        .root_module = hubproxy_module,
    });
    const run_hubproxy_tests = b.addRunArtifact(hubproxy_tests);
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

fn targetSaStdArchivePath(os_tag: std.Target.Os.Tag) []const u8 {
    return switch (os_tag) {
        .windows => "artifacts/sa_std/sa_std.lib",
        else => "artifacts/sa_std/libsa_std.a",
    };
}

fn targetSaStdRoot(os_tag: std.Target.Os.Tag) []const u8 {
    return switch (os_tag) {
        .windows => "src/runtime/sa_std_windows.zig",
        else => "src/runtime/sa_std.zig",
    };
}

fn defaultLlvmIncludeDir(os_tag: std.Target.Os.Tag) []const u8 {
    return switch (os_tag) {
        .windows => "C:/LLVM-14/include",
        else => "/usr/lib/llvm-14/include",
    };
}

fn defaultLlvmLibDir(os_tag: std.Target.Os.Tag) []const u8 {
    return switch (os_tag) {
        .windows => "C:/LLVM-14/lib",
        else => "/usr/lib/llvm-14/lib",
    };
}

fn defaultLlvmLibName(os_tag: std.Target.Os.Tag) []const u8 {
    return switch (os_tag) {
        .windows => "LLVM-C",
        else => "LLVM-14",
    };
}

fn validateLlvmConfig(
    b: *std.Build,
    os_tag: std.Target.Os.Tag,
    enable_llvm: bool,
    include_dir: []const u8,
    lib_dir: []const u8,
    lib_name: []const u8,
) void {
    if (!enable_llvm) return;

    const core_header = std.fs.path.join(b.allocator, &.{ include_dir, "llvm-c", "Core.h" }) catch |err| {
        failLlvmConfig("failed to construct LLVM include path: {s}", .{@errorName(err)});
    };
    defer b.allocator.free(core_header);
    std.fs.cwd().access(core_header, .{}) catch |err| {
        failLlvmConfig(
            "LLVM-C header not found: {s}\n  pass -Dllvm-include-dir=<path-to-llvm-include> or use -Dllvm=false for the bootstrap compiler ({s})",
            .{ core_header, @errorName(err) },
        );
    };

    std.fs.cwd().access(lib_dir, .{}) catch |err| {
        failLlvmConfig(
            "LLVM library directory not found: {s}\n  pass -Dllvm-lib-dir=<path-to-llvm-lib> or use -Dllvm=false for the bootstrap compiler ({s})",
            .{ lib_dir, @errorName(err) },
        );
    };

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

fn failLlvmConfig(comptime fmt: []const u8, args: anytype) noreturn {
    std.debug.print("error: LLVM-C backend configuration failed\n  " ++ fmt ++ "\n", args);
    std.process.exit(1);
}

fn llvmLibraryExists(b: *std.Build, os_tag: std.Target.Os.Tag, lib_dir: []const u8, lib_name: []const u8) bool {
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
        std.fs.cwd().access(path, .{}) catch continue;
        return true;
    }
    if (os_tag == .linux or os_tag == .macos) {
        if (versionedSharedLibraryExists(b.allocator, os_tag, lib_dir, lib_name)) return true;
    }
    return false;
}

fn versionedSharedLibraryExists(allocator: std.mem.Allocator, os_tag: std.Target.Os.Tag, lib_dir: []const u8, lib_name: []const u8) bool {
    var dir = std.fs.cwd().openDir(lib_dir, .{ .iterate = true }) catch return false;
    defer dir.close();
    const prefix = switch (os_tag) {
        .linux => std.fmt.allocPrint(allocator, "lib{s}.so.", .{lib_name}) catch return false,
        .macos => std.fmt.allocPrint(allocator, "lib{s}.", .{lib_name}) catch return false,
        else => return false,
    };
    defer allocator.free(prefix);
    var it = dir.iterate();
    while (it.next() catch null) |entry| {
        if (entry.kind == .file or entry.kind == .sym_link) {
            if (std.mem.startsWith(u8, entry.name, prefix)) return true;
        }
    }
    return false;
}

fn llvmLibraryCandidateApplies(os_tag: std.Target.Os.Tag, candidate: []const u8) bool {
    return switch (os_tag) {
        .windows => std.mem.endsWith(u8, candidate, ".lib") or std.mem.endsWith(u8, candidate, ".dll.a") or !std.mem.containsAtLeast(u8, candidate, 1, "."),
        .linux => std.mem.endsWith(u8, candidate, ".so") or std.mem.endsWith(u8, candidate, ".a") or !std.mem.containsAtLeast(u8, candidate, 1, "."),
        .macos => std.mem.endsWith(u8, candidate, ".dylib") or std.mem.endsWith(u8, candidate, ".a") or !std.mem.containsAtLeast(u8, candidate, 1, "."),
        else => true,
    };
}

fn addLlvmcSupportToModule(
    b: *std.Build,
    module: *std.Build.Module,
    enable_llvm: bool,
    include_dir: []const u8,
    lib_dir: []const u8,
    lib_name: []const u8,
) void {
    if (enable_llvm) {
        module.addCSourceFile(.{ .file = b.path("src/emit_llvm_llvmc_shim.c"), .flags = &.{} });
        linkLLVMToModule(module, include_dir, lib_dir, lib_name);
    } else {
        module.addCSourceFile(.{ .file = b.path("src/emit_llvm_llvmc_stub.c"), .flags = &.{} });
    }
}

fn addHostThreadShimToModule(b: *std.Build, module: *std.Build.Module, os_tag: std.Target.Os.Tag) void {
    switch (os_tag) {
        .windows => {},
        else => module.addCSourceFile(.{ .file = b.path("src/runtime/sa_pthread_host.c"), .flags = &.{} }),
    }
}

fn linkLLVMToModule(module: *std.Build.Module, include_dir: []const u8, lib_dir: []const u8, lib_name: []const u8) void {
    module.addSystemIncludePath(.{ .cwd_relative = include_dir });
    module.addLibraryPath(.{ .cwd_relative = lib_dir });
    module.linkSystemLibrary(lib_name, .{});
}

fn linkLLVMToCompile(compile: *std.Build.Step.Compile, enable_llvm: bool, include_dir: []const u8, lib_dir: []const u8, lib_name: []const u8) void {
    if (!enable_llvm) return;
    compile.addSystemIncludePath(.{ .cwd_relative = include_dir });
    compile.addLibraryPath(.{ .cwd_relative = lib_dir });
    compile.linkSystemLibrary(lib_name);
}

fn addLlvmBinDirToRun(
    b: *std.Build,
    run: *std.Build.Step.Run,
    enable_llvm: bool,
    lib_dir: []const u8,
    os_tag: std.Target.Os.Tag,
) void {
    if (!enable_llvm or os_tag != .windows) return;
    const llvm_root_dir = std.fs.path.dirname(lib_dir) orelse lib_dir;
    run.addPathDir(b.pathJoin(&.{ llvm_root_dir, "bin" }));
}

/// On Windows, `sa.exe` is linked against the LLVM-C import library but the
/// runtime DLL lives in `<llvm-lib-dir-父>/bin/LLVM-C.dll`. Without it next to
/// the executable the binary fails to start in any environment that does not
/// already have that LLVM install on PATH (e.g. a fresh clone, the distributable
/// zip produced by `tools/make_windows_dist.bat`, or CI). This step installs the
/// DLL alongside `sa.exe` so the install prefix is self-contained.
fn installLlvmCDll(
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

fn linkWindowsNetworkingToCompile(compile: *std.Build.Step.Compile, os_tag: std.Target.Os.Tag) void {
    if (os_tag != .windows) return;
    compile.linkSystemLibrary("ws2_32");
    compile.linkSystemLibrary("iphlpapi");
}

