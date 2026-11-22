//! 可达性报告与集成入口 —— SA 标准库模块化 Phase 5（P5C，sa-reachability）。
//!
//! 职责（只做整理与接线）：
//!   - 把 P5A 可达性分析的结果（`ReachabilityResult`）整理成一份
//!     `ReachabilityReport`：可达符号（发现顺序）、可裁剪候选
//!     （`PruneCandidate`）、按模块统计（`ReachStats`）、P5B 的收敛
//!     结果（`Convergence`，原样带入，不二次计算）；
//!   - 提供人类可读的文本摘要（`summarize`）；
//!   - 提供 Phase 5 的集成入口（`analyzeAll`）：按顺序接线
//!     computeRoots → ReachabilityAnalyzer.analyze → reachableModules
//!     → converge.converge → buildReport。
//!
//! 不属于本文件（硬边界）：
//!   - 不删除、不裁剪任何东西：裁剪是 Phase 6 的事。本文件只报告
//!     “哪些符号不可达、因何不可达”，不删符号、不改图、不改保留集。
//!     唯一的例外是 `analyzeAll` 按 P5B 的约定调用 `computeRoots`，
//!     而 `computeRoots` 会修改传入的 `RetainSet`（先调 `retainMain`
//!     再调 `retainGlobalInits`）；这是根计算的约定，不是裁剪，
//!     见 `analyzeAll` 的文档注释；
//!   - 不发明保留规则判定逻辑：保留规则的判定能力缺口见
//!     `retention.zig` 的 `rule_notes`（宏展开 / 反射 / 动态调用 /
//!     导出四条规则今天只登记文本，不做判定）；本文件只消费
//!     `RetainSet` 已登记的结果，不判定任何符号是否“应保留”；
//!   - 不做可达性分析本身（那是 P5A 的 `analyzer.zig`）、不算根
//!     （P5B 的 `roots.zig`）、不做模块收敛（P5B 的 `converge.zig`）。
//!
//! 输入契约：
//!   - `graph`：已建好的 `SymbolGraph`（Phase 4），节点为已定义符号
//!     集（`graph.nodes` 的 key），边为已记录的引用边（含 Flattener
//!     展开边；展开边与源码 import 边以 `RefKind` 区分，见
//!     `symbol_graph.zig`）；
//!   - `result`：P5A `ReachabilityAnalyzer.analyze` 对同一张图跑出
//!     的结果；`buildReport` 假定 `result` 与 `graph` 对应同一张图
//!     （若两者来自不同的图，可达集与定义集的差集无意义）；
//!   - `convergence`：P5B `converge` 对同一轮分析跑出的结果，原样
//!     带入，不二次计算；
//!   - `analyzeAll` 的 `retain` 为 `*RetainSet`：`computeRoots` 会
//!     修改它（先 `retainMain` 再 `retainGlobalInits`），调用方须
//!     传入可写的登记集，且不得假定调用后它保持不变。
//!
//! 所有权 / arena 规则（与 Phase 2 的 A8、Phase 3 的 loader、Phase 4
//! 的图一致）：
//!   - 调用方传入一个 arena 分配器；报告用它分配一切 owned 切片
//!     （`reachable` / `prunable` / `stats.modules`）；
//!   - `ReachabilityReport.deinit` 只释放这些容器与 owned 切片，不
//!     释放任何借用串（符号名、模块 path 均为调用方 arena 所有）；
//!   - `Convergence` 的三字段（`reachable_modules` /
//!     `converged_deps` / `module_only_modules`）假定为同一分配器
//!     分配的 owned 切片，随报告释放（P5B 约定；若 P5B 改为借用，
//!     协调时改 `freeConvergence` 一处）；
//!   - 报告不持有分析器内部存储的引用：`reachable` 切片由
//!     `result.reachableNodes(allocator)` 新分配；`prunable` 的节点
//!     值为拷贝（字符串仍借用）；分析器可在报告建好后释放。
//!
//! P5A / P5B 未落盘说明（本副本里还没有 `analyzer.zig` /
//! `roots.zig` / `converge.zig`，三文件由 P5A / P5B 在各自副本中
//! 编写）：本文件按任务约定的调用形状写 `@import` 与调用点，
//! `zig ast-check` 是 parse-only，不解析 import，故检查可通过；
//! 类型正确性与调用形状由协调合并时统一验证。约定的调用形状：
//!   - `roots_mod.computeRoots(graph, retain, entry_module, allocator)`
//!     返回 `[]RootEntry`（调用方释放切片本身）；
//!   - `analyzer_mod.ReachabilityAnalyzer.init(allocator)` 构造，
//!     `.analyze(graph, roots)` 分析，`.deinit()` 释放；
//!   - `result.reachableNodes(allocator)` /
//!     `result.reachableModules(allocator)` 返回 owned 切片；
//!   - `converge_mod.converge(symbol_graph, module_graph,
//!     reachable_modules, allocator)` 为自由函数，返回 `Convergence`。
//! 若 P5A / P5B 落盘的形状与此不同，协调时以落盘为准改本文件的
//! 调用点（只改调用点，不改报告结构）；见 MANIFEST §7.5。
//!
//! 已知缺口：
//!   - `PruneReason` 只有两档：若某条入边来自可达符号、节点本身却
//!     不可达，说明分析器与图不一致（正常不应发生）；此时仍归入
//!     `referenced_only_by_unreachable`（有入边，故不是
//!     `not_referenced`），调用方可用 `result.isReachable` /
//!     `result.reasonFor` 复核；见 `classifyPrune`；
//!   - 全边线性扫描：`classifyPrune` 对每个不可达符号扫描全部边
//!     （O(E) / 符号），与 P4B `reachableSymbols` 同款取舍；图变大
//!     再建邻接索引，不在 Phase 5 做（见 MANIFEST §7.5）；
//!   - `summarize` 只产纯文本，无结构化（JSON）输出；
//!   - facade（`src/reachability.zig`）由协调合并时写，本任务不写。
//!
//! 不属于本文件：build.zig 注册（后续 Phase / 协调方接线）；
//! P5A 的分析器、P5B 的根计算与收敛实现。

