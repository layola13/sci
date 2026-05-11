const std = @import("std");
const instr = @import("instruction.zig");
const upstream = @import("upstream_loc.zig");

pub const ParseError = error{
    OutOfMemory,
    InvalidFunctionSig,
    UnsupportedType,
};

pub const PrimType = enum(u8) {
    void,
    i8,
    i16,
    i32,
    i64,
    u8,
    u16,
    u32,
    u64,
    f32,
    f64,
    ptr,
};

pub const ParamSpec = struct {
    name: []const u8,
    ty: PrimType,
    cap: instr.CapPrefix,
};

pub const FunctionSig = struct {
    id: u32,
    name: []const u8,
    params: []const ParamSpec,
    kind: FunctionKind,
    return_cap: ?instr.CapPrefix,
    return_ty: PrimType,
    return_fallible: bool = false,
    entry_inst_idx: u32,
    is_ffi_wrapper: bool,
    upstream_file: ?[]const u8 = null,
    upstream_loc: ?upstream.UpstreamLoc = null,
    param_ids: []const u32 = &.{},

    pub fn deinit(self: *FunctionSig, allocator: std.mem.Allocator) void {
        for (self.params) |param| {
            allocator.free(param.name);
        }
        allocator.free(self.params);
        if (self.param_ids.len != 0) allocator.free(self.param_ids);
        if (self.upstream_file) |file| allocator.free(file);
        allocator.free(self.name);
        self.* = undefined;
    }
};

pub const FunctionKind = enum(u8) {
    normal,
    ffi_wrapper,
    external,
    exported,
};

const HeaderSpec = struct {
    prefix: []const u8,
    require_colon: bool,
};

fn isIdentStart(c: u8) bool {
    return std.ascii.isAlphabetic(c) or c == '_';
}

fn isIdentChar(c: u8) bool {
    return std.ascii.isAlphanumeric(c) or c == '_';
}

pub fn parsePrimType(text: []const u8) ParseError!PrimType {
    const trimmed = std.mem.trim(u8, text, " \t\r");
    inline for ([_]struct { name: []const u8, ty: PrimType }{
        .{ .name = "void", .ty = .void },
        .{ .name = "i8", .ty = .i8 },
        .{ .name = "i16", .ty = .i16 },
        .{ .name = "i32", .ty = .i32 },
        .{ .name = "i64", .ty = .i64 },
        .{ .name = "u8", .ty = .u8 },
        .{ .name = "u16", .ty = .u16 },
        .{ .name = "u32", .ty = .u32 },
        .{ .name = "u64", .ty = .u64 },
        .{ .name = "f32", .ty = .f32 },
        .{ .name = "f64", .ty = .f64 },
        .{ .name = "ptr", .ty = .ptr },
    }) |item| {
        if (std.mem.eql(u8, trimmed, item.name)) return item.ty;
    }
    return ParseError.UnsupportedType;
}

pub fn primTypeName(ty: PrimType) []const u8 {
    return switch (ty) {
        .void => "void",
        .i8 => "i8",
        .i16 => "i16",
        .i32 => "i32",
        .i64 => "i64",
        .u8 => "u8",
        .u16 => "u16",
        .u32 => "u32",
        .u64 => "u64",
        .f32 => "f32",
        .f64 => "f64",
        .ptr => "ptr",
    };
}

pub fn primTypeBits(ty: PrimType) u32 {
    return switch (ty) {
        .void => 0,
        .i8, .u8 => 8,
        .i16, .u16 => 16,
        .i32, .u32, .f32 => 32,
        .i64, .u64, .f64, .ptr => 64,
    };
}

pub fn primTypeBytes(ty: PrimType) u32 {
    return switch (ty) {
        .void => 0,
        else => @max(@as(u32, 1), primTypeBits(ty) / 8),
    };
}

pub fn primTypeFromTag(tag: u32) ?PrimType {
    if (tag > @intFromEnum(PrimType.ptr)) return null;
    return @enumFromInt(tag);
}

fn parseOptionalCap(text: []const u8) struct { cap: ?instr.CapPrefix, rest: []const u8 } {
    const trimmed = std.mem.trim(u8, text, " \t\r");
    if (trimmed.len == 0) return .{ .cap = null, .rest = trimmed };
    return switch (trimmed[0]) {
        '&' => .{ .cap = .borrow, .rest = std.mem.trim(u8, trimmed[1..], " \t\r") },
        '^' => .{ .cap = .move, .rest = std.mem.trim(u8, trimmed[1..], " \t\r") },
        '*' => .{ .cap = .raw, .rest = std.mem.trim(u8, trimmed[1..], " \t\r") },
        else => .{ .cap = null, .rest = trimmed },
    };
}

