//! DCE 裁剪安全校验 —— SA 标准库模块化 Phase 6（P6B，sa-reachability DCE）。
//!
//! 职责：校验 P6A 产出的裁剪结果（`PrunedGraph`）是否满足裁剪不变量。
//! 只校验，不裁剪：本文件不删除任何符号、不修改任何图、不发明任何
//! 保留规则判定逻辑；发现问题只返回违规列表（空列表 = 通过），由调用
//! 方决定如何处理（报错 / 回退到未裁剪图 / 记日志）。
//!
//! 校验的 7 条不变量（`verifyPruned` 内按此编号逐项实现，缺一不可）：
//!   1. reachable_missing —— `report.reachable` 里的每个符号都在
//!      `pruned.symbols` 里；
//!   2. prunable_survived —— `report.prunable` 里每个符号（kind !=
//!      `.unknown` 的）都不在 `pruned.symbols` 里；
//!   3. dangling_edge —— `pruned.symbols` 的每条符号边两端都在
//!      `pruned.symbols` 里；每条 module_dep（以及模块图的每条边）两端
//!      都在 `pruned.modules` 里；
//!   4. retained_missing —— `retain` 里 `entry_point` 与 `global_init`
//!      两条规则保留的节点都在 `pruned.symbols` 里；
//!   5. unknown_pruned —— 原图里 kind == `.unknown` 的符号全部都在
//!      `pruned.symbols` 里（种类未知不得删除）；
//!   6. count_mismatch —— `removed_symbols.len + pruned 符号数 == 原图
//!      符号数`；`removed_edges == 原图边数 - pruned 边数`；
//!   7. pruned_module_survived —— `removed_modules` 里的模块不在
//!      `pruned.modules` 里；`report.convergence` 的 module_only 模块
//!      仍在 `pruned.modules` 里。
//!
//! 协调说明（P6A 并行实现）：
//!   - `RemovedSymbol` / `PrunedGraph` 在本文件按任务书契约声明，P6A
//!     按同一契约产出裁剪结果；P6A 的文件不在本副本里，协调合并时以
//!     落盘形状为准对齐（本文件声明的字段名 / 类型以任务书为准）；
//!   - `SymbolGraph` 与 `ModuleGraph` 只有 add API、没有 remove/delete
//!     API（append-only），裁剪产出的是一个全新的 `PrunedGraph`，本
//!     文件校验它，不改原图。
//!
//! 保留规则边界（提案 §3 末尾；`retention.zig` 的 `rule_notes`）：
//!   - 只有 `entry_point`（main）与 `global_init` 有真实执行逻辑，本
//!     文件只核对 `RetainSet` 里已按这两条规则登记的节点是否幸存；
//!   - `macro_expanded` / `reflective` / `dynamic_call` / `exported`
//!     今天只登记文本、无判定逻辑，本文件不发明判定逻辑、不猜测哪些
//!     符号“应保留”，只核对登记集本身。
//!
//! 所有权 / arena 规则（与 Phase 2 的 A8、Phase 4 的图、Phase 5 的报告一致）：
//!   - `PrunedGraph` 拥有 `removed_symbols` / `removed_modules` 两个切片
//!     与 `symbols` / `modules` 两个子图；`deinit` 只释放容器本身，不释
//!     放任何借用串（符号名、模块 path 均由调用方 arena 统一释放）；
//!   - `verifyPruned` 返回的 `[]DceViolation` 为 owned 切片，调用方释放
//!     切片本身；`DceViolation.detail` 均为静态字面量（借用，不拥有），
//!     `node` 为值拷贝（字符串仍借用调用方 arena）；
//!   - `countStats` 不分配、不拥有任何东西。
//!
//! 口径说明：
//!   - `removed_edges` 计符号引用边（`SymbolGraph.edgeCount()`），不含
//!     模块级依赖（`moduleDepCount()` 另计）；不变量 6 的边数方程按此口径；
//!   - 不变量 6 的符号数方程中，kind == `.unknown` 的幸存者计在 kept 侧
//!     （`pruned` 符号数内），不计入 `removed_symbols`；
//!   - 不变量 4 按字面核对：`RetainSet` 里登记了 `entry_point` /
//!     `global_init` 的节点必须在 `pruned.symbols` 里，即使该节点在原
//!     图里未定义（入口缺失本身就是问题，不静默放过）。
//!
//! 不属于本文件：裁剪实现（P6A）；可达性分析（P5A）；根计算与模块收敛
//! （P5B）；build.zig 注册（后续 Phase / 协调方接线）。

