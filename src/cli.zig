const std = @import("std");
const builtin = @import("builtin");

const flattener = @import("flattener.zig");
const line_classifier = @import("flattener/line_classifier.zig");
const interp = @import("interp.zig");
const build_options = @import("build_options");
const driver = @import("driver/zigcc.zig");
const emit_llvm = @import("emit_llvm.zig");
const llvm2sa = @import("llvm2sa.zig");
const layout = @import("layout.zig");
const manifest = @import("pkg/manifest.zig");
const pkg_fetch = @import("pkg/fetch.zig");
const pkg_resolver = @import("pkg/resolver.zig");
const plugins = @import("plugins.zig");
const referee_call = @import("referee/call.zig");
const referee = @import("referee.zig");
const sax_cli = @import("sax/cli.zig");
const test_meta = @import("test_meta.zig");
const test_runner = @import("test_runner.zig");
const trap = @import("common/trap.zig");
const common_upstream = @import("common/upstream_loc.zig");
const db = @import("db/mod.zig");
const db_trap = @import("db/common/trap.zig");

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

const CompileMetrics = struct {
    compile_tokens: u64,
    instruction_count: u64,
};

fn computeCompileMetrics(flat: *const flattener.FlattenResult, verified: *const referee.VerifyOk) CompileMetrics {
    const compile_tokens = @as(u64, flat.instructions.len) + @as(u64, flat.const_decls.len) + @as(u64, flat.function_sigs.len) + @as(u64, flat.test_sigs.len) + @as(u64, verified.annotated.len);
    return .{
        .compile_tokens = compile_tokens,
        .instruction_count = @as(u64, verified.annotated.len),
    };
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
    offline: bool = false,
    project_root: ?[]const u8 = null,
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
    build,
    build_exe,
    build_wasm,
    build_obj,
    llvm2sa,
    sax,
    audit,
    graph,
    db,
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
    ll_path: []const u8,
    target_name: []const u8,
    source_suffix: []const u8,
    hash_key: []const u8,

    fn deinit(self: *ProjectBuildArtifact, allocator: std.mem.Allocator) void {
        allocator.free(self.name);
        allocator.free(self.out_path);
        allocator.free(self.ll_path);
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
    const src_path = try pathJoinAlloc(allocator, &.{ root_path, "src", "main.saasm" });
    if (projectPathExists(src_path)) return src_path;
    allocator.free(src_path);
    const fallback = try pathJoinAlloc(allocator, &.{ root_path, "main.saasm" });
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
        .build_exe => "build-exe",
        .build_wasm => "build-wasm",
        .build_obj => "build-obj",
        .llvm2sa => "llvm2sa",
        .sax => "sax",
        .audit => "audit",
        .graph => "graph",
        .db => "db",
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
    return std.mem.eql(u8, name, "build") or std.mem.eql(u8, name, "run") or std.mem.eql(u8, name, "build-exe") or std.mem.eql(u8, name, "build-wasm") or std.mem.eql(u8, name, "build-obj") or std.mem.eql(u8, name, "audit") or std.mem.eql(u8, name, "graph") or std.mem.eql(u8, name, "layout") or std.mem.eql(u8, name, "size") or std.mem.eql(u8, name, "test") or std.mem.eql(u8, name, "explain") or std.mem.eql(u8, name, "fix") or std.mem.eql(u8, name, "skills");
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
                "The same issue appears in build, run, test, fetch, and db subcommands when the target path is omitted.",
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

fn convertDbTrapReport(report: db_trap.TrapReport) trap.TrapReport {
    return .{
        .trap = @as(trap.Trap, @enumFromInt(@intFromEnum(report.trap))),
        .trap_code = report.trap_code,
        .line = report.line,
        .source_line = report.source_line,
        .source_text_buf = report.source_text_buf,
        .original_text_buf = report.original_text_buf,
        .source_text = report.source_text,
        .original_text = report.original_text,
        .register_buf = report.register_buf,
        .register = report.register,
        .registers = report.registers,
        .expected_mask = report.expected_mask,
        .actual_mask = report.actual_mask,
        .expected_mask_name = report.expected_mask_name,
        .actual_mask_name = report.actual_mask_name,
        .upstream_loc = if (report.upstream_loc) |loc| .{
            .file = loc.file,
            .line = loc.line,
            .col = loc.col,
        } else null,
        .upstream_file_buf = report.upstream_file_buf,
        .upstream_line = report.upstream_line,
        .upstream_col = report.upstream_col,
        .function_buf = report.function_buf,
        .function = report.function,
        .is_ffi_wrapper = report.is_ffi_wrapper,
        .repair_action = report.repair_action,
        .repair_hint = report.repair_hint,
        .repair_confidence = report.repair_confidence,
        .message = report.message,
        .hint = report.hint,
    };
}

fn printUsage(writer: anytype) !void {
    try writer.writeAll("usage: saasm <command> [options]\n\n");
    try writer.writeAll("Commands:\n");
    try writer.writeAll("  build        <file>            Compile a .saasm source to a native executable\n");
    try writer.writeAll("  run          <file>            Compile and immediately execute a .saasm file\n");
    try writer.writeAll("  build-exe    <file>            Build a standalone executable (alias for build)\n");
    try writer.writeAll("  build-obj    <file>            Build an object file (.o)\n");
    try writer.writeAll("  build-wasm   <file>            Build a WebAssembly module (.wasm)\n");
    try writer.writeAll("  test         <file>            Run @test blocks in a .saasm file\n");
    try writer.writeAll("  sax          <sub> <file>      SAX subcommands: build | check | dev | new\n");
    try writer.writeAll("  db           <sub> ...         DB subcommands: init | register | exec | inspect | ...\n");
    try writer.writeAll("  fetch        <url>             Fetch and cache a remote package\n");
    try writer.writeAll("  audit        <file>            Audit package capability declarations\n");
    try writer.writeAll("  graph        <path>            Output a dependency/call graph\n");
    try writer.writeAll("  layout       ...               Print struct layout information\n");
    try writer.writeAll("  size         <file>            Print function size statistics\n");
    try writer.writeAll("  llvm2sa      <file>            Translate LLVM IR to SA assembly\n");
    try writer.writeAll("  explain      <code>            Explain a diagnostic error code\n");
    try writer.writeAll("  fix          <file>            Suggest fixes for diagnostics\n");
    try writer.writeAll("  skills                         List compiler skills and capabilities\n");
    try writer.writeAll("  help         [command]         Show this help message\n");
    try writer.writeAll("  version                        Print the SA toolchain version\n");
    try writer.writeAll("\nGlobal options:\n");
    try writer.writeAll("  --json                         Output diagnostics in JSON format\n");
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
    try writer.print("saasm {s}\n", .{ver});
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
            .hint = "use --format text or --format json",
        },
        error.InvalidLayoutFormat => .{
            .code = "SA-CLI-011",
            .message = "invalid layout format",
            .hint = "use --format text or --format json",
        },
        error.UnknownCommand => .{
            .code = "SA-CLI-012",
            .message = "unknown command",
            .hint = "use build, run, build-exe, build-wasm, build-obj, audit, graph, layout, size, test, explain, fix, skills, sax, db, fetch, llvm2sa, help, or version",
        },
        error.UnexpectedArgument => .{
            .code = "SA-CLI-013",
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
        error.InvalidImportPath => "use a valid relative `.saasm` or package identity without `../`, empty segments, or whitespace",
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
            "explain <code>",
            "fix --plan --json",
            "skills",
        } },
        .{ .name = "std runtime", .summary = "Current Zig-backed facade surface", .items = &.{
            "JSON DOM and streaming facade",
            "Regex facade over Zig/POSIX backend",
            "fs/net/process/term facades stay thin in SA",
        } },
    };
    const plugin_sections = try plugins.collectSkills(std.heap.page_allocator);
    defer std.heap.page_allocator.free(plugin_sections);

    var sections_list = std.ArrayList(SkillSection).init(std.heap.page_allocator);
    errdefer sections_list.deinit();
    try sections_list.appendSlice(&base_sections);
    for (plugin_sections) |section| {
        try sections_list.append(.{
            .name = section.name,
            .summary = section.summary,
            .items = section.items,
        });
    }
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

