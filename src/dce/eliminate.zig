//! Dead Code Elimination 集成入口与报告 —— SA 标准库模块化 Phase 6（P6C，sa-dce）。
//!
//! 职责（只做接线与报告）：
//!   - 提供 Phase 6 的集成入口（`eliminate`）：按固定五步接线
//!     Phase 5 的可达性分析（`analyzeAll`）→ P6A 的裁剪（`prune`）
//!     → P6B 的校验（`verifyPruned`）→ 定 outcome → 返回 `DceResult`；
//!   - 定义 DCE 的结果类型（`RemovedSymbol` / `PrunedGraph` /
//!     `DceViolationKind` / `DceViolation` / `DceOutcome` /
//!     `DceResult`），供 P6A / P6B 与调用方共享；
//!   - 提供人类可读的文本摘要（`summarizeDce`）。
//!
//! 不属于本文件（硬边界）：
//!   - 不实现裁剪本身：把哪些符号、边、模块从图里拿掉，是 P6A 的
//!     `prune` 的事（产出全新的 `PrunedGraph`）；本文件只接线，
//!     不直接建新图、不删符号、不改原图；
//!   - 不实现校验本身：裁剪后的图是否满足“可达的都在、该删的都删
//!     了、无悬空边”，是 P6B 的 `verifyPruned` 的事；本文件只
//!     消费它返回的违规列表，不判定任何一条违规、不补任何检查；
//!   - 不发明保留规则判定逻辑：保留规则的判定能力缺口见
//!     `retention.zig` 的 `rule_notes`（宏展开 / 反射 / 动态调用 /
//!     导出四条规则今天只登记文本，不做判定）；本文件只消费
//!     `analyzeAll` 已算好的报告，不判定任何符号是否“应保留”；
//!   - 不做可达性分析本身（那是 Phase 5 的 `analyzeAll`）、不算根、
//!     不做模块收敛（那是 P5B 的 `converge`，已包在 `analyzeAll` 里）。
//!
//! 关键事实（提案 §3 与 Phase 4 落盘）：
//!   - `SymbolGraph` 与 `ModuleGraph` 都只有 add API，没有
//!     remove / delete API（append-only）；裁剪绝不在原图上删东西，
//!     而是产出全新的 `PrunedGraph`（P6A），原图原样不动；
//!   - `analyzeAll` 的 `retain` 为 `*RetainSet`：`computeRoots` 会
//!     修改它（先 `retainMain` 再 `retainGlobalInits`），调用方须
//!     传入可写的登记集，且不得假定调用后它保持不变（见 Phase 5
//!     `report.zig` 的 `analyzeAll` 文档注释）；
//!   - `PruneReason` 只有两档（`not_referenced` /
//!     `referenced_only_by_unreachable`）；`SymbolKind` 只有五档
//!     （`function` / `global` / `type` / `macro` / `unknown`）；
//!     `RetainRule` 只有 `entry_point` 与 `global_init` 有真实
//!     执行逻辑，其余只登记文本、无判定逻辑。
//!
//! `eliminate` 的五步（缺一不可，顺序固定；见 `eliminate` 的文档注释）：
//!   1. `analyzeAll` —— 得 `ReachabilityReport`；
//!   2. `prune` —— 得 `PrunedGraph`（P6A）；
//!   3. `verifyPruned` —— 得违规列表 `[]DceViolation`（P6B）；
//!   4. 定 outcome：违规非空 → `.verification_failed`；否则
//!      prunable 为空 → `.nothing_to_prune`；否则 → `.pruned`；
//!   5. 返回 `DceResult`（拥有 report / pruned / violations）。
//!
//! outcome 三态的优先级（第 4 步的唯一判定式）：
//!   - 违规非空时 outcome 一律是 `.verification_failed`，无论
//!     prunable 是否为空——校验失败压倒“无事可删”；
//!   - 违规为空且 prunable 为空时才是 `.nothing_to_prune`，此时仍
//!     产出 `PrunedGraph`（与原图等价的空裁剪结果），不返回 null；
//!   - 违规为空且 prunable 非空时是 `.pruned`。
//! 违规非空时 `DceResult` 仍保留 `PrunedGraph` 与违规列表供诊断，
//! 不静默丢弃（见 `eliminate` 的文档注释）。
//!
//! 所有权 / arena 规则（与 Phase 2 的 A8、Phase 3 的 loader、Phase 4
//! 的图、Phase 5 的报告一致）：
//!   - 调用方传入一个 arena 分配器；`DceResult` 用它分配一切 owned
//!     切片（`pruned.removed_symbols` / `pruned.removed_modules` /
//!     `violations`；`report` 内切片的分配见 Phase 5 `report.zig`）；
//!   - `DceResult` 拥有 `report` / `pruned` / `violations` 三者，
//!     `deinit` 统一释放；调用方只调一次 `DceResult.deinit`，不得
//!     再单独释放其中的 `report` 或 `pruned`（避免重复释放）；
//!   - `violations` 切片本身由 `DceResult.deinit` 释放，释放用的
//!     分配器取 `report.allocator`——约定：`verifyPruned` 须用与
//!     `eliminate` 同一个分配器分配该切片（见对齐点 C3）；
//!   - `DceViolation.detail` 为借用串（字面量或调用方 arena 所有），
//!     `deinit` 只释放 `violations` 切片本身，不释放每条 `detail`
//!     （与全仓“类型只借用字符串”的口径一致；若 P6B 落盘改为
//!     detail 由校验器拥有，合并时改 `DceResult.deinit` 一处，
//!     见对齐点 C3）；
//!   - `PrunedGraph.deinit` 只释放 `removed_symbols` /
//!     `removed_modules` 两个切片本身与 `symbols` / `modules`
//!     两张图的容器（两张图的 `deinit` 只释容器，不释借用串）；
//!     长度为 0 的切片不释放（它可能是一段编译期空切片，而非
//!     分配器产物；与 P5B `Convergence.deinit` 同款口径）；
//!   - `eliminate` 的中间失败（`prune` / `verifyPruned` 报
//!     `OutOfMemory`）由本函数的 errdefer 清理已得的中间产物，
//!     不留半成品 `DceResult`。
//!
//! 合并已完成（协调 agent，M1–M4）：P6A 的 `pruner.zig` 与 P6B 的
//! `guard.zig` 已落盘，调用形状以落盘为准（见 MANIFEST §5 对齐点
//! C2 / C3）：`prune(symbol_graph, module_graph, report,
//! allocator) !PrunedGraph`；`verifyPruned(symbol_graph,
//! module_graph, pruned, report, retain, allocator)
//! ![]DceViolation`——P6B 落盘的签名比 P6C 假设多一个 `retain`
//! 参数（校验不变量 4 需读保留集），本文件调用点已按落盘补齐。
//!   - `pruner_mod.prune(symbol_graph, module_graph, report,
//!     allocator) !PrunedGraph`——输入原两张图与 Phase 5 报告，
//!     返回全新的裁剪后图；
//!   - `guard_mod.verifyPruned(symbol_graph, module_graph, pruned,
//!     report, retain, allocator) ![]DceViolation`——输入原两张图、
//!     裁剪
//!     后图与 Phase 5 报告，返回违规列表（空 = 通过）；
//!   - 两者的错误集均为 `std.mem.Allocator.Error`（只报分配失败；
//!     校验发现的问题一律记进返回的违规列表，不以 error 形式报出）。
//!
//! 类型正本说明（见 MANIFEST §5 对齐点 C1 / C4）：`RemovedSymbol` /
//! `PrunedGraph` 的正本在 P6A 的 `pruner.zig`，`DceViolationKind` /
//! `DceViolation` 的正本在 P6B 的 `guard.zig`；本文件只转发
//! （re-export），不留两份定义。三处落盘的字段形状逐字一致，
//! 以正本为准。
//!
//! 已知缺口：
//!   - `prune` / `verifyPruned` 的调用形状已按落盘对齐（C2 / C3），
    //!     但未经编译验证（只跑 ast-check，见 MANIFEST §8）；
