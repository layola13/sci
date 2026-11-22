//! 缓存过滤 —— SA 标准库模块化 Phase 8（并行模块分析，P8B）。
//!
//! 职责：把一层模块按 Phase 7 的 `ReusePlan` 切成两半——该分析的
//! （`to_analyze`）与可跳过的（`skipped`）。只做切分，不分析模块、
//! 不改 loader / 图 / store 的任何状态、不读文件。
//!
//! 背景：提案 STD-MODULARIZATION-PROPOSAL.md §5 第 8 阶段（并行模块
//! 分析，P2）接 Phase 7（增量编译缓存，P2）：Phase 7 的
//! `planIncremental` 已算出一次编译里哪些模块可复用（`plan.reuse`）、
//! 哪些须重编（`plan.rebuild`）、哪些已失效（`plan.invalidated`）；
//! 本文件把这个计划落到每一层上，供 P8C 驱动按层取用——每层只把
//! `to_analyze` 交给 `worker.zig` 的 `analyzeOne`，`skipped` 里的
//! 模块直接记 outcome 为 `.skipped_cached`（该映射是 P8C 驱动的事，
//! 本文件只产出切片，不产出 `WorkResult`）。
//!
//! `splitLayer` 的切分规则（三条，按序判定）：
//!   1. 落在 `plan.rebuild` 里的 → `to_analyze`；
//!   2. 落在 `plan.reuse` 里的 → `skipped`；
//!   3. 两边都不在的（未进计划，如 unloaded 未规划模块）→ 保守进
//!      `to_analyze`（漏分析是错，重复分析只是慢；宁可多算，不可漏算）。
//! 重叠优先：若某模块同时落在 `reuse` 与 `rebuild` 里（按 Phase 7
//! 的约定两者互斥，不应发生；防御性处理），第 1 条先判定，进
//! `to_analyze`——同样是保守选择。
//!
//! 顺序：两个输出切片均保持输入顺序（输入已按 `(package, path)` 排过，
//! 本文件不重排；与 Phase 7 `ReusePlan` 的 reuse / rebuild 切片口径一致）。
//!
//! 成员判定：线性扫描（`isReuse` / `isRebuild` 各扫一遍对应切片）。
//! `reuse` / `rebuild` 切片已按 `(package, path)` 排过，但本文件不用
//! 二分查找，避 `std.sort` 版本间 API；sa_std 约 645 模块规模下线性
//! 扫描足够（最坏约一层 645 个模块 × 计划 645 条 ≈ 42 万次 `eql`，
//! 与 Phase 4 的 O(E) 注记同款做法——规模小处用简单实现，不上复杂结构）。
//!
//! 所有权 / arena 规则（与 Phase 2 的 A8、Phase 7 的 `ReusePlan` 一致）：
//!   - 调用方传入一个 arena 分配器；`LayerSplit` 用它分配两个 owned
//!     切片（`to_analyze` / `skipped`），并存一份该分配器（`allocator`
//!     字段），`deinit` 用它释放；
//!   - `LayerSplit.deinit` 只释两个 owned 切片，长度为 0 的不释放
//!     （它可能是一段编译期空切片，而非分配器产物；与 Phase 7
//!     `ReusePlan.deinit` 同款口径）；调用方只调一次 `deinit`，不得
//!     再单独释放其中任一切片（避免重复释放）；
//!   - `ModuleId` 为值拷贝（`package` / `path` 字符串仍借用调用方
//!     arena），`deinit` 不释放任何借用串。
//!
//! 类型正本（本文件只 import、不重定义）：
//!   - `ReusePlan`——正本在 Phase 7 的 `src/incremental_cache/driver.zig`
//!    （`reuse` / `rebuild` / `invalidated` 三个 `[]ModuleId` 切片，
//!     均按 `(package, path)` 字典序）；
//!   - `ModuleId`——复用 `src/module_loader/loader.zig`（其与
//!     `src/dependency_graph/types.zig` 的同名 re-export 是同一声明，
//!     均源自 `src/module_resolver/types.zig`，类型身份一致；与 Phase 7
//!     `driver.zig` 的 import 口径一致）。
//!
//! 已知缺口（只记，不擅自改结构）：
//!   - N1：`splitLayer` 只信计划，不查 loader 状态。若计划算出后、
//!     切分前 loader 状态变了（如某复用模块被重新加载回 `.loaded`），
//!     本文件仍按旧计划把它划进 `skipped`。计划与切分应在同一轮内
//!     先后完成（P8C 驱动的责任）；是否在切分时二次核对 loader 状态，
//!     待协调 agent 裁决。
//!   - N2：本文件未经编译验证（只跑 `zig ast-check`，见任务书硬约束）；
//!     跨文件调用形状（`ReusePlan` 三个切片的字段名、`ModuleId.eql`
//!     的签名）靠读 `driver.zig` / `module_resolver/types.zig` 落盘
//!     代码核对，未经编译。
//!
//! 不属于本文件：build.zig 注册（后续 Phase / 协调方接线）；facade
//! （由协调 agent 合并时写）；计划本身的计算（那是 Phase 7
//! `planIncremental` 的事）；`skipped` 到 `WorkResult`（outcome
//! `.skipped_cached`）的映射（那是 P8C 驱动的事）。

