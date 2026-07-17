const std = @import("std");
const builtin = @import("builtin");

const call = @import("referee/call.zig");
const referee = @import("referee.zig");
const emit_options = @import("emit_options.zig");
const flattener = @import("flattener.zig");
const inst = @import("common/instruction.zig");
const atomic = @import("common/atomic.zig");
const sig = @import("common/signature.zig");
const const_decl = @import("common/const_decl.zig");
const upstream = @import("common/upstream_loc.zig");

extern fn sa_llvmc_free(ptr: ?*anyopaque) callconv(.C) void;
extern fn sa_llvmc_backend_version() callconv(.C) [*:0]const u8;
extern fn sa_llvmc_backend_target_triple() callconv(.C) ?[*:0]u8;
extern fn sa_llvmc_make_minimal_module_bitcode(out_bytes: *?[*]u8, out_len: *usize, out_error: *?[*:0]u8) callconv(.C) i32;
extern fn sa_llvmc_emit_module_bitcode(module: *const CModule, opt_level: c_int, out_bytes: *?[*]u8, out_len: *usize, out_error: *?[*:0]u8) callconv(.C) i32;
extern fn sa_llvmc_emit_module_object(module: *const CModule, out_path: [*:0]const u8, opt_level: c_int, out_error: *?[*:0]u8) callconv(.C) i32;
extern fn sa_llvmc_emit_module_artifacts(module: *const CModule, out_bitcode_path: [*:0]const u8, out_object_path: [*:0]const u8, opt_level: c_int, out_error: *?[*:0]u8) callconv(.C) i32;

pub const LlvmcError = error{ Failed, InvalidOperand, UnsupportedType, UnknownFunction, UnsupportedInstruction };
pub const EmitOptions = emit_options.EmitOptions;

const CType = enum(c_int) { void = 0, i1 = 1, i8 = 2, i16 = 3, i32 = 4, i64 = 5, f32 = 6, f64 = 7, ptr = 8, u8 = 9, u16 = 10, u32 = 11, u64 = 12 };
const CFuncKind = enum(c_int) { normal = 0, external = 1, exported = 2, test_func = 3 };
const COp = enum(c_int) { none = 0, label = 1, alloc = 2, stack_alloc = 3, load = 4, store = 5, op = 6, ptr_add = 7, jmp = 8, br = 9, call = 10, ret = 11, panic = 12, panic_msg = 13, atomic_load = 14, atomic_store = 15, atomic_rmw = 16, cmpxchg = 17, fence = 18, try_ = 19, call_indirect = 20, assign = 21, release = 22, take = 23 };
const COperandKind = enum(c_int) { none = 0, reg = 1, imm_i64 = 2, imm_u64 = 3, const_ptr = 4, imm_f64 = 5 };
const CBinaryOp = enum(c_int) { add = 0, sub = 1, mul = 2, sdiv = 3, udiv = 4, srem = 5, urem = 6, band = 7, bor = 8, xor = 9, shl = 10, lshr = 11, ashr = 12, eq = 13, ne = 14, slt = 15, sle = 16, sgt = 17, sge = 18, ult = 19, ule = 20, ugt = 21, uge = 22, fadd = 23, fsub = 24, fmul = 25, fdiv = 26, fcmp_eq = 27, fcmp_ne = 28, fcmp_lt = 29, fcmp_le = 30, fcmp_gt = 31, fcmp_ge = 32 };
const CAtomicOrdering = enum(c_int) { relaxed = 0, acquire = 1, release = 2, acq_rel = 3, seq_cst = 4 };
const CAtomicRmwOp = enum(c_int) { add = 0, sub = 1, band = 2, bor = 3, xor = 4, xchg = 5, min = 6, max = 7, umin = 8, umax = 9 };

const CConst = extern struct { name: [*:0]const u8, data: [*]const u8, len: usize };
const CVTable = extern struct { name: [*:0]const u8, funcs: [*]const [*:0]const u8, func_count: usize };
const CParam = extern struct { name: [*:0]const u8, ty: CType, slot: u32 };
const CDebugLoc = extern struct { line: u32, col: u32 };
const CDebugVar = extern struct { name: [*:0]const u8, ty: CType, slot: u32, is_param: bool, line: u32, col: u32 };
const COperand = extern struct { kind: COperandKind, reg: u32, i64_value: i64, u64_value: u64, f64_value: f64, ty: CType, name: ?[*:0]const u8 };
const CInstruction = extern struct {
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
};
const CFunction = extern struct {
    name: [*:0]const u8,
    kind: CFuncKind,
    ret_ty: CType,
    ret_ty2: CType = .void,
    return_fallible: bool,
    return_owned: bool,
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
    internal_symbol: bool,
};
const CModule = extern struct {
    size_bits: u16,
    wasm_compat: bool,
    test_mode: bool,
    debug: bool,
    is_cgu: bool,
    owns_process_globals: bool,
    source_file: ?[*:0]const u8,
    source_dir: ?[*:0]const u8,
    consts: [*]const CConst,
    const_count: usize,
    vtables: [*]const CVTable,
    vtable_count: usize,
    functions: [*]const CFunction,
    function_count: usize,
};

fn takeOwnedBitcode(allocator: std.mem.Allocator, bytes: *?[*]u8, len: *usize) ![]u8 {
    const ptr = bytes.* orelse return error.Failed;
    const out = try allocator.dupe(u8, ptr[0..len.*]);
    sa_llvmc_free(ptr);
    bytes.* = null;
    len.* = 0;
    return out;
}

