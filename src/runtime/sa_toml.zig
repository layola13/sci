//! sa_std TOML: parser + dotted-path accessors + builder/serializer
//! (P0-6 / D4).
//!
//! TOML v1.0 document model mirroring the JSON surface shape: parse the
//! whole text into a handle, then read values by dotted path
//! ("mcp_servers.jex.command"). Datetimes are preserved as raw text with
//! their own kind so nothing is silently coerced. Duplicate keys and
//! table redefinitions are hard parse errors (CXU's config.toml health
//! check depends on duplicates being visible, never last-wins).
//! Status codes mirror sa_std.zig (0 ok, 1 invalid argument, 2 invalid
//! handle, 3 not found, 5 no memory).
//!
//! The write side (sa_toml_new / set_* / array_push_* / remove /
//! stringify) mutates the handle's tree in place: set_* replaces
//! whatever sits at the path, intermediate tables are created on
//! demand, and mutation walks descend into inline tables (the
//! inline-table restriction is a parse-time text rule, not a builder
//! rule). sa_toml_stringify emits TOML text that this parser reads
//! back; its buffer is document-owned and invalidated by the next
//! mutation or stringify of the same document.

const std = @import("std");
const sio = @import("sio");

const OK: i32 = 0;
const ERR_INVALID: i32 = 1;
const ERR_HANDLE: i32 = 2;
const ERR_NOT_FOUND: i32 = 3;
const ERR_NOMEM: i32 = 5;

pub const KIND_STRING: u32 = 1;
pub const KIND_INTEGER: u32 = 2;
pub const KIND_FLOAT: u32 = 3;
pub const KIND_BOOL: u32 = 4;
pub const KIND_DATETIME: u32 = 5;
pub const KIND_ARRAY: u32 = 6;
pub const KIND_TABLE: u32 = 7;

const CreatedAs = enum { implicit, dotted, header, inline_table };

const Table = struct {
    entries: std.array_list.Managed(Entry),
    created_as: CreatedAs = .implicit,
    header_defined: bool = false,
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
    array_of_tables: bool = false,
    table: ?*Table = null,
};

const Document = struct {
    allocator: std.mem.Allocator,
    root: *Table,
    ser_buf: ?[]u8 = null,

    fn deinit(self: *Document) void {
        if (self.ser_buf) |buf| self.allocator.free(buf);
        freeTable(self.allocator, self.root);
        self.allocator.destroy(self);
    }
};

fn freeTable(alloc: std.mem.Allocator, table: *Table) void {
    for (table.entries.items) |entry| {
        alloc.free(entry.key);
        freeValue(alloc, entry.value);
    }
    table.entries.deinit();
    alloc.destroy(table);
}

fn freeValue(alloc: std.mem.Allocator, value: Value) void {
    switch (value.kind) {
        KIND_STRING, KIND_DATETIME => alloc.free(value.str),
        KIND_ARRAY => {
            for (value.array) |item| freeValue(alloc, item);
            alloc.free(value.array);
        },
        KIND_TABLE => if (value.table) |t| freeTable(alloc, t),
        else => {},
    }
}

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

// ---------------- last parse error ----------------

var last_error_buf: [512]u8 = undefined;
var last_error_len: usize = 0;

fn setLastError(comptime fmt: []const u8, args: anytype) void {
    const msg = std.fmt.bufPrint(&last_error_buf, fmt, args) catch blk: {
        last_error_len = 0;
        break :blk "";
    };
    last_error_len = msg.len;
}

fn clearLastError() void {
    last_error_len = 0;
}

// ---------------- parser ----------------

const ParseError = error{ TomlSyntax, DuplicateKey, OutOfMemory };

