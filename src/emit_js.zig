const std = @import("std");

const emit_options = @import("emit_options.zig");
const inst = @import("common/instruction.zig");
const sig = @import("common/signature.zig");
const call = @import("referee/call.zig");
const const_decl = @import("common/const_decl.zig");

pub const EmitOptions = emit_options.EmitOptions;
pub const JsEmitError = error{ Failed, InvalidOperand, UnknownFunction, UnsupportedInstruction, OutOfMemory };

/// Last instruction raw text seen by the emitter (diagnostics only).
pub threadlocal var last_js_inst: []const u8 = "";
pub threadlocal var last_js_func: []const u8 = "";

pub const JsFormat = enum {
    esm,
    cjs,

    pub fn parse(text: []const u8) ?JsFormat {
        if (std.mem.eql(u8, text, "esm") or std.mem.eql(u8, text, "mjs")) return .esm;
        if (std.mem.eql(u8, text, "cjs") or std.mem.eql(u8, text, "cjs")) return .cjs;
        return null;
    }
};

pub const JsEmitOptions = struct {
    format: JsFormat = .esm,
    mem_pages: u32 = 256, // 256 * 64KiB = 16MiB initial
    debug_comments: bool = true,
};

/// JS reserved words (strict-mode ESM): suffixed with `$` when emitted.
fn isJsReserved(name: []const u8) bool {
    const reserved = [_][]const u8{
        "break",       "case",     "catch",   "class",    "const",      "continue",
        "debugger",    "default",  "delete",  "do",       "else",       "enum",
        "export",      "extends",  "false",    "finally",  "for",        "function",
        "if",          "import",   "in",       "instanceof", "new",      "null",
        "return",      "super",    "switch",   "this",     "throw",      "true",
        "try",         "typeof",   "var",      "void",     "while",      "with",
        "yield",       "let",      "static",   "await",    "implements", "interface",
        "package",     "private",  "protected", "public",  "arguments",  "eval",
    };
    for (reserved) |word| {
        if (std.mem.eql(u8, name, word)) return true;
    }
    return false;
}

fn jsIdent(writer: anytype, name: []const u8) !void {
    // SA names may contain characters invalid in JS; sanitize.
    // Reserved words get a `$` suffix; note `jsFuncName` must apply the same
    // mapping to declarations and call sites consistently (both go through here).
    if (name.len == 0) return writer.writeAll("_anon");
    var first = true;
    for (name) |c| {
        const ok = std.ascii.isAlphanumeric(c) or c == '_' or c == '$';
        if (first) {
            if (std.ascii.isAlphabetic(c) or c == '_' or c == '$') {
                try writer.writeByte(c);
            } else {
                try writer.writeAll("_");
                if (ok) try writer.writeByte(c);
            }
            first = false;
        } else {
            if (ok) try writer.writeByte(c) else try writer.writeByte('_');
        }
    }
    if (isJsReserved(name)) try writer.writeAll("$");
}

fn jsFuncName(writer: anytype, name: []const u8) !void {
    // Strip surrounding quotes used by test funcs.
    var n = name;
    if (n.len >= 2 and n[0] == '"' and n[n.len - 1] == '"') n = n[1 .. n.len - 1];
    // Strip @ prefix used by callee names.
    if (n.len >= 1 and n[0] == '@') n = n[1..];
    try jsIdent(writer, n);
}

fn tagToPrim(tag: u32) sig.PrimType {
    return sig.primTypeFromTag(tag) orelse .i64;
}

/// Byte-flatten any data const (hex/utf8/repeat/struct_). Mirrors
/// emit_llvm_llvmc.constBytesLen/fillConstBytes so JS sees identical bytes.
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

/// JS identifier for a const's address slot: `C_<sanitized>`.
fn writeConstSlot(writer: anytype, name: []const u8) !void {
    try writer.writeAll("C_");
    try jsIdent(writer, name);
}

fn loadedPrimType(base: inst.Instruction) sig.PrimType {
    if (base.operands[3] == .ty) return tagToPrim(base.operands[3].ty);
    return .i64;
}

/// Element type for load/store/atomic memory ops. Atomics carry their type
/// in `atomic_value_ty` (mirrors emit_llvm_llvmc.atomicValueType).
fn memPrimType(base: inst.Instruction) sig.PrimType {
    if (base.kind == .atomic_load or base.kind == .atomic_store) {
        if (base.atomic_value_ty) |tag| return tagToPrim(tag);
        return .i64;
    }
    return loadedPrimType(base);
}

/// DataView helper per element type (exact width reads/writes).
fn memLoadFn(ty: sig.PrimType) []const u8 {
    return switch (ty) {
        .i1, .i8 => "__sa_load_i8",
        .u8 => "__sa_load_u8",
        .i16 => "__sa_load_i16",
        .u16 => "__sa_load_u16",
        .i32 => "__sa_load_i32",
        .u32 => "__sa_load_u32",
        .f32 => "__sa_load_f32",
        .f64 => "__sa_load_f64",
        .i64, .u64, .ptr, .blob_handle => "__sa_load_i64",
        else => "__sa_load_i32",
    };
}

fn memStoreFn(ty: sig.PrimType) []const u8 {
    return switch (ty) {
        .i1, .i8 => "__sa_store_i8",
        .u8 => "__sa_store_u8",
        .i16 => "__sa_store_i16",
        .u16 => "__sa_store_u16",
        .i32 => "__sa_store_i32",
        .u32 => "__sa_store_u32",
        .f32 => "__sa_store_f32",
        .f64 => "__sa_store_f64",
        .i64, .u64, .ptr, .blob_handle => "__sa_store_i64",
        else => "__sa_store_i32",
    };
}

fn opIsFloat(kind: inst.OpKind) bool {
    return switch (kind) {
        .fadd, .fsub, .fmul, .fdiv, .fneg, .fcmp_eq, .fcmp_ne, .fcmp_lt, .fcmp_le, .fcmp_gt, .fcmp_ge => true,
        else => false,
    };
}

const FuncTask = struct {
    fsig_index: usize,
    start_idx: usize, // index of func_decl in annotated
    end_idx: usize, // exclusive
    kind: inst.InstKind,
};

fn collectFuncTasks(allocator: std.mem.Allocator, verified: anytype) ![]FuncTask {
    var tasks = std.ArrayList(FuncTask).init(allocator);
    errdefer tasks.deinit();
    var sig_index: usize = 0;
    var idx: usize = 0;
    while (idx < verified.annotated.len) : (idx += 1) {
        const k = verified.annotated[idx].base.kind;
        switch (k) {
            .func_decl, .ffi_wrapper_decl, .extern_decl, .export_decl, .test_decl => {
                sig_index += 1;
                var end = idx + 1;
                while (end < verified.annotated.len) {
                    const nk = verified.annotated[end].base.kind;
                    switch (nk) {
                        .func_decl, .ffi_wrapper_decl, .extern_decl, .export_decl, .test_decl => break,
                        else => end += 1,
                    }
                }
                try tasks.append(.{
                    .fsig_index = sig_index - 1,
                    .start_idx = idx,
                    .end_idx = end,
                    .kind = k,
                });
                idx = end - 1;
            },
            else => {},
        }
    }
    return tasks.toOwnedSlice();
}

