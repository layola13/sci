const std = @import("std");
const call = @import("../referee/call.zig");
const referee = @import("../referee.zig");
const emit_options = @import("../emit_options.zig");
const flattener = @import("../flattener.zig");
const inst = @import("../common/instruction.zig");
const atomic = @import("../common/atomic.zig");
const sig = @import("../common/signature.zig");
const const_decl = @import("../common/const_decl.zig");
const upstream = @import("../common/upstream_loc.zig");
const sio = @import("sio");

const SharedEmitTables = @import("atomic_rmw_op.zig").SharedEmitTables;

pub extern fn sa_llvmc_free(ptr: ?*anyopaque) callconv(.c) void;
pub extern fn sa_llvmc_make_minimal_module_bitcode(out_bytes: *?[*]u8, out_len: *usize, out_error: *?[*:0]u8) callconv(.c) i32;
pub extern fn sa_llvmc_emit_module_bitcode(module: *const CModule, opt_level: c_int, out_bytes: *?[*]u8, out_len: *usize, out_error: *?[*:0]u8) callconv(.c) i32;
pub extern fn sa_llvmc_emit_module_object(module: *const CModule, out_path: [*:0]const u8, opt_level: c_int, out_error: *?[*:0]u8) callconv(.c) i32;
pub extern fn sa_llvmc_emit_module_artifacts(module: *const CModule, out_bitcode_path: [*:0]const u8, out_object_path: [*:0]const u8, opt_level: c_int, out_error: *?[*:0]u8) callconv(.c) i32;

pub const LlvmcError = error{ Failed, InvalidOperand, UnsupportedType, UnknownFunction, UnsupportedInstruction, UnsupportedVariadic };
pub const EmitOptions = emit_options.EmitOptions;

pub threadlocal var last_error_buf: [512]u8 = undefined;
pub threadlocal var last_error_len: usize = 0;

pub fn recordLastError(message: []const u8) void {
    const len = @min(message.len, last_error_buf.len);
    @memcpy(last_error_buf[0..len], message[0..len]);
    last_error_len = len;
}

pub fn recordLlvmcError(prefix: []const u8, msg: [*:0]const u8) void {
    const message = std.mem.sliceTo(msg, 0);
    var stream = std.Io.Writer.fixed(&last_error_buf);
    stream.print("{s}: {s}", .{ prefix, message }) catch {
        recordLastError(message);
        return;
    };
    last_error_len = stream.end;
}

pub fn lastErrorMessage() ?[]const u8 {
    if (last_error_len == 0) return null;
    return last_error_buf[0..last_error_len];
}

pub const CType = enum(c_int) { void = 0, i1 = 1, i8 = 2, i16 = 3, i32 = 4, i64 = 5, f32 = 6, f64 = 7, ptr = 8, u8 = 9, u16 = 10, u32 = 11, u64 = 12 };
pub const CFuncKind = enum(c_int) { normal = 0, external = 1, exported = 2, test_func = 3 };
pub const COp = enum(c_int) { none = 0, label = 1, alloc = 2, stack_alloc = 3, load = 4, store = 5, op = 6, ptr_add = 7, jmp = 8, br = 9, call = 10, ret = 11, panic = 12, panic_msg = 13, atomic_load = 14, atomic_store = 15, atomic_rmw = 16, cmpxchg = 17, fence = 18, try_ = 19, call_indirect = 20, assign = 21, release = 22, take = 23, va_start = 24, va_arg = 25, va_end = 26, bitcast = 27 };
pub const COperandKind = enum(c_int) { none = 0, reg = 1, imm_i64 = 2, imm_u64 = 3, const_ptr = 4, imm_f64 = 5 };
pub const CBinaryOp = enum(c_int) { add = 0, sub = 1, mul = 2, sdiv = 3, udiv = 4, srem = 5, urem = 6, band = 7, bor = 8, xor = 9, shl = 10, lshr = 11, ashr = 12, eq = 13, ne = 14, slt = 15, sle = 16, sgt = 17, sge = 18, ult = 19, ule = 20, ugt = 21, uge = 22, fadd = 23, fsub = 24, fmul = 25, fdiv = 26, fcmp_eq = 27, fcmp_ne = 28, fcmp_lt = 29, fcmp_le = 30, fcmp_gt = 31, fcmp_ge = 32 };
pub const CAtomicOrdering = enum(c_int) { relaxed = 0, acquire = 1, release = 2, acq_rel = 3, seq_cst = 4 };
pub const CAtomicRmwOp = enum(c_int) { add = 0, sub = 1, band = 2, bor = 3, xor = 4, xchg = 5, min = 6, max = 7, umin = 8, umax = 9 };

