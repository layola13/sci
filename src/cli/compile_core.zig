const std = @import("std");
const CompileOptions = @import("types.zig").CompileOptions;
const CompileResult = @import("types.zig").CompileResult;
const CompileMemoryMetrics = @import("types.zig").CompileMemoryMetrics;
const MemoryStageReporterContext = @import("types.zig").MemoryStageReporterContext;
const flattener = @import("../flattener.zig");
const incr_verify = @import("../incr_verify.zig");
const manifest = @import("../pkg/manifest.zig");
const pkg_resolver = @import("../pkg/resolver.zig");
const pkg_workspace = @import("../pkg/workspace.zig");
const pruneSabFlatToSelectedTests = @import("cache.zig").pruneSabFlatToSelectedTests;
const referee = @import("../referee.zig");
const sab = @import("../sab.zig");
const setFile = @import("trap_errors.zig").setFile;
const sio = @import("sio");
const stdRootFromEnv = @import("cache.zig").stdRootFromEnv;
const trap = @import("../common/trap.zig");
const trapFromFlattenError = @import("trap_errors.zig").trapFromFlattenError;
const trapFromPackagePreflightError = @import("trap_errors.zig").trapFromPackagePreflightError;
const verifyProjectPackageState = @import("package.zig").verifyProjectPackageState;
const computeCompileMetrics = @import("compile.zig").computeCompileMetrics;
const defaultStableImportRoots = @import("compile.zig").defaultStableImportRoots;
const elapsedNs = @import("compile.zig").elapsedNs;
const freeOwnedStringSlice = @import("compile.zig").freeOwnedStringSlice;
const loadSabFlat = @import("compile.zig").loadSabFlat;
const loadSource = @import("compile.zig").loadSource;
const manifestDependencies = @import("compile.zig").manifestDependencies;
const manifestPluginImportRoots = @import("compile.zig").manifestPluginImportRoots;
const reportPluginImportDiagnostic = @import("compile.zig").reportPluginImportDiagnostic;
const reportVerifierMemoryStage = @import("compile.zig").reportVerifierMemoryStage;
const resolveProjectFromSourcePath = @import("compile.zig").resolveProjectFromSourcePath;
const trustedSabVerifyOk = @import("compile.zig").trustedSabVerifyOk;
const proof_elim = @import("../proof_elim/pass.zig");
const verifyModeByte = @import("compile.zig").verifyModeByte;
const writeMemoryStageSampleForOptions = @import("compile.zig").writeMemoryStageSampleForOptions;

