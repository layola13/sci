//! 增量编译缓存：内存存储与失效 —— SA 标准库模块化 Phase 7（sa-incremental-cache，P7B）。
//!
//! 职责：只做缓存条目的内存表与失效逻辑，不做磁盘 I/O、不建图、不跑
//! 可达性分析、不触发任何重编（失效只是把条目标记/删掉，重编是调用方
//! 的事；磁盘持久化是 P7C 的事）。
//!
//! 类型约定（与 P7A 的 types.zig 同名同字段，P7A 正本为准；本文件只
//! import、不重定义；写本文件时 P7A 尚未落盘，合并时以 P7A 落盘为准对齐）：
//!   - `CacheKey` 四分量：content_hash + compiler_version + plugin_version
//!     + opt_level。键含版本分量，版本变了自然是另一个键、自然 miss。
//!   - `CacheEntry` 字段：key / module / state / artifact_path /
//!     artifact_hash / created_at。本文件只读 `key` 与 `module`，其余
//!     字段只做值透传，不解读、不比较。
//!   - `CacheError`：P7A 落盘只有三项（VersionMismatch / CorruptEntry /
//!     KeyMismatch），不含 `error.OutOfMemory`；本文件唯一的分配失败出口
//!     因此不走 CacheError——合并时裁决（M1）：`store` / `evictModules` /
//!     `invalidate` / `validateAll` 一律返回 `std.mem.Allocator.Error!T`
//!    （与 Phase 6 `prune` 同款口径：唯一可达错误是 OutOfMemory）。
//!     `dependents()` 的 GraphError 在 `invalidate` 内按
//!     NodeNotFound 跳过 / OutOfMemory 直传 / 其余 unreachable 收窄
//!     （CycleDetected / InvalidState 在 dependents 路径上不可达）。
//!   - `CacheStats`：P7A 落盘四字段 hits / misses / invalidated / evicted
//!    （皆 u64，默认 0）；本文件只碰前三项；`init` 用 `std.mem.zeroes`
//!     全零初始化，不逐字段写字面量，以免合并时漏字段。
//!   - `CacheKey.compiler_version` / `plugin_version` 为 `[]const u8`，
//!     `opt_level` 为 `u8`——由 `validateAll` 的形参类型（`[]const u8` /
//!     `[]const u8` / `u8`）反推；若 P7A 落盘类型不同，合并时改比较处。
//!
//! 失效语义（`invalidate`）：
//!   - 变了的模块本身失效；再沿模块图反向依赖闭包失效——即所有（直接或
//!     传递）依赖于任一 changed 模块的模块都失效。边 `from -> to` 表示
//!     from 依赖 to，所以从 changed 出发要走入边（dependents），不是
//!     `reachableFrom` 的正向（reachableFrom 走的是“依赖了谁”，方向反了）。
//!   - 状态门：只走 loaded / analyzed 态节点（`stateIsTraversable`，与
//!     `reachableFrom` 同款口径）。unloaded / loading 态节点既不进入
//!     失效集，也不被穿过；其依赖方若还依赖别的已失效模块，会经那条路被
//!     发现。门只设在“被走到的节点”上，changed 种子本身不设门（同款）。
//!   - 返回列表是失效的模块集合（changed 去重后 + 反向闭包），owned，
//!     调用方释放；changed 里有、store 里没有的模块不报错、只计入返回
//!     列表。`stats.invalidated` 只计实际从 store 里删掉的条目数，不计
//!     返回列表长度（两者可能不同：无条目的模块计入列表、不计入计数；
//!     一个模块多条 content_hash 条目只在列表里出现一次、计数里算多条）。
//!   - 返回顺序是确定的：changed 按输入顺序（去重），其后按 DFS 发现顺序，
//!     同层兄弟按边的加入顺序（`dependents()` 的返回顺序）。
//!
//! 版本校验（`validateAll`，对应 2026-11-20 教训）：compiler_version /
//! plugin_version / opt_level 任一对不上的条目全部失效——版本变了旧缓存
//! 必须整体失效，不能静默复用。返回的模块列表按 (package, path) 排序
//! （HashMap 迭代顺序不稳定，排序后输出才确定），一个模块多条过期条目
//! 只返回一次；删掉的条目同样计入 `stats.invalidated`。
//!
//! 所有权 / 借用规则（与 Phase 2 的 A8、Phase 4 的图一致）：
//!   - 表里存的 `CacheKey` / `CacheEntry` 均为值拷贝，但其中的字符串
//!     （版本串、artifact_path 等）只借用，不拥有。`store` 覆盖同键旧条目
//!     时不释放旧串；`CacheStore.deinit` 只释放表容器本身，不释放任何借用串。
//!   - `invalidate` / `validateAll` 返回的 `[]ModuleId` 是调用方拥有的
//!     owned 切片，用完调 allocator.free 释放；空结果同样返回长度 0 的
//!     切片（与 ModuleGraph 的查询约定一致）。
//!   - `CacheStore` 不拥有 allocator，只借用（调用方在 store 活着时不得
//!     释放它）。
//!
//! 未做的事（按任务书硬约束）：不跑 zig build、不跑 zig test、不修 bug、
//! 不动 sa_std/、tests/、build.zig*、不合 main；`types.zig`（P7A 正本）
//! 尚未落盘，本文件只 import，合并时对齐；磁盘持久化 / 加载不在本文件。

