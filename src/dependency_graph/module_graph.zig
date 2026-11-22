//! 模块依赖图本体 —— SA 标准库模块化 Phase 4（sa-dependency-graph，P4A）。
//!
//! 职责：提案 §3 的第一层图（Module Dependency Graph）：决定哪些模块
//! 需要加载/分析。节点是模块（ModuleNode），边是模块级依赖（ModuleEdge，
//! 多条 SymbolEdge 按 (from, to) 去重落成一条，保留首条 kind）。
//! 第二层图（符号/函数依赖图）是 P4B/P4C 的事：本文件只提供 SymbolNode /
//! SymbolKind 类型（见 types.zig），不建符号图。
//!
//! 与既有机制的关系：
//!   - 不替换 Phase 2 的 ClosureBuilder 与 Phase 3 的 LazyLoader：两者
//!     是“发现依赖、记录结构”的生产者，本图是它们的消费者——fromLoader()
//!     只读 LazyLoader 的模块表与 edges 列表建图，不改 loader 的任何状态。
//!   - 不替换 flattener 的 ImportCycle 判定：本图的 topoSort() 遇环只
//!     返回 error.CycleDetected 并把环记录留在 lastCycles() 里，不报
//!     诊断、不写 ErrorContext；环是否合法由语义规则定（提案 §2）。
//!   - 不接 build：只新增 src/dependency_graph/ 下文件，不改任何既有
//!     文件；构建接线（build.zig 注册）是后续 Phase / 协调方的事；
//!     验证只跑 `zig ast-check` 与 @import 悬空核对。
//!
//! 构造器输入形状（与 P4B/P4C 的接口约定）：
//!   - `ModuleGraph.init(allocator)`：空图，allocator 由调用方传入
//!     （arena 规则见下）；节点/边用 addModule / addEdge 逐个加入。
//!   - `ModuleGraph.fromLoader(loader)`：loader 为 `*const LazyLoader`
//!    （只读）。节点取 loader.modules 表的每一项（id / state /
//!     info.fs_path）；边取 loader.edges 的每一项（from / to / kind，
//!     不去重的原始列表，去重在本图内做）。loader 的 cycles 不复制：
//!     环由本图的 topoSort() 重新算。
//!   - fromLoader 的节点插入顺序按 (package, path) 字典序排过，因此
//!     topoSort() 的输出对同一 loader 输入是确定的；手工建图时
//!     topoSort() 的顺序由 addModule 的加入顺序决定（同顺序 → 同输出）。
//!
//! 查询语义：
//!   - dependsOn / dependents：直接后继 / 直接前驱（去重后的边，
//!     按边的加入顺序返回）；目标不在图里报 error.NodeNotFound。
//!   - reachableFrom：传递闭包（DFS 先序，按边的加入顺序发现），
//!     只走 loaded/analyzed 态节点：unloaded/loading 态的节点既不
//!     进入可达集，也不被穿过（其出边不继续展开）；起点本身不计入
//!     结果。目标不在图里报 error.NodeNotFound。
//!   - roots / leaves：入度 0 / 出度 0 的节点，按节点加入顺序返回。
//!   - topoSort：Kahn 算法（显式队列）；依赖先于使用方；有环返回
//!     error.CycleDetected，环记录（CycleRecord 列表）留在
//!     lastCycles() 里，每条记录是一条简单环（cycle_path 首尾相接，
//!     entry 为环入口）。自边（A → A）算作长 1 的环。
//!   - 查询返回的切片一律由调用方拥有（allocator 分配），用完调
//!     allocator.free 释放；空结果返回长度 0 的已分配切片（非 null）。
//!
//! 所有权 / arena 规则（与 Phase 2 的 A8、Phase 3 的 loader 一致）：
//!   - allocator 由调用方传入（预期为 arena）；图用它分配一切容器与
//!     环路径。deinit 只释放容器本身与图拥有的 cycle_path 切片，不释
//!     放任何借用串（ModuleId / fs_path / 符号名均由调用方 arena 统一
//!     释放）。调用方不得在图活着时释放 arena。
//!   - addModule 已存在时只更新 state（fs_path 非 null 时才覆盖），
//!     不报错、不重复记入插入顺序；addEdge 遇到已存在的 (from, to)
//!     是无操作（保留首条 kind）；addEdge 的端点缺失时自动以
//!     .unloaded 态补建节点（不报 NodeNotFound；NodeNotFound 只由
//!     查询与 setState 报告）。
//!   - setState 只允许单步前向迁移（与 loader 的状态机同款）：
//!     unloaded → loading → loaded → analyzed，同态重复置位是无操作；
//!     其余迁移报 error.InvalidState，目标不在图里报 NodeNotFound。
//!
//! 复杂度说明：查询每次扫描边表（O(E)）；topoSort 为 O(V + E)；环提
//! 取最坏 O(V * E)。sa_std 约 645 个模块的规模下足够；更大图需要
//! 邻接表时再重构，不在本 Phase 做。

