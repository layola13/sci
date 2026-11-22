//! src/module_resolver.zig — sa-module-resolver facade（Phase 2，提案 §4）。
//!
//! 模块用途：提案 §4 的三个独立模块之首 `sa-module-resolver`（模块定位、
//! import 解析、版本解析）的唯一对外入口。本文件是薄 re-export 层（仿任务 28
//! 的 shim 模式）：不含逻辑，只把四个子文件的公开 API 聚合到一处，供编译器
//! 其余部分用一个 import 取用。
//!
//! 四个子文件分工：
//!   - module_resolver/types.zig   — 共享类型：ModuleState、ImportKind、
//!     ResolveError、ImportSpec、ModuleId、ModuleInfo、SymbolEdge。
//!     ModuleState 四态（unloaded/loading/loaded/analyzed）与循环依赖处理
//!     见提案 §2；两层依赖图（模块依赖图 vs 符号/函数依赖图）见提案 §3。
//!   - module_resolver/locator.zig — 模块定位：Locator、domains 表、
//!     normalizeSpecifier、probeExtensions、findPrelude。
//!   - module_resolver/spec.zig    — import 串解析：parseImportSpec、
//!     classifyImport、canonicalize、VersionSpec、parseVersionSpec、
//!     extractImportStrings（行级文本扫描，供闭包构建器抽 @import 行）。
//!   - module_resolver/closure.zig — 依赖闭包构建器：CycleRecord、
//!     ClosureBuilder（工作表算法，产出 states/order/edges/cycles）。
//!
//! Phase 映射：
//!   - 本文件对应提案 §4 的 sa-module-resolver（Phase 2，Import Resolver）。
//!   - sa-dependency-graph（Phase 4，模块和符号依赖图）与 sa-reachability
//!     （Phase 5，可达性分析、未使用符号裁剪）是后续 Phase，不在本文件；
//!     闭包构建器产出的 edges/cycles 是它们的输入，不是它们本身。
//!   - 懒加载本体（Phase 3，Lazy Module Loading）消费 ClosureBuilder，
//!     接线点在 Phase 3；Phase 2 只定义结构与状态流转，不接线、不替换
//!     flattener 的 expandimportsinto。
//!
//! 依赖：本模块独立于 Lexer、Referee、Backend（提案 §4）；只依赖 std 与
//! 仓库既有 sio 封装做文件存在性判断、读取与文本扫描。详见
//! src/module_resolver/MANIFEST.md。

const types = @import("module_resolver/types.zig");
const locator = @import("module_resolver/locator.zig");
const spec = @import("module_resolver/spec.zig");
const closure = @import("module_resolver/closure.zig");

// types.zig：共享类型。
pub const ModuleState = types.ModuleState;
pub const ImportKind = types.ImportKind;
pub const ResolveError = types.ResolveError;
pub const ImportSpec = types.ImportSpec;
pub const ModuleId = types.ModuleId;
pub const ModuleInfo = types.ModuleInfo;
pub const SymbolEdge = types.SymbolEdge;

// locator.zig：模块定位。
pub const Locator = locator.Locator;
pub const domains = locator.domains;
pub const normalizeSpecifier = locator.normalizeSpecifier;
pub const probeExtensions = locator.probeExtensions;
pub const findPrelude = locator.findPrelude;

// spec.zig：import 串解析。
pub const parseImportSpec = spec.parseImportSpec;
pub const classifyImport = spec.classifyImport;
pub const canonicalize = spec.canonicalize;
pub const VersionSpec = spec.VersionSpec;
pub const parseVersionSpec = spec.parseVersionSpec;
pub const extractImportStrings = spec.extractImportStrings;

// closure.zig：依赖闭包构建器。
pub const CycleRecord = closure.CycleRecord;
pub const ClosureBuilder = closure.ClosureBuilder;
