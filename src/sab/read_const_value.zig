const std = @import("std");
const upstream = @import("../common/upstream_loc.zig");
const inst = instruction;
const sig = signature;

const Cursor = @import("instruction.zig").Cursor;
const Module = @import("instruction.zig").Module;
const SectionId = @import("instruction.zig").SectionId;
const addPoolText = @import("instruction.zig").addPoolText;
const collectConstValueSymbols = @import("instruction.zig").collectConstValueSymbols;
const const_decl = @import("instruction.zig").const_decl;
const decodeUleb128 = @import("instruction.zig").decodeUleb128;
const encodeUleb128 = @import("instruction.zig").encodeUleb128;
const instruction = @import("instruction.zig").instruction;
const isFragmentBytes = @import("instruction.zig").isFragmentBytes;
const magic = @import("instruction.zig").magic;
const poolId = @import("instruction.zig").poolId;
const readBytesLiteral = @import("instruction.zig").readBytesLiteral;
const readOperand = @import("instruction.zig").readOperand;
const readOptionalAllocText = @import("instruction.zig").readOptionalAllocText;
const readOptionalAllocUpstreamLoc = @import("instruction.zig").readOptionalAllocUpstreamLoc;
const readOptionalEnum = @import("instruction.zig").readOptionalEnum;
const readOptionalHash = @import("instruction.zig").readOptionalHash;
const readOptionalPooledText = @import("instruction.zig").readOptionalPooledText;
const readPooledText = @import("instruction.zig").readPooledText;
const readStringPool = @import("instruction.zig").readStringPool;
const readStringPoolBorrowed = @import("instruction.zig").readStringPoolBorrowed;
const signature = @import("instruction.zig").signature;
const skipOptionalPoolText = @import("instruction.zig").skipOptionalPoolText;
const skipOptionalUpstreamLoc = @import("instruction.zig").skipOptionalUpstreamLoc;
const synthesizeRawText = @import("instruction.zig").synthesizeRawText;
const version_major = @import("instruction.zig").version_major;
const version_minor = @import("instruction.zig").version_minor;
const writeConstValue = @import("instruction.zig").writeConstValue;
const writeDisasmInstruction = @import("write_disasm_instruction.zig").writeDisasmInstruction;
const writeInstructions = @import("instruction.zig").writeInstructions;
const writeOptionalPoolText = @import("instruction.zig").writeOptionalPoolText;
const writeOptionalUpstreamLoc = @import("instruction.zig").writeOptionalUpstreamLoc;
const writeSection = @import("instruction.zig").writeSection;
const writeStringPool = @import("instruction.zig").writeStringPool;

pub fn readConstValue(allocator: std.mem.Allocator, symbols: []const []const u8, cursor: *Cursor) !const_decl.ConstValue {
    const tag = (std.enums.fromInt(const_decl.ConstLiteralKind, try cursor.readByte()) orelse return error.InvalidTag);
    return switch (tag) {
        .hex => .{ .hex = try readBytesLiteral(allocator, cursor, .hex) },
        .utf8 => .{ .utf8 = try readBytesLiteral(allocator, cursor, .utf8) },
        .repeat => .{ .repeat = try readBytesLiteral(allocator, cursor, .repeat) },
        .struct_ => blk: {
            const count = try decodeUleb128(cursor);
            if (count > std.math.maxInt(usize)) return error.Leb128Overflow;
            const fields = try allocator.alloc(const_decl.StructField, @intCast(count));
            errdefer allocator.free(fields);
            var initialized: usize = 0;
            errdefer for (fields[0..initialized]) |*field| field.deinit(allocator);
            for (fields) |*field| {
                field.* = .{
                    .name = try readSymbolName(allocator, symbols, try decodeUleb128(cursor)),
                    .size = try decodeUleb128(cursor),
                    .value = try readConstValue(allocator, symbols, cursor),
                };
                initialized += 1;
            }
            break :blk .{ .struct_ = .{ .fields = fields } };
        },
        .vtable => blk: {
            const count = try decodeUleb128(cursor);
            if (count > std.math.maxInt(usize)) return error.Leb128Overflow;
            const slots = try allocator.alloc(const_decl.VTableSlot, @intCast(count));
            errdefer allocator.free(slots);
            var initialized: usize = 0;
            errdefer for (slots[0..initialized]) |*slot| slot.deinit(allocator);
            for (slots) |*slot| {
                slot.* = .{
                    .name = try readSymbolName(allocator, symbols, try decodeUleb128(cursor)),
                    .func_name = try readSymbolName(allocator, symbols, try decodeUleb128(cursor)),
                };
                initialized += 1;
            }
            break :blk .{ .vtable = .{ .slots = slots } };
        },
    };
}