const std = @import("std");
const types_mod = @import("types.zig");
const graph_mod = @import("../dependency_graph/module_graph.zig");
const resolver_types = @import("../module_resolver/types.zig");

// P7A 类型（只 import、不重定义；P7A 正本为准）。
pub const CacheKey = types_mod.CacheKey;
pub const CacheEntry = types_mod.CacheEntry;
pub const CacheError = types_mod.CacheError;
pub const CacheStats = types_mod.CacheStats;
// 复用类型（不重定义）：ModuleGraph 经 dependency_graph，ModuleId 经
// module_resolver（module_graph.zig 亦有同款 re-export，同一类型）。
pub const ModuleGraph = graph_mod.ModuleGraph;
pub const ModuleId = resolver_types.ModuleId;
const stateIsTraversable = graph_mod.stateIsTraversable;

/// 增量缓存的内存表：键是含版本分量的 `CacheKey`，值是整条 `CacheEntry`。
///
/// 键含版本分量是第一道防线（版本变了自然 miss）；`validateAll` 是第二道
/// 防线（整库扫一遍，把版本对不上的旧条目清掉，不留静默复用的口子）。
pub const CacheStore = struct {
    /// 调用方传入的分配器（只借用，不拥有）。
    allocator: std.mem.Allocator,
    /// 条目表：键与值均为值拷贝，其中的字符串只借用（见文件头）。
    entries: std.AutoHashMap(CacheKey, CacheEntry),
    /// 累计计数器（hits / misses / invalidated；`init` 全零初始化）。
    stats: CacheStats,

    /// 空表 + 零计数器。allocator 由调用方传入。
    pub fn init(allocator: std.mem.Allocator) CacheStore {
        return .{
            .allocator = allocator,
            .entries = std.AutoHashMap(CacheKey, CacheEntry).init(allocator),
            .stats = std.mem.zeroes(CacheStats),
        };
    }

    /// 只释放表容器本身，不释放任何借用串（条目里的版本串 /
    /// artifact_path 等均由调用方拥有）。调用后实例不可再用。
    pub fn deinit(self: *CacheStore) void {
        self.entries.deinit();
        self.* = undefined;
    }

    /// 查表：命中返回条目拷贝并记 `hits`，未命中返回 null 并记 `misses`。
    /// 版本变了是另一个键，自然走未命中分支（不做任何版本比较）。
    pub fn lookup(self: *CacheStore, key: CacheKey) ?CacheEntry {
        if (self.entries.get(key)) |entry| {
            self.stats.hits += 1;
            return entry;
        }
        self.stats.misses += 1;
        return null;
    }

    /// 存一条：同键覆盖旧条目（旧 artifact_path 只借用、不拥有，覆盖时
    /// 不释放旧串）；新键追加。唯一可达错误是 OutOfMemory（M1：返回
    /// Allocator.Error，不走 CacheError）。
    pub fn store(self: *CacheStore, entry: CacheEntry) std.mem.Allocator.Error!void {
        try self.entries.put(entry.key, entry);
    }

    /// 按键删一条：删掉了返回 true，键不在表里返回 false。
    /// 只删表项，不动 stats（计数口径见 `invalidate` / `validateAll`）。
    pub fn evict(self: *CacheStore, key: CacheKey) bool {
        return self.entries.remove(key);
    }

    /// 清空全表（保留表容量）。只清表，不动 stats：计数器是累计口径，
    /// clear 不是一个新的统计周期。
    pub fn clear(self: *CacheStore) void {
        self.entries.clearRetainingCapacity();
    }

    /// 删掉 `module` 属于 `ids` 的全部条目，返回实际删除的条目数。
    /// 一个模块可因不同 content_hash 而有多条，须全表扫描、按模块匹配，
    /// 不能只按单个键删。供 `invalidate` / `validateAll` 共用；先收
    /// 集待删键、再逐个删（不在迭代器活着时改表）。
    fn evictModules(self: *CacheStore, ids: []const ModuleId) std.mem.Allocator.Error!usize {
        var doomed = std.array_list.Managed(CacheKey).init(self.allocator);
        defer doomed.deinit();
        var it = self.entries.iterator();
        while (it.next()) |kv| {
            if (moduleIdInSlice(ids, kv.value_ptr.*.module)) {
                try doomed.append(kv.key_ptr.*);
            }
        }
        var removed: usize = 0;
        for (doomed.items) |key| {
            if (self.entries.remove(key)) removed += 1;
        }
        return removed;
    }
};

