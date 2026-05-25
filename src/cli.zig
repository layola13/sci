const std = @import("std");
const builtin = @import("builtin");

const flattener = @import("flattener.zig");
const line_classifier = @import("flattener/line_classifier.zig");
const interp = @import("interp.zig");
const build_options = @import("build_options");
const driver = @import("driver/zigcc.zig");
const emit_llvm_llvmc = @import("emit_llvm_llvmc.zig");
const bc2sa = @import("llvm2sa.zig");
const layout = @import("layout.zig");
const manifest = @import("pkg/manifest.zig");
const pkg_audit = @import("pkg/audit.zig");
const pkg_ci = @import("pkg/ci.zig");
const pkg_confirm = @import("pkg/confirm.zig");
const pkg_fetch = @import("pkg/fetch.zig");
const pkg_mirror = @import("pkg/mirror.zig");
const pkg_resolver = @import("pkg/resolver.zig");
const pkg_sum = @import("pkg/sum.zig");
const referee_call = @import("referee/call.zig");
const referee = @import("referee.zig");
const test_meta = @import("test_meta.zig");
const test_runner = @import("test_runner.zig");
const trap = @import("common/trap.zig");
const common_upstream = @import("common/upstream_loc.zig");

fn intermediateArtifactPath(allocator: std.mem.Allocator, out_path: []const u8) ![]u8 {
    return try std.fmt.allocPrint(allocator, "{s}.sa.bc", .{out_path});
}

const CompileOk = struct {
    flat: flattener.FlattenResult,
    verified: referee.VerifyOk,
    metrics: CompileMetrics,

    fn deinit(self: *CompileOk, allocator: std.mem.Allocator) void {
        self.verified.deinit(allocator);
        self.flat.deinit(allocator);
        self.* = undefined;
    }
};

const CompileResult = union(enum) {
    ok: CompileOk,
    trap: trap.TrapReport,
};

const GraphNodeKind = enum {
    source_file,
    function,
    call_target,
};

const GraphNode = struct {
    id: []const u8,
    kind: GraphNodeKind,
    label: []const u8,
};

const GraphEdgeKind = enum {
    imports,
    calls,
};

const GraphEdge = struct {
    from: []const u8,
    to: []const u8,
    kind: GraphEdgeKind,
};

const FunctionSizeEntry = struct {
    name: []const u8,
    instruction_count: u64,
    byte_count: u64,
};

const CompilePhaseMetrics = struct {
    load_ns: u64 = 0,
    setup_ns: u64 = 0,
    flatten_ns: u64 = 0,
    verify_ns: u64 = 0,
    emit_ns: ?u64 = null,
    link_ns: ?u64 = null,
    total_ns: ?u64 = null,
};

const CompileMetrics = struct {
    compile_tokens: u64,
    instruction_count: u64,
    phases: ?CompilePhaseMetrics = null,
};

fn computeCompileMetrics(flat: *const flattener.FlattenResult, verified: *const referee.VerifyOk, phases: ?CompilePhaseMetrics) CompileMetrics {
    const compile_tokens = @as(u64, flat.instructions.len) + @as(u64, flat.const_decls.len) + @as(u64, flat.function_sigs.len) + @as(u64, flat.test_sigs.len) + @as(u64, verified.annotated.len);
    return .{
        .compile_tokens = compile_tokens,
        .instruction_count = @as(u64, verified.annotated.len),
        .phases = phases,
    };
}

fn elapsedNs(start: std.time.Instant) u64 {
    const end = std.time.Instant.now() catch return 0;
    return end.since(start);
}

fn finishProfileMetrics(metrics: *CompileMetrics, emit_ns: ?u64, link_ns: ?u64, total_ns: ?u64) void {
    if (metrics.phases) |phases| {
        metrics.phases = .{
            .load_ns = phases.load_ns,
            .setup_ns = phases.setup_ns,
            .flatten_ns = phases.flatten_ns,
            .verify_ns = phases.verify_ns,
            .emit_ns = emit_ns,
            .link_ns = link_ns,
            .total_ns = total_ns,
        };
    }
}

fn computeFunctionSizes(allocator: std.mem.Allocator, verified: *const referee.VerifyOk) ![]FunctionSizeEntry {
    var entries = std.ArrayList(FunctionSizeEntry).init(allocator);
    errdefer entries.deinit();

    for (verified.function_sigs, 0..) |sig_item, idx| {
        const start = @as(usize, @intCast(sig_item.entry_inst_idx));
        const end = if (idx + 1 < verified.function_sigs.len)
            @as(usize, @intCast(verified.function_sigs[idx + 1].entry_inst_idx))
        else
            verified.annotated.len;

        var instruction_count: u64 = 0;
        var byte_count: u64 = 0;
        if (start < end and end <= verified.annotated.len) {
            for (verified.annotated[start..end]) |item| {
                instruction_count += 1;
                byte_count += @as(u64, @intCast(item.base.raw_text.len));
            }
        }

        try entries.append(.{
            .name = sig_item.name,
            .instruction_count = instruction_count,
            .byte_count = byte_count,
        });
    }

    return try entries.toOwnedSlice();
}

const GraphBuildContext = struct {
    allocator: std.mem.Allocator,
    node_map: *std.StringHashMap(usize),
    nodes: *std.ArrayList(GraphNode),
    edges: *std.ArrayList(GraphEdge),
    dependencies: []const pkg_resolver.Dependency,
    project_root: []const u8,
    offline: bool,
};

fn graphNodeId(allocator: std.mem.Allocator, kind: []const u8, text: []const u8) ![]u8 {
    return try std.fmt.allocPrint(allocator, "{s}:{s}", .{ kind, text });
}

fn graphNodeKindName(kind: GraphNodeKind) []const u8 {
    return switch (kind) {
        .source_file => "source_file",
        .function => "function",
        .call_target => "call_target",
    };
}

fn graphEdgeKindName(kind: GraphEdgeKind) []const u8 {
    return switch (kind) {
        .imports => "imports",
        .calls => "calls",
    };
}

fn ensureGraphNode(ctx: *GraphBuildContext, id: []const u8, kind: GraphNodeKind, label: []const u8) !usize {
    if (ctx.node_map.get(id)) |index| {
        ctx.allocator.free(id);
        return index;
    }

    const key = try ctx.allocator.dupe(u8, id);
    errdefer ctx.allocator.free(key);
    const label_copy = try ctx.allocator.dupe(u8, label);
    errdefer ctx.allocator.free(label_copy);

    const index = ctx.nodes.items.len;
    try ctx.node_map.put(key, index);
    try ctx.nodes.append(.{
        .id = id,
        .kind = kind,
        .label = label_copy,
    });
    return index;
}

fn appendGraphEdge(ctx: *GraphBuildContext, from: []const u8, to: []const u8, kind: GraphEdgeKind) !void {
    try ctx.edges.append(.{ .from = from, .to = to, .kind = kind });
}

fn collectSourceGraph(ctx: *GraphBuildContext, source_path: []const u8) !usize {
    const source_id = try graphNodeId(ctx.allocator, "source", source_path);
    if (ctx.node_map.get(source_id)) |index| {
        ctx.allocator.free(source_id);
        return index;
    }

    const stable_source_id = try ensureGraphNode(ctx, source_id, .source_file, source_path);
    const source = try loadSource(ctx.allocator, source_path);
    defer ctx.allocator.free(source);

    var iter = std.mem.splitScalar(u8, source, '\n');
    while (iter.next()) |line| {
        const classified = line_classifier.classifyLine(line);
        if (classified.kind != .import_decl) continue;
        const import_path = classified.parts[0];
        var imported = try pkg_resolver.resolveImport(ctx.allocator, ctx.dependencies, std.fs.path.dirname(source_path) orelse ".", import_path, .{
            .project_root = ctx.project_root,
            .offline = ctx.offline,
        });
        defer imported.deinit(ctx.allocator);

        const child_index = try collectSourceGraph(ctx, imported.entry_path);
        try appendGraphEdge(ctx, ctx.nodes.items[stable_source_id].id, ctx.nodes.items[child_index].id, .imports);
    }

    return stable_source_id;
}

fn buildFunctionGraph(ctx: *GraphBuildContext, verified: *const referee.VerifyOk) !std.StringHashMap(usize) {
    var function_nodes = std.StringHashMap(usize).init(ctx.allocator);
    errdefer function_nodes.deinit();

    for (verified.function_sigs) |sig_item| {
        const node_id = try graphNodeId(ctx.allocator, "function", sig_item.name);
        const index = try ensureGraphNode(ctx, node_id, .function, sig_item.name);
        try function_nodes.put(sig_item.name, index);
    }

    return function_nodes;
}

fn buildCallGraph(
    ctx: *GraphBuildContext,
    verified: *const referee.VerifyOk,
    function_nodes: *const std.StringHashMap(usize),
) !void {
    var current_fn: ?usize = null;
    var sig_index: usize = 0;

    for (verified.annotated) |item| {
        switch (item.base.kind) {
            .func_decl, .ffi_wrapper_decl, .extern_decl, .export_decl, .test_decl => {
                if (sig_index >= verified.function_sigs.len) break;
                const sig_item = verified.function_sigs[sig_index];
                sig_index += 1;
                current_fn = function_nodes.get(sig_item.name);
            },
            .call, .call_indirect => {
                const caller_index = current_fn orelse continue;
                var parsed = referee_call.parseCall(ctx.allocator, item.base.raw_text) catch continue;
                defer parsed.deinit(ctx.allocator);

                const target_index = if (function_nodes.get(parsed.callee)) |fn_idx| blk: {
                    break :blk fn_idx;
                } else blk: {
                    const call_target_id = try graphNodeId(ctx.allocator, "target", parsed.callee);
                    break :blk try ensureGraphNode(ctx, call_target_id, .call_target, parsed.callee);
                };
                try appendGraphEdge(ctx, ctx.nodes.items[caller_index].id, ctx.nodes.items[target_index].id, .calls);
            },
            else => {},
        }
    }
}

fn writeGraphJson(writer: anytype, metrics: CompileMetrics, nodes: []const GraphNode, edges: []const GraphEdge) !void {
    try writer.writeAll("{\"status\":\"ok\",\"metrics\":");
    try writeMetricsJson(writer, metrics);
    try writer.writeAll(",\"graph\":{\"nodes\":[");
    for (nodes, 0..) |node, idx| {
        if (idx != 0) try writer.writeByte(',');
        try writer.writeByte('{');
        try writer.writeAll("\"id\":");
        try writeJsonString(writer, node.id);
        try writer.writeAll(",\"kind\":");
        try writeJsonString(writer, graphNodeKindName(node.kind));
        try writer.writeAll(",\"label\":");
        try writeJsonString(writer, node.label);
        try writer.writeByte('}');
    }
    try writer.writeAll("],\"edges\":[");
    for (edges, 0..) |edge, idx| {
        if (idx != 0) try writer.writeByte(',');
        try writer.writeByte('{');
        try writer.writeAll("\"from\":");
        try writeJsonString(writer, edge.from);
        try writer.writeAll(",\"to\":");
        try writeJsonString(writer, edge.to);
        try writer.writeAll(",\"kind\":");
        try writeJsonString(writer, graphEdgeKindName(edge.kind));
        try writer.writeByte('}');
    }
    try writer.writeAll("]}}\n");
}

fn writeGraphText(writer: anytype, metrics: CompileMetrics, nodes: []const GraphNode, edges: []const GraphEdge) !void {
    try writer.print("compile_tokens: {d}\n", .{metrics.compile_tokens});
    try writer.print("instruction_count: {d}\n", .{metrics.instruction_count});
    try writer.print("nodes: {d}\n", .{nodes.len});
    for (nodes) |node| {
        try writer.print("- {s} [{s}] {s}\n", .{ node.id, graphNodeKindName(node.kind), node.label });
    }
    try writer.print("edges: {d}\n", .{edges.len});
    for (edges) |edge| {
        try writer.print("- {s} -> {s} ({s})\n", .{ edge.from, edge.to, graphEdgeKindName(edge.kind) });
    }
}

fn writeSizeJson(writer: anytype, metrics: CompileMetrics, entries: []const FunctionSizeEntry) !void {
    try writer.writeAll("{\"status\":\"ok\",\"metrics\":");
    try writeMetricsJson(writer, metrics);
    try writer.writeAll(",\"functions\":[");
    for (entries, 0..) |entry, idx| {
        if (idx != 0) try writer.writeByte(',');
        try writer.writeByte('{');
        try writer.writeAll("\"name\":");
        try writeJsonString(writer, entry.name);
        try writer.writeAll(",\"instruction_count\":");
        try writer.print("{d}", .{entry.instruction_count});
        try writer.writeAll(",\"byte_count\":");
        try writer.print("{d}", .{entry.byte_count});
        try writer.writeByte('}');
    }
    try writer.writeAll("]}\n");
}

fn writeSizeText(writer: anytype, metrics: CompileMetrics, entries: []const FunctionSizeEntry) !void {
    try writer.print("compile_tokens: {d}\n", .{metrics.compile_tokens});
    try writer.print("instruction_count: {d}\n", .{metrics.instruction_count});
    try writer.writeAll("functions:\n");
    for (entries) |entry| {
        try writer.print("- {s}: instructions={d} bytes={d}\n", .{ entry.name, entry.instruction_count, entry.byte_count });
    }
}

const CompileOptions = struct {
    jobs: ?usize = null,
    jobs_explicit: bool = false,
    offline: bool = false,
    ci: bool = false,
    allow_unaudited_risks: bool = false,
    auto_approve_requested: bool = false,
    project_root: ?[]const u8 = null,
    profile: bool = false,
    stdin_reader: ?std.io.AnyReader = null,
    stdin_is_tty: ?bool = null,
    diagnostic_writer: ?std.io.AnyWriter = null,
};

pub const DiagnosticsMode = enum {
    human,
    json,
};

pub const ExplainEntry = struct {
    codes: []const []const u8,
    title: []const u8,
    summary: []const u8,
    details: []const []const u8,
    fix_hint: ?[]const u8 = null,
};

pub const FixPlanStep = struct {
    action: []const u8,
    target: []const u8,
    detail: []const u8,
};

pub const FixPlan = struct {
    steps: []const FixPlanStep,
    rationale: []const []const u8,
};

pub const SkillSection = struct {
    name: []const u8,
    summary: []const u8,
    items: []const []const u8,
};

const CliErrorInfo = struct {
    code: ?[]const u8,
    message: []const u8,
    hint: ?[]const u8,
};

const Command = enum {
    run,
    init,
    install,
    build,
    build_exe,
    build_wasm,
    build_obj,
    bc2sa,
    audit,
    graph,
    layout,
    fetch,
    size,
    test_cmd,
    explain,
    fix,
    skills,
    help,
    version,
};

pub fn hasJsonFlag(argv: []const []const u8) bool {
    for (argv) |arg| {
        if (std.mem.eql(u8, arg, "--json")) return true;
    }
    return false;
}

fn stripJsonFlag(allocator: std.mem.Allocator, argv: []const []const u8) ![]const []const u8 {
    var items = std.ArrayList([]const u8).init(allocator);
    errdefer items.deinit();

    for (argv) |arg| {
        if (std.mem.eql(u8, arg, "--json")) continue;
        try items.append(arg);
    }

    return try items.toOwnedSlice();
}

const ProjectTargetKind = enum {
    native,
    wasm32,
    wasm64,
};

const ProjectTarget = struct {
    kind: ProjectTargetKind,
    name: []const u8,
    output_suffix: []const u8,
    source_suffix: []const u8,
    wasm: ?WasmTarget = null,
    size_bits: u16,
};

const AuditHit = struct {
    capability: manifest.Capability,
    callee: []const u8,
    raw_text: []const u8,
    source_line: u32,
    upstream_loc: ?common_upstream.UpstreamLoc,

    fn deinit(self: *AuditHit, allocator: std.mem.Allocator) void {
        if (self.upstream_loc) |loc| allocator.free(loc.file);
        allocator.free(self.callee);
        allocator.free(self.raw_text);
        self.* = undefined;
    }
};

const PackageAudit = struct {
    identity: []const u8,
    ref: []const u8,
    source_sha256: [32]u8,
    declared_grants: []const manifest.Capability,
    hits: std.ArrayList(AuditHit),
    requested_caps: std.ArrayList(manifest.Capability),
    risk_score: u8 = 100,
    approved_hash: ?[32]u8 = null,
    source_sha_matches: bool = true,
    lock_present: bool = false,
    lock_hash_matches: bool = false,

    fn deinit(self: *PackageAudit, allocator: std.mem.Allocator) void {
        for (self.hits.items) |*hit| hit.deinit(allocator);
        self.hits.deinit();
        allocator.free(self.identity);
        allocator.free(self.ref);
        allocator.free(self.declared_grants);
        self.requested_caps.deinit();
        self.* = undefined;
    }
};