pub fn writeConstDecls(writer: *std.Io.Writer, const_decls: []const const_decl.ConstDecl, pool: *std.StringHashMap(u32)) !void {
    try encodeUleb128(writer, const_decls.len);
    for (const_decls) |decl| {
        try encodeUleb128(writer, decl.source_line);
        try encodeUleb128(writer, decl.expanded_line);
        try encodeUleb128(writer, try poolId(pool, decl.name));
        try encodeUleb128(writer, try poolId(pool, decl.literal_text));
        try writeOptionalUpstreamLoc(writer, pool, decl.upstream_loc);
        try writeConstValue(writer, decl.value, pool);
    }
}

pub fn readConstDecls(allocator: std.mem.Allocator, symbols: []const []const u8, payload: []const u8, has_metadata: bool) ![]const_decl.ConstDecl {
    var cursor = Cursor{ .bytes = payload };
    const count = try decodeUleb128(&cursor);
    if (count > std.math.maxInt(usize)) return error.Leb128Overflow;
    const out = try allocator.alloc(const_decl.ConstDecl, @intCast(count));
    errdefer allocator.free(out);
    var initialized: usize = 0;
    errdefer for (out[0..initialized]) |*decl| decl.deinit(allocator);
    for (out) |*decl| {
        const source_line: u32 = @intCast(try decodeUleb128(&cursor));
        const expanded_line: u32 = @intCast(try decodeUleb128(&cursor));
        const name = try readSymbolName(allocator, symbols, try decodeUleb128(&cursor));
        errdefer allocator.free(name);
        const literal_text = try readSymbolName(allocator, symbols, try decodeUleb128(&cursor));
        errdefer allocator.free(literal_text);
        const raw_text = try std.fmt.allocPrint(allocator, "@const {s} = {s}", .{ name, literal_text });
        errdefer allocator.free(raw_text);
        var upstream_loc: ?upstream.UpstreamLoc = null;
        errdefer if (upstream_loc) |loc| allocator.free(loc.file);
        if (has_metadata) upstream_loc = try readOptionalAllocUpstreamLoc(allocator, symbols, &cursor);
        decl.* = .{
            .source_line = source_line,
            .expanded_line = expanded_line,
            .upstream_loc = upstream_loc,
            .raw_text = raw_text,
            .name = name,
            .literal_text = literal_text,
            .value = try readConstValue(allocator, symbols, &cursor),
        };
        upstream_loc = null;
        initialized += 1;
    }
    return out;
}

pub fn writeFunctionSigs(writer: *std.Io.Writer, function_sigs: []const sig.FunctionSig, pool: *std.StringHashMap(u32)) !void {
    try encodeUleb128(writer, function_sigs.len);
    for (function_sigs) |item| {
        try encodeUleb128(writer, item.id);
        try encodeUleb128(writer, try poolId(pool, item.name));
        try writer.writeByte(@intFromEnum(item.kind));
        try writer.writeByte(if (item.return_cap != null) 1 else 0);
        if (item.return_cap) |cap| try writer.writeByte(@intFromEnum(cap));
        try writer.writeByte(@intFromEnum(item.return_ty));
        try writer.writeByte(if (item.return_fallible) 1 else 0);
        try encodeUleb128(writer, item.entry_inst_idx);
        try writer.writeByte(if (item.is_ffi_wrapper) 1 else 0);
        try writer.writeByte(if (item.ignored) 1 else 0);
        try writer.writeByte(if (item.should_panic) 1 else 0);
        try writer.writeByte(if (item.is_variadic) 1 else 0);
        try writeOptionalPoolText(writer, pool, item.upstream_file);
        try writeOptionalUpstreamLoc(writer, pool, item.upstream_loc);
        try writeOptionalPoolText(writer, pool, item.llvm_name);

        try encodeUleb128(writer, item.params.len);
        for (item.params) |param| {
            try encodeUleb128(writer, try poolId(pool, param.name));
            try writer.writeByte(@intFromEnum(param.ty));
            try writer.writeByte(@intFromEnum(param.cap));
        }
        try encodeUleb128(writer, item.param_ids.len);
        for (item.param_ids) |id| try encodeUleb128(writer, id);
        try encodeUleb128(writer, item.reg_ids.len);
        for (item.reg_ids) |id| try encodeUleb128(writer, id);
    }
}