const Parser = struct {
    alloc: std.mem.Allocator,
    src: []const u8,
    pos: usize = 0,

    fn lineCol(self: *const Parser) struct { line: usize, col: usize } {
        var line: usize = 1;
        var col: usize = 1;
        for (self.src[0..@min(self.pos, self.src.len)]) |c| {
            if (c == '\n') {
                line += 1;
                col = 1;
            } else {
                col += 1;
            }
        }
        return .{ .line = line, .col = col };
    }

    fn fail(self: *Parser, err: ParseError, msg: []const u8) ParseError {
        const lc = self.lineCol();
        if (err == error.DuplicateKey) {
            setLastError("toml: duplicate key ({s}) at line {d}, col {d}", .{ msg, lc.line, lc.col });
        } else {
            setLastError("toml: syntax error ({s}) at line {d}, col {d}", .{ msg, lc.line, lc.col });
        }
        return err;
    }

    fn peek(self: *const Parser) ?u8 {
        if (self.pos >= self.src.len) return null;
        return self.src[self.pos];
    }

    fn skipInlineWs(self: *Parser) void {
        while (self.pos < self.src.len and (self.src[self.pos] == ' ' or self.src[self.pos] == '\t')) self.pos += 1;
    }

    fn skipComment(self: *Parser) void {
        if (self.peek() == '#') {
            while (self.pos < self.src.len and self.src[self.pos] != '\n') self.pos += 1;
        }
    }

    // Between statements: whitespace, comments and newlines are all free.
    fn skipTrivia(self: *Parser) void {
        while (self.pos < self.src.len) {
            const c = self.src[self.pos];
            if (c == ' ' or c == '\t' or c == '\n' or c == '\r') {
                self.pos += 1;
            } else if (c == '#') {
                self.skipComment();
            } else break;
        }
    }

    // Inside arrays: newlines and comments are free too.
    fn skipArrayTrivia(self: *Parser) void {
        self.skipTrivia();
    }

    fn expectNewlineOrEof(self: *Parser) ParseError!void {
        self.skipInlineWs();
        self.skipComment();
        if (self.pos >= self.src.len) return;
        if (self.src[self.pos] == '\r') self.pos += 1;
        if (self.pos < self.src.len and self.src[self.pos] == '\n') {
            self.pos += 1;
            return;
        }
        return self.fail(error.TomlSyntax, "expected end of line");
    }

    fn parseKeySegment(self: *Parser) ParseError![]const u8 {
        self.skipInlineWs();
        const c = self.peek() orelse return self.fail(error.TomlSyntax, "expected key");
        if (c == '"') {
            self.pos += 1;
            var out = std.array_list.Managed(u8).init(self.alloc);
            errdefer out.deinit();
            while (true) {
                const ch = self.peek() orelse return self.fail(error.TomlSyntax, "unterminated quoted key");
                if (ch == '"') {
                    self.pos += 1;
                    break;
                }
                if (ch == '\\') {
                    self.pos += 1;
                    try self.parseEscapeInto(&out);
                    continue;
                }
                if (ch == '\n') return self.fail(error.TomlSyntax, "newline in quoted key");
                try out.append(ch);
                self.pos += 1;
            }
            return out.toOwnedSlice();
        }
        if (c == '\'') {
            self.pos += 1;
            const start = self.pos;
            while (self.pos < self.src.len and self.src[self.pos] != '\'') self.pos += 1;
            if (self.pos >= self.src.len) return self.fail(error.TomlSyntax, "unterminated literal key");
            const raw = self.src[start..self.pos];
            self.pos += 1;
            return self.alloc.dupe(u8, raw);
        }
        const start = self.pos;
        while (self.pos < self.src.len) {
            const ch = self.src[self.pos];
            if ((ch >= 'A' and ch <= 'Z') or (ch >= 'a' and ch <= 'z') or (ch >= '0' and ch <= '9') or ch == '_' or ch == '-') {
                self.pos += 1;
            } else break;
        }
        if (self.pos == start) return self.fail(error.TomlSyntax, "expected key");
        return self.alloc.dupe(u8, self.src[start..self.pos]);
    }

    fn parseDottedKey(self: *Parser) ParseError![][]const u8 {
        var segs = std.array_list.Managed([]const u8).init(self.alloc);
        errdefer {
            for (segs.items) |s| self.alloc.free(s);
            segs.deinit();
        }
        while (true) {
            const seg = try self.parseKeySegment();
            try segs.append(seg);
            self.skipInlineWs();
            if (self.peek() == '.') {
                self.pos += 1;
                continue;
            }
            break;
        }
        return segs.toOwnedSlice();
    }

    fn freeSegs(self: *Parser, segs: [][]const u8) void {
        for (segs) |s| self.alloc.free(s);
        self.alloc.free(segs);
    }

    fn parseEscapeInto(self: *Parser, out: *std.array_list.Managed(u8)) ParseError!void {
        const c = self.peek() orelse return self.fail(error.TomlSyntax, "dangling escape");
        self.pos += 1;
        switch (c) {
            'b' => try out.append(0x08),
            't' => try out.append('\t'),
            'n' => try out.append('\n'),
            'f' => try out.append(0x0C),
            'r' => try out.append('\r'),
            '"' => try out.append('"'),
            '\\' => try out.append('\\'),
            'e' => try out.append(0x1B),
            'u', 'U' => {
                const digits: usize = if (c == 'u') 4 else 8;
                if (self.pos + digits > self.src.len) return self.fail(error.TomlSyntax, "short unicode escape");
                const hex = self.src[self.pos .. self.pos + digits];
                const cp = std.fmt.parseInt(u32, hex, 16) catch return self.fail(error.TomlSyntax, "bad unicode escape");
                self.pos += digits;
                if (cp > 0x10FFFF or (cp >= 0xD800 and cp <= 0xDFFF)) return self.fail(error.TomlSyntax, "invalid unicode scalar");
                var buf: [4]u8 = undefined;
                const n = std.unicode.utf8Encode(@intCast(cp), &buf) catch return self.fail(error.TomlSyntax, "invalid unicode scalar");
                try out.appendSlice(buf[0..n]);
            },
            else => return self.fail(error.TomlSyntax, "unknown escape"),
        }
    }

    fn parseBasicString(self: *Parser, multiline: bool) ParseError![]const u8 {
        // self.pos is just past the opening quote(s).
        var out = std.array_list.Managed(u8).init(self.alloc);
        errdefer out.deinit();
        if (multiline) {
            // A newline immediately after the opening delimiter is trimmed.
            if (self.peek() == '\r') self.pos += 1;
            if (self.peek() == '\n') self.pos += 1;
        }
        while (true) {
            const c = self.peek() orelse return self.fail(error.TomlSyntax, "unterminated string");
            if (multiline) {
                if (std.mem.startsWith(u8, self.src[self.pos..], "\"\"\"")) {
                    self.pos += 3;
                    // Up to two extra quotes belong to the string.
                    var extra: usize = 0;
                    while (extra < 2 and self.peek() == '"') : (extra += 1) {
                        try out.append('"');
                        self.pos += 1;
                    }
                    break;
                }
            } else {
                if (c == '"') {
                    self.pos += 1;
                    break;
                }
                if (c == '\n') return self.fail(error.TomlSyntax, "newline in string");
            }
            if (c == '\\') {
                self.pos += 1;
                if (multiline) {
                    // Line-ending backslash: skip all following whitespace
                    // including newlines.
                    var p = self.pos;
                    var saw_ws = false;
                    while (p < self.src.len and (self.src[p] == ' ' or self.src[p] == '\t' or self.src[p] == '\n' or self.src[p] == '\r')) : (p += 1) saw_ws = true;
                    if (saw_ws) {
                        self.pos = p;
                        continue;
                    }
                }
                try self.parseEscapeInto(&out);
                continue;
            }
            try out.append(c);
            self.pos += 1;
        }
        return out.toOwnedSlice();
    }

    fn parseLiteralString(self: *Parser, multiline: bool) ParseError![]const u8 {
        var out = std.array_list.Managed(u8).init(self.alloc);
        errdefer out.deinit();
        if (multiline) {
            if (self.peek() == '\r') self.pos += 1;
            if (self.peek() == '\n') self.pos += 1;
        }
        while (true) {
            const c = self.peek() orelse return self.fail(error.TomlSyntax, "unterminated literal string");
            if (multiline) {
                if (std.mem.startsWith(u8, self.src[self.pos..], "'''")) {
                    self.pos += 3;
                    var extra: usize = 0;
                    while (extra < 2 and self.peek() == '\'') : (extra += 1) {
                        try out.append('\'');
                        self.pos += 1;
                    }
                    break;
                }
            } else {
                if (c == '\'') {
                    self.pos += 1;
                    break;
                }
                if (c == '\n') return self.fail(error.TomlSyntax, "newline in literal string");
            }
            try out.append(c);
            self.pos += 1;
        }
        return out.toOwnedSlice();
    }

    fn newTable(self: *Parser, created_as: CreatedAs) ParseError!*Table {
        const t = try self.alloc.create(Table);
        t.* = .{ .entries = std.array_list.Managed(Entry).init(self.alloc), .created_as = created_as };
        return t;
    }

    fn findEntry(table: *Table, key: []const u8) ?*Entry {
        for (table.entries.items) |*entry| {
            if (std.mem.eql(u8, entry.key, key)) return entry;
        }
        return null;
    }

    // Navigate one segment into a table value that must act as a table:
    // plain tables descend directly; arrays of tables descend into the
    // most recent element.
    fn descend(self: *Parser, value: *Value) ParseError!*Table {
        if (value.kind == KIND_TABLE) {
            const t = value.table.?;
            if (t.created_as == .inline_table) return self.fail(error.TomlSyntax, "cannot extend an inline table");
            return t;
        }
        if (value.kind == KIND_ARRAY and value.array_of_tables) {
            if (value.array.len == 0) return self.fail(error.TomlSyntax, "empty array of tables");
            const last = &value.array[value.array.len - 1];
            if (last.kind == KIND_TABLE) return last.table.?;
        }
        return self.fail(error.TomlSyntax, "key conflicts with an existing value");
    }

    // Walk/create intermediate tables for segs[0..n-1]; `flavor` marks how
    // newly created tables came to exist.
    fn navigate(self: *Parser, root: *Table, segs: []const []const u8, flavor: CreatedAs) ParseError!*Table {
        var current = root;
        for (segs) |seg| {
            if (Parser.findEntry(current, seg)) |entry| {
                current = try self.descend(&entry.value);
            } else {
                const t = try self.newTable(flavor);
                const key_copy = try self.alloc.dupe(u8, seg);
                try current.entries.append(.{ .key = key_copy, .value = .{ .kind = KIND_TABLE, .table = t } });
                current = t;
            }
        }
        return current;
    }

    fn insertValue(self: *Parser, table: *Table, key: []const u8, value: Value) ParseError!void {
        if (Parser.findEntry(table, key) != null) {
            return self.fail(error.DuplicateKey, key);
        }
        const key_copy = try self.alloc.dupe(u8, key);
        try table.entries.append(.{ .key = key_copy, .value = value });
    }

    fn parseBareToken(self: *Parser) []const u8 {
        const start = self.pos;
        while (self.pos < self.src.len) {
            const c = self.src[self.pos];
            if (c == ' ' or c == '\t' or c == '\n' or c == '\r' or c == ',' or c == ']' or c == '}' or c == '#') break;
            self.pos += 1;
        }
        return self.src[start..self.pos];
    }

    fn looksLikeDatetime(token: []const u8) bool {
        if (token.len >= 5 and std.ascii.isDigit(token[0]) and std.ascii.isDigit(token[1]) and std.ascii.isDigit(token[2]) and std.ascii.isDigit(token[3]) and token[4] == '-') return true;
        // Local time HH:MM:SS
        if (token.len >= 5 and std.ascii.isDigit(token[0]) and std.ascii.isDigit(token[1]) and token[2] == ':') return true;
        return false;
    }

    fn parseScalarToken(self: *Parser, token: []const u8) ParseError!Value {
        if (std.mem.eql(u8, token, "true")) return .{ .kind = KIND_BOOL, .boolean = true };
        if (std.mem.eql(u8, token, "false")) return .{ .kind = KIND_BOOL, .boolean = false };
        // Integer forms (underscores stripped first).
        var cleaned_buf: [128]u8 = undefined;
        if (token.len <= cleaned_buf.len) {
            var n: usize = 0;
            for (token) |c| {
                if (c != '_') {
                    cleaned_buf[n] = c;
                    n += 1;
                }
            }
            const cleaned = cleaned_buf[0..n];
            if (std.fmt.parseInt(i64, cleaned, 0)) |v| {
                return .{ .kind = KIND_INTEGER, .int = v };
            } else |_| {}
            if (std.fmt.parseFloat(f64, cleaned)) |v| {
                // parseFloat also accepts bare words like "nan"/"inf"; those
                // are valid TOML floats. But it must not swallow datetimes
                // or garbage: require the token to start with a digit, a
                // sign, or be exactly inf/nan spellings.
                const first_ok = cleaned.len > 0 and (std.ascii.isDigit(cleaned[0]) or cleaned[0] == '+' or cleaned[0] == '-' or std.mem.eql(u8, cleaned, "inf") or std.mem.eql(u8, cleaned, "nan"));
                if (first_ok and !looksLikeDatetime(token)) return .{ .kind = KIND_FLOAT, .float = v };
            } else |_| {}
        }
        if (looksLikeDatetime(token)) {
            return .{ .kind = KIND_DATETIME, .str = try self.alloc.dupe(u8, token) };
        }
        return self.fail(error.TomlSyntax, "unrecognized value");
    }

    fn parseValue(self: *Parser) ParseError!Value {
        self.skipInlineWs();
        const c = self.peek() orelse return self.fail(error.TomlSyntax, "expected value");
        switch (c) {
            '"' => {
                if (std.mem.startsWith(u8, self.src[self.pos..], "\"\"\"")) {
                    self.pos += 3;
                    const s = try self.parseBasicString(true);
                    return .{ .kind = KIND_STRING, .str = s };
                }
                self.pos += 1;
                const s = try self.parseBasicString(false);
                return .{ .kind = KIND_STRING, .str = s };
            },
            '\'' => {
                if (std.mem.startsWith(u8, self.src[self.pos..], "'''")) {
                    self.pos += 3;
                    const s = try self.parseLiteralString(true);
                    return .{ .kind = KIND_STRING, .str = s };
                }
                self.pos += 1;
                const s = try self.parseLiteralString(false);
                return .{ .kind = KIND_STRING, .str = s };
            },
            '[' => {
                self.pos += 1;
                var items = std.array_list.Managed(Value).init(self.alloc);
                errdefer {
                    for (items.items) |item| freeValue(self.alloc, item);
                    items.deinit();
                }
                while (true) {
                    self.skipArrayTrivia();
                    if (self.peek() == ']') {
                        self.pos += 1;
                        break;
                    }
                    const item = try self.parseValue();
                    try items.append(item);
                    self.skipArrayTrivia();
                    if (self.peek() == ',') {
                        self.pos += 1;
                        continue;
                    }
                    if (self.peek() == ']') {
                        self.pos += 1;
                        break;
                    }
                    return self.fail(error.TomlSyntax, "expected ',' or ']' in array");
                }
                return .{ .kind = KIND_ARRAY, .array = try items.toOwnedSlice() };
            },
            '{' => {
                self.pos += 1;
                const table = try self.newTable(.inline_table);
                errdefer freeTable(self.alloc, table);
                while (true) {
                    self.skipInlineWs();
                    if (self.peek() == '}') {
                        self.pos += 1;
                        break;
                    }
                    try self.parseKeyValInto(table);
                    self.skipInlineWs();
                    if (self.peek() == ',') {
                        self.pos += 1;
                        continue;
                    }
                    if (self.peek() == '}') {
                        self.pos += 1;
                        break;
                    }
                    return self.fail(error.TomlSyntax, "expected ',' or '}' in inline table");
                }
                return .{ .kind = KIND_TABLE, .table = table };
            },
            else => {
                const token = self.parseBareToken();
                if (token.len == 0) return self.fail(error.TomlSyntax, "expected value");
                // Offset datetimes contain a space before the offset in
                // some styles ("1979-05-27 07:32:00Z" uses 'T' or space).
                // TOML allows a space instead of 'T'; support it by
                // extending the token across one space when the tail
                // still looks like a time.
                if (looksLikeDatetime(token) and token.len >= 10 and self.peek() == ' ') {
                    self.pos += 1;
                    const tail_start = self.pos;
                    while (self.pos < self.src.len and self.src[self.pos] != ' ' and self.src[self.pos] != '\t' and self.src[self.pos] != '\n' and self.src[self.pos] != ',' and self.src[self.pos] != ']' and self.src[self.pos] != '}' and self.src[self.pos] != '#') self.pos += 1;
                    const tail = self.src[tail_start..self.pos];
                    if (tail.len >= 5 and std.ascii.isDigit(tail[0]) and std.ascii.isDigit(tail[1]) and tail[2] == ':') {
                        var joined = std.array_list.Managed(u8).init(self.alloc);
                        try joined.appendSlice(token);
                        try joined.append('T');
                        try joined.appendSlice(tail);
                        return .{ .kind = KIND_DATETIME, .str = try joined.toOwnedSlice() };
                    }
                    self.pos = tail_start - 1;
                }
                return self.parseScalarToken(token);
            },
        }
    }

    fn parseKeyValInto(self: *Parser, table: *Table) ParseError!void {
        const segs = try self.parseDottedKey();
        defer self.freeSegs(segs);
        self.skipInlineWs();
        if (self.peek() != '=') return self.fail(error.TomlSyntax, "expected '='");
        self.pos += 1;
        const value = try self.parseValue();
        errdefer freeValue(self.alloc, value);
        const parent = try self.navigate(table, segs[0 .. segs.len - 1], .dotted);
        try self.insertValue(parent, segs[segs.len - 1], value);
    }

    fn parseHeader(self: *Parser, root: *Table) ParseError!*Table {
        // self.pos at '['
        self.pos += 1;
        var is_array = false;
        if (self.peek() == '[') {
            is_array = true;
            self.pos += 1;
        }
        const segs = try self.parseDottedKey();
        defer self.freeSegs(segs);
        self.skipInlineWs();
        if (self.peek() != ']') return self.fail(error.TomlSyntax, "expected ']'");
        self.pos += 1;
        if (is_array) {
            if (self.peek() != ']') return self.fail(error.TomlSyntax, "expected ']]'");
            self.pos += 1;
        }
        try self.expectNewlineOrEof();

        const parent = try self.navigate(root, segs[0 .. segs.len - 1], .implicit);
        const last = segs[segs.len - 1];
        if (is_array) {
            if (Parser.findEntry(parent, last)) |entry| {
                if (entry.value.kind != KIND_ARRAY or !entry.value.array_of_tables) {
                    return self.fail(error.TomlSyntax, "array table conflicts with existing value");
                }
                const t = try self.newTable(.header);
                t.header_defined = true;
                var items = std.array_list.Managed(Value).init(self.alloc);
                try items.appendSlice(entry.value.array);
                try items.append(.{ .kind = KIND_TABLE, .table = t });
                self.alloc.free(entry.value.array);
                entry.value.array = try items.toOwnedSlice();
                return t;
            }
            const t = try self.newTable(.header);
            t.header_defined = true;
            var items = std.array_list.Managed(Value).init(self.alloc);
            try items.append(.{ .kind = KIND_TABLE, .table = t });
            const arr = try items.toOwnedSlice();
            try self.insertValue(parent, last, .{ .kind = KIND_ARRAY, .array = arr, .array_of_tables = true });
            return t;
        }
        if (Parser.findEntry(parent, last)) |entry| {
            if (entry.value.kind != KIND_TABLE) return self.fail(error.TomlSyntax, "table header conflicts with existing value");
            const t = entry.value.table.?;
            if (t.created_as != .implicit or t.header_defined) {
                return self.fail(error.DuplicateKey, last);
            }
            t.created_as = .header;
            t.header_defined = true;
            return t;
        }
        const t = try self.newTable(.header);
        t.header_defined = true;
        try self.insertValue(parent, last, .{ .kind = KIND_TABLE, .table = t });
        return t;
    }

    fn parseDocument(self: *Parser) ParseError!*Document {
        const root = try self.newTable(.header);
        root.header_defined = true;
        errdefer freeTable(self.alloc, root);
        var current = root;
        while (true) {
            self.skipTrivia();
            if (self.pos >= self.src.len) break;
            if (self.peek() == '[') {
                current = try self.parseHeader(root);
            } else {
                try self.parseKeyValInto(current);
                try self.expectNewlineOrEof();
            }
        }
        const doc = try self.alloc.create(Document);
        doc.* = .{ .allocator = self.alloc, .root = root };
        return doc;
    }
};

