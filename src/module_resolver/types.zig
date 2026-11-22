//! 模块解析器核心类型 —— SA 标准库模块化 Phase 2（Import Resolver）。
//!
//! 本文件只定义类型，不做任何磁盘 I/O 与定位逻辑（定位见 locator.zig）。
//! 公开 API 名由 Phase 2 任务固定，P2C 的 facade 会按这些名字 re-export，
//! 改名即 breaking change。
//!
//! 背景：提案 STD-MODULARIZATION-PROPOSAL.md §2（四种模块状态与循环依赖）、
//! §7（符号级与模块级都支持，底层统一成符号依赖图）；Phase 1 接口见
//! RESULT.md §6（re-export 就是 1 行 @import 转发；@import 为文本包含 +
//! 按规范路径去重；.sa 与同 stem 的 .sai/.sal 必须同目录移动）。

const std = @import("std");

/// 模块在懒加载状态机中的位置（提案 §2）。
/// 迁移方向：unloaded → loading → loaded → analyzed。
/// 循环依赖时一个模块会在 loading 态被再次遇到，是否合法由语义规则
/// （Phase 3）判定，本文件只记录状态，不判定。
pub const ModuleState = enum {
    /// 只知道模块路径，尚未读取。
    unloaded,
    /// 正在读取和解析。
    loading,
    /// AST / 模块内容已加载。
    loaded,
    /// 名称解析、语义分析已完成。
    analyzed,
};

/// 导入的粒度（提案 §7：两种都支持，底层统一成符号依赖图）。
pub const ImportKind = enum {
    /// 符号级导入：`import sa_std.io.print`，只加载 print 及其依赖。
    symbol,
    /// 模块级导入：`import sa_std.io`，加载 io 域 prelude，但只把实际
    /// 使用的符号编入产物（裁剪在 Phase 5/6 做）。
    module,
};

/// 解析器在定位与解析阶段可能报出的错误。
///
/// 注意：ImportCycle 在本 Phase 2 不由定位器触发——循环检测仍由现有
/// flattener（src/flattener/expandimportsinto.zig 的 seen_paths，约 110
/// 行处）负责；此处保留该变体，供 Phase 3 懒加载器在接管加载状态机时使用。
/// AmbiguousImport 与 UnsupportedVersion 同理为预留：Phase 2 是本地单一
/// 版本树、无注册表，定位器按扩展名优先级（.sa → .sal → .sla → .sai）
/// 唯一确定命中，不产生歧义；版本只记录不校验。
pub const ResolveError = error{
    /// 规范路径在域内无命中，且顶层旧路径 shim 也不存在。
    ModuleNotFound,
    /// 依赖闭包中出现环（Phase 2 定位器不触发，见上）。
    ImportCycle,
    /// 同一导入说明符匹配到多个候选且无优先级可裁决（Phase 2 不触发，预留）。
    AmbiguousImport,
    /// 请求的版本在本地树中不存在（Phase 2 无注册表、不校验，预留）。
    UnsupportedVersion,
    /// 导入说明符为空、缺包名、或含 `..` 等非法段。
    InvalidImportSpec,
    /// 分配失败。
    OutOfMemory,
};

/// 一条 import 声明解析后的结构化形式。
///
/// 所有权规则（合并对齐，Phase 2）：
/// parseImportSpec 返回的 spec：raw/path/version 为 owned（调用方负责
/// 释放，见 deinit）；package 与 symbol 借用 path 的子串（首段 / 末段去
/// 扩展名），不单独释放。手工构造的 spec 若字段并非此借用关系，不得
/// 调 deinit。`path` 为归一化后的斜杠路径（含包名前缀，如
/// `sa_std/io/print`；扩展名按原文保留，可能带也可能不带）。
pub const ImportSpec = struct {
    /// 原始说明符文本，如 `sa_std.io.print` 或 `sa_std/io/print.sa`。
    raw: []const u8,
    /// 符号级（symbol）或模块级（module）。
    kind: ImportKind,
    /// 包名，如 `sa_std`。
    package: []const u8,
    /// 归一化后的斜杠路径，如 `sa_std/io/print`（扩展名按原文保留）。
    path: []const u8,
    /// 符号级导入的符号名；模块级导入为 null。
    symbol: ?[]const u8,
    /// 请求版本原文（如 `>=0.1.8`）；无版本要求为 null。
    /// Phase 2 只解析并记录：本地树是单一版本，不做校验、不查注册表
    /// （sa_std/sa.mod 第 5 行注释：版本/依赖字段当前 manifest 语法不支持）。
    version: ?[]const u8,

    /// 释放 parseImportSpec 产出的 owned 字段（raw/path/version）。
    /// 前提：本 spec 由 parseImportSpec 产出（此时 package 与 symbol
    /// 借用 path，不单独释放）。手工构造的 spec 不得调用。
    pub fn deinit(self: *ImportSpec, allocator: std.mem.Allocator) void {
        allocator.free(self.raw);
        allocator.free(self.path);
        if (self.version) |v| allocator.free(v);
        self.* = undefined;
    }
};

