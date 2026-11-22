//! 保留规则登记 —— SA 标准库模块化 Phase 4（P4B，sa-dependency-graph）。
//!
//! 职责：提案 §3 末尾的保留规则——对宏、反射、动态调用、全局初始化，
//! 提供必要的保留规则，不能错误删除运行时会访问的符号。
//!
//! 本文件只登记（register），不实现裁剪：裁剪（Reachability-based
//! DCE）是 Phase 5/6（sa-reachability）的事。`RetainSet` 只回答“哪些
//! 符号因哪条规则被保留”，不回答“哪些符号可以删除”，更不删除任何东西。
//!
//! 判定边界（今天没有判定能力，故只登记规则文本与触发条件）：
//!   - 入口点（`entry_point`）：可判定——`main` 符号恒保留，见
//!     `retainMain`；
//!   - 全局初始化（`global_init`）：可登记——有 `global_init` 边的符号
//!     默认保留，见 `retainGlobalInits`（边由符号图提供）；
//!   - 宏展开（`macro_expanded`）、反射（`reflective`）、动态调用
//!     （`dynamic_call`）：只登记规则文本与触发条件（`rule_notes` /
//!     `noteFor`），不做判定逻辑——判定需解析器 / 后端能力（宏展开表、
//!     反射元数据、动态分发表），今天没有；
//!   - 导出（`exported`）：只登记——导出表由后端 / 链接层提供，今天没有，
//!     调用方拿到导出符号后用 `retainExported` 登记。
//!
//! 去重口径：`RetainSet` 按符号节点键去重——键即
//! `SymbolNode` 的身份（`module: ModuleId` + `name`），与键字符串
//! `<path>:<symbol>`（如 `sa_std/io/print.sa:print`）一一对应；
//! 同一节点可累积多条规则，`rulesFor` 返回其全部规则。
//!
//! 所有权 / arena 规则（与 Phase 2/3、symbol_graph.zig 一致）：
//!   - 登记集不拥有任何字符串：节点名、模块 path 均为调用方所有；
//!   - `deinit` 只释放容器本身；`rulesList` / `retainedNodes` 返回的
//!     owned 切片由调用方释放切片本身，切片内的节点仍借用原字符串。
//!
//! 不属于本文件：裁剪实现（Phase 5/6）；判定逻辑（解析器 / 后端）；
//! build.zig 注册（后续 Phase / 协调方接线）。

const std = @import("std");
const types = @import("../module_resolver/types.zig");
const symbol_graph = @import("symbol_graph.zig");

// 复用，不重定义。
pub const ModuleId = types.ModuleId;
pub const SymbolNode = symbol_graph.SymbolNode;
pub const SymbolKind = symbol_graph.SymbolKind;
pub const RefKind = symbol_graph.RefKind;
pub const SymbolGraph = symbol_graph.SymbolGraph;

/// 保留规则：一条符号因何被保留。
pub const RetainRule = enum {
    /// 入口点：程序入口符号恒保留（`main`，见 `retainMain`）。
    entry_point,
    /// 宏展开产物：符号由宏展开产生或被宏展开引用。
    macro_expanded,
    /// 反射访问：符号可能经反射（按名查找）访问。
    reflective,
    /// 动态调用：符号可能经动态分发 / 函数指针 / 回调访问。
    dynamic_call,
    /// 全局初始化：符号参与全局量初始化（有 `global_init` 边）。
    global_init,
    /// 导出符号：符号在导出表内，对外可见。
    exported,

    /// 规则的英文名（`@tagName`）。
    pub fn name(self: RetainRule) []const u8 {
        return @tagName(self);
    }
};

/// 一条规则的登记文本：规则 + 触发条件（文字描述）+ 备注。
/// 只登记，不做判定逻辑——判定需解析器 / 后端能力，今天没有。
pub const RuleNote = struct {
    rule: RetainRule,
    /// 触发条件（文字描述）：什么情况下该规则适用。
    condition: []const u8,
    /// 备注：判定能力缺口与后续接线点。
    note: []const u8,
};

