// LLVM value / operand translation and function headers.
const std = @import("std");
const trim = @import("text.zig").trim;
const sanitizeIdent = @import("text.zig").sanitizeIdent;
const labelName = @import("text.zig").labelName;
const findMatching = @import("text.zig").findMatching;
const splitTopLevelComma = @import("text.zig").splitTopLevelComma;
const startsWithWord = @import("text.zig").startsWithWord;
const typeTokenToSa = @import("types.zig").typeTokenToSa;
const firstTypeToken = @import("types.zig").firstTypeToken;
const returnTypeFromPrefix = @import("types.zig").returnTypeFromPrefix;
const parseLlvmInteger = @import("types.zig").parseLlvmInteger;
const arrayElementType = @import("types.zig").arrayElementType;
const typeBytes = @import("types.zig").typeBytes;
const structFieldOffset = @import("types.zig").structFieldOffset;
const structFieldType = @import("types.zig").structFieldType;
const arrayBoundFromType = @import("types.zig").arrayBoundFromType;

pub fn llvmTypedValueToValue(text: []const u8) []const u8 {
    const t = trim(text);
    if (t.len == 0) return t;
    if (std.mem.indexOf(u8, t, "getelementptr")) |gep_idx| return trim(t[gep_idx..]);

    var parts = std.mem.tokenizeAny(u8, t, " \t\r\n");
    var last: []const u8 = t;
    while (parts.next()) |part| {
        last = part;
    }

    if (std.mem.startsWith(u8, last, "%") or std.mem.startsWith(u8, last, "@")) return last;
    if (std.mem.eql(u8, last, "null") or std.mem.eql(u8, last, "true") or std.mem.eql(u8, last, "false")) return last;
    if (std.fmt.parseInt(i64, last, 10)) |_| return last else |_| {}
    if (std.fmt.parseFloat(f64, last)) |_| return last else |_| {}
    if (std.mem.startsWith(u8, last, "0x")) return last;
    return t;
}

pub fn saValue(allocator: std.mem.Allocator, raw: []const u8) ![]u8 {
    var value = trim(raw);
    value = trim(std.mem.trimEnd(u8, value, ","));
    value = llvmTypedValueToValue(value);

    if (value.len == 0) return error.InvalidIr;
    if (std.mem.startsWith(u8, value, "%")) return sanitizeIdent(allocator, value, "r");
    if (std.mem.startsWith(u8, value, "@")) {
        const name = try sanitizeIdent(allocator, value, "g_");
        defer allocator.free(name);
        return try std.fmt.allocPrint(allocator, "&{s}", .{name});
    }
    if (std.mem.eql(u8, value, "null") or std.mem.eql(u8, value, "zeroinitializer")) return try allocator.dupe(u8, "0");
    if (std.mem.eql(u8, value, "true")) return try allocator.dupe(u8, "1");
    if (std.mem.eql(u8, value, "false")) return try allocator.dupe(u8, "0");
    if (std.fmt.parseInt(i64, value, 10)) |_| return try allocator.dupe(u8, value) else |_| {}
    if (std.fmt.parseFloat(f64, value)) |number| return try std.fmt.allocPrint(allocator, "{d}", .{number}) else |_| {}
    if (std.mem.startsWith(u8, value, "0x")) {
        if (std.fmt.parseInt(u64, value[2..], 16)) |bits| {
            const number: f64 = @bitCast(bits);
            return try std.fmt.allocPrint(allocator, "{d}", .{number});
        } else |_| {}
    }

    if (std.mem.startsWith(u8, value, "getelementptr")) {
        return try saGetElementPtrConstant(allocator, value);
    }

    return error.UnsupportedInstruction;
}

