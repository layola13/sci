const std = @import("std");
const sio = @import("sio");
const Entry = @import("y01.zig").Entry;
const Fail = @import("y01.zig").Fail;
const KIND_ARRAY = @import("y01.zig").KIND_ARRAY;
const KIND_BOOL = @import("y01.zig").KIND_BOOL;
const KIND_FLOAT = @import("y01.zig").KIND_FLOAT;
const KIND_INTEGER = @import("y01.zig").KIND_INTEGER;
const KIND_TABLE = @import("y01.zig").KIND_TABLE;
const Table = @import("y01.zig").Table;
const TextCursor = @import("y01.zig").TextCursor;
const Value = @import("y01.zig").Value;
const failAt = @import("y01.zig").failAt;
const failDuplicateKey = @import("y01.zig").failDuplicateKey;
const failUnsupported = @import("y01.zig").failUnsupported;
const floatFromInt = @import("y01.zig").floatFromInt;
const intSyntax = @import("y01.zig").intSyntax;
const isNullSpelling = @import("y01.zig").isNullSpelling;
const null_value = @import("y01.zig").null_value;
const parseDoubleQuoted = @import("y01.zig").parseDoubleQuoted;
const parseIntExact = @import("y01.zig").parseIntExact;
const parseSingleQuoted = @import("y01.zig").parseSingleQuoted;
const parseYamlFloat = @import("y01.zig").parseYamlFloat;
const rtrimWs = @import("y01.zig").rtrimWs;
const setLastError = @import("y01.zig").setLastError;
const stringValue = @import("y01.zig").stringValue;
const trimWs = @import("y01.zig").trimWs;

/// Resolve a plain scalar's text to a typed value, using the
/// JSON-aligned inference rules documented at the top of this file.
pub fn resolvePlainScalar(alloc: std.mem.Allocator, text: []const u8) Fail!Value {
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
pub fn isIndicatorStart(c: u8) bool {
    return switch (c) {
        '!', '&', '*', '[', ']', '{', '}', ',', '#', '|', '>', '@', '%', '`' => true,
        else => false,
    };
}

pub const KeyHit = struct { key: []const u8, colon: usize };

/// Detect a mapping key at the start of a block line's content.
/// Returns the key text and the index of the ':' separator, or null
/// when the line does not start a mapping entry.
pub fn scanBlockKey(alloc: std.mem.Allocator, content: []const u8, line_no: usize) Fail!?KeyHit {
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
pub const Line = struct { no: usize, raw: []const u8, col0: usize = 0 };

pub const DocRange = struct { start: usize, end: usize };

pub const SplitResult = struct {
    lines: []Line,
    ranges: []DocRange,
    alloc: std.mem.Allocator,

    fn deinit(self: *SplitResult) void {
        self.alloc.free(self.lines);
        self.alloc.free(self.ranges);
    }
};

pub fn isBlankRaw(raw: []const u8) bool {
    for (raw) |c| {
        if (c != ' ' and c != '\t') return false;
    }
    return true;
}

pub fn isCommentRaw(raw: []const u8) bool {
    var i: usize = 0;
    while (i < raw.len and (raw[i] == ' ' or raw[i] == '\t')) i += 1;
    return i < raw.len and raw[i] == '#';
}

/// Marker text after "---" / "..." on the same line, if the line is a
/// document marker at column 0. Returns the rest (untrimmed) or null.
pub fn markerRest(raw: []const u8, marker: []const u8) ?[]const u8 {
    if (!std.mem.startsWith(u8, raw, marker)) return null;
    if (raw.len == marker.len) return "";
    const c = raw[marker.len];
    if (c != ' ' and c != '\t') return null;
    return raw[marker.len + 1 ..];
}

/// Split the source into physical lines and document ranges.
/// Document markers are recognized at column 0 before any parsing
/// (subset simplification, see the module doc).
pub fn splitDocuments(alloc: std.mem.Allocator, src: []const u8) Fail!SplitResult {
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
pub const MapPart = union(enum) { entry: Entry, merge: Value };

pub const MapBuilder = struct {
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

pub fn findInEntries(entries: []const Entry, key: []const u8) ?*const Value {
    for (entries) |*e| {
        if (std.mem.eql(u8, e.key, key)) return &e.value;
    }
    return null;
}

// ---------------- block parser ----------------
pub const LineView = struct {
    no: usize,
    ind: usize,
    content: []const u8,
    col: usize, // 1-based column of content start
    physical: bool,
};

pub fn lineIndent(line: Line) Fail!usize {
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

pub fn isSeqStart(content: []const u8) bool {
    return content.len == 1 and content[0] == '-' or
        (content.len > 1 and content[0] == '-' and content[1] == ' ');
}

pub fn isAnchorChar(c: u8) bool {
    return (c >= 'a' and c <= 'z') or (c >= 'A' and c <= 'Z') or
        (c >= '0' and c <= '9') or c == '_' or c == '-';
}

pub fn validAnchorName(name: []const u8) bool {
    if (name.len == 0) return false;
    for (name) |c| {
        if (!isAnchorChar(c)) return false;
    }
    return true;
}

pub fn failUnknownAlias(name: []const u8, line: usize, col: usize) Fail {
    setLastError("yaml: unknown alias ({s}) at line {d}, col {d}", .{ name, line, col });
    return error.ParseFail;
}

pub const Prefix = struct { anchor: ?[]const u8, rest: []const u8, col: usize };

/// Strip leading anchor (&name) prefixes from a node-start text.
/// Any explicit tag is an UNSUPPORTED error, per the subset rulings.
pub fn stripPrefixes(text: []const u8, line_no: usize, col: usize, existing: ?[]const u8) Fail!Prefix {
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