/// 失效：changed 本身 + 沿模块图反向依赖闭包的全部模块。
///
/// 走法是反向（入边方向），不是 `reachableFrom` 的正向：边 `from -> to`
/// 表示 from 依赖 to，to 变了则所有依赖 to 的模块都失效，故用
/// `dependents()` 逐层反向展开。状态门只设在被走到的节点上
/// （loaded / analyzed 才进集、才穿过；unloaded / loading 不进集、也不
/// 被穿过），changed 种子本身不设门（与 `reachableFrom` 同款）。
///
/// 返回失效的模块列表（owned，调用方释放；changed 去重后在前，其后按
/// DFS 发现顺序，同层兄弟按边的加入顺序）。失效的条目从 store 里删掉
/// 并记 `invalidated` 计数；changed 里有、store 里没有的模块不报错、
/// 只计入返回列表（不计入 `invalidated`）。图里没有的 changed 模块
/// （`dependents` 报 NodeNotFound）同样不报错：它本身已在返回列表里，
/// 只是没有已知的依赖方可以展开。
pub fn invalidate(
    store: *CacheStore,
    changed: []const ModuleId,
    module_graph: *const ModuleGraph,
    allocator: std.mem.Allocator,
) std.mem.Allocator.Error![]ModuleId {
    var result = std.array_list.Managed(ModuleId).init(allocator);
    errdefer result.deinit();
    var seen = std.HashMap(ModuleId, void, ModuleId.Context, 80).init(allocator);
    defer seen.deinit();
    var stack = std.array_list.Managed(ModuleId).init(allocator);
    defer stack.deinit();

    // 种子：changed 本身全部失效（去重），不论其在图里的状态、也不论
    // store 里有没有对应条目。
    for (changed) |id| {
        if (seen.contains(id)) continue;
        try seen.put(id, {});
        try result.append(id);
        try stack.append(id);
    }

    // 反向闭包：DFS，用 dependents() 沿入边展开。
    while (stack.pop()) |current| {
        const direct = module_graph.dependents(current) catch |err| switch (err) {
            // 图里没有该模块：无已知的依赖方，跳过展开（本身已在结果里）。
            error.NodeNotFound => continue,
            error.OutOfMemory => return error.OutOfMemory,
            // dependents() 除以上两项无其他可达错误（无环判定、无状态迁移）。
            else => unreachable,
        };
        // dependents() 返回的切片调用方拥有；包一层块作用域，defer 在块尾释放。
        {
            defer allocator.free(direct);
            for (direct) |dep| {
                if (seen.contains(dep)) continue;
                // 先记 seen：unloaded / loading 节点即使被跳过也不必反复查。
                try seen.put(dep, {});
                const state = module_graph.stateOf(dep) orelse continue;
                if (!stateIsTraversable(state)) continue;
                try result.append(dep);
                try stack.append(dep);
            }
        }
    }

    const removed = try store.evictModules(result.items);
    store.stats.invalidated += removed;
    return try result.toOwnedSlice();
}