//!   - `summarizeDce` 只产纯文本，无结构化（JSON）输出；不逐个
//!     列出被删符号（被删符号可能成千上万，逐个列出无意义；要看
//!     明细读 `result.pruned.?.removed_symbols`）；
//!   - facade（`src/dce.zig`）由协调合并时写，本任务不写；
//!   - build.zig 注册（后续 Phase / 协调方接线），本任务不做。
//!
//! 不属于本文件：build.zig 注册（后续 Phase / 协调方接线）；
//! P6A 的裁剪、P6B 的校验实现。

const std = @import("std");
const symbol_graph_mod = @import("../dependency_graph/symbol_graph.zig");
const module_graph_mod = @import("../dependency_graph/module_graph.zig");
const retention_mod = @import("../dependency_graph/retention.zig");
const report_mod = @import("../reachability/report.zig");
const pruner_mod = @import("pruner.zig");
const guard_mod = @import("guard.zig");

// 复用，不重定义。
pub const ModuleId = symbol_graph_mod.ModuleId;
pub const SymbolNode = symbol_graph_mod.SymbolNode;
pub const SymbolKind = symbol_graph_mod.SymbolKind;
pub const SymbolGraph = symbol_graph_mod.SymbolGraph;
pub const ModuleGraph = module_graph_mod.ModuleGraph;
pub const RetainRule = retention_mod.RetainRule;
pub const RetainSet = retention_mod.RetainSet;
pub const PruneReason = report_mod.PruneReason;
pub const PruneCandidate = report_mod.PruneCandidate;
pub const ReachabilityReport = report_mod.ReachabilityReport;
pub const analyzeAll = report_mod.analyzeAll;

