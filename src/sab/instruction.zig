const std = @import("std");
const upstream = @import("../common/upstream_loc.zig");
const inst = instruction;
const sig = signature;

const freeDecodedInstructionMetadata = @import("read_const_value.zig").freeDecodedInstructionMetadata;
const readSymbolName = @import("read_const_value.zig").readSymbolName;

pub const instruction = @import("../common/instruction.zig");
pub const signature = @import("../common/signature.zig");
pub const const_decl = @import("../common/const_decl.zig");
pub const magic = "SAB\x00";
pub const version_major: u8 = 4;
pub const version_minor: u8 = 0;

/// Magic of the SAB fragment container defined in sab_fragment.zig. A
/// fragment is a compiler-internal building block (an unchecked-encoded
/// function body plus its register contract), never a program: every
/// module decode entry point rejects it with error.SabFragmentNotAProgram
/// so a bare fragment can never be silently built, run, or checked as a
/// whole program.
pub const fragment_magic = "SAFRAG\x00";

pub fn isFragmentBytes(bytes: []const u8) bool {
    return bytes.len >= fragment_magic.len and std.mem.eql(u8, bytes[0..fragment_magic.len], fragment_magic);
}

pub const SectionId = enum(u64) {
    symbol_pool = 1,
    function_sigs = 2,
    const_decls = 3,
    instructions = 4,
};

pub const Error = error{
    InvalidSabMagic,
    SabFragmentNotAProgram,
    UnsupportedSabVersion,
    MissingInstructionSection,
    TruncatedSab,
    Leb128Overflow,
    InvalidTag,
    OutOfMemory,
};

pub const Module = struct {
    symbols: []const []const u8,
    owns_symbol_text: bool = true,
    function_sigs: []sig.FunctionSig,
    const_decls: []const_decl.ConstDecl,
    instructions: []inst.Instruction,
    owned_text: [][]const u8,

    pub fn deinit(self: *Module, allocator: std.mem.Allocator) void {
        if (self.owns_symbol_text) {
            for (self.symbols) |name| allocator.free(name);
        }
        allocator.free(self.symbols);
        for (self.function_sigs) |*item| item.deinit(allocator);
        allocator.free(self.function_sigs);
        for (self.const_decls) |*decl| decl.deinit(allocator);
        allocator.free(self.const_decls);
        for (self.owned_text) |text| allocator.free(text);
        allocator.free(self.owned_text);
        freeDecodedInstructionMetadata(allocator, self.instructions);
        allocator.free(self.instructions);
        self.* = undefined;
    }
};

pub const Cursor = struct {
    bytes: []const u8,
    index: usize = 0,

    pub fn readByte(self: *Cursor) Error!u8 {
        if (self.index >= self.bytes.len) return error.TruncatedSab;
        const byte = self.bytes[self.index];
        self.index += 1;
        return byte;
    }

    pub fn readSlice(self: *Cursor, len: usize) Error![]const u8 {
        if (len > self.bytes.len - self.index) return error.TruncatedSab;
        const start = self.index;
        self.index += len;
        return self.bytes[start..self.index];
    }
};

pub fn encodeUleb128(writer: *std.Io.Writer, value: u64) !void {
    var remaining = value;
    while (true) {
        var byte: u8 = @intCast(remaining & 0x7f);
        remaining >>= 7;
        if (remaining != 0) byte |= 0x80;
        try writer.writeByte(byte);
        if (remaining == 0) break;
    }
}

pub fn decodeUleb128(cursor: *Cursor) Error!u64 {
    var result: u64 = 0;
    var shift: u6 = 0;
    while (true) {
        const byte = try cursor.readByte();
        result |= @as(u64, byte & 0x7f) << shift;
        if ((byte & 0x80) == 0) return result;
        if (shift >= 63) return error.Leb128Overflow;
        shift += 7;
    }
}

pub fn encodeSleb128(writer: *std.Io.Writer, value: i64) !void {
    var remaining = value;
    var more = true;
    while (more) {
        var byte: u8 = @intCast(@as(u64, @bitCast(remaining)) & 0x7f);
        const sign_bit_set = (byte & 0x40) != 0;
        remaining >>= 7;
        more = !((remaining == 0 and !sign_bit_set) or (remaining == -1 and sign_bit_set));
        if (more) byte |= 0x80;
        try writer.writeByte(byte);
    }
}