pub const CConst = extern struct { name: [*:0]const u8, data: [*]const u8, len: usize };
pub const CVTable = extern struct { name: [*:0]const u8, funcs: [*]const [*:0]const u8, func_count: usize };
pub const CParam = extern struct { name: [*:0]const u8, ty: CType, slot: u32, is_malloc: bool };
pub const CDebugLoc = extern struct { line: u32, col: u32 };
pub const CDebugVar = extern struct { name: [*:0]const u8, ty: CType, slot: u32, is_param: bool, line: u32, col: u32 };
pub const COperand = extern struct { kind: COperandKind, reg: u32, i64_value: i64, u64_value: u64, f64_value: f64, ty: CType, name: ?[*:0]const u8 };
pub const CInstruction = extern struct {
    op: COp,
    dst: u32,
    operand0: COperand,
    operand1: COperand,
    operand2: COperand,
    ty: CType,
    binary_op: CBinaryOp,
    label: ?[*:0]const u8,
    false_label: ?[*:0]const u8,
    callee: ?[*:0]const u8,
    args: [*]const COperand,
    arg_count: usize,
    indirect_param_tys: [*]const CType,
    indirect_param_count: usize,
    has_dst: bool,
    atomic_ordering: CAtomicOrdering,
    atomic_second_ordering: CAtomicOrdering,
    atomic_rmw_op: CAtomicRmwOp,
    return_fallible: bool,
    indirect_sig_index: u32,
    is_malloc: bool = false,
    // C2 sab_carried_indirect_sig: when the frontend carried the
    // fn-pointer type's full signature on a call_indirect, the shim
    // trusts it over provenance/inference. indirect_param_tys above
    // then holds the FIXED parameter types; these fields add the
    // return type and variadic flag.
    indirect_ret_ty: CType = .void,
    indirect_is_variadic: bool = false,
    indirect_has_carried_sig: bool = false,
};
pub const CFunction = extern struct {
    name: [*:0]const u8,
    kind: CFuncKind,
    ret_ty: CType,
    return_fallible: bool,
    params: [*]const CParam,
    param_count: usize,
    instructions: [*]const CInstruction,
    instruction_count: usize,
    source_file: ?[*:0]const u8,
    source_dir: ?[*:0]const u8,
    entry_line: u32,
    entry_col: u32,
    debug_locs: [*]const CDebugLoc,
    debug_loc_count: usize,
    debug_vars: [*]const CDebugVar,
    debug_var_count: usize,
    emit_main_wrapper: bool,
    is_variadic: bool,
};
pub const CModule = extern struct {
    size_bits: u16,
    wasm_compat: bool,
    test_mode: bool,
    debug: bool,
    is_cgu: bool,
    fast_math: bool,
    source_file: ?[*:0]const u8,
    source_dir: ?[*:0]const u8,
    consts: [*]const CConst,
    const_count: usize,
    vtables: [*]const CVTable,
    vtable_count: usize,
    functions: [*]const CFunction,
    function_count: usize,
    target_triple: ?[*:0]const u8,
};

pub fn takeOwnedBitcode(allocator: std.mem.Allocator, bytes: *?[*]u8, len: *usize) ![]u8 {
    const ptr = bytes.* orelse return error.Failed;
    const out = try allocator.dupe(u8, ptr[0..len.*]);
    sa_llvmc_free(ptr);
    bytes.* = null;
    len.* = 0;
    return out;
}

