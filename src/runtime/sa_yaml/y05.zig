const std = @import("std");
const sio = @import("sio");
const Document = @import("y01.zig").Document;
const ERR_HANDLE = @import("y01.zig").ERR_HANDLE;
const ERR_INVALID = @import("y01.zig").ERR_INVALID;
const ERR_NOMEM = @import("y01.zig").ERR_NOMEM;
const ERR_NOT_FOUND = @import("y01.zig").ERR_NOT_FOUND;
const KIND_ARRAY = @import("y01.zig").KIND_ARRAY;
const KIND_BOOL = @import("y01.zig").KIND_BOOL;
const KIND_FLOAT = @import("y01.zig").KIND_FLOAT;
const KIND_INTEGER = @import("y01.zig").KIND_INTEGER;
const KIND_NULL = @import("y01.zig").KIND_NULL;
const KIND_STRING = @import("y01.zig").KIND_STRING;
const KIND_TABLE = @import("y01.zig").KIND_TABLE;
const KIND_UNDEFINED = @import("y01.zig").KIND_UNDEFINED;
const OK = @import("y01.zig").OK;
const Table = @import("y01.zig").Table;
const Value = @import("y01.zig").Value;
const clearLastError = @import("y01.zig").clearLastError;
const constSlice = @import("y01.zig").constSlice;
const getDocument = @import("y01.zig").getDocument;
const intSyntax = @import("y01.zig").intSyntax;
const isIndicatorStart = @import("y02.zig").isIndicatorStart;
const isNullSpelling = @import("y01.zig").isNullSpelling;
const newDocument = @import("y01.zig").newDocument;
const newTableValue = @import("y04.zig").newTableValue;
const null_value = @import("y01.zig").null_value;
const parseYamlFloat = @import("y01.zig").parseYamlFloat;
const pushValueAt = @import("y04.zig").pushValueAt;
const registerDocument = @import("y01.zig").registerDocument;
const removeAt = @import("y04.zig").removeAt;
const resolveValue = @import("y04.zig").resolveValue;
const sa_yaml_array_get_i64 = @import("y04.zig").sa_yaml_array_get_i64;
const sa_yaml_array_get_string = @import("y04.zig").sa_yaml_array_get_string;
const sa_yaml_array_len = @import("y04.zig").sa_yaml_array_len;
const sa_yaml_free = @import("y04.zig").sa_yaml_free;
const sa_yaml_get_bool = @import("y04.zig").sa_yaml_get_bool;
const sa_yaml_get_f64 = @import("y04.zig").sa_yaml_get_f64;
const sa_yaml_get_i64 = @import("y04.zig").sa_yaml_get_i64;
const sa_yaml_get_string = @import("y04.zig").sa_yaml_get_string;
const sa_yaml_kind = @import("y04.zig").sa_yaml_kind;
const sa_yaml_last_error = @import("y04.zig").sa_yaml_last_error;
const sa_yaml_parse = @import("y04.zig").sa_yaml_parse;
const sa_yaml_table_len = @import("y04.zig").sa_yaml_table_len;
const setLastError = @import("y01.zig").setLastError;
const setValueAt = @import("y04.zig").setValueAt;
const stringValue = @import("y01.zig").stringValue;

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
pub const EmitError = error{ OutOfMemory, NonFinite };

pub fn appendFmt(out: *std.array_list.Managed(u8), comptime fmt: []const u8, args: anytype) !void {
    const s = try std.fmt.allocPrint(std.heap.page_allocator, fmt, args);
    defer std.heap.page_allocator.free(s);
    try out.appendSlice(s);
}

pub fn writeFloatInto(out: *std.array_list.Managed(u8), v: f64) error{OutOfMemory}!void {
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

pub fn plainSafe(s: []const u8, is_key: bool) bool {
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

pub fn appendYamlString(out: *std.array_list.Managed(u8), s: []const u8, is_key: bool) error{OutOfMemory}!void {
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

pub fn appendYamlScalar(out: *std.array_list.Managed(u8), v: *const Value) error{OutOfMemory}!void {
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

pub fn appendIndent(out: *std.array_list.Managed(u8), indent: usize) error{OutOfMemory}!void {
    for (0..indent) |_| try out.append(' ');
}

pub fn emitYamlMapping(out: *std.array_list.Managed(u8), table: *const Table, indent: usize) error{OutOfMemory}!void {
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

pub fn emitYamlSequence(out: *std.array_list.Managed(u8), arr: []const Value, indent: usize) error{OutOfMemory}!void {
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

pub fn emitYamlDocument(doc: *Document) error{OutOfMemory}![]u8 {
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

pub fn appendJsonString(out: *std.array_list.Managed(u8), s: []const u8) error{OutOfMemory}!void {
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

pub fn emitJsonValue(out: *std.array_list.Managed(u8), v: *const Value) EmitError!void {
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

pub fn emitJsonDocument(doc: *Document) EmitError![]u8 {
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
pub fn expectParse(text: []const u8) !u64 {
    const h = sa_yaml_parse(text.ptr, text.len);
    if (h == 0) {
        std.debug.print("unexpected yaml parse failure: {s}\n", .{lastErrorText()});
        return error.TestUnexpectedResult;
    }
    return h;
}

pub fn lastErrorText() []const u8 {
    var p: ?[*]const u8 = null;
    var l: u64 = 0;
    _ = sa_yaml_last_error(&p, &l);
    if (p) |ptr| return ptr[0..@intCast(l)];
    return "";
}

pub fn getString(h: u64, path: []const u8) ![]const u8 {
    var p: ?[*]const u8 = null;
    var l: u64 = 0;
    try std.testing.expectEqual(OK, sa_yaml_get_string(h, path.ptr, path.len, &p, &l));
    return p.?[0..@intCast(l)];
}

pub fn getI64(h: u64, path: []const u8) !i64 {
    var v: i64 = 0;
    try std.testing.expectEqual(OK, sa_yaml_get_i64(h, path.ptr, path.len, &v));
    return v;
}

pub fn getF64(h: u64, path: []const u8) !f64 {
    var v: f64 = 0;
    try std.testing.expectEqual(OK, sa_yaml_get_f64(h, path.ptr, path.len, &v));
    return v;
}

pub fn getBool(h: u64, path: []const u8) !bool {
    var v: u32 = 0;
    try std.testing.expectEqual(OK, sa_yaml_get_bool(h, path.ptr, path.len, &v));
    return v != 0;
}

pub fn kindOf(h: u64, path: []const u8) !u32 {
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