pub fn readSymbolName(allocator: std.mem.Allocator, symbols: []const []const u8, id: u64) ![]u8 {
    if (id > std.math.maxInt(usize)) return error.Leb128Overflow;
    const idx: usize = @intCast(id);
    if (idx >= symbols.len) return error.InvalidTag;
    return try allocator.dupe(u8, symbols[idx]);
}

pub fn readFunctionSigs(allocator: std.mem.Allocator, symbols: []const []const u8, payload: []const u8, has_metadata: bool) ![]sig.FunctionSig {
    var cursor = Cursor{ .bytes = payload };
    const count = try decodeUleb128(&cursor);
    if (count > std.math.maxInt(usize)) return error.Leb128Overflow;
    const out = try allocator.alloc(sig.FunctionSig, @intCast(count));
    errdefer allocator.free(out);
    var initialized: usize = 0;
    errdefer for (out[0..initialized]) |*item| item.deinit(allocator);

    for (out) |*item| {
        const id: u32 = @intCast(try decodeUleb128(&cursor));
        const name = try readSymbolName(allocator, symbols, try decodeUleb128(&cursor));
        errdefer allocator.free(name);
        const kind = (std.enums.fromInt(sig.FunctionKind, try cursor.readByte()) orelse return error.InvalidTag);
        const return_cap_present = try cursor.readByte();
        const return_cap: ?inst.CapPrefix = if (return_cap_present == 1)
            (std.enums.fromInt(inst.CapPrefix, try cursor.readByte()) orelse return error.InvalidTag)
        else if (return_cap_present == 0) null else return error.InvalidTag;
        const return_ty = (std.enums.fromInt(sig.PrimType, try cursor.readByte()) orelse return error.InvalidTag);
        const return_fallible = (try cursor.readByte()) == 1;
        const entry_inst_idx: u32 = @intCast(try decodeUleb128(&cursor));
        const is_ffi_wrapper = (try cursor.readByte()) == 1;
        const ignored = (try cursor.readByte()) == 1;
        const should_panic = (try cursor.readByte()) == 1;
        const is_variadic = (try cursor.readByte()) == 1;
        var upstream_file: ?[]u8 = null;
        errdefer if (upstream_file) |file| allocator.free(file);
        var upstream_loc: ?upstream.UpstreamLoc = null;
        errdefer if (upstream_loc) |loc| allocator.free(loc.file);
        var llvm_name: ?[]u8 = null;
        errdefer if (llvm_name) |value| allocator.free(value);
        if (has_metadata) {
            upstream_file = try readOptionalAllocText(allocator, symbols, &cursor);
            upstream_loc = try readOptionalAllocUpstreamLoc(allocator, symbols, &cursor);
            llvm_name = try readOptionalAllocText(allocator, symbols, &cursor);
        }

        const param_count = try decodeUleb128(&cursor);
        if (param_count > std.math.maxInt(usize)) return error.Leb128Overflow;
        const params = try allocator.alloc(sig.ParamSpec, @intCast(param_count));
        errdefer allocator.free(params);
        var param_initialized: usize = 0;
        errdefer for (params[0..param_initialized]) |param| allocator.free(param.name);
        for (params) |*param| {
            param.* = .{
                .name = try readSymbolName(allocator, symbols, try decodeUleb128(&cursor)),
                .ty = (std.enums.fromInt(sig.PrimType, try cursor.readByte()) orelse return error.InvalidTag),
                .cap = (std.enums.fromInt(inst.CapPrefix, try cursor.readByte()) orelse return error.InvalidTag),
            };
            param_initialized += 1;
        }

        const param_id_count = try decodeUleb128(&cursor);
        if (param_id_count > std.math.maxInt(usize)) return error.Leb128Overflow;
        const param_ids = try allocator.alloc(u32, @intCast(param_id_count));
        errdefer allocator.free(param_ids);
        for (param_ids) |*slot| slot.* = @intCast(try decodeUleb128(&cursor));

        const reg_id_count = try decodeUleb128(&cursor);
        if (reg_id_count > std.math.maxInt(usize)) return error.Leb128Overflow;
        const reg_ids = try allocator.alloc(u32, @intCast(reg_id_count));
        errdefer allocator.free(reg_ids);
        for (reg_ids) |*slot| slot.* = @intCast(try decodeUleb128(&cursor));

        item.* = .{
            .id = id,
            .name = name,
            .params = params,
            .kind = kind,
            .return_cap = return_cap,
            .return_ty = return_ty,
            .return_fallible = return_fallible,
            .entry_inst_idx = entry_inst_idx,
            .is_ffi_wrapper = is_ffi_wrapper,
            .param_ids = param_ids,
            .reg_ids = reg_ids,
            .upstream_file = upstream_file,
            .upstream_loc = upstream_loc,
            .llvm_name = llvm_name,
            .ignored = ignored,
            .should_panic = should_panic,
            .is_variadic = is_variadic,
        };
        upstream_file = null;
        upstream_loc = null;
        llvm_name = null;
        initialized += 1;
    }
    return out;
}