pub fn cType(ty: sig.PrimType) !CType {
    return switch (ty) {
        .void => .void,
        .i1 => .i1,
        .i8 => .i8,
        .u8 => .u8,
        .i16 => .i16,
        .u16 => .u16,
        .i32, .blob_handle => .i32,
        .u32 => .u32,
        .i64 => .i64,
        .u64 => .u64,
        .f32 => .f32,
        .f64 => .f64,
        .ptr => .ptr,
        else => error.UnsupportedType,
    };
}

pub const CarriedIndirectSig = struct {
    params: []CType,
    ret_ty: CType,
    is_variadic: bool,
};

/// C2 sab_carried_indirect_sig: parse a carried fn-pointer signature
/// `(i32, ...) -> f64` into shim-ready types. Parameters are SA
/// primitive names; a trailing `...` marks the signature variadic. The
/// return accepts the pointer decorations parseFunctionSig allows
/// (`*` / `&` / `^`); a fallible `!` return is not expressible in this
/// record and fails the conversion.
pub fn parseCarriedIndirectSig(allocator: std.mem.Allocator, text: []const u8) !CarriedIndirectSig {
    const trimmed = std.mem.trim(u8, text, " \t");
    if (trimmed.len == 0 or trimmed[0] != '(') return error.InvalidOperand;
    const close = std.mem.indexOfScalar(u8, trimmed, ')') orelse return error.InvalidOperand;
    const tail = std.mem.trim(u8, trimmed[close + 1 ..], " \t");
    if (!std.mem.startsWith(u8, tail, "->")) return error.InvalidOperand;
    const ret_text = std.mem.trim(u8, tail[2..], " \t");
    if (ret_text.len == 0 or std.mem.indexOfScalar(u8, ret_text, '!') != null) return error.InvalidOperand;
    const ret_prim: sig.PrimType = if (ret_text[0] == '*' or ret_text[0] == '&' or ret_text[0] == '^')
        .ptr
    else
        sig.parsePrimType(ret_text) catch return error.InvalidOperand;
    var params = std.array_list.Managed(CType).init(allocator);
    errdefer params.deinit();
    var is_variadic = false;
    const params_text = std.mem.trim(u8, trimmed[1..close], " \t");
    if (params_text.len != 0) {
        var it = std.mem.splitScalar(u8, params_text, ',');
        while (it.next()) |raw_part| {
            const part = std.mem.trim(u8, raw_part, " \t");
            if (part.len == 0) continue;
            if (std.mem.eql(u8, part, "...")) {
                is_variadic = true;
                continue;
            }
            const prim = sig.parsePrimType(part) catch return error.InvalidOperand;
            try params.append(try cType(prim));
        }
    }
    return .{ .params = try params.toOwnedSlice(), .ret_ty = try cType(ret_prim), .is_variadic = is_variadic };
}

pub fn valueTypeForPrefix(prefix: inst.CapPrefix, ty: sig.PrimType) sig.PrimType {
    return switch (prefix) {
        .borrow, .raw => .ptr,
        .move, .by_value => ty,
    };
}

pub fn isRawQuotedStringArg(arg: call.ParsedArg) bool {
    return arg.prefix == .raw and arg.text.len >= 2 and arg.text[0] == '"' and arg.text[arg.text.len - 1] == '"';
}

pub fn parseHexDigitPair(text: []const u8) !u8 {
    if (text.len != 2) return error.InvalidOperand;
    const hi = std.fmt.charToDigit(text[0], 16) catch return error.InvalidOperand;
    const lo = std.fmt.charToDigit(text[1], 16) catch return error.InvalidOperand;
    return @as(u8, @intCast((hi << 4) | lo));
}

