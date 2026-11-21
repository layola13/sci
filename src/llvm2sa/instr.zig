// Per-instruction lowering from LLVM IR to SA text.
const std = @import("std");
const trim = @import("text.zig").trim;
const sanitizeIdent = @import("text.zig").sanitizeIdent;
const labelName = @import("text.zig").labelName;
const findMatching = @import("text.zig").findMatching;
const splitTopLevelComma = @import("text.zig").splitTopLevelComma;
const cleanInstructionLine = @import("text.zig").cleanInstructionLine;
const startsWithWord = @import("text.zig").startsWithWord;
const typeTokenToSa = @import("types.zig").typeTokenToSa;
const firstTypeToken = @import("types.zig").firstTypeToken;
const typeBytes = @import("types.zig").typeBytes;
const arrayElementType = @import("types.zig").arrayElementType;
const structFieldOffset = @import("types.zig").structFieldOffset;
const arrayBoundFromType = @import("types.zig").arrayBoundFromType;
const structFieldType = @import("types.zig").structFieldType;
const parseLlvmInteger = @import("types.zig").parseLlvmInteger;
const llvmTypedValueToValue = @import("values.zig").llvmTypedValueToValue;
const saValue = @import("values.zig").saValue;
const appendValue = @import("values.zig").appendValue;
const appendPointerOperand = @import("values.zig").appendPointerOperand;
const parseConstantGepBase = @import("values.zig").parseConstantGepBase;

pub fn llvmBinaryOpToSa(op: []const u8) ?[]const u8 {
    inline for ([_]struct { llvm: []const u8, sa: []const u8 }{
        .{ .llvm = "add", .sa = "add" },
        .{ .llvm = "sub", .sa = "sub" },
        .{ .llvm = "mul", .sa = "mul" },
        .{ .llvm = "sdiv", .sa = "sdiv" },
        .{ .llvm = "udiv", .sa = "udiv" },
        .{ .llvm = "srem", .sa = "srem" },
        .{ .llvm = "urem", .sa = "urem" },
        .{ .llvm = "and", .sa = "and" },
        .{ .llvm = "or", .sa = "or" },
        .{ .llvm = "xor", .sa = "xor" },
        .{ .llvm = "shl", .sa = "shl" },
        .{ .llvm = "lshr", .sa = "lshr" },
        .{ .llvm = "ashr", .sa = "ashr" },
    }) |item| {
        if (std.mem.eql(u8, op, item.llvm)) return item.sa;
    }
    return null;
}

pub fn llvmIcmpToSa(pred: []const u8) ?[]const u8 {
    inline for ([_]struct { llvm: []const u8, sa: []const u8 }{
        .{ .llvm = "eq", .sa = "eq" },
        .{ .llvm = "ne", .sa = "ne" },
        .{ .llvm = "slt", .sa = "slt" },
        .{ .llvm = "sle", .sa = "sle" },
        .{ .llvm = "sgt", .sa = "sgt" },
        .{ .llvm = "sge", .sa = "sge" },
        .{ .llvm = "ult", .sa = "ult" },
        .{ .llvm = "ule", .sa = "ule" },
        .{ .llvm = "ugt", .sa = "ugt" },
        .{ .llvm = "uge", .sa = "uge" },
    }) |item| {
        if (std.mem.eql(u8, pred, item.llvm)) return item.sa;
    }
    return null;
}

pub fn skipOverflowFlags(text: []const u8) []const u8 {
    var rest = trim(text);
    while (true) {
        const first_space = std.mem.indexOfAny(u8, rest, " \t") orelse return rest;
        const word = rest[0..first_space];
        if (!(std.mem.eql(u8, word, "nsw") or std.mem.eql(u8, word, "nuw") or std.mem.eql(u8, word, "exact"))) return rest;
        rest = trim(rest[first_space..]);
    }
}

pub fn appendBinaryOp(out: *std.array_list.Managed(u8), allocator: std.mem.Allocator, lhs: []const u8, op: []const u8, rest: []const u8) !void {
    const sa_op = llvmBinaryOpToSa(op) orelse return error.UnsupportedInstruction;
    const body = skipOverflowFlags(rest);
    const ty_token = firstTypeToken(body) orelse return error.UnsupportedInstruction;
    const after_ty = trim(body[(std.mem.indexOf(u8, body, ty_token) orelse 0) + ty_token.len ..]);
    const args = try splitTopLevelComma(allocator, after_ty);
    defer allocator.free(args);
    if (args.len != 2) return error.UnsupportedInstruction;

    const dst = try sanitizeIdent(allocator, lhs, "r");
    defer allocator.free(dst);
    try out.print("  {s} = {s} ", .{ dst, sa_op });
    try appendValue(out, allocator, args[0]);
    try out.appendSlice(", ");
    try appendValue(out, allocator, args[1]);
    try out.append('\n');
}

