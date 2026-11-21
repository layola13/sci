const std = @import("std");
const CompileOptions = @import("types.zig").CompileOptions;
const DiagnosticsMode = @import("types.zig").DiagnosticsMode;
const WasmTarget = @import("types.zig").WasmTarget;
const driver = @import("../driver/zigcc.zig");
const sio = @import("sio");
const writeSuccessDiagnostics = @import("errors.zig").writeSuccessDiagnostics;
const writeMemoryStageSampleForOptions = @import("compile.zig").writeMemoryStageSampleForOptions;
const stdRootFromEnv = @import("cache.zig").stdRootFromEnv;
const rejectNpmBindsUnlessJs = @import("compile.zig").rejectNpmBindsUnlessJs;
const recordMetricMemoryEnd = @import("compile.zig").recordMetricMemoryEnd;
const recordMetricMemoryAfterLink = @import("compile.zig").recordMetricMemoryAfterLink;
const recordMetricMemoryAfterEmit = @import("compile.zig").recordMetricMemoryAfterEmit;
const projectCacheHit = @import("compile.zig").projectCacheHit;
const printTrapReport = @import("errors.zig").printTrapReport;
const memoryEndPrevious = @import("types.zig").memoryEndPrevious;
const loadProjectContext = @import("compile.zig").loadProjectContext;
const intermediateArtifactPath = @import("build_lib.zig").intermediateArtifactPath;
const finishProfileMetrics = @import("types.zig").finishProfileMetrics;
const ensureParentDir = @import("compile.zig").ensureParentDir;
const emit_llvm_llvmc = @import("../emit_llvm_llvmc.zig");
const emit_c = @import("../emit_c.zig");
const elapsedNs = @import("compile.zig").elapsedNs;
const computeProjectBuildKey = @import("compile.zig").computeProjectBuildKey;
const compileSource = @import("compile.zig").compileSource;
const build_options = @import("build_options");
const attachBackendIrMetrics = @import("compile.zig").attachBackendIrMetrics;
const ProjectCacheKey = @import("types.zig").ProjectCacheKey;
const CompileMetrics = @import("types.zig").CompileMetrics;
const BuildCacheKind = @import("types.zig").BuildCacheKind;
const projectRootFromSourcePath = @import("compile.zig").projectRootFromSourcePath;
const cacheHitMemoryMetrics = @import("build_exe.zig").cacheHitMemoryMetrics;
const CompileMemoryMetrics = @import("types.zig").CompileMemoryMetrics;
const printStageTiming = @import("types.zig").printStageTiming;
const stageTimingEnabled = @import("compile.zig").stageTimingEnabled;
const saStdArchivePathForTarget = @import("compile.zig").saStdArchivePathForTarget;
const cguSeqShardCount = @import("compile.zig").cguSeqShardCount;
const wasmStdArchivePath = @import("build_exe.zig").wasmStdArchivePath;
const makeExecutable = @import("build_exe.zig").makeExecutable;
const emitOptLevel = @import("build_exe.zig").emitOptLevel;
const buildIncrementalObject = @import("build_exe.zig").buildIncrementalObject;
const collectExternalSymbolNames = @import("build_exe.zig").collectExternalSymbolNames;
const appendNativePluginLinkInputs = @import("build_exe.zig").appendNativePluginLinkInputs;
const projectCacheStore = @import("cache.zig").projectCacheStore;
const printLlvmcEmitError = @import("errors.zig").printLlvmcEmitError;

