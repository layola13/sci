const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const release_small = b.option(bool, "release-small", "Build all artifacts with ReleaseSmall optimization.") orelse false;
    const version = b.option([]const u8, "version", "SA toolchain semantic version.") orelse "0.0.1";
    const llvm_include_dir = b.option([]const u8, "llvm-include-dir", "LLVM C API include directory.") orelse "/usr/lib/llvm-14/include";
    const llvm_lib_dir = b.option([]const u8, "llvm-lib-dir", "LLVM library directory.") orelse "/usr/lib/llvm-14/lib";
    const llvm_lib_name = b.option([]const u8, "llvm-lib-name", "LLVM system library name.") orelse "LLVM-14";
    var optimize = b.standardOptimizeOption(.{});
    if (release_small) optimize = .ReleaseSmall;
    const repo_root = b.pathFromRoot(".");
    const repo_root_lazy = b.path(".");
    const build_options = b.addOptions();
    const test_build_options = b.addOptions();
    build_options.addOption([]const u8, "sa_std_archive_path", b.pathFromRoot("artifacts/sa_std/libsa_std.a"));
    build_options.addOption([]const u8, "repo_root", repo_root);
    build_options.addOption([]const u8, "version", version);
    test_build_options.addOption([]const u8, "repo_root", repo_root);

    const lib_module = b.createModule(.{
        .root_source_file = b.path("src/lib.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    addLlvmcShimToModule(b, lib_module);
    linkLLVMToModule(lib_module, llvm_include_dir, llvm_lib_dir, llvm_lib_name);
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
    test_step.dependOn(&run_lib_root_smoke.step);

    const llvmc_test_module = b.createModule(.{
        .root_source_file = b.path("src/emit_llvm_llvmc.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    addLlvmcShimToModule(b, llvmc_test_module);
    llvmc_test_module.addOptions("build_options", build_options);
    llvmc_test_module.addSystemIncludePath(.{ .cwd_relative = "/usr/lib/llvm-14/include" });
    llvmc_test_module.addLibraryPath(.{ .cwd_relative = "/usr/lib/llvm-14/lib" });
    llvmc_test_module.linkSystemLibrary("LLVM-14", .{});
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
    linkLLVMToModule(cli_module, llvm_include_dir, llvm_lib_dir, llvm_lib_name);
    cli_module.addOptions("build_options", build_options);
    const exe = b.addExecutable(.{
        .name = "sa",
        .root_module = cli_module,
    });
    linkLLVMToCompile(exe, llvm_include_dir, llvm_lib_dir, llvm_lib_name);
    b.installArtifact(exe);

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
    test_step.dependOn(&run_unit_framework.step);

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

    const scope_demo = b.addTest(.{
        .root_source_file = b.path("tests/libsa_scope_demo.zig"),
        .target = target,
        .optimize = optimize,
    });
    scope_demo.root_module.addOptions("build_options", build_options);
    const run_scope_demo = b.addRunArtifact(scope_demo);
    run_scope_demo.setCwd(repo_root_lazy);
    test_step.dependOn(&run_scope_demo.step);

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

    const hubproxy_exe = b.addExecutable(.{
        .name = "hubproxy",
        .root_module = hubproxy_module,
    });
    const install_hubproxy_exe = b.addInstallArtifact(hubproxy_exe, .{});
    b.getInstallStep().dependOn(&install_hubproxy_exe.step);

    const referee_loc_lint = b.addSystemCommand(&.{ "zig", "run", "tools/referee_loc_lint.zig" });
    referee_loc_lint.setCwd(repo_root_lazy);
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
    ci_step.dependOn(&referee_loc_lint.step);
    ci_step.dependOn(&run_wasm_matrix.step);

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

fn linkLLVMToModule(module: *std.Build.Module, include_dir: []const u8, lib_dir: []const u8, lib_name: []const u8) void {
    module.addSystemIncludePath(.{ .cwd_relative = include_dir });
    module.addLibraryPath(.{ .cwd_relative = lib_dir });
    module.linkSystemLibrary(lib_name, .{});
}

fn linkLLVMToCompile(compile: *std.Build.Step.Compile, include_dir: []const u8, lib_dir: []const u8, lib_name: []const u8) void {
    compile.addSystemIncludePath(.{ .cwd_relative = include_dir });
    compile.addLibraryPath(.{ .cwd_relative = lib_dir });
    compile.linkSystemLibrary(lib_name);
}