const std = @import("std");
const symbol_graph_mod = @import("../dependency_graph/symbol_graph.zig");
const module_graph_mod = @import("../dependency_graph/module_graph.zig");
const retention_mod = @import("../dependency_graph/retention.zig");
const analyzer_mod = @import("analyzer.zig");
const roots_mod = @import("roots.zig");
const converge_mod = @import("converge.zig");

// 复用，不重定义。
pub const ModuleId = symbol_graph_mod.ModuleId;
pub const SymbolNode = symbol_graph_mod.SymbolNode;
pub const SymbolKind = symbol_graph_mod.SymbolKind;
pub const SymbolRefEdge = symbol_graph_mod.SymbolRefEdge;
pub const ModuleDep = symbol_graph_mod.ModuleDep;
pub const RefKind = symbol_graph_mod.RefKind;
pub const SymbolGraph = symbol_graph_mod.SymbolGraph;
pub const ModuleGraph = module_graph_mod.ModuleGraph;
pub const RetainRule = retention_mod.RetainRule;
pub const RetainRuleSet = retention_mod.RetainRuleSet;
pub const RetainSet = retention_mod.RetainSet;
pub const ReachabilityAnalyzer = analyzer_mod.ReachabilityAnalyzer;
pub const ReachabilityResult = analyzer_mod.ReachabilityResult;
pub const ReachReason = analyzer_mod.ReachReason;
pub const RootEntry = roots_mod.RootEntry;
pub const Convergence = converge_mod.Convergence;
pub const ConvergedDep = converge_mod.ConvergedDep;
pub const ConvergedStatus = converge_mod.ConvergedStatus;

/// 候选被裁剪的原因（只描述“为何不可达”，不判定“能否删除”：
/// 保留规则、导出表等仍可能要求保留一个不可达符号，删除与否是
/// Phase 6 的事）。
pub const PruneReason = enum {
    /// 图中没有任何边指向它。
    not_referenced,
    /// 指向它的边全部来自不可达符号（逐条核对每条入边的 from 端
    /// 是否在可达集里；见 `classifyPrune`）。
    referenced_only_by_unreachable,
};

/// 一个可裁剪候选：已定义但不可达的符号，附其不可达原因。
/// `node` 与 `kind` 均为值拷贝（字符串仍借用调用方 arena）。
pub const PruneCandidate = struct {
    node: SymbolNode,
    kind: SymbolKind,
    reason: PruneReason,
};

