//! src/module_loader/cycle.zig — 循环记录与判定（Std 模块化 Phase 3，P3B）。
//!
//! 职责：当懒加载器再次遇到一个 loading 态模块时，产出环记录并按策略
//! 裁决是报错还是放行；并把环写进 flattener 的 ErrorContext，供诊断用。
//! 本文件只做“检测 + 记录 + 裁决 + 诊断”，不读文件、不定位模块、不做
//! 名称解析与语义分析；环合法性的语义规则见 policy.zig（提案 §2）。
//!
//! 复用（不重定义）：
//!   - CycleRecord 取自 Phase 2 的 ClosureBuilder
//!    （src/module_resolver/closure.zig）：`cycle_path: []ModuleId`
//!     按发现顺序排列（首元素即 entry，末尾不重复 entry，首尾相接
//!     成环），`entry: ModuleId` 为环入口。detectCycle 的取栈段算法
//!     与 ClosureBuilder.recordCycle 同款（栈上自 entry 到栈顶的
//!     连续段；栈上找不到时退化为单元素 [entry]）。
//!   - ModuleState / ModuleId / ResolveError 取自
//!     src/module_resolver/types.zig。
//!   - ErrorContext 与 recordErrorOrigin / recordErrorLine /
//!     setErrorDetail 取自 src/flattener/importexpansion.zig。
//!
//! 与现行 flattener 的关系（并存，不替换）：
//!   - flattener（src/flattener/expandimportsinto.zig 约 110 行处）用
//!     active_paths（递归栈）检测环并立即 `return error.ImportCycle`，
//!     是真正展开 @import、报环的地方；本文件不改变它的任何行为。
//!   - 本文件是 Phase 3 懒加载器的环判定件：状态机“在栈上 = loading
//!     态”的判定与 flattener 的 active_paths 判定同义，只是换了一套
//!     状态表述（ModuleState）。懒加载器接管加载状态机后调 checkCycle；
//!     在此之前 flattener 的行为保持不变。
//!
//! 策略（CyclePolicy）：
//!   - .strict（默认）：任何环 → error.ImportCycle，与现行 flattener
//!     行为一致。checkCycle 在返回错误前先把环路径与入口写进
//!     ErrorContext（见 reportCycle），调用方无需另行取记录即可报出
//!     带环路径的诊断。
//!   - .permissive_hook（预留）：环被发现后放行，本次不实现任何放宽
//!     逻辑。放宽的条件（例如仅类型引用构成的环）只写在 policy.zig
//!     的注释里，不落成代码；生产加载器在语义规则落地前不得选用本
//!     策略（见 policy.zig 语义规则节）。
//!
//! 所有权（与 Phase 2 的 arena 规则一致，见 closure.zig 文件头 A8）：
//!   - detectCycle 返回的 CycleRecord.cycle_path 为调用方所有的 owned
//!     切片（本文件用传入 allocator 分配），调用方负责释放——即使
//!     checkCycle 内部调用 detectCycle，也由 checkCycle 自行释放，
//!     不外泄。
//!   - cyclePathString / formatCycleRecord 返回的格式化串同样为 owned，
//!     调用方负责释放。
//!   - ModuleId 本身是值类型（package/path 为借用串，见 types.zig）；
//!     本文件只复制 ModuleId 值，不 dup 其内部串，不拥有它们。
//!   - reportCycle 写入 ErrorContext 的内容受 ErrorContext 固定缓冲
//!     限制（origin 256 字节、detail 128 字节，超长截断——这是
//!     ErrorContext 的既有行为，本文件不改）；完整环路径串可由调用方
//!     用 cyclePathString 另行取去记日志。
//!
//! 诊断坐标约定：环没有唯一的“出错行”——环是一组模块之间的关系而不
//! 是某一行的错误。因此 reportCycle 用 recordErrorOrigin(ctx,
//! entry.path, 0) 记录入口模块路径、行号 0（0 在 importexpansion.zig
//! 里表示“无具体行号”，见 recordErrorLine 的 `origin_line_no != 0`
//! 判断）；detail 写 "ImportCycle: <环路径>"（128 字节截断）。

const std = @import("std");
const types = @import("../module_resolver/types.zig");
const closure = @import("../module_resolver/closure.zig");
const importexpansion = @import("../flattener/importexpansion.zig");

pub const ModuleId = types.ModuleId;
pub const ModuleState = types.ModuleState;
pub const ResolveError = types.ResolveError;
pub const CycleRecord = closure.CycleRecord;
pub const ErrorContext = importexpansion.ErrorContext;
pub const recordErrorOrigin = importexpansion.recordErrorOrigin;
pub const recordErrorLine = importexpansion.recordErrorLine;
pub const setErrorDetail = importexpansion.setErrorDetail;

// ---------------------------------------------------------------------
// 策略
// ---------------------------------------------------------------------