pub fn decodeQuotedBytes(allocator: std.mem.Allocator, raw: []const u8) ![]u8 {
    if (raw.len < 2 or raw[0] != '"' or raw[raw.len - 1] != '"') return error.InvalidOperand;

    var out = std.array_list.Managed(u8).init(allocator);
    errdefer out.deinit();

    var i: usize = 1;
    while (i < raw.len - 1) {
        const c = raw[i];
        if (c != '\\') {
            try out.append(c);
            i += 1;
            continue;
        }

        if (i + 1 >= raw.len - 1) return error.InvalidOperand;
        switch (raw[i + 1]) {
            '\\' => {
                try out.append('\\');
                i += 2;
            },
            '"' => {
                try out.append('"');
                i += 2;
            },
            'n' => {
                try out.append('\n');
                i += 2;
            },
            'r' => {
                try out.append('\r');
                i += 2;
            },
            't' => {
                try out.append('\t');
                i += 2;
            },
            '0' => {
                try out.append(0);
                i += 2;
            },
            'x' => {
                if (i + 3 >= raw.len - 1) return error.InvalidOperand;
                try out.append(try parseHexDigitPair(raw[i + 2 .. i + 4]));
                i += 4;
            },
            else => return error.InvalidOperand,
        }
    }

    return try out.toOwnedSlice();
}

pub fn returnTypeForSig(return_cap: ?inst.CapPrefix, return_ty: sig.PrimType) sig.PrimType {
    if (return_ty == .void) return .void;
    return switch (return_cap orelse .by_value) {
        .raw, .borrow => .ptr,
        .move, .by_value => return_ty,
    };
}

pub fn emittedFunctionName(fsig: sig.FunctionSig) []const u8 {
    if (fsig.kind == .normal and fsig.params.len == 0 and std.mem.eql(u8, fsig.name, "main")) {
        return "saasm_main";
    }
    if (fsig.llvm_name) |name| return name;
    return fsig.name;
}

pub fn sourceFileName(path: []const u8) []const u8 {
    return std.fs.path.basename(path);
}

pub fn sourceDirName(path: []const u8) []const u8 {
    return std.fs.path.dirname(path) orelse ".";
}

pub fn debugLocForInstruction(item: inst.Instruction, table_loc: ?upstream.UpstreamLoc, fallback: CDebugLoc) CDebugLoc {
    if (table_loc) |actual| return .{ .line = actual.line, .col = actual.col };
    if (item.upstream_loc) |actual| return .{ .line = actual.line, .col = actual.col };
    if (item.source_line != 0) return .{ .line = item.source_line, .col = 1 };
    return fallback;
}

pub fn makeSlotFallbackName(allocator: std.mem.Allocator, slot: usize) ![*:0]const u8 {
    const raw = try std.fmt.allocPrint(allocator, "slot_{d}", .{slot});
    defer allocator.free(raw);
    const text = try allocator.dupeSentinel(u8, raw, 0);
    return text.ptr;
}

pub fn buildDebugVars(allocator: std.mem.Allocator, symbols: anytype, fsig: sig.FunctionSig, entry_loc: CDebugLoc) ![]CDebugVar {
    if (fsig.reg_ids.len == 0) return &.{};
    const vars = try allocator.alloc(CDebugVar, fsig.reg_ids.len);
    for (fsig.reg_ids, 0..) |reg_id, slot| {
        const raw_name = symbols.lookupName(reg_id);
        const name = if (raw_name) |value| (try allocator.dupeSentinel(u8, value, 0)).ptr else try makeSlotFallbackName(allocator, slot);
        vars[slot] = .{
            .name = name,
            .ty = .i64,
            .slot = @intCast(slot),
            .is_param = false,
            .line = entry_loc.line,
            .col = entry_loc.col,
        };
    }
    for (fsig.params, 0..) |param, pidx| {
        if (pidx >= fsig.param_ids.len) continue;
        const slot = fsig.slotOf(fsig.param_ids[pidx]) orelse continue;
        if (slot >= vars.len) continue;
        vars[slot].ty = try cType(valueTypeForPrefix(param.cap, param.ty));
        vars[slot].is_param = true;
    }
    return vars;
}

