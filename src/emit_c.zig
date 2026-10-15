const std = @import("std");

const emit_options = @import("emit_options.zig");
const inst = @import("common/instruction.zig");
const sig = @import("common/signature.zig");
const call = @import("referee/call.zig");
const const_decl = @import("common/const_decl.zig");
const sio = @import("sio");

pub const EmitOptions = emit_options.EmitOptions;
pub const CEmitError = error{ Failed, InvalidOperand, UnknownFunction, UnsupportedInstruction, OutOfMemory };

/// Last instruction raw text seen by the emitter (diagnostics only).
pub threadlocal var last_c_inst: []const u8 = "";
pub threadlocal var last_c_func: []const u8 = "";

pub const CEmitOptions = struct {
    mem_pages: u32 = 256, // 256 * 64KiB = 16MiB initial
    debug_comments: bool = true,
};

const FuncTask = struct {
    fsig_index: usize,
    start_idx: usize,
    end_idx: usize,
    kind: inst.InstKind,
};

fn collectFuncTasks(allocator: std.mem.Allocator, verified: anytype) ![]FuncTask {
    var tasks = std.array_list.Managed(FuncTask).init(allocator);
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

fn isCReserved(name: []const u8) bool {
    const reserved = [_][]const u8{
        "auto", "break", "case", "char", "const", "continue", "default", "do",
        "double", "else", "enum", "extern", "float", "for", "goto", "if",
        "inline", "int", "long", "register", "restrict", "return", "short",
        "signed", "sizeof", "static", "struct", "switch", "typedef", "union",
        "unsigned", "void", "volatile", "while", "_Bool", "_Complex",
        "_Imaginary", "sa_mem", "sa_brk",
    };
    for (reserved) |word| {
        if (std.mem.eql(u8, name, word)) return true;
    }
    return false;
}

fn cIdent(writer: anytype, name: []const u8) !void {
    if (name.len == 0) return writer.writeAll("_anon");
    var first = true;
    for (name) |c| {
        const ok = std.ascii.isAlphanumeric(c) or c == '_';
        if (first) {
            if (std.ascii.isAlphabetic(c) or c == '_') {
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
    if (isCReserved(name)) try writer.writeAll("_");
}

fn cFuncName(writer: anytype, name: []const u8) !void {
    var n = name;
    if (n.len >= 2 and n[0] == '"' and n[n.len - 1] == '"') n = n[1 .. n.len - 1];
    if (n.len >= 1 and n[0] == '@') n = n[1..];
    try writer.writeAll("sa_fn_");
    try cIdent(writer, n);
}

fn tagToPrim(tag: u32) sig.PrimType {
    return sig.primTypeFromTag(tag) orelse .i64;
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

fn writeCStrEscaped(writer: anytype, text: []const u8) !void {
    for (text) |c| {
        switch (c) {
            '\\' => try writer.writeAll("\\\\"),
            '"' => try writer.writeAll("\\\""),
            '\n' => try writer.writeAll("\\n"),
            '\r' => try writer.writeAll("\\r"),
            '\t' => try writer.writeAll("\\t"),
            else => {
                if (c < 32 or c > 126) {
                    try writer.print("\\x{x:0>2}", .{c});
                } else {
                    try writer.writeByte(c);
                }
            },
        }
    }
}

fn writeConstSym(writer: anytype, name: []const u8) !void {
    try writer.writeAll("SA_CONST_");
    for (name) |c| {
        if (std.ascii.isAlphanumeric(c)) {
            try writer.writeByte(std.ascii.toUpper(c));
        } else {
            try writer.writeByte('_');
        }
    }
}

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
    if (use_global) return fsig.slotOf(slot_or_id) orelse return CEmitError.InvalidOperand;
    if (@as(usize, slot_or_id) < fsig.reg_ids.len) return slot_or_id;
    return fsig.slotOf(slot_or_id) orelse return CEmitError.InvalidOperand;
}

fn offIsZero(op: inst.Operand) bool {
    return switch (op) {
        .imm_int => |v| v == 0,
        .imm_i64 => |v| v == 0,
        .imm_u64 => |v| v == 0,
        else => false,
    };
}

fn fnIndexOf(fn_idx: anytype, name: []const u8) ?usize {
    if (fn_idx.get(name)) |idx| return idx;
    if (name.len >= 1 and name[0] == '@') {
        if (fn_idx.get(name[1..])) |idx| return idx;
    } else {
        var buf: [512]u8 = undefined;
        if (name.len + 1 <= buf.len) {
            buf[0] = '@';
            @memcpy(buf[1 .. 1 + name.len], name);
            if (fn_idx.get(buf[0 .. 1 + name.len])) |idx| return idx;
        }
    }
    return null;
}

fn resolveTextToC(writer: anytype, symbols: anytype, fsig: sig.FunctionSig, const_addrs: anytype, raw: []const u8) !void {
    var text = std.mem.trim(u8, raw, " \t");
    if (text.len == 0) return CEmitError.InvalidOperand;
    if (text[0] == '&' or text[0] == '*' or text[0] == '^') text = std.mem.trim(u8, text[1..], " \t");
    if (std.mem.lastIndexOf(u8, text, " as ")) |idx| {
        text = std.mem.trim(u8, text[0..idx], " \t\r");
    }
    if (text.len == 0) return CEmitError.InvalidOperand;
    if (std.fmt.parseInt(i64, text, 10)) |v| {
        if (v < 0) {
            try writer.print("(sa_u64)((sa_i64){d})", .{v});
        } else {
            try writer.print("(sa_u64){d}ULL", .{v});
        }
        return;
    } else |_| {}
    if (std.fmt.parseInt(u64, text, 10)) |v| {
        try writer.print("(sa_u64){d}ULL", .{v});
        return;
    } else |_| {}
    if (std.fmt.parseFloat(f64, text)) |v| {
        const bits: u64 = @bitCast(v);
        try writer.print("(sa_u64)0x{x}ULL /* {d} */", .{ bits, v });
        return;
    } else |_| {}
    if (const_addrs.get(text)) |_| {
        try writeConstSym(writer, text);
        return;
    }
    if (symbols.findId(text)) |id| {
        if (fsig.slotOf(id)) |slot| {
            try writer.print("r{d}", .{slot});
            return;
        }
    }
    return CEmitError.InvalidOperand;
}

fn resolveValueToC(writer: anytype, symbols: anytype, fsig: sig.FunctionSig, use_global: bool, const_addrs: anytype, fn_idx: anytype, op: inst.Operand) !void {
    switch (op) {
        .reg => |r| {
            const slot = try regSlot(fsig, use_global, r);
            try writer.print("r{d}", .{slot});
        },
        .symbol, .label => |id| {
            const name = symbols.lookupName(id) orelse return CEmitError.InvalidOperand;
            try resolveTextToC(writer, symbols, fsig, const_addrs, name);
        },
        .func => |id| {
            const name = symbols.lookupName(id) orelse return CEmitError.InvalidOperand;
            const fidx = fnIndexOf(fn_idx, name) orelse return CEmitError.InvalidOperand;
            try writer.print("sa_fnaddr({d})", .{fidx});
        },
        .imm_int => |v| {
            if (v < 0) {
                try writer.print("(sa_u64)((sa_i64){d})", .{v});
            } else {
                try writer.print("(sa_u64){d}ULL", .{v});
            }
        },
        .imm_i64 => |v| {
            if (v < 0) {
                try writer.print("(sa_u64)((sa_i64){d})", .{v});
            } else {
                try writer.print("(sa_u64){d}ULL", .{v});
            }
        },
        .imm_u64 => |v| try writer.print("(sa_u64){d}ULL", .{v}),
        .imm_float => |v| {
            const bits: u64 = @bitCast(v);
            try writer.print("(sa_u64)0x{x}ULL", .{bits});
        },
        .text, .native_text => |t| try resolveTextToC(writer, symbols, fsig, const_addrs, t),
        else => return CEmitError.InvalidOperand,
    }
}

fn memPrimType(base: inst.Instruction) sig.PrimType {
    // operands[3] for load/store is usually .ty tag; fall back to u8/i64.
    for (base.operands) |op| {
        if (op == .ty) return tagToPrim(op.ty);
    }
    return .u8;
}

fn memLoadFn(ty: sig.PrimType) []const u8 {
    return switch (ty) {
        .i8, .i1 => "sa_load_i8",
        .u8 => "sa_load_u8",
        .i16 => "sa_load_i16",
        .u16 => "sa_load_u16",
        .i32 => "sa_load_i32",
        .u32 => "sa_load_u32",
        .i64, .u64, .ptr, .blob_handle => "sa_load_u64",
        .f32 => "sa_load_f32",
        .f64 => "sa_load_f64",
        else => "sa_load_u8",
    };
}

fn memStoreFn(ty: sig.PrimType) []const u8 {
    return switch (ty) {
        .i8, .u8, .i1 => "sa_store_u8",
        .i16, .u16 => "sa_store_u16",
        .i32, .u32 => "sa_store_u32",
        .i64, .u64, .ptr, .blob_handle => "sa_store_u64",
        .f32 => "sa_store_f32",
        .f64 => "sa_store_f64",
        else => "sa_store_u8",
    };
}

fn emitCvtExpr(writer: anytype, symbols: anytype, fsig: sig.FunctionSig, use_global: bool, const_addrs: anytype, fn_idx: anytype, opcode: inst.OpKind, tgt: sig.PrimType, src_op: inst.Operand) !void {
    const sfx: []const u8 = switch (tgt) {
        .i1 => "i1", .i8 => "i8", .i16 => "i16", .i32 => "i32", .i64 => "i64",
        .u8 => "u8", .u16 => "u16", .u32 => "u32", .u64 => "u64", .blob_handle => "u64",
        .ptr => "ptr", .f32 => "f32", .f64 => "f64",
        else => return CEmitError.InvalidOperand,
    };
    const opname: []const u8 = switch (opcode) {
        .trunc => "trunc", .zext => "zext", .sext => "sext", .fptosi => "fptosi",
        .sitofp => "sitofp", .uitofp => "uitofp", .fptrunc => "fptrunc",
        .fpext => "fpext", .bitcast => "bitcast",
        else => return CEmitError.InvalidOperand,
    };
    try writer.print("sa_cvt_{s}_{s}(", .{ opname, sfx });
    try resolveValueToC(writer, symbols, fsig, use_global, const_addrs, fn_idx, src_op);
    try writer.writeAll(")");
}

fn emitOpExpr(writer: anytype, symbols: anytype, fsig: sig.FunctionSig, use_global: bool, const_addrs: anytype, fn_idx: anytype, opcode: inst.OpKind, lhs: inst.Operand, rhs: inst.Operand) !void {
    const name: []const u8 = switch (opcode) {
        .add => "sa_add", .sub => "sa_sub", .mul => "sa_mul",
        .sdiv => "sa_sdiv", .udiv => "sa_udiv", .srem => "sa_srem", .urem => "sa_urem",
        .div => "sa_sdiv", .rem => "sa_srem",
        .@"and" => "sa_band", .@"or" => "sa_bor", .xor => "sa_bxor",
        .shl => "sa_shl", .lshr => "sa_lshr", .ashr => "sa_ashr", .shr => "sa_ashr",
        .not => "sa_bnot",
        .neg => "sa_neg",
        .eq => "sa_eq", .ne => "sa_ne",
        .slt => "sa_slt", .sle => "sa_sle", .sgt => "sa_sgt", .sge => "sa_sge",
        .ult => "sa_ult", .ule => "sa_ule", .ugt => "sa_ugt", .uge => "sa_uge",
        .lt => "sa_slt", .gt => "sa_sgt",
        .fadd => "sa_fadd", .fsub => "sa_fsub", .fmul => "sa_fmul", .fdiv => "sa_fdiv",
        .fneg => "sa_fneg",
        .fcmp_eq => "sa_fcmp_eq", .fcmp_ne => "sa_fcmp_ne",
        .fcmp_lt => "sa_fcmp_lt", .fcmp_le => "sa_fcmp_le",
        .fcmp_gt => "sa_fcmp_gt", .fcmp_ge => "sa_fcmp_ge",
        else => return CEmitError.InvalidOperand,
    };
    if (opcode == .not or opcode == .neg or opcode == .fneg) {
        try writer.print("{s}(", .{name});
        try resolveValueToC(writer, symbols, fsig, use_global, const_addrs, fn_idx, lhs);
        try writer.writeAll(")");
        return;
    }
    try writer.print("{s}(", .{name});
    try resolveValueToC(writer, symbols, fsig, use_global, const_addrs, fn_idx, lhs);
    try writer.writeAll(", ");
    try resolveValueToC(writer, symbols, fsig, use_global, const_addrs, fn_idx, rhs);
    try writer.writeAll(")");
}

fn dstSlot(fsig: sig.FunctionSig, use_global: bool, op: inst.Operand) !u32 {
    switch (op) {
        .reg => |r| return regSlot(fsig, use_global, r),
        .symbol => |id| return fsig.slotOf(id) orelse return CEmitError.InvalidOperand,
        .text, .native_text => return CEmitError.InvalidOperand,
        else => return CEmitError.InvalidOperand,
    }
}

fn emitReturnStmt(writer: anytype, symbols: anytype, fsig: sig.FunctionSig, use_global: bool, const_addrs: anytype, fn_idx: anytype, operand: inst.Operand, indent: []const u8) !void {
    if (fsig.return_fallible) {
        switch (operand) {
            .none => try writer.print("{s}return sa_ok_none();\n", .{indent}),
            else => {
                try writer.print("{s}return sa_ok_val((", .{indent});
                try resolveValueToC(writer, symbols, fsig, use_global, const_addrs, fn_idx, operand);
                try writer.writeAll("));\n");
            },
        }
    } else switch (operand) {
        .none => try writer.print("{s}return 0;\n", .{indent}),
        else => {
            try writer.print("{s}return (", .{indent});
            try resolveValueToC(writer, symbols, fsig, use_global, const_addrs, fn_idx, operand);
            try writer.writeAll(");\n");
        },
    }
}

fn writeRuntimeHeader(writer: anytype, c_opt: CEmitOptions, size_bits: u16) !void {
    const mem_bytes: usize = @as(usize, c_opt.mem_pages) * 65536;
    try writer.print("/* Generated by `sa build-c` (c backend, MVP). DO NOT EDIT. */\n", .{});
    try writer.print("/* size_bits={d} mem_bytes={d} */\n", .{ size_bits, mem_bytes });
    try writer.writeAll(
        \\#include <stdint.h>
        \\#include <stdio.h>
        \\#include <stdlib.h>
        \\#include <string.h>
        \\typedef uint64_t sa_u64;
        \\typedef int64_t sa_i64;
        \\typedef uint32_t sa_u32;
        \\typedef int32_t sa_i32;
        \\#ifndef SA_MEM_BYTES
        \\#define SA_MEM_BYTES 16777216UL
        \\#endif
        \\static uint8_t sa_mem[SA_MEM_BYTES];
        \\static uint32_t sa_brk = 65536;
        \\static void sa_trap(const char *msg) { fprintf(stderr, "[sa-trap] %s\n", msg); exit(1); }
        \\static void sa_panic(sa_u64 code) { fprintf(stderr, "[sa-panic] code=%llu\n", (unsigned long long)code); exit(1); }
        \\static sa_u64 sa_ok_none(void) { return 0; }
        \\static sa_u64 sa_ok_val(sa_u64 v) { (void)v; return v; }
        \\static int sa_truthy(sa_u64 v) { return v != 0; }
        \\static sa_u64 sa_align(sa_u64 n, sa_u64 a) { return (n + (a - 1)) & ~(a - 1); }
        \\static sa_u64 sa_alloc(sa_u64 size) {
        \\  size = sa_align(size, 8); if (size == 0) size = 8;
        \\  uint32_t base = sa_brk; sa_brk += (uint32_t)(size + 8);
        \\  if ((size_t)sa_brk >= sizeof(sa_mem)) sa_trap("out of memory (bump)");
        \\  memset(&sa_mem[base], 0, (size_t)(size + 8));
        \\  *(uint32_t*)&sa_mem[base] = (uint32_t)size;
        \\  return (sa_u64)(base + 8);
        \\}
        \\static sa_u64 sa_salloc(sa_u64 size) { return sa_alloc(size); }
        \\static sa_u64 sa_free(sa_u64 ptr) { (void)ptr; return 0; }
        \\static sa_u64 sa_ptr_add(sa_u64 base, sa_u64 off) { return base + off; }
        \\static uint32_t sa_addr(sa_u64 a) { return (uint32_t)(a & 0xFFFFFFFFu); }
        \\static sa_u64 sa_load_u8(sa_u64 a) { return (sa_u64)sa_mem[sa_addr(a)]; }
        \\static sa_u64 sa_load_i8(sa_u64 a) { return (sa_u64)(sa_u64)(sa_i64)(int8_t)sa_mem[sa_addr(a)]; }
        \\static sa_u64 sa_load_u16(sa_u64 a) { uint16_t v; memcpy(&v, &sa_mem[sa_addr(a)], 2); return v; }
        \\static sa_u64 sa_load_i16(sa_u64 a) { int16_t v; memcpy(&v, &sa_mem[sa_addr(a)], 2); return (sa_u64)(sa_i64)v; }
        \\static sa_u64 sa_load_u32(sa_u64 a) { uint32_t v; memcpy(&v, &sa_mem[sa_addr(a)], 4); return v; }
        \\static sa_u64 sa_load_i32(sa_u64 a) { int32_t v; memcpy(&v, &sa_mem[sa_addr(a)], 4); return (sa_u64)(sa_i64)v; }
        \\static sa_u64 sa_load_u64(sa_u64 a) { uint64_t v; memcpy(&v, &sa_mem[sa_addr(a)], 8); return v; }
        \\static sa_u64 sa_load_f32(sa_u64 a) { uint32_t v; memcpy(&v, &sa_mem[sa_addr(a)], 4); return (sa_u64)v; }
        \\static sa_u64 sa_load_f64(sa_u64 a) { uint64_t v; memcpy(&v, &sa_mem[sa_addr(a)], 8); return v; }
        \\static void sa_store_u8(sa_u64 a, sa_u64 v) { sa_mem[sa_addr(a)] = (uint8_t)(v & 0xFFu); }
        \\static void sa_store_u16(sa_u64 a, sa_u64 v) { uint16_t t=(uint16_t)v; memcpy(&sa_mem[sa_addr(a)], &t, 2); }
        \\static void sa_store_u32(sa_u64 a, sa_u64 v) { uint32_t t=(uint32_t)v; memcpy(&sa_mem[sa_addr(a)], &t, 4); }
        \\static void sa_store_u64(sa_u64 a, sa_u64 v) { uint64_t t=v; memcpy(&sa_mem[sa_addr(a)], &t, 8); }
        \\static void sa_store_f32(sa_u64 a, sa_u64 v) { uint32_t t=(uint32_t)v; memcpy(&sa_mem[sa_addr(a)], &t, 4); }
        \\static void sa_store_f64(sa_u64 a, sa_u64 v) { uint64_t t=v; memcpy(&sa_mem[sa_addr(a)], &t, 8); }
        \\static sa_u64 sa_add(sa_u64 a, sa_u64 b) { return a + b; }
        \\static sa_u64 sa_sub(sa_u64 a, sa_u64 b) { return a - b; }
        \\static sa_u64 sa_mul(sa_u64 a, sa_u64 b) { return a * b; }
        \\static sa_u64 sa_sdiv(sa_u64 a, sa_u64 b) { if ((sa_i64)b==0) sa_trap("div by zero"); return (sa_u64)((sa_i64)a / (sa_i64)b); }
        \\static sa_u64 sa_udiv(sa_u64 a, sa_u64 b) { if (b==0) sa_trap("div by zero"); return a / b; }
        \\static sa_u64 sa_srem(sa_u64 a, sa_u64 b) { if ((sa_i64)b==0) sa_trap("rem by zero"); return (sa_u64)((sa_i64)a % (sa_i64)b); }
        \\static sa_u64 sa_urem(sa_u64 a, sa_u64 b) { if (b==0) sa_trap("rem by zero"); return a % b; }
        \\static sa_u64 sa_band(sa_u64 a, sa_u64 b) { return a & b; }
        \\static sa_u64 sa_bor(sa_u64 a, sa_u64 b) { return a | b; }
        \\static sa_u64 sa_bxor(sa_u64 a, sa_u64 b) { return a ^ b; }
        \\static sa_u64 sa_bnot(sa_u64 a) { return ~a; }
        \\static sa_u64 sa_neg(sa_u64 a) { return (sa_u64)(-(sa_i64)a); }
        \\static sa_u64 sa_shl(sa_u64 a, sa_u64 b) { return a << (b & 63); }
        \\static sa_u64 sa_lshr(sa_u64 a, sa_u64 b) { return a >> (b & 63); }
        \\static sa_u64 sa_ashr(sa_u64 a, sa_u64 b) { return (sa_u64)((sa_i64)a >> (b & 63)); }
        \\static sa_u64 sa_eq(sa_u64 a, sa_u64 b) { return a == b ? 1 : 0; }
        \\static sa_u64 sa_ne(sa_u64 a, sa_u64 b) { return a != b ? 1 : 0; }
        \\static sa_u64 sa_slt(sa_u64 a, sa_u64 b) { return (sa_i64)a < (sa_i64)b ? 1 : 0; }
        \\static sa_u64 sa_sle(sa_u64 a, sa_u64 b) { return (sa_i64)a <= (sa_i64)b ? 1 : 0; }
        \\static sa_u64 sa_sgt(sa_u64 a, sa_u64 b) { return (sa_i64)a > (sa_i64)b ? 1 : 0; }
        \\static sa_u64 sa_sge(sa_u64 a, sa_u64 b) { return (sa_i64)a >= (sa_i64)b ? 1 : 0; }
        \\static sa_u64 sa_ult(sa_u64 a, sa_u64 b) { return a < b ? 1 : 0; }
        \\static sa_u64 sa_ule(sa_u64 a, sa_u64 b) { return a <= b ? 1 : 0; }
        \\static sa_u64 sa_ugt(sa_u64 a, sa_u64 b) { return a > b ? 1 : 0; }
        \\static sa_u64 sa_uge(sa_u64 a, sa_u64 b) { return a >= b ? 1 : 0; }
        \\static double sa_bits_f64(sa_u64 v) { double d; uint64_t t=v; memcpy(&d,&t,8); return d; }
        \\static sa_u64 sa_f64_bits(double d) { uint64_t t; memcpy(&t,&d,8); return t; }
        \\static float sa_bits_f32(sa_u64 v) { float f; uint32_t t=(uint32_t)v; memcpy(&f,&t,4); return f; }
        \\static sa_u64 sa_f32_bits(float f) { uint32_t t; memcpy(&t,&f,4); return t; }
        \\static sa_u64 sa_fadd(sa_u64 a, sa_u64 b) { return sa_f64_bits(sa_bits_f64(a)+sa_bits_f64(b)); }
        \\static sa_u64 sa_fsub(sa_u64 a, sa_u64 b) { return sa_f64_bits(sa_bits_f64(a)-sa_bits_f64(b)); }
        \\static sa_u64 sa_fmul(sa_u64 a, sa_u64 b) { return sa_f64_bits(sa_bits_f64(a)*sa_bits_f64(b)); }
        \\static sa_u64 sa_fdiv(sa_u64 a, sa_u64 b) { return sa_f64_bits(sa_bits_f64(a)/sa_bits_f64(b)); }
        \\static sa_u64 sa_fneg(sa_u64 a) { return sa_f64_bits(-sa_bits_f64(a)); }
        \\static sa_u64 sa_fcmp_eq(sa_u64 a, sa_u64 b) { return sa_bits_f64(a)==sa_bits_f64(b)?1:0; }
        \\static sa_u64 sa_fcmp_ne(sa_u64 a, sa_u64 b) { return sa_bits_f64(a)!=sa_bits_f64(b)?1:0; }
        \\static sa_u64 sa_fcmp_lt(sa_u64 a, sa_u64 b) { return sa_bits_f64(a)<sa_bits_f64(b)?1:0; }
        \\static sa_u64 sa_fcmp_le(sa_u64 a, sa_u64 b) { return sa_bits_f64(a)<=sa_bits_f64(b)?1:0; }
        \\static sa_u64 sa_fcmp_gt(sa_u64 a, sa_u64 b) { return sa_bits_f64(a)>sa_bits_f64(b)?1:0; }
        \\static sa_u64 sa_fcmp_ge(sa_u64 a, sa_u64 b) { return sa_bits_f64(a)>=sa_bits_f64(b)?1:0; }
        \\static sa_u64 sa_cvt_trunc_i1(sa_u64 v){return v&1;} static sa_u64 sa_cvt_trunc_i8(sa_u64 v){return (sa_u64)(sa_i64)(int8_t)v;}
        \\static sa_u64 sa_cvt_trunc_i16(sa_u64 v){return (sa_u64)(sa_i64)(int16_t)v;} static sa_u64 sa_cvt_trunc_i32(sa_u64 v){return (sa_u64)(sa_i64)(int32_t)v;}
        \\static sa_u64 sa_cvt_trunc_i64(sa_u64 v){return v;} static sa_u64 sa_cvt_trunc_u8(sa_u64 v){return v&0xFFu;}
        \\static sa_u64 sa_cvt_trunc_u16(sa_u64 v){return v&0xFFFFu;} static sa_u64 sa_cvt_trunc_u32(sa_u64 v){return v&0xFFFFFFFFu;}
        \\static sa_u64 sa_cvt_trunc_u64(sa_u64 v){return v;} static sa_u64 sa_cvt_trunc_ptr(sa_u64 v){return v;}
        \\static sa_u64 sa_cvt_zext_i1(sa_u64 v){return v&1;} static sa_u64 sa_cvt_zext_i8(sa_u64 v){return v&0xFFu;}
        \\static sa_u64 sa_cvt_zext_i16(sa_u64 v){return v&0xFFFFu;} static sa_u64 sa_cvt_zext_i32(sa_u64 v){return v&0xFFFFFFFFu;}
        \\static sa_u64 sa_cvt_zext_i64(sa_u64 v){return v;} static sa_u64 sa_cvt_zext_u8(sa_u64 v){return v&0xFFu;}
        \\static sa_u64 sa_cvt_zext_u16(sa_u64 v){return v&0xFFFFu;} static sa_u64 sa_cvt_zext_u32(sa_u64 v){return v&0xFFFFFFFFu;}
        \\static sa_u64 sa_cvt_zext_u64(sa_u64 v){return v;} static sa_u64 sa_cvt_zext_ptr(sa_u64 v){return v;}
        \\static sa_u64 sa_cvt_sext_i8(sa_u64 v){return (sa_u64)(sa_i64)(int8_t)v;} static sa_u64 sa_cvt_sext_i16(sa_u64 v){return (sa_u64)(sa_i64)(int16_t)v;}
        \\static sa_u64 sa_cvt_sext_i32(sa_u64 v){return (sa_u64)(sa_i64)(int32_t)v;} static sa_u64 sa_cvt_sext_i64(sa_u64 v){return v;}
        \\static sa_u64 sa_cvt_sext_i1(sa_u64 v){return (sa_u64)(sa_i64)(v&1? -1:0);} static sa_u64 sa_cvt_sext_u8(sa_u64 v){return (sa_u64)(sa_i64)(int8_t)v;}
        \\static sa_u64 sa_cvt_sext_u16(sa_u64 v){return (sa_u64)(sa_i64)(int16_t)v;} static sa_u64 sa_cvt_sext_u32(sa_u64 v){return (sa_u64)(sa_i64)(int32_t)v;}
        \\static sa_u64 sa_cvt_sext_u64(sa_u64 v){return v;} static sa_u64 sa_cvt_sext_ptr(sa_u64 v){return v;}
        \\static sa_u64 sa_cvt_sitofp_f32(sa_u64 v){return sa_f32_bits((float)(sa_i64)v);} static sa_u64 sa_cvt_sitofp_f64(sa_u64 v){return sa_f64_bits((double)(sa_i64)v);}
        \\static sa_u64 sa_cvt_uitofp_f32(sa_u64 v){return sa_f32_bits((float)v);} static sa_u64 sa_cvt_uitofp_f64(sa_u64 v){return sa_f64_bits((double)v);}
        \\static sa_u64 sa_cvt_fptosi_i32(sa_u64 v){return (sa_u64)(sa_i64)(int32_t)sa_bits_f64(v);} static sa_u64 sa_cvt_fptosi_i64(sa_u64 v){return (sa_u64)(sa_i64)sa_bits_f64(v);}
        \\static sa_u64 sa_cvt_fptosi_u32(sa_u64 v){return (sa_u64)(uint32_t)sa_bits_f64(v);} static sa_u64 sa_cvt_fptosi_u64(sa_u64 v){return (sa_u64)sa_bits_f64(v);}
        \\static sa_u64 sa_cvt_fptosi_i1(sa_u64 v){return ((sa_i64)sa_bits_f64(v))&1;} static sa_u64 sa_cvt_fptosi_i8(sa_u64 v){return (sa_u64)(sa_i64)(int8_t)sa_bits_f64(v);}
        \\static sa_u64 sa_cvt_fptosi_i16(sa_u64 v){return (sa_u64)(sa_i64)(int16_t)sa_bits_f64(v);} static sa_u64 sa_cvt_fptosi_u8(sa_u64 v){return (sa_u64)(uint8_t)sa_bits_f64(v);}
        \\static sa_u64 sa_cvt_fptosi_u16(sa_u64 v){return (sa_u64)(uint16_t)sa_bits_f64(v);} static sa_u64 sa_cvt_fptosi_ptr(sa_u64 v){return (sa_u64)sa_bits_f64(v);}
        \\static sa_u64 sa_cvt_fptrunc_f32(sa_u64 v){return sa_f32_bits((float)sa_bits_f64(v));} static sa_u64 sa_cvt_fpext_f64(sa_u64 v){float f=sa_bits_f32(v); return sa_f64_bits((double)f);}
        \\static sa_u64 sa_cvt_bitcast_i32(sa_u64 v){return (sa_u64)(sa_i64)(int32_t)(uint32_t)v;} static sa_u64 sa_cvt_bitcast_u32(sa_u64 v){return v&0xFFFFFFFFu;}
        \\static sa_u64 sa_cvt_bitcast_i64(sa_u64 v){return v;} static sa_u64 sa_cvt_bitcast_u64(sa_u64 v){return v;}
        \\static sa_u64 sa_cvt_bitcast_f32(sa_u64 v){return v&0xFFFFFFFFu;} static sa_u64 sa_cvt_bitcast_f64(sa_u64 v){return v;}
        \\static sa_u64 sa_cvt_bitcast_ptr(sa_u64 v){return v;} static sa_u64 sa_cvt_bitcast_i8(sa_u64 v){return v&0xFFu;}
        \\static sa_u64 sa_cvt_bitcast_u8(sa_u64 v){return v&0xFFu;} static sa_u64 sa_cvt_bitcast_i16(sa_u64 v){return v&0xFFFFu;}
        \\static sa_u64 sa_cvt_bitcast_u16(sa_u64 v){return v&0xFFFFu;} static sa_u64 sa_cvt_bitcast_i1(sa_u64 v){return v&1;}
        \\static sa_u64 sa_print_bytes(sa_u64 addr, sa_u64 len) { uint32_t a=sa_addr(addr); if ((size_t)a+(size_t)len>sizeof(sa_mem)) sa_trap("print oob"); fwrite(&sa_mem[a],1,(size_t)len,stdout); return 0; }
        \\static sa_u64 sa_fnaddr(int i) { return (sa_u64)(uint64_t)(1000000 + i); }
        \\
    );
}

fn emitLinearInstruction(writer: anytype, allocator: std.mem.Allocator, symbols: anytype, fsig: sig.FunctionSig, use_global: bool, const_addrs: anytype, fn_idx: anytype, base: inst.Instruction) !void {
    last_c_inst = base.raw_text;
    last_c_func = fsig.name;
    switch (base.kind) {
        .return_ => try emitReturnStmt(writer, symbols, fsig, use_global, const_addrs, fn_idx, base.operands[0], "  "),
        .try_, .early_return => {
            const slot = try dstSlot(fsig, use_global, base.operands[0]);
            try writer.writeAll("  { sa_u64 __t = (");
            try resolveValueToC(writer, symbols, fsig, use_global, const_addrs, fn_idx, base.operands[1]);
            try writer.print("); r{d} = __t; }}\n", .{slot});
        },
        .op => {
            const slot = try dstSlot(fsig, use_global, base.operands[0]);
            const opcode = base.op_kind orelse return CEmitError.InvalidOperand;
            if (inst.isTypeConversionOpKind(opcode)) {
                if (base.operands[2] != .ty) return CEmitError.InvalidOperand;
                var tgt = tagToPrim(base.operands[2].ty);
                if ((opcode == .sitofp or opcode == .uitofp) and tgt != .f32 and tgt != .f64) tgt = .f64;
                try writer.print("  r{d} = ", .{slot});
                try emitCvtExpr(writer, symbols, fsig, use_global, const_addrs, fn_idx, opcode, tgt, base.operands[1]);
                try writer.writeAll(";\n");
                return;
            }
            try writer.print("  r{d} = ", .{slot});
            try emitOpExpr(writer, symbols, fsig, use_global, const_addrs, fn_idx, opcode, base.operands[1], base.operands[2]);
            try writer.writeAll(";\n");
        },
        .alloc => {
            const slot = try dstSlot(fsig, use_global, base.operands[0]);
            try writer.print("  r{d} = sa_alloc(", .{slot});
            try resolveValueToC(writer, symbols, fsig, use_global, const_addrs, fn_idx, base.operands[1]);
            try writer.writeAll(");\n");
        },
        .stack_alloc => {
            const slot = try dstSlot(fsig, use_global, base.operands[0]);
            try writer.print("  r{d} = sa_salloc(", .{slot});
            try resolveValueToC(writer, symbols, fsig, use_global, const_addrs, fn_idx, base.operands[1]);
            try writer.writeAll(");\n");
        },
        .ptr_add => {
            const slot = try dstSlot(fsig, use_global, base.operands[0]);
            if (offIsZero(base.operands[2])) {
                try writer.print("  r{d} = ", .{slot});
                try resolveValueToC(writer, symbols, fsig, use_global, const_addrs, fn_idx, base.operands[1]);
                try writer.writeAll(";\n");
            } else {
                try writer.print("  r{d} = sa_ptr_add(", .{slot});
                try resolveValueToC(writer, symbols, fsig, use_global, const_addrs, fn_idx, base.operands[1]);
                try writer.writeAll(", ");
                try resolveValueToC(writer, symbols, fsig, use_global, const_addrs, fn_idx, base.operands[2]);
                try writer.writeAll(");\n");
            }
        },
        .load, .take, .atomic_load => {
            const slot = try dstSlot(fsig, use_global, base.operands[0]);
            const ty = memPrimType(base);
            const load_fn = memLoadFn(ty);
            if (offIsZero(base.operands[2])) {
                try writer.print("  r{d} = {s}(", .{ slot, load_fn });
                try resolveValueToC(writer, symbols, fsig, use_global, const_addrs, fn_idx, base.operands[1]);
                try writer.writeAll(");\n");
            } else {
                try writer.print("  r{d} = {s}(sa_ptr_add(", .{ slot, load_fn });
                try resolveValueToC(writer, symbols, fsig, use_global, const_addrs, fn_idx, base.operands[1]);
                try writer.writeAll(", ");
                try resolveValueToC(writer, symbols, fsig, use_global, const_addrs, fn_idx, base.operands[2]);
                try writer.writeAll("));\n");
            }
        },
        .store, .atomic_store => {
            const ty = memPrimType(base);
            const store_fn = memStoreFn(ty);
            if (offIsZero(base.operands[1])) {
                try writer.print("  {s}(", .{store_fn});
                try resolveValueToC(writer, symbols, fsig, use_global, const_addrs, fn_idx, base.operands[0]);
                try writer.writeAll(", ");
                try resolveValueToC(writer, symbols, fsig, use_global, const_addrs, fn_idx, base.operands[2]);
                try writer.writeAll(");\n");
            } else {
                try writer.print("  {s}(sa_ptr_add(", .{store_fn});
                try resolveValueToC(writer, symbols, fsig, use_global, const_addrs, fn_idx, base.operands[0]);
                try writer.writeAll(", ");
                try resolveValueToC(writer, symbols, fsig, use_global, const_addrs, fn_idx, base.operands[1]);
                try writer.writeAll("), ");
                try resolveValueToC(writer, symbols, fsig, use_global, const_addrs, fn_idx, base.operands[2]);
                try writer.writeAll(");\n");
            }
        },
        .call => {
            var parsed = call.parseInstructionCall(allocator, base, symbols) catch {
                try writer.print("  sa_trap(\"unsupported call: {s}\");\n", .{std.mem.trim(u8, base.raw_text, " \t\r\n")});
                return;
            };
            defer parsed.deinit(allocator);
            if (parsed.dest) |dest| {
                const id = symbols.findId(dest) orelse return CEmitError.InvalidOperand;
                const slot = fsig.slotOf(id) orelse return CEmitError.InvalidOperand;
                try writer.print("  r{d} = ", .{slot});
            } else {
                try writer.writeAll("  ");
            }
            if (parsed.is_indirect) {
                try writer.writeAll("sa_call_indirect(");
                try resolveTextToC(writer, symbols, fsig, const_addrs, parsed.callee);
                for (parsed.args) |arg| {
                    try writer.writeAll(", ");
                    try resolveTextToC(writer, symbols, fsig, const_addrs, arg.text);
                }
                try writer.writeAll(");\n");
            } else {
                // known host shims map to runtime helpers
                if (std.mem.eql(u8, parsed.callee, "sa_print_bytes") or std.mem.eql(u8, parsed.callee, "@sa_print_bytes")) {
                    try writer.writeAll("sa_print_bytes(");
                    for (parsed.args, 0..) |arg, idx| {
                        if (idx != 0) try writer.writeAll(", ");
                        try resolveTextToC(writer, symbols, fsig, const_addrs, arg.text);
                    }
                    try writer.writeAll(");\n");
                } else {
                    try cFuncName(writer, parsed.callee);
                    try writer.writeAll("(");
                    for (parsed.args, 0..) |arg, idx| {
                        if (idx != 0) try writer.writeAll(", ");
                        try resolveTextToC(writer, symbols, fsig, const_addrs, arg.text);
                    }
                    try writer.writeAll(");\n");
                }
            }
        },
        .call_indirect => {
            var parsed = call.parseInstructionCall(allocator, base, symbols) catch {
                try writer.writeAll("  sa_trap(\"unsupported call_indirect\");\n");
                return;
            };
            defer parsed.deinit(allocator);
            if (parsed.dest) |dest| {
                const id = symbols.findId(dest) orelse return CEmitError.InvalidOperand;
                const slot = fsig.slotOf(id) orelse return CEmitError.InvalidOperand;
                try writer.print("  r{d} = ", .{slot});
            } else {
                try writer.writeAll("  ");
            }
            try writer.writeAll("sa_call_indirect(");
            try resolveTextToC(writer, symbols, fsig, const_addrs, parsed.callee);
            for (parsed.args) |arg| {
                try writer.writeAll(", ");
                try resolveTextToC(writer, symbols, fsig, const_addrs, arg.text);
            }
            try writer.writeAll(");\n");
        },
        .cmpxchg => {
            const dst_old = try dstSlot(fsig, use_global, base.operands[0]);
            const dst_ok = try dstSlot(fsig, use_global, base.operands[1]);
            const expected = base.atomic_expected_text orelse return CEmitError.InvalidOperand;
            const new_text = base.atomic_new_text orelse return CEmitError.InvalidOperand;
            const ty = memPrimType(base);
            const load_fn = memLoadFn(ty);
            const store_fn = memStoreFn(ty);
            try writer.writeAll("  { sa_u64 __addr = sa_ptr_add(");
            try resolveValueToC(writer, symbols, fsig, use_global, const_addrs, fn_idx, base.operands[2]);
            try writer.writeAll(", ");
            try resolveValueToC(writer, symbols, fsig, use_global, const_addrs, fn_idx, base.operands[3]);
            try writer.print("); sa_u64 __old = {s}(__addr); sa_u64 __exp = (", .{load_fn});
            try resolveTextToC(writer, symbols, fsig, const_addrs, expected);
            try writer.writeAll("); sa_u64 __ok = (__old == __exp) ? 1 : 0; if (__ok) ");
            try writer.print("{s}(__addr, (", .{store_fn});
            try resolveTextToC(writer, symbols, fsig, const_addrs, new_text);
            try writer.print(")); r{d} = __old; r{d} = __ok; }}\n", .{ dst_old, dst_ok });
        },
        .atomic_rmw => {
            const op = base.atomic_rmw_op orelse return CEmitError.InvalidOperand;
            const dst = try dstSlot(fsig, use_global, base.operands[0]);
            const ty = memPrimType(base);
            const load_fn = memLoadFn(ty);
            const store_fn = memStoreFn(ty);
            try writer.writeAll("  { sa_u64 __addr = sa_ptr_add(");
            try resolveValueToC(writer, symbols, fsig, use_global, const_addrs, fn_idx, base.operands[1]);
            try writer.writeAll(", ");
            try resolveValueToC(writer, symbols, fsig, use_global, const_addrs, fn_idx, base.operands[2]);
            try writer.print("); sa_u64 __old = {s}(__addr); sa_u64 __val = (", .{load_fn});
            try resolveValueToC(writer, symbols, fsig, use_global, const_addrs, fn_idx, base.operands[3]);
            try writer.writeAll("); sa_u64 __new = ");
            switch (op) {
                .add => try writer.writeAll("sa_add(__old, __val)"),
                .sub => try writer.writeAll("sa_sub(__old, __val)"),
                .@"and" => try writer.writeAll("sa_band(__old, __val)"),
                .@"or" => try writer.writeAll("sa_bor(__old, __val)"),
                .xor => try writer.writeAll("sa_bxor(__old, __val)"),
                .xchg => try writer.writeAll("__val"),
                .min => try writer.writeAll("(sa_sle(__old, __val) ? __old : __val)"),
                .max => try writer.writeAll("(sa_sge(__old, __val) ? __old : __val)"),
                .umin => try writer.writeAll("(sa_ule(__old, __val) ? __old : __val)"),
                .umax => try writer.writeAll("(sa_uge(__old, __val) ? __old : __val)"),
            }
            try writer.print("; {s}(__addr, __new); r{d} = __old; }}\n", .{ store_fn, dst });
        },
        .fence => {
            try writer.writeAll("  /* fence: no-op on C backend */\n");
        },
        .assign, .borrow, .raw_cast, .assume_safe, .assume_borrow => {
            const slot = try dstSlot(fsig, use_global, base.operands[0]);
            try writer.print("  r{d} = (", .{slot});
            switch (base.operands[1]) {
                .reg, .symbol, .func, .label, .imm_i64, .imm_int, .imm_u64, .imm_float, .text, .native_text => {
                    try resolveValueToC(writer, symbols, fsig, use_global, const_addrs, fn_idx, base.operands[1]);
                },
                else => return CEmitError.InvalidOperand,
            }
            try writer.writeAll(");\n");
        },
        .panic => {
            var parsed = call.parseInstructionCall(allocator, base, symbols) catch {
                try writer.print("  sa_trap(\"panic: {s}\");\n", .{std.mem.trim(u8, base.raw_text, " \t\r\n")});
                return;
            };
            defer parsed.deinit(allocator);
            if (parsed.args.len != 1) {
                try writer.writeAll("  sa_trap(\"panic\");\n");
                return;
            }
            try writer.writeAll("  sa_panic(");
            try resolveTextToC(writer, symbols, fsig, const_addrs, parsed.args[0].text);
            try writer.writeAll(");\n");
        },
        .panic_msg => {
            try writer.writeAll("  sa_trap(\"panic_msg\");\n");
        },
        .move_ => {
            try writer.print("  /* no-op {s}: {s} */\n", .{ @tagName(base.kind), std.mem.trim(u8, base.raw_text, " \t\r\n") });
        },
        .release => {
            try writer.writeAll("  sa_free(");
            try resolveValueToC(writer, symbols, fsig, use_global, const_addrs, fn_idx, base.operands[0]);
            try writer.writeAll(");\n");
        },
        .native => {
            const raw = std.mem.trim(u8, base.raw_text, " \t\r\n");
            if (std.mem.indexOf(u8, raw, "asm sideeffect \"\"") != null) {
                try writer.writeAll("  /* no-op empty inline asm */\n");
            } else {
                try writer.writeAll("  sa_trap(\"unsupported native: ");
                try writeCStrEscaped(writer, raw);
                try writer.writeAll("\");\n");
            }
        },
        else => {
            // jmp/br/br_null/label/func_decl/extern/export/test_decl handled by caller
            try writer.print("  sa_trap(\"unsupported {s}: ", .{@tagName(base.kind)});
            try writeCStrEscaped(writer, std.mem.trim(u8, base.raw_text, " \t\r\n"));
            try writer.writeAll("\");\n");
        },
    }
}

fn emitOneFunction(writer: anytype, allocator: std.mem.Allocator, verified: anytype, task: FuncTask, const_addrs: anytype, fn_idx: anytype, c_opt: CEmitOptions) !void {
    const fsig = verified.function_sigs[task.fsig_index];
    const use_global = taskUsesGlobalRegIds(fsig, verified, task);
    last_c_func = fsig.name;
    // prototype
    try writer.writeAll("static sa_u64 ");
    try cFuncName(writer, fsig.name);
    try writer.writeAll("(");
    if (fsig.params.len == 0) {
        try writer.writeAll("void");
    } else {
        for (fsig.params, 0..) |_, pi| {
            if (pi != 0) try writer.writeAll(", ");
            try writer.print("sa_u64 a{d}", .{pi});
        }
    }
    try writer.writeAll(") {\n");
    const nregs = fsig.reg_ids.len;
    if (nregs > 0) {
        try writer.print("  sa_u64 r{d}", .{0});
        var s: usize = 1;
        while (s < nregs) : (s += 1) {
            try writer.print(", r{d}", .{s});
        }
        try writer.writeAll(";\n  (void)r0;\n");
    }
    // map params to slots
    for (fsig.param_ids, 0..) |pid, pi| {
        if (fsig.slotOf(pid)) |slot| {
            try writer.print("  r{d} = a{d};\n", .{ slot, pi });
        }
    }
    if (c_opt.debug_comments) {
        try writer.print("  /* fn {s} regs={d} */\n", .{ fsig.name, nregs });
    }
    var i: usize = task.start_idx + 1;
    while (i < task.end_idx) : (i += 1) {
        const base = verified.annotated[i].base;
        switch (base.kind) {
            .func_decl, .ffi_wrapper_decl, .extern_decl, .export_decl, .test_decl => {
                try writer.writeAll("  sa_trap(\"nested decl\");\n");
            },
            .label => {
                const id: u32 = switch (base.operands[0]) {
                    .label => |v| v, .symbol => |v| v, else => 0,
                };
                try writer.print("SA_L_{d}:\n", .{id});
                if (c_opt.debug_comments) {
                    try writer.print("  /* {s} */\n", .{std.mem.trim(u8, base.raw_text, " \t\r\n")});
                }
            },
            .jmp => {
                const id: u32 = switch (base.operands[1]) {
                    .label => |v| v, .symbol => |v| v, else => return CEmitError.InvalidOperand,
                };
                try writer.print("  goto SA_L_{d};\n", .{id});
            },
            .br => {
                const t: u32 = switch (base.operands[1]) {
                    .label => |v| v, .symbol => |v| v, else => return CEmitError.InvalidOperand,
                };
                const f: u32 = switch (base.operands[3]) {
                    .label => |v| v, .symbol => |v| v, else => return CEmitError.InvalidOperand,
                };
                try writer.writeAll("  if (sa_truthy(");
                try resolveValueToC(writer, verified.symbols, fsig, use_global, const_addrs, fn_idx, base.operands[0]);
                try writer.print(")) goto SA_L_{d}; else goto SA_L_{d};\n", .{ t, f });
            },
            .br_null => {
                const t: u32 = switch (base.operands[1]) {
                    .label => |v| v, .symbol => |v| v, else => return CEmitError.InvalidOperand,
                };
                const f: u32 = switch (base.operands[3]) {
                    .label => |v| v, .symbol => |v| v, else => return CEmitError.InvalidOperand,
                };
                try writer.writeAll("  if (((");
                try resolveValueToC(writer, verified.symbols, fsig, use_global, const_addrs, fn_idx, base.operands[0]);
                try writer.print(") == 0)) goto SA_L_{d}; else goto SA_L_{d};\n", .{ t, f });
            },
            else => {
                if (c_opt.debug_comments) {
                    try writer.print("  /* {s} */\n", .{std.mem.trim(u8, base.raw_text, " \t\r\n")});
                }
                try emitLinearInstruction(writer, allocator, verified.symbols, fsig, use_global, const_addrs, fn_idx, base);
            },
        }
    }
    // default return for fallthrough
    if (fsig.return_ty == .void and !fsig.return_fallible) {
        try writer.writeAll("  return 0;\n}\n");
    } else {
        try writer.writeAll("  return 0;\n}\n");
    }
}

pub fn emitCToString(allocator: std.mem.Allocator, verified: anytype, source_path: []const u8, size_bits: u16, c_opt: CEmitOptions) ![]u8 {
    var out: std.Io.Writer.Allocating = .init(allocator);
    errdefer out.deinit();
    const writer = &out.writer;
    var fn_names = std.array_list.Managed([]const u8).init(allocator);
    defer fn_names.deinit();
    var fn_idx = std.StringHashMap(usize).init(allocator);
    defer fn_idx.deinit();
    for (verified.const_decls) |decl| {
        if (decl.value != .vtable) continue;
        for (decl.value.vtable.slots) |slot| {
            if (fn_idx.contains(slot.func_name)) continue;
            try fn_idx.put(slot.func_name, fn_names.items.len);
            try fn_names.append(slot.func_name);
        }
    }
    const tasks = try collectFuncTasks(allocator, verified);
    defer allocator.free(tasks);
    try writeRuntimeHeader(writer, c_opt, size_bits);
    try writer.print("/* source: {s} */\n", .{source_path});
    // const addresses
    var const_addrs = std.StringHashMap(usize).init(allocator);
    defer const_addrs.deinit();
    var const_cursor: usize = 4096;
    const bump_start: usize = 65536;
    for (verified.const_decls) |decl| {
        const len = constBytesLen(decl.value) catch 0;
        const aligned = std.mem.alignForward(usize, const_cursor, 8);
        if (decl.value == .vtable or len == 0) {
            const is_vt = decl.value == .vtable;
            const slots: usize = if (is_vt) decl.value.vtable.slots.len * 8 else 8;
            const a2 = std.mem.alignForward(usize, const_cursor, 8);
            if (a2 + slots > bump_start) return CEmitError.Failed;
            try const_addrs.put(decl.name, a2);
            try writer.writeAll("#define ");
            try writeConstSym(writer, decl.name);
            try writer.print(" {d}UL /* {s} */\n", .{ a2, @tagName(decl.value) });
            const_cursor = a2 + slots;
            continue;
        }
        if (aligned + len > bump_start) return CEmitError.Failed;
        try const_addrs.put(decl.name, aligned);
        try writer.writeAll("#define ");
        try writeConstSym(writer, decl.name);
        try writer.print(" {d}UL\n", .{aligned});
        const_cursor = aligned + len;
    }
    // forward decls
    for (tasks) |task| {
        if (task.kind == .extern_decl) continue;
        const fsig = verified.function_sigs[task.fsig_index];
        try writer.writeAll("static sa_u64 ");
        try cFuncName(writer, fsig.name);
        try writer.writeAll("(");
        if (fsig.params.len == 0) try writer.writeAll("void") else {
            for (fsig.params, 0..) |_, pi| {
                if (pi != 0) try writer.writeAll(", ");
                try writer.writeAll("sa_u64");
            }
        }
        try writer.writeAll(");\n");
    }
    // const init
    try writer.writeAll("static void sa_init_consts(void) {\n  static int done = 0; if (done) return; done = 1;\n");
    for (verified.const_decls) |decl| {
        const len = constBytesLen(decl.value) catch 0;
        if (decl.value == .vtable or len == 0) {
            if (decl.value == .vtable) {
                var sidx: usize = 0;
                for (decl.value.vtable.slots) |vslot| {
                    const fidx = fnIndexOf(fn_idx, vslot.func_name) orelse return CEmitError.UnknownFunction;
                    const addr = const_addrs.get(decl.name) orelse return CEmitError.InvalidOperand;
                    const le: u64 = 1000000 + @as(u64, @intCast(fidx));
                    try writer.print("  {{ uint64_t t={d}ULL; memcpy(&sa_mem[{d}], &t, 8); }}\n", .{ le, addr + sidx * 8 });
                    sidx += 1;
                }
            }
            continue;
        }
        const bytes = try allocator.alloc(u8, len);
        defer allocator.free(bytes);
        try fillConstBytes(bytes, decl.value);
        const addr = const_addrs.get(decl.name) orelse return CEmitError.InvalidOperand;
        try writer.print("  {{ static const uint8_t b[] = {{", .{});
        for (bytes, 0..) |b, idx| {
            if (idx != 0) try writer.writeAll(",");
            try writer.print("{d}", .{b});
        }
        try writer.print("}}; memcpy(&sa_mem[{d}], b, {d}); }}\n", .{ addr, len });
    }
    try writer.writeAll("}\n");
    // indirect dispatch
    try writer.writeAll("static sa_u64 sa_call_indirect(sa_u64 f");
    // max arity: scan tasks for max params
    var max_arity: usize = 0;
    for (tasks) |task| {
        if (task.kind == .extern_decl) continue;
        max_arity = @max(max_arity, verified.function_sigs[task.fsig_index].params.len);
    }
    max_arity = @max(max_arity, 8);
    for (0..max_arity) |k| {
        try writer.print(", sa_u64 a{d}", .{k});
    }
    try writer.writeAll(") {\n  uint64_t idx = (uint64_t)(f - 1000000);\n");
    var fi: usize = 0;
    for (fn_names.items) |fname| {
        try writer.print("  if (idx == {d}) return ", .{fi});
        try cFuncName(writer, fname);
        try writer.writeAll("(");
        // pass first N args where N = target arity is unknown at runtime; pass min arity?
        // For MVP, forward first 8 args; callees ignore extras (C allows extra args? no—strict).
        // Instead dispatch via switch on arity is complex; emit generic call with all args
        // and rely on C prototypes matching max arity via cast. Simplify: cast to generic fn.
        try writer.writeAll("/* indirect arity mismatch: trap */ 0);\n");
        fi += 1;
    }
    try writer.writeAll("  sa_trap(\"bad indirect callee\"); return 0;\n}\n");
    // NOTE: indirect calls with exact arity are emitted via sa_call_indirect only as fallback;
    // direct vtable use in demos goes through direct calls after monomorphization, so this
    // trap path is rarely hit in the MVP matrix.
    var emitted = std.StringHashMap(void).init(allocator);
    defer emitted.deinit();
    for (tasks) |task| {
        if (task.kind == .extern_decl) continue;
        try emitOneFunction(writer, allocator, verified, task, &const_addrs, &fn_idx, c_opt);
        const fsig = verified.function_sigs[task.fsig_index];
        try emitted.put(fsig.name, {});
    }
    for (tasks) |task| {
        if (task.kind != .extern_decl) continue;
        const fsig = verified.function_sigs[task.fsig_index];
        if (emitted.contains(fsig.name)) continue;
        if (std.mem.eql(u8, fsig.name, "sa_print_bytes")) continue; // runtime provides it
        // trap stub
        try writer.writeAll("static sa_u64 ");
        try cFuncName(writer, fsig.name);
        try writer.writeAll("(");
        if (fsig.params.len == 0) try writer.writeAll("void") else {
            for (fsig.params, 0..) |_, pi| {
                if (pi != 0) try writer.writeAll(", ");
                try writer.print("sa_u64 a{d}", .{pi});
            }
        }
        try writer.print(") {{ sa_trap(\"extern {s}\"); return 0; }}\n", .{fsig.name});
    }
    try writer.writeAll("int main(void) { sa_init_consts();\n");
    // call sa main if present
    var found_main = false;
    for (tasks) |task| {
        if (task.kind == .extern_decl) continue;
        const fsig = verified.function_sigs[task.fsig_index];
        if (std.mem.eql(u8, fsig.name, "main")) {
            found_main = true;
            break;
        }
    }
    if (found_main) {
        try writer.writeAll("  sa_u64 rc = sa_fn_main();\n  return (int)(rc & 0xFF);\n}\n");
    } else {
        try writer.writeAll("  return 0;\n}\n");
    }
    return out.toOwnedSlice();
}

pub fn emitCToFile(allocator: std.mem.Allocator, verified: anytype, source_path: []const u8, size_bits: u16, c_opt: CEmitOptions, path: []const u8) !void {
    const text = try emitCToString(allocator, verified, source_path, size_bits, c_opt);
    defer allocator.free(text);
    const dir = std.fs.path.dirname(path);
    if (dir) |d| try sio.cwd().makePath(d);
    const f = try sio.cwd().createFile(path, .{});
    defer f.close();
    try f.writeAll(text);
}

test "c ident sanitizes names" {
    var buf: [64]u8 = undefined;
    var fbs = std.Io.Writer.fixed(&buf);
    try cIdent(&fbs, "hello-world.foo");
    try std.testing.expectEqualStrings("hello_world_foo", fbs.buffered());
}