pub fn readTestFunctionSigs(allocator: std.mem.Allocator, symbols: []const []const u8, payload: []const u8, has_metadata: bool) ![]sig.FunctionSig {
    var cursor = Cursor{ .bytes = payload };
    const count = try decodeUleb128(&cursor);
    if (count > std.math.maxInt(usize)) return error.Leb128Overflow;

    var out = std.array_list.Managed(sig.FunctionSig).init(allocator);
    errdefer {
        for (out.items) |*item| item.deinit(allocator);
        out.deinit();
    }

    var i: u64 = 0;
    while (i < count) : (i += 1) {
        const id: u32 = @intCast(try decodeUleb128(&cursor));
        const name_id = try decodeUleb128(&cursor);
        const kind = (std.enums.fromInt(sig.FunctionKind, try cursor.readByte()) orelse return error.InvalidTag);
        const return_cap_present = try cursor.readByte();
        const return_cap: ?inst.CapPrefix = if (return_cap_present == 1)
            (std.enums.fromInt(inst.CapPrefix, try cursor.readByte()) orelse return error.InvalidTag)
        else if (return_cap_present == 0) null else return error.InvalidTag;
        const return_ty = (std.enums.fromInt(sig.PrimType, try cursor.readByte()) orelse return error.InvalidTag);
        const return_fallible = (try cursor.readByte()) == 1;
        const entry_inst_idx: u32 = @intCast(try decodeUleb128(&cursor));
        const is_ffi_wrapper = (try cursor.readByte()) == 1;
        const ignored = (try cursor.readByte()) == 1;
        const should_panic = (try cursor.readByte()) == 1;
        const is_variadic = (try cursor.readByte()) == 1;

        var upstream_file: ?[]u8 = null;
        errdefer if (upstream_file) |file| allocator.free(file);
        var upstream_loc: ?upstream.UpstreamLoc = null;
        errdefer if (upstream_loc) |loc| allocator.free(loc.file);
        var llvm_name: ?[]u8 = null;
        errdefer if (llvm_name) |value| allocator.free(value);

        const is_test = kind == .test_func;
        if (has_metadata) {
            if (is_test) {
                upstream_file = try readOptionalAllocText(allocator, symbols, &cursor);
                upstream_loc = try readOptionalAllocUpstreamLoc(allocator, symbols, &cursor);
                llvm_name = try readOptionalAllocText(allocator, symbols, &cursor);
            } else {
                try skipOptionalPoolText(&cursor);
                try skipOptionalUpstreamLoc(&cursor);
                try skipOptionalPoolText(&cursor);
            }
        }

        const param_count = try decodeUleb128(&cursor);
        var param_i: u64 = 0;
        while (param_i < param_count) : (param_i += 1) {
            _ = try decodeUleb128(&cursor);
            _ = try cursor.readByte();
            _ = try cursor.readByte();
        }

        const param_id_count = try decodeUleb128(&cursor);
        var param_id_i: u64 = 0;
        while (param_id_i < param_id_count) : (param_id_i += 1) _ = try decodeUleb128(&cursor);

        const reg_id_count = try decodeUleb128(&cursor);
        var reg_id_i: u64 = 0;
        while (reg_id_i < reg_id_count) : (reg_id_i += 1) _ = try decodeUleb128(&cursor);

        if (!is_test) continue;

        const name = try readSymbolName(allocator, symbols, name_id);
        errdefer allocator.free(name);
        const params = try allocator.alloc(sig.ParamSpec, 0);
        errdefer allocator.free(params);

        try out.append(.{
            .id = id,
            .name = name,
            .params = params,
            .kind = kind,
            .return_cap = return_cap,
            .return_ty = return_ty,
            .return_fallible = return_fallible,
            .entry_inst_idx = entry_inst_idx,
            .is_ffi_wrapper = is_ffi_wrapper,
            .param_ids = &.{},
            .reg_ids = &.{},
            .upstream_file = upstream_file,
            .upstream_loc = upstream_loc,
            .llvm_name = llvm_name,
            .ignored = ignored,
            .should_panic = should_panic,
            .is_variadic = is_variadic,
        });
        upstream_file = null;
        upstream_loc = null;
        llvm_name = null;
    }

    return try out.toOwnedSlice();
}