const std = @import("std");
const types_mod = @import("types.zig");
const loader_mod = @import("../module_loader/loader.zig");

// 共享类型（复用，不重定义；经 types.zig 转发）。
pub const ModuleState = types_mod.ModuleState;
pub const ImportKind = types_mod.ImportKind;
pub const ModuleId = types_mod.ModuleId;
pub const ModuleInfo = types_mod.ModuleInfo;
pub const SymbolEdge = types_mod.SymbolEdge;
pub const ResolveError = types_mod.ResolveError;
pub const CycleRecord = types_mod.CycleRecord;
pub const SymbolKind = types_mod.SymbolKind;
pub const ModuleNode = types_mod.ModuleNode;
pub const SymbolNode = types_mod.SymbolNode;
pub const ModuleEdge = types_mod.ModuleEdge;
pub const GraphError = types_mod.GraphError;
pub const stateIsTraversable = types_mod.stateIsTraversable;
// LazyLoader 复用 Phase 3（只读消费，见 fromLoader）。
pub const LazyLoader = loader_mod.LazyLoader;
pub const ModuleEntry = loader_mod.ModuleEntry;

/// (from, to) 去重键：与 ModuleEdge 的去重口径一致（不含 kind）。
const EdgeKey = struct {
    from: ModuleId,
    to: ModuleId,

    pub fn eql(self: EdgeKey, other: EdgeKey) bool {
        return self.from.eql(other.from) and self.to.eql(other.to);
    }

    pub fn hash(self: EdgeKey) u64 {
        var h = self.from.hash();
        h = std.hash.Wyhash.hash(h, self.to.package);
        h = std.hash.Wyhash.hash(h, self.to.path);
        return h;
    }

    pub const Context = struct {
        pub fn hash(_: Context, key: EdgeKey) u64 {
            return key.hash();
        }

        pub fn eql(_: Context, a: EdgeKey, b: EdgeKey) bool {
            return a.eql(b);
        }
    };
};

