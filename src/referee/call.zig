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
    dest2: ?[]const u8 = null,
    callee: []const u8,
    args: []ParsedArg,
    is_indirect: bool,

    pub fn deinit(self: *ParsedCall, allocator: std.mem.Allocator) void {
        if (self.dest) |dest| allocator.free(dest);
        if (self.dest2) |dest| allocator.free(dest);
        allocator.free(self.callee);
        for (self.args) |arg| {
            allocator.free(arg.text);
        }
        allocator.free(self.args);
        self.* = undefined;
    }
};

fn operandTextFromInstruction(operand: common_instruction.Operand, symbols: anytype) ?[]const u8 {
    return switch (operand) {
        .reg => |id| symbols.lookupName(id),
        .symbol => |id| symbols.lookupName(id),
        .label => |id| symbols.lookupName(id),
        .func => |id| symbols.lookupName(id),
        .text => |text| text,
        .native_text => |text| text,
        .imm_i64, .imm_u64, .imm_int, .imm_float => null,
        else => null,
    };
}

fn parsedArgFromOperand(allocator: std.mem.Allocator, operand: common_instruction.Operand, symbols: anytype) !ParsedArg {
    const text = operandTextFromInstruction(operand, symbols) orelse return CallError.InvalidCallSyntax;
    return try parseArg(allocator, text);
}

fn parsedSpecialArgFromOperand(allocator: std.mem.Allocator, operand: common_instruction.Operand, symbols: anytype) !ParsedArg {
    const text = operandTextFromInstruction(operand, symbols) orelse return CallError.InvalidCallSyntax;
    const trimmed = std.mem.trim(u8, text, " \t");
    if (trimmed.len >= 2 and trimmed[0] == '(' and trimmed[trimmed.len - 1] == ')') {
        return try parseArg(allocator, trimmed[1 .. trimmed.len - 1]);
    }
    return try parseArg(allocator, trimmed);
}

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

fn splitCallArgs(allocator: std.mem.Allocator, text: []const u8) ![]const []const u8 {
    const trimmed = std.mem.trim(u8, text, " \t");
    if (trimmed.len == 0) return try allocator.alloc([]const u8, 0);

    var segments = std.ArrayList([]const u8).init(allocator);
    errdefer segments.deinit();

    var paren_depth: usize = 0;
    var brace_depth: usize = 0;
    var bracket_depth: usize = 0;
    var in_string = false;
    var escape = false;
    var start: usize = 0;

    for (trimmed, 0..) |c, idx| {
        if (in_string) {
            if (escape) {
                escape = false;
                continue;
            }
            switch (c) {
                '\\' => escape = true,
                '"' => in_string = false,
                else => {},
            }
            continue;
        }

        switch (c) {
            '"' => in_string = true,
            '(' => paren_depth += 1,
            ')' => {
                if (paren_depth == 0) return CallError.InvalidCallSyntax;
                paren_depth -= 1;
            },
            '{' => brace_depth += 1,
            '}' => {
                if (brace_depth == 0) return CallError.InvalidCallSyntax;
                brace_depth -= 1;
            },
            '[' => bracket_depth += 1,
            ']' => {
                if (bracket_depth == 0) return CallError.InvalidCallSyntax;
                bracket_depth -= 1;
            },
            ',' => {
                if (paren_depth == 0 and brace_depth == 0 and bracket_depth == 0) {
                    const segment = std.mem.trim(u8, trimmed[start..idx], " \t");
                    if (segment.len == 0) return CallError.InvalidCallSyntax;
                    try segments.append(segment);
                    start = idx + 1;
                }
            },
            else => {},
        }
    }

    if (in_string or escape or paren_depth != 0 or brace_depth != 0 or bracket_depth != 0) {
        return CallError.InvalidCallSyntax;
    }

    const final_segment = std.mem.trim(u8, trimmed[start..], " \t");
    if (final_segment.len == 0) return CallError.InvalidCallSyntax;
    try segments.append(final_segment);
    return try segments.toOwnedSlice();
}