pub fn constBytesLen(value: const_decl.ConstValue) !usize {
    return switch (value) {
        .hex, .utf8 => |literal| literal.bytes.len,
        .repeat => |literal| @intCast(literal.repeat_count orelse return error.InvalidOperand),
        .struct_ => |literal| blk: {
            var total: usize = 0;
            for (literal.fields) |field| {
                const len = try constBytesLen(field.value);
                if (len != field.size) return error.InvalidOperand;
                total = std.math.add(usize, total, len) catch return error.InvalidOperand;
            }
            break :blk total;
        },
        else => error.UnsupportedType,
    };
}

pub fn fillConstBytes(out: []u8, value: const_decl.ConstValue) !void {
    switch (value) {
        .hex, .utf8 => |literal| @memcpy(out, literal.bytes),
        .repeat => |literal| @memset(out, literal.repeat_byte orelse 0),
        .struct_ => |literal| {
            var cursor: usize = 0;
            for (literal.fields) |field| {
                const len = try constBytesLen(field.value);
                if (len != field.size or cursor + len > out.len) return error.InvalidOperand;
                try fillConstBytes(out[cursor .. cursor + len], field.value);
                cursor += len;
            }
            if (cursor != out.len) return error.InvalidOperand;
        },
        else => return error.UnsupportedType,
    }
}

pub fn collectAnonStringConsts(
    allocator: std.mem.Allocator,
    symbols: anytype,
    annotated: []const referee.AnnotatedInstruction,
    anon_string_names: *std.StringHashMap([*:0]const u8),
    c_consts: *std.array_list.Managed(CConst),
) !void {
    var anon_idx: usize = c_consts.items.len;
    for (annotated) |item| {
        switch (item.base.kind) {
            .call, .call_indirect, .panic, .panic_msg => {},
            else => continue,
        }

        var parsed = call.parseInstructionCall(allocator, item.base, symbols) catch |err| switch (err) {
            error.InvalidCallSyntax => continue,
            else => return err,
        };
        defer parsed.deinit(allocator);

        for (parsed.args) |arg| {
            if (!isRawQuotedStringArg(arg)) continue;
            if (anon_string_names.contains(arg.text)) continue;

            const bytes = try decodeQuotedBytes(allocator, arg.text);
            defer allocator.free(bytes);
            if (!std.unicode.utf8ValidateSlice(bytes)) return error.InvalidOperand;

            const raw_key = try allocator.dupe(u8, arg.text);
            errdefer allocator.free(raw_key);
            const raw_name = try std.fmt.allocPrint(allocator, "__sa_anon_str_{d}", .{anon_idx});
            defer allocator.free(raw_name);
            const name = try allocator.dupeSentinel(u8, raw_name, 0);
            const data = try allocator.dupe(u8, bytes);

            try c_consts.append(.{ .name = name.ptr, .data = data.ptr, .len = data.len });
            try anon_string_names.put(raw_key, name.ptr);
            anon_idx += 1;
        }
    }
}