const AuditReport = struct {
    packages: std.ArrayList(PackageAudit),
    fn deinit(self: *AuditReport, allocator: std.mem.Allocator) void {
        for (self.packages.items) |*item| item.deinit(allocator);
        self.packages.deinit();
        self.* = undefined;
    }
};

const ProjectAuditResult = union(enum) {
    ok: AuditReport,
    trap: trap.TrapReport,
};

const TemporaryApproval = struct {
    url: []const u8,
    ref: []const u8,
    source_sha256: [32]u8,
    grants: []const manifest.Capability,
};

const ProjectBuildOptions = struct {
    ci: bool = false,
    allow_unaudited_risks: bool = false,
    offline: bool = false,
    all_targets: bool = false,
    lock_only: bool = false,
    debug: bool = false,
    release_fast: bool = false,
    out_path: ?[]const u8 = null,
    jobs: ?usize = null,
};

const ProjectAuditOptions = struct {
    update_lock: bool = false,
    offline: bool = false,
    all_targets: bool = false,
    jobs: ?usize = null,
};

const ProjectBuildArtifact = struct {
    name: []const u8,
    out_path: []const u8,
    artifact_path: []const u8,
    target_name: []const u8,
    source_suffix: []const u8,
    hash_key: []const u8,

    fn deinit(self: *ProjectBuildArtifact, allocator: std.mem.Allocator) void {
        allocator.free(self.name);
        allocator.free(self.out_path);
        allocator.free(self.artifact_path);
        allocator.free(self.target_name);
        allocator.free(self.source_suffix);
        allocator.free(self.hash_key);
        self.* = undefined;
    }
};

const ProjectContext = struct {
    root_path: []const u8,
    manifest_path: []const u8,
    manifest: ?manifest.Manifest,
    lock_file: ?manifest.LockFile,
    sum_file: ?manifest.SumFile,

    fn deinit(self: *ProjectContext, allocator: std.mem.Allocator) void {
        if (self.manifest) |*m| m.deinit(allocator);
        if (self.lock_file) |*lock| lock.deinit(allocator);
        if (self.sum_file) |*sum| sum.deinit(allocator);
        allocator.free(self.root_path);
        allocator.free(self.manifest_path);
        self.* = undefined;
    }
};

const WasmTarget = struct {
    triple: []const u8,
    no_entry: bool,
    size_bits: u16,
};

fn nativeSizeBits() u16 {
    return @as(u16, @bitSizeOf(usize));
}

fn boolEnv(name: []const u8) bool {
    const value = std.process.getEnvVarOwned(std.heap.page_allocator, name) catch return false;
    defer std.heap.page_allocator.free(value);
    return value.len != 0 and !std.mem.eql(u8, value, "0") and !std.mem.eql(u8, value, "false") and !std.mem.eql(u8, value, "False");
}

fn stdinIsTty() bool {
    return std.posix.isatty(std.io.getStdIn().handle);
}

fn isCiMode(options: ProjectBuildOptions) bool {
    return options.ci or boolEnv("CI") or boolEnv("GITHUB_ACTIONS") or !stdinIsTty();
}

fn isProjectRootPath(path: []const u8) bool {
    return std.fs.path.basename(path).len != 0;
}

fn projectRootDir(allocator: std.mem.Allocator) ![]u8 {
    return std.fs.cwd().realpathAlloc(allocator, ".") catch return error.InvalidPath;
}

fn pathJoinAlloc(allocator: std.mem.Allocator, parts: []const []const u8) ![]u8 {
    return try std.fs.path.join(allocator, parts);
}

fn projectPathExists(path: []const u8) bool {
    std.fs.cwd().access(path, .{}) catch return false;
    return true;
}

fn readTextFileAlloc(allocator: std.mem.Allocator, path: []const u8) ![]u8 {
    var file = try std.fs.cwd().openFile(path, .{});
    defer file.close();
    return try file.readToEndAlloc(allocator, 16 * 1024 * 1024);
}

fn projectManifestPath(allocator: std.mem.Allocator, root_path: []const u8) ![]u8 {
    return try pathJoinAlloc(allocator, &.{ root_path, "sa.mod" });
}

fn projectLockPath(allocator: std.mem.Allocator, root_path: []const u8) ![]u8 {
    return try pathJoinAlloc(allocator, &.{ root_path, "sa.lock" });
}

fn projectSumPath(allocator: std.mem.Allocator, root_path: []const u8) ![]u8 {
    return try pathJoinAlloc(allocator, &.{ root_path, "sa.sum" });
}

fn projectSourcePath(allocator: std.mem.Allocator, root_path: []const u8) ![]u8 {
    const src_path = try pathJoinAlloc(allocator, &.{ root_path, "src", "main.sa" });
    if (projectPathExists(src_path)) return src_path;
    allocator.free(src_path);
    const fallback = try pathJoinAlloc(allocator, &.{ root_path, "main.sa" });
    if (projectPathExists(fallback)) return fallback;
    allocator.free(fallback);
    return error.FileNotFound;
}

fn readManifestFile(allocator: std.mem.Allocator, path: []const u8) !manifest.Manifest {
    const source = try readTextFileAlloc(allocator, path);
    defer allocator.free(source);
    return try manifest.parseManifestWithFile(allocator, source, path);
}

fn readLockFile(allocator: std.mem.Allocator, path: []const u8) !?manifest.LockFile {
    const source = std.fs.cwd().openFile(path, .{}) catch |err| switch (err) {
        error.FileNotFound => return null,
        else => return err,
    };
    defer source.close();
    const bytes = try source.readToEndAlloc(allocator, 16 * 1024 * 1024);
    defer allocator.free(bytes);
    return try manifest.parseLock(allocator, bytes);
}

fn readSumFile(allocator: std.mem.Allocator, path: []const u8) !?manifest.SumFile {
    const source = std.fs.cwd().openFile(path, .{}) catch |err| switch (err) {
        error.FileNotFound => return null,
        else => return err,
    };
    defer source.close();
    const bytes = try source.readToEndAlloc(allocator, 16 * 1024 * 1024);
    defer allocator.free(bytes);
    return try manifest.parseSum(allocator, bytes);
}

fn loadProjectContext(allocator: std.mem.Allocator, root_path: []const u8) !ProjectContext {
    const root_copy = try allocator.dupe(u8, root_path);
    errdefer allocator.free(root_copy);
    const manifest_path = try projectManifestPath(allocator, root_copy);
    errdefer allocator.free(manifest_path);

    var ctx = ProjectContext{
        .root_path = root_copy,
        .manifest_path = manifest_path,
        .manifest = null,
        .lock_file = null,
        .sum_file = null,
    };

    const manifest_file = readManifestFile(allocator, manifest_path) catch |err| switch (err) {
        error.FileNotFound => null,
        else => return err,
    };
    ctx.manifest = manifest_file;

    const lock_path = try projectLockPath(allocator, root_copy);
    defer allocator.free(lock_path);
    if (try readLockFile(allocator, lock_path)) |lock_file| {
        ctx.lock_file = lock_file;
    }

    const sum_path = try projectSumPath(allocator, root_copy);
    defer allocator.free(sum_path);
    if (try readSumFile(allocator, sum_path)) |sum_file| {
        ctx.sum_file = sum_file;
    }

    return ctx;
}

fn sourceHashHex(hash: [32]u8) [64]u8 {
    return std.fmt.bytesToHex(hash, .lower);
}

fn hashBytes(bytes: []const u8) [32]u8 {
    var hasher = std.crypto.hash.sha2.Sha256.init(.{});
    hasher.update(bytes);
    var out: [32]u8 = undefined;
    hasher.final(&out);
    return out;
}

fn sourceStem(path: []const u8) []const u8 {
    const basename = std.fs.path.basename(path);
    const dot = std.mem.lastIndexOfScalar(u8, basename, '.') orelse return basename;
    return basename[0..dot];
}

fn projectTargetKey(allocator: std.mem.Allocator, target_name: []const u8, source_suffix: []const u8) ![]u8 {
    return try std.fmt.allocPrint(allocator, "{s}:{s}", .{ target_name, source_suffix });
}

fn projectTargetDisplayName(allocator: std.mem.Allocator, target_name: []const u8, source_suffix: []const u8) ![]u8 {
    if (source_suffix.len == 0) return try allocator.dupe(u8, target_name);
    return try std.fmt.allocPrint(allocator, "{s}:{s}", .{ target_name, source_suffix });
}

fn targetTripleName(target: builtin.Target) ![]u8 {
    return try target.zigTriple(std.heap.page_allocator);
}

fn emitSumFromManifest(allocator: std.mem.Allocator, manifest_file: *const manifest.Manifest) !manifest.SumFile {
    var entries = std.ArrayList(manifest.SumEntry).init(allocator);
    errdefer {
        for (entries.items) |*entry| entry.deinit(allocator);
        entries.deinit();
    }

    for (manifest_file.requires) |entry| {
        try entries.append(.{
            .url = try allocator.dupe(u8, entry.url),
            .ref = try allocator.dupe(u8, entry.ref),
            .source_sha256 = entry.source_sha256,
            .depth = 0,
        });
    }

    std.sort.insertion(manifest.SumEntry, entries.items, {}, struct {
        fn lessThan(_: void, lhs: manifest.SumEntry, rhs: manifest.SumEntry) bool {
            const order = std.mem.order(u8, lhs.url, rhs.url);
            if (order != .eq) return order == .lt;
            return std.mem.order(u8, lhs.ref, rhs.ref) == .lt;
        }
    }.lessThan);

    return .{ .entries = try entries.toOwnedSlice() };
}

fn targetHashKeyForName(allocator: std.mem.Allocator, name: []const u8, source_suffix: []const u8) ![]const u8 {
    return try projectTargetKey(allocator, name, source_suffix);
}

fn computeArtifactHash(source_path: []const u8, source_bytes: []const u8, target_name: []const u8, source_suffix: []const u8, out_path: []const u8) [32]u8 {
    var hasher = std.crypto.hash.sha2.Sha256.init(.{});
    hasher.update(source_path);
    hasher.update(&[_]u8{0});
    hasher.update(source_bytes);
    hasher.update(&[_]u8{0});
    hasher.update(target_name);
    hasher.update(&[_]u8{0});
    hasher.update(source_suffix);
    hasher.update(&[_]u8{0});
    hasher.update(out_path);
    var out: [32]u8 = undefined;
    hasher.final(&out);
    return out;
}

fn commandName(cmd: Command) []const u8 {
    return switch (cmd) {
        .build => "build",
        .run => "run",
        .init => "init",
        .install => "install",
        .build_exe => "build-exe",
        .build_wasm => "build-wasm",
        .build_obj => "build-obj",
        .bc2sa => "bc2sa",
        .audit => "audit",
        .graph => "graph",
        .fetch => "fetch",
        .layout => "layout",
        .size => "size",
        .test_cmd => "test",
        .explain => "explain",
        .fix => "fix",
        .skills => "skills",
        .help => "help",
        .version => "version",
    };
}

fn commandSupported(name: []const u8) bool {
    return std.mem.eql(u8, name, "build") or std.mem.eql(u8, name, "run") or std.mem.eql(u8, name, "init") or std.mem.eql(u8, name, "install") or std.mem.eql(u8, name, "build-exe") or std.mem.eql(u8, name, "build-wasm") or std.mem.eql(u8, name, "build-obj") or std.mem.eql(u8, name, "audit") or std.mem.eql(u8, name, "graph") or std.mem.eql(u8, name, "layout") or std.mem.eql(u8, name, "size") or std.mem.eql(u8, name, "test") or std.mem.eql(u8, name, "explain") or std.mem.eql(u8, name, "fix") or std.mem.eql(u8, name, "skills");
}

fn explainEntries() []const ExplainEntry {
    return &.{
        .{
            .codes = &.{ "ForbiddenSyntax", "SA-FLAT-001" },
            .title = "Flattening rejected surface syntax",
            .summary = "The flattener only accepts the SA linear instruction surface.",
            .details = &.{
                "Braces, if/else, while, for, and dotted property chains are rejected before verification.",
                "The frontend must lower structured control flow into labels, branches, and explicit register moves.",
            },
            .fix_hint = "Rewrite the source into labels and br/jmp blocks before flattening.",
        },
        .{
            .codes = &.{ "ImportResolutionFailed", "SA-FLAT-050" },
            .title = "Import could not be resolved",
            .summary = "The import path or package identity could not be matched to a source artifact.",
            .details = &.{
                "The resolver accepts source packages and pinned package identities.",
                "Ambiguous versions, rejected artifacts, and invalid paths all surface through the same public trap.",
            },
            .fix_hint = "Pin the package ref, fix the path, or depend on the source package instead of a precompiled artifact.",
        },
        .{
            .codes = &.{ "RegisterRedefinition", "SA-REF-010" },
            .title = "Live register re-bound",
            .summary = "A register that is still live cannot be assigned a second time without an explicit move or release.",
            .details = &.{
                "The referee checks register ownership and capability masks on every instruction.",
                "Rebinding a live register without consuming the previous value violates the linear ownership model.",
            },
            .fix_hint = "Rename the destination register or release/move the old value first.",
        },
        .{
            .codes = &.{ "UnknownRegister", "SA-REF-011" },
            .title = "Register used before declaration",
            .summary = "The verifier could not resolve the register name to a live slot.",
            .details = &.{
                "All register reads and writes must refer to a register introduced by a preceding instruction.",
                "Import-expanded code and macro-generated code must keep the same register namespace consistent.",
            },
            .fix_hint = "Declare the register earlier or thread the correct register name through the macro expansion.",
        },
        .{
            .codes = &.{"SA-CLI-001"},
            .title = "Missing required operand",
            .summary = "The CLI command needs a positional argument such as a source file or project path.",
            .details = &.{
                "The top-level dispatcher fails fast when no source or operand is provided.",
                "The same issue appears in build, run, test, and fetch subcommands when the target path is omitted.",
            },
            .fix_hint = "Pass the required file, path, or operand after the command.",
        },
    };
}

fn explainEntryForCode(code: []const u8) ?ExplainEntry {
    for (explainEntries()) |entry| {
        for (entry.codes) |alias| {
            if (std.mem.eql(u8, alias, code)) return entry;
        }
    }
    return null;
}

fn printTrapReport(writer: anytype, report: trap.TrapReport, mode: DiagnosticsMode) !void {
    switch (mode) {
        .human => {
            const function_text = textOrBuf(report.function, report.function_buf[0..]);
            const register_text = textOrBuf(report.register, report.register_buf[0..]);
            var source_text_buf: [256]u8 = [_]u8{0} ** 256;
            copyTextBuf(&source_text_buf, reportText(&report));
            const source_text = bufText(source_text_buf[0..]);
            try writer.print("error[{s}]: {s}\n", .{ trap.trapName(report.trap), report.message });
            if (function_text.len != 0) {
                try writer.print("  in function {s}\n", .{function_text});
            }
            try printUpstreamLocation(writer, report);
            if (source_text.len != 0) {
                if (report.source_line != 0) {
                    if (report.line != 0 and report.line != report.source_line) {
                        try writer.print("  line {d} (expanded {d}): {s}\n", .{ report.source_line, report.line, source_text });
                    } else {
                        try writer.print("  line {d}: {s}\n", .{ report.source_line, source_text });
                    }
                } else {
                    try writer.print("  source: {s}\n", .{source_text});
                }
            }
            if (register_text.len != 0) {
                try writer.print("  register: {s}\n", .{register_text});
            } else if (report.registers.len != 0) {
                try writer.writeAll("  registers:");
                for (report.registers) |name| {
                    try writer.print(" {s}", .{name});
                }
                try writer.writeByte('\n');
            }
            try printMaskState(writer, report);
            if (report.hint) |hint| {
                try writer.print("  help: {s}\n", .{hint});
            }
            if (report.repair_action) |action| {
                try writer.print("  repair: {s}\n", .{action});
                if (report.repair_hint) |hint| {
                    try writer.print("    hint: {s}\n", .{hint});
                }
                if (report.repair_confidence) |confidence| {
                    try writer.print("    confidence: {s}\n", .{confidence});
                }
            }
            try trap.writeJson(writer, report);
            try writer.writeByte('\n');
        },
        .json => {
            try writer.writeAll("{\"status\":\"error\",\"diagnostics\":[");
            try trap.writeJson(writer, report);
            try writer.writeAll("]}\n");
        },
    }
}

