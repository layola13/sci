//! 并行模块分析共享类型 —— SA 标准库模块化 Phase 8（sa-parallel-analysis，P8A）。
//!
//! 职责：本模块（`src/parallel_analysis/`）内共享类型的正本。P8B（分析
//! 执行器）与 P8C（并行驱动）复用本文件，不重定义；协调 agent 合并时写
//! facade（`src/parallel_analysis.zig`），本文件不写 facade。
//!
//! 背景：提案 STD-MODULARIZATION-PROPOSAL.md §5 第 8 阶段（并行模块分析，
//! P2）与 §2（四种模块状态）。Phase 8 只做“哪些模块可以并行分析、按什么
//! 顺序分层”的计划与类型，不编译模块、不跑分析、不写缓存（那是 P8B/P8C
//! 与后续 Phase 的事）。
//!
//! 类型正本与复用（不重定义）：
//!   - `ModuleId` / `ModuleState` / `GraphError` / `stateIsTraversable`
//!     经 `src/dependency_graph/types.zig` 转发（与 Phase 4 的图同款口径；
//!     `ModuleId` 的正本在 `src/module_resolver/types.zig`）；
//!   - `ModuleGraph` 的正本在 `src/dependency_graph/module_graph.zig`，
//!     由 `scheduler.zig` 直接 import，本文件不转发（避免两处转发口径漂移）；
//!   - `AnalysisOutcome` / `Layer` / `Schedule` / `ParallelConfig` /
//!     `ParallelError` 的正本在本文件，P8B 的 `analyzeOne` 与 P8C 的报告
//!     都用它们。
//!
//! 四态（`AnalysisOutcome`，提案 §2 的状态机在并行分析里的投影）：
//!   - `analyzed` —— 本轮实际执行了分析并完成；
//!   - `skipped_cached` —— 命中 Phase 7 的增量缓存，本轮跳过；
//!   - `already_analyzed` —— 本轮之前已是 `analyzed` 态，无需再做；
//!   - `failed` —— 本模块分析出错（错误详情见 P8B `WorkResult` 的
//!     detail 字段，本枚举只记“失败了”这一事实，不携带错误值）。
//!
//! 确定性口径（与 Phase 4 `fromLoader`、Phase 7 `planIncremental` 同款）：
//! 同一层内的模块、以及同一输入下 `Schedule` 的层划分，只按 `(package, path)`
//! 字典序决定（先 package 后 path），不受 `HashMap` 枚举序影响；
//! `ParallelConfig.deterministic = true` 时层内顺序固定为该字典序。
//!
//! 所有权 / arena 规则（与 Phase 2 的 A8、Phase 3 的 loader、Phase 4 的图、
//! Phase 7 的 `ReusePlan` 一致）：
//!   - 调用方传入一个 arena 分配器；`Schedule` 用它分配一切 owned 切片
//!     （`layers` 数组与各层 `modules` 切片）；`Schedule` 存一份该分配器
//!     （`allocator` 字段），`deinit` 用它释放；
//!   - `deinit` 只释放容器（`layers` 数组与各层 `modules` 切片），不释放
//!     任何借用串（`ModuleId` 的 package/path 均由调用方 arena 统一释放）；
//!     长度为 0 的切片不释放；调用后实例不可再用。

const std = @import("std");
const dg_types = @import("../dependency_graph/types.zig");

// Phase 4 类型（复用，不重定义；经 dependency_graph/types.zig 转发）。
pub const ModuleId = dg_types.ModuleId;
pub const ModuleState = dg_types.ModuleState;
pub const GraphError = dg_types.GraphError;
pub const stateIsTraversable = dg_types.stateIsTraversable;

/// `computeLayers` 的错误集：图错误（含 `CycleDetected` / `NodeNotFound` /
/// `InvalidState`）并上分配失败。
pub const ParallelError = GraphError || std.mem.Allocator.Error;

/// 一轮并行分析里一个模块的结果状态（四态，P8B 的 `analyzeOne` 与 P8C 的
/// 报告共用；`failed` 只记事实，错误详情见 P8B `WorkResult` 的 detail 字段）。
pub const AnalysisOutcome = enum {
    /// 本轮实际执行了分析并完成。
    analyzed,
    /// 命中 Phase 7 的增量缓存，本轮跳过。
    skipped_cached,
    /// 本轮之前已是 `analyzed` 态，无需再做。
    already_analyzed,
    /// 本模块分析出错（详情见 `WorkResult`）。
    failed,
};

/// 调度的一层：同一深度、可并行分析的模块集合。
///
/// `depth` 为依赖深度（0 = 不依赖任何模块；其余见 `scheduler.computeLayers`）；
/// `modules` 按 `(package, path)` 字典序排过（先 package 后 path，与 Phase 4
/// `fromLoader`、Phase 7 `planIncremental` 同款口径）。
pub const Layer = struct {
    depth: usize,
    modules: []ModuleId,
};

/// 一次分层调度的完整结果：按依赖深度排好的层列表。
///
/// `layers` 按 `depth` 升序排列（`layers[i].depth == i`）；`total_modules` 为
/// 图中节点总数（与各层 `modules` 长度之和相等）；`max_width` 为最宽一层的
/// 模块数（空图时为 0）。`allocator` 为调用方传入的分配器，`deinit` 用它释放。
pub const Schedule = struct {
    layers: []Layer,
    total_modules: usize,
    max_width: usize,
    allocator: std.mem.Allocator,

    /// 只释放容器（`layers` 数组与各层 `modules` 切片），不释放任何借用串；
    /// 长度为 0 的切片不释放；调用后实例不可再用。
    pub fn deinit(self: *Schedule) void {
        for (self.layers) |layer| {
            if (layer.modules.len > 0) self.allocator.free(layer.modules);
        }
        if (self.layers.len > 0) self.allocator.free(self.layers);
        self.* = undefined;
    }
};

/// 并行分析的运行配置（P8C 驱动消费；调度分层本身不消费它，见
/// `scheduler.computeLayers` 的文档注释）。
pub const ParallelConfig = struct {
    /// 最大工作线程数；null 表示不限（调用方决定线程数）。
    max_workers: ?usize = null,
    /// 为 true 时层内顺序固定为 `(package, path)` 字典序（确定性输出）。
    deterministic: bool = true,
};
