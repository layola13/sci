const std = @import("std");
const computeProjectBuildKey = @import("compile.zig").computeProjectBuildKey;
const elapsedNs = @import("compile.zig").elapsedNs;
const ProjectCacheKey = @import("types.zig").ProjectCacheKey;
const sizeBitsForTriple = @import("compile.zig").sizeBitsForTriple;
const loadProjectContext = @import("compile.zig").loadProjectContext;
const ensureParentDir = @import("compile.zig").ensureParentDir;
const stageTimingEnabled = @import("compile.zig").stageTimingEnabled;
const projectRootFromSourcePath = @import("compile.zig").projectRootFromSourcePath;
const printTrapReport = @import("errors.zig").printTrapReport;
const compileSource = @import("compile.zig").compileSource;
const CompileOptions = @import("types.zig").CompileOptions;
const WasmTarget = @import("types.zig").WasmTarget;
const builtin = @import("builtin");
const sio = @import("sio");
const build_options = @import("build_options");
const flattener = @import("../flattener.zig");
const emit_js = @import("../emit_js.zig");
const emit_c = @import("../emit_c.zig");
const emit_llvm_llvmc = @import("../emit_llvm_llvmc.zig");
const emit_options = @import("../emit_options.zig");
const driver = @import("../driver/zigcc.zig");
const bc2sa = @import("../llvm2sa.zig");
const layout = @import("../layout.zig");
const sab = @import("../sab.zig");
const plugins = @import("../plugins.zig");
const DiagnosticsMode = @import("types.zig").DiagnosticsMode;