// ---------------- dotted-path resolution ----------------

fn splitPath(alloc: std.mem.Allocator, path: []const u8) ![][]const u8 {
    var segs = std.array_list.Managed([]const u8).init(alloc);
    errdefer {
        for (segs.items) |s| alloc.free(s);
        segs.deinit();
    }
    var i: usize = 0;
    while (i < path.len) {
        if (path[i] == '.') {
            i += 1;
            continue;
        }
        if (path[i] == '"' or path[i] == '\'') {
            const quote = path[i];
            const start = i + 1;
            var j = start;
            while (j < path.len and path[j] != quote) j += 1;
            try segs.append(try alloc.dupe(u8, path[start..j]));
            i = if (j < path.len) j + 1 else j;
        } else {
            const start = i;
            while (i < path.len and path[i] != '.') i += 1;
            try segs.append(try alloc.dupe(u8, path[start..i]));
        }
    }
    return segs.toOwnedSlice();
}

fn freePathSegs(alloc: std.mem.Allocator, segs: [][]const u8) void {
    for (segs) |s| alloc.free(s);
    alloc.free(segs);
}

fn findInTable(table: *Table, key: []const u8) ?*Value {
    for (table.entries.items) |*entry| {
        if (std.mem.eql(u8, entry.key, key)) return &entry.value;
    }
    return null;
}

fn resolveValue(doc: *Document, path: []const u8) ?*Value {
    const alloc = std.heap.page_allocator;
    const segs = splitPath(alloc, path) catch return null;
    defer freePathSegs(alloc, segs);
    if (segs.len == 0) return null;
    var current_table: ?*Table = doc.root;
    var current: ?*Value = null;
    for (segs) |seg| {
        if (current_table) |t| {
            const v = findInTable(t, seg) orelse return null;
            current = v;
        } else if (current) |v| {
            if (v.kind == KIND_ARRAY) {
                const idx = std.fmt.parseInt(usize, seg, 10) catch return null;
                if (idx >= v.array.len) return null;
                current = &v.array[idx];
            } else return null;
        } else return null;
        if (current) |v| {
            current_table = if (v.kind == KIND_TABLE) v.table else null;
        }
    }
    return current;
}

fn constSlice(ptr: ?[*]const u8, len: u64) ?[]const u8 {
    if (len == 0) return "";
    const p = ptr orelse return null;
    return p[0..@intCast(len)];
}

// ---------------- exports ----------------

pub export fn sa_toml_parse(bytes: ?[*]const u8, len: u64) u64 {
    clearLastError();
    const input = constSlice(bytes, len) orelse {
        setLastError("toml: invalid argument (null bytes)", .{});
        return 0;
    };
    const alloc = std.heap.page_allocator;
    const owned = alloc.dupe(u8, input) catch return 0;
    defer alloc.free(owned);
    var parser = Parser{ .alloc = alloc, .src = owned };
    const doc = parser.parseDocument() catch return 0;
    return registerDocument(doc) catch {
        doc.deinit();
        return 0;
    };
}

pub export fn sa_toml_free(handle: u64) i32 {
    const doc = removeDocument(handle) orelse return ERR_HANDLE;
    doc.deinit();
    return OK;
}

