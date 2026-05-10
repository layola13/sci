const std = @import("std");

pub const Trap = enum(u8) {
    forbidden_syntax,
    duplicate_def,
    duplicate_label,
    unsupported_type,
    macro_recursion_limit,
    register_redefinition,
    unknown_register,
    borrow_conflict,
    use_after_move,
    double_mutable_borrow,
    read_write_conflict,
    memory_leak,
    capability_mismatch,
    fallthrough_forbidden,
    phi_state_conflict,
    gas_exceeded,
    arena_oom,
    snapshot_version_mismatch,
    illegal_unsafe_context,
    ffi_ownership_violation,
    unsupported_sys_intrinsic,
};

pub const TrapReport = struct {
    trap: Trap,
    line: u32,
    source_line: u32,
    register_buf: [20]u8 = [_]u8{0} ** 20,
    register: ?[]const u8 = null,
    registers: []const []const u8 = &.{},
    expected_mask: ?u8 = null,
    actual_mask: ?u8 = null,
    expected_mask_name: ?[]const u8 = null,
    actual_mask_name: ?[]const u8 = null,
    function_buf: [64]u8 = [_]u8{0} ** 64,
    function: ?[]const u8 = null,
    is_ffi_wrapper: ?bool = null,
    message: []const u8,
    hint: ?[]const u8 = null,
};

pub fn trapName(trap: Trap) []const u8 {
    return switch (trap) {
        .forbidden_syntax => "ForbiddenSyntax",
        .duplicate_def => "DuplicateDef",
        .duplicate_label => "DuplicateLabel",
        .unsupported_type => "UnsupportedType",
        .macro_recursion_limit => "MacroRecursionLimit",
        .register_redefinition => "RegisterRedefinition",
        .unknown_register => "UnknownRegister",
        .borrow_conflict => "BorrowConflict",
        .use_after_move => "UseAfterMove",
        .double_mutable_borrow => "DoubleMutableBorrow",
        .read_write_conflict => "ReadWriteConflict",
        .memory_leak => "MemoryLeak",
        .capability_mismatch => "CapabilityMismatch",
        .fallthrough_forbidden => "FallthroughForbidden",
        .phi_state_conflict => "PhiStateConflict",
        .gas_exceeded => "GasExceeded",
        .arena_oom => "ArenaOOM",
        .snapshot_version_mismatch => "SnapshotVersionMismatch",
        .illegal_unsafe_context => "IllegalUnsafeContext",
        .ffi_ownership_violation => "FfiOwnershipViolation",
        .unsupported_sys_intrinsic => "UnsupportedSysIntrinsic",
    };
}

test "trap names are stable" {
    try std.testing.expectEqualStrings("ForbiddenSyntax", trapName(.forbidden_syntax));
    try std.testing.expectEqualStrings("MemoryLeak", trapName(.memory_leak));
}
