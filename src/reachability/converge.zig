//! 模块级收敛 —— SA 标准库模块化 Phase 5（P5B，sa-reachability）。
//!
//! 职责：收敛 Phase 4 留下的模块级边。背景（Phase 4 RESULT §2，
//! `src/dependency_graph/types.zig` 文件头与 `symbol_graph.zig` 的
//! “导入边的落图规则”）：`symbol` 为 null 的模块级边只记在
//! `SymbolGraph.module_deps` 里，不展开成符号边；一个模块的符号变得
//! 可达，当且仅当某条已记录的边从可达符号指向它。
//!
//! 收敛规则（硬性）：模块级导入绝不能展开成“该模块的全部符号”——那样
//! 会毁掉 DCE。本文件只给每条 `ModuleDep` 定一个收敛状态，不展开任何
//! 符号边、不新增符号可达性（那是 P5A 分析器的事）、不删除、不裁剪
//! 任何东西。
//!
//! 状态定义（`ConvergedStatus`）：
//!   - `expanded_when_referenced`：from 模块可达，且图中存在从可达
//!     符号指向 to 模块内符号的边（即 to 模块已有符号正被引用）；
//!   - `module_only`：from 模块可达，但 to 模块暂无符号被可达代码引用
//!     （模块可达、符号未展开）。
//!
//! 粒度说明（调用前必须知道）：`converge` 的输入只有可达模块列表，
//! 没有可达符号集，因此“可达符号”在本文件按模块粒度判定——“从可达
//! 符号发出的边”指“从属于可达模块的符号发出的已记录边”（含模块根节点
//! 发出的 `.import` 边）。这是一个必要条件，不是符号级证明：它只能
//! 说明 to 模块至少有一个符号被可达模块的代码引用，不能说明具体哪个
//! from 符号可达。真正的符号级可达性由 P5A 分析器的
//! `reachableSymbols` 判定；后续若调用方能传入可达符号集，本状态可
//! 再收紧为符号级判定。
//!
//! 输入契约：
//!   - `symbol_graph`：只读；`converge` 不改图，只读 `module_deps` 与
//!     `edges`；
//!   - `module_graph`：只读；只用于模块级闭包展开
//!     （`reachableFrom`，内部只走 loaded/analyzed 态节点）与状态门
//!     （`stateOf` / `stateIsTraversable`）；
//!   - `reachable_modules`：种子可达模块列表（调用方通常取自 P5A
//!     分析结果的 `reachableModules()`）；种子本身不设状态门——P5A
//!     已判定它们可达；去重后进入闭包；
//!   - `allocator`：结果 `Convergence` 内三个 owned 切片的分配器
//!     （通常是 arena）。
//!
//! 闭包规则：从种子出发，沿两条线做模块级闭包，只走 loaded/analyzed
//! 态节点（`stateIsTraversable`）：
//!   - (a) `SymbolGraph.module_deps`：from 可达的边的 to 端；
//!   - (b) `ModuleGraph.reachableFrom`：每可达模块的传递闭包（其内部
//!     已设同样的状态门）。
//! 状态门只设在“被走到的节点”上（与 `reachableFrom` 一致）：to 端模块
//! 若在 `ModuleGraph` 里且为 unloaded/loading 态，既不进入可达集，
//! 也不被穿过；to 端模块若不在 `ModuleGraph` 里（两图未对齐），无状态
//! 信息可否决，按可走处理（见“已知缺口”）。`reachableFrom` 报
//! `NodeNotFound` 等图错误时只跳过该模块的图展开，闭包仍由 (a) 继续
//! 推进；只有分配失败（`OutOfMemory`）才向上传。
//!
//! 输出约定：
//!   - `Convergence.reachable_modules`：闭包后的全部可达模块，owned
//!     去重列表，按 BFS 发现顺序排列（种子按调用方传入顺序在先）；
//!   - `Convergence.converged_deps`：`module_deps` 中 from 端可达的每条
//!     依赖各一条记录（`ModuleDep` 在落图时已去重，此处不再二次去重），
//!     按 `module_deps` 的记录顺序排列；from 端不可达的依赖不进入结果；
//!   - `Convergence.module_only_modules`：status 全是 `module_only` 的
//!     to 端模块去重列表（某 to 端模块只要有一条入边是
//!     `expanded_when_referenced`，就不列入），按 `converged_deps` 的
//!     出现顺序排列。
//!
//! 所有权 / arena 规则（与 Phase 2/3/4 一致）：
//!   - `Convergence` 拥有三个切片的容器本身，不拥有任何字符串
//!     （`ModuleId` 的 package / path 均为调用方所有）；`deinit` 只释放
//!     三个切片本身（长度为 0 的切片不释放——它可能是一段编译期空切片，
//!     而非分配器产物）；
//!   - `Convergence.init(allocator)` 构造空结果；`converge` 返回已填好
//!     的结果，调用方用完调 `deinit`；`deinit` 后实例不可再用。
//!
//! 已知缺口：
//!   - 符号级判定缺口：见上“粒度说明”——本状态是模块级必要条件，
//!     不是符号级证明；
//!   - 跨图一致性缺口：`converged_deps` 只覆盖 `SymbolGraph.module_deps`
//!     里的依赖；只存在于 `ModuleGraph` 边里的模块关系参与闭包展开，
//!     但不产生 `ConvergedDep` 记录（两图正常由同一 loader 边集建成，
//!     应一致；不一致时以 `module_deps` 为准）；
//!   - 不在 `ModuleGraph` 里的模块无状态门（见“闭包规则”），可能把
//!     未加载模块计入可达集——调用方应保证两图由同一批模块建成。
//!
//! 不属于本文件：符号可达闭包（P5A analyzer）、裁剪（Phase 5/6）、
//! 保留规则判定（见 roots.zig）、build.zig 注册（后续 Phase / 协调方接线）。