pub fn executeBuildWasm(allocator: std.mem.Allocator, source_path: []const u8, out_path: []const u8, target: WasmTarget, debug: bool, optimization: driver.Optimization, compile_options: CompileOptions, stderr: anytype, diagnostics_mode: DiagnosticsMode) !u8 {
    const total_start = if (compile_options.profile) std.Io.Clock.awake.now(sio.io()) else null;
    const project_root_owned = compile_options.project_root == null;
    const project_root = compile_options.project_root orelse try projectRootFromSourcePath(allocator, source_path);
    defer if (project_root_owned) allocator.free(project_root);
    var project_context = try loadProjectContext(allocator, project_root, compile_options.package_name);
    defer project_context.deinit(allocator);
    const cache_key: ?ProjectCacheKey = if (compile_options.incremental_cache)
        try computeProjectBuildKey(allocator, &project_context, project_root, source_path, "wasm", target.triple, .build_wasm, debug, optimization == .release_fast, false, target, true, compile_options.offline, compile_options.dce, compile_options.default_immutable, compile_options.fast_math)
    else
        null;
    const artifact_path = try intermediateArtifactPath(allocator, out_path);
    defer allocator.free(artifact_path);

    if (cache_key) |key| {
        if (try projectCacheHit(allocator, project_root, .build_wasm, key, artifact_path, out_path)) {
            if (diagnostics_mode == .json or compile_options.mem_report) {
                const metrics = CompileMetrics{ .compile_tokens = 0, .instruction_count = 0, .phases = if (compile_options.profile) .{ .load_ns = 0, .setup_ns = 0, .flatten_ns = 0, .verify_ns = 0, .emit_ns = 0, .link_ns = 0, .total_ns = if (total_start) |start| elapsedNs(start) else null } else null, .memory = cacheHitMemoryMetrics(compile_options.mem_report), .cache = .{ .kind = BuildCacheKind.build_wasm.dirName(), .hit = true } };
                try writeSuccessDiagnostics(stderr, metrics, diagnostics_mode);
            }
            return 0;
        }
    }

    const compiled = try compileSource(allocator, source_path, compile_options);
    switch (compiled) {
        .trap => |report| {
            try printTrapReport(stderr, report, diagnostics_mode);
            return 1;
        },
        .ok => |ok| {
            var owned = ok;
            defer owned.deinit(allocator);
            rejectNpmBindsUnlessJs("sa build-wasm", &owned.flat, stderr) catch return 1;
            if (comptime !build_options.llvm_enabled) {
                // LLVM-C is unavailable in this build. Reuse the pure-Zig C
                // backend and let `zig cc` lower the portable C to wasm, so
                // `build-wasm` still produces a runnable module without LLVM.
                const c_path = try std.fmt.allocPrint(allocator, "{s}.wasm.c", .{artifact_path});
                defer allocator.free(c_path);
                defer sio.cwd().deleteFile(c_path) catch {};
                try ensureParentDir(c_path);
                const emit_start = if (compile_options.profile) std.Io.Clock.awake.now(sio.io()) else null;
                emit_c.emitCToFile(allocator, owned.verified, source_path, target.size_bits, .{ .debug_comments = debug }, c_path) catch |err| {
                    try stderr.print("error: C backend emit failed: {s}", .{@errorName(err)});
                    if (emit_c.last_c_func.len != 0) try stderr.print(" in {s}", .{emit_c.last_c_func});
                    if (emit_c.last_c_inst.len != 0) try stderr.print(": {s}", .{std.mem.trim(u8, emit_c.last_c_inst, " \t\r\n")});
                    try stderr.writeAll("\n");
                    try stderr.writeAll("hint: this sa build has no LLVM-C backend, so wasm fell back to the limited C emitter; rebuild with -Dllvm=true for full wasm support\n");
                    return 1;
                };
                const emit_ns = if (emit_start) |start| elapsedNs(start) else null;
                recordMetricMemoryAfterEmit(&owned.metrics);
                if (owned.metrics.memory) |memory| try writeMemoryStageSampleForOptions(compile_options, "after_emit", memory.after_emit_rss_bytes, memory.after_verify_rss_bytes);

                const c_std_archive_path: ?[]u8 = wasmStdArchivePath(allocator, target, stderr) catch return 1;
                defer if (c_std_archive_path) |p| allocator.free(p);
                const link_start = if (compile_options.profile) std.Io.Clock.awake.now(sio.io()) else null;
                driver.compileWasm(allocator, c_path, out_path, .{ .triple = target.triple, .no_entry = target.no_entry }, optimization, debug, c_std_archive_path, stderr) catch |err| switch (err) {
                    error.ChildProcessFailed => return 1,
                    else => return err,
                };
                const link_ns = if (link_start) |start| elapsedNs(start) else null;
                recordMetricMemoryAfterLink(&owned.metrics);
                recordMetricMemoryEnd(&owned.metrics);
                if (owned.metrics.memory) |memory| try writeMemoryStageSampleForOptions(compile_options, "end", memory.end_rss_bytes, memoryEndPrevious(memory));
                finishProfileMetrics(&owned.metrics, emit_ns, link_ns, if (total_start) |start| elapsedNs(start) else null);
                attachBackendIrMetrics(&owned.metrics, &owned.verified, debug);
                if (cache_key) |key| try projectCacheStore(allocator, project_root, .build_wasm, key, c_path, out_path);
                if (cache_key != null) owned.metrics.cache = .{ .kind = BuildCacheKind.build_wasm.dirName(), .hit = false };
                try writeSuccessDiagnostics(stderr, owned.metrics, diagnostics_mode);
                return 0;
            }
            const emit_std_root = try stdRootFromEnv(allocator);
            defer allocator.free(emit_std_root);
            try ensureParentDir(artifact_path);
            const emit_start = if (compile_options.profile) std.Io.Clock.awake.now(sio.io()) else null;
            emit_llvm_llvmc.emitLlvmcToFile(allocator, owned.verified, &owned.flat.def_dict, owned.flat.loc_table, source_path, target.size_bits, .{ .debug = debug, .wasm_compat = true, .jobs = compile_options.jobs, .opt_level = emitOptLevel(debug, optimization), .dce = compile_options.dce, .fast_math = compile_options.fast_math, .std_root = emit_std_root }, artifact_path) catch |err| {
                try printLlvmcEmitError(stderr, err, diagnostics_mode);
                return 1;
            };
            const emit_ns = if (emit_start) |start| elapsedNs(start) else null;
            recordMetricMemoryAfterEmit(&owned.metrics);
            if (owned.metrics.memory) |memory| try writeMemoryStageSampleForOptions(compile_options, "after_emit", memory.after_emit_rss_bytes, memory.after_verify_rss_bytes);

            const std_archive_path: ?[]u8 = wasmStdArchivePath(allocator, target, stderr) catch return 1;
            defer if (std_archive_path) |p| allocator.free(p);
            const link_start = if (compile_options.profile) std.Io.Clock.awake.now(sio.io()) else null;
            driver.compileWasm(allocator, artifact_path, out_path, .{ .triple = target.triple, .no_entry = target.no_entry }, optimization, debug, std_archive_path, stderr) catch |err| switch (err) {
                error.ChildProcessFailed => return 1,
                else => return err,
            };
            const link_ns = if (link_start) |start| elapsedNs(start) else null;
            recordMetricMemoryAfterLink(&owned.metrics);
            if (owned.metrics.memory) |memory| try writeMemoryStageSampleForOptions(compile_options, "after_link", memory.after_link_rss_bytes, memory.after_emit_rss_bytes);
            recordMetricMemoryEnd(&owned.metrics);
            if (owned.metrics.memory) |memory| try writeMemoryStageSampleForOptions(compile_options, "end", memory.end_rss_bytes, memoryEndPrevious(memory));
            finishProfileMetrics(&owned.metrics, emit_ns, link_ns, if (total_start) |start| elapsedNs(start) else null);
            attachBackendIrMetrics(&owned.metrics, &owned.verified, debug);
            if (cache_key) |key| try projectCacheStore(allocator, project_root, .build_wasm, key, artifact_path, out_path);
            if (cache_key != null) owned.metrics.cache = .{ .kind = BuildCacheKind.build_wasm.dirName(), .hit = false };
            try writeSuccessDiagnostics(stderr, owned.metrics, diagnostics_mode);
            return 0;
        },
    }
}
