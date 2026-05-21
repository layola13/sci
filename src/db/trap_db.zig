const std = @import("std");
const trap = @import("common/trap.zig");

pub const DbTrap = enum {
    capability_escalation,
    memory_guard_violation,
    blob_arena_oom,
    concurrency_conflict,
    schema_mismatch,
    cursor_overflow,
    column_type_mismatch,
    query_hash_unknown,
    blob_handle_invalid,
    snapshot_corrupted,
    duplicate_register,
    forbidden_sql_string,
};

pub const DbTrapInfo = struct {
    trap: trap.Trap,
    code: u32,
    name: []const u8,
    default_message: []const u8,
};

pub fn dbTrapInfo(kind: DbTrap) DbTrapInfo {
    return switch (kind) {
        .capability_escalation => .{
            .trap = .db_capability_escalation,
            .code = trap.trapCode(.db_capability_escalation),
            .name = "DbCapabilityEscalation",
            .default_message = "database capability check failed",
        },
        .memory_guard_violation => .{
            .trap = .db_memory_guard_violation,
            .code = trap.trapCode(.db_memory_guard_violation),
            .name = "DbMemoryGuardViolation",
            .default_message = "database memory guard violation",
        },
        .blob_arena_oom => .{
            .trap = .db_blob_arena_oom,
            .code = trap.trapCode(.db_blob_arena_oom),
            .name = "DbBlobArenaOOM",
            .default_message = "blob arena is out of memory",
        },
        .concurrency_conflict => .{
            .trap = .db_concurrency_conflict,
            .code = trap.trapCode(.db_concurrency_conflict),
            .name = "DbConcurrencyConflict",
            .default_message = "database concurrency conflict",
        },
        .schema_mismatch => .{
            .trap = .db_schema_mismatch,
            .code = trap.trapCode(.db_schema_mismatch),
            .name = "DbSchemaMismatch",
            .default_message = "database schema mismatch",
        },
        .cursor_overflow => .{
            .trap = .db_cursor_overflow,
            .code = trap.trapCode(.db_cursor_overflow),
            .name = "DbCursorOverflow",
            .default_message = "cursor overflow",
        },
        .column_type_mismatch => .{
            .trap = .db_column_type_mismatch,
            .code = trap.trapCode(.db_column_type_mismatch),
            .name = "DbColumnTypeMismatch",
            .default_message = "column type mismatch",
        },
        .query_hash_unknown => .{
            .trap = .db_query_hash_unknown,
            .code = trap.trapCode(.db_query_hash_unknown),
            .name = "DbQueryHashUnknown",
            .default_message = "query hash is not registered",
        },
        .blob_handle_invalid => .{
            .trap = .db_blob_handle_invalid,
            .code = trap.trapCode(.db_blob_handle_invalid),
            .name = "DbBlobHandleInvalid",
            .default_message = "blob handle is invalid",
        },
        .snapshot_corrupted => .{
            .trap = .db_snapshot_corrupted,
            .code = trap.trapCode(.db_snapshot_corrupted),
            .name = "DbSnapshotCorrupted",
            .default_message = "snapshot data is corrupted",
        },
        .duplicate_register => .{
            .trap = .db_duplicate_register,
            .code = trap.trapCode(.db_duplicate_register),
            .name = "DbDuplicateRegister",
            .default_message = "duplicate database register entry",
        },
        .forbidden_sql_string => .{
            .trap = .db_forbidden_sql_string,
            .code = trap.trapCode(.db_forbidden_sql_string),
            .name = "DbForbiddenSqlString",
            .default_message = "runtime SQL strings are forbidden",
        },
    };
}

test "db trap catalog is stable" {
    const info = dbTrapInfo(.capability_escalation);
    try std.testing.expectEqual(trap.Trap.db_capability_escalation, info.trap);
    try std.testing.expectEqualStrings("DbCapabilityEscalation", info.name);
    try std.testing.expect(info.code != 0);
}