/// 一个被删除的符号：原节点（值拷贝，字符串仍借用调用方 arena）+ 图
/// 登记的 kind + 裁剪原因（Phase 5 报告的 `PruneReason` 两档）。
// 正本在 pruner.zig（P6A 产出，M1）；本文件只转发，不重定义。
pub const RemovedSymbol = pruner_mod.RemovedSymbol;

/// 裁剪后的图：全新的两张图（只含保留内容，原图不动）+ 删除清单。
///
/// `symbols` / `modules` 为 P6A 新建的图（只含可达符号与保留模块，
/// 以及它们之间的边；`SymbolGraph` / `ModuleGraph` 均无 remove API，
/// 故裁剪只能产新图，不能在原图上删）；`removed_symbols` 为全部被
/// 删符号（与 Phase 5 报告的 `prunable` 对应，顺序为 P6A 的裁剪
/// 顺序，未指定）；`removed_edges` 为删除的符号引用边数；
/// `removed_modules` 为整模块被删的模块（其内符号全不可达）。
// 正本在 pruner.zig（P6A 产出，M1）；本文件只转发，不重定义。
pub const PrunedGraph = pruner_mod.PrunedGraph;

/// 一条 DCE 校验违规的种类（P6B 的 `verifyPruned` 返回，空 = 通过）。
// 正本在 guard.zig（P6B 产出，M2）；本文件只转发，不重定义。
pub const DceViolationKind = guard_mod.DceViolationKind;

/// 一条 DCE 校验违规：种类 + 相关节点（无相关节点时为 null）+
/// 说明文本（借用串，见文件头“所有权”，`deinit` 不释放它）。
// 正本在 guard.zig（P6B 产出，M2）；本文件只转发，不重定义。
pub const DceViolation = guard_mod.DceViolation;

/// `eliminate` 的结果状态（三态，见文件头“outcome 三态的优先级”）。
pub const DceOutcome = enum {
    /// 校验通过，且删掉了东西。
    pruned,
    /// 校验通过，但无事可删（prunable 为空；仍产出 `PrunedGraph`）。
    nothing_to_prune,
    /// 校验失败（违规列表非空；仍保留 `PrunedGraph` 与违规列表供诊断）。
    verification_failed,
};

