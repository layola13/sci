//! 符号依赖图 —— SA 标准库模块化 Phase 4（P4B，sa-dependency-graph）。
//!
//! 职责：提案 §3 的第二层依赖图（Symbol / Function Dependency Graph），
//! 决定哪些函数、全局数据需要进入最终产物；与模块依赖图（P4A 的
//! src/dependency_graph/types.zig）并列，两层共同构成依赖分析的输入。
//!
//! 本文件只建图与查询，不做解析、不做裁剪：
//!   - 不解析源码：边只来自调用方给定的 `SymbolEdge`（Phase 3 的
//!     `LazyLoader.edges`）或调用方显式登记的引用边；
//!   - 不做可达性收敛之外的判定：`reachableSymbols` 只走已记录的边；
//!   - 不裁剪：裁剪是 Phase 5/6（sa-reachability）的事。
//!
//! 符号节点身份约定（与 P4A 约定逐字一致，合并时协调 agent 统一到
//! types.zig；已统一到 types.zig（SymbolNode/SymbolKind 为 re-export））：
//!   - 节点身份 = `module: ModuleId` + `name: []const u8`；
//!   - 节点键字符串 = `<path>:<symbol>`，如 `sa_std/io/print.sa:print`。
//!     `ModuleId.path` 本身已含包名前缀（如 `sa_std/io/print.sa`），故
//!     键就是 path + ":" + name，不再重复拼包名；只有当 path 不以
//!     `package + "/"` 开头时（如相对导入定位出的空包模块），键才拼成
//!     `<package>/<path>:<symbol>`。见 `SymbolNode.key`。
//!   - 模块自身作为符号命名空间根：模块根节点命名约定为
//!     `<module>:<module>`，即节点名取模块自身的 path，其键形如
//!     `sa_std/io/print.sa:sa_std/io/print.sa`。见 `SymbolNode.moduleRoot`。
//!
//! 导入边的落图规则（`addSymbolEdges`）：
//!   - `symbol` 有值的边：落成一条 kind 为 `.import` 的符号边，from 为
//!     导入方模块的模块根节点，to 为目标符号节点（kind 暂记 `.unknown`，
//!     待解析器给出真实 kind 后由 `addSymbol` 升级）；
//!   - `symbol` 为 null 的模块级边：只记一条模块级依赖（`module_deps`），
//!     不展开成符号边——模块级导入的“具体用到了哪个符号”由 Phase 5 的
//!     可达性收敛再定，本文件不猜测、不展开；
//!   - 每条边（无论符号级还是模块级）都同时记一条模块级依赖。
//!
//! 展开后引用（提案 §4：Flattener 会展开宏、内联函数或隐式依赖，
//! Reachability 必须考虑展开后的实际引用，不能只看源码 import）：
//! Flattener 展开后产生的引用边由 `addExpandedEdge` 单独记录，与源码
//! import 边区分 kind（`.import` 之外的 kind）；Phase 5 消费展开后的边。
//!
//! 所有权 / arena 规则（与 Phase 2/3 一致）：
//!   - 图不拥有任何字符串：节点名、模块 path 均为调用方所有（通常是
//!     arena）；`deinit` 只释放容器本身；
//!   - `key` / `definedSymbols` / `referencedSymbols` /
//!     `reachableSymbols` / `moduleDependencies` 返回的 owned 切片由调用方
//!     释放（切片本身），切片内的节点仍借用原字符串；
//!   - 去重按内容（ModuleId.Context / SymbolNode.Context 的哈希与判等）做，
//!     与调用方是否复用同一字符串无关。
//!
//! 不属于本文件：build.zig 注册（后续 Phase / 协调方接线）；P4A 的模块
//! 依赖图类型（`types.zig`，由另一 agent 并行编写，合并时统一）。

const std = @import("std");
const types = @import("../module_resolver/types.zig");
const dep_types = @import("types.zig");

// Phase 2 类型（复用，不重定义）。
pub const ModuleId = types.ModuleId;
pub const SymbolEdge = types.SymbolEdge;
pub const ImportKind = types.ImportKind;

/// 符号的种类。解析器尚未给出真实 kind 时记 `.unknown`，由 `addSymbol`
/// 在拿到更具体的 kind 后升级（`.unknown` 可被任何具体 kind 覆盖，具体
/// kind 之间不互相覆盖，先到为准）。
pub const SymbolKind = dep_types.SymbolKind;

/// 符号引用边的种类：一条引用是从哪个层面产生的。
pub const RefKind = enum {
    /// 源码 import 声明产生的边（`addSymbolEdges` 落图，from 为导入方
    /// 模块根节点）。
    import,
    /// 函数调用产生的边（调用方符号 → 被调函数符号）。
    call,
    /// 一般引用（取值、取地址、类型引用等非调用、非初始化引用）。
    reference,
    /// 全局初始化产生的边（全局量初始化表达式引用到的符号）。
    global_init,
    /// 宏展开产生的边（展开后的实际引用，见 `addExpandedEdge`）。
    macro_expansion,
};

