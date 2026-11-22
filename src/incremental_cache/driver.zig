//! 增量驱动 —— SA 标准库模块化 Phase 7（sa-incremental-cache，P7C）。
//!
//! 职责（只做计划，不编译、不写缓存、不删缓存条目）：
//!   - 提供 Phase 7 的集成入口（`planIncremental`）：按固定五步接线
//!     P7B 的版本校验（`validateAll`）→ P7B 的失效闭包（`invalidate`）
//!     → P7A 的键计算（`CacheKey.compute`）→ P7B 的命中查询
//!     （`lookup`）→ 返回 `ReusePlan`；
//!   - 定义复用计划的类型（`ReusePlan`，含 `deinit` 与 `stats` 拷贝）；
//!   - 提供人类可读的文本摘要（`summarizePlan`）。
//!
//! 不属于本文件（硬边界）：
//!   - 不实现缓存键、缓存条目、缓存统计、缓存库本身：`CacheKey` /
//!     `CacheEntry` / `CacheStats` 的正本在 P7A 的 `types.zig`，
//!     `CacheStore` / `validateAll` / `invalidate` / `lookup` 的正本
//!     在 P7B 的 `store.zig`；本文件只 import、不重定义（见下文
//!     “类型正本与合并对齐”）；
//!   - 不编译任何模块：`reuse` 里的模块由调用方取缓存产物，`rebuild`
//!     里的模块由调用方重编；本文件不调用任何编译入口；
//!   - 不读文件：模块内容一律由调用方通过 `content_of` 回调传入
//!     （见 `planIncremental` 的文档注释）；本文件不做任何磁盘 I/O；
//!   - 不改 `LazyLoader` 与 `ModuleGraph` 的任何状态：两者均为
//!     `*const` 输入，只读；失效只发生在 `CacheStore` 内部（P7B 的
//!     `invalidate` 负责丢弃条目），不碰 loader / 图的状态机；
//!   - 不发明保留规则判定逻辑、不做可达性分析、不做裁剪（那分别是
//!     Phase 4 / Phase 5 / Phase 6 的事）。
//!
//! `planIncremental` 的五步（缺一不可，顺序固定；见 `planIncremental`
//! 的文档注释）：
//!   1. `validateAll` —— 整库版本校验（编译器版本 + 插件版本对不上
//!      先整库失效，由 P7B 在调用内完成；本步骤不产出计划条目）；
//!   2. `invalidate` —— 求失效闭包（changed + 反向依赖，loaded /
//!      analyzed 态才进闭包；changed 本身含在闭包里）；
//!   3. 对 `loader.modules` 表里每个 loaded / analyzed 态模块算
//!      `CacheKey`（内容经 `content_of` 回调取，不直接读文件）；
//!   4. 键命中 store 即 reuse、未命中即 rebuild（已失效的模块不算键，
//!      直接进 rebuild）；
//!   5. 返回 `ReusePlan`（拥有 reuse / rebuild / invalidated 三个
//!      owned 切片与 `stats` 本次计数的拷贝）。
//!
//! 状态门（第 2 / 3 步共用同一口径，与 Phase 4 的 `stateIsTraversable`
//! 一致：只有 loaded / analyzed 态可参与）：
//!   - unloaded 态模块不进 plan（还没加载，无物可缓存）；
//!   - loading 态模块不进 plan（正在加载中，留待下轮）；
//!   - 第 2 步的门由 P7B 的 `invalidate` 在闭包内执行（以模块图的
//!     节点状态为准，见“已知缺口”第 2 项）；第 3 步的门由本文件按
//!     `loader.modules` 表里登记的权威状态执行。
//!
//! 候选顺序（确定性）：第 3 步先把候选模块按 `(package, path)` 字典序
//! 排过再分类，因此同一输入下 `reuse` / `rebuild` 的顺序是确定的，
//! 与 `loader.modules` 的 `HashMap` 枚举序无关（与 Phase 4
//! `fromLoader` 按 `(package, path)` 排序的口径一致）。排序用本文件
//! 的插入排序实现（不依赖 `std.sort` 的版本间 API 形态；sa_std 约
//! 645 个模块的规模下足够）。
//!
//! 所有权 / arena 规则（与 Phase 2 的 A8、Phase 3 的 loader、Phase 4
//! 的图、Phase 5 的报告、Phase 6 的 DCE 一致）：
//!   - 调用方传入一个 arena 分配器；`ReusePlan` 用它分配一切 owned
//!     切片（`reuse` / `rebuild` / `invalidated`）；`ReusePlan` 存
//!     一份该分配器（`allocator` 字段，与 `ReachabilityReport` /
//!     `Convergence` 同款），`deinit` 用它释放；
//!   - `ReusePlan.deinit` 统一释放三个 owned 切片；调用方只调一次
//!     `ReusePlan.deinit`，不得再单独释放其中任一切片（避免重复释放）；
//!   - 长度为 0 的切片不释放（它可能是一段编译期空切片，而非分配器
//!     产物；与 P5B `Convergence.deinit` / P6C `DceResult` 同款口径）；
//!   - `ModuleId` 为值拷贝（`package` / `path` 字符串仍借用调用方
//!     arena），`deinit` 不释放任何借用串；
//!   - `stats` 是本次计数的拷贝（值类型），不拥有任何切片；
//!   - `summarizePlan` 的所有权见下节；`content_of` 回调返回的内
//!     容只借用、不拥有，至少在当次 `CacheKey.compute` 调用期间有效。
//!
//! `summarizePlan` 的所有权（任务书二选一，本文件选静态拼接）：
//!   - 返回指向文件级静态缓冲区（`summary_buf`，512 字节）的借用切片；
//!   - 调用方如需久存请自行复制；连续两次调用后一次覆盖前一次；
//!   - 非线程安全；摘要只有 4 个数字，最长约 140 字节，512 字节的
//!     缓冲区在事实上不会溢出，溢出时退化为一条固定短句（不断言、不报错）。
//!
//! 类型正本与合并对齐（P7A / P7B 尚未落盘，本文件按任务书给定的名字
//! import；调用形状的假设集中于此，合并时由协调 agent 按 P7A / P7B
//! 落盘逐项核对，见 MANIFEST §5 对齐点 C1–C5）：
//!   - C1：`CacheKey.compute(content, compiler_version, plugin_version,
//!     opt_level) CacheKey`——纯函数，无分配器、无错误集；内容哈希与
//!     版本 / 优化级别的折叠方式由 P7A 定，本文件只传参；
//!   - C2：`store_mod.validateAll(store, compiler_version, plugin_version,
//!     opt_level, allocator) Allocator.Error![]ModuleId`——返回本次因版本
//!     失配而失效的模块列表（owned；版本全对上时为空列表）。合并裁决
//!     （M2）：`planIncremental` 第 ① 步调它、取回的列表立即释放（长度
//!     为 0 的不释放）；版本失配不另设专用字段记录——失配的条目已从库
//!     里删掉（记入 `store.stats.invalidated` 累计），受影响的模块在
//!     第 ④ 步自然全不命中、进 rebuild，失配只表现为命中率 0%；
//!     是否补字段留待接线 Phase（见 MANIFEST §7.3 第 2 项，合并时已决：
//!     Phase 7 不补字段）；
//!   - C3：`store_mod.invalidate(store, changed, module_graph,
//!     allocator) ![]ModuleId`——P7B 的自由函数：既丢弃库内对应条目，
//!     又返回 owned 失效闭包（changed 本身含在内；loaded / analyzed
//!     态才进闭包；门以模块图节点状态为准）。若 P7B 落盘为方法或多一
//!     个 `loader` 参数，合并时改这一处调用点；
//!   - C4：`store.lookup(key) ?CacheEntry`——方法调用，null = 未命中；
//!     本文件只用它作命中测试，不消费返回的条目值（复用产物的取用是
//!     调用方的事）。若 P7B 只提供 `contains`，合并时换这一处调用；
//!   - C5：`CacheStats` 的字段以 P7A 落盘为准：`hits` / `misses` /
//!     `invalidated` / `evicted`（皆 `u64`，无 `total` 字段；合并裁决
//!     M3：第 ⑤ 步的字面量按落盘写，`evicted = 0`——本次计划不淘汰条
//!     目）。字段含义：hits = reuse 数；misses = rebuild 数；
//!     invalidated = invalidated 数；evicted = 本次淘汰数（恒为 0）；
//!
//! 已知缺口：
//!   - 上述 C1–C5 未经编译验证（只跑 ast-check；P7A / P7B 尚未落盘，
//!     `types.zig` / `store.zig` 两处 import 在合并前悬空，见 MANIFEST §8）；
//!   - `summarizePlan` 只产纯文本，无结构化（JSON）输出（与 Phase 5
//!     `summarize` / Phase 6 `summarizeDce` 同款口径；JSON 输出本身是
//!     Phase 5 §6 第 5 项待裁决）；不逐个列出复用 / 重编模块（模块可能
//!     成百上千，逐个列出无意义；要看明细读 `plan.reuse` / `plan.rebuild`）；
//!   - facade（`src/incremental_cache.zig`）由协调合并时写，本任务不写；
//!   - build.zig 注册（后续 Phase / 协调方接线），本任务不做。
//!
//! 不属于本文件：build.zig 注册（后续 Phase / 协调方接线）；P7A 的
//! 键 / 条目 / 统计定义；P7B 的库实现、版本校验与失效闭包实现。

