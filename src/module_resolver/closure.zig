//! src/module_resolver/closure.zig — 依赖闭包构建器（Phase 2，提案 §2/§3/§4）。
//!
//! 职责：从入口 import 出发，沿 @import 边做显式栈 DFS（工作表算法），产出
//! 一个模块的依赖闭包：
//!   - states：每个已发现模块的 ModuleState（unloaded → loading → loaded → analyzed）；
//!   - order：后序拓扑顺序（依赖先于使用方；环内成员相邻，严格拓扑序不存在）；
//!   - edges：符号级与模块级 import 统一落成的 SymbolEdge；
//!   - cycles：发现的导入环（只记录，不报错）。
//!
//! 与现有机制的关系（详见 src/module_resolver/MANIFEST.md 关系表）：
//!   - 不替换 flattener 的 expandimportsinto.zig。flattener 仍是真正展开
//!     @import、报 error.ImportCycle 的地方；本构建器只做“发现依赖、记录
//!     结构”，供 Phase 3 懒加载消费时再接线。
//!   - 环处理与 ImportCycle 的语义关系：flattener 用 active_paths（递归栈）
//!     检测环并立即报 error.ImportCycle；本构建器用同样的“在栈上 =
//!     loading 态”判定，遇到已在 loading 态的目标时不递归，只记一条
//!     CycleRecord。环是否合法由语义规则定（提案 §2），Phase 3 决定；
//!     Phase 2 不改变 flattener 的任何行为。
//!   - analyzed 在 Phase 2 是占位态：loaded 之后直接置 analyzed，表示
//!     “本构建器已完成对该模块的发现工作”；真正的名称解析/语义分析是
//!     Phase 3 的事，届时在 loaded → analyzed 之间插入。
//!   - 不做并行（提案 §5：先把依赖语义弄正确，再考虑并行）。
//!   - .sai/.sal 不作为闭包节点：导入 .sa 时同目录同 stem 的 .sai/.sal
//!     由 flattener/injectimportedfile.zig 自动注入，是伴生文件而非
//!     @import 目标；本构建器只扫描定位到的模块文件本身的 @import 行。
//!   - 相对路径 import（如 `../sync/rwlock.sal`）的解析责任在 caller /
//!     locator：本构建器把行内原始串原样交给 parseImportSpec 与
//!     locator.locate，不自己拼基准目录。
//!
//! 合并对齐（协调 agent 合并时已按 P2A 的 types.zig/locator.zig 与
//! P2B 的 spec.zig 核对，约定如下；与本文件头其他部分不一致处以此为准）：
//!   A1. types.ModuleId 为值类型，可 AutoHash（types.zig 的 Context）；
//!       types.ModuleInfo 含 `id: ModuleId`、`state`、`fs_path: []const u8`
//!       （磁盘路径）、`kind`、`is_shim`——没有 `path` 字段，读文件用
//!       `fs_path`。ModuleId.package 恒为字面量 "sa_std"（locator 的
//!       makeInfo 不借用 spec 字符串）；id.path/fs_path 为定位器分配的
//!       字符串，按 A8 的 arena 规则统一释放，builder 不逐个释放。
//!   A2. Locator.locate(self: Locator, spec: ImportSpec) ResolveError!ModuleInfo
//!       （self 按值传；ClosureBuilder 按值持有 locator 副本）。
//!   A3. 模块级边的 `to` 取法：调 `locator.locatePrelude(domain)` 得
//!       ModuleInfo，用其 `.id`；无 prelude 的域（如 string/）报
//!       ModuleNotFound 时 `to` 保持为域模块本身。自由函数
//!       `locator.findPrelude(allocator, domain)` 只返回 prelude 相对
//!       路径（?[]u8），不直接返回 ModuleId。
//!   A4. spec.extractImportStrings(allocator, source) ![][]const u8，
//!       返回的每个字符串与外层切片均为 owned（allocator.dupe）；帧
//!       弹出/出错时须逐个 free 再 free 切片（见 pushModule 与 build）。
//!   A5. spec.parseImportSpec(allocator, raw: []const u8) ResolveError!ImportSpec；
//!       ImportSpec 含 `raw/kind/package/path/symbol/version`（package 与
//!       symbol 借用 path 的子串；无 `domain` 字段——域名由本文件的
//!       domainOf(spec) 从 path 取）。歧义时 parseImportSpec 透传
//!       error.AmbiguousImport。
//!   A6. ImportKind 只有 .symbol 与 .module 两态；SymbolEdge 含
//!       `from/to/symbol/kind`。emitEdge 的 switch 为穷尽 switch。
//!   A7. 文件读取走仓库既有 sio 封装（与 src/llvm2sa/translate.zig 同款调用
//!       `sio.cwd().readFileAlloc(allocator, path, limit)`）。
//!   A8. 所有权/arena 规则：解析产物字符串（spec 的 raw/path/version、
//!       ModuleInfo 的 id.path/fs_path、extractImportStrings 的串）均由
//!       调用方分配器分配，Phase 2 不逐个追踪释放；预期用法是调用方用
//!       arena（或短命分配器）跑一次构建后统一释放。ClosureBuilder
//!       .deinit 只释放自身 dup 的东西（边符号串、环路径、帧的 source 与
//!       imports 串）；不释放 locator（调用方拥有）。例外：build() 循环内
//!       每轮的 spec 在迭代结束即 deinit（此时 locate/emitEdge 已用完它，
//!       且不借用它的串）。