/// 符号节点：身份 = 所属模块 + 符号名。
///
/// 与 P4A 约定逐字一致：节点键字符串形如
/// `<package>/<path>:<symbol>`，实例 `sa_std/io/print.sa:print`
/// （见 `key` 对包名前缀去重的说明）。
pub const SymbolNode = dep_types.SymbolNode;

/// 一条符号引用边：from 符号引用了 to 符号。
pub const SymbolRefEdge = struct {
    from: SymbolNode,
    to: SymbolNode,
    kind: RefKind,

    pub fn eql(self: SymbolRefEdge, other: SymbolRefEdge) bool {
        return self.from.eql(other.from) and
            self.to.eql(other.to) and
            self.kind == other.kind;
    }

    /// 哈希：按 (from, to, kind) 混入——复用节点哈希再混入 kind。
    pub fn hash(self: SymbolRefEdge) u64 {
        var h = self.from.hash();
        h = std.hash.Wyhash.hash(h, self.to.module.package);
        h = std.hash.Wyhash.hash(h, self.to.module.path);
        h = std.hash.Wyhash.hash(h, self.to.name);
        h ^= @as(u64, @intFromEnum(self.kind)) * 0x9e3779b97f4a7c15;
        return h;
    }

    /// `std.HashMap(SymbolRefEdge, V, SymbolRefEdge.Context, ...)` 的上下文。
    pub const Context = struct {
        pub fn hash(_: Context, edge: SymbolRefEdge) u64 {
            return edge.hash();
        }

        pub fn eql(_: Context, a: SymbolRefEdge, b: SymbolRefEdge) bool {
            return a.eql(b);
        }
    };
};

/// 一条模块级依赖：from 模块依赖 to 模块（不展开到符号）。
/// 来源：`SymbolEdge` 落图时每条边都记一条；`symbol == null` 的模块级
/// 边只记这一条，不产生符号边。
pub const ModuleDep = struct {
    from: ModuleId,
    to: ModuleId,

    pub fn eql(self: ModuleDep, other: ModuleDep) bool {
        return self.from.eql(other.from) and self.to.eql(other.to);
    }

    pub fn hash(self: ModuleDep) u64 {
        var h = self.from.hash();
        h = std.hash.Wyhash.hash(h, self.to.package);
        h = std.hash.Wyhash.hash(h, self.to.path);
        return h;
    }

    /// `std.HashMap(ModuleDep, V, ModuleDep.Context, ...)` 的上下文。
    pub const Context = struct {
        pub fn hash(_: Context, dep: ModuleDep) u64 {
            return dep.hash();
        }

        pub fn eql(_: Context, a: ModuleDep, b: ModuleDep) bool {
            return a.eql(b);
        }
    };
};

/// 本文件的方法可能报出的错误：分配失败，或 `addExpandedEdge` 接到
/// 了 `.import` kind（展开边与源码 import 边必须区分 kind）。
pub const GraphError = std.mem.Allocator.Error || error{
    InvalidExpandedEdgeKind,
};