fn writeRuntimeHeader(writer: anytype, js_opt: JsEmitOptions, size_bits: u16) !void {
    const mem_bytes: usize = @as(usize, js_opt.mem_pages) * 65536;
    try writer.print("// Generated by `sa build-js` (js backend, MVP). DO NOT EDIT.\n", .{});
    try writer.print("// size_bits={d} pages={d} ({d} bytes linear memory)\n", .{ size_bits, js_opt.mem_pages, mem_bytes });
    try writer.writeAll(
        \\// ---- SA JS runtime (MVP, JEV: ArrayBuffer linear memory) ----
        \\const __SA_MEM_BYTES = __SA_MEM_BYTES_DECL__;
        \\const __sa_memory = new ArrayBuffer(__SA_MEM_BYTES);
        \\const __sa_view = new DataView(__sa_memory);
        \\const __sa_u8 = new Uint8Array(__sa_memory);
        \\let __sa_brk = 65536; // bump allocator starts after reserved zero page region
        \\function __sa_trap(msg) { throw new Error("[sa-trap] " + msg); }
        \\function __sa_panic(code) { throw new Error("[sa-panic] code=" + code); }
        \\function __sa_truthy(v) { return !!v; }
        \\function __sa_fok(t) { return ((t && typeof t === "object" && ("s" in t)) ? ((t.s | 0) === 0) : true); }
        \\function __sa_fv(t) { return ((t && typeof t === "object" && ("v" in t)) ? t.v : t); }
        \\function __sa_num(v) { return (typeof v === "bigint") ? Number(v) : (+v); }
        \\function __sa_addr(a) { return (typeof a === "bigint") ? Number(BigInt.asUintN(32, a)) : (a | 0); }
        \\function __sa_align(n, a) { return (n + (a - 1)) & ~(a - 1); }
        \\function __sa_alloc(size) {
        \\  size = __sa_align((size | 0), 8);
        \\  const ptr = __sa_brk;
        \\  __sa_brk += size;
        \\  if (__sa_brk >= __sa_memory.byteLength) __sa_trap("out of memory (bump)");
        \\  __sa_u8.fill(0, ptr, ptr + size);
        \\  return ptr | 0;
        \\}
        \\function __sa_load_i8(addr) { return __sa_view.getInt8(__sa_addr(addr)); }
        \\function __sa_load_u8(addr) { return __sa_view.getUint8(__sa_addr(addr)); }
        \\function __sa_load_i16(addr) { return __sa_view.getInt16(__sa_addr(addr), true); }
        \\function __sa_load_u16(addr) { return __sa_view.getUint16(__sa_addr(addr), true); }
        \\function __sa_load_i32(addr) { return __sa_view.getInt32(__sa_addr(addr), true); }
        \\function __sa_load_u32(addr) { return __sa_view.getUint32(__sa_addr(addr), true); }
        \\function __sa_load_f32(addr) { return __sa_view.getFloat32(__sa_addr(addr), true); }
        \\function __sa_load_f64(addr) { return __sa_view.getFloat64(__sa_addr(addr), true); }
        \\function __sa_store_i8(addr, v) { __sa_view.setInt8(__sa_addr(addr), v | 0); }
        \\function __sa_store_u8(addr, v) { __sa_view.setUint8(__sa_addr(addr), v | 0); }
        \\function __sa_store_i16(addr, v) { __sa_view.setInt16(__sa_addr(addr), v | 0, true); }
        \\function __sa_store_u16(addr, v) { __sa_view.setUint16(__sa_addr(addr), v | 0, true); }
        \\function __sa_store_i32(addr, v) { __sa_view.setInt32(__sa_addr(addr), v | 0, true); }
        \\function __sa_store_u32(addr, v) { __sa_view.setUint32(__sa_addr(addr), v >>> 0, true); }
        \\function __sa_store_f32(addr, v) { __sa_view.setFloat32(__sa_addr(addr), +v, true); }
        \\function __sa_store_f64(addr, v) { __sa_view.setFloat64(__sa_addr(addr), +v, true); }
        \\function __sa_load_i64(addr) { return __sa_view.getBigInt64(__sa_addr(addr), true); }
        \\function __sa_store_i64(addr, v) { __sa_view.setBigInt64(__sa_addr(addr), BigInt.asIntN(64, BigInt(v)), true); }
        \\function __sa_load_ptr(addr) { return __sa_load_i64(addr); }
        \\function __sa_store_ptr(addr, v) { __sa_store_i64(addr, v); }
        \\function __sa_ptr_add(ptr, off) {
        \\  if (typeof ptr === "bigint" || typeof off === "bigint") return BigInt.asIntN(64, BigInt(ptr) + BigInt(off));
        \\  return (ptr + off) | 0;
        \\}
        \\function __sa_i32(v) { return v | 0; }
        \\function __sa_i64(v) { return BigInt.asIntN(64, BigInt(v)); }
        \\function __sa_f64(v) { return +v; }
        \\function __sa_BI(v) { return BigInt.asIntN(64, BigInt(v)); }
        \\function __sa_BU(v) { return BigInt.asUintN(64, BigInt(v)); }
        \\function __sa_isBI(a, b) { return typeof a === "bigint" || typeof b === "bigint"; }
        \\function __sa_add(a, b) { return __sa_isBI(a, b) ? __sa_BI(BigInt(a) + BigInt(b)) : (((+a) + (+b)) | 0); }
        \\function __sa_sub(a, b) { return __sa_isBI(a, b) ? __sa_BI(BigInt(a) - BigInt(b)) : (((+a) - (+b)) | 0); }
        \\function __sa_mul(a, b) { return __sa_isBI(a, b) ? __sa_BI(BigInt(a) * BigInt(b)) : Math.imul(a, b); }
        \\function __sa_sdiv(a, b) { if (__sa_isBI(a, b)) { if (BigInt(b) === 0n) __sa_trap("div by zero"); return __sa_BI(BigInt(a) / BigInt(b)); } if ((b | 0) === 0) __sa_trap("div by zero"); return (Math.trunc(a / b)) | 0; }
        \\function __sa_udiv(a, b) { if (__sa_isBI(a, b)) { const d = __sa_BU(b); if (d === 0n) __sa_trap("div by zero"); return __sa_BU(BigInt(a) / d); } if ((b >>> 0) === 0) __sa_trap("div by zero"); return (Math.trunc((a >>> 0) / (b >>> 0))) | 0; }
        \\function __sa_srem(a, b) { return __sa_isBI(a, b) ? __sa_BI(BigInt(a) % BigInt(b)) : ((a % b) | 0); }
        \\function __sa_urem(a, b) { if (__sa_isBI(a, b)) { const d = __sa_BU(b); if (d === 0n) __sa_trap("rem by zero"); return __sa_BU(BigInt(a) % d); } return (((a >>> 0) % (b >>> 0)) | 0); }
        \\function __sa_neg(a) { return (typeof a === "bigint") ? __sa_BI(-a) : ((-a) | 0); }
        \\function __sa_band(a, b) { return __sa_isBI(a, b) ? __sa_BI(BigInt(a) & BigInt(b)) : ((a & b) | 0); }
        \\function __sa_bor(a, b) { return __sa_isBI(a, b) ? __sa_BI(BigInt(a) | BigInt(b)) : ((a | b) | 0); }
        \\function __sa_bxor(a, b) { return __sa_isBI(a, b) ? __sa_BI(BigInt(a) ^ BigInt(b)) : ((a ^ b) | 0); }
        \\function __sa_shl(a, b) { return __sa_isBI(a, b) ? __sa_BI(BigInt(a) << (BigInt(b) & 63n)) : ((a << (b & 31)) | 0); }
        \\function __sa_lshr(a, b) { return __sa_isBI(a, b) ? __sa_BU(BigInt(a) >> (BigInt(b) & 63n)) : ((a >>> (b & 31)) | 0); }
        \\function __sa_ashr(a, b) { return __sa_isBI(a, b) ? __sa_BI(BigInt(a) >> (BigInt(b) & 63n)) : ((a >> (b & 31)) | 0); }
        \\function __sa_bnot(a) { return (typeof a === "bigint") ? __sa_BI(~a) : ((~a) | 0); }
        \\function __sa_eq(a, b) { return ((a == b) ? 1 : 0); }
        \\function __sa_ne(a, b) { return ((a != b) ? 1 : 0); }
        \\function __sa_slt(a, b) { return ((__sa_isBI(a, b) ? (BigInt(a) < BigInt(b)) : ((a | 0) < (b | 0))) ? 1 : 0); }
        \\function __sa_sle(a, b) { return ((__sa_isBI(a, b) ? (BigInt(a) <= BigInt(b)) : ((a | 0) <= (b | 0))) ? 1 : 0); }
        \\function __sa_sgt(a, b) { return ((__sa_isBI(a, b) ? (BigInt(a) > BigInt(b)) : ((a | 0) > (b | 0))) ? 1 : 0); }
        \\function __sa_sge(a, b) { return ((__sa_isBI(a, b) ? (BigInt(a) >= BigInt(b)) : ((a | 0) >= (b | 0))) ? 1 : 0); }
        \\function __sa_ult(a, b) { return ((__sa_isBI(a, b) ? (__sa_BU(a) < __sa_BU(b)) : ((a >>> 0) < (b >>> 0))) ? 1 : 0); }
        \\function __sa_ule(a, b) { return ((__sa_isBI(a, b) ? (__sa_BU(a) <= __sa_BU(b)) : ((a >>> 0) <= (b >>> 0))) ? 1 : 0); }
        \\function __sa_ugt(a, b) { return ((__sa_isBI(a, b) ? (__sa_BU(a) > __sa_BU(b)) : ((a >>> 0) > (b >>> 0))) ? 1 : 0); }
        \\function __sa_uge(a, b) { return ((__sa_isBI(a, b) ? (__sa_BU(a) >= __sa_BU(b)) : ((a >>> 0) >= (b >>> 0))) ? 1 : 0); }
        \\function __sa_fadd(a, b) { return ((+a) + (+b)); }
        \\function __sa_fsub(a, b) { return ((+a) - (+b)); }
        \\function __sa_fmul(a, b) { return ((+a) * (+b)); }
        \\function __sa_fdiv(a, b) { return ((+a) / (+b)); }
        \\function __sa_fneg(a) { return (-(+a)); }
        \\function __sa_feq(a, b) { return (((+a) === (+b)) ? 1 : 0); }
        \\function __sa_fne(a, b) { return (((+a) !== (+b)) ? 1 : 0); }
        \\function __sa_flt(a, b) { return (((+a) < (+b)) ? 1 : 0); }
        \\function __sa_fle(a, b) { return (((+a) <= (+b)) ? 1 : 0); }
        \\function __sa_fgt(a, b) { return (((+a) > (+b)) ? 1 : 0); }
        \\function __sa_fge(a, b) { return (((+a) >= (+b)) ? 1 : 0); }
        \\function __sa_cvt(v) { return v; }
        \\// ---- end runtime ----
        \\
    );
}

