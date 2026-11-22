//! 单模块工作单元 —— SA 标准库模块化 Phase 8（并行模块分析，P8B）。
//!
//! 职责：一个模块的一次分析（`analyzeOne`），外加工作单元的形状
//! （`WorkItem` / `WorkResult`）。不多做一步：
//!   - 不负责层调度（哪一层先跑、层内顺序由谁定，是 P8C 驱动的事）；
//!   - 不负责缓存判断（该模块该不该分析，由 `cache_filter.zig` 的
//!     `splitLayer` 按 Phase 7 的 `ReusePlan` 先切分，见 P8C 驱动）；
//!   - 不开线程：并行只发生在“同一层的多个 `WorkItem` 可交由不同执行
//!     单元跑”这一层，执行单元（线程 / 任务）的创建与回收是 P8C
//!     驱动的事，本文件对此一无所知。
//!
//! 背景：提案 STD-MODULARIZATION-PROPOSAL.md §5 第 8 阶段（并行模块
//! 分析，P2）与 §2 四态（unloaded → loading → loaded → analyzed）。
//! 本文件只推进四态的最后一步（loaded → analyzed），前三步仍是
//! Phase 3 `LazyLoader`（`loadRoot` / `drainWorklist`）的事。
//!
//! `analyzeOne` 的三步（合并定稿 M1，见“已知缺口”N1）：
//!   1. 读 `loader.stateOf(id)`：已是 `.analyzed` → 返回
//!      `{ .already_analyzed, "already analyzed" }`，不调钩子、不改
//!      状态；`.unloaded` → 返回 `{ .failed, "module not loaded" }`；
//!      `.loading` → 返回 `{ .failed, "module still loading" }`。
//!   2. 只有 `.loaded` 才继续：调 `try loader.markAnalyzed(id)`，
//!      由它置 analyzed 态并依次驱动 `type_check_hook` 与
//!      `analyze_hook`（单次调用；钩子失败不回滚，见 Phase 3 的
//!      `markAnalyzed` 文档）。本函数不直接调钩子。
//!   3. 成功返回 `{ .analyzed, "" }`。
//!
//! 错误分界（调用方凭错误集区分）：
//!   - 状态不对（已分析 / 未加载 / 正在加载）不是错误，直传
//!     `WorkResult`（outcome 为 `.already_analyzed` / `.failed`），
//!     调用方据 outcome 分流，不用 `catch`；
//!   - 钩子或 `markAnalyzed` 出错时错误直传（不包成
//!     `WorkResult.failed`），错误集为 `LoaderError`。
//!
//! 所有权：`WorkResult.detail` 只借用（静态串或调用方 arena 的串），
//! 不拥有、不释放。`WorkItem` / `WorkResult` 只含值拷贝的 `ModuleId`
//!（`package` / `path` 串仍借用调用方 arena），本文件不分配、不释放
//! 任何东西。
//!
//! 类型正本与合并对齐（P8A 的 `types.zig` 是正本，本文件只 import、
//! 不重定义；写时 `types.zig` 尚未落盘，合并时由协调 agent 按落盘核对）：
//!   - A1：`AnalysisOutcome`（`analyzed` / `skipped_cached` /
//!     `already_analyzed` / `failed`）——复用 P8A 的 `types.zig`；
//!   - A2：`ModuleId` / `ModuleState` / `LoaderError` / `LazyLoader`——
//!     复用 `src/module_loader/loader.zig`（其 `ModuleId` /
//!     `ModuleState` 与 `src/dependency_graph/types.zig` 的同名
//!     re-export 是同一声明，均源自 `src/module_resolver/types.zig`，
//!     类型身份一致）；
//!   - A3：`ParallelError`（`GraphError || Allocator.Error`）是 P8C
//!     驱动的错误集，本文件不用（`analyzeOne` 只报 `LoaderError`，
//!     `splitLayer` 只报 `Allocator.Error`），故不在此重定义、不
//!     re-export。
//!
//! 已知缺口（只记，不擅自改结构）：
//!   - N1（已裁决，合并 M1）：`markAnalyzed` 内部先置 analyzed 态再
//!     依次调 `type_check_hook` 与 `analyze_hook`，故 `analyzeOne`
//!     不直接调钩子，只调 `markAnalyzed`（钩子单次调用；与 loader 自
//!     身的 `analyzeAll` 同款模式）。若按任务书字面顺序“先调
//!     `analyze_hook`、再调 `markAnalyzed`”，非 noop 钩子会被调两次，
//!     故合并时改了第 ② 步。钩子失败不回滚是 Phase 3 已文档化的语义。
//!   - N2：`stateOf` 对未登记的模块返回 `null`。本函数按 `.unloaded`
//!     同款处理（返回 `{ .failed, "module not loaded" }`），不把它
//!     升级成直传错误（`markAnalyzed` 对未登记模块本就会报
//!     `ModuleNotFound`，但走到那一步之前状态检查已先拦截）。是否
//!     改为独立的 outcome / detail（如 "module not registered"），
//!     待协调 agent 确认。
//!   - N3：`types.zig` 的 import 在合并前悬空（P8A 并行在写，见上文
//!     A1；与 Phase 7 合并前 `types.zig` / `store.zig` 两处 import
//!     悬空同款，是并行编写期的预期跨 agent 依赖，不是新增的意外悬空）。
//!   - N4：本文件未经编译验证（只跑 `zig ast-check`，见任务书硬约束）；
//!     跨文件调用形状（`stateOf` / `analyze_hook` 字段 /
//!     `markAnalyzed` 的签名）靠读 `loader.zig` 落盘代码核对，未经编译。
//!
//! 不属于本文件：build.zig 注册（后续 Phase / 协调方接线）；facade
//! （由协调 agent 合并时写）；真正的 parse / type-check / analyze
//! 实现（钩子槽位仍是 Phase 3 遗留的空实现）。