pub export fn sa_toml_last_error(out_ptr: ?*?[*]const u8, out_len: ?*u64) i32 {
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

pub export fn sa_toml_kind(handle: u64, path_ptr: ?[*]const u8, path_len: u64, out_kind: ?*u32) i32 {
    const slot = out_kind orelse return ERR_INVALID;
    slot.* = 0;
    const doc = getDocument(handle) orelse return ERR_HANDLE;
    const path = constSlice(path_ptr, path_len) orelse return ERR_INVALID;
    if (path.len == 0) {
        slot.* = KIND_TABLE;
        return OK;
    }
    const v = resolveValue(doc, path) orelse return ERR_NOT_FOUND;
    slot.* = v.kind;
    return OK;
}

pub export fn sa_toml_get_string(handle: u64, path_ptr: ?[*]const u8, path_len: u64, out_ptr: ?*?[*]const u8, out_len: ?*u64) i32 {
    const ptr_slot = out_ptr orelse return ERR_INVALID;
    const len_slot = out_len orelse return ERR_INVALID;
    ptr_slot.* = null;
    len_slot.* = 0;
    const doc = getDocument(handle) orelse return ERR_HANDLE;
    const path = constSlice(path_ptr, path_len) orelse return ERR_INVALID;
    const v = resolveValue(doc, path) orelse return ERR_NOT_FOUND;
    if (v.kind != KIND_STRING) return ERR_INVALID;
    ptr_slot.* = v.str.ptr;
    len_slot.* = @intCast(v.str.len);
    return OK;
}

pub export fn sa_toml_get_datetime(handle: u64, path_ptr: ?[*]const u8, path_len: u64, out_ptr: ?*?[*]const u8, out_len: ?*u64) i32 {
    const ptr_slot = out_ptr orelse return ERR_INVALID;
    const len_slot = out_len orelse return ERR_INVALID;
    ptr_slot.* = null;
    len_slot.* = 0;
    const doc = getDocument(handle) orelse return ERR_HANDLE;
    const path = constSlice(path_ptr, path_len) orelse return ERR_INVALID;
    const v = resolveValue(doc, path) orelse return ERR_NOT_FOUND;
    if (v.kind != KIND_DATETIME) return ERR_INVALID;
    ptr_slot.* = v.str.ptr;
    len_slot.* = @intCast(v.str.len);
    return OK;
}

pub export fn sa_toml_get_i64(handle: u64, path_ptr: ?[*]const u8, path_len: u64, out_value: ?*i64) i32 {
    const slot = out_value orelse return ERR_INVALID;
    slot.* = 0;
    const doc = getDocument(handle) orelse return ERR_HANDLE;
    const path = constSlice(path_ptr, path_len) orelse return ERR_INVALID;
    const v = resolveValue(doc, path) orelse return ERR_NOT_FOUND;
    if (v.kind != KIND_INTEGER) return ERR_INVALID;
    slot.* = v.int;
    return OK;
}

pub export fn sa_toml_get_f64(handle: u64, path_ptr: ?[*]const u8, path_len: u64, out_value: ?*f64) i32 {
    const slot = out_value orelse return ERR_INVALID;
    slot.* = 0;
    const doc = getDocument(handle) orelse return ERR_HANDLE;
    const path = constSlice(path_ptr, path_len) orelse return ERR_INVALID;
    const v = resolveValue(doc, path) orelse return ERR_NOT_FOUND;
    if (v.kind != KIND_FLOAT) return ERR_INVALID;
    slot.* = v.float;
    return OK;
}

pub export fn sa_toml_get_bool(handle: u64, path_ptr: ?[*]const u8, path_len: u64, out_value: ?*u32) i32 {
    const slot = out_value orelse return ERR_INVALID;
    slot.* = 0;
    const doc = getDocument(handle) orelse return ERR_HANDLE;
    const path = constSlice(path_ptr, path_len) orelse return ERR_INVALID;
    const v = resolveValue(doc, path) orelse return ERR_NOT_FOUND;
    if (v.kind != KIND_BOOL) return ERR_INVALID;
    slot.* = if (v.boolean) 1 else 0;
    return OK;
}

pub export fn sa_toml_array_len(handle: u64, path_ptr: ?[*]const u8, path_len: u64, out_len: ?*u64) i32 {
    const slot = out_len orelse return ERR_INVALID;
    slot.* = 0;
    const doc = getDocument(handle) orelse return ERR_HANDLE;
    const path = constSlice(path_ptr, path_len) orelse return ERR_INVALID;
    const v = resolveValue(doc, path) orelse return ERR_NOT_FOUND;
    if (v.kind != KIND_ARRAY) return ERR_INVALID;
    slot.* = @intCast(v.array.len);
    return OK;
}

pub export fn sa_toml_table_len(handle: u64, path_ptr: ?[*]const u8, path_len: u64, out_len: ?*u64) i32 {
    const slot = out_len orelse return ERR_INVALID;
    slot.* = 0;
    const doc = getDocument(handle) orelse return ERR_HANDLE;
    const path = constSlice(path_ptr, path_len) orelse return ERR_INVALID;
    if (path.len == 0) {
        slot.* = @intCast(doc.root.entries.items.len);
        return OK;
    }
    const v = resolveValue(doc, path) orelse return ERR_NOT_FOUND;
    if (v.kind != KIND_TABLE) return ERR_INVALID;
    slot.* = @intCast(v.table.?.entries.items.len);
    return OK;
}

pub export fn sa_toml_array_get_string(handle: u64, path_ptr: ?[*]const u8, path_len: u64, index: u64, out_ptr: ?*?[*]const u8, out_len: ?*u64) i32 {
    const ptr_slot = out_ptr orelse return ERR_INVALID;
    const len_slot = out_len orelse return ERR_INVALID;
    ptr_slot.* = null;
    len_slot.* = 0;
    const doc = getDocument(handle) orelse return ERR_HANDLE;
    const path = constSlice(path_ptr, path_len) orelse return ERR_INVALID;
    const v = resolveValue(doc, path) orelse return ERR_NOT_FOUND;
    if (v.kind != KIND_ARRAY) return ERR_INVALID;
    if (index >= v.array.len) return ERR_NOT_FOUND;
    const item = v.array[@intCast(index)];
    if (item.kind != KIND_STRING) return ERR_INVALID;
    ptr_slot.* = item.str.ptr;
    len_slot.* = @intCast(item.str.len);
    return OK;
}

pub export fn sa_toml_array_get_i64(handle: u64, path_ptr: ?[*]const u8, path_len: u64, index: u64, out_value: ?*i64) i32 {
    const slot = out_value orelse return ERR_INVALID;
    slot.* = 0;
    const doc = getDocument(handle) orelse return ERR_HANDLE;
    const path = constSlice(path_ptr, path_len) orelse return ERR_INVALID;
    const v = resolveValue(doc, path) orelse return ERR_NOT_FOUND;
    if (v.kind != KIND_ARRAY) return ERR_INVALID;
    if (index >= v.array.len) return ERR_NOT_FOUND;
    const item = v.array[@intCast(index)];
    if (item.kind != KIND_INTEGER) return ERR_INVALID;
    slot.* = item.int;
    return OK;
}

// ---------------- mutation + serialization (builder) ----------------
//
// The write side mirrors the JSON mutation surface's design language
// (handle + set_* family + a serialization exit), adapted to this
// module's dotted-path addressing. set_* REPLACES whatever sits at the
// path (freeing the old value); intermediate tables are created on
// demand with created_as .dotted. Mutation walks descend into inline
// tables: parsed configs (env = { ... }) must stay editable, and the
// inline-table restriction is a text rule, not a builder rule.

const WriteError = error{ Invalid, NotFound, OutOfMemory };

fn bareTable(alloc: std.mem.Allocator, created_as: CreatedAs) WriteError!*Table {
    const t = alloc.create(Table) catch return error.OutOfMemory;
    t.* = .{ .entries = std.array_list.Managed(Entry).init(alloc), .created_as = created_as };
    return t;
}

// Invalidate the cached serialization after a successful mutation.
fn touch(doc: *Document) void {
    if (doc.ser_buf) |buf| {
        doc.allocator.free(buf);
        doc.ser_buf = null;
    }
}

// Descend one existing container value during a mutation walk. Only
// tables qualify: arrays are addressed by explicit numeric segments
// (handled by the walks themselves), never by an implicit "most
// recent element", so a path means the same thing to the mutation
// walks as it does to resolveValue on the read side.
fn descendMutable(value: *Value) WriteError!*Table {
    if (value.kind == KIND_TABLE) return value.table.?;
    return error.Invalid;
}

// Walk segs as CONTAINERS from the root and return the table they land
// in. With create=false nothing is allocated and a missing segment
// yields error.NotFound (callers read that as "creatable"); with
// create=true missing segments become fresh tables. A numeric segment
// directly after an array key indexes that array, exactly like the
// read side's resolveValue.
fn walkParent(doc: *Document, segs: []const []const u8, create: bool) WriteError!*Table {
    const alloc = doc.allocator;
    var table = doc.root;
    var i: usize = 0;
    while (i < segs.len) {
        const seg = segs[i];
        const entry = Parser.findEntry(table, seg) orelse {
            if (!create) return error.NotFound;
            const t = try bareTable(alloc, .dotted);
            const key_copy = alloc.dupe(u8, seg) catch {
                freeTable(alloc, t);
                return error.OutOfMemory;
            };
            table.entries.append(.{ .key = key_copy, .value = .{ .kind = KIND_TABLE, .table = t } }) catch {
                alloc.free(key_copy);
                freeTable(alloc, t);
                return error.OutOfMemory;
            };
            table = t;
            i += 1;
            continue;
        };
        if (entry.value.kind == KIND_ARRAY and i + 1 < segs.len) {
            if (std.fmt.parseInt(usize, segs[i + 1], 10)) |idx| {
                if (idx >= entry.value.array.len) return error.Invalid;
                const elem = &entry.value.array[idx];
                if (elem.kind != KIND_TABLE) return error.Invalid;
                table = elem.table.?;
                i += 2;
                continue;
            } else |_| {}
            return error.Invalid;
        }
        table = try descendMutable(&entry.value);
        i += 1;
    }
    return table;
}

// Install `value` at `path`, taking ownership of it on every outcome
// (it is freed again on failure). The parent chain is validated before
// any table is created, so a rejected set leaves the document
// untouched apart from tables a dry run proved creatable.
fn setValueAt(doc: *Document, path: []const u8, value: Value) i32 {
    const alloc = doc.allocator;
    const segs = splitPath(alloc, path) catch {
        freeValue(alloc, value);
        return ERR_NOMEM;
    };
    defer freePathSegs(alloc, segs);
    if (segs.len == 0) {
        freeValue(alloc, value);
        return ERR_INVALID;
    }
    _ = walkParent(doc, segs[0 .. segs.len - 1], false) catch |err| switch (err) {
        error.NotFound => {},
        error.OutOfMemory => {
            freeValue(alloc, value);
            return ERR_NOMEM;
        },
        else => {
            freeValue(alloc, value);
            return ERR_INVALID;
        },
    };
    const parent = walkParent(doc, segs[0 .. segs.len - 1], true) catch {
        freeValue(alloc, value);
        return ERR_NOMEM;
    };
    const key = segs[segs.len - 1];
    if (Parser.findEntry(parent, key)) |entry| {
        freeValue(alloc, entry.value);
        entry.value = value;
    } else {
        const key_copy = alloc.dupe(u8, key) catch {
            freeValue(alloc, value);
            return ERR_NOMEM;
        };
        parent.entries.append(.{ .key = key_copy, .value = value }) catch {
            alloc.free(key_copy);
            freeValue(alloc, value);
            return ERR_NOMEM;
        };
    }
    touch(doc);
    return OK;
}

fn appendToArray(alloc: std.mem.Allocator, arr_value: *Value, value: Value) WriteError!void {
    var items = std.array_list.Managed(Value).init(alloc);
    defer items.deinit();
    items.appendSlice(arr_value.array) catch return error.OutOfMemory;
    items.append(value) catch return error.OutOfMemory;
    const new_arr = items.toOwnedSlice() catch return error.OutOfMemory;
    alloc.free(arr_value.array);
    arr_value.array = new_arr;
}

// Append `value` to the array at `path`, creating the array when the
// path is still free. is_table marks arrays created by
// sa_toml_array_push_table so they serialize as [[table]] blocks.
fn pushValueAt(doc: *Document, path: []const u8, value: Value, is_table: bool) i32 {
    const alloc = doc.allocator;
    const segs = splitPath(alloc, path) catch {
        freeValue(alloc, value);
        return ERR_NOMEM;
    };
    defer freePathSegs(alloc, segs);
    if (segs.len == 0) {
        freeValue(alloc, value);
        return ERR_INVALID;
    }
    // Reject up front when a non-array already sits at the path, or a
    // scalar would land in an array of tables.
    if (resolveValue(doc, path)) |existing| {
        if (existing.kind != KIND_ARRAY or (existing.array_of_tables and !is_table)) {
            freeValue(alloc, value);
            return ERR_INVALID;
        }
    }
    _ = walkParent(doc, segs[0 .. segs.len - 1], false) catch |err| switch (err) {
        error.NotFound => {},
        error.OutOfMemory => {
            freeValue(alloc, value);
            return ERR_NOMEM;
        },
        else => {
            freeValue(alloc, value);
            return ERR_INVALID;
        },
    };
    const parent = walkParent(doc, segs[0 .. segs.len - 1], true) catch {
        freeValue(alloc, value);
        return ERR_NOMEM;
    };
    const key = segs[segs.len - 1];
    if (Parser.findEntry(parent, key)) |entry| {
        appendToArray(alloc, &entry.value, value) catch {
            freeValue(alloc, value);
            return ERR_NOMEM;
        };
    } else {
        const key_copy = alloc.dupe(u8, key) catch {
            freeValue(alloc, value);
            return ERR_NOMEM;
        };
        var items = std.array_list.Managed(Value).init(alloc);
        defer items.deinit();
        items.append(value) catch {
            alloc.free(key_copy);
            freeValue(alloc, value);
            return ERR_NOMEM;
        };
        const arr = items.toOwnedSlice() catch {
            alloc.free(key_copy);
            freeValue(alloc, value);
            return ERR_NOMEM;
        };
        parent.entries.append(.{ .key = key_copy, .value = .{ .kind = KIND_ARRAY, .array = arr, .array_of_tables = is_table } }) catch {
            alloc.free(key_copy);
            const arr_value = Value{ .kind = KIND_ARRAY, .array = arr, .array_of_tables = is_table };
            freeValue(alloc, arr_value);
            return ERR_NOMEM;
        };
    }
    touch(doc);
    return OK;
}

fn removeAtPath(doc: *Document, path: []const u8) i32 {
    const alloc = doc.allocator;
    const segs = splitPath(alloc, path) catch return ERR_NOMEM;
    defer freePathSegs(alloc, segs);
    if (segs.len == 0) return ERR_INVALID;
    var table = doc.root;
    var i: usize = 0;
    while (i + 1 < segs.len) {
        const entry = Parser.findEntry(table, segs[i]) orelse return ERR_NOT_FOUND;
        switch (entry.value.kind) {
            KIND_TABLE => {
                table = entry.value.table.?;
                i += 1;
            },
            KIND_ARRAY => {
                if (std.fmt.parseInt(usize, segs[i + 1], 10)) |idx| {
                    if (idx >= entry.value.array.len) return ERR_NOT_FOUND;
                    if (i + 2 == segs.len) {
                        // The final segment indexes this array: remove
                        // the element itself.
                        var items = std.array_list.Managed(Value).init(alloc);
                        defer items.deinit();
                        items.appendSlice(entry.value.array) catch return ERR_NOMEM;
                        const removed = items.orderedRemove(idx);
                        const new_arr = items.toOwnedSlice() catch return ERR_NOMEM;
                        alloc.free(entry.value.array);
                        entry.value.array = new_arr;
                        freeValue(alloc, removed);
                        touch(doc);
                        return OK;
                    }
                    const elem = &entry.value.array[idx];
                    if (elem.kind != KIND_TABLE) return ERR_NOT_FOUND;
                    table = elem.table.?;
                    i += 2;
                } else |_| {
                    // A non-numeric segment addresses nothing inside
                    // an array (read-side parity).
                    return ERR_NOT_FOUND;
                }
            },
            else => return ERR_NOT_FOUND,
        }
    }
    const key = segs[segs.len - 1];
    for (table.entries.items, 0..) |entry, idx| {
        if (std.mem.eql(u8, entry.key, key)) {
            const removed = table.entries.orderedRemove(idx);
            alloc.free(removed.key);
            freeValue(alloc, removed.value);
            touch(doc);
            return OK;
        }
    }
    return ERR_NOT_FOUND;
}

// ---------------- serializer ----------------

fn isBareKey(key: []const u8) bool {
    if (key.len == 0) return false;
    for (key) |c| {
        const ok = (c >= 'A' and c <= 'Z') or (c >= 'a' and c <= 'z') or (c >= '0' and c <= '9') or c == '_' or c == '-';
        if (!ok) return false;
    }
    return true;
}

fn writeEscapedInto(out: *std.array_list.Managed(u8), s: []const u8) error{OutOfMemory}!void {
    const hexd = "0123456789ABCDEF";
    for (s) |c| {
        switch (c) {
            '"' => try out.appendSlice("\\\""),
            '\\' => try out.appendSlice("\\\\"),
            0x08 => try out.appendSlice("\\b"),
            '\t' => try out.appendSlice("\\t"),
            '\n' => try out.appendSlice("\\n"),
            0x0C => try out.appendSlice("\\f"),
            '\r' => try out.appendSlice("\\r"),
            else => {
                if (c < 0x20 or c == 0x7F) {
                    try out.appendSlice("\\u00");
                    try out.append(hexd[(c >> 4) & 0xF]);
                    try out.append(hexd[c & 0xF]);
                } else {
                    try out.append(c);
                }
            },
        }
    }
}

fn writeKeyInto(out: *std.array_list.Managed(u8), key: []const u8) error{OutOfMemory}!void {
    if (isBareKey(key)) {
        try out.appendSlice(key);
        return;
    }
    try out.append('"');
    try writeEscapedInto(out, key);
    try out.append('"');
}

fn writeFloatInto(alloc: std.mem.Allocator, out: *std.array_list.Managed(u8), v: f64) error{OutOfMemory}!void {
    if (std.math.isNan(v)) {
        try out.appendSlice("nan");
        return;
    }
    if (std.math.isInf(v)) {
        try out.appendSlice(if (v > 0) "inf" else "-inf");
        return;
    }
    const s = try std.fmt.allocPrint(alloc, "{d}", .{v});
    defer alloc.free(s);
    try out.appendSlice(s);
    // Keep the value a float on reparse: bare "1" would read back as
    // an integer.
    if (std.mem.indexOfAny(u8, s, ".eE") == null) try out.appendSlice(".0");
}

// Value form: scalars, arrays and tables as they appear after "=" or
// inside an array (tables become inline tables here).
fn writeValueInto(alloc: std.mem.Allocator, out: *std.array_list.Managed(u8), value: Value) error{OutOfMemory}!void {
    switch (value.kind) {
        KIND_STRING => {
            try out.append('"');
            try writeEscapedInto(out, value.str);
            try out.append('"');
        },
        KIND_DATETIME => try out.appendSlice(value.str),
        KIND_INTEGER => {
            const s = try std.fmt.allocPrint(alloc, "{d}", .{value.int});
            defer alloc.free(s);
            try out.appendSlice(s);
        },
        KIND_FLOAT => try writeFloatInto(alloc, out, value.float),
        KIND_BOOL => try out.appendSlice(if (value.boolean) "true" else "false"),
        KIND_ARRAY => {
            try out.append('[');
            for (value.array, 0..) |item, idx| {
                if (idx > 0) try out.appendSlice(", ");
                try writeValueInto(alloc, out, item);
            }
            try out.append(']');
        },
        KIND_TABLE => {
            const t = value.table.?;
            try out.appendSlice("{");
            for (t.entries.items, 0..) |entry, idx| {
                if (idx > 0) try out.appendSlice(",");
                try out.append(' ');
                try writeKeyInto(out, entry.key);
                try out.appendSlice(" = ");
                try writeValueInto(alloc, out, entry.value);
            }
            if (t.entries.items.len > 0) try out.append(' ');
            try out.append('}');
        },
        else => {},
    }
}

fn childPrefix(alloc: std.mem.Allocator, prefix: []const u8, key: []const u8) error{OutOfMemory}![]u8 {
    var seg = std.array_list.Managed(u8).init(alloc);
    defer seg.deinit();
    try writeKeyInto(&seg, key);
    if (prefix.len == 0) return alloc.dupe(u8, seg.items);
    return std.fmt.allocPrint(alloc, "{s}.{s}", .{ prefix, seg.items });
}

// Section form: plain entries first (they belong to the section the
// caller just opened), then subtable sections, then [[array]] blocks.
// prefix is this table's written dotted path ("" for the root).
fn writeTableInto(alloc: std.mem.Allocator, out: *std.array_list.Managed(u8), table: *Table, prefix: []const u8) error{OutOfMemory}!void {
    for (table.entries.items) |entry| {
        const v = entry.value;
        if (v.kind == KIND_TABLE) continue;
        if (v.kind == KIND_ARRAY and v.array_of_tables) continue;
        try writeKeyInto(out, entry.key);
        try out.appendSlice(" = ");
        try writeValueInto(alloc, out, v);
        try out.append('\n');
    }
    for (table.entries.items) |entry| {
        if (entry.value.kind != KIND_TABLE) continue;
        const p = try childPrefix(alloc, prefix, entry.key);
        defer alloc.free(p);
        try out.append('[');
        try out.appendSlice(p);
        try out.appendSlice("]\n");
        try writeTableInto(alloc, out, entry.value.table.?, p);
    }
    for (table.entries.items) |entry| {
        const v = entry.value;
        if (v.kind != KIND_ARRAY or !v.array_of_tables) continue;
        const p = try childPrefix(alloc, prefix, entry.key);
        defer alloc.free(p);
        for (v.array) |elem| {
            if (elem.kind != KIND_TABLE) continue;
            try out.appendSlice("[[");
            try out.appendSlice(p);
            try out.appendSlice("]]\n");
            try writeTableInto(alloc, out, elem.table.?, p);
        }
    }
}

// ---------------- write-side exports ----------------

pub export fn sa_toml_new() u64 {
    const alloc = std.heap.page_allocator;
    const root = bareTable(alloc, .header) catch return 0;
    root.header_defined = true;
    const doc = alloc.create(Document) catch {
        freeTable(alloc, root);
        return 0;
    };
    doc.* = .{ .allocator = alloc, .root = root };
    return registerDocument(doc) catch {
        doc.deinit();
        return 0;
    };
}

pub export fn sa_toml_table_key_at(handle: u64, path_ptr: ?[*]const u8, path_len: u64, index: u64, out_ptr: ?*?[*]const u8, out_len: ?*u64) i32 {
    const ptr_slot = out_ptr orelse return ERR_INVALID;
    const len_slot = out_len orelse return ERR_INVALID;
    ptr_slot.* = null;
    len_slot.* = 0;
    const doc = getDocument(handle) orelse return ERR_HANDLE;
    const path = constSlice(path_ptr, path_len) orelse return ERR_INVALID;
    var table = doc.root;
    if (path.len != 0) {
        const v = resolveValue(doc, path) orelse return ERR_NOT_FOUND;
        if (v.kind != KIND_TABLE) return ERR_INVALID;
        table = v.table.?;
    }
    if (index >= table.entries.items.len) return ERR_NOT_FOUND;
    const key = table.entries.items[@intCast(index)].key;
    ptr_slot.* = key.ptr;
    len_slot.* = @intCast(key.len);
    return OK;
}

pub export fn sa_toml_set_string(handle: u64, path_ptr: ?[*]const u8, path_len: u64, val_ptr: ?[*]const u8, val_len: u64) i32 {
    const doc = getDocument(handle) orelse return ERR_HANDLE;
    const path = constSlice(path_ptr, path_len) orelse return ERR_INVALID;
    const raw = constSlice(val_ptr, val_len) orelse return ERR_INVALID;
    const owned = doc.allocator.dupe(u8, raw) catch return ERR_NOMEM;
    return setValueAt(doc, path, .{ .kind = KIND_STRING, .str = owned });
}

pub export fn sa_toml_set_datetime(handle: u64, path_ptr: ?[*]const u8, path_len: u64, val_ptr: ?[*]const u8, val_len: u64) i32 {
    const doc = getDocument(handle) orelse return ERR_HANDLE;
    const path = constSlice(path_ptr, path_len) orelse return ERR_INVALID;
    const raw = constSlice(val_ptr, val_len) orelse return ERR_INVALID;
    const owned = doc.allocator.dupe(u8, raw) catch return ERR_NOMEM;
    return setValueAt(doc, path, .{ .kind = KIND_DATETIME, .str = owned });
}

pub export fn sa_toml_set_i64(handle: u64, path_ptr: ?[*]const u8, path_len: u64, value: i64) i32 {
    const doc = getDocument(handle) orelse return ERR_HANDLE;
    const path = constSlice(path_ptr, path_len) orelse return ERR_INVALID;
    return setValueAt(doc, path, .{ .kind = KIND_INTEGER, .int = value });
}

pub export fn sa_toml_set_f64(handle: u64, path_ptr: ?[*]const u8, path_len: u64, value: f64) i32 {
    const doc = getDocument(handle) orelse return ERR_HANDLE;
    const path = constSlice(path_ptr, path_len) orelse return ERR_INVALID;
    return setValueAt(doc, path, .{ .kind = KIND_FLOAT, .float = value });
}

pub export fn sa_toml_set_bool(handle: u64, path_ptr: ?[*]const u8, path_len: u64, value: u32) i32 {
    const doc = getDocument(handle) orelse return ERR_HANDLE;
    const path = constSlice(path_ptr, path_len) orelse return ERR_INVALID;
    return setValueAt(doc, path, .{ .kind = KIND_BOOL, .boolean = value != 0 });
}

pub export fn sa_toml_set_table(handle: u64, path_ptr: ?[*]const u8, path_len: u64) i32 {
    const doc = getDocument(handle) orelse return ERR_HANDLE;
    const path = constSlice(path_ptr, path_len) orelse return ERR_INVALID;
    const alloc = doc.allocator;
    const segs = splitPath(alloc, path) catch return ERR_NOMEM;
    defer freePathSegs(alloc, segs);
    if (segs.len == 0) return ERR_INVALID;
    _ = walkParent(doc, segs[0 .. segs.len - 1], false) catch |err| switch (err) {
        error.NotFound => {},
        error.OutOfMemory => return ERR_NOMEM,
        else => return ERR_INVALID,
    };
    const parent = walkParent(doc, segs[0 .. segs.len - 1], true) catch return ERR_NOMEM;
    const key = segs[segs.len - 1];
    if (Parser.findEntry(parent, key)) |entry| {
        // Ensuring a table that already exists is a no-op success; a
        // conflicting non-table is never silently destroyed.
        if (entry.value.kind != KIND_TABLE) return ERR_INVALID;
        touch(doc);
        return OK;
    }
    const t = bareTable(alloc, .dotted) catch return ERR_NOMEM;
    const key_copy = alloc.dupe(u8, key) catch {
        freeTable(alloc, t);
        return ERR_NOMEM;
    };
    parent.entries.append(.{ .key = key_copy, .value = .{ .kind = KIND_TABLE, .table = t } }) catch {
        alloc.free(key_copy);
        freeTable(alloc, t);
        return ERR_NOMEM;
    };
    touch(doc);
    return OK;
}

pub export fn sa_toml_remove(handle: u64, path_ptr: ?[*]const u8, path_len: u64) i32 {
    const doc = getDocument(handle) orelse return ERR_HANDLE;
    const path = constSlice(path_ptr, path_len) orelse return ERR_INVALID;
    return removeAtPath(doc, path);
}

pub export fn sa_toml_array_push_string(handle: u64, path_ptr: ?[*]const u8, path_len: u64, val_ptr: ?[*]const u8, val_len: u64) i32 {
    const doc = getDocument(handle) orelse return ERR_HANDLE;
    const path = constSlice(path_ptr, path_len) orelse return ERR_INVALID;
    const raw = constSlice(val_ptr, val_len) orelse return ERR_INVALID;
    const owned = doc.allocator.dupe(u8, raw) catch return ERR_NOMEM;
    return pushValueAt(doc, path, .{ .kind = KIND_STRING, .str = owned }, false);
}

pub export fn sa_toml_array_push_datetime(handle: u64, path_ptr: ?[*]const u8, path_len: u64, val_ptr: ?[*]const u8, val_len: u64) i32 {
    const doc = getDocument(handle) orelse return ERR_HANDLE;
    const path = constSlice(path_ptr, path_len) orelse return ERR_INVALID;
    const raw = constSlice(val_ptr, val_len) orelse return ERR_INVALID;
    const owned = doc.allocator.dupe(u8, raw) catch return ERR_NOMEM;
    return pushValueAt(doc, path, .{ .kind = KIND_DATETIME, .str = owned }, false);
}

pub export fn sa_toml_array_push_i64(handle: u64, path_ptr: ?[*]const u8, path_len: u64, value: i64) i32 {
    const doc = getDocument(handle) orelse return ERR_HANDLE;
    const path = constSlice(path_ptr, path_len) orelse return ERR_INVALID;
    return pushValueAt(doc, path, .{ .kind = KIND_INTEGER, .int = value }, false);
}

pub export fn sa_toml_array_push_f64(handle: u64, path_ptr: ?[*]const u8, path_len: u64, value: f64) i32 {
    const doc = getDocument(handle) orelse return ERR_HANDLE;
    const path = constSlice(path_ptr, path_len) orelse return ERR_INVALID;
    return pushValueAt(doc, path, .{ .kind = KIND_FLOAT, .float = value }, false);
}

pub export fn sa_toml_array_push_bool(handle: u64, path_ptr: ?[*]const u8, path_len: u64, value: u32) i32 {
    const doc = getDocument(handle) orelse return ERR_HANDLE;
    const path = constSlice(path_ptr, path_len) orelse return ERR_INVALID;
    return pushValueAt(doc, path, .{ .kind = KIND_BOOL, .boolean = value != 0 }, false);
}

pub export fn sa_toml_array_push_table(handle: u64, path_ptr: ?[*]const u8, path_len: u64) i32 {
    const doc = getDocument(handle) orelse return ERR_HANDLE;
    const path = constSlice(path_ptr, path_len) orelse return ERR_INVALID;
    const t = bareTable(doc.allocator, .header) catch return ERR_NOMEM;
    t.header_defined = true;
    return pushValueAt(doc, path, .{ .kind = KIND_TABLE, .table = t }, true);
}

pub export fn sa_toml_stringify(handle: u64, out_ptr: ?*?[*]const u8, out_len: ?*u64) i32 {
    const ptr_slot = out_ptr orelse return ERR_INVALID;
    const len_slot = out_len orelse return ERR_INVALID;
    ptr_slot.* = null;
    len_slot.* = 0;
    const doc = getDocument(handle) orelse return ERR_HANDLE;
    const alloc = doc.allocator;
    var out = std.array_list.Managed(u8).init(alloc);
    defer out.deinit();
    writeTableInto(alloc, &out, doc.root, "") catch return ERR_NOMEM;
    const buf = out.toOwnedSlice() catch return ERR_NOMEM;
    if (doc.ser_buf) |old| alloc.free(old);
    doc.ser_buf = buf;
    ptr_slot.* = buf.ptr;
    len_slot.* = @intCast(buf.len);
    return OK;
}

// ---------------- tests ----------------

test "toml: codex-style config values by dotted path" {
    const text =
        \\model = "gpt-cxu"
        \\temperature = 0.2
        \\max_turns = 42
        \\debug = true
        \\released = 2026-10-25T07:32:00Z
        \\
        \\[model_providers.cxu]
        \\base_url = "https://example.invalid/v1"
        \\wire_api = "responses"
        \\
        \\[mcp_servers.jex]
        \\command = "node"
        \\args = ["server.js", "--port", "8080"]
        \\env = { API_KEY = "redacted", RETRIES = 3 }
        \\
        \\[[servers]]
        \\host = "a.example"
        \\port = 8001
        \\
        \\[[servers]]
        \\host = "b.example"
        \\port = 8002
    ;
    const doc = sa_toml_parse(text.ptr, text.len);
    try std.testing.expect(doc != 0);
    defer _ = sa_toml_free(doc);

    var sp: ?[*]const u8 = null;
    var sl: u64 = 0;
    try std.testing.expectEqual(OK, sa_toml_get_string(doc, "model".ptr, 5, &sp, &sl));
    try std.testing.expectEqualStrings("gpt-cxu", sp.?[0..@intCast(sl)]);
    try std.testing.expectEqual(OK, sa_toml_get_string(doc, "model_providers.cxu.base_url".ptr, 28, &sp, &sl));
    try std.testing.expectEqualStrings("https://example.invalid/v1", sp.?[0..@intCast(sl)]);

    var iv: i64 = 0;
    try std.testing.expectEqual(OK, sa_toml_get_i64(doc, "max_turns".ptr, 9, &iv));
    try std.testing.expectEqual(@as(i64, 42), iv);
    try std.testing.expectEqual(OK, sa_toml_get_i64(doc, "mcp_servers.jex.env.RETRIES".ptr, 27, &iv));
    try std.testing.expectEqual(@as(i64, 3), iv);
    try std.testing.expectEqual(OK, sa_toml_get_i64(doc, "servers.1.port".ptr, 14, &iv));
    try std.testing.expectEqual(@as(i64, 8002), iv);

    var fv: f64 = 0;
    try std.testing.expectEqual(OK, sa_toml_get_f64(doc, "temperature".ptr, 11, &fv));
    try std.testing.expectApproxEqAbs(@as(f64, 0.2), fv, 0.000001);

    var bv: u32 = 0;
    try std.testing.expectEqual(OK, sa_toml_get_bool(doc, "debug".ptr, 5, &bv));
    try std.testing.expectEqual(@as(u32, 1), bv);

    var kind: u32 = 0;
    try std.testing.expectEqual(OK, sa_toml_kind(doc, "released".ptr, 8, &kind));
    try std.testing.expectEqual(KIND_DATETIME, kind);
    try std.testing.expectEqual(OK, sa_toml_get_datetime(doc, "released".ptr, 8, &sp, &sl));
    try std.testing.expectEqualStrings("2026-10-25T07:32:00Z", sp.?[0..@intCast(sl)]);

    var n: u64 = 0;
    try std.testing.expectEqual(OK, sa_toml_array_len(doc, "mcp_servers.jex.args".ptr, 20, &n));
    try std.testing.expectEqual(@as(u64, 3), n);
    try std.testing.expectEqual(OK, sa_toml_array_get_string(doc, "mcp_servers.jex.args".ptr, 20, 1, &sp, &sl));
    try std.testing.expectEqualStrings("--port", sp.?[0..@intCast(sl)]);
    try std.testing.expectEqual(OK, sa_toml_array_len(doc, "servers".ptr, 7, &n));
    try std.testing.expectEqual(@as(u64, 2), n);
    try std.testing.expectEqual(OK, sa_toml_table_len(doc, "mcp_servers.jex".ptr, 15, &n));
    try std.testing.expectEqual(@as(u64, 3), n);
    try std.testing.expectEqual(ERR_NOT_FOUND, sa_toml_get_string(doc, "missing.key".ptr, 11, &sp, &sl));
    try std.testing.expectEqual(ERR_INVALID, sa_toml_get_string(doc, "max_turns".ptr, 9, &sp, &sl));
}

test "toml: duplicate keys and redefined tables are hard errors" {
    const dup_key = "a = 1\na = 2\n";
    try std.testing.expectEqual(@as(u64, 0), sa_toml_parse(dup_key.ptr, dup_key.len));
    var sp: ?[*]const u8 = null;
    var sl: u64 = 0;
    try std.testing.expectEqual(OK, sa_toml_last_error(&sp, &sl));
    try std.testing.expect(std.mem.indexOf(u8, sp.?[0..@intCast(sl)], "duplicate") != null);

    const dup_table = "[t]\na = 1\n[t]\nb = 2\n";
    try std.testing.expectEqual(@as(u64, 0), sa_toml_parse(dup_table.ptr, dup_table.len));

    const dotted_then_header = "a.b = 1\n[a]\n";
    try std.testing.expectEqual(@as(u64, 0), sa_toml_parse(dotted_then_header.ptr, dotted_then_header.len));

    const bad_syntax = "a = \n";
    try std.testing.expectEqual(@as(u64, 0), sa_toml_parse(bad_syntax.ptr, bad_syntax.len));
}

test "toml: string forms and escapes" {
    const text =
        \\lit = 'C:\path\file'
        \\esc = "a\tb\u00e9"
        \\hex = 0xDEADBEEF
        \\under = 1_000_000
    ;
    const doc = sa_toml_parse(text.ptr, text.len);
    try std.testing.expect(doc != 0);
    defer _ = sa_toml_free(doc);
    var sp: ?[*]const u8 = null;
    var sl: u64 = 0;
    try std.testing.expectEqual(OK, sa_toml_get_string(doc, "lit".ptr, 3, &sp, &sl));
    try std.testing.expectEqualStrings("C:\\path\\file", sp.?[0..@intCast(sl)]);
    var iv: i64 = 0;
    try std.testing.expectEqual(OK, sa_toml_get_i64(doc, "hex".ptr, 3, &iv));
    try std.testing.expectEqual(@as(i64, 0xDEADBEEF), iv);
    try std.testing.expectEqual(OK, sa_toml_get_i64(doc, "under".ptr, 5, &iv));
    try std.testing.expectEqual(@as(i64, 1000000), iv);
}

test "toml: table key enumeration" {
    const text =
        \\name = "cxu"
        \\version = 3
        \\
        \\[owner]
        \\name = "layola13"
        \\id = 7
        \\
        \\[empty]
    ;
    const doc = sa_toml_parse(text.ptr, text.len);
    try std.testing.expect(doc != 0);
    defer _ = sa_toml_free(doc);

    var n: u64 = 0;
    try std.testing.expectEqual(OK, sa_toml_table_len(doc, "".ptr, 0, &n));
    try std.testing.expectEqual(@as(u64, 4), n);

    var kp: ?[*]const u8 = null;
    var kl: u64 = 0;
    try std.testing.expectEqual(OK, sa_toml_table_key_at(doc, "".ptr, 0, 0, &kp, &kl));
    try std.testing.expectEqualStrings("name", kp.?[0..@intCast(kl)]);
    try std.testing.expectEqual(OK, sa_toml_table_key_at(doc, "".ptr, 0, 3, &kp, &kl));
    try std.testing.expectEqualStrings("empty", kp.?[0..@intCast(kl)]);
    try std.testing.expectEqual(ERR_NOT_FOUND, sa_toml_table_key_at(doc, "".ptr, 0, 4, &kp, &kl));

    const owner = "owner";
    try std.testing.expectEqual(OK, sa_toml_table_len(doc, owner.ptr, owner.len, &n));
    try std.testing.expectEqual(@as(u64, 2), n);
    try std.testing.expectEqual(OK, sa_toml_table_key_at(doc, owner.ptr, owner.len, 1, &kp, &kl));
    try std.testing.expectEqualStrings("id", kp.?[0..@intCast(kl)]);

    const empty = "empty";
    try std.testing.expectEqual(OK, sa_toml_table_len(doc, empty.ptr, empty.len, &n));
    try std.testing.expectEqual(@as(u64, 0), n);
    try std.testing.expectEqual(ERR_NOT_FOUND, sa_toml_table_key_at(doc, empty.ptr, empty.len, 0, &kp, &kl));

    const not_table = "name";
    try std.testing.expectEqual(ERR_INVALID, sa_toml_table_key_at(doc, not_table.ptr, not_table.len, 0, &kp, &kl));
    const missing = "nope";
    try std.testing.expectEqual(ERR_NOT_FOUND, sa_toml_table_key_at(doc, missing.ptr, missing.len, 0, &kp, &kl));
    try std.testing.expectEqual(ERR_HANDLE, sa_toml_table_key_at(999999, "".ptr, 0, 0, &kp, &kl));
}

test "toml: build a document and stringify round-trip" {
    const doc = sa_toml_new();
    try std.testing.expect(doc != 0);
    defer _ = sa_toml_free(doc);

    const title = "title";
    const cfg = "cfg.toml";
    try std.testing.expectEqual(OK, sa_toml_set_string(doc, title.ptr, title.len, cfg.ptr, cfg.len));
    const debug = "debug";
    try std.testing.expectEqual(OK, sa_toml_set_bool(doc, debug.ptr, debug.len, 1));
    const ratio = "ratio";
    try std.testing.expectEqual(OK, sa_toml_set_f64(doc, ratio.ptr, ratio.len, 1.0));
    const stamp = "stamp";
    const when = "2026-10-26T01:02:03Z";
    try std.testing.expectEqual(OK, sa_toml_set_datetime(doc, stamp.ptr, stamp.len, when.ptr, when.len));

    const host = "server.host";
    const hostv = "localhost";
    try std.testing.expectEqual(OK, sa_toml_set_string(doc, host.ptr, host.len, hostv.ptr, hostv.len));
    const port = "server.port";
    try std.testing.expectEqual(OK, sa_toml_set_i64(doc, port.ptr, port.len, 8080));
    const opts = "server.opts";
    try std.testing.expectEqual(OK, sa_toml_set_table(doc, opts.ptr, opts.len));
    // Ensuring a table that already exists is a no-op success.
    try std.testing.expectEqual(OK, sa_toml_set_table(doc, opts.ptr, opts.len));
    // ...but a scalar in the way is an error, never silently destroyed.
    try std.testing.expectEqual(ERR_INVALID, sa_toml_set_table(doc, title.ptr, title.len));

    const tags = "tags";
    const t1 = "alpha";
    const t2 = "beta";
    try std.testing.expectEqual(OK, sa_toml_array_push_string(doc, tags.ptr, tags.len, t1.ptr, t1.len));
    try std.testing.expectEqual(OK, sa_toml_array_push_string(doc, tags.ptr, tags.len, t2.ptr, t2.len));
    const nums = "nums";
    try std.testing.expectEqual(OK, sa_toml_array_push_i64(doc, nums.ptr, nums.len, 10));
    try std.testing.expectEqual(OK, sa_toml_array_push_f64(doc, nums.ptr, nums.len, 2.5));
    try std.testing.expectEqual(OK, sa_toml_array_push_bool(doc, nums.ptr, nums.len, 0));
    const stamps = "stamps";
    try std.testing.expectEqual(OK, sa_toml_array_push_datetime(doc, stamps.ptr, stamps.len, when.ptr, when.len));
    // A scalar push into an array of tables is rejected.
    const servers = "servers";
    try std.testing.expectEqual(OK, sa_toml_array_push_table(doc, servers.ptr, servers.len));
    try std.testing.expectEqual(ERR_INVALID, sa_toml_array_push_i64(doc, servers.ptr, servers.len, 1));
    try std.testing.expectEqual(OK, sa_toml_array_push_table(doc, servers.ptr, servers.len));
    const s0 = "servers.0.host";
    const h0 = "a.example";
    try std.testing.expectEqual(OK, sa_toml_set_string(doc, s0.ptr, s0.len, h0.ptr, h0.len));
    const s1 = "servers.1.host";
    const h1 = "b.example";
    try std.testing.expectEqual(OK, sa_toml_set_string(doc, s1.ptr, s1.len, h1.ptr, h1.len));
    const s1p = "servers.1.port";
    try std.testing.expectEqual(OK, sa_toml_set_i64(doc, s1p.ptr, s1p.len, 9001));
    // Array elements are addressed by explicit index only: the bare
    // form resolves neither on the read side nor on the write side.
    const slast = "servers.host";
    var chk: ?[*]const u8 = null;
    var chkl: u64 = 0;
    try std.testing.expectEqual(ERR_NOT_FOUND, sa_toml_get_string(doc, slast.ptr, slast.len, &chk, &chkl));
    try std.testing.expectEqual(ERR_INVALID, sa_toml_set_string(doc, slast.ptr, slast.len, h1.ptr, h1.len));

    var sp: ?[*]const u8 = null;
    var sl: u64 = 0;
    try std.testing.expectEqual(OK, sa_toml_stringify(doc, &sp, &sl));
    const text = sp.?[0..@intCast(sl)];
    try std.testing.expect(std.mem.indexOf(u8, text, "[server]") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "[[servers]]") != null);

    const doc2 = sa_toml_parse(text.ptr, text.len);
    try std.testing.expect(doc2 != 0);
    defer _ = sa_toml_free(doc2);
    var iv: i64 = 0;
    try std.testing.expectEqual(OK, sa_toml_get_i64(doc2, port.ptr, port.len, &iv));
    try std.testing.expectEqual(@as(i64, 8080), iv);
    var fv: f64 = 0;
    try std.testing.expectEqual(OK, sa_toml_get_f64(doc2, ratio.ptr, ratio.len, &fv));
    try std.testing.expectEqual(@as(f64, 1.0), fv);
    var kind: u32 = 0;
    try std.testing.expectEqual(OK, sa_toml_kind(doc2, ratio.ptr, ratio.len, &kind));
    try std.testing.expectEqual(KIND_FLOAT, kind);
    try std.testing.expectEqual(OK, sa_toml_kind(doc2, stamp.ptr, stamp.len, &kind));
    try std.testing.expectEqual(KIND_DATETIME, kind);
    var n: u64 = 0;
    try std.testing.expectEqual(OK, sa_toml_array_len(doc2, servers.ptr, servers.len, &n));
    try std.testing.expectEqual(@as(u64, 2), n);
    try std.testing.expectEqual(OK, sa_toml_get_string(doc2, s1.ptr, s1.len, &sp, &sl));
    try std.testing.expectEqualStrings("b.example", sp.?[0..@intCast(sl)]);
    try std.testing.expectEqual(OK, sa_toml_table_len(doc2, opts.ptr, opts.len, &n));
    try std.testing.expectEqual(@as(u64, 0), n);
    try std.testing.expectEqual(OK, sa_toml_array_get_string(doc2, tags.ptr, tags.len, 1, &sp, &sl));
    try std.testing.expectEqualStrings("beta", sp.?[0..@intCast(sl)]);
    try std.testing.expectEqual(OK, sa_toml_array_len(doc2, stamps.ptr, stamps.len, &n));
    try std.testing.expectEqual(@as(u64, 1), n);
}