fn printUsage(writer: anytype) !void {
    try writer.writeAll("usage: sa <command> [options]\n\n");
    try writer.writeAll("Commands:\n");
    try writer.writeAll("  init         [path]            Create a new SA binary project\n");
    try writer.writeAll("  install      [identity]        Install project dependencies or one package\n");
    try writer.writeAll("  build        <file>            Compile a .sa source to a native executable\n");
    try writer.writeAll("  run          <file>            Compile and immediately execute a .sa file\n");
    try writer.writeAll("  build-exe    <file>            Build a standalone executable (alias for build)\n");
    try writer.writeAll("  build-obj    <file>            Build an object file (.o)\n");
    try writer.writeAll("  build-wasm   <file>            Build a WebAssembly module (.wasm)\n");
    try writer.writeAll("  test         <file>            Run @test blocks in a .sa file\n");
    try writer.writeAll("  fetch        <url>             Fetch and cache a remote package (compat alias)\n");
    try writer.writeAll("  audit        <file>            Audit package capability declarations\n");
    try writer.writeAll("  graph        <path>            Output a dependency/call graph\n");
    try writer.writeAll("  layout       ...               Print struct layout information\n");
    try writer.writeAll("  size         <file>            Print function size statistics\n");
    try writer.writeAll("  bc2sa      <file>            Translate LLVM bitcode to SA assembly\n");
    try writer.writeAll("  explain      <code>            Explain a diagnostic error code\n");
    try writer.writeAll("  fix          <file>            Suggest fixes for diagnostics\n");
    try writer.writeAll("  skills                         List compiler skills and capabilities\n");
    try writer.writeAll("  help         [command]         Show this help message\n");
    try writer.writeAll("  version                        Print the SA toolchain version\n");
    try writer.writeAll("\nGlobal options:\n");
    try writer.writeAll("  --json                         Output diagnostics in JSON format\n");
    try writer.writeAll("  --profile                      Include compile phase timings in JSON metrics\n");
    try writer.writeAll("  --jobs auto|N                  Set the number of parallel compile jobs\n");
    try writer.writeAll("  -h, --help                     Show this help message\n");
    try writer.writeAll("  --version                      Print version and exit\n");
    try writer.writeAll("\nTest flags:\n");
    try writer.writeAll("  --filter <pattern>             Include only matching tests (repeatable)\n");
    try writer.writeAll("  --skip <pattern>               Exclude matching tests (repeatable)\n");
    try writer.writeAll("  --exact                        Match test names exactly\n");
    try writer.writeAll("  --ignored                      Run only ignored tests\n");
    try writer.writeAll("  --include-ignored              Run all tests including ignored\n");
}

fn printVersion(writer: anytype) !void {
    const ver = build_options.version;
    try writer.print("sa {s}\n", .{ver});
}

const TmpWorkDir = struct {
    dir: std.fs.Dir,
    parent_dir: std.fs.Dir,
    sub_path: [std.fs.base64_encoder.calcSize(12)]u8,

    fn init() !TmpWorkDir {
        var random_bytes: [12]u8 = undefined;
        std.crypto.random.bytes(&random_bytes);

        var sub_path: [std.fs.base64_encoder.calcSize(12)]u8 = undefined;
        _ = std.fs.base64_encoder.encode(&sub_path, &random_bytes);

        const cwd = std.fs.cwd();
        var cache_dir = try cwd.makeOpenPath(".zig-cache", .{});
        defer cache_dir.close();
        var parent_dir = try cache_dir.makeOpenPath("tmp", .{});
        errdefer parent_dir.close();
        const dir = try parent_dir.makeOpenPath(&sub_path, .{});
        return .{ .dir = dir, .parent_dir = parent_dir, .sub_path = sub_path };
    }

    fn cleanup(self: *TmpWorkDir) void {
        self.dir.close();
        self.parent_dir.deleteTree(&self.sub_path) catch {};
        self.parent_dir.close();
        self.* = undefined;
    }
};

fn writeFile(dir: std.fs.Dir, path: []const u8, bytes: []const u8) !void {
    var file = try dir.createFile(path, .{ .truncate = true });
    defer file.close();
    try file.writeAll(bytes);
}

fn forbiddenHint(hit: flattener.ForbiddenHit) []const u8 {
    return switch (hit.token) {
        .brace_open, .brace_close => "remove brace syntax and flatten the control flow into labels and jumps",
        .keyword_if, .keyword_else, .keyword_while, .keyword_for => "replace control-flow keywords with labels and jmp/br instructions",
        .property_chain => "replace dotted property access with explicit SSA registers or constant expansion",
    };
}

fn lineContains(line: ?[]const u8, needle: []const u8) bool {
    return if (line) |text| std.mem.indexOf(u8, text, needle) != null else false;
}

fn writeJsonString(writer: anytype, text: []const u8) !void {
    try writer.writeByte('"');
    for (text) |c| {
        switch (c) {
            '"' => try writer.writeAll("\\\""),
            '\\' => try writer.writeAll("\\\\"),
            '\n' => try writer.writeAll("\\n"),
            '\r' => try writer.writeAll("\\r"),
            '\t' => try writer.writeAll("\\t"),
            else => {
                if (c < 0x20) {
                    try writer.print("\\u{X:0>4}", .{c});
                } else {
                    try writer.writeByte(c);
                }
            },
        }
    }
    try writer.writeByte('"');
}

fn writeMaybeJsonString(writer: anytype, value: ?[]const u8) !void {
    if (value) |text| {
        try writeJsonString(writer, text);
    } else {
        try writer.writeAll("null");
    }
}

fn copyContextLine(report: *trap.TrapReport, idx: usize, line_no: u32, text: []const u8) void {
    if (idx >= report.context.len) return;
    report.context[idx].line = line_no;
    report.context[idx].text = null;
    report.context[idx].text_buf = [_]u8{0} ** 256;
    copyTextBuf(&report.context[idx].text_buf, std.mem.trimRight(u8, text, "\r"));
}

fn copyBadToken(report: *trap.TrapReport, token: []const u8) void {
    report.bad_token = null;
    report.bad_token_buf = [_]u8{0} ** 64;
    copyTextBuf(&report.bad_token_buf, token);
}

fn setFile(report: *trap.TrapReport, source_path: []const u8) void {
    report.file = null;
    report.file_buf = [_]u8{0} ** 128;
    copyTextBuf(&report.file_buf, source_path);
}

fn setContextFromLine(report: *trap.TrapReport, line_no: u32, text: ?[]const u8) void {
    if (text) |line| {
        copyContextLine(report, 0, line_no, line);
        report.context_len = 1;
    }
}

fn setRepairAlternatives(report: *trap.TrapReport, alternatives: []const []const u8) void {
    const limit = @min(report.repair_alternatives.len, alternatives.len);
    report.repair_alternatives_len = @intCast(limit);
    for (0..limit) |idx| {
        report.repair_alternatives[idx] = null;
        report.repair_alternatives_buf[idx] = [_]u8{0} ** 64;
        copyTextBuf(&report.repair_alternatives_buf[idx], alternatives[idx]);
        const end = std.mem.indexOfScalar(u8, report.repair_alternatives_buf[idx][0..], 0) orelse alternatives[idx].len;
        report.repair_alternatives[idx] = report.repair_alternatives_buf[idx][0..end];
    }
}

fn firstBadTokenForTypeLine(line: ?[]const u8) ?[]const u8 {
    const text = line orelse return null;
    if (std.mem.indexOf(u8, text, "*")) |idx| {
        const tail = text[idx..];
        const end = std.mem.indexOfAny(u8, tail, " \t,)]}") orelse tail.len;
        return tail[0..end];
    }
    if (std.mem.indexOf(u8, text, "bool")) |_| return "bool";
    if (std.mem.indexOf(u8, text, "string")) |_| return "string";
    if (std.mem.indexOf(u8, text, "&")) |_| return "&";
    return null;
}

fn fillContextWindow(report: *trap.TrapReport, source: []const u8, center_line: u32) void {
    const start_line = if (center_line > 2) center_line - 2 else 1;
    var idx: usize = 0;
    var line_no = start_line;
    while (idx < report.context.len and line_no <= center_line + 2) : ({ idx += 1; line_no += 1; }) {
        if (lineAt(source, line_no)) |line| {
            copyContextLine(report, idx, line_no, sourceExcerpt(line));
        }
    }
    report.context_len = @intCast(idx);
}

fn setLineText(report: *trap.TrapReport, text: []const u8) void {
    report.source_text = null;
    report.original_text = null;
    report.source_text_buf = [_]u8{0} ** 256;
    report.original_text_buf = [_]u8{0} ** 256;
    copyTextBuf(&report.source_text_buf, text);
    copyTextBuf(&report.original_text_buf, text);
}

fn unsupportedTypeHint(line: ?[]const u8) []const u8 {
    if (lineContains(line, "call @")) {
        return "inspect the callee declaration referenced by this call site; the unsupported annotation is usually in the imported signature";
    }
    if (lineContains(line, "@import")) {
        return "inspect the imported file for unsupported primitive names or ownership suffixes";
    }
    return "check the primitive type names and ownership suffixes in the declaration";
}

fn cliErrorInfo(err: anyerror) CliErrorInfo {
    return switch (err) {
        error.MissingSourcePath => .{
            .code = "SA-CLI-001",
            .message = "missing required positional argument",
            .hint = "pass the source file, project path, or required operand after the command",
        },
        error.MissingOutputPath => .{
            .code = "SA-CLI-002",
            .message = "missing output path after -o",
            .hint = "add a path after -o or omit -o to use the default output name",
        },
        error.MissingJobs => .{
            .code = "SA-CLI-003",
            .message = "missing job count after --jobs",
            .hint = "use --jobs auto or --jobs <positive integer>",
        },
        error.InvalidJobs => .{
            .code = "SA-CLI-004",
            .message = "invalid job count",
            .hint = "use --jobs auto or a positive integer",
        },
        error.MissingTarget => .{
            .code = "SA-CLI-005",
            .message = "missing target after --target",
            .hint = "use wasm32 or wasm64 after --target",
        },
        error.InvalidTarget => .{
            .code = "SA-CLI-006",
            .message = "invalid target",
            .hint = "use wasm32 or wasm64 after --target",
        },
        error.MissingFilterValue => .{
            .code = "SA-CLI-007",
            .message = "missing filter pattern",
            .hint = "pass a pattern after --filter or --skip",
        },
        error.MissingLayoutName => .{
            .code = "SA-CLI-008",
            .message = "missing layout name",
            .hint = "pass --name <TypeName>",
        },
        error.MissingLayoutFields => .{
            .code = "SA-CLI-009",
            .message = "missing layout fields",
            .hint = "pass --fields <name:ty,...>",
        },
        error.MissingLayoutFormat => .{
            .code = "SA-CLI-010",
            .message = "missing layout format",
            .hint = "use --format text, --format json, --format debug, or --format dict",
        },
        error.InvalidLayoutFormat => .{
            .code = "SA-CLI-011",
            .message = "invalid layout format",
            .hint = "use --format text, --format json, --format debug, or --format dict",
        },
        error.UnsupportedBitcodeInput => .{
            .code = "SA-CLI-012",
            .message = "unsupported bitcode input",
            .hint = "bc2sa expects real LLVM bitcode (.bc); text LLVM IR and non-bitcode files are rejected",
        },
        error.LlvmDisNotFound => .{
            .code = "SA-CLI-016",
            .message = "llvm-dis not found",
            .hint = "install llvm-dis-14 or make llvm-dis available on PATH before running bc2sa",
        },
        error.LlvmDisFailed => .{
            .code = "SA-CLI-017",
            .message = "llvm-dis failed",
            .hint = "verify the input is valid LLVM bitcode for the installed LLVM toolchain",
        },
        error.UnsupportedInstruction => .{
            .code = "SA-CLI-018",
            .message = "unsupported LLVM instruction",
            .hint = "bc2sa currently supports a conservative scalar/load-store/branch subset and rejects unsupported IR instead of emitting invalid SA",
        },
        error.UnknownCommand => .{
            .code = "SA-CLI-013",
            .message = "unknown command",
            .hint = "use build, run, build-exe, build-wasm, build-obj, audit, graph, layout, size, test, explain, fix, skills, fetch, bc2sa, help, or version",
        },
        error.UnexpectedArgument => .{
            .code = "SA-CLI-014",
            .message = "unexpected argument",
            .hint = "check option order and remove unsupported flags",
        },
        error.InvalidPath => .{
            .code = "SA-CLI-014",
            .message = "invalid path",
            .hint = "check the filesystem path and project root",
        },
        error.MissingRef => .{
            .code = "SA-CLI-015",
            .message = "missing package ref",
            .hint = "pass a ref value after --ref",
        },
        else => .{
            .code = null,
            .message = @errorName(err),
            .hint = null,
        },
    };
}

pub fn printCliError(writer: anytype, err: anyerror, mode: DiagnosticsMode) !void {
    const info = cliErrorInfo(err);
    switch (mode) {
        .human => {
            if (info.code) |code| {
                try writer.print("error[{s}]: {s}\n", .{ code, info.message });
            } else {
                try writer.print("error: {s}\n", .{info.message});
            }
            if (info.hint) |hint| {
                try writer.print("  help: {s}\n", .{hint});
            }
        },
        .json => {
            try writer.writeAll("{\"status\":\"error\",\"error\":{");
            try writer.writeAll("\"name\":");
            try writeJsonString(writer, @errorName(err));
            try writer.writeAll(",\"code\":");
            try writeMaybeJsonString(writer, info.code);
            try writer.writeAll(",\"message\":");
            try writeJsonString(writer, info.message);
            try writer.writeAll(",\"hint\":");
            try writeMaybeJsonString(writer, info.hint);
            try writer.writeAll("}}\n");
        },
    }
}

fn importResolutionMessage(err: anyerror) []const u8 {
    return switch (err) {
        error.InvalidImportPath => "invalid import path",
        error.PackageNotResolved => "import path could not be resolved",
        error.AmbiguousPackageVersion => "multiple package versions match this import",
        error.PrecompiledArtifactRejected => "precompiled artifact imports are not allowed",
        error.InvalidPath => "invalid path while resolving an import",
        else => "import resolution failed",
    };
}

fn importResolutionHint(line: ?[]const u8, err: anyerror) []const u8 {
    _ = line;
    return switch (err) {
        error.InvalidImportPath => "use a valid relative `.sa` or package identity without `../`, empty segments, or whitespace",
        error.PackageNotResolved => "check the import path, package identity, local vendor tree, and package cache",
        error.AmbiguousPackageVersion => "pin the required package ref in `sa.mod` so the resolver can choose one version",
        error.PrecompiledArtifactRejected => "depend on the source package instead of a precompiled artifact",
        error.InvalidPath => "check the project root or import path for filesystem errors",
        else => "check the import path, package identity, local vendor tree, and package cache",
    };
}

fn lineAt(source: []const u8, target_line: u32) ?[]const u8 {
    if (target_line == 0) return null;
    var iter = std.mem.splitScalar(u8, source, '\n');
    var line_no: u32 = 1;
    while (iter.next()) |line| : (line_no += 1) {
        if (line_no == target_line) return line;
    }
    return null;
}

fn sourceExcerpt(line: []const u8) []const u8 {
    return std.mem.trimRight(u8, line, "\r");
}

fn copyTextBuf(dest: []u8, text: []const u8) void {
    const len = @min(dest.len, text.len);
    std.mem.copyForwards(u8, dest[0..len], text[0..len]);
}

fn bufText(buf: []const u8) []const u8 {
    return buf[0..(std.mem.indexOfScalar(u8, buf, 0) orelse buf.len)];
}

fn textOrBuf(value: ?[]const u8, buf: []const u8) []const u8 {
    if (value) |text| return text;
    return bufText(buf);
}

fn reportText(report: *const trap.TrapReport) []const u8 {
    if (report.source_text) |text| return text;
    const source_fallback = bufText(report.source_text_buf[0..]);
    if (source_fallback.len != 0) return source_fallback;
    if (report.original_text) |text| return text;
    return bufText(report.original_text_buf[0..]);
}

fn printUpstreamLocation(writer: anytype, report: trap.TrapReport) !void {
    if (report.upstream_loc) |loc| {
        try writer.print("  upstream {s}:{d}:{d}\n", .{ loc.file, loc.line, loc.col });
        return;
    }

    const file = bufText(report.upstream_file_buf[0..]);
    if (file.len == 0) return;

    if (report.upstream_line != 0 and report.upstream_col != 0) {
        try writer.print("  upstream {s}:{d}:{d}\n", .{ file, report.upstream_line, report.upstream_col });
    } else if (report.upstream_line != 0) {
        try writer.print("  upstream {s}:{d}\n", .{ file, report.upstream_line });
    } else {
        try writer.print("  upstream {s}\n", .{file});
    }
}