pub const BuildState = struct {
    allocator: std.mem.Allocator,
    symbols: *const @import("../flattener/symbol.zig").SymbolTable,
    fsig: sig.FunctionSig,
    reg_operands_are_global_ids: bool,
    const_names: *const std.StringHashMap(void),
    anon_string_names: *const std.StringHashMap([*:0]const u8),
    function_sigs: []const sig.FunctionSig,
    function_sig_index: *const std.StringHashMap(usize),
    shared: *const SharedEmitTables,

    pub fn init(
        allocator: std.mem.Allocator,
        symbols: *const @import("../flattener/symbol.zig").SymbolTable,
        fsig: sig.FunctionSig,
        reg_operands_are_global_ids: bool,
        function_sigs: []const sig.FunctionSig,
        function_sig_index: *const std.StringHashMap(usize),
        shared: *const SharedEmitTables,
        anon_string_names: *const std.StringHashMap([*:0]const u8),
    ) BuildState {
        // No per-function table build: const_names is the prep-built shared
        // set (see SharedEmitTables), so this constructor cannot fail.
        return .{ .allocator = allocator, .symbols = symbols, .fsig = fsig, .reg_operands_are_global_ids = reg_operands_are_global_ids, .const_names = &shared.const_names, .anon_string_names = anon_string_names, .function_sigs = function_sigs, .function_sig_index = function_sig_index, .shared = shared };
    }

    pub fn calleeSig(self: *BuildState, name: []const u8) ?sig.FunctionSig {
        const idx = self.function_sig_index.get(name) orelse return null;
        return self.function_sigs[idx];
    }

    pub fn regGlobalId(self: *BuildState, slot_or_id: u32) !u32 {
        if (self.reg_operands_are_global_ids) return slot_or_id;
        const slot_index: usize = @intCast(slot_or_id);
        if (slot_index < self.fsig.reg_ids.len) return self.fsig.globalId(slot_or_id);
        return slot_or_id;
    }

    pub fn regSlot(self: *BuildState, slot_or_id: u32) !u32 {
        if (self.reg_operands_are_global_ids) {
            return self.fsig.slotOf(slot_or_id) orelse return error.InvalidOperand;
        }
        const slot_index: usize = @intCast(slot_or_id);
        if (slot_index < self.fsig.reg_ids.len) return slot_or_id;
        return self.fsig.slotOf(slot_or_id) orelse return error.InvalidOperand;
    }

    pub fn regName(self: *BuildState, slot_or_id: u32) ?[]const u8 {
        const global_id = self.regGlobalId(slot_or_id) catch return null;
        return self.symbols.lookupName(global_id);
    }

    pub fn lookupName(self: *BuildState, id: u32) ?[]const u8 {
        return self.regName(id);
    }

    pub fn operand(self: *BuildState, op: inst.Operand) !COperand {
        return switch (op) {
            .reg => |slot_or_id| .{ .kind = .reg, .reg = try self.regSlot(slot_or_id), .i64_value = 0, .u64_value = 0, .f64_value = 0, .ty = .i64, .name = null },
            .imm_i64 => |v| .{ .kind = .imm_i64, .reg = 0, .i64_value = v, .u64_value = 0, .f64_value = 0, .ty = .i64, .name = null },
            .imm_int => |v| .{ .kind = .imm_i64, .reg = 0, .i64_value = v, .u64_value = 0, .f64_value = 0, .ty = .i64, .name = null },
            .imm_u64 => |v| .{ .kind = .imm_u64, .reg = 0, .i64_value = 0, .u64_value = v, .f64_value = 0, .ty = .i64, .name = null },
            .imm_float => |v| .{ .kind = .imm_f64, .reg = 0, .i64_value = 0, .u64_value = 0, .f64_value = v, .ty = .f64, .name = null },
            .text => |text| try self.textOperand(text),
            else => error.InvalidOperand,
        };
    }

    pub fn callArgOperand(self: *BuildState, arg: call.ParsedArg) !COperand {
        if (isRawQuotedStringArg(arg)) {
            const name = self.anon_string_names.get(arg.text) orelse return error.InvalidOperand;
            return .{ .kind = .const_ptr, .reg = 0, .i64_value = 0, .u64_value = 0, .f64_value = 0, .ty = .ptr, .name = name };
        }
        return try self.textOperand(arg.text);
    }

    pub fn textOperand(self: *BuildState, raw: []const u8) !COperand {
        var text = std.mem.trim(u8, raw, " \t");
        if (text.len == 0) return error.InvalidOperand;
        if (text[0] == '&' or text[0] == '*' or text[0] == '^') text = std.mem.trim(u8, text[1..], " \t");
        const explicit_ty: ?CType = if (std.mem.lastIndexOf(u8, text, " as ")) |idx| blk: {
            const ty_text = std.mem.trim(u8, text[idx + 4 ..], " \t\r");
            text = std.mem.trim(u8, text[0..idx], " \t\r");
            break :blk if (std.mem.eql(u8, ty_text, "ptr"))
                .ptr
            else if (std.mem.eql(u8, ty_text, "i1"))
                .i1
            else if (std.mem.eql(u8, ty_text, "i8"))
                .i8
            else if (std.mem.eql(u8, ty_text, "u8"))
                .u8
            else if (std.mem.eql(u8, ty_text, "i16"))
                .i16
            else if (std.mem.eql(u8, ty_text, "u16"))
                .u16
            else if (std.mem.eql(u8, ty_text, "i32"))
                .i32
            else if (std.mem.eql(u8, ty_text, "u32"))
                .u32
            else if (std.mem.eql(u8, ty_text, "i64"))
                .i64
            else if (std.mem.eql(u8, ty_text, "u64"))
                .u64
            else if (std.mem.eql(u8, ty_text, "f32"))
                .f32
            else if (std.mem.eql(u8, ty_text, "f64"))
                .f64
            else
                null;
        } else null;
        if (std.fmt.parseInt(i64, text, 10)) |v| {
            return .{ .kind = .imm_i64, .reg = 0, .i64_value = v, .u64_value = 0, .f64_value = 0, .ty = explicit_ty orelse .i64, .name = null };
        } else |_| {}
        if (std.fmt.parseFloat(f64, text)) |v| {
            return .{ .kind = .imm_f64, .reg = 0, .i64_value = 0, .u64_value = 0, .f64_value = v, .ty = explicit_ty orelse .f64, .name = null };
        } else |_| {}
        if (self.const_names.contains(text)) {
            const z = try self.allocator.dupeSentinel(u8, text, 0);
            return .{ .kind = .const_ptr, .reg = 0, .i64_value = 0, .u64_value = 0, .f64_value = 0, .ty = .ptr, .name = z.ptr };
        }
        if (self.symbols.findId(text)) |id| {
            if (self.fsig.slotOf(id)) |slot| {
                return .{ .kind = .reg, .reg = slot, .i64_value = 0, .u64_value = 0, .f64_value = 0, .ty = .i64, .name = null };
            }
        }
        return error.InvalidOperand;
    }
};

