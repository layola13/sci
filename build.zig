const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const release_small = b.option(bool, "release-small", "Build all artifacts with ReleaseSmall optimization.") orelse false;
    var optimize = b.standardOptimizeOption(.{});
    if (release_small) optimize = .ReleaseSmall;
    const repo_root = b.pathFromRoot(".");
    const repo_root_lazy = b.path(".");
    const build_options = b.addOptions();
    build_options.addOption([]const u8, "sa_std_archive_path", b.pathFromRoot("artifacts/sa_std/libsa_std.a"));
    build_options.addOption([]const u8, "repo_root", repo_root);
    build_options.addOption([]const u8, "version", "0.0.0");

    const lib_module = b.createModule(.{
        .root_source_file = b.path("src/lib.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    const plugin_api_module = b.createModule(.{
        .root_source_file = b.path("src/plugin.zig"),
        .target = target,
        .optimize = optimize,
    });
    lib_module.addImport("plugin", plugin_api_module);
    lib_module.addOptions("build_options", build_options);
    plugin_api_module.addOptions("build_options", build_options);

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

    const plugin_root = b.step("plugins", "Build and install runtime-loadable plugin libraries");
    const sax_module = b.createModule(.{
        .root_source_file = b.path("src/sax.zig"),
        .target = target,
        .optimize = optimize,
    });
    sax_module.addOptions("build_options", build_options);
    sax_module.addImport("trap", b.createModule(.{
        .root_source_file = b.path("src/common/trap.zig"),
        .target = target,
        .optimize = optimize,
    }));
    sax_module.addImport("driver", b.createModule(.{
        .root_source_file = b.path("src/driver/zigcc.zig"),
        .target = target,
        .optimize = optimize,
    }));
    sax_module.addImport("emit_llvm", b.createModule(.{
        .root_source_file = b.path("src/emit_llvm.zig"),
        .target = target,
        .optimize = optimize,
    }));
    sax_module.addImport("flattener", b.createModule(.{
        .root_source_file = b.path("src/flattener.zig"),
        .target = target,
        .optimize = optimize,
    }));
    sax_module.addImport("manifest", b.createModule(.{
        .root_source_file = b.path("src/pkg/manifest.zig"),
        .target = target,
        .optimize = optimize,
    }));
    sax_module.addImport("pkg_resolver", b.createModule(.{
        .root_source_file = b.path("src/pkg/resolver.zig"),
        .target = target,
        .optimize = optimize,
    }));
    sax_module.addImport("referee", b.createModule(.{
        .root_source_file = b.path("src/referee.zig"),
        .target = target,
        .optimize = optimize,
    }));
    const plugin_sources = [_]struct {
        source: []const u8,
        name: []const u8,
    }{
        .{ .source = "src/http_client/plugin.zig", .name = "saasm-http-client" },
        .{ .source = "src/sax_plugin.zig", .name = "saasm-sax" },
        .{ .source = "src/db_plugin.zig", .name = "saasm-db" },
        .{ .source = "src/pkg/plugin.zig", .name = "saasm-pkg" },
        .{ .source = "src/llvm2sa_plugin.zig", .name = "saasm-llvm2sa" },
        .{ .source = "src/http_server/plugin.zig", .name = "saasm-http-server" },
    };
    for (plugin_sources) |entry| {
        const mod = b.createModule(.{
            .root_source_file = b.path(entry.source),
            .target = target,
            .optimize = optimize,
            .link_libc = true,
        });
        mod.addImport("plugin", plugin_api_module);
        mod.addOptions("build_options", build_options);
        const lib_plugin = b.addLibrary(.{
            .name = entry.name,
            .root_module = mod,
            .linkage = .dynamic,
        });
        const install_plugin = b.addInstallArtifact(lib_plugin, .{});
        plugin_root.dependOn(&install_plugin.step);
        b.getInstallStep().dependOn(&install_plugin.step);
    }

    const tests = b.addTest(.{
        .root_module = lib_module,
    });
    const run_tests = b.addRunArtifact(tests);
    run_tests.setCwd(repo_root_lazy);
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(plugin_root);
    test_step.dependOn(&run_tests.step);

    const plugins_tests_module = b.createModule(.{
        .root_source_file = b.path("src/plugins.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    plugins_tests_module.addImport("plugin", plugin_api_module);
    plugins_tests_module.addOptions("build_options", build_options);
    const plugins_tests = b.addTest(.{
        .root_module = plugins_tests_module,
    });
    const run_plugins_tests = b.addRunArtifact(plugins_tests);
    run_plugins_tests.setCwd(repo_root_lazy);
    test_step.dependOn(&run_plugins_tests.step);

    const cli_module = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    cli_module.addImport("plugin", plugin_api_module);
    cli_module.addOptions("build_options", build_options);
    const exe = b.addExecutable(.{
        .name = "sa",
        .root_module = cli_module,
    });
    b.installArtifact(exe);

    const cli_tests_module = b.createModule(.{
        .root_source_file = b.path("tests/cli_smoke.zig"),
        .target = target,
        .optimize = optimize,
    });
    cli_tests_module.addImport("saasm", lib_module);
    cli_tests_module.addOptions("build_options", build_options);
    const cli_tests = b.addTest(.{
        .root_module = cli_tests_module,
    });
    const run_cli_tests = b.addRunArtifact(cli_tests);
    run_cli_tests.setCwd(repo_root_lazy);
    test_step.dependOn(&run_cli_tests.step);

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

    const std_smoke_module = b.createModule(.{
        .root_source_file = b.path("tests/std_smoke.zig"),
        .target = target,
        .optimize = optimize,
    });
    std_smoke_module.addImport("saasm", lib_module);
    std_smoke_module.addOptions("build_options", build_options);
    const std_smoke = b.addTest(.{
        .root_module = std_smoke_module,
    });
    const run_std_smoke = b.addRunArtifact(std_smoke);
    run_std_smoke.setCwd(repo_root_lazy);
    test_step.dependOn(&run_std_smoke.step);

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
    smoke.root_module.addOptions("build_options", build_options);
    const run_smoke = b.addRunArtifact(smoke);
    run_smoke.setCwd(repo_root_lazy);
    const smoke_step = b.step("smoke", "Run smoke tests");
    smoke_step.dependOn(&run_smoke.step);
    smoke_step.dependOn(&run_std_smoke.step);
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
    ci_step.dependOn(&run_hubproxy_tests.step);
    ci_step.dependOn(&referee_loc_lint.step);

    const bench_step = b.addSystemCommand(&.{ "zig", "run", "bench/task_6_26.zig", "--", "--lines", "64" });
    bench_step.setCwd(repo_root_lazy);
    ci_step.dependOn(&bench_step.step);
}
