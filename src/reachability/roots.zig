//! 根集计算 —— SA 标准库模块化 Phase 5（P5B，sa-reachability）。
//!
//! 职责：把 Phase 4 登记的保留规则（`RetainSet`）汇总成分析器的根集
//! （`[]RootEntry`）：一个保留节点一条记录，带它的全部规则集。
//! 分析器（P5A 的 analyzer.zig）以根集为种子做符号可达闭包；根集
//! 本身不做可达分析、不做裁剪、不删除任何东西。
//!
//! 副作用（调用前必须知道）：`computeRoots` 会修改传入的 `RetainSet`：
//! 先调 `retainMain(entry_module)`（入口模块内名为 `main` 的符号恒保留，
//! 规则 `entry_point`），再调 `retainGlobalInits(graph)`（图中全部
//! `global_init` 边的 to 端符号，规则 `global_init`）。两次登记都是
//! 幂等的（同一节点重复登记只累积规则，不重复产生记录），因此对同一
//! `RetainSet` 重复调用 `computeRoots` 是安全的，但第一次调用后
//! `RetainSet` 里已带有这两批登记。
//!
//! 判定边界（与 retention.zig 的 rule_notes 一致，今天只有两条规则可计算）：
//!   - `entry_point`：可计算——经 `retainMain` 登记；
//!   - `global_init`：可计算——经 `retainGlobalInits` 登记；
//!   - `macro_expanded` / `reflective` / `dynamic_call` / `exported`：
//!     没有数据源，不发明判定逻辑。本文件只汇总 `RetainSet` 里已有的登记：
//!     调用方若预先用 `retainExported`（或 `retain` / `retainRules`）
//!     登记过节点，`retainedNodes()` 会自动带出它们，`rulesFor` 会带出
//!     其全部规则；本文件不判断谁是导出符号、不判断谁被宏展开或反射访问。
//!
//! 输入契约：
//!   - `graph`：只读符号图；`computeRoots` 不改图（`retainGlobalInits`
//!     只读 `graph.edges`）；
//!   - `retain`：调用方传入的 `RetainSet`（通常与图共用一个 arena 分配器）；
//!     传入前可预先登记任意规则，登记结果都会进入根集；
//!   - `entry_module`：程序入口模块；其内名为 `main` 的符号记为
//!     function kind（见 `RetainSet.retainMain` 的约定）；
//!   - `allocator`：根集切片的分配器（通常是 arena）。
//!
//! 所有权 / arena 规则（与 Phase 2/3/4 一致）：
//!   - 返回的 `[]RootEntry` 是 owned 切片，调用方释放切片本身
//!     （`allocator.free`）；切片内的 `SymbolNode` 仍借用原字符串
//!     （模块 path / 符号名由调用方 arena 所有），不得单独释放；
//!   - `RootEntry.rules` 是按值拷贝的 `RetainRuleSet` 位集，不拥有任何内存；
//!   - 返回顺序未指定（`RetainSet` 哈希迭代序）；需要确定顺序的调用方
//!     自行按 `(module, name)` 排序；
//!   - 空根集（无保留节点时）返回长度 0 的切片。
//!
//! 不属于本文件：可达闭包（P5A analyzer）、裁剪（Phase 5/6）、保留规则的
//! 判定逻辑（解析器 / 后端）、build.zig 注册（后续 Phase / 协调方接线）。

const std = @import("std");
const retention = @import("../dependency_graph/retention.zig");
const symbol_graph = @import("../dependency_graph/symbol_graph.zig");

// 共享类型（复用，不重定义）。
pub const RetainSet = retention.RetainSet;
pub const RetainRule = retention.RetainRule;
pub const RetainRuleSet = retention.RetainRuleSet;
pub const SymbolGraph = symbol_graph.SymbolGraph;
pub const SymbolNode = symbol_graph.SymbolNode;
pub const ModuleId = symbol_graph.ModuleId;

/// 一条根集记录：一个被保留的符号节点，带它的全部保留规则。
///
/// P5A 的 analyzer.zig 以 `@import("roots.zig")` 引用本类型作为根集的
/// 记录形状。`node` 借用原字符串（见文件头所有权规则）；`rules` 是按值
/// 拷贝的位集，同一节点可同时带有 `entry_point` 与 `global_init` 等
/// 多条规则（例如入口模块的 `main` 同时是全局初始化的目标时）。
pub const RootEntry = struct {
    node: SymbolNode,
    rules: RetainRuleSet,

    /// 该记录是否带有某条保留规则。
    pub fn hasRule(self: RootEntry, rule: RetainRule) bool {
        return self.rules.contains(rule);
    }
};

/// 计算根集：汇总 `RetainSet` 里已登记的全部保留节点。
///
/// 步骤（顺序固定）：
///   1. `retain.retainMain(entry_module)`——入口模块内名为 `main` 的
///      符号恒保留（`entry_point`）；
///   2. `retain.retainGlobalInits(graph)`——图中全部 `global_init` 边的
///      to 端符号保留（`global_init`）；
///   3. `retain.retainedNodes(allocator)` 取全部被保留节点，对每个节点
///      用 `retain.rulesFor(node)` 拼出 `RootEntry`。
///
/// 副作用：修改传入的 `RetainSet`（第 1、2 步的登记落入其中）；不修改
/// `graph`。调用方预先登记的规则（例如经 `retainExported` 登记的导出
/// 符号）自动带出，本函数不另行判定任何规则。
///
/// 返回 owned 切片，调用方释放切片本身；顺序未指定（哈希迭代序）。
/// 只可能报分配失败（`std.mem.Allocator.Error`）。
pub fn computeRoots(
    graph: *const SymbolGraph,
    retain: *RetainSet,
    entry_module: ModuleId,
    allocator: std.mem.Allocator,
) std.mem.Allocator.Error![]RootEntry {
    // 注意：以下两行修改传入的 RetainSet（见文件头“副作用”）。
    try retain.retainMain(entry_module);
    try retain.retainGlobalInits(graph);

    const nodes = try retain.retainedNodes(allocator);
    defer allocator.free(nodes);

    var out = std.array_list.Managed(RootEntry).init(allocator);
    errdefer out.deinit();
    for (nodes) |node| {
        try out.append(.{
            .node = node,
            .rules = retain.rulesFor(node),
        });
    }
    return out.toOwnedSlice();
}