test "toml: mutate a parsed document" {
    const text =
        \\model = "old"
        \\keep = 1
        \\
        \\[mcp_servers.jex]
        \\command = "node"
        \\args = ["a", "b", "c"]
        \\env = { API_KEY = "k1", RETRIES = 3 }
    ;
    const doc = sa_toml_parse(text.ptr, text.len);
    try std.testing.expect(doc != 0);
    defer _ = sa_toml_free(doc);

    const model = "model";
    const newv = "new";
    try std.testing.expectEqual(OK, sa_toml_set_string(doc, model.ptr, model.len, newv.ptr, newv.len));
    var sp: ?[*]const u8 = null;
    var sl: u64 = 0;
    try std.testing.expectEqual(OK, sa_toml_get_string(doc, model.ptr, model.len, &sp, &sl));
    try std.testing.expectEqualStrings("new", sp.?[0..@intCast(sl)]);

    // Descend into an inline table and replace a value inside it.
    const retries = "mcp_servers.jex.env.RETRIES";
    try std.testing.expectEqual(OK, sa_toml_set_i64(doc, retries.ptr, retries.len, 9));
    var iv: i64 = 0;
    try std.testing.expectEqual(OK, sa_toml_get_i64(doc, retries.ptr, retries.len, &iv));
    try std.testing.expectEqual(@as(i64, 9), iv);

    // A set whose parent path crosses a scalar is an invalid argument
    // and leaves the document untouched.
    const through = "keep.x";
    try std.testing.expectEqual(ERR_INVALID, sa_toml_set_i64(doc, through.ptr, through.len, 1));
    try std.testing.expectEqual(OK, sa_toml_get_i64(doc, "keep".ptr, 4, &iv));
    try std.testing.expectEqual(@as(i64, 1), iv);

    // Remove a key, then an array element (numeric final segment).
    const keep = "keep";
    try std.testing.expectEqual(OK, sa_toml_remove(doc, keep.ptr, keep.len));
    var kind: u32 = 0;
    try std.testing.expectEqual(ERR_NOT_FOUND, sa_toml_kind(doc, keep.ptr, keep.len, &kind));
    try std.testing.expectEqual(ERR_NOT_FOUND, sa_toml_remove(doc, keep.ptr, keep.len));

    const args0 = "mcp_servers.jex.args.0";
    try std.testing.expectEqual(OK, sa_toml_remove(doc, args0.ptr, args0.len));
    const args = "mcp_servers.jex.args";
    var n: u64 = 0;
    try std.testing.expectEqual(OK, sa_toml_array_len(doc, args.ptr, args.len, &n));
    try std.testing.expectEqual(@as(u64, 2), n);
    try std.testing.expectEqual(OK, sa_toml_array_get_string(doc, args.ptr, args.len, 0, &sp, &sl));
    try std.testing.expectEqualStrings("b", sp.?[0..@intCast(sl)]);

    // Stringify and reparse: the mutations survive the round trip.
    try std.testing.expectEqual(OK, sa_toml_stringify(doc, &sp, &sl));
    const out = sp.?[0..@intCast(sl)];
    const doc2 = sa_toml_parse(out.ptr, out.len);
    try std.testing.expect(doc2 != 0);
    defer _ = sa_toml_free(doc2);
    try std.testing.expectEqual(OK, sa_toml_get_i64(doc2, retries.ptr, retries.len, &iv));
    try std.testing.expectEqual(@as(i64, 9), iv);
    try std.testing.expectEqual(ERR_NOT_FOUND, sa_toml_kind(doc2, keep.ptr, keep.len, &kind));
    try std.testing.expectEqual(OK, sa_toml_get_string(doc2, model.ptr, model.len, &sp, &sl));
    try std.testing.expectEqualStrings("new", sp.?[0..@intCast(sl)]);
}