pub fn saGetElementPtrConstant(allocator: std.mem.Allocator, expr: []const u8) ![]u8 {
    const open = std.mem.indexOfScalar(u8, expr, '(') orelse return error.UnsupportedInstruction;
    const close = findMatching(expr, open, '(', ')') orelse return error.UnsupportedInstruction;
    const args = try splitTopLevelComma(allocator, expr[open + 1 .. close]);
    defer allocator.free(args);
    if (args.len < 2) return error.UnsupportedInstruction;

    const base = llvmTypedValueToValue(args[1]);
    if (!std.mem.startsWith(u8, base, "@")) return error.UnsupportedInstruction;
    const name = try sanitizeIdent(allocator, base, "g_");
    defer allocator.free(name);
    const offset = try gepConstantOffset(allocator, args[0], args[2..]);
    if (offset != 0) return error.UnsupportedInstruction;
    return try std.fmt.allocPrint(allocator, "&{s}", .{name});
}

pub fn parseConstantGepBase(allocator: std.mem.Allocator, expr: []const u8) !struct { name: []u8, offset: i128 } {
    const open = std.mem.indexOfScalar(u8, expr, '(') orelse return error.UnsupportedInstruction;
    const close = findMatching(expr, open, '(', ')') orelse return error.UnsupportedInstruction;
    const args = try splitTopLevelComma(allocator, expr[open + 1 .. close]);
    defer allocator.free(args);
    if (args.len < 2) return error.UnsupportedInstruction;
    const base = llvmTypedValueToValue(args[1]);
    if (!std.mem.startsWith(u8, base, "@")) return error.UnsupportedInstruction;
    const name = try sanitizeIdent(allocator, base, "g_");
    errdefer allocator.free(name);
    return .{ .name = name, .offset = try gepConstantOffset(allocator, args[0], args[2..]) };
}

pub fn gepConstantOffset(allocator: std.mem.Allocator, source_type: []const u8, index_args: []const []const u8) !i128 {
    _ = allocator;
    var current_type = trim(source_type);
    var offset: i128 = 0;

    for (index_args, 0..) |index_arg, index| {
        const raw_index = llvmTypedValueToValue(index_arg);
        const value = parseLlvmInteger(raw_index) orelse return error.UnsupportedInstruction;

        if (index == 0) {
            if (arrayElementType(current_type) != null and value != 0) return error.StaticMemoryOverflow;
            const stride = typeBytes(current_type) orelse return error.UnsupportedInstruction;
            const delta = std.math.mul(i128, value, @as(i128, @intCast(stride))) catch return error.UnsupportedInstruction;
            offset = std.math.add(i128, offset, delta) catch return error.UnsupportedInstruction;
            continue;
        }

        if (arrayElementType(current_type)) |element_type| {
            const bound = arrayBoundFromType(current_type) orelse return error.UnsupportedInstruction;
            if (value < 0 or value >= @as(i128, @intCast(bound))) return error.StaticMemoryOverflow;
            const stride = typeBytes(element_type) orelse return error.UnsupportedInstruction;
            const delta = std.math.mul(i128, value, @as(i128, @intCast(stride))) catch return error.UnsupportedInstruction;
            offset = std.math.add(i128, offset, delta) catch return error.UnsupportedInstruction;
            current_type = element_type;
            continue;
        }

        {
            const field_index = value;
            const field_offset = structFieldOffset(current_type, @intCast(field_index)) orelse return error.UnsupportedInstruction;
            offset = std.math.add(i128, offset, @intCast(field_offset)) catch return error.UnsupportedInstruction;
            current_type = structFieldType(current_type, @intCast(field_index)) orelse return error.UnsupportedInstruction;
            continue;
        }

        return error.UnsupportedInstruction;
    }

    return offset;
}

pub fn appendPointerOperand(out: *std.array_list.Managed(u8), allocator: std.mem.Allocator, raw: []const u8, hint: []const u8) ![]u8 {
    if (std.mem.indexOf(u8, raw, "getelementptr")) |gep_index| {
        const parsed = try parseConstantGepBase(allocator, trim(raw[gep_index..]));
        defer allocator.free(parsed.name);
        const base = try std.fmt.allocPrint(allocator, "&{s}", .{parsed.name});
        defer allocator.free(base);
        const pointer = try std.fmt.allocPrint(allocator, "bc2sa_gep_base_{s}", .{hint});
        try out.print("  {s} = ptr_add {s}, {d}\n", .{ pointer, base, parsed.offset });
        return pointer;
    }
    return try saValue(allocator, raw);
}

