const std = @import("std");
const CreatedAs = @import("sa_toml.zig").CreatedAs;
const Document = @import("sa_toml.zig").Document;
const ERR_INVALID = @import("sa_toml.zig").ERR_INVALID;
const ERR_NOMEM = @import("sa_toml.zig").ERR_NOMEM;
const ERR_NOT_FOUND = @import("sa_toml.zig").ERR_NOT_FOUND;
const Entry = @import("sa_toml.zig").Entry;
const KIND_ARRAY = @import("sa_toml.zig").KIND_ARRAY;
const KIND_BOOL = @import("sa_toml.zig").KIND_BOOL;
const KIND_DATETIME = @import("sa_toml.zig").KIND_DATETIME;
const KIND_FLOAT = @import("sa_toml.zig").KIND_FLOAT;
const KIND_INTEGER = @import("sa_toml.zig").KIND_INTEGER;
const KIND_STRING = @import("sa_toml.zig").KIND_STRING;
const KIND_TABLE = @import("sa_toml.zig").KIND_TABLE;
const OK = @import("sa_toml.zig").OK;
const Parser = @import("sa_toml.zig").Parser;
const Table = @import("sa_toml.zig").Table;
const Value = @import("sa_toml.zig").Value;
const freePathSegs = @import("sa_toml.zig").freePathSegs;
const freeTable = @import("sa_toml.zig").freeTable;
const freeValue = @import("sa_toml.zig").freeValue;
const resolveValue = @import("sa_toml.zig").resolveValue;
const splitPath = @import("sa_toml.zig").splitPath;

pub const WriteError = error{ Invalid, NotFound, OutOfMemory };

pub fn bareTable(alloc: std.mem.Allocator, created_as: CreatedAs) WriteError!*Table {
    const t = alloc.create(Table) catch return error.OutOfMemory;
    t.* = .{ .entries = std.array_list.Managed(Entry).init(alloc), .created_as = created_as };
    return t;
}

pub fn touch(doc: *Document) void {
    if (doc.ser_buf) |buf| {
        doc.allocator.free(buf);
        doc.ser_buf = null;
    }
}

pub fn descendMutable(value: *Value) WriteError!*Table {
    if (value.kind == KIND_TABLE) return value.table.?;
    return error.Invalid;
}

pub fn walkParent(doc: *Document, segs: []const []const u8, create: bool) WriteError!*Table {
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

pub fn setValueAt(doc: *Document, path: []const u8, value: Value) i32 {
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

pub fn appendToArray(alloc: std.mem.Allocator, arr_value: *Value, value: Value) WriteError!void {
    var items = std.array_list.Managed(Value).init(alloc);
    defer items.deinit();
    items.appendSlice(arr_value.array) catch return error.OutOfMemory;
    items.append(value) catch return error.OutOfMemory;
    const new_arr = items.toOwnedSlice() catch return error.OutOfMemory;
    alloc.free(arr_value.array);
    arr_value.array = new_arr;
}

pub fn pushValueAt(doc: *Document, path: []const u8, value: Value, is_table: bool) i32 {
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

pub fn removeAtPath(doc: *Document, path: []const u8) i32 {
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

pub fn isBareKey(key: []const u8) bool {
    if (key.len == 0) return false;
    for (key) |c| {
        const ok = (c >= 'A' and c <= 'Z') or (c >= 'a' and c <= 'z') or (c >= '0' and c <= '9') or c == '_' or c == '-';
        if (!ok) return false;
    }
    return true;
}

pub fn writeEscapedInto(out: *std.array_list.Managed(u8), s: []const u8) error{OutOfMemory}!void {
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

pub fn writeKeyInto(out: *std.array_list.Managed(u8), key: []const u8) error{OutOfMemory}!void {
    if (isBareKey(key)) {
        try out.appendSlice(key);
        return;
    }
    try out.append('"');
    try writeEscapedInto(out, key);
    try out.append('"');
}

pub fn writeFloatInto(alloc: std.mem.Allocator, out: *std.array_list.Managed(u8), v: f64) error{OutOfMemory}!void {
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

pub fn writeValueInto(alloc: std.mem.Allocator, out: *std.array_list.Managed(u8), value: Value) error{OutOfMemory}!void {
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

pub fn childPrefix(alloc: std.mem.Allocator, prefix: []const u8, key: []const u8) error{OutOfMemory}![]u8 {
    var seg = std.array_list.Managed(u8).init(alloc);
    defer seg.deinit();
    try writeKeyInto(&seg, key);
    if (prefix.len == 0) return alloc.dupe(u8, seg.items);
    return std.fmt.allocPrint(alloc, "{s}.{s}", .{ prefix, seg.items });
}

pub fn writeTableInto(alloc: std.mem.Allocator, out: *std.array_list.Managed(u8), table: *Table, prefix: []const u8) error{OutOfMemory}!void {
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
