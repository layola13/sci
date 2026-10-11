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

/// Names the JS emitter reserves for itself: register locals `r<slot>`
/// and the `__sa*` / `__SA*` runtime namespace. A user ident mapping onto
/// those would be shadowed by function-scope locals (e.g. a function named
/// `r1` is hidden by `let r1` inside every caller) or clobber the runtime.
fn isEmitterReserved(name: []const u8) bool {
    if (std.mem.startsWith(u8, name, "__sa") or std.mem.startsWith(u8, name, "__SA")) return true;
    if (name.len < 2 or name[0] != 'r') return false;
    for (name[1..]) |c| {
        if (!std.ascii.isDigit(c)) return false;
    }
    return true;
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
    if (isEmitterReserved(name)) try writer.writeAll("$");
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
        \\const __sa_ti8 = new Int8Array(__sa_memory);
        \\const __sa_ti16 = new Int16Array(__sa_memory);
        \\const __sa_tu16 = new Uint16Array(__sa_memory);
        \\const __sa_ti32 = new Int32Array(__sa_memory);
        \\const __sa_tu32 = new Uint32Array(__sa_memory);
        \\const __sa_tf32 = new Float32Array(__sa_memory);
        \\const __sa_tf64 = new Float64Array(__sa_memory);
        \\const __sa_tb64 = new BigInt64Array(__sa_memory);
        \\const __sa_use_dv64 = (typeof globalThis.Bun !== "undefined"); // JSC BigInt typed arrays are slow; DataView is ~3x faster there
        \\let __sa_brk = 65536; // bump allocator starts after reserved zero page region
        \\const __sa_live = new Set(); // live BIG heap bases (>32B, user pointers handed out by __sa_alloc)
        \\const __sa_fl = Object.create(null); // free-list buckets: aligned size -> stack of user pointers (big blocks only)
        \\const __sa_SMALL_MAX = 32; // headerless slab classes: 8/16/24/32
        \\const __sa_SLAB = 4096; // bytes per slab chunk carved from linear memory
        \\const __sa_slab_by_page = new Map(); // (chunkBase >>> 12) -> slab record
        \\const __sa_slab_by_class = { 8: [], 16: [], 24: [], 32: [] }; // per-class slab chunks
        \\const __sa_slab_hint = { 8: null, 16: null, 24: null, 32: null }; // slab known to have a free slot
        \\function __sa_slab_new(sc) {
        \\  __sa_brk = (__sa_brk + (__sa_SLAB - 1)) & ~(__sa_SLAB - 1);
        \\  const base = __sa_brk;
        \\  __sa_brk += __sa_SLAB;
        \\  if (__sa_brk >= __sa_memory.byteLength) __sa_trap("out of memory (slab)");
        \\  __sa_u8.fill(0, base, base + __sa_SLAB);
        \\  const count = (__sa_SLAB / sc) | 0;
        \\  const slab = { base, sc, count, next: 0, free: new Int32Array(count), top: 0, live: new Uint8Array(count) };
        \\  __sa_slab_by_page.set(base >>> 12, slab);
        \\  __sa_slab_by_class[sc].push(slab);
        \\  __sa_slab_hint[sc] = slab;
        \\  return slab;
        \\}
        \\function __sa_slab_take(slab) {
        \\  let idx;
        \\  if (slab.top > 0) idx = slab.free[--slab.top];
        \\  else idx = slab.next++;
        \\  slab.live[idx] = 1;
        \\  if (slab.top === 0 && slab.next >= slab.count && __sa_slab_hint[slab.sc] === slab) __sa_slab_hint[slab.sc] = null;
        \\  const ptr = slab.base + idx * slab.sc;
        \\  __sa_u8.fill(0, ptr, ptr + slab.sc);
        \\  return ptr | 0;
        \\}
        \\function __sa_slab_alloc(sc) {
        \\  let slab = __sa_slab_hint[sc];
        \\  if (!slab || (slab.top === 0 && slab.next >= slab.count)) {
        \\    const list = __sa_slab_by_class[sc];
        \\    slab = null;
        \\    for (let i = list.length - 1; i >= 0; i--) { const c = list[i]; if (c.top > 0 || c.next < c.count) { slab = c; break; } }
        \\    if (!slab) slab = __sa_slab_new(sc);
        \\    __sa_slab_hint[sc] = slab;
        \\  }
        \\  return __sa_slab_take(slab);
        \\}
        \\function __sa_slab_release(ptr) {
        \\  // Recycle one live slab slot; foreign, misaligned, const or
        \\  // already-free pointers report false (all stay silent no-ops).
        \\  const p = __sa_addr(ptr);
        \\  const slab = __sa_slab_by_page.get(p >>> 12);
        \\  if (!slab) return false;
        \\  const off = p - slab.base;
        \\  const idx = (off / slab.sc) | 0;
        \\  if (idx < 0 || idx >= slab.count || slab.base + idx * slab.sc !== p) return false;
        \\  if (!slab.live[idx]) return false;
        \\  slab.live[idx] = 0;
        \\  slab.free[slab.top++] = idx;
        \\  __sa_slab_hint[slab.sc] = slab;
        \\  return true;
        \\}
        \\function __sa_mem_used() { return (__sa_brk - 65536) | 0; } // linear bytes consumed (slab metadata excluded)
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
        \\  if (size <= __sa_SMALL_MAX) return __sa_slab_alloc(size); // headerless, no live Set
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
        \\  // Slab members (<=32B) recycle via bitset; big bases via the live
        \\  // Set + header. BigInt pointers are normalized to 32-bit addresses
        \\  // first so 64-bit-typed bases stay freeable; interior pointers,
        \\  // consts and unknown addresses remain no-ops.
        \\  if (__sa_slab_release(ptr)) return 0;
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
        \\  // via __sa_sfree (mirrors stack-slot lifetime; the interpreter
        \\  // never frees these mid-frame either). Small sizes ride the
        \\  // headerless slab (no __sa_live); big sizes share the free-list
        \\  // pool with __sa_alloc (every big block keeps its 8-byte header).
        \\  // Either way the live Set is untouched, so frame temporaries skip
        \\  // both Set add/delete on the hot path. Returned blocks are
        \\  // recycled on frame pop.
        \\  size = __sa_align((__sa_num(size) | 0), 8);
        \\  if (!__sa_fstack.length) return __sa_alloc(size);
        \\  let ptr;
        \\  if (size <= __sa_SMALL_MAX) { ptr = __sa_slab_alloc(size); }
        \\  else {
        \\  const bucket = __sa_fl[size];
        \\  if (bucket && bucket.length) { ptr = bucket.pop(); __sa_u8.fill(0, ptr, ptr + size); }
        \\  else {
        \\    const base = __sa_brk;
        \\    __sa_brk += (size + 8);
        \\    if (__sa_brk >= __sa_memory.byteLength) __sa_trap("out of memory (bump)");
        \\    __sa_u8.fill(0, base, base + size + 8);
        \\    __sa_view.setUint32(base, size, true);
        \\    ptr = (base + 8);
        \\  }
        \\  }
        \\  __sa_fstack[__sa_fstack.length - 1].push(ptr | 0);
        \\  return ptr | 0;
        \\}
        \\function __sa_sfree(ptr) {
        \\  // Frame-pop recycle for __sa_salloc blocks: slab members via
        \\  // bitset, big blocks via header size. No __sa_live membership
        \\  // test needed (salloc never registers).
        \\  if (__sa_slab_release(ptr)) return 0;
        \\  const p = __sa_addr(ptr);
        \\  const size = __sa_view.getUint32((p - 8), true);
        \\  (__sa_fl[size] || (__sa_fl[size] = [])).push(p);
        \\  return 0;
        \\}
        \\function __sa_load_i8(addr) { return __sa_ti8[__sa_addr(addr)]; }
        \\function __sa_load_u8(addr) { return __sa_u8[__sa_addr(addr)]; }
        \\function __sa_load_i16(addr) { const a = __sa_addr(addr); return ((a & 1) === 0) ? __sa_ti16[a >> 1] : __sa_view.getInt16(a, true); }
        \\function __sa_load_u16(addr) { const a = __sa_addr(addr); return ((a & 1) === 0) ? __sa_tu16[a >> 1] : __sa_view.getUint16(a, true); }
        \\function __sa_load_i32(addr) { const a = __sa_addr(addr); return ((a & 3) === 0) ? __sa_ti32[a >> 2] : __sa_view.getInt32(a, true); }
        \\function __sa_load_u32(addr) { const a = __sa_addr(addr); return ((a & 3) === 0) ? __sa_tu32[a >> 2] : __sa_view.getUint32(a, true); }
        \\function __sa_load_f32(addr) { const a = __sa_addr(addr); return ((a & 3) === 0) ? __sa_tf32[a >> 2] : __sa_view.getFloat32(a, true); }
        \\function __sa_load_f64(addr) { const a = __sa_addr(addr); return ((a & 7) === 0) ? __sa_tf64[a >> 3] : __sa_view.getFloat64(a, true); }
        \\function __sa_store_i8(addr, v) { __sa_ti8[__sa_addr(addr)] = __sa_narrow(v, 8, true); }
        \\function __sa_store_u8(addr, v) { __sa_u8[__sa_addr(addr)] = __sa_narrow(v, 8, false); }
        \\function __sa_store_i16(addr, v) { const a = __sa_addr(addr); const n = __sa_narrow(v, 16, true); if ((a & 1) === 0) __sa_ti16[a >> 1] = n; else __sa_view.setInt16(a, n, true); }
        \\function __sa_store_u16(addr, v) { const a = __sa_addr(addr); const n = __sa_narrow(v, 16, false); if ((a & 1) === 0) __sa_tu16[a >> 1] = n; else __sa_view.setUint16(a, n, true); }
        \\function __sa_store_i32(addr, v) { const a = __sa_addr(addr); const n = __sa_narrow(v, 32, true); if ((a & 3) === 0) __sa_ti32[a >> 2] = n; else __sa_view.setInt32(a, n, true); }
        \\function __sa_store_u32(addr, v) { const a = __sa_addr(addr); const n = __sa_narrow(v, 32, false); if ((a & 3) === 0) __sa_tu32[a >> 2] = n; else __sa_view.setUint32(a, n, true); }
        \\function __sa_store_f32(addr, v) { const a = __sa_addr(addr); const n = +v; if ((a & 3) === 0) __sa_tf32[a >> 2] = n; else __sa_view.setFloat32(a, n, true); }
        \\function __sa_store_f64(addr, v) { const a = __sa_addr(addr); const n = +v; if ((a & 7) === 0) __sa_tf64[a >> 3] = n; else __sa_view.setFloat64(a, n, true); }
        \\function __sa_load_i64(addr) { const a = __sa_addr(addr); if (__sa_use_dv64) return __sa_view.getBigInt64(a, true); return ((a & 7) === 0) ? __sa_tb64[a >> 3] : __sa_view.getBigInt64(a, true); }
        \\function __sa_store_i64(addr, v) { const a = __sa_addr(addr); const n = BigInt.asIntN(64, BigInt(v)); if (__sa_use_dv64) { __sa_view.setBigInt64(a, n, true); return; } if ((a & 7) === 0) __sa_tb64[a >> 3] = n; else __sa_view.setBigInt64(a, n, true); }
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
        \\function __sa_fnum(v) { return (typeof v === "bigint") ? Number(v) : (+v); }
        \\function __sa_fadd(a, b) { return (__sa_fnum(a) + __sa_fnum(b)); }
        \\function __sa_fsub(a, b) { return (__sa_fnum(a) - __sa_fnum(b)); }
        \\function __sa_fmul(a, b) { return (__sa_fnum(a) * __sa_fnum(b)); }
        \\function __sa_fdiv(a, b) { return (__sa_fnum(a) / __sa_fnum(b)); }
        \\function __sa_fneg(a) { return (-__sa_fnum(a)); }
        \\function __sa_feq(a, b) { return ((__sa_fnum(a) === __sa_fnum(b)) ? 1 : 0); }
        \\function __sa_fne(a, b) { return ((__sa_fnum(a) !== __sa_fnum(b)) ? 1 : 0); }
        \\function __sa_flt(a, b) { return ((__sa_fnum(a) < __sa_fnum(b)) ? 1 : 0); }
        \\function __sa_fle(a, b) { return ((__sa_fnum(a) <= __sa_fnum(b)) ? 1 : 0); }
        \\function __sa_fgt(a, b) { return ((__sa_fnum(a) > __sa_fnum(b)) ? 1 : 0); }
        \\function __sa_fge(a, b) { return ((__sa_fnum(a) >= __sa_fnum(b)) ? 1 : 0); }
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
        \\function __sa_divfloor(a, b) {
        \\  // Floored BigInt division (Zig @divFloor semantics).
        \\  const q = a / b, r = a % b;
        \\  if ((r !== 0n) && ((r < 0n) !== (b < 0n))) return q - 1n;
        \\  return q;
        \\}
        \\function __sa_modfloor(a, b) {
        \\  // Floored BigInt modulo (Zig @mod semantics; b > 0 in our uses).
        \\  const r = a % b;
        \\  return (r < 0n) ? r + (b < 0n ? -b : b) : r;
        \\}
        \\function __sa_civil(ms) {
        \\  // Howard Hinnant civil_from_days over unix millis (mirrors
        \\  // src/runtime/sa_std.zig civilParts). Returns
        \\  // [year, month1, day, hour, min, sec, milli, days] as BigInt.
        \\  const m = (typeof ms === "bigint") ? BigInt.asIntN(64, ms) : BigInt(Math.trunc(+ms));
        \\  const DAY = 86400000n;
        \\  const days = __sa_divfloor(m, DAY);
        \\  const dm = __sa_modfloor(m, DAY);
        \\  const z = days + 719468n;
        \\  const era = (z >= 0n) ? __sa_divfloor(z, 146097n) : __sa_divfloor(z - 146096n, 146097n);
        \\  const doe = z - era * 146097n;
        \\  const yoe = __sa_divfloor(doe - __sa_divfloor(doe, 1460n) + __sa_divfloor(doe, 36524n) - __sa_divfloor(doe, 146096n), 365n);
        \\  const y = yoe + era * 400n;
        \\  const doy = doe - (365n * yoe + __sa_divfloor(yoe, 4n) - __sa_divfloor(yoe, 100n));
        \\  const mp = __sa_divfloor(5n * doy + 2n, 153n);
        \\  const month = (mp < 10n) ? mp + 3n : mp - 9n;
        \\  return [(month <= 2n) ? y + 1n : y, month,
        \\    doy - __sa_divfloor(153n * mp + 2n, 5n) + 1n,
        \\    __sa_divfloor(dm, 3600000n),
        \\    __sa_divfloor(__sa_modfloor(dm, 3600000n), 60000n),
        \\    __sa_divfloor(__sa_modfloor(dm, 60000n), 1000n),
        \\    __sa_modfloor(dm, 1000n), days];
        \\}
        \\const __sa_buffers = new Map();
        \\let __sa_bufnext = 1;
        \\const __sa_regexes = new Map();
        \\let __sa_regexnext = 1;
        \\const __sa_regexmatches = new Map();
        \\let __sa_regexmatchnext = 1;
        \\const __sa_modstate = new Map();
        \\const __sa_jsonnodes = new Map();
        \\let __sa_jsonnext = 1;
        \\const __sa_jsonwriters = new Map();
        \\let __sa_jsonwriternext = 1;
        \\const __sa_jsonbufs = new Map();
        \\let __sa_jsonbufnext = 1;
        \\function __sa_json_quote(bytes, esc_uni) {
        \\  const s = new globalThis.TextDecoder().decode(bytes);
        \\  let o = '"';
        \\  for (const ch of s) {
        \\    const c = ch.codePointAt(0);
        \\    if (c === 34) o += '\\"';
        \\    else if (c === 92) o += '\\\\';
        \\    else if (c === 8) o += '\\b';
        \\    else if (c === 9) o += '\\t';
        \\    else if (c === 10) o += '\\n';
        \\    else if (c === 12) o += '\\f';
        \\    else if (c === 13) o += '\\r';
        \\    else if (c < 0x20) o += '\\u00' + c.toString(16).padStart(2, '0');
        \\    else if (esc_uni && c > 0x7f) {
        \\      if (c > 0xffff) {
        \\        const v = c - 0x10000;
        \\        o += '\\u' + (0xd800 + (v >> 10)).toString(16).padStart(4, '0');
        \\        o += '\\u' + (0xdc00 + (v & 0x3ff)).toString(16).padStart(4, '0');
        \\      } else o += '\\u' + c.toString(16).padStart(4, '0');
        \\    }
        \\    else o += ch;
        \\  }
        \\  return o + '"';
        \\}
        \\function __sa_json_f64_str(x) {
        \\  // Zig std.json shortest-scientific float format (probed native:
        \\  // 7->7e0, 0.5->5e-1, 1e21->1e21, NaN->"nan", Inf->inf, -0->0e0).
        \\  const v = (typeof x === "bigint") ? Number(x) : (+x);
        \\  if (Number.isNaN(v)) return '"nan"';
        \\  if (v === Infinity) return 'inf';
        \\  if (v === -Infinity) return '-inf';
        \\  const a = (v < 0) ? -v : v;
        \\  const e = a.toExponential().replace("e+", "e");
        \\  return ((v < 0) ? "-" : "") + e;
        \\}
        \\function __sa_jw_begin(w, open) {
        \\  if (w.result !== null) return 2;
        \\  if (w.root_done && w.stack.length === 0) return 1;
        \\  if (w.stack.length !== 0) {
        \\    const top = w.stack[w.stack.length - 1];
        \\    if (top.t === 1) {
        \\      if (!top.first) w.parts.push(',');
        \\      top.first = false;
        \\    }
        \\    // Object parents: the field key (with its comma) was emitted
        \\    // by object_field/field_* just before; push directly.
        \\  }
        \\  w.parts.push(open);
        \\  w.stack.push({ t: open === '{' ? 0 : 1, first: true });
        \\  return 0;
        \\}
        \\function __sa_jw_scalar(w, text) {
        \\  if (w.result !== null) return 2;
        \\  if (w.stack.length !== 0) {
        \\    const top = w.stack[w.stack.length - 1];
        \\    if (top.t !== 1) return 1;
        \\    if (!top.first) w.parts.push(',');
        \\    top.first = false;
        \\  } else {
        \\    if (w.root_done) return 1;
        \\    w.root_done = true;
        \\  }
        \\  w.parts.push(text);
        \\  return 0;
        \\}
        \\function __sa_jw_field(w, key_bytes) {
        \\  if (w.result !== null) return 2;
        \\  if (w.stack.length === 0) return 1;
        \\  const top = w.stack[w.stack.length - 1];
        \\  if (top.t !== 0) return 1;
        \\  if (!top.first) w.parts.push(',');
        \\  top.first = false;
        \\  w.parts.push(__sa_json_quote(key_bytes, w.esc_uni));
        \\  w.parts.push(':');
        \\  return 0;
        \\}
        \\function __sa_jw_end(w, close) {
        \\  if (w.result !== null) return 2;
        \\  if (w.stack.length === 0) return 1;
        \\  const top = w.stack.pop();
        \\  if ((close === '}' && top.t !== 0) || (close === ']' && top.t !== 1)) return 1;
        \\  w.parts.push(close);
        \\  if (w.stack.length === 0) w.root_done = true;
        \\  return 0;
        \\}
        \\function __sa_buf_open(bytes) {
        \\  // Owned byte buffer (mirrors openOwnedBuffer): handle is a u64.
        \\  const h = __sa_bufnext++;
        \\  __sa_buffers.set(h, bytes.slice());
        \\  return BigInt(h);
        \\}
        \\function __sa_buf_get(handle) {
        \\  const b = __sa_buffers.get(__sa_num(handle));
        \\  return (b !== undefined) ? b : null;
        \\}
        \\function __sa_mem_bytes(ptr, len) {
        \\  // Copy of a linear-memory range as Uint8Array.
        \\  const a = __sa_addr(ptr);
        \\  let n = __sa_num(len);
        \\  if (!(n > 0)) return new Uint8Array(0);
        \\  if (a < 0) return new Uint8Array(0);
        \\  return __sa_u8.slice(a, a + n);
        \\}
        \\function __sa_utf8_dec(bytes, idx) {
        \\  // Strict UTF-8 scalar decode (mirrors utf8ScalarAt): returns
        \\  // [scalar, width] or null (overlongs/surrogates rejected).
        \\  if (idx >= bytes.length) return null;
        \\  const b0 = bytes[idx];
        \\  if (b0 < 0x80) return [b0, 1];
        \\  let w = 0;
        \\  if (b0 >= 0xc2 && b0 <= 0xdf) w = 2;
        \\  else if (b0 >= 0xe0 && b0 <= 0xef) w = 3;
        \\  else if (b0 >= 0xf0 && b0 <= 0xf4) w = 4;
        \\  else return null;
        \\  if (idx + w > bytes.length) return null;
        \\  const b1 = bytes[idx + 1];
        \\  if (b1 < 0x80 || b1 > 0xbf) return null;
        \\  if (w === 2) return [((b0 & 0x1f) << 6) | (b1 & 0x3f), 2];
        \\  const b2 = bytes[idx + 2];
        \\  if (b2 < 0x80 || b2 > 0xbf) return null;
        \\  if (w === 3) {
        \\    if (b0 === 0xe0 && b1 < 0xa0) return null;
        \\    if (b0 === 0xed && b1 >= 0xa0) return null;
        \\    return [((b0 & 0x0f) << 12) | ((b1 & 0x3f) << 6) | (b2 & 0x3f), 3];
        \\  }
        \\  const b3 = bytes[idx + 3];
        \\  if (b3 < 0x80 || b3 > 0xbf) return null;
        \\  if (b0 === 0xf0 && b1 < 0x90) return null;
        \\  if (b0 === 0xf4 && b1 >= 0x90) return null;
        \\  return [((b0 & 0x07) << 18) | ((b1 & 0x3f) << 12) | ((b2 & 0x3f) << 6) | (b3 & 0x3f), 4];
        \\}
        \\function __sa_is_ws(b) { return b === 32 || b === 9 || b === 10 || b === 13 || b === 11 || b === 12; }
        \\function __sa_tou(v) {
        \\  // u64 wrapping conversion for index/count params (mirrors Zig
        \\  // u64 param passing: negative Numbers wrap huge, then callers
        \\  // clamp with Math.min against the real length).
        \\  const n = (typeof v === "bigint") ? v : BigInt(Math.trunc(+v));
        \\  return Number(BigInt.asUintN(64, n));
        \\}
        \\function __sa_regex_group(match, group_idx) {
        \\  const r = __sa_regexmatches.get(__sa_num(match));
        \\  if (r === undefined) return null;
        \\  const i = __sa_num(group_idx);
        \\  if (!(i >= 0) || i >= r.groups.length) return null;
        \\  const g = r.groups[i];
        \\  if (g[0] < 0 || g[1] < 0) return null;
        \\  return { rec: r, so: g[0], eo: g[1] };
        \\}
        \\function __sa_json_kind_of(v) {
        \\  if (v === null) return 0;
        \\  if (typeof v === "boolean") return 1;
        \\  if (typeof v === "number") return Number.isInteger(v) ? 2 : 3;
        \\  if (typeof v === "string") return 5;
        \\  if (Array.isArray(v)) return 6;
        \\  if (typeof v === "object") return 7;
        \\  return 4294967295;
        \\}
        \\function __sa_json_i64_of(v) {
        \\  if (typeof v !== "number" || !Number.isInteger(v)) return null;
        \\  if (v > 9223372036854775807 || v < -9223372036854775808) return null;
        \\  return BigInt.asIntN(64, BigInt(v));
        \\}
        \\function __sa_json_f64_of(v) {
        \\  if (typeof v !== "number" || !Number.isFinite(v)) return null;
        \\  return v;
        \\}
        \\function __sa_node_builtin(mod) {
        \\  try {
        \\    const p = globalThis.process;
        \\    if (p && p.getBuiltinModule) return p.getBuiltinModule(mod);
        \\  } catch (e) {}
        \\  return null;
        \\}
        \\function __sa_node_emit(out_ptr, out_len, bytes) {
        \\  const p = __sa_alloc(bytes.length);
        \\  __sa_u8.set(bytes, p);
        \\  __sa_store_i64(out_ptr, p);
        \\  __sa_store_i64(out_len, bytes.length);
        \\  return 0;
        \\}
        \\function __sa_fmt_f64_str(v, prec) {
        \\  // Zig std.fmt.formatFloat decimal mode with precision p (mirrors
        \\  // sa_fmt_f64_into). Returns the text or null on invalid precision.
        \\  const p = __sa_num(prec);
        \\  if (!Number.isInteger(p) || p < 0 || p > 100) return null;
        \\  const x = +v;
        \\  if (Number.isNaN(x)) return "nan";
        \\  if (x === Infinity) return "inf";
        \\  if (x === -Infinity) return "-inf";
        \\  const neg = (x < 0) || (x === 0 && (1 / x) === -Infinity);
        \\  const a = Math.abs(x);
        \\  let s;
        \\  if (a >= 1e21) {
        \\    // Plain decimal notation (Zig never exponentiates); doubles this
        \\    // large are integral so the fraction is all zeros.
        \\    const e = a.toString();
        \\    const m = /^(\\d)(?:\\.(\\d+))?e\\+(\\d+)$/.exec(e);
        \\    if (!m) return (neg ? "-" : "") + e;
        \\    const exp = parseInt(m[3], 10);
        \\    let digits = m[1] + (m[2] || "");
        \\    while (digits.length < exp + 1) digits += "0";
        \\    s = digits.slice(0, exp + 1) + "." + "0".repeat(p);
        \\  } else {
        \\    s = a.toFixed(p);
        \\  }
        \\  return (neg ? "-" : "") + s;
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

/// Peephole predicate: address offset operand is a constant zero in any
/// integer domain (x+0 == x in both Number and BigInt semantics), so the
/// `__sa_ptr_add` wrapper can be skipped on the hot path.
fn offIsZero(op: inst.Operand) bool {
    return switch (op) {
        .imm_int => |v| v == 0,
        .imm_i64 => |v| v == 0,
        .imm_u64 => |v| v == 0,
        else => false,
    };
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
        //
        // Exception: immediates whose magnitude already fits the 32-bit
        // Number domain are emitted as plain digits. The runtime helpers
        // dispatch on typeof, so `__sa_add(u64Value, 5)` still promotes 5 to
        // BigInt whenever the other operand is a BigInt; but when the whole
        // expression is 32-bit (the common loop case), keeping the literal as
        // a Number avoids a megamorphic BigInt/Number mix and lets V8/JSC
        // inline the arithmetic. Without this, every `i < 4096` saturated to
        // the BigInt path (observed: __sa_ult/__sa_add/__sa_BU hot in V8 CPU
        // profiles) and cost ~165x the engine's Number-domain floor.
        .imm_i64 => |v| if (v >= std.math.minInt(i32) and v <= std.math.maxInt(i32))
            try writer.print("{d}", .{v})
        else
            try writer.print("{d}n", .{v}),
        .imm_u64 => |v| if (v <= std.math.maxInt(u32))
            try writer.print("{d}", .{v})
        else
            try writer.print("{d}n", .{v}),
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
                // Mirrors the emitter: bare sitofp/uitofp default to f64.
                var tgt = tagToPrim(base.operands[2].ty);
                if ((opcode == .sitofp or opcode == .uitofp) and tgt != .f32 and tgt != .f64) {
                    tgt = .f64;
                }
                if (packWidth(tgt)) |w| {
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

/// Slot of a textual value (`store` keeps its value operand as `.text`;
/// see flattener.zig). Mirrors resolveTextToJs name resolution exactly
/// (global id -> slotOf, ignoring use_global) so escape kills apply to
/// textual values too; immediates never name slots.
fn provTextSlot(symbols: anytype, fsig: sig.FunctionSig, use_global: bool, text: []const u8) ?u32 {
    _ = use_global;
    var t = std.mem.trim(u8, text, " \t");
    if (t.len == 0) return null;
    if (t[0] == '&' or t[0] == '*' or t[0] == '^') t = std.mem.trim(u8, t[1..], " \t");
    if (std.mem.lastIndexOf(u8, t, " as ")) |idx| t = std.mem.trim(u8, t[0..idx], " \t\r");
    if (t.len == 0) return null;
    if (std.fmt.parseInt(i64, t, 10)) |_| return null else |_| {}
    if (std.fmt.parseFloat(f64, t)) |_| return null else |_| {}
    const id = symbols.findId(t) orelse return null;
    return fsig.slotOf(id);
}

/// Forget the stored value's slot on `.store` (any operand shape).
fn provKillStoreValue(bases: *BaseSet, symbols: anytype, fsig: sig.FunctionSig, use_global: bool, op: inst.Operand) void {
    switch (op) {
        .reg, .symbol => provKill(bases, fsig, use_global, op),
        .text, .native_text => |t| {
            if (provTextSlot(symbols, fsig, use_global, t)) |slot| _ = bases.remove(slot);
        },
        else => {},
    }
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
        try writer.print("  r{d} = ", .{slot});
    } else {
        try writer.writeAll("  ");
    }
    // Move-prefix arguments are consumed. Bare (by_value) arguments
    // may be retained by the callee: forget those slots too (leak
    // beats use-after-free; mirrors the store-escape rule).
    // Borrow (&) / raw (*) args are only read through: kept.
    // Runs for dest-less calls too (push_word has no dest).
    for (parsed.args) |arg| {
        if (arg.prefix == .move or arg.prefix == .by_value) {
            if (provArgSlot(symbols, fsig, arg.text)) |aslot| _ = bases.remove(aslot);
        }
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
        try writer.print("  r{d} = ", .{slot});
    } else {
        try writer.writeAll("  ");
    }
    // Move-prefix arguments are consumed. Bare (by_value) arguments
    // may be retained by the callee: forget those slots too (leak
    // beats use-after-free; mirrors the store-escape rule).
    // Borrow (&) / raw (*) args are only read through: kept.
    // Runs for dest-less calls too.
    for (parsed.args) |arg| {
        if (arg.prefix == .move or arg.prefix == .by_value) {
            if (provArgSlot(symbols, fsig, arg.text)) |aslot| _ = bases.remove(aslot);
        }
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
                // Tsgosa emits bare `sitofp X` / `uitofp X` (Number()
                // conversions) without `as f64`; the flattener defaults the
                // target to i32, which no float conversion accepts. Native
                // coerces to f64 at the consuming call site, so default the
                // target to f64 here for identical observable behavior.
                var tgt = tagToPrim(base.operands[2].ty);
                if ((opcode == .sitofp or opcode == .uitofp) and tgt != .f32 and tgt != .f64) {
                    tgt = .f64;
                }
                try writer.print("  r{d} = ", .{slot});
                try emitCvtExpr(writer, symbols, fsig, use_global, const_addrs, fn_idx, opcode, tgt, base.operands[1], widths);
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
            // Peephole: ptr_add(x, 0) is the identity; skipping the helper
            // also skips BigInt materialization for 64-bit zero offsets on
            // the hot path (correct: x+0 == x in both domains).
            if (offIsZero(base.operands[2])) {
                try writer.print("  r{d} = ", .{slot});
                try resolveValueToJs(writer, symbols, fsig, use_global, const_addrs, fn_idx, base.operands[1]);
                try writer.writeAll(";\n");
            } else {
                try writer.print("  r{d} = __sa_ptr_add(", .{slot});
                try resolveValueToJs(writer, symbols, fsig, use_global, const_addrs, fn_idx, base.operands[1]);
                try writer.writeAll(", ");
                try resolveValueToJs(writer, symbols, fsig, use_global, const_addrs, fn_idx, base.operands[2]);
                try writer.writeAll(");\n");
            }
        },
        .load, .take, .atomic_load => {
            // NOTE: atomic ordering is ignored (single-threaded JS runtime).
            const slot = try dstSlot(fsig, use_global, base.operands[0]);
            // Loaded data is never an owned base.
            _ = bases.remove(slot);
            const ty = memPrimType(base);
            const load_fn = memLoadFn(ty);
            if (offIsZero(base.operands[2])) {
                try writer.print("  r{d} = {s}(", .{ slot, load_fn });
                try resolveValueToJs(writer, symbols, fsig, use_global, const_addrs, fn_idx, base.operands[1]);
                try writer.writeAll(");\n");
            } else {
                try writer.print("  r{d} = {s}(__sa_ptr_add(", .{ slot, load_fn });
                try resolveValueToJs(writer, symbols, fsig, use_global, const_addrs, fn_idx, base.operands[1]);
                try writer.writeAll(", ");
                try resolveValueToJs(writer, symbols, fsig, use_global, const_addrs, fn_idx, base.operands[2]);
                try writer.writeAll("));\n");
            }
        },
        .store, .atomic_store => {
            // NOTE: atomic ordering is ignored (single-threaded JS runtime).
            // Escape: the stored value may be an owned base aliased into
            // memory; forget the source slot so a later `release` stays a
            // no-op (mirrors provTransfer; see the array-literal pattern).
            provKillStoreValue(bases, symbols, fsig, use_global, base.operands[2]);
            const ty = memPrimType(base);
            const store_fn = memStoreFn(ty);
            if (offIsZero(base.operands[1])) {
                try writer.print("  {s}(", .{store_fn});
                try resolveValueToJs(writer, symbols, fsig, use_global, const_addrs, fn_idx, base.operands[0]);
                try writer.writeAll(", ");
                try resolveValueToJs(writer, symbols, fsig, use_global, const_addrs, fn_idx, base.operands[2]);
                try writer.writeAll(");\n");
            } else {
                try writer.print("  {s}(__sa_ptr_add(", .{store_fn});
                try resolveValueToJs(writer, symbols, fsig, use_global, const_addrs, fn_idx, base.operands[0]);
                try writer.writeAll(", ");
                try resolveValueToJs(writer, symbols, fsig, use_global, const_addrs, fn_idx, base.operands[1]);
                try writer.writeAll("), ");
                try resolveValueToJs(writer, symbols, fsig, use_global, const_addrs, fn_idx, base.operands[2]);
                try writer.writeAll(");\n");
            }
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
            .store, .atomic_store => {
                // Storing an owned base into memory escapes it (struct
                // fields, array slots, spills): the source register no
                // longer solely owns the block, so a later `release` of
                // the source must stay a no-op. Tsgosa emits this for
                // every array literal (`store s+0, p as ptr` ... `!p`);
                // freeing there corrupts the stored copy on free-list
                // reuse (native malloc survives by luck: LIFO + no
                // zeroing). Leaking instead is always observably safe.
                // The value operand is `.text`-shaped (see flattener),
                // so resolve it through the symbol table.
                provKillStoreValue(out_set, symbols, fsig, use_global, base.operands[2]);
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
                // Move-prefix arguments are consumed by the call. Bare
                // (by_value) arguments may be retained (mirrors emission).
                for (parsed.args) |arg| {
                    if (arg.prefix == .move or arg.prefix == .by_value) {
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
    if (std.mem.eql(u8, name, "sa_fmt_i64_into")) return true;
    if (std.mem.eql(u8, name, "sa_fmt_u64_into")) return true;
    if (std.mem.eql(u8, name, "sa_fmt_bool_into")) return true;
    if (std.mem.eql(u8, name, "sa_fmt_bytes_into")) return true;
    if (std.mem.eql(u8, name, "sa_time_unix_ms")) return true;
    if (std.mem.eql(u8, name, "sa_time_unix_s")) return true;
    if (std.mem.eql(u8, name, "sa_time_unix_ns")) return true;
    if (std.mem.eql(u8, name, "sa_time_instant_ns")) return true;
    if (std.mem.eql(u8, name, "sa_time_sleep_ns")) return true;
    if (std.mem.eql(u8, name, "sa_time_sleep_ms")) return true;
    if (std.mem.eql(u8, name, "sa_time_get_full_year")) return true;
    if (std.mem.eql(u8, name, "sa_time_get_month")) return true;
    if (std.mem.eql(u8, name, "sa_time_get_date")) return true;
    if (std.mem.eql(u8, name, "sa_time_get_hours")) return true;
    if (std.mem.eql(u8, name, "sa_time_get_minutes")) return true;
    if (std.mem.eql(u8, name, "sa_time_get_seconds")) return true;
    if (std.mem.eql(u8, name, "sa_time_get_milliseconds")) return true;
    if (std.mem.eql(u8, name, "sa_time_get_day")) return true;
    if (std.mem.eql(u8, name, "sa_time_parse_iso")) return true;
    if (std.mem.eql(u8, name, "sa_fmt_i64")) return true;
    if (std.mem.eql(u8, name, "sa_fmt_u64")) return true;
    if (std.mem.eql(u8, name, "sa_fmt_f64")) return true;
    if (std.mem.eql(u8, name, "sa_fmt_bool")) return true;
    if (std.mem.eql(u8, name, "sa_fmt_bytes")) return true;
    if (std.mem.eql(u8, name, "sa_fmt_f64_into")) return true;
    if (std.mem.eql(u8, name, "sa_fmt_buffer_data")) return true;
    if (std.mem.eql(u8, name, "sa_fmt_buffer_len")) return true;
    if (std.mem.eql(u8, name, "sa_fmt_buffer_free")) return true;
    if (std.mem.eql(u8, name, "sa_string_concat")) return true;
    if (std.mem.eql(u8, name, "sa_string_from_char_code")) return true;
    if (std.mem.eql(u8, name, "sa_string_index_of")) return true;
    if (std.mem.eql(u8, name, "sa_string_last_index_of")) return true;
    if (std.mem.eql(u8, name, "sa_string_starts_with")) return true;
    if (std.mem.eql(u8, name, "sa_string_ends_with")) return true;
    if (std.mem.eql(u8, name, "sa_string_to_lower_ascii")) return true;
    if (std.mem.eql(u8, name, "sa_string_to_upper_ascii")) return true;
    if (std.mem.eql(u8, name, "sa_parse_float")) return true;
    if (std.mem.eql(u8, name, "sa_string_repeat")) return true;
    if (std.mem.eql(u8, name, "sa_string_pad_start")) return true;
    if (std.mem.eql(u8, name, "sa_string_pad_end")) return true;
    if (std.mem.eql(u8, name, "sa_string_replace")) return true;
    if (std.mem.eql(u8, name, "sa_string_code_point_at")) return true;
    if (std.mem.eql(u8, name, "sa_string_from_code_point")) return true;
    if (std.mem.eql(u8, name, "sa_str_is_ascii")) return true;
    if (std.mem.eql(u8, name, "sa_str_eq_ignore_ascii_case")) return true;
    if (std.mem.eql(u8, name, "sa_str_trim_ascii_start_index")) return true;
    if (std.mem.eql(u8, name, "sa_str_trim_ascii_end_len")) return true;
    if (std.mem.eql(u8, name, "sa_str_utf8_char_count")) return true;
    if (std.mem.eql(u8, name, "sa_str_utf8_validate")) return true;
    if (std.mem.eql(u8, name, "sa_str_utf8_char_at")) return true;
    if (std.mem.eql(u8, name, "sa_str_utf8_char_at_byte")) return true;
    if (std.mem.eql(u8, name, "sa_str_utf8_lossy_next")) return true;
    if (std.mem.eql(u8, name, "sa_str_utf8_char_range_at")) return true;
    if (std.mem.eql(u8, name, "sa_regex_compile")) return true;
    if (std.mem.eql(u8, name, "sa_regex_match")) return true;
    if (std.mem.eql(u8, name, "sa_regex_group_ptr")) return true;
    if (std.mem.eql(u8, name, "sa_regex_group_len")) return true;
    if (std.mem.eql(u8, name, "sa_regex_group_start")) return true;
    if (std.mem.eql(u8, name, "sa_regex_group_count")) return true;
    if (std.mem.eql(u8, name, "sa_regex_free")) return true;
    if (std.mem.eql(u8, name, "sa_regex_match_free")) return true;
    if (std.mem.eql(u8, name, "sa_modstate_get_u64")) return true;
    if (std.mem.eql(u8, name, "sa_modstate_set_u64")) return true;
    if (std.mem.eql(u8, name, "sa_json_parse")) return true;
    if (std.mem.eql(u8, name, "sa_json_kind")) return true;
    if (std.mem.eql(u8, name, "sa_json_object_get")) return true;
    if (std.mem.eql(u8, name, "sa_json_array_get")) return true;
    if (std.mem.eql(u8, name, "sa_json_object_key_at")) return true;
    if (std.mem.eql(u8, name, "sa_json_object_get_string")) return true;
    if (std.mem.eql(u8, name, "sa_json_object_get_bool")) return true;
    if (std.mem.eql(u8, name, "sa_json_object_get_i64")) return true;
    if (std.mem.eql(u8, name, "sa_json_object_get_f64")) return true;
    if (std.mem.eql(u8, name, "sa_json_as_i64")) return true;
    if (std.mem.eql(u8, name, "sa_json_as_f64")) return true;
    if (std.mem.eql(u8, name, "sa_json_as_bool")) return true;
    if (std.mem.eql(u8, name, "sa_json_free")) return true;
    if (std.mem.eql(u8, name, "sa_json_value_count")) return true;
    if (std.mem.eql(u8, name, "sa_json_writer_new")) return true;
    if (std.mem.eql(u8, name, "sa_json_writer_free")) return true;
    if (std.mem.eql(u8, name, "sa_json_writer_begin_object")) return true;
    if (std.mem.eql(u8, name, "sa_json_writer_end_object")) return true;
    if (std.mem.eql(u8, name, "sa_json_writer_begin_array")) return true;
    if (std.mem.eql(u8, name, "sa_json_writer_end_array")) return true;
    if (std.mem.eql(u8, name, "sa_json_writer_object_field")) return true;
    if (std.mem.eql(u8, name, "sa_json_writer_field_string")) return true;
    if (std.mem.eql(u8, name, "sa_json_writer_field_bool")) return true;
    if (std.mem.eql(u8, name, "sa_json_writer_field_i64")) return true;
    if (std.mem.eql(u8, name, "sa_json_writer_field_f64")) return true;
    if (std.mem.eql(u8, name, "sa_json_writer_field_null")) return true;
    if (std.mem.eql(u8, name, "sa_json_writer_write_bool")) return true;
    if (std.mem.eql(u8, name, "sa_json_writer_write_i64")) return true;
    if (std.mem.eql(u8, name, "sa_json_writer_write_f64")) return true;
    if (std.mem.eql(u8, name, "sa_json_writer_write_string")) return true;
    if (std.mem.eql(u8, name, "sa_json_writer_write_null")) return true;
    if (std.mem.eql(u8, name, "sa_json_writer_finish")) return true;
    if (std.mem.eql(u8, name, "sa_json_writer_finish_buffer")) return true;
    if (std.mem.eql(u8, name, "sa_json_buffer_data")) return true;
    if (std.mem.eql(u8, name, "sa_json_buffer_len")) return true;
    if (std.mem.eql(u8, name, "sa_json_buffer_free")) return true;
    if (std.mem.eql(u8, name, "sa_time_set_field")) return true;
    if (std.mem.eql(u8, name, "sa_std_fs_exists")) return true;
    if (std.mem.eql(u8, name, "sa_node_plugin_path_join")) return true;
    if (std.mem.eql(u8, name, "sa_node_plugin_path_normalize")) return true;
    if (std.mem.eql(u8, name, "sa_node_plugin_path_dirname")) return true;
    if (std.mem.eql(u8, name, "sa_node_plugin_path_extname")) return true;
    if (std.mem.eql(u8, name, "sa_node_plugin_path_is_absolute")) return true;
    if (std.mem.eql(u8, name, "sa_node_plugin_punycode_encode")) return true;
    if (std.mem.eql(u8, name, "sa_node_plugin_punycode_decode")) return true;
    if (std.mem.eql(u8, name, "sa_node_plugin_querystring_escape")) return true;
    if (std.mem.eql(u8, name, "sa_node_plugin_querystring_unescape")) return true;
    if (std.mem.eql(u8, name, "sa_node_plugin_buffer_concat")) return true;
    if (std.mem.eql(u8, name, "sa_node_plugin_crypto_random_bytes")) return true;
    if (std.mem.eql(u8, name, "sa_node_plugin_crypto_hash")) return true;
    if (std.mem.eql(u8, name, "sa_deno_plugin_atob")) return true;
    if (std.mem.eql(u8, name, "sa_deno_plugin_btoa")) return true;
    if (std.mem.eql(u8, name, "sa_deno_plugin_read_text_file")) return true;
    if (std.mem.eql(u8, name, "sa_deno_plugin_write_text_file")) return true;
    if (std.mem.eql(u8, name, "sa_deno_plugin_mkdir")) return true;
    if (std.mem.eql(u8, name, "sa_deno_plugin_remove")) return true;
    if (std.mem.eql(u8, name, "sa_node_plugin_free_buffer")) return true;
    if (std.mem.eql(u8, name, "sa_deno_plugin_free_buffer")) return true;
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

/// Whether a call result slot is proven to hold a SOLELY-owned base:
/// allocator shims and alloc-class callees always qualify. Param-class
/// (pass-through) callees NEVER qualify: the result aliases the caller's
/// argument block, so freeing through the result would corrupt the still
/// live source (e.g. `t_8 = call @greet(t)` ... `!t_8` must stay a no-op
/// while `t` is used again; native preserves the block). Leaking instead
/// is always observably safe.
fn provCallDestBase(
    set: *const BaseSet,
    symbols: anytype,
    fsig: sig.FunctionSig,
    parsed_callee: []const u8,
    parsed_args: anytype,
    retbase: *const RetBaseTable,
) bool {
    _ = set;
    _ = symbols;
    _ = fsig;
    _ = parsed_args;
    if (isAllocatorShim(parsed_callee)) return true;
    const info = retbase.get(parsed_callee) orelse return false;
    return info == .alloc;
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
        // Integer/bool/bytes formatting shims (mirror src/runtime/sa_std.zig
        // writeFormattedInto: *out_len always set to text length, even when
        // truncated or out_cap == 0; no partial copy on truncation).
        if (std.mem.eql(u8, fsig.name, "sa_fmt_i64_into")) {
            try writer.writeAll(
                \\function sa_fmt_i64_into(value, base, out, out_cap, out_len) {
                \\  const b = __sa_num(base);
                \\  const v = BigInt.asIntN(64, BigInt(value));
                \\  let text;
                \\  if (b === 2 || b === 8 || b === 10) text = v.toString(b);
                \\  else if (b === 16) text = v.toString(16);
                \\  else if (b === 17) text = v.toString(16).toUpperCase();
                \\  else return 1;
                \\  __sa_store_i64(out_len, text.length);
                \\  const cap = __sa_num(out_cap);
                \\  if (cap === 0) return 0;
                \\  if (cap < text.length) return 9;
                \\  const a = __sa_addr(out);
                \\  for (let i = 0; i < text.length; i++) __sa_u8[a + i] = text.charCodeAt(i);
                \\  return 0;
                \\}
                \\
            );
            return;
        }
        if (std.mem.eql(u8, fsig.name, "sa_fmt_u64_into")) {
            try writer.writeAll(
                \\function sa_fmt_u64_into(value, base, out, out_cap, out_len) {
                \\  const b = __sa_num(base);
                \\  const v = BigInt.asUintN(64, BigInt(value));
                \\  let text;
                \\  if (b === 2 || b === 8 || b === 10) text = v.toString(b);
                \\  else if (b === 16) text = v.toString(16);
                \\  else if (b === 17) text = v.toString(16).toUpperCase();
                \\  else return 1;
                \\  __sa_store_i64(out_len, text.length);
                \\  const cap = __sa_num(out_cap);
                \\  if (cap === 0) return 0;
                \\  if (cap < text.length) return 9;
                \\  const a = __sa_addr(out);
                \\  for (let i = 0; i < text.length; i++) __sa_u8[a + i] = text.charCodeAt(i);
                \\  return 0;
                \\}
                \\
            );
            return;
        }
        if (std.mem.eql(u8, fsig.name, "sa_fmt_bool_into")) {
            try writer.writeAll(
                \\function sa_fmt_bool_into(value, out, out_cap, out_len) {
                \\  const text = __sa_num(value) ? "true" : "false";
                \\  __sa_store_i64(out_len, text.length);
                \\  const cap = __sa_num(out_cap);
                \\  if (cap === 0) return 0;
                \\  if (cap < text.length) return 9;
                \\  const a = __sa_addr(out);
                \\  for (let i = 0; i < text.length; i++) __sa_u8[a + i] = text.charCodeAt(i);
                \\  return 0;
                \\}
                \\
            );
            return;
        }
        if (std.mem.eql(u8, fsig.name, "sa_fmt_bytes_into")) {
            try writer.writeAll(
                \\function sa_fmt_bytes_into(buf, len, out, out_cap, out_len) {
                \\  const n = __sa_num(len);
                \\  __sa_store_i64(out_len, n);
                \\  const cap = __sa_num(out_cap);
                \\  if (cap === 0) return 0;
                \\  if (cap < n) return 9;
                \\  const s = __sa_addr(buf), d = __sa_addr(out);
                \\  __sa_u8.copyWithin(d, s, s + n);
                \\  return 0;
                \\}
                \\
            );
            return;
        }
        if (std.mem.eql(u8, fsig.name, "sa_time_unix_ms")) {
            try writer.writeAll(
                \\function sa_time_unix_ms() { return BigInt.asIntN(64, BigInt(globalThis.Date.now())); }
                \\
            );
            return;
        }
        if (std.mem.eql(u8, fsig.name, "sa_time_unix_s")) {
            try writer.writeAll(
                \\function sa_time_unix_s() { return BigInt.asIntN(64, BigInt(Math.floor(globalThis.Date.now() / 1000))); }
                \\
            );
            return;
        }
        if (std.mem.eql(u8, fsig.name, "sa_time_unix_ns")) {
            try writer.writeAll(
                \\function sa_time_unix_ns() { return BigInt.asIntN(64, BigInt(globalThis.Date.now()) * 1000000n); }
                \\
            );
            return;
        }
        if (std.mem.eql(u8, fsig.name, "sa_time_instant_ns")) {
            try writer.writeAll(
                \\function sa_time_instant_ns() { return BigInt.asUintN(64, BigInt(globalThis.Date.now()) * 1000000n); }
                \\
            );
            return;
        }
        if (std.mem.eql(u8, fsig.name, "sa_time_sleep_ns")) {
            try writer.writeAll("function sa_time_sleep_ns(ns) { return 0; }\n");
            return;
        }
        if (std.mem.eql(u8, fsig.name, "sa_time_sleep_ms")) {
            try writer.writeAll("function sa_time_sleep_ms(ms) { return 0; }\n");
            return;
        }
        if (std.mem.eql(u8, fsig.name, "sa_time_get_full_year")) {
            try writer.writeAll("function sa_time_get_full_year(ms) { return __sa_civil(ms)[0]; }\n");
            return;
        }
        if (std.mem.eql(u8, fsig.name, "sa_time_get_month")) {
            try writer.writeAll("function sa_time_get_month(ms) { return __sa_civil(ms)[1] - 1n; }\n");
            return;
        }
        if (std.mem.eql(u8, fsig.name, "sa_time_get_date")) {
            try writer.writeAll("function sa_time_get_date(ms) { return __sa_civil(ms)[2]; }\n");
            return;
        }
        if (std.mem.eql(u8, fsig.name, "sa_time_get_hours")) {
            try writer.writeAll("function sa_time_get_hours(ms) { return __sa_civil(ms)[3]; }\n");
            return;
        }
        if (std.mem.eql(u8, fsig.name, "sa_time_get_minutes")) {
            try writer.writeAll("function sa_time_get_minutes(ms) { return __sa_civil(ms)[4]; }\n");
            return;
        }
        if (std.mem.eql(u8, fsig.name, "sa_time_get_seconds")) {
            try writer.writeAll("function sa_time_get_seconds(ms) { return __sa_civil(ms)[5]; }\n");
            return;
        }
        if (std.mem.eql(u8, fsig.name, "sa_time_get_milliseconds")) {
            try writer.writeAll("function sa_time_get_milliseconds(ms) { return __sa_civil(ms)[6]; }\n");
            return;
        }
        if (std.mem.eql(u8, fsig.name, "sa_time_get_day")) {
            try writer.writeAll("function sa_time_get_day(ms) { const d = __sa_civil(ms)[7]; return __sa_modfloor(d + 4n, 7n); }\n");
            return;
        }
        if (std.mem.eql(u8, fsig.name, "sa_time_get_day")) {
            try writer.writeAll("function sa_time_get_day(ms) { const d = __sa_civil(ms)[7]; return __sa_modfloor(d + 4n, 7n); }\n");
            return;
        }
        if (std.mem.eql(u8, fsig.name, "sa_time_parse_iso")) {
            try writer.writeAll(
                \\function sa_time_parse_iso(iso_ptr, iso_len, out_ms) {
                \\  __sa_store_i64(out_ms, 0n);
                \\  const bytes = __sa_mem_bytes(iso_ptr, iso_len);
                \\  let p = 0;
                \\  const digits = (n) => {
                \\    if (p + n > bytes.length) return null;
                \\    let v = 0n;
                \\    for (let i = 0; i < n; i++) {
                \\      const c = bytes[p + i];
                \\      if (c < 48 || c > 57) return null;
                \\      v = v * 10n + BigInt(c - 48);
                \\    }
                \\    p += n;
                \\    return v;
                \\  };
                \\  const year = digits(4); if (year === null) return 1;
                \\  if (p >= bytes.length || bytes[p] !== 45) return 1; p += 1;
                \\  const month = digits(2); if (month === null) return 1;
                \\  if (p >= bytes.length || bytes[p] !== 45) return 1; p += 1;
                \\  const day = digits(2); if (day === null) return 1;
                \\  let hour = 0n, minute = 0n, second = 0n, milli = 0n;
                \\  if (p < bytes.length) {
                \\    const t = bytes[p];
                \\    if (t !== 84 && t !== 116 && t !== 32) return 1; p += 1;
                \\    hour = digits(2); if (hour === null) return 1;
                \\    if (p >= bytes.length || bytes[p] !== 58) return 1; p += 1;
                \\    minute = digits(2); if (minute === null) return 1;
                \\    if (p >= bytes.length || bytes[p] !== 58) return 1; p += 1;
                \\    second = digits(2); if (second === null) return 1;
                \\    if (p < bytes.length && bytes[p] === 46) {
                \\      p += 1;
                \\      const fs = p;
                \\      while (p < bytes.length && bytes[p] >= 48 && bytes[p] <= 57) p += 1;
                \\      const fl = p - fs;
                \\      if (fl === 0 || fl > 3) return 1;
                \\      let f = 0n;
                \\      for (let i = fs; i < p; i++) f = f * 10n + BigInt(bytes[i] - 48);
                \\      milli = fl === 1 ? f * 100n : fl === 2 ? f * 10n : f;
                \\    }
                \\  }
                \\  let off = 0n;
                \\  if (p < bytes.length) {
                \\    const z = bytes[p];
                \\    if (z === 90 || z === 122) { p += 1; }
                \\    else if (z === 43 || z === 45) {
                \\      const neg = z === 45; p += 1;
                \\      const oh = digits(2); if (oh === null) return 1;
                \\      if (p >= bytes.length || bytes[p] !== 58) return 1; p += 1;
                \\      const om = digits(2); if (om === null) return 1;
                \\      if (oh > 23n || om > 59n) return 1;
                \\      off = oh * 60n + om;
                \\      if (neg) off = -off;
                \\    } else return 1;
                \\  }
                \\  if (p !== bytes.length) return 1;
                \\  if (month < 1n || month > 12n) return 1;
                \\  const leap = __sa_modfloor(year, 4n) === 0n && (__sa_modfloor(year, 100n) !== 0n || __sa_modfloor(year, 400n) === 0n);
                \\  const dim = (month === 1n || month === 3n || month === 5n || month === 7n || month === 8n || month === 10n || month === 12n) ? 31n
                \\    : (month === 4n || month === 6n || month === 9n || month === 11n) ? 30n : (leap ? 29n : 28n);
                \\  if (day < 1n || day > dim) return 1;
                \\  if (hour > 23n || minute > 59n || second > 59n) return 1;
                \\  const y = month <= 2n ? year - 1n : year;
                \\  const era = y >= 0n ? __sa_divfloor(y, 400n) : __sa_divfloor(y - 399n, 400n);
                \\  const yoe = y - era * 400n;
                \\  const mp = __sa_modfloor(month - 3n, 12n);
                \\  const doy = __sa_divfloor(153n * mp + 2n, 5n) + day - 1n;
                \\  const doe = yoe * 365n + __sa_divfloor(yoe, 4n) - __sa_divfloor(yoe, 100n) + doy;
                \\  const days = era * 146097n + doe - 719468n;
                \\  __sa_store_i64(out_ms, ((days * 86400n + hour * 3600n + minute * 60n + second) * 1000n + milli) - off * 60000n);
                \\  return 0;
                \\}
                \\
            );
            return;
        }
        // Owned-buffer handles (mirror openOwnedBuffer + sa_fmt_buffer_*):
        // data is materialized into linear memory on read so handles stay
        // valid across frees (ts_arr_join_append read-back pattern).
        if (std.mem.eql(u8, fsig.name, "sa_fmt_buffer_data")) {
            try writer.writeAll(
                \\function sa_fmt_buffer_data(handle) {
                \\  const b = __sa_buf_get(handle);
                \\  if (b === null) return 0;
                \\  const p = __sa_alloc(b.length);
                \\  __sa_u8.set(b, p);
                \\  return p;
                \\}
                \\
            );
            return;
        }
        if (std.mem.eql(u8, fsig.name, "sa_fmt_buffer_len")) {
            try writer.writeAll(
                \\function sa_fmt_buffer_len(handle) {
                \\  const b = __sa_buf_get(handle);
                \\  return b === null ? 0n : BigInt(b.length);
                \\}
                \\
            );
            return;
        }
        if (std.mem.eql(u8, fsig.name, "sa_fmt_buffer_free")) {
            try writer.writeAll(
                \\function sa_fmt_buffer_free(handle) { __sa_buffers.delete(__sa_num(handle)); return 0; }
                \\
            );
            return;
        }
        if (std.mem.eql(u8, fsig.name, "sa_fmt_f64_into")) {
            try writer.writeAll(
                \\function sa_fmt_f64_into(value, precision, out, out_cap, out_len) {
                \\  const text = __sa_fmt_f64_str(value, precision);
                \\  if (text === null) return 1;
                \\  const n = text.length;
                \\  __sa_store_i64(out_len, n);
                \\  const cap = __sa_num(out_cap);
                \\  if (cap === 0) return 0;
                \\  if (cap < n) return 9;
                \\  const a = __sa_addr(out);
                \\  for (let i = 0; i < n; i++) __sa_u8[a + i] = text.charCodeAt(i);
                \\  return 0;
                \\}
                \\
            );
            return;
        }
        if (std.mem.eql(u8, fsig.name, "sa_fmt_i64")) {
            try writer.writeAll(
                \\function sa_fmt_i64(value, base) {
                \\  const b = __sa_num(base);
                \\  const v = BigInt.asIntN(64, BigInt(value));
                \\  let text = null;
                \\  if (b === 2 || b === 8 || b === 10) text = v.toString(b);
                \\  else if (b === 16) text = v.toString(16);
                \\  else if (b === 17) text = v.toString(16).toUpperCase();
                \\  if (text === null) return 0n;
                \\  return __sa_buf_open(new globalThis.TextEncoder().encode(text));
                \\}
                \\
            );
            return;
        }
        if (std.mem.eql(u8, fsig.name, "sa_fmt_u64")) {
            try writer.writeAll(
                \\function sa_fmt_u64(value, base) {
                \\  const b = __sa_num(base);
                \\  const v = BigInt.asUintN(64, BigInt(value));
                \\  let text = null;
                \\  if (b === 2 || b === 8 || b === 10) text = v.toString(b);
                \\  else if (b === 16) text = v.toString(16);
                \\  else if (b === 17) text = v.toString(16).toUpperCase();
                \\  if (text === null) return 0n;
                \\  return __sa_buf_open(new globalThis.TextEncoder().encode(text));
                \\}
                \\
            );
            return;
        }
        if (std.mem.eql(u8, fsig.name, "sa_fmt_f64")) {
            try writer.writeAll(
                \\function sa_fmt_f64(value, precision) {
                \\  const text = __sa_fmt_f64_str(value, precision);
                \\  if (text === null) return 0n;
                \\  return __sa_buf_open(new globalThis.TextEncoder().encode(text));
                \\}
                \\
            );
            return;
        }
        if (std.mem.eql(u8, fsig.name, "sa_fmt_bool")) {
            try writer.writeAll(
                \\function sa_fmt_bool(value) {
                \\  return __sa_buf_open(new globalThis.TextEncoder().encode(__sa_num(value) ? "true" : "false"));
                \\}
                \\
            );
            return;
        }
        if (std.mem.eql(u8, fsig.name, "sa_fmt_bytes")) {
            try writer.writeAll(
                \\function sa_fmt_bytes(buf, len) { return __sa_buf_open(__sa_mem_bytes(buf, len)); }
                \\
            );
            return;
        }
        // Byte-oriented string ops (mirror sa_string_* in sa_std.zig).
        if (std.mem.eql(u8, fsig.name, "sa_string_concat")) {
            try writer.writeAll(
                \\function sa_string_concat(left, left_len, right, right_len) {
                \\  const l = __sa_mem_bytes(left, left_len), r = __sa_mem_bytes(right, right_len);
                \\  const out = new Uint8Array(l.length + r.length);
                \\  out.set(l, 0); out.set(r, l.length);
                \\  return __sa_buf_open(out);
                \\}
                \\
            );
            return;
        }
        if (std.mem.eql(u8, fsig.name, "sa_string_from_char_code")) {
            try writer.writeAll(
                \\function sa_string_from_char_code(code) { return __sa_buf_open(new Uint8Array([__sa_num(code) & 0xff])); }
                \\
            );
            return;
        }
        if (std.mem.eql(u8, fsig.name, "sa_string_index_of")) {
            try writer.writeAll(
                \\function sa_string_index_of(hay_ptr, hay_len, ndl_ptr, ndl_len, from) {
                \\  const hay = __sa_mem_bytes(hay_ptr, hay_len), ndl = __sa_mem_bytes(ndl_ptr, ndl_len);
                \\  const start = Math.min(__sa_tou(from), hay.length);
                \\  if (ndl.length === 0) return Math.min(start, hay.length);
                \\  if (ndl.length > hay.length) return -1;
                \\  outer: for (let i = start; i + ndl.length <= hay.length; i++) {
                \\    for (let j = 0; j < ndl.length; j++) if (hay[i + j] !== ndl[j]) continue outer;
                \\    return i;
                \\  }
                \\  return -1;
                \\}
                \\
            );
            return;
        }
        if (std.mem.eql(u8, fsig.name, "sa_string_last_index_of")) {
            try writer.writeAll(
                \\function sa_string_last_index_of(hay_ptr, hay_len, ndl_ptr, ndl_len, from) {
                \\  const hay = __sa_mem_bytes(hay_ptr, hay_len), ndl = __sa_mem_bytes(ndl_ptr, ndl_len);
                \\  const start = Math.min(__sa_tou(from), hay.length);
                \\  if (ndl.length === 0) return Math.min(start, hay.length);
                \\  if (ndl.length > hay.length) return -1;
                \\  outer: for (let i = Math.min(start, hay.length - ndl.length); ; i--) {
                \\    let ok = true;
                \\    for (let j = 0; j < ndl.length; j++) if (hay[i + j] !== ndl[j]) { ok = false; break; }
                \\    if (ok) return i;
                \\    if (i === 0) break;
                \\  }
                \\  return -1;
                \\}
                \\
            );
            return;
        }
        if (std.mem.eql(u8, fsig.name, "sa_string_starts_with")) {
            try writer.writeAll(
                \\function sa_string_starts_with(hay_ptr, hay_len, ndl_ptr, ndl_len) {
                \\  const hay = __sa_mem_bytes(hay_ptr, hay_len), ndl = __sa_mem_bytes(ndl_ptr, ndl_len);
                \\  if (ndl.length > hay.length) return 0;
                \\  for (let j = 0; j < ndl.length; j++) if (hay[j] !== ndl[j]) return 0;
                \\  return 1;
                \\}
                \\
            );
            return;
        }
        if (std.mem.eql(u8, fsig.name, "sa_string_ends_with")) {
            try writer.writeAll(
                \\function sa_string_ends_with(hay_ptr, hay_len, ndl_ptr, ndl_len) {
                \\  const hay = __sa_mem_bytes(hay_ptr, hay_len), ndl = __sa_mem_bytes(ndl_ptr, ndl_len);
                \\  if (ndl.length > hay.length) return 0;
                \\  const o = hay.length - ndl.length;
                \\  for (let j = 0; j < ndl.length; j++) if (hay[o + j] !== ndl[j]) return 0;
                \\  return 1;
                \\}
                \\
            );
            return;
        }
        if (std.mem.eql(u8, fsig.name, "sa_string_to_lower_ascii")) {
            try writer.writeAll(
                \\function sa_string_to_lower_ascii(ptr, len) {
                \\  const b = __sa_mem_bytes(ptr, len);
                \\  for (let i = 0; i < b.length; i++) if (b[i] >= 65 && b[i] <= 90) b[i] += 32;
                \\  return __sa_buf_open(b);
                \\}
                \\
            );
            return;
        }
        if (std.mem.eql(u8, fsig.name, "sa_string_to_upper_ascii")) {
            try writer.writeAll(
                \\function sa_string_to_upper_ascii(ptr, len) {
                \\  const b = __sa_mem_bytes(ptr, len);
                \\  for (let i = 0; i < b.length; i++) if (b[i] >= 97 && b[i] <= 122) b[i] -= 32;
                \\  return __sa_buf_open(b);
                \\}
                \\
            );
            return;
        }
        if (std.mem.eql(u8, fsig.name, "sa_parse_float")) {
            try writer.writeAll(
                \\function sa_parse_float(ptr, len) {
                \\  const bytes = __sa_mem_bytes(ptr, len);
                \\  let i = 0;
                \\  while (i < bytes.length && __sa_is_ws(bytes[i])) i++;
                \\  let neg = false;
                \\  if (i < bytes.length && (bytes[i] === 43 || bytes[i] === 45)) { neg = bytes[i] === 45; i++; }
                \\  const rest = bytes.slice(i);
                \\  const rs = (t) => String.fromCharCode.apply(null, t);
                \\  if (rest.length >= 8 && rs(rest.slice(0, 8)) === "Infinity") return neg ? -Infinity : Infinity;
                \\  if (rest.length >= 3 && rs(rest.slice(0, 3)) === "NaN") return NaN;
                \\  let j = 0;
                \\  while (j < rest.length && rest[j] >= 48 && rest[j] <= 57) j++;
                \\  const ints = j;
                \\  if (j < rest.length && rest[j] === 46) {
                \\    j++;
                \\    while (j < rest.length && rest[j] >= 48 && rest[j] <= 57) j++;
                \\  }
                \\  const fracs = j - ints - ((j > ints && rest[ints] === 46) ? 1 : 0);
                \\  if (ints === 0 && fracs === 0) return NaN;
                \\  let k = j;
                \\  if (k < rest.length && (rest[k] === 101 || rest[k] === 69)) {
                \\    let m = k + 1;
                \\    if (m < rest.length && (rest[m] === 43 || rest[m] === 45)) m++;
                \\    const es = m;
                \\    while (m < rest.length && rest[m] >= 48 && rest[m] <= 57) m++;
                \\    if (m > es) k = m;
                \\  }
                \\  const num = parseFloat(rs(rest.slice(0, k)));
                \\  if (Number.isNaN(num)) return NaN;
                \\  if (!Number.isFinite(num)) return neg ? -Infinity : Infinity;
                \\  return neg ? -num : num;
                \\}
                \\
            );
            return;
        }
        if (std.mem.eql(u8, fsig.name, "sa_string_repeat")) {
            try writer.writeAll(
                \\function sa_string_repeat(ptr, len, count) {
                \\  const b = __sa_mem_bytes(ptr, len);
                \\  if (b.length === 0) return __sa_buf_open(new Uint8Array(0));
                \\  const n = __sa_num(count);
                \\  if (n === 0) return __sa_buf_open(new Uint8Array(0));
                \\  if (!(n > 0) || !Number.isSafeInteger(n) || n > 4294967295 / b.length) return 0n;
                \\  const out = new Uint8Array(b.length * n);
                \\  for (let i = 0; i < n; i++) out.set(b, i * b.length);
                \\  return __sa_buf_open(out);
                \\}
                \\
            );
            return;
        }
        if (std.mem.eql(u8, fsig.name, "sa_string_pad_start")) {
            try writer.writeAll(
                \\function sa_string_pad_start(ptr, len, target_len, pad_ptr, pad_len) {
                \\  const b = __sa_mem_bytes(ptr, len), pad = __sa_mem_bytes(pad_ptr, pad_len);
                \\  const t = __sa_num(target_len);
                \\  if (t <= b.length || pad.length === 0) return __sa_buf_open(b);
                \\  const out = new Uint8Array(t);
                \\  const fill = t - b.length;
                \\  for (let i = 0; i < fill; i++) out[i] = pad[i % pad.length];
                \\  out.set(b, fill);
                \\  return __sa_buf_open(out);
                \\}
                \\
            );
            return;
        }
        if (std.mem.eql(u8, fsig.name, "sa_string_pad_end")) {
            try writer.writeAll(
                \\function sa_string_pad_end(ptr, len, target_len, pad_ptr, pad_len) {
                \\  const b = __sa_mem_bytes(ptr, len), pad = __sa_mem_bytes(pad_ptr, pad_len);
                \\  const t = __sa_num(target_len);
                \\  if (t <= b.length || pad.length === 0) return __sa_buf_open(b);
                \\  const out = new Uint8Array(t);
                \\  out.set(b, 0);
                \\  for (let i = b.length; i < t; i++) out[i] = pad[(i - b.length) % pad.length];
                \\  return __sa_buf_open(out);
                \\}
                \\
            );
            return;
        }
        if (std.mem.eql(u8, fsig.name, "sa_string_replace")) {
            try writer.writeAll(
                \\function sa_string_replace(hay_ptr, hay_len, ndl_ptr, ndl_len, rep_ptr, rep_len, all) {
                \\  const hay = __sa_mem_bytes(hay_ptr, hay_len), ndl = __sa_mem_bytes(ndl_ptr, ndl_len), rep = __sa_mem_bytes(rep_ptr, rep_len);
                \\  const want_all = __sa_num(all) !== 0;
                \\  const at = (i) => { for (let j = 0; j < ndl.length; j++) if (hay[i + j] !== ndl[j]) return false; return true; };
                \\  if (ndl.length === 0) {
                \\    if (!want_all) { const o = new Uint8Array(rep.length + hay.length); o.set(rep, 0); o.set(hay, rep.length); return __sa_buf_open(o); }
                \\    const o = new Uint8Array(hay.length + rep.length * (hay.length + 1));
                \\    let w = 0;
                \\    for (let i = 0; i < hay.length; i++) { o.set(rep, w); w += rep.length; o[w++] = hay[i]; }
                \\    o.set(rep, w); w += rep.length;
                \\    return __sa_buf_open(o.slice(0, w));
                \\  }
                \\  if (ndl.length > hay.length) return __sa_buf_open(hay);
                \\  const starts = [];
                \\  if (!want_all) { for (let i = 0; i + ndl.length <= hay.length; i++) if (at(i)) { starts.push(i); break; } }
                \\  else { for (let i = 0; i + ndl.length <= hay.length;) if (at(i)) { starts.push(i); i += ndl.length; } else i++; }
                \\  if (starts.length === 0) return __sa_buf_open(hay);
                \\  let total = hay.length;
                \\  for (const s of starts) total += rep.length - ndl.length;
                \\  const o = new Uint8Array(total);
                \\  let w = 0, s = 0;
                \\  for (const m of starts) {
                \\    o.set(hay.slice(s, m), w); w += m - s;
                \\    o.set(rep, w); w += rep.length;
                \\    s = m + ndl.length;
                \\  }
                \\  o.set(hay.slice(s), w);
                \\  return __sa_buf_open(o);
                \\}
                \\
            );
            return;
        }
        if (std.mem.eql(u8, fsig.name, "sa_string_code_point_at")) {
            try writer.writeAll(
                \\function sa_string_code_point_at(ptr, len, idx) {
                \\  const b = __sa_mem_bytes(ptr, len);
                \\  const i = __sa_num(idx);
                \\  if (i < 0 || i >= b.length) return -1;
                \\  return b[i];
                \\}
                \\
            );
            return;
        }
        if (std.mem.eql(u8, fsig.name, "sa_string_from_code_point")) {
            try writer.writeAll(
                \\function sa_string_from_code_point(code) {
                \\  let cp = __sa_num(code);
                \\  if (cp < 0 || cp > 0x10ffff || (cp >= 0xd800 && cp <= 0xdfff)) cp = 0xfffd;
                \\  return __sa_buf_open(new globalThis.TextEncoder().encode(String.fromCodePoint(cp)));
                \\}
                \\
            );
            return;
        }
        if (std.mem.eql(u8, fsig.name, "sa_str_is_ascii")) {
            try writer.writeAll(
                \\function sa_str_is_ascii(ptr, len) {
                \\  const b = __sa_mem_bytes(ptr, len);
                \\  for (let i = 0; i < b.length; i++) if (b[i] > 0x7f) return 0;
                \\  return 1;
                \\}
                \\
            );
            return;
        }
        if (std.mem.eql(u8, fsig.name, "sa_str_eq_ignore_ascii_case")) {
            try writer.writeAll(
                \\function sa_str_eq_ignore_ascii_case(left_ptr, left_len, right_ptr, right_len) {
                \\  const l = __sa_mem_bytes(left_ptr, left_len), r = __sa_mem_bytes(right_ptr, right_len);
                \\  if (l.length !== r.length) return 0;
                \\  const f = (c) => (c >= 65 && c <= 90) ? c + 32 : c;
                \\  for (let i = 0; i < l.length; i++) if (f(l[i]) !== f(r[i])) return 0;
                \\  return 1;
                \\}
                \\
            );
            return;
        }
        if (std.mem.eql(u8, fsig.name, "sa_str_trim_ascii_start_index")) {
            try writer.writeAll(
                \\function sa_str_trim_ascii_start_index(ptr, len) {
                \\  const b = __sa_mem_bytes(ptr, len);
                \\  let i = 0;
                \\  while (i < b.length && __sa_is_ws(b[i])) i++;
                \\  return BigInt(i);
                \\}
                \\
            );
            return;
        }
        if (std.mem.eql(u8, fsig.name, "sa_str_trim_ascii_end_len")) {
            try writer.writeAll(
                \\function sa_str_trim_ascii_end_len(ptr, len) {
                \\  const b = __sa_mem_bytes(ptr, len);
                \\  let e = b.length;
                \\  while (e > 0 && __sa_is_ws(b[e - 1])) e--;
                \\  return BigInt(e);
                \\}
                \\
            );
            return;
        }
        if (std.mem.eql(u8, fsig.name, "sa_str_utf8_char_count")) {
            try writer.writeAll(
                \\function sa_str_utf8_char_count(ptr, len) {
                \\  const b = __sa_mem_bytes(ptr, len);
                \\  let i = 0, n = 0n;
                \\  while (i < b.length) {
                \\    const d = __sa_utf8_dec(b, i);
                \\    if (d === null) return 0n;
                \\    i += d[1]; n++;
                \\  }
                \\  return n;
                \\}
                \\
            );
            return;
        }
        if (std.mem.eql(u8, fsig.name, "sa_str_utf8_validate")) {
            try writer.writeAll(
                \\function sa_str_utf8_validate(ptr, len) {
                \\  const b = __sa_mem_bytes(ptr, len);
                \\  let i = 0;
                \\  while (i < b.length) {
                \\    const d = __sa_utf8_dec(b, i);
                \\    if (d === null) return 1;
                \\    i += d[1];
                \\  }
                \\  return 0;
                \\}
                \\
            );
            return;
        }
        if (std.mem.eql(u8, fsig.name, "sa_str_utf8_char_at")) {
            try writer.writeAll(
                \\function sa_str_utf8_char_at(ptr, len, char_index, out_codepoint) {
                \\  __sa_store_i64(out_codepoint, 0n);
                \\  const b = __sa_mem_bytes(ptr, len);
                \\  let bi = 0, cur = 0n;
                \\  const want = BigInt.asUintN(64, BigInt(__sa_num(char_index)));
                \\  while (bi < b.length) {
                \\    const d = __sa_utf8_dec(b, bi);
                \\    if (d === null) return 1;
                \\    if (cur === want) { __sa_store_i64(out_codepoint, d[0]); return 0; }
                \\    bi += d[1]; cur++;
                \\  }
                \\  return 3;
                \\}
                \\
            );
            return;
        }
        if (std.mem.eql(u8, fsig.name, "sa_str_utf8_char_at_byte")) {
            try writer.writeAll(
                \\function sa_str_utf8_char_at_byte(ptr, len, byte_index, out_codepoint, out_len) {
                \\  __sa_store_i64(out_codepoint, 0n);
                \\  __sa_store_i64(out_len, 0n);
                \\  const b = __sa_mem_bytes(ptr, len);
                \\  const idx = __sa_num(byte_index);
                \\  if (idx < 0 || idx >= b.length) return 3;
                \\  const d = __sa_utf8_dec(b, idx);
                \\  if (d === null) return 1;
                \\  __sa_store_i64(out_codepoint, d[0]);
                \\  __sa_store_i64(out_len, d[1]);
                \\  return 0;
                \\}
                \\
            );
            return;
        }
        if (std.mem.eql(u8, fsig.name, "sa_str_utf8_lossy_next")) {
            try writer.writeAll(
                \\function sa_str_utf8_lossy_next(ptr, len, byte_index, out_codepoint, out_len) {
                \\  __sa_store_i64(out_codepoint, 0n);
                \\  __sa_store_i64(out_len, 0n);
                \\  const b = __sa_mem_bytes(ptr, len);
                \\  const idx = __sa_num(byte_index);
                \\  if (idx < 0 || idx >= b.length) return 1;
                \\  const d = __sa_utf8_dec(b, idx);
                \\  if (d === null) {
                \\    let w = 1;
                \\    const b0 = b[idx];
                \\    const exp = (b0 >= 0xc2 && b0 <= 0xdf) ? 2 : (b0 >= 0xe0 && b0 <= 0xef) ? 3 : (b0 >= 0xf0 && b0 <= 0xf4) ? 4 : 1;
                \\    while (w < exp && idx + w < b.length) { const c = b[idx + w]; if (c < 0x80 || c > 0xbf) break; w++; }
                \\    __sa_store_i64(out_codepoint, 65533);
                \\    __sa_store_i64(out_len, w);
                \\    return 0;
                \\  }
                \\  __sa_store_i64(out_codepoint, d[0]);
                \\  __sa_store_i64(out_len, d[1]);
                \\  return 0;
                \\}
                \\
            );
            return;
        }
        if (std.mem.eql(u8, fsig.name, "sa_str_utf8_char_range_at")) {
            try writer.writeAll(
                \\function sa_str_utf8_char_range_at(ptr, len, char_index, out_start, out_len) {
                \\  __sa_store_i64(out_start, 0n);
                \\  __sa_store_i64(out_len, 0n);
                \\  const b = __sa_mem_bytes(ptr, len);
                \\  let bi = 0, cur = 0n;
                \\  const want = BigInt.asUintN(64, BigInt(__sa_num(char_index)));
                \\  while (bi < b.length) {
                \\    const d = __sa_utf8_dec(b, bi);
                \\    if (d === null) return 1;
                \\    if (cur === want) { __sa_store_i64(out_start, bi); __sa_store_i64(out_len, d[1]); return 0; }
                \\    bi += d[1]; cur++;
                \\  }
                \\  return 3;
                \\}
                \\
            );
            return;
        }
        // POSIX-regex shims via JS RegExp (mirror sa_regex_* in sa_std.zig:
        // compile/match handles, group (so,eo) triples, NUL-payload
        // refusal). Byte offsets equal JS indices on ASCII payloads, which
        // is all the tsgosa regex table emits; non-ASCII edges may differ.
        if (std.mem.eql(u8, fsig.name, "sa_regex_compile")) {
            try writer.writeAll(
                \\function sa_regex_compile(pattern, pattern_len, cflags) {
                \\  const bytes = __sa_mem_bytes(pattern, pattern_len);
                \\  for (let i = 0; i < bytes.length; i++) if (bytes[i] === 0) return 0n;
                \\  const src = new globalThis.TextDecoder().decode(bytes);
                \\  const f = __sa_num(cflags);
                \\  let flags = "d";
                \\  if ((f & 2) !== 0) flags += "i";
                \\  if ((f & 4) !== 0) flags += "m";
                \\  let re;
                \\  try { re = new RegExp(src, flags); } catch (e) { return 0n; }
                \\  let ngroups = 0;
                \\  try {
                \\    const probe = new RegExp("(?:" + src + ")|()", flags);
                \\    const pm = probe.exec("");
                \\    ngroups = (pm && pm.indices) ? pm.indices.length - 2 : 0;
                \\  } catch (e) { ngroups = 0; }
                \\  const h = __sa_regexnext++;
                \\  __sa_regexes.set(h, { re: re, ngroups: ngroups });
                \\  return BigInt(h);
                \\}
                \\
            );
            return;
        }
        if (std.mem.eql(u8, fsig.name, "sa_regex_match")) {
            try writer.writeAll(
                \\function sa_regex_match(regex, text, text_len) {
                \\  const rec = __sa_regexes.get(__sa_num(regex));
                \\  if (rec === undefined) return 0n;
                \\  const bytes = __sa_mem_bytes(text, text_len);
                \\  for (let i = 0; i < bytes.length; i++) if (bytes[i] === 0) return 0n;
                \\  const s = new globalThis.TextDecoder().decode(bytes);
                \\  rec.re.lastIndex = 0;
                \\  const m = rec.re.exec(s);
                \\  if (m === null || m.indices === undefined) return 0n;
                \\  const p = __sa_alloc(bytes.length);
                \\  __sa_u8.set(bytes, p);
                \\  const groups = m.indices.map((g) => ((g === undefined) ? [-1, -1] : [g[0], g[1]]));
                \\  const h = __sa_regexmatchnext++;
                \\  __sa_regexmatches.set(h, { base: p, len: bytes.length, groups: groups });
                \\  return BigInt(h);
                \\}
                \\
            );
            return;
        }
        if (std.mem.eql(u8, fsig.name, "sa_regex_group_ptr")) {
            try writer.writeAll(
                \\function sa_regex_group_ptr(match, group_idx) {
                \\  const g = __sa_regex_group(match, group_idx);
                \\  if (g === null) return 0;
                \\  return __sa_ptr_add(g.rec.base, g.so);
                \\}
                \\
            );
            return;
        }
        if (std.mem.eql(u8, fsig.name, "sa_regex_group_len")) {
            try writer.writeAll(
                \\function sa_regex_group_len(match, group_idx) {
                \\  const g = __sa_regex_group(match, group_idx);
                \\  if (g === null) return 0n;
                \\  return BigInt(g.eo - g.so);
                \\}
                \\
            );
            return;
        }
        if (std.mem.eql(u8, fsig.name, "sa_regex_group_start")) {
            try writer.writeAll(
                \\function sa_regex_group_start(match, group_idx) {
                \\  const g = __sa_regex_group(match, group_idx);
                \\  if (g === null) return 0n;
                \\  return BigInt(g.so);
                \\}
                \\
            );
            return;
        }
        if (std.mem.eql(u8, fsig.name, "sa_regex_group_count")) {
            try writer.writeAll(
                \\function sa_regex_group_count(regex) {
                \\  const rec = __sa_regexes.get(__sa_num(regex));
                \\  if (rec === undefined) return 0n;
                \\  return BigInt(rec.ngroups + 1);
                \\}
                \\
            );
            return;
        }
        if (std.mem.eql(u8, fsig.name, "sa_regex_free")) {
            try writer.writeAll(
                \\function sa_regex_free(regex) { __sa_regexes.delete(__sa_num(regex)); return 0; }
                \\
            );
            return;
        }
        if (std.mem.eql(u8, fsig.name, "sa_regex_match_free")) {
            try writer.writeAll(
                \\function sa_regex_match_free(match) {
                \\  const r = __sa_regexmatches.get(__sa_num(match));
                \\  if (r !== undefined) { __sa_regexmatches.delete(__sa_num(match)); __sa_free(r.base); }
                \\  return 0;
                \\}
                \\
            );
            return;
        }
        // Module-state slots (mirror modstate.sai over the thread-local
        // registry): opaque u64 cells keyed by FNV-1a-64, zero on first
        // touch. Single-threaded JS: a plain Map suffices.
        if (std.mem.eql(u8, fsig.name, "sa_modstate_get_u64")) {
            try writer.writeAll(
                \\function sa_modstate_get_u64(key) {
                \\  const v = __sa_modstate.get(__sa_tou(key));
                \\  return (v === undefined) ? 0n : BigInt.asUintN(64, v);
                \\}
                \\
            );
            return;
        }
        if (std.mem.eql(u8, fsig.name, "sa_modstate_set_u64")) {
            try writer.writeAll(
                \\function sa_modstate_set_u64(key, value) {
                \\  __sa_modstate.set(__sa_tou(key), BigInt.asUintN(64, BigInt(__sa_num(value))));
                \\  return 0;
                \\}
                \\
            );
            return;
        }
        // JSON reader family (mirror sa_json_* in sa_std.zig over
        // std.json.Value). Handles index parsed JS values; children borrow
        // (no ownership split needed single-threaded).
        if (std.mem.eql(u8, fsig.name, "sa_json_parse")) {
            try writer.writeAll(
                \\function sa_json_parse(json_ptr, len) {
                \\  const bytes = __sa_mem_bytes(json_ptr, len);
                \\  let text = "";
                \\  try { text = new globalThis.TextDecoder("utf-8", { fatal: true }).decode(bytes); } catch (e) { return 0n; }
                \\  let value;
                \\  try { value = globalThis.JSON.parse(text); } catch (e) { return 0n; }
                \\  if (value === undefined) return 0n;
                \\  const h = __sa_jsonnext++;
                \\  __sa_jsonnodes.set(h, value);
                \\  return BigInt(h);
                \\}
                \\
            );
            return;
        }
        if (std.mem.eql(u8, fsig.name, "sa_json_kind")) {
            try writer.writeAll(
                \\function sa_json_kind(node) {
                \\  const v = __sa_jsonnodes.get(__sa_num(node));
                \\  if (v === undefined) return 4294967295;
                \\  return __sa_json_kind_of(v);
                \\}
                \\
            );
            return;
        }
        if (std.mem.eql(u8, fsig.name, "sa_json_object_get")) {
            try writer.writeAll(
                \\function sa_json_object_get(node, key_ptr, key_len, out_handle) {
                \\  __sa_store_i64(out_handle, 0n);
                \\  const v = __sa_jsonnodes.get(__sa_num(node));
                \\  if (v === undefined || v === null || typeof v !== "object" || Array.isArray(v)) return 2;
                \\  const key = new globalThis.TextDecoder().decode(__sa_mem_bytes(key_ptr, key_len));
                \\  if (key.length === 0) return 1;
                \\  if (!Object.prototype.hasOwnProperty.call(v, key)) return 3;
                \\  const h = __sa_jsonnext++;
                \\  __sa_jsonnodes.set(h, v[key]);
                \\  __sa_store_i64(out_handle, BigInt(h));
                \\  return 0;
                \\}
                \\
            );
            return;
        }
        if (std.mem.eql(u8, fsig.name, "sa_json_array_get")) {
            try writer.writeAll(
                \\function sa_json_array_get(node, index, out_handle) {
                \\  __sa_store_i64(out_handle, 0n);
                \\  const v = __sa_jsonnodes.get(__sa_num(node));
                \\  if (v === undefined || !Array.isArray(v)) return 2;
                \\  const i = __sa_tou(index);
                \\  if (!(i >= 0) || i >= v.length) return 3;
                \\  const h = __sa_jsonnext++;
                \\  __sa_jsonnodes.set(h, v[i]);
                \\  __sa_store_i64(out_handle, BigInt(h));
                \\  return 0;
                \\}
                \\
            );
            return;
        }
        if (std.mem.eql(u8, fsig.name, "sa_json_object_key_at")) {
            try writer.writeAll(
                \\function sa_json_object_key_at(node, index, out_ptr, out_len) {
                \\  __sa_store_i64(out_ptr, 0n);
                \\  __sa_store_i64(out_len, 0n);
                \\  const v = __sa_jsonnodes.get(__sa_num(node));
                \\  if (v === undefined || v === null || typeof v !== "object" || Array.isArray(v)) return 2;
                \\  const keys = Object.keys(v);
                \\  const i = __sa_tou(index);
                \\  if (!(i >= 0) || i >= keys.length) return 3;
                \\  const bytes = new globalThis.TextEncoder().encode(keys[i]);
                \\  const p = __sa_alloc(bytes.length);
                \\  __sa_u8.set(bytes, p);
                \\  __sa_store_i64(out_ptr, p);
                \\  __sa_store_i64(out_len, bytes.length);
                \\  return 0;
                \\}
                \\
            );
            return;
        }
        if (std.mem.eql(u8, fsig.name, "sa_json_object_get_string")) {
            try writer.writeAll(
                \\function sa_json_object_get_string(node, key_ptr, key_len, out_ptr, out_len) {
                \\  __sa_store_i64(out_ptr, 0n);
                \\  __sa_store_i64(out_len, 0n);
                \\  const v = __sa_jsonnodes.get(__sa_num(node));
                \\  if (v === undefined || v === null || typeof v !== "object" || Array.isArray(v)) return 2;
                \\  const key = new globalThis.TextDecoder().decode(__sa_mem_bytes(key_ptr, key_len));
                \\  if (key.length === 0) return 1;
                \\  if (!Object.prototype.hasOwnProperty.call(v, key)) return 3;
                \\  const s = v[key];
                \\  if (typeof s !== "string") return 1;
                \\  const bytes = new globalThis.TextEncoder().encode(s);
                \\  const p = __sa_alloc(bytes.length);
                \\  __sa_u8.set(bytes, p);
                \\  __sa_store_i64(out_ptr, p);
                \\  __sa_store_i64(out_len, bytes.length);
                \\  return 0;
                \\}
                \\
            );
            return;
        }
        if (std.mem.eql(u8, fsig.name, "sa_json_object_get_bool")) {
            try writer.writeAll(
                \\function sa_json_object_get_bool(node, key_ptr, key_len, out_value) {
                \\  __sa_store_u8(out_value, 0);
                \\  const v = __sa_jsonnodes.get(__sa_num(node));
                \\  if (v === undefined || v === null || typeof v !== "object" || Array.isArray(v)) return 2;
                \\  const key = new globalThis.TextDecoder().decode(__sa_mem_bytes(key_ptr, key_len));
                \\  if (key.length === 0) return 1;
                \\  if (!Object.prototype.hasOwnProperty.call(v, key)) return 3;
                \\  const b = v[key];
                \\  if (typeof b !== "boolean") return 1;
                \\  __sa_store_u8(out_value, b ? 1 : 0);
                \\  return 0;
                \\}
                \\
            );
            return;
        }
        if (std.mem.eql(u8, fsig.name, "sa_json_object_get_i64")) {
            try writer.writeAll(
                \\function sa_json_object_get_i64(node, key_ptr, key_len, out_value) {
                \\  __sa_store_i64(out_value, 0n);
                \\  const v = __sa_jsonnodes.get(__sa_num(node));
                \\  if (v === undefined || v === null || typeof v !== "object" || Array.isArray(v)) return 2;
                \\  const key = new globalThis.TextDecoder().decode(__sa_mem_bytes(key_ptr, key_len));
                \\  if (key.length === 0) return 1;
                \\  if (!Object.prototype.hasOwnProperty.call(v, key)) return 3;
                \\  const n = __sa_json_i64_of(v[key]);
                \\  if (n === null) return 1;
                \\  __sa_store_i64(out_value, n);
                \\  return 0;
                \\}
                \\
            );
            return;
        }
        if (std.mem.eql(u8, fsig.name, "sa_json_object_get_f64")) {
            try writer.writeAll(
                \\function sa_json_object_get_f64(node, key_ptr, key_len, out_value) {
                \\  __sa_store_f64(out_value, 0);
                \\  const v = __sa_jsonnodes.get(__sa_num(node));
                \\  if (v === undefined || v === null || typeof v !== "object" || Array.isArray(v)) return 2;
                \\  const key = new globalThis.TextDecoder().decode(__sa_mem_bytes(key_ptr, key_len));
                \\  if (key.length === 0) return 1;
                \\  if (!Object.prototype.hasOwnProperty.call(v, key)) return 3;
                \\  const n = __sa_json_f64_of(v[key]);
                \\  if (n === null) return 1;
                \\  __sa_store_f64(out_value, n);
                \\  return 0;
                \\}
                \\
            );
            return;
        }
        if (std.mem.eql(u8, fsig.name, "sa_json_as_i64")) {
            try writer.writeAll(
                \\function sa_json_as_i64(node, out_value) {
                \\  __sa_store_i64(out_value, 0n);
                \\  const v = __sa_jsonnodes.get(__sa_num(node));
                \\  if (v === undefined) return 2;
                \\  const n = __sa_json_i64_of(v);
                \\  if (n === null) return 1;
                \\  __sa_store_i64(out_value, n);
                \\  return 0;
                \\}
                \\
            );
            return;
        }
        if (std.mem.eql(u8, fsig.name, "sa_json_as_f64")) {
            try writer.writeAll(
                \\function sa_json_as_f64(node, out_value) {
                \\  __sa_store_f64(out_value, 0);
                \\  const v = __sa_jsonnodes.get(__sa_num(node));
                \\  if (v === undefined) return 2;
                \\  const n = __sa_json_f64_of(v);
                \\  if (n === null) return 1;
                \\  __sa_store_f64(out_value, n);
                \\  return 0;
                \\}
                \\
            );
            return;
        }
        if (std.mem.eql(u8, fsig.name, "sa_json_as_bool")) {
            try writer.writeAll(
                \\function sa_json_as_bool(node, out_value) {
                \\  __sa_store_u8(out_value, 0);
                \\  const v = __sa_jsonnodes.get(__sa_num(node));
                \\  if (v === undefined) return 2;
                \\  if (typeof v !== "boolean") return 1;
                \\  __sa_store_u8(out_value, v ? 1 : 0);
                \\  return 0;
                \\}
                \\
            );
            return;
        }
        if (std.mem.eql(u8, fsig.name, "sa_json_free")) {
            try writer.writeAll(
                \\function sa_json_free(node) { __sa_jsonnodes.delete(__sa_num(node)); return 0; }
                \\
            );
            return;
        }
        if (std.mem.eql(u8, fsig.name, "sa_json_value_count")) {
            try writer.writeAll(
                \\function sa_json_value_count(node, out_count) {
                \\  __sa_store_i64(out_count, 0n);
                \\  const v = __sa_jsonnodes.get(__sa_num(node));
                \\  if (v === undefined) return 2;
                \\  if (Array.isArray(v)) { __sa_store_i64(out_count, v.length); return 0; }
                \\  if (v !== null && typeof v === "object") { __sa_store_i64(out_count, Object.keys(v).length); return 0; }
                \\  return 1;
                \\}
                \\
            );
            return;
        }
        // Streaming JSON writer (mirror sa_json_writer_* in sa_std.zig).
        // Only minified whitespace is supported exactly (all tsgosa demos
        // use it; native itself crashes on indented shapes, so non-zero
        // whitespace fails loudly rather than emitting wrong bytes).
        if (std.mem.eql(u8, fsig.name, "sa_json_writer_new")) {
            try writer.writeAll(
                \\function sa_json_writer_new(whitespace, e_null, e_arr, esc_uni, e_nonport, out_handle) {
                \\  __sa_store_i64(out_handle, 0n);
                \\  if (__sa_num(whitespace) !== 0) return 1;
                \\  const h = __sa_jsonwriternext++;
                \\  __sa_jsonwriters.set(h, { parts: [], stack: [], root_done: false, result: null, esc_uni: __sa_num(esc_uni) !== 0 });
                \\  __sa_store_i64(out_handle, BigInt(h));
                \\  return 0;
                \\}
                \\
            );
            return;
        }
        if (std.mem.eql(u8, fsig.name, "sa_json_writer_free")) {
            try writer.writeAll(
                \\function sa_json_writer_free(writer) { __sa_jsonwriters.delete(__sa_num(writer)); return 0; }
                \\
            );
            return;
        }
        if (std.mem.eql(u8, fsig.name, "sa_json_writer_begin_object")) {
            try writer.writeAll(
                \\function sa_json_writer_begin_object(writer) {
                \\  const w = __sa_jsonwriters.get(__sa_num(writer));
                \\  if (w === undefined) return 2;
                \\  return __sa_jw_begin(w, '{');
                \\}
                \\
            );
            return;
        }
        if (std.mem.eql(u8, fsig.name, "sa_json_writer_end_object")) {
            try writer.writeAll(
                \\function sa_json_writer_end_object(writer) {
                \\  const w = __sa_jsonwriters.get(__sa_num(writer));
                \\  if (w === undefined) return 2;
                \\  return __sa_jw_end(w, '}');
                \\}
                \\
            );
            return;
        }
        if (std.mem.eql(u8, fsig.name, "sa_json_writer_begin_array")) {
            try writer.writeAll(
                \\function sa_json_writer_begin_array(writer) {
                \\  const w = __sa_jsonwriters.get(__sa_num(writer));
                \\  if (w === undefined) return 2;
                \\  return __sa_jw_begin(w, '[');
                \\}
                \\
            );
            return;
        }
        if (std.mem.eql(u8, fsig.name, "sa_json_writer_end_array")) {
            try writer.writeAll(
                \\function sa_json_writer_end_array(writer) {
                \\  const w = __sa_jsonwriters.get(__sa_num(writer));
                \\  if (w === undefined) return 2;
                \\  return __sa_jw_end(w, ']');
                \\}
                \\
            );
            return;
        }
        if (std.mem.eql(u8, fsig.name, "sa_json_writer_object_field")) {
            try writer.writeAll(
                \\function sa_json_writer_object_field(writer, key_ptr, key_len) {
                \\  const w = __sa_jsonwriters.get(__sa_num(writer));
                \\  if (w === undefined) return 2;
                \\  return __sa_jw_field(w, __sa_mem_bytes(key_ptr, key_len));
                \\}
                \\
            );
            return;
        }
        if (std.mem.eql(u8, fsig.name, "sa_json_writer_field_string")) {
            try writer.writeAll(
                \\function sa_json_writer_field_string(writer, key_ptr, key_len, data_ptr, data_len) {
                \\  const w = __sa_jsonwriters.get(__sa_num(writer));
                \\  if (w === undefined) return 2;
                \\  const rc = __sa_jw_field(w, __sa_mem_bytes(key_ptr, key_len));
                \\  if (rc !== 0) return rc;
                \\  w.parts.push(__sa_json_quote(__sa_mem_bytes(data_ptr, data_len), w.esc_uni));
                \\  if (w.stack.length === 0) w.root_done = true;
                \\  return 0;
                \\}
                \\
            );
            return;
        }
        if (std.mem.eql(u8, fsig.name, "sa_json_writer_field_bool")) {
            try writer.writeAll(
                \\function sa_json_writer_field_bool(writer, key_ptr, key_len, value) {
                \\  const w = __sa_jsonwriters.get(__sa_num(writer));
                \\  if (w === undefined) return 2;
                \\  const rc = __sa_jw_field(w, __sa_mem_bytes(key_ptr, key_len));
                \\  if (rc !== 0) return rc;
                \\  w.parts.push(__sa_num(value) !== 0 ? "true" : "false");
                \\  if (w.stack.length === 0) w.root_done = true;
                \\  return 0;
                \\}
                \\
            );
            return;
        }
        if (std.mem.eql(u8, fsig.name, "sa_json_writer_field_i64")) {
            try writer.writeAll(
                \\function sa_json_writer_field_i64(writer, key_ptr, key_len, value) {
                \\  const w = __sa_jsonwriters.get(__sa_num(writer));
                \\  if (w === undefined) return 2;
                \\  const rc = __sa_jw_field(w, __sa_mem_bytes(key_ptr, key_len));
                \\  if (rc !== 0) return rc;
                \\  w.parts.push(BigInt.asIntN(64, BigInt(__sa_num(value))).toString(10));
                \\  if (w.stack.length === 0) w.root_done = true;
                \\  return 0;
                \\}
                \\
            );
            return;
        }
        if (std.mem.eql(u8, fsig.name, "sa_json_writer_field_f64")) {
            try writer.writeAll(
                \\function sa_json_writer_field_f64(writer, key_ptr, key_len, value) {
                \\  const w = __sa_jsonwriters.get(__sa_num(writer));
                \\  if (w === undefined) return 2;
                \\  const rc = __sa_jw_field(w, __sa_mem_bytes(key_ptr, key_len));
                \\  if (rc !== 0) return rc;
                \\  w.parts.push(__sa_json_f64_str(value));
                \\  if (w.stack.length === 0) w.root_done = true;
                \\  return 0;
                \\}
                \\
            );
            return;
        }
        if (std.mem.eql(u8, fsig.name, "sa_json_writer_field_null")) {
            try writer.writeAll(
                \\function sa_json_writer_field_null(writer, key_ptr, key_len) {
                \\  const w = __sa_jsonwriters.get(__sa_num(writer));
                \\  if (w === undefined) return 2;
                \\  const rc = __sa_jw_field(w, __sa_mem_bytes(key_ptr, key_len));
                \\  if (rc !== 0) return rc;
                \\  w.parts.push("null");
                \\  if (w.stack.length === 0) w.root_done = true;
                \\  return 0;
                \\}
                \\
            );
            return;
        }
        if (std.mem.eql(u8, fsig.name, "sa_json_writer_write_bool")) {
            try writer.writeAll(
                \\function sa_json_writer_write_bool(writer, value) {
                \\  const w = __sa_jsonwriters.get(__sa_num(writer));
                \\  if (w === undefined) return 2;
                \\  return __sa_jw_scalar(w, __sa_num(value) !== 0 ? "true" : "false");
                \\}
                \\
            );
            return;
        }
        if (std.mem.eql(u8, fsig.name, "sa_json_writer_write_i64")) {
            try writer.writeAll(
                \\function sa_json_writer_write_i64(writer, value) {
                \\  const w = __sa_jsonwriters.get(__sa_num(writer));
                \\  if (w === undefined) return 2;
                \\  return __sa_jw_scalar(w, BigInt.asIntN(64, BigInt(__sa_num(value))).toString(10));
                \\}
                \\
            );
            return;
        }
        if (std.mem.eql(u8, fsig.name, "sa_json_writer_write_f64")) {
            try writer.writeAll(
                \\function sa_json_writer_write_f64(writer, value) {
                \\  const w = __sa_jsonwriters.get(__sa_num(writer));
                \\  if (w === undefined) return 2;
                \\  return __sa_jw_scalar(w, __sa_json_f64_str(value));
                \\}
                \\
            );
            return;
        }
        if (std.mem.eql(u8, fsig.name, "sa_json_writer_write_string")) {
            try writer.writeAll(
                \\function sa_json_writer_write_string(writer, data_ptr, data_len) {
                \\  const w = __sa_jsonwriters.get(__sa_num(writer));
                \\  if (w === undefined) return 2;
                \\  return __sa_jw_scalar(w, __sa_json_quote(__sa_mem_bytes(data_ptr, data_len), w.esc_uni));
                \\}
                \\
            );
            return;
        }
        if (std.mem.eql(u8, fsig.name, "sa_json_writer_write_null")) {
            try writer.writeAll(
                \\function sa_json_writer_write_null(writer) {
                \\  const w = __sa_jsonwriters.get(__sa_num(writer));
                \\  if (w === undefined) return 2;
                \\  return __sa_jw_scalar(w, "null");
                \\}
                \\
            );
            return;
        }
        if (std.mem.eql(u8, fsig.name, "sa_json_writer_finish")) {
            try writer.writeAll(
                \\function sa_json_writer_finish(writer, out_handle) {
                \\  __sa_store_i64(out_handle, 0n);
                \\  const w = __sa_jsonwriters.get(__sa_num(writer));
                \\  if (w === undefined) return 2;
                \\  if (w.result !== null) { __sa_store_i64(out_handle, BigInt(w.result)); return 0; }
                \\  if (!w.root_done || w.stack.length !== 0) return 1;
                \\  const bytes = new globalThis.TextEncoder().encode(w.parts.join(""));
                \\  const h = __sa_jsonbufnext++;
                \\  __sa_jsonbufs.set(h, bytes);
                \\  w.result = h;
                \\  __sa_store_i64(out_handle, BigInt(h));
                \\  return 0;
                \\}
                \\
            );
            return;
        }
        if (std.mem.eql(u8, fsig.name, "sa_json_writer_finish_buffer")) {
            try writer.writeAll(
                \\function sa_json_writer_finish_buffer(writer) {
                \\  const w = __sa_jsonwriters.get(__sa_num(writer));
                \\  if (w === undefined) return 0n;
                \\  if (w.result !== null) return BigInt(w.result);
                \\  if (!w.root_done || w.stack.length !== 0) return 0n;
                \\  const bytes = new globalThis.TextEncoder().encode(w.parts.join(""));
                \\  const h = __sa_jsonbufnext++;
                \\  __sa_jsonbufs.set(h, bytes);
                \\  w.result = h;
                \\  return BigInt(h);
                \\}
                \\
            );
            return;
        }
        if (std.mem.eql(u8, fsig.name, "sa_json_buffer_data")) {
            try writer.writeAll(
                \\function sa_json_buffer_data(handle) {
                \\  const b = __sa_jsonbufs.get(__sa_num(handle));
                \\  if (b === undefined) return 0;
                \\  const p = __sa_alloc(b.length);
                \\  __sa_u8.set(b, p);
                \\  return p;
                \\}
                \\
            );
            return;
        }
        if (std.mem.eql(u8, fsig.name, "sa_json_buffer_len")) {
            try writer.writeAll(
                \\function sa_json_buffer_len(handle) {
                \\  const b = __sa_jsonbufs.get(__sa_num(handle));
                \\  return (b === undefined) ? 0n : BigInt(b.length);
                \\}
                \\
            );
            return;
        }
        if (std.mem.eql(u8, fsig.name, "sa_json_buffer_free")) {
            try writer.writeAll(
                \\function sa_json_buffer_free(handle) { __sa_jsonbufs.delete(__sa_num(handle)); return 0; }
                \\
            );
            return;
        }
        // Date set-field (mirror sa_time_set_field in sa_std.zig; fields
        // 0..6 = year/month0/date/hours/minutes/seconds/ms, else identity).
        if (std.mem.eql(u8, fsig.name, "sa_time_set_field")) {
            try writer.writeAll(
                \\function sa_time_set_field(ms, field, value) {
                \\  const c = __sa_civil(ms);
                \\  let y = c[0], mo = c[1], d = c[2];
                \\  let tod = c[3] * 3600000n + c[4] * 60000n + c[5] * 1000n + c[6];
                \\  const v = BigInt.asIntN(64, BigInt(__sa_num(value)));
                \\  const f = __sa_num(field);
                \\  if (f === 0) y = v;
                \\  else if (f === 1) { const tm = y * 12n + v; y = __sa_divfloor(tm, 12n); mo = __sa_modfloor(tm, 12n) + 1n; }
                \\  else if (f === 2) d = v;
                \\  else if (f === 3) tod = v * 3600000n + __sa_modfloor(tod, 3600000n);
                \\  else if (f === 4) tod = (tod - __sa_modfloor(tod, 3600000n)) + v * 60000n + __sa_modfloor(tod, 60000n);
                \\  else if (f === 5) tod = (tod - __sa_modfloor(tod, 60000n)) + v * 1000n + __sa_modfloor(tod, 1000n);
                \\  else if (f === 6) tod = tod - __sa_modfloor(tod, 1000n) + v;
                \\  else return BigInt.asIntN(64, (typeof ms === "bigint") ? ms : BigInt(Math.trunc(+ms)));
                \\  const tm2 = y * 12n + (mo - 1n);
                \\  const y2 = __sa_divfloor(tm2, 12n);
                \\  const m2 = __sa_modfloor(tm2, 12n) + 1n;
                \\  const yp = m2 <= 2n ? y2 - 1n : y2;
                \\  const era = yp >= 0n ? __sa_divfloor(yp, 400n) : __sa_divfloor(yp - 399n, 400n);
                \\  const yoe = yp - era * 400n;
                \\  const mp = __sa_modfloor(m2 - 3n, 12n);
                \\  const doy = __sa_divfloor(153n * mp + 2n, 5n);
                \\  const doe = yoe * 365n + __sa_divfloor(yoe, 4n) - __sa_divfloor(yoe, 100n) + doy;
                \\  const days = era * 146097n + doe - 719468n + (d - 1n);
                \\  const total = days + __sa_divfloor(tod, 86400000n);
                \\  const norm = tod - __sa_divfloor(tod, 86400000n) * 86400000n;
                \\  return BigInt.asIntN(64, (total * 86400n) * 1000n + norm);
                \\}
                \\
            );
            return;
        }
        // Node/Deno plugin shims (mirror sa_plugin_node/deno externs).
        // Implemented over the host Node.js builtins (the JS backend runs
        // on node): node:path POSIX flavor, node:querystring/punycode,
        // node:crypto, node:fs. Results materialize into linear memory;
        // nonlocal nonzero statuses fail the same `ne st, 0` gates.
        if (std.mem.eql(u8, fsig.name, "sa_std_fs_exists")) {
            try writer.writeAll(
                \\function sa_std_fs_exists(path_ptr, path_len) {
                \\  // Status-code shape (mirror native): 0 exists,
                \\  // NOT_FOUND(3) missing, INVALID_ARGUMENT(1) on bad input.
                \\  const fs = __sa_node_builtin("node:fs");
                \\  if (fs === null) return 1;
                \\  try {
                \\    const p = new globalThis.TextDecoder().decode(__sa_mem_bytes(path_ptr, path_len));
                \\    return fs.existsSync(p) ? 0 : 3;
                \\  } catch (e) { return 1; }
                \\}
                \\
            );
            return;
        }
        if (std.mem.eql(u8, fsig.name, "sa_node_plugin_path_normalize")) {
            try writer.writeAll(
                \\function sa_node_plugin_path_normalize(path_ptr, path_len, out_ptr, out_len) {
                \\  const pathmod = __sa_node_builtin("node:path");
                \\  if (pathmod === null) return 1;
                \\  try {
                \\    const s = new globalThis.TextDecoder().decode(__sa_mem_bytes(path_ptr, path_len));
                \\    return __sa_node_emit(out_ptr, out_len, new globalThis.TextEncoder().encode(pathmod.posix.normalize(s)));
                \\  } catch (e) { return 1; }
                \\}
                \\
            );
            return;
        }
        if (std.mem.eql(u8, fsig.name, "sa_node_plugin_path_dirname")) {
            try writer.writeAll(
                \\function sa_node_plugin_path_dirname(path_ptr, path_len, out_ptr, out_len) {
                \\  const pathmod = __sa_node_builtin("node:path");
                \\  if (pathmod === null) return 1;
                \\  try {
                \\    const s = new globalThis.TextDecoder().decode(__sa_mem_bytes(path_ptr, path_len));
                \\    return __sa_node_emit(out_ptr, out_len, new globalThis.TextEncoder().encode(pathmod.posix.dirname(s)));
                \\  } catch (e) { return 1; }
                \\}
                \\
            );
            return;
        }
        if (std.mem.eql(u8, fsig.name, "sa_node_plugin_path_extname")) {
            try writer.writeAll(
                \\function sa_node_plugin_path_extname(path_ptr, path_len, out_ptr, out_len) {
                \\  const pathmod = __sa_node_builtin("node:path");
                \\  if (pathmod === null) return 1;
                \\  try {
                \\    const s = new globalThis.TextDecoder().decode(__sa_mem_bytes(path_ptr, path_len));
                \\    return __sa_node_emit(out_ptr, out_len, new globalThis.TextEncoder().encode(pathmod.posix.extname(s)));
                \\  } catch (e) { return 1; }
                \\}
                \\
            );
            return;
        }
        if (std.mem.eql(u8, fsig.name, "sa_node_plugin_path_is_absolute")) {
            try writer.writeAll(
                \\function sa_node_plugin_path_is_absolute(path_ptr, path_len, out_bool) {
                \\  const pathmod = __sa_node_builtin("node:path");
                \\  if (pathmod === null) return 1;
                \\  try {
                \\    const s = new globalThis.TextDecoder().decode(__sa_mem_bytes(path_ptr, path_len));
                \\    __sa_store_i32(out_bool, pathmod.posix.isAbsolute(s) ? 1 : 0);
                \\    return 0;
                \\  } catch (e) { return 1; }
                \\}
                \\
            );
            return;
        }
        if (std.mem.eql(u8, fsig.name, "sa_node_plugin_path_join")) {
            try writer.writeAll(
                \\function sa_node_plugin_path_join(argv_ptr, argc, out_ptr, out_len) {
                \\  const pathmod = __sa_node_builtin("node:path");
                \\  if (pathmod === null) return 1;
                \\  try {
                \\    const base = __sa_addr(argv_ptr);
                \\    const n = __sa_num(argc);
                \\    const parts = [];
                \\    for (let i = 0; i < n; i++) {
                \\      const p = Number(__sa_view.getBigInt64(base + i * 16, true));
                \\      const l = Number(__sa_view.getBigUint64(base + i * 16 + 8, true));
                \\      parts.push(new globalThis.TextDecoder().decode(__sa_mem_bytes(p, l)));
                \\    }
                \\    return __sa_node_emit(out_ptr, out_len, new globalThis.TextEncoder().encode(pathmod.posix.join(...parts)));
                \\  } catch (e) { return 1; }
                \\}
                \\
            );
            return;
        }
        if (std.mem.eql(u8, fsig.name, "sa_node_plugin_punycode_encode")) {
            try writer.writeAll(
                \\function sa_node_plugin_punycode_encode(data_ptr, data_len, out_ptr, out_len) {
                \\  const pu = __sa_node_builtin("punycode");
                \\  if (pu === null) return 1;
                \\  try {
                \\    const s = new globalThis.TextDecoder().decode(__sa_mem_bytes(data_ptr, data_len));
                \\    return __sa_node_emit(out_ptr, out_len, new globalThis.TextEncoder().encode(pu.encode(s)));
                \\  } catch (e) { return 1; }
                \\}
                \\
            );
            return;
        }
        if (std.mem.eql(u8, fsig.name, "sa_node_plugin_punycode_decode")) {
            try writer.writeAll(
                \\function sa_node_plugin_punycode_decode(data_ptr, data_len, out_ptr, out_len) {
                \\  const pu = __sa_node_builtin("punycode");
                \\  if (pu === null) return 1;
                \\  try {
                \\    const s = new globalThis.TextDecoder().decode(__sa_mem_bytes(data_ptr, data_len));
                \\    return __sa_node_emit(out_ptr, out_len, new globalThis.TextEncoder().encode(pu.decode(s)));
                \\  } catch (e) { return 1; }
                \\}
                \\
            );
            return;
        }
        if (std.mem.eql(u8, fsig.name, "sa_node_plugin_querystring_escape")) {
            try writer.writeAll(
                \\function sa_node_plugin_querystring_escape(data_ptr, data_len, out_ptr, out_len) {
                \\  const qs = __sa_node_builtin("node:querystring");
                \\  if (qs === null) return 1;
                \\  try {
                \\    const s = new globalThis.TextDecoder().decode(__sa_mem_bytes(data_ptr, data_len));
                \\    return __sa_node_emit(out_ptr, out_len, new globalThis.TextEncoder().encode(qs.escape(s)));
                \\  } catch (e) { return 1; }
                \\}
                \\
            );
            return;
        }
        if (std.mem.eql(u8, fsig.name, "sa_node_plugin_querystring_unescape")) {
            try writer.writeAll(
                \\function sa_node_plugin_querystring_unescape(data_ptr, data_len, out_ptr, out_len) {
                \\  const qs = __sa_node_builtin("node:querystring");
                \\  if (qs === null) return 1;
                \\  try {
                \\    const s = new globalThis.TextDecoder().decode(__sa_mem_bytes(data_ptr, data_len));
                \\    return __sa_node_emit(out_ptr, out_len, new globalThis.TextEncoder().encode(qs.unescape(s)));
                \\  } catch (e) { return 1; }
                \\}
                \\
            );
            return;
        }
        if (std.mem.eql(u8, fsig.name, "sa_node_plugin_buffer_concat")) {
            try writer.writeAll(
                \\function sa_node_plugin_buffer_concat(argv_ptr, argc, out_ptr, out_len) {
                \\  try {
                \\    const base = __sa_addr(argv_ptr);
                \\    const n = __sa_num(argc);
                \\    let total = 0;
                \\    const parts = [];
                \\    for (let i = 0; i < n; i++) {
                \\      const p = Number(__sa_view.getBigInt64(base + i * 16, true));
                \\      const l = Number(__sa_view.getBigUint64(base + i * 16 + 8, true));
                \\      const b = __sa_mem_bytes(p, l);
                \\      parts.push(b);
                \\      total += b.length;
                \\    }
                \\    const out = new Uint8Array(total);
                \\    let w = 0;
                \\    for (const b of parts) { out.set(b, w); w += b.length; }
                \\    return __sa_node_emit(out_ptr, out_len, out);
                \\  } catch (e) { return 1; }
                \\}
                \\
            );
            return;
        }
        if (std.mem.eql(u8, fsig.name, "sa_node_plugin_crypto_random_bytes")) {
            try writer.writeAll(
                \\function sa_node_plugin_crypto_random_bytes(size, out_ptr) {
                \\  const c = __sa_node_builtin("node:crypto");
                \\  if (c === null) return 1;
                \\  try {
                \\    const n = __sa_num(size);
                \\    const b = c.randomBytes(n);
                \\    const p = __sa_alloc(b.length);
                \\    __sa_u8.set(b, p);
                \\    __sa_store_i64(out_ptr, p);
                \\    return 0;
                \\  } catch (e) { return 1; }
                \\}
                \\
            );
            return;
        }
        if (std.mem.eql(u8, fsig.name, "sa_node_plugin_crypto_hash")) {
            try writer.writeAll(
                \\function sa_node_plugin_crypto_hash(algo_ptr, algo_len, data_ptr, data_len, out_ptr, out_len) {
                \\  const c = __sa_node_builtin("node:crypto");
                \\  if (c === null) return 1;
                \\  try {
                \\    const algo = new globalThis.TextDecoder().decode(__sa_mem_bytes(algo_ptr, algo_len)).toLowerCase();
                \\    if (algo !== "sha256" && algo !== "sha512" && algo !== "sha1" && algo !== "md5") return 2;
                \\    const h = c.createHash(algo);
                \\    h.update(__sa_mem_bytes(data_ptr, data_len));
                \\    return __sa_node_emit(out_ptr, out_len, new globalThis.TextEncoder().encode(h.digest("hex")));
                \\  } catch (e) { return 2; }
                \\}
                \\
            );
            return;
        }
        if (std.mem.eql(u8, fsig.name, "sa_deno_plugin_btoa")) {
            try writer.writeAll(
                \\function sa_deno_plugin_btoa(data_ptr, data_len, out_ptr, out_len) {
                \\  try {
                \\    const b = __sa_mem_bytes(data_ptr, data_len);
                \\    let s = "";
                \\    for (let i = 0; i < b.length; i++) s += String.fromCharCode(b[i]);
                \\    return __sa_node_emit(out_ptr, out_len, new globalThis.TextEncoder().encode(globalThis.btoa(s)));
                \\  } catch (e) { return 1; }
                \\}
                \\
            );
            return;
        }
        if (std.mem.eql(u8, fsig.name, "sa_deno_plugin_atob")) {
            try writer.writeAll(
                \\function sa_deno_plugin_atob(data_ptr, data_len, out_ptr, out_len) {
                \\  try {
                \\    const s = new globalThis.TextDecoder().decode(__sa_mem_bytes(data_ptr, data_len));
                \\    const bin = globalThis.atob(s);
                \\    const out = new Uint8Array(bin.length);
                \\    for (let i = 0; i < bin.length; i++) out[i] = bin.charCodeAt(i) & 0xff;
                \\    return __sa_node_emit(out_ptr, out_len, out);
                \\  } catch (e) { return 1; }
                \\}
                \\
            );
            return;
        }
        if (std.mem.eql(u8, fsig.name, "sa_deno_plugin_read_text_file")) {
            try writer.writeAll(
                \\function sa_deno_plugin_read_text_file(path_ptr, path_len, out_ptr, out_len) {
                \\  const fs = __sa_node_builtin("node:fs");
                \\  if (fs === null) return 1;
                \\  try {
                \\    const p = new globalThis.TextDecoder().decode(__sa_mem_bytes(path_ptr, path_len));
                \\    return __sa_node_emit(out_ptr, out_len, new globalThis.TextEncoder().encode(fs.readFileSync(p, "utf8")));
                \\  } catch (e) { return 1; }
                \\}
                \\
            );
            return;
        }
        if (std.mem.eql(u8, fsig.name, "sa_deno_plugin_write_text_file")) {
            try writer.writeAll(
                \\function sa_deno_plugin_write_text_file(path_ptr, path_len, data_ptr, data_len) {
                \\  const fs = __sa_node_builtin("node:fs");
                \\  if (fs === null) return 1;
                \\  try {
                \\    const p = new globalThis.TextDecoder().decode(__sa_mem_bytes(path_ptr, path_len));
                \\    fs.writeFileSync(p, __sa_mem_bytes(data_ptr, data_len));
                \\    return 0;
                \\  } catch (e) { return 1; }
                \\}
                \\
            );
            return;
        }
        if (std.mem.eql(u8, fsig.name, "sa_deno_plugin_mkdir")) {
            try writer.writeAll(
                \\function sa_deno_plugin_mkdir(path_ptr, path_len, recursive) {
                \\  const fs = __sa_node_builtin("node:fs");
                \\  if (fs === null) return 1;
                \\  try {
                \\    const p = new globalThis.TextDecoder().decode(__sa_mem_bytes(path_ptr, path_len));
                \\    fs.mkdirSync(p, { recursive: __sa_num(recursive) !== 0 });
                \\    return 0;
                \\  } catch (e) { return 1; }
                \\}
                \\
            );
            return;
        }
        if (std.mem.eql(u8, fsig.name, "sa_deno_plugin_remove")) {
            try writer.writeAll(
                \\function sa_deno_plugin_remove(path_ptr, path_len, recursive) {
                \\  const fs = __sa_node_builtin("node:fs");
                \\  if (fs === null) return 1;
                \\  try {
                \\    const p = new globalThis.TextDecoder().decode(__sa_mem_bytes(path_ptr, path_len));
                \\    if (__sa_num(recursive) !== 0) { fs.rmSync(p, { recursive: true }); return 0; }
                \\    try { fs.unlinkSync(p); return 0; } catch (e) {}
                \\    fs.rmdirSync(p);
                \\    return 0;
                \\  } catch (e) { return 1; }
                \\}
                \\
            );
            return;
        }
        if (std.mem.eql(u8, fsig.name, "sa_node_plugin_free_buffer")) {
            try writer.writeAll(
                \\function sa_node_plugin_free_buffer(ptr, len) { __sa_free(ptr); return 0; }
                \\
            );
            return;
        }
        if (std.mem.eql(u8, fsig.name, "sa_deno_plugin_free_buffer")) {
            try writer.writeAll(
                \\function sa_deno_plugin_free_buffer(ptr, len) { __sa_free(ptr); return 0; }
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
    try writer.writeAll("  } finally { const __f = __sa_fstack.pop(); for (let __k = 0; __k < __f.length; __k++) __sa_sfree(__f[__k]); }\n}\n");
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
        try writer.writeAll("\nmodule.exports = { __sa_memory, __sa_view, __sa_u8, __sa_alloc, __sa_free, __sa_salloc, __sa_sfree, __sa_mem_used");
        for (tasks) |task| {
            if (task.kind == .extern_decl) continue;
            const fsig = verified.function_sigs[task.fsig_index];
            try writer.writeAll(", ");
            try jsFuncName(writer, fsig.name);
        }
        try writer.writeAll(" };\n");
        if (has_main) try writer.writeAll("if (require.main === module) { main(); }\n");
    } else {
        try writer.writeAll("\nexport { __sa_memory, __sa_view, __sa_u8, __sa_alloc, __sa_free, __sa_salloc, __sa_sfree, __sa_mem_used };\n");
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