const std = @import("std");
const symbol_graph_mod = @import("../dependency_graph/symbol_graph.zig");
const module_graph_mod = @import("../dependency_graph/module_graph.zig");

// 共享类型（复用，不重定义）。
pub const SymbolGraph = symbol_graph_mod.SymbolGraph;
pub const ModuleGraph = module_graph_mod.ModuleGraph;
pub const ModuleDep = symbol_graph_mod.ModuleDep;
pub const ModuleId = symbol_graph_mod.ModuleId;
pub const SymbolNode = symbol_graph_mod.SymbolNode;
pub const stateIsTraversable = module_graph_mod.stateIsTraversable;

/// 一条模块级依赖的收敛状态。
pub const ConvergedStatus = enum {
    /// from 模块可达，且图中存在从可达符号指向 to 模块内符号的边
    /// （to 模块已有符号正被引用；“可达符号”按模块粒度判定，见文件头）。
    expanded_when_referenced,
    /// from 模块可达，但 to 模块暂无符号被可达代码引用
    /// （模块可达、符号未展开）。
    module_only,
};

/// 一条已收敛的模块级依赖：原依赖 + 收敛状态。
pub const ConvergedDep = struct {
    dep: ModuleDep,
    status: ConvergedStatus,

    /// 该依赖是否已展开到符号引用（to 模块已有符号被引用）。
    pub fn isExpanded(self: ConvergedDep) bool {
        return self.status == .expanded_when_referenced;
    }

    /// 该依赖是否仍只是模块级（to 模块暂无符号被引用）。
    pub fn isModuleOnly(self: ConvergedDep) bool {
        return self.status == .module_only;
    }
};

