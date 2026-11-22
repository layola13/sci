//! 并行分层驱动 —— SA 标准库模块化 Phase 8（sa-parallel-analysis，P8C）。
//!
//! 职责（只做分层调度与结果汇总，不并行、不编译、不缓存）：
//!   - 提供 Phase 8 的集成入口（`runSchedule` / `analyzeAllParallel`）：
//!     按固定五步接线 P8A 的分层（`computeLayers`）→ P8B 的层内切分
//!     （`splitLayer`）→ P8B 的单模块分析（`analyzeOne`）→ 状态核对
//!     （`loader.stateOf`）→ 返回 `RunReport`；
//!   - 定义运行报告的类型（`LayerReport` / `RunReport`，含 `deinit`
//!     与 `summarize`）；
//!   - 提供人类可读的文本摘要（`RunReport.summarize`）。
//!
//! 执行模型（本文件头必须写明，见任务书）：
//!   - 本驱动在进程内**串行**执行各层：层间按层号从小到大依次走，
//!     层内按 modules 顺序逐个调 `analyzeOne`。这是可验证的回退行为，
//!     不是并行执行；
//!   - 层本身就是并行结构：同层模块之间无依赖关系（分层保证：一条边
//!     `from -> to` 的两端必在不同层，`to` 的层号更小），可交由不同
//!     执行单元并发跑；
//!   - 将来线程池执行器替换第 ③ 步的串行循环即可，无需改计划结构：
//!     计划（`Schedule`）与切分（`LayerSplit`）的形状不变，执行器只
//!     换“怎么跑完一层 to_analyze”的实现；
//!   - 线程本身的创建 / 同步是后续接线阶段的事，与 build.zig 注册同款
//!     “未接线”状态（见“已知缺口”第 1、2 项）。
//!
//! `runSchedule` 的五步（缺一不可，顺序固定；见 `runSchedule` 的文档注释）：
//!   1. 按层号从小到大走 `schedule.layers`（层间串行：后一层开始前，
//!      前一层全部完成——依赖保证）；
//!   2. 每层先调 `splitLayer` 切分：`plan.reuse` 里的记 skipped（不调
//!      `analyzeOne`）；其余进 to_analyze；
//!   3. 层内按 modules 顺序（已按 `(package, path)` 排过）逐个调
//!      `analyzeOne`，串行执行；outcome 分别计入 analyzed /
//!      already_analyzed / failed；`analyzeOne` 返回 `.failed`
//!      （`WorkResult`，非错误）时记 failed 继续下一模块，不中断整层；
//!      `analyzeOne` 抛错误（`LoaderError`）时整轮返回错误（调用方凭
//!      错误集区分可恢复失败与硬错误）；
//!   4. 每模块 `analyzeOne` 返回 `.analyzed` 后核对
//!      `loader.stateOf(id) == .analyzed`，不对则该模块改记 failed
//!      （detail 记 `"state not analyzed after analyzeOne"`）；
//!   5. 返回 `RunReport`。
//!
//! 错误语义：
//!   - `DriverError = ParallelError || LoaderError`（见下文类型正本）。
//!     分层 / 切分失败（`ParallelError`：图错误或分配失败）与单模块
//!     分析抛错（`LoaderError`）都以错误返回整轮，不产出半成品
//!     `RunReport`；已攒的层报告由 errdefer 释放；
//!   - `.failed` 的 `WorkResult` 不是错误：只计 failed，不中断、不返回
//!     错误（见第 ③ 步）；
//!   - 调用方凭错误集区分：`error.OutOfMemory` / 图错误
//!     （`CycleDetected` 等）是硬错误；`LoaderError` 的其余变体（如
//!     `InvalidStateTransition` / `ReadFailed`）是单模块可恢复失败的
//!     信号——但本驱动不重试、不跳过：抛错即整轮返回，重试策略是调用方
//!     的事。
//!
//! 所有权 / arena 规则（与 Phase 2 的 A8、Phase 3 的 loader、Phase 4
//! 的图、Phase 5 的报告、Phase 6 的 DCE、Phase 7 的计划一致）：
//!   - 调用方传入一个 arena 分配器；`RunReport` 用它分配唯一的 owned
//!     切片（`layers`）；`RunReport` 存一份该分配器（`allocator` 字段，
//!     与 `ReusePlan` / `ReachabilityReport` 同款），`deinit` 用它释放；
//!   - `RunReport.deinit` 只释放 `layers` 切片；调用方只调一次
//!     `RunReport.deinit`，不得再单独释放其中任一切片（避免重复释放）；
//!   - 长度为 0 的切片不释放（它可能是一段编译期空切片，而非分配器
//!     产物；与 P5B `Convergence.deinit` / P6C `DceResult` / P7C
//!     `ReusePlan.deinit` 同款口径）；
//!   - `LayerReport` 是值类型，不拥有任何切片；`ModuleId` 为值拷贝
//!     （`package` / `path` 字符串仍借用调用方 arena），`deinit` 不
//!     释放任何借用串；
//!   - `LayerSplit`（P8B）的 owned 切片（`skipped` / `to_analyze`）由本
//!     驱动在每层结束时 `deinit` 释放，不带出本轮；
//!   - `Schedule` 由调用方拥有：`runSchedule` 只借用（`*const`），不
//!     释放；`analyzeAllParallel` 内部建的 `Schedule` 用完即 `deinit`
//!     （见该函数）；
//!   - `summarize` 的所有权见下节；`plan` / `graph` 只借用，不拥有、
//!     不修改。
//!
//! `RunReport.summarize` 的所有权（任务书指定，本文件按 Phase 5
//! `summarize` / Phase 6 `summarizeDce` / Phase 7 `summarizePlan`
//! 同款口径）：
//!   - 返回指向文件级静态缓冲区（`summary_buf`，512 字节）的借用切片；
//!   - 调用方如需久存请自行复制；连续两次调用后一次覆盖前一次；
//!   - 非线程安全；摘要只有总数与每层 4 个数字，最长约 140 字节加每层
//!     约 20 字节，层数极多时 512 字节可能溢出，溢出时退化为已写出的
//!     前缀（总数行完整，层明细截断；不断言、不报错）。
//!
//! 类型正本与合并对齐（P8A / P8B 尚未落盘，本文件按任务书给定的名字
//! import；调用形状的假设集中于此，合并时由协调 agent 按 P8A / P8B
//! 落盘逐项核对，见 MANIFEST §5 对齐点 A1–A8）：
//!   - A1：`types.zig`（P8A 正本）——`AnalysisOutcome`（`analyzed` /
//!     `skipped_cached` / `already_analyzed` / `failed`）、
//!     `ParallelError`（`GraphError || std.mem.Allocator.Error`）、
//!     `Schedule`（`layers` / `total_modules` / `max_width` /
//!     `deinit`）、`Layer`（`depth` / `modules`）、`ParallelConfig`
//!     （执行器配置，本驱动不消费——串行回退不取任何配置，见“执行
//!     模型”；配置留给后续线程池执行器）；
//!   - A2：`scheduler.zig`（P8A 正本）——`computeLayers(graph,
//!     allocator) ParallelError!Schedule`；`graph` 取 `*ModuleGraph`
//!     （可写：内部分层调 `topoSort()`，该方法会写 `lastCycles`）；
//!     返回的 `layers` 按 `depth` 升序，本驱动信任该顺序、不重排；
//!   - A3：`worker.zig`（P8B 正本）——`WorkItem` / `WorkResult` /
//!     `analyzeOne(loader, id) LoaderError!WorkResult`；`WorkResult`
//!     含 `module: ModuleId`、`outcome: AnalysisOutcome` 与可写
//!     `detail: []const u8`；`loader` 取 `*LazyLoader`（分析会推进
//!     loader 状态机）；（合并 M2：字段名以 P8B 落盘为准，`module`
//!     非 `id`；`detail` 存在，第 ④ 步的改写保留。）
//!   - A4：`cache_filter.zig`（P8B 正本）——`LayerSplit`（`skipped` /
//!     `to_analyze` 两个 owned `[]ModuleId` 切片 + `allocator` +
//!     `deinit`）、`splitLayer(modules, plan, allocator)
//!     std.mem.Allocator.Error!LayerSplit`（`modules` 为本层模块切片，
//!     `plan` 为整轮 `ReusePlan`；`skipped` = 本层中在 `plan.reuse`
//!     里的模块，`to_analyze` = 其余）、`isReuse(plan, id) bool` /
//!     `isRebuild(plan, id) bool`（切分谓词，本驱动不直接调——
//!     `splitLayer` 已封装；仅 re-export 供 facade / 调用方用）；
//!     （合并 M2：P8C 起草时误写 `reuse` 字段与 `ParallelError` 错误
//!     集，已按 P8B 落盘改回 `skipped` 与 `Allocator.Error`；参数顺序
//!     以落盘 `(plan, id)` 为准。）
//!   - A5：`ReusePlan` 的正本在 Phase 7 的 `driver.zig`
//!     （`src/incremental_cache/driver.zig`）：`reuse` / `rebuild` /
//!     `invalidated` 三个 `[]ModuleId` 切片，均按 `(package, path)`
//!     字典序；本文件只 import、不重定义；
//!   - A6：`DriverError = ParallelError || LoaderError`；`LoaderError`
//!     复用 `src/module_loader/loader.zig` 的正本；`ModuleId` /
//!     `ModuleState` / `LazyLoader` 复用 loader.zig 的正本，
//!     `ModuleGraph` / `GraphError` 复用 dependency_graph 的正本；
//!   - A7：第 ④ 步的状态核对失败时，本驱动改写本地 `WorkResult` 副本
//!     的 `outcome` 为 `.failed` 并把 `detail` 置为
//!     `"state not analyzed after analyzeOne"`（`RunReport` 只记数，
//!     不存逐模块 detail；改写后的副本只用于本层计数，不带出本轮）。
//!     若 P8B 落盘的 `WorkResult` 无 `detail` 字段，合并时删这一行
//!     赋值、只计 failed；
//!   - A8：`Schedule.deinit` 与 `LayerSplit.deinit` 存在（与 Phase 7
//!     `ReusePlan.deinit` 同款口径：释放 owned 切片，长度为 0 的不
//!     释放）；若落盘形状不同，合并时改本文件的两处 `deinit` 调用点。
//!
//! 已知缺口：
//!   - 上述 A1–A8 未经编译验证（只跑 ast-check；P8A / P8B 尚未落盘，
//!     `types.zig` / `scheduler.zig` / `worker.zig` /
//!     `cache_filter.zig` 四处 import 在合并前悬空，见 MANIFEST §8）；
//!   - 线程执行器未实现：本驱动是串行回退（见“执行模型”）；
//!   - `summarize` 只产纯文本，无结构化（JSON）输出（与 Phase 5
//!     `summarize` / Phase 6 `summarizeDce` / Phase 7 `summarizePlan`
//!     同款口径；JSON 输出本身是 Phase 5 §6 第 5 项待裁决）；不逐个
//!     列出分析 / 跳过 / 失败模块（模块可能成百上千，逐个列出无意义；
//!     要看明细读 `schedule` 各层与 `plan` 的三个切片）；
//!   - facade（`src/parallel_analysis.zig`）由协调合并时写，本任务不写；
//!   - build.zig 注册（后续 Phase / 协调方接线），本任务不做。
//!
//! 不属于本文件：build.zig 注册（后续 Phase / 协调方接线）；P8A 的
//! 类型与分层实现；P8B 的切分与单模块分析实现；Phase 7 的计划计算。