/// Resolve raw call-arg text (`&name`, `10`, `3.5`, `"str"`) to a JS expr.
/// Mirrors emit_llvm_llvmc.textOperand: int/float literal, else symbol slot.
fn resolveTextToJs(writer: anytype, symbols: anytype, fsig: sig.FunctionSig, const_addrs: anytype, raw: []const u8) !void {
    var text = std.mem.trim(u8, raw, " \t");
    if (text.len == 0) return JsEmitError.InvalidOperand;
    if (text[0] == '&' or text[0] == '*' or text[0] == '^') text = std.mem.trim(u8, text[1..], " \t");
    if (std.mem.lastIndexOf(u8, text, " as ")) |idx| {
        text = std.mem.trim(u8, text[0..idx], " \t\r");
    }
    if (text.len == 0) return JsEmitError.InvalidOperand;
    if (std.fmt.parseInt(i64, text, 10)) |v| {
        try writer.print("{d}", .{v});
        return;
    } else |_| {}
    if (std.fmt.parseFloat(f64, text)) |v| {
        try writer.print("{d}", .{v});
        return;
    } else |_| {}
    // Static consts live at fixed linear-memory addresses (mirrors
    // emit_llvm_llvmc.textOperand checking const_names before symbols).
    if (const_addrs.get(text)) |_| {
        try writeConstSlot(writer, text);
        return;
    }
    if (symbols.findId(text)) |id| {
        if (fsig.slotOf(id)) |slot| {
            try writer.print("r{d}", .{slot});
            return;
        }
    }
    return JsEmitError.InvalidOperand;
}

/// Resolve any value operand to a JS expression.
fn resolveValueToJs(writer: anytype, symbols: anytype, fsig: sig.FunctionSig, use_global: bool, const_addrs: anytype, op: inst.Operand) !void {
    switch (op) {
        .reg => |r| {
            const slot = try regSlot(fsig, use_global, r);
            try writer.print("r{d}", .{slot});
        },
        .symbol, .func, .label => |id| {
            // Mirror assignOperand: resolve id -> name -> text operand.
            const name = symbols.lookupName(id) orelse return JsEmitError.InvalidOperand;
            try resolveTextToJs(writer, symbols, fsig, const_addrs, name);
        },
        .imm_i64, .imm_int => |v| try writer.print("{d}", .{v}),
        .imm_u64 => |v| try writer.print("{d}", .{v}),
        .imm_float => |v| try writer.print("{d}", .{v}),
        .text, .native_text => |t| try resolveTextToJs(writer, symbols, fsig, const_addrs, t),
        else => return JsEmitError.InvalidOperand,
    }
}

fn labelPcOf(label_pc: *const std.AutoHashMap(u32, usize), op: inst.Operand) !usize {
    const id: u32 = switch (op) {
        .label => |v| v,
        .symbol => |v| v,
        else => return JsEmitError.InvalidOperand,
    };
    return label_pc.get(id) orelse return JsEmitError.UnknownFunction;
}

/// Mirror emit_llvm_llvmc.functionUsesGlobalRegIds: .reg operands may hold
/// per-function slot indexes or global symbol ids, depending on the body.
fn taskUsesGlobalRegIds(fsig: sig.FunctionSig, verified: anytype, task: FuncTask) bool {
    var i: usize = task.start_idx + 1;
    while (i < task.end_idx) : (i += 1) {
        for (verified.annotated[i].base.operands) |operand| {
            if (operand == .reg) {
                const raw = operand.reg;
                if (raw >= fsig.reg_ids.len and fsig.slotOf(raw) != null) return true;
            }
        }
    }
    return false;
}

fn regSlot(fsig: sig.FunctionSig, use_global: bool, slot_or_id: u32) !u32 {
    if (use_global) return fsig.slotOf(slot_or_id) orelse return JsEmitError.InvalidOperand;
    if (@as(usize, slot_or_id) < fsig.reg_ids.len) return slot_or_id;
    return fsig.slotOf(slot_or_id) orelse return JsEmitError.InvalidOperand;
}

