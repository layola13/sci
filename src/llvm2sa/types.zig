// LLVM type queries (sizes, alignments, struct/array layout).
const std = @import("std");
const trim = @import("text.zig").trim;
const splitTopLevelComma = @import("text.zig").splitTopLevelComma;

pub var active_type_defs: ?*std.StringHashMap([]const u8) = null;

pub fn typeTokenToSa(token: []const u8) ?[]const u8 {
    const t = trim(token);
    if (t.len == 0) return null;
    if (std.mem.eql(u8, t, "void")) return "void";
    if (std.mem.eql(u8, t, "i1")) return "i1";
    if (std.mem.eql(u8, t, "i8")) return "i8";
    if (std.mem.eql(u8, t, "i16")) return "i16";
    if (std.mem.eql(u8, t, "i32")) return "i32";
    if (std.mem.eql(u8, t, "i64")) return "i64";
    if (std.mem.eql(u8, t, "float")) return "f32";
    if (std.mem.eql(u8, t, "double")) return "f64";
    if (std.mem.eql(u8, t, "ptr")) return "ptr";
    if (std.mem.endsWith(u8, t, "*")) return "ptr";
    if (std.mem.startsWith(u8, t, "%") and std.mem.endsWith(u8, t, "*")) return "ptr";
    return null;
}

pub fn typeBytes(type_text: []const u8) ?u64 {
    const t = trim(type_text);
    if (std.mem.eql(u8, t, "i1") or std.mem.eql(u8, t, "i8")) return 1;
    if (std.mem.eql(u8, t, "i16")) return 2;
    if (std.mem.eql(u8, t, "i32") or std.mem.eql(u8, t, "float")) return 4;
    if (std.mem.eql(u8, t, "i64") or std.mem.eql(u8, t, "double") or std.mem.eql(u8, t, "ptr") or std.mem.endsWith(u8, t, "*")) return 8;

    if (t.len >= 5 and t[0] == '[' and t[t.len - 1] == ']') {
        const body = trim(t[1 .. t.len - 1]);
        const x_idx = std.mem.indexOf(u8, body, " x ") orelse return null;
        const count = std.fmt.parseInt(u64, trim(body[0..x_idx]), 10) catch return null;
        const elem = typeBytes(body[x_idx + 3 ..]) orelse return null;
        return std.math.mul(u64, count, elem) catch null;
    }

    if (t.len >= 2 and t[0] == '<' and t[t.len - 1] == '>') {
        const body = trim(t[1 .. t.len - 1]);
        const x_idx = std.mem.indexOf(u8, body, " x ") orelse return null;
        const count = std.fmt.parseInt(u64, trim(body[0..x_idx]), 10) catch return null;
        const elem = typeBytes(body[x_idx + 3 ..]) orelse return null;
        return std.math.mul(u64, count, elem) catch null;
    }

    if (t.len > 0 and t[0] == '%') {
        const body = if (active_type_defs) |defs| defs.get(t) else null;
        const fields_text = body orelse return 8;
        if (std.mem.eql(u8, fields_text, "opaque")) return 8;
        const packed_struct = fields_text.len >= 2 and fields_text[0] == '<' and fields_text[1] == '{';
        const open: usize = if (packed_struct) 1 else 0;
        if (fields_text.len < open + 2 or fields_text[open] != '{' or fields_text[fields_text.len - 1] != '}') return null;
        const fields = splitTopLevelComma(std.heap.page_allocator, fields_text[open + 1 .. fields_text.len - 1]) catch return null;
        defer std.heap.page_allocator.free(fields);
        var size: u64 = 0;
        var alignment: u64 = 1;
        for (fields) |field| {
            const field_align = typeAlignment(field) orelse return null;
            const field_size = typeBytes(field) orelse return null;
            alignment = @max(alignment, field_align);
            if (!packed_struct) size = std.mem.alignForward(u64, size, field_align);
            size = std.math.add(u64, size, field_size) catch return null;
        }
        if (!packed_struct) size = std.mem.alignForward(u64, size, alignment);
        return size;
    }

    return null;
}

