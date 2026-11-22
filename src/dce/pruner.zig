//! DCE 裁剪器 —— SA 标准库模块化 Phase 6（P6A，sa-reachability）。
//!
//! 职责：按 P5C 的 `ReachabilityReport`，把 Phase 4 的两张图裁剪成
//! 新图（提案 §3 的 Reachability-based DCE 的执行动作）：
//!   - 符号图：只留可达符号 + 两端都可达的符号边；
//!   - 模块图：只留仍有符号的模块 + module_only 模块 + 两端模块都还在的边；
//!   - 交出被删掉的符号（`removed_symbols`）、符号边条数
//!     （`removed_edges`）与被整模块删掉的模块（`removed_modules`），
//!     供 P6B/P6C 核对与写回。
//!
//! 核心约束（Phase 5 M3 的假设同样适用）：`SymbolGraph` 与
//! `ModuleGraph` 都只有 add API、没有 remove/delete API（append-only）。
//! 所以裁剪不能原地删，必须建新图：把保留的部分复制进一个全新的
//! `SymbolGraph` + `ModuleGraph`，原图原样不动。
//!
//! 保留规则（按任务契约，缺一不可）：
//!   1. 新图只含 `report.reachable` 里的符号；只复制两端都在可达集里
//!      的边；`module_deps` 只保留两端模块都还在的（“还在”的定义见
//!      `keptModules`：有保留符号的模块 ∪ module_only 模块）。
//!   2. 绝不裁剪 kind == .unknown 的符号：种类未知不得理解为“可删
//!      除”。即使它在 `report.prunable` 里，也把它当保留，留在新图
//!      里，且不计入 `removed_symbols`。注意：边的去留仍只按规则 1
//!      的“两端都在可达集”判定，不因端点被保留而放宽——被保留的
//!      unknown 符号若不在可达集里，其关联边仍被删（边的
//!      `removed_edges` 计数与此一致）。
//!   3. 绝不裁剪 `report.reachable` 里的符号：以可达集为准绳，即使
//!      `prunable` 里误含同一符号，也以可达为准（不删除、不计入
//!      `removed_symbols`）。
//!   4. 保留插入顺序、保证结果确定性：边（`edges` / `module_deps` /
//!      模块边）按原图列表的插入顺序复制；模块节点按原模块图的
//!      `insertion_order` 复制；`removed_symbols` 按 `report.prunable`
//!      的顺序，`removed_modules` 按原模块图的 `insertion_order`。
//!      例外——符号节点的插入顺序无法从原图恢复：`SymbolGraph.nodes`
//!      是 HashMap，不存插入顺序；因此节点按“边中首次出现顺序 →
//!      `report.reachable` 顺序 → `prunable` 顺序 → 排序后的防御剩余”
//!      复制（见 `prune` 内注释）。节点顺序在 `SymbolGraph` 内本来也
//!      不可观测（新图的节点表同样是 HashMap），上述顺序只保证复制
//!      过程本身确定。
//!   5. 只借用字符串，不拥有（与 Phase 4/5 的 arena 规则一致）：节点
//!      名、模块 path 均为调用方 arena 所有；`deinit` 只释放自己拥有
//!      的容器与 owned 切片（`removed_symbols` / `removed_modules`）。
//!
//! module_only（`report.convergence.module_only_modules`）：模块级边
//! 绝不展开成该模块的全部符号；module_only 模块留在模块图里，但不
//! 贡献符号——即它的符号仍按可达性正常裁剪，不因“模块被留下”而保留。
//!
//! 不判定保留规则：`RetainRule`（entry_point / macro_expanded /
//! reflective / dynamic_call / global_init / exported）中只有
//! entry_point（main）与 global_init 有真实执行逻辑，其余四条只登记
//! 文本、无判定逻辑（见 retention.zig）；保留规则的判定在 P5B 的
//! roots/retention，分析结果已体现在报告里。本文件只消费报告，不重
//! 新判定任何符号是否“应保留”，不发明判定逻辑。
//!
//! 防御性保留（报告与图不一致时才触发，正常输入下是空操作）：
//!   - `report.reachable` 里有、原图 `nodes` 里没有的符号（如未登记
//!     的根节点）：仍复制进新图，kind 取报告节点自带的 kind；
//!   - 原图 `nodes` 里有、既不在 `reachable` 也不在 `prunable` 里的
//!     符号（报告过期 / 两图未对齐）：保守保留，不删除未分类的符号，
//!     不计入 `removed_symbols`；此类节点按 (package, path, name)
//!     排序后复制，保证确定性。
//!
//! 不属于本文件：可达性分析（P5A 的 analyzer.zig）、报告生成（P5C
//! 的 report.zig）、裁剪结果的发射与写回（P6B/P6C）、build.zig 注册
//! （后续 Phase / 协调方接线）；不改任何既有文件。