pub fn decodeSleb128(cursor: *Cursor) Error!i64 {
    var result: i64 = 0;
    var shift: u6 = 0;
    var byte: u8 = 0;
    while (true) {
        byte = try cursor.readByte();
        result |= @as(i64, byte & 0x7f) << shift;
        shift += 7;
        if ((byte & 0x80) == 0) break;
        if (shift >= 63) return error.Leb128Overflow;
    }
    if (shift < 64 and (byte & 0x40) != 0) {
        result |= -(@as(i64, 1) << shift);
    }
    return result;
}

pub fn writeSection(writer: *std.Io.Writer, id: SectionId, payload: []const u8) !void {
    try encodeUleb128(writer, @intFromEnum(id));
    try encodeUleb128(writer, payload.len);
    try writer.writeAll(payload);
}

pub fn writeStringPool(writer: *std.Io.Writer, symbols: []const []const u8) !void {
    try encodeUleb128(writer, symbols.len);
    for (symbols) |name| {
        try encodeUleb128(writer, name.len);
        try writer.writeAll(name);
    }
}

pub fn readStringPool(allocator: std.mem.Allocator, payload: []const u8) ![]const []const u8 {
    var cursor = Cursor{ .bytes = payload };
    const count = try decodeUleb128(&cursor);
    if (count > std.math.maxInt(usize)) return error.Leb128Overflow;
    const symbols = try allocator.alloc([]const u8, @intCast(count));
    errdefer allocator.free(symbols);
    var initialized: usize = 0;
    errdefer for (symbols[0..initialized]) |name| allocator.free(name);
    for (symbols) |*slot| {
        const len = try decodeUleb128(&cursor);
        if (len > std.math.maxInt(usize)) return error.Leb128Overflow;
        slot.* = try allocator.dupe(u8, try cursor.readSlice(@intCast(len)));
        initialized += 1;
    }
    return symbols;
}

pub fn readStringPoolBorrowed(allocator: std.mem.Allocator, payload: []const u8) ![]const []const u8 {
    var cursor = Cursor{ .bytes = payload };
    const count = try decodeUleb128(&cursor);
    if (count > std.math.maxInt(usize)) return error.Leb128Overflow;
    const symbols = try allocator.alloc([]const u8, @intCast(count));
    errdefer allocator.free(symbols);
    for (symbols) |*slot| {
        const len = try decodeUleb128(&cursor);
        if (len > std.math.maxInt(usize)) return error.Leb128Overflow;
        slot.* = try cursor.readSlice(@intCast(len));
    }
    return symbols;
}

pub fn writeOptionalEnum(writer: *std.Io.Writer, value: anytype) !void {
    if (value) |v| {
        try writer.writeByte(1);
        try writer.writeByte(@intFromEnum(v));
    } else {
        try writer.writeByte(0);
    }
}

pub fn readOptionalEnum(comptime T: type, cursor: *Cursor) !?T {
    const present = try cursor.readByte();
    if (present == 0) return null;
    if (present != 1) return error.InvalidTag;
    return std.enums.fromInt(T, try cursor.readByte()) orelse error.InvalidTag;
}

pub fn writeOperand(writer: *std.Io.Writer, operand: inst.Operand, pool: *std.StringHashMap(u32)) !void {
    switch (operand) {
        .none => try writer.writeByte(0),
        .reg => |v| {
            try writer.writeByte(1);
            try encodeUleb128(writer, v);
        },
        .symbol => |v| {
            try writer.writeByte(2);
            try encodeUleb128(writer, v);
        },
        .label => |v| {
            try writer.writeByte(3);
            try encodeUleb128(writer, v);
        },
        .func => |v| {
            try writer.writeByte(4);
            try encodeUleb128(writer, v);
        },
        .imm_i64 => |v| {
            try writer.writeByte(5);
            try encodeSleb128(writer, v);
        },
        .imm_u64 => |v| {
            try writer.writeByte(6);
            try encodeUleb128(writer, v);
        },
        .imm_int => |v| {
            try writer.writeByte(7);
            try encodeSleb128(writer, v);
        },
        .imm_float => |v| {
            try writer.writeByte(8);
            try writer.writeInt(u64, @bitCast(v), .little);
        },
        .op_code => |v| {
            try writer.writeByte(9);
            try writer.writeByte(@intFromEnum(v));
        },
        .cap_prefix => |v| {
            try writer.writeByte(10);
            try writer.writeByte(@intFromEnum(v));
        },
        .offset => |v| {
            try writer.writeByte(11);
            try encodeUleb128(writer, v);
        },
        .ty => |v| {
            try writer.writeByte(12);
            try encodeUleb128(writer, v);
        },
        .text => |v| {
            try writer.writeByte(13);
            try encodeUleb128(writer, pool.get(v) orelse return error.InvalidTag);
        },
        .native_text => |v| {
            try writer.writeByte(14);
            try encodeUleb128(writer, pool.get(v) orelse return error.InvalidTag);
        },
    }
}