fn printMaskState(writer: anytype, report: trap.TrapReport) !void {
    if (report.expected_mask_name) |expected| {
        if (report.actual_mask_name) |actual| {
            try writer.print("  state: expected {s}, actual {s}\n", .{ expected, actual });
            return;
        }
        try writer.print("  state: expected {s}\n", .{expected});
        return;
    }

    if (report.actual_mask_name) |actual| {
        try writer.print("  state: {s}\n", .{actual});
        return;
    }

    if (report.expected_mask) |expected| {
        if (report.actual_mask) |actual| {
            try writer.print("  state: expected {d}, actual {d}\n", .{ expected, actual });
            return;
        }
        try writer.print("  state: expected {d}\n", .{expected});
        return;
    }

    if (report.actual_mask) |actual| {
        try writer.print("  state: {d}\n", .{actual});
    }
}

fn writeMetricsJson(writer: anytype, metrics: CompileMetrics) !void {
    try writer.writeByte('{');
    try writer.writeAll("\"compile_tokens\":");
    try writer.print("{d}", .{metrics.compile_tokens});
    try writer.writeAll(",\"instruction_count\":");
    try writer.print("{d}", .{metrics.instruction_count});
    if (metrics.phases) |phases| {
        try writer.writeAll(",\"phases_ns\":{");
        try writer.writeAll("\"load\":");
        try writer.print("{d}", .{phases.load_ns});
        try writer.writeAll(",\"setup\":");
        try writer.print("{d}", .{phases.setup_ns});
        try writer.writeAll(",\"flatten\":");
        try writer.print("{d}", .{phases.flatten_ns});
        try writer.writeAll(",\"verify\":");
        try writer.print("{d}", .{phases.verify_ns});
        if (phases.emit_ns) |ns| {
            try writer.writeAll(",\"emit\":");
            try writer.print("{d}", .{ns});
        }
        if (phases.link_ns) |ns| {
            try writer.writeAll(",\"link\":");
            try writer.print("{d}", .{ns});
        }
        if (phases.total_ns) |ns| {
            try writer.writeAll(",\"total\":");
            try writer.print("{d}", .{ns});
        }
        try writer.writeByte('}');
    }
    try writer.writeByte('}');
}

fn writeSuccessJson(writer: anytype, metrics: CompileMetrics) !void {
    try writer.writeAll("{\"status\":\"ok\",\"metrics\":");
    try writeMetricsJson(writer, metrics);
    try writer.writeAll("}\n");
}

fn writeJsonStringArray(writer: anytype, items: []const []const u8) !void {
    try writer.writeByte('[');
    for (items, 0..) |item, idx| {
        if (idx != 0) try writer.writeByte(',');
        try writeJsonString(writer, item);
    }
    try writer.writeByte(']');
}

fn writeExplainEntryJson(writer: anytype, entry: ExplainEntry) !void {
    try writer.writeByte('{');
    try writer.writeAll("\"codes\":");
    try writeJsonStringArray(writer, entry.codes);
    try writer.writeAll(",\"title\":");
    try writeJsonString(writer, entry.title);
    try writer.writeAll(",\"summary\":");
    try writeJsonString(writer, entry.summary);
    try writer.writeAll(",\"details\":");
    try writeJsonStringArray(writer, entry.details);
    try writer.writeAll(",\"fix_hint\":");
    try writeMaybeJsonString(writer, entry.fix_hint);
    try writer.writeByte('}');
}

fn writeExplainEntryText(writer: anytype, entry: ExplainEntry) !void {
    try writer.print("code: {s}\n", .{entry.codes[0]});
    if (entry.codes.len > 1) {
        try writer.writeAll("aliases:");
        for (entry.codes[1..]) |alias| {
            try writer.print(" {s}", .{alias});
        }
        try writer.writeByte('\n');
    }
    try writer.print("title: {s}\n", .{entry.title});
    try writer.print("summary: {s}\n", .{entry.summary});
    for (entry.details) |detail| {
        try writer.print("detail: {s}\n", .{detail});
    }
    if (entry.fix_hint) |hint| {
        try writer.print("fix: {s}\n", .{hint});
    }
}

fn writeFixPlanJson(writer: anytype, code: []const u8, plan: FixPlan) !void {
    try writer.writeByte('{');
    try writer.writeAll("\"code\":");
    try writeJsonString(writer, code);
    try writer.writeAll(",\"plan\":[");
    for (plan.steps, 0..) |step, idx| {
        if (idx != 0) try writer.writeByte(',');
        try writer.writeByte('{');
        try writer.writeAll("\"action\":");
        try writeJsonString(writer, step.action);
        try writer.writeAll(",\"target\":");
        try writeJsonString(writer, step.target);
        try writer.writeAll(",\"detail\":");
        try writeJsonString(writer, step.detail);
        try writer.writeByte('}');
    }
    try writer.writeAll("],\"rationale\":");
    try writeJsonStringArray(writer, plan.rationale);
    try writer.writeByte('}');
}

fn writeFixPlanText(writer: anytype, code: []const u8, plan: FixPlan) !void {
    try writer.print("code: {s}\n", .{code});
    for (plan.rationale) |item| {
        try writer.print("rationale: {s}\n", .{item});
    }
    for (plan.steps) |step| {
        try writer.print("plan: {s} {s} - {s}\n", .{ step.action, step.target, step.detail });
    }
}

fn explainCommand(writer: anytype, args: []const []const u8, json_mode: bool) !u8 {
    if (args.len < 3) return error.MissingSourcePath;
    const code = args[2];
    const entry = explainEntryForCode(code) orelse {
        try writer.print("unknown code: {s}\n", .{code});
        return 1;
    };
    if (json_mode) {
        try writer.writeAll("{\"status\":\"ok\",\"explain\":");
        try writeExplainEntryJson(writer, entry);
        try writer.writeAll("}\n");
    } else {
        try writeExplainEntryText(writer, entry);
    }
    return 0;
}

fn fixPlanForCode(code: []const u8) ?FixPlan {
    return if (std.mem.eql(u8, code, "ForbiddenSyntax")) .{
        .steps = &.{
            .{ .action = "rewrite", .target = "control-flow", .detail = "lower braces and keywords into labels, br, and jmp" },
            .{ .action = "re-run", .target = "flattener", .detail = "verify that the line stream no longer contains forbidden syntax" },
        },
        .rationale = &.{
            "The flattener rejects structured syntax before semantic verification.",
            "Agent-side patching should preserve the original semantics while removing unsupported surface forms.",
        },
    } else if (std.mem.eql(u8, code, "ImportResolutionFailed")) .{
        .steps = &.{
            .{ .action = "pin", .target = "package-ref", .detail = "choose a single version or local path and record it in the manifest" },
            .{ .action = "retry", .target = "resolver", .detail = "re-run the import resolution against the pinned source" },
        },
        .rationale = &.{
            "The resolver needs one concrete source artifact, not an ambiguous graph.",
            "The current CLI fallback already treats invalid import data as a structured trap.",
        },
    } else if (std.mem.eql(u8, code, "SA-CLI-001")) .{
        .steps = &.{
            .{ .action = "add", .target = "positional-argument", .detail = "supply the missing source file or project path" },
            .{ .action = "retry", .target = "command", .detail = "invoke the same CLI command with the required operand" },
        },
        .rationale = &.{
            "The command dispatcher needs an explicit target path to operate on.",
            "This is a deterministic CLI error rather than a semantic trap.",
        },
    } else null;
}

fn fixCommand(writer: anytype, args: []const []const u8, json_mode: bool) !u8 {
    var code: ?[]const u8 = null;
    var i: usize = 2;
    while (i < args.len) : (i += 1) {
        const arg = args[i];
        if (std.mem.eql(u8, arg, "--plan")) continue;
        if (std.mem.eql(u8, arg, "--json")) continue;
        if (code == null) {
            code = arg;
            continue;
        }
        return error.UnexpectedArgument;
    }
    const target = code orelse return error.MissingSourcePath;
    const plan = fixPlanForCode(target) orelse {
        try writer.print("unknown code: {s}\n", .{target});
        return 1;
    };
    if (json_mode) {
        try writer.writeAll("{\"status\":\"ok\",\"fix\":");
        try writeFixPlanJson(writer, target, plan);
        try writer.writeAll("}\n");
    } else {
        try writeFixPlanText(writer, target, plan);
    }
    return 0;
}

fn writeSkillSectionText(writer: anytype, title: []const u8, summary: []const u8, items: []const []const u8) !void {
    try writer.print("{s}\n", .{title});
    try writer.print("summary: {s}\n", .{summary});
    for (items) |item| {
        try writer.print("- {s}\n", .{item});
    }
}

fn writeSkillsJson(writer: anytype, sections: []const SkillSection) !void {
    try writer.writeByte('{');
    try writer.writeAll("\"status\":\"ok\",\"skills\":[");
    for (sections, 0..) |section, idx| {
        if (idx != 0) try writer.writeByte(',');
        try writer.writeByte('{');
        try writer.writeAll("\"name\":");
        try writeJsonString(writer, section.name);
        try writer.writeAll(",\"summary\":");
        try writeJsonString(writer, section.summary);
        try writer.writeAll(",\"items\":");
        try writeJsonStringArray(writer, section.items);
        try writer.writeByte('}');
    }
    try writer.writeAll("]}\n");
}

fn skillsCommand(writer: anytype, json_mode: bool) !u8 {
    const base_sections = [_]SkillSection{
        .{ .name = "core diagnostics", .summary = "Agent-facing error handling and JSON reports", .items = &.{
            "stable trap names and trap codes",
            "structured JSON diagnostics with repair hints",
            "human and JSON output modes remain aligned",
        } },
        .{ .name = "cli toolchain", .summary = "Agent-first CLI entry points", .items = &.{
            "init [path]",
            "install [identity]",
            "explain <code>",
            "fix --plan --json",
            "skills",
        } },
        .{ .name = "project lifecycle", .summary = "Rust-like project setup and local builds", .items = &.{
            "init [path]",
            "install",
            "build src/main.sa",
            "run src/main.sa",
            "test <file>",
        } },
        .{ .name = "std runtime", .summary = "Current Zig-backed facade surface", .items = &.{
            "JSON DOM and streaming facade",
            "Regex facade over Zig/POSIX backend",
            "fs/net/process/term facades stay thin in SA",
        } },
    };
    var sections_list = std.ArrayList(SkillSection).init(std.heap.page_allocator);
    errdefer sections_list.deinit();
    try sections_list.appendSlice(&base_sections);
    const sections = try sections_list.toOwnedSlice();
    defer std.heap.page_allocator.free(sections);

    if (json_mode) {
        try writeSkillsJson(writer, sections);
    } else {
        try writer.writeAll("agent-first toolchain\n");
        for (sections) |section| {
            try writeSkillSectionText(writer, section.name, section.summary, section.items);
        }
    }
    return 0;
}