pub fn compileSource(allocator: std.mem.Allocator, source_path: []const u8, options: CompileOptions) !CompileResult {
    var memory_metrics: ?CompileMemoryMetrics = if (options.mem_report) .{} else null;
    if (memory_metrics) |*memory| {
        memory.recordStart();
        try writeMemoryStageSampleForOptions(options, "start", memory.start_rss_bytes, null);
    }

    const total_start = if (options.profile) std.Io.Clock.awake.now(sio.io()) else null;
    if (std.mem.endsWith(u8, source_path, ".sab")) {
        const load_flat_start = if (options.profile) std.Io.Clock.awake.now(sio.io()) else null;
        var flat = try loadSabFlat(allocator, source_path);
        errdefer flat.deinit(allocator);
        const load_flat_ns = if (load_flat_start) |start| elapsedNs(start) else null;
        const prune_start = if (options.profile) std.Io.Clock.awake.now(sio.io()) else null;
        try pruneSabFlatToSelectedTests(allocator, &flat, options.sab_selected_test_names);
        const prune_ns = if (prune_start) |start| elapsedNs(start) else null;
        const verify_start = if (options.profile) std.Io.Clock.awake.now(sio.io()) else null;
        if (options.sab_skip_verify and options.sab_selected_test_names.len != 0) {
            const trusted = try trustedSabVerifyOk(allocator, &flat);
            const verify_ns = if (verify_start) |start| elapsedNs(start) else null;
            if (options.profile) {
                var null_buf: [64]u8 = undefined;
                var null_discarding: std.Io.Writer.Discarding = .init(&null_buf);
                const writer = options.diagnostic_writer orelse &null_discarding.writer;
                try writer.print(
                    "profile sab load_flat={d:.3}ms prune={d:.3}ms verify={d:.3}ms trusted=1\n",
                    .{
                        @as(f64, @floatFromInt(load_flat_ns orelse 0)) / 1_000_000.0,
                        @as(f64, @floatFromInt(prune_ns orelse 0)) / 1_000_000.0,
                        @as(f64, @floatFromInt(verify_ns orelse 0)) / 1_000_000.0,
                    },
                );
            }
            return .{ .ok = .{ .flat = flat, .verified = trusted, .metrics = computeCompileMetrics(&flat, &trusted, if (options.profile) .{ .load_ns = load_flat_ns orelse 0, .setup_ns = 0, .flatten_ns = prune_ns orelse 0, .verify_ns = verify_ns orelse 0, .total_ns = if (total_start) |start| elapsedNs(start) else null } else null, memory_metrics) } };
        }
        const verified = try referee.verifyWithOptions(allocator, flat.instructions, flat.const_decls, .{
            .jobs = options.jobs,
            .stage_reporter = null,
            .predecoded_symbol_names = flat.symbols.names.items,
            .predecoded_function_sigs = flat.function_sigs,
            .check_exit_leaks = options.sab_selected_test_names.len == 0,
            .default_immutable = options.default_immutable,
        });
        const verify_ns = if (verify_start) |start| elapsedNs(start) else null;
        if (options.profile) {
            var null_buf: [64]u8 = undefined;
            var null_discarding: std.Io.Writer.Discarding = .init(&null_buf);
            const writer = options.diagnostic_writer orelse &null_discarding.writer;
            try writer.print(
                "profile sab load_flat={d:.3}ms prune={d:.3}ms verify={d:.3}ms\n",
                .{
                    @as(f64, @floatFromInt(load_flat_ns orelse 0)) / 1_000_000.0,
                    @as(f64, @floatFromInt(prune_ns orelse 0)) / 1_000_000.0,
                    @as(f64, @floatFromInt(verify_ns orelse 0)) / 1_000_000.0,
                },
            );
        }
        return switch (verified) {
            .ok => |ok| blk: {
                const digest = incr_verify.hashInstructionsMode(flat.instructions, verifyModeByte(options.default_immutable));
                incr_verify.recordVerified(digest);
                break :blk .{ .ok = .{ .flat = flat, .verified = ok, .metrics = computeCompileMetrics(&flat, &ok, if (options.profile) .{ .load_ns = 0, .setup_ns = 0, .flatten_ns = 0, .verify_ns = 0, .total_ns = if (total_start) |start| elapsedNs(start) else null } else null, memory_metrics) } };
            },
            .trap => |report| {
                var r = report;
                if (r.file == null) setFile(&r, source_path);
                flat.deinit(allocator);
                return .{ .trap = r };
            },
        };
    }
    const load_start = if (options.profile) std.Io.Clock.awake.now(sio.io()) else null;
    const source = try loadSource(allocator, source_path);
    defer allocator.free(source);
    const load_ns = if (load_start) |start| elapsedNs(start) else 0;
    if (memory_metrics) |*memory| {
        memory.recordAfterLoad();
        try writeMemoryStageSampleForOptions(options, "after_load", memory.after_load_rss_bytes, memory.start_rss_bytes);
    }

    const setup_start = if (options.profile) std.Io.Clock.awake.now(sio.io()) else null;
    var resolution = if (options.project_root) |project_root|
        try pkg_workspace.resolveFromRootPath(allocator, project_root, .{ .request = options.package_name })
    else
        try resolveProjectFromSourcePath(allocator, source_path, options.package_name);
    defer resolution.deinit(allocator);

    const project_root = resolution.workspace_root;
    const member_root = resolution.member_root;
    const std_root = try stdRootFromEnv(allocator);
    defer allocator.free(std_root);

    const project_manifest = resolution.effective_manifest;

    var dependency_slice: []pkg_resolver.Dependency = &.{};
    defer if (dependency_slice.len != 0) allocator.free(dependency_slice);

    var plugin_import_roots: []const []const u8 = &.{};
    defer if (plugin_import_roots.len != 0) freeOwnedStringSlice(allocator, plugin_import_roots);
    const stable_import_roots = try defaultStableImportRoots(allocator, member_root);
    defer freeOwnedStringSlice(allocator, stable_import_roots);

    if (project_manifest) |*m| {
        verifyProjectPackageState(allocator, project_root, m.*, options) catch |err| {
            if (trapFromPackagePreflightError(err)) |report| {
                return .{ .trap = report };
            }
            return err;
        };
        dependency_slice = try manifestDependencies(m, allocator);
        plugin_import_roots = try manifestPluginImportRoots(m, allocator);
    }

    const package_grants: []const manifest.RequireEntry = if (project_manifest) |*m| m.requires else &.{};

    var error_ctx: flattener.ErrorContext = .{};
    const resolve_ctx = flattener.ResolveContext{
        .dependencies = dependency_slice,
        .options = .{
            .project_root = project_root,
            .std_root = std_root,
            .offline = options.offline,
            .plugin_import_roots = plugin_import_roots,
            .stable_import_roots = stable_import_roots,
            .diagnostics = &reportPluginImportDiagnostic,
        },
    };
    const setup_ns = if (setup_start) |start| elapsedNs(start) else 0;
    if (memory_metrics) |*memory| {
        memory.recordAfterSetup();
        try writeMemoryStageSampleForOptions(options, "after_setup", memory.after_setup_rss_bytes, memory.after_load_rss_bytes);
    }

    const flatten_start = if (options.profile) std.Io.Clock.awake.now(sio.io()) else null;
    var flat = flattener.flattenFileWithContextAndPackages(allocator, source_path, source, &error_ctx, resolve_ctx) catch |err| {
        return .{ .trap = trapFromFlattenError(source_path, source, err, flattener.errorReport(&error_ctx)) };
    };
    errdefer flat.deinit(allocator);
    const flatten_ns = if (flatten_start) |start| elapsedNs(start) else 0;
    if (memory_metrics) |*memory| {
        memory.recordAfterFlatten();
        try writeMemoryStageSampleForOptions(options, "after_flatten", memory.after_flatten_rss_bytes, memory.after_setup_rss_bytes);
    }

    var null_buf: [64]u8 = undefined;
    var null_discarding: std.Io.Writer.Discarding = .init(&null_buf);
    var verifier_stage_context = MemoryStageReporterContext{
        .writer = options.diagnostic_writer orelse &null_discarding.writer,
        .memory = if (memory_metrics) |*memory| memory else null,
        .previous_rss_bytes = if (memory_metrics) |memory| memory.after_flatten_rss_bytes else null,
        .peak_rss_bytes = if (memory_metrics) |memory| memory.peak_rss_bytes else null,
        .live = options.mem_report_live,
        .timing_live = options.profile,
        .timing_start = if (options.profile) std.Io.Clock.awake.now(sio.io()) else null,
    };
    const verifier_stage_reporter: ?referee.VerifyStageReporter = if (options.mem_report or options.profile)
        .{ .context = &verifier_stage_context, .report_fn = reportVerifierMemoryStage }
    else
        null;

    const verify_start = if (options.profile) std.Io.Clock.awake.now(sio.io()) else null;
    // Proof elimination (jihoo 01 prototype): remove bounds checks proved
    // from loop-head conditions. Runs after flattening and before the
    // content hash and verification, so the referee backstops it. Kill
    // switch: PROOF_ELIM=0. PROOF_ELIM_REPORT=<path> writes a
    // per-function report. The .sab path is out of scope.
    if (proof_elim.isEnabled(allocator)) {
        const elim_report = try proof_elim.runProofElim(allocator, flat.instructions, flat.function_sigs, flat.test_sigs);
        defer allocator.free(elim_report.funcs);
        if (elim_report.removed > 0) {
            const elim_writer = options.diagnostic_writer orelse &null_discarding.writer;
            elim_writer.print("proof-elim: removed {d} bounds checks ({d} proven of {d} target-class, {d} checks in {d} functions)\n", .{ elim_report.removed, elim_report.proven, elim_report.target, elim_report.checks, elim_report.functions }) catch {};
        }
        if (sio.getEnvVarOwned(allocator, "PROOF_ELIM_REPORT") catch null) |report_path| {
            defer allocator.free(report_path);
            if (report_path.len > 0) {
                const text = proof_elim.reportText(allocator, &elim_report) catch null;
                if (text) |t| {
                    defer allocator.free(t);
                    const f = sio.cwd().createFile(report_path, .{ .truncate = true }) catch null;
                    if (f) |file| {
                        defer file.close();
                        file.writeAll(t) catch {};
                    }
                }
            }
        }
    }

    const content_hash = incr_verify.hashInstructionsMode(flat.instructions, verifyModeByte(options.default_immutable));
    // Phase B-B hybrid: on verdict hit rebuild a trusted annotated shell from the
    // current FlattenResult (no dangling VerifyOk reuse). Misses run the referee.
    if (incr_verify.isVerified(content_hash)) {
        const trusted = try trustedSabVerifyOk(allocator, &flat);
        const verify_ns = if (verify_start) |start| elapsedNs(start) else 0;
        if (memory_metrics) |*memory| {
            memory.recordAfterVerify();
            try writeMemoryStageSampleForOptions(options, "after_verify", memory.after_verify_rss_bytes, memory.after_flatten_rss_bytes);
            memory.recordEnd();
        }
        var metrics = computeCompileMetrics(&flat, &trusted, if (options.profile) .{ .load_ns = load_ns, .setup_ns = setup_ns, .flatten_ns = flatten_ns, .verify_ns = verify_ns, .total_ns = if (total_start) |start| elapsedNs(start) else null } else null, memory_metrics);
        metrics.cache = .{ .kind = "verdict", .hit = true };
        return .{ .ok = .{ .flat = flat, .verified = trusted, .metrics = metrics } };
    }
    const verified = try referee.verifyWithOptions(allocator, flat.instructions, flat.const_decls, .{ .jobs = options.jobs, .package_grants = package_grants, .stage_reporter = verifier_stage_reporter, .default_immutable = options.default_immutable });
    const verify_ns = if (verify_start) |start| elapsedNs(start) else 0;
    if (memory_metrics) |*memory| {
        memory.updatePeak(verifier_stage_context.peak_rss_bytes);
        memory.recordAfterVerify();
        try writeMemoryStageSampleForOptions(options, "after_verify", memory.after_verify_rss_bytes, memory.after_flatten_rss_bytes);
        memory.recordEnd();
    }

    return switch (verified) {
        .ok => |ok| blk: {
            incr_verify.recordVerified(content_hash);
            // NOTE: no recordResultFromInstructions call here on purpose
            // (LINE-OPT-INCR-SNAPSHOT-FIX, R320 opt1_stop). The B-B result
            // snapshot it built is a write-only cache: hasResult has zero
            // call sites and its documented consumer restoreMinimal()
            // does not exist, while recording deep-clones every
            // instruction through page_allocator (~+1.9 GiB peak on a
            // 100k cold compile). The verdict-only cache above
            // (recordVerified) is the live cache and is untouched.
            var metrics = computeCompileMetrics(&flat, &ok, if (options.profile) .{ .load_ns = load_ns, .setup_ns = setup_ns, .flatten_ns = flatten_ns, .verify_ns = verify_ns, .total_ns = if (total_start) |start| elapsedNs(start) else null } else null, memory_metrics);
            metrics.cache = .{ .kind = "verdict", .hit = false };
            break :blk .{ .ok = .{ .flat = flat, .verified = ok, .metrics = metrics } };
        },
        .trap => |report| {
            var r = report;
            if (r.file == null) {
                setFile(&r, source_path);
            }
            flat.deinit(allocator);
            return .{ .trap = r };
        },
    };
}
