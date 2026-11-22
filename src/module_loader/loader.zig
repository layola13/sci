//! 懒加载器核心 —— SA 标准库模块化 Phase 3（LazyLoader，P3A）。
//!
//! 职责：按需加载模块并推进四态状态机
//!   unloaded → loading → loaded → analyzed（提案 §2）。
//!
//! 加载驱动（本文件）：
//!   - `loadRoot(spec)`：定位入口 import，压入工作表，排空工作表直至闭包；
//!   - 工作表循环（`drainWorklist`）：显式栈工作表（与 Phase 2 的
//!     ClosureBuilder 同构）：读文件（sio）→ 抽 @import 行 → 逐条
//!     parseImportSpec → 定位 → 发边 → 未见过的目标压栈；已在 loading 态的
//!     目标不递归，只记一条 CycleRecord；
//!   - shim 跟随：is_shim 的模块只跟随其第 1 行 @import 转发（Phase 1 契约：
//!     shim 恰好 1 行转发）；去重按定位后的规范 ModuleId 做；
//!   - 导入语义（用户已定第三种，提案 §7）：符号级与模块级都支持，底层统一
//!     落成 SymbolEdge，loader 维护 edges 列表供 Phase 4 消费。
//!
//! 不属于本文件：parse / type-check / analyze 的真正实现。它们以三个钩子槽位
//! 留出（见“钩子”一节）：loader 只定义调用点与顺序——模块到达 loaded 态时
//! 调 parse 钩子，到达 analyzed 态时先调 type-check 钩子再调 analyze 钩子。
//! 钩子的真正实现是后续 Phase / 现有解析器的事。
//!
//! 状态机不变量：
//!   - loading ⟺ 在工作表栈上。pushFrame 先读文件、抽 import、帧入栈成功后
//!     才置 loading；帧完成出栈时才置 loaded。loadRoot 对 loading 态的根直接
//!     返回 id（外层排空会完成它），不重复压栈。
//!   - 非法迁移（unloaded → analyzed、analyzed → loading、loading → analyzed
//!     等）返回 LoaderError.InvalidStateTransition；对表里不存在的模块做迁移
//!     返回 error.ModuleNotFound。
//!   - 钩子失败不回滚迁移：markLoaded / markAnalyzed 先置新状态再调钩子，
//!     钩子报错时状态保持新状态、错误向上传。
//!
//! 所有权 / arena 规则（与 Phase 2 的 A8 一致）：
//!   - 调用方传入一个 arena 分配器（`allocator`），loader 用它分配一切：
//!     定位产物串（ModuleId.path / fs_path，定位器分配）、源码、import 串、
//!     边符号串、环路径。loader 不逐个追踪释放——deinit 只释放容器本身的
//!     表/缓冲，字符串由调用方统一释放 arena。
//!   - 例外：工作表循环内每轮的 ImportSpec 在迭代结束即 deinit（此时定位与
//!     发边已用完它，且不借用它的串；与 ClosureBuilder.build 同款）。
//!   - 钩子必须不重入：parse / type-check / analyze 钩子内不得调 loadRoot /
//!     drainWorklist（无重入保护）；钩子只读 loader 状态或登记自己的产物。
//!
//! 出错后的状态：排空工作表途中若某步失败（如子 import 定位失败、文件读
//! 失败），loader 停在局部完成状态（部分模块仍为 loading 且帧在栈上）。
//! 此时实例视为脏状态：调用方应丢弃本 loader（arena 统一释放）后重建，
//! 不得继续用它加载（重试语义是后续 Phase 的事）。
//!
//! 与现有机制的关系：
//!   - 不替换 flattener 的 expandimportsinto.zig：flattener 仍是真正展开
//!     @import、报 error.ImportCycle 的地方；本 loader 只做“按需加载、记录
//!     结构”，环只记 CycleRecord 不报错，环是否合法由语义规则定（提案 §2）。
//!   - 相对路径 import（如 `../sync/rwlock.sal`）仍是已知缺口：parseImportSpec
//!     与 Locator.locate 没有基准目录参数，此类串在排空时报 InvalidImportSpec
//!     / ModuleNotFound（与 Phase 2 闭包构建器一致）；基准目录解析是后续
//!     Phase 的事。本 loader 不私自拼基准目录。
//!   - `.sai` / `.sal` 伴生文件不作为加载节点（与 ClosureBuilder 一致）：只
//!     扫描定位到的模块文件本身的 @import 行。
//!   - 本文件不接 build：只新增 src/module_loader/ 下文件，不改任何现有文件，
//!     构建接线（build.zig 注册）是后续 Phase / 协调方的事；验证只跑
//!     `zig ast-check` 与 @import 悬空核对。