fn emitOpExpr(writer: anytype, symbols: anytype, fsig: sig.FunctionSig, use_global: bool, const_addrs: anytype, opcode: inst.OpKind, lhs: inst.Operand, rhs: inst.Operand) !void {
    switch (opcode) {
        .add => {
            try writer.writeAll("__sa_add(");
            try resolveValueToJs(writer, symbols, fsig, use_global, const_addrs, lhs);
            try writer.writeAll(", ");
            try resolveValueToJs(writer, symbols, fsig, use_global, const_addrs, rhs);
            try writer.writeAll(")");
        },
        .sub => {
            try writer.writeAll("__sa_sub(");
            try resolveValueToJs(writer, symbols, fsig, use_global, const_addrs, lhs);
            try writer.writeAll(", ");
            try resolveValueToJs(writer, symbols, fsig, use_global, const_addrs, rhs);
            try writer.writeAll(")");
        },
        .mul => {
            try writer.writeAll("__sa_mul(");
            try resolveValueToJs(writer, symbols, fsig, use_global, const_addrs, lhs);
            try writer.writeAll(", ");
            try resolveValueToJs(writer, symbols, fsig, use_global, const_addrs, rhs);
            try writer.writeAll(")");
        },
        .sdiv, .div => {
            try writer.writeAll("__sa_sdiv(");
            try resolveValueToJs(writer, symbols, fsig, use_global, const_addrs, lhs);
            try writer.writeAll(", ");
            try resolveValueToJs(writer, symbols, fsig, use_global, const_addrs, rhs);
            try writer.writeAll(")");
        },
        .udiv => {
            try writer.writeAll("__sa_udiv(");
            try resolveValueToJs(writer, symbols, fsig, use_global, const_addrs, lhs);
            try writer.writeAll(", ");
            try resolveValueToJs(writer, symbols, fsig, use_global, const_addrs, rhs);
            try writer.writeAll(")");
        },
        .srem, .rem => {
            try writer.writeAll("__sa_srem(");
            try resolveValueToJs(writer, symbols, fsig, use_global, const_addrs, lhs);
            try writer.writeAll(", ");
            try resolveValueToJs(writer, symbols, fsig, use_global, const_addrs, rhs);
            try writer.writeAll(")");
        },
        .urem => {
            try writer.writeAll("__sa_urem(");
            try resolveValueToJs(writer, symbols, fsig, use_global, const_addrs, lhs);
            try writer.writeAll(", ");
            try resolveValueToJs(writer, symbols, fsig, use_global, const_addrs, rhs);
            try writer.writeAll(")");
        },
        .@"and" => {
            try writer.writeAll("__sa_band(");
            try resolveValueToJs(writer, symbols, fsig, use_global, const_addrs, lhs);
            try writer.writeAll(", ");
            try resolveValueToJs(writer, symbols, fsig, use_global, const_addrs, rhs);
            try writer.writeAll(")");
        },
        .@"or" => {
            try writer.writeAll("__sa_bor(");
            try resolveValueToJs(writer, symbols, fsig, use_global, const_addrs, lhs);
            try writer.writeAll(", ");
            try resolveValueToJs(writer, symbols, fsig, use_global, const_addrs, rhs);
            try writer.writeAll(")");
        },
        .xor => {
            try writer.writeAll("__sa_bxor(");
            try resolveValueToJs(writer, symbols, fsig, use_global, const_addrs, lhs);
            try writer.writeAll(", ");
            try resolveValueToJs(writer, symbols, fsig, use_global, const_addrs, rhs);
            try writer.writeAll(")");
        },
        .shl => {
            try writer.writeAll("__sa_shl(");
            try resolveValueToJs(writer, symbols, fsig, use_global, const_addrs, lhs);
            try writer.writeAll(", ");
            try resolveValueToJs(writer, symbols, fsig, use_global, const_addrs, rhs);
            try writer.writeAll(")");
        },
        .lshr, .shr => {
            try writer.writeAll("__sa_lshr(");
            try resolveValueToJs(writer, symbols, fsig, use_global, const_addrs, lhs);
            try writer.writeAll(", ");
            try resolveValueToJs(writer, symbols, fsig, use_global, const_addrs, rhs);
            try writer.writeAll(")");
        },
        .ashr => {
            try writer.writeAll("__sa_ashr(");
            try resolveValueToJs(writer, symbols, fsig, use_global, const_addrs, lhs);
            try writer.writeAll(", ");
            try resolveValueToJs(writer, symbols, fsig, use_global, const_addrs, rhs);
            try writer.writeAll(")");
        },
        .eq => {
            try writer.writeAll("__sa_eq(");
            try resolveValueToJs(writer, symbols, fsig, use_global, const_addrs, lhs);
            try writer.writeAll(", ");
            try resolveValueToJs(writer, symbols, fsig, use_global, const_addrs, rhs);
            try writer.writeAll(")");
        },
        .ne => {
            try writer.writeAll("__sa_ne(");
            try resolveValueToJs(writer, symbols, fsig, use_global, const_addrs, lhs);
            try writer.writeAll(", ");
            try resolveValueToJs(writer, symbols, fsig, use_global, const_addrs, rhs);
            try writer.writeAll(")");
        },
        .slt, .lt => {
            try writer.writeAll("__sa_slt(");
            try resolveValueToJs(writer, symbols, fsig, use_global, const_addrs, lhs);
            try writer.writeAll(", ");
            try resolveValueToJs(writer, symbols, fsig, use_global, const_addrs, rhs);
            try writer.writeAll(")");
        },
        .sle => {
            try writer.writeAll("__sa_sle(");
            try resolveValueToJs(writer, symbols, fsig, use_global, const_addrs, lhs);
            try writer.writeAll(", ");
            try resolveValueToJs(writer, symbols, fsig, use_global, const_addrs, rhs);
            try writer.writeAll(")");
        },
        .sgt, .gt => {
            try writer.writeAll("__sa_sgt(");
            try resolveValueToJs(writer, symbols, fsig, use_global, const_addrs, lhs);
            try writer.writeAll(", ");
            try resolveValueToJs(writer, symbols, fsig, use_global, const_addrs, rhs);
            try writer.writeAll(")");
        },
        .sge => {
            try writer.writeAll("__sa_sge(");
            try resolveValueToJs(writer, symbols, fsig, use_global, const_addrs, lhs);
            try writer.writeAll(", ");
            try resolveValueToJs(writer, symbols, fsig, use_global, const_addrs, rhs);
            try writer.writeAll(")");
        },
        .ult => {
            try writer.writeAll("__sa_ult(");
            try resolveValueToJs(writer, symbols, fsig, use_global, const_addrs, lhs);
            try writer.writeAll(", ");
            try resolveValueToJs(writer, symbols, fsig, use_global, const_addrs, rhs);
            try writer.writeAll(")");
        },
        .ule => {
            try writer.writeAll("__sa_ule(");
            try resolveValueToJs(writer, symbols, fsig, use_global, const_addrs, lhs);
            try writer.writeAll(", ");
            try resolveValueToJs(writer, symbols, fsig, use_global, const_addrs, rhs);
            try writer.writeAll(")");
        },
        .ugt => {
            try writer.writeAll("__sa_ugt(");
            try resolveValueToJs(writer, symbols, fsig, use_global, const_addrs, lhs);
            try writer.writeAll(", ");
            try resolveValueToJs(writer, symbols, fsig, use_global, const_addrs, rhs);
            try writer.writeAll(")");
        },
        .uge => {
            try writer.writeAll("__sa_uge(");
            try resolveValueToJs(writer, symbols, fsig, use_global, const_addrs, lhs);
            try writer.writeAll(", ");
            try resolveValueToJs(writer, symbols, fsig, use_global, const_addrs, rhs);
            try writer.writeAll(")");
        },
        .fadd => {
            try writer.writeAll("__sa_fadd(");
            try resolveValueToJs(writer, symbols, fsig, use_global, const_addrs, lhs);
            try writer.writeAll(", ");
            try resolveValueToJs(writer, symbols, fsig, use_global, const_addrs, rhs);
            try writer.writeAll(")");
        },
        .fsub => {
            try writer.writeAll("__sa_fsub(");
            try resolveValueToJs(writer, symbols, fsig, use_global, const_addrs, lhs);
            try writer.writeAll(", ");
            try resolveValueToJs(writer, symbols, fsig, use_global, const_addrs, rhs);
            try writer.writeAll(")");
        },
        .fmul => {
            try writer.writeAll("__sa_fmul(");
            try resolveValueToJs(writer, symbols, fsig, use_global, const_addrs, lhs);
            try writer.writeAll(", ");
            try resolveValueToJs(writer, symbols, fsig, use_global, const_addrs, rhs);
            try writer.writeAll(")");
        },
        .fdiv => {
            try writer.writeAll("__sa_fdiv(");
            try resolveValueToJs(writer, symbols, fsig, use_global, const_addrs, lhs);
            try writer.writeAll(", ");
            try resolveValueToJs(writer, symbols, fsig, use_global, const_addrs, rhs);
            try writer.writeAll(")");
        },
        .fcmp_eq => {
            try writer.writeAll("__sa_feq(");
            try resolveValueToJs(writer, symbols, fsig, use_global, const_addrs, lhs);
            try writer.writeAll(", ");
            try resolveValueToJs(writer, symbols, fsig, use_global, const_addrs, rhs);
            try writer.writeAll(")");
        },
        .fcmp_ne => {
            try writer.writeAll("__sa_fne(");
            try resolveValueToJs(writer, symbols, fsig, use_global, const_addrs, lhs);
            try writer.writeAll(", ");
            try resolveValueToJs(writer, symbols, fsig, use_global, const_addrs, rhs);
            try writer.writeAll(")");
        },
        .fcmp_lt => {
            try writer.writeAll("__sa_flt(");
            try resolveValueToJs(writer, symbols, fsig, use_global, const_addrs, lhs);
            try writer.writeAll(", ");
            try resolveValueToJs(writer, symbols, fsig, use_global, const_addrs, rhs);
            try writer.writeAll(")");
        },
        .fcmp_le => {
            try writer.writeAll("__sa_fle(");
            try resolveValueToJs(writer, symbols, fsig, use_global, const_addrs, lhs);
            try writer.writeAll(", ");
            try resolveValueToJs(writer, symbols, fsig, use_global, const_addrs, rhs);
            try writer.writeAll(")");
        },
        .fcmp_gt => {
            try writer.writeAll("__sa_fgt(");
            try resolveValueToJs(writer, symbols, fsig, use_global, const_addrs, lhs);
            try writer.writeAll(", ");
            try resolveValueToJs(writer, symbols, fsig, use_global, const_addrs, rhs);
            try writer.writeAll(")");
        },
        .fcmp_ge => {
            try writer.writeAll("__sa_fge(");
            try resolveValueToJs(writer, symbols, fsig, use_global, const_addrs, lhs);
            try writer.writeAll(", ");
            try resolveValueToJs(writer, symbols, fsig, use_global, const_addrs, rhs);
            try writer.writeAll(")");
        },
        .neg => {
            try writer.writeAll("__sa_neg(");
            try resolveValueToJs(writer, symbols, fsig, use_global, const_addrs, lhs);
            try writer.writeAll(")");
        },
        .not => {
            try writer.writeAll("__sa_bnot(");
            try resolveValueToJs(writer, symbols, fsig, use_global, const_addrs, lhs);
            try writer.writeAll(")");
        },
        .fneg => {
            try writer.writeAll("__sa_fneg(");
            try resolveValueToJs(writer, symbols, fsig, use_global, const_addrs, lhs);
            try writer.writeAll(")");
        },
        else => {
            try writer.writeAll("__sa_trap(\"unsupported op\")");
        },
    }
}
fn dstSlot(fsig: sig.FunctionSig, use_global: bool, op: inst.Operand) !u32 {
    return switch (op) {
        .reg => |r| try regSlot(fsig, use_global, r),
        .symbol => |id| try regSlot(fsig, use_global, id),
        else => return JsEmitError.InvalidOperand,
    };
}

