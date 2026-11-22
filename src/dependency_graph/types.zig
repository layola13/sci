//! 依赖图共享类型 —— SA 标准库模块化 Phase 4（sa-dependency-graph，P4A）。
//!
//! 职责：只定义 `src/dependency_graph/` 内共享的类型，不做任何磁盘 I/O、
//! 不建图、不跑可达性分析（建图见 module_graph.zig；符号级可达性与裁剪
//! 是 Phase 5/6 的事）。
//!
//! 背景：提案 STD-MODULARIZATION-PROPOSAL.md §3（两层依赖图：模块依赖图
//! 决定哪些模块需要加载/分析，符号/函数依赖图决定哪些函数与全局数据进入
//! 最终产物）与 §7（符号级与模块级导入都支持，底层统一成符号依赖图）。
//! 本文件是这两层图共用的类型层：ModuleNode / ModuleEdge 是模块图层，
//! SymbolNode 是符号图层（P4B/P4C 消费）。
//!
//! 复用（不重定义）：ModuleState / ImportKind / ModuleId / ModuleInfo /
//! SymbolEdge / ResolveError 复用 `src/module_resolver/types.zig`；
//! CycleRecord 复用 `src/module_resolver/closure.zig`。
//!
//! 所有权 / arena 规则（与 Phase 2 的 A8、Phase 3 的 loader 一致）：
//!   - 本文件所有类型只借用字符串，不拥有。ModuleNode.fs_path、
//!     SymbolNode.name 均为调用方 arena（或短命分配器）里的借用串；
//!     deinit（在 module_graph.zig 的 ModuleGraph.deinit 里）只释放容器
//!     本身，不释放任何借用串。调用方跑完一次构建后统一释放 arena。
//!   - 例外：ModuleGraph.topoSort() 发现环时产生的 CycleRecord.cycle_path
//!     由 ModuleGraph 自己分配并拥有，随 ModuleGraph.deinit / 下一次
//!     topoSort() 释放（见 module_graph.zig 的 clearCycles）。
//!
//! SymbolNode 命名规则（与 P4B/P4C 的接口约定）：
//!   - `name` 是裸符号名，即 import 写法里的符号原样，不带包名前缀、
//!     不带模块路径、不带扩展名、不带版本后缀。例如
//!     `import sa_std.io.print` 对应 name = "print"，而不是
//!     "sa_std/io/print" 或 "sa_std.io.print"。
//!   - 模块级导入（SymbolEdge.symbol 为 null）没有对应的 SymbolNode：
//!     它只落一条 ModuleEdge（via = .module），表示“依赖该模块的公共面”；
//!     具体用到哪些符号由 Phase 5 的可达性分析再收敛，P4B 不得把模块级
//!     导入展开成“该模块的全部符号”。
//!   - 同一符号在不同模块里是不同节点：SymbolNode 的身份是
//!     (module, name)，kind 只是分类属性，不参与 eql/hash。

const std = @import("std");
const types = @import("../module_resolver/types.zig");
const closure_mod = @import("../module_resolver/closure.zig");

// Phase 2 类型（复用，不重定义）。
pub const ModuleState = types.ModuleState;
pub const ImportKind = types.ImportKind;
pub const ModuleId = types.ModuleId;
pub const ModuleInfo = types.ModuleInfo;
pub const SymbolEdge = types.SymbolEdge;
pub const ResolveError = types.ResolveError;
// CycleRecord 复用 closure.zig 的形状（依赖图只维护自己的 cycles 列表）。
pub const CycleRecord = closure_mod.CycleRecord;

/// 符号种类：Phase 5 可达性分析的分类基础；本 Phase 只记录，不判定
/// 任何保留规则（宏 / 反射 / 动态调用 / 全局初始化的保留规则在 Phase 5
/// 定，见提案 §3）。
pub const SymbolKind = enum {
    /// 普通函数（含方法、过程）。
    function,
    /// 全局变量 / 全局常量。
    global,
    /// 类型声明（struct / enum / alias 等）。
    type,
    /// 宏定义（展开后才产生实际引用，见提案 §4 的 Flattener 取舍）。
    macro,
    /// 种类未知（调用方尚未分类时用；不得理解为“可删除”）。
    unknown,
};

/// 模块图节点：一个模块在依赖图里的投影。
///
/// `id` 是规范身份（包名 + 含扩展名的规范路径，见 types.ModuleId）；
/// `state` 是建图时看到的加载状态（fromLoader 取 loader 模块表的权威
/// 状态；手工 addModule 时由调用方传入）；`fs_path` 是借用串（磁盘路径，
/// 无路径信息时为 null，如手工建图未给路径的节点）。
pub const ModuleNode = struct {
    id: ModuleId,
    state: ModuleState,
    fs_path: ?[]const u8 = null,
};

