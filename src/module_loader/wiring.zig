//! Flattener ↔ module-loader 接线（Std 模块化 Phase 3，P3C）。
//!
//! 薄适配层：把 flattener 原有的两张 `StringHashMap(void)`（active_paths /
//! seen_paths）换成一张以 `ModuleId` 为键、`ModuleState` 为值的模块状态表
//! `ModuleTable`，供 `expandImportsInto` 的表核心与 `ImportExpansion` 持有。
//!
//! 过渡期约定（合并时与 P3A 的 LazyLoader 对齐后可收紧）：
//!   - 去重与循环判定仍以两张 map 为准：loading 态重遇 → `error.ImportCycle`，
//!     loaded/analyzed 态重遇 → 跳过。`states` 表是覆盖层，只记录 flattener
//!     自己经手的状态推进（unloaded → loading → loaded），不参与判定。
//!   - 两张 map 仍保留在表内，是向尚未迁移的调用方
//!    （`injectImportedFile`、`appendExpandedImportCacheHit`，均直接读写两张
//!     map）的投影；它们绕过本表直接改 map 时 `states` 表可能滞后——
//!     `checkImport` 只读 map，所以判定结果不受滞后影响。
//!   - `states` 的键借用与 map 键相同的路径切片（调用方 `owned_paths` 拥有），
//!     本表不拥有键字符串，`deinit` 只释放三张 map 本身，不释放键。
//!   - flattener 侧的模块身份一律为平文件身份：`package` 为 `""`，`path` 为
//!     规范 entry_path。包限定的身份（`sa_std/...`）由 resolver / locator
//!     的 `ModuleInfo.id` 建立（`idForLocated`），加载器接管解析后再统一。
//!   - 本文件不依赖 P3A 的 `src/module_loader/loader.zig`（并行开发中）：
//!     合并时协调 agent 再把 `ModuleTable` 与 LazyLoader 的状态机对齐。

const std = @import("std");
const types = @import("../module_resolver/types.zig");

pub const ModuleId = types.ModuleId;
pub const ModuleInfo = types.ModuleInfo;
pub const ModuleState = types.ModuleState;

/// `checkImport` 的判定结果：fresh 可展开，loading 是环，seen 跳过。
pub const ImportCheck = enum {
    fresh,
    loading,
    seen,
};

/// 模块状态表：两张旧去重 map + 一张 `ModuleId → ModuleState` 覆盖层。
pub const ModuleTable = struct {
    allocator: std.mem.Allocator,
    /// loading 态的规范路径集合（旧 active_paths 的投影）。
    active_paths: std.StringHashMap(void),
    /// loaded/analyzed 态的规范路径集合（旧 seen_paths 的投影）。
    seen_paths: std.StringHashMap(void),
    /// 以 ModuleId 为键的状态机覆盖层（见文件头过渡期约定）。
    states: std.HashMap(ModuleId, ModuleState, ModuleId.Context, 80),

    pub fn init(allocator: std.mem.Allocator) ModuleTable {
        return .{
            .allocator = allocator,
            .active_paths = std.StringHashMap(void).init(allocator),
            .seen_paths = std.StringHashMap(void).init(allocator),
            .states = std.HashMap(ModuleId, ModuleState, ModuleId.Context, 80).init(allocator),
        };
    }

    pub fn deinit(self: *ModuleTable) void {
        self.states.deinit();
        self.active_paths.deinit();
        self.seen_paths.deinit();
        self.* = undefined;
    }

    /// 平文件导入的模块身份：无包，path 即规范 entry_path。
    pub fn idForEntryPath(entry_path: []const u8) ModuleId {
        return .{ .package = "", .path = entry_path };
    }

    /// 定位器已解析模块的身份：直接取 `ModuleInfo.id`。
    pub fn idForLocated(info: ModuleInfo) ModuleId {
        return info.id;
    }

    /// 去重与循环判定（以两张 map 为准；见文件头过渡期约定）。
    /// loading 态重遇 → `.loading`（调用方报 `error.ImportCycle`），
    /// loaded/analyzed 态重遇 → `.seen`（调用方跳过），否则 `.fresh`。
    pub fn checkImport(self: *const ModuleTable, entry_path: []const u8) ImportCheck {
        if (self.active_paths.contains(entry_path)) return .loading;
        if (self.seen_paths.contains(entry_path)) return .seen;
        return .fresh;
    }

    /// 开始展开一个模块：按原顺序先记 seen 再记 active，状态记为 loading。
    /// 顺序与旧代码一致（旧代码先 `seen_paths.put` 再 `active_paths.put`）。
    pub fn markLoading(self: *ModuleTable, id: ModuleId, entry_path: []const u8) !void {
        try self.seen_paths.put(entry_path, {});
        try self.active_paths.put(entry_path, {});
        try self.states.put(id, .loading);
    }

    /// 完成一个模块的展开：离 active，留在 seen，状态推进为 loaded。
    /// `states.put` 的失败（仅 OOM）静默忽略：判定以两张 map 为准，
    /// 覆盖层滞后不影响去重与循环语义。
    pub fn finishLoading(self: *ModuleTable, id: ModuleId, entry_path: []const u8) void {
        _ = self.active_paths.remove(entry_path);
        self.states.put(id, .loaded) catch {};
    }

    /// 覆盖层直查：返回 flattener 自己记录的状态；经旧 map 路径
    /// （injectImportedFile 等）展开的模块可能查不到，返回 null。
    pub fn stateOf(self: *const ModuleTable, id: ModuleId) ?ModuleState {
        return self.states.get(id);
    }

    /// 供未来加载器推进状态机：loaded → analyzed。失败静默忽略，理由同上。
    pub fn markAnalyzed(self: *ModuleTable, id: ModuleId) void {
        self.states.put(id, .analyzed) catch {};
    }

    /// 把调用方的一对旧 map 临时装进本表（只交换 map 头，O(1)），供尚未迁移
    /// 的调用方（`expandImportsInto` 旧签名适配器）复用表核心。
    /// 调用方必须在返回前调 `restoreMaps` 把它们换回去，再 `deinit` 本表；
    /// adopt 与 restore 之间不得 `deinit` 本表（会释放调用方的 map）。
    pub fn adoptMaps(
        self: *ModuleTable,
        active_paths: *std.StringHashMap(void),
        seen_paths: *std.StringHashMap(void),
    ) AdoptedMaps {
        const saved = AdoptedMaps{ .active = self.active_paths, .seen = self.seen_paths };
        self.active_paths = active_paths.*;
        self.seen_paths = seen_paths.*;
        return saved;
    }

    /// `adoptMaps` 的逆操作：把调用方的两张 map（可能已被表核心改动过）
    /// 换回调用方，并把本表自己的空 map 头换回来。
    pub fn restoreMaps(
        self: *ModuleTable,
        active_paths: *std.StringHashMap(void),
        seen_paths: *std.StringHashMap(void),
        saved: AdoptedMaps,
    ) void {
        active_paths.* = self.active_paths;
        seen_paths.* = self.seen_paths;
        self.active_paths = saved.active;
        self.seen_paths = saved.seen;
    }
};

/// `adoptMaps` / `restoreMaps` 共用的暂存：调用方两张旧 map 的原 map 头。
pub const AdoptedMaps = struct {
    active: std.StringHashMap(void),
    seen: std.StringHashMap(void),
};