const std = @import("std");
const driver_mod = @import("../incremental_cache/driver.zig");
const loader_mod = @import("../module_loader/loader.zig");

// 复用，不重定义（正本见文件头“类型正本”）。
pub const ModuleId = loader_mod.ModuleId;
pub const ReusePlan = driver_mod.ReusePlan;

/// 一层模块的缓存切分结果：该分析的与可跳过的。
///
/// 两个切片均保持输入顺序（见文件头“顺序”一节）；`allocator` 为调用方
/// 传入的 arena 分配器，`deinit` 用它释放。
pub const LayerSplit = struct {
    /// 须分析的模块（`plan.rebuild` 成员 + 未进计划者；保持输入顺序）。
    to_analyze: []ModuleId = &.{},
    /// 可跳过的模块（`plan.reuse` 成员；保持输入顺序；P8C 驱动记
    /// outcome 为 `.skipped_cached`）。
    skipped: []ModuleId = &.{},
    /// 调用方传入的分配器（`deinit` 用它释放两个 owned 切片）。
    allocator: std.mem.Allocator,

    /// 释放两个 owned 切片；调用后实例不可再用。
    /// 长度为 0 的切片不释放（见文件头所有权规则）。
    pub fn deinit(self: *LayerSplit) void {
        if (self.to_analyze.len > 0) self.allocator.free(self.to_analyze);
        if (self.skipped.len > 0) self.allocator.free(self.skipped);
        self.* = undefined;
    }
};

/// 该模块是否在复用计划里（线性扫描 `plan.reuse`；见文件头“成员判定”）。
pub fn isReuse(plan: *const ReusePlan, id: ModuleId) bool {
    for (plan.reuse) |candidate| {
        if (id.eql(candidate)) return true;
    }
    return false;
}

/// 该模块是否在重编计划里（线性扫描 `plan.rebuild`；见文件头“成员判定”）。
pub fn isRebuild(plan: *const ReusePlan, id: ModuleId) bool {
    for (plan.rebuild) |candidate| {
        if (id.eql(candidate)) return true;
    }
    return false;
}

/// 把一层模块按 Phase 7 的 `ReusePlan` 切分（规则见文件头）。
///
/// 只做切分：不分析模块、不改任何状态、不读文件。失败语义只报分配失败
/// （`std.mem.Allocator.Error`）；中途分配失败时已得的中间产物由
/// errdefer 清理，不留半成品 `LayerSplit`。
pub fn splitLayer(
    modules: []const ModuleId,
    plan: *const ReusePlan,
    allocator: std.mem.Allocator,
) std.mem.Allocator.Error!LayerSplit {
    var to_analyze = std.array_list.Managed(ModuleId).init(allocator);
    errdefer to_analyze.deinit();
    var skipped = std.array_list.Managed(ModuleId).init(allocator);
    errdefer skipped.deinit();
    for (modules) |id| {
        // 重建优先于复用（重叠时保守进 to_analyze；见文件头“切分规则”）。
        if (isRebuild(plan, id)) {
            try to_analyze.append(id);
        } else if (isReuse(plan, id)) {
            try skipped.append(id);
        } else {
            // 两边都不在：未进计划，保守进 to_analyze。
            try to_analyze.append(id);
        }
    }
    const to_analyze_slice = try to_analyze.toOwnedSlice();
    errdefer allocator.free(to_analyze_slice);
    const skipped_slice = try skipped.toOwnedSlice();
    return .{
        .to_analyze = to_analyze_slice,
        .skipped = skipped_slice,
        .allocator = allocator,
    };
}