const std = @import("std");
const types_mod = @import("types.zig");
const scheduler_mod = @import("scheduler.zig");
const worker_mod = @import("worker.zig");
const cache_filter_mod = @import("cache_filter.zig");
const loader_mod = @import("../module_loader/loader.zig");
const module_graph_mod = @import("../dependency_graph/module_graph.zig");
const incremental_driver_mod = @import("../incremental_cache/driver.zig");

// 复用，不重定义（正本见文件头“类型正本与合并对齐”）。
pub const AnalysisOutcome = types_mod.AnalysisOutcome;
pub const ParallelError = types_mod.ParallelError;
pub const Schedule = types_mod.Schedule;
pub const Layer = types_mod.Layer;
pub const ParallelConfig = types_mod.ParallelConfig;
pub const computeLayers = scheduler_mod.computeLayers;
pub const WorkItem = worker_mod.WorkItem;
pub const WorkResult = worker_mod.WorkResult;
pub const analyzeOne = worker_mod.analyzeOne;
pub const LayerSplit = cache_filter_mod.LayerSplit;
pub const splitLayer = cache_filter_mod.splitLayer;
pub const isReuse = cache_filter_mod.isReuse;
pub const isRebuild = cache_filter_mod.isRebuild;
pub const ModuleId = loader_mod.ModuleId;
pub const ModuleState = loader_mod.ModuleState;
pub const LazyLoader = loader_mod.LazyLoader;
pub const LoaderError = loader_mod.LoaderError;
pub const ModuleGraph = module_graph_mod.ModuleGraph;
pub const GraphError = module_graph_mod.GraphError;
pub const ReusePlan = incremental_driver_mod.ReusePlan;