const std = @import("std");
const sio = @import("sio");
const types = @import("../module_resolver/types.zig");
const locator_mod = @import("../module_resolver/locator.zig");
const spec_mod = @import("../module_resolver/spec.zig");
const closure_mod = @import("../module_resolver/closure.zig");

// Phase 2 类型（复用，不重定义）。
pub const ModuleState = types.ModuleState;
pub const ImportKind = types.ImportKind;
pub const ResolveError = types.ResolveError;
pub const ImportSpec = types.ImportSpec;
pub const ModuleId = types.ModuleId;
pub const ModuleInfo = types.ModuleInfo;
pub const SymbolEdge = types.SymbolEdge;
pub const Locator = locator_mod.Locator;
// CycleRecord 复用 closure.zig 的形状（loader 只维护自己的 cycles 列表）。
pub const CycleRecord = closure_mod.CycleRecord;

/// loader 专用的错误集：Phase 2 的 ResolveError 全集 + 本文件新增的变体。
/// 不改 Phase 2 的 ResolveError（任务硬约束）。
pub const LoaderError = ResolveError || error{
    /// 非法状态迁移，如 unloaded → analyzed、analyzed → loading、
    /// loading → analyzed。
    InvalidStateTransition,
    /// shim 文件里没有 @import 转发行（shim 契约：恰好 1 行 @import 转发）。
    MalformedShim,
    /// 定位成功后文件读不出来（定位与读取之间文件消失、权限不足、超限等）。
    /// OutOfMemory 不归入此类，仍按 error.OutOfMemory 返回。
    ReadFailed,
};

/// 模块表里的一个条目：定位记录 + 权威状态 + 已读源码。
pub const ModuleEntry = struct {
    /// 定位器给出的模块记录（id / fs_path / kind / is_shim）。
    /// 其中的 state 字段与本 entry 的 state 保持同步（见 setState）。
    info: ModuleInfo,
    /// 本加载器的权威状态；stateOf() 读的就是它。
    state: ModuleState,
    /// 已读入的源码（arena 所有）；尚未读取时为 null。
    source: ?[]const u8 = null,
};

// ---------------------------------------------------------------------
// 钩子
// ---------------------------------------------------------------------

/// 解析钩子：在模块到达 loaded 态时调用。`source` 为 loader 读到的模块
/// 源码；钩子只借用，不拥有、不释放（arena 所有）。模块未经 loader 读取
/// （如外部直接 markLoading → markLoaded）时 source 为空串。
/// 默认实现：空操作。真正实现由后续 Phase / 现有解析器接线。
pub const ParseHook = *const fn (*LazyLoader, ModuleId, []const u8) LoaderError!void;
/// 类型检查钩子：在模块到达 analyzed 态时调用，顺序在 analyze 钩子之前。
/// 默认实现：空操作。
pub const TypeCheckHook = *const fn (*LazyLoader, ModuleId) LoaderError!void;
/// 分析钩子：在模块到达 analyzed 态时调用，顺序在 type-check 钩子之后。
/// 默认实现：空操作。
pub const AnalyzeHook = *const fn (*LazyLoader, ModuleId) LoaderError!void;

/// 默认 parse 钩子：空实现。
pub fn noopParseHook(_: *LazyLoader, _: ModuleId, _: []const u8) LoaderError!void {}
/// 默认 type-check 钩子：空实现。
pub fn noopTypeCheckHook(_: *LazyLoader, _: ModuleId) LoaderError!void {}
/// 默认 analyze 钩子：空实现。
pub fn noopAnalyzeHook(_: *LazyLoader, _: ModuleId) LoaderError!void {}

/// 工作表栈帧。source 与 imports 均为 arena 所有，帧出栈时不释放
/// （与 ClosureBuilder 不同：本 loader 按 arena 规则不逐个追踪释放）。
const Frame = struct {
    id: ModuleId,
    source: []u8,
    imports: [][]const u8,
    next: usize,
};