const std = @import("std");
const types_mod = @import("types.zig");
const store_mod = @import("store.zig");
const loader_mod = @import("../module_loader/loader.zig");
const module_graph_mod = @import("../dependency_graph/module_graph.zig");

// 复用，不重定义（正本见文件头“类型正本与合并对齐”）。
pub const CacheKey = types_mod.CacheKey;
pub const CacheEntry = types_mod.CacheEntry;
pub const CacheStats = types_mod.CacheStats;
pub const CacheStore = store_mod.CacheStore;
pub const invalidate = store_mod.invalidate;
pub const ModuleId = loader_mod.ModuleId;
pub const ModuleState = loader_mod.ModuleState;
pub const LazyLoader = loader_mod.LazyLoader;
pub const ModuleGraph = module_graph_mod.ModuleGraph;

/// `summarizePlan` 的静态缓冲区（见文件头“所有权”一节）。
var summary_buf: [512]u8 = undefined;

/// 增量复用计划：一次 `planIncremental` 的全部产出。
///
/// `reuse` / `rebuild` 互斥且完备：`loader.modules` 表里每个
/// loaded / analyzed 态模块恰好进其中之一（按 `(package, path)`
/// 字典序排过）；`invalidated` 是本次失效的模块（第 2 步的闭包，
/// 含 changed 本身）；`stats` 是本次计数的拷贝（值类型；evicted 恒
/// 为 0，本次计划不淘汰条目）。
/// `allocator` 为调用方传入的 arena 分配器，`deinit` 用它释放。
pub const ReusePlan = struct {
    /// 调用方传入的分配器（`deinit` 用它释放三个 owned 切片）。
    allocator: std.mem.Allocator,
    /// 命中缓存、可复用的模块（按 `(package, path)` 字典序）。
    reuse: []ModuleId = &.{},
    /// 须重编的模块（键未命中，或在本次失效闭包里；按 `(package, path)` 字典序）。
    rebuild: []ModuleId = &.{},
    /// 本次失效的模块（第 2 步的闭包，含 changed 本身；顺序为 `invalidate` 返回的顺序）。
    invalidated: []ModuleId = &.{},
    /// 本次计数的拷贝：hits = reuse 数；misses = rebuild 数；
    /// invalidated = invalidated 数；total = 本次参与计划的模块数。
    stats: CacheStats,

    /// 统一释放三个 owned 切片；调用后实例不可再用。
    /// 长度为 0 的切片不释放（见文件头所有权规则）。
    pub fn deinit(self: *ReusePlan) void {
        if (self.reuse.len > 0) self.allocator.free(self.reuse);
        if (self.rebuild.len > 0) self.allocator.free(self.rebuild);
        if (self.invalidated.len > 0) self.allocator.free(self.invalidated);
        self.* = undefined;
    }
};

