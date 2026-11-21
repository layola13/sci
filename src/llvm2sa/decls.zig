// LLVM string literals and @const declarations.
const std = @import("std");
const trim = @import("text.zig").trim;
const sanitizeIdent = @import("text.zig").sanitizeIdent;

pub fn decodeLlvmCString(allocator: std.mem.Allocator, literal: []const u8) ![]u8 {
    var out = std.array_list.Managed(u8).init(allocator);
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

pub fn appendSaQuotedByte(out: *std.array_list.Managed(u8), byte: u8) !void {
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
                try out.print("\\x{X:0>2}", .{byte});
            }
        },
    }
}

pub fn appendConstDecl(out: *std.array_list.Managed(u8), allocator: std.mem.Allocator, line: []const u8) !bool {
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
        try out.print("@const {s} = utf8:\"", .{name});
        for (bytes) |byte| try appendSaQuotedByte(out, byte);
        try out.appendSlice("\"\n");
    } else {
        try out.print("@const {s} = hex:", .{name});
        for (bytes) |byte| try out.print("\\x{X:0>2}", .{byte});
        try out.append('\n');
    }
    return true;
}