pub fn appendValue(out: *std.array_list.Managed(u8), allocator: std.mem.Allocator, value: []const u8) !void {
    const translated = try saValue(allocator, value);
    defer allocator.free(translated);
    try out.appendSlice(translated);
}

pub fn parseParam(allocator: std.mem.Allocator, fragment: []const u8, index: usize) !struct { name: []u8, ty: []const u8 } {
    const ty_token = firstTypeToken(fragment) orelse return error.UnsupportedInstruction;
    const ty = typeTokenToSa(ty_token) orelse return error.UnsupportedInstruction;

    var name_token: ?[]const u8 = null;
    var parts = std.mem.tokenizeAny(u8, fragment, " \t\r\n");
    while (parts.next()) |part| {
        if (std.mem.startsWith(u8, part, "%")) name_token = part;
    }

    const name = if (name_token) |token|
        try sanitizeIdent(allocator, token, "arg")
    else
        try std.fmt.allocPrint(allocator, "arg{d}", .{index});

    return .{ .name = name, .ty = ty };
}

pub fn appendParamList(out: *std.array_list.Managed(u8), allocator: std.mem.Allocator, params_text: []const u8) !void {
    const params = try splitTopLevelComma(allocator, params_text);
    defer allocator.free(params);

    var wrote_any = false;
    var named_idx: usize = 0;
    for (params) |param_text| {
        // Extern variadic batch: preserve the trailing `...` marker
        // instead of silently dropping it (the SA declaration gains the
        // shared is_variadic flag when sci parses it back).
        if (std.mem.eql(u8, trim(param_text), "...")) {
            if (wrote_any) try out.appendSlice(", ");
            try out.appendSlice("...");
            wrote_any = true;
            continue;
        }
        if (wrote_any) try out.appendSlice(", ");
        const param = try parseParam(allocator, param_text, named_idx);
        named_idx += 1;
        defer allocator.free(param.name);
        try out.print("{s}: {s}", .{ param.name, param.ty });
        wrote_any = true;
    }
}

pub fn appendFunctionHeader(out: *std.array_list.Managed(u8), allocator: std.mem.Allocator, line: []const u8, is_declare: bool) !void {
    const keyword = if (is_declare) "declare" else "define";
    if (!startsWithWord(line, keyword)) return error.InvalidIr;

    const at = std.mem.indexOfScalar(u8, line, '@') orelse return error.InvalidIr;
    const prefix = trim(line[keyword.len..at]);
    const ret_ty = try returnTypeFromPrefix(prefix);

    const after_at = line[at..];
    const open_rel = std.mem.indexOfScalar(u8, after_at, '(') orelse return error.InvalidIr;
    const raw_name = after_at[0..open_rel];
    const open = at + open_rel;
    const close = findMatching(line, open, '(', ')') orelse return error.InvalidIr;
    const name = try sanitizeIdent(allocator, raw_name, "fn_");
    defer allocator.free(name);

    if (is_declare) {
        try out.print("@extern {s}(", .{name});
    } else {
        try out.print("@export {s}(", .{name});
    }
    try appendParamList(out, allocator, line[open + 1 .. close]);
    try out.append(')');
    if (!std.mem.eql(u8, ret_ty, "void")) {
        try out.print(" -> {s}", .{ret_ty});
    }
    if (!is_declare) try out.append(':');
    try out.append('\n');
}

pub fn appendLabel(out: *std.array_list.Managed(u8), allocator: std.mem.Allocator, raw_label: []const u8) !void {
    const label = try labelName(allocator, raw_label);
    defer allocator.free(label);
    try out.print("{s}:\n", .{label});
}