pub fn freeDecodedInstructionMetadataOne(allocator: std.mem.Allocator, item: *const inst.Instruction) void {
    if (item.package_identity) |identity| allocator.free(identity);
    if (item.upstream_loc) |loc| allocator.free(loc.file);
    if (item.native_reg_names.len != 0) allocator.free(item.native_reg_names);
}

pub fn freeDecodedInstructionMetadata(allocator: std.mem.Allocator, instructions: []inst.Instruction) void {
    for (instructions) |*item| freeDecodedInstructionMetadataOne(allocator, item);
}

pub fn readInstructions(allocator: std.mem.Allocator, symbols: []const []const u8, owned_text: *std.array_list.Managed([]const u8), payload: []const u8, has_raw_text: bool, has_full_metadata: bool, synthesize_debug_text: bool) ![]inst.Instruction {
    var cursor = Cursor{ .bytes = payload };
    const count = try decodeUleb128(&cursor);
    if (count > std.math.maxInt(usize)) return error.Leb128Overflow;
    const instructions = try allocator.alloc(inst.Instruction, @intCast(count));
    var initialized: usize = 0;
    errdefer {
        freeDecodedInstructionMetadata(allocator, instructions[0..initialized]);
        allocator.free(instructions);
    }
    for (instructions) |*item| {
        const kind = (std.enums.fromInt(inst.InstKind, try cursor.readByte()) orelse return error.InvalidTag);
        // SA-text 为语义标准：保留编码中的 expanded_line（宏展开行号），
        // 不得以解码序号覆盖，否则诊断行号/const 交错与文本路径分歧。
        item.* = inst.makeInstruction(kind, @intCast(try decodeUleb128(&cursor)), @intCast(try decodeUleb128(&cursor)), null, "");
        var item_initialized = false;
        errdefer if (!item_initialized) freeDecodedInstructionMetadataOne(allocator, item);
        item.op_kind = try readOptionalEnum(inst.OpKind, &cursor);
        for (&item.operands) |*operand| operand.* = try readOperand(allocator, symbols, owned_text, &cursor);
        if (has_raw_text) {
            const raw_present = try cursor.readByte();
            if (raw_present == 1) {
                item.raw_text = try readPooledText(allocator, symbols, owned_text, try decodeUleb128(&cursor));
            } else if (raw_present != 0) {
                return error.InvalidTag;
            }
        }
        item.atomic_value_ty = if (try cursor.readByte() == 1) @intCast(try decodeUleb128(&cursor)) else null;
        item.atomic_ordering = try readOptionalEnum(inst.AtomicOrdering, &cursor);
        item.atomic_second_ordering = try readOptionalEnum(inst.AtomicOrdering, &cursor);
        item.atomic_rmw_op = try readOptionalEnum(inst.AtomicRmwOp, &cursor);
        if (has_full_metadata) {
            item.atomic_expected_text = try readOptionalPooledText(allocator, symbols, owned_text, &cursor);
            item.atomic_new_text = try readOptionalPooledText(allocator, symbols, owned_text, &cursor);

            const native_count = try decodeUleb128(&cursor);
            if (native_count > std.math.maxInt(usize)) return error.Leb128Overflow;
            if (native_count != 0) {
                const native_names = try allocator.alloc([]const u8, @intCast(native_count));
                errdefer allocator.free(native_names);
                for (native_names) |*name| name.* = try readPooledText(allocator, symbols, owned_text, try decodeUleb128(&cursor));
                item.native_reg_names = native_names;
            }

            item.package_identity = try readOptionalAllocText(allocator, symbols, &cursor);
            item.package_source_sha256 = try readOptionalHash(&cursor);
            item.upstream_loc = try readOptionalAllocUpstreamLoc(allocator, symbols, &cursor);
        }
        if (synthesize_debug_text and item.raw_text.len == 0) try synthesizeRawText(allocator, symbols, owned_text, item);
        item_initialized = true;
        initialized += 1;
    }
    return instructions;
}

