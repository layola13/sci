//! sa-dependency-graph facade —— SA 标准库模块化 Phase 4（P0）。
//!
//! 薄 re-export，不含逻辑。两层依赖图（提案 §3）：Module Dependency Graph
//! （ModuleGraph）与 Symbol / Function Dependency Graph（SymbolGraph），
//! 加保留规则登记（RetainSet）与图构建器（GraphBuilder）。
//! 独立于 Lexer、Referee、Backend；只做整理/实现，不跑构建/测试、不修 bug。

const types_mod = @import("dependency_graph/types.zig");
const module_graph_mod = @import("dependency_graph/module_graph.zig");
const symbol_graph_mod = @import("dependency_graph/symbol_graph.zig");
const retention_mod = @import("dependency_graph/retention.zig");
const builder_mod = @import("dependency_graph/builder.zig");

// types.zig：共享类型（Phase 2 类型复用，不重定义）
pub const ModuleState = types_mod.ModuleState;
pub const ImportKind = types_mod.ImportKind;
pub const ModuleId = types_mod.ModuleId;
pub const ModuleInfo = types_mod.ModuleInfo;
pub const SymbolEdge = types_mod.SymbolEdge;
pub const ResolveError = types_mod.ResolveError;
pub const CycleRecord = types_mod.CycleRecord;
pub const SymbolKind = types_mod.SymbolKind;
pub const ModuleNode = types_mod.ModuleNode;
pub const SymbolNode = types_mod.SymbolNode;
pub const ModuleEdge = types_mod.ModuleEdge;
pub const GraphError = types_mod.GraphError;
pub const stateIsTraversable = types_mod.stateIsTraversable;

// module_graph.zig：第一层图（Module Dependency Graph）
pub const ModuleGraph = module_graph_mod.ModuleGraph;

// symbol_graph.zig：第二层图（Symbol / Function Dependency Graph）
// 注意：本文件的 GraphError 是 types.zig 的规范错误集；symbol_graph.zig
// 自含的 GraphError（Allocator.Error || InvalidExpandedEdgeKind）是
// SymbolGraph 方法的局部错误集，未由 facade 转发，统一是后续接线 Phase 的事。
pub const RefKind = symbol_graph_mod.RefKind;
pub const SymbolRefEdge = symbol_graph_mod.SymbolRefEdge;
pub const ModuleDep = symbol_graph_mod.ModuleDep;
pub const SymbolGraph = symbol_graph_mod.SymbolGraph;

// retention.zig：保留规则登记（只登记，不裁剪）
pub const RetainRule = retention_mod.RetainRule;
pub const RuleNote = retention_mod.RuleNote;
pub const rule_notes = retention_mod.rule_notes;
pub const noteFor = retention_mod.noteFor;
pub const RetainRuleSet = retention_mod.RetainRuleSet;
pub const RetainSet = retention_mod.RetainSet;

// builder.zig：图构建器（边整理器，只读输入、不改 loader/flattener）
pub const StateFn = builder_mod.StateFn;
pub const FilterResult = builder_mod.FilterResult;
pub const GraphBuilder = builder_mod.GraphBuilder;
