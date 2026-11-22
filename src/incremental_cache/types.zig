//! 增量编译缓存核心类型 —— SA 标准库模块化 Phase 7（sa-incremental-cache，P7A）。
//!
//! 职责：只定义缓存键与核心类型，不做任何磁盘 I/O、不读不写缓存文件、
//! 不建缓存目录、不做失效扫描（存储与失效策略是后续 P7B/P7C 的事）。
//! 本文件只新增，不改任何既有文件；构建接线（build.zig 注册）是后续
//! Phase / 协调方的事；验证只跑 `zig ast-check` 与 @import 悬空核对。
//!
//! 背景教训（缓存键为什么必须含这四个分量，缺一不可）：
//!   - 2026-11-20，`~/.cache/sa/frontend` 的缓存键只有源码哈希，
//!     不含编译器版本与插件版本：工具链更新后缓存仍命中旧产物，
//!     读到的是过期编译结果，错得静默、无报错。教训：源码相同
//!     不等于产物相同，编译器 / 插件变了就必须换键。
//!   - d31b99b 把优化级别折进 `.sa_cache` 的构建键：同一源码在
//!     不同优化级别下产物不同（opt 0 调试构建与 release-fast 构建
//!     不是同一份产物），优化级别也必须进键，否则 debug 产物会
//!     被当成 release 产物命中。
//!   因此 CacheKey 同时含：模块内容哈希 + 编译器版本 + 插件版本 +
//!   优化级别。任一分量变了，eql 即不等、hash 即不同，旧条目一律
//!   失效（见 CacheEntry.isStale）。格式本身另有版本保护：
//!   CacheFormatVersion 变了，旧缓存文件一律失效（见 CacheError
//!   .VersionMismatch），不做迁移、不做兼容读取。
//!
//! 复用（不重定义）：ModuleId / ModuleState 复用
//! `src/module_resolver/types.zig`（Phase 2）；ModuleState 的四态
//! （unloaded → loading → loaded → analyzed）与 Phase 3 懒加载器
//! （`src/module_loader/loader.zig`）的状态机是同一台机器，缓存条目
//! 只记录模块到达的状态，不推进、不判定迁移合法性。
//!
//! 所有权 / 借用规则（与 Phase 2 的 A8、Phase 3 的 loader、Phase 4
//! 的依赖图一致）：
//!   - 本文件所有类型只借用字符串，不拥有。CacheKey.compiler_version
//!     / plugin_version、CacheEntry.artifact_path 均为调用方 arena
//!     （或短命分配器）里的借用串；本文件不分配、不释放它们。
//!   - 例外：CacheStats.summarize 返回 owned 文本（调用方释放），
//!     与 Phase 6 `summarizeDce` 同款口径（纯文本一行，无 JSON 输出）。
//!
//! Phase 6 RESULT.md §6 待裁决项（只记，不改）：本文件不裁决、不
//! 落任何一项——结构化（JSON）报告输出（Phase 6 §6 第 7 项，未决）
//! 不在本文件做，summarize 只产纯文本；其余 Phase 6/5/4/3/2/1 的
//! 待裁决项原样登记在 RESULT.md / MANIFEST 里，本文件不动。
//!
//! 不属于本文件：缓存文件的读写、缓存目录管理、失效扫描与淘汰
//! （evict）策略、并发访问保护。CacheStats 只计数，不执行淘汰。

const std = @import("std");
const types = @import("../module_resolver/types.zig");

// Phase 2 类型（复用，不重定义）。
pub const ModuleId = types.ModuleId;
pub const ModuleState = types.ModuleState;

/// 缓存格式版本（u32，从 1 起）。
///
/// 格式变了，旧缓存一律失效：读缓存时先比对存盘的版本号与本常量，
/// 不等即报 CacheError.VersionMismatch，不做迁移、不做兼容读取。
/// 只有改了缓存条目的落盘格式（字段、编码、哈希算法）时才 bump；
/// 只改键的分量取值（如新编译器版本）不 bump——那由 CacheKey 的
/// eql/hash 自然失效。
pub const CacheFormatVersion: u32 = 1;