pub fn appendIcmp(out: *std.array_list.Managed(u8), allocator: std.mem.Allocator, lhs: []const u8, rest: []const u8) !void {
    var parts = std.mem.tokenizeAny(u8, rest, " \t\r\n");
    const pred = parts.next() orelse return error.InvalidIr;
    const sa_op = llvmIcmpToSa(pred) orelse return error.UnsupportedInstruction;
    const ty_token = parts.next() orelse return error.UnsupportedInstruction;
    if (typeTokenToSa(ty_token) == null) return error.UnsupportedInstruction;
    const after_ty_start = std.mem.indexOf(u8, rest, ty_token) orelse return error.InvalidIr;
    const args_text = trim(rest[after_ty_start + ty_token.len ..]);
    const args = try splitTopLevelComma(allocator, args_text);
    defer allocator.free(args);
    if (args.len != 2) return error.UnsupportedInstruction;

    const dst = try sanitizeIdent(allocator, lhs, "r");
    defer allocator.free(dst);
    try out.print("  {s} = {s} ", .{ dst, sa_op });
    try appendValue(out, allocator, args[0]);
    try out.appendSlice(", ");
    try appendValue(out, allocator, args[1]);
    try out.append('\n');
}

pub fn appendAlloca(out: *std.array_list.Managed(u8), allocator: std.mem.Allocator, lhs: []const u8, rest: []const u8) !void {
    const comma = std.mem.indexOfScalar(u8, rest, ',') orelse rest.len;
    const alloc_ty = trim(rest[0..comma]);
    const size = typeBytes(alloc_ty) orelse return error.UnsupportedInstruction;
    const dst = try sanitizeIdent(allocator, lhs, "r");
    defer allocator.free(dst);
    try out.print("  {s} = stack_alloc {d}\n", .{ dst, size });
}

pub fn appendLoad(out: *std.array_list.Managed(u8), allocator: std.mem.Allocator, lhs: []const u8, rest: []const u8) !void {
    const args = try splitTopLevelComma(allocator, rest);
    defer allocator.free(args);
    if (args.len < 2) return error.UnsupportedInstruction;

    const value_ty = firstTypeToken(args[0]) orelse return error.UnsupportedInstruction;
    const sa_ty = typeTokenToSa(value_ty) orelse return error.UnsupportedInstruction;
    const dst = try sanitizeIdent(allocator, lhs, "r");
    defer allocator.free(dst);
    const base = try appendPointerOperand(out, allocator, args[1], dst);
    defer allocator.free(base);
    try out.print("  {s} = load {s}+0 as {s}\n", .{ dst, base, sa_ty });
}

pub fn appendStore(out: *std.array_list.Managed(u8), allocator: std.mem.Allocator, rest: []const u8) !void {
    const args = try splitTopLevelComma(allocator, rest);
    defer allocator.free(args);
    if (args.len < 2) return error.UnsupportedInstruction;

    const value_ty = firstTypeToken(args[0]) orelse return error.UnsupportedInstruction;
    const sa_ty = typeTokenToSa(value_ty) orelse return error.UnsupportedInstruction;
    const value = try saValue(allocator, args[0]);
    defer allocator.free(value);
    const hint = try std.fmt.allocPrint(allocator, "store_{d}", .{out.items.len});
    defer allocator.free(hint);
    const base = try appendPointerOperand(out, allocator, args[1], hint);
    defer allocator.free(base);
    try out.print("  store {s}+0, {s} as {s}\n", .{ base, value, sa_ty });
}

pub fn appendBranch(out: *std.array_list.Managed(u8), allocator: std.mem.Allocator, rest: []const u8) !void {
    const t = trim(rest);
    if (std.mem.startsWith(u8, t, "label ")) {
        const label = try labelName(allocator, llvmTypedValueToValue(t["label ".len..]));
        defer allocator.free(label);
        try out.print("  jmp {s}\n", .{label});
        return;
    }

    const args = try splitTopLevelComma(allocator, t);
    defer allocator.free(args);
    if (args.len != 3) return error.UnsupportedInstruction;
    const cond = try saValue(allocator, args[0]);
    defer allocator.free(cond);
    const true_label = try labelName(allocator, llvmTypedValueToValue(args[1]));
    defer allocator.free(true_label);
    const false_label = try labelName(allocator, llvmTypedValueToValue(args[2]));
    defer allocator.free(false_label);
    try out.print("  br {s} -> {s}, {s}\n", .{ cond, true_label, false_label });
}

