//! 依赖图构建器 —— SA 标准库模块化 Phase 4（P4C：图构建器接线）。
//!
//! 职责：把 Phase 3 懒加载器产出的原始依赖边（`LazyLoader.edges`，
//! `[]const SymbolEdge`，不去重）整理成 Phase 4 的两层依赖图（提案 §3）
//! 可消费的输入：
//!   - 模块边列表（Module Dependency Graph 的边集）：按 `(from, to)` 去重；
//!   - 符号边列表（Symbol / Function Dependency Graph 的边集）：只保留
//!     符号级边，模块级边不展开。
//!
//! 本文件是**纯整理器**，不是图本身：
//!   - P4A 的 `ModuleGraph` 与 P4B 的 `SymbolGraph` / `RetainSet` 由另两个
//!     agent 并行编写，本任务不依赖它们的落盘文件，也不定义图结构；
//!   - 本构建器只定义输入 / 输出契约（见下），合并时协调 agent 把本构建器
//!     的产出接到真实图类型上；
//!   - 环不重新检测：`cyclesFrom` 只透传 Phase 2/3 已发现的 `CycleRecord`。
//!
//! 输入 / 输出契约：
//!   - 输入 1：`edges: []const SymbolEdge`（Phase 2 `types.zig` 的形状，
//!     复用，不重定义）。调用方通常传 `loader.edges.items`；builder 只读
//!     输入，不改 loader / flattener / resolver 的任何状态。
//!   - 输入 2：模块状态查询接口 `StateFn`，即
//!     `*const fn (ModuleId) ?ModuleState`。调用方传一个适配器函数：
//!     对 `LazyLoader` 传包着 `loader.stateOf` 的适配器，对 `ModuleTable`
//!     传包着 `table.stateOf` 的适配器。函数指针不带上下文，适配器须由
//!     调用方在自己的作用域里写（示例见 `StateFn` 的文档注释）；
//!     合并时协调 agent 把适配器落到真实接线处。
//!   - 输入 3：`records: []const CycleRecord`（Phase 2 `closure.zig` 的
//!     形状，经 `loader.zig` re-export；复用，不重定义）。只透传，不检测。
//!   - 输出 1：`[]ModuleEdge` —— 去重后的模块边（`from`/`to` + 首条边的 kind（via 字段）。自边（from == to）跳过并计数；重复边只保留首次出现的 kind。
//!   - 输出 2：`[]SymbolEdge` —— 只含符号级边（`symbol != null`）的列表，
//!     保持输入顺序，不去重（去重是图结构的职责）；模块级边
//!     （`symbol == null`）不展开，记入 `skipped_module_edges`。
//!   - 输出 3：`FilterResult` —— `filterByState` 按状态分流的结果：
//!     `loaded` / `analyzed` 进 `ready`，`unloaded` / `loading` / 未登记
//!     （`stateOf` 返回 null）进 `pending`。
//!   - 输出 4：`[]CycleRecord` —— 透传的环记录列表（与输入同一批记录，
//!     只复制记录本身，`cycle_path` 切片仍借用调用方的存储）。
//!
//! 所有权 / arena 规则（与 Phase 2 的 A8、Phase 3 的 loader 一致）：
//!   - 调用方传入一个 arena 分配器；builder 用它分配一切输出切片与内部
//!     容器；`deinit` 只释放容器本身（去重用的临时表在每次调用内建内释），
//!     不释放任何字符串与 `cycle_path` 切片（它们由调用方统一释放 arena）。
//!   - 返回的切片在 builder 下一次改变同一列表的调用前有效；需要跨多次
//!     构建长期持有时，调用方应自行复制。
//!   - builder 只读输入：不写 `LazyLoader.modules` / `edges` / `cycles`，
//!     不写 `ModuleTable` 的任何 map，不调 `markAnalyzed` / `markLoading`。
//!
//! 不属于本文件：
//!   - 图结构本身（P4A `ModuleGraph`、P4B `SymbolGraph` / `RetainSet`）；
//!   - 可达性分析与裁剪（Phase 5，提案 §3 的 Reachability-based DCE）；
//!   - 循环检测与环是否合法的语义判定（Phase 3 `cycle.zig` 的
//!     `detectCycle` / `CyclePolicy`；本文件只透传记录）；
//!   - 模块定位与加载（Phase 2 locator / Phase 3 loader）；
//!   - build.zig 注册（后续 Phase / 协调方的事；本任务只新增文件）。

