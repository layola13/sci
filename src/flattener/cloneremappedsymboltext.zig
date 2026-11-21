const std = @import("std");
const classifier = @import("line_classifier.zig");
const common_const_decl = @import("../common/const_decl.zig");
const common_signature = @import("../common/signature.zig");
const common_upstream = @import("../common/upstream_loc.zig");
const ConstDecl = @import("../common/const_decl.zig").ConstDecl;
const DefDict = @import("def_dict.zig").DefDict;
const FunctionSig = @import("../common/signature.zig").FunctionSig;
const Instruction = @import("../common/instruction.zig").Instruction;
const Operand = @import("../common/instruction.zig").Operand;
const SymbolTable = @import("symbol.zig").SymbolTable;
const FlattenResult = @import("appendexpandedimportcachehit.zig").FlattenResult;
const LayoutVersion = @import("importexpansion.zig").LayoutVersion;
const MacroDef = @import("importexpansion.zig").MacroDef;
const SourceLine = @import("importexpansion.zig").SourceLine;
const cloneRemappedInstruction = @import("injectimportedfile.zig").cloneRemappedInstruction;
const isIdentChar = @import("renderwithtokenreplacements.zig").isIdentChar;
const isIdentStart = @import("renderwithtokenreplacements.zig").isIdentStart;
const ownText = @import("renderwithtokenreplacements.zig").ownText;
const restoreCachedMacroDefs = @import("appendexpandedimportcachehit.zig").restoreCachedMacroDefs;


pub fn scanSource(
    allocator: std.mem.Allocator,
    source: []const u8,
    line_package_identities: []const ?[]const u8,
    line_package_hashes: []const ?[32]u8,
) ![]SourceLine {
    return scanSourceWithOrigins(allocator, source, line_package_identities, line_package_hashes, &.{}, &.{});
}

pub fn scanSourceWithOrigins(
    allocator: std.mem.Allocator,
    source: []const u8,
    line_package_identities: []const ?[]const u8,
    line_package_hashes: []const ?[32]u8,
    line_origin_paths: []const ?[]const u8,
    line_origin_lines: []const u32,
) ![]SourceLine {
    var lines = std.array_list.Managed(SourceLine).init(allocator);
    errdefer lines.deinit();
    try lines.ensureTotalCapacity(countSourceLines(source));

    var iterator = std.mem.splitScalar(u8, source, '\n');
    var line_idx: usize = 0;
    while (iterator.next()) |raw_line| : (line_idx += 1) {
        const line_no = std.math.cast(u32, line_idx + 1) orelse return error.SourceTooLarge;
        const idx = line_idx;
        const package_identity = if (idx < line_package_identities.len) line_package_identities[idx] else null;
        const package_source_sha256 = if (idx < line_package_hashes.len) line_package_hashes[idx] else null;
        const origin_path = if (idx < line_origin_paths.len) line_origin_paths[idx] else null;
        const origin_line_no = if (idx < line_origin_lines.len) line_origin_lines[idx] else 0;
        try lines.append(.{
            .line_no = line_no,
            .text = raw_line,
            .classified = classifier.classifyLine(raw_line),
            .package_identity = package_identity,
            .package_source_sha256 = package_source_sha256,
            .origin_path = origin_path,
            .origin_line_no = origin_line_no,
        });
    }

    return try lines.toOwnedSlice();
}

pub fn countSourceLines(source: []const u8) usize {
    return std.mem.count(u8, source, "\n") + 1;
}

pub fn buildSymbolIdRemap(allocator: std.mem.Allocator, source_symbols: *const SymbolTable, target_symbols: *SymbolTable) ![]u32 {
    const remap = try allocator.alloc(u32, source_symbols.names.items.len);
    errdefer allocator.free(remap);
    for (source_symbols.names.items, 0..) |name, idx| {
        remap[idx] = try target_symbols.intern(name);
    }
    return remap;
}

fn remapSymbolId(remap: []const u32, old_id: u32) !u32 {
    const idx: usize = @intCast(old_id);
    if (idx >= remap.len) return error.InvalidOperand;
    return remap[idx];
}

pub fn remapOperandSymbolIds(operand: *Operand, remap: []const u32) !void {
    switch (operand.*) {
        .reg => |old_id| operand.* = .{ .reg = try remapSymbolId(remap, old_id) },
        .symbol => |old_id| operand.* = .{ .symbol = try remapSymbolId(remap, old_id) },
        .label => |old_id| operand.* = .{ .label = try remapSymbolId(remap, old_id) },
        .func => |old_id| operand.* = .{ .func = try remapSymbolId(remap, old_id) },
        else => {},
    }
}

