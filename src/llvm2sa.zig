const std = @import("std");

pub const TranslateError = error{
    OutOfMemory,
    InvalidBitcode,
    InvalidIr,
    LlvmDisFailed,
    LlvmDisNotFound,
    UnsupportedBitcodeInput,
    UnsupportedInstruction,
};

const bitcode_magic = [_]u8{ 'B', 'C', 0xc0, 0xde };
const max_bitcode_bytes = 64 * 1024 * 1024;
const max_ir_bytes = 64 * 1024 * 1024;

fn trim(text: []const u8) []const u8 {
    return std.mem.trim(u8, text, " \t\r\n");
}

fn startsWithWord(text: []const u8, word: []const u8) bool {
    if (!std.mem.startsWith(u8, text, word)) return false;
    if (text.len == word.len) return true;
    const next = text[word.len];
    return std.ascii.isWhitespace(next) or next == '(' or next == '@';
}

fn stripLlvmSigil(text: []const u8) []const u8 {
    const t = trim(text);
    if (t.len == 0) return t;
    if (t[0] == '%' or t[0] == '@') return t[1..];
    return t;
}

fn isIdentChar(c: u8) bool {
    return std.ascii.isAlphanumeric(c) or c == '_';
}

fn sanitizeIdent(allocator: std.mem.Allocator, raw: []const u8, prefix: []const u8) ![]u8 {
    var source = stripLlvmSigil(raw);
    source = trim(source);
    if (source.len >= 2 and source[0] == '"' and source[source.len - 1] == '"') {
        source = source[1 .. source.len - 1];
    }

    var out = std.ArrayList(u8).init(allocator);
    errdefer out.deinit();

    if (source.len == 0 or !(std.ascii.isAlphabetic(source[0]) or source[0] == '_')) {
        try out.appendSlice(prefix);
    }

    for (source) |c| {
        try out.append(if (isIdentChar(c)) c else '_');
    }

    if (out.items.len == 0) try out.appendSlice(prefix);
    return try out.toOwnedSlice();
}

fn labelName(allocator: std.mem.Allocator, raw: []const u8) ![]u8 {
    const base = try sanitizeIdent(allocator, raw, "block_");
    defer allocator.free(base);
    if (std.mem.startsWith(u8, base, "L_")) return try allocator.dupe(u8, base);
    return try std.fmt.allocPrint(allocator, "L_{s}", .{base});
}

fn stripCommentOutsideString(line: []const u8) []const u8 {
    var in_string = false;
    var escaped = false;
    for (line, 0..) |c, idx| {
        if (in_string) {
            if (escaped) {
                escaped = false;
                continue;
            }
            if (c == '\\') {
                escaped = true;
            } else if (c == '"') {
                in_string = false;
            }
            continue;
        }
        if (c == '"') {
            in_string = true;
        } else if (c == ';') {
            return line[0..idx];
        }
    }
    return line;
}

fn stripMetadataSuffix(line: []const u8) []const u8 {
    const markers = [_][]const u8{
        ", !dbg ",
        ", !tbaa ",
        ", !range ",
        ", !nonnull ",
        ", !align ",
        ", !noundef ",
    };
    var end = line.len;
    for (markers) |marker| {
        if (std.mem.indexOf(u8, line[0..end], marker)) |idx| end = @min(end, idx);
    }
    return trim(line[0..end]);
}

fn cleanInstructionLine(line: []const u8) []const u8 {
    return stripMetadataSuffix(stripCommentOutsideString(line));
}

fn findMatching(text: []const u8, open_idx: usize, open_ch: u8, close_ch: u8) ?usize {
    var depth: usize = 0;
    var in_string = false;
    var escaped = false;
    var idx = open_idx;
    while (idx < text.len) : (idx += 1) {
        const c = text[idx];
        if (in_string) {
            if (escaped) {
                escaped = false;
                continue;
            }
            if (c == '\\') {
                escaped = true;
            } else if (c == '"') {
                in_string = false;
            }
            continue;
        }
        if (c == '"') {
            in_string = true;
            continue;
        }
        if (c == open_ch) {
            depth += 1;
        } else if (c == close_ch) {
            if (depth == 0) return null;
            depth -= 1;
            if (depth == 0) return idx;
        }
    }
    return null;
}