pub fn labelNameZ(allocator: std.mem.Allocator, symbols: anytype, operand: inst.Operand) ![*:0]const u8 {
    const id = switch (operand) {
        .label => |v| v,
        else => return error.InvalidOperand,
    };
    const name = symbols.lookupName(id) orelse return error.InvalidOperand;
    return (try allocator.dupeSentinel(u8, name, 0)).ptr;
}

pub fn binaryOp(kind: inst.OpKind) !CBinaryOp {
    return switch (kind) {
        .add => .add,
        .sub => .sub,
        .mul => .mul,
        .sdiv, .div => .sdiv,
        .udiv => .udiv,
        .srem, .rem => .srem,
        .urem => .urem,
        .@"and" => .band,
        .@"or" => .bor,
        .xor => .xor,
        .shl => .shl,
        .lshr => .lshr,
        .ashr, .shr => .ashr,
        .eq => .eq,
        .ne => .ne,
        .slt, .lt => .slt,
        .sle => .sle,
        .sgt, .gt => .sgt,
        .sge => .sge,
        .ult => .ult,
        .ule => .ule,
        .ugt => .ugt,
        .uge => .uge,
        .fadd => .fadd,
        .fsub, .fneg => .fsub,
        .fmul => .fmul,
        .fdiv => .fdiv,
        .fcmp_eq => .fcmp_eq,
        .fcmp_ne => .fcmp_ne,
        .fcmp_lt => .fcmp_lt,
        .fcmp_le => .fcmp_le,
        .fcmp_gt => .fcmp_gt,
        .fcmp_ge => .fcmp_ge,
        else => error.UnsupportedInstruction,
    };
}

pub fn atomicOrdering(ordering: ?atomic.AtomicOrdering) CAtomicOrdering {
    return switch (ordering orelse .seq_cst) {
        .relaxed => .relaxed,
        .acquire => .acquire,
        .release => .release,
        .acq_rel => .acq_rel,
        .seq_cst => .seq_cst,
    };
}