/// 符号依赖图。
///
/// 只记录已给定的边，不解析源码；`reachableSymbols` 只走已记录的边。
/// 节点与边均按内容去重；端点节点在加边时自动登记（kind 为 `.unknown`，
/// 待 `addSymbol` 给出真实 kind 后升级）。
pub const SymbolGraph = struct {
    /// 调用方传入的分配器（通常是 arena）；图不拥有它，也不拥有字符串。
    allocator: std.mem.Allocator,
    /// 已登记的符号节点 → 最新 kind。
    nodes: std.HashMap(SymbolNode, SymbolKind, SymbolNode.Context, std.hash_map.default_max_load_percentage),
    /// 符号引用边（按插入顺序；去重由 edge_set 保证）。
    edges: std.array_list.Managed(SymbolRefEdge),
    /// 边去重集：按 (from, to, kind) 去重。
    edge_set: std.HashMap(SymbolRefEdge, void, SymbolRefEdge.Context, std.hash_map.default_max_load_percentage),
    /// 模块级依赖（按插入顺序；去重由 module_dep_set 保证）。
    module_deps: std.array_list.Managed(ModuleDep),
    /// 模块级依赖去重集。
    module_dep_set: std.HashMap(ModuleDep, void, ModuleDep.Context, std.hash_map.default_max_load_percentage),

    pub fn init(allocator: std.mem.Allocator) SymbolGraph {
        return .{
            .allocator = allocator,
            .nodes = std.HashMap(SymbolNode, SymbolKind, SymbolNode.Context, std.hash_map.default_max_load_percentage).init(allocator),
            .edges = std.array_list.Managed(SymbolRefEdge).init(allocator),
            .edge_set = std.HashMap(SymbolRefEdge, void, SymbolRefEdge.Context, std.hash_map.default_max_load_percentage).init(allocator),
            .module_deps = std.array_list.Managed(ModuleDep).init(allocator),
            .module_dep_set = std.HashMap(ModuleDep, void, ModuleDep.Context, std.hash_map.default_max_load_percentage).init(allocator),
        };
    }

    pub fn deinit(self: *SymbolGraph) void {
        // 只释放容器本身；节点名 / 模块 path 等字符串均为调用方所有
        // （arena 规则），不在此释放。
        self.nodes.deinit();
        self.edges.deinit();
        self.edge_set.deinit();
        self.module_deps.deinit();
        self.module_dep_set.deinit();
    }

    /// 已登记的符号节点数。
    pub fn nodeCount(self: *const SymbolGraph) usize {
        return self.nodes.count();
    }

    /// 已记录的符号引用边数（去重后）。
    pub fn edgeCount(self: *const SymbolGraph) usize {
        return self.edges.items.len;
    }

    /// 已记录的模块级依赖数（去重后）。
    pub fn moduleDepCount(self: *const SymbolGraph) usize {
        return self.module_deps.items.len;
    }

    /// 登记一个符号节点。已存在时不重复登记；若已有 kind 为
    /// `.unknown` 而新 kind 更具体，则升级 kind（具体 kind 之间不
    /// 互相覆盖）。返回 true 当且仅当本次新登记了该节点。
    pub fn addSymbol(self: *SymbolGraph, node: SymbolNode) GraphError!bool {
        if (self.nodes.getPtr(node)) |kind_ptr| {
            if (kind_ptr.* == .unknown and node.kind != .unknown) {
                kind_ptr.* = node.kind;
            }
            return false;
        }
        try self.nodes.put(node, node.kind);
        return true;
    }

    /// 登记一个符号节点的便捷形式（按模块 + 符号名 + kind 构造节点）。
    pub fn addSymbolKind(self: *SymbolGraph, module: ModuleId, name: []const u8, kind: SymbolKind) GraphError!bool {
        return self.addSymbol(.{ .module = module, .name = name, .kind = kind });
    }

    /// 查询节点的已登记 kind；未登记返回 null。
    pub fn symbolKindOf(self: *const SymbolGraph, node: SymbolNode) ?SymbolKind {
        return self.nodes.get(node);
    }

    /// 节点是否已登记。
    pub fn containsSymbol(self: *const SymbolGraph, node: SymbolNode) bool {
        return self.nodes.contains(node);
    }

    /// 加一条符号引用边，按 (from, to, kind) 去重。端点节点自动登记
    /// （未登记过则以 `.unknown` 登记）。返回 true 当且仅当本次新加了边。
    pub fn addEdge(self: *SymbolGraph, from: SymbolNode, to: SymbolNode, kind: RefKind) GraphError!bool {
        const edge = SymbolRefEdge{ .from = from, .to = to, .kind = kind };
        if (self.edge_set.contains(edge)) return false;
        _ = try self.addSymbol(from);
        _ = try self.addSymbol(to);
        try self.edges.append(edge);
        try self.edge_set.put(edge, {});
        return true;
    }

    /// 加一条 Flattener 展开后产生的引用边（宏展开 / 内联 / 隐式依赖）。
    /// 与源码 import 边区分 kind：`kind` 不得为 `.import`，否则报
    /// `error.InvalidExpandedEdgeKind`。Phase 5 消费展开后的边。
    pub fn addExpandedEdge(self: *SymbolGraph, from: SymbolNode, to: SymbolNode, kind: RefKind) GraphError!bool {
        if (kind == .import) return error.InvalidExpandedEdgeKind;
        return self.addEdge(from, to, kind);
    }

    /// 记一条模块级依赖，按 (from, to) 去重。返回 true 当且仅当本次新记。
    pub fn addModuleDep(self: *SymbolGraph, from: ModuleId, to: ModuleId) GraphError!bool {
        const dep = ModuleDep{ .from = from, .to = to };
        if (self.module_dep_set.contains(dep)) return false;
        try self.module_deps.append(dep);
        try self.module_dep_set.put(dep, {});
        return true;
    }

    /// 从 `[]const SymbolEdge` 建图（边源之一是 Phase 3 的
    /// `LazyLoader.edges`，其列表本身不去重，去重在本图内做）：
    ///   - `symbol` 有值：落成一条 kind 为 `.import` 的符号边，from 为
    ///     导入方模块的模块根节点，to 为目标符号节点（kind `.unknown`）；
    ///   - `symbol` 为 null：只记模块级依赖，不展开成符号边（模块级
    ///     导入具体用到哪个符号，留待 Phase 5 可达性收敛，见文件头）；
    ///   - 每条边都同时记一条模块级依赖。
    pub fn addSymbolEdges(self: *SymbolGraph, edges: []const SymbolEdge) GraphError!void {
        for (edges) |edge| {
            _ = try self.addModuleDep(edge.from, edge.to);
            if (edge.symbol) |name| {
                const from = SymbolNode.moduleRoot(edge.from);
                const to = SymbolNode{ .module = edge.to, .name = name, .kind = .unknown };
                _ = try self.addEdge(from, to, .import);
            }
        }
    }

    /// 是否已记录指定的边。
    pub fn hasEdge(self: *const SymbolGraph, from: SymbolNode, to: SymbolNode, kind: RefKind) bool {
        return self.edge_set.contains(.{ .from = from, .to = to, .kind = kind });
    }

    /// 是否已记录指定的模块级依赖。
    pub fn dependsOnModule(self: *const SymbolGraph, from: ModuleId, to: ModuleId) bool {
        return self.module_dep_set.contains(.{ .from = from, .to = to });
    }

    /// 该模块内已定义（已登记）的全部符号节点。返回 owned 切片，调用
    /// 方释放切片本身；顺序未指定（哈希表迭代序）。
    pub fn definedSymbols(self: *const SymbolGraph, module: ModuleId, allocator: std.mem.Allocator) std.mem.Allocator.Error![]SymbolNode {
        var out = std.array_list.Managed(SymbolNode).init(allocator);
        errdefer out.deinit();
        var it = self.nodes.keyIterator();
        while (it.next()) |node_ptr| {
            if (node_ptr.*.module.eql(module)) {
                try out.append(node_ptr.*);
            }
        }
        return out.toOwnedSlice();
    }

    /// 该模块引用到的全部符号节点：所有 from 节点属于该模块的边的 to
    /// 节点（含模块根节点发出的 import 边）。去重。返回 owned 切片，
    /// 调用方释放切片本身；顺序未指定。
    pub fn referencedSymbols(self: *const SymbolGraph, module: ModuleId, allocator: std.mem.Allocator) std.mem.Allocator.Error![]SymbolNode {
        var seen = std.HashMap(SymbolNode, void, SymbolNode.Context, std.hash_map.default_max_load_percentage).init(allocator);
        defer seen.deinit();
        var out = std.array_list.Managed(SymbolNode).init(allocator);
        errdefer out.deinit();
        for (self.edges.items) |edge| {
            if (!edge.from.module.eql(module)) continue;
            if (seen.contains(edge.to)) continue;
            try seen.put(edge.to, {});
            try out.append(edge.to);
        }
        return out.toOwnedSlice();
    }

    /// 从根节点集出发、只走已记录的边可达的全部符号节点。返回中包含
    /// 根节点本身（即使根未登记在图中）。不做解析：未记录的边不存在，
    /// 不会凭空展开。去重，按 BFS 发现顺序返回 owned 切片，调用方
    /// 释放切片本身。
    pub fn reachableSymbols(self: *const SymbolGraph, roots: []const SymbolNode, allocator: std.mem.Allocator) std.mem.Allocator.Error![]SymbolNode {
        var seen = std.HashMap(SymbolNode, void, SymbolNode.Context, std.hash_map.default_max_load_percentage).init(allocator);
        defer seen.deinit();
        var queue = std.array_list.Managed(SymbolNode).init(allocator);
        errdefer queue.deinit();
        for (roots) |root| {
            if (seen.contains(root)) continue;
            try seen.put(root, {});
            try queue.append(root);
        }
        var head: usize = 0;
        while (head < queue.items.len) : (head += 1) {
            const current = queue.items[head];
            for (self.edges.items) |edge| {
                if (!edge.from.eql(current)) continue;
                if (seen.contains(edge.to)) continue;
                try seen.put(edge.to, {});
                try queue.append(edge.to);
            }
        }
        return queue.toOwnedSlice();
    }

    /// 该模块直接依赖的全部模块（模块级依赖的 to 端）。去重（落图时
    /// 已去重，此处不再二次去重）。返回 owned 切片，调用方释放切片本身。
    pub fn moduleDependencies(self: *const SymbolGraph, module: ModuleId, allocator: std.mem.Allocator) std.mem.Allocator.Error![]ModuleId {
        var out = std.array_list.Managed(ModuleId).init(allocator);
        errdefer out.deinit();
        for (self.module_deps.items) |dep| {
            if (dep.from.eql(module)) {
                try out.append(dep.to);
            }
        }
        return out.toOwnedSlice();
    }
};
