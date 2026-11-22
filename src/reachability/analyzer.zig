//! 可达性分析器 —— SA 标准库模块化 Phase 5（P5A，sa-reachability）。
//!
//! 职责：提案 §3 的 Reachability-based DCE 的闭包计算核心。给定符号依赖
//! 图（Phase 4 的 `SymbolGraph`）与一组根节点（P5B 的 `roots.zig` 产出
//! 的 `RootEntry`），算出从根出发、沿全部引用边可达的符号闭包，并为每个
//! 可达节点记下“为什么可达”：根节点记其保留规则集（`ReachReason.retained`），
//! 其余节点记把它带入闭包的那条边（`ReachReason.reached_via`，含 from 节
//! 点与边的 `RefKind`）。
//!
//! 与 Phase 4 的 `SymbolGraph.reachableSymbols` 的区别：
//!   - 本分析器给出每个节点的 reason（根规则集 / 引入边），而
//!     `reachableSymbols` 是无 reason 的 plain BFS；协调合并时最终结果以
//!     本分析器为准，不复用 `reachableSymbols` 做最终结果；
//!   - `reachableSymbols` 每步全边线性扫描（Phase 4 已注明是待优化点）；
//!     本分析器先建一次邻接索引（from 节点 → 其发出的全部边），再按 BFS
//!     展开，索引在分析器内缓存复用（见 `ReachabilityAnalyzer`）。
//!
//! 输入契约：
//!   - 图只读：`analyze` 不修改 `SymbolGraph`，不增删节点与边；
//!   - 遍历走全部 `RefKind` 的边（含 `.macro_expansion` 展开边），不按
//!     kind 过滤；reason 里记下引入边的 kind；
//!   - 根节点本身即使未登记在图中也计入可达（与 `reachableSymbols` 的
//!     口径一致）；重复出现的根节点合并其规则集；
//!   - 同一节点可由多条边到达时，reason 只记 BFS 首次发现它的那条边
//!     （先到为准，按邻接表顺序，即图 `edges.items` 的插入顺序）；
//!   - 不展开模块级导入：图里模块级导入只记 `ModuleDep`，不产生符号边
//!     （见 `symbol_graph.zig` 的落图规则）；本分析器只走已记录的符号边，
//!     不猜测模块级导入具体用到哪个符号。模块级导入的收敛由调用方在根
//!     层处理（例如把模块根节点或 prelude 符号登记为根）。
//!
//! 本文件只做分析，不做以下事：
//!   - 不删除、不裁剪任何东西（裁剪是 Phase 6 的事）；
//!   - 不判定保留规则：规则来自 `RetainSet` / `roots.zig`，分析器只消费
//!     `RootEntry.rules`，不发明新的保留规则判定逻辑；
//!   - 不补边：动态调用 / 反射等没有图边来源的目标不会凭空进入闭包，
//!     须由调用方按 `dynamic_call` / `reflective` 规则登记为根。
//!
//! 所有权 / arena 规则（与 Phase 2/3/4 一致）：
//!   - 分析器与结果都不拥有任何字符串：节点名、模块 path 均为调用方所有
//!     （通常是 arena）；`deinit` 只释放容器本身，不释放借用串；
//!   - `ReachabilityResult` 为 owned 结果：调用方负责 `deinit`；
//!     `reachableNodes` / `reachableModules` 返回的 owned 切片由调用方
//!     释放切片本身，切片内的节点 / 模块仍借用原字符串；
//!   - `ReachReason.reached_via` 记的边是边的逐值拷贝（边内节点同样只
//!     借用字符串），不拥有字符串。
//!
//! 已知缺口：
//!   - `roots.zig`（P5B）未落盘前 `@import("roots.zig")` 无法参与全量编
//!     译；本文件只做 `zig ast-check`（parse-only，不解析 import），
//!     等协调合并时统一验证。接口约定见文件末尾注释：`RootEntry` 为
//!     `struct { node: SymbolNode, rules: RetainRuleSet }`；
//!   - 索引缓存假设图边只追加：`SymbolGraph` 没有删边 / 改边 API，缓存
//!     键为（图指针，边数）。若将来图支持删边，调用方须在改图后调
//!     `invalidateIndex`，否则分析器可能用旧索引；
//!   - 本文件不负责“根从哪里来”（入口点 / 导出表 / 反射注册表等根来源
//!     在 P5B 的 roots.zig），也不负责收敛后的裁剪动作。
//!
//! 不属于本文件：build.zig 注册（后续 Phase / 协调方接线）；Phase 2/3/4
//! 的既有文件（只读使用，不改）。

