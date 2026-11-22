//! 并行模块分析 —— SA 标准库模块化 Phase 8（sa-parallel-analysis，P2）。
//!
//! 薄 re-export，不含逻辑。协调 agent 合并时写（见 MANIFEST §5 M1）。
//!
//! 职责：提案 §5 第 8 阶段——以 Phase 4 的模块依赖图（`topoSort`）为调度
//! 依据分层（同层可并行、层间串行），与 Phase 3 的 `LazyLoader` 状态机
//! （`unloaded` / `loading` / `loaded` / `analyzed`）与 Phase 7 的增量
//! 缓存（`ReusePlan`）对齐：已缓存的模块跳过分析、只分析失效模块，分析
//! 结果写回状态机（`analyzed` 态）。执行模型是进程内串行回退（见
//! `driver.zig` 文件头）；线程执行器是后续接线阶段的事。

const types_mod = @import("parallel_analysis/types.zig");
const scheduler_mod = @import("parallel_analysis/scheduler.zig");
const worker_mod = @import("parallel_analysis/worker.zig");
const cache_filter_mod = @import("parallel_analysis/cache_filter.zig");
const driver_mod = @import("parallel_analysis/driver.zig");
const loader_mod = @import("module_loader/loader.zig");
const module_graph_mod = @import("dependency_graph/module_graph.zig");
const incremental_driver_mod = @import("incremental_cache/driver.zig");

// types.zig（P8A）：共享类型正本。
pub const ParallelError = types_mod.ParallelError;
pub const AnalysisOutcome = types_mod.AnalysisOutcome;
pub const Layer = types_mod.Layer;
pub const Schedule = types_mod.Schedule;
pub const ParallelConfig = types_mod.ParallelConfig;
pub const ModuleId = types_mod.ModuleId;
pub const ModuleState = types_mod.ModuleState;
pub const GraphError = types_mod.GraphError;

// scheduler.zig（P8A）：分层。
pub const computeLayers = scheduler_mod.computeLayers;

// worker.zig（P8B）：单模块工作单元。
pub const WorkItem = worker_mod.WorkItem;
pub const WorkResult = worker_mod.WorkResult;
pub const analyzeOne = worker_mod.analyzeOne;

// cache_filter.zig（P8B）：层内复用切分。
pub const LayerSplit = cache_filter_mod.LayerSplit;
pub const splitLayer = cache_filter_mod.splitLayer;
pub const isReuse = cache_filter_mod.isReuse;
pub const isRebuild = cache_filter_mod.isRebuild;

// driver.zig（P8C）：分层驱动与报告。
pub const LayerReport = driver_mod.LayerReport;
pub const RunReport = driver_mod.RunReport;
pub const DriverError = driver_mod.DriverError;
pub const runSchedule = driver_mod.runSchedule;
pub const analyzeAllParallel = driver_mod.analyzeAllParallel;

// 复用 Phase 3 / Phase 4 / Phase 7 的类型。
pub const LazyLoader = loader_mod.LazyLoader;
pub const ModuleGraph = module_graph_mod.ModuleGraph;
pub const ReusePlan = incremental_driver_mod.ReusePlan;