/// 一个模块的可达性统计。
pub const ModuleStats = struct {
    module: ModuleId,
    /// 该模块内已定义（已登记）的符号数。
    defined: usize,
    /// 其中可达的符号数。
    reachable: usize,
    /// 其中不可达（可裁剪候选）的符号数。
    prunable: usize,
};

/// 全图的可达性统计。
pub const ReachStats = struct {
    /// 全图已定义符号总数（`graph.nodeCount()`）。
    total_defined: usize,
    /// 可达符号数（等于 `reachable.len`）。
    reachable_count: usize,
    /// 可裁剪候选数（等于 `prunable.len`）。
    prunable_count: usize,
    /// 按模块分表，按 module（package, path）字典序排过。
    modules: []ModuleStats,
};

/// 可达性报告：P5A 分析结果的整理形态。
///
/// `reachable` 按 P5A 的发现顺序（`result.reachableNodes` 的顺序）；
/// `prunable` 为全部已定义但不可达的符号（`graph.nodes` 的 key 减去
/// 可达集），顺序为图节点枚举序（未指定）；`convergence` 为 P5B 的
/// 结果，原样带入，不二次计算。
pub const ReachabilityReport = struct {
    /// 调用方传入的分配器（通常是 arena）；`deinit` 用它释放 owned 切片。
    allocator: std.mem.Allocator,
    /// 可达符号，按发现顺序。
    reachable: []SymbolNode,
    /// 可裁剪候选：已定义但不可达的全部符号。
    prunable: []PruneCandidate,
    /// 全图与按模块统计。
    stats: ReachStats,
    /// P5B 的收敛结果，原样带入。
    convergence: Convergence,

    /// 只释放报告自己拥有的容器与 owned 切片（`reachable` /
    /// `prunable` / `stats.modules` / `convergence` 的三字段）；
    /// 不释放任何借用串（符号名、模块 path 由调用方 arena 统一释放）。
    pub fn deinit(self: *ReachabilityReport) void {
        self.allocator.free(self.reachable);
        self.allocator.free(self.prunable);
        self.allocator.free(self.stats.modules);
        freeConvergence(self.allocator, &self.convergence);
    }
};

/// 释放 `Convergence` 的三个 owned 切片。
///
/// 约定：三字段均为与报告同一分配器分配的 owned 切片（P5B 约定）；
/// 若 P5B 落盘改为借用，协调时改此处一行（同时改
/// `ReachabilityReport.deinit` 与 `buildReport` 的 errdefer）。
fn freeConvergence(allocator: std.mem.Allocator, convergence: *const Convergence) void {
    allocator.free(convergence.reachable_modules);
    allocator.free(convergence.converged_deps);
    allocator.free(convergence.module_only_modules);
}

/// 判定一个不可达符号的裁剪原因：扫描图中全部边，核对指向它的
/// 每条入边的 from 端是否在可达集里。
///
///   - 没有任何边指向它 → `.not_referenced`；
///   - 有入边，且全部入边的 from 端都不可达 →
///     `.referenced_only_by_unreachable`。
///
/// 不一致情形（正常不应发生）：某条入边的 from 端可达、节点本身却
/// 不可达，说明分析器与图不一致；此时仍归入
/// `.referenced_only_by_unreachable`（有入边，故不是
/// `.not_referenced`），调用方可用 `result.isReachable` /
/// `result.reasonFor` 复核。枚举只有两档，无处可记第三种情形，
/// 见文件头“已知缺口”。
fn classifyPrune(
    graph: *const SymbolGraph,
    result: *const ReachabilityResult,
    node: SymbolNode,
) PruneReason {
    var has_incoming = false;
    for (graph.edges.items) |edge| {
        if (!edge.to.eql(node)) continue;
        has_incoming = true;
        // 入边来自可达符号：按分析器语义该节点本应可达（见上文
        // “不一致情形”）；此处不提前返回，继续核对剩余入边，
        // 最终仍归入 referenced_only_by_unreachable。
        _ = result.isReachable(edge.from);
    }
    if (!has_incoming) return .not_referenced;
    return .referenced_only_by_unreachable;
}

