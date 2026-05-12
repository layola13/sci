const std = @import("std");
const sig = @import("common/signature.zig");

pub const LayoutFormat = enum {
    text,
    json,
};

pub const LayoutField = struct {
    name: []u8,
    offset: u32,
    size: u32,
    alignment: u32,
    ty: sig.PrimType,
};

pub const Layout = struct {
    name: []u8,
    size: u32,
    max_align: u32,
    fields: []LayoutField,

    pub fn deinit(self: *Layout, allocator: std.mem.Allocator) void {
        for (self.fields) |field| {
            allocator.free(field.name);
        }
        allocator.free(self.fields);
        allocator.free(self.name);
        self.* = undefined;
    }
};

pub const LayoutError = error{
    InvalidTarget,
    InvalidFieldList,
    InvalidFieldName,
    DuplicateField,
    UnsupportedType,
    OutOfMemory,
};

fn isIdentStart(c: u8) bool {
    return std.ascii.isAlphabetic(c) or c == '_';
}

fn isIdentChar(c: u8) bool {
    return std.ascii.isAlphanumeric(c) or c == '_';
}

fn roundUp(value: u32, alignment: u32) u32 {
    if (alignment <= 1) return value;
    const rem = value % alignment;
    if (rem == 0) return value;
    return value + (alignment - rem);
}

const FieldInfo = struct {
    size: u32,
    alignment: u32,
};

fn fieldInfo(ty: sig.PrimType, target_bits: u16) LayoutError!FieldInfo {
    return switch (ty) {
        .void => LayoutError.UnsupportedType,
        .i1 => .{ .size = 1, .alignment = 1 },
        .i8, .u8 => .{ .size = 1, .alignment = 1 },
        .i16, .u16 => .{ .size = 2, .alignment = 2 },
        .i32, .u32, .f32 => .{ .size = 4, .alignment = 4 },
        .i64, .u64, .f64 => .{ .size = 8, .alignment = 8 },
        .ptr => switch (target_bits) {
            32 => .{ .size = 4, .alignment = 4 },
            64 => .{ .size = 8, .alignment = 8 },
            else => LayoutError.InvalidTarget,
        },
    };
}

fn writeJsonString(writer: anytype, text: []const u8) !void {
    try writer.writeByte('"');
    for (text) |c| {
        switch (c) {
            '"' => try writer.writeAll("\\\""),
            '\\' => try writer.writeAll("\\\\"),
            '\n' => try writer.writeAll("\\n"),
            '\r' => try writer.writeAll("\\r"),
            '\t' => try writer.writeAll("\\t"),
            else => {
                if (c < 0x20) {
                    try writer.print("\\u{X:0>4}", .{c});
                } else {
                    try writer.writeByte(c);
                }
            },
        }
    }
    try writer.writeByte('"');
}

pub fn parseTargetBits(text: []const u8) LayoutError!u16 {
    const trimmed = std.mem.trim(u8, text, " \t\r");
    if (std.mem.eql(u8, trimmed, "32")) return 32;
    if (std.mem.eql(u8, trimmed, "64")) return 64;
    return LayoutError.InvalidTarget;
}

pub fn compute(
    allocator: std.mem.Allocator,
    name: []const u8,
    fields_text: []const u8,
    target_bits: u16,
) LayoutError!Layout {
    const layout_name = try allocator.dupe(u8, std.mem.trim(u8, name, " \t\r"));
    errdefer allocator.free(layout_name);
    if (layout_name.len == 0 or !isIdentStart(layout_name[0])) return LayoutError.InvalidFieldName;
    for (layout_name[1..]) |c| {
        if (!isIdentChar(c)) return LayoutError.InvalidFieldName;
    }

    var fields = std.ArrayList(LayoutField).init(allocator);
    errdefer {
        for (fields.items) |field| allocator.free(field.name);
        fields.deinit();
    }

    var seen = std.StringHashMap(void).init(allocator);
    defer seen.deinit();

    const trimmed_fields = std.mem.trim(u8, fields_text, " \t\r");
    var offset: u32 = 0;
    var max_align: u32 = 1;

    if (trimmed_fields.len != 0) {
        var iterator = std.mem.splitScalar(u8, trimmed_fields, ',');
        while (iterator.next()) |fragment| {
            const trimmed = std.mem.trim(u8, fragment, " \t\r");
            if (trimmed.len == 0) return LayoutError.InvalidFieldList;

            const colon = std.mem.indexOfScalar(u8, trimmed, ':') orelse return LayoutError.InvalidFieldList;
            const field_name = std.mem.trim(u8, trimmed[0..colon], " \t\r");
            const ty_text = std.mem.trim(u8, trimmed[colon + 1 ..], " \t\r");
            if (field_name.len == 0 or ty_text.len == 0) return LayoutError.InvalidFieldList;
            if (!isIdentStart(field_name[0])) return LayoutError.InvalidFieldName;
            for (field_name[1..]) |c| {
                if (!isIdentChar(c)) return LayoutError.InvalidFieldName;
            }
            if (seen.contains(field_name)) return LayoutError.DuplicateField;
            try seen.put(field_name, {});

            const ty = sig.parsePrimType(ty_text) catch |err| switch (err) {
                sig.ParseError.UnsupportedType => return LayoutError.UnsupportedType,
                else => return LayoutError.InvalidFieldList,
            };
            const info = try fieldInfo(ty, target_bits);
            const aligned_offset = roundUp(offset, info.alignment);
            const name_copy = try allocator.dupe(u8, field_name);
            errdefer allocator.free(name_copy);

            try fields.append(.{
                .name = name_copy,
                .offset = aligned_offset,
                .size = info.size,
                .alignment = info.alignment,
                .ty = ty,
            });
            offset = aligned_offset + info.size;
            if (info.alignment > max_align) max_align = info.alignment;
        }
    }

    const size = roundUp(offset, max_align);
    return .{
        .name = layout_name,
        .size = size,
        .max_align = max_align,
        .fields = try fields.toOwnedSlice(),
    };
}