pub fn remapInstructionSymbolIds(instruction: *Instruction, remap: []const u32) !void {
    for (&instruction.operands) |*operand| {
        try remapOperandSymbolIds(operand, remap);
    }
}

fn isOpaqueMacroArgName(name: []const u8) bool {
    return std.mem.startsWith(u8, name, "__sla_macro_arg_");
}

fn remappedSymbolName(
    source_symbols: *const SymbolTable,
    target_symbols: *const SymbolTable,
    remap: []const u32,
    name: []const u8,
) !?[]const u8 {
    if (isOpaqueMacroArgName(name)) return null;
    const old_id = source_symbols.findId(name) orelse return null;
    const new_id = try remapSymbolId(remap, old_id);
    return target_symbols.lookupName(new_id) orelse error.InvalidOperand;
}

fn appendRemappedSymbolToken(
    out: *std.array_list.Managed(u8),
    source_symbols: *const SymbolTable,
    target_symbols: *const SymbolTable,
    remap: []const u32,
    token: []const u8,
) !void {
    if (try remappedSymbolName(source_symbols, target_symbols, remap, token)) |name| {
        try out.appendSlice(name);
    } else {
        try out.appendSlice(token);
    }
}

pub fn cloneRemappedSymbolText(
    allocator: std.mem.Allocator,
    owned_text: *std.array_list.Managed([]const u8),
    text: []const u8,
    source_symbols: *const SymbolTable,
    target_symbols: *const SymbolTable,
    remap: []const u32,
) ![]const u8 {
    var out = std.array_list.Managed(u8).init(allocator);
    errdefer out.deinit();

    var i: usize = 0;
    while (i < text.len) {
        const c = text[i];

        if (c == '"') {
            try out.append(c);
            i += 1;
            while (i < text.len) {
                const ch = text[i];
                try out.append(ch);
                i += 1;
                if (ch == '\\' and i < text.len) {
                    try out.append(text[i]);
                    i += 1;
                    continue;
                }
                if (ch == '"') break;
            }
            continue;
        }

        if (c == '/' and i + 1 < text.len and text[i + 1] == '/') {
            try out.appendSlice(text[i..]);
            break;
        }

        if ((c == '@' or c == '#' or c == '%') and i + 1 < text.len and isIdentStart(text[i + 1])) {
            try out.append(c);
            const start = i + 1;
            i = start + 1;
            while (i < text.len and isIdentChar(text[i])) : (i += 1) {}
            if (c == '#') {
                try out.appendSlice(text[start..i]);
            } else {
                try appendRemappedSymbolToken(&out, source_symbols, target_symbols, remap, text[start..i]);
            }
            continue;
        }

        if (isIdentStart(c)) {
            const start = i;
            i += 1;
            while (i < text.len and isIdentChar(text[i])) : (i += 1) {}
            try appendRemappedSymbolToken(&out, source_symbols, target_symbols, remap, text[start..i]);
            continue;
        }

        try out.append(c);
        i += 1;
    }

    const owned = try out.toOwnedSlice();
    errdefer allocator.free(owned);
    try owned_text.append(owned);
    return owned;
}

pub fn cloneRemappedSymbolIdSlice(allocator: std.mem.Allocator, ids: []const u32, remap: []const u32) ![]const u32 {
    if (ids.len == 0) return &.{};
    const out = try allocator.alloc(u32, ids.len);
    errdefer allocator.free(out);
    for (ids, 0..) |old_id, idx| {
        out[idx] = try remapSymbolId(remap, old_id);
    }
    return out;
}

fn cloneParams(allocator: std.mem.Allocator, params: []const common_signature.ParamSpec) ![]const common_signature.ParamSpec {
    if (params.len == 0) return &.{};
    const out = try allocator.alloc(common_signature.ParamSpec, params.len);
    errdefer allocator.free(out);
    var copied: usize = 0;
    errdefer {
        for (out[0..copied]) |param| allocator.free(param.name);
    }
    for (params, 0..) |param, idx| {
        out[idx] = .{
            .name = try allocator.dupe(u8, param.name),
            .ty = param.ty,
            .cap = param.cap,
        };
        copied += 1;
    }
    return out;
}

