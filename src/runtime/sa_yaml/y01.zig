const std = @import("std");
const sio = @import("sio");

pub const OK: i32 = 0;

pub const ERR_INVALID: i32 = 1;

pub const ERR_HANDLE: i32 = 2;

pub const ERR_NOT_FOUND: i32 = 3;

pub const ERR_NOMEM: i32 = 5;

pub const KIND_UNDEFINED: u32 = 0;

pub const KIND_NULL: u32 = 1;

pub const KIND_BOOL: u32 = 2;

pub const KIND_INTEGER: u32 = 3;

pub const KIND_FLOAT: u32 = 4;

pub const KIND_STRING: u32 = 5;

pub const KIND_ARRAY: u32 = 6;

pub const KIND_TABLE: u32 = 7;

pub const Table = struct {
    entries: std.array_list.Managed(Entry),
};

pub const Entry = struct {
    key: []const u8,
    value: Value,
};

pub const Value = struct {
    kind: u32,
    str: []const u8 = "",
    int: i64 = 0,
    float: f64 = 0,
    boolean: bool = false,
    array: []Value = &.{},
    table: ?*Table = null,
};

pub const null_value: Value = .{ .kind = KIND_NULL };

pub fn stringValue(s: []const u8) Value {
    return .{ .kind = KIND_STRING, .str = s };
}

pub const Document = struct {
    arena: std.heap.ArenaAllocator,
    root: Value,
    yaml_buf: ?[]u8 = null,
    json_buf: ?[]u8 = null,

    pub fn alloc(self: *Document) std.mem.Allocator {
        return self.arena.allocator();
    }

    pub fn deinit(self: *Document) void {
        if (self.yaml_buf) |buf| std.heap.page_allocator.free(buf);
        if (self.json_buf) |buf| std.heap.page_allocator.free(buf);
        self.arena.deinit();
        std.heap.page_allocator.destroy(self);
    }

    fn invalidateBuffers(self: *Document) void {
        if (self.yaml_buf) |buf| {
            std.heap.page_allocator.free(buf);
            self.yaml_buf = null;
        }
        if (self.json_buf) |buf| {
            std.heap.page_allocator.free(buf);
            self.json_buf = null;
        }
    }
};

pub fn newDocument() !*Document {
    const doc = try std.heap.page_allocator.create(Document);
    doc.* = .{
        .arena = std.heap.ArenaAllocator.init(std.heap.page_allocator),
        .root = .{ .kind = KIND_TABLE, .table = null },
    };
    const table = try doc.alloc().create(Table);
    table.* = .{ .entries = std.array_list.Managed(Entry).init(doc.alloc()) };
    doc.root.table = table;
    return doc;
}

pub fn deepClone(alloc: std.mem.Allocator, v: Value) !Value {
    var out = v;
    switch (v.kind) {
        KIND_STRING => out.str = try alloc.dupe(u8, v.str),
        KIND_ARRAY => {
            const items = try alloc.alloc(Value, v.array.len);
            for (v.array, 0..) |item, i| items[i] = try deepClone(alloc, item);
            out.array = items;
        },
        KIND_TABLE => {
            const src = v.table.?;
            const table = try alloc.create(Table);
            table.* = .{ .entries = std.array_list.Managed(Entry).init(alloc) };
            for (src.entries.items) |entry| {
                try table.entries.append(.{
                    .key = try alloc.dupe(u8, entry.key),
                    .value = try deepClone(alloc, entry.value),
                });
            }
            out.table = table;
        },
        else => {},
    }
    return out;
}

// ---------------- handle registry (mirrors sa_toml.zig) ----------------
pub var docs_mu = std.Io.Mutex.init;

pub var docs_map: std.AutoHashMapUnmanaged(u64, *Document) = .empty;

pub var docs_next: u64 = 1;

pub fn registerDocument(doc: *Document) !u64 {
    docs_mu.lockUncancelable(sio.io());
    defer docs_mu.unlock(sio.io());
    const h = docs_next;
    docs_next += 1;
    try docs_map.put(std.heap.page_allocator, h, doc);
    return h;
}

pub fn getDocument(handle: u64) ?*Document {
    docs_mu.lockUncancelable(sio.io());
    defer docs_mu.unlock(sio.io());
    return docs_map.get(handle);
}