fn trapFromFlattenError(source_path: []const u8, source: []const u8, err: anyerror, last_line: ?u32) trap.TrapReport {
    const forbidden = flattener.findFirstForbiddenLine(source);
    const line_no = if (forbidden) |hit| hit.line_no else last_line orelse 1;
    const line_text = lineAt(source, line_no);
    const source_text = if (line_text) |line| std.mem.trimRight(u8, line, "\r") else null;
    const source_text_buf: [256]u8 = [_]u8{0} ** 256;
    const original_text_buf: [256]u8 = [_]u8{0} ** 256;
    const file_buf: [128]u8 = [_]u8{0} ** 128;
    const bad_token_buf: [64]u8 = [_]u8{0} ** 64;
    var report: trap.TrapReport = switch (err) {
        error.ForbiddenSyntax => .{
            .trap = .forbidden_syntax,
            .trap_code = trap.trapCode(.forbidden_syntax),
            .file_buf = file_buf,
            .file = source_path,
            .line = line_no,
            .source_line = line_no,
            .column = if (forbidden) |hit| @as(u32, @intCast(hit.hit.column)) else null,
            .source_text_buf = source_text_buf,
            .original_text_buf = original_text_buf,
            .source_text = null,
            .original_text = null,
            .bad_token_buf = bad_token_buf,
            .bad_token = if (forbidden) |hit| switch (hit.hit.token) {
                .brace_open => "{",
                .brace_close => "}",
                .keyword_if => "if",
                .keyword_else => "else",
                .keyword_while => "while",
                .keyword_for => "for",
                .property_chain => ".",
            } else null,
            .context = .{ .{}, .{}, .{}, .{}, .{} },
            .context_len = 0,
            .register = null,
            .registers = &.{},
            .expected_mask = null,
            .actual_mask = null,
            .expected_mask_name = null,
            .actual_mask_name = null,
            .function = null,
            .is_ffi_wrapper = null,
            .message = "forbidden syntax detected during flattening",
            .hint = if (forbidden) |hit| forbiddenHint(hit.hit) else null,
        },
        error.UnsupportedType => .{
            .trap = .unsupported_type,
            .trap_code = trap.trapCode(.unsupported_type),
            .file_buf = file_buf,
            .file = source_path,
            .line = line_no,
            .source_line = line_no,
            .column = if (line_text) |lt| if (std.mem.indexOfAny(u8, lt, "*&")) |idx| @as(u32, @intCast(idx + 1)) else null else null,
            .source_text_buf = source_text_buf,
            .original_text_buf = original_text_buf,
            .source_text = null,
            .original_text = null,
            .bad_token_buf = bad_token_buf,
            .bad_token = firstBadTokenForTypeLine(source_text),
            .context = .{ .{}, .{}, .{}, .{}, .{} },
            .context_len = 0,
            .register = null,
            .registers = &.{},
            .expected_mask = null,
            .actual_mask = null,
            .expected_mask_name = null,
            .actual_mask_name = null,
            .function = null,
            .is_ffi_wrapper = null,
            .message = "unsupported type annotation during flattening",
            .hint = unsupportedTypeHint(line_text),
            .repair_alternatives = .{ null, null, null },
            .repair_alternatives_len = 0,
        },
        error.InvalidImportPath, error.PackageNotResolved, error.AmbiguousPackageVersion, error.PrecompiledArtifactRejected, error.InvalidPath => .{
            .trap = .import_resolution_failed,
            .trap_code = trap.trapCode(.import_resolution_failed),
            .file_buf = file_buf,
            .file = source_path,
            .line = line_no,
            .source_line = line_no,
            .column = null,
            .source_text_buf = source_text_buf,
            .original_text_buf = original_text_buf,
            .source_text = null,
            .original_text = null,
            .bad_token_buf = bad_token_buf,
            .bad_token = null,
            .context = .{ .{}, .{}, .{}, .{}, .{} },
            .context_len = 0,
            .register = null,
            .registers = &.{},
            .expected_mask = null,
            .actual_mask = null,
            .expected_mask_name = null,
            .actual_mask_name = null,
            .function = null,
            .is_ffi_wrapper = null,
            .message = importResolutionMessage(err),
            .hint = importResolutionHint(line_text, err),
            .repair_action = "fix-import",
            .repair_hint = importResolutionHint(line_text, err),
            .repair_confidence = if (err == error.InvalidImportPath) "high" else "medium",
            .repair_alternatives = .{ null, null, null },
            .repair_alternatives_len = 0,
        },
        error.OutOfMemory => .{
            .trap = .arena_oom,
            .trap_code = trap.trapCode(.arena_oom),
            .file_buf = file_buf,
            .file = source_path,
            .line = line_no,
            .source_line = line_no,
            .column = null,
            .source_text_buf = source_text_buf,
            .original_text_buf = original_text_buf,
            .source_text = null,
            .original_text = null,
            .bad_token_buf = bad_token_buf,
            .bad_token = null,
            .context = .{ .{}, .{}, .{}, .{}, .{} },
            .context_len = 0,
            .register = null,
            .registers = &.{},
            .expected_mask = null,
            .actual_mask = null,
            .expected_mask_name = null,
            .actual_mask_name = null,
            .function = null,
            .is_ffi_wrapper = null,
            .message = "out of memory while flattening",
            .hint = null,
        },
        error.ImportCycle => .{
            .trap = .forbidden_syntax,
            .trap_code = trap.trapCode(.forbidden_syntax),
            .file_buf = file_buf,
            .file = source_path,
            .line = line_no,
            .source_line = line_no,
            .column = null,
            .source_text_buf = source_text_buf,
            .original_text_buf = original_text_buf,
            .source_text = null,
            .original_text = null,
            .bad_token_buf = bad_token_buf,
            .bad_token = null,
            .context = .{ .{}, .{}, .{}, .{}, .{} },
            .context_len = 0,
            .register = null,
            .registers = &.{},
            .expected_mask = null,
            .actual_mask = null,
            .expected_mask_name = null,
            .actual_mask_name = null,
            .function = null,
            .is_ffi_wrapper = null,
            .message = "import cycle detected during flattening",
            .hint = "break the cycle in imported files or inline the shared definitions",
        },
        error.DuplicateDef => .{
            .trap = .duplicate_def,
            .trap_code = trap.trapCode(.duplicate_def),
            .file_buf = file_buf,
            .file = source_path,
            .line = line_no,
            .source_line = line_no,
            .column = null,
            .source_text_buf = source_text_buf,
            .original_text_buf = original_text_buf,
            .source_text = null,
            .original_text = null,
            .bad_token_buf = bad_token_buf,
            .bad_token = null,
            .context = .{ .{}, .{}, .{}, .{}, .{} },
            .context_len = 0,
            .register = null,
            .registers = &.{},
            .expected_mask = null,
            .actual_mask = null,
            .expected_mask_name = null,
            .actual_mask_name = null,
            .function = null,
            .is_ffi_wrapper = null,
            .message = "duplicate definition detected during flattening",
            .hint = null,
        },
        error.MacroRecursionLimit => .{
            .trap = .macro_recursion_limit,
            .trap_code = trap.trapCode(.macro_recursion_limit),
            .file_buf = file_buf,
            .file = source_path,
            .line = line_no,
            .source_line = line_no,
            .column = null,
            .source_text_buf = source_text_buf,
            .original_text_buf = original_text_buf,
            .source_text = null,
            .original_text = null,
            .bad_token_buf = bad_token_buf,
            .bad_token = null,
            .context = .{ .{}, .{}, .{}, .{}, .{} },
            .context_len = 0,
            .register = null,
            .registers = &.{},
            .expected_mask = null,
            .actual_mask = null,
            .expected_mask_name = null,
            .actual_mask_name = null,
            .function = null,
            .is_ffi_wrapper = null,
            .message = "macro recursion limit exceeded",
            .hint = null,
        },
        error.InvalidAtomicOrdering => .{
            .trap = .invalid_atomic_ordering,
            .trap_code = trap.trapCode(.invalid_atomic_ordering),
            .file_buf = file_buf,
            .file = source_path,
            .line = line_no,
            .source_line = line_no,
            .column = null,
            .source_text_buf = source_text_buf,
            .original_text_buf = original_text_buf,
            .source_text = null,
            .original_text = null,
            .bad_token_buf = bad_token_buf,
            .bad_token = null,
            .context = .{ .{}, .{}, .{}, .{}, .{} },
            .context_len = 0,
            .register = null,
            .registers = &.{},
            .expected_mask = null,
            .actual_mask = null,
            .expected_mask_name = null,
            .actual_mask_name = null,
            .function = null,
            .is_ffi_wrapper = null,
            .message = "invalid atomic ordering",
            .hint = null,
        },
        error.InvalidMacroInvocation, error.InvalidMacroDefinitionContext, error.UnbalancedMacro, error.UnbalancedRep, error.InvalidSyntax => .{
            .trap = .forbidden_syntax,
            .trap_code = trap.trapCode(.forbidden_syntax),
            .file_buf = file_buf,
            .file = source_path,
            .line = line_no,
            .source_line = line_no,
            .column = null,
            .source_text_buf = source_text_buf,
            .original_text_buf = original_text_buf,
            .source_text = null,
            .original_text = null,
            .bad_token_buf = bad_token_buf,
            .bad_token = null,
            .context = .{ .{}, .{}, .{}, .{}, .{} },
            .context_len = 0,
            .register = null,
            .registers = &.{},
            .expected_mask = null,
            .actual_mask = null,
            .expected_mask_name = null,
            .actual_mask_name = null,
            .function = null,
            .is_ffi_wrapper = null,
            .message = @errorName(err),
            .hint = switch (err) {
                error.InvalidMacroInvocation => "check the macro name, argument count, and comma-separated expansion syntax",
                error.InvalidMacroDefinitionContext => "macro definitions are only allowed at top level",
                error.UnbalancedMacro => "make sure [MACRO] has a matching [END_MACRO]",
                error.UnbalancedRep => "make sure [REP] has a matching [END_REP]",
                error.InvalidSyntax => "check the flattened line syntax and operand ordering",
                else => null,
            },
        },
        else => .{
            .trap = .forbidden_syntax,
            .trap_code = trap.trapCode(.forbidden_syntax),
            .file_buf = file_buf,
            .file = source_path,
            .line = line_no,
            .source_line = line_no,
            .column = null,
            .source_text_buf = source_text_buf,
            .original_text_buf = original_text_buf,
            .source_text = null,
            .original_text = null,
            .bad_token_buf = bad_token_buf,
            .bad_token = null,
            .context = .{ .{}, .{}, .{}, .{}, .{} },
            .context_len = 0,
            .register = null,
            .registers = &.{},
            .expected_mask = null,
            .actual_mask = null,
            .expected_mask_name = null,
            .actual_mask_name = null,
            .function = null,
            .is_ffi_wrapper = null,
            .message = @errorName(err),
            .hint = "flattening failed before a public trap mapping was available",
        },
    };
    if (line_text) |line| {
        const excerpt = sourceExcerpt(line);
        setLineText(&report, excerpt);
        fillContextWindow(&report, source, line_no);
    }
    switch (report.trap) {
        .forbidden_syntax => {
            report.repair_action = "rewrite";
            report.repair_hint = "lower structured control flow into labels, branches, and explicit register moves";
            report.repair_confidence = "high";
            setRepairAlternatives(&report, &.{ "jmp", "label", "ptr" });
        },
        .unsupported_type => {
            report.repair_action = "inspect-signature";
            report.repair_hint = "replace unsupported structured types with ptr or a primitive SA type and adjust the callee signature";
            report.repair_confidence = "medium";
            setRepairAlternatives(&report, &.{ "ptr", "u64", "i64" });
        },
        .import_resolution_failed => {
            report.repair_action = "pin-import";
            report.repair_hint = "pin one package ref or replace the import path with a unique local package identity";
            report.repair_confidence = "medium";
            setRepairAlternatives(&report, &.{ "sa.mod", "local package", "pinned ref" });
        },
        .duplicate_def => {
            report.repair_action = "rename-def";
            report.repair_hint = "change one of the conflicting names or namespace the symbol";
            report.repair_confidence = "high";
        },
        .macro_recursion_limit => {
            report.repair_action = "simplify-macro";
            report.repair_hint = "reduce recursive expansion depth or inline the macro body";
            report.repair_confidence = "medium";
        },
        .invalid_atomic_ordering => {
            report.repair_action = "adjust-ordering";
            report.repair_hint = "use a success ordering that is not weaker than the failure ordering";
            report.repair_confidence = "medium";
        },
        else => {},
    }
    return report;
}

const PackageTrapInfo = struct {
    kind: trap.Trap,
    message: []const u8,
    hint: ?[]const u8,
};

fn trapFromPackagePreflightError(err: anyerror) ?trap.TrapReport {
    const info: PackageTrapInfo = switch (err) {
        error.ForbiddenGlobalConfig => .{
            .kind = .forbidden_global_config,
            .message = "global SA package configuration is forbidden for reproducible builds",
            .hint = "remove ~/.sa/config.toml, ~/.sa/mirror.toml, and /etc/sa/*.toml; use sa.mod or project .sa_env mirrors instead",
        },
        error.SumHashMismatch => .{
            .kind = .sum_hash_mismatch,
            .message = "sa.sum does not match the resolved dependency tree",
            .hint = "run sa install to refresh sa.sum, or restore the vendored dependency source",
        },
        error.UpstreamShaMismatch => .{
            .kind = .upstream_sha_mismatch,
            .message = "package source hash does not match the granted requirement",
            .hint = "verify the dependency source and update the manifest hash only after auditing it",
        },
        error.UnauthorizedPrimitive => .{
            .kind = .unauthorized_primitive,
            .message = "package uses @sys_* outside its declared grants",
            .hint = "add the explicit grant only after auditing the package source, or remove the dependency",
        },
        error.MissingTtyForConfirmation => .{
            .kind = .missing_tty_for_confirmation,
            .message = "high-risk package confirmation requires an interactive TTY",
            .hint = "run from a real terminal and type the full package URL, or use CI taint mode deliberately",
        },
        error.BlockedRiskUnconfirmed => .{
            .kind = .blocked_risk_unconfirmed,
            .message = "high-risk package confirmation did not match the full package URL",
            .hint = "rerun and type the exact package URL shown in the review banner",
        },
        error.AutoApproveForbidden => .{
            .kind = .blocked_risk_unconfirmed,
            .message = "package risk confirmation cannot be auto-approved",
            .hint = "remove --yes/--auto-approve and type the exact package URL in a TTY",
        },
        error.UnauditedRiskBlocked => .{
            .kind = .blocked_risk_unconfirmed,
            .message = "CI blocked a high-risk unaudited package",
            .hint = "audit the dependency locally or rerun CI with --allow-unaudited-risks to produce a tainted build",
        },
        error.PackageNotResolved, error.InvalidImportPath, error.AmbiguousPackageVersion, error.PrecompiledArtifactRejected, error.InvalidPath => .{
            .kind = .import_resolution_failed,
            .message = importResolutionMessage(err),
            .hint = importResolutionHint(null, err),
        },
        else => return null,
    };

    return .{
        .trap = info.kind,
        .trap_code = trap.trapCode(info.kind),
        .line = 1,
        .source_line = 1,
        .registers = &.{},
        .message = info.message,
        .hint = info.hint,
    };
}

fn pathExists(path: []const u8) !bool {
    std.fs.cwd().access(path, .{ .mode = .read_only }) catch |err| switch (err) {
        error.FileNotFound => return false,
        else => return err,
    };
    return true;
}

fn dirExists(path: []const u8) bool {
    var dir = std.fs.cwd().openDir(path, .{ .iterate = true }) catch return false;
    dir.close();
    return true;
}

fn globalCacheRoot(allocator: std.mem.Allocator, identity: []const u8, ref: []const u8) ![]u8 {
    const home = std.process.getEnvVarOwned(allocator, "HOME") catch {
        return error.PackageNotResolved;
    };
    defer allocator.free(home);
    const leaf = try std.fmt.allocPrint(allocator, "{s}@{s}", .{ identity, ref });
    defer allocator.free(leaf);
    return try std.fs.path.join(allocator, &.{ home, ".sa", "pkg", leaf });
}

fn resolvePackageAuditRoot(
    allocator: std.mem.Allocator,
    project_root: []const u8,
    entry: manifest.RequireEntry,
    offline: bool,
) ![]u8 {
    const local_root = try std.fs.path.join(allocator, &.{ project_root, "sa_vendor", entry.url });
    errdefer allocator.free(local_root);
    if (dirExists(local_root)) return local_root;
    allocator.free(local_root);

    if (offline) return error.PackageNotResolved;

    const global_root = try globalCacheRoot(allocator, entry.url, entry.ref);
    errdefer allocator.free(global_root);
    if (dirExists(global_root)) return global_root;
    allocator.free(global_root);

    return error.PackageNotResolved;
}

fn hashesEqual(lhs: [32]u8, rhs: [32]u8) bool {
    return std.mem.eql(u8, lhs[0..], rhs[0..]);
}

fn appendCiSummaryIfConfigured(
    allocator: std.mem.Allocator,
    report: pkg_audit.AuditReport,
    status: pkg_ci.VerifyStatus,
) !void {
    const summary_path = std.process.getEnvVarOwned(allocator, "GITHUB_STEP_SUMMARY") catch |err| switch (err) {
        error.EnvironmentVariableNotFound => return,
        else => return err,
    };
    defer allocator.free(summary_path);
    var summary_file = try std.fs.cwd().openFile(summary_path, .{ .mode = .write_only });
    defer summary_file.close();
    try summary_file.seekFromEnd(0);
    try pkg_ci.writeGithubSummary(summary_file.writer(), report, status);
}

fn preflightCiPackage(
    allocator: std.mem.Allocator,
    report: pkg_audit.AuditReport,
    expected_source_sha256: [32]u8,
    options: CompileOptions,
) !void {
    const status = try pkg_ci.dualTrackVerify(report, .{
        .expected_source_sha256 = expected_source_sha256,
        .allow_unaudited_risks = options.allow_unaudited_risks,
    });
    if (status == .tainted_unaudited_code) {
        var null_writer = std.io.null_writer;
        const writer = options.diagnostic_writer orelse null_writer.any();
        try pkg_ci.writeTaintBanner(writer, report);
        try appendCiSummaryIfConfigured(allocator, report, status);
    }
}

fn preflightInteractivePackage(
    report: pkg_audit.AuditReport,
    expected_source_sha256: [32]u8,
    session: *pkg_confirm.Session,
    options: CompileOptions,
) !void {
    if (!hashesEqual(report.source_sha256, expected_source_sha256)) return error.UpstreamShaMismatch;

    var empty_input = std.io.fixedBufferStream("");
    var null_writer = std.io.null_writer;
    const reader = options.stdin_reader orelse empty_input.reader().any();
    const writer = options.diagnostic_writer orelse null_writer.any();
    const stdin_is_tty = options.stdin_is_tty orelse stdinIsTty();
    try pkg_confirm.confirmWithReaderWriter(
        session,
        report,
        reader,
        writer,
        stdin_is_tty,
        options.auto_approve_requested,
    );
}

fn verifyProjectPackageState(
    allocator: std.mem.Allocator,
    project_root: []const u8,
    project_manifest: manifest.Manifest,
    options: CompileOptions,
) !void {
    try pkg_mirror.rejectForbiddenGlobalConfig(allocator);

    const sum_path = try std.fs.path.join(allocator, &.{ project_root, "sa.sum" });
    defer allocator.free(sum_path);
    if (try pathExists(sum_path)) {
        try pkg_sum.verifyProjectSum(allocator, project_root, project_manifest);
    }

    var session = pkg_confirm.Session.init(allocator);
    defer session.deinit();
    const stdin_is_tty = options.stdin_is_tty orelse stdinIsTty();
    const ci_mode = pkg_ci.detectMode(.{
        .explicit_ci = options.ci,
        // Plain pipes must not silently become the CI taint path; they should
        // hit the interactive confirmation guard and fail with MissingTty.
        .stdin_is_tty = if (options.ci) stdin_is_tty else true,
    });

    for (project_manifest.requires) |entry| {
        const audit_root = try resolvePackageAuditRoot(allocator, project_root, entry, options.offline);
        defer allocator.free(audit_root);
        var report = try pkg_audit.auditPackage(allocator, entry.url, entry.ref, audit_root, entry.grants);
        defer report.deinit(allocator);

        if (ci_mode) {
            try preflightCiPackage(allocator, report, entry.source_sha256, options);
        } else {
            try preflightInteractivePackage(report, entry.source_sha256, &session, options);
        }
    }
}

fn consumeCompileOption(arg: []const u8, args: []const []const u8, index: *usize, options: *CompileOptions) !bool {
    if (try consumeJobsOption(arg, args, index, options)) return true;
    if (consumeProfileOption(arg, options)) return true;
    if (std.mem.eql(u8, arg, "--offline")) {
        options.offline = true;
        return true;
    }
    if (std.mem.eql(u8, arg, "--ci")) {
        options.ci = true;
        return true;
    }
    if (std.mem.eql(u8, arg, "--allow-unaudited-risks")) {
        options.allow_unaudited_risks = true;
        return true;
    }
    if (std.mem.eql(u8, arg, "--yes") or std.mem.eql(u8, arg, "--auto-approve")) {
        options.auto_approve_requested = true;
        return true;
    }
    return false;
}

fn parseJobsValue(text: []const u8) !?usize {
    if (std.mem.eql(u8, text, "auto")) return null;
    const jobs = std.fmt.parseInt(usize, text, 10) catch return error.InvalidJobs;
    if (jobs == 0) return error.InvalidJobs;
    return jobs;
}

fn consumeJobsOption(arg: []const u8, args: []const []const u8, index: *usize, options: *CompileOptions) !bool {
    if (!std.mem.eql(u8, arg, "--jobs")) return false;
    if (index.* + 1 >= args.len) return error.MissingJobs;
    options.jobs = try parseJobsValue(args[index.* + 1]);
    options.jobs_explicit = true;
    index.* += 1;
    return true;
}

fn consumeProfileOption(arg: []const u8, options: *CompileOptions) bool {
    if (!std.mem.eql(u8, arg, "--profile")) return false;
    options.profile = true;
    return true;
}

