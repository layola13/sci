//! sa-incremental-cache facade: thin re-export, no logic.
//!
//! Phase 7（P2）增量编译缓存：回答一次编译“哪些模块可以复用上次的
//! 编译产物、哪些必须重编”。只做计划，不编译模块、不写缓存、不删条目。
//! 本文件只含 re-export，不含逻辑（15/15 公开名，见 check_phase7.py）。

const types_mod = @import("incremental_cache/types.zig");
const store_mod = @import("incremental_cache/store.zig");
const driver_mod = @import("incremental_cache/driver.zig");
const loader_mod = @import("module_loader/loader.zig");
const module_graph_mod = @import("dependency_graph/module_graph.zig");

// types.zig (P7A): 缓存键与核心类型。
pub const CacheFormatVersion = types_mod.CacheFormatVersion;
pub const CacheKey = types_mod.CacheKey;
pub const CacheEntry = types_mod.CacheEntry;
pub const CacheError = types_mod.CacheError;
pub const CacheStats = types_mod.CacheStats;
pub const ModuleId = types_mod.ModuleId;
pub const ModuleState = types_mod.ModuleState;

// store.zig (P7B): 内存存储与失效。
pub const CacheStore = store_mod.CacheStore;
pub const invalidate = store_mod.invalidate;
pub const validateAll = store_mod.validateAll;

// driver.zig (P7C): 增量驱动。
pub const ReusePlan = driver_mod.ReusePlan;
pub const planIncremental = driver_mod.planIncremental;
pub const summarizePlan = driver_mod.summarizePlan;

// 复用的 Phase 3 / Phase 4 类型。
pub const LazyLoader = loader_mod.LazyLoader;
pub const ModuleGraph = module_graph_mod.ModuleGraph;