const std = @import("std");
const symbol_graph = @import("../dependency_graph/symbol_graph.zig");
const retention = @import("../dependency_graph/retention.zig");
const roots_mod = @import("roots.zig");

// 复用，不重定义（路径均相对于 src/reachability/）。
pub const SymbolGraph = symbol_graph.SymbolGraph;
pub const SymbolNode = symbol_graph.SymbolNode;
pub const SymbolKind = symbol_graph.SymbolKind;
pub const SymbolRefEdge = symbol_graph.SymbolRefEdge;
pub const RefKind = symbol_graph.RefKind;
pub const ModuleId = symbol_graph.ModuleId;
pub const RetainRule = retention.RetainRule;
pub const RetainRuleSet = retention.RetainRuleSet;
pub const RootEntry = roots_mod.RootEntry;

/// 一个可达节点的“为什么可达”。
pub const ReachReason = union(enum) {
    /// 根节点：因保留规则集而可达（根节点本身即使未登记在图中也计入）。
    /// 规则集为该节点全部根登记合并后的结果（重复根的规则集合并）。
    retained: RetainRuleSet,
    /// 非根节点：因这条边而被带入闭包（边的 from 为已可达节点，to 为本
    /// 节点；kind 记下引入边的种类，含 `.macro_expansion` 等全部 kind）。
    /// 同一节点可由多条边到达时，只记 BFS 首次发现它的那条边。
    reached_via: SymbolRefEdge,
};

/// 一次可达性分析的 owned 结果。
///
/// `reachable` 与 `order` 互为同一闭包的两种视图：`reachable` 按节点查
/// reason，`order` 按 BFS 发现顺序列节点（同时也是分析过程中的队列）。
pub const ReachabilityResult = struct {
    /// 调用方传入的分配器（通常是 arena）；结果不拥有它，也不拥有字符串。
    allocator: std.mem.Allocator,
    /// 可达节点 → 其 reason。根节点记 `.retained`，其余记 `.reached_via`。
    reachable: std.HashMap(SymbolNode, ReachReason, SymbolNode.Context, std.hash_map.default_max_load_percentage),
    /// 可达节点，按 BFS 发现顺序（根节点按 `roots` 传入顺序在前）。
    order: std.array_list.Managed(SymbolNode),

    pub fn init(allocator: std.mem.Allocator) ReachabilityResult {
        return .{
            .allocator = allocator,
            .reachable = std.HashMap(SymbolNode, ReachReason, SymbolNode.Context, std.hash_map.default_max_load_percentage).init(allocator),
            .order = std.array_list.Managed(SymbolNode).init(allocator),
        };
    }

    pub fn deinit(self: *ReachabilityResult) void {
        // 只释放容器本身；节点名 / 模块 path 等字符串均为调用方所有
        // （arena 规则），不在此释放。
        self.reachable.deinit();
        self.order.deinit();
    }

    /// 可达节点数。
    pub fn count(self: *const ReachabilityResult) usize {
        return self.reachable.count();
    }

    /// 该节点是否在可达闭包内。
    pub fn isReachable(self: *const ReachabilityResult, node: SymbolNode) bool {
        return self.reachable.contains(node);
    }

    /// 该节点的 reason；不可达返回 null。返回值为逐值拷贝（内含的边与
    /// 节点只借用字符串）。
    pub fn reasonFor(self: *const ReachabilityResult, node: SymbolNode) ?ReachReason {
        return self.reachable.get(node);
    }

    /// 全部可达节点，按 BFS 发现顺序。返回 owned 切片，调用方释放切片
    /// 本身；切片内的节点仍借用原字符串。
    pub fn reachableNodes(self: *const ReachabilityResult, allocator: std.mem.Allocator) std.mem.Allocator.Error![]SymbolNode {
        return allocator.dupe(SymbolNode, self.order.items);
    }

    /// 可达节点所属的去重模块列表，按模块在 BFS 发现顺序中首次出现
    /// 的顺序（供 P5B 收敛用）。返回 owned 切片，调用方释放切片本身；
    /// 切片内的模块仍借用原字符串。
    pub fn reachableModules(self: *const ReachabilityResult, allocator: std.mem.Allocator) std.mem.Allocator.Error![]ModuleId {
        var seen = std.HashMap(ModuleId, void, ModuleId.Context, std.hash_map.default_max_load_percentage).init(allocator);
        defer seen.deinit();
        var out = std.array_list.Managed(ModuleId).init(allocator);
        errdefer out.deinit();
        for (self.order.items) |node| {
            if (seen.contains(node.module)) continue;
            try seen.put(node.module, {});
            try out.append(node.module);
        }
        return out.toOwnedSlice();
    }
};