test "toml: stringify escapes, float forms and quoted keys" {
    const doc = sa_toml_new();
    try std.testing.expect(doc != 0);
    defer _ = sa_toml_free(doc);

    const tricky = "tricky";
    const raw = "a\"b\\c\nd\te";
    try std.testing.expectEqual(OK, sa_toml_set_string(doc, tricky.ptr, tricky.len, raw.ptr, raw.len));
    const half = "half";
    try std.testing.expectEqual(OK, sa_toml_set_f64(doc, half.ptr, half.len, 0.5));
    const neg = "neg";
    try std.testing.expectEqual(OK, sa_toml_set_f64(doc, neg.ptr, neg.len, -3.25));
    const spaced = "\"my key\"";
    const v = "v";
    try std.testing.expectEqual(OK, sa_toml_set_string(doc, spaced.ptr, spaced.len, v.ptr, v.len));

    var sp: ?[*]const u8 = null;
    var sl: u64 = 0;
    try std.testing.expectEqual(OK, sa_toml_stringify(doc, &sp, &sl));
    const out = sp.?[0..@intCast(sl)];
    try std.testing.expect(std.mem.indexOf(u8, out, "\"my key\"") != null);

    const doc2 = sa_toml_parse(out.ptr, out.len);
    try std.testing.expect(doc2 != 0);
    defer _ = sa_toml_free(doc2);
    try std.testing.expectEqual(OK, sa_toml_get_string(doc2, tricky.ptr, tricky.len, &sp, &sl));
    try std.testing.expectEqualStrings(raw, sp.?[0..@intCast(sl)]);
    var fv: f64 = 0;
    try std.testing.expectEqual(OK, sa_toml_get_f64(doc2, half.ptr, half.len, &fv));
    try std.testing.expectEqual(@as(f64, 0.5), fv);
    var kind: u32 = 0;
    try std.testing.expectEqual(OK, sa_toml_kind(doc2, neg.ptr, neg.len, &kind));
    try std.testing.expectEqual(KIND_FLOAT, kind);
    try std.testing.expectEqual(OK, sa_toml_get_string(doc2, spaced.ptr, spaced.len, &sp, &sl));
    try std.testing.expectEqualStrings("v", sp.?[0..@intCast(sl)]);
}