fn parseCallBody(allocator: std.mem.Allocator, body: []const u8, is_indirect: bool) !ParsedCall {
    const trimmed = std.mem.trim(u8, body, " \t");
    if (trimmed.len == 0) return CallError.InvalidCallSyntax;

    const open = std.mem.indexOfScalar(u8, trimmed, '(') orelse return CallError.InvalidCallSyntax;
    const close = std.mem.lastIndexOfScalar(u8, trimmed, ')') orelse return CallError.InvalidCallSyntax;
    if (close < open) return CallError.InvalidCallSyntax;
    if (std.mem.trim(u8, trimmed[close + 1 ..], " \t").len != 0) return CallError.InvalidCallSyntax;

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
        const fragments = try splitCallArgs(allocator, args_text);
        defer allocator.free(fragments);
        for (fragments) |fragment| {
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

fn parseSpecialCallBody(allocator: std.mem.Allocator, body: []const u8, callee_name: []const u8) !ParsedCall {
    const trimmed = std.mem.trim(u8, body, " \t");
    if (trimmed.len == 0) return CallError.InvalidCallSyntax;

    const open = std.mem.indexOfScalar(u8, trimmed, '(') orelse return CallError.InvalidCallSyntax;
    const close = std.mem.lastIndexOfScalar(u8, trimmed, ')') orelse return CallError.InvalidCallSyntax;
    if (close < open) return CallError.InvalidCallSyntax;
    if (std.mem.trim(u8, trimmed[close + 1 ..], " \t").len != 0) return CallError.InvalidCallSyntax;

    const prefix = std.mem.trim(u8, trimmed[0..open], " \t");
    if (!std.mem.eql(u8, prefix, callee_name)) return CallError.InvalidCallSyntax;

    var args_list = std.ArrayList(ParsedArg).init(allocator);
    errdefer {
        for (args_list.items) |arg| allocator.free(arg.text);
        args_list.deinit();
    }

    const args_text = std.mem.trim(u8, trimmed[open + 1 .. close], " \t");
    if (args_text.len != 0) {
        const fragments = try splitCallArgs(allocator, args_text);
        defer allocator.free(fragments);
        for (fragments) |fragment| {
            try args_list.append(try parseArg(allocator, fragment));
        }
    }

    return .{
        .dest = null,
        .callee = try allocator.dupe(u8, callee_name),
        .args = try args_list.toOwnedSlice(),
        .is_indirect = false,
    };
}

fn startsWithWord(s: []const u8, word: []const u8) bool {
    if (!std.mem.startsWith(u8, s, word)) return false;
    if (s.len == word.len) return true;
    const next = s[word.len];
    return std.ascii.isWhitespace(next) or next == '(' or next == '[' or next == ':' or next == '=' or next == '@' or next == '-';
}

fn isCallKeywordBoundary(c: u8) bool {
    return std.ascii.isWhitespace(c) or c == '=';
}

fn findCallKeyword(s: []const u8, keyword: []const u8) ?usize {
    var index: usize = 0;
    while (std.mem.indexOfPos(u8, s, index, keyword)) |found| {
        const before_ok = found == 0 or isCallKeywordBoundary(s[found - 1]);
        const after_index = found + keyword.len;
        const after_ok = after_index >= s.len or std.ascii.isWhitespace(s[after_index]);
        if (before_ok and after_ok) return found;
        index = found + keyword.len;
    }
    return null;
}

pub fn parseCall(allocator: std.mem.Allocator, raw_text: []const u8) !ParsedCall {
    const trimmed = std.mem.trim(u8, raw_text, " \t\r");
    if (trimmed.len == 0) return CallError.InvalidCallSyntax;

    if (startsWithWord(trimmed, "panic_msg")) {
        return parseSpecialCallBody(allocator, trimmed, "panic_msg");
    }
    if (startsWithWord(trimmed, "panic")) {
        return parseSpecialCallBody(allocator, trimmed, "panic");
    }

    const call_start = if (findCallKeyword(trimmed, "call_indirect")) |idx| idx else if (findCallKeyword(trimmed, "call")) |idx| idx else return CallError.InvalidCallSyntax;
    const prefix = std.mem.trim(u8, trimmed[0..call_start], " \t");
    var dest: ?[]const u8 = null;
    var dest2: ?[]const u8 = null;
    if (prefix.len != 0) {
        const eq = std.mem.indexOfScalar(u8, prefix, '=') orelse return CallError.InvalidCallSyntax;
        const name = std.mem.trim(u8, prefix[0..eq], " \t");
        const tail = std.mem.trim(u8, prefix[eq + 1 ..], " \t");
        if (name.len == 0 or tail.len != 0) return CallError.InvalidCallSyntax;
        if (std.mem.indexOfScalar(u8, name, ',')) |comma| {
            const left = std.mem.trim(u8, name[0..comma], " \t");
            const right = std.mem.trim(u8, name[comma + 1 ..], " \t");
            if (left.len == 0 or right.len == 0) return CallError.InvalidCallSyntax;
            if (std.mem.indexOfScalar(u8, right, ',') != null) return CallError.InvalidCallSyntax;
            dest = try allocator.dupe(u8, left);
            dest2 = try allocator.dupe(u8, right);
        } else {
            dest = try allocator.dupe(u8, name);
        }
    }
    errdefer if (dest) |value| allocator.free(value);
    errdefer if (dest2) |value| allocator.free(value);

    if (findCallKeyword(trimmed, "call_indirect")) |idx| {
        const body = std.mem.trimLeft(u8, trimmed[idx + "call_indirect".len ..], " \t");
        var call = try parseCallBody(allocator, body, true);
        call.dest = dest;
        call.dest2 = dest2;
        return call;
    }

    if (findCallKeyword(trimmed, "call")) |idx| {
        const body = std.mem.trimLeft(u8, trimmed[idx + "call".len ..], " \t");
        var call = try parseCallBody(allocator, body, false);
        call.dest = dest;
        call.dest2 = dest2;
        return call;
    }

    if (dest) |value| allocator.free(value);
    return CallError.InvalidCallSyntax;
}

pub fn parseInstructionCall(allocator: std.mem.Allocator, item: common_instruction.Instruction, symbols: anytype) !ParsedCall {
    if (item.raw_text.len != 0) return parseCall(allocator, item.raw_text);
    return switch (item.kind) {
        .call, .call_indirect => blk: {
            const has_dest = item.operands[0] == .reg;
            const body_operand = if (has_dest) item.operands[1] else item.operands[0];
            const body = operandTextFromInstruction(body_operand, symbols) orelse return CallError.InvalidCallSyntax;
            var parsed = try parseCallBody(allocator, body, item.kind == .call_indirect);
            errdefer parsed.deinit(allocator);
            if (has_dest) {
                parsed.dest = try allocator.dupe(u8, operandTextFromInstruction(item.operands[0], symbols) orelse return CallError.InvalidCallSyntax);
            }
            break :blk parsed;
        },
        .panic => blk: {
            var args = try allocator.alloc(ParsedArg, 1);
            errdefer allocator.free(args);
            args[0] = try parsedSpecialArgFromOperand(allocator, item.operands[0], symbols);
            break :blk .{ .dest = null, .callee = try allocator.dupe(u8, "panic"), .args = args, .is_indirect = false };
        },
        .panic_msg => blk: {
            if (item.operands[1] == .none and item.operands[2] == .none) {
                const text = operandTextFromInstruction(item.operands[0], symbols) orelse return CallError.InvalidCallSyntax;
                const trimmed = std.mem.trim(u8, text, " \t");
                if (startsWithWord(trimmed, "panic_msg")) {
                    break :blk try parseSpecialCallBody(allocator, trimmed, "panic_msg");
                }
                if (trimmed.len >= 2 and trimmed[0] == '(' and trimmed[trimmed.len - 1] == ')') {
                    const body = try std.fmt.allocPrint(allocator, "panic_msg{s}", .{trimmed});
                    defer allocator.free(body);
                    break :blk try parseSpecialCallBody(allocator, body, "panic_msg");
                }
            }
            var args = try allocator.alloc(ParsedArg, 3);
            errdefer allocator.free(args);
            var initialized: usize = 0;
            errdefer for (args[0..initialized]) |arg| allocator.free(arg.text);
            args[0] = try parsedArgFromOperand(allocator, item.operands[0], symbols);
            initialized += 1;
            args[1] = try parsedArgFromOperand(allocator, item.operands[1], symbols);
            initialized += 1;
            args[2] = try parsedArgFromOperand(allocator, item.operands[2], symbols);
            initialized += 1;
            break :blk .{ .dest = null, .callee = try allocator.dupe(u8, "panic_msg"), .args = args, .is_indirect = false };
        },
        else => CallError.InvalidCallSyntax,
    };
}

fn validatePrefix(expected: common_instruction.CapPrefix, actual: common_instruction.CapPrefix) bool {
    return expected == actual;
}

fn prefixText(prefix: common_instruction.CapPrefix) []const u8 {
    return switch (prefix) {
        .by_value => "",
        .borrow => "&",
        .move => "^",
        .raw => "*",
    };
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

    if (std.mem.eql(u8, call.callee, "panic")) {
        if (call.args.len != 1 or call.args[0].prefix != .by_value) return CallError.CapabilityMismatch;
        return call;
    }
    if (std.mem.eql(u8, call.callee, "panic_msg")) {
        if (call.args.len != 3 or call.args[0].prefix != .by_value or call.args[1].prefix != .raw or call.args[2].prefix != .by_value) {
            return CallError.CapabilityMismatch;
        }
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

test "parse and validate panic builtins" {
    var panic_call = try validateCall(std.testing.allocator, &.{}, "panic(7)");
    defer panic_call.deinit(std.testing.allocator);
    try std.testing.expectEqualStrings("panic", panic_call.callee);
    try std.testing.expectEqual(@as(usize, 1), panic_call.args.len);
    try std.testing.expectEqual(common_instruction.CapPrefix.by_value, panic_call.args[0].prefix);

    var msg_call = try validateCall(std.testing.allocator, &.{}, "panic_msg(7, *msg, len)");
    defer msg_call.deinit(std.testing.allocator);
    try std.testing.expectEqualStrings("panic_msg", msg_call.callee);
    try std.testing.expectEqual(@as(usize, 3), msg_call.args.len);
    try std.testing.expectEqual(common_instruction.CapPrefix.by_value, msg_call.args[0].prefix);
    try std.testing.expectEqual(common_instruction.CapPrefix.raw, msg_call.args[1].prefix);
    try std.testing.expectEqual(common_instruction.CapPrefix.by_value, msg_call.args[2].prefix);
}

const TestSymbols = struct {
    names: []const []const u8,

    pub fn lookupName(self: *const TestSymbols, id: u32) ?[]const u8 {
        const idx: usize = @intCast(id);
        if (idx >= self.names.len) return null;
        return self.names[idx];
    }
};

test "parseInstructionCall decodes structured call instructions without raw text" {
    const symbols = TestSymbols{ .names = &.{ "dst", "input" } };
    var item = common_instruction.makeInstruction(.call, 1, 0, null, "");
    item.operands[0] = .{ .reg = 0 };
    item.operands[1] = .{ .text = "@consume(^input)" };

    var parsed = try parseInstructionCall(std.testing.allocator, item, &symbols);
    defer parsed.deinit(std.testing.allocator);
    try std.testing.expectEqualStrings("dst", parsed.dest.?);
    try std.testing.expectEqualStrings("consume", parsed.callee);
    try std.testing.expectEqual(@as(usize, 1), parsed.args.len);
    try std.testing.expectEqual(common_instruction.CapPrefix.move, parsed.args[0].prefix);
    try std.testing.expectEqualStrings("input", parsed.args[0].text);
}

test "parseInstructionCall decodes structured panic instructions without raw text" {
    const symbols = TestSymbols{ .names = &.{ "code", "msg", "len" } };
    var panic_item = common_instruction.makeInstruction(.panic, 1, 0, null, "");
    panic_item.operands[0] = .{ .reg = 0 };

    var parsed_panic = try parseInstructionCall(std.testing.allocator, panic_item, &symbols);
    defer parsed_panic.deinit(std.testing.allocator);
    try std.testing.expectEqualStrings("panic", parsed_panic.callee);
    try std.testing.expectEqualStrings("code", parsed_panic.args[0].text);

    var panic_msg = common_instruction.makeInstruction(.panic_msg, 2, 1, null, "");
    panic_msg.operands[0] = .{ .reg = 0 };
    panic_msg.operands[1] = .{ .text = "*msg" };
    panic_msg.operands[2] = .{ .reg = 2 };

    var parsed_msg = try parseInstructionCall(std.testing.allocator, panic_msg, &symbols);
    defer parsed_msg.deinit(std.testing.allocator);
    try std.testing.expectEqualStrings("panic_msg", parsed_msg.callee);
    try std.testing.expectEqual(common_instruction.CapPrefix.raw, parsed_msg.args[1].prefix);
    try std.testing.expectEqualStrings("msg", parsed_msg.args[1].text);
    try std.testing.expectEqualStrings("len", parsed_msg.args[2].text);
}

test "parseInstructionCall decodes single operand structured panic_msg" {
    const symbols = TestSymbols{ .names = &.{} };
    var item = common_instruction.makeInstruction(.panic_msg, 1, 0, null, "");
    item.operands[0] = .{ .text = "(17, *RESULT_UNWRAP_PANIC, 39)" };

    var parsed = try parseInstructionCall(std.testing.allocator, item, &symbols);
    defer parsed.deinit(std.testing.allocator);
    try std.testing.expectEqualStrings("panic_msg", parsed.callee);
    try std.testing.expectEqual(@as(usize, 3), parsed.args.len);
    try std.testing.expectEqualStrings("17", parsed.args[0].text);
    try std.testing.expectEqual(common_instruction.CapPrefix.raw, parsed.args[1].prefix);
    try std.testing.expectEqualStrings("RESULT_UNWRAP_PANIC", parsed.args[1].text);
    try std.testing.expectEqualStrings("39", parsed.args[2].text);
}

test "parseCall rejects trailing garbage on special calls" {
    try std.testing.expectError(CallError.InvalidCallSyntax, parseCall(std.testing.allocator, "panic(7) extra"));
    try std.testing.expectError(CallError.InvalidCallSyntax, parseCall(std.testing.allocator, "panic_msg(7, *msg, len) trailing"));
}

test "parseCall keeps quoted commas inside arguments" {
    var call = try parseCall(std.testing.allocator, "call @sink(utf8:\"a,b\", *\"c,d\", len)");
    defer call.deinit(std.testing.allocator);

    try std.testing.expectEqualStrings("sink", call.callee);
    try std.testing.expectEqual(@as(usize, 3), call.args.len);
    try std.testing.expectEqual(common_instruction.CapPrefix.by_value, call.args[0].prefix);
    try std.testing.expectEqualStrings("utf8:\"a,b\"", call.args[0].text);
    try std.testing.expectEqual(common_instruction.CapPrefix.raw, call.args[1].prefix);
    try std.testing.expectEqualStrings("\"c,d\"", call.args[1].text);
    try std.testing.expectEqual(common_instruction.CapPrefix.by_value, call.args[2].prefix);
    try std.testing.expectEqualStrings("len", call.args[2].text);
}

test "parseCall does not treat call substring in destination as keyword" {
    var call = try parseCall(std.testing.allocator, "call_idx = call @sa_bytes_find(&body, body_len, &J_CALL_ID_KEY, J_CALL_ID_KEY_LEN)");
    defer call.deinit(std.testing.allocator);

    try std.testing.expectEqualStrings("call_idx", call.dest.?);
    try std.testing.expectEqualStrings("sa_bytes_find", call.callee);
    try std.testing.expectEqual(@as(usize, 4), call.args.len);
    try std.testing.expectEqual(common_instruction.CapPrefix.borrow, call.args[0].prefix);
    try std.testing.expectEqualStrings("body", call.args[0].text);
}

test "validateCall rejects capability mismatches" {
    var sigs = std.ArrayList(common_signature.FunctionSig).init(std.testing.allocator);
    defer {
        for (sigs.items) |*sig| sig.deinit(std.testing.allocator);
        sigs.deinit();
    }

    try sigs.append(try common_signature.parseFunctionSig(std.testing.allocator, "@sink(&p: ptr, ^q: ptr) -> i32:", 0, 0));
    try std.testing.expectError(CallError.CapabilityMismatch, validateCall(std.testing.allocator, sigs.items, "call @sink(^p, ^q)"));
    try std.testing.expectError(CallError.CapabilityMismatch, validateCall(std.testing.allocator, sigs.items, "call @sink(&p)"));
}

test "call contract PBT matches random capability signatures" {
    var prng = std.Random.DefaultPrng.init(0x5A5A_6120);
    const random = prng.random();
    const caps = [_]common_instruction.CapPrefix{ .by_value, .borrow, .move, .raw };

    for (0..96) |iter| {
        const param_count = random.intRangeAtMost(usize, 1, 3);
        var sig_text = std.ArrayList(u8).init(std.testing.allocator);
        defer sig_text.deinit();
        var call_text = std.ArrayList(u8).init(std.testing.allocator);
        defer call_text.deinit();

        try sig_text.writer().writeAll("@sink(");
        try call_text.writer().writeAll("call @sink(");

        var expect_ok = true;
        for (0..param_count) |idx| {
            if (idx != 0) {
                try sig_text.writer().writeAll(", ");
                try call_text.writer().writeAll(", ");
            }

            const param_cap = caps[random.intRangeLessThan(usize, 0, caps.len)];
            const arg_cap = caps[random.intRangeLessThan(usize, 0, caps.len)];
            if (param_cap != arg_cap) expect_ok = false;

            try sig_text.writer().print("{s}p{d}: ptr", .{ prefixText(param_cap), idx });
            try call_text.writer().print("{s}p{d}", .{ prefixText(arg_cap), idx });
        }
        try sig_text.writer().writeAll(") -> i32:");
        try call_text.writer().writeByte(')');

        var sigs = std.ArrayList(common_signature.FunctionSig).init(std.testing.allocator);
        defer {
            for (sigs.items) |*sig| sig.deinit(std.testing.allocator);
            sigs.deinit();
        }
        try sigs.append(try common_signature.parseFunctionSig(std.testing.allocator, sig_text.items, @intCast(iter), 0));

        if (expect_ok) {
            var parsed = try validateCall(std.testing.allocator, sigs.items, call_text.items);
            defer parsed.deinit(std.testing.allocator);
            try std.testing.expectEqual(param_count, parsed.args.len);
        } else {
            try std.testing.expectError(CallError.CapabilityMismatch, validateCall(std.testing.allocator, sigs.items, call_text.items));
        }
    }
}