fn splitTopLevelComma(allocator: std.mem.Allocator, text: []const u8) ![]const []const u8 {
    const t = trim(text);
    if (t.len == 0) return try allocator.alloc([]const u8, 0);

    var list = std.ArrayList([]const u8).init(allocator);
    errdefer list.deinit();

    var paren_depth: usize = 0;
    var bracket_depth: usize = 0;
    var brace_depth: usize = 0;
    var in_string = false;
    var escaped = false;
    var start: usize = 0;

    for (t, 0..) |c, idx| {
        if (in_string) {
            if (escaped) {
                escaped = false;
                continue;
            }
            if (c == '\\') {
                escaped = true;
            } else if (c == '"') {
                in_string = false;
            }
            continue;
        }

        switch (c) {
            '"' => in_string = true,
            '(' => paren_depth += 1,
            ')' => {
                if (paren_depth != 0) paren_depth -= 1;
            },
            '[' => bracket_depth += 1,
            ']' => {
                if (bracket_depth != 0) bracket_depth -= 1;
            },
            '{' => brace_depth += 1,
            '}' => {
                if (brace_depth != 0) brace_depth -= 1;
            },
            ',' => {
                if (paren_depth == 0 and bracket_depth == 0 and brace_depth == 0) {
                    const part = trim(t[start..idx]);
                    if (part.len == 0) return error.InvalidIr;
                    try list.append(part);
                    start = idx + 1;
                }
            },
            else => {},
        }
    }

    const tail = trim(t[start..]);
    if (tail.len == 0) return error.InvalidIr;
    try list.append(tail);
    return try list.toOwnedSlice();
}

fn typeTokenToSa(token: []const u8) ?[]const u8 {
    const t = trim(token);
    if (t.len == 0) return null;
    if (std.mem.eql(u8, t, "void")) return "void";
    if (std.mem.eql(u8, t, "i1")) return "i1";
    if (std.mem.eql(u8, t, "i8")) return "i8";
    if (std.mem.eql(u8, t, "i16")) return "i16";
    if (std.mem.eql(u8, t, "i32")) return "i32";
    if (std.mem.eql(u8, t, "i64")) return "i64";
    if (std.mem.eql(u8, t, "float")) return "f32";
    if (std.mem.eql(u8, t, "double")) return "f64";
    if (std.mem.eql(u8, t, "ptr")) return "ptr";
    if (std.mem.endsWith(u8, t, "*")) return "ptr";
    if (std.mem.startsWith(u8, t, "%") and std.mem.endsWith(u8, t, "*")) return "ptr";
    return null;
}

fn typeBytes(type_text: []const u8) ?u64 {
    const t = trim(type_text);
    if (std.mem.eql(u8, t, "i1") or std.mem.eql(u8, t, "i8")) return 1;
    if (std.mem.eql(u8, t, "i16")) return 2;
    if (std.mem.eql(u8, t, "i32") or std.mem.eql(u8, t, "float")) return 4;
    if (std.mem.eql(u8, t, "i64") or std.mem.eql(u8, t, "double") or std.mem.eql(u8, t, "ptr") or std.mem.endsWith(u8, t, "*")) return 8;

    if (t.len >= 5 and t[0] == '[' and t[t.len - 1] == ']') {
        const body = trim(t[1 .. t.len - 1]);
        const x_idx = std.mem.indexOf(u8, body, " x ") orelse return null;
        const count = std.fmt.parseInt(u64, trim(body[0..x_idx]), 10) catch return null;
        const elem = typeBytes(body[x_idx + 3 ..]) orelse return null;
        return std.math.mul(u64, count, elem) catch null;
    }

    return null;
}

