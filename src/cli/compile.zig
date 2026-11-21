const std = @import("std");
const incr_verify = @import("../incr_verify.zig");
const DceMode = @import("../emit_options.zig").DceMode;
const ProjectCacheKey = @import("types.zig").ProjectCacheKey;
const isSabFunctionDecl = @import("cache.zig").isSabFunctionDecl;
const WasmTarget = @import("types.zig").WasmTarget;
const common_upstream = @import("../common/upstream_loc.zig");
const manifest = @import("../pkg/manifest.zig");
const builtin = @import("builtin");
const BuildCacheKind = @import("types.zig").BuildCacheKind;
const sio = @import("sio");
const pkg_workspace = @import("../pkg/workspace.zig");
const CompileMetrics = @import("types.zig").CompileMetrics;
const ProjectContext = @import("types.zig").ProjectContext;
const CompileMemoryMetrics = @import("types.zig").CompileMemoryMetrics;
const CompilePhaseMetrics = @import("types.zig").CompilePhaseMetrics;
const flattener = @import("../flattener.zig");
const referee = @import("../referee.zig");
const sab = @import("../sab.zig");
const trap = @import("../common/trap.zig");
const CompileOptions = @import("types.zig").CompileOptions;
const CompileResult = @import("types.zig").CompileResult;
const setFile = @import("trap_errors.zig").setFile;
const stdRootFromEnv = @import("cache.zig").stdRootFromEnv;
const build_options = @import("build_options");
const BackendIrMetrics = @import("types.zig").BackendIrMetrics;
const pkg_resolver = @import("../pkg/resolver.zig");
const verifyProjectPackageState = @import("../cli.zig").verifyProjectPackageState;
const trapFromPackagePreflightError = @import("trap_errors.zig").trapFromPackagePreflightError;
const plugins = @import("../plugins.zig");

pub var test_source_tree_load_count: usize = 0;

pub fn computeCompileMetrics(flat: *const flattener.FlattenResult, verified: *const referee.VerifyOk, phases: ?CompilePhaseMetrics, memory: ?CompileMemoryMetrics) CompileMetrics {
    const compile_tokens = @as(u64, flat.instructions.len) + @as(u64, flat.const_decls.len) + @as(u64, flat.function_sigs.len) + @as(u64, flat.test_sigs.len) + @as(u64, verified.annotated.len);
    return .{
        .compile_tokens = compile_tokens,
        .instruction_count = @as(u64, verified.annotated.len),
        .phases = phases,
        .memory = memory,
    };
}

/// Stage timing (SA_STAGE_TIMING=1): env-gated wall-clock phase summary
/// for build pipelines. When the variable is unset this is fully inert:
/// no timers run, no output is produced, and compile behaviour is
/// unchanged. When set, executeBuildExe forces phase profiling on and
/// prints one `[stage-timing]` line per successful build; the language
/// frontend dispatch in routeLanguageFrontend prints its own
/// `[stage-timing] frontend:` line.
pub fn stageTimingEnabled() bool {
    return boolEnv("SA_STAGE_TIMING");
}

pub fn projectRootFromSourcePath(allocator: std.mem.Allocator, source_path: []const u8) ![]u8 {
    var resolved = try resolveProjectFromSourcePath(allocator, source_path, null);
    defer resolved.deinit(allocator);
    return try allocator.dupe(u8, resolved.workspace_root);
}

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

pub fn boolEnv(name: []const u8) bool {
    const value = sio.getEnvVarOwned(std.heap.page_allocator, name) catch return false;
    defer std.heap.page_allocator.free(value);
    return value.len != 0 and !std.mem.eql(u8, value, "0") and !std.mem.eql(u8, value, "false") and !std.mem.eql(u8, value, "False");
}

pub fn resolveProjectFromSourcePath(allocator: std.mem.Allocator, source_path: []const u8, package_name: ?[]const u8) !pkg_workspace.PackageResolution {
    const real_source = try sio.cwd().realpathAlloc(allocator, source_path);
    defer allocator.free(real_source);
    const source_dir = std.fs.path.dirname(real_source) orelse ".";
    return try pkg_workspace.resolveFromRootPath(allocator, source_dir, .{ .request = package_name });
}