pub fn cloneRemappedFunctionSig(
    allocator: std.mem.Allocator,
    source_sig: FunctionSig,
    remap: []const u32,
    function_id_offset: u32,
    entry_inst_offset: u32,
) !FunctionSig {
    const cloned_id = try std.math.add(u32, source_sig.id, function_id_offset);
    var out = FunctionSig{
        .id = cloned_id,
        .name = try allocator.dupe(u8, source_sig.name),
        .params = &.{},
        .kind = source_sig.kind,
        .return_cap = source_sig.return_cap,
        .return_ty = source_sig.return_ty,
        .return_fallible = source_sig.return_fallible,
        .entry_inst_idx = try std.math.add(u32, source_sig.entry_inst_idx, entry_inst_offset),
        .is_ffi_wrapper = source_sig.is_ffi_wrapper,
        .upstream_file = null,
        .upstream_loc = null,
        .param_ids = &.{},
        .reg_ids = &.{},
        .llvm_name = null,
        .ignored = source_sig.ignored,
        .should_panic = source_sig.should_panic,
        .is_variadic = source_sig.is_variadic,
    };
    errdefer out.deinit(allocator);

    out.params = try cloneParams(allocator, source_sig.params);
    out.param_ids = try cloneRemappedSymbolIdSlice(allocator, source_sig.param_ids, remap);
    out.reg_ids = try cloneRemappedSymbolIdSlice(allocator, source_sig.reg_ids, remap);
    if (source_sig.upstream_loc) |loc| {
        const file_copy = try allocator.dupe(u8, loc.file);
        out.upstream_file = file_copy;
        out.upstream_loc = .{ .file = file_copy, .line = loc.line, .col = loc.col };
    } else if (source_sig.upstream_file) |file| {
        out.upstream_file = try allocator.dupe(u8, file);
    }
    if (source_sig.llvm_name) |llvm_name| {
        if (source_sig.kind == .test_func) {
            out.llvm_name = try common_signature.testLLVMName(allocator, cloned_id);
        } else {
            out.llvm_name = try allocator.dupe(u8, llvm_name);
        }
    }
    return out;
}

fn cloneExactFunctionSig(allocator: std.mem.Allocator, source_sig: FunctionSig) !FunctionSig {
    var out = FunctionSig{
        .id = source_sig.id,
        .name = try allocator.dupe(u8, source_sig.name),
        .params = &.{},
        .kind = source_sig.kind,
        .return_cap = source_sig.return_cap,
        .return_ty = source_sig.return_ty,
        .return_fallible = source_sig.return_fallible,
        .entry_inst_idx = source_sig.entry_inst_idx,
        .is_ffi_wrapper = source_sig.is_ffi_wrapper,
        .upstream_file = null,
        .upstream_loc = null,
        .param_ids = &.{},
        .reg_ids = &.{},
        .llvm_name = null,
        .ignored = source_sig.ignored,
        .should_panic = source_sig.should_panic,
        .is_variadic = source_sig.is_variadic,
    };
    errdefer out.deinit(allocator);

    out.params = try cloneParams(allocator, source_sig.params);
    out.param_ids = try allocator.dupe(u32, source_sig.param_ids);
    out.reg_ids = try allocator.dupe(u32, source_sig.reg_ids);
    if (source_sig.upstream_loc) |loc| {
        const file_copy = try allocator.dupe(u8, loc.file);
        out.upstream_file = file_copy;
        out.upstream_loc = .{ .file = file_copy, .line = loc.line, .col = loc.col };
    } else if (source_sig.upstream_file) |file| {
        out.upstream_file = try allocator.dupe(u8, file);
    }
    if (source_sig.llvm_name) |llvm_name| {
        out.llvm_name = try allocator.dupe(u8, llvm_name);
    }
    return out;
}

fn cloneBytesLiteral(allocator: std.mem.Allocator, source: common_const_decl.BytesLiteral) !common_const_decl.BytesLiteral {
    return .{
        .kind = source.kind,
        .bytes = try allocator.dupe(u8, source.bytes),
        .repeat_count = source.repeat_count,
        .repeat_byte = source.repeat_byte,
    };
}

fn cloneVTableSlot(allocator: std.mem.Allocator, source: common_const_decl.VTableSlot) !common_const_decl.VTableSlot {
    var out = common_const_decl.VTableSlot{
        .name = try allocator.dupe(u8, source.name),
        .func_name = &.{},
    };
    errdefer out.deinit(allocator);
    out.func_name = try allocator.dupe(u8, source.func_name);
    return out;
}