pub const LazyLoader = struct {
    /// 调用方传入的 arena 分配器（见文件头所有权规则）；loader 不拥有它。
    allocator: std.mem.Allocator,
    /// 按值持有的定位器（与 ClosureBuilder 一致；调用方拥有定位器本体）。
    locator: Locator,
    /// 模块表：规范 ModuleId → ModuleEntry。去重按规范路径做
    /// （ModuleId.Context 按包名 + 路径内容哈希 / 判等）。
    modules: std.HashMap(ModuleId, ModuleEntry, ModuleId.Context, std.hash_map.default_max_load_percentage),
    /// 工作表：显式栈（帧）。loading ⟺ 在栈上（见文件头状态机不变量）。
    worklist: std.array_list.Managed(Frame),
    /// 依赖边：符号级与模块级 import 统一落成 SymbolEdge，供 Phase 4 消费。
    /// 不去重（与 ClosureBuilder 一致；去重是 Phase 4 依赖图的事）。
    edges: std.array_list.Managed(SymbolEdge),
    /// 发现的导入环：只记录，不报错。
    cycles: std.array_list.Managed(CycleRecord),
    /// 加载完成顺序（模块到达 loaded 态的顺序；依赖先于使用方，环内成员相邻）。
    order: std.array_list.Managed(ModuleId),
    /// 三个钩子槽位：调用方直接赋值替换（如 `loader.parse_hook = myParse;`），
    /// 不赋值即默认空实现。
    parse_hook: ParseHook = noopParseHook,
    type_check_hook: TypeCheckHook = noopTypeCheckHook,
    analyze_hook: AnalyzeHook = noopAnalyzeHook,

    /// 单个模块源码上限（64 MiB；与 ClosureBuilder 相同，sa_std 内最大文件远小于此值）。
    const max_source_bytes: usize = 64 * 1024 * 1024;

    pub fn init(allocator: std.mem.Allocator, locator: Locator) LazyLoader {
        return .{
            .allocator = allocator,
            .locator = locator,
            .modules = std.HashMap(ModuleId, ModuleEntry, ModuleId.Context, std.hash_map.default_max_load_percentage).init(allocator),
            .worklist = std.array_list.Managed(Frame).init(allocator),
            .edges = std.array_list.Managed(SymbolEdge).init(allocator),
            .cycles = std.array_list.Managed(CycleRecord).init(allocator),
            .order = std.array_list.Managed(ModuleId).init(allocator),
        };
    }

    pub fn deinit(self: *LazyLoader) void {
        // 只释放容器本身的表 / 缓冲；模块字符串、源码、边符号串、环路径
        // 均为 arena 所有，由调用方统一释放（见文件头所有权规则）。
        // 注意：不释放 locator（调用方拥有）。
        self.modules.deinit();
        self.worklist.deinit();
        self.edges.deinit();
        self.cycles.deinit();
        self.order.deinit();
    }

    /// 模块表里的条目数。
    pub fn count(self: *const LazyLoader) usize {
        return self.modules.count();
    }

    /// 查询模块当前状态；未登记返回 null。
    pub fn stateOf(self: *const LazyLoader, id: ModuleId) ?ModuleState {
        const entry = self.modules.get(id) orelse return null;
        return entry.state;
    }

    /// 查询模块表条目（值拷贝）；未登记返回 null。
    pub fn entryOf(self: *const LazyLoader, id: ModuleId) ?ModuleEntry {
        return self.modules.get(id);
    }

    /// 查询已读入的模块源码；未登记或尚未读取返回 null。
    pub fn sourceOf(self: *const LazyLoader, id: ModuleId) ?[]const u8 {
        const entry = self.modules.get(id) orelse return null;
        return entry.source;
    }

    /// 登记一个已定位的模块（幂等）：已在表里则无操作（先登记的为准）；
    /// 否则以 .unloaded 登记，不读文件、不压栈。
    pub fn register(self: *LazyLoader, info: ModuleInfo) LoaderError!void {
        if (self.modules.contains(info.id)) return;
        try self.modules.put(info.id, .{ .info = info, .state = .unloaded });
    }

    /// 登记一个入口 import。只做定位与登记，不读文件、不展开依赖；
    /// 真正的工作在 loadRoot / drainWorklist 里。重复登记同一入口是无操作。
    pub fn addRoot(self: *LazyLoader, spec: ImportSpec) LoaderError!void {
        const info = try self.locator.locate(spec);
        try self.register(info);
    }

    /// 写状态（entry.state 与 entry.info.state 同步写）。调用方保证
    /// 模块已登记，否则报 ModuleNotFound。
    fn setState(self: *LazyLoader, id: ModuleId, state: ModuleState) LoaderError!void {
        const entry = self.modules.getPtr(id) orelse return error.ModuleNotFound;
        entry.state = state;
        entry.info.state = state;
    }

    /// unloaded → loading。只允许该迁移；表里无此模块报 ModuleNotFound，
    /// 状态不对报 InvalidStateTransition。
    pub fn markLoading(self: *LazyLoader, id: ModuleId) LoaderError!void {
        const current = self.stateOf(id) orelse return error.ModuleNotFound;
        if (current != .unloaded) return error.InvalidStateTransition;
        try self.setState(id, .loading);
    }

    /// loading → loaded，并调 parse 钩子（见文件头：先置状态再调钩子，
    /// 钩子失败不回滚）。只允许该迁移；状态不对报 InvalidStateTransition。
    pub fn markLoaded(self: *LazyLoader, id: ModuleId) LoaderError!void {
        const current = self.stateOf(id) orelse return error.ModuleNotFound;
        if (current != .loading) return error.InvalidStateTransition;
        const entry = self.modules.get(id).?; // 刚查过，一定存在
        const source = entry.source orelse "";
        try self.setState(id, .loaded);
        try self.parse_hook(self, id, source);
    }

    /// loaded → analyzed，并依次调 type-check 钩子与 analyze 钩子
    /// （见文件头：先置状态再调钩子，钩子失败不回滚）。
    /// 只允许该迁移；状态不对报 InvalidStateTransition。
    pub fn markAnalyzed(self: *LazyLoader, id: ModuleId) LoaderError!void {
        const current = self.stateOf(id) orelse return error.ModuleNotFound;
        if (current != .loaded) return error.InvalidStateTransition;
        try self.setState(id, .analyzed);
        try self.type_check_hook(self, id);
        try self.analyze_hook(self, id);
    }

    /// 加载一个入口 import 并排空工作表直至闭包，返回入口模块的规范 id。
    /// 已 loaded / analyzed 的根直接返回 id，不重复加载；正在 loading 的根
    /// 直接返回 id（它已在工作表上，外层排空会完成它）。
    pub fn loadRoot(self: *LazyLoader, spec: ImportSpec) LoaderError!ModuleId {
        const info = try self.locator.locate(spec);
        const id = info.id;
        switch (self.stateOf(id) orelse .unloaded) {
            .loaded, .analyzed => return id,
            .loading => return id,
            .unloaded => {},
        }
        try self.register(info);
        try self.pushFrame(info);
        try self.drainWorklist();
        return id;
    }

    /// 把已加载（loaded 态）的全部模块按 order 顺序逐一推进到 analyzed 态
    /// （依次调 type-check 与 analyze 钩子）。已 analyzed 的跳过。
    /// 尚未加载的模块不在 order 里，不处理——先调 loadRoot。
    pub fn analyzeAll(self: *LazyLoader) LoaderError!void {
        const n = self.order.items.len;
        for (self.order.items[0..n]) |id| {
            if (self.stateOf(id) == .loaded) {
                try self.markAnalyzed(id);
            }
        }
    }

    /// 排空工作表：沿 @import 边遍历直至闭包。
    ///
    /// 每个模块的状态流转：unloaded → loading（读文件、抽 @import 行）→
    /// loaded（调 parse 钩子，见 markLoaded）。analyzed 不在此推进，
    /// 由 analyzeAll / markAnalyzed 单独驱动。
    /// 已在 loading 态的目标再次被发现时不递归，记一条 CycleRecord；
    /// 已 loaded / analyzed 的目标直接跳过（边照常发，见 emitEdge）。
    pub fn drainWorklist(self: *LazyLoader) LoaderError!void {
        while (self.worklist.items.len > 0) {
            const top = self.worklist.items.len - 1;
            // 按值拷贝帧头（不持指针跨 append 调用：压栈可能重分配 worklist 缓冲）。
            const frame = self.worklist.items[top];
            if (frame.next >= frame.imports.len) {
                // 该模块的全部 import 已处理：loading → loaded（调 parse 钩子）。
                try self.markLoaded(frame.id);
                try self.order.append(frame.id);
                _ = self.worklist.pop();
                continue;
            }
            // 推进游标（按索引写回），再取当前这条 import 行。
            self.worklist.items[top].next += 1;
            const raw = frame.imports[frame.next];
            const importer = frame.id;
            var spec = try spec_mod.parseImportSpec(self.allocator, raw);
            // spec 的 raw/path/version 为 owned；locate / emitEdge 不借用
            // 它们（ModuleId.package 为字面量、id.path 为新分配串、边符号串
            // 由 emitEdge 自行 dupe），本轮迭代结束即释放。
            defer spec.deinit(self.allocator);
            const info = try self.locator.locate(spec);
            try self.emitEdge(importer, spec, info);
            switch (self.stateOf(info.id) orelse .unloaded) {
                .loading => try self.recordCycle(info.id),
                .unloaded => try self.pushFrame(info),
                .loaded, .analyzed => {},
            }
        }
    }

    /// 读入一个模块并压入工作表栈：unloaded → loading。
    /// 只在目标确为 unloaded 时调用；其余状态由 drainWorklist 分流。
    /// 帧入栈成功后才置 loading：入栈失败时状态仍为 unloaded，不留半截状态。
    fn pushFrame(self: *LazyLoader, info: ModuleInfo) LoaderError!void {
        try self.register(info);
        const current = self.stateOf(info.id) orelse .unloaded;
        if (current != .unloaded) return;
        const source = sio.cwd().readFileAlloc(self.allocator, info.fs_path, max_source_bytes) catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
            else => return error.ReadFailed,
        };
        var imports = spec_mod.extractImportStrings(self.allocator, source) catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
            else => return error.ReadFailed,
        };
        if (info.is_shim) {
            // shim 契约：恰好 1 行 @import 转发。无转发行是 malformed；
            // 多于 1 行时只跟随第一行（其余忽略）；跟随本身走工作表循环
            // 的正常路径（解析 → 定位 → 发边 → 规范目标压栈），去重按
            // 定位后的规范 ModuleId 做。
            if (imports.len == 0) return error.MalformedShim;
            imports = imports[0..1];
        }
        try self.worklist.append(.{
            .id = info.id,
            .source = source,
            .imports = imports,
            .next = 0,
        });
        try self.setState(info.id, .loading);
        if (self.modules.getPtr(info.id)) |entry| entry.source = source;
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
    /// 去重是 Phase 4 依赖图的事）。与 ClosureBuilder.emitEdge 同口径：
    ///   - 符号级（.symbol）：symbol = 导入的符号名（loader 复制持有，arena 所有）；
    ///   - 模块级（.module）：symbol = null，to = 该域 prelude 的 ModuleId；
    ///     无 prelude 的域（如 string/）locatePrelude 报 ModuleNotFound，to 保
    ///     持为域模块本身。
    fn emitEdge(self: *LazyLoader, importer: ModuleId, spec: ImportSpec, info: ModuleInfo) LoaderError!void {
        var to = info.id;
        var symbol: ?[]const u8 = null;
        switch (spec.kind) {
            .symbol => {
                if (spec.symbol) |name| {
                    symbol = try self.allocator.dupe(u8, name);
                }
            },
            .module => {
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

    /// 记录一条环：cycle_path 为工作表栈上从 entry 到栈顶的连续段（按发现顺序），
    /// entry 为环入口。栈上必有 entry（loading 态当且仅当在栈上）；防御性地，
    /// 若栈上找不到，路径退化为单元素 [entry]。
    fn recordCycle(self: *LazyLoader, entry: ModuleId) LoaderError!void {
        var found: ?usize = null;
        for (self.worklist.items, 0..) |frame, i| {
            if (frame.id.eql(entry)) {
                found = i;
                break;
            }
        }
        var path: []ModuleId = undefined;
        if (found) |start| {
            const frames = self.worklist.items[start..];
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