pub fn removeDocument(handle: u64) ?*Document {
    docs_mu.lockUncancelable(sio.io());
    defer docs_mu.unlock(sio.io());
    const kv = docs_map.fetchRemove(handle) orelse return null;
    return kv.value;
}

// ---------------- last error (mirrors sa_toml.zig) ----------------
pub var last_error_buf: [1024]u8 = undefined;

pub var last_error_len: usize = 0;

pub fn setLastError(comptime fmt: []const u8, args: anytype) void {
    const msg = std.fmt.bufPrint(&last_error_buf, fmt, args) catch blk: {
        last_error_len = 0;
        break :blk last_error_buf[0..0];
    };
    last_error_len = msg.len;
}

pub fn clearLastError() void {
    last_error_len = 0;
}

pub const Fail = error{ ParseFail, OutOfMemory };

pub fn failAt(line: usize, col: usize, msg: []const u8) Fail {
    setLastError("yaml: syntax error ({s}) at line {d}, col {d}", .{ msg, line, col });
    return error.ParseFail;
}

pub fn failUnsupported(line: usize, col: usize, msg: []const u8) Fail {
    setLastError("yaml: unsupported ({s}) at line {d}, col {d}", .{ msg, line, col });
    return error.ParseFail;
}

pub fn failDuplicateKey(key: []const u8, line: usize, col: usize) Fail {
    setLastError("yaml: duplicate key ({s}) at line {d}, col {d}", .{ key, line, col });
    return error.ParseFail;
}

pub fn constSlice(ptr: ?[*]const u8, len: u64) ?[]const u8 {
    if (len == 0) return "";
    const p = ptr orelse return null;
    return p[0..@intCast(len)];
}

// ---------------- text helpers ----------------
pub fn rtrimWs(s: []const u8) []const u8 {
    var end = s.len;
    while (end > 0 and (s[end - 1] == ' ' or s[end - 1] == '\t' or s[end - 1] == '\r')) end -= 1;
    return s[0..end];
}

pub fn trimWs(s: []const u8) []const u8 {
    var start: usize = 0;
    while (start < s.len and (s[start] == ' ' or s[start] == '\t')) start += 1;
    return rtrimWs(s[start..]);
}

pub fn countLeadingSpaces(s: []const u8) usize {
    var n: usize = 0;
    while (n < s.len and s[n] == ' ') n += 1;
    return n;
}

/// Strip a trailing comment from a structural line's content. A '#'
/// starts a comment when preceded by whitespace (or at the start) and
/// not inside a quoted scalar; a quote only opens quoted state at a
/// token boundary, so an apostrophe inside a plain scalar ("it's")
/// does not hide a later comment.
pub fn stripComment(s: []const u8) []const u8 {
    var i: usize = 0;
    var quote: u8 = 0;
    while (i < s.len) {
        const c = s[i];
        if (quote == '\'') {
            if (c == '\'') {
                if (i + 1 < s.len and s[i + 1] == '\'') {
                    i += 2;
                    continue;
                }
                quote = 0;
            }
            i += 1;
            continue;
        }
        if (quote == '"') {
            if (c == '\\') {
                i += 2;
                continue;
            }
            if (c == '"') quote = 0;
            i += 1;
            continue;
        }
        if (c == '#' and (i == 0 or s[i - 1] == ' ' or s[i - 1] == '\t')) {
            return rtrimWs(s[0..i]);
        }
        if ((c == '\'' or c == '"') and (i == 0 or s[i - 1] == ' ' or s[i - 1] == '\t' or s[i - 1] == ':' or s[i - 1] == '[' or s[i - 1] == '{' or s[i - 1] == ',')) {
            quote = c;
        }
        i += 1;
    }
    return rtrimWs(s);
}

// ---------------- quoted scalars ----------------
pub const QFail = error{ ParseFail, Unterminated, OutOfMemory };

pub const TextCursor = struct {
    buf: []const u8,
    i: usize = 0,
    line: usize,
    col: usize,

    fn peek(self: *const TextCursor) ?u8 {
        return if (self.i < self.buf.len) self.buf[self.i] else null;
    }

    fn peekAt(self: *const TextCursor, off: usize) ?u8 {
        const j = self.i + off;
        return if (j < self.buf.len) self.buf[j] else null;
    }

    fn bump(self: *TextCursor) ?u8 {
        const c = self.peek() orelse return null;
        self.i += 1;
        if (c == '\n') {
            self.line += 1;
            self.col = 1;
        } else {
            self.col += 1;
        }
        return c;
    }
};