const std = @import("std");
const symbol_graph_mod = @import("../dependency_graph/symbol_graph.zig");
const module_graph_mod = @import("../dependency_graph/module_graph.zig");
const retention_mod = @import("../dependency_graph/retention.zig");
const report_mod = @import("../reachability/report.zig");
const pruner_mod = @import("pruner.zig");

// 复用，不重定义。
pub const ModuleId = symbol_graph_mod.ModuleId;
pub const SymbolNode = symbol_graph_mod.SymbolNode;
pub const SymbolKind = symbol_graph_mod.SymbolKind;
pub const SymbolGraph = symbol_graph_mod.SymbolGraph;
pub const ModuleGraph = module_graph_mod.ModuleGraph;
pub const RetainRule = retention_mod.RetainRule;
pub const RetainRuleSet = retention_mod.RetainRuleSet;
pub const RetainSet = retention_mod.RetainSet;
pub const ReachabilityReport = report_mod.ReachabilityReport;
pub const PruneCandidate = report_mod.PruneCandidate;
pub const PruneReason = report_mod.PruneReason;
pub const Convergence = report_mod.Convergence;

/// 一个被裁剪掉的符号：原图节点 + 裁剪时登记的 kind + 裁剪原因。
/// `node` 为值拷贝（字符串仍借用调用方 arena）。
// 正本在 pruner.zig（P6A 产出，M1）；本文件只转发，不重定义。
pub const RemovedSymbol = pruner_mod.RemovedSymbol;

/// 裁剪产出：一个全新的图（P6A 产出，本文件只校验）。
///
/// 契约（任务书；P6A 按同一契约产出，协调合并时以落盘为准）：
///   - `symbols` / `modules` 为裁剪后幸存的符号图与模块图；
///   - `removed_symbols` 为被删符号的记录（顺序未指定）；
///   - `removed_edges` 为被删的符号引用边数（见文件头口径：只计
///     `SymbolGraph.edgeCount()` 口径的符号边，不含模块级依赖）；
///   - `removed_modules` 为被删模块的记录（顺序未指定）。
// 正本在 pruner.zig（P6A 产出，M1）；本文件只转发，不重定义。
pub const PrunedGraph = pruner_mod.PrunedGraph;

/// 一条 DCE 违规的种类（与 7 条不变量一一对应；`count_mismatch` 覆盖
/// 不变量 6 的两条计数方程及其记录完整性子检查，见 `verifyPruned`）。
pub const DceViolationKind = enum {
    /// 不变量 1：可达符号在裁剪后丢失。
    reachable_missing,
    /// 不变量 2：可裁剪符号在裁剪后幸存。
    prunable_survived,
    /// 不变量 3：裁剪后图的边端点缺失（悬空边）。
    dangling_edge,
    /// 不变量 7：已裁剪模块在裁剪后幸存（或 module_only 模块丢失）。
    pruned_module_survived,
    /// 不变量 4：保留规则要求保留的符号在裁剪后丢失。
    retained_missing,
    /// 不变量 5：种类未知的符号被删除。
    unknown_pruned,
    /// 不变量 6：删除记录的数量与原图 / 裁剪后图的数量对不上。
    count_mismatch,
};