pub const ExecuteOptions = struct {
    stdin_reader: ?std.io.AnyReader = null,
    stdin_is_tty: ?bool = null,
};

fn applyExecuteOptions(options: *CompileOptions, exec_options: ExecuteOptions, diagnostic_writer: std.io.AnyWriter) void {
    options.stdin_reader = exec_options.stdin_reader;
    options.stdin_is_tty = exec_options.stdin_is_tty;
    options.diagnostic_writer = diagnostic_writer;
}

fn newCompileOptions(exec_options: ExecuteOptions, diagnostic_writer: std.io.AnyWriter) CompileOptions {
    var options: CompileOptions = .{};
    applyExecuteOptions(&options, exec_options, diagnostic_writer);
    return options;
}

fn loadSource(allocator: std.mem.Allocator, path: []const u8) ![]u8 {
    var file = try std.fs.cwd().openFile(path, .{});
    defer file.close();
    return try file.readToEndAlloc(allocator, 16 * 1024 * 1024);
}

fn projectRootFromSourcePath(allocator: std.mem.Allocator, source_path: []const u8) ![]u8 {
    const cwd_abs = try std.fs.cwd().realpathAlloc(allocator, ".");
    errdefer allocator.free(cwd_abs);

    const source_dir = std.fs.path.dirname(source_path) orelse ".";
    var current = try allocator.dupe(u8, source_dir);
    defer allocator.free(current);

    while (true) {
        const candidate_dir = if (std.fs.path.isAbsolute(current))
            try allocator.dupe(u8, current)
        else
            try std.fs.path.join(allocator, &.{ cwd_abs, current });
        defer allocator.free(candidate_dir);

        const manifest_path = try std.fs.path.join(allocator, &.{ candidate_dir, "sa.mod" });
        defer allocator.free(manifest_path);

        if (std.fs.cwd().openFile(manifest_path, .{})) |file| {
            file.close();
            allocator.free(cwd_abs);
            return try std.fs.cwd().realpathAlloc(allocator, candidate_dir);
        } else |err| switch (err) {
            error.FileNotFound => {},
            else => return err,
        }

        const parent = std.fs.path.dirname(current) orelse break;
        if (std.mem.eql(u8, parent, current)) break;
        const next = try allocator.dupe(u8, parent);
        allocator.free(current);
        current = next;
    }

    return cwd_abs;
}

fn stdRootFromEnv(allocator: std.mem.Allocator) ![]u8 {
    const repo_std_root = try std.fs.path.join(allocator, &.{ build_options.repo_root, "sa_std" });
    errdefer allocator.free(repo_std_root);

    if (builtin.is_test) {
        return repo_std_root;
    }

    const env_root = std.process.getEnvVarOwned(allocator, "SA_STD_DIR") catch |err| switch (err) {
        error.EnvironmentVariableNotFound => return repo_std_root,
        else => return err,
    };
    errdefer allocator.free(env_root);

    const required_files = [_][]const u8{
        "io/print.sai",
        "core/sa_core.sa",
        "core/result.sa",
        "core/option.sa",
    };
    for (required_files) |rel| {
        const probe_path = try std.fs.path.join(allocator, &.{ env_root, rel });
        defer allocator.free(probe_path);
        if (std.fs.cwd().openFile(probe_path, .{})) |file| {
            file.close();
        } else |err| switch (err) {
            error.FileNotFound => {
                allocator.free(env_root);
                return repo_std_root;
            },
            else => return err,
        }
    }

    allocator.free(repo_std_root);
    return env_root;
}


fn readProjectManifest(allocator: std.mem.Allocator, project_root: []const u8) !?manifest.Manifest {
    const manifest_path = try std.fs.path.join(allocator, &.{ project_root, "sa.mod" });
    defer allocator.free(manifest_path);

    const file = std.fs.cwd().openFile(manifest_path, .{}) catch |err| switch (err) {
        error.FileNotFound => return null,
        else => return err,
    };
    defer file.close();

    const source = try file.readToEndAlloc(allocator, 16 * 1024 * 1024);
    defer allocator.free(source);
    return try manifest.parseManifestWithFile(allocator, source, manifest_path);
}

fn manifestDependencies(manifest_file: *const manifest.Manifest, allocator: std.mem.Allocator) ![]pkg_resolver.Dependency {
    var deps = std.ArrayList(pkg_resolver.Dependency).init(allocator);
    errdefer deps.deinit();

    for (manifest_file.requires) |entry| {
        try deps.append(.{
            .url = entry.url,
            .ref = entry.ref,
        });
    }

    return try deps.toOwnedSlice();
}

fn compileSource(allocator: std.mem.Allocator, source_path: []const u8, options: CompileOptions) !CompileResult {
    const total_start = if (options.profile) std.time.Instant.now() catch null else null;
    const load_start = if (options.profile) std.time.Instant.now() catch null else null;
    const source = try loadSource(allocator, source_path);
    defer allocator.free(source);
    const load_ns = if (load_start) |start| elapsedNs(start) else 0;

    const setup_start = if (options.profile) std.time.Instant.now() catch null else null;
    const project_root_owned = options.project_root == null;
    const project_root = options.project_root orelse try projectRootFromSourcePath(allocator, source_path);
    defer if (project_root_owned) allocator.free(project_root);
    const std_root = try stdRootFromEnv(allocator);
    defer allocator.free(std_root);

    var project_manifest = try readProjectManifest(allocator, project_root);
    defer if (project_manifest) |*m| m.deinit(allocator);

    var dependency_slice: []pkg_resolver.Dependency = &.{};
    defer if (dependency_slice.len != 0) allocator.free(dependency_slice);

    if (project_manifest) |*m| {
        verifyProjectPackageState(allocator, project_root, m.*, options) catch |err| {
            if (trapFromPackagePreflightError(err)) |report| {
                return .{ .trap = report };
            }
            return err;
        };
        dependency_slice = try manifestDependencies(m, allocator);
    }

    const package_grants: []const manifest.RequireEntry = if (project_manifest) |*m| m.requires else &.{};

    var error_ctx: flattener.ErrorContext = .{};
    const resolve_ctx = flattener.ResolveContext{
        .dependencies = dependency_slice,
        .options = .{
            .project_root = project_root,
            .std_root = std_root,
            .offline = options.offline,
        },
    };
    const setup_ns = if (setup_start) |start| elapsedNs(start) else 0;

    const flatten_start = if (options.profile) std.time.Instant.now() catch null else null;
    var flat = flattener.flattenFileWithContextAndPackages(allocator, source_path, source, &error_ctx, resolve_ctx) catch |err| {
        return .{ .trap = trapFromFlattenError(source_path, source, err, flattener.takeErrorSourceLine(&error_ctx)) };
    };
    errdefer flat.deinit(allocator);
    const flatten_ns = if (flatten_start) |start| elapsedNs(start) else 0;

    const verify_start = if (options.profile) std.time.Instant.now() catch null else null;
    const verified = try referee.verifyWithOptions(allocator, flat.instructions, flat.const_decls, .{ .jobs = options.jobs, .package_grants = package_grants });
    const verify_ns = if (verify_start) |start| elapsedNs(start) else 0;

    return switch (verified) {
        .ok => |ok| .{ .ok = .{ .flat = flat, .verified = ok, .metrics = computeCompileMetrics(&flat, &ok, if (options.profile) .{ .load_ns = load_ns, .setup_ns = setup_ns, .flatten_ns = flatten_ns, .verify_ns = verify_ns, .total_ns = if (total_start) |start| elapsedNs(start) else null } else null) } },
        .trap => |report| {
            flat.deinit(allocator);
            return .{ .trap = report };
        },
    };
}

fn deriveOutputPath(allocator: std.mem.Allocator, source_path: []const u8, suffix: []const u8) ![]const u8 {
    const dir = std.fs.path.dirname(source_path);
    const stem = sourceStem(source_path);
    if (dir) |parent| {
        return try std.fmt.allocPrint(allocator, "{s}/{s}{s}", .{ parent, stem, suffix });
    }
    return try std.fmt.allocPrint(allocator, "{s}{s}", .{ stem, suffix });
}

fn ensureParentDir(path: []const u8) !void {
    if (std.fs.path.dirname(path)) |dir| {
        if (dir.len != 0) try std.fs.cwd().makePath(dir);
    }
}

fn writeAllFile(path: []const u8, bytes: []const u8) !void {
    try ensureParentDir(path);
    var file = try std.fs.cwd().createFile(path, .{ .truncate = true });
    defer file.close();
    try file.writeAll(bytes);
}

fn writeTextFile(allocator: std.mem.Allocator, path: []const u8, bytes: []const u8) !void {
    _ = allocator;
    try writeAllFile(path, bytes);
}

fn ensureNewFile(path: []const u8, bytes: []const u8) !void {
    try ensureParentDir(path);
    var file = try std.fs.cwd().createFile(path, .{ .exclusive = true });
    defer file.close();
    try file.writeAll(bytes);
}

fn executeInit(allocator: std.mem.Allocator, args: []const []const u8, stdout: anytype) !u8 {
    if (args.len > 1) return error.UnexpectedArgument;
    const project_path = if (args.len == 1) args[0] else ".";

    try std.fs.cwd().makePath(project_path);

    const src_dir = try std.fs.path.join(allocator, &.{ project_path, "src" });
    defer allocator.free(src_dir);
    try std.fs.cwd().makePath(src_dir);

    const manifest_path = try std.fs.path.join(allocator, &.{ project_path, "sa.mod" });
    defer allocator.free(manifest_path);
    const main_path = try std.fs.path.join(allocator, &.{ project_path, "src", "main.sa" });
    defer allocator.free(main_path);
    const gitignore_path = try std.fs.path.join(allocator, &.{ project_path, ".gitignore" });
    defer allocator.free(gitignore_path);

    try ensureNewFile(manifest_path,
        \\# generated by sa init
        \\
    );
    try ensureNewFile(main_path,
        \\@main() -> i32:
        \\return 0
        \\
    );
    try ensureNewFile(gitignore_path,
        \\.zig-cache/
        \\zig-out/
        \\*.out
        \\*.sa.bc
        \\
    );

    try stdout.print("Initialized SA binary project: {s}\n", .{project_path});
    try stdout.print("Entry: {s}\n", .{main_path});
    return 0;
}

const InstallArgs = struct {
    options: pkg_fetch.FetchOptions = .{},
    identity: ?[]const u8 = null,
    ref: []const u8 = "HEAD",
};

fn parseInstallArgs(args: []const []const u8) !InstallArgs {
    var parsed = InstallArgs{};
    var i: usize = 0;
    while (i < args.len) : (i += 1) {
        const arg = args[i];
        if (std.mem.eql(u8, arg, "-g")) {
            parsed.options.global = true;
            continue;
        }
        if (std.mem.eql(u8, arg, "--offline")) {
            parsed.options.offline = true;
            continue;
        }
        if (std.mem.eql(u8, arg, "--ref")) {
            if (i + 1 >= args.len) return error.MissingRef;
            parsed.ref = args[i + 1];
            i += 1;
            continue;
        }
        if (parsed.identity == null) {
            parsed.identity = arg;
            continue;
        }
        return error.UnexpectedArgument;
    }
    return parsed;
}

fn installManifestDependencies(allocator: std.mem.Allocator, options: pkg_fetch.FetchOptions, stdout: anytype) !u8 {
    const source = try loadSource(allocator, "sa.mod");
    defer allocator.free(source);

    var project_manifest = try manifest.parseManifestWithFile(allocator, source, "sa.mod");
    defer project_manifest.deinit(allocator);

    const project_root = try std.fs.cwd().realpathAlloc(allocator, ".");
    defer allocator.free(project_root);

    var mirror_rules = try pkg_mirror.loadProjectRules(allocator, project_root, project_manifest.mirrors);
    defer mirror_rules.deinit(allocator);

    var fetch_options = options;
    fetch_options.mirror_rules = mirror_rules.rules;

    for (project_manifest.requires) |entry| {
        var result = try pkg_fetch.fetchPackage(allocator, entry.url, entry.ref, fetch_options);
        defer result.deinit(allocator);
        try stdout.print("{s}\n", .{result.root});
    }

    var update = try pkg_sum.updateProjectSum(allocator, project_root, project_manifest);
    defer update.deinit(allocator);

    return 0;
}

fn executeInstall(allocator: std.mem.Allocator, args: []const []const u8, stdout: anytype) !u8 {
    const parsed = try parseInstallArgs(args);
    if (parsed.identity) |identity| {
        var result = try pkg_fetch.fetchPackage(allocator, identity, parsed.ref, parsed.options);
        defer result.deinit(allocator);
        try stdout.print("{s}\n", .{result.root});
        return 0;
    }
    return try installManifestDependencies(allocator, parsed.options, stdout);
}