/// Consume a newline run starting at the current '\n': the newline,
/// any blank lines, and the leading whitespace of the following
/// content line. Returns the number of newlines in the run.
pub fn consumeNewlineRun(cur: *TextCursor) usize {
    var n: usize = 0;
    while (cur.peek() == '\n') {
        _ = cur.bump();
        n += 1;
        while (cur.peek() == ' ' or cur.peek() == '\t') _ = cur.bump();
    }
    return n;
}

pub fn appendFoldedBreak(out: *std.array_list.Managed(u8), newlines: usize) !void {
    if (newlines <= 1) {
        try out.append(' ');
    } else {
        for (1..newlines) |_| try out.append('\n');
    }
}

/// True when the spaces/tabs at the cursor are immediately followed
/// by a newline (they are folding fodder, not content).
pub fn spacesBeforeNewline(cur: *const TextCursor) bool {
    var j = cur.i;
    while (j < cur.buf.len and (cur.buf[j] == ' ' or cur.buf[j] == '\t')) j += 1;
    return j < cur.buf.len and cur.buf[j] == '\n';
}

pub fn parseSingleQuoted(alloc: std.mem.Allocator, cur: *TextCursor) QFail![]const u8 {
    _ = cur.bump(); // opening '
    var out = std.array_list.Managed(u8).init(alloc);
    while (true) {
        const c = cur.peek() orelse return error.Unterminated;
        if (c == '\'') {
            if (cur.peekAt(1) == '\'') {
                _ = cur.bump();
                _ = cur.bump();
                try out.append('\'');
                continue;
            }
            _ = cur.bump();
            return out.toOwnedSlice();
        }
        if (c == '\n') {
            const n = consumeNewlineRun(cur);
            const next = cur.peek();
            // Breaks at the very start of the scalar or directly
            // before the closing quote are trimmed, not folded.
            if (next != null and next != '\'' and out.items.len > 0) {
                try appendFoldedBreak(&out, n);
            }
            continue;
        }
        if ((c == ' ' or c == '\t') and spacesBeforeNewline(cur)) {
            while (cur.peek() == ' ' or cur.peek() == '\t') _ = cur.bump();
            continue;
        }
        try out.append(c);
        _ = cur.bump();
    }
}

pub fn appendCodepoint(out: *std.array_list.Managed(u8), cp: u32, line: usize, col: usize) QFail!void {
    if (cp > 0x10FFFF or (cp >= 0xD800 and cp <= 0xDFFF)) {
        return failAt(line, col, "escape sequence is not a valid unicode codepoint");
    }
    var buf: [4]u8 = undefined;
    const n = std.unicode.utf8Encode(@intCast(cp), &buf) catch {
        return failAt(line, col, "escape sequence is not a valid unicode codepoint");
    };
    try out.appendSlice(buf[0..n]);
}