pub fn writeText(writer: anytype, layout: Layout) !void {
    try writer.print("#def {s}_SIZE  = {d}\n", .{ layout.name, layout.size });
    var cursor: u32 = 0;
    for (layout.fields, 0..) |field, idx| {
        if (field.offset > cursor) {
            try writer.print("// {d} bytes padding\n", .{field.offset - cursor});
        }
        try writer.print("#def {s}_{s} = +{d}\n", .{ layout.name, field.name, field.offset });
        cursor = field.offset + field.size;
        if (idx + 1 == layout.fields.len and layout.size > cursor) {
            try writer.print("// {d} bytes tail padding\n", .{layout.size - cursor});
        }
    }
}

pub fn writeJson(writer: anytype, layout: Layout) !void {
    try writer.writeByte('{');
    try writer.writeAll("\"name\":");
    try writeJsonString(writer, layout.name);
    try writer.writeAll(",\"size\":");
    try writer.print("{d}", .{layout.size});
    try writer.writeAll(",\"fields\":[");
    for (layout.fields, 0..) |field, idx| {
        if (idx != 0) try writer.writeByte(',');
        try writer.writeByte('{');
        try writer.writeAll("\"name\":");
        try writeJsonString(writer, field.name);
        try writer.writeAll(",\"offset\":");
        try writer.print("{d}", .{field.offset});
        try writer.writeAll(",\"size\":");
        try writer.print("{d}", .{field.size});
        try writer.writeAll(",\"ty\":");
        try writeJsonString(writer, sig.primTypeName(field.ty));
        try writer.writeByte('}');
    }
    try writer.writeAll("]}");
}

test "layout text output rounds offsets and sizes" {
    var layout = try compute(
        std.testing.allocator,
        "Entity",
        "id:u32, pos_x:f64, pos_y:f64, hp:i32",
        64,
    );
    defer layout.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(u32, 32), layout.size);
    try std.testing.expectEqual(@as(usize, 4), layout.fields.len);
    try std.testing.expectEqualStrings("Entity", layout.name);
    try std.testing.expectEqualStrings("id", layout.fields[0].name);
    try std.testing.expectEqual(@as(u32, 0), layout.fields[0].offset);
    try std.testing.expectEqual(@as(u32, 8), layout.fields[1].offset);
    try std.testing.expectEqual(@as(u32, 16), layout.fields[2].offset);
    try std.testing.expectEqual(@as(u32, 24), layout.fields[3].offset);

    var buf = std.ArrayList(u8).init(std.testing.allocator);
    defer buf.deinit();
    try writeText(buf.writer(), layout);
    try std.testing.expectEqualStrings(
        "#def Entity_SIZE  = 32\n#def Entity_id = +0\n// 4 bytes padding\n#def Entity_pos_x = +8\n#def Entity_pos_y = +16\n#def Entity_hp = +24\n// 4 bytes tail padding\n",
        buf.items,
    );
}

test "layout json output and 32-bit ptr alignment" {
    var layout = try compute(std.testing.allocator, "Pair", "head:ptr, count:u32", 32);
    defer layout.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(u32, 8), layout.size);
    try std.testing.expectEqual(@as(u32, 0), layout.fields[0].offset);
    try std.testing.expectEqual(@as(u32, 4), layout.fields[1].offset);
    try std.testing.expectEqual(@as(u32, 4), layout.fields[0].size);
    try std.testing.expectEqual(@as(u32, 4), layout.fields[0].alignment);

    var buf = std.ArrayList(u8).init(std.testing.allocator);
    defer buf.deinit();
    try writeJson(buf.writer(), layout);
    try std.testing.expectEqualStrings(
        "{\"name\":\"Pair\",\"size\":8,\"fields\":[{\"name\":\"head\",\"offset\":0,\"size\":4,\"ty\":\"ptr\"},{\"name\":\"count\",\"offset\":4,\"size\":4,\"ty\":\"u32\"}]}",
        buf.items,
    );
}

test "layout rejects invalid field types and empty structs" {
    var empty = try compute(std.testing.allocator, "Empty", "   ", 64);
    defer empty.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(u32, 0), empty.size);
    try std.testing.expectEqual(@as(usize, 0), empty.fields.len);

    try std.testing.expectError(LayoutError.UnsupportedType, compute(std.testing.allocator, "Bad", "x:v128", 64));
    try std.testing.expectError(LayoutError.InvalidFieldName, compute(std.testing.allocator, "123Bad", "", 64));
}
