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
    addLlvmcShimToModule(b, sax_module);
    linkLLVMToModule(sax_module, llvm_include_dir, llvm_lib_dir, llvm_lib_name);
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
        .{ .source = "src/llvm2sa_plugin.zig", .name = "saasm-bc2sa" },
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

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(plugin_root);

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

    const db_exec_smoke_module = b.createModule(.{
        .root_source_file = b.path("tests/db_exec_smoke.zig"),
        .target = target,
        .optimize = optimize,
    });
    db_exec_smoke_module.addImport("saasm", lib_module);
    db_exec_smoke_module.addOptions("build_options", build_options);
    const db_exec_smoke = b.addTest(.{
        .root_module = db_exec_smoke_module,
    });
    const run_db_exec_smoke = b.addRunArtifact(db_exec_smoke);
    run_db_exec_smoke.setCwd(repo_root_lazy);
    test_step.dependOn(&run_db_exec_smoke.step);

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
        .link_libc = true,
    });
    addLlvmcShimToModule(b, cli_module);
    linkLLVMToModule(cli_module, llvm_include_dir, llvm_lib_dir, llvm_lib_name);
    cli_module.addImport("plugin", plugin_api_module);
    cli_module.addOptions("build_options", build_options);
    const exe = b.addExecutable(.{
        .name = "sa",
        .root_module = cli_module,
    });
    linkLLVMToCompile(exe, llvm_include_dir, llvm_lib_dir, llvm_lib_name);
    b.installArtifact(exe);

    const cli_tests_module = b.createModule(.{
        .root_source_file = b.path("tests/cli_smoke.zig"),
        .target = target,
        .optimize = optimize,
    });
    cli_tests_module.addImport("saasm", lib_module);
    cli_tests_module.addOptions("build_options", build_options);
    var cli_smoke_steps = std.ArrayList(*std.Build.Step).init(b.allocator);
    defer cli_smoke_steps.deinit();
    const cli_test_filters = [_]struct { name: []const u8, filters: []const []const u8 }{
        .{ .name = "cli-core", .filters = &.{
            "cli run/build-exe/build-wasm produce real artifacts",
            "cli sax build produces browser bundle artifacts",
            "cli build-exe with jobs 1 and auto produce bitcode artifacts",
            "cli run with jobs 2 keeps the earliest source-order trap",
            "hello world demo prints through sa run",
            "hello world demo prints through build-wasm and node wasi",
            "hello world upstream line can break in gdb",
            "hello compute demo prints through build-exe and build-wasm",
            "trait vtable demo runs through sa run",
            "callback registration demo compiles and prints through build-exe",
            "pkg lib dynamic demo compiles via object archive and prints through native link",
            "comparison alias demos run through sa run",
            "ownership and borrow demos compile and print through build-exe",
            "core control-flow and data demos compile and print through build-exe",
        } },
        .{ .name = "cli-rosetta", .filters = &.{
            "additional rosetta demos compile and print through build-exe",
            "fallible rosetta demos compile and print through build-exe",
            "slice and cache rosetta demos compile and print through build-exe",
            "baseline rosetta demos compile and print through build-exe",
            "break and nested loop rosetta demos compile and print through build-exe",
            "more baseline rosetta demos compile and print through build-exe",
            "more rosetta demos compile and print through build-exe",
            "even more rosetta demos compile and print through build-exe",
            "final rosetta batch compile and print through build-exe",
            "service and concurrency rosetta demos compile and print through build-exe",
            "remaining rosetta demos compile and print through build-exe",
        } },
        .{ .name = "cli-runtime", .filters = &.{
            "async await demo runs through sa run",
            "macro demo compiles and prints through build-exe",
            "sa_core macros compile and print through imported standard library macros",
            "time demo compiles and prints through build-exe",
            "time demo runs through sa run",
            "mutex demo compiles and prints through build-exe",
            "mutex demo runs through sa run",
            "once demo compiles and prints through build-exe",
            "once demo runs through sa run",
            "mpsc demo compiles and prints through build-exe",
            "mpsc demo runs through sa run",
            "io demo compiles and prints through build-exe",
            "hashmap demo compiles and prints through build-exe",
            "hashset demo compiles and prints through build-exe",
            "hashset demo runs through sa run",
            "sort demo compiles and prints through build-exe",
        } },
        .{ .name = "cli-rejects", .filters = &.{
            "use after move demo is rejected with structured trap output",
            "return after move demo is rejected with structured trap output",
            "borrow conflict demo is rejected with structured trap output",
            "read write conflict demo is rejected with structured trap output",
            "illegal unsafe context demo is rejected with structured trap output",
            "stack escape demo is rejected with structured trap output",
            "const mutation demo is rejected with structured trap output",
            "early return leak demo is rejected with structured trap output",
            "macro recursion demo is rejected with structured trap output",
            "forbidden syntax demo is rejected with structured trap output",
            "forbidden if demo is rejected with structured trap output",
            "forbidden while demo is rejected with structured trap output",
            "forbidden for demo is rejected with structured trap output",
            "forbidden brace demo is rejected with structured trap output",
            "forbidden property chain demo is rejected with structured trap output",
            "memory leak after borrow demo is rejected with structured trap output",
            "memory leak partial release demo is rejected with structured trap output",
            "atomic ordering mismatch demo is rejected with structured trap output",
            "invalid atomic ordering demo is rejected with structured trap output",
            "unknown register return demo is rejected with structured trap output",
            "capability mismatch demo is rejected with structured trap output",
            "package and module roadmap demos are rejected with structured trap output",
        } },
        .{ .name = "cli-special", .filters = &.{
            "struct demo runs through sa run",
            "sys runtime demo prints and round-trips file contents",
            "ffi airlock demo preserves pointer values through assume_* in sa run",
            "http client saasm demo builds through plugin-linked native exe",
            "http server saasm demo builds through plugin-linked native exe",
            "panic builtins terminate through the interpreter",
            "sa test runs isolated native tests with filterable names",
            "fallible ABI and ? propagation work end to end",
            "result unwrap_or and map_or helpers branch on tags correctly",
            "const pointer stores survive load and print end to end",
            "vtable loads preserve indirect call provenance end to end",
            "bc2sa rejects bitcode until importer is implemented",
            "import expansion keeps source paths alive end to end",
            "atomic instructions work end to end and emit real LLVM",
            "ptr arithmetic lowers to gep and runs through the interpreter",
            "invalid cmpxchg ordering is rejected by the flattener",
            "atomic ordering mismatch is rejected by the verifier",
            "panic lowers to native executable failure code",
            "raw pointer escape is rejected outside ffi wrapper",
            "extern export ffi wrapper map to real declarations and symbols",
            "unknown sys intrinsic is rejected before emission",
            "external compiler failures report linker context instead of child process noise",
            "unknown register demo is rejected with structured trap output",
            "memory leak demo is rejected with structured trap output",
            "fallthrough demo is rejected without a terminator",
            "duplicate label demo is rejected with structured trap output",
            "phi conflict demo is rejected on mismatched join states",
            "phi join AND demo runs through the join point",
            "build-wasm supports wasm64 freestanding no-entry",
            "cli init creates a binary project and install syncs manifest dependencies",
            "db cli init writes iface and table lifecycle commands update storage",
            "db cli register inspect exec round trip through registry",
            "layout cli prints text, json, and debug macro outputs",
            "agent-first cli commands print explain fix and skills outputs",
            "build and run json diagnostics emit structured success metrics on stderr",
            "graph and size cli emit structured reports for a tiny project",
            "llvmc backend compilation and verification on rosetta demos",
        } },
    };

    for (cli_test_filters) |entry| {
        const mod = b.createModule(.{
            .root_source_file = b.path("tests/cli_smoke.zig"),
            .target = target,
            .optimize = optimize,
        });
        mod.addImport("saasm", lib_module);
        mod.addOptions("build_options", build_options);
        const test_artifact = b.addTest(.{
            .root_module = mod,
            .filters = entry.filters,
        });
        const run_artifact = b.addRunArtifact(test_artifact);
        run_artifact.setCwd(repo_root_lazy);
        run_artifact.step.name = entry.name;
        test_step.dependOn(&run_artifact.step);
        cli_smoke_steps.append(&run_artifact.step) catch @panic("OOM");
    }

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
    ci_step.dependOn(&referee_loc_lint.step);
    for (cli_smoke_steps.items) |step| {
        ci_step.dependOn(step);
    }
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