const std = @import("std");
const symbol_graph_mod = @import("../dependency_graph/symbol_graph.zig");
const module_graph_mod = @import("../dependency_graph/module_graph.zig");
const report_mod = @import("../reachability/report.zig");

// 复用，不重定义（路径均相对于 src/dce/）。
pub const SymbolGraph = symbol_graph_mod.SymbolGraph;
pub const SymbolNode = symbol_graph_mod.SymbolNode;
pub const SymbolKind = symbol_graph_mod.SymbolKind;
pub const SymbolRefEdge = symbol_graph_mod.SymbolRefEdge;
pub const RefKind = symbol_graph_mod.RefKind;
pub const ModuleGraph = module_graph_mod.ModuleGraph;
pub const ModuleId = symbol_graph_mod.ModuleId;
pub const ModuleDep = symbol_graph_mod.ModuleDep;
pub const PruneReason = report_mod.PruneReason;
pub const PruneCandidate = report_mod.PruneCandidate;
pub const ReachabilityReport = report_mod.ReachabilityReport;

/// 保留符号表：节点 → 有效 kind（去重键是 SymbolNode 身份，
/// 即 (module, name)，kind 不参与 eql/hash）。
const KeptMap = std.HashMap(SymbolNode, SymbolKind, SymbolNode.Context, std.hash_map.default_max_load_percentage);
/// 符号节点集：可达集 / prunable 集（去重与成员判定用）。
const NodeSet = std.HashMap(SymbolNode, void, SymbolNode.Context, std.hash_map.default_max_load_percentage);
/// 模块集：保留模块集（去重与成员判定用）。
const ModuleSet = std.HashMap(ModuleId, void, ModuleId.Context, std.hash_map.default_max_load_percentage);

/// 一个被裁剪掉的符号：节点 + 图登记的 kind + 报告给出的裁剪原因。
/// `node` 与 `kind` 均为值拷贝（字符串仍借用调用方 arena）。
pub const RemovedSymbol = struct {
    node: SymbolNode,
    kind: SymbolKind,
    reason: PruneReason,
};

