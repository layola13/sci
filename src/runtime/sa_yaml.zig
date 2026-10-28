//! sa_std YAML: parser + dotted-path accessors + builder/serializer
//! (STD batch 4; demand source: the sub2api / new-api backend censuses
//! of 2026-10-28 -- both gateways use YAML as a primary config format
//! while sa_std shipped only JSON and TOML faces).
//!
//! The face mirrors sa_toml.zig: parse the whole text into an opaque
//! OWNED U64 HANDLE (not a pointer), then read values by dotted path
//! ("server.port"); array elements in a path are addressed by a
//! numeric segment ("upstreams.0.host"). Status codes mirror
//! sa_std.zig (0 ok, 1 invalid argument, 2 invalid handle, 3 not
//! found, 5 no memory). Parse failures return handle 0 and are
//! reported through sa_yaml_last_error with a line/column position.
//!
//! This is a CONFIG-LEVEL SUBSET of YAML 1.2, not a general YAML
//! processor. The subset rulings (also in sa_std/encoding/yaml.sai):
//!  - Block mappings/sequences by indentation, flow mappings and
//!    sequences, plain / single-quoted / double-quoted scalars,
//!    literal (|) and folded (>) block scalars with chomping and
//!    indent indicators, comments, multi-document streams (--- / ...),
//!    %YAML directives (1.x; %TAG and unknown directives are
//!    UNSUPPORTED), anchors (&a), aliases (*a, deep-copied on use)
//!    and merge keys (<<).
//!  - Plain-scalar type resolution is aligned with JSON, NOT with
//!    YAML 1.1: null is ~ / null / Null / NULL / empty; bool is
//!    true/false in the three core-schema casings ONLY (yes/no/on/off
//!    stay strings); integers are decimal (underscores between digits
//!    allowed), 0x hex, 0o and legacy 0NNN octal, 0b binary; floats
//!    need a dot or an exponent, plus .inf/.nan; timestamps and
//!    sexagesimal numbers stay strings. An integer that overflows i64
//!    becomes a float (magnitude preserved approximately). Quoted and
//!    block scalars are always strings. Mapping keys are stored as
//!    their scalar text (quoted keys unescaped): the DOM is a
//!    string-keyed tree exactly like JSON/TOML, which is what makes
//!    sa_yaml_to_json a pure walk.
//!  - Duplicate keys in one mapping are a hard parse error (never
//!    silently last-wins), reported with the duplicate's position.
//!  - Explicit tags (!!str, !custom, ...), complex/explicit keys
//!    ("? key"), and document markers not at column 0 as content are
//!    rejected with an explicit UNSUPPORTED error -- nothing in this
//!    module silently approximates a construct it does not implement.
//!    Document markers ARE recognized at column 0 before parsing
//!    (subset simplification), so a column-0 "---" line can never be
//!    block-scalar content.
//!
//! Documents own an arena: every string/subtree a parse or an alias
//! clone produces lives in the arena and is released by sa_yaml_free.
//! The stringify / to_json buffers are document-owned (allocated
//! outside the arena) and are invalidated by the next mutation or
//! the next call of the same emitter on that document.

const std = @import("std");
const sio = @import("sio");

const OK: i32 = 0;
const ERR_INVALID: i32 = 1;
const ERR_HANDLE: i32 = 2;
const ERR_NOT_FOUND: i32 = 3;
const ERR_NOMEM: i32 = 5;

pub const KIND_UNDEFINED: u32 = 0;
pub const KIND_NULL: u32 = 1;
pub const KIND_BOOL: u32 = 2;
pub const KIND_INTEGER: u32 = 3;
pub const KIND_FLOAT: u32 = 4;
pub const KIND_STRING: u32 = 5;
pub const KIND_ARRAY: u32 = 6;
pub const KIND_TABLE: u32 = 7;

const Table = struct {
    entries: std.array_list.Managed(Entry),
};

const Entry = struct {
    key: []const u8,
    value: Value,
};

const Value = struct {
    kind: u32,
    str: []const u8 = "",
    int: i64 = 0,
    float: f64 = 0,
    boolean: bool = false,
    array: []Value = &.{},
    table: ?*Table = null,
};

const null_value: Value = .{ .kind = KIND_NULL };

fn stringValue(s: []const u8) Value {
    return .{ .kind = KIND_STRING, .str = s };
}