pub fn encodeProgramWithConsts(allocator: std.mem.Allocator, symbols: []const []const u8, const_decls: []const const_decl.ConstDecl, function_sigs: []const sig.FunctionSig, instructions: []const inst.Instruction) ![]u8 {
    var pool_items = std.array_list.Managed([]const u8).init(allocator);
    defer pool_items.deinit();
    var pool = std.StringHashMap(u32).init(allocator);
    defer pool.deinit();

    for (symbols) |name| {
        try addPoolText(&pool_items, &pool, name);
    }
    for (instructions) |item| {
        if (item.atomic_expected_text) |text| try addPoolText(&pool_items, &pool, text);
        if (item.atomic_new_text) |text| try addPoolText(&pool_items, &pool, text);
        for (item.native_reg_names) |name| try addPoolText(&pool_items, &pool, name);
        if (item.package_identity) |identity| try addPoolText(&pool_items, &pool, identity);
        if (item.upstream_loc) |loc| try addPoolText(&pool_items, &pool, loc.file);
        for (item.operands) |operand| switch (operand) {
            .text, .native_text => |text| try addPoolText(&pool_items, &pool, text),
            else => {},
        };
    }
    for (function_sigs) |item| {
        try addPoolText(&pool_items, &pool, item.name);
        if (item.upstream_file) |file| try addPoolText(&pool_items, &pool, file);
        if (item.upstream_loc) |loc| try addPoolText(&pool_items, &pool, loc.file);
        if (item.llvm_name) |name| try addPoolText(&pool_items, &pool, name);
        for (item.params) |param| {
            try addPoolText(&pool_items, &pool, param.name);
        }
    }
    for (const_decls) |decl| {
        try addPoolText(&pool_items, &pool, decl.name);
        try addPoolText(&pool_items, &pool, decl.literal_text);
        if (decl.upstream_loc) |loc| try addPoolText(&pool_items, &pool, loc.file);
        try collectConstValueSymbols(&pool_items, &pool, decl.value);
    }

    var sym_payload: std.Io.Writer.Allocating = .init(allocator);
    defer sym_payload.deinit();
    try writeStringPool(&sym_payload.writer, pool_items.items);

    var inst_payload: std.Io.Writer.Allocating = .init(allocator);
    defer inst_payload.deinit();
    try writeInstructions(&inst_payload.writer, instructions, &pool);

    var sig_payload: std.Io.Writer.Allocating = .init(allocator);
    defer sig_payload.deinit();
    try writeFunctionSigs(&sig_payload.writer, function_sigs, &pool);

    var const_payload: std.Io.Writer.Allocating = .init(allocator);
    defer const_payload.deinit();
    try writeConstDecls(&const_payload.writer, const_decls, &pool);

    var out: std.Io.Writer.Allocating = .init(allocator);
    errdefer out.deinit();
    try out.writer.writeAll(magic);
    try out.writer.writeByte(version_major);
    try out.writer.writeByte(version_minor);
    try encodeUleb128(&out.writer, 4);
    try writeSection(&out.writer, .symbol_pool, sym_payload.writer.buffered());
    try writeSection(&out.writer, .function_sigs, sig_payload.writer.buffered());
    try writeSection(&out.writer, .const_decls, const_payload.writer.buffered());
    try writeSection(&out.writer, .instructions, inst_payload.writer.buffered());
    return try out.toOwnedSlice();
}