pub fn readPooledText(allocator: std.mem.Allocator, symbols: []const []const u8, owned_text: *std.array_list.Managed([]const u8), id: u64) ![]const u8 {
    if (id > std.math.maxInt(usize)) return error.Leb128Overflow;
    const idx: usize = @intCast(id);
    if (idx >= symbols.len) return error.InvalidTag;
    const text = try allocator.dupe(u8, symbols[idx]);
    errdefer allocator.free(text);
    try owned_text.append(text);
    return text;
}

pub fn poolId(pool: *std.StringHashMap(u32), text: []const u8) !u32 {
    return pool.get(text) orelse error.InvalidTag;
}

pub fn writeOptionalPoolText(writer: *std.Io.Writer, pool: *std.StringHashMap(u32), text: ?[]const u8) !void {
    if (text) |value| {
        try writer.writeByte(1);
        try encodeUleb128(writer, try poolId(pool, value));
    } else {
        try writer.writeByte(0);
    }
}

pub fn writeOptionalHash(writer: *std.Io.Writer, hash: ?[32]u8) !void {
    if (hash) |value| {
        try writer.writeByte(1);
        try writer.writeAll(value[0..]);
    } else {
        try writer.writeByte(0);
    }
}

pub fn writeOptionalUpstreamLoc(writer: *std.Io.Writer, pool: *std.StringHashMap(u32), loc: ?upstream.UpstreamLoc) !void {
    if (loc) |value| {
        try writer.writeByte(1);
        try encodeUleb128(writer, try poolId(pool, value.file));
        try encodeUleb128(writer, value.line);
        try encodeUleb128(writer, value.col);
    } else {
        try writer.writeByte(0);
    }
}

pub fn readOptionalPooledText(allocator: std.mem.Allocator, symbols: []const []const u8, owned_text: *std.array_list.Managed([]const u8), cursor: *Cursor) !?[]const u8 {
    const present = try cursor.readByte();
    if (present == 0) return null;
    if (present != 1) return error.InvalidTag;
    return try readPooledText(allocator, symbols, owned_text, try decodeUleb128(cursor));
}

pub fn readOptionalAllocText(allocator: std.mem.Allocator, symbols: []const []const u8, cursor: *Cursor) !?[]u8 {
    const present = try cursor.readByte();
    if (present == 0) return null;
    if (present != 1) return error.InvalidTag;
    return try readSymbolName(allocator, symbols, try decodeUleb128(cursor));
}

pub fn skipOptionalPoolText(cursor: *Cursor) !void {
    const present = try cursor.readByte();
    if (present == 0) return;
    if (present != 1) return error.InvalidTag;
    _ = try decodeUleb128(cursor);
}

pub fn readOptionalHash(cursor: *Cursor) !?[32]u8 {
    const present = try cursor.readByte();
    if (present == 0) return null;
    if (present != 1) return error.InvalidTag;
    var out: [32]u8 = undefined;
    @memcpy(out[0..], try cursor.readSlice(32));
    return out;
}

pub fn readOptionalPooledUpstreamLoc(allocator: std.mem.Allocator, symbols: []const []const u8, owned_text: *std.array_list.Managed([]const u8), cursor: *Cursor) !?upstream.UpstreamLoc {
    const present = try cursor.readByte();
    if (present == 0) return null;
    if (present != 1) return error.InvalidTag;
    return .{
        .file = try readPooledText(allocator, symbols, owned_text, try decodeUleb128(cursor)),
        .line = @intCast(try decodeUleb128(cursor)),
        .col = @intCast(try decodeUleb128(cursor)),
    };
}

pub fn readOptionalAllocUpstreamLoc(allocator: std.mem.Allocator, symbols: []const []const u8, cursor: *Cursor) !?upstream.UpstreamLoc {
    const present = try cursor.readByte();
    if (present == 0) return null;
    if (present != 1) return error.InvalidTag;
    const file = try readSymbolName(allocator, symbols, try decodeUleb128(cursor));
    errdefer allocator.free(file);
    return .{
        .file = file,
        .line = @intCast(try decodeUleb128(cursor)),
        .col = @intCast(try decodeUleb128(cursor)),
    };
}

pub fn skipOptionalUpstreamLoc(cursor: *Cursor) !void {
    const present = try cursor.readByte();
    if (present == 0) return;
    if (present != 1) return error.InvalidTag;
    _ = try decodeUleb128(cursor);
    _ = try decodeUleb128(cursor);
    _ = try decodeUleb128(cursor);
}