pub fn loadProjectContext(allocator: std.mem.Allocator, root_path: []const u8, package_name: ?[]const u8) !ProjectContext {
    const resolution = try pkg_workspace.resolveFromRootPath(allocator, root_path, .{ .request = package_name });

    var ctx = ProjectContext{
        .root_path = resolution.workspace_root,
        .member_root_path = resolution.member_root,
        .workspace_manifest_path = resolution.workspace_manifest_path,
        .member_manifest_path = resolution.member_manifest_path,
        .manifest = resolution.effective_manifest,
        .workspace_manifest = resolution.workspace_manifest,
        .member_manifest = resolution.member_manifest,
        .lock_file = null,
        .sum_file = null,
    };
    errdefer ctx.deinit(allocator);
    if (resolution.selected_package) |name| allocator.free(name);
    if (resolution.workspace_rel_member_path) |path| allocator.free(path);

    const lock_path = try projectLockPath(allocator, ctx.root_path);
    defer allocator.free(lock_path);
    if (try readLockFile(allocator, lock_path)) |lock_file| {
        ctx.lock_file = lock_file;
    }

    const sum_path = try projectSumPath(allocator, ctx.root_path);
    defer allocator.free(sum_path);
    if (try readSumFile(allocator, sum_path)) |sum_file| {
        ctx.sum_file = sum_file;
    }

    return ctx;
}

pub fn writeMemoryStageSampleForOptions(options: CompileOptions, label: []const u8, value: ?u64, previous: ?u64) !void {
    if (!options.mem_report_live) return;
    const writer = options.diagnostic_writer orelse return;
    try writeMemoryStageSample(writer, label, value, previous);
}

pub fn ensureParentDir(path: []const u8) !void {
    if (std.fs.path.dirname(path)) |dir| {
        if (dir.len != 0) try sio.cwd().makePath(dir);
    }
}

/// Pointer size for a cross-compilation triple (zig-style arch-os-abi).
/// Unknown triples default to 64-bit.
pub fn sizeBitsForTriple(triple: ?[]const u8) u16 {
    const t = triple orelse return nativeSizeBits();
    const arch = if (std.mem.indexOfScalar(u8, t, '-')) |i| t[0..i] else t;
    for ([_][]const u8{ "wasm32", "i386", "i486", "i586", "i686", "arm", "armeb", "thumb", "riscv32", "mips", "mipsel", "mips64el", "powerpc", "sparc", "sparcel", "s390", "xcore", "nvptx", "amdgcn", "bpfel", "bpfeb", "csky", "hexagon", "m68k", "msp430", "avr", "arc", "xtensa" }) |a32| {
        if (std.mem.eql(u8, arch, a32)) return 32;
    }
    return 64;
}

const projectLockPath = @import("cache.zig").projectLockPath;

pub fn writeMemoryStageSample(writer: anytype, label: []const u8, value: ?u64, previous: ?u64) !void {
    try writer.writeAll("memory stage ");
    try writer.writeAll(label);
    try writer.writeByte(' ');
    try writeMemoryAmount(writer, value);
    try writeMemoryDelta(writer, previous, value);
    try writer.writeByte('\n');
}

pub fn loadSabFlat(allocator: std.mem.Allocator, source_path: []const u8) !flattener.FlattenResult {
    const bytes = try loadSource(allocator, source_path);
    defer allocator.free(bytes);
    var module = try sab.decodeModule(allocator, bytes);
    errdefer module.deinit(allocator);

    var symbols = flattener.SymbolTable.init(allocator);
    errdefer symbols.deinit();
    for (module.symbols) |name| _ = try symbols.intern(name);

    if (module.owns_symbol_text) {
        for (module.symbols) |name| allocator.free(name);
    }
    allocator.free(module.symbols);
    module.symbols = &.{};
    module.owns_symbol_text = false;

    var test_sigs = std.array_list.Managed(flattener.FunctionSig).init(allocator);
    errdefer test_sigs.deinit();
    for (module.function_sigs) |fsig| {
        if (fsig.kind == .test_func) try test_sigs.append(fsig);
    }

    const loc_table = try allocator.alloc(?common_upstream.UpstreamLoc, module.instructions.len);
    @memset(loc_table, null);

    const result = flattener.FlattenResult{
        .instructions = module.instructions,
        .const_decls = module.const_decls,
        .function_sigs = module.function_sigs,
        .test_sigs = try test_sigs.toOwnedSlice(),
        .cached_macro_defs = &.{},
        .def_dict = flattener.DefDict.init(allocator),
        .symbols = symbols,
        .loc_table = loc_table,
        .layout_versions = &.{},
        .package_identities = std.StringHashMap(void).init(allocator),
        .owned_text = module.owned_text,
        .trap = null,
    };
    module.instructions = &.{};
    module.const_decls = &.{};
    module.function_sigs = &.{};
    module.owned_text = &.{};
    return result;
}

