const std = @import("std");
const atomic = @import("common/atomic.zig");
const inst = @import("common/instruction.zig");
const trap = @import("common/trap.zig");

pub const GrantKind = enum {
    db_read,
    db_write,
    db_alloc_blob,
    db_atomic_cursor,
};

pub const Grant = struct {
    kind: GrantKind,
    target: []const u8,
};

fn trapReport(kind: trap.Trap, item: anytype, message: []const u8) trap.TrapReport {
    var report: trap.TrapReport = .{
        .trap = kind,
        .trap_code = trap.trapCode(kind),
        .line = item.expanded_line + 1,
        .source_line = item.source_line,
        .source_text_buf = [_]u8{0} ** 256,
        .original_text_buf = [_]u8{0} ** 256,
        .source_text = null,
        .original_text = null,
        .register_buf = [_]u8{0} ** 64,
        .register = null,
        .registers = &.{},
        .expected_mask = null,
        .actual_mask = null,
        .expected_mask_name = null,
        .actual_mask_name = null,
        .upstream_loc = null,
        .upstream_file_buf = [_]u8{0} ** 128,
        .upstream_line = if (item.upstream_loc) |loc| loc.line else 0,
        .upstream_col = if (item.upstream_loc) |loc| loc.col else 0,
        .function_buf = [_]u8{0} ** 64,
        .function = null,
        .is_ffi_wrapper = null,
        .message = message,
        .hint = null,
    };
    if (item.upstream_loc) |loc| {
        const len = @min(report.upstream_file_buf.len, loc.file.len);
        std.mem.copyForwards(u8, report.upstream_file_buf[0..len], loc.file[0..len]);
    }
    if (item.raw_text.len != 0) {
        const len = @min(report.source_text_buf.len, item.raw_text.len);
        std.mem.copyForwards(u8, report.source_text_buf[0..len], item.raw_text[0..len]);
        std.mem.copyForwards(u8, report.original_text_buf[0..len], item.raw_text[0..len]);
    }
    return report;
}

fn hasGrantKind(grants: []const Grant, kind: GrantKind) bool {
    for (grants) |grant| {
        if (grant.kind == kind) return true;
    }
    return false;
}

fn trim(text: []const u8) []const u8 {
    return std.mem.trim(u8, text, " \t\r");
}

fn loadBase(raw_text: []const u8) ?[]const u8 {
    const trimmed = trim(raw_text);
    const eq = std.mem.indexOfScalar(u8, trimmed, '=') orelse return null;
    const rhs = trim(trimmed[eq + 1 ..]);
    if (!std.mem.startsWith(u8, rhs, "load ")) return null;
    const after = trim(rhs["load".len ..]);
    const as_idx = std.mem.indexOf(u8, after, " as ") orelse after.len;
    const address = trim(after[0..as_idx]);
    const plus = std.mem.indexOfScalar(u8, address, '+') orelse return null;
    return trim(address[0..plus]);
}

fn storeBase(raw_text: []const u8) ?[]const u8 {
    const trimmed = trim(raw_text);
    if (!std.mem.startsWith(u8, trimmed, "store ")) return null;
    const after = trim(trimmed["store".len ..]);
    const comma = std.mem.indexOfScalar(u8, after, ',') orelse return null;
    const address = trim(after[0..comma]);
    const plus = std.mem.indexOfScalar(u8, address, '+') orelse return null;
    return trim(address[0..plus]);
}

fn requireGrant(item: anytype, grants: []const Grant, kind: GrantKind, message: []const u8) ?trap.TrapReport {
    if (!hasGrantKind(grants, kind)) {
        return trapReport(.db_capability_escalation, item, message);
    }
    return null;
}

fn scanInstruction(item: anytype, grants: []const Grant) ?trap.TrapReport {
    switch (item.kind) {
        .load => {
            if (loadBase(item.raw_text) == null) return null;
            return requireGrant(item, grants, .db_read, "load requires db_read grant");
        },
        .store => {
            if (storeBase(item.raw_text) == null) return null;
            return requireGrant(item, grants, .db_write, "store requires db_write grant");
        },
        .atomic_load => {
            const parsed = atomic.parseLoad(item.raw_text) catch return null;
            _ = parsed;
            return requireGrant(item, grants, .db_read, "atomic_load requires db_read grant");
        },
        .atomic_store => {
            const parsed = atomic.parseStore(item.raw_text) catch return null;
            _ = parsed;
            return requireGrant(item, grants, .db_write, "atomic_store requires db_write grant");
        },
        .cmpxchg => {
            const parsed = atomic.parseCmpxchg(item.raw_text) catch return null;
            _ = parsed;
            return requireGrant(item, grants, .db_write, "cmpxchg requires db_write grant");
        },
        .atomic_rmw => {
            const parsed = atomic.parseRmw(item.raw_text) catch return null;
            if (parsed.op == .add and std.mem.eql(u8, trim(parsed.offset), "0")) {
                return requireGrant(item, grants, .db_atomic_cursor, "atomic cursor requires db_atomic_cursor grant");
            }
            return requireGrant(item, grants, .db_write, "atomic_rmw requires db_write grant");
        },
        else => {},
    }
    return null;
}

pub fn scanForTrap(instructions: anytype, grants: []const Grant) ?trap.TrapReport {
    for (instructions) |item| {
        if (scanInstruction(item, grants)) |report| return report;
    }
    return null;
}

pub fn inspectText(allocator: std.mem.Allocator, source: []const u8) ![]u8 {
    var out = std.ArrayList(u8).init(allocator);
    errdefer out.deinit();
    try out.writer().print("db-inspect: {d} bytes\n", .{source.len});
    return try out.toOwnedSlice();
}

test "db referee catches missing read grant" {
    const ins = [_]inst.Instruction{
        .{
            .kind = .load,
            .source_line = 1,
            .expanded_line = 0,
            .operands = .{
                inst.operandNone(),
                inst.operandNone(),
                inst.operandNone(),
                inst.operandNone(),
            },
            .raw_text = "x = load col_inventory+0 as u32",
        },
    };
    const grants = [_]Grant{};
    try std.testing.expect(scanForTrap(ins[0..], grants[0..]) != null);
}

test "db referee catches missing cursor grant" {
    const ins = [_]inst.Instruction{
        .{
            .kind = .atomic_rmw,
            .source_line = 1,
            .expanded_line = 0,
            .operands = .{
                inst.operandNone(),
                inst.operandNone(),
                inst.operandNone(),
                inst.operandNone(),
            },
            .raw_text = "old = atomic_rmw_add global_len+0, 1 seq_cst",
        },
    };
    const grants = [_]Grant{};
    try std.testing.expect(scanForTrap(ins[0..], grants[0..]) != null);
}

test "db referee allows matching grant kinds" {
    const ins = [_]inst.Instruction{
        .{
            .kind = .store,
            .source_line = 1,
            .expanded_line = 0,
            .operands = .{
                inst.operandNone(),
                inst.operandNone(),
                inst.operandNone(),
                inst.operandNone(),
            },
            .raw_text = "store col_inventory+0, value as u32",
        },
    };
    const grants = [_]Grant{
        .{ .kind = .db_write, .target = "flash_sale" },
    };
    try std.testing.expect(scanForTrap(ins[0..], grants[0..]) == null);
}