fn saStdArchivePath(allocator: std.mem.Allocator) ![]u8 {
    const archive_name = switch (builtin.os.tag) {
        .windows => "sa_std.lib",
        else => "libsa_std.a",
    };
    const env_root: ?[]u8 = std.process.getEnvVarOwned(allocator, "SA_STD_DIR") catch |err| switch (err) {
        error.EnvironmentVariableNotFound => null,
        else => return err,
    };
    if (env_root) |root| {
        errdefer allocator.free(root);
        const archive = try std.fs.path.join(allocator, &.{ root, archive_name });
        if (std.fs.cwd().openFile(archive, .{})) |file| {
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

fn executeRun(
    allocator: std.mem.Allocator,
    source_path: []const u8,
    compile_options: CompileOptions,
    argv: []const []const u8,
    stdout: anytype,
    stderr: anytype,
    diagnostics_mode: DiagnosticsMode,
) !u8 {
    const compiled = try compileSource(allocator, source_path, compile_options);
    switch (compiled) {
        .trap => |report| {
            try printTrapReport(stderr, report, diagnostics_mode);
            return 1;
        },
        .ok => |ok| {
            var owned = ok;
            defer owned.deinit(allocator);
            const code = interp.runWithWriters(allocator, &owned.verified, argv, stdout.any(), stderr.any()) catch |err| switch (err) {
                error.UserExit => 0,
                else => {
                    try printCliError(stderr, err, diagnostics_mode);
                    return 1;
                },
            };
            if (diagnostics_mode == .json) {
                try writeSuccessJson(stderr, owned.metrics);
            }
            return code;
        },
    }
}

fn executeBuildExe(allocator: std.mem.Allocator, source_path: []const u8, out_path: []const u8, debug: bool, optimization: driver.Optimization, compile_options: CompileOptions, stderr: anytype, diagnostics_mode: DiagnosticsMode) !u8 {
    const total_start = if (compile_options.profile) std.time.Instant.now() catch null else null;
    const compiled = try compileSource(allocator, source_path, compile_options);
    switch (compiled) {
        .trap => |report| {
            try printTrapReport(stderr, report, diagnostics_mode);
            return 1;
        },
        .ok => |ok| {
            var owned = ok;
            defer owned.deinit(allocator);
            const std_archive_path = try saStdArchivePath(allocator);
            defer allocator.free(std_archive_path);

            const worker_count = blk: {
                if (compile_options.jobs) |j| {
                    break :blk j;
                }
                break :blk std.Thread.getCpuCount() catch 1;
            };
            const emission_workers = @max(@min(worker_count, 4), 1);
            const use_cgu = (compile_options.jobs_explicit and emission_workers > 1 and owned.verified.function_sigs.len >= 100);

            if (use_cgu) {
                const cgu_count = @min(@max(emission_workers, 2), 4);

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
                    cgu_idx_val: usize,
                    cgu_count_val: usize,
                    object_path_val: []const u8,
                    opt_level_val: u8,
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
                                .codegen_unit_index = self.cgu_idx_val,
                                .codegen_unit_count = self.cgu_count_val,
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
                        .size_bits_val = nativeSizeBits(),
                        .debug_val = debug,
                        .jobs_val = if (compile_options.jobs) |j| if (j > 1) 1 else j else 1,
                        .cgu_idx_val = i,
                        .cgu_count_val = cgu_count,
                        .object_path_val = cgu_obj_paths[i],
                        .opt_level_val = switch (optimization) {
                            .release_small => 1,
                            .release_fast => 3,
                        },
                    };
                }

                var cgu_emit_threads = try allocator.alloc(std.Thread, cgu_count - 1);
                defer allocator.free(cgu_emit_threads);

                var started_cgu_emit: usize = 0;
                errdefer {
                    while (started_cgu_emit > 0) {
                        started_cgu_emit -= 1;
                        cgu_emit_threads[started_cgu_emit].join();
                    }
                }

                const emit_start = if (compile_options.profile) std.time.Instant.now() catch null else null;
                while (started_cgu_emit < cgu_count - 1) : (started_cgu_emit += 1) {
                    cgu_emit_threads[started_cgu_emit] = try std.Thread.spawn(.{}, CguEmitWorker.run, .{&cgu_emit_workers[started_cgu_emit + 1]});
                }

                cgu_emit_workers[0].run();

                while (started_cgu_emit > 0) {
                    started_cgu_emit -= 1;
                    cgu_emit_threads[started_cgu_emit].join();
                }

                for (cgu_emit_workers) |w| {
                    if (w.err) |err| return err;
                }
                const emit_ns = if (emit_start) |start| elapsedNs(start) else null;

                // Link them all together
                const extra_input_count: usize = cgu_count - 1;
                const extra_inputs = try allocator.alloc([]const u8, extra_input_count);
                defer allocator.free(extra_inputs);

                var extra_idx: usize = 0;
                for (1..cgu_count) |i| {
                    extra_inputs[extra_idx] = cgu_obj_paths[i];
                    extra_idx += 1;
                }

                const link_start = if (compile_options.profile) std.time.Instant.now() catch null else null;
                driver.compileExe(allocator, cgu_obj_paths[0], out_path, optimization, std_archive_path, extra_inputs, debug, stderr) catch |err| switch (err) {
                    error.ChildProcessFailed => return 1,
                    else => return err,
                };
                const link_ns = if (link_start) |start| elapsedNs(start) else null;
                finishProfileMetrics(&owned.metrics, emit_ns, link_ns, if (total_start) |start| elapsedNs(start) else null);
            } else {
                const artifact_path = try intermediateArtifactPath(allocator, out_path);
                defer allocator.free(artifact_path);
                try ensureParentDir(artifact_path);
                const emit_start = if (compile_options.profile) std.time.Instant.now() catch null else null;
                try emit_llvm_llvmc.emitLlvmcToFile(allocator, owned.verified, &owned.flat.def_dict, owned.flat.loc_table, source_path, nativeSizeBits(), .{ .debug = debug, .jobs = compile_options.jobs }, artifact_path);
                const emit_ns = if (emit_start) |start| elapsedNs(start) else null;

                const link_start = if (compile_options.profile) std.time.Instant.now() catch null else null;
                driver.compileExe(allocator, artifact_path, out_path, optimization, std_archive_path, &.{}, debug, stderr) catch |err| switch (err) {
                    error.ChildProcessFailed => return 1,
                    else => return err,
                };
                const link_ns = if (link_start) |start| elapsedNs(start) else null;
                finishProfileMetrics(&owned.metrics, emit_ns, link_ns, if (total_start) |start| elapsedNs(start) else null);
            }

            if (diagnostics_mode == .json) {
                try writeSuccessJson(stderr, owned.metrics);
            }
            return 0;
        },
    }
}

fn executeBuildObj(allocator: std.mem.Allocator, source_path: []const u8, out_path: []const u8, debug: bool, optimization: driver.Optimization, compile_options: CompileOptions, stderr: anytype, diagnostics_mode: DiagnosticsMode) !u8 {
    const total_start = if (compile_options.profile) std.time.Instant.now() catch null else null;
    const compiled = try compileSource(allocator, source_path, compile_options);
    switch (compiled) {
        .trap => |report| {
            try printTrapReport(stderr, report, diagnostics_mode);
            return 1;
        },
        .ok => |ok| {
            var owned = ok;
            defer owned.deinit(allocator);
            const artifact_path = try intermediateArtifactPath(allocator, out_path);
            defer allocator.free(artifact_path);
            try ensureParentDir(artifact_path);
            const object_path = try allocator.dupe(u8, out_path);
            defer allocator.free(object_path);
            const emit_start = if (compile_options.profile) std.time.Instant.now() catch null else null;
            try emit_llvm_llvmc.emitLlvmcToFile(allocator, owned.verified, &owned.flat.def_dict, owned.flat.loc_table, source_path, nativeSizeBits(), .{ .debug = debug, .jobs = compile_options.jobs }, artifact_path);
            try emit_llvm_llvmc.emitLlvmcToObject(allocator, owned.verified, &owned.flat.def_dict, owned.flat.loc_table, source_path, nativeSizeBits(), .{ .debug = debug, .jobs = compile_options.jobs }, object_path, switch (optimization) {
                .release_small => 1,
                .release_fast => 3,
            });
            finishProfileMetrics(&owned.metrics, if (emit_start) |start| elapsedNs(start) else null, null, if (total_start) |start| elapsedNs(start) else null);
            if (diagnostics_mode == .json) {
                try writeSuccessJson(stderr, owned.metrics);
            }
            return 0;
        },
    }
}

fn executeBuildWasm(allocator: std.mem.Allocator, source_path: []const u8, out_path: []const u8, target: WasmTarget, debug: bool, optimization: driver.Optimization, compile_options: CompileOptions, stderr: anytype, diagnostics_mode: DiagnosticsMode) !u8 {
    const compiled = try compileSource(allocator, source_path, compile_options);
    switch (compiled) {
        .trap => |report| {
            try printTrapReport(stderr, report, diagnostics_mode);
            return 1;
        },
        .ok => |ok| {
            var owned = ok;
            defer owned.deinit(allocator);
            const artifact_path = try intermediateArtifactPath(allocator, out_path);
            defer allocator.free(artifact_path);
            try ensureParentDir(artifact_path);
            try emit_llvm_llvmc.emitLlvmcToFile(allocator, owned.verified, &owned.flat.def_dict, owned.flat.loc_table, source_path, target.size_bits, .{ .debug = debug, .wasm_compat = true, .jobs = compile_options.jobs }, artifact_path);

            driver.compileWasm(allocator, artifact_path, out_path, .{ .triple = target.triple, .no_entry = target.no_entry }, optimization, debug, stderr) catch |err| switch (err) {
                error.ChildProcessFailed => return 1,
                else => return err,
            };
            if (diagnostics_mode == .json) {
                try writeSuccessJson(stderr, owned.metrics);
            }
            return 0;
        },
    }
}

fn executeLayout(
    allocator: std.mem.Allocator,
    args: []const []const u8,
    stdout: anytype,
    stderr: anytype,
) !u8 {
    var name: ?[]const u8 = null;
    var fields: ?[]const u8 = null;
    var format: layout.LayoutFormat = .text;
    var target_bits: u16 = 64;

    var i: usize = 0;
    while (i < args.len) : (i += 1) {
        const arg = args[i];
        if (std.mem.eql(u8, arg, "--name")) {
            if (i + 1 >= args.len) return error.MissingLayoutName;
            name = args[i + 1];
            i += 1;
            continue;
        }
        if (std.mem.eql(u8, arg, "--fields")) {
            if (i + 1 >= args.len) return error.MissingLayoutFields;
            fields = args[i + 1];
            i += 1;
            continue;
        }
        if (std.mem.eql(u8, arg, "--format")) {
            if (i + 1 >= args.len) return error.MissingLayoutFormat;
            const value = args[i + 1];
            if (std.mem.eql(u8, value, "json")) {
                format = .json;
            } else if (std.mem.eql(u8, value, "text")) {
                format = .text;
            } else if (std.mem.eql(u8, value, "debug")) {
                format = .debug;
            } else if (std.mem.eql(u8, value, "dict")) {
                format = .dict;
            } else {
                return error.InvalidLayoutFormat;
            }
            i += 1;
            continue;
        }
        if (std.mem.eql(u8, arg, "--target")) {
            if (i + 1 >= args.len) return error.MissingTarget;
            target_bits = try layout.parseTargetBits(args[i + 1]);
            i += 1;
            continue;
        }
        return error.UnexpectedArgument;
    }

    const layout_name = name orelse return error.MissingLayoutName;
    const layout_fields = fields orelse return error.MissingLayoutFields;
    var computed = try layout.compute(allocator, layout_name, layout_fields, target_bits);
    defer computed.deinit(allocator);

    switch (format) {
        .text => try layout.writeText(stdout, computed),
        .json => {
            try layout.writeJson(stdout, computed);
            try stdout.writeByte('\n');
        },
        .debug => try layout.writeDebug(stdout, computed),
        .dict => try layout.writeDict(stdout, computed),
    }
    _ = stderr;
    return 0;
}

fn executeGraph(
    allocator: std.mem.Allocator,
    args: []const []const u8,
    stdout: anytype,
    stderr: anytype,
    json_mode: bool,
    exec_options: ExecuteOptions,
) !u8 {
    var compile_options = newCompileOptions(exec_options, stderr.any());
    var source_arg: ?[]const u8 = null;
    var i: usize = 0;
    while (i < args.len) : (i += 1) {
        const arg = args[i];
        if (try consumeCompileOption(arg, args, &i, &compile_options)) continue;
        if (source_arg == null) {
            source_arg = arg;
            continue;
        }
        return error.UnexpectedArgument;
    }

    const project_root = try projectRootDir(allocator);
    defer allocator.free(project_root);
    const source_path = if (source_arg) |path| path else try projectSourcePath(allocator, project_root);
    defer if (source_arg == null) allocator.free(source_path);

    const compiled = try compileSource(allocator, source_path, compile_options);
    switch (compiled) {
        .trap => |report| {
            try printTrapReport(stderr, report, if (json_mode) .json else .human);
            return 1;
        },
        .ok => |ok| {
            var owned = ok;
            defer owned.deinit(allocator);

            const resolved_project_root = compile_options.project_root orelse try projectRootFromSourcePath(allocator, source_path);
            defer allocator.free(resolved_project_root);

            var project_manifest = try readProjectManifest(allocator, resolved_project_root);
            defer if (project_manifest) |*m| m.deinit(allocator);

            var dependencies: []pkg_resolver.Dependency = &.{};
            defer if (dependencies.len != 0) allocator.free(dependencies);
            if (project_manifest) |*m| {
                dependencies = try manifestDependencies(m, allocator);
            }

            var node_map = std.StringHashMap(usize).init(allocator);
            defer {
                var it = node_map.iterator();
                while (it.next()) |entry| allocator.free(entry.key_ptr.*);
                node_map.deinit();
            }
            var nodes = std.ArrayList(GraphNode).init(allocator);
            defer {
                for (nodes.items) |node| {
                    allocator.free(node.id);
                    allocator.free(node.label);
                }
                nodes.deinit();
            }
            var edges = std.ArrayList(GraphEdge).init(allocator);
            defer edges.deinit();

            var graph_ctx = GraphBuildContext{
                .allocator = allocator,
                .node_map = &node_map,
                .nodes = &nodes,
                .edges = &edges,
                .dependencies = dependencies,
                .project_root = resolved_project_root,
                .offline = compile_options.offline,
            };

            _ = try collectSourceGraph(&graph_ctx, source_path);
            var function_nodes = try buildFunctionGraph(&graph_ctx, &owned.verified);
            defer function_nodes.deinit();
            try buildCallGraph(&graph_ctx, &owned.verified, &function_nodes);

            if (json_mode) {
                try writeGraphJson(stdout, owned.metrics, nodes.items, edges.items);
            } else {
                try writeGraphText(stdout, owned.metrics, nodes.items, edges.items);
            }
            return 0;
        },
    }
}

fn executeSize(
    allocator: std.mem.Allocator,
    args: []const []const u8,
    stdout: anytype,
    stderr: anytype,
    json_mode: bool,
    exec_options: ExecuteOptions,
) !u8 {
    var compile_options = newCompileOptions(exec_options, stderr.any());
    var source_arg: ?[]const u8 = null;
    var i: usize = 0;
    while (i < args.len) : (i += 1) {
        const arg = args[i];
        if (try consumeCompileOption(arg, args, &i, &compile_options)) continue;
        if (source_arg == null) {
            source_arg = arg;
            continue;
        }
        return error.UnexpectedArgument;
    }

    const project_root = try projectRootDir(allocator);
    defer allocator.free(project_root);
    const source_path = if (source_arg) |path| path else try projectSourcePath(allocator, project_root);
    defer if (source_arg == null) allocator.free(source_path);

    const compiled = try compileSource(allocator, source_path, compile_options);
    switch (compiled) {
        .trap => |report| {
            try printTrapReport(stderr, report, if (json_mode) .json else .human);
            return 1;
        },
        .ok => |ok| {
            var owned = ok;
            defer owned.deinit(allocator);
            const sizes = try computeFunctionSizes(allocator, &owned.verified);
            defer allocator.free(sizes);

            if (json_mode) {
                try writeSizeJson(stdout, owned.metrics, sizes);
            } else {
                try writeSizeText(stdout, owned.metrics, sizes);
            }
            return 0;
        },
    }
}

fn parseTarget(text: []const u8) !WasmTarget {
    if (std.mem.eql(u8, text, "wasm32")) return .{ .triple = "wasm32-wasi", .no_entry = false, .size_bits = 32 };
    if (std.mem.eql(u8, text, "wasm64")) return .{ .triple = "wasm64-freestanding", .no_entry = true, .size_bits = 64 };
    return error.InvalidTarget;
}

fn parseOptimizationFlag(arg: []const u8) ?driver.Optimization {
    if (std.mem.eql(u8, arg, "--release-fast")) return .release_fast;
    if (std.mem.eql(u8, arg, "--release-small")) return .release_small;
    return null;
}

fn executeTest(
    allocator: std.mem.Allocator,
    source_path: []const u8,
    compile_options: CompileOptions,
    selection: test_meta.TestSelection,
    stdout: anytype,
    stderr: anytype,
    diagnostics_mode: DiagnosticsMode,
) !u8 {
    const compiled = try compileSource(allocator, source_path, compile_options);
    switch (compiled) {
        .trap => |report| {
            try printTrapReport(stderr, report, diagnostics_mode);
            return 1;
        },
        .ok => |ok| {
            var owned = ok;
            defer owned.deinit(allocator);
            const std_archive_path = try saStdArchivePath(allocator);
            defer allocator.free(std_archive_path);

            var tmp = try TmpWorkDir.init();
            defer tmp.cleanup();

            const source_stem = sourceStem(source_path);
            const artifact_name = try std.fmt.allocPrint(allocator, "{s}.test.sa.bc", .{source_stem});
            defer allocator.free(artifact_name);
            const exe_name = try std.fmt.allocPrint(allocator, "{s}.test", .{source_stem});
            defer allocator.free(exe_name);

            const artifact_dir = try tmp.dir.realpathAlloc(allocator, ".");
            defer allocator.free(artifact_dir);

            const artifact_full_path = try std.fs.path.join(allocator, &.{ artifact_dir, artifact_name });
            defer allocator.free(artifact_full_path);
            try emit_llvm_llvmc.emitLlvmcToFile(allocator, owned.verified, &owned.flat.def_dict, owned.flat.loc_table, source_path, nativeSizeBits(), .{ .jobs = compile_options.jobs, .test_mode = true }, artifact_full_path);

            const exe_full_path = try std.fs.path.join(allocator, &.{ artifact_dir, exe_name });
            defer allocator.free(exe_full_path);

            driver.compileExe(allocator, artifact_full_path, exe_full_path, .release_small, std_archive_path, &.{}, false, stderr) catch |err| switch (err) {
                error.ChildProcessFailed => return 1,
                else => return err,
            };

            var test_list = try test_meta.collect(allocator, owned.verified.function_sigs);
            return try test_runner.run(
                allocator,
                exe_full_path,
                tmp.dir,
                &test_list,
                selection,
                compile_options.jobs,
                stdout.any(),
                stderr.any(),
            );
        },
    }
}

pub fn executeWithWritersAndOptions(
    allocator: std.mem.Allocator,
    argv: []const []const u8,
    stdout: anytype,
    stderr: anytype,
    exec_options: ExecuteOptions,
) !u8 {
    const normalized_args = try stripJsonFlag(allocator, argv);
    defer allocator.free(normalized_args);

    const args = normalized_args;
    const json_mode = hasJsonFlag(argv);

    // Global flags: --help / -h / --version (checked before command dispatch)
    if (args.len >= 2) {
        if (std.mem.eql(u8, args[1], "--help") or std.mem.eql(u8, args[1], "-h")) {
            try printUsage(stdout);
            return 0;
        }
        if (std.mem.eql(u8, args[1], "--version")) {
            try printVersion(stdout);
            return 0;
        }
    }

    if (args.len < 2) {
        try printUsage(stderr);
        return 1;
    }

    const cmd: Command = blk: {
        if (std.mem.eql(u8, args[1], commandName(.build))) break :blk .build;
        if (std.mem.eql(u8, args[1], commandName(.run))) break :blk .run;
        if (std.mem.eql(u8, args[1], commandName(.init))) break :blk .init;
        if (std.mem.eql(u8, args[1], commandName(.install))) break :blk .install;
        if (std.mem.eql(u8, args[1], commandName(.build_exe))) break :blk .build_exe;
        if (std.mem.eql(u8, args[1], commandName(.build_wasm))) break :blk .build_wasm;
        if (std.mem.eql(u8, args[1], commandName(.build_obj))) break :blk .build_obj;
        if (std.mem.eql(u8, args[1], commandName(.bc2sa))) break :blk .bc2sa;
        if (std.mem.eql(u8, args[1], commandName(.audit))) break :blk .audit;
        if (std.mem.eql(u8, args[1], commandName(.graph))) break :blk .graph;
        if (std.mem.eql(u8, args[1], commandName(.layout))) break :blk .layout;
        if (std.mem.eql(u8, args[1], commandName(.fetch))) break :blk .fetch;
        if (std.mem.eql(u8, args[1], commandName(.size))) break :blk .size;
        if (std.mem.eql(u8, args[1], commandName(.test_cmd))) break :blk .test_cmd;
        if (std.mem.eql(u8, args[1], commandName(.explain))) break :blk .explain;
        if (std.mem.eql(u8, args[1], commandName(.fix))) break :blk .fix;
        if (std.mem.eql(u8, args[1], commandName(.skills))) break :blk .skills;
        if (std.mem.eql(u8, args[1], commandName(.help))) break :blk .help;
        if (std.mem.eql(u8, args[1], commandName(.version))) break :blk .version;
        return error.UnknownCommand;
    };

    switch (cmd) {
        .help => {
            try printUsage(stdout);
            return 0;
        },
        .version => {
            try printVersion(stdout);
            return 0;
        },
        .layout => {
            return try executeLayout(allocator, args[2..], stdout, stderr);
        },
        .graph => {
            return try executeGraph(allocator, args[2..], stdout, stderr, json_mode, exec_options);
        },
        .audit => return error.UnknownCommand,
        .explain => return try explainCommand(stdout, args, json_mode),
        .fix => return try fixCommand(stdout, args, json_mode),
        .skills => return try skillsCommand(stdout, json_mode),
        .init => return try executeInit(allocator, args[2..], stdout),
        .install => return try executeInstall(allocator, args[2..], stdout),
        .build => {
            if (args.len < 3) return error.MissingSourcePath;
            const source_path = args[2];
            var compile_options = newCompileOptions(exec_options, stderr.any());
            var out_path: ?[]const u8 = null;
            var debug = false;
            var optimization: driver.Optimization = .release_small;
            var i: usize = 3;
            while (i < args.len) : (i += 1) {
                if (try consumeCompileOption(args[i], args, &i, &compile_options)) continue;
                if (std.mem.eql(u8, args[i], "-o")) {
                    if (i + 1 >= args.len) return error.MissingOutputPath;
                    out_path = args[i + 1];
                    i += 1;
                    continue;
                }
                if (std.mem.eql(u8, args[i], "-g")) {
                    debug = true;
                    continue;
                }
                if (std.mem.eql(u8, args[i], "--no-debug")) {
                    debug = false;
                    continue;
                }
                if (parseOptimizationFlag(args[i])) |mode| {
                    optimization = mode;
                    continue;
                }
                return error.UnexpectedArgument;
            }
            const owned_out = if (out_path) |p| p else try deriveOutputPath(allocator, source_path, "");
            defer if (out_path == null) allocator.free(owned_out);
            return try executeBuildExe(allocator, source_path, if (out_path) |p| p else owned_out, debug, optimization, compile_options, stderr, if (json_mode) .json else .human);
        },
        .fetch => {
            if (args.len < 3) return error.MissingSourcePath;
            var result = try pkg_fetch.fetchPackage(allocator, args[2], "HEAD", .{});
            defer result.deinit(allocator);
            try stdout.print("{s}\n", .{result.root});
            return 0;
        },
        .size => {
            return try executeSize(allocator, args[2..], stdout, stderr, json_mode, exec_options);
        },
        .run => {
            if (args.len < 3) return error.MissingSourcePath;
            var compile_options = newCompileOptions(exec_options, stderr.any());
            var source_path: ?[]const u8 = null;
            var runtime_args = std.ArrayList([]const u8).init(allocator);
            defer runtime_args.deinit();

            var i: usize = 2;
            while (i < args.len) : (i += 1) {
                if (try consumeCompileOption(args[i], args, &i, &compile_options)) continue;
                if (source_path == null) {
                    source_path = args[i];
                    continue;
                }
                try runtime_args.append(args[i]);
            }
            const source = source_path orelse return error.MissingSourcePath;
            return try executeRun(allocator, source, compile_options, runtime_args.items, stdout, stderr, if (json_mode) .json else .human);
        },
        .build_exe => {
            if (args.len < 3) return error.MissingSourcePath;
            const source_path = args[2];
            var compile_options = newCompileOptions(exec_options, stderr.any());
            var out_path: ?[]const u8 = null;
            var debug = false;
            var optimization: driver.Optimization = .release_small;
            var i: usize = 3;
            while (i < args.len) : (i += 1) {
                if (try consumeCompileOption(args[i], args, &i, &compile_options)) continue;
                if (std.mem.eql(u8, args[i], "-o")) {
                    if (i + 1 >= args.len) return error.MissingOutputPath;
                    out_path = args[i + 1];
                    i += 1;
                    continue;
                }
                if (std.mem.eql(u8, args[i], "-g")) {
                    debug = true;
                    continue;
                }
                if (std.mem.eql(u8, args[i], "--no-debug")) {
                    debug = false;
                    continue;
                }
                if (parseOptimizationFlag(args[i])) |mode| {
                    optimization = mode;
                    continue;
                }
                return error.UnexpectedArgument;
            }
            const owned_out = if (out_path) |p| p else try deriveOutputPath(allocator, source_path, "");
            defer if (out_path == null) allocator.free(owned_out);
            return try executeBuildExe(allocator, source_path, if (out_path) |p| p else owned_out, debug, optimization, compile_options, stderr, if (json_mode) .json else .human);
        },
        .build_obj => {
            if (args.len < 3) return error.MissingSourcePath;
            const source_path = args[2];
            var compile_options = newCompileOptions(exec_options, stderr.any());
            var out_path: ?[]const u8 = null;
            var debug = false;
            var optimization: driver.Optimization = .release_small;
            var i: usize = 3;
            while (i < args.len) : (i += 1) {
                if (try consumeCompileOption(args[i], args, &i, &compile_options)) continue;
                if (std.mem.eql(u8, args[i], "-o")) {
                    if (i + 1 >= args.len) return error.MissingOutputPath;
                    out_path = args[i + 1];
                    i += 1;
                    continue;
                }
                if (std.mem.eql(u8, args[i], "-g")) {
                    debug = true;
                    continue;
                }
                if (std.mem.eql(u8, args[i], "--no-debug")) {
                    debug = false;
                    continue;
                }
                if (parseOptimizationFlag(args[i])) |mode| {
                    optimization = mode;
                    continue;
                }
                return error.UnexpectedArgument;
            }
            const owned_out = if (out_path) |p| p else try deriveOutputPath(allocator, source_path, ".o");
            defer if (out_path == null) allocator.free(owned_out);
            return try executeBuildObj(allocator, source_path, if (out_path) |p| p else owned_out, debug, optimization, compile_options, stderr, if (json_mode) .json else .human);
        },
        .build_wasm => {
            if (args.len < 3) return error.MissingSourcePath;
            const source_path = args[2];
            var compile_options = newCompileOptions(exec_options, stderr.any());
            var out_path: ?[]const u8 = null;
            var target: WasmTarget = .{ .triple = "wasm32-wasi", .no_entry = false, .size_bits = 32 };
            var debug = false;
            var optimization: driver.Optimization = .release_small;
            var i: usize = 3;
            while (i < args.len) : (i += 1) {
                if (try consumeCompileOption(args[i], args, &i, &compile_options)) continue;
                if (std.mem.eql(u8, args[i], "-o")) {
                    if (i + 1 >= args.len) return error.MissingOutputPath;
                    out_path = args[i + 1];
                    i += 1;
                    continue;
                }
                if (std.mem.eql(u8, args[i], "-g")) {
                    debug = true;
                    continue;
                }
                if (std.mem.eql(u8, args[i], "--no-debug")) {
                    debug = false;
                    continue;
                }
                if (parseOptimizationFlag(args[i])) |mode| {
                    optimization = mode;
                    continue;
                }
                if (std.mem.eql(u8, args[i], "--target")) {
                    if (i + 1 >= args.len) return error.MissingTarget;
                    target = try parseTarget(args[i + 1]);
                    i += 1;
                    continue;
                }
                return error.UnexpectedArgument;
            }
            const owned_out = if (out_path) |p| p else try deriveOutputPath(allocator, source_path, ".wasm");
            defer if (out_path == null) allocator.free(owned_out);
            return try executeBuildWasm(allocator, source_path, if (out_path) |p| p else owned_out, target, debug, optimization, compile_options, stderr, if (json_mode) .json else .human);
        },
        .bc2sa => {
            if (args.len < 3) return error.MissingSourcePath;
            const source_path = args[2];
            const translated = bc2sa.translateBitcodeFile(allocator, source_path) catch |err| {
                try printCliError(stderr, err, if (json_mode) .json else .human);
                return 1;
            };
            defer allocator.free(translated);
            try stdout.writeAll(translated);
            if (translated.len == 0 or translated[translated.len - 1] != '\n') try stdout.writeByte('\n');
            return 0;
        },
        .test_cmd => {
            if (args.len < 3) return error.MissingSourcePath;
            const source_path = args[2];
            var compile_options = newCompileOptions(exec_options, stderr.any());
            var include_filters = std.ArrayList([]const u8).init(allocator);
            defer include_filters.deinit();
            var skip_filters = std.ArrayList([]const u8).init(allocator);
            defer skip_filters.deinit();
            var exact = false;
            var run_ignored = test_meta.RunIgnored.normal;
            var i: usize = 3;
            while (i < args.len) : (i += 1) {
                if (try consumeCompileOption(args[i], args, &i, &compile_options)) continue;
                if (std.mem.eql(u8, args[i], "--filter")) {
                    if (i + 1 >= args.len) return error.MissingFilterValue;
                    try include_filters.append(args[i + 1]);
                    i += 1;
                    continue;
                }
                if (std.mem.eql(u8, args[i], "--skip")) {
                    if (i + 1 >= args.len) return error.MissingFilterValue;
                    try skip_filters.append(args[i + 1]);
                    i += 1;
                    continue;
                }
                if (std.mem.eql(u8, args[i], "--exact")) {
                    exact = true;
                    continue;
                }
                if (std.mem.eql(u8, args[i], "--ignored")) {
                    run_ignored = .only;
                    continue;
                }
                if (std.mem.eql(u8, args[i], "--include-ignored")) {
                    run_ignored = .include;
                    continue;
                }
                return error.UnexpectedArgument;
            }
            const selection = test_meta.TestSelection{
                .include_filters = include_filters.items,
                .skip_filters = skip_filters.items,
                .exact = exact,
                .ignored = run_ignored,
            };
            return try executeTest(allocator, source_path, compile_options, selection, stdout, stderr, if (json_mode) .json else .human);
        },
    }
}

pub fn executeWithWriters(allocator: std.mem.Allocator, argv: []const []const u8, stdout: anytype, stderr: anytype) !u8 {
    return executeWithWritersAndOptions(allocator, argv, stdout, stderr, .{});
}

pub fn execute(allocator: std.mem.Allocator, argv: []const []const u8) !u8 {
    return executeWithWriters(allocator, argv, std.io.getStdOut().writer(), std.io.getStdErr().writer());
}

test "trap reports print a human summary and preserve json payload" {
    var list = std.ArrayList(u8).init(std.testing.allocator);
    defer list.deinit();

    var report = trap.TrapReport{
        .trap = .memory_leak,
        .trap_code = trap.trapCode(.memory_leak),
        .line = 12,
        .source_line = 9,
        .source_text_buf = [_]u8{0} ** 256,
        .original_text_buf = [_]u8{0} ** 256,
        .source_text = null,
        .original_text = null,
        .register_buf = [_]u8{0} ** 64,
        .register = null,
        .registers = &.{},
        .expected_mask = null,
        .actual_mask = 1,
        .expected_mask_name = null,
        .actual_mask_name = "Active",
        .upstream_loc = null,
        .upstream_file_buf = [_]u8{0} ** 128,
        .upstream_line = 42,
        .upstream_col = 7,
        .function_buf = [_]u8{0} ** 64,
        .function = null,
        .is_ffi_wrapper = false,
        .message = "live registers remain at function exit",
        .hint = "insert explicit release",
    };
    const source = "result = load node+0 as i32";
    std.mem.copyForwards(u8, report.source_text_buf[0..source.len], source);
    const register = "r1";
    std.mem.copyForwards(u8, report.register_buf[0..register.len], register);
    const upstream_file = "main.rs";
    std.mem.copyForwards(u8, report.upstream_file_buf[0..upstream_file.len], upstream_file);
    const function = "@main() -> i32:";
    std.mem.copyForwards(u8, report.function_buf[0..function.len], function);
    try printTrapReport(list.writer(), report, .human);
    const output = list.items;

    try std.testing.expect(std.mem.indexOf(u8, output, "error[MemoryLeak]: live registers remain at function exit") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "  in function @main() -> i32:") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "  upstream main.rs:42:7") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "  line 9 (expanded 12): result = load node+0 as i32") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "  register: r1") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "  state: Active") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "  help: insert explicit release") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "\"trap\":\"MemoryLeak\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "\"function\":\"@main() -> i32:\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "\"register\":\"r1\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "\"hint\":\"insert explicit release\"") != null);
}

