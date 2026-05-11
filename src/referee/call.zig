const std = @import("std");
const common_instruction = @import("../common/instruction.zig");
const common_signature = @import("../common/signature.zig");

pub const CallError = error{
    InvalidCallSyntax,
    UnknownFunction,
    CapabilityMismatch,
    OutOfMemory,
};

pub const ParsedArg = struct {
    prefix: common_instruction.CapPrefix,
    text: []const u8,
};

pub const ParsedCall = struct {
    dest: ?[]const u8,
    callee: []const u8,
    args: []ParsedArg,
    is_indirect: bool,

    pub fn deinit(self: *ParsedCall, allocator: std.mem.Allocator) void {
        if (self.dest) |dest| allocator.free(dest);
        allocator.free(self.callee);
        for (self.args) |arg| {
            allocator.free(arg.text);
        }
        allocator.free(self.args);
        self.* = undefined;
    }
};

fn parseArg(allocator: std.mem.Allocator, text: []const u8) !ParsedArg {
    const trimmed = std.mem.trim(u8, text, " \t");
    if (trimmed.len == 0) return CallError.InvalidCallSyntax;

    return switch (trimmed[0]) {
        '&' => .{
            .prefix = .borrow,
            .text = try allocator.dupe(u8, std.mem.trim(u8, trimmed[1..], " \t")),
        },
        '^' => .{
            .prefix = .move,
            .text = try allocator.dupe(u8, std.mem.trim(u8, trimmed[1..], " \t")),
        },
        '*' => .{
            .prefix = .raw,
            .text = try allocator.dupe(u8, std.mem.trim(u8, trimmed[1..], " \t")),
        },
        else => .{
            .prefix = .by_value,
            .text = try allocator.dupe(u8, trimmed),
        },
    };
}

fn parseCallBody(allocator: std.mem.Allocator, body: []const u8, is_indirect: bool) !ParsedCall {
    const trimmed = std.mem.trim(u8, body, " \t");
    if (trimmed.len == 0) return CallError.InvalidCallSyntax;

    const open = std.mem.indexOfScalar(u8, trimmed, '(') orelse return CallError.InvalidCallSyntax;
    const close = std.mem.lastIndexOfScalar(u8, trimmed, ')') orelse return CallError.InvalidCallSyntax;
    if (close < open) return CallError.InvalidCallSyntax;

    const callee_text = std.mem.trim(u8, trimmed[0..open], " \t");
    if (callee_text.len == 0) return CallError.InvalidCallSyntax;
    const callee_name = if (callee_text[0] == '@') callee_text[1..] else callee_text;

    var args_list = std.ArrayList(ParsedArg).init(allocator);
    errdefer {
        for (args_list.items) |arg| allocator.free(arg.text);
        args_list.deinit();
    }

    const args_text = std.mem.trim(u8, trimmed[open + 1 .. close], " \t");
    if (args_text.len != 0) {
        var it = std.mem.splitScalar(u8, args_text, ',');
        while (it.next()) |fragment| {
            try args_list.append(try parseArg(allocator, fragment));
        }
    }

    return .{
        .dest = null,
        .callee = try allocator.dupe(u8, callee_name),
        .args = try args_list.toOwnedSlice(),
        .is_indirect = is_indirect,
    };
}

pub fn parseCall(allocator: std.mem.Allocator, raw_text: []const u8) !ParsedCall {
    const trimmed = std.mem.trim(u8, raw_text, " \t\r");
    if (trimmed.len == 0) return CallError.InvalidCallSyntax;

    const call_start = if (std.mem.indexOf(u8, trimmed, "call_indirect")) |idx| idx else if (std.mem.indexOf(u8, trimmed, "call")) |idx| idx else return CallError.InvalidCallSyntax;
    const prefix = std.mem.trim(u8, trimmed[0..call_start], " \t");
    const dest = if (prefix.len != 0) blk: {
        const eq = std.mem.indexOfScalar(u8, prefix, '=') orelse return CallError.InvalidCallSyntax;
        const name = std.mem.trim(u8, prefix[0..eq], " \t");
        const tail = std.mem.trim(u8, prefix[eq + 1 ..], " \t");
        if (name.len == 0 or tail.len != 0) return CallError.InvalidCallSyntax;
        break :blk try allocator.dupe(u8, name);
    } else null;
    errdefer if (dest) |value| allocator.free(value);

    if (std.mem.indexOf(u8, trimmed, "call_indirect")) |idx| {
        const body = std.mem.trimLeft(u8, trimmed[idx + "call_indirect".len ..], " \t");
        var call = try parseCallBody(allocator, body, true);
        call.dest = dest;
        return call;
    }

    if (std.mem.indexOf(u8, trimmed, "call")) |idx| {
        const body = std.mem.trimLeft(u8, trimmed[idx + "call".len ..], " \t");
        var call = try parseCallBody(allocator, body, false);
        call.dest = dest;
        return call;
    }

    if (dest) |value| allocator.free(value);
    return CallError.InvalidCallSyntax;
}

fn validatePrefix(expected: common_instruction.CapPrefix, actual: common_instruction.CapPrefix) bool {
    return expected == actual;
}

pub fn validateCall(
    allocator: std.mem.Allocator,
    sigs: []const common_signature.FunctionSig,
    raw_text: []const u8,
) !ParsedCall {
    var call = try parseCall(allocator, raw_text);
    errdefer call.deinit(allocator);

    if (call.is_indirect) {
        return call;
    }

    var sig: ?common_signature.FunctionSig = null;
    for (sigs) |item| {
        if (std.mem.eql(u8, item.name, call.callee)) {
            sig = item;
            break;
        }
    }
    const resolved = sig orelse return CallError.UnknownFunction;
    if (resolved.params.len != call.args.len) return CallError.CapabilityMismatch;

    for (call.args, resolved.params, 0..) |arg, param, idx| {
        if (!validatePrefix(param.cap, arg.prefix)) {
            _ = idx;
            return CallError.CapabilityMismatch;
        }
    }

    return call;
}

test "parse and validate a direct call signature" {
    var sigs = std.ArrayList(common_signature.FunctionSig).init(std.testing.allocator);
    defer {
        for (sigs.items) |*sig| sig.deinit(std.testing.allocator);
        sigs.deinit();
    }

    try sigs.append(try common_signature.parseFunctionSig(std.testing.allocator, "@consume(^p: i32) -> void:", 0, 0));

    var call = try validateCall(std.testing.allocator, sigs.items, "call @consume(^p)");
    defer call.deinit(std.testing.allocator);
    try std.testing.expectEqualStrings("consume", call.callee);
    try std.testing.expectEqual(@as(usize, 1), call.args.len);
    try std.testing.expectEqual(common_instruction.CapPrefix.move, call.args[0].prefix);
}
