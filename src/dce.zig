//! sa-dce facade —— SA 标准库模块化 Phase 6（P1）。
//!
//! 薄 re-export，不含逻辑。死代码消除（提案 §2 第 3 点、§3）：在
//! Phase 5 可达性分析的报告基础上做实际裁剪删除——不可达的函数 /
//! 全局不进产物。只做整理/实现，不跑构建/测试、不修 bug。

const pruner_mod = @import("dce/pruner.zig");
const guard_mod = @import("dce/guard.zig");
const eliminate_mod = @import("dce/eliminate.zig");
const symbol_graph_mod = @import("dependency_graph/symbol_graph.zig");
const module_graph_mod = @import("dependency_graph/module_graph.zig");
const retention_mod = @import("dependency_graph/retention.zig");
const report_mod = @import("reachability/report.zig");
const converge_mod = @import("reachability/converge.zig");

// pruner.zig：裁剪器（P6A）
pub const RemovedSymbol = pruner_mod.RemovedSymbol;
pub const PrunedGraph = pruner_mod.PrunedGraph;
pub const prune = pruner_mod.prune;

// guard.zig：安全校验（P6B）
pub const DceViolationKind = guard_mod.DceViolationKind;
pub const DceViolation = guard_mod.DceViolation;
pub const DceStats = guard_mod.DceStats;
pub const verifyPruned = guard_mod.verifyPruned;
pub const countStats = guard_mod.countStats;

// eliminate.zig：集成入口与报告（P6C）
pub const DceOutcome = eliminate_mod.DceOutcome;
pub const DceResult = eliminate_mod.DceResult;
pub const eliminate = eliminate_mod.eliminate;
pub const summarizeDce = eliminate_mod.summarizeDce;

// 复用（Phase 4 / Phase 5 类型，不重定义；与 Phase 5 facade 同款做法）
pub const ModuleId = symbol_graph_mod.ModuleId;
pub const SymbolNode = symbol_graph_mod.SymbolNode;
pub const SymbolKind = symbol_graph_mod.SymbolKind;
pub const SymbolGraph = symbol_graph_mod.SymbolGraph;
pub const ModuleGraph = module_graph_mod.ModuleGraph;
pub const RetainRule = retention_mod.RetainRule;
pub const RetainRuleSet = retention_mod.RetainRuleSet;
pub const RetainSet = retention_mod.RetainSet;
pub const PruneReason = report_mod.PruneReason;
pub const PruneCandidate = report_mod.PruneCandidate;
pub const ReachabilityReport = report_mod.ReachabilityReport;
pub const Convergence = converge_mod.Convergence;
pub const analyzeAll = report_mod.analyzeAll;