/// 符号图节点：一个模块内的一个符号在依赖图里的投影（P4B/P4C 消费）。
///
/// 身份是 (module, name)：同一名字在不同模块里是不同节点；`kind` 只是
/// 分类属性，不参与 eql/hash（同一符号被不同阶段分类出不同 kind 时仍
/// 是同一节点）。`name` 为借用串，命名规则见文件头（裸符号名）。
pub const SymbolNode = struct {
    module: ModuleId,
    name: []const u8,
    kind: SymbolKind = .unknown,

    pub fn eql(self: SymbolNode, other: SymbolNode) bool {
        return self.module.eql(other.module) and
            std.mem.eql(u8, self.name, other.name);
    }

    /// 64 位哈希（Wyhash，先模块身份后符号名），供 HashMap 去重用。
    /// 与 ModuleId.hash 同款拼法：模块哈希作种子，再混入符号名。
    pub fn hash(self: SymbolNode) u64 {
        var h = self.module.hash();
        h = std.hash.Wyhash.hash(h, self.name);
        return h;
    }

    /// `std.HashMap(SymbolNode, V, SymbolNode.Context, ...)` 的上下文。
    pub const Context = struct {
        pub fn hash(_: Context, node: SymbolNode) u64 {
            return node.hash();
        }

        pub fn eql(_: Context, a: SymbolNode, b: SymbolNode) bool {
            return a.eql(b);
        }
    };

    /// 节点键字符串：`<path>:<symbol>`，如 `sa_std/io/print.sa:print`。
    ///
    /// `ModuleId.path` 已含包名前缀，故通常直接拼 path + ":" + name；
    /// 只有当 path 不以 `package + "/"` 开头时才补包名前缀（相对导入
    /// 定位出的空包 / 非包内模块）。返回 owned 字符串，调用方释放。
    pub fn key(self: SymbolNode, allocator: std.mem.Allocator) std.mem.Allocator.Error![]u8 {
        const pkg = self.module.package;
        const path = self.module.path;
        if (pkg.len > 0 and
            !(std.mem.startsWith(u8, path, pkg) and
                path.len > pkg.len and path[pkg.len] == '/'))
        {
            return std.fmt.allocPrint(allocator, "{s}/{s}:{s}", .{ pkg, path, self.name });
        }
        return std.fmt.allocPrint(allocator, "{s}:{s}", .{ path, self.name });
    }

    /// 模块根节点：模块自身作为符号命名空间根，命名约定为
    /// `<module>:<module>`——节点名取模块自身的 path，键形如
    /// `sa_std/io/print.sa:sa_std/io/print.sa`。
    pub fn moduleRoot(module: ModuleId) SymbolNode {
        return .{ .module = module, .name = module.path, .kind = .unknown };
    }

    /// 是否为模块根节点（节点名等于所属模块的 path）。
    pub fn isModuleRoot(self: SymbolNode) bool {
        return std.mem.eql(u8, self.name, self.module.path);
    }
};

/// 模块级依赖边：一条模块到模块的依赖（多条 SymbolEdge 落成一条）。
///
/// 两种导入在模块图里是同一种边，区别只在 `via`：
///   - 符号级导入（`import sa_std.io.print`）落成的边 via = .symbol；
///   - 模块级导入（`import sa_std.io`）落成的边 via = .module；
///   - via = null 表示粒度未知 / 未记录（手工 addEdge 未传 kind 时），
///     不得理解为第三种导入方式。
/// 去重按 (from, to) 做：多条 SymbolEdge 落成一条 ModuleEdge 时保留
/// 首条边的 kind（见 ModuleGraph.addEdge）。
pub const ModuleEdge = struct {
    /// 导入方模块。
    from: ModuleId,
    /// 被导入模块。
    to: ModuleId,
    /// 该边的导入粒度（即落成此边的首条 SymbolEdge 的 kind）。
    via: ?ImportKind = null,
};

/// 依赖图操作的错误集。
///
/// 注意：OutOfMemory 在此集中，所以分配失败可直接以 GraphError!T 的
/// 形式向上传，不必再包一层 error 集。
pub const GraphError = error{
    /// 分配失败。
    OutOfMemory,
    /// 查询 / 迁移的目标模块不在图里。
    NodeNotFound,
    /// topoSort() 遇环：环记录见 ModuleGraph.lastCycles()。
    CycleDetected,
    /// 非法状态迁移（见 ModuleGraph.setState 的单步前向规则）。
    InvalidState,
};

/// 判定该状态的节点是否可参与可达遍历：只有 loaded / analyzed 态的
/// 节点才可走（提案 §2：unloaded 只是知道路径，loading 正在读解析中，
/// 两者都还没有可供遍历的模块内容）。
/// ModuleGraph.reachableFrom() 用此判定过滤可达集。
pub fn stateIsTraversable(state: ModuleState) bool {
    return switch (state) {
        .loaded, .analyzed => true,
        .unloaded, .loading => false,
    };
}