/// Shared return emission for straight-line and pc-machine bodies.
/// Fallible functions return {s, v} objects (mirrors SA_OP_RET
/// build_fallible_ok); plain functions return bare values.
fn emitReturnStmt(writer: anytype, symbols: anytype, fsig: sig.FunctionSig, use_global: bool, const_addrs: anytype, operand: inst.Operand, indent: []const u8) !void {
    if (fsig.return_fallible) {
        switch (operand) {
            .none => try writer.print("{s}return {{s: 0}};\n", .{indent}),
            else => {
                try writer.print("{s}return {{s: 0, v: (", .{indent});
                try resolveValueToJs(writer, symbols, fsig, use_global, const_addrs, operand);
                try writer.writeAll(")};\n");
            },
        }
    } else switch (operand) {
        .none => try writer.print("{s}return 0;\n", .{indent}),
        else => {
            try writer.print("{s}return (", .{indent});
            try resolveValueToJs(writer, symbols, fsig, use_global, const_addrs, operand);
            try writer.writeAll(");\n");
        },
    }
}

fn emitCallInstruction(writer: anytype, allocator: std.mem.Allocator, symbols: anytype, fsig: sig.FunctionSig, use_global: bool, const_addrs: anytype, base: inst.Instruction) !void {
    _ = use_global;
    var parsed = call.parseInstructionCall(allocator, base, symbols) catch {
        try writer.print("  __sa_trap(\"unsupported call: {s}\");\n", .{std.mem.trim(u8, base.raw_text, " \t\r\n")});
        return;
    };
    defer parsed.deinit(allocator);
    if (parsed.is_indirect) {
        try writer.print("  __sa_trap(\"unsupported call_indirect: {s}\");\n", .{std.mem.trim(u8, base.raw_text, " \t\r\n")});
        return;
    }
    if (parsed.dest) |dest| {
        const id = symbols.findId(dest) orelse return JsEmitError.InvalidOperand;
        const slot = fsig.slotOf(id) orelse return JsEmitError.InvalidOperand;
        try writer.print("  r{d} = ", .{slot});
    } else {
        try writer.writeAll("  ");
    }
    try jsFuncName(writer, parsed.callee);
    try writer.writeAll("(");
    for (parsed.args, 0..) |arg, idx| {
        if (idx != 0) try writer.writeAll(", ");
        try resolveTextToJs(writer, symbols, fsig, const_addrs, arg.text);
    }
    try writer.writeAll(");\n");
}