/// `eliminate` 的结果：outcome + 裁剪后图 + 违规列表 + Phase 5 报告。
///
/// `DceResult` 拥有三者（`report` / `pruned` / `violations`），
/// `deinit` 统一释放；调用方只调一次 `DceResult.deinit`，不得再
/// 单独释放其中的 `report` 或 `pruned`。`pruned` 在三态下均为
/// 非 null（`nothing_to_prune` 与 `verification_failed` 也产出
/// `PrunedGraph`）；`violations` 在通过时为空切片。
pub const DceResult = struct {
    outcome: DceOutcome,
    pruned: ?PrunedGraph,
    violations: []DceViolation,
    report: ReachabilityReport,

    /// 统一释放本结果拥有的三者：`pruned`（若有）、`violations`
    /// 切片本身（释放用 `report.allocator`；`detail` 为借用串，
    /// 不释放，见文件头“所有权”）、`report`。调用后实例不可再用。
    pub fn deinit(self: *DceResult) void {
        if (self.pruned) |*pruned| pruned.deinit();
        if (self.violations.len > 0) self.report.allocator.free(self.violations);
        self.report.deinit();
        self.* = undefined;
    }
};

/// 写一个模块身份：`package/path`（package 为空时只写 path）。
/// 与 Phase 5 `report.zig` 的同名辅助同款写法。
fn writeModuleId(writer: anytype, id: ModuleId) !void {
    if (id.package.len > 0) {
        try writer.print("{s}/{s}", .{ id.package, id.path });
    } else {
        try writer.print("{s}", .{id.path});
    }
}

/// Phase 6 的集成入口：按顺序接线，只做分析与裁剪的接线，不直接
/// 建新图、不删符号、不判定任何保留规则（见文件头“硬边界”）。
///
/// 接线顺序（五步，缺一不可，顺序固定）：
///   1. `analyzeAll(module_graph, symbol_graph, retain, entry_module,
///      allocator)` —— Phase 5 可达性分析，得 `ReachabilityReport`。
///      注意：它会修改传入的 `RetainSet`（先 `retainMain` 再
///      `retainGlobalInits`），调用方须传入可写的登记集；
///   2. `prune(symbol_graph, module_graph, &report, allocator)` ——
///      P6A 裁剪，得全新的 `PrunedGraph`（原图不动）；
///   3. `verifyPruned(symbol_graph, module_graph, &pruned, &report,
///      retain, allocator)` —— P6B 校验，得违规列表（空 = 通过）；
///   4. 定 outcome：违规非空 → `.verification_failed`；否则
///      prunable 为空 → `.nothing_to_prune`（仍产出 `PrunedGraph`）；
///      否则 → `.pruned`；
///   5. 返回 `DceResult`（拥有 report / pruned / violations）。
///
/// 失败语义：只报分配失败（`std.mem.Allocator.Error`）。校验发现
/// 的问题不以 error 形式报出，而是记进返回的 `DceResult.violations`
///（outcome 为 `.verification_failed`，`PrunedGraph` 与违规列表
/// 仍保留供诊断，不静默丢弃）。中间步骤报分配失败时，已得的中间
/// 产物由 errdefer 清理，不留半成品 `DceResult`。
pub fn eliminate(
    module_graph: *const ModuleGraph,
    symbol_graph: *const SymbolGraph,
    retain: *RetainSet,
    entry_module: ModuleId,
    allocator: std.mem.Allocator,
) std.mem.Allocator.Error!DceResult {
    // 1. Phase 5 可达性分析（会修改 retain，见上文）。
    var report = try analyzeAll(module_graph, symbol_graph, retain, entry_module, allocator);
    errdefer report.deinit();

    // 2. P6A 裁剪：产出全新的 PrunedGraph（原图不动）。
    var pruned = try pruner_mod.prune(symbol_graph, module_graph, &report, allocator);
    errdefer pruned.deinit();

    // 3. P6B 校验：违规列表（空 = 通过）。
    const violations = try guard_mod.verifyPruned(symbol_graph, module_graph, &pruned, &report, retain, allocator);
    errdefer allocator.free(violations);

    // 4. 定 outcome（优先级：违规非空 > prunable 为空 > 否则 pruned）。
    const outcome: DceOutcome = if (violations.len > 0)
        .verification_failed
    else if (report.prunable.len == 0)
        .nothing_to_prune
    else
        .pruned;

    // 5. 返回 DceResult（所有权转移：report / pruned / violations）。
    return .{
        .outcome = outcome,
        .pruned = pruned,
        .violations = violations,
        .report = report,
    };
}