/// 一条 DCE 违规：种类 + 涉事符号（模块级违规为 null）+ 说明。
///
/// `detail` 均为静态字面量，只借用、不拥有；`node` 为值拷贝（字符串
/// 仍借用调用方 arena）。违规列表本身（切片）由 `verifyPruned` 分配，
/// 调用方释放切片本身。
pub const DceViolation = struct {
    kind: DceViolationKind,
    node: ?SymbolNode,
    detail: []const u8,
};

/// 裁剪统计：按 kind / 按原因拆分的删除数，以及删除 / 保留的边、模块、
/// 符号数。
///
/// 下标约定（与枚举声明顺序无关，用 `kindIndex` / `reasonIndex` 的
/// switch 固定映射，枚举重排也不影响分桶）：
///   - `removed_by_kind`：0=function，1=global，2=type，3=macro，
///     4=unknown；
///   - `removed_by_reason`：0=not_referenced，
///     1=referenced_only_by_unreachable。
pub const DceStats = struct {
    removed_by_kind: [5]usize,
    removed_by_reason: [2]usize,
    removed_edges: usize,
    removed_modules: usize,
    kept_symbols: usize,
    kept_modules: usize,
};

/// `SymbolKind` → `removed_by_kind` 下标（固定映射，不依赖枚举序）。
fn kindIndex(kind: SymbolKind) usize {
    return switch (kind) {
        .function => 0,
        .global => 1,
        .type => 2,
        .macro => 3,
        .unknown => 4,
    };
}

/// `PruneReason` → `removed_by_reason` 下标（固定映射，不依赖枚举序）。
fn reasonIndex(reason: PruneReason) usize {
    return switch (reason) {
        .not_referenced => 0,
        .referenced_only_by_unreachable => 1,
    };
}

/// 往违规列表里追加一条违规（内部辅助）。
fn addViolation(
    list: *std.array_list.Managed(DceViolation),
    kind: DceViolationKind,
    node: ?SymbolNode,
    detail: []const u8,
) std.mem.Allocator.Error!void {
    try list.append(.{ .kind = kind, .node = node, .detail = detail });
}