pub fn parseDoubleQuoted(alloc: std.mem.Allocator, cur: *TextCursor) QFail![]const u8 {
    _ = cur.bump(); // opening "
    var out = std.array_list.Managed(u8).init(alloc);
    while (true) {
        const c = cur.peek() orelse return error.Unterminated;
        if (c == '"') {
            _ = cur.bump();
            return out.toOwnedSlice();
        }
        if (c == '\n') {
            const n = consumeNewlineRun(cur);
            const next = cur.peek();
            // Breaks at the very start of the scalar or directly
            // before the closing quote are trimmed, not folded.
            if (next != null and next != '"' and out.items.len > 0) {
                try appendFoldedBreak(&out, n);
            }
            continue;
        }
        if ((c == ' ' or c == '\t') and spacesBeforeNewline(cur)) {
            while (cur.peek() == ' ' or cur.peek() == '\t') _ = cur.bump();
            continue;
        }
        if (c == '\\') {
            const esc_line = cur.line;
            const esc_col = cur.col;
            _ = cur.bump();
            const e = cur.peek() orelse return error.Unterminated;
            if (e == '\n') {
                // Escaped newline: the break and all leading
                // whitespace of the next line vanish entirely.
                _ = consumeNewlineRun(cur);
                continue;
            }
            _ = cur.bump();
            switch (e) {
                '0' => try out.append(0),
                'a' => try out.append(7),
                'b' => try out.append(8),
                't', '\t' => try out.append(9),
                'n' => try out.append(10),
                'v' => try out.append(11),
                'f' => try out.append(12),
                'r' => try out.append(13),
                'e' => try out.append(27),
                '"' => try out.append('"'),
                '/' => try out.append('/'),
                '\\' => try out.append('\\'),
                ' ' => try out.append(' '),
                'N' => try appendCodepoint(&out, 0x85, esc_line, esc_col),
                '_' => try appendCodepoint(&out, 0xA0, esc_line, esc_col),
                'L' => try appendCodepoint(&out, 0x2028, esc_line, esc_col),
                'P' => try appendCodepoint(&out, 0x2029, esc_line, esc_col),
                'x', 'u', 'U' => {
                    const digits: usize = if (e == 'x') 2 else if (e == 'u') 4 else 8;
                    var cp: u32 = 0;
                    var k: usize = 0;
                    while (k < digits) : (k += 1) {
                        const h = cur.peek() orelse return error.Unterminated;
                        const d: u32 = switch (h) {
                            '0'...'9' => h - '0',
                            'a'...'f' => h - 'a' + 10,
                            'A'...'F' => h - 'A' + 10,
                            else => return failAt(esc_line, esc_col, "invalid hex digit in escape sequence"),
                        };
                        cp = cp * 16 + d;
                        _ = cur.bump();
                    }
                    try appendCodepoint(&out, cp, esc_line, esc_col);
                },
                else => return failAt(esc_line, esc_col, "unknown escape character in double-quoted scalar"),
            }
            continue;
        }
        try out.append(c);
        _ = cur.bump();
    }
}

// ---------------- plain scalar resolution ----------------
pub fn isNullSpelling(t: []const u8) bool {
    return t.len == 0 or std.mem.eql(u8, t, "~") or std.mem.eql(u8, t, "null") or
        std.mem.eql(u8, t, "Null") or std.mem.eql(u8, t, "NULL");
}

pub fn digitVal(c: u8) u8 {
    return switch (c) {
        '0'...'9' => c - '0',
        'a'...'f' => c - 'a' + 10,
        'A'...'F' => c - 'A' + 10,
        else => 0,
    };
}

pub fn isDigitForBase(c: u8, base: u8) bool {
    const v: ?u8 = switch (c) {
        '0'...'9' => c - '0',
        'a'...'f' => c - 'a' + 10,
        'A'...'F' => c - 'A' + 10,
        else => null,
    };
    if (v) |d| return d < base;
    return false;
}

/// Digits with single underscores allowed strictly between digits.
pub fn validDigitRun(s: []const u8, base: u8) bool {
    if (s.len == 0) return false;
    if (s[0] == '_' or s[s.len - 1] == '_') return false;
    var prev_us = false;
    for (s) |c| {
        if (c == '_') {
            if (prev_us) return false;
            prev_us = true;
            continue;
        }
        if (!isDigitForBase(c, base)) return false;
        prev_us = false;
    }
    return true;
}

pub const IntSyntax = struct { neg: bool, base: u8, digits: []const u8 };

pub fn intSyntax(text: []const u8) ?IntSyntax {
    var s = text;
    var neg = false;
    if (s.len > 0 and (s[0] == '+' or s[0] == '-')) {
        neg = s[0] == '-';
        s = s[1..];
    }
    if (s.len == 0) return null;
    if (s.len > 2 and s[0] == '0' and (s[1] == 'x' or s[1] == 'X')) {
        if (!validDigitRun(s[2..], 16)) return null;
        return .{ .neg = neg, .base = 16, .digits = s[2..] };
    }
    if (s.len > 2 and s[0] == '0' and (s[1] == 'o' or s[1] == 'O')) {
        if (!validDigitRun(s[2..], 8)) return null;
        return .{ .neg = neg, .base = 8, .digits = s[2..] };
    }
    if (s.len > 2 and s[0] == '0' and (s[1] == 'b' or s[1] == 'B')) {
        if (!validDigitRun(s[2..], 2)) return null;
        return .{ .neg = neg, .base = 2, .digits = s[2..] };
    }
    if (s.len > 1 and s[0] == '0' and validDigitRun(s, 8)) {
        return .{ .neg = neg, .base = 8, .digits = s };
    }
    if (!validDigitRun(s, 10)) return null;
    return .{ .neg = neg, .base = 10, .digits = s };
}