/// `ModuleStats` 的字典序比较：先比 package，再比 path。
fn moduleStatsLessThan(_: void, a: ModuleStats, b: ModuleStats) bool {
    const pkg = std.mem.order(u8, a.module.package, b.module.package);
    if (pkg != .eq) return pkg == .lt;
    return std.mem.order(u8, a.module.path, b.module.path) == .lt;
}

/// 写一个模块身份：`package/path`（package 为空时只写 path）。
fn writeModuleId(writer: anytype, id: ModuleId) !void {
    if (id.package.len > 0) {
        try writer.print("{s}/{s}", .{ id.package, id.path });
    } else {
        try writer.print("{s}", .{id.path});
    }
}

/// 从 P5A 的分析结果建报告。
///
///   - `reachable`：`result.reachableNodes(allocator)` 的原样返回
///     （发现顺序），所有权转移给报告；
///   - `prunable`：枚举 `graph.nodes` 的全部 key，减去可达集
///     （`result.isReachable` 逐个判定），逐个用 `classifyPrune`
///     定原因；`kind` 取图登记的 kind（`nodes` 表的值，即升级后
///     的真实 kind，而非节点自带的 kind 字段）；
///   - `stats`：`total_defined` 取 `graph.nodeCount()`；
///     `modules` 按 module 字典序排过；
///   - `convergence`：原样带入，不二次计算；调用后其所有权转移
///     给报告（建报告失败时由本函数的 errdefer 释放）。
///
/// 只做整理：不删除、不裁剪任何东西，不改图、不改保留集、不发明
/// 保留规则判定逻辑。
pub fn buildReport(
    graph: *const SymbolGraph,
    result: *const ReachabilityResult,
    convergence: Convergence,
    allocator: std.mem.Allocator,
) std.mem.Allocator.Error!ReachabilityReport {
    errdefer freeConvergence(allocator, &convergence);

    const reachable = try result.reachableNodes(allocator);
    errdefer allocator.free(reachable);

    var prunable = std.array_list.Managed(PruneCandidate).init(allocator);
    errdefer prunable.deinit();

    var stats_map = std.HashMap(ModuleId, ModuleStats, ModuleId.Context, std.hash_map.default_max_load_percentage).init(allocator);
    defer stats_map.deinit();

    var it = graph.nodes.iterator();
    while (it.next()) |entry| {
        const node = entry.key_ptr.*;
        const kind = entry.value_ptr.*;
        const slot = try stats_map.getOrPut(node.module);
        if (!slot.found_existing) {
            slot.value_ptr.* = .{
                .module = node.module,
                .defined = 0,
                .reachable = 0,
                .prunable = 0,
            };
        }
        slot.value_ptr.defined += 1;
        if (result.isReachable(node)) {
            slot.value_ptr.reachable += 1;
        } else {
            slot.value_ptr.prunable += 1;
            try prunable.append(.{
                .node = node,
                .kind = kind,
                .reason = classifyPrune(graph, result, node),
            });
        }
    }

    var modules = std.array_list.Managed(ModuleStats).init(allocator);
    errdefer modules.deinit();
    var mit = stats_map.valueIterator();
    while (mit.next()) |stats| {
        try modules.append(stats.*);
    }
    const modules_slice = try modules.toOwnedSlice();
    errdefer allocator.free(modules_slice);
    std.sort.block(ModuleStats, modules_slice, {}, moduleStatsLessThan);

    const prunable_slice = try prunable.toOwnedSlice();

    return .{
        .allocator = allocator,
        .reachable = reachable,
        .prunable = prunable_slice,
        .stats = .{
            .total_defined = graph.nodeCount(),
            .reachable_count = reachable.len,
            .prunable_count = prunable_slice.len,
            .modules = modules_slice,
        },
        .convergence = convergence,
    };
}

