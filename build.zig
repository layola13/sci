const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const release_small = b.option(bool, "release-small", "Build all artifacts with ReleaseSmall optimization.") orelse false;
    var optimize = b.standardOptimizeOption(.{});
    if (release_small) optimize = .ReleaseSmall;
    const repo_root = b.path(".");
    const build_options = b.addOptions();
    build_options.addOption([]const u8, "sa_std_archive_path", b.pathFromRoot("artifacts/sa_std/libsa_std.a"));

    const lib_module = b.createModule(.{
        .root_source_file = b.path("src/lib.zig"),
        .target = target,
        .optimize = optimize,
    });
    lib_module.addOptions("build_options", build_options);

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
    const sa_std_static = b.addLibrary(.{
        .name = "sa_std",
        .root_module = sa_std_static_module,
        .linkage = .static,
    });
    const install_sa_std_static = b.addInstallArtifact(sa_std_static, .{});
    b.getInstallStep().dependOn(&install_sa_std_static.step);

    const sa_std_shared_module = b.createModule(.{
        .root_source_file = b.path("src/runtime/sa_std.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
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

    const tests = b.addTest(.{
        .root_module = lib_module,
    });
    const run_tests = b.addRunArtifact(tests);
    run_tests.setCwd(repo_root);
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_tests.step);

    const cli_module = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    cli_module.addOptions("build_options", build_options);
    const exe = b.addExecutable(.{
        .name = "saasm",
        .root_module = cli_module,
    });
    b.installArtifact(exe);

    const cli_tests_module = b.createModule(.{
        .root_source_file = b.path("tests/cli_smoke.zig"),
        .target = target,
        .optimize = optimize,
    });
    cli_tests_module.addImport("saasm", lib_module);
    const cli_tests = b.addTest(.{
        .root_module = cli_tests_module,
    });
    const run_cli_tests = b.addRunArtifact(cli_tests);
    run_cli_tests.setCwd(repo_root);
    test_step.dependOn(&run_cli_tests.step);

    const trap_baseline_module = b.createModule(.{
        .root_source_file = b.path("tests/golden/trap_baseline.zig"),
        .target = target,
        .optimize = optimize,
    });
    trap_baseline_module.addImport("saasm", lib_module);
    const trap_baseline = b.addTest(.{
        .root_module = trap_baseline_module,
    });
    const run_trap_baseline = b.addRunArtifact(trap_baseline);
    run_trap_baseline.setCwd(repo_root);
    test_step.dependOn(&run_trap_baseline.step);

    const std_smoke_module = b.createModule(.{
        .root_source_file = b.path("tests/std_smoke.zig"),
        .target = target,
        .optimize = optimize,
    });
    std_smoke_module.addImport("saasm", lib_module);
    const std_smoke = b.addTest(.{
        .root_module = std_smoke_module,
    });
    const run_std_smoke = b.addRunArtifact(std_smoke);
    run_std_smoke.setCwd(repo_root);
    test_step.dependOn(&run_std_smoke.step);

    const unit_framework_module = b.createModule(.{
        .root_source_file = b.path("tests/unit_framework/runner.zig"),
        .target = target,
        .optimize = optimize,
    });
    unit_framework_module.addImport("saasm", lib_module);
    const unit_framework = b.addTest(.{
        .root_module = unit_framework_module,
    });
    const run_unit_framework = b.addRunArtifact(unit_framework);
    run_unit_framework.setCwd(repo_root);
    test_step.dependOn(&run_unit_framework.step);

    const sa_std_unit_module = b.createModule(.{
        .root_source_file = b.path("src/runtime/sa_std.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    const sa_std_unit = b.addTest(.{
        .root_module = sa_std_unit_module,
    });
    const run_sa_std_unit = b.addRunArtifact(sa_std_unit);
    run_sa_std_unit.setCwd(repo_root);
    test_step.dependOn(&run_sa_std_unit.step);

    const sa_std_runtime_module = b.createModule(.{
        .root_source_file = b.path("tests/sa_std_runtime.zig"),
        .target = target,
        .optimize = optimize,
    });
    const sa_std_runtime = b.addTest(.{
        .root_module = sa_std_runtime_module,
    });
    const run_sa_std_runtime = b.addRunArtifact(sa_std_runtime);
    run_sa_std_runtime.setCwd(repo_root);
    test_step.dependOn(&run_sa_std_runtime.step);

    const sa_net_uring_module = b.createModule(.{
        .root_source_file = b.path("src/runtime/sa_net_uring.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    const sa_net_uring_tests = b.addTest(.{
        .root_module = sa_net_uring_module,
    });
    const run_sa_net_uring_tests = b.addRunArtifact(sa_net_uring_tests);
    run_sa_net_uring_tests.setCwd(repo_root);
    test_step.dependOn(&run_sa_net_uring_tests.step);

    const sa_term_runtime_module = b.createModule(.{
        .root_source_file = b.path("tests/sa_term_runtime.zig"),
        .target = target,
        .optimize = optimize,
    });
    const sa_term_runtime = b.addTest(.{
        .root_module = sa_term_runtime_module,
    });
    const run_sa_term_runtime = b.addRunArtifact(sa_term_runtime);
    run_sa_term_runtime.setCwd(repo_root);
    test_step.dependOn(&run_sa_term_runtime.step);

    const native_sys_runtime_module = b.createModule(.{
        .root_source_file = b.path("tests/native_sys_runtime.zig"),
        .target = target,
        .optimize = optimize,
    });
    const native_sys_runtime = b.addTest(.{
        .root_module = native_sys_runtime_module,
    });
    const run_native_sys_runtime = b.addRunArtifact(native_sys_runtime);
    run_native_sys_runtime.setCwd(repo_root);
    test_step.dependOn(&run_native_sys_runtime.step);

    const std_smoke_step = b.step("std-smoke", "Run the SA standard library smoke tests");
    std_smoke_step.dependOn(&run_std_smoke.step);

    const std_step = b.step("std", "Run the SA standard library and runtime checks");
    std_step.dependOn(&run_std_smoke.step);
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
    const run_smoke = b.addRunArtifact(smoke);
    run_smoke.setCwd(repo_root);
    const smoke_step = b.step("smoke", "Run smoke tests");
    smoke_step.dependOn(&run_smoke.step);
    smoke_step.dependOn(&run_std_smoke.step);
    test_step.dependOn(&run_smoke.step);

    const scope_demo = b.addTest(.{
        .root_source_file = b.path("tests/libsa_scope_demo.zig"),
        .target = target,
        .optimize = optimize,
    });
    const run_scope_demo = b.addRunArtifact(scope_demo);
    run_scope_demo.setCwd(repo_root);
    test_step.dependOn(&run_scope_demo.step);

    const ffi_handle_demo_module = b.createModule(.{
        .root_source_file = b.path("tests/integration/ffi_handle_demo.zig"),
        .target = target,
        .optimize = optimize,
    });
    ffi_handle_demo_module.addImport("saasm", lib_module);
    const ffi_handle_demo = b.addTest(.{
        .root_module = ffi_handle_demo_module,
    });
    const run_ffi_handle_demo = b.addRunArtifact(ffi_handle_demo);
    run_ffi_handle_demo.setCwd(repo_root);
    test_step.dependOn(&run_ffi_handle_demo.step);

    const referee_loc_lint = b.addSystemCommand(&.{ "zig", "run", "tools/referee_loc_lint.zig" });
    referee_loc_lint.setCwd(repo_root);
    const ci_step = b.step("ci", "Run the v0.1 CI gate");
    ci_step.dependOn(&run_tests.step);
    ci_step.dependOn(&run_cli_tests.step);
    ci_step.dependOn(&run_trap_baseline.step);
    ci_step.dependOn(&run_std_smoke.step);
    ci_step.dependOn(&run_unit_framework.step);
    ci_step.dependOn(&run_sa_std_unit.step);
    ci_step.dependOn(&run_sa_std_runtime.step);
    ci_step.dependOn(&run_sa_net_uring_tests.step);
    ci_step.dependOn(&run_sa_term_runtime.step);
    ci_step.dependOn(&run_native_sys_runtime.step);
    ci_step.dependOn(&run_smoke.step);
    ci_step.dependOn(&run_scope_demo.step);
    ci_step.dependOn(&run_ffi_handle_demo.step);
    ci_step.dependOn(&referee_loc_lint.step);

    const bench_step = b.addSystemCommand(&.{ "zig", "run", "bench/task_6_26.zig", "--", "--lines", "64" });
    bench_step.setCwd(repo_root);
    ci_step.dependOn(&bench_step.step);
}