fn firstTypeToken(fragment: []const u8) ?[]const u8 {
    var parts = std.mem.tokenizeAny(u8, fragment, " \t\r\n");
    while (parts.next()) |part| {
        if (typeTokenToSa(part) != null) return part;
        if (std.mem.startsWith(u8, part, "[") or std.mem.startsWith(u8, part, "{")) return null;
    }
    return null;
}

fn returnTypeFromPrefix(prefix: []const u8) ![]const u8 {
    var last: ?[]const u8 = null;
    var parts = std.mem.tokenizeAny(u8, prefix, " \t\r\n");
    while (parts.next()) |part| {
        if (typeTokenToSa(part) != null) last = part;
    }
    const token = last orelse return error.UnsupportedInstruction;
    return typeTokenToSa(token).?;
}

fn llvmTypedValueToValue(text: []const u8) []const u8 {
    const t = trim(text);
    if (t.len == 0) return t;
    if (std.mem.startsWith(u8, t, "getelementptr")) return t;

    var parts = std.mem.tokenizeAny(u8, t, " \t\r\n");
    var last: []const u8 = t;
    while (parts.next()) |part| {
        last = part;
    }

    if (std.mem.startsWith(u8, last, "%") or std.mem.startsWith(u8, last, "@")) return last;
    if (std.mem.eql(u8, last, "null") or std.mem.eql(u8, last, "true") or std.mem.eql(u8, last, "false")) return last;
    if (std.fmt.parseInt(i64, last, 10)) |_| return last else |_| {}
    return t;
}

fn saValue(allocator: std.mem.Allocator, raw: []const u8) ![]u8 {
    var value = trim(raw);
    value = trim(std.mem.trimRight(u8, value, ","));
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

    if (std.mem.startsWith(u8, value, "getelementptr")) {
        return try saGetElementPtrConstant(allocator, value);
    }

    return error.UnsupportedInstruction;
}

fn saGetElementPtrConstant(allocator: std.mem.Allocator, expr: []const u8) ![]u8 {
    const open = std.mem.indexOfScalar(u8, expr, '(') orelse return error.UnsupportedInstruction;
    const close = findMatching(expr, open, '(', ')') orelse return error.UnsupportedInstruction;
    const args = try splitTopLevelComma(allocator, expr[open + 1 .. close]);
    defer allocator.free(args);
    if (args.len < 2) return error.UnsupportedInstruction;

    const base = llvmTypedValueToValue(args[1]);
    if (!std.mem.startsWith(u8, base, "@")) return error.UnsupportedInstruction;
    for (args[2..]) |arg| {
        const value = llvmTypedValueToValue(arg);
        if (!std.mem.eql(u8, value, "0")) return error.UnsupportedInstruction;
    }

    const name = try sanitizeIdent(allocator, base, "g_");
    defer allocator.free(name);
    return try std.fmt.allocPrint(allocator, "&{s}", .{name});
}

fn appendValue(out: *std.ArrayList(u8), allocator: std.mem.Allocator, value: []const u8) !void {
    const translated = try saValue(allocator, value);
    defer allocator.free(translated);
    try out.appendSlice(translated);
}

fn parseParam(allocator: std.mem.Allocator, fragment: []const u8, index: usize) !struct { name: []u8, ty: []const u8 } {
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

fn appendParamList(out: *std.ArrayList(u8), allocator: std.mem.Allocator, params_text: []const u8) !void {
    const params = try splitTopLevelComma(allocator, params_text);
    defer allocator.free(params);

    for (params, 0..) |param_text, idx| {
        if (idx != 0) try out.appendSlice(", ");
        const param = try parseParam(allocator, param_text, idx);
        defer allocator.free(param.name);
        try out.writer().print("{s}: {s}", .{ param.name, param.ty });
    }
}

fn appendFunctionHeader(out: *std.ArrayList(u8), allocator: std.mem.Allocator, line: []const u8, is_declare: bool) !void {
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
        try out.writer().print("@extern {s}(", .{name});
    } else {
        try out.writer().print("@export {s}(", .{name});
    }
    try appendParamList(out, allocator, line[open + 1 .. close]);
    try out.append(')');
    if (!std.mem.eql(u8, ret_ty, "void")) {
        try out.writer().print(" -> {s}", .{ret_ty});
    }
    if (!is_declare) try out.append(':');
    try out.append('\n');
}