pub fn appendReturn(out: *std.array_list.Managed(u8), allocator: std.mem.Allocator, rest: []const u8) !void {
    const t = trim(rest);
    if (std.mem.eql(u8, t, "void") or t.len == 0) {
        try out.appendSlice("  return\n");
        return;
    }
    try out.appendSlice("  return ");
    try appendValue(out, allocator, t);
    try out.append('\n');
}

pub fn appendCast(out: *std.array_list.Managed(u8), allocator: std.mem.Allocator, lhs: []const u8, op: []const u8, rest: []const u8) !void {
    const to_idx = std.mem.lastIndexOf(u8, rest, " to ") orelse return error.UnsupportedInstruction;
    const source = trim(rest[0..to_idx]);
    const dest_ty_text = trim(rest[to_idx + 4 ..]);
    const dest_ty_token = firstTypeToken(dest_ty_text) orelse return error.UnsupportedInstruction;
    const dest_ty = typeTokenToSa(dest_ty_token) orelse return error.UnsupportedInstruction;
    const dst = try sanitizeIdent(allocator, lhs, "r");
    defer allocator.free(dst);
    try out.print("  {s} = {s} ", .{ dst, op });
    try appendValue(out, allocator, source);
    try out.print(" as {s}\n", .{dest_ty});
}

pub fn appendSelect(out: *std.array_list.Managed(u8), allocator: std.mem.Allocator, lhs: []const u8, rest: []const u8) !void {
    const args = try splitTopLevelComma(allocator, rest);
    defer allocator.free(args);
    if (args.len != 3) return error.UnsupportedInstruction;

    const cond_ty = firstTypeToken(args[0]) orelse return error.UnsupportedInstruction;
    if (!std.mem.eql(u8, typeTokenToSa(cond_ty) orelse return error.UnsupportedInstruction, "i1")) {
        return error.UnsupportedInstruction;
    }

    const true_ty = firstTypeToken(args[1]) orelse return error.UnsupportedInstruction;
    const false_ty = firstTypeToken(args[2]) orelse return error.UnsupportedInstruction;
    const sa_ty = typeTokenToSa(true_ty) orelse return error.UnsupportedInstruction;
    if (!std.mem.eql(u8, sa_ty, typeTokenToSa(false_ty) orelse return error.UnsupportedInstruction)) {
        return error.UnsupportedInstruction;
    }
    const size = typeBytes(true_ty) orelse return error.UnsupportedInstruction;

    const dst = try sanitizeIdent(allocator, lhs, "r");
    defer allocator.free(dst);
    const slot = try std.fmt.allocPrint(allocator, "bc2sa_select_slot_{s}", .{dst});
    defer allocator.free(slot);
    const true_label = try std.fmt.allocPrint(allocator, "L_BC2SA_SELECT_TRUE_{s}", .{dst});
    defer allocator.free(true_label);
    const false_label = try std.fmt.allocPrint(allocator, "L_BC2SA_SELECT_FALSE_{s}", .{dst});
    defer allocator.free(false_label);
    const join_label = try std.fmt.allocPrint(allocator, "L_BC2SA_SELECT_JOIN_{s}", .{dst});
    defer allocator.free(join_label);

    try out.print("  {s} = stack_alloc {d}\n", .{ slot, size });
    try out.appendSlice("  br ");
    try appendValue(out, allocator, args[0]);
    try out.print(" -> {s}, {s}\n", .{ true_label, false_label });

    try out.print("{s}:\n", .{true_label});
    try out.print("  store {s}+0, ", .{slot});
    try appendValue(out, allocator, args[1]);
    try out.print(" as {s}\n", .{sa_ty});
    try out.print("  jmp {s}\n", .{join_label});

    try out.print("{s}:\n", .{false_label});
    try out.print("  store {s}+0, ", .{slot});
    try appendValue(out, allocator, args[2]);
    try out.print(" as {s}\n", .{sa_ty});
    try out.print("  jmp {s}\n", .{join_label});

    try out.print("{s}:\n", .{join_label});
    try out.print("  {s} = load {s}+0 as {s}\n", .{ dst, slot, sa_ty });
}

