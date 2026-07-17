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
const sab = @import("sab.zig");
const plugins = @import("plugins.zig");
const manifest = @import("pkg/manifest.zig");
const pkg_audit = @import("pkg/audit.zig");
const pkg_ci = @import("pkg/ci.zig");
const pkg_confirm = @import("pkg/confirm.zig");
const pkg_fetch = @import("pkg/fetch.zig");
const pkg_mirror = @import("pkg/mirror.zig");
const pkg_resolver = @import("pkg/resolver.zig");
const pkg_sum = @import("pkg/sum.zig");
const pkg_workspace = @import("pkg/workspace.zig");
const referee_call = @import("referee/call.zig");
const referee = @import("referee.zig");
const test_formatter = @import("test_formatter.zig");
const test_meta = @import("test_meta.zig");
const test_runner = @import("test_runner.zig");
const trap = @import("common/trap.zig");
const affected_tests = @import("affected_tests.zig");
const daemon_cancel = @import("daemon_cancel.zig");
const daemon_client = @import("daemon_client.zig");
const incr_verify = @import("incr_verify.zig");
const common_signature = @import("common/signature.zig");
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

const CheckOk = struct {
    metrics: CompileMetrics,

    fn deinit(self: *CheckOk, allocator: std.mem.Allocator) void {
        _ = allocator;
        self.* = undefined;
    }
};

const CheckCompileResult = union(enum) {
    ok: CheckOk,
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

const VerifierMemoryMetrics = struct {
    start_rss_bytes: ?u64 = null,
    after_classify_rss_bytes: ?u64 = null,
    after_metadata_rss_bytes: ?u64 = null,
    after_chunks_rss_bytes: ?u64 = null,
    parallel_start_rss_bytes: ?u64 = null,
    parallel_after_worker_allocators_rss_bytes: ?u64 = null,
    parallel_after_body_rss_bytes: ?u64 = null,
    parallel_merge_rss_bytes: ?u64 = null,
    after_body_rss_bytes: ?u64 = null,
    after_finalize_rss_bytes: ?u64 = null,
    empty_rss_bytes: ?u64 = null,
};

const CompileMemoryMetrics = struct {
    start_rss_bytes: ?u64 = null,
    after_load_rss_bytes: ?u64 = null,
    after_setup_rss_bytes: ?u64 = null,
    after_flatten_rss_bytes: ?u64 = null,
    after_verify_rss_bytes: ?u64 = null,
    after_emit_rss_bytes: ?u64 = null,
    after_link_rss_bytes: ?u64 = null,
    end_rss_bytes: ?u64 = null,
    peak_rss_bytes: ?u64 = null,
    verifier: VerifierMemoryMetrics = .{},

    fn updatePeak(self: *CompileMemoryMetrics, rss: ?u64) void {
        const value = rss orelse return;
        if (self.peak_rss_bytes == null or value > self.peak_rss_bytes.?) {
            self.peak_rss_bytes = value;
        }
    }

    fn recordStart(self: *CompileMemoryMetrics) void {
        const rss = currentRssBytes();
        self.start_rss_bytes = rss;
        self.updatePeak(rss);
    }

    fn recordAfterLoad(self: *CompileMemoryMetrics) void {
        const rss = currentRssBytes();
        self.after_load_rss_bytes = rss;
        self.updatePeak(rss);
    }

    fn recordAfterSetup(self: *CompileMemoryMetrics) void {
        const rss = currentRssBytes();
        self.after_setup_rss_bytes = rss;
        self.updatePeak(rss);
    }

    fn recordAfterFlatten(self: *CompileMemoryMetrics) void {
        const rss = currentRssBytes();
        self.after_flatten_rss_bytes = rss;
        self.updatePeak(rss);
    }

    fn recordAfterVerify(self: *CompileMemoryMetrics) void {
        const rss = currentRssBytes();
        self.after_verify_rss_bytes = rss;
        self.updatePeak(rss);
    }

    fn recordAfterEmit(self: *CompileMemoryMetrics) void {
        const rss = currentRssBytes();
        self.after_emit_rss_bytes = rss;
        self.updatePeak(rss);
    }

    fn recordAfterLink(self: *CompileMemoryMetrics) void {
        const rss = currentRssBytes();
        self.after_link_rss_bytes = rss;
        self.updatePeak(rss);
    }

    fn recordEnd(self: *CompileMemoryMetrics) void {
        const rss = currentRssBytes();
        self.end_rss_bytes = rss;
        self.updatePeak(rss);
    }

    fn recordVerifierStage(self: *CompileMemoryMetrics, stage: []const u8, rss: ?u64) void {
        if (std.mem.eql(u8, stage, "start")) {
            self.verifier.start_rss_bytes = rss;
        } else if (std.mem.eql(u8, stage, "after_classify")) {
            self.verifier.after_classify_rss_bytes = rss;
        } else if (std.mem.eql(u8, stage, "after_metadata")) {
            self.verifier.after_metadata_rss_bytes = rss;
        } else if (std.mem.eql(u8, stage, "after_chunks")) {
            self.verifier.after_chunks_rss_bytes = rss;
        } else if (std.mem.eql(u8, stage, "parallel_start")) {
            self.verifier.parallel_start_rss_bytes = rss;
        } else if (std.mem.eql(u8, stage, "parallel_after_worker_allocators")) {
            self.verifier.parallel_after_worker_allocators_rss_bytes = rss;
        } else if (std.mem.eql(u8, stage, "parallel_after_body")) {
            self.verifier.parallel_after_body_rss_bytes = rss;
        } else if (std.mem.eql(u8, stage, "parallel_merge")) {
            self.verifier.parallel_merge_rss_bytes = rss;
        } else if (std.mem.eql(u8, stage, "after_body")) {
            self.verifier.after_body_rss_bytes = rss;
        } else if (std.mem.eql(u8, stage, "after_finalize")) {
            self.verifier.after_finalize_rss_bytes = rss;
        } else if (std.mem.eql(u8, stage, "empty")) {
            self.verifier.empty_rss_bytes = rss;
        }
        self.updatePeak(rss);
    }
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
    memory: ?CompileMemoryMetrics = null,
    backend_ir: ?BackendIrMetrics = null,
    cache: ?BuildCacheMetrics = null,
};

const BuildCacheMetrics = struct {
    kind: []const u8,
    hit: bool,
    reason: ?[]const u8 = null,
};

fn computeCompileMetrics(flat: *const flattener.FlattenResult, verified: *const referee.VerifyOk, phases: ?CompilePhaseMetrics, memory: ?CompileMemoryMetrics) CompileMetrics {
    const compile_tokens = @as(u64, flat.instructions.len) + @as(u64, flat.const_decls.len) + @as(u64, flat.function_sigs.len) + @as(u64, flat.test_sigs.len) + @as(u64, verified.annotated.len);
    return .{
        .compile_tokens = compile_tokens,
        .instruction_count = @as(u64, verified.annotated.len),
        .phases = phases,
        .memory = memory,
    };
}

fn computeCheckMetrics(flat: *const flattener.FlattenResult, verdict: referee.VerdictOnlyOk, phases: ?CompilePhaseMetrics, memory: ?CompileMemoryMetrics) CompileMetrics {
    return .{
        .compile_tokens = @as(u64, flat.instructions.len) * 2 + @as(u64, flat.const_decls.len) + @as(u64, flat.function_sigs.len) + @as(u64, flat.test_sigs.len),
        .instruction_count = @as(u64, flat.instructions.len),
        .phases = phases,
        .memory = memory,
        .cache = .{ .kind = "verify-verdict-v2", .hit = verdict.cache_hit },
    };
}

fn currentRssBytes() ?u64 {
    if (builtin.os.tag != .linux) return null;

    var file = std.fs.openFileAbsolute("/proc/self/statm", .{}) catch return null;
    defer file.close();

    var buf: [128]u8 = undefined;
    const n = file.readAll(&buf) catch return null;
    var it = std.mem.tokenizeAny(u8, buf[0..n], " \t\r\n");
    _ = it.next() orelse return null;
    const rss_pages_text = it.next() orelse return null;
    const rss_pages = std.fmt.parseInt(u64, rss_pages_text, 10) catch return null;
    const page_size: u64 = @intCast(std.heap.pageSize());
    return rss_pages * page_size;
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

fn recordMetricMemoryAfterEmit(metrics: *CompileMetrics) void {
    if (metrics.memory) |*memory| memory.recordAfterEmit();
}

fn recordMetricMemoryAfterLink(metrics: *CompileMetrics) void {
    if (metrics.memory) |*memory| memory.recordAfterLink();
}

fn recordMetricMemoryEnd(metrics: *CompileMetrics) void {
    if (metrics.memory) |*memory| memory.recordEnd();
}

fn cacheHitMemoryMetrics(enabled: bool) ?CompileMemoryMetrics {
    if (!enabled) return null;
    var memory = CompileMemoryMetrics{};
    memory.recordStart();
    memory.recordEnd();
    return memory;
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
    package_name: ?[]const u8 = null,
    project_root: ?[]const u8 = null,
    profile: bool = false,
    mem_report: bool = false,
    mem_report_live: bool = false,
    stdin_reader: ?std.io.AnyReader = null,
    stdin_is_tty: ?bool = null,
    diagnostic_writer: ?std.io.AnyWriter = null,
    sab_selected_test_names: []const []const u8 = &.{},
};

const TestCommandOptions = struct {
    selection: test_meta.TestSelection,
    list: bool = false,
    compile_only: bool = false,
    trace_panic: bool = false,
    affected: bool = false,
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
    build_workspace,
    build_exe,
    build_wasm,
    build_obj,
    bc2sa,
    audit,
    check,
    graph,
    layout,
    fetch,
    size,
    test_cmd,
    explain,
    fix,
    skills,
    daemon,
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
    member_root_path: []const u8,
    workspace_manifest_path: []const u8,
    member_manifest_path: []const u8,
    manifest: ?manifest.Manifest,
    workspace_manifest: ?manifest.Manifest,
    member_manifest: ?manifest.Manifest,
    lock_file: ?manifest.LockFile,
    sum_file: ?manifest.SumFile,

    fn deinit(self: *ProjectContext, allocator: std.mem.Allocator) void {
        if (self.manifest) |*m| m.deinit(allocator);
        if (self.workspace_manifest) |*m| m.deinit(allocator);
        if (self.member_manifest) |*m| m.deinit(allocator);
        if (self.lock_file) |*lock| lock.deinit(allocator);
        if (self.sum_file) |*sum| sum.deinit(allocator);
        allocator.free(self.root_path);
        allocator.free(self.member_root_path);
        allocator.free(self.workspace_manifest_path);
        allocator.free(self.member_manifest_path);
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

fn projectSourcePath(allocator: std.mem.Allocator, root_path: []const u8, package_name: ?[]const u8) ![]u8 {
    var resolved = try pkg_workspace.resolveFromRootPath(allocator, root_path, .{ .request = package_name });
    defer resolved.deinit(allocator);
    return try pkg_workspace.selectedSourcePath(allocator, &resolved);
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

fn loadProjectContext(allocator: std.mem.Allocator, root_path: []const u8, package_name: ?[]const u8) !ProjectContext {
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
        .build_workspace => "build-workspace",
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
        .check => "check",
        .graph => "graph",
        .fetch => "fetch",
        .layout => "layout",
        .size => "size",
        .test_cmd => "test",
        .explain => "explain",
        .fix => "fix",
        .skills => "skills",
        .daemon => "daemon",
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
    try writer.writeAll("  --project-root <dir>           Use a specific project root for package resolution and .sa_cache\n");
    try writer.writeAll("  --profile                      Include compile phase timings in JSON metrics\n");
    try writer.writeAll("  --mem-report                   Print compile RSS stage samples; JSON mode includes metrics\n");
    try writer.writeAll("  --offline                      Use local package cache only\n");
    try writer.writeAll("  --ci                           Use CI package preflight behavior\n");
    try writer.writeAll("  --allow-unaudited-risks        Allow high-risk package audit findings\n");
    try writer.writeAll("  --yes, --auto-approve          Approve package review prompts when allowed\n");
    try writer.writeAll("  -p, --package <name>           Select a workspace member package\n");
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
        try writer.writeAll("  -p, --package <name>           Install one workspace member package\n");
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
    if (std.mem.eql(u8, sub, "status")) {
        try writer.writeAll("usage: sa cache status [options]\n\n");
        try writer.writeAll("Inspect project cache entries and explain their current reuse status.\n\n");
        try writer.writeAll("Options:\n");
        try writer.writeAll("  --kind <kind>                  Limit to build-exe, build-obj, build-wasm, build-obj-incremental, or test\n");
        try writer.writeAll("  --max-age-days <n>             Explain otherwise reusable entries older than n days as expired\n");
        try writer.writeAll("  --json                         Emit JSON report\n");
        try writer.writeAll("  -h, --help                     Show this help message\n");
        return;
    }
    if (std.mem.eql(u8, sub, "why")) {
        try writer.writeAll("usage: sa cache why --kind <kind> --key <hex> [--json]\n\n");
        try writer.writeAll("Explain one project cache entry without exposing source or package secrets.\n\n");
        try writer.writeAll("Options:\n");
        try writer.writeAll("  --kind <kind>                  Cache kind to inspect\n");
        try writer.writeAll("  --key <hex>                    64-character cache key\n");
        try writer.writeAll("  --max-age-days <n>             Explain an otherwise reusable entry older than n days as expired\n");
        try writer.writeAll("  --json                         Emit JSON report\n");
        try writer.writeAll("  -h, --help                     Show this help message\n");
        return;
    }

    try writer.writeAll("usage: sa cache <status|why|clean> [options]\n\n");
    try writer.writeAll("Inspect and clean project-local SA build/test caches.\n\n");
    try writer.writeAll("Subcommands:\n");
    try writer.writeAll("  status                         List cache entries with reusable/miss reasons\n");
    try writer.writeAll("  why                            Explain one cache entry by kind and key\n");
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
            try writer.writeAll("  -p, --package <name>           Install one workspace member package\n");
            try writer.writeAll("  --ref <ref>                    Fetch a specific package ref\n");
            try writer.writeAll("  -h, --help                     Show this help message\n");
        },
        .plugin => try printPluginHelp(writer, args),
        .pkg => try printPkgHelp(writer, args),
        .cache => try printCacheHelp(writer, args),
        .build => {
            try writer.writeAll("usage: sa build <file> [options]\n\n");
            try writer.writeAll("Compile a .sa source file or experimental .sab binary to a native executable.\n\n");
            try writer.writeAll("Options:\n");
            try writeBuildOptionsHelp(writer, "the executable", false);
            try writer.writeAll("  -h, --help                     Show this help message\n");
        },
        .build_workspace => {
            try writer.writeAll("usage: sa build-workspace [options]\n\n");
            try writer.writeAll("Build the selected workspace member from the current workspace root or member directory.\n\n");
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
            try writer.writeAll("Build a native object file from a .sa source file or experimental .sab binary.\n\n");
            try writer.writeAll("Options:\n");
            try writeBuildOptionsHelp(writer, "the object file", true);
            try writer.writeAll("  -h, --help                     Show this help message\n");
        },
        .build_wasm => {
            try writer.writeAll("usage: sa build-wasm <file> [options]\n\n");
            try writer.writeAll("Build a WebAssembly module from a .sa source file or experimental .sab binary.\n\n");
            try writer.writeAll("Options:\n");
            try writer.writeAll("  --target wasm32|wasm64         Select the WebAssembly target\n");
            try writeBuildOptionsHelp(writer, "the wasm module", false);
            try writer.writeAll("  -h, --help                     Show this help message\n");
        },
        .run => {
            try writer.writeAll("usage: sa run <file> [compile-options] [args...]\n\n");
            try writer.writeAll("Compile and execute a .sa source file or experimental .sab binary.\n\n");
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
            try writer.writeAll("  --affected                     Run only tests impacted by changed functions\n");
            try writeCompileOptionsHelp(writer);
            try writer.writeAll("  -h, --help                     Show this help message\n");
        },
        .check => {
            try writer.writeAll("usage: sa check <file> [options]\n\n");
            try writer.writeAll("Flatten and verify a .sa/.sab file without codegen or linking.\n");
            try writer.writeAll("Runs the full Referee verifier. Verdict-only reuse remains disabled until key v2 and a result API that does not construct VerifyOk are available; compile/emit reuse additionally requires a complete owned snapshot.\n\n");
            try writer.writeAll("Options:\n");
            try writer.writeAll("  --json                         Emit JSON report\n");
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
        .daemon => {
            try writer.writeAll("usage: sa daemon [--socket path] [--max-workers N] [--per-agent-limit N]\n\n");
            try writer.writeAll("Run a persistent compile/verify/test server over local IPC.\n\n");
            try writer.writeAll("Options:\n");
            try writer.writeAll("  --socket <path>                Unix socket path (default: platform temp directory)\n");
            try writer.writeAll("  --max-workers <N>              Max concurrent request workers (default 8)\n");
            try writer.writeAll("  --per-agent-limit <N>          Max in-flight requests per agent_id (default 4)\n");
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
    try writer.writeAll("  build        <file>            Compile a .sa/.sab source to a native executable\n");
    try writer.writeAll("  build-workspace                Build the selected workspace member executable\n");
    try writer.writeAll("  run          <file>            Compile and immediately execute a .sa/.sab file\n");
    try writer.writeAll("  build-exe    <file>            Build a standalone executable (alias for build)\n");
    try writer.writeAll("  build-obj    <file>            Build an object file (.o)\n");
    try writer.writeAll("  build-wasm   <file>            Build a WebAssembly module (.wasm)\n");
    try writer.writeAll("  test         <file>            Run @test blocks in a .sa/.sab file\n");
    try writer.writeAll("  check        <file>            Flatten and verify without codegen\n");
    try writer.writeAll("  fetch        <url>             Fetch and cache a remote package (compat)\n");
    try writer.writeAll("  audit        <file>            Use `sa pkg audit` from the package plugin\n");
    try writer.writeAll("  graph        <path>            Output a dependency/call graph\n");
    try writer.writeAll("  layout       ...               Print struct layout information\n");
    try writer.writeAll("  size         <file>            Print function size statistics\n");
    try writer.writeAll("  bc2sa      <file>            Translate LLVM bitcode to SA assembly\n");
    try writer.writeAll("  explain      <code>            Explain a diagnostic error code\n");
    try writer.writeAll("  fix          <file>            Suggest fixes for diagnostics\n");
    try writer.writeAll("  skills                         List compiler skills and capabilities\n");
    try writer.writeAll("  daemon                         Run a persistent compile/verify server\n");
    try writer.writeAll("  help         [command]         Show this help message\n");
    try writer.writeAll("  version                        Print the SA toolchain version\n");
    try writer.writeAll("\nGlobal options:\n");
    try writer.writeAll("  --json                         Output diagnostics in JSON format\n");
    try writer.writeAll("  --profile                      Include compile phase timings in JSON metrics\n");
    try writer.writeAll("  --mem-report                   Print compile RSS stage samples; JSON mode includes metrics\n");
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
    try writer.writeAll("  --affected                     Run only tests impacted by changed functions\n");
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

const BuildOutputPublishLock = struct {
    file: std.fs.File,

    fn deinit(self: *BuildOutputPublishLock) void {
        self.file.close();
        self.* = undefined;
    }
};

const BuildOutputPublishTestPause = struct {
    reached: std.Thread.ResetEvent = .{},
    continue_event: std.Thread.ResetEvent = .{},
};

var build_output_publish_test_pause: ?*BuildOutputPublishTestPause = null;

fn acquireBuildOutputPublishLock(allocator: std.mem.Allocator, out_path: []const u8) !BuildOutputPublishLock {
    const parent_path = std.fs.path.dirname(out_path) orelse ".";
    const lock_dir_path = try std.fs.path.join(allocator, &.{ parent_path, ".sa-output-locks" });
    defer allocator.free(lock_dir_path);
    try std.fs.cwd().makePath(lock_dir_path);
    const lock_path = try std.fs.path.join(allocator, &.{ lock_dir_path, std.fs.path.basename(out_path) });
    defer allocator.free(lock_path);
    return .{ .file = try std.fs.cwd().createFile(lock_path, .{
        .read = true,
        .truncate = false,
        .lock = .exclusive,
    }) };
}

const BuildOutputStage = struct {
    dir_path: []u8,
    artifact_path: []u8,
    output_path: []u8,

    fn init(allocator: std.mem.Allocator, out_path: []const u8) !BuildOutputStage {
        const dir_path = try createProjectCacheStagingDir(allocator, out_path);
        errdefer allocator.free(dir_path);
        errdefer deleteCacheTree(dir_path);
        const artifact_path = try std.fs.path.join(allocator, &.{ dir_path, "artifact.sa.bc" });
        errdefer allocator.free(artifact_path);
        const output_path = try std.fs.path.join(allocator, &.{ dir_path, "output.bin" });
        return .{
            .dir_path = dir_path,
            .artifact_path = artifact_path,
            .output_path = output_path,
        };
    }

    fn publish(
        self: *const BuildOutputStage,
        allocator: std.mem.Allocator,
        artifact_path: []const u8,
        out_path: []const u8,
        include_artifact: bool,
        executable: bool,
    ) !void {
        if (executable) try makeExecutable(self.output_path);
        var output_lock = try acquireBuildOutputPublishLock(allocator, out_path);
        defer output_lock.deinit();
        if (include_artifact) {
            try renameCachePath(self.artifact_path, artifact_path);
        } else {
            std.fs.cwd().deleteFile(artifact_path) catch |err| switch (err) {
                error.FileNotFound => {},
                else => return err,
            };
        }
        if (builtin.is_test) {
            if (build_output_publish_test_pause) |pause| {
                if (!pause.reached.isSet()) {
                    pause.reached.set();
                    pause.continue_event.wait();
                }
            }
        }
        // The primary output is the successful publication commit marker.
        try renameCachePath(self.output_path, out_path);
    }

    fn deinit(self: *BuildOutputStage, allocator: std.mem.Allocator) void {
        allocator.free(self.artifact_path);
        allocator.free(self.output_path);
        deleteCacheTree(self.dir_path);
        allocator.free(self.dir_path);
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
            .hint = "use build, build-workspace, run, build-exe, build-wasm, build-obj, pkg, cache, graph, layout, size, test, explain, fix, skills, bc2sa, help, or version",
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
        try writer.writeAll(",\"phases_ms\":{");
        try writer.writeAll("\"load\":");
        try writer.print("{d}", .{phases.load_ns / 1_000_000});
        try writer.writeAll(",\"setup\":");
        try writer.print("{d}", .{phases.setup_ns / 1_000_000});
        try writer.writeAll(",\"flatten\":");
        try writer.print("{d}", .{phases.flatten_ns / 1_000_000});
        try writer.writeAll(",\"verify\":");
        try writer.print("{d}", .{phases.verify_ns / 1_000_000});
        if (phases.emit_ns) |ns| {
            try writer.writeAll(",\"emit\":");
            try writer.print("{d}", .{ns / 1_000_000});
        }
        if (phases.link_ns) |ns| {
            try writer.writeAll(",\"link\":");
            try writer.print("{d}", .{ns / 1_000_000});
        }
        if (phases.total_ns) |ns| {
            try writer.writeAll(",\"total\":");
            try writer.print("{d}", .{ns / 1_000_000});
        }
        try writer.writeByte('}');
    }
    if (metrics.memory) |memory| {
        try writer.writeAll(",\"memory\":{");
        try writer.writeAll("\"rss_bytes\":{");
        try writeOptionalJsonU64Field(writer, "start", memory.start_rss_bytes, true);
        try writeOptionalJsonU64Field(writer, "after_load", memory.after_load_rss_bytes, false);
        try writeOptionalJsonU64Field(writer, "after_setup", memory.after_setup_rss_bytes, false);
        try writeOptionalJsonU64Field(writer, "after_flatten", memory.after_flatten_rss_bytes, false);
        try writeOptionalJsonU64Field(writer, "after_verify", memory.after_verify_rss_bytes, false);
        try writeOptionalJsonU64Field(writer, "after_emit", memory.after_emit_rss_bytes, false);
        try writeOptionalJsonU64Field(writer, "after_link", memory.after_link_rss_bytes, false);
        try writeOptionalJsonU64Field(writer, "end", memory.end_rss_bytes, false);
        try writer.writeByte('}');
        try writer.writeAll(",\"verifier_rss_bytes\":{");
        try writeOptionalJsonU64Field(writer, "start", memory.verifier.start_rss_bytes, true);
        try writeOptionalJsonU64Field(writer, "after_classify", memory.verifier.after_classify_rss_bytes, false);
        try writeOptionalJsonU64Field(writer, "after_metadata", memory.verifier.after_metadata_rss_bytes, false);
        try writeOptionalJsonU64Field(writer, "after_chunks", memory.verifier.after_chunks_rss_bytes, false);
        try writeOptionalJsonU64Field(writer, "parallel_start", memory.verifier.parallel_start_rss_bytes, false);
        try writeOptionalJsonU64Field(writer, "parallel_after_worker_allocators", memory.verifier.parallel_after_worker_allocators_rss_bytes, false);
        try writeOptionalJsonU64Field(writer, "parallel_after_body", memory.verifier.parallel_after_body_rss_bytes, false);
        try writeOptionalJsonU64Field(writer, "parallel_merge", memory.verifier.parallel_merge_rss_bytes, false);
        try writeOptionalJsonU64Field(writer, "after_body", memory.verifier.after_body_rss_bytes, false);
        try writeOptionalJsonU64Field(writer, "after_finalize", memory.verifier.after_finalize_rss_bytes, false);
        try writeOptionalJsonU64Field(writer, "empty", memory.verifier.empty_rss_bytes, false);
        try writer.writeByte('}');
        try writer.writeAll(",\"peak_rss_bytes\":");
        try writeOptionalJsonU64(writer, memory.peak_rss_bytes);
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
        if (cache.reason) |reason| {
            try writer.writeAll(",\"reason\":");
            try writeJsonString(writer, reason);
        }
        try writer.writeByte('}');
    }
    try writer.writeByte('}');
}

fn writeOptionalJsonU64(writer: anytype, value: ?u64) !void {
    if (value) |v| {
        try writer.print("{d}", .{v});
    } else {
        try writer.writeAll("null");
    }
}

fn writeOptionalJsonU64Field(writer: anytype, name: []const u8, value: ?u64, first: bool) !void {
    if (!first) try writer.writeByte(',');
    try writer.writeByte('"');
    try writer.writeAll(name);
    try writer.writeAll("\":");
    try writeOptionalJsonU64(writer, value);
}

fn writeSuccessJson(writer: anytype, metrics: CompileMetrics) !void {
    try writer.writeAll("{\"status\":\"ok\",\"metrics\":");
    try writeMetricsJson(writer, metrics);
    try writer.writeAll("}\n");
}

fn writeMemoryAmount(writer: anytype, value: ?u64) !void {
    const bytes = value orelse {
        try writer.writeAll("n/a");
        return;
    };
    const bytes_per_mib: u64 = 1024 * 1024;
    const tenths = (bytes * 10 + bytes_per_mib / 2) / bytes_per_mib;
    try writer.print("{d}.{d} MiB", .{ tenths / 10, tenths % 10 });
}

fn writeMemoryDelta(writer: anytype, previous: ?u64, current: ?u64) !void {
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

fn writeMemoryStageLine(writer: anytype, label: []const u8, value: ?u64, previous: ?u64) !void {
    try writer.print("  {s}", .{label});
    try writeMemoryAmount(writer, value);
    try writeMemoryDelta(writer, previous, value);
    try writer.writeByte('\n');
}

fn writeMemoryStageSample(writer: anytype, label: []const u8, value: ?u64, previous: ?u64) !void {
    try writer.writeAll("memory stage ");
    try writer.writeAll(label);
    try writer.writeByte(' ');
    try writeMemoryAmount(writer, value);
    try writeMemoryDelta(writer, previous, value);
    try writer.writeByte('\n');
}

fn writeMemoryStageSampleForOptions(options: CompileOptions, label: []const u8, value: ?u64, previous: ?u64) !void {
    if (!options.mem_report_live) return;
    const writer = options.diagnostic_writer orelse return;
    try writeMemoryStageSample(writer, label, value, previous);
}

const MemoryStageReporterContext = struct {
    writer: std.io.AnyWriter,
    memory: ?*CompileMemoryMetrics = null,
    previous_rss_bytes: ?u64 = null,
    peak_rss_bytes: ?u64 = null,
    live: bool = false,
};

fn writeVerifierMemoryStage(context: *MemoryStageReporterContext, stage: []const u8, completed: usize, total: usize) !void {
    const rss = currentRssBytes();
    if (context.memory) |memory| memory.recordVerifierStage(stage, rss);
    if (rss) |value| {
        if (context.peak_rss_bytes == null or value > context.peak_rss_bytes.?) {
            context.peak_rss_bytes = value;
        }
    }

    if (!context.live) {
        context.previous_rss_bytes = rss;
        return;
    }

    try context.writer.writeAll("memory stage verifier.");
    try context.writer.writeAll(stage);
    if (total != 0) {
        try context.writer.print(" {d}/{d}", .{ completed, total });
    }
    try context.writer.writeByte(' ');
    try writeMemoryAmount(context.writer, rss);
    try writeMemoryDelta(context.writer, context.previous_rss_bytes, rss);
    try context.writer.writeByte('\n');
    context.previous_rss_bytes = rss;
}

fn reportVerifierMemoryStage(context: *anyopaque, stage: []const u8, completed: usize, total: usize) void {
    const typed = @as(*MemoryStageReporterContext, @ptrCast(@alignCast(context)));
    writeVerifierMemoryStage(typed, stage, completed, total) catch {};
}

fn memoryEndPrevious(memory: CompileMemoryMetrics) ?u64 {
    return memory.after_link_rss_bytes orelse memory.after_emit_rss_bytes orelse memory.after_verify_rss_bytes;
}

fn writeMemoryReportText(writer: anytype, metrics: CompileMetrics) !void {
    const memory = metrics.memory orelse return;
    try writer.writeAll("memory report (RSS)\n");
    try writeMemoryStageLine(writer, "start          ", memory.start_rss_bytes, null);
    try writeMemoryStageLine(writer, "after_load     ", memory.after_load_rss_bytes, memory.start_rss_bytes);
    try writeMemoryStageLine(writer, "after_setup    ", memory.after_setup_rss_bytes, memory.after_load_rss_bytes);
    try writeMemoryStageLine(writer, "after_flatten  ", memory.after_flatten_rss_bytes, memory.after_setup_rss_bytes);
    try writeMemoryStageLine(writer, "after_verify   ", memory.after_verify_rss_bytes, memory.after_flatten_rss_bytes);
    try writeMemoryStageLine(writer, "after_emit     ", memory.after_emit_rss_bytes, memory.after_verify_rss_bytes);
    try writeMemoryStageLine(writer, "after_link     ", memory.after_link_rss_bytes, memory.after_emit_rss_bytes);
    try writeMemoryStageLine(writer, "end            ", memory.end_rss_bytes, memoryEndPrevious(memory));
    try writer.writeAll("  peak           ");
    try writeMemoryAmount(writer, memory.peak_rss_bytes);
    try writer.writeByte('\n');
}

fn writeSuccessDiagnostics(writer: anytype, metrics: CompileMetrics, mode: DiagnosticsMode) !void {
    switch (mode) {
        .json => try writeSuccessJson(writer, metrics),
        .human => try writeMemoryReportText(writer, metrics),
    }
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

fn writeTrapExplanation(writer: anytype, t: trap.Trap, json_mode: bool) !void {
    const ex = trap.explainTrap(t);
    const name = trap.trapName(t);
    const numeric = trap.trapCode(t);
    if (json_mode) {
        try writer.writeAll("{\"status\":\"ok\",\"explain\":{\"name\":");
        try writeJsonString(writer, name);
        try writer.writeAll(",\"stable_code\":");
        try writeJsonString(writer, ex.stable_code);
        try writer.print(",\"numeric_code\":{d},\"summary\":", .{numeric});
        try writeJsonString(writer, ex.summary);
        try writer.writeAll(",\"fix_hint\":");
        try writeJsonString(writer, ex.fix_hint);
        try writer.writeAll("}}\n");
    } else {
        try writer.print("{s} [{s} / {d}]: {s}\n", .{ name, ex.stable_code, numeric, ex.summary });
        try writer.print("fix: {s}\n", .{ex.fix_hint});
    }
}

fn explainCommand(writer: anytype, args: []const []const u8, json_mode: bool) !u8 {
    if (args.len < 3) return error.MissingSourcePath;
    const code = args[2];
    // Resolve by trap name, stable code (SA-REF-010), or numeric code (1006).
    // Covers all 57 traps via trap_agent.
    const maybe_trap = trap.trapFromName(code) orelse trap.trapFromStableCode(code) orelse blk: {
        const n = std.fmt.parseInt(u32, code, 10) catch break :blk null;
        break :blk trap.trapFromNumericCode(n);
    };
    if (maybe_trap) |t| {
        try writeTrapExplanation(writer, t, json_mode);
        return 0;
    }
    const entry = explainEntryForCode(code) orelse {
        if (json_mode) {
            try writer.writeAll("{\"status\":\"error\",\"explain\":null}\n");
        } else {
            try writer.print("unknown code: {s}\n", .{code});
        }
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
    // Trap-code fix: resolve by name/stable/numeric and synthesize a one-step
    // plan from the trap's fix_hint. Covers all 57 traps.
    if (trap.trapFromName(target) orelse trap.trapFromStableCode(target) orelse blk: {
        const num = std.fmt.parseInt(u32, target, 10) catch break :blk null;
        break :blk trap.trapFromNumericCode(num);
    }) |t| {
        const ex = trap.explainTrap(t);
        const steps = [_]FixPlanStep{.{ .action = "apply", .target = trap.trapStableCode(t), .detail = ex.fix_hint }};
        const rationale = [_][]const u8{ex.summary};
        const tplan = FixPlan{ .steps = &steps, .rationale = &rationale };
        if (json_mode) {
            try writer.writeAll("{\"status\":\"ok\",\"fix\":");
            try writeFixPlanJson(writer, trap.trapStableCode(t), tplan);
            try writer.writeAll("}\n");
        } else {
            try writeFixPlanText(writer, trap.trapStableCode(t), tplan);
        }
        return 0;
    }
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
    try writer.writeAll("- Use `sa build-workspace -p <package> -o <path>` for workspace-root member builds, or `sa build-exe <file> -o <path>`, `sa build-obj <file> -o <path>`, and `sa build-wasm <file> -o <path>` for direct file artifacts.\n");
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
            "check <file>",
            "test --affected",
            "daemon",
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
    // Diagnostic catalog: expose all verifier/flattener traps (name + stable
    // code) so Agents can discover the full diagnostic surface. Items live for
    // the function scope; sections are rendered before this list is freed.
    var trap_items = std.ArrayList([]const u8).init(allocator);
    defer {
        for (trap_items.items) |it| allocator.free(it);
        trap_items.deinit();
    }
    for (trap.allTraps()) |t| {
        const it = std.fmt.allocPrint(allocator, "{s} ({s})", .{ trap.trapName(t), trap.trapStableCode(t) }) catch continue;
        trap_items.append(it) catch continue;
    }
    try sections_list.append(.{ .name = "diagnostic catalog", .summary = "All verifier/flattener traps; use sa explain <name|code> for details", .items = trap_items.items });
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

fn daemonWorker(allocator: std.mem.Allocator, conn: std.net.Server.Connection, in_flight: *std.atomic.Value(usize)) void {
    defer {
        const previous = in_flight.fetchSub(1, .monotonic);
        daemon_in_flight_global.store(previous - 1, .monotonic);
    }
    handleDaemonConnection(allocator, conn);
}

var daemon_shutdown_flag = std.atomic.Value(bool).init(false);
var daemon_in_flight_global = std.atomic.Value(usize).init(0);
// Process cwd is shared by every thread. Until command execution accepts an
// explicit request-local root throughout the stack, serialize all non-control
// requests so a request without a cwd cannot observe another request's chdir.
var daemon_execution_mutex: std.Thread.Mutex = .{};

fn reserveDaemonWorkerSlot(in_flight: *std.atomic.Value(usize), max_workers: usize) bool {
    const current = in_flight.load(.monotonic);
    if (current >= max_workers) return false;
    _ = in_flight.fetchAdd(1, .monotonic);
    daemon_in_flight_global.store(current + 1, .monotonic);
    return true;
}

fn rejectDaemonBusy(conn: std.net.Server.Connection) void {
    defer conn.stream.close();
    daemon_cancel.noteBusyRejected();
    conn.stream.writeAll("{\"status\":\"busy\",\"message\":\"daemon worker limit reached\"}\n") catch {};
}

fn handleDaemonConnection(allocator: std.mem.Allocator, conn: std.net.Server.Connection) void {
    defer conn.stream.close();
    var read_buf: [65536]u8 = undefined;
    const n = conn.stream.read(read_buf[0..]) catch return;
    if (n == 0) return;
    const request_line = std.mem.trimRight(u8, read_buf[0..n], "\n\r ");

    // Control ops that don't need argv execution.
    if (std.mem.indexOf(u8, request_line, "\"op\":\"ping\"") != null or std.mem.indexOf(u8, request_line, "\"op\": \"ping\"") != null) {
        const st = daemon_cancel.stats();
        const vs = incr_verify.stats();
        const as = affected_tests.stats();
        var header = std.ArrayList(u8).init(allocator);
        defer header.deinit();
        header.writer().print(
            "{{\"status\":\"ok\",\"code\":0,\"metrics\":{{\"in_flight\":{d},\"accepted\":{d},\"canceled\":{d},\"busy_rejects\":{d},\"verdict_hits\":{d},\"verdict_misses\":{d},\"affected_hits\":{d},\"affected_misses\":{d}}}}}\n",
            .{
                daemon_in_flight_global.load(.monotonic),
                st.accepted,
                st.canceled,
                st.busy_rejects,
                vs.hits,
                vs.misses,
                as.hits,
                as.misses,
            },
        ) catch return;
        conn.stream.writeAll(header.items) catch {};
        return;
    }
    if (std.mem.indexOf(u8, request_line, "\"op\":\"shutdown\"") != null or std.mem.indexOf(u8, request_line, "\"op\": \"shutdown\"") != null) {
        daemon_shutdown_flag.store(true, .monotonic);
        conn.stream.writeAll("{\"status\":\"ok\",\"code\":0,\"message\":\"shutting down\"}\n") catch {};
        return;
    }
    if (std.mem.indexOf(u8, request_line, "\"op\":\"cancel\"") != null or std.mem.indexOf(u8, request_line, "\"op\": \"cancel\"") != null) {
        const agent_id = daemon_cancel.parseJsonStrField(request_line, "\"agent_id\"") orelse "";
        const gen = daemon_cancel.cancelAgent(agent_id);
        daemon_cancel.noteCanceled();
        var header = std.ArrayList(u8).init(allocator);
        defer header.deinit();
        header.writer().print("{{\"status\":\"ok\",\"code\":0,\"canceled_generation\":{d}}}\n", .{gen}) catch return;
        conn.stream.writeAll(header.items) catch {};
        return;
    }

    // Cooperative cancellation: skip work if a newer generation superseded this.
    const agent_id = daemon_cancel.parseJsonStrField(request_line, "\"agent_id\"") orelse "";
    const generation = daemon_cancel.parseJsonU64Field(request_line, "\"generation\"") orelse 0;
    if (agent_id.len != 0) {
        _ = daemon_cancel.registerGeneration(agent_id, generation);
        if (!daemon_cancel.generationIsCurrent(agent_id, generation)) {
            daemon_cancel.noteCanceled();
            conn.stream.writeAll("{\"status\":\"canceled\"}\n") catch {};
            return;
        }
    }

    // Per-agent quota: reject if this agent already has too many in-flight
    // requests. Prevents one agent from starving others. Empty id = unlimited.
    if (agent_id.len != 0 and !daemon_cancel.acquireSlot(agent_id)) {
        conn.stream.writeAll("{\"status\":\"busy\",\"message\":\"per-agent quota exceeded\"}\n") catch {};
        return;
    }
    defer if (agent_id.len != 0) daemon_cancel.releaseSlot(agent_id);

    const parsed = parseDaemonArgv(allocator, request_line) catch {
        conn.stream.writeAll("{\"status\":\"error\",\"message\":\"invalid request\"}\n") catch {};
        return;
    };
    defer freeDaemonArgv(allocator, parsed);

    const wall_start = std.time.Instant.now() catch null;
    var resp = std.ArrayList(u8).init(allocator);
    defer resp.deinit();
    const code: u8 = execution: {
        daemon_execution_mutex.lock();
        defer daemon_execution_mutex.unlock();

        var old_cwd_buf: [std.fs.max_path_bytes]u8 = undefined;
        const old_cwd = std.fs.cwd().realpath(".", &old_cwd_buf) catch null;
        defer if (old_cwd) |cwd| std.posix.chdir(cwd) catch {};
        if (daemon_cancel.parseJsonStrField(request_line, "\"cwd\"")) |cwd| {
            std.posix.chdir(cwd) catch |err| {
                resp.writer().print("execution error: invalid cwd: {s}", .{@errorName(err)}) catch {};
                break :execution 1;
            };
        }

        break :execution executeWithWritersAndOptions(allocator, parsed, resp.writer(), resp.writer(), .{}) catch |err| {
            resp.clearRetainingCapacity();
            resp.writer().print("execution error: {s}", .{@errorName(err)}) catch {};
            break :execution 1;
        };
    };
    const wall_ms: u64 = if (wall_start) |s| elapsedNs(s) / 1_000_000 else 0;
    const vs = incr_verify.stats();
    const as = affected_tests.stats();

    // Re-check cancellation after work (cooperative end boundary).
    if (agent_id.len != 0 and !daemon_cancel.generationIsCurrent(agent_id, generation)) {
        daemon_cancel.noteCanceled();
        conn.stream.writeAll("{\"status\":\"canceled\"}\n") catch {};
        return;
    }

    var header = std.ArrayList(u8).init(allocator);
    defer header.deinit();
    header.writer().print(
        "{{\"status\":\"ok\",\"code\":{d},\"len\":{d},\"metrics\":{{\"wall_ms\":{d},\"verdict_hits\":{d},\"verdict_misses\":{d},\"affected_hits\":{d},\"affected_misses\":{d}}}}}\n",
        .{ code, resp.items.len, wall_ms, vs.hits, vs.misses, as.hits, as.misses },
    ) catch return;
    conn.stream.writeAll(header.items) catch {};
    conn.stream.writeAll(resp.items) catch {};
}

fn parseDaemonArgv(allocator: std.mem.Allocator, request: []const u8) ![]const []const u8 {
    // Prefer explicit argv array. Also accept op/file/args document style.
    if (std.mem.indexOf(u8, request, "\"argv\"")) |_| {
        const lb = std.mem.indexOfScalar(u8, request, '[') orelse return error.InvalidRequest;
        const rb = std.mem.lastIndexOfScalar(u8, request, ']') orelse return error.InvalidRequest;
        if (rb <= lb) return error.InvalidRequest;
        const inner = request[lb + 1 .. rb];
        var list = std.ArrayList([]const u8).init(allocator);
        errdefer {
            for (list.items) |it| allocator.free(it);
            list.deinit();
        }
        var i: usize = 0;
        while (i < inner.len) {
            if (inner[i] != '"') {
                i += 1;
                continue;
            }
            i += 1;
            var item = std.ArrayList(u8).init(allocator);
            errdefer item.deinit();
            while (i < inner.len and inner[i] != '"') {
                if (inner[i] == '\\' and i + 1 < inner.len) {
                    i += 1;
                }
                try item.append(inner[i]);
                i += 1;
            }
            i += 1; // closing quote
            try list.append(try item.toOwnedSlice());
        }
        // Normalize argv[0] to "sa". Clients may send the real binary path
        // (e.g. zig-out/bin/sa) or omit argv[0] entirely and start at the command.
        if (list.items.len == 0) {
            try list.insert(0, try allocator.dupe(u8, "sa"));
        } else if (std.mem.eql(u8, list.items[0], "sa") or std.mem.endsWith(u8, list.items[0], "/sa")) {
            if (!std.mem.eql(u8, list.items[0], "sa")) {
                allocator.free(list.items[0]);
                list.items[0] = try allocator.dupe(u8, "sa");
            }
        } else if (commandFromName(list.items[0]) != null or std.mem.eql(u8, list.items[0], "help") or std.mem.eql(u8, list.items[0], "version")) {
            try list.insert(0, try allocator.dupe(u8, "sa"));
        } else {
            // Unknown first token: still force sa so dispatch can error cleanly.
            try list.insert(0, try allocator.dupe(u8, "sa"));
        }
        return try list.toOwnedSlice();
    }

    // Document-style: {"op":"build","file":"x.sa","args":["--json"]}
    const op = daemon_cancel.parseJsonStrField(request, "\"op\"") orelse return error.InvalidRequest;
    var list = std.ArrayList([]const u8).init(allocator);
    errdefer {
        for (list.items) |it| allocator.free(it);
        list.deinit();
    }
    try list.append(try allocator.dupe(u8, "sa"));
    try list.append(try allocator.dupe(u8, op));
    if (daemon_cancel.parseJsonStrField(request, "\"file\"")) |file| {
        try list.append(try allocator.dupe(u8, file));
    }
    // Best-effort: pull string items after "args"
    if (std.mem.indexOf(u8, request, "\"args\"")) |ap| {
        const sub = request[ap..];
        const lb = std.mem.indexOfScalar(u8, sub, '[') orelse 0;
        const rb = std.mem.indexOfScalar(u8, sub, ']') orelse 0;
        if (rb > lb) {
            const inner = sub[lb + 1 .. rb];
            var i: usize = 0;
            while (i < inner.len) {
                if (inner[i] != '"') {
                    i += 1;
                    continue;
                }
                i += 1;
                var item = std.ArrayList(u8).init(allocator);
                errdefer item.deinit();
                while (i < inner.len and inner[i] != '"') {
                    if (inner[i] == '\\' and i + 1 < inner.len) i += 1;
                    try item.append(inner[i]);
                    i += 1;
                }
                i += 1;
                try list.append(try item.toOwnedSlice());
            }
        }
    }
    return try list.toOwnedSlice();
}

fn freeDaemonArgv(allocator: std.mem.Allocator, argv: []const []const u8) void {
    for (argv) |a| allocator.free(a);
    allocator.free(argv);
}

fn defaultDaemonSocketPath(allocator: std.mem.Allocator) ![]u8 {
    const env_names = [_][]const u8{ "XDG_RUNTIME_DIR", "TMPDIR", "TEMP", "TMP" };
    for (env_names) |name| {
        const root = std.process.getEnvVarOwned(allocator, name) catch continue;
        defer allocator.free(root);
        if (root.len == 0) continue;
        return try std.fs.path.join(allocator, &.{ root, "sa-daemon.sock" });
    }
    return try allocator.dupe(u8, "/tmp/sa-daemon.sock");
}

fn daemonCommand(allocator: std.mem.Allocator, args: []const []const u8, stdout: anytype, stderr: anytype) !u8 {
    if (builtin.os.tag == .windows) {
        try stderr.writeAll("daemon is not supported on Windows; other commands continue to run in-process\n");
        return 1;
    }
    return try daemonCommandUnix(allocator, args, stdout, stderr);
}

fn daemonCommandUnix(allocator: std.mem.Allocator, args: []const []const u8, stdout: anytype, stderr: anytype) !u8 {
    const default_socket_path = try defaultDaemonSocketPath(allocator);
    defer allocator.free(default_socket_path);
    var socket_path: []const u8 = default_socket_path;
    var max_workers: usize = 8;
    var i: usize = 0;
    while (i < args.len) : (i += 1) {
        if (std.mem.eql(u8, args[i], "--socket") and i + 1 < args.len) {
            socket_path = args[i + 1];
            i += 1;
        } else if (std.mem.eql(u8, args[i], "--max-workers") and i + 1 < args.len) {
            max_workers = @max(1, std.fmt.parseInt(usize, args[i + 1], 10) catch 8);
            i += 1;
        } else if (std.mem.eql(u8, args[i], "--per-agent-limit") and i + 1 < args.len) {
            daemon_cancel.setPerAgentLimit(std.fmt.parseInt(u32, args[i + 1], 10) catch 4);
            i += 1;
        }
    }
    std.fs.cwd().deleteFile(socket_path) catch {};
    const addr = try std.net.Address.initUnix(socket_path);
    var server = addr.listen(.{}) catch |err| {
        try stderr.print("daemon: failed to listen on {s}: {s}\n", .{ socket_path, @errorName(err) });
        return 1;
    };
    defer server.deinit();
    try stdout.print("sa daemon listening on {s} (max_workers={d})\n", .{ socket_path, max_workers });

    var in_flight = std.atomic.Value(usize).init(0);
    daemon_shutdown_flag.store(false, .monotonic);
    while (!daemon_shutdown_flag.load(.monotonic)) {
        const conn = server.accept() catch |err| {
            if (daemon_shutdown_flag.load(.monotonic)) break;
            try stderr.print("daemon: accept failed: {s}\n", .{@errorName(err)});
            continue;
        };
        // Hard backpressure: never execute an N+1 request on the accept thread.
        // A bounded queue is a later scheduler step; containment rejects busy.
        if (!reserveDaemonWorkerSlot(&in_flight, max_workers)) {
            rejectDaemonBusy(conn);
            continue;
        }
        const thread = std.Thread.spawn(.{}, daemonWorker, .{ allocator, conn, &in_flight }) catch {
            const previous = in_flight.fetchSub(1, .monotonic);
            daemon_in_flight_global.store(previous - 1, .monotonic);
            rejectDaemonBusy(conn);
            continue;
        };
        thread.detach();
    }
    // Wait briefly for in-flight workers to drain.
    var spins: usize = 0;
    while (in_flight.load(.monotonic) > 0 and spins < 1000) : (spins += 1) {
        std.Thread.sleep(1 * std.time.ns_per_ms);
    }
    std.fs.cwd().deleteFile(socket_path) catch {};
    return 0;
}

test "daemon worker reservation enforces a hard max without inline N plus one" {
    var in_flight = std.atomic.Value(usize).init(0);
    try std.testing.expect(reserveDaemonWorkerSlot(&in_flight, 2));
    try std.testing.expect(reserveDaemonWorkerSlot(&in_flight, 2));
    try std.testing.expect(!reserveDaemonWorkerSlot(&in_flight, 2));
    try std.testing.expectEqual(@as(usize, 2), in_flight.load(.monotonic));
    _ = in_flight.fetchSub(1, .monotonic);
    try std.testing.expect(reserveDaemonWorkerSlot(&in_flight, 2));
    try std.testing.expectEqual(@as(usize, 2), in_flight.load(.monotonic));
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
    if (try consumePackageOption(arg, args, index, options)) return true;
    if (consumeProfileOption(arg, options)) return true;
    if (consumeMemReportOption(arg, options)) return true;
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
    if (std.mem.startsWith(u8, arg, "--project-root=")) {
        options.project_root = arg["--project-root=".len..];
        if (options.project_root.?.len == 0) return error.InvalidPath;
        return true;
    }
    if (std.mem.eql(u8, arg, "--project-root")) {
        if (index.* + 1 >= args.len) return error.InvalidPath;
        options.project_root = args[index.* + 1];
        if (options.project_root.?.len == 0) return error.InvalidPath;
        index.* += 1;
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

fn consumePackageOption(arg: []const u8, args: []const []const u8, index: *usize, options: *CompileOptions) !bool {
    if (std.mem.startsWith(u8, arg, "--package=")) {
        options.package_name = arg["--package=".len..];
        if (options.package_name.?.len == 0) return error.UnknownPackage;
        return true;
    }
    if (std.mem.eql(u8, arg, "--package") or std.mem.eql(u8, arg, "-p")) {
        if (index.* + 1 >= args.len) return error.UnknownPackage;
        options.package_name = args[index.* + 1];
        if (options.package_name.?.len == 0) return error.UnknownPackage;
        index.* += 1;
        return true;
    }
    if (std.mem.startsWith(u8, arg, "-p=")) {
        options.package_name = arg["-p=".len..];
        if (options.package_name.?.len == 0) return error.UnknownPackage;
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

fn consumeMemReportOption(arg: []const u8, options: *CompileOptions) bool {
    if (!std.mem.eql(u8, arg, "--mem-report")) return false;
    options.mem_report = true;
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

fn configureCompileDiagnostics(options: *CompileOptions, json_mode: bool) void {
    options.mem_report_live = options.mem_report and !json_mode;
}

fn loadSource(allocator: std.mem.Allocator, path: []const u8) ![]u8 {
    if (builtin.is_test) test_source_tree_load_count += 1;
    var file = try std.fs.cwd().openFile(path, .{});
    defer file.close();
    return try file.readToEndAlloc(allocator, 16 * 1024 * 1024);
}

fn loadSabFlat(allocator: std.mem.Allocator, source_path: []const u8) !flattener.FlattenResult {
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

    var test_sigs = std.ArrayList(flattener.FunctionSig).init(allocator);
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

fn collectSabTestListFast(allocator: std.mem.Allocator, source_path: []const u8) !test_meta.TestList {
    const bytes = try loadSource(allocator, source_path);
    defer allocator.free(bytes);

    const function_sigs = try sab.decodeTestFunctionSigsOnly(allocator, bytes);
    defer {
        for (function_sigs) |*function_sig| function_sig.deinit(allocator);
        allocator.free(function_sigs);
    }

    return try test_meta.collect(allocator, function_sigs);
}

fn hasExplicitTestSelection(selection: test_meta.TestSelection) bool {
    return selection.include_filters.len != 0 or
        selection.skip_filters.len != 0 or
        selection.exact or
        selection.ignored != .normal;
}

fn selectedTestNamesFromList(allocator: std.mem.Allocator, test_list: test_meta.TestList, selection: test_meta.TestSelection) ![]const []const u8 {
    if (!hasExplicitTestSelection(selection)) return &.{};
    const selected_count = selection.countSelected(test_list.tests);
    if (selected_count == 0) return &.{};

    const selected_names = try allocator.alloc([]const u8, selected_count);
    errdefer allocator.free(selected_names);
    var selected_index: usize = 0;
    for (test_list.tests) |test_case| {
        if (!selection.shouldRun(test_case)) continue;
        selected_names[selected_index] = test_case.selectorName();
        selected_index += 1;
    }
    return selected_names;
}

fn sabPruneDebugEnabled(allocator: std.mem.Allocator) bool {
    const value = std.process.getEnvVarOwned(allocator, "SA_DEBUG_SAB_PRUNE") catch return false;
    defer allocator.free(value);
    return value.len != 0 and !std.mem.eql(u8, value, "0");
}

const SabFunctionRange = struct {
    sig_index: usize,
    start: usize,
    end: usize,
};

fn isSabFunctionDecl(kind: flattener.InstKind) bool {
    return switch (kind) {
        .func_decl, .ffi_wrapper_decl, .extern_decl, .export_decl, .test_decl => true,
        else => false,
    };
}

fn buildSabFunctionRanges(allocator: std.mem.Allocator, instructions: []const flattener.Instruction) ![]SabFunctionRange {
    var ranges = std.ArrayList(SabFunctionRange).init(allocator);
    errdefer ranges.deinit();

    var current_start: ?usize = null;
    var current_sig_index: usize = 0;
    var next_sig_index: usize = 0;
    for (instructions, 0..) |item, idx| {
        if (!isSabFunctionDecl(item.kind)) continue;
        if (current_start) |start| {
            try ranges.append(.{
                .sig_index = current_sig_index,
                .start = start,
                .end = idx,
            });
        }
        current_start = idx;
        current_sig_index = next_sig_index;
        next_sig_index += 1;
    }
    if (current_start) |start| {
        try ranges.append(.{
            .sig_index = current_sig_index,
            .start = start,
            .end = instructions.len,
        });
    }
    return try ranges.toOwnedSlice();
}

fn putSabFunctionAlias(index: *std.StringHashMap(usize), name: []const u8, sig_index: usize) !void {
    if (name.len == 0 or index.contains(name)) return;
    try index.put(name, sig_index);
}

fn buildSabFunctionSigIndex(allocator: std.mem.Allocator, function_sigs: []const flattener.FunctionSig) !std.StringHashMap(usize) {
    var index = std.StringHashMap(usize).init(allocator);
    errdefer index.deinit();
    const max_aliases = std.math.mul(usize, function_sigs.len, 2) catch function_sigs.len;
    try index.ensureTotalCapacity(@intCast(max_aliases));
    for (function_sigs, 0..) |function_sig, sig_index| {
        try putSabFunctionAlias(&index, function_sig.name, sig_index);
        if (function_sig.llvm_name) |llvm_name| try putSabFunctionAlias(&index, llvm_name, sig_index);
    }
    return index;
}

fn buildSabConstIndex(allocator: std.mem.Allocator, const_decls: []const flattener.ConstDecl) !std.StringHashMap(usize) {
    var index = std.StringHashMap(usize).init(allocator);
    errdefer index.deinit();
    try index.ensureTotalCapacity(@intCast(const_decls.len));
    for (const_decls, 0..) |decl, const_index| {
        if (!index.contains(decl.name)) try index.put(decl.name, const_index);
    }
    return index;
}

fn enqueueSabReachableByName(
    reachable: *std.AutoHashMap(usize, void),
    queue: *std.ArrayList(usize),
    sig_index_by_name: *const std.StringHashMap(usize),
    name: []const u8,
) !bool {
    const sig_index = sig_index_by_name.get(name) orelse return false;
    if (reachable.contains(sig_index)) return false;
    try reachable.put(sig_index, {});
    try queue.append(sig_index);
    return true;
}

fn sabReferenceName(text: []const u8) []const u8 {
    var trimmed = std.mem.trim(u8, text, " \t\r");
    while (trimmed.len != 0 and (trimmed[0] == '&' or trimmed[0] == '^' or trimmed[0] == '*')) {
        trimmed = std.mem.trim(u8, trimmed[1..], " \t\r");
    }
    if (trimmed.len != 0 and trimmed[0] == '@') trimmed = trimmed[1..];
    return trimmed;
}

fn sabReferenceIsExplicitSymbol(text: []const u8) bool {
    var trimmed = std.mem.trim(u8, text, " \t\r");
    while (trimmed.len != 0 and (trimmed[0] == '&' or trimmed[0] == '^' or trimmed[0] == '*')) {
        trimmed = std.mem.trim(u8, trimmed[1..], " \t\r");
    }
    return trimmed.len != 0 and trimmed[0] == '@';
}

fn markSabReachableVtableConstByName(
    reachable_functions: *std.AutoHashMap(usize, void),
    reachable_vtable_consts: *std.AutoHashMap(usize, void),
    sig_index_by_name: *const std.StringHashMap(usize),
    const_index_by_name: *const std.StringHashMap(usize),
    const_decls: []const flattener.ConstDecl,
    name: []const u8,
    closure_complete: *bool,
    queue: *std.ArrayList(usize),
) !bool {
    const normalized = sabReferenceName(name);
    if (normalized.len == 0) return false;
    const const_index = const_index_by_name.get(normalized) orelse return false;
    switch (const_decls[const_index].value) {
        .vtable => |literal| {
            if (reachable_vtable_consts.contains(const_index)) return false;
            try reachable_vtable_consts.put(const_index, {});
            var changed = true;
            for (literal.slots) |slot| {
                if (!sig_index_by_name.contains(slot.func_name)) {
                    closure_complete.* = false;
                    continue;
                }
                changed = (try enqueueSabReachableByName(reachable_functions, queue, sig_index_by_name, slot.func_name)) or changed;
            }
            return changed;
        },
        else => return false,
    }
}

fn markSabReachableVtableConstFromOperand(
    reachable_functions: *std.AutoHashMap(usize, void),
    reachable_vtable_consts: *std.AutoHashMap(usize, void),
    sig_index_by_name: *const std.StringHashMap(usize),
    const_index_by_name: *const std.StringHashMap(usize),
    flat: *const flattener.FlattenResult,
    operand: anytype,
    closure_complete: *bool,
    queue: *std.ArrayList(usize),
) !bool {
    const text = switch (operand) {
        .reg => |id| flat.symbols.lookupName(id),
        .symbol => |id| flat.symbols.lookupName(id),
        .label => |id| flat.symbols.lookupName(id),
        .func => |id| flat.symbols.lookupName(id),
        .text => |value| value,
        .native_text => |value| value,
        else => null,
    } orelse return false;
    return try markSabReachableVtableConstByName(reachable_functions, reachable_vtable_consts, sig_index_by_name, const_index_by_name, flat.const_decls, text, closure_complete, queue);
}

fn freeFlatInstructionMetadata(allocator: std.mem.Allocator, item: flattener.Instruction) void {
    if (item.package_identity) |identity| allocator.free(identity);
    if (item.upstream_loc) |loc| allocator.free(loc.file);
    if (item.native_reg_names.len != 0) allocator.free(item.native_reg_names);
}

fn freeFlatLocEntry(allocator: std.mem.Allocator, entry: ?common_upstream.UpstreamLoc) void {
    if (entry) |loc| allocator.free(loc.file);
}

fn pruneSabVtableConsts(
    allocator: std.mem.Allocator,
    flat: *flattener.FlattenResult,
    reachable_vtable_consts: *const std.AutoHashMap(usize, void),
) !void {
    if (flat.const_decls.len == 0) return;

    var keep = try allocator.alloc(bool, flat.const_decls.len);
    defer allocator.free(keep);
    var pruned_any = false;
    var kept_count: usize = 0;
    for (flat.const_decls, 0..) |decl, const_index| {
        keep[const_index] = switch (decl.value) {
            .vtable => reachable_vtable_consts.contains(const_index),
            else => true,
        };
        if (keep[const_index]) {
            kept_count += 1;
        } else {
            pruned_any = true;
        }
    }
    if (!pruned_any) return;

    const new_const_decls = try allocator.alloc(flattener.ConstDecl, kept_count);
    var kept_index: usize = 0;
    for (flat.const_decls, 0..) |decl, const_index| {
        if (keep[const_index]) {
            new_const_decls[kept_index] = decl;
            kept_index += 1;
        } else {
            var dropped = decl;
            dropped.deinit(allocator);
        }
    }
    allocator.free(flat.const_decls);
    flat.const_decls = new_const_decls;
}

fn collectSabSelectedReachability(
    allocator: std.mem.Allocator,
    flat: *const flattener.FlattenResult,
    ranges: []const SabFunctionRange,
    sig_index_by_name: *const std.StringHashMap(usize),
    const_index_by_name: *const std.StringHashMap(usize),
    selected_test_names: []const []const u8,
    reachable_vtable_consts: *std.AutoHashMap(usize, void),
    closure_complete: *bool,
) !std.AutoHashMap(usize, void) {
    var reachable = std.AutoHashMap(usize, void).init(allocator);
    errdefer reachable.deinit();
    var queue = std.ArrayList(usize).init(allocator);
    defer queue.deinit();

    var range_index_by_sig = try allocator.alloc(?usize, flat.function_sigs.len);
    defer allocator.free(range_index_by_sig);
    @memset(range_index_by_sig, null);
    for (ranges, 0..) |range, range_index| {
        if (range.sig_index < range_index_by_sig.len) range_index_by_sig[range.sig_index] = range_index;
    }

    for (selected_test_names) |name| {
        if (!sig_index_by_name.contains(name)) {
            closure_complete.* = false;
            continue;
        }
        _ = try enqueueSabReachableByName(&reachable, &queue, sig_index_by_name, name);
    }

    var queue_index: usize = 0;
    while (queue_index < queue.items.len) : (queue_index += 1) {
        const sig_index = queue.items[queue_index];
        const range_index = if (sig_index < range_index_by_sig.len) range_index_by_sig[sig_index] else null;
        const range = ranges[
            range_index orelse {
                closure_complete.* = false;
                continue;
            }
        ];

        for (flat.instructions[range.start..range.end]) |item| {
            if (item.kind != .call and item.kind != .call_indirect) continue;
            var parsed = referee_call.parseInstructionCall(allocator, item, &flat.symbols) catch |err| switch (err) {
                error.InvalidCallSyntax => {
                    closure_complete.* = false;
                    continue;
                },
                else => return err,
            };
            defer parsed.deinit(allocator);
            if (parsed.is_indirect) {
                closure_complete.* = false;
                continue;
            }
            if (!sig_index_by_name.contains(parsed.callee)) {
                closure_complete.* = false;
                continue;
            }
            _ = try enqueueSabReachableByName(&reachable, &queue, sig_index_by_name, parsed.callee);
        }
        for (flat.instructions[range.start..range.end]) |item| {
            for (item.operands) |operand| {
                switch (operand) {
                    .func => |id| {
                        const function_name = flat.symbols.lookupName(id) orelse {
                            closure_complete.* = false;
                            continue;
                        };
                        if (!sig_index_by_name.contains(function_name)) {
                            closure_complete.* = false;
                        } else {
                            _ = try enqueueSabReachableByName(&reachable, &queue, sig_index_by_name, function_name);
                        }
                    },
                    else => {},
                }

                if (item.kind != .call and item.kind != .call_indirect and !isSabFunctionDecl(item.kind)) {
                    const reference_text = switch (operand) {
                        .reg => |id| flat.symbols.lookupName(id),
                        .symbol => |id| flat.symbols.lookupName(id),
                        .func => |id| flat.symbols.lookupName(id),
                        .text => |text| text,
                        .native_text => |text| text,
                        else => null,
                    };
                    if (reference_text) |text| {
                        if (sabReferenceIsExplicitSymbol(text)) {
                            const referenced_name = sabReferenceName(text);
                            if (sig_index_by_name.contains(referenced_name)) {
                                _ = try enqueueSabReachableByName(&reachable, &queue, sig_index_by_name, referenced_name);
                            } else if (!const_index_by_name.contains(referenced_name)) {
                                closure_complete.* = false;
                            }
                        }
                    }
                }
                _ = try markSabReachableVtableConstFromOperand(&reachable, reachable_vtable_consts, sig_index_by_name, const_index_by_name, flat, operand, closure_complete, &queue);
            }
        }
    }

    return reachable;
}

fn pruneSabFlatToSelectedTests(allocator: std.mem.Allocator, flat: *flattener.FlattenResult, selected_test_names: []const []const u8) !void {
    if (selected_test_names.len == 0 or flat.function_sigs.len == 0 or flat.instructions.len == 0) return;
    const original_function_count = flat.function_sigs.len;
    const original_test_count = flat.test_sigs.len;
    const original_instruction_count = flat.instructions.len;
    const original_const_count = flat.const_decls.len;

    const ranges = try buildSabFunctionRanges(allocator, flat.instructions);
    defer allocator.free(ranges);
    if (ranges.len == 0) return;

    var sig_index_by_name = try buildSabFunctionSigIndex(allocator, flat.function_sigs);
    defer sig_index_by_name.deinit();

    var const_index_by_name = try buildSabConstIndex(allocator, flat.const_decls);
    defer const_index_by_name.deinit();

    var reachable_vtable_consts = std.AutoHashMap(usize, void).init(allocator);
    defer reachable_vtable_consts.deinit();

    var closure_complete = true;
    var reachable = try collectSabSelectedReachability(allocator, flat, ranges, &sig_index_by_name, &const_index_by_name, selected_test_names, &reachable_vtable_consts, &closure_complete);
    defer reachable.deinit();
    // The full module is the only sound fallback while indirect/address-taken
    // target sets are unresolved. This return occurs before any FlatResult
    // allocation is transferred or freed.
    if (!closure_complete) return;
    if (reachable.count() == 0) return;

    var kept_sigs = std.ArrayList(flattener.FunctionSig).init(allocator);
    errdefer kept_sigs.deinit();
    var kept_test_sigs = std.ArrayList(flattener.FunctionSig).init(allocator);
    errdefer kept_test_sigs.deinit();
    var kept_instructions = std.ArrayList(flattener.Instruction).init(allocator);
    errdefer kept_instructions.deinit();
    var kept_loc_table = std.ArrayList(?common_upstream.UpstreamLoc).init(allocator);
    errdefer kept_loc_table.deinit();

    var keep_ranges = try allocator.alloc(bool, ranges.len);
    defer allocator.free(keep_ranges);
    @memset(keep_ranges, false);
    for (ranges, 0..) |range, range_idx| {
        if (range.sig_index >= flat.function_sigs.len) continue;
        if (!reachable.contains(range.sig_index)) continue;
        keep_ranges[range_idx] = true;

        const function_sig = flat.function_sigs[range.sig_index];
        try kept_sigs.append(function_sig);
        if (function_sig.kind == .test_func) try kept_test_sigs.append(function_sig);
        try kept_instructions.appendSlice(flat.instructions[range.start..range.end]);
        try kept_loc_table.appendSlice(flat.loc_table[range.start..range.end]);
    }
    if (kept_sigs.items.len == 0) return;

    const new_function_sigs = try kept_sigs.toOwnedSlice();
    errdefer allocator.free(new_function_sigs);
    const new_test_sigs = try kept_test_sigs.toOwnedSlice();
    errdefer allocator.free(new_test_sigs);
    const new_instructions = try kept_instructions.toOwnedSlice();
    errdefer allocator.free(new_instructions);
    const new_loc_table = try kept_loc_table.toOwnedSlice();
    errdefer allocator.free(new_loc_table);

    try pruneSabVtableConsts(allocator, flat, &reachable_vtable_consts);

    var range_index: usize = 0;
    var instruction_index: usize = 0;
    while (instruction_index < flat.instructions.len) {
        if (range_index < ranges.len and instruction_index == ranges[range_index].start) {
            const range = ranges[range_index];
            if (!keep_ranges[range_index]) {
                for (flat.instructions[range.start..range.end]) |item| freeFlatInstructionMetadata(allocator, item);
                for (flat.loc_table[range.start..range.end]) |entry| freeFlatLocEntry(allocator, entry);
            }
            instruction_index = range.end;
            range_index += 1;
            continue;
        }
        freeFlatInstructionMetadata(allocator, flat.instructions[instruction_index]);
        freeFlatLocEntry(allocator, flat.loc_table[instruction_index]);
        instruction_index += 1;
    }

    var sig_keep = try allocator.alloc(bool, flat.function_sigs.len);
    defer allocator.free(sig_keep);
    @memset(sig_keep, false);
    for (ranges, 0..) |range, range_idx| {
        if (range.sig_index < sig_keep.len and keep_ranges[range_idx]) sig_keep[range.sig_index] = true;
    }
    for (flat.function_sigs, 0..) |*function_sig, sig_index| {
        if (!sig_keep[sig_index]) function_sig.deinit(allocator);
    }

    allocator.free(flat.function_sigs);
    allocator.free(flat.test_sigs);
    allocator.free(flat.instructions);
    allocator.free(flat.loc_table);

    flat.function_sigs = new_function_sigs;
    flat.test_sigs = new_test_sigs;
    flat.instructions = new_instructions;
    flat.loc_table = new_loc_table;

    if (sabPruneDebugEnabled(allocator)) {
        std.debug.print(
            "sab prune: funcs {d}->{d}, tests {d}->{d}, inst {d}->{d}, consts {d}->{d}, vtables_kept {d}\n",
            .{
                original_function_count,
                flat.function_sigs.len,
                original_test_count,
                flat.test_sigs.len,
                original_instruction_count,
                flat.instructions.len,
                original_const_count,
                flat.const_decls.len,
                reachable_vtable_consts.count(),
            },
        );
    }
}

fn cloneSabFunctionSig(allocator: std.mem.Allocator, source: flattener.FunctionSig) !flattener.FunctionSig {
    const name = try allocator.dupe(u8, source.name);
    errdefer allocator.free(name);

    const params = try allocator.alloc(common_signature.ParamSpec, source.params.len);
    errdefer allocator.free(params);
    var param_initialized: usize = 0;
    errdefer for (params[0..param_initialized]) |param| allocator.free(param.name);
    for (source.params, 0..) |param, idx| {
        params[idx] = .{
            .name = try allocator.dupe(u8, param.name),
            .ty = param.ty,
            .cap = param.cap,
        };
        param_initialized += 1;
    }

    const param_ids = try allocator.dupe(u32, source.param_ids);
    errdefer allocator.free(param_ids);
    const reg_ids = try allocator.dupe(u32, source.reg_ids);
    errdefer allocator.free(reg_ids);

    var upstream_file: ?[]u8 = null;
    errdefer if (upstream_file) |file| allocator.free(file);
    if (source.upstream_file) |file| upstream_file = try allocator.dupe(u8, file);

    var upstream_loc: ?common_upstream.UpstreamLoc = null;
    errdefer if (upstream_loc) |loc| allocator.free(loc.file);
    if (source.upstream_loc) |loc| {
        upstream_loc = .{
            .file = try allocator.dupe(u8, loc.file),
            .line = loc.line,
            .col = loc.col,
        };
    }

    var llvm_name: ?[]u8 = null;
    errdefer if (llvm_name) |value| allocator.free(value);
    if (source.llvm_name) |value| llvm_name = try allocator.dupe(u8, value);

    return .{
        .id = source.id,
        .name = name,
        .params = params,
        .kind = source.kind,
        .return_cap = source.return_cap,
        .return_ty = source.return_ty,
        .return_fallible = source.return_fallible,
        .entry_inst_idx = source.entry_inst_idx,
        .is_ffi_wrapper = source.is_ffi_wrapper,
        .upstream_file = upstream_file,
        .upstream_loc = upstream_loc,
        .param_ids = param_ids,
        .reg_ids = reg_ids,
        .llvm_name = llvm_name,
        .ignored = source.ignored,
        .should_panic = source.should_panic,
    };
}

var test_source_tree_load_count: usize = 0;

fn resolveProjectFromSourcePath(allocator: std.mem.Allocator, source_path: []const u8, package_name: ?[]const u8) !pkg_workspace.PackageResolution {
    const real_source = try std.fs.cwd().realpathAlloc(allocator, source_path);
    defer allocator.free(real_source);
    const source_dir = std.fs.path.dirname(real_source) orelse ".";
    return try pkg_workspace.resolveFromRootPath(allocator, source_dir, .{ .request = package_name });
}

fn projectRootFromSourcePath(allocator: std.mem.Allocator, source_path: []const u8) ![]u8 {
    var resolved = try resolveProjectFromSourcePath(allocator, source_path, null);
    defer resolved.deinit(allocator);
    return try allocator.dupe(u8, resolved.workspace_root);
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
    var resolved = try pkg_workspace.resolveFromCurrentDir(allocator, .{});
    defer resolved.deinit(allocator);
    return try allocator.dupe(u8, resolved.workspace_root);
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
    var memory_metrics: ?CompileMemoryMetrics = if (options.mem_report) .{} else null;
    if (memory_metrics) |*memory| {
        memory.recordStart();
        try writeMemoryStageSampleForOptions(options, "start", memory.start_rss_bytes, null);
    }

    const total_start = if (options.profile) std.time.Instant.now() catch null else null;
    if (std.mem.endsWith(u8, source_path, ".sab")) {
        const load_flat_start = if (options.profile) std.time.Instant.now() catch null else null;
        var flat = try loadSabFlat(allocator, source_path);
        errdefer flat.deinit(allocator);
        const load_flat_ns = if (load_flat_start) |start| elapsedNs(start) else null;
        const prune_start = if (options.profile) std.time.Instant.now() catch null else null;
        try pruneSabFlatToSelectedTests(allocator, &flat, options.sab_selected_test_names);
        const prune_ns = if (prune_start) |start| elapsedNs(start) else null;
        const verify_start = if (options.profile) std.time.Instant.now() catch null else null;
        const verified = try referee.verifyWithOptions(allocator, flat.instructions, flat.const_decls, .{
            .jobs = options.jobs,
            .stage_reporter = null,
            .predecoded_symbol_names = flat.symbols.names.items,
            .predecoded_function_sigs = flat.function_sigs,
            .check_exit_leaks = options.sab_selected_test_names.len == 0,
        });
        const verify_ns = if (verify_start) |start| elapsedNs(start) else null;
        if (options.profile) {
            var null_writer = std.io.null_writer;
            const writer = options.diagnostic_writer orelse null_writer.any();
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
            .ok => |ok| .{ .ok = .{ .flat = flat, .verified = ok, .metrics = computeCompileMetrics(&flat, &ok, if (options.profile) .{ .load_ns = load_flat_ns orelse 0, .setup_ns = 0, .flatten_ns = prune_ns orelse 0, .verify_ns = verify_ns orelse 0, .total_ns = if (total_start) |start| elapsedNs(start) else null } else null, memory_metrics) } },
            .trap => |report| {
                var r = report;
                if (r.file == null) setFile(&r, source_path);
                flat.deinit(allocator);
                return .{ .trap = r };
            },
        };
    }
    const load_start = if (options.profile) std.time.Instant.now() catch null else null;
    const source = try loadSource(allocator, source_path);
    defer allocator.free(source);
    const load_ns = if (load_start) |start| elapsedNs(start) else 0;
    if (memory_metrics) |*memory| {
        memory.recordAfterLoad();
        try writeMemoryStageSampleForOptions(options, "after_load", memory.after_load_rss_bytes, memory.start_rss_bytes);
    }

    const setup_start = if (options.profile) std.time.Instant.now() catch null else null;
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
        },
    };
    const setup_ns = if (setup_start) |start| elapsedNs(start) else 0;
    if (memory_metrics) |*memory| {
        memory.recordAfterSetup();
        try writeMemoryStageSampleForOptions(options, "after_setup", memory.after_setup_rss_bytes, memory.after_load_rss_bytes);
    }

    const flatten_start = if (options.profile) std.time.Instant.now() catch null else null;
    var flat = flattener.flattenFileWithContextAndPackages(allocator, source_path, source, &error_ctx, resolve_ctx) catch |err| {
        return .{ .trap = trapFromFlattenError(source_path, source, err, flattener.takeErrorSourceLine(&error_ctx)) };
    };
    errdefer flat.deinit(allocator);
    const flatten_ns = if (flatten_start) |start| elapsedNs(start) else 0;
    if (memory_metrics) |*memory| {
        memory.recordAfterFlatten();
        try writeMemoryStageSampleForOptions(options, "after_flatten", memory.after_flatten_rss_bytes, memory.after_setup_rss_bytes);
    }

    var null_writer = std.io.null_writer;
    var verifier_stage_context = MemoryStageReporterContext{
        .writer = options.diagnostic_writer orelse null_writer.any(),
        .memory = if (memory_metrics) |*memory| memory else null,
        .previous_rss_bytes = if (memory_metrics) |memory| memory.after_flatten_rss_bytes else null,
        .peak_rss_bytes = if (memory_metrics) |memory| memory.peak_rss_bytes else null,
        .live = options.mem_report_live,
    };
    const verifier_stage_reporter: ?referee.VerifyStageReporter = if (options.mem_report)
        .{ .context = &verifier_stage_context, .report_fn = reportVerifierMemoryStage }
    else
        null;

    const verify_start = if (options.profile) std.time.Instant.now() catch null else null;
    const verified = try referee.verifyWithOptions(allocator, flat.instructions, flat.const_decls, .{ .jobs = options.jobs, .package_grants = package_grants, .stage_reporter = verifier_stage_reporter });
    const verify_ns = if (verify_start) |start| elapsedNs(start) else 0;
    if (memory_metrics) |*memory| {
        memory.updatePeak(verifier_stage_context.peak_rss_bytes);
        memory.recordAfterVerify();
        try writeMemoryStageSampleForOptions(options, "after_verify", memory.after_verify_rss_bytes, memory.after_flatten_rss_bytes);
        memory.recordEnd();
    }

    return switch (verified) {
        .ok => |ok| blk: {
            const metrics = computeCompileMetrics(&flat, &ok, if (options.profile) .{ .load_ns = load_ns, .setup_ns = setup_ns, .flatten_ns = flatten_ns, .verify_ns = verify_ns, .total_ns = if (total_start) |start| elapsedNs(start) else null } else null, memory_metrics);
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

const build_cache_kinds = [_]BuildCacheKind{ .build_exe, .build_obj, .build_wasm, .build_obj_incremental, .test_cache };

fn parseBuildCacheKindName(name: []const u8) ?BuildCacheKind {
    for (build_cache_kinds) |kind| {
        if (std.mem.eql(u8, name, kind.dirName())) return kind;
    }
    return null;
}

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

const ProjectCacheKeyInputField = enum {
    schema,
    compiler,
    backend,
    toolchain,
    host_target,
    project,
    command,
    wasm_target,
    semantic_file_inputs,
    project_manifests,
    source_tree,

    fn jsonName(self: ProjectCacheKeyInputField) []const u8 {
        return switch (self) {
            .schema => "schema",
            .compiler => "compiler",
            .backend => "backend",
            .toolchain => "toolchain",
            .host_target => "host_target",
            .project => "project",
            .command => "command",
            .wasm_target => "wasm_target",
            .semantic_file_inputs => "semantic_file_inputs",
            .project_manifests => "project_manifests",
            .source_tree => "source_tree",
        };
    }
};

const project_cache_key_input_fields = [_]ProjectCacheKeyInputField{
    .schema,
    .compiler,
    .backend,
    .toolchain,
    .host_target,
    .project,
    .command,
    .wasm_target,
    .semantic_file_inputs,
    .project_manifests,
    .source_tree,
};

const ProjectCacheKeyInputTrace = struct {
    hashers: [project_cache_key_input_fields.len]std.crypto.hash.sha2.Sha256,
    seen: [project_cache_key_input_fields.len]bool,

    fn init() ProjectCacheKeyInputTrace {
        var trace: ProjectCacheKeyInputTrace = undefined;
        for (&trace.hashers) |*hasher| hasher.* = std.crypto.hash.sha2.Sha256.init(.{});
        trace.seen = [_]bool{false} ** project_cache_key_input_fields.len;
        return trace;
    }

    fn addBytes(self: *ProjectCacheKeyInputTrace, field: ProjectCacheKeyInputField, bytes: []const u8) void {
        const idx = @intFromEnum(field);
        self.seen[idx] = true;
        self.hashers[idx].update(bytes);
        self.hashers[idx].update(&[_]u8{0});
    }

    fn addBool(self: *ProjectCacheKeyInputTrace, field: ProjectCacheKeyInputField, value: bool) void {
        self.addBytes(field, &[_]u8{if (value) 1 else 0});
    }

    fn addU64(self: *ProjectCacheKeyInputTrace, field: ProjectCacheKeyInputField, value: u64) void {
        var buf: [8]u8 = undefined;
        std.mem.writeInt(u64, &buf, value, .little);
        self.addBytes(field, &buf);
    }

    fn digestHex(self: *const ProjectCacheKeyInputTrace, field: ProjectCacheKeyInputField) [64]u8 {
        var hasher = self.hashers[@intFromEnum(field)];
        var digest: [32]u8 = undefined;
        hasher.final(&digest);
        return std.fmt.bytesToHex(digest, .lower);
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

fn cacheTraceBytes(hasher: *std.crypto.hash.sha2.Sha256, trace: ?*ProjectCacheKeyInputTrace, field: ProjectCacheKeyInputField, bytes: []const u8) void {
    cacheBytes(hasher, bytes);
    if (trace) |key_trace| key_trace.addBytes(field, bytes);
}

fn cacheTraceU64(hasher: *std.crypto.hash.sha2.Sha256, trace: ?*ProjectCacheKeyInputTrace, field: ProjectCacheKeyInputField, value: u64) void {
    cacheU64(hasher, value);
    if (trace) |key_trace| key_trace.addU64(field, value);
}

fn cacheTraceBool(hasher: *std.crypto.hash.sha2.Sha256, trace: ?*ProjectCacheKeyInputTrace, field: ProjectCacheKeyInputField, value: bool) void {
    cacheBool(hasher, value);
    if (trace) |key_trace| key_trace.addBool(field, value);
}

fn cacheCompilerVersion() []const u8 {
    if (builtin.is_test) return "test";
    return build_options.version;
}

fn projectFileMaybeHash(hasher: *std.crypto.hash.sha2.Sha256, allocator: std.mem.Allocator, path: []const u8) !void {
    try projectFileMaybeHashWithTrace(hasher, null, allocator, path);
}

fn projectFileMaybeHashWithTrace(hasher: *std.crypto.hash.sha2.Sha256, trace: ?*ProjectCacheKeyInputTrace, allocator: std.mem.Allocator, path: []const u8) !void {
    if (!projectPathExists(path)) return;
    const bytes = try readTextFileAlloc(allocator, path);
    defer allocator.free(bytes);
    cacheBytes(hasher, bytes);
    if (trace) |key_trace| {
        key_trace.addBytes(.project_manifests, path);
        key_trace.addBytes(.project_manifests, bytes);
    }
}

const SourceTreeFileStat = struct {
    path: []u8,
    mtime: i128,
    size: u64,
};

const SourceTreeHashCacheEntry = struct {
    digest: [32]u8,
    project_cacheable: bool,
    files: []SourceTreeFileStat,
    last_used_tick: u64,
};

const SourceTreeHashResult = struct {
    digest: [32]u8,
    project_cacheable: bool,
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

fn sourceTreeHashCacheHit(cache_key: []const u8) ?SourceTreeHashResult {
    source_tree_hash_cache_mutex.lock();
    defer source_tree_hash_cache_mutex.unlock();
    const cache = sourceTreeHashCacheMap();
    const entry = cache.getPtr(cache_key) orelse return null;
    for (entry.files) |file| {
        const stat = std.fs.cwd().statFile(file.path) catch return null;
        if (stat.mtime != file.mtime or stat.size != file.size) return null;
    }
    entry.last_used_tick = nextSourceTreeHashCacheTickLocked();
    return .{ .digest = entry.digest, .project_cacheable = entry.project_cacheable };
}

fn storeSourceTreeHashCacheEntry(cache_key: []const u8, digest: [32]u8, project_cacheable: bool, files: []const SourceTreeFileStat) !void {
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
        old.* = .{ .digest = digest, .project_cacheable = project_cacheable, .files = owned_files, .last_used_tick = nextSourceTreeHashCacheTickLocked() };
        cache_allocator.free(owned_key);
        evictSourceTreeHashCacheIfNeeded(cache, sourceTreeHashCacheMaxEntries());
        return;
    }
    try cache.put(owned_key, .{ .digest = digest, .project_cacheable = project_cacheable, .files = owned_files, .last_used_tick = nextSourceTreeHashCacheTickLocked() });
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

fn addSourceTreeDigestToHasher(hasher: *std.crypto.hash.sha2.Sha256, trace: ?*ProjectCacheKeyInputTrace, digest: [32]u8) void {
    cacheBytes(hasher, "source-tree-digest-v1");
    hasher.update(&digest);
    if (trace) |key_trace| {
        key_trace.addBytes(.source_tree, "source-tree-digest-v1");
        key_trace.addBytes(.source_tree, &digest);
    }
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
    project_cacheable: *bool,
) !void {
    const real_source_path = try std.fs.cwd().realpathAlloc(allocator, source_path);
    var owned_by_files = false;
    errdefer if (!owned_by_files) allocator.free(real_source_path);
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
    owned_by_files = true;

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
        try hashResolvedSourceTreeUncached(allocator, hasher, dependencies, plugin_import_roots, project_root, std_root, offline, imported.entry_path, visited, files, imported.source, project_cacheable);
    }
}

fn hashResolvedSourceTree(
    allocator: std.mem.Allocator,
    hasher: *std.crypto.hash.sha2.Sha256,
    trace: ?*ProjectCacheKeyInputTrace,
    dependencies: []pkg_resolver.Dependency,
    plugin_import_roots: []const []const u8,
    project_root: []const u8,
    std_root: []const u8,
    offline: bool,
    source_path: []const u8,
) !bool {
    const real_source_path = try std.fs.cwd().realpathAlloc(allocator, source_path);
    defer allocator.free(real_source_path);
    const cache_key = try buildSourceTreeHashCacheKey(allocator, dependencies, plugin_import_roots, project_root, std_root, offline, real_source_path);
    defer allocator.free(cache_key);
    if (sourceTreeHashCacheHit(cache_key)) |result| {
        addSourceTreeDigestToHasher(hasher, trace, result.digest);
        return result.project_cacheable;
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
    var project_cacheable = true;
    try hashResolvedSourceTreeUncached(allocator, &tree_hasher, dependencies, plugin_import_roots, project_root, std_root, offline, source_path, &visited, &files, null, &project_cacheable);
    var digest: [32]u8 = undefined;
    tree_hasher.final(&digest);
    try storeSourceTreeHashCacheEntry(cache_key, digest, project_cacheable, files.items);
    addSourceTreeDigestToHasher(hasher, trace, digest);
    return project_cacheable;
}

fn computeProjectBuildKeyWithTrace(
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
    jobs: ?usize,
    jobs_explicit: bool,
    semantic_file_inputs: []const []const u8,
    trace: ?*ProjectCacheKeyInputTrace,
) !?ProjectCacheKey {
    const std_root = try stdRootFromEnv(allocator);
    defer allocator.free(std_root);

    var hasher = std.crypto.hash.sha2.Sha256.init(.{});
    var project_cacheable = true;
    cacheTraceBytes(&hasher, trace, .schema, "sa-build-cache-v3");
    cacheTraceBytes(&hasher, trace, .compiler, cacheCompilerVersion());
    const backend_identity = try emit_llvm_llvmc.backendCacheIdentity(allocator);
    defer allocator.free(backend_identity);
    cacheTraceBytes(&hasher, trace, .backend, backend_identity);
    const toolchain_identity = try driver.toolchainCacheIdentity(allocator, .{
        .path_env = if (builtin.is_test) project_build_key_toolchain_path_override else null,
        .include_objcopy = kind == .build_obj_incremental,
    });
    defer allocator.free(toolchain_identity);
    cacheTraceBytes(&hasher, trace, .toolchain, toolchain_identity);
    cacheTraceBytes(&hasher, trace, .compiler, builtin.zig_version_string);
    cacheTraceBytes(&hasher, trace, .host_target, @tagName(builtin.target.cpu.arch));
    cacheTraceBytes(&hasher, trace, .host_target, builtin.target.cpu.model.name);
    cacheTraceBytes(&hasher, trace, .host_target, @tagName(builtin.target.os.tag));
    cacheTraceBytes(&hasher, trace, .host_target, @tagName(builtin.target.abi));
    cacheTraceBytes(&hasher, trace, .project, project_root);
    cacheTraceBytes(&hasher, trace, .command, kind.dirName());
    cacheTraceBytes(&hasher, trace, .command, source_path);
    cacheTraceBytes(&hasher, trace, .command, target_name);
    cacheTraceBytes(&hasher, trace, .command, source_suffix);
    cacheTraceBool(&hasher, trace, .command, debug);
    cacheTraceBool(&hasher, trace, .command, release_fast);
    cacheTraceBool(&hasher, trace, .command, incremental);
    cacheTraceBytes(&hasher, trace, .command, dce.name());
    cacheTraceBool(&hasher, trace, .command, jobs_explicit);
    cacheTraceU64(&hasher, trace, .command, if (jobs) |count| @intCast(count) else 0);
    if (wasm) |target| {
        cacheTraceBytes(&hasher, trace, .wasm_target, target.triple);
        cacheTraceBool(&hasher, trace, .wasm_target, target.no_entry);
        cacheTraceU64(&hasher, trace, .wasm_target, target.size_bits);
    }
    for (semantic_file_inputs) |path| {
        const canonical_path = try std.fs.cwd().realpathAlloc(allocator, path);
        defer allocator.free(canonical_path);
        const stat = try std.fs.cwd().statFile(canonical_path);
        if (stat.kind != .file) return error.InvalidCacheInput;
        const digest_hex = try hashFileHex(allocator, canonical_path);
        cacheTraceBytes(&hasher, trace, .semantic_file_inputs, canonical_path);
        cacheTraceU64(&hasher, trace, .semantic_file_inputs, stat.size);
        cacheTraceBytes(&hasher, trace, .semantic_file_inputs, digest_hex[0..]);
    }

    const project_manifest = project_context.manifest;
    if (project_manifest) |*m| {
        cacheTraceBytes(&hasher, trace, .project_manifests, project_context.workspace_manifest_path);
        if (projectPathExists(project_context.workspace_manifest_path)) {
            const workspace_manifest_bytes = try readTextFileAlloc(allocator, project_context.workspace_manifest_path);
            defer allocator.free(workspace_manifest_bytes);
            cacheTraceBytes(&hasher, trace, .project_manifests, workspace_manifest_bytes);
        }
        if (!std.mem.eql(u8, project_context.member_manifest_path, project_context.workspace_manifest_path)) {
            cacheTraceBytes(&hasher, trace, .project_manifests, project_context.member_manifest_path);
            if (projectPathExists(project_context.member_manifest_path)) {
                const member_manifest_bytes = try readTextFileAlloc(allocator, project_context.member_manifest_path);
                defer allocator.free(member_manifest_bytes);
                cacheTraceBytes(&hasher, trace, .project_manifests, member_manifest_bytes);
            }
        }
        if (project_context.lock_file != null) {
            const lock_path = try projectLockPath(allocator, project_context.root_path);
            defer allocator.free(lock_path);
            try projectFileMaybeHashWithTrace(&hasher, trace, allocator, lock_path);
        }
        if (project_context.sum_file != null) {
            const sum_path = try projectSumPath(allocator, project_context.root_path);
            defer allocator.free(sum_path);
            try projectFileMaybeHashWithTrace(&hasher, trace, allocator, sum_path);
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
            project_cacheable = try hashResolvedSourceTree(allocator, &hasher, trace, dependency_slice, plugin_import_roots, project_context.root_path, std_root, offline, source_path);
        }
    } else {
        try projectFileMaybeHashWithTrace(&hasher, trace, allocator, project_context.workspace_manifest_path);
        if (!std.mem.eql(u8, project_context.member_manifest_path, project_context.workspace_manifest_path)) {
            try projectFileMaybeHashWithTrace(&hasher, trace, allocator, project_context.member_manifest_path);
        }
        if (hash_source_tree) {
            project_cacheable = try hashResolvedSourceTree(allocator, &hasher, trace, &.{}, &.{}, project_context.root_path, std_root, offline, source_path);
        }
    }

    if (!project_cacheable) return null;

    var out: [32]u8 = undefined;
    hasher.final(&out);
    return .{ .hex = std.fmt.bytesToHex(out, .lower) };
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
    jobs: ?usize,
    jobs_explicit: bool,
    semantic_file_inputs: []const []const u8,
) !?ProjectCacheKey {
    return try computeProjectBuildKeyWithTrace(allocator, project_context, project_root, source_path, target_name, source_suffix, kind, debug, release_fast, incremental, wasm, hash_source_tree, offline, dce, jobs, jobs_explicit, semantic_file_inputs, null);
}

fn computeProjectBuildKeyAndRecordInputs(
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
    jobs: ?usize,
    jobs_explicit: bool,
    semantic_file_inputs: []const []const u8,
) !?ProjectCacheKey {
    var trace = ProjectCacheKeyInputTrace.init();
    const key = try computeProjectBuildKeyWithTrace(allocator, project_context, project_root, source_path, target_name, source_suffix, kind, debug, release_fast, incremental, wasm, hash_source_tree, offline, dce, jobs, jobs_explicit, semantic_file_inputs, &trace);
    if (key) |cache_key| {
        projectCacheWriteKeyInputTelemetry(allocator, project_root, kind, cache_key, &trace) catch |err| {
            _ = @errorName(err);
        };
    }
    return key;
}

fn projectCacheDir(allocator: std.mem.Allocator, project_root: []const u8, kind: BuildCacheKind, key: ProjectCacheKey) ![]u8 {
    return try pathJoinAlloc(allocator, &.{ project_root, ".sa_cache", kind.dirName(), key.slice() });
}

fn projectCacheArtifactPath(allocator: std.mem.Allocator, project_root: []const u8, kind: BuildCacheKind, key: ProjectCacheKey, filename: []const u8) ![]u8 {
    const dir = try projectCacheDir(allocator, project_root, kind, key);
    defer allocator.free(dir);
    return try pathJoinAlloc(allocator, &.{ dir, filename });
}

fn projectCacheEntryPath(allocator: std.mem.Allocator, entry_dir: []const u8, filename: []const u8) ![]u8 {
    return try pathJoinAlloc(allocator, &.{ entry_dir, filename });
}

fn createProjectCacheStagingDir(allocator: std.mem.Allocator, final_dir: []const u8) ![]u8 {
    try ensureParentDir(final_dir);
    for (0..8) |_| {
        var random: [8]u8 = undefined;
        std.crypto.random.bytes(&random);
        const suffix = std.fmt.bytesToHex(random, .lower);
        const staging_dir = try std.fmt.allocPrint(allocator, "{s}.tmp.{s}", .{ final_dir, suffix[0..] });
        std.fs.cwd().makeDir(staging_dir) catch |err| switch (err) {
            error.PathAlreadyExists => {
                allocator.free(staging_dir);
                continue;
            },
            else => {
                allocator.free(staging_dir);
                return err;
            },
        };
        return staging_dir;
    }
    return error.PathAlreadyExists;
}

fn deleteCacheTree(path: []const u8) void {
    std.fs.cwd().deleteTree(path) catch |err| {
        _ = @errorName(err);
    };
}

fn renameCachePath(old_path: []const u8, new_path: []const u8) !void {
    if (std.fs.path.isAbsolute(old_path) and std.fs.path.isAbsolute(new_path)) {
        return try std.fs.renameAbsolute(old_path, new_path);
    }
    return try std.fs.cwd().rename(old_path, new_path);
}

fn syncCacheFile(path: []const u8) !void {
    var file = try std.fs.cwd().openFile(path, .{ .mode = .read_write });
    defer file.close();
    try file.sync();
}

fn copyCacheFileSynced(src_path: []const u8, dst_path: []const u8) !void {
    try ensureParentDir(dst_path);
    try std.fs.cwd().copyFile(src_path, std.fs.cwd(), dst_path, .{ .override_mode = std.fs.File.default_mode });
    try syncCacheFile(dst_path);
}

const ProjectCacheEntryLock = struct {
    file: std.fs.File,

    fn deinit(self: *ProjectCacheEntryLock) void {
        self.file.close();
        self.* = undefined;
    }
};

fn releaseProjectCacheOwner(owner: *?ProjectCacheEntryLock) void {
    if (owner.*) |*entry_lock| entry_lock.deinit();
    owner.* = null;
}

const ProjectCacheStoreTestPause = struct {
    reached: std.Thread.ResetEvent = .{},
    continue_event: std.Thread.ResetEvent = .{},
};

var project_cache_store_test_pause: ?*ProjectCacheStoreTestPause = null;
var project_build_key_toolchain_path_override: ?[]const u8 = null;

fn projectCacheLockPath(allocator: std.mem.Allocator, project_root: []const u8, kind: BuildCacheKind, key: ProjectCacheKey) ![]u8 {
    const filename = try std.fmt.allocPrint(allocator, "{s}.lock", .{key.slice()});
    defer allocator.free(filename);
    return try pathJoinAlloc(allocator, &.{ project_root, ".sa_cache", kind.dirName(), ".locks", filename });
}

fn projectCacheBuildLockPath(allocator: std.mem.Allocator, project_root: []const u8, kind: BuildCacheKind, key: ProjectCacheKey) ![]u8 {
    const filename = try std.fmt.allocPrint(allocator, "{s}.build.lock", .{key.slice()});
    defer allocator.free(filename);
    return try pathJoinAlloc(allocator, &.{ project_root, ".sa_cache", kind.dirName(), ".locks", filename });
}

fn acquireProjectCacheEntryLock(
    allocator: std.mem.Allocator,
    project_root: []const u8,
    kind: BuildCacheKind,
    key: ProjectCacheKey,
    mode: std.fs.File.Lock,
) !ProjectCacheEntryLock {
    const lock_path = try projectCacheLockPath(allocator, project_root, kind, key);
    defer allocator.free(lock_path);
    try ensureParentDir(lock_path);
    return .{ .file = try std.fs.cwd().createFile(lock_path, .{
        .read = true,
        .truncate = false,
        .lock = mode,
    }) };
}

fn acquireProjectCacheBuildLock(
    allocator: std.mem.Allocator,
    project_root: []const u8,
    kind: BuildCacheKind,
    key: ProjectCacheKey,
    mode: std.fs.File.Lock,
) !ProjectCacheEntryLock {
    const lock_path = try projectCacheBuildLockPath(allocator, project_root, kind, key);
    defer allocator.free(lock_path);
    try ensureParentDir(lock_path);
    return .{ .file = try std.fs.cwd().createFile(lock_path, .{
        .read = true,
        .truncate = false,
        .lock = mode,
    }) };
}

fn tryLockProjectCacheFileExclusive(file: std.fs.File) !bool {
    if (builtin.os.tag == .windows) {
        const windows = std.os.windows;
        const range_off: windows.LARGE_INTEGER = 0;
        const range_len: windows.LARGE_INTEGER = 1;
        var io_status_block: windows.IO_STATUS_BLOCK = undefined;
        windows.LockFile(
            file.handle,
            null,
            null,
            null,
            &io_status_block,
            &range_off,
            &range_len,
            null,
            windows.TRUE,
            windows.TRUE,
        ) catch |err| switch (err) {
            error.WouldBlock => return false,
            else => |lock_err| return lock_err,
        };
        return true;
    }
    return file.tryLock(.exclusive);
}

fn tryAcquireProjectCacheEntryLockInKindDir(kind_dir: std.fs.Dir, key_name: []const u8) !?ProjectCacheEntryLock {
    try kind_dir.makePath(".locks");
    var lock_name_buf: [96]u8 = undefined;
    const lock_name = try std.fmt.bufPrint(&lock_name_buf, ".locks/{s}.lock", .{key_name});
    var file = try kind_dir.createFile(lock_name, .{ .read = true, .truncate = false });
    errdefer file.close();
    if (!try tryLockProjectCacheFileExclusive(file)) {
        file.close();
        return null;
    }
    return .{ .file = file };
}

fn projectCacheArtifactExistsNonEmpty(path: []const u8) bool {
    if (!cachePathIsRegularFile(path)) return false;
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

fn jsonString(value: std.json.Value) ![]const u8 {
    return switch (value) {
        .string => |text| text,
        else => error.InvalidCacheManifest,
    };
}

fn jsonSha256(value: std.json.Value) !bool {
    const text = try jsonString(value);
    if (text.len != 64) return false;
    for (text) |byte| {
        switch (byte) {
            '0'...'9', 'a'...'f' => {},
            else => return false,
        }
    }
    return true;
}

fn projectCacheDynamicDependenciesWellFormed(value: std.json.Value) !bool {
    const dependencies = switch (value) {
        .array => |items| items.items,
        else => return error.InvalidCacheManifest,
    };
    if (dependencies.len > 4096) return false;

    for (dependencies) |dependency| {
        const object = switch (dependency) {
            .object => |object| object,
            else => return error.InvalidCacheManifest,
        };
        const kind = try jsonString(object.get("kind") orelse return error.InvalidCacheManifest);
        if (std.mem.eql(u8, kind, "environment")) {
            const key = try jsonString(object.get("key") orelse return error.InvalidCacheManifest);
            if (key.len == 0 or key.len > 4096) return false;
            const present = try jsonBool(object.get("present") orelse return error.InvalidCacheManifest);
            if (present) {
                if (!try jsonSha256(object.get("sha256") orelse return error.InvalidCacheManifest)) return false;
            } else if (object.get("sha256") != null) {
                return false;
            }
            continue;
        }
        if (std.mem.eql(u8, kind, "file")) {
            const path = try jsonString(object.get("path") orelse return error.InvalidCacheManifest);
            if (path.len == 0 or path.len > std.fs.max_path_bytes or !std.fs.path.isAbsolute(path)) return false;
            const size = object.get("size") orelse return error.InvalidCacheManifest;
            switch (size) {
                .integer => |integer| if (integer < 0) return false,
                else => return error.InvalidCacheManifest,
            }
            if (!try jsonSha256(object.get("sha256") orelse return error.InvalidCacheManifest)) return false;
            continue;
        }
        return false;
    }
    return true;
}

fn projectCacheDynamicDependenciesValid(allocator: std.mem.Allocator, value: std.json.Value) !bool {
    if (!try projectCacheDynamicDependenciesWellFormed(value)) return false;
    const dependencies = switch (value) {
        .array => |items| items.items,
        else => return error.InvalidCacheManifest,
    };
    if (dependencies.len > 4096) return false;

    for (dependencies) |dependency| {
        const kind = try jsonString(try jsonGetObject(dependency, "kind"));
        if (std.mem.eql(u8, kind, "environment")) {
            const key = try jsonString(try jsonGetObject(dependency, "key"));
            if (key.len == 0 or key.len > 4096) return false;
            const expected_present = try jsonBool(try jsonGetObject(dependency, "present"));
            const current_value: ?[]u8 = std.process.getEnvVarOwned(allocator, key) catch |err| switch (err) {
                error.EnvironmentVariableNotFound => null,
                else => return err,
            };
            defer if (current_value) |bytes| allocator.free(bytes);
            if (expected_present != (current_value != null)) return false;
            if (current_value) |bytes| {
                var digest: [32]u8 = undefined;
                std.crypto.hash.sha2.Sha256.hash(bytes, &digest, .{});
                const digest_hex = std.fmt.bytesToHex(digest, .lower);
                if (!jsonStringEquals(try jsonGetObject(dependency, "sha256"), digest_hex[0..])) return false;
            }
            continue;
        }
        if (std.mem.eql(u8, kind, "file")) {
            const path = try jsonString(try jsonGetObject(dependency, "path"));
            if (path.len == 0 or path.len > std.fs.max_path_bytes or !std.fs.path.isAbsolute(path)) return false;
            const stat = std.fs.cwd().statFile(path) catch return false;
            if (stat.kind != .file) return false;
            if (!jsonIntEquals(try jsonGetObject(dependency, "size"), stat.size)) return false;
            const digest_hex = try hashFileHex(allocator, path);
            if (!jsonStringEquals(try jsonGetObject(dependency, "sha256"), digest_hex[0..])) return false;
            continue;
        }
        return false;
    }
    return true;
}

fn projectCacheArtifactMatchesManifest(allocator: std.mem.Allocator, artifact_value: std.json.Value, path: []const u8) !bool {
    if (!cachePathIsRegularFile(path)) return false;
    const stat = std.fs.cwd().statFile(path) catch return false;
    if (stat.kind != .file or stat.size == 0) return false;
    if (!jsonIntEquals(try jsonGetObject(artifact_value, "size"), stat.size)) return false;
    const hash_hex = try hashFileHex(allocator, path);
    return jsonStringEquals(try jsonGetObject(artifact_value, "sha256"), hash_hex[0..]);
}

const ProjectCacheLookupReason = enum {
    hit,
    disabled,
    absent,
    dependency_changed,
    manifest_invalid,
    artifact_corrupt,
    incomplete,
    expired,
    security_context_changed,
    selection_changed,
    bypassed_untrusted,
    evicted,
    lock_owner_failed,
    unknown,

    fn jsonName(self: ProjectCacheLookupReason) []const u8 {
        return switch (self) {
            .hit => "hit",
            .disabled => "disabled",
            .absent => "absent",
            .dependency_changed => "dependency_changed",
            .manifest_invalid => "manifest_invalid",
            .artifact_corrupt => "artifact_corrupt",
            .incomplete => "incomplete",
            .expired => "expired",
            .security_context_changed => "security_context_changed",
            .selection_changed => "selection_changed",
            .bypassed_untrusted => "bypassed_untrusted",
            .evicted => "evicted",
            .lock_owner_failed => "lock_owner_failed",
            .unknown => "unknown",
        };
    }
};

fn projectCacheLookupReasonName(reason: ?ProjectCacheLookupReason) []const u8 {
    return (reason orelse ProjectCacheLookupReason.unknown).jsonName();
}

fn projectCacheArtifactLookupReason(allocator: std.mem.Allocator, artifact_value: std.json.Value, path: []const u8) ProjectCacheLookupReason {
    if (!projectCacheArtifactExistsNonEmpty(path)) return .incomplete;
    const matches = projectCacheArtifactMatchesManifest(allocator, artifact_value, path) catch |err| switch (err) {
        error.InvalidCacheManifest => return .manifest_invalid,
        else => return .unknown,
    };
    return if (matches) .hit else .artifact_corrupt;
}

fn projectCacheManifestLookupReason(
    allocator: std.mem.Allocator,
    project_root: []const u8,
    kind: BuildCacheKind,
    key: ProjectCacheKey,
    artifact_path: []const u8,
    out_path: []const u8,
) ProjectCacheLookupReason {
    const manifest_path = projectCacheManifestPath(allocator, project_root, kind, key) catch return .unknown;
    defer allocator.free(manifest_path);
    const manifest_stat = std.fs.cwd().statFile(manifest_path) catch |err| switch (err) {
        error.FileNotFound => return .absent,
        else => return .manifest_invalid,
    };
    if (manifest_stat.kind != .file or manifest_stat.size == 0) return .incomplete;
    if (!cachePathIsRegularFile(manifest_path)) return .incomplete;
    const manifest_bytes = readTextFileAlloc(allocator, manifest_path) catch return .manifest_invalid;
    defer allocator.free(manifest_bytes);
    var parsed = std.json.parseFromSlice(std.json.Value, allocator, manifest_bytes, .{}) catch return .manifest_invalid;
    defer parsed.deinit();
    // v1 had no dynamic-dependency contract and must never be reused.
    if (!jsonIntEquals(jsonGetObject(parsed.value, "version") catch return .manifest_invalid, 2)) return .manifest_invalid;
    if (!jsonStringEquals(jsonGetObject(parsed.value, "kind") catch return .manifest_invalid, kind.dirName())) return .manifest_invalid;
    if (!jsonStringEquals(jsonGetObject(parsed.value, "key") catch return .manifest_invalid, key.slice())) return .manifest_invalid;
    const dependencies = jsonGetObject(parsed.value, "dynamic_dependencies") catch return .manifest_invalid;
    if (!(projectCacheDynamicDependenciesWellFormed(dependencies) catch return .manifest_invalid)) return .manifest_invalid;
    if (!(projectCacheDynamicDependenciesValid(allocator, dependencies) catch return .unknown)) return .dependency_changed;
    const artifact_reason = projectCacheArtifactLookupReason(allocator, jsonGetObject(parsed.value, "artifact") catch return .manifest_invalid, artifact_path);
    if (artifact_reason != .hit) return artifact_reason;
    const output_reason = projectCacheArtifactLookupReason(allocator, jsonGetObject(parsed.value, "output") catch return .manifest_invalid, out_path);
    if (output_reason != .hit) return output_reason;
    if (kind == .test_cache) {
        const metadata_path = projectCacheTestMetadataPath(allocator, project_root, key) catch return .unknown;
        defer allocator.free(metadata_path);
        const metadata_reason = projectCacheArtifactLookupReason(allocator, jsonGetObject(parsed.value, "test_metadata") catch return .manifest_invalid, metadata_path);
        if (metadata_reason != .hit) return metadata_reason;
    }
    return .hit;
}

fn projectCacheManifestValid(
    allocator: std.mem.Allocator,
    project_root: []const u8,
    kind: BuildCacheKind,
    key: ProjectCacheKey,
    artifact_path: []const u8,
    out_path: []const u8,
) bool {
    return projectCacheManifestLookupReason(allocator, project_root, kind, key, artifact_path, out_path) == .hit;
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

fn writeProjectCacheDynamicDependencies(writer: anytype, dependencies: []const flattener.DynamicDependency) !void {
    try writer.writeByte('[');
    for (dependencies, 0..) |dependency, index| {
        if (index != 0) try writer.writeByte(',');
        switch (dependency.kind) {
            .environment => {
                try writer.writeAll("{\"kind\":\"environment\",\"key\":");
                try writeJsonString(writer, dependency.key);
                try writer.writeAll(",\"present\":");
                try writer.writeAll(if (dependency.present) "true" else "false");
                if (dependency.present) {
                    const digest_hex = std.fmt.bytesToHex(dependency.sha256, .lower);
                    try writer.writeAll(",\"sha256\":");
                    try writeJsonString(writer, digest_hex[0..]);
                }
                try writer.writeByte('}');
            },
            .file => {
                const digest_hex = std.fmt.bytesToHex(dependency.sha256, .lower);
                try writer.writeAll("{\"kind\":\"file\",\"path\":");
                try writeJsonString(writer, dependency.key);
                try writer.writeAll(",\"size\":");
                try writer.print("{d}", .{dependency.size});
                try writer.writeAll(",\"sha256\":");
                try writeJsonString(writer, digest_hex[0..]);
                try writer.writeByte('}');
            },
        }
    }
    try writer.writeByte(']');
}

const project_cache_manifest_max_bytes = 16 * 1024 * 1024;

fn writeCacheManifestBytesAtomically(allocator: std.mem.Allocator, manifest_path: []const u8, contents: []const u8) !void {
    if (contents.len > project_cache_manifest_max_bytes) return error.CacheManifestTooLarge;
    try ensureParentDir(manifest_path);
    var random: [8]u8 = undefined;
    std.crypto.random.bytes(&random);
    const suffix = std.fmt.bytesToHex(random, .lower);
    const tmp_path = try std.fmt.allocPrint(allocator, "{s}.tmp.{s}", .{ manifest_path, suffix[0..] });
    defer allocator.free(tmp_path);
    var file = try std.fs.cwd().createFile(tmp_path, .{ .exclusive = true });
    var file_open = true;
    errdefer std.fs.cwd().deleteFile(tmp_path) catch |err| {
        _ = @errorName(err);
    };
    errdefer if (file_open) file.close();
    try file.writeAll(contents);
    try file.sync();
    file.close();
    file_open = false;
    try renameCachePath(tmp_path, manifest_path);
}

fn projectCacheWriteKeyInputTelemetry(allocator: std.mem.Allocator, project_root: []const u8, kind: BuildCacheKind, key: ProjectCacheKey, trace: *const ProjectCacheKeyInputTrace) !void {
    const marker_path = try projectCacheKeyInputMarkerPath(allocator, project_root, kind, key);
    defer allocator.free(marker_path);

    var contents = std.ArrayList(u8).init(allocator);
    defer contents.deinit();
    var writer = contents.writer();
    try writer.writeAll("{\"version\":1,\"kind\":");
    try writeJsonString(writer, kind.dirName());
    try writer.writeAll(",\"key_prefix\":");
    try writeJsonString(writer, key.slice()[0..12]);
    try writer.writeAll(",\"fields\":[");
    var first = true;
    for (project_cache_key_input_fields) |field| {
        if (!trace.seen[@intFromEnum(field)]) continue;
        if (!first) try writer.writeByte(',');
        first = false;
        const digest_hex = trace.digestHex(field);
        try writer.writeAll("{\"name\":");
        try writeJsonString(writer, field.jsonName());
        try writer.writeAll(",\"sha256\":");
        try writeJsonString(writer, digest_hex[0..]);
        try writer.writeByte('}');
    }
    try writer.writeAll("]}\n");

    try writeCacheManifestBytesAtomically(allocator, marker_path, contents.items);
}

fn projectCacheWriteManifestAt(
    allocator: std.mem.Allocator,
    manifest_path: []const u8,
    kind: BuildCacheKind,
    key: ProjectCacheKey,
    cached_artifact: []const u8,
    cached_output: []const u8,
    cached_test_metadata: ?[]const u8,
    dynamic_dependencies: []const flattener.DynamicDependency,
) !void {
    try ensureParentDir(manifest_path);

    var contents = std.ArrayList(u8).init(allocator);
    defer contents.deinit();
    var writer = contents.writer();
    try writer.writeAll("{\"version\":2,\"kind\":");
    try writeJsonString(writer, kind.dirName());
    try writer.writeAll(",\"key\":");
    try writeJsonString(writer, key.slice());
    try writer.writeAll(",\"dynamic_dependencies\":");
    try writeProjectCacheDynamicDependencies(writer, dynamic_dependencies);
    try writer.writeByte(',');
    try writeCacheArtifactManifestEntry(writer, allocator, "artifact", cached_artifact);
    try writer.writeByte(',');
    try writeCacheArtifactManifestEntry(writer, allocator, "output", cached_output);
    if (kind == .test_cache) {
        const metadata_path = cached_test_metadata orelse return error.InvalidCacheManifest;
        try writer.writeByte(',');
        try writeCacheArtifactManifestEntry(writer, allocator, "test_metadata", metadata_path);
    }
    try writer.writeAll("}\n");

    try writeCacheManifestBytesAtomically(allocator, manifest_path, contents.items);
}

const ProjectCacheHitResult = union(enum) {
    miss: ProjectCacheLookupReason,
    hit,
    authorization_rejected,
};

const ProjectCacheClaimOwner = struct {
    lock: ProjectCacheEntryLock,
    miss_reason: ProjectCacheLookupReason,
};

const ProjectCacheClaimResult = union(enum) {
    hit,
    owner: ProjectCacheClaimOwner,
    authorization_rejected,
};

fn projectCacheHitLocked(
    allocator: std.mem.Allocator,
    project_root: []const u8,
    kind: BuildCacheKind,
    key: ProjectCacheKey,
    project_context: *const ProjectContext,
    options: CompileOptions,
    artifact_path: []const u8,
    out_path: []const u8,
    stderr: anytype,
    diagnostics_mode: DiagnosticsMode,
) !ProjectCacheHitResult {
    const cached_artifact = try projectCacheArtifactPath(allocator, project_root, kind, key, "artifact.sa.bc");
    defer allocator.free(cached_artifact);
    const cached_output = try projectCacheArtifactPath(allocator, project_root, kind, key, "output.bin");
    defer allocator.free(cached_output);
    const lookup_reason = projectCacheManifestLookupReason(allocator, project_root, kind, key, cached_artifact, cached_output);
    if (lookup_reason != .hit) return .{ .miss = lookup_reason };

    // A cache manifest proves artifact identity, not that this request is
    // currently authorized to use it. Run package and permission checks only
    // after finding a valid entry, but before publishing either cached file.
    if (project_context.manifest) |project_manifest| {
        verifyProjectPackageState(allocator, project_context.root_path, project_manifest, options) catch |err| {
            if (trapFromPackagePreflightError(err)) |report| {
                try printTrapReport(stderr, report, diagnostics_mode);
                return .authorization_rejected;
            }
            return err;
        };
    }
    copyFileAlloc(allocator, cached_artifact, artifact_path) catch |err| {
        return err;
    };
    copyFileAlloc(allocator, cached_output, out_path) catch |err| {
        return err;
    };
    return .hit;
}

fn projectCacheClaim(
    allocator: std.mem.Allocator,
    project_root: []const u8,
    kind: BuildCacheKind,
    key: ProjectCacheKey,
    project_context: *const ProjectContext,
    options: CompileOptions,
    artifact_path: []const u8,
    out_path: []const u8,
    stderr: anytype,
    diagnostics_mode: DiagnosticsMode,
) !ProjectCacheClaimResult {
    {
        var entry_lock = try acquireProjectCacheEntryLock(allocator, project_root, kind, key, .shared);
        defer entry_lock.deinit();
        switch (try projectCacheHitLocked(allocator, project_root, kind, key, project_context, options, artifact_path, out_path, stderr, diagnostics_mode)) {
            .miss => {},
            .hit => {
                projectCacheTouchHitTelemetry(allocator, project_root, kind, key) catch |err| {
                    _ = @errorName(err);
                };
                return .hit;
            },
            .authorization_rejected => return .authorization_rejected,
        }
    }

    var owner = try acquireProjectCacheBuildLock(allocator, project_root, kind, key, .exclusive);
    errdefer owner.deinit();
    {
        var entry_lock = try acquireProjectCacheEntryLock(allocator, project_root, kind, key, .shared);
        defer entry_lock.deinit();
        switch (try projectCacheHitLocked(allocator, project_root, kind, key, project_context, options, artifact_path, out_path, stderr, diagnostics_mode)) {
            .miss => |reason| return .{ .owner = .{ .lock = owner, .miss_reason = reason } },
            .hit => {
                projectCacheTouchHitTelemetry(allocator, project_root, kind, key) catch |err| {
                    _ = @errorName(err);
                };
                owner.deinit();
                return .hit;
            },
            .authorization_rejected => {
                owner.deinit();
                return .authorization_rejected;
            },
        }
    }
}

fn projectCacheEntryValidAtPath(kind: BuildCacheKind, key: ProjectCacheKey, entry_path: []const u8) bool {
    var entry_dir = std.fs.cwd().openDir(entry_path, .{}) catch return false;
    defer entry_dir.close();
    return cacheEntryComplete(kind, entry_dir) and cacheEntryManifestValid(kind, key.slice(), entry_dir);
}

fn projectCacheEntryReusableNow(allocator: std.mem.Allocator, project_root: []const u8, kind: BuildCacheKind, key: ProjectCacheKey) bool {
    const cached_artifact = projectCacheArtifactPath(allocator, project_root, kind, key, "artifact.sa.bc") catch return false;
    defer allocator.free(cached_artifact);
    const cached_output = projectCacheArtifactPath(allocator, project_root, kind, key, "output.bin") catch return false;
    defer allocator.free(cached_output);
    if (!projectCacheArtifactExistsNonEmpty(cached_artifact) or !projectCacheArtifactExistsNonEmpty(cached_output)) return false;
    if (kind == .test_cache) {
        const metadata_path = projectCacheTestMetadataPath(allocator, project_root, key) catch return false;
        defer allocator.free(metadata_path);
        if (!projectCacheArtifactExistsNonEmpty(metadata_path)) return false;
    }
    if (!projectCacheManifestValid(allocator, project_root, kind, key, cached_artifact, cached_output)) return false;
    if (kind == .test_cache) {
        var test_list = projectCacheReadTestMetadata(allocator, project_root, key) catch return false;
        test_list.deinit(allocator);
    }
    return true;
}

const ProjectCachePublishResult = enum {
    published,
    winner_exists,
};

fn publishProjectCacheEntry(kind: BuildCacheKind, key: ProjectCacheKey, staging_dir: []const u8, final_dir: []const u8) !ProjectCachePublishResult {
    renameCachePath(staging_dir, final_dir) catch |err| switch (err) {
        error.PathAlreadyExists => if (projectCacheEntryValidAtPath(kind, key, final_dir)) return .winner_exists else return err,
        // Windows can report AccessDenied for a directory rename collision.
        // Only accept it as a winner when the existing entry is structurally
        // complete; unrelated access failures must remain visible.
        error.AccessDenied => if (projectCacheEntryValidAtPath(kind, key, final_dir)) return .winner_exists else return err,
        else => return err,
    };
    return .published;
}

fn projectCacheStore(
    allocator: std.mem.Allocator,
    project_root: []const u8,
    kind: BuildCacheKind,
    key: ProjectCacheKey,
    artifact_path: []const u8,
    out_path: []const u8,
    dynamic_dependencies: []const flattener.DynamicDependency,
) !void {
    try projectCacheStoreWithOwnerMissReason(allocator, project_root, kind, key, artifact_path, out_path, dynamic_dependencies, null);
}

fn projectCacheStoreWithOwnerMissReason(
    allocator: std.mem.Allocator,
    project_root: []const u8,
    kind: BuildCacheKind,
    key: ProjectCacheKey,
    artifact_path: []const u8,
    out_path: []const u8,
    dynamic_dependencies: []const flattener.DynamicDependency,
    owner_miss_reason: ?ProjectCacheLookupReason,
) !void {
    try projectCacheStoreEntry(allocator, project_root, kind, key, artifact_path, out_path, null, dynamic_dependencies, owner_miss_reason);
}

fn projectCacheTestMetadataPath(allocator: std.mem.Allocator, project_root: []const u8, key: ProjectCacheKey) ![]u8 {
    return try projectCacheArtifactPath(allocator, project_root, .test_cache, key, "test-metadata.json");
}

fn projectCacheHitMarkerPath(allocator: std.mem.Allocator, project_root: []const u8, kind: BuildCacheKind, key: ProjectCacheKey) ![]u8 {
    return try pathJoinAlloc(allocator, &.{ project_root, ".sa_cache", ".hits", kind.dirName(), key.slice() });
}

fn projectCacheStoreMarkerPath(allocator: std.mem.Allocator, project_root: []const u8, kind: BuildCacheKind, key: ProjectCacheKey) ![]u8 {
    return try pathJoinAlloc(allocator, &.{ project_root, ".sa_cache", ".stores", kind.dirName(), key.slice() });
}

fn projectCacheStoreEventMarkerPath(allocator: std.mem.Allocator, project_root: []const u8, kind: BuildCacheKind, key: ProjectCacheKey) ![]u8 {
    return try pathJoinAlloc(allocator, &.{ project_root, ".sa_cache", ".store-events", kind.dirName(), key.slice() });
}

fn projectCacheStoreEventHistoryDirPath(allocator: std.mem.Allocator, project_root: []const u8, kind: BuildCacheKind, key: ProjectCacheKey) ![]u8 {
    return try pathJoinAlloc(allocator, &.{ project_root, ".sa_cache", ".store-event-history", kind.dirName(), key.slice() });
}

fn projectCacheKeyInputMarkerPath(allocator: std.mem.Allocator, project_root: []const u8, kind: BuildCacheKind, key: ProjectCacheKey) ![]u8 {
    const filename = try std.fmt.allocPrint(allocator, "{s}.json", .{key.slice()});
    defer allocator.free(filename);
    return try pathJoinAlloc(allocator, &.{ project_root, ".sa_cache", ".key-inputs", kind.dirName(), filename });
}

fn projectCacheEvictionMarkerPath(allocator: std.mem.Allocator, project_root: []const u8, kind: BuildCacheKind, key: ProjectCacheKey) ![]u8 {
    return try pathJoinAlloc(allocator, &.{ project_root, ".sa_cache", ".evictions", kind.dirName(), key.slice() });
}

fn projectCacheTouchTelemetryMarker(allocator: std.mem.Allocator, marker_path: []const u8) !void {
    _ = allocator;
    try ensureParentDir(marker_path);
    var file = try std.fs.cwd().createFile(marker_path, .{ .truncate = true });
    defer file.close();
    try file.sync();
}

fn projectCacheTouchHitTelemetry(allocator: std.mem.Allocator, project_root: []const u8, kind: BuildCacheKind, key: ProjectCacheKey) !void {
    const marker_path = try projectCacheHitMarkerPath(allocator, project_root, kind, key);
    defer allocator.free(marker_path);
    try projectCacheTouchTelemetryMarker(allocator, marker_path);
}

fn projectCacheStoreEventWriterPid() ?u64 {
    return switch (builtin.os.tag) {
        .linux => @as(u64, @intCast(std.os.linux.getpid())),
        .macos, .ios, .tvos, .watchos, .visionos, .freebsd, .netbsd, .openbsd, .dragonfly => @as(u64, @intCast(std.c.getpid())),
        .windows => @as(u64, @intCast(std.os.windows.GetCurrentProcessId())),
        else => null,
    };
}

fn projectCacheStoreEventWriterStartTicks() ?u64 {
    if (builtin.os.tag != .linux) return null;

    var file = std.fs.openFileAbsolute("/proc/self/stat", .{}) catch return null;
    defer file.close();

    var buf: [4096]u8 = undefined;
    const n = file.readAll(&buf) catch return null;
    const text = buf[0..n];
    const close_paren = std.mem.lastIndexOf(u8, text, ") ") orelse return null;
    var it = std.mem.tokenizeAny(u8, text[close_paren + 2 ..], " \t\r\n");
    for (0..19) |_| _ = it.next() orelse return null;
    const start_ticks_text = it.next() orelse return null;
    return std.fmt.parseInt(u64, start_ticks_text, 10) catch null;
}

fn writeProjectCacheStoreEventJson(writer: anytype, kind: BuildCacheKind, key: ProjectCacheKey, result: []const u8, stage: []const u8, event_ns: i128, writer_pid: ?u64, writer_start_ticks: ?u64, owner_miss_reason: ?ProjectCacheLookupReason) !void {
    try writer.writeAll("{\"version\":1,\"result\":");
    try writeJsonString(writer, result);
    try writer.writeAll(",\"kind\":");
    try writeJsonString(writer, kind.dirName());
    try writer.writeAll(",\"stage\":");
    try writeJsonString(writer, stage);
    try writer.writeAll(",\"key_prefix\":");
    try writeJsonString(writer, key.slice()[0..12]);
    try writer.writeAll(",\"event_ns\":");
    try writer.print("{d}", .{event_ns});
    try writer.writeAll(",\"writer_pid\":");
    if (writer_pid) |pid| {
        try writer.print("{d}", .{pid});
    } else {
        try writer.writeAll("null");
    }
    try writer.writeAll(",\"writer_start_ticks\":");
    if (writer_start_ticks) |ticks| {
        try writer.print("{d}", .{ticks});
    } else {
        try writer.writeAll("null");
    }
    try writer.writeAll(",\"owner_miss_reason\":");
    if (owner_miss_reason) |reason| {
        try writeJsonString(writer, reason.jsonName());
    } else {
        try writer.writeAll("null");
    }
    try writer.writeAll("}\n");
}

fn projectCacheWriteStoreEventTelemetry(allocator: std.mem.Allocator, project_root: []const u8, kind: BuildCacheKind, key: ProjectCacheKey, result: []const u8, stage: []const u8, owner_miss_reason: ?ProjectCacheLookupReason) !void {
    const event_ns = std.time.nanoTimestamp();
    const writer_pid = projectCacheStoreEventWriterPid();
    const writer_start_ticks = projectCacheStoreEventWriterStartTicks();

    const event_path = try projectCacheStoreEventMarkerPath(allocator, project_root, kind, key);
    defer allocator.free(event_path);
    try ensureParentDir(event_path);
    var event_file = try std.fs.cwd().createFile(event_path, .{ .truncate = true });
    defer event_file.close();
    try writeProjectCacheStoreEventJson(event_file.writer(), kind, key, result, stage, event_ns, writer_pid, writer_start_ticks, owner_miss_reason);
    try event_file.sync();

    const history_dir = try projectCacheStoreEventHistoryDirPath(allocator, project_root, kind, key);
    defer allocator.free(history_dir);
    try std.fs.cwd().makePath(history_dir);
    var random: [8]u8 = undefined;
    std.crypto.random.bytes(&random);
    const suffix = std.fmt.bytesToHex(random, .lower);
    const filename = try std.fmt.allocPrint(allocator, "{d}-{s}.json", .{ event_ns, suffix[0..] });
    defer allocator.free(filename);
    const history_path = try pathJoinAlloc(allocator, &.{ history_dir, filename });
    defer allocator.free(history_path);
    var history_file = try std.fs.cwd().createFile(history_path, .{ .exclusive = true });
    defer history_file.close();
    try writeProjectCacheStoreEventJson(history_file.writer(), kind, key, result, stage, event_ns, writer_pid, writer_start_ticks, owner_miss_reason);
    try history_file.sync();
}

fn projectCacheTouchStoreTelemetry(allocator: std.mem.Allocator, project_root: []const u8, kind: BuildCacheKind, key: ProjectCacheKey, owner_miss_reason: ?ProjectCacheLookupReason) !void {
    const marker_path = try projectCacheStoreMarkerPath(allocator, project_root, kind, key);
    defer allocator.free(marker_path);
    try projectCacheTouchTelemetryMarker(allocator, marker_path);
    try projectCacheWriteStoreEventTelemetry(allocator, project_root, kind, key, "published", "publish", owner_miss_reason);
}

fn projectCacheTouchStoreFailureTelemetry(allocator: std.mem.Allocator, project_root: []const u8, kind: BuildCacheKind, key: ProjectCacheKey, stage: []const u8, owner_miss_reason: ?ProjectCacheLookupReason) !void {
    try projectCacheWriteStoreEventTelemetry(allocator, project_root, kind, key, "failed", stage, owner_miss_reason);
}

fn projectCacheTouchEvictionTelemetry(allocator: std.mem.Allocator, project_root: []const u8, kind: BuildCacheKind, key: ProjectCacheKey) !void {
    const marker_path = try projectCacheEvictionMarkerPath(allocator, project_root, kind, key);
    defer allocator.free(marker_path);
    try projectCacheTouchTelemetryMarker(allocator, marker_path);
}

fn projectCacheClearEvictionTelemetry(allocator: std.mem.Allocator, project_root: []const u8, kind: BuildCacheKind, key: ProjectCacheKey) !void {
    const marker_path = try projectCacheEvictionMarkerPath(allocator, project_root, kind, key);
    defer allocator.free(marker_path);
    std.fs.cwd().deleteFile(marker_path) catch |err| switch (err) {
        error.FileNotFound => {},
        else => return err,
    };
}

fn writeOptionalJsonString(writer: anytype, value: ?[]const u8) !void {
    if (value) |text| {
        try writeJsonString(writer, text);
    } else {
        try writer.writeAll("null");
    }
}

fn projectCacheWriteTestMetadataAt(
    allocator: std.mem.Allocator,
    metadata_path: []const u8,
    test_list: test_meta.TestList,
) !void {
    _ = allocator;
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
    try file.sync();
}

fn projectCacheStoreEntryLocked(
    allocator: std.mem.Allocator,
    project_root: []const u8,
    kind: BuildCacheKind,
    key: ProjectCacheKey,
    artifact_path: []const u8,
    out_path: []const u8,
    test_list: ?test_meta.TestList,
    dynamic_dependencies: []const flattener.DynamicDependency,
    owner_miss_reason: ?ProjectCacheLookupReason,
) !void {
    var store_failure_stage: []const u8 = "validate";
    errdefer projectCacheTouchStoreFailureTelemetry(std.heap.page_allocator, project_root, kind, key, store_failure_stage, owner_miss_reason) catch |err| {
        _ = @errorName(err);
    };

    if ((kind == .test_cache) != (test_list != null)) return error.InvalidCacheManifest;
    store_failure_stage = "prepare";
    const final_dir = try projectCacheDir(allocator, project_root, kind, key);
    defer allocator.free(final_dir);
    if (projectCacheEntryReusableNow(allocator, project_root, kind, key)) return;
    if (projectPathExists(final_dir)) {
        // The exclusive key lock pins readers and other writers while an old
        // unusable entry is retired. Readers therefore observe either the old
        // complete directory or the final staging rename, never partial files.
        store_failure_stage = "cleanup_old";
        try std.fs.cwd().deleteTree(final_dir);
    }

    store_failure_stage = "stage";
    const staging_dir = try createProjectCacheStagingDir(allocator, final_dir);
    defer allocator.free(staging_dir);
    var staging_live = true;
    defer if (staging_live) deleteCacheTree(staging_dir);

    const cached_artifact = try projectCacheEntryPath(allocator, staging_dir, "artifact.sa.bc");
    defer allocator.free(cached_artifact);
    const cached_output = try projectCacheEntryPath(allocator, staging_dir, "output.bin");
    defer allocator.free(cached_output);
    const cached_test_metadata = if (test_list != null)
        try projectCacheEntryPath(allocator, staging_dir, "test-metadata.json")
    else
        null;
    defer if (cached_test_metadata) |path| allocator.free(path);
    const manifest_path = try projectCacheEntryPath(allocator, staging_dir, "manifest.json");
    defer allocator.free(manifest_path);

    store_failure_stage = "copy_artifact";
    try copyCacheFileSynced(artifact_path, cached_artifact);
    store_failure_stage = "copy_output";
    try copyCacheFileSynced(out_path, cached_output);
    if (test_list) |metadata| {
        store_failure_stage = "test_metadata";
        try projectCacheWriteTestMetadataAt(allocator, cached_test_metadata.?, metadata);
    } else if (kind == .test_cache) {
        store_failure_stage = "validate";
        return error.InvalidCacheManifest;
    }
    store_failure_stage = "manifest";
    try projectCacheWriteManifestAt(allocator, manifest_path, kind, key, cached_artifact, cached_output, cached_test_metadata, dynamic_dependencies);
    if (builtin.is_test) {
        if (project_cache_store_test_pause) |pause| {
            pause.reached.set();
            pause.continue_event.wait();
        }
    }
    store_failure_stage = "publish";
    switch (try publishProjectCacheEntry(kind, key, staging_dir, final_dir)) {
        .published => {
            staging_live = false;
            projectCacheClearEvictionTelemetry(std.heap.page_allocator, project_root, kind, key) catch |err| {
                _ = @errorName(err);
            };
            projectCacheTouchStoreTelemetry(std.heap.page_allocator, project_root, kind, key, owner_miss_reason) catch |err| {
                _ = @errorName(err);
            };
        },
        .winner_exists => {},
    }
}

fn projectCacheStoreEntry(
    allocator: std.mem.Allocator,
    project_root: []const u8,
    kind: BuildCacheKind,
    key: ProjectCacheKey,
    artifact_path: []const u8,
    out_path: []const u8,
    test_list: ?test_meta.TestList,
    dynamic_dependencies: []const flattener.DynamicDependency,
    owner_miss_reason: ?ProjectCacheLookupReason,
) !void {
    var entry_lock = acquireProjectCacheEntryLock(allocator, project_root, kind, key, .exclusive) catch |err| {
        projectCacheTouchStoreFailureTelemetry(std.heap.page_allocator, project_root, kind, key, "lock", owner_miss_reason) catch |telemetry_err| {
            _ = @errorName(telemetry_err);
        };
        return err;
    };
    defer entry_lock.deinit();
    try projectCacheStoreEntryLocked(allocator, project_root, kind, key, artifact_path, out_path, test_list, dynamic_dependencies, owner_miss_reason);
}

fn projectCacheStoreTest(
    allocator: std.mem.Allocator,
    project_root: []const u8,
    key: ProjectCacheKey,
    artifact_path: []const u8,
    out_path: []const u8,
    test_list: test_meta.TestList,
    dynamic_dependencies: []const flattener.DynamicDependency,
) !void {
    try projectCacheStoreTestWithOwnerMissReason(allocator, project_root, key, artifact_path, out_path, test_list, dynamic_dependencies, null);
}

fn projectCacheStoreTestWithOwnerMissReason(
    allocator: std.mem.Allocator,
    project_root: []const u8,
    key: ProjectCacheKey,
    artifact_path: []const u8,
    out_path: []const u8,
    test_list: test_meta.TestList,
    dynamic_dependencies: []const flattener.DynamicDependency,
    owner_miss_reason: ?ProjectCacheLookupReason,
) !void {
    try projectCacheStoreEntry(allocator, project_root, .test_cache, key, artifact_path, out_path, test_list, dynamic_dependencies, owner_miss_reason);
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
    if (!cachePathIsRegularFile(metadata_path)) return error.InvalidCacheManifest;
    const metadata_bytes = try readTextFileAlloc(allocator, metadata_path);
    defer allocator.free(metadata_bytes);
    return try parseProjectCacheTestMetadata(allocator, metadata_bytes);
}

fn parseProjectCacheTestMetadata(allocator: std.mem.Allocator, metadata_bytes: []const u8) !test_meta.TestList {
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

const ProjectCacheTestHitResult = union(enum) {
    miss: ProjectCacheLookupReason,
    hit: test_meta.TestList,
    authorization_rejected,
};

const ProjectCacheTestClaimResult = union(enum) {
    hit: test_meta.TestList,
    owner: ProjectCacheClaimOwner,
    authorization_rejected,
};

fn projectCacheTestHitLocked(
    allocator: std.mem.Allocator,
    project_root: []const u8,
    key: ProjectCacheKey,
    project_context: *const ProjectContext,
    options: CompileOptions,
    artifact_path: []const u8,
    out_path: []const u8,
    stderr: anytype,
    diagnostics_mode: DiagnosticsMode,
) !ProjectCacheTestHitResult {
    switch (try projectCacheHitLocked(allocator, project_root, .test_cache, key, project_context, options, artifact_path, out_path, stderr, diagnostics_mode)) {
        .miss => |reason| return .{ .miss = reason },
        .authorization_rejected => return .authorization_rejected,
        .hit => {
            const test_list = projectCacheReadTestMetadata(allocator, project_root, key) catch |err| switch (err) {
                error.OutOfMemory => return err,
                else => return .{ .miss = .artifact_corrupt },
            };
            return .{ .hit = test_list };
        },
    }
}

fn projectCacheTestClaim(
    allocator: std.mem.Allocator,
    project_root: []const u8,
    key: ProjectCacheKey,
    project_context: *const ProjectContext,
    options: CompileOptions,
    artifact_path: []const u8,
    out_path: []const u8,
    stderr: anytype,
    diagnostics_mode: DiagnosticsMode,
) !ProjectCacheTestClaimResult {
    {
        var entry_lock = try acquireProjectCacheEntryLock(allocator, project_root, .test_cache, key, .shared);
        defer entry_lock.deinit();
        switch (try projectCacheTestHitLocked(allocator, project_root, key, project_context, options, artifact_path, out_path, stderr, diagnostics_mode)) {
            .miss => {},
            .hit => |test_list| {
                projectCacheTouchHitTelemetry(allocator, project_root, .test_cache, key) catch |err| {
                    _ = @errorName(err);
                };
                return .{ .hit = test_list };
            },
            .authorization_rejected => return .authorization_rejected,
        }
    }

    var owner = try acquireProjectCacheBuildLock(allocator, project_root, .test_cache, key, .exclusive);
    errdefer owner.deinit();
    {
        var entry_lock = try acquireProjectCacheEntryLock(allocator, project_root, .test_cache, key, .shared);
        defer entry_lock.deinit();
        switch (try projectCacheTestHitLocked(allocator, project_root, key, project_context, options, artifact_path, out_path, stderr, diagnostics_mode)) {
            .miss => |reason| return .{ .owner = .{ .lock = owner, .miss_reason = reason } },
            .hit => |test_list| {
                projectCacheTouchHitTelemetry(allocator, project_root, .test_cache, key) catch |err| {
                    _ = @errorName(err);
                };
                owner.deinit();
                return .{ .hit = test_list };
            },
            .authorization_rejected => {
                owner.deinit();
                return .authorization_rejected;
            },
        }
    }
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

fn cacheStagingKey(name: []const u8) ?[]const u8 {
    const separator = ".tmp.";
    if (name.len != 64 + separator.len + 16) return null;
    if (!isHexCacheKey(name[0..64]) or !std.mem.eql(u8, name[64 .. 64 + separator.len], separator)) return null;
    for (name[64 + separator.len ..]) |byte| {
        switch (byte) {
            '0'...'9', 'a'...'f' => {},
            else => return null,
        }
    }
    return name[0..64];
}

fn cacheEntryExpired(stat: std.fs.File.Stat, max_age_days: u64) bool {
    if (max_age_days == 0) return false;
    const now = std.time.nanoTimestamp();
    if (stat.mtime >= now) return false;
    const max_age_ns = @as(i128, @intCast(max_age_days)) * 24 * 60 * 60 * std.time.ns_per_s;
    return now - stat.mtime > max_age_ns;
}

fn cacheDirFileIsRegularFile(dir: std.fs.Dir, name: []const u8) bool {
    var link_buf: [std.fs.max_path_bytes]u8 = undefined;
    _ = dir.readLink(name, &link_buf) catch |err| switch (err) {
        error.NotLink => {
            const stat = dir.statFile(name) catch return false;
            return stat.kind == .file;
        },
        else => return false,
    };
    return false;
}

fn cacheFilePresentNonEmpty(dir: std.fs.Dir, name: []const u8) bool {
    if (!cacheDirFileIsRegularFile(dir, name)) return false;
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
    if (!cacheDirFileIsRegularFile(entry_dir, name)) return false;
    const stat = entry_dir.statFile(name) catch return false;
    if (stat.kind != .file or stat.size == 0) return false;
    if (!jsonIntEquals(try jsonGetObject(artifact_value, "size"), stat.size)) return false;
    const hash_hex = try hashDirFileHex(entry_dir, name);
    return jsonStringEquals(try jsonGetObject(artifact_value, "sha256"), hash_hex[0..]);
}

fn cacheEntryTestMetadataValid(entry_dir: std.fs.Dir) bool {
    if (!cacheDirFileIsRegularFile(entry_dir, "test-metadata.json")) return false;
    const metadata_bytes = entry_dir.readFileAlloc(std.heap.page_allocator, "test-metadata.json", 16 * 1024 * 1024) catch return false;
    defer std.heap.page_allocator.free(metadata_bytes);
    var test_list = parseProjectCacheTestMetadata(std.heap.page_allocator, metadata_bytes) catch return false;
    defer test_list.deinit(std.heap.page_allocator);
    return true;
}

fn cacheEntryManifestValid(kind: BuildCacheKind, key_name: []const u8, entry_dir: std.fs.Dir) bool {
    if (kind == .build_obj_incremental) {
        var incremental_manifest = readIncrementalObjectManifest(std.heap.page_allocator, entry_dir, key_name, null) catch return false;
        defer incremental_manifest.deinit(std.heap.page_allocator);
        return incremental_manifest.complete();
    }
    if (!cacheDirFileIsRegularFile(entry_dir, "manifest.json")) return false;
    const manifest_bytes = entry_dir.readFileAlloc(std.heap.page_allocator, "manifest.json", project_cache_manifest_max_bytes) catch return false;
    defer std.heap.page_allocator.free(manifest_bytes);
    var parsed = std.json.parseFromSlice(std.json.Value, std.heap.page_allocator, manifest_bytes, .{}) catch return false;
    defer parsed.deinit();
    if (!jsonIntEquals(jsonGetObject(parsed.value, "version") catch return false, 2)) return false;
    if (!jsonStringEquals(jsonGetObject(parsed.value, "kind") catch return false, kind.dirName())) return false;
    if (!jsonStringEquals(jsonGetObject(parsed.value, "key") catch return false, key_name)) return false;
    if (!(projectCacheDynamicDependenciesWellFormed(jsonGetObject(parsed.value, "dynamic_dependencies") catch return false) catch return false)) return false;
    if (!(cacheEntryArtifactMatchesManifest(entry_dir, jsonGetObject(parsed.value, "artifact") catch return false, "artifact.sa.bc") catch return false)) return false;
    if (!(cacheEntryArtifactMatchesManifest(entry_dir, jsonGetObject(parsed.value, "output") catch return false, "output.bin") catch return false)) return false;
    if (kind == .test_cache) {
        if (!(cacheEntryArtifactMatchesManifest(entry_dir, jsonGetObject(parsed.value, "test_metadata") catch return false, "test-metadata.json") catch return false)) return false;
        if (!cacheEntryTestMetadataValid(entry_dir)) return false;
    }
    return true;
}

fn projectCacheKeyFromHex(text: []const u8) !ProjectCacheKey {
    if (!isHexCacheKey(text)) return error.InvalidCacheKey;
    var key = ProjectCacheKey{ .hex = undefined };
    std.mem.copyForwards(u8, key.hex[0..], text);
    return key;
}

fn cacheEntrySizeBytes(entry_dir: std.fs.Dir) !u64 {
    var total: u64 = 0;
    var iter_dir = entry_dir;
    var iter = iter_dir.iterate();
    while (try iter.next()) |entry| {
        switch (entry.kind) {
            .directory => {
                var child = try iter_dir.openDir(entry.name, .{ .iterate = true });
                defer child.close();
                total += try cacheEntrySizeBytes(child);
            },
            else => {
                const stat = iter_dir.statFile(entry.name) catch continue;
                total += stat.size;
            },
        }
    }
    return total;
}

fn cacheEntrySizeBytesAt(allocator: std.mem.Allocator, project_root: []const u8, kind: BuildCacheKind, key: ProjectCacheKey) u64 {
    const entry_path = projectCacheDir(allocator, project_root, kind, key) catch return 0;
    defer allocator.free(entry_path);
    var entry_dir = std.fs.cwd().openDir(entry_path, .{ .iterate = true }) catch return 0;
    defer entry_dir.close();
    return cacheEntrySizeBytes(entry_dir) catch 0;
}

fn projectCacheEntryMtimeNs(allocator: std.mem.Allocator, project_root: []const u8, kind: BuildCacheKind, key: ProjectCacheKey) ?i128 {
    const stat = projectCacheEntryStat(allocator, project_root, kind, key) orelse return null;
    return stat.mtime;
}

fn projectCacheEntryLastHitNs(allocator: std.mem.Allocator, project_root: []const u8, kind: BuildCacheKind, key: ProjectCacheKey) ?i128 {
    const marker_path = projectCacheHitMarkerPath(allocator, project_root, kind, key) catch return null;
    defer allocator.free(marker_path);
    const stat = std.fs.cwd().statFile(marker_path) catch return null;
    if (stat.kind != .file) return null;
    return stat.mtime;
}

fn projectCacheEntryLastStoreNs(allocator: std.mem.Allocator, project_root: []const u8, kind: BuildCacheKind, key: ProjectCacheKey) ?i128 {
    const marker_path = projectCacheStoreMarkerPath(allocator, project_root, kind, key) catch return null;
    defer allocator.free(marker_path);
    const stat = std.fs.cwd().statFile(marker_path) catch return null;
    if (stat.kind != .file) return null;
    return stat.mtime;
}

fn projectCacheEntryLastStoreResult(allocator: std.mem.Allocator, project_root: []const u8, kind: BuildCacheKind, key: ProjectCacheKey) ?[]const u8 {
    const marker_path = projectCacheStoreEventMarkerPath(allocator, project_root, kind, key) catch return null;
    defer allocator.free(marker_path);
    const bytes = readTextFileAlloc(allocator, marker_path) catch return null;
    defer allocator.free(bytes);
    var parsed = std.json.parseFromSlice(std.json.Value, allocator, bytes, .{}) catch return "unknown";
    defer parsed.deinit();
    const result = jsonString(jsonGetObject(parsed.value, "result") catch return "unknown") catch return "unknown";
    if (std.mem.eql(u8, result, "published")) return "published";
    if (std.mem.eql(u8, result, "failed")) return "failed";
    return "unknown";
}

fn projectCacheEntryLastStoreStage(allocator: std.mem.Allocator, project_root: []const u8, kind: BuildCacheKind, key: ProjectCacheKey) ?[]const u8 {
    const marker_path = projectCacheStoreEventMarkerPath(allocator, project_root, kind, key) catch return null;
    defer allocator.free(marker_path);
    const bytes = readTextFileAlloc(allocator, marker_path) catch return null;
    defer allocator.free(bytes);
    var parsed = std.json.parseFromSlice(std.json.Value, allocator, bytes, .{}) catch return "unknown";
    defer parsed.deinit();
    const stage = jsonString(jsonGetObject(parsed.value, "stage") catch return "unknown") catch return "unknown";
    if (std.mem.eql(u8, stage, "lock")) return "lock";
    if (std.mem.eql(u8, stage, "validate")) return "validate";
    if (std.mem.eql(u8, stage, "prepare")) return "prepare";
    if (std.mem.eql(u8, stage, "cleanup_old")) return "cleanup_old";
    if (std.mem.eql(u8, stage, "stage")) return "stage";
    if (std.mem.eql(u8, stage, "copy_artifact")) return "copy_artifact";
    if (std.mem.eql(u8, stage, "copy_output")) return "copy_output";
    if (std.mem.eql(u8, stage, "test_metadata")) return "test_metadata";
    if (std.mem.eql(u8, stage, "manifest")) return "manifest";
    if (std.mem.eql(u8, stage, "publish")) return "publish";
    return "unknown";
}

fn projectCacheStoreReasonNameFromText(text: []const u8) []const u8 {
    if (std.meta.stringToEnum(ProjectCacheLookupReason, text)) |reason| return reason.jsonName();
    return "unknown";
}

fn projectCacheEntryLastStoreOwnerMissReason(allocator: std.mem.Allocator, project_root: []const u8, kind: BuildCacheKind, key: ProjectCacheKey) ?[]const u8 {
    const marker_path = projectCacheStoreEventMarkerPath(allocator, project_root, kind, key) catch return null;
    defer allocator.free(marker_path);
    const bytes = readTextFileAlloc(allocator, marker_path) catch return null;
    defer allocator.free(bytes);
    var parsed = std.json.parseFromSlice(std.json.Value, allocator, bytes, .{}) catch return "unknown";
    defer parsed.deinit();
    const value = jsonGetObject(parsed.value, "owner_miss_reason") catch return null;
    return switch (value) {
        .null => null,
        .string => |text| projectCacheStoreReasonNameFromText(text),
        else => "unknown",
    };
}

fn projectCacheEntryLastStoreEventNs(allocator: std.mem.Allocator, project_root: []const u8, kind: BuildCacheKind, key: ProjectCacheKey) ?i128 {
    const marker_path = projectCacheStoreEventMarkerPath(allocator, project_root, kind, key) catch return null;
    defer allocator.free(marker_path);
    const bytes = readTextFileAlloc(allocator, marker_path) catch return null;
    defer allocator.free(bytes);
    var parsed = std.json.parseFromSlice(std.json.Value, allocator, bytes, .{}) catch return null;
    defer parsed.deinit();
    const value = jsonGetObject(parsed.value, "event_ns") catch return null;
    return switch (value) {
        .integer => |ns| if (ns > 0) ns else null,
        else => null,
    };
}

fn projectCacheEntryLastStoreWriterPid(allocator: std.mem.Allocator, project_root: []const u8, kind: BuildCacheKind, key: ProjectCacheKey) ?u64 {
    const marker_path = projectCacheStoreEventMarkerPath(allocator, project_root, kind, key) catch return null;
    defer allocator.free(marker_path);
    const bytes = readTextFileAlloc(allocator, marker_path) catch return null;
    defer allocator.free(bytes);
    var parsed = std.json.parseFromSlice(std.json.Value, allocator, bytes, .{}) catch return null;
    defer parsed.deinit();
    const value = jsonGetObject(parsed.value, "writer_pid") catch return null;
    return switch (value) {
        .integer => |pid| if (pid > 0) @as(u64, @intCast(pid)) else null,
        else => null,
    };
}

fn projectCacheEntryLastStoreWriterStartTicks(allocator: std.mem.Allocator, project_root: []const u8, kind: BuildCacheKind, key: ProjectCacheKey) ?u64 {
    const marker_path = projectCacheStoreEventMarkerPath(allocator, project_root, kind, key) catch return null;
    defer allocator.free(marker_path);
    const bytes = readTextFileAlloc(allocator, marker_path) catch return null;
    defer allocator.free(bytes);
    var parsed = std.json.parseFromSlice(std.json.Value, allocator, bytes, .{}) catch return null;
    defer parsed.deinit();
    const value = jsonGetObject(parsed.value, "writer_start_ticks") catch return null;
    return switch (value) {
        .integer => |ticks| if (ticks > 0) @as(u64, @intCast(ticks)) else null,
        else => null,
    };
}

fn projectCacheEntryStoreEventHistoryCount(allocator: std.mem.Allocator, project_root: []const u8, kind: BuildCacheKind, key: ProjectCacheKey) ?u64 {
    const history_dir_path = projectCacheStoreEventHistoryDirPath(allocator, project_root, kind, key) catch return null;
    defer allocator.free(history_dir_path);
    var history_dir = std.fs.cwd().openDir(history_dir_path, .{ .iterate = true }) catch |err| switch (err) {
        error.FileNotFound => return null,
        error.NotDir => return null,
        else => return null,
    };
    defer history_dir.close();

    var count: u64 = 0;
    var iter = history_dir.iterate();
    while (iter.next() catch return null) |entry| {
        if (entry.kind == .file and std.mem.endsWith(u8, entry.name, ".json")) count += 1;
    }
    return count;
}

const ProjectCacheStoreEventHistoryResultCounts = struct {
    published: u64 = 0,
    failed: u64 = 0,
};

fn projectCacheEntryStoreEventHistoryResultCounts(allocator: std.mem.Allocator, project_root: []const u8, kind: BuildCacheKind, key: ProjectCacheKey) ?ProjectCacheStoreEventHistoryResultCounts {
    const history_dir_path = projectCacheStoreEventHistoryDirPath(allocator, project_root, kind, key) catch return null;
    defer allocator.free(history_dir_path);
    var history_dir = std.fs.cwd().openDir(history_dir_path, .{ .iterate = true }) catch |err| switch (err) {
        error.FileNotFound => return null,
        error.NotDir => return null,
        else => return null,
    };
    defer history_dir.close();

    var counts: ProjectCacheStoreEventHistoryResultCounts = .{};
    var iter = history_dir.iterate();
    while (iter.next() catch return null) |entry| {
        if (entry.kind != .file or !std.mem.endsWith(u8, entry.name, ".json")) continue;
        const bytes = history_dir.readFileAlloc(allocator, entry.name, 64 * 1024) catch continue;
        defer allocator.free(bytes);
        var parsed = std.json.parseFromSlice(std.json.Value, allocator, bytes, .{}) catch continue;
        defer parsed.deinit();
        const result = jsonString(jsonGetObject(parsed.value, "result") catch continue) catch continue;
        if (std.mem.eql(u8, result, "published")) {
            counts.published += 1;
        } else if (std.mem.eql(u8, result, "failed")) {
            counts.failed += 1;
        }
    }
    return counts;
}

fn projectCacheEntryWasEvicted(allocator: std.mem.Allocator, project_root: []const u8, kind: BuildCacheKind, key: ProjectCacheKey) bool {
    const marker_path = projectCacheEvictionMarkerPath(allocator, project_root, kind, key) catch return false;
    defer allocator.free(marker_path);
    const stat = std.fs.cwd().statFile(marker_path) catch return false;
    return stat.kind == .file;
}

fn projectCacheEntryStat(allocator: std.mem.Allocator, project_root: []const u8, kind: BuildCacheKind, key: ProjectCacheKey) ?std.fs.File.Stat {
    const entry_path = projectCacheDir(allocator, project_root, kind, key) catch return null;
    defer allocator.free(entry_path);
    const stat = std.fs.cwd().statFile(entry_path) catch return null;
    return stat;
}

fn projectCacheManifestPathForKind(allocator: std.mem.Allocator, project_root: []const u8, kind: BuildCacheKind, key: ProjectCacheKey) ![]u8 {
    return switch (kind) {
        .build_obj_incremental => projectFunctionCacheManifestPath(allocator, project_root, key),
        else => projectCacheManifestPath(allocator, project_root, kind, key),
    };
}

fn projectCacheManifestStatusName(allocator: std.mem.Allocator, project_root: []const u8, kind: BuildCacheKind, key: ProjectCacheKey, reason: ProjectCacheLookupReason) []const u8 {
    const manifest_path = projectCacheManifestPathForKind(allocator, project_root, kind, key) catch return "unknown";
    defer allocator.free(manifest_path);
    const stat = std.fs.cwd().statFile(manifest_path) catch |err| switch (err) {
        error.FileNotFound => return "missing",
        else => return "unknown",
    };
    if (!cachePathIsRegularFile(manifest_path)) return "invalid";
    if (stat.kind != .file) return "invalid";
    if (reason == .manifest_invalid) return "invalid";
    return "valid";
}

fn projectCacheEntryLookupReasonAt(
    allocator: std.mem.Allocator,
    project_root: []const u8,
    kind: BuildCacheKind,
    key: ProjectCacheKey,
) ProjectCacheLookupReason {
    if (kind == .build_obj_incremental) {
        const entry_path = projectCacheDir(allocator, project_root, kind, key) catch return .unknown;
        defer allocator.free(entry_path);
        var entry_dir = std.fs.cwd().openDir(entry_path, .{}) catch |err| switch (err) {
            error.FileNotFound => return if (projectCacheEntryWasEvicted(allocator, project_root, kind, key)) .evicted else .absent,
            else => return .manifest_invalid,
        };
        defer entry_dir.close();
        if (!cacheEntryComplete(kind, entry_dir)) return .incomplete;
        return if (cacheEntryManifestValid(kind, key.slice(), entry_dir)) .hit else .manifest_invalid;
    }

    const entry_path = projectCacheDir(allocator, project_root, kind, key) catch return .unknown;
    defer allocator.free(entry_path);
    _ = std.fs.cwd().statFile(entry_path) catch |err| switch (err) {
        error.FileNotFound => {
            if (projectCacheEntryWasEvicted(allocator, project_root, kind, key)) return .evicted;
        },
        else => {},
    };

    {
        var entry_dir = std.fs.cwd().openDir(entry_path, .{}) catch null;
        if (entry_dir) |*dir| {
            defer dir.close();
            if (!cacheEntryComplete(kind, dir.*)) return .incomplete;
        }
    }

    const cached_artifact = projectCacheArtifactPath(allocator, project_root, kind, key, "artifact.sa.bc") catch return .unknown;
    defer allocator.free(cached_artifact);
    const cached_output = projectCacheArtifactPath(allocator, project_root, kind, key, "output.bin") catch return .unknown;
    defer allocator.free(cached_output);
    return projectCacheManifestLookupReason(allocator, project_root, kind, key, cached_artifact, cached_output);
}

fn projectCacheDynamicDependenciesFirstDifference(allocator: std.mem.Allocator, value: std.json.Value) ?[]const u8 {
    const dependencies = switch (value) {
        .array => |items| items.items,
        else => return "dynamic_dependencies",
    };
    if (dependencies.len > 4096) return "dynamic_dependencies";

    for (dependencies) |dependency| {
        const object = switch (dependency) {
            .object => |object| object,
            else => return "dynamic_dependencies",
        };
        const kind = jsonString(object.get("kind") orelse return "dynamic_dependencies.kind") catch return "dynamic_dependencies.kind";
        if (std.mem.eql(u8, kind, "environment")) {
            const key = jsonString(object.get("key") orelse return "dynamic_dependencies.key") catch return "dynamic_dependencies.key";
            if (key.len == 0 or key.len > 4096) return "dynamic_dependencies.key";
            const expected_present = jsonBool(object.get("present") orelse return "dynamic_dependencies.present") catch return "dynamic_dependencies.present";
            const current_value: ?[]u8 = std.process.getEnvVarOwned(allocator, key) catch |err| switch (err) {
                error.EnvironmentVariableNotFound => null,
                else => return "dynamic_dependencies.present",
            };
            defer if (current_value) |bytes| allocator.free(bytes);
            if (expected_present != (current_value != null)) return "dynamic_dependencies.present";
            if (current_value) |bytes| {
                const sha_value = object.get("sha256") orelse return "dynamic_dependencies.sha256";
                if (!(jsonSha256(sha_value) catch return "dynamic_dependencies.sha256")) return "dynamic_dependencies.sha256";
                var digest: [32]u8 = undefined;
                std.crypto.hash.sha2.Sha256.hash(bytes, &digest, .{});
                const digest_hex = std.fmt.bytesToHex(digest, .lower);
                if (!jsonStringEquals(sha_value, digest_hex[0..])) return "dynamic_dependencies.sha256";
            } else if (object.get("sha256") != null) {
                return "dynamic_dependencies.sha256";
            }
            continue;
        }
        if (std.mem.eql(u8, kind, "file")) {
            const path = jsonString(object.get("path") orelse return "dynamic_dependencies.path") catch return "dynamic_dependencies.path";
            if (path.len == 0 or path.len > std.fs.max_path_bytes or !std.fs.path.isAbsolute(path)) return "dynamic_dependencies.path";
            const stat = std.fs.cwd().statFile(path) catch return "dynamic_dependencies.path";
            if (stat.kind != .file) return "dynamic_dependencies.path";
            if (!jsonIntEquals(object.get("size") orelse return "dynamic_dependencies.size", stat.size)) return "dynamic_dependencies.size";
            const sha_value = object.get("sha256") orelse return "dynamic_dependencies.sha256";
            if (!(jsonSha256(sha_value) catch return "dynamic_dependencies.sha256")) return "dynamic_dependencies.sha256";
            const digest_hex = hashFileHex(allocator, path) catch return "dynamic_dependencies.sha256";
            if (!jsonStringEquals(sha_value, digest_hex[0..])) return "dynamic_dependencies.sha256";
            continue;
        }
        return "dynamic_dependencies.kind";
    }
    return null;
}

fn projectCacheArtifactFirstDifference(
    allocator: std.mem.Allocator,
    artifact_value: std.json.Value,
    path: []const u8,
    file_field: []const u8,
    size_field: []const u8,
    sha_field: []const u8,
) ?[]const u8 {
    if (!cachePathIsRegularFile(path)) return file_field;
    const stat = std.fs.cwd().statFile(path) catch return file_field;
    if (stat.kind != .file or stat.size == 0) return file_field;
    if (!jsonIntEquals(jsonGetObject(artifact_value, "size") catch return size_field, stat.size)) return size_field;
    const sha_value = jsonGetObject(artifact_value, "sha256") catch return sha_field;
    if (!(jsonSha256(sha_value) catch return sha_field)) return sha_field;
    const hash_hex = hashFileHex(allocator, path) catch return sha_field;
    if (!jsonStringEquals(sha_value, hash_hex[0..])) return sha_field;
    return null;
}

fn projectCacheManifestFirstDifference(
    allocator: std.mem.Allocator,
    project_root: []const u8,
    kind: BuildCacheKind,
    key: ProjectCacheKey,
) ?[]const u8 {
    if (kind == .build_obj_incremental) return null;

    const manifest_path = projectCacheManifestPath(allocator, project_root, kind, key) catch return "manifest.path";
    defer allocator.free(manifest_path);
    if (!cachePathIsRegularFile(manifest_path)) return "manifest";
    const manifest_bytes = readTextFileAlloc(allocator, manifest_path) catch return "manifest";
    defer allocator.free(manifest_bytes);
    var parsed = std.json.parseFromSlice(std.json.Value, allocator, manifest_bytes, .{}) catch return "manifest.json";
    defer parsed.deinit();

    if (!jsonIntEquals(jsonGetObject(parsed.value, "version") catch return "manifest.version", 2)) return "manifest.version";
    if (!jsonStringEquals(jsonGetObject(parsed.value, "kind") catch return "manifest.kind", kind.dirName())) return "manifest.kind";
    if (!jsonStringEquals(jsonGetObject(parsed.value, "key") catch return "manifest.key", key.slice())) return "manifest.key";
    const dependencies = jsonGetObject(parsed.value, "dynamic_dependencies") catch return "dynamic_dependencies";
    if (projectCacheDynamicDependenciesFirstDifference(allocator, dependencies)) |field| return field;

    const cached_artifact = projectCacheArtifactPath(allocator, project_root, kind, key, "artifact.sa.bc") catch return "artifact.file";
    defer allocator.free(cached_artifact);
    const cached_output = projectCacheArtifactPath(allocator, project_root, kind, key, "output.bin") catch return "output.file";
    defer allocator.free(cached_output);
    if (projectCacheArtifactFirstDifference(allocator, jsonGetObject(parsed.value, "artifact") catch return "artifact", cached_artifact, "artifact.file", "artifact.size", "artifact.sha256")) |field| return field;
    if (projectCacheArtifactFirstDifference(allocator, jsonGetObject(parsed.value, "output") catch return "output", cached_output, "output.file", "output.size", "output.sha256")) |field| return field;
    if (kind == .test_cache) {
        const metadata_path = projectCacheTestMetadataPath(allocator, project_root, key) catch return "test_metadata.file";
        defer allocator.free(metadata_path);
        if (projectCacheArtifactFirstDifference(allocator, jsonGetObject(parsed.value, "test_metadata") catch return "test_metadata", metadata_path, "test_metadata.file", "test_metadata.size", "test_metadata.sha256")) |field| return field;
    }
    return null;
}

fn projectCacheKeyInputFieldFromName(name: []const u8) ?ProjectCacheKeyInputField {
    for (project_cache_key_input_fields) |field| {
        if (std.mem.eql(u8, name, field.jsonName())) return field;
    }
    return null;
}

fn projectCacheKeyInputTraceValid(value: std.json.Value, kind: BuildCacheKind, key: ProjectCacheKey) bool {
    if (!jsonIntEquals(jsonGetObject(value, "version") catch return false, 1)) return false;
    if (!jsonStringEquals(jsonGetObject(value, "kind") catch return false, kind.dirName())) return false;
    if (!jsonStringEquals(jsonGetObject(value, "key_prefix") catch return false, key.slice()[0..12])) return false;
    const fields = switch (jsonGetObject(value, "fields") catch return false) {
        .array => |items| items.items,
        else => return false,
    };
    if (fields.len > project_cache_key_input_fields.len) return false;
    var seen = [_]bool{false} ** project_cache_key_input_fields.len;
    for (fields) |item| {
        const name = jsonString(jsonGetObject(item, "name") catch return false) catch return false;
        const field = projectCacheKeyInputFieldFromName(name) orelse return false;
        const idx = @intFromEnum(field);
        if (seen[idx]) return false;
        seen[idx] = true;
        const digest_value = jsonGetObject(item, "sha256") catch return false;
        if (!(jsonSha256(digest_value) catch return false)) return false;
    }
    return true;
}

fn projectCacheKeyInputFieldDigest(value: std.json.Value, field: ProjectCacheKeyInputField) ?[]const u8 {
    const fields = switch (jsonGetObject(value, "fields") catch return null) {
        .array => |items| items.items,
        else => return null,
    };
    for (fields) |item| {
        const name_value = jsonGetObject(item, "name") catch return null;
        if (!jsonStringEquals(name_value, field.jsonName())) continue;
        const digest_value = jsonGetObject(item, "sha256") catch return null;
        return jsonString(digest_value) catch return null;
    }
    return null;
}

fn projectCacheKeyInputFirstDifference(
    allocator: std.mem.Allocator,
    project_root: []const u8,
    kind: BuildCacheKind,
    requested_key: ProjectCacheKey,
    candidate_key: ProjectCacheKey,
) ?[]const u8 {
    const requested_path = projectCacheKeyInputMarkerPath(allocator, project_root, kind, requested_key) catch return null;
    defer allocator.free(requested_path);
    const candidate_path = projectCacheKeyInputMarkerPath(allocator, project_root, kind, candidate_key) catch return null;
    defer allocator.free(candidate_path);
    const requested_bytes = readTextFileAlloc(allocator, requested_path) catch return null;
    defer allocator.free(requested_bytes);
    const candidate_bytes = readTextFileAlloc(allocator, candidate_path) catch return null;
    defer allocator.free(candidate_bytes);

    var requested = std.json.parseFromSlice(std.json.Value, allocator, requested_bytes, .{}) catch return null;
    defer requested.deinit();
    var candidate = std.json.parseFromSlice(std.json.Value, allocator, candidate_bytes, .{}) catch return null;
    defer candidate.deinit();
    if (!projectCacheKeyInputTraceValid(requested.value, kind, requested_key)) return null;
    if (!projectCacheKeyInputTraceValid(candidate.value, kind, candidate_key)) return null;

    for (project_cache_key_input_fields) |field| {
        const requested_digest = projectCacheKeyInputFieldDigest(requested.value, field);
        const candidate_digest = projectCacheKeyInputFieldDigest(candidate.value, field);
        if (requested_digest == null and candidate_digest == null) continue;
        if (requested_digest == null or candidate_digest == null or !std.mem.eql(u8, requested_digest.?, candidate_digest.?)) {
            return switch (field) {
                .schema => "key.schema",
                .compiler => "key.compiler",
                .backend => "key.backend",
                .toolchain => "key.toolchain",
                .host_target => "key.host_target",
                .project => "key.project",
                .command => "key.command",
                .wasm_target => "key.wasm_target",
                .semantic_file_inputs => "key.semantic_file_inputs",
                .project_manifests => "key.project_manifests",
                .source_tree => "key.source_tree",
            };
        }
    }
    return null;
}

fn projectCacheCandidateKeyFirstDifference(
    allocator: std.mem.Allocator,
    project_root: []const u8,
    kind: BuildCacheKind,
    key: ProjectCacheKey,
) ?[]const u8 {
    const kind_dir_path = pathJoinAlloc(allocator, &.{ project_root, ".sa_cache", kind.dirName() }) catch return null;
    defer allocator.free(kind_dir_path);
    var kind_dir = std.fs.cwd().openDir(kind_dir_path, .{ .iterate = true }) catch return null;
    defer kind_dir.close();

    var iter = kind_dir.iterate();
    while (iter.next() catch return null) |entry| {
        if (entry.kind != .directory or !isHexCacheKey(entry.name)) continue;
        if (std.mem.eql(u8, entry.name, key.slice())) continue;
        if (std.mem.startsWith(u8, entry.name, key.slice()[0..12])) {
            const candidate_key = projectCacheKeyFromHex(entry.name) catch return "key.digest";
            return projectCacheKeyInputFirstDifference(allocator, project_root, kind, key, candidate_key) orelse "key.digest";
        }
    }
    return null;
}

const CacheStatusSummary = struct {
    entries: usize = 0,
    bytes: u64 = 0,
};

fn writeCacheStatusEntryJson(
    writer: anytype,
    kind: BuildCacheKind,
    key: ProjectCacheKey,
    reason: ProjectCacheLookupReason,
    manifest_status: []const u8,
    bytes: u64,
    mtime_ns: ?i128,
    last_hit_ns: ?i128,
    last_store_ns: ?i128,
    last_store_result: ?[]const u8,
    last_store_stage: ?[]const u8,
    last_store_owner_miss_reason: ?[]const u8,
    last_store_event_ns: ?i128,
    last_store_writer_pid: ?u64,
    last_store_writer_start_ticks: ?u64,
    last_store_event_count: ?u64,
    last_store_published_event_count: ?u64,
    last_store_failed_event_count: ?u64,
    first_difference: ?[]const u8,
) !void {
    try writer.writeAll("{\"kind\":");
    try writeJsonString(writer, kind.dirName());
    try writer.writeAll(",\"key_prefix\":");
    try writeJsonString(writer, key.slice()[0..12]);
    try writer.writeAll(",\"reason\":");
    try writeJsonString(writer, reason.jsonName());
    try writer.writeAll(",\"manifest\":");
    try writeJsonString(writer, manifest_status);
    try writer.writeAll(",\"bytes\":");
    try writer.print("{d}", .{bytes});
    try writer.writeAll(",\"last_write_ns\":");
    if (mtime_ns) |ns| {
        try writer.print("{d}", .{ns});
    } else {
        try writer.writeAll("null");
    }
    try writer.writeAll(",\"last_hit_ns\":");
    if (last_hit_ns) |ns| {
        try writer.print("{d}", .{ns});
    } else {
        try writer.writeAll("null");
    }
    try writer.writeAll(",\"last_store_ns\":");
    if (last_store_ns) |ns| {
        try writer.print("{d}", .{ns});
    } else {
        try writer.writeAll("null");
    }
    try writer.writeAll(",\"last_store_result\":");
    if (last_store_result) |result| {
        try writeJsonString(writer, result);
    } else {
        try writer.writeAll("null");
    }
    try writer.writeAll(",\"last_store_stage\":");
    if (last_store_stage) |stage| {
        try writeJsonString(writer, stage);
    } else {
        try writer.writeAll("null");
    }
    try writer.writeAll(",\"last_store_owner_miss_reason\":");
    if (last_store_owner_miss_reason) |owner_miss_reason| {
        try writeJsonString(writer, owner_miss_reason);
    } else {
        try writer.writeAll("null");
    }
    try writer.writeAll(",\"last_store_event_ns\":");
    if (last_store_event_ns) |ns| {
        try writer.print("{d}", .{ns});
    } else {
        try writer.writeAll("null");
    }
    try writer.writeAll(",\"last_store_writer_pid\":");
    if (last_store_writer_pid) |pid| {
        try writer.print("{d}", .{pid});
    } else {
        try writer.writeAll("null");
    }
    try writer.writeAll(",\"last_store_writer_start_ticks\":");
    if (last_store_writer_start_ticks) |ticks| {
        try writer.print("{d}", .{ticks});
    } else {
        try writer.writeAll("null");
    }
    try writer.writeAll(",\"last_store_event_count\":");
    if (last_store_event_count) |count| {
        try writer.print("{d}", .{count});
    } else {
        try writer.writeAll("null");
    }
    try writer.writeAll(",\"last_store_published_event_count\":");
    if (last_store_published_event_count) |count| {
        try writer.print("{d}", .{count});
    } else {
        try writer.writeAll("null");
    }
    try writer.writeAll(",\"last_store_failed_event_count\":");
    if (last_store_failed_event_count) |count| {
        try writer.print("{d}", .{count});
    } else {
        try writer.writeAll("null");
    }
    try writer.writeAll(",\"first_difference\":");
    if (first_difference) |field| {
        try writeJsonString(writer, field);
    } else {
        try writer.writeAll("null");
    }
    try writer.writeByte('}');
}

fn writeCacheStatusEntryText(
    writer: anytype,
    prefix: []const u8,
    kind: BuildCacheKind,
    key: ProjectCacheKey,
    reason: ProjectCacheLookupReason,
    manifest_status: []const u8,
    bytes: u64,
    mtime_ns: ?i128,
    last_hit_ns: ?i128,
    last_store_ns: ?i128,
    last_store_result: ?[]const u8,
    last_store_stage: ?[]const u8,
    last_store_owner_miss_reason: ?[]const u8,
    last_store_event_ns: ?i128,
    last_store_writer_pid: ?u64,
    last_store_writer_start_ticks: ?u64,
    last_store_event_count: ?u64,
    last_store_published_event_count: ?u64,
    last_store_failed_event_count: ?u64,
    first_difference: ?[]const u8,
) !void {
    try writer.print("{s}: kind={s} key={s} reason={s} manifest={s} bytes={d}", .{ prefix, kind.dirName(), key.slice()[0..12], reason.jsonName(), manifest_status, bytes });
    if (mtime_ns) |ns| {
        try writer.print(" last_write_ns={d}", .{ns});
    } else {
        try writer.writeAll(" last_write_ns=null");
    }
    if (last_hit_ns) |ns| {
        try writer.print(" last_hit_ns={d}", .{ns});
    } else {
        try writer.writeAll(" last_hit_ns=null");
    }
    if (last_store_ns) |ns| {
        try writer.print(" last_store_ns={d}", .{ns});
    } else {
        try writer.writeAll(" last_store_ns=null");
    }
    if (last_store_result) |result| {
        try writer.print(" last_store_result={s}", .{result});
    } else {
        try writer.writeAll(" last_store_result=null");
    }
    if (last_store_stage) |stage| {
        try writer.print(" last_store_stage={s}", .{stage});
    } else {
        try writer.writeAll(" last_store_stage=null");
    }
    if (last_store_owner_miss_reason) |owner_miss_reason| {
        try writer.print(" last_store_owner_miss_reason={s}", .{owner_miss_reason});
    } else {
        try writer.writeAll(" last_store_owner_miss_reason=null");
    }
    if (last_store_event_ns) |ns| {
        try writer.print(" last_store_event_ns={d}", .{ns});
    } else {
        try writer.writeAll(" last_store_event_ns=null");
    }
    if (last_store_writer_pid) |pid| {
        try writer.print(" last_store_writer_pid={d}", .{pid});
    } else {
        try writer.writeAll(" last_store_writer_pid=null");
    }
    if (last_store_writer_start_ticks) |ticks| {
        try writer.print(" last_store_writer_start_ticks={d}", .{ticks});
    } else {
        try writer.writeAll(" last_store_writer_start_ticks=null");
    }
    if (last_store_event_count) |count| {
        try writer.print(" last_store_event_count={d}", .{count});
    } else {
        try writer.writeAll(" last_store_event_count=null");
    }
    if (last_store_published_event_count) |count| {
        try writer.print(" last_store_published_event_count={d}", .{count});
    } else {
        try writer.writeAll(" last_store_published_event_count=null");
    }
    if (last_store_failed_event_count) |count| {
        try writer.print(" last_store_failed_event_count={d}", .{count});
    } else {
        try writer.writeAll(" last_store_failed_event_count=null");
    }
    if (first_difference) |field| {
        try writer.print(" first_difference={s}", .{field});
    } else {
        try writer.writeAll(" first_difference=null");
    }
    try writer.writeByte('\n');
}

fn writeCacheStatusEntry(
    allocator: std.mem.Allocator,
    project_root: []const u8,
    kind: BuildCacheKind,
    key: ProjectCacheKey,
    max_age_days: u64,
    json: bool,
    prefix: []const u8,
    writer: anytype,
    json_first: *bool,
    summary: *CacheStatusSummary,
) !void {
    var reason = projectCacheEntryLookupReasonAt(allocator, project_root, kind, key);
    const stat = projectCacheEntryStat(allocator, project_root, kind, key);
    if (reason == .hit and stat != null and cacheEntryExpired(stat.?, max_age_days)) {
        reason = .expired;
    }
    const manifest_status = projectCacheManifestStatusName(allocator, project_root, kind, key, reason);
    const bytes = cacheEntrySizeBytesAt(allocator, project_root, kind, key);
    const mtime_ns = if (stat) |entry_stat| entry_stat.mtime else null;
    const last_hit_ns = if (stat != null) projectCacheEntryLastHitNs(allocator, project_root, kind, key) else null;
    const last_store_ns = if (stat != null) projectCacheEntryLastStoreNs(allocator, project_root, kind, key) else null;
    const last_store_result = projectCacheEntryLastStoreResult(allocator, project_root, kind, key);
    const last_store_stage = projectCacheEntryLastStoreStage(allocator, project_root, kind, key);
    const last_store_owner_miss_reason = projectCacheEntryLastStoreOwnerMissReason(allocator, project_root, kind, key);
    const last_store_event_ns = projectCacheEntryLastStoreEventNs(allocator, project_root, kind, key);
    const last_store_writer_pid = projectCacheEntryLastStoreWriterPid(allocator, project_root, kind, key);
    const last_store_writer_start_ticks = projectCacheEntryLastStoreWriterStartTicks(allocator, project_root, kind, key);
    const last_store_event_count = projectCacheEntryStoreEventHistoryCount(allocator, project_root, kind, key);
    const last_store_result_counts = projectCacheEntryStoreEventHistoryResultCounts(allocator, project_root, kind, key);
    const last_store_published_event_count = if (last_store_result_counts) |counts| counts.published else null;
    const last_store_failed_event_count = if (last_store_result_counts) |counts| counts.failed else null;
    const first_difference = if (reason == .hit or reason == .expired)
        null
    else if (stat == null)
        projectCacheCandidateKeyFirstDifference(allocator, project_root, kind, key)
    else
        projectCacheManifestFirstDifference(allocator, project_root, kind, key);
    summary.entries += 1;
    summary.bytes += bytes;
    if (json) {
        if (!json_first.*) try writer.writeByte(',');
        json_first.* = false;
        try writeCacheStatusEntryJson(writer, kind, key, reason, manifest_status, bytes, mtime_ns, last_hit_ns, last_store_ns, last_store_result, last_store_stage, last_store_owner_miss_reason, last_store_event_ns, last_store_writer_pid, last_store_writer_start_ticks, last_store_event_count, last_store_published_event_count, last_store_failed_event_count, first_difference);
    } else {
        try writeCacheStatusEntryText(writer, prefix, kind, key, reason, manifest_status, bytes, mtime_ns, last_hit_ns, last_store_ns, last_store_result, last_store_stage, last_store_owner_miss_reason, last_store_event_ns, last_store_writer_pid, last_store_writer_start_ticks, last_store_event_count, last_store_published_event_count, last_store_failed_event_count, first_difference);
    }
}

fn writeCacheStatusKind(
    allocator: std.mem.Allocator,
    project_root: []const u8,
    kind: BuildCacheKind,
    max_age_days: u64,
    json: bool,
    writer: anytype,
    json_first: *bool,
    summary: *CacheStatusSummary,
) !void {
    const kind_dir_path = try pathJoinAlloc(allocator, &.{ project_root, ".sa_cache", kind.dirName() });
    defer allocator.free(kind_dir_path);
    var kind_dir = std.fs.cwd().openDir(kind_dir_path, .{ .iterate = true }) catch |err| switch (err) {
        error.FileNotFound => return,
        error.NotDir => return,
        else => return err,
    };
    defer kind_dir.close();

    var iter = kind_dir.iterate();
    while (try iter.next()) |entry| {
        if (std.mem.eql(u8, entry.name, ".locks")) continue;
        if (entry.kind != .directory or !isHexCacheKey(entry.name)) continue;
        const key = try projectCacheKeyFromHex(entry.name);
        try writeCacheStatusEntry(allocator, project_root, kind, key, max_age_days, json, "cache entry", writer, json_first, summary);
    }
}

fn cleanCacheKindDir(
    allocator: std.mem.Allocator,
    project_root: []const u8,
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
    if (!options.dry_run) try kind_dir.makePath(".locks");

    var iter = kind_dir.iterate();
    while (try iter.next()) |entry| {
        if (std.mem.eql(u8, entry.name, ".locks")) continue;
        stats.scanned += 1;
        const staging_key = cacheStagingKey(entry.name);
        const lock_key: ?[]const u8 = if (isHexCacheKey(entry.name)) entry.name else staging_key;
        var entry_lock: ?ProjectCacheEntryLock = if (!options.dry_run and lock_key != null)
            try tryAcquireProjectCacheEntryLockInKindDir(kind_dir, lock_key.?)
        else
            null;
        defer if (entry_lock) |*lock| lock.deinit();
        if (!options.dry_run and lock_key != null and entry_lock == null) {
            stats.kept += 1;
            continue;
        }

        var remove = entry.kind != .directory or !isHexCacheKey(entry.name);
        if (staging_key != null) {
            remove = true;
        } else if (!remove) {
            const stat: ?std.fs.File.Stat = kind_dir.statFile(entry.name) catch null;
            if (kind_dir.openDir(entry.name, .{})) |entry_dir_value| {
                var entry_dir = entry_dir_value;
                remove = !cacheEntryComplete(kind, entry_dir) or
                    !cacheEntryManifestValid(kind, entry.name, entry_dir) or
                    (if (stat) |s| cacheEntryExpired(s, options.max_age_days) else true);
                entry_dir.close();
            } else |_| {
                remove = true;
            }
        }

        if (remove) {
            stats.removed += 1;
            if (!options.dry_run) {
                const evicted_key = if (entry.kind == .directory and isHexCacheKey(entry.name))
                    try projectCacheKeyFromHex(entry.name)
                else
                    null;
                if (entry.kind == .directory) {
                    try kind_dir.deleteTree(entry.name);
                } else {
                    try kind_dir.deleteFile(entry.name);
                }
                if (evicted_key) |key| {
                    try projectCacheTouchEvictionTelemetry(allocator, project_root, kind, key);
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
    try cleanCacheKindDir(allocator, project_root, root_dir, .build_exe, options, &stats);
    try cleanCacheKindDir(allocator, project_root, root_dir, .build_obj, options, &stats);
    try cleanCacheKindDir(allocator, project_root, root_dir, .build_wasm, options, &stats);
    try cleanCacheKindDir(allocator, project_root, root_dir, .build_obj_incremental, options, &stats);
    try cleanCacheKindDir(allocator, project_root, root_dir, .test_cache, options, &stats);
    return stats;
}

const CacheStatusOptions = struct {
    kind: ?BuildCacheKind = null,
    key: ?ProjectCacheKey = null,
    max_age_days: u64 = 0,
    json: bool = false,
};

fn parseCacheStatusOptions(args: []const []const u8, require_key: bool) !CacheStatusOptions {
    var options: CacheStatusOptions = .{};
    var positional: usize = 0;
    var i: usize = 0;
    while (i < args.len) : (i += 1) {
        if (std.mem.eql(u8, args[i], "--json")) {
            options.json = true;
            continue;
        }
        if (std.mem.eql(u8, args[i], "--kind")) {
            if (i + 1 >= args.len) return error.MissingArgument;
            options.kind = parseBuildCacheKindName(args[i + 1]) orelse return error.InvalidCacheKind;
            i += 1;
            continue;
        }
        if (std.mem.startsWith(u8, args[i], "--kind=")) {
            options.kind = parseBuildCacheKindName(args[i]["--kind=".len..]) orelse return error.InvalidCacheKind;
            continue;
        }
        if (std.mem.eql(u8, args[i], "--key")) {
            if (i + 1 >= args.len) return error.MissingArgument;
            options.key = try projectCacheKeyFromHex(args[i + 1]);
            i += 1;
            continue;
        }
        if (std.mem.startsWith(u8, args[i], "--key=")) {
            options.key = try projectCacheKeyFromHex(args[i]["--key=".len..]);
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
        if (args[i].len != 0 and args[i][0] != '-') {
            if (require_key and positional == 0) {
                options.kind = parseBuildCacheKindName(args[i]) orelse return error.InvalidCacheKind;
                positional += 1;
                continue;
            }
            if (require_key and positional == 1) {
                options.key = try projectCacheKeyFromHex(args[i]);
                positional += 1;
                continue;
            }
        }
        return error.UnexpectedArgument;
    }
    if (require_key) {
        if (options.kind == null) return error.MissingCacheKind;
        if (options.key == null) return error.MissingCacheKey;
    }
    return options;
}

fn executeCacheStatusCommand(allocator: std.mem.Allocator, args: []const []const u8, stdout: anytype, json_mode: bool) !u8 {
    var options = try parseCacheStatusOptions(args, false);
    if (json_mode) options.json = true;
    const project_root = try projectRootDir(allocator);
    defer allocator.free(project_root);

    var summary: CacheStatusSummary = .{};
    var json_first = true;
    if (options.json) {
        try stdout.writeAll("{\"status\":\"ok\",\"entries\":[");
    } else {
        try stdout.writeAll("cache status: root=.sa_cache\n");
    }

    if (options.kind) |kind| {
        try writeCacheStatusKind(allocator, project_root, kind, options.max_age_days, options.json, stdout, &json_first, &summary);
    } else {
        for (build_cache_kinds) |kind| {
            try writeCacheStatusKind(allocator, project_root, kind, options.max_age_days, options.json, stdout, &json_first, &summary);
        }
    }

    if (options.json) {
        try stdout.writeAll("],\"summary\":{\"entries\":");
        try stdout.print("{d}", .{summary.entries});
        try stdout.writeAll(",\"bytes\":");
        try stdout.print("{d}", .{summary.bytes});
        try stdout.writeAll("}}\n");
    } else {
        try stdout.print("cache status summary: entries={d} bytes={d}\n", .{ summary.entries, summary.bytes });
    }
    return 0;
}

fn executeCacheWhyCommand(allocator: std.mem.Allocator, args: []const []const u8, stdout: anytype, json_mode: bool) !u8 {
    var options = try parseCacheStatusOptions(args, true);
    if (json_mode) options.json = true;
    const project_root = try projectRootDir(allocator);
    defer allocator.free(project_root);
    var summary: CacheStatusSummary = .{};
    var json_first = true;
    if (options.json) {
        try stdout.writeAll("{\"status\":\"ok\",\"entries\":[");
    }
    try writeCacheStatusEntry(allocator, project_root, options.kind.?, options.key.?, options.max_age_days, options.json, "cache why", stdout, &json_first, &summary);
    if (options.json) {
        try stdout.writeAll("],\"summary\":{\"entries\":1,\"bytes\":");
        try stdout.print("{d}", .{summary.bytes});
        try stdout.writeAll("}}\n");
    }
    return 0;
}

fn executeCacheCommand(allocator: std.mem.Allocator, args: []const []const u8, stdout: anytype, json_mode: bool) !u8 {
    if (args.len == 0 or isHelpFlag(args[0])) {
        try printCacheHelp(stdout, args);
        return 0;
    }
    if (std.mem.eql(u8, args[0], "status")) {
        if (args.len > 1 and isHelpFlag(args[1])) {
            try printCacheHelp(stdout, args);
            return 0;
        }
        return try executeCacheStatusCommand(allocator, args[1..], stdout, json_mode);
    }
    if (std.mem.eql(u8, args[0], "why")) {
        if (args.len > 1 and isHelpFlag(args[1])) {
            try printCacheHelp(stdout, args);
            return 0;
        }
        return try executeCacheWhyCommand(allocator, args[1..], stdout, json_mode);
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

const IncrementalFunctionObjectMetadata = struct {
    size: u64,
    sha256: [64]u8,
};

const IncrementalFunctionManifestEntry = struct {
    relative_path: []const u8,
    size: u64,
    sha256: []const u8,
    valid: bool = false,
};

const IncrementalObjectManifest = struct {
    bytes: []u8,
    parsed: std.json.Parsed(std.json.Value),
    functions: std.StringHashMap(IncrementalFunctionManifestEntry),
    unexpected_entries: bool = false,

    fn deinit(self: *IncrementalObjectManifest, allocator: std.mem.Allocator) void {
        self.functions.deinit();
        self.parsed.deinit();
        allocator.free(self.bytes);
        self.* = undefined;
    }

    fn objectMetadata(self: *const IncrementalObjectManifest, function_key: []const u8) ?IncrementalFunctionObjectMetadata {
        const entry = self.functions.get(function_key) orelse return null;
        if (!entry.valid) return null;
        var sha256: [64]u8 = undefined;
        @memcpy(sha256[0..], entry.sha256);
        return .{ .size = entry.size, .sha256 = sha256 };
    }

    fn complete(self: *const IncrementalObjectManifest) bool {
        if (self.unexpected_entries or self.functions.count() == 0) return false;
        var iter = self.functions.valueIterator();
        while (iter.next()) |entry| {
            if (!entry.valid) return false;
        }
        return true;
    }
};

fn jsonPositiveU64(value: std.json.Value) !u64 {
    return switch (value) {
        .integer => |integer| if (integer > 0) @intCast(integer) else error.InvalidCacheManifest,
        else => error.InvalidCacheManifest,
    };
}

fn parseOwnedIncrementalObjectManifest(
    allocator: std.mem.Allocator,
    manifest_bytes: []u8,
    expected_key: []const u8,
    expected_source: ?[]const u8,
) !IncrementalObjectManifest {
    errdefer allocator.free(manifest_bytes);
    var parsed = try std.json.parseFromSlice(std.json.Value, allocator, manifest_bytes, .{});
    errdefer parsed.deinit();
    if (!jsonIntEquals(try jsonGetObject(parsed.value, "version"), 2)) return error.InvalidCacheManifest;
    if (!jsonStringEquals(try jsonGetObject(parsed.value, "kind"), BuildCacheKind.build_obj_incremental.dirName())) return error.InvalidCacheManifest;
    if (!jsonStringEquals(try jsonGetObject(parsed.value, "key"), expected_key)) return error.InvalidCacheManifest;
    const source = try jsonString(try jsonGetObject(parsed.value, "source"));
    if (expected_source) |expected| {
        if (!std.mem.eql(u8, source, expected)) return error.InvalidCacheManifest;
    }
    const functions_value = try jsonGetObject(parsed.value, "functions");
    const function_items = switch (functions_value) {
        .array => |array| array.items,
        else => return error.InvalidCacheManifest,
    };
    if (function_items.len == 0 or function_items.len > 65_536) return error.InvalidCacheManifest;

    var functions = std.StringHashMap(IncrementalFunctionManifestEntry).init(allocator);
    errdefer functions.deinit();
    for (function_items) |item| {
        const function_key = try jsonString(try jsonGetObject(item, "key"));
        if (!isHexCacheKey(function_key) or functions.contains(function_key)) return error.InvalidCacheManifest;
        const relative_path = try jsonString(try jsonGetObject(item, "path"));
        var expected_path_buf: [96]u8 = undefined;
        const expected_path = try std.fmt.bufPrint(&expected_path_buf, "functions/{s}.o", .{function_key});
        if (!std.mem.eql(u8, relative_path, expected_path)) return error.InvalidCacheManifest;
        const size = try jsonPositiveU64(try jsonGetObject(item, "size"));
        const sha256_value = try jsonGetObject(item, "sha256");
        const sha256 = try jsonString(sha256_value);
        if (!try jsonSha256(sha256_value)) return error.InvalidCacheManifest;
        try functions.put(function_key, .{
            .relative_path = relative_path,
            .size = size,
            .sha256 = sha256,
        });
    }

    return .{
        .bytes = manifest_bytes,
        .parsed = parsed,
        .functions = functions,
    };
}

fn markIncrementalManifestFile(manifest_value: *IncrementalObjectManifest, functions_dir: std.fs.Dir, entry: std.fs.Dir.Entry) void {
    if (entry.name.len != 66 or !std.mem.endsWith(u8, entry.name, ".o") or !isHexCacheKey(entry.name[0..64])) {
        manifest_value.unexpected_entries = true;
        return;
    }
    const manifest_entry = manifest_value.functions.getPtr(entry.name[0..64]) orelse {
        manifest_value.unexpected_entries = true;
        return;
    };
    if (!cacheDirEntryIsRegularFile(functions_dir, entry)) {
        manifest_value.unexpected_entries = true;
        return;
    }
    const stat = functions_dir.statFile(entry.name) catch return;
    if (stat.kind != .file or stat.size != manifest_entry.size) return;
    const hash_hex = hashDirFileHex(functions_dir, entry.name) catch return;
    manifest_entry.valid = std.mem.eql(u8, manifest_entry.sha256, hash_hex[0..]);
}

fn markIncrementalManifestFiles(manifest_value: *IncrementalObjectManifest, entry_dir: std.fs.Dir) void {
    var functions_dir = entry_dir.openDir("functions", .{ .iterate = true, .no_follow = true }) catch {
        manifest_value.unexpected_entries = true;
        return;
    };
    defer functions_dir.close();
    var iter = functions_dir.iterate();
    while (iter.next() catch {
        manifest_value.unexpected_entries = true;
        return;
    }) |entry| markIncrementalManifestFile(manifest_value, functions_dir, entry);
}

fn readIncrementalObjectManifest(
    allocator: std.mem.Allocator,
    entry_dir: std.fs.Dir,
    expected_key: []const u8,
    expected_source: ?[]const u8,
) !IncrementalObjectManifest {
    const manifest_bytes = try entry_dir.readFileAlloc(allocator, "manifest.json", project_cache_manifest_max_bytes);
    var manifest_value = try parseOwnedIncrementalObjectManifest(allocator, manifest_bytes, expected_key, expected_source);
    markIncrementalManifestFiles(&manifest_value, entry_dir);
    return manifest_value;
}

fn loadIncrementalObjectManifestAtPath(
    allocator: std.mem.Allocator,
    project_root: []const u8,
    cache_key: ProjectCacheKey,
    expected_source: []const u8,
) ?IncrementalObjectManifest {
    const entry_path = projectCacheDir(allocator, project_root, .build_obj_incremental, cache_key) catch return null;
    defer allocator.free(entry_path);
    var entry_dir = std.fs.cwd().openDir(entry_path, .{ .iterate = true, .no_follow = true }) catch return null;
    defer entry_dir.close();
    return readIncrementalObjectManifest(allocator, entry_dir, cache_key.slice(), expected_source) catch null;
}

fn cacheFunctionKeyBytes(hasher: *std.crypto.hash.sha2.Sha256, bytes: []const u8) void {
    cacheU64(hasher, bytes.len);
    hasher.update(bytes);
}

fn cacheFunctionKeyOptionalBytes(hasher: *std.crypto.hash.sha2.Sha256, bytes: ?[]const u8) void {
    cacheBool(hasher, bytes != null);
    if (bytes) |value| cacheFunctionKeyBytes(hasher, value);
}

fn cacheFunctionKeyUpstreamLoc(hasher: *std.crypto.hash.sha2.Sha256, loc: ?common_upstream.UpstreamLoc) void {
    cacheBool(hasher, loc != null);
    if (loc) |value| {
        cacheFunctionKeyBytes(hasher, value.file);
        cacheU64(hasher, value.line);
        cacheU64(hasher, value.col);
    }
}

fn cacheFunctionKeySymbolId(hasher: *std.crypto.hash.sha2.Sha256, symbols: *const flattener.SymbolTable, id: u32) void {
    if (symbols.lookupName(id)) |name| {
        cacheBool(hasher, true);
        cacheFunctionKeyBytes(hasher, name);
    } else {
        cacheBool(hasher, false);
        cacheU64(hasher, id);
    }
}

fn cacheFunctionSigGlobal(hasher: *std.crypto.hash.sha2.Sha256, sig_item: anytype) void {
    cacheFunctionKeyBytes(hasher, sig_item.name);
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
    cacheFunctionKeyOptionalBytes(hasher, sig_item.llvm_name);
    cacheU64(hasher, sig_item.params.len);
    for (sig_item.params) |param| {
        cacheU64(hasher, @intFromEnum(param.ty));
        cacheU64(hasher, @intFromEnum(param.cap));
    }
}

fn cacheFunctionSigLocal(
    hasher: *std.crypto.hash.sha2.Sha256,
    sig_item: anytype,
    symbols: *const flattener.SymbolTable,
    debug: bool,
) void {
    cacheU64(hasher, sig_item.params.len);
    for (sig_item.params) |param| cacheFunctionKeyBytes(hasher, param.name);
    cacheU64(hasher, sig_item.param_ids.len);
    for (sig_item.param_ids) |id| cacheFunctionKeySymbolId(hasher, symbols, id);
    cacheU64(hasher, sig_item.reg_ids.len);
    for (sig_item.reg_ids) |id| cacheFunctionKeySymbolId(hasher, symbols, id);
    cacheFunctionKeyOptionalBytes(hasher, sig_item.upstream_file);
    if (debug) {
        cacheU64(hasher, sig_item.entry_inst_idx);
        cacheFunctionKeyUpstreamLoc(hasher, sig_item.upstream_loc);
    }
}

fn cacheFunctionConstValue(hasher: *std.crypto.hash.sha2.Sha256, value: anytype) void {
    cacheU64(hasher, @intFromEnum(std.meta.activeTag(value)));
    switch (value) {
        .hex, .utf8, .repeat => |literal| {
            cacheU64(hasher, @intFromEnum(literal.kind));
            cacheFunctionKeyBytes(hasher, literal.bytes);
            cacheBool(hasher, literal.repeat_count != null);
            if (literal.repeat_count) |count| cacheU64(hasher, count);
            cacheBool(hasher, literal.repeat_byte != null);
            if (literal.repeat_byte) |byte| cacheU64(hasher, byte);
        },
        .struct_ => |literal| {
            cacheU64(hasher, literal.fields.len);
            for (literal.fields) |field| {
                cacheFunctionKeyBytes(hasher, field.name);
                cacheU64(hasher, field.size);
                cacheFunctionConstValue(hasher, field.value);
            }
        },
        .vtable => |literal| {
            cacheU64(hasher, literal.slots.len);
            for (literal.slots) |slot| {
                cacheFunctionKeyBytes(hasher, slot.name);
                cacheFunctionKeyBytes(hasher, slot.func_name);
            }
        },
    }
}

fn cacheFunctionOperand(hasher: *std.crypto.hash.sha2.Sha256, symbols: *const flattener.SymbolTable, operand: anytype) void {
    cacheU64(hasher, @intFromEnum(std.meta.activeTag(operand)));
    switch (operand) {
        .none => {},
        .reg => |slot| cacheU64(hasher, slot),
        .symbol, .label, .func => |id| cacheFunctionKeySymbolId(hasher, symbols, id),
        .imm_i64, .imm_int => |value| cacheU64(hasher, @bitCast(value)),
        .imm_u64 => |value| cacheU64(hasher, value),
        .imm_float => |value| cacheU64(hasher, @bitCast(value)),
        .op_code => |value| cacheU64(hasher, @intFromEnum(value)),
        .cap_prefix => |value| cacheU64(hasher, @intFromEnum(value)),
        .offset, .ty => |value| cacheU64(hasher, value),
        .text, .native_text => |value| cacheFunctionKeyBytes(hasher, value),
    }
}

fn cacheFunctionInstruction(
    hasher: *std.crypto.hash.sha2.Sha256,
    symbols: *const flattener.SymbolTable,
    item: referee.AnnotatedInstruction,
    loc: ?common_upstream.UpstreamLoc,
    debug: bool,
) void {
    const base = item.base;
    cacheU64(hasher, @intFromEnum(base.kind));
    cacheFunctionKeyBytes(hasher, base.raw_text);
    cacheFunctionKeyOptionalBytes(hasher, base.package_identity);
    cacheBool(hasher, base.package_source_sha256 != null);
    if (base.package_source_sha256) |digest| hasher.update(&digest);
    cacheBool(hasher, base.op_kind != null);
    if (base.op_kind) |kind| cacheU64(hasher, @intFromEnum(kind));
    for (base.operands) |operand| cacheFunctionOperand(hasher, symbols, operand);
    cacheBool(hasher, base.atomic_value_ty != null);
    if (base.atomic_value_ty) |ty| cacheU64(hasher, ty);
    cacheBool(hasher, base.atomic_ordering != null);
    if (base.atomic_ordering) |ordering| cacheU64(hasher, @intFromEnum(ordering));
    cacheBool(hasher, base.atomic_second_ordering != null);
    if (base.atomic_second_ordering) |ordering| cacheU64(hasher, @intFromEnum(ordering));
    cacheBool(hasher, base.atomic_rmw_op != null);
    if (base.atomic_rmw_op) |op| cacheU64(hasher, @intFromEnum(op));
    cacheFunctionKeyOptionalBytes(hasher, base.atomic_expected_text);
    cacheFunctionKeyOptionalBytes(hasher, base.atomic_new_text);
    cacheU64(hasher, base.native_reg_names.len);
    for (base.native_reg_names) |name| cacheFunctionKeyBytes(hasher, name);
    cacheU64(hasher, item.delta.changes.len);
    for (item.delta.changes) |change| {
        cacheU64(hasher, change.reg);
        cacheU64(hasher, change.before);
        cacheU64(hasher, change.after);
    }
    if (debug) {
        cacheU64(hasher, base.source_line);
        cacheU64(hasher, base.expanded_line);
        cacheFunctionKeyUpstreamLoc(hasher, base.upstream_loc);
        cacheFunctionKeyUpstreamLoc(hasher, loc);
    }
}

fn computeFunctionObjectKeyBase(
    allocator: std.mem.Allocator,
    cache_key: ProjectCacheKey,
    source_path: []const u8,
    compiled: *const CompileOk,
    debug: bool,
) !std.crypto.hash.sha2.Sha256 {
    var hasher = std.crypto.hash.sha2.Sha256.init(.{});
    cacheFunctionKeyBytes(&hasher, "sa-build-obj-function-cache/v8");
    cacheFunctionKeyBytes(&hasher, "llvmc-function-object/v8-local-register-slots");
    cacheFunctionKeyBytes(&hasher, cacheCompilerVersion());
    const backend_identity = try emit_llvm_llvmc.backendCacheIdentity(allocator);
    defer allocator.free(backend_identity);
    cacheFunctionKeyBytes(&hasher, backend_identity);
    cacheFunctionKeyBytes(&hasher, cache_key.slice());
    cacheFunctionKeyBytes(&hasher, source_path);
    cacheBool(&hasher, debug);
    cacheU64(&hasher, compiled.verified.function_sigs.len);
    for (compiled.verified.function_sigs) |sig_item| {
        cacheFunctionSigGlobal(&hasher, sig_item);
    }
    for (compiled.verified.const_decls) |decl| {
        cacheFunctionKeyBytes(&hasher, decl.name);
        cacheFunctionKeyBytes(&hasher, decl.literal_text);
        cacheFunctionConstValue(&hasher, decl.value);
        if (debug) cacheFunctionKeyUpstreamLoc(&hasher, decl.upstream_loc);
    }
    return hasher;
}

fn functionObjectInternalSymbolNamespace(base_hasher: std.crypto.hash.sha2.Sha256) [64]u8 {
    var hasher = base_hasher;
    cacheFunctionKeyBytes(&hasher, "internal-symbol-namespace/v1");
    var digest: [32]u8 = undefined;
    hasher.final(&digest);
    return std.fmt.bytesToHex(digest, .lower);
}

fn computeFunctionObjectKey(
    allocator: std.mem.Allocator,
    base_hasher: std.crypto.hash.sha2.Sha256,
    compiled: *const CompileOk,
    sig_index: usize,
    task_index: usize,
    start_idx: usize,
    end_idx: usize,
    debug: bool,
    owns_process_globals: bool,
) ![]const u8 {
    var hasher = base_hasher;
    if (sig_index >= compiled.verified.function_sigs.len) return error.UnknownFunction;
    cacheFunctionSigLocal(&hasher, compiled.verified.function_sigs[sig_index], &compiled.verified.symbols, debug);
    cacheU64(&hasher, sig_index);
    cacheU64(&hasher, task_index);
    cacheBool(&hasher, owns_process_globals);
    cacheU64(&hasher, end_idx - start_idx);
    for (compiled.verified.annotated[start_idx..end_idx], start_idx..) |item, annotated_idx| {
        const loc = if (annotated_idx < compiled.flat.loc_table.len) compiled.flat.loc_table[annotated_idx] else null;
        cacheFunctionInstruction(&hasher, &compiled.verified.symbols, item, loc, debug);
    }
    var out: [32]u8 = undefined;
    hasher.final(&out);
    const hex = std.fmt.bytesToHex(out, .lower);
    return try allocator.dupe(u8, hex[0..]);
}

const IncrementalFunctionObjectRecord = struct {
    function_key: []const u8,
    object_path: []const u8,
    metadata: IncrementalFunctionObjectMetadata,
    transient: bool,
};

const IncrementalFunctionObjectEmission = struct {
    transient_path: ?[]u8,
    metadata: IncrementalFunctionObjectMetadata,
};

fn cacheDirEntryIsRegularFile(dir: std.fs.Dir, entry: std.fs.Dir.Entry) bool {
    return switch (entry.kind) {
        .file => true,
        .unknown => blk: {
            var link_buf: [std.fs.max_path_bytes]u8 = undefined;
            _ = dir.readLink(entry.name, &link_buf) catch |err| switch (err) {
                error.NotLink => {
                    const stat = dir.statFile(entry.name) catch break :blk false;
                    break :blk stat.kind == .file;
                },
                else => break :blk false,
            };
            break :blk false;
        },
        else => false,
    };
}

fn cachePathIsRegularFile(path: []const u8) bool {
    const parent = std.fs.path.dirname(path) orelse ".";
    const basename = std.fs.path.basename(path);
    var dir = std.fs.cwd().openDir(parent, .{ .iterate = true, .no_follow = true }) catch return false;
    defer dir.close();
    var iter = dir.iterate();
    while (iter.next() catch return false) |entry| {
        if (std.mem.eql(u8, entry.name, basename)) return cacheDirEntryIsRegularFile(dir, entry);
    }
    return false;
}

fn createIncrementalObjectStagingPath(allocator: std.mem.Allocator, object_path: []const u8) ![]u8 {
    try ensureParentDir(object_path);
    for (0..8) |_| {
        var random: [8]u8 = undefined;
        std.crypto.random.bytes(&random);
        const suffix = std.fmt.bytesToHex(random, .lower);
        const staging_path = try std.fmt.allocPrint(allocator, "{s}.tmp.{s}", .{ object_path, suffix[0..] });
        var file = std.fs.cwd().createFile(staging_path, .{ .exclusive = true }) catch |err| switch (err) {
            error.PathAlreadyExists => {
                allocator.free(staging_path);
                continue;
            },
            else => {
                allocator.free(staging_path);
                return err;
            },
        };
        file.close();
        return staging_path;
    }
    return error.CacheStagingCollision;
}

fn incrementalObjectMatches(
    allocator: std.mem.Allocator,
    path: []const u8,
    expected_size: u64,
    expected_sha256: []const u8,
) bool {
    if (!cachePathIsRegularFile(path)) return false;
    const stat = std.fs.cwd().statFile(path) catch return false;
    if (stat.kind != .file or stat.size != expected_size) return false;
    const hash_hex = hashFileHex(allocator, path) catch return false;
    return std.mem.eql(u8, expected_sha256, hash_hex[0..]);
}

fn emitIncrementalFunctionObjectAtomically(
    allocator: std.mem.Allocator,
    compiled: *const CompileOk,
    source_path: []const u8,
    object_path: []const u8,
    debug: bool,
    opt_level: u8,
    task_index: usize,
    owns_process_globals: bool,
    internal_symbol_namespace: []const u8,
    compile_options: CompileOptions,
    emit_std_root: []const u8,
    publish: bool,
) !IncrementalFunctionObjectEmission {
    const staging_path = try createIncrementalObjectStagingPath(allocator, object_path);
    var staging_owned = true;
    errdefer if (staging_owned) {
        std.fs.cwd().deleteFile(staging_path) catch |err| {
            _ = @errorName(err);
        };
        allocator.free(staging_path);
    };

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
            .function_task_index = task_index,
            .function_task_owns_process_globals = owns_process_globals,
            .internal_symbol_namespace = internal_symbol_namespace,
            .dce = compile_options.dce,
            .std_root = emit_std_root,
        },
        staging_path,
        opt_level,
    );
    const stat = try std.fs.cwd().statFile(staging_path);
    if (stat.kind != .file or stat.size == 0) return error.InvalidCacheArtifact;
    try syncCacheFile(staging_path);
    const hash_hex = try hashFileHex(allocator, staging_path);
    const metadata = IncrementalFunctionObjectMetadata{ .size = stat.size, .sha256 = hash_hex };

    if (!publish) {
        staging_owned = false;
        return .{ .transient_path = staging_path, .metadata = metadata };
    }

    renameCachePath(staging_path, object_path) catch {
        if (incrementalObjectMatches(allocator, object_path, stat.size, hash_hex[0..])) {
            std.fs.cwd().deleteFile(staging_path) catch |err| {
                _ = @errorName(err);
            };
            allocator.free(staging_path);
            staging_owned = false;
            return .{ .transient_path = null, .metadata = metadata };
        }
        staging_owned = false;
        return .{ .transient_path = staging_path, .metadata = metadata };
    };
    allocator.free(staging_path);
    staging_owned = false;
    return .{ .transient_path = null, .metadata = metadata };
}

fn writeIncrementalObjectManifest(
    allocator: std.mem.Allocator,
    project_root: []const u8,
    cache_key: ProjectCacheKey,
    source_path: []const u8,
    records: []const IncrementalFunctionObjectRecord,
) !void {
    if (records.len == 0 or records.len > 65_536) return error.InvalidCacheManifest;
    var contents = std.ArrayList(u8).init(allocator);
    defer contents.deinit();
    const writer = contents.writer();
    try writer.writeAll("{\"version\":2,\"kind\":\"build-obj-incremental\",\"key\":");
    try writeJsonString(writer, cache_key.slice());
    try writer.writeAll(",\"source\":");
    try writeJsonString(writer, source_path);
    try writer.writeAll(",\"functions\":[");
    for (records, 0..) |record, index| {
        if (record.transient or record.metadata.size == 0) return error.InvalidCacheArtifact;
        if (index != 0) try writer.writeByte(',');
        try writer.writeAll("{\"key\":");
        try writeJsonString(writer, record.function_key);
        try writer.writeAll(",\"path\":");
        var relative_path_buf: [96]u8 = undefined;
        const relative_path = try std.fmt.bufPrint(&relative_path_buf, "functions/{s}.o", .{record.function_key});
        try writeJsonString(writer, relative_path);
        try writer.writeAll(",\"size\":");
        try writer.print("{d}", .{record.metadata.size});
        try writer.writeAll(",\"sha256\":");
        try writeJsonString(writer, record.metadata.sha256[0..]);
        try writer.writeByte('}');
    }
    try writer.writeAll("]}\n");

    const manifest_path = try projectFunctionCacheManifestPath(allocator, project_root, cache_key);
    defer allocator.free(manifest_path);
    try writeCacheManifestBytesAtomically(allocator, manifest_path, contents.items);
}

fn deleteIncrementalCacheChild(dir: std.fs.Dir, entry: std.fs.Dir.Entry) void {
    if (entry.kind == .directory) {
        dir.deleteTree(entry.name) catch |err| {
            _ = @errorName(err);
        };
    } else {
        dir.deleteFile(entry.name) catch |err| {
            _ = @errorName(err);
        };
    }
}

fn cleanupIncrementalObjectEntry(
    allocator: std.mem.Allocator,
    project_root: []const u8,
    cache_key: ProjectCacheKey,
    records: []const IncrementalFunctionObjectRecord,
) void {
    var keep = std.StringHashMap(void).init(allocator);
    defer keep.deinit();
    for (records) |record| keep.put(record.function_key, {}) catch return;

    const entry_path = projectCacheDir(allocator, project_root, .build_obj_incremental, cache_key) catch return;
    defer allocator.free(entry_path);
    var entry_dir = std.fs.cwd().openDir(entry_path, .{ .iterate = true, .no_follow = true }) catch return;
    defer entry_dir.close();

    if (entry_dir.openDir("functions", .{ .iterate = true, .no_follow = true })) |functions_dir_value| {
        var functions_dir = functions_dir_value;
        defer functions_dir.close();
        var iter = functions_dir.iterate();
        while (iter.next() catch return) |entry| {
            const keep_entry = cacheDirEntryIsRegularFile(functions_dir, entry) and
                entry.name.len == 66 and
                std.mem.endsWith(u8, entry.name, ".o") and
                isHexCacheKey(entry.name[0..64]) and
                keep.contains(entry.name[0..64]);
            if (!keep_entry) deleteIncrementalCacheChild(functions_dir, entry);
        }
    } else |_| {}

    var entry_iter = entry_dir.iterate();
    while (entry_iter.next() catch return) |entry| {
        if (std.mem.startsWith(u8, entry.name, "manifest.json.tmp.")) deleteIncrementalCacheChild(entry_dir, entry);
    }
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
    var entry_lock = try acquireProjectCacheEntryLock(allocator, project_root, .build_obj_incremental, cache_key, .exclusive);
    defer entry_lock.deinit();
    const cacheable = compiled.flat.dynamic_dependencies_cacheable;
    var existing_manifest = if (cacheable) loadIncrementalObjectManifestAtPath(allocator, project_root, cache_key, source_path) else null;
    defer if (existing_manifest) |*manifest_value| manifest_value.deinit(allocator);
    const opt_level = emitOptLevel(debug, optimization);
    const emit_std_root = try stdRootFromEnv(allocator);
    defer allocator.free(emit_std_root);
    const selected_task_indices = try emit_llvm_llvmc.collectIncrementalFunctionTaskIndices(allocator, compiled.verified, source_path, .{
        .dce = compile_options.dce,
        .std_root = emit_std_root,
    });
    defer allocator.free(selected_task_indices);
    if (selected_task_indices.len == 0) {
        try emit_llvm_llvmc.emitLlvmcToObject(
            allocator,
            compiled.verified,
            &compiled.flat.def_dict,
            compiled.flat.loc_table,
            source_path,
            nativeSizeBits(),
            .{
                .debug = debug,
                .jobs = compile_options.jobs,
                .opt_level = opt_level,
                .dce = compile_options.dce,
                .std_root = emit_std_root,
            },
            out_path,
            opt_level,
        );
        return;
    }
    const process_globals_owner_task_index = selected_task_indices[0];
    var records = std.ArrayList(IncrementalFunctionObjectRecord).init(allocator);
    defer {
        for (records.items) |record| {
            if (record.transient) {
                std.fs.cwd().deleteFile(record.object_path) catch |err| {
                    _ = @errorName(err);
                };
            }
            allocator.free(record.function_key);
            allocator.free(record.object_path);
        }
        records.deinit();
    }
    var cache_publication_ready = cacheable;
    const function_key_base = try computeFunctionObjectKeyBase(allocator, cache_key, source_path, compiled, debug);
    const internal_symbol_namespace = functionObjectInternalSymbolNamespace(function_key_base);

    var sig_index: usize = 0;
    var idx: usize = 0;
    var task_idx: usize = 0;
    var selected_task_cursor: usize = 0;
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

                const selected = selected_task_cursor < selected_task_indices.len and selected_task_indices[selected_task_cursor] == task_idx;
                if (selected) {
                    selected_task_cursor += 1;
                    const owns_process_globals = task_idx == process_globals_owner_task_index;
                    const function_key = try computeFunctionObjectKey(allocator, function_key_base, compiled, current_sig_index, task_idx, idx, end, debug, owns_process_globals);
                    var function_key_owned = true;
                    errdefer if (function_key_owned) allocator.free(function_key);
                    var record_owned = true;
                    var object_path = try projectFunctionCachePath(allocator, project_root, cache_key, function_key);
                    var transient = false;
                    errdefer if (record_owned) {
                        if (transient) {
                            std.fs.cwd().deleteFile(object_path) catch |err| {
                                _ = @errorName(err);
                            };
                        }
                        allocator.free(object_path);
                    };
                    var metadata = if (existing_manifest) |*manifest_value| manifest_value.objectMetadata(function_key) else null;
                    if (metadata == null) {
                        const emission = try emitIncrementalFunctionObjectAtomically(allocator, compiled, source_path, object_path, debug, opt_level, task_idx, owns_process_globals, internal_symbol_namespace[0..], compile_options, emit_std_root, cache_publication_ready);
                        metadata = emission.metadata;
                        if (emission.transient_path) |transient_path| {
                            allocator.free(object_path);
                            object_path = transient_path;
                            transient = true;
                            cache_publication_ready = false;
                        }
                    }
                    try records.append(.{
                        .function_key = function_key,
                        .object_path = object_path,
                        .metadata = metadata.?,
                        .transient = transient,
                    });
                    record_owned = false;
                    function_key_owned = false;
                }

                task_idx += 1;
                idx = end - 1;
            },
            else => {},
        }
    }

    if (selected_task_cursor != selected_task_indices.len) return error.UnknownFunction;
    if (records.items.len == 0) return error.UnknownFunction;

    const object_paths = try allocator.alloc([]const u8, records.items.len);
    defer allocator.free(object_paths);
    for (records.items, 0..) |record, index| object_paths[index] = record.object_path;

    try ensureParentDir(out_path);
    driver.compileRelocatableObj(allocator, object_paths, out_path, stderr) catch |err| switch (err) {
        error.ChildProcessFailed => return error.ChildProcessFailed,
        else => return err,
    };

    if (!cache_publication_ready) return;
    writeIncrementalObjectManifest(allocator, project_root, cache_key, source_path, records.items) catch return;
    cleanupIncrementalObjectEntry(allocator, project_root, cache_key, records.items);
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
    package_name: ?[]const u8 = null,
};

fn fetchManifestRequires(allocator: std.mem.Allocator, manifest_file: *const manifest.Manifest, fetch_options: pkg_fetch.FetchOptions, stdout: anytype) !void {
    for (manifest_file.requires) |entry| {
        var entry_fetch_options = fetch_options;
        entry_fetch_options.expected_source_sha256 = entry.source_sha256;
        var result = try pkg_fetch.fetchPackage(allocator, entry.url, entry.ref, entry_fetch_options);
        defer result.deinit(allocator);
        if (!hashesEqual(result.source_sha256, entry.source_sha256)) return error.UpstreamShaMismatch;
        try stdout.print("{s}\n", .{result.root});
    }
}

fn installManifestPlugins(allocator: std.mem.Allocator, manifest_file: *const manifest.Manifest, stdout: anytype) !u8 {
    for (manifest_file.plugin_requires) |entry| {
        _ = entry.abi;
        _ = entry.ref;
        const code = try plugins.installFromPath(allocator, entry.identity, stdout, .{});
        if (code != 0) return code;
    }
    return 0;
}

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
        if (std.mem.eql(u8, arg, "--package") or std.mem.eql(u8, arg, "-p")) {
            if (i + 1 >= args.len) return error.UnknownPackage;
            parsed.package_name = args[i + 1];
            i += 1;
            continue;
        }
        if (std.mem.startsWith(u8, arg, "--package=")) {
            parsed.package_name = arg["--package=".len..];
            continue;
        }
        if (std.mem.startsWith(u8, arg, "-p=")) {
            parsed.package_name = arg["-p=".len..];
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

fn installManifestDependencies(allocator: std.mem.Allocator, options: pkg_fetch.FetchOptions, package_name: ?[]const u8, stdout: anytype) !u8 {
    var resolution = try pkg_workspace.resolveFromCurrentDir(allocator, .{ .request = package_name });
    defer resolution.deinit(allocator);

    const project_root = resolution.workspace_root;
    const project_manifest = resolution.effective_manifest orelse return 0;

    const current_dir = try std.fs.cwd().realpathAlloc(allocator, ".");
    defer allocator.free(current_dir);

    if (package_name == null and
        resolution.workspace_manifest != null and
        resolution.workspace_manifest.?.workspace != null and
        std.mem.eql(u8, current_dir, resolution.workspace_root))
    {
        const members = try pkg_workspace.listWorkspaceMembers(allocator, resolution.workspace_root, &resolution.workspace_manifest.?);
        defer pkg_workspace.freeWorkspaceMembers(allocator, members);

        var member_manifests = std.ArrayList(manifest.Manifest).init(allocator);
        defer {
            for (member_manifests.items) |*member_manifest| member_manifest.deinit(allocator);
            member_manifests.deinit();
        }

        var member_manifest_ptrs = std.ArrayList(*const manifest.Manifest).init(allocator);
        defer member_manifest_ptrs.deinit();

        for (members) |member| {
            const member_manifest_path = try projectManifestPath(allocator, member.member_root);
            defer allocator.free(member_manifest_path);
            const member_manifest = try readManifestFile(allocator, member_manifest_path);
            try member_manifests.append(member_manifest);
        }

        for (member_manifests.items) |*member_manifest| {
            try member_manifest_ptrs.append(member_manifest);
        }

        var aggregate_manifest = try manifest.mergeWorkspaceMemberSet(
            allocator,
            &resolution.workspace_manifest.?,
            member_manifest_ptrs.items,
        );
        defer aggregate_manifest.deinit(allocator);

        var mirror_rules = try pkg_mirror.loadProjectRules(allocator, project_root, aggregate_manifest.mirrors);
        defer mirror_rules.deinit(allocator);

        var fetch_options = options;
        fetch_options.mirror_rules = mirror_rules.rules;

        try fetchManifestRequires(allocator, &aggregate_manifest, fetch_options, stdout);
        const plugin_code = try installManifestPlugins(allocator, &aggregate_manifest, stdout);
        if (plugin_code != 0) return plugin_code;

        var update = try pkg_sum.updateProjectSum(allocator, project_root, aggregate_manifest);
        defer update.deinit(allocator);
        return 0;
    }

    var mirror_rules = try pkg_mirror.loadProjectRules(allocator, project_root, project_manifest.mirrors);
    defer mirror_rules.deinit(allocator);

    var fetch_options = options;
    fetch_options.mirror_rules = mirror_rules.rules;

    try fetchManifestRequires(allocator, &project_manifest, fetch_options, stdout);
    const plugin_code = try installManifestPlugins(allocator, &project_manifest, stdout);
    if (plugin_code != 0) return plugin_code;

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
    return try installManifestDependencies(allocator, parsed.options, parsed.package_name, stdout);
}

fn executePkgCommandFallback(allocator: std.mem.Allocator, args: []const []const u8, stdout: anytype, stderr: anytype) !?u8 {
    if (args.len < 3) return null;
    const sub = args[2];
    if (std.mem.eql(u8, sub, "install")) {
        return try executeInstall(allocator, args[3..], stdout);
    }
    _ = stderr;
    return null;
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

fn archivePathIfReadable(allocator: std.mem.Allocator, root: []const u8, archive_name: []const u8) !?[]u8 {
    const archive = try std.fs.path.join(allocator, &.{ root, archive_name });
    errdefer allocator.free(archive);
    std.fs.cwd().access(archive, .{ .mode = .read_only }) catch |err| switch (err) {
        error.FileNotFound => {
            allocator.free(archive);
            return null;
        },
        else => return err,
    };
    return archive;
}

fn saStdArchiveNameFor(os_tag: std.Target.Os.Tag) []const u8 {
    return switch (os_tag) {
        .windows => "sa_std.lib",
        else => "libsa_std.a",
    };
}

fn saStdArchivePath(allocator: std.mem.Allocator) ![]u8 {
    const archive_name = saStdArchiveNameFor(builtin.os.tag);
    if (builtin.is_test) {
        return try allocator.dupe(u8, build_options.test_sa_std_archive_path);
    }
    const env_root: ?[]u8 = std.process.getEnvVarOwned(allocator, "SA_STD_DIR") catch |err| switch (err) {
        error.EnvironmentVariableNotFound => null,
        else => return err,
    };
    if (env_root) |root| {
        defer allocator.free(root);
        if (try archivePathIfReadable(allocator, root, archive_name)) |archive| return archive;
    }

    if (std.fs.selfExeDirPathAlloc(allocator)) |exe_dir| {
        defer allocator.free(exe_dir);
        const sibling_roots = [_][]const u8{ "../std", "../lib" };
        for (sibling_roots) |sibling| {
            const root = try std.fs.path.join(allocator, &.{ exe_dir, sibling });
            defer allocator.free(root);
            if (try archivePathIfReadable(allocator, root, archive_name)) |archive| return archive;
        }
    } else |_| {}

    const source_tree_root = if (builtin.os.tag == .windows) "zig-out/lib" else "artifacts/sa_std";
    if (try archivePathIfReadable(allocator, source_tree_root, archive_name)) |archive| {
        return archive;
    }
    return error.FileNotFound;
}

test "runtime archive name matches native Zig library output" {
    try std.testing.expectEqualStrings("libsa_std.a", saStdArchiveNameFor(.linux));
    try std.testing.expectEqualStrings("libsa_std.a", saStdArchiveNameFor(.macos));
    try std.testing.expectEqualStrings("sa_std.lib", saStdArchiveNameFor(.windows));
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
            try writeSuccessDiagnostics(stderr, owned.metrics, diagnostics_mode);
            return code;
        },
    }
}

fn executeBuildExe(allocator: std.mem.Allocator, source_path: []const u8, out_path: []const u8, debug: bool, optimization: driver.Optimization, compile_options: CompileOptions, stderr: anytype, diagnostics_mode: DiagnosticsMode) !u8 {
    const total_start = if (compile_options.profile) std.time.Instant.now() catch null else null;
    const project_root_owned = compile_options.project_root == null;
    const project_root = compile_options.project_root orelse try projectRootFromSourcePath(allocator, source_path);
    defer if (project_root_owned) allocator.free(project_root);
    var project_context = try loadProjectContext(allocator, project_root, compile_options.package_name);
    defer project_context.deinit(allocator);
    const std_archive_path = try saStdArchivePath(allocator);
    defer allocator.free(std_archive_path);
    const cache_key: ?ProjectCacheKey = if (compile_options.incremental_cache)
        try computeProjectBuildKeyAndRecordInputs(allocator, &project_context, project_root, source_path, "exe", "", .build_exe, debug, optimization == .release_fast, false, null, true, compile_options.offline, compile_options.dce, compile_options.jobs, compile_options.jobs_explicit, &.{std_archive_path})
    else
        null;
    const artifact_path = try intermediateArtifactPath(allocator, out_path);
    defer allocator.free(artifact_path);
    var output_stage = try BuildOutputStage.init(allocator, out_path);
    defer output_stage.deinit(allocator);
    var cache_owner: ?ProjectCacheEntryLock = null;
    var cache_miss_reason: ?ProjectCacheLookupReason = null;
    defer releaseProjectCacheOwner(&cache_owner);

    if (cache_key) |key| {
        const claim: ?ProjectCacheClaimResult = projectCacheClaim(allocator, project_root, .build_exe, key, &project_context, compile_options, output_stage.artifact_path, output_stage.output_path, stderr, diagnostics_mode) catch |err| blk: {
            _ = @errorName(err);
            cache_miss_reason = .lock_owner_failed;
            break :blk null;
        };
        if (claim) |result| switch (result) {
            .owner => |owner| {
                cache_miss_reason = owner.miss_reason;
                cache_owner = owner.lock;
            },
            .authorization_rejected => return 1,
            .hit => {
                try output_stage.publish(allocator, artifact_path, out_path, true, true);
                if (diagnostics_mode == .json or compile_options.mem_report) {
                    const metrics = CompileMetrics{ .compile_tokens = 0, .instruction_count = 0, .phases = if (compile_options.profile) .{ .load_ns = 0, .setup_ns = 0, .flatten_ns = 0, .verify_ns = 0, .emit_ns = 0, .link_ns = 0, .total_ns = if (total_start) |start| elapsedNs(start) else null } else null, .memory = cacheHitMemoryMetrics(compile_options.mem_report), .cache = .{ .kind = BuildCacheKind.build_exe.dirName(), .hit = true, .reason = ProjectCacheLookupReason.hit.jsonName() } };
                    try writeSuccessDiagnostics(stderr, metrics, diagnostics_mode);
                }
                return 0;
            },
        };
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
            const emit_std_root = try stdRootFromEnv(allocator);
            defer allocator.free(emit_std_root);

            const worker_count = blk: {
                if (compile_options.jobs) |j| {
                    break :blk j;
                }
                break :blk std.Thread.getCpuCount() catch 1;
            };
            const emission_workers = @max(@min(worker_count, 4), 1);
            const use_cgu = (compile_options.jobs_explicit and emission_workers > 1 and owned.verified.function_sigs.len >= 100);
            if (use_cgu or !owned.flat.dynamic_dependencies_cacheable) {
                cache_miss_reason = .bypassed_untrusted;
                releaseProjectCacheOwner(&cache_owner);
            }

            if (use_cgu) {
                const cgu_count = @min(@max(emission_workers, 2), 4);

                const cgu_obj_paths = try allocator.alloc([]const u8, cgu_count);
                defer {
                    for (cgu_obj_paths) |p| allocator.free(p);
                    allocator.free(cgu_obj_paths);
                }
                for (0..cgu_count) |i| {
                    cgu_obj_paths[i] = try std.fmt.allocPrint(allocator, "{s}_cgu_{d}.o", .{ output_stage.output_path, i });
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
                    std_root_val: []const u8,
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
                                .std_root = self.std_root_val,
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
                        .std_root_val = emit_std_root,
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
                recordMetricMemoryAfterEmit(&owned.metrics);
                if (owned.metrics.memory) |memory| try writeMemoryStageSampleForOptions(compile_options, "after_emit", memory.after_emit_rss_bytes, memory.after_verify_rss_bytes);

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
                driver.compileExe(allocator, cgu_obj_paths[0], output_stage.output_path, optimization, std_archive_path, link_inputs.items, debug, stderr) catch |err| switch (err) {
                    error.ChildProcessFailed => return 1,
                    else => return err,
                };
                const link_ns = if (link_start) |start| elapsedNs(start) else null;
                recordMetricMemoryAfterLink(&owned.metrics);
                if (owned.metrics.memory) |memory| try writeMemoryStageSampleForOptions(compile_options, "after_link", memory.after_link_rss_bytes, memory.after_emit_rss_bytes);
                recordMetricMemoryEnd(&owned.metrics);
                if (owned.metrics.memory) |memory| try writeMemoryStageSampleForOptions(compile_options, "end", memory.end_rss_bytes, memoryEndPrevious(memory));
                finishProfileMetrics(&owned.metrics, emit_ns, link_ns, if (total_start) |start| elapsedNs(start) else null);
                try output_stage.publish(allocator, artifact_path, out_path, false, true);
            } else {
                try ensureParentDir(output_stage.artifact_path);
                const emit_start = if (compile_options.profile) std.time.Instant.now() catch null else null;
                try emit_llvm_llvmc.emitLlvmcToFile(allocator, owned.verified, &owned.flat.def_dict, owned.flat.loc_table, source_path, nativeSizeBits(), .{ .debug = debug, .jobs = compile_options.jobs, .opt_level = emitOptLevel(debug, optimization), .dce = compile_options.dce, .std_root = emit_std_root }, output_stage.artifact_path);
                const emit_ns = if (emit_start) |start| elapsedNs(start) else null;
                recordMetricMemoryAfterEmit(&owned.metrics);
                if (owned.metrics.memory) |memory| try writeMemoryStageSampleForOptions(compile_options, "after_emit", memory.after_emit_rss_bytes, memory.after_verify_rss_bytes);

                const link_start = if (compile_options.profile) std.time.Instant.now() catch null else null;
                var link_inputs = std.ArrayList([]const u8).init(allocator);
                defer link_inputs.deinit();
                var owned_link_inputs = std.ArrayList([]const u8).init(allocator);
                defer {
                    for (owned_link_inputs.items) |arg| allocator.free(arg);
                    owned_link_inputs.deinit();
                }
                try appendNativePluginLinkInputs(allocator, &link_inputs, &owned_link_inputs, &owned.verified);
                if (owned_link_inputs.items.len != 0) {
                    cache_miss_reason = .bypassed_untrusted;
                    releaseProjectCacheOwner(&cache_owner);
                }
                driver.compileExe(allocator, output_stage.artifact_path, output_stage.output_path, optimization, std_archive_path, link_inputs.items, debug, stderr) catch |err| switch (err) {
                    error.ChildProcessFailed => return 1,
                    else => return err,
                };
                const link_ns = if (link_start) |start| elapsedNs(start) else null;
                recordMetricMemoryAfterLink(&owned.metrics);
                if (owned.metrics.memory) |memory| try writeMemoryStageSampleForOptions(compile_options, "after_link", memory.after_link_rss_bytes, memory.after_emit_rss_bytes);
                recordMetricMemoryEnd(&owned.metrics);
                if (owned.metrics.memory) |memory| try writeMemoryStageSampleForOptions(compile_options, "end", memory.end_rss_bytes, memoryEndPrevious(memory));
                finishProfileMetrics(&owned.metrics, emit_ns, link_ns, if (total_start) |start| elapsedNs(start) else null);
                if (cache_key) |key| {
                    if (owned.flat.dynamic_dependencies_cacheable and cache_owner != null) {
                        projectCacheStoreWithOwnerMissReason(allocator, project_root, .build_exe, key, output_stage.artifact_path, output_stage.output_path, owned.flat.dynamic_dependencies, cache_miss_reason) catch |err| {
                            _ = @errorName(err);
                        };
                        releaseProjectCacheOwner(&cache_owner);
                    }
                }
                try output_stage.publish(allocator, artifact_path, out_path, true, true);
            }
            attachBackendIrMetrics(&owned.metrics, &owned.verified, debug);
            if (cache_key != null) {
                owned.metrics.cache = .{ .kind = BuildCacheKind.build_exe.dirName(), .hit = false, .reason = projectCacheLookupReasonName(cache_miss_reason) };
            } else if (!compile_options.incremental_cache) {
                owned.metrics.cache = .{ .kind = BuildCacheKind.build_exe.dirName(), .hit = false, .reason = ProjectCacheLookupReason.disabled.jsonName() };
            }

            try writeSuccessDiagnostics(stderr, owned.metrics, diagnostics_mode);
            return 0;
        },
    }
}

fn executeBuildObj(allocator: std.mem.Allocator, source_path: []const u8, out_path: []const u8, debug: bool, optimization: driver.Optimization, incremental: bool, compile_options: CompileOptions, stderr: anytype, diagnostics_mode: DiagnosticsMode) !u8 {
    const total_start = if (compile_options.profile) std.time.Instant.now() catch null else null;
    const project_root_owned = compile_options.project_root == null;
    const project_root = compile_options.project_root orelse try projectRootFromSourcePath(allocator, source_path);
    defer if (project_root_owned) allocator.free(project_root);
    var project_context = try loadProjectContext(allocator, project_root, compile_options.package_name);
    defer project_context.deinit(allocator);
    const cache_key: ?ProjectCacheKey = if (compile_options.incremental_cache)
        try computeProjectBuildKeyAndRecordInputs(allocator, &project_context, project_root, source_path, "obj", "", .build_obj, debug, optimization == .release_fast, incremental, null, true, compile_options.offline, compile_options.dce, compile_options.jobs, compile_options.jobs_explicit, &.{})
    else
        null;
    const artifact_path = try intermediateArtifactPath(allocator, out_path);
    defer allocator.free(artifact_path);
    var output_stage = try BuildOutputStage.init(allocator, out_path);
    defer output_stage.deinit(allocator);
    var cache_owner: ?ProjectCacheEntryLock = null;
    var cache_miss_reason: ?ProjectCacheLookupReason = null;
    defer releaseProjectCacheOwner(&cache_owner);

    if (cache_key) |key| {
        const claim: ?ProjectCacheClaimResult = projectCacheClaim(allocator, project_root, .build_obj, key, &project_context, compile_options, output_stage.artifact_path, output_stage.output_path, stderr, diagnostics_mode) catch |err| blk: {
            _ = @errorName(err);
            cache_miss_reason = .lock_owner_failed;
            break :blk null;
        };
        if (claim) |result| switch (result) {
            .owner => |owner| {
                cache_miss_reason = owner.miss_reason;
                cache_owner = owner.lock;
            },
            .authorization_rejected => return 1,
            .hit => {
                try output_stage.publish(allocator, artifact_path, out_path, true, false);
                if (diagnostics_mode == .json or compile_options.mem_report) {
                    const metrics = CompileMetrics{ .compile_tokens = 0, .instruction_count = 0, .phases = if (compile_options.profile) .{ .load_ns = 0, .setup_ns = 0, .flatten_ns = 0, .verify_ns = 0, .emit_ns = 0, .link_ns = 0, .total_ns = if (total_start) |start| elapsedNs(start) else null } else null, .memory = cacheHitMemoryMetrics(compile_options.mem_report), .cache = .{ .kind = BuildCacheKind.build_obj.dirName(), .hit = true, .reason = ProjectCacheLookupReason.hit.jsonName() } };
                    try writeSuccessDiagnostics(stderr, metrics, diagnostics_mode);
                }
                return 0;
            },
        };
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
            if (!owned.flat.dynamic_dependencies_cacheable) {
                cache_miss_reason = .bypassed_untrusted;
                releaseProjectCacheOwner(&cache_owner);
            }
            const emit_std_root = try stdRootFromEnv(allocator);
            defer allocator.free(emit_std_root);
            try ensureParentDir(output_stage.artifact_path);
            const emit_start = if (compile_options.profile) std.time.Instant.now() catch null else null;
            const opt_level = emitOptLevel(debug, optimization);
            if (incremental) {
                // Function tasks always emit serially, so job scheduling must not
                // partition their reusable object namespace. DCE remains semantic.
                const incremental_key = (try computeProjectBuildKeyAndRecordInputs(allocator, &project_context, project_root, source_path, "obj", "", .build_obj_incremental, debug, optimization == .release_fast, true, null, false, compile_options.offline, compile_options.dce, null, false, &.{})) orelse unreachable;
                try buildIncrementalObject(allocator, project_root, incremental_key, &owned, source_path, output_stage.output_path, debug, optimization, compile_options, stderr);
                try emit_llvm_llvmc.emitLlvmcToFile(allocator, owned.verified, &owned.flat.def_dict, owned.flat.loc_table, source_path, nativeSizeBits(), .{ .debug = debug, .jobs = compile_options.jobs, .opt_level = opt_level, .dce = compile_options.dce, .std_root = emit_std_root }, output_stage.artifact_path);
            } else {
                try emit_llvm_llvmc.emitLlvmcToArtifacts(allocator, owned.verified, &owned.flat.def_dict, owned.flat.loc_table, source_path, nativeSizeBits(), .{ .debug = debug, .jobs = compile_options.jobs, .opt_level = opt_level, .dce = compile_options.dce, .std_root = emit_std_root }, output_stage.artifact_path, output_stage.output_path, opt_level);
            }
            recordMetricMemoryAfterEmit(&owned.metrics);
            if (owned.metrics.memory) |memory| try writeMemoryStageSampleForOptions(compile_options, "after_emit", memory.after_emit_rss_bytes, memory.after_verify_rss_bytes);
            recordMetricMemoryEnd(&owned.metrics);
            if (owned.metrics.memory) |memory| try writeMemoryStageSampleForOptions(compile_options, "end", memory.end_rss_bytes, memoryEndPrevious(memory));
            finishProfileMetrics(&owned.metrics, if (emit_start) |start| elapsedNs(start) else null, null, if (total_start) |start| elapsedNs(start) else null);
            attachBackendIrMetrics(&owned.metrics, &owned.verified, debug);
            if (cache_key) |key| {
                if (owned.flat.dynamic_dependencies_cacheable and cache_owner != null) {
                    projectCacheStoreWithOwnerMissReason(allocator, project_root, .build_obj, key, output_stage.artifact_path, output_stage.output_path, owned.flat.dynamic_dependencies, cache_miss_reason) catch |err| {
                        _ = @errorName(err);
                    };
                    releaseProjectCacheOwner(&cache_owner);
                }
            }
            try output_stage.publish(allocator, artifact_path, out_path, true, false);
            if (cache_key != null) {
                owned.metrics.cache = .{ .kind = BuildCacheKind.build_obj.dirName(), .hit = false, .reason = projectCacheLookupReasonName(cache_miss_reason) };
            } else if (!compile_options.incremental_cache) {
                owned.metrics.cache = .{ .kind = BuildCacheKind.build_obj.dirName(), .hit = false, .reason = ProjectCacheLookupReason.disabled.jsonName() };
            }
            try writeSuccessDiagnostics(stderr, owned.metrics, diagnostics_mode);
            return 0;
        },
    }
}

fn executeBuildWasm(allocator: std.mem.Allocator, source_path: []const u8, out_path: []const u8, target: WasmTarget, debug: bool, optimization: driver.Optimization, compile_options: CompileOptions, stderr: anytype, diagnostics_mode: DiagnosticsMode) !u8 {
    const total_start = if (compile_options.profile) std.time.Instant.now() catch null else null;
    const project_root_owned = compile_options.project_root == null;
    const project_root = compile_options.project_root orelse try projectRootFromSourcePath(allocator, source_path);
    defer if (project_root_owned) allocator.free(project_root);
    var project_context = try loadProjectContext(allocator, project_root, compile_options.package_name);
    defer project_context.deinit(allocator);
    const cache_key: ?ProjectCacheKey = if (compile_options.incremental_cache)
        try computeProjectBuildKeyAndRecordInputs(allocator, &project_context, project_root, source_path, "wasm", target.triple, .build_wasm, debug, optimization == .release_fast, false, target, true, compile_options.offline, compile_options.dce, compile_options.jobs, compile_options.jobs_explicit, &.{})
    else
        null;
    const artifact_path = try intermediateArtifactPath(allocator, out_path);
    defer allocator.free(artifact_path);
    var output_stage = try BuildOutputStage.init(allocator, out_path);
    defer output_stage.deinit(allocator);
    var cache_owner: ?ProjectCacheEntryLock = null;
    var cache_miss_reason: ?ProjectCacheLookupReason = null;
    defer releaseProjectCacheOwner(&cache_owner);

    if (cache_key) |key| {
        const claim: ?ProjectCacheClaimResult = projectCacheClaim(allocator, project_root, .build_wasm, key, &project_context, compile_options, output_stage.artifact_path, output_stage.output_path, stderr, diagnostics_mode) catch |err| blk: {
            _ = @errorName(err);
            cache_miss_reason = .lock_owner_failed;
            break :blk null;
        };
        if (claim) |result| switch (result) {
            .owner => |owner| {
                cache_miss_reason = owner.miss_reason;
                cache_owner = owner.lock;
            },
            .authorization_rejected => return 1,
            .hit => {
                try output_stage.publish(allocator, artifact_path, out_path, true, false);
                if (diagnostics_mode == .json or compile_options.mem_report) {
                    const metrics = CompileMetrics{ .compile_tokens = 0, .instruction_count = 0, .phases = if (compile_options.profile) .{ .load_ns = 0, .setup_ns = 0, .flatten_ns = 0, .verify_ns = 0, .emit_ns = 0, .link_ns = 0, .total_ns = if (total_start) |start| elapsedNs(start) else null } else null, .memory = cacheHitMemoryMetrics(compile_options.mem_report), .cache = .{ .kind = BuildCacheKind.build_wasm.dirName(), .hit = true, .reason = ProjectCacheLookupReason.hit.jsonName() } };
                    try writeSuccessDiagnostics(stderr, metrics, diagnostics_mode);
                }
                return 0;
            },
        };
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
            if (!owned.flat.dynamic_dependencies_cacheable) {
                cache_miss_reason = .bypassed_untrusted;
                releaseProjectCacheOwner(&cache_owner);
            }
            const emit_std_root = try stdRootFromEnv(allocator);
            defer allocator.free(emit_std_root);
            try ensureParentDir(output_stage.artifact_path);
            const emit_start = if (compile_options.profile) std.time.Instant.now() catch null else null;
            try emit_llvm_llvmc.emitLlvmcToFile(allocator, owned.verified, &owned.flat.def_dict, owned.flat.loc_table, source_path, target.size_bits, .{ .debug = debug, .wasm_compat = true, .jobs = compile_options.jobs, .opt_level = emitOptLevel(debug, optimization), .dce = compile_options.dce, .std_root = emit_std_root }, output_stage.artifact_path);
            const emit_ns = if (emit_start) |start| elapsedNs(start) else null;
            recordMetricMemoryAfterEmit(&owned.metrics);
            if (owned.metrics.memory) |memory| try writeMemoryStageSampleForOptions(compile_options, "after_emit", memory.after_emit_rss_bytes, memory.after_verify_rss_bytes);

            const link_start = if (compile_options.profile) std.time.Instant.now() catch null else null;
            driver.compileWasm(allocator, output_stage.artifact_path, output_stage.output_path, .{ .triple = target.triple, .no_entry = target.no_entry }, optimization, debug, stderr) catch |err| switch (err) {
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
            if (cache_key) |key| {
                if (owned.flat.dynamic_dependencies_cacheable and cache_owner != null) {
                    projectCacheStoreWithOwnerMissReason(allocator, project_root, .build_wasm, key, output_stage.artifact_path, output_stage.output_path, owned.flat.dynamic_dependencies, cache_miss_reason) catch |err| {
                        _ = @errorName(err);
                    };
                    releaseProjectCacheOwner(&cache_owner);
                }
            }
            try output_stage.publish(allocator, artifact_path, out_path, true, false);
            if (cache_key != null) {
                owned.metrics.cache = .{ .kind = BuildCacheKind.build_wasm.dirName(), .hit = false, .reason = projectCacheLookupReasonName(cache_miss_reason) };
            } else if (!compile_options.incremental_cache) {
                owned.metrics.cache = .{ .kind = BuildCacheKind.build_wasm.dirName(), .hit = false, .reason = ProjectCacheLookupReason.disabled.jsonName() };
            }
            try writeSuccessDiagnostics(stderr, owned.metrics, diagnostics_mode);
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

fn executeCheck(
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
    if (source_arg == null) return error.MissingSourcePath;
    const source_path = source_arg.?;
    configureCompileDiagnostics(&compile_options, json_mode);

    const total_start = std.time.Instant.now() catch null;
    // Flatten and run the full Referee verifier, then discard codegen state.
    const compiled = try compileSourceForCheck(allocator, source_path, compile_options);
    const wall_ns = if (total_start) |start| elapsedNs(start) else 0;
    switch (compiled) {
        .trap => |report| {
            try printTrapReport(if (json_mode) stdout else stderr, report, if (json_mode) .json else .human);
            return 1;
        },
        .ok => |ok| {
            var owned = ok;
            defer owned.deinit(allocator);
            if (json_mode) {
                try stdout.writeAll("{\"status\":\"ok\",\"metrics\":");
                try writeMetricsJson(stdout, owned.metrics);
                try stdout.print(",\"wall_ms\":{d}", .{wall_ns / 1_000_000});
                try stdout.writeAll("}\n");
            } else {
                try stdout.print("check ok: instructions={d} compile_tokens={d} verdict_cache={s}\n", .{
                    owned.metrics.instruction_count,
                    owned.metrics.compile_tokens,
                    if (owned.metrics.cache) |cache| (if (cache.hit) "hit" else "miss") else "disabled",
                });
            }
            return 0;
        },
    }
}

/// Check-oriented compile: flatten + verdict-only verification.
fn compileSourceForCheck(allocator: std.mem.Allocator, source_path: []const u8, options: CompileOptions) !CheckCompileResult {
    var memory_metrics: ?CompileMemoryMetrics = if (options.mem_report) .{} else null;
    if (memory_metrics) |*memory| memory.recordStart();
    const total_start = if (options.profile) std.time.Instant.now() catch null else null;

    if (std.mem.endsWith(u8, source_path, ".sab")) {
        const load_flat_start = if (options.profile) std.time.Instant.now() catch null else null;
        var flat = try loadSabFlat(allocator, source_path);
        defer flat.deinit(allocator);
        const load_flat_ns = if (load_flat_start) |start| elapsedNs(start) else 0;
        if (memory_metrics) |*memory| memory.recordAfterLoad();

        const prune_start = if (options.profile) std.time.Instant.now() catch null else null;
        try pruneSabFlatToSelectedTests(allocator, &flat, options.sab_selected_test_names);
        const prune_ns = if (prune_start) |start| elapsedNs(start) else 0;
        if (memory_metrics) |*memory| memory.recordAfterFlatten();

        const verify_start = if (options.profile) std.time.Instant.now() catch null else null;
        const verdict = try referee.verifyVerdictOnly(allocator, .{
            .instructions = flat.instructions,
            .const_decls = flat.const_decls,
            .package_grants = &.{},
            .sax_component_name = null,
            .metadata = .{ .predecoded = .{
                .symbol_names = flat.symbols.names.items,
                .function_sigs = flat.function_sigs,
            } },
            .check_exit_leaks = options.sab_selected_test_names.len == 0,
        }, .{
            .jobs = options.jobs,
            .stage_reporter = null,
        });
        const verify_ns = if (verify_start) |start| elapsedNs(start) else 0;
        if (memory_metrics) |*memory| {
            memory.recordAfterVerify();
            memory.recordEnd();
        }
        return switch (verdict) {
            .ok => |ok| .{ .ok = .{ .metrics = computeCheckMetrics(&flat, ok, if (options.profile) .{ .load_ns = load_flat_ns, .setup_ns = 0, .flatten_ns = prune_ns, .verify_ns = verify_ns, .total_ns = if (total_start) |start| elapsedNs(start) else null } else null, memory_metrics) } },
            .trap => |report| {
                var r = report;
                if (r.file == null) setFile(&r, source_path);
                return .{ .trap = r };
            },
        };
    }

    const load_start = if (options.profile) std.time.Instant.now() catch null else null;
    const source = try loadSource(allocator, source_path);
    defer allocator.free(source);
    const load_ns = if (load_start) |start| elapsedNs(start) else 0;
    if (memory_metrics) |*memory| memory.recordAfterLoad();

    const setup_start = if (options.profile) std.time.Instant.now() catch null else null;
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
        },
    };
    const setup_ns = if (setup_start) |start| elapsedNs(start) else 0;
    if (memory_metrics) |*memory| memory.recordAfterSetup();

    const flatten_start = if (options.profile) std.time.Instant.now() catch null else null;
    var flat = flattener.flattenFileWithContextAndPackages(allocator, source_path, source, &error_ctx, resolve_ctx) catch |err| {
        return .{ .trap = trapFromFlattenError(source_path, source, err, flattener.takeErrorSourceLine(&error_ctx)) };
    };
    defer flat.deinit(allocator);
    const flatten_ns = if (flatten_start) |start| elapsedNs(start) else 0;
    if (memory_metrics) |*memory| memory.recordAfterFlatten();

    const verify_start = if (options.profile) std.time.Instant.now() catch null else null;
    const verdict = try referee.verifyVerdictOnly(allocator, .{
        .instructions = flat.instructions,
        .const_decls = flat.const_decls,
        .package_grants = package_grants,
        .sax_component_name = null,
        .metadata = .{ .rebuild = {} },
        .check_exit_leaks = true,
    }, .{
        .jobs = options.jobs,
        .stage_reporter = null,
    });
    const verify_ns = if (verify_start) |start| elapsedNs(start) else 0;
    if (memory_metrics) |*memory| {
        memory.recordAfterVerify();
        memory.recordEnd();
    }
    return switch (verdict) {
        .ok => |ok| .{ .ok = .{ .metrics = computeCheckMetrics(&flat, ok, if (options.profile) .{ .load_ns = load_ns, .setup_ns = setup_ns, .flatten_ns = flatten_ns, .verify_ns = verify_ns, .total_ns = if (total_start) |start| elapsedNs(start) else null } else null, memory_metrics) } },
        .trap => |report| {
            var r = report;
            if (r.file == null) setFile(&r, source_path);
            return .{ .trap = r };
        },
    };
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
    const source_path = if (source_arg) |path| path else try projectSourcePath(allocator, project_root, compile_options.package_name);
    defer if (source_arg == null) allocator.free(source_path);
    configureCompileDiagnostics(&compile_options, json_mode);

    const compiled = try compileSource(allocator, source_path, compile_options);
    switch (compiled) {
        .trap => |report| {
            try printTrapReport(stderr, report, if (json_mode) .json else .human);
            return 1;
        },
        .ok => |ok| {
            var owned = ok;
            defer owned.deinit(allocator);

            var resolution = if (compile_options.project_root) |root|
                try pkg_workspace.resolveFromRootPath(allocator, root, .{ .request = compile_options.package_name })
            else
                try resolveProjectFromSourcePath(allocator, source_path, compile_options.package_name);
            defer resolution.deinit(allocator);

            const resolved_project_root = resolution.workspace_root;
            const project_manifest = resolution.effective_manifest;

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
    const source_path = if (source_arg) |path| path else try projectSourcePath(allocator, project_root, compile_options.package_name);
    defer if (source_arg == null) allocator.free(source_path);
    configureCompileDiagnostics(&compile_options, json_mode);

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

const affected_module_context_key = "\x00sa-affected-module-context-v2";

fn affectedBaselineNamespace(
    allocator: std.mem.Allocator,
    source_path: []const u8,
    compile_options: CompileOptions,
    test_options: TestCommandOptions,
) ![64]u8 {
    const canonical_source = std.fs.cwd().realpathAlloc(allocator, source_path) catch try allocator.dupe(u8, source_path);
    defer allocator.free(canonical_source);

    var hasher = std.crypto.hash.sha2.Sha256.init(.{});
    cacheBytes(&hasher, "sa-affected-baseline-v2");
    cacheBytes(&hasher, cacheCompilerVersion());
    cacheBytes(&hasher, canonical_source);
    if (compile_options.project_root) |root| {
        const canonical_root = std.fs.cwd().realpathAlloc(allocator, root) catch try allocator.dupe(u8, root);
        defer allocator.free(canonical_root);
        cacheBytes(&hasher, canonical_root);
    } else {
        cacheBytes(&hasher, "<project-root-from-source>");
    }
    cacheBytes(&hasher, compile_options.package_name orelse "");
    cacheBytes(&hasher, compile_options.permission_set orelse "");
    cacheBytes(&hasher, compile_options.dce.name());
    cacheBool(&hasher, compile_options.offline);
    cacheBool(&hasher, compile_options.ci);
    cacheBool(&hasher, compile_options.allow_unaudited_risks);
    cacheBool(&hasher, compile_options.auto_approve_requested);
    cacheBool(&hasher, compile_options.allow_env_requested);
    cacheBool(&hasher, compile_options.allow_net_requested);
    cacheBool(&hasher, compile_options.allow_read_requested);
    cacheBool(&hasher, compile_options.allow_write_requested);
    cacheBool(&hasher, compile_options.allow_run_requested);

    cacheBytes(&hasher, "include");
    cacheU64(&hasher, @intCast(test_options.selection.include_filters.len));
    for (test_options.selection.include_filters) |filter| cacheBytes(&hasher, filter);
    cacheBytes(&hasher, "skip");
    cacheU64(&hasher, @intCast(test_options.selection.skip_filters.len));
    for (test_options.selection.skip_filters) |filter| cacheBytes(&hasher, filter);
    cacheBool(&hasher, test_options.selection.exact);
    cacheU64(&hasher, @intFromEnum(test_options.selection.ignored));
    cacheBool(&hasher, test_options.trace_panic);
    cacheBool(&hasher, test_options.list);
    cacheBool(&hasher, test_options.compile_only);

    var digest: [32]u8 = undefined;
    hasher.final(&digest);
    return std.fmt.bytesToHex(digest, .lower);
}

fn addAffectedModuleContextHash(
    allocator: std.mem.Allocator,
    flat: *const flattener.FlattenResult,
    function_bodies: *affected_tests.FunctionHashMap,
) !void {
    var hasher = std.crypto.hash.sha2.Sha256.init(.{});
    cacheBytes(&hasher, "sa-affected-module-context-v2");
    for (flat.const_decls) |decl| cacheBytes(&hasher, decl.raw_text);
    for (flat.instructions) |item| {
        switch (item.kind) {
            .func_decl, .ffi_wrapper_decl, .extern_decl, .export_decl, .test_decl => break,
            else => cacheBytes(&hasher, item.raw_text),
        }
    }
    var digest: [32]u8 = undefined;
    hasher.final(&digest);
    const owned_key = try allocator.dupe(u8, affected_module_context_key);
    errdefer allocator.free(owned_key);
    try function_bodies.put(owned_key, digest);
}

fn affectedGraphHasVtable(flat: *const flattener.FlattenResult) bool {
    for (flat.const_decls) |decl| {
        switch (decl.value) {
            .vtable => return true,
            else => {},
        }
    }
    return false;
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
    if (!test_options.affected) return executeTestInner(allocator, source_path, compile_options, test_options, stdout, stderr, diagnostics_mode);

    // Call-graph selective execution. The legacy whole-source pass cache is
    // intentionally not consulted: its key omits project, full selection,
    // imports, dynamic dependencies, permissions, and runner semantics.
    // Compile once to inspect functions,
    // compute changed set vs baseline, restrict selection.include_filters to
    // impacted tests, then run. On first baseline, run all selected tests.
    const compiled = try compileSource(allocator, source_path, compile_options);
    switch (compiled) {
        .trap => |report| {
            try printTrapReport(stderr, report, diagnostics_mode);
            return 1;
        },
        .ok => |ok| {
            var owned = ok;
            defer owned.deinit(allocator);

            var function_bodies = try collectFunctionBodyHashes(allocator, &owned.verified);
            defer freeFunctionBodyHashes(allocator, &function_bodies);
            try addAffectedModuleContextHash(allocator, &owned.flat, &function_bodies);

            const namespace = try affectedBaselineNamespace(allocator, source_path, compile_options, test_options);

            var changed = std.ArrayList([]const u8).init(allocator);
            defer changed.deinit();
            const had_baseline = affected_tests.hasFunctionBaseline(&namespace);
            var module_context_changed = !had_baseline;
            var it = function_bodies.iterator();
            while (it.next()) |entry| {
                const entry_changed = !had_baseline or affected_tests.functionChanged(&namespace, entry.key_ptr.*, entry.value_ptr.*);
                if (std.mem.eql(u8, entry.key_ptr.*, affected_module_context_key)) {
                    module_context_changed = entry_changed;
                } else if (entry_changed) {
                    try changed.append(entry.key_ptr.*);
                }
            }
            const deleted_function = had_baseline and affected_tests.baselineHasDeletedFunctions(&namespace, &function_bodies);

            // Build call edges from annotated stream.
            var callers = std.ArrayList([]const u8).init(allocator);
            defer callers.deinit();
            var callees = std.ArrayList([]const u8).init(allocator);
            defer {
                for (callees.items) |c| allocator.free(c);
                callees.deinit();
            }
            const call_graph_complete = try collectCallEdges(allocator, &owned.verified, &callers, &callees);
            const force_full_selection = module_context_changed or deleted_function or !call_graph_complete or affectedGraphHasVtable(&owned.flat);

            var rev = try affected_tests.buildReverseCallMap(allocator, callers.items, callees.items);
            defer {
                var rit = rev.iterator();
                while (rit.next()) |e| e.value_ptr.deinit();
                rev.deinit();
            }

            // Normalize changed names for reverse-graph lookup.
            var changed_norm = std.ArrayList([]const u8).init(allocator);
            defer changed_norm.deinit();
            for (changed.items) |c| try changed_norm.append(normalizeFnName(c));
            var impacted = try affected_tests.impactedFunctions(allocator, changed_norm.items, &rev);
            defer impacted.deinit();

            // Restrict only within the user's original selection. If the graph
            // is incomplete, leave that selection untouched and run it fully.
            var discovered_tests = try test_meta.collect(allocator, owned.verified.function_sigs);
            defer discovered_tests.deinit(allocator);
            var selected_names = std.ArrayList([]const u8).init(allocator);
            defer {
                for (selected_names.items) |n| allocator.free(n);
                selected_names.deinit();
            }
            var total_tests: usize = 0;
            for (discovered_tests.tests) |test_case| {
                if (!test_options.selection.shouldRun(test_case)) continue;
                total_tests += 1;
                const display = test_case.displayName();
                const norm = normalizeFnName(test_case.selectorName());
                const keep = if (!had_baseline or force_full_selection)
                    true
                else
                    impacted.contains(norm) or impacted.contains(display);
                if (keep) try selected_names.append(try allocator.dupe(u8, display));
            }

            if (diagnostics_mode == .json) {
                try stdout.writeAll("{\"status\":\"ok\",\"affected\":{");
                try stdout.print("\"had_baseline\":{s},\"changed_functions\":{d},\"selected_tests\":{d},\"total_tests\":{d},\"graph_complete\":{s},\"full_fallback\":{s}", .{
                    if (had_baseline) "true" else "false",
                    changed.items.len,
                    selected_names.items.len,
                    total_tests,
                    if (call_graph_complete) "true" else "false",
                    if (force_full_selection) "true" else "false",
                });
                try stdout.writeAll("}}\n");
            } else {
                try stdout.print(
                    "affected: baseline={s} changed_fns={d} selected_tests={d}/{d} graph={s} fallback={s}\n",
                    .{
                        if (had_baseline) "yes" else "no",
                        changed.items.len,
                        selected_names.items.len,
                        total_tests,
                        if (call_graph_complete) "complete" else "incomplete",
                        if (force_full_selection) "full" else "none",
                    },
                );
            }

            // Restrict filters to selected test names when we have a baseline.
            var effective = test_options;
            var owned_filters: []const []const u8 = &.{};
            defer if (owned_filters.len != 0) {
                for (owned_filters) |f| allocator.free(f);
                allocator.free(owned_filters);
            };
            if (had_baseline and !force_full_selection and selected_names.items.len > 0) {
                var filters = try allocator.alloc([]const u8, selected_names.items.len);
                for (selected_names.items, 0..) |n, idx| filters[idx] = try allocator.dupe(u8, n);
                owned_filters = filters;
                effective.selection.include_filters = owned_filters;
                effective.selection.exact = true;
            }

            const code = try executeTestInner(allocator, source_path, compile_options, effective, stdout, stderr, diagnostics_mode);
            if (code == 0 and !test_options.list and !test_options.compile_only) {
                try affected_tests.replaceFunctionBaseline(&namespace, &function_bodies);
            }
            return code;
        },
    }
}

const FunctionBodyHashMap = affected_tests.FunctionHashMap;

fn collectFunctionBodyHashes(allocator: std.mem.Allocator, verified: *const referee.VerifyOk) !FunctionBodyHashMap {
    var map = FunctionBodyHashMap.init(allocator);
    errdefer freeFunctionBodyHashes(allocator, &map);
    var sig_index: usize = 0;
    var idx: usize = 0;
    while (idx < verified.annotated.len) : (idx += 1) {
        const item = verified.annotated[idx].base;
        switch (item.kind) {
            .func_decl, .ffi_wrapper_decl, .extern_decl, .export_decl, .test_decl => {
                if (sig_index >= verified.function_sigs.len) break;
                const fs = verified.function_sigs[sig_index];
                sig_index += 1;
                var end = idx + 1;
                while (end < verified.annotated.len and switch (verified.annotated[end].base.kind) {
                    .func_decl, .ffi_wrapper_decl, .extern_decl, .export_decl, .test_decl => false,
                    else => true,
                }) : (end += 1) {}
                var lines = std.ArrayList([]const u8).init(allocator);
                defer lines.deinit();
                var j = idx;
                while (j < end) : (j += 1) try lines.append(verified.annotated[j].base.raw_text);
                const digest = affected_tests.hashFunctionBody(fs.name, lines.items);
                const key = try allocator.dupe(u8, fs.name);
                try map.put(key, digest);
                idx = end - 1;
            },
            else => {},
        }
    }
    return map;
}

fn freeFunctionBodyHashes(allocator: std.mem.Allocator, map: *FunctionBodyHashMap) void {
    var it = map.keyIterator();
    while (it.next()) |k| allocator.free(k.*);
    map.deinit();
}

fn normalizeFnName(name: []const u8) []const u8 {
    var s = name;
    if (s.len > 0 and s[0] == '@') s = s[1..];
    // Strip signature tail: `@foo() -> i32:` / `foo():` -> foo / display text
    if (std.mem.indexOfScalar(u8, s, '(')) |paren| s = s[0..paren];
    if (std.mem.indexOfScalar(u8, s, '"')) |q1| {
        if (std.mem.indexOfScalar(u8, s[q1 + 1 ..], '"')) |q2| {
            return s[q1 + 1 .. q1 + 1 + q2];
        }
    }
    return s;
}

fn collectCallEdges(
    allocator: std.mem.Allocator,
    verified: *const referee.VerifyOk,
    callers: *std.ArrayList([]const u8),
    callees: *std.ArrayList([]const u8),
) !bool {
    var known_functions = std.StringHashMap(void).init(allocator);
    defer known_functions.deinit();
    for (verified.function_sigs) |sig_item| {
        try known_functions.put(normalizeFnName(sig_item.name), {});
    }

    var complete = true;
    var current_fn: ?[]const u8 = null;
    var sig_index: usize = 0;
    for (verified.annotated) |item| {
        switch (item.base.kind) {
            .func_decl, .ffi_wrapper_decl, .extern_decl, .export_decl, .test_decl => {
                if (sig_index >= verified.function_sigs.len) break;
                current_fn = verified.function_sigs[sig_index].name;
                sig_index += 1;
            },
            .call, .call_indirect => {
                const caller = current_fn orelse continue;
                var parsed = referee_call.parseCall(allocator, item.base.raw_text) catch {
                    complete = false;
                    continue;
                };
                defer parsed.deinit(allocator);
                if (item.base.kind == .call_indirect or parsed.is_indirect) {
                    complete = false;
                    continue;
                }
                const callee = normalizeFnName(parsed.callee);
                if (!known_functions.contains(callee)) {
                    complete = false;
                    continue;
                }
                try callers.append(normalizeFnName(caller));
                const callee_owned = try allocator.dupe(u8, callee);
                try callees.append(callee_owned);
            },
            else => {
                // A function operand outside a resolved direct call is an
                // address-taken edge. The current reverse graph has no sound
                // target set for it, so affected selection must fall back.
                for (item.base.operands) |operand| {
                    switch (operand) {
                        .func => complete = false,
                        else => {},
                    }
                }
            },
        }
    }
    return complete;
}

fn executeTestInner(
    allocator: std.mem.Allocator,
    source_path: []const u8,
    compile_options: CompileOptions,
    test_options: TestCommandOptions,
    stdout: anytype,
    stderr: anytype,
    diagnostics_mode: DiagnosticsMode,
) !u8 {
    if (test_options.list and std.mem.endsWith(u8, source_path, ".sab")) {
        var test_list = try collectSabTestListFast(allocator, source_path);
        defer test_list.deinit(allocator);
        try test_formatter.writeList(stdout, test_list.tests, test_options.selection);
        return 0;
    }

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
    var project_context = try loadProjectContext(allocator, project_root, compile_options.package_name);
    defer project_context.deinit(allocator);
    const test_total_start = if (compile_options.profile) std.time.Instant.now() catch null else null;
    const cache_key: ?ProjectCacheKey = if (compile_options.incremental_cache)
        try computeProjectBuildKeyAndRecordInputs(allocator, &project_context, project_root, source_path, "test", "", .test_cache, false, false, false, null, true, compile_options.offline, compile_options.dce, compile_options.jobs, compile_options.jobs_explicit, &.{std_archive_path})
    else
        null;
    var cache_owner: ?ProjectCacheEntryLock = null;
    var cache_miss_reason: ?ProjectCacheLookupReason = null;
    defer releaseProjectCacheOwner(&cache_owner);

    if (cache_key) |key| {
        const claim: ?ProjectCacheTestClaimResult = projectCacheTestClaim(allocator, project_root, key, &project_context, compile_options, artifact_full_path, exe_full_path, stderr, diagnostics_mode) catch |err| blk: {
            _ = @errorName(err);
            cache_miss_reason = .lock_owner_failed;
            break :blk null;
        };
        if (claim) |result| switch (result) {
            .owner => |owner| {
                cache_miss_reason = owner.miss_reason;
                cache_owner = owner.lock;
                if (test_options.list or hasExplicitTestSelection(test_options.selection)) {
                    cache_miss_reason = .selection_changed;
                    releaseProjectCacheOwner(&cache_owner);
                }
            },
            .authorization_rejected => return 1,
            .hit => |hit_test_list| {
                var cached_test_list = hit_test_list;
                makeExecutable(exe_full_path) catch |err| {
                    cached_test_list.deinit(allocator);
                    return err;
                };
                if (test_options.list) {
                    defer cached_test_list.deinit(allocator);
                    const metrics = CompileMetrics{ .compile_tokens = 0, .instruction_count = 0, .phases = if (compile_options.profile) .{ .load_ns = 0, .setup_ns = 0, .flatten_ns = 0, .verify_ns = 0, .emit_ns = 0, .link_ns = 0, .total_ns = if (test_total_start) |start| elapsedNs(start) else null } else null, .memory = cacheHitMemoryMetrics(compile_options.mem_report), .cache = .{ .kind = BuildCacheKind.test_cache.dirName(), .hit = true, .reason = ProjectCacheLookupReason.hit.jsonName() } };
                    if (diagnostics_mode == .json or compile_options.mem_report) {
                        try writeSuccessDiagnostics(stderr, metrics, diagnostics_mode);
                    }
                    try test_formatter.writeList(stdout, cached_test_list.tests, test_options.selection);
                    return 0;
                }
                if (test_options.compile_only) {
                    defer cached_test_list.deinit(allocator);
                    if (diagnostics_mode == .json or compile_options.mem_report) {
                        const metrics = CompileMetrics{ .compile_tokens = 0, .instruction_count = 0, .phases = if (compile_options.profile) .{ .load_ns = 0, .setup_ns = 0, .flatten_ns = 0, .verify_ns = 0, .emit_ns = 0, .link_ns = 0, .total_ns = if (test_total_start) |start| elapsedNs(start) else null } else null, .memory = cacheHitMemoryMetrics(compile_options.mem_report), .cache = .{ .kind = BuildCacheKind.test_cache.dirName(), .hit = true, .reason = ProjectCacheLookupReason.hit.jsonName() } };
                        try writeSuccessDiagnostics(stderr, metrics, diagnostics_mode);
                    }
                    try stdout.print(
                        "compiled {d} selected tests ({d} discovered)\n",
                        .{
                            test_options.selection.countSelected(cached_test_list.tests),
                            cached_test_list.tests.len,
                        },
                    );
                    return 0;
                }
                const metrics = CompileMetrics{ .compile_tokens = 0, .instruction_count = 0, .phases = if (compile_options.profile) .{ .load_ns = 0, .setup_ns = 0, .flatten_ns = 0, .verify_ns = 0, .emit_ns = 0, .link_ns = 0, .total_ns = if (test_total_start) |start| elapsedNs(start) else null } else null, .memory = cacheHitMemoryMetrics(compile_options.mem_report), .cache = .{ .kind = BuildCacheKind.test_cache.dirName(), .hit = true, .reason = ProjectCacheLookupReason.hit.jsonName() } };
                const run_code = try test_runner.run(
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
                if (run_code == 0 and (diagnostics_mode == .json or compile_options.mem_report)) {
                    try writeSuccessDiagnostics(stderr, metrics, diagnostics_mode);
                }
                return run_code;
            },
        };
    }

    var effective_compile_options = compile_options;
    var sab_selected_test_list: ?test_meta.TestList = null;
    defer if (sab_selected_test_list) |*list| list.deinit(allocator);
    var selected_test_names: []const []const u8 = &.{};
    defer if (selected_test_names.len != 0) allocator.free(selected_test_names);

    if (std.mem.endsWith(u8, source_path, ".sab") and hasExplicitTestSelection(test_options.selection)) {
        sab_selected_test_list = try collectSabTestListFast(allocator, source_path);
        selected_test_names = try selectedTestNamesFromList(allocator, sab_selected_test_list.?, test_options.selection);
        effective_compile_options.sab_selected_test_names = selected_test_names;
    }

    const compile_start = if (compile_options.profile) std.time.Instant.now() catch null else null;
    const compiled = try compileSource(allocator, source_path, effective_compile_options);
    const compile_ns = if (compile_start) |start| elapsedNs(start) else null;
    switch (compiled) {
        .trap => |report| {
            try printTrapReport(stderr, report, diagnostics_mode);
            return 1;
        },
        .ok => |ok| {
            var owned = ok;
            defer owned.deinit(allocator);
            if (!owned.flat.dynamic_dependencies_cacheable) {
                cache_miss_reason = .bypassed_untrusted;
                releaseProjectCacheOwner(&cache_owner);
            }

            var compiled_test_list: ?test_meta.TestList = null;
            defer if (compiled_test_list) |*list| list.deinit(allocator);
            if (sab_selected_test_list == null) {
                compiled_test_list = try test_meta.collect(allocator, owned.verified.function_sigs);
            }
            const test_list = if (sab_selected_test_list) |*list| list else &compiled_test_list.?;
            if (test_options.list) {
                if (cache_key != null) {
                    owned.metrics.cache = .{ .kind = BuildCacheKind.test_cache.dirName(), .hit = false, .reason = projectCacheLookupReasonName(cache_miss_reason) };
                } else if (!compile_options.incremental_cache) {
                    owned.metrics.cache = .{ .kind = BuildCacheKind.test_cache.dirName(), .hit = false, .reason = ProjectCacheLookupReason.disabled.jsonName() };
                }
                try writeSuccessDiagnostics(stderr, owned.metrics, diagnostics_mode);
                try test_formatter.writeList(stdout, test_list.tests, test_options.selection);
                return 0;
            }

            const has_explicit_test_selection = hasExplicitTestSelection(test_options.selection);
            if (selected_test_names.len == 0 and has_explicit_test_selection) {
                selected_test_names = try selectedTestNamesFromList(allocator, test_list.*, test_options.selection);
            }

            var link_inputs = std.ArrayList([]const u8).init(allocator);
            defer link_inputs.deinit();
            var owned_link_inputs = std.ArrayList([]const u8).init(allocator);
            defer {
                for (owned_link_inputs.items) |arg| allocator.free(arg);
                owned_link_inputs.deinit();
            }
            try appendNativePluginLinkInputs(allocator, &link_inputs, &owned_link_inputs, &owned.verified);
            if (link_inputs.items.len != 0) {
                cache_miss_reason = .bypassed_untrusted;
                releaseProjectCacheOwner(&cache_owner);
            }

            const emit_std_root = try stdRootFromEnv(allocator);
            defer allocator.free(emit_std_root);
            const emit_start = if (compile_options.profile) std.time.Instant.now() catch null else null;
            try emit_llvm_llvmc.emitLlvmcToFile(allocator, owned.verified, &owned.flat.def_dict, owned.flat.loc_table, source_path, nativeSizeBits(), .{ .jobs = compile_options.jobs, .test_mode = true, .dce = compile_options.dce, .std_root = emit_std_root, .selected_test_names = selected_test_names }, artifact_full_path);
            const emit_ns = if (emit_start) |start| elapsedNs(start) else null;

            const fast_sab_compile_only = test_options.compile_only and std.mem.endsWith(u8, source_path, ".sab") and has_explicit_test_selection;
            if (fast_sab_compile_only) {
                if (compile_options.profile and diagnostics_mode == .human) {
                    try stderr.print(
                        "profile test compile={d:.3}ms emit={d:.3}ms link=0.000ms total={d:.3}ms\n",
                        .{
                            @as(f64, @floatFromInt(compile_ns orelse 0)) / 1_000_000.0,
                            @as(f64, @floatFromInt(emit_ns orelse 0)) / 1_000_000.0,
                            @as(f64, @floatFromInt(if (test_total_start) |start| elapsedNs(start) else 0)) / 1_000_000.0,
                        },
                    );
                }
                try stdout.print(
                    "compiled {d} selected tests ({d} discovered)\n",
                    .{
                        test_options.selection.countSelected(test_list.tests),
                        test_list.tests.len,
                    },
                );
                return 0;
            }

            const link_start = if (compile_options.profile) std.time.Instant.now() catch null else null;
            driver.compileExe(allocator, artifact_full_path, exe_full_path, .release_small, std_archive_path, link_inputs.items, false, stderr) catch |err| switch (err) {
                error.ChildProcessFailed => return 1,
                else => return err,
            };
            const link_ns = if (link_start) |start| elapsedNs(start) else null;
            finishProfileMetrics(&owned.metrics, emit_ns, link_ns, if (test_total_start) |start| elapsedNs(start) else null);
            if (compile_options.profile and diagnostics_mode == .human) {
                try stderr.print(
                    "profile test compile={d:.3}ms emit={d:.3}ms link={d:.3}ms total={d:.3}ms\n",
                    .{
                        @as(f64, @floatFromInt(compile_ns orelse 0)) / 1_000_000.0,
                        @as(f64, @floatFromInt(emit_ns orelse 0)) / 1_000_000.0,
                        @as(f64, @floatFromInt(link_ns orelse 0)) / 1_000_000.0,
                        @as(f64, @floatFromInt(if (test_total_start) |start| elapsedNs(start) else 0)) / 1_000_000.0,
                    },
                );
            }

            if (cache_key) |key| {
                if (!has_explicit_test_selection and link_inputs.items.len == 0 and owned.flat.dynamic_dependencies_cacheable and cache_owner != null) {
                    projectCacheStoreTestWithOwnerMissReason(allocator, project_root, key, artifact_full_path, exe_full_path, test_list.*, owned.flat.dynamic_dependencies, cache_miss_reason) catch |err| {
                        _ = @errorName(err);
                    };
                    releaseProjectCacheOwner(&cache_owner);
                }
            }

            if (cache_key != null) {
                owned.metrics.cache = .{ .kind = BuildCacheKind.test_cache.dirName(), .hit = false, .reason = projectCacheLookupReasonName(cache_miss_reason) };
            } else if (!compile_options.incremental_cache) {
                owned.metrics.cache = .{ .kind = BuildCacheKind.test_cache.dirName(), .hit = false, .reason = ProjectCacheLookupReason.disabled.jsonName() };
            }

            if (test_options.compile_only) {
                try writeSuccessDiagnostics(stderr, owned.metrics, diagnostics_mode);
                try stdout.print(
                    "compiled {d} selected tests ({d} discovered)\n",
                    .{
                        test_options.selection.countSelected(test_list.tests),
                        test_list.tests.len,
                    },
                );
                return 0;
            }

            if (sab_selected_test_list) |list| {
                var run_list = list;
                sab_selected_test_list = null;
                const run_code = try test_runner.run(
                    allocator,
                    exe_full_path,
                    tmp.dir,
                    &run_list,
                    test_options.selection,
                    test_options.trace_panic,
                    compile_options.jobs,
                    stdout.any(),
                    stderr.any(),
                );
                if (run_code == 0 and (diagnostics_mode == .json or compile_options.mem_report)) {
                    try writeSuccessDiagnostics(stderr, owned.metrics, diagnostics_mode);
                }
                return run_code;
            } else {
                var run_list = compiled_test_list.?;
                compiled_test_list = null;
                const run_code = try test_runner.run(
                    allocator,
                    exe_full_path,
                    tmp.dir,
                    &run_list,
                    test_options.selection,
                    test_options.trace_panic,
                    compile_options.jobs,
                    stdout.any(),
                    stderr.any(),
                );
                if (run_code == 0 and (diagnostics_mode == .json or compile_options.mem_report)) {
                    try writeSuccessDiagnostics(stderr, owned.metrics, diagnostics_mode);
                }
                return run_code;
            }
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
            if (try executePkgCommandFallback(allocator, args, stdout, stderr)) |code| return code;
            var plugin_auth = try buildPluginRuntimeAuthorization(allocator, args);
            defer plugin_auth.deinit(allocator);
            var plugin_runtime = try plugins.Runtime.initFromEnvWithAuthorization(allocator, plugin_auth.input);
            defer plugin_runtime.deinit();
            if (try plugin_runtime.dispatchCommand(args, stdout, stderr, json_mode)) |code| return code;
            return error.UnknownCommand;
        },
        .cache => return try executeCacheCommand(allocator, args[2..], stdout, json_mode),
        .audit => return error.UnknownCommand,
        .check => {
            return try executeCheck(allocator, args[2..], stdout, stderr, json_mode, exec_options);
        },
        .explain => return try explainCommand(stdout, args, json_mode),
        .fix => return try fixCommand(stdout, args, json_mode),
        .skills => return try skillsCommand(allocator, stdout, json_mode),
        .daemon => return try daemonCommand(allocator, args[2..], stdout, stderr),
        .init => return try executeInit(allocator, args[2..], stdout),
        .install => return try executeInstall(allocator, args[2..], stdout),
        .plugin => return try executePluginCommand(allocator, args[2..], stdout, stderr),
        .build => {
            var compile_options = newCompileOptions(exec_options, stderr.any());
            var source_path: ?[]const u8 = null;
            var out_path: ?[]const u8 = null;
            var debug = false;
            var optimization: driver.Optimization = .release_small;
            var i: usize = 2;
            while (i < args.len) : (i += 1) {
                if (try consumeCompileOption(args[i], args, &i, &compile_options)) continue;
                if (source_path == null) {
                    source_path = args[i];
                    continue;
                }
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
            const project_root = try projectRootDir(allocator);
            defer allocator.free(project_root);
            const owned_source_path = if (source_path) |_| null else try projectSourcePath(allocator, project_root, compile_options.package_name);
            defer if (owned_source_path) |path| allocator.free(path);
            const final_source_path = source_path orelse owned_source_path.?;
            const owned_out = if (out_path) |p| p else try deriveOutputPath(allocator, final_source_path, "");
            defer if (out_path == null) allocator.free(owned_out);
            configureCompileDiagnostics(&compile_options, json_mode);
            return try executeBuildExe(allocator, final_source_path, if (out_path) |p| p else owned_out, debug, optimization, compile_options, stderr, if (json_mode) .json else .human);
        },
        .build_workspace => {
            var compile_options = newCompileOptions(exec_options, stderr.any());
            var out_path: ?[]const u8 = null;
            var debug = false;
            var optimization: driver.Optimization = .release_small;
            var i: usize = 2;
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
            const project_root = try projectRootDir(allocator);
            defer allocator.free(project_root);
            const final_source_path = try projectSourcePath(allocator, project_root, compile_options.package_name);
            defer allocator.free(final_source_path);
            const owned_out = if (out_path) |p| p else try deriveOutputPath(allocator, final_source_path, "");
            defer if (out_path == null) allocator.free(owned_out);
            configureCompileDiagnostics(&compile_options, json_mode);
            return try executeBuildExe(allocator, final_source_path, if (out_path) |p| p else owned_out, debug, optimization, compile_options, stderr, if (json_mode) .json else .human);
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
            configureCompileDiagnostics(&compile_options, json_mode);
            return try executeRun(allocator, source, compile_options, runtime_args.items, stdout, stderr, if (json_mode) .json else .human);
        },
        .build_exe => {
            var compile_options = newCompileOptions(exec_options, stderr.any());
            var source_path: ?[]const u8 = null;
            var out_path: ?[]const u8 = null;
            var debug = false;
            var optimization: driver.Optimization = .release_small;
            var i: usize = 2;
            while (i < args.len) : (i += 1) {
                if (try consumeCompileOption(args[i], args, &i, &compile_options)) continue;
                if (source_path == null) {
                    source_path = args[i];
                    continue;
                }
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
            const project_root = try projectRootDir(allocator);
            defer allocator.free(project_root);
            const owned_source_path = if (source_path) |_| null else try projectSourcePath(allocator, project_root, compile_options.package_name);
            defer if (owned_source_path) |path| allocator.free(path);
            const final_source_path = source_path orelse owned_source_path.?;
            const owned_out = if (out_path) |p| p else try deriveOutputPath(allocator, final_source_path, "");
            defer if (out_path == null) allocator.free(owned_out);
            configureCompileDiagnostics(&compile_options, json_mode);
            return try executeBuildExe(allocator, final_source_path, if (out_path) |p| p else owned_out, debug, optimization, compile_options, stderr, if (json_mode) .json else .human);
        },
        .build_obj => {
            var compile_options = newCompileOptions(exec_options, stderr.any());
            var source_path: ?[]const u8 = null;
            var out_path: ?[]const u8 = null;
            var debug = false;
            var optimization: driver.Optimization = .release_small;
            var incremental = false;
            var i: usize = 2;
            while (i < args.len) : (i += 1) {
                if (try consumeCompileOption(args[i], args, &i, &compile_options)) continue;
                if (source_path == null) {
                    source_path = args[i];
                    continue;
                }
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
            const project_root = try projectRootDir(allocator);
            defer allocator.free(project_root);
            const owned_source_path = if (source_path) |_| null else try projectSourcePath(allocator, project_root, compile_options.package_name);
            defer if (owned_source_path) |path| allocator.free(path);
            const final_source_path = source_path orelse owned_source_path.?;
            const owned_out = if (out_path) |p| p else try deriveOutputPath(allocator, final_source_path, ".o");
            defer if (out_path == null) allocator.free(owned_out);
            configureCompileDiagnostics(&compile_options, json_mode);
            return try executeBuildObj(allocator, final_source_path, if (out_path) |p| p else owned_out, debug, optimization, incremental, compile_options, stderr, if (json_mode) .json else .human);
        },
        .build_wasm => {
            var compile_options = newCompileOptions(exec_options, stderr.any());
            var source_path: ?[]const u8 = null;
            var out_path: ?[]const u8 = null;
            var target: WasmTarget = .{ .triple = "wasm32-wasi", .no_entry = false, .size_bits = 32 };
            var debug = false;
            var optimization: driver.Optimization = .release_small;
            var i: usize = 2;
            while (i < args.len) : (i += 1) {
                if (try consumeCompileOption(args[i], args, &i, &compile_options)) continue;
                if (source_path == null) {
                    source_path = args[i];
                    continue;
                }
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
            const project_root = try projectRootDir(allocator);
            defer allocator.free(project_root);
            const owned_source_path = if (source_path) |_| null else try projectSourcePath(allocator, project_root, compile_options.package_name);
            defer if (owned_source_path) |path| allocator.free(path);
            const final_source_path = source_path orelse owned_source_path.?;
            const owned_out = if (out_path) |p| p else try deriveOutputPath(allocator, final_source_path, ".wasm");
            defer if (out_path == null) allocator.free(owned_out);
            configureCompileDiagnostics(&compile_options, json_mode);
            return try executeBuildWasm(allocator, final_source_path, if (out_path) |p| p else owned_out, target, debug, optimization, compile_options, stderr, if (json_mode) .json else .human);
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
            var compile_options = newCompileOptions(exec_options, stderr.any());
            var source_path: ?[]const u8 = null;
            var include_filters = std.ArrayList([]const u8).init(allocator);
            defer include_filters.deinit();
            var skip_filters = std.ArrayList([]const u8).init(allocator);
            defer skip_filters.deinit();
            var exact = false;
            var run_ignored = test_meta.RunIgnored.normal;
            var list_tests = false;
            var compile_only = false;
            var trace_panic = false;
            var affected_flag = false;
            var i: usize = 2;
            while (i < args.len) : (i += 1) {
                if (try consumeCompileOption(args[i], args, &i, &compile_options)) continue;
                if (source_path == null) {
                    source_path = args[i];
                    continue;
                }
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
                if (std.mem.eql(u8, args[i], "--affected")) {
                    affected_flag = true;
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
            const project_root = try projectRootDir(allocator);
            defer allocator.free(project_root);
            const owned_source_path = if (source_path) |_| null else try projectSourcePath(allocator, project_root, compile_options.package_name);
            defer if (owned_source_path) |path| allocator.free(path);
            const final_source_path = source_path orelse owned_source_path.?;
            configureCompileDiagnostics(&compile_options, json_mode);
            return try executeTest(allocator, final_source_path, compile_options, .{
                .selection = selection,
                .list = list_tests,
                .compile_only = compile_only,
                .trace_panic = trace_panic,
                .affected = affected_flag,
            }, stdout, stderr, if (json_mode) .json else .human);
        },
    }
}

pub fn executeWithWriters(allocator: std.mem.Allocator, argv: []const []const u8, stdout: anytype, stderr: anytype) !u8 {
    return executeWithWritersAndOptions(allocator, argv, stdout, stderr, .{});
}

pub fn execute(allocator: std.mem.Allocator, argv: []const []const u8) !u8 {
    if (try daemon_client.tryDaemonClient(allocator, argv, std.io.getStdOut().writer())) |code| return code;
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

test "build-workspace command is recognized in help" {
    var list = std.ArrayList(u8).init(std.testing.allocator);
    defer list.deinit();

    try printUsage(list.writer());
    try std.testing.expect(std.mem.indexOf(u8, list.items, "build-workspace") != null);

    list.clearRetainingCapacity();
    try printCommandHelp(list.writer(), .build_workspace, &.{});
    try std.testing.expect(std.mem.indexOf(u8, list.items, "usage: sa build-workspace [options]") != null);
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
    _ = try hashResolvedSourceTree(std.testing.allocator, &first_hasher, null, &.{}, &.{}, project_root, std_root, false, "main.sa");
    var first_digest: [32]u8 = undefined;
    first_hasher.final(&first_digest);
    try std.testing.expectEqual(@as(usize, 1), test_source_tree_load_count);

    const resolve_ctx = flattener.ResolveContext{ .options = .{ .project_root = project_root, .std_root = std_root } };
    var warmed_import = try flattener.readImportSourceFile(std.testing.allocator, ".", "sa_std/core/cache_probe.sai", resolve_ctx);
    defer warmed_import.deinit(std.testing.allocator);
    try std.testing.expect(warmed_import.owned_source == null);

    var second_hasher = std.crypto.hash.sha2.Sha256.init(.{});
    _ = try hashResolvedSourceTree(std.testing.allocator, &second_hasher, null, &.{}, &.{}, project_root, std_root, false, "main.sa");
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
    _ = try hashResolvedSourceTree(std.testing.allocator, &third_hasher, null, &.{}, &.{}, project_root, std_root, false, "main.sa");
    var third_digest: [32]u8 = undefined;
    third_hasher.final(&third_digest);
    try std.testing.expect(test_source_tree_load_count > 1);
    try std.testing.expect(!std.mem.eql(u8, first_digest[0..], third_digest[0..]));
}

test "source tree with dynamic compile inputs remains keyable for manifest depfile validation" {
    var original_cwd = try std.fs.cwd().openDir(".", .{});
    defer original_cwd.close();
    var tmp = std.testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();
    try tmp.dir.setAsCwd();
    defer original_cwd.setAsCwd() catch {};

    try tmp.dir.writeFile(.{
        .sub_path = "dynamic.sa",
        .data =
        \\EXPAND OPTION_ENV! "SA_DYNAMIC_CACHE_PROBE"
        \\@dynamic_helper() -> i32:
        \\return 1
        ,
    });
    try tmp.dir.writeFile(.{
        .sub_path = "main.sa",
        .data =
        \\@import "dynamic.sa"
        \\@main() -> i32:
        \\return 0
        ,
    });
    const project_root = try std.fs.cwd().realpathAlloc(std.testing.allocator, ".");
    defer std.testing.allocator.free(project_root);

    var first_hasher = std.crypto.hash.sha2.Sha256.init(.{});
    const first_cacheable = try hashResolvedSourceTree(std.testing.allocator, &first_hasher, null, &.{}, &.{}, project_root, project_root, false, "main.sa");
    try std.testing.expect(first_cacheable);

    // Dynamic values are deliberately excluded from this preliminary key.
    // The request-local recorder and manifest prevalidation own that part of
    // the cache contract, including warm source-tree-cache lookups.
    var second_hasher = std.crypto.hash.sha2.Sha256.init(.{});
    const second_cacheable = try hashResolvedSourceTree(std.testing.allocator, &second_hasher, null, &.{}, &.{}, project_root, project_root, false, "main.sa");
    try std.testing.expect(second_cacheable);
}

test "project build key tracks runtime archive content" {
    var original_cwd = try std.fs.cwd().openDir(".", .{});
    defer original_cwd.close();
    var tmp = std.testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();
    try tmp.dir.setAsCwd();
    defer original_cwd.setAsCwd() catch {};

    try tmp.dir.writeFile(.{ .sub_path = "libsa_std.a", .data = "runtime-v1" });
    const project_root = try std.fs.cwd().realpathAlloc(std.testing.allocator, ".");
    defer std.testing.allocator.free(project_root);
    const archive_path = try tmp.dir.realpathAlloc(std.testing.allocator, "libsa_std.a");
    defer std.testing.allocator.free(archive_path);
    const missing_manifest = try std.fs.path.join(std.testing.allocator, &.{ project_root, "missing.sa.mod" });
    defer std.testing.allocator.free(missing_manifest);

    const project_context = ProjectContext{
        .root_path = project_root,
        .member_root_path = project_root,
        .workspace_manifest_path = missing_manifest,
        .member_manifest_path = missing_manifest,
        .manifest = null,
        .workspace_manifest = null,
        .member_manifest = null,
        .lock_file = null,
        .sum_file = null,
    };
    const first = (try computeProjectBuildKey(
        std.testing.allocator,
        &project_context,
        project_root,
        "main.sa",
        "exe",
        "",
        .build_exe,
        false,
        false,
        false,
        null,
        false,
        false,
        .std,
        1,
        true,
        &.{archive_path},
    )) orelse unreachable;

    // Keep the size stable so the regression proves that archive contents,
    // rather than path/metadata alone, participate in the artifact key.
    try tmp.dir.writeFile(.{ .sub_path = "libsa_std.a", .data = "runtime-v2" });
    const second = (try computeProjectBuildKey(
        std.testing.allocator,
        &project_context,
        project_root,
        "main.sa",
        "exe",
        "",
        .build_exe,
        false,
        false,
        false,
        null,
        false,
        false,
        .std,
        1,
        true,
        &.{archive_path},
    )) orelse unreachable;

    try std.testing.expect(!std.mem.eql(u8, first.slice(), second.slice()));
}

test "project build key tracks zigcc toolchain identity" {
    if (builtin.os.tag == .windows) return error.SkipZigTest;

    const Helper = struct {
        fn writeFakeTool(path: []const u8, version: []const u8) !void {
            const source = try std.fmt.allocPrint(std.testing.allocator, "#!/bin/sh\necho {s}\n", .{version});
            defer std.testing.allocator.free(source);
            try writeAllFile(path, source);
            try makeExecutable(path);
        }
    };

    var original_cwd = try std.fs.cwd().openDir(".", .{});
    defer original_cwd.close();
    var tmp = std.testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();
    try tmp.dir.setAsCwd();
    defer original_cwd.setAsCwd() catch {};

    try tmp.dir.makePath("bin");
    try Helper.writeFakeTool("bin/zig", "zig-tool-v1");
    try writeAllFile("libsa_std.a", "runtime-v1");
    const bin_path = try tmp.dir.realpathAlloc(std.testing.allocator, "bin");
    defer std.testing.allocator.free(bin_path);
    const previous_toolchain_path = project_build_key_toolchain_path_override;
    project_build_key_toolchain_path_override = bin_path;
    defer project_build_key_toolchain_path_override = previous_toolchain_path;

    const project_root = try std.fs.cwd().realpathAlloc(std.testing.allocator, ".");
    defer std.testing.allocator.free(project_root);
    const archive_path = try tmp.dir.realpathAlloc(std.testing.allocator, "libsa_std.a");
    defer std.testing.allocator.free(archive_path);
    const missing_manifest = try std.fs.path.join(std.testing.allocator, &.{ project_root, "missing.sa.mod" });
    defer std.testing.allocator.free(missing_manifest);

    const project_context = ProjectContext{
        .root_path = project_root,
        .member_root_path = project_root,
        .workspace_manifest_path = missing_manifest,
        .member_manifest_path = missing_manifest,
        .manifest = null,
        .workspace_manifest = null,
        .member_manifest = null,
        .lock_file = null,
        .sum_file = null,
    };
    const first = (try computeProjectBuildKey(
        std.testing.allocator,
        &project_context,
        project_root,
        "main.sa",
        "exe",
        "",
        .build_exe,
        false,
        false,
        false,
        null,
        false,
        false,
        .std,
        1,
        true,
        &.{archive_path},
    )) orelse unreachable;

    try Helper.writeFakeTool("bin/zig", "zig-tool-v2");
    const second = (try computeProjectBuildKey(
        std.testing.allocator,
        &project_context,
        project_root,
        "main.sa",
        "exe",
        "",
        .build_exe,
        false,
        false,
        false,
        null,
        false,
        false,
        .std,
        1,
        true,
        &.{archive_path},
    )) orelse unreachable;

    try std.testing.expect(!std.mem.eql(u8, first.slice(), second.slice()));
}

test "build output publication serializes artifact output pairs" {
    var original_cwd = try std.fs.cwd().openDir(".", .{});
    defer original_cwd.close();
    var tmp = std.testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();
    try tmp.dir.setAsCwd();
    defer original_cwd.setAsCwd() catch {};

    var stage_a = try BuildOutputStage.init(std.testing.allocator, "shared.out");
    defer stage_a.deinit(std.testing.allocator);
    var stage_b = try BuildOutputStage.init(std.testing.allocator, "shared.out");
    defer stage_b.deinit(std.testing.allocator);
    try writeAllFile(stage_a.artifact_path, "artifact-A");
    try writeAllFile(stage_a.output_path, "output-A");
    try writeAllFile(stage_b.artifact_path, "artifact-B");
    try writeAllFile(stage_b.output_path, "output-B");

    var pause = BuildOutputPublishTestPause{};
    build_output_publish_test_pause = &pause;
    defer {
        pause.continue_event.set();
        build_output_publish_test_pause = null;
    }

    const Publisher = struct {
        stage: *const BuildOutputStage,
        started: std.Thread.ResetEvent = .{},
        done: std.Thread.ResetEvent = .{},
        failure: ?anyerror = null,

        fn run(self: *@This()) void {
            defer self.done.set();
            self.started.set();
            self.stage.publish(std.heap.page_allocator, "shared.out.sa.bc", "shared.out", true, false) catch |err| {
                self.failure = err;
            };
        }
    };

    var publisher_a = Publisher{ .stage = &stage_a };
    var publisher_b = Publisher{ .stage = &stage_b };
    const thread_a = try std.Thread.spawn(.{}, Publisher.run, .{&publisher_a});
    var joined_a = false;
    defer if (!joined_a) thread_a.join();
    try pause.reached.timedWait(5 * std.time.ns_per_s);

    const thread_b = try std.Thread.spawn(.{}, Publisher.run, .{&publisher_b});
    var joined_b = false;
    defer if (!joined_b) thread_b.join();
    publisher_b.started.wait();
    try std.testing.expectError(error.Timeout, publisher_b.done.timedWait(20 * std.time.ns_per_ms));

    pause.continue_event.set();
    thread_a.join();
    joined_a = true;
    thread_b.join();
    joined_b = true;
    if (publisher_a.failure) |err| return err;
    if (publisher_b.failure) |err| return err;

    const artifact = try tmp.dir.readFileAlloc(std.testing.allocator, "shared.out.sa.bc", 1024);
    defer std.testing.allocator.free(artifact);
    const output = try tmp.dir.readFileAlloc(std.testing.allocator, "shared.out", 1024);
    defer std.testing.allocator.free(output);
    try std.testing.expectEqualStrings("artifact-B", artifact);
    try std.testing.expectEqualStrings("output-B", output);
}

test "project cache publishes one complete entry under concurrent writers" {
    var original_cwd = try std.fs.cwd().openDir(".", .{});
    defer original_cwd.close();
    var tmp = std.testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();
    try tmp.dir.setAsCwd();
    defer original_cwd.setAsCwd() catch {};

    try tmp.dir.writeFile(.{ .sub_path = "artifact-a.bc", .data = "artifact-A" });
    try tmp.dir.writeFile(.{ .sub_path = "output-a.bin", .data = "output-A" });
    try tmp.dir.writeFile(.{ .sub_path = "artifact-b.bc", .data = "artifact-B" });
    try tmp.dir.writeFile(.{ .sub_path = "output-b.bin", .data = "output-B" });

    const project_root = try std.fs.cwd().realpathAlloc(std.testing.allocator, ".");
    defer std.testing.allocator.free(project_root);
    const artifact_a = try tmp.dir.realpathAlloc(std.testing.allocator, "artifact-a.bc");
    defer std.testing.allocator.free(artifact_a);
    const output_a = try tmp.dir.realpathAlloc(std.testing.allocator, "output-a.bin");
    defer std.testing.allocator.free(output_a);
    const artifact_b = try tmp.dir.realpathAlloc(std.testing.allocator, "artifact-b.bc");
    defer std.testing.allocator.free(artifact_b);
    const output_b = try tmp.dir.realpathAlloc(std.testing.allocator, "output-b.bin");
    defer std.testing.allocator.free(output_b);

    var key = ProjectCacheKey{ .hex = undefined };
    @memset(key.hex[0..], 'a');
    const Writer = struct {
        project_root: []const u8,
        key: ProjectCacheKey,
        artifact: []const u8,
        output: []const u8,
        failure: ?anyerror = null,

        fn run(self: *@This()) void {
            projectCacheStore(std.heap.page_allocator, self.project_root, .build_exe, self.key, self.artifact, self.output, &.{}) catch |err| {
                self.failure = err;
            };
        }
    };
    var writer_a = Writer{ .project_root = project_root, .key = key, .artifact = artifact_a, .output = output_a };
    var writer_b = Writer{ .project_root = project_root, .key = key, .artifact = artifact_b, .output = output_b };
    const thread_a = try std.Thread.spawn(.{}, Writer.run, .{&writer_a});
    const thread_b = try std.Thread.spawn(.{}, Writer.run, .{&writer_b});
    thread_a.join();
    thread_b.join();
    if (writer_a.failure) |err| return err;
    if (writer_b.failure) |err| return err;

    const entry_dir = try projectCacheDir(std.testing.allocator, project_root, .build_exe, key);
    defer std.testing.allocator.free(entry_dir);
    try std.testing.expect(projectCacheEntryValidAtPath(.build_exe, key, entry_dir));
    const cached_artifact = try projectCacheEntryPath(std.testing.allocator, entry_dir, "artifact.sa.bc");
    defer std.testing.allocator.free(cached_artifact);
    const cached_output = try projectCacheEntryPath(std.testing.allocator, entry_dir, "output.bin");
    defer std.testing.allocator.free(cached_output);
    const artifact_bytes = try readTextFileAlloc(std.testing.allocator, cached_artifact);
    defer std.testing.allocator.free(artifact_bytes);
    const output_bytes = try readTextFileAlloc(std.testing.allocator, cached_output);
    defer std.testing.allocator.free(output_bytes);
    const coherent_a = std.mem.eql(u8, artifact_bytes, "artifact-A") and std.mem.eql(u8, output_bytes, "output-A");
    const coherent_b = std.mem.eql(u8, artifact_bytes, "artifact-B") and std.mem.eql(u8, output_bytes, "output-B");
    try std.testing.expect(coherent_a or coherent_b);

    var kind_dir = try tmp.dir.openDir(".sa_cache/build-exe", .{ .iterate = true });
    defer kind_dir.close();
    var entries = kind_dir.iterate();
    var entry_count: usize = 0;
    while (try entries.next()) |entry| {
        if (std.mem.eql(u8, entry.name, ".locks")) continue;
        entry_count += 1;
        try std.testing.expectEqualStrings(key.slice(), entry.name);
    }
    try std.testing.expectEqual(@as(usize, 1), entry_count);
}

test "project cache manifest rejects symlink artifact entries" {
    if (builtin.os.tag == .windows) return error.SkipZigTest;

    var original_cwd = try std.fs.cwd().openDir(".", .{});
    defer original_cwd.close();
    var tmp = std.testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();
    try tmp.dir.setAsCwd();
    defer original_cwd.setAsCwd() catch {};

    const project_root = try std.fs.cwd().realpathAlloc(std.testing.allocator, ".");
    defer std.testing.allocator.free(project_root);
    const key = ProjectCacheKey{ .hex = [_]u8{'f'} ** 64 };
    const entry_dir = try projectCacheDir(std.testing.allocator, project_root, .build_exe, key);
    defer std.testing.allocator.free(entry_dir);
    try std.fs.cwd().makePath(entry_dir);

    const artifact_path = try projectCacheArtifactPath(std.testing.allocator, project_root, .build_exe, key, "artifact.sa.bc");
    defer std.testing.allocator.free(artifact_path);
    const output_path = try projectCacheArtifactPath(std.testing.allocator, project_root, .build_exe, key, "output.bin");
    defer std.testing.allocator.free(output_path);
    try writeAllFile(artifact_path, "artifact");
    try writeAllFile("real-output.bin", "output");
    try std.fs.cwd().symLink("real-output.bin", output_path, .{});
    const manifest_path = try projectCacheManifestPath(std.testing.allocator, project_root, .build_exe, key);
    defer std.testing.allocator.free(manifest_path);
    try projectCacheWriteManifestAt(std.testing.allocator, manifest_path, .build_exe, key, artifact_path, "real-output.bin", null, &.{});

    try std.testing.expectEqual(
        ProjectCacheLookupReason.incomplete,
        projectCacheManifestLookupReason(std.testing.allocator, project_root, .build_exe, key, artifact_path, output_path),
    );
    try std.testing.expectEqualStrings(
        "output.file",
        projectCacheManifestFirstDifference(std.testing.allocator, project_root, .build_exe, key).?,
    );
}

test "project cache manifest rejects symlink manifest entries" {
    if (builtin.os.tag == .windows) return error.SkipZigTest;

    var original_cwd = try std.fs.cwd().openDir(".", .{});
    defer original_cwd.close();
    var tmp = std.testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();
    try tmp.dir.setAsCwd();
    defer original_cwd.setAsCwd() catch {};

    const project_root = try std.fs.cwd().realpathAlloc(std.testing.allocator, ".");
    defer std.testing.allocator.free(project_root);
    const key = ProjectCacheKey{ .hex = [_]u8{'d'} ** 64 };
    const entry_dir = try projectCacheDir(std.testing.allocator, project_root, .build_exe, key);
    defer std.testing.allocator.free(entry_dir);
    try std.fs.cwd().makePath(entry_dir);

    const artifact_path = try projectCacheArtifactPath(std.testing.allocator, project_root, .build_exe, key, "artifact.sa.bc");
    defer std.testing.allocator.free(artifact_path);
    const output_path = try projectCacheArtifactPath(std.testing.allocator, project_root, .build_exe, key, "output.bin");
    defer std.testing.allocator.free(output_path);
    const real_manifest_path = try projectCacheArtifactPath(std.testing.allocator, project_root, .build_exe, key, "manifest-real.json");
    defer std.testing.allocator.free(real_manifest_path);
    const manifest_path = try projectCacheManifestPath(std.testing.allocator, project_root, .build_exe, key);
    defer std.testing.allocator.free(manifest_path);
    try writeAllFile(artifact_path, "artifact");
    try writeAllFile(output_path, "output");
    try projectCacheWriteManifestAt(std.testing.allocator, real_manifest_path, .build_exe, key, artifact_path, output_path, null, &.{});
    try std.fs.cwd().symLink("manifest-real.json", manifest_path, .{});

    try std.testing.expectEqual(
        ProjectCacheLookupReason.incomplete,
        projectCacheManifestLookupReason(std.testing.allocator, project_root, .build_exe, key, artifact_path, output_path),
    );
    try std.testing.expectEqualStrings(
        "manifest",
        projectCacheManifestFirstDifference(std.testing.allocator, project_root, .build_exe, key).?,
    );
    try std.testing.expectEqualStrings(
        "invalid",
        projectCacheManifestStatusName(std.testing.allocator, project_root, .build_exe, key, .incomplete),
    );
}

test "project cache manifest rejects symlink test metadata entries" {
    if (builtin.os.tag == .windows) return error.SkipZigTest;

    var original_cwd = try std.fs.cwd().openDir(".", .{});
    defer original_cwd.close();
    var tmp = std.testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();
    try tmp.dir.setAsCwd();
    defer original_cwd.setAsCwd() catch {};

    const project_root = try std.fs.cwd().realpathAlloc(std.testing.allocator, ".");
    defer std.testing.allocator.free(project_root);
    const key = ProjectCacheKey{ .hex = [_]u8{'c'} ** 64 };
    const entry_dir = try projectCacheDir(std.testing.allocator, project_root, .test_cache, key);
    defer std.testing.allocator.free(entry_dir);
    try std.fs.cwd().makePath(entry_dir);

    const artifact_path = try projectCacheArtifactPath(std.testing.allocator, project_root, .test_cache, key, "artifact.sa.bc");
    defer std.testing.allocator.free(artifact_path);
    const output_path = try projectCacheArtifactPath(std.testing.allocator, project_root, .test_cache, key, "output.bin");
    defer std.testing.allocator.free(output_path);
    const real_metadata_path = try projectCacheArtifactPath(std.testing.allocator, project_root, .test_cache, key, "test-metadata-real.json");
    defer std.testing.allocator.free(real_metadata_path);
    const metadata_path = try projectCacheTestMetadataPath(std.testing.allocator, project_root, key);
    defer std.testing.allocator.free(metadata_path);
    const manifest_path = try projectCacheManifestPath(std.testing.allocator, project_root, .test_cache, key);
    defer std.testing.allocator.free(manifest_path);
    try writeAllFile(artifact_path, "artifact");
    try writeAllFile(output_path, "output");
    try writeAllFile(real_metadata_path, "{\"version\":1,\"tests\":[]}\n");
    try std.fs.cwd().symLink("test-metadata-real.json", metadata_path, .{});
    try projectCacheWriteManifestAt(std.testing.allocator, manifest_path, .test_cache, key, artifact_path, output_path, real_metadata_path, &.{});

    try std.testing.expectEqual(
        ProjectCacheLookupReason.incomplete,
        projectCacheManifestLookupReason(std.testing.allocator, project_root, .test_cache, key, artifact_path, output_path),
    );
    try std.testing.expectEqualStrings(
        "test_metadata.file",
        projectCacheManifestFirstDifference(std.testing.allocator, project_root, .test_cache, key).?,
    );
    try std.testing.expectError(
        error.InvalidCacheManifest,
        projectCacheReadTestMetadata(std.testing.allocator, project_root, key),
    );
}

const ProjectCacheFailureTest = struct {
    fn expectNoEntryOrStaging(dir: std.fs.Dir, key: ProjectCacheKey) !void {
        var kind_dir = dir.openDir(".sa_cache/build-exe", .{ .iterate = true }) catch |err| switch (err) {
            error.FileNotFound => return,
            else => return err,
        };
        defer kind_dir.close();
        var entries = kind_dir.iterate();
        while (try entries.next()) |entry| {
            if (std.mem.eql(u8, entry.name, key.slice()) or cacheStagingKey(entry.name) != null) {
                return error.TestUnexpectedResult;
            }
        }
    }
};

test "project cache single flight hands a failed owner to one waiter" {
    var original_cwd = try std.fs.cwd().openDir(".", .{});
    defer original_cwd.close();
    var tmp = std.testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();
    try tmp.dir.setAsCwd();
    defer original_cwd.setAsCwd() catch {};

    try tmp.dir.writeFile(.{ .sub_path = "artifact.bc", .data = "owner-artifact" });
    try tmp.dir.writeFile(.{ .sub_path = "output.bin", .data = "owner-output" });
    const project_root = try std.fs.cwd().realpathAlloc(std.testing.allocator, ".");
    defer std.testing.allocator.free(project_root);
    const artifact_path = try tmp.dir.realpathAlloc(std.testing.allocator, "artifact.bc");
    defer std.testing.allocator.free(artifact_path);
    const output_path = try tmp.dir.realpathAlloc(std.testing.allocator, "output.bin");
    defer std.testing.allocator.free(output_path);
    const missing_manifest = try std.fs.path.join(std.testing.allocator, &.{ project_root, "missing.sa.mod" });
    defer std.testing.allocator.free(missing_manifest);
    const project_context = ProjectContext{
        .root_path = project_root,
        .member_root_path = project_root,
        .workspace_manifest_path = missing_manifest,
        .member_manifest_path = missing_manifest,
        .manifest = null,
        .workspace_manifest = null,
        .member_manifest = null,
        .lock_file = null,
        .sum_file = null,
    };
    var key = ProjectCacheKey{ .hex = undefined };
    @memset(key.hex[0..], 'd');

    const null_writer = std.io.null_writer;
    var first_owner: ?ProjectCacheEntryLock = null;
    var first_owner_miss_reason: ?ProjectCacheLookupReason = null;
    defer releaseProjectCacheOwner(&first_owner);
    switch (try projectCacheClaim(
        std.testing.allocator,
        project_root,
        .build_exe,
        key,
        &project_context,
        .{},
        "first-restore.bc",
        "first-restore.bin",
        null_writer,
        .human,
    )) {
        .owner => |owner| {
            first_owner = owner.lock;
            first_owner_miss_reason = owner.miss_reason;
        },
        else => return error.TestUnexpectedResult,
    }

    const Waiter = struct {
        project_root: []const u8,
        project_context: *const ProjectContext,
        key: ProjectCacheKey,
        artifact_path: []const u8,
        output_path: []const u8,
        started: std.Thread.ResetEvent = .{},
        done: std.Thread.ResetEvent = .{},
        became_owner: bool = false,
        owner_miss_reason: ?ProjectCacheLookupReason = null,
        failure: ?anyerror = null,

        fn run(self: *@This()) void {
            defer self.done.set();
            self.started.set();
            const thread_null_writer = std.io.null_writer;
            var owner: ?ProjectCacheEntryLock = null;
            defer releaseProjectCacheOwner(&owner);
            const claim = projectCacheClaim(
                std.heap.page_allocator,
                self.project_root,
                .build_exe,
                self.key,
                self.project_context,
                .{},
                "waiter-restore.bc",
                "waiter-restore.bin",
                thread_null_writer,
                .human,
            ) catch |err| {
                self.failure = err;
                return;
            };
            switch (claim) {
                .owner => |owner_value| {
                    owner = owner_value.lock;
                    self.owner_miss_reason = owner_value.miss_reason;
                },
                else => {
                    self.failure = error.TestUnexpectedResult;
                    return;
                },
            }
            projectCacheStoreWithOwnerMissReason(std.heap.page_allocator, self.project_root, .build_exe, self.key, self.artifact_path, self.output_path, &.{}, self.owner_miss_reason) catch |err| {
                self.failure = err;
                return;
            };
            self.became_owner = true;
        }
    };
    var waiter = Waiter{
        .project_root = project_root,
        .project_context = &project_context,
        .key = key,
        .artifact_path = artifact_path,
        .output_path = output_path,
    };
    const thread = try std.Thread.spawn(.{}, Waiter.run, .{&waiter});
    var joined = false;
    defer if (!joined) thread.join();
    waiter.started.wait();
    try std.testing.expectError(error.Timeout, waiter.done.timedWait(20 * std.time.ns_per_ms));

    try std.testing.expectError(
        error.FileNotFound,
        projectCacheStoreWithOwnerMissReason(std.testing.allocator, project_root, .build_exe, key, artifact_path, "missing-output.bin", &.{}, first_owner_miss_reason),
    );
    try ProjectCacheFailureTest.expectNoEntryOrStaging(tmp.dir, key);
    try std.testing.expectEqualStrings("failed", projectCacheEntryLastStoreResult(std.testing.allocator, project_root, .build_exe, key).?);
    try std.testing.expectEqualStrings("copy_output", projectCacheEntryLastStoreStage(std.testing.allocator, project_root, .build_exe, key).?);
    try std.testing.expectEqualStrings("absent", projectCacheEntryLastStoreOwnerMissReason(std.testing.allocator, project_root, .build_exe, key).?);
    try std.testing.expect(projectCacheEntryLastStoreEventNs(std.testing.allocator, project_root, .build_exe, key) != null);
    try std.testing.expect(projectCacheEntryLastStoreWriterPid(std.testing.allocator, project_root, .build_exe, key) != null);
    try std.testing.expect(projectCacheEntryLastStoreWriterStartTicks(std.testing.allocator, project_root, .build_exe, key) != null);
    try std.testing.expectEqual(@as(u64, 1), projectCacheEntryStoreEventHistoryCount(std.testing.allocator, project_root, .build_exe, key).?);
    const failed_counts = projectCacheEntryStoreEventHistoryResultCounts(std.testing.allocator, project_root, .build_exe, key).?;
    try std.testing.expectEqual(@as(u64, 0), failed_counts.published);
    try std.testing.expectEqual(@as(u64, 1), failed_counts.failed);
    var why_json = std.ArrayList(u8).init(std.testing.allocator);
    defer why_json.deinit();
    const why_args = [_][]const u8{ "--kind", "build-exe", "--key", key.slice(), "--json" };
    try std.testing.expectEqual(@as(u8, 0), try executeCacheWhyCommand(std.testing.allocator, why_args[0..], why_json.writer(), false));
    try std.testing.expect(std.mem.containsAtLeast(u8, why_json.items, 1, "\"reason\":\"absent\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, why_json.items, 1, "\"key_prefix\":\"dddddddddddd\""));
    try std.testing.expect(std.mem.indexOf(u8, why_json.items, key.slice()) == null);
    try std.testing.expect(std.mem.containsAtLeast(u8, why_json.items, 1, "\"last_store_result\":\"failed\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, why_json.items, 1, "\"last_store_stage\":\"copy_output\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, why_json.items, 1, "\"last_store_owner_miss_reason\":\"absent\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, why_json.items, 1, "\"last_store_event_ns\":"));
    try std.testing.expect(std.mem.indexOf(u8, why_json.items, "\"last_store_event_ns\":null") == null);
    try std.testing.expect(std.mem.containsAtLeast(u8, why_json.items, 1, "\"last_store_writer_pid\":"));
    try std.testing.expect(std.mem.indexOf(u8, why_json.items, "\"last_store_writer_pid\":null") == null);
    try std.testing.expect(std.mem.containsAtLeast(u8, why_json.items, 1, "\"last_store_writer_start_ticks\":"));
    try std.testing.expect(std.mem.indexOf(u8, why_json.items, "\"last_store_writer_start_ticks\":null") == null);
    try std.testing.expect(std.mem.containsAtLeast(u8, why_json.items, 1, "\"last_store_event_count\":1"));
    try std.testing.expect(std.mem.containsAtLeast(u8, why_json.items, 1, "\"last_store_published_event_count\":0"));
    try std.testing.expect(std.mem.containsAtLeast(u8, why_json.items, 1, "\"last_store_failed_event_count\":1"));

    releaseProjectCacheOwner(&first_owner);
    thread.join();
    joined = true;
    if (waiter.failure) |err| return err;
    try std.testing.expect(waiter.became_owner);
    try std.testing.expectEqual(ProjectCacheLookupReason.absent, waiter.owner_miss_reason.?);

    const entry_dir = try projectCacheDir(std.testing.allocator, project_root, .build_exe, key);
    defer std.testing.allocator.free(entry_dir);
    try std.testing.expect(projectCacheEntryValidAtPath(.build_exe, key, entry_dir));
    try std.testing.expectEqualStrings("published", projectCacheEntryLastStoreResult(std.testing.allocator, project_root, .build_exe, key).?);
    try std.testing.expectEqualStrings("publish", projectCacheEntryLastStoreStage(std.testing.allocator, project_root, .build_exe, key).?);
    try std.testing.expectEqualStrings("absent", projectCacheEntryLastStoreOwnerMissReason(std.testing.allocator, project_root, .build_exe, key).?);
    try std.testing.expect(projectCacheEntryLastStoreEventNs(std.testing.allocator, project_root, .build_exe, key) != null);
    try std.testing.expect(projectCacheEntryLastStoreWriterPid(std.testing.allocator, project_root, .build_exe, key) != null);
    try std.testing.expect(projectCacheEntryLastStoreWriterStartTicks(std.testing.allocator, project_root, .build_exe, key) != null);
    try std.testing.expectEqual(@as(u64, 2), projectCacheEntryStoreEventHistoryCount(std.testing.allocator, project_root, .build_exe, key).?);
    const published_counts = projectCacheEntryStoreEventHistoryResultCounts(std.testing.allocator, project_root, .build_exe, key).?;
    try std.testing.expectEqual(@as(u64, 1), published_counts.published);
    try std.testing.expectEqual(@as(u64, 1), published_counts.failed);
    why_json.clearRetainingCapacity();
    try std.testing.expectEqual(@as(u8, 0), try executeCacheWhyCommand(std.testing.allocator, why_args[0..], why_json.writer(), false));
    try std.testing.expect(std.mem.containsAtLeast(u8, why_json.items, 1, "\"reason\":\"hit\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, why_json.items, 1, "\"key_prefix\":\"dddddddddddd\""));
    try std.testing.expect(std.mem.indexOf(u8, why_json.items, key.slice()) == null);
    try std.testing.expect(std.mem.containsAtLeast(u8, why_json.items, 1, "\"last_store_result\":\"published\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, why_json.items, 1, "\"last_store_stage\":\"publish\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, why_json.items, 1, "\"last_store_owner_miss_reason\":\"absent\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, why_json.items, 1, "\"last_store_event_ns\":"));
    try std.testing.expect(std.mem.indexOf(u8, why_json.items, "\"last_store_event_ns\":null") == null);
    try std.testing.expect(std.mem.containsAtLeast(u8, why_json.items, 1, "\"last_store_writer_start_ticks\":"));
    try std.testing.expect(std.mem.indexOf(u8, why_json.items, "\"last_store_writer_start_ticks\":null") == null);
    try std.testing.expect(std.mem.containsAtLeast(u8, why_json.items, 1, "\"last_store_event_count\":2"));
    try std.testing.expect(std.mem.containsAtLeast(u8, why_json.items, 1, "\"last_store_published_event_count\":1"));
    try std.testing.expect(std.mem.containsAtLeast(u8, why_json.items, 1, "\"last_store_failed_event_count\":1"));
    var kind_dir = try tmp.dir.openDir(".sa_cache/build-exe", .{ .iterate = true });
    defer kind_dir.close();
    var entries = kind_dir.iterate();
    while (try entries.next()) |entry| try std.testing.expect(cacheStagingKey(entry.name) == null);
}

test "project cache OOM never publishes a partial entry" {
    const Ctx = struct {
        fn run(allocator: std.mem.Allocator) !void {
            var original_cwd = try std.fs.cwd().openDir(".", .{});
            defer original_cwd.close();
            var tmp = std.testing.tmpDir(.{ .iterate = true });
            defer tmp.cleanup();
            try tmp.dir.setAsCwd();
            defer original_cwd.setAsCwd() catch {};

            try tmp.dir.writeFile(.{ .sub_path = "artifact.bc", .data = "oom-artifact" });
            try tmp.dir.writeFile(.{ .sub_path = "output.bin", .data = "oom-output" });
            const project_root = try std.fs.cwd().realpathAlloc(std.testing.allocator, ".");
            defer std.testing.allocator.free(project_root);
            const artifact_path = try tmp.dir.realpathAlloc(std.testing.allocator, "artifact.bc");
            defer std.testing.allocator.free(artifact_path);
            const output_path = try tmp.dir.realpathAlloc(std.testing.allocator, "output.bin");
            defer std.testing.allocator.free(output_path);
            var key = ProjectCacheKey{ .hex = undefined };
            @memset(key.hex[0..], 'e');

            projectCacheStore(allocator, project_root, .build_exe, key, artifact_path, output_path, &.{}) catch |err| {
                if (err == error.OutOfMemory) try ProjectCacheFailureTest.expectNoEntryOrStaging(tmp.dir, key);
                return err;
            };

            const entry_dir = try projectCacheDir(std.testing.allocator, project_root, .build_exe, key);
            defer std.testing.allocator.free(entry_dir);
            try std.testing.expect(projectCacheEntryValidAtPath(.build_exe, key, entry_dir));
        }
    };

    try std.testing.checkAllAllocationFailures(std.testing.allocator, Ctx.run, .{});
}

test "project cache clean pins an active staging writer" {
    var original_cwd = try std.fs.cwd().openDir(".", .{});
    defer original_cwd.close();
    var tmp = std.testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();
    try tmp.dir.setAsCwd();
    defer original_cwd.setAsCwd() catch {};

    try tmp.dir.writeFile(.{ .sub_path = "artifact.bc", .data = "active-artifact" });
    try tmp.dir.writeFile(.{ .sub_path = "output.bin", .data = "active-output" });
    const project_root = try std.fs.cwd().realpathAlloc(std.testing.allocator, ".");
    defer std.testing.allocator.free(project_root);
    const artifact_path = try tmp.dir.realpathAlloc(std.testing.allocator, "artifact.bc");
    defer std.testing.allocator.free(artifact_path);
    const output_path = try tmp.dir.realpathAlloc(std.testing.allocator, "output.bin");
    defer std.testing.allocator.free(output_path);
    var key = ProjectCacheKey{ .hex = undefined };
    @memset(key.hex[0..], 'b');

    const Writer = struct {
        project_root: []const u8,
        key: ProjectCacheKey,
        artifact: []const u8,
        output: []const u8,
        failure: ?anyerror = null,

        fn run(self: *@This()) void {
            projectCacheStore(std.heap.page_allocator, self.project_root, .build_exe, self.key, self.artifact, self.output, &.{}) catch |err| {
                self.failure = err;
            };
        }
    };
    var pause = ProjectCacheStoreTestPause{};
    project_cache_store_test_pause = &pause;
    var writer = Writer{ .project_root = project_root, .key = key, .artifact = artifact_path, .output = output_path };
    const thread = try std.Thread.spawn(.{}, Writer.run, .{&writer});
    var joined = false;
    defer {
        pause.continue_event.set();
        if (!joined) thread.join();
        project_cache_store_test_pause = null;
    }
    try pause.reached.timedWait(5 * std.time.ns_per_s);

    const final_dir = try projectCacheDir(std.testing.allocator, project_root, .build_exe, key);
    defer std.testing.allocator.free(final_dir);
    try std.testing.expect(!projectPathExists(final_dir));
    const clean_stats = try cleanProjectCache(std.testing.allocator, project_root, .{ .max_age_days = 0 });
    try std.testing.expectEqual(@as(usize, 0), clean_stats.removed);
    try std.testing.expectEqual(@as(usize, 1), clean_stats.kept);

    var kind_dir = try tmp.dir.openDir(".sa_cache/build-exe", .{ .iterate = true });
    defer kind_dir.close();
    var entries = kind_dir.iterate();
    var staging_count: usize = 0;
    while (try entries.next()) |entry| {
        if (cacheStagingKey(entry.name) != null) staging_count += 1;
    }
    try std.testing.expectEqual(@as(usize, 1), staging_count);

    pause.continue_event.set();
    thread.join();
    joined = true;
    project_cache_store_test_pause = null;
    if (writer.failure) |err| return err;
    try std.testing.expect(projectCacheEntryValidAtPath(.build_exe, key, final_dir));
}

test "project cache clean preserves structurally valid stale dynamic entry" {
    var original_cwd = try std.fs.cwd().openDir(".", .{});
    defer original_cwd.close();
    var tmp = std.testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();
    try tmp.dir.setAsCwd();
    defer original_cwd.setAsCwd() catch {};

    try tmp.dir.writeFile(.{ .sub_path = "artifact.bc", .data = "artifact" });
    try tmp.dir.writeFile(.{ .sub_path = "output.bin", .data = "output" });
    try tmp.dir.writeFile(.{ .sub_path = "dependency.txt", .data = "first" });
    const project_root = try std.fs.cwd().realpathAlloc(std.testing.allocator, ".");
    defer std.testing.allocator.free(project_root);
    const artifact_path = try tmp.dir.realpathAlloc(std.testing.allocator, "artifact.bc");
    defer std.testing.allocator.free(artifact_path);
    const output_path = try tmp.dir.realpathAlloc(std.testing.allocator, "output.bin");
    defer std.testing.allocator.free(output_path);
    const dependency_path = try tmp.dir.realpathAlloc(std.testing.allocator, "dependency.txt");
    defer std.testing.allocator.free(dependency_path);
    var dependency_digest: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash("first", &dependency_digest, .{});
    const dependencies = [_]flattener.DynamicDependency{.{
        .kind = .file,
        .key = dependency_path,
        .present = true,
        .size = 5,
        .sha256 = dependency_digest,
    }};
    var key = ProjectCacheKey{ .hex = undefined };
    @memset(key.hex[0..], 'c');
    try projectCacheStore(std.testing.allocator, project_root, .build_exe, key, artifact_path, output_path, &dependencies);

    try tmp.dir.writeFile(.{ .sub_path = "dependency.txt", .data = "second" });
    const entry_dir = try projectCacheDir(std.testing.allocator, project_root, .build_exe, key);
    defer std.testing.allocator.free(entry_dir);
    try std.testing.expect(projectCacheEntryValidAtPath(.build_exe, key, entry_dir));
    try std.testing.expect(!projectCacheEntryReusableNow(std.testing.allocator, project_root, .build_exe, key));

    const clean_stats = try cleanProjectCache(std.testing.allocator, project_root, .{ .max_age_days = 0 });
    try std.testing.expectEqual(@as(usize, 0), clean_stats.removed);
    try std.testing.expectEqual(@as(usize, 1), clean_stats.kept);
    try std.testing.expect(projectCacheEntryValidAtPath(.build_exe, key, entry_dir));
}

test "project cache dynamic dependency validation detects file and environment changes" {
    var original_cwd = try std.fs.cwd().openDir(".", .{});
    defer original_cwd.close();
    var tmp = std.testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();
    try tmp.dir.setAsCwd();
    defer original_cwd.setAsCwd() catch {};

    try tmp.dir.writeFile(.{ .sub_path = "payload.txt", .data = "first" });
    const payload_path = try tmp.dir.realpathAlloc(std.testing.allocator, "payload.txt");
    defer std.testing.allocator.free(payload_path);
    const payload_hash = try hashFileHex(std.testing.allocator, payload_path);
    var file_json = std.ArrayList(u8).init(std.testing.allocator);
    defer file_json.deinit();
    try file_json.writer().writeAll("[{\"kind\":\"file\",\"path\":");
    try writeJsonString(file_json.writer(), payload_path);
    try file_json.writer().writeAll(",\"size\":5,\"sha256\":");
    try writeJsonString(file_json.writer(), payload_hash[0..]);
    try file_json.writer().writeAll("}]");
    var parsed_file = try std.json.parseFromSlice(std.json.Value, std.testing.allocator, file_json.items, .{});
    defer parsed_file.deinit();
    try std.testing.expect(try projectCacheDynamicDependenciesValid(std.testing.allocator, parsed_file.value));
    try tmp.dir.writeFile(.{ .sub_path = "payload.txt", .data = "changed" });
    try std.testing.expect(!try projectCacheDynamicDependenciesValid(std.testing.allocator, parsed_file.value));

    const path_value = std.process.getEnvVarOwned(std.testing.allocator, "PATH") catch return error.SkipZigTest;
    defer std.testing.allocator.free(path_value);
    var path_digest: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(path_value, &path_digest, .{});
    const path_digest_hex = std.fmt.bytesToHex(path_digest, .lower);
    const env_json = try std.fmt.allocPrint(
        std.testing.allocator,
        "[{{\"kind\":\"environment\",\"key\":\"PATH\",\"present\":true,\"sha256\":\"{s}\"}}]",
        .{path_digest_hex[0..]},
    );
    defer std.testing.allocator.free(env_json);
    var parsed_env = try std.json.parseFromSlice(std.json.Value, std.testing.allocator, env_json, .{});
    defer parsed_env.deinit();
    try std.testing.expect(try projectCacheDynamicDependenciesValid(std.testing.allocator, parsed_env.value));

    var parsed_wrong_presence = try std.json.parseFromSlice(
        std.json.Value,
        std.testing.allocator,
        "[{\"kind\":\"environment\",\"key\":\"PATH\",\"present\":false}]",
        .{},
    );
    defer parsed_wrong_presence.deinit();
    try std.testing.expect(!try projectCacheDynamicDependenciesValid(std.testing.allocator, parsed_wrong_presence.value));

    var parsed_absent = try std.json.parseFromSlice(
        std.json.Value,
        std.testing.allocator,
        "[{\"kind\":\"environment\",\"key\":\"SA_CACHE_DEPFILE_EXPECTED_ABSENT_7F3A\",\"present\":false}]",
        .{},
    );
    defer parsed_absent.deinit();
    try std.testing.expect(try projectCacheDynamicDependenciesValid(std.testing.allocator, parsed_absent.value));
}

test "source tree hash missing import returns PackageNotResolved without ownership errors" {
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
            \\@import "missing.sa"
            \\@main() -> i32:
            \\return 0
            \\
        );
    }

    const project_root = try std.fs.cwd().realpathAlloc(std.testing.allocator, ".");
    defer std.testing.allocator.free(project_root);
    const std_root = try std.fs.cwd().realpathAlloc(std.testing.allocator, "sa_std");
    defer std.testing.allocator.free(std_root);

    var hasher = std.crypto.hash.sha2.Sha256.init(.{});
    try std.testing.expectError(
        error.PackageNotResolved,
        hashResolvedSourceTree(std.testing.allocator, &hasher, null, &.{}, &.{}, project_root, std_root, false, "main.sa"),
    );
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
    _ = try hashResolvedSourceTree(std.testing.allocator, &first_hasher, null, &.{}, &.{}, project_root, project_root, false, "a.sa");
    try std.testing.expectEqual(@as(usize, 1), test_source_tree_load_count);

    var second_hasher = std.crypto.hash.sha2.Sha256.init(.{});
    _ = try hashResolvedSourceTree(std.testing.allocator, &second_hasher, null, &.{}, &.{}, project_root, project_root, false, "b.sa");
    try std.testing.expectEqual(@as(usize, 2), test_source_tree_load_count);

    var second_hit_hasher = std.crypto.hash.sha2.Sha256.init(.{});
    _ = try hashResolvedSourceTree(std.testing.allocator, &second_hit_hasher, null, &.{}, &.{}, project_root, project_root, false, "b.sa");
    try std.testing.expectEqual(@as(usize, 2), test_source_tree_load_count);

    var first_again_hasher = std.crypto.hash.sha2.Sha256.init(.{});
    _ = try hashResolvedSourceTree(std.testing.allocator, &first_again_hasher, null, &.{}, &.{}, project_root, project_root, false, "a.sa");
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

test "selected SAB compileSource runs Referee and preserves annotation deltas" {
    var original_cwd = try std.fs.cwd().openDir(".", .{});
    defer original_cwd.close();
    var tmp = std.testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();
    try tmp.dir.setAsCwd();
    defer original_cwd.setAsCwd() catch {};

    const reg_ids = [_]u32{1};
    const fsig = @import("common/signature.zig").FunctionSig{
        .id = 0,
        .name = "main",
        .params = &.{},
        .kind = .normal,
        .return_cap = null,
        .return_ty = .i32,
        .entry_inst_idx = 0,
        .is_ffi_wrapper = false,
        .reg_ids = reg_ids[0..],
    };
    var decl = @import("common/instruction.zig").makeInstruction(.func_decl, 1, 0, null, "");
    decl.operands[0] = .{ .symbol = 0 };
    decl.operands[1] = .{ .func = 0 };
    var assign = @import("common/instruction.zig").makeInstruction(.assign, 2, 1, null, "");
    assign.operands[0] = .{ .reg = 1 };
    assign.operands[1] = .{ .imm_i64 = 7 };
    var ret = @import("common/instruction.zig").makeInstruction(.return_, 3, 2, null, "");
    ret.operands[0] = .{ .reg = 1 };

    const bytes = try sab.encodeProgram(std.testing.allocator, &.{ "main", "value" }, &.{fsig}, &.{ decl, assign, ret });
    defer std.testing.allocator.free(bytes);
    try tmp.dir.writeFile(.{ .sub_path = "main.sab", .data = bytes });

    var compiled = try compileSource(std.testing.allocator, "main.sab", .{ .sab_selected_test_names = &.{"main"} });
    switch (compiled) {
        .ok => |*ok| {
            defer ok.deinit(std.testing.allocator);
            try std.testing.expectEqual(@as(usize, 3), ok.verified.annotated.len);
            try std.testing.expect(ok.verified.annotated[1].delta.changes.len != 0);
            try std.testing.expect(ok.verified.annotated[1].gas_step_cost != 0);
        },
        .trap => return error.TestUnexpectedResult,
    }
}

test "SAB check uses predecoded verdict cache without building a VerifyOk shell" {
    var original_cwd = try std.fs.cwd().openDir(".", .{});
    defer original_cwd.close();
    var tmp = std.testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();
    try tmp.dir.setAsCwd();
    defer original_cwd.setAsCwd() catch {};

    const reg_ids = [_]u32{1};
    const fsig = @import("common/signature.zig").FunctionSig{
        .id = 0,
        .name = "main",
        .params = &.{},
        .kind = .normal,
        .return_cap = null,
        .return_ty = .i32,
        .entry_inst_idx = 0,
        .is_ffi_wrapper = false,
        .reg_ids = reg_ids[0..],
    };
    var decl = @import("common/instruction.zig").makeInstruction(.func_decl, 1, 0, null, "");
    decl.operands[0] = .{ .symbol = 0 };
    decl.operands[1] = .{ .func = 0 };
    var assign = @import("common/instruction.zig").makeInstruction(.assign, 2, 1, null, "");
    assign.operands[0] = .{ .reg = 1 };
    assign.operands[1] = .{ .imm_i64 = 7 };
    var ret = @import("common/instruction.zig").makeInstruction(.return_, 3, 2, null, "");
    ret.operands[0] = .{ .reg = 1 };

    const bytes = try sab.encodeProgram(std.testing.allocator, &.{ "main", "value" }, &.{fsig}, &.{ decl, assign, ret });
    defer std.testing.allocator.free(bytes);
    try tmp.dir.writeFile(.{ .sub_path = "main.sab", .data = bytes });

    var stdout_buffer = std.ArrayList(u8).init(std.testing.allocator);
    defer stdout_buffer.deinit();
    var stderr_buffer = std.ArrayList(u8).init(std.testing.allocator);
    defer stderr_buffer.deinit();
    const check_argv = [_][]const u8{ "sa", "check", "main.sab", "--json" };

    incr_verify.clear();
    const first_code = try executeWithWriters(std.testing.allocator, check_argv[0..], stdout_buffer.writer(), stderr_buffer.writer());
    try std.testing.expectEqual(@as(u8, 0), first_code);
    var first_json = try std.json.parseFromSlice(std.json.Value, std.testing.allocator, stdout_buffer.items, .{});
    defer first_json.deinit();
    try std.testing.expect(jsonStringEquals(try jsonGetObject(first_json.value, "status"), "ok"));
    const first_metrics = try jsonGetObject(first_json.value, "metrics");
    const first_cache = try jsonGetObject(first_metrics, "cache");
    try std.testing.expect(jsonStringEquals(try jsonGetObject(first_cache, "kind"), "verify-verdict-v2"));
    try std.testing.expectEqual(false, try jsonBool(try jsonGetObject(first_cache, "hit")));
    try std.testing.expect((try jsonPositiveU64(try jsonGetObject(first_metrics, "instruction_count"))) > 0);
    try std.testing.expectEqual(@as(u64, 0), incr_verify.stats().hits);
    try std.testing.expectEqual(@as(u64, 1), incr_verify.stats().misses);

    stdout_buffer.clearRetainingCapacity();
    stderr_buffer.clearRetainingCapacity();
    const second_code = try executeWithWriters(std.testing.allocator, check_argv[0..], stdout_buffer.writer(), stderr_buffer.writer());
    try std.testing.expectEqual(@as(u8, 0), second_code);
    var second_json = try std.json.parseFromSlice(std.json.Value, std.testing.allocator, stdout_buffer.items, .{});
    defer second_json.deinit();
    const second_metrics = try jsonGetObject(second_json.value, "metrics");
    const second_cache = try jsonGetObject(second_metrics, "cache");
    try std.testing.expect(jsonStringEquals(try jsonGetObject(second_cache, "kind"), "verify-verdict-v2"));
    try std.testing.expectEqual(true, try jsonBool(try jsonGetObject(second_cache, "hit")));
    try std.testing.expectEqual(@as(u64, 1), incr_verify.stats().hits);
    try std.testing.expectEqual(@as(u64, 1), incr_verify.stats().misses);
}

test "selected SAB prune keeps the full module for unresolved indirect calls" {
    const source =
        \\@test "selected indirect root"():
        \\result = call_indirect callback()
        \\!result
        \\return
        \\@test "unselected ownership sentinel"():
        \\leaked = alloc 8
        \\return
    ;
    var flat = try flattener.flatten(std.testing.allocator, source);
    defer flat.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(usize, 2), flat.function_sigs.len);
    try std.testing.expectEqual(@as(usize, 2), flat.test_sigs.len);

    const selected_name = flat.test_sigs[0].name;
    const original_instruction_count = flat.instructions.len;
    try pruneSabFlatToSelectedTests(std.testing.allocator, &flat, &.{selected_name});

    try std.testing.expectEqual(@as(usize, 2), flat.function_sigs.len);
    try std.testing.expectEqual(@as(usize, 2), flat.test_sigs.len);
    try std.testing.expectEqual(original_instruction_count, flat.instructions.len);
}

test "selected SAB prune falls back for an unknown direct callee" {
    const source =
        \\@test "selected unknown callee"():
        \\call @missing_target()
        \\return
        \\@test "unselected sentinel"():
        \\return
    ;
    var flat = try flattener.flatten(std.testing.allocator, source);
    defer flat.deinit(std.testing.allocator);
    const selected_name = flat.test_sigs[0].name;
    try pruneSabFlatToSelectedTests(std.testing.allocator, &flat, &.{selected_name});
    try std.testing.expectEqual(@as(usize, 2), flat.function_sigs.len);
    try std.testing.expectEqual(@as(usize, 2), flat.test_sigs.len);
}

test "selected SAB prune retains explicit address-taken functions" {
    const source =
        \\@address_taken_helper():
        \\return
        \\@test "selected address root"():
        \\callback = @address_taken_helper
        \\!callback
        \\return
        \\@test "unselected sentinel"():
        \\return
    ;
    var flat = try flattener.flatten(std.testing.allocator, source);
    defer flat.deinit(std.testing.allocator);
    const selected_name = flat.test_sigs[0].name;
    try pruneSabFlatToSelectedTests(std.testing.allocator, &flat, &.{selected_name});
    try std.testing.expectEqual(@as(usize, 2), flat.function_sigs.len);
    try std.testing.expectEqual(@as(usize, 1), flat.test_sigs.len);
    var retained_helper = false;
    for (flat.function_sigs) |sig_item| {
        if (std.mem.eql(u8, sig_item.name, "address_taken_helper")) retained_helper = true;
    }
    try std.testing.expect(retained_helper);
}

test "selected SAB reachability work queue follows a transitive call chain" {
    const source =
        \\@leaf():
        \\return
        \\@middle():
        \\call @leaf()
        \\return
        \\@test "queue root"():
        \\call @middle()
        \\return
        \\@unrelated():
        \\return
    ;
    var flat = try flattener.flatten(std.testing.allocator, source);
    defer flat.deinit(std.testing.allocator);
    const selected_name = flat.test_sigs[0].name;
    try pruneSabFlatToSelectedTests(std.testing.allocator, &flat, &.{selected_name});
    try std.testing.expectEqual(@as(usize, 3), flat.function_sigs.len);
    for ([_][]const u8{ "leaf", "middle" }) |expected| {
        var found = false;
        for (flat.function_sigs) |sig_item| {
            if (std.mem.eql(u8, sig_item.name, expected)) found = true;
        }
        try std.testing.expect(found);
    }
    for (flat.function_sigs) |sig_item| try std.testing.expect(!std.mem.eql(u8, sig_item.name, "unrelated"));
}

test "repeated text compile never replaces Referee annotations with a verdict shell" {
    incr_verify.clear();

    var original_cwd = try std.fs.cwd().openDir(".", .{});
    defer original_cwd.close();
    var tmp = std.testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();
    try tmp.dir.setAsCwd();
    defer original_cwd.setAsCwd() catch {};

    const source =
        \\@main() -> i32:
        \\value = alloc 8
        \\!value
        \\return 0
    ;
    try tmp.dir.writeFile(.{ .sub_path = "main.sa", .data = source });

    var first = try compileSource(std.testing.allocator, "main.sa", .{});
    defer switch (first) {
        .ok => |*ok| ok.deinit(std.testing.allocator),
        .trap => {},
    };
    const first_ok = switch (first) {
        .ok => |*ok| ok,
        .trap => return error.TestUnexpectedResult,
    };
    try std.testing.expect(first_ok.verified.annotated[1].delta.changes.len != 0);
    try std.testing.expect(first_ok.verified.annotated[1].gas_step_cost != 0);

    var second = try compileSource(std.testing.allocator, "main.sa", .{});
    defer switch (second) {
        .ok => |*ok| ok.deinit(std.testing.allocator),
        .trap => {},
    };
    const second_ok = switch (second) {
        .ok => |*ok| ok,
        .trap => return error.TestUnexpectedResult,
    };

    try std.testing.expectEqual(first_ok.verified.annotated.len, second_ok.verified.annotated.len);
    try std.testing.expectEqual(first_ok.verified.annotated[1].gas_step_cost, second_ok.verified.annotated[1].gas_step_cost);
    const first_changes = first_ok.verified.annotated[1].delta.changes;
    const second_changes = second_ok.verified.annotated[1].delta.changes;
    try std.testing.expectEqual(first_changes.len, second_changes.len);
    for (first_changes, second_changes) |first_change, second_change| {
        try std.testing.expectEqual(first_change.reg, second_change.reg);
        try std.testing.expectEqual(first_change.before, second_change.before);
        try std.testing.expectEqual(first_change.after, second_change.after);
    }
    try std.testing.expectEqual(@as(u64, 0), incr_verify.stats().hits);
}

test "incremental cache regular-file fallback handles unknown dirent kinds without following links" {
    var tmp = std.testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();
    try tmp.dir.writeFile(.{ .sub_path = "object.o", .data = "object" });

    const unknown_file = std.fs.Dir.Entry{ .name = "object.o", .kind = .unknown };
    try std.testing.expect(cacheDirEntryIsRegularFile(tmp.dir, unknown_file));

    if (builtin.os.tag != .windows) {
        try tmp.dir.symLink("object.o", "object-link.o", .{});
        const unknown_link = std.fs.Dir.Entry{ .name = "object-link.o", .kind = .unknown };
        try std.testing.expect(!cacheDirEntryIsRegularFile(tmp.dir, unknown_link));
    }

    try tmp.dir.makeDir("functions");
    var functions_dir = try tmp.dir.openDir("functions", .{});
    defer functions_dir.close();
    const function_key = [_]u8{'a'} ** 64;
    const cache_key = [_]u8{'b'} ** 64;
    const object_name = try std.fmt.allocPrint(std.testing.allocator, "{s}.o", .{function_key[0..]});
    defer std.testing.allocator.free(object_name);
    try functions_dir.writeFile(.{ .sub_path = object_name, .data = "object" });
    var object_hasher = std.crypto.hash.sha2.Sha256.init(.{});
    object_hasher.update("object");
    var object_digest: [32]u8 = undefined;
    object_hasher.final(&object_digest);
    const object_sha256 = std.fmt.bytesToHex(object_digest, .lower);
    const manifest_bytes = try std.fmt.allocPrint(
        std.testing.allocator,
        "{{\"version\":2,\"kind\":\"build-obj-incremental\",\"key\":\"{s}\",\"source\":\"main.sa\",\"functions\":[{{\"key\":\"{s}\",\"path\":\"functions/{s}.o\",\"size\":6,\"sha256\":\"{s}\"}}]}}\n",
        .{ cache_key[0..], function_key[0..], function_key[0..], object_sha256[0..] },
    );
    var manifest_value = try parseOwnedIncrementalObjectManifest(std.testing.allocator, manifest_bytes, cache_key[0..], "main.sa");
    defer manifest_value.deinit(std.testing.allocator);
    markIncrementalManifestFile(&manifest_value, functions_dir, .{ .name = object_name, .kind = .unknown });
    try std.testing.expect(!manifest_value.unexpected_entries);
    try std.testing.expect(manifest_value.objectMetadata(function_key[0..]) != null);
}

test "non-cacheable dynamic dependencies do not reuse or publish incremental objects" {
    var original_cwd = try std.fs.cwd().openDir(".", .{});
    defer original_cwd.close();
    var tmp = std.testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();
    try tmp.dir.setAsCwd();
    defer original_cwd.setAsCwd() catch {};

    const source =
        \\@main() -> i32:
        \\return 0
    ;
    try tmp.dir.writeFile(.{ .sub_path = "main.sa", .data = source });

    var compile_result = try compileSource(std.testing.allocator, "main.sa", .{});
    defer switch (compile_result) {
        .ok => |*ok| ok.deinit(std.testing.allocator),
        .trap => {},
    };
    const compiled = switch (compile_result) {
        .ok => |*ok| ok,
        .trap => return error.TestUnexpectedResult,
    };

    const cache_key = ProjectCacheKey{ .hex = [_]u8{'a'} ** 64 };
    var stderr_buffer = std.ArrayList(u8).init(std.testing.allocator);
    defer stderr_buffer.deinit();
    try buildIncrementalObject(std.testing.allocator, ".", cache_key, compiled, "main.sa", "first.o", false, .release_fast, .{}, stderr_buffer.writer());

    const entry_path = try projectCacheDir(std.testing.allocator, ".", .build_obj_incremental, cache_key);
    defer std.testing.allocator.free(entry_path);
    const manifest_path = try pathJoinAlloc(std.testing.allocator, &.{ entry_path, "manifest.json" });
    defer std.testing.allocator.free(manifest_path);
    const manifest_before = try std.fs.cwd().readFileAlloc(std.testing.allocator, manifest_path, project_cache_manifest_max_bytes);
    defer std.testing.allocator.free(manifest_before);

    const object_name = object_name: {
        const functions_path = try pathJoinAlloc(std.testing.allocator, &.{ entry_path, "functions" });
        defer std.testing.allocator.free(functions_path);
        var functions_dir = try std.fs.cwd().openDir(functions_path, .{ .iterate = true });
        defer functions_dir.close();
        var iter = functions_dir.iterate();
        while (try iter.next()) |entry| {
            if (entry.kind == .file and std.mem.endsWith(u8, entry.name, ".o")) {
                break :object_name try std.testing.allocator.dupe(u8, entry.name);
            }
        }
        return error.TestUnexpectedResult;
    };
    defer std.testing.allocator.free(object_name);
    const object_path = try pathJoinAlloc(std.testing.allocator, &.{ entry_path, "functions", object_name });
    defer std.testing.allocator.free(object_path);
    const pristine_object = try std.fs.cwd().readFileAlloc(std.testing.allocator, object_path, 64 * 1024 * 1024);
    defer std.testing.allocator.free(pristine_object);
    try std.testing.expect(pristine_object.len > 0);
    const zeroed_object = try std.testing.allocator.alloc(u8, pristine_object.len);
    defer std.testing.allocator.free(zeroed_object);
    @memset(zeroed_object, 0);
    try std.fs.cwd().writeFile(.{ .sub_path = object_path, .data = zeroed_object });

    compiled.flat.dynamic_dependencies_cacheable = false;
    stderr_buffer.clearRetainingCapacity();
    try buildIncrementalObject(std.testing.allocator, ".", cache_key, compiled, "main.sa", "second.o", false, .release_fast, .{}, stderr_buffer.writer());

    const manifest_after = try std.fs.cwd().readFileAlloc(std.testing.allocator, manifest_path, project_cache_manifest_max_bytes);
    defer std.testing.allocator.free(manifest_after);
    try std.testing.expectEqualSlices(u8, manifest_before, manifest_after);
    const cached_after = try std.fs.cwd().readFileAlloc(std.testing.allocator, object_path, 64 * 1024 * 1024);
    defer std.testing.allocator.free(cached_after);
    try std.testing.expectEqualSlices(u8, zeroed_object, cached_after);
    const second_stat = try std.fs.cwd().statFile("second.o");
    try std.testing.expect(second_stat.kind == .file and second_stat.size > 0);

    const functions_path = try pathJoinAlloc(std.testing.allocator, &.{ entry_path, "functions" });
    defer std.testing.allocator.free(functions_path);
    var functions_dir = try std.fs.cwd().openDir(functions_path, .{ .iterate = true });
    defer functions_dir.close();
    var iter = functions_dir.iterate();
    while (try iter.next()) |entry| try std.testing.expect(std.mem.indexOf(u8, entry.name, ".tmp.") == null);
}

test "selected SAB compile-only cannot bypass Referee ownership traps" {
    var original_cwd = try std.fs.cwd().openDir(".", .{});
    defer original_cwd.close();
    var tmp = std.testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();
    try tmp.dir.setAsCwd();
    defer original_cwd.setAsCwd() catch {};

    const source =
        \\@test "probe"():
        \\value = alloc 8
        \\^value
        \\probe = load value+0 as i8
        \\return
    ;
    var flat = try flattener.flatten(std.testing.allocator, source);
    defer flat.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(usize, 1), flat.function_sigs.len);
    try std.testing.expectEqual(@as(usize, 0), flat.function_sigs[0].reg_ids.len);
    flat.function_sigs[0].reg_ids = try std.testing.allocator.dupe(u32, &.{
        flat.symbols.findId("value").?,
        flat.symbols.findId("probe").?,
    });
    const bytes = try sab.encodeProgramWithConsts(
        std.testing.allocator,
        flat.symbols.names.items,
        flat.const_decls,
        flat.function_sigs,
        flat.instructions,
    );
    defer std.testing.allocator.free(bytes);
    try tmp.dir.writeFile(.{ .sub_path = "invalid.sab", .data = bytes });

    var stdout_buffer = std.ArrayList(u8).init(std.testing.allocator);
    defer stdout_buffer.deinit();
    var stderr_buffer = std.ArrayList(u8).init(std.testing.allocator);
    defer stderr_buffer.deinit();
    const argv = [_][]const u8{
        "sa",
        "test",
        "invalid.sab",
        "--compile-only",
        "--filter",
        "probe",
        "--no-incremental",
        "--profile",
    };
    const code = try executeWithWriters(
        std.testing.allocator,
        argv[0..],
        stdout_buffer.writer(),
        stderr_buffer.writer(),
    );

    try std.testing.expectEqual(@as(u8, 1), code);
    try std.testing.expect(std.mem.containsAtLeast(u8, stderr_buffer.items, 1, "UseAfterMove"));
    try std.testing.expect(std.mem.indexOf(u8, stderr_buffer.items, "trusted=1") == null);
}