pub fn parseIntExact(syn: IntSyntax) ?i64 {
    var mag: u64 = 0;
    for (syn.digits) |c| {
        if (c == '_') continue;
        const mul = @mulWithOverflow(mag, @as(u64, syn.base));
        if (mul[1] != 0) return null;
        const add = @addWithOverflow(mul[0], @as(u64, digitVal(c)));
        if (add[1] != 0) return null;
        mag = add[0];
    }
    if (syn.neg) {
        if (mag > 9223372036854775808) return null;
        if (mag == 9223372036854775808) return std.math.minInt(i64);
        return -@as(i64, @intCast(mag));
    }
    if (mag > @as(u64, std.math.maxInt(i64))) return null;
    return @intCast(mag);
}

pub fn floatFromInt(syn: IntSyntax) f64 {
    var v: f64 = 0;
    for (syn.digits) |c| {
        if (c == '_') continue;
        v = v * @as(f64, @floatFromInt(syn.base)) + @as(f64, @floatFromInt(digitVal(c)));
    }
    return if (syn.neg) -v else v;
}

pub fn parseYamlFloat(text: []const u8) ?f64 {
    var s = text;
    var neg = false;
    if (s.len > 0 and (s[0] == '+' or s[0] == '-')) {
        neg = s[0] == '-';
        s = s[1..];
    }
    if (std.mem.eql(u8, s, ".inf") or std.mem.eql(u8, s, ".Inf") or std.mem.eql(u8, s, ".INF")) {
        return if (neg) -std.math.inf(f64) else std.math.inf(f64);
    }
    if (std.mem.eql(u8, s, ".nan") or std.mem.eql(u8, s, ".NaN") or std.mem.eql(u8, s, ".NAN")) {
        return std.math.nan(f64);
    }
    // Split mantissa / exponent.
    var mant = s;
    var exp: ?[]const u8 = null;
    if (std.mem.indexOfAny(u8, s, "eE")) |ei| {
        mant = s[0..ei];
        exp = s[ei + 1 ..];
    }
    if (exp) |e| {
        var ed = e;
        if (ed.len > 0 and (ed[0] == '+' or ed[0] == '-')) ed = ed[1..];
        if (!validDigitRun(ed, 10)) return null;
    }
    if (std.mem.indexOfScalar(u8, mant, '.')) |di| {
        const a = mant[0..di];
        const b = mant[di + 1 ..];
        if (a.len == 0 and b.len == 0) return null;
        if (a.len > 0 and !validDigitRun(a, 10)) return null;
        if (b.len > 0 and !validDigitRun(b, 10)) return null;
    } else {
        if (exp == null) return null; // pure digits: an integer, handled earlier
        if (!validDigitRun(mant, 10)) return null;
    }
    // Normalize for std.fmt.parseFloat: strip underscores, keep a
    // digit on both sides of the dot.
    var buf: [128]u8 = undefined;
    var n: usize = 0;
    if (neg) {
        buf[n] = '-';
        n += 1;
    }
    for (s) |c| {
        if (c == '_') continue;
        if (n >= buf.len) return null;
        buf[n] = c;
        n += 1;
    }
    const cleaned = buf[0..n];
    if (std.mem.indexOfScalar(u8, cleaned, '.')) |di| {
        if (di + 1 == cleaned.len or cleaned[di + 1] == 'e' or cleaned[di + 1] == 'E') {
            // "5." or "5.e3": insert a 0 after the dot.
            if (n + 1 >= buf.len) return null;
            std.mem.copyBackwards(u8, buf[di + 2 .. n + 1], buf[di + 1 .. n]);
            buf[di + 1] = '0';
            n += 1;
        }
        if (di == 0 or (di == 1 and buf[0] == '-')) {
            // ".5": parseFloat accepts it, nothing to do.
        }
    }
    return std.fmt.parseFloat(f64, buf[0..n]) catch null;
}