/// `ModuleId` 的字典序：先 `package` 后 `path`（与 Phase 4
/// `fromLoader` 的节点排序口径一致）。
fn moduleIdLessThan(a: ModuleId, b: ModuleId) bool {
    const by_package = std.mem.order(u8, a.package, b.package);
    if (by_package != .eq) return by_package == .lt;
    return std.mem.order(u8, a.path, b.path) == .lt;
}

/// 插入排序（原地）：候选规模约 sa_std 的 645 个模块，足够；
/// 不依赖 `std.sort` 的版本间 API 形态。
fn sortModuleIds(items: []ModuleId) void {
    var i: usize = 1;
    while (i < items.len) : (i += 1) {
        const key = items[i];
        var j = i;
        while (j > 0 and moduleIdLessThan(key, items[j - 1])) {
            items[j] = items[j - 1];
            j -= 1;
        }
        items[j] = key;
    }
}

/// Phase 7 的集成入口：算一次增量复用计划。只做计划，不编译模块、
/// 不写缓存、不改 loader / 图的状态（见文件头“硬边界”）。
///
/// 五步固定顺序（缺一不可）：
///   1. `validateAll(store, compiler_version, plugin_version, opt_level,
///      allocator)` —— 整库版本校验；版本对不上时 P7B 在调用内先整库
///      失效并返回失配模块列表，本步骤取回后立即释放（失配后库已空，
///      后续查询自然全不命中；失配无专用字段，见文件头对齐点 C2）；
///   2. `invalidate(store, changed, module_graph, allocator)` ——
///      求失效闭包（changed + 反向依赖，loaded / analyzed 态才进
///      闭包；changed 本身含在内）。返回的 owned 切片所有权转移给
///      `ReusePlan.invalidated`；
///   3. 对 `loader.modules` 表里每个 loaded / analyzed 态模块算
///      `CacheKey`：内容经 `content_of` 回调取（`content_of(id)` 返回
///      该模块的当前内容；未知模块返回空串 `""`，不得返回 null）；
///      unloaded 态模块不进 plan（还没加载，无物可缓存）；loading
///      态模块不进 plan（正在加载中，留待下轮）；
///   4. 键命中 store 即 reuse、未命中即 rebuild；已在失效闭包里的
///      模块不算键，直接进 rebuild；
///   5. 返回 `ReusePlan`（拥有 reuse / rebuild / invalidated 三个
///      owned 切片与 `stats` 本次计数的拷贝；`stats.hits` = reuse 数，
///      `stats.misses` = rebuild 数，`stats.invalidated` = invalidated
///      数，`stats.evicted` = 0）。
///
/// 失败语义：只报分配失败（推断错误集，实为
/// `std.mem.Allocator.Error`）。中间步骤报分配失败时，已得的中间
/// 产物由 errdefer 清理，不留半成品 `ReusePlan`。
pub fn planIncremental(
    store: *CacheStore,
    loader: *const LazyLoader,
    module_graph: *const ModuleGraph,
    changed: []const ModuleId,
    compiler_version: []const u8,
    plugin_version: []const u8,
    opt_level: u8,
    content_of: *const fn (module: ModuleId) []const u8,
    allocator: std.mem.Allocator,
) !ReusePlan {
    // 1. 整库版本校验（版本对不上先整库失效，由 P7B 在调用内完成；
    // 取回的失配模块列表立即释放：失配后库已空，后续查询自然全不命中；
    // 失配的条目数已记入 store.stats.invalidated 累计；版本失配无专用
    // 字段可记，见文件头对齐点 C2）。长度为 0 的切片不释放。
    const version_invalidated = try store_mod.validateAll(store, compiler_version, plugin_version, opt_level, allocator);
    if (version_invalidated.len > 0) allocator.free(version_invalidated);

    // 2. 失效闭包（changed + 反向依赖；changed 本身含在内）。
    // 所有权随第 5 步转移给 ReusePlan；中途失败由 errdefer 释放。
    const invalidated = try store_mod.invalidate(store, changed, module_graph, allocator);
    errdefer allocator.free(invalidated);

    // 失效成员集合（O(1)  membership 检查；键为值拷贝，串仍借用 arena）。
    var invalid_set = std.HashMap(ModuleId, void, ModuleId.Context, std.hash_map.default_max_load_percentage).init(allocator);
    defer invalid_set.deinit();
    for (invalidated) |id| {
        try invalid_set.put(id, {});
    }

    // 3. 候选：loader.modules 表里 loaded / analyzed 态的模块。
    // unloaded 不进 plan（无物可缓存）；loading 不进 plan（留待下轮）。
    var candidates = std.array_list.Managed(ModuleId).init(allocator);
    defer candidates.deinit();
    var it = loader.modules.iterator();
    while (it.next()) |kv| {
        const state = kv.value_ptr.state;
        if (state != .loaded and state != .analyzed) continue;
        try candidates.append(kv.key_ptr.*);
    }
    // 确定性：按 (package, path) 字典序排过再分类。
    sortModuleIds(candidates.items);

    // 4. 分类：已失效 → rebuild（不算键）；否则算键，命中 → reuse，未命中 → rebuild。
    var reuse = std.array_list.Managed(ModuleId).init(allocator);
    errdefer reuse.deinit();
    var rebuild = std.array_list.Managed(ModuleId).init(allocator);
    errdefer rebuild.deinit();
    for (candidates.items) |id| {
        if (invalid_set.contains(id)) {
            try rebuild.append(id);
            continue;
        }
        const key = CacheKey.compute(content_of(id), compiler_version, plugin_version, opt_level);
        if (store.lookup(key) != null) {
            try reuse.append(id);
        } else {
            try rebuild.append(id);
        }
    }

    // 5. 返回 ReusePlan（所有权转移：reuse / rebuild / invalidated）。
    const reuse_slice = try reuse.toOwnedSlice();
    errdefer allocator.free(reuse_slice);
    const rebuild_slice = try rebuild.toOwnedSlice();
    return .{
        .allocator = allocator,
        .reuse = reuse_slice,
        .rebuild = rebuild_slice,
        .invalidated = invalidated,
        .stats = .{
            .hits = reuse_slice.len,
            .misses = rebuild_slice.len,
            .invalidated = invalidated.len,
            .evicted = 0,
        },
    };
}