/// 驱动错误集：分层 / 切分失败（`ParallelError`：图错误或分配失败）或
/// 单模块分析抛错（`LoaderError`）都以错误返回整轮（见文件头“错误语义”）。
/// `.failed` 的 `WorkResult` 不是错误，不进此集。
pub const DriverError = ParallelError || LoaderError;

/// `summarize` 的静态缓冲区（见文件头“所有权”一节）。
var summary_buf: [512]u8 = undefined;

/// 一层的运行报告：值类型，不拥有任何切片。
pub const LayerReport = struct {
    /// 本层层号（与 `Schedule` 里对应 `Layer.depth` 一致）。
    depth: usize,
    /// 本层 `analyzeOne` 返回 `.analyzed` 且状态核对通过的模块数。
    analyzed: usize = 0,
    /// 本层在 `plan.reuse` 里而跳过 `analyzeOne` 的模块数，加上
    /// `analyzeOne` 自身返回 `.skipped_cached` 的模块数。
    skipped: usize = 0,
    /// 本层 `analyzeOne` 返回 `.already_analyzed` 的模块数。
    already: usize = 0,
    /// 本层失败的模块数：`analyzeOne` 返回 `.failed`，或返回
    /// `.analyzed` 但状态核对未通过（见 `runSchedule` 第 ④ 步）。
    failed: usize = 0,
};