pub fn encodeProgram(allocator: std.mem.Allocator, symbols: []const []const u8, function_sigs: []const sig.FunctionSig, instructions: []const inst.Instruction) ![]u8 {
    return encodeProgramWithConsts(allocator, symbols, &.{}, function_sigs, instructions);
}

pub fn encodeModule(allocator: std.mem.Allocator, symbols: []const []const u8, instructions: []const inst.Instruction) ![]u8 {
    return encodeProgram(allocator, symbols, &.{}, instructions);
}

pub fn decodeModule(allocator: std.mem.Allocator, bytes: []const u8) !Module {
    if (bytes.len < magic.len + 2) return error.TruncatedSab;
    if (isFragmentBytes(bytes)) return error.SabFragmentNotAProgram;
    if (!std.mem.eql(u8, bytes[0..magic.len], magic)) return error.InvalidSabMagic;
    var cursor = Cursor{ .bytes = bytes, .index = magic.len };
    const major = try cursor.readByte();
    _ = try cursor.readByte();
    if (major != 1 and major != 2 and major != 3 and major != version_major) return error.UnsupportedSabVersion;
    const has_raw_text = major >= 2 and major < 4;
    const has_full_metadata = major >= 3;
    const synthesize_debug_text = major < 4;

    var symbols: []const []const u8 = &.{};
    var function_sigs: []sig.FunctionSig = &.{};
    var const_decls: []const_decl.ConstDecl = &.{};
    var instructions: ?[]inst.Instruction = null;
    var owned_text = std.array_list.Managed([]const u8).init(allocator);
    errdefer {
        for (owned_text.items) |text| allocator.free(text);
        owned_text.deinit();
    }
    const section_count = try decodeUleb128(&cursor);
    var i: u64 = 0;
    while (i < section_count) : (i += 1) {
        const id = try decodeUleb128(&cursor);
        const len = try decodeUleb128(&cursor);
        if (len > std.math.maxInt(usize)) return error.Leb128Overflow;
        const payload = try cursor.readSlice(@intCast(len));
        if (id == @intFromEnum(SectionId.symbol_pool)) symbols = try readStringPoolBorrowed(allocator, payload);
        if (id == @intFromEnum(SectionId.function_sigs)) function_sigs = try readFunctionSigs(allocator, symbols, payload, has_full_metadata);
        if (id == @intFromEnum(SectionId.const_decls)) const_decls = try readConstDecls(allocator, symbols, payload, has_full_metadata);
        if (id == @intFromEnum(SectionId.instructions)) instructions = try readInstructions(allocator, symbols, &owned_text, payload, has_raw_text, has_full_metadata, synthesize_debug_text);
    }
    return .{ .symbols = symbols, .owns_symbol_text = false, .function_sigs = function_sigs, .const_decls = const_decls, .instructions = instructions orelse return error.MissingInstructionSection, .owned_text = try owned_text.toOwnedSlice() };
}

