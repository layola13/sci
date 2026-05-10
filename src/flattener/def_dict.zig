const std = @import("std");

pub const DefError = error{
    OutOfMemory,
    DuplicateDef,
    UnknownDef,
    InvalidExpression,
    RecursionLimit,
};

pub const DefDict = struct {
    allocator: std.mem.Allocator,
    entries: std.StringHashMap([]const u8),

    pub fn init(allocator: std.mem.Allocator) DefDict {
        return .{
            .allocator = allocator,
            .entries = std.StringHashMap([]const u8).init(allocator),
        };
    }

    pub fn deinit(self: *DefDict) void {
        var it = self.entries.iterator();
        while (it.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            self.allocator.free(entry.value_ptr.*);
        }
        self.entries.deinit();
    }

    pub fn putExpression(self: *DefDict, name: []const u8, expr: []const u8) DefError!void {
        if (self.entries.contains(name)) return DefError.DuplicateDef;

        const value = try self.evalExpression(expr, 0);
        const key_copy = try self.allocator.dupe(u8, name);
        const value_copy = try std.fmt.allocPrint(self.allocator, "{d}", .{value});
        errdefer self.allocator.free(key_copy);
        errdefer self.allocator.free(value_copy);
        try self.entries.put(key_copy, value_copy);
    }

    pub fn get(self: *const DefDict, name: []const u8) ?[]const u8 {
        return self.entries.get(name);
    }

    pub fn resolveToken(self: *const DefDict, token: []const u8) ?[]const u8 {
        return self.get(token) orelse token;
    }

    pub fn foldToken(self: *const DefDict, token: []const u8) DefError![]const u8 {
        const resolved = self.resolveToken(token) orelse return token;
        return resolved;
    }

    pub fn foldText(self: *const DefDict, allocator: std.mem.Allocator, text: []const u8) DefError![]const u8 {
        var out = std.ArrayList(u8).init(allocator);
        errdefer out.deinit();

        var i: usize = 0;
        while (i < text.len) {
            if (std.ascii.isAlphabetic(text[i]) or text[i] == '_') {
                const start = i;
                i += 1;
                while (i < text.len and (std.ascii.isAlphanumeric(text[i]) or text[i] == '_')) : (i += 1) {}
                const token = text[start..i];
                if (self.get(token)) |replacement| {
                    try out.appendSlice(replacement);
                } else {
                    try out.appendSlice(token);
                }
            } else {
                try out.append(text[i]);
                i += 1;
            }
        }

        return try out.toOwnedSlice();
    }

    fn skipSpaces(text: []const u8, pos: *usize) void {
        while (pos.* < text.len and std.ascii.isWhitespace(text[pos.*])) : (pos.* += 1) {}
    }

    fn parseNumber(text: []const u8, pos: *usize) ?i64 {
        const start = pos.*;
        var i = start;
        if (i < text.len and (text[i] == '+' or text[i] == '-')) i += 1;
        var has_digit = false;
        while (i < text.len and std.ascii.isDigit(text[i])) : (i += 1) {
            has_digit = true;
        }
        if (!has_digit) return null;
        pos.* = i;
        return std.fmt.parseInt(i64, text[start..i], 10) catch null;
    }

    fn parseIdentifier(text: []const u8, pos: *usize) ?[]const u8 {
        const start = pos.*;
        if (start >= text.len) return null;
        const first = text[start];
        if (!(std.ascii.isAlphabetic(first) or first == '_')) return null;
        var i = start + 1;
        while (i < text.len and (std.ascii.isAlphanumeric(text[i]) or text[i] == '_')) : (i += 1) {}
        pos.* = i;
        return text[start..i];
    }

    fn parsePrimary(self: *const DefDict, text: []const u8, pos: *usize, depth: u8) DefError!i64 {
        skipSpaces(text, pos);
        if (pos.* >= text.len) return DefError.InvalidExpression;

        if (text[pos.*] == '(') {
            pos.* += 1;
            const value = try self.parseAddSub(text, pos, depth + 1);
            skipSpaces(text, pos);
            if (pos.* >= text.len or text[pos.*] != ')') return DefError.InvalidExpression;
            pos.* += 1;
            return value;
        }

        if (text[pos.*] == '-') {
            pos.* += 1;
            return -try self.parsePrimary(text, pos, depth + 1);
        }

        if (parseNumber(text, pos)) |num| {
            return num;
        }

        if (parseIdentifier(text, pos)) |ident| {
            if (depth > 32) return DefError.RecursionLimit;
            const resolved = self.get(ident) orelse return DefError.UnknownDef;
            const nested = try self.evalExpressionWithDepth(resolved, depth + 1);
            return nested;
        }

        return DefError.InvalidExpression;
    }

    fn parseMul(self: *const DefDict, text: []const u8, pos: *usize, depth: u8) DefError!i64 {
        var value = try self.parsePrimary(text, pos, depth);
        while (true) {
            skipSpaces(text, pos);
            if (pos.* >= text.len or text[pos.*] != '*') break;
            pos.* += 1;
            const rhs = try self.parsePrimary(text, pos, depth);
            value *= rhs;
        }
        return value;
    }

    fn parseAddSub(self: *const DefDict, text: []const u8, pos: *usize, depth: u8) DefError!i64 {
        var value = try self.parseMul(text, pos, depth);
        while (true) {
            skipSpaces(text, pos);
            if (pos.* >= text.len) break;
            const op = text[pos.*];
            if (op != '+' and op != '-') break;
            pos.* += 1;
            const rhs = try self.parseMul(text, pos, depth);
            if (op == '+') {
                value += rhs;
            } else {
                value -= rhs;
            }
        }
        return value;
    }

    fn evalExpressionWithDepth(self: *const DefDict, expr: []const u8, depth: u8) DefError!i64 {
        var pos: usize = 0;
        const value = try self.parseAddSub(expr, &pos, depth);
        skipSpaces(expr, &pos);
        if (pos != expr.len) return DefError.InvalidExpression;
        return value;
    }

    fn evalExpression(self: *const DefDict, expr: []const u8, depth: u8) DefError!i64 {
        return self.evalExpressionWithDepth(expr, depth);
    }
};

test "def dict folds arithmetic expressions" {
    var dict = DefDict.init(std.testing.allocator);
    defer dict.deinit();

    try dict.putExpression("A", "1 + 2 * 3");
    try dict.putExpression("B", "(A + 1) * 2");

    try std.testing.expectEqualStrings("7", dict.get("A").?);
    try std.testing.expectEqualStrings("16", dict.get("B").?);
}

test "def dict rejects duplicate names" {
    var dict = DefDict.init(std.testing.allocator);
    defer dict.deinit();

    try dict.putExpression("X", "8");
    try std.testing.expectError(DefError.DuplicateDef, dict.putExpression("X", "9"));
}