/// 一轮并行分析的运行报告：全部产出。
///
/// `layers` 按 `depth` 升序，与 `Schedule.layers` 一一对应；四个总数
/// 是各层计数的和（`total_skipped` 含每层 `plan.reuse` 的跳过数）。
/// `allocator` 为调用方传入的 arena 分配器，`deinit` 用它释放 `layers`。
pub const RunReport = struct {
    /// 各层报告（owned，按 `depth` 升序；长度为 0 时不释放，见 `deinit`）。
    layers: []LayerReport = &.{},
    /// 全轮 `analyzeOne` 返回 `.analyzed` 且状态核对通过的模块数。
    total_analyzed: usize = 0,
    /// 全轮缓存跳过的模块数（`plan.reuse` 的跳过 + `.skipped_cached`）。
    total_skipped: usize = 0,
    /// 全轮 `analyzeOne` 返回 `.already_analyzed` 的模块数。
    total_already: usize = 0,
    /// 全轮失败的模块数（见 `LayerReport.failed`）。
    total_failed: usize = 0,
    /// 调用方传入的分配器（`deinit` 用它释放 `layers`）。
    allocator: std.mem.Allocator,

    /// 释放 `layers` 切片；调用后实例不可再用。
    /// 长度为 0 的切片不释放（见文件头所有权规则）。
    pub fn deinit(self: *RunReport) void {
        if (self.layers.len > 0) self.allocator.free(self.layers);
        self.* = undefined;
    }

    /// 人类可读的文本摘要：一行——各层 / 总数：分析数、缓存跳过数、
    /// 已分析数、失败数。
    ///
    /// 只产纯文本，无结构化（JSON）输出（见文件头“已知缺口”）。
    /// 返回静态缓冲区的借用切片（见文件头“所有权”一节）：调用方如需
    /// 久存请自行复制；连续两次调用后一次覆盖前一次；非线程安全。
    /// 格式：`并行分析：共 N 层 / 分析 A / 缓存跳过 S / 已分析 Y /
    /// 失败 F`，其后每层一段 `; L{depth}: a/s/y/f`（依次为分析 /
    /// 跳过 / 已分析 / 失败）；层数极多致 512 字节溢出时返回已写出的
    /// 前缀（总数行完整，层明细截断）；无层时后缀
    /// `（无待分析模块）`。不逐个列出模块（要看明细读 `schedule`
    /// 各层与 `plan` 的三个切片）。
    pub fn summarize(self: *const RunReport) []const u8 {
        var used: usize = 0;
        const head = std.fmt.bufPrint(
            summary_buf[used..],
            "并行分析：共 {d} 层 / 分析 {d} / 缓存跳过 {d} / 已分析 {d} / 失败 {d}",
            .{
                self.layers.len,
                self.total_analyzed,
                self.total_skipped,
                self.total_already,
                self.total_failed,
            },
        ) catch return "并行分析：摘要过长";
        used += head.len;

        if (self.layers.len == 0) {
            const tail = std.fmt.bufPrint(
                summary_buf[used..],
                "（无待分析模块）",
                .{},
            ) catch return summary_buf[0..used];
            used += tail.len;
            return summary_buf[0..used];
        }

        for (self.layers) |layer| {
            const seg = std.fmt.bufPrint(
                summary_buf[used..],
                "; L{d}: {d}/{d}/{d}/{d}",
                .{
                    layer.depth,
                    layer.analyzed,
                    layer.skipped,
                    layer.already,
                    layer.failed,
                },
            ) catch return summary_buf[0..used];
            used += seg.len;
        }
        return summary_buf[0..used];
    }
};