/// 模块级收敛的结果。
///
/// 三个切片均为 owned（由 `allocator` 分配），`deinit` 只释放切片本身。
pub const Convergence = struct {
    allocator: std.mem.Allocator,
    /// 闭包后的全部可达模块（owned 去重列表，BFS 发现顺序）。
    reachable_modules: []ModuleId = &.{},
    /// from 端可达的模块级依赖各一条记录（按 `module_deps` 记录顺序）。
    converged_deps: []ConvergedDep = &.{},
    /// status 全是 `module_only` 的 to 端模块去重列表。
    module_only_modules: []ModuleId = &.{},

    pub fn init(allocator: std.mem.Allocator) Convergence {
        return .{ .allocator = allocator };
    }

    /// 只释放三个切片本身，不释放任何借用串；调用后实例不可再用。
    pub fn deinit(self: *Convergence) void {
        // 长度为 0 的切片不释放：它可能是一段编译期空切片，而非
        // 分配器产物；非空切片一定来自 `toOwnedSlice`，可安全释放。
        if (self.reachable_modules.len > 0) self.allocator.free(self.reachable_modules);
        if (self.converged_deps.len > 0) self.allocator.free(self.converged_deps);
        if (self.module_only_modules.len > 0) self.allocator.free(self.module_only_modules);
        self.* = undefined;
    }

    /// 可达模块数（闭包后，去重）。
    pub fn reachableModuleCount(self: *const Convergence) usize {
        return self.reachable_modules.len;
    }

    /// 已收敛的依赖条数（from 端可达的 `ModuleDep` 数）。
    pub fn convergedDepCount(self: *const Convergence) usize {
        return self.converged_deps.len;
    }

    /// 已展开到符号引用的依赖条数。
    pub fn expandedDepCount(self: *const Convergence) usize {
        var n: usize = 0;
        for (self.converged_deps) |cd| {
            if (cd.isExpanded()) n += 1;
        }
        return n;
    }

    /// 仍只是模块级的依赖条数。
    pub fn moduleOnlyDepCount(self: *const Convergence) usize {
        var n: usize = 0;
        for (self.converged_deps) |cd| {
            if (cd.isModuleOnly()) n += 1;
        }
        return n;
    }

    /// 该模块是否在可达闭包内。
    pub fn isReachable(self: *const Convergence, id: ModuleId) bool {
        for (self.reachable_modules) |m| {
            if (m.eql(id)) return true;
        }
        return false;
    }

    /// 该模块是否全是 `module_only` 状态（即在 `module_only_modules` 内）。
    pub fn isModuleOnly(self: *const Convergence, id: ModuleId) bool {
        for (self.module_only_modules) |m| {
            if (m.eql(id)) return true;
        }
        return false;
    }

    /// 某条依赖的收敛状态；该依赖不在结果里（from 端不可达）时返回 null。
    pub fn statusOf(self: *const Convergence, dep: ModuleDep) ?ConvergedStatus {
        for (self.converged_deps) |cd| {
            if (cd.dep.eql(dep)) return cd.status;
        }
        return null;
    }
};

/// 闭包入队辅助：未见过且可走（loaded/analyzed 态，或不在模块图里）
/// 的模块才入队。种子不走本函数（种子不设状态门，见 `converge`）。
fn enqueueIfNew(
    seen: *std.HashMap(ModuleId, void, ModuleId.Context, std.hash_map.default_max_load_percentage),
    queue: *std.array_list.Managed(ModuleId),
    module_graph: *const ModuleGraph,
    id: ModuleId,
) std.mem.Allocator.Error!void {
    if (seen.contains(id)) return;
    // 状态门：模块在 ModuleGraph 里时只有 loaded/analyzed 态可走；
    // 不在图里时无状态信息可否决，按可走处理（见文件头“闭包规则”）。
    if (module_graph.stateOf(id)) |state| {
        if (!stateIsTraversable(state)) return;
    }
    try seen.put(id, {});
    try queue.append(id);
}