pub fn readOperand(allocator: std.mem.Allocator, symbols: []const []const u8, owned_text: *std.array_list.Managed([]const u8), cursor: *Cursor) !inst.Operand {
    return switch (try cursor.readByte()) {
        0 => .{ .none = {} },
        1 => .{ .reg = @intCast(try decodeUleb128(cursor)) },
        2 => .{ .symbol = @intCast(try decodeUleb128(cursor)) },
        3 => .{ .label = @intCast(try decodeUleb128(cursor)) },
        4 => .{ .func = @intCast(try decodeUleb128(cursor)) },
        5 => .{ .imm_i64 = try decodeSleb128(cursor) },
        6 => .{ .imm_u64 = try decodeUleb128(cursor) },
        7 => .{ .imm_int = try decodeSleb128(cursor) },
        8 => blk: {
            const raw = try cursor.readSlice(8);
            const bits = std.mem.readInt(u64, raw[0..8], .little);
            break :blk .{ .imm_float = @bitCast(bits) };
        },
        9 => .{ .op_code = (std.enums.fromInt(inst.OpCode, try cursor.readByte()) orelse return error.InvalidTag) },
        10 => .{ .cap_prefix = (std.enums.fromInt(inst.CapPrefix, try cursor.readByte()) orelse return error.InvalidTag) },
        11 => .{ .offset = @intCast(try decodeUleb128(cursor)) },
        12 => .{ .ty = @intCast(try decodeUleb128(cursor)) },
        13 => .{ .text = try readPooledText(allocator, symbols, owned_text, try decodeUleb128(cursor)) },
        14 => .{ .native_text = try readPooledText(allocator, symbols, owned_text, try decodeUleb128(cursor)) },
        else => error.InvalidTag,
    };
}

pub fn operandRegName(symbols: []const []const u8, operand: inst.Operand) ![]const u8 {
    if (operand != .reg) return error.InvalidTag;
    const idx: usize = @intCast(operand.reg);
    if (idx >= symbols.len) return error.InvalidTag;
    return symbols[idx];
}

pub fn synthesizeRawText(
    allocator: std.mem.Allocator,
    symbols: []const []const u8,
    owned_text: *std.array_list.Managed([]const u8),
    item: *inst.Instruction,
) !void {
    const raw = switch (item.kind) {
        .call, .call_indirect => blk: {
            // C2 sab_carried_indirect_sig: re-attach the carried
            // fn-pointer signature (operands[3]) to the synthesised
            // raw text so referee parsing sees it exactly as in the
            // SA text form.
            const carried_suffix = if (item.kind == .call_indirect and item.operands[3] == .text and item.operands[3].text.len != 0)
                try std.fmt.allocPrint(allocator, " : {s}", .{item.operands[3].text})
            else
                try allocator.dupe(u8, "");
            defer allocator.free(carried_suffix);
            if (item.operands[0] == .reg) {
                const body = if (item.operands[1] == .text) item.operands[1].text else return;
                break :blk try std.fmt.allocPrint(
                    allocator,
                    "{s} = {s} {s}{s}",
                    .{ try operandRegName(symbols, item.operands[0]), if (item.kind == .call) "call" else "call_indirect", body, carried_suffix },
                );
            }
            const body = if (item.operands[0] == .text)
                item.operands[0].text
            else if (item.operands[1] == .text)
                item.operands[1].text
            else
                return;
            break :blk try std.fmt.allocPrint(
                allocator,
                "{s} {s}{s}",
                .{ if (item.kind == .call) "call" else "call_indirect", body, carried_suffix },
            );
        },
        .panic, .panic_msg => blk: {
            const arg = switch (item.operands[0]) {
                .text => |text| text,
                .reg => try operandRegName(symbols, item.operands[0]),
                else => "1",
            };
            if (arg.len >= 2 and arg[0] == '(' and arg[arg.len - 1] == ')') {
                break :blk try std.fmt.allocPrint(
                    allocator,
                    "{s}{s}",
                    .{ if (item.kind == .panic) "panic" else "panic_msg", arg },
                );
            }
            break :blk try std.fmt.allocPrint(
                allocator,
                "{s}({s})",
                .{ if (item.kind == .panic) "panic" else "panic_msg", arg },
            );
        },
        else => return,
    };
    errdefer allocator.free(raw);
    try owned_text.append(raw);
    item.raw_text = raw;
}

