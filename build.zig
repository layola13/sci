const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const repo_root = b.path(".");

    const lib_module = b.createModule(.{
        .root_source_file = b.path("src/lib.zig"),
        .target = target,
        .optimize = optimize,
    });

    const lib = b.addLibrary(.{
        .name = "sa_asm",
        .root_module = lib_module,
        .linkage = .static,
    });
    b.installArtifact(lib);

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
}
