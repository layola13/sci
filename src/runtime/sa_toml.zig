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

test "sa_toml_tests" { std.testing.refAllDecls(@import("sa_toml_test.zig")); }

const std = @import("std");
const sio = @import("sio");

pub const OK: i32 = 0;
pub const ERR_INVALID: i32 = 1;
pub const ERR_HANDLE: i32 = 2;
pub const ERR_NOT_FOUND: i32 = 3;
pub const ERR_NOMEM: i32 = 5;

pub const KIND_STRING: u32 = 1;
pub const KIND_INTEGER: u32 = 2;
pub const KIND_FLOAT: u32 = 3;
pub const KIND_BOOL: u32 = 4;
pub const KIND_DATETIME: u32 = 5;
pub const KIND_ARRAY: u32 = 6;
pub const KIND_TABLE: u32 = 7;

pub const CreatedAs = enum { implicit, dotted, header, inline_table };

pub const Table = struct {
    entries: std.array_list.Managed(Entry),
    created_as: CreatedAs = .implicit,
    header_defined: bool = false,
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
    array_of_tables: bool = false,
    table: ?*Table = null,
};

pub const Document = struct {
    allocator: std.mem.Allocator,
    root: *Table,
    ser_buf: ?[]u8 = null,

    fn deinit(self: *Document) void {
        if (self.ser_buf) |buf| self.allocator.free(buf);
        freeTable(self.allocator, self.root);
        self.allocator.destroy(self);
    }
};

pub fn freeTable(alloc: std.mem.Allocator, table: *Table) void {
    for (table.entries.items) |entry| {
        alloc.free(entry.key);
        freeValue(alloc, entry.value);
    }
    table.entries.deinit();
    alloc.destroy(table);
}

pub fn freeValue(alloc: std.mem.Allocator, value: Value) void {
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

pub fn setLastError(comptime fmt: []const u8, args: anytype) void {
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

pub const ParseError = error{ TomlSyntax, DuplicateKey, OutOfMemory };

pub const Parser = @import("sa_toml_parser.zig").Parser;

// ---------------- dotted-path resolution ----------------

pub fn splitPath(alloc: std.mem.Allocator, path: []const u8) ![][]const u8 {
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

pub fn freePathSegs(alloc: std.mem.Allocator, segs: [][]const u8) void {
    for (segs) |s| alloc.free(s);
    alloc.free(segs);
}

fn findInTable(table: *Table, key: []const u8) ?*Value {
    for (table.entries.items) |*entry| {
        if (std.mem.eql(u8, entry.key, key)) return &entry.value;
    }
    return null;
}

pub fn resolveValue(doc: *Document, path: []const u8) ?*Value {
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

pub const WriteError = @import("sa_toml_write.zig").WriteError;

pub const bareTable = @import("sa_toml_write.zig").bareTable;

// Invalidate the cached serialization after a successful mutation.
pub const touch = @import("sa_toml_write.zig").touch;

// Descend one existing container value during a mutation walk. Only
// tables qualify: arrays are addressed by explicit numeric segments
// (handled by the walks themselves), never by an implicit "most
// recent element", so a path means the same thing to the mutation
// walks as it does to resolveValue on the read side.
pub const descendMutable = @import("sa_toml_write.zig").descendMutable;

// Walk segs as CONTAINERS from the root and return the table they land
// in. With create=false nothing is allocated and a missing segment
// yields error.NotFound (callers read that as "creatable"); with
// create=true missing segments become fresh tables. A numeric segment
// directly after an array key indexes that array, exactly like the
// read side's resolveValue.
pub const walkParent = @import("sa_toml_write.zig").walkParent;

// Install `value` at `path`, taking ownership of it on every outcome
// (it is freed again on failure). The parent chain is validated before
// any table is created, so a rejected set leaves the document
// untouched apart from tables a dry run proved creatable.
pub const setValueAt = @import("sa_toml_write.zig").setValueAt;

pub const appendToArray = @import("sa_toml_write.zig").appendToArray;

// Append `value` to the array at `path`, creating the array when the
// path is still free. is_table marks arrays created by
// sa_toml_array_push_table so they serialize as [[table]] blocks.
pub const pushValueAt = @import("sa_toml_write.zig").pushValueAt;

pub const removeAtPath = @import("sa_toml_write.zig").removeAtPath;

// ---------------- serializer ----------------

pub const isBareKey = @import("sa_toml_write.zig").isBareKey;

pub const writeEscapedInto = @import("sa_toml_write.zig").writeEscapedInto;

pub const writeKeyInto = @import("sa_toml_write.zig").writeKeyInto;

pub const writeFloatInto = @import("sa_toml_write.zig").writeFloatInto;

// Value form: scalars, arrays and tables as they appear after "=" or
// inside an array (tables become inline tables here).
pub const writeValueInto = @import("sa_toml_write.zig").writeValueInto;

pub const childPrefix = @import("sa_toml_write.zig").childPrefix;

// Section form: plain entries first (they belong to the section the
// caller just opened), then subtable sections, then [[array]] blocks.
// prefix is this table's written dotted path ("" for the root).
pub const writeTableInto = @import("sa_toml_write.zig").writeTableInto;

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