pub fn elapsedNs(start: std.Io.Timestamp) u64 {
    const end = std.Io.Clock.awake.now(sio.io());
    const ns: i96 = start.durationTo(end).toNanoseconds();
    return if (ns < 0) 0 else @intCast(ns);
}

pub fn nativeSizeBits() u16 {
    return @as(u16, @bitSizeOf(usize));
}

pub fn pathJoinAlloc(allocator: std.mem.Allocator, parts: []const []const u8) ![]u8 {
    return try std.fs.path.join(allocator, parts);
}

pub fn readLockFile(allocator: std.mem.Allocator, path: []const u8) !?manifest.LockFile {
    const source = sio.cwd().openFile(path, .{}) catch |err| switch (err) {
        error.FileNotFound => return null,
        else => return err,
    };
    defer source.close();
    const bytes = try source.readToEndAlloc(allocator, 16 * 1024 * 1024);
    defer allocator.free(bytes);
    return try manifest.parseLock(allocator, bytes);
}

pub fn writeMemoryAmount(writer: anytype, value: ?u64) !void {
    const bytes = value orelse {
        try writer.writeAll("n/a");
        return;
    };
    const bytes_per_mib: u64 = 1024 * 1024;
    const tenths = (bytes * 10 + bytes_per_mib / 2) / bytes_per_mib;
    try writer.print("{d}.{d} MiB", .{ tenths / 10, tenths % 10 });
}

pub fn loadSource(allocator: std.mem.Allocator, path: []const u8) ![]u8 {
    if (builtin.is_test) test_source_tree_load_count += 1;
    var file = try sio.cwd().openFile(path, .{});
    defer file.close();
    // C2b: the 16 MiB cap also guards .sab inputs, but the SLA compiler
    // emits .sab files far beyond that for large module closures
    // (measured 20-85 MiB for the saVmTool closure), so `sa test` on
    // such a .sab died with error.StreamTooLong before doing any work.
    // Source files are fully buffered by every downstream stage anyway;
    // keep a 1 GiB sanity ceiling instead.
    const bytes = try file.readToEndAlloc(allocator, 1024 * 1024 * 1024);
    // A SAB fragment container is not a program: whatever path or
    // extension it arrives under, it must never be flattened as text
    // or decoded as a module here. Reject it by name at the single
    // source-loading choke point every command path shares.
    if (sab.isFragmentBytes(bytes)) {
        allocator.free(bytes);
        return error.SabFragmentNotAProgram;
    }
    return bytes;
}

const computeProjectBuildKey = @import("cache.zig").computeProjectBuildKey;

pub fn recordMetricMemoryAfterEmit(metrics: *CompileMetrics) void {
    if (metrics.memory) |*memory| memory.recordAfterEmit();
}

const projectSumPath = @import("cache.zig").projectSumPath;

pub fn writeMemoryDelta(writer: anytype, previous: ?u64, current: ?u64) !void {
    const prev = previous orelse return;
    const curr = current orelse return;
    try writer.writeAll("  delta ");
    if (curr >= prev) {
        try writer.writeByte('+');
        try writeMemoryAmount(writer, curr - prev);
    } else {
        try writer.writeByte('-');
        try writeMemoryAmount(writer, prev - curr);
    }
}

const pruneSabFlatToSelectedTests = @import("cache.zig").pruneSabFlatToSelectedTests;

const readSumFile = @import("cache.zig").readSumFile;

pub fn trustedSabVerifyOk(allocator: std.mem.Allocator, flat: *flattener.FlattenResult) !referee.VerifyOk {
    // Verdict-cache fast path: the reused sigs never went through scope
    // finalization, so rebuild verifier-equivalent reg scopes (and localize
    // body regs to slots) before codegen, which requires populated reg_ids.
    try referee.populateTrustedRegScopes(allocator, flat.instructions, flat.const_decls, flat.function_sigs, &flat.symbols);
    var annotated = std.array_list.Managed(referee.AnnotatedInstruction).init(allocator);
    errdefer annotated.deinit();
    var fatal_terminated = false;
    for (flat.instructions) |item| {
        if (fatal_terminated and item.kind != .label and !isSabFunctionDecl(item.kind)) continue;
        if (item.kind == .label or isSabFunctionDecl(item.kind)) fatal_terminated = false;
        try annotated.append(.{
            .base = item,
            .delta = .{ .changes = &.{} },
            .gas_step_cost = 0,
        });
        if (item.kind == .panic or item.kind == .panic_msg) fatal_terminated = true;
    }
    const annotated_slice = try annotated.toOwnedSlice();
    errdefer allocator.free(annotated_slice);

    const function_sigs = flat.function_sigs;
    flat.function_sigs = &.{};

    const symbols = flat.symbols;
    flat.symbols = flattener.SymbolTable.init(allocator);

    return .{
        .annotated = annotated_slice,
        .function_sigs = function_sigs,
        .symbols = symbols,
        .const_decls = flat.const_decls,
        .gas = .{
            .max_alloc_bytes = 0,
            .max_instruction_steps = .{ .bounded = 0 },
            .call_depth = 0,
            .has_unbounded_loop = false,
        },
    };
}