/// 全部保留规则的登记文本表（编译期常量）。
/// `entry_point` 与 `global_init` 已有可执行的登记入口
/// （`retainMain` / `retainGlobalInits`）；其余规则的判定逻辑待
/// 解析器 / 后端能力到位后在 Phase 5/6 接线，此处只留文本。
pub const rule_notes: []const RuleNote = &.{
    .{
        .rule = .entry_point,
        .condition = "符号是程序入口 `main`（入口模块内名为 `main` 的符号）。",
        .note = "恒保留，无条件；由 retainMain 登记，不依赖任何分析结果。",
    },
    .{
        .rule = .macro_expanded,
        .condition = "符号由宏展开产生，或被展开后的代码引用（Flattener 展开后出现 macro_expansion 边指向该符号）。",
        .note = "判定需 Flattener 的宏展开表：展开产物表未建成前不做判定，只登记规则；展开边由 SymbolGraph.addExpandedEdge 记录。",
    },
    .{
        .rule = .reflective,
        .condition = "符号可能经反射按名查找访问（如按字符串名解析符号、动态加载符号表）。",
        .note = "判定需反射元数据（哪些符号参与反射注册）：今天无反射元数据来源，不做判定；有反射注册表后，注册表内符号按本规则登记。",
    },
    .{
        .rule = .dynamic_call,
        .condition = "符号可能经动态分发访问（如函数指针、虚表 / 动态调用点、回调注册）。",
        .note = "判定需动态分发表（调用点 → 候选目标集）：今天无分发表来源，不做判定；分发表建成后，候选目标按本规则登记。",
    },
    .{
        .rule = .global_init,
        .condition = "符号参与全局量初始化（符号图中有 global_init 边指向该符号）。",
        .note = "默认保留；由 retainGlobalInits 按符号图中的 global_init 边登记。全局初始化顺序本身不是本文件的职责。",
    },
    .{
        .rule = .exported,
        .condition = "符号在导出表内（模块 / 库的对外导出符号）。",
        .note = "判定需后端 / 链接层提供的导出表：今天无导出表来源，不做判定；拿到导出表后，表内符号用 retainExported 登记。",
    },
};

/// 取一条规则的登记文本；未知规则（不应发生）返回 null。
pub fn noteFor(rule: RetainRule) ?RuleNote {
    for (rule_notes) |note| {
        if (note.rule == rule) return note;
    }
    return null;
}

/// 一组保留规则（位集；同一节点可累积多条规则）。
pub const RetainRuleSet = struct {
    bits: u8 = 0,

    fn bit(rule: RetainRule) u8 {
        return @as(u8, 1) << @as(u3, @intCast(@intFromEnum(rule)));
    }

    pub fn insert(self: *RetainRuleSet, rule: RetainRule) void {
        self.bits |= bit(rule);
    }

    pub fn contains(self: RetainRuleSet, rule: RetainRule) bool {
        return self.bits & bit(rule) != 0;
    }

    pub fn isEmpty(self: RetainRuleSet) bool {
        return self.bits == 0;
    }

    /// 集合内规则条数。
    pub fn count(self: RetainRuleSet) usize {
        return @popCount(self.bits);
    }

    /// 与另一规则集合并。
    pub fn merge(self: *RetainRuleSet, other: RetainRuleSet) void {
        self.bits |= other.bits;
    }
};