fn cloneStructField(allocator: std.mem.Allocator, source: common_const_decl.StructField) anyerror!common_const_decl.StructField {
    var out = common_const_decl.StructField{
        .name = try allocator.dupe(u8, source.name),
        .size = source.size,
        .value = undefined,
    };
    errdefer allocator.free(out.name);
    out.value = try cloneConstValue(allocator, source.value);
    return out;
}

fn cloneConstValue(allocator: std.mem.Allocator, source: common_const_decl.ConstValue) anyerror!common_const_decl.ConstValue {
    switch (source) {
        .hex => |literal| return .{ .hex = try cloneBytesLiteral(allocator, literal) },
        .utf8 => |literal| return .{ .utf8 = try cloneBytesLiteral(allocator, literal) },
        .repeat => |literal| return .{ .repeat = try cloneBytesLiteral(allocator, literal) },
        .struct_ => |literal| {
            const fields = try allocator.alloc(common_const_decl.StructField, literal.fields.len);
            errdefer allocator.free(fields);
            var copied: usize = 0;
            errdefer {
                for (fields[0..copied]) |*field| field.deinit(allocator);
            }
            for (literal.fields, 0..) |field, idx| {
                fields[idx] = try cloneStructField(allocator, field);
                copied += 1;
            }
            return .{ .struct_ = .{ .fields = fields } };
        },
        .vtable => |literal| {
            const slots = try allocator.alloc(common_const_decl.VTableSlot, literal.slots.len);
            errdefer allocator.free(slots);
            var copied: usize = 0;
            errdefer {
                for (slots[0..copied]) |*slot| slot.deinit(allocator);
            }
            for (literal.slots, 0..) |slot, idx| {
                slots[idx] = try cloneVTableSlot(allocator, slot);
                copied += 1;
            }
            return .{ .vtable = .{ .slots = slots } };
        },
    }
}

fn cloneConstDecl(
    allocator: std.mem.Allocator,
    source: ConstDecl,
    source_line_offset: u32,
    expanded_line_offset: u32,
) !ConstDecl {
    const raw_text = try allocator.dupe(u8, source.raw_text);
    errdefer allocator.free(raw_text);
    const name = try allocator.dupe(u8, source.name);
    errdefer allocator.free(name);
    const literal_text = try allocator.dupe(u8, source.literal_text);
    errdefer allocator.free(literal_text);
    var value = try cloneConstValue(allocator, source.value);
    errdefer value.deinit(allocator);

    var upstream_loc: ?common_upstream.UpstreamLoc = null;
    if (source.upstream_loc) |loc| {
        upstream_loc = .{
            .file = try allocator.dupe(u8, loc.file),
            .line = loc.line,
            .col = loc.col,
        };
    }
    errdefer if (upstream_loc) |loc| allocator.free(loc.file);

    return .{
        .source_line = try std.math.add(u32, source.source_line, source_line_offset),
        .expanded_line = try std.math.add(u32, source.expanded_line, expanded_line_offset),
        .upstream_loc = upstream_loc,
        .raw_text = raw_text,
        .name = name,
        .literal_text = literal_text,
        .value = value,
    };
}

fn bytesLiteralEql(a: common_const_decl.BytesLiteral, b: common_const_decl.BytesLiteral) bool {
    return a.kind == b.kind and
        std.mem.eql(u8, a.bytes, b.bytes) and
        a.repeat_count == b.repeat_count and
        a.repeat_byte == b.repeat_byte;
}

fn constValueEql(a: common_const_decl.ConstValue, b: common_const_decl.ConstValue) bool {
    switch (a) {
        .hex => |a_lit| return switch (b) {
            .hex => |b_lit| bytesLiteralEql(a_lit, b_lit),
            else => false,
        },
        .utf8 => |a_lit| return switch (b) {
            .utf8 => |b_lit| bytesLiteralEql(a_lit, b_lit),
            else => false,
        },
        .repeat => |a_lit| return switch (b) {
            .repeat => |b_lit| bytesLiteralEql(a_lit, b_lit),
            else => false,
        },
        .struct_ => |a_lit| return switch (b) {
            .struct_ => |b_lit| structLiteralEql(a_lit, b_lit),
            else => false,
        },
        .vtable => |a_lit| return switch (b) {
            .vtable => |b_lit| vtableLiteralEql(a_lit, b_lit),
            else => false,
        },
    }
}

