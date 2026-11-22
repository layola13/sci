//! 层调度 —— SA 标准库模块化 Phase 8（sa-parallel-analysis，P8A）。
//!
//! 职责：只回答“把图里的模块按依赖深度分层，同一层的模块可以并行分析”
//! 这一件事。入口只有一个：`computeLayers(graph, allocator)`。
//! 不分析模块、不跑线程、不做状态过滤、不做缓存过滤（见下文“状态门”）。
//!
//! 算法（分两步）：
//!   1. 调 `graph.topoSort()` 拿拓扑序；有环时 `error.CycleDetected` 直传，
//!      环记录留在 `graph.lastCycles()` 里，本文件不报诊断、不写
//!      ErrorContext（与 Phase 4 的口径一致：环是否合法由语义规则定，
//!      提案 §2）；
//!   2. 按拓扑序逐个节点算层：`layer(m) = 0`（`dependsOn(m)` 为空），否则
//!      `1 + max(layer(d))`（`d` 取遍 `dependsOn(m)`，即 m 直接依赖的模块）。
//!
//! 拓扑序方向：`ModuleGraph.topoSort()` 输出依赖先于使用方（Kahn 算法，
//! 零依赖节点先出队；例：A 依赖 B、B 依赖 C 时输出 C、B、A）。本文件正序
//! 遍历拓扑序算层，算 `layer(m)` 时其依赖的层必已算好（任务 105 按 Jev
//! 裁决 fix_impl_deps_first 改实现就文档，倒序同步改回正序）。
//! 依赖深度未算好时本文件用 `unreachable`
//! 响亮失败，不静默回退成深度 0（与 Phase 7 M1 的收窄口径一致）。
//!
//! 边方向：`ModuleGraph` 里边 `from -> to` 表示 from 依赖 to；
//! `dependsOn` 返回直接后继（即依赖方），与 Phase 7 `invalidate` 的
//! 口径一致（`invalidate` 用反向的 `dependents()`，本文件用正向的
//! `dependsOn()`）。
//!
//! 层内顺序（确定性）：每层的模块落盘前按 `(package, path)` 字典序排过
//! （先 package 后 path；手写插入排序，不依赖 `std.sort` 版本间 API，
//! 与 Phase 4 `fromLoader`、Phase 7 `planIncremental` 同款做法），
//! 输出确定性不受 `HashMap` 枚举序影响。
//!
//! 状态门：`computeLayers` 对图里全部节点分层，不按状态过滤——
//! `unloaded` / `loading` 态节点也进层。状态过滤与缓存过滤是 P8C 驱动
//! 与 P8B 的事（P8C 按 `stateIsTraversable` 与 Phase 7 的缓存计划决定
//! 哪些层内模块真正执行、哪些跳过；`AnalysisOutcome.skipped_cached` /
//! `.already_analyzed` 由 P8B/P8C 产出，本文件不产出）。
//!
//! 空图：返回 0 层、`total_modules` 0、`max_width` 0。
//!
//! 所有权（与 `Schedule` 的口径一致）：返回的 `Schedule` 拥有 `layers`
//! 数组与各层 `modules` 切片，调用方用完调 `Schedule.deinit` 释放；
//! 本文件不拥有 `graph`（只读借用，不改图的状态；`topoSort()` 的副作用
//! 只限于其自带的 `lastCycles()` 记录）。另注意：`topoSort()` 与
//! `dependsOn()` 返回的切片由图的分配器（`graph.allocator`）分配，故用
//! `graph.allocator` 释放，不用传入的 `allocator`（合并 M3；两者是同
//! 一 arena 时等价）。

const std = @import("std");
const types_mod = @import("types.zig");
const graph_mod = @import("../dependency_graph/module_graph.zig");

// 共享类型（复用，不重定义；类型正本见 types.zig / module_graph.zig）。
pub const ModuleId = types_mod.ModuleId;
pub const ModuleGraph = graph_mod.ModuleGraph;
pub const Layer = types_mod.Layer;
pub const Schedule = types_mod.Schedule;
pub const ParallelError = types_mod.ParallelError;