const projectCacheHit = @import("cache.zig").projectCacheHit;

pub fn recordMetricMemoryEnd(metrics: *CompileMetrics) void {
    if (metrics.memory) |*memory| memory.recordEnd();
}

/// Verification mode byte folded into the incremental verdict digest so a
/// verdict produced in one mode is never reused in another.
pub fn verifyModeByte(default_immutable: bool) u8 {
    return if (default_immutable) 1 else 0;
}

/// `#npm_bind` bindings only lower under `sa build-js`. Every other
/// emit/run path rejects them here with a targeted diagnostic instead of
/// a confusing missing-symbol failure downstream (JS target only; the
/// wasm and native backends have no ESM import mechanism).
pub fn rejectNpmBindsUnlessJs(cmd_name: []const u8, flat: *const flattener.FlattenResult, stderr: anytype) !void {
    if (flat.def_dict.npm_binds.count() == 0) return;
    try stderr.print("error: {s} does not support `#npm_bind` npm imports; use `sa build-js` (JS target only)\n", .{cmd_name});
    return error.NpmImportJsOnly;
}

pub fn tripleIsWindows(triple: ?[]const u8) bool {
    const t = triple orelse return builtin.os.tag == .windows;
    return std.mem.indexOf(u8, t, "windows") != null;
}

pub fn saStdArchivePath(allocator: std.mem.Allocator) ![]u8 {
    const archive_name = switch (builtin.os.tag) {
        .windows => "sa_std.lib",
        else => "libsa_std.a",
    };
    if (builtin.is_test) {
        return try allocator.dupe(u8, build_options.sa_std_archive_path);
    }
    const env_root: ?[]u8 = sio.getEnvVarOwned(allocator, "SA_STD_DIR") catch |err| switch (err) {
        error.EnvironmentVariableNotFound => null,
        else => return err,
    };
    if (env_root) |root| {
        errdefer allocator.free(root);
        const archive = try std.fs.path.join(allocator, &.{ root, archive_name });
        if (sio.cwd().openFile(archive, .{})) |file| {
            file.close();
            allocator.free(root);
            return archive;
        } else |_| {
            allocator.free(archive);
        }
        allocator.free(root);
    }
    return try allocator.dupe(u8, build_options.sa_std_archive_path);
}

/// Locate the sa_std static archive for an optional cross-compilation triple.
/// Layout: $SA_STD_DIR/<triple>/libsa_std.a (or sa_std.lib for windows triples).
/// Returns error.ArchiveNotFoundForTarget when the triple archive is missing.
pub fn saStdArchivePathForTarget(allocator: std.mem.Allocator, target_triple: ?[]const u8) ![]u8 {
    const triple = target_triple orelse return saStdArchivePath(allocator);
    const archive_name: []const u8 = if (tripleIsWindows(target_triple)) "sa_std.lib" else "libsa_std.a";
    const env_root: ?[]u8 = sio.getEnvVarOwned(allocator, "SA_STD_DIR") catch |err| switch (err) {
        error.EnvironmentVariableNotFound => null,
        else => return err,
    };
    if (env_root) |root| {
        defer allocator.free(root);
        const archive = try std.fs.path.join(allocator, &.{ root, triple, archive_name });
        errdefer allocator.free(archive);
        if (sio.cwd().openFile(archive, .{})) |file| {
            file.close();
            return archive;
        } else |_| {}
        return error.ArchiveNotFoundForTarget;
    }
    // No SA_STD_DIR: fall back to the directory holding the host
    // archive (the baked build path), with the same <triple>/ layout.
    // This mirrors saStdArchivePath's own baked fallback for the host
    // target; without it cross archives built into the tree were
    // unreachable unless the user hand-exported SA_STD_DIR.
    const host_archive = try saStdArchivePath(allocator);
    defer allocator.free(host_archive);
    const host_dir = std.fs.path.dirname(host_archive) orelse return error.ArchiveNotFoundForTarget;
    const archive = try std.fs.path.join(allocator, &.{ host_dir, triple, archive_name });
    errdefer allocator.free(archive);
    if (sio.cwd().openFile(archive, .{})) |file| {
        file.close();
        return archive;
    } else |_| {}
    return error.ArchiveNotFoundForTarget;
}