fn emitLinearInstruction(writer: anytype, allocator: std.mem.Allocator, symbols: anytype, fsig: sig.FunctionSig, use_global: bool, const_addrs: anytype, base: inst.Instruction, js_opt: JsEmitOptions) !void {
    _ = js_opt;
    last_js_inst = base.raw_text;
    last_js_func = fsig.name;
    switch (base.kind) {
        .return_ => try emitReturnStmt(writer, symbols, fsig, use_global, const_addrs, base.operands[0], "  "),
        .try_, .early_return => {
            // Unpack {s, v}; on error early-return like SA_OP_TRY.
            const slot = try dstSlot(fsig, use_global, base.operands[0]);
            try writer.writeAll("  { const __t = (");
            try resolveValueToJs(writer, symbols, fsig, use_global, const_addrs, base.operands[1]);
            try writer.writeAll("); if (!__sa_fok(__t)) ");
            if (fsig.return_fallible) {
                try writer.writeAll("return __t;");
            } else if (fsig.return_ty == .void) {
                try writer.writeAll("return;");
            } else {
                try writer.writeAll("return 0;");
            }
            try writer.print(" r{d} = __sa_fv(__t); }}\n", .{slot});
        },
        .op => {
            const slot = try dstSlot(fsig, use_global, base.operands[0]);
            const opcode = base.op_kind orelse return JsEmitError.InvalidOperand;
            if (inst.isTypeConversionOpKind(opcode)) {
                try writer.print("  r{d} = (", .{slot});
                try resolveValueToJs(writer, symbols, fsig, use_global, const_addrs, base.operands[1]);
                try writer.writeAll(");\n");
                return;
            }
            try writer.print("  r{d} = ", .{slot});
            if (opcode == .fneg) {
                try writer.writeAll("(-(");
                try resolveValueToJs(writer, symbols, fsig, use_global, const_addrs, base.operands[1]);
                try writer.writeAll("));\n");
                return;
            }
            try emitOpExpr(writer, symbols, fsig, use_global, const_addrs, opcode, base.operands[1], base.operands[2]);
            try writer.writeAll(";\n");
        },
        .alloc, .stack_alloc => {
            const slot = try dstSlot(fsig, use_global, base.operands[0]);
            try writer.print("  r{d} = __sa_alloc(", .{slot});
            try resolveValueToJs(writer, symbols, fsig, use_global, const_addrs, base.operands[1]);
            try writer.writeAll(");\n");
        },
        .ptr_add => {
            const slot = try dstSlot(fsig, use_global, base.operands[0]);
            try writer.print("  r{d} = __sa_ptr_add(", .{slot});
            try resolveValueToJs(writer, symbols, fsig, use_global, const_addrs, base.operands[1]);
            try writer.writeAll(", ");
            try resolveValueToJs(writer, symbols, fsig, use_global, const_addrs, base.operands[2]);
            try writer.writeAll(");\n");
        },
        .load, .take, .atomic_load => {
            // NOTE: atomic ordering is ignored (single-threaded JS runtime).
            const slot = try dstSlot(fsig, use_global, base.operands[0]);
            const ty = memPrimType(base);
            try writer.print("  r{d} = {s}(__sa_ptr_add(", .{ slot, memLoadFn(ty) });
            try resolveValueToJs(writer, symbols, fsig, use_global, const_addrs, base.operands[1]);
            try writer.writeAll(", ");
            try resolveValueToJs(writer, symbols, fsig, use_global, const_addrs, base.operands[2]);
            try writer.writeAll("));\n");
        },
        .store, .atomic_store => {
            // NOTE: atomic ordering is ignored (single-threaded JS runtime).
            const ty = memPrimType(base);
            try writer.print("  {s}(__sa_ptr_add(", .{memStoreFn(ty)});
            try resolveValueToJs(writer, symbols, fsig, use_global, const_addrs, base.operands[0]);
            try writer.writeAll(", ");
            try resolveValueToJs(writer, symbols, fsig, use_global, const_addrs, base.operands[1]);
            try writer.writeAll("), ");
            try resolveValueToJs(writer, symbols, fsig, use_global, const_addrs, base.operands[2]);
            try writer.writeAll(");\n");
        },
        .call => try emitCallInstruction(writer, allocator, symbols, fsig, use_global, const_addrs, base),
        .call_indirect => {
            try writer.print("  __sa_trap(\"unsupported call_indirect: {s}\");\n", .{std.mem.trim(u8, base.raw_text, " \t\r\n")});
        },
        .cmpxchg => {
            // Single-threaded降级: old = load; ok = (old == expected);
            // if (ok) store(new). Mirrors SA_OP_CMPXCHG (dst=old, 2nd target=ok).
            const dst_old = try dstSlot(fsig, use_global, base.operands[0]);
            const dst_ok = try dstSlot(fsig, use_global, base.operands[1]);
            const expected = base.atomic_expected_text orelse return JsEmitError.InvalidOperand;
            const new_text = base.atomic_new_text orelse return JsEmitError.InvalidOperand;
            const ty = memPrimType(base);
            const load_fn = memLoadFn(ty);
            const store_fn = memStoreFn(ty);
            try writer.writeAll("  { const __addr = __sa_ptr_add(");
            try resolveValueToJs(writer, symbols, fsig, use_global, const_addrs, base.operands[2]);
            try writer.writeAll(", ");
            try resolveValueToJs(writer, symbols, fsig, use_global, const_addrs, base.operands[3]);
            try writer.print("); const __old = {s}(__addr); const __exp = (", .{load_fn});
            try resolveTextToJs(writer, symbols, fsig, const_addrs, expected);
            try writer.writeAll("); const __ok = ((__old == __exp) ? 1 : 0); if (__ok) ");
            try writer.print("{s}(__addr, (", .{store_fn});
            try resolveTextToJs(writer, symbols, fsig, const_addrs, new_text);
            try writer.print(")); r{d} = __old; r{d} = __ok; }}\n", .{ dst_old, dst_ok });
        },
        .fence => {
            try writer.writeAll("  /* no-op fence (single-threaded JS runtime) */\n");
        },
        .assign, .borrow, .raw_cast => {
            // Mirror emit_llvm_llvmc assignOperand: dst aliases the value.
            const slot = try dstSlot(fsig, use_global, base.operands[0]);
            try writer.print("  r{d} = (", .{slot});
            switch (base.operands[1]) {
                .reg, .symbol, .func, .label, .imm_i64, .imm_int, .imm_u64, .imm_float, .text, .native_text => {
                    try resolveValueToJs(writer, symbols, fsig, use_global, const_addrs, base.operands[1]);
                },
                else => return JsEmitError.InvalidOperand,
            }
            try writer.writeAll(");\n");
        },
        .panic => {
            // `panic(code)` uses call syntax; parse args like the LLVM backend.
            var parsed = call.parseInstructionCall(allocator, base, symbols) catch {
                try writer.print("  __sa_trap(\"panic: {s}\");\n", .{std.mem.trim(u8, base.raw_text, " \t\r\n")});
                return;
            };
            defer parsed.deinit(allocator);
            if (parsed.args.len != 1) {
                try writer.print("  __sa_trap(\"panic: {s}\");\n", .{std.mem.trim(u8, base.raw_text, " \t\r\n")});
                return;
            }
            try writer.writeAll("  __sa_panic(");
            try resolveTextToJs(writer, symbols, fsig, const_addrs, parsed.args[0].text);
            try writer.writeAll(");\n");
        },
        .panic_msg => {
            var parsed = call.parseInstructionCall(allocator, base, symbols) catch {
                try writer.writeAll("  __sa_trap(\"panic_msg\");\n");
                return;
            };
            defer parsed.deinit(allocator);
            if (parsed.args.len >= 1) {
                try writer.writeAll("  __sa_trap(\"panic_msg: \" + (");
                try resolveTextToJs(writer, symbols, fsig, const_addrs, parsed.args[0].text);
                try writer.writeAll("));\n");
            } else {
                try writer.writeAll("  __sa_trap(\"panic_msg\");\n");
            }
        },
        .move_, .release, .assume_safe, .assume_borrow => {
            try writer.print("  /* no-op {s}: {s} */\n", .{ @tagName(base.kind), std.mem.trim(u8, base.raw_text, " \t\r\n") });
        },
        else => {
            try writer.print("  __sa_trap(\"unsupported {s}: {s}\");\n", .{ @tagName(base.kind), std.mem.trim(u8, base.raw_text, " \t\r\n") });
        },
    }
}