pub const ModuleGraph = struct {
    /// 调用方传入的分配器（预期为 arena；图不拥有它）。
    allocator: std.mem.Allocator,
    /// 节点表：规范 ModuleId → ModuleNode（键与值里的 id 借用同一串）。
    nodes: std.HashMap(ModuleId, ModuleNode, ModuleId.Context, 80),
    /// 节点加入顺序：一切按序输出（topoSort / roots / leaves）的基准。
    insertion_order: std.array_list.Managed(ModuleId),
    /// 去重后的模块边（按加入顺序）。
    edges: std.array_list.Managed(ModuleEdge),
    /// 去重索引：已存在的 (from, to) 集合（与 edges 同步维护）。
    edge_set: std.HashMap(EdgeKey, void, EdgeKey.Context, 80),
    /// 最近一次 topoSort() 发现的环（成功时为空；CycleDetected 时为
    /// 提取出的简单环列表）。cycle_path 切片由本图拥有。
    cycles: std.array_list.Managed(CycleRecord),

    pub fn init(allocator: std.mem.Allocator) ModuleGraph {
        return .{
            .allocator = allocator,
            .nodes = std.HashMap(ModuleId, ModuleNode, ModuleId.Context, 80).init(allocator),
            .insertion_order = std.array_list.Managed(ModuleId).init(allocator),
            .edges = std.array_list.Managed(ModuleEdge).init(allocator),
            .edge_set = std.HashMap(EdgeKey, void, EdgeKey.Context, 80).init(allocator),
            .cycles = std.array_list.Managed(CycleRecord).init(allocator),
        };
    }

    /// 只释放容器本身与图拥有的 cycle_path 切片；不释放任何借用串
    /// （见文件头所有权规则）。调用后实例不可再用。
    pub fn deinit(self: *ModuleGraph) void {
        self.clearCycles();
        self.cycles.deinit();
        self.edge_set.deinit();
        self.edges.deinit();
        self.insertion_order.deinit();
        self.nodes.deinit();
        self.* = undefined;
    }

    /// 释放 cycles 里的 cycle_path 切片并清空列表（deinit 与
    /// topoSort() 开头共用；不释放 cycles 容器本身）。
    fn clearCycles(self: *ModuleGraph) void {
        for (self.cycles.items) |record| {
            self.allocator.free(record.cycle_path);
        }
        self.cycles.clearRetainingCapacity();
    }

    /// 最近一次 topoSort() 的环记录：成功时为空；CycleDetected 时为
    /// 提取出的简单环列表。切片借用本图，调用方不得释放、不得久存
    /// （下一次 topoSort() 或 deinit 会释放它）。
    pub fn lastCycles(self: *const ModuleGraph) []const CycleRecord {
        return self.cycles.items;
    }

    /// 节点数。
    pub fn nodeCount(self: *const ModuleGraph) usize {
        return self.nodes.count();
    }

    /// 去重后的边数（原始 SymbolEdge 条数可能更多）。
    pub fn edgeCount(self: *const ModuleGraph) usize {
        return self.edges.count();
    }

    /// 图里是否已有该模块。
    pub fn contains(self: *const ModuleGraph, id: ModuleId) bool {
        return self.nodes.contains(id);
    }

    /// 查询模块当前状态；未登记返回 null。
    pub fn stateOf(self: *const ModuleGraph, id: ModuleId) ?ModuleState {
        const node = self.nodes.get(id) orelse return null;
        return node.state;
    }

    /// 查询节点（值拷贝）；未登记返回 null。
    pub fn nodeOf(self: *const ModuleGraph, id: ModuleId) ?ModuleNode {
        return self.nodes.get(id);
    }

    /// 是否已存在从 from 到 to 的模块边（去重后的口径）。
    pub fn hasEdge(self: *const ModuleGraph, from: ModuleId, to: ModuleId) bool {
        return self.edge_set.contains(.{ .from = from, .to = to });
    }

    /// 加入一个模块；已存在时只更新 state（同态重复置位是无操作），
    /// 不重复记入插入顺序。fs_path 为 null（无路径信息）。
    pub fn addModule(self: *ModuleGraph, id: ModuleId, state: ModuleState) GraphError!void {
        try self.addModuleWithPath(id, state, null);
    }

    /// 加入一个模块并带磁盘路径（借用串，图不拥有）。
    /// 已存在时更新 state；fs_path 非 null 时才覆盖旧路径。
    pub fn addModuleWithPath(
        self: *ModuleGraph,
        id: ModuleId,
        state: ModuleState,
        fs_path: ?[]const u8,
    ) GraphError!void {
        if (self.nodes.getPtr(id)) |node| {
            node.state = state;
            if (fs_path) |p| node.fs_path = p;
            return;
        }
        try self.nodes.put(id, .{ .id = id, .state = state, .fs_path = fs_path });
        try self.insertion_order.append(id);
    }

    /// 推进一个模块的状态：只允许单步前向迁移
    /// unloaded → loading → loaded → analyzed（与 loader 同款），
    /// 同态重复置位是无操作；其余迁移报 error.InvalidState；
    /// 目标不在图里报 error.NodeNotFound。
    pub fn setState(self: *ModuleGraph, id: ModuleId, new_state: ModuleState) GraphError!void {
        const node = self.nodes.getPtr(id) orelse return error.NodeNotFound;
        if (node.state == new_state) return;
        const allowed = switch (node.state) {
            .unloaded => new_state == .loading,
            .loading => new_state == .loaded,
            .loaded => new_state == .analyzed,
            .analyzed => false,
        };
        if (!allowed) return error.InvalidState;
        node.state = new_state;
    }

    /// 加入一条模块边（kind 为落成此边的首条 SymbolEdge 的 kind，
    /// 可为 null 表示粒度未知）。按 (from, to) 去重：已存在时是
    /// 无操作，保留首条边的 kind。端点缺失时自动以 .unloaded 态
    /// 补建节点（无 fs_path）。
    pub fn addEdge(
        self: *ModuleGraph,
        from: ModuleId,
        to: ModuleId,
        kind: ?ImportKind,
    ) GraphError!void {
        const key = EdgeKey{ .from = from, .to = to };
        if (self.edge_set.contains(key)) return;
        if (!self.nodes.contains(from)) try self.addModule(from, .unloaded);
        if (!self.nodes.contains(to)) try self.addModule(to, .unloaded);
        try self.edge_set.put(key, {});
        errdefer _ = self.edge_set.remove(key);
        try self.edges.append(.{ .from = from, .to = to, .via = kind });
    }

    /// 从 LazyLoader 建图（只读，不改 loader）。
    /// 节点取 loader.modules 表的每一项（id / state / info.fs_path）；
    /// 边取 loader.edges 的每一项（from / to / kind）。loader 的
    /// cycles 不复制，环由本图的 topoSort() 重新算。
    /// 节点插入顺序按 (package, path) 字典序排过，因此同一 loader
    /// 输入的 topoSort() 输出是确定的。
    pub fn fromLoader(loader: *const LazyLoader) GraphError!ModuleGraph {
        var graph = ModuleGraph.init(loader.allocator);
        errdefer graph.deinit();
        var it = loader.modules.iterator();
        while (it.next()) |entry| {
            const id = entry.key_ptr.*;
            const mod = entry.value_ptr.*;
            try graph.addModuleWithPath(id, mod.state, mod.info.fs_path);
        }
        for (loader.edges.items) |edge| {
            try graph.addEdge(edge.from, edge.to, edge.kind);
        }
        graph.sortInsertionOrder();
        return graph;
    }

    /// 按 (package, path) 字典序排 insertion_order（fromLoader 用；
    /// 简单插入排序，图规模小且只在建图时跑一次）。
    fn sortInsertionOrder(self: *ModuleGraph) void {
        const items = self.insertion_order.items;
        var i: usize = 1;
        while (i < items.len) : (i += 1) {
            const cur = items[i];
            var j = i;
            while (j > 0 and moduleIdLessThan(cur, items[j - 1])) {
                items[j] = items[j - 1];
                j -= 1;
            }
            items[j] = cur;
        }
    }

    /// 拓扑排序（Kahn 算法，显式队列）：依赖先于使用方。
    /// 成功返回调用方拥有的顺序切片（用完调 allocator.free 释放）；
    /// 有环返回 error.CycleDetected，环记录见 lastCycles()。
    /// 输出顺序是确定的：零依赖节点（出度 0）按节点加入顺序出队，
    /// 使用方按边的加入顺序入队。
    pub fn topoSort(self: *ModuleGraph) GraphError![]ModuleId {
        self.clearCycles();
        // 剩余依赖数：边 from -> to 表示 from 依赖 to，故每条边使 from
        // 的剩余依赖数 +1。零依赖节点（出度 0）先出队，出队后沿反向边
        // 递减其使用方的剩余依赖数，归零即入队；输出为依赖先于使用方。
        var remaining = std.HashMap(ModuleId, usize, ModuleId.Context, 80).init(self.allocator);
        defer remaining.deinit();
        for (self.insertion_order.items) |id| {
            try remaining.put(id, 0);
        }
        for (self.edges.items) |edge| {
            const cur = remaining.get(edge.from) orelse 0;
            try remaining.put(edge.from, cur + 1);
        }
        var queue = std.array_list.Managed(ModuleId).init(self.allocator);
        defer queue.deinit();
        var head: usize = 0;
        for (self.insertion_order.items) |id| {
            if (remaining.get(id) orelse 0 == 0) try queue.append(id);
        }
        var order = std.array_list.Managed(ModuleId).init(self.allocator);
        errdefer order.deinit();
        while (head < queue.items.len) {
            const id = queue.items[head];
            head += 1;
            try order.append(id);
            for (self.edges.items) |edge| {
                if (!edge.to.eql(id)) continue;
                const d = remaining.get(edge.from) orelse 0;
                if (d == 0) continue; // 防御：剩余依赖数不可能在处理中先归零
                const next = d - 1;
                try remaining.put(edge.from, next);
                if (next == 0) try queue.append(edge.from);
            }
        }
        if (order.items.len == self.insertion_order.items.len) {
            return try order.toOwnedSlice();
        }
        // 有环：剩余节点（未出队者）为环成员及其使用方；提取简单环。
        var seen = std.HashMap(ModuleId, void, ModuleId.Context, 80).init(self.allocator);
        defer seen.deinit();
        for (order.items) |id| {
            try seen.put(id, {});
        }
        var residue = std.array_list.Managed(ModuleId).init(self.allocator);
        defer residue.deinit();
        for (self.insertion_order.items) |id| {
            if (!seen.contains(id)) try residue.append(id);
        }
        try self.extractCycles(residue.items);
        return error.CycleDetected;
    }

    /// 从 Kahn 剩余集里提取简单环（每条记录是一条首尾相接的环）。
    /// 对每个剩余节点试一次沿边行走：走到已在当前路径上的节点即成环；
    /// 走到死胡同（在剩余集内无后继）则换下一个起点。已记入环的节点
    /// 不再作起点。防御性兜底：若一次也没提取到（理论上不应发生——
    /// 非空剩余集必含环），把整个剩余集记为一条记录，调用方仍能看到
    /// 环成员集合。
    fn extractCycles(self: *ModuleGraph, residue: []const ModuleId) GraphError!void {
        var covered = std.HashMap(ModuleId, void, ModuleId.Context, 80).init(self.allocator);
        defer covered.deinit();
        for (residue) |start| {
            if (covered.contains(start)) continue;
            if (try self.walkCycle(start, residue)) |record| {
                errdefer self.allocator.free(record.cycle_path);
                for (record.cycle_path) |id| {
                    try covered.put(id, {});
                }
                try self.cycles.append(record);
            }
        }
        if (self.cycles.items.len == 0 and residue.len > 0) {
            const owned = try self.allocator.dupe(ModuleId, residue);
            errdefer self.allocator.free(owned);
            try self.cycles.append(.{ .cycle_path = owned, .entry = residue[0] });
        }
    }

    /// 从 start 出发沿剩余集内的边行走，找一条简单环；找到返回记录
    /// （cycle_path 由调用方——extractCycles——接管所有权），
    /// 死胡同返回 null。路径上的节点各只出现一次，首次重访即成环。
    fn walkCycle(
        self: *ModuleGraph,
        start: ModuleId,
        residue: []const ModuleId,
    ) GraphError!?CycleRecord {
        var path = std.array_list.Managed(ModuleId).init(self.allocator);
        defer path.deinit();
        var index_of = std.HashMap(ModuleId, usize, ModuleId.Context, 80).init(self.allocator);
        defer index_of.deinit();
        var current = start;
        while (true) {
            if (index_of.get(current)) |idx| {
                const owned = try self.allocator.dupe(ModuleId, path.items[idx..]);
                return .{ .cycle_path = owned, .entry = current };
            }
            if (!inSlice(residue, current)) return null;
            try index_of.put(current, path.items.len);
            try path.append(current);
            const next = self.firstSuccessorIn(current, residue) orelse return null;
            current = next;
        }
    }

    /// current 在剩余集内的第一个后继（按边的加入顺序）；无后继为 null。
    fn firstSuccessorIn(
        self: *const ModuleGraph,
        current: ModuleId,
        residue: []const ModuleId,
    ) ?ModuleId {
        for (self.edges.items) |edge| {
            if (!edge.from.eql(current)) continue;
            if (inSlice(residue, edge.to)) return edge.to;
        }
        return null;
    }

    /// id 的直接依赖（出边目标）：去重后的边，按边的加入顺序返回。
    /// 目标不在图里报 error.NodeNotFound。返回切片由调用方拥有。
    pub fn dependsOn(self: *const ModuleGraph, id: ModuleId) GraphError![]ModuleId {
        if (!self.nodes.contains(id)) return error.NodeNotFound;
        var out = std.array_list.Managed(ModuleId).init(self.allocator);
        errdefer out.deinit();
        for (self.edges.items) |edge| {
            if (edge.from.eql(id)) try out.append(edge.to);
        }
        return try out.toOwnedSlice();
    }

    /// id 的直接依赖方（入边来源）：去重后的边，按边的加入顺序返回。
    /// 目标不在图里报 error.NodeNotFound。返回切片由调用方拥有。
    pub fn dependents(self: *const ModuleGraph, id: ModuleId) GraphError![]ModuleId {
        if (!self.nodes.contains(id)) return error.NodeNotFound;
        var out = std.array_list.Managed(ModuleId).init(self.allocator);
        errdefer out.deinit();
        for (self.edges.items) |edge| {
            if (edge.to.eql(id)) try out.append(edge.from);
        }
        return try out.toOwnedSlice();
    }

    /// 从 id 出发的传递闭包（DFS 先序，按边的加入顺序发现）。
    /// 只走 loaded/analyzed 态节点：unloaded/loading 态的节点既不进入
    /// 可达集，也不被穿过；起点本身不计入结果。
    /// 目标不在图里报 error.NodeNotFound。返回切片由调用方拥有。
    /// 注意：起点的自身状态不设门——门只设在“被走到的节点”上（见文件头）。
    pub fn reachableFrom(self: *const ModuleGraph, id: ModuleId) GraphError![]ModuleId {
        if (!self.nodes.contains(id)) return error.NodeNotFound;
        var out = std.array_list.Managed(ModuleId).init(self.allocator);
        errdefer out.deinit();
        var seen = std.HashMap(ModuleId, void, ModuleId.Context, 80).init(self.allocator);
        defer seen.deinit();
        try seen.put(id, {});
        var stack = std.array_list.Managed(ModuleId).init(self.allocator);
        defer stack.deinit();
        try stack.append(id);
        while (stack.pop()) |current| {
            if (!current.eql(id)) try out.append(current);
            // 后继按边的加入顺序入栈：倒序压栈使弹出顺序为正序。
            var i = self.edges.items.len;
            while (i > 0) {
                i -= 1;
                const edge = self.edges.items[i];
                if (!edge.from.eql(current)) continue;
                if (seen.contains(edge.to)) continue;
                const node = self.nodes.get(edge.to) orelse continue;
                if (!stateIsTraversable(node.state)) continue;
                try seen.put(edge.to, {});
                try stack.append(edge.to);
            }
        }
        return try out.toOwnedSlice();
    }

    /// 入度为 0 的节点（无依赖方）：按节点加入顺序返回。
    /// 返回切片由调用方拥有。
    pub fn roots(self: *const ModuleGraph) GraphError![]ModuleId {
        var out = std.array_list.Managed(ModuleId).init(self.allocator);
        errdefer out.deinit();
        for (self.insertion_order.items) |id| {
            if (!self.hasIncoming(id)) try out.append(id);
        }
        return try out.toOwnedSlice();
    }

    /// 出度为 0 的节点（不依赖任何模块）：按节点加入顺序返回。
    /// 返回切片由调用方拥有。
    pub fn leaves(self: *const ModuleGraph) GraphError![]ModuleId {
        var out = std.array_list.Managed(ModuleId).init(self.allocator);
        errdefer out.deinit();
        for (self.insertion_order.items) |id| {
            if (!self.hasOutgoing(id)) try out.append(id);
        }
        return try out.toOwnedSlice();
    }

    fn hasIncoming(self: *const ModuleGraph, id: ModuleId) bool {
        for (self.edges.items) |edge| {
            if (edge.to.eql(id)) return true;
        }
        return false;
    }

    fn hasOutgoing(self: *const ModuleGraph, id: ModuleId) bool {
        for (self.edges.items) |edge| {
            if (edge.from.eql(id)) return true;
        }
        return false;
    }
};

/// (package, path) 字典序：先比包名，再比路径。
fn moduleIdLessThan(a: ModuleId, b: ModuleId) bool {
    const pkg = std.mem.order(u8, a.package, b.package);
    if (pkg != .eq) return pkg == .lt;
    return std.mem.order(u8, a.path, b.path) == .lt;
}

/// 线性成员判定（剩余集规模小，不另建表）。
fn inSlice(list: []const ModuleId, id: ModuleId) bool {
    for (list) |item| {
        if (item.eql(id)) return true;
    }
    return false;
}