/// 增量缓存的键：四个分量缺一不可（见文件头背景教训）。
///
///   - content_hash：模块内容哈希（SHA-256，见 compute）；
///   - compiler_version：编译器版本串（如 "0.1.8-80f8783"），借用；
///   - plugin_version：插件版本串，借用；
///   - opt_level：优化级别（与 sa build-exe 优化级别政策一致：
///     0 = 开发/debug 零优化，1 = --release-small，3 = --release-fast）。
///
/// 借用规则：compiler_version / plugin_version 只借用，不拥有；
/// 调用方保证它们在键的使用期内有效（与 Phase 2 ModuleId 的
/// package/path 借用口径一致）。手工构造的键若字段并非借用关系，
/// 不得在释放后继续使用。
pub const CacheKey = struct {
    content_hash: [32]u8,
    compiler_version: []const u8,
    plugin_version: []const u8,
    opt_level: u8,

    /// 由四个分量算出缓存键：内容先 SHA-256 得 content_hash，版本串
    /// 与优化级别原样存入键；四个分量的确定性组合哈希见 hash()
    /// （std.hash.Wyhash 链式混合），判等见 eql（逐项比对四个分量）。
    /// 任一分量变了，算出的键就变：内容变了 content_hash 变；版本
    /// 串变了 eql 即不等；优化级别变了 eql 即不等。
    pub fn compute(
        content: []const u8,
        compiler_version: []const u8,
        plugin_version: []const u8,
        opt_level: u8,
    ) CacheKey {
        var content_hash: [32]u8 = undefined;
        std.crypto.hash.sha2.Sha256.hash(content, &content_hash, .{});
        return .{
            .content_hash = content_hash,
            .compiler_version = compiler_version,
            .plugin_version = plugin_version,
            .opt_level = opt_level,
        };
    }

    /// 四个分量逐项判等：内容哈希、编译器版本、插件版本、优化级别
    /// 全等才相等。任一分量不等即不等——这正是 isStale 的依据。
    pub fn eql(self: CacheKey, other: CacheKey) bool {
        return std.mem.eql(u8, &self.content_hash, &other.content_hash) and
            std.mem.eql(u8, self.compiler_version, other.compiler_version) and
            std.mem.eql(u8, self.plugin_version, other.plugin_version) and
            self.opt_level == other.opt_level;
    }

    /// 四个分量的确定性组合哈希（Wyhash，先内容哈希、再编译器版本、
    /// 再插件版本、最后优化级别），供 HashMap 用。与 eql 一致：
    /// eql 相等的两个键 hash 必然相等；任一分量变了 hash 即变
    /// （与 ModuleId.hash 同款拼法：前一分量的哈希作下一分量的种子）。
    pub fn hash(self: CacheKey) u64 {
        var h = std.hash.Wyhash.hash(0, &self.content_hash);
        h = std.hash.Wyhash.hash(h, self.compiler_version);
        h = std.hash.Wyhash.hash(h, self.plugin_version);
        h = std.hash.Wyhash.hash(h, &.{self.opt_level});
        return h;
    }

    /// `std.HashMap(CacheKey, V, CacheKey.Context, ...)` 的上下文。
    pub const Context = struct {
        pub fn hash(_: Context, key: CacheKey) u64 {
            return key.hash();
        }

        pub fn eql(_: Context, a: CacheKey, b: CacheKey) bool {
            return a.eql(b);
        }
    };
};

/// 一条缓存条目：键 + 模块身份 + 状态 + 产物定位。
///
///   - key：命中判定用的完整键（四个分量）；
///   - module：该条目所属模块的规范身份（Phase 2 ModuleId）；
///   - state：写缓存时模块到达的加载状态（Phase 2/3 四态）；
///     只有 loaded / analyzed 态的模块才有可缓存的产物，
///     unloaded / loading 态的条目不得写入（写入是后续 Phase 的事，
///     本文件只定义形状，不判定）；
///   - artifact_path：产物磁盘路径，只借用、不拥有；
///   - artifact_hash：产物内容的 SHA-256（32 字节），用于读回时
///     校验产物文件本身是否被改动 / 损坏；
///   - created_at：条目创建时间（unix 秒）；0 表示未知（读旧格式
///     缓存时无此字段，不以此判定过期——过期只看键，见 isStale）。
///
/// 借用规则：artifact_path 只借用，不拥有；调用方保证其在条目
/// 使用期内有效。本文件不分配、不释放它。
pub const CacheEntry = struct {
    key: CacheKey,
    module: ModuleId,
    state: ModuleState,
    artifact_path: []const u8,
    artifact_hash: [32]u8,
    created_at: i64 = 0,

    /// 键不等即过期：期望键（当前内容 + 当前编译器/插件版本 +
    /// 当前优化级别）与本条目的键逐项比对，任一分量不等即过期。
    /// 注意：只看键，不看 created_at——时间戳为 0（未知）也不
    /// 影响判定；产物文件本身的完整性另由 artifact_hash 校验，
    /// 不在本函数做。
    pub fn isStale(self: CacheEntry, expected: CacheKey) bool {
        return !self.key.eql(expected);
    }
};

/// 缓存操作的错误集：只含本模块可达的错误，不冒用别的模块的
/// 错误集（不复用 ResolveError / LoaderError / GraphError）。
/// 本文件不做磁盘 I/O、不分配：OutOfMemory 不归入此类。
pub const CacheError = error{
    /// 存盘的缓存格式版本与 CacheFormatVersion 不等：旧缓存一律
    /// 失效，不做迁移、不做兼容读取。
    VersionMismatch,
    /// 缓存条目损坏：落盘字段缺失、长度越界、或 artifact_hash
    /// 与产物文件内容对不上。
    CorruptEntry,
    /// 查到的条目键与期望键不等（命中了错误的条目，如键冲突或
    /// 缓存文件被错放）。
    KeyMismatch,
};

/// 缓存命中统计：只计数，不执行任何缓存操作（淘汰 / 失效扫描
/// 是后续 Phase 的事；evicted 只记录已发生的淘汰次数）。
pub const CacheStats = struct {
    hits: u64 = 0,
    misses: u64 = 0,
    invalidated: u64 = 0,
    evicted: u64 = 0,

    pub fn recordHit(self: *CacheStats) void {
        self.hits += 1;
    }

    pub fn recordMiss(self: *CacheStats) void {
        self.misses += 1;
    }

    pub fn recordInvalidated(self: *CacheStats) void {
        self.invalidated += 1;
    }

    pub fn recordEvicted(self: *CacheStats) void {
        self.evicted += 1;
    }

    /// 纯文本一行摘要（owned，调用方释放），与 Phase 6
    /// `summarizeDce` 同款口径：纯文本，无 JSON 输出。
    /// 形如：`cache hits=12 misses=3 invalidated=1 evicted=0`。
    pub fn summarize(self: CacheStats, allocator: std.mem.Allocator) std.mem.Allocator.Error![]u8 {
        return std.fmt.allocPrint(
            allocator,
            "cache hits={d} misses={d} invalidated={d} evicted={d}",
            .{ self.hits, self.misses, self.invalidated, self.evicted },
        );
    }
};