/// 保留规则登记集：符号节点 → 其保留规则集。
///
/// 只登记，不裁剪。调用方（Phase 5/6 的 sa-reachability）在做可达性
/// 分析时把本集作为“不可删除”的种子之一：被保留的符号及其可达闭包
/// 不参与裁剪；其余符号的去留由可达性判定。
pub const RetainSet = struct {
    /// 调用方传入的分配器（通常是 arena）；登记集不拥有它，也不拥有字符串。
    allocator: std.mem.Allocator,
    /// 按符号节点键去重的登记表：键即 SymbolNode 身份，与键字符串
    /// `<path>:<symbol>` 一一对应。
    entries: std.HashMap(SymbolNode, RetainRuleSet, SymbolNode.Context, std.hash_map.default_max_load_percentage),

    pub fn init(allocator: std.mem.Allocator) RetainSet {
        return .{
            .allocator = allocator,
            .entries = std.HashMap(SymbolNode, RetainRuleSet, SymbolNode.Context, std.hash_map.default_max_load_percentage).init(allocator),
        };
    }

    pub fn deinit(self: *RetainSet) void {
        // 只释放容器本身；节点字符串均为调用方所有（arena 规则）。
        self.entries.deinit();
    }

    /// 已登记的符号节点数（去重后）。
    pub fn count(self: *const RetainSet) usize {
        return self.entries.count();
    }

    /// 按一条规则保留一个符号（同一节点可多次登记不同规则，累积）。
    pub fn retain(self: *RetainSet, node: SymbolNode, rule: RetainRule) std.mem.Allocator.Error!void {
        const entry = try self.entries.getOrPut(node);
        if (!entry.found_existing) {
            entry.value_ptr.* = .{};
        }
        entry.value_ptr.insert(rule);
    }

    /// 按一组规则保留一个符号。
    pub fn retainRules(self: *RetainSet, node: SymbolNode, rules: RetainRuleSet) std.mem.Allocator.Error!void {
        const entry = try self.entries.getOrPut(node);
        if (!entry.found_existing) {
            entry.value_ptr.* = .{};
        }
        entry.value_ptr.merge(rules);
    }

    /// 该符号是否被保留（至少登记了一条规则）。
    pub fn isRetained(self: *const RetainSet, node: SymbolNode) bool {
        const rules = self.entries.get(node) orelse return false;
        return !rules.isEmpty();
    }

    /// 该符号的全部保留规则（未登记返回空集）。
    pub fn rulesFor(self: *const RetainSet, node: SymbolNode) RetainRuleSet {
        return self.entries.get(node) orelse .{};
    }

    /// 该符号的全部保留规则，展开为 owned 规则切片（按 RetainRule
    /// 声明顺序）。调用方释放切片本身。
    pub fn rulesList(self: *const RetainSet, node: SymbolNode, allocator: std.mem.Allocator) std.mem.Allocator.Error![]RetainRule {
        const rules = self.rulesFor(node);
        var out = std.array_list.Managed(RetainRule).init(allocator);
        errdefer out.deinit();
        const all = [_]RetainRule{ .entry_point, .macro_expanded, .reflective, .dynamic_call, .global_init, .exported };
        for (all) |rule| {
            if (rules.contains(rule)) try out.append(rule);
        }
        return out.toOwnedSlice();
    }

    /// 全部被保留的符号节点。返回 owned 切片，调用方释放切片本身；
    /// 顺序未指定（哈希表迭代序）。
    pub fn retainedNodes(self: *const RetainSet, allocator: std.mem.Allocator) std.mem.Allocator.Error![]SymbolNode {
        var out = std.array_list.Managed(SymbolNode).init(allocator);
        errdefer out.deinit();
        var it = self.entries.keyIterator();
        while (it.next()) |node_ptr| {
            try out.append(node_ptr.*);
        }
        return out.toOwnedSlice();
    }

    /// 入口点约定：入口模块内名为 `main` 的符号恒保留（entry_point）。
    /// 调用方传入程序入口模块；`main` 记为 function kind。
    pub fn retainMain(self: *RetainSet, entry_module: ModuleId) std.mem.Allocator.Error!void {
        try self.retain(.{
            .module = entry_module,
            .name = "main",
            .kind = .function,
        }, .entry_point);
    }

    /// 全局初始化：符号图中有 `global_init` 边的符号默认保留。
    /// 遍历图中全部 `global_init` 边，将每条边的 to 端以 `global_init`
    /// 规则登记。只读符号图，不改图。
    pub fn retainGlobalInits(self: *RetainSet, graph: *const SymbolGraph) std.mem.Allocator.Error!void {
        for (graph.edges.items) |edge| {
            if (edge.kind == .global_init) {
                try self.retain(edge.to, .global_init);
            }
        }
    }

    /// 导出符号登记：调用方拿到导出表后，将表内符号逐个登记为
    /// `exported`。导出表本身由后端 / 链接层提供，今天没有，本方法
    /// 只做登记，不判定谁是导出符号。
    pub fn retainExported(self: *RetainSet, node: SymbolNode) std.mem.Allocator.Error!void {
        try self.retain(node, .exported);
    }
};