const loader_mod = @import("../module_loader/loader.zig");
const types_mod = @import("types.zig");

// 复用，不重定义（正本见文件头“类型正本与合并对齐”）。
pub const LazyLoader = loader_mod.LazyLoader;
pub const LoaderError = loader_mod.LoaderError;
pub const ModuleId = loader_mod.ModuleId;
pub const ModuleState = loader_mod.ModuleState;
pub const AnalysisOutcome = types_mod.AnalysisOutcome;

/// 一个模块的一次分析工作：属于第 `layer` 层的 `module`。
/// `layer` 只作记录（供驱动按层调度与排错）；本文件不解释层号的含义，
/// 不验证层内依赖已就绪——层划分是 P8A 的事。
pub const WorkItem = struct {
    module: ModuleId,
    layer: usize,
};

/// 一次 `analyzeOne` 的结果。
///
/// `detail` 只借用（静态串或调用方 arena 的串），不拥有、不释放：
/// 本函数只填四个静态串（见 `analyzeOne`），调用方如需久存请自行复制。
pub const WorkResult = struct {
    module: ModuleId,
    outcome: AnalysisOutcome,
    detail: []const u8,
};

/// 单模块分析步骤：一个模块的一次分析（三步见文件头）。
///
/// 状态检查在先：只有 `.loaded` 态才调 `markAnalyzed`（置态并驱动钩子）；
/// 其余三态直接返回 `WorkResult`（不调钩子、不改状态、不报错误）。
/// `markAnalyzed`（含其驱动的钩子）出错时错误直传（`LoaderError`），
/// 不包成 `WorkResult.failed`。
pub fn analyzeOne(loader: *LazyLoader, id: ModuleId) LoaderError!WorkResult {
    // ① 状态检查。未登记的模块 `stateOf` 返回 null，按 `.unloaded`
    // 同款处理（见文件头已知缺口 N2）。
    switch (loader.stateOf(id) orelse .unloaded) {
        .analyzed => return .{
            .module = id,
            .outcome = .already_analyzed,
            .detail = "already analyzed",
        },
        .unloaded => return .{
            .module = id,
            .outcome = .failed,
            .detail = "module not loaded",
        },
        .loading => return .{
            .module = id,
            .outcome = .failed,
            .detail = "module still loading",
        },
        .loaded => {},
    }
    // ② 写回状态机：调 `markAnalyzed` 置 analyzed 态并驱动钩子
    // （单次调用；见文件头已知缺口 N1 合并裁决）。
    try loader.markAnalyzed(id);
    // ③ 成功。
    return .{
        .module = id,
        .outcome = .analyzed,
        .detail = "",
    };
}