/// 裁剪后的图：全新的 `SymbolGraph` + `ModuleGraph`（原图不动），
/// 附被删的符号、符号边条数与被整模块删掉的模块。
///
/// 不变式（`prune` 保证，P6B/P6C 可据此核对）：
///   - `symbols` 的已定义符号 = `report.reachable` ∪ kind 为 .unknown
///     的 prunable 候选 ∪ 防御性保留（见文件头；正常输入下第三项为空）；
///   - `symbols` 的边 = 原图 `edges` 中两端都在 `report.reachable`
///     里的边（按原插入顺序），其余边计入 `removed_edges`；
///   - `symbols` 的 `module_deps` = 原图 `module_deps` 中两端模块都
///     在保留模块集里的依赖（按原插入顺序）；
///   - `modules` 的节点 = 仍有符号的模块 ∪ module_only 模块（按原
///     模块图 `insertion_order`；module_only 模块若原先不在模块图
///     里，以 .unloaded 态补建，见 `prune` 内注释）；
///   - `modules` 的边 = 原模块图边中两端模块都在保留模块集里的边
///     （按原插入顺序）；
///   - `removed_symbols` = `report.prunable` 中既不在可达集里、kind
///     又不为 .unknown 的候选（按 `report.prunable` 的顺序）；
///   - `removed_modules` = 原模块图节点中不在保留模块集里的模块
///     （按原模块图 `insertion_order`）。
pub const PrunedGraph = struct {
    /// 调用方传入的分配器；`deinit` 用它释放 owned 切片。
    allocator: std.mem.Allocator,
    /// 仅可达符号 + 两端都可达的边（另见不变式里的 unknown 保留例外）。
    symbols: SymbolGraph,
    /// 仅仍有符号的模块 + module_only 模块。
    modules: ModuleGraph,
    /// 被删掉的符号（按 `report.prunable` 的顺序）。
    removed_symbols: []RemovedSymbol,
    /// 被删掉的符号边条数（原图边数减去新图边数）。
    removed_edges: usize,
    /// 被整模块删掉的模块（无符号剩余且非 module_only，按原模块图
    /// `insertion_order`）。
    removed_modules: []ModuleId,

    /// 只释放本结构自己拥有的容器与 owned 切片（`removed_symbols` /
    /// `removed_modules` 与两张新图的容器）；不释放任何借用串（符号
    /// 名、模块 path 由调用方 arena 统一释放）。调用后实例不可再用。
    pub fn deinit(self: *PrunedGraph) void {
        // 长度为 0 的切片不释放：它可能是一段空切片而非分配器产物
        //（与 converge.zig 的 Convergence.deinit 同款防御）。
        if (self.removed_symbols.len > 0) self.allocator.free(self.removed_symbols);
        if (self.removed_modules.len > 0) self.allocator.free(self.removed_modules);
        self.symbols.deinit();
        self.modules.deinit();
        self.* = undefined;
    }
};

/// 节点的有效 kind：以原图 `nodes` 表登记的 kind 为准（`addSymbol`
/// 升级后的真实 kind，见 report.zig 的 buildReport）；原图未登记
/// 时取调用方给的 fallback（报告节点自带的 kind / 候选的 kind）。
fn effectiveKind(graph: *const SymbolGraph, node: SymbolNode, fallback: SymbolKind) SymbolKind {
    return graph.symbolKindOf(node) orelse fallback;
}

/// 登记一个保留符号及其有效 kind；同一节点多次登记时 kind 只做
/// unknown → 具体升级（与 `SymbolGraph.addSymbol` 的升级语义一致），
/// 不降级、不覆盖。
fn putKept(kept: *KeptMap, node: SymbolNode, kind: SymbolKind) std.mem.Allocator.Error!void {
    const entry = try kept.getOrPut(node);
    if (!entry.found_existing) {
        entry.value_ptr.* = kind;
    } else if (entry.value_ptr.* == .unknown and kind != .unknown) {
        entry.value_ptr.* = kind;
    }
}

/// (package, path, name) 字典序：防御性保留节点的排序比较器。
fn symbolNodeLessThan(_: void, a: SymbolNode, b: SymbolNode) bool {
    const pkg = std.mem.order(u8, a.module.package, b.module.package);
    if (pkg != .eq) return pkg == .lt;
    const path = std.mem.order(u8, a.module.path, b.module.path);
    if (path != .eq) return path == .lt;
    return std.mem.order(u8, a.name, b.name) == .lt;
}