fn trapFromFlattenError(source: []const u8, err: anyerror, last_line: ?u32) trap.TrapReport {
    const forbidden = flattener.findFirstForbiddenLine(source);
    const line_no = if (forbidden) |hit| hit.line_no else last_line orelse 1;
    const line_text = lineAt(source, line_no);
    const source_text_buf: [256]u8 = [_]u8{0} ** 256;
    const original_text_buf: [256]u8 = [_]u8{0} ** 256;
    var report: trap.TrapReport = switch (err) {
        error.ForbiddenSyntax => .{
            .trap = .forbidden_syntax,
            .trap_code = trap.trapCode(.forbidden_syntax),
            .line = line_no,
            .source_line = line_no,
            .source_text_buf = source_text_buf,
            .original_text_buf = original_text_buf,
            .source_text = null,
            .original_text = null,
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
            .line = line_no,
            .source_line = line_no,
            .source_text_buf = source_text_buf,
            .original_text_buf = original_text_buf,
            .source_text = null,
            .original_text = null,
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
        },
        error.InvalidImportPath, error.PackageNotResolved, error.AmbiguousPackageVersion, error.PrecompiledArtifactRejected, error.InvalidPath => .{
            .trap = .import_resolution_failed,
            .trap_code = trap.trapCode(.import_resolution_failed),
            .line = line_no,
            .source_line = line_no,
            .source_text_buf = source_text_buf,
            .original_text_buf = original_text_buf,
            .source_text = null,
            .original_text = null,
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
        },
        error.OutOfMemory => .{
            .trap = .arena_oom,
            .trap_code = trap.trapCode(.arena_oom),
            .line = line_no,
            .source_line = line_no,
            .source_text_buf = source_text_buf,
            .original_text_buf = original_text_buf,
            .source_text = null,
            .original_text = null,
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
            .line = line_no,
            .source_line = line_no,
            .source_text_buf = source_text_buf,
            .original_text_buf = original_text_buf,
            .source_text = null,
            .original_text = null,
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
            .line = line_no,
            .source_line = line_no,
            .source_text_buf = source_text_buf,
            .original_text_buf = original_text_buf,
            .source_text = null,
            .original_text = null,
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
            .line = line_no,
            .source_line = line_no,
            .source_text_buf = source_text_buf,
            .original_text_buf = original_text_buf,
            .source_text = null,
            .original_text = null,
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
            .line = line_no,
            .source_line = line_no,
            .source_text_buf = source_text_buf,
            .original_text_buf = original_text_buf,
            .source_text = null,
            .original_text = null,
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
            .line = line_no,
            .source_line = line_no,
            .source_text_buf = source_text_buf,
            .original_text_buf = original_text_buf,
            .source_text = null,
            .original_text = null,
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
            .line = line_no,
            .source_line = line_no,
            .source_text_buf = source_text_buf,
            .original_text_buf = original_text_buf,
            .source_text = null,
            .original_text = null,
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
        copyTextBuf(&report.source_text_buf, excerpt);
        copyTextBuf(&report.original_text_buf, excerpt);
    }
    switch (report.trap) {
        .forbidden_syntax => {
            report.repair_action = "rewrite";
            report.repair_hint = "lower structured control flow into labels, branches, and explicit register moves";
            report.repair_confidence = "high";
        },
        .unsupported_type => {
            report.repair_action = "inspect-signature";
            report.repair_hint = "check the callee declaration or imported signature for unsupported primitive names";
            report.repair_confidence = "medium";
        },
        .import_resolution_failed => {
            report.repair_action = "pin-import";
            report.repair_hint = "choose one source package or ref and avoid ambiguous or rejected artifacts";
            report.repair_confidence = "medium";
        },
        .duplicate_def => {
            report.repair_action = "rename-def";
            report.repair_hint = "change one of the conflicting #def names";
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
    index.* += 1;
    return true;
}

fn loadSource(allocator: std.mem.Allocator, path: []const u8) ![]u8 {
    var file = try std.fs.cwd().openFile(path, .{});
    defer file.close();
    return try file.readToEndAlloc(allocator, 16 * 1024 * 1024);
}

fn projectRootFromSourcePath(source_path: []const u8) []const u8 {
    return std.fs.path.dirname(source_path) orelse ".";
}

fn pluginSoPath(allocator: std.mem.Allocator, file_name: []const u8) ![]u8 {
    return try std.fs.path.join(allocator, &.{ build_options.repo_root, "zig-out", "lib", file_name });
}

fn copyFileByStream(source_path: []const u8, dest_path: []const u8) !void {
    const source_file = try std.fs.openFileAbsolute(source_path, .{ .mode = .read_only });
    defer source_file.close();

    const source_stat = try source_file.stat();
    var dest_file = std.fs.createFileAbsolute(dest_path, .{
        .truncate = true,
        .exclusive = true,
        .read = true,
        .mode = source_stat.mode,
    }) catch |err| switch (err) {
        error.PathAlreadyExists => return,
        else => return err,
    };
    defer dest_file.close();

    var buffer: [16 * 1024]u8 = undefined;
    while (true) {
        const read_len = try source_file.read(&buffer);
        if (read_len == 0) break;
        try dest_file.writeAll(buffer[0..read_len]);
    }
}

fn copyFileAbsoluteCompat(source_path: []const u8, dest_path: []const u8) !void {
    std.fs.copyFileAbsolute(source_path, dest_path, .{}) catch |err| switch (err) {
        error.PathAlreadyExists => return,
        error.AccessDenied, error.BadPathName, error.FileNotFound, error.FileTooBig, error.IsDir, error.NoDevice, error.NotDir, error.SystemResources, error.Unexpected => return copyFileByStream(source_path, dest_path),
        else => return err,
    };
}

fn ensurePluginSoAvailable(allocator: std.mem.Allocator, out_path: []const u8, file_name: []const u8) !void {
    const source_path = try pluginSoPath(allocator, file_name);
    defer allocator.free(source_path);

    const dest_dir = std.fs.path.dirname(out_path) orelse ".";
    const cwd_abs = try std.fs.cwd().realpathAlloc(allocator, ".");
    defer allocator.free(cwd_abs);
    const abs_dest_dir = if (std.fs.path.isAbsolute(dest_dir))
        try allocator.dupe(u8, dest_dir)
    else
        try std.fs.path.join(allocator, &.{ cwd_abs, dest_dir });
    defer allocator.free(abs_dest_dir);

    const dest_path = try std.fs.path.join(allocator, &.{ abs_dest_dir, file_name });
    defer allocator.free(dest_path);
    try std.fs.cwd().makePath(abs_dest_dir);

    try copyFileAbsoluteCompat(source_path, dest_path);
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
    const source = try loadSource(allocator, source_path);
    defer allocator.free(source);

    const project_root = options.project_root orelse projectRootFromSourcePath(source_path);

    var project_manifest = try readProjectManifest(allocator, project_root);
    defer if (project_manifest) |*m| m.deinit(allocator);

    var dependency_slice: []pkg_resolver.Dependency = &.{};
    defer if (dependency_slice.len != 0) allocator.free(dependency_slice);

    if (project_manifest) |*m| {
        dependency_slice = try manifestDependencies(m, allocator);
    }

    const package_grants: []const manifest.RequireEntry = if (project_manifest) |*m| m.requires else &.{};

    var error_ctx: flattener.ErrorContext = .{};
    const resolve_ctx = flattener.ResolveContext{
        .dependencies = dependency_slice,
        .options = .{
            .project_root = project_root,
            .offline = options.offline,
        },
    };
    var flat = flattener.flattenFileWithContextAndPackages(allocator, source_path, source, &error_ctx, resolve_ctx) catch |err| {
        return .{ .trap = trapFromFlattenError(source, err, flattener.takeErrorSourceLine(&error_ctx)) };
    };
    errdefer flat.deinit(allocator);

    const verified = try referee.verifyWithOptions(allocator, flat.instructions, flat.const_decls, .{ .jobs = options.jobs, .package_grants = package_grants });
    return switch (verified) {
        .ok => |ok| .{ .ok = .{ .flat = flat, .verified = ok, .metrics = computeCompileMetrics(&flat, &ok) } },
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

fn printTableInfo(writer: anytype, info: db.table.TableInfo) !void {
    try writer.print("row_count: {d}\n", .{info.row_count});
    try writer.print("segment_count: {d}\n", .{info.segment_count});
    try writer.print("epoch: {d}\n", .{info.epoch});
    try writer.print("locked: {s}\n", .{if (info.locked) "true" else "false"});
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
    const compiled = try compileSource(allocator, source_path, compile_options);
    switch (compiled) {
        .trap => |report| {
            try printTrapReport(stderr, report, diagnostics_mode);
            return 1;
        },
        .ok => |ok| {
            var owned = ok;
            defer owned.deinit(allocator);
            const ll = try emit_llvm.emitLlvm(allocator, owned.verified, &owned.flat.def_dict, owned.flat.loc_table, source_path, nativeSizeBits(), .{ .debug = debug, .jobs = compile_options.jobs });
            defer allocator.free(ll);

            const ll_path = try std.fmt.allocPrint(allocator, "{s}.saasm.ll", .{out_path});
            defer allocator.free(ll_path);
            try writeAllFile(ll_path, ll);

            const extra_inputs = &[_][]const u8{
                try pluginSoPath(allocator, "libsaasm-http-client.so"),
                try pluginSoPath(allocator, "libsaasm-http-server.so"),
            };
            defer allocator.free(extra_inputs[0]);
            defer allocator.free(extra_inputs[1]);
            driver.compileExe(allocator, ll_path, out_path, optimization, build_options.sa_std_archive_path, extra_inputs[0..], debug, stderr) catch |err| switch (err) {
                error.ChildProcessFailed => return 1,
                else => return err,
            };
            try ensurePluginSoAvailable(allocator, out_path, "libsaasm-http-client.so");
            try ensurePluginSoAvailable(allocator, out_path, "libsaasm-http-server.so");
            if (diagnostics_mode == .json) {
                try writeSuccessJson(stderr, owned.metrics);
            }
            return 0;
        },
    }
}

fn executeBuildObj(allocator: std.mem.Allocator, source_path: []const u8, out_path: []const u8, debug: bool, optimization: driver.Optimization, compile_options: CompileOptions, stderr: anytype, diagnostics_mode: DiagnosticsMode) !u8 {
    const compiled = try compileSource(allocator, source_path, compile_options);
    switch (compiled) {
        .trap => |report| {
            try printTrapReport(stderr, report, diagnostics_mode);
            return 1;
        },
        .ok => |ok| {
            var owned = ok;
            defer owned.deinit(allocator);
            const ll = try emit_llvm.emitLlvm(allocator, owned.verified, &owned.flat.def_dict, owned.flat.loc_table, source_path, nativeSizeBits(), .{ .debug = debug, .jobs = compile_options.jobs });
            defer allocator.free(ll);

            const ll_path = try std.fmt.allocPrint(allocator, "{s}.saasm.ll", .{out_path});
            defer allocator.free(ll_path);
            try writeAllFile(ll_path, ll);

            driver.compileObj(allocator, ll_path, out_path, optimization, debug, stderr) catch |err| switch (err) {
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
            const ll = try emit_llvm.emitLlvm(allocator, owned.verified, &owned.flat.def_dict, owned.flat.loc_table, source_path, target.size_bits, .{ .debug = debug, .wasm_compat = true, .jobs = compile_options.jobs });
            defer allocator.free(ll);

            const ll_path = try std.fmt.allocPrint(allocator, "{s}.saasm.ll", .{out_path});
            defer allocator.free(ll_path);
            try writeAllFile(ll_path, ll);

            driver.compileWasm(allocator, ll_path, out_path, .{ .triple = target.triple, .no_entry = target.no_entry }, optimization, debug, stderr) catch |err| switch (err) {
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
) !u8 {
    var compile_options: CompileOptions = .{};
    var source_arg: ?[]const u8 = null;
    var i: usize = 0;
    while (i < args.len) : (i += 1) {
        const arg = args[i];
        if (try consumeJobsOption(arg, args, &i, &compile_options)) continue;
        if (std.mem.eql(u8, arg, "--offline")) {
            compile_options.offline = true;
            continue;
        }
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

            var project_manifest = try readProjectManifest(allocator, compile_options.project_root orelse projectRootFromSourcePath(source_path));
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
                .project_root = compile_options.project_root orelse projectRootFromSourcePath(source_path),
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
) !u8 {
    var compile_options: CompileOptions = .{};
    var source_arg: ?[]const u8 = null;
    var i: usize = 0;
    while (i < args.len) : (i += 1) {
        const arg = args[i];
        if (try consumeJobsOption(arg, args, &i, &compile_options)) continue;
        if (std.mem.eql(u8, arg, "--offline")) {
            compile_options.offline = true;
            continue;
        }
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

            const ll = try emit_llvm.emitLlvm(
                allocator,
                owned.verified,
                &owned.flat.def_dict,
                owned.flat.loc_table,
                source_path,
                nativeSizeBits(),
                .{ .jobs = compile_options.jobs, .test_mode = true },
            );
            defer allocator.free(ll);

            var tmp = try TmpWorkDir.init();
            defer tmp.cleanup();

            const source_stem = sourceStem(source_path);
            const ll_name = try std.fmt.allocPrint(allocator, "{s}.test.saasm.ll", .{source_stem});
            defer allocator.free(ll_name);
            const exe_name = try std.fmt.allocPrint(allocator, "{s}.test", .{source_stem});
            defer allocator.free(exe_name);

            const ll_path = try tmp.dir.realpathAlloc(allocator, ".");
            defer allocator.free(ll_path);

            const ll_full_path = try std.fs.path.join(allocator, &.{ ll_path, ll_name });
            defer allocator.free(ll_full_path);
            try writeFile(tmp.dir, ll_name, ll);

            const exe_full_path = try std.fs.path.join(allocator, &.{ ll_path, exe_name });
            defer allocator.free(exe_full_path);

            const extra_inputs = &[_][]const u8{
                try pluginSoPath(allocator, "libsaasm-http-client.so"),
                try pluginSoPath(allocator, "libsaasm-http-server.so"),
            };
            defer allocator.free(extra_inputs[0]);
            defer allocator.free(extra_inputs[1]);
            driver.compileExe(allocator, ll_full_path, exe_full_path, .release_small, build_options.sa_std_archive_path, extra_inputs[0..], false, stderr) catch |err| switch (err) {
                error.ChildProcessFailed => return 1,
                else => return err,
            };
            try ensurePluginSoAvailable(allocator, exe_full_path, "libsaasm-http-client.so");
            try ensurePluginSoAvailable(allocator, exe_full_path, "libsaasm-http-server.so");

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

pub fn executeWithWriters(allocator: std.mem.Allocator, argv: []const []const u8, stdout: anytype, stderr: anytype) !u8 {
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
        if (std.mem.eql(u8, args[1], commandName(.build_exe))) break :blk .build_exe;
        if (std.mem.eql(u8, args[1], commandName(.build_wasm))) break :blk .build_wasm;
        if (std.mem.eql(u8, args[1], commandName(.build_obj))) break :blk .build_obj;
        if (std.mem.eql(u8, args[1], commandName(.llvm2sa))) break :blk .llvm2sa;
        if (std.mem.eql(u8, args[1], commandName(.sax))) break :blk .sax;
        if (std.mem.eql(u8, args[1], commandName(.audit))) break :blk .audit;
        if (std.mem.eql(u8, args[1], commandName(.graph))) break :blk .graph;
        if (std.mem.eql(u8, args[1], commandName(.db))) break :blk .db;
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
            return try executeGraph(allocator, args[2..], stdout, stderr, json_mode);
        },
        .audit => {
            const audit_argv = args[2..];
            if (audit_argv.len == 0) return error.MissingSourcePath;
            const source_path = audit_argv[0];
            const source = try loadSource(allocator, source_path);
            defer allocator.free(source);
            try stdout.print("audit: {s}\n", .{source_path});
            try stdout.print("size: {d}\n", .{source.len});
            return 0;
        },
        .explain => return try explainCommand(stdout, args, json_mode),
        .fix => return try fixCommand(stdout, args, json_mode),
        .skills => return try skillsCommand(stdout, json_mode),
        .build => {
            if (args.len < 3) return error.MissingSourcePath;
            const source_path = args[2];
            var compile_options: CompileOptions = .{};
            var out_path: ?[]const u8 = null;
            var debug = false;
            var optimization: driver.Optimization = .release_small;
            var i: usize = 3;
            while (i < args.len) : (i += 1) {
                if (try consumeJobsOption(args[i], args, &i, &compile_options)) continue;
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
        .sax => {
            if (args.len < 3) return error.MissingSourcePath;
            const sub = args[2];
            if (sax_cli.parseSaxCommand(sub)) |sax_cmd| {
                switch (sax_cmd) {
                    .build => {
                        const sax_file = if (args.len >= 4) args[3] else return error.MissingSourcePath;
                        return try sax_cli.executeSaxBuild(allocator, sax_file, null, stdout, stderr);
                    },
                    .check => {
                        const sax_file = if (args.len >= 4) args[3] else return error.MissingSourcePath;
                        return try sax_cli.executeSaxCheck(allocator, sax_file, stdout, stderr);
                    },
                    .dev => {
                        const sax_file = if (args.len >= 4) args[3] else return error.MissingSourcePath;
                        return try sax_cli.executeSaxDev(allocator, sax_file, 8080, stdout, stderr);
                    },
                    .new_project => {
                        const project_name = if (args.len >= 4) args[3] else return error.MissingSourcePath;
                        return try sax_cli.executeSaxNew(allocator, project_name, stdout, stderr);
                    },
                }
            }
            return error.UnknownCommand;
        },
        .fetch => {
            var result = try pkg_fetch.fetchPackage(allocator, args[2], "HEAD", .{});
            defer result.deinit(allocator);
            try stdout.print("{s}\n", .{result.root});
            return 0;
        },
        .size => {
            return try executeSize(allocator, args[2..], stdout, stderr, json_mode);
        },
        .db => {
            if (args.len < 3) return error.UnknownCommand;
            const sub = args[2];
            if (std.mem.eql(u8, sub, "init")) {
                if (args.len < 4) return error.MissingSourcePath;
                const iface = db.exec.compileSchema(allocator, args[3]) catch |err| {
                    try printCliError(stderr, err, if (json_mode) .json else .human);
                    return 1;
                };
                defer allocator.free(iface);
                const iface_path = db.schema.ifaceFilePath(allocator, args[3]) catch |err| {
                    try printCliError(stderr, err, if (json_mode) .json else .human);
                    return 1;
                };
                defer allocator.free(iface_path);
                writeTextFile(allocator, iface_path, iface) catch |err| {
                    try printCliError(stderr, err, if (json_mode) .json else .human);
                    return 1;
                };
                try stdout.print("{s}\n", .{iface_path});
                return 0;
            }
            if (std.mem.eql(u8, sub, "register")) {
                if (args.len < 4) return error.MissingSourcePath;
                const source_path = args[3];
                const abs_source_path = try std.fs.cwd().realpathAlloc(allocator, source_path);
                defer allocator.free(abs_source_path);
                const project_root = std.fs.path.dirname(abs_source_path) orelse ".";
                var result = db.exec.registerQuery(allocator, abs_source_path, project_root) catch |err| {
                    try printCliError(stderr, err, if (json_mode) .json else .human);
                    return 1;
                };
                defer result.deinit(allocator);
                const hex = std.fmt.bytesToHex(result.hash, .lower);
                try stdout.print("Compiled: {s}\n", .{source_path});
                try stdout.print("Hash: {s}\n", .{hex[0..]});
                try stdout.print("Registered: {s}\n", .{std.fs.path.basename(result.qmod_path)});
                return 0;
            }
            if (std.mem.eql(u8, sub, "inspect")) {
                if (args.len < 4) return error.MissingSourcePath;
                const root_dir = try std.fs.cwd().realpathAlloc(allocator, ".");
                defer allocator.free(root_dir);
                const report = db.exec.inspectRegistry(allocator, root_dir, args[3]) catch |err| {
                    try printCliError(stderr, err, if (json_mode) .json else .human);
                    return 1;
                };
                defer allocator.free(report);
                try stdout.writeAll(report);
                return 0;
            }
            if (std.mem.eql(u8, sub, "ingest")) {
                if (args.len < 5) return error.MissingSourcePath;
                const info = db.table.ingestTable(allocator, ".", args[3], args[4]) catch |err| {
                    try printCliError(stderr, err, if (json_mode) .json else .human);
                    return 1;
                };
                try printTableInfo(stdout, info);
                return 0;
            }
            if (std.mem.eql(u8, sub, "snapshot")) {
                if (args.len < 4) return error.MissingSourcePath;
                const info = db.table.snapshotTable(allocator, ".", args[3]) catch |err| {
                    try printCliError(stderr, err, if (json_mode) .json else .human);
                    return 1;
                };
                try printTableInfo(stdout, info);
                return 0;
            }
            if (std.mem.eql(u8, sub, "restore")) {
                if (args.len < 5) return error.MissingSourcePath;
                const epoch = std.fmt.parseInt(u64, args[4], 10) catch return error.InvalidPath;
                const info = db.table.restoreTable(allocator, ".", args[3], epoch) catch |err| {
                    try printCliError(stderr, err, if (json_mode) .json else .human);
                    return 1;
                };
                try printTableInfo(stdout, info);
                return 0;
            }
            if (std.mem.eql(u8, sub, "verify")) {
                if (args.len < 4) return error.MissingSourcePath;
                const info = db.table.verifyTable(allocator, ".", args[3]) catch |err| {
                    try printCliError(stderr, err, if (json_mode) .json else .human);
                    return 1;
                };
                try printTableInfo(stdout, info);
                return 0;
            }
            if (std.mem.eql(u8, sub, "lock")) {
                if (args.len < 4) return error.MissingSourcePath;
                const info = db.table.lockTable(allocator, ".", args[3]) catch |err| {
                    try printCliError(stderr, err, if (json_mode) .json else .human);
                    return 1;
                };
                try printTableInfo(stdout, info);
                return 0;
            }
            if (std.mem.eql(u8, sub, "compact")) {
                if (args.len < 4) return error.MissingSourcePath;
                const info = db.table.compactTable(allocator, ".", args[3]) catch |err| {
                    try printCliError(stderr, err, if (json_mode) .json else .human);
                    return 1;
                };
                try printTableInfo(stdout, info);
                return 0;
            }
            if (std.mem.eql(u8, sub, "exec")) {
                if (args.len < 4) return error.MissingSourcePath;
                var params_path: ?[]const u8 = null;
                var i: usize = 4;
                while (i < args.len) : (i += 1) {
                    if (std.mem.eql(u8, args[i], "--params")) {
                        if (i + 1 >= args.len) return error.MissingSourcePath;
                        params_path = args[i + 1];
                        i += 1;
                        continue;
                    }
                    if (params_path == null) {
                        params_path = args[i];
                        continue;
                    }
                    return error.UnexpectedArgument;
                }
                const root_dir = try std.fs.cwd().realpathAlloc(allocator, ".");
                defer allocator.free(root_dir);
                const abs_params_path = if (params_path) |path| try std.fs.cwd().realpathAlloc(allocator, path) else null;
                defer if (abs_params_path) |path| allocator.free(path);
                var exec_result = db.exec.execQuery(allocator, root_dir, args[3], abs_params_path, stdout.any(), stderr.any()) catch |err| {
                    try printCliError(stderr, err, if (json_mode) .json else .human);
                    return 1;
                };
                defer exec_result.deinit(allocator);
                switch (exec_result) {
                    .trap => |report| {
                        const converted = convertDbTrapReport(report);
                        std.debug.print("cli db exec trap={s}\n", .{trap.trapName(converted.trap)});
                        try printTrapReport(stderr, converted, if (json_mode) .json else .human);
                        return 1;
                    },
                    .ok => |result| {
                        std.debug.print("cli db exec ok code={d}\n", .{result.code});
                        return result.code;
                    },
                }
            }
            return error.UnknownCommand;
        },
        .run => {
            if (args.len < 3) return error.MissingSourcePath;
            var compile_options: CompileOptions = .{};
            var source_path: ?[]const u8 = null;
            var runtime_args = std.ArrayList([]const u8).init(allocator);
            defer runtime_args.deinit();

            var i: usize = 2;
            while (i < args.len) : (i += 1) {
                if (try consumeJobsOption(args[i], args, &i, &compile_options)) continue;
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
            var compile_options: CompileOptions = .{};
            var out_path: ?[]const u8 = null;
            var debug = false;
            var optimization: driver.Optimization = .release_small;
            var i: usize = 3;
            while (i < args.len) : (i += 1) {
                if (try consumeJobsOption(args[i], args, &i, &compile_options)) continue;
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
            var compile_options: CompileOptions = .{};
            var out_path: ?[]const u8 = null;
            var debug = false;
            var optimization: driver.Optimization = .release_small;
            var i: usize = 3;
            while (i < args.len) : (i += 1) {
                if (try consumeJobsOption(args[i], args, &i, &compile_options)) continue;
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
            var compile_options: CompileOptions = .{};
            var out_path: ?[]const u8 = null;
            var target: WasmTarget = .{ .triple = "wasm32-wasi", .no_entry = false, .size_bits = 32 };
            var debug = false;
            var optimization: driver.Optimization = .release_small;
            var i: usize = 3;
            while (i < args.len) : (i += 1) {
                if (try consumeJobsOption(args[i], args, &i, &compile_options)) continue;
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
        .llvm2sa => {
            if (args.len < 3) return error.MissingSourcePath;
            const source_path = args[2];
            const translated = try llvm2sa.translateFile(allocator, source_path);
            defer allocator.free(translated);
            try stdout.writeAll(translated);
            if (translated.len == 0 or translated[translated.len - 1] != '\n') try stdout.writeByte('\n');
            return 0;
        },
        .test_cmd => {
            if (args.len < 3) return error.MissingSourcePath;
            const source_path = args[2];
            var compile_options: CompileOptions = .{};
            var include_filters = std.ArrayList([]const u8).init(allocator);
            defer include_filters.deinit();
            var skip_filters = std.ArrayList([]const u8).init(allocator);
            defer skip_filters.deinit();
            var exact = false;
            var run_ignored = test_meta.RunIgnored.normal;
            var i: usize = 3;
            while (i < args.len) : (i += 1) {
                if (try consumeJobsOption(args[i], args, &i, &compile_options)) continue;
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
        \\@import "missing.saasm"
        \\@main() -> i32:
        \\    return 0
    ;
    const import_report = trapFromFlattenError(import_source, error.PackageNotResolved, 1);
    try std.testing.expectEqual(trap.Trap.import_resolution_failed, import_report.trap);
    try std.testing.expectEqual(@as(u32, 1050), import_report.trap_code.?);
    try std.testing.expectEqualStrings("import path could not be resolved", import_report.message);
    try std.testing.expectEqualStrings("check the import path, package identity, local vendor tree, and package cache", import_report.hint.?);

    const type_source =
        \\@test "probe":
        \\    point = call @support_make_point(10, 20)
    ;
    const type_report = trapFromFlattenError(type_source, error.UnsupportedType, 2);
    try std.testing.expectEqual(trap.Trap.unsupported_type, type_report.trap);
    try std.testing.expectEqualStrings("unsupported type annotation during flattening", type_report.message);
    try std.testing.expectEqualStrings("inspect the callee declaration referenced by this call site; the unsupported annotation is usually in the imported signature", type_report.hint.?);
}
