const std = @import("std");
const inst = @import("../common/instruction.zig");
const sig = @import("../common/signature.zig");
const const_decl = @import("../common/const_decl.zig");

/// JS reserved words (strict-mode ESM): suffixed with `$` when emitted.
pub fn isJsReserved(name: []const u8) bool {
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

/// Names the JS emitter reserves for itself: register locals `r<slot>`
/// and the `__sa*` / `__SA*` runtime namespace. A user ident mapping onto
/// those would be shadowed by function-scope locals (e.g. a function named
/// `r1` is hidden by `let r1` inside every caller) or clobber the runtime.
pub fn isEmitterReserved(name: []const u8) bool {
    if (std.mem.startsWith(u8, name, "__sa") or std.mem.startsWith(u8, name, "__SA")) return true;
    if (name.len < 2 or name[0] != 'r') return false;
    for (name[1..]) |c| {
        if (!std.ascii.isDigit(c)) return false;
    }
    return true;
}

pub fn jsIdent(writer: anytype, name: []const u8) !void {
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
    if (isEmitterReserved(name)) try writer.writeAll("$");
}

pub fn jsFuncName(writer: anytype, name: []const u8) !void {
    // Strip surrounding quotes used by test funcs.
    var n = name;
    if (n.len >= 2 and n[0] == '"' and n[n.len - 1] == '"') n = n[1 .. n.len - 1];
    // Strip @ prefix used by callee names.
    if (n.len >= 1 and n[0] == '@') n = n[1..];
    try jsIdent(writer, n);
}

pub fn tagToPrim(tag: u32) sig.PrimType {
    return sig.primTypeFromTag(tag) orelse .i64;
}

/// Byte-flatten any data const (hex/utf8/repeat/struct_). Mirrors
/// emit_llvm_llvmc.constBytesLen/fillConstBytes so JS sees identical bytes.
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

/// Write text escaped for interpolation into a double-quoted JS string
/// literal (prevents raw SA text containing `"` or `\` from breaking
/// the generated module).
pub fn writeJsStrEscaped(writer: anytype, text: []const u8) !void {
    for (text) |c| {
        switch (c) {
            '\\' => try writer.writeAll("\\\\"),
            '"' => try writer.writeAll("\\\""),
            '\n' => try writer.writeAll("\\n"),
            '\r' => try writer.writeAll("\\r"),
            '\t' => try writer.writeAll("\\t"),
            else => try writer.writeByte(c),
        }
    }
}

/// JS identifier for a const's address slot: `C_<sanitized>`.
pub fn writeConstSlot(writer: anytype, name: []const u8) !void {
    try writer.writeAll("C_");
    try jsIdent(writer, name);
}

pub fn loadedPrimType(base: inst.Instruction) sig.PrimType {
    if (base.operands[3] == .ty) return tagToPrim(base.operands[3].ty);
    return .i64;
}

/// Element type for load/store/atomic memory ops. Atomics carry their type
/// in `atomic_value_ty` (mirrors emit_llvm_llvmc.atomicValueType).
pub fn memPrimType(base: inst.Instruction) sig.PrimType {
    if (base.kind == .atomic_load or base.kind == .atomic_store or base.kind == .atomic_rmw) {
        if (base.atomic_value_ty) |tag| return tagToPrim(tag);
        return .i64;
    }
    return loadedPrimType(base);
}

/// DataView helper per element type (exact width reads/writes).
pub fn memLoadFn(ty: sig.PrimType) []const u8 {
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

pub fn memStoreFn(ty: sig.PrimType) []const u8 {
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

pub fn opIsFloat(kind: inst.OpKind) bool {
    return switch (kind) {
        .fadd, .fsub, .fmul, .fdiv, .fneg, .fcmp_eq, .fcmp_ne, .fcmp_lt, .fcmp_le, .fcmp_gt, .fcmp_ge => true,
        else => false,
    };
}
