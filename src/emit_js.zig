const std = @import("std");

const emit_options = @import("emit_options.zig");
const inst = @import("common/instruction.zig");
const sig = @import("common/signature.zig");
const call = @import("referee/call.zig");
const const_decl = @import("common/const_decl.zig");

pub const EmitOptions = emit_options.EmitOptions;
pub const JsEmitError = error{ Failed, InvalidOperand, UnknownFunction, UnsupportedInstruction, UnsupportedNpmBinding, OutOfMemory };

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

/// Write text escaped for interpolation into a double-quoted JS string
/// literal (prevents raw SA text containing `"` or `\` from breaking
/// the generated module).
fn writeJsStrEscaped(writer: anytype, text: []const u8) !void {
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
    if (base.kind == .atomic_load or base.kind == .atomic_store or base.kind == .atomic_rmw) {
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

/// One `#npm_bind` import edge: ESM specifier + export name + the local
/// alias emitted into the module prologue. MVP marshaling covers numbers
/// plus adjacent (ptr, integer-length) UTF8 pairs; anything else (binary
/// blobs, JS objects, string returns) is rejected with
/// UnsupportedNpmBinding so mis-marshals trap at build time instead of
/// corrupting linear memory at runtime.
///
/// Binding shapes (`#npm_bind <extern> "<spec>#<export>"`):
/// - `"spec#name"`       named import: `import { name as alias }`.
/// - `"spec#ns.member"`  namespace import: `import * as alias_ns`
///   and calls lower to `alias_ns.member(...)`. Exactly one dot level;
///   deeper paths are rejected (bind a narrower export instead).
const NpmImport = struct {
    spec: []const u8,
    export_name: []const u8,
    member: ?[]const u8,
    alias: []const u8,
    extern_name: []const u8,
};

fn collectNpmImports(
    allocator: std.mem.Allocator,
    verified: anytype,
    tasks: []const FuncTask,
    npm_binds: *const std.StringHashMap([]const u8),
) ![]NpmImport {
    var out = std.ArrayList(NpmImport).init(allocator);
    errdefer out.deinit();
    for (tasks) |task| {
        if (task.kind != .extern_decl) continue;
        const fsig = verified.function_sigs[task.fsig_index];
        const binding = npm_binds.get(fsig.name) orelse continue;
        const hash = std.mem.lastIndexOfScalar(u8, binding, '#') orelse return JsEmitError.UnsupportedNpmBinding;
        if (hash == 0 or hash + 1 >= binding.len) return JsEmitError.UnsupportedNpmBinding;
        const spec = binding[0..hash];
        const export_name = binding[hash + 1 ..];
        // Namespace form `"spec#ns.member"`: split one dot level; both
        // sides must be plain JS identifiers (deeper paths rejected).
        var member: ?[]const u8 = null;
        var export_id = export_name;
        if (std.mem.indexOfScalar(u8, export_name, '.')) |dot| {
            if (dot == 0 or dot + 1 >= export_name.len) return JsEmitError.UnsupportedNpmBinding;
            if (std.mem.indexOfScalarPos(u8, export_name, dot + 1, '.') != null) return JsEmitError.UnsupportedNpmBinding;
            const ns = export_name[0..dot];
            member = export_name[dot + 1 ..];
            if (!isNpmExportIdent(ns) or !isNpmExportIdent(member.?)) return JsEmitError.UnsupportedNpmBinding;
            export_id = ns;
        } else if (!isNpmExportIdent(export_name)) {
            return JsEmitError.UnsupportedNpmBinding;
        }
        var exists = false;
        for (out.items) |item| {
            if (std.mem.eql(u8, item.extern_name, fsig.name)) {
                exists = true;
                break;
            }
        }
        if (exists) continue;
        const alias = if (member == null)
            try std.fmt.allocPrint(allocator, "sa_npm_{d}", .{out.items.len})
        else
            try std.fmt.allocPrint(allocator, "sa_npm_ns_{d}", .{out.items.len});
        try out.append(.{
            .spec = spec,
            .export_name = export_id,
            .member = member,
            .alias = alias,
            .extern_name = fsig.name,
        });
    }
    return out.toOwnedSlice();
}

fn npmImportFor(imports: []const NpmImport, extern_name: []const u8) ?NpmImport {
    for (imports) |item| {
        if (std.mem.eql(u8, item.extern_name, extern_name)) return item;
    }
    return null;
}

/// Export names land verbatim in the ESM prologue, so they must be plain
/// JS identifiers (rejects quotes/dots/slashes that would break out of
/// the import statement).
fn isNpmExportIdent(name: []const u8) bool {
    if (name.len == 0) return false;
    if (!std.ascii.isAlphabetic(name[0]) and name[0] != '_' and name[0] != '$') return false;
    for (name[1..]) |c| {
        if (!std.ascii.isAlphanumeric(c) and c != '_' and c != '$') return false;
    }
    return true;
}

fn isNpmIntType(ty: sig.PrimType) bool {
    return switch (ty) {
        .i8, .i16, .i32, .i64, .u8, .u16, .u32, .u64 => true,
        else => false,
    };
}

fn isNpmNumericType(ty: sig.PrimType) bool {
    return switch (ty) {
        .i1, .i8, .i16, .i32, .i64, .u8, .u16, .u32, .u64, .f32, .f64 => true,
        else => false,
    };
}

/// Emits the JS wrapper for one npm-bound extern: numeric params via
/// `__sa_num`, adjacent (ptr, integer-length) params as one UTF8 string,
/// lone ptr params as raw addresses. String/binary/object results are
/// rejected at build time (MVP boundary, see NpmImport).
fn emitNpmWrapper(
    writer: anytype,
    fsig: sig.FunctionSig,
    npm_item: NpmImport,
    js_opt: JsEmitOptions,
) !void {
    if (fsig.return_ty == .void or fsig.return_ty == .blob_handle or fsig.return_ty == .v128) {
        return JsEmitError.UnsupportedNpmBinding;
    }
    if (!isNpmNumericType(fsig.return_ty) and fsig.return_ty != .ptr) {
        return JsEmitError.UnsupportedNpmBinding;
    }
    if (js_opt.format == .esm) try writer.writeAll("export function ") else try writer.writeAll("function ");
    try jsFuncName(writer, fsig.name);
    try writer.writeAll("(");
    for (fsig.params, 0..) |p, idx| {
        if (idx != 0) try writer.writeAll(", ");
        try jsIdent(writer, p.name);
    }
    try writer.writeAll(") {\n");
    var idx: usize = 0;
    try writer.writeAll("  const __sa_npm_args = [];\n");
    while (idx < fsig.params.len) : (idx += 1) {
        const p = fsig.params[idx];
        if (p.ty == .ptr and idx + 1 < fsig.params.len and isNpmIntType(fsig.params[idx + 1].ty)) {
            const len_p = fsig.params[idx + 1];
            try writer.writeAll("  __sa_npm_args.push(new globalThis.TextDecoder().decode(__sa_u8.slice(");
            try writer.writeAll("__sa_addr(");
            try jsIdent(writer, p.name);
            try writer.writeAll("), __sa_addr(");
            try jsIdent(writer, p.name);
            try writer.writeAll(") + __sa_num(");
            try jsIdent(writer, len_p.name);
            try writer.writeAll("))));\n");
            idx += 1;
            continue;
        }
        if (p.ty == .ptr) {
            try writer.writeAll("  __sa_npm_args.push(__sa_addr(");
            try jsIdent(writer, p.name);
            try writer.writeAll("));\n");
        } else if (isNpmNumericType(p.ty)) {
            try writer.writeAll("  __sa_npm_args.push(__sa_num(");
            try jsIdent(writer, p.name);
            try writer.writeAll("));\n");
        } else {
            return JsEmitError.UnsupportedNpmBinding;
        }
    }
    try writer.writeAll("  const __sa_npm_r = ");
    try writer.writeAll(npm_item.alias);
    if (npm_item.member) |member| {
        try writer.writeAll(".");
        try writer.writeAll(member);
    }
    try writer.writeAll("(...__sa_npm_args);\n");
    try writer.writeAll("  if (typeof __sa_npm_r !== \"number\" && typeof __sa_npm_r !== \"bigint\" && typeof __sa_npm_r !== \"boolean\") __sa_trap(\"npm extern returned non-numeric: ");
    try jsFuncName(writer, fsig.name);
    try writer.writeAll("\");\n");
    try writer.writeAll("  return __sa_num(__sa_npm_r);\n}\n");
}

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

fn writeRuntimeHeader(writer: anytype, js_opt: JsEmitOptions, size_bits: u16, npm_imports: []const NpmImport) !void {
    const mem_bytes: usize = @as(usize, js_opt.mem_pages) * 65536;
    try writer.print("// Generated by `sa build-js` (js backend, MVP). DO NOT EDIT.\n", .{});
    try writer.print("// size_bits={d} pages={d} ({d} bytes linear memory)\n", .{ size_bits, js_opt.mem_pages, mem_bytes });
    // Third-party/host ESM imports for `#npm_bind` externs (JS target only).
    // Grouped by specifier; one alias per bound export. Bare npm specifiers
    // resolve through the runner's node_modules; `node:` builtins need none.
    // Namespace bindings (`"spec#ns.member"`) get their own
    // `import * as` statement each.
    if (npm_imports.len != 0) {
        if (js_opt.format == .esm) {
            // Named imports, one statement per specifier.
            for (npm_imports, 0..) |item, idx| {
                if (item.member != null) continue;
                var done = false;
                for (npm_imports[0..idx]) |prev| {
                    if (prev.member == null and std.mem.eql(u8, prev.spec, item.spec)) {
                        done = true;
                        break;
                    }
                }
                if (done) continue;
                try writer.writeAll("import { ");
                var first = true;
                for (npm_imports) |other| {
                    if (other.member != null or !std.mem.eql(u8, other.spec, item.spec)) continue;
                    if (!first) try writer.writeAll(", ");
                    first = false;
                    try writer.writeAll(other.export_name);
                    try writer.writeAll(" as ");
                    try writer.writeAll(other.alias);
                }
                try writer.print(" }} from \"{s}\";\n", .{item.spec});
            }
            // Namespace imports, one statement each.
            for (npm_imports) |item| {
                if (item.member == null) continue;
                try writer.print("import * as {s} from \"{s}\";\n", .{ item.alias, item.spec });
            }
        } else {
            for (npm_imports) |item| {
                if (item.member != null) continue;
                try writer.print("const {{ {s}: {s} }} = require(\"{s}\");\n", .{ item.export_name, item.alias, item.spec });
            }
            for (npm_imports) |item| {
                if (item.member == null) continue;
                try writer.print("const {s} = require(\"{s}\");\n", .{ item.alias, item.spec });
            }
        }
    }
    try writer.writeAll(
        \\// ---- SA JS runtime (MVP, JEV: ArrayBuffer linear memory) ----
        \\const __SA_MEM_BYTES = __SA_MEM_BYTES_DECL__;
        \\const __sa_memory = new ArrayBuffer(__SA_MEM_BYTES);
        \\const __sa_view = new DataView(__sa_memory);
        \\const __sa_u8 = new Uint8Array(__sa_memory);
        \\let __sa_brk = 65536; // bump allocator starts after reserved zero page region
        \\const __sa_live = new Set(); // live heap bases (user pointers handed out by __sa_alloc)
        \\const __sa_fl = Object.create(null); // free-list buckets: aligned size -> stack of user pointers
        \\function __sa_trap(msg) { throw new Error("[sa-trap] " + msg); }
        \\function __sa_panic(code) { throw new Error("[sa-panic] code=" + code); }
        \\function __sa_truthy(v) { return !!v; }
        \\const __SA_FN_BASE = 0x5341000000000000n;
        \\function __sa_fnptr(i) { return __SA_FN_BASE + BigInt(i); }
        \\function __sa_fnval(v) { const d = BigInt(v) - __SA_FN_BASE; return (d >= 0n && d < BigInt(__sa_ftable.length)) ? Number(d) : -1; }
        \\function __sa_call_indirect(f, ...args) { const i = __sa_fnval(f); if (i < 0) __sa_trap("bad indirect callee"); return __sa_ftable[i](...args); }
        \\function __sa_fok(t) { return ((t && typeof t === "object" && ("s" in t)) ? ((t.s | 0) === 0) : true); }
        \\function __sa_fv(t) { return ((t && typeof t === "object" && ("v" in t)) ? t.v : t); }
        \\function __sa_num(v) { return (typeof v === "bigint") ? Number(v) : (+v); }
        \\function __sa_addr(a) { return (typeof a === "bigint") ? Number(BigInt.asUintN(32, a)) : (a | 0); }
        \\function __sa_align(n, a) { return (n + (a - 1)) & ~(a - 1); }
        \\function __sa_alloc(size) {
        \\  size = __sa_align((__sa_num(size) | 0), 8);
        \\  const bucket = __sa_fl[size];
        \\  if (bucket && bucket.length) { const ptr = bucket.pop(); __sa_u8.fill(0, ptr, ptr + size); __sa_live.add(ptr | 0); return ptr | 0; }
        \\  const total = (size + 8); // 8-byte header holds the aligned user size
        \\  const base = __sa_brk;
        \\  __sa_brk += total;
        \\  if (__sa_brk >= __sa_memory.byteLength) __sa_trap("out of memory (bump)");
        \\  __sa_u8.fill(0, base, base + total);
        \\  __sa_view.setUint32(base, size, true);
        \\  const ptr = (base + 8);
        \\  __sa_live.add(ptr | 0);
        \\  return ptr | 0;
        \\}
        \\function __sa_free(ptr) {
        \\  // Mirrors the interpreter: only exact live heap bases are recycled.
        \\  // BigInt pointers are normalized to 32-bit addresses first so
        \\  // 64-bit-typed bases stay freeable; interior pointers, consts and
        \\  // unknown addresses remain no-ops (never present in __sa_live).
        \\  const p = __sa_addr(ptr);
        \\  if (!__sa_live.has(p)) return 0;
        \\  __sa_live.delete(p);
        \\  const size = __sa_view.getUint32((p - 8), true);
        \\  (__sa_fl[size] || (__sa_fl[size] = [])).push(p);
        \\  return 0;
        \\}
        \\const __sa_fstack = []; // call-stack of frames; each frame lists its stack slots
        \\function __sa_salloc(size) {
        \\  // Function-scoped allocation: freed when the owning frame returns
        \\  // (mirrors stack-slot lifetime; the interpreter never frees these
        \\  // mid-frame either). Returned to the free list on frame pop.
        \\  const ptr = __sa_alloc(size);
        \\  if (__sa_fstack.length) __sa_fstack[__sa_fstack.length - 1].push(ptr | 0);
        \\  return ptr;
        \\}
        \\function __sa_load_i8(addr) { return __sa_view.getInt8(__sa_addr(addr)); }
        \\function __sa_load_u8(addr) { return __sa_view.getUint8(__sa_addr(addr)); }
        \\function __sa_load_i16(addr) { return __sa_view.getInt16(__sa_addr(addr), true); }
        \\function __sa_load_u16(addr) { return __sa_view.getUint16(__sa_addr(addr), true); }
        \\function __sa_load_i32(addr) { return __sa_view.getInt32(__sa_addr(addr), true); }
        \\function __sa_load_u32(addr) { return __sa_view.getUint32(__sa_addr(addr), true); }
        \\function __sa_load_f32(addr) { return __sa_view.getFloat32(__sa_addr(addr), true); }
        \\function __sa_load_f64(addr) { return __sa_view.getFloat64(__sa_addr(addr), true); }
        \\function __sa_store_i8(addr, v) { __sa_view.setInt8(__sa_addr(addr), __sa_narrow(v, 8, true)); }
        \\function __sa_store_u8(addr, v) { __sa_view.setUint8(__sa_addr(addr), __sa_narrow(v, 8, false)); }
        \\function __sa_store_i16(addr, v) { __sa_view.setInt16(__sa_addr(addr), __sa_narrow(v, 16, true), true); }
        \\function __sa_store_u16(addr, v) { __sa_view.setUint16(__sa_addr(addr), __sa_narrow(v, 16, false), true); }
        \\function __sa_store_i32(addr, v) { __sa_view.setInt32(__sa_addr(addr), __sa_narrow(v, 32, true), true); }
        \\function __sa_store_u32(addr, v) { __sa_view.setUint32(__sa_addr(addr), __sa_narrow(v, 32, false), true); }
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
        \\function __sa_sdiv(a, b) { if (__sa_isBI(a, b)) { const nb = (typeof b === "bigint") ? b : BigInt(b | 0); if (nb === 0n) __sa_trap("div by zero"); const na = (typeof a === "bigint") ? a : BigInt(a | 0); return __sa_BI(na / nb); } const nb32 = (b | 0); if (nb32 === 0) __sa_trap("div by zero"); return (Math.trunc((a | 0) / nb32) | 0); }
        \\function __sa_udiv(a, b) { if (__sa_isBI(a, b)) { const x = (typeof a === "bigint") ? __sa_BU(a) : BigInt(a >>> 0); const y = (typeof b === "bigint") ? __sa_BU(b) : BigInt(b >>> 0); if (y === 0n) __sa_trap("div by zero"); return x / y; } const y32 = (b >>> 0); if (y32 === 0) __sa_trap("div by zero"); return Math.trunc((a >>> 0) / y32); }
        \\function __sa_srem(a, b) { if (__sa_isBI(a, b)) { const nb = (typeof b === "bigint") ? b : BigInt(b | 0); if (nb === 0n) __sa_trap("rem by zero"); const na = (typeof a === "bigint") ? a : BigInt(a | 0); return __sa_BI(na % nb); } const nb32 = (b | 0); if (nb32 === 0) __sa_trap("rem by zero"); return (((a | 0) % nb32) | 0); }
        \\function __sa_urem(a, b) { if (__sa_isBI(a, b)) { const x = (typeof a === "bigint") ? __sa_BU(a) : BigInt(a >>> 0); const y = (typeof b === "bigint") ? __sa_BU(b) : BigInt(b >>> 0); if (y === 0n) __sa_trap("rem by zero"); return x % y; } const y32 = (b >>> 0); if (y32 === 0) __sa_trap("rem by zero"); return ((a >>> 0) % y32); }
        \\function __sa_neg(a) { return (typeof a === "bigint") ? __sa_BI(-a) : ((-a) | 0); }
        \\function __sa_band(a, b) { return __sa_isBI(a, b) ? __sa_BI(BigInt(a) & BigInt(b)) : ((a & b) | 0); }
        \\function __sa_bor(a, b) { return __sa_isBI(a, b) ? __sa_BI(BigInt(a) | BigInt(b)) : ((a | b) | 0); }
        \\function __sa_bxor(a, b) { return __sa_isBI(a, b) ? __sa_BI(BigInt(a) ^ BigInt(b)) : ((a ^ b) | 0); }
        \\function __sa_shl(a, b) { return __sa_isBI(a, b) ? __sa_BI(BigInt(a) << (BigInt(b) & 63n)) : ((a << (b & 31)) | 0); }
        \\function __sa_lshr(a, b) { if (typeof a === "bigint") return __sa_BU(a) >> (BigInt(b) & 63n); return (a >>> (typeof b === "bigint" ? Number(BigInt(b) & 63n) & 31 : (b & 31))); }
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
        \\function __sa_narrow(v, bits, signed) {
        \\  // Narrow any int-domain value to a target width, returned as Number.
        \\  // BigInt inputs are 64-bit sources; Number inputs are 32-bit (or
        \\  // smaller) sources. Matches interpreter wrap-around for
        \\  // trunc/zext/sext/bitcast to widths <= 32.
        \\  if (typeof v === "bigint") return signed ? Number(BigInt.asIntN(bits, v)) : Number(BigInt.asUintN(bits, v));
        \\  if (bits === 32) return signed ? (v | 0) : (v >>> 0);
        \\  if (bits === 1) return (v & 1);
        \\  const m = Math.pow(2, bits);
        \\  let r = Math.trunc(+v) % m;
        \\  if (r < 0) r += m;
        \\  if (signed && r >= m / 2) r -= m;
        \\  return r;
        \\}
        \\function __sa_wide(v, signed) {
        \\  // Widen any int-domain value to 64 bits, returned as BigInt.
        \\  // BigInt inputs are 64-bit sources (modular); Number inputs are
        \\  // 32-bit sources read with signed/unsigned 32-bit semantics.
        \\  if (typeof v === "bigint") return signed ? BigInt.asIntN(64, v) : BigInt.asUintN(64, v);
        \\  if (!Number.isFinite(+v)) return 0n;
        \\  return signed ? BigInt((+v) | 0) : BigInt((+v) >>> 0);
        \\}
        \\function __sa_cvt_trunc_i8(v) { return __sa_narrow(v, 8, true); }
        \\function __sa_cvt_trunc_i16(v) { return __sa_narrow(v, 16, true); }
        \\function __sa_cvt_trunc_i1(v) { return __sa_narrow(v, 1, false); }
        \\function __sa_cvt_trunc_i32(v) { return __sa_narrow(v, 32, true); }
        \\function __sa_cvt_trunc_u8(v) { return __sa_narrow(v, 8, false); }
        \\function __sa_cvt_trunc_u16(v) { return __sa_narrow(v, 16, false); }
        \\function __sa_cvt_trunc_u32(v) { return __sa_narrow(v, 32, false); }
        \\function __sa_cvt_trunc_i64(v) { return __sa_wide(v, true); }
        \\function __sa_cvt_trunc_u64(v) { return __sa_wide(v, false); }
        \\function __sa_cvt_trunc_ptr(v) { return __sa_cvt_ptr64(v); }
        \\function __sa_cvt_zext_i8(v) { return __sa_narrow(v, 8, false); }
        \\function __sa_cvt_zext_i16(v) { return __sa_narrow(v, 16, false); }
        \\function __sa_cvt_zext_i1(v) { return __sa_narrow(v, 1, false); }
        \\function __sa_cvt_zext_i32(v) { return __sa_narrow(v, 32, false); }
        \\function __sa_cvt_zext_u8(v) { return __sa_narrow(v, 8, false); }
        \\function __sa_cvt_zext_u16(v) { return __sa_narrow(v, 16, false); }
        \\function __sa_cvt_zext_u32(v) { return __sa_narrow(v, 32, false); }
        \\function __sa_cvt_zext_i64(v) { return (typeof v === "bigint") ? BigInt.asIntN(64, v) : BigInt((+v) >>> 0); }
        \\function __sa_cvt_zext_u64(v) { return (typeof v === "bigint") ? BigInt.asUintN(64, v) : BigInt((+v) >>> 0); }
        \\function __sa_cvt_zext_ptr(v) { return __sa_cvt_ptr64(v); }
        \\function __sa_cvt_sext_i8(v) { return __sa_narrow(v, 8, true); }
        \\function __sa_cvt_sext_i16(v) { return __sa_narrow(v, 16, true); }
        \\function __sa_cvt_sext_i1(v) { return __sa_narrow(v, 1, false); }
        \\function __sa_cvt_sext_i32(v) { return __sa_narrow(v, 32, true); }
        \\function __sa_cvt_sext_u8(v) { return __sa_narrow(v, 8, true); }
        \\function __sa_cvt_sext_u16(v) { return __sa_narrow(v, 16, true); }
        \\function __sa_cvt_sext_u32(v) { return __sa_narrow(v, 32, true); }
        \\function __sa_cvt_sext_i64(v) { return (typeof v === "bigint") ? BigInt.asIntN(64, v) : BigInt((+v) | 0); }
        \\function __sa_cvt_sext_u64(v) { return (typeof v === "bigint") ? BigInt.asUintN(64, v) : BigInt.asUintN(64, BigInt((+v) | 0)); }
        \\function __sa_cvt_sext_ptr(v) { return __sa_cvt_ptr64(v); }
        \\function __sa_cvt_sitofp_f64(v) { return (typeof v === "bigint") ? Number(v) : (+v); }
        \\function __sa_cvt_sitofp_f32(v) { return Math.fround((typeof v === "bigint") ? Number(v) : (+v)); }
        \\function __sa_cvt_uitofp_f64(v) { return (typeof v === "bigint") ? Number(v) : (+v); }
        \\function __sa_cvt_uitofp_f32(v) { return Math.fround((typeof v === "bigint") ? Number(v) : (+v)); }
        \\function __sa_cvt_fptosi_i64(v) {
        \\  // Truncate toward zero like LLVM fptosi; out-of-range/NaN/Inf
        \\  // maps to INT64_MIN (x86 cvttsd2si behavior) instead of throwing.
        \\  const t = Math.trunc(+v);
        \\  if (!Number.isFinite(t) || t >= 9223372036854775808 || t < -9223372036854775808) return -9223372036854775808n;
        \\  return BigInt(t);
        \\}
        \\function __sa_cvt_fptosi_u64(v) { return BigInt.asUintN(64, __sa_cvt_fptosi_i64(v)); }
        \\function __sa_cvt_fptosi_i32(v) { return Number(BigInt.asIntN(32, __sa_cvt_fptosi_i64(v))); }
        \\function __sa_cvt_fptosi_u32(v) { return Number(BigInt.asUintN(32, __sa_cvt_fptosi_i64(v))); }
        \\function __sa_cvt_fptosi_i16(v) { return Number(BigInt.asIntN(16, __sa_cvt_fptosi_i64(v))); }
        \\function __sa_cvt_fptosi_u16(v) { return Number(BigInt.asUintN(16, __sa_cvt_fptosi_i64(v))); }
        \\function __sa_cvt_fptosi_i8(v) { return Number(BigInt.asIntN(8, __sa_cvt_fptosi_i64(v))); }
        \\function __sa_cvt_fptosi_u8(v) { return Number(BigInt.asUintN(8, __sa_cvt_fptosi_i64(v))); }
        \\function __sa_cvt_fptosi_i1(v) { return Number(BigInt.asUintN(1, __sa_cvt_fptosi_i64(v))); }
        \\function __sa_cvt_fptosi_ptr(v) { return __sa_addr(__sa_cvt_fptosi_i64(v)); }
        \\function __sa_cvt_fptrunc_f32(v) { return Math.fround(+v); }
        \\function __sa_cvt_fpext_f64(v) { return (+v); }
        \\const __sa_bc_dv = new DataView(new ArrayBuffer(8));
        \\function __sa_cvt_bitcast_i8(v) { return (typeof v === "bigint") ? Number(BigInt.asIntN(8, v)) : ((v << 24) >> 24); }
        \\function __sa_cvt_bitcast_u8(v) { return (typeof v === "bigint") ? Number(BigInt.asUintN(8, v)) : (v & 0xFF); }
        \\function __sa_cvt_bitcast_i16(v) { return (typeof v === "bigint") ? Number(BigInt.asIntN(16, v)) : ((v << 16) >> 16); }
        \\function __sa_cvt_bitcast_u16(v) { return (typeof v === "bigint") ? Number(BigInt.asUintN(16, v)) : (v & 0xFFFF); }
        \\function __sa_cvt_bitcast_i1(v) { return (typeof v === "bigint") ? Number(BigInt.asUintN(1, v)) : (v & 1); }
        \\function __sa_cvt_bitcast_i32(v) {
        \\  // Non-integer Numbers are f32-domain values (f64 sources are
        \\  // rejected by the verifier for 32-bit bitcasts); reinterpret them.
        \\  if (typeof v === "bigint") return Number(BigInt.asIntN(32, v));
        \\  if (!Number.isInteger(v)) { __sa_bc_dv.setFloat32(0, v, true); return __sa_bc_dv.getInt32(0, true); }
        \\  return (v | 0);
        \\}
        \\function __sa_cvt_bitcast_u32(v) {
        \\  if (typeof v === "bigint") return Number(BigInt.asUintN(32, v));
        \\  if (!Number.isInteger(v)) { __sa_bc_dv.setFloat32(0, v, true); return __sa_bc_dv.getUint32(0, true); }
        \\  return (v >>> 0);
        \\}
        \\function __sa_cvt_bitcast_i64(v) {
        \\  // Non-integer Numbers are f64-domain values; reinterpret them.
        \\  // Integer Numbers are immediates (f64-integral bitcasts are a
        \\  // known edge; use sitofp-produced values only via fptosi).
        \\  if (typeof v === "bigint") return BigInt.asIntN(64, v);
        \\  if (!Number.isInteger(v)) { __sa_bc_dv.setFloat64(0, v, true); return __sa_bc_dv.getBigInt64(0, true); }
        \\  return BigInt(v);
        \\}
        \\function __sa_cvt_bitcast_u64(v) {
        \\  if (typeof v === "bigint") return BigInt.asUintN(64, v);
        \\  if (!Number.isInteger(v)) { __sa_bc_dv.setFloat64(0, v, true); return BigInt.asUintN(64, __sa_bc_dv.getBigInt64(0, true)); }
        \\  return BigInt(v);
        \\}
        \\function __sa_cvt_bitcast_ptr(v) {
        \\  // Pointers carry full 64-bit patterns in every backend (only
        \\  // real heap bases are 32-bit); narrowing here would break
        \\  // bitcast roundtrips of high-bit patterns.
        \\  if (typeof v === "bigint") return BigInt.asUintN(64, v);
        \\  return v;
        \\}
        \\function __sa_cvt_ptr64(v) {
        \\  // 64-bit-preserving pointer conversion (trunc/zext/sext to ptr):
        \\  // same as bitcast_ptr, factored for the int-conversion family.
        \\  if (typeof v === "bigint") return BigInt.asUintN(64, v);
        \\  return v;
        \\}
        \\function __sa_cvt_bitcast_f32(v) {
        \\  // BigInt/integer inputs are int-domain bits; fractional inputs are
        \\  // already f32-domain values (f32-to-f32 is identity).
        \\  if (typeof v === "bigint") { __sa_bc_dv.setUint32(0, Number(BigInt.asUintN(32, v)), true); return __sa_bc_dv.getFloat32(0, true); }
        \\  if (!Number.isInteger(v)) return (+v);
        \\  __sa_bc_dv.setInt32(0, v | 0, true); return __sa_bc_dv.getFloat32(0, true);
        \\}
        \\function __sa_cvt_bitcast_f64(v) {
        \\  // Number inputs are always f64-domain here (equal-bits rule keeps
        \\  // int-domain f64 bitcasts on the BigInt path).
        \\  if (typeof v === "bigint") { __sa_bc_dv.setBigInt64(0, BigInt.asIntN(64, v), true); return __sa_bc_dv.getFloat64(0, true); }
        \\  return (+v);
        \\}
        \\function __sa_srcmask(v, w, signed) {
        \\  // Restrict a value to a known source width (statically tracked by
        \\  // the emitter for load-defined slots) before zext/sext, so
        \\  // sub-32-bit sources (e.g. i8 0xFF) extend from the right bits
        \\  // instead of the 32-bit value-inference default.
        \\  if (typeof v === "bigint") return signed ? BigInt.asIntN(w, v) : BigInt.asUintN(w, v);
        \\  if (w >= 64) return v;
        \\  if (w === 32) return signed ? (v | 0) : (v >>> 0);
        \\  if (w === 1) return (v & 1);
        \\  const s = 32 - w;
        \\  return signed ? ((v << s) >> s) : (((v << s) >>> s));
        \\}
        \\function __sa_cvt_bitcast_f64i(v) {
        \\  // int-domain source with a 64-bit target: reinterpret the bits.
        \\  // Used when the emitter statically knows the source is integral
        \\  // (plain bitcast_f64 treats Numbers as f64-domain values).
        \\  const b = (typeof v === "bigint") ? BigInt.asIntN(64, v) : BigInt(Math.trunc(+v));
        \\  __sa_bc_dv.setBigInt64(0, b, true); return __sa_bc_dv.getFloat64(0, true);
        \\}
        \\function __sa_cvt_bitcast_i32f(v) {
        \\  // float-domain f32 source reinterpreted as i32 (emitter-known).
        \\  __sa_bc_dv.setFloat32(0, +v, true); return __sa_bc_dv.getInt32(0, true);
        \\}
        \\function __sa_cvt_bitcast_u32f(v) {
        \\  __sa_bc_dv.setFloat32(0, +v, true); return __sa_bc_dv.getUint32(0, true);
        \\}
        \\function __sa_cvt_bitcast_i64b(v) {
        \\  // float-domain f64 source reinterpreted as i64 (emitter-known).
        \\  __sa_bc_dv.setFloat64(0, +v, true); return __sa_bc_dv.getBigInt64(0, true);
        \\}
        \\function __sa_cvt_bitcast_u64b(v) {
        \\  __sa_bc_dv.setFloat64(0, +v, true); return BigInt.asUintN(64, __sa_bc_dv.getBigInt64(0, true));
        \\}
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
    // u64-range literals that overflow i64 still materialize exactly as
    // BigInt (plain float formatting would lose precision above 2^53).
    if (std.fmt.parseInt(u64, text, 10)) |v| {
        try writer.print("{d}n", .{v});
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

/// Look up a function name in the indirect-call table, tolerating the
/// `@` prefix variance between symbol names and vtable slot spellings.
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

/// Resolve any value operand to a JS expression.
fn resolveValueToJs(writer: anytype, symbols: anytype, fsig: sig.FunctionSig, use_global: bool, const_addrs: anytype, fn_idx: anytype, op: inst.Operand) !void {
    switch (op) {
        .reg => |r| {
            const slot = try regSlot(fsig, use_global, r);
            try writer.print("r{d}", .{slot});
        },
        .symbol, .label => |id| {
            // Mirror assignOperand: resolve id -> name -> text operand.
            const name = symbols.lookupName(id) orelse return JsEmitError.InvalidOperand;
            try resolveTextToJs(writer, symbols, fsig, const_addrs, name);
        },
        .func => |id| {
            // Function addresses box into the indirect-call table.
            const name = symbols.lookupName(id) orelse return JsEmitError.InvalidOperand;
            const fidx = fnIndexOf(fn_idx, name) orelse return JsEmitError.InvalidOperand;
            try writer.print("__sa_fnptr({d})", .{fidx});
        },
        .imm_int => |v| try writer.print("{d}", .{v}),
        // 64-bit immediates materialize as BigInt literals so the runtime
        // typeof-dispatch (number = 32-bit/float, bigint = 64-bit) stays
        // exact across the full u64 range. Plain digits would silently lose
        // precision above 2^53 and wrap 64-bit arithmetic at 32 bits.
        .imm_i64 => |v| try writer.print("{d}n", .{v}),
        .imm_u64 => |v| try writer.print("{d}n", .{v}),
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

/// Runtime helper suffix for a conversion target type. blob_handle shares
/// the u64 helpers (both are 64-bit); v128/void targets are rejected loudly
/// (the verifier never produces them, so reaching here is a compiler bug).
fn cvtTargetSuffix(tgt: sig.PrimType) ?[]const u8 {
    return switch (tgt) {
        .i1 => "i1",
        .i8 => "i8",
        .i16 => "i16",
        .i32 => "i32",
        .i64 => "i64",
        .u8 => "u8",
        .u16 => "u16",
        .u32 => "u32",
        .u64, .blob_handle => "u64",
        .f32 => "f32",
        .f64 => "f64",
        .ptr => "ptr",
        else => null,
    };
}

/// Whether (opcode, target) is a verifier-accepted conversion shape.
/// Anything else fails the build loudly instead of emitting wrong code.
fn cvtShapeValid(opcode: inst.OpKind, tgt: sig.PrimType) bool {
    return switch (opcode) {
        // Mirror interp isIntLike: int<->int only (float targets are
        // verifier-rejected, so reaching them here is a compiler bug).
        .trunc, .zext, .sext => switch (tgt) {
            .i1, .i8, .i16, .i32, .i64, .u8, .u16, .u32, .u64, .ptr, .blob_handle => true,
            else => false,
        },
        // bitcast allows any equal-width pair (verifier-enforced), so float
        // targets are legal here.
        .bitcast => switch (tgt) {
            .i1, .i8, .i16, .i32, .i64, .u8, .u16, .u32, .u64, .ptr, .blob_handle, .f32, .f64 => true,
            else => false,
        },
        .sitofp, .uitofp => switch (tgt) {
            .f32, .f64 => true,
            else => false,
        },
        .fptosi => switch (tgt) {
            .i1, .i8, .i16, .i32, .i64, .u8, .u16, .u32, .u64, .ptr, .blob_handle => true,
            else => false,
        },
        .fptrunc => tgt == .f32,
        .fpext => tgt == .f64,
        else => false,
    };
}

fn opNameForCvt(opcode: inst.OpKind) []const u8 {
    return switch (opcode) {
        .trunc => "trunc",
        .zext => "zext",
        .sext => "sext",
        .fptosi => "fptosi",
        .sitofp => "sitofp",
        .uitofp => "uitofp",
        .fptrunc => "fptrunc",
        .fpext => "fpext",
        .bitcast => "bitcast",
        else => "unknown",
    };
}

fn emitCvtExpr(writer: anytype, symbols: anytype, fsig: sig.FunctionSig, use_global: bool, const_addrs: anytype, fn_idx: anytype, opcode: inst.OpKind, tgt: sig.PrimType, src_op: inst.Operand, widths: *const WidthMap) !void {
    if (!cvtShapeValid(opcode, tgt)) return JsEmitError.InvalidOperand;
    const sfx = cvtTargetSuffix(tgt) orelse return JsEmitError.InvalidOperand;
    // Load-typed source widths sharpen conversions whose runtime
    // value-inference default (32-bit for Numbers) would misread
    // sub-word sources (e.g. zext of an i8-loaded 0xFF).
    const src_w: ?u32 = if (src_op == .reg) widths.get(src_op.reg) else null;
    if ((opcode == .zext or opcode == .sext) and src_w != null and !widthIsFloat(src_w.?) and widthBits(src_w.?) < 64) {
        const w = widthBits(src_w.?);
        try writer.print("__sa_cvt_{s}_{s}(__sa_srcmask(", .{ opNameForCvt(opcode), sfx });
        try resolveValueToJs(writer, symbols, fsig, use_global, const_addrs, fn_idx, src_op);
        try writer.print(", {d}, {s}))", .{ w, if (opcode == .sext) "true" else "false" });
        return;
    }
    if (opcode == .bitcast and tgt == .f32 and src_w != null and widthIsFloat(src_w.?)) {
        try writer.writeAll("(+");
        try resolveValueToJs(writer, symbols, fsig, use_global, const_addrs, fn_idx, src_op);
        try writer.writeAll(")");
        return;
    }
    if (opcode == .bitcast and tgt == .f64 and src_w != null and !widthIsFloat(src_w.?)) {
        try writer.writeAll("__sa_cvt_bitcast_f64i(");
        try resolveValueToJs(writer, symbols, fsig, use_global, const_addrs, fn_idx, src_op);
        try writer.writeAll(")");
        return;
    }
    if (opcode == .bitcast and (tgt == .i32 or tgt == .u32) and src_w != null and widthIsFloat(src_w.?)) {
        if (tgt == .i32) {
            try writer.writeAll("__sa_cvt_bitcast_i32f(");
        } else {
            try writer.writeAll("__sa_cvt_bitcast_u32f(");
        }
        try resolveValueToJs(writer, symbols, fsig, use_global, const_addrs, fn_idx, src_op);
        try writer.writeAll(")");
        return;
    }
    if (opcode == .bitcast and (tgt == .i64 or tgt == .u64) and src_w != null and widthIsFloat(src_w.?)) {
        if (tgt == .i64) {
            try writer.writeAll("__sa_cvt_bitcast_i64b(");
        } else {
            try writer.writeAll("__sa_cvt_bitcast_u64b(");
        }
        try resolveValueToJs(writer, symbols, fsig, use_global, const_addrs, fn_idx, src_op);
        try writer.writeAll(")");
        return;
    }
    try writer.print("__sa_cvt_{s}_{s}(", .{ opNameForCvt(opcode), sfx });
    try resolveValueToJs(writer, symbols, fsig, use_global, const_addrs, fn_idx, src_op);
    try writer.writeAll(")");
}

/// Statically tracked source widths for int/float-domain slots, keyed by
/// raw register id. Populated by a single forward pass over each function
/// body (see trackWidths); cleared at every label since merges are
/// untracked. Absent entries fall back to runtime value inference
/// (BigInt = 64-bit, Number = 32-bit), which is today's behavior, so the
/// map can only sharpen conversions, never change covered paths.
/// Packing: low 31 bits = width, high bit = float domain.
const WidthMap = std.AutoHashMap(u32, u32);

/// Packing: low 31 bits = width, bit 30 = signed integer domain,
/// bit 31 = float domain.
const WidthSignBit: u32 = 0x40000000;
const WidthFloatBit: u32 = 0x80000000;

fn packWidth(prim: sig.PrimType) ?u32 {
    return switch (prim) {
        .i1 => 1,
        .i8 => 8 | WidthSignBit,
        .i16 => 16 | WidthSignBit,
        .i32 => 32 | WidthSignBit,
        .i64 => 64 | WidthSignBit,
        .u8 => 8,
        .u16 => 16,
        .u32 => 32,
        .u64 => 64,
        .ptr, .blob_handle => 64,
        .f32 => WidthFloatBit | 32,
        .f64 => WidthFloatBit | 64,
        else => null,
    };
}

fn widthIsFloat(code: u32) bool {
    return (code & WidthFloatBit) != 0;
}

fn widthIsSigned(code: u32) bool {
    return (code & WidthSignBit) != 0;
}

fn widthBits(code: u32) u8 {
    return @intCast(code & 0xff);
}

fn widthRemoveSlot(widths: *WidthMap, op: inst.Operand) void {
    if (op == .reg) _ = widths.remove(op.reg);
}

fn widthCopySlot(widths: *WidthMap, dst_op: inst.Operand, src_op: inst.Operand) void {
    if (dst_op != .reg) return;
    if (src_op == .reg) {
        if (widths.get(src_op.reg)) |w| {
            widths.put(dst_op.reg, w) catch return;
        } else {
            _ = widths.remove(dst_op.reg);
        }
        return;
    }
    switch (src_op) {
        .imm_int, .imm_i64 => widths.put(dst_op.reg, 64 | WidthSignBit) catch return,
        .imm_u64 => widths.put(dst_op.reg, 64) catch return,
        .imm_float => widths.put(dst_op.reg, WidthFloatBit | 64) catch return,
        else => _ = widths.remove(dst_op.reg),
    }
}

/// Operand domain for kind-driven compat aliases (div/rem/gt/lt/shr),
/// mirroring interp numKind: float wins, then signed, else unsigned.
/// Unknown preserves today's forced-signed lowering exactly.
const OpndKind = enum { float, signed, unsigned, unknown };

fn operandKind(op: inst.Operand, widths: *const WidthMap) OpndKind {
    switch (op) {
        .reg => |id| {
            const w = widths.get(id) orelse return .unknown;
            if (widthIsFloat(w)) return .float;
            return if (widthIsSigned(w)) .signed else .unsigned;
        },
        .imm_float => return .float,
        .imm_int, .imm_i64 => return .signed,
        .imm_u64 => return .unsigned,
        .text, .native_text => |t| {
            var text = std.mem.trim(u8, t, " \t");
            if (text.len == 0) return .unknown;
            if (text[0] == '&' or text[0] == '*' or text[0] == '^') text = std.mem.trim(u8, text[1..], " \t");
            if (std.mem.lastIndexOf(u8, text, " as ")) |idx| text = std.mem.trim(u8, text[0..idx], " \t\r");
            if (text.len == 0) return .unknown;
            if (std.fmt.parseInt(i64, text, 10)) |_| return .signed else |_| {}
            if (std.fmt.parseInt(u64, text, 10)) |_| return .unsigned else |_| {}
            if (std.mem.indexOfAny(u8, text, ".eE")) |_| {
                if (std.fmt.parseFloat(f64, text)) |_| return .float else |_| {}
            }
            return .unknown;
        },
        else => return .unknown,
    }
}

fn combinedKind(a: OpndKind, b: OpndKind) OpndKind {
    if (a == .float or b == .float) return .float;
    if (a == .signed or b == .signed) return .signed;
    if (a == .unsigned and b == .unsigned) return .unsigned;
    return .unknown;
}

/// Forward type-width transfer for one instruction. Mirrors native typing:
/// int-op results are 64-bit (interp always builds i64/u64), int compares
/// are i1, float ops are f64. Anything unrecognized drops knowledge so a
/// stale entry can never feed a wrong mask.
fn trackWidths(widths: *WidthMap, allocator: std.mem.Allocator, symbols: anytype, base: inst.Instruction) void {
    switch (base.kind) {
        .load, .take, .atomic_load => {
            if (base.operands[0] != .reg) return;
            if (packWidth(memPrimType(base))) |w| {
                widths.put(base.operands[0].reg, w) catch return;
            } else {
                _ = widths.remove(base.operands[0].reg);
            }
        },
        .op => {
            if (base.operands[0] != .reg) return;
            const dst = base.operands[0].reg;
            const opcode = base.op_kind orelse {
                _ = widths.remove(dst);
                return;
            };
            if (inst.isTypeConversionOpKind(opcode)) {
                // Self-referential conversion keeps no reliable width.
                if (base.operands[1] == .reg and base.operands[1].reg == dst) {
                    _ = widths.remove(dst);
                    return;
                }
                if (base.operands[2] != .ty) {
                    _ = widths.remove(dst);
                    return;
                }
                if (packWidth(tagToPrim(base.operands[2].ty))) |w| {
                    widths.put(dst, w) catch return;
                } else {
                    _ = widths.remove(dst);
                }
                return;
            }
            switch (opcode) {
                .neg, .not, .fneg => widthCopySlot(widths, base.operands[0], base.operands[1]),
                .eq, .ne, .gt, .lt, .sgt, .slt, .sge, .sle, .ugt, .ult, .uge, .ule, .fcmp_eq, .fcmp_ne, .fcmp_lt, .fcmp_le, .fcmp_gt, .fcmp_ge => widths.put(dst, 1) catch return,
                .fadd, .fsub, .fmul, .fdiv => widths.put(dst, WidthFloatBit | 64) catch return,
                .sdiv, .srem, .ashr => widths.put(dst, 64 | WidthSignBit) catch return,
                .udiv, .urem, .lshr => widths.put(dst, 64) catch return,
                .add_v128, .sub_v128, .mul_v128, .shuffle_v128, .extract_lane, .insert_lane => _ = widths.remove(dst),
                .add, .sub, .mul, .div, .rem, .@"and", .@"or", .xor, .shl, .shr => {
                    // Kind-driven like interp numKind; unknown keeps today's
                    // forced-signed lowering exactly (no behavior change).
                    switch (combinedKind(operandKind(base.operands[1], widths), operandKind(base.operands[2], widths))) {
                        .float => _ = widths.remove(dst),
                        .signed => widths.put(dst, 64 | WidthSignBit) catch return,
                        .unsigned => widths.put(dst, 64) catch return,
                        .unknown => widths.put(dst, 64 | WidthSignBit) catch return,
                    }
                },
                else => widths.put(dst, 64 | WidthSignBit) catch return,
            }
        },
        .assign, .assume_safe, .assume_borrow => widthCopySlot(widths, base.operands[0], base.operands[1]),
        .borrow => {
            if (base.operands[0] == .reg) widths.put(base.operands[0].reg, 64) catch return;
        },
        .raw_cast => widthRemoveSlot(widths, base.operands[0]),
        .ptr_add, .alloc, .stack_alloc => {
            if (base.operands[0] == .reg) widths.put(base.operands[0].reg, 64) catch return;
        },
        .call, .call_indirect => {
            var parsed = call.parseInstructionCall(allocator, base, symbols) catch {
                widths.clearRetainingCapacity();
                return;
            };
            defer parsed.deinit(allocator);
            if (parsed.dest) |dest| {
                if (symbols.findId(dest)) |id| _ = widths.remove(id);
            }
        },
        .try_, .early_return => widthRemoveSlot(widths, base.operands[0]),
        .cmpxchg => {
            widthRemoveSlot(widths, base.operands[0]);
            widthRemoveSlot(widths, base.operands[1]);
        },
        .atomic_rmw => widthRemoveSlot(widths, base.operands[0]),
        .move_ => {
            widthRemoveSlot(widths, base.operands[0]);
            widthRemoveSlot(widths, base.operands[1]);
        },
        .store, .atomic_store, .fence, .release, .jmp, .br, .br_null, .panic, .panic_msg, .return_, .native, .label, .func_decl, .ffi_wrapper_decl, .extern_decl, .export_decl, .test_decl => {},
    }
}

/// Runtime callee for kind-driven compat aliases (div/rem/gt/lt/shr),
/// mirroring interp numKind. Unknown keeps today's forced-signed
/// lowering exactly, so only statically-known shapes change.
fn aliasCallee(opcode: inst.OpKind, k: OpndKind) []const u8 {
    return switch (opcode) {
        .div => switch (k) {
            .float => "__sa_fdiv",
            .unsigned => "__sa_udiv",
            else => "__sa_sdiv",
        },
        .rem => switch (k) {
            .unsigned => "__sa_urem",
            else => "__sa_srem",
        },
        .shr => switch (k) {
            .signed => "__sa_ashr",
            else => "__sa_lshr",
        },
        .gt => switch (k) {
            .float => "__sa_fgt",
            .unsigned => "__sa_ugt",
            else => "__sa_sgt",
        },
        .lt => switch (k) {
            .float => "__sa_flt",
            .unsigned => "__sa_ult",
            else => "__sa_slt",
        },
        else => unreachable,
    };
}

fn emitAliasOperands(writer: anytype, symbols: anytype, fsig: sig.FunctionSig, use_global: bool, const_addrs: anytype, fn_idx: anytype, lhs: inst.Operand, rhs: inst.Operand) !void {
    try resolveValueToJs(writer, symbols, fsig, use_global, const_addrs, fn_idx, lhs);
    try writer.writeAll(", ");
    try resolveValueToJs(writer, symbols, fsig, use_global, const_addrs, fn_idx, rhs);
    try writer.writeAll(")");
}

fn emitOpExpr(writer: anytype, symbols: anytype, fsig: sig.FunctionSig, use_global: bool, const_addrs: anytype, fn_idx: anytype, opcode: inst.OpKind, lhs: inst.Operand, rhs: inst.Operand, widths: *const WidthMap) !void {
    switch (opcode) {
        .add => {
            try writer.writeAll("__sa_add(");
            try resolveValueToJs(writer, symbols, fsig, use_global, const_addrs, fn_idx, lhs);
            try writer.writeAll(", ");
            try resolveValueToJs(writer, symbols, fsig, use_global, const_addrs, fn_idx, rhs);
            try writer.writeAll(")");
        },
        .sub => {
            try writer.writeAll("__sa_sub(");
            try resolveValueToJs(writer, symbols, fsig, use_global, const_addrs, fn_idx, lhs);
            try writer.writeAll(", ");
            try resolveValueToJs(writer, symbols, fsig, use_global, const_addrs, fn_idx, rhs);
            try writer.writeAll(")");
        },
        .mul => {
            try writer.writeAll("__sa_mul(");
            try resolveValueToJs(writer, symbols, fsig, use_global, const_addrs, fn_idx, lhs);
            try writer.writeAll(", ");
            try resolveValueToJs(writer, symbols, fsig, use_global, const_addrs, fn_idx, rhs);
            try writer.writeAll(")");
        },
        .sdiv => {
            try writer.writeAll("__sa_sdiv(");
            try resolveValueToJs(writer, symbols, fsig, use_global, const_addrs, fn_idx, lhs);
            try writer.writeAll(", ");
            try resolveValueToJs(writer, symbols, fsig, use_global, const_addrs, fn_idx, rhs);
            try writer.writeAll(")");
        },
        .div => {
            try writer.writeAll(aliasCallee(.div, combinedKind(operandKind(lhs, widths), operandKind(rhs, widths))));
            try writer.writeAll("(");
            try emitAliasOperands(writer, symbols, fsig, use_global, const_addrs, fn_idx, lhs, rhs);
        },
        .udiv => {
            try writer.writeAll("__sa_udiv(");
            try resolveValueToJs(writer, symbols, fsig, use_global, const_addrs, fn_idx, lhs);
            try writer.writeAll(", ");
            try resolveValueToJs(writer, symbols, fsig, use_global, const_addrs, fn_idx, rhs);
            try writer.writeAll(")");
        },
        .srem => {
            try writer.writeAll("__sa_srem(");
            try resolveValueToJs(writer, symbols, fsig, use_global, const_addrs, fn_idx, lhs);
            try writer.writeAll(", ");
            try resolveValueToJs(writer, symbols, fsig, use_global, const_addrs, fn_idx, rhs);
            try writer.writeAll(")");
        },
        .rem => {
            try writer.writeAll(aliasCallee(.rem, combinedKind(operandKind(lhs, widths), operandKind(rhs, widths))));
            try writer.writeAll("(");
            try emitAliasOperands(writer, symbols, fsig, use_global, const_addrs, fn_idx, lhs, rhs);
        },
        .urem => {
            try writer.writeAll("__sa_urem(");
            try resolveValueToJs(writer, symbols, fsig, use_global, const_addrs, fn_idx, lhs);
            try writer.writeAll(", ");
            try resolveValueToJs(writer, symbols, fsig, use_global, const_addrs, fn_idx, rhs);
            try writer.writeAll(")");
        },
        .@"and" => {
            try writer.writeAll("__sa_band(");
            try resolveValueToJs(writer, symbols, fsig, use_global, const_addrs, fn_idx, lhs);
            try writer.writeAll(", ");
            try resolveValueToJs(writer, symbols, fsig, use_global, const_addrs, fn_idx, rhs);
            try writer.writeAll(")");
        },
        .@"or" => {
            try writer.writeAll("__sa_bor(");
            try resolveValueToJs(writer, symbols, fsig, use_global, const_addrs, fn_idx, lhs);
            try writer.writeAll(", ");
            try resolveValueToJs(writer, symbols, fsig, use_global, const_addrs, fn_idx, rhs);
            try writer.writeAll(")");
        },
        .xor => {
            try writer.writeAll("__sa_bxor(");
            try resolveValueToJs(writer, symbols, fsig, use_global, const_addrs, fn_idx, lhs);
            try writer.writeAll(", ");
            try resolveValueToJs(writer, symbols, fsig, use_global, const_addrs, fn_idx, rhs);
            try writer.writeAll(")");
        },
        .shl => {
            try writer.writeAll("__sa_shl(");
            try resolveValueToJs(writer, symbols, fsig, use_global, const_addrs, fn_idx, lhs);
            try writer.writeAll(", ");
            try resolveValueToJs(writer, symbols, fsig, use_global, const_addrs, fn_idx, rhs);
            try writer.writeAll(")");
        },
        .lshr => {
            try writer.writeAll("__sa_lshr(");
            try resolveValueToJs(writer, symbols, fsig, use_global, const_addrs, fn_idx, lhs);
            try writer.writeAll(", ");
            try resolveValueToJs(writer, symbols, fsig, use_global, const_addrs, fn_idx, rhs);
            try writer.writeAll(")");
        },
        .shr => {
            try writer.writeAll(aliasCallee(.shr, combinedKind(operandKind(lhs, widths), operandKind(rhs, widths))));
            try writer.writeAll("(");
            try emitAliasOperands(writer, symbols, fsig, use_global, const_addrs, fn_idx, lhs, rhs);
        },
        .ashr => {
            try writer.writeAll("__sa_ashr(");
            try resolveValueToJs(writer, symbols, fsig, use_global, const_addrs, fn_idx, lhs);
            try writer.writeAll(", ");
            try resolveValueToJs(writer, symbols, fsig, use_global, const_addrs, fn_idx, rhs);
            try writer.writeAll(")");
        },
        .eq => {
            try writer.writeAll("__sa_eq(");
            try resolveValueToJs(writer, symbols, fsig, use_global, const_addrs, fn_idx, lhs);
            try writer.writeAll(", ");
            try resolveValueToJs(writer, symbols, fsig, use_global, const_addrs, fn_idx, rhs);
            try writer.writeAll(")");
        },
        .ne => {
            try writer.writeAll("__sa_ne(");
            try resolveValueToJs(writer, symbols, fsig, use_global, const_addrs, fn_idx, lhs);
            try writer.writeAll(", ");
            try resolveValueToJs(writer, symbols, fsig, use_global, const_addrs, fn_idx, rhs);
            try writer.writeAll(")");
        },
        .slt => {
            try writer.writeAll("__sa_slt(");
            try resolveValueToJs(writer, symbols, fsig, use_global, const_addrs, fn_idx, lhs);
            try writer.writeAll(", ");
            try resolveValueToJs(writer, symbols, fsig, use_global, const_addrs, fn_idx, rhs);
            try writer.writeAll(")");
        },
        .lt => {
            try writer.writeAll(aliasCallee(.lt, combinedKind(operandKind(lhs, widths), operandKind(rhs, widths))));
            try writer.writeAll("(");
            try emitAliasOperands(writer, symbols, fsig, use_global, const_addrs, fn_idx, lhs, rhs);
        },
        .sle => {
            try writer.writeAll("__sa_sle(");
            try resolveValueToJs(writer, symbols, fsig, use_global, const_addrs, fn_idx, lhs);
            try writer.writeAll(", ");
            try resolveValueToJs(writer, symbols, fsig, use_global, const_addrs, fn_idx, rhs);
            try writer.writeAll(")");
        },
        .sgt => {
            try writer.writeAll("__sa_sgt(");
            try resolveValueToJs(writer, symbols, fsig, use_global, const_addrs, fn_idx, lhs);
            try writer.writeAll(", ");
            try resolveValueToJs(writer, symbols, fsig, use_global, const_addrs, fn_idx, rhs);
            try writer.writeAll(")");
        },
        .gt => {
            try writer.writeAll(aliasCallee(.gt, combinedKind(operandKind(lhs, widths), operandKind(rhs, widths))));
            try writer.writeAll("(");
            try emitAliasOperands(writer, symbols, fsig, use_global, const_addrs, fn_idx, lhs, rhs);
        },
        .sge => {
            try writer.writeAll("__sa_sge(");
            try resolveValueToJs(writer, symbols, fsig, use_global, const_addrs, fn_idx, lhs);
            try writer.writeAll(", ");
            try resolveValueToJs(writer, symbols, fsig, use_global, const_addrs, fn_idx, rhs);
            try writer.writeAll(")");
        },
        .ult => {
            try writer.writeAll("__sa_ult(");
            try resolveValueToJs(writer, symbols, fsig, use_global, const_addrs, fn_idx, lhs);
            try writer.writeAll(", ");
            try resolveValueToJs(writer, symbols, fsig, use_global, const_addrs, fn_idx, rhs);
            try writer.writeAll(")");
        },
        .ule => {
            try writer.writeAll("__sa_ule(");
            try resolveValueToJs(writer, symbols, fsig, use_global, const_addrs, fn_idx, lhs);
            try writer.writeAll(", ");
            try resolveValueToJs(writer, symbols, fsig, use_global, const_addrs, fn_idx, rhs);
            try writer.writeAll(")");
        },
        .ugt => {
            try writer.writeAll("__sa_ugt(");
            try resolveValueToJs(writer, symbols, fsig, use_global, const_addrs, fn_idx, lhs);
            try writer.writeAll(", ");
            try resolveValueToJs(writer, symbols, fsig, use_global, const_addrs, fn_idx, rhs);
            try writer.writeAll(")");
        },
        .uge => {
            try writer.writeAll("__sa_uge(");
            try resolveValueToJs(writer, symbols, fsig, use_global, const_addrs, fn_idx, lhs);
            try writer.writeAll(", ");
            try resolveValueToJs(writer, symbols, fsig, use_global, const_addrs, fn_idx, rhs);
            try writer.writeAll(")");
        },
        .fadd => {
            try writer.writeAll("__sa_fadd(");
            try resolveValueToJs(writer, symbols, fsig, use_global, const_addrs, fn_idx, lhs);
            try writer.writeAll(", ");
            try resolveValueToJs(writer, symbols, fsig, use_global, const_addrs, fn_idx, rhs);
            try writer.writeAll(")");
        },
        .fsub => {
            try writer.writeAll("__sa_fsub(");
            try resolveValueToJs(writer, symbols, fsig, use_global, const_addrs, fn_idx, lhs);
            try writer.writeAll(", ");
            try resolveValueToJs(writer, symbols, fsig, use_global, const_addrs, fn_idx, rhs);
            try writer.writeAll(")");
        },
        .fmul => {
            try writer.writeAll("__sa_fmul(");
            try resolveValueToJs(writer, symbols, fsig, use_global, const_addrs, fn_idx, lhs);
            try writer.writeAll(", ");
            try resolveValueToJs(writer, symbols, fsig, use_global, const_addrs, fn_idx, rhs);
            try writer.writeAll(")");
        },
        .fdiv => {
            try writer.writeAll("__sa_fdiv(");
            try resolveValueToJs(writer, symbols, fsig, use_global, const_addrs, fn_idx, lhs);
            try writer.writeAll(", ");
            try resolveValueToJs(writer, symbols, fsig, use_global, const_addrs, fn_idx, rhs);
            try writer.writeAll(")");
        },
        .fcmp_eq => {
            try writer.writeAll("__sa_feq(");
            try resolveValueToJs(writer, symbols, fsig, use_global, const_addrs, fn_idx, lhs);
            try writer.writeAll(", ");
            try resolveValueToJs(writer, symbols, fsig, use_global, const_addrs, fn_idx, rhs);
            try writer.writeAll(")");
        },
        .fcmp_ne => {
            try writer.writeAll("__sa_fne(");
            try resolveValueToJs(writer, symbols, fsig, use_global, const_addrs, fn_idx, lhs);
            try writer.writeAll(", ");
            try resolveValueToJs(writer, symbols, fsig, use_global, const_addrs, fn_idx, rhs);
            try writer.writeAll(")");
        },
        .fcmp_lt => {
            try writer.writeAll("__sa_flt(");
            try resolveValueToJs(writer, symbols, fsig, use_global, const_addrs, fn_idx, lhs);
            try writer.writeAll(", ");
            try resolveValueToJs(writer, symbols, fsig, use_global, const_addrs, fn_idx, rhs);
            try writer.writeAll(")");
        },
        .fcmp_le => {
            try writer.writeAll("__sa_fle(");
            try resolveValueToJs(writer, symbols, fsig, use_global, const_addrs, fn_idx, lhs);
            try writer.writeAll(", ");
            try resolveValueToJs(writer, symbols, fsig, use_global, const_addrs, fn_idx, rhs);
            try writer.writeAll(")");
        },
        .fcmp_gt => {
            try writer.writeAll("__sa_fgt(");
            try resolveValueToJs(writer, symbols, fsig, use_global, const_addrs, fn_idx, lhs);
            try writer.writeAll(", ");
            try resolveValueToJs(writer, symbols, fsig, use_global, const_addrs, fn_idx, rhs);
            try writer.writeAll(")");
        },
        .fcmp_ge => {
            try writer.writeAll("__sa_fge(");
            try resolveValueToJs(writer, symbols, fsig, use_global, const_addrs, fn_idx, lhs);
            try writer.writeAll(", ");
            try resolveValueToJs(writer, symbols, fsig, use_global, const_addrs, fn_idx, rhs);
            try writer.writeAll(")");
        },
        .neg => {
            try writer.writeAll("__sa_neg(");
            try resolveValueToJs(writer, symbols, fsig, use_global, const_addrs, fn_idx, lhs);
            try writer.writeAll(")");
        },
        .not => {
            try writer.writeAll("__sa_bnot(");
            try resolveValueToJs(writer, symbols, fsig, use_global, const_addrs, fn_idx, lhs);
            try writer.writeAll(")");
        },
        .fneg => {
            try writer.writeAll("__sa_fneg(");
            try resolveValueToJs(writer, symbols, fsig, use_global, const_addrs, fn_idx, lhs);
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

/// Slots proven (within the current straight-line block) to hold owned heap
/// bases produced by `alloc`. `release` emits a real `__sa_free` only for
/// these; every other release stays a no-op comment. This mirrors the
/// interpreter, which frees exact owned bases but never interior pointers,
/// borrows, consts, or stack slots (value-equality alone is unsound: e.g.
/// `sa_mem_copy` releases borrow params whose values may equal a live base,
/// which corrupted `sort_probe` under unconditional freeing).
const BaseSet = std.AutoHashMap(u32, void);

fn provSlotOf(fsig: sig.FunctionSig, use_global: bool, op: inst.Operand) ?u32 {
    return switch (op) {
        .reg => |r| regSlot(fsig, use_global, r) catch null,
        .symbol => |id| regSlot(fsig, use_global, id) catch null,
        else => null,
    };
}

fn provKill(bases: *BaseSet, fsig: sig.FunctionSig, use_global: bool, op: inst.Operand) void {
    if (provSlotOf(fsig, use_global, op)) |slot| _ = bases.remove(slot);
}

fn provMark(bases: *BaseSet, fsig: sig.FunctionSig, use_global: bool, dst_op: inst.Operand, src_op: inst.Operand) JsEmitError!void {
    const dst = try dstSlot(fsig, use_global, dst_op);
    const src_base = if (provSlotOf(fsig, use_global, src_op)) |src| bases.get(src) != null else false;
    if (src_base) {
        bases.put(dst, {}) catch return JsEmitError.OutOfMemory;
    } else {
        _ = bases.remove(dst);
    }
}

/// Shared return emission for straight-line and pc-machine bodies.
/// Fallible functions return {s, v} objects (mirrors SA_OP_RET
/// build_fallible_ok); plain functions return bare values.
fn emitReturnStmt(writer: anytype, symbols: anytype, fsig: sig.FunctionSig, use_global: bool, const_addrs: anytype, fn_idx: anytype, operand: inst.Operand, indent: []const u8) !void {
    if (fsig.return_fallible) {
        switch (operand) {
            .none => try writer.print("{s}return {{s: 0}};\n", .{indent}),
            else => {
                try writer.print("{s}return {{s: 0, v: (", .{indent});
                try resolveValueToJs(writer, symbols, fsig, use_global, const_addrs, fn_idx, operand);
                try writer.writeAll(")};\n");
            },
        }
    } else switch (operand) {
        .none => try writer.print("{s}return 0;\n", .{indent}),
        else => {
            try writer.print("{s}return (", .{indent});
            try resolveValueToJs(writer, symbols, fsig, use_global, const_addrs, fn_idx, operand);
            try writer.writeAll(");\n");
        },
    }
}

fn emitCallInstruction(writer: anytype, allocator: std.mem.Allocator, symbols: anytype, fsig: sig.FunctionSig, use_global: bool, const_addrs: anytype, fn_idx: anytype, base: inst.Instruction, bases: *BaseSet, retbase: *const RetBaseTable) !void {
    _ = use_global;
    _ = fn_idx;
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
        // Fresh blocks from allocator shims and proven callees keep base
        // provenance; everything else is killed (unknown). Move-prefix
        // arguments are consumed.
        if (!parsed.is_indirect and provCallDestBase(bases, symbols, fsig, parsed.callee, parsed.args, retbase)) {
            bases.put(slot, {}) catch return JsEmitError.OutOfMemory;
        } else {
            _ = bases.remove(slot);
        }
        for (parsed.args) |arg| {
            if (arg.prefix == .move) {
                if (provArgSlot(symbols, fsig, arg.text)) |aslot| _ = bases.remove(aslot);
            }
        }
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

/// Indirect calls resolve through the runtime function table.
/// Boxed callee values come from vtable loads or `&func` expressions;
/// results (including fallible {s,v} objects) pass through untouched.
fn emitCallIndirectInstruction(writer: anytype, allocator: std.mem.Allocator, symbols: anytype, fsig: sig.FunctionSig, use_global: bool, const_addrs: anytype, fn_idx: anytype, base: inst.Instruction, bases: *BaseSet, retbase: *const RetBaseTable) !void {
    _ = use_global;
    _ = fn_idx;
    var parsed = call.parseInstructionCall(allocator, base, symbols) catch {
        try writer.print("  __sa_trap(\"unsupported call_indirect: {s}\");\n", .{std.mem.trim(u8, base.raw_text, " \t\r\n")});
        return;
    };
    defer parsed.deinit(allocator);
    if (parsed.dest) |dest| {
        const id = symbols.findId(dest) orelse return JsEmitError.InvalidOperand;
        const slot = fsig.slotOf(id) orelse return JsEmitError.InvalidOperand;
        // Fresh blocks from allocator shims and proven callees keep base
        // provenance; everything else is killed (unknown). Move-prefix
        // arguments are consumed.
        if (!parsed.is_indirect and provCallDestBase(bases, symbols, fsig, parsed.callee, parsed.args, retbase)) {
            bases.put(slot, {}) catch return JsEmitError.OutOfMemory;
        } else {
            _ = bases.remove(slot);
        }
        for (parsed.args) |arg| {
            if (arg.prefix == .move) {
                if (provArgSlot(symbols, fsig, arg.text)) |aslot| _ = bases.remove(aslot);
            }
        }
        try writer.print("  r{d} = ", .{slot});
    } else {
        try writer.writeAll("  ");
    }
    try writer.writeAll("__sa_call_indirect(");
    try resolveTextToJs(writer, symbols, fsig, const_addrs, parsed.callee);
    for (parsed.args) |arg| {
        try writer.writeAll(", ");
        try resolveTextToJs(writer, symbols, fsig, const_addrs, arg.text);
    }
    try writer.writeAll(");\n");
}

fn emitLinearInstruction(writer: anytype, allocator: std.mem.Allocator, symbols: anytype, fsig: sig.FunctionSig, use_global: bool, const_addrs: anytype, fn_idx: anytype, base: inst.Instruction, js_opt: JsEmitOptions, bases: *BaseSet, retbase: *const RetBaseTable, widths: *WidthMap) !void {
    _ = js_opt;
    last_js_inst = base.raw_text;
    last_js_func = fsig.name;
    trackWidths(widths, allocator, symbols, base);
    switch (base.kind) {
        .return_ => try emitReturnStmt(writer, symbols, fsig, use_global, const_addrs, fn_idx, base.operands[0], "  "),
        .try_, .early_return => {
            // Unpack {s, v}; on error early-return like SA_OP_TRY.
            const slot = try dstSlot(fsig, use_global, base.operands[0]);
            provKill(bases, fsig, use_global, base.operands[0]);
            try writer.writeAll("  { const __t = (");
            try resolveValueToJs(writer, symbols, fsig, use_global, const_addrs, fn_idx, base.operands[1]);
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
            provKill(bases, fsig, use_global, base.operands[0]);
            const opcode = base.op_kind orelse return JsEmitError.InvalidOperand;
            if (inst.isTypeConversionOpKind(opcode)) {
                if (base.operands[2] != .ty) return JsEmitError.InvalidOperand;
                try writer.print("  r{d} = ", .{slot});
                try emitCvtExpr(writer, symbols, fsig, use_global, const_addrs, fn_idx, opcode, tagToPrim(base.operands[2].ty), base.operands[1], widths);
                try writer.writeAll(";\n");
                return;
            }
            try writer.print("  r{d} = ", .{slot});
            if (opcode == .fneg) {
                try writer.writeAll("(-(");
                try resolveValueToJs(writer, symbols, fsig, use_global, const_addrs, fn_idx, base.operands[1]);
                try writer.writeAll("));\n");
                return;
            }
            try emitOpExpr(writer, symbols, fsig, use_global, const_addrs, fn_idx, opcode, base.operands[1], base.operands[2], widths);
            try writer.writeAll(";\n");
        },
        .alloc => {
            const slot = try dstSlot(fsig, use_global, base.operands[0]);
            // Fresh owned heap base: eligible for `__sa_free` on release.
            bases.put(slot, {}) catch return JsEmitError.OutOfMemory;
            try writer.print("  r{d} = __sa_alloc(", .{slot});
            try resolveValueToJs(writer, symbols, fsig, use_global, const_addrs, fn_idx, base.operands[1]);
            try writer.writeAll(");\n");
        },
        .stack_alloc => {
            const slot = try dstSlot(fsig, use_global, base.operands[0]);
            // Mirrors the interpreter: stack slots are never freed mid-frame;
            // they are recycled when the owning frame returns (finally pop).
            _ = bases.remove(slot);
            try writer.print("  r{d} = __sa_salloc(", .{slot});
            try resolveValueToJs(writer, symbols, fsig, use_global, const_addrs, fn_idx, base.operands[1]);
            try writer.writeAll(");\n");
        },
        .ptr_add => {
            const slot = try dstSlot(fsig, use_global, base.operands[0]);
            // Interior pointer (even at offset 0): never an owned base.
            _ = bases.remove(slot);
            try writer.print("  r{d} = __sa_ptr_add(", .{slot});
            try resolveValueToJs(writer, symbols, fsig, use_global, const_addrs, fn_idx, base.operands[1]);
            try writer.writeAll(", ");
            try resolveValueToJs(writer, symbols, fsig, use_global, const_addrs, fn_idx, base.operands[2]);
            try writer.writeAll(");\n");
        },
        .load, .take, .atomic_load => {
            // NOTE: atomic ordering is ignored (single-threaded JS runtime).
            const slot = try dstSlot(fsig, use_global, base.operands[0]);
            // Loaded data is never an owned base.
            _ = bases.remove(slot);
            const ty = memPrimType(base);
            try writer.print("  r{d} = {s}(__sa_ptr_add(", .{ slot, memLoadFn(ty) });
            try resolveValueToJs(writer, symbols, fsig, use_global, const_addrs, fn_idx, base.operands[1]);
            try writer.writeAll(", ");
            try resolveValueToJs(writer, symbols, fsig, use_global, const_addrs, fn_idx, base.operands[2]);
            try writer.writeAll("));\n");
        },
        .store, .atomic_store => {
            // NOTE: atomic ordering is ignored (single-threaded JS runtime).
            const ty = memPrimType(base);
            try writer.print("  {s}(__sa_ptr_add(", .{memStoreFn(ty)});
            try resolveValueToJs(writer, symbols, fsig, use_global, const_addrs, fn_idx, base.operands[0]);
            try writer.writeAll(", ");
            try resolveValueToJs(writer, symbols, fsig, use_global, const_addrs, fn_idx, base.operands[1]);
            try writer.writeAll("), ");
            try resolveValueToJs(writer, symbols, fsig, use_global, const_addrs, fn_idx, base.operands[2]);
            try writer.writeAll(");\n");
        },
        .call => try emitCallInstruction(writer, allocator, symbols, fsig, use_global, const_addrs, fn_idx, base, bases, retbase),
        .call_indirect => try emitCallIndirectInstruction(writer, allocator, symbols, fsig, use_global, const_addrs, fn_idx, base, bases, retbase),
        .cmpxchg => {
            // Single-threaded降级: old = load; ok = (old == expected);
            // if (ok) store(new). Mirrors SA_OP_CMPXCHG (dst=old, 2nd target=ok).
            const dst_old = try dstSlot(fsig, use_global, base.operands[0]);
            const dst_ok = try dstSlot(fsig, use_global, base.operands[1]);
            _ = bases.remove(dst_old);
            _ = bases.remove(dst_ok);
            const expected = base.atomic_expected_text orelse return JsEmitError.InvalidOperand;
            const new_text = base.atomic_new_text orelse return JsEmitError.InvalidOperand;
            const ty = memPrimType(base);
            const load_fn = memLoadFn(ty);
            const store_fn = memStoreFn(ty);
            try writer.writeAll("  { const __addr = __sa_ptr_add(");
            try resolveValueToJs(writer, symbols, fsig, use_global, const_addrs, fn_idx, base.operands[2]);
            try writer.writeAll(", ");
            try resolveValueToJs(writer, symbols, fsig, use_global, const_addrs, fn_idx, base.operands[3]);
            try writer.print("); const __old = {s}(__addr); const __exp = (", .{load_fn});
            try resolveTextToJs(writer, symbols, fsig, const_addrs, expected);
            try writer.writeAll("); const __ok = ((__old == __exp) ? 1 : 0); if (__ok) ");
            try writer.print("{s}(__addr, (", .{store_fn});
            try resolveTextToJs(writer, symbols, fsig, const_addrs, new_text);
            try writer.print(")); r{d} = __old; r{d} = __ok; }}\n", .{ dst_old, dst_ok });
        },
        .atomic_rmw => {
            // Single-threaded降级: dst = old = load(addr); store(addr, op(old, value)).
            // Mirrors LLVM atomicrmw (returns the previous memory contents).
            const op = base.atomic_rmw_op orelse return JsEmitError.InvalidOperand;
            const dst = try dstSlot(fsig, use_global, base.operands[0]);
            _ = bases.remove(dst);
            const ty = memPrimType(base);
            const load_fn = memLoadFn(ty);
            const store_fn = memStoreFn(ty);
            try writer.writeAll("  { const __addr = __sa_ptr_add(");
            try resolveValueToJs(writer, symbols, fsig, use_global, const_addrs, fn_idx, base.operands[1]);
            try writer.writeAll(", ");
            try resolveValueToJs(writer, symbols, fsig, use_global, const_addrs, fn_idx, base.operands[2]);
            try writer.print("); const __old = {s}(__addr); const __val = (", .{load_fn});
            try resolveValueToJs(writer, symbols, fsig, use_global, const_addrs, fn_idx, base.operands[3]);
            try writer.writeAll("); const __new = ");
            switch (op) {
                .add => try writer.writeAll("__sa_add(__old, __val)"),
                .sub => try writer.writeAll("__sa_sub(__old, __val)"),
                .@"and" => try writer.writeAll("__sa_band(__old, __val)"),
                .@"or" => try writer.writeAll("__sa_bor(__old, __val)"),
                .xor => try writer.writeAll("__sa_bxor(__old, __val)"),
                .xchg => try writer.writeAll("__val"),
                .min => try writer.writeAll("((__sa_sle(__old, __val)) ? __old : __val)"),
                .max => try writer.writeAll("((__sa_sge(__old, __val)) ? __old : __val)"),
                .umin => try writer.writeAll("((__sa_ule(__old, __val)) ? __old : __val)"),
                .umax => try writer.writeAll("((__sa_uge(__old, __val)) ? __old : __val)"),
            }
            try writer.print("; {s}(__addr, __new); r{d} = __old; }}\n", .{ store_fn, dst });
        },
        .fence => {
            try writer.writeAll("  /* no-op fence (single-threaded JS runtime) */\n");
        },
        .assign, .borrow, .raw_cast, .assume_safe, .assume_borrow => {
            // Mirror emit_llvm_llvmc assignOperand (and the interpreter):
            // dst aliases the value. assume_* are NOT no-ops: dropping the
            // copy leaves the dst slot at its zero init (broke pthread_spawn
            // entry delivery in 184_pthread_spawn_join).
            const slot = try dstSlot(fsig, use_global, base.operands[0]);
            // Alias preserves base provenance (borrow checking guarantees no
            // live use after any release of an alias).
            try provMark(bases, fsig, use_global, base.operands[0], base.operands[1]);
            try writer.print("  r{d} = (", .{slot});
            switch (base.operands[1]) {
                .reg, .symbol, .func, .label, .imm_i64, .imm_int, .imm_u64, .imm_float, .text, .native_text => {
                    try resolveValueToJs(writer, symbols, fsig, use_global, const_addrs, fn_idx, base.operands[1]);
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
        .move_ => {
            try writer.print("  /* no-op {s}: {s} */\n", .{ @tagName(base.kind), std.mem.trim(u8, base.raw_text, " \t\r\n") });
        },
        .release => {
            // Ownership release: emit a real `__sa_free` only for slots
            // proven to hold owned heap bases. Anything else (interior
            // pointers, borrows, scalars, consts) stays a no-op comment,
            // mirroring interp release semantics.
            const freeable = if (provSlotOf(fsig, use_global, base.operands[0])) |slot| bases.get(slot) != null else false;
            if (freeable) {
                if (provSlotOf(fsig, use_global, base.operands[0])) |slot| _ = bases.remove(slot);
                try writer.writeAll("  __sa_free(");
                try resolveValueToJs(writer, symbols, fsig, use_global, const_addrs, fn_idx, base.operands[0]);
                try writer.writeAll(");\n");
            } else {
                try writer.print("  /* no-op {s}: {s} */\n", .{ @tagName(base.kind), std.mem.trim(u8, base.raw_text, " \t\r\n") });
            }
        },
        .native => {
            // Empty-template `asm sideeffect ""` carries no observable effect;
            // downgrade to a no-op (value passes through, matching demo intent).
            // Non-empty native escapes stay a loud trap, escaped so quotes in
            // the raw text cannot break the generated JS module.
            const raw = std.mem.trim(u8, base.raw_text, " \t\r\n");
            if (std.mem.indexOf(u8, raw, "asm sideeffect \"\"") != null) {
                try writer.writeAll("  /* no-op empty inline asm (single-threaded JS runtime) */\n");
            } else {
                try writer.writeAll("  __sa_trap(\"unsupported native: ");
                try writeJsStrEscaped(writer, raw);
                try writer.writeAll("\");\n");
            }
        },
        else => {
            try writer.print("  __sa_trap(\"unsupported {s}: ", .{@tagName(base.kind)});
            try writeJsStrEscaped(writer, std.mem.trim(u8, base.raw_text, " \t\r\n"));
            try writer.writeAll("\");\n");
        },
    }
}

fn emitPcInstruction(writer: anytype, allocator: std.mem.Allocator, symbols: anytype, fsig: sig.FunctionSig, use_global: bool, const_addrs: anytype, fn_idx: anytype, base: inst.Instruction, label_pc: *std.AutoHashMap(u32, usize), js_opt: JsEmitOptions, bases: *BaseSet, retbase: *const RetBaseTable, widths: *WidthMap) !void {
    switch (base.kind) {
        .jmp => {
            const npc = try labelPcOf(label_pc, base.operands[1]);
            try writer.print("        __pc = {d}; break;\n", .{npc});
        },
        .br => {
            const tpc = try labelPcOf(label_pc, base.operands[1]);
            const fpc = try labelPcOf(label_pc, base.operands[3]);
            try writer.writeAll("        __pc = (__sa_truthy(");
            try resolveValueToJs(writer, symbols, fsig, use_global, const_addrs, fn_idx, base.operands[0]);
            try writer.print(") ? {d} : {d}); break;\n", .{ tpc, fpc });
        },
        .br_null => {
            // Null test on raw bits (mirrors interp `cond.bits == 0`):
            // only 0 / 0n count as null. NaN is *not* null (bits != 0),
            // so this intentionally differs from `!v` / `__sa_truthy`.
            const tpc = try labelPcOf(label_pc, base.operands[1]);
            const fpc = try labelPcOf(label_pc, base.operands[3]);
            try writer.writeAll("        __pc = ((((");
            try resolveValueToJs(writer, symbols, fsig, use_global, const_addrs, fn_idx, base.operands[0]);
            try writer.writeAll(") === 0) || ((");
            try resolveValueToJs(writer, symbols, fsig, use_global, const_addrs, fn_idx, base.operands[0]);
            try writer.writeAll(") === 0n))");
            try writer.print(" ? {d} : {d}); break;\n", .{ tpc, fpc });
        },
        .return_ => try emitReturnStmt(writer, symbols, fsig, use_global, const_addrs, fn_idx, base.operands[0], "        "),
        else => {
            try writer.writeAll("        ");
            // Reuse the linear emitter, then re-indent (it emits with 2-space indent).
            var buf: [32768]u8 = undefined;
            var fbs = std.io.fixedBufferStream(&buf);
            try emitLinearInstruction(fbs.writer(), allocator, symbols, fsig, use_global, const_addrs, fn_idx, base, js_opt, bases, retbase, widths);
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

const BlockRange = struct { start: usize, end: usize, label: ?u32 };

/// Forward must-analysis transfer for owned-base provenance: computes the set
/// of slots that hold `alloc` bases on EVERY path reaching each point.
/// Mirrors the interpreter (alloc marks; alias preserves; loads, arithmetic,
/// ptr_add, calls, cmpxchg results and stack_allocs kill).
fn provTransfer(
    allocator: std.mem.Allocator,
    symbols: anytype,
    fsig: sig.FunctionSig,
    use_global: bool,
    annotated: anytype,
    start: usize,
    end: usize,
    in_set: *const BaseSet,
    out_set: *BaseSet,
    retbase: *const RetBaseTable,
) JsEmitError!void {
    out_set.clearRetainingCapacity();
    var it = in_set.iterator();
    while (it.next()) |e| out_set.put(e.key_ptr.*, {}) catch return JsEmitError.OutOfMemory;
    var k: usize = start;
    while (k < end) : (k += 1) {
        const base = annotated[k].base;
        switch (base.kind) {
            .alloc => {
                if (provSlotOf(fsig, use_global, base.operands[0])) |slot| {
                    out_set.put(slot, {}) catch return JsEmitError.OutOfMemory;
                }
            },
            .assign, .borrow, .raw_cast, .assume_safe, .assume_borrow => {
                const dst = provSlotOf(fsig, use_global, base.operands[0]);
                const src_base = if (provSlotOf(fsig, use_global, base.operands[1])) |s| out_set.get(s) != null else false;
                if (dst) |d| {
                    if (src_base) {
                        out_set.put(d, {}) catch return JsEmitError.OutOfMemory;
                    } else {
                        _ = out_set.remove(d);
                    }
                }
            },
            .op, .ptr_add, .load, .take, .atomic_load, .atomic_rmw, .try_, .early_return => {
                provKill(out_set, fsig, use_global, base.operands[0]);
            },
            .cmpxchg => {
                provKill(out_set, fsig, use_global, base.operands[0]);
                provKill(out_set, fsig, use_global, base.operands[1]);
            },
            .move_ => {
                // Ownership transfer: forget both sides (sound over-approximation).
                provKill(out_set, fsig, use_global, base.operands[0]);
                provKill(out_set, fsig, use_global, base.operands[1]);
            },
            .release, .stack_alloc => {
                provKill(out_set, fsig, use_global, base.operands[0]);
            },
            .call, .call_indirect => {
                var parsed = call.parseInstructionCall(allocator, base, symbols) catch {
                    out_set.clearRetainingCapacity();
                    continue;
                };
                defer parsed.deinit(allocator);
                if (parsed.dest) |dest| {
                    if (symbols.findId(dest)) |id| {
                        if (fsig.slotOf(id)) |slot| {
                            if (!parsed.is_indirect and provCallDestBase(out_set, symbols, fsig, parsed.callee, parsed.args, retbase)) {
                                out_set.put(slot, {}) catch return JsEmitError.OutOfMemory;
                            } else {
                                _ = out_set.remove(slot);
                            }
                        }
                    }
                }
                // Move-prefix arguments are consumed by the call.
                for (parsed.args) |arg| {
                    if (arg.prefix == .move) {
                        if (provArgSlot(symbols, fsig, arg.text)) |aslot| _ = out_set.remove(aslot);
                    }
                }
            },
            else => {},
        }
    }
}

fn provSetEq(a: *const BaseSet, b: *const BaseSet) bool {
    if (a.count() != b.count()) return false;
    var it = a.iterator();
    while (it.next()) |e| {
        if (b.get(e.key_ptr.*) == null) return false;
    }
    return true;
}

fn provLabelId(op: inst.Operand) ?u32 {
    return switch (op) {
        .label => |v| v,
        .symbol => |v| v,
        else => null,
    };
}

/// Callee summary for base provenance: either every return carries a fresh
/// owned base from the callee body (alloc), or every return passes through
/// the same by_value/move parameter (param). Anything else is unprovable.
const RetBaseInfo = union(enum) { alloc: void, param: usize };
const RetBaseTable = std.StringHashMap(RetBaseInfo);

/// Host shims whose JS lowering allocates a fresh linear-memory block.
fn isAllocatorShim(name: []const u8) bool {
    return std.mem.eql(u8, name, "mmap") or
        std.mem.eql(u8, name, "dlopen") or
        std.mem.eql(u8, name, "dlsym");
}

/// Every extern name with a built-in host lowering in the emitter (as
/// opposed to a trap stub). A same-module `@export` never shadows these.
fn isKnownShim(name: []const u8) bool {
    if (std.mem.eql(u8, name, "sa_print_bytes")) return true;
    if (std.mem.eql(u8, name, "fd_open")) return true;
    if (std.mem.eql(u8, name, "fd_close")) return true;
    if (std.mem.eql(u8, name, "fd_read")) return true;
    if (isAllocatorShim(name)) return true;
    if (std.mem.eql(u8, name, "munmap")) return true;
    if (std.mem.eql(u8, name, "signal")) return true;
    if (std.mem.eql(u8, name, "pthread_spawn")) return true;
    if (std.mem.eql(u8, name, "pthread_join")) return true;
    if (std.mem.eql(u8, name, "pthread_drop")) return true;
    if (std.mem.eql(u8, name, "dlclose")) return true;
    if (std.mem.eql(u8, name, "sqlite3_prepare")) return true;
    if (std.mem.eql(u8, name, "sqlite3_step")) return true;
    if (std.mem.eql(u8, name, "sqlite3_finalize")) return true;
    if (std.mem.eql(u8, name, "sa_http_client_new")) return true;
    if (std.mem.eql(u8, name, "sa_http_client_req_new")) return true;
    if (std.mem.eql(u8, name, "sa_http_client_req_add_header")) return true;
    if (std.mem.eql(u8, name, "sa_http_client_req_set_body")) return true;
    if (std.mem.eql(u8, name, "sa_http_client_req_send")) return true;
    if (std.mem.eql(u8, name, "sa_http_client_resp_status")) return true;
    if (std.mem.eql(u8, name, "sa_http_client_resp_body_reader")) return true;
    if (std.mem.eql(u8, name, "sa_http_client_resp_read_chunk")) return true;
    if (std.mem.eql(u8, name, "sa_http_client_resp_free")) return true;
    if (std.mem.eql(u8, name, "sa_http_client_body_reader_free")) return true;
    if (std.mem.eql(u8, name, "sa_http_client_req_free")) return true;
    if (std.mem.eql(u8, name, "sa_http_client_free")) return true;
    if (std.mem.eql(u8, name, "sa_http_server_new")) return true;
    if (std.mem.eql(u8, name, "sa_http_server_start")) return true;
    if (std.mem.eql(u8, name, "sa_http_server_accept")) return true;
    if (std.mem.eql(u8, name, "sa_http_server_req_get_path")) return true;
    if (std.mem.eql(u8, name, "sa_http_server_req_get_header")) return true;
    if (std.mem.eql(u8, name, "sa_http_server_req_get_body")) return true;
    if (std.mem.eql(u8, name, "sa_http_server_resp_stream_new")) return true;
    if (std.mem.eql(u8, name, "sa_http_server_resp_stream_write")) return true;
    if (std.mem.eql(u8, name, "sa_http_server_resp_stream_flush")) return true;
    if (std.mem.eql(u8, name, "sa_http_server_resp_stream_end")) return true;
    if (std.mem.eql(u8, name, "sa_http_server_resp_stream_free")) return true;
    if (std.mem.eql(u8, name, "sa_http_server_req_free")) return true;
    if (std.mem.eql(u8, name, "sa_http_server_free")) return true;
    return false;
}

/// Slot of a call argument by its bare name (prefix already stripped by the
/// call parser). Used to test by_value/move argument provenance.
fn provArgSlot(symbols: anytype, fsig: sig.FunctionSig, arg_text: []const u8) ?u32 {
    const id = symbols.findId(arg_text) orelse return null;
    return fsig.slotOf(id);
}

/// Whether a call result slot is proven to hold an owned base: allocator
/// shims and alloc-class callees always qualify; param-class callees qualify
/// iff the corresponding argument is a transparent (by_value/move) proven
/// base in the caller's set.
fn provCallDestBase(
    set: *const BaseSet,
    symbols: anytype,
    fsig: sig.FunctionSig,
    parsed_callee: []const u8,
    parsed_args: anytype,
    retbase: *const RetBaseTable,
) bool {
    if (isAllocatorShim(parsed_callee)) return true;
    const info = retbase.get(parsed_callee) orelse return false;
    switch (info) {
        .alloc => return true,
        .param => |pi| {
            if (pi >= parsed_args.len) return false;
            const arg = parsed_args[pi];
            if (arg.prefix != .by_value and arg.prefix != .move) return false;
            if (provArgSlot(symbols, fsig, arg.text)) |aslot| {
                return set.get(aslot) != null;
            }
            return false;
        },
    }
}

const ProvBody = struct {
    blocks: std.ArrayList(BlockRange),
    lid_to_blk: std.AutoHashMap(u32, usize),
    succs: std.ArrayList(std.ArrayList(usize)),
    in_sets: std.ArrayList(BaseSet),
    out_sets: std.ArrayList(BaseSet),

    fn deinit(self: *ProvBody) void {
        for (self.in_sets.items) |*s| s.deinit();
        for (self.out_sets.items) |*s| s.deinit();
        for (self.succs.items) |*s| s.deinit();
        self.blocks.deinit();
        self.lid_to_blk.deinit();
        self.succs.deinit();
        self.in_sets.deinit();
        self.out_sets.deinit();
    }
};

/// Build blocks/CFG and run the owned-base must-analysis fixpoint for one
/// function body. Shared by emission and return-base summary computation.
fn provSolveBody(
    allocator: std.mem.Allocator,
    verified: anytype,
    fsig: sig.FunctionSig,
    use_global: bool,
    task: FuncTask,
    retbase: *const RetBaseTable,
    seed: ?u32,
) JsEmitError!ProvBody {
    var prov = ProvBody{
        .blocks = std.ArrayList(BlockRange).init(allocator),
        .lid_to_blk = std.AutoHashMap(u32, usize).init(allocator),
        .succs = std.ArrayList(std.ArrayList(usize)).init(allocator),
        .in_sets = std.ArrayList(BaseSet).init(allocator),
        .out_sets = std.ArrayList(BaseSet).init(allocator),
    };
    errdefer prov.deinit();
    {
        var bs: usize = task.start_idx + 1;
        var blabel: ?u32 = null;
        var j: usize = bs;
        while (j < task.end_idx) : (j += 1) {
            const bk = verified.annotated[j].base;
            if (bk.kind == .label) {
                if (j > bs) {
                    prov.blocks.append(.{ .start = bs, .end = j, .label = blabel }) catch return JsEmitError.OutOfMemory;
                    blabel = provLabelId(bk.operands[1]);
                    bs = j + 1;
                } else if (blabel == null) {
                    blabel = provLabelId(bk.operands[1]);
                }
            } else if (bk.kind == .jmp or bk.kind == .br or bk.kind == .br_null or bk.kind == .return_) {
                prov.blocks.append(.{ .start = bs, .end = j + 1, .label = blabel }) catch return JsEmitError.OutOfMemory;
                blabel = null;
                bs = j + 1;
            }
        }
        if (bs < task.end_idx) prov.blocks.append(.{ .start = bs, .end = task.end_idx, .label = blabel }) catch return JsEmitError.OutOfMemory;
    }
    for (prov.blocks.items, 0..) |blk, bi| {
        if (blk.label) |lid| {
            if (prov.lid_to_blk.get(lid) == null) prov.lid_to_blk.put(lid, bi) catch return JsEmitError.OutOfMemory;
        }
    }
    for (prov.blocks.items, 0..) |blk, bi| {
        var s = std.ArrayList(usize).init(allocator);
        errdefer s.deinit();
        if (blk.end > blk.start) {
            const last = verified.annotated[blk.end - 1].base;
            switch (last.kind) {
                .jmp => {
                    if (provLabelId(last.operands[1])) |lid| {
                        if (prov.lid_to_blk.get(lid)) |t| s.append(t) catch return JsEmitError.OutOfMemory;
                    }
                },
                .br => {
                    if (provLabelId(last.operands[1])) |lid| {
                        if (prov.lid_to_blk.get(lid)) |t| s.append(t) catch return JsEmitError.OutOfMemory;
                    }
                    if (provLabelId(last.operands[3])) |lid| {
                        if (prov.lid_to_blk.get(lid)) |t| s.append(t) catch return JsEmitError.OutOfMemory;
                    }
                },
                .return_ => {},
                else => {
                    if (bi + 1 < prov.blocks.items.len) s.append(bi + 1) catch return JsEmitError.OutOfMemory;
                },
            }
        } else if (bi + 1 < prov.blocks.items.len) {
            s.append(bi + 1) catch return JsEmitError.OutOfMemory;
        }
        prov.succs.append(s) catch return JsEmitError.OutOfMemory;
    }
    for (prov.blocks.items) |_| {
        prov.in_sets.append(BaseSet.init(allocator)) catch return JsEmitError.OutOfMemory;
        prov.out_sets.append(BaseSet.init(allocator)) catch return JsEmitError.OutOfMemory;
    }
    var universe = BaseSet.init(allocator);
    defer universe.deinit();
    for (prov.blocks.items) |blk| {
        var k: usize = blk.start;
        while (k < blk.end) : (k += 1) {
            const base = verified.annotated[k].base;
            switch (base.kind) {
                .alloc, .stack_alloc, .assign, .borrow, .raw_cast, .assume_safe, .assume_borrow, .op, .ptr_add, .load, .take, .atomic_load, .atomic_rmw, .try_, .early_return, .move_, .release => {
                    if (provSlotOf(fsig, use_global, base.operands[0])) |slot| {
                        universe.put(slot, {}) catch return JsEmitError.OutOfMemory;
                    }
                },
                .cmpxchg => {
                    if (provSlotOf(fsig, use_global, base.operands[0])) |slot| {
                        universe.put(slot, {}) catch return JsEmitError.OutOfMemory;
                    }
                    if (provSlotOf(fsig, use_global, base.operands[1])) |slot| {
                        universe.put(slot, {}) catch return JsEmitError.OutOfMemory;
                    }
                },
                .call, .call_indirect => {
                    var parsed = call.parseInstructionCall(allocator, base, verified.symbols) catch continue;
                    defer parsed.deinit(allocator);
                    if (parsed.dest) |dest| {
                        if (verified.symbols.findId(dest)) |id| {
                            if (fsig.slotOf(id)) |slot| {
                                universe.put(slot, {}) catch return JsEmitError.OutOfMemory;
                            }
                        }
                    }
                },
                else => {},
            }
        }
    }
    for (prov.in_sets.items, 0..) |*st, bi| {
        if (bi == 0) continue;
        var uit = universe.iterator();
        while (uit.next()) |e| st.put(e.key_ptr.*, {}) catch return JsEmitError.OutOfMemory;
    }
    var rounds: usize = 0;
    while (rounds < 100) : (rounds += 1) {
        var changed = false;
        for (prov.blocks.items, 0..) |blk, bi| {
            var tmp = BaseSet.init(allocator);
            defer tmp.deinit();
            var first_pred = true;
            for (prov.blocks.items, 0..) |_, pi| {
                var is_pred = false;
                for (prov.succs.items[pi].items) |t| {
                    if (t == bi) {
                        is_pred = true;
                        break;
                    }
                }
                if (!is_pred) continue;
                if (first_pred) {
                    var oit = prov.out_sets.items[pi].iterator();
                    while (oit.next()) |e| tmp.put(e.key_ptr.*, {}) catch return JsEmitError.OutOfMemory;
                    first_pred = false;
                } else {
                    var rm = std.ArrayList(u32).init(allocator);
                    defer rm.deinit();
                    var tit = tmp.iterator();
                    while (tit.next()) |e| {
                        if (prov.out_sets.items[pi].get(e.key_ptr.*) == null) rm.append(e.key_ptr.*) catch return JsEmitError.OutOfMemory;
                    }
                    for (rm.items) |slot| _ = tmp.remove(slot);
                }
            }
            if (first_pred) tmp.clearRetainingCapacity();
            if (bi == 0) {
                // Entry seed (for param-passthrough queries): a parameter
                // assumed to be a base on entry.
                if (seed) |s| tmp.put(s, {}) catch return JsEmitError.OutOfMemory;
            }
            if (!provSetEq(&prov.in_sets.items[bi], &tmp)) {
                prov.in_sets.items[bi].clearRetainingCapacity();
                var tit = tmp.iterator();
                while (tit.next()) |e| prov.in_sets.items[bi].put(e.key_ptr.*, {}) catch return JsEmitError.OutOfMemory;
                changed = true;
            }
            try provTransfer(allocator, verified.symbols, fsig, use_global, verified.annotated, blk.start, blk.end, &prov.in_sets.items[bi], &prov.out_sets.items[bi], retbase);
        }
        if (!changed) break;
    }
    return prov;
}

/// True iff every `return` in the body returns a slot proven to hold an
/// owned heap base (replaying the block transfer up to each return).
fn provAllReturnsProven(
    allocator: std.mem.Allocator,
    verified: anytype,
    fsig: sig.FunctionSig,
    use_global: bool,
    prov: *const ProvBody,
    retbase: *const RetBaseTable,
) JsEmitError!bool {
    var found = false;
    for (prov.blocks.items, 0..) |blk, bi| {
        var k: usize = blk.start;
        while (k < blk.end) : (k += 1) {
            const base = verified.annotated[k].base;
            if (base.kind != .return_) continue;
            found = true;
            var tmp = BaseSet.init(allocator);
            defer tmp.deinit();
            try provTransfer(allocator, verified.symbols, fsig, use_global, verified.annotated, blk.start, k, &prov.in_sets.items[bi], &tmp, retbase);
            const ok = if (provSlotOf(fsig, use_global, base.operands[0])) |slot| tmp.get(slot) != null else false;
            if (!ok) return false;
        }
    }
    return found;
}

fn emitBodyAsPcMachine(writer: anytype, allocator: std.mem.Allocator, verified: anytype, fsig: sig.FunctionSig, task: FuncTask, const_addrs: anytype, fn_idx: anytype, js_opt: JsEmitOptions, retbase: *const RetBaseTable) !void {    const use_global = taskUsesGlobalRegIds(fsig, verified, task);
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
    // Owned-base provenance for `release` lowering (see provSolveBody).
    var bases = BaseSet.init(allocator);
    defer bases.deinit();
    // Statically tracked source widths for conversions (see trackWidths);
    // cleared at every label since merges are untracked (sound fallback).
    var widths = WidthMap.init(allocator);
    defer widths.deinit();
    var prov = try provSolveBody(allocator, verified, fsig, use_global, task, retbase, null);
    defer prov.deinit();
    // If no labels at all, emit straight-line body without pc machine.
    if (pcs == 1) {
        i = task.start_idx + 1;
        while (i < task.end_idx) : (i += 1) {
            try emitLinearInstruction(writer, allocator, verified.symbols, fsig, use_global, const_addrs, fn_idx, verified.annotated[i].base, js_opt, &bases, retbase, &widths);
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
            // Join point: load the fixpoint IN set for this block (sound on
            // every path); unknown labels fall back to empty (safe).
            bases.clearRetainingCapacity();
            widths.clearRetainingCapacity();
            if (prov.lid_to_blk.get(lid)) |tbi| {
                var iit = prov.in_sets.items[tbi].iterator();
                while (iit.next()) |e| try bases.put(e.key_ptr.*, {});
            }
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
        try emitPcInstruction(writer, allocator, verified.symbols, fsig, use_global, const_addrs, fn_idx, base, &label_pc, js_opt, &bases, retbase, &widths);
        prev_terminates = base.kind == .jmp or base.kind == .br or base.kind == .br_null or base.kind == .return_;
    }
    try writer.writeAll("        return __sa_trap(\"fallthrough end of function\");\n      }\n      default: return __sa_trap(\"bad pc \" + __pc);\n    }\n  }\n");
}

fn emitOneFunction(writer: anytype, allocator: std.mem.Allocator, verified: anytype, task: FuncTask, const_addrs: anytype, fn_idx: anytype, js_opt: JsEmitOptions, retbase: *const RetBaseTable) !void {
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
        // POSIX-like host shims for OS-binding demos (single-threaded
        // simulation, same staged semantics as the native plugin oracles).
        // fds start at 3 per Linux convention (0/1/2 reserved).
        if (std.mem.eql(u8, fsig.name, "fd_open")) {
            try writer.writeAll(
                \\function fd_open(path) {
                \\  globalThis.__sa_next_fd = (globalThis.__sa_next_fd || 3);
                \\  return globalThis.__sa_next_fd++;
                \\}
                \\
            );
            return;
        }
        if (std.mem.eql(u8, fsig.name, "fd_close")) {
            try writer.writeAll("function fd_close(fd) { return 0; }\n");
            return;
        }
        if (std.mem.eql(u8, fsig.name, "fd_read")) {
            // Staged simulation: matches the rosetta oracle (read yields 3).
            try writer.writeAll("function fd_read(fd) { return 3; }\n");
            return;
        }
        if (std.mem.eql(u8, fsig.name, "mmap")) {
            // Zero-filled bump allocation stands in for an anonymous mapping.
            try writer.writeAll("function mmap(fd, len) { return __sa_alloc(__sa_num(len)); }\n");
            return;
        }
        if (std.mem.eql(u8, fsig.name, "munmap")) {
            try writer.writeAll("function munmap(map, len) { return 0; }\n");
            return;
        }
        if (std.mem.eql(u8, fsig.name, "signal")) {
            // Echo the signal number back (staged oracle semantics).
            try writer.writeAll("function signal(sig, handler) { return __sa_num(sig); }\n");
            return;
        }
        if (std.mem.eql(u8, fsig.name, "pthread_spawn")) {
            // Single-threaded: run the entry synchronously via the fn table,
            // then hand out a joinable handle.
            try writer.writeAll(
                \\function pthread_spawn(entry, arg) {
                \\  const i = __sa_fnval(entry);
                \\  if (i >= 0) __sa_ftable[i](arg);
                \\  globalThis.__sa_next_thr = (globalThis.__sa_next_thr || 1);
                \\  return globalThis.__sa_next_thr++;
                \\}
                \\
            );
            return;
        }
        if (std.mem.eql(u8, fsig.name, "pthread_join")) {
            // Entry already ran inside pthread_spawn; nothing to wait for.
            try writer.writeAll("function pthread_join(handle, out) { return 0; }\n");
            return;
        }
        if (std.mem.eql(u8, fsig.name, "pthread_drop")) {
            try writer.writeAll("function pthread_drop(handle) { return 0; }\n");
            return;
        }
        // Dynamic-loader shims: nonzero cookie handles stand in for the OS
        // loader (staged oracle semantics: handle/symbol nonzero, close 0).
        if (std.mem.eql(u8, fsig.name, "dlopen")) {
            try writer.writeAll("function dlopen(path, flags) { return __sa_alloc(8); }\n");
            return;
        }
        if (std.mem.eql(u8, fsig.name, "dlsym")) {
            try writer.writeAll("function dlsym(handle, symbol) { return __sa_alloc(8); }\n");
            return;
        }
        if (std.mem.eql(u8, fsig.name, "dlclose")) {
            try writer.writeAll("function dlclose(handle) { return 0; }\n");
            return;
        }
        // SQLite C-API shims (staged oracle semantics: prepare/finalize 0,
        // step returns SQLITE_ROW so the row-present branch is taken).
        if (std.mem.eql(u8, fsig.name, "sqlite3_prepare")) {
            try writer.writeAll("function sqlite3_prepare(sqlite, sql, len, stmt_out) { return 0; }\n");
            return;
        }
        if (std.mem.eql(u8, fsig.name, "sqlite3_step")) {
            try writer.writeAll("function sqlite3_step(stmt) { return 100; }\n");
            return;
        }
        if (std.mem.eql(u8, fsig.name, "sqlite3_finalize")) {
            try writer.writeAll("function sqlite3_finalize(stmt) { return 0; }\n");
            return;
        }
        // HTTP client/server shims (staged oracle semantics: in-heap echo and
        // canned request/response, same single-threaded simulation waterline
        // as the fd/pthread/sqlite shims above; the native plugin oracles do
        // real 127.0.0.1 loopback while the JS backend stages the values).
        if (std.mem.eql(u8, fsig.name, "sa_http_client_new")) {
            try writer.writeAll(
                \\function sa_http_client_new(use_tls, out_client) {
                \\  globalThis.__sa_http_c = (globalThis.__sa_http_c || {});
                \\  globalThis.__sa_http_req = (globalThis.__sa_http_req || {});
                \\  globalThis.__sa_http_resp = (globalThis.__sa_http_resp || {});
                \\  globalThis.__sa_http_rd = (globalThis.__sa_http_rd || {});
                \\  const h = __sa_alloc(8);
                \\  globalThis.__sa_http_c[__sa_addr(h)] = { tls: __sa_num(use_tls) };
                \\  __sa_store_ptr(out_client, h);
                \\  return 0;
                \\}
                \\
            );
            return;
        }
        if (std.mem.eql(u8, fsig.name, "sa_http_client_req_new")) {
            try writer.writeAll(
                \\function sa_http_client_req_new(client, method, url, url_len, out_req) {
                \\  const a = __sa_addr(url), n = __sa_num(url_len);
                \\  const u = new globalThis.TextDecoder().decode(__sa_u8.slice(a, a + n));
                \\  const h = __sa_alloc(8);
                \\  globalThis.__sa_http_req[__sa_addr(h)] = { method: __sa_num(method), url: u, headers: {}, body: new Uint8Array(0) };
                \\  __sa_store_ptr(out_req, h);
                \\  return 0;
                \\}
                \\
            );
            return;
        }
        if (std.mem.eql(u8, fsig.name, "sa_http_client_req_add_header")) {
            try writer.writeAll(
                \\function sa_http_client_req_add_header(req, key, key_len, val, val_len) {
                \\  const r = globalThis.__sa_http_req[__sa_addr(req)];
                \\  if (!r) return 1;
                \\  const ka = __sa_addr(key), kn = __sa_num(key_len), va = __sa_addr(val), vn = __sa_num(val_len);
                \\  const dec = new globalThis.TextDecoder();
                \\  r.headers[dec.decode(__sa_u8.slice(ka, ka + kn))] = dec.decode(__sa_u8.slice(va, va + vn));
                \\  return 0;
                \\}
                \\
            );
            return;
        }
        if (std.mem.eql(u8, fsig.name, "sa_http_client_req_set_body")) {
            try writer.writeAll(
                \\function sa_http_client_req_set_body(req, body, body_len) {
                \\  const r = globalThis.__sa_http_req[__sa_addr(req)];
                \\  if (!r) return 1;
                \\  const a = __sa_addr(body), n = __sa_num(body_len);
                \\  r.body = __sa_u8.slice(a, a + n);
                \\  return 0;
                \\}
                \\
            );
            return;
        }
        if (std.mem.eql(u8, fsig.name, "sa_http_client_req_send")) {
            try writer.writeAll(
                \\function sa_http_client_req_send(req, out_resp) {
                \\  const r = globalThis.__sa_http_req[__sa_addr(req)];
                \\  if (!r) return 1;
                \\  const h = __sa_alloc(8);
                \\  globalThis.__sa_http_resp[__sa_addr(h)] = { status: 200, body: r.body.slice() };
                \\  __sa_store_ptr(out_resp, h);
                \\  return 0;
                \\}
                \\
            );
            return;
        }
        if (std.mem.eql(u8, fsig.name, "sa_http_client_resp_status")) {
            try writer.writeAll(
                \\function sa_http_client_resp_status(resp) {
                \\  const r = globalThis.__sa_http_resp[__sa_addr(resp)];
                \\  return r ? r.status : 0;
                \\}
                \\
            );
            return;
        }
        if (std.mem.eql(u8, fsig.name, "sa_http_client_resp_body_reader")) {
            try writer.writeAll(
                \\function sa_http_client_resp_body_reader(resp, out_reader) {
                \\  const r = globalThis.__sa_http_resp[__sa_addr(resp)];
                \\  if (!r) return 1;
                \\  const h = __sa_alloc(8);
                \\  globalThis.__sa_http_rd[__sa_addr(h)] = { body: r.body, off: 0 };
                \\  __sa_store_ptr(out_reader, h);
                \\  return 0;
                \\}
                \\
            );
            return;
        }
        if (std.mem.eql(u8, fsig.name, "sa_http_client_resp_read_chunk")) {
            try writer.writeAll(
                \\function sa_http_client_resp_read_chunk(reader, buf, cap, out_len) {
                \\  const r = globalThis.__sa_http_rd[__sa_addr(reader)];
                \\  if (!r) return 1;
                \\  const n = Math.min(__sa_num(cap), r.body.length - r.off);
                \\  __sa_u8.set(r.body.subarray(r.off, r.off + n), __sa_addr(buf));
                \\  r.off += n;
                \\  __sa_store_i64(out_len, n);
                \\  return 0;
                \\}
                \\
            );
            return;
        }
        if (std.mem.eql(u8, fsig.name, "sa_http_client_resp_free")) {
            try writer.writeAll("function sa_http_client_resp_free(resp) { delete globalThis.__sa_http_resp[__sa_addr(resp)]; return 0; }\n");
            return;
        }
        if (std.mem.eql(u8, fsig.name, "sa_http_client_body_reader_free")) {
            try writer.writeAll("function sa_http_client_body_reader_free(reader) { delete globalThis.__sa_http_rd[__sa_addr(reader)]; return 0; }\n");
            return;
        }
        if (std.mem.eql(u8, fsig.name, "sa_http_client_req_free")) {
            try writer.writeAll("function sa_http_client_req_free(req) { delete globalThis.__sa_http_req[__sa_addr(req)]; return 0; }\n");
            return;
        }
        if (std.mem.eql(u8, fsig.name, "sa_http_client_free")) {
            try writer.writeAll("function sa_http_client_free(client) { delete globalThis.__sa_http_c[__sa_addr(client)]; return 0; }\n");
            return;
        }
        if (std.mem.eql(u8, fsig.name, "sa_http_server_new")) {
            try writer.writeAll(
                \\function sa_http_server_new(out_server) {
                \\  globalThis.__sa_https = (globalThis.__sa_https || {});
                \\  globalThis.__sa_http_sreq = (globalThis.__sa_http_sreq || {});
                \\  globalThis.__sa_http_sresp = (globalThis.__sa_http_sresp || {});
                \\  const h = __sa_alloc(8);
                \\  globalThis.__sa_https[__sa_addr(h)] = {};
                \\  __sa_store_ptr(out_server, h);
                \\  return 0;
                \\}
                \\
            );
            return;
        }
        if (std.mem.eql(u8, fsig.name, "sa_http_server_start")) {
            try writer.writeAll(
                \\function sa_http_server_start(server, host, host_len, port) {
                \\  const s = globalThis.__sa_https[__sa_addr(server)];
                \\  if (!s) return 1;
                \\  const a = __sa_addr(host), n = __sa_num(host_len);
                \\  s.host = new globalThis.TextDecoder().decode(__sa_u8.slice(a, a + n));
                \\  s.port = __sa_num(port);
                \\  return 0;
                \\}
                \\
            );
            return;
        }
        if (std.mem.eql(u8, fsig.name, "sa_http_server_accept")) {
            try writer.writeAll(
                \\function sa_http_server_accept(server, out_req) {
                \\  if (!globalThis.__sa_https[__sa_addr(server)]) return 1;
                \\  const h = __sa_alloc(8);
                \\  globalThis.__sa_http_sreq[__sa_addr(h)] = {
                \\    path: new globalThis.TextEncoder().encode("/stream"),
                \\    hdr_val: new globalThis.TextEncoder().encode("text/plain"),
                \\    body: new Uint8Array(0),
                \\  };
                \\  __sa_store_ptr(out_req, h);
                \\  return 0;
                \\}
                \\
            );
            return;
        }
        if (std.mem.eql(u8, fsig.name, "sa_http_server_req_get_path")) {
            try writer.writeAll(
                \\function sa_http_server_req_get_path(req, out_path, out_len) {
                \\  const r = globalThis.__sa_http_sreq[__sa_addr(req)];
                \\  if (!r) return 1;
                \\  const p = __sa_alloc(r.path.length);
                \\  __sa_u8.set(r.path, p);
                \\  __sa_store_ptr(out_path, p);
                \\  __sa_store_i64(out_len, r.path.length);
                \\  return 0;
                \\}
                \\
            );
            return;
        }
        if (std.mem.eql(u8, fsig.name, "sa_http_server_req_get_header")) {
            try writer.writeAll(
                \\function sa_http_server_req_get_header(req, key, key_len, out_val, out_len) {
                \\  const r = globalThis.__sa_http_sreq[__sa_addr(req)];
                \\  if (!r) return 1;
                \\  const p = __sa_alloc(r.hdr_val.length);
                \\  __sa_u8.set(r.hdr_val, p);
                \\  __sa_store_ptr(out_val, p);
                \\  __sa_store_i64(out_len, r.hdr_val.length);
                \\  return 0;
                \\}
                \\
            );
            return;
        }
        if (std.mem.eql(u8, fsig.name, "sa_http_server_req_get_body")) {
            try writer.writeAll(
                \\function sa_http_server_req_get_body(req, out_body, out_len) {
                \\  const r = globalThis.__sa_http_sreq[__sa_addr(req)];
                \\  if (!r) return 1;
                \\  __sa_store_ptr(out_body, 0);
                \\  __sa_store_i64(out_len, 0);
                \\  return 0;
                \\}
                \\
            );
            return;
        }
        if (std.mem.eql(u8, fsig.name, "sa_http_server_resp_stream_new")) {
            try writer.writeAll(
                \\function sa_http_server_resp_stream_new(req, status, out_resp) {
                \\  if (!globalThis.__sa_http_sreq[__sa_addr(req)]) return 1;
                \\  const h = __sa_alloc(8);
                \\  globalThis.__sa_http_sresp[__sa_addr(h)] = { status: __sa_num(status), chunks: [] };
                \\  __sa_store_ptr(out_resp, h);
                \\  return 0;
                \\}
                \\
            );
            return;
        }
        if (std.mem.eql(u8, fsig.name, "sa_http_server_resp_stream_write")) {
            try writer.writeAll(
                \\function sa_http_server_resp_stream_write(resp, body, body_len) {
                \\  const r = globalThis.__sa_http_sresp[__sa_addr(resp)];
                \\  if (!r) return 1;
                \\  const a = __sa_addr(body), n = __sa_num(body_len);
                \\  r.chunks.push(__sa_u8.slice(a, a + n));
                \\  return 0;
                \\}
                \\
            );
            return;
        }
        if (std.mem.eql(u8, fsig.name, "sa_http_server_resp_stream_flush")) {
            try writer.writeAll(
                \\function sa_http_server_resp_stream_flush(resp) {
                \\  return globalThis.__sa_http_sresp[__sa_addr(resp)] ? 0 : 1;
                \\}
                \\
            );
            return;
        }
        if (std.mem.eql(u8, fsig.name, "sa_http_server_resp_stream_end")) {
            try writer.writeAll(
                \\function sa_http_server_resp_stream_end(resp) {
                \\  return globalThis.__sa_http_sresp[__sa_addr(resp)] ? 0 : 1;
                \\}
                \\
            );
            return;
        }
        if (std.mem.eql(u8, fsig.name, "sa_http_server_resp_stream_free")) {
            try writer.writeAll("function sa_http_server_resp_stream_free(resp) { delete globalThis.__sa_http_sresp[__sa_addr(resp)]; return 0; }\n");
            return;
        }
        if (std.mem.eql(u8, fsig.name, "sa_http_server_req_free")) {
            try writer.writeAll("function sa_http_server_req_free(req) { delete globalThis.__sa_http_sreq[__sa_addr(req)]; return 0; }\n");
            return;
        }
        if (std.mem.eql(u8, fsig.name, "sa_http_server_free")) {
            try writer.writeAll("function sa_http_server_free(server) { delete globalThis.__sa_https[__sa_addr(server)]; return 0; }\n");
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
    // Frame scope for stack slots: push on entry, recycle on exit via
    // finally (covers early returns and panics). Indentation of the wrapped
    // body is irrelevant to JS semantics.
    try writer.writeAll("  __sa_fstack.push([]);\n  try {\n");
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
    try emitBodyAsPcMachine(writer, allocator, verified, fsig, task, const_addrs, fn_idx, js_opt, retbase);
    try writer.writeAll("  } finally { const __f = __sa_fstack.pop(); for (let __k = 0; __k < __f.length; __k++) __sa_free(__f[__k]); }\n}\n");
}

pub fn emitJsToString(allocator: std.mem.Allocator, verified: anytype, source_path: []const u8, size_bits: u16, js_opt: JsEmitOptions, npm_binds: *const std.StringHashMap([]const u8)) ![]u8 {
    var out = std.ArrayList(u8).init(allocator);
    errdefer out.deinit();
    const writer = out.writer();
    // Indirect-call function table: every vtable slot target, deduped in order.
    var fn_names = std.ArrayList([]const u8).init(allocator);
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
    // `#npm_bind` imports must precede the runtime header: ESM import
    // declarations live in the module prologue.
    const tasks = try collectFuncTasks(allocator, verified);
    defer allocator.free(tasks);
    const npm_imports = try collectNpmImports(allocator, verified, tasks, npm_binds);
    defer {
        for (npm_imports) |item| allocator.free(item.alias);
        allocator.free(npm_imports);
    }
    try writeRuntimeHeader(writer, js_opt, size_bits, npm_imports);
    try writer.print("// source: {s}\n", .{source_path});
    // Function table for call_indirect (boxed addresses, see vtable consts).
    try writer.writeAll("const __sa_ftable = [");
    for (fn_names.items, 0..) |fname, idx| {
        if (idx != 0) try writer.writeAll(", ");
        try jsFuncName(writer, fname);
    }
    try writer.writeAll("];\n");
    // Static consts: fixed linear-memory addresses below the bump region.
    var const_addrs = std.StringHashMap(usize).init(allocator);
    defer const_addrs.deinit();
    var const_cursor: usize = 4096;
    const bump_start: usize = 65536;
    for (verified.const_decls) |decl| {
        const len = constBytesLen(decl.value) catch 0;
        const aligned = std.mem.alignForward(usize, const_cursor, 8);
        if (decl.value == .vtable or len == 0) {
            // VTable slots hold boxed function addresses (u64 LE of
            // FN_BASE + table index) so call_indirect resolves at runtime.
            // Non-vtable empty consts reserve 8 zeroed bytes.
            const is_vt = decl.value == .vtable;
            const slots: usize = if (is_vt) decl.value.vtable.slots.len * 8 else 8;
            const a2 = std.mem.alignForward(usize, const_cursor, 8);
            if (a2 + slots > bump_start) return JsEmitError.Failed;
            try const_addrs.put(decl.name, a2);
            try writer.writeAll("const ");
            try writeConstSlot(writer, decl.name);
            try writer.print(" = {d}; // {s} ({d} bytes)\n", .{ a2, @tagName(decl.value), slots });
            if (is_vt) {
                var sidx: usize = 0;
                for (decl.value.vtable.slots) |vslot| {
                    const fidx = fn_idx.get(vslot.func_name) orelse return JsEmitError.UnknownFunction;
                    var le: [8]u8 = undefined;
                    std.mem.writeInt(u64, &le, 0x5341000000000000 + @as(u64, @intCast(fidx)), .little);
                    try writer.print("__sa_u8.set([", .{});
                    for (le, 0..) |b, bidx| {
                        if (bidx != 0) try writer.writeAll(",");
                        try writer.print("{d}", .{b});
                    }
                    try writer.print("], {d});\n", .{a2 + sidx * 8});
                    sidx += 1;
                }
            } else {
                try writer.print("__sa_u8.fill(0, {d}, {d});\n", .{ a2, a2 + slots });
            }
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
    // Non-extern function names: a same-module `@export` satisfies an
    // `@extern` declaration, so no trap stub is emitted for those (the
    // stub used to clobber the real body).
    var emitted = std.StringHashMap(void).init(allocator);
    defer emitted.deinit();
    // Must-return-base summary (increasing fixpoint from empty, hence sound
    // for recursion): alloc-class callees return fresh bases; param(i)-class
    // callees pass through one transparent (by_value/move) parameter.
    var retbase = RetBaseTable.init(allocator);
    defer retbase.deinit();
    {
        var iter: usize = 0;
        var stable = false;
        while (!stable and iter < 100) : (iter += 1) {
            stable = true;
            for (tasks) |task| {
                if (task.kind == .extern_decl) continue;
                const fsig = verified.function_sigs[task.fsig_index];
                if (retbase.contains(fsig.name)) continue;
                const ug = taskUsesGlobalRegIds(fsig, verified, task);
                var classified = false;
                {
                    var prov = try provSolveBody(allocator, verified, fsig, ug, task, &retbase, null);
                    defer prov.deinit();
                    if (try provAllReturnsProven(allocator, verified, fsig, ug, &prov, &retbase)) {
                        try retbase.put(fsig.name, .{ .alloc = {} });
                        classified = true;
                    }
                }
                if (!classified) {
                    for (fsig.param_ids, 0..) |pid, pi| {
                        const pseed = fsig.slotOf(pid) orelse continue;
                        var prov = try provSolveBody(allocator, verified, fsig, ug, task, &retbase, pseed);
                        defer prov.deinit();
                        if (try provAllReturnsProven(allocator, verified, fsig, ug, &prov, &retbase)) {
                            try retbase.put(fsig.name, .{ .param = pi });
                            classified = true;
                            break;
                        }
                    }
                }
                if (classified) stable = false;
            }
        }
    }
    var has_main = false;
    for (tasks) |task| {
        if (task.kind == .extern_decl) continue;
        try emitOneFunction(writer, allocator, verified, task, &const_addrs, &fn_idx, js_opt, &retbase);
        const fsig = verified.function_sigs[task.fsig_index];
        try emitted.put(fsig.name, {});
        if (std.mem.eql(u8, fsig.name, "main")) has_main = true;
    }
    // extern stubs (so calls don't ReferenceError; they trap with name).
    // `#npm_bind` externs get a marshaling wrapper instead, unless a
    // same-module `@export` already satisfies the declaration.
    for (tasks) |task| {
        if (task.kind != .extern_decl) continue;
        const fsig = verified.function_sigs[task.fsig_index];
        if (npmImportFor(npm_imports, fsig.name)) |npm_item| {
            if (emitted.contains(fsig.name)) continue;
            last_js_func = fsig.name;
            try emitNpmWrapper(writer, fsig, npm_item, js_opt);
            try emitted.put(fsig.name, {});
            continue;
        }
        if (!isKnownShim(fsig.name) and emitted.contains(fsig.name)) continue;
        try emitOneFunction(writer, allocator, verified, task, &const_addrs, &fn_idx, js_opt, &retbase);
    }
    // exports + main runner
    if (js_opt.format == .cjs) {
        try writer.writeAll("\nmodule.exports = { __sa_memory, __sa_view, __sa_u8, __sa_alloc, __sa_free, __sa_salloc");
        for (tasks) |task| {
            if (task.kind == .extern_decl) continue;
            const fsig = verified.function_sigs[task.fsig_index];
            try writer.writeAll(", ");
            try jsFuncName(writer, fsig.name);
        }
        try writer.writeAll(" };\n");
        if (has_main) try writer.writeAll("if (require.main === module) { main(); }\n");
    } else {
        try writer.writeAll("\nexport { __sa_memory, __sa_view, __sa_u8, __sa_alloc, __sa_free, __sa_salloc };\n");
        if (has_main) try writer.writeAll("if (typeof globalThis.process !== \"undefined\" && globalThis.process.argv && globalThis.process.argv[1] && /\\.(mjs|js|cjs)$/.test(globalThis.process.argv[1])) { try { main(); } catch (e) { globalThis.console.error(e); globalThis.process.exit(1); } }\n");
    }
    return out.toOwnedSlice();
}

pub fn emitJsToFile(allocator: std.mem.Allocator, verified: anytype, source_path: []const u8, size_bits: u16, js_opt: JsEmitOptions, npm_binds: *const std.StringHashMap([]const u8), path: []const u8) !void {
    const text = try emitJsToString(allocator, verified, source_path, size_bits, js_opt, npm_binds);
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
