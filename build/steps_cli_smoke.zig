const BuildCtx = @import("ctx.zig").BuildCtx;
const addLlvmBinDirToRun = @import("llvm.zig").addLlvmBinDirToRun;

/// build.zig lines 701-910.
pub fn buildCliSmokeTests(ctx: *BuildCtx) void {
    const b = ctx.b;
    const target = ctx.target;
    const optimize = ctx.optimize;
    const enable_llvm = ctx.enable_llvm;
    const llvm_lib_dir = ctx.llvm_lib_dir;
    const repo_root_lazy = ctx.repo_root_lazy;
    const build_options = ctx.build_options;
    const sio_module = ctx.sio_module;
    const lib_module = ctx.lib_module;
    const test_step = ctx.test_step;
    const sync_sa_std_artifact = ctx.sync_sa_std_artifact;

    const cli_smoke_module = b.createModule(.{
        .root_source_file = b.path("tests/cli_smoke.zig"),
        .target = target,
        .optimize = optimize,
    });
    cli_smoke_module.addImport("sio", sio_module);
    cli_smoke_module.addImport("saasm", lib_module);
    cli_smoke_module.addOptions("build_options", build_options);
    const cli_smoke = b.addTest(.{
        .root_module = cli_smoke_module,
        .filters = &.{
            "bc2sa translates real llvm bitcode",
            "bc2sa translates clang cmake bitcode demo",
            "bc2sa translates sqlite3 api probe bitcode",
            "cli build-exe prunes unused imported functions before llvm emission",
            "extern i32 fallible return uses ABI-aligned payload offset",
            "indirect calls shadowed by an early import resolve to valued callees",
        },
    });
    const run_cli_smoke = b.addRunArtifact(cli_smoke);
    run_cli_smoke.setCwd(repo_root_lazy);
    addLlvmBinDirToRun(b, run_cli_smoke, enable_llvm, llvm_lib_dir, target.result.os.tag);
    run_cli_smoke.step.dependOn(&sync_sa_std_artifact.step);
    if (enable_llvm) test_step.dependOn(&run_cli_smoke.step);
    const cli_smoke_step = b.step("bc2sa-smoke", "Run the bc2sa real bitcode smoke tests");
    cli_smoke_step.dependOn(&run_cli_smoke.step);

    const wasm32_std_smoke_module = b.createModule(.{
        .root_source_file = b.path("tests/cli_smoke.zig"),
        .target = target,
        .optimize = optimize,
    });
    wasm32_std_smoke_module.addImport("sio", sio_module);
    wasm32_std_smoke_module.addImport("saasm", lib_module);
    wasm32_std_smoke_module.addOptions("build_options", build_options);
    const wasm32_std_smoke = b.addTest(.{
        .root_module = wasm32_std_smoke_module,
        .filters = &.{
            "wasm32 ptr slot convention: MAP_FAILED sentinel checks fire (DEF-WASM32-PTR-REPR)",
            "wasm32 std size_t conversion sites run end to end (DEF-WASM32-STD-WASM-USEAFTERMOVE)",
        },
    });
    const run_wasm32_std_smoke = b.addRunArtifact(wasm32_std_smoke);
    run_wasm32_std_smoke.setCwd(repo_root_lazy);
    addLlvmBinDirToRun(b, run_wasm32_std_smoke, enable_llvm, llvm_lib_dir, target.result.os.tag);
    run_wasm32_std_smoke.step.dependOn(&sync_sa_std_artifact.step);
    if (enable_llvm) test_step.dependOn(&run_wasm32_std_smoke.step);
    const wasm32_std_smoke_step = b.step("wasm32-std-smoke", "Run wasm32 std archive end-to-end smoke tests");
    wasm32_std_smoke_step.dependOn(&run_wasm32_std_smoke.step);

    const cli_json_debug_smoke_module = b.createModule(.{
        .root_source_file = b.path("tests/cli_smoke.zig"),
        .target = target,
        .optimize = optimize,
    });
    cli_json_debug_smoke_module.addImport("sio", sio_module);
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
    cli_skills_smoke_module.addImport("sio", sio_module);
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
    cli_host_basic_module.addImport("sio", sio_module);
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
    ctx.run_cli_host_basic = run_cli_host_basic;
    run_cli_host_basic.setCwd(repo_root_lazy);
    addLlvmBinDirToRun(b, run_cli_host_basic, enable_llvm, llvm_lib_dir, target.result.os.tag);
    const cli_host_basic_step = b.step("cli-host-basic", "Run host-portable CLI compatibility smoke tests");
    cli_host_basic_step.dependOn(&run_cli_host_basic.step);

    const workspace_smoke_module = b.createModule(.{
        .root_source_file = b.path("tests/cli_smoke.zig"),
        .target = target,
        .optimize = optimize,
    });
    workspace_smoke_module.addImport("sio", sio_module);
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

    const toolchain_u1u2_module = b.createModule(.{
        .root_source_file = b.path("tests/cli_smoke.zig"),
        .target = target,
        .optimize = optimize,
    });
    toolchain_u1u2_module.addImport("sio", sio_module);
    toolchain_u1u2_module.addImport("saasm", lib_module);
    toolchain_u1u2_module.addOptions("build_options", build_options);
    const toolchain_u1u2_smoke = b.addTest(.{
        .root_module = toolchain_u1u2_module,
        .filters = &.{
            "cli pkg add records the require line and pkg list reads it back",
            "cli cache clean --all removes the project .sla-cache only on request",
            "cli build-exe cache key separates plain and release-small",
            "cli help surfaces lifecycle routing, pkg aliases, and plugin confirm",
        },
    });
    const run_toolchain_u1u2_smoke = b.addRunArtifact(toolchain_u1u2_smoke);
    run_toolchain_u1u2_smoke.setCwd(repo_root_lazy);
    addLlvmBinDirToRun(b, run_toolchain_u1u2_smoke, enable_llvm, llvm_lib_dir, target.result.os.tag);
    run_toolchain_u1u2_smoke.step.dependOn(&sync_sa_std_artifact.step);
    test_step.dependOn(&run_toolchain_u1u2_smoke.step);
    const toolchain_u1u2_step = b.step("toolchain-u1u2-smoke", "Run toolchain phase-1 (U1/U2) CLI smoke tests");
    toolchain_u1u2_step.dependOn(&run_toolchain_u1u2_smoke.step);

    const sab_corrupt_smoke_module = b.createModule(.{
        .root_source_file = b.path("tests/cli_smoke.zig"),
        .target = target,
        .optimize = optimize,
    });
    sab_corrupt_smoke_module.addImport("sio", sio_module);
    sab_corrupt_smoke_module.addImport("saasm", lib_module);
    sab_corrupt_smoke_module.addOptions("build_options", build_options);
    const sab_corrupt_smoke = b.addTest(.{
        .root_module = sab_corrupt_smoke_module,
        .filters = &.{"sab with corrupted param_ids traps CorruptedSignature without panic or text fallback"},
    });
    const run_sab_corrupt_smoke = b.addRunArtifact(sab_corrupt_smoke);
    run_sab_corrupt_smoke.setCwd(repo_root_lazy);
    addLlvmBinDirToRun(b, run_sab_corrupt_smoke, enable_llvm, llvm_lib_dir, target.result.os.tag);
    test_step.dependOn(&run_sab_corrupt_smoke.step);
    const sab_corrupt_smoke_step = b.step("sab-corrupt-smoke", "Run the corrupted SAB param_ids regression smoke test");
    sab_corrupt_smoke_step.dependOn(&run_sab_corrupt_smoke.step);

    const pthread_vtable_smoke_module = b.createModule(.{
        .root_source_file = b.path("tests/cli_smoke.zig"),
        .target = target,
        .optimize = optimize,
    });
    pthread_vtable_smoke_module.addImport("sio", sio_module);
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

    const arc_double_free_smoke_module = b.createModule(.{
        .root_source_file = b.path("tests/cli_smoke.zig"),
        .target = target,
        .optimize = optimize,
    });
    arc_double_free_smoke_module.addImport("sio", sio_module);
    arc_double_free_smoke_module.addImport("saasm", lib_module);
    arc_double_free_smoke_module.addOptions("build_options", build_options);
    const arc_double_free_smoke = b.addTest(.{
        .root_module = arc_double_free_smoke_module,
        .filters = &.{
            "sa test arc drop frees once (task 104 regression)",
            "sa test barrier123 three workers drop Arc once (task 125 regression)",
        },
    });
    const run_arc_double_free_smoke = b.addRunArtifact(arc_double_free_smoke);
    run_arc_double_free_smoke.setCwd(repo_root_lazy);
    addLlvmBinDirToRun(b, run_arc_double_free_smoke, enable_llvm, llvm_lib_dir, target.result.os.tag);
    test_step.dependOn(&run_arc_double_free_smoke.step);
    const arc_double_free_smoke_step = b.step("arc-double-free-smoke", "Run the Arc drop double-free regression smoke test (task 104)");
    arc_double_free_smoke_step.dependOn(&run_arc_double_free_smoke.step);

    const trap_baseline_module = b.createModule(.{
        .root_source_file = b.path("tests/golden/trap_baseline.zig"),
        .target = target,
        .optimize = optimize,
    });
    trap_baseline_module.addImport("sio", sio_module);
    trap_baseline_module.addImport("saasm", lib_module);
    trap_baseline_module.addOptions("build_options", build_options);
    const trap_baseline = b.addTest(.{
        .root_module = trap_baseline_module,
    });
    const run_trap_baseline = b.addRunArtifact(trap_baseline);
    ctx.run_trap_baseline = run_trap_baseline;
    run_trap_baseline.setCwd(repo_root_lazy);
    addLlvmBinDirToRun(b, run_trap_baseline, enable_llvm, llvm_lib_dir, target.result.os.tag);
    test_step.dependOn(&run_trap_baseline.step);
    const trap_baseline_step = b.step("trap-baseline", "Run golden trap diagnostic baseline tests");
    trap_baseline_step.dependOn(&run_trap_baseline.step);
}
