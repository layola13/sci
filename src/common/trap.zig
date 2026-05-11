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

fn writeJsonString(writer: anytype, text: []const u8) !void {
    try writer.writeByte('"');
    for (text) |c| {
        switch (c) {
            '"' => try writer.writeAll("\\\""),
            '\\' => try writer.writeAll("\\\\"),
            '\n' => try writer.writeAll("\\n"),
            '\r' => try writer.writeAll("\\r"),
            '\t' => try writer.writeAll("\\t"),
            else => {
                if (c < 0x20) {
                    try writer.print("\\u{X:0>4}", .{c});
                } else {
                    try writer.writeByte(c);
                }
            },
        }
    }
    try writer.writeByte('"');
}

fn writeMaybeString(writer: anytype, value: ?[]const u8) !void {
    if (value) |text| {
        try writeJsonString(writer, text);
    } else {
        try writer.writeAll("null");
    }
}

fn writeMaybeBool(writer: anytype, value: ?bool) !void {
    if (value) |v| {
        try writer.writeAll(if (v) "true" else "false");
    } else {
        try writer.writeAll("null");
    }
}

fn writeMaybeU8(writer: anytype, value: ?u8) !void {
    if (value) |v| {
        try writer.print("{d}", .{v});
    } else {
        try writer.writeAll("null");
    }
}

pub fn writeJson(writer: anytype, report: TrapReport) !void {
    try writer.writeAll("{");
    try writer.writeAll("\"trap\":");
    try writeJsonString(writer, trapName(report.trap));
    try writer.writeAll(",\"line\":");
    try writer.print("{d}", .{report.line});
    try writer.writeAll(",\"source_line\":");
    try writer.print("{d}", .{report.source_line});
    try writer.writeAll(",\"register\":");
    try writeMaybeString(writer, report.register);
    try writer.writeAll(",\"registers\":[");
    for (report.registers, 0..) |item, idx| {
        if (idx != 0) try writer.writeByte(',');
        try writeJsonString(writer, item);
    }
    try writer.writeAll("],\"expected_mask\":");
    try writeMaybeU8(writer, report.expected_mask);
    try writer.writeAll(",\"actual_mask\":");
    try writeMaybeU8(writer, report.actual_mask);
    try writer.writeAll(",\"expected_mask_name\":");
    try writeMaybeString(writer, report.expected_mask_name);
    try writer.writeAll(",\"actual_mask_name\":");
    try writeMaybeString(writer, report.actual_mask_name);
    try writer.writeAll(",\"function\":");
    try writeMaybeString(writer, report.function);
    try writer.writeAll(",\"is_ffi_wrapper\":");
    try writeMaybeBool(writer, report.is_ffi_wrapper);
    try writer.writeAll(",\"message\":");
    try writeJsonString(writer, report.message);
    try writer.writeAll(",\"hint\":");
    try writeMaybeString(writer, report.hint);
    try writer.writeAll("}");
}

test "trap names are stable" {
    try std.testing.expectEqualStrings("ForbiddenSyntax", trapName(.forbidden_syntax));
    try std.testing.expectEqualStrings("MemoryLeak", trapName(.memory_leak));
}
