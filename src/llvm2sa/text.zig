// Text / identifier helpers for LLVM IR source.
const std = @import("std");

pub fn trim(text: []const u8) []const u8 {
    return std.mem.trim(u8, text, " \t\r\n");
}

pub fn startsWithWord(text: []const u8, word: []const u8) bool {
    if (!std.mem.startsWith(u8, text, word)) return false;
    if (text.len == word.len) return true;
    const next = text[word.len];
    return std.ascii.isWhitespace(next) or next == '(' or next == '@';
}

pub fn stripLlvmSigil(text: []const u8) []const u8 {
    const t = trim(text);
    if (t.len == 0) return t;
    if (t[0] == '%' or t[0] == '@') return t[1..];
    return t;
}

pub fn isIdentChar(c: u8) bool {
    return std.ascii.isAlphanumeric(c) or c == '_';
}

pub fn sanitizeIdent(allocator: std.mem.Allocator, raw: []const u8, prefix: []const u8) ![]u8 {
    var source = stripLlvmSigil(raw);
    source = trim(source);
    if (source.len >= 2 and source[0] == '"' and source[source.len - 1] == '"') {
        source = source[1 .. source.len - 1];
    }

    var out = std.array_list.Managed(u8).init(allocator);
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

pub fn labelName(allocator: std.mem.Allocator, raw: []const u8) ![]u8 {
    const base = try sanitizeIdent(allocator, raw, "block_");
    defer allocator.free(base);
    if (std.mem.startsWith(u8, base, "L_")) return try allocator.dupe(u8, base);
    return try std.fmt.allocPrint(allocator, "L_{s}", .{base});
}

pub fn stripCommentOutsideString(line: []const u8) []const u8 {
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

pub fn stripMetadataSuffix(line: []const u8) []const u8 {
    const markers = [_][]const u8{
        ", !dbg ",
        ", !tbaa ",
        ", !range ",
        ", !nonnull ",
        ", !align ",
        ", !noundef ",
        ", !llvm.loop ",
        ", !prof ",
        ", !llvm.expect ",
        ", !unpredictable ",
        ", !annotation ",
    };
    var end = line.len;
    for (markers) |marker| {
        if (std.mem.indexOf(u8, line[0..end], marker)) |idx| end = @min(end, idx);
    }
    return trim(line[0..end]);
}

pub fn cleanInstructionLine(line: []const u8) []const u8 {
    return stripMetadataSuffix(stripCommentOutsideString(line));
}

pub fn findMatching(text: []const u8, open_idx: usize, open_ch: u8, close_ch: u8) ?usize {
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

pub fn splitTopLevelComma(allocator: std.mem.Allocator, text: []const u8) ![]const []const u8 {
    const t = trim(text);
    if (t.len == 0) return try allocator.alloc([]const u8, 0);

    var list = std.array_list.Managed([]const u8).init(allocator);
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
