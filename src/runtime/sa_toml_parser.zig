const std = @import("std");
const CreatedAs = @import("sa_toml.zig").CreatedAs;
const Document = @import("sa_toml.zig").Document;
const Entry = @import("sa_toml.zig").Entry;
const KIND_ARRAY = @import("sa_toml.zig").KIND_ARRAY;
const KIND_BOOL = @import("sa_toml.zig").KIND_BOOL;
const KIND_DATETIME = @import("sa_toml.zig").KIND_DATETIME;
const KIND_FLOAT = @import("sa_toml.zig").KIND_FLOAT;
const KIND_INTEGER = @import("sa_toml.zig").KIND_INTEGER;
const KIND_STRING = @import("sa_toml.zig").KIND_STRING;
const KIND_TABLE = @import("sa_toml.zig").KIND_TABLE;
const ParseError = @import("sa_toml.zig").ParseError;
const Table = @import("sa_toml.zig").Table;
const Value = @import("sa_toml.zig").Value;
const freeTable = @import("sa_toml.zig").freeTable;
const freeValue = @import("sa_toml.zig").freeValue;
const setLastError = @import("sa_toml.zig").setLastError;

pub const Parser = struct {
    alloc: std.mem.Allocator,
    src: []const u8,
    pos: usize = 0,

    pub fn lineCol(self: *const Parser) struct { line: usize, col: usize } {
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

    pub fn fail(self: *Parser, err: ParseError, msg: []const u8) ParseError {
        const lc = self.lineCol();
        if (err == error.DuplicateKey) {
            setLastError("toml: duplicate key ({s}) at line {d}, col {d}", .{ msg, lc.line, lc.col });
        } else {
            setLastError("toml: syntax error ({s}) at line {d}, col {d}", .{ msg, lc.line, lc.col });
        }
        return err;
    }

    pub fn peek(self: *const Parser) ?u8 {
        if (self.pos >= self.src.len) return null;
        return self.src[self.pos];
    }

    pub fn skipInlineWs(self: *Parser) void {
        while (self.pos < self.src.len and (self.src[self.pos] == ' ' or self.src[self.pos] == '\t')) self.pos += 1;
    }

    pub fn skipComment(self: *Parser) void {
        if (self.peek() == '#') {
            while (self.pos < self.src.len and self.src[self.pos] != '\n') self.pos += 1;
        }
    }

    // Between statements: whitespace, comments and newlines are all free.
    pub fn skipTrivia(self: *Parser) void {
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
    pub fn skipArrayTrivia(self: *Parser) void {
        self.skipTrivia();
    }

    pub fn expectNewlineOrEof(self: *Parser) ParseError!void {
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

    pub fn parseKeySegment(self: *Parser) ParseError![]const u8 {
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

    pub fn parseDottedKey(self: *Parser) ParseError![][]const u8 {
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

    pub fn freeSegs(self: *Parser, segs: [][]const u8) void {
        for (segs) |s| self.alloc.free(s);
        self.alloc.free(segs);
    }

    pub fn parseEscapeInto(self: *Parser, out: *std.array_list.Managed(u8)) ParseError!void {
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

    pub fn parseBasicString(self: *Parser, multiline: bool) ParseError![]const u8 {
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

    pub fn parseLiteralString(self: *Parser, multiline: bool) ParseError![]const u8 {
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

    pub fn newTable(self: *Parser, created_as: CreatedAs) ParseError!*Table {
        const t = try self.alloc.create(Table);
        t.* = .{ .entries = std.array_list.Managed(Entry).init(self.alloc), .created_as = created_as };
        return t;
    }

    pub fn findEntry(table: *Table, key: []const u8) ?*Entry {
        for (table.entries.items) |*entry| {
            if (std.mem.eql(u8, entry.key, key)) return entry;
        }
        return null;
    }

    // Navigate one segment into a table value that must act as a table:
    // plain tables descend directly; arrays of tables descend into the
    // most recent element.
    pub fn descend(self: *Parser, value: *Value) ParseError!*Table {
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
    pub fn navigate(self: *Parser, root: *Table, segs: []const []const u8, flavor: CreatedAs) ParseError!*Table {
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

    pub fn insertValue(self: *Parser, table: *Table, key: []const u8, value: Value) ParseError!void {
        if (Parser.findEntry(table, key) != null) {
            return self.fail(error.DuplicateKey, key);
        }
        const key_copy = try self.alloc.dupe(u8, key);
        try table.entries.append(.{ .key = key_copy, .value = value });
    }

    pub fn parseBareToken(self: *Parser) []const u8 {
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

pub fn parseDocument(self: *Parser) ParseError!*Document {
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