const std = @import("std");
const types = @import("../module_resolver/types.zig");
const closure_mod = @import("../module_resolver/closure.zig");
const dep_types = @import("types.zig");

// Phase 2 类型（复用，不重定义）。
pub const ModuleId = types.ModuleId;
pub const ModuleState = types.ModuleState;
pub const ImportKind = types.ImportKind;
pub const SymbolEdge = types.SymbolEdge;
// CycleRecord 复用 closure.zig 的形状（loader.zig 同款 re-export）。
pub const CycleRecord = closure_mod.CycleRecord;

/// 模块依赖图的一条边：模块级去重后的 `(from, to)`，kind 取首次出现的边。
///
/// 与 `SymbolEdge` 的区别：没有 `symbol` 字段——模块图只关心“模块 A 依赖
/// 模块 B”，不关心是哪个符号；符号级细节留在 `[]SymbolEdge` 里，供
/// P4B 的 SymbolGraph 消费。
pub const ModuleEdge = dep_types.ModuleEdge;

/// 模块状态查询接口：调用方提供的适配器函数指针。
///
/// 函数指针本身不带上下文，适配器须由调用方在自己的作用域里写，例如：
///
/// ```zig
/// // 对 LazyLoader 的适配（合并时由协调 agent 落到真实接线处）：
/// const LoaderCtx = struct {
///     var ptr: *const LazyLoader = undefined;
///     fn stateOf(id: ModuleId) ?ModuleState {
///         return ptr.stateOf(id);
///     }
/// };
/// LoaderCtx.ptr = &loader;
/// const filtered = try builder.filterByState(ids, LoaderCtx.stateOf);
///
/// // 对 ModuleTable 的适配（flattener 侧过渡层，见 Phase 3 M2）：
/// const TableCtx = struct {
///     var ptr: *const ModuleTable = undefined;
///     fn stateOf(id: ModuleId) ?ModuleState {
///         return ptr.stateOf(id);
///     }
/// };
/// TableCtx.ptr = &table;
/// const filtered = try builder.filterByState(ids, TableCtx.stateOf);
/// ```
///
/// 返回 null 表示该模块未在状态源里登记；`filterByState` 把未登记的模块
/// 按保守口径归入 `pending`（绝不假设未登记即就绪）。
pub const StateFn = *const fn (ModuleId) ?ModuleState;

/// `filterByState` 的分流结果：两个切片均借用 builder 内部的暂存列表，
/// 在下一次 `filterByState` 调用前有效（见文件头所有权规则）。
pub const FilterResult = struct {
    /// 状态为 `loaded` / `analyzed` 的模块 id（可进入依赖图）。
    ready: []ModuleId,
    /// 状态为 `unloaded` / `loading` 或未登记的模块 id（尚未就绪，
    /// 调用方应等加载推进后再重跑本构建器）。
    pending: []ModuleId,
};

/// 模块边去重的键：`(from, to)` 对，kind 不参与去重（保留首条 kind）。
const ModuleEdgeKey = struct {
    from: ModuleId,
    to: ModuleId,

    pub const Context = struct {
        pub fn hash(_: Context, key: ModuleEdgeKey) u64 {
            var h = key.from.hash();
            h = std.hash.Wyhash.hash(h, key.to.package);
            h = std.hash.Wyhash.hash(h, key.to.path);
            return h;
        }

        pub fn eql(_: Context, a: ModuleEdgeKey, b: ModuleEdgeKey) bool {
            return a.from.eql(b.from) and a.to.eql(b.to);
        }
    };
};