/// 整库版本校验：compiler_version / plugin_version / opt_level 任一对不
/// 上的条目全部失效（2026-11-20 教训：版本变了旧缓存必须整体失效，
/// 不能静默复用；键里含版本分量只能防住新查，对已入库的旧条目须由本
/// 函数扫一遍清掉）。
///
/// 返回失效条目所属的模块列表（owned，调用方释放；按 (package, path)
/// 排序，一个模块多条过期条目只返回一次）。删掉的条目计入
/// `stats.invalidated`。版本全对上时返回空列表、不动表。
pub fn validateAll(
    store: *CacheStore,
    expected_compiler: []const u8,
    expected_plugin: []const u8,
    expected_opt: u8,
    allocator: std.mem.Allocator,
) std.mem.Allocator.Error![]ModuleId {
    var doomed = std.array_list.Managed(CacheKey).init(allocator);
    defer doomed.deinit();
    var modules = std.array_list.Managed(ModuleId).init(allocator);
    errdefer modules.deinit();
    var seen = std.HashMap(ModuleId, void, ModuleId.Context, 80).init(allocator);
    defer seen.deinit();

    // 先收集：迭代器活着时不改表。
    var it = store.entries.iterator();
    while (it.next()) |kv| {
        const entry = kv.value_ptr.*;
        const stale = !std.mem.eql(u8, entry.key.compiler_version, expected_compiler) or
            !std.mem.eql(u8, entry.key.plugin_version, expected_plugin) or
            entry.key.opt_level != expected_opt;
        if (!stale) continue;
        try doomed.append(kv.key_ptr.*);
        if (!seen.contains(entry.module)) {
            try seen.put(entry.module, {});
            try modules.append(entry.module);
        }
    }

    var removed: usize = 0;
    for (doomed.items) |key| {
        if (store.entries.remove(key)) removed += 1;
    }
    store.stats.invalidated += removed;

    // HashMap 迭代顺序不稳定，返回前按 (package, path) 排序，输出才确定。
    std.sort.block(ModuleId, modules.items, {}, moduleIdLessThan);
    return try modules.toOwnedSlice();
}

/// 线性成员判定（失效集规模小，不另建表；与 module_graph.zig 的
/// inSlice 同款做法）。
fn moduleIdInSlice(list: []const ModuleId, id: ModuleId) bool {
    for (list) |item| {
        if (item.eql(id)) return true;
    }
    return false;
}

/// (package, path) 字典序：先比包名，再比路径（与 module_graph.zig 的
/// moduleIdLessThan 同款口径，供 `validateAll` 的返回排序用）。
fn moduleIdLessThan(_: void, a: ModuleId, b: ModuleId) bool {
    const pkg = std.mem.order(u8, a.package, b.package);
    if (pkg != .eq) return pkg == .lt;
    return std.mem.order(u8, a.path, b.path) == .lt;
}