/// 把 add-only 图调用的 GraphError 收窄为 `std.mem.Allocator.Error`：
/// 本文件只调 add 系调用（`addSymbol` / `addEdge` / `addModuleDep` /
/// `addModule` / `addModuleWithPath`），它们除分配失败外不返回其他
/// 错误（`InvalidExpandedEdgeKind` 只属于 `addExpandedEdge`，本文件
/// 不调它；`NodeNotFound` / `CycleDetected` / `InvalidState` 只属于
/// 查询 / topoSort / setState，本文件不调它们）。若真出现其他错误，
/// 是调用逻辑错误，`unreachable` 显式暴露，不静默吞掉。
fn oomOnly(err: anyerror) std.mem.Allocator.Error {
    return switch (err) {
        error.OutOfMemory => error.OutOfMemory,
        else => unreachable,
    };
}

/// 按 `report` 裁剪两张图，返回全新的 `PrunedGraph`。
///
///   - `symbol_graph` / `module_graph`：只读，原图原样不动；
///   - `report`：P5C 的 `ReachabilityReport`（须与 `symbol_graph` 对
///     应同一张图；若两者来自不同的图，可达集与定义集的差集无意义，
///     见 report.zig 的输入契约）；
///   - `allocator`：新图与 owned 切片的分配器（通常是 arena）；返回
///     的 `PrunedGraph` 持有它，`deinit` 时用它释放。
///
/// 步骤（顺序固定）：
///   1. 建可达集（`report.reachable`）与 prunable 集（`report.prunable`
///      的节点身份集，供第 4 步的防御性 sweep 用）；
///   2. 过一遍 `report.prunable`：在可达集里的跳过（规则 3，以可达
///      为准绳）；kind 为 .unknown 的记为保留（规则 2，不计入
///      `removed_symbols`）；其余的记入 `removed_symbols`；
///   3. 保留符号表 = 全部可达符号（有效 kind 取图登记）+ 第 2 步的
///      unknown 保留 + 防御性 sweep（原图 `nodes` 里既不在可达集也
///      不在 prunable 集里的符号，保守保留，按字典序排过）；
///   4. 保留模块集 = 保留符号所属的模块 ∪ module_only 模块；
///   5. 建新符号图：节点按“边中首次出现顺序 → `report.reachable`
///      顺序 → `prunable` 顺序 → 排序后的防御剩余”复制（原图
///      `nodes` 是 HashMap、无插入顺序，此为最接近原图插入顺序的
///      确定顺序；见文件头规则 4）；边只复制两端都在可达集里的
///      （按原 `edges.items` 顺序），其余计入 `removed_edges`；
///      `module_deps` 只复制两端模块都在保留模块集里的（按原顺序）；
///   6. 建新模块图：节点按原模块图 `insertion_order` 复制保留模块
///      （state / fs_path 原样带过）；module_only 模块若原先不在模
///      块图里，以 .unloaded 态补建（“模块级边绝不展开”，状态未知时
///      .unloaded 是中性初态，不伪装成已加载）；边只复制两端模块都
///      在保留模块集里的（按原顺序）；不在保留模块集里的原模块节点
///      记入 `removed_modules`（按原 `insertion_order`）。
pub fn prune(
    symbol_graph: *const SymbolGraph,
    module_graph: *const ModuleGraph,
    report: *const ReachabilityReport,
    allocator: std.mem.Allocator,
) std.mem.Allocator.Error!PrunedGraph {
    // —— 第 1 步：可达集与 prunable 集 ——
    var reachable_set = NodeSet.init(allocator);
    defer reachable_set.deinit();
    for (report.reachable) |node| {
        try reachable_set.put(node, {});
    }

    var prunable_set = NodeSet.init(allocator);
    defer prunable_set.deinit();
    for (report.prunable) |candidate| {
        try prunable_set.put(candidate.node, {});
    }

    // —— 第 2 步：过 prunable，定 removed / unknown 保留 ——
    var removed = std.array_list.Managed(RemovedSymbol).init(allocator);
    errdefer removed.deinit();
    var unknown_retained = std.array_list.Managed(SymbolNode).init(allocator);
    errdefer unknown_retained.deinit();
    for (report.prunable) |candidate| {
        // 规则 3：以可达集为准绳——prunable 里误含可达符号时不删。
        if (reachable_set.contains(candidate.node)) continue;
        const kind = effectiveKind(symbol_graph, candidate.node, candidate.kind);
        // 规则 2：kind 未知不得理解为“可删除”——保留，不计入 removed。
        if (kind == .unknown) {
            try unknown_retained.append(.{
                .module = candidate.node.module,
                .name = candidate.node.name,
                .kind = .unknown,
            });
            continue;
        }
        try removed.append(.{
            .node = candidate.node,
            .kind = kind,
            .reason = candidate.reason,
        });
    }

    // —— 第 3 步：保留符号表 ——
    var kept = KeptMap.init(allocator);
    defer kept.deinit();
    // 3a. 全部可达符号（有效 kind 取图登记；未登记的根节点取报告 kind）。
    for (report.reachable) |node| {
        try putKept(&kept, node, effectiveKind(symbol_graph, node, node.kind));
    }
    // 3b. unknown 保留（第 2 步）。
    for (unknown_retained.items) |node| {
        try putKept(&kept, node, node.kind);
    }
    // 3c. 防御性 sweep：原图已定义、既不在可达集也不在 prunable 集里
    // 的符号——报告与图不一致时才出现；保守保留，不计入 removed。
    // 按 (package, path, name) 排序后登记，保证确定性。
    var leftovers = std.array_list.Managed(SymbolNode).init(allocator);
    defer leftovers.deinit();
    var it = symbol_graph.nodes.iterator();
    while (it.next()) |entry| {
        const node = entry.key_ptr.*;
        if (reachable_set.contains(node)) continue;
        if (prunable_set.contains(node)) continue;
        try leftovers.append(.{
            .module = node.module,
            .name = node.name,
            .kind = entry.value_ptr.*,
        });
    }
    if (leftovers.items.len > 1) {
        std.sort.block(SymbolNode, leftovers.items, {}, symbolNodeLessThan);
    }
    for (leftovers.items) |node| {
        try putKept(&kept, node, node.kind);
    }

    // —— 第 4 步：保留模块集 = 保留符号所属模块 ∪ module_only 模块 ——
    var kept_modules = ModuleSet.init(allocator);
    defer kept_modules.deinit();
    var kit = kept.keyIterator();
    while (kit.next()) |node_ptr| {
        try kept_modules.put(node_ptr.*.module, {});
    }
    // module_only 模块留在模块图里，但不贡献符号（此处只登记模块，
    // 不把该模块的符号加入保留表）。
    for (report.convergence.module_only_modules) |id| {
        try kept_modules.put(id, {});
    }

    // —— 第 5 步：建新符号图 ——
    var new_symbols = SymbolGraph.init(allocator);
    errdefer new_symbols.deinit();
    // 5a. 节点复制（确定顺序，见文件头规则 4）：
    //   (i) 边中首次出现顺序——最接近原图插入顺序的可恢复顺序；
    //   (ii) report.reachable 顺序——覆盖无边可循的孤立可达符号；
    //   (iii) prunable 顺序——覆盖无边可循的孤立 unknown 保留符号；
    //   (iv) 排序后的防御剩余——覆盖第 3c 步的 sweep 符号。
    // addSymbol 是幂等的（已登记则无操作），多遍登记不重复、不改 kind
    //（具体 kind 之间不互相覆盖，见 symbol_graph.zig）。
    for (symbol_graph.edges.items) |edge| {
        if (kept.get(edge.from)) |kind| {
            _ = new_symbols.addSymbol(.{ .module = edge.from.module, .name = edge.from.name, .kind = kind }) catch |err| return oomOnly(err);
        }
        if (kept.get(edge.to)) |kind| {
            _ = new_symbols.addSymbol(.{ .module = edge.to.module, .name = edge.to.name, .kind = kind }) catch |err| return oomOnly(err);
        }
    }
    for (report.reachable) |node| {
        if (kept.get(node)) |kind| {
            _ = new_symbols.addSymbol(.{ .module = node.module, .name = node.name, .kind = kind }) catch |err| return oomOnly(err);
        }
    }
    for (unknown_retained.items) |node| {
        if (kept.get(node)) |kind| {
            _ = new_symbols.addSymbol(.{ .module = node.module, .name = node.name, .kind = kind }) catch |err| return oomOnly(err);
        }
    }
    for (leftovers.items) |node| {
        if (kept.get(node)) |kind| {
            _ = new_symbols.addSymbol(.{ .module = node.module, .name = node.name, .kind = kind }) catch |err| return oomOnly(err);
        }
    }
    // 5b. 边复制：只复制两端都在可达集里的边（按原 edges.items 顺序）；
    // 其余计入 removed_edges。addEdge 自动登记端点——端点已在 5a 登
    // 记过，此处不再改变 kind（已登记的具体 kind 不会被边的 kind 覆盖）。
    var removed_edges: usize = 0;
    for (symbol_graph.edges.items) |edge| {
        if (!reachable_set.contains(edge.from) or !reachable_set.contains(edge.to)) {
            removed_edges += 1;
            continue;
        }
        _ = new_symbols.addEdge(edge.from, edge.to, edge.kind) catch |err| return oomOnly(err);
    }
    // 5c. module_deps 复制：只保留两端模块都还在的（按原顺序）。
    for (symbol_graph.module_deps.items) |dep| {
        if (!kept_modules.contains(dep.from) or !kept_modules.contains(dep.to)) continue;
        _ = new_symbols.addModuleDep(dep.from, dep.to) catch |err| return oomOnly(err);
    }

    // —— 第 6 步：建新模块图 ——
    var new_modules = ModuleGraph.init(allocator);
    errdefer new_modules.deinit();
    // 6a. 节点复制：按原模块图 insertion_order，state / fs_path 原样带过。
    for (module_graph.insertion_order.items) |id| {
        if (!kept_modules.contains(id)) continue;
        const node = module_graph.nodeOf(id) orelse continue;
        new_modules.addModuleWithPath(node.id, node.state, node.fs_path) catch |err| return oomOnly(err);
    }
    // 6b. module_only 模块若原先不在模块图里，以 .unloaded 态补建，
    // 使“module_only 模块留在模块图里”成立；已复制过的跳过（addModule
    // 本是幂等更新，此处用 contains 显式跳过，避免补建覆盖已复制的 state）。
    for (report.convergence.module_only_modules) |id| {
        if (new_modules.contains(id)) continue;
        new_modules.addModule(id, .unloaded) catch |err| return oomOnly(err);
    }
    // 6c. 边复制：只保留两端模块都还在的（按原顺序，via 原样带过）。
    for (module_graph.edges.items) |edge| {
        if (!kept_modules.contains(edge.from) or !kept_modules.contains(edge.to)) continue;
        new_modules.addEdge(edge.from, edge.to, edge.via) catch |err| return oomOnly(err);
    }
    // 6d. removed_modules：原模块图节点中不在保留模块集里的（按原顺序）。
    var removed_mods = std.array_list.Managed(ModuleId).init(allocator);
    errdefer removed_mods.deinit();
    for (module_graph.insertion_order.items) |id| {
        if (!kept_modules.contains(id)) {
            try removed_mods.append(id);
        }
    }

    const removed_symbols = try removed.toOwnedSlice();
    errdefer if (removed_symbols.len > 0) allocator.free(removed_symbols);
    const removed_modules = try removed_mods.toOwnedSlice();
    errdefer if (removed_modules.len > 0) allocator.free(removed_modules);

    return .{
        .allocator = allocator,
        .symbols = new_symbols,
        .modules = new_modules,
        .removed_symbols = removed_symbols,
        .removed_edges = removed_edges,
        .removed_modules = removed_modules,
    };
}