pub fn decodeFunctionSigsOnly(allocator: std.mem.Allocator, bytes: []const u8) ![]sig.FunctionSig {
    if (bytes.len < magic.len + 2) return error.TruncatedSab;
    if (isFragmentBytes(bytes)) return error.SabFragmentNotAProgram;
    if (!std.mem.eql(u8, bytes[0..magic.len], magic)) return error.InvalidSabMagic;
    var cursor = Cursor{ .bytes = bytes, .index = magic.len };
    const major = try cursor.readByte();
    _ = try cursor.readByte();
    if (major != 1 and major != 2 and major != 3 and major != version_major) return error.UnsupportedSabVersion;
    const has_full_metadata = major >= 3;

    var symbols: []const []const u8 = &.{};
    defer {
        for (symbols) |name| allocator.free(name);
        allocator.free(symbols);
    }

    var function_sig_payload: ?[]const u8 = null;
    const section_count = try decodeUleb128(&cursor);
    var i: u64 = 0;
    while (i < section_count) : (i += 1) {
        const id = try decodeUleb128(&cursor);
        const len = try decodeUleb128(&cursor);
        if (len > std.math.maxInt(usize)) return error.Leb128Overflow;
        const payload = try cursor.readSlice(@intCast(len));
        if (id == @intFromEnum(SectionId.symbol_pool)) symbols = try readStringPool(allocator, payload);
        if (id == @intFromEnum(SectionId.function_sigs)) function_sig_payload = payload;
    }

    if (function_sig_payload) |payload| {
        return try readFunctionSigs(allocator, symbols, payload, has_full_metadata);
    }
    return try allocator.alloc(sig.FunctionSig, 0);
}

pub fn decodeTestFunctionSigsOnly(allocator: std.mem.Allocator, bytes: []const u8) ![]sig.FunctionSig {
    if (bytes.len < magic.len + 2) return error.TruncatedSab;
    if (isFragmentBytes(bytes)) return error.SabFragmentNotAProgram;
    if (!std.mem.eql(u8, bytes[0..magic.len], magic)) return error.InvalidSabMagic;
    var cursor = Cursor{ .bytes = bytes, .index = magic.len };
    const major = try cursor.readByte();
    _ = try cursor.readByte();
    if (major != 1 and major != 2 and major != 3 and major != version_major) return error.UnsupportedSabVersion;
    const has_full_metadata = major >= 3;

    var symbols: []const []const u8 = &.{};
    defer allocator.free(symbols);

    var function_sig_payload: ?[]const u8 = null;
    const section_count = try decodeUleb128(&cursor);
    var i: u64 = 0;
    while (i < section_count) : (i += 1) {
        const id = try decodeUleb128(&cursor);
        const len = try decodeUleb128(&cursor);
        if (len > std.math.maxInt(usize)) return error.Leb128Overflow;
        const payload = try cursor.readSlice(@intCast(len));
        if (id == @intFromEnum(SectionId.symbol_pool)) symbols = try readStringPoolBorrowed(allocator, payload);
        if (id == @intFromEnum(SectionId.function_sigs)) function_sig_payload = payload;
    }

    if (function_sig_payload) |payload| {
        return try readTestFunctionSigs(allocator, symbols, payload, has_full_metadata);
    }
    return try allocator.alloc(sig.FunctionSig, 0);
}

pub fn disasmModule(allocator: std.mem.Allocator, bytes: []const u8, writer: *std.Io.Writer) !void {
    var module = try decodeModule(allocator, bytes);
    defer module.deinit(allocator);

    for (module.function_sigs) |fsig| {
        try sig.writeFunctionHeader(writer, fsig);
        try writer.writeByte('\n');
    }
    if (module.function_sigs.len > 0) try writer.writeByte('\n');

    for (module.const_decls) |decl| {
        try writer.print("@const {s} = {s}\n", .{ decl.name, decl.literal_text });
    }
    if (module.const_decls.len > 0) try writer.writeByte('\n');

    for (module.instructions) |item| {
        switch (item.kind) {
            .func_decl, .ffi_wrapper_decl, .extern_decl, .export_decl, .test_decl, .gpu_decl => {
                try writer.writeByte('\n');
                try writeDisasmInstruction(writer, item, module.symbols);
            },
            .label => {
                try writeDisasmInstruction(writer, item, module.symbols);
            },
            else => {
                try writer.writeAll("    ");
                try writeDisasmInstruction(writer, item, module.symbols);
            },
        }
    }
}