/// 环判定策略（语义规则见 policy.zig；本文件只执行策略，不定策略）。
pub const CyclePolicy = enum {
    /// 任何环都非法：与现行 flattener 行为一致，见 ImportCycle。
    strict,
    /// 预留：后续语义规则放宽时用。本次不实现放宽逻辑，见文件头。
    permissive_hook,

    /// 默认策略：strict。
    pub const default: CyclePolicy = .strict;

    /// 策略名（供日志与诊断用）。
    pub fn name(self: CyclePolicy) []const u8 {
        return switch (self) {
            .strict => "strict",
            .permissive_hook => "permissive_hook",
        };
    }
};

// ---------------------------------------------------------------------
// 加载器状态视图
// ---------------------------------------------------------------------

/// 懒加载器的只读状态视图：checkCycle / detectCycle 只需要这两样东西——
/// 每个模块当前处于哪个 ModuleState，以及当前 DFS 栈（自底向上）。
///
/// 视图不拥有状态表：`states` 指向加载器自己的状态表（与 Phase 2 的
/// ClosureBuilder.states 同形：`std.AutoHashMap(ModuleId, ModuleState)`；
/// AutoHashMap.get 按值接收，可经 *const 指针调用，只读不写）。
/// `stack` 为加载器 DFS 栈的模块 id 投影（自底向上，与 ClosureBuilder
/// 的帧栈顺序一致）；加载器须保证“loading 态当且仅当在栈上”，与
/// ClosureBuilder.recordCycle 的前提相同，否则 detectCycle 对栈上找
/// 不到的 entry 退化为单元素路径 [entry]。
///
/// 适配示例（Phase 3 加载器接线时）：从 ClosureBuilder 取 states 表指针，
/// 再把帧栈的 id 投影成 []ModuleId 传进来；帧栈本身仍由 builder 拥有。
pub const LoaderState = struct {
    states: *const std.AutoHashMap(ModuleId, ModuleState),
    stack: []const ModuleId,

    /// 查询模块当前状态；未登记返回 null（等同 .unloaded，见下）。
    pub fn stateOf(self: *const LoaderState, id: ModuleId) ?ModuleState {
        return self.states.get(id);
    }

    /// 该模块是否正处在“再次遇到即成环”的状态：loading 态当且仅当成环；
    /// 未登记（null）按未开始加载处理，不成环。
    pub fn isLoading(self: *const LoaderState, id: ModuleId) bool {
        return self.stateOf(id) == .loading;
    }
};

/// 一个状态值是否表示“再次遇到即成环”（仅 .loading）。
/// 供不需要整张状态表的调用方复用判定口径。
pub fn isCycleState(state: ?ModuleState) bool {
    return state == .loading;
}

// ---------------------------------------------------------------------
// 检测与裁决
// ---------------------------------------------------------------------

/// 纯检测：`id` 再次被遇到时是否构成环。
///
///   - stateOf(id) 不是 .loading（未登记 / unloaded / loaded / analyzed）
///     → 返回 null：不是环。已 loaded/analyzed 的重遇由调用方的去重逻辑
///     处理（与 flattener 的 seen_paths 同义），不属于本函数。
///   - 是 .loading → 返回 owned 的 CycleRecord（cycle_path 为栈上自 entry
///     到栈顶的连续段；栈上找不到 entry 时退化为 [entry]，与
///     ClosureBuilder.recordCycle 一致）。调用方负责释放
///     `record.cycle_path`（allocator.free）。
///
/// 本函数不应用策略、不报错、不写 ErrorContext；只回答“有没有环、环
/// 是什么”。策略由 checkCycle 应用；permissive_hook 下需要记录的调用
/// 方直接调本函数。
pub fn detectCycle(
    allocator: std.mem.Allocator,
    loader_state: *const LoaderState,
    id: ModuleId,
) !?CycleRecord {
    if (!loader_state.isLoading(id)) return null;

    var start: ?usize = null;
    for (loader_state.stack, 0..) |stack_id, i| {
        if (stack_id.eql(id)) {
            start = i;
            break;
        }
    }
    var path: []ModuleId = undefined;
    if (start) |s| {
        const segment = loader_state.stack[s..];
        path = try allocator.alloc(ModuleId, segment.len);
        for (segment, 0..) |stack_id, i| path[i] = stack_id;
    } else {
        path = try allocator.dupe(ModuleId, &.{id});
    }
    errdefer allocator.free(path);
    return CycleRecord{
        .cycle_path = path,
        .entry = id,
    };
}

/// 检测 + 按策略裁决（任务指定的主入口）。
///
///   - 无环 → 直接返回（void），不碰 error_ctx。
///   - 有环 + .strict → 先调 reportCycle 把环路径与入口写进 error_ctx
///    （error_ctx 为 null 时跳过诊断写入，但仍报错），再返回
///     error.ImportCycle。记录本身由本函数在返回前释放，不外泄。
///   - 有环 + .permissive_hook → 放行，返回 void；不写 error_ctx（非错
///     误路径不得污染错误上下文），记录直接丢弃。注意：放行不是“环合
///     法”的语义判断——本次不实现任何放宽逻辑（见文件头与 policy.zig），
///     只是把“发现了环”这一事实交还给调用方继续加载；需要记录的调用
///     方应直接调 detectCycle。
///
/// 参数顺序遵循仓内约定（allocator 在前，见 parseImportSpec）：调用方
/// 传加载器的 LoaderState 视图与被再次遇到的模块 id。
pub fn checkCycle(
    allocator: std.mem.Allocator,
    policy: CyclePolicy,
    loader_state: *const LoaderState,
    id: ModuleId,
    error_ctx: ?*ErrorContext,
) ResolveError!void {
    const record = try detectCycle(allocator, loader_state, id) orelse return;
    defer allocator.free(record.cycle_path);
    switch (policy) {
        .strict => {
            try reportCycle(allocator, error_ctx, &record);
            return error.ImportCycle;
        },
        .permissive_hook => {
            return;
        },
    }
}