const std = @import("std");
const sio = @import("sio");
const types = @import("types.zig");
const locator_mod = @import("locator.zig");
const spec_mod = @import("spec.zig");

pub const ModuleId = types.ModuleId;
pub const ModuleState = types.ModuleState;
pub const ImportKind = types.ImportKind;
pub const ImportSpec = types.ImportSpec;
pub const ModuleInfo = types.ModuleInfo;
pub const SymbolEdge = types.SymbolEdge;
pub const ResolveError = types.ResolveError;
pub const Locator = locator_mod.Locator;

/// 一条被发现的导入环（只记录，不报错；与 ImportCycle 的关系见文件头）。
pub const CycleRecord = struct {
    /// 环路径，按发现顺序排列（DFS 栈自底向上），首元素即 entry。
    /// 末尾不重复 entry：环为 cycle_path 首尾相接。
    cycle_path: []ModuleId,
    /// 环入口：栈上第一个被再次发现的 loading 态模块。
    entry: ModuleId,
};

/// DFS 栈帧。source 与 imports 由 builder 拥有，帧弹出时释放；
/// imports 中的串为 extractImportStrings 的 owned dupe，释放时先逐个
/// 释串，再释 imports 外层切片，最后释 source。
const Frame = struct {
    id: ModuleId,
    source: []u8,
    imports: [][]const u8,
    next: usize,
};