/// 人类可读的文本摘要：一行——复用数、重编数、失效数、命中率。
///
/// 只产纯文本，无结构化（JSON）输出（见文件头“已知缺口”）。
/// 返回静态缓冲区的借用切片（见文件头“所有权”一节）：调用方如需
/// 久存请自行复制；连续两次调用后一次覆盖前一次；非线程安全。
/// 不逐个列出复用 / 重编模块（要看明细读 `plan.reuse` / `plan.rebuild`）。
/// 命中率 = reuse / (reuse + rebuild)，整数百分比；无待计划模块时记为“—”。
pub fn summarizePlan(plan: *const ReusePlan) []const u8 {
    const total = plan.reuse.len + plan.rebuild.len;
    if (total == 0) {
        return std.fmt.bufPrint(
            &summary_buf,
            "增量复用计划：复用 0 / 重编 0 / 失效 {d} / 命中率 —（无待计划模块）",
            .{plan.invalidated.len},
        ) catch "增量复用计划：摘要过长";
    }
    const pct = plan.reuse.len * 100 / total;
    return std.fmt.bufPrint(
        &summary_buf,
        "增量复用计划：复用 {d} / 重编 {d} / 失效 {d} / 命中率 {d}%",
        .{ plan.reuse.len, plan.rebuild.len, plan.invalidated.len, pct },
    ) catch "增量复用计划：摘要过长";
}
