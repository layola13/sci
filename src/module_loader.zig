//! src/module_loader.zig — sa-lazy-loader facade（Phase 3，提案 §4）。
//!
//! 模块用途：提案 §4 的三个独立模块之二 `sa-lazy-loader`（Lazy Module Loading）
//! 的唯一对外入口。本文件是薄 re-export 层（仿 Phase 2 的 module_resolver.zig
//! 与任务 28 的 shim 模式）：不含逻辑，只把四个子文件的公开 API 聚合到一处，
//! 供编译器其余部分用一个 import 取用。
//!
//! 四个子文件分工：
//!   - module_loader/loader.zig  — 懒加载器本体：LazyLoader、模块表、状态机、
//!     loadRoot + 工作表循环、shim 跟随、SymbolEdge、三个钩子槽位。
//!   - module_loader/cycle.zig   — 循环检测与诊断：CyclePolicy、LoaderState、
//!     detectCycle、checkCycle、cyclePathString、reportCycle。
//!   - module_loader/policy.zig  — 加载策略与裁决：LoaderPolicy、
//!     Disambiguation、SpellingRule、UnknownExtensionRule、disambiguate、
//!     classifyBySpelling、三项待裁决的结论。
//!   - module_loader/wiring.zig  — flattener 接线适配：ModuleTable、ImportCheck、
//!     adoptMaps/restoreMaps，把 flattener 的 seen/active 两张 map 换成
//!     ModuleState 表（行为与旧代码一致）。
//!
//! Phase 映射：
//!   - 本文件对应提案 §2（四种模块状态与循环依赖）与 §4 的 sa-lazy-loader
//!     （Phase 3，Lazy Module Loading）。
//!   - sa-module-resolver（Phase 2）是本模块的输入：定位、import 解析、
//!     版本解析一律复用，不重定义（ModuleState 等共享类型取自
//!     module_resolver/types.zig）。
//!   - sa-dependency-graph（Phase 4）与 sa-reachability（Phase 5）是后续
//!     Phase：loader 产出的 modules/order/edges/cycles 是它们的输入，
//!     不是它们本身。
//!   - 本文件只定义加载驱动与状态机，不做解析、类型检查、语义分析（那三件
//!     以钩子槽位留出，见 loader.zig §4）；不跑构建、不跑测试、不修 bug
//!     （用户 2026-11-22 10:02 令）。
//!
//! 依赖：本模块独立于 Lexer、Referee、Backend（提案 §4）；只依赖 std、
//! 仓库既有 sio 封装与 module_resolver。详见 src/module_loader/MANIFEST.md。

const loader = @import("module_loader/loader.zig");
const cycle = @import("module_loader/cycle.zig");
const policy = @import("module_loader/policy.zig");
const wiring = @import("module_loader/wiring.zig");

// loader.zig：懒加载器本体（共享类型为 Phase 2 re-export，不重定义）。
pub const ModuleState = loader.ModuleState;
pub const ImportKind = loader.ImportKind;
pub const ResolveError = loader.ResolveError;
pub const ImportSpec = loader.ImportSpec;
pub const ModuleId = loader.ModuleId;
pub const ModuleInfo = loader.ModuleInfo;
pub const SymbolEdge = loader.SymbolEdge;
pub const Locator = loader.Locator;
pub const CycleRecord = loader.CycleRecord;
pub const LoaderError = loader.LoaderError;
pub const ModuleEntry = loader.ModuleEntry;
pub const ParseHook = loader.ParseHook;
pub const TypeCheckHook = loader.TypeCheckHook;
pub const AnalyzeHook = loader.AnalyzeHook;
pub const noopParseHook = loader.noopParseHook;
pub const noopTypeCheckHook = loader.noopTypeCheckHook;
pub const noopAnalyzeHook = loader.noopAnalyzeHook;
pub const LazyLoader = loader.LazyLoader;

// cycle.zig：循环检测与诊断。
pub const CyclePolicy = cycle.CyclePolicy;
pub const LoaderState = cycle.LoaderState;
pub const ErrorContext = cycle.ErrorContext;
pub const isCycleState = cycle.isCycleState;
pub const detectCycle = cycle.detectCycle;
pub const checkCycle = cycle.checkCycle;
pub const cyclePathString = cycle.cyclePathString;
pub const formatCycleRecord = cycle.formatCycleRecord;
pub const reportCycle = cycle.reportCycle;
pub const reportCycleAtLine = cycle.reportCycleAtLine;

// policy.zig：加载策略与裁决。
pub const Disambiguation = policy.Disambiguation;
pub const SpellingRule = policy.SpellingRule;
pub const UnknownExtensionRule = policy.UnknownExtensionRule;
pub const LoaderPolicy = policy.LoaderPolicy;
pub const default_policy = policy.default_policy;
pub const describePolicy = policy.describePolicy;
pub const disambiguate = policy.disambiguate;
pub const disambiguateOrError = policy.disambiguateOrError;
pub const ImportSpelling = policy.ImportSpelling;
pub const dottedSegmentKind = policy.dottedSegmentKind;
pub const classifyBySpelling = policy.classifyBySpelling;
pub const known_source_extensions = policy.known_source_extensions;
pub const isKnownSourceExtension = policy.isKnownSourceExtension;
pub const unknown_extension_rejection = policy.unknown_extension_rejection;

// wiring.zig：flattener 接线适配。
pub const ImportCheck = wiring.ImportCheck;
pub const ModuleTable = wiring.ModuleTable;
pub const AdoptedMaps = wiring.AdoptedMaps;