pub fn appendGetElementPtr(out: *std.array_list.Managed(u8), allocator: std.mem.Allocator, lhs: []const u8, rest: []const u8) !void {
    var body = trim(rest);
    if (std.mem.startsWith(u8, body, "inbounds ")) body = trim(body["inbounds ".len..]);
    const args = try splitTopLevelComma(allocator, body);
    defer allocator.free(args);
    if (args.len < 3) return error.UnsupportedInstruction;

    const dst = try sanitizeIdent(allocator, lhs, "r");
    defer allocator.free(dst);
    var base: []u8 = undefined;
    var base_offset: i128 = 0;
    if (std.mem.indexOf(u8, args[1], "getelementptr")) |gep_index| {
        const parsed_base = try parseConstantGepBase(allocator, trim(args[1][gep_index..]));
        defer allocator.free(parsed_base.name);
        base = try std.fmt.allocPrint(allocator, "&{s}", .{parsed_base.name});
        base_offset = parsed_base.offset;
    } else {
        base = try saValue(allocator, args[1]);
    }
    defer allocator.free(base);
    var current_type = trim(args[0]);
    var offset_expr: ?[]u8 = if (base_offset != 0) try std.fmt.allocPrint(allocator, "{d}", .{base_offset}) else null;
    defer if (offset_expr) |expr| allocator.free(expr);
    var term_id: usize = 0;

    for (args[2..], 0..) |index_arg, index| {
        const raw_index = llvmTypedValueToValue(index_arg);
        const constant_index = parseLlvmInteger(raw_index);
        var stride: u64 = 0;
        var struct_offset: ?u64 = null;
        if (index == 0) {
            stride = typeBytes(current_type) orelse return error.UnsupportedInstruction;
        } else if (arrayElementType(current_type)) |element_type| {
            stride = typeBytes(element_type) orelse return error.UnsupportedInstruction;
        } else {
            const field_index = constant_index orelse return error.UnsupportedInstruction;
            struct_offset = structFieldOffset(current_type, @intCast(field_index)) orelse return error.UnsupportedInstruction;
        }

        if (index == 0 and arrayElementType(current_type) != null) {
            if (constant_index) |value| {
                if (value != 0) return error.StaticMemoryOverflow;
            }
        }
        if (index != 0 and arrayElementType(current_type) != null) {
            if (constant_index) |value| {
                const bound = arrayBoundFromType(current_type) orelse return error.UnsupportedInstruction;
                if (value < 0 or value >= @as(i128, @intCast(bound))) return error.StaticMemoryOverflow;
            }
            current_type = arrayElementType(current_type).?;
        } else if (index != 0) {
            const field_index = constant_index.?;
            current_type = structFieldType(current_type, @intCast(field_index)) orelse return error.UnsupportedInstruction;
        }

        var term: []u8 = undefined;
        if (struct_offset) |field_offset| {
            term = try std.fmt.allocPrint(allocator, "{d}", .{field_offset});
        } else if (constant_index) |value| {
            const byte_offset = std.math.mul(i128, value, @as(i128, @intCast(stride))) catch return error.UnsupportedInstruction;
            term = try std.fmt.allocPrint(allocator, "{d}", .{byte_offset});
        } else {
            const value = try saValue(allocator, raw_index);
            defer allocator.free(value);
            if (stride == 1) {
                term = try allocator.dupe(u8, value);
            } else {
                const temp = try std.fmt.allocPrint(allocator, "bc2sa_gep_term_{s}_{d}", .{ dst, term_id });
                defer allocator.free(temp);
                try out.print("  {s} = mul {s}, {d}\n", .{ temp, value, stride });
                term = try allocator.dupe(u8, temp);
            }
            term_id += 1;
        }

        if (offset_expr) |previous| {
            const sum = try std.fmt.allocPrint(allocator, "bc2sa_gep_offset_{s}_{d}", .{ dst, term_id });
            try out.print("  {s} = add {s}, {s}\n", .{ sum, previous, term });
            allocator.free(previous);
            allocator.free(term);
            offset_expr = sum;
        } else {
            offset_expr = term;
        }
    }

    const offset = offset_expr orelse try allocator.dupe(u8, "0");
    if (offset_expr == null) offset_expr = offset;
    try out.print("  {s} = ptr_add {s}, {s}\n", .{ dst, base, offset });
}