pub fn executeBuildExe(allocator: std.mem.Allocator, source_path: []const u8, out_path: []const u8, debug: bool, optimization: driver.Optimization, compile_options_in: CompileOptions, stderr: anytype, diagnostics_mode: DiagnosticsMode) !u8 {
    var compile_options = compile_options_in;
    if (stageTimingEnabled()) compile_options.profile = true;
    const total_start = if (compile_options.profile) std.Io.Clock.awake.now(sio.io()) else null;
    const project_root_owned = compile_options.project_root == null;
    const project_root = compile_options.project_root orelse try projectRootFromSourcePath(allocator, source_path);
    defer if (project_root_owned) allocator.free(project_root);
    var project_context = try loadProjectContext(allocator, project_root, compile_options.package_name);
    defer project_context.deinit(allocator);
    const cache_key: ?ProjectCacheKey = if (compile_options.incremental_cache)
        try computeProjectBuildKey(allocator, &project_context, project_root, source_path, "exe", compile_options.target_triple orelse "", .build_exe, debug, optimization == .release_fast, false, null, true, compile_options.offline, compile_options.dce, compile_options.default_immutable, compile_options.fast_math)
    else
        null;
    const artifact_path = try intermediateArtifactPath(allocator, out_path);
    defer allocator.free(artifact_path);

    if (cache_key) |key| {
        if (try projectCacheHit(allocator, project_root, .build_exe, key, artifact_path, out_path)) {
            try makeExecutable(out_path);
            if (diagnostics_mode == .json or compile_options.mem_report) {
                const metrics = CompileMetrics{ .compile_tokens = 0, .instruction_count = 0, .phases = if (compile_options.profile) .{ .load_ns = 0, .setup_ns = 0, .flatten_ns = 0, .verify_ns = 0, .emit_ns = 0, .link_ns = 0, .total_ns = if (total_start) |start| elapsedNs(start) else null } else null, .memory = cacheHitMemoryMetrics(compile_options.mem_report), .cache = .{ .kind = BuildCacheKind.build_exe.dirName(), .hit = true } };
                if (stageTimingEnabled()) printStageTiming(stderr, &metrics);
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
            rejectNpmBindsUnlessJs("sa build-exe", &owned.flat, stderr) catch return 1;
            // verify->emit seam: rejectNpmBindsUnlessJs is the last reader
            // of owned.flat above; everything below consumes owned.verified
            // (plus flat.loc_table / flat.def_dict only). Release the flat
            // instruction store before emit so its residency does not
            // stack under the emit peak.
            owned.releaseFlatInstructions(allocator);
            const emit_std_root = try stdRootFromEnv(allocator);
            defer allocator.free(emit_std_root);
            const std_archive_path = saStdArchivePathForTarget(allocator, compile_options.target_triple) catch |err| {
                if (err == error.ArchiveNotFoundForTarget) {
                    try stderr.print("error: no sa_std archive for target '{s}'. Build it with:\n", .{compile_options.target_triple.?});
                    try stderr.writeAll("  zig build -Dtarget=<triple> sa-std-static\n");
                    try stderr.writeAll("then copy zig-out/lib/<libsa_std.a|sa_std.lib> to $SA_STD_DIR/<triple>/\n");
                    return 1;
                }
                return err;
            };
            defer allocator.free(std_archive_path);
            const size_bits = sizeBitsForTriple(compile_options.target_triple);

            const worker_count = blk: {
                if (compile_options.jobs) |j| {
                    break :blk j;
                }
                break :blk std.Thread.getCpuCount() catch 1;
            };
            const emission_workers = @max(@min(worker_count, 4), 1);
            const seq_shards = cguSeqShardCount();
            const use_cgu = seq_shards != null or (emission_workers > 1 and owned.verified.function_sigs.len >= 100);
            // LINE-PEAK50-EMIT Form 1: sequential shards when explicitly
            // requested (SA_CGU_SEQ_SHARDS wins over the parallel opt-in)
            // or, by default, for large modules (fn count above the gate).
            // SA_CGU_PARALLEL=1 opts back into the old parallel path for
            // large modules.
            const sequential_cgu = seq_shards != null or (!cguForceParallel() and owned.verified.function_sigs.len > cgu_seq_fn_threshold);

            if (use_cgu) {
                const cgu_count = if (seq_shards) |n| n else @min(@max(emission_workers, 2), 4);

                const cgu_obj_paths = try allocator.alloc([]const u8, cgu_count);
                defer {
                    for (cgu_obj_paths) |p| allocator.free(p);
                    allocator.free(cgu_obj_paths);
                }
                for (0..cgu_count) |i| {
                    cgu_obj_paths[i] = try std.fmt.allocPrint(allocator, "{s}_cgu_{d}.o", .{ out_path, i });
                }

                // Ensure parent directory exists for all of them
                for (cgu_obj_paths) |p| {
                    try ensureParentDir(p);
                }

                // Parallel emit CGU bitcode files
                const VerifiedType = @TypeOf(owned.verified);
                const CguEmitWorker = struct {
                    alloc_val: std.mem.Allocator,
                    verified_ptr: *const VerifiedType,
                    def_dict_ptr: ?*const flattener.DefDict,
                    loc_table_val: @TypeOf(owned.flat.loc_table),
                    source_path_val: []const u8,
                    size_bits_val: u16,
                    debug_val: bool,
                    jobs_val: ?usize,
                    dce_val: DceMode,
                    fast_math_val: bool,
                    cgu_idx_val: usize,
                    cgu_count_val: usize,
                    object_path_val: []const u8,
                    opt_level_val: u8,
                    std_root_val: []const u8,
                    target_triple_val: ?[]const u8,
                    err: ?anyerror = null,

                    pub fn run(self: *@This()) void {
                        emit_llvm_llvmc.emitLlvmcToObject(
                            self.alloc_val,
                            self.verified_ptr.*,
                            self.def_dict_ptr,
                            self.loc_table_val,
                            self.source_path_val,
                            self.size_bits_val,
                            .{
                                .debug = self.debug_val,
                                .jobs = self.jobs_val,
                                .opt_level = self.opt_level_val,
                                .codegen_unit_index = self.cgu_idx_val,
                                .codegen_unit_count = self.cgu_count_val,
                                .dce = self.dce_val,
                                .fast_math = self.fast_math_val,
                                .std_root = self.std_root_val,
                                .target_triple = self.target_triple_val,
                            },
                            self.object_path_val,
                            self.opt_level_val,
                        ) catch |err| {
                            self.err = err;
                        };
                    }
                };

                var cgu_emit_workers = try allocator.alloc(CguEmitWorker, cgu_count);
                defer allocator.free(cgu_emit_workers);

                for (0..cgu_count) |i| {
                    cgu_emit_workers[i] = .{
                        .alloc_val = allocator,
                        .verified_ptr = &owned.verified,
                        .def_dict_ptr = &owned.flat.def_dict,
                        .loc_table_val = owned.flat.loc_table,
                        .source_path_val = source_path,
                        .size_bits_val = size_bits,
                        .debug_val = debug,
                        // LINE-PEAK50-EMIT Form 1: a sequential shard may
                        // use the full worker pool for its internal
                        // ParallelEmitJob codegen (same CModule output, less
                        // wall time); parallel shards keep jobs=1 to avoid
                        // oversubscription (4 shards x N workers).
                        .jobs_val = if (sequential_cgu) emission_workers else if (compile_options.jobs) |j| if (j > 1) 1 else j else 1,
                        .dce_val = compile_options.dce,
                        .fast_math_val = compile_options.fast_math,
                        .cgu_idx_val = i,
                        .cgu_count_val = cgu_count,
                        .object_path_val = cgu_obj_paths[i],
                        .opt_level_val = emitOptLevel(debug, optimization),
                        .std_root_val = emit_std_root,
                        .target_triple_val = compile_options.target_triple,
                    };
                }

                const emit_start = if (compile_options.profile) std.Io.Clock.awake.now(sio.io()) else null;
                if (sequential_cgu) {
                    // Sequential shard emission (LINE-OPT-CGU-SHARD
                    // prototype, now the Form 1 default for large modules).
                    // Each shard's emit call builds and deinits its own
                    // arenas, so shard i's C fragments and LLVM module are
                    // released before shard i+1 starts; peak emit residency
                    // is one shard's working set.
                    for (cgu_emit_workers) |*w| w.run();
                } else {
                    var cgu_emit_threads = try allocator.alloc(std.Thread, cgu_count - 1);
                    defer allocator.free(cgu_emit_threads);

                    var started_cgu_emit: usize = 0;
                    errdefer {
                        while (started_cgu_emit > 0) {
                            started_cgu_emit -= 1;
                            cgu_emit_threads[started_cgu_emit].join();
                        }
                    }

                    while (started_cgu_emit < cgu_count - 1) : (started_cgu_emit += 1) {
                        cgu_emit_threads[started_cgu_emit] = try std.Thread.spawn(.{}, CguEmitWorker.run, .{&cgu_emit_workers[started_cgu_emit + 1]});
                    }

                    cgu_emit_workers[0].run();

                    while (started_cgu_emit > 0) {
                        started_cgu_emit -= 1;
                        cgu_emit_threads[started_cgu_emit].join();
                    }
                }

                for (cgu_emit_workers) |w| {
                    if (w.err) |err| return err;
                }
                const emit_ns = if (emit_start) |start| elapsedNs(start) else null;
                recordMetricMemoryAfterEmit(&owned.metrics);
                if (owned.metrics.memory) |memory| try writeMemoryStageSampleForOptions(compile_options, "after_emit", memory.after_emit_rss_bytes, memory.after_verify_rss_bytes);

                var link_inputs = std.array_list.Managed([]const u8).init(allocator);
                defer link_inputs.deinit();
                var owned_link_inputs = std.array_list.Managed([]const u8).init(allocator);
                defer {
                    for (owned_link_inputs.items) |arg| allocator.free(arg);
                    owned_link_inputs.deinit();
                }

                for (1..cgu_count) |i| {
                    try link_inputs.append(cgu_obj_paths[i]);
                }
                if (compile_options.target_triple) |triple| {
                    const extern_names = try collectExternalSymbolNames(allocator, &owned.verified);
                    defer allocator.free(extern_names);
                    if (extern_names.len != 0) {
                        try stderr.print("error: --target {s} does not support native plugins yet (program uses extern symbol '{s}')\n", .{ triple, extern_names[0] });
                        return 1;
                    }
                } else {
                    if (!try appendNativePluginLinkInputs(allocator, &link_inputs, &owned_link_inputs, &owned.verified, stderr)) return 1;
                }

                const link_start = if (compile_options.profile) std.Io.Clock.awake.now(sio.io()) else null;
                driver.compileExe(allocator, cgu_obj_paths[0], out_path, optimization, std_archive_path, link_inputs.items, debug, stderr, compile_options.target_triple) catch |err| switch (err) {
                    error.ChildProcessFailed => return 1,
                    else => return err,
                };
                const link_ns = if (link_start) |start| elapsedNs(start) else null;
                recordMetricMemoryAfterLink(&owned.metrics);
                if (owned.metrics.memory) |memory| try writeMemoryStageSampleForOptions(compile_options, "after_link", memory.after_link_rss_bytes, memory.after_emit_rss_bytes);
                recordMetricMemoryEnd(&owned.metrics);
                if (owned.metrics.memory) |memory| try writeMemoryStageSampleForOptions(compile_options, "end", memory.end_rss_bytes, memoryEndPrevious(memory));
                finishProfileMetrics(&owned.metrics, emit_ns, link_ns, if (total_start) |start| elapsedNs(start) else null);
                // CGU emission produces no whole-module bitcode artifact, so
                // record the linked executable as the artifact payload: the
                // build-exe cache entry must still be stored, otherwise every
                // --jobs build misses the cache and recompiles from scratch.
                // The hit path consumes output.bin; artifact.sa.bc is only
                // restored to the intermediate path, which build-exe does
                // not read back.
                if (cache_key) |key| try projectCacheStore(allocator, project_root, .build_exe, key, out_path, out_path);
            } else {
                try ensureParentDir(artifact_path);
                const emit_start = if (compile_options.profile) std.Io.Clock.awake.now(sio.io()) else null;
                emit_llvm_llvmc.emitLlvmcToFile(allocator, owned.verified, &owned.flat.def_dict, owned.flat.loc_table, source_path, size_bits, .{ .debug = debug, .jobs = compile_options.jobs, .opt_level = emitOptLevel(debug, optimization), .dce = compile_options.dce, .fast_math = compile_options.fast_math, .std_root = emit_std_root, .target_triple = compile_options.target_triple }, artifact_path) catch |err| {
                    try printLlvmcEmitError(stderr, err, diagnostics_mode);
                    return 1;
                };
                const emit_ns = if (emit_start) |start| elapsedNs(start) else null;
                recordMetricMemoryAfterEmit(&owned.metrics);
                if (owned.metrics.memory) |memory| try writeMemoryStageSampleForOptions(compile_options, "after_emit", memory.after_emit_rss_bytes, memory.after_verify_rss_bytes);

                const link_start = if (compile_options.profile) std.Io.Clock.awake.now(sio.io()) else null;
                var link_inputs = std.array_list.Managed([]const u8).init(allocator);
                defer link_inputs.deinit();
                var owned_link_inputs = std.array_list.Managed([]const u8).init(allocator);
                defer {
                    for (owned_link_inputs.items) |arg| allocator.free(arg);
                    owned_link_inputs.deinit();
                }
                if (compile_options.target_triple) |triple| {
                    const extern_names = try collectExternalSymbolNames(allocator, &owned.verified);
                    defer allocator.free(extern_names);
                    if (extern_names.len != 0) {
                        try stderr.print("error: --target {s} does not support native plugins yet (program uses extern symbol '{s}')\n", .{ triple, extern_names[0] });
                        return 1;
                    }
                } else {
                    if (!try appendNativePluginLinkInputs(allocator, &link_inputs, &owned_link_inputs, &owned.verified, stderr)) return 1;
                }
                driver.compileExe(allocator, artifact_path, out_path, optimization, std_archive_path, link_inputs.items, debug, stderr, compile_options.target_triple) catch |err| switch (err) {
                    error.ChildProcessFailed => return 1,
                    else => return err,
                };
                const link_ns = if (link_start) |start| elapsedNs(start) else null;
                recordMetricMemoryAfterLink(&owned.metrics);
                if (owned.metrics.memory) |memory| try writeMemoryStageSampleForOptions(compile_options, "after_link", memory.after_link_rss_bytes, memory.after_emit_rss_bytes);
                recordMetricMemoryEnd(&owned.metrics);
                if (owned.metrics.memory) |memory| try writeMemoryStageSampleForOptions(compile_options, "end", memory.end_rss_bytes, memoryEndPrevious(memory));
                finishProfileMetrics(&owned.metrics, emit_ns, link_ns, if (total_start) |start| elapsedNs(start) else null);
                if (cache_key) |key| try projectCacheStore(allocator, project_root, .build_exe, key, artifact_path, out_path);
            }
            attachBackendIrMetrics(&owned.metrics, &owned.verified, debug);
            if (cache_key != null) owned.metrics.cache = .{ .kind = BuildCacheKind.build_exe.dirName(), .hit = false };

            if (stageTimingEnabled()) printStageTiming(stderr, &owned.metrics);
            try writeSuccessDiagnostics(stderr, owned.metrics, diagnostics_mode);
            return 0;
        },
    }
}

pub fn executeBuildObj(allocator: std.mem.Allocator, source_path: []const u8, out_path: []const u8, debug: bool, optimization: driver.Optimization, incremental: bool, compile_options: CompileOptions, stderr: anytype, diagnostics_mode: DiagnosticsMode) !u8 {
    const total_start = if (compile_options.profile) std.Io.Clock.awake.now(sio.io()) else null;
    const project_root_owned = compile_options.project_root == null;
    const project_root = compile_options.project_root orelse try projectRootFromSourcePath(allocator, source_path);
    defer if (project_root_owned) allocator.free(project_root);
    var project_context = try loadProjectContext(allocator, project_root, compile_options.package_name);
    defer project_context.deinit(allocator);
    const cache_key: ?ProjectCacheKey = if (compile_options.incremental_cache)
        try computeProjectBuildKey(allocator, &project_context, project_root, source_path, "obj", compile_options.target_triple orelse "", .build_obj, debug, optimization == .release_fast, incremental, null, true, compile_options.offline, compile_options.dce, compile_options.default_immutable, compile_options.fast_math)
    else
        null;
    const artifact_path = try intermediateArtifactPath(allocator, out_path);
    defer allocator.free(artifact_path);

    if (cache_key) |key| {
        if (try projectCacheHit(allocator, project_root, .build_obj, key, artifact_path, out_path)) {
            if (diagnostics_mode == .json or compile_options.mem_report) {
                const metrics = CompileMetrics{ .compile_tokens = 0, .instruction_count = 0, .phases = if (compile_options.profile) .{ .load_ns = 0, .setup_ns = 0, .flatten_ns = 0, .verify_ns = 0, .emit_ns = 0, .link_ns = 0, .total_ns = if (total_start) |start| elapsedNs(start) else null } else null, .memory = cacheHitMemoryMetrics(compile_options.mem_report), .cache = .{ .kind = BuildCacheKind.build_obj.dirName(), .hit = true } };
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
            rejectNpmBindsUnlessJs("sa build-obj", &owned.flat, stderr) catch return 1;
            const emit_std_root = try stdRootFromEnv(allocator);
            defer allocator.free(emit_std_root);
            try ensureParentDir(artifact_path);
            const emit_start = if (compile_options.profile) std.Io.Clock.awake.now(sio.io()) else null;
            const opt_level = emitOptLevel(debug, optimization);
            if (compile_options.target_triple != null and incremental) {
                try stderr.writeAll("error: --target cannot be combined with --incremental yet\n");
                return 1;
            }
            const size_bits = sizeBitsForTriple(compile_options.target_triple);
            if (incremental) {
                const incremental_key = try computeProjectBuildKey(allocator, &project_context, project_root, source_path, "obj", "", .build_obj_incremental, debug, optimization == .release_fast, true, null, false, compile_options.offline, compile_options.dce, compile_options.default_immutable, compile_options.fast_math);
                try buildIncrementalObject(allocator, project_root, incremental_key, &owned, source_path, out_path, debug, optimization, compile_options, stderr);
                emit_llvm_llvmc.emitLlvmcToFile(allocator, owned.verified, &owned.flat.def_dict, owned.flat.loc_table, source_path, size_bits, .{ .debug = debug, .jobs = compile_options.jobs, .opt_level = opt_level, .dce = compile_options.dce, .fast_math = compile_options.fast_math, .std_root = emit_std_root, .target_triple = compile_options.target_triple }, artifact_path) catch |err| {
                    try printLlvmcEmitError(stderr, err, diagnostics_mode);
                    return 1;
                };
            } else {
                emit_llvm_llvmc.emitLlvmcToArtifacts(allocator, owned.verified, &owned.flat.def_dict, owned.flat.loc_table, source_path, size_bits, .{ .debug = debug, .jobs = compile_options.jobs, .opt_level = opt_level, .dce = compile_options.dce, .fast_math = compile_options.fast_math, .std_root = emit_std_root, .target_triple = compile_options.target_triple }, artifact_path, out_path, opt_level) catch |err| {
                    try printLlvmcEmitError(stderr, err, diagnostics_mode);
                    return 1;
                };
            }
            recordMetricMemoryAfterEmit(&owned.metrics);
            if (owned.metrics.memory) |memory| try writeMemoryStageSampleForOptions(compile_options, "after_emit", memory.after_emit_rss_bytes, memory.after_verify_rss_bytes);
            recordMetricMemoryEnd(&owned.metrics);
            if (owned.metrics.memory) |memory| try writeMemoryStageSampleForOptions(compile_options, "end", memory.end_rss_bytes, memoryEndPrevious(memory));
            finishProfileMetrics(&owned.metrics, if (emit_start) |start| elapsedNs(start) else null, null, if (total_start) |start| elapsedNs(start) else null);
            attachBackendIrMetrics(&owned.metrics, &owned.verified, debug);
            if (cache_key) |key| try projectCacheStore(allocator, project_root, .build_obj, key, artifact_path, out_path);
            if (cache_key != null) owned.metrics.cache = .{ .kind = BuildCacheKind.build_obj.dirName(), .hit = false };
            try writeSuccessDiagnostics(stderr, owned.metrics, diagnostics_mode);
            return 0;
        },
    }
}

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

pub fn executeBuildC(allocator: std.mem.Allocator, source_path: []const u8, out_path: []const u8, debug: bool, compile_options: CompileOptions, stderr: anytype, diagnostics_mode: DiagnosticsMode) !u8 {
    const total_start = if (compile_options.profile) std.Io.Clock.awake.now(sio.io()) else null;
    const compiled = try compileSource(allocator, source_path, compile_options);
    switch (compiled) {
        .trap => |report| {
            try printTrapReport(stderr, report, diagnostics_mode);
            return 1;
        },
        .ok => |ok| {
            var owned = ok;
            defer owned.deinit(allocator);
            try ensureParentDir(out_path);
            const emit_start = if (compile_options.profile) std.Io.Clock.awake.now(sio.io()) else null;
            const size_bits = sizeBitsForTriple(compile_options.target_triple);
            emit_c.emitCToFile(allocator, owned.verified, source_path, size_bits, .{ .debug_comments = debug }, out_path) catch |err| {
                try stderr.print("error: C backend emit failed: {s}", .{@errorName(err)});
                if (emit_c.last_c_func.len != 0) try stderr.print(" in {s}", .{emit_c.last_c_func});
                if (emit_c.last_c_inst.len != 0) try stderr.print(": {s}", .{std.mem.trim(u8, emit_c.last_c_inst, " \t\r\n")});
                try stderr.writeAll("\n");
                return 1;
            };
            const emit_ns = if (emit_start) |start| elapsedNs(start) else null;
            recordMetricMemoryAfterEmit(&owned.metrics);
            if (owned.metrics.memory) |memory| try writeMemoryStageSampleForOptions(compile_options, "after_emit", memory.after_emit_rss_bytes, memory.after_verify_rss_bytes);
            recordMetricMemoryEnd(&owned.metrics);
            if (owned.metrics.memory) |memory| try writeMemoryStageSampleForOptions(compile_options, "end", memory.end_rss_bytes, memoryEndPrevious(memory));
            finishProfileMetrics(&owned.metrics, emit_ns, null, if (total_start) |start| elapsedNs(start) else null);
            attachBackendIrMetrics(&owned.metrics, &owned.verified, debug);
            try writeSuccessDiagnostics(stderr, owned.metrics, diagnostics_mode);
            return 0;
        },
    }
}