const Document = struct {
    arena: std.heap.ArenaAllocator,
    root: Value,
    yaml_buf: ?[]u8 = null,
    json_buf: ?[]u8 = null,

    fn alloc(self: *Document) std.mem.Allocator {
        return self.arena.allocator();
    }

    fn deinit(self: *Document) void {
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

fn newDocument() !*Document {
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

fn deepClone(alloc: std.mem.Allocator, v: Value) !Value {
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

var docs_mu = std.Io.Mutex.init;
var docs_map: std.AutoHashMapUnmanaged(u64, *Document) = .empty;
var docs_next: u64 = 1;

fn registerDocument(doc: *Document) !u64 {
    docs_mu.lockUncancelable(sio.io());
    defer docs_mu.unlock(sio.io());
    const h = docs_next;
    docs_next += 1;
    try docs_map.put(std.heap.page_allocator, h, doc);
    return h;
}

fn getDocument(handle: u64) ?*Document {
    docs_mu.lockUncancelable(sio.io());
    defer docs_mu.unlock(sio.io());
    return docs_map.get(handle);
}

fn removeDocument(handle: u64) ?*Document {
    docs_mu.lockUncancelable(sio.io());
    defer docs_mu.unlock(sio.io());
    const kv = docs_map.fetchRemove(handle) orelse return null;
    return kv.value;
}

// ---------------- last error (mirrors sa_toml.zig) ----------------

var last_error_buf: [1024]u8 = undefined;
var last_error_len: usize = 0;

fn setLastError(comptime fmt: []const u8, args: anytype) void {
    const msg = std.fmt.bufPrint(&last_error_buf, fmt, args) catch blk: {
        last_error_len = 0;
        break :blk last_error_buf[0..0];
    };
    last_error_len = msg.len;
}

fn clearLastError() void {
    last_error_len = 0;
}

const Fail = error{ ParseFail, OutOfMemory };

fn failAt(line: usize, col: usize, msg: []const u8) Fail {
    setLastError("yaml: syntax error ({s}) at line {d}, col {d}", .{ msg, line, col });
    return error.ParseFail;
}

fn failUnsupported(line: usize, col: usize, msg: []const u8) Fail {
    setLastError("yaml: unsupported ({s}) at line {d}, col {d}", .{ msg, line, col });
    return error.ParseFail;
}

fn failDuplicateKey(key: []const u8, line: usize, col: usize) Fail {
    setLastError("yaml: duplicate key ({s}) at line {d}, col {d}", .{ key, line, col });
    return error.ParseFail;
}

fn constSlice(ptr: ?[*]const u8, len: u64) ?[]const u8 {
    if (len == 0) return "";
    const p = ptr orelse return null;
    return p[0..@intCast(len)];
}

// ---------------- text helpers ----------------

fn rtrimWs(s: []const u8) []const u8 {
    var end = s.len;
    while (end > 0 and (s[end - 1] == ' ' or s[end - 1] == '\t' or s[end - 1] == '\r')) end -= 1;
    return s[0..end];
}

fn trimWs(s: []const u8) []const u8 {
    var start: usize = 0;
    while (start < s.len and (s[start] == ' ' or s[start] == '\t')) start += 1;
    return rtrimWs(s[start..]);
}

fn countLeadingSpaces(s: []const u8) usize {
    var n: usize = 0;
    while (n < s.len and s[n] == ' ') n += 1;
    return n;
}

/// Strip a trailing comment from a structural line's content. A '#'
/// starts a comment when preceded by whitespace (or at the start) and
/// not inside a quoted scalar; a quote only opens quoted state at a
/// token boundary, so an apostrophe inside a plain scalar ("it's")
/// does not hide a later comment.
fn stripComment(s: []const u8) []const u8 {
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

const QFail = error{ ParseFail, Unterminated, OutOfMemory };

const TextCursor = struct {
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
fn consumeNewlineRun(cur: *TextCursor) usize {
    var n: usize = 0;
    while (cur.peek() == '\n') {
        _ = cur.bump();
        n += 1;
        while (cur.peek() == ' ' or cur.peek() == '\t') _ = cur.bump();
    }
    return n;
}

fn appendFoldedBreak(out: *std.array_list.Managed(u8), newlines: usize) !void {
    if (newlines <= 1) {
        try out.append(' ');
    } else {
        for (1..newlines) |_| try out.append('\n');
    }
}

/// True when the spaces/tabs at the cursor are immediately followed
/// by a newline (they are folding fodder, not content).
fn spacesBeforeNewline(cur: *const TextCursor) bool {
    var j = cur.i;
    while (j < cur.buf.len and (cur.buf[j] == ' ' or cur.buf[j] == '\t')) j += 1;
    return j < cur.buf.len and cur.buf[j] == '\n';
}

fn parseSingleQuoted(alloc: std.mem.Allocator, cur: *TextCursor) QFail![]const u8 {
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

fn appendCodepoint(out: *std.array_list.Managed(u8), cp: u32, line: usize, col: usize) QFail!void {
    if (cp > 0x10FFFF or (cp >= 0xD800 and cp <= 0xDFFF)) {
        return failAt(line, col, "escape sequence is not a valid unicode codepoint");
    }
    var buf: [4]u8 = undefined;
    const n = std.unicode.utf8Encode(@intCast(cp), &buf) catch {
        return failAt(line, col, "escape sequence is not a valid unicode codepoint");
    };
    try out.appendSlice(buf[0..n]);
}

fn parseDoubleQuoted(alloc: std.mem.Allocator, cur: *TextCursor) QFail![]const u8 {
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

fn isNullSpelling(t: []const u8) bool {
    return t.len == 0 or std.mem.eql(u8, t, "~") or std.mem.eql(u8, t, "null") or
        std.mem.eql(u8, t, "Null") or std.mem.eql(u8, t, "NULL");
}

fn digitVal(c: u8) u8 {
    return switch (c) {
        '0'...'9' => c - '0',
        'a'...'f' => c - 'a' + 10,
        'A'...'F' => c - 'A' + 10,
        else => 0,
    };
}

fn isDigitForBase(c: u8, base: u8) bool {
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
fn validDigitRun(s: []const u8, base: u8) bool {
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

const IntSyntax = struct { neg: bool, base: u8, digits: []const u8 };

fn intSyntax(text: []const u8) ?IntSyntax {
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

fn parseIntExact(syn: IntSyntax) ?i64 {
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

fn floatFromInt(syn: IntSyntax) f64 {
    var v: f64 = 0;
    for (syn.digits) |c| {
        if (c == '_') continue;
        v = v * @as(f64, @floatFromInt(syn.base)) + @as(f64, @floatFromInt(digitVal(c)));
    }
    return if (syn.neg) -v else v;
}

fn parseYamlFloat(text: []const u8) ?f64 {
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

/// Resolve a plain scalar's text to a typed value, using the
/// JSON-aligned inference rules documented at the top of this file.
fn resolvePlainScalar(alloc: std.mem.Allocator, text: []const u8) Fail!Value {
    if (isNullSpelling(text)) return null_value;
    if (std.mem.eql(u8, text, "true") or std.mem.eql(u8, text, "True") or std.mem.eql(u8, text, "TRUE")) {
        return .{ .kind = KIND_BOOL, .boolean = true };
    }
    if (std.mem.eql(u8, text, "false") or std.mem.eql(u8, text, "False") or std.mem.eql(u8, text, "FALSE")) {
        return .{ .kind = KIND_BOOL, .boolean = false };
    }
    if (intSyntax(text)) |syn| {
        if (parseIntExact(syn)) |v| return .{ .kind = KIND_INTEGER, .int = v };
        return .{ .kind = KIND_FLOAT, .float = floatFromInt(syn) };
    }
    if (parseYamlFloat(text)) |v| return .{ .kind = KIND_FLOAT, .float = v };
    return stringValue(try alloc.dupe(u8, text));
}

// ---------------- key scanning ----------------

fn isIndicatorStart(c: u8) bool {
    return switch (c) {
        '!', '&', '*', '[', ']', '{', '}', ',', '#', '|', '>', '@', '%', '`' => true,
        else => false,
    };
}

const KeyHit = struct { key: []const u8, colon: usize };

/// Detect a mapping key at the start of a block line's content.
/// Returns the key text and the index of the ':' separator, or null
/// when the line does not start a mapping entry.
fn scanBlockKey(alloc: std.mem.Allocator, content: []const u8, line_no: usize) Fail!?KeyHit {
    if (content.len == 0) return null;
    const c0 = content[0];
    if (c0 == '\'' or c0 == '"') {
        var cur = TextCursor{ .buf = content, .line = line_no, .col = 1 };
        const key = (if (c0 == '\'') parseSingleQuoted(alloc, &cur) else parseDoubleQuoted(alloc, &cur)) catch |err| switch (err) {
            error.Unterminated => return null,
            error.OutOfMemory => return error.OutOfMemory,
            error.ParseFail => return error.ParseFail,
        };
        var j = cur.i;
        while (j < content.len and content[j] == ' ') j += 1;
        if (j < content.len and content[j] == ':' and (j + 1 == content.len or content[j + 1] == ' ')) {
            return .{ .key = key, .colon = j };
        }
        return null;
    }
    if (isIndicatorStart(c0)) return null;
    var i: usize = 0;
    while (i < content.len) : (i += 1) {
        const c = content[i];
        if (c == ':' and (i + 1 == content.len or content[i + 1] == ' ')) {
            const key = rtrimWs(content[0..i]);
            if (key.len == 0) return null;
            return .{ .key = try alloc.dupe(u8, key), .colon = i };
        }
        if (c == '#' and i > 0 and content[i - 1] == ' ') return null;
    }
    return null;
}

// ---------------- document splitting ----------------

const Line = struct { no: usize, raw: []const u8, col0: usize = 0 };
const DocRange = struct { start: usize, end: usize };

const SplitResult = struct {
    lines: []Line,
    ranges: []DocRange,
    alloc: std.mem.Allocator,

    fn deinit(self: *SplitResult) void {
        self.alloc.free(self.lines);
        self.alloc.free(self.ranges);
    }
};

fn isBlankRaw(raw: []const u8) bool {
    for (raw) |c| {
        if (c != ' ' and c != '\t') return false;
    }
    return true;
}

fn isCommentRaw(raw: []const u8) bool {
    var i: usize = 0;
    while (i < raw.len and (raw[i] == ' ' or raw[i] == '\t')) i += 1;
    return i < raw.len and raw[i] == '#';
}

/// Marker text after "---" / "..." on the same line, if the line is a
/// document marker at column 0. Returns the rest (untrimmed) or null.
fn markerRest(raw: []const u8, marker: []const u8) ?[]const u8 {
    if (!std.mem.startsWith(u8, raw, marker)) return null;
    if (raw.len == marker.len) return "";
    const c = raw[marker.len];
    if (c != ' ' and c != '\t') return null;
    return raw[marker.len + 1 ..];
}

/// Split the source into physical lines and document ranges.
/// Document markers are recognized at column 0 before any parsing
/// (subset simplification, see the module doc).
fn splitDocuments(alloc: std.mem.Allocator, src: []const u8) Fail!SplitResult {
    var out_lines = std.array_list.Managed(Line).init(alloc);
    errdefer out_lines.deinit();
    var ranges = std.array_list.Managed(DocRange).init(alloc);
    errdefer ranges.deinit();

    var doc_open = false;
    var doc_has_content = false;
    var after_end = false;
    var cur_start: usize = 0;

    var it = std.mem.splitScalar(u8, src, '\n');
    var line_no: usize = 0;
    while (it.next()) |raw0| {
        line_no += 1;
        var raw = raw0;
        if (raw.len > 0 and raw[raw.len - 1] == '\r') raw = raw[0 .. raw.len - 1];

        // Directives (only between documents).
        if (!doc_open and raw.len > 0 and raw[0] == '%') {
            if (std.mem.startsWith(u8, raw, "%YAML")) {
                const rest = trimWs(raw["%YAML".len..]);
                var tok = rest;
                if (std.mem.indexOfAny(u8, rest, " \t")) |sp| tok = rest[0..sp];
                var ok = false;
                if (std.mem.indexOfScalar(u8, tok, '.')) |dot| {
                    const major = tok[0..dot];
                    const minor = tok[dot + 1 ..];
                    if (major.len > 0 and minor.len > 0 and std.mem.eql(u8, major, "1")) {
                        ok = true;
                        for (minor) |c| {
                            if (c < '0' or c > '9') ok = false;
                        }
                    }
                }
                if (!ok) return failUnsupported(line_no, 1, "only %YAML 1.x documents are supported");
                continue;
            }
            if (std.mem.startsWith(u8, raw, "%TAG")) {
                return failUnsupported(line_no, 1, "%TAG directive");
            }
            return failUnsupported(line_no, 1, "unknown directive");
        }

        // Document start marker.
        if (markerRest(raw, "---")) |rest| {
            if (doc_open) {
                try ranges.append(.{ .start = cur_start, .end = out_lines.items.len });
            }
            doc_open = true;
            doc_has_content = false;
            after_end = false;
            cur_start = out_lines.items.len;
            const trimmed = trimWs(rest);
            if (trimmed.len > 0 and !isCommentRaw(rest)) {
                var off: usize = 0;
                while (off < rest.len and (rest[off] == ' ' or rest[off] == '\t')) off += 1;
                try out_lines.append(.{ .no = line_no, .raw = rest[off..], .col0 = 4 + off });
                doc_has_content = true;
            }
            continue;
        }

        // Document end marker.
        if (markerRest(raw, "...")) |rest| {
            if (trimWs(rest).len > 0) {
                return failAt(line_no, 5, "unexpected content after document end marker");
            }
            if (doc_open) {
                try ranges.append(.{ .start = cur_start, .end = out_lines.items.len });
                doc_open = false;
                doc_has_content = false;
            }
            after_end = true;
            continue;
        }

        const significant = !isBlankRaw(raw) and !isCommentRaw(raw);
        if (significant and after_end) {
            return failAt(line_no, 1, "did not find expected <document start>");
        }
        if (!doc_open) {
            if (!significant) continue;
            doc_open = true;
            doc_has_content = false;
            after_end = false;
            cur_start = out_lines.items.len;
        }
        try out_lines.append(.{ .no = line_no, .raw = raw, .col0 = 0 });
        if (significant) doc_has_content = true;
    }
    if (doc_open) {
        try ranges.append(.{ .start = cur_start, .end = out_lines.items.len });
    }
    return .{
        .lines = try out_lines.toOwnedSlice(),
        .ranges = try ranges.toOwnedSlice(),
        .alloc = alloc,
    };
}

// ---------------- mapping builder (block + flow share this) ----------------

const MapPart = union(enum) { entry: Entry, merge: Value };

const MapBuilder = struct {
    parts: std.array_list.Managed(MapPart),

    fn addEntry(self: *MapBuilder, key: []const u8, value: Value, line: usize, col: usize) Fail!void {
        for (self.parts.items) |part| {
            switch (part) {
                .entry => |e| {
                    if (std.mem.eql(u8, e.key, key)) return failDuplicateKey(key, line, col);
                },
                .merge => {},
            }
        }
        try self.parts.append(.{ .entry = .{ .key = key, .value = value } });
    }

    fn addMergeChecked(self: *MapBuilder, value: Value, line: usize, col: usize) Fail!void {
        if (value.kind == KIND_TABLE) {
            try self.parts.append(.{ .merge = value });
            return;
        }
        if (value.kind == KIND_ARRAY) {
            for (value.array) |item| {
                if (item.kind != KIND_TABLE) {
                    return failAt(line, col, "merge key value must be a mapping or a sequence of mappings");
                }
                try self.parts.append(.{ .merge = item });
            }
            return;
        }
        return failAt(line, col, "merge key value must be a mapping or a sequence of mappings");
    }

    fn finish(self: *MapBuilder, alloc: std.mem.Allocator) Fail!Value {
        const table = try alloc.create(Table);
        table.* = .{ .entries = std.array_list.Managed(Entry).init(alloc) };
        for (self.parts.items) |part| {
            switch (part) {
                .entry => |e| try table.entries.append(e),
                .merge => |m| {
                    for (m.table.?.entries.items) |me| {
                        if (findInEntries(table.entries.items, me.key) != null) continue;
                        if (self.hasExplicit(me.key)) continue;
                        try table.entries.append(me);
                    }
                },
            }
        }
        return .{ .kind = KIND_TABLE, .table = table };
    }

    fn hasExplicit(self: *const MapBuilder, key: []const u8) bool {
        for (self.parts.items) |part| {
            switch (part) {
                .entry => |e| {
                    if (std.mem.eql(u8, e.key, key)) return true;
                },
                .merge => {},
            }
        }
        return false;
    }
};

fn findInEntries(entries: []const Entry, key: []const u8) ?*const Value {
    for (entries) |*e| {
        if (std.mem.eql(u8, e.key, key)) return &e.value;
    }
    return null;
}

// ---------------- block parser ----------------

const LineView = struct {
    no: usize,
    ind: usize,
    content: []const u8,
    col: usize, // 1-based column of content start
    physical: bool,
};

fn lineIndent(line: Line) Fail!usize {
    var i: usize = 0;
    var first_tab: ?usize = null;
    while (i < line.raw.len and (line.raw[i] == ' ' or line.raw[i] == '\t')) {
        if (line.raw[i] == '\t' and first_tab == null) first_tab = i;
        i += 1;
    }
    if (i >= line.raw.len) return 0; // blank line; indent is moot
    if (first_tab) |t| {
        return failAt(line.no, line.col0 + t + 1, "tab character used for indentation");
    }
    return i;
}

fn isSeqStart(content: []const u8) bool {
    return content.len == 1 and content[0] == '-' or
        (content.len > 1 and content[0] == '-' and content[1] == ' ');
}

fn isAnchorChar(c: u8) bool {
    return (c >= 'a' and c <= 'z') or (c >= 'A' and c <= 'Z') or
        (c >= '0' and c <= '9') or c == '_' or c == '-';
}

fn validAnchorName(name: []const u8) bool {
    if (name.len == 0) return false;
    for (name) |c| {
        if (!isAnchorChar(c)) return false;
    }
    return true;
}

fn failUnknownAlias(name: []const u8, line: usize, col: usize) Fail {
    setLastError("yaml: unknown alias ({s}) at line {d}, col {d}", .{ name, line, col });
    return error.ParseFail;
}

const Prefix = struct { anchor: ?[]const u8, rest: []const u8, col: usize };

/// Strip leading anchor (&name) prefixes from a node-start text.
/// Any explicit tag is an UNSUPPORTED error, per the subset rulings.
fn stripPrefixes(text: []const u8, line_no: usize, col: usize, existing: ?[]const u8) Fail!Prefix {
    var rest = text;
    var c = col;
    var anchor = existing;
    while (true) {
        var k: usize = 0;
        while (k < rest.len and (rest[k] == ' ' or rest[k] == '\t')) k += 1;
        rest = rest[k..];
        c += k;
        if (rest.len == 0) break;
        if (rest[0] == '&') {
            if (anchor != null) return failAt(line_no, c, "duplicate anchor on the same node");
            var e: usize = 1;
            while (e < rest.len and isAnchorChar(rest[e])) e += 1;
            if (e == 1) return failAt(line_no, c, "empty anchor name");
            anchor = rest[1..e];
            rest = rest[e..];
            c += e;
            continue;
        }
        if (rest[0] == '!') {
            return failUnsupported(line_no, c, "explicit tags are not supported");
        }
        break;
    }
    return .{ .anchor = anchor, .rest = rest, .col = c };
}

const Parser = struct {
    alloc: std.mem.Allocator,
    lines: []const Line,
    pos: usize = 0,
    anchors: std.StringHashMapUnmanaged(Value) = .empty,
    pending: ?LineView = null,

    fn registerAnchor(self: *Parser, name: []const u8, value: Value) Fail!void {
        try self.anchors.put(self.alloc, try self.alloc.dupe(u8, name), value);
    }

    fn skipBlankLines(self: *Parser) void {
        while (self.pos < self.lines.len) {
            const raw = self.lines[self.pos].raw;
            if (isBlankRaw(raw) or isCommentRaw(raw)) {
                self.pos += 1;
            } else break;
        }
    }

    fn peekView(self: *Parser) Fail!LineView {
        const line = self.lines[self.pos];
        const ind = try lineIndent(line);
        return .{
            .no = line.no,
            .ind = ind,
            .content = line.raw[ind..],
            .col = line.col0 + ind + 1,
            .physical = true,
        };
    }

    fn parseRoot(self: *Parser) Fail!Value {
        self.skipBlankLines();
        if (self.pos >= self.lines.len) return null_value;
        const v = try self.parseBlockNode(0, null, 0);
        self.skipBlankLines();
        if (self.pos < self.lines.len) {
            const line = self.lines[self.pos];
            return failAt(line.no, 1, "unexpected content after the document's root node");
        }
        return v;
    }

    /// Parse a block node whose first significant line is at indent
    /// >= min_indent. `parent_indent` is the indent of the structure
    /// that owns this node (drives block scalars and plain-scalar
    /// continuation). May consume the parser's pending first-line
    /// view (sequence compact notation).
    fn parseBlockNode(self: *Parser, min_indent: usize, anchor: ?[]const u8, parent_indent: usize) Fail!Value {
        var first: LineView = undefined;
        if (self.pending) |p| {
            first = p;
            self.pending = null;
        } else {
            self.skipBlankLines();
            if (self.pos >= self.lines.len) return null_value;
            first = try self.peekView();
            if (first.ind < min_indent) return null_value;
        }
        const content = stripComment(first.content);
        const pfx = try stripPrefixes(content, first.no, first.col, anchor);
        if (pfx.rest.len == 0) {
            // Anchor-only line: the node is on the following lines.
            if (first.physical) self.pos += 1;
            self.skipBlankLines();
            if (self.pos >= self.lines.len) {
                if (pfx.anchor) |a| try self.registerAnchor(a, null_value);
                return null_value;
            }
            const nv = try self.peekView();
            if (nv.ind < first.ind) {
                if (pfx.anchor) |a| try self.registerAnchor(a, null_value);
                return null_value;
            }
            return self.parseBlockNode(first.ind, pfx.anchor, parent_indent);
        }
        if (isSeqStart(pfx.rest)) {
            const fv = LineView{ .no = first.no, .ind = first.ind, .content = pfx.rest, .col = pfx.col, .physical = first.physical };
            return self.parseBlockSequence(first.ind, pfx.anchor, fv);
        }
        if ((try scanBlockKey(self.alloc, pfx.rest, first.no)) != null) {
            const fv = LineView{ .no = first.no, .ind = first.ind, .content = pfx.rest, .col = pfx.col, .physical = first.physical };
            return self.parseBlockMapping(first.ind, pfx.anchor, fv);
        }
        if (first.physical) self.pos += 1;
        return self.parseInlineNode(pfx.rest, first.no, pfx.col, parent_indent, pfx.anchor);
    }

    /// The value for a key (or a "- " entry) when nothing follows on
    /// the same line: a deeper block node, optionally a sequence at
    /// the key's own indent (mapping values only), or null.
    fn parseNestedValue(self: *Parser, key_indent: usize, anchor: ?[]const u8, allow_same_indent_seq: bool) Fail!Value {
        self.skipBlankLines();
        if (self.pos >= self.lines.len) {
            if (anchor) |a| try self.registerAnchor(a, null_value);
            return null_value;
        }
        const nv = try self.peekView();
        if (nv.ind > key_indent) {
            return self.parseBlockNode(key_indent + 1, anchor, key_indent);
        }
        if (allow_same_indent_seq and nv.ind == key_indent) {
            const content = stripComment(nv.content);
            const pfx = try stripPrefixes(content, nv.no, nv.col, anchor);
            if (isSeqStart(pfx.rest)) {
                const fv = LineView{ .no = nv.no, .ind = nv.ind, .content = pfx.rest, .col = pfx.col, .physical = true };
                return self.parseBlockSequence(key_indent, pfx.anchor, fv);
            }
        }
        if (anchor) |a| try self.registerAnchor(a, null_value);
        return null_value;
    }

    fn parseValueAfterKey(self: *Parser, rest_raw: []const u8, line_no: usize, rest_col: usize, key_indent: usize) Fail!Value {
        const pfx = try stripPrefixes(rest_raw, line_no, rest_col, null);
        if (pfx.rest.len == 0) {
            return self.parseNestedValue(key_indent, pfx.anchor, true);
        }
        return self.parseInlineNode(pfx.rest, line_no, pfx.col, key_indent, pfx.anchor);
    }

    fn parseBlockMapping(self: *Parser, indent: usize, anchor: ?[]const u8, first: LineView) Fail!Value {
        var builder = MapBuilder{ .parts = std.array_list.Managed(MapPart).init(self.alloc) };
        var first_pending: ?LineView = first;
        while (true) {
            const v: LineView = if (first_pending) |f| blk: {
                first_pending = null;
                break :blk f;
            } else blk: {
                self.skipBlankLines();
                if (self.pos >= self.lines.len) break;
                const pv = try self.peekView();
                if (pv.ind != indent) break;
                break :blk pv;
            };
            const content = stripComment(v.content);
            if (content.len == 0) {
                if (v.physical) self.pos += 1;
                continue;
            }
            if (isSeqStart(content)) {
                if (!v.physical) return failAt(v.no, v.col, "unexpected sequence entry inside a mapping");
                break;
            }
            if (content.len >= 2 and content[0] == '?' and content[1] == ' ') {
                return failUnsupported(v.no, v.col, "explicit (complex) keys");
            }
            const hit = (try scanBlockKey(self.alloc, content, v.no)) orelse
                return failAt(v.no, v.col, "could not find expected ':'");
            if (v.physical) self.pos += 1;
            const rest = content[hit.colon + 1 ..];
            const value = try self.parseValueAfterKey(rest, v.no, v.col + hit.colon + 1, indent);
            if (std.mem.eql(u8, hit.key, "<<")) {
                try builder.addMergeChecked(value, v.no, v.col);
            } else {
                try builder.addEntry(hit.key, value, v.no, v.col);
            }
        }
        const result = try builder.finish(self.alloc);
        if (anchor) |a| try self.registerAnchor(a, result);
        return result;
    }

    fn parseBlockSequence(self: *Parser, indent: usize, anchor: ?[]const u8, first: LineView) Fail!Value {
        var items = std.array_list.Managed(Value).init(self.alloc);
        var first_pending: ?LineView = first;
        while (true) {
            const v: LineView = if (first_pending) |f| blk: {
                first_pending = null;
                break :blk f;
            } else blk: {
                self.skipBlankLines();
                if (self.pos >= self.lines.len) break;
                const pv = try self.peekView();
                if (pv.ind != indent) break;
                break :blk pv;
            };
            const content = stripComment(v.content);
            if (!isSeqStart(content)) {
                if (!v.physical) return failAt(v.no, v.col, "expected a sequence entry");
                break;
            }
            if (v.physical) self.pos += 1;
            var idx: usize = 1;
            while (idx < content.len and content[idx] == ' ') idx += 1;
            const rest = content[idx..];
            if (rest.len == 0) {
                const item = try self.parseNestedValue(indent, null, false);
                try items.append(item);
            } else {
                self.pending = .{
                    .no = v.no,
                    .ind = indent + idx,
                    .content = rest,
                    .col = v.col + idx,
                    .physical = false,
                };
                const item = try self.parseBlockNode(indent + idx, null, indent);
                try items.append(item);
            }
        }
        const result = Value{ .kind = KIND_ARRAY, .array = try items.toOwnedSlice() };
        if (anchor) |a| try self.registerAnchor(a, result);
        return result;
    }

    /// Parse a value that starts on the current line: a block scalar
    /// header, a flow collection, a quoted scalar, an alias, or a
    /// plain scalar (which may continue on deeper-indented lines).
    /// `text` is the value's first-line text, prefixes already stripped.
    fn parseInlineNode(self: *Parser, text: []const u8, line_no: usize, col: usize, parent_indent: usize, anchor: ?[]const u8) Fail!Value {
        const c0 = text[0];
        var value: Value = undefined;
        if (c0 == '|' or c0 == '>') {
            value = try self.parseBlockScalar(text, line_no, col, parent_indent);
        } else if (c0 == '[' or c0 == '{') {
            const buf = try self.gatherFlowText(text, line_no);
            var fp = FlowParser{ .p = self, .cur = .{ .buf = buf, .line = line_no, .col = col } };
            value = try fp.parseNode();
            fp.skipWs();
            if (fp.cur.i != buf.len) {
                return failAt(fp.cur.line, fp.cur.col, "unexpected content after flow collection");
            }
        } else if (c0 == '\'' or c0 == '"') {
            value = stringValue(try self.parseQuotedGathered(text, line_no, col, c0));
        } else if (c0 == '*') {
            const name = trimWs(text[1..]);
            if (!validAnchorName(name)) return failAt(line_no, col, "invalid alias name");
            const src = self.anchors.get(name) orelse return failUnknownAlias(name, line_no, col + 1);
            value = try deepClone(self.alloc, src);
        } else {
            value = try self.parsePlainBlockScalar(text, line_no, col, parent_indent);
        }
        if (anchor) |a| try self.registerAnchor(a, value);
        return value;
    }

    fn parseQuotedGathered(self: *Parser, first_text: []const u8, line_no: usize, col: usize, quote: u8) Fail![]const u8 {
        var buf = std.array_list.Managed(u8).init(self.alloc);
        try buf.appendSlice(first_text);
        while (true) {
            var cur = TextCursor{ .buf = buf.items, .line = line_no, .col = col };
            const parsed = if (quote == '\'') parseSingleQuoted(self.alloc, &cur) else parseDoubleQuoted(self.alloc, &cur);
            if (parsed) |text| {
                var rest = buf.items[cur.i..];
                if (std.mem.indexOfScalar(u8, rest, '\n')) |nl| rest = rest[0..nl];
                if (trimWs(stripComment(rest)).len != 0) {
                    return failAt(cur.line, cur.col, "unexpected content after quoted scalar");
                }
                return text;
            } else |err| switch (err) {
                error.Unterminated => {
                    if (self.pos >= self.lines.len) {
                        return failAt(line_no, col, "unterminated quoted scalar");
                    }
                    try buf.append('\n');
                    try buf.appendSlice(self.lines[self.pos].raw);
                    self.pos += 1;
                },
                error.OutOfMemory => return error.OutOfMemory,
                error.ParseFail => return error.ParseFail,
            }
        }
    }

    fn parsePlainBlockScalar(self: *Parser, first_text: []const u8, line_no: usize, col: usize, parent_indent: usize) Fail!Value {
        if (first_text.len > 1 and first_text[0] == '-' and first_text[1] == ' ') {
            return failAt(line_no, col, "block sequence entries are not allowed in this context");
        }
        if (first_text.len > 1 and first_text[0] == '?' and first_text[1] == ' ') {
            return failUnsupported(line_no, col, "explicit (complex) keys");
        }
        if (std.mem.indexOf(u8, first_text, ": ") != null) {
            return failAt(line_no, col, "mapping values are not allowed here");
        }
        const Part = struct { text: []const u8, gap: usize };
        var parts = std.array_list.Managed(Part).init(self.alloc);
        try parts.append(.{ .text = rtrimWs(first_text), .gap = 0 });
        var scan = self.pos;
        var consumed = self.pos;
        var pending_blanks: usize = 0;
        while (scan < self.lines.len) {
            const line = self.lines[scan];
            if (isBlankRaw(line.raw) or isCommentRaw(line.raw)) {
                pending_blanks += 1;
                scan += 1;
                continue;
            }
            const ind = try lineIndent(line);
            if (ind <= parent_indent) break;
            const content = stripComment(line.raw[ind..]);
            if (content.len == 0) {
                pending_blanks += 1;
                scan += 1;
                continue;
            }
            if (isSeqStart(content)) {
                return failAt(line.no, line.col0 + ind + 1, "block sequence entries are not allowed in this context");
            }
            if ((try scanBlockKey(self.alloc, content, line.no)) != null) {
                return failAt(line.no, line.col0 + ind + 1, "mapping values are not allowed here");
            }
            try parts.append(.{ .text = content, .gap = pending_blanks + 1 });
            pending_blanks = 0;
            scan += 1;
            consumed = scan;
        }
        self.pos = consumed;
        var out = std.array_list.Managed(u8).init(self.alloc);
        for (parts.items, 0..) |part, idx| {
            if (idx > 0) try appendFoldedBreak(&out, part.gap);
            try out.appendSlice(part.text);
        }
        const text = try out.toOwnedSlice();
        return resolvePlainScalar(self.alloc, text);
    }

    fn parseBlockScalar(self: *Parser, header: []const u8, line_no: usize, col: usize, parent_indent: usize) Fail!Value {
        const folded = header[0] == '>';
        var chomp: enum { clip, strip, keep } = .clip;
        var indicator: ?usize = null;
        var seen_chomp = false;
        var seen_ind = false;
        var i: usize = 1;
        while (i < header.len) : (i += 1) {
            const c = header[i];
            if (c == '+' or c == '-') {
                if (seen_chomp) return failAt(line_no, col + i, "duplicate chomping indicator in block scalar header");
                seen_chomp = true;
                chomp = if (c == '+') .keep else .strip;
            } else if (c >= '1' and c <= '9') {
                if (seen_ind) return failAt(line_no, col + i, "duplicate indent indicator in block scalar header");
                seen_ind = true;
                indicator = c - '0';
            } else break;
        }
        if (trimWs(header[i..]).len != 0) {
            return failAt(line_no, col + i, "invalid block scalar header");
        }

        var content_indent: usize = undefined;
        if (indicator) |d| {
            content_indent = parent_indent + d;
        } else {
            var detected: ?usize = null;
            var j = self.pos;
            while (j < self.lines.len) : (j += 1) {
                const line = self.lines[j];
                if (isBlankRaw(line.raw)) continue;
                detected = countLeadingSpaces(line.raw);
                break;
            }
            if (detected == null or detected.? <= parent_indent) {
                return stringValue("");
            }
            content_indent = detected.?;
        }

        var collected = std.array_list.Managed([]const u8).init(self.alloc);
        var j = self.pos;
        while (j < self.lines.len) : (j += 1) {
            const line = self.lines[j];
            if (isBlankRaw(line.raw)) {
                try collected.append("");
                continue;
            }
            const sp = countLeadingSpaces(line.raw);
            if (sp < content_indent) break;
            try collected.append(line.raw[content_indent..]);
        }
        self.pos = j;

        var trailing: usize = 0;
        while (collected.items.len > 0 and collected.items[collected.items.len - 1].len == 0) {
            trailing += 1;
            _ = collected.pop();
        }
        const body = collected.items;

        var out = std.array_list.Managed(u8).init(self.alloc);
        if (!folded) {
            for (body, 0..) |l, idx| {
                if (idx > 0) try out.append('\n');
                try out.appendSlice(l);
            }
        } else {
            // Folded style: a run of k breaks between two content
            // lines becomes one space (k == 1, unless either line is
            // more-indented) or k-1 breaks (k >= 2). Leading blank
            // lines are breaks verbatim.
            var idx: usize = 0;
            while (idx < body.len and body[idx].len == 0) : (idx += 1) {
                try out.append('\n');
            }
            var have_prev = false;
            var prev_line: []const u8 = "";
            var gap: usize = 0;
            while (idx < body.len) {
                const l = body[idx];
                if (have_prev) {
                    if (gap == 1) {
                        if (prev_line[0] == ' ' or l[0] == ' ') {
                            try out.append('\n');
                        } else {
                            try out.append(' ');
                        }
                    } else {
                        for (0..gap - 1) |_| try out.append('\n');
                    }
                }
                try out.appendSlice(l);
                prev_line = l;
                have_prev = true;
                var blanks: usize = 0;
                var nxt = idx + 1;
                while (nxt < body.len and body[nxt].len == 0) {
                    blanks += 1;
                    nxt += 1;
                }
                gap = blanks + 1;
                idx = nxt;
            }
        }
        if (body.len > 0) {
            for (0..trailing + 1) |_| try out.append('\n');
        } else {
            for (0..trailing) |_| try out.append('\n');
        }
        var text = try out.toOwnedSlice();
        switch (chomp) {
            .strip => {
                var end = text.len;
                while (end > 0 and text[end - 1] == '\n') end -= 1;
                text = text[0..end];
            },
            .clip => {
                var end = text.len;
                while (end > 0 and text[end - 1] == '\n') end -= 1;
                if (end == 0) {
                    text = "";
                } else {
                    const nt = try self.alloc.alloc(u8, end + 1);
                    @memcpy(nt[0..end], text[0..end]);
                    nt[end] = '\n';
                    text = nt;
                }
            },
            .keep => {},
        }
        return stringValue(text);
    }

    /// Gather a flow collection's full text: the first line's text
    /// plus raw following lines until the brackets balance.
    fn gatherFlowText(self: *Parser, first_text: []const u8, line_no: usize) Fail![]const u8 {
        var buf = std.array_list.Managed(u8).init(self.alloc);
        try buf.appendSlice(first_text);
        while (!flowBalanced(buf.items)) {
            if (self.pos >= self.lines.len) {
                return failAt(line_no, 1, "unterminated flow collection");
            }
            try buf.append('\n');
            try buf.appendSlice(self.lines[self.pos].raw);
            self.pos += 1;
        }
        return buf.toOwnedSlice();
    }
};

fn flowBalanced(buf: []const u8) bool {
    var depth: i32 = 0;
    var quote: u8 = 0;
    var comment = false;
    var i: usize = 0;
    while (i < buf.len) {
        const c = buf[i];
        if (comment) {
            if (c == '\n') comment = false;
            i += 1;
            continue;
        }
        if (quote == '\'') {
            if (c == '\'') {
                if (i + 1 < buf.len and buf[i + 1] == '\'') {
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
        if (c == '#' and (i == 0 or buf[i - 1] == ' ' or buf[i - 1] == '\t' or buf[i - 1] == '\n')) {
            comment = true;
            i += 1;
            continue;
        }
        if (c == '\'' or c == '"') {
            quote = c;
            i += 1;
            continue;
        }
        if (c == '[' or c == '{') depth += 1;
        if (c == ']' or c == '}') depth -= 1;
        i += 1;
    }
    return depth <= 0;
}

// ---------------- flow parser ----------------

fn foldFlowPlain(alloc: std.mem.Allocator, raw: []const u8) Fail![]const u8 {
    var out = std.array_list.Managed(u8).init(alloc);
    var it = std.mem.splitScalar(u8, raw, '\n');
    var started = false;
    var pending_newlines: usize = 0;
    while (it.next()) |seg0| {
        const seg = trimWs(seg0);
        if (!started) {
            if (seg.len == 0) continue;
            try out.appendSlice(seg);
            started = true;
            continue;
        }
        if (seg.len == 0) {
            pending_newlines += 1;
            continue;
        }
        try appendFoldedBreak(&out, pending_newlines + 1);
        try out.appendSlice(seg);
        pending_newlines = 0;
    }
    return out.toOwnedSlice();
}

const FlowParser = struct {
    p: *Parser,
    cur: TextCursor,

    const FlowNode = struct { value: Value, key_text: ?[]const u8 = null };

    fn skipWs(self: *FlowParser) void {
        while (self.cur.peek()) |c| {
            if (c == ' ' or c == '\t' or c == '\n' or c == '\r') {
                _ = self.cur.bump();
                continue;
            }
            if (c == '#') {
                while (self.cur.peek()) |cc| {
                    if (cc == '\n') break;
                    _ = self.cur.bump();
                }
                continue;
            }
            break;
        }
    }

    fn parseNode(self: *FlowParser) Fail!Value {
        const n = try self.parseNodeFull();
        return n.value;
    }

    fn parseNodeFull(self: *FlowParser) Fail!FlowNode {
        var anchor: ?[]const u8 = null;
        while (true) {
            self.skipWs();
            const c = self.cur.peek() orelse
                return failAt(self.cur.line, self.cur.col, "unexpected end of flow collection");
            if (c == '&') {
                if (anchor != null) return failAt(self.cur.line, self.cur.col, "duplicate anchor on the same node");
                _ = self.cur.bump();
                anchor = try self.readAnchorName();
                continue;
            }
            if (c == '!') return failUnsupported(self.cur.line, self.cur.col, "explicit tags are not supported");
            break;
        }
        const node = try self.parseFlowAtom();
        if (anchor) |a| try self.p.registerAnchor(a, node.value);
        return node;
    }

    fn readAnchorName(self: *FlowParser) Fail![]const u8 {
        const start = self.cur.i;
        while (self.cur.peek()) |c| {
            if (!isAnchorChar(c)) break;
            _ = self.cur.bump();
        }
        if (self.cur.i == start) return failAt(self.cur.line, self.cur.col, "empty anchor name");
        return self.cur.buf[start..self.cur.i];
    }

    fn parseFlowAtom(self: *FlowParser) Fail!FlowNode {
        const c = self.cur.peek() orelse
            return failAt(self.cur.line, self.cur.col, "unexpected end of flow collection");
        switch (c) {
            '[' => return self.parseFlowSequence(),
            '{' => return self.parseFlowMapping(),
            '|', '>' => return failAt(self.cur.line, self.cur.col, "block scalars are not allowed in flow collections"),
            '\'', '"' => {
                const text = (if (c == '\'') parseSingleQuoted(self.p.alloc, &self.cur) else parseDoubleQuoted(self.p.alloc, &self.cur)) catch |err| switch (err) {
                    error.Unterminated => return failAt(self.cur.line, self.cur.col, "unterminated quoted scalar"),
                    error.OutOfMemory => return error.OutOfMemory,
                    error.ParseFail => return error.ParseFail,
                };
                return .{ .value = stringValue(text), .key_text = text };
            },
            '*' => {
                _ = self.cur.bump();
                const name = try self.readAnchorName();
                const src = self.p.anchors.get(name) orelse
                    return failUnknownAlias(name, self.cur.line, self.cur.col);
                const v = try deepClone(self.p.alloc, src);
                return .{ .value = v, .key_text = if (v.kind == KIND_STRING) v.str else null };
            },
            else => return self.parseFlowPlain(),
        }
    }

    fn parseFlowPlain(self: *FlowParser) Fail!FlowNode {
        const start_line = self.cur.line;
        const start_col = self.cur.col;
        var raw = std.array_list.Managed(u8).init(self.p.alloc);
        var prev: ?u8 = null;
        while (self.cur.peek()) |c| {
            if (c == ',' or c == '[' or c == ']' or c == '{' or c == '}') break;
            if (c == ':') {
                const n = self.cur.peekAt(1);
                if (n == null or n == ' ' or n == '\t' or n == '\n' or n == ',' or
                    n == ']' or n == '}' or n == '[' or n == '{') break;
            }
            if (c == '#') {
                if (prev == null or prev == ' ' or prev == '\t' or prev == '\n') break;
            }
            try raw.append(c);
            prev = c;
            _ = self.cur.bump();
        }
        const text = try foldFlowPlain(self.p.alloc, raw.items);
        if (text.len == 0) return failAt(start_line, start_col, "expected a value");
        const v = try resolvePlainScalar(self.p.alloc, text);
        return .{ .value = v, .key_text = text };
    }

    fn parsePairValue(self: *FlowParser) Fail!Value {
        self.skipWs();
        const c = self.cur.peek();
        if (c == null or c == ',' or c == '}' or c == ']') return null_value;
        return self.parseNode();
    }

    fn parseFlowSequence(self: *FlowParser) Fail!FlowNode {
        _ = self.cur.bump(); // '['
        var items = std.array_list.Managed(Value).init(self.p.alloc);
        self.skipWs();
        if (self.cur.peek() == ']') {
            _ = self.cur.bump();
            return .{ .value = .{ .kind = KIND_ARRAY, .array = &.{} } };
        }
        while (true) {
            const entry = try self.parseFlowEntry();
            try items.append(entry);
            self.skipWs();
            const c = self.cur.peek() orelse
                return failAt(self.cur.line, self.cur.col, "unterminated flow sequence");
            if (c == ',') {
                _ = self.cur.bump();
                self.skipWs();
                if (self.cur.peek() == ']') {
                    _ = self.cur.bump();
                    break;
                }
                continue;
            }
            if (c == ']') {
                _ = self.cur.bump();
                break;
            }
            return failAt(self.cur.line, self.cur.col, "expected ',' or ']' in flow sequence");
        }
        return .{ .value = .{ .kind = KIND_ARRAY, .array = try items.toOwnedSlice() } };
    }

    fn parseFlowEntry(self: *FlowParser) Fail!Value {
        const first = try self.parseNodeFull();
        self.skipWs();
        if (self.cur.peek() == ':') {
            const key = first.key_text orelse
                return failAt(self.cur.line, self.cur.col, "mapping key in a flow sequence must be a scalar");
            const key_line = self.cur.line;
            const key_col = self.cur.col;
            _ = self.cur.bump();
            var builder = MapBuilder{ .parts = std.array_list.Managed(MapPart).init(self.p.alloc) };
            const val = try self.parsePairValue();
            if (std.mem.eql(u8, key, "<<")) {
                try builder.addMergeChecked(val, key_line, key_col);
            } else {
                try builder.addEntry(key, val, key_line, key_col);
            }
            return builder.finish(self.p.alloc);
        }
        return first.value;
    }

    fn parseFlowMapping(self: *FlowParser) Fail!FlowNode {
        _ = self.cur.bump(); // '{'
        var builder = MapBuilder{ .parts = std.array_list.Managed(MapPart).init(self.p.alloc) };
        self.skipWs();
        if (self.cur.peek() == '}') {
            _ = self.cur.bump();
            return .{ .value = try builder.finish(self.p.alloc) };
        }
        while (true) {
            self.skipWs();
            if (self.cur.peek() == '?') {
                const n = self.cur.peekAt(1);
                if (n == null or n == ' ' or n == '\t' or n == '\n' or n == ',' or n == '}') {
                    return failUnsupported(self.cur.line, self.cur.col, "explicit (complex) keys");
                }
            }
            const key_line = self.cur.line;
            const key_col = self.cur.col;
            const kn = try self.parseNodeFull();
            const key = kn.key_text orelse
                return failAt(key_line, key_col, "mapping key must be a scalar (complex keys are unsupported)");
            self.skipWs();
            var value: Value = null_value;
            if (self.cur.peek() == ':') {
                _ = self.cur.bump();
                value = try self.parsePairValue();
            }
            if (std.mem.eql(u8, key, "<<")) {
                try builder.addMergeChecked(value, key_line, key_col);
            } else {
                try builder.addEntry(key, value, key_line, key_col);
            }
            self.skipWs();
            const c = self.cur.peek() orelse
                return failAt(self.cur.line, self.cur.col, "unterminated flow mapping");
            if (c == ',') {
                _ = self.cur.bump();
                self.skipWs();
                if (self.cur.peek() == '}') {
                    _ = self.cur.bump();
                    break;
                }
                continue;
            }
            if (c == '}') {
                _ = self.cur.bump();
                break;
            }
            return failAt(self.cur.line, self.cur.col, "expected ',' or '}' in flow mapping");
        }
        return .{ .value = try builder.finish(self.p.alloc) };
    }
};

// ---------------- dotted-path access and mutation ----------------

fn parseIndex(seg: []const u8) ?usize {
    if (seg.len == 0) return null;
    for (seg) |c| {
        if (c < '0' or c > '9') return null;
    }
    return std.fmt.parseInt(usize, seg, 10) catch null;
}

fn resolveValue(root: *const Value, path: []const u8) ?*const Value {
    var cursor: *const Value = root;
    if (path.len == 0) return cursor;
    var it = std.mem.splitScalar(u8, path, '.');
    while (it.next()) |seg| {
        if (cursor.kind == KIND_TABLE) {
            cursor = findInEntries(cursor.table.?.entries.items, seg) orelse return null;
        } else if (cursor.kind == KIND_ARRAY) {
            const idx = parseIndex(seg) orelse return null;
            if (idx >= cursor.array.len) return null;
            cursor = &cursor.array[idx];
        } else return null;
    }
    return cursor;
}

fn findEntryMut(table: *Table, key: []const u8) ?*Entry {
    for (table.entries.items) |*e| {
        if (std.mem.eql(u8, e.key, key)) return e;
    }
    return null;
}

const WalkError = error{ NotFound, Invalid, OutOfMemory };

/// Descend through `segs` without creating anything.
fn descendMut(doc: *Document, segs: []const []const u8) WalkError!*Value {
    var cursor: *Value = &doc.root;
    for (segs) |seg| {
        if (cursor.kind == KIND_TABLE) {
            const e = findEntryMut(cursor.table.?, seg) orelse return error.NotFound;
            cursor = &e.value;
        } else if (cursor.kind == KIND_ARRAY) {
            const idx = parseIndex(seg) orelse return error.Invalid;
            if (idx >= cursor.array.len) return error.NotFound;
            cursor = &cursor.array[idx];
        } else return error.Invalid;
    }
    return cursor;
}

/// Descend through `segs`, creating intermediate tables on demand,
/// and return the table the walk ends in. Mirrors sa_toml's mutation
/// walks: intermediate segments may pass through arrays via numeric
/// segments, but the walk must end in a table.
fn walkParentTable(doc: *Document, segs: []const []const u8) WalkError!*Table {
    var cursor: *Value = &doc.root;
    for (segs) |seg| {
        if (cursor.kind == KIND_TABLE) {
            const t = cursor.table.?;
            if (findEntryMut(t, seg)) |e| {
                cursor = &e.value;
            } else {
                const nt = try newTableValue(doc);
                try t.entries.append(.{ .key = try doc.alloc().dupe(u8, seg), .value = nt });
                cursor = &t.entries.items[t.entries.items.len - 1].value;
            }
        } else if (cursor.kind == KIND_ARRAY) {
            const idx = parseIndex(seg) orelse return error.Invalid;
            if (idx >= cursor.array.len) return error.NotFound;
            cursor = &cursor.array[idx];
        } else return error.Invalid;
    }
    if (cursor.kind != KIND_TABLE) return error.Invalid;
    return cursor.table.?;
}

fn newTableValue(doc: *Document) !Value {
    const table = try doc.alloc().create(Table);
    table.* = .{ .entries = std.array_list.Managed(Entry).init(doc.alloc()) };
    return .{ .kind = KIND_TABLE, .table = table };
}

fn splitPathAlloc(alloc: std.mem.Allocator, path: []const u8) ![][]const u8 {
    var segs = std.array_list.Managed([]const u8).init(alloc);
    var it = std.mem.splitScalar(u8, path, '.');
    while (it.next()) |seg| try segs.append(seg);
    return segs.toOwnedSlice();
}

fn walkStatus(err: WalkError) i32 {
    return switch (err) {
        error.NotFound => ERR_NOT_FOUND,
        error.Invalid => ERR_INVALID,
        error.OutOfMemory => ERR_NOMEM,
    };
}

/// Install `value` at `path` (final segment is always a table key),
/// creating intermediate tables on demand and replacing whatever sat
/// at the path. The replaced subtree stays in the document arena
/// until sa_yaml_free -- there is no per-value free in this module.
fn setValueAt(doc: *Document, path: []const u8, value: Value) i32 {
    if (path.len == 0) return ERR_INVALID;
    const segs = splitPathAlloc(doc.alloc(), path) catch return ERR_NOMEM;
    const parent = walkParentTable(doc, segs[0 .. segs.len - 1]) catch |err| return walkStatus(err);
    const key = segs[segs.len - 1];
    if (findEntryMut(parent, key)) |e| {
        e.value = value;
    } else {
        const key_copy = doc.alloc().dupe(u8, key) catch return ERR_NOMEM;
        parent.entries.append(.{ .key = key_copy, .value = value }) catch return ERR_NOMEM;
    }
    doc.invalidateBuffers();
    return OK;
}

fn pushValueAt(doc: *Document, path: []const u8, value: Value) i32 {
    if (path.len == 0) return ERR_INVALID;
    if (resolveValue(&doc.root, path)) |existing| {
        if (existing.kind != KIND_ARRAY) return ERR_INVALID;
    }
    const segs = splitPathAlloc(doc.alloc(), path) catch return ERR_NOMEM;
    const parent = walkParentTable(doc, segs[0 .. segs.len - 1]) catch |err| return walkStatus(err);
    const key = segs[segs.len - 1];
    if (findEntryMut(parent, key)) |e| {
        var items = std.array_list.Managed(Value).init(doc.alloc());
        items.appendSlice(e.value.array) catch return ERR_NOMEM;
        items.append(value) catch return ERR_NOMEM;
        e.value.array = items.toOwnedSlice() catch return ERR_NOMEM;
    } else {
        const key_copy = doc.alloc().dupe(u8, key) catch return ERR_NOMEM;
        const arr = doc.alloc().alloc(Value, 1) catch return ERR_NOMEM;
        arr[0] = value;
        parent.entries.append(.{ .key = key_copy, .value = .{ .kind = KIND_ARRAY, .array = arr } }) catch return ERR_NOMEM;
    }
    doc.invalidateBuffers();
    return OK;
}

fn removeAt(doc: *Document, path: []const u8) i32 {
    if (path.len == 0) return ERR_INVALID;
    const segs = splitPathAlloc(doc.alloc(), path) catch return ERR_NOMEM;
    const container = descendMut(doc, segs[0 .. segs.len - 1]) catch |err| return walkStatus(err);
    const last = segs[segs.len - 1];
    if (container.kind == KIND_TABLE) {
        const t = container.table.?;
        for (t.entries.items, 0..) |e, i| {
            if (std.mem.eql(u8, e.key, last)) {
                _ = t.entries.orderedRemove(i);
                doc.invalidateBuffers();
                return OK;
            }
        }
        return ERR_NOT_FOUND;
    }
    if (container.kind == KIND_ARRAY) {
        const idx = parseIndex(last) orelse return ERR_INVALID;
        if (idx >= container.array.len) return ERR_NOT_FOUND;
        if (container.array.len > 1) {
            std.mem.copyForwards(Value, container.array[idx .. container.array.len - 1], container.array[idx + 1 ..]);
        }
        container.array = container.array[0 .. container.array.len - 1];
        doc.invalidateBuffers();
        return OK;
    }
    return ERR_INVALID;
}

// ---------------- exports ----------------

fn parseToDocument(input: []const u8, index: ?usize) ?*Document {
    const alloc = std.heap.page_allocator;
    var split = splitDocuments(alloc, input) catch |err| {
        if (err == error.OutOfMemory) setLastError("yaml: out of memory", .{});
        return null;
    };
    defer split.deinit();
    if (index) |which| {
        if (which >= split.ranges.len) {
            setLastError("yaml: document index {d} out of range ({d} document(s) in stream)", .{ which, split.ranges.len });
            return null;
        }
    }
    const doc = newDocument() catch {
        setLastError("yaml: out of memory", .{});
        return null;
    };
    if (split.ranges.len == 0) {
        doc.root = null_value;
        return doc;
    }
    const range = split.ranges[index orelse 0];
    var parser = Parser{ .alloc = doc.alloc(), .lines = split.lines[range.start..range.end] };
    const root = parser.parseRoot() catch |err| {
        if (err == error.OutOfMemory and last_error_len == 0) setLastError("yaml: out of memory", .{});
        doc.deinit();
        return null;
    };
    doc.root = root;
    return doc;
}

pub export fn sa_yaml_parse(bytes: ?[*]const u8, len: u64) u64 {
    clearLastError();
    const input = constSlice(bytes, len) orelse {
        setLastError("yaml: invalid argument (null bytes)", .{});
        return 0;
    };
    const doc = parseToDocument(input, null) orelse return 0;
    return registerDocument(doc) catch {
        doc.deinit();
        return 0;
    };
}

pub export fn sa_yaml_parse_at(bytes: ?[*]const u8, len: u64, index: u64) u64 {
    clearLastError();
    const input = constSlice(bytes, len) orelse {
        setLastError("yaml: invalid argument (null bytes)", .{});
        return 0;
    };
    const doc = parseToDocument(input, @intCast(index)) orelse return 0;
    return registerDocument(doc) catch {
        doc.deinit();
        return 0;
    };
}

pub export fn sa_yaml_count_documents(bytes: ?[*]const u8, len: u64, out_count: ?*u64) i32 {
    clearLastError();
    const slot = out_count orelse return ERR_INVALID;
    slot.* = 0;
    const input = constSlice(bytes, len) orelse return ERR_INVALID;
    var split = splitDocuments(std.heap.page_allocator, input) catch |err| {
        if (err == error.OutOfMemory) {
            setLastError("yaml: out of memory", .{});
            return ERR_NOMEM;
        }
        return ERR_INVALID;
    };
    defer split.deinit();
    slot.* = @intCast(split.ranges.len);
    return OK;
}

pub export fn sa_yaml_free(handle: u64) i32 {
    const doc = removeDocument(handle) orelse return ERR_HANDLE;
    doc.deinit();
    return OK;
}

pub export fn sa_yaml_last_error(out_ptr: ?*?[*]const u8, out_len: ?*u64) i32 {
    const ptr_slot = out_ptr orelse return ERR_INVALID;
    const len_slot = out_len orelse return ERR_INVALID;
    if (last_error_len == 0) {
        ptr_slot.* = null;
        len_slot.* = 0;
        return ERR_NOT_FOUND;
    }
    ptr_slot.* = last_error_buf[0..last_error_len].ptr;
    len_slot.* = @intCast(last_error_len);
    return OK;
}

pub export fn sa_yaml_kind(handle: u64, path_ptr: ?[*]const u8, path_len: u64, out_kind: ?*u32) i32 {
    const slot = out_kind orelse return ERR_INVALID;
    slot.* = KIND_UNDEFINED;
    const doc = getDocument(handle) orelse return ERR_HANDLE;
    const path = constSlice(path_ptr, path_len) orelse return ERR_INVALID;
    const v = resolveValue(&doc.root, path) orelse return ERR_NOT_FOUND;
    slot.* = v.kind;
    return OK;
}

pub export fn sa_yaml_get_string(handle: u64, path_ptr: ?[*]const u8, path_len: u64, out_ptr: ?*?[*]const u8, out_len: ?*u64) i32 {
    const ptr_slot = out_ptr orelse return ERR_INVALID;
    const len_slot = out_len orelse return ERR_INVALID;
    ptr_slot.* = null;
    len_slot.* = 0;
    const doc = getDocument(handle) orelse return ERR_HANDLE;
    const path = constSlice(path_ptr, path_len) orelse return ERR_INVALID;
    const v = resolveValue(&doc.root, path) orelse return ERR_NOT_FOUND;
    if (v.kind != KIND_STRING) return ERR_INVALID;
    ptr_slot.* = v.str.ptr;
    len_slot.* = @intCast(v.str.len);
    return OK;
}

pub export fn sa_yaml_get_i64(handle: u64, path_ptr: ?[*]const u8, path_len: u64, out_value: ?*i64) i32 {
    const slot = out_value orelse return ERR_INVALID;
    slot.* = 0;
    const doc = getDocument(handle) orelse return ERR_HANDLE;
    const path = constSlice(path_ptr, path_len) orelse return ERR_INVALID;
    const v = resolveValue(&doc.root, path) orelse return ERR_NOT_FOUND;
    if (v.kind != KIND_INTEGER) return ERR_INVALID;
    slot.* = v.int;
    return OK;
}

pub export fn sa_yaml_get_f64(handle: u64, path_ptr: ?[*]const u8, path_len: u64, out_value: ?*f64) i32 {
    const slot = out_value orelse return ERR_INVALID;
    slot.* = 0;
    const doc = getDocument(handle) orelse return ERR_HANDLE;
    const path = constSlice(path_ptr, path_len) orelse return ERR_INVALID;
    const v = resolveValue(&doc.root, path) orelse return ERR_NOT_FOUND;
    if (v.kind != KIND_FLOAT) return ERR_INVALID;
    slot.* = v.float;
    return OK;
}

pub export fn sa_yaml_get_bool(handle: u64, path_ptr: ?[*]const u8, path_len: u64, out_value: ?*u32) i32 {
    const slot = out_value orelse return ERR_INVALID;
    slot.* = 0;
    const doc = getDocument(handle) orelse return ERR_HANDLE;
    const path = constSlice(path_ptr, path_len) orelse return ERR_INVALID;
    const v = resolveValue(&doc.root, path) orelse return ERR_NOT_FOUND;
    if (v.kind != KIND_BOOL) return ERR_INVALID;
    slot.* = if (v.boolean) 1 else 0;
    return OK;
}

pub export fn sa_yaml_array_len(handle: u64, path_ptr: ?[*]const u8, path_len: u64, out_len: ?*u64) i32 {
    const slot = out_len orelse return ERR_INVALID;
    slot.* = 0;
    const doc = getDocument(handle) orelse return ERR_HANDLE;
    const path = constSlice(path_ptr, path_len) orelse return ERR_INVALID;
    const v = resolveValue(&doc.root, path) orelse return ERR_NOT_FOUND;
    if (v.kind != KIND_ARRAY) return ERR_INVALID;
    slot.* = @intCast(v.array.len);
    return OK;
}

pub export fn sa_yaml_table_len(handle: u64, path_ptr: ?[*]const u8, path_len: u64, out_len: ?*u64) i32 {
    const slot = out_len orelse return ERR_INVALID;
    slot.* = 0;
    const doc = getDocument(handle) orelse return ERR_HANDLE;
    const path = constSlice(path_ptr, path_len) orelse return ERR_INVALID;
    const v = resolveValue(&doc.root, path) orelse return ERR_NOT_FOUND;
    if (v.kind != KIND_TABLE) return ERR_INVALID;
    slot.* = @intCast(v.table.?.entries.items.len);
    return OK;
}

pub export fn sa_yaml_array_get_string(handle: u64, path_ptr: ?[*]const u8, path_len: u64, index: u64, out_ptr: ?*?[*]const u8, out_len: ?*u64) i32 {
    const ptr_slot = out_ptr orelse return ERR_INVALID;
    const len_slot = out_len orelse return ERR_INVALID;
    ptr_slot.* = null;
    len_slot.* = 0;
    const doc = getDocument(handle) orelse return ERR_HANDLE;
    const path = constSlice(path_ptr, path_len) orelse return ERR_INVALID;
    const v = resolveValue(&doc.root, path) orelse return ERR_NOT_FOUND;
    if (v.kind != KIND_ARRAY) return ERR_INVALID;
    if (index >= v.array.len) return ERR_NOT_FOUND;
    const elem = v.array[@intCast(index)];
    if (elem.kind != KIND_STRING) return ERR_INVALID;
    ptr_slot.* = elem.str.ptr;
    len_slot.* = @intCast(elem.str.len);
    return OK;
}

pub export fn sa_yaml_array_get_i64(handle: u64, path_ptr: ?[*]const u8, path_len: u64, index: u64, out_value: ?*i64) i32 {
    const slot = out_value orelse return ERR_INVALID;
    slot.* = 0;
    const doc = getDocument(handle) orelse return ERR_HANDLE;
    const path = constSlice(path_ptr, path_len) orelse return ERR_INVALID;
    const v = resolveValue(&doc.root, path) orelse return ERR_NOT_FOUND;
    if (v.kind != KIND_ARRAY) return ERR_INVALID;
    if (index >= v.array.len) return ERR_NOT_FOUND;
    const elem = v.array[@intCast(index)];
    if (elem.kind != KIND_INTEGER) return ERR_INVALID;
    slot.* = elem.int;
    return OK;
}

pub export fn sa_yaml_table_key_at(handle: u64, path_ptr: ?[*]const u8, path_len: u64, index: u64, out_ptr: ?*?[*]const u8, out_len: ?*u64) i32 {
    const ptr_slot = out_ptr orelse return ERR_INVALID;
    const len_slot = out_len orelse return ERR_INVALID;
    ptr_slot.* = null;
    len_slot.* = 0;
    const doc = getDocument(handle) orelse return ERR_HANDLE;
    const path = constSlice(path_ptr, path_len) orelse return ERR_INVALID;
    const v = resolveValue(&doc.root, path) orelse return ERR_NOT_FOUND;
    if (v.kind != KIND_TABLE) return ERR_INVALID;
    const entries = v.table.?.entries.items;
    if (index >= entries.len) return ERR_NOT_FOUND;
    const key = entries[@intCast(index)].key;
    ptr_slot.* = key.ptr;
    len_slot.* = @intCast(key.len);
    return OK;
}

pub export fn sa_yaml_new() u64 {
    clearLastError();
    const doc = newDocument() catch return 0;
    return registerDocument(doc) catch {
        doc.deinit();
        return 0;
    };
}

pub export fn sa_yaml_set_string(handle: u64, path_ptr: ?[*]const u8, path_len: u64, value_ptr: ?[*]const u8, value_len: u64) i32 {
    const doc = getDocument(handle) orelse return ERR_HANDLE;
    const path = constSlice(path_ptr, path_len) orelse return ERR_INVALID;
    const value = constSlice(value_ptr, value_len) orelse return ERR_INVALID;
    const copy = doc.alloc().dupe(u8, value) catch return ERR_NOMEM;
    return setValueAt(doc, path, stringValue(copy));
}

pub export fn sa_yaml_set_i64(handle: u64, path_ptr: ?[*]const u8, path_len: u64, value: i64) i32 {
    const doc = getDocument(handle) orelse return ERR_HANDLE;
    const path = constSlice(path_ptr, path_len) orelse return ERR_INVALID;
    return setValueAt(doc, path, .{ .kind = KIND_INTEGER, .int = value });
}

pub export fn sa_yaml_set_f64(handle: u64, path_ptr: ?[*]const u8, path_len: u64, value: f64) i32 {
    const doc = getDocument(handle) orelse return ERR_HANDLE;
    const path = constSlice(path_ptr, path_len) orelse return ERR_INVALID;
    return setValueAt(doc, path, .{ .kind = KIND_FLOAT, .float = value });
}

pub export fn sa_yaml_set_bool(handle: u64, path_ptr: ?[*]const u8, path_len: u64, value: u32) i32 {
    const doc = getDocument(handle) orelse return ERR_HANDLE;
    const path = constSlice(path_ptr, path_len) orelse return ERR_INVALID;
    return setValueAt(doc, path, .{ .kind = KIND_BOOL, .boolean = value != 0 });
}

pub export fn sa_yaml_set_null(handle: u64, path_ptr: ?[*]const u8, path_len: u64) i32 {
    const doc = getDocument(handle) orelse return ERR_HANDLE;
    const path = constSlice(path_ptr, path_len) orelse return ERR_INVALID;
    return setValueAt(doc, path, null_value);
}

pub export fn sa_yaml_set_table(handle: u64, path_ptr: ?[*]const u8, path_len: u64) i32 {
    const doc = getDocument(handle) orelse return ERR_HANDLE;
    const path = constSlice(path_ptr, path_len) orelse return ERR_INVALID;
    const value = newTableValue(doc) catch return ERR_NOMEM;
    return setValueAt(doc, path, value);
}

pub export fn sa_yaml_remove(handle: u64, path_ptr: ?[*]const u8, path_len: u64) i32 {
    const doc = getDocument(handle) orelse return ERR_HANDLE;
    const path = constSlice(path_ptr, path_len) orelse return ERR_INVALID;
    return removeAt(doc, path);
}

pub export fn sa_yaml_array_push_string(handle: u64, path_ptr: ?[*]const u8, path_len: u64, value_ptr: ?[*]const u8, value_len: u64) i32 {
    const doc = getDocument(handle) orelse return ERR_HANDLE;
    const path = constSlice(path_ptr, path_len) orelse return ERR_INVALID;
    const value = constSlice(value_ptr, value_len) orelse return ERR_INVALID;
    const copy = doc.alloc().dupe(u8, value) catch return ERR_NOMEM;
    return pushValueAt(doc, path, stringValue(copy));
}

pub export fn sa_yaml_array_push_i64(handle: u64, path_ptr: ?[*]const u8, path_len: u64, value: i64) i32 {
    const doc = getDocument(handle) orelse return ERR_HANDLE;
    const path = constSlice(path_ptr, path_len) orelse return ERR_INVALID;
    return pushValueAt(doc, path, .{ .kind = KIND_INTEGER, .int = value });
}

pub export fn sa_yaml_array_push_f64(handle: u64, path_ptr: ?[*]const u8, path_len: u64, value: f64) i32 {
    const doc = getDocument(handle) orelse return ERR_HANDLE;
    const path = constSlice(path_ptr, path_len) orelse return ERR_INVALID;
    return pushValueAt(doc, path, .{ .kind = KIND_FLOAT, .float = value });
}

pub export fn sa_yaml_array_push_bool(handle: u64, path_ptr: ?[*]const u8, path_len: u64, value: u32) i32 {
    const doc = getDocument(handle) orelse return ERR_HANDLE;
    const path = constSlice(path_ptr, path_len) orelse return ERR_INVALID;
    return pushValueAt(doc, path, .{ .kind = KIND_BOOL, .boolean = value != 0 });
}

pub export fn sa_yaml_array_push_null(handle: u64, path_ptr: ?[*]const u8, path_len: u64) i32 {
    const doc = getDocument(handle) orelse return ERR_HANDLE;
    const path = constSlice(path_ptr, path_len) orelse return ERR_INVALID;
    return pushValueAt(doc, path, null_value);
}

pub export fn sa_yaml_array_push_table(handle: u64, path_ptr: ?[*]const u8, path_len: u64) i32 {
    const doc = getDocument(handle) orelse return ERR_HANDLE;
    const path = constSlice(path_ptr, path_len) orelse return ERR_INVALID;
    const value = newTableValue(doc) catch return ERR_NOMEM;
    return pushValueAt(doc, path, value);
}

pub export fn sa_yaml_stringify(handle: u64, out_ptr: ?*?[*]const u8, out_len: ?*u64) i32 {
    const ptr_slot = out_ptr orelse return ERR_INVALID;
    const len_slot = out_len orelse return ERR_INVALID;
    ptr_slot.* = null;
    len_slot.* = 0;
    const doc = getDocument(handle) orelse return ERR_HANDLE;
    const text = emitYamlDocument(doc) catch return ERR_NOMEM;
    doc.yaml_buf = text;
    ptr_slot.* = text.ptr;
    len_slot.* = @intCast(text.len);
    return OK;
}

pub export fn sa_yaml_to_json(handle: u64, out_ptr: ?*?[*]const u8, out_len: ?*u64) i32 {
    const ptr_slot = out_ptr orelse return ERR_INVALID;
    const len_slot = out_len orelse return ERR_INVALID;
    ptr_slot.* = null;
    len_slot.* = 0;
    const doc = getDocument(handle) orelse return ERR_HANDLE;
    const text = emitJsonDocument(doc) catch |err| switch (err) {
        error.OutOfMemory => return ERR_NOMEM,
        error.NonFinite => {
            setLastError("yaml: non-finite number cannot be represented in JSON", .{});
            return ERR_INVALID;
        },
    };
    doc.json_buf = text;
    ptr_slot.* = text.ptr;
    len_slot.* = @intCast(text.len);
    return OK;
}

// ---------------- emitters ----------------

const EmitError = error{ OutOfMemory, NonFinite };

fn appendFmt(out: *std.array_list.Managed(u8), comptime fmt: []const u8, args: anytype) !void {
    const s = try std.fmt.allocPrint(std.heap.page_allocator, fmt, args);
    defer std.heap.page_allocator.free(s);
    try out.appendSlice(s);
}

fn writeFloatInto(out: *std.array_list.Managed(u8), v: f64) error{OutOfMemory}!void {
    if (std.math.isNan(v)) {
        try out.appendSlice(".nan");
        return;
    }
    if (std.math.isInf(v)) {
        try out.appendSlice(if (v > 0) ".inf" else "-.inf");
        return;
    }
    const s = try std.fmt.allocPrint(std.heap.page_allocator, "{d}", .{v});
    defer std.heap.page_allocator.free(s);
    try out.appendSlice(s);
    // Keep the value a float on reparse: bare "1" would read back as
    // an integer.
    if (std.mem.indexOfAny(u8, s, ".eE") == null) try out.appendSlice(".0");
}

fn plainSafe(s: []const u8, is_key: bool) bool {
    if (s.len == 0) return false;
    if (isNullSpelling(s)) return false;
    if (std.mem.eql(u8, s, "true") or std.mem.eql(u8, s, "True") or std.mem.eql(u8, s, "TRUE") or
        std.mem.eql(u8, s, "false") or std.mem.eql(u8, s, "False") or std.mem.eql(u8, s, "FALSE")) return false;
    if (intSyntax(s) != null) return false;
    if (parseYamlFloat(s) != null) return false;
    if (is_key and std.mem.eql(u8, s, "<<")) return false;
    const c0 = s[0];
    if (isIndicatorStart(c0) or c0 == '\'' or c0 == '"') return false;
    if ((c0 == '-' or c0 == '?') and (s.len == 1 or s[1] == ' ')) return false;
    if (c0 == ':') return false;
    if (s[0] == ' ' or s[s.len - 1] == ' ' or s[s.len - 1] == ':') return false;
    for (s) |c| {
        if (c < 0x20 or c == 0x7f or c == '\t') return false;
    }
    if (std.mem.indexOf(u8, s, ": ") != null) return false;
    if (std.mem.indexOf(u8, s, " #") != null) return false;
    if (is_key and std.mem.indexOfScalar(u8, s, ':') != null) return false;
    return true;
}

fn appendYamlString(out: *std.array_list.Managed(u8), s: []const u8, is_key: bool) error{OutOfMemory}!void {
    if (plainSafe(s, is_key)) {
        try out.appendSlice(s);
        return;
    }
    try out.append('"');
    for (s) |c| {
        switch (c) {
            '"' => try out.appendSlice("\\\""),
            '\\' => try out.appendSlice("\\\\"),
            '\n' => try out.appendSlice("\\n"),
            '\r' => try out.appendSlice("\\r"),
            '\t' => try out.appendSlice("\\t"),
            0 => try out.appendSlice("\\0"),
            else => {
                if (c < 0x20 or c == 0x7f) {
                    try appendFmt(out, "\\x{X:0>2}", .{c});
                } else {
                    try out.append(c);
                }
            },
        }
    }
    try out.append('"');
}

fn appendYamlScalar(out: *std.array_list.Managed(u8), v: *const Value) error{OutOfMemory}!void {
    switch (v.kind) {
        KIND_NULL => try out.appendSlice("null"),
        KIND_BOOL => try out.appendSlice(if (v.boolean) "true" else "false"),
        KIND_INTEGER => try appendFmt(out, "{d}", .{v.int}),
        KIND_FLOAT => try writeFloatInto(out, v.float),
        KIND_STRING => try appendYamlString(out, v.str, false),
        KIND_ARRAY => try out.appendSlice("[]"),
        KIND_TABLE => try out.appendSlice("{}"),
        else => try out.appendSlice("null"),
    }
}

fn appendIndent(out: *std.array_list.Managed(u8), indent: usize) error{OutOfMemory}!void {
    for (0..indent) |_| try out.append(' ');
}

fn emitYamlMapping(out: *std.array_list.Managed(u8), table: *const Table, indent: usize) error{OutOfMemory}!void {
    for (table.entries.items) |e| {
        try appendIndent(out, indent);
        try appendYamlString(out, e.key, true);
        try out.append(':');
        const val = &e.value;
        switch (val.kind) {
            KIND_TABLE => {
                if (val.table.?.entries.items.len == 0) {
                    try out.appendSlice(" {}\n");
                } else {
                    try out.append('\n');
                    try emitYamlMapping(out, val.table.?, indent + 2);
                }
            },
            KIND_ARRAY => {
                if (val.array.len == 0) {
                    try out.appendSlice(" []\n");
                } else {
                    try out.append('\n');
                    try emitYamlSequence(out, val.array, indent + 2);
                }
            },
            else => {
                try out.append(' ');
                try appendYamlScalar(out, val);
                try out.append('\n');
            },
        }
    }
}

fn emitYamlSequence(out: *std.array_list.Managed(u8), arr: []const Value, indent: usize) error{OutOfMemory}!void {
    for (arr) |*item| {
        try appendIndent(out, indent);
        switch (item.kind) {
            KIND_TABLE => {
                if (item.table.?.entries.items.len == 0) {
                    try out.appendSlice("- {}\n");
                } else {
                    try out.appendSlice("-\n");
                    try emitYamlMapping(out, item.table.?, indent + 2);
                }
            },
            KIND_ARRAY => {
                if (item.array.len == 0) {
                    try out.appendSlice("- []\n");
                } else {
                    try out.appendSlice("-\n");
                    try emitYamlSequence(out, item.array, indent + 2);
                }
            },
            else => {
                try out.appendSlice("- ");
                try appendYamlScalar(out, item);
                try out.append('\n');
            },
        }
    }
}

fn emitYamlDocument(doc: *Document) error{OutOfMemory}![]u8 {
    if (doc.yaml_buf) |buf| {
        std.heap.page_allocator.free(buf);
        doc.yaml_buf = null;
    }
    var out = std.array_list.Managed(u8).init(std.heap.page_allocator);
    errdefer out.deinit();
    const root = &doc.root;
    switch (root.kind) {
        KIND_TABLE => {
            if (root.table.?.entries.items.len == 0) {
                try out.appendSlice("{}\n");
            } else {
                try emitYamlMapping(&out, root.table.?, 0);
            }
        },
        KIND_ARRAY => {
            if (root.array.len == 0) {
                try out.appendSlice("[]\n");
            } else {
                try emitYamlSequence(&out, root.array, 0);
            }
        },
        else => {
            try appendYamlScalar(&out, root);
            try out.append('\n');
        },
    }
    return out.toOwnedSlice();
}

fn appendJsonString(out: *std.array_list.Managed(u8), s: []const u8) error{OutOfMemory}!void {
    try out.append('"');
    for (s) |c| {
        switch (c) {
            '"' => try out.appendSlice("\\\""),
            '\\' => try out.appendSlice("\\\\"),
            '\n' => try out.appendSlice("\\n"),
            '\r' => try out.appendSlice("\\r"),
            '\t' => try out.appendSlice("\\t"),
            0x08 => try out.appendSlice("\\b"),
            0x0C => try out.appendSlice("\\f"),
            else => {
                if (c < 0x20) {
                    try appendFmt(out, "\\u{X:0>4}", .{c});
                } else {
                    try out.append(c);
                }
            },
        }
    }
    try out.append('"');
}

fn emitJsonValue(out: *std.array_list.Managed(u8), v: *const Value) EmitError!void {
    switch (v.kind) {
        KIND_NULL => try out.appendSlice("null"),
        KIND_BOOL => try out.appendSlice(if (v.boolean) "true" else "false"),
        KIND_INTEGER => try appendFmt(out, "{d}", .{v.int}),
        KIND_FLOAT => {
            if (!std.math.isFinite(v.float)) return error.NonFinite;
            try writeFloatInto(out, v.float);
        },
        KIND_STRING => try appendJsonString(out, v.str),
        KIND_ARRAY => {
            try out.append('[');
            for (v.array, 0..) |*item, i| {
                if (i > 0) try out.append(',');
                try emitJsonValue(out, item);
            }
            try out.append(']');
        },
        KIND_TABLE => {
            try out.append('{');
            for (v.table.?.entries.items, 0..) |e, i| {
                if (i > 0) try out.append(',');
                try appendJsonString(out, e.key);
                try out.append(':');
                try emitJsonValue(out, &e.value);
            }
            try out.append('}');
        },
        else => return error.NonFinite,
    }
}

fn emitJsonDocument(doc: *Document) EmitError![]u8 {
    if (doc.json_buf) |buf| {
        std.heap.page_allocator.free(buf);
        doc.json_buf = null;
    }
    var out = std.array_list.Managed(u8).init(std.heap.page_allocator);
    errdefer out.deinit();
    try emitJsonValue(&out, &doc.root);
    return out.toOwnedSlice();
}

// ---------------- tests ----------------

fn expectParse(text: []const u8) !u64 {
    const h = sa_yaml_parse(text.ptr, text.len);
    if (h == 0) {
        std.debug.print("unexpected yaml parse failure: {s}\n", .{lastErrorText()});
        return error.TestUnexpectedResult;
    }
    return h;
}

fn lastErrorText() []const u8 {
    var p: ?[*]const u8 = null;
    var l: u64 = 0;
    _ = sa_yaml_last_error(&p, &l);
    if (p) |ptr| return ptr[0..@intCast(l)];
    return "";
}

fn getString(h: u64, path: []const u8) ![]const u8 {
    var p: ?[*]const u8 = null;
    var l: u64 = 0;
    try std.testing.expectEqual(OK, sa_yaml_get_string(h, path.ptr, path.len, &p, &l));
    return p.?[0..@intCast(l)];
}

fn getI64(h: u64, path: []const u8) !i64 {
    var v: i64 = 0;
    try std.testing.expectEqual(OK, sa_yaml_get_i64(h, path.ptr, path.len, &v));
    return v;
}

fn getF64(h: u64, path: []const u8) !f64 {
    var v: f64 = 0;
    try std.testing.expectEqual(OK, sa_yaml_get_f64(h, path.ptr, path.len, &v));
    return v;
}

fn getBool(h: u64, path: []const u8) !bool {
    var v: u32 = 0;
    try std.testing.expectEqual(OK, sa_yaml_get_bool(h, path.ptr, path.len, &v));
    return v != 0;
}

fn kindOf(h: u64, path: []const u8) !u32 {
    var k: u32 = 99;
    try std.testing.expectEqual(OK, sa_yaml_kind(h, path.ptr, path.len, &k));
    return k;
}

test "yaml: config values by dotted path" {
    const h = try expectParse(
        \\# gateway config
        \\server:
        \\  host: 0.0.0.0
        \\  port: 8080
        \\  debug: false
        \\database:
        \\  url: postgres://localhost:5432/sub2api
        \\  pool:
        \\    max_open: 25
        \\    ratio: 0.75
        \\name: sub2api
    );
    defer _ = sa_yaml_free(h);
    try std.testing.expectEqualStrings("sub2api", try getString(h, "name"));
    try std.testing.expectEqualStrings("0.0.0.0", try getString(h, "server.host"));
    try std.testing.expectEqual(@as(i64, 8080), try getI64(h, "server.port"));
    try std.testing.expectEqual(false, try getBool(h, "server.debug"));
    try std.testing.expectEqual(@as(i64, 25), try getI64(h, "database.pool.max_open"));
    try std.testing.expectEqual(@as(f64, 0.75), try getF64(h, "database.pool.ratio"));
    try std.testing.expectEqual(KIND_TABLE, try kindOf(h, "database.pool"));
    try std.testing.expectEqual(KIND_STRING, try kindOf(h, "database.url"));
    // Missing path -> NOT_FOUND; wrong kind -> INVALID.
    var v: i64 = 0;
    try std.testing.expectEqual(ERR_NOT_FOUND, sa_yaml_get_i64(h, "server.nope", 11, &v));
    try std.testing.expectEqual(ERR_INVALID, sa_yaml_get_i64(h, "name", 4, &v));
    // Root kind via the empty path.
    try std.testing.expectEqual(KIND_TABLE, try kindOf(h, ""));
    var n: u64 = 0;
    try std.testing.expectEqual(OK, sa_yaml_table_len(h, "", 0, &n));
    try std.testing.expectEqual(@as(u64, 3), n);
}

test "yaml: handle discipline" {
    try std.testing.expectEqual(ERR_HANDLE, sa_yaml_free(424242));
    const h = try expectParse("a: 1");
    try std.testing.expectEqual(OK, sa_yaml_free(h));
    var k: u32 = 0;
    try std.testing.expectEqual(ERR_HANDLE, sa_yaml_kind(h, "a", 1, &k));
    try std.testing.expectEqual(KIND_UNDEFINED, k);
}

test "yaml: block sequences and compact mappings" {
    const h = try expectParse(
        \\tags:
        \\  - alpha
        \\  - beta
        \\servers:
        \\  - host: a.example.com
        \\    port: 80
        \\  - host: b.example.com
        \\    port: 443
        \\matrix:
        \\  - - 1
        \\    - 2
        \\  - - 3
        \\flat:
        \\- x
        \\- y
    );
    defer _ = sa_yaml_free(h);
    var n: u64 = 0;
    try std.testing.expectEqual(OK, sa_yaml_array_len(h, "tags", 4, &n));
    try std.testing.expectEqual(@as(u64, 2), n);
    try std.testing.expectEqualStrings("alpha", try getString(h, "tags.0"));
    try std.testing.expectEqualStrings("a.example.com", try getString(h, "servers.0.host"));
    try std.testing.expectEqual(@as(i64, 443), try getI64(h, "servers.1.port"));
    try std.testing.expectEqual(@as(i64, 2), try getI64(h, "matrix.0.1"));
    try std.testing.expectEqual(@as(i64, 3), try getI64(h, "matrix.1.0"));
    // Sequence at the same indent as its key.
    try std.testing.expectEqualStrings("y", try getString(h, "flat.1"));
    // array_get_* forms.
    var p: ?[*]const u8 = null;
    var l: u64 = 0;
    try std.testing.expectEqual(OK, sa_yaml_array_get_string(h, "tags", 4, 1, &p, &l));
    try std.testing.expectEqualStrings("beta", p.?[0..@intCast(l)]);
    var iv: i64 = 0;
    try std.testing.expectEqual(OK, sa_yaml_array_get_i64(h, "matrix.0", 8, 0, &iv));
    try std.testing.expectEqual(@as(i64, 1), iv);
    try std.testing.expectEqual(ERR_NOT_FOUND, sa_yaml_array_get_i64(h, "matrix.0", 8, 9, &iv));
}

test "yaml: flow collections" {
    const h = try expectParse(
        \\point: {x: 1, y: 2}
        \\names: [alpha, beta, "quoted, with comma"]
        \\nested: {a: [1, {b: 2}], c: {}}
        \\empty_list: []
        \\bare: {flag, other: 1}
        \\pairs: [k: v, 7]
        \\multi: [
        \\  1,
        \\  2,
        \\]
    );
    defer _ = sa_yaml_free(h);
    try std.testing.expectEqual(@as(i64, 1), try getI64(h, "point.x"));
    try std.testing.expectEqualStrings("quoted, with comma", try getString(h, "names.2"));
    try std.testing.expectEqual(@as(i64, 2), try getI64(h, "nested.a.1.b"));
    try std.testing.expectEqual(KIND_TABLE, try kindOf(h, "nested.c"));
    var n: u64 = 0;
    try std.testing.expectEqual(OK, sa_yaml_array_len(h, "empty_list", 10, &n));
    try std.testing.expectEqual(@as(u64, 0), n);
    try std.testing.expectEqual(KIND_NULL, try kindOf(h, "bare.flag"));
    try std.testing.expectEqualStrings("v", try getString(h, "pairs.0.k"));
    try std.testing.expectEqual(@as(i64, 7), try getI64(h, "pairs.1"));
    try std.testing.expectEqual(@as(i64, 2), try getI64(h, "multi.1"));
}

test "yaml: scalar styles" {
    const h = try expectParse(
        \\sq: 'it''s fine'
        \\dq: "tab\tnewline\nquote\""
        \\uni: "Aé"
        \\lit: |
        \\  line one
        \\  line two
        \\lit_strip: |-
        \\  no trailing
        \\lit_keep: |+
        \\  kept
        \\
        \\
        \\fold: >
        \\  some words
        \\  wrapped here
        \\
        \\  new paragraph
        \\plain_multi: this is
        \\  one scalar
        \\indented: |2
        \\   three spaces
    );
    defer _ = sa_yaml_free(h);
    try std.testing.expectEqualStrings("it's fine", try getString(h, "sq"));
    try std.testing.expectEqualStrings("tab\tnewline\nquote\"", try getString(h, "dq"));
    try std.testing.expectEqualStrings("Aé", try getString(h, "uni"));
    try std.testing.expectEqualStrings("line one\nline two\n", try getString(h, "lit"));
    try std.testing.expectEqualStrings("no trailing", try getString(h, "lit_strip"));
    try std.testing.expectEqualStrings("kept\n\n\n", try getString(h, "lit_keep"));
    try std.testing.expectEqualStrings("some words wrapped here\nnew paragraph\n", try getString(h, "fold"));
    try std.testing.expectEqualStrings("this is one scalar", try getString(h, "plain_multi"));
    try std.testing.expectEqualStrings(" three spaces\n", try getString(h, "indented"));
}

test "yaml: type inference" {
    const h = try expectParse(
        \\n1: ~
        \\n2: null
        \\n3:
        \\b1: true
        \\b2: FALSE
        \\s1: yes
        \\s2: on
        \\s3: Off
        \\i1: 42
        \\i2: -17
        \\i3: +12
        \\i4: 1_000
        \\i5: 0x1F
        \\i6: 0o17
        \\i7: 017
        \\i8: 0b101
        \\i9: 08
        \\f1: 1.5
        \\f2: .5
        \\f3: 5.
        \\f4: 1e3
        \\f5: -2.5e-2
        \\f6: .inf
        \\f7: -.inf
        \\s4: 2026-10-28
        \\s5: 1:30
        \\s6: 1.2.3
        \\s7: '42'
        \\big: 99999999999999999999999
    );
    defer _ = sa_yaml_free(h);
    try std.testing.expectEqual(KIND_NULL, try kindOf(h, "n1"));
    try std.testing.expectEqual(KIND_NULL, try kindOf(h, "n2"));
    try std.testing.expectEqual(KIND_NULL, try kindOf(h, "n3"));
    try std.testing.expectEqual(true, try getBool(h, "b1"));
    try std.testing.expectEqual(false, try getBool(h, "b2"));
    // YAML 1.1 booleans stay strings under the JSON-aligned rules.
    try std.testing.expectEqualStrings("yes", try getString(h, "s1"));
    try std.testing.expectEqualStrings("on", try getString(h, "s2"));
    try std.testing.expectEqualStrings("Off", try getString(h, "s3"));
    try std.testing.expectEqual(@as(i64, 42), try getI64(h, "i1"));
    try std.testing.expectEqual(@as(i64, -17), try getI64(h, "i2"));
    try std.testing.expectEqual(@as(i64, 12), try getI64(h, "i3"));
    try std.testing.expectEqual(@as(i64, 1000), try getI64(h, "i4"));
    try std.testing.expectEqual(@as(i64, 31), try getI64(h, "i5"));
    try std.testing.expectEqual(@as(i64, 15), try getI64(h, "i6"));
    try std.testing.expectEqual(@as(i64, 15), try getI64(h, "i7"));
    try std.testing.expectEqual(@as(i64, 5), try getI64(h, "i8"));
    try std.testing.expectEqual(@as(i64, 8), try getI64(h, "i9"));
    try std.testing.expectEqual(@as(f64, 1.5), try getF64(h, "f1"));
    try std.testing.expectEqual(@as(f64, 0.5), try getF64(h, "f2"));
    try std.testing.expectEqual(@as(f64, 5.0), try getF64(h, "f3"));
    try std.testing.expectEqual(@as(f64, 1000.0), try getF64(h, "f4"));
    try std.testing.expectEqual(@as(f64, -0.025), try getF64(h, "f5"));
    try std.testing.expect(std.math.isInf(try getF64(h, "f6")));
    try std.testing.expect(std.math.isInf(try getF64(h, "f7")));
    // Timestamps and sexagesimal numbers stay strings.
    try std.testing.expectEqualStrings("2026-10-28", try getString(h, "s4"));
    try std.testing.expectEqualStrings("1:30", try getString(h, "s5"));
    try std.testing.expectEqualStrings("1.2.3", try getString(h, "s6"));
    try std.testing.expectEqualStrings("42", try getString(h, "s7"));
    // i64 overflow becomes a float.
    try std.testing.expectEqual(KIND_FLOAT, try kindOf(h, "big"));
}

test "yaml: anchors aliases and merge keys" {
    const h = try expectParse(
        \\defaults: &def
        \\  retries: 3
        \\  timeout: 30
        \\prod:
        \\  <<: *def
        \\  timeout: 60
        \\copy: *def
        \\scalar_anchor: &greeting hello
        \\use: *greeting
    );
    defer _ = sa_yaml_free(h);
    try std.testing.expectEqual(@as(i64, 3), try getI64(h, "prod.retries"));
    try std.testing.expectEqual(@as(i64, 60), try getI64(h, "prod.timeout"));
    try std.testing.expectEqual(@as(i64, 30), try getI64(h, "copy.timeout"));
    try std.testing.expectEqualStrings("hello", try getString(h, "use"));
    // The alias is a deep copy: mutating the source leaves it alone.
    try std.testing.expectEqual(OK, sa_yaml_set_i64(h, "defaults.timeout", 16, 99));
    try std.testing.expectEqual(@as(i64, 99), try getI64(h, "defaults.timeout"));
    try std.testing.expectEqual(@as(i64, 30), try getI64(h, "copy.timeout"));
    try std.testing.expectEqual(@as(i64, 60), try getI64(h, "prod.timeout"));
}

test "yaml: merge key sequence order" {
    const h = try expectParse(
        \\a: &a {x: 1, shared: from-a}
        \\b: &b {y: 2, shared: from-b}
        \\c:
        \\  <<: [*a, *b]
        \\  z: 3
    );
    defer _ = sa_yaml_free(h);
    try std.testing.expectEqualStrings("from-a", try getString(h, "c.shared"));
    try std.testing.expectEqual(@as(i64, 2), try getI64(h, "c.y"));
    try std.testing.expectEqual(@as(i64, 3), try getI64(h, "c.z"));
}

test "yaml: multi-document streams" {
    const text =
        \\%YAML 1.2
        \\---
        \\a: 1
        \\---
        \\b: 2
        \\...
    ;
    var count: u64 = 0;
    try std.testing.expectEqual(OK, sa_yaml_count_documents(text.ptr, text.len, &count));
    try std.testing.expectEqual(@as(u64, 2), count);
    const h0 = sa_yaml_parse_at(text.ptr, text.len, 0);
    defer _ = sa_yaml_free(h0);
    try std.testing.expect(h0 != 0);
    try std.testing.expectEqual(@as(i64, 1), try getI64(h0, "a"));
    const h1 = sa_yaml_parse_at(text.ptr, text.len, 1);
    defer _ = sa_yaml_free(h1);
    try std.testing.expect(h1 != 0);
    try std.testing.expectEqual(@as(i64, 2), try getI64(h1, "b"));
    // Out of range index fails loudly.
    try std.testing.expectEqual(@as(u64, 0), sa_yaml_parse_at(text.ptr, text.len, 2));
    try std.testing.expect(std.mem.indexOf(u8, lastErrorText(), "out of range") != null);
    // sa_yaml_parse reads document 0.
    const hd = try expectParse(text);
    defer _ = sa_yaml_free(hd);
    try std.testing.expectEqual(@as(i64, 1), try getI64(hd, "a"));
    // Empty input: zero documents, but parse yields a null document.
    try std.testing.expectEqual(OK, sa_yaml_count_documents("", 0, &count));
    try std.testing.expectEqual(@as(u64, 0), count);
    const he = try expectParse("");
    defer _ = sa_yaml_free(he);
    try std.testing.expectEqual(KIND_NULL, try kindOf(he, ""));
}

test "yaml: errors carry positions" {
    const cases = [_]struct { text: []const u8, needle: []const u8 }{
        .{ .text = "a: 1\na: 2\n", .needle = "duplicate key" },
        .{ .text = "a:\n\tb: 1\n", .needle = "tab character" },
        .{ .text = "a: 'unterminated\n", .needle = "unterminated quoted scalar" },
        .{ .text = "a: !!str 5\n", .needle = "unsupported" },
        .{ .text = "%TAG ! tag:example.com,2026:\na: 1\n", .needle = "unsupported" },
        .{ .text = "a: [1, 2\n", .needle = "unterminated flow" },
        .{ .text = "a: *missing\n", .needle = "unknown alias" },
        .{ .text = "a: 1\n  b: 2\n", .needle = "line 2" },
    };
    for (cases) |case| {
        const h = sa_yaml_parse(case.text.ptr, case.text.len);
        try std.testing.expectEqual(@as(u64, 0), h);
        const msg = lastErrorText();
        if (std.mem.indexOf(u8, msg, case.needle) == null) {
            std.debug.print("error case needle '{s}' not in '{s}'\n", .{ case.needle, msg });
            return error.TestUnexpectedResult;
        }
        try std.testing.expect(std.mem.indexOf(u8, msg, "line ") != null);
    }
    // The duplicate key error names the duplicate's own line.
    const dup = "one: 1\ntwo: 2\none: 3\n";
    try std.testing.expectEqual(@as(u64, 0), sa_yaml_parse(dup.ptr, dup.len));
    try std.testing.expect(std.mem.indexOf(u8, lastErrorText(), "line 3") != null);
}

test "yaml: build and stringify round trip" {
    const h = sa_yaml_new();
    try std.testing.expect(h != 0);
    defer _ = sa_yaml_free(h);
    try std.testing.expectEqual(OK, sa_yaml_set_string(h, "server.host", 11, "127.0.0.1", 9));
    try std.testing.expectEqual(OK, sa_yaml_set_i64(h, "server.port", 11, 9000));
    try std.testing.expectEqual(OK, sa_yaml_set_bool(h, "server.tls", 10, 1));
    try std.testing.expectEqual(OK, sa_yaml_set_null(h, "server.note", 11));
    try std.testing.expectEqual(OK, sa_yaml_array_push_string(h, "tags", 4, "one", 3));
    try std.testing.expectEqual(OK, sa_yaml_array_push_i64(h, "tags", 4, 2));
    try std.testing.expectEqual(OK, sa_yaml_array_push_table(h, "items", 5));
    try std.testing.expectEqual(OK, sa_yaml_set_string(h, "items.0.name", 12, "first", 5));
    var p: ?[*]const u8 = null;
    var l: u64 = 0;
    try std.testing.expectEqual(OK, sa_yaml_stringify(h, &p, &l));
    const text = p.?[0..@intCast(l)];
    const h2 = try expectParse(text);
    defer _ = sa_yaml_free(h2);
    try std.testing.expectEqualStrings("127.0.0.1", try getString(h2, "server.host"));
    try std.testing.expectEqual(@as(i64, 9000), try getI64(h2, "server.port"));
    try std.testing.expectEqual(true, try getBool(h2, "server.tls"));
    try std.testing.expectEqual(KIND_NULL, try kindOf(h2, "server.note"));
    try std.testing.expectEqualStrings("one", try getString(h2, "tags.0"));
    try std.testing.expectEqual(@as(i64, 2), try getI64(h2, "tags.1"));
    try std.testing.expectEqualStrings("first", try getString(h2, "items.0.name"));
    // Removal: a table key and an array element.
    try std.testing.expectEqual(OK, sa_yaml_remove(h, "server.tls", 10));
    var kk: u32 = 0;
    try std.testing.expectEqual(ERR_NOT_FOUND, sa_yaml_kind(h, "server.tls", 10, &kk));
    try std.testing.expectEqual(OK, sa_yaml_remove(h, "tags.0", 6));
    try std.testing.expectEqual(@as(i64, 2), try getI64(h, "tags.0"));
    // Pushing onto a scalar path is an explicit error.
    try std.testing.expectEqual(ERR_INVALID, sa_yaml_array_push_i64(h, "server.port", 11, 1));
}

test "yaml: stringify stability and to_json" {
    const text =
        \\server:
        \\  port: 8080
        \\  ratio: 1.5
        \\  host: example.com
        \\  secure: true
        \\  note: null
        \\  tags:
        \\    - a
        \\    - b
    ;
    const h = try expectParse(text);
    defer _ = sa_yaml_free(h);
    var p: ?[*]const u8 = null;
    var l: u64 = 0;
    try std.testing.expectEqual(OK, sa_yaml_to_json(h, &p, &l));
    try std.testing.expectEqualStrings(
        "{\"server\":{\"port\":8080,\"ratio\":1.5,\"host\":\"example.com\",\"secure\":true,\"note\":null,\"tags\":[\"a\",\"b\"]}}",
        p.?[0..@intCast(l)],
    );
    try std.testing.expectEqual(OK, sa_yaml_stringify(h, &p, &l));
    const once = try std.testing.allocator.dupe(u8, p.?[0..@intCast(l)]);
    defer std.testing.allocator.free(once);
    const h2 = try expectParse(once);
    defer _ = sa_yaml_free(h2);
    try std.testing.expectEqual(OK, sa_yaml_stringify(h2, &p, &l));
    try std.testing.expectEqualStrings(once, p.?[0..@intCast(l)]);
}

test "yaml: scalar and empty roots" {
    const hs = try expectParse("just a string");
    defer _ = sa_yaml_free(hs);
    try std.testing.expectEqual(KIND_STRING, try kindOf(hs, ""));
    const hi = try expectParse("42");
    defer _ = sa_yaml_free(hi);
    try std.testing.expectEqual(@as(i64, 42), try getI64(hi, ""));
    const ha = try expectParse("- 1\n- 2\n");
    defer _ = sa_yaml_free(ha);
    try std.testing.expectEqual(@as(i64, 2), try getI64(ha, "1"));
    const hn = try expectParse("---\n");
    defer _ = sa_yaml_free(hn);
    try std.testing.expectEqual(KIND_NULL, try kindOf(hn, ""));
}

test "yaml: gateway-shaped config corpus" {
    const h = try expectParse(
        \\# sub2api-shaped gateway configuration (structure-equivalent,
        \\# secrets replaced)
        \\server:
        \\  host: "0.0.0.0"
        \\  port: 8080
        \\  mode: release
        \\database:
        \\  driver: postgres
        \\  dsn: postgres://user:pass@db.internal:5432/sub2api?sslmode=require
        \\  max_open_conns: 50
        \\redis:
        \\  addr: redis.internal:6379
        \\  db: 0
        \\  pool_size: 100
        \\jwt:
        \\  secret: "replace-me"
        \\  expire_hours: 24
        \\defaults: &defaults
        \\  rate_multiplier: 1.0
        \\  enabled: true
        \\groups:
        \\  - name: default
        \\    <<: *defaults
        \\  - name: vip
        \\    <<: *defaults
        \\    rate_multiplier: 0.8
        \\notes: |
        \\  first line
        \\  second line
    );
    defer _ = sa_yaml_free(h);
    try std.testing.expectEqualStrings("postgres", try getString(h, "database.driver"));
    try std.testing.expectEqualStrings("postgres://user:pass@db.internal:5432/sub2api?sslmode=require", try getString(h, "database.dsn"));
    try std.testing.expectEqual(@as(i64, 50), try getI64(h, "database.max_open_conns"));
    try std.testing.expectEqual(@as(i64, 100), try getI64(h, "redis.pool_size"));
    try std.testing.expectEqual(@as(i64, 24), try getI64(h, "jwt.expire_hours"));
    try std.testing.expectEqual(@as(f64, 1.0), try getF64(h, "groups.0.rate_multiplier"));
    try std.testing.expectEqual(true, try getBool(h, "groups.0.enabled"));
    try std.testing.expectEqual(@as(f64, 0.8), try getF64(h, "groups.1.rate_multiplier"));
    try std.testing.expectEqualStrings("first line\nsecond line\n", try getString(h, "notes"));
    // The whole document survives a YAML -> JSON view conversion.
    var p: ?[*]const u8 = null;
    var l: u64 = 0;
    try std.testing.expectEqual(OK, sa_yaml_to_json(h, &p, &l));
    try std.testing.expect(std.mem.indexOf(u8, p.?[0..@intCast(l)], "\"driver\":\"postgres\"") != null);
}
