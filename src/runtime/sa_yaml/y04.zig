const std = @import("std");
const sio = @import("sio");
const Document = @import("y01.zig").Document;
const ERR_HANDLE = @import("y01.zig").ERR_HANDLE;
const ERR_INVALID = @import("y01.zig").ERR_INVALID;
const ERR_NOMEM = @import("y01.zig").ERR_NOMEM;
const ERR_NOT_FOUND = @import("y01.zig").ERR_NOT_FOUND;
const Entry = @import("y01.zig").Entry;
const Fail = @import("y01.zig").Fail;
const KIND_ARRAY = @import("y01.zig").KIND_ARRAY;
const KIND_BOOL = @import("y01.zig").KIND_BOOL;
const KIND_FLOAT = @import("y01.zig").KIND_FLOAT;
const KIND_INTEGER = @import("y01.zig").KIND_INTEGER;
const KIND_STRING = @import("y01.zig").KIND_STRING;
const KIND_TABLE = @import("y01.zig").KIND_TABLE;
const KIND_UNDEFINED = @import("y01.zig").KIND_UNDEFINED;
const MapBuilder = @import("y02.zig").MapBuilder;
const MapPart = @import("y02.zig").MapPart;
const OK = @import("y01.zig").OK;
const Parser = @import("y03.zig").Parser;
const Table = @import("y01.zig").Table;
const TextCursor = @import("y01.zig").TextCursor;
const Value = @import("y01.zig").Value;
const clearLastError = @import("y01.zig").clearLastError;
const constSlice = @import("y01.zig").constSlice;
const deepClone = @import("y01.zig").deepClone;
const failAt = @import("y01.zig").failAt;
const failUnknownAlias = @import("y02.zig").failUnknownAlias;
const failUnsupported = @import("y01.zig").failUnsupported;
const findInEntries = @import("y02.zig").findInEntries;
const foldFlowPlain = @import("y03.zig").foldFlowPlain;
const getDocument = @import("y01.zig").getDocument;
const isAnchorChar = @import("y02.zig").isAnchorChar;
const last_error_buf = @import("y01.zig").last_error_buf;
const newDocument = @import("y01.zig").newDocument;
const null_value = @import("y01.zig").null_value;
const parseDoubleQuoted = @import("y01.zig").parseDoubleQuoted;
const parseSingleQuoted = @import("y01.zig").parseSingleQuoted;
const registerDocument = @import("y01.zig").registerDocument;
const removeDocument = @import("y01.zig").removeDocument;
const resolvePlainScalar = @import("y02.zig").resolvePlainScalar;
const setLastError = @import("y01.zig").setLastError;
const splitDocuments = @import("y02.zig").splitDocuments;
const stringValue = @import("y01.zig").stringValue;
const y01 = @import("y01.zig");

pub const FlowParser = struct {
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
pub fn parseIndex(seg: []const u8) ?usize {
    if (seg.len == 0) return null;
    for (seg) |c| {
        if (c < '0' or c > '9') return null;
    }
    return std.fmt.parseInt(usize, seg, 10) catch null;
}

pub fn resolveValue(root: *const Value, path: []const u8) ?*const Value {
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

pub fn findEntryMut(table: *Table, key: []const u8) ?*Entry {
    for (table.entries.items) |*e| {
        if (std.mem.eql(u8, e.key, key)) return e;
    }
    return null;
}

pub const WalkError = error{ NotFound, Invalid, OutOfMemory };

/// Descend through `segs` without creating anything.
pub fn descendMut(doc: *Document, segs: []const []const u8) WalkError!*Value {
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
pub fn walkParentTable(doc: *Document, segs: []const []const u8) WalkError!*Table {
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

pub fn newTableValue(doc: *Document) !Value {
    const table = try doc.alloc().create(Table);
    table.* = .{ .entries = std.array_list.Managed(Entry).init(doc.alloc()) };
    return .{ .kind = KIND_TABLE, .table = table };
}

pub fn splitPathAlloc(alloc: std.mem.Allocator, path: []const u8) ![][]const u8 {
    var segs = std.array_list.Managed([]const u8).init(alloc);
    var it = std.mem.splitScalar(u8, path, '.');
    while (it.next()) |seg| try segs.append(seg);
    return segs.toOwnedSlice();
}

pub fn walkStatus(err: WalkError) i32 {
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
pub fn setValueAt(doc: *Document, path: []const u8, value: Value) i32 {
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

pub fn pushValueAt(doc: *Document, path: []const u8, value: Value) i32 {
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

pub fn removeAt(doc: *Document, path: []const u8) i32 {
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
pub fn parseToDocument(input: []const u8, index: ?usize) ?*Document {
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
        if (err == error.OutOfMemory and y01.last_error_len == 0) setLastError("yaml: out of memory", .{});
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
    if (y01.last_error_len == 0) {
        ptr_slot.* = null;
        len_slot.* = 0;
        return ERR_NOT_FOUND;
    }
    ptr_slot.* = last_error_buf[0..last_error_len].ptr;
    len_slot.* = @intCast(y01.last_error_len);
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