pub fn estimateBackendIrMetrics(verified: *const referee.VerifyOk, debug: bool) BackendIrMetrics {
    var out = BackendIrMetrics{};
    var sig_index: usize = 0;
    for (verified.annotated) |item| {
        switch (item.base.kind) {
            .func_decl, .ffi_wrapper_decl, .extern_decl, .export_decl, .test_decl, .gpu_decl => {
                out.functions += 1;
                out.blocks += 1;
                if (sig_index < verified.function_sigs.len) {
                    if (debug) out.alloca_slots += @as(u64, @intCast(verified.function_sigs[sig_index].reg_ids.len));
                    sig_index += 1;
                }
            },
            .label => out.blocks += 1,
            .load, .take, .atomic_load => {
                out.instructions += 1;
                out.loads += 1;
            },
            .store, .atomic_store => {
                out.instructions += 1;
                out.stores += 1;
            },
            .move_, .release => {},
            else => out.instructions += 1,
        }
    }
    return out;
}

pub fn attachBackendIrMetrics(metrics: *CompileMetrics, verified: *const referee.VerifyOk, debug: bool) void {
    if (metrics.phases == null) return;
    metrics.backend_ir = estimateBackendIrMetrics(verified, debug);
}

pub fn cguSeqShardCount() ?usize {
    const value = sio.getEnvVarOwned(std.heap.page_allocator, "SA_CGU_SEQ_SHARDS") catch return null;
    defer std.heap.page_allocator.free(value);
    const n = std.fmt.parseInt(usize, std.mem.trim(u8, value, " \t\r\n"), 10) catch return null;
    if (n < 2 or n > 64) return null;
    return n;
}

pub fn recordMetricMemoryAfterLink(metrics: *CompileMetrics) void {
    if (metrics.memory) |*memory| memory.recordAfterLink();
}

pub fn freeOwnedStringSlice(allocator: std.mem.Allocator, items: []const []const u8) void {
    for (items) |item| allocator.free(item);
    allocator.free(items);
}

pub fn dirExistsAbsolute(path: []const u8) bool {
    var dir = sio.openDirAbsolute(path, .{}) catch return false;
    dir.close();
    return true;
}

pub fn defaultStableImportRoots(allocator: std.mem.Allocator, project_root: []const u8) ![]const []const u8 {
    var roots = std.array_list.Managed([]const u8).init(allocator);
    errdefer {
        for (roots.items) |root| allocator.free(root);
        roots.deinit();
    }

    const unit_support = try std.fs.path.join(allocator, &.{ project_root, "tests", "unit_framework", "support" });
    if (dirExistsAbsolute(unit_support)) {
        try roots.append(unit_support);
    } else {
        allocator.free(unit_support);
    }

    return try roots.toOwnedSlice();
}

pub fn cguForceParallel() bool {
    return boolEnv("SA_CGU_PARALLEL");
}

pub const cgu_seq_fn_threshold: usize = 2048;

pub fn manifestDependencies(manifest_file: *const manifest.Manifest, allocator: std.mem.Allocator) ![]pkg_resolver.Dependency {
    var deps = std.array_list.Managed(pkg_resolver.Dependency).init(allocator);
    errdefer deps.deinit();

    for (manifest_file.requires) |entry| {
        try deps.append(.{
            .url = entry.url,
            .ref = entry.ref,
            .source_sha256 = entry.source_sha256,
        });
    }

    return try deps.toOwnedSlice();
}

pub fn manifestPluginImportRoots(manifest_file: *const manifest.Manifest, allocator: std.mem.Allocator) ![]const []const u8 {
    var roots = std.array_list.Managed([]const u8).init(allocator);
    errdefer {
        for (roots.items) |root| allocator.free(root);
        roots.deinit();
    }

    if (manifest_file.plugin_requires.len == 0) return try roots.toOwnedSlice();

    const home = try plugins.pluginsHomePath(allocator);
    defer allocator.free(home);

    for (manifest_file.plugin_requires) |entry| {
        try roots.append(try std.fs.path.join(allocator, &.{ home, "installed", entry.identity, "current", "sa" }));
    }

    return try roots.toOwnedSlice();
}