/// 模块的规范身份：包名 + 归一化斜杠路径。
///
/// `path` 是含扩展名的完整规范路径（如 `sa_std/io/print.sa`）。与
/// ImportSpec.path 的区别：ImportSpec.path 是用户写法的归一化（可能无
/// 扩展名），ModuleId.path 是定位器解析后的唯一身份（含命中扩展名），
/// 供去重与依赖闭包使用——`sa_std/io/print` 与 `sa_std/io/print.sa`
/// 指向同一个 ModuleId。
///
/// 例外：经旧路径 shim 定位的模块，ModuleId.path 是 shim 自身的路径
/// （如 `sa_std/vec.sa`），而非其转发的规范路径；Phase 3 加载器在读到
/// shim 的 1 行 @import 转发时再解析到规范目标（见 ModuleInfo.is_shim）。
pub const ModuleId = struct {
    package: []const u8,
    path: []const u8,

    pub fn eql(self: ModuleId, other: ModuleId) bool {
        return std.mem.eql(u8, self.package, other.package) and
            std.mem.eql(u8, self.path, other.path);
    }

    /// 64 位哈希（Wyhash，先包名后路径），供 HashMap 去重用。
    pub fn hash(self: ModuleId) u64 {
        var h = std.hash.Wyhash.hash(0, self.package);
        h = std.hash.Wyhash.hash(h, self.path);
        return h;
    }

    /// `std.HashMap(ModuleId, V, ModuleId.Context, ...)` 的上下文。
    pub const Context = struct {
        pub fn hash(_: Context, id: ModuleId) u64 {
            return id.hash();
        }

        pub fn eql(_: Context, a: ModuleId, b: ModuleId) bool {
            return a.eql(b);
        }
    };
};

/// 定位器解析出的一条模块记录。
///
/// `fs_path` 与 `id.path` 为定位器分配的所有权字符串（调用方负责释放，
/// 约定与 Locator 的 allocator 一致）；其余字段为借用或值类型。
/// `kind` 记录本次是通过哪种粒度的导入定位到该模块的：符号级导入命中
/// 单个文件，模块级导入命中域 prelude（见 Locator.locatePrelude）。
pub const ModuleInfo = struct {
    /// 规范身份（path 含命中扩展名；shim 定位时为 shim 自身路径）。
    id: ModuleId,
    /// 加载状态机位置；定位器刚解析出的模块一律为 .unloaded
    /// （定位 ≠ 读取，读取是 Phase 3 懒加载器的事）。
    state: ModuleState,
    /// 磁盘路径（std_root 与规范路径拼接，如 `<std_root>/io/print.sa`）。
    fs_path: []const u8,
    /// 本次定位的导入粒度。
    kind: ImportKind,
    /// 是否经旧路径 shim 定位（顶层同名文件，如 sa_std/vec.sa）。
    /// shim 本身是 1 行 @import 转发（Phase 1 约定），加载器后续跟随
    /// 转发到规范路径；去重按规范路径做，见 flattener seen_paths。
    is_shim: bool,
};

/// 符号级与模块级导入统一落成的依赖边（提案 §3/§7）。
///
/// 两种导入在依赖图里是同一种边，区别只在 `symbol` 与 `kind`：
/// 符号级边 symbol 有值；模块级边 symbol 为 null，表示“依赖该模块的
/// 公共面，具体符号由可达性分析（Phase 5）再收敛”。
/// 供 Phase 4（sa-dependency-graph）消费；本文件只定义形状，不建图。
pub const SymbolEdge = struct {
    /// 导入方模块。
    from: ModuleId,
    /// 被导入模块。
    to: ModuleId,
    /// 符号级导入的符号名；模块级导入为 null。
    symbol: ?[]const u8,
    /// 边的导入粒度。
    kind: ImportKind,
};