/// 人类可读的文本摘要：总数、可达数、可裁剪数（附两档原因拆分）、
/// 按模块分表、module_only 模块列表。
///
/// 只产纯文本，无结构化（JSON）输出（见文件头“已知缺口”）。
/// 返回 owned 字符串，调用方释放。摘要不列出单个可裁剪符号
/// （候选可能成千上万，逐个列出无意义；要看明细读
/// `report.prunable`）。
pub fn summarize(
    report: *const ReachabilityReport,
    allocator: std.mem.Allocator,
) std.mem.Allocator.Error![]u8 {
    var buf = std.array_list.Managed(u8).init(allocator);
    errdefer buf.deinit();
    const writer = buf.writer();

    var not_referenced: usize = 0;
    var only_by_unreachable: usize = 0;
    for (report.prunable) |candidate| {
        switch (candidate.reason) {
            .not_referenced => not_referenced += 1,
            .referenced_only_by_unreachable => only_by_unreachable += 1,
        }
    }

    try writer.print("可达性报告\n", .{});
    try writer.print("  已定义符号：{d}\n", .{report.stats.total_defined});
    try writer.print("  可达符号：{d}\n", .{report.stats.reachable_count});
    try writer.print("  可裁剪候选：{d}（无引用：{d}；仅被不可达符号引用：{d}）\n", .{
        report.stats.prunable_count,
        not_referenced,
        only_by_unreachable,
    });
    try writer.print("  可达模块（P5B 收敛）：{d}\n", .{report.convergence.reachable_modules.len});
    try writer.print("  已收敛的模块依赖：{d} 条\n", .{report.convergence.converged_deps.len});
    try writer.print("按模块（{d} 个）：\n", .{report.stats.modules.len});
    for (report.stats.modules) |module_stats| {
        try writer.print("  ", .{});
        try writeModuleId(writer, module_stats.module);
        try writer.print("：定义 {d}，可达 {d}，可裁剪 {d}\n", .{
            module_stats.defined,
            module_stats.reachable,
            module_stats.prunable,
        });
    }
    try writer.print("仅模块级导入的模块（module_only，{d} 个）：\n", .{report.convergence.module_only_modules.len});
    for (report.convergence.module_only_modules) |id| {
        try writer.print("  ", .{});
        try writeModuleId(writer, id);
        try writer.print("\n", .{});
    }

    return buf.toOwnedSlice();
}

/// Phase 5 的集成入口：按顺序接线，只做分析，不删除、不裁剪
/// 任何东西（裁剪是 Phase 6 的事）。
///
/// 接线顺序（五步，缺一不可，顺序固定）：
///   1. `computeRoots(symbol_graph, retain, entry_module, allocator)`
///      —— 算根。注意：它会修改传入的 `RetainSet`（先调
///      `retainMain` 再调 `retainGlobalInits`），调用方须传入
///      可写的登记集，且不得假定调用后它保持不变；
///   2. `ReachabilityAnalyzer.analyze(symbol_graph, roots)` ——
///      P5A 可达性分析（单遍遍历，无不动点迭代；见 MANIFEST §7.5）；
///   3. `result.reachableModules(allocator)` —— 取可达模块集；
///   4. `converge(symbol_graph, module_graph, reachable_modules,
///      allocator)` —— P5B 模块收敛；
///   5. `buildReport(symbol_graph, &result, convergence, allocator)`
///      —— 建报告。
///
/// 中间产物（`roots` / `reachable_modules` 切片）由本函数分配并
/// 在返回前释放：分析器与收敛器只拷贝它们需要的值，不保留切片
/// 本身。报告建好后，分析器即可释放（报告不持有分析器内部存储
/// 的引用，见文件头“所有权”）。
pub fn analyzeAll(
    module_graph: *const ModuleGraph,
    symbol_graph: *const SymbolGraph,
    retain: *RetainSet,
    entry_module: ModuleId,
    allocator: std.mem.Allocator,
) std.mem.Allocator.Error!ReachabilityReport {
    // 1. 根：会修改 retain（先 retainMain 再 retainGlobalInits）。
    const roots = try roots_mod.computeRoots(symbol_graph, retain, entry_module, allocator);
    defer allocator.free(roots);

    // 2. P5A 可达性分析。
    var analyzer = analyzer_mod.ReachabilityAnalyzer.init(allocator);
    defer analyzer.deinit();
    var result = try analyzer.analyze(symbol_graph, roots);

    // 3. 可达模块集。
    const reachable_modules = try result.reachableModules(allocator);
    defer allocator.free(reachable_modules);

    // 4. P5B 模块收敛（convergence 所有权随第 5 步转移给报告；
    // 建报告失败时由 buildReport 的 errdefer 释放，本函数不再
    // 另设 errdefer，避免重复释放）。
    const convergence = try converge_mod.converge(symbol_graph, module_graph, reachable_modules, allocator);

    // 5. 建报告。
    return buildReport(symbol_graph, &result, convergence, allocator);
}