fn parseParam(allocator: std.mem.Allocator, fragment: []const u8) ParseError!ParamSpec {
    const trimmed = std.mem.trim(u8, fragment, " \t\r");
    if (trimmed.len == 0) return ParseError.InvalidFunctionSig;

    const cap_split = parseOptionalCap(trimmed);
    const body = cap_split.rest;
    const colon = std.mem.indexOfScalar(u8, body, ':') orelse return ParseError.InvalidFunctionSig;
    const name = std.mem.trim(u8, body[0..colon], " \t\r");
    const ty_text = std.mem.trim(u8, body[colon + 1 ..], " \t\r");
    if (name.len == 0 or ty_text.len == 0) return ParseError.InvalidFunctionSig;
    if (!isIdentStart(name[0])) return ParseError.InvalidFunctionSig;
    for (name[1..]) |c| {
        if (!isIdentChar(c)) return ParseError.InvalidFunctionSig;
    }

    return .{
        .name = try allocator.dupe(u8, name),
        .ty = try parsePrimType(ty_text),
        .cap = cap_split.cap orelse .by_value,
    };
}

pub fn parseFunctionSig(
    allocator: std.mem.Allocator,
    text: []const u8,
    id: u32,
    entry_inst_idx: u32,
) ParseError!FunctionSig {
    const trimmed = std.mem.trim(u8, text, " \t\r");
    if (trimmed.len < 3 or trimmed[0] != '@' or trimmed[trimmed.len - 1] != ':') {
        return ParseError.InvalidFunctionSig;
    }

    const body = trimmed[1 .. trimmed.len - 1];
    const open = std.mem.indexOfScalar(u8, body, '(') orelse return ParseError.InvalidFunctionSig;
    const close = std.mem.lastIndexOfScalar(u8, body, ')') orelse return ParseError.InvalidFunctionSig;
    if (close <= open) return ParseError.InvalidFunctionSig;

    const name_text = std.mem.trim(u8, body[0..open], " \t\r");
    if (name_text.len == 0 or !isIdentStart(name_text[0])) return ParseError.InvalidFunctionSig;
    for (name_text[1..]) |c| {
        if (!isIdentChar(c)) return ParseError.InvalidFunctionSig;
    }

    const params_text = std.mem.trim(u8, body[open + 1 .. close], " \t\r");
    var tail = std.mem.trim(u8, body[close + 1 ..], " \t\r");

    var return_cap: ?instr.CapPrefix = null;
    var return_ty: PrimType = .void;
    var return_fallible = false;
    if (tail.len != 0) {
        if (!std.mem.startsWith(u8, tail, "->")) return ParseError.InvalidFunctionSig;
        var return_text = std.mem.trim(u8, tail[2..], " \t\r");
        if (return_text.len == 0) return ParseError.InvalidFunctionSig;
        if (return_text[return_text.len - 1] == '!') {
            return_fallible = true;
            return_text = std.mem.trimRight(u8, return_text[0 .. return_text.len - 1], " \t\r");
            if (return_text.len == 0) return ParseError.InvalidFunctionSig;
        }
        const cap_split = parseOptionalCap(return_text);
        return_cap = cap_split.cap;
        const ty_text = std.mem.trimLeft(u8, cap_split.rest, " \t\r");
        if (ty_text.len != 0 and (ty_text[0] == '*' or ty_text[0] == '&' or ty_text[0] == '^')) {
            return_ty = .ptr;
        } else {
            return_ty = try parsePrimType(ty_text);
        }
    }

    var param_list = std.ArrayList(ParamSpec).init(allocator);
    errdefer {
        for (param_list.items) |param| allocator.free(param.name);
        param_list.deinit();
    }

    if (params_text.len != 0) {
        var iterator = std.mem.splitScalar(u8, params_text, ',');
        while (iterator.next()) |fragment| {
            try param_list.append(try parseParam(allocator, fragment));
        }
    }

    const name = try allocator.dupe(u8, name_text);
    errdefer allocator.free(name);
    const params = try param_list.toOwnedSlice();

    return .{
        .id = id,
        .name = name,
        .params = params,
        .kind = .normal,
        .return_cap = return_cap,
        .return_ty = return_ty,
        .return_fallible = return_fallible,
        .entry_inst_idx = entry_inst_idx,
        .is_ffi_wrapper = false,
        .upstream_file = null,
        .upstream_loc = null,
    };
}