/// 校验裁剪结果是否满足 7 条不变量。
///
/// 只读五个输入，不修改任何图、报告或保留集；只借用字符串，不拥有。
/// 返回 owned 违规列表，调用方释放切片本身；空列表 = 通过（7 条不变量
/// 全部满足）。返回的 `detail` 均为静态字面量，`node` 为值拷贝。
///
/// 各不变量的实现位置（按编号）：
///   1. `report.reachable` 逐个查 `pruned.symbols.containsSymbol`；
///   2. `report.prunable` 中 kind != `.unknown` 者逐个查不在
///      `pruned.symbols` 里（`.unknown` 的候选豁免，见不变量 5）；
///   3. `pruned.symbols` 的每条符号边、每条 module_dep、以及
///      `pruned.modules` 的每条模块边，逐条核对两端在位；
///   4. `retain.retainedNodes` 中规则集含 `entry_point` 或 `global_init`
///      的节点，逐个查在 `pruned.symbols` 里（其余规则只登记文本、无
///      判定逻辑，不发明判定、不核对）；
///   5. 原图 `nodes` 表中 kind == `.unknown` 的节点逐个查在
///      `pruned.symbols` 里；
///   6. 两条计数方程（符号数方程、边数方程），外加两条记录完整性子检查
///      （`removed_symbols` / `removed_modules` 的每条记录都应在原图
///      里——删掉的东西必须曾经存在）；
///   7. `removed_modules` 逐个查不在 `pruned.modules` 里；
///      `report.convergence.module_only_modules` 逐个查仍在
///      `pruned.modules` 里。
pub fn verifyPruned(
    original_symbols: *const SymbolGraph,
    original_modules: *const ModuleGraph,
    pruned: *const PrunedGraph,
    report: *const ReachabilityReport,
    retain: *const RetainSet,
    allocator: std.mem.Allocator,
) std.mem.Allocator.Error![]DceViolation {
    var violations = std.array_list.Managed(DceViolation).init(allocator);
    errdefer violations.deinit();

    // 不变量 1：reachable_missing——可达符号一个都不能丢。
    for (report.reachable) |node| {
        if (!pruned.symbols.containsSymbol(node)) {
            try addViolation(&violations, .reachable_missing, node, "可达符号在裁剪后丢失");
        }
    }

    // 不变量 2：prunable_survived——可裁剪候选（kind 已知者）一个都
    // 不能幸存；kind == .unknown 的候选豁免（见不变量 5）。
    for (report.prunable) |candidate| {
        if (candidate.kind == .unknown) continue;
        if (pruned.symbols.containsSymbol(candidate.node)) {
            try addViolation(&violations, .prunable_survived, candidate.node, "可裁剪符号在裁剪后幸存");
        }
    }

    // 不变量 3：dangling_edge——裁剪后图的边两端必须都在位。
    // 3a. 符号引用边的两端都在 pruned.symbols 里。
    for (pruned.symbols.edges.items) |edge| {
        if (!pruned.symbols.containsSymbol(edge.from)) {
            try addViolation(&violations, .dangling_edge, edge.from, "裁剪后符号边的 from 端不在裁剪后符号图里");
        }
        if (!pruned.symbols.containsSymbol(edge.to)) {
            try addViolation(&violations, .dangling_edge, edge.to, "裁剪后符号边的 to 端不在裁剪后符号图里");
        }
    }
    // 3b. 模块级依赖（SymbolGraph.module_deps）的两端模块都在
    // pruned.modules 里。
    for (pruned.symbols.module_deps.items) |dep| {
        if (!pruned.modules.contains(dep.from)) {
            try addViolation(&violations, .dangling_edge, null, "裁剪后模块依赖的 from 模块不在裁剪后模块图里");
        }
        if (!pruned.modules.contains(dep.to)) {
            try addViolation(&violations, .dangling_edge, null, "裁剪后模块依赖的 to 模块不在裁剪后模块图里");
        }
    }
    // 3c. 模块图边的两端模块都在 pruned.modules 里（模块图加边时自动
    // 补建端点节点，合规的裁剪后模块图不应出现悬空模块边）。
    for (pruned.modules.edges.items) |edge| {
        if (!pruned.modules.contains(edge.from)) {
            try addViolation(&violations, .dangling_edge, null, "裁剪后模块边的 from 模块不在裁剪后模块图里");
        }
        if (!pruned.modules.contains(edge.to)) {
            try addViolation(&violations, .dangling_edge, null, "裁剪后模块边的 to 模块不在裁剪后模块图里");
        }
    }

    // 不变量 4：retained_missing——entry_point / global_init 保留的
    // 节点必须幸存。只核对登记集本身（`retainedNodes` / `rulesFor`），
    // 不发明任何保留判定逻辑；其余规则（macro_expanded / reflective /
    // dynamic_call / exported）只登记文本，不核对。
    const retained = try retain.retainedNodes(allocator);
    defer allocator.free(retained);
    for (retained) |node| {
        const rules = retain.rulesFor(node);
        if (!rules.contains(.entry_point) and !rules.contains(.global_init)) continue;
        if (!pruned.symbols.containsSymbol(node)) {
            try addViolation(&violations, .retained_missing, node, "保留规则（entry_point/global_init）要求保留的符号在裁剪后丢失");
        }
    }

    // 不变量 5：unknown_pruned——原图里 kind == .unknown 的符号全部
    // 幸存（种类未知不得删除）。
    var it = original_symbols.nodes.iterator();
    while (it.next()) |entry| {
        if (entry.value_ptr.* != .unknown) continue;
        const node = entry.key_ptr.*;
        if (!pruned.symbols.containsSymbol(node)) {
            try addViolation(&violations, .unknown_pruned, node, "种类未知的符号被删除");
        }
    }

    // 不变量 6：count_mismatch——两条计数方程 + 记录完整性子检查。
    // 6a. 符号数方程：removed + kept == 原图符号数（unknown 幸存者计
    // 在 kept 侧，不计入 removed，见文件头口径说明）。
    if (pruned.removed_symbols.len + pruned.symbols.nodeCount() != original_symbols.nodeCount()) {
        try addViolation(&violations, .count_mismatch, null, "删除符号数 + 保留符号数与原图符号数不一致");
    }
    // 6b. 边数方程：removed_edges == 原图边数 - pruned 边数（符号引用
    // 边口径；pruned 边数多于原图边数时同样判违规）。
    const orig_edges = original_symbols.edgeCount();
    const pruned_edges = pruned.symbols.edgeCount();
    if (pruned_edges > orig_edges or pruned.removed_edges != orig_edges - pruned_edges) {
        try addViolation(&violations, .count_mismatch, null, "删除边数与原图边数减裁剪后边数不一致");
    }
    // 6c. 记录完整性：删掉的符号必须曾经在原图里。
    for (pruned.removed_symbols) |removed| {
        if (!original_symbols.containsSymbol(removed.node)) {
            try addViolation(&violations, .count_mismatch, removed.node, "删除记录中的符号在原图里不存在");
        }
    }
    // 6d. 记录完整性：删掉的模块必须曾经在原图里。
    for (pruned.removed_modules) |id| {
        if (!original_modules.contains(id)) {
            try addViolation(&violations, .count_mismatch, null, "删除记录中的模块在原图里不存在");
        }
    }

    // 不变量 7：pruned_module_survived。
    // 7a. removed_modules 里的模块不在 pruned.modules 里。
    for (pruned.removed_modules) |id| {
        if (pruned.modules.contains(id)) {
            try addViolation(&violations, .pruned_module_survived, null, "已裁剪模块在裁剪后模块图里幸存");
        }
    }
    // 7b. module_only 模块（按 report.convergence）仍在 pruned.modules
    // 里：仅模块级导入的模块没有符号级可达证据，但模块本身仍被需要，
    // 不得随符号裁剪一起删掉。
    for (report.convergence.module_only_modules) |id| {
        if (!pruned.modules.contains(id)) {
            try addViolation(&violations, .pruned_module_survived, null, "module_only 模块在裁剪后模块图里丢失");
        }
    }

    return violations.toOwnedSlice();
}