pub fn writeInstructions(writer: *std.Io.Writer, instructions: []const inst.Instruction, pool: *std.StringHashMap(u32)) !void {
    try encodeUleb128(writer, instructions.len);
    for (instructions) |item| {
        try writer.writeByte(@intFromEnum(item.kind));
        try encodeUleb128(writer, item.source_line);
        try encodeUleb128(writer, item.expanded_line);
        try writeOptionalEnum(writer, item.op_kind);
        for (item.operands) |operand| try writeOperand(writer, operand, pool);
        try writer.writeByte(if (item.atomic_value_ty != null) 1 else 0);
        if (item.atomic_value_ty) |ty| try encodeUleb128(writer, ty);
        try writeOptionalEnum(writer, item.atomic_ordering);
        try writeOptionalEnum(writer, item.atomic_second_ordering);
        try writeOptionalEnum(writer, item.atomic_rmw_op);
        try writeOptionalPoolText(writer, pool, item.atomic_expected_text);
        try writeOptionalPoolText(writer, pool, item.atomic_new_text);
        try encodeUleb128(writer, item.native_reg_names.len);
        for (item.native_reg_names) |name| try encodeUleb128(writer, try poolId(pool, name));
        try writeOptionalPoolText(writer, pool, item.package_identity);
        try writeOptionalHash(writer, item.package_source_sha256);
        try writeOptionalUpstreamLoc(writer, pool, item.upstream_loc);
    }
}

pub fn addPoolText(pool_items: *std.array_list.Managed([]const u8), pool: *std.StringHashMap(u32), text: []const u8) !void {
    if (pool.contains(text)) return;
    const id: u32 = @intCast(pool_items.items.len);
    try pool_items.append(text);
    try pool.put(text, id);
}

pub fn collectConstValueSymbols(pool_items: *std.array_list.Managed([]const u8), pool: *std.StringHashMap(u32), value: const_decl.ConstValue) !void {
    switch (value) {
        .hex, .utf8, .repeat => {},
        .struct_ => |literal| {
            for (literal.fields) |field| {
                try addPoolText(pool_items, pool, field.name);
                try collectConstValueSymbols(pool_items, pool, field.value);
            }
        },
        .vtable => |literal| {
            for (literal.slots) |slot| {
                try addPoolText(pool_items, pool, slot.name);
                try addPoolText(pool_items, pool, slot.func_name);
            }
        },
    }
}

pub fn writeBytesLiteral(writer: *std.Io.Writer, literal: const_decl.BytesLiteral) !void {
    try encodeUleb128(writer, literal.bytes.len);
    try writer.writeAll(literal.bytes);
    if (literal.repeat_count) |count| {
        try writer.writeByte(1);
        try encodeUleb128(writer, count);
        try writer.writeByte(literal.repeat_byte orelse 0);
    } else {
        try writer.writeByte(0);
    }
}

pub fn readBytesLiteral(allocator: std.mem.Allocator, cursor: *Cursor, kind: const_decl.ConstLiteralKind) !const_decl.BytesLiteral {
    const len = try decodeUleb128(cursor);
    if (len > std.math.maxInt(usize)) return error.Leb128Overflow;
    const bytes = try allocator.dupe(u8, try cursor.readSlice(@intCast(len)));
    errdefer allocator.free(bytes);
    const repeat_present = try cursor.readByte();
    if (repeat_present == 0) {
        return .{ .kind = kind, .bytes = bytes };
    }
    if (repeat_present != 1) return error.InvalidTag;
    return .{
        .kind = kind,
        .bytes = bytes,
        .repeat_count = try decodeUleb128(cursor),
        .repeat_byte = try cursor.readByte(),
    };
}

pub fn writeConstValue(writer: *std.Io.Writer, value: const_decl.ConstValue, pool: *std.StringHashMap(u32)) !void {
    const tag = std.meta.activeTag(value);
    try writer.writeByte(@intFromEnum(tag));
    switch (value) {
        .hex, .utf8, .repeat => |literal| try writeBytesLiteral(writer, literal),
        .struct_ => |literal| {
            try encodeUleb128(writer, literal.fields.len);
            for (literal.fields) |field| {
                try encodeUleb128(writer, try poolId(pool, field.name));
                try encodeUleb128(writer, field.size);
                try writeConstValue(writer, field.value, pool);
            }
        },
        .vtable => |literal| {
            try encodeUleb128(writer, literal.slots.len);
            for (literal.slots) |slot| {
                try encodeUleb128(writer, try poolId(pool, slot.name));
                try encodeUleb128(writer, try poolId(pool, slot.func_name));
            }
        },
    }
}