pub fn parseFunctionHeader(
    allocator: std.mem.Allocator,
    text: []const u8,
    id: u32,
    entry_inst_idx: u32,
    kind: FunctionKind,
) ParseError!FunctionSig {
    const trimmed = std.mem.trim(u8, text, " \t\r");
    if (trimmed.len == 0) return ParseError.InvalidFunctionSig;

    const spec: HeaderSpec = switch (kind) {
        .normal => .{ .prefix = "@", .require_colon = true },
        .ffi_wrapper => .{ .prefix = "@ffi_wrapper", .require_colon = true },
        .external => .{ .prefix = "@extern", .require_colon = false },
        .exported => .{ .prefix = "@export", .require_colon = true },
    };

    if (!std.mem.startsWith(u8, trimmed, spec.prefix)) return ParseError.InvalidFunctionSig;
    if (spec.require_colon and trimmed[trimmed.len - 1] != ':') return ParseError.InvalidFunctionSig;

    const body = if (spec.require_colon)
        trimmed[spec.prefix.len .. trimmed.len - 1]
    else
        std.mem.trimRight(u8, trimmed[spec.prefix.len..], " :\t\r");

    const after_name = std.mem.trimLeft(u8, body, " \t");
    const open = std.mem.indexOfScalar(u8, after_name, '(') orelse return ParseError.InvalidFunctionSig;
    const close = std.mem.lastIndexOfScalar(u8, after_name, ')') orelse return ParseError.InvalidFunctionSig;
    if (close <= open) return ParseError.InvalidFunctionSig;

    const name_text = std.mem.trim(u8, after_name[0..open], " \t\r");
    if (name_text.len == 0 or !isIdentStart(name_text[0])) return ParseError.InvalidFunctionSig;
    for (name_text[1..]) |c| {
        if (!isIdentChar(c)) return ParseError.InvalidFunctionSig;
    }

    const params_text = std.mem.trim(u8, after_name[open + 1 .. close], " \t\r");
    var tail = std.mem.trim(u8, after_name[close + 1 ..], " \t\r");

    var return_cap: ?instr.CapPrefix = null;
    var return_ty: PrimType = .void;
    var return_fallible = false;
    if (tail.len != 0) {
        if (!std.mem.startsWith(u8, tail, "->")) return ParseError.InvalidFunctionSig;
        var return_text = std.mem.trim(u8, tail[2..], " \t\r");
        if (return_text.len == 0) return ParseError.InvalidFunctionSig;
        if (return_text[return_text.len - 1] == '!') {
            return_fallible = true;
            return_text = std.mem.trimRight(u8, return_text[0 .. return_text.len - 1], " \t\r");
            if (return_text.len == 0) return ParseError.InvalidFunctionSig;
        }
        const cap_split = parseOptionalCap(return_text);
        return_cap = cap_split.cap;
        const ty_text = std.mem.trimLeft(u8, cap_split.rest, " \t\r");
        if (ty_text.len != 0 and (ty_text[0] == '*' or ty_text[0] == '&' or ty_text[0] == '^')) {
            return_ty = .ptr;
        } else {
            return_ty = try parsePrimType(ty_text);
        }
    }

    var param_list = std.ArrayList(ParamSpec).init(allocator);
    errdefer {
        for (param_list.items) |param| allocator.free(param.name);
        param_list.deinit();
    }

    if (params_text.len != 0) {
        var iterator = std.mem.splitScalar(u8, params_text, ',');
        while (iterator.next()) |fragment| {
            try param_list.append(try parseParam(allocator, fragment));
        }
    }

    const name = try allocator.dupe(u8, name_text);
    errdefer allocator.free(name);
    const params = try param_list.toOwnedSlice();

    return .{
        .id = id,
        .name = name,
        .params = params,
        .kind = kind,
        .return_cap = return_cap,
        .return_ty = return_ty,
        .return_fallible = return_fallible,
        .entry_inst_idx = entry_inst_idx,
        .is_ffi_wrapper = kind == .ffi_wrapper,
        .upstream_file = null,
        .upstream_loc = null,
    };
}

test "function signature carries prefix and params" {
    const params = [_]ParamSpec{
        .{ .name = "x", .ty = .i32, .cap = .borrow },
    };
    const sig = FunctionSig{
        .id = 1,
        .name = "main",
        .params = params[0..],
        .kind = .normal,
        .return_cap = .move,
        .return_ty = .i32,
        .return_fallible = true,
        .entry_inst_idx = 0,
        .is_ffi_wrapper = false,
        .upstream_file = "main.rs",
        .upstream_loc = .{ .file = "main.rs", .line = 1, .col = 1 },
        .param_ids = &.{},
    };
    try std.testing.expectEqual(@as(u32, 1), sig.id);
    try std.testing.expectEqualStrings("main", sig.name);
    try std.testing.expectEqual(@as(usize, 1), sig.params.len);
    try std.testing.expectEqual(instr.CapPrefix.move, sig.return_cap.?);
    try std.testing.expect(sig.return_fallible);
}

test "parse function signature with params and return cap" {
    var sig = try parseFunctionSig(std.testing.allocator, "@sum(^lhs: i32, rhs: i32) -> ^i32!:", 7, 3);
    defer sig.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(u32, 7), sig.id);
    try std.testing.expectEqualStrings("sum", sig.name);
    try std.testing.expectEqual(@as(usize, 2), sig.params.len);
    try std.testing.expectEqual(instr.CapPrefix.move, sig.params[0].cap);
    try std.testing.expectEqual(PrimType.i32, sig.params[0].ty);
    try std.testing.expectEqual(instr.CapPrefix.by_value, sig.params[1].cap);
    try std.testing.expectEqual(instr.CapPrefix.move, sig.return_cap.?);
    try std.testing.expectEqual(PrimType.i32, sig.return_ty);
    try std.testing.expect(sig.return_fallible);
}