fn emitPcInstruction(writer: anytype, allocator: std.mem.Allocator, symbols: anytype, fsig: sig.FunctionSig, use_global: bool, const_addrs: anytype, base: inst.Instruction, label_pc: *std.AutoHashMap(u32, usize), js_opt: JsEmitOptions) !void {
    switch (base.kind) {
        .jmp => {
            const npc = try labelPcOf(label_pc, base.operands[1]);
            try writer.print("        __pc = {d}; break;\n", .{npc});
        },
        .br => {
            const tpc = try labelPcOf(label_pc, base.operands[1]);
            const fpc = try labelPcOf(label_pc, base.operands[3]);
            try writer.writeAll("        __pc = (__sa_truthy(");
            try resolveValueToJs(writer, symbols, fsig, use_global, const_addrs, base.operands[0]);
            try writer.print(") ? {d} : {d}); break;\n", .{ tpc, fpc });
        },
        .br_null => {
            try writer.print("        __sa_trap(\"unsupported br_null: {s}\");\n", .{std.mem.trim(u8, base.raw_text, " \t\r\n")});
        },
        .return_ => try emitReturnStmt(writer, symbols, fsig, use_global, const_addrs, base.operands[0], "        "),
        else => {
            try writer.writeAll("        ");
            // Reuse the linear emitter, then re-indent (it emits with 2-space indent).
            var buf: [32768]u8 = undefined;
            var fbs = std.io.fixedBufferStream(&buf);
            try emitLinearInstruction(fbs.writer(), allocator, symbols, fsig, use_global, const_addrs, base, js_opt);
            const s = std.mem.trim(u8, fbs.getWritten(), " \t\r\n");
            // Linear emitter may produce multiple lines; indent each by 8 spaces.
            var it = std.mem.splitScalar(u8, s, '\n');
            var first_line = true;
            while (it.next()) |line| {
                const t = std.mem.trim(u8, line, " \t\r");
                if (t.len == 0) continue;
                if (!first_line) try writer.writeAll("        ");
                try writer.print("{s}\n", .{t});
                first_line = false;
            }
        },
    }
}

fn emitBodyAsPcMachine(writer: anytype, allocator: std.mem.Allocator, verified: anytype, fsig: sig.FunctionSig, task: FuncTask, const_addrs: anytype, js_opt: JsEmitOptions) !void {
    const use_global = taskUsesGlobalRegIds(fsig, verified, task);
    // Map label symbol id -> pc number. Entry (before first label) is pc 0.
    var label_pc = std.AutoHashMap(u32, usize).init(allocator);
    defer label_pc.deinit();
    var pcs: usize = 1; // next free pc
    var i: usize = task.start_idx + 1;
    while (i < task.end_idx) : (i += 1) {
        const base = verified.annotated[i].base;
        if (base.kind == .label) {
            const lid: u32 = switch (base.operands[1]) {
                .label => |v| v,
                .symbol => |v| v,
                else => continue,
            };
            if (label_pc.get(lid) == null) {
                try label_pc.put(lid, pcs);
                pcs += 1;
            }
        }
    }
    // If no labels at all, emit straight-line body without pc machine.
    if (pcs == 1) {
        i = task.start_idx + 1;
        while (i < task.end_idx) : (i += 1) {
            try emitLinearInstruction(writer, allocator, verified.symbols, fsig, use_global, const_addrs, verified.annotated[i].base, js_opt);
        }
        return;
    }

    try writer.writeAll("  let __pc = 0;\n  while (true) {\n    switch (__pc) {\n      case 0: {\n");
    i = task.start_idx + 1;
    var prev_terminates = false;
    while (i < task.end_idx) : (i += 1) {
        const base = verified.annotated[i].base;
        if (base.kind == .label) {
            const lid: u32 = switch (base.operands[1]) {
                .label => |v| v,
                .symbol => |v| v,
                else => continue,
            };
            const npc = label_pc.get(lid) orelse continue;
            // A preceding jmp/br/return already leaves the case; skip the
            // redundant `__pc = N; break;` instead of emitting dead code.
            if (prev_terminates) {
                try writer.print("      }}\n      case {d}: {{\n", .{npc});
            } else {
                try writer.print("        __pc = {d}; break;\n      }}\n      case {d}: {{\n", .{ npc, npc });
            }
            prev_terminates = false;
            continue;
        }
        try emitPcInstruction(writer, allocator, verified.symbols, fsig, use_global, const_addrs, base, &label_pc, js_opt);
        prev_terminates = base.kind == .jmp or base.kind == .br or base.kind == .return_;
    }
    try writer.writeAll("        return __sa_trap(\"fallthrough end of function\");\n      }\n      default: return __sa_trap(\"bad pc \" + __pc);\n    }\n  }\n");
}

fn emitOneFunction(writer: anytype, allocator: std.mem.Allocator, verified: anytype, task: FuncTask, const_addrs: anytype, js_opt: JsEmitOptions) !void {
    const fsig = verified.function_sigs[task.fsig_index];
    if (task.kind == .extern_decl) {
        // Known sa_std IO shims live in the emitter (NOT in sa_std): they only
        // read already-emitted linear memory. Unknown externs still trap.
        if (std.mem.eql(u8, fsig.name, "sa_print_bytes")) {
            try writer.writeAll(
                \\function sa_print_bytes(ptr, len) {
                \\  const a = __sa_addr(ptr), n = __sa_num(len);
                \\  const s = new globalThis.TextDecoder().decode(__sa_u8.slice(a, a + n));
                \\  if (typeof globalThis.process !== "undefined" && globalThis.process.stdout) { globalThis.process.stdout.write(s); }
                \\  else { globalThis.console.log(s); }
                \\  return 0;
                \\}
                \\
            );
            return;
        }
        try writer.writeAll("function ");
        try jsFuncName(writer, fsig.name);
        try writer.writeAll("() { __sa_trap(\"extern not linked: ");
        try jsFuncName(writer, fsig.name);
        try writer.writeAll("\"); }\n");
        return;
    }
    if (js_opt.format == .esm) try writer.writeAll("export function ") else try writer.writeAll("function ");
    try jsFuncName(writer, fsig.name);
    try writer.writeAll("(");
    for (fsig.params, 0..) |p, idx| {
        if (idx != 0) try writer.writeAll(", ");
        try jsIdent(writer, p.name);
    }
    try writer.writeAll(") {\n");
    if (js_opt.debug_comments) {
        try writer.print("  // sa-sig: {s} -> {s} regs={d}\n", .{ fsig.name, sig.primTypeName(fsig.return_ty), fsig.reg_ids.len });
    }
    // Declare registers as locals. Slots aliasing static consts are
    // initialized to the const address (mirrors LLVM const reg init);
    // all other slots start at 0. Params bind into their slots after.
    if (fsig.reg_ids.len > 0) {
        try writer.writeAll("  let ");
        var first = true;
        for (fsig.reg_ids, 0..) |gid, slot| {
            if (!first) try writer.writeAll(", ");
            try writer.print("r{d} = ", .{slot});
            if (verified.symbols.lookupName(gid)) |gname| {
                if (const_addrs.get(gname)) |_| {
                    try writeConstSlot(writer, gname);
                } else {
                    try writer.writeAll("0");
                }
            } else {
                try writer.writeAll("0");
            }
            first = false;
        }
        try writer.writeAll(";\n");
        // bind params into their slots
        for (fsig.params, 0..) |p, pidx| {
            if (pidx < fsig.param_ids.len) {
                const gid = fsig.param_ids[pidx];
                if (fsig.slotOf(gid)) |slot| {
                    try writer.print("  r{d} = ", .{slot});
                    try jsIdent(writer, p.name);
                    try writer.writeAll(";\n");
                }
            }
        }
    }
    try emitBodyAsPcMachine(writer, allocator, verified, fsig, task, const_addrs, js_opt);
    try writer.writeAll("}\n");
}