fn structLiteralEql(a: common_const_decl.StructLiteral, b: common_const_decl.StructLiteral) bool {
    if (a.fields.len != b.fields.len) return false;
    for (a.fields, b.fields) |a_field, b_field| {
        if (!std.mem.eql(u8, a_field.name, b_field.name)) return false;
        if (a_field.size != b_field.size) return false;
        if (!constValueEql(a_field.value, b_field.value)) return false;
    }
    return true;
}

fn vtableLiteralEql(a: common_const_decl.VTableLiteral, b: common_const_decl.VTableLiteral) bool {
    if (a.slots.len != b.slots.len) return false;
    for (a.slots, b.slots) |a_slot, b_slot| {
        if (!std.mem.eql(u8, a_slot.name, b_slot.name)) return false;
        if (!std.mem.eql(u8, a_slot.func_name, b_slot.func_name)) return false;
    }
    return true;
}

pub fn mergeDefDictAllowingIdentical(target: *DefDict, source: *const DefDict) !void {
    var it = source.entries.iterator();
    while (it.next()) |entry| {
        if (target.entries.get(entry.key_ptr.*)) |existing| {
            if (!std.mem.eql(u8, existing, entry.value_ptr.*)) return error.DuplicateDef;
            continue;
        }
        const key_copy = try target.allocator.dupe(u8, entry.key_ptr.*);
        errdefer target.allocator.free(key_copy);
        const value_copy = try target.allocator.dupe(u8, entry.value_ptr.*);
        errdefer target.allocator.free(value_copy);
        try target.entries.put(key_copy, value_copy);
    }
    var bind_it = source.npm_binds.iterator();
    while (bind_it.next()) |entry| {
        if (target.npm_binds.get(entry.key_ptr.*)) |existing| {
            if (!std.mem.eql(u8, existing, entry.value_ptr.*)) return error.DuplicateDef;
            continue;
        }
        const key_copy = try target.allocator.dupe(u8, entry.key_ptr.*);
        errdefer target.allocator.free(key_copy);
        const value_copy = try target.allocator.dupe(u8, entry.value_ptr.*);
        errdefer target.allocator.free(value_copy);
        try target.npm_binds.put(key_copy, value_copy);
    }
}

pub fn mergeConstDeclsAllowingIdentical(
    allocator: std.mem.Allocator,
    target: *std.array_list.Managed(ConstDecl),
    source: []const ConstDecl,
    source_line_offset: u32,
    expanded_line_offset: u32,
) !void {
    for (source) |decl| {
        var existing: ?*ConstDecl = null;
        for (target.items) |*item| {
            if (std.mem.eql(u8, item.name, decl.name)) {
                existing = item;
                break;
            }
        }
        if (existing) |item| {
            if (!constValueEql(item.value, decl.value)) return error.DuplicateConstDecl;
            continue;
        }
        const cloned = try cloneConstDecl(allocator, decl, source_line_offset, expanded_line_offset);
        errdefer {
            var cleanup = cloned;
            cleanup.deinit(allocator);
        }
        try target.append(cloned);
    }
}

fn cloneLayoutVersion(allocator: std.mem.Allocator, source: LayoutVersion) !LayoutVersion {
    return .{
        .path = try allocator.dupe(u8, source.path),
        .version = source.version,
    };
}

pub fn mergeLayoutVersionsAllowingIdentical(
    allocator: std.mem.Allocator,
    target: *std.array_list.Managed(LayoutVersion),
    source: []const LayoutVersion,
) !void {
    for (source) |layout_version| {
        var existing: ?*LayoutVersion = null;
        for (target.items) |*item| {
            if (std.mem.eql(u8, item.path, layout_version.path)) {
                existing = item;
                break;
            }
        }
        if (existing) |item| {
            if (item.version != layout_version.version) return error.LayoutVersionConflict;
            continue;
        }
        const cloned = try cloneLayoutVersion(allocator, layout_version);
        errdefer {
            var cleanup = cloned;
            cleanup.deinit(allocator);
        }
        try target.append(cloned);
    }
}

pub fn mergePackageIdentities(
    allocator: std.mem.Allocator,
    target: *std.StringHashMap(void),
    source: *const std.StringHashMap(void),
) !void {
    var it = source.iterator();
    while (it.next()) |entry| {
        if (target.contains(entry.key_ptr.*)) continue;
        const copy = try allocator.dupe(u8, entry.key_ptr.*);
        errdefer allocator.free(copy);
        try target.put(copy, {});
    }
}

