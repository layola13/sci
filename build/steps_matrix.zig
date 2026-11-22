const BuildCtx = @import("ctx.zig").BuildCtx;
const addLlvmBinDirToRun = @import("llvm.zig").addLlvmBinDirToRun;

/// build.zig lines 581-700.
pub fn buildMatrixTests(ctx: *BuildCtx) void {
    const b = ctx.b;
    const target = ctx.target;
    const optimize = ctx.optimize;
    const enable_llvm = ctx.enable_llvm;
    const llvm_lib_dir = ctx.llvm_lib_dir;
    const repo_root_lazy = ctx.repo_root_lazy;
    const build_options = ctx.build_options;
    const test_build_options = ctx.test_build_options;
    const sio_module = ctx.sio_module;
    const lib_module = ctx.lib_module;
    const test_step = ctx.test_step;
    const sync_sa_std_artifact = ctx.sync_sa_std_artifact;

    const wasm_matrix_module = b.createModule(.{
        .root_source_file = b.path("tests/wasm_matrix_smoke.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    wasm_matrix_module.addImport("sio", sio_module);
    wasm_matrix_module.addImport("saasm", lib_module);
    wasm_matrix_module.addOptions("build_options", build_options);
    const wasm_matrix = b.addTest(.{
        .root_module = wasm_matrix_module,
    });
    const run_wasm_matrix = b.addRunArtifact(wasm_matrix);
    ctx.run_wasm_matrix = run_wasm_matrix;
    run_wasm_matrix.setCwd(repo_root_lazy);
    addLlvmBinDirToRun(b, run_wasm_matrix, enable_llvm, llvm_lib_dir, target.result.os.tag);
    // Shard selector for the long wasm demo matrix ("i/n"); empty runs all.
    // Passed as an explicit env var (not inherited) so each shard gets its
    // own run-step fingerprint instead of a false cache hit.
    run_wasm_matrix.setEnvironmentVariable("SA_WASM_MATRIX_SHARD", b.option([]const u8, "wasm-matrix-shard", "Run only wasm matrix demos with sequence number seq % n == i (\"i/n\").") orelse "");
    run_wasm_matrix.step.name = "wasm-matrix";
    test_step.dependOn(&run_wasm_matrix.step);
    const wasm_matrix_step = b.step("wasm-matrix", "Run LLVM-C native/wasm32 demo equivalence matrix");
    wasm_matrix_step.dependOn(&run_wasm_matrix.step);

    const js_matrix_module = b.createModule(.{
        .root_source_file = b.path("tests/js_matrix_smoke.zig"),
        .target = target,
        .optimize = optimize,
    });
    js_matrix_module.addImport("sio", sio_module);
    js_matrix_module.addImport("saasm", lib_module);
    js_matrix_module.addOptions("build_options", build_options);
    const js_matrix = b.addTest(.{
        .root_module = js_matrix_module,
    });
    const run_js_matrix = b.addRunArtifact(js_matrix);
    run_js_matrix.setCwd(repo_root_lazy);
    addLlvmBinDirToRun(b, run_js_matrix, enable_llvm, llvm_lib_dir, target.result.os.tag);
    // Shard selector for the long JS demo matrix ("i/n"); empty runs all.
    // Explicit env var so each shard gets its own run-step fingerprint.
    run_js_matrix.setEnvironmentVariable("SA_JS_MATRIX_SHARD", b.option([]const u8, "js-matrix-shard", "Run only JS matrix demos with sequence number seq % n == i (\"i/n\").") orelse "");
    run_js_matrix.step.name = "js-matrix";
    run_js_matrix.step.dependOn(&sync_sa_std_artifact.step);
    test_step.dependOn(&run_js_matrix.step);
    const js_matrix_step = b.step("js-matrix", "Run JS backend demo equivalence matrix under node");
    js_matrix_step.dependOn(&run_js_matrix.step);

    const emit_sab_inprocess_module = b.createModule(.{
        .root_source_file = b.path("tests/emit_sab_inprocess_smoke.zig"),
        .target = target,
        .optimize = optimize,
    });
    emit_sab_inprocess_module.addImport("sio", sio_module);
    emit_sab_inprocess_module.addImport("saasm", lib_module);
    emit_sab_inprocess_module.addOptions("build_options", build_options);
    const emit_sab_inprocess = b.addTest(.{
        .root_module = emit_sab_inprocess_module,
    });
    const run_emit_sab_inprocess = b.addRunArtifact(emit_sab_inprocess);
    run_emit_sab_inprocess.setCwd(repo_root_lazy);
    addLlvmBinDirToRun(b, run_emit_sab_inprocess, enable_llvm, llvm_lib_dir, target.result.os.tag);
    test_step.dependOn(&run_emit_sab_inprocess.step);
    const emit_sab_inprocess_step = b.step("emit-sab-inprocess-smoke", "Run finding D in-process check --emit-sab regression");
    emit_sab_inprocess_step.dependOn(&run_emit_sab_inprocess.step);

    const fragment_smoke_module = b.createModule(.{
        .root_source_file = b.path("tests/fragment_smoke.zig"),
        .target = target,
        .optimize = optimize,
    });
    fragment_smoke_module.addImport("sio", sio_module);
    fragment_smoke_module.addImport("saasm", lib_module);
    const fragment_smoke = b.addTest(.{
        .root_module = fragment_smoke_module,
    });
    const run_fragment_smoke = b.addRunArtifact(fragment_smoke);
    run_fragment_smoke.setCwd(repo_root_lazy);
    addLlvmBinDirToRun(b, run_fragment_smoke, enable_llvm, llvm_lib_dir, target.result.os.tag);
    test_step.dependOn(&run_fragment_smoke.step);
    const fragment_smoke_step = b.step("fragment-smoke", "Run SAB fragment contract golden and negative corpus");
    fragment_smoke_step.dependOn(&run_fragment_smoke.step);

    const decl_target_smoke_module = b.createModule(.{
        .root_source_file = b.path("tests/decl_target_flatten_smoke.zig"),
        .target = target,
        .optimize = optimize,
    });
    decl_target_smoke_module.addImport("sio", sio_module);
    decl_target_smoke_module.addImport("saasm", lib_module);
    decl_target_smoke_module.addOptions("test_build_options", test_build_options);
    const decl_target_smoke = b.addTest(.{
        .root_module = decl_target_smoke_module,
    });
    const run_decl_target_smoke = b.addRunArtifact(decl_target_smoke);
    run_decl_target_smoke.setCwd(repo_root_lazy);
    test_step.dependOn(&run_decl_target_smoke.step);
    const decl_target_smoke_step = b.step("decl-target-smoke", "Run flattener @target materialization regression (DEF-WASM32-STD-HYBRID-INPROCESS-FLATTEN)");
    decl_target_smoke_step.dependOn(&run_decl_target_smoke.step);

    const c_matrix_module = b.createModule(.{
        .root_source_file = b.path("tests/c_matrix_smoke.zig"),
        .target = target,
        .optimize = optimize,
    });
    c_matrix_module.addImport("sio", sio_module);
    c_matrix_module.addImport("saasm", lib_module);
    c_matrix_module.addOptions("build_options", build_options);
    const c_matrix = b.addTest(.{
        .root_module = c_matrix_module,
    });
    const run_c_matrix = b.addRunArtifact(c_matrix);
    run_c_matrix.setCwd(repo_root_lazy);
    addLlvmBinDirToRun(b, run_c_matrix, enable_llvm, llvm_lib_dir, target.result.os.tag);
    run_c_matrix.setEnvironmentVariable("SA_C_MATRIX_SHARD", b.option([]const u8, "c-matrix-shard", "Run only C matrix demos with sequence number seq % n == i (\"i/n\").") orelse "");
    run_c_matrix.step.name = "c-matrix";
    run_c_matrix.step.dependOn(&sync_sa_std_artifact.step);
    test_step.dependOn(&run_c_matrix.step);
    const c_matrix_step = b.step("c-matrix", "Run C backend demo equivalence matrix under cc");
    c_matrix_step.dependOn(&run_c_matrix.step);
}