pub fn appendCall(out: *std.array_list.Managed(u8), allocator: std.mem.Allocator, lhs: ?[]const u8, rest: []const u8) !void {
    const call_idx = std.mem.indexOf(u8, rest, "call ") orelse return error.UnsupportedInstruction;
    const call_text = trim(rest[call_idx + "call ".len ..]);
    const at = std.mem.indexOfScalar(u8, call_text, '@');
    const open = if (at) |at_index|
        at_index + (std.mem.indexOfScalar(u8, call_text[at_index..], '(') orelse return error.InvalidIr)
    else
        std.mem.indexOfScalar(u8, call_text, '(') orelse return error.InvalidIr;
    const close = findMatching(call_text, open, '(', ')') orelse return error.InvalidIr;
    const indirect = at == null;
    const callee = if (at) |at_index|
        try sanitizeIdent(allocator, call_text[at_index..open], "fn_")
    else
        try saValue(allocator, call_text[0..open]);
    defer allocator.free(callee);

    if (lhs) |lhs_text| {
        const dst = try sanitizeIdent(allocator, lhs_text, "r");
        defer allocator.free(dst);
        if (indirect) {
            try out.print("  {s} = call_indirect {s}(", .{ dst, callee });
        } else {
            try out.print("  {s} = call @{s}(", .{ dst, callee });
        }
    } else {
        if (indirect) {
            try out.print("  call_indirect {s}(", .{callee});
        } else {
            try out.print("  call @{s}(", .{callee});
        }
    }

    const args = try splitTopLevelComma(allocator, call_text[open + 1 .. close]);
    defer allocator.free(args);
    for (args, 0..) |arg, idx| {
        if (idx != 0) try out.appendSlice(", ");
        const hint = try std.fmt.allocPrint(allocator, "call_{d}_{d}", .{ out.items.len, idx });
        defer allocator.free(hint);
        if (std.mem.indexOf(u8, arg, "getelementptr") != null) {
            const pointer = try appendPointerOperand(out, allocator, arg, hint);
            defer allocator.free(pointer);
            try out.appendSlice(pointer);
        } else {
            try appendValue(out, allocator, arg);
        }
    }
    try out.appendSlice(")\n");
}

pub fn appendAssignmentInstruction(out: *std.array_list.Managed(u8), allocator: std.mem.Allocator, lhs: []const u8, rhs: []const u8) !void {
    var words = std.mem.tokenizeAny(u8, rhs, " \t\r\n");
    const op = words.next() orelse return error.InvalidIr;
    const rest_start = std.mem.indexOf(u8, rhs, op) orelse return error.InvalidIr;
    const rest = trim(rhs[rest_start + op.len ..]);

    if (std.mem.eql(u8, op, "phi")) return error.UnsupportedPhi;
    if (llvmBinaryOpToSa(op) != null) return appendBinaryOp(out, allocator, lhs, op, rest);
    if (std.mem.eql(u8, op, "icmp")) return appendIcmp(out, allocator, lhs, rest);
    if (std.mem.eql(u8, op, "alloca")) return appendAlloca(out, allocator, lhs, rest);
    if (std.mem.eql(u8, op, "load")) return appendLoad(out, allocator, lhs, rest);
    if (std.mem.eql(u8, op, "getelementptr")) return appendGetElementPtr(out, allocator, lhs, rest);
    if (std.mem.eql(u8, op, "select")) return appendSelect(out, allocator, lhs, rest);
    if (std.mem.eql(u8, op, "call") or std.mem.indexOf(u8, rhs, " call ") != null) return appendCall(out, allocator, lhs, rhs);
    if (std.mem.eql(u8, op, "trunc") or std.mem.eql(u8, op, "zext") or std.mem.eql(u8, op, "sext") or std.mem.eql(u8, op, "bitcast") or std.mem.eql(u8, op, "ptrtoint") or std.mem.eql(u8, op, "inttoptr") or std.mem.eql(u8, op, "addrspacecast")) {
        const sa_op = if (std.mem.eql(u8, op, "ptrtoint") or std.mem.eql(u8, op, "inttoptr") or std.mem.eql(u8, op, "addrspacecast")) "bitcast" else op;
        return appendCast(out, allocator, lhs, sa_op, rest);
    }

    return error.UnsupportedInstruction;
}