/// 统计裁剪结果：按 kind / 按原因拆分的删除数，以及删除 / 保留的
/// 边、模块、符号数。
///
/// 计数全部取自 `pruned` 自身的删除记录与幸存图（`removed_symbols` /
/// `removed_edges` / `removed_modules` / `symbols.nodeCount()` /
/// `modules.nodeCount()`），不做跨图核对（跨图一致性是 `verifyPruned`
/// 不变量 6 的事）；`original_symbols` 与 `allocator` 仅为与
/// `verifyPruned` 对称的调用形状而保留，本函数不使用它们（不分配）。
pub fn countStats(
    original_symbols: *const SymbolGraph,
    pruned: *const PrunedGraph,
    allocator: std.mem.Allocator,
) DceStats {
    _ = original_symbols;
    _ = allocator;

    var stats = DceStats{
        .removed_by_kind = .{ 0, 0, 0, 0, 0 },
        .removed_by_reason = .{ 0, 0 },
        .removed_edges = pruned.removed_edges,
        .removed_modules = pruned.removed_modules.len,
        .kept_symbols = pruned.symbols.nodeCount(),
        .kept_modules = pruned.modules.nodeCount(),
    };
    for (pruned.removed_symbols) |removed| {
        stats.removed_by_kind[kindIndex(removed.kind)] += 1;
        stats.removed_by_reason[reasonIndex(removed.reason)] += 1;
    }
    return stats;
}