fn cType(ty: sig.PrimType) !CType {
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

fn valueTypeForPrefix(prefix: inst.CapPrefix, ty: sig.PrimType) sig.PrimType {
    return switch (prefix) {
        .borrow, .raw => .ptr,
        .move, .by_value => ty,
    };
}

fn isRawQuotedStringArg(arg: call.ParsedArg) bool {
    return arg.prefix == .raw and arg.text.len >= 2 and arg.text[0] == '"' and arg.text[arg.text.len - 1] == '"';
}

fn parseHexDigitPair(text: []const u8) !u8 {
    if (text.len != 2) return error.InvalidOperand;
    const hi = std.fmt.charToDigit(text[0], 16) catch return error.InvalidOperand;
    const lo = std.fmt.charToDigit(text[1], 16) catch return error.InvalidOperand;
    return @as(u8, @intCast((hi << 4) | lo));
}

fn decodeQuotedBytes(allocator: std.mem.Allocator, raw: []const u8) ![]u8 {
    if (raw.len < 2 or raw[0] != '"' or raw[raw.len - 1] != '"') return error.InvalidOperand;

    var out = std.ArrayList(u8).init(allocator);
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

fn returnTypeForSig(return_cap: ?inst.CapPrefix, return_ty: sig.PrimType) sig.PrimType {
    if (return_ty == .void) return .void;
    return switch (return_cap orelse .by_value) {
        .raw, .borrow => .ptr,
        .move, .by_value => return_ty,
    };
}

fn emittedFunctionName(fsig: sig.FunctionSig) []const u8 {
    if (fsig.kind == .normal and fsig.params.len == 0 and std.mem.eql(u8, fsig.name, "main")) {
        return "saasm_main";
    }
    if (fsig.llvm_name) |name| return name;
    return fsig.name;
}

fn isInternalFunctionSig(fsig: sig.FunctionSig) bool {
    const internal_kind = fsig.kind == .normal or fsig.kind == .test_func;
    return internal_kind and !std.mem.eql(u8, emittedFunctionName(fsig), "saasm_main");
}

/// Identity for cached objects produced by the LLVM C backend. Bump the ABI
/// epoch whenever lowering, the Zig/C bridge, the pass pipeline, linkage, or
/// TargetMachine policy changes in a way that can alter object compatibility.
pub fn backendCacheIdentity(allocator: std.mem.Allocator) ![]u8 {
    const triple_ptr = sa_llvmc_backend_target_triple() orelse return error.Failed;
    defer sa_llvmc_free(triple_ptr);
    const partial_link_policy = if (builtin.os.tag == .linux)
        "elf-objcopy-localize-hidden-v1"
    else
        "namespaced-hidden-strong-v1";
    return try std.fmt.allocPrint(
        allocator,
        "llvmc-object-cache-abi/v11;llvm={s};triple={s};cpu=generic-v1;features=none;reloc=default;code-model=default;pipeline=legacy-pmb-v1;partial-link={s};function-anon-strings=local-collision-safe-v2;lowering-reg-delta=local-slots-v1;release-type=tracked-register-v1;indirect-return-ownership=signature-v1",
        .{ std.mem.span(sa_llvmc_backend_version()), std.mem.span(triple_ptr), partial_link_policy },
    );
}

fn buildEmittedFunctionNames(
    allocator: std.mem.Allocator,
    function_sigs: []const sig.FunctionSig,
    internal_symbol_namespace: []const u8,
) ![]const [*:0]const u8 {
    const names = try allocator.alloc([*:0]const u8, function_sigs.len);
    for (function_sigs, 0..) |fsig, index| {
        const base_name = emittedFunctionName(fsig);
        const name = if (internal_symbol_namespace.len != 0 and isInternalFunctionSig(fsig))
            try std.fmt.allocPrintZ(allocator, "__sa_internal_{s}_{s}", .{ internal_symbol_namespace, base_name })
        else
            try allocator.dupeZ(u8, base_name);
        names[index] = name.ptr;
    }
    return names;
}

fn sourceFileName(path: []const u8) []const u8 {
    return std.fs.path.basename(path);
}

fn sourceDirName(path: []const u8) []const u8 {
    return std.fs.path.dirname(path) orelse ".";
}

fn debugLocForInstruction(item: inst.Instruction, table_loc: ?upstream.UpstreamLoc, fallback: CDebugLoc) CDebugLoc {
    if (table_loc) |actual| return .{ .line = actual.line, .col = actual.col };
    if (item.upstream_loc) |actual| return .{ .line = actual.line, .col = actual.col };
    if (item.source_line != 0) return .{ .line = item.source_line, .col = 1 };
    return fallback;
}

fn makeSlotFallbackName(allocator: std.mem.Allocator, slot: usize) ![*:0]const u8 {
    const text = try std.fmt.allocPrintZ(allocator, "slot_{d}", .{slot});
    return text.ptr;
}

fn buildDebugVars(allocator: std.mem.Allocator, symbols: anytype, fsig: sig.FunctionSig, entry_loc: CDebugLoc) ![]CDebugVar {
    if (fsig.reg_ids.len == 0) return &.{};
    const vars = try allocator.alloc(CDebugVar, fsig.reg_ids.len);
    for (fsig.reg_ids, 0..) |reg_id, slot| {
        const raw_name = symbols.lookupName(reg_id);
        const name = if (raw_name) |value| (try allocator.dupeZ(u8, value)).ptr else try makeSlotFallbackName(allocator, slot);
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

fn constBytesLen(value: const_decl.ConstValue) !usize {
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

fn fillConstBytes(out: []u8, value: const_decl.ConstValue) !void {
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

fn allocateAnonStringName(
    allocator: std.mem.Allocator,
    occupied_global_names: *std.StringHashMap(void),
    anon_idx: *usize,
) ![:0]u8 {
    while (true) {
        const candidate = try std.fmt.allocPrintZ(allocator, ".sa.anon.{d}", .{anon_idx.*});
        anon_idx.* += 1;
        if (occupied_global_names.contains(candidate)) {
            allocator.free(candidate);
            continue;
        }
        errdefer allocator.free(candidate);
        try occupied_global_names.put(candidate, {});
        return candidate;
    }
}

fn collectAnonStringConsts(
    allocator: std.mem.Allocator,
    symbols: anytype,
    annotated: []const referee.AnnotatedInstruction,
    anon_string_names: *std.StringHashMap([*:0]const u8),
    occupied_global_names: *std.StringHashMap(void),
    c_consts: *std.ArrayList(CConst),
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
            const name = try allocateAnonStringName(allocator, occupied_global_names, &anon_idx);
            const data = try allocator.dupe(u8, bytes);

            try c_consts.append(.{ .name = name.ptr, .data = data.ptr, .len = data.len });
            try anon_string_names.put(raw_key, name.ptr);
        }
    }
}

fn collectAnonStringConstsForOptions(
    allocator: std.mem.Allocator,
    symbols: anytype,
    annotated: []const referee.AnnotatedInstruction,
    options: EmitOptions,
    anon_string_names: *std.StringHashMap([*:0]const u8),
    occupied_global_names: *std.StringHashMap(void),
    c_consts: *std.ArrayList(CConst),
) !void {
    const wanted_task_index = options.function_task_index orelse {
        return try collectAnonStringConsts(allocator, symbols, annotated, anon_string_names, occupied_global_names, c_consts);
    };

    var task_index: usize = 0;
    var index: usize = 0;
    while (index < annotated.len) {
        if (!isFunctionDeclaration(annotated[index].base.kind)) {
            index += 1;
            continue;
        }
        var end = index + 1;
        while (end < annotated.len and !isFunctionDeclaration(annotated[end].base.kind)) : (end += 1) {}
        if (task_index == wanted_task_index) {
            return try collectAnonStringConsts(allocator, symbols, annotated[index + 1 .. end], anon_string_names, occupied_global_names, c_consts);
        }
        task_index += 1;
        index = end;
    }
    return error.UnknownFunction;
}

const BuildState = struct {
    allocator: std.mem.Allocator,
    symbols: *const @import("flattener/symbol.zig").SymbolTable,
    fsig: sig.FunctionSig,
    reg_operands_are_global_ids: bool,
    const_names: std.StringHashMap(void),
    anon_string_names: *const std.StringHashMap([*:0]const u8),
    const_decls: []const const_decl.ConstDecl,
    function_sigs: []const sig.FunctionSig,
    function_sig_index: *const std.StringHashMap(usize),
    function_names: []const [*:0]const u8,

    fn init(
        allocator: std.mem.Allocator,
        symbols: *const @import("flattener/symbol.zig").SymbolTable,
        fsig: sig.FunctionSig,
        reg_operands_are_global_ids: bool,
        const_decls: []const const_decl.ConstDecl,
        function_sigs: []const sig.FunctionSig,
        function_sig_index: *const std.StringHashMap(usize),
        function_names: []const [*:0]const u8,
        anon_string_names: *const std.StringHashMap([*:0]const u8),
    ) !BuildState {
        var const_names = std.StringHashMap(void).init(allocator);
        errdefer const_names.deinit();
        for (const_decls) |decl| try const_names.put(decl.name, {});
        return .{ .allocator = allocator, .symbols = symbols, .fsig = fsig, .reg_operands_are_global_ids = reg_operands_are_global_ids, .const_names = const_names, .anon_string_names = anon_string_names, .const_decls = const_decls, .function_sigs = function_sigs, .function_sig_index = function_sig_index, .function_names = function_names };
    }

    fn deinit(self: *BuildState) void {
        self.const_names.deinit();
    }

    fn calleeSigIndex(self: *BuildState, name: []const u8) ?usize {
        return self.function_sig_index.get(name);
    }

    fn regGlobalId(self: *BuildState, slot_or_id: u32) !u32 {
        if (self.reg_operands_are_global_ids) return slot_or_id;
        const slot_index: usize = @intCast(slot_or_id);
        if (slot_index < self.fsig.reg_ids.len) return self.fsig.globalId(slot_or_id);
        return slot_or_id;
    }

    fn regSlot(self: *BuildState, slot_or_id: u32) !u32 {
        if (self.reg_operands_are_global_ids) {
            return self.fsig.slotOf(slot_or_id) orelse return error.InvalidOperand;
        }
        const slot_index: usize = @intCast(slot_or_id);
        if (slot_index < self.fsig.reg_ids.len) return slot_or_id;
        return self.fsig.slotOf(slot_or_id) orelse return error.InvalidOperand;
    }

    fn regName(self: *BuildState, slot_or_id: u32) ?[]const u8 {
        const global_id = self.regGlobalId(slot_or_id) catch return null;
        return self.symbols.lookupName(global_id);
    }

    pub fn lookupName(self: *BuildState, id: u32) ?[]const u8 {
        return self.regName(id);
    }

    fn operand(self: *BuildState, op: inst.Operand) !COperand {
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

    fn callArgOperand(self: *BuildState, arg: call.ParsedArg) !COperand {
        if (isRawQuotedStringArg(arg)) {
            const name = self.anon_string_names.get(arg.text) orelse return error.InvalidOperand;
            return .{ .kind = .const_ptr, .reg = 0, .i64_value = 0, .u64_value = 0, .f64_value = 0, .ty = .ptr, .name = name };
        }
        return try self.textOperand(arg.text);
    }

    fn textOperand(self: *BuildState, raw: []const u8) !COperand {
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
            const z = try self.allocator.dupeZ(u8, text);
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

fn labelNameZ(allocator: std.mem.Allocator, symbols: anytype, operand: inst.Operand) ![*:0]const u8 {
    const id = switch (operand) {
        .label => |v| v,
        else => return error.InvalidOperand,
    };
    const name = symbols.lookupName(id) orelse return error.InvalidOperand;
    return (try allocator.dupeZ(u8, name)).ptr;
}

fn binaryOp(kind: inst.OpKind) !CBinaryOp {
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

fn atomicOrdering(ordering: ?atomic.AtomicOrdering) CAtomicOrdering {
    return switch (ordering orelse .seq_cst) {
        .relaxed => .relaxed,
        .acquire => .acquire,
        .release => .release,
        .acq_rel => .acq_rel,
        .seq_cst => .seq_cst,
    };
}

fn atomicRmwOp(op: ?atomic.AtomicRmwOp) !CAtomicRmwOp {
    return switch (op orelse return error.InvalidOperand) {
        .add => .add,
        .sub => .sub,
        .@"and" => .band,
        .@"or" => .bor,
        .xor => .xor,
        .xchg => .xchg,
        .min => .min,
        .max => .max,
        .umin => .umin,
        .umax => .umax,
    };
}

fn atomicValueType(base: inst.Instruction, fallback: sig.PrimType) sig.PrimType {
    if (base.atomic_value_ty) |tag| {
        return sig.primTypeFromTag(tag) orelse fallback;
    }
    return fallback;
}

fn findFunctionSigIndex(sigs: []const sig.FunctionSig, name: []const u8) ?usize {
    for (sigs, 0..) |candidate, idx| {
        if (std.mem.eql(u8, candidate.name, name)) return idx;
        if (candidate.llvm_name) |llvm_name| {
            if (std.mem.eql(u8, llvm_name, name)) return idx;
        }
        if (std.mem.eql(u8, emittedFunctionName(candidate), name)) return idx;
    }
    return null;
}

fn putFunctionSigAlias(index: *std.StringHashMap(usize), name: []const u8, sig_idx: usize) !void {
    const entry = try index.getOrPut(name);
    if (!entry.found_existing) entry.value_ptr.* = sig_idx;
}

fn buildFunctionSigIndex(allocator: std.mem.Allocator, sigs: []const sig.FunctionSig) !std.StringHashMap(usize) {
    var index = std.StringHashMap(usize).init(allocator);
    errdefer index.deinit();
    const max_aliases = std.math.mul(usize, sigs.len, 3) catch sigs.len;
    try index.ensureTotalCapacity(@intCast(max_aliases));
    for (sigs, 0..) |candidate, idx| {
        try putFunctionSigAlias(&index, candidate.name, idx);
        if (candidate.llvm_name) |llvm_name| try putFunctionSigAlias(&index, llvm_name, idx);
        try putFunctionSigAlias(&index, emittedFunctionName(candidate), idx);
    }
    return index;
}

fn markReachableFunctionByName(
    reachable: *std.StringHashMap(void),
    sigs: []const sig.FunctionSig,
    sig_index: *const std.StringHashMap(usize),
    name: []const u8,
    newly_reachable: ?*std.ArrayList(usize),
) !bool {
    const idx = sig_index.get(name) orelse return false;
    const canonical_name = sigs[idx].name;
    if (reachable.contains(canonical_name)) return false;
    try reachable.put(canonical_name, {});
    if (newly_reachable) |work_queue| try work_queue.append(idx);
    return true;
}

fn collectVtableFunctionReferences(
    const_decls: []const const_decl.ConstDecl,
    function_sigs: []const sig.FunctionSig,
    sig_index: *const std.StringHashMap(usize),
    reachable: *std.StringHashMap(void),
) !void {
    for (const_decls) |decl| {
        switch (decl.value) {
            .vtable => |literal| {
                for (literal.slots) |slot| {
                    _ = try markReachableFunctionByName(reachable, function_sigs, sig_index, slot.func_name, null);
                }
            },
            else => {},
        }
    }
}

fn isFunctionReferenceDelimiter(byte: u8) bool {
    return std.ascii.isWhitespace(byte) or switch (byte) {
        '(', ')', '[', ']', '{', '}', ',', ':', ';', '=', '+', '*', '/', '&', '^', '<', '>', '!', '"', '\'' => true,
        else => false,
    };
}

fn collectTextFunctionReferences(
    verified: anytype,
    sig_index: *const std.StringHashMap(usize),
    text_value: []const u8,
    reachable: *std.StringHashMap(void),
    closure_complete: *bool,
    newly_reachable: ?*std.ArrayList(usize),
) !bool {
    var changed = false;
    var search_from: usize = 0;
    while (std.mem.indexOfScalarPos(u8, text_value, search_from, '@')) |at_index| {
        const name_start = at_index + 1;
        var name_end = name_start;
        while (name_end < text_value.len and !isFunctionReferenceDelimiter(text_value[name_end])) : (name_end += 1) {}
        search_from = @max(name_end, name_start);
        if (name_end == name_start) {
            closure_complete.* = false;
            continue;
        }

        const name = text_value[name_start..name_end];
        if (!sig_index.contains(name)) {
            closure_complete.* = false;
            continue;
        }
        changed = (try markReachableFunctionByName(reachable, verified.function_sigs, sig_index, name, newly_reachable)) or changed;
    }
    return changed;
}

fn collectInstructionFunctionReferences(
    verified: anytype,
    sig_index: *const std.StringHashMap(usize),
    base: inst.Instruction,
    reachable: *std.StringHashMap(void),
    closure_complete: *bool,
    newly_reachable: ?*std.ArrayList(usize),
) !bool {
    var changed = try collectTextFunctionReferences(verified, sig_index, base.raw_text, reachable, closure_complete, newly_reachable);
    for (base.operands) |operand| {
        switch (operand) {
            .func => |id| {
                const name = verified.symbols.lookupName(id) orelse {
                    closure_complete.* = false;
                    continue;
                };
                if (!sig_index.contains(name)) {
                    closure_complete.* = false;
                    continue;
                }
                changed = (try markReachableFunctionByName(reachable, verified.function_sigs, sig_index, name, newly_reachable)) or changed;
            },
            .text => |text_value| changed = (try collectTextFunctionReferences(verified, sig_index, text_value, reachable, closure_complete, newly_reachable)) or changed,
            .native_text => |text_value| changed = (try collectTextFunctionReferences(verified, sig_index, text_value, reachable, closure_complete, newly_reachable)) or changed,
            else => {},
        }
    }
    return changed;
}

fn collectBodyDirectCallees(
    allocator: std.mem.Allocator,
    verified: anytype,
    sig_index: *const std.StringHashMap(usize),
    start_idx: usize,
    end_idx: usize,
    reachable: *std.StringHashMap(void),
    closure_complete: ?*bool,
    newly_reachable: ?*std.ArrayList(usize),
) !bool {
    var changed = false;
    for (verified.annotated[start_idx..end_idx]) |body_item| {
        const base = body_item.base;
        if (closure_complete) |complete| {
            changed = (try collectInstructionFunctionReferences(verified, sig_index, base, reachable, complete, newly_reachable)) or changed;
        }
        if (base.kind != .call and base.kind != .call_indirect) continue;

        var parsed = call.parseInstructionCall(allocator, base, &verified.symbols) catch |err| switch (err) {
            error.InvalidCallSyntax => {
                if (closure_complete) |complete| complete.* = false;
                continue;
            },
            else => return err,
        };
        defer parsed.deinit(allocator);

        if (parsed.is_indirect) {
            if (closure_complete) |complete| complete.* = false;
            continue;
        }
        if (!sig_index.contains(parsed.callee)) {
            if (closure_complete) |complete| complete.* = false;
            continue;
        }
        changed = (try markReachableFunctionByName(reachable, verified.function_sigs, sig_index, parsed.callee, newly_reachable)) or changed;
    }
    return changed;
}

fn collectNormalBuildReachability(allocator: std.mem.Allocator, verified: anytype, sig_index_by_name: *const std.StringHashMap(usize), reachable: *std.StringHashMap(void)) !void {
    try collectVtableFunctionReferences(verified.const_decls, verified.function_sigs, sig_index_by_name, reachable);

    var sig_index: usize = 0;
    var idx: usize = 0;
    while (idx < verified.annotated.len) : (idx += 1) {
        const item = verified.annotated[idx].base;
        switch (item.kind) {
            .func_decl, .ffi_wrapper_decl, .extern_decl, .export_decl, .test_decl => {
                if (sig_index >= verified.function_sigs.len) return error.UnknownFunction;
                const fsig = verified.function_sigs[sig_index];
                sig_index += 1;

                const is_main = fsig.kind == .normal and std.mem.eql(u8, fsig.name, "main") and fsig.params.len == 0;
                const is_public_entry = item.kind == .export_decl or item.kind == .ffi_wrapper_decl or item.kind == .extern_decl;
                if (is_main or is_public_entry) {
                    try reachable.put(fsig.name, {});
                }
            },
            else => {},
        }
    }

    var changed = true;
    while (changed) {
        changed = false;
        sig_index = 0;
        idx = 0;
        while (idx < verified.annotated.len) : (idx += 1) {
            const item = verified.annotated[idx].base;
            switch (item.kind) {
                .func_decl, .ffi_wrapper_decl, .extern_decl, .export_decl, .test_decl => {
                    if (sig_index >= verified.function_sigs.len) return error.UnknownFunction;
                    const fsig = verified.function_sigs[sig_index];
                    sig_index += 1;
                    var end = idx + 1;
                    while (end < verified.annotated.len and switch (verified.annotated[end].base.kind) {
                        .func_decl, .ffi_wrapper_decl, .extern_decl, .export_decl, .test_decl => false,
                        else => true,
                    }) : (end += 1) {}

                    if (reachable.contains(fsig.name)) {
                        changed = (try collectBodyDirectCallees(allocator, verified, sig_index_by_name, idx + 1, end, reachable, null, null)) or changed;
                    }
                    idx = end - 1;
                },
                else => {},
            }
        }
    }
}

const FocusedFunctionBodyRange = struct {
    start: usize = 0,
    end: usize = 0,
    declared: bool = false,
};

fn isFunctionDeclaration(kind: inst.InstKind) bool {
    return switch (kind) {
        .func_decl, .ffi_wrapper_decl, .extern_decl, .export_decl, .test_decl => true,
        else => false,
    };
}

fn buildFocusedFunctionBodyRanges(allocator: std.mem.Allocator, verified: anytype, closure_complete: *bool) ![]FocusedFunctionBodyRange {
    const ranges = try allocator.alloc(FocusedFunctionBodyRange, verified.function_sigs.len);
    errdefer allocator.free(ranges);
    @memset(ranges, .{});

    var sig_index: usize = 0;
    var idx: usize = 0;
    while (idx < verified.annotated.len) {
        if (!isFunctionDeclaration(verified.annotated[idx].base.kind)) {
            idx += 1;
            continue;
        }
        if (sig_index >= ranges.len) {
            closure_complete.* = false;
            break;
        }
        var end = idx + 1;
        while (end < verified.annotated.len and !isFunctionDeclaration(verified.annotated[end].base.kind)) : (end += 1) {}
        ranges[sig_index] = .{ .start = idx + 1, .end = end, .declared = true };
        sig_index += 1;
        idx = end;
    }
    if (sig_index != ranges.len) closure_complete.* = false;
    return ranges;
}

fn collectSelectedTestReachability(
    allocator: std.mem.Allocator,
    verified: anytype,
    sig_index_by_name: *const std.StringHashMap(usize),
    selected_test_names: []const []const u8,
    reachable: *std.StringHashMap(void),
    body_scan_count: ?*usize,
) !bool {
    var closure_complete = true;
    const ranges = try buildFocusedFunctionBodyRanges(allocator, verified, &closure_complete);
    defer allocator.free(ranges);
    var work_queue = std.ArrayList(usize).init(allocator);
    defer work_queue.deinit();
    const processed = try allocator.alloc(bool, verified.function_sigs.len);
    defer allocator.free(processed);
    @memset(processed, false);

    for (verified.const_decls) |decl| {
        switch (decl.value) {
            .vtable => |literal| {
                for (literal.slots) |slot| {
                    if (!sig_index_by_name.contains(slot.func_name)) {
                        closure_complete = false;
                        continue;
                    }
                    _ = try markReachableFunctionByName(reachable, verified.function_sigs, sig_index_by_name, slot.func_name, &work_queue);
                }
            },
            else => {},
        }
    }

    for (selected_test_names) |name| {
        if (!sig_index_by_name.contains(name)) {
            closure_complete = false;
            continue;
        }
        _ = try markReachableFunctionByName(reachable, verified.function_sigs, sig_index_by_name, name, &work_queue);
    }

    var queue_index: usize = 0;
    while (queue_index < work_queue.items.len) : (queue_index += 1) {
        const sig_index = work_queue.items[queue_index];
        if (sig_index >= ranges.len or processed[sig_index]) continue;
        processed[sig_index] = true;
        const range = ranges[sig_index];
        if (!range.declared) {
            closure_complete = false;
            continue;
        }
        if (body_scan_count) |count| count.* += 1;
        _ = try collectBodyDirectCallees(
            allocator,
            verified,
            sig_index_by_name,
            range.start,
            range.end,
            reachable,
            &closure_complete,
            &work_queue,
        );
    }
    return closure_complete;
}

fn collectFocusedTestPruneReachability(
    allocator: std.mem.Allocator,
    verified: anytype,
    sig_index_by_name: *const std.StringHashMap(usize),
    selected_test_names: []const []const u8,
    reachable: *std.StringHashMap(void),
) !bool {
    const closure_complete = try collectSelectedTestReachability(allocator, verified, sig_index_by_name, selected_test_names, reachable, null);
    return closure_complete and reachable.count() != 0;
}

fn isPathSepByte(byte: u8) bool {
    return byte == '/' or byte == '\\';
}

fn trimTrailingPathSeps(path: []const u8) []const u8 {
    var end = path.len;
    while (end > 0 and isPathSepByte(path[end - 1])) : (end -= 1) {}
    return path[0..end];
}

fn pathIsUnderRoot(path: []const u8, root_path: []const u8) bool {
    const root = trimTrailingPathSeps(root_path);
    if (root.len == 0) return false;
    if (std.mem.eql(u8, path, root)) return true;
    return path.len > root.len and std.mem.startsWith(u8, path, root) and isPathSepByte(path[root.len]);
}

fn pathHasSegment(path: []const u8, segment: []const u8) bool {
    var start: usize = 0;
    while (start <= path.len) {
        var end = start;
        while (end < path.len and !isPathSepByte(path[end])) : (end += 1) {}
        if (std.mem.eql(u8, path[start..end], segment)) return true;
        if (end == path.len) break;
        start = end + 1;
    }
    return false;
}

fn functionSourcePath(fsig: sig.FunctionSig, source_path: []const u8) []const u8 {
    if (fsig.upstream_loc) |loc| return loc.file;
    if (fsig.upstream_file) |file| return file;
    return source_path;
}

fn functionHasStdOrigin(fsig: sig.FunctionSig, source_path: []const u8, std_root: ?[]const u8) bool {
    const path = functionSourcePath(fsig, source_path);
    if (std_root) |root| {
        if (pathIsUnderRoot(path, root)) return true;
    }
    return pathHasSegment(path, "sa_std");
}

fn markStdDceUserRoots(reachable: *std.StringHashMap(void), sigs: []const sig.FunctionSig, source_path: []const u8, std_root: ?[]const u8) !void {
    for (sigs) |fsig| {
        if (!functionHasStdOrigin(fsig, source_path, std_root)) try reachable.put(fsig.name, {});
    }
}

fn collectDceReachability(allocator: std.mem.Allocator, verified: anytype, sig_index_by_name: *const std.StringHashMap(usize), source_path: []const u8, options: EmitOptions, reachable: *std.StringHashMap(void)) !void {
    if (options.dce == .std) {
        try markStdDceUserRoots(reachable, verified.function_sigs, source_path, options.std_root);
    }
    try collectNormalBuildReachability(allocator, verified, sig_index_by_name, reachable);
}

fn shouldPruneUnreachableFunction(options: EmitOptions, fsig: sig.FunctionSig, source_path: []const u8) bool {
    return switch (options.dce) {
        .no => false,
        .full => true,
        .std => functionHasStdOrigin(fsig, source_path, options.std_root),
    };
}

pub fn collectIncrementalFunctionTaskIndices(
    allocator: std.mem.Allocator,
    verified: anytype,
    source_path: []const u8,
    options: EmitOptions,
) ![]usize {
    var function_sig_index = try buildFunctionSigIndex(allocator, verified.function_sigs);
    defer function_sig_index.deinit();
    var reachable = std.StringHashMap(void).init(allocator);
    defer reachable.deinit();

    var prune_unreachable = options.dce != .no;
    if (prune_unreachable) {
        try collectDceReachability(allocator, verified, &function_sig_index, source_path, options, &reachable);
        prune_unreachable = reachable.count() != 0;
    }

    var selected = std.ArrayList(usize).init(allocator);
    errdefer selected.deinit();
    var sig_index: usize = 0;
    var task_index: usize = 0;
    for (verified.annotated) |item| {
        const kind = item.base.kind;
        switch (kind) {
            .func_decl, .ffi_wrapper_decl, .extern_decl, .export_decl, .test_decl => {
                if (sig_index >= verified.function_sigs.len) return error.UnknownFunction;
                const fsig = verified.function_sigs[sig_index];
                sig_index += 1;
                const pruned = prune_unreachable and
                    !reachable.contains(fsig.name) and
                    shouldPruneUnreachableFunction(options, fsig, source_path);
                if (kind != .extern_decl and !pruned) try selected.append(task_index);
                task_index += 1;
            },
            else => {},
        }
    }
    if (sig_index != verified.function_sigs.len) return error.UnknownFunction;
    return try selected.toOwnedSlice();
}

fn usesSplitModuleSemantics(options: EmitOptions) bool {
    return options.codegen_unit_count > 1 or options.codegen_unit_index != null or options.function_task_index != null;
}

fn ownsProcessGlobals(options: EmitOptions, annotated: anytype) bool {
    if (options.function_task_owns_process_globals) |owns| return owns;
    if (options.function_task_index) |wanted_task_idx| {
        var task_idx: usize = 0;
        for (annotated) |item| {
            const kind = item.base.kind;
            switch (kind) {
                .func_decl, .ffi_wrapper_decl, .extern_decl, .export_decl, .test_decl => {
                    if (kind != .extern_decl) return task_idx == wanted_task_idx;
                    task_idx += 1;
                },
                else => {},
            }
        }
        return false;
    }
    if (options.codegen_unit_index) |cgu_idx| return cgu_idx == 0;
    return true;
}

fn functionSigShapeEqual(lhs: sig.FunctionSig, rhs: sig.FunctionSig) bool {
    if (lhs.return_cap != rhs.return_cap or lhs.return_ty != rhs.return_ty or lhs.return_ty2 != rhs.return_ty2 or lhs.return_fallible != rhs.return_fallible) return false;
    if (lhs.params.len != rhs.params.len) return false;
    for (lhs.params, rhs.params) |lparam, rparam| {
        if (lparam.cap != rparam.cap or lparam.ty != rparam.ty) return false;
    }
    return true;
}

fn offsetFromOperand(op: inst.Operand) ?u64 {
    return switch (op) {
        .imm_u64 => |v| v,
        .imm_i64, .imm_int => |v| if (v >= 0) @intCast(v) else null,
        else => null,
    };
}

fn slotTokenFromLoadText(raw: []const u8) ?[]const u8 {
    const plus = std.mem.indexOfScalar(u8, raw, '+') orelse return null;
    const tail = std.mem.trim(u8, raw[plus + 1 ..], " \t\r");
    const as_idx = std.mem.indexOf(u8, tail, " as ") orelse tail.len;
    const token = std.mem.trim(u8, tail[0..as_idx], " \t\r");
    return if (token.len == 0) null else token;
}

fn slotNameFromToken(token: []const u8) []const u8 {
    if (std.mem.lastIndexOfScalar(u8, token, '_')) |idx| {
        return token[idx + 1 ..];
    }
    return token;
}

fn normalizeIdentInto(buf: []u8, text: []const u8) []const u8 {
    var len: usize = 0;
    for (text) |ch| {
        if (std.ascii.isAlphanumeric(ch)) {
            if (len >= buf.len) break;
            buf[len] = std.ascii.toLower(ch);
            len += 1;
        }
    }
    return buf[0..len];
}

fn stripKnownTypeSuffix(text: []const u8) []const u8 {
    if (std.mem.endsWith(u8, text, "vtable")) return text[0 .. text.len - "vtable".len];
    if (std.mem.endsWith(u8, text, "vt")) return text[0 .. text.len - "vt".len];
    if (std.mem.endsWith(u8, text, "fn")) return text[0 .. text.len - "fn".len];
    return text;
}

fn slotPrefixKeyFromToken(buf: []u8, token: []const u8) []const u8 {
    const prefix = if (std.mem.lastIndexOfScalar(u8, token, '_')) |idx| token[0..idx] else return &.{};
    const normalized = normalizeIdentInto(buf, prefix);
    return stripKnownTypeSuffix(normalized);
}

fn normalizedContainsKey(buf: []u8, text: []const u8, key: []const u8) bool {
    if (key.len == 0) return false;
    const normalized = normalizeIdentInto(buf, text);
    return std.mem.indexOf(u8, normalized, key) != null;
}

fn chooseIndirectSigIndex(state: *BuildState, current: ?usize, candidate: usize) ?usize {
    if (current) |existing| {
        if (existing == candidate) return existing;
        if (functionSigShapeEqual(state.function_sigs[existing], state.function_sigs[candidate])) return existing;
        return null;
    }
    return candidate;
}

fn inferIndirectSigIndexFromSlot(state: *BuildState, slot_name: []const u8) ?usize {
    var resolved: ?usize = null;
    for (state.const_decls) |decl| {
        switch (decl.value) {
            .vtable => |literal| {
                for (literal.slots) |slot| {
                    if (!std.mem.eql(u8, slot.name, slot_name)) continue;
                    const idx = state.function_sig_index.get(slot.func_name) orelse continue;
                    resolved = chooseIndirectSigIndex(state, resolved, idx) orelse return null;
                }
            },
            else => {},
        }
    }
    return resolved;
}

fn inferIndirectSigIndexFromSlotWithPrefix(state: *BuildState, slot_name: []const u8, prefix_key: []const u8) ?usize {
    if (prefix_key.len == 0) return null;
    var resolved: ?usize = null;
    for (state.const_decls) |decl| {
        switch (decl.value) {
            .vtable => |literal| {
                var decl_buf: [256]u8 = undefined;
                const decl_match = normalizedContainsKey(&decl_buf, decl.name, prefix_key);
                for (literal.slots) |slot| {
                    if (!std.mem.eql(u8, slot.name, slot_name)) continue;
                    var func_buf: [256]u8 = undefined;
                    if (!decl_match and !normalizedContainsKey(&func_buf, slot.func_name, prefix_key)) continue;
                    const idx = state.function_sig_index.get(slot.func_name) orelse continue;
                    resolved = chooseIndirectSigIndex(state, resolved, idx) orelse return null;
                }
            },
            else => {},
        }
    }
    return resolved;
}

fn inferIndirectSigIndexFromOffset(state: *BuildState, offset: u64) ?usize {
    if (offset % 8 != 0) return null;
    const slot_index: usize = @intCast(offset / 8);
    var resolved: ?usize = null;
    for (state.const_decls) |decl| {
        switch (decl.value) {
            .vtable => |literal| {
                if (slot_index >= literal.slots.len) continue;
                const idx = state.function_sig_index.get(literal.slots[slot_index].func_name) orelse continue;
                resolved = chooseIndirectSigIndex(state, resolved, idx) orelse return null;
            },
            else => {},
        }
    }
    return resolved;
}

fn inferIndirectSigIndexFromLoad(state: *BuildState, base: inst.Instruction) ?usize {
    if (base.raw_text.len != 0) if (slotTokenFromLoadText(base.raw_text)) |token| {
        const slot = slotNameFromToken(token);
        var prefix_buf: [256]u8 = undefined;
        const prefix_key = slotPrefixKeyFromToken(&prefix_buf, token);
        if (inferIndirectSigIndexFromSlotWithPrefix(state, slot, prefix_key)) |idx| return idx;
        if (inferIndirectSigIndexFromSlot(state, slot)) |idx| return idx;
    };
    if (offsetFromOperand(base.operands[2])) |offset| {
        return inferIndirectSigIndexFromOffset(state, offset);
    }
    return null;
}

fn builtinReturnType(name: []const u8) ?CType {
    if (std.mem.eql(u8, name, "sys_argc")) return .i32;
    if (std.mem.eql(u8, name, "sys_argv")) return .ptr;
    if (std.mem.eql(u8, name, "sys_read_file")) return .ptr;
    if (std.mem.eql(u8, name, "sys_write_file")) return .i32;
    if (std.mem.eql(u8, name, "sys_print")) return .void;
    if (std.mem.eql(u8, name, "sys_exit")) return .void;
    if (std.mem.eql(u8, name, "sa_print_bytes")) return .void;
    return null;
}

fn assignTy(kind: inst.InstKind, value: COperand) CType {
    return switch (kind) {
        .raw_cast => .i64,
        .borrow, .assume_safe, .assume_borrow => .ptr,
        .assign => switch (value.kind) {
            .const_ptr => .ptr,
            .imm_i64, .imm_u64 => if (value.ty == .ptr) .ptr else .void,
            .imm_f64 => value.ty,
            else => .void,
        },
        else => .void,
    };
}

fn isFloatOp(opcode: inst.OpKind) bool {
    return switch (opcode) {
        .fadd, .fsub, .fmul, .fdiv, .fneg, .fcmp_eq, .fcmp_ne, .fcmp_lt, .fcmp_le, .fcmp_gt, .fcmp_ge => true,
        else => false,
    };
}

fn opConversionTy(base: inst.Instruction) !CType {
    if (base.operands[2] != .ty) return error.InvalidOperand;
    return try cType(sig.primTypeFromTag(base.operands[2].ty) orelse return error.InvalidOperand);
}

fn localizedRegName(state: *BuildState, slot_or_id: u32) ?[]const u8 {
    return state.regName(slot_or_id);
}

fn functionUsesGlobalRegIds(fsig: sig.FunctionSig, body: []const referee.AnnotatedInstruction) bool {
    for (body) |body_item| {
        for (body_item.base.operands) |operand| {
            if (operand == .reg) {
                const raw = operand.reg;
                if (raw >= fsig.reg_ids.len and fsig.slotOf(raw) != null) return true;
            }
        }
    }
    return false;
}

fn assignOperand(state: *BuildState, base: inst.Instruction) !COperand {
    return switch (base.operands[1]) {
        .reg => |id| blk: {
            if (localizedRegName(state, id)) |name| {
                if (state.const_names.contains(name)) break :blk try state.textOperand(name);
            }
            break :blk try state.operand(base.operands[1]);
        },
        .symbol => |id| blk: {
            const name = state.symbols.lookupName(id) orelse return error.InvalidOperand;
            break :blk try state.textOperand(name);
        },
        .func => |id| blk: {
            const name = state.symbols.lookupName(id) orelse return error.InvalidOperand;
            break :blk try state.textOperand(name);
        },
        .label => |id| blk: {
            const name = state.symbols.lookupName(id) orelse return error.InvalidOperand;
            break :blk try state.textOperand(name);
        },
        else => try state.operand(base.operands[1]),
    };
}

fn deltaMarksMalloc(changes: anytype, local_slot: u32) bool {
    const non_malloc_state_mask: u16 = 0x10 | 0x20 | 0x40 | 0x0200;
    for (changes) |change| {
        if (change.reg != local_slot) continue;
        return (change.after & non_malloc_state_mask) == 0;
    }
    return false;
}

fn lowerInstruction(allocator: std.mem.Allocator, state: *BuildState, body_item: referee.AnnotatedInstruction) !?CInstruction {
    const base = body_item.base;
    const none = COperand{ .kind = .none, .reg = 0, .i64_value = 0, .u64_value = 0, .f64_value = 0, .ty = .void, .name = null };
    const default_ordering: CAtomicOrdering = .seq_cst;
    const default_rmw: CAtomicRmwOp = .add;
    return switch (base.kind) {
        .label => .{ .op = .label, .dst = 0, .operand0 = none, .operand1 = none, .operand2 = none, .ty = .void, .binary_op = .add, .label = try labelNameZ(allocator, state.symbols, base.operands[1]), .false_label = null, .callee = null, .args = &.{}, .arg_count = 0, .indirect_param_tys = &.{}, .indirect_param_count = 0, .has_dst = false, .atomic_ordering = default_ordering, .atomic_second_ordering = default_ordering, .atomic_rmw_op = default_rmw, .return_fallible = false, .indirect_sig_index = std.math.maxInt(u32) },
        .alloc, .stack_alloc => |k| .{ .op = if (k == .alloc) .alloc else .stack_alloc, .dst = try state.regSlot(base.operands[0].reg), .operand0 = try state.operand(base.operands[1]), .operand1 = none, .operand2 = none, .ty = .ptr, .binary_op = .add, .label = null, .false_label = null, .callee = null, .args = &.{}, .arg_count = 0, .indirect_param_tys = &.{}, .indirect_param_count = 0, .has_dst = true, .atomic_ordering = default_ordering, .atomic_second_ordering = default_ordering, .atomic_rmw_op = default_rmw, .return_fallible = false, .indirect_sig_index = std.math.maxInt(u32), .is_malloc = (k == .alloc) },
        .load, .take => |k| blk: {
            const loaded_ty = if (base.operands[3] == .ty) sig.primTypeFromTag(base.operands[3].ty) orelse .i64 else sig.PrimType.i64;
            const indirect_sig_index: u32 = if (loaded_ty == .ptr)
                if (inferIndirectSigIndexFromLoad(state, base)) |idx| @intCast(idx) else std.math.maxInt(u32)
            else
                std.math.maxInt(u32);
            break :blk .{ .op = if (k == .load) .load else .take, .dst = try state.regSlot(base.operands[0].reg), .operand0 = try state.operand(base.operands[1]), .operand1 = try state.operand(base.operands[2]), .operand2 = none, .ty = try cType(loaded_ty), .binary_op = .add, .label = null, .false_label = null, .callee = null, .args = &.{}, .arg_count = 0, .indirect_param_tys = &.{}, .indirect_param_count = 0, .has_dst = true, .atomic_ordering = default_ordering, .atomic_second_ordering = default_ordering, .atomic_rmw_op = default_rmw, .return_fallible = false, .indirect_sig_index = indirect_sig_index, .is_malloc = (k == .take) };
        },
        .atomic_load => .{ .op = .atomic_load, .dst = try state.regSlot(base.operands[0].reg), .operand0 = try state.operand(base.operands[1]), .operand1 = try state.operand(base.operands[2]), .operand2 = none, .ty = try cType(atomicValueType(base, .i64)), .binary_op = .add, .label = null, .false_label = null, .callee = null, .args = &.{}, .arg_count = 0, .indirect_param_tys = &.{}, .indirect_param_count = 0, .has_dst = true, .atomic_ordering = atomicOrdering(base.atomic_ordering), .atomic_second_ordering = default_ordering, .atomic_rmw_op = default_rmw, .return_fallible = false, .indirect_sig_index = std.math.maxInt(u32) },
        .atomic_store => .{ .op = .atomic_store, .dst = 0, .operand0 = try state.operand(base.operands[0]), .operand1 = try state.operand(base.operands[1]), .operand2 = try state.operand(base.operands[2]), .ty = try cType(atomicValueType(base, .i64)), .binary_op = .add, .label = null, .false_label = null, .callee = null, .args = &.{}, .arg_count = 0, .indirect_param_tys = &.{}, .indirect_param_count = 0, .has_dst = false, .atomic_ordering = atomicOrdering(base.atomic_ordering), .atomic_second_ordering = default_ordering, .atomic_rmw_op = default_rmw, .return_fallible = false, .indirect_sig_index = std.math.maxInt(u32) },
        .atomic_rmw => .{ .op = .atomic_rmw, .dst = try state.regSlot(base.operands[0].reg), .operand0 = try state.operand(base.operands[1]), .operand1 = try state.operand(base.operands[2]), .operand2 = try state.operand(base.operands[3]), .ty = try cType(atomicValueType(base, .i64)), .binary_op = .add, .label = null, .false_label = null, .callee = null, .args = &.{}, .arg_count = 0, .indirect_param_tys = &.{}, .indirect_param_count = 0, .has_dst = true, .atomic_ordering = atomicOrdering(base.atomic_ordering), .atomic_second_ordering = default_ordering, .atomic_rmw_op = try atomicRmwOp(base.atomic_rmw_op), .return_fallible = false, .indirect_sig_index = std.math.maxInt(u32) },
        .cmpxchg => blk: {
            const args = try allocator.alloc(COperand, 2);
            args[0] = try state.textOperand(base.atomic_new_text orelse return error.InvalidOperand);
            args[1] = .{ .kind = .reg, .reg = try state.regSlot(base.operands[1].reg), .i64_value = 0, .u64_value = 0, .f64_value = 0, .ty = .i1, .name = null };
            break :blk .{ .op = .cmpxchg, .dst = try state.regSlot(base.operands[0].reg), .operand0 = try state.operand(base.operands[2]), .operand1 = try state.operand(base.operands[3]), .operand2 = try state.textOperand(base.atomic_expected_text orelse return error.InvalidOperand), .ty = try cType(atomicValueType(base, .i64)), .binary_op = .add, .label = null, .false_label = null, .callee = null, .args = args.ptr, .arg_count = args.len, .indirect_param_tys = &.{}, .indirect_param_count = 0, .has_dst = true, .atomic_ordering = atomicOrdering(base.atomic_ordering), .atomic_second_ordering = atomicOrdering(base.atomic_second_ordering), .atomic_rmw_op = default_rmw, .return_fallible = false, .indirect_sig_index = std.math.maxInt(u32) };
        },
        .fence => .{ .op = .fence, .dst = 0, .operand0 = none, .operand1 = none, .operand2 = none, .ty = .void, .binary_op = .add, .label = null, .false_label = null, .callee = null, .args = &.{}, .arg_count = 0, .indirect_param_tys = &.{}, .indirect_param_count = 0, .has_dst = false, .atomic_ordering = atomicOrdering(base.atomic_ordering), .atomic_second_ordering = default_ordering, .atomic_rmw_op = default_rmw, .return_fallible = false, .indirect_sig_index = std.math.maxInt(u32) },
        .store => .{ .op = .store, .dst = 0, .operand0 = try state.operand(base.operands[0]), .operand1 = try state.operand(base.operands[1]), .operand2 = try state.operand(base.operands[2]), .ty = if (base.operands[3] == .ty) try cType(sig.primTypeFromTag(base.operands[3].ty) orelse .i64) else .i64, .binary_op = .add, .label = null, .false_label = null, .callee = null, .args = &.{}, .arg_count = 0, .indirect_param_tys = &.{}, .indirect_param_count = 0, .has_dst = false, .atomic_ordering = default_ordering, .atomic_second_ordering = default_ordering, .atomic_rmw_op = default_rmw, .return_fallible = false, .indirect_sig_index = std.math.maxInt(u32) },
        .op => blk: {
            const opcode = base.op_kind orelse return error.InvalidOperand;
            if (inst.isTypeConversionOpKind(opcode)) {
                break :blk .{ .op = .assign, .dst = try state.regSlot(base.operands[0].reg), .operand0 = try state.operand(base.operands[1]), .operand1 = none, .operand2 = none, .ty = try opConversionTy(base), .binary_op = .add, .label = null, .false_label = null, .callee = null, .args = &.{}, .arg_count = 0, .indirect_param_tys = &.{}, .indirect_param_count = 0, .has_dst = true, .atomic_ordering = default_ordering, .atomic_second_ordering = default_ordering, .atomic_rmw_op = default_rmw, .return_fallible = false, .indirect_sig_index = std.math.maxInt(u32) };
            }
            if (opcode == .fneg) {
                break :blk .{ .op = .op, .dst = try state.regSlot(base.operands[0].reg), .operand0 = .{ .kind = .imm_f64, .reg = 0, .i64_value = 0, .u64_value = 0, .f64_value = 0.0, .ty = .f64, .name = null }, .operand1 = try state.operand(base.operands[1]), .operand2 = none, .ty = .f64, .binary_op = try binaryOp(opcode), .label = null, .false_label = null, .callee = null, .args = &.{}, .arg_count = 0, .indirect_param_tys = &.{}, .indirect_param_count = 0, .has_dst = true, .atomic_ordering = default_ordering, .atomic_second_ordering = default_ordering, .atomic_rmw_op = default_rmw, .return_fallible = false, .indirect_sig_index = std.math.maxInt(u32) };
            }
            break :blk .{ .op = .op, .dst = try state.regSlot(base.operands[0].reg), .operand0 = try state.operand(base.operands[1]), .operand1 = try state.operand(base.operands[2]), .operand2 = none, .ty = if (isFloatOp(opcode)) .f64 else .i64, .binary_op = try binaryOp(opcode), .label = null, .false_label = null, .callee = null, .args = &.{}, .arg_count = 0, .indirect_param_tys = &.{}, .indirect_param_count = 0, .has_dst = true, .atomic_ordering = default_ordering, .atomic_second_ordering = default_ordering, .atomic_rmw_op = default_rmw, .return_fallible = false, .indirect_sig_index = std.math.maxInt(u32) };
        },
        .ptr_add => .{ .op = .ptr_add, .dst = try state.regSlot(base.operands[0].reg), .operand0 = try state.operand(base.operands[1]), .operand1 = try state.operand(base.operands[2]), .operand2 = none, .ty = .ptr, .binary_op = .add, .label = null, .false_label = null, .callee = null, .args = &.{}, .arg_count = 0, .indirect_param_tys = &.{}, .indirect_param_count = 0, .has_dst = true, .atomic_ordering = default_ordering, .atomic_second_ordering = default_ordering, .atomic_rmw_op = default_rmw, .return_fallible = false, .indirect_sig_index = std.math.maxInt(u32) },
        .jmp => .{ .op = .jmp, .dst = 0, .operand0 = none, .operand1 = none, .operand2 = none, .ty = .void, .binary_op = .add, .label = try labelNameZ(allocator, state.symbols, base.operands[1]), .false_label = null, .callee = null, .args = &.{}, .arg_count = 0, .indirect_param_tys = &.{}, .indirect_param_count = 0, .has_dst = false, .atomic_ordering = default_ordering, .atomic_second_ordering = default_ordering, .atomic_rmw_op = default_rmw, .return_fallible = false, .indirect_sig_index = std.math.maxInt(u32) },
        .br => .{ .op = .br, .dst = 0, .operand0 = try state.operand(base.operands[0]), .operand1 = none, .operand2 = none, .ty = .void, .binary_op = .add, .label = try labelNameZ(allocator, state.symbols, base.operands[1]), .false_label = try labelNameZ(allocator, state.symbols, base.operands[3]), .callee = null, .args = &.{}, .arg_count = 0, .indirect_param_tys = &.{}, .indirect_param_count = 0, .has_dst = false, .atomic_ordering = default_ordering, .atomic_second_ordering = default_ordering, .atomic_rmw_op = default_rmw, .return_fallible = false, .indirect_sig_index = std.math.maxInt(u32) },
        .call, .call_indirect, .panic, .panic_msg => blk: {
            var parsed = call.parseInstructionCall(allocator, base, state) catch return error.InvalidOperand;
            defer parsed.deinit(allocator);
            if (base.kind == .panic) {
                if (parsed.args.len != 1) return error.InvalidOperand;
                break :blk .{ .op = .panic, .dst = 0, .operand0 = try state.callArgOperand(parsed.args[0]), .operand1 = none, .operand2 = none, .ty = .void, .binary_op = .add, .label = null, .false_label = null, .callee = null, .args = &.{}, .arg_count = 0, .indirect_param_tys = &.{}, .indirect_param_count = 0, .has_dst = false, .atomic_ordering = default_ordering, .atomic_second_ordering = default_ordering, .atomic_rmw_op = default_rmw, .return_fallible = false, .indirect_sig_index = std.math.maxInt(u32) };
            }
            if (base.kind == .panic_msg) {
                if (parsed.args.len != 3) return error.InvalidOperand;
                const panic_args = try allocator.alloc(COperand, 3);
                errdefer allocator.free(panic_args);
                panic_args[0] = try state.callArgOperand(parsed.args[0]);
                panic_args[1] = try state.callArgOperand(parsed.args[1]);
                panic_args[2] = try state.callArgOperand(parsed.args[2]);
                break :blk .{ .op = .call, .dst = 0, .operand0 = none, .operand1 = none, .operand2 = none, .ty = .void, .binary_op = .add, .label = null, .false_label = null, .callee = "panic_msg", .args = panic_args.ptr, .arg_count = panic_args.len, .indirect_param_tys = &.{}, .indirect_param_count = 0, .has_dst = false, .atomic_ordering = default_ordering, .atomic_second_ordering = default_ordering, .atomic_rmw_op = default_rmw, .return_fallible = false, .indirect_sig_index = std.math.maxInt(u32) };
            }
            if (base.kind != .call and base.kind != .call_indirect) break :blk .{ .op = .panic, .dst = 0, .operand0 = none, .operand1 = none, .operand2 = none, .ty = .void, .binary_op = .add, .label = null, .false_label = null, .callee = null, .args = &.{}, .arg_count = 0, .indirect_param_tys = &.{}, .indirect_param_count = 0, .has_dst = false, .atomic_ordering = default_ordering, .atomic_second_ordering = default_ordering, .atomic_rmw_op = default_rmw, .return_fallible = false, .indirect_sig_index = std.math.maxInt(u32) };
            const args = try allocator.alloc(COperand, parsed.args.len);
            for (parsed.args, 0..) |arg, idx| args[idx] = try state.callArgOperand(arg);
            const resolved_sig_index = state.calleeSigIndex(parsed.callee);
            const resolved = if (resolved_sig_index) |index| state.function_sigs[index] else null;
            const dst: u32 = if (parsed.dest) |dest| blk2: {
                const id = state.symbols.findId(dest) orelse return error.InvalidOperand;
                break :blk2 state.fsig.slotOf(id) orelse return error.InvalidOperand;
            } else 0;
            const is_malloc_val = parsed.dest != null and deltaMarksMalloc(body_item.delta.changes, dst);
            if (parsed.is_indirect) {
                const callee_op = try state.textOperand(parsed.callee);
                break :blk .{ .op = .call_indirect, .dst = dst, .operand0 = callee_op, .operand1 = none, .operand2 = none, .ty = .void, .binary_op = .add, .label = null, .false_label = null, .callee = null, .args = args.ptr, .arg_count = args.len, .indirect_param_tys = &.{}, .indirect_param_count = 0, .has_dst = parsed.dest != null, .atomic_ordering = default_ordering, .atomic_second_ordering = default_ordering, .atomic_rmw_op = default_rmw, .return_fallible = false, .indirect_sig_index = std.math.maxInt(u32), .is_malloc = is_malloc_val };
            }
            const callee = if (resolved_sig_index) |index|
                state.function_names[index]
            else
                (try allocator.dupeZ(u8, parsed.callee)).ptr;
            const call_ty = if (resolved) |resolved_sig| try cType(returnTypeForSig(resolved_sig.return_cap, resolved_sig.return_ty)) else builtinReturnType(parsed.callee) orelse CType.void;
            const call_fallible = if (resolved) |resolved_sig| resolved_sig.return_fallible else false;
            break :blk .{ .op = .call, .dst = dst, .operand0 = none, .operand1 = none, .operand2 = none, .ty = call_ty, .binary_op = .add, .label = null, .false_label = null, .callee = callee, .args = args.ptr, .arg_count = args.len, .indirect_param_tys = &.{}, .indirect_param_count = 0, .has_dst = parsed.dest != null, .atomic_ordering = default_ordering, .atomic_second_ordering = default_ordering, .atomic_rmw_op = default_rmw, .return_fallible = call_fallible, .indirect_sig_index = std.math.maxInt(u32), .is_malloc = is_malloc_val };
        },
        .try_, .early_return => .{ .op = .try_, .dst = try state.regSlot(base.operands[0].reg), .operand0 = try state.operand(base.operands[1]), .operand1 = none, .operand2 = none, .ty = try cType(returnTypeForSig(state.fsig.return_cap, state.fsig.return_ty)), .binary_op = .add, .label = null, .false_label = null, .callee = null, .args = &.{}, .arg_count = 0, .indirect_param_tys = &.{}, .indirect_param_count = 0, .has_dst = true, .atomic_ordering = default_ordering, .atomic_second_ordering = default_ordering, .atomic_rmw_op = default_rmw, .return_fallible = false, .indirect_sig_index = std.math.maxInt(u32) },
        .assign, .borrow, .raw_cast, .assume_safe, .assume_borrow => blk: {
            const value = try assignOperand(state, base);
            const assign_ty = assignTy(base.kind, value);
            const is_ptr = (assign_ty == .ptr);
            const dst = try state.regSlot(base.operands[0].reg);
            const is_malloc_val = is_ptr and deltaMarksMalloc(body_item.delta.changes, dst);
            break :blk .{ .op = .assign, .dst = dst, .operand0 = value, .operand1 = none, .operand2 = none, .ty = assign_ty, .binary_op = .add, .label = null, .false_label = null, .callee = null, .args = &.{}, .arg_count = 0, .indirect_param_tys = &.{}, .indirect_param_count = 0, .has_dst = true, .atomic_ordering = default_ordering, .atomic_second_ordering = default_ordering, .atomic_rmw_op = default_rmw, .return_fallible = false, .indirect_sig_index = std.math.maxInt(u32), .is_malloc = is_malloc_val };
        },
        .return_ => blk: {
            const has_second = state.fsig.return_ty2 != .void and base.operands[1] != .none;
            break :blk .{
                .op = .ret,
                .dst = 0,
                .operand0 = if (base.operands[0] == .none) none else try state.operand(base.operands[0]),
                .operand1 = if (has_second) try state.operand(base.operands[1]) else none,
                .operand2 = none,
                .ty = try cType(returnTypeForSig(state.fsig.return_cap, state.fsig.return_ty)),
                .binary_op = .add,
                .label = null,
                .false_label = null,
                .callee = null,
                .args = &.{},
                .arg_count = 0,
                .indirect_param_tys = &.{},
                .indirect_param_count = 0,
                .has_dst = base.operands[0] != .none,
                .atomic_ordering = default_ordering,
                .atomic_second_ordering = default_ordering,
                .atomic_rmw_op = default_rmw,
                .return_fallible = false,
                .indirect_sig_index = std.math.maxInt(u32),
            };
        },
        .move_ => null,
        .release => .{
            .op = .release,
            .dst = 0,
            .operand0 = try state.operand(base.operands[0]),
            .operand1 = none,
            .operand2 = none,
            .ty = .void,
            .binary_op = .add,
            .label = null,
            .false_label = null,
            .callee = null,
            .args = &.{},
            .arg_count = 0,
            .indirect_param_tys = &.{},
            .indirect_param_count = 0,
            .has_dst = false,
            .atomic_ordering = default_ordering,
            .atomic_second_ordering = default_ordering,
            .atomic_rmw_op = default_rmw,
            .return_fallible = false,
            .indirect_sig_index = std.math.maxInt(u32),
            .is_malloc = false,
        },
        else => error.UnsupportedInstruction,
    };
}

const ParallelEmitTask = struct {
    sig_index: usize,
    fsig: sig.FunctionSig,
    kind: CFuncKind,
    emit_main_wrapper: bool,
    start_idx: usize,
    end_idx: usize,
    decl_kind: inst.InstKind,
};

fn buildParallelEmitTasks(
    allocator: std.mem.Allocator,
    verified: anytype,
    source_path: []const u8,
    options: EmitOptions,
    function_sig_index: *const std.StringHashMap(usize),
) ![]ParallelEmitTask {
    var referenced_functions = std.StringHashMap(void).init(allocator);
    defer referenced_functions.deinit();

    const focused_test_prune = options.test_mode and options.selected_test_names.len != 0 and options.codegen_unit_index == null and options.function_task_index == null;
    var prune_unreachable = options.dce != .no and (!options.test_mode or focused_test_prune) and options.codegen_unit_index == null and options.function_task_index == null;
    if (focused_test_prune) {
        prune_unreachable = try collectFocusedTestPruneReachability(allocator, verified, function_sig_index, options.selected_test_names, &referenced_functions);
    } else if (prune_unreachable) {
        try collectDceReachability(allocator, verified, function_sig_index, source_path, options, &referenced_functions);
        prune_unreachable = referenced_functions.count() != 0;
    } else if (options.codegen_unit_index) |cgu_idx| {
        try collectVtableFunctionReferences(verified.const_decls, verified.function_sigs, function_sig_index, &referenced_functions);

        var sig_index: usize = 0;
        var idx: usize = 0;
        var task_idx: usize = 0;
        while (idx < verified.annotated.len) : (idx += 1) {
            const item = verified.annotated[idx].base;
            switch (item.kind) {
                .func_decl, .ffi_wrapper_decl, .extern_decl, .export_decl, .test_decl => {
                    if (sig_index >= verified.function_sigs.len) return error.UnknownFunction;
                    sig_index += 1;
                    var end = idx + 1;
                    while (end < verified.annotated.len and !isFunctionDeclaration(verified.annotated[end].base.kind)) : (end += 1) {}

                    if (task_idx % options.codegen_unit_count == cgu_idx) {
                        _ = try collectBodyDirectCallees(allocator, verified, function_sig_index, idx + 1, end, &referenced_functions, null, null);
                    }
                    task_idx += 1;
                    idx = end - 1;
                },
                else => {},
            }
        }
    } else if (options.function_task_index) |wanted_task_idx| {
        try collectVtableFunctionReferences(verified.const_decls, verified.function_sigs, function_sig_index, &referenced_functions);

        var sig_index: usize = 0;
        var idx: usize = 0;
        var task_idx: usize = 0;
        while (idx < verified.annotated.len) : (idx += 1) {
            const item = verified.annotated[idx].base;
            switch (item.kind) {
                .func_decl, .ffi_wrapper_decl, .extern_decl, .export_decl, .test_decl => {
                    if (sig_index >= verified.function_sigs.len) return error.UnknownFunction;
                    sig_index += 1;
                    var end = idx + 1;
                    while (end < verified.annotated.len and !isFunctionDeclaration(verified.annotated[end].base.kind)) : (end += 1) {}

                    if (task_idx == wanted_task_idx) {
                        _ = try collectBodyDirectCallees(allocator, verified, function_sig_index, idx + 1, end, &referenced_functions, null, null);
                    }
                    task_idx += 1;
                    idx = end - 1;
                },
                else => {},
            }
        }
    }

    var tasks = std.ArrayList(ParallelEmitTask).init(allocator);
    errdefer tasks.deinit();

    var sig_index: usize = 0;
    var idx: usize = 0;
    var task_idx: usize = 0;
    while (idx < verified.annotated.len) : (idx += 1) {
        const item = verified.annotated[idx].base;
        switch (item.kind) {
            .func_decl, .ffi_wrapper_decl, .extern_decl, .export_decl, .test_decl => {
                if (sig_index >= verified.function_sigs.len) return error.UnknownFunction;
                const current_sig_index = sig_index;
                const fsig = verified.function_sigs[sig_index];
                sig_index += 1;
                var end = idx + 1;
                while (end < verified.annotated.len and !isFunctionDeclaration(verified.annotated[end].base.kind)) : (end += 1) {}

                var c_kind: CFuncKind = switch (item.kind) {
                    .extern_decl => .external,
                    .export_decl => .exported,
                    .ffi_wrapper_decl => .exported,
                    .test_decl => .test_func,
                    else => .normal,
                };
                var emit_wrapper = !options.test_mode and fsig.kind == .normal and std.mem.eql(u8, fsig.name, "main") and fsig.params.len == 0;

                var should_include = true;
                if (options.function_task_index) |wanted_task_idx| {
                    if (task_idx != wanted_task_idx) {
                        c_kind = .external;
                        emit_wrapper = false;
                    }
                } else if (options.codegen_unit_index) |cgu_idx| {
                    if (task_idx % options.codegen_unit_count != cgu_idx) {
                        c_kind = .external;
                        emit_wrapper = false;
                    }
                } else if (prune_unreachable and !referenced_functions.contains(fsig.name)) {
                    if (focused_test_prune or shouldPruneUnreachableFunction(options, fsig, source_path)) should_include = false;
                }

                if (should_include) {
                    try tasks.append(.{
                        .sig_index = current_sig_index,
                        .fsig = fsig,
                        .kind = c_kind,
                        .emit_main_wrapper = emit_wrapper,
                        .start_idx = idx,
                        .end_idx = end,
                        .decl_kind = if (c_kind == .external) .extern_decl else item.kind,
                    });
                }
                task_idx += 1;
                idx = end - 1;
            },
            else => {},
        }
    }
    if (sig_index != verified.function_sigs.len) return error.UnknownFunction;
    return try tasks.toOwnedSlice();
}

const ParallelEmitJob = struct {
    arena: std.heap.ArenaAllocator,
    err: ?anyerror = null,
    result: ?CFunction = null,
};

fn ParallelEmitContext(comptime VerifiedType: type) type {
    return struct {
        allocator: std.mem.Allocator,
        verified: VerifiedType,
        loc_table: upstream.LocTable,
        source_path: []const u8,
        options: EmitOptions,
        anon_string_names: *const std.StringHashMap([*:0]const u8),
        function_sig_index: *const std.StringHashMap(usize),
        function_names: []const [*:0]const u8,
        tasks: []const ParallelEmitTask,
        jobs: []ParallelEmitJob,
        next_task: std.atomic.Value(usize),
    };
}

fn chooseEmitWorkerCount(requested_jobs: ?usize, task_count: usize) usize {
    if (task_count < 2) return 1;
    if (requested_jobs) |jobs| {
        return if (jobs <= 1) 1 else @min(jobs, task_count);
    }
    const cpu_count = std.Thread.getCpuCount() catch 1;
    return if (cpu_count <= 1) 1 else @min(cpu_count, task_count);
}

fn emitJobBackingAllocator(parent_allocator: std.mem.Allocator, worker_count: usize) std.mem.Allocator {
    return if (worker_count <= 1) parent_allocator else std.heap.page_allocator;
}

fn emitWorker(comptime VerifiedType: type, context_ptr: *anyopaque) void {
    const context: *ParallelEmitContext(VerifiedType) = @ptrCast(@alignCast(context_ptr));
    while (true) {
        const task_idx = context.next_task.fetchAdd(1, .monotonic);
        if (task_idx >= context.tasks.len) return;

        const task = context.tasks[task_idx];
        const job = &context.jobs[task_idx];
        const a = job.arena.allocator();

        const fsig = task.fsig;
        const entry_loc: CDebugLoc = if (fsig.upstream_loc) |loc|
            .{ .line = loc.line, .col = loc.col }
        else
            .{ .line = fsig.entry_inst_idx + 1, .col = 1 };

        const func_source_path = if (fsig.upstream_loc) |loc| loc.file else context.source_path;
        const func_source_file = a.dupeZ(u8, sourceFileName(func_source_path)) catch |err| {
            job.err = err;
            return;
        };
        const func_source_dir = a.dupeZ(u8, sourceDirName(func_source_path)) catch |err| {
            job.err = err;
            return;
        };

        const params = a.alloc(CParam, fsig.params.len) catch |err| {
            job.err = err;
            return;
        };
        for (fsig.params, 0..) |param, pidx| {
            const pname = a.dupeZ(u8, param.name) catch |err| {
                job.err = err;
                return;
            };
            const reg_id = fsig.param_ids[pidx];
            params[pidx] = .{ .name = pname.ptr, .ty = cType(valueTypeForPrefix(param.cap, param.ty)) catch |err| {
                job.err = err;
                return;
            }, .slot = fsig.slotOf(reg_id) orelse @intCast(pidx) };
        }

        const debug_vars = if (context.options.debug and task.decl_kind != .extern_decl)
            buildDebugVars(a, &context.verified.symbols, fsig, entry_loc) catch |err| {
                job.err = err;
                return;
            }
        else
            @as([]CDebugVar, &.{});

        var insts = std.ArrayList(CInstruction).init(a);
        var debug_locs = std.ArrayList(CDebugLoc).init(a);

        if (task.decl_kind != .extern_decl) {
            const body = context.verified.annotated[task.start_idx + 1 .. task.end_idx];
            var state = BuildState.init(a, &context.verified.symbols, fsig, functionUsesGlobalRegIds(fsig, body), context.verified.const_decls, context.verified.function_sigs, context.function_sig_index, context.function_names, context.anon_string_names) catch |err| {
                job.err = err;
                return;
            };
            defer state.deinit();
            for (body, task.start_idx + 1..) |body_item, annotated_idx| {
                if (lowerInstruction(a, &state, body_item) catch |err| {
                    job.err = err;
                    return;
                }) |ci| {
                    insts.append(ci) catch |err| {
                        job.err = err;
                        return;
                    };
                    if (context.options.debug) {
                        debug_locs.append(debugLocForInstruction(body_item.base, context.loc_table[annotated_idx], entry_loc)) catch |err| {
                            job.err = err;
                            return;
                        };
                    }
                }
            }
        }

        const ret_ty = cType(returnTypeForSig(fsig.return_cap, fsig.return_ty)) catch |err| {
            job.err = err;
            return;
        };
        const ret_ty2 = if (fsig.return_ty2 == .void) CType.void else (cType(fsig.return_ty2) catch |err| {
            job.err = err;
            return;
        });

        job.result = .{
            .name = context.function_names[task.sig_index],
            .kind = task.kind,
            .ret_ty = ret_ty,
            .ret_ty2 = ret_ty2,
            .return_fallible = fsig.return_fallible,
            .return_owned = fsig.return_cap == .move,
            .params = params.ptr,
            .param_count = params.len,
            .instructions = insts.items.ptr,
            .instruction_count = insts.items.len,
            .source_file = if (context.options.debug) func_source_file.ptr else null,
            .source_dir = if (context.options.debug) func_source_dir.ptr else null,
            .entry_line = if (context.options.debug) entry_loc.line else 0,
            .entry_col = if (context.options.debug) entry_loc.col else 0,
            .debug_locs = debug_locs.items.ptr,
            .debug_loc_count = if (context.options.debug) debug_locs.items.len else 0,
            .debug_vars = debug_vars.ptr,
            .debug_var_count = if (context.options.debug) debug_vars.len else 0,
            .emit_main_wrapper = task.emit_main_wrapper,
            .internal_symbol = isInternalFunctionSig(fsig),
        };
    }
}

fn emitLlvmcInternal(allocator: std.mem.Allocator, verified: anytype, def_dict: ?*const flattener.DefDict, loc_table: upstream.LocTable, source_path: []const u8, size_bits: u16, options: EmitOptions, obj_path: ?[]const u8, opt_level: u8) ![]const u8 {
    _ = def_dict;
    if (options.debug and loc_table.len != verified.annotated.len) return error.InvalidOperand;
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const module_source_file = try a.dupeZ(u8, sourceFileName(source_path));
    const module_source_dir = try a.dupeZ(u8, sourceDirName(source_path));
    var function_sig_index = try buildFunctionSigIndex(a, verified.function_sigs);
    const function_names = try buildEmittedFunctionNames(a, verified.function_sigs, options.internal_symbol_namespace);

    var c_consts = std.ArrayList(CConst).init(a);
    var c_vtables = std.ArrayList(CVTable).init(a);
    var anon_string_names = std.StringHashMap([*:0]const u8).init(a);
    var occupied_global_names = std.StringHashMap(void).init(a);
    for (function_names) |name| try occupied_global_names.put(std.mem.span(name), {});
    for (verified.const_decls) |decl| try occupied_global_names.put(decl.name, {});
    for (verified.const_decls) |decl| {
        switch (decl.value) {
            .vtable => |literal| {
                const funcs = try a.alloc([*:0]const u8, literal.slots.len);
                for (literal.slots, 0..) |slot, slot_idx| {
                    const sig_idx = function_sig_index.get(slot.func_name) orelse return error.UnknownFunction;
                    funcs[slot_idx] = function_names[sig_idx];
                }
                const name = try a.dupeZ(u8, decl.name);
                try c_vtables.append(.{ .name = name.ptr, .funcs = funcs.ptr, .func_count = funcs.len });
            },
            else => {
                const len = try constBytesLen(decl.value);
                const bytes = try a.alloc(u8, len);
                try fillConstBytes(bytes, decl.value);
                const name = try a.dupeZ(u8, decl.name);
                try c_consts.append(.{ .name = name.ptr, .data = bytes.ptr, .len = bytes.len });
            },
        }
    }
    try collectAnonStringConstsForOptions(a, &verified.symbols, verified.annotated, options, &anon_string_names, &occupied_global_names, &c_consts);

    const tasks = try buildParallelEmitTasks(a, verified, source_path, options, &function_sig_index);

    const worker_count = chooseEmitWorkerCount(options.jobs, tasks.len);
    const jobs = try a.alloc(ParallelEmitJob, tasks.len);
    const job_backing_allocator = emitJobBackingAllocator(allocator, worker_count);
    for (jobs) |*job| {
        job.* = .{ .arena = std.heap.ArenaAllocator.init(job_backing_allocator) };
    }
    defer {
        for (jobs) |*job| job.arena.deinit();
    }

    const VerifiedType = @TypeOf(verified);
    var context = ParallelEmitContext(VerifiedType){
        .allocator = allocator,
        .verified = verified,
        .loc_table = loc_table,
        .source_path = source_path,
        .options = options,
        .anon_string_names = &anon_string_names,
        .function_sig_index = &function_sig_index,
        .function_names = function_names,
        .tasks = tasks,
        .jobs = jobs,
        .next_task = std.atomic.Value(usize).init(0),
    };

    if (worker_count <= 1) {
        emitWorker(VerifiedType, &context);
    } else {
        const spawned_count = worker_count - 1;
        var threads = try a.alloc(std.Thread, spawned_count);
        var started_threads: usize = 0;
        errdefer {
            while (started_threads > 0) {
                started_threads -= 1;
                threads[started_threads].join();
            }
        }

        while (started_threads < spawned_count) : (started_threads += 1) {
            threads[started_threads] = try std.Thread.spawn(.{}, emitWorker, .{ VerifiedType, &context });
        }

        emitWorker(VerifiedType, &context);

        while (started_threads > 0) {
            started_threads -= 1;
            threads[started_threads].join();
        }
    }

    var c_funcs = std.ArrayList(CFunction).init(a);
    for (jobs) |job| {
        if (job.err) |err| return err;
        try c_funcs.append(job.result orelse return error.Failed);
    }

    const module = CModule{
        .size_bits = size_bits,
        .wasm_compat = options.wasm_compat,
        .test_mode = options.test_mode,
        .debug = options.debug,
        .is_cgu = usesSplitModuleSemantics(options),
        .owns_process_globals = ownsProcessGlobals(options, verified.annotated),
        .source_file = if (options.debug) module_source_file.ptr else null,
        .source_dir = if (options.debug) module_source_dir.ptr else null,
        .consts = c_consts.items.ptr,
        .const_count = c_consts.items.len,
        .vtables = c_vtables.items.ptr,
        .vtable_count = c_vtables.items.len,
        .functions = c_funcs.items.ptr,
        .function_count = c_funcs.items.len,
    };

    if (obj_path) |path| {
        const path_z = try a.dupeZ(u8, path);
        var err_msg: ?[*:0]u8 = null;
        if (sa_llvmc_emit_module_object(&module, path_z.ptr, @intCast(opt_level), &err_msg) != 0) {
            if (err_msg) |msg| {
                std.debug.print("llvmc object emit: {s}\n", .{std.mem.sliceTo(msg, 0)});
                sa_llvmc_free(msg);
            }
            return error.Failed;
        }
        return &[_]u8{};
    } else {
        var out_bytes: ?[*]u8 = null;
        var out_len: usize = 0;
        var err_msg: ?[*:0]u8 = null;
        if (sa_llvmc_emit_module_bitcode(&module, @intCast(options.opt_level), &out_bytes, &out_len, &err_msg) != 0) {
            if (err_msg) |msg| {
                std.debug.print("llvmc backend: {s}\n", .{std.mem.sliceTo(msg, 0)});
                sa_llvmc_free(msg);
            }
            return error.Failed;
        }
        errdefer if (out_bytes) |ptr| sa_llvmc_free(ptr);
        return try takeOwnedBitcode(allocator, &out_bytes, &out_len);
    }
}

pub fn emitLlvmc(allocator: std.mem.Allocator, verified: anytype, def_dict: ?*const flattener.DefDict, loc_table: upstream.LocTable, source_path: []const u8, size_bits: u16, options: EmitOptions) ![]const u8 {
    return emitLlvmcInternal(allocator, verified, def_dict, loc_table, source_path, size_bits, options, null, 0);
}

pub fn emitLlvmcToObject(allocator: std.mem.Allocator, verified: anytype, def_dict: ?*const flattener.DefDict, loc_table: upstream.LocTable, source_path: []const u8, size_bits: u16, options: EmitOptions, obj_path: []const u8, opt_level: u8) !void {
    _ = try emitLlvmcInternal(allocator, verified, def_dict, loc_table, source_path, size_bits, options, obj_path, opt_level);
}

pub fn emitLlvmcToArtifacts(allocator: std.mem.Allocator, verified: anytype, def_dict: ?*const flattener.DefDict, loc_table: upstream.LocTable, source_path: []const u8, size_bits: u16, options: EmitOptions, bitcode_path: []const u8, object_path: []const u8, opt_level: u8) !void {
    _ = def_dict;
    if (options.debug and loc_table.len != verified.annotated.len) return error.InvalidOperand;
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const module_source_file = try a.dupeZ(u8, sourceFileName(source_path));
    const module_source_dir = try a.dupeZ(u8, sourceDirName(source_path));
    var function_sig_index = try buildFunctionSigIndex(a, verified.function_sigs);
    const function_names = try buildEmittedFunctionNames(a, verified.function_sigs, options.internal_symbol_namespace);

    var c_consts = std.ArrayList(CConst).init(a);
    var c_vtables = std.ArrayList(CVTable).init(a);
    var anon_string_names = std.StringHashMap([*:0]const u8).init(a);
    var occupied_global_names = std.StringHashMap(void).init(a);
    for (function_names) |name| try occupied_global_names.put(std.mem.span(name), {});
    for (verified.const_decls) |decl| try occupied_global_names.put(decl.name, {});
    for (verified.const_decls) |decl| {
        switch (decl.value) {
            .vtable => |literal| {
                const funcs = try a.alloc([*:0]const u8, literal.slots.len);
                for (literal.slots, 0..) |slot, slot_idx| {
                    const sig_idx = function_sig_index.get(slot.func_name) orelse return error.UnknownFunction;
                    funcs[slot_idx] = function_names[sig_idx];
                }
                const name = try a.dupeZ(u8, decl.name);
                try c_vtables.append(.{ .name = name.ptr, .funcs = funcs.ptr, .func_count = funcs.len });
            },
            else => {
                const len = try constBytesLen(decl.value);
                const bytes = try a.alloc(u8, len);
                try fillConstBytes(bytes, decl.value);
                const name = try a.dupeZ(u8, decl.name);
                try c_consts.append(.{ .name = name.ptr, .data = bytes.ptr, .len = bytes.len });
            },
        }
    }
    try collectAnonStringConstsForOptions(a, &verified.symbols, verified.annotated, options, &anon_string_names, &occupied_global_names, &c_consts);

    const tasks = try buildParallelEmitTasks(a, verified, source_path, options, &function_sig_index);

    const worker_count = chooseEmitWorkerCount(options.jobs, tasks.len);
    const jobs = try a.alloc(ParallelEmitJob, tasks.len);
    const job_backing_allocator = emitJobBackingAllocator(allocator, worker_count);
    for (jobs) |*job| job.* = .{ .arena = std.heap.ArenaAllocator.init(job_backing_allocator) };
    defer for (jobs) |*job| job.arena.deinit();

    const VerifiedType = @TypeOf(verified);
    var context = ParallelEmitContext(VerifiedType){
        .allocator = allocator,
        .verified = verified,
        .loc_table = loc_table,
        .source_path = source_path,
        .options = options,
        .anon_string_names = &anon_string_names,
        .function_sig_index = &function_sig_index,
        .function_names = function_names,
        .tasks = tasks,
        .jobs = jobs,
        .next_task = std.atomic.Value(usize).init(0),
    };

    if (worker_count <= 1) {
        emitWorker(VerifiedType, &context);
    } else {
        const spawned_count = worker_count - 1;
        var threads = try a.alloc(std.Thread, spawned_count);
        var started_threads: usize = 0;
        errdefer {
            while (started_threads > 0) {
                started_threads -= 1;
                threads[started_threads].join();
            }
        }

        while (started_threads < spawned_count) : (started_threads += 1) {
            threads[started_threads] = try std.Thread.spawn(.{}, emitWorker, .{ VerifiedType, &context });
        }

        emitWorker(VerifiedType, &context);

        while (started_threads > 0) {
            started_threads -= 1;
            threads[started_threads].join();
        }
    }

    var c_funcs = std.ArrayList(CFunction).init(a);
    for (jobs) |job| {
        if (job.err) |err| return err;
        try c_funcs.append(job.result orelse return error.Failed);
    }

    const module = CModule{
        .size_bits = size_bits,
        .wasm_compat = options.wasm_compat,
        .test_mode = options.test_mode,
        .debug = options.debug,
        .is_cgu = usesSplitModuleSemantics(options),
        .owns_process_globals = ownsProcessGlobals(options, verified.annotated),
        .source_file = if (options.debug) module_source_file.ptr else null,
        .source_dir = if (options.debug) module_source_dir.ptr else null,
        .consts = c_consts.items.ptr,
        .const_count = c_consts.items.len,
        .vtables = c_vtables.items.ptr,
        .vtable_count = c_vtables.items.len,
        .functions = c_funcs.items.ptr,
        .function_count = c_funcs.items.len,
    };

    const bc_z = try a.dupeZ(u8, bitcode_path);
    const obj_z = try a.dupeZ(u8, object_path);
    var err_msg: ?[*:0]u8 = null;
    if (sa_llvmc_emit_module_artifacts(&module, bc_z.ptr, obj_z.ptr, @intCast(opt_level), &err_msg) != 0) {
        if (err_msg) |msg| {
            std.debug.print("llvmc artifact emit: {s}\n", .{std.mem.sliceTo(msg, 0)});
            sa_llvmc_free(msg);
        }
        return error.Failed;
    }
}

pub fn emitLlvmcToFile(allocator: std.mem.Allocator, verified: anytype, def_dict: ?*const flattener.DefDict, loc_table: upstream.LocTable, source_path: []const u8, size_bits: u16, options: EmitOptions, path: []const u8) !void {
    const verified_bitcode = try emitLlvmc(allocator, verified, def_dict, loc_table, source_path, size_bits, options);
    defer allocator.free(verified_bitcode);
    var file = if (std.fs.path.isAbsolute(path)) try std.fs.createFileAbsolute(path, .{ .truncate = true }) else try std.fs.cwd().createFile(path, .{ .truncate = true });
    defer file.close();
    try file.writeAll(verified_bitcode);
}

const FocusedReachabilityTestAnnotated = struct {
    base: inst.Instruction,
};

const FocusedReachabilityTestSymbols = struct {
    names: []const []const u8,

    pub fn lookupName(self: *const FocusedReachabilityTestSymbols, id: u32) ?[]const u8 {
        const index: usize = @intCast(id);
        if (index >= self.names.len) return null;
        return self.names[index];
    }
};

const FocusedReachabilityTestResult = struct {
    prune_enabled: bool,
    selected_reachable: bool,
    helper_reachable: bool,
    leaf_reachable: bool,
    unrelated_reachable: bool,
    body_scan_count: usize,
};

fn runFocusedReachabilityTest(body: inst.Instruction) !FocusedReachabilityTestResult {
    const function_sigs = [_]sig.FunctionSig{
        .{ .id = 0, .name = "selected", .params = &.{}, .kind = .test_func, .return_cap = null, .return_ty = .void, .entry_inst_idx = 0, .is_ffi_wrapper = false },
        .{ .id = 1, .name = "helper", .params = &.{}, .kind = .normal, .return_cap = null, .return_ty = .void, .entry_inst_idx = 3, .is_ffi_wrapper = false },
        .{ .id = 2, .name = "leaf", .params = &.{}, .kind = .normal, .return_cap = null, .return_ty = .void, .entry_inst_idx = 6, .is_ffi_wrapper = false },
        .{ .id = 3, .name = "unrelated", .params = &.{}, .kind = .normal, .return_cap = null, .return_ty = .void, .entry_inst_idx = 8, .is_ffi_wrapper = false },
    };
    const annotated = [_]FocusedReachabilityTestAnnotated{
        .{ .base = inst.makeInstruction(.test_decl, 1, 0, null, "@test selected():") },
        .{ .base = body },
        .{ .base = inst.makeInstruction(.return_, 3, 2, null, "return") },
        .{ .base = inst.makeInstruction(.func_decl, 4, 3, null, "@helper():") },
        .{ .base = inst.makeInstruction(.call, 5, 4, null, "call @leaf()") },
        .{ .base = inst.makeInstruction(.return_, 6, 5, null, "return") },
        .{ .base = inst.makeInstruction(.func_decl, 7, 6, null, "@leaf():") },
        .{ .base = inst.makeInstruction(.return_, 8, 7, null, "return") },
        .{ .base = inst.makeInstruction(.func_decl, 9, 8, null, "@unrelated():") },
        .{ .base = inst.makeInstruction(.return_, 10, 9, null, "return") },
    };
    var symbol_names = [_][]const u8{"helper"};
    const verified = .{
        .annotated = annotated[0..],
        .function_sigs = function_sigs[0..],
        .symbols = FocusedReachabilityTestSymbols{ .names = symbol_names[0..] },
        .const_decls = @as([]const const_decl.ConstDecl, &.{}),
    };

    var function_sig_index = try buildFunctionSigIndex(std.testing.allocator, function_sigs[0..]);
    defer function_sig_index.deinit();
    var reachable = std.StringHashMap(void).init(std.testing.allocator);
    defer reachable.deinit();

    var body_scan_count: usize = 0;
    const closure_complete = try collectSelectedTestReachability(std.testing.allocator, verified, &function_sig_index, &.{"selected"}, &reachable, &body_scan_count);
    const prune_enabled = closure_complete and reachable.count() != 0;
    return .{
        .prune_enabled = prune_enabled,
        .selected_reachable = reachable.contains("selected"),
        .helper_reachable = reachable.contains("helper"),
        .leaf_reachable = reachable.contains("leaf"),
        .unrelated_reachable = reachable.contains("unrelated"),
        .body_scan_count = body_scan_count,
    };
}

fn expectFocusedBitcodePrunedClosure(bitcode: []const u8) !void {
    try std.testing.expect(std.mem.indexOf(u8, bitcode, "selected") != null);
    try std.testing.expect(std.mem.indexOf(u8, bitcode, "helper") != null);
    try std.testing.expect(std.mem.indexOf(u8, bitcode, "leaf") != null);
    try std.testing.expect(std.mem.indexOf(u8, bitcode, "unrelated") == null);
}

fn runFocusedEmitPathDifferential(use_artifacts_path: bool) !void {
    const function_sigs = [_]sig.FunctionSig{
        .{ .id = 0, .name = "selected", .params = &.{}, .kind = .test_func, .return_cap = null, .return_ty = .void, .entry_inst_idx = 0, .is_ffi_wrapper = false },
        .{ .id = 1, .name = "helper", .params = &.{}, .kind = .normal, .return_cap = null, .return_ty = .void, .entry_inst_idx = 3, .is_ffi_wrapper = false },
        .{ .id = 2, .name = "leaf", .params = &.{}, .kind = .normal, .return_cap = null, .return_ty = .void, .entry_inst_idx = 6, .is_ffi_wrapper = false },
        .{ .id = 3, .name = "unrelated", .params = &.{}, .kind = .normal, .return_cap = null, .return_ty = .void, .entry_inst_idx = 8, .is_ffi_wrapper = false },
    };
    const annotated = [_]referee.AnnotatedInstruction{
        .{ .base = inst.makeInstruction(.test_decl, 1, 0, null, "@test selected():"), .delta = .{ .changes = &.{} }, .gas_step_cost = 1 },
        .{ .base = inst.makeInstruction(.call, 2, 1, null, "call @helper()"), .delta = .{ .changes = &.{} }, .gas_step_cost = 1 },
        .{ .base = inst.makeInstruction(.return_, 3, 2, null, "return"), .delta = .{ .changes = &.{} }, .gas_step_cost = 1 },
        .{ .base = inst.makeInstruction(.func_decl, 4, 3, null, "@helper():"), .delta = .{ .changes = &.{} }, .gas_step_cost = 1 },
        .{ .base = inst.makeInstruction(.call, 5, 4, null, "call @leaf()"), .delta = .{ .changes = &.{} }, .gas_step_cost = 1 },
        .{ .base = inst.makeInstruction(.return_, 6, 5, null, "return"), .delta = .{ .changes = &.{} }, .gas_step_cost = 1 },
        .{ .base = inst.makeInstruction(.func_decl, 7, 6, null, "@leaf():"), .delta = .{ .changes = &.{} }, .gas_step_cost = 1 },
        .{ .base = inst.makeInstruction(.return_, 8, 7, null, "return"), .delta = .{ .changes = &.{} }, .gas_step_cost = 1 },
        .{ .base = inst.makeInstruction(.func_decl, 9, 8, null, "@unrelated():"), .delta = .{ .changes = &.{} }, .gas_step_cost = 1 },
        .{ .base = inst.makeInstruction(.return_, 10, 9, null, "return"), .delta = .{ .changes = &.{} }, .gas_step_cost = 1 },
    };
    var symbols = @import("flattener/symbol.zig").SymbolTable.init(std.testing.allocator);
    defer symbols.deinit();
    const verified = .{
        .annotated = annotated[0..],
        .function_sigs = function_sigs[0..],
        .symbols = symbols,
        .const_decls = @as([]const const_decl.ConstDecl, &.{}),
    };
    const options = EmitOptions{
        .test_mode = true,
        .dce = .full,
        .selected_test_names = &.{"selected"},
        .jobs = 1,
    };

    if (!use_artifacts_path) {
        const bitcode = try emitLlvmc(std.testing.allocator, verified, null, &.{}, "/tmp/focused.sa", 64, options);
        defer std.testing.allocator.free(bitcode);
        try expectFocusedBitcodePrunedClosure(bitcode);
        return;
    }

    var original_cwd = try std.fs.cwd().openDir(".", .{});
    defer original_cwd.close();
    var tmp = std.testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();
    try tmp.dir.setAsCwd();
    defer original_cwd.setAsCwd() catch {};

    try emitLlvmcToArtifacts(std.testing.allocator, verified, null, &.{}, "/tmp/focused.sa", 64, options, "focused.bc", "focused.o", 0);
    const bitcode_file = try tmp.dir.openFile("focused.bc", .{});
    defer bitcode_file.close();
    const bitcode = try bitcode_file.readToEndAlloc(std.testing.allocator, 1 << 20);
    defer std.testing.allocator.free(bitcode);
    try expectFocusedBitcodePrunedClosure(bitcode);
}

test "function signature index preserves linear alias precedence" {
    const sigs = [_]sig.FunctionSig{
        .{ .id = 0, .name = "one", .params = &.{}, .kind = .normal, .return_cap = null, .return_ty = .void, .entry_inst_idx = 0, .is_ffi_wrapper = false, .llvm_name = "shared" },
        .{ .id = 1, .name = "shared", .params = &.{}, .kind = .normal, .return_cap = null, .return_ty = .void, .entry_inst_idx = 0, .is_ffi_wrapper = false },
        .{ .id = 2, .name = "main", .params = &.{}, .kind = .normal, .return_cap = null, .return_ty = .void, .entry_inst_idx = 0, .is_ffi_wrapper = false },
    };
    var index = try buildFunctionSigIndex(std.testing.allocator, sigs[0..]);
    defer index.deinit();

    try std.testing.expectEqual(@as(usize, 0), index.get("one").?);
    try std.testing.expectEqual(@as(usize, 0), index.get("shared").?);
    try std.testing.expectEqual(@as(usize, 2), index.get("main").?);
    try std.testing.expectEqual(@as(usize, 2), index.get("saasm_main").?);
}

test "function tasks use split module semantics" {
    try std.testing.expect(!usesSplitModuleSemantics(.{}));
    try std.testing.expect(usesSplitModuleSemantics(.{ .codegen_unit_index = 0 }));
    try std.testing.expect(usesSplitModuleSemantics(.{ .codegen_unit_count = 2 }));
    try std.testing.expect(usesSplitModuleSemantics(.{ .function_task_index = 0 }));
}

test "split module reachability includes every vtable slot function" {
    const function_sigs = [_]sig.FunctionSig{
        .{ .id = 0, .name = "draw", .params = &.{}, .kind = .normal, .return_cap = null, .return_ty = .void, .entry_inst_idx = 0, .is_ffi_wrapper = false },
        .{ .id = 1, .name = "drop", .params = &.{}, .kind = .normal, .return_cap = null, .return_ty = .void, .entry_inst_idx = 0, .is_ffi_wrapper = false },
        .{ .id = 2, .name = "unrelated", .params = &.{}, .kind = .normal, .return_cap = null, .return_ty = .void, .entry_inst_idx = 0, .is_ffi_wrapper = false },
    };
    var vtable = try const_decl.parseConstDecl(std.testing.allocator, "@const SHAPE_VT = vtable { draw = @draw, drop = @drop }", 1, 1, null);
    defer vtable.deinit(std.testing.allocator);

    var index = try buildFunctionSigIndex(std.testing.allocator, function_sigs[0..]);
    defer index.deinit();
    var reachable = std.StringHashMap(void).init(std.testing.allocator);
    defer reachable.deinit();

    try collectVtableFunctionReferences(&.{vtable}, function_sigs[0..], &index, &reachable);

    try std.testing.expect(reachable.contains("draw"));
    try std.testing.expect(reachable.contains("drop"));
    try std.testing.expect(!reachable.contains("unrelated"));
}

test "focused test prune keeps a complete direct-call closure" {
    const body = inst.makeInstruction(.call, 2, 1, null, "call @helper()");
    const result = try runFocusedReachabilityTest(body);

    try std.testing.expect(result.prune_enabled);
    try std.testing.expect(result.selected_reachable);
    try std.testing.expect(result.helper_reachable);
    try std.testing.expect(result.leaf_reachable);
    try std.testing.expect(!result.unrelated_reachable);
    try std.testing.expectEqual(@as(usize, 3), result.body_scan_count);
}

test "focused test prune scans self-recursive roots once" {
    const body = inst.makeInstruction(.call, 2, 1, null, "call @selected()");
    const result = try runFocusedReachabilityTest(body);

    try std.testing.expect(result.prune_enabled);
    try std.testing.expect(result.selected_reachable);
    try std.testing.expect(!result.helper_reachable);
    try std.testing.expect(!result.leaf_reachable);
    try std.testing.expect(!result.unrelated_reachable);
    try std.testing.expectEqual(@as(usize, 1), result.body_scan_count);
}

test "focused test prune applies to bitcode emit path" {
    try runFocusedEmitPathDifferential(false);
}

test "focused test prune applies to artifact emit path" {
    try runFocusedEmitPathDifferential(true);
}

test "focused test prune falls back for indirect invalid and unknown calls" {
    const indirect = try runFocusedReachabilityTest(inst.makeInstruction(.call_indirect, 2, 1, null, "call_indirect callback()"));
    try std.testing.expect(!indirect.prune_enabled);

    const invalid = try runFocusedReachabilityTest(inst.makeInstruction(.call, 2, 1, null, "call @"));
    try std.testing.expect(!invalid.prune_enabled);

    const unknown = try runFocusedReachabilityTest(inst.makeInstruction(.call, 2, 1, null, "call @missing()"));
    try std.testing.expect(!unknown.prune_enabled);
}

test "focused test prune tracks function operands and rejects unresolved addresses" {
    var known_body = inst.makeInstruction(.assign, 2, 1, null, "");
    known_body.operands[1] = .{ .func = 0 };
    const known = try runFocusedReachabilityTest(known_body);
    try std.testing.expect(known.prune_enabled);
    try std.testing.expect(known.helper_reachable);

    var unknown_body = inst.makeInstruction(.assign, 2, 1, null, "");
    unknown_body.operands[1] = .{ .func = 99 };
    const unknown = try runFocusedReachabilityTest(unknown_body);
    try std.testing.expect(!unknown.prune_enabled);
}

test "dce modes prune std and user functions at distinct levels" {
    const std_func = sig.FunctionSig{
        .id = 0,
        .name = "std_unused",
        .params = &.{},
        .kind = .normal,
        .return_cap = null,
        .return_ty = .void,
        .entry_inst_idx = 0,
        .is_ffi_wrapper = false,
        .upstream_file = "/tmp/app/sa_std/core/unused.sa",
    };
    const user_func = sig.FunctionSig{
        .id = 1,
        .name = "user_unused",
        .params = &.{},
        .kind = .normal,
        .return_cap = null,
        .return_ty = .void,
        .entry_inst_idx = 0,
        .is_ffi_wrapper = false,
        .upstream_file = "/tmp/app/src/user.sa",
    };

    const source_path = "/tmp/app/src/main.sa";
    try std.testing.expect(shouldPruneUnreachableFunction(.{ .dce = .std, .std_root = "/tmp/app/sa_std" }, std_func, source_path));
    try std.testing.expect(!shouldPruneUnreachableFunction(.{ .dce = .std, .std_root = "/tmp/app/sa_std" }, user_func, source_path));
    try std.testing.expect(shouldPruneUnreachableFunction(.{ .dce = .full, .std_root = "/tmp/app/sa_std" }, user_func, source_path));
    try std.testing.expect(!shouldPruneUnreachableFunction(.{ .dce = .no, .std_root = "/tmp/app/sa_std" }, std_func, source_path));
}

test "owned pointer deltas are matched by localized register slot" {
    const TestChange = struct { reg: u32, before: u16, after: u16 };
    const changes = [_]TestChange{
        .{ .reg = 7, .before = 0, .after = 1 },
        .{ .reg = 1, .before = 0, .after = 0x20 },
        .{ .reg = 2, .before = 0, .after = 1 },
    };

    try std.testing.expect(!deltaMarksMalloc(changes[0..], 1));
    try std.testing.expect(deltaMarksMalloc(changes[0..], 2));
    try std.testing.expect(deltaMarksMalloc(changes[0..], 7));
    try std.testing.expect(!deltaMarksMalloc(changes[0..], 3));
}

test "anonymous string names avoid occupied module symbols" {
    var occupied = std.StringHashMap(void).init(std.testing.allocator);
    defer occupied.deinit();
    try occupied.put(".sa.anon.1", {});

    var next_index: usize = 1;
    const name = try allocateAnonStringName(std.testing.allocator, &occupied, &next_index);
    defer {
        _ = occupied.remove(name);
        std.testing.allocator.free(name);
    }

    try std.testing.expectEqualStrings(".sa.anon.2", name);
    try std.testing.expectEqual(@as(usize, 3), next_index);
}

test "assignOperand resolves localized const vtable slots without raw text" {
    var symbols = flattener.SymbolTable.init(std.testing.allocator);
    defer symbols.deinit();
    const const_id = try symbols.intern("SLA_THREAD_VT_0");

    var anon_string_names = std.StringHashMap([*:0]const u8).init(std.testing.allocator);
    defer anon_string_names.deinit();
    var function_sig_index = std.StringHashMap(usize).init(std.testing.allocator);
    defer function_sig_index.deinit();

    const reg_ids = [_]u32{const_id};
    const fsig = sig.FunctionSig{
        .id = 0,
        .name = "wrap",
        .params = &.{},
        .kind = .ffi_wrapper,
        .return_cap = null,
        .return_ty = .void,
        .entry_inst_idx = 0,
        .is_ffi_wrapper = true,
        .reg_ids = reg_ids[0..],
    };

    var state = BuildState{
        .allocator = std.testing.allocator,
        .symbols = &symbols,
        .fsig = fsig,
        .reg_operands_are_global_ids = false,
        .const_names = std.StringHashMap(void).init(std.testing.allocator),
        .anon_string_names = &anon_string_names,
        .const_decls = &.{},
        .function_sigs = &.{},
        .function_sig_index = &function_sig_index,
        .function_names = &.{},
    };
    state.const_names = std.StringHashMap(void).init(std.testing.allocator);
    defer state.const_names.deinit();
    try state.const_names.put("SLA_THREAD_VT_0", {});

    var item = inst.makeInstruction(.borrow, 1, 0, null, "");
    item.operands[0] = .{ .reg = 1 };
    item.operands[1] = .{ .reg = 0 };

    const got = try assignOperand(&state, item);
    defer if (got.name) |name| std.testing.allocator.free(std.mem.span(name));
    try std.testing.expectEqual(COperandKind.const_ptr, got.kind);
    try std.testing.expect(got.name != null);
    try std.testing.expectEqualStrings("SLA_THREAD_VT_0", std.mem.sliceTo(got.name.?, 0));
}

test "llvmc backend can construct and write bitcode in memory" {
    var out_bytes: ?[*]u8 = null;
    var out_len: usize = 0;
    var err_msg: ?[*:0]u8 = null;
    try std.testing.expectEqual(@as(i32, 0), sa_llvmc_make_minimal_module_bitcode(&out_bytes, &out_len, &err_msg));
    defer if (err_msg) |msg| sa_llvmc_free(msg);
    defer if (out_bytes) |ptr| sa_llvmc_free(ptr);
    try std.testing.expect(out_bytes != null);
    try std.testing.expect(out_len > 0);
}

test "backend cache identity pins cpu and feature policy" {
    const identity = try backendCacheIdentity(std.testing.allocator);
    defer std.testing.allocator.free(identity);

    try std.testing.expect(std.mem.indexOf(u8, identity, "llvmc-object-cache-abi/v11;") != null);
    try std.testing.expect(std.mem.indexOf(u8, identity, "cpu=generic-v1;features=none;") != null);
    try std.testing.expect(std.mem.indexOf(u8, identity, "pipeline=legacy-pmb-v1;") != null);
    if (builtin.os.tag == .linux) {
        try std.testing.expect(std.mem.indexOf(u8, identity, "partial-link=elf-objcopy-localize-hidden-v1") != null);
    } else {
        try std.testing.expect(std.mem.indexOf(u8, identity, "partial-link=namespaced-hidden-strong-v1") != null);
    }
}
