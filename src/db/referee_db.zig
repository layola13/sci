const std = @import("std");
const trap = @import("../common/trap.zig");
const sig = @import("../common/signature.zig");
const inst = @import("../common/instruction.zig");
const upstream = @import("../common/upstream_loc.zig");

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

pub const ScanFinding = struct {
    trap: trap.Trap = .db_capability_escalation,
    line: u32,
    source_line: u32,
    message: []const u8,
    expected_mask: ?u16 = null,
    actual_mask: ?u16 = null,
    upstream_loc: ?upstream.UpstreamLoc = null,
    table: ?[]const u8 = null,
    sha256: ?[32]u8 = null,
    offset: ?u64 = null,
};

fn trapReport(kind: trap.Trap, item: inst.Instruction, message: []const u8) trap.TrapReport {
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
        .upstream_loc = item.upstream_loc,
        .upstream_file_buf = [_]u8{0} ** 128,
        .upstream_line = if (item.upstream_loc) |loc| loc.line else 0,
        .upstream_col = if (item.upstream_loc) |loc| loc.col else 0,
        .function_buf = [_]u8{0} ** 64,
        .function = null,
        .is_ffi_wrapper = null,
        .message = message,
        .hint = null,
    };
    if (item.raw_text.len != 0) {
        const len = @min(report.source_text_buf.len, item.raw_text.len);
        std.mem.copyForwards(u8, report.source_text_buf[0..len], item.raw_text[0..len]);
        std.mem.copyForwards(u8, report.original_text_buf[0..len], item.raw_text[0..len]);
    }
    return report;
}

fn containsGrant(grants: []const Grant, kind: GrantKind, target: []const u8) bool {
    for (grants) |grant| {
        if (grant.kind == kind and std.mem.eql(u8, grant.target, target)) return true;
    }
    return false;
}

fn classifyStoreAddress(item: inst.Instruction) ?[]const u8 {
    if (item.operands[0] != .text) return null;
    const text = item.operands[0].text;
    const plus = std.mem.indexOfScalar(u8, text, '+') orelse return text;
    return text[0..plus];
}

fn classifyAtomicAddress(item: inst.Instruction) ?[]const u8 {
    switch (item.kind) {
        .atomic_rmw => {
            if (item.operands[1] == .text) {
                const text = item.operands[1].text;
                const plus = std.mem.indexOfScalar(u8, text, '+') orelse return text;
                return text[0..plus];
            }
        },
        .cmpxchg => {
            if (item.operands[0] == .text) {
                const text = item.operands[0].text;
                const plus = std.mem.indexOfScalar(u8, text, '+') orelse return text;
                return text[0..plus];
            }
        },
        else => {},
    }
    return null;
}

fn reportEscalation(item: inst.Instruction, message: []const u8) trap.TrapReport {
    return trapReport(.db_capability_escalation, item, message);
}

pub fn scanForTrap(
    instructions: []const inst.Instruction,
    grants: []const Grant,
) ?trap.TrapReport {
    for (instructions) |item| {
        switch (item.kind) {
            .load => {
                if (classifyStoreAddress(item)) |base| {
                    if (!containsGrant(grants, .db_read, base)) {
                        return reportEscalation(item, "load requires db_read grant");
                    }
                }
            },
            .store => {
                if (classifyStoreAddress(item)) |base| {
                    if (!containsGrant(grants, .db_write, base)) {
                        return reportEscalation(item, "store requires db_write grant");
                    }
                }
            },
            .atomic_rmw => {
                if (classifyAtomicAddress(item)) |base| {
                    if (!containsGrant(grants, .db_atomic_cursor, base)) {
                        return reportEscalation(item, "atomic cursor requires db_atomic_cursor grant");
                    }
                }
            },
            else => {},
        }
    }
    return null;
}

pub fn inspectText(
    allocator: std.mem.Allocator,
    source: []const u8,
) ![]u8 {
    var list = std.ArrayList(u8).init(allocator);
    errdefer list.deinit();
    try list.writer().print("db-inspect: {d} bytes\n", .{source.len});
    return try list.toOwnedSlice();
}

test "db referee catches missing read grant" {
    const ins = [_]inst.Instruction{
        .{
            .kind = .load,
            .source_line = 1,
            .expanded_line = 0,
            .operands = .{
                .{ .reg = 0 },
                .{ .text = "col_inventory+0" },
                .{ .none = {} },
                .{ .none = {} },
            },
            .raw_text = "x = load col_inventory+0 as u32",
        },
    };
    const grants = [_]Grant{};
    try std.testing.expect(scanForTrap(ins[0..], grants[0..]) != null);
}
