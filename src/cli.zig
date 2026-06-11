const std = @import("std");
const builtin = @import("builtin");

const flattener = @import("flattener.zig");
const line_classifier = @import("flattener/line_classifier.zig");
const interp = @import("interp.zig");
const build_options = @import("build_options");
const driver = @import("driver/zigcc.zig");
const emit_options = @import("emit_options.zig");
const emit_llvm_llvmc = @import("emit_llvm_llvmc.zig");
const bc2sa = @import("llvm2sa.zig");
const layout = @import("layout.zig");
const plugins = @import("plugins.zig");
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
const test_formatter = @import("test_formatter.zig");
const test_meta = @import("test_meta.zig");
const test_runner = @import("test_runner.zig");
const trap = @import("common/trap.zig");
const common_upstream = @import("common/upstream_loc.zig");

const DceMode = emit_options.DceMode;

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

const BackendIrMetrics = struct {
    functions: u64 = 0,
    blocks: u64 = 0,
    instructions: u64 = 0,
    alloca_slots: u64 = 0,
    loads: u64 = 0,
    stores: u64 = 0,
};

const CompileMetrics = struct {
    compile_tokens: u64,
    instruction_count: u64,
    phases: ?CompilePhaseMetrics = null,
    backend_ir: ?BackendIrMetrics = null,
    cache: ?BuildCacheMetrics = null,
};

