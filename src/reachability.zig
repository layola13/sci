//! sa-reachability facade —— SA 标准库模块化 Phase 5（P1）。
//!
//! 薄 re-export，不含逻辑。符号级可达性分析（提案 §2 第 3 点、§3）：
//! 从入口（main 恒保留、有 global_init 边的符号、保留集）出发，沿符号
//! 引用边做可达性闭包，判定哪些函数/全局进产物、哪些是可裁剪候选。
//! 只做分析（产出可达集合与裁剪候选），不做实际裁剪删除（DCE 是 Phase 6 的事）。
//! 独立于 Lexer、Referee、Backend；只做整理/实现，不跑构建/测试、不修 bug。

const analyzer_mod = @import("reachability/analyzer.zig");
const roots_mod = @import("reachability/roots.zig");
const converge_mod = @import("reachability/converge.zig");
const report_mod = @import("reachability/report.zig");
const symbol_graph_mod = @import("dependency_graph/symbol_graph.zig");
const module_graph_mod = @import("dependency_graph/module_graph.zig");
const retention_mod = @import("dependency_graph/retention.zig");

// analyzer.zig：可达性闭包（P5A）
pub const ReachReason = analyzer_mod.ReachReason;
pub const ReachabilityResult = analyzer_mod.ReachabilityResult;
pub const ReachabilityAnalyzer = analyzer_mod.ReachabilityAnalyzer;

// roots.zig：根集（P5B）
pub const RootEntry = roots_mod.RootEntry;
pub const computeRoots = roots_mod.computeRoots;

// converge.zig：模块级收敛（P5B）
pub const ConvergedStatus = converge_mod.ConvergedStatus;
pub const ConvergedDep = converge_mod.ConvergedDep;
pub const Convergence = converge_mod.Convergence;
pub const converge = converge_mod.converge;

// report.zig：报告与集成入口（P5C）
pub const PruneReason = report_mod.PruneReason;
pub const PruneCandidate = report_mod.PruneCandidate;
pub const ModuleStats = report_mod.ModuleStats;
pub const ReachStats = report_mod.ReachStats;
pub const ReachabilityReport = report_mod.ReachabilityReport;
pub const buildReport = report_mod.buildReport;
pub const summarize = report_mod.summarize;
pub const analyzeAll = report_mod.analyzeAll;

// 复用（Phase 4 类型，不重定义；与 Phase 4 facade 复用 Phase 2 类型同款做法）
pub const ModuleId = symbol_graph_mod.ModuleId;
pub const SymbolNode = symbol_graph_mod.SymbolNode;
pub const SymbolKind = symbol_graph_mod.SymbolKind;
pub const SymbolRefEdge = symbol_graph_mod.SymbolRefEdge;
pub const RefKind = symbol_graph_mod.RefKind;
pub const ModuleDep = symbol_graph_mod.ModuleDep;
pub const SymbolGraph = symbol_graph_mod.SymbolGraph;
pub const ModuleGraph = module_graph_mod.ModuleGraph;
pub const RetainRule = retention_mod.RetainRule;
pub const RetainRuleSet = retention_mod.RetainRuleSet;
pub const RetainSet = retention_mod.RetainSet;