/// 模块级收敛：从可达模块种子出发做模块级闭包，并给每条 from 端可达的
/// `ModuleDep` 定收敛状态。
///
/// 不改两张图，不新增符号可达性，不删除、不裁剪任何东西。
/// 只可能报分配失败（`std.mem.Allocator.Error`）；`ModuleGraph` 的
/// 查询错误（`NodeNotFound` 等）内部消化为“跳过该模块的图展开”，
/// 只有 `OutOfMemory` 向上传。
pub fn converge(
    symbol_graph: *const SymbolGraph,
    module_graph: *const ModuleGraph,
    reachable_modules: []const ModuleId,
    allocator: std.mem.Allocator,
) std.mem.Allocator.Error!Convergence {
    var result = Convergence.init(allocator);
    errdefer result.deinit();

    // —— 第 1 步：模块级闭包（BFS；种子不设状态门）——
    var seen = std.HashMap(ModuleId, void, ModuleId.Context, std.hash_map.default_max_load_percentage).init(allocator);
    defer seen.deinit();
    var queue = std.array_list.Managed(ModuleId).init(allocator);
    defer queue.deinit();
    for (reachable_modules) |id| {
        if (seen.contains(id)) continue;
        try seen.put(id, {});
        try queue.append(id);
    }

    var head: usize = 0;
    while (head < queue.items.len) : (head += 1) {
        const current = queue.items[head];
        // (a) 符号图的模块级依赖：from 可达的边的 to 端。
        for (symbol_graph.module_deps.items) |dep| {
            if (!dep.from.eql(current)) continue;
            try enqueueIfNew(&seen, &queue, module_graph, dep.to);
        }
        // (b) 模块图的传递闭包（内部只走 loaded/analyzed 态节点）。
        // 不在图里时跳过本模块的图展开；闭包仍由 (a) 继续推进。
        if (module_graph.contains(current)) {
            const reached = module_graph.reachableFrom(current) catch |err| switch (err) {
                error.OutOfMemory => return error.OutOfMemory,
                else => &[_]ModuleId{},
            };
            defer if (reached.len > 0) module_graph.allocator.free(reached);
            for (reached) |id| {
                try enqueueIfNew(&seen, &queue, module_graph, id);
            }
        }
    }
    result.reachable_modules = try queue.toOwnedSlice();

    // —— 第 2 步：哪些 to 模块已有符号被可达模块的符号引用 ——
    // “可达符号”按模块粒度判定：from 端符号属于闭包内任一模块的边，
    // 其 to 端模块即为“已有符号正被引用”的模块。
    var referenced_targets = std.HashMap(ModuleId, void, ModuleId.Context, std.hash_map.default_max_load_percentage).init(allocator);
    defer referenced_targets.deinit();
    for (symbol_graph.edges.items) |edge| {
        if (!seen.contains(edge.from.module)) continue;
        try referenced_targets.put(edge.to.module, {});
    }

    // —— 第 3 步：给每条 from 端可达的 ModuleDep 定状态 ——
    var deps = std.array_list.Managed(ConvergedDep).init(allocator);
    errdefer deps.deinit();
    for (symbol_graph.module_deps.items) |dep| {
        if (!seen.contains(dep.from)) continue;
        const status: ConvergedStatus = if (referenced_targets.contains(dep.to))
            .expanded_when_referenced
        else
            .module_only;
        try deps.append(.{ .dep = dep, .status = status });
    }
    result.converged_deps = try deps.toOwnedSlice();

    // —— 第 4 步：status 全是 module_only 的 to 端模块（去重） ——
    // 某 to 端模块只要有一条入边是 expanded_when_referenced，就不列入。
    var expanded_targets = std.HashMap(ModuleId, void, ModuleId.Context, std.hash_map.default_max_load_percentage).init(allocator);
    defer expanded_targets.deinit();
    for (result.converged_deps) |cd| {
        if (cd.isExpanded()) try expanded_targets.put(cd.dep.to, {});
    }
    var only = std.array_list.Managed(ModuleId).init(allocator);
    errdefer only.deinit();
    var only_seen = std.HashMap(ModuleId, void, ModuleId.Context, std.hash_map.default_max_load_percentage).init(allocator);
    defer only_seen.deinit();
    for (result.converged_deps) |cd| {
        if (!cd.isModuleOnly()) continue;
        if (expanded_targets.contains(cd.dep.to)) continue;
        if (only_seen.contains(cd.dep.to)) continue;
        try only_seen.put(cd.dep.to, {});
        try only.append(cd.dep.to);
    }
    result.module_only_modules = try only.toOwnedSlice();

    return result;
}