pub fn appendInstruction(out: *std.array_list.Managed(u8), allocator: std.mem.Allocator, line: []const u8) !void {
    const cleaned = cleanInstructionLine(line);
    const t = trim(cleaned);
    if (t.len == 0) return;

    if (std.mem.indexOfScalar(u8, t, '=')) |eq_idx| {
        const lhs = trim(t[0..eq_idx]);
        const rhs = trim(t[eq_idx + 1 ..]);
        return appendAssignmentInstruction(out, allocator, lhs, rhs);
    }

    if (startsWithWord(t, "ret")) return appendReturn(out, allocator, t["ret".len..]);
    if (startsWithWord(t, "br")) return appendBranch(out, allocator, t["br".len..]);
    if (startsWithWord(t, "store")) return appendStore(out, allocator, t["store".len..]);
    if (std.mem.indexOf(u8, t, "call ") != null) return appendCall(out, allocator, null, t);

    return error.UnsupportedInstruction;
}

pub fn appendSwitch(out: *std.array_list.Managed(u8), allocator: std.mem.Allocator, text: []const u8, switch_id: usize) !void {
    const open = std.mem.indexOfScalar(u8, text, '[') orelse return error.UnsupportedInstruction;
    const close = std.mem.lastIndexOfScalar(u8, text, ']') orelse return error.InvalidIr;
    if (close < open) return error.InvalidIr;

    const header = try splitTopLevelComma(allocator, trim(text["switch".len..open]));
    defer allocator.free(header);
    if (header.len != 2) return error.UnsupportedInstruction;
    const switch_ty = firstTypeToken(header[0]) orelse return error.UnsupportedInstruction;
    const sa_ty = typeTokenToSa(switch_ty) orelse return error.UnsupportedInstruction;
    const switch_value = try saValue(allocator, header[0]);
    defer allocator.free(switch_value);
    const default_text = trim(header[1]);
    if (!std.mem.startsWith(u8, default_text, "label ")) return error.UnsupportedInstruction;
    const default_label = try labelName(allocator, llvmTypedValueToValue(default_text["label ".len..]));
    defer allocator.free(default_label);

    var cases = std.array_list.Managed([]const []const u8).init(allocator);
    defer {
        for (cases.items) |parts| allocator.free(parts);
        cases.deinit();
    }
    var case_lines = std.mem.splitScalar(u8, text[open + 1 .. close], '\n');
    while (case_lines.next()) |raw_case| {
        const case_line = trim(raw_case);
        if (case_line.len == 0) continue;
        {
            const parts = try splitTopLevelComma(allocator, case_line);
            defer allocator.free(parts);
            if (parts.len == 0 or parts.len % 2 != 0) return error.UnsupportedInstruction;
            var part_idx: usize = 0;
            while (part_idx < parts.len) : (part_idx += 2) {
                const pair = try allocator.alloc([]const u8, 2);
                pair[0] = parts[part_idx];
                pair[1] = parts[part_idx + 1];
                cases.append(pair) catch |err| {
                    allocator.free(pair);
                    return err;
                };
            }
        }
    }

    if (cases.items.len == 0) {
        try out.print("  jmp {s}\n", .{default_label});
        return;
    }

    for (cases.items, 0..) |parts, idx| {
        const case_ty = firstTypeToken(parts[0]) orelse return error.UnsupportedInstruction;
        if (!std.mem.eql(u8, sa_ty, typeTokenToSa(case_ty) orelse return error.UnsupportedInstruction)) {
            return error.UnsupportedInstruction;
        }
        const case_value = try saValue(allocator, parts[0]);
        defer allocator.free(case_value);
        const case_label_text = trim(parts[1]);
        if (!std.mem.startsWith(u8, case_label_text, "label ")) return error.UnsupportedInstruction;
        const case_label = try labelName(allocator, llvmTypedValueToValue(case_label_text["label ".len..]));
        defer allocator.free(case_label);

        const cmp_name = try std.fmt.allocPrint(allocator, "bc2sa_switch_cmp_{d}_{d}", .{ switch_id, idx });
        defer allocator.free(cmp_name);
        try out.print("  {s} = eq {s}, {s}\n", .{ cmp_name, switch_value, case_value });

        if (idx + 1 == cases.items.len) {
            try out.print("  br {s} -> {s}, {s}\n", .{ cmp_name, case_label, default_label });
        } else {
            const next_label = try std.fmt.allocPrint(allocator, "L_BC2SA_SWITCH_NEXT_{d}_{d}", .{ switch_id, idx });
            defer allocator.free(next_label);
            try out.print("  br {s} -> {s}, {s}\n", .{ cmp_name, case_label, next_label });
            try out.print("{s}:\n", .{next_label});
        }
    }
}