/// Phase 8 的分层驱动：按给定 `Schedule` 与 `ReusePlan` 跑一轮分析。
///
/// 只做调度与汇总，不并行、不编译模块本身（单模块分析是 P8B 的
/// `analyzeOne` 的事）、不改 `graph` / `plan`（两者均为只读输入；
/// `loader` 的状态机只由 `analyzeOne` 内部推进，本函数不直接改状态）。
///
/// 五步固定顺序（缺一不可）：
///   1. 按层号从小到大走 `schedule.layers`（层间串行：后一层开始前，
///      前一层全部完成——依赖保证）。本函数信任 `computeLayers` 返回
///      的 `layers` 已按 `depth` 升序，不重排（见文件头对齐点 A2）；
///   2. 每层先调 `splitLayer(layer.modules, plan, allocator)` 切分：
///      `plan.reuse` 里的记 skipped（不调 `analyzeOne`）；其余进
///      to_analyze；
///   3. 层内按 modules 顺序（已按 `(package, path)` 排过）逐个调
///      `analyzeOne(loader, id)`，串行执行；outcome 分别计入
///      analyzed / already_analyzed / failed（`analyzeOne` 自身返回
///      `.skipped_cached` 时也记 skipped）；`analyzeOne` 返回
///      `.failed`（`WorkResult`，非错误）时记 failed 继续下一模块，
///      不中断整层；`analyzeOne` 抛错误（`LoaderError`）时整轮返回
///      错误（调用方凭错误集区分可恢复失败与硬错误；已攒的层报告由
///      errdefer 释放，不产出半成品 `RunReport`）；
///   4. 每模块 `analyzeOne` 返回 `.analyzed` 后核对
///      `loader.stateOf(id) == .analyzed`，不对则该模块改记 failed
///      （detail 记 `"state not analyzed after analyzeOne"`，见文件头
///      对齐点 A7）；
///   5. 返回 `RunReport`（拥有 `layers` 切片与四个总数）。
///
/// 失败语义：只报 `DriverError`（分层 / 切分失败或单模块分析抛错）；
/// 中间步骤报失败时，已得的中间产物由 errdefer 清理。
pub fn runSchedule(
    loader: *LazyLoader,
    schedule: *const Schedule,
    plan: *const ReusePlan,
    allocator: std.mem.Allocator,
) DriverError!RunReport {
    var layer_reports = std.array_list.Managed(LayerReport).init(allocator);
    errdefer layer_reports.deinit();

    var total_analyzed: usize = 0;
    var total_skipped: usize = 0;
    var total_already: usize = 0;
    var total_failed: usize = 0;

    // 1. 层间串行：按层号从小到大走 schedule.layers（computeLayers 已
    // 按 depth 升序，见文件头对齐点 A2）；后一层开始前，前一层全部完成。
    for (schedule.layers) |layer| {
        var report = LayerReport{ .depth = layer.depth };

        // 2. 层内切分：plan.reuse 里的记 skipped（不调 analyzeOne）；
        // 其余进 to_analyze。LayerSplit 的 owned 切片由本层结束时释放。
        var split = try splitLayer(layer.modules, plan, allocator);
        defer split.deinit();
        report.skipped += split.skipped.len;

        // 3. 层内串行：按 modules 顺序（已按 (package, path) 排过）逐个
        // 调 analyzeOne。将来线程池执行器替换的正是这个循环（见文件头
        // “执行模型”）；计划结构（Schedule / LayerSplit）无需改。
        for (split.to_analyze) |id| {
            var result = try analyzeOne(loader, id);
            switch (result.outcome) {
                .analyzed => {
                    // 4. 状态核对：analyzeOne 报 .analyzed 后，loader 里
                    // 该模块必须已是 .analyzed 态；不对则改记 failed。
                    if (loader.stateOf(id) != .analyzed) {
                        result.outcome = .failed;
                        result.detail = "state not analyzed after analyzeOne";
                        report.failed += 1;
                    } else {
                        report.analyzed += 1;
                    }
                },
                .skipped_cached => report.skipped += 1,
                .already_analyzed => report.already += 1,
                .failed => report.failed += 1,
            }
        }

        total_analyzed += report.analyzed;
        total_skipped += report.skipped;
        total_already += report.already;
        total_failed += report.failed;
        try layer_reports.append(report);
    }

    // 5. 返回 RunReport（layers 切片所有权转移给报告）。
    return .{
        .layers = try layer_reports.toOwnedSlice(),
        .total_analyzed = total_analyzed,
        .total_skipped = total_skipped,
        .total_already = total_already,
        .total_failed = total_failed,
        .allocator = allocator,
    };
}

/// 便捷入口：分层 + 分层驱动一站式。
///
/// `computeLayers(graph, allocator)` 得 `Schedule`，再调 `runSchedule`；
/// `Schedule` 用完即 `deinit`（本函数内建，调用方不另行释放）。
/// `graph` 取 `*ModuleGraph`（内部分层调 `topoSort()`，见文件头对齐点 A2）。
pub fn analyzeAllParallel(
    loader: *LazyLoader,
    graph: *ModuleGraph,
    plan: *const ReusePlan,
    allocator: std.mem.Allocator,
) DriverError!RunReport {
    var schedule = try computeLayers(graph, allocator);
    defer schedule.deinit();
    return runSchedule(loader, &schedule, plan, allocator);
}