pub fn appendFlattenFragment(
    allocator: std.mem.Allocator,
    target_instructions: *std.array_list.Managed(Instruction),
    target_const_decls: *std.array_list.Managed(ConstDecl),
    target_function_sigs: *std.array_list.Managed(FunctionSig),
    target_test_sigs: *std.array_list.Managed(FunctionSig),
    target_def_dict: *DefDict,
    target_symbols: *SymbolTable,
    target_layout_versions: *std.array_list.Managed(LayoutVersion),
    target_package_identities: *std.StringHashMap(void),
    target_owned_text: *std.array_list.Managed([]const u8),
    target_macros: *std.StringHashMap(MacroDef),
    fragment: *const FlattenResult,
    source_line_offset: u32,
    expanded_line_offset: u32,
) !void {
    const remap = try buildSymbolIdRemap(allocator, &fragment.symbols, target_symbols);
    defer allocator.free(remap);

    try mergeDefDictAllowingIdentical(target_def_dict, &fragment.def_dict);
    try mergeConstDeclsAllowingIdentical(
        allocator,
        target_const_decls,
        fragment.const_decls,
        source_line_offset,
        expanded_line_offset,
    );
    try mergeLayoutVersionsAllowingIdentical(allocator, target_layout_versions, fragment.layout_versions);
    try mergePackageIdentities(allocator, target_package_identities, &fragment.package_identities);
    try restoreCachedMacroDefs(allocator, fragment.cached_macro_defs, target_macros);

    const function_id_offset: u32 = @intCast(target_function_sigs.items.len);
    const entry_inst_offset: u32 = @intCast(target_instructions.items.len);
    for (fragment.instructions) |instruction| {
        const cloned = try cloneRemappedInstruction(
            allocator,
            target_owned_text,
            instruction,
            &fragment.symbols,
            target_symbols,
            remap,
            source_line_offset,
            expanded_line_offset,
        );
        try target_instructions.append(cloned);
    }

    for (fragment.function_sigs) |sig| {
        const cloned = try cloneRemappedFunctionSig(
            allocator,
            sig,
            remap,
            function_id_offset,
            entry_inst_offset,
        );
        try target_function_sigs.append(cloned);
        if (cloned.kind == .test_func) {
            try target_test_sigs.append(try cloneExactFunctionSig(allocator, cloned));
        }
    }
}

pub fn cloneRemappedOperand(
    allocator: std.mem.Allocator,
    owned_text: *std.array_list.Managed([]const u8),
    operand: Operand,
    source_symbols: *const SymbolTable,
    target_symbols: *const SymbolTable,
    remap: []const u32,
) !Operand {
    return switch (operand) {
        .reg => |old_id| .{ .reg = try remapSymbolId(remap, old_id) },
        .symbol => |old_id| .{ .symbol = try remapSymbolId(remap, old_id) },
        .label => |old_id| .{ .label = try remapSymbolId(remap, old_id) },
        .func => |old_id| .{ .func = try remapSymbolId(remap, old_id) },
        .text => |text| .{ .text = try cloneRemappedSymbolText(allocator, owned_text, text, source_symbols, target_symbols, remap) },
        .native_text => |text| .{ .native_text = try cloneRemappedSymbolText(allocator, owned_text, text, source_symbols, target_symbols, remap) },
        else => operand,
    };
}

pub fn cloneNativeRegNames(
    allocator: std.mem.Allocator,
    owned_text: *std.array_list.Managed([]const u8),
    source: Instruction,
    cloned_native_text: ?[]const u8,
) ![]const []const u8 {
    if (source.native_reg_names.len == 0) return &.{};
    if (cloned_native_text) |native_text| return try classifier.collectNativeRegisterNames(allocator, native_text);

    const out = try allocator.alloc([]const u8, source.native_reg_names.len);
    errdefer allocator.free(out);
    var copied: usize = 0;
    errdefer {
        for (out[0..copied]) |name| {
            for (owned_text.items, 0..) |owned, idx| {
                if (owned.ptr == name.ptr and owned.len == name.len) {
                    _ = owned_text.orderedRemove(idx);
                    allocator.free(owned);
                    break;
                }
            }
        }
    }
    for (source.native_reg_names, 0..) |name, idx| {
        out[idx] = try ownText(allocator, owned_text, name);
        copied += 1;
    }
    return out;
}