/// 把图里的全部模块按依赖深度分层：同一层的模块互不依赖，可以并行分析。
///
/// 层定义：`layer(m) = 0`（m 不依赖任何模块），否则 `1 + max(layer(d))`
/// （d 取遍 `dependsOn(m)`）。返回的 `Schedule.layers` 按 `depth` 升序排列，
/// 每层内的模块按 `(package, path)` 字典序排过；`total_modules` 为图中节点
/// 总数，`max_width` 为最宽一层的模块数。空图返回 0 层、总数 0、最宽 0。
///
/// 错误：有环时 `error.CycleDetected` 直传（环记录见 `graph.lastCycles()`）；
/// 分配失败时 `error.OutOfMemory`。不对节点做状态过滤（见文件头“状态门”）。
/// 本函数不消费 `ParallelConfig`（线程数与确定性开关是 P8C 驱动的事）。
pub fn computeLayers(graph: *ModuleGraph, allocator: std.mem.Allocator) ParallelError!Schedule {
    const order = try graph.topoSort();
    defer if (order.len > 0) graph.allocator.free(order);

    if (order.len == 0) {
        return .{
            .layers = &.{},
            .total_modules = 0,
            .max_width = 0,
            .allocator = allocator,
        };
    }

    // 每节点的依赖深度。正序遍历拓扑序：topoSort() 输出依赖先于使用方
    // （见文件头），算 layer(m) 时其依赖的层必已在表里；未命中即排序
    // 不变式被破坏，响亮失败（不静默当 0 层）。
    var depth_of = std.HashMap(ModuleId, usize, ModuleId.Context, 80).init(allocator);
    defer depth_of.deinit();

    var max_depth: usize = 0;
    for (order) |id| {
        const deps = try graph.dependsOn(id);
        defer if (deps.len > 0) graph.allocator.free(deps);
        var depth: usize = 0;
        for (deps) |dep| {
            const dep_depth = depth_of.get(dep) orelse unreachable;
            if (dep_depth + 1 > depth) depth = dep_depth + 1;
        }
        try depth_of.put(id, depth);
        if (depth > max_depth) max_depth = depth;
    }

    // 按深度计数，再按计数分配各层的 modules 切片（深度 0..max_depth 连续：
    // 有深度 d 的节点必有深度 d-1 的依赖，故每层非空）。
    const layer_count = max_depth + 1;
    const counts = try allocator.alloc(usize, layer_count);
    defer allocator.free(counts);
    @memset(counts, 0);
    for (order) |id| {
        counts[depth_of.get(id).?] += 1;
    }

    var layers = try allocator.alloc(Layer, layer_count);
    errdefer {
        for (layers) |layer| {
            if (layer.modules.len > 0) allocator.free(layer.modules);
        }
        allocator.free(layers);
    }
    for (layers, 0..) |*layer, depth| {
        layer.* = .{ .depth = depth, .modules = &.{} };
    }
    for (layers) |*layer| {
        if (counts[layer.depth] > 0) {
            layer.modules = try allocator.alloc(ModuleId, counts[layer.depth]);
        }
    }

    // 第二遍按拓扑序把节点填进各自的层（填入顺序不重要，落盘前统一排序）。
    const cursors = try allocator.alloc(usize, layer_count);
    defer allocator.free(cursors);
    @memset(cursors, 0);
    for (order) |id| {
        const depth = depth_of.get(id).?;
        const layer = &layers[depth];
        layer.modules[cursors[depth]] = id;
        cursors[depth] += 1;
    }

    var max_width: usize = 0;
    for (layers) |layer| {
        sortModuleIds(layer.modules);
        if (layer.modules.len > max_width) max_width = layer.modules.len;
    }

    return .{
        .layers = layers,
        .total_modules = order.len,
        .max_width = max_width,
        .allocator = allocator,
    };
}

/// `ModuleId` 的字典序：先 `package` 后 `path`（与 Phase 4 `fromLoader`
/// 的节点排序、Phase 7 `planIncremental` 的候选排序口径一致）。
fn moduleIdLessThan(a: ModuleId, b: ModuleId) bool {
    const by_package = std.mem.order(u8, a.package, b.package);
    if (by_package != .eq) return by_package == .lt;
    return std.mem.order(u8, a.path, b.path) == .lt;
}

/// 插入排序（原地）：层规模约 sa_std 的 645 个模块，足够；
/// 不依赖 `std.sort` 的版本间 API 形态。
fn sortModuleIds(items: []ModuleId) void {
    var j: usize = 1;
    while (j < items.len) : (j += 1) {
        const key = items[j];
        var k = j;
        while (k > 0 and moduleIdLessThan(key, items[k - 1])) {
            items[k] = items[k - 1];
            k -= 1;
        }
        items[k] = key;
    }
}