fn appendLabel(out: *std.ArrayList(u8), allocator: std.mem.Allocator, raw_label: []const u8) !void {
    const label = try labelName(allocator, raw_label);
    defer allocator.free(label);
    try out.writer().print("{s}:\n", .{label});
}

fn llvmBinaryOpToSa(op: []const u8) ?[]const u8 {
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

fn llvmIcmpToSa(pred: []const u8) ?[]const u8 {
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

fn skipOverflowFlags(text: []const u8) []const u8 {
    var rest = trim(text);
    while (true) {
        const first_space = std.mem.indexOfAny(u8, rest, " \t") orelse return rest;
        const word = rest[0..first_space];
        if (!(std.mem.eql(u8, word, "nsw") or std.mem.eql(u8, word, "nuw") or std.mem.eql(u8, word, "exact"))) return rest;
        rest = trim(rest[first_space..]);
    }
}

fn appendBinaryOp(out: *std.ArrayList(u8), allocator: std.mem.Allocator, lhs: []const u8, op: []const u8, rest: []const u8) !void {
    const sa_op = llvmBinaryOpToSa(op) orelse return error.UnsupportedInstruction;
    const body = skipOverflowFlags(rest);
    const ty_token = firstTypeToken(body) orelse return error.UnsupportedInstruction;
    const after_ty = trim(body[(std.mem.indexOf(u8, body, ty_token) orelse 0) + ty_token.len ..]);
    const args = try splitTopLevelComma(allocator, after_ty);
    defer allocator.free(args);
    if (args.len != 2) return error.UnsupportedInstruction;

    const dst = try sanitizeIdent(allocator, lhs, "r");
    defer allocator.free(dst);
    try out.writer().print("  {s} = {s} ", .{ dst, sa_op });
    try appendValue(out, allocator, args[0]);
    try out.appendSlice(", ");
    try appendValue(out, allocator, args[1]);
    try out.append('\n');
}

fn appendIcmp(out: *std.ArrayList(u8), allocator: std.mem.Allocator, lhs: []const u8, rest: []const u8) !void {
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
    try out.writer().print("  {s} = {s} ", .{ dst, sa_op });
    try appendValue(out, allocator, args[0]);
    try out.appendSlice(", ");
    try appendValue(out, allocator, args[1]);
    try out.append('\n');
}

fn appendAlloca(out: *std.ArrayList(u8), allocator: std.mem.Allocator, lhs: []const u8, rest: []const u8) !void {
    const comma = std.mem.indexOfScalar(u8, rest, ',') orelse rest.len;
    const alloc_ty = trim(rest[0..comma]);
    if (std.mem.indexOfScalar(u8, alloc_ty, '%') != null) return error.UnsupportedInstruction;
    const size = typeBytes(alloc_ty) orelse return error.UnsupportedInstruction;
    const dst = try sanitizeIdent(allocator, lhs, "r");
    defer allocator.free(dst);
    try out.writer().print("  {s} = stack_alloc {d}\n", .{ dst, size });
}

fn appendLoad(out: *std.ArrayList(u8), allocator: std.mem.Allocator, lhs: []const u8, rest: []const u8) !void {
    const args = try splitTopLevelComma(allocator, rest);
    defer allocator.free(args);
    if (args.len < 2) return error.UnsupportedInstruction;

    const value_ty = firstTypeToken(args[0]) orelse return error.UnsupportedInstruction;
    const sa_ty = typeTokenToSa(value_ty) orelse return error.UnsupportedInstruction;
    const base = try saValue(allocator, args[1]);
    defer allocator.free(base);
    const dst = try sanitizeIdent(allocator, lhs, "r");
    defer allocator.free(dst);
    try out.writer().print("  {s} = load {s}+0 as {s}\n", .{ dst, base, sa_ty });
}

fn appendStore(out: *std.ArrayList(u8), allocator: std.mem.Allocator, rest: []const u8) !void {
    const args = try splitTopLevelComma(allocator, rest);
    defer allocator.free(args);
    if (args.len < 2) return error.UnsupportedInstruction;

    const value_ty = firstTypeToken(args[0]) orelse return error.UnsupportedInstruction;
    const sa_ty = typeTokenToSa(value_ty) orelse return error.UnsupportedInstruction;
    const value = try saValue(allocator, args[0]);
    defer allocator.free(value);
    const base = try saValue(allocator, args[1]);
    defer allocator.free(base);
    try out.writer().print("  store {s}+0, {s} as {s}\n", .{ base, value, sa_ty });
}

fn appendBranch(out: *std.ArrayList(u8), allocator: std.mem.Allocator, rest: []const u8) !void {
    const t = trim(rest);
    if (std.mem.startsWith(u8, t, "label ")) {
        const label = try labelName(allocator, llvmTypedValueToValue(t["label ".len..]));
        defer allocator.free(label);
        try out.writer().print("  jmp {s}\n", .{label});
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
    try out.writer().print("  br {s} -> {s}, {s}\n", .{ cond, true_label, false_label });
}

fn appendReturn(out: *std.ArrayList(u8), allocator: std.mem.Allocator, rest: []const u8) !void {
    const t = trim(rest);
    if (std.mem.eql(u8, t, "void") or t.len == 0) {
        try out.appendSlice("  return\n");
        return;
    }
    try out.appendSlice("  return ");
    try appendValue(out, allocator, t);
    try out.append('\n');
}

fn appendCast(out: *std.ArrayList(u8), allocator: std.mem.Allocator, lhs: []const u8, op: []const u8, rest: []const u8) !void {
    const to_idx = std.mem.lastIndexOf(u8, rest, " to ") orelse return error.UnsupportedInstruction;
    const source = trim(rest[0..to_idx]);
    const dest_ty_text = trim(rest[to_idx + 4 ..]);
    const dest_ty_token = firstTypeToken(dest_ty_text) orelse return error.UnsupportedInstruction;
    const dest_ty = typeTokenToSa(dest_ty_token) orelse return error.UnsupportedInstruction;
    const dst = try sanitizeIdent(allocator, lhs, "r");
    defer allocator.free(dst);
    try out.writer().print("  {s} = {s} ", .{ dst, op });
    try appendValue(out, allocator, source);
    try out.writer().print(" as {s}\n", .{dest_ty});
}

fn appendGetElementPtr(out: *std.ArrayList(u8), allocator: std.mem.Allocator, lhs: []const u8, rest: []const u8) !void {
    var body = trim(rest);
    if (std.mem.startsWith(u8, body, "inbounds ")) body = trim(body["inbounds ".len..]);
    const args = try splitTopLevelComma(allocator, body);
    defer allocator.free(args);
    if (args.len < 3) return error.UnsupportedInstruction;

    const dst = try sanitizeIdent(allocator, lhs, "r");
    defer allocator.free(dst);
    const base = try saValue(allocator, args[1]);
    defer allocator.free(base);
    const offset = try saValue(allocator, args[args.len - 1]);
    defer allocator.free(offset);
    try out.writer().print("  {s} = ptr_add {s}, {s}\n", .{ dst, base, offset });
}

fn appendCall(out: *std.ArrayList(u8), allocator: std.mem.Allocator, lhs: ?[]const u8, rest: []const u8) !void {
    const call_idx = std.mem.indexOf(u8, rest, "call ") orelse return error.UnsupportedInstruction;
    const call_text = trim(rest[call_idx + "call ".len ..]);
    const at = std.mem.indexOfScalar(u8, call_text, '@') orelse return error.UnsupportedInstruction;
    const open_rel = std.mem.indexOfScalar(u8, call_text[at..], '(') orelse return error.InvalidIr;
    const open = at + open_rel;
    const close = findMatching(call_text, open, '(', ')') orelse return error.InvalidIr;
    const raw_callee = call_text[at..open];
    const callee = try sanitizeIdent(allocator, raw_callee, "fn_");
    defer allocator.free(callee);

    if (lhs) |lhs_text| {
        const dst = try sanitizeIdent(allocator, lhs_text, "r");
        defer allocator.free(dst);
        try out.writer().print("  {s} = call @{s}(", .{ dst, callee });
    } else {
        try out.writer().print("  call @{s}(", .{callee});
    }

    const args = try splitTopLevelComma(allocator, call_text[open + 1 .. close]);
    defer allocator.free(args);
    for (args, 0..) |arg, idx| {
        if (idx != 0) try out.appendSlice(", ");
        try appendValue(out, allocator, arg);
    }
    try out.appendSlice(")\n");
}

fn appendAssignmentInstruction(out: *std.ArrayList(u8), allocator: std.mem.Allocator, lhs: []const u8, rhs: []const u8) !void {
    var words = std.mem.tokenizeAny(u8, rhs, " \t\r\n");
    const op = words.next() orelse return error.InvalidIr;
    const rest_start = std.mem.indexOf(u8, rhs, op) orelse return error.InvalidIr;
    const rest = trim(rhs[rest_start + op.len ..]);

    if (llvmBinaryOpToSa(op) != null) return appendBinaryOp(out, allocator, lhs, op, rest);
    if (std.mem.eql(u8, op, "icmp")) return appendIcmp(out, allocator, lhs, rest);
    if (std.mem.eql(u8, op, "alloca")) return appendAlloca(out, allocator, lhs, rest);
    if (std.mem.eql(u8, op, "load")) return appendLoad(out, allocator, lhs, rest);
    if (std.mem.eql(u8, op, "getelementptr")) return appendGetElementPtr(out, allocator, lhs, rest);
    if (std.mem.eql(u8, op, "call") or std.mem.indexOf(u8, rhs, " call ") != null) return appendCall(out, allocator, lhs, rhs);
    if (std.mem.eql(u8, op, "trunc") or std.mem.eql(u8, op, "zext") or std.mem.eql(u8, op, "sext") or std.mem.eql(u8, op, "bitcast")) {
        return appendCast(out, allocator, lhs, op, rest);
    }

    return error.UnsupportedInstruction;
}

fn appendInstruction(out: *std.ArrayList(u8), allocator: std.mem.Allocator, line: []const u8) !void {
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

fn decodeLlvmCString(allocator: std.mem.Allocator, literal: []const u8) ![]u8 {
    var out = std.ArrayList(u8).init(allocator);
    errdefer out.deinit();

    var i: usize = 0;
    while (i < literal.len) {
        if (literal[i] != '\\') {
            try out.append(literal[i]);
            i += 1;
            continue;
        }

        if (i + 2 >= literal.len) return error.InvalidIr;
        const hi = std.fmt.charToDigit(literal[i + 1], 16) catch {
            switch (literal[i + 1]) {
                '\\' => {
                    try out.append('\\');
                    i += 2;
                    continue;
                },
                '"' => {
                    try out.append('"');
                    i += 2;
                    continue;
                },
                else => return error.InvalidIr,
            }
        };
        const lo = std.fmt.charToDigit(literal[i + 2], 16) catch return error.InvalidIr;
        try out.append(@as(u8, @intCast((hi << 4) | lo)));
        i += 3;
    }

    return try out.toOwnedSlice();
}

fn appendSaQuotedByte(out: *std.ArrayList(u8), byte: u8) !void {
    switch (byte) {
        '\\' => try out.appendSlice("\\\\"),
        '"' => try out.appendSlice("\\\""),
        '\n' => try out.appendSlice("\\n"),
        '\r' => try out.appendSlice("\\r"),
        '\t' => try out.appendSlice("\\t"),
        0 => try out.appendSlice("\\0"),
        else => {
            if (byte >= 0x20 and byte <= 0x7e) {
                try out.append(byte);
            } else {
                try out.writer().print("\\x{X:0>2}", .{byte});
            }
        },
    }
}

fn appendConstDecl(out: *std.ArrayList(u8), allocator: std.mem.Allocator, line: []const u8) !bool {
    const eq = std.mem.indexOfScalar(u8, line, '=') orelse return false;
    const raw_name = trim(line[0..eq]);
    if (!std.mem.startsWith(u8, raw_name, "@")) return false;
    if (std.mem.indexOf(u8, line[eq + 1 ..], " constant ") == null) return false;
    const c_idx = std.mem.indexOf(u8, line[eq + 1 ..], " c\"") orelse return false;
    const literal_start = eq + 1 + c_idx + 3;
    const literal_end = std.mem.lastIndexOfScalar(u8, line, '"') orelse return error.InvalidIr;
    if (literal_end < literal_start) return error.InvalidIr;

    const bytes = try decodeLlvmCString(allocator, line[literal_start..literal_end]);
    defer allocator.free(bytes);
    const name = try sanitizeIdent(allocator, raw_name, "g_");
    defer allocator.free(name);

    if (std.unicode.utf8ValidateSlice(bytes)) {
        try out.writer().print("@const {s} = utf8:\"", .{name});
        for (bytes) |byte| try appendSaQuotedByte(out, byte);
        try out.appendSlice("\"\n");
    } else {
        try out.writer().print("@const {s} = hex:", .{name});
        for (bytes) |byte| try out.writer().print("\\x{X:0>2}", .{byte});
        try out.append('\n');
    }
    return true;
}

pub fn translateIrSource(allocator: std.mem.Allocator, source: []const u8) ![]u8 {
    var out = std.ArrayList(u8).init(allocator);
    errdefer out.deinit();

    var in_function = false;
    var need_entry_label = false;
    var lines = std.mem.splitScalar(u8, source, '\n');
    while (lines.next()) |raw_line| {
        const trimmed_line = trim(raw_line);
        if (trimmed_line.len == 0) continue;
        if (std.mem.startsWith(u8, trimmed_line, ";")) continue;

        if (!in_function) {
            if (try appendConstDecl(&out, allocator, trimmed_line)) continue;
            const cleaned = cleanInstructionLine(trimmed_line);
            const line = trim(cleaned);
            if (line.len == 0) continue;
            if (startsWithWord(line, "declare")) {
                try appendFunctionHeader(&out, allocator, line, true);
                continue;
            }
            if (startsWithWord(line, "define")) {
                try appendFunctionHeader(&out, allocator, line, false);
                in_function = true;
                need_entry_label = true;
                continue;
            }
            continue;
        }

        const cleaned = cleanInstructionLine(trimmed_line);
        const line = trim(cleaned);
        if (line.len == 0) continue;
        if (std.mem.eql(u8, line, "}")) {
            in_function = false;
            need_entry_label = false;
            try out.append('\n');
            continue;
        }

        if (std.mem.endsWith(u8, line, ":")) {
            try appendLabel(&out, allocator, line[0 .. line.len - 1]);
            need_entry_label = false;
            continue;
        }

        if (need_entry_label) {
            try out.appendSlice("L_ENTRY:\n");
            need_entry_label = false;
        }
        try appendInstruction(&out, allocator, line);
    }

    if (in_function) return error.InvalidIr;
    return try out.toOwnedSlice();
}

fn runLlvmDisTool(allocator: std.mem.Allocator, exe: []const u8, path: []const u8) !?[]u8 {
    const argv = [_][]const u8{ exe, "-o", "-", path };
    const result = std.process.Child.run(.{
        .allocator = allocator,
        .argv = argv[0..],
        .max_output_bytes = max_ir_bytes,
    }) catch |err| switch (err) {
        error.FileNotFound => return null,
        else => return err,
    };
    errdefer allocator.free(result.stdout);
    defer allocator.free(result.stderr);

    switch (result.term) {
        .Exited => |code| {
            if (code == 0) return result.stdout;
            return error.LlvmDisFailed;
        },
        else => return error.LlvmDisFailed,
    }
}

fn disassembleBitcode(allocator: std.mem.Allocator, path: []const u8) ![]u8 {
    if (try runLlvmDisTool(allocator, "llvm-dis-14", path)) |ir| return ir;
    if (try runLlvmDisTool(allocator, "llvm-dis", path)) |ir| return ir;
    return error.LlvmDisNotFound;
}

pub fn translateBitcodeFile(allocator: std.mem.Allocator, path: []const u8) ![]u8 {
    const source = std.fs.cwd().readFileAlloc(allocator, path, max_bitcode_bytes) catch |err| switch (err) {
        error.FileNotFound => return error.UnsupportedBitcodeInput,
        else => return err,
    };
    defer allocator.free(source);

    if (source.len < bitcode_magic.len or !std.mem.eql(u8, source[0..bitcode_magic.len], bitcode_magic[0..])) {
        return error.UnsupportedBitcodeInput;
    }

    const ir = try disassembleBitcode(allocator, path);
    defer allocator.free(ir);
    return try translateIrSource(allocator, ir);
}

fn llvmAs(allocator: std.mem.Allocator, input_path: []const u8, output_path: []const u8) !void {
    const argv = [_][]const u8{ "llvm-as-14", input_path, "-o", output_path };
    const result = std.process.Child.run(.{
        .allocator = allocator,
        .argv = argv[0..],
    }) catch |err| switch (err) {
        error.FileNotFound => return error.SkipZigTest,
        else => return err,
    };
    defer allocator.free(result.stdout);
    defer allocator.free(result.stderr);
    switch (result.term) {
        .Exited => |code| if (code != 0) return error.SkipZigTest,
        else => return error.SkipZigTest,
    }
}

test "bc2sa translates real llvm bitcode" {
    var tmp = std.testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();
    try tmp.dir.writeFile(.{ .sub_path = "sample.ll", .data = 
        \\define i32 @main(i32 %lhs, i32 %rhs) {
        \\entry:
        \\  %0 = add i32 %lhs, %rhs
        \\  %1 = icmp sgt i32 %0, 2
        \\  br i1 %1, label %ok, label %err
        \\ok:
        \\  ret i32 %0
        \\err:
        \\  ret i32 0
        \\}
        \\
    });
    const ll_path = try tmp.dir.realpathAlloc(std.testing.allocator, "sample.ll");
    defer std.testing.allocator.free(ll_path);
    const tmp_path = try tmp.dir.realpathAlloc(std.testing.allocator, ".");
    defer std.testing.allocator.free(tmp_path);
    const bc_path = try std.fs.path.join(std.testing.allocator, &.{ tmp_path, "sample.bc" });
    defer std.testing.allocator.free(bc_path);
    try llvmAs(std.testing.allocator, ll_path, bc_path);

    const out = try translateBitcodeFile(std.testing.allocator, bc_path);
    defer std.testing.allocator.free(out);
    try std.testing.expect(std.mem.containsAtLeast(u8, out, 1, "@export main(lhs: i32, rhs: i32) -> i32:"));
    try std.testing.expect(std.mem.containsAtLeast(u8, out, 1, "L_entry:"));
    try std.testing.expect(std.mem.containsAtLeast(u8, out, 1, "r0 = add lhs, rhs"));
    try std.testing.expect(std.mem.containsAtLeast(u8, out, 1, "r1 = sgt r0, 2"));
    try std.testing.expect(std.mem.containsAtLeast(u8, out, 1, "br r1 -> L_ok, L_err"));
    try std.testing.expect(std.mem.containsAtLeast(u8, out, 1, "return r0"));
}

test "bc2sa rejects text llvm ir on bitcode-only path" {
    var tmp = std.testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();
    try tmp.dir.writeFile(.{
        .sub_path = "sample.ll",
        .data = "define i32 @main() {\nentry:\n  ret i32 0\n}\n",
    });
    const sample_path = try tmp.dir.realpathAlloc(std.testing.allocator, "sample.ll");
    defer std.testing.allocator.free(sample_path);
    try std.testing.expectError(error.UnsupportedBitcodeInput, translateBitcodeFile(std.testing.allocator, sample_path));
}