// ---------------------------------------------------------------------
// 格式化
// ---------------------------------------------------------------------

/// 模块 id 的可读写法：直接取 ModuleId.path。
/// path 本身就是含包名前缀的完整规范路径（如 `sa_std/io/print.sa`，
/// 见 types.zig），不再拼 package，否则会写成 `sa_std/sa_std/...`。
fn displayId(id: ModuleId) []const u8 {
    return id.path;
}

/// 环路径 → 可读字符串（供诊断与日志用）。
///
/// 形如 `sa_std/a.sa -> sa_std/b.sa -> sa_std/a.sa`：用 " -> " 连接
/// cycle_path 各元素，并在末尾重复首元素以闭合环路——CycleRecord 本身
/// 的 cycle_path 末尾不重复 entry（首尾相接是约定），格式化时补上，
/// 读起来才是一条完整的环。
/// 单元素路径（自导入或栈上找不到 entry 的退化记录）格式化为
/// `A -> A`，同样表示自环。
/// 空路径返回空串（防御性分支；合法的 CycleRecord 路径恒非空）。
/// 返回 owned 字符串，调用方负责释放。
pub fn cyclePathString(
    allocator: std.mem.Allocator,
    cycle_path: []const ModuleId,
) ![]u8 {
    var out = std.ArrayList(u8).init(allocator);
    errdefer out.deinit();
    for (cycle_path, 0..) |id, i| {
        if (i != 0) try out.appendSlice(" -> ");
        try out.appendSlice(displayId(id));
    }
    if (cycle_path.len > 0) {
        try out.appendSlice(" -> ");
        try out.appendSlice(displayId(cycle_path[0]));
    }
    return out.toOwnedSlice();
}

/// cyclePathString 的记录版：直接取 record.cycle_path 格式化。
pub fn formatCycleRecord(
    allocator: std.mem.Allocator,
    record: *const CycleRecord,
) ![]u8 {
    return cyclePathString(allocator, record.cycle_path);
}

// ---------------------------------------------------------------------
// 诊断
// ---------------------------------------------------------------------

/// 把一条环记录写进 flattener 的 ErrorContext（ImportCycle 诊断）。
///
///   - origin：record.entry 的规范路径（recordErrorOrigin），行号 0
///     表示“无具体行号”（环是模块间关系，不是某一行的错误，见文件头）。
///   - detail：`"ImportCycle: <cyclePathString>"`（setErrorDetail；
///     受 ErrorContext.detail_buf 128 字节限制，超长截断——完整串请
///     调用方用 cyclePathString 另行记日志）。
///
/// error_ctx 为 null 时什么都不做（与 recordErrorOrigin / setErrorDetail
/// 的 null 语义一致）。格式化失败只可能是 OutOfMemory。
pub fn reportCycle(
    allocator: std.mem.Allocator,
    error_ctx: ?*ErrorContext,
    record: *const CycleRecord,
) !void {
    const ctx = error_ctx orelse return;
    const path_str = try cyclePathString(allocator, record.cycle_path);
    defer allocator.free(path_str);
    const detail = try std.fmt.allocPrint(allocator, "ImportCycle: {s}", .{path_str});
    defer allocator.free(detail);
    recordErrorOrigin(ctx, record.entry.path, 0);
    setErrorDetail(ctx, detail);
}

/// 已有 SourceLine 时的诊断入口：行号优先取该行的 origin 坐标，环路
/// 径仍写进 detail。调用方在导入行本身有 SourceLine 可用时用本函数，
/// 否则用 reportCycle（行号 0）。
/// 导入行的 SourceLine 形态见 importexpansion.zig 的 SourceLine
/// （origin_path / origin_line_no）；origin_line_no 为 0 时回退到
/// recordErrorLine 的 fallback 语义（见 recordErrorLine）。
pub fn reportCycleAtLine(
    allocator: std.mem.Allocator,
    error_ctx: ?*ErrorContext,
    record: *const CycleRecord,
    line: importexpansion.SourceLine,
    fallback_line: u32,
) !void {
    const ctx = error_ctx orelse return;
    const path_str = try cyclePathString(allocator, record.cycle_path);
    defer allocator.free(path_str);
    const detail = try std.fmt.allocPrint(allocator, "ImportCycle: {s}", .{path_str});
    defer allocator.free(detail);
    recordErrorLine(ctx, line, fallback_line);
    setErrorDetail(ctx, detail);
}
