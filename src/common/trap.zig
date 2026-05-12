const std = @import("std");

const upstream = @import("upstream_loc.zig");

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
    interior_ptr_escape,
    stack_escape,
    early_return_leak,
    fallible_contract_mismatch,
    invalid_atomic_ordering,
    atomic_ordering_mismatch,
};

pub const TrapReport = struct {
    trap: Trap,
    line: u32,
    source_line: u32,
    register_buf: [64]u8 = [_]u8{0} ** 64,
    register: ?[]const u8 = null,
    registers: []const []const u8 = &.{},
    expected_mask: ?u16 = null,
    actual_mask: ?u16 = null,
    expected_mask_name: ?[]const u8 = null,
    actual_mask_name: ?[]const u8 = null,
    upstream_loc: ?upstream.UpstreamLoc = null,
    upstream_file_buf: [128]u8 = [_]u8{0} ** 128,
    upstream_line: u32 = 0,
    upstream_col: u32 = 0,
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
        .interior_ptr_escape => "InteriorPtrEscape",
        .stack_escape => "StackEscape",
        .early_return_leak => "EarlyReturnLeak",
        .fallible_contract_mismatch => "FallibleContractMismatch",
        .invalid_atomic_ordering => "InvalidAtomicOrdering",
        .atomic_ordering_mismatch => "AtomicOrderingMismatch",
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

fn bufText(buf: []const u8) []const u8 {
    return buf[0..(std.mem.indexOfScalar(u8, buf, 0) orelse buf.len)];
}

fn writeStringOrBuf(writer: anytype, value: ?[]const u8, buf: []const u8) !void {
    if (value) |text| {
        try writeJsonString(writer, text);
    } else {
        try writeJsonString(writer, bufText(buf));
    }
}

fn writeMaybeBool(writer: anytype, value: ?bool) !void {
    if (value) |v| {
        try writer.writeAll(if (v) "true" else "false");
    } else {
        try writer.writeAll("null");
    }
}

fn writeMaybeU16(writer: anytype, value: ?u16) !void {
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
    try writeStringOrBuf(writer, report.register, &report.register_buf);
    try writer.writeAll(",\"registers\":[");
    for (report.registers, 0..) |item, idx| {
        if (idx != 0) try writer.writeByte(',');
        try writeJsonString(writer, item);
    }
    try writer.writeAll("],\"expected_mask\":");
    try writeMaybeU16(writer, report.expected_mask);
    try writer.writeAll(",\"actual_mask\":");
    try writeMaybeU16(writer, report.actual_mask);
    try writer.writeAll(",\"expected_mask_name\":");
    try writeMaybeString(writer, report.expected_mask_name);
    try writer.writeAll(",\"actual_mask_name\":");
    try writeMaybeString(writer, report.actual_mask_name);
    try writer.writeAll(",\"upstream_loc\":");
    if (report.upstream_loc) |loc| {
        try writer.writeByte('{');
        try writer.writeAll("\"file\":");
        try writeJsonString(writer, loc.file);
        try writer.writeAll(",\"line\":");
        try writer.print("{d}", .{loc.line});
        try writer.writeAll(",\"col\":");
        try writer.print("{d}", .{loc.col});
        try writer.writeByte('}');
    } else if (report.upstream_file_buf[0] != 0) {
        try writer.writeByte('{');
        try writer.writeAll("\"file\":");
        try writeJsonString(writer, bufText(&report.upstream_file_buf));
        try writer.writeAll(",\"line\":");
        try writer.print("{d}", .{report.upstream_line});
        try writer.writeAll(",\"col\":");
        try writer.print("{d}", .{report.upstream_col});
        try writer.writeByte('}');
    } else {
        try writer.writeAll("null");
    }
    try writer.writeAll(",\"function\":");
    try writeStringOrBuf(writer, report.function, &report.function_buf);
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
    try std.testing.expectEqualStrings("InteriorPtrEscape", trapName(.interior_ptr_escape));
}

test "trap json serialization is stable" {
    var list = std.ArrayList(u8).init(std.testing.allocator);
    defer list.deinit();

    const report = TrapReport{
        .trap = .memory_leak,
        .line = 12,
        .source_line = 9,
        .register = "r1",
        .registers = &.{ "r1", "r2" },
        .expected_mask = 0x01,
        .actual_mask = 0x08,
        .expected_mask_name = "Active",
        .actual_mask_name = "Consumed",
        .upstream_loc = .{ .file = "main.rs", .line = 42, .col = 7 },
        .function = "main",
        .is_ffi_wrapper = false,
        .message = "live registers remain at function exit",
        .hint = "insert explicit release",
    };

    try writeJson(list.writer(), report);
    try std.testing.expectEqualStrings(
        "{\"trap\":\"MemoryLeak\",\"line\":12,\"source_line\":9,\"register\":\"r1\",\"registers\":[\"r1\",\"r2\"],\"expected_mask\":1,\"actual_mask\":8,\"expected_mask_name\":\"Active\",\"actual_mask_name\":\"Consumed\",\"upstream_loc\":{\"file\":\"main.rs\",\"line\":42,\"col\":7},\"function\":\"main\",\"is_ffi_wrapper\":false,\"message\":\"live registers remain at function exit\",\"hint\":\"insert explicit release\"}",
        list.items,
    );
}