/// 依赖图构建器：纯整理器，只读输入，不改任何加载器 / 解析器状态。
pub const GraphBuilder = struct {
    allocator: std.mem.Allocator,
    /// `buildModuleEdges` 的累计产出（去重后的模块边）。
    module_edges: std.array_list.Managed(ModuleEdge),
    /// `buildSymbolEdges` 的累计产出（符号级边，保持输入顺序）。
    symbol_edges: std.array_list.Managed(SymbolEdge),
    /// `cyclesFrom` 的累计产出（透传的环记录）。
    cycles: std.array_list.Managed(CycleRecord),
    /// `filterByState` 的暂存：就绪 id 列表。
    ready_ids: std.array_list.Managed(ModuleId),
    /// `filterByState` 的暂存：未就绪 id 列表。
    pending_ids: std.array_list.Managed(ModuleId),

    /// 计数器（调用方可读；`reset` 清零）：
    /// `buildModuleEdges` 跳过的自边（from == to）条数。
    skipped_self_edges: usize = 0,
    /// `buildModuleEdges` 去掉的重复模块边条数。
    duplicate_module_edges: usize = 0,
    /// `buildSymbolEdges` 跳过的模块级边（symbol == null）条数。
    skipped_module_edges: usize = 0,
    /// `buildSymbolEdges` 保留的符号级边条数。
    kept_symbol_edges: usize = 0,

    pub fn init(allocator: std.mem.Allocator) GraphBuilder {
        return .{
            .allocator = allocator,
            .module_edges = std.array_list.Managed(ModuleEdge).init(allocator),
            .symbol_edges = std.array_list.Managed(SymbolEdge).init(allocator),
            .cycles = std.array_list.Managed(CycleRecord).init(allocator),
            .ready_ids = std.array_list.Managed(ModuleId).init(allocator),
            .pending_ids = std.array_list.Managed(ModuleId).init(allocator),
        };
    }

    /// 只释放容器本身；字符串与 `cycle_path` 切片由调用方统一释放 arena。
    pub fn deinit(self: *GraphBuilder) void {
        self.module_edges.deinit();
        self.symbol_edges.deinit();
        self.cycles.deinit();
        self.ready_ids.deinit();
        self.pending_ids.deinit();
        self.* = undefined;
    }

    /// 清空全部累计产出与计数器（保留已分配的容量），供下一轮构建复用。
    pub fn reset(self: *GraphBuilder) void {
        self.module_edges.clearRetainingCapacity();
        self.symbol_edges.clearRetainingCapacity();
        self.cycles.clearRetainingCapacity();
        self.ready_ids.clearRetainingCapacity();
        self.pending_ids.clearRetainingCapacity();
        self.skipped_self_edges = 0;
        self.duplicate_module_edges = 0;
        self.skipped_module_edges = 0;
        self.kept_symbol_edges = 0;
    }

    /// 从原始边集构建模块边列表。
    ///
    /// 规则：
    ///   - 自边（`from == to`）跳过，记入 `skipped_self_edges`；
    ///   - 按 `(from, to)` 去重，重复边记入 `duplicate_module_edges`，
    ///     只保留首次出现的 kind；
    ///   - 符号级边与模块级边在此处不区分——两者都落成一条模块边
    ///     （提案 §7：两种导入统一成依赖图；粒度区分在符号边列表里保留）。
    ///
    /// 返回累计的模块边切片（含此前调用的产出；只要本轮去重结果时调
    /// `reset` 后再构建，或直接取返回切片的尾段）。
    pub fn buildModuleEdges(
        self: *GraphBuilder,
        edges: []const SymbolEdge,
    ) std.mem.Allocator.Error![]ModuleEdge {
        var seen = std.HashMap(ModuleEdgeKey, void, ModuleEdgeKey.Context, 80).init(self.allocator);
        defer seen.deinit();
        // 本轮之前已产出的边同样参与去重：先把已有产出登记进 seen，
        // 避免跨多次调用出现重复模块边。
        for (self.module_edges.items) |e| {
            try seen.put(.{ .from = e.from, .to = e.to }, {});
        }
        for (edges) |edge| {
            if (edge.from.eql(edge.to)) {
                self.skipped_self_edges += 1;
                continue;
            }
            const key = ModuleEdgeKey{ .from = edge.from, .to = edge.to };
            if (seen.contains(key)) {
                self.duplicate_module_edges += 1;
                continue;
            }
            try seen.put(key, {});
            try self.module_edges.append(.{
                .from = edge.from,
                .to = edge.to,
                .via = edge.kind,
            });
        }
        return self.module_edges.items;
    }

    /// 从原始边集构建符号边列表。
    ///
    /// 规则：
    ///   - 只保留 `symbol != null` 的符号级边，保持输入顺序，不去重
    ///     （符号边的去重是 P4B SymbolGraph 的职责；同一符号被多处
    ///     import 时图层自行合并）；
    ///   - 模块级边（`symbol == null`）不展开成符号边，记入
    ///     `skipped_module_edges`——模块级导入的具体符号收敛是 Phase 5
    ///     可达性分析的事（提案 §3；`string/` 等无 prelude 的域见缺口）。
    ///
    /// 返回累计的符号边切片。
    pub fn buildSymbolEdges(
        self: *GraphBuilder,
        edges: []const SymbolEdge,
    ) std.mem.Allocator.Error![]SymbolEdge {
        for (edges) |edge| {
            if (edge.symbol == null) {
                self.skipped_module_edges += 1;
                continue;
            }
            try self.symbol_edges.append(edge);
            self.kept_symbol_edges += 1;
        }
        return self.symbol_edges.items;
    }

    /// 按模块状态分流 id 列表：`loaded` / `analyzed` 进 `ready`，
    /// 其余（`unloaded` / `loading` / 未登记 null）进 `pending`。
    ///
    /// `stateOf` 由调用方提供（见 `StateFn` 的适配示例）。本方法只读
    /// 状态，不推进任何模块的状态机；`pending` 里的模块须由加载器继续
    /// 推进后，调用方重跑本构建器。
    ///
    /// 返回的两个切片借用 builder 内部暂存列表，下一次调用本方法前有效。
    pub fn filterByState(
        self: *GraphBuilder,
        ids: []const ModuleId,
        stateOf: StateFn,
    ) std.mem.Allocator.Error!FilterResult {
        self.ready_ids.clearRetainingCapacity();
        self.pending_ids.clearRetainingCapacity();
        for (ids) |id| {
            switch (stateOf(id) orelse .unloaded) {
                .loaded, .analyzed => try self.ready_ids.append(id),
                .unloaded, .loading => try self.pending_ids.append(id),
            }
        }
        return .{
            .ready = self.ready_ids.items,
            .pending = self.pending_ids.items,
        };
    }

    /// 透传环记录：把 Phase 2/3 已发现的 `CycleRecord` 原样记入 builder，
    /// 不重新检测、不改写、不判定环是否合法。
    ///
    /// 只复制记录本身（`cycle_path` 切片仍借用调用方的存储，见文件头
    /// 所有权规则）；环是否合法由 Phase 3 `cycle.zig` 的 `CyclePolicy`
    /// 判定，图层消费时只读这些记录。
    ///
    /// 返回累计的环记录切片。
    pub fn cyclesFrom(
        self: *GraphBuilder,
        records: []const CycleRecord,
    ) std.mem.Allocator.Error![]CycleRecord {
        try self.cycles.appendSlice(records);
        return self.cycles.items;
    }
};