test "cli error printing is detailed and json capable" {
    var human = std.ArrayList(u8).init(std.testing.allocator);
    defer human.deinit();
    try printCliError(human.writer(), error.MissingSourcePath, .human);
    try std.testing.expect(std.mem.indexOf(u8, human.items, "error[SA-CLI-001]: missing required positional argument") != null);
    try std.testing.expect(std.mem.indexOf(u8, human.items, "help: pass the source file, project path, or required operand after the command") != null);

    var json = std.ArrayList(u8).init(std.testing.allocator);
    defer json.deinit();
    try printCliError(json.writer(), error.InvalidTarget, .json);
    try std.testing.expect(std.mem.indexOf(u8, json.items, "\"status\":\"error\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json.items, "\"code\":\"SA-CLI-006\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json.items, "\"name\":\"InvalidTarget\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json.items, "\"message\":\"invalid target\"") != null);
}

test "flatten error mapping keeps import resolution and unsupported type hints specific" {
    const import_source =
        \\@import "missing.sa"
        \\@main() -> i32:
        \\    return 0
    ;
    const import_report = trapFromFlattenError("/tmp/import.sa", import_source, error.PackageNotResolved, 1);
    try std.testing.expectEqual(trap.Trap.import_resolution_failed, import_report.trap);
    try std.testing.expectEqual(@as(u32, 1050), import_report.trap_code.?);
    try std.testing.expectEqualStrings("/tmp/import.sa", import_report.file.?);
    try std.testing.expectEqualStrings("import path could not be resolved", import_report.message);
    try std.testing.expectEqualStrings("check the import path, package identity, local vendor tree, and package cache", import_report.hint.?);
    try std.testing.expectEqualStrings("fix-import", import_report.repair_action.?);

    const type_source =
        \\@test "probe":
        \\    point = call @support_make_point(10, 20)
    ;
    const type_report = trapFromFlattenError("/tmp/type.sa", type_source, error.UnsupportedType, 2);
    try std.testing.expectEqual(trap.Trap.unsupported_type, type_report.trap);
    try std.testing.expectEqualStrings("/tmp/type.sa", type_report.file.?);
    try std.testing.expect(type_report.bad_token != null);
    try std.testing.expectEqualStrings("unsupported type annotation during flattening", type_report.message);
    try std.testing.expectEqualStrings("inspect the callee declaration referenced by this call site; the unsupported annotation is usually in the imported signature", type_report.hint.?);
}

test "duplicate definition trap gets a repair hint" {
    const source =
        \\#def X = 1
        \\#def X = 2
    ;
    const report = trapFromFlattenError("/tmp/dup.sa", source, error.DuplicateDef, 2);
    try std.testing.expectEqual(trap.Trap.duplicate_def, report.trap);
    try std.testing.expectEqualStrings("/tmp/dup.sa", report.file.?);
    try std.testing.expectEqualStrings("rename-def", report.repair_action.?);
    try std.testing.expectEqualStrings("change one of the conflicting names or namespace the symbol", report.repair_hint.?);
    try std.testing.expectEqualStrings("high", report.repair_confidence.?);
}
