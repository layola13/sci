const std = @import("std");
const sio = @import("sio");
const CompileOptions = @import("types.zig").CompileOptions;
const DiagnosticsMode = @import("types.zig").DiagnosticsMode;
const CompileResult = @import("types.zig").CompileResult;
const ExecuteOptions = @import("types.zig").ExecuteOptions;
const CompileMemoryMetrics = @import("types.zig").CompileMemoryMetrics;
const newCompileOptions = @import("types.zig").newCompileOptions;
const compileSource = @import("compile.zig").compileSource;
const consumeCompileOption = @import("options.zig").consumeCompileOption;
const loadSource = @import("compile.zig").loadSource;
const configureCompileDiagnostics = @import("types.zig").configureCompileDiagnostics;

/// Check-oriented compile: flatten + verify, with verdict-cache short circuit.
pub fn compileSourceForCheck(allocator: std.mem.Allocator, source_path: []const u8, options: CompileOptions) !CompileResult {
    var memory_metrics: ?CompileMemoryMetrics = if (options.mem_report) .{} else null;
    if (memory_metrics) |*memory| memory.recordStart();
    const total_start = if (options.profile) std.Io.Clock.awake.now(sio.io()) else null;

    if (std.mem.endsWith(u8, source_path, ".sab")) {
        // Reuse the normal SAB path (already records verdict on success).
        return try compileSource(allocator, source_path, options);
    }

    const load_start = if (options.profile) std.Io.Clock.awake.now(sio.io()) else null;
    const source = try loadSource(allocator, source_path);
    defer allocator.free(source);
    const load_ns = if (load_start) |start| elapsedNs(start) else 0;

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
            if (trapFromPackagePreflightError(err)) |report| return .{ .trap = report };
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

    const flatten_start = if (options.profile) std.Io.Clock.awake.now(sio.io()) else null;
    var flat = flattener.flattenFileWithContextAndPackages(allocator, source_path, source, &error_ctx, resolve_ctx) catch |err| {
        return .{ .trap = trapFromFlattenError(source_path, source, err, flattener.errorReport(&error_ctx)) };
    };
    errdefer flat.deinit(allocator);
    const flatten_ns = if (flatten_start) |start| elapsedNs(start) else 0;

    const content_hash = incr_verify.hashInstructionsMode(flat.instructions, verifyModeByte(options.default_immutable));
    const verify_start = if (options.profile) std.Io.Clock.awake.now(sio.io()) else null;
    if (!options.skip_verdict_cache and incr_verify.isVerified(content_hash)) {
        // Verdict hit: build a trusted shell without re-running the referee.
        const trusted = try trustedSabVerifyOk(allocator, &flat);
        const verify_ns = if (verify_start) |start| elapsedNs(start) else 0;
        var metrics = computeCompileMetrics(&flat, &trusted, if (options.profile) .{ .load_ns = load_ns, .setup_ns = setup_ns, .flatten_ns = flatten_ns, .verify_ns = verify_ns, .total_ns = if (total_start) |start| elapsedNs(start) else null } else null, memory_metrics);
        metrics.cache = .{ .kind = "verdict", .hit = true };
        return .{ .ok = .{ .flat = flat, .verified = trusted, .metrics = metrics } };
    }

    const verified = try referee.verifyWithOptions(allocator, flat.instructions, flat.const_decls, .{
        .jobs = options.jobs,
        .package_grants = package_grants,
        .stage_reporter = null,
        .default_immutable = options.default_immutable,
    });
    const verify_ns = if (verify_start) |start| elapsedNs(start) else 0;
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
            if (r.file == null) setFile(&r, source_path);
            flat.deinit(allocator);
            return .{ .trap = r };
        },
    };
}

pub fn executeCheck(
    allocator: std.mem.Allocator,
    args: []const []const u8,
    stdout: anytype,
    stderr: anytype,
    json_mode: bool,
    exec_options: ExecuteOptions,
) !u8 {
    var diag_forward = sio.ForwardWriter(@TypeOf(stderr)).init(stderr);
    defer diag_forward.writer().flush() catch {};
    var compile_options = newCompileOptions(exec_options, diag_forward.writer());
    var source_arg: ?[]const u8 = null;
    var emit_sab_path: ?[]const u8 = null;
    var i: usize = 0;
    while (i < args.len) : (i += 1) {
        const arg = args[i];
        if (try consumeCompileOption(arg, args, &i, &compile_options)) continue;
        if (std.mem.eql(u8, arg, "--emit-sab")) {
            if (i + 1 >= args.len) return error.MissingOutputPath;
            emit_sab_path = args[i + 1];
            i += 1;
            continue;
        }
        if (source_arg == null) {
            source_arg = arg;
            continue;
        }
        return error.UnexpectedArgument;
    }
    if (source_arg == null) return error.MissingSourcePath;
    const source_path = source_arg.?;
    configureCompileDiagnostics(&compile_options, json_mode);

    // --emit-sab encodes from the flat itself (encodeSabFromFlat re-verifies
    // the pristine stream and reads flat.symbols), so the verdict-cache
    // fast path must not repurpose that flat in place (finding D).
    compile_options.skip_verdict_cache = emit_sab_path != null;

    const total_start = std.Io.Clock.awake.now(sio.io());
    // Flatten via compileSource front half by reusing compileSource then discarding codegen.
    // Fast path: if we already verified this instruction stream, skip verify.
    const compiled = try compileSourceForCheck(allocator, source_path, compile_options);
    const wall_ns = elapsedNs(total_start);
    switch (compiled) {
        .trap => |report| {
            try printTrapReport(if (json_mode) stdout else stderr, report, if (json_mode) .json else .human);
            return 1;
        },
        .ok => |ok| {
            var owned = ok;
            defer owned.deinit(allocator);
            if (emit_sab_path) |sab_path| {
                // SAB encode path is standalone: it never falls back to .sa text.
                // encodeSabFromFlat re-verifies and returns error.VerificationTrap
                // on failure, which we surface as a check failure.
                const sab_bytes = plugin_bridge.encodeSabFromFlat(allocator, &owned.flat, compile_options.default_immutable) catch |err| {
                    if (err == error.VerificationTrap) {
                        try stderr.print("check: SAB encode failed: verification trap\n", .{});
                        return 1;
                    }
                    return err;
                };
                defer allocator.free(sab_bytes);
                const cwd = sio.cwd();
                const sab_file = try cwd.createFile(sab_path, .{});
                defer sab_file.close();
                try sab_file.writeAll(sab_bytes);
                if (!json_mode) {
                    try stdout.print("check ok: wrote SAB binary: {s} ({d} bytes)\n", .{ sab_path, sab_bytes.len });
                }
            }
            if (json_mode) {
                try stdout.writeAll("{\"status\":\"ok\",\"metrics\":");
                try writeMetricsJson(stdout, owned.metrics);
                try stdout.print(",\"wall_ms\":{d}", .{wall_ns / 1_000_000});
                try stdout.writeAll("}\n");
            } else {
                const cache_hit = if (owned.metrics.cache) |c| c.hit else false;
                try stdout.print("check ok: instructions={d} compile_tokens={d} verdict_cache={s}\n", .{
                    owned.metrics.instruction_count,
                    owned.metrics.compile_tokens,
                    if (cache_hit) "hit" else "miss",
                });
            }
            return 0;
        },
    }
}
