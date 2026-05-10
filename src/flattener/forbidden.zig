const std = @import("std");

pub const ForbiddenToken = enum {
    brace_open,
    brace_close,
    keyword_if,
    keyword_else,
    keyword_while,
    keyword_for,
    property_chain,
};

pub const ForbiddenHit = struct {
    token: ForbiddenToken,
    column: usize,
};

fn isIdentChar(c: u8) bool {
    return std.ascii.isAlphanumeric(c) or c == '_';
}

fn stripComment(line: []const u8) []const u8 {
    const trimmed = std.mem.trim(u8, line, " \t\r");
    if (trimmed.len == 0 or std.mem.startsWith(u8, trimmed, "//")) return "";
    if (std.mem.indexOf(u8, trimmed, "//")) |idx| {
        return std.mem.trimRight(u8, trimmed[0..idx], " \t");
    }
    return trimmed;
}

fn findWord(s: []const u8, word: []const u8) ?usize {
    if (word.len == 0 or s.len < word.len) return null;
    var i: usize = 0;
    while (i + word.len <= s.len) : (i += 1) {
        if (!std.mem.startsWith(u8, s[i..], word)) continue;
        const before_ok = i == 0 or !isIdentChar(s[i - 1]);
        const after_index = i + word.len;
        const after_ok = after_index == s.len or !isIdentChar(s[after_index]);
        if (before_ok and after_ok) return i;
    }
    return null;
}

fn findPropertyChain(s: []const u8) ?usize {
    var i: usize = 0;
    while (i < s.len) : (i += 1) {
        if (!isIdentChar(s[i]) or !std.ascii.isAlphabetic(s[i]) and s[i] != '_') continue;
        var j = i;
        while (j < s.len and isIdentChar(s[j])) : (j += 1) {}
        if (j >= s.len or s[j] != '.') continue;
        var k = j + 1;
        if (k >= s.len or !std.ascii.isAlphabetic(s[k]) and s[k] != '_') continue;
        while (k < s.len and isIdentChar(s[k])) : (k += 1) {}
        if (k >= s.len or s[k] != '.') continue;
        const l = k + 1;
        if (l < s.len and (std.ascii.isAlphabetic(s[l]) or s[l] == '_')) return i;
    }
    return null;
}

pub fn findForbiddenSyntax(line: []const u8) ?ForbiddenHit {
    const scan = stripComment(line);
    if (scan.len == 0) return null;

    if (std.mem.indexOfScalar(u8, scan, '{')) |idx| return .{ .token = .brace_open, .column = idx + 1 };
    if (std.mem.indexOfScalar(u8, scan, '}')) |idx| return .{ .token = .brace_close, .column = idx + 1 };
    if (findWord(scan, "if")) |idx| return .{ .token = .keyword_if, .column = idx + 1 };
    if (findWord(scan, "else")) |idx| return .{ .token = .keyword_else, .column = idx + 1 };
    if (findWord(scan, "while")) |idx| return .{ .token = .keyword_while, .column = idx + 1 };
    if (findWord(scan, "for")) |idx| return .{ .token = .keyword_for, .column = idx + 1 };
    if (findPropertyChain(scan)) |idx| return .{ .token = .property_chain, .column = idx + 1 };
    return null;
}

test "forbidden syntax detection is conservative and exact enough" {
    try std.testing.expect(findForbiddenSyntax("   // if ignored") == null);
    try std.testing.expectEqual(ForbiddenToken.keyword_if, findForbiddenSyntax("if x = 1").?.token);
    try std.testing.expectEqual(ForbiddenToken.brace_open, findForbiddenSyntax("x = { y }").?.token);
    try std.testing.expectEqual(ForbiddenToken.property_chain, findForbiddenSyntax("x = a.b.c").?.token);
}