pub const ClosureBuilder = struct {
    allocator: std.mem.Allocator,
    locator: Locator,
    states: std.AutoHashMap(ModuleId, ModuleState),
    order: std.array_list.Managed(ModuleId),
    edges: std.array_list.Managed(SymbolEdge),
    cycles: std.array_list.Managed(CycleRecord),
    roots: std.array_list.Managed(ModuleInfo),
    stack: std.array_list.Managed(Frame),

    /// 单个模块源码上限（64 MiB；sa_std 内最大文件远小于此值）。
    const max_source_bytes: usize = 64 * 1024 * 1024;

    pub fn init(allocator: std.mem.Allocator, locator: Locator) ClosureBuilder {
        return .{
            .allocator = allocator,
            .locator = locator,
            .states = std.AutoHashMap(ModuleId, ModuleState).init(allocator),
            .order = std.array_list.Managed(ModuleId).init(allocator),
            .edges = std.array_list.Managed(SymbolEdge).init(allocator),
            .cycles = std.array_list.Managed(CycleRecord).init(allocator),
            .roots = std.array_list.Managed(ModuleInfo).init(allocator),
            .stack = std.array_list.Managed(Frame).init(allocator),
        };
    }

    pub fn deinit(self: *ClosureBuilder) void {
        // 边里复制持有的符号名串（见 emitEdge）由 builder 拥有。
        for (self.edges.items) |edge| {
            if (edge.symbol) |symbol| self.allocator.free(symbol);
        }
        self.edges.deinit();
        for (self.cycles.items) |record| {
            self.allocator.free(record.cycle_path);
        }
        self.cycles.deinit();
        // build 未跑完或中途出错时栈上残留的帧一并释放。
        for (self.stack.items) |frame| {
            for (frame.imports) |s| self.allocator.free(s);
            self.allocator.free(frame.imports);
            self.allocator.free(frame.source);
        }
        self.stack.deinit();
        self.order.deinit();
        self.roots.deinit();
        self.states.deinit();
        // 注意：不释放 locator（调用方拥有）；不释放 ModuleId 内部串
        // （借用 locator arena，见文件头假设 A1）。
    }

    /// 查询模块当前状态；未发现返回 null。Phase 3 懒加载消费时的便利查询。
    pub fn stateOf(self: *const ClosureBuilder, id: ModuleId) ?ModuleState {
        return self.states.get(id);
    }

    /// 登记一个入口 import。只做定位与登记，不读文件、不展开依赖；
    /// 真正的工作在 build() 里。重复登记同一入口是无操作（幂等）。
    pub fn addRoot(self: *ClosureBuilder, spec: ImportSpec) ResolveError!void {
        const info = try self.locator.locate(spec);
        if (self.states.contains(info.id)) return;
        try self.states.put(info.id, .unloaded);
        try self.roots.append(info);
    }

    /// 工作表算法：沿 @import 边遍历直至闭包。
    ///
    /// 每个模块的状态流转（见文件头）：
    ///   unloaded → loading（读文件、抽 @import 行）→ loaded → analyzed（占位）。
    /// 已在 loading 态的目标再次被发现时不递归，记一条 CycleRecord；
    /// 已 loaded/analyzed 的目标直接跳过（边照常发，见 emitEdge）。
    /// 相对路径 import 的解析责任在 caller/locator（见文件头）。
    pub fn build(self: *ClosureBuilder) !void {
        for (self.roots.items) |root| {
            if (self.states.get(root.id) != .unloaded) continue;
            try self.pushModule(root);
            while (self.stack.items.len > 0) {
                const frame = &self.stack.items[self.stack.items.len - 1];
                if (frame.next >= frame.imports.len) {
                    // 该模块的全部 import 已发现：loaded → analyzed（占位）。
                    try self.states.put(frame.id, .loaded);
                    try self.states.put(frame.id, .analyzed);
                    try self.order.append(frame.id);
                    const done = self.stack.pop().?;
                    for (done.imports) |s| self.allocator.free(s);
                    self.allocator.free(done.imports);
                    self.allocator.free(done.source);
                    continue;
                }
                const raw = frame.imports[frame.next];
                frame.next += 1;
                const importer = frame.id;
                var spec = try spec_mod.parseImportSpec(self.allocator, raw);
                // spec 的 raw/path/version 为 owned；locate/emitEdge 不借用
                // 它们（ModuleId.package 为字面量、id.path 为新分配串、
                // 边符号串由 emitEdge 自行 dupe），本轮迭代结束即释放。
                defer spec.deinit(self.allocator);
                const info = try self.locator.locate(spec);
                try self.emitEdge(importer, spec, info);
                switch (self.states.get(info.id) orelse .unloaded) {
                    .loading => try self.recordCycle(info.id),
                    .unloaded => try self.pushModule(info),
                    .loaded, .analyzed => {},
                }
            }
        }
    }

    /// 读入一个模块并压入 DFS 栈：unloaded → loading。
    /// 只在目标确为 unloaded（或尚未登记）时调用；其余状态由 build() 分流。
    fn pushModule(self: *ClosureBuilder, info: ModuleInfo) !void {
        if (self.states.get(info.id) orelse .unloaded != .unloaded) return;
        const source = try sio.cwd().readFileAlloc(self.allocator, info.fs_path, max_source_bytes);
        errdefer self.allocator.free(source);
        const imports = try spec_mod.extractImportStrings(self.allocator, source);
        errdefer {
            for (imports) |s| self.allocator.free(s);
            self.allocator.free(imports);
        }
        try self.states.put(info.id, .loading);
        try self.stack.append(.{
            .id = info.id,
            .source = source,
            .imports = imports,
            .next = 0,
        });
    }

    /// 从模块级 import 的规范路径取域名：`sa_std/<domain>/...` 的第二段。
    /// `sa_std/io` → `io`；`sa_std` 本身或相对路径返回 null。
    fn domainOf(spec: ImportSpec) ?[]const u8 {
        const prefix = "sa_std/";
        if (!std.mem.startsWith(u8, spec.path, prefix)) return null;
        const rest = spec.path[prefix.len..];
        if (rest.len == 0) return null;
        const end = std.mem.indexOfScalar(u8, rest, '/') orelse rest.len;
        const domain = rest[0..end];
        if (domain.len == 0) return null;
        return domain;
    }

    /// 每定位到一个模块发一条边（无论目标状态如何：环边与重复边都如实记录；
    /// 去重是 Phase 4 依赖图的事）。
    ///   - 符号级（.symbol）：symbol = 导入的符号名；
    ///   - 模块级（.module）：symbol = null，to = 该域 prelude 的 ModuleId；
    ///     无 prelude 的域（如 string/，见 MANIFEST 已知缺口）边指向该域本身。
    /// symbol 名串由 builder 复制持有，随 deinit 释放（行内原始串借用帧的
    /// source 缓冲，帧弹出即失效，不能直接存进边里）。
    fn emitEdge(self: *ClosureBuilder, importer: ModuleId, spec: ImportSpec, info: ModuleInfo) !void {
        var to = info.id;
        var symbol: ?[]const u8 = null;
        switch (spec.kind) {
            .symbol => {
                if (spec.symbol) |name| {
                    symbol = try self.allocator.dupe(u8, name);
                }
            },
            .module => {
                // 模块级边的 to 取该域 prelude 的 ModuleId；无 prelude 的
                // 域（如 string/）locatePrelude 报 ModuleNotFound，to 保
                // 持为域模块本身。prelude 的 ModuleInfo 字符串按 A8 的
                // arena 规则处理（本处不释放）。
                if (domainOf(spec)) |domain| {
                    if (self.locator.locatePrelude(domain)) |prelude| {
                        to = prelude.id;
                    } else |_| {}
                }
            },
        }
        errdefer if (symbol) |name| self.allocator.free(name);
        try self.edges.append(.{
            .from = importer,
            .to = to,
            .symbol = symbol,
            .kind = spec.kind,
        });
    }

    /// 记录一条环：cycle_path 为 DFS 栈上从 entry 到栈顶的连续段（按发现顺序），
    /// entry 为环入口。栈上必有 entry（loading 态当且仅当在栈上）；防御性地，
    /// 若栈上找不到，路径退化为单元素 [entry]。
    fn recordCycle(self: *ClosureBuilder, entry: ModuleId) !void {
        var found: ?usize = null;
        for (self.stack.items, 0..) |frame, i| {
            if (std.meta.eql(frame.id, entry)) {
                found = i;
                break;
            }
        }
        var path: []ModuleId = undefined;
        if (found) |start| {
            const frames = self.stack.items[start..];
            const owned = try self.allocator.alloc(ModuleId, frames.len);
            for (frames, 0..) |frame, i| owned[i] = frame.id;
            path = owned;
        } else {
            path = try self.allocator.dupe(ModuleId, &.{entry});
        }
        errdefer self.allocator.free(path);
        try self.cycles.append(.{
            .cycle_path = path,
            .entry = entry,
        });
    }
};