pub fn emitJsToString(allocator: std.mem.Allocator, verified: anytype, source_path: []const u8, size_bits: u16, js_opt: JsEmitOptions) ![]u8 {
    var out = std.ArrayList(u8).init(allocator);
    errdefer out.deinit();
    const writer = out.writer();
    try writeRuntimeHeader(writer, js_opt, size_bits);
    try writer.print("// source: {s}\n", .{source_path});
    // Static consts: fixed linear-memory addresses below the bump region.
    var const_addrs = std.StringHashMap(usize).init(allocator);
    defer const_addrs.deinit();
    var const_cursor: usize = 4096;
    const bump_start: usize = 65536;
    for (verified.const_decls) |decl| {
        const len = constBytesLen(decl.value) catch 0;
        const aligned = std.mem.alignForward(usize, const_cursor, 8);
        if (decl.value == .vtable or len == 0) {
            // VTables hold function pointers (no JS address); reserve 8B/slot zeroed.
            const slots: usize = if (decl.value == .vtable) decl.value.vtable.slots.len * 8 else 8;
            const a2 = std.mem.alignForward(usize, const_cursor, 8);
            if (a2 + slots > bump_start) return JsEmitError.Failed;
            try const_addrs.put(decl.name, a2);
            try writer.writeAll("const ");
            try writeConstSlot(writer, decl.name);
            try writer.print(" = {d}; // {s} (zeroed, {d} bytes)\n", .{ a2, @tagName(decl.value), slots });
            try writer.print("__sa_u8.fill(0, {d}, {d});\n", .{ a2, a2 + slots });
            const_cursor = a2 + slots;
            continue;
        }
        if (aligned + len > bump_start) return JsEmitError.Failed;
        try const_addrs.put(decl.name, aligned);
        const bytes = try allocator.alloc(u8, len);
        defer allocator.free(bytes);
        try fillConstBytes(bytes, decl.value);
        try writer.writeAll("const ");
        try writeConstSlot(writer, decl.name);
        try writer.print(" = {d}; // {s} ({d} bytes)\n", .{ aligned, @tagName(decl.value), len });
        try writer.print("__sa_u8.set([", .{});
        for (bytes, 0..) |b, idx| {
            if (idx != 0) try writer.writeAll(",");
            try writer.print("{d}", .{b});
        }
        try writer.print("], {d});\n", .{aligned});
        const_cursor = aligned + len;
    }
    const tasks = try collectFuncTasks(allocator, verified);
    defer allocator.free(tasks);
    var has_main = false;
    for (tasks) |task| {
        if (task.kind == .extern_decl) continue;
        try emitOneFunction(writer, allocator, verified, task, &const_addrs, js_opt);
        const fsig = verified.function_sigs[task.fsig_index];
        if (std.mem.eql(u8, fsig.name, "main")) has_main = true;
    }
    // extern stubs (so calls don't ReferenceError; they trap with name)
    for (tasks) |task| {
        if (task.kind != .extern_decl) continue;
        try emitOneFunction(writer, allocator, verified, task, &const_addrs, js_opt);
    }
    // exports + main runner
    if (js_opt.format == .cjs) {
        try writer.writeAll("\nmodule.exports = { __sa_memory, __sa_view, __sa_u8, __sa_alloc");
        for (tasks) |task| {
            if (task.kind == .extern_decl) continue;
            const fsig = verified.function_sigs[task.fsig_index];
            try writer.writeAll(", ");
            try jsFuncName(writer, fsig.name);
        }
        try writer.writeAll(" };\n");
        if (has_main) try writer.writeAll("if (require.main === module) { main(); }\n");
    } else {
        try writer.writeAll("\nexport { __sa_memory, __sa_view, __sa_u8, __sa_alloc };\n");
        if (has_main) try writer.writeAll("if (typeof globalThis.process !== \"undefined\" && globalThis.process.argv && globalThis.process.argv[1] && /\\.(mjs|js|cjs)$/.test(globalThis.process.argv[1])) { try { main(); } catch (e) { globalThis.console.error(e); globalThis.process.exit(1); } }\n");
    }
    return out.toOwnedSlice();
}

pub fn emitJsToFile(allocator: std.mem.Allocator, verified: anytype, source_path: []const u8, size_bits: u16, js_opt: JsEmitOptions, path: []const u8) !void {
    const text = try emitJsToString(allocator, verified, source_path, size_bits, js_opt);
    defer allocator.free(text);
    // patch mem-bytes placeholder
    const mem_bytes: usize = @as(usize, js_opt.mem_pages) * 65536;
    var final = try allocator.dupe(u8, text);
    defer allocator.free(final);
    const needle = "__SA_MEM_BYTES_DECL__";
    if (std.mem.indexOf(u8, final, needle)) |pos| {
        var patched = std.ArrayList(u8).init(allocator);
        errdefer patched.deinit();
        try patched.appendSlice(final[0..pos]);
        try patched.writer().print("{d}", .{mem_bytes});
        try patched.appendSlice(final[pos + needle.len ..]);
        const owned = try patched.toOwnedSlice();
        defer allocator.free(owned);
        const dir = std.fs.path.dirname(path);
        if (dir) |d| try std.fs.cwd().makePath(d);
        const f = try std.fs.cwd().createFile(path, .{});
        defer f.close();
        try f.writeAll(owned);
        return;
    }
    const dir = std.fs.path.dirname(path);
    if (dir) |d| try std.fs.cwd().makePath(d);
    const f = try std.fs.cwd().createFile(path, .{});
    defer f.close();
    try f.writeAll(final);
}

test "js ident sanitizes names" {
    var buf: [64]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    try jsIdent(fbs.writer(), "hello-world.foo");
    try std.testing.expectEqualStrings("hello_world_foo", fbs.getWritten());
}

test "js format parses esm and cjs" {
    try std.testing.expectEqual(JsFormat.esm, JsFormat.parse("esm").?);
    try std.testing.expectEqual(JsFormat.cjs, JsFormat.parse("cjs").?);
    try std.testing.expect(JsFormat.parse("bad") == null);
}