const BuildCacheMetrics = struct {
    kind: []const u8,
    hit: bool,
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

fn estimateBackendIrMetrics(verified: *const referee.VerifyOk, debug: bool) BackendIrMetrics {
    var out = BackendIrMetrics{};
    var sig_index: usize = 0;
    for (verified.annotated) |item| {
        switch (item.base.kind) {
            .func_decl, .ffi_wrapper_decl, .extern_decl, .export_decl, .test_decl => {
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

fn attachBackendIrMetrics(metrics: *CompileMetrics, verified: *const referee.VerifyOk, debug: bool) void {
    if (metrics.phases == null) return;
    metrics.backend_ir = estimateBackendIrMetrics(verified, debug);
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
    plugin_import_roots: []const []const u8,
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
            .plugin_import_roots = ctx.plugin_import_roots,
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
    dce: DceMode = .std,
    incremental_cache: bool = true,
    offline: bool = false,
    ci: bool = false,
    allow_unaudited_risks: bool = false,
    auto_approve_requested: bool = false,
    permission_set: ?[]const u8 = null,
    allow_env_requested: bool = false,
    allow_net_requested: bool = false,
    allow_read_requested: bool = false,
    allow_write_requested: bool = false,
    allow_run_requested: bool = false,
    project_root: ?[]const u8 = null,
    profile: bool = false,
    stdin_reader: ?std.io.AnyReader = null,
    stdin_is_tty: ?bool = null,
    diagnostic_writer: ?std.io.AnyWriter = null,
};

const TestCommandOptions = struct {
    selection: test_meta.TestSelection,
    list: bool = false,
    compile_only: bool = false,
    trace_panic: bool = false,
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

const SaStdSurface = struct {
    files: []const []const u8,
    macros: []const []const u8,
    externs: []const []const u8,

    fn deinit(self: SaStdSurface, allocator: std.mem.Allocator) void {
        freeOwnedStringSlice(allocator, self.files);
        freeOwnedStringSlice(allocator, self.macros);
        freeOwnedStringSlice(allocator, self.externs);
    }
};

const SaPluginsSurface = struct {
    root: ?[]const u8,
    plugins: []const []const u8,
    declarations: []const []const u8,
    notes: []const []const u8,

    fn deinit(self: SaPluginsSurface, allocator: std.mem.Allocator) void {
        if (self.root) |root| allocator.free(root);
        freeOwnedStringSlice(allocator, self.plugins);
        freeOwnedStringSlice(allocator, self.declarations);
        freeOwnedStringSlice(allocator, self.notes);
    }
};

const AgentSkillPaths = struct {
    sa_codex: []const u8,
    sa_claude: []const u8,
    plugins_codex: []const u8,
    plugins_claude: []const u8,

    fn deinit(self: AgentSkillPaths, allocator: std.mem.Allocator) void {
        allocator.free(self.sa_codex);
        allocator.free(self.sa_claude);
        allocator.free(self.plugins_codex);
        allocator.free(self.plugins_claude);
    }
};

const OwnedPluginRuntimeAuthorization = struct {
    input: plugins.RuntimeAuthorizationInput = .{},
    env: []const []const u8 = &.{},
    read: []const []const u8 = &.{},
    write: []const []const u8 = &.{},
    net: []const []const u8 = &.{},
    run: []const []const u8 = &.{},
    project_root: ?[]u8 = null,

    fn deinit(self: *OwnedPluginRuntimeAuthorization, allocator: std.mem.Allocator) void {
        for (self.env) |entry| allocator.free(entry);
        allocator.free(self.env);
        for (self.read) |entry| allocator.free(entry);
        allocator.free(self.read);
        for (self.write) |entry| allocator.free(entry);
        allocator.free(self.write);
        for (self.net) |entry| allocator.free(entry);
        allocator.free(self.net);
        for (self.run) |entry| allocator.free(entry);
        allocator.free(self.run);
        if (self.project_root) |root| allocator.free(root);
        self.* = undefined;
    }
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
    plugin,
    pkg,
    cache,
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

fn readManifestTextFileAlloc(allocator: std.mem.Allocator, path: []const u8) ![]u8 {
    var file = try std.fs.cwd().openFile(path, .{});
    defer file.close();
    return try file.readToEndAlloc(allocator, manifest.max_manifest_bytes);
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
    const source = try readManifestTextFileAlloc(allocator, path);
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

fn hashFileHex(allocator: std.mem.Allocator, path: []const u8) ![64]u8 {
    _ = allocator;
    var file = try std.fs.cwd().openFile(path, .{});
    defer file.close();
    return try hashOpenFileHex(&file);
}

fn hashDirFileHex(dir: std.fs.Dir, name: []const u8) ![64]u8 {
    var file = try dir.openFile(name, .{});
    defer file.close();
    return try hashOpenFileHex(&file);
}

fn hashOpenFileHex(file: *std.fs.File) ![64]u8 {
    var hasher = std.crypto.hash.sha2.Sha256.init(.{});
    var buf: [8192]u8 = undefined;
    while (true) {
        const n = try file.read(&buf);
        if (n == 0) break;
        hasher.update(buf[0..n]);
    }
    var out: [32]u8 = undefined;
    hasher.final(&out);
    return sourceHashHex(out);
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
        .plugin => "plugin",
        .pkg => "pkg",
        .cache => "cache",
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

fn commandFromName(name: []const u8) ?Command {
    inline for (std.meta.fields(Command)) |field| {
        const cmd: Command = @enumFromInt(field.value);
        if (std.mem.eql(u8, name, commandName(cmd))) return cmd;
    }
    return null;
}

fn commandSupported(name: []const u8) bool {
    return commandFromName(name) != null;
}

fn isHelpFlag(arg: []const u8) bool {
    return std.mem.eql(u8, arg, "--help") or std.mem.eql(u8, arg, "-h");
}

fn commandHelpRequested(cmd: Command, args: []const []const u8) bool {
    if (args.len < 3) return false;
    if (isHelpFlag(args[2])) return true;
    return switch (cmd) {
        .pkg, .plugin, .cache => args.len >= 4 and isHelpFlag(args[3]),
        else => false,
    };
}

fn writeCompileOptionsHelp(writer: anytype) !void {
    try writer.writeAll("  --jobs auto|N                  Set parallel compile jobs\n");
    try writer.writeAll("  --dce no|std|full              Select dead-code elimination level\n");
    try writer.writeAll("  --no-incremental               Disable the default project build cache\n");
    try writer.writeAll("  --profile                      Include compile phase timings in JSON metrics\n");
    try writer.writeAll("  --offline                      Use local package cache only\n");
    try writer.writeAll("  --ci                           Use CI package preflight behavior\n");
    try writer.writeAll("  --allow-unaudited-risks        Allow high-risk package audit findings\n");
    try writer.writeAll("  --yes, --auto-approve          Approve package review prompts when allowed\n");
    try writer.writeAll("  -P, --permission-set <name>    Select a named permission set\n");
    try writer.writeAll("  --allow-env[=list]             Allow environment access for reviewed packages\n");
    try writer.writeAll("  --allow-net[=list]             Allow network access for reviewed packages\n");
    try writer.writeAll("  --allow-read[=list]            Allow filesystem reads for reviewed packages\n");
    try writer.writeAll("  --allow-write[=list]           Allow filesystem writes for reviewed packages\n");
    try writer.writeAll("  --allow-run[=list]             Allow process execution for reviewed packages\n");
}

fn writeBuildOptionsHelp(writer: anytype, artifact: []const u8, include_incremental: bool) !void {
    try writer.print("  -o <path>                      Write {s} to path\n", .{artifact});
    try writer.writeAll("  -g                             Include debug information\n");
    try writer.writeAll("  --no-debug                     Disable debug information\n");
    try writer.writeAll("  --release-small                Optimize for small release output\n");
    try writer.writeAll("  --release-fast                 Optimize for fast release output\n");
    if (include_incremental) try writer.writeAll("  --incremental                  Reuse per-function cached objects when building .o\n");
    try writeCompileOptionsHelp(writer);
}

fn printPkgHelp(writer: anytype, args: []const []const u8) !void {
    const sub = if (args.len != 0 and !isHelpFlag(args[0])) args[0] else "";
    if (std.mem.eql(u8, sub, "install")) {
        try writer.writeAll("usage: sa pkg install [options] [identity]\n\n");
        try writer.writeAll("Fetch project dependencies from sa.mod, or fetch one package identity.\n\n");
        try writer.writeAll("Options:\n");
        try writer.writeAll("  --offline                      Use local package cache only\n");
        try writer.writeAll("  -g                             Install into the global package cache\n");
        try writer.writeAll("  --ref <ref>                    Fetch a specific package ref\n");
        try writer.writeAll("  -h, --help                     Show this help message\n");
        return;
    }
    if (std.mem.eql(u8, sub, "fetch")) {
        try writer.writeAll("usage: sa pkg fetch [options] <identity>\n\n");
        try writer.writeAll("Fetch and cache one package identity.\n\n");
        try writer.writeAll("Options:\n");
        try writer.writeAll("  --offline                      Use local package cache only\n");
        try writer.writeAll("  -g                             Install into the global package cache\n");
        try writer.writeAll("  --ref <ref>                    Fetch a specific package ref\n");
        try writer.writeAll("  -h, --help                     Show this help message\n");
        return;
    }
    if (std.mem.eql(u8, sub, "audit")) {
        try writer.writeAll("usage: sa pkg audit [options] <identity>\n\n");
        try writer.writeAll("Audit a package source tree and report required capabilities.\n\n");
        try writer.writeAll("Options:\n");
        try writer.writeAll("  --format text|json             Select report format\n");
        try writer.writeAll("  --json                         Emit JSON report\n");
        try writer.writeAll("  --ci                           Fail on CI policy violations\n");
        try writer.writeAll("  --allow-unaudited-risks        Allow high-risk audit findings\n");
        try writer.writeAll("  --update-lock                  Update project package lock metadata\n");
        try writer.writeAll("  --ref <ref>                    Audit a specific package ref\n");
        try writer.writeAll("  -h, --help                     Show this help message\n");
        return;
    }

    try writer.writeAll("usage: sa pkg <install|fetch|audit> [options]\n\n");
    try writer.writeAll("Package fetch, audit, install, and lock commands.\n\n");
    try writer.writeAll("Subcommands:\n");
    try writer.writeAll("  install                        Fetch project dependencies or one identity\n");
    try writer.writeAll("  fetch                          Fetch and cache one identity\n");
    try writer.writeAll("  audit                          Audit package capabilities and risk\n");
    try writer.writeAll("\nUse `sa pkg <subcommand> --help` for subcommand options.\n");
}

fn printCacheHelp(writer: anytype, args: []const []const u8) !void {
    const sub = if (args.len != 0 and !isHelpFlag(args[0])) args[0] else "";
    if (std.mem.eql(u8, sub, "clean")) {
        try writer.writeAll("usage: sa cache clean [options]\n\n");
        try writer.writeAll("Remove invalid, incomplete, or expired project cache entries from .sa_cache.\n\n");
        try writer.writeAll("Options:\n");
        try writer.writeAll("  --dry-run                      Report removals without deleting files\n");
        try writer.writeAll("  --max-age-days <n>             Remove complete entries older than n days (default: 30)\n");
        try writer.writeAll("  -h, --help                     Show this help message\n");
        return;
    }

    try writer.writeAll("usage: sa cache <clean> [options]\n\n");
    try writer.writeAll("Inspect and clean project-local SA build/test caches.\n\n");
    try writer.writeAll("Subcommands:\n");
    try writer.writeAll("  clean                          Remove invalid or expired .sa_cache entries\n");
    try writer.writeAll("\nUse `sa cache <subcommand> --help` for subcommand options.\n");
}

fn printPluginHelp(writer: anytype, args: []const []const u8) !void {
    const sub = if (args.len != 0 and !isHelpFlag(args[0])) args[0] else "";
    if (std.mem.eql(u8, sub, "install")) {
        try writer.writeAll("usage: sa plugin install [--dev] [--review] <path|sap.json>\n\n");
        try writer.writeAll("Build, verify, and install a native SA plugin project.\n\n");
        try writer.writeAll("Options:\n");
        try writer.writeAll("  --dev                          Allow development-mode install checks\n");
        try writer.writeAll("  --review                       Force review output before install\n");
        try writer.writeAll("  -h, --help                     Show this help message\n");
        return;
    }
    if (std.mem.eql(u8, sub, "list")) {
        try writer.writeAll("usage: sa plugin list\n\n");
        try writer.writeAll("List installed native SA plugins.\n\n");
        try writer.writeAll("Options:\n");
        try writer.writeAll("  -h, --help                     Show this help message\n");
        return;
    }

    try writer.writeAll("usage: sa plugin <install|list> [options]\n\n");
    try writer.writeAll("Install and list native SA plugins.\n\n");
    try writer.writeAll("Subcommands:\n");
    try writer.writeAll("  install                        Install a plugin project or sap.json\n");
    try writer.writeAll("  list                           List installed plugins\n");
    try writer.writeAll("\nUse `sa plugin <subcommand> --help` for subcommand options.\n");
}

fn printCommandHelp(writer: anytype, cmd: Command, args: []const []const u8) !void {
    switch (cmd) {
        .init => {
            try writer.writeAll("usage: sa init [path]\n\n");
            try writer.writeAll("Create a new SA binary project.\n\n");
            try writer.writeAll("Options:\n");
            try writer.writeAll("  -h, --help                     Show this help message\n");
        },
        .install => {
            try writer.writeAll("usage: sa install [options] [identity]\n\n");
            try writer.writeAll("Install project dependencies or one package identity. This is a compatibility alias for package install behavior.\n\n");
            try writer.writeAll("Options:\n");
            try writer.writeAll("  --offline                      Use local package cache only\n");
            try writer.writeAll("  -g                             Install into the global package cache\n");
            try writer.writeAll("  --ref <ref>                    Fetch a specific package ref\n");
            try writer.writeAll("  -h, --help                     Show this help message\n");
        },
        .plugin => try printPluginHelp(writer, args),
        .pkg => try printPkgHelp(writer, args),
        .cache => try printCacheHelp(writer, args),
        .build => {
            try writer.writeAll("usage: sa build <file> [options]\n\n");
            try writer.writeAll("Compile a .sa source file to a native executable.\n\n");
            try writer.writeAll("Options:\n");
            try writeBuildOptionsHelp(writer, "the executable", false);
            try writer.writeAll("  -h, --help                     Show this help message\n");
        },
        .build_exe => {
            try writer.writeAll("usage: sa build-exe <file> [options]\n\n");
            try writer.writeAll("Build a standalone native executable. This is an alias for `sa build`.\n\n");
            try writer.writeAll("Options:\n");
            try writeBuildOptionsHelp(writer, "the executable", false);
            try writer.writeAll("  -h, --help                     Show this help message\n");
        },
        .build_obj => {
            try writer.writeAll("usage: sa build-obj <file> [options]\n\n");
            try writer.writeAll("Build a native object file from a .sa source file.\n\n");
            try writer.writeAll("Options:\n");
            try writeBuildOptionsHelp(writer, "the object file", true);
            try writer.writeAll("  -h, --help                     Show this help message\n");
        },
        .build_wasm => {
            try writer.writeAll("usage: sa build-wasm <file> [options]\n\n");
            try writer.writeAll("Build a WebAssembly module from a .sa source file.\n\n");
            try writer.writeAll("Options:\n");
            try writer.writeAll("  --target wasm32|wasm64         Select the WebAssembly target\n");
            try writeBuildOptionsHelp(writer, "the wasm module", false);
            try writer.writeAll("  -h, --help                     Show this help message\n");
        },
        .run => {
            try writer.writeAll("usage: sa run <file> [compile-options] [args...]\n\n");
            try writer.writeAll("Compile and execute a .sa source file.\n\n");
            try writer.writeAll("Options:\n");
            try writeCompileOptionsHelp(writer);
            try writer.writeAll("  -h, --help                     Show this help message\n");
        },
        .fetch => {
            try writer.writeAll("usage: sa fetch <identity>\n\n");
            try writer.writeAll("Fetch and cache a remote package. This is a compatibility alias; prefer `sa pkg fetch`.\n\n");
            try writer.writeAll("Options:\n");
            try writer.writeAll("  -h, --help                     Show this help message\n");
        },
        .audit => {
            try writer.writeAll("usage: sa audit <identity>\n\n");
            try writer.writeAll("Compatibility alias for package audit. Prefer `sa pkg audit <identity>`.\n\n");
            try writer.writeAll("Options:\n");
            try writer.writeAll("  -h, --help                     Show this help message\n");
        },
        .graph => {
            try writer.writeAll("usage: sa graph [path] [options]\n\n");
            try writer.writeAll("Output a dependency and call graph for a source file or project.\n\n");
            try writer.writeAll("Options:\n");
            try writer.writeAll("  --json                         Emit graph JSON\n");
            try writeCompileOptionsHelp(writer);
            try writer.writeAll("  -h, --help                     Show this help message\n");
        },
        .layout => {
            try writer.writeAll("usage: sa layout --name <TypeName> --fields <name:ty,...> [options]\n\n");
            try writer.writeAll("Compute and print struct layout information.\n\n");
            try writer.writeAll("Options:\n");
            try writer.writeAll("  --name <TypeName>              Struct/type name to display\n");
            try writer.writeAll("  --fields <name:ty,...>         Comma-separated field list\n");
            try writer.writeAll("  --format text|json|debug|dict  Select output format\n");
            try writer.writeAll("  --target 32|64                 Select pointer width\n");
            try writer.writeAll("  -h, --help                     Show this help message\n");
        },
        .size => {
            try writer.writeAll("usage: sa size [path] [options]\n\n");
            try writer.writeAll("Print function size statistics for a source file or project.\n\n");
            try writer.writeAll("Options:\n");
            try writer.writeAll("  --json                         Emit size data as JSON\n");
            try writeCompileOptionsHelp(writer);
            try writer.writeAll("  -h, --help                     Show this help message\n");
        },
        .test_cmd => {
            try writer.writeAll("usage: sa test <file> [options]\n\n");
            try writer.writeAll("Run @test blocks in a .sa source file.\n\n");
            try writer.writeAll("Options:\n");
            try writer.writeAll("  --list                         List selected tests after frontend checks only\n");
            try writer.writeAll("  --compile-only                 Compile and link tests without running them\n");
            try writer.writeAll("  --trace-panic                  Include panic diagnostics on failed tests\n");
            try writer.writeAll("  --test-debug                   Alias for --trace-panic\n");
            try writer.writeAll("  --filter <pattern>             Include only matching tests (repeatable)\n");
            try writer.writeAll("  --skip <pattern>               Exclude matching tests (repeatable)\n");
            try writer.writeAll("  --exact                        Match test names exactly\n");
            try writer.writeAll("  --ignored                      Run only ignored tests\n");
            try writer.writeAll("  --include-ignored              Run all tests including ignored\n");
            try writeCompileOptionsHelp(writer);
            try writer.writeAll("  -h, --help                     Show this help message\n");
        },
        .bc2sa => {
            try writer.writeAll("usage: sa bc2sa <file.bc>\n\n");
            try writer.writeAll("Translate LLVM bitcode to SA assembly.\n\n");
            try writer.writeAll("Options:\n");
            try writer.writeAll("  -h, --help                     Show this help message\n");
        },
        .explain => {
            try writer.writeAll("usage: sa explain <code>\n\n");
            try writer.writeAll("Explain a diagnostic error code.\n\n");
            try writer.writeAll("Options:\n");
            try writer.writeAll("  --json                         Emit explanation as JSON\n");
            try writer.writeAll("  -h, --help                     Show this help message\n");
        },
        .fix => {
            try writer.writeAll("usage: sa fix [--plan] <code>\n\n");
            try writer.writeAll("Suggest fixes for diagnostics.\n\n");
            try writer.writeAll("Options:\n");
            try writer.writeAll("  --plan                         Print a deterministic fix plan\n");
            try writer.writeAll("  --json                         Emit fix plan as JSON\n");
            try writer.writeAll("  -h, --help                     Show this help message\n");
        },
        .skills => {
            try writer.writeAll("usage: sa skills [--json]\n\n");
            try writer.writeAll("List compiler and plugin skills/capabilities. Text mode also writes agent skills into the current directory.\n");
            try writer.writeAll("The generated SA skill scans the current sa_std root and records every .sa/.sal/.sai macro and extern/export declaration.\n\n");
            try writer.writeAll("Options:\n");
            try writer.writeAll("  --json                         Emit skills as JSON\n");
            try writer.writeAll("  -h, --help                     Show this help message\n");
        },
        .help => {
            try writer.writeAll("usage: sa help [command]\n\n");
            try writer.writeAll("Show global help or help for one command.\n\n");
            try writer.writeAll("Examples:\n");
            try writer.writeAll("  sa help test\n");
            try writer.writeAll("  sa help pkg audit\n");
            try writer.writeAll("  sa test --help\n");
        },
        .version => {
            try writer.writeAll("usage: sa version\n\n");
            try writer.writeAll("Print the SA toolchain version.\n\n");
            try writer.writeAll("Options:\n");
            try writer.writeAll("  --version                      Print version and exit\n");
            try writer.writeAll("  -h, --help                     Show this help message\n");
        },
    }
}

fn printHelpTopic(writer: anytype, args: []const []const u8) !u8 {
    if (args.len == 0) {
        try printUsage(writer);
        return 0;
    }
    if (isHelpFlag(args[0])) {
        try printCommandHelp(writer, .help, &.{});
        return 0;
    }
    const cmd = commandFromName(args[0]) orelse {
        try writer.print("unknown help topic: {s}\n", .{args[0]});
        return 1;
    };
    try printCommandHelp(writer, cmd, args[1..]);
    return 0;
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
    try writer.writeAll("  pkg          <subcommand>      Package fetch, audit, install, and lock commands\n");
    try writer.writeAll("  plugin       <subcommand>      Install and list native SA plugins\n");
    try writer.writeAll("  cache        <subcommand>      Inspect and clean project-local caches\n");
    try writer.writeAll("  install      [identity]        Install project dependencies or one package (compat)\n");
    try writer.writeAll("  build        <file>            Compile a .sa source to a native executable\n");
    try writer.writeAll("  run          <file>            Compile and immediately execute a .sa file\n");
    try writer.writeAll("  build-exe    <file>            Build a standalone executable (alias for build)\n");
    try writer.writeAll("  build-obj    <file>            Build an object file (.o)\n");
    try writer.writeAll("  build-wasm   <file>            Build a WebAssembly module (.wasm)\n");
    try writer.writeAll("  test         <file>            Run @test blocks in a .sa file\n");
    try writer.writeAll("  fetch        <url>             Fetch and cache a remote package (compat)\n");
    try writer.writeAll("  audit        <file>            Use `sa pkg audit` from the package plugin\n");
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
    try writer.writeAll("  --dce no|std|full              Select dead-code elimination level\n");
    try writer.writeAll("  --no-incremental               Disable the default project build cache\n");
    try writer.writeAll("  -h, --help                     Show this help message\n");
    try writer.writeAll("  --version                      Print version and exit\n");
    try writer.writeAll("\nTest flags:\n");
    try writer.writeAll("  --list                         List selected tests after frontend checks only\n");
    try writer.writeAll("  --compile-only                 Compile and link tests without running them\n");
    try writer.writeAll("  --trace-panic                  Include panic diagnostics on failed tests\n");
    try writer.writeAll("  --test-debug                   Alias for --trace-panic\n");
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
        self.parent_dir.deleteTree(&self.sub_path) catch |err| {
            // Temporary build directories are best-effort cleanup after the caller has finished using them.
            _ = @errorName(err);
        };
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
    while (idx < report.context.len and line_no <= center_line + 2) : ({
        idx += 1;
        line_no += 1;
    }) {
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
        error.MissingDceMode => .{
            .code = "SA-CLI-020",
            .message = "missing DCE mode after --dce",
            .hint = "use --dce no, --dce std, or --dce full",
        },
        error.InvalidDceMode => .{
            .code = "SA-CLI-021",
            .message = "invalid DCE mode",
            .hint = "use --dce no, --dce std, or --dce full",
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
        error.StaticMemoryOverflow => .{
            .code = "SA-CLI-019",
            .message = "static memory overflow detected in LLVM bitcode",
            .hint = "reduce the constant GEP/index offset or widen the fixed-size array before translating",
        },
        error.UnknownCommand => .{
            .code = "SA-CLI-013",
            .message = "unknown command",
            .hint = "use build, run, build-exe, build-wasm, build-obj, pkg, cache, graph, layout, size, test, explain, fix, skills, bc2sa, help, or version",
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
    if (metrics.backend_ir) |ir| {
        try writer.writeAll(",\"backend\":{\"ir\":{");
        try writer.writeAll("\"functions\":");
        try writer.print("{d}", .{ir.functions});
        try writer.writeAll(",\"blocks\":");
        try writer.print("{d}", .{ir.blocks});
        try writer.writeAll(",\"instructions\":");
        try writer.print("{d}", .{ir.instructions});
        try writer.writeAll(",\"alloca_slots\":");
        try writer.print("{d}", .{ir.alloca_slots});
        try writer.writeAll(",\"loads\":");
        try writer.print("{d}", .{ir.loads});
        try writer.writeAll(",\"stores\":");
        try writer.print("{d}", .{ir.stores});
        try writer.writeAll("}}");
    }
    if (metrics.cache) |cache| {
        try writer.writeAll(",\"cache\":{");
        try writer.writeAll("\"kind\":");
        try writeJsonString(writer, cache.kind);
        try writer.writeAll(",\"hit\":");
        try writer.writeAll(if (cache.hit) "true" else "false");
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

fn stringSliceLessThan(_: void, lhs: []const u8, rhs: []const u8) bool {
    return std.mem.order(u8, lhs, rhs) == .lt;
}

fn freeStringArrayListItems(allocator: std.mem.Allocator, list: *std.ArrayList([]const u8)) void {
    for (list.items) |item| allocator.free(item);
    list.deinit();
}

fn normalizeSkillPathAlloc(allocator: std.mem.Allocator, path: []const u8) ![]u8 {
    const out = try allocator.alloc(u8, path.len);
    for (path, 0..) |c, idx| {
        out[idx] = if (std.fs.path.isSep(c)) '/' else c;
    }
    return out;
}

fn isSaStdSurfaceFile(path: []const u8) bool {
    if (std.mem.eql(u8, std.fs.path.basename(path), "sa.mod")) return true;
    const ext = std.fs.path.extension(path);
    return std.mem.eql(u8, ext, ".sa") or
        std.mem.eql(u8, ext, ".sal") or
        std.mem.eql(u8, ext, ".sai");
}

fn appendStdDeclarations(
    allocator: std.mem.Allocator,
    macros: *std.ArrayList([]const u8),
    externs: *std.ArrayList([]const u8),
    rel_path: []const u8,
    source: []const u8,
) !void {
    var lines = std.mem.splitScalar(u8, source, '\n');
    while (lines.next()) |raw_line| {
        const line = std.mem.trimRight(u8, raw_line, "\r");
        if (std.mem.startsWith(u8, line, "[MACRO] ")) {
            try macros.append(try std.fmt.allocPrint(allocator, "{s}: {s}", .{ rel_path, line }));
        } else if (std.mem.startsWith(u8, line, "@extern ") or std.mem.startsWith(u8, line, "@export ")) {
            try externs.append(try std.fmt.allocPrint(allocator, "{s}: {s}", .{ rel_path, line }));
        }
    }
}

fn collectSaStdSurface(allocator: std.mem.Allocator, std_root: []const u8) !SaStdSurface {
    var files = std.ArrayList([]const u8).init(allocator);
    var macros = std.ArrayList([]const u8).init(allocator);
    var externs = std.ArrayList([]const u8).init(allocator);
    var files_slice: ?[]const []const u8 = null;
    var macros_slice: ?[]const []const u8 = null;
    var externs_slice: ?[]const []const u8 = null;
    errdefer {
        if (files_slice) |items| freeOwnedStringSlice(allocator, items) else freeStringArrayListItems(allocator, &files);
        if (macros_slice) |items| freeOwnedStringSlice(allocator, items) else freeStringArrayListItems(allocator, &macros);
        if (externs_slice) |items| freeOwnedStringSlice(allocator, items) else freeStringArrayListItems(allocator, &externs);
    }

    var root = try std.fs.cwd().openDir(std_root, .{ .iterate = true });
    defer root.close();

    var walker = try root.walk(allocator);
    defer walker.deinit();
    while (try walker.next()) |entry| {
        if (entry.kind != .file) continue;
        if (!isSaStdSurfaceFile(entry.path)) continue;

        const rel_path = try normalizeSkillPathAlloc(allocator, entry.path);
        errdefer allocator.free(rel_path);
        try files.append(rel_path);

        const source = try root.readFileAlloc(allocator, entry.path, 16 * 1024 * 1024);
        defer allocator.free(source);
        try appendStdDeclarations(allocator, &macros, &externs, rel_path, source);
    }

    std.mem.sort([]const u8, files.items, {}, stringSliceLessThan);
    std.mem.sort([]const u8, macros.items, {}, stringSliceLessThan);
    std.mem.sort([]const u8, externs.items, {}, stringSliceLessThan);

    files_slice = try files.toOwnedSlice();
    macros_slice = try macros.toOwnedSlice();
    externs_slice = try externs.toOwnedSlice();

    const result = SaStdSurface{
        .files = files_slice.?,
        .macros = macros_slice.?,
        .externs = externs_slice.?,
    };
    files_slice = null;
    macros_slice = null;
    externs_slice = null;
    return result;
}

const common_official_plugins = [_][]const u8{
    "bc2sa",
    "db",
    "deno",
    "http-client",
    "http-server",
    "node",
    "pkg",
    "sax",
    "vm",
};

fn isCommonOfficialPluginName(name: []const u8) bool {
    const normalized = if (std.mem.startsWith(u8, name, "sa_plugin_")) name["sa_plugin_".len..] else name;
    for (common_official_plugins) |candidate| {
        if (std.mem.eql(u8, normalized, candidate)) return true;
        if (std.mem.eql(u8, name, candidate)) return true;
    }
    return false;
}

fn dirExistsAbsolute(path: []const u8) bool {
    var dir = std.fs.openDirAbsolute(path, .{}) catch return false;
    dir.close();
    return true;
}

fn dirExistsCwd(path: []const u8) bool {
    var dir = std.fs.cwd().openDir(path, .{}) catch return false;
    dir.close();
    return true;
}

fn officialPluginsRootFromEnv(allocator: std.mem.Allocator) !?[]u8 {
    if (dirExistsCwd("sa_plugins")) {
        return try std.fs.cwd().realpathAlloc(allocator, "sa_plugins");
    }

    const env_root = std.process.getEnvVarOwned(allocator, "SA_PLUGINS_WORKSPACE") catch |err| switch (err) {
        error.EnvironmentVariableNotFound => null,
        else => return err,
    };
    if (env_root) |root| {
        defer allocator.free(root);
        if (std.fs.path.isAbsolute(root)) {
            if (dirExistsAbsolute(root)) return try allocator.dupe(u8, root);
        } else if (dirExistsCwd(root)) {
            return try std.fs.cwd().realpathAlloc(allocator, root);
        }
    }

    if (std.fs.path.dirname(build_options.repo_root)) |parent| {
        const sibling = try std.fs.path.join(allocator, &.{ parent, "sa_plugins" });
        defer allocator.free(sibling);
        if (dirExistsAbsolute(sibling)) return try allocator.dupe(u8, sibling);
    }

    return null;
}

fn appendJsonStringArrayToCsv(
    allocator: std.mem.Allocator,
    list: *std.ArrayList([]const u8),
    value: ?std.json.Value,
) ![]const u8 {
    var scratch = std.ArrayList([]const u8).init(allocator);
    defer scratch.deinit();
    if (value) |v| switch (v) {
        .array => |arr| {
            for (arr.items) |item| switch (item) {
                .string => |text| try scratch.append(text),
                else => {},
            };
        },
        else => {},
    };
    if (scratch.items.len == 0) {
        const owned = try allocator.dupe(u8, "none");
        try list.append(owned);
        return owned;
    }
    const owned = try std.mem.join(allocator, ", ", scratch.items);
    try list.append(owned);
    return owned;
}

fn appendJsonObjectKeysToCsv(
    allocator: std.mem.Allocator,
    list: *std.ArrayList([]const u8),
    value: ?std.json.Value,
) ![]const u8 {
    var scratch = std.ArrayList([]const u8).init(allocator);
    defer scratch.deinit();
    if (value) |v| switch (v) {
        .object => |obj| {
            var it = obj.iterator();
            while (it.next()) |entry| try scratch.append(entry.key_ptr.*);
        },
        else => {},
    };
    if (scratch.items.len == 0) {
        const owned = try allocator.dupe(u8, "none");
        try list.append(owned);
        return owned;
    }
    std.mem.sort([]const u8, scratch.items, {}, stringSliceLessThan);
    const owned = try std.mem.join(allocator, ", ", scratch.items);
    try list.append(owned);
    return owned;
}

fn appendJsonInterfaceSummary(
    allocator: std.mem.Allocator,
    list: *std.ArrayList([]const u8),
    value: ?std.json.Value,
) ![]const u8 {
    var scratch = std.ArrayList([]const u8).init(allocator);
    defer scratch.deinit();
    if (value) |v| switch (v) {
        .object => |obj| {
            var it = obj.iterator();
            while (it.next()) |entry| {
                const key = entry.key_ptr.*;
                switch (entry.value_ptr.*) {
                    .string => |path| try scratch.append(try std.fmt.allocPrint(allocator, "{s}:{s}", .{ key, path })),
                    .object => |o| if (o.get("path")) |path_value| switch (path_value) {
                        .string => |path| try scratch.append(try std.fmt.allocPrint(allocator, "{s}:{s}", .{ key, path })),
                        else => {},
                    },
                    .array => |arr| for (arr.items) |item| switch (item) {
                        .string => |path| try scratch.append(try std.fmt.allocPrint(allocator, "{s}:{s}", .{ key, path })),
                        .object => |o| if (o.get("path")) |path_value| switch (path_value) {
                            .string => |path| try scratch.append(try std.fmt.allocPrint(allocator, "{s}:{s}", .{ key, path })),
                            else => {},
                        },
                        else => {},
                    },
                    else => {},
                }
            }
        },
        else => {},
    };
    defer {
        for (scratch.items) |item| allocator.free(item);
    }
    if (scratch.items.len == 0) {
        const owned = try allocator.dupe(u8, "CLI-only or native descriptor only");
        try list.append(owned);
        return owned;
    }
    std.mem.sort([]const u8, scratch.items, {}, stringSliceLessThan);
    const owned = try std.mem.join(allocator, ", ", scratch.items);
    try list.append(owned);
    return owned;
}

fn appendPermissionSummary(
    allocator: std.mem.Allocator,
    list: *std.ArrayList([]const u8),
    value: ?std.json.Value,
) ![]const u8 {
    const obj = if (value) |v| switch (v) {
        .object => |o| o,
        else => null,
    } else null;
    if (obj == null) {
        const owned = try allocator.dupe(u8, "no manifest permissions declared");
        try list.append(owned);
        return owned;
    }
    const o = obj.?;
    const fs_count = if (o.get("fs")) |fs_value| switch (fs_value) {
        .array => |arr| arr.items.len,
        else => 0,
    } else 0;
    const net_count = if (o.get("net")) |net_value| switch (net_value) {
        .array => |arr| arr.items.len,
        else => 0,
    } else 0;
    const env_count = if (o.get("env")) |env_value| switch (env_value) {
        .array => |arr| arr.items.len,
        else => 0,
    } else 0;
    const process_spawn = if (o.get("process")) |process_value| switch (process_value) {
        .object => |process_obj| if (process_obj.get("spawn")) |spawn_value| switch (spawn_value) {
            .bool => |b| b,
            else => false,
        } else false,
        else => false,
    } else false;
    const owned = try std.fmt.allocPrint(allocator, "fs:{d}, net:{d}, env:{d}, process_spawn:{s}", .{ fs_count, net_count, env_count, if (process_spawn) "yes" else "no" });
    try list.append(owned);
    return owned;
}

fn pluginInterfaceFileCandidate(path: []const u8) bool {
    const base = std.fs.path.basename(path);
    if (std.mem.eql(u8, base, "expanded.sa")) return false;
    if (std.mem.startsWith(u8, base, "tmp_")) return false;
    if (std.mem.startsWith(u8, base, "_tmp")) return false;
    const ext = std.fs.path.extension(path);
    return std.mem.eql(u8, ext, ".sa") or
        std.mem.eql(u8, ext, ".sal") or
        std.mem.eql(u8, ext, ".sai");
}

fn appendPluginDeclarations(
    allocator: std.mem.Allocator,
    declarations: *std.ArrayList([]const u8),
    plugin_name: []const u8,
    plugin_dir_name: []const u8,
    plugin_dir: std.fs.Dir,
) !void {
    var it = plugin_dir.iterate();
    while (try it.next()) |entry| {
        if (entry.kind != .file and entry.kind != .sym_link) continue;
        if (!pluginInterfaceFileCandidate(entry.name)) continue;
        const source = try plugin_dir.readFileAlloc(allocator, entry.name, 16 * 1024 * 1024);
        defer allocator.free(source);
        var lines = std.mem.splitScalar(u8, source, '\n');
        while (lines.next()) |raw_line| {
            const line = std.mem.trimRight(u8, raw_line, "\r");
            if (std.mem.startsWith(u8, line, "[MACRO] ") or
                std.mem.startsWith(u8, line, "@extern ") or
                std.mem.startsWith(u8, line, "@export "))
            {
                try declarations.append(try std.fmt.allocPrint(allocator, "{s}/{s}/{s}: {s}", .{ plugin_name, plugin_dir_name, entry.name, line }));
            }
        }
    }
}

fn appendDocSummary(
    allocator: std.mem.Allocator,
    list: *std.ArrayList([]const u8),
    plugin_dir: std.fs.Dir,
) ![]const u8 {
    const doc_names = [_][]const u8{ "README.md", "api.md", "AGENTS.md" };
    for (doc_names) |doc_name| {
        const source = plugin_dir.readFileAlloc(allocator, doc_name, 128 * 1024) catch |err| switch (err) {
            error.FileNotFound => continue,
            else => return err,
        };
        defer allocator.free(source);
        var lines = std.mem.splitScalar(u8, source, '\n');
        while (lines.next()) |raw_line| {
            const line = std.mem.trim(u8, raw_line, " \t\r");
            if (line.len == 0) continue;
            if (std.mem.startsWith(u8, line, "#")) continue;
            if (std.mem.startsWith(u8, line, "---")) continue;
            if (std.mem.startsWith(u8, line, "```")) continue;
            const owned = try allocator.dupe(u8, line);
            try list.append(owned);
            return owned;
        }
    }
    const owned = try allocator.dupe(u8, "No README summary found; inspect the plugin manifest and interface files before using it.");
    try list.append(owned);
    return owned;
}

fn appendOfficialPluginInfo(
    allocator: std.mem.Allocator,
    plugins_list: *std.ArrayList([]const u8),
    declarations: *std.ArrayList([]const u8),
    notes: *std.ArrayList([]const u8),
    root_dir: std.fs.Dir,
    root_path: []const u8,
    dir_name: []const u8,
) !void {
    var plugin_dir = try root_dir.openDir(dir_name, .{ .iterate = true });
    defer plugin_dir.close();

    const manifest_source = plugin_dir.readFileAlloc(allocator, "sap.json", 1024 * 1024) catch |err| switch (err) {
        error.FileNotFound => return,
        else => return err,
    };
    defer allocator.free(manifest_source);
    var parsed = try std.json.parseFromSlice(std.json.Value, allocator, manifest_source, .{});
    defer parsed.deinit();
    const object = switch (parsed.value) {
        .object => |obj| obj,
        else => return,
    };
    const manifest_name = switch (object.get("name") orelse return) {
        .string => |s| s,
        else => return,
    };
    if (!isCommonOfficialPluginName(manifest_name) and !isCommonOfficialPluginName(dir_name)) return;

    const version = if (object.get("version")) |version_value| switch (version_value) {
        .string => |s| s,
        else => "unknown",
    } else "unknown";
    const doc_summary = try appendDocSummary(allocator, notes, plugin_dir);
    const skills = try appendJsonStringArrayToCsv(allocator, notes, object.get("skills"));
    const interfaces = try appendJsonInterfaceSummary(allocator, notes, object.get("interfaces"));
    const dependencies = try appendJsonObjectKeysToCsv(allocator, notes, object.get("dependencies"));
    const permissions = try appendPermissionSummary(allocator, notes, object.get("permissions"));
    const plugin_path = try std.fs.path.join(allocator, &.{ root_path, dir_name });
    defer allocator.free(plugin_path);

    try plugins_list.append(try std.fmt.allocPrint(
        allocator,
        "{s} ({s}) from `{s}`: {s} Skills: {s}. Interfaces: {s}. Dependencies: {s}. Permissions: {s}. Optional plugin: install before use with `SA_PLUGIN_DEV=1 sa plugin install --dev {s}`, then verify availability with `sa plugin list` or `sa skills --json`.",
        .{ manifest_name, version, dir_name, doc_summary, skills, interfaces, dependencies, permissions, plugin_path },
    ));

    try appendPluginDeclarations(allocator, declarations, manifest_name, dir_name, plugin_dir);
}

fn collectOfficialSaPluginsSurface(allocator: std.mem.Allocator) !SaPluginsSurface {
    var plugins_list = std.ArrayList([]const u8).init(allocator);
    var declarations = std.ArrayList([]const u8).init(allocator);
    var notes = std.ArrayList([]const u8).init(allocator);
    var plugins_slice: ?[]const []const u8 = null;
    var declarations_slice: ?[]const []const u8 = null;
    var notes_slice: ?[]const []const u8 = null;
    var root_owned: ?[]u8 = null;
    errdefer {
        if (root_owned) |root| allocator.free(root);
        if (plugins_slice) |items| freeOwnedStringSlice(allocator, items) else freeStringArrayListItems(allocator, &plugins_list);
        if (declarations_slice) |items| freeOwnedStringSlice(allocator, items) else freeStringArrayListItems(allocator, &declarations);
        if (notes_slice) |items| freeOwnedStringSlice(allocator, items) else freeStringArrayListItems(allocator, &notes);
    }

    root_owned = try officialPluginsRootFromEnv(allocator);
    if (root_owned) |root_path| {
        var root_dir = try std.fs.openDirAbsolute(root_path, .{ .iterate = true });
        defer root_dir.close();
        var it = root_dir.iterate();
        while (try it.next()) |entry| {
            if (entry.kind != .directory and entry.kind != .sym_link) continue;
            if (!std.mem.startsWith(u8, entry.name, "sa_plugin_")) continue;
            try appendOfficialPluginInfo(allocator, &plugins_list, &declarations, &notes, root_dir, root_path, entry.name);
        }
    }

    std.mem.sort([]const u8, plugins_list.items, {}, stringSliceLessThan);
    std.mem.sort([]const u8, declarations.items, {}, stringSliceLessThan);
    plugins_slice = try plugins_list.toOwnedSlice();
    declarations_slice = try declarations.toOwnedSlice();
    notes_slice = try notes.toOwnedSlice();

    const result = SaPluginsSurface{
        .root = root_owned,
        .plugins = plugins_slice.?,
        .declarations = declarations_slice.?,
        .notes = notes_slice.?,
    };
    root_owned = null;
    plugins_slice = null;
    declarations_slice = null;
    notes_slice = null;
    return result;
}

fn writeFrontmatterField(writer: anytype, name: []const u8, value: []const u8) !void {
    try writer.print("{s}: ", .{name});
    try writeJsonString(writer, value);
    try writer.writeByte('\n');
}

fn writeMarkdownCodeList(writer: anytype, items: []const []const u8) !void {
    if (items.len == 0) {
        try writer.writeAll("- none\n");
        return;
    }
    for (items) |item| {
        try writer.print("- `{s}`\n", .{item});
    }
}

fn writeMarkdownTextList(writer: anytype, items: []const []const u8) !void {
    if (items.len == 0) {
        try writer.writeAll("- none\n");
        return;
    }
    for (items) |item| {
        try writer.print("- {s}\n", .{item});
    }
}

fn writeSaAgentSkillMarkdown(
    writer: anytype,
    agent_name: []const u8,
    std_root: []const u8,
    sections: []const SkillSection,
    surface: SaStdSurface,
) !void {
    const description = if (std.mem.eql(u8, agent_name, "claude"))
        "Use the installed SA compiler and current sa_std surface to build, test, debug, and inspect SA projects from Claude."
    else
        "Use the installed SA compiler and current sa_std surface to build, test, debug, and inspect SA projects from Codex.";
    try writer.writeAll("---\n");
    try writeFrontmatterField(writer, "name", "sa");
    try writeFrontmatterField(writer, "description", description);
    try writeFrontmatterField(writer, "when_to_use", "Use when working on SA assembly, running SA CLI builds/tests, diagnosing verifier errors, or checking the available sa_std macros and extern APIs.");
    try writer.writeAll("---\n\n");

    try writer.writeAll("# SA Toolchain\n\n");
    try writer.writeAll("## Core Workflow\n");
    try writer.writeAll("- Run `sa version` to confirm the installed compiler version.\n");
    try writer.writeAll("- Use `sa build <file>` to compile and verify SA source without running it; project build caching is on by default and `--no-incremental` forces a clean rebuild.\n");
    try writer.writeAll("- Use `sa run <file> [args...]` for compile-and-run workflows.\n");
    try writer.writeAll("- Use `sa build-exe <file> -o <path>`, `sa build-obj <file> -o <path>`, or `sa build-wasm <file> -o <path>` for artifacts.\n");
    try writer.writeAll("- Use `sa test <file> --list`, `sa test <file> --filter <pattern>`, `sa test <file> --compile-only`, and `sa test <file> --trace-panic` for unit tests.\n");
    try writer.writeAll("- Use `sa explain <code>` and `sa fix --plan <code>` before guessing at diagnostics.\n");
    try writer.writeAll("- Treat the `sa_std Surface` section below as authoritative for currently available macros and extern/export declarations; it is generated by scanning the active std root.\n");
    try writer.writeAll("- Keep plugin-specific APIs out of compiler std; optional official plugin notes are generated separately at `../sa_plugins/SKILL.md`.\n");
    try writer.writeAll("- Before using any plugin API, run `sa plugin list` or `sa skills --json` to confirm that the plugin is installed for this environment.\n\n");

    try writer.writeAll("## CLI Skill Sections\n");
    for (sections) |section| {
        try writer.print("### {s}\n", .{section.name});
        try writer.print("{s}\n", .{section.summary});
        try writeMarkdownCodeList(writer, section.items);
        try writer.writeByte('\n');
    }

    try writer.writeAll("## Std Coverage Guide\n");
    try writer.writeAll("- Core macro families include string, vec, slice, option, result, iter, mem, ptr, num, cmp, ops, default, convert, borrow, any, error, hash, marker, pin, char, and ascii helpers.\n");
    try writer.writeAll("- Runtime-backed std families include fs, env, process, io, time, net, path, term, fmt, json, regex, and sync helpers.\n");
    try writer.writeAll("- Rust-style fs coverage includes create_dir, create_dir_all, remove_dir, remove_dir_all, read_to_string, try_exists, canonicalize, hard_link, symlink, read_link, permissions, and file sync helpers where listed in the generated surface.\n");
    try writer.writeAll("- Rust-style net coverage includes owned address handles, ToSocketAddrs first-address resolution, TCP listener/stream helpers, UDP socket helpers, and address formatting where listed in the generated surface.\n");
    try writer.writeAll("- Future/task/async macros cover the current SA facade; Rust's full std::future/std::task poll, executor, join, select, trait, and generic type system are not implied unless concrete macros appear below.\n");
    try writer.writeAll("- Deno, http, node, db, sax, vm, bc2sa, and other optional plugin APIs are documented separately under `../sa_plugins/SKILL.md` and must not be assumed installed.\n\n");

    try writer.writeAll("## sa_std Surface\n");
    try writer.print("Generated from `{s}`.\n\n", .{std_root});
    try writer.print("- files: `{d}`\n", .{surface.files.len});
    try writer.print("- macros: `{d}`\n", .{surface.macros.len});
    try writer.print("- extern/export declarations: `{d}`\n\n", .{surface.externs.len});

    try writer.writeAll("### Files\n");
    try writeMarkdownCodeList(writer, surface.files);
    try writer.writeAll("\n### Macros\n");
    try writeMarkdownCodeList(writer, surface.macros);
    try writer.writeAll("\n### Externs And Exports\n");
    try writeMarkdownCodeList(writer, surface.externs);
}

fn writeSaPluginsAgentSkillMarkdown(
    writer: anytype,
    agent_name: []const u8,
    surface: SaPluginsSurface,
) !void {
    const description = if (std.mem.eql(u8, agent_name, "claude"))
        "Use the optional official SA plugin catalog from Claude without assuming plugins are installed."
    else
        "Use the optional official SA plugin catalog from Codex without assuming plugins are installed.";
    try writer.writeAll("---\n");
    try writeFrontmatterField(writer, "name", "sa_plugins");
    try writeFrontmatterField(writer, "description", description);
    try writeFrontmatterField(writer, "when_to_use", "Use when a task mentions optional SA plugins such as deno, http-client, http-server, node, pkg, db, sax, bc2sa, or vm. Always verify installation before using plugin APIs.");
    try writer.writeAll("---\n\n");

    try writer.writeAll("# SA Optional Plugins\n\n");
    try writer.writeAll("## Rules\n");
    try writer.writeAll("- This file is a catalog of common official plugins, not proof that any plugin is installed.\n");
    try writer.writeAll("- Run `sa plugin list` to inspect installed plugins before using plugin commands or imports.\n");
    try writer.writeAll("- Run `sa skills --json` to inspect capability sections exported by currently loaded plugins.\n");
    try writer.writeAll("- Install a needed local official plugin with `SA_PLUGIN_DEV=1 sa plugin install --dev <plugin-dir>`; plugin dependencies may need to be installed first or declared in `sap.json`.\n");
    try writer.writeAll("- Keep these APIs out of compiler `sa_std`; plugin availability is per environment and can change.\n\n");

    try writer.writeAll("## Source\n");
    if (surface.root) |root| {
        try writer.print("Generated from optional plugin workspace `{s}`.\n", .{root});
    } else {
        try writer.writeAll("No official plugin workspace was found. Set `SA_PLUGINS_WORKSPACE` or keep `/home/vscode/projects/sa_plugins` beside the compiler checkout to populate this catalog.\n");
    }
    try writer.print("- common plugins listed: `{d}`\n", .{surface.plugins.len});
    try writer.print("- interface declarations listed: `{d}`\n\n", .{surface.declarations.len});

    try writer.writeAll("## Common Official Plugins\n");
    try writeMarkdownTextList(writer, surface.plugins);
    try writer.writeAll("\n## Interface Declarations\n");
    try writeMarkdownCodeList(writer, surface.declarations);
}

fn writeSaAgentSkills(
    allocator: std.mem.Allocator,
    std_root: []const u8,
    sections: []const SkillSection,
    surface: SaStdSurface,
    plugins_surface: SaPluginsSurface,
) !AgentSkillPaths {
    const sa_codex_dir = ".codex/skills/sa";
    const sa_claude_dir = ".claude/skills/sa";
    const plugins_codex_dir = ".codex/skills/sa_plugins";
    const plugins_claude_dir = ".claude/skills/sa_plugins";
    const sa_codex_path = ".codex/skills/sa/SKILL.md";
    const sa_claude_path = ".claude/skills/sa/SKILL.md";
    const plugins_codex_path = ".codex/skills/sa_plugins/SKILL.md";
    const plugins_claude_path = ".claude/skills/sa_plugins/SKILL.md";

    try std.fs.cwd().makePath(sa_codex_dir);
    try std.fs.cwd().makePath(sa_claude_dir);
    try std.fs.cwd().makePath(plugins_codex_dir);
    try std.fs.cwd().makePath(plugins_claude_dir);

    {
        var file = try std.fs.cwd().createFile(sa_codex_path, .{ .truncate = true });
        defer file.close();
        try writeSaAgentSkillMarkdown(file.writer(), "codex", std_root, sections, surface);
    }
    {
        var file = try std.fs.cwd().createFile(sa_claude_path, .{ .truncate = true });
        defer file.close();
        try writeSaAgentSkillMarkdown(file.writer(), "claude", std_root, sections, surface);
    }
    {
        var file = try std.fs.cwd().createFile(plugins_codex_path, .{ .truncate = true });
        defer file.close();
        try writeSaPluginsAgentSkillMarkdown(file.writer(), "codex", plugins_surface);
    }
    {
        var file = try std.fs.cwd().createFile(plugins_claude_path, .{ .truncate = true });
        defer file.close();
        try writeSaPluginsAgentSkillMarkdown(file.writer(), "claude", plugins_surface);
    }

    return .{
        .sa_codex = try allocator.dupe(u8, sa_codex_path),
        .sa_claude = try allocator.dupe(u8, sa_claude_path),
        .plugins_codex = try allocator.dupe(u8, plugins_codex_path),
        .plugins_claude = try allocator.dupe(u8, plugins_claude_path),
    };
}

fn skillsCommand(allocator: std.mem.Allocator, writer: anytype, json_mode: bool) !u8 {
    const base_sections = [_]SkillSection{
        .{ .name = "core diagnostics", .summary = "Agent-facing error handling and JSON reports", .items = &.{
            "stable trap names and trap codes",
            "structured JSON diagnostics with repair hints",
            "human and JSON output modes remain aligned",
        } },
        .{ .name = "cli toolchain", .summary = "Agent-first CLI entry points", .items = &.{
            "init [path]",
            "pkg install [identity]",
            "explain <code>",
            "fix --plan --json",
            "skills",
        } },
        .{ .name = "project lifecycle", .summary = "Rust-like project setup and local builds", .items = &.{
            "init [path]",
            "pkg install",
            "build src/main.sa",
            "run src/main.sa",
            "test <file>",
        } },
        .{ .name = "std runtime", .summary = "Current Zig-backed facade surface", .items = &.{
            "Rust-style string/vec/slice/option/result/core helper macros",
            "fs/env/process/io/time/net/sync facades over the compiler runtime",
            "JSON DOM, regex, formatting, path, and terminal facades",
            "optional deno/http/node/db/plugin APIs stay outside compiler std",
        } },
    };
    var sections_list = std.ArrayList(SkillSection).init(allocator);
    errdefer sections_list.deinit();
    try sections_list.appendSlice(base_sections[0..]);
    var plugin_runtime = try plugins.Runtime.initFromEnv(allocator);
    defer plugin_runtime.deinit();
    try plugin_runtime.appendSkills(&sections_list);
    const sections = try sections_list.toOwnedSlice();
    defer allocator.free(sections);

    if (json_mode) {
        try writeSkillsJson(writer, sections);
    } else {
        const std_root = try stdRootFromEnv(allocator);
        defer allocator.free(std_root);
        const surface = try collectSaStdSurface(allocator, std_root);
        defer surface.deinit(allocator);
        const plugins_surface = try collectOfficialSaPluginsSurface(allocator);
        defer plugins_surface.deinit(allocator);
        const skill_paths = try writeSaAgentSkills(allocator, std_root, sections, surface, plugins_surface);
        defer skill_paths.deinit(allocator);

        try writer.writeAll("agent-first toolchain\n");
        try writer.print("generated agent skills:\n- {s}\n- {s}\n- {s}\n- {s}\n", .{ skill_paths.sa_codex, skill_paths.sa_claude, skill_paths.plugins_codex, skill_paths.plugins_claude });
        try writer.print("std surface: {d} files, {d} macros, {d} extern/export declarations\n", .{ surface.files.len, surface.macros.len, surface.externs.len });
        try writer.print("official plugin catalog: {d} common plugins, {d} interface declarations; availability still depends on local installation\n", .{ plugins_surface.plugins.len, plugins_surface.declarations.len });
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
    if (options.permission_set) |set_name| {
        if (!manifestPermissionSetExists(project_manifest, set_name)) return error.InvalidPermissionSet;
    } else if (ci_mode and project_manifest.permission_sets.len != 0 and !compileOptionsHaveAllowList(options)) {
        return error.MissingPermissionSet;
    }

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

fn manifestPermissionSetExists(project_manifest: manifest.Manifest, name: []const u8) bool {
    for (project_manifest.permission_sets) |set| {
        if (std.mem.eql(u8, set.name, name)) return true;
    }
    return false;
}

fn compileOptionsHaveAllowList(options: CompileOptions) bool {
    return options.allow_env_requested or
        options.allow_net_requested or
        options.allow_read_requested or
        options.allow_write_requested or
        options.allow_run_requested;
}

fn consumeCompileOption(arg: []const u8, args: []const []const u8, index: *usize, options: *CompileOptions) !bool {
    if (try consumeJobsOption(arg, args, index, options)) return true;
    if (try consumeDceOption(arg, args, index, options)) return true;
    if (consumeProfileOption(arg, options)) return true;
    if (try consumePermissionSetOption(arg, args, index, options)) return true;
    if (consumeAllowOption(arg, options)) return true;
    if (std.mem.eql(u8, arg, "--offline")) {
        options.offline = true;
        return true;
    }
    if (std.mem.eql(u8, arg, "--no-incremental")) {
        options.incremental_cache = false;
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

fn parseDceValue(text: []const u8) !DceMode {
    return DceMode.parse(text) orelse error.InvalidDceMode;
}

fn consumeDceOption(arg: []const u8, args: []const []const u8, index: *usize, options: *CompileOptions) !bool {
    if (std.mem.startsWith(u8, arg, "--dce=")) {
        options.dce = try parseDceValue(arg["--dce=".len..]);
        return true;
    }
    if (std.mem.eql(u8, arg, "--dce")) {
        if (index.* + 1 >= args.len) return error.MissingDceMode;
        options.dce = try parseDceValue(args[index.* + 1]);
        index.* += 1;
        return true;
    }
    if (std.mem.eql(u8, arg, "--no-dce")) {
        options.dce = .no;
        return true;
    }
    return false;
}

fn consumePermissionSetOption(arg: []const u8, args: []const []const u8, index: *usize, options: *CompileOptions) !bool {
    if (std.mem.startsWith(u8, arg, "--permission-set=")) {
        options.permission_set = arg["--permission-set=".len..];
        if (options.permission_set.?.len == 0) return error.InvalidPermissionSet;
        return true;
    }
    if (std.mem.eql(u8, arg, "--permission-set")) {
        if (index.* + 1 >= args.len) return error.MissingPermissionSet;
        options.permission_set = args[index.* + 1];
        index.* += 1;
        return true;
    }
    if (std.mem.startsWith(u8, arg, "-P=")) {
        options.permission_set = arg["-P=".len..];
        if (options.permission_set.?.len == 0) return error.InvalidPermissionSet;
        return true;
    }
    if (std.mem.eql(u8, arg, "-P")) {
        options.permission_set = "default";
        return true;
    }
    return false;
}

fn consumeAllowOption(arg: []const u8, options: *CompileOptions) bool {
    if (std.mem.eql(u8, arg, "--allow-env") or std.mem.startsWith(u8, arg, "--allow-env=")) {
        options.allow_env_requested = true;
        return true;
    }
    if (std.mem.eql(u8, arg, "--allow-net") or std.mem.startsWith(u8, arg, "--allow-net=")) {
        options.allow_net_requested = true;
        return true;
    }
    if (std.mem.eql(u8, arg, "--allow-read") or std.mem.startsWith(u8, arg, "--allow-read=")) {
        options.allow_read_requested = true;
        return true;
    }
    if (std.mem.eql(u8, arg, "--allow-write") or std.mem.startsWith(u8, arg, "--allow-write=")) {
        options.allow_write_requested = true;
        return true;
    }
    if (std.mem.eql(u8, arg, "--allow-run") or std.mem.startsWith(u8, arg, "--allow-run=")) {
        options.allow_run_requested = true;
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
    if (builtin.is_test) test_source_tree_load_count += 1;
    var file = try std.fs.cwd().openFile(path, .{});
    defer file.close();
    return try file.readToEndAlloc(allocator, 16 * 1024 * 1024);
}

var test_source_tree_load_count: usize = 0;

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

    if (builtin.is_test) return repo_std_root;

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

fn defaultStableImportRoots(allocator: std.mem.Allocator, project_root: []const u8) ![]const []const u8 {
    var roots = std.ArrayList([]const u8).init(allocator);
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

fn readProjectManifest(allocator: std.mem.Allocator, project_root: []const u8) !?manifest.Manifest {
    const manifest_path = try std.fs.path.join(allocator, &.{ project_root, "sa.mod" });
    defer allocator.free(manifest_path);

    const file = std.fs.cwd().openFile(manifest_path, .{}) catch |err| switch (err) {
        error.FileNotFound => return null,
        else => return err,
    };
    defer file.close();

    const source = try file.readToEndAlloc(allocator, manifest.max_manifest_bytes);
    defer allocator.free(source);
    return try manifest.parseManifestWithFile(allocator, source, manifest_path);
}

fn projectRootFromCurrentDir(allocator: std.mem.Allocator) ![]u8 {
    const cwd_abs = try std.fs.cwd().realpathAlloc(allocator, ".");
    errdefer allocator.free(cwd_abs);

    var current = try allocator.dupe(u8, cwd_abs);
    defer allocator.free(current);
    while (true) {
        const manifest_path = try std.fs.path.join(allocator, &.{ current, "sa.mod" });
        defer allocator.free(manifest_path);

        if (std.fs.cwd().openFile(manifest_path, .{})) |file| {
            file.close();
            allocator.free(cwd_abs);
            return try allocator.dupe(u8, current);
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

fn parseAllowListFragment(allocator: std.mem.Allocator, list: *std.ArrayList([]const u8), value_text: []const u8) !void {
    var it = std.mem.splitScalar(u8, value_text, ',');
    while (it.next()) |raw_item| {
        const item = std.mem.trim(u8, raw_item, " \t\r\n");
        if (item.len == 0) return error.InvalidArgument;
        try list.append(try allocator.dupe(u8, item));
    }
}

fn appendPermissionSetStrings(allocator: std.mem.Allocator, list: *std.ArrayList([]const u8), entries: []const []const u8) !void {
    for (entries) |entry| try list.append(try allocator.dupe(u8, entry));
}

fn validateRunAllowList(entries: []const []const u8) !void {
    for (entries) |entry| {
        if (!std.fs.path.isAbsolute(entry)) return error.InvalidArgument;
    }
}

fn findPermissionSet(project_manifest: manifest.Manifest, name: []const u8) ?*const manifest.PermissionSet {
    for (project_manifest.permission_sets) |*set| {
        if (std.mem.eql(u8, set.name, name)) return set;
    }
    return null;
}

fn buildPluginRuntimeAuthorization(allocator: std.mem.Allocator, args: []const []const u8) !OwnedPluginRuntimeAuthorization {
    var env = std.ArrayList([]const u8).init(allocator);
    errdefer {
        for (env.items) |entry| allocator.free(entry);
        env.deinit();
    }
    var read = std.ArrayList([]const u8).init(allocator);
    errdefer {
        for (read.items) |entry| allocator.free(entry);
        read.deinit();
    }
    var write = std.ArrayList([]const u8).init(allocator);
    errdefer {
        for (write.items) |entry| allocator.free(entry);
        write.deinit();
    }
    var net = std.ArrayList([]const u8).init(allocator);
    errdefer {
        for (net.items) |entry| allocator.free(entry);
        net.deinit();
    }
    var run = std.ArrayList([]const u8).init(allocator);
    errdefer {
        for (run.items) |entry| allocator.free(entry);
        run.deinit();
    }

    var permission_set: ?[]const u8 = null;
    var allow_env_declared = false;
    var allow_read_declared = false;
    var allow_write_declared = false;
    var allow_net_declared = false;
    var allow_run_declared = false;

    var i: usize = 2;
    while (i < args.len) : (i += 1) {
        const arg = args[i];
        if (std.mem.startsWith(u8, arg, "--permission-set=")) {
            permission_set = arg["--permission-set=".len..];
            if (permission_set.?.len == 0) return error.InvalidPermissionSet;
            continue;
        }
        if (std.mem.eql(u8, arg, "--permission-set")) {
            if (i + 1 >= args.len) return error.MissingPermissionSet;
            permission_set = args[i + 1];
            i += 1;
            continue;
        }
        if (std.mem.startsWith(u8, arg, "-P=")) {
            permission_set = arg["-P=".len..];
            if (permission_set.?.len == 0) return error.InvalidPermissionSet;
            continue;
        }
        if (std.mem.eql(u8, arg, "-P")) {
            permission_set = "default";
            continue;
        }
        if (std.mem.startsWith(u8, arg, "--allow-env=")) {
            try parseAllowListFragment(allocator, &env, arg["--allow-env=".len..]);
            continue;
        }
        if (std.mem.eql(u8, arg, "--allow-env")) {
            allow_env_declared = true;
            continue;
        }
        if (std.mem.startsWith(u8, arg, "--allow-read=")) {
            try parseAllowListFragment(allocator, &read, arg["--allow-read=".len..]);
            continue;
        }
        if (std.mem.eql(u8, arg, "--allow-read")) {
            allow_read_declared = true;
            continue;
        }
        if (std.mem.startsWith(u8, arg, "--allow-write=")) {
            try parseAllowListFragment(allocator, &write, arg["--allow-write=".len..]);
            continue;
        }
        if (std.mem.eql(u8, arg, "--allow-write")) {
            allow_write_declared = true;
            continue;
        }
        if (std.mem.startsWith(u8, arg, "--allow-net=")) {
            try parseAllowListFragment(allocator, &net, arg["--allow-net=".len..]);
            continue;
        }
        if (std.mem.eql(u8, arg, "--allow-net")) {
            allow_net_declared = true;
            continue;
        }
        if (std.mem.startsWith(u8, arg, "--allow-run=")) {
            try parseAllowListFragment(allocator, &run, arg["--allow-run=".len..]);
            continue;
        }
        if (std.mem.eql(u8, arg, "--allow-run")) {
            allow_run_declared = true;
            continue;
        }
    }

    const project_root = try projectRootFromCurrentDir(allocator);
    errdefer allocator.free(project_root);

    if (permission_set) |set_name| {
        var project_manifest = (try readProjectManifest(allocator, project_root)) orelse return error.InvalidPermissionSet;
        defer project_manifest.deinit(allocator);
        const selected = findPermissionSet(project_manifest, set_name) orelse return error.InvalidPermissionSet;
        try appendPermissionSetStrings(allocator, &env, selected.env);
        try appendPermissionSetStrings(allocator, &read, selected.read);
        try appendPermissionSetStrings(allocator, &write, selected.write);
        try appendPermissionSetStrings(allocator, &net, selected.net);
        try appendPermissionSetStrings(allocator, &run, selected.run);
    }
    try validateRunAllowList(run.items);

    var owned = OwnedPluginRuntimeAuthorization{
        .project_root = project_root,
        .env = try env.toOwnedSlice(),
        .read = try read.toOwnedSlice(),
        .write = try write.toOwnedSlice(),
        .net = try net.toOwnedSlice(),
        .run = try run.toOwnedSlice(),
    };
    owned.input = .{
        .dev_mode = false,
        .project_root = owned.project_root,
        .allow_env_declared = allow_env_declared,
        .allow_env = owned.env,
        .allow_read_declared = allow_read_declared,
        .allow_read = owned.read,
        .allow_write_declared = allow_write_declared,
        .allow_write = owned.write,
        .allow_net_declared = allow_net_declared,
        .allow_net = owned.net,
        .allow_run_declared = allow_run_declared,
        .allow_run = owned.run,
    };
    return owned;
}

fn manifestDependencies(manifest_file: *const manifest.Manifest, allocator: std.mem.Allocator) ![]pkg_resolver.Dependency {
    var deps = std.ArrayList(pkg_resolver.Dependency).init(allocator);
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

fn freeOwnedStringSlice(allocator: std.mem.Allocator, items: []const []const u8) void {
    for (items) |item| allocator.free(item);
    allocator.free(items);
}

fn manifestPluginImportRoots(manifest_file: *const manifest.Manifest, allocator: std.mem.Allocator) ![]const []const u8 {
    var roots = std.ArrayList([]const u8).init(allocator);
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

    var plugin_import_roots: []const []const u8 = &.{};
    defer if (plugin_import_roots.len != 0) freeOwnedStringSlice(allocator, plugin_import_roots);
    const stable_import_roots = try defaultStableImportRoots(allocator, project_root);
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
            var r = report;
            if (r.file == null) {
                setFile(&r, source_path);
            }
            flat.deinit(allocator);
            return .{ .trap = r };
        },
    };
}

fn collectExternalSymbolNames(allocator: std.mem.Allocator, verified: *const referee.VerifyOk) ![]const []const u8 {
    var names = std.ArrayList([]const u8).init(allocator);
    errdefer names.deinit();
    for (verified.function_sigs) |fsig| {
        if (fsig.kind == .external) try names.append(fsig.name);
    }
    return try names.toOwnedSlice();
}

fn appendNativePluginLinkInputs(
    allocator: std.mem.Allocator,
    link_inputs: *std.ArrayList([]const u8),
    owned_link_inputs: *std.ArrayList([]const u8),
    verified: *const referee.VerifyOk,
) !void {
    const extern_names = try collectExternalSymbolNames(allocator, verified);
    defer allocator.free(extern_names);
    if (extern_names.len == 0) return;

    // Native linking only needs plugin metadata and exported symbols. Do not
    // apply runtime sandbox gating here, or privileged plugins such as HTTP
    // client/server are silently skipped and their externs fail at link time.
    var plugin_runtime = try plugins.Runtime.initFromEnvWithAuthorization(allocator, .{
        .dev_mode = true,
    });
    defer plugin_runtime.deinit();

    var plugin_libs = std.ArrayList([]const u8).init(allocator);
    defer plugin_libs.deinit();
    try plugin_runtime.appendLibrariesExportingAny(&plugin_libs, extern_names);

    for (plugin_libs.items) |lib_path| {
        const owned_lib_path = try allocator.dupe(u8, lib_path);
        link_inputs.append(owned_lib_path) catch |err| {
            allocator.free(owned_lib_path);
            return err;
        };
        owned_link_inputs.append(owned_lib_path) catch |err| {
            allocator.free(owned_lib_path);
            return err;
        };
        if (std.fs.path.dirname(lib_path)) |dir| {
            const rpath_arg = try std.fmt.allocPrint(allocator, "-Wl,-rpath,{s}", .{dir});
            link_inputs.append(rpath_arg) catch |err| {
                allocator.free(rpath_arg);
                return err;
            };
            owned_link_inputs.append(rpath_arg) catch |err| {
                allocator.free(rpath_arg);
                return err;
            };
        }
    }
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

fn copyFileAlloc(allocator: std.mem.Allocator, src_path: []const u8, dst_path: []const u8) !void {
    _ = allocator;
    try ensureParentDir(dst_path);
    try std.fs.cwd().copyFile(src_path, std.fs.cwd(), dst_path, .{});
}

fn makeExecutable(path: []const u8) !void {
    if (builtin.os.tag == .windows) return;
    var file = try std.fs.cwd().openFile(path, .{ .mode = .read_write });
    defer file.close();
    try file.chmod(0o755);
}

fn cacheRootPath(allocator: std.mem.Allocator, project_root: []const u8) ![]u8 {
    return try pathJoinAlloc(allocator, &.{ project_root, ".sa_cache" });
}

const BuildCacheKind = enum {
    build_exe,
    build_obj,
    build_wasm,
    build_obj_incremental,
    test_cache,

    fn dirName(self: BuildCacheKind) []const u8 {
        return switch (self) {
            .build_exe => "build-exe",
            .build_obj => "build-obj",
            .build_wasm => "build-wasm",
            .build_obj_incremental => "build-obj-incremental",
            .test_cache => "test",
        };
    }
};

const CacheCleanStats = struct {
    scanned: usize = 0,
    removed: usize = 0,
    kept: usize = 0,
};

const CacheCleanOptions = struct {
    dry_run: bool = false,
    max_age_days: u64 = 30,
};

const ProjectCacheKey = struct {
    hex: [64]u8,

    fn slice(self: *const ProjectCacheKey) []const u8 {
        return self.hex[0..];
    }
};

fn cacheBytes(hasher: *std.crypto.hash.sha2.Sha256, bytes: []const u8) void {
    hasher.update(bytes);
    hasher.update(&[_]u8{0});
}

fn cacheU64(hasher: *std.crypto.hash.sha2.Sha256, value: u64) void {
    var buf: [8]u8 = undefined;
    std.mem.writeInt(u64, &buf, value, .little);
    hasher.update(&buf);
}

fn cacheBool(hasher: *std.crypto.hash.sha2.Sha256, value: bool) void {
    hasher.update(&.{if (value) 1 else 0});
}

fn cacheCompilerVersion() []const u8 {
    if (builtin.is_test) return "test";
    return build_options.version;
}

fn projectFileMaybeHash(hasher: *std.crypto.hash.sha2.Sha256, allocator: std.mem.Allocator, path: []const u8) !void {
    if (!projectPathExists(path)) return;
    const bytes = try readTextFileAlloc(allocator, path);
    defer allocator.free(bytes);
    cacheBytes(hasher, bytes);
}

const SourceTreeFileStat = struct {
    path: []u8,
    mtime: i128,
    size: u64,
};

const SourceTreeHashCacheEntry = struct {
    digest: [32]u8,
    files: []SourceTreeFileStat,
    last_used_tick: u64,
};

var source_tree_hash_cache_mutex: std.Thread.Mutex = .{};
var source_tree_hash_cache: ?std.StringHashMap(SourceTreeHashCacheEntry) = null;
var source_tree_hash_cache_tick: u64 = 0;
var test_source_tree_hash_cache_max_entries: ?usize = null;

fn sourceTreeHashCacheMap() *std.StringHashMap(SourceTreeHashCacheEntry) {
    if (source_tree_hash_cache == null) {
        source_tree_hash_cache = std.StringHashMap(SourceTreeHashCacheEntry).init(std.heap.page_allocator);
    }
    return &source_tree_hash_cache.?;
}

fn freeSourceTreeHashCacheEntry(entry: SourceTreeHashCacheEntry) void {
    for (entry.files) |file| std.heap.page_allocator.free(file.path);
    std.heap.page_allocator.free(entry.files);
}

fn sourceTreeHashCacheMaxEntries() ?usize {
    if (builtin.is_test) {
        if (test_source_tree_hash_cache_max_entries) |value| return value;
    }
    const value = std.process.getEnvVarOwned(std.heap.page_allocator, "SA_SOURCE_TREE_HASH_CACHE_MAX_ENTRIES") catch return null;
    defer std.heap.page_allocator.free(value);
    const parsed = std.fmt.parseUnsigned(usize, value, 10) catch return null;
    return if (parsed == 0) null else parsed;
}

fn nextSourceTreeHashCacheTickLocked() u64 {
    source_tree_hash_cache_tick +%= 1;
    return source_tree_hash_cache_tick;
}

fn buildSourceTreeHashCacheKey(
    allocator: std.mem.Allocator,
    dependencies: []pkg_resolver.Dependency,
    plugin_import_roots: []const []const u8,
    project_root: []const u8,
    std_root: []const u8,
    offline: bool,
    real_source_path: []const u8,
) ![]u8 {
    var out = std.ArrayList(u8).init(allocator);
    errdefer out.deinit();
    try appendCacheKeyBytes(&out, cacheCompilerVersion());
    try appendCacheKeyBytes(&out, project_root);
    try appendCacheKeyBytes(&out, std_root);
    try appendCacheKeyBytes(&out, real_source_path);
    try out.writer().print("{}\x00", .{offline});
    for (plugin_import_roots) |root| try appendCacheKeyBytes(&out, root);
    try out.append(0);
    for (dependencies) |dep| {
        try appendCacheKeyBytes(&out, dep.url);
        try appendCacheKeyBytes(&out, dep.ref);
    }
    return try out.toOwnedSlice();
}

fn appendCacheKeyBytes(out: *std.ArrayList(u8), bytes: []const u8) !void {
    try out.appendSlice(bytes);
    try out.append(0);
}

fn sourceTreeHashCacheHit(cache_key: []const u8) ?[32]u8 {
    source_tree_hash_cache_mutex.lock();
    defer source_tree_hash_cache_mutex.unlock();
    const cache = sourceTreeHashCacheMap();
    const entry = cache.getPtr(cache_key) orelse return null;
    for (entry.files) |file| {
        const stat = std.fs.cwd().statFile(file.path) catch return null;
        if (stat.mtime != file.mtime or stat.size != file.size) return null;
    }
    entry.last_used_tick = nextSourceTreeHashCacheTickLocked();
    return entry.digest;
}

fn storeSourceTreeHashCacheEntry(cache_key: []const u8, digest: [32]u8, files: []const SourceTreeFileStat) !void {
    const cache_allocator = std.heap.page_allocator;
    const owned_key = try cache_allocator.dupe(u8, cache_key);
    errdefer cache_allocator.free(owned_key);
    const owned_files = try cache_allocator.alloc(SourceTreeFileStat, files.len);
    errdefer cache_allocator.free(owned_files);
    var copied: usize = 0;
    errdefer {
        for (owned_files[0..copied]) |file| cache_allocator.free(file.path);
    }
    for (files, 0..) |file, idx| {
        owned_files[idx] = .{
            .path = try cache_allocator.dupe(u8, file.path),
            .mtime = file.mtime,
            .size = file.size,
        };
        copied += 1;
    }

    source_tree_hash_cache_mutex.lock();
    defer source_tree_hash_cache_mutex.unlock();
    var cache = sourceTreeHashCacheMap();
    if (cache.getPtr(cache_key)) |old| {
        freeSourceTreeHashCacheEntry(old.*);
        old.* = .{ .digest = digest, .files = owned_files, .last_used_tick = nextSourceTreeHashCacheTickLocked() };
        cache_allocator.free(owned_key);
        evictSourceTreeHashCacheIfNeeded(cache, sourceTreeHashCacheMaxEntries());
        return;
    }
    try cache.put(owned_key, .{ .digest = digest, .files = owned_files, .last_used_tick = nextSourceTreeHashCacheTickLocked() });
    evictSourceTreeHashCacheIfNeeded(cache, sourceTreeHashCacheMaxEntries());
}

fn evictSourceTreeHashCacheIfNeeded(cache: *std.StringHashMap(SourceTreeHashCacheEntry), max_entries: ?usize) void {
    const limit = max_entries orelse return;
    while (cache.count() > limit) {
        var oldest_key: ?[]const u8 = null;
        var oldest_tick: u64 = std.math.maxInt(u64);
        var it = cache.iterator();
        while (it.next()) |entry| {
            if (entry.value_ptr.last_used_tick <= oldest_tick) {
                oldest_key = entry.key_ptr.*;
                oldest_tick = entry.value_ptr.last_used_tick;
            }
        }
        const key = oldest_key orelse return;
        if (cache.fetchRemove(key)) |removed| {
            std.heap.page_allocator.free(removed.key);
            freeSourceTreeHashCacheEntry(removed.value);
        } else {
            return;
        }
    }
}

fn addSourceTreeDigestToHasher(hasher: *std.crypto.hash.sha2.Sha256, digest: [32]u8) void {
    cacheBytes(hasher, "source-tree-digest-v1");
    hasher.update(&digest);
}

fn hashResolvedSourceTreeUncached(
    allocator: std.mem.Allocator,
    hasher: *std.crypto.hash.sha2.Sha256,
    dependencies: []pkg_resolver.Dependency,
    plugin_import_roots: []const []const u8,
    project_root: []const u8,
    std_root: []const u8,
    offline: bool,
    source_path: []const u8,
    visited: *std.StringHashMap(void),
    files: *std.ArrayList(SourceTreeFileStat),
    resolved_source: ?[]const u8,
) !void {
    const real_source_path = try std.fs.cwd().realpathAlloc(allocator, source_path);
    errdefer allocator.free(real_source_path);
    if (visited.contains(real_source_path)) {
        allocator.free(real_source_path);
        return;
    }
    const visited_key = try allocator.dupe(u8, real_source_path);
    var visited_key_inserted = false;
    errdefer if (!visited_key_inserted) allocator.free(visited_key);
    try visited.put(visited_key, {});
    visited_key_inserted = true;

    const stat = try std.fs.cwd().statFile(real_source_path);
    try files.append(.{ .path = real_source_path, .mtime = stat.mtime, .size = stat.size });

    cacheBytes(hasher, real_source_path);
    const owned_source = if (resolved_source == null) try loadSource(allocator, source_path) else null;
    defer if (owned_source) |source| allocator.free(source);
    const source = resolved_source orelse owned_source.?;
    cacheBytes(hasher, source);

    var iter = std.mem.splitScalar(u8, source, '\n');
    while (iter.next()) |line| {
        const classified = line_classifier.classifyLine(line);
        if (classified.kind != .import_decl) continue;
        const import_path = classified.parts[0];
        const resolve_ctx = flattener.ResolveContext{ .dependencies = dependencies, .options = .{
            .project_root = project_root,
            .std_root = std_root,
            .offline = offline,
            .plugin_import_roots = plugin_import_roots,
        } };
        var imported = try flattener.readImportSourceFile(allocator, std.fs.path.dirname(source_path) orelse ".", import_path, resolve_ctx);
        defer imported.deinit(allocator);
        try hashResolvedSourceTreeUncached(allocator, hasher, dependencies, plugin_import_roots, project_root, std_root, offline, imported.entry_path, visited, files, imported.source);
    }
}

fn hashResolvedSourceTree(
    allocator: std.mem.Allocator,
    hasher: *std.crypto.hash.sha2.Sha256,
    dependencies: []pkg_resolver.Dependency,
    plugin_import_roots: []const []const u8,
    project_root: []const u8,
    std_root: []const u8,
    offline: bool,
    source_path: []const u8,
) !void {
    const real_source_path = try std.fs.cwd().realpathAlloc(allocator, source_path);
    defer allocator.free(real_source_path);
    const cache_key = try buildSourceTreeHashCacheKey(allocator, dependencies, plugin_import_roots, project_root, std_root, offline, real_source_path);
    defer allocator.free(cache_key);
    if (sourceTreeHashCacheHit(cache_key)) |digest| {
        addSourceTreeDigestToHasher(hasher, digest);
        return;
    }

    var tree_hasher = std.crypto.hash.sha2.Sha256.init(.{});
    var visited = std.StringHashMap(void).init(allocator);
    defer {
        var it = visited.iterator();
        while (it.next()) |entry| allocator.free(entry.key_ptr.*);
        visited.deinit();
    }
    var files = std.ArrayList(SourceTreeFileStat).init(allocator);
    defer {
        for (files.items) |file| allocator.free(file.path);
        files.deinit();
    }
    try hashResolvedSourceTreeUncached(allocator, &tree_hasher, dependencies, plugin_import_roots, project_root, std_root, offline, source_path, &visited, &files, null);
    var digest: [32]u8 = undefined;
    tree_hasher.final(&digest);
    try storeSourceTreeHashCacheEntry(cache_key, digest, files.items);
    addSourceTreeDigestToHasher(hasher, digest);
}

fn computeProjectBuildKey(
    allocator: std.mem.Allocator,
    project_context: *const ProjectContext,
    project_root: []const u8,
    source_path: []const u8,
    target_name: []const u8,
    source_suffix: []const u8,
    kind: BuildCacheKind,
    debug: bool,
    release_fast: bool,
    incremental: bool,
    wasm: ?WasmTarget,
    hash_source_tree: bool,
    offline: bool,
    dce: DceMode,
) !ProjectCacheKey {
    const std_root = try stdRootFromEnv(allocator);
    defer allocator.free(std_root);

    var hasher = std.crypto.hash.sha2.Sha256.init(.{});
    cacheBytes(&hasher, "sa-build-cache");
    cacheBytes(&hasher, cacheCompilerVersion());
    cacheBytes(&hasher, project_root);
    cacheBytes(&hasher, kind.dirName());
    cacheBytes(&hasher, source_path);
    cacheBytes(&hasher, target_name);
    cacheBytes(&hasher, source_suffix);
    cacheBool(&hasher, debug);
    cacheBool(&hasher, release_fast);
    cacheBool(&hasher, incremental);
    cacheBytes(&hasher, dce.name());
    if (wasm) |target| {
        cacheBytes(&hasher, target.triple);
        cacheBool(&hasher, target.no_entry);
        cacheU64(&hasher, target.size_bits);
    }

    const project_manifest = project_context.manifest;
    if (project_manifest) |*m| {
        cacheBytes(&hasher, project_context.manifest_path);
        if (projectPathExists(project_context.manifest_path)) {
            const manifest_bytes = try readTextFileAlloc(allocator, project_context.manifest_path);
            defer allocator.free(manifest_bytes);
            cacheBytes(&hasher, manifest_bytes);
        }
        if (project_context.lock_file != null) {
            const lock_path = try projectLockPath(allocator, project_context.root_path);
            defer allocator.free(lock_path);
            try projectFileMaybeHash(&hasher, allocator, lock_path);
        }
        if (project_context.sum_file != null) {
            const sum_path = try projectSumPath(allocator, project_context.root_path);
            defer allocator.free(sum_path);
            try projectFileMaybeHash(&hasher, allocator, sum_path);
        }
        var dependency_slice: []pkg_resolver.Dependency = &.{};
        defer if (dependency_slice.len != 0) allocator.free(dependency_slice);
        var plugin_import_roots: []const []const u8 = &.{};
        defer if (plugin_import_roots.len != 0) freeOwnedStringSlice(allocator, plugin_import_roots);
        if (m.requires.len != 0) {
            dependency_slice = try manifestDependencies(m, allocator);
        }
        if (m.plugin_requires.len != 0) {
            plugin_import_roots = try manifestPluginImportRoots(m, allocator);
        }

        if (hash_source_tree) {
            try hashResolvedSourceTree(allocator, &hasher, dependency_slice, plugin_import_roots, project_context.root_path, std_root, offline, source_path);
        }
    } else {
        try projectFileMaybeHash(&hasher, allocator, project_context.manifest_path);
        if (hash_source_tree) {
            try hashResolvedSourceTree(allocator, &hasher, &.{}, &.{}, project_context.root_path, std_root, offline, source_path);
        }
    }

    var out: [32]u8 = undefined;
    hasher.final(&out);
    return .{ .hex = std.fmt.bytesToHex(out, .lower) };
}

fn projectCacheDir(allocator: std.mem.Allocator, project_root: []const u8, kind: BuildCacheKind, key: ProjectCacheKey) ![]u8 {
    return try pathJoinAlloc(allocator, &.{ project_root, ".sa_cache", kind.dirName(), key.slice() });
}

fn projectCacheArtifactPath(allocator: std.mem.Allocator, project_root: []const u8, kind: BuildCacheKind, key: ProjectCacheKey, filename: []const u8) ![]u8 {
    const dir = try projectCacheDir(allocator, project_root, kind, key);
    defer allocator.free(dir);
    return try pathJoinAlloc(allocator, &.{ dir, filename });
}

fn projectCacheRemoveKey(allocator: std.mem.Allocator, project_root: []const u8, kind: BuildCacheKind, key: ProjectCacheKey) void {
    const dir = projectCacheDir(allocator, project_root, kind, key) catch return;
    defer allocator.free(dir);
    std.fs.cwd().deleteTree(dir) catch |err| {
        // Build cache repair is opportunistic here; callers fall back to recompilation on unusable entries.
        _ = @errorName(err);
    };
}

fn projectCacheArtifactExistsNonEmpty(path: []const u8) bool {
    const stat = std.fs.cwd().statFile(path) catch return false;
    return stat.kind == .file and stat.size != 0;
}

fn projectCacheManifestPath(allocator: std.mem.Allocator, project_root: []const u8, kind: BuildCacheKind, key: ProjectCacheKey) ![]u8 {
    return try projectCacheArtifactPath(allocator, project_root, kind, key, "manifest.json");
}

fn jsonGetObject(value: std.json.Value, key: []const u8) !std.json.Value {
    const object = switch (value) {
        .object => |object| object,
        else => return error.InvalidCacheManifest,
    };
    return object.get(key) orelse return error.InvalidCacheManifest;
}

fn jsonStringEquals(value: std.json.Value, expected: []const u8) bool {
    return switch (value) {
        .string => |text| std.mem.eql(u8, text, expected),
        else => false,
    };
}

fn jsonIntEquals(value: std.json.Value, expected: u64) bool {
    return switch (value) {
        .integer => |v| v >= 0 and @as(u64, @intCast(v)) == expected,
        else => false,
    };
}

fn projectCacheArtifactMatchesManifest(allocator: std.mem.Allocator, artifact_value: std.json.Value, path: []const u8) !bool {
    const stat = std.fs.cwd().statFile(path) catch return false;
    if (stat.kind != .file or stat.size == 0) return false;
    if (!jsonIntEquals(try jsonGetObject(artifact_value, "size"), stat.size)) return false;
    const hash_hex = try hashFileHex(allocator, path);
    return jsonStringEquals(try jsonGetObject(artifact_value, "sha256"), hash_hex[0..]);
}

fn projectCacheManifestValid(
    allocator: std.mem.Allocator,
    project_root: []const u8,
    kind: BuildCacheKind,
    key: ProjectCacheKey,
    artifact_path: []const u8,
    out_path: []const u8,
) bool {
    const manifest_path = projectCacheManifestPath(allocator, project_root, kind, key) catch return false;
    defer allocator.free(manifest_path);
    const manifest_bytes = readTextFileAlloc(allocator, manifest_path) catch return false;
    defer allocator.free(manifest_bytes);
    var parsed = std.json.parseFromSlice(std.json.Value, allocator, manifest_bytes, .{}) catch return false;
    defer parsed.deinit();
    if (!jsonIntEquals(jsonGetObject(parsed.value, "version") catch return false, 1)) return false;
    if (!jsonStringEquals(jsonGetObject(parsed.value, "kind") catch return false, kind.dirName())) return false;
    if (!jsonStringEquals(jsonGetObject(parsed.value, "key") catch return false, key.slice())) return false;
    if (!(projectCacheArtifactMatchesManifest(allocator, jsonGetObject(parsed.value, "artifact") catch return false, artifact_path) catch return false)) return false;
    if (!(projectCacheArtifactMatchesManifest(allocator, jsonGetObject(parsed.value, "output") catch return false, out_path) catch return false)) return false;
    return true;
}

fn writeCacheArtifactManifestEntry(writer: anytype, allocator: std.mem.Allocator, name: []const u8, path: []const u8) !void {
    const stat = try std.fs.cwd().statFile(path);
    const hash_hex = try hashFileHex(allocator, path);
    try writer.writeByte('"');
    try writer.writeAll(name);
    try writer.writeAll("\":{\"size\":");
    try writer.print("{d}", .{stat.size});
    try writer.writeAll(",\"sha256\":");
    try writeJsonString(writer, hash_hex[0..]);
    try writer.writeByte('}');
}

fn projectCacheWriteManifest(
    allocator: std.mem.Allocator,
    project_root: []const u8,
    kind: BuildCacheKind,
    key: ProjectCacheKey,
    cached_artifact: []const u8,
    cached_output: []const u8,
) !void {
    const manifest_path = try projectCacheManifestPath(allocator, project_root, kind, key);
    defer allocator.free(manifest_path);
    try ensureParentDir(manifest_path);
    var file = try std.fs.cwd().createFile(manifest_path, .{ .truncate = true });
    defer file.close();
    var writer = file.writer();
    try writer.writeAll("{\"version\":1,\"kind\":");
    try writeJsonString(writer, kind.dirName());
    try writer.writeAll(",\"key\":");
    try writeJsonString(writer, key.slice());
    try writer.writeByte(',');
    try writeCacheArtifactManifestEntry(writer, allocator, "artifact", cached_artifact);
    try writer.writeByte(',');
    try writeCacheArtifactManifestEntry(writer, allocator, "output", cached_output);
    try writer.writeAll("}\n");
}

fn projectCacheHit(
    allocator: std.mem.Allocator,
    project_root: []const u8,
    kind: BuildCacheKind,
    key: ProjectCacheKey,
    artifact_path: []const u8,
    out_path: []const u8,
) !bool {
    const cached_artifact = try projectCacheArtifactPath(allocator, project_root, kind, key, "artifact.sa.bc");
    defer allocator.free(cached_artifact);
    const cached_output = try projectCacheArtifactPath(allocator, project_root, kind, key, "output.bin");
    defer allocator.free(cached_output);
    const cached_test_metadata = if (kind == .test_cache) try projectCacheTestMetadataPath(allocator, project_root, key) else null;
    defer if (cached_test_metadata) |path| allocator.free(path);
    if (!projectCacheArtifactExistsNonEmpty(cached_artifact) or
        !projectCacheArtifactExistsNonEmpty(cached_output) or
        (if (cached_test_metadata) |path| !projectCacheArtifactExistsNonEmpty(path) else false) or
        !projectCacheManifestValid(allocator, project_root, kind, key, cached_artifact, cached_output))
    {
        projectCacheRemoveKey(allocator, project_root, kind, key);
        return false;
    }
    copyFileAlloc(allocator, cached_artifact, artifact_path) catch |err| {
        projectCacheRemoveKey(allocator, project_root, kind, key);
        return err;
    };
    copyFileAlloc(allocator, cached_output, out_path) catch |err| {
        projectCacheRemoveKey(allocator, project_root, kind, key);
        return err;
    };
    return true;
}

fn projectCacheStore(
    allocator: std.mem.Allocator,
    project_root: []const u8,
    kind: BuildCacheKind,
    key: ProjectCacheKey,
    artifact_path: []const u8,
    out_path: []const u8,
) !void {
    const cached_artifact = try projectCacheArtifactPath(allocator, project_root, kind, key, "artifact.sa.bc");
    defer allocator.free(cached_artifact);
    const cached_output = try projectCacheArtifactPath(allocator, project_root, kind, key, "output.bin");
    defer allocator.free(cached_output);
    try copyFileAlloc(allocator, artifact_path, cached_artifact);
    try copyFileAlloc(allocator, out_path, cached_output);
    try projectCacheWriteManifest(allocator, project_root, kind, key, cached_artifact, cached_output);
}

fn projectCacheTestMetadataPath(allocator: std.mem.Allocator, project_root: []const u8, key: ProjectCacheKey) ![]u8 {
    return try projectCacheArtifactPath(allocator, project_root, .test_cache, key, "test-metadata.json");
}

fn writeOptionalJsonString(writer: anytype, value: ?[]const u8) !void {
    if (value) |text| {
        try writeJsonString(writer, text);
    } else {
        try writer.writeAll("null");
    }
}

fn projectCacheWriteTestMetadata(
    allocator: std.mem.Allocator,
    project_root: []const u8,
    key: ProjectCacheKey,
    test_list: test_meta.TestList,
) !void {
    const metadata_path = try projectCacheTestMetadataPath(allocator, project_root, key);
    defer allocator.free(metadata_path);
    try ensureParentDir(metadata_path);
    var file = try std.fs.cwd().createFile(metadata_path, .{ .truncate = true });
    defer file.close();
    var writer = file.writer();
    try writer.writeAll("{\"version\":1,\"tests\":[");
    for (test_list.tests, 0..) |test_case, idx| {
        if (idx != 0) try writer.writeByte(',');
        try writer.writeAll("{\"id\":");
        try writer.print("{d}", .{test_case.desc.id});
        try writer.writeAll(",\"name\":");
        try writeJsonString(writer, test_case.desc.name);
        try writer.writeAll(",\"selector\":");
        try writeJsonString(writer, test_case.testfn.selector_name);
        try writer.writeAll(",\"source_file\":");
        try writeOptionalJsonString(writer, test_case.desc.source_file);
        try writer.writeAll(",\"line\":");
        try writer.print("{d}", .{test_case.desc.line});
        try writer.writeAll(",\"col\":");
        try writer.print("{d}", .{test_case.desc.col});
        try writer.writeAll(",\"ignored\":");
        try writer.writeAll(if (test_case.desc.ignored) "true" else "false");
        try writer.writeAll(",\"should_panic\":");
        try writer.writeAll(if (test_case.desc.should_panic) "true" else "false");
        try writer.writeByte('}');
    }
    try writer.writeAll("]}\n");
}

fn projectCacheStoreTest(
    allocator: std.mem.Allocator,
    project_root: []const u8,
    key: ProjectCacheKey,
    artifact_path: []const u8,
    out_path: []const u8,
    test_list: test_meta.TestList,
) !void {
    const cached_artifact = try projectCacheArtifactPath(allocator, project_root, .test_cache, key, "artifact.sa.bc");
    defer allocator.free(cached_artifact);
    const cached_output = try projectCacheArtifactPath(allocator, project_root, .test_cache, key, "output.bin");
    defer allocator.free(cached_output);
    try copyFileAlloc(allocator, artifact_path, cached_artifact);
    try copyFileAlloc(allocator, out_path, cached_output);
    try projectCacheWriteTestMetadata(allocator, project_root, key, test_list);
    try projectCacheWriteManifest(allocator, project_root, .test_cache, key, cached_artifact, cached_output);
}

fn jsonBool(value: std.json.Value) !bool {
    return switch (value) {
        .bool => |v| v,
        else => error.InvalidCacheManifest,
    };
}

fn jsonU32(value: std.json.Value) !u32 {
    return switch (value) {
        .integer => |v| if (v >= 0 and v <= std.math.maxInt(u32)) @intCast(v) else error.InvalidCacheManifest,
        else => error.InvalidCacheManifest,
    };
}

fn jsonStringDup(allocator: std.mem.Allocator, value: std.json.Value) ![]u8 {
    return switch (value) {
        .string => |text| try allocator.dupe(u8, text),
        else => error.InvalidCacheManifest,
    };
}

fn jsonOptionalStringDup(allocator: std.mem.Allocator, value: std.json.Value) !?[]u8 {
    return switch (value) {
        .null => null,
        .string => |text| try allocator.dupe(u8, text),
        else => error.InvalidCacheManifest,
    };
}

fn projectCacheReadTestMetadata(
    allocator: std.mem.Allocator,
    project_root: []const u8,
    key: ProjectCacheKey,
) !test_meta.TestList {
    const metadata_path = try projectCacheTestMetadataPath(allocator, project_root, key);
    defer allocator.free(metadata_path);
    const metadata_bytes = try readTextFileAlloc(allocator, metadata_path);
    defer allocator.free(metadata_bytes);
    var parsed = try std.json.parseFromSlice(std.json.Value, allocator, metadata_bytes, .{});
    defer parsed.deinit();
    if (!jsonIntEquals(try jsonGetObject(parsed.value, "version"), 1)) return error.InvalidCacheManifest;
    const tests_value = try jsonGetObject(parsed.value, "tests");
    const tests_array = switch (tests_value) {
        .array => |array| array.items,
        else => return error.InvalidCacheManifest,
    };

    var tests = std.ArrayList(test_meta.TestDescAndFn).init(allocator);
    errdefer {
        for (tests.items) |*test_case| test_case.deinit(allocator);
        tests.deinit();
    }
    for (tests_array) |item| {
        switch (item) {
            .object => {},
            else => return error.InvalidCacheManifest,
        }
        const name = try jsonStringDup(allocator, try jsonGetObject(item, "name"));
        errdefer allocator.free(name);
        const selector = try jsonStringDup(allocator, try jsonGetObject(item, "selector"));
        errdefer allocator.free(selector);
        const source_file = try jsonOptionalStringDup(allocator, try jsonGetObject(item, "source_file"));
        errdefer if (source_file) |file| allocator.free(file);
        try tests.append(.{
            .desc = .{
                .id = try jsonU32(try jsonGetObject(item, "id")),
                .name = name,
                .source_file = source_file,
                .line = try jsonU32(try jsonGetObject(item, "line")),
                .col = try jsonU32(try jsonGetObject(item, "col")),
                .ignored = try jsonBool(try jsonGetObject(item, "ignored")),
                .should_panic = try jsonBool(try jsonGetObject(item, "should_panic")),
            },
            .testfn = .{ .selector_name = selector },
        });
    }
    return .{ .tests = try tests.toOwnedSlice(), .order = .Unsorted };
}

fn isHexCacheKey(name: []const u8) bool {
    if (name.len != 64) return false;
    for (name) |c| {
        switch (c) {
            '0'...'9', 'a'...'f' => {},
            else => return false,
        }
    }
    return true;
}

fn cacheEntryExpired(stat: std.fs.File.Stat, max_age_days: u64) bool {
    if (max_age_days == 0) return false;
    const now = std.time.nanoTimestamp();
    if (stat.mtime >= now) return false;
    const max_age_ns = @as(i128, @intCast(max_age_days)) * 24 * 60 * 60 * std.time.ns_per_s;
    return now - stat.mtime > max_age_ns;
}

fn cacheFilePresentNonEmpty(dir: std.fs.Dir, name: []const u8) bool {
    const stat = dir.statFile(name) catch return false;
    return stat.kind == .file and stat.size != 0;
}

fn cacheDirPresent(dir: std.fs.Dir, name: []const u8) bool {
    const stat = dir.statFile(name) catch return false;
    return stat.kind == .directory;
}

fn cacheEntryComplete(kind: BuildCacheKind, entry_dir: std.fs.Dir) bool {
    return switch (kind) {
        .build_exe, .build_obj, .build_wasm => cacheFilePresentNonEmpty(entry_dir, "artifact.sa.bc") and cacheFilePresentNonEmpty(entry_dir, "output.bin") and cacheFilePresentNonEmpty(entry_dir, "manifest.json"),
        .test_cache => cacheFilePresentNonEmpty(entry_dir, "artifact.sa.bc") and cacheFilePresentNonEmpty(entry_dir, "output.bin") and cacheFilePresentNonEmpty(entry_dir, "manifest.json") and cacheFilePresentNonEmpty(entry_dir, "test-metadata.json"),
        .build_obj_incremental => cacheFilePresentNonEmpty(entry_dir, "manifest.json") and cacheDirPresent(entry_dir, "functions"),
    };
}

fn cacheEntryArtifactMatchesManifest(entry_dir: std.fs.Dir, artifact_value: std.json.Value, name: []const u8) !bool {
    const stat = entry_dir.statFile(name) catch return false;
    if (stat.kind != .file or stat.size == 0) return false;
    if (!jsonIntEquals(try jsonGetObject(artifact_value, "size"), stat.size)) return false;
    const hash_hex = try hashDirFileHex(entry_dir, name);
    return jsonStringEquals(try jsonGetObject(artifact_value, "sha256"), hash_hex[0..]);
}

fn cacheEntryManifestValid(kind: BuildCacheKind, key_name: []const u8, entry_dir: std.fs.Dir) bool {
    if (kind == .build_obj_incremental) return true;
    const manifest_bytes = entry_dir.readFileAlloc(std.heap.page_allocator, "manifest.json", 64 * 1024) catch return false;
    defer std.heap.page_allocator.free(manifest_bytes);
    var parsed = std.json.parseFromSlice(std.json.Value, std.heap.page_allocator, manifest_bytes, .{}) catch return false;
    defer parsed.deinit();
    if (!jsonIntEquals(jsonGetObject(parsed.value, "version") catch return false, 1)) return false;
    if (!jsonStringEquals(jsonGetObject(parsed.value, "kind") catch return false, kind.dirName())) return false;
    if (!jsonStringEquals(jsonGetObject(parsed.value, "key") catch return false, key_name)) return false;
    if (!(cacheEntryArtifactMatchesManifest(entry_dir, jsonGetObject(parsed.value, "artifact") catch return false, "artifact.sa.bc") catch return false)) return false;
    if (!(cacheEntryArtifactMatchesManifest(entry_dir, jsonGetObject(parsed.value, "output") catch return false, "output.bin") catch return false)) return false;
    return true;
}

fn cleanCacheKindDir(
    root_dir: std.fs.Dir,
    kind: BuildCacheKind,
    options: CacheCleanOptions,
    stats: *CacheCleanStats,
) !void {
    var kind_dir = root_dir.openDir(kind.dirName(), .{ .iterate = true }) catch |err| switch (err) {
        error.FileNotFound => return,
        error.NotDir => {
            stats.scanned += 1;
            stats.removed += 1;
            if (!options.dry_run) try root_dir.deleteFile(kind.dirName());
            return;
        },
        else => return err,
    };
    defer kind_dir.close();

    var iter = kind_dir.iterate();
    while (try iter.next()) |entry| {
        stats.scanned += 1;
        var remove = entry.kind != .directory or !isHexCacheKey(entry.name);
        if (!remove) {
            var entry_dir = kind_dir.openDir(entry.name, .{}) catch {
                remove = true;
                if (!options.dry_run) try kind_dir.deleteTree(entry.name);
                stats.removed += 1;
                continue;
            };
            defer entry_dir.close();

            const stat: ?std.fs.File.Stat = kind_dir.statFile(entry.name) catch null;
            remove = !cacheEntryComplete(kind, entry_dir) or
                !cacheEntryManifestValid(kind, entry.name, entry_dir) or
                (if (stat) |s| cacheEntryExpired(s, options.max_age_days) else true);
        }

        if (remove) {
            stats.removed += 1;
            if (!options.dry_run) {
                if (entry.kind == .directory) {
                    try kind_dir.deleteTree(entry.name);
                } else {
                    try kind_dir.deleteFile(entry.name);
                }
            }
        } else {
            stats.kept += 1;
        }
    }
}

fn cleanProjectCache(allocator: std.mem.Allocator, project_root: []const u8, options: CacheCleanOptions) !CacheCleanStats {
    const cache_root = try cacheRootPath(allocator, project_root);
    defer allocator.free(cache_root);
    var root_dir = std.fs.cwd().openDir(cache_root, .{ .iterate = true }) catch |err| switch (err) {
        error.FileNotFound => return .{},
        error.NotDir => {
            if (!options.dry_run) try std.fs.cwd().deleteFile(cache_root);
            return .{ .scanned = 1, .removed = 1 };
        },
        else => return err,
    };
    defer root_dir.close();

    var stats: CacheCleanStats = .{};
    try cleanCacheKindDir(root_dir, .build_exe, options, &stats);
    try cleanCacheKindDir(root_dir, .build_obj, options, &stats);
    try cleanCacheKindDir(root_dir, .build_wasm, options, &stats);
    try cleanCacheKindDir(root_dir, .build_obj_incremental, options, &stats);
    try cleanCacheKindDir(root_dir, .test_cache, options, &stats);
    return stats;
}

fn executeCacheCommand(allocator: std.mem.Allocator, args: []const []const u8, stdout: anytype) !u8 {
    if (args.len == 0 or isHelpFlag(args[0])) {
        try printCacheHelp(stdout, args);
        return 0;
    }
    if (!std.mem.eql(u8, args[0], "clean")) return error.UnknownCommand;

    var options: CacheCleanOptions = .{};
    var i: usize = 1;
    while (i < args.len) : (i += 1) {
        if (isHelpFlag(args[i])) {
            try printCacheHelp(stdout, args);
            return 0;
        }
        if (std.mem.eql(u8, args[i], "--dry-run")) {
            options.dry_run = true;
            continue;
        }
        if (std.mem.eql(u8, args[i], "--max-age-days")) {
            if (i + 1 >= args.len) return error.MissingArgument;
            options.max_age_days = try std.fmt.parseInt(u64, args[i + 1], 10);
            i += 1;
            continue;
        }
        if (std.mem.startsWith(u8, args[i], "--max-age-days=")) {
            options.max_age_days = try std.fmt.parseInt(u64, args[i]["--max-age-days=".len..], 10);
            continue;
        }
        return error.UnexpectedArgument;
    }

    const project_root = try projectRootDir(allocator);
    defer allocator.free(project_root);
    const stats = try cleanProjectCache(allocator, project_root, options);
    try stdout.print("cache clean: scanned={d} removed={d} kept={d} dry_run={} max_age_days={d}\n", .{ stats.scanned, stats.removed, stats.kept, options.dry_run, options.max_age_days });
    return 0;
}

fn projectFunctionCachePath(
    allocator: std.mem.Allocator,
    project_root: []const u8,
    key: ProjectCacheKey,
    function_key: []const u8,
) ![]u8 {
    const filename = try std.fmt.allocPrint(allocator, "{s}.o", .{function_key});
    defer allocator.free(filename);
    return try pathJoinAlloc(allocator, &.{ project_root, ".sa_cache", BuildCacheKind.build_obj_incremental.dirName(), key.slice(), "functions", filename });
}

fn projectFunctionCacheManifestPath(allocator: std.mem.Allocator, project_root: []const u8, key: ProjectCacheKey) ![]u8 {
    return try pathJoinAlloc(allocator, &.{ project_root, ".sa_cache", BuildCacheKind.build_obj_incremental.dirName(), key.slice(), "manifest.json" });
}

fn cacheFunctionSig(hasher: *std.crypto.hash.sha2.Sha256, sig_item: anytype) void {
    cacheBytes(hasher, sig_item.name);
    cacheU64(hasher, @intFromEnum(sig_item.kind));
    cacheBool(hasher, sig_item.return_fallible);
    cacheBool(hasher, sig_item.is_ffi_wrapper);
    cacheBool(hasher, sig_item.ignored);
    cacheBool(hasher, sig_item.should_panic);
    cacheU64(hasher, @intFromEnum(sig_item.return_ty));
    if (sig_item.return_cap) |cap| {
        cacheBool(hasher, true);
        cacheU64(hasher, @intFromEnum(cap));
    } else {
        cacheBool(hasher, false);
    }
    if (sig_item.llvm_name) |name| cacheBytes(hasher, name) else cacheBytes(hasher, "");
    for (sig_item.params) |param| {
        cacheBytes(hasher, param.name);
        cacheU64(hasher, @intFromEnum(param.ty));
        cacheU64(hasher, @intFromEnum(param.cap));
    }
}

fn computeFunctionObjectKey(allocator: std.mem.Allocator, source_path: []const u8, verified: *const referee.VerifyOk, sig_index: usize, start_idx: usize, end_idx: usize) ![]const u8 {
    var hasher = std.crypto.hash.sha2.Sha256.init(.{});
    cacheBytes(&hasher, "sa-build-obj-function-cache");
    cacheBytes(&hasher, cacheCompilerVersion());
    cacheBytes(&hasher, source_path);
    for (verified.function_sigs) |sig_item| {
        cacheFunctionSig(&hasher, sig_item);
    }
    for (verified.const_decls) |decl| {
        cacheBytes(&hasher, decl.raw_text);
    }
    cacheU64(&hasher, sig_index);
    cacheFunctionSig(&hasher, verified.function_sigs[sig_index]);
    for (verified.annotated[start_idx..end_idx]) |item| {
        cacheBytes(&hasher, item.base.raw_text);
    }
    var out: [32]u8 = undefined;
    hasher.final(&out);
    const hex = std.fmt.bytesToHex(out, .lower);
    return try allocator.dupe(u8, hex[0..]);
}

fn buildIncrementalObject(
    allocator: std.mem.Allocator,
    project_root: []const u8,
    cache_key: ProjectCacheKey,
    compiled: *const CompileOk,
    source_path: []const u8,
    out_path: []const u8,
    debug: bool,
    optimization: driver.Optimization,
    compile_options: CompileOptions,
    stderr: anytype,
) !void {
    const opt_level = emitOptLevel(debug, optimization);
    var object_paths = std.ArrayList([]const u8).init(allocator);
    defer {
        for (object_paths.items) |path| allocator.free(path);
        object_paths.deinit();
    }
    var function_keys = std.ArrayList([]const u8).init(allocator);
    defer {
        for (function_keys.items) |key| allocator.free(key);
        function_keys.deinit();
    }

    var sig_index: usize = 0;
    var idx: usize = 0;
    var task_idx: usize = 0;
    while (idx < compiled.verified.annotated.len) : (idx += 1) {
        const item = compiled.verified.annotated[idx].base;
        switch (item.kind) {
            .func_decl, .ffi_wrapper_decl, .extern_decl, .export_decl, .test_decl => {
                if (sig_index >= compiled.verified.function_sigs.len) return error.UnknownFunction;
                const current_sig_index = sig_index;
                sig_index += 1;

                var end = idx + 1;
                while (end < compiled.verified.annotated.len and switch (compiled.verified.annotated[end].base.kind) {
                    .func_decl, .ffi_wrapper_decl, .extern_decl, .export_decl, .test_decl => false,
                    else => true,
                }) : (end += 1) {}

                if (item.kind != .extern_decl) {
                    const function_key = try computeFunctionObjectKey(allocator, source_path, &compiled.verified, current_sig_index, idx, end);
                    var function_key_owned = true;
                    errdefer if (function_key_owned) allocator.free(function_key);
                    const object_path = try projectFunctionCachePath(allocator, project_root, cache_key, function_key);
                    var object_path_owned = true;
                    errdefer if (object_path_owned) allocator.free(object_path);
                    if (!projectPathExists(object_path)) {
                        try ensureParentDir(object_path);
                        try emit_llvm_llvmc.emitLlvmcToObject(
                            allocator,
                            compiled.verified,
                            &compiled.flat.def_dict,
                            compiled.flat.loc_table,
                            source_path,
                            nativeSizeBits(),
                            .{
                                .debug = debug,
                                .jobs = 1,
                                .opt_level = opt_level,
                                .function_task_index = task_idx,
                                .dce = compile_options.dce,
                            },
                            object_path,
                            opt_level,
                        );
                    }
                    try function_keys.append(function_key);
                    function_key_owned = false;
                    try object_paths.append(object_path);
                    object_path_owned = false;
                }

                task_idx += 1;
                idx = end - 1;
            },
            else => {},
        }
    }

    if (object_paths.items.len == 0) {
        return error.UnknownFunction;
    }

    try ensureParentDir(out_path);
    driver.compileRelocatableObj(allocator, object_paths.items, out_path, stderr) catch |err| switch (err) {
        error.ChildProcessFailed => return error.ChildProcessFailed,
        else => return err,
    };

    const manifest_path = try projectFunctionCacheManifestPath(allocator, project_root, cache_key);
    defer allocator.free(manifest_path);
    try ensureParentDir(manifest_path);
    var manifest_file = try std.fs.cwd().createFile(manifest_path, .{ .truncate = true });
    defer manifest_file.close();
    const writer = manifest_file.writer();
    try writer.writeAll("{\"version\":1,\"kind\":\"build-obj-incremental\",\"source\":");
    try writeJsonString(writer, source_path);
    try writer.writeAll(",\"cache_key\":");
    try writeJsonString(writer, cache_key.slice());
    try writer.writeAll(",\"functions\":[");
    for (function_keys.items, object_paths.items, 0..) |function_key, object_path, i| {
        if (i != 0) try writer.writeByte(',');
        try writer.writeAll("{\"key\":");
        try writeJsonString(writer, function_key);
        try writer.writeAll(",\"object\":");
        try writeJsonString(writer, object_path);
        try writer.writeByte('}');
    }
    try writer.writeAll("]}\n");
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
        \\.sa_cache/
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
    const source = try readManifestTextFileAlloc(allocator, "sa.mod");
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
        var entry_fetch_options = fetch_options;
        entry_fetch_options.expected_source_sha256 = entry.source_sha256;
        var result = try pkg_fetch.fetchPackage(allocator, entry.url, entry.ref, entry_fetch_options);
        defer result.deinit(allocator);
        if (!hashesEqual(result.source_sha256, entry.source_sha256)) return error.UpstreamShaMismatch;
        try stdout.print("{s}\n", .{result.root});
    }

    for (project_manifest.plugin_requires) |entry| {
        _ = entry.abi;
        _ = entry.ref;
        const code = try plugins.installFromPath(allocator, entry.identity, stdout, .{});
        if (code != 0) return code;
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

fn executePluginCommand(allocator: std.mem.Allocator, args: []const []const u8, stdout: anytype, stderr: anytype) !u8 {
    if (args.len == 0) {
        try stderr.writeAll("usage: sa plugin install [--dev] [--review] <path|sap.json> | list\n");
        return 1;
    }
    if (std.mem.eql(u8, args[0], "install")) {
        if (args.len < 2) {
            try stderr.writeAll("usage: sa plugin install [--dev] [--review] <path|sap.json>\n");
            return 1;
        }
        var dev = false;
        var review = false;
        var target: ?[]const u8 = null;
        for (args[1..]) |arg| {
            if (std.mem.eql(u8, arg, "--dev")) {
                dev = true;
                continue;
            }
            if (std.mem.eql(u8, arg, "--review")) {
                review = true;
                continue;
            }
            if (target == null) {
                target = arg;
                continue;
            }
            return error.UnexpectedArgument;
        }
        return try plugins.installFromPath(allocator, target orelse return error.MissingSourcePath, stdout, .{ .dev = dev, .review = review });
    }
    if (std.mem.eql(u8, args[0], "list")) {
        if (args.len > 1) return error.UnexpectedArgument;
        return try plugins.listInstalled(allocator, stdout);
    }
    try stderr.writeAll("usage: sa plugin install [--dev] [--review] <path|sap.json> | list\n");
    return 1;
}

fn saStdArchivePath(allocator: std.mem.Allocator) ![]u8 {
    const archive_name = switch (builtin.os.tag) {
        .windows => "sa_std.lib",
        else => "libsa_std.a",
    };
    if (builtin.is_test) {
        return try allocator.dupe(u8, build_options.sa_std_archive_path);
    }
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
                error.UnsupportedExtern => return 1,
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
    const project_root_owned = compile_options.project_root == null;
    const project_root = compile_options.project_root orelse try projectRootFromSourcePath(allocator, source_path);
    defer if (project_root_owned) allocator.free(project_root);
    var project_context = try loadProjectContext(allocator, project_root);
    defer project_context.deinit(allocator);
    const cache_key: ?ProjectCacheKey = if (compile_options.incremental_cache)
        try computeProjectBuildKey(allocator, &project_context, project_root, source_path, "exe", "", .build_exe, debug, optimization == .release_fast, false, null, true, compile_options.offline, compile_options.dce)
    else
        null;
    const artifact_path = try intermediateArtifactPath(allocator, out_path);
    defer allocator.free(artifact_path);

    if (cache_key) |key| {
        if (try projectCacheHit(allocator, project_root, .build_exe, key, artifact_path, out_path)) {
            try makeExecutable(out_path);
            if (diagnostics_mode == .json) {
                const metrics = CompileMetrics{ .compile_tokens = 0, .instruction_count = 0, .phases = if (compile_options.profile) .{ .load_ns = 0, .setup_ns = 0, .flatten_ns = 0, .verify_ns = 0, .emit_ns = 0, .link_ns = 0, .total_ns = if (total_start) |start| elapsedNs(start) else null } else null, .cache = .{ .kind = BuildCacheKind.build_exe.dirName(), .hit = true } };
                try writeSuccessJson(stderr, metrics);
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
                    dce_val: DceMode,
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
                                .opt_level = self.opt_level_val,
                                .codegen_unit_index = self.cgu_idx_val,
                                .codegen_unit_count = self.cgu_count_val,
                                .dce = self.dce_val,
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
                        .dce_val = compile_options.dce,
                        .cgu_idx_val = i,
                        .cgu_count_val = cgu_count,
                        .object_path_val = cgu_obj_paths[i],
                        .opt_level_val = emitOptLevel(debug, optimization),
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

                var link_inputs = std.ArrayList([]const u8).init(allocator);
                defer link_inputs.deinit();
                var owned_link_inputs = std.ArrayList([]const u8).init(allocator);
                defer {
                    for (owned_link_inputs.items) |arg| allocator.free(arg);
                    owned_link_inputs.deinit();
                }

                for (1..cgu_count) |i| {
                    try link_inputs.append(cgu_obj_paths[i]);
                }
                try appendNativePluginLinkInputs(allocator, &link_inputs, &owned_link_inputs, &owned.verified);

                const link_start = if (compile_options.profile) std.time.Instant.now() catch null else null;
                driver.compileExe(allocator, cgu_obj_paths[0], out_path, optimization, std_archive_path, link_inputs.items, debug, stderr) catch |err| switch (err) {
                    error.ChildProcessFailed => return 1,
                    else => return err,
                };
                const link_ns = if (link_start) |start| elapsedNs(start) else null;
                finishProfileMetrics(&owned.metrics, emit_ns, link_ns, if (total_start) |start| elapsedNs(start) else null);
            } else {
                try ensureParentDir(artifact_path);
                const emit_start = if (compile_options.profile) std.time.Instant.now() catch null else null;
                try emit_llvm_llvmc.emitLlvmcToFile(allocator, owned.verified, &owned.flat.def_dict, owned.flat.loc_table, source_path, nativeSizeBits(), .{ .debug = debug, .jobs = compile_options.jobs, .opt_level = emitOptLevel(debug, optimization), .dce = compile_options.dce }, artifact_path);
                const emit_ns = if (emit_start) |start| elapsedNs(start) else null;

                const link_start = if (compile_options.profile) std.time.Instant.now() catch null else null;
                var link_inputs = std.ArrayList([]const u8).init(allocator);
                defer link_inputs.deinit();
                var owned_link_inputs = std.ArrayList([]const u8).init(allocator);
                defer {
                    for (owned_link_inputs.items) |arg| allocator.free(arg);
                    owned_link_inputs.deinit();
                }
                try appendNativePluginLinkInputs(allocator, &link_inputs, &owned_link_inputs, &owned.verified);
                driver.compileExe(allocator, artifact_path, out_path, optimization, std_archive_path, link_inputs.items, debug, stderr) catch |err| switch (err) {
                    error.ChildProcessFailed => return 1,
                    else => return err,
                };
                const link_ns = if (link_start) |start| elapsedNs(start) else null;
                finishProfileMetrics(&owned.metrics, emit_ns, link_ns, if (total_start) |start| elapsedNs(start) else null);
                if (cache_key) |key| try projectCacheStore(allocator, project_root, .build_exe, key, artifact_path, out_path);
            }
            attachBackendIrMetrics(&owned.metrics, &owned.verified, debug);
            if (cache_key != null) owned.metrics.cache = .{ .kind = BuildCacheKind.build_exe.dirName(), .hit = false };

            if (diagnostics_mode == .json) {
                try writeSuccessJson(stderr, owned.metrics);
            }
            return 0;
        },
    }
}

fn executeBuildObj(allocator: std.mem.Allocator, source_path: []const u8, out_path: []const u8, debug: bool, optimization: driver.Optimization, incremental: bool, compile_options: CompileOptions, stderr: anytype, diagnostics_mode: DiagnosticsMode) !u8 {
    const total_start = if (compile_options.profile) std.time.Instant.now() catch null else null;
    const project_root_owned = compile_options.project_root == null;
    const project_root = compile_options.project_root orelse try projectRootFromSourcePath(allocator, source_path);
    defer if (project_root_owned) allocator.free(project_root);
    var project_context = try loadProjectContext(allocator, project_root);
    defer project_context.deinit(allocator);
    const cache_key: ?ProjectCacheKey = if (compile_options.incremental_cache)
        try computeProjectBuildKey(allocator, &project_context, project_root, source_path, "obj", "", .build_obj, debug, optimization == .release_fast, incremental, null, true, compile_options.offline, compile_options.dce)
    else
        null;
    const artifact_path = try intermediateArtifactPath(allocator, out_path);
    defer allocator.free(artifact_path);

    if (cache_key) |key| {
        if (try projectCacheHit(allocator, project_root, .build_obj, key, artifact_path, out_path)) {
            if (diagnostics_mode == .json) {
                const metrics = CompileMetrics{ .compile_tokens = 0, .instruction_count = 0, .phases = if (compile_options.profile) .{ .load_ns = 0, .setup_ns = 0, .flatten_ns = 0, .verify_ns = 0, .emit_ns = 0, .link_ns = 0, .total_ns = if (total_start) |start| elapsedNs(start) else null } else null, .cache = .{ .kind = BuildCacheKind.build_obj.dirName(), .hit = true } };
                try writeSuccessJson(stderr, metrics);
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
            try ensureParentDir(artifact_path);
            const emit_start = if (compile_options.profile) std.time.Instant.now() catch null else null;
            const opt_level = emitOptLevel(debug, optimization);
            if (incremental) {
                const incremental_key = try computeProjectBuildKey(allocator, &project_context, project_root, source_path, "obj", "", .build_obj_incremental, debug, optimization == .release_fast, true, null, false, compile_options.offline, compile_options.dce);
                try buildIncrementalObject(allocator, project_root, incremental_key, &owned, source_path, out_path, debug, optimization, compile_options, stderr);
                try emit_llvm_llvmc.emitLlvmcToFile(allocator, owned.verified, &owned.flat.def_dict, owned.flat.loc_table, source_path, nativeSizeBits(), .{ .debug = debug, .jobs = compile_options.jobs, .opt_level = opt_level, .dce = compile_options.dce }, artifact_path);
            } else {
                try emit_llvm_llvmc.emitLlvmcToArtifacts(allocator, owned.verified, &owned.flat.def_dict, owned.flat.loc_table, source_path, nativeSizeBits(), .{ .debug = debug, .jobs = compile_options.jobs, .opt_level = opt_level, .dce = compile_options.dce }, artifact_path, out_path, opt_level);
            }
            finishProfileMetrics(&owned.metrics, if (emit_start) |start| elapsedNs(start) else null, null, if (total_start) |start| elapsedNs(start) else null);
            attachBackendIrMetrics(&owned.metrics, &owned.verified, debug);
            if (cache_key) |key| try projectCacheStore(allocator, project_root, .build_obj, key, artifact_path, out_path);
            if (cache_key != null) owned.metrics.cache = .{ .kind = BuildCacheKind.build_obj.dirName(), .hit = false };
            if (diagnostics_mode == .json) {
                try writeSuccessJson(stderr, owned.metrics);
            }
            return 0;
        },
    }
}

fn executeBuildWasm(allocator: std.mem.Allocator, source_path: []const u8, out_path: []const u8, target: WasmTarget, debug: bool, optimization: driver.Optimization, compile_options: CompileOptions, stderr: anytype, diagnostics_mode: DiagnosticsMode) !u8 {
    const total_start = if (compile_options.profile) std.time.Instant.now() catch null else null;
    const project_root_owned = compile_options.project_root == null;
    const project_root = compile_options.project_root orelse try projectRootFromSourcePath(allocator, source_path);
    defer if (project_root_owned) allocator.free(project_root);
    var project_context = try loadProjectContext(allocator, project_root);
    defer project_context.deinit(allocator);
    const cache_key: ?ProjectCacheKey = if (compile_options.incremental_cache)
        try computeProjectBuildKey(allocator, &project_context, project_root, source_path, "wasm", target.triple, .build_wasm, debug, optimization == .release_fast, false, target, true, compile_options.offline, compile_options.dce)
    else
        null;
    const artifact_path = try intermediateArtifactPath(allocator, out_path);
    defer allocator.free(artifact_path);

    if (cache_key) |key| {
        if (try projectCacheHit(allocator, project_root, .build_wasm, key, artifact_path, out_path)) {
            if (diagnostics_mode == .json) {
                const metrics = CompileMetrics{ .compile_tokens = 0, .instruction_count = 0, .phases = if (compile_options.profile) .{ .load_ns = 0, .setup_ns = 0, .flatten_ns = 0, .verify_ns = 0, .emit_ns = 0, .link_ns = 0, .total_ns = if (total_start) |start| elapsedNs(start) else null } else null, .cache = .{ .kind = BuildCacheKind.build_wasm.dirName(), .hit = true } };
                try writeSuccessJson(stderr, metrics);
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
            try ensureParentDir(artifact_path);
            try emit_llvm_llvmc.emitLlvmcToFile(allocator, owned.verified, &owned.flat.def_dict, owned.flat.loc_table, source_path, target.size_bits, .{ .debug = debug, .wasm_compat = true, .jobs = compile_options.jobs, .opt_level = emitOptLevel(debug, optimization), .dce = compile_options.dce }, artifact_path);

            driver.compileWasm(allocator, artifact_path, out_path, .{ .triple = target.triple, .no_entry = target.no_entry }, optimization, debug, stderr) catch |err| switch (err) {
                error.ChildProcessFailed => return 1,
                else => return err,
            };
            if (cache_key) |key| try projectCacheStore(allocator, project_root, .build_wasm, key, artifact_path, out_path);
            if (cache_key != null) owned.metrics.cache = .{ .kind = BuildCacheKind.build_wasm.dirName(), .hit = false };
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
            var plugin_import_roots: []const []const u8 = &.{};
            defer if (plugin_import_roots.len != 0) freeOwnedStringSlice(allocator, plugin_import_roots);
            if (project_manifest) |*m| {
                dependencies = try manifestDependencies(m, allocator);
                plugin_import_roots = try manifestPluginImportRoots(m, allocator);
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
                .plugin_import_roots = plugin_import_roots,
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

fn emitOptLevel(debug: bool, optimization: driver.Optimization) u8 {
    if (debug) return 0;
    return switch (optimization) {
        .release_small => 1,
        .release_fast => 3,
    };
}

fn executeTest(
    allocator: std.mem.Allocator,
    source_path: []const u8,
    compile_options: CompileOptions,
    test_options: TestCommandOptions,
    stdout: anytype,
    stderr: anytype,
    diagnostics_mode: DiagnosticsMode,
) !u8 {
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
    const exe_full_path = try std.fs.path.join(allocator, &.{ artifact_dir, exe_name });
    defer allocator.free(exe_full_path);

    const project_root_owned = compile_options.project_root == null;
    const project_root = compile_options.project_root orelse try projectRootFromSourcePath(allocator, source_path);
    defer if (project_root_owned) allocator.free(project_root);
    var project_context = try loadProjectContext(allocator, project_root);
    defer project_context.deinit(allocator);
    const cache_key: ?ProjectCacheKey = if (compile_options.incremental_cache)
        try computeProjectBuildKey(allocator, &project_context, project_root, source_path, "test", "", .test_cache, false, false, false, null, true, compile_options.offline, compile_options.dce)
    else
        null;

    if (cache_key) |key| cached: {
        var cached_test_list = projectCacheReadTestMetadata(allocator, project_root, key) catch |err| {
            _ = @errorName(err);
            break :cached;
        };
        const hit = projectCacheHit(allocator, project_root, .test_cache, key, artifact_full_path, exe_full_path) catch |err| {
            cached_test_list.deinit(allocator);
            return err;
        };
        if (hit) {
            makeExecutable(exe_full_path) catch |err| {
                cached_test_list.deinit(allocator);
                return err;
            };
            if (test_options.list) {
                defer cached_test_list.deinit(allocator);
                try test_formatter.writeList(stdout, cached_test_list.tests, test_options.selection);
                return 0;
            }
            if (test_options.compile_only) {
                defer cached_test_list.deinit(allocator);
                try stdout.print(
                    "compiled {d} selected tests ({d} discovered)\n",
                    .{
                        test_options.selection.countSelected(cached_test_list.tests),
                        cached_test_list.tests.len,
                    },
                );
                return 0;
            }
            return try test_runner.run(
                allocator,
                exe_full_path,
                tmp.dir,
                &cached_test_list,
                test_options.selection,
                test_options.trace_panic,
                compile_options.jobs,
                stdout.any(),
                stderr.any(),
            );
        }
        cached_test_list.deinit(allocator);
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

            var test_list = try test_meta.collect(allocator, owned.verified.function_sigs);
            if (test_options.list) {
                defer test_list.deinit(allocator);
                try test_formatter.writeList(stdout, test_list.tests, test_options.selection);
                return 0;
            }

            var link_inputs = std.ArrayList([]const u8).init(allocator);
            defer link_inputs.deinit();
            var owned_link_inputs = std.ArrayList([]const u8).init(allocator);
            defer {
                for (owned_link_inputs.items) |arg| allocator.free(arg);
                owned_link_inputs.deinit();
            }
            try appendNativePluginLinkInputs(allocator, &link_inputs, &owned_link_inputs, &owned.verified);

            try emit_llvm_llvmc.emitLlvmcToFile(allocator, owned.verified, &owned.flat.def_dict, owned.flat.loc_table, source_path, nativeSizeBits(), .{ .jobs = compile_options.jobs, .test_mode = true, .dce = compile_options.dce }, artifact_full_path);

            driver.compileExe(allocator, artifact_full_path, exe_full_path, .release_small, std_archive_path, link_inputs.items, false, stderr) catch |err| switch (err) {
                error.ChildProcessFailed => return 1,
                else => return err,
            };

            if (cache_key) |key| {
                if (link_inputs.items.len == 0) try projectCacheStoreTest(allocator, project_root, key, artifact_full_path, exe_full_path, test_list);
            }

            if (test_options.compile_only) {
                defer test_list.deinit(allocator);
                try stdout.print(
                    "compiled {d} selected tests ({d} discovered)\n",
                    .{
                        test_options.selection.countSelected(test_list.tests),
                        test_list.tests.len,
                    },
                );
                return 0;
            }

            return try test_runner.run(
                allocator,
                exe_full_path,
                tmp.dir,
                &test_list,
                test_options.selection,
                test_options.trace_panic,
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
        if (isHelpFlag(args[1])) {
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

    const cmd: Command = if (commandFromName(args[1])) |known| known else {
        var plugin_auth = try buildPluginRuntimeAuthorization(allocator, args);
        defer plugin_auth.deinit(allocator);
        var plugin_runtime = try plugins.Runtime.initFromEnvWithAuthorization(allocator, plugin_auth.input);
        defer plugin_runtime.deinit();
        if (try plugin_runtime.dispatchCommand(args, stdout, stderr, json_mode)) |code| return code;
        return error.UnknownCommand;
    };

    if (commandHelpRequested(cmd, args)) {
        try printCommandHelp(stdout, cmd, args[2..]);
        return 0;
    }

    switch (cmd) {
        .help => {
            return try printHelpTopic(stdout, args[2..]);
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
        .pkg => {
            var plugin_auth = try buildPluginRuntimeAuthorization(allocator, args);
            defer plugin_auth.deinit(allocator);
            var plugin_runtime = try plugins.Runtime.initFromEnvWithAuthorization(allocator, plugin_auth.input);
            defer plugin_runtime.deinit();
            if (try plugin_runtime.dispatchCommand(args, stdout, stderr, json_mode)) |code| return code;
            return error.UnknownCommand;
        },
        .cache => return try executeCacheCommand(allocator, args[2..], stdout),
        .audit => return error.UnknownCommand,
        .explain => return try explainCommand(stdout, args, json_mode),
        .fix => return try fixCommand(stdout, args, json_mode),
        .skills => return try skillsCommand(allocator, stdout, json_mode),
        .init => return try executeInit(allocator, args[2..], stdout),
        .install => return try executeInstall(allocator, args[2..], stdout),
        .plugin => return try executePluginCommand(allocator, args[2..], stdout, stderr),
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
            var incremental = false;
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
                if (std.mem.eql(u8, args[i], "--incremental")) {
                    incremental = true;
                    continue;
                }
                return error.UnexpectedArgument;
            }
            const owned_out = if (out_path) |p| p else try deriveOutputPath(allocator, source_path, ".o");
            defer if (out_path == null) allocator.free(owned_out);
            return try executeBuildObj(allocator, source_path, if (out_path) |p| p else owned_out, debug, optimization, incremental, compile_options, stderr, if (json_mode) .json else .human);
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
            var list_tests = false;
            var compile_only = false;
            var trace_panic = false;
            var i: usize = 3;
            while (i < args.len) : (i += 1) {
                if (try consumeCompileOption(args[i], args, &i, &compile_options)) continue;
                if (std.mem.eql(u8, args[i], "--list")) {
                    list_tests = true;
                    continue;
                }
                if (std.mem.eql(u8, args[i], "--compile-only")) {
                    compile_only = true;
                    continue;
                }
                if (std.mem.eql(u8, args[i], "--trace-panic") or std.mem.eql(u8, args[i], "--test-debug")) {
                    trace_panic = true;
                    continue;
                }
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
            return try executeTest(allocator, source_path, compile_options, .{
                .selection = selection,
                .list = list_tests,
                .compile_only = compile_only,
                .trace_panic = trace_panic,
            }, stdout, stderr, if (json_mode) .json else .human);
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

test "source tree hash cache reuses mtime size digest without reloading unchanged files" {
    var original_cwd = try std.fs.cwd().openDir(".", .{});
    defer original_cwd.close();
    var tmp = std.testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();

    try tmp.dir.setAsCwd();
    defer original_cwd.setAsCwd() catch {};

    try tmp.dir.makePath("sa_std/core");

    {
        var file = try tmp.dir.createFile("main.sa", .{ .truncate = true });
        defer file.close();
        try file.writeAll(
            \\@import "sa_std/core/cache_probe.sai"
            \\@main() -> i32:
            \\return dep_value
            \\
        );
    }
    {
        var file = try tmp.dir.createFile("sa_std/core/cache_probe.sai", .{ .truncate = true });
        defer file.close();
        try file.writeAll("#def dep_value = 7\n");
    }

    const project_root = try std.fs.cwd().realpathAlloc(std.testing.allocator, ".");
    defer std.testing.allocator.free(project_root);
    const std_root = try std.fs.cwd().realpathAlloc(std.testing.allocator, "sa_std");
    defer std.testing.allocator.free(std_root);

    test_source_tree_load_count = 0;
    var first_hasher = std.crypto.hash.sha2.Sha256.init(.{});
    try hashResolvedSourceTree(std.testing.allocator, &first_hasher, &.{}, &.{}, project_root, std_root, false, "main.sa");
    var first_digest: [32]u8 = undefined;
    first_hasher.final(&first_digest);
    try std.testing.expectEqual(@as(usize, 1), test_source_tree_load_count);

    const resolve_ctx = flattener.ResolveContext{ .options = .{ .project_root = project_root, .std_root = std_root } };
    var warmed_import = try flattener.readImportSourceFile(std.testing.allocator, ".", "sa_std/core/cache_probe.sai", resolve_ctx);
    defer warmed_import.deinit(std.testing.allocator);
    try std.testing.expect(warmed_import.owned_source == null);

    var second_hasher = std.crypto.hash.sha2.Sha256.init(.{});
    try hashResolvedSourceTree(std.testing.allocator, &second_hasher, &.{}, &.{}, project_root, std_root, false, "main.sa");
    var second_digest: [32]u8 = undefined;
    second_hasher.final(&second_digest);
    try std.testing.expectEqual(@as(usize, 1), test_source_tree_load_count);
    try std.testing.expectEqualSlices(u8, first_digest[0..], second_digest[0..]);

    {
        var file = try tmp.dir.createFile("sa_std/core/cache_probe.sai", .{ .truncate = true });
        defer file.close();
        try file.writeAll("#def dep_value = 777\n");
    }

    var third_hasher = std.crypto.hash.sha2.Sha256.init(.{});
    try hashResolvedSourceTree(std.testing.allocator, &third_hasher, &.{}, &.{}, project_root, std_root, false, "main.sa");
    var third_digest: [32]u8 = undefined;
    third_hasher.final(&third_digest);
    try std.testing.expect(test_source_tree_load_count > 1);
    try std.testing.expect(!std.mem.eql(u8, first_digest[0..], third_digest[0..]));
}

test "source tree hash cache LRU is opt-in" {
    const previous_limit = test_source_tree_hash_cache_max_entries;
    test_source_tree_hash_cache_max_entries = 1;
    defer test_source_tree_hash_cache_max_entries = previous_limit;

    var original_cwd = try std.fs.cwd().openDir(".", .{});
    defer original_cwd.close();
    var tmp = std.testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();

    try tmp.dir.setAsCwd();
    defer original_cwd.setAsCwd() catch {};

    {
        var file = try tmp.dir.createFile("a.sa", .{ .truncate = true });
        defer file.close();
        try file.writeAll(
            \\@main() -> i32:
            \\return 1
            \\
        );
    }
    {
        var file = try tmp.dir.createFile("b.sa", .{ .truncate = true });
        defer file.close();
        try file.writeAll(
            \\@main() -> i32:
            \\return 2
            \\
        );
    }

    const project_root = try std.fs.cwd().realpathAlloc(std.testing.allocator, ".");
    defer std.testing.allocator.free(project_root);

    test_source_tree_load_count = 0;
    var first_hasher = std.crypto.hash.sha2.Sha256.init(.{});
    try hashResolvedSourceTree(std.testing.allocator, &first_hasher, &.{}, &.{}, project_root, project_root, false, "a.sa");
    try std.testing.expectEqual(@as(usize, 1), test_source_tree_load_count);

    var second_hasher = std.crypto.hash.sha2.Sha256.init(.{});
    try hashResolvedSourceTree(std.testing.allocator, &second_hasher, &.{}, &.{}, project_root, project_root, false, "b.sa");
    try std.testing.expectEqual(@as(usize, 2), test_source_tree_load_count);

    var second_hit_hasher = std.crypto.hash.sha2.Sha256.init(.{});
    try hashResolvedSourceTree(std.testing.allocator, &second_hit_hasher, &.{}, &.{}, project_root, project_root, false, "b.sa");
    try std.testing.expectEqual(@as(usize, 2), test_source_tree_load_count);

    var first_again_hasher = std.crypto.hash.sha2.Sha256.init(.{});
    try hashResolvedSourceTree(std.testing.allocator, &first_again_hasher, &.{}, &.{}, project_root, project_root, false, "a.sa");
    try std.testing.expectEqual(@as(usize, 3), test_source_tree_load_count);
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
    try std.testing.expectEqualStrings("pin-import", import_report.repair_action.?);

    const type_source =
        \\@test "probe":
        \\    point = call @support_make_point(10, 20)
    ;
    const type_report = trapFromFlattenError("/tmp/type.sa", type_source, error.UnsupportedType, 2);
    try std.testing.expectEqual(trap.Trap.unsupported_type, type_report.trap);
    try std.testing.expectEqualStrings("/tmp/type.sa", type_report.file.?);
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