/// 人类可读的文本摘要：总定义数、可达数、删除数（按 kind 五档与
/// reason 两档拆分）、删除边数、删除模块数、保留模块数、module_only
/// 模块列表、outcome 一行。
///
/// 只产纯文本，无结构化（JSON）输出（见文件头“已知缺口”）。返回
/// owned 字符串，调用方释放。摘要不逐个列出被删符号（被删符号可能
/// 成千上万，逐个列出无意义；要看明细读
/// `result.pruned.?.removed_symbols`）。`pruned` 为 null 时删除
/// 侧数字全按 0 计（`eliminate` 的三态下它均为非 null；此处只作
/// 防御，不断言）。
pub fn summarizeDce(
    result: *const DceResult,
    allocator: std.mem.Allocator,
) std.mem.Allocator.Error![]u8 {
    var buf = std.array_list.Managed(u8).init(allocator);
    errdefer buf.deinit();
    const writer = buf.writer();

    var removed_count: usize = 0;
    var removed_edges: usize = 0;
    var removed_modules: usize = 0;
    var removed_function: usize = 0;
    var removed_global: usize = 0;
    var removed_type: usize = 0;
    var removed_macro: usize = 0;
    var removed_unknown: usize = 0;
    var reason_not_referenced: usize = 0;
    var reason_only_by_unreachable: usize = 0;
    if (result.pruned) |*pruned| {
        removed_count = pruned.removed_symbols.len;
        removed_edges = pruned.removed_edges;
        removed_modules = pruned.removed_modules.len;
        for (pruned.removed_symbols) |removed| {
            switch (removed.kind) {
                .function => removed_function += 1,
                .global => removed_global += 1,
                .type => removed_type += 1,
                .macro => removed_macro += 1,
                .unknown => removed_unknown += 1,
            }
            switch (removed.reason) {
                .not_referenced => reason_not_referenced += 1,
                .referenced_only_by_unreachable => reason_only_by_unreachable += 1,
            }
        }
    }

    try writer.print("DCE 报告\n", .{});
    try writer.print("  已定义符号：{d}\n", .{result.report.stats.total_defined});
    try writer.print("  可达符号：{d}\n", .{result.report.stats.reachable_count});
    try writer.print("  已删除符号：{d}（函数：{d}；全局：{d}；类型：{d}；宏：{d}；未知：{d}）\n", .{
        removed_count,
        removed_function,
        removed_global,
        removed_type,
        removed_macro,
        removed_unknown,
    });
    try writer.print("  删除原因：无引用：{d}；仅被不可达符号引用：{d}\n", .{
        reason_not_referenced,
        reason_only_by_unreachable,
    });
    try writer.print("  已删除边：{d} 条\n", .{removed_edges});
    try writer.print("  已删除模块：{d} 个\n", .{removed_modules});
    try writer.print("  保留模块（P5B 收敛）：{d} 个\n", .{result.report.convergence.reachable_modules.len});
    try writer.print("仅模块级导入的模块（module_only，{d} 个）：\n", .{result.report.convergence.module_only_modules.len});
    for (result.report.convergence.module_only_modules) |id| {
        try writer.print("  ", .{});
        try writeModuleId(writer, id);
        try writer.print("\n", .{});
    }
    try writer.print("  校验违规：{d} 条\n", .{result.violations.len});
    try writer.print("结果：{s}", .{@tagName(result.outcome)});
    if (result.outcome == .verification_failed) {
        try writer.print("（违规 {d} 条，裁剪后图与违规列表已保留供诊断）", .{result.violations.len});
    }
    try writer.print("\n", .{});

    return buf.toOwnedSlice();
}