pub fn typeAlignment(type_text: []const u8) ?u64 {
    const t = trim(type_text);
    if (std.mem.eql(u8, t, "i1") or std.mem.eql(u8, t, "i8")) return 1;
    if (std.mem.eql(u8, t, "i16")) return 2;
    if (std.mem.eql(u8, t, "i32") or std.mem.eql(u8, t, "float")) return 4;
    if (std.mem.eql(u8, t, "i64") or std.mem.eql(u8, t, "double") or std.mem.eql(u8, t, "ptr") or std.mem.endsWith(u8, t, "*")) return 8;
    if (t.len >= 5 and t[0] == '[' and t[t.len - 1] == ']') return typeAlignment(arrayElementType(t).?);
    if (t.len >= 2 and t[0] == '<' and t[t.len - 1] == '>') return typeAlignment(trim(t[1 .. t.len - 1][std.mem.indexOf(u8, t[1 .. t.len - 1], " x ").? + 3 ..]));
    if (t.len > 0 and t[0] == '%') {
        const body = if (active_type_defs) |defs| defs.get(t) else null;
        const fields_text = body orelse return 8;
        if (std.mem.eql(u8, fields_text, "opaque")) return 8;
        const packed_struct = fields_text.len >= 2 and fields_text[0] == '<' and fields_text[1] == '{';
        const open: usize = if (packed_struct) 1 else 0;
        if (fields_text.len < open + 2 or fields_text[open] != '{' or fields_text[fields_text.len - 1] != '}') return null;
        const fields = splitTopLevelComma(std.heap.page_allocator, fields_text[open + 1 .. fields_text.len - 1]) catch return null;
        defer std.heap.page_allocator.free(fields);
        var alignment: u64 = 1;
        for (fields) |field| alignment = @max(alignment, typeAlignment(field) orelse return null);
        return alignment;
    }
    return null;
}

pub fn structFieldType(type_text: []const u8, field_index: u64) ?[]const u8 {
    const t = trim(type_text);
    if (t.len == 0 or t[0] != '%') return null;
    const fields_text = (if (active_type_defs) |defs| defs.get(t) else null) orelse return null;
    if (std.mem.eql(u8, fields_text, "opaque")) return null;
    const packed_struct = fields_text.len >= 2 and fields_text[0] == '<' and fields_text[1] == '{';
    const open: usize = if (packed_struct) 1 else 0;
    if (fields_text.len < open + 2 or fields_text[open] != '{' or fields_text[fields_text.len - 1] != '}') return null;
    const fields = splitTopLevelComma(std.heap.page_allocator, fields_text[open + 1 .. fields_text.len - 1]) catch return null;
    defer std.heap.page_allocator.free(fields);
    if (field_index >= fields.len) return null;
    return fields[field_index];
}

pub fn structFieldOffset(type_text: []const u8, field_index: u64) ?u64 {
    const t = trim(type_text);
    if (t.len == 0 or t[0] != '%') return null;
    const fields_text = (if (active_type_defs) |defs| defs.get(t) else null) orelse return null;
    if (std.mem.eql(u8, fields_text, "opaque")) return null;
    const packed_struct = fields_text.len >= 2 and fields_text[0] == '<' and fields_text[1] == '{';
    const open: usize = if (packed_struct) 1 else 0;
    if (fields_text.len < open + 2 or fields_text[open] != '{' or fields_text[fields_text.len - 1] != '}') return null;
    const fields = splitTopLevelComma(std.heap.page_allocator, fields_text[open + 1 .. fields_text.len - 1]) catch return null;
    defer std.heap.page_allocator.free(fields);
    if (field_index >= fields.len) return null;
    var offset: u64 = 0;
    for (fields[0..field_index]) |field| {
        const field_align = typeAlignment(field) orelse return null;
        if (!packed_struct) offset = std.mem.alignForward(u64, offset, field_align);
        offset = std.math.add(u64, offset, typeBytes(field) orelse return null) catch return null;
    }
    return offset;
}

pub fn arrayElementType(type_text: []const u8) ?[]const u8 {
    const t = trim(type_text);
    if (t.len < 5 or t[0] != '[' or t[t.len - 1] != ']') return null;
    const body = trim(t[1 .. t.len - 1]);
    const x_idx = std.mem.indexOf(u8, body, " x ") orelse return null;
    return trim(body[x_idx + 3 ..]);
}

pub fn parseLlvmInteger(text: []const u8) ?i128 {
    const t = trim(text);
    if (std.fmt.parseInt(i128, t, 10)) |value| return value else |_| {}
    if (std.fmt.parseInt(i128, t, 0)) |value| return value else |_| {}
    return null;
}

pub fn arrayBoundFromType(type_text: []const u8) ?u64 {
    const t = trim(type_text);
    if (t.len < 5 or t[0] != '[' or t[t.len - 1] != ']') return null;
    const body = trim(t[1 .. t.len - 1]);
    const x_idx = std.mem.indexOf(u8, body, " x ") orelse return null;
    return std.fmt.parseInt(u64, trim(body[0..x_idx]), 10) catch null;
}

pub fn firstTypeToken(fragment: []const u8) ?[]const u8 {
    var parts = std.mem.tokenizeAny(u8, fragment, " \t\r\n");
    while (parts.next()) |part| {
        if (typeTokenToSa(part) != null) return part;
        if (std.mem.startsWith(u8, part, "[") or std.mem.startsWith(u8, part, "{")) return null;
    }
    return null;
}

pub fn returnTypeFromPrefix(prefix: []const u8) ![]const u8 {
    var last: ?[]const u8 = null;
    var parts = std.mem.tokenizeAny(u8, prefix, " \t\r\n");
    while (parts.next()) |part| {
        if (typeTokenToSa(part) != null) last = part;
    }
    const token = last orelse return error.UnsupportedInstruction;
    return typeTokenToSa(token).?;
}