/// 可达性分析器：sa-reachability 的闭包计算核心。
///
/// 持有从图边建出的邻接索引（from 节点 → 其发出的全部边），`analyze`
/// 用显式队列 BFS 展开闭包。索引在分析器内缓存：同一张图（指针相同且
/// 边数未变）多次 `analyze` 只建一次；换图或边数变化时重建。缓存假设
/// 图边只追加（`SymbolGraph` 无删边 / 改边 API）；若将来图支持删边，
/// 调用方须在改图后调 `invalidateIndex`。
///
/// 分析器本身不拥有图与字符串；`analyze` 返回的 owned 结果由调用方
/// `deinit`。分析器不是线程安全的：不要并发调 `analyze`。
pub const ReachabilityAnalyzer = struct {
    /// 调用方传入的分配器（通常是 arena）；分析器不拥有它。
    allocator: std.mem.Allocator,
    /// 邻接索引：from 节点 → 该节点发出的全部边（按图 `edges.items`
    /// 的插入顺序）。索引内的边为逐值拷贝，只借用字符串。
    index: std.HashMap(SymbolNode, std.array_list.Managed(SymbolRefEdge), SymbolNode.Context, std.hash_map.default_max_load_percentage),
    /// 索引针对的图（指针身份）；null 表示当前无有效索引。
    indexed_graph: ?*const SymbolGraph = null,
    /// 建索引时图的边数；与 `indexed_graph` 共同构成缓存键。
    indexed_edge_count: usize = 0,

    pub fn init(allocator: std.mem.Allocator) ReachabilityAnalyzer {
        return .{
            .allocator = allocator,
            .index = std.HashMap(SymbolNode, std.array_list.Managed(SymbolRefEdge), SymbolNode.Context, std.hash_map.default_max_load_percentage).init(allocator),
        };
    }

    pub fn deinit(self: *ReachabilityAnalyzer) void {
        self.clearIndex();
        self.index.deinit();
    }

    /// 使缓存的邻接索引失效：下一次 `analyze` 重新建索引。
    /// 图边被删 / 改后必须调用（今天 `SymbolGraph` 边只追加，一般不
    /// 需要；换图或边数变化时 `analyze` 会自动重建）。
    pub fn invalidateIndex(self: *ReachabilityAnalyzer) void {
        self.clearIndex();
    }

    /// 释放索引内全部邻接表并清空索引（保留索引哈希表本身的容量复用）。
    fn clearIndex(self: *ReachabilityAnalyzer) void {
        var it = self.index.valueIterator();
        while (it.next()) |list_ptr| {
            list_ptr.deinit();
        }
        self.index.clearRetainingCapacity();
        self.indexed_graph = null;
        self.indexed_edge_count = 0;
    }

    /// 从 `graph.edges.items` 重建邻接索引（建一次复用）。失败时索引
    /// 回到空状态（不留半建成索引）。
    fn rebuildIndex(self: *ReachabilityAnalyzer, graph: *const SymbolGraph) std.mem.Allocator.Error!void {
        self.clearIndex();
        errdefer self.clearIndex();
        for (graph.edges.items) |edge| {
            const entry = try self.index.getOrPut(edge.from);
            if (!entry.found_existing) {
                entry.value_ptr.* = std.array_list.Managed(SymbolRefEdge).init(self.allocator);
            }
            try entry.value_ptr.append(edge);
        }
        self.indexed_graph = graph;
        self.indexed_edge_count = graph.edgeCount();
    }

    /// 从 `roots` 出发、沿图中全部引用边做 BFS，返回带 reason 的可达闭包。
    ///
    /// 语义（与 Phase 4 `SymbolGraph.reachableSymbols` 的口径一致）：
    ///   - 根节点本身即使未登记在图中也计入可达，reason 为
    ///     `.retained`（带该根的全部规则集）；重复根合并规则集；
    ///   - 其余可达节点 reason 为把它首次带入的那条边（`.reached_via`），
    ///     含边的 from 节点与 kind；
    ///   - 全部 `RefKind` 的边都走（含 `.macro_expansion`）；环与自环由
    ///     可达集去重自然终止；
    ///   - 返回 owned 结果，调用方负责 `deinit`。
    pub fn analyze(self: *ReachabilityAnalyzer, graph: *const SymbolGraph, roots: []const RootEntry) std.mem.Allocator.Error!ReachabilityResult {
        // 索引缓存：同一张图且边数未变时复用，否则重建。
        if (self.indexed_graph != graph or self.indexed_edge_count != graph.edgeCount()) {
            try self.rebuildIndex(graph);
        }

        var result = ReachabilityResult.init(self.allocator);
        errdefer result.deinit();

        // 先把全部根节点入队（根先于任何展开入队，故根的 reason 恒为
        // `.retained`；重复根合并规则集）。
        for (roots) |root| {
            if (result.reachable.getPtr(root.node)) |reason_ptr| {
                switch (reason_ptr.*) {
                    .retained => |*rules| rules.merge(root.rules),
                    // 防御分支：当前流程中根节点不可能已是 `.reached_via`
                    // （根全部先于 BFS 展开入队）；若将来流程调整，根身
                    // 份优先于引入边，升级为 `.retained`。
                    .reached_via => reason_ptr.* = .{ .retained = root.rules },
                }
                continue;
            }
            try result.reachable.put(root.node, .{ .retained = root.rules });
            try result.order.append(root.node);
        }

        // 显式队列 BFS：`result.order` 本身即队列（按发现顺序追加，
        // head 指针推进），不再另建队列。
        var head: usize = 0;
        while (head < result.order.items.len) : (head += 1) {
            const current = result.order.items[head];
            const outgoing = self.index.get(current) orelse continue;
            for (outgoing.items) |edge| {
                if (result.reachable.contains(edge.to)) continue;
                try result.reachable.put(edge.to, .{ .reached_via = edge });
                try result.order.append(edge.to);
            }
        }

        return result;
    }
};

// 与 P5B 的 roots.zig 的接口约定（协调合并时以此为准，见文件头）：
//   pub const RootEntry = struct {
//       node: SymbolNode,       // 根符号节点（SymbolNode，见 symbol_graph.zig）
//       rules: RetainRuleSet,   // 该根的全部保留规则（RetainRuleSet，见 retention.zig）
//   };
// 本文件只消费 `RootEntry.node` / `RootEntry.rules`，不构造 RootEntry，
// 不判定规则从何而来。
