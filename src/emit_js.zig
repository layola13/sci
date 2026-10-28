const std = @import("std");

const emit_options = @import("emit_options.zig");
const inst = @import("common/instruction.zig");
const sig = @import("common/signature.zig");
const call = @import("referee/call.zig");
const const_decl = @import("common/const_decl.zig");
const sio = @import("sio");

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
///   WARNING: the first segment is only a label — the member is
///   resolved on the MODULE namespace object, not on a named export.
///   `"three#MathUtils.clamp"` therefore calls
///   `<three namespace>.clamp`, NOT `MathUtils.clamp` (BU d.ts2sai
///   evidence: builds RC=0, throws TypeError at runtime). Members of
///   named export objects are NOT expressible in this form; use a
///   named import of the member's owner or generated glue instead.
///
/// Handle shapes (JS value handles; see DESIGN.md of the js-handle line):
/// colon-separated shape keywords may follow the target segment:
/// - `"spec#Name:ctor"`: construct with `new`, return the object as a
///   blob_handle into the runtime handle table. Namespace targets
///   (`"spec#ns.Name:ctor"`) are REJECTED at build time: with the
///   namespace semantics above, `new alias.Name` would construct a
///   member of the module namespace while the spelling suggests a
///   class nested in a named export — the same silent mis-shape as
///   the call form. Bind the class by its top-level named export.
/// - `"@handle#name:method"`: first extern param is a blob_handle
///   self; calls `self.name(...)`. No import is emitted. The spec is
///   the reserved marker `@handle` (the flattener's npm_bind line
///   parser rejects a truly empty spec before emit_js ever runs).
/// - `"@handle#name:get"`: first extern param is a blob_handle
///   self; reads the property `self.name` (no further params).
/// - `:bytes` / `:f32view` modifiers (combinable with any shape): the
///   extern's adjacent (ptr, len) pairs marshal as zero-copy Uint8Array /
///   Float32Array views over linear memory instead of UTF8 strings.
/// String returns are signature-driven (orthogonal to shape): an extern
/// whose params end with (ptr, integer, ptr) and that returns an integer
/// is a string-out binding — the JS string is written back into linear
/// memory per the (out_ptr, out_cap, &out_len) convention.
const NpmShape = enum { call, ctor, method, get };
const NpmBytesView = enum { none, u8, f32 };

const NpmImport = struct {
    spec: []const u8,
    export_name: []const u8,
    member: ?[]const u8,
    alias: []const u8,
    extern_name: []const u8,
    shape: NpmShape = .call,
    bytes_view: NpmBytesView = .none,
};

/// Whether an npm-bound extern with this signature uses the string-out
/// marshaling path: params end with (out_ptr: ptr, out_cap: integer,
/// out_len: ptr) and the return is an integer status. Ctor bindings are
/// excluded (they return handles). Shared by the wrapper emitter and by
/// the runtime-chunk gate so the two never disagree.
fn npmStrOut(fsig: sig.FunctionSig, shape: NpmShape) bool {
    if (shape == .ctor) return false;
    const params = fsig.params;
    if (params.len < 3) return false;
    const n = params.len;
    return params[n - 3].ty == .ptr and isNpmIntType(params[n - 2].ty) and
        params[n - 1].ty == .ptr and isNpmIntType(fsig.return_ty);
}

fn collectNpmImports(
    allocator: std.mem.Allocator,
    verified: anytype,
    tasks: []const FuncTask,
    npm_binds: *const std.StringHashMap([]const u8),
) ![]NpmImport {
    var out = std.array_list.Managed(NpmImport).init(allocator);
    errdefer out.deinit();
    for (tasks) |task| {
        if (task.kind != .extern_decl) continue;
        const fsig = verified.function_sigs[task.fsig_index];
        const binding = npm_binds.get(fsig.name) orelse continue;
        const hash = std.mem.lastIndexOfScalar(u8, binding, '#') orelse return JsEmitError.UnsupportedNpmBinding;
        if (hash + 1 >= binding.len) return JsEmitError.UnsupportedNpmBinding;
        const spec = binding[0..hash];
        const rest = binding[hash + 1 ..];
        // Shape keywords: colon-separated suffixes after the target
        // segment (`"three#Vector3:ctor"`, `"#length:method"`,
        // `"spec#fn:bytes"`). Unknown/duplicated/conflicting keywords
        // are rejected at build time.
        var shape: NpmShape = .call;
        var bytes_view: NpmBytesView = .none;
        var target = rest;
        if (std.mem.indexOfScalar(u8, rest, ':')) |colon| {
            target = rest[0..colon];
            var seen_shape = false;
            var kw_it = std.mem.splitScalar(u8, rest[colon + 1 ..], ':');
            while (kw_it.next()) |kw| {
                if (kw.len == 0) return JsEmitError.UnsupportedNpmBinding;
                if (std.mem.eql(u8, kw, "ctor") or std.mem.eql(u8, kw, "method") or std.mem.eql(u8, kw, "get")) {
                    if (seen_shape) return JsEmitError.UnsupportedNpmBinding;
                    seen_shape = true;
                    shape = if (std.mem.eql(u8, kw, "ctor")) .ctor else if (std.mem.eql(u8, kw, "method")) .method else .get;
                } else if (std.mem.eql(u8, kw, "bytes")) {
                    if (bytes_view != .none) return JsEmitError.UnsupportedNpmBinding;
                    bytes_view = .u8;
                } else if (std.mem.eql(u8, kw, "f32view")) {
                    if (bytes_view != .none) return JsEmitError.UnsupportedNpmBinding;
                    bytes_view = .f32;
                } else {
                    return JsEmitError.UnsupportedNpmBinding;
                }
            }
        }
        // Method/get bindings name a member on a handle value: nothing
        // is imported, and the target is a single identifier. The spec
        // must be the reserved marker "@handle" — a truly empty spec
        // ("#name:method") is rejected earlier by the flattener's
        // npm_bind line parser (shared layer, out of this line's edit
        // domain), so the marker keeps the grammar inside emit_js.
        if (shape == .method or shape == .get) {
            if (!std.mem.eql(u8, spec, "@handle")) return JsEmitError.UnsupportedNpmBinding;
            if (!isNpmExportIdent(target)) return JsEmitError.UnsupportedNpmBinding;
        } else if (spec.len == 0 or std.mem.eql(u8, spec, "@handle")) {
            return JsEmitError.UnsupportedNpmBinding;
        }
        const export_name = target;
        // Namespace form `"spec#ns.member"`: split one dot level; both
        // sides must be plain JS identifiers (deeper paths rejected).
        var member: ?[]const u8 = null;
        var export_id = export_name;
        if (shape == .method or shape == .get) {
            // Single-identifier target already validated above.
        } else if (std.mem.indexOfScalar(u8, export_name, '.')) |dot| {
            if (dot == 0 or dot + 1 >= export_name.len) return JsEmitError.UnsupportedNpmBinding;
            if (std.mem.indexOfScalarPos(u8, export_name, dot + 1, '.') != null) return JsEmitError.UnsupportedNpmBinding;
            const ns = export_name[0..dot];
            member = export_name[dot + 1 ..];
            if (!isNpmExportIdent(ns) or !isNpmExportIdent(member.?)) return JsEmitError.UnsupportedNpmBinding;
            export_id = ns;
            // Ctor over a namespace target is rejected: the emitted
            // `new alias.member(...)` would construct a member of the
            // module namespace object, while the spelling reads as a
            // class nested inside a named export — a silent mis-shape
            // (BU evidence on the call form: "three#MathUtils.clamp").
            // Bind the class by its top-level named export instead.
            if (shape == .ctor) return JsEmitError.UnsupportedNpmBinding;
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
            .shape = shape,
            .bytes_view = bytes_view,
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

/// Emits the JS wrapper for one npm-bound extern. Marshaling:
/// - numeric params via `__sa_num`, adjacent (ptr, integer-length)
///   params as one UTF8 string (or a zero-copy TypedArray view under
///   the `:bytes` / `:f32view` modifiers), lone ptr params as raw
///   addresses, blob_handle params decoded through the handle table.
/// - ctor shape constructs with `new` and returns a fresh handle;
///   method/get shapes take the first param as the handle self.
/// - a trailing (out_ptr, out_cap, out_len) param trio plus an integer
///   return selects the string-out path (see npmStrOut).
/// - returns: numeric (checked), ptr (raw number), blob_handle (result
///   registered in the handle table), or void (result discarded; a
///   Promise result traps in every path — bindings are synchronous).
/// Anything outside these shapes is rejected at build time with
/// UnsupportedNpmBinding so mis-marshals fail loudly instead of
/// corrupting linear memory at runtime.
fn emitNpmWrapper(
    writer: anytype,
    fsig: sig.FunctionSig,
    npm_item: NpmImport,
    js_opt: JsEmitOptions,
) !void {
    const shape = npm_item.shape;
    const str_out = npmStrOut(fsig, shape);
    const arg_params = if (str_out) fsig.params[0 .. fsig.params.len - 3] else fsig.params;
    // Return-shape validation (build time).
    switch (shape) {
        .ctor => {
            if (fsig.return_ty != .blob_handle) return JsEmitError.UnsupportedNpmBinding;
        },
        .call, .method, .get => {
            if (str_out) {
                // npmStrOut already required an integer status return.
            } else if (fsig.return_ty == .void or fsig.return_ty == .blob_handle or fsig.return_ty == .ptr) {
                // Discarded result / handle registration / raw address.
            } else if (!isNpmNumericType(fsig.return_ty)) {
                return JsEmitError.UnsupportedNpmBinding;
            }
        },
    }
    // Self-handle validation for method/get (build time).
    if (shape == .method or shape == .get) {
        if (arg_params.len == 0 or arg_params[0].ty != .blob_handle) return JsEmitError.UnsupportedNpmBinding;
        if (shape == .get and arg_params.len != 1) return JsEmitError.UnsupportedNpmBinding;
    }
    if (js_opt.format == .esm) try writer.writeAll("export function ") else try writer.writeAll("function ");
    try jsFuncName(writer, fsig.name);
    try writer.writeAll("(");
    for (fsig.params, 0..) |p, idx| {
        if (idx != 0) try writer.writeAll(", ");
        try jsIdent(writer, p.name);
    }
    try writer.writeAll(") {\n");
    if (shape == .method or shape == .get) {
        try writer.writeAll("  const __sa_js_self = __sa_jsh_get(");
        try jsIdent(writer, arg_params[0].name);
        try writer.writeAll(");\n");
    }
    var idx: usize = if (shape == .method or shape == .get) 1 else 0;
    try writer.writeAll("  const __sa_npm_args = [];\n");
    while (idx < arg_params.len) : (idx += 1) {
        const p = arg_params[idx];
        if (p.ty == .ptr and idx + 1 < arg_params.len and isNpmIntType(arg_params[idx + 1].ty)) {
            const len_p = arg_params[idx + 1];
            switch (npm_item.bytes_view) {
                .u8 => try writer.writeAll("  __sa_npm_args.push(__sa_jsh_u8view("),
                .f32 => try writer.writeAll("  __sa_npm_args.push(__sa_jsh_f32view("),
                .none => try writer.writeAll("  __sa_npm_args.push(new globalThis.TextDecoder().decode(__sa_u8.slice("),
            }
            try writer.writeAll("__sa_addr(");
            try jsIdent(writer, p.name);
            if (npm_item.bytes_view == .none) {
                try writer.writeAll("), __sa_addr(");
                try jsIdent(writer, p.name);
                try writer.writeAll(") + __sa_num(");
            } else {
                try writer.writeAll("), ");
            }
            try jsIdent(writer, len_p.name);
            // Close out the marshaling call: string path nests
            // push(decode(slice(addr, addr + num))) (4 parens), view
            // path nests push(view(addr, len)) (2 parens; addr's own
            // paren was closed inline above).
            if (npm_item.bytes_view == .none) {
                try writer.writeAll("))));\n");
            } else {
                try writer.writeAll("));\n");
            }
            idx += 1;
            continue;
        }
        if (p.ty == .blob_handle) {
            try writer.writeAll("  __sa_npm_args.push(__sa_jsh_get(");
            try jsIdent(writer, p.name);
            try writer.writeAll("));\n");
        } else if (p.ty == .ptr) {
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
    switch (shape) {
        .call => {
            try writer.writeAll(npm_item.alias);
            if (npm_item.member) |member| {
                try writer.writeAll(".");
                try writer.writeAll(member);
            }
            try writer.writeAll("(...__sa_npm_args);\n");
        },
        .ctor => {
            try writer.writeAll("new ");
            try writer.writeAll(npm_item.alias);
            if (npm_item.member) |member| {
                try writer.writeAll(".");
                try writer.writeAll(member);
            }
            try writer.writeAll("(...__sa_npm_args);\n");
        },
        .method => {
            try writer.writeAll("__sa_js_self.");
            try writer.writeAll(npm_item.export_name);
            try writer.writeAll("(...__sa_npm_args);\n");
        },
        .get => {
            try writer.writeAll("__sa_js_self.");
            try writer.writeAll(npm_item.export_name);
            try writer.writeAll(";\n");
        },
    }
    if (str_out) {
        const n = fsig.params.len;
        try writer.writeAll("  return __sa_jsh_str_out(__sa_npm_r, ");
        try jsIdent(writer, fsig.params[n - 3].name);
        try writer.writeAll(", ");
        try jsIdent(writer, fsig.params[n - 2].name);
        try writer.writeAll(", ");
        try jsIdent(writer, fsig.params[n - 1].name);
        try writer.writeAll(");\n}\n");
        return;
    }
    switch (shape) {
        .ctor => {
            try writer.writeAll("  return __sa_jsh_new(__sa_npm_r);\n}\n");
            return;
        },
        .call, .method, .get => {},
    }
    if (fsig.return_ty == .blob_handle) {
        try writer.writeAll("  if (__sa_npm_r !== null && (typeof __sa_npm_r === \"object\" || typeof __sa_npm_r === \"function\") && typeof __sa_npm_r.then === \"function\") __sa_trap(\"npm extern returned a Promise: ");
        try jsFuncName(writer, fsig.name);
        try writer.writeAll("\");\n");
        try writer.writeAll("  return __sa_jsh_new(__sa_npm_r);\n}\n");
        return;
    }
    if (fsig.return_ty == .void) {
        try writer.writeAll("  if (__sa_npm_r !== null && (typeof __sa_npm_r === \"object\" || typeof __sa_npm_r === \"function\") && typeof __sa_npm_r.then === \"function\") __sa_trap(\"npm extern returned a Promise: ");
        try jsFuncName(writer, fsig.name);
        try writer.writeAll("\");\n}\n");
        return;
    }
    try writer.writeAll("  if (typeof __sa_npm_r !== \"number\" && typeof __sa_npm_r !== \"bigint\" && typeof __sa_npm_r !== \"boolean\") __sa_trap(\"npm extern returned non-numeric: ");
    try jsFuncName(writer, fsig.name);
    try writer.writeAll("\");\n");
    try writer.writeAll("  return __sa_num(__sa_npm_r);\n}\n");
}

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

const policy_runtime_js =
    \\// ---- sa policy (16_policy phase 1; JS port of sa_policy.zig) ----
    \\// Same policy JSON, same SA_POLICY_* env vars, same audit JSONL shape
    \\// and decision semantics as the native runtime. Lazily initialized on
    \\// first gated call; with no policy configured the backend stays in
    \\// legacy mode (everything allowed), exactly like the native default.
    \\const __sa_policy = (() => {
    \\  let state = null;
    \\  const CATS = ['net', 'fs', 'env', 'run', 'time', 'random'];
    \\  function env(name) {
    \\    try {
    \\      const p = globalThis.process;
    \\      if (p && p.env && typeof p.env[name] === 'string') return p.env[name];
    \\    } catch (e) {}
    \\    return null;
    \\  }
    \\  function fail(msg, code) {
    \\    try { console.error('[sa-policy] ' + msg); } catch (e) {}
    \\    try { globalThis.process.exit(code); } catch (e) {}
    \\    throw new Error(msg);
    \\  }
    \\  function auditPathOf(policy) {
    \\    const f = env('SA_AUDIT_FILE');
    \\    if (f) return f;
    \\    if (policy && typeof policy.audit_sink === 'string' && policy.audit_sink.startsWith('file://')) return policy.audit_sink.slice(7);
    \\    return null;
    \\  }
    \\  function stringList(v) {
    \\    if (!Array.isArray(v)) fail('InvalidPolicy', 2);
    \\    for (const s of v) if (typeof s !== 'string') fail('InvalidPolicy', 2);
    \\    return v.slice();
    \\  }
    \\  function parseCategory(v, category) {
    \\    if (v === null || typeof v !== 'object' || Array.isArray(v)) fail('InvalidPolicy', 2);
    \\    const out = { mode: null, allow: [], read: [], write: [] };
    \\    let hasLists = false;
    \\    for (const k of Object.keys(v)) {
    \\      if (k === 'mode') {
    \\        if (['allow', 'deny', 'allow-list', 'audit', 'ask'].indexOf(v.mode) < 0) fail('InvalidPolicy', 2);
    \\        out.mode = v.mode;
    \\      } else if (k === 'allow') {
    \\        if (category === 'fs' || category === 'time' || category === 'random') fail('InvalidPolicy', 2);
    \\        out.allow = stringList(v.allow); hasLists = true;
    \\      } else if (k === 'read') {
    \\        if (category !== 'fs') fail('InvalidPolicy', 2);
    \\        out.read = stringList(v.read); hasLists = true;
    \\      } else if (k === 'write') {
    \\        if (category !== 'fs') fail('InvalidPolicy', 2);
    \\        out.write = stringList(v.write); hasLists = true;
    \\      } else fail('InvalidPolicy', 2);
    \\    }
    \\    if (out.mode === null) out.mode = hasLists ? 'allow-list' : 'deny';
    \\    return out;
    \\  }
    \\  function parsePolicy(text) {
    \\    let root;
    \\    try { root = JSON.parse(text); } catch (e) { fail('InvalidPolicy', 2); }
    \\    if (root === null || typeof root !== 'object' || Array.isArray(root)) fail('InvalidPolicy', 2);
    \\    const policy = { audit_sink: null };
    \\    for (const k of Object.keys(root)) {
    \\      if (k === 'permissions') {
    \\        const perms = root.permissions;
    \\        if (perms === null || typeof perms !== 'object' || Array.isArray(perms)) fail('InvalidPolicy', 2);
    \\        for (const name of Object.keys(perms)) {
    \\          if (CATS.indexOf(name) < 0) fail('InvalidPolicy', 2);
    \\          policy[name] = parseCategory(perms[name], name);
    \\        }
    \\      } else if (k === 'audit') {
    \\        const a = root.audit;
    \\        if (a === null || typeof a !== 'object' || Array.isArray(a)) fail('InvalidPolicy', 2);
    \\        for (const ak of Object.keys(a)) {
    \\          if (ak === 'sink') { if (typeof a.sink !== 'string') fail('InvalidPolicy', 2); policy.audit_sink = a.sink; }
    \\          else if (ak === 'events') { if (!Array.isArray(a.events)) fail('InvalidPolicy', 2); }
    \\          else fail('InvalidPolicy', 2);
    \\        }
    \\      } else fail('InvalidPolicy', 2);
    \\    }
    \\    for (const c of CATS) if (!policy[c]) policy[c] = { mode: 'deny', allow: [], read: [], write: [] };
    \\    return policy;
    \\  }
    \\  function init() {
    \\    if (state !== null) return state;
    \\    if (env('SA_POLICY_ALLOW_ALL') === '1') {
    \\      const allowAll = { audit_sink: null };
    \\      for (const c of CATS) allowAll[c] = { mode: 'allow', allow: [], read: [], write: [] };
    \\      state = { policy: allowAll, auditPath: auditPathOf(null) };
    \\      try { console.error('[sa-policy] allow-all policy engaged via SA_POLICY_ALLOW_ALL (audit trace)'); } catch (e) {}
    \\      audit('run', 'SA_POLICY_ALLOW_ALL', 'allow-all', 'env');
    \\      return state;
    \\    }
    \\    let text = env('SA_POLICY_JSON');
    \\    if (text === null) {
    \\      const f = env('SA_POLICY_FILE');
    \\      if (f !== null) {
    \\        const fs = __sa_node_builtin('node:fs');
    \\        if (fs === null) fail('SA_POLICY_FILE is set but cannot be opened', 2);
    \\        try { text = fs.readFileSync(f, 'utf8'); } catch (e) { fail('SA_POLICY_FILE is set but cannot be opened', 2); }
    \\      }
    \\    }
    \\    if (text !== null) {
    \\      const policy = parsePolicy(text);
    \\      state = { policy: policy, auditPath: auditPathOf(policy) };
    \\      return state;
    \\    }
    \\    if (env('SA_POLICY_REQUIRED') === '1') fail('SA_POLICY_REQUIRED is set but no policy was provided (set SA_POLICY_JSON, SA_POLICY_FILE, or SA_POLICY_ALLOW_ALL=1)', 1);
    \\    state = { policy: null, auditPath: null };
    \\    return state;
    \\  }
    \\  function audit(category, resource, decision, source) {
    \\    if (!state || !state.auditPath) return;
    \\    const fs = __sa_node_builtin('node:fs');
    \\    if (fs === null) return;
    \\    const ts = (BigInt(Date.now()) * 1000000n).toString();
    \\    const line = '{"ts_ns":' + ts + ',"context":1,"category":' + JSON.stringify(category) + ',"resource":' + JSON.stringify(resource) + ',"decision":' + JSON.stringify(decision) + ',"source":' + JSON.stringify(source) + '}' + String.fromCharCode(10);
    \\    try { fs.appendFileSync(state.auditPath, line); } catch (e) {}
    \\  }
    \\  function fsListAllows(list, path) {
    \\    for (let entry of list) {
    \\      let prefix = entry;
    \\      while (prefix.endsWith('/')) prefix = prefix.slice(0, -1);
    \\      if (path === prefix) return true;
    \\      if (path.length > prefix.length && path.startsWith(prefix) && path.charAt(prefix.length) === '/') return true;
    \\    }
    \\    return false;
    \\  }
    \\  function parseIpv4(t) {
    \\    const parts = t.split('.');
    \\    if (parts.length !== 4) return null;
    \\    let v = 0;
    \\    for (const part of parts) {
    \\      if (part.length === 0 || part.length > 3) return null;
    \\      const n = Number(part);
    \\      if (!Number.isInteger(n) || n < 0 || n > 255 || String(n) !== part) return null;
    \\      v = v * 256 + n;
    \\    }
    \\    return v;
    \\  }
    \\  function netEntryMatches(entry, host, port) {
    \\    const colon = entry.lastIndexOf(':');
    \\    if (colon < 0) return false;
    \\    const eHost = entry.slice(0, colon);
    \\    const ePort = entry.slice(colon + 1);
    \\    if (ePort !== '*' && Number(ePort) !== port) return false;
    \\    const slash = eHost.indexOf('/');
    \\    if (slash >= 0) {
    \\      const prefixLen = Number(eHost.slice(slash + 1));
    \\      if (!Number.isInteger(prefixLen) || prefixLen < 0 || prefixLen > 32) return false;
    \\      const network = parseIpv4(eHost.slice(0, slash));
    \\      const hostIp = parseIpv4(host);
    \\      if (network === null || hostIp === null) return false;
    \\      if (prefixLen === 0) return true;
    \\      const div = Math.pow(2, 32 - prefixLen);
    \\      return Math.floor(network / div) === Math.floor(hostIp / div);
    \\    }
    \\    return eHost.toLowerCase() === host.toLowerCase();
    \\  }
    \\  function decide(category, resource) {
    \\    const cp = state.policy[category];
    \\    if (cp.mode === 'allow') return 'allow';
    \\    if (cp.mode === 'deny') return 'deny';
    \\    if (cp.mode === 'audit') return 'allow_audit';
    \\    if (cp.mode === 'ask') return 'deny_ask_unhandled';
    \\    // allow-list
    \\    if (resource.kind === 'net') return cp.allow.some((e) => netEntryMatches(e, resource.host, resource.port)) ? 'allow' : 'deny';
    \\    if (resource.kind === 'fs') return fsListAllows(resource.write ? cp.write : cp.read, resource.path) ? 'allow' : 'deny';
    \\    if (resource.kind === 'str') return cp.allow.indexOf(resource.value) >= 0 ? 'allow' : 'deny';
    \\    return 'deny';
    \\  }
    \\  function resourceKey(category, resource) {
    \\    if (resource.kind === 'net') return resource.host + ':' + resource.port;
    \\    if (resource.kind === 'fs') return (resource.write ? 'write:' : 'read:') + resource.path;
    \\    if (resource.kind === 'str') return resource.value;
    \\    return category;
    \\  }
    \\  function check(category, resource) {
    \\    const st = init();
    \\    if (st.policy === null) return true;
    \\    const d = decide(category, resource);
    \\    if (d === 'allow') return true;
    \\    if (d === 'allow_audit') { audit(category, resourceKey(category, resource), 'allow', 'policy-audit'); return true; }
    \\    audit(category, resourceKey(category, resource), 'deny', d === 'deny_ask_unhandled' ? 'ask-unhandled' : 'policy');
    \\    return false;
    \\  }
    \\  return { check: check };
    \\})();
    \\function __sa_policy_fs(path, write) { return __sa_policy.check('fs', { kind: 'fs', path: path, write: write }); }
    \\function __sa_policy_net(host, port) { return __sa_policy.check('net', { kind: 'net', host: host, port: port }); }
    \\function __sa_policy_unit(category) { return __sa_policy.check(category, { kind: 'unit' }); }
    \\
;

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
                if (item.shape == .method or item.shape == .get) continue; // handle shapes import nothing
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
                if (item.shape == .method or item.shape == .get) continue; // handle shapes import nothing
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
        \\const __sa_buf = (typeof globalThis.Buffer !== "undefined" && globalThis.Buffer.from) ? globalThis.Buffer.from(__sa_memory) : null; // zero-copy host Buffer: C++ memset/memmove fast path for bulk shims (both node and bun provide it)
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
        \\  if (!__sa_slab_by_class[sc]) __sa_slab_by_class[sc] = [];
        \\  if (!(sc > 0)) __sa_trap("bad slab class");
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
        \\  sc = __sa_align((__sa_num(sc) | 0), 8);
        \\  if (sc <= 0) sc = 8;
        \\  if (sc > __sa_SMALL_MAX) __sa_trap("bad slab class " + sc);
        \\  if (!__sa_slab_by_class[sc]) { __sa_slab_by_class[sc] = []; __sa_slab_hint[sc] = null; }
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
        \\  if (!(size > 0)) size = 8; // malloc(0)-style: never hand out class 0 (was: slab list undefined -> TypeError length)
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
        \\  if (!(size > 0)) size = 8;
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
        \\function __sa_add(a, b) { return __sa_isBI(a, b) ? __sa_BI(BigInt(a) + BigInt(b)) : ((+a) + (+b)); }
        \\function __sa_sub(a, b) { return __sa_isBI(a, b) ? __sa_BI(BigInt(a) - BigInt(b)) : ((+a) - (+b)); }
        \\function __sa_mul(a, b) { if (__sa_isBI(a, b)) return __sa_BI(BigInt(a) * BigInt(b)); const p = (+a) * (+b); return (p >= -2147483648 && p <= 2147483647) ? (p | 0) : (Number.isSafeInteger(p) ? p : __sa_BI(BigInt(a) * BigInt(b))); }
        \\function __sa_sdiv(a, b) { if (__sa_isBI(a, b) || a > 2147483647 || a < -2147483648 || b > 2147483647 || b < -2147483648) { const nb = BigInt.asIntN(64, BigInt(b)); if (nb === 0n) __sa_trap("div by zero"); return __sa_BI(BigInt.asIntN(64, BigInt(a)) / nb); } const nb32 = (b | 0); if (nb32 === 0) __sa_trap("div by zero"); return (Math.trunc((a | 0) / nb32) | 0); }
        \\function __sa_udiv(a, b) { if (__sa_isBI(a, b) || a < 0 || b < 0 || a > 4294967295 || b > 4294967295) { const x = __sa_BU(a), y = __sa_BU(b); if (y === 0n) __sa_trap("div by zero"); return x / y; } const y32 = (b >>> 0); if (y32 === 0) __sa_trap("div by zero"); return Math.trunc((a >>> 0) / y32); }
        \\function __sa_srem(a, b) { if (__sa_isBI(a, b) || a > 2147483647 || a < -2147483648 || b > 2147483647 || b < -2147483648) { const nb = BigInt.asIntN(64, BigInt(b)); if (nb === 0n) __sa_trap("rem by zero"); return __sa_BI(BigInt.asIntN(64, BigInt(a)) % nb); } const nb32 = (b | 0); if (nb32 === 0) __sa_trap("rem by zero"); return (((a | 0) % nb32) | 0); }
        \\function __sa_urem(a, b) { if (__sa_isBI(a, b) || a < 0 || b < 0 || a > 4294967295 || b > 4294967295) { const x = __sa_BU(a), y = __sa_BU(b); if (y === 0n) __sa_trap("rem by zero"); return x % y; } const y32 = (b >>> 0); if (y32 === 0) __sa_trap("rem by zero"); return ((a >>> 0) % y32); }
        \\function __sa_neg(a) { return (typeof a === "bigint") ? __sa_BI(-a) : (-(+a)); }
        \\function __sa_band(a, b) { if (__sa_isBI(a, b) || a > 2147483647 || a < -2147483648 || b > 2147483647 || b < -2147483648) return __sa_BI(BigInt(a) & BigInt(b)); return ((a & b) | 0); }
        \\function __sa_bor(a, b) { if (__sa_isBI(a, b) || a > 2147483647 || a < -2147483648 || b > 2147483647 || b < -2147483648) return __sa_BI(BigInt(a) | BigInt(b)); return ((a | b) | 0); }
        \\function __sa_bxor(a, b) { if (__sa_isBI(a, b) || a > 2147483647 || a < -2147483648 || b > 2147483647 || b < -2147483648) return __sa_BI(BigInt(a) ^ BigInt(b)); return ((a ^ b) | 0); }
        \\function __sa_shl(a, b) { if (__sa_isBI(a, b) || a > 2147483647 || a < -2147483648 || (typeof b !== "bigint" && b > 31)) return __sa_BI(BigInt(a) << (BigInt(b) & 63n)); return ((a << (b & 31)) | 0); }
        \\function __sa_lshr(a, b) { if (typeof a === "bigint" || a < 0 || a > 4294967295 || (typeof b !== "bigint" && b > 31)) return __sa_BU(a) >> (BigInt(b) & 63n); if (typeof b === "bigint") { const k = Number(BigInt(b) & 63n); return k >= 32 ? 0 : (a >>> k); } return (a >>> (b & 31)); }
        \\function __sa_ashr(a, b) { if (__sa_isBI(a, b) || a > 2147483647 || a < -2147483648 || (typeof b !== "bigint" && b > 31)) return __sa_BI(BigInt.asIntN(64, BigInt(a)) >> (BigInt(b) & 63n)); return ((a >> (b & 31)) | 0); }
        \\function __sa_bnot(a) { if (typeof a === "bigint" || a > 2147483647 || a < -2147483648) return __sa_BI(~BigInt(a)); return ((~a) | 0); }
        \\function __sa_eq(a, b) { return ((a == b) ? 1 : 0); }
        \\function __sa_ne(a, b) { return ((a != b) ? 1 : 0); }
        \\function __sa_slt(a, b) { if (__sa_isBI(a, b) || a > 2147483647 || a < -2147483648 || b > 2147483647 || b < -2147483648) return ((BigInt.asIntN(64, BigInt(a)) < BigInt.asIntN(64, BigInt(b))) ? 1 : 0); return (((a | 0) < (b | 0)) ? 1 : 0); }
        \\function __sa_sle(a, b) { if (__sa_isBI(a, b) || a > 2147483647 || a < -2147483648 || b > 2147483647 || b < -2147483648) return ((BigInt.asIntN(64, BigInt(a)) <= BigInt.asIntN(64, BigInt(b))) ? 1 : 0); return (((a | 0) <= (b | 0)) ? 1 : 0); }
        \\function __sa_sgt(a, b) { if (__sa_isBI(a, b) || a > 2147483647 || a < -2147483648 || b > 2147483647 || b < -2147483648) return ((BigInt.asIntN(64, BigInt(a)) > BigInt.asIntN(64, BigInt(b))) ? 1 : 0); return (((a | 0) > (b | 0)) ? 1 : 0); }
        \\function __sa_sge(a, b) { if (__sa_isBI(a, b) || a > 2147483647 || a < -2147483648 || b > 2147483647 || b < -2147483648) return ((BigInt.asIntN(64, BigInt(a)) >= BigInt.asIntN(64, BigInt(b))) ? 1 : 0); return (((a | 0) >= (b | 0)) ? 1 : 0); }
        \\function __sa_ult(a, b) { if (__sa_isBI(a, b) || a < 0 || b < 0 || a > 4294967295 || b > 4294967295) return ((__sa_BU(a) < __sa_BU(b)) ? 1 : 0); return (((a >>> 0) < (b >>> 0)) ? 1 : 0); }
        \\function __sa_ule(a, b) { if (__sa_isBI(a, b) || a < 0 || b < 0 || a > 4294967295 || b > 4294967295) return ((__sa_BU(a) <= __sa_BU(b)) ? 1 : 0); return (((a >>> 0) <= (b >>> 0)) ? 1 : 0); }
        \\function __sa_ugt(a, b) { if (__sa_isBI(a, b) || a < 0 || b < 0 || a > 4294967295 || b > 4294967295) return ((__sa_BU(a) > __sa_BU(b)) ? 1 : 0); return (((a >>> 0) > (b >>> 0)) ? 1 : 0); }
        \\function __sa_uge(a, b) { if (__sa_isBI(a, b) || a < 0 || b < 0 || a > 4294967295 || b > 4294967295) return ((__sa_BU(a) >= __sa_BU(b)) ? 1 : 0); return (((a >>> 0) >= (b >>> 0)) ? 1 : 0); }
        \\function __sa_ult32(a, b) { if (__sa_isBI(a, b) || a > 4294967295 || b > 4294967295) return ((__sa_BU(a) < __sa_BU(b)) ? 1 : 0); return (((a >>> 0) < (b >>> 0)) ? 1 : 0); }
        \\function __sa_ule32(a, b) { if (__sa_isBI(a, b) || a > 4294967295 || b > 4294967295) return ((__sa_BU(a) <= __sa_BU(b)) ? 1 : 0); return (((a >>> 0) <= (b >>> 0)) ? 1 : 0); }
        \\function __sa_ugt32(a, b) { if (__sa_isBI(a, b) || a > 4294967295 || b > 4294967295) return ((__sa_BU(a) > __sa_BU(b)) ? 1 : 0); return (((a >>> 0) > (b >>> 0)) ? 1 : 0); }
        \\function __sa_uge32(a, b) { if (__sa_isBI(a, b) || a > 4294967295 || b > 4294967295) return ((__sa_BU(a) >= __sa_BU(b)) ? 1 : 0); return (((a >>> 0) >= (b >>> 0)) ? 1 : 0); }
        \\function __sa_udiv32(a, b) { if (__sa_isBI(a, b) || a > 4294967295 || b > 4294967295) { const x = __sa_BU(a), y = __sa_BU(b); if (y === 0n) __sa_trap("div by zero"); return x / y; } const y32 = (b >>> 0); if (y32 === 0) __sa_trap("div by zero"); return Math.trunc((a >>> 0) / y32); }
        \\function __sa_urem32(a, b) { if (__sa_isBI(a, b) || a > 4294967295 || b > 4294967295) { const x = __sa_BU(a), y = __sa_BU(b); if (y === 0n) __sa_trap("rem by zero"); return x % y; } const y32 = (b >>> 0); if (y32 === 0) __sa_trap("rem by zero"); return ((a >>> 0) % y32); }
        \\function __sa_lshr32(a, b) { if (typeof a === "bigint" || a > 4294967295 || (typeof b !== "bigint" && b > 31)) return __sa_BU(a) >> (BigInt(b) & 63n); if (typeof b === "bigint") { const k = Number(BigInt(b) & 63n); return k >= 32 ? 0 : (a >>> k); } return (a >>> (b & 31)); }
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
        \\function __sa_cvt_sext_i64(v) { return (typeof v === "bigint") ? BigInt.asIntN(64, v) : BigInt.asIntN(64, BigInt(Math.trunc(+v))); }
        \\function __sa_cvt_sext_u64(v) { return (typeof v === "bigint") ? BigInt.asUintN(64, v) : BigInt.asUintN(64, BigInt(Math.trunc(+v))); }
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
        \\const __sa_regexlists = new Map();
        \\let __sa_regexlistnext = 1;
        \\const __sa_regexbufs = new Map();
        \\let __sa_regexbufnext = 1;
        \\const __sa_regexsplits = new Map();
        \\let __sa_regexsplitnext = 1;
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
        \\  // Match native (Zig 0.17 std.json decimal shortest): 2.5->"2.5".
        \\  const v = (typeof x === "bigint") ? Number(x) : (+x);
        \\  if (Number.isNaN(v)) return '"nan"';
        \\  if (v === Infinity) return 'inf';
        \\  if (v === -Infinity) return '-inf';
        \\  return String(v).replace("e+", "e");
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
        \\function __sa_regex_collect(rec, s) {
        \\  // JS global-exec loop mirroring regexCollectMatches in sa_std.zig:
        \\  // after an empty match the search advances one position (native: one
        \\  // byte; this JS model works on decoded strings, like sa_regex_match).
        \\  const re = new RegExp(rec.re.source, rec.re.flags + "g");
        \\  const out = [];
        \\  let pos = 0;
        \\  while (pos <= s.length) {
        \\    re.lastIndex = pos;
        \\    const m = re.exec(s);
        \\    if (m === null || m.indices === undefined) break;
        \\    const groups = m.indices.map((g) => ((g === undefined) ? [-1, -1] : [g[0], g[1]]));
        \\    out.push(groups);
        \\    const st = groups[0][0], en = groups[0][1];
        \\    pos = (en === st) ? en + 1 : en;
        \\  }
        \\  return out;
        \\}
        \\function __sa_regex_group_text(text, groups, idx) {
        \\  if (idx >= groups.length) return "";
        \\  const g = groups[idx];
        \\  if (g[0] < 0 || g[1] < 0) return "";
        \\  return text.slice(g[0], g[1]);
        \\}
        \\function __sa_regex_expand(text, groups, repl) {
        \\  // Port of regexAppendExpansion in sa_std.zig (JS template rules):
        \\  // $$ literal $, $& whole match, $` before, $' after, $n/$nn groups
        \\  // (non-participating expands to nothing, out-of-range stays literal,
        \\  // $<name> stays literal).
        \\  const total = groups.length - 1;
        \\  let out = "";
        \\  let i = 0;
        \\  while (i < repl.length) {
        \\    const c = repl[i];
        \\    if (c !== "$" || i + 1 >= repl.length) { out += c; i += 1; continue; }
        \\    const n = repl[i + 1];
        \\    if (n === "$") { out += "$"; i += 2; }
        \\    else if (n === "&") { out += __sa_regex_group_text(text, groups, 0); i += 2; }
        \\    else if (n === "`") { out += text.slice(0, groups[0][0]); i += 2; }
        \\    else if (n === "'") { out += text.slice(groups[0][1]); i += 2; }
        \\    else if (n >= "1" && n <= "9") {
        \\      const d1 = n.charCodeAt(0) - 48;
        \\      let consumed = 0;
        \\      if (i + 2 < repl.length && repl[i + 2] >= "0" && repl[i + 2] <= "9") {
        \\        const nn = d1 * 10 + (repl[i + 2].charCodeAt(0) - 48);
        \\        if (nn >= 1 && nn <= total) { out += __sa_regex_group_text(text, groups, nn); consumed = 3; }
        \\      }
        \\      if (consumed === 0 && d1 <= total) { out += __sa_regex_group_text(text, groups, d1); consumed = 2; }
        \\      if (consumed === 0) { out += "$"; i += 1; } else { i += consumed; }
        \\    }
        \\    else { out += "$"; i += 1; }
        \\  }
        \\  return out;
        \\}
        \\function __sa_regex_split_pieces(rec, s, limit) {
        \\  // Port of regexSplitHandle in sa_std.zig (JS String.split semantics;
        \\  // limit caps the total piece count including inserted groups, and
        \\  // limit == 0 means no limit -- a deliberate divergence from JS).
        \\  const lim = (limit === 0) ? Infinity : limit;
        \\  const pieces = [];
        \\  const re = new RegExp(rec.re.source, rec.re.flags + "g");
        \\  if (s.length === 0) {
        \\    re.lastIndex = 0;
        \\    if (re.exec(s) === null) pieces.push([0, 0]);
        \\    return pieces;
        \\  }
        \\  let p = 0, q = 0, done = false;
        \\  while (!done && q <= s.length) {
        \\    re.lastIndex = q;
        \\    const m = re.exec(s);
        \\    if (m === null || m.indices === undefined) break;
        \\    const groups = m.indices.map((g) => ((g === undefined) ? [-1, -1] : [g[0], g[1]]));
        \\    const ms = groups[0][0], me = groups[0][1];
        \\    if (me === p) { q = me + 1; continue; }
        \\    pieces.push([p, ms]);
        \\    if (pieces.length >= lim) { done = true; break; }
        \\    for (let gi = 1; gi < groups.length; gi++) {
        \\      pieces.push(groups[gi]);
        \\      if (pieces.length >= lim) { done = true; break; }
        \\    }
        \\    if (done) break;
        \\    p = me; q = p;
        \\  }
        \\  if (!done) pieces.push([p, s.length]);
        \\  return pieces;
        \\}
        \\function __sa_json_clone(v) {
        \\  // Deep copy for sa_json_*_set_node / *_push_node (native clones the
        \\  // child into the target document arena; the stored value must not
        \\  // alias the child document tree).
        \\  if (v === null || typeof v !== "object") return v;
        \\  if (Array.isArray(v)) return v.map((x) => __sa_json_clone(x));
        \\  const o = {};
        \\  for (const k of Object.keys(v)) o[k] = __sa_json_clone(v[k]);
        \\  return o;
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
    try writer.writeAll(policy_runtime_js);
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
        // Number domain are emitted as plain digits. SOUNDNESS INVARIANT
        // (interpreter computes all int ALU at 64 bits): every runtime int
        // helper carries full 64-bit precision — add/sub are double-exact to
        // 2^53 (no |0 truncation); mul/div/rem/shifts/bitwise/comparisons
        // dynamically promote out-of-32-bit-range Number operands to the
        // BigInt path; only provably-32-bit pairs take the fast path.
        // Narrowing happens solely at explicit narrow points (stores, loads,
        // cvt, comparisons coerce their inputs). 64-bit literals, extern
        // BigInt returns, and u64 loads stay BigInt end to end.
        // Negative i64 literals stay BigInt (their unsigned reading is
        // mod-2^64); unsigned-forcing ops (udiv/urem/ult/ule/ugt/uge/lshr)
        // select the neg-checking GENERAL helper unless every relevant
        // operand is statically <=32-bit (demos 337 vs 347), in which case
        // the pure->>>0 FAST helper is bit-identical to legacy behavior.
        .imm_i64 => |v| if (v >= 0 and v <= std.math.maxInt(i32))
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

/// Width-directed unsigned-op selection (demos 337 vs 347): a negative
/// Number means mod-2^32 for <=32-bit regs but mod-2^64 for 64-bit regs,
/// and the runtime cannot tell them apart. So unsigned-forcing ops
/// (udiv/urem/ult/ule/ugt/uge/lshr) use the neg-checking GENERAL helper
/// unless every relevant operand is provably 32-bit-or-safe, in which
/// case the pure->>>0 FAST helper is bit-identical to the old behavior.
/// A 64-bit reg holding a small Number still takes the >>>0 path inside
/// GENERAL (values coincide); only actually-negative/big inputs pay BigInt.
fn u32SafeOperand(op: inst.Operand, widths: *const WidthMap) bool {
    switch (op) {
        .reg => |id| {
            const w = widths.get(id) orelse return false;
            if (widthIsFloat(w)) return false;
            return widthBits(w) <= 32;
        },
        .imm_int => |v| return v >= 0,
        .imm_i64 => |v| return v >= 0,
        .imm_u64 => return true,
        .imm_float => return false,
        .text, .native_text => |t| {
            var text = std.mem.trim(u8, t, " \t");
            if (text.len == 0) return false;
            if (text[0] == '&' or text[0] == '*' or text[0] == '^') text = std.mem.trim(u8, text[1..], " \t");
            if (std.mem.lastIndexOf(u8, text, " as ")) |idx| text = std.mem.trim(u8, text[0..idx], " \t\r");
            if (std.fmt.parseInt(u64, text, 10)) |_| return true else |_| {}
            return false;
        },
        else => return false,
    }
}

fn useFastU32(lhs: inst.Operand, rhs: inst.Operand, widths: *const WidthMap, checkBoth: bool) bool {
    if (!u32SafeOperand(lhs, widths)) return false;
    if (checkBoth and !u32SafeOperand(rhs, widths)) return false;
    return true;
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
            try writer.writeAll(if (useFastU32(lhs, rhs, widths, true)) "__sa_udiv32(" else "__sa_udiv(");
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
            try writer.writeAll(if (useFastU32(lhs, rhs, widths, true)) "__sa_urem32(" else "__sa_urem(");
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
            try writer.writeAll(if (useFastU32(lhs, rhs, widths, false)) "__sa_lshr32(" else "__sa_lshr(");
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
            try writer.writeAll(if (useFastU32(lhs, rhs, widths, true)) "__sa_ult32(" else "__sa_ult(");
            try resolveValueToJs(writer, symbols, fsig, use_global, const_addrs, fn_idx, lhs);
            try writer.writeAll(", ");
            try resolveValueToJs(writer, symbols, fsig, use_global, const_addrs, fn_idx, rhs);
            try writer.writeAll(")");
        },
        .ule => {
            try writer.writeAll(if (useFastU32(lhs, rhs, widths, true)) "__sa_ule32(" else "__sa_ule(");
            try resolveValueToJs(writer, symbols, fsig, use_global, const_addrs, fn_idx, lhs);
            try writer.writeAll(", ");
            try resolveValueToJs(writer, symbols, fsig, use_global, const_addrs, fn_idx, rhs);
            try writer.writeAll(")");
        },
        .ugt => {
            try writer.writeAll(if (useFastU32(lhs, rhs, widths, true)) "__sa_ugt32(" else "__sa_ugt(");
            try resolveValueToJs(writer, symbols, fsig, use_global, const_addrs, fn_idx, lhs);
            try writer.writeAll(", ");
            try resolveValueToJs(writer, symbols, fsig, use_global, const_addrs, fn_idx, rhs);
            try writer.writeAll(")");
        },
        .uge => {
            try writer.writeAll(if (useFastU32(lhs, rhs, widths, true)) "__sa_uge32(" else "__sa_uge(");
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

/// Slot-promotion (register) analysis for the JS backend: finds `stack_alloc`
/// slots whose every use is a zero-offset plain `.load`/`.store` base.
/// Promoted slots become function-scope JS locals (`__sa_sp{slot}`), which
/// lets V8/JSC keep counters/accumulators in registers instead of bouncing
/// them through linear memory on every iteration. Soundness rules
/// (conservative; anything unclear disqualifies):
/// - the def must be the single `stack_alloc` in this function (params and
///   heap allocs never qualify); any reassignment disqualifies;
/// - any mention outside load/store base position disqualifies (borrows via
///   `&`, ptr_add/call/return/br operands, nonzero offsets, take/atomics,
///   cmpxchg, release), textual operands included;
/// - all accesses must share one int type so the store-side conversion is
///   exact (<=32-bit via `__sa_narrow`; 64-bit via `BigInt.asIntN`, mirroring
///   `__sa_store_i64` which both i64 and u64 use); floats/pointers never
///   qualify; init is an in-place load at the alloc site, so
///   even never-stored slots observe identical stale bytes.
const PromoInfo = struct {
    load_fn: []const u8,
    narrow_bits: u8,
    narrow_signed: bool,
};
const PromoMap = std.AutoHashMap(u32, PromoInfo);

fn promoNarrowBits(ty: sig.PrimType) ?struct { bits: u8, signed: bool } {
    return switch (ty) {
        .u8 => .{ .bits = 8, .signed = false },
        .i8, .i1 => .{ .bits = 8, .signed = true },
        .u16 => .{ .bits = 16, .signed = false },
        .i16 => .{ .bits = 16, .signed = true },
        .u32 => .{ .bits = 32, .signed = false },
        .i32 => .{ .bits = 32, .signed = true },
        // 64-bit mirror __sa_store_i64 exactly (asIntN for both i64/u64).
        .i64, .u64 => .{ .bits = 64, .signed = true },
        else => null,
    };
}

/// Slot named by any operand shape (mirrors provKillStoreValue: textual
/// values resolve exactly like regs; immediates never name slots).
fn promoMentionSlot(symbols: anytype, fsig: sig.FunctionSig, use_global: bool, op: inst.Operand) ?u32 {
    switch (op) {
        .reg, .symbol => return provSlotOf(fsig, use_global, op),
        .text, .native_text => |t| {
            if (provTextSlot(symbols, fsig, use_global, t)) |s| return s;
            // Composite text operands (a call's argument list rendered
            // as one string) hide slot mentions from the whole-text
            // lookup. Scan identifier tokens so an escaped slot still
            // disqualifies promotion: a callee may write through the
            // slot's address (extern out-params do exactly that), and a
            // promoted slot would keep serving the stale init value.
            // Conservative: a false hit only loses the optimization.
            var it = std.mem.tokenizeAny(u8, t, " \t\r\n,()[]{}:;\"'`");
            while (it.next()) |tok| {
                if (provTextSlot(symbols, fsig, use_global, tok)) |s| return s;
            }
            return null;
        },
        else => return null,
    }
}

fn collectPromotableSlots(allocator: std.mem.Allocator, verified: anytype, fsig: sig.FunctionSig, task: FuncTask, use_global: bool) !PromoMap {
    var promo = PromoMap.init(allocator);
    errdefer promo.deinit();
    var defined = std.AutoHashMap(u32, void).init(allocator);
    defer defined.deinit();
    var bad = std.AutoHashMap(u32, void).init(allocator);
    defer bad.deinit();
    const UseInfo = struct { ty: sig.PrimType, loads: u32, stores: u32 };
    var uses = std.AutoHashMap(u32, UseInfo).init(allocator);
    defer uses.deinit();
    for (fsig.param_ids) |gid| {
        if (fsig.slotOf(gid)) |s| try bad.put(s, {});
    }
    var i: usize = task.start_idx + 1;
    while (i < task.end_idx) : (i += 1) {
        const base = verified.annotated[i].base;
        const ops = base.operands;
        switch (base.kind) {
            .stack_alloc => {
                if (ops.len < 1) continue;
                if (promoMentionSlot(verified.symbols, fsig, use_global, ops[0])) |ds| {
                    if (defined.get(ds) != null) try bad.put(ds, {});
                    try defined.put(ds, {});
                }
                var k: usize = 1;
                while (k < ops.len) : (k += 1) {
                    if (promoMentionSlot(verified.symbols, fsig, use_global, ops[k])) |s| try bad.put(s, {});
                }
            },
            .load => {
                if (ops.len < 3) continue;
                if (promoMentionSlot(verified.symbols, fsig, use_global, ops[0])) |ds| try bad.put(ds, {});
                if (promoMentionSlot(verified.symbols, fsig, use_global, ops[2])) |os| try bad.put(os, {});
                const b = promoMentionSlot(verified.symbols, fsig, use_global, ops[1]) orelse continue;
                if (!offIsZero(ops[2])) { try bad.put(b, {}); continue; }
                const ty = memPrimType(base);
                const gop = try uses.getOrPut(b);
                if (!gop.found_existing) gop.value_ptr.* = .{ .ty = ty, .loads = 0, .stores = 0 };
                if (gop.value_ptr.ty != ty) { try bad.put(b, {}); continue; }
                gop.value_ptr.loads += 1;
            },
            .store => {
                if (ops.len < 3) continue;
                if (promoMentionSlot(verified.symbols, fsig, use_global, ops[1])) |os| try bad.put(os, {});
                if (promoMentionSlot(verified.symbols, fsig, use_global, ops[2])) |vs| try bad.put(vs, {});
                const b = promoMentionSlot(verified.symbols, fsig, use_global, ops[0]) orelse continue;
                if (!offIsZero(ops[1])) { try bad.put(b, {}); continue; }
                const ty = memPrimType(base);
                const gop = try uses.getOrPut(b);
                if (!gop.found_existing) gop.value_ptr.* = .{ .ty = ty, .loads = 0, .stores = 0 };
                if (gop.value_ptr.ty != ty) { try bad.put(b, {}); continue; }
                gop.value_ptr.stores += 1;
            },
            else => {
                for (ops) |op| {
                    if (promoMentionSlot(verified.symbols, fsig, use_global, op)) |s| try bad.put(s, {});
                }
                // Call instructions carry their arguments in raw_text,
                // not in operands, so the operand scan above never sees
                // them. Scan the text as well: a slot passed to a callee
                // that writes through its address (extern out-params)
                // must not be promoted, or later loads would serve the
                // stale promoted init value instead of memory.
                var tit = std.mem.tokenizeAny(u8, base.raw_text, " \t\r\n,()[]{}:;\"'`@=");
                while (tit.next()) |tok| {
                    if (provTextSlot(verified.symbols, fsig, use_global, tok)) |s| try bad.put(s, {});
                }
            },
        }
    }
    var uit = uses.iterator();
    while (uit.next()) |e| {
        const s = e.key_ptr.*;
        if (defined.get(s) == null) continue;
        if (bad.get(s) != null) continue;
        if (e.value_ptr.loads == 0 or e.value_ptr.stores == 0) continue;
        const nb = promoNarrowBits(e.value_ptr.ty) orelse continue;
        try promo.put(s, .{ .load_fn = memLoadFn(e.value_ptr.ty), .narrow_bits = nb.bits, .narrow_signed = nb.signed });
    }
    return promo;
}

/// Promoted base slot for a zero-offset plain load/store, else null.
fn promoBaseSlot(fsig: sig.FunctionSig, use_global: bool, base: inst.Instruction, promo: *const PromoMap) ?u32 {
    const is_load = base.kind == .load;
    const is_store = base.kind == .store;
    if (!is_load and !is_store) return null;
    const base_op = if (is_load) base.operands[1] else base.operands[0];
    const off_op = if (is_load) base.operands[2] else base.operands[1];
    if (!offIsZero(off_op)) return null;
    const bs = provSlotOf(fsig, use_global, base_op) orelse return null;
    if (promo.get(bs) == null) return null;
    return bs;
}

fn emitLinearInstruction(writer: anytype, allocator: std.mem.Allocator, symbols: anytype, fsig: sig.FunctionSig, use_global: bool, const_addrs: anytype, fn_idx: anytype, base: inst.Instruction, js_opt: JsEmitOptions, bases: *BaseSet, retbase: *const RetBaseTable, widths: *WidthMap, promo: *const PromoMap) !void {
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
            // Promoted slot: snapshot the cell into its local (identical
            // stale bytes to what the program would observe; re-executes
            // correctly if the alloc itself is inside a loop).
            if (promo.get(slot)) |info| {
                try writer.print("  __sa_sp{d} = {s}(r{d});\n", .{ slot, info.load_fn, slot });
            }
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
            if (promoBaseSlot(fsig, use_global, base, promo)) |bs| {
                try writer.print("  r{d} = __sa_sp{d};\n", .{ slot, bs });
            } else if (offIsZero(base.operands[2])) {
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
            if (promoBaseSlot(fsig, use_global, base, promo)) |bs| {
                const info = promo.get(bs).?;
                // Narrow inline for 32-bit (bit-identical to __sa_narrow;
                // value operands are pure refs so triple emission is safe,
                // mirroring the br_null duplicate-operand precedent).
                if (info.narrow_bits == 32) {
                    try writer.print("  __sa_sp{d} = ((typeof (", .{bs});
                    try resolveValueToJs(writer, symbols, fsig, use_global, const_addrs, fn_idx, base.operands[2]);
                    if (info.narrow_signed) {
                        try writer.writeAll(") === \"bigint\") ? Number(BigInt.asIntN(32, (");
                    } else {
                        try writer.writeAll(") === \"bigint\") ? Number(BigInt.asUintN(32, (");
                    }
                    try resolveValueToJs(writer, symbols, fsig, use_global, const_addrs, fn_idx, base.operands[2]);
                    if (info.narrow_signed) {
                        try writer.writeAll("))) : ((");
                    } else {
                        try writer.writeAll("))) : ((");
                    }
                    try resolveValueToJs(writer, symbols, fsig, use_global, const_addrs, fn_idx, base.operands[2]);
                    if (info.narrow_signed) {
                        try writer.writeAll(") | 0));\n");
                    } else {
                        try writer.writeAll(") >>> 0));\n");
                    }
                } else if (info.narrow_bits == 64) {
                    // Mirrors __sa_store_i64 exactly (asIntN for both i64/u64).
                    try writer.print("  __sa_sp{d} = BigInt.asIntN(64, BigInt((", .{bs});
                    try resolveValueToJs(writer, symbols, fsig, use_global, const_addrs, fn_idx, base.operands[2]);
                    try writer.writeAll(")));\n");
                } else {
                    try writer.print("  __sa_sp{d} = __sa_narrow(", .{bs});
                    try resolveValueToJs(writer, symbols, fsig, use_global, const_addrs, fn_idx, base.operands[2]);
                    try writer.print(", {d}, {s});\n", .{ info.narrow_bits, if (info.narrow_signed) "true" else "false" });
                }
            } else if (offIsZero(base.operands[1])) {
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

fn emitPcInstruction(writer: anytype, allocator: std.mem.Allocator, symbols: anytype, fsig: sig.FunctionSig, use_global: bool, const_addrs: anytype, fn_idx: anytype, base: inst.Instruction, label_pc: *std.AutoHashMap(u32, usize), js_opt: JsEmitOptions, bases: *BaseSet, retbase: *const RetBaseTable, widths: *WidthMap, promo: *const PromoMap) !void {
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
            var fbs = std.Io.Writer.fixed(&buf);
            try emitLinearInstruction(&fbs, allocator, symbols, fsig, use_global, const_addrs, fn_idx, base, js_opt, bases, retbase, widths, promo);
            const s = std.mem.trim(u8, fbs.buffered(), " \t\r\n");
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

/// Whether `name` is a JS value-handle runtime builtin: externs the JS
/// target implements by name (handle release, callback creation, the
/// callback queue pump). They are runtime services, not npm bindings;
/// declaring one pulls in the handle runtime chunk (gate below).
fn isJsHandleBuiltin(name: []const u8) bool {
    return std.mem.eql(u8, name, "sa_js_value_release") or
        std.mem.eql(u8, name, "sa_js_make_callback") or
        std.mem.eql(u8, name, "sa_js_callback_poll");
}

// JS value-handle runtime chunk: the handle table behind the npm
// ctor/method/get binding shapes, string-out writeback, zero-copy
// TypedArray views, and the queue-drain callback pump (the JS closure
// only enqueues; SA dispatches in its own flow via sa_js_callback_poll).
// Emitted once per program that uses any of those (gate below).
// Handle encoding: gen * 2^32 + (index + 1), returned as BigInt; 0 is
// never a valid handle. Release bumps the slot generation, so a stale
// handle traps instead of silently aliasing a recycled slot's value.
const jshandle_runtime_js =
    \\// ---- SA JS value handles (npm ctor/method/get bindings + callbacks) ----
    \\const SA_JS_STR_TOO_LONG = 1;
    \\const __sa_jsh_slots = [];
    \\const __sa_jsh_free = [];
    \\const __sa_jsh_EMPTY = {};
    \\function __sa_jsh_new(v) {
    \\  if (v === undefined) __sa_trap("js handle: cannot register undefined as a handle");
    \\  let idx;
    \\  if (__sa_jsh_free.length) idx = __sa_jsh_free.pop();
    \\  else { idx = __sa_jsh_slots.length; __sa_jsh_slots.push({ v: __sa_jsh_EMPTY, gen: 1 }); }
    \\  __sa_jsh_slots[idx].v = v;
    \\  return BigInt(__sa_jsh_slots[idx].gen * 4294967296 + (idx + 1));
    \\}
    \\function __sa_jsh_decode(h, what) {
    \\  const n = (typeof h === "bigint") ? Number(h) : __sa_num(h);
    \\  if (!Number.isSafeInteger(n) || n <= 0) __sa_trap("js handle: invalid handle (" + what + ")");
    \\  const idx = (n % 4294967296) - 1;
    \\  const gen = Math.floor(n / 4294967296);
    \\  if (idx < 0 || idx >= __sa_jsh_slots.length) __sa_trap("js handle: handle out of range (" + what + ")");
    \\  const slot = __sa_jsh_slots[idx];
    \\  if (slot.v === __sa_jsh_EMPTY || slot.gen !== gen) __sa_trap("js handle: stale or released handle (" + what + ")");
    \\  return idx;
    \\}
    \\function __sa_jsh_get(h) { return __sa_jsh_slots[__sa_jsh_decode(h, "use")].v; }
    \\function __sa_jsh_release(h) {
    \\  const idx = __sa_jsh_decode(h, "release");
    \\  const slot = __sa_jsh_slots[idx];
    \\  slot.v = __sa_jsh_EMPTY;
    \\  slot.gen += 1;
    \\  __sa_jsh_free.push(idx);
    \\  return 0;
    \\}
    \\function __sa_jsh_str_out(v, out_ptr, out_cap, out_len_ptr) {
    \\  if (typeof v !== "string") __sa_trap("npm extern returned non-string for a string out-param binding");
    \\  const bytes = new globalThis.TextEncoder().encode(v);
    \\  __sa_view.setBigUint64(__sa_addr(out_len_ptr), BigInt(bytes.length), true);
    \\  if (bytes.length > __sa_num(out_cap)) return SA_JS_STR_TOO_LONG;
    \\  __sa_u8.set(bytes, __sa_addr(out_ptr));
    \\  return 0;
    \\}
    \\function __sa_jsh_u8view(ptr, len) {
    \\  const a = __sa_addr(ptr), n = __sa_num(len);
    \\  if (!(n >= 0) || a < 0 || a + n > __sa_u8.length) __sa_trap("js bytes view out of bounds");
    \\  return new Uint8Array(__sa_memory, a, n);
    \\}
    \\function __sa_jsh_f32view(ptr, len) {
    \\  const a = __sa_addr(ptr), n = __sa_num(len);
    \\  if (!(n >= 0) || (n % 4) !== 0 || (a % 4) !== 0 || a + n > __sa_u8.length) __sa_trap("js f32 view out of bounds or unaligned");
    \\  return new Float32Array(__sa_memory, a, n / 4);
    \\}
    \\const __sa_jsh_cb_queue = [];
    \\function __sa_jsh_make_callback(fn) {
    \\  const idx = __sa_fnval(fn);
    \\  if (idx < 0) __sa_trap("sa_js_make_callback: argument is not an SA function pointer");
    \\  const closure = (...args) => {
    \\    const nums = [];
    \\    for (const a of args) {
    \\      if (typeof a === "number") nums.push(a);
    \\      else if (typeof a === "bigint") nums.push(Number(a));
    \\      else if (typeof a === "boolean") nums.push(a ? 1 : 0);
    \\      else __sa_trap("js callback: non-numeric argument from JS");
    \\    }
    \\    __sa_jsh_cb_queue.push({ fn: idx, args: nums });
    \\    return undefined;
    \\  };
    \\  return __sa_jsh_new(closure);
    \\}
    \\function __sa_jsh_cb_poll(fn_out, argc_out, args_out) {
    \\  const ev = __sa_jsh_cb_queue.shift();
    \\  if (!ev) return 0;
    \\  __sa_view.setBigUint64(__sa_addr(fn_out), __sa_fnptr(ev.fn), true);
    \\  __sa_view.setBigUint64(__sa_addr(argc_out), BigInt(ev.args.length), true);
    \\  const base = __sa_addr(args_out);
    \\  for (let i = 0; i < ev.args.length; i++) __sa_view.setFloat64(base + i * 8, ev.args[i], true);
    \\  return 1;
    \\}
    \\try {
    \\  const __sa_jsh_p = globalThis.process;
    \\  if (__sa_jsh_p && typeof __sa_jsh_p.on === "function") __sa_jsh_p.on("exit", () => {
    \\    if (__sa_jsh_cb_queue.length) { try { __sa_jsh_p.stderr.write("[sa-js] exit with " + __sa_jsh_cb_queue.length + " undrained callback event(s)\n"); } catch (e) {} }
    \\  });
    \\} catch (e) {}
    \\
;

/// Every extern name with a built-in host lowering in the emitter (as
/// opposed to a trap stub). A same-module `@export` never shadows these.
// sa2js net runtime chunk (BP): cookie engine, TLS config model,
// synchronous socket bridge (worker + SAB + Atomics.wait), netinfo.
// Emitted once per program that declares any BP net shim (gate below).
const jsnet_runtime_js =
    \\// ---- sa2js net runtime chunk (BP wave: cookie / tls-config / net-slice / netinfo) ----
    \\// Emitted ONCE per generated program that declares any BP net shim (see the
    \\// gate after writeRuntimeHeader in emit_js.zig). Pure functions operate on
    \\// Uint8Array byte strings (latin1-exact); shims adapt linear memory <-> bytes.
    \\// Cookie semantics mirror src/runtime/sa_cookie.zig exactly (RFC 6265);
    \\// TLS verification modes mirror src/runtime/sa_tls_client.zig.
    \\globalThis.__sa_jsnet = globalThis.__sa_jsnet || (function () {
    \\  "use strict";
    \\  // ---------- byte helpers ----------
    \\  function bLen(b) { return b.length; }
    \\  function bEq(a, b) {
    \\    if (a.length !== b.length) return false;
    \\    for (let i = 0; i < a.length; i++) if (a[i] !== b[i]) return false;
    \\    return true;
    \\  }
    \\  function bLower(b) {
    \\    const o = new Uint8Array(b.length);
    \\    for (let i = 0; i < b.length; i++) { const c = b[i]; o[i] = (c >= 65 && c <= 90) ? c + 32 : c; }
    \\    return o;
    \\  }
    \\  function bEqFold(a, b) { return bEq(bLower(a), bLower(b)); }
    \\  function bEndsWithFold(s, suf) {
    \\    if (suf.length > s.length) return false;
    \\    return bEqFold(s.subarray(s.length - suf.length), suf);
    \\  }
    \\  function bTrimOws(b) {
    \\    let a = 0, z = b.length;
    \\    while (a < z && (b[a] === 32 || b[a] === 9)) a++;
    \\    while (z > a && (b[z - 1] === 32 || b[z - 1] === 9)) z--;
    \\    return b.subarray(a, z);
    \\  }
    \\  function bIndexOf(b, byte, from) {
    \\    for (let i = (from || 0); i < b.length; i++) if (b[i] === byte) return i;
    \\    return -1;
    \\  }
    \\  function bFromStr(s) {
    \\    const o = new Uint8Array(s.length);
    \\    for (let i = 0; i < s.length; i++) o[i] = s.charCodeAt(i) & 255;
    \\    return o;
    \\  }
    \\  function bToStr(b) {
    \\    let s = "";
    \\    for (let i = 0; i < b.length; i++) s += String.fromCharCode(b[i]);
    \\    return s;
    \\  }
    \\  function bConcat(parts) {
    \\    let n = 0;
    \\    for (const p of parts) n += p.length;
    \\    const o = new Uint8Array(n);
    \\    let off = 0;
    \\    for (const p of parts) { o.set(p, off); off += p.length; }
    \\    return o;
    \\  }
    \\  function isDigit(c) { return c >= 48 && c <= 57; }
    \\  function isCtl(c) { return c < 32 || c === 127; }
    \\  function isTokenChar(c) {
    \\    if (c >= 48 && c <= 57) return true;
    \\    if (c >= 65 && c <= 90) return true;
    \\    if (c >= 97 && c <= 122) return true;
    \\    return c === 33 || c === 35 || c === 36 || c === 37 || c === 38 || c === 39 ||
    \\      c === 42 || c === 43 || c === 45 || c === 46 || c === 94 || c === 95 ||
    \\      c === 96 || c === 124 || c === 126;
    \\  }
    \\  function isCookieOctet(c) {
    \\    return c === 33 || (c >= 35 && c <= 43) || (c >= 45 && c <= 58) ||
    \\      (c >= 60 && c <= 91) || (c >= 93 && c <= 126);
    \\  }
    \\  function validCookieName(b) {
    \\    if (b.length === 0) return false;
    \\    for (let i = 0; i < b.length; i++) if (!isTokenChar(b[i])) return false;
    \\    return true;
    \\  }
    \\  function validCookieValue(b) {
    \\    for (let i = 0; i < b.length; i++) if (!isCookieOctet(b[i])) return false;
    \\    return true;
    \\  }
    \\  function validDomainAttr(b) {
    \\    if (b.length === 0) return false;
    \\    for (let i = 0; i < b.length; i++) {
    \\      const c = b[i];
    \\      const ok = (c >= 48 && c <= 57) || (c >= 65 && c <= 90) || (c >= 97 && c <= 122) ||
    \\        c === 45 || c === 46 || c === 95;
    \\      if (!ok) return false;
    \\    }
    \\    return true;
    \\  }
    \\  // ---------- dates (RFC 6265 5.1.1 + IMF-fixdate) ----------
    \\  function daysFromCivil(y0, m, d) {
    \\    let y = y0;
    \\    if (m <= 2) y -= 1;
    \\    const era = Math.floor(y / 400);
    \\    const yoe = y - era * 400;
    \\    const mp = (m > 2) ? m - 3 : m + 9;
    \\    const doy = Math.floor((153 * mp + 2) / 5) + d - 1;
    \\    const doe = yoe * 365 + Math.floor(yoe / 4) - Math.floor(yoe / 100) + doy;
    \\    return era * 146097 + doe - 719468;
    \\  }
    \\  function civilFromDays(z0) {
    \\    const z = z0 + 719468;
    \\    const era = Math.floor(z / 146097);
    \\    const doe = z - era * 146097;
    \\    const yoe = Math.floor((doe - Math.floor(doe / 1460) + Math.floor(doe / 36524) - Math.floor(doe / 146096)) / 365);
    \\    const y = yoe + era * 400;
    \\    const doy = doe - (365 * yoe + Math.floor(yoe / 4) - Math.floor(yoe / 100));
    \\    const mp = Math.floor((5 * doy + 2) / 153);
    \\    const d = doy - Math.floor((153 * mp + 2) / 5) + 1;
    \\    const m = (mp < 10) ? mp + 3 : mp - 9;
    \\    return { year: (m <= 2) ? y + 1 : y, month: m, day: d };
    \\  }
    \\  function isDateDelimiter(c) {
    \\    return c === 9 || (c >= 32 && c <= 47) || (c >= 59 && c <= 64) ||
    \\      (c >= 91 && c <= 96) || (c >= 123 && c <= 126);
    \\  }
    \\  const MONTH3 = ["jan", "feb", "mar", "apr", "may", "jun", "jul", "aug", "sep", "oct", "nov", "dec"];
    \\  function parseLeadingUint(tok, maxDigits) {
    \\    let v = 0, n = 0;
    \\    while (n < tok.length && n < maxDigits && isDigit(tok[n])) { v = v * 10 + (tok[n] - 48); n++; }
    \\    if (n === 0) return null;
    \\    return { value: v, digits: n };
    \\  }
    \\  function tokenTime(tok) {
    \\    const h = parseLeadingUint(tok, 2);
    \\    if (!h) return null;
    \\    let rest = tok.subarray(h.digits);
    \\    if (rest.length === 0 || rest[0] !== 58) return null;
    \\    rest = rest.subarray(1);
    \\    const m = parseLeadingUint(rest, 2);
    \\    if (!m) return null;
    \\    rest = rest.subarray(m.digits);
    \\    if (rest.length === 0 || rest[0] !== 58) return null;
    \\    rest = rest.subarray(1);
    \\    const s = parseLeadingUint(rest, 2);
    \\    if (!s) return null;
    \\    return { h: h.value, m: m.value, s: s.value };
    \\  }
    \\  function parseCookieDate(b) {
    \\    let time = null, day = null, month = null, year = null;
    \\    let i = 0;
    \\    while (i < b.length) {
    \\      while (i < b.length && isDateDelimiter(b[i])) i++;
    \\      if (i >= b.length) break;
    \\      const start = i;
    \\      while (i < b.length && !isDateDelimiter(b[i])) i++;
    \\      const tok = b.subarray(start, i);
    \\      if (time === null) {
    \\        const t = tokenTime(tok);
    \\        if (t) { time = t; continue; }
    \\      }
    \\      if (day === null) {
    \\        const d = parseLeadingUint(tok, 2);
    \\        if (d && (d.digits === tok.length || !isDigit(tok[d.digits]))) { day = d.value; continue; }
    \\      }
    \\      if (month === null && tok.length >= 3) {
    \\        const first3 = bLower(tok.subarray(0, 3));
    \\        let mo = null;
    \\        for (let k = 0; k < 12; k++) {
    \\          if (bEq(first3, bFromStr(MONTH3[k]))) { mo = k + 1; break; }
    \\        }
    \\        if (mo !== null) { month = mo; continue; }
    \\      }
    \\      if (year === null) {
    \\        const y = parseLeadingUint(tok, 4);
    \\        if (y && y.digits >= 2 && (y.digits === tok.length || !isDigit(tok[y.digits]))) {
    \\          let v = y.value;
    \\          if (y.digits === 2) v += (v >= 70) ? 1900 : 2000;
    \\          year = v;
    \\          continue;
    \\        }
    \\      }
    \\    }
    \\    if (time === null || day === null || month === null || year === null) return null;
    \\    if (day < 1 || day > 31) return null;
    \\    if (year < 1601) return null;
    \\    if (time.h > 23 || time.m > 59 || time.s > 59) return null;
    \\    return daysFromCivil(year, month, day) * 86400 + time.h * 3600 + time.m * 60 + time.s;
    \\  }
    \\  const WEEKDAY = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"];
    \\  const MONTHFULL = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"];
    \\  function pad2(n) { return (n < 10 ? "0" : "") + n; }
    \\  function pad4(n) { let s = String(n); while (s.length < 4) s = "0" + s; return s; }
    \\  function formatImfFixdate(unix) {
    \\    const days = Math.floor(unix / 86400);
    \\    let rem = unix - days * 86400;
    \\    const c = civilFromDays(days);
    \\    const wd = ((days + 4) % 7 + 7) % 7;
    \\    const hh = Math.floor(rem / 3600); rem -= hh * 3600;
    \\    const mm = Math.floor(rem / 60); const ss = rem - mm * 60;
    \\    const ystr = (c.year >= 0 && c.year <= 9999) ? pad4(c.year) : String(c.year);
    \\    return bFromStr(WEEKDAY[wd] + ", " + pad2(c.day) + " " + MONTHFULL[c.month - 1] + " " +
    \\      ystr + " " + pad2(hh) + ":" + pad2(mm) + ":" + pad2(ss) + " GMT");
    \\  }
    \\
    \\  // ---------- cookie value layer ----------
    \\  function mkCookie(name, value) {
    \\    return { name: name, value: value, domain: new Uint8Array(0), hasDomain: false,
    \\      hostOnly: false, path: new Uint8Array(0), hasPath: false, expires: null,
    \\      maxAge: null, secure: false, httpOnly: false, partitioned: false, sameSite: 0, seq: 0 };
    \\  }
    \\  function cloneCookie(c) {
    \\    const o = mkCookie(c.name.slice(), c.value.slice());
    \\    o.domain = c.domain.slice(); o.hasDomain = c.hasDomain; o.hostOnly = c.hostOnly;
    \\    o.path = c.path.slice(); o.hasPath = c.hasPath; o.expires = c.expires;
    \\    o.maxAge = c.maxAge; o.secure = c.secure; o.httpOnly = c.httpOnly;
    \\    o.partitioned = c.partitioned; o.sameSite = c.sameSite; o.seq = c.seq;
    \\    return o;
    \\  }
    \\  function parseMaxAge(b) {
    \\    if (b.length === 0) return null;
    \\    let idx = 0, neg = false;
    \\    if (b[0] === 45) { neg = true; idx = 1; }
    \\    if (idx >= b.length) return null;
    \\    let v = 0;
    \\    const cap = 1 << 62;
    \\    while (idx < b.length) {
    \\      const c = b[idx];
    \\      if (!isDigit(c)) return null;
    \\      const d = c - 48;
    \\      v = (v >= Math.floor((cap - 9) / 10)) ? cap : v * 10 + d;
    \\      idx++;
    \\    }
    \\    return neg ? -v : v;
    \\  }
    \\  function parseSetCookie(raw) {
    \\    const firstSemi = bIndexOf(raw, 59, 0);
    \\    const pairEnd = (firstSemi < 0) ? raw.length : firstSemi;
    \\    const pair = bTrimOws(raw.subarray(0, pairEnd));
    \\    const eq = bIndexOf(pair, 61, 0);
    \\    if (eq < 0) return null;
    \\    const name = bTrimOws(pair.subarray(0, eq));
    \\    if (!validCookieName(name)) return null;
    \\    let value = bTrimOws(pair.subarray(eq + 1));
    \\    if (value.length >= 2 && value[0] === 34 && value[value.length - 1] === 34) {
    \\      value = value.subarray(1, value.length - 1);
    \\    }
    \\    if (!validCookieValue(value)) return null;
    \\    const cookie = mkCookie(name.slice(), value.slice());
    \\    if (firstSemi >= 0) {
    \\      let pos = firstSemi + 1;
    \\      while (pos <= raw.length) {
    \\        const next = bIndexOf(raw, 59, pos);
    \\        const segEnd = (next < 0) ? raw.length : next;
    \\        const attr = bTrimOws(raw.subarray(pos, segEnd));
    \\        if (attr.length > 0) {
    \\          const aeq = bIndexOf(attr, 61, 0);
    \\          const aname = (aeq < 0) ? attr : bTrimOws(attr.subarray(0, aeq));
    \\          const avalue = (aeq < 0) ? new Uint8Array(0) : bTrimOws(attr.subarray(aeq + 1));
    \\          if (bEqFold(aname, bFromStr("expires"))) {
    \\            const ts = parseCookieDate(avalue);
    \\            if (ts !== null) cookie.expires = ts;
    \\          } else if (bEqFold(aname, bFromStr("max-age"))) {
    \\            const ma = parseMaxAge(avalue);
    \\            if (ma !== null) cookie.maxAge = ma;
    \\          } else if (bEqFold(aname, bFromStr("domain"))) {
    \\            let d = avalue;
    \\            if (d.length > 0 && d[0] === 46) d = d.subarray(1);
    \\            if (validDomainAttr(d)) { cookie.domain = bLower(d).slice(); cookie.hasDomain = true; }
    \\          } else if (bEqFold(aname, bFromStr("path"))) {
    \\            if (avalue.length > 0 && avalue[0] === 47) {
    \\              let bad = false;
    \\              for (let i = 0; i < avalue.length; i++) if (isCtl(avalue[i])) bad = true;
    \\              if (!bad) { cookie.path = avalue.slice(); cookie.hasPath = true; }
    \\            }
    \\          } else if (bEqFold(aname, bFromStr("secure"))) {
    \\            cookie.secure = true;
    \\          } else if (bEqFold(aname, bFromStr("httponly"))) {
    \\            cookie.httpOnly = true;
    \\          } else if (bEqFold(aname, bFromStr("partitioned"))) {
    \\            cookie.partitioned = true;
    \\          } else if (bEqFold(aname, bFromStr("samesite"))) {
    \\            if (bEqFold(avalue, bFromStr("lax"))) cookie.sameSite = 1;
    \\            else if (bEqFold(avalue, bFromStr("strict"))) cookie.sameSite = 2;
    \\            else if (bEqFold(avalue, bFromStr("none"))) cookie.sameSite = 3;
    \\          }
    \\        }
    \\        if (next < 0) break;
    \\        pos = next + 1;
    \\      }
    \\    }
    \\    return cookie;
    \\  }
    \\  function serializeCookie(c, pairOnly) {
    \\    const parts = [c.name, bFromStr("="), c.value];
    \\    if (pairOnly) return bConcat(parts);
    \\    if (c.hasDomain) parts.push(bFromStr("; Domain="), c.domain);
    \\    if (c.hasPath) parts.push(bFromStr("; Path="), c.path);
    \\    if (c.expires !== null) parts.push(bFromStr("; Expires="), formatImfFixdate(c.expires));
    \\    if (c.maxAge !== null) parts.push(bFromStr("; Max-Age=" + String(c.maxAge)));
    \\    if (c.secure) parts.push(bFromStr("; Secure"));
    \\    if (c.httpOnly) parts.push(bFromStr("; HttpOnly"));
    \\    if (c.sameSite === 1) parts.push(bFromStr("; SameSite=Lax"));
    \\    else if (c.sameSite === 2) parts.push(bFromStr("; SameSite=Strict"));
    \\    else if (c.sameSite === 3) parts.push(bFromStr("; SameSite=None"));
    \\    if (c.partitioned) parts.push(bFromStr("; Partitioned"));
    \\    return bConcat(parts);
    \\  }
    \\  function hostIsIp(host) {
    \\    if (host.length === 0) return false;
    \\    if (bIndexOf(host, 58, 0) >= 0) return true;
    \\    let parts = 0, pos = 0;
    \\    while (pos <= host.length) {
    \\      const dot = bIndexOf(host, 46, pos);
    \\      const end = (dot < 0) ? host.length : dot;
    \\      const part = host.subarray(pos, end);
    \\      if (part.length === 0 || part.length > 3) return false;
    \\      for (let i = 0; i < part.length; i++) if (!isDigit(part[i])) return false;
    \\      parts++;
    \\      if (dot < 0) break;
    \\      pos = dot + 1;
    \\    }
    \\    return parts === 4;
    \\  }
    \\  function domainMatch(domain, host) {
    \\    if (domain.length === 0 || host.length === 0) return false;
    \\    if (bEqFold(domain, host)) return true;
    \\    if (hostIsIp(host)) return false;
    \\    if (host.length <= domain.length) return false;
    \\    if (host[host.length - domain.length - 1] !== 46) return false;
    \\    return bEndsWithFold(host, domain);
    \\  }
    \\  function pathMatch(cookiePath, requestPath) {
    \\    if (cookiePath.length === 0) return false;
    \\    const rp = (requestPath.length === 0) ? bFromStr("/") : requestPath;
    \\    if (bEq(cookiePath, rp)) return true;
    \\    if (rp.length > cookiePath.length) {
    \\      let pre = true;
    \\      for (let i = 0; i < cookiePath.length; i++) if (rp[i] !== cookiePath[i]) { pre = false; break; }
    \\      if (pre) {
    \\        if (cookiePath[cookiePath.length - 1] === 47) return true;
    \\        if (rp[cookiePath.length] === 47) return true;
    \\      }
    \\    }
    \\    return false;
    \\  }
    \\  function defaultPath(uriPath) {
    \\    if (uriPath.length === 0 || uriPath[0] !== 47) return bFromStr("/");
    \\    let last = -1;
    \\    for (let i = 0; i < uriPath.length; i++) if (uriPath[i] === 47) last = i;
    \\    if (last <= 0) return bFromStr("/");
    \\    return uriPath.subarray(0, last);
    \\  }
    \\  function splitUrl(url) {
    \\    const schemeEnd = bToStr(url).indexOf("://");
    \\    if (schemeEnd < 0) return null;
    \\    const scheme = url.subarray(0, schemeEnd);
    \\    if (scheme.length === 0) return null;
    \\    for (let i = 0; i < scheme.length; i++) {
    \\      const c = scheme[i];
    \\      if (isCtl(c) || c === 32 || c === 47) return null;
    \\    }
    \\    let rest = url.subarray(schemeEnd + 3);
    \\    let authEnd = rest.length;
    \\    for (let i = 0; i < rest.length; i++) {
    \\      const c = rest[i];
    \\      if (c === 47 || c === 63 || c === 35) { authEnd = i; break; }
    \\    }
    \\    let authority = rest.subarray(0, authEnd);
    \\    rest = rest.subarray(authEnd);
    \\    let at = -1;
    \\    for (let i = 0; i < authority.length; i++) if (authority[i] === 64) at = i;
    \\    if (at >= 0) authority = authority.subarray(at + 1);
    \\    let host;
    \\    if (authority.length > 0 && authority[0] === 91) {
    \\      const close = bIndexOf(authority, 93, 0);
    \\      if (close < 0) return null;
    \\      host = authority.subarray(1, close);
    \\    } else {
    \\      const colon = bIndexOf(authority, 58, 0);
    \\      host = (colon < 0) ? authority : authority.subarray(0, colon);
    \\    }
    \\    if (host.length === 0) return null;
    \\    let path = new Uint8Array(0);
    \\    if (rest.length > 0 && rest[0] === 47) {
    \\      let pathEnd = rest.length;
    \\      for (let i = 0; i < rest.length; i++) {
    \\        const c = rest[i];
    \\        if (c === 63 || c === 35) { pathEnd = i; break; }
    \\      }
    \\      path = rest.subarray(0, pathEnd);
    \\    }
    \\    return { scheme: scheme, host: host, path: path };
    \\  }
    \\  function originTrustworthy(scheme, host) {
    \\    if (bEqFold(scheme, bFromStr("https")) || bEqFold(scheme, bFromStr("wss"))) return true;
    \\    if (bEqFold(host, bFromStr("localhost")) || bEndsWithFold(host, bFromStr(".localhost"))) return true;
    \\    if (bEq(host, bFromStr("127.0.0.1")) || bEq(host, bFromStr("::1"))) return true;
    \\    return false;
    \\  }
    \\  // ---------- cookie registries + last error ----------
    \\  const CK = { cookies: new Map(), jars: new Map(), next: 1, err: null };
    \\  function ckErrSet(msg) { CK.err = bFromStr(msg); }
    \\  function ckErrClear() { CK.err = null; }
    \\  function ckErrGet() { return CK.err; }
    \\  function ckReg(c) { const h = CK.next++; CK.cookies.set(h, c); return h; }
    \\  function ckGet(h) { return CK.cookies.get(h) || null; }
    \\  function ckFree(h) { return CK.cookies.delete(h); }
    \\  function jarReg(j) { const h = CK.next++; CK.jars.set(h, j); return h; }
    \\  function jarGet(h) { return CK.jars.get(h) || null; }
    \\  function jarFree(h) { return CK.jars.delete(h); }
    \\  function mkJar() { return { entries: [], policy: 0, nextSeq: 1 }; }
    \\  function jarFind(jar, name, domain, path) {
    \\    for (let i = 0; i < jar.entries.length; i++) {
    \\      const e = jar.entries[i];
    \\      if (bEq(e.name, name) && bEq(e.domain, domain) && bEq(e.path, path)) return i;
    \\    }
    \\    return -1;
    \\  }
    \\  function jarInsert(jar, entry) {
    \\    const idx = jarFind(jar, entry.name, entry.domain, entry.path);
    \\    if (idx >= 0) { const seq = jar.entries[idx].seq; entry.seq = seq; jar.entries[idx] = entry; return 1; }
    \\    entry.seq = jar.nextSeq++;
    \\    jar.entries.push(entry);
    \\    return 0;
    \\  }
    \\  function jarEvict(jar, now) {
    \\    let removed = 0;
    \\    for (let i = jar.entries.length - 1; i >= 0; i--) {
    \\      const e = jar.entries[i];
    \\      if (e.expires !== null && e.expires <= now) { jar.entries.splice(i, 1); removed++; }
    \\    }
    \\    return removed;
    \\  }
    \\  // returns STORE code 0..4, or -1 for call-level invalid (bad url / bad cookie)
    \\  function jarStore(jar, urlB, scB, now) {
    \\    const url = splitUrl(urlB);
    \\    if (!url) return -1;
    \\    const parsed = parseSetCookie(scB);
    \\    if (!parsed) return -1;
    \\    if (jar.policy === 1) return 4;
    \\    const hostLower = bLower(url.host);
    \\    let domain, hostOnly;
    \\    if (parsed.hasDomain && jar.policy !== 2) {
    \\      if (!domainMatch(parsed.domain, hostLower)) return 4;
    \\      domain = parsed.domain.slice(); hostOnly = false;
    \\    } else {
    \\      domain = hostLower.slice(); hostOnly = true;
    \\    }
    \\    if (parsed.secure && !originTrustworthy(url.scheme, hostLower)) return 4;
    \\    const path = parsed.hasPath ? parsed.path.slice() : defaultPath(url.path).slice();
    \\    let expires = parsed.expires;
    \\    if (parsed.maxAge !== null) expires = (parsed.maxAge <= 0) ? now : now + parsed.maxAge;
    \\    const entry = mkCookie(parsed.name.slice(), parsed.value.slice());
    \\    entry.domain = domain; entry.hasDomain = true; entry.hostOnly = hostOnly;
    \\    entry.path = path; entry.hasPath = true; entry.expires = expires;
    \\    entry.secure = parsed.secure; entry.httpOnly = parsed.httpOnly;
    \\    entry.partitioned = parsed.partitioned; entry.sameSite = parsed.sameSite;
    \\    if (expires !== null && expires <= now) {
    \\      const idx = jarFind(jar, entry.name, entry.domain, entry.path);
    \\      if (idx >= 0) { jar.entries.splice(idx, 1); return 2; }
    \\      return 3;
    \\    }
    \\    return jarInsert(jar, entry);
    \\  }
    \\  function jarHeader(jar, urlB, now) {
    \\    const url = splitUrl(urlB);
    \\    if (!url) return null;
    \\    jarEvict(jar, now);
    \\    const matches = [];
    \\    for (const e of jar.entries) {
    \\      if (e.hostOnly) { if (!bEqFold(e.domain, url.host)) continue; }
    \\      else { if (!domainMatch(e.domain, url.host)) continue; }
    \\      if (!pathMatch(e.path, url.path)) continue;
    \\      if (e.secure && !originTrustworthy(url.scheme, url.host)) continue;
    \\      matches.push(e);
    \\    }
    \\    if (matches.length === 0) return null;
    \\    matches.sort((a, b) => {
    \\      if (a.path.length !== b.path.length) return b.path.length - a.path.length;
    \\      return a.seq - b.seq;
    \\    });
    \\    const parts = [];
    \\    for (let i = 0; i < matches.length; i++) {
    \\      if (i > 0) parts.push(bFromStr("; "));
    \\      parts.push(serializeCookie(matches[i], true));
    \\    }
    \\    return bConcat(parts);
    \\  }
    \\  function jarSaveText(jar) {
    \\    const parts = [bFromStr("# Netscape HTTP Cookie File\n# Written by sa_std (sa_cookie_jar_save). HttpOnly cookies carry the #HttpOnly_ prefix.\n\n")];
    \\    for (const e of jar.entries) {
    \\      if (e.httpOnly) parts.push(bFromStr("#HttpOnly_"));
    \\      if (e.hostOnly) parts.push(e.domain);
    \\      else parts.push(bFromStr("."), e.domain);
    \\      parts.push(bFromStr("\t"), bFromStr(e.hostOnly ? "FALSE" : "TRUE"));
    \\      parts.push(bFromStr("\t"), e.path);
    \\      parts.push(bFromStr("\t"), bFromStr(e.secure ? "TRUE" : "FALSE"));
    \\      parts.push(bFromStr("\t"), bFromStr(String(e.expires === null ? 0 : e.expires)));
    \\      parts.push(bFromStr("\t"), e.name, bFromStr("\t"), e.value, bFromStr("\n"));
    \\    }
    \\    return bConcat(parts);
    \\  }
    \\  // returns { loaded } or { error } ; on error the jar is untouched
    \\  function jarLoad(jar, data) {
    \\    const pending = [];
    \\    let lineNo = 0, pos = 0;
    \\    while (pos <= data.length) {
    \\      const nl = bIndexOf(data, 10, pos);
    \\      const rawEnd = (nl < 0) ? data.length : nl;
    \\      let line = data.subarray(pos, rawEnd);
    \\      lineNo++;
    \\      if (line.length > 0 && line[line.length - 1] === 13) line = line.subarray(0, line.length - 1);
    \\      if (line.length > 0) {
    \\        let httpOnly = false;
    \\        if (line.length >= 10 && bEq(line.subarray(0, 10), bFromStr("#HttpOnly_"))) {
    \\          httpOnly = true; line = line.subarray(10);
    \\        } else if (line[0] === 35) {
    \\          line = null;
    \\        }
    \\        if (line !== null) {
    \\          const fields = [];
    \\          let fpos = 0;
    \\          while (fpos <= line.length) {
    \\            const tab = bIndexOf(line, 9, fpos);
    \\            const fend = (tab < 0) ? line.length : tab;
    \\            fields.push(line.subarray(fpos, fend));
    \\            if (tab < 0) break;
    \\            fpos = tab + 1;
    \\          }
    \\          if (fields.length > 7) return { error: "cookie: netscape line " + lineNo + " has too many fields" };
    \\          if (fields.length !== 7) return { error: "cookie: netscape line " + lineNo + " has " + fields.length + " fields, want 7" };
    \\          const flagAll = bToStr(fields[1]);
    \\          const secureWord = bToStr(fields[3]);
    \\          if (flagAll !== "TRUE" && flagAll !== "FALSE") return { error: "cookie: netscape line " + lineNo + " has a bad domain flag" };
    \\          if (secureWord !== "TRUE" && secureWord !== "FALSE") return { error: "cookie: netscape line " + lineNo + " has a bad secure flag" };
    \\          const expStr = bToStr(fields[4]);
    \\          if (!/^[+-]?\d+$/.test(expStr)) return { error: "cookie: netscape line " + lineNo + " has a bad expiry" };
    \\          let exp = null;
    \\          try {
    \\            const bv = BigInt(expStr);
    \\            if (bv > 9223372036854775807n || bv < -9223372036854775808n) return { error: "cookie: netscape line " + lineNo + " has a bad expiry" };
    \\            exp = (bv === 0n) ? null : Number(bv);
    \\          } catch (e) { return { error: "cookie: netscape line " + lineNo + " has a bad expiry" }; }
    \\          let domain = fields[0];
    \\          if (domain.length > 0 && domain[0] === 46) domain = domain.subarray(1);
    \\          if (!validDomainAttr(domain)) return { error: "cookie: netscape line " + lineNo + " has a bad domain" };
    \\          if (!validCookieName(fields[5])) return { error: "cookie: netscape line " + lineNo + " has a bad name" };
    \\          if (!validCookieValue(fields[6])) return { error: "cookie: netscape line " + lineNo + " has a bad value" };
    \\          if (fields[2].length === 0 || fields[2][0] !== 47) return { error: "cookie: netscape line " + lineNo + " has a bad path" };
    \\          const entry = mkCookie(fields[5].slice(), fields[6].slice());
    \\          entry.domain = bLower(domain).slice(); entry.hasDomain = true;
    \\          entry.hostOnly = (flagAll === "FALSE");
    \\          entry.path = fields[2].slice(); entry.hasPath = true;
    \\          entry.expires = exp; entry.secure = (secureWord === "TRUE"); entry.httpOnly = httpOnly;
    \\          pending.push(entry);
    \\        }
    \\      }
    \\      if (nl < 0) break;
    \\      pos = nl + 1;
    \\    }
    \\    let loaded = 0;
    \\    for (const e of pending) { jarInsert(jar, e); loaded++; }
    \\    return { loaded: loaded };
    \\  }
    \\  function parseHeaderPair(seg) {
    \\    const eq = bIndexOf(seg, 61, 0);
    \\    if (eq < 0) return null;
    \\    const name = bTrimOws(seg.subarray(0, eq));
    \\    if (!validCookieName(name)) return null;
    \\    let value = bTrimOws(seg.subarray(eq + 1));
    \\    if (value.length >= 2 && value[0] === 34 && value[value.length - 1] === 34) {
    \\      value = value.subarray(1, value.length - 1);
    \\    }
    \\    if (!validCookieValue(value)) return null;
    \\    return mkCookie(name.slice(), value.slice());
    \\  }
    \\  // returns count, or -1 on any bad pair
    \\  function headerPairCount(raw) {
    \\    let count = 0, pos = 0;
    \\    while (pos <= raw.length) {
    \\      const semi = bIndexOf(raw, 59, pos);
    \\      const end = (semi < 0) ? raw.length : semi;
    \\      const seg = bTrimOws(raw.subarray(pos, end));
    \\      if (seg.length > 0) {
    \\        if (!parseHeaderPair(seg)) return -1;
    \\        count++;
    \\      }
    \\      if (semi < 0) break;
    \\      pos = semi + 1;
    \\    }
    \\    return count;
    \\  }
    \\  // returns cookie, the string "bad" (indexed pair malformed -> last_error),
    \\  // or null (index out of range -> no error)
    \\  function headerPairAt(raw, index) {
    \\    let idx = 0, pos = 0;
    \\    while (pos <= raw.length) {
    \\      const semi = bIndexOf(raw, 59, pos);
    \\      const end = (semi < 0) ? raw.length : semi;
    \\      const seg = bTrimOws(raw.subarray(pos, end));
    \\      if (seg.length > 0) {
    \\        if (idx === index) {
    \\          const c = parseHeaderPair(seg);
    \\          return c === null ? "bad" : c;
    \\        }
    \\        idx++;
    \\      }
    \\      if (semi < 0) break;
    \\      pos = semi + 1;
    \\    }
    \\    return null;
    \\  }
    \\
    \\  // ---------- synchronous socket bridge (worker + SAB + Atomics.wait) ----------
    \\  // SA calls are synchronous; Node net/tls/dgram are async. One worker thread
    \\  // owns every real socket; the main thread issues one request at a time and
    \\  // blocks in Atomics.wait. No emitter async-lowering change is involved:
    \\  // the asynchrony is confined to the worker, and SA programs observe plain
    \\  // synchronous call/return semantics. If Worker/SAB/Atomics are unavailable
    \\  // (browser builds), every bridge op answers the family's UNSUPPORTED code.
    \\  function __sa_jsnet_worker() {
    \\    "use strict";
    \\    const { parentPort, workerData } = require("node:worker_threads");
    \\    const net = require("node:net");
    \\    const tls = require("node:tls");
    \\    const dgram = require("node:dgram");
    \\    const dns = require("node:dns");
    \\    const crypto = require("node:crypto");
    \\    const sab = workerData.sab;
    \\    const hdr = new Int32Array(sab, 0, 4);
    \\    const data = new Uint8Array(sab, 256);
    \\    const enc = new TextEncoder();
    \\    const dec = new TextDecoder();
    \\    const socks = new Map();
    \\    let nextId = 1;
    \\    function respond(status, json, payload) {
    \\      const jb = enc.encode(JSON.stringify(Object.assign({ __status: status }, json || {})));
    \\      data.set(jb, 0);
    \\      let plen = 0;
    \\      if (payload && payload.length) { data.set(payload, jb.length); plen = payload.length; }
    \\      hdr[2] = jb.length;
    \\      hdr[3] = plen;
    \\      Atomics.store(hdr, 0, 2);
    \\      Atomics.notify(hdr, 0);
    \\    }
    \\    function fail(status, msg) { respond(status, { error: String(msg || "error") }, null); }
    \\    function getSock(id) { return socks.get(id) || null; }
    \\    function udpEntry(sock) {
    \\      const e = { kind: "udp", sock: sock, queue: [], waiter: null, readTimeoutMs: 0, writeTimeoutMs: 0, opts: new Map() };
    \\      sock.on("message", (msg, rinfo) => {
    \\        const item = { buf: Buffer.from(msg), src: { host: rinfo.address, port: rinfo.port, family: rinfo.family } };
    \\        if (e.waiter) { const w = e.waiter; e.waiter = null; w(item); }
    \\        else e.queue.push(item);
    \\      });
    \\      sock.on("error", () => {});
    \\      return e;
    \\    }
    \\    function streamEntry(kind, sock) {
    \\      const e = { kind: kind, sock: sock, chunks: [], buffered: 0, waiter: null, eof: false, readTimeoutMs: 0, writeTimeoutMs: 0, opts: new Map() };
    \\      sock.on("data", (chunk) => {
    \\        e.chunks.push(chunk); e.buffered += chunk.length;
    \\        if (e.waiter) { const w = e.waiter; e.waiter = null; w(); }
    \\      });
    \\      const done = () => { e.eof = true; if (e.waiter) { const w = e.waiter; e.waiter = null; w(); } };
    \\      sock.on("end", done);
    \\      sock.on("close", done);
    \\      sock.on("error", done);
    \\      return e;
    \\    }
    \\    function waitReadable(e, timeoutMs) {
    \\      return new Promise((resolve) => {
    \\        let settled = false;
    \\        const finish = (v) => { if (!settled) { settled = true; resolve(v); } };
    \\        e.waiter = () => finish("data");
    \\        if (e.eof) finish("eof");
    \\        if (timeoutMs > 0) setTimeout(() => finish("timeout"), timeoutMs);
    \\      });
    \\    }
    \\    const CERT_ERR = /CERT|certificate|self.signed|unable to verify|altname|ALPN/i;
    \\    function tlsErrStatus(err) {
    \\      if (!err) return -5;
    \\      const code = String(err.code || "");
    \\      const msg = String(err.message || err);
    \\      if (CERT_ERR.test(code) || CERT_ERR.test(msg)) return -100;
    \\      return -5;
    \\    }
    \\    async function tlsUpgrade(existingSock, p) {
    \\      const serverName = (p.serverName === undefined) ? null : p.serverName;
    \\      const caPems = p.caPems || [];
    \\      let opts = { servername: undefined };
    \\      if (existingSock) opts.socket = existingSock;
    \\      else { opts.host = p.host; opts.port = p.port; }
    \\      if (p.insecure) {
    \\        opts.rejectUnauthorized = false;
    \\        opts.servername = serverName === null ? undefined : serverName;
    \\      } else if (p.verifySelfSigned) {
    \\        opts.rejectUnauthorized = false;
    \\        opts.servername = serverName === null ? p.host : serverName;
    \\      } else {
    \\        opts.rejectUnauthorized = true;
    \\        opts.ca = tls.rootCertificates.concat(caPems);
    \\        opts.servername = serverName === null ? p.host : serverName;
    \\      }
    \\      const sock = tls.connect(opts);
    \\      await new Promise((resolve, reject) => {
    \\        let done = false;
    \\        const ok = () => { if (!done) { done = true; resolve(); } };
    \\        const bad = (e) => { if (!done) { done = true; reject(e); } };
    \\        sock.once("secureConnect", ok);
    \\        sock.once("error", bad);
    \\        if (p.timeoutMs > 0) setTimeout(() => bad(new Error("tls handshake timeout")), p.timeoutMs);
    \\      }).catch((err) => { try { sock.destroy(); } catch (e2) {} throw err; });
    \\      if (p.insecure) return sock;
    \\      if (p.verifySelfSigned) {
    \\        const cert = sock.getPeerCertificate(true);
    \\        if (!cert || !cert.raw) { sock.destroy(); const e = new Error("no peer certificate"); e.code = "CERT"; throw e; }
    \\        let x;
    \\        try { x = new crypto.X509Certificate(cert.raw); } catch (e2) { sock.destroy(); const e = new Error("peer certificate unparsable"); e.code = "CERT"; throw e; }
    \\        const now = Date.now();
    \\        const selfSigned = (x.issuer === x.subject) && x.verify(x.publicKey);
    \\        const inDate = (Date.parse(x.validFrom) <= now) && (now <= Date.parse(x.validTo));
    \\        const idErr = tls.checkServerIdentity(serverName === null ? p.host : serverName, cert);
    \\        if (!selfSigned || !inDate || idErr) { sock.destroy(); const e = new Error("self-signed verification failed: " + (idErr ? idErr.message : (!selfSigned ? "not self-signed" : "out of date"))); e.code = "CERT"; throw e; }
    \\        return sock;
    \\      }
    \\      if (!sock.authorized) {
    \\        const e = new Error("peer verification failed: " + String(sock.authorizationError || "unauthorized"));
    \\        e.code = "CERT";
    \\        sock.destroy();
    \\        throw e;
    \\      }
    \\      return sock;
    \\    }
    \\    async function handle(req, payload) {
    \\      const op = req.op;
    \\      try {
    \\        switch (op) {
    \\          case "resolve": {
    \\            const addrs = await dns.promises.lookup(req.host, { all: true, verbatim: true }).catch((e) => { throw Object.assign(new Error("resolve failed"), { saStatus: 7 }); });
    \\            respond(0, { addrs: addrs.map((a) => ({ host: a.address, family: a.family })) }, null);
    \\            return;
    \\          }
    \\          case "udp_bind": {
    \\            const fam = (req.host && req.host.indexOf(":") >= 0) ? "udp6" : "udp4";
    \\            const sock = dgram.createSocket(fam);
    \\            const e = udpEntry(sock);
    \\            await new Promise((resolve, reject) => {
    \\              sock.once("error", reject);
    \\              sock.bind(req.port, req.host, () => resolve());
    \\            }).catch((err) => { try { sock.close(); } catch (e2) {} throw Object.assign(err, { saStatus: 6 }); });
    \\            const id = nextId++;
    \\            socks.set(id, e);
    \\            const addr = sock.address();
    \\            respond(0, { id: id, port: addr.port, host: addr.address, family: addr.family }, null);
    \\            return;
    \\          }
    \\          case "udp_connect": {
    \\            const e = getSock(req.id); if (!e || e.kind !== "udp") return fail(2, "bad handle");
    \\            await new Promise((resolve, reject) => { e.sock.connect(req.port, req.host, (err) => err ? reject(err) : resolve()); })
    \\              .catch((err) => { throw Object.assign(err, { saStatus: 6 }); });
    \\            respond(0, {}, null);
    \\            return;
    \\          }
    \\          case "udp_send": {
    \\            const e = getSock(req.id); if (!e || e.kind !== "udp") return fail(2, "bad handle");
    \\            const buf = Buffer.from(payload || []);
    \\            const sendP = req.dest
    \\              ? new Promise((res, rej) => { e.sock.send(buf, req.dest.port, req.dest.host, (err, bytes) => err ? rej(err) : res(bytes)); })
    \\              : new Promise((res, rej) => { e.sock.send(buf, (err, bytes) => err ? rej(err) : res(bytes)); });
    \\            const n = await sendP.catch((err) => { throw Object.assign(err, { saStatus: 6 }); });
    \\            respond(0, { written: n }, null);
    \\            return;
    \\          }
    \\          case "udp_recv": {
    \\            const e = getSock(req.id); if (!e || e.kind !== "udp") return fail(2, "bad handle");
    \\            let item = e.queue.shift() || null;
    \\            if (!item) {
    \\              const what = await new Promise((resolve) => {
    \\                let settled = false;
    \\                const fin = (v) => { if (!settled) { settled = true; resolve(v); } };
    \\                e.waiter = (it) => fin(it);
    \\                if (e.readTimeoutMs > 0) setTimeout(() => { if (e.waiter) e.waiter = null; fin(null); }, e.readTimeoutMs);
    \\              });
    \\              item = what;
    \\              if (!item) return fail(6, "recv timeout");
    \\            }
    \\            const cap = req.cap || item.buf.length;
    \\            const out = item.buf.subarray(0, cap);
    \\            respond(0, { read: out.length, src: item.src }, out);
    \\            return;
    \\          }
    \\          case "udp_set_read_timeout": {
    \\            const e = getSock(req.id); if (!e) return fail(2, "bad handle");
    \\            e.readTimeoutMs = req.timeoutMs || 0;
    \\            respond(0, {}, null);
    \\            return;
    \\          }
    \\          case "sock_close": {
    \\            const e = getSock(req.id); if (!e) return fail(2, "bad handle");
    \\            socks.delete(req.id);
    \\            try { if (e.kind === "udp") e.sock.close(); else e.sock.destroy(); } catch (err) {}
    \\            respond(0, {}, null);
    \\            return;
    \\          }
    \\          case "tcp_connect": {
    \\            const sock = net.connect({ host: req.host, port: req.port });
    \\            const e = streamEntry("tcp", sock);
    \\            await new Promise((resolve, reject) => {
    \\              let done = false;
    \\              const ok = () => { if (!done) { done = true; resolve(); } };
    \\              const bad = (err) => { if (!done) { done = true; reject(err); } };
    \\              sock.once("connect", ok);
    \\              sock.once("error", bad);
    \\              if (req.timeoutMs > 0) setTimeout(() => bad(new Error("connect timeout")), req.timeoutMs);
    \\            }).catch((err) => { try { sock.destroy(); } catch (e2) {} throw Object.assign(err, { saStatus: 6 }); });
    \\            const id = nextId++;
    \\            socks.set(id, e);
    \\            respond(0, { id: id, local: { host: sock.localAddress, port: sock.localPort }, peer: { host: sock.remoteAddress, port: sock.remotePort } }, null);
    \\            return;
    \\          }
    \\          case "stream_read": {
    \\            const e = getSock(req.id); if (!e || (e.kind !== "tcp" && e.kind !== "tls")) return fail(2, "bad handle");
    \\            const cap = req.cap;
    \\            while (e.buffered === 0 && !e.eof) {
    \\              const what = await waitReadable(e, e.readTimeoutMs);
    \\              if (what === "timeout") return fail(req.tlsSpace ? -5 : 6, "read timeout");
    \\            }
    \\            if (e.buffered === 0 && e.eof) { respond(0, { read: 0, eof: true }, null); return; }
    \\            const parts = [];
    \\            let need = cap;
    \\            while (need > 0 && e.chunks.length) {
    \\              const c = e.chunks[0];
    \\              if (c.length <= need) { parts.push(c); e.chunks.shift(); e.buffered -= c.length; need -= c.length; }
    \\              else { parts.push(c.subarray(0, need)); e.chunks[0] = c.subarray(need); e.buffered -= need; need = 0; }
    \\            }
    \\            const out = Buffer.concat(parts);
    \\            respond(0, { read: out.length, eof: false }, out);
    \\            return;
    \\          }
    \\          case "stream_write": {
    \\            const e = getSock(req.id); if (!e || (e.kind !== "tcp" && e.kind !== "tls")) return fail(2, "bad handle");
    \\            const buf = Buffer.from(payload || []);
    \\            const wp = new Promise((resolve, reject) => { e.sock.write(buf, (err) => err ? reject(err) : resolve()); });
    \\            if (e.writeTimeoutMs > 0) {
    \\              await Promise.race([wp, new Promise((_, rej) => setTimeout(() => rej(new Error("write timeout")), e.writeTimeoutMs))])
    \\                .catch((err) => { try { e.sock.destroy(); } catch (e2) {} throw Object.assign(err, { saStatus: req.tlsSpace ? -5 : 6 }); });
    \\            } else {
    \\              await wp.catch((err) => { throw Object.assign(err, { saStatus: req.tlsSpace ? -5 : 6 }); });
    \\            }
    \\            respond(0, { written: buf.length }, null);
    \\            return;
    \\          }
    \\          case "stream_set_read_timeout": {
    \\            const e = getSock(req.id); if (!e) return fail(2, "bad handle");
    \\            e.readTimeoutMs = req.timeoutMs || 0;
    \\            respond(0, {}, null);
    \\            return;
    \\          }
    \\          case "stream_set_write_timeout": {
    \\            const e = getSock(req.id); if (!e) return fail(2, "bad handle");
    \\            e.writeTimeoutMs = req.timeoutMs || 0;
    \\            respond(0, {}, null);
    \\            return;
    \\          }
    \\          case "reverse": {
    \\            const names = await dns.promises.reverse(req.host).catch(() => null);
    \\            if (!names || names.length === 0) return fail(7, "reverse lookup failed");
    \\            respond(0, { name: names[0] }, null);
    \\            return;
    \\          }
    \\          case "udp_set_broadcast": {
    \\            const e = getSock(req.id); if (!e || e.kind !== "udp") return fail(2, "bad handle");
    \\            try { e.sock.setBroadcast(req.enabled !== 0); } catch (err) { return fail(6, err.message); }
    \\            respond(0, {}, null);
    \\            return;
    \\          }
    \\          case "udp_set_ttl": {
    \\            const e = getSock(req.id); if (!e || e.kind !== "udp") return fail(2, "bad handle");
    \\            try { e.sock.setTTL(req.ttl); } catch (err) { return fail(6, err.message); }
    \\            respond(0, {}, null);
    \\            return;
    \\          }
    \\          case "udp_set_multicast_ttl": {
    \\            const e = getSock(req.id); if (!e || e.kind !== "udp") return fail(2, "bad handle");
    \\            try { e.sock.setMulticastTTL(req.ttl); } catch (err) { return fail(6, err.message); }
    \\            respond(0, {}, null);
    \\            return;
    \\          }
    \\          case "udp_set_multicast_loop": {
    \\            const e = getSock(req.id); if (!e || e.kind !== "udp") return fail(2, "bad handle");
    \\            try { e.sock.setMulticastLoop(req.enabled !== 0); } catch (err) { return fail(6, err.message); }
    \\            respond(0, {}, null);
    \\            return;
    \\          }
    \\          case "tcp_set_nodelay": {
    \\            const e = getSock(req.id); if (!e || e.kind !== "tcp") return fail(2, "bad handle");
    \\            try { e.sock.setNoDelay(req.enabled !== 0); } catch (err) { return fail(6, err.message); }
    \\            respond(0, {}, null);
    \\            return;
    \\          }
    \\          case "tcp_set_keepalive": {
    \\            const e = getSock(req.id); if (!e || e.kind !== "tcp") return fail(2, "bad handle");
    \\            try { e.sock.setKeepAlive(req.enabled !== 0); } catch (err) { return fail(6, err.message); }
    \\            respond(0, {}, null);
    \\            return;
    \\          }
    \\          case "tls_connect": {
    \\            let sock;
    \\            try { sock = await tlsUpgrade(null, req); }
    \\            catch (err) { return fail(tlsErrStatus(err), err.message); }
    \\            const e = streamEntry("tls", sock);
    \\            const id = nextId++;
    \\            socks.set(id, e);
    \\            respond(0, { id: id }, null);
    \\            return;
    \\          }
    \\          case "tls_start": {
    \\            const e0 = getSock(req.id); if (!e0 || e0.kind !== "tcp") return fail(-22, "bad plain handle");
    \\            e0.sock.removeAllListeners("data");
    \\            e0.chunks = []; e0.buffered = 0; e0.waiter = null;
    \\            let sock;
    \\            try { sock = await tlsUpgrade(e0.sock, req); }
    \\            catch (err) { return fail(tlsErrStatus(err), err.message); }
    \\            e0.kind = "tls";
    \\            e0.sock = sock;
    \\            sock.on("data", (chunk) => { e0.chunks.push(chunk); e0.buffered += chunk.length; if (e0.waiter) { const w = e0.waiter; e0.waiter = null; w(); } });
    \\            const done = () => { e0.eof = true; if (e0.waiter) { const w = e0.waiter; e0.waiter = null; w(); } };
    \\            sock.on("end", done); sock.on("close", done); sock.on("error", done);
    \\            respond(0, { id: req.id }, null);
    \\            return;
    \\          }
    \\          default:
    \\            return fail(8, "unknown op " + op);
    \\        }
    \\      } catch (err) {
    \\        const st = err && err.saStatus !== undefined ? err.saStatus : 6;
    \\        fail(st, err && err.message ? err.message : err);
    \\      }
    \\    }
    \\    parentPort.on("message", () => {
    \\      const jlen = hdr[1];
    \\      const jsonText = dec.decode(data.subarray(0, jlen));
    \\      let req;
    \\      try { req = JSON.parse(jsonText); } catch (e) { fail(1, "bad request json"); return; }
    \\      const plen = req.plen || 0;
    \\      const payload = plen > 0 ? Buffer.from(data.subarray(jlen, jlen + plen)) : null;
    \\      handle(req, payload);
    \\    });
    \\  }
    \\  let BR = null, BRbad = false;
    \\  function bridgeInit() {
    \\    if (BR) return true;
    \\    if (BRbad) return false;
    \\    try {
    \\      const wt = __sa_node_builtin("node:worker_threads");
    \\      if (!wt || !wt.Worker) throw new Error("no worker_threads");
    \\      if (typeof SharedArrayBuffer === "undefined" || typeof Atomics === "undefined" || typeof Atomics.wait !== "function") throw new Error("no SAB/Atomics");
    \\      const sab = new SharedArrayBuffer(4 * 1024 * 1024);
    \\      const worker = new wt.Worker("(" + __sa_jsnet_worker.toString() + ")()", { eval: true, workerData: { sab: sab } });
    \\      worker.unref();
    \\      BR = { sab: sab, hdr: new Int32Array(sab, 0, 4), data: new Uint8Array(sab, 256), enc: new TextEncoder(), dec: new TextDecoder(), worker: worker };
    \\      return true;
    \\    } catch (e) { BRbad = true; return false; }
    \\  }
    \\  // One synchronous bridge round-trip. tlsSpace selects the error-code space
    \\  // for the unavailable-bridge failure (-1 vs 8). A 10-minute watchdog bounds
    \\  // a dead worker; a legitimately blocked socket call returns through the
    \\  // worker long before that in every realistic probe.
    \\  function bridgeCall(op, params, payload, tlsSpace) {
    \\    if (!bridgeInit()) return { status: tlsSpace ? -1 : 8, json: { error: "bridge unavailable" }, bytes: null };
    \\    const req = Object.assign({ op: op, plen: payload ? payload.length : 0 }, params || {});
    \\    const jb = BR.enc.encode(JSON.stringify(req));
    \\    if (jb.length + (payload ? payload.length : 0) > BR.data.length) return { status: tlsSpace ? -1 : 8, json: { error: "bridge payload too large" }, bytes: null };
    \\    BR.data.set(jb, 0);
    \\    if (payload) BR.data.set(payload, jb.length);
    \\    BR.hdr[1] = jb.length;
    \\    Atomics.store(BR.hdr, 0, 1);
    \\    BR.worker.postMessage({});
    \\    const deadline = Date.now() + 600000;
    \\    for (;;) {
    \\      Atomics.wait(BR.hdr, 0, 1, 1000);
    \\      if (Atomics.load(BR.hdr, 0) === 2) break;
    \\      if (Date.now() > deadline) return { status: tlsSpace ? -5 : 6, json: { error: "bridge watchdog timeout" }, bytes: null };
    \\    }
    \\    const jlen = BR.hdr[2];
    \\    const plen = BR.hdr[3];
    \\    const json = JSON.parse(BR.dec.decode(BR.data.subarray(0, jlen)));
    \\    const bytes = plen > 0 ? Buffer.from(BR.data.subarray(jlen, jlen + plen)) : null;
    \\    Atomics.store(BR.hdr, 0, 0);
    \\    return { status: json.__status, json: json, bytes: bytes };
    \\  }
    \\  // ---------- net handle registry (SA-side) ----------
    \\  // byBridge: live bridge id -> SA handle. detached: bridge ids whose SA
    \\  // handle was consumed by fd_into_raw (start_tls upgrades them in place
    \\  // and mints a fresh SA handle, mirroring native fd ownership transfer).
    \\  const NET = { h: new Map(), next: 1, byBridge: new Map(), detached: new Map() };
    \\  function netReg(entry) { const h = NET.next++; NET.h.set(h, entry); if (entry.bridgeId !== undefined && entry.bridgeId !== null) NET.byBridge.set(entry.bridgeId, h); return h; }
    \\  function netGet(h) { return NET.h.get(h) || null; }
    \\  function netDel(h) { const e = NET.h.get(h); if (e) { NET.h.delete(h); if (e.bridgeId !== undefined && e.bridgeId !== null) NET.byBridge.delete(e.bridgeId); } return e || null; }
    \\  // ---------- TLS config registry ----------
    \\  const TLS = { configs: new Map(), next: 1, processCas: [] };
    \\  function tlsCfgNew() { const c = { serverName: null, caFiles: [], caPems: [], insecure: false, verifySelfSigned: false }; const h = TLS.next++; TLS.configs.set(h, c); return h; }
    \\  function tlsCfgGet(h) { return TLS.configs.get(h) || null; }
    \\  function tlsCfgFree(h) { return TLS.configs.delete(h); }
    \\  // Resolve the effective CA PEM list for a connect: process-wide CAs +
    \\  // config ca_files (read eagerly; a missing file fails the connect with -5)
    \\  // + config ca_pems. Returns { pems } or { err }.
    \\  function tlsResolveCas(cfg) {
    \\    const pems = TLS.processCas.slice();
    \\    if (cfg) {
    \\      for (const f of cfg.caFiles) {
    \\        try {
    \\          const fs = __sa_node_builtin("node:fs");
    \\          pems.push(fs.readFileSync(bToStr(f), "utf8"));
    \\        } catch (e) { return { err: -5 }; }
    \\      }
    \\      for (const p of cfg.caPems) pems.push(p);
    \\    }
    \\    return { pems: pems };
    \\  }
    \\  // Count usable certificates in a PEM string (-1 on any decode failure).
    \\  // Native skips some unparseable classes; this port fails loudly instead
    \\  // (documented approximation; probes use valid certificates).
    \\  function pemUsableCount(pemStr) {
    \\    try {
    \\      const crypto = __sa_node_builtin("node:crypto");
    \\      if (!crypto || !crypto.X509Certificate) return -1;
    \\      let count = 0;
    \\      const begin = "-----BEGIN CERTIFICATE-----";
    \\      const end = "-----END CERTIFICATE-----";
    \\      let pos = 0;
    \\      while (true) {
    \\        const b = pemStr.indexOf(begin, pos);
    \\        if (b < 0) break;
    \\        const e = pemStr.indexOf(end, b + begin.length);
    \\        if (e < 0) return -1;
    \\        const b64 = pemStr.slice(b + begin.length, e).replace(/\s/g, "");
    \\        let der;
    \\        try { der = Buffer.from(b64, "base64"); } catch (err) { return -1; }
    \\        try { new crypto.X509Certificate(der); count++; } catch (err) { return -1; }
    \\        pos = e + end.length;
    \\      }
    \\      return count;
    \\    } catch (err) { return -1; }
    \\  }
    \\  // Full TLS connect path shared by connect / connect_config / start_tls.
    \\  // cfg: null (default) or a config object. upgradeBridgeId: null (fresh
    \\  // dial) or a bridge socket id to upgrade in place. Returns
    \\  // { status, saHandle } ; on upgrade failure the plain entry is consumed
    \\  // (closed), mirroring the native fd-ownership rule.
    \\  function tlsConnectFull(hostStr, portNum, cfg, upgradeBridgeId) {
    \\    if (!hostStr || hostStr.length === 0) return { status: -22 };
    \\    // Fresh dials need a valid port; upgrades reuse the existing socket.
    \\    if ((upgradeBridgeId === null || upgradeBridgeId === undefined) &&
    \\        (portNum === 0 || portNum > 65535)) return { status: -22 };
    \\    let serverName = null, insecure = false, verifySelfSigned = false;
    \\    if (cfg) {
    \\      serverName = (cfg.serverName === null) ? null : bToStr(cfg.serverName);
    \\      insecure = cfg.insecure; verifySelfSigned = cfg.verifySelfSigned;
    \\      if (insecure && (verifySelfSigned || serverName !== null)) return { status: -22 };
    \\      if (verifySelfSigned && (cfg.caFiles.length > 0 || cfg.caPems.length > 0)) return { status: -22 };
    \\    }
    \\    const cas = tlsResolveCas(cfg);
    \\    if (cas.err) return { status: cas.err };
    \\    const params = { host: hostStr, port: portNum, timeoutMs: 0,
    \\      serverName: serverName, caPems: cas.pems,
    \\      insecure: insecure, verifySelfSigned: verifySelfSigned };
    \\    if (upgradeBridgeId === null || upgradeBridgeId === undefined) {
    \\      const r = bridgeCall("tls_connect", params, null, true);
    \\      if (r.status !== 0) return { status: r.status };
    \\      const h = netReg({ kind: "tls", bridgeId: r.json.id, readTimeoutMs: 0, writeTimeoutMs: 0, opts: new Map() });
    \\      return { status: 0, saHandle: h };
    \\    }
    \\    const saH = NET.byBridge.get(upgradeBridgeId);
    \\    const entry = (saH !== undefined) ? NET.h.get(saH) : null;
    \\    const detached = NET.detached.get(upgradeBridgeId) === true;
    \\    if (!detached && (!entry || entry.kind !== "tcp")) return { status: -22 };
    \\    if (detached && entry) return { status: -22 };
    \\    const r = bridgeCall("tls_start", Object.assign({ id: upgradeBridgeId }, params), null, true);
    \\    if (r.status !== 0) {
    \\      if (entry) { NET.h.delete(saH); NET.byBridge.delete(upgradeBridgeId); }
    \\      NET.detached.delete(upgradeBridgeId);
    \\      bridgeCall("sock_close", { id: upgradeBridgeId }, null, true);
    \\      return { status: r.status };
    \\    }
    \\    if (detached) {
    \\      NET.detached.delete(upgradeBridgeId);
    \\      const h = netReg({ kind: "tls", bridgeId: upgradeBridgeId, readTimeoutMs: 0, writeTimeoutMs: 0, opts: new Map() });
    \\      return { status: 0, saHandle: h };
    \\    }
    \\    entry.kind = "tls";
    \\    return { status: 0, saHandle: saH };
    \\  }
    \\  // ---------- netinfo ----------
    \\  function netinfoJson() {
    \\    const os = __sa_node_builtin("node:os");
    \\    const ifs = os.networkInterfaces();
    \\    const out = [];
    \\    for (const name of Object.keys(ifs)) {
    \\      for (const a of ifs[name]) {
    \\        if (!a.address) continue;
    \\        const fam = (a.family === "IPv4" || a.family === 4) ? 2 : 10;
    \\        let netmask = a.netmask || "";
    \\        let prefix = 0;
    \\        if (fam === 2 && netmask) {
    \\          const parts = netmask.split(".");
    \\          for (const p of parts) {
    \\            let v = parseInt(p, 10);
    \\            while (v) { prefix += (v & 1); v >>= 1; }
    \\          }
    \\        } else if (fam === 10 && a.cidr) {
    \\          const slash = a.cidr.indexOf("/");
    \\          if (slash >= 0) prefix = parseInt(a.cidr.slice(slash + 1), 10);
    \\        }
    \\        let broadcast = null;
    \\        if (fam === 2 && !a.internal && netmask) {
    \\          const ap = a.address.split(".").map((x) => parseInt(x, 10));
    \\          const mp = netmask.split(".").map((x) => parseInt(x, 10));
    \\          if (ap.length === 4 && mp.length === 4) {
    \\            broadcast = ap.map((v, i) => (v | (~mp[i] & 255))).join(".");
    \\          }
    \\        }
    \\        out.push({ name: name, family: fam, address: a.address, netmask: netmask,
    \\          prefix_len: prefix, broadcast: broadcast, scope_id: (a.scopeid !== undefined && a.scopeid !== null) ? a.scopeid : 0 });
    \\      }
    \\    }
    \\    return bFromStr(JSON.stringify(out));
    \\  }
    \\  // String out-pair helper (mirrors sa_cookie.zig outString): null value ->
    \\  // NOT_FOUND with ptr 0 / len 0; otherwise a fresh linear-memory copy.
    \\  // Uses the generated module's own memory helpers (defined in the header,
    \\  // which precedes this chunk in every emitted program).
    \\  function outStr(out_ptr, out_len, bytesOrNull) {
    \\    if (bytesOrNull === null) { __sa_store_ptr(out_ptr, 0); __sa_store_i64(out_len, 0n); return 3; }
    \\    const p = __sa_alloc(bytesOrNull.length);
    \\    __sa_u8.set(bytesOrNull, p);
    \\    __sa_store_ptr(out_ptr, p);
    \\    __sa_store_i64(out_len, BigInt(bytesOrNull.length));
    \\    return 0;
    \\  }
    \\  return {
    \\    outStr: outStr,
    \\    validCookieName: validCookieName, validCookieValue: validCookieValue,
    \\    validDomainAttr: validDomainAttr,
    \\    bFromStr: bFromStr, bToStr: bToStr, bEq: bEq, bEqFold: bEqFold, bLower: bLower,
    \\    bTrimOws: bTrimOws, bConcat: bConcat,
    \\    parseCookieDate: parseCookieDate, formatImfFixdate: formatImfFixdate,
    \\    parseSetCookie: parseSetCookie, serializeCookie: serializeCookie,
    \\    cloneCookie: cloneCookie, mkCookie: mkCookie,
    \\    domainMatch: domainMatch, pathMatch: pathMatch, defaultPath: defaultPath,
    \\    splitUrl: splitUrl, originTrustworthy: originTrustworthy,
    \\    ckErrSet: ckErrSet, ckErrClear: ckErrClear, ckErrGet: ckErrGet,
    \\    ckReg: ckReg, ckGet: ckGet, ckFree: ckFree,
    \\    jarReg: jarReg, jarGet: jarGet, jarFree: jarFree, mkJar: mkJar,
    \\    jarStore: jarStore, jarHeader: jarHeader, jarSaveText: jarSaveText,
    \\    jarLoad: jarLoad, jarEvict: jarEvict,
    \\    parseHeaderPair: parseHeaderPair, headerPairCount: headerPairCount, headerPairAt: headerPairAt,
    \\    bridgeCall: bridgeCall, netReg: netReg, netGet: netGet, netDel: netDel, NET: NET,
    \\    tlsCfgNew: tlsCfgNew, tlsCfgGet: tlsCfgGet, tlsCfgFree: tlsCfgFree,
    \\    tlsResolveCas: tlsResolveCas, pemUsableCount: pemUsableCount,
    \\    tlsConnectFull: tlsConnectFull, TLS: TLS, netinfoJson: netinfoJson
    \\  };
    \\})();
;

fn isKnownShim(name: []const u8) bool {
    if (std.mem.eql(u8, name, "sa_print_bytes")) return true;
    if (std.mem.eql(u8, name, "sa_std_compress_supported")) return true;
    if (std.mem.eql(u8, name, "sa_std_compress_encode")) return true;
    if (std.mem.eql(u8, name, "sa_std_compress_decode")) return true;
    if (std.mem.eql(u8, name, "sa_std_compress_buffer_data")) return true;
    if (std.mem.eql(u8, name, "sa_std_compress_buffer_len")) return true;
    if (std.mem.eql(u8, name, "sa_std_compress_buffer_free")) return true;
    if (std.mem.eql(u8, name, "sa_std_multipart_parse")) return true;
    if (std.mem.eql(u8, name, "sa_std_multipart_free")) return true;
    if (std.mem.eql(u8, name, "sa_std_multipart_count")) return true;
    if (std.mem.eql(u8, name, "sa_std_multipart_part_name")) return true;
    if (std.mem.eql(u8, name, "sa_std_multipart_part_filename")) return true;
    if (std.mem.eql(u8, name, "sa_std_multipart_part_content_type")) return true;
    if (std.mem.eql(u8, name, "sa_std_multipart_part_header")) return true;
    if (std.mem.eql(u8, name, "sa_std_multipart_part_body")) return true;
    if (std.mem.eql(u8, name, "sa_std_multipart_builder_new")) return true;
    if (std.mem.eql(u8, name, "sa_std_multipart_builder_free")) return true;
    if (std.mem.eql(u8, name, "sa_std_multipart_builder_add_field")) return true;
    if (std.mem.eql(u8, name, "sa_std_multipart_builder_add_file")) return true;
    if (std.mem.eql(u8, name, "sa_std_multipart_builder_boundary")) return true;
    if (std.mem.eql(u8, name, "sa_std_multipart_builder_content_type")) return true;
    if (std.mem.eql(u8, name, "sa_std_multipart_builder_finish")) return true;
    if (std.mem.eql(u8, name, "sa_std_multipart_buffer_data")) return true;
    if (std.mem.eql(u8, name, "sa_std_multipart_buffer_len")) return true;
    if (std.mem.eql(u8, name, "sa_std_multipart_buffer_free")) return true;
    if (std.mem.eql(u8, name, "sa_std_ssh_supported")) return true;
    if (std.mem.eql(u8, name, "sa_std_ssh_buffer_data")) return true;
    if (std.mem.eql(u8, name, "sa_std_ssh_buffer_len")) return true;
    if (std.mem.eql(u8, name, "sa_std_ssh_buffer_free")) return true;
    if (std.mem.eql(u8, name, "sa_std_ssh_client_connect")) return true;
    if (std.mem.eql(u8, name, "sa_std_ssh_hostkey_fingerprint")) return true;
    if (std.mem.eql(u8, name, "sa_std_ssh_auth_password")) return true;
    if (std.mem.eql(u8, name, "sa_std_ssh_auth_keyfile")) return true;
    if (std.mem.eql(u8, name, "sa_std_ssh_exec")) return true;
    if (std.mem.eql(u8, name, "sa_std_ssh_sftp_read")) return true;
    if (std.mem.eql(u8, name, "sa_std_ssh_sftp_write")) return true;
    if (std.mem.eql(u8, name, "sa_std_ssh_sftp_stat")) return true;
    if (std.mem.eql(u8, name, "sa_std_ssh_session_close")) return true;
    if (std.mem.eql(u8, name, "sa_std_ssh_server_listen")) return true;
    if (std.mem.eql(u8, name, "sa_std_ssh_server_accept")) return true;
    if (std.mem.eql(u8, name, "sa_std_ssh_server_auth_next")) return true;
    if (std.mem.eql(u8, name, "sa_std_ssh_server_auth_accept")) return true;
    if (std.mem.eql(u8, name, "sa_std_ssh_server_auth_deny")) return true;
    if (std.mem.eql(u8, name, "sa_std_ssh_server_channel_accept")) return true;
    if (std.mem.eql(u8, name, "sa_std_ssh_server_channel_exec")) return true;
    if (std.mem.eql(u8, name, "sa_std_ssh_channel_write")) return true;
    if (std.mem.eql(u8, name, "sa_std_ssh_channel_read")) return true;
    if (std.mem.eql(u8, name, "sa_std_ssh_channel_send_exit")) return true;
    if (std.mem.eql(u8, name, "sa_std_ssh_channel_close")) return true;
    if (std.mem.eql(u8, name, "sa_std_ssh_server_session_close")) return true;
    if (std.mem.eql(u8, name, "sa_std_ssh_server_bind_close")) return true;
    if (std.mem.eql(u8, name, "sa_http_client_req_new_joined")) return true;
    if (std.mem.eql(u8, name, "sa_http_client_req_add_openai_auth")) return true;
    if (std.mem.eql(u8, name, "sa_http_client_resp_get_header")) return true;
    if (std.mem.eql(u8, name, "sa_http_client_resp_body_slice")) return true;
    if (std.mem.eql(u8, name, "sa_http_client_resp_body_ptr")) return true;
    if (std.mem.eql(u8, name, "sa_http_client_resp_body_len")) return true;
    if (std.mem.eql(u8, name, "sa_http_client_req_send_async")) return true;
    if (std.mem.eql(u8, name, "sa_http_client_async_poll")) return true;
    if (std.mem.eql(u8, name, "sa_http_client_async_take_response")) return true;
    if (std.mem.eql(u8, name, "sa_http_client_async_free")) return true;
    if (std.mem.eql(u8, name, "sa_http_client_websocket_connect")) return true;
    if (std.mem.eql(u8, name, "sa_http_websocket_read")) return true;
    if (std.mem.eql(u8, name, "sa_http_websocket_write")) return true;
    if (std.mem.eql(u8, name, "sa_http_websocket_free")) return true;
    if (std.mem.eql(u8, name, "sa_http_client_sse_post")) return true;
    if (std.mem.eql(u8, name, "sa_http_client_sse_read")) return true;
    if (std.mem.eql(u8, name, "sa_http_client_sse_poll")) return true;
    if (std.mem.eql(u8, name, "sa_http_client_sse_status")) return true;
    if (std.mem.eql(u8, name, "sa_http_client_sse_free")) return true;
    if (std.mem.eql(u8, name, "sa_http_client_sse_turn")) return true;
    if (std.mem.eql(u8, name, "sa_http_client_sse_turn_free")) return true;
    if (std.mem.eql(u8, name, "sa_http_client_new_v2")) return true;
    if (std.mem.eql(u8, name, "sa_http_client_req_new_v2")) return true;
    if (std.mem.eql(u8, name, "sa_http_client_req_add_header_v2")) return true;
    if (std.mem.eql(u8, name, "sa_http_client_req_set_body_v2")) return true;
    if (std.mem.eql(u8, name, "sa_http_client_req_set_timeout_v2")) return true;
    if (std.mem.eql(u8, name, "sa_http_client_req_set_max_response_bytes_v2")) return true;
    if (std.mem.eql(u8, name, "sa_http_client_req_send_v2")) return true;
    if (std.mem.eql(u8, name, "sa_http_client_req_send_async_v2")) return true;
    if (std.mem.eql(u8, name, "sa_http_client_async_poll_v2")) return true;
    if (std.mem.eql(u8, name, "sa_http_client_async_take_response_v2")) return true;
    if (std.mem.eql(u8, name, "sa_http_client_async_cancel_v2")) return true;
    if (std.mem.eql(u8, name, "sa_http_client_async_free_v2")) return true;
    if (std.mem.eql(u8, name, "sa_http_client_websocket_connect_v2")) return true;
    if (std.mem.eql(u8, name, "sa_http_client_websocket_connect_unix_v2")) return true;
    if (std.mem.eql(u8, name, "sa_http_client_req_websocket_connect_v2")) return true;
    if (std.mem.eql(u8, name, "sa_http_client_req_websocket_connect_unix_v2")) return true;
    if (std.mem.eql(u8, name, "sa_http_websocket_poll_v2")) return true;
    if (std.mem.eql(u8, name, "sa_http_websocket_read_v2")) return true;
    if (std.mem.eql(u8, name, "sa_http_websocket_write_v2")) return true;
    if (std.mem.eql(u8, name, "sa_http_websocket_close_v2")) return true;
    if (std.mem.eql(u8, name, "sa_http_websocket_free_v2")) return true;
    if (std.mem.eql(u8, name, "sa_mfill")) return true;
    if (std.mem.eql(u8, name, "sa_mcopy")) return true;
    if (std.mem.eql(u8, name, "sa_msum_u8")) return true;
    if (std.mem.eql(u8, name, "sa_msum_u32")) return true;
    if (std.mem.eql(u8, name, "sa_mwrite_u8")) return true;
    if (std.mem.eql(u8, name, "sa_mfind_u32")) return true;
    if (std.mem.eql(u8, name, "sa_mfind_u8")) return true;
    if (std.mem.eql(u8, name, "sa_b64dec")) return true;
    if (std.mem.eql(u8, name, "sa_hexdec")) return true;
    if (std.mem.eql(u8, name, "sa_esc_html")) return true;
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
    if (std.mem.eql(u8, name, "sa_regex_match_all")) return true;
    if (std.mem.eql(u8, name, "sa_unicode_normalize")) return true;
    if (std.mem.eql(u8, name, "sa_host_is_bun")) return true;
    if (std.mem.eql(u8, name, "sa_regex_match_list_count")) return true;
    if (std.mem.eql(u8, name, "sa_regex_match_list_at")) return true;
    if (std.mem.eql(u8, name, "sa_regex_match_list_free")) return true;
    if (std.mem.eql(u8, name, "sa_regex_replace")) return true;
    if (std.mem.eql(u8, name, "sa_regex_replace_all")) return true;
    if (std.mem.eql(u8, name, "sa_regex_buffer_data")) return true;
    if (std.mem.eql(u8, name, "sa_regex_buffer_len")) return true;
    if (std.mem.eql(u8, name, "sa_regex_buffer_free")) return true;
    if (std.mem.eql(u8, name, "sa_regex_split")) return true;
    if (std.mem.eql(u8, name, "sa_regex_split_count")) return true;
    if (std.mem.eql(u8, name, "sa_regex_split_ptr")) return true;
    if (std.mem.eql(u8, name, "sa_regex_split_len")) return true;
    if (std.mem.eql(u8, name, "sa_regex_split_free")) return true;
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
    if (std.mem.eql(u8, name, "sa_json_object_set_string")) return true;
    if (std.mem.eql(u8, name, "sa_json_object_set_i64")) return true;
    if (std.mem.eql(u8, name, "sa_json_object_set_f64")) return true;
    if (std.mem.eql(u8, name, "sa_json_object_set_bool")) return true;
    if (std.mem.eql(u8, name, "sa_json_object_set_null")) return true;
    if (std.mem.eql(u8, name, "sa_json_object_set_node")) return true;
    if (std.mem.eql(u8, name, "sa_json_object_remove")) return true;
    if (std.mem.eql(u8, name, "sa_json_array_push_string")) return true;
    if (std.mem.eql(u8, name, "sa_json_array_push_i64")) return true;
    if (std.mem.eql(u8, name, "sa_json_array_push_f64")) return true;
    if (std.mem.eql(u8, name, "sa_json_array_push_bool")) return true;
    if (std.mem.eql(u8, name, "sa_json_array_push_null")) return true;
    if (std.mem.eql(u8, name, "sa_json_array_push_node")) return true;
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
    // BP net shims (cookie / tls-config / net-slice / netinfo).
    if (std.mem.eql(u8, name, "sa_cookie_parse_set_cookie")) return true;
    if (std.mem.eql(u8, name, "sa_cookie_last_error")) return true;
    if (std.mem.eql(u8, name, "sa_cookie_free")) return true;
    if (std.mem.eql(u8, name, "sa_cookie_new")) return true;
    if (std.mem.eql(u8, name, "sa_cookie_name")) return true;
    if (std.mem.eql(u8, name, "sa_cookie_value")) return true;
    if (std.mem.eql(u8, name, "sa_cookie_domain")) return true;
    if (std.mem.eql(u8, name, "sa_cookie_path")) return true;
    if (std.mem.eql(u8, name, "sa_cookie_expires")) return true;
    if (std.mem.eql(u8, name, "sa_cookie_max_age")) return true;
    if (std.mem.eql(u8, name, "sa_cookie_flags")) return true;
    if (std.mem.eql(u8, name, "sa_cookie_same_site")) return true;
    if (std.mem.eql(u8, name, "sa_cookie_is_host_only")) return true;
    if (std.mem.eql(u8, name, "sa_cookie_set_domain")) return true;
    if (std.mem.eql(u8, name, "sa_cookie_set_path")) return true;
    if (std.mem.eql(u8, name, "sa_cookie_set_expires")) return true;
    if (std.mem.eql(u8, name, "sa_cookie_set_max_age")) return true;
    if (std.mem.eql(u8, name, "sa_cookie_clear_expiry")) return true;
    if (std.mem.eql(u8, name, "sa_cookie_set_secure")) return true;
    if (std.mem.eql(u8, name, "sa_cookie_set_http_only")) return true;
    if (std.mem.eql(u8, name, "sa_cookie_set_partitioned")) return true;
    if (std.mem.eql(u8, name, "sa_cookie_set_same_site")) return true;
    if (std.mem.eql(u8, name, "sa_cookie_serialize")) return true;
    if (std.mem.eql(u8, name, "sa_cookie_serialize_pair")) return true;
    if (std.mem.eql(u8, name, "sa_cookie_is_expired")) return true;
    if (std.mem.eql(u8, name, "sa_cookie_domain_match")) return true;
    if (std.mem.eql(u8, name, "sa_cookie_path_match")) return true;
    if (std.mem.eql(u8, name, "sa_cookie_header_pair_count")) return true;
    if (std.mem.eql(u8, name, "sa_cookie_header_pair_at")) return true;
    if (std.mem.eql(u8, name, "sa_cookie_jar_new")) return true;
    if (std.mem.eql(u8, name, "sa_cookie_jar_free")) return true;
    if (std.mem.eql(u8, name, "sa_cookie_jar_set_policy")) return true;
    if (std.mem.eql(u8, name, "sa_cookie_jar_policy")) return true;
    if (std.mem.eql(u8, name, "sa_cookie_jar_store")) return true;
    if (std.mem.eql(u8, name, "sa_cookie_jar_header")) return true;
    if (std.mem.eql(u8, name, "sa_cookie_jar_count")) return true;
    if (std.mem.eql(u8, name, "sa_cookie_jar_at")) return true;
    if (std.mem.eql(u8, name, "sa_cookie_jar_clear")) return true;
    if (std.mem.eql(u8, name, "sa_cookie_jar_evict_expired")) return true;
    if (std.mem.eql(u8, name, "sa_cookie_jar_save")) return true;
    if (std.mem.eql(u8, name, "sa_cookie_jar_load")) return true;
    if (std.mem.eql(u8, name, "sa_cookie_jar_request_header")) return true;
    if (std.mem.eql(u8, name, "sa_cookie_jar_store_response")) return true;
    if (std.mem.eql(u8, name, "sa_std_tls_client_supported")) return true;
    if (std.mem.eql(u8, name, "sa_std_tls_client_add_ca_file")) return true;
    if (std.mem.eql(u8, name, "sa_std_tls_client_connect")) return true;
    if (std.mem.eql(u8, name, "sa_std_tls_client_read")) return true;
    if (std.mem.eql(u8, name, "sa_std_tls_client_write")) return true;
    if (std.mem.eql(u8, name, "sa_std_tls_client_close")) return true;
    if (std.mem.eql(u8, name, "sa_std_tls_client_status_json")) return true;
    if (std.mem.eql(u8, name, "sa_std_tls_client_buffer_data")) return true;
    if (std.mem.eql(u8, name, "sa_std_tls_client_buffer_len")) return true;
    if (std.mem.eql(u8, name, "sa_std_tls_client_buffer_free")) return true;
    if (std.mem.eql(u8, name, "sa_std_tls_client_peer_cert_json")) return true;
    if (std.mem.eql(u8, name, "sa_std_tls_client_config_new")) return true;
    if (std.mem.eql(u8, name, "sa_std_tls_client_config_free")) return true;
    if (std.mem.eql(u8, name, "sa_std_tls_client_config_set_server_name")) return true;
    if (std.mem.eql(u8, name, "sa_std_tls_client_config_add_ca_file")) return true;
    if (std.mem.eql(u8, name, "sa_std_tls_client_config_add_ca_memory")) return true;
    if (std.mem.eql(u8, name, "sa_std_tls_client_config_set_insecure_no_verification")) return true;
    if (std.mem.eql(u8, name, "sa_std_tls_client_config_set_verify_self_signed")) return true;
    if (std.mem.eql(u8, name, "sa_std_tls_client_connect_config")) return true;
    if (std.mem.eql(u8, name, "sa_std_tls_client_start_tls")) return true;
    if (std.mem.eql(u8, name, "sa_std_tls_shaped_supported")) return true;
    if (std.mem.eql(u8, name, "sa_std_tls_shaped_connect")) return true;
    if (std.mem.eql(u8, name, "sa_std_tls_shaped_read")) return true;
    if (std.mem.eql(u8, name, "sa_std_tls_shaped_write")) return true;
    if (std.mem.eql(u8, name, "sa_std_tls_shaped_close")) return true;
    if (std.mem.eql(u8, name, "sa_std_tls_shaped_negotiated_json")) return true;
    if (std.mem.eql(u8, name, "sa_std_tls_shaped_hello_ja3")) return true;
    if (std.mem.eql(u8, name, "sa_std_tls_shaped_hello_ja3_string")) return true;
    if (std.mem.eql(u8, name, "sa_std_tls_shaped_hello_ja4")) return true;
    if (std.mem.eql(u8, name, "sa_std_tls_shaped_start_tls")) return true;
    if (std.mem.eql(u8, name, "sa_std_tls_shaped_session_blob")) return true;
    if (std.mem.eql(u8, name, "sa_std_tls_shaped_peer_cert_chain_json")) return true;
    if (std.mem.eql(u8, name, "sa_std_tls_shaped_buffer_data")) return true;
    if (std.mem.eql(u8, name, "sa_std_tls_shaped_buffer_len")) return true;
    if (std.mem.eql(u8, name, "sa_std_tls_shaped_buffer_free")) return true;
    if (std.mem.eql(u8, name, "sa_std_net_to_socket_addr_first")) return true;
    if (std.mem.eql(u8, name, "sa_std_net_to_socket_addr_list")) return true;
    if (std.mem.eql(u8, name, "sa_std_net_addr_list_next")) return true;
    if (std.mem.eql(u8, name, "sa_std_net_addr_list_remaining")) return true;
    if (std.mem.eql(u8, name, "sa_std_net_addr_list_reset")) return true;
    if (std.mem.eql(u8, name, "sa_std_net_addr_list_free")) return true;
    if (std.mem.eql(u8, name, "sa_std_net_addr_reverse_lookup")) return true;
    if (std.mem.eql(u8, name, "sa_net_addr_host")) return true;
    if (std.mem.eql(u8, name, "sa_net_addr_host_len")) return true;
    if (std.mem.eql(u8, name, "sa_net_addr_port")) return true;
    if (std.mem.eql(u8, name, "sa_net_addr_family")) return true;
    if (std.mem.eql(u8, name, "sa_net_addr_scope_id")) return true;
    if (std.mem.eql(u8, name, "sa_net_addr_free")) return true;
    if (std.mem.eql(u8, name, "sa_std_net_addr_format")) return true;
    if (std.mem.eql(u8, name, "sa_std_net_udp_bind")) return true;
    if (std.mem.eql(u8, name, "sa_std_net_udp_local_addr")) return true;
    if (std.mem.eql(u8, name, "sa_std_net_udp_connect")) return true;
    if (std.mem.eql(u8, name, "sa_std_net_udp_connect_addr")) return true;
    if (std.mem.eql(u8, name, "sa_std_net_udp_set_read_timeout")) return true;
    if (std.mem.eql(u8, name, "sa_std_net_udp_set_write_timeout")) return true;
    if (std.mem.eql(u8, name, "sa_std_net_udp_set_broadcast")) return true;
    if (std.mem.eql(u8, name, "sa_std_net_udp_broadcast")) return true;
    if (std.mem.eql(u8, name, "sa_std_net_udp_set_ttl")) return true;
    if (std.mem.eql(u8, name, "sa_std_net_udp_ttl")) return true;
    if (std.mem.eql(u8, name, "sa_std_net_udp_set_multicast_loop_v4")) return true;
    if (std.mem.eql(u8, name, "sa_std_net_udp_set_multicast_ttl_v4")) return true;
    if (std.mem.eql(u8, name, "sa_std_net_udp_set_multicast_loop_v6")) return true;
    if (std.mem.eql(u8, name, "sa_std_net_udp_set_multicast_hops_v6")) return true;
    if (std.mem.eql(u8, name, "sa_std_net_udp_set_only_v6")) return true;
    if (std.mem.eql(u8, name, "sa_std_net_udp_set_nonblocking")) return true;
    if (std.mem.eql(u8, name, "sa_std_net_udp_send")) return true;
    if (std.mem.eql(u8, name, "sa_std_net_udp_send_to")) return true;
    if (std.mem.eql(u8, name, "sa_std_net_udp_recv")) return true;
    if (std.mem.eql(u8, name, "sa_std_net_udp_recv_from")) return true;
    if (std.mem.eql(u8, name, "sa_std_net_tcp_connect")) return true;
    if (std.mem.eql(u8, name, "sa_std_net_tcp_connect_timeout")) return true;
    if (std.mem.eql(u8, name, "sa_std_net_tcp_connect_timeout_addr")) return true;
    if (std.mem.eql(u8, name, "sa_std_net_tcp_connect_timeout_all")) return true;
    if (std.mem.eql(u8, name, "sa_std_net_tcp_stream_read")) return true;
    if (std.mem.eql(u8, name, "sa_std_net_tcp_stream_write")) return true;
    if (std.mem.eql(u8, name, "sa_std_net_tcp_stream_set_read_timeout")) return true;
    if (std.mem.eql(u8, name, "sa_std_net_tcp_stream_set_write_timeout")) return true;
    if (std.mem.eql(u8, name, "sa_std_net_tcp_stream_read_timeout")) return true;
    if (std.mem.eql(u8, name, "sa_std_net_tcp_stream_write_timeout")) return true;
    if (std.mem.eql(u8, name, "sa_std_net_tcp_stream_set_nodelay")) return true;
    if (std.mem.eql(u8, name, "sa_std_net_tcp_stream_set_keepalive")) return true;
    if (std.mem.eql(u8, name, "sa_std_net_socket_setsockopt")) return true;
    if (std.mem.eql(u8, name, "sa_std_net_socket_getsockopt")) return true;
    if (std.mem.eql(u8, name, "sa_std_net_socket_setsockopt_int")) return true;
    if (std.mem.eql(u8, name, "sa_std_net_socket_getsockopt_int")) return true;
    if (std.mem.eql(u8, name, "sa_std_net_udp_recv_msg")) return true;
    if (std.mem.eql(u8, name, "sa_std_net_udp_recv_multi")) return true;
    if (std.mem.eql(u8, name, "sa_std_net_unix_datagram_peer_cred")) return true;
    if (std.mem.eql(u8, name, "sa_std_net_unix_stream_peer_cred")) return true;
    if (std.mem.eql(u8, name, "sa_std_close")) return true;
    if (std.mem.eql(u8, name, "sa_std_fd_into_raw")) return true;
    if (std.mem.eql(u8, name, "sa_fs_read_buffer_data")) return true;
    if (std.mem.eql(u8, name, "sa_fs_read_buffer_len")) return true;
    if (std.mem.eql(u8, name, "sa_fs_read_buffer_free")) return true;
    if (std.mem.eql(u8, name, "sa_std_net_interface_addresses_json")) return true;
    return false;
}

/// Whether `name` is a BP net shim (gates the jsnet runtime chunk).
fn isJsNetShim(name: []const u8) bool {
    if (std.mem.eql(u8, name, "sa_cookie_parse_set_cookie")) return true;
    if (std.mem.eql(u8, name, "sa_cookie_last_error")) return true;
    if (std.mem.eql(u8, name, "sa_cookie_free")) return true;
    if (std.mem.eql(u8, name, "sa_cookie_new")) return true;
    if (std.mem.eql(u8, name, "sa_cookie_name")) return true;
    if (std.mem.eql(u8, name, "sa_cookie_value")) return true;
    if (std.mem.eql(u8, name, "sa_cookie_domain")) return true;
    if (std.mem.eql(u8, name, "sa_cookie_path")) return true;
    if (std.mem.eql(u8, name, "sa_cookie_expires")) return true;
    if (std.mem.eql(u8, name, "sa_cookie_max_age")) return true;
    if (std.mem.eql(u8, name, "sa_cookie_flags")) return true;
    if (std.mem.eql(u8, name, "sa_cookie_same_site")) return true;
    if (std.mem.eql(u8, name, "sa_cookie_is_host_only")) return true;
    if (std.mem.eql(u8, name, "sa_cookie_set_domain")) return true;
    if (std.mem.eql(u8, name, "sa_cookie_set_path")) return true;
    if (std.mem.eql(u8, name, "sa_cookie_set_expires")) return true;
    if (std.mem.eql(u8, name, "sa_cookie_set_max_age")) return true;
    if (std.mem.eql(u8, name, "sa_cookie_clear_expiry")) return true;
    if (std.mem.eql(u8, name, "sa_cookie_set_secure")) return true;
    if (std.mem.eql(u8, name, "sa_cookie_set_http_only")) return true;
    if (std.mem.eql(u8, name, "sa_cookie_set_partitioned")) return true;
    if (std.mem.eql(u8, name, "sa_cookie_set_same_site")) return true;
    if (std.mem.eql(u8, name, "sa_cookie_serialize")) return true;
    if (std.mem.eql(u8, name, "sa_cookie_serialize_pair")) return true;
    if (std.mem.eql(u8, name, "sa_cookie_is_expired")) return true;
    if (std.mem.eql(u8, name, "sa_cookie_domain_match")) return true;
    if (std.mem.eql(u8, name, "sa_cookie_path_match")) return true;
    if (std.mem.eql(u8, name, "sa_cookie_header_pair_count")) return true;
    if (std.mem.eql(u8, name, "sa_cookie_header_pair_at")) return true;
    if (std.mem.eql(u8, name, "sa_cookie_jar_new")) return true;
    if (std.mem.eql(u8, name, "sa_cookie_jar_free")) return true;
    if (std.mem.eql(u8, name, "sa_cookie_jar_set_policy")) return true;
    if (std.mem.eql(u8, name, "sa_cookie_jar_policy")) return true;
    if (std.mem.eql(u8, name, "sa_cookie_jar_store")) return true;
    if (std.mem.eql(u8, name, "sa_cookie_jar_header")) return true;
    if (std.mem.eql(u8, name, "sa_cookie_jar_count")) return true;
    if (std.mem.eql(u8, name, "sa_cookie_jar_at")) return true;
    if (std.mem.eql(u8, name, "sa_cookie_jar_clear")) return true;
    if (std.mem.eql(u8, name, "sa_cookie_jar_evict_expired")) return true;
    if (std.mem.eql(u8, name, "sa_cookie_jar_save")) return true;
    if (std.mem.eql(u8, name, "sa_cookie_jar_load")) return true;
    if (std.mem.eql(u8, name, "sa_cookie_jar_request_header")) return true;
    if (std.mem.eql(u8, name, "sa_cookie_jar_store_response")) return true;
    if (std.mem.eql(u8, name, "sa_std_tls_client_supported")) return true;
    if (std.mem.eql(u8, name, "sa_std_tls_client_add_ca_file")) return true;
    if (std.mem.eql(u8, name, "sa_std_tls_client_connect")) return true;
    if (std.mem.eql(u8, name, "sa_std_tls_client_read")) return true;
    if (std.mem.eql(u8, name, "sa_std_tls_client_write")) return true;
    if (std.mem.eql(u8, name, "sa_std_tls_client_close")) return true;
    if (std.mem.eql(u8, name, "sa_std_tls_client_status_json")) return true;
    if (std.mem.eql(u8, name, "sa_std_tls_client_buffer_data")) return true;
    if (std.mem.eql(u8, name, "sa_std_tls_client_buffer_len")) return true;
    if (std.mem.eql(u8, name, "sa_std_tls_client_buffer_free")) return true;
    if (std.mem.eql(u8, name, "sa_std_tls_client_peer_cert_json")) return true;
    if (std.mem.eql(u8, name, "sa_std_tls_client_config_new")) return true;
    if (std.mem.eql(u8, name, "sa_std_tls_client_config_free")) return true;
    if (std.mem.eql(u8, name, "sa_std_tls_client_config_set_server_name")) return true;
    if (std.mem.eql(u8, name, "sa_std_tls_client_config_add_ca_file")) return true;
    if (std.mem.eql(u8, name, "sa_std_tls_client_config_add_ca_memory")) return true;
    if (std.mem.eql(u8, name, "sa_std_tls_client_config_set_insecure_no_verification")) return true;
    if (std.mem.eql(u8, name, "sa_std_tls_client_config_set_verify_self_signed")) return true;
    if (std.mem.eql(u8, name, "sa_std_tls_client_connect_config")) return true;
    if (std.mem.eql(u8, name, "sa_std_tls_client_start_tls")) return true;
    if (std.mem.eql(u8, name, "sa_std_tls_shaped_supported")) return true;
    if (std.mem.eql(u8, name, "sa_std_tls_shaped_connect")) return true;
    if (std.mem.eql(u8, name, "sa_std_tls_shaped_read")) return true;
    if (std.mem.eql(u8, name, "sa_std_tls_shaped_write")) return true;
    if (std.mem.eql(u8, name, "sa_std_tls_shaped_close")) return true;
    if (std.mem.eql(u8, name, "sa_std_tls_shaped_negotiated_json")) return true;
    if (std.mem.eql(u8, name, "sa_std_tls_shaped_hello_ja3")) return true;
    if (std.mem.eql(u8, name, "sa_std_tls_shaped_hello_ja3_string")) return true;
    if (std.mem.eql(u8, name, "sa_std_tls_shaped_hello_ja4")) return true;
    if (std.mem.eql(u8, name, "sa_std_tls_shaped_start_tls")) return true;
    if (std.mem.eql(u8, name, "sa_std_tls_shaped_session_blob")) return true;
    if (std.mem.eql(u8, name, "sa_std_tls_shaped_peer_cert_chain_json")) return true;
    if (std.mem.eql(u8, name, "sa_std_tls_shaped_buffer_data")) return true;
    if (std.mem.eql(u8, name, "sa_std_tls_shaped_buffer_len")) return true;
    if (std.mem.eql(u8, name, "sa_std_tls_shaped_buffer_free")) return true;
    if (std.mem.eql(u8, name, "sa_std_net_to_socket_addr_first")) return true;
    if (std.mem.eql(u8, name, "sa_std_net_to_socket_addr_list")) return true;
    if (std.mem.eql(u8, name, "sa_std_net_addr_list_next")) return true;
    if (std.mem.eql(u8, name, "sa_std_net_addr_list_remaining")) return true;
    if (std.mem.eql(u8, name, "sa_std_net_addr_list_reset")) return true;
    if (std.mem.eql(u8, name, "sa_std_net_addr_list_free")) return true;
    if (std.mem.eql(u8, name, "sa_std_net_addr_reverse_lookup")) return true;
    if (std.mem.eql(u8, name, "sa_net_addr_host")) return true;
    if (std.mem.eql(u8, name, "sa_net_addr_host_len")) return true;
    if (std.mem.eql(u8, name, "sa_net_addr_port")) return true;
    if (std.mem.eql(u8, name, "sa_net_addr_family")) return true;
    if (std.mem.eql(u8, name, "sa_net_addr_scope_id")) return true;
    if (std.mem.eql(u8, name, "sa_net_addr_free")) return true;
    if (std.mem.eql(u8, name, "sa_std_net_addr_format")) return true;
    if (std.mem.eql(u8, name, "sa_std_net_udp_bind")) return true;
    if (std.mem.eql(u8, name, "sa_std_net_udp_local_addr")) return true;
    if (std.mem.eql(u8, name, "sa_std_net_udp_connect")) return true;
    if (std.mem.eql(u8, name, "sa_std_net_udp_connect_addr")) return true;
    if (std.mem.eql(u8, name, "sa_std_net_udp_set_read_timeout")) return true;
    if (std.mem.eql(u8, name, "sa_std_net_udp_set_write_timeout")) return true;
    if (std.mem.eql(u8, name, "sa_std_net_udp_set_broadcast")) return true;
    if (std.mem.eql(u8, name, "sa_std_net_udp_broadcast")) return true;
    if (std.mem.eql(u8, name, "sa_std_net_udp_set_ttl")) return true;
    if (std.mem.eql(u8, name, "sa_std_net_udp_ttl")) return true;
    if (std.mem.eql(u8, name, "sa_std_net_udp_set_multicast_loop_v4")) return true;
    if (std.mem.eql(u8, name, "sa_std_net_udp_set_multicast_ttl_v4")) return true;
    if (std.mem.eql(u8, name, "sa_std_net_udp_set_multicast_loop_v6")) return true;
    if (std.mem.eql(u8, name, "sa_std_net_udp_set_multicast_hops_v6")) return true;
    if (std.mem.eql(u8, name, "sa_std_net_udp_set_only_v6")) return true;
    if (std.mem.eql(u8, name, "sa_std_net_udp_set_nonblocking")) return true;
    if (std.mem.eql(u8, name, "sa_std_net_udp_send")) return true;
    if (std.mem.eql(u8, name, "sa_std_net_udp_send_to")) return true;
    if (std.mem.eql(u8, name, "sa_std_net_udp_recv")) return true;
    if (std.mem.eql(u8, name, "sa_std_net_udp_recv_from")) return true;
    if (std.mem.eql(u8, name, "sa_std_net_tcp_connect")) return true;
    if (std.mem.eql(u8, name, "sa_std_net_tcp_connect_timeout")) return true;
    if (std.mem.eql(u8, name, "sa_std_net_tcp_connect_timeout_addr")) return true;
    if (std.mem.eql(u8, name, "sa_std_net_tcp_connect_timeout_all")) return true;
    if (std.mem.eql(u8, name, "sa_std_net_tcp_stream_read")) return true;
    if (std.mem.eql(u8, name, "sa_std_net_tcp_stream_write")) return true;
    if (std.mem.eql(u8, name, "sa_std_net_tcp_stream_set_read_timeout")) return true;
    if (std.mem.eql(u8, name, "sa_std_net_tcp_stream_set_write_timeout")) return true;
    if (std.mem.eql(u8, name, "sa_std_net_tcp_stream_read_timeout")) return true;
    if (std.mem.eql(u8, name, "sa_std_net_tcp_stream_write_timeout")) return true;
    if (std.mem.eql(u8, name, "sa_std_net_tcp_stream_set_nodelay")) return true;
    if (std.mem.eql(u8, name, "sa_std_net_tcp_stream_set_keepalive")) return true;
    if (std.mem.eql(u8, name, "sa_std_net_socket_setsockopt")) return true;
    if (std.mem.eql(u8, name, "sa_std_net_socket_getsockopt")) return true;
    if (std.mem.eql(u8, name, "sa_std_net_socket_setsockopt_int")) return true;
    if (std.mem.eql(u8, name, "sa_std_net_socket_getsockopt_int")) return true;
    if (std.mem.eql(u8, name, "sa_std_net_udp_recv_msg")) return true;
    if (std.mem.eql(u8, name, "sa_std_net_udp_recv_multi")) return true;
    if (std.mem.eql(u8, name, "sa_std_net_unix_datagram_peer_cred")) return true;
    if (std.mem.eql(u8, name, "sa_std_net_unix_stream_peer_cred")) return true;
    if (std.mem.eql(u8, name, "sa_std_close")) return true;
    if (std.mem.eql(u8, name, "sa_std_fd_into_raw")) return true;
    if (std.mem.eql(u8, name, "sa_fs_read_buffer_data")) return true;
    if (std.mem.eql(u8, name, "sa_fs_read_buffer_len")) return true;
    if (std.mem.eql(u8, name, "sa_fs_read_buffer_free")) return true;
    if (std.mem.eql(u8, name, "sa_std_net_interface_addresses_json")) return true;
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
    blocks: std.array_list.Managed(BlockRange),
    lid_to_blk: std.AutoHashMap(u32, usize),
    succs: std.array_list.Managed(std.array_list.Managed(usize)),
    in_sets: std.array_list.Managed(BaseSet),
    out_sets: std.array_list.Managed(BaseSet),

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
        .blocks = std.array_list.Managed(BlockRange).init(allocator),
        .lid_to_blk = std.AutoHashMap(u32, usize).init(allocator),
        .succs = std.array_list.Managed(std.array_list.Managed(usize)).init(allocator),
        .in_sets = std.array_list.Managed(BaseSet).init(allocator),
        .out_sets = std.array_list.Managed(BaseSet).init(allocator),
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
        var s = std.array_list.Managed(usize).init(allocator);
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
                    var rm = std.array_list.Managed(u32).init(allocator);
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
    // Slot promotion: unescaped stack slots become function-scope locals.
    var promo = try collectPromotableSlots(allocator, verified, fsig, task, use_global);
    defer promo.deinit();
    if (promo.count() != 0) {
        var pkeys = std.array_list.Managed(u32).init(allocator);
        defer pkeys.deinit();
        var pkit = promo.keyIterator();
        while (pkit.next()) |k| try pkeys.append(k.*);
        std.mem.sort(u32, pkeys.items, {}, std.sort.asc(u32));
        for (pkeys.items) |s| {
            const is64 = if (promo.get(s)) |info| info.narrow_bits == 64 else false;
            if (is64) try writer.print("  let __sa_sp{d} = 0n;\n", .{s}) else try writer.print("  let __sa_sp{d} = 0;\n", .{s});
        }
    }
    // If no labels at all, emit straight-line body without pc machine.
    if (pcs == 1) {
        i = task.start_idx + 1;
        while (i < task.end_idx) : (i += 1) {
            try emitLinearInstruction(writer, allocator, verified.symbols, fsig, use_global, const_addrs, fn_idx, verified.annotated[i].base, js_opt, &bases, retbase, &widths, &promo);
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
        try emitPcInstruction(writer, allocator, verified.symbols, fsig, use_global, const_addrs, fn_idx, base, &label_pc, js_opt, &bases, retbase, &widths, &promo);
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
        // Fused bulk-memory shims: one host call executes a tight raw loop
        // (or engine intrinsic) instead of N per-element helper dispatches.
        // These are what let sa2js meet or beat per-call accessor benches
        // (e.g. bun's buf.readUInt8-per-element): same engine, fewer calls.
        if (std.mem.eql(u8, fsig.name, "sa_mfill")) {
            try writer.writeAll(
        \\function sa_mfill(ptr, len, byte) {
        \\  const a = __sa_addr(ptr), n = __sa_num(len), b = __sa_num(byte) & 255;
        \\  if (__sa_buf) __sa_buf.fill(b, a, a + n);
        \\  else __sa_u8.subarray(a, a + n).fill(b);
        \\  return 0;
        \\}
        \\
            );
            return;
        }
        if (std.mem.eql(u8, fsig.name, "sa_mcopy")) {
            try writer.writeAll(
                \\function sa_mcopy(dst, src, len) {
                \\  const d = __sa_addr(dst), s = __sa_addr(src), n = __sa_num(len);
                \\  if (__sa_buf) __sa_buf.copy(__sa_buf, d, s, s + n);
                \\  else __sa_u8.copyWithin(d, s, s + n);
                \\  return 0;
                \\}
                \\
            );
            return;
        }
        if (std.mem.eql(u8, fsig.name, "sa_msum_u8")) {
            try writer.writeAll(
                \\function sa_msum_u8(ptr, len) {
                \\  const a = __sa_addr(ptr), n = __sa_num(len), u8 = __sa_u8;
                \\  let s = 0, i = 0;
                \\  const h = Math.min(n, (4 - (a & 3)) & 3);
                \\  for (; i < h; i++) s += u8[a + i];
                \\  const w = new Uint32Array(__sa_memory, a + i, ((n - i) >> 2));
                \\  for (let j = 0; j < w.length; j++) { const v = w[j]; s += (v & 255) + ((v >> 8) & 255) + ((v >> 16) & 255) + (v >>> 24); }
                \\  i += w.length << 2;
                \\  for (; i < n; i++) s += u8[a + i];
                \\  return s;
                \\}
                \\
            );
            return;
        }
        if (std.mem.eql(u8, fsig.name, "sa_msum_u32")) {
            try writer.writeAll(
                \\function sa_msum_u32(ptr, len) {
                \\  const a = __sa_addr(ptr), n = __sa_num(len);
                \\  if ((a & 3) === 0) {
                \\  const w = __sa_tu32, o = a >> 2, e = o + (n >> 2);
                \\  let s = 0;
                \\  for (let i = o; i < e; i++) s += w[i];
                \\  return s > 4294967295 ? BigInt(s) : s;
                \\  }
                \\  const u = __sa_u8;
                \\  let s = 0;
                \\  for (let i = 0; i < n; i += 4) s += (((u[a + i] | (u[a + i + 1] << 8)) | (u[a + i + 2] << 16)) | (u[a + i + 3] << 24)) >>> 0;
                \\  return s;
                \\}
                \\
            );
            return;
        }
        if (std.mem.eql(u8, fsig.name, "sa_mwrite_u8")) {
            try writer.writeAll(
                \\function sa_mwrite_u8(ptr, len) {
                \\  const a = __sa_addr(ptr), n = __sa_num(len), w = __sa_u8.subarray(a, a + n);
                \\  for (let i = 0; i < n; i++) w[i] = i & 255;
                \\  return 0;
                \\}
                \\
            );
            return;
        }
        if (std.mem.eql(u8, fsig.name, "sa_mfind_u32")) {
            try writer.writeAll(
                \\function sa_mfind_u32(ptr, len, needle) {
                \\  const a = __sa_addr(ptr), n = __sa_num(len), t = __sa_num(needle) >>> 0;
                \\  if ((a & 3) === 0) {
                \\    // NOTE: the subarray is load-bearing, NOT gratuitous:
                \\    // indexOf scans to the END of its receiver, so a direct
                \\    // __sa_tu32.indexOf(t, base) scans megabytes on every
                \\    // miss (measured 425us vs ~1us bounded). Keep bounded.
                \\    const r = __sa_tu32.subarray(a >> 2, (a >> 2) + n).indexOf(t);
                \\    return r < 0 ? n : r;
                \\  }
                \\  const u = __sa_u8;
                \\  const b0 = t & 255, b1 = (t >> 8) & 255, b2 = (t >> 16) & 255, b3 = (t >>> 24) & 255;
                \\  for (let i = 0; i < n; i++) {
                \\    const o = a + (i << 2);
                \\    if (u[o] === b0 && u[o + 1] === b1 && u[o + 2] === b2 && u[o + 3] === b3) return i;
                \\  }
                \\  return n;
                \\}
                \\
            );
            return;
        }
        // Fused byte-substring search: single host memmem call when a
        // Buffer exists (same intrinsic the bun benches ultimately hit),
        // scalar first-byte filter + memcmp fallback otherwise. Returns
        // byte offset of first hit, or hay_len (miss sentinel). Empty
        // needle matches at 0; needle longer than haystack misses. The
        // indexOf scan may run past the hay range, so hits ending beyond
        // h+n are rejected (no complete in-range occurrence can hide
        // behind an earlier out-of-range one: indexOf returns the first).
        // Speed note: SA bump allocation keeps needle near hay, so the
        // scan usually terminates nearby; correctness never depends on it.
        if (std.mem.eql(u8, fsig.name, "sa_mfind_u8")) {
            try writer.writeAll(
                \\function sa_mfind_u8(hay_ptr, hay_len, ndl_ptr, ndl_len) {
                \\  const h = __sa_addr(hay_ptr), n = __sa_num(hay_len);
                \\  const q = __sa_addr(ndl_ptr), m = __sa_num(ndl_len), u = __sa_u8;
                \\  if (m === 0) return 0;
                \\  if (m > n) return n;
                \\  if (__sa_buf) {
                \\    const r = __sa_buf.indexOf(u.subarray(q, q + m), h);
                \\    if (r < h || r + m > h + n) return n;
                \\    return r - h;
                \\  }
                \\  const b0 = u[q], last = n - m;
                \\  for (let i = 0; i <= last; i++) {
                \\    if (u[h + i] !== b0) continue;
                \\    let k = 1;
                \\    for (; k < m; k++) { if (u[h + i + k] !== u[q + k]) break; }
                \\    if (k === m) return i;
                \\  }
                \\  return n;
                \\}
                \\
            );
            return;
        }
        // Host-codec shims: decode via the host Buffer (same intrinsic the
        // bun benches call). Both node and bun provide globalThis.Buffer;
        // without it these trap instead of silently falling back.
        // Two-pass in-place form: latin1 snapshot of the input range (one
        // C++ pass, no UTF-8 validation) + Buffer.write decode directly
        // into the output range (second C++ pass). No temp Buffer alloc,
        // no copy-back, no TextDecoder. For clean ASCII input the bytes
        // and return value are identical to Buffer.from(...).length.
        // Contract is strict: a short decode (garbage input or an
        // undersized out range) traps instead of returning short, so a
        // caller bug can never become silent data truncation.
        if (std.mem.eql(u8, fsig.name, "sa_b64dec")) {
            try writer.writeAll(
                \\function sa_b64dec(in_ptr, in_len, out_ptr) {
                \\  if (!__sa_buf) __sa_trap("no host Buffer for base64");
                \\  const a = __sa_addr(in_ptr), n = __sa_num(in_len), o = __sa_addr(out_ptr);
                \\  const w = __sa_buf.write(__sa_buf.toString("latin1", a, a + n), o, "base64");
                \\  if (w * 4 < n - 4) __sa_trap("base64 decode short output");
                \\  return w;
                \\}
                \\
            );
            return;
        }
        if (std.mem.eql(u8, fsig.name, "sa_hexdec")) {
            try writer.writeAll(
                \\function sa_hexdec(in_ptr, in_len, out_ptr) {
                \\  if (!__sa_buf) __sa_trap("no host Buffer for hex");
                \\  const a = __sa_addr(in_ptr), n = __sa_num(in_len), o = __sa_addr(out_ptr);
                \\  const w = __sa_buf.write(__sa_buf.toString("latin1", a, a + n), o, "hex");
                \\  if ((w << 1) < (n & ~1)) __sa_trap("hex decode short output");
                \\  return w;
                \\}
                \\
            );
            return;
        }
        // Fused HTML escape: single call, table-driven loop. Bridging
        // Bun.escapeHTML was measured and REJECTED (2026-10-13): its
        // string-in/string-out shape allocates 3 temp strings per call
        // (snapshot + escaped + quote-normalize) whose GC tax exceeds the
        // SIMD gain at 64KB granularity (bridge 342us vs table 155us
        // slope). The zero-alloc in-place table loop wins; same lesson as
        // the Buffer.write beat over Buffer.from+set. Bytes written are
        // identical to the old branch chain by construction.
        if (std.mem.eql(u8, fsig.name, "sa_esc_html")) {
            try writer.writeAll(
                \\function sa_esc_html(in_ptr, in_len, out_ptr) {
                \\  const a = __sa_addr(in_ptr), n = __sa_num(in_len), o = __sa_addr(out_ptr), u = __sa_u8;
                \\  let T = sa_esc_html.T;
                \\  if (!T) {
                \\    const L = new Uint8Array(256).fill(1), S = new Uint8Array(1536);
                \\    const put = (c, s) => { L[c] = s.length; for (let k = 0; k < s.length; k++) S[c * 6 + k] = s.charCodeAt(k); };
                \\    put(60, "&lt;"); put(62, "&gt;"); put(38, "&amp;"); put(34, "&quot;"); put(39, "&#39;");
                \\    T = sa_esc_html.T = [L, S];
                \\  }
                \\  const L = T[0], S = T[1];
                \\  let w = o;
                \\  for (let i = 0; i < n; i++) {
                \\    const c = u[a + i], l = L[c];
                \\    if (l === 1) { u[w++] = c; continue; }
                \\    const t = c * 6;
                \\    u[w] = S[t]; u[w + 1] = S[t + 1]; u[w + 2] = S[t + 2]; u[w + 3] = S[t + 3];
                \\    if (l > 4) { u[w + 4] = S[t + 4]; if (l > 5) u[w + 5] = S[t + 5]; }
                \\    w += l;
                \\  }
                \\  return w - o;
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
                \\function sa_time_unix_ms() { if (!__sa_policy_unit('time')) return 0n; return BigInt.asIntN(64, BigInt(globalThis.Date.now())); }
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
                \\function sa_time_instant_ns() { if (!__sa_policy_unit('time')) return 0n; return BigInt.asUintN(64, BigInt(globalThis.Date.now()) * 1000000n); }
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
        if (std.mem.eql(u8, fsig.name, "sa_regex_match_all")) {
            try writer.writeAll(
                \\function sa_regex_match_all(regex, text, text_len) {
                \\  const rec = __sa_regexes.get(__sa_num(regex));
                \\  if (rec === undefined) return 0n;
                \\  const bytes = __sa_mem_bytes(text, text_len);
                \\  for (let i = 0; i < bytes.length; i++) if (bytes[i] === 0) return 0n;
                \\  const s = new globalThis.TextDecoder().decode(bytes);
                \\  const matches = __sa_regex_collect(rec, s);
                \\  const p = __sa_alloc(bytes.length);
                \\  __sa_u8.set(bytes, p);
                \\  const h = __sa_regexlistnext++;
                \\  __sa_regexlists.set(h, { base: p, len: bytes.length, matches: matches });
                \\  return BigInt(h);
                \\}
                \\
            );
            return;
        }
        if (std.mem.eql(u8, fsig.name, "sa_unicode_normalize")) {
            try writer.writeAll(
                \\function sa_unicode_normalize(text, text_len, form, out, out_cap) {
                \\  const bytes = __sa_mem_bytes(text, text_len);
                \\  const s = new globalThis.TextDecoder().decode(bytes);
                \\  const forms = ["NFC", "NFD", "NFKC", "NFKD"];
                \\  const f = __sa_num(form);
                \\  if (f < 0 || f > 3) throw new globalThis.RangeError("Invalid normalization form");
                \\  const norm = s.normalize(forms[f]);
                \\  const enc = new globalThis.TextEncoder().encode(norm);
                \\  if (__sa_num(out_cap) === 0) return BigInt(enc.length);
                \\  if (enc.length > __sa_num(out_cap)) return BigInt(enc.length);
                \\  __sa_u8.set(enc, __sa_addr(out));
                \\  return BigInt(enc.length);
                \\}
                \\
            );
            return;
        }
        if (std.mem.eql(u8, fsig.name, "sa_host_is_bun")) {
            try writer.writeAll(
                \\function sa_host_is_bun() {
                \\  return typeof Bun !== "undefined" ? 1 : 0;
                \\}
                \\
            );
            return;
        }
        if (std.mem.eql(u8, fsig.name, "sa_regex_match_list_count")) {
            try writer.writeAll(
                \\function sa_regex_match_list_count(list) {
                \\  const lst = __sa_regexlists.get(__sa_num(list));
                \\  if (lst === undefined) return 0n;
                \\  return BigInt(lst.matches.length);
                \\}
                \\
            );
            return;
        }
        if (std.mem.eql(u8, fsig.name, "sa_regex_match_list_at")) {
            try writer.writeAll(
                \\function sa_regex_match_list_at(list, index) {
                \\  const lst = __sa_regexlists.get(__sa_num(list));
                \\  if (lst === undefined) return 0n;
                \\  const i = __sa_tou(index);
                \\  if (!(i >= 0) || i >= lst.matches.length) return 0n;
                \\  const bytes = __sa_mem_bytes(lst.base, lst.len);
                \\  const p = __sa_alloc(bytes.length);
                \\  __sa_u8.set(bytes, p);
                \\  const groups = lst.matches[i].map((g) => [g[0], g[1]]);
                \\  const h = __sa_regexmatchnext++;
                \\  __sa_regexmatches.set(h, { base: p, len: bytes.length, groups: groups });
                \\  return BigInt(h);
                \\}
                \\
            );
            return;
        }
        if (std.mem.eql(u8, fsig.name, "sa_regex_match_list_free")) {
            try writer.writeAll(
                \\function sa_regex_match_list_free(list) {
                \\  const lst = __sa_regexlists.get(__sa_num(list));
                \\  if (lst !== undefined) { __sa_regexlists.delete(__sa_num(list)); __sa_free(lst.base); }
                \\  return 0;
                \\}
                \\
            );
            return;
        }
        if (std.mem.eql(u8, fsig.name, "sa_regex_replace")) {
            try writer.writeAll(
                \\function sa_regex_replace(regex, text, text_len, replacement, replacement_len) {
                \\  const rec = __sa_regexes.get(__sa_num(regex));
                \\  if (rec === undefined) return 0n;
                \\  const bytes = __sa_mem_bytes(text, text_len);
                \\  for (let i = 0; i < bytes.length; i++) if (bytes[i] === 0) return 0n;
                \\  const s = new globalThis.TextDecoder().decode(bytes);
                \\  const repl = new globalThis.TextDecoder().decode(__sa_mem_bytes(replacement, replacement_len));
                \\  const re = new RegExp(rec.re.source, rec.re.flags);
                \\  const m = re.exec(s);
                \\  let out = s;
                \\  if (m !== null && m.indices !== undefined) {
                \\    const groups = m.indices.map((g) => ((g === undefined) ? [-1, -1] : [g[0], g[1]]));
                \\    out = s.slice(0, groups[0][0]) + __sa_regex_expand(s, groups, repl) + s.slice(groups[0][1]);
                \\  }
                \\  const ob = new globalThis.TextEncoder().encode(out);
                \\  const p = __sa_alloc(ob.length);
                \\  __sa_u8.set(ob, p);
                \\  const h = __sa_regexbufnext++;
                \\  __sa_regexbufs.set(h, { base: p, len: ob.length });
                \\  return BigInt(h);
                \\}
                \\
            );
            return;
        }
        if (std.mem.eql(u8, fsig.name, "sa_regex_replace_all")) {
            try writer.writeAll(
                \\function sa_regex_replace_all(regex, text, text_len, replacement, replacement_len) {
                \\  const rec = __sa_regexes.get(__sa_num(regex));
                \\  if (rec === undefined) return 0n;
                \\  const bytes = __sa_mem_bytes(text, text_len);
                \\  for (let i = 0; i < bytes.length; i++) if (bytes[i] === 0) return 0n;
                \\  const s = new globalThis.TextDecoder().decode(bytes);
                \\  const repl = new globalThis.TextDecoder().decode(__sa_mem_bytes(replacement, replacement_len));
                \\  const matches = __sa_regex_collect(rec, s);
                \\  let out = "";
                \\  let last = 0;
                \\  for (const groups of matches) {
                \\    out += s.slice(last, groups[0][0]);
                \\    out += __sa_regex_expand(s, groups, repl);
                \\    last = groups[0][1];
                \\  }
                \\  out += s.slice(last);
                \\  const ob = new globalThis.TextEncoder().encode(out);
                \\  const p = __sa_alloc(ob.length);
                \\  __sa_u8.set(ob, p);
                \\  const h = __sa_regexbufnext++;
                \\  __sa_regexbufs.set(h, { base: p, len: ob.length });
                \\  return BigInt(h);
                \\}
                \\
            );
            return;
        }
        if (std.mem.eql(u8, fsig.name, "sa_regex_buffer_data")) {
            try writer.writeAll(
                \\function sa_regex_buffer_data(buffer) {
                \\  const b = __sa_regexbufs.get(__sa_num(buffer));
                \\  if (b === undefined) return 0;
                \\  return b.base;
                \\}
                \\
            );
            return;
        }
        if (std.mem.eql(u8, fsig.name, "sa_regex_buffer_len")) {
            try writer.writeAll(
                \\function sa_regex_buffer_len(buffer) {
                \\  const b = __sa_regexbufs.get(__sa_num(buffer));
                \\  if (b === undefined) return 0n;
                \\  return BigInt(b.len);
                \\}
                \\
            );
            return;
        }
        if (std.mem.eql(u8, fsig.name, "sa_regex_buffer_free")) {
            try writer.writeAll(
                \\function sa_regex_buffer_free(buffer) {
                \\  const b = __sa_regexbufs.get(__sa_num(buffer));
                \\  if (b !== undefined) { __sa_regexbufs.delete(__sa_num(buffer)); __sa_free(b.base); }
                \\  return 0;
                \\}
                \\
            );
            return;
        }
        if (std.mem.eql(u8, fsig.name, "sa_regex_split")) {
            try writer.writeAll(
                \\function sa_regex_split(regex, text, text_len, limit) {
                \\  const rec = __sa_regexes.get(__sa_num(regex));
                \\  if (rec === undefined) return 0n;
                \\  const bytes = __sa_mem_bytes(text, text_len);
                \\  for (let i = 0; i < bytes.length; i++) if (bytes[i] === 0) return 0n;
                \\  const s = new globalThis.TextDecoder().decode(bytes);
                \\  const pieces = __sa_regex_split_pieces(rec, s, __sa_tou(limit));
                \\  const p = __sa_alloc(bytes.length);
                \\  __sa_u8.set(bytes, p);
                \\  const h = __sa_regexsplitnext++;
                \\  __sa_regexsplits.set(h, { base: p, len: bytes.length, pieces: pieces });
                \\  return BigInt(h);
                \\}
                \\
            );
            return;
        }
        if (std.mem.eql(u8, fsig.name, "sa_regex_split_count")) {
            try writer.writeAll(
                \\function sa_regex_split_count(list) {
                \\  const lst = __sa_regexsplits.get(__sa_num(list));
                \\  if (lst === undefined) return 0n;
                \\  return BigInt(lst.pieces.length);
                \\}
                \\
            );
            return;
        }
        if (std.mem.eql(u8, fsig.name, "sa_regex_split_ptr")) {
            try writer.writeAll(
                \\function sa_regex_split_ptr(list, index) {
                \\  const lst = __sa_regexsplits.get(__sa_num(list));
                \\  if (lst === undefined) return 0;
                \\  const i = __sa_tou(index);
                \\  if (!(i >= 0) || i >= lst.pieces.length) return 0;
                \\  const pc = lst.pieces[i];
                \\  if (pc[0] < 0) return 0;
                \\  return __sa_ptr_add(lst.base, pc[0]);
                \\}
                \\
            );
            return;
        }
        if (std.mem.eql(u8, fsig.name, "sa_regex_split_len")) {
            try writer.writeAll(
                \\function sa_regex_split_len(list, index) {
                \\  const lst = __sa_regexsplits.get(__sa_num(list));
                \\  if (lst === undefined) return 0n;
                \\  const i = __sa_tou(index);
                \\  if (!(i >= 0) || i >= lst.pieces.length) return 0n;
                \\  const pc = lst.pieces[i];
                \\  if (pc[0] < 0 || pc[1] < 0) return 0n;
                \\  return BigInt(pc[1] - pc[0]);
                \\}
                \\
            );
            return;
        }
        if (std.mem.eql(u8, fsig.name, "sa_regex_split_free")) {
            try writer.writeAll(
                \\function sa_regex_split_free(list) {
                \\  const lst = __sa_regexsplits.get(__sa_num(list));
                \\  if (lst !== undefined) { __sa_regexsplits.delete(__sa_num(list)); __sa_free(lst.base); }
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
        if (std.mem.eql(u8, fsig.name, "sa_json_object_set_string")) {
            try writer.writeAll(
                \\function sa_json_object_set_string(node, key_ptr, key_len, data_ptr, len) {
                \\  const key = new globalThis.TextDecoder().decode(__sa_mem_bytes(key_ptr, key_len));
                \\  if (key.length === 0) return 1;
                \\  const v = __sa_jsonnodes.get(__sa_num(node));
                \\  if (v === undefined || v === null || typeof v !== "object" || Array.isArray(v)) return 2;
                \\  v[key] = new globalThis.TextDecoder().decode(__sa_mem_bytes(data_ptr, len));
                \\  return 0;
                \\}
                \\
            );
            return;
        }
        if (std.mem.eql(u8, fsig.name, "sa_json_object_set_i64")) {
            try writer.writeAll(
                \\function sa_json_object_set_i64(node, key_ptr, key_len, value) {
                \\  const key = new globalThis.TextDecoder().decode(__sa_mem_bytes(key_ptr, key_len));
                \\  if (key.length === 0) return 1;
                \\  const v = __sa_jsonnodes.get(__sa_num(node));
                \\  if (v === undefined || v === null || typeof v !== "object" || Array.isArray(v)) return 2;
                \\  v[key] = Number(BigInt.asIntN(64, BigInt(__sa_num(value))));
                \\  return 0;
                \\}
                \\
            );
            return;
        }
        if (std.mem.eql(u8, fsig.name, "sa_json_object_set_f64")) {
            try writer.writeAll(
                \\function sa_json_object_set_f64(node, key_ptr, key_len, value) {
                \\  const key = new globalThis.TextDecoder().decode(__sa_mem_bytes(key_ptr, key_len));
                \\  if (key.length === 0) return 1;
                \\  if (!Number.isFinite(+value)) return 1;
                \\  const v = __sa_jsonnodes.get(__sa_num(node));
                \\  if (v === undefined || v === null || typeof v !== "object" || Array.isArray(v)) return 2;
                \\  v[key] = +value;
                \\  return 0;
                \\}
                \\
            );
            return;
        }
        if (std.mem.eql(u8, fsig.name, "sa_json_object_set_bool")) {
            try writer.writeAll(
                \\function sa_json_object_set_bool(node, key_ptr, key_len, value) {
                \\  const key = new globalThis.TextDecoder().decode(__sa_mem_bytes(key_ptr, key_len));
                \\  if (key.length === 0) return 1;
                \\  const v = __sa_jsonnodes.get(__sa_num(node));
                \\  if (v === undefined || v === null || typeof v !== "object" || Array.isArray(v)) return 2;
                \\  v[key] = __sa_num(value) !== 0;
                \\  return 0;
                \\}
                \\
            );
            return;
        }
        if (std.mem.eql(u8, fsig.name, "sa_json_object_set_null")) {
            try writer.writeAll(
                \\function sa_json_object_set_null(node, key_ptr, key_len) {
                \\  const key = new globalThis.TextDecoder().decode(__sa_mem_bytes(key_ptr, key_len));
                \\  if (key.length === 0) return 1;
                \\  const v = __sa_jsonnodes.get(__sa_num(node));
                \\  if (v === undefined || v === null || typeof v !== "object" || Array.isArray(v)) return 2;
                \\  v[key] = null;
                \\  return 0;
                \\}
                \\
            );
            return;
        }
        if (std.mem.eql(u8, fsig.name, "sa_json_object_set_node")) {
            try writer.writeAll(
                \\function sa_json_object_set_node(node, key_ptr, key_len, child) {
                \\  const key = new globalThis.TextDecoder().decode(__sa_mem_bytes(key_ptr, key_len));
                \\  if (key.length === 0) return 1;
                \\  const v = __sa_jsonnodes.get(__sa_num(node));
                \\  if (v === undefined || v === null || typeof v !== "object" || Array.isArray(v)) return 2;
                \\  const cv = __sa_jsonnodes.get(__sa_num(child));
                \\  if (cv === undefined) return 2;
                \\  v[key] = __sa_json_clone(cv);
                \\  return 0;
                \\}
                \\
            );
            return;
        }
        if (std.mem.eql(u8, fsig.name, "sa_json_object_remove")) {
            try writer.writeAll(
                \\function sa_json_object_remove(node, key_ptr, key_len) {
                \\  const key = new globalThis.TextDecoder().decode(__sa_mem_bytes(key_ptr, key_len));
                \\  if (key.length === 0) return 1;
                \\  const v = __sa_jsonnodes.get(__sa_num(node));
                \\  if (v === undefined || v === null || typeof v !== "object" || Array.isArray(v)) return 2;
                \\  if (!Object.prototype.hasOwnProperty.call(v, key)) return 3;
                \\  delete v[key];
                \\  return 0;
                \\}
                \\
            );
            return;
        }
        if (std.mem.eql(u8, fsig.name, "sa_json_array_push_string")) {
            try writer.writeAll(
                \\function sa_json_array_push_string(node, data_ptr, len) {
                \\  const v = __sa_jsonnodes.get(__sa_num(node));
                \\  if (v === undefined || !Array.isArray(v)) return 2;
                \\  v.push(new globalThis.TextDecoder().decode(__sa_mem_bytes(data_ptr, len)));
                \\  return 0;
                \\}
                \\
            );
            return;
        }
        if (std.mem.eql(u8, fsig.name, "sa_json_array_push_i64")) {
            try writer.writeAll(
                \\function sa_json_array_push_i64(node, value) {
                \\  const v = __sa_jsonnodes.get(__sa_num(node));
                \\  if (v === undefined || !Array.isArray(v)) return 2;
                \\  v.push(Number(BigInt.asIntN(64, BigInt(__sa_num(value)))));
                \\  return 0;
                \\}
                \\
            );
            return;
        }
        if (std.mem.eql(u8, fsig.name, "sa_json_array_push_f64")) {
            try writer.writeAll(
                \\function sa_json_array_push_f64(node, value) {
                \\  if (!Number.isFinite(+value)) return 1;
                \\  const v = __sa_jsonnodes.get(__sa_num(node));
                \\  if (v === undefined || !Array.isArray(v)) return 2;
                \\  v.push(+value);
                \\  return 0;
                \\}
                \\
            );
            return;
        }
        if (std.mem.eql(u8, fsig.name, "sa_json_array_push_bool")) {
            try writer.writeAll(
                \\function sa_json_array_push_bool(node, value) {
                \\  const v = __sa_jsonnodes.get(__sa_num(node));
                \\  if (v === undefined || !Array.isArray(v)) return 2;
                \\  v.push(__sa_num(value) !== 0);
                \\  return 0;
                \\}
                \\
            );
            return;
        }
        if (std.mem.eql(u8, fsig.name, "sa_json_array_push_null")) {
            try writer.writeAll(
                \\function sa_json_array_push_null(node) {
                \\  const v = __sa_jsonnodes.get(__sa_num(node));
                \\  if (v === undefined || !Array.isArray(v)) return 2;
                \\  v.push(null);
                \\  return 0;
                \\}
                \\
            );
            return;
        }
        if (std.mem.eql(u8, fsig.name, "sa_json_array_push_node")) {
            try writer.writeAll(
                \\function sa_json_array_push_node(node, child) {
                \\  const v = __sa_jsonnodes.get(__sa_num(node));
                \\  if (v === undefined || !Array.isArray(v)) return 2;
                \\  const cv = __sa_jsonnodes.get(__sa_num(child));
                \\  if (cv === undefined) return 2;
                \\  v.push(__sa_json_clone(cv));
                \\  return 0;
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
                \\  if (!__sa_policy_unit('random')) return 10;
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
                \\    if (!__sa_policy_fs(p, false)) return 10;
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
                \\    if (!__sa_policy_fs(p, true)) return 10;
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
                \\    if (!__sa_policy_fs(p, true)) return 10;
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
                \\    if (!__sa_policy_fs(p, true)) return 10;
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
        if (std.mem.eql(u8, fsig.name, "sa_std_compress_supported")) {
            try writer.writeAll(
                \\function sa_std_compress_supported(out_flags) {
                \\  let flags = 0;
                \\  const z = __sa_node_builtin("node:zlib");
                \\  if (z) { flags = 1; if (z.brotliCompressSync && z.brotliDecompressSync) flags |= 2; }
                \\  __sa_store_i64(out_flags, BigInt(flags));
                \\  return 0;
                \\}
                \\
            );
            return;
        }
        if (std.mem.eql(u8, fsig.name, "sa_std_compress_encode")) {
            try writer.writeAll(
                \\function sa_std_compress_encode(format, data, data_len, out_handle) {
                \\  const z = __sa_node_builtin("node:zlib");
                \\  if (!z) return 8;
                \\  const f = __sa_num(format);
                \\  const a = __sa_addr(data), n = __sa_num(data_len);
                \\  const input = __sa_u8.slice(a, a + n);
                \\  let out = null;
                \\  try {
                \\    if (f === 1) out = z.gzipSync(input);
                \\    else if (f === 2) out = z.deflateSync(input);
                \\    else if (f === 3) out = z.deflateRawSync(input);
                \\    else if (f === 4) { if (!z.brotliCompressSync) return 8; out = z.brotliCompressSync(input); }
                \\    else return 1;
                \\  } catch (e) { return 6; }
                \\  globalThis.__sa_cbuf = (globalThis.__sa_cbuf || { next: 1, map: {} });
                \\  const id = globalThis.__sa_cbuf.next++;
                \\  globalThis.__sa_cbuf.map[id] = { bytes: new Uint8Array(out), addr: 0 };
                \\  __sa_store_i64(out_handle, BigInt(id));
                \\  return 0;
                \\}
                \\
            );
            return;
        }
        if (std.mem.eql(u8, fsig.name, "sa_std_compress_decode")) {
            try writer.writeAll(
                \\function sa_std_compress_decode(format, data, data_len, out_handle) {
                \\  const z = __sa_node_builtin("node:zlib");
                \\  if (!z) return 8;
                \\  const f = __sa_num(format);
                \\  const a = __sa_addr(data), n = __sa_num(data_len);
                \\  const input = __sa_u8.slice(a, a + n);
                \\  let out = null;
                \\  try {
                \\    if (f === 1) out = z.gunzipSync(input);
                \\    else if (f === 2) out = z.inflateSync(input);
                \\    else if (f === 3) out = z.inflateRawSync(input);
                \\    else if (f === 4) { if (!z.brotliDecompressSync) return 8; out = z.brotliDecompressSync(input); }
                \\    else return 1;
                \\  } catch (e) { return 6; }
                \\  globalThis.__sa_cbuf = (globalThis.__sa_cbuf || { next: 1, map: {} });
                \\  const id = globalThis.__sa_cbuf.next++;
                \\  globalThis.__sa_cbuf.map[id] = { bytes: new Uint8Array(out), addr: 0 };
                \\  __sa_store_i64(out_handle, BigInt(id));
                \\  return 0;
                \\}
                \\
            );
            return;
        }
        if (std.mem.eql(u8, fsig.name, "sa_std_compress_buffer_data")) {
            try writer.writeAll(
                \\function sa_std_compress_buffer_data(buffer) {
                \\  const m = globalThis.__sa_cbuf;
                \\  const rec = m ? m.map[Number(buffer)] : null;
                \\  if (!rec) return 0;
                \\  if (!rec.addr) { rec.addr = __sa_alloc(rec.bytes.length); __sa_u8.set(rec.bytes, rec.addr); }
                \\  return rec.addr;
                \\}
                \\
            );
            return;
        }
        if (std.mem.eql(u8, fsig.name, "sa_std_compress_buffer_len")) {
            try writer.writeAll(
                \\function sa_std_compress_buffer_len(buffer) {
                \\  const m = globalThis.__sa_cbuf;
                \\  const rec = m ? m.map[Number(buffer)] : null;
                \\  return rec ? BigInt(rec.bytes.length) : BigInt(0);
                \\}
                \\
            );
            return;
        }
        if (std.mem.eql(u8, fsig.name, "sa_std_compress_buffer_free")) {
            try writer.writeAll(
                \\function sa_std_compress_buffer_free(buffer) {
                \\  const m = globalThis.__sa_cbuf;
                \\  if (m) { const rec = m.map[Number(buffer)]; if (rec) { if (rec.addr) __sa_free(rec.addr); delete m.map[Number(buffer)]; } }
                \\  return 0;
                \\}
                \\
            );
            return;
        }
        if (std.mem.eql(u8, fsig.name, "sa_std_multipart_parse")) {
            try writer.writeAll(
                \\function sa_std_multipart_parse(body, body_len, content_type, content_type_len, out_handle) {
                \\  globalThis.__sa_mp = (globalThis.__sa_mp || { next: 1, items: {}, bufs: {} });
                \\  const dec = new globalThis.TextDecoder();
                \\  const ba = __sa_addr(body), bn = __sa_num(body_len);
                \\  const ca = __sa_addr(content_type), cn = __sa_num(content_type_len);
                \\  const ct = dec.decode(__sa_u8.slice(ca, ca + cn));
                \\  let boundary = null;
                \\  for (const part of ct.split(";")) {
                \\    const t = part.trim();
                \\    if (t.startsWith("boundary=")) { boundary = t.slice(9).trim(); if (boundary.startsWith("\"") && boundary.endsWith("\"")) boundary = boundary.slice(1, -1); }
                \\  }
                \\  if (!boundary) return 1;
                \\  const raw = __sa_u8.slice(ba, ba + bn);
                \\  let text = "";
                \\  for (let i = 0; i < raw.length; i += 8192) text += String.fromCharCode.apply(null, raw.subarray(i, i + 8192));
                \\  const segs = text.split("--" + boundary);
                \\  const parts = [];
                \\  for (let i = 1; i < segs.length; i++) {
                \\    let seg = segs[i];
                \\    if (seg.startsWith("--")) break;
                \\    if (!seg.startsWith("\r\n")) return 1;
                \\    seg = seg.slice(2);
                \\    if (seg.endsWith("\r\n")) seg = seg.slice(0, -2);
                \\    const cut = seg.indexOf("\r\n\r\n");
                \\    if (cut < 0) return 1;
                \\    const head = seg.slice(0, cut);
                \\    const pbody = seg.slice(cut + 4);
                \\    const part = { name: "", filename: null, contentType: null, headers: [], body: new Uint8Array(pbody.length) };
                \\    for (let j = 0; j < pbody.length; j++) part.body[j] = pbody.charCodeAt(j) & 255;
                \\    for (const line of head.split("\r\n")) {
                \\      const colon = line.indexOf(":");
                \\      if (colon < 0) continue;
                \\      const hn = line.slice(0, colon).trim();
                \\      const hv = line.slice(colon + 1).trim();
                \\      part.headers.push([hn, hv]);
                \\      const lhn = hn.toLowerCase();
                \\      if (lhn === "content-type") part.contentType = hv;
                \\      if (lhn === "content-disposition") {
                \\        for (const tok of hv.split(";")) {
                \\          const t = tok.trim();
                \\          const eq = t.indexOf("=");
                \\          if (eq < 0) continue;
                \\          const k = t.slice(0, eq).trim();
                \\          let v = t.slice(eq + 1).trim();
                \\          if (v.startsWith("\"") && v.endsWith("\"")) v = v.slice(1, -1);
                \\          if (k === "name") part.name = v;
                \\          if (k === "filename") part.filename = v;
                \\        }
                \\      }
                \\    }
                \\    parts.push(part);
                \\  }
                \\  const id = globalThis.__sa_mp.next++;
                \\  globalThis.__sa_mp.items[id] = { kind: "parsed", parts: parts };
                \\  __sa_store_i64(out_handle, BigInt(id));
                \\  return 0;
                \\}
                \\
            );
            return;
        }
        if (std.mem.eql(u8, fsig.name, "sa_std_multipart_free")) {
            try writer.writeAll(
                \\function sa_std_multipart_free(handle) {
                \\  globalThis.__sa_mp = (globalThis.__sa_mp || { next: 1, items: {}, bufs: {} });
                \\  delete globalThis.__sa_mp.items[Number(handle)];
                \\  return 0;
                \\}
                \\
            );
            return;
        }
        if (std.mem.eql(u8, fsig.name, "sa_std_multipart_count")) {
            try writer.writeAll(
                \\function sa_std_multipart_count(handle) {
                \\  globalThis.__sa_mp = (globalThis.__sa_mp || { next: 1, items: {}, bufs: {} });
                \\  const it = globalThis.__sa_mp.items[Number(handle)];
                \\  return (it && it.kind === "parsed") ? BigInt(it.parts.length) : BigInt(0);
                \\}
                \\
            );
            return;
        }
        if (std.mem.eql(u8, fsig.name, "sa_std_multipart_part_name")) {
            try writer.writeAll(
                \\function sa_std_multipart_part_name(handle, index, out, cap, out_len) {
                \\  globalThis.__sa_mp = (globalThis.__sa_mp || { next: 1, items: {}, bufs: {} });
                \\  const it = globalThis.__sa_mp.items[Number(handle)];
                \\  if (!it || it.kind !== "parsed") return 3;
                \\  const part = it.parts[__sa_num(index)];
                \\  if (!part) return 3;
                \\  const value = part.name;
                \\  const enc = new globalThis.TextEncoder();
                \\  const bytes = enc.encode(value);
                \\  __sa_store_i64(out_len, BigInt(bytes.length));
                \\  if (__sa_num(cap) < bytes.length) return 9;
                \\  __sa_u8.set(bytes, __sa_addr(out));
                \\  return 0;
                \\}
                \\
            );
            return;
        }
        if (std.mem.eql(u8, fsig.name, "sa_std_multipart_part_filename")) {
            try writer.writeAll(
                \\function sa_std_multipart_part_filename(handle, index, out, cap, out_len) {
                \\  globalThis.__sa_mp = (globalThis.__sa_mp || { next: 1, items: {}, bufs: {} });
                \\  const it = globalThis.__sa_mp.items[Number(handle)];
                \\  if (!it || it.kind !== "parsed") return 3;
                \\  const part = it.parts[__sa_num(index)];
                \\  if (!part) return 3;
                \\  const value = part.filename;
                \\  if (value === null || value === undefined) return 100;
                \\  const enc = new globalThis.TextEncoder();
                \\  const bytes = enc.encode(value);
                \\  __sa_store_i64(out_len, BigInt(bytes.length));
                \\  if (__sa_num(cap) < bytes.length) return 9;
                \\  __sa_u8.set(bytes, __sa_addr(out));
                \\  return 0;
                \\}
                \\
            );
            return;
        }
        if (std.mem.eql(u8, fsig.name, "sa_std_multipart_part_content_type")) {
            try writer.writeAll(
                \\function sa_std_multipart_part_content_type(handle, index, out, cap, out_len) {
                \\  globalThis.__sa_mp = (globalThis.__sa_mp || { next: 1, items: {}, bufs: {} });
                \\  const it = globalThis.__sa_mp.items[Number(handle)];
                \\  if (!it || it.kind !== "parsed") return 3;
                \\  const part = it.parts[__sa_num(index)];
                \\  if (!part) return 3;
                \\  const value = part.contentType;
                \\  if (value === null || value === undefined) return 100;
                \\  const enc = new globalThis.TextEncoder();
                \\  const bytes = enc.encode(value);
                \\  __sa_store_i64(out_len, BigInt(bytes.length));
                \\  if (__sa_num(cap) < bytes.length) return 9;
                \\  __sa_u8.set(bytes, __sa_addr(out));
                \\  return 0;
                \\}
                \\
            );
            return;
        }
        if (std.mem.eql(u8, fsig.name, "sa_std_multipart_part_header")) {
            try writer.writeAll(
                \\function sa_std_multipart_part_header(handle, index, name, name_len, out, cap, out_len) {
                \\  globalThis.__sa_mp = (globalThis.__sa_mp || { next: 1, items: {}, bufs: {} });
                \\  const it = globalThis.__sa_mp.items[Number(handle)];
                \\  if (!it || it.kind !== "parsed") return 3;
                \\  const part = it.parts[__sa_num(index)];
                \\  if (!part) return 3;
                \\  const dec = new globalThis.TextDecoder();
                \\  const na = __sa_addr(name), nn = __sa_num(name_len);
                \\  const want = dec.decode(__sa_u8.slice(na, na + nn)).toLowerCase();
                \\  let value = null;
                \\  for (const pair of part.headers) { if (pair[0].toLowerCase() === want) { value = pair[1]; break; } }
                \\  if (value === null) return 100;
                \\  const enc = new globalThis.TextEncoder();
                \\  const bytes = enc.encode(value);
                \\  __sa_store_i64(out_len, BigInt(bytes.length));
                \\  if (__sa_num(cap) < bytes.length) return 9;
                \\  __sa_u8.set(bytes, __sa_addr(out));
                \\  return 0;
                \\}
                \\
            );
            return;
        }
        if (std.mem.eql(u8, fsig.name, "sa_std_multipart_part_body")) {
            try writer.writeAll(
                \\function sa_std_multipart_part_body(handle, index, out_ptr, out_len) {
                \\  globalThis.__sa_mp = (globalThis.__sa_mp || { next: 1, items: {}, bufs: {} });
                \\  const it = globalThis.__sa_mp.items[Number(handle)];
                \\  if (!it || it.kind !== "parsed") return 3;
                \\  const part = it.parts[__sa_num(index)];
                \\  if (!part) return 3;
                \\  if (!part.addr) { part.addr = __sa_alloc(part.body.length); __sa_u8.set(part.body, part.addr); }
                \\  __sa_store_ptr(out_ptr, part.addr);
                \\  __sa_store_i64(out_len, BigInt(part.body.length));
                \\  return 0;
                \\}
                \\
            );
            return;
        }
        if (std.mem.eql(u8, fsig.name, "sa_std_multipart_builder_new")) {
            try writer.writeAll(
                \\function sa_std_multipart_builder_new(out_handle) {
                \\  globalThis.__sa_mp = (globalThis.__sa_mp || { next: 1, items: {}, bufs: {} });
                \\  const id = globalThis.__sa_mp.next++;
                \\  globalThis.__sa_mp.items[id] = { kind: "builder", list: [], boundary: "----sa-std-multipart-js-" + id };
                \\  __sa_store_i64(out_handle, BigInt(id));
                \\  return 0;
                \\}
                \\
            );
            return;
        }
        if (std.mem.eql(u8, fsig.name, "sa_std_multipart_builder_free")) {
            try writer.writeAll(
                \\function sa_std_multipart_builder_free(handle) {
                \\  globalThis.__sa_mp = (globalThis.__sa_mp || { next: 1, items: {}, bufs: {} });
                \\  delete globalThis.__sa_mp.items[Number(handle)];
                \\  return 0;
                \\}
                \\
            );
            return;
        }
        if (std.mem.eql(u8, fsig.name, "sa_std_multipart_builder_add_field")) {
            try writer.writeAll(
                \\function sa_std_multipart_builder_add_field(handle, name, name_len, value, value_len) {
                \\  globalThis.__sa_mp = (globalThis.__sa_mp || { next: 1, items: {}, bufs: {} });
                \\  const it = globalThis.__sa_mp.items[Number(handle)];
                \\  if (!it || it.kind !== "builder") return 2;
                \\  const na = __sa_addr(name), nn = __sa_num(name_len);
                \\  const va = __sa_addr(value), vn = __sa_num(value_len);
                \\  it.list.push({ name: __sa_u8.slice(na, na + nn), filename: null, contentType: null, data: __sa_u8.slice(va, va + vn) });
                \\  return 0;
                \\}
                \\
            );
            return;
        }
        if (std.mem.eql(u8, fsig.name, "sa_std_multipart_builder_add_file")) {
            try writer.writeAll(
                \\function sa_std_multipart_builder_add_file(handle, name, name_len, filename, filename_len, content_type, content_type_len, data, data_len) {
                \\  globalThis.__sa_mp = (globalThis.__sa_mp || { next: 1, items: {}, bufs: {} });
                \\  const it = globalThis.__sa_mp.items[Number(handle)];
                \\  if (!it || it.kind !== "builder") return 2;
                \\  it.list.push({
                \\    name: __sa_u8.slice(__sa_addr(name), __sa_addr(name) + __sa_num(name_len)),
                \\    filename: __sa_u8.slice(__sa_addr(filename), __sa_addr(filename) + __sa_num(filename_len)),
                \\    contentType: __sa_u8.slice(__sa_addr(content_type), __sa_addr(content_type) + __sa_num(content_type_len)),
                \\    data: __sa_u8.slice(__sa_addr(data), __sa_addr(data) + __sa_num(data_len))
                \\  });
                \\  return 0;
                \\}
                \\
            );
            return;
        }
        if (std.mem.eql(u8, fsig.name, "sa_std_multipart_builder_boundary")) {
            try writer.writeAll(
                \\function sa_std_multipart_builder_boundary(handle, out, cap, out_len) {
                \\  globalThis.__sa_mp = (globalThis.__sa_mp || { next: 1, items: {}, bufs: {} });
                \\  const it = globalThis.__sa_mp.items[Number(handle)];
                \\  if (!it || it.kind !== "builder") return 2;
                \\  const value = it.boundary;
                \\  const enc = new globalThis.TextEncoder();
                \\  const bytes = enc.encode(value);
                \\  __sa_store_i64(out_len, BigInt(bytes.length));
                \\  if (__sa_num(cap) < bytes.length) return 9;
                \\  __sa_u8.set(bytes, __sa_addr(out));
                \\  return 0;
                \\}
                \\
            );
            return;
        }
        if (std.mem.eql(u8, fsig.name, "sa_std_multipart_builder_content_type")) {
            try writer.writeAll(
                \\function sa_std_multipart_builder_content_type(handle, out, cap, out_len) {
                \\  globalThis.__sa_mp = (globalThis.__sa_mp || { next: 1, items: {}, bufs: {} });
                \\  const it = globalThis.__sa_mp.items[Number(handle)];
                \\  if (!it || it.kind !== "builder") return 2;
                \\  const value = "multipart/form-data; boundary=" + it.boundary;
                \\  const enc = new globalThis.TextEncoder();
                \\  const bytes = enc.encode(value);
                \\  __sa_store_i64(out_len, BigInt(bytes.length));
                \\  if (__sa_num(cap) < bytes.length) return 9;
                \\  __sa_u8.set(bytes, __sa_addr(out));
                \\  return 0;
                \\}
                \\
            );
            return;
        }
        if (std.mem.eql(u8, fsig.name, "sa_std_multipart_builder_finish")) {
            try writer.writeAll(
                \\function sa_std_multipart_builder_finish(handle, out_handle) {
                \\  globalThis.__sa_mp = (globalThis.__sa_mp || { next: 1, items: {}, bufs: {} });
                \\  const it = globalThis.__sa_mp.items[Number(handle)];
                \\  if (!it || it.kind !== "builder") return 2;
                \\  const enc = new globalThis.TextEncoder();
                \\  const chunks = [];
                \\  let first = true;
                \\  for (const item of it.list) {
                \\    if (!first) chunks.push(enc.encode("\r\n"));
                \\    first = false;
                \\    chunks.push(enc.encode("--" + it.boundary + "\r\nContent-Disposition: form-data; name=\""));
                \\    chunks.push(item.name);
                \\    if (item.filename !== null) {
                \\      chunks.push(enc.encode("\"; filename=\""));
                \\      chunks.push(item.filename);
                \\    }
                \\    chunks.push(enc.encode("\""));
                \\    if (item.contentType !== null) {
                \\      chunks.push(enc.encode("\r\nContent-Type: "));
                \\      chunks.push(item.contentType);
                \\    }
                \\    chunks.push(enc.encode("\r\n\r\n"));
                \\    chunks.push(item.data);
                \\  }
                \\  chunks.push(enc.encode("\r\n--" + it.boundary + "--\r\n"));
                \\  let total = 0;
                \\  for (const c of chunks) total += c.length;
                \\  const bytes = new Uint8Array(total);
                \\  let off = 0;
                \\  for (const c of chunks) { bytes.set(c, off); off += c.length; }
                \\  const id = globalThis.__sa_mp.next++;
                \\  globalThis.__sa_mp.bufs[id] = { bytes: bytes, addr: 0 };
                \\  __sa_store_i64(out_handle, BigInt(id));
                \\  return 0;
                \\}
                \\
            );
            return;
        }
        if (std.mem.eql(u8, fsig.name, "sa_std_multipart_buffer_data")) {
            try writer.writeAll(
                \\function sa_std_multipart_buffer_data(buffer) {
                \\  globalThis.__sa_mp = (globalThis.__sa_mp || { next: 1, items: {}, bufs: {} });
                \\  const rec = globalThis.__sa_mp.bufs[Number(buffer)];
                \\  if (!rec) return 0;
                \\  if (!rec.addr) { rec.addr = __sa_alloc(rec.bytes.length); __sa_u8.set(rec.bytes, rec.addr); }
                \\  return rec.addr;
                \\}
                \\
            );
            return;
        }
        if (std.mem.eql(u8, fsig.name, "sa_std_multipart_buffer_len")) {
            try writer.writeAll(
                \\function sa_std_multipart_buffer_len(buffer) {
                \\  globalThis.__sa_mp = (globalThis.__sa_mp || { next: 1, items: {}, bufs: {} });
                \\  const rec = globalThis.__sa_mp.bufs[Number(buffer)];
                \\  return rec ? BigInt(rec.bytes.length) : BigInt(0);
                \\}
                \\
            );
            return;
        }
        if (std.mem.eql(u8, fsig.name, "sa_std_multipart_buffer_free")) {
            try writer.writeAll(
                \\function sa_std_multipart_buffer_free(buffer) {
                \\  globalThis.__sa_mp = (globalThis.__sa_mp || { next: 1, items: {}, bufs: {} });
                \\  const rec = globalThis.__sa_mp.bufs[Number(buffer)];
                \\  if (rec) { if (rec.addr) __sa_free(rec.addr); delete globalThis.__sa_mp.bufs[Number(buffer)]; }
                \\  return 0;
                \\}
                \\
            );
            return;
        }
        if (std.mem.eql(u8, fsig.name, "sa_std_ssh_supported")) {
            try writer.writeAll(
                \\function sa_std_ssh_supported(out_flags) {
                \\  __sa_store_i64(out_flags, BigInt(0));
                \\  return 0;
                \\}
                \\
            );
            return;
        }
        if (std.mem.eql(u8, fsig.name, "sa_std_ssh_buffer_data")) {
            try writer.writeAll("function sa_std_ssh_buffer_data(buffer) { return 0; }\n");
            return;
        }
        if (std.mem.eql(u8, fsig.name, "sa_std_ssh_buffer_len")) {
            try writer.writeAll("function sa_std_ssh_buffer_len(buffer) { return BigInt(0); }\n");
            return;
        }
        if (std.mem.eql(u8, fsig.name, "sa_std_ssh_buffer_free")) {
            try writer.writeAll("function sa_std_ssh_buffer_free() { return 8; }\n");
            return;
        }
        if (std.mem.eql(u8, fsig.name, "sa_std_ssh_client_connect")) {
            try writer.writeAll("function sa_std_ssh_client_connect(host, host_len, port, out_session) { return 8; }\n");
            return;
        }
        if (std.mem.eql(u8, fsig.name, "sa_std_ssh_hostkey_fingerprint")) {
            try writer.writeAll("function sa_std_ssh_hostkey_fingerprint() { return 8; }\n");
            return;
        }
        if (std.mem.eql(u8, fsig.name, "sa_std_ssh_auth_password")) {
            try writer.writeAll("function sa_std_ssh_auth_password() { return 8; }\n");
            return;
        }
        if (std.mem.eql(u8, fsig.name, "sa_std_ssh_auth_keyfile")) {
            try writer.writeAll("function sa_std_ssh_auth_keyfile() { return 8; }\n");
            return;
        }
        if (std.mem.eql(u8, fsig.name, "sa_std_ssh_exec")) {
            try writer.writeAll("function sa_std_ssh_exec(session, command, command_len, out_stdout, out_stderr, out_exit) { return 8; }\n");
            return;
        }
        if (std.mem.eql(u8, fsig.name, "sa_std_ssh_sftp_read")) {
            try writer.writeAll("function sa_std_ssh_sftp_read() { return 8; }\n");
            return;
        }
        if (std.mem.eql(u8, fsig.name, "sa_std_ssh_sftp_write")) {
            try writer.writeAll("function sa_std_ssh_sftp_write() { return 8; }\n");
            return;
        }
        if (std.mem.eql(u8, fsig.name, "sa_std_ssh_sftp_stat")) {
            try writer.writeAll("function sa_std_ssh_sftp_stat() { return 8; }\n");
            return;
        }
        if (std.mem.eql(u8, fsig.name, "sa_std_ssh_session_close")) {
            try writer.writeAll("function sa_std_ssh_session_close() { return 8; }\n");
            return;
        }
        if (std.mem.eql(u8, fsig.name, "sa_std_ssh_server_listen")) {
            try writer.writeAll("function sa_std_ssh_server_listen() { return 8; }\n");
            return;
        }
        if (std.mem.eql(u8, fsig.name, "sa_std_ssh_server_accept")) {
            try writer.writeAll("function sa_std_ssh_server_accept() { return 8; }\n");
            return;
        }
        if (std.mem.eql(u8, fsig.name, "sa_std_ssh_server_auth_next")) {
            try writer.writeAll("function sa_std_ssh_server_auth_next() { return 8; }\n");
            return;
        }
        if (std.mem.eql(u8, fsig.name, "sa_std_ssh_server_auth_accept")) {
            try writer.writeAll("function sa_std_ssh_server_auth_accept() { return 8; }\n");
            return;
        }
        if (std.mem.eql(u8, fsig.name, "sa_std_ssh_server_auth_deny")) {
            try writer.writeAll("function sa_std_ssh_server_auth_deny() { return 8; }\n");
            return;
        }
        if (std.mem.eql(u8, fsig.name, "sa_std_ssh_server_channel_accept")) {
            try writer.writeAll("function sa_std_ssh_server_channel_accept() { return 8; }\n");
            return;
        }
        if (std.mem.eql(u8, fsig.name, "sa_std_ssh_server_channel_exec")) {
            try writer.writeAll("function sa_std_ssh_server_channel_exec() { return 8; }\n");
            return;
        }
        if (std.mem.eql(u8, fsig.name, "sa_std_ssh_channel_write")) {
            try writer.writeAll("function sa_std_ssh_channel_write() { return 8; }\n");
            return;
        }
        if (std.mem.eql(u8, fsig.name, "sa_std_ssh_channel_read")) {
            try writer.writeAll("function sa_std_ssh_channel_read() { return 8; }\n");
            return;
        }
        if (std.mem.eql(u8, fsig.name, "sa_std_ssh_channel_send_exit")) {
            try writer.writeAll("function sa_std_ssh_channel_send_exit() { return 8; }\n");
            return;
        }
        if (std.mem.eql(u8, fsig.name, "sa_std_ssh_channel_close")) {
            try writer.writeAll("function sa_std_ssh_channel_close() { return 8; }\n");
            return;
        }
        if (std.mem.eql(u8, fsig.name, "sa_std_ssh_server_session_close")) {
            try writer.writeAll("function sa_std_ssh_server_session_close() { return 8; }\n");
            return;
        }
        if (std.mem.eql(u8, fsig.name, "sa_std_ssh_server_bind_close")) {
            try writer.writeAll("function sa_std_ssh_server_bind_close() { return 8; }\n");
            return;
        }
        if (std.mem.eql(u8, fsig.name, "sa_http_client_req_new_joined")) {
            try writer.writeAll(
                \\function sa_http_client_req_new_joined(client, method, target, target_len, path, path_len, preserve, out_req) {
                \\  globalThis.__sa_http_c = (globalThis.__sa_http_c || {});
                \\  globalThis.__sa_http_req = (globalThis.__sa_http_req || {});
                \\  globalThis.__sa_http_resp = (globalThis.__sa_http_resp || {});
                \\  globalThis.__sa_http_rd = (globalThis.__sa_http_rd || {});
                \\  globalThis.__sa_http_op = (globalThis.__sa_http_op || {});
                \\  globalThis.__sa_http_ws = (globalThis.__sa_http_ws || {});
                \\  globalThis.__sa_http_sse = (globalThis.__sa_http_sse || {});
                \\  const dec = new globalThis.TextDecoder();
                \\  const ta = __sa_addr(target), tn = __sa_num(target_len);
                \\  const pa = __sa_addr(path), pn = __sa_num(path_len);
                \\  const url = dec.decode(__sa_u8.slice(ta, ta + tn)) + dec.decode(__sa_u8.slice(pa, pa + pn));
                \\  const h = __sa_alloc(8);
                \\  globalThis.__sa_http_req[__sa_addr(h)] = { method: __sa_num(method), url: url, headers: {}, body: new Uint8Array(0) };
                \\  __sa_store_ptr(out_req, h);
                \\  return 0;
                \\}
                \\
            );
            return;
        }
        if (std.mem.eql(u8, fsig.name, "sa_http_client_req_add_openai_auth")) {
            try writer.writeAll(
                \\function sa_http_client_req_add_openai_auth(req, key, key_len) {
                \\  globalThis.__sa_http_c = (globalThis.__sa_http_c || {});
                \\  globalThis.__sa_http_req = (globalThis.__sa_http_req || {});
                \\  globalThis.__sa_http_resp = (globalThis.__sa_http_resp || {});
                \\  globalThis.__sa_http_rd = (globalThis.__sa_http_rd || {});
                \\  globalThis.__sa_http_op = (globalThis.__sa_http_op || {});
                \\  globalThis.__sa_http_ws = (globalThis.__sa_http_ws || {});
                \\  globalThis.__sa_http_sse = (globalThis.__sa_http_sse || {});
                \\  const r = globalThis.__sa_http_req[__sa_addr(req)];
                \\  if (!r) return 2;
                \\  const dec = new globalThis.TextDecoder();
                \\  const ka = __sa_addr(key), kn = __sa_num(key_len);
                \\  r.headers["authorization"] = "Bearer " + dec.decode(__sa_u8.slice(ka, ka + kn));
                \\  return 0;
                \\}
                \\
            );
            return;
        }
        if (std.mem.eql(u8, fsig.name, "sa_http_client_resp_get_header")) {
            try writer.writeAll(
                \\function sa_http_client_resp_get_header(resp, key, key_len, out_val, out_len) {
                \\  globalThis.__sa_http_c = (globalThis.__sa_http_c || {});
                \\  globalThis.__sa_http_req = (globalThis.__sa_http_req || {});
                \\  globalThis.__sa_http_resp = (globalThis.__sa_http_resp || {});
                \\  globalThis.__sa_http_rd = (globalThis.__sa_http_rd || {});
                \\  globalThis.__sa_http_op = (globalThis.__sa_http_op || {});
                \\  globalThis.__sa_http_ws = (globalThis.__sa_http_ws || {});
                \\  globalThis.__sa_http_sse = (globalThis.__sa_http_sse || {});
                \\  const r = globalThis.__sa_http_resp[__sa_addr(resp)];
                \\  if (!r) return 2;
                \\  const dec = new globalThis.TextDecoder();
                \\  const ka = __sa_addr(key), kn = __sa_num(key_len);
                \\  const want = dec.decode(__sa_u8.slice(ka, ka + kn)).toLowerCase();
                \\  const headers = r.headers || {};
                \\  for (const k of Object.keys(headers)) {
                \\    if (k.toLowerCase() === want) {
                \\      const enc = new globalThis.TextEncoder();
                \\      const bytes = enc.encode(headers[k]);
                \\      const p = __sa_alloc(bytes.length);
                \\      __sa_u8.set(bytes, p);
                \\      __sa_store_ptr(out_val, p);
                \\      __sa_store_i64(out_len, BigInt(bytes.length));
                \\      return 0;
                \\    }
                \\  }
                \\  return 2;
                \\}
                \\
            );
            return;
        }
        if (std.mem.eql(u8, fsig.name, "sa_http_client_resp_body_slice")) {
            try writer.writeAll(
                \\function sa_http_client_resp_body_slice(resp, out_body, out_len) {
                \\  globalThis.__sa_http_c = (globalThis.__sa_http_c || {});
                \\  globalThis.__sa_http_req = (globalThis.__sa_http_req || {});
                \\  globalThis.__sa_http_resp = (globalThis.__sa_http_resp || {});
                \\  globalThis.__sa_http_rd = (globalThis.__sa_http_rd || {});
                \\  globalThis.__sa_http_op = (globalThis.__sa_http_op || {});
                \\  globalThis.__sa_http_ws = (globalThis.__sa_http_ws || {});
                \\  globalThis.__sa_http_sse = (globalThis.__sa_http_sse || {});
                \\  const r = globalThis.__sa_http_resp[__sa_addr(resp)];
                \\  if (!r) return 2;
                \\  if (!r.body_addr) { r.body_addr = __sa_alloc(r.body.length); __sa_u8.set(r.body, r.body_addr); }
                \\  __sa_store_ptr(out_body, r.body_addr);
                \\  __sa_store_i64(out_len, BigInt(r.body.length));
                \\  return 0;
                \\}
                \\
            );
            return;
        }
        if (std.mem.eql(u8, fsig.name, "sa_http_client_resp_body_ptr")) {
            try writer.writeAll(
                \\function sa_http_client_resp_body_ptr(resp) {
                \\  globalThis.__sa_http_c = (globalThis.__sa_http_c || {});
                \\  globalThis.__sa_http_req = (globalThis.__sa_http_req || {});
                \\  globalThis.__sa_http_resp = (globalThis.__sa_http_resp || {});
                \\  globalThis.__sa_http_rd = (globalThis.__sa_http_rd || {});
                \\  globalThis.__sa_http_op = (globalThis.__sa_http_op || {});
                \\  globalThis.__sa_http_ws = (globalThis.__sa_http_ws || {});
                \\  globalThis.__sa_http_sse = (globalThis.__sa_http_sse || {});
                \\  const r = globalThis.__sa_http_resp[__sa_addr(resp)];
                \\  if (!r) return 0;
                \\  if (!r.body_addr) { r.body_addr = __sa_alloc(r.body.length); __sa_u8.set(r.body, r.body_addr); }
                \\  return r.body_addr;
                \\}
                \\
            );
            return;
        }
        if (std.mem.eql(u8, fsig.name, "sa_http_client_resp_body_len")) {
            try writer.writeAll(
                \\function sa_http_client_resp_body_len(resp) {
                \\  globalThis.__sa_http_c = (globalThis.__sa_http_c || {});
                \\  globalThis.__sa_http_req = (globalThis.__sa_http_req || {});
                \\  globalThis.__sa_http_resp = (globalThis.__sa_http_resp || {});
                \\  globalThis.__sa_http_rd = (globalThis.__sa_http_rd || {});
                \\  globalThis.__sa_http_op = (globalThis.__sa_http_op || {});
                \\  globalThis.__sa_http_ws = (globalThis.__sa_http_ws || {});
                \\  globalThis.__sa_http_sse = (globalThis.__sa_http_sse || {});
                \\  const r = globalThis.__sa_http_resp[__sa_addr(resp)];
                \\  return r ? BigInt(r.body.length) : BigInt(0);
                \\}
                \\
            );
            return;
        }
        if (std.mem.eql(u8, fsig.name, "sa_http_client_req_send_async")) {
            try writer.writeAll(
                \\function sa_http_client_req_send_async(req, out_op) {
                \\  globalThis.__sa_http_c = (globalThis.__sa_http_c || {});
                \\  globalThis.__sa_http_req = (globalThis.__sa_http_req || {});
                \\  globalThis.__sa_http_resp = (globalThis.__sa_http_resp || {});
                \\  globalThis.__sa_http_rd = (globalThis.__sa_http_rd || {});
                \\  globalThis.__sa_http_op = (globalThis.__sa_http_op || {});
                \\  globalThis.__sa_http_ws = (globalThis.__sa_http_ws || {});
                \\  globalThis.__sa_http_sse = (globalThis.__sa_http_sse || {});
                \\  const r = globalThis.__sa_http_req[__sa_addr(req)];
                \\  if (!r) return 2;
                \\  const h = __sa_alloc(8);
                \\  globalThis.__sa_http_op[__sa_addr(h)] = { resp: { status: 200, body: r.body.slice(), headers: Object.assign({}, r.headers) }, taken: false };
                \\  __sa_store_ptr(out_op, h);
                \\  return 0;
                \\}
                \\
            );
            return;
        }
        if (std.mem.eql(u8, fsig.name, "sa_http_client_async_poll")) {
            try writer.writeAll(
                \\function sa_http_client_async_poll(op, out_ready) {
                \\  globalThis.__sa_http_c = (globalThis.__sa_http_c || {});
                \\  globalThis.__sa_http_req = (globalThis.__sa_http_req || {});
                \\  globalThis.__sa_http_resp = (globalThis.__sa_http_resp || {});
                \\  globalThis.__sa_http_rd = (globalThis.__sa_http_rd || {});
                \\  globalThis.__sa_http_op = (globalThis.__sa_http_op || {});
                \\  globalThis.__sa_http_ws = (globalThis.__sa_http_ws || {});
                \\  globalThis.__sa_http_sse = (globalThis.__sa_http_sse || {});
                \\  const o = globalThis.__sa_http_op[__sa_addr(op)];
                \\  if (!o) return 2;
                \\  __sa_store_i64(out_ready, BigInt(1));
                \\  return 0;
                \\}
                \\
            );
            return;
        }
        if (std.mem.eql(u8, fsig.name, "sa_http_client_async_take_response")) {
            try writer.writeAll(
                \\function sa_http_client_async_take_response(op, out_resp) {
                \\  globalThis.__sa_http_c = (globalThis.__sa_http_c || {});
                \\  globalThis.__sa_http_req = (globalThis.__sa_http_req || {});
                \\  globalThis.__sa_http_resp = (globalThis.__sa_http_resp || {});
                \\  globalThis.__sa_http_rd = (globalThis.__sa_http_rd || {});
                \\  globalThis.__sa_http_op = (globalThis.__sa_http_op || {});
                \\  globalThis.__sa_http_ws = (globalThis.__sa_http_ws || {});
                \\  globalThis.__sa_http_sse = (globalThis.__sa_http_sse || {});
                \\  const o = globalThis.__sa_http_op[__sa_addr(op)];
                \\  if (!o || o.taken) return 2;
                \\  o.taken = true;
                \\  const h = __sa_alloc(8);
                \\  globalThis.__sa_http_resp[__sa_addr(h)] = o.resp;
                \\  __sa_store_ptr(out_resp, h);
                \\  return 0;
                \\}
                \\
            );
            return;
        }
        if (std.mem.eql(u8, fsig.name, "sa_http_client_async_free")) {
            try writer.writeAll(
                \\function sa_http_client_async_free(op) {
                \\  globalThis.__sa_http_c = (globalThis.__sa_http_c || {});
                \\  globalThis.__sa_http_req = (globalThis.__sa_http_req || {});
                \\  globalThis.__sa_http_resp = (globalThis.__sa_http_resp || {});
                \\  globalThis.__sa_http_rd = (globalThis.__sa_http_rd || {});
                \\  globalThis.__sa_http_op = (globalThis.__sa_http_op || {});
                \\  globalThis.__sa_http_ws = (globalThis.__sa_http_ws || {});
                \\  globalThis.__sa_http_sse = (globalThis.__sa_http_sse || {});
                \\  delete globalThis.__sa_http_op[__sa_addr(op)];
                \\  return 0;
                \\}
                \\
            );
            return;
        }
        if (std.mem.eql(u8, fsig.name, "sa_http_client_websocket_connect")) {
            try writer.writeAll(
                \\function sa_http_client_websocket_connect(client, url, url_len, out_ws) {
                \\  globalThis.__sa_http_c = (globalThis.__sa_http_c || {});
                \\  globalThis.__sa_http_req = (globalThis.__sa_http_req || {});
                \\  globalThis.__sa_http_resp = (globalThis.__sa_http_resp || {});
                \\  globalThis.__sa_http_rd = (globalThis.__sa_http_rd || {});
                \\  globalThis.__sa_http_op = (globalThis.__sa_http_op || {});
                \\  globalThis.__sa_http_ws = (globalThis.__sa_http_ws || {});
                \\  globalThis.__sa_http_sse = (globalThis.__sa_http_sse || {});
                \\  const h = __sa_alloc(8);
                \\  globalThis.__sa_http_ws[__sa_addr(h)] = { queue: [], stream: new Uint8Array(0), closed: false };
                \\  __sa_store_ptr(out_ws, h);
                \\  return 0;
                \\}
                \\
            );
            return;
        }
        if (std.mem.eql(u8, fsig.name, "sa_http_websocket_write")) {
            try writer.writeAll(
                \\function sa_http_websocket_write(ws, opcode, data, data_len) {
                \\  globalThis.__sa_http_c = (globalThis.__sa_http_c || {});
                \\  globalThis.__sa_http_req = (globalThis.__sa_http_req || {});
                \\  globalThis.__sa_http_resp = (globalThis.__sa_http_resp || {});
                \\  globalThis.__sa_http_rd = (globalThis.__sa_http_rd || {});
                \\  globalThis.__sa_http_op = (globalThis.__sa_http_op || {});
                \\  globalThis.__sa_http_ws = (globalThis.__sa_http_ws || {});
                \\  globalThis.__sa_http_sse = (globalThis.__sa_http_sse || {});
                \\  const w = globalThis.__sa_http_ws[__sa_addr(ws)];
                \\  if (!w) return 2;
                \\  const a = __sa_addr(data), n = __sa_num(data_len);
                \\  w.queue.push({ opcode: __sa_num(opcode), bytes: __sa_u8.slice(a, a + n) });
                \\  return 0;
                \\}
                \\
            );
            return;
        }
        if (std.mem.eql(u8, fsig.name, "sa_http_websocket_read")) {
            try writer.writeAll(
                \\function sa_http_websocket_read(ws, max_len, out_opcode, out_ptr, out_len) {
                \\  globalThis.__sa_http_c = (globalThis.__sa_http_c || {});
                \\  globalThis.__sa_http_req = (globalThis.__sa_http_req || {});
                \\  globalThis.__sa_http_resp = (globalThis.__sa_http_resp || {});
                \\  globalThis.__sa_http_rd = (globalThis.__sa_http_rd || {});
                \\  globalThis.__sa_http_op = (globalThis.__sa_http_op || {});
                \\  globalThis.__sa_http_ws = (globalThis.__sa_http_ws || {});
                \\  globalThis.__sa_http_sse = (globalThis.__sa_http_sse || {});
                \\  const w = globalThis.__sa_http_ws[__sa_addr(ws)];
                \\  if (!w) return 2;
                \\  const msg = w.queue.shift();
                \\  if (!msg) { __sa_store_i64(out_len, BigInt(0)); return 2; }
                \\  const p = __sa_alloc(msg.bytes.length);
                \\  __sa_u8.set(msg.bytes, p);
                \\  __sa_store_i64(out_opcode, BigInt(msg.opcode));
                \\  __sa_store_ptr(out_ptr, p);
                \\  __sa_store_i64(out_len, BigInt(msg.bytes.length));
                \\  return 0;
                \\}
                \\
            );
            return;
        }
        if (std.mem.eql(u8, fsig.name, "sa_http_websocket_free")) {
            try writer.writeAll(
                \\function sa_http_websocket_free(ws) {
                \\  globalThis.__sa_http_c = (globalThis.__sa_http_c || {});
                \\  globalThis.__sa_http_req = (globalThis.__sa_http_req || {});
                \\  globalThis.__sa_http_resp = (globalThis.__sa_http_resp || {});
                \\  globalThis.__sa_http_rd = (globalThis.__sa_http_rd || {});
                \\  globalThis.__sa_http_op = (globalThis.__sa_http_op || {});
                \\  globalThis.__sa_http_ws = (globalThis.__sa_http_ws || {});
                \\  globalThis.__sa_http_sse = (globalThis.__sa_http_sse || {});
                \\  delete globalThis.__sa_http_ws[__sa_addr(ws)];
                \\  return 0;
                \\}
                \\
            );
            return;
        }
        if (std.mem.eql(u8, fsig.name, "sa_http_client_sse_post")) {
            try writer.writeAll(
                \\function sa_http_client_sse_post(url, url_len, body, body_len, key, key_len, out_handle) {
                \\  globalThis.__sa_http_c = (globalThis.__sa_http_c || {});
                \\  globalThis.__sa_http_req = (globalThis.__sa_http_req || {});
                \\  globalThis.__sa_http_resp = (globalThis.__sa_http_resp || {});
                \\  globalThis.__sa_http_rd = (globalThis.__sa_http_rd || {});
                \\  globalThis.__sa_http_op = (globalThis.__sa_http_op || {});
                \\  globalThis.__sa_http_ws = (globalThis.__sa_http_ws || {});
                \\  globalThis.__sa_http_sse = (globalThis.__sa_http_sse || {});
                \\  const a = __sa_addr(body), n = __sa_num(body_len);
                \\  const h = __sa_alloc(8);
                \\  globalThis.__sa_http_sse[__sa_addr(h)] = { body: __sa_u8.slice(a, a + n), off: 0, status: 200 };
                \\  __sa_store_ptr(out_handle, h);
                \\  return 0;
                \\}
                \\
            );
            return;
        }
        if (std.mem.eql(u8, fsig.name, "sa_http_client_sse_read")) {
            try writer.writeAll(
                \\function sa_http_client_sse_read(handle, buf, buf_cap, out_len) {
                \\  globalThis.__sa_http_c = (globalThis.__sa_http_c || {});
                \\  globalThis.__sa_http_req = (globalThis.__sa_http_req || {});
                \\  globalThis.__sa_http_resp = (globalThis.__sa_http_resp || {});
                \\  globalThis.__sa_http_rd = (globalThis.__sa_http_rd || {});
                \\  globalThis.__sa_http_op = (globalThis.__sa_http_op || {});
                \\  globalThis.__sa_http_ws = (globalThis.__sa_http_ws || {});
                \\  globalThis.__sa_http_sse = (globalThis.__sa_http_sse || {});
                \\  const rec = globalThis.__sa_http_sse[__sa_addr(handle)];
                \\  if (!rec) return 2;
                \\  const cap = __sa_num(buf_cap);
                \\  const n = Math.min(cap, rec.body.length - rec.off);
                \\  __sa_u8.set(rec.body.subarray(rec.off, rec.off + n), __sa_addr(buf));
                \\  rec.off += n;
                \\  __sa_store_i64(out_len, BigInt(n));
                \\  return 0;
                \\}
                \\
            );
            return;
        }
        if (std.mem.eql(u8, fsig.name, "sa_http_client_sse_poll")) {
            try writer.writeAll(
                \\function sa_http_client_sse_poll(handle, out_done) {
                \\  globalThis.__sa_http_c = (globalThis.__sa_http_c || {});
                \\  globalThis.__sa_http_req = (globalThis.__sa_http_req || {});
                \\  globalThis.__sa_http_resp = (globalThis.__sa_http_resp || {});
                \\  globalThis.__sa_http_rd = (globalThis.__sa_http_rd || {});
                \\  globalThis.__sa_http_op = (globalThis.__sa_http_op || {});
                \\  globalThis.__sa_http_ws = (globalThis.__sa_http_ws || {});
                \\  globalThis.__sa_http_sse = (globalThis.__sa_http_sse || {});
                \\  const rec = globalThis.__sa_http_sse[__sa_addr(handle)];
                \\  if (!rec) return 2;
                \\  __sa_store_i64(out_done, BigInt(rec.off >= rec.body.length ? 1 : 0));
                \\  return 0;
                \\}
                \\
            );
            return;
        }
        if (std.mem.eql(u8, fsig.name, "sa_http_client_sse_status")) {
            try writer.writeAll(
                \\function sa_http_client_sse_status(handle) {
                \\  globalThis.__sa_http_c = (globalThis.__sa_http_c || {});
                \\  globalThis.__sa_http_req = (globalThis.__sa_http_req || {});
                \\  globalThis.__sa_http_resp = (globalThis.__sa_http_resp || {});
                \\  globalThis.__sa_http_rd = (globalThis.__sa_http_rd || {});
                \\  globalThis.__sa_http_op = (globalThis.__sa_http_op || {});
                \\  globalThis.__sa_http_ws = (globalThis.__sa_http_ws || {});
                \\  globalThis.__sa_http_sse = (globalThis.__sa_http_sse || {});
                \\  const rec = globalThis.__sa_http_sse[__sa_addr(handle)];
                \\  return rec ? rec.status : 0;
                \\}
                \\
            );
            return;
        }
        if (std.mem.eql(u8, fsig.name, "sa_http_client_sse_free")) {
            try writer.writeAll(
                \\function sa_http_client_sse_free(handle) {
                \\  globalThis.__sa_http_c = (globalThis.__sa_http_c || {});
                \\  globalThis.__sa_http_req = (globalThis.__sa_http_req || {});
                \\  globalThis.__sa_http_resp = (globalThis.__sa_http_resp || {});
                \\  globalThis.__sa_http_rd = (globalThis.__sa_http_rd || {});
                \\  globalThis.__sa_http_op = (globalThis.__sa_http_op || {});
                \\  globalThis.__sa_http_ws = (globalThis.__sa_http_ws || {});
                \\  globalThis.__sa_http_sse = (globalThis.__sa_http_sse || {});
                \\  delete globalThis.__sa_http_sse[__sa_addr(handle)];
                \\  return 0;
                \\}
                \\
            );
            return;
        }
        if (std.mem.eql(u8, fsig.name, "sa_http_client_sse_turn")) {
            try writer.writeAll(
                \\function sa_http_client_sse_turn(url, url_len, body, body_len, key, key_len, api_mode, out_text, out_text_len, out_calls, out_calls_len) {
                \\  globalThis.__sa_http_c = (globalThis.__sa_http_c || {});
                \\  globalThis.__sa_http_req = (globalThis.__sa_http_req || {});
                \\  globalThis.__sa_http_resp = (globalThis.__sa_http_resp || {});
                \\  globalThis.__sa_http_rd = (globalThis.__sa_http_rd || {});
                \\  globalThis.__sa_http_op = (globalThis.__sa_http_op || {});
                \\  globalThis.__sa_http_ws = (globalThis.__sa_http_ws || {});
                \\  globalThis.__sa_http_sse = (globalThis.__sa_http_sse || {});
                \\  const a = __sa_addr(body), n = __sa_num(body_len);
                \\  const text = __sa_u8.slice(a, a + n);
                \\  const tp = __sa_alloc(text.length);
                \\  __sa_u8.set(text, tp);
                \\  const cp = __sa_alloc(1);
                \\  __sa_store_ptr(out_text, tp);
                \\  __sa_store_i64(out_text_len, BigInt(text.length));
                \\  __sa_store_ptr(out_calls, cp);
                \\  __sa_store_i64(out_calls_len, BigInt(0));
                \\  return 0;
                \\}
                \\
            );
            return;
        }
        if (std.mem.eql(u8, fsig.name, "sa_http_client_sse_turn_free")) {
            try writer.writeAll("function sa_http_client_sse_turn_free(buf, len) { }\n");
            return;
        }
        if (std.mem.eql(u8, fsig.name, "sa_http_client_new_v2")) {
            try writer.writeAll(
                \\function sa_http_client_new_v2(use_tls, ca_bundle_path, ca_bundle_path_len, out_client) {
                \\  globalThis.__sa_http_c = (globalThis.__sa_http_c || {});
                \\  globalThis.__sa_http_req = (globalThis.__sa_http_req || {});
                \\  globalThis.__sa_http_resp = (globalThis.__sa_http_resp || {});
                \\  globalThis.__sa_http_rd = (globalThis.__sa_http_rd || {});
                \\  globalThis.__sa_http_op = (globalThis.__sa_http_op || {});
                \\  globalThis.__sa_http_ws = (globalThis.__sa_http_ws || {});
                \\  globalThis.__sa_http_sse = (globalThis.__sa_http_sse || {});
                \\  const h = __sa_alloc(8);
                \\  globalThis.__sa_http_c[__sa_addr(h)] = { tls: __sa_num(use_tls), v2: true };
                \\  __sa_store_ptr(out_client, h);
                \\  return 0;
                \\}
                \\
            );
            return;
        }
        if (std.mem.eql(u8, fsig.name, "sa_http_client_req_new_v2")) {
            try writer.writeAll(
                \\function sa_http_client_req_new_v2(client, method, url, url_len, out_req) {
                \\  globalThis.__sa_http_c = (globalThis.__sa_http_c || {});
                \\  globalThis.__sa_http_req = (globalThis.__sa_http_req || {});
                \\  globalThis.__sa_http_resp = (globalThis.__sa_http_resp || {});
                \\  globalThis.__sa_http_rd = (globalThis.__sa_http_rd || {});
                \\  globalThis.__sa_http_op = (globalThis.__sa_http_op || {});
                \\  globalThis.__sa_http_ws = (globalThis.__sa_http_ws || {});
                \\  globalThis.__sa_http_sse = (globalThis.__sa_http_sse || {});
                \\  const dec = new globalThis.TextDecoder();
                \\  const a = __sa_addr(url), n = __sa_num(url_len);
                \\  const h = __sa_alloc(8);
                \\  globalThis.__sa_http_req[__sa_addr(h)] = { method: __sa_num(method), url: dec.decode(__sa_u8.slice(a, a + n)), headers: {}, body: new Uint8Array(0), timeout: 0, max: 0 };
                \\  __sa_store_ptr(out_req, h);
                \\  return 0;
                \\}
                \\
            );
            return;
        }
        if (std.mem.eql(u8, fsig.name, "sa_http_client_req_add_header_v2")) {
            try writer.writeAll(
                \\function sa_http_client_req_add_header_v2(req, key, key_len, value, value_len) {
                \\  globalThis.__sa_http_c = (globalThis.__sa_http_c || {});
                \\  globalThis.__sa_http_req = (globalThis.__sa_http_req || {});
                \\  globalThis.__sa_http_resp = (globalThis.__sa_http_resp || {});
                \\  globalThis.__sa_http_rd = (globalThis.__sa_http_rd || {});
                \\  globalThis.__sa_http_op = (globalThis.__sa_http_op || {});
                \\  globalThis.__sa_http_ws = (globalThis.__sa_http_ws || {});
                \\  globalThis.__sa_http_sse = (globalThis.__sa_http_sse || {});
                \\  const r = globalThis.__sa_http_req[__sa_addr(req)];
                \\  if (!r) return 5;
                \\  const dec = new globalThis.TextDecoder();
                \\  const ka = __sa_addr(key), kn = __sa_num(key_len);
                \\  const va = __sa_addr(value), vn = __sa_num(value_len);
                \\  r.headers[dec.decode(__sa_u8.slice(ka, ka + kn))] = dec.decode(__sa_u8.slice(va, va + vn));
                \\  return 0;
                \\}
                \\
            );
            return;
        }
        if (std.mem.eql(u8, fsig.name, "sa_http_client_req_set_body_v2")) {
            try writer.writeAll(
                \\function sa_http_client_req_set_body_v2(req, body, body_len) {
                \\  globalThis.__sa_http_c = (globalThis.__sa_http_c || {});
                \\  globalThis.__sa_http_req = (globalThis.__sa_http_req || {});
                \\  globalThis.__sa_http_resp = (globalThis.__sa_http_resp || {});
                \\  globalThis.__sa_http_rd = (globalThis.__sa_http_rd || {});
                \\  globalThis.__sa_http_op = (globalThis.__sa_http_op || {});
                \\  globalThis.__sa_http_ws = (globalThis.__sa_http_ws || {});
                \\  globalThis.__sa_http_sse = (globalThis.__sa_http_sse || {});
                \\  const r = globalThis.__sa_http_req[__sa_addr(req)];
                \\  if (!r) return 5;
                \\  const a = __sa_addr(body), n = __sa_num(body_len);
                \\  r.body = __sa_u8.slice(a, a + n);
                \\  return 0;
                \\}
                \\
            );
            return;
        }
        if (std.mem.eql(u8, fsig.name, "sa_http_client_req_set_timeout_v2")) {
            try writer.writeAll(
                \\function sa_http_client_req_set_timeout_v2(req, timeout_ms) {
                \\  globalThis.__sa_http_c = (globalThis.__sa_http_c || {});
                \\  globalThis.__sa_http_req = (globalThis.__sa_http_req || {});
                \\  globalThis.__sa_http_resp = (globalThis.__sa_http_resp || {});
                \\  globalThis.__sa_http_rd = (globalThis.__sa_http_rd || {});
                \\  globalThis.__sa_http_op = (globalThis.__sa_http_op || {});
                \\  globalThis.__sa_http_ws = (globalThis.__sa_http_ws || {});
                \\  globalThis.__sa_http_sse = (globalThis.__sa_http_sse || {});
                \\  const r = globalThis.__sa_http_req[__sa_addr(req)];
                \\  if (!r) return 5;
                \\  r.timeout = __sa_num(timeout_ms);
                \\  return 0;
                \\}
                \\
            );
            return;
        }
        if (std.mem.eql(u8, fsig.name, "sa_http_client_req_set_max_response_bytes_v2")) {
            try writer.writeAll(
                \\function sa_http_client_req_set_max_response_bytes_v2(req, max_bytes) {
                \\  globalThis.__sa_http_c = (globalThis.__sa_http_c || {});
                \\  globalThis.__sa_http_req = (globalThis.__sa_http_req || {});
                \\  globalThis.__sa_http_resp = (globalThis.__sa_http_resp || {});
                \\  globalThis.__sa_http_rd = (globalThis.__sa_http_rd || {});
                \\  globalThis.__sa_http_op = (globalThis.__sa_http_op || {});
                \\  globalThis.__sa_http_ws = (globalThis.__sa_http_ws || {});
                \\  globalThis.__sa_http_sse = (globalThis.__sa_http_sse || {});
                \\  const r = globalThis.__sa_http_req[__sa_addr(req)];
                \\  if (!r) return 5;
                \\  r.max = __sa_num(max_bytes);
                \\  return 0;
                \\}
                \\
            );
            return;
        }
        if (std.mem.eql(u8, fsig.name, "sa_http_client_req_send_v2")) {
            try writer.writeAll(
                \\function sa_http_client_req_send_v2(req, out_resp) {
                \\  globalThis.__sa_http_c = (globalThis.__sa_http_c || {});
                \\  globalThis.__sa_http_req = (globalThis.__sa_http_req || {});
                \\  globalThis.__sa_http_resp = (globalThis.__sa_http_resp || {});
                \\  globalThis.__sa_http_rd = (globalThis.__sa_http_rd || {});
                \\  globalThis.__sa_http_op = (globalThis.__sa_http_op || {});
                \\  globalThis.__sa_http_ws = (globalThis.__sa_http_ws || {});
                \\  globalThis.__sa_http_sse = (globalThis.__sa_http_sse || {});
                \\  const r = globalThis.__sa_http_req[__sa_addr(req)];
                \\  if (!r) return 5;
                \\  if (r.max && r.body.length > r.max) return 4;
                \\  const resp = { status: 200, body: r.body.slice(), headers: Object.assign({}, r.headers) };
                \\  const h = __sa_alloc(8);
                \\  globalThis.__sa_http_resp[__sa_addr(h)] = resp;
                \\  __sa_store_ptr(out_resp, h);
                \\  return 0;
                \\}
                \\
            );
            return;
        }
        if (std.mem.eql(u8, fsig.name, "sa_http_client_req_send_async_v2")) {
            try writer.writeAll(
                \\function sa_http_client_req_send_async_v2(req, out_op) {
                \\  globalThis.__sa_http_c = (globalThis.__sa_http_c || {});
                \\  globalThis.__sa_http_req = (globalThis.__sa_http_req || {});
                \\  globalThis.__sa_http_resp = (globalThis.__sa_http_resp || {});
                \\  globalThis.__sa_http_rd = (globalThis.__sa_http_rd || {});
                \\  globalThis.__sa_http_op = (globalThis.__sa_http_op || {});
                \\  globalThis.__sa_http_ws = (globalThis.__sa_http_ws || {});
                \\  globalThis.__sa_http_sse = (globalThis.__sa_http_sse || {});
                \\  const r = globalThis.__sa_http_req[__sa_addr(req)];
                \\  if (!r) return 5;
                \\  if (r.max && r.body.length > r.max) return 4;
                \\  const resp = { status: 200, body: r.body.slice(), headers: Object.assign({}, r.headers) };
                \\  const h = __sa_alloc(8);
                \\  globalThis.__sa_http_op[__sa_addr(h)] = { resp: resp, taken: false, v2: true };
                \\  __sa_store_ptr(out_op, h);
                \\  return 0;
                \\}
                \\
            );
            return;
        }
        if (std.mem.eql(u8, fsig.name, "sa_http_client_async_poll_v2")) {
            try writer.writeAll(
                \\function sa_http_client_async_poll_v2(op, timeout_ms, out_ready) {
                \\  globalThis.__sa_http_c = (globalThis.__sa_http_c || {});
                \\  globalThis.__sa_http_req = (globalThis.__sa_http_req || {});
                \\  globalThis.__sa_http_resp = (globalThis.__sa_http_resp || {});
                \\  globalThis.__sa_http_rd = (globalThis.__sa_http_rd || {});
                \\  globalThis.__sa_http_op = (globalThis.__sa_http_op || {});
                \\  globalThis.__sa_http_ws = (globalThis.__sa_http_ws || {});
                \\  globalThis.__sa_http_sse = (globalThis.__sa_http_sse || {});
                \\  const o = globalThis.__sa_http_op[__sa_addr(op)];
                \\  if (!o) return 5;
                \\  __sa_store_i64(out_ready, BigInt(o.cancelled ? 0 : 1));
                \\  return 0;
                \\}
                \\
            );
            return;
        }
        if (std.mem.eql(u8, fsig.name, "sa_http_client_async_take_response_v2")) {
            try writer.writeAll(
                \\function sa_http_client_async_take_response_v2(op, out_resp) {
                \\  globalThis.__sa_http_c = (globalThis.__sa_http_c || {});
                \\  globalThis.__sa_http_req = (globalThis.__sa_http_req || {});
                \\  globalThis.__sa_http_resp = (globalThis.__sa_http_resp || {});
                \\  globalThis.__sa_http_rd = (globalThis.__sa_http_rd || {});
                \\  globalThis.__sa_http_op = (globalThis.__sa_http_op || {});
                \\  globalThis.__sa_http_ws = (globalThis.__sa_http_ws || {});
                \\  globalThis.__sa_http_sse = (globalThis.__sa_http_sse || {});
                \\  const o = globalThis.__sa_http_op[__sa_addr(op)];
                \\  if (!o || o.taken || o.cancelled) return 5;
                \\  o.taken = true;
                \\  const h = __sa_alloc(8);
                \\  globalThis.__sa_http_resp[__sa_addr(h)] = o.resp;
                \\  __sa_store_ptr(out_resp, h);
                \\  return 0;
                \\}
                \\
            );
            return;
        }
        if (std.mem.eql(u8, fsig.name, "sa_http_client_async_cancel_v2")) {
            try writer.writeAll(
                \\function sa_http_client_async_cancel_v2(op) {
                \\  globalThis.__sa_http_c = (globalThis.__sa_http_c || {});
                \\  globalThis.__sa_http_req = (globalThis.__sa_http_req || {});
                \\  globalThis.__sa_http_resp = (globalThis.__sa_http_resp || {});
                \\  globalThis.__sa_http_rd = (globalThis.__sa_http_rd || {});
                \\  globalThis.__sa_http_op = (globalThis.__sa_http_op || {});
                \\  globalThis.__sa_http_ws = (globalThis.__sa_http_ws || {});
                \\  globalThis.__sa_http_sse = (globalThis.__sa_http_sse || {});
                \\  const o = globalThis.__sa_http_op[__sa_addr(op)];
                \\  if (!o) return 5;
                \\  o.cancelled = true;
                \\  return 0;
                \\}
                \\
            );
            return;
        }
        if (std.mem.eql(u8, fsig.name, "sa_http_client_async_free_v2")) {
            try writer.writeAll(
                \\function sa_http_client_async_free_v2(op) {
                \\  globalThis.__sa_http_c = (globalThis.__sa_http_c || {});
                \\  globalThis.__sa_http_req = (globalThis.__sa_http_req || {});
                \\  globalThis.__sa_http_resp = (globalThis.__sa_http_resp || {});
                \\  globalThis.__sa_http_rd = (globalThis.__sa_http_rd || {});
                \\  globalThis.__sa_http_op = (globalThis.__sa_http_op || {});
                \\  globalThis.__sa_http_ws = (globalThis.__sa_http_ws || {});
                \\  globalThis.__sa_http_sse = (globalThis.__sa_http_sse || {});
                \\  delete globalThis.__sa_http_op[__sa_addr(op)];
                \\  return 0;
                \\}
                \\
            );
            return;
        }
        if (std.mem.eql(u8, fsig.name, "sa_http_client_websocket_connect_v2")) {
            try writer.writeAll(
                \\function sa_http_client_websocket_connect_v2(client, url, url_len, timeout_ms, out_ws) {
                \\  globalThis.__sa_http_c = (globalThis.__sa_http_c || {});
                \\  globalThis.__sa_http_req = (globalThis.__sa_http_req || {});
                \\  globalThis.__sa_http_resp = (globalThis.__sa_http_resp || {});
                \\  globalThis.__sa_http_rd = (globalThis.__sa_http_rd || {});
                \\  globalThis.__sa_http_op = (globalThis.__sa_http_op || {});
                \\  globalThis.__sa_http_ws = (globalThis.__sa_http_ws || {});
                \\  globalThis.__sa_http_sse = (globalThis.__sa_http_sse || {});
                \\  const h = __sa_alloc(8);
                \\  globalThis.__sa_http_ws[__sa_addr(h)] = { queue: [], stream: new Uint8Array(0), off: 0, closed: false };
                \\  __sa_store_ptr(out_ws, h);
                \\  return 0;
                \\}
                \\
            );
            return;
        }
        if (std.mem.eql(u8, fsig.name, "sa_http_client_websocket_connect_unix_v2")) {
            try writer.writeAll(
                \\function sa_http_client_websocket_connect_unix_v2(client, socket_path, socket_path_len, url, url_len, timeout_ms, out_ws) {
                \\  globalThis.__sa_http_c = (globalThis.__sa_http_c || {});
                \\  globalThis.__sa_http_req = (globalThis.__sa_http_req || {});
                \\  globalThis.__sa_http_resp = (globalThis.__sa_http_resp || {});
                \\  globalThis.__sa_http_rd = (globalThis.__sa_http_rd || {});
                \\  globalThis.__sa_http_op = (globalThis.__sa_http_op || {});
                \\  globalThis.__sa_http_ws = (globalThis.__sa_http_ws || {});
                \\  globalThis.__sa_http_sse = (globalThis.__sa_http_sse || {});
                \\  const h = __sa_alloc(8);
                \\  globalThis.__sa_http_ws[__sa_addr(h)] = { queue: [], stream: new Uint8Array(0), off: 0, closed: false };
                \\  __sa_store_ptr(out_ws, h);
                \\  return 0;
                \\}
                \\
            );
            return;
        }
        if (std.mem.eql(u8, fsig.name, "sa_http_client_req_websocket_connect_v2")) {
            try writer.writeAll(
                \\function sa_http_client_req_websocket_connect_v2(req, timeout_ms, out_ws) {
                \\  globalThis.__sa_http_c = (globalThis.__sa_http_c || {});
                \\  globalThis.__sa_http_req = (globalThis.__sa_http_req || {});
                \\  globalThis.__sa_http_resp = (globalThis.__sa_http_resp || {});
                \\  globalThis.__sa_http_rd = (globalThis.__sa_http_rd || {});
                \\  globalThis.__sa_http_op = (globalThis.__sa_http_op || {});
                \\  globalThis.__sa_http_ws = (globalThis.__sa_http_ws || {});
                \\  globalThis.__sa_http_sse = (globalThis.__sa_http_sse || {});
                \\  const h = __sa_alloc(8);
                \\  globalThis.__sa_http_ws[__sa_addr(h)] = { queue: [], stream: new Uint8Array(0), off: 0, closed: false };
                \\  __sa_store_ptr(out_ws, h);
                \\  return 0;
                \\}
                \\
            );
            return;
        }
        if (std.mem.eql(u8, fsig.name, "sa_http_client_req_websocket_connect_unix_v2")) {
            try writer.writeAll(
                \\function sa_http_client_req_websocket_connect_unix_v2(req, socket_path, socket_path_len, timeout_ms, out_ws) {
                \\  globalThis.__sa_http_c = (globalThis.__sa_http_c || {});
                \\  globalThis.__sa_http_req = (globalThis.__sa_http_req || {});
                \\  globalThis.__sa_http_resp = (globalThis.__sa_http_resp || {});
                \\  globalThis.__sa_http_rd = (globalThis.__sa_http_rd || {});
                \\  globalThis.__sa_http_op = (globalThis.__sa_http_op || {});
                \\  globalThis.__sa_http_ws = (globalThis.__sa_http_ws || {});
                \\  globalThis.__sa_http_sse = (globalThis.__sa_http_sse || {});
                \\  const h = __sa_alloc(8);
                \\  globalThis.__sa_http_ws[__sa_addr(h)] = { queue: [], stream: new Uint8Array(0), off: 0, closed: false };
                \\  __sa_store_ptr(out_ws, h);
                \\  return 0;
                \\}
                \\
            );
            return;
        }
        if (std.mem.eql(u8, fsig.name, "sa_http_websocket_poll_v2")) {
            try writer.writeAll(
                \\function sa_http_websocket_poll_v2(ws, interests, timeout_ms, out_events) {
                \\  globalThis.__sa_http_c = (globalThis.__sa_http_c || {});
                \\  globalThis.__sa_http_req = (globalThis.__sa_http_req || {});
                \\  globalThis.__sa_http_resp = (globalThis.__sa_http_resp || {});
                \\  globalThis.__sa_http_rd = (globalThis.__sa_http_rd || {});
                \\  globalThis.__sa_http_op = (globalThis.__sa_http_op || {});
                \\  globalThis.__sa_http_ws = (globalThis.__sa_http_ws || {});
                \\  globalThis.__sa_http_sse = (globalThis.__sa_http_sse || {});
                \\  const w = globalThis.__sa_http_ws[__sa_addr(ws)];
                \\  if (!w) return 5;
                \\  let ev = 2;
                \\  if (w.off < w.stream.length || w.queue.length) ev |= 1;
                \\  if (w.closed) ev |= 4;
                \\  __sa_store_i64(out_events, BigInt(ev));
                \\  return 0;
                \\}
                \\
            );
            return;
        }
        if (std.mem.eql(u8, fsig.name, "sa_http_websocket_write_v2")) {
            try writer.writeAll(
                \\function sa_http_websocket_write_v2(ws, opcode, data, data_len, out_written) {
                \\  globalThis.__sa_http_c = (globalThis.__sa_http_c || {});
                \\  globalThis.__sa_http_req = (globalThis.__sa_http_req || {});
                \\  globalThis.__sa_http_resp = (globalThis.__sa_http_resp || {});
                \\  globalThis.__sa_http_rd = (globalThis.__sa_http_rd || {});
                \\  globalThis.__sa_http_op = (globalThis.__sa_http_op || {});
                \\  globalThis.__sa_http_ws = (globalThis.__sa_http_ws || {});
                \\  globalThis.__sa_http_sse = (globalThis.__sa_http_sse || {});
                \\  const w = globalThis.__sa_http_ws[__sa_addr(ws)];
                \\  if (!w) return 5;
                \\  const a = __sa_addr(data), n = __sa_num(data_len);
                \\  const chunk = __sa_u8.slice(a, a + n);
                \\  const merged = new Uint8Array(w.stream.length + chunk.length);
                \\  merged.set(w.stream, 0);
                \\  merged.set(chunk, w.stream.length);
                \\  w.stream = merged;
                \\  __sa_store_i64(out_written, BigInt(n));
                \\  return 0;
                \\}
                \\
            );
            return;
        }
        if (std.mem.eql(u8, fsig.name, "sa_http_websocket_read_v2")) {
            try writer.writeAll(
                \\function sa_http_websocket_read_v2(ws, max_len, out_opcode, out_ptr, out_len) {
                \\  globalThis.__sa_http_c = (globalThis.__sa_http_c || {});
                \\  globalThis.__sa_http_req = (globalThis.__sa_http_req || {});
                \\  globalThis.__sa_http_resp = (globalThis.__sa_http_resp || {});
                \\  globalThis.__sa_http_rd = (globalThis.__sa_http_rd || {});
                \\  globalThis.__sa_http_op = (globalThis.__sa_http_op || {});
                \\  globalThis.__sa_http_ws = (globalThis.__sa_http_ws || {});
                \\  globalThis.__sa_http_sse = (globalThis.__sa_http_sse || {});
                \\  const w = globalThis.__sa_http_ws[__sa_addr(ws)];
                \\  if (!w) return 5;
                \\  const avail = w.stream.length - w.off;
                \\  if (avail <= 0) { __sa_store_i64(out_len, BigInt(0)); return w.closed ? 2 : 1; }
                \\  const n = Math.min(avail, __sa_num(max_len));
                \\  const chunk = w.stream.slice(w.off, w.off + n);
                \\  w.off += n;
                \\  if (!w.read_addr || w.read_cap < chunk.length) { w.read_addr = __sa_alloc(chunk.length); w.read_cap = chunk.length; }
                \\  __sa_u8.set(chunk, w.read_addr);
                \\  __sa_store_i64(out_opcode, BigInt(2));
                \\  __sa_store_ptr(out_ptr, w.read_addr);
                \\  __sa_store_i64(out_len, BigInt(n));
                \\  return 0;
                \\}
                \\
            );
            return;
        }
        if (std.mem.eql(u8, fsig.name, "sa_http_websocket_close_v2")) {
            try writer.writeAll(
                \\function sa_http_websocket_close_v2(ws, code, reason, reason_len) {
                \\  globalThis.__sa_http_c = (globalThis.__sa_http_c || {});
                \\  globalThis.__sa_http_req = (globalThis.__sa_http_req || {});
                \\  globalThis.__sa_http_resp = (globalThis.__sa_http_resp || {});
                \\  globalThis.__sa_http_rd = (globalThis.__sa_http_rd || {});
                \\  globalThis.__sa_http_op = (globalThis.__sa_http_op || {});
                \\  globalThis.__sa_http_ws = (globalThis.__sa_http_ws || {});
                \\  globalThis.__sa_http_sse = (globalThis.__sa_http_sse || {});
                \\  const w = globalThis.__sa_http_ws[__sa_addr(ws)];
                \\  if (!w) return 5;
                \\  w.closed = true;
                \\  return 0;
                \\}
                \\
            );
            return;
        }
        if (std.mem.eql(u8, fsig.name, "sa_http_websocket_free_v2")) {
            try writer.writeAll(
                \\function sa_http_websocket_free_v2(ws) {
                \\  globalThis.__sa_http_c = (globalThis.__sa_http_c || {});
                \\  globalThis.__sa_http_req = (globalThis.__sa_http_req || {});
                \\  globalThis.__sa_http_resp = (globalThis.__sa_http_resp || {});
                \\  globalThis.__sa_http_rd = (globalThis.__sa_http_rd || {});
                \\  globalThis.__sa_http_op = (globalThis.__sa_http_op || {});
                \\  globalThis.__sa_http_ws = (globalThis.__sa_http_ws || {});
                \\  globalThis.__sa_http_sse = (globalThis.__sa_http_sse || {});
                \\  delete globalThis.__sa_http_ws[__sa_addr(ws)];
                \\  return 0;
                \\}
                \\
            );
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
        // BP net shims (cookie / tls-config / net-slice / netinfo).
        if (std.mem.eql(u8, fsig.name, "sa_cookie_parse_set_cookie")) {
            try writer.writeAll(
                \\function sa_cookie_parse_set_cookie(bytes, len) {
                \\  const J = globalThis.__sa_jsnet;
                \\  J.ckErrClear();
                \\  const raw = __sa_mem_bytes(bytes, len);
                \\  const c = J.parseSetCookie(raw);
                \\  if (!c) { J.ckErrSet("cookie: invalid Set-Cookie value"); return 0n; }
                \\  return BigInt(J.ckReg(c));
                \\}
                \\
            );
            return;
        }
        if (std.mem.eql(u8, fsig.name, "sa_cookie_last_error")) {
            try writer.writeAll(
                \\function sa_cookie_last_error(out_ptr, out_len) {
                \\  const J = globalThis.__sa_jsnet;
                \\  return J.outStr(out_ptr, out_len, J.ckErrGet());
                \\}
                \\
            );
            return;
        }
        if (std.mem.eql(u8, fsig.name, "sa_cookie_free")) {
            try writer.writeAll(
                \\function sa_cookie_free(handle) {
                \\  const J = globalThis.__sa_jsnet;
                \\  return J.ckFree(__sa_num(handle)) ? 0 : 2;
                \\}
                \\
            );
            return;
        }
        if (std.mem.eql(u8, fsig.name, "sa_cookie_new")) {
            try writer.writeAll(
                \\function sa_cookie_new(name, name_len, value, value_len) {
                \\  const J = globalThis.__sa_jsnet;
                \\  J.ckErrClear();
                \\  const n = __sa_mem_bytes(name, name_len);
                \\  const v = __sa_mem_bytes(value, value_len);
                \\  if (!J.validCookieName(n)) { J.ckErrSet("cookie: invalid cookie name"); return 0n; }
                \\  if (!J.validCookieValue(v)) { J.ckErrSet("cookie: invalid cookie value"); return 0n; }
                \\  return BigInt(J.ckReg(J.mkCookie(n.slice(), v.slice())));
                \\}
                \\
            );
            return;
        }
        if (std.mem.eql(u8, fsig.name, "sa_cookie_name")) {
            try writer.writeAll(
                \\function sa_cookie_name(handle, out_ptr, out_len) {
                \\  const J = globalThis.__sa_jsnet;
                \\  const c = J.ckGet(__sa_num(handle));
                \\  if (!c) return 2;
                \\  return J.outStr(out_ptr, out_len, c.name);
                \\}
                \\
            );
            return;
        }
        if (std.mem.eql(u8, fsig.name, "sa_cookie_value")) {
            try writer.writeAll(
                \\function sa_cookie_value(handle, out_ptr, out_len) {
                \\  const J = globalThis.__sa_jsnet;
                \\  const c = J.ckGet(__sa_num(handle));
                \\  if (!c) return 2;
                \\  return J.outStr(out_ptr, out_len, c.value);
                \\}
                \\
            );
            return;
        }
        if (std.mem.eql(u8, fsig.name, "sa_cookie_domain")) {
            try writer.writeAll(
                \\function sa_cookie_domain(handle, out_ptr, out_len) {
                \\  const J = globalThis.__sa_jsnet;
                \\  const c = J.ckGet(__sa_num(handle));
                \\  if (!c) return 2;
                \\  return J.outStr(out_ptr, out_len, c.hasDomain ? c.domain : null);
                \\}
                \\
            );
            return;
        }
        if (std.mem.eql(u8, fsig.name, "sa_cookie_path")) {
            try writer.writeAll(
                \\function sa_cookie_path(handle, out_ptr, out_len) {
                \\  const J = globalThis.__sa_jsnet;
                \\  const c = J.ckGet(__sa_num(handle));
                \\  if (!c) return 2;
                \\  return J.outStr(out_ptr, out_len, c.hasPath ? c.path : null);
                \\}
                \\
            );
            return;
        }
        if (std.mem.eql(u8, fsig.name, "sa_cookie_expires")) {
            try writer.writeAll(
                \\function sa_cookie_expires(handle, out_unix) {
                \\  const J = globalThis.__sa_jsnet;
                \\  __sa_store_i64(out_unix, 0n);
                \\  const c = J.ckGet(__sa_num(handle));
                \\  if (!c) return 2;
                \\  if (c.expires === null) return 3;
                \\  __sa_store_i64(out_unix, BigInt(c.expires));
                \\  return 0;
                \\}
                \\
            );
            return;
        }
        if (std.mem.eql(u8, fsig.name, "sa_cookie_max_age")) {
            try writer.writeAll(
                \\function sa_cookie_max_age(handle, out_secs) {
                \\  const J = globalThis.__sa_jsnet;
                \\  __sa_store_i64(out_secs, 0n);
                \\  const c = J.ckGet(__sa_num(handle));
                \\  if (!c) return 2;
                \\  if (c.maxAge === null) return 3;
                \\  __sa_store_i64(out_secs, BigInt(c.maxAge));
                \\  return 0;
                \\}
                \\
            );
            return;
        }
        if (std.mem.eql(u8, fsig.name, "sa_cookie_flags")) {
            try writer.writeAll(
                \\function sa_cookie_flags(handle, out_secure, out_http_only, out_partitioned) {
                \\  const J = globalThis.__sa_jsnet;
                \\  const c = J.ckGet(__sa_num(handle));
                \\  if (!c) return 2;
                \\  __sa_store_i32(out_secure, c.secure ? 1 : 0);
                \\  __sa_store_i32(out_http_only, c.httpOnly ? 1 : 0);
                \\  __sa_store_i32(out_partitioned, c.partitioned ? 1 : 0);
                \\  return 0;
                \\}
                \\
            );
            return;
        }
        if (std.mem.eql(u8, fsig.name, "sa_cookie_same_site")) {
            try writer.writeAll(
                \\function sa_cookie_same_site(handle, out_mode) {
                \\  const J = globalThis.__sa_jsnet;
                \\  __sa_store_u32(out_mode, 0);
                \\  const c = J.ckGet(__sa_num(handle));
                \\  if (!c) return 2;
                \\  __sa_store_u32(out_mode, c.sameSite);
                \\  return 0;
                \\}
                \\
            );
            return;
        }
        if (std.mem.eql(u8, fsig.name, "sa_cookie_is_host_only")) {
            try writer.writeAll(
                \\function sa_cookie_is_host_only(handle, out_flag) {
                \\  const J = globalThis.__sa_jsnet;
                \\  __sa_store_i32(out_flag, 0);
                \\  const c = J.ckGet(__sa_num(handle));
                \\  if (!c) return 2;
                \\  __sa_store_i32(out_flag, c.hostOnly ? 1 : 0);
                \\  return 0;
                \\}
                \\
            );
            return;
        }
        if (std.mem.eql(u8, fsig.name, "sa_cookie_set_domain")) {
            try writer.writeAll(
                \\function sa_cookie_set_domain(handle, bytes, len) {
                \\  const J = globalThis.__sa_jsnet;
                \\  const c = J.ckGet(__sa_num(handle));
                \\  if (!c) return 2;
                \\  let d = __sa_mem_bytes(bytes, len);
                \\  if (d.length > 0 && d[0] === 46) d = d.subarray(1);
                \\  if (!J.validDomainAttr(d)) return 1;
                \\  c.domain = J.bLower(d).slice();
                \\  c.hasDomain = true;
                \\  return 0;
                \\}
                \\
            );
            return;
        }
        if (std.mem.eql(u8, fsig.name, "sa_cookie_set_path")) {
            try writer.writeAll(
                \\function sa_cookie_set_path(handle, bytes, len) {
                \\  const J = globalThis.__sa_jsnet;
                \\  const c = J.ckGet(__sa_num(handle));
                \\  if (!c) return 2;
                \\  const p = __sa_mem_bytes(bytes, len);
                \\  if (p.length === 0 || p[0] !== 47) return 1;
                \\  for (let i = 0; i < p.length; i++) if (p[i] < 32 || p[i] === 127) return 1;
                \\  c.path = p.slice();
                \\  c.hasPath = true;
                \\  return 0;
                \\}
                \\
            );
            return;
        }
        if (std.mem.eql(u8, fsig.name, "sa_cookie_set_expires")) {
            try writer.writeAll(
                \\function sa_cookie_set_expires(handle, unix) {
                \\  const J = globalThis.__sa_jsnet;
                \\  const c = J.ckGet(__sa_num(handle));
                \\  if (!c) return 2;
                \\  c.expires = __sa_num(unix);
                \\  return 0;
                \\}
                \\
            );
            return;
        }
        if (std.mem.eql(u8, fsig.name, "sa_cookie_set_max_age")) {
            try writer.writeAll(
                \\function sa_cookie_set_max_age(handle, secs) {
                \\  const J = globalThis.__sa_jsnet;
                \\  const c = J.ckGet(__sa_num(handle));
                \\  if (!c) return 2;
                \\  c.maxAge = __sa_num(secs);
                \\  return 0;
                \\}
                \\
            );
            return;
        }
        if (std.mem.eql(u8, fsig.name, "sa_cookie_clear_expiry")) {
            try writer.writeAll(
                \\function sa_cookie_clear_expiry(handle) {
                \\  const J = globalThis.__sa_jsnet;
                \\  const c = J.ckGet(__sa_num(handle));
                \\  if (!c) return 2;
                \\  c.expires = null;
                \\  c.maxAge = null;
                \\  return 0;
                \\}
                \\
            );
            return;
        }
        if (std.mem.eql(u8, fsig.name, "sa_cookie_set_secure")) {
            try writer.writeAll(
                \\function sa_cookie_set_secure(handle, on) {
                \\  const J = globalThis.__sa_jsnet;
                \\  const c = J.ckGet(__sa_num(handle));
                \\  if (!c) return 2;
                \\  c.secure = __sa_num(on) !== 0;
                \\  return 0;
                \\}
                \\
            );
            return;
        }
        if (std.mem.eql(u8, fsig.name, "sa_cookie_set_http_only")) {
            try writer.writeAll(
                \\function sa_cookie_set_http_only(handle, on) {
                \\  const J = globalThis.__sa_jsnet;
                \\  const c = J.ckGet(__sa_num(handle));
                \\  if (!c) return 2;
                \\  c.httpOnly = __sa_num(on) !== 0;
                \\  return 0;
                \\}
                \\
            );
            return;
        }
        if (std.mem.eql(u8, fsig.name, "sa_cookie_set_partitioned")) {
            try writer.writeAll(
                \\function sa_cookie_set_partitioned(handle, on) {
                \\  const J = globalThis.__sa_jsnet;
                \\  const c = J.ckGet(__sa_num(handle));
                \\  if (!c) return 2;
                \\  c.partitioned = __sa_num(on) !== 0;
                \\  return 0;
                \\}
                \\
            );
            return;
        }
        if (std.mem.eql(u8, fsig.name, "sa_cookie_set_same_site")) {
            try writer.writeAll(
                \\function sa_cookie_set_same_site(handle, mode) {
                \\  const J = globalThis.__sa_jsnet;
                \\  const c = J.ckGet(__sa_num(handle));
                \\  if (!c) return 2;
                \\  if (__sa_num(mode) > 3) return 1;
                \\  c.sameSite = __sa_num(mode);
                \\  return 0;
                \\}
                \\
            );
            return;
        }
        if (std.mem.eql(u8, fsig.name, "sa_cookie_serialize")) {
            try writer.writeAll(
                \\function sa_cookie_serialize(handle, out_ptr, out_len) {
                \\  const J = globalThis.__sa_jsnet;
                \\  const c = J.ckGet(__sa_num(handle));
                \\  if (!c) return 2;
                \\  return J.outStr(out_ptr, out_len, J.serializeCookie(c, false));
                \\}
                \\
            );
            return;
        }
        if (std.mem.eql(u8, fsig.name, "sa_cookie_serialize_pair")) {
            try writer.writeAll(
                \\function sa_cookie_serialize_pair(handle, out_ptr, out_len) {
                \\  const J = globalThis.__sa_jsnet;
                \\  const c = J.ckGet(__sa_num(handle));
                \\  if (!c) return 2;
                \\  return J.outStr(out_ptr, out_len, J.serializeCookie(c, true));
                \\}
                \\
            );
            return;
        }
        if (std.mem.eql(u8, fsig.name, "sa_cookie_is_expired")) {
            try writer.writeAll(
                \\function sa_cookie_is_expired(handle, now, out_flag) {
                \\  const J = globalThis.__sa_jsnet;
                \\  __sa_store_i32(out_flag, 0);
                \\  const c = J.ckGet(__sa_num(handle));
                \\  if (!c) return 2;
                \\  if (c.expires !== null && c.expires <= __sa_num(now)) __sa_store_i32(out_flag, 1);
                \\  return 0;
                \\}
                \\
            );
            return;
        }
        if (std.mem.eql(u8, fsig.name, "sa_cookie_domain_match")) {
            try writer.writeAll(
                \\function sa_cookie_domain_match(domain, domain_len, host, host_len, out_flag) {
                \\  const J = globalThis.__sa_jsnet;
                \\  __sa_store_i32(out_flag, 0);
                \\  let d = __sa_mem_bytes(domain, domain_len);
                \\  if (d.length > 0 && d[0] === 46) d = d.subarray(1);
                \\  const h = __sa_mem_bytes(host, host_len);
                \\  __sa_store_i32(out_flag, J.domainMatch(d, h) ? 1 : 0);
                \\  return 0;
                \\}
                \\
            );
            return;
        }
        if (std.mem.eql(u8, fsig.name, "sa_cookie_path_match")) {
            try writer.writeAll(
                \\function sa_cookie_path_match(cookie_path, cookie_path_len, request_path, request_path_len, out_flag) {
                \\  const J = globalThis.__sa_jsnet;
                \\  __sa_store_i32(out_flag, 0);
                \\  const cp = __sa_mem_bytes(cookie_path, cookie_path_len);
                \\  const rp = __sa_mem_bytes(request_path, request_path_len);
                \\  __sa_store_i32(out_flag, J.pathMatch(cp, rp) ? 1 : 0);
                \\  return 0;
                \\}
                \\
            );
            return;
        }
        if (std.mem.eql(u8, fsig.name, "sa_cookie_header_pair_count")) {
            try writer.writeAll(
                \\function sa_cookie_header_pair_count(bytes, len, out_count) {
                \\  const J = globalThis.__sa_jsnet;
                \\  __sa_store_i64(out_count, 0n);
                \\  const raw = __sa_mem_bytes(bytes, len);
                \\  const n = J.headerPairCount(raw);
                \\  if (n < 0) return 1;
                \\  __sa_store_i64(out_count, BigInt(n));
                \\  return 0;
                \\}
                \\
            );
            return;
        }
        if (std.mem.eql(u8, fsig.name, "sa_cookie_header_pair_at")) {
            try writer.writeAll(
                \\function sa_cookie_header_pair_at(bytes, len, index) {
                \\  const J = globalThis.__sa_jsnet;
                \\  J.ckErrClear();
                \\  const raw = __sa_mem_bytes(bytes, len);
                \\  const c = J.headerPairAt(raw, __sa_num(index));
                \\  if (c === null) return 0n;
                \\  if (c === "bad") { J.ckErrSet("cookie: invalid Cookie header pair"); return 0n; }
                \\  return BigInt(J.ckReg(c));
                \\}
                \\
            );
            return;
        }
        if (std.mem.eql(u8, fsig.name, "sa_cookie_jar_new")) {
            try writer.writeAll(
                \\function sa_cookie_jar_new() {
                \\  const J = globalThis.__sa_jsnet;
                \\  return BigInt(J.jarReg(J.mkJar()));
                \\}
                \\
            );
            return;
        }
        if (std.mem.eql(u8, fsig.name, "sa_cookie_jar_free")) {
            try writer.writeAll(
                \\function sa_cookie_jar_free(jar) {
                \\  const J = globalThis.__sa_jsnet;
                \\  return J.jarFree(__sa_num(jar)) ? 0 : 2;
                \\}
                \\
            );
            return;
        }
        if (std.mem.eql(u8, fsig.name, "sa_cookie_jar_set_policy")) {
            try writer.writeAll(
                \\function sa_cookie_jar_set_policy(jar, policy) {
                \\  const J = globalThis.__sa_jsnet;
                \\  const j = J.jarGet(__sa_num(jar));
                \\  if (!j) return 2;
                \\  if (__sa_num(policy) > 2) return 1;
                \\  j.policy = __sa_num(policy);
                \\  return 0;
                \\}
                \\
            );
            return;
        }
        if (std.mem.eql(u8, fsig.name, "sa_cookie_jar_policy")) {
            try writer.writeAll(
                \\function sa_cookie_jar_policy(jar, out_policy) {
                \\  const J = globalThis.__sa_jsnet;
                \\  __sa_store_u32(out_policy, 0);
                \\  const j = J.jarGet(__sa_num(jar));
                \\  if (!j) return 2;
                \\  __sa_store_u32(out_policy, j.policy);
                \\  return 0;
                \\}
                \\
            );
            return;
        }
        if (std.mem.eql(u8, fsig.name, "sa_cookie_jar_store")) {
            try writer.writeAll(
                \\function sa_cookie_jar_store(jar, url, url_len, set_cookie, set_cookie_len, now, out_result) {
                \\  const J = globalThis.__sa_jsnet;
                \\  const j = J.jarGet(__sa_num(jar));
                \\  if (!j) return 2;
                \\  const u = __sa_mem_bytes(url, url_len);
                \\  const sc = __sa_mem_bytes(set_cookie, set_cookie_len);
                \\  const r = J.jarStore(j, u, sc, __sa_num(now));
                \\  if (r < 0) return 1;
                \\  __sa_store_u32(out_result, r);
                \\  return 0;
                \\}
                \\
            );
            return;
        }
        if (std.mem.eql(u8, fsig.name, "sa_cookie_jar_header")) {
            try writer.writeAll(
                \\function sa_cookie_jar_header(jar, url, url_len, now, out_ptr, out_len) {
                \\  const J = globalThis.__sa_jsnet;
                \\  __sa_store_ptr(out_ptr, 0);
                \\  __sa_store_i64(out_len, 0n);
                \\  const j = J.jarGet(__sa_num(jar));
                \\  if (!j) return 2;
                \\  const u = __sa_mem_bytes(url, url_len);
                \\  const h = J.jarHeader(j, u, __sa_num(now));
                \\  if (h === null) return 3;
                \\  return J.outStr(out_ptr, out_len, h);
                \\}
                \\
            );
            return;
        }
        if (std.mem.eql(u8, fsig.name, "sa_cookie_jar_count")) {
            try writer.writeAll(
                \\function sa_cookie_jar_count(jar, out_count) {
                \\  const J = globalThis.__sa_jsnet;
                \\  __sa_store_i64(out_count, 0n);
                \\  const j = J.jarGet(__sa_num(jar));
                \\  if (!j) return 2;
                \\  __sa_store_i64(out_count, BigInt(j.entries.length));
                \\  return 0;
                \\}
                \\
            );
            return;
        }
        if (std.mem.eql(u8, fsig.name, "sa_cookie_jar_at")) {
            try writer.writeAll(
                \\function sa_cookie_jar_at(jar, index) {
                \\  const J = globalThis.__sa_jsnet;
                \\  const j = J.jarGet(__sa_num(jar));
                \\  if (!j) return 0n;
                \\  const idx = __sa_num(index);
                \\  if (idx >= j.entries.length) return 0n;
                \\  const copy = J.cloneCookie(j.entries[idx]);
                \\  copy.maxAge = null;
                \\  return BigInt(J.ckReg(copy));
                \\}
                \\
            );
            return;
        }
        if (std.mem.eql(u8, fsig.name, "sa_cookie_jar_clear")) {
            try writer.writeAll(
                \\function sa_cookie_jar_clear(jar) {
                \\  const J = globalThis.__sa_jsnet;
                \\  const j = J.jarGet(__sa_num(jar));
                \\  if (!j) return 2;
                \\  j.entries.length = 0;
                \\  return 0;
                \\}
                \\
            );
            return;
        }
        if (std.mem.eql(u8, fsig.name, "sa_cookie_jar_evict_expired")) {
            try writer.writeAll(
                \\function sa_cookie_jar_evict_expired(jar, now, out_removed) {
                \\  const J = globalThis.__sa_jsnet;
                \\  __sa_store_i64(out_removed, 0n);
                \\  const j = J.jarGet(__sa_num(jar));
                \\  if (!j) return 2;
                \\  __sa_store_i64(out_removed, BigInt(J.jarEvict(j, __sa_num(now))));
                \\  return 0;
                \\}
                \\
            );
            return;
        }
        if (std.mem.eql(u8, fsig.name, "sa_cookie_jar_save")) {
            try writer.writeAll(
                \\function sa_cookie_jar_save(jar, path, path_len) {
                \\  const J = globalThis.__sa_jsnet;
                \\  const j = J.jarGet(__sa_num(jar));
                \\  if (!j) return 2;
                \\  const p = __sa_mem_bytes(path, path_len);
                \\  if (p.length === 0) return 1;
                \\  try {
                \\    const fs = __sa_node_builtin("node:fs");
                \\    fs.writeFileSync(J.bToStr(p), Buffer.from(J.jarSaveText(j)));
                \\  } catch (e) { return 6; }
                \\  return 0;
                \\}
                \\
            );
            return;
        }
        if (std.mem.eql(u8, fsig.name, "sa_cookie_jar_load")) {
            try writer.writeAll(
                \\function sa_cookie_jar_load(jar, path, path_len, out_loaded) {
                \\  const J = globalThis.__sa_jsnet;
                \\  __sa_store_i64(out_loaded, 0n);
                \\  const j = J.jarGet(__sa_num(jar));
                \\  if (!j) return 2;
                \\  const p = __sa_mem_bytes(path, path_len);
                \\  if (p.length === 0) return 1;
                \\  let data;
                \\  try {
                \\    const fs = __sa_node_builtin("node:fs");
                \\    data = new Uint8Array(fs.readFileSync(J.bToStr(p)));
                \\  } catch (e) { return 6; }
                \\  const r = J.jarLoad(j, data);
                \\  if (r.error) { J.ckErrSet(r.error); return 1; }
                \\  __sa_store_i64(out_loaded, BigInt(r.loaded));
                \\  return 0;
                \\}
                \\
            );
            return;
        }
        if (std.mem.eql(u8, fsig.name, "sa_cookie_jar_request_header")) {
            try writer.writeAll(
                \\function sa_cookie_jar_request_header(jar, url, url_len, out_ptr, out_len) {
                \\  const J = globalThis.__sa_jsnet;
                \\  __sa_store_ptr(out_ptr, 0);
                \\  __sa_store_i64(out_len, 0n);
                \\  const j = J.jarGet(__sa_num(jar));
                \\  if (!j) return 2;
                \\  const u = __sa_mem_bytes(url, url_len);
                \\  const now = Math.floor(Date.now() / 1000);
                \\  const h = J.jarHeader(j, u, now);
                \\  if (h === null) return 3;
                \\  return J.outStr(out_ptr, out_len, h);
                \\}
                \\
            );
            return;
        }
        if (std.mem.eql(u8, fsig.name, "sa_cookie_jar_store_response")) {
            try writer.writeAll(
                \\function sa_cookie_jar_store_response(jar, url, url_len, set_cookie, set_cookie_len) {
                \\  const J = globalThis.__sa_jsnet;
                \\  const j = J.jarGet(__sa_num(jar));
                \\  if (!j) return 2;
                \\  const u = __sa_mem_bytes(url, url_len);
                \\  const sc = __sa_mem_bytes(set_cookie, set_cookie_len);
                \\  const now = Math.floor(Date.now() / 1000);
                \\  const r = J.jarStore(j, u, sc, now);
                \\  if (r < 0) return 1;
                \\  return 0;
                \\}
                \\
            );
            return;
        }
        if (std.mem.eql(u8, fsig.name, "sa_std_tls_client_supported")) {
            try writer.writeAll(
                \\function sa_std_tls_client_supported(out_supported) {
                \\  const J = globalThis.__sa_jsnet;
                \\  __sa_store_u32(out_supported, 1);
                \\  return 0;
                \\}
                \\
            );
            return;
        }
        if (std.mem.eql(u8, fsig.name, "sa_std_tls_client_add_ca_file")) {
            try writer.writeAll(
                \\function sa_std_tls_client_add_ca_file(path, path_len) {
                \\  const J = globalThis.__sa_jsnet;
                \\  const p = __sa_mem_bytes(path, path_len);
                \\  const s = J.bToStr(p);
                \\  if (s.length === 0 || s[0] !== "/") return -22;
                \\  try {
                \\    const fs = __sa_node_builtin("node:fs");
                \\    J.TLS.processCas.push(fs.readFileSync(s, "utf8"));
                \\  } catch (e) { return -5; }
                \\  return 0;
                \\}
                \\
            );
            return;
        }
        if (std.mem.eql(u8, fsig.name, "sa_std_tls_client_connect")) {
            try writer.writeAll(
                \\function sa_std_tls_client_connect(host, host_len, port, out_handle) {
                \\  const J = globalThis.__sa_jsnet;
                \\  __sa_store_i64(out_handle, 0n);
                \\  const h = J.bToStr(__sa_mem_bytes(host, host_len));
                \\  const r = J.tlsConnectFull(h, __sa_num(port), null, null);
                \\  if (r.status !== 0) return r.status;
                \\  __sa_store_i64(out_handle, BigInt(r.saHandle));
                \\  return 0;
                \\}
                \\
            );
            return;
        }
        if (std.mem.eql(u8, fsig.name, "sa_std_tls_client_read")) {
            try writer.writeAll(
                \\function sa_std_tls_client_read(handle, buf, cap, out_read) {
                \\  const J = globalThis.__sa_jsnet;
                \\  __sa_store_i64(out_read, 0n);
                \\  const e = J.netGet(__sa_num(handle));
                \\  if (!e || e.kind !== "tls") return -22;
                \\  const r = J.bridgeCall("stream_read", { id: e.bridgeId, cap: __sa_num(cap), tlsSpace: true }, null, true);
                \\  if (r.status !== 0) return r.status;
                \\  if (r.bytes) __sa_u8.set(r.bytes, __sa_addr(buf));
                \\  __sa_store_i64(out_read, BigInt(r.json.read || 0));
                \\  return 0;
                \\}
                \\
            );
            return;
        }
        if (std.mem.eql(u8, fsig.name, "sa_std_tls_client_write")) {
            try writer.writeAll(
                \\function sa_std_tls_client_write(handle, buf, len, out_written) {
                \\  const J = globalThis.__sa_jsnet;
                \\  __sa_store_i64(out_written, 0n);
                \\  const e = J.netGet(__sa_num(handle));
                \\  if (!e || e.kind !== "tls") return -22;
                \\  const payload = __sa_mem_bytes(buf, len);
                \\  const r = J.bridgeCall("stream_write", { id: e.bridgeId, tlsSpace: true }, payload, true);
                \\  if (r.status !== 0) return r.status;
                \\  __sa_store_i64(out_written, BigInt(r.json.written || 0));
                \\  return 0;
                \\}
                \\
            );
            return;
        }
        if (std.mem.eql(u8, fsig.name, "sa_std_tls_client_close")) {
            try writer.writeAll(
                \\function sa_std_tls_client_close(handle) {
                \\  const J = globalThis.__sa_jsnet;
                \\  const e = J.netGet(__sa_num(handle));
                \\  if (!e || e.kind !== "tls") return -22;
                \\  J.bridgeCall("sock_close", { id: e.bridgeId }, null, true);
                \\  J.netDel(__sa_num(handle));
                \\  return 0;
                \\}
                \\
            );
            return;
        }
        if (std.mem.eql(u8, fsig.name, "sa_std_tls_client_status_json")) {
            try writer.writeAll(
                \\function sa_std_tls_client_status_json(out_handle) {
                \\  const J = globalThis.__sa_jsnet;
                \\  __sa_store_i64(out_handle, 0n);
                \\  const text = JSON.stringify({ module: "tls_client", backend: "node:tls", supported: true, protocolMachine: true });
                \\  const h = __sa_buf_open(new globalThis.TextEncoder().encode(text));
                \\  __sa_store_i64(out_handle, h);
                \\  return 0;
                \\}
                \\
            );
            return;
        }
        if (std.mem.eql(u8, fsig.name, "sa_std_tls_client_buffer_data")) {
            try writer.writeAll(
                \\function sa_std_tls_client_buffer_data(buffer) {
                \\  const J = globalThis.__sa_jsnet;
                \\  const b = __sa_buf_get(buffer);
                \\  if (b === null) return 0;
                \\  const p = __sa_alloc(b.length);
                \\  __sa_u8.set(b, p);
                \\  return p;
                \\}
                \\
            );
            return;
        }
        if (std.mem.eql(u8, fsig.name, "sa_std_tls_client_buffer_len")) {
            try writer.writeAll(
                \\function sa_std_tls_client_buffer_len(buffer) {
                \\  const J = globalThis.__sa_jsnet;
                \\  const b = __sa_buf_get(buffer);
                \\  return b === null ? 0n : BigInt(b.length);
                \\}
                \\
            );
            return;
        }
        if (std.mem.eql(u8, fsig.name, "sa_std_tls_client_buffer_free")) {
            try writer.writeAll(
                \\function sa_std_tls_client_buffer_free(buffer) {
                \\  const J = globalThis.__sa_jsnet;
                \\  return __sa_buffers.delete(__sa_num(buffer)) ? 0 : -22;
                \\}
                \\
            );
            return;
        }
        if (std.mem.eql(u8, fsig.name, "sa_std_tls_client_peer_cert_json")) {
            try writer.writeAll(
                \\function sa_std_tls_client_peer_cert_json(handle, out_handle) {
                \\  const J = globalThis.__sa_jsnet;
                \\  // UNSUPPORTED by construction on this backend too (std.crypto.tls does
                \\  // not retain the peer certificate; Node could, but the contract mirrors
                \\  // native exactly): handle 0 -> -22, anything else -> -1, out untouched.
                \\  if (__sa_num(handle) === 0) return -22;
                \\  return -1;
                \\}
                \\
            );
            return;
        }
        if (std.mem.eql(u8, fsig.name, "sa_std_tls_client_config_new")) {
            try writer.writeAll(
                \\function sa_std_tls_client_config_new(out_config) {
                \\  const J = globalThis.__sa_jsnet;
                \\  __sa_store_i64(out_config, 0n);
                \\  __sa_store_i64(out_config, BigInt(J.tlsCfgNew()));
                \\  return 0;
                \\}
                \\
            );
            return;
        }
        if (std.mem.eql(u8, fsig.name, "sa_std_tls_client_config_free")) {
            try writer.writeAll(
                \\function sa_std_tls_client_config_free(config) {
                \\  const J = globalThis.__sa_jsnet;
                \\  if (__sa_num(config) === 0) return 0;
                \\  J.tlsCfgFree(__sa_num(config));
                \\  return 0;
                \\}
                \\
            );
            return;
        }
        if (std.mem.eql(u8, fsig.name, "sa_std_tls_client_config_set_server_name")) {
            try writer.writeAll(
                \\function sa_std_tls_client_config_set_server_name(config, name, name_len) {
                \\  const J = globalThis.__sa_jsnet;
                \\  const c = J.tlsCfgGet(__sa_num(config));
                \\  if (!c) return -22;
                \\  const n = __sa_mem_bytes(name, name_len);
                \\  c.serverName = (n.length === 0) ? null : n.slice();
                \\  return 0;
                \\}
                \\
            );
            return;
        }
        if (std.mem.eql(u8, fsig.name, "sa_std_tls_client_config_add_ca_file")) {
            try writer.writeAll(
                \\function sa_std_tls_client_config_add_ca_file(config, path, path_len) {
                \\  const J = globalThis.__sa_jsnet;
                \\  const c = J.tlsCfgGet(__sa_num(config));
                \\  if (!c) return -22;
                \\  const p = __sa_mem_bytes(path, path_len);
                \\  const s = J.bToStr(p);
                \\  if (s.length === 0 || s[0] !== "/") return -22;
                \\  c.caFiles.push(p.slice());
                \\  return 0;
                \\}
                \\
            );
            return;
        }
        if (std.mem.eql(u8, fsig.name, "sa_std_tls_client_config_add_ca_memory")) {
            try writer.writeAll(
                \\function sa_std_tls_client_config_add_ca_memory(config, pem, pem_len) {
                \\  const J = globalThis.__sa_jsnet;
                \\  const c = J.tlsCfgGet(__sa_num(config));
                \\  if (!c) return -22;
                \\  const p = __sa_mem_bytes(pem, pem_len);
                \\  if (p.length === 0) return -22;
                \\  const n = J.pemUsableCount(J.bToStr(p));
                \\  if (n <= 0) return -22;
                \\  c.caPems.push(J.bToStr(p));
                \\  return 0;
                \\}
                \\
            );
            return;
        }
        if (std.mem.eql(u8, fsig.name, "sa_std_tls_client_config_set_insecure_no_verification")) {
            try writer.writeAll(
                \\function sa_std_tls_client_config_set_insecure_no_verification(config, enabled) {
                \\  const J = globalThis.__sa_jsnet;
                \\  const c = J.tlsCfgGet(__sa_num(config));
                \\  if (!c) return -22;
                \\  c.insecure = __sa_num(enabled) !== 0;
                \\  return 0;
                \\}
                \\
            );
            return;
        }
        if (std.mem.eql(u8, fsig.name, "sa_std_tls_client_config_set_verify_self_signed")) {
            try writer.writeAll(
                \\function sa_std_tls_client_config_set_verify_self_signed(config, enabled) {
                \\  const J = globalThis.__sa_jsnet;
                \\  const c = J.tlsCfgGet(__sa_num(config));
                \\  if (!c) return -22;
                \\  c.verifySelfSigned = __sa_num(enabled) !== 0;
                \\  return 0;
                \\}
                \\
            );
            return;
        }
        if (std.mem.eql(u8, fsig.name, "sa_std_tls_client_connect_config")) {
            try writer.writeAll(
                \\function sa_std_tls_client_connect_config(host, host_len, port, config, out_handle) {
                \\  const J = globalThis.__sa_jsnet;
                \\  __sa_store_i64(out_handle, 0n);
                \\  const h = J.bToStr(__sa_mem_bytes(host, host_len));
                \\  let cfg = null;
                \\  if (__sa_num(config) !== 0) {
                \\    cfg = J.tlsCfgGet(__sa_num(config));
                \\    if (!cfg) return -22;
                \\  }
                \\  const r = J.tlsConnectFull(h, __sa_num(port), cfg, null);
                \\  if (r.status !== 0) return r.status;
                \\  __sa_store_i64(out_handle, BigInt(r.saHandle));
                \\  return 0;
                \\}
                \\
            );
            return;
        }
        if (std.mem.eql(u8, fsig.name, "sa_std_tls_client_start_tls")) {
            try writer.writeAll(
                \\function sa_std_tls_client_start_tls(fd, host, host_len, config, out_handle) {
                \\  const J = globalThis.__sa_jsnet;
                \\  __sa_store_i64(out_handle, 0n);
                \\  const h = J.bToStr(__sa_mem_bytes(host, host_len));
                \\  let cfg = null;
                \\  if (__sa_num(config) !== 0) {
                \\    cfg = J.tlsCfgGet(__sa_num(config));
                \\    if (!cfg) return -22;
                \\  }
                \\  const r = J.tlsConnectFull(h, 0, cfg, __sa_num(fd));
                \\  // The port comes from the existing connection; the chunk skips the
                \\  // port check on the upgrade branch.
                \\  if (r.status !== 0) return r.status;
                \\  __sa_store_i64(out_handle, BigInt(r.saHandle));
                \\  return 0;
                \\}
                \\
            );
            return;
        }
        if (std.mem.eql(u8, fsig.name, "sa_std_tls_shaped_supported")) {
            try writer.writeAll(
                \\function sa_std_tls_shaped_supported(out_supported) {
                \\  const J = globalThis.__sa_jsnet;
                \\  __sa_store_u32(out_supported, 0);
                \\  return 0;
                \\}
                \\
            );
            return;
        }
        if (std.mem.eql(u8, fsig.name, "sa_std_tls_shaped_connect")) {
            try writer.writeAll(
                \\function sa_std_tls_shaped_connect(host, host_len, port, profile, profile_len, out_handle) {
                \\  const J = globalThis.__sa_jsnet;
                \\  __sa_store_i64(out_handle, 0n);
                \\  return -1;
                \\}
                \\
            );
            return;
        }
        if (std.mem.eql(u8, fsig.name, "sa_std_tls_shaped_read")) {
            try writer.writeAll(
                \\function sa_std_tls_shaped_read(handle, buf, cap, out_read) {
                \\  const J = globalThis.__sa_jsnet;
                \\  __sa_store_i64(out_read, 0n);
                \\  return -1;
                \\}
                \\
            );
            return;
        }
        if (std.mem.eql(u8, fsig.name, "sa_std_tls_shaped_write")) {
            try writer.writeAll(
                \\function sa_std_tls_shaped_write(handle, buf, len, out_written) {
                \\  const J = globalThis.__sa_jsnet;
                \\  __sa_store_i64(out_written, 0n);
                \\  return -1;
                \\}
                \\
            );
            return;
        }
        if (std.mem.eql(u8, fsig.name, "sa_std_tls_shaped_close")) {
            try writer.writeAll(
                \\function sa_std_tls_shaped_close(handle) {
                \\  const J = globalThis.__sa_jsnet;
                \\  return -1;
                \\}
                \\
            );
            return;
        }
        if (std.mem.eql(u8, fsig.name, "sa_std_tls_shaped_negotiated_json")) {
            try writer.writeAll(
                \\function sa_std_tls_shaped_negotiated_json(handle, out_handle) {
                \\  const J = globalThis.__sa_jsnet;
                \\  __sa_store_i64(out_handle, 0n);
                \\  return -1;
                \\}
                \\
            );
            return;
        }
        if (std.mem.eql(u8, fsig.name, "sa_std_tls_shaped_hello_ja3")) {
            try writer.writeAll(
                \\function sa_std_tls_shaped_hello_ja3(handle, out, out_cap, out_len) {
                \\  const J = globalThis.__sa_jsnet;
                \\  __sa_store_i64(out_len, 0n);
                \\  return -1;
                \\}
                \\
            );
            return;
        }
        if (std.mem.eql(u8, fsig.name, "sa_std_tls_shaped_hello_ja3_string")) {
            try writer.writeAll(
                \\function sa_std_tls_shaped_hello_ja3_string(handle, out, out_cap, out_len) {
                \\  const J = globalThis.__sa_jsnet;
                \\  __sa_store_i64(out_len, 0n);
                \\  return -1;
                \\}
                \\
            );
            return;
        }
        if (std.mem.eql(u8, fsig.name, "sa_std_tls_shaped_hello_ja4")) {
            try writer.writeAll(
                \\function sa_std_tls_shaped_hello_ja4(handle, out, out_cap, out_len) {
                \\  const J = globalThis.__sa_jsnet;
                \\  __sa_store_i64(out_len, 0n);
                \\  return -1;
                \\}
                \\
            );
            return;
        }
        if (std.mem.eql(u8, fsig.name, "sa_std_tls_shaped_start_tls")) {
            try writer.writeAll(
                \\function sa_std_tls_shaped_start_tls(fd, host, host_len, profile, profile_len, out_handle) {
                \\  const J = globalThis.__sa_jsnet;
                \\  __sa_store_i64(out_handle, 0n);
                \\  return -1;
                \\}
                \\
            );
            return;
        }
        if (std.mem.eql(u8, fsig.name, "sa_std_tls_shaped_session_blob")) {
            try writer.writeAll(
                \\function sa_std_tls_shaped_session_blob(handle, out_handle) {
                \\  const J = globalThis.__sa_jsnet;
                \\  __sa_store_i64(out_handle, 0n);
                \\  return -1;
                \\}
                \\
            );
            return;
        }
        if (std.mem.eql(u8, fsig.name, "sa_std_tls_shaped_peer_cert_chain_json")) {
            try writer.writeAll(
                \\function sa_std_tls_shaped_peer_cert_chain_json(handle, out_handle) {
                \\  const J = globalThis.__sa_jsnet;
                \\  __sa_store_i64(out_handle, 0n);
                \\  return -1;
                \\}
                \\
            );
            return;
        }
        if (std.mem.eql(u8, fsig.name, "sa_std_tls_shaped_buffer_data")) {
            try writer.writeAll(
                \\function sa_std_tls_shaped_buffer_data(buffer) {
                \\  const J = globalThis.__sa_jsnet;
                \\  return 0;
                \\}
                \\
            );
            return;
        }
        if (std.mem.eql(u8, fsig.name, "sa_std_tls_shaped_buffer_len")) {
            try writer.writeAll(
                \\function sa_std_tls_shaped_buffer_len(buffer) {
                \\  const J = globalThis.__sa_jsnet;
                \\  return 0n;
                \\}
                \\
            );
            return;
        }
        if (std.mem.eql(u8, fsig.name, "sa_std_tls_shaped_buffer_free")) {
            try writer.writeAll(
                \\function sa_std_tls_shaped_buffer_free(buffer) {
                \\  const J = globalThis.__sa_jsnet;
                \\  return -22;
                \\}
                \\
            );
            return;
        }
        if (std.mem.eql(u8, fsig.name, "sa_std_net_to_socket_addr_first")) {
            try writer.writeAll(
                \\function sa_std_net_to_socket_addr_first(host, host_len, port, out_handle) {
                \\  const J = globalThis.__sa_jsnet;
                \\  function addrFromWorker(a, port) {
                \\    return { kind: "addr", host: a.host, port: port, family: (a.family === 4 || a.family === "IPv4") ? 2 : 10, scopeId: 0 };
                \\  }
                \\  __sa_store_i64(out_handle, 0n);
                \\  const h = J.bToStr(__sa_mem_bytes(host, host_len));
                \\  const r = J.bridgeCall("resolve", { host: h }, null, false);
                \\  if (r.status !== 0) return r.status;
                \\  if (!r.json.addrs || r.json.addrs.length === 0) return 7;
                \\  const a = addrFromWorker(r.json.addrs[0], __sa_num(port));
                \\  __sa_store_i64(out_handle, BigInt(J.netReg(a)));
                \\  return 0;
                \\}
                \\
            );
            return;
        }
        if (std.mem.eql(u8, fsig.name, "sa_std_net_to_socket_addr_list")) {
            try writer.writeAll(
                \\function sa_std_net_to_socket_addr_list(host, host_len, port, out_handle) {
                \\  const J = globalThis.__sa_jsnet;
                \\  function addrFromWorker(a, port) {
                \\    return { kind: "addr", host: a.host, port: port, family: (a.family === 4 || a.family === "IPv4") ? 2 : 10, scopeId: 0 };
                \\  }
                \\  __sa_store_i64(out_handle, 0n);
                \\  const h = J.bToStr(__sa_mem_bytes(host, host_len));
                \\  const r = J.bridgeCall("resolve", { host: h }, null, false);
                \\  if (r.status !== 0) return r.status;
                \\  const addrs = (r.json.addrs || []).map((a) => addrFromWorker(a, __sa_num(port)));
                \\  __sa_store_i64(out_handle, BigInt(J.netReg({ kind: "addrlist", addrs: addrs, idx: 0 })));
                \\  return 0;
                \\}
                \\
            );
            return;
        }
        if (std.mem.eql(u8, fsig.name, "sa_std_net_addr_list_next")) {
            try writer.writeAll(
                \\function sa_std_net_addr_list_next(list, out_ok, out_addr) {
                \\  const J = globalThis.__sa_jsnet;
                \\  __sa_store_i32(out_ok, 0);
                \\  __sa_store_i64(out_addr, 0n);
                \\  const l = J.netGet(__sa_num(list));
                \\  if (!l || l.kind !== "addrlist") return 2;
                \\  if (l.idx >= l.addrs.length) return 0;
                \\  const a = l.addrs[l.idx++];
                \\  __sa_store_i32(out_ok, 1);
                \\  __sa_store_i64(out_addr, BigInt(J.netReg(a)));
                \\  return 0;
                \\}
                \\
            );
            return;
        }
        if (std.mem.eql(u8, fsig.name, "sa_std_net_addr_list_remaining")) {
            try writer.writeAll(
                \\function sa_std_net_addr_list_remaining(list, out_remaining) {
                \\  const J = globalThis.__sa_jsnet;
                \\  __sa_store_i64(out_remaining, 0n);
                \\  const l = J.netGet(__sa_num(list));
                \\  if (!l || l.kind !== "addrlist") return 2;
                \\  __sa_store_i64(out_remaining, BigInt(l.addrs.length - l.idx));
                \\  return 0;
                \\}
                \\
            );
            return;
        }
        if (std.mem.eql(u8, fsig.name, "sa_std_net_addr_list_reset")) {
            try writer.writeAll(
                \\function sa_std_net_addr_list_reset(list) {
                \\  const J = globalThis.__sa_jsnet;
                \\  const l = J.netGet(__sa_num(list));
                \\  if (!l || l.kind !== "addrlist") return 2;
                \\  l.idx = 0;
                \\  return 0;
                \\}
                \\
            );
            return;
        }
        if (std.mem.eql(u8, fsig.name, "sa_std_net_addr_list_free")) {
            try writer.writeAll(
                \\function sa_std_net_addr_list_free(list) {
                \\  const J = globalThis.__sa_jsnet;
                \\  return J.netDel(__sa_num(list)) ? 0 : 2;
                \\}
                \\
            );
            return;
        }
        if (std.mem.eql(u8, fsig.name, "sa_std_net_addr_reverse_lookup")) {
            try writer.writeAll(
                \\function sa_std_net_addr_reverse_lookup(addr, out, out_cap, out_len) {
                \\  const J = globalThis.__sa_jsnet;
                \\  __sa_store_i64(out_len, 0n);
                \\  const a = J.netGet(__sa_num(addr));
                \\  if (!a || a.kind !== "addr") return 2;
                \\  const r = J.bridgeCall("reverse", { host: a.host }, null, false);
                \\  if (r.status !== 0) return r.status;
                \\  const name = J.bFromStr(r.json.name);
                \\  const cap = __sa_num(out_cap);
                \\  const n = Math.min(cap, name.length);
                \\  __sa_u8.set(name.subarray(0, n), __sa_addr(out));
                \\  __sa_store_i64(out_len, BigInt(n));
                \\  return (n < name.length) ? 9 : 0;
                \\}
                \\
            );
            return;
        }
        if (std.mem.eql(u8, fsig.name, "sa_net_addr_host")) {
            try writer.writeAll(
                \\function sa_net_addr_host(addr) {
                \\  const J = globalThis.__sa_jsnet;
                \\  const a = J.netGet(__sa_num(addr));
                \\  if (!a || a.kind !== "addr") return 0;
                \\  const b = J.bFromStr(a.host);
                \\  const p = __sa_alloc(b.length);
                \\  __sa_u8.set(b, p);
                \\  return p;
                \\}
                \\
            );
            return;
        }
        if (std.mem.eql(u8, fsig.name, "sa_net_addr_host_len")) {
            try writer.writeAll(
                \\function sa_net_addr_host_len(addr) {
                \\  const J = globalThis.__sa_jsnet;
                \\  const a = J.netGet(__sa_num(addr));
                \\  if (!a || a.kind !== "addr") return 0n;
                \\  return BigInt(J.bFromStr(a.host).length);
                \\}
                \\
            );
            return;
        }
        if (std.mem.eql(u8, fsig.name, "sa_net_addr_port")) {
            try writer.writeAll(
                \\function sa_net_addr_port(addr) {
                \\  const J = globalThis.__sa_jsnet;
                \\  const a = J.netGet(__sa_num(addr));
                \\  if (!a || a.kind !== "addr") return 0;
                \\  return a.port;
                \\}
                \\
            );
            return;
        }
        if (std.mem.eql(u8, fsig.name, "sa_net_addr_family")) {
            try writer.writeAll(
                \\function sa_net_addr_family(addr) {
                \\  const J = globalThis.__sa_jsnet;
                \\  const a = J.netGet(__sa_num(addr));
                \\  if (!a || a.kind !== "addr") return 0;
                \\  return a.family;
                \\}
                \\
            );
            return;
        }
        if (std.mem.eql(u8, fsig.name, "sa_net_addr_scope_id")) {
            try writer.writeAll(
                \\function sa_net_addr_scope_id(addr) {
                \\  const J = globalThis.__sa_jsnet;
                \\  const a = J.netGet(__sa_num(addr));
                \\  if (!a || a.kind !== "addr") return 0n;
                \\  return BigInt(a.scopeId);
                \\}
                \\
            );
            return;
        }
        if (std.mem.eql(u8, fsig.name, "sa_net_addr_free")) {
            try writer.writeAll(
                \\function sa_net_addr_free(addr) {
                \\  const J = globalThis.__sa_jsnet;
                \\  return J.netDel(__sa_num(addr)) ? 0 : 2;
                \\}
                \\
            );
            return;
        }
        if (std.mem.eql(u8, fsig.name, "sa_std_net_addr_format")) {
            try writer.writeAll(
                \\function sa_std_net_addr_format(addr, out, out_cap, out_len) {
                \\  const J = globalThis.__sa_jsnet;
                \\  __sa_store_i64(out_len, 0n);
                \\  const a = J.netGet(__sa_num(addr));
                \\  if (!a || a.kind !== "addr") return 2;
                \\  const text = (a.family === 10) ? "[" + a.host + "]:" + a.port : a.host + ":" + a.port;
                \\  const b = J.bFromStr(text);
                \\  const cap = __sa_num(out_cap);
                \\  const n = Math.min(cap, b.length);
                \\  __sa_u8.set(b.subarray(0, n), __sa_addr(out));
                \\  __sa_store_i64(out_len, BigInt(n));
                \\  return (n < b.length) ? 9 : 0;
                \\}
                \\
            );
            return;
        }
        if (std.mem.eql(u8, fsig.name, "sa_std_net_udp_bind")) {
            try writer.writeAll(
                \\function sa_std_net_udp_bind(host, host_len, port, out_handle) {
                \\  const J = globalThis.__sa_jsnet;
                \\  __sa_store_i64(out_handle, 0n);
                \\  const h = J.bToStr(__sa_mem_bytes(host, host_len));
                \\  const r = J.bridgeCall("udp_bind", { host: h, port: __sa_num(port) }, null, false);
                \\  if (r.status !== 0) return r.status;
                \\  const e = { kind: "udp", bridgeId: r.json.id, localHost: r.json.host, localPort: r.json.port,
                \\    localFamily: (r.json.family === "IPv4" || r.json.family === 4) ? 2 : 10,
                \\    readTimeoutMs: 0, writeTimeoutMs: 0, opts: new Map() };
                \\  __sa_store_i64(out_handle, BigInt(J.netReg(e)));
                \\  return 0;
                \\}
                \\
            );
            return;
        }
        if (std.mem.eql(u8, fsig.name, "sa_std_net_udp_local_addr")) {
            try writer.writeAll(
                \\function sa_std_net_udp_local_addr(socket, out_handle) {
                \\  const J = globalThis.__sa_jsnet;
                \\  __sa_store_i64(out_handle, 0n);
                \\  const e = J.netGet(__sa_num(socket));
                \\  if (!e || e.kind !== "udp") return 2;
                \\  const a = { kind: "addr", host: e.localHost, port: e.localPort, family: e.localFamily, scopeId: 0 };
                \\  __sa_store_i64(out_handle, BigInt(J.netReg(a)));
                \\  return 0;
                \\}
                \\
            );
            return;
        }
        if (std.mem.eql(u8, fsig.name, "sa_std_net_udp_connect")) {
            try writer.writeAll(
                \\function sa_std_net_udp_connect(socket, host, host_len, port) {
                \\  const J = globalThis.__sa_jsnet;
                \\  const e = J.netGet(__sa_num(socket));
                \\  if (!e || e.kind !== "udp") return 2;
                \\  const h = J.bToStr(__sa_mem_bytes(host, host_len));
                \\  const r = J.bridgeCall("udp_connect", { id: e.bridgeId, host: h, port: __sa_num(port) }, null, false);
                \\  return r.status;
                \\}
                \\
            );
            return;
        }
        if (std.mem.eql(u8, fsig.name, "sa_std_net_udp_connect_addr")) {
            try writer.writeAll(
                \\function sa_std_net_udp_connect_addr(socket, addr) {
                \\  const J = globalThis.__sa_jsnet;
                \\  const e = J.netGet(__sa_num(socket));
                \\  const a = J.netGet(__sa_num(addr));
                \\  if (!e || e.kind !== "udp" || !a || a.kind !== "addr") return 2;
                \\  const r = J.bridgeCall("udp_connect", { id: e.bridgeId, host: a.host, port: a.port }, null, false);
                \\  return r.status;
                \\}
                \\
            );
            return;
        }
        if (std.mem.eql(u8, fsig.name, "sa_std_net_udp_set_read_timeout")) {
            try writer.writeAll(
                \\function sa_std_net_udp_set_read_timeout(socket, timeout_ns) {
                \\  const J = globalThis.__sa_jsnet;
                \\  const e = J.netGet(__sa_num(socket));
                \\  if (!e || e.kind !== "udp") return 2;
                \\  const ms = __sa_num(timeout_ns) / 1000000;
                \\  e.readTimeoutMs = ms;
                \\  const r = J.bridgeCall("udp_set_read_timeout", { id: e.bridgeId, timeoutMs: ms }, null, false);
                \\  return r.status;
                \\}
                \\
            );
            return;
        }
        if (std.mem.eql(u8, fsig.name, "sa_std_net_udp_set_write_timeout")) {
            try writer.writeAll(
                \\function sa_std_net_udp_set_write_timeout(socket, timeout_ns) {
                \\  const J = globalThis.__sa_jsnet;
                \\  const e = J.netGet(__sa_num(socket));
                \\  if (!e || e.kind !== "udp") return 2;
                \\  e.writeTimeoutMs = __sa_num(timeout_ns) / 1000000;
                \\  return 0;
                \\}
                \\
            );
            return;
        }
        if (std.mem.eql(u8, fsig.name, "sa_std_net_udp_set_broadcast")) {
            try writer.writeAll(
                \\function sa_std_net_udp_set_broadcast(socket, enabled) {
                \\  const J = globalThis.__sa_jsnet;
                \\  const e = J.netGet(__sa_num(socket));
                \\  if (!e || e.kind !== "udp") return 2;
                \\  const r = J.bridgeCall("udp_set_broadcast", { id: e.bridgeId, enabled: __sa_num(enabled) }, null, false);
                \\  if (r.status !== 0) return r.status;
                \\  e.opts.set("1:6", __sa_num(enabled) !== 0 ? 1 : 0);
                \\  return 0;
                \\}
                \\
            );
            return;
        }
        if (std.mem.eql(u8, fsig.name, "sa_std_net_udp_broadcast")) {
            try writer.writeAll(
                \\function sa_std_net_udp_broadcast(socket, out_enabled) {
                \\  const J = globalThis.__sa_jsnet;
                \\  __sa_store_i32(out_enabled, 0);
                \\  const e = J.netGet(__sa_num(socket));
                \\  if (!e || e.kind !== "udp") return 2;
                \\  const v = e.opts.get("1:6");
                \\  if (v === undefined) return 8;
                \\  __sa_store_i32(out_enabled, v);
                \\  return 0;
                \\}
                \\
            );
            return;
        }
        if (std.mem.eql(u8, fsig.name, "sa_std_net_udp_set_ttl")) {
            try writer.writeAll(
                \\function sa_std_net_udp_set_ttl(socket, ttl) {
                \\  const J = globalThis.__sa_jsnet;
                \\  const e = J.netGet(__sa_num(socket));
                \\  if (!e || e.kind !== "udp") return 2;
                \\  const r = J.bridgeCall("udp_set_ttl", { id: e.bridgeId, ttl: __sa_num(ttl) }, null, false);
                \\  if (r.status !== 0) return r.status;
                \\  e.opts.set("0:2", __sa_num(ttl));
                \\  return 0;
                \\}
                \\
            );
            return;
        }
        if (std.mem.eql(u8, fsig.name, "sa_std_net_udp_ttl")) {
            try writer.writeAll(
                \\function sa_std_net_udp_ttl(socket, out_ttl) {
                \\  const J = globalThis.__sa_jsnet;
                \\  __sa_store_u32(out_ttl, 0);
                \\  const e = J.netGet(__sa_num(socket));
                \\  if (!e || e.kind !== "udp") return 2;
                \\  const v = e.opts.get("0:2");
                \\  if (v === undefined) return 8;
                \\  __sa_store_u32(out_ttl, v);
                \\  return 0;
                \\}
                \\
            );
            return;
        }
        if (std.mem.eql(u8, fsig.name, "sa_std_net_udp_set_multicast_loop_v4")) {
            try writer.writeAll(
                \\function sa_std_net_udp_set_multicast_loop_v4(socket, enabled) {
                \\  const J = globalThis.__sa_jsnet;
                \\  const e = J.netGet(__sa_num(socket));
                \\  if (!e || e.kind !== "udp") return 2;
                \\  const r = J.bridgeCall("udp_set_multicast_loop", { id: e.bridgeId, enabled: __sa_num(enabled) }, null, false);
                \\  if (r.status !== 0) return r.status;
                \\  e.opts.set("0:34", __sa_num(enabled) !== 0 ? 1 : 0);
                \\  return 0;
                \\}
                \\
            );
            return;
        }
        if (std.mem.eql(u8, fsig.name, "sa_std_net_udp_set_multicast_ttl_v4")) {
            try writer.writeAll(
                \\function sa_std_net_udp_set_multicast_ttl_v4(socket, ttl) {
                \\  const J = globalThis.__sa_jsnet;
                \\  const e = J.netGet(__sa_num(socket));
                \\  if (!e || e.kind !== "udp") return 2;
                \\  const r = J.bridgeCall("udp_set_multicast_ttl", { id: e.bridgeId, ttl: __sa_num(ttl) }, null, false);
                \\  if (r.status !== 0) return r.status;
                \\  e.opts.set("0:33", __sa_num(ttl));
                \\  return 0;
                \\}
                \\
            );
            return;
        }
        if (std.mem.eql(u8, fsig.name, "sa_std_net_udp_set_multicast_loop_v6")) {
            try writer.writeAll(
                \\function sa_std_net_udp_set_multicast_loop_v6(socket, enabled) {
                \\  const J = globalThis.__sa_jsnet;
                \\  // No Node API for IPv6 multicast loop on a bound socket: explicit UNSUPPORTED.
                \\  const e = J.netGet(__sa_num(socket));
                \\  if (!e || e.kind !== "udp") return 2;
                \\  return 8;
                \\}
                \\
            );
            return;
        }
        if (std.mem.eql(u8, fsig.name, "sa_std_net_udp_set_multicast_hops_v6")) {
            try writer.writeAll(
                \\function sa_std_net_udp_set_multicast_hops_v6(socket, hops) {
                \\  const J = globalThis.__sa_jsnet;
                \\  // No Node API for IPv6 multicast hops on a bound socket: explicit UNSUPPORTED.
                \\  const e = J.netGet(__sa_num(socket));
                \\  if (!e || e.kind !== "udp") return 2;
                \\  return 8;
                \\}
                \\
            );
            return;
        }
        if (std.mem.eql(u8, fsig.name, "sa_std_net_udp_set_only_v6")) {
            try writer.writeAll(
                \\function sa_std_net_udp_set_only_v6(socket, enabled) {
                \\  const J = globalThis.__sa_jsnet;
                \\  // Socket family is fixed at bind time; it cannot change afterwards.
                \\  const e = J.netGet(__sa_num(socket));
                \\  if (!e || e.kind !== "udp") return 2;
                \\  return 8;
                \\}
                \\
            );
            return;
        }
        if (std.mem.eql(u8, fsig.name, "sa_std_net_udp_set_nonblocking")) {
            try writer.writeAll(
                \\function sa_std_net_udp_set_nonblocking(socket, enabled) {
                \\  const J = globalThis.__sa_jsnet;
                \\  // The bridge model is blocking-only (worker queue + Atomics.wait).
                \\  const e = J.netGet(__sa_num(socket));
                \\  if (!e || e.kind !== "udp") return 2;
                \\  return 8;
                \\}
                \\
            );
            return;
        }
        if (std.mem.eql(u8, fsig.name, "sa_std_net_udp_send")) {
            try writer.writeAll(
                \\function sa_std_net_udp_send(socket, buf, len, out_written) {
                \\  const J = globalThis.__sa_jsnet;
                \\  __sa_store_i64(out_written, 0n);
                \\  const e = J.netGet(__sa_num(socket));
                \\  if (!e || e.kind !== "udp") return 2;
                \\  const payload = __sa_mem_bytes(buf, len);
                \\  const r = J.bridgeCall("udp_send", { id: e.bridgeId }, payload, false);
                \\  if (r.status !== 0) return r.status;
                \\  __sa_store_i64(out_written, BigInt(r.json.written || 0));
                \\  return 0;
                \\}
                \\
            );
            return;
        }
        if (std.mem.eql(u8, fsig.name, "sa_std_net_udp_send_to")) {
            try writer.writeAll(
                \\function sa_std_net_udp_send_to(socket, buf, len, host, host_len, port, out_written) {
                \\  const J = globalThis.__sa_jsnet;
                \\  __sa_store_i64(out_written, 0n);
                \\  const e = J.netGet(__sa_num(socket));
                \\  if (!e || e.kind !== "udp") return 2;
                \\  const payload = __sa_mem_bytes(buf, len);
                \\  const h = J.bToStr(__sa_mem_bytes(host, host_len));
                \\  const r = J.bridgeCall("udp_send", { id: e.bridgeId, dest: { host: h, port: __sa_num(port) } }, payload, false);
                \\  if (r.status !== 0) return r.status;
                \\  __sa_store_i64(out_written, BigInt(r.json.written || 0));
                \\  return 0;
                \\}
                \\
            );
            return;
        }
        if (std.mem.eql(u8, fsig.name, "sa_std_net_udp_recv")) {
            try writer.writeAll(
                \\function sa_std_net_udp_recv(socket, buf, cap, out_read) {
                \\  const J = globalThis.__sa_jsnet;
                \\  __sa_store_i64(out_read, 0n);
                \\  const e = J.netGet(__sa_num(socket));
                \\  if (!e || e.kind !== "udp") return 2;
                \\  const r = J.bridgeCall("udp_recv", { id: e.bridgeId, cap: __sa_num(cap) }, null, false);
                \\  if (r.status !== 0) return r.status;
                \\  if (r.bytes) __sa_u8.set(r.bytes, __sa_addr(buf));
                \\  __sa_store_i64(out_read, BigInt(r.json.read || 0));
                \\  return 0;
                \\}
                \\
            );
            return;
        }
        if (std.mem.eql(u8, fsig.name, "sa_std_net_udp_recv_from")) {
            try writer.writeAll(
                \\function sa_std_net_udp_recv_from(socket, buf, cap, out_read, out_addr) {
                \\  const J = globalThis.__sa_jsnet;
                \\  __sa_store_i64(out_read, 0n);
                \\  __sa_store_i64(out_addr, 0n);
                \\  const e = J.netGet(__sa_num(socket));
                \\  if (!e || e.kind !== "udp") return 2;
                \\  const r = J.bridgeCall("udp_recv", { id: e.bridgeId, cap: __sa_num(cap) }, null, false);
                \\  if (r.status !== 0) return r.status;
                \\  if (r.bytes) __sa_u8.set(r.bytes, __sa_addr(buf));
                \\  __sa_store_i64(out_read, BigInt(r.json.read || 0));
                \\  const s = r.json.src;
                \\  const a = { kind: "addr", host: s.host, port: s.port, family: (s.family === "IPv4" || s.family === 4) ? 2 : 10, scopeId: 0 };
                \\  __sa_store_i64(out_addr, BigInt(J.netReg(a)));
                \\  return 0;
                \\}
                \\
            );
            return;
        }
        if (std.mem.eql(u8, fsig.name, "sa_std_net_tcp_connect")) {
            try writer.writeAll(
                \\function sa_std_net_tcp_connect(host, host_len, port, out_handle) {
                \\  const J = globalThis.__sa_jsnet;
                \\  __sa_store_i64(out_handle, 0n);
                \\  const h = J.bToStr(__sa_mem_bytes(host, host_len));
                \\  const r = J.bridgeCall("tcp_connect", { host: h, port: __sa_num(port), timeoutMs: 0 }, null, false);
                \\  if (r.status !== 0) return r.status;
                \\  const e = { kind: "tcp", bridgeId: r.json.id, localHost: r.json.local.host, localPort: r.json.local.port,
                \\    peerHost: r.json.peer.host, peerPort: r.json.peer.port,
                \\    readTimeoutMs: 0, writeTimeoutMs: 0, opts: new Map() };
                \\  __sa_store_i64(out_handle, BigInt(J.netReg(e)));
                \\  return 0;
                \\}
                \\
            );
            return;
        }
        if (std.mem.eql(u8, fsig.name, "sa_std_net_tcp_connect_timeout")) {
            try writer.writeAll(
                \\function sa_std_net_tcp_connect_timeout(host, host_len, port, timeout_ns, out_handle) {
                \\  const J = globalThis.__sa_jsnet;
                \\  __sa_store_i64(out_handle, 0n);
                \\  const h = J.bToStr(__sa_mem_bytes(host, host_len));
                \\  const r = J.bridgeCall("tcp_connect", { host: h, port: __sa_num(port), timeoutMs: __sa_num(timeout_ns) / 1000000 }, null, false);
                \\  if (r.status !== 0) return r.status;
                \\  const e = { kind: "tcp", bridgeId: r.json.id, localHost: r.json.local.host, localPort: r.json.local.port,
                \\    peerHost: r.json.peer.host, peerPort: r.json.peer.port,
                \\    readTimeoutMs: 0, writeTimeoutMs: 0, opts: new Map() };
                \\  __sa_store_i64(out_handle, BigInt(J.netReg(e)));
                \\  return 0;
                \\}
                \\
            );
            return;
        }
        if (std.mem.eql(u8, fsig.name, "sa_std_net_tcp_connect_timeout_addr")) {
            try writer.writeAll(
                \\function sa_std_net_tcp_connect_timeout_addr(addr, timeout_ns, out_handle) {
                \\  const J = globalThis.__sa_jsnet;
                \\  __sa_store_i64(out_handle, 0n);
                \\  const a = J.netGet(__sa_num(addr));
                \\  if (!a || a.kind !== "addr") return 2;
                \\  const r = J.bridgeCall("tcp_connect", { host: a.host, port: a.port, timeoutMs: __sa_num(timeout_ns) / 1000000 }, null, false);
                \\  if (r.status !== 0) return r.status;
                \\  const e = { kind: "tcp", bridgeId: r.json.id, localHost: r.json.local.host, localPort: r.json.local.port,
                \\    peerHost: r.json.peer.host, peerPort: r.json.peer.port,
                \\    readTimeoutMs: 0, writeTimeoutMs: 0, opts: new Map() };
                \\  __sa_store_i64(out_handle, BigInt(J.netReg(e)));
                \\  return 0;
                \\}
                \\
            );
            return;
        }
        if (std.mem.eql(u8, fsig.name, "sa_std_net_tcp_connect_timeout_all")) {
            try writer.writeAll(
                \\function sa_std_net_tcp_connect_timeout_all(host, host_len, port, timeout_ns, out_handle) {
                \\  const J = globalThis.__sa_jsnet;
                \\  // Best-effort alias of connect_timeout: Node resolves and tries the
                \\  // address family selection itself (autoSelectFamily).
                \\  __sa_store_i64(out_handle, 0n);
                \\  const h = J.bToStr(__sa_mem_bytes(host, host_len));
                \\  const r = J.bridgeCall("tcp_connect", { host: h, port: __sa_num(port), timeoutMs: __sa_num(timeout_ns) / 1000000 }, null, false);
                \\  if (r.status !== 0) return r.status;
                \\  const e = { kind: "tcp", bridgeId: r.json.id, localHost: r.json.local.host, localPort: r.json.local.port,
                \\    peerHost: r.json.peer.host, peerPort: r.json.peer.port,
                \\    readTimeoutMs: 0, writeTimeoutMs: 0, opts: new Map() };
                \\  __sa_store_i64(out_handle, BigInt(J.netReg(e)));
                \\  return 0;
                \\}
                \\
            );
            return;
        }
        if (std.mem.eql(u8, fsig.name, "sa_std_net_tcp_stream_read")) {
            try writer.writeAll(
                \\function sa_std_net_tcp_stream_read(stream, buf, cap, out_read) {
                \\  const J = globalThis.__sa_jsnet;
                \\  __sa_store_i64(out_read, 0n);
                \\  const e = J.netGet(__sa_num(stream));
                \\  if (!e || (e.kind !== "tcp" && e.kind !== "tls")) return 2;
                \\  const r = J.bridgeCall("stream_read", { id: e.bridgeId, cap: __sa_num(cap) }, null, false);
                \\  if (r.status !== 0) return r.status;
                \\  if (r.bytes) __sa_u8.set(r.bytes, __sa_addr(buf));
                \\  __sa_store_i64(out_read, BigInt(r.json.read || 0));
                \\  return 0;
                \\}
                \\
            );
            return;
        }
        if (std.mem.eql(u8, fsig.name, "sa_std_net_tcp_stream_write")) {
            try writer.writeAll(
                \\function sa_std_net_tcp_stream_write(stream, buf, len, out_written) {
                \\  const J = globalThis.__sa_jsnet;
                \\  __sa_store_i64(out_written, 0n);
                \\  const e = J.netGet(__sa_num(stream));
                \\  if (!e || (e.kind !== "tcp" && e.kind !== "tls")) return 2;
                \\  const payload = __sa_mem_bytes(buf, len);
                \\  const r = J.bridgeCall("stream_write", { id: e.bridgeId }, payload, false);
                \\  if (r.status !== 0) return r.status;
                \\  __sa_store_i64(out_written, BigInt(r.json.written || 0));
                \\  return 0;
                \\}
                \\
            );
            return;
        }
        if (std.mem.eql(u8, fsig.name, "sa_std_net_tcp_stream_set_read_timeout")) {
            try writer.writeAll(
                \\function sa_std_net_tcp_stream_set_read_timeout(stream, timeout_ns) {
                \\  const J = globalThis.__sa_jsnet;
                \\  const e = J.netGet(__sa_num(stream));
                \\  if (!e || (e.kind !== "tcp" && e.kind !== "tls")) return 2;
                \\  const ms = __sa_num(timeout_ns) / 1000000;
                \\  e.readTimeoutMs = ms;
                \\  const r = J.bridgeCall("stream_set_read_timeout", { id: e.bridgeId, timeoutMs: ms }, null, false);
                \\  return r.status;
                \\}
                \\
            );
            return;
        }
        if (std.mem.eql(u8, fsig.name, "sa_std_net_tcp_stream_set_write_timeout")) {
            try writer.writeAll(
                \\function sa_std_net_tcp_stream_set_write_timeout(stream, timeout_ns) {
                \\  const J = globalThis.__sa_jsnet;
                \\  const e = J.netGet(__sa_num(stream));
                \\  if (!e || (e.kind !== "tcp" && e.kind !== "tls")) return 2;
                \\  const ms = __sa_num(timeout_ns) / 1000000;
                \\  e.writeTimeoutMs = ms;
                \\  const r = J.bridgeCall("stream_set_write_timeout", { id: e.bridgeId, timeoutMs: ms }, null, false);
                \\  return r.status;
                \\}
                \\
            );
            return;
        }
        if (std.mem.eql(u8, fsig.name, "sa_std_net_tcp_stream_read_timeout")) {
            try writer.writeAll(
                \\function sa_std_net_tcp_stream_read_timeout(stream, out_timeout_ns) {
                \\  const J = globalThis.__sa_jsnet;
                \\  __sa_store_i64(out_timeout_ns, 0n);
                \\  const e = J.netGet(__sa_num(stream));
                \\  if (!e || (e.kind !== "tcp" && e.kind !== "tls")) return 2;
                \\  __sa_store_i64(out_timeout_ns, BigInt(Math.round(e.readTimeoutMs * 1000000)));
                \\  return 0;
                \\}
                \\
            );
            return;
        }
        if (std.mem.eql(u8, fsig.name, "sa_std_net_tcp_stream_write_timeout")) {
            try writer.writeAll(
                \\function sa_std_net_tcp_stream_write_timeout(stream, out_timeout_ns) {
                \\  const J = globalThis.__sa_jsnet;
                \\  __sa_store_i64(out_timeout_ns, 0n);
                \\  const e = J.netGet(__sa_num(stream));
                \\  if (!e || (e.kind !== "tcp" && e.kind !== "tls")) return 2;
                \\  __sa_store_i64(out_timeout_ns, BigInt(Math.round(e.writeTimeoutMs * 1000000)));
                \\  return 0;
                \\}
                \\
            );
            return;
        }
        if (std.mem.eql(u8, fsig.name, "sa_std_net_tcp_stream_set_nodelay")) {
            try writer.writeAll(
                \\function sa_std_net_tcp_stream_set_nodelay(stream, enabled) {
                \\  const J = globalThis.__sa_jsnet;
                \\  const e = J.netGet(__sa_num(stream));
                \\  if (!e || e.kind !== "tcp") return 2;
                \\  const r = J.bridgeCall("tcp_set_nodelay", { id: e.bridgeId, enabled: __sa_num(enabled) }, null, false);
                \\  if (r.status !== 0) return r.status;
                \\  e.opts.set("6:1", __sa_num(enabled) !== 0 ? 1 : 0);
                \\  return 0;
                \\}
                \\
            );
            return;
        }
        if (std.mem.eql(u8, fsig.name, "sa_std_net_tcp_stream_set_keepalive")) {
            try writer.writeAll(
                \\function sa_std_net_tcp_stream_set_keepalive(stream, enabled) {
                \\  const J = globalThis.__sa_jsnet;
                \\  const e = J.netGet(__sa_num(stream));
                \\  if (!e || e.kind !== "tcp") return 2;
                \\  const r = J.bridgeCall("tcp_set_keepalive", { id: e.bridgeId, enabled: __sa_num(enabled) }, null, false);
                \\  if (r.status !== 0) return r.status;
                \\  e.opts.set("1:9", __sa_num(enabled) !== 0 ? 1 : 0);
                \\  return 0;
                \\}
                \\
            );
            return;
        }
        if (std.mem.eql(u8, fsig.name, "sa_std_net_socket_setsockopt")) {
            try writer.writeAll(
                \\function sa_std_net_socket_setsockopt(handle, level, optname, value, value_len) {
                \\  const J = globalThis.__sa_jsnet;
                \\  function sockoptApply(e, level, optname, value) {
                \\    const key = level + ":" + optname;
                \\    if (level === 1 && optname === 3) return 8;
                \\    const opmap = { "1:6": "udp_set_broadcast", "0:2": "udp_set_ttl", "0:33": "udp_set_multicast_ttl", "0:34": "udp_set_multicast_loop", "6:1": "tcp_set_nodelay", "1:9": "tcp_set_keepalive" };
                \\    const op = opmap[key];
                \\    if (!op) return 8;
                \\    if (op === "udp_set_broadcast" || op === "udp_set_multicast_loop" || op === "tcp_set_keepalive") {
                \\      if (e.kind !== "udp" && op !== "tcp_set_keepalive") return 8;
                \\      if (op === "tcp_set_keepalive" && e.kind !== "tcp") return 8;
                \\      const r = J.bridgeCall(op, { id: e.bridgeId, enabled: value }, null, false);
                \\      if (r.status !== 0) return r.status;
                \\    } else if (op === "tcp_set_nodelay") {
                \\      if (e.kind !== "tcp") return 8;
                \\      const r = J.bridgeCall(op, { id: e.bridgeId, enabled: value }, null, false);
                \\      if (r.status !== 0) return r.status;
                \\    } else {
                \\      if (e.kind !== "udp") return 8;
                \\      const field = (op === "udp_set_ttl" || op === "udp_set_multicast_ttl") ? "ttl" : "enabled";
                \\      const params = { id: e.bridgeId }; params[field] = value;
                \\      const r = J.bridgeCall(op, params, null, false);
                \\      if (r.status !== 0) return r.status;
                \\    }
                \\    e.opts.set(key, value);
                \\    return 0;
                \\  }
                \\  function sockoptRead(e, level, optname) {
                \\    if (level === 1 && optname === 3) return e.kind === "udp" ? 2 : 1;
                \\    const v = e.opts.get(level + ":" + optname);
                \\    return (v === undefined) ? null : v;
                \\  }
                \\  const e = J.netGet(__sa_num(handle));
                \\  if (!e || (e.kind !== "udp" && e.kind !== "tcp")) return 2;
                \\  const lv = __sa_num(level), on = __sa_num(optname);
                \\  const bytes = __sa_mem_bytes(value, value_len);
                \\  if (bytes.length < 4) return 1;
                \\  const v = (bytes[0] | (bytes[1] << 8) | (bytes[2] << 16) | (bytes[3] << 24));
                \\  return sockoptApply(e, lv, on, v);
                \\}
                \\
            );
            return;
        }
        if (std.mem.eql(u8, fsig.name, "sa_std_net_socket_getsockopt")) {
            try writer.writeAll(
                \\function sa_std_net_socket_getsockopt(handle, level, optname, out, out_cap, out_len) {
                \\  const J = globalThis.__sa_jsnet;
                \\  function sockoptApply(e, level, optname, value) {
                \\    const key = level + ":" + optname;
                \\    if (level === 1 && optname === 3) return 8;
                \\    const opmap = { "1:6": "udp_set_broadcast", "0:2": "udp_set_ttl", "0:33": "udp_set_multicast_ttl", "0:34": "udp_set_multicast_loop", "6:1": "tcp_set_nodelay", "1:9": "tcp_set_keepalive" };
                \\    const op = opmap[key];
                \\    if (!op) return 8;
                \\    if (op === "udp_set_broadcast" || op === "udp_set_multicast_loop" || op === "tcp_set_keepalive") {
                \\      if (e.kind !== "udp" && op !== "tcp_set_keepalive") return 8;
                \\      if (op === "tcp_set_keepalive" && e.kind !== "tcp") return 8;
                \\      const r = J.bridgeCall(op, { id: e.bridgeId, enabled: value }, null, false);
                \\      if (r.status !== 0) return r.status;
                \\    } else if (op === "tcp_set_nodelay") {
                \\      if (e.kind !== "tcp") return 8;
                \\      const r = J.bridgeCall(op, { id: e.bridgeId, enabled: value }, null, false);
                \\      if (r.status !== 0) return r.status;
                \\    } else {
                \\      if (e.kind !== "udp") return 8;
                \\      const field = (op === "udp_set_ttl" || op === "udp_set_multicast_ttl") ? "ttl" : "enabled";
                \\      const params = { id: e.bridgeId }; params[field] = value;
                \\      const r = J.bridgeCall(op, params, null, false);
                \\      if (r.status !== 0) return r.status;
                \\    }
                \\    e.opts.set(key, value);
                \\    return 0;
                \\  }
                \\  function sockoptRead(e, level, optname) {
                \\    if (level === 1 && optname === 3) return e.kind === "udp" ? 2 : 1;
                \\    const v = e.opts.get(level + ":" + optname);
                \\    return (v === undefined) ? null : v;
                \\  }
                \\  __sa_store_i64(out_len, 0n);
                \\  const e = J.netGet(__sa_num(handle));
                \\  if (!e || (e.kind !== "udp" && e.kind !== "tcp")) return 2;
                \\  const v = sockoptRead(e, __sa_num(level), __sa_num(optname));
                \\  if (v === null) return 8;
                \\  const cap = __sa_num(out_cap);
                \\  if (cap < 4) return 9;
                \\  __sa_view.setInt32(__sa_addr(out), v, true);
                \\  __sa_store_i64(out_len, 4n);
                \\  return 0;
                \\}
                \\
            );
            return;
        }
        if (std.mem.eql(u8, fsig.name, "sa_std_net_socket_setsockopt_int")) {
            try writer.writeAll(
                \\function sa_std_net_socket_setsockopt_int(handle, level, optname, value) {
                \\  const J = globalThis.__sa_jsnet;
                \\  function sockoptApply(e, level, optname, value) {
                \\    const key = level + ":" + optname;
                \\    if (level === 1 && optname === 3) return 8;
                \\    const opmap = { "1:6": "udp_set_broadcast", "0:2": "udp_set_ttl", "0:33": "udp_set_multicast_ttl", "0:34": "udp_set_multicast_loop", "6:1": "tcp_set_nodelay", "1:9": "tcp_set_keepalive" };
                \\    const op = opmap[key];
                \\    if (!op) return 8;
                \\    if (op === "udp_set_broadcast" || op === "udp_set_multicast_loop" || op === "tcp_set_keepalive") {
                \\      if (e.kind !== "udp" && op !== "tcp_set_keepalive") return 8;
                \\      if (op === "tcp_set_keepalive" && e.kind !== "tcp") return 8;
                \\      const r = J.bridgeCall(op, { id: e.bridgeId, enabled: value }, null, false);
                \\      if (r.status !== 0) return r.status;
                \\    } else if (op === "tcp_set_nodelay") {
                \\      if (e.kind !== "tcp") return 8;
                \\      const r = J.bridgeCall(op, { id: e.bridgeId, enabled: value }, null, false);
                \\      if (r.status !== 0) return r.status;
                \\    } else {
                \\      if (e.kind !== "udp") return 8;
                \\      const field = (op === "udp_set_ttl" || op === "udp_set_multicast_ttl") ? "ttl" : "enabled";
                \\      const params = { id: e.bridgeId }; params[field] = value;
                \\      const r = J.bridgeCall(op, params, null, false);
                \\      if (r.status !== 0) return r.status;
                \\    }
                \\    e.opts.set(key, value);
                \\    return 0;
                \\  }
                \\  function sockoptRead(e, level, optname) {
                \\    if (level === 1 && optname === 3) return e.kind === "udp" ? 2 : 1;
                \\    const v = e.opts.get(level + ":" + optname);
                \\    return (v === undefined) ? null : v;
                \\  }
                \\  const e = J.netGet(__sa_num(handle));
                \\  if (!e || (e.kind !== "udp" && e.kind !== "tcp")) return 2;
                \\  return sockoptApply(e, __sa_num(level), __sa_num(optname), __sa_num(value));
                \\}
                \\
            );
            return;
        }
        if (std.mem.eql(u8, fsig.name, "sa_std_net_socket_getsockopt_int")) {
            try writer.writeAll(
                \\function sa_std_net_socket_getsockopt_int(handle, level, optname, out_value) {
                \\  const J = globalThis.__sa_jsnet;
                \\  function sockoptApply(e, level, optname, value) {
                \\    const key = level + ":" + optname;
                \\    if (level === 1 && optname === 3) return 8;
                \\    const opmap = { "1:6": "udp_set_broadcast", "0:2": "udp_set_ttl", "0:33": "udp_set_multicast_ttl", "0:34": "udp_set_multicast_loop", "6:1": "tcp_set_nodelay", "1:9": "tcp_set_keepalive" };
                \\    const op = opmap[key];
                \\    if (!op) return 8;
                \\    if (op === "udp_set_broadcast" || op === "udp_set_multicast_loop" || op === "tcp_set_keepalive") {
                \\      if (e.kind !== "udp" && op !== "tcp_set_keepalive") return 8;
                \\      if (op === "tcp_set_keepalive" && e.kind !== "tcp") return 8;
                \\      const r = J.bridgeCall(op, { id: e.bridgeId, enabled: value }, null, false);
                \\      if (r.status !== 0) return r.status;
                \\    } else if (op === "tcp_set_nodelay") {
                \\      if (e.kind !== "tcp") return 8;
                \\      const r = J.bridgeCall(op, { id: e.bridgeId, enabled: value }, null, false);
                \\      if (r.status !== 0) return r.status;
                \\    } else {
                \\      if (e.kind !== "udp") return 8;
                \\      const field = (op === "udp_set_ttl" || op === "udp_set_multicast_ttl") ? "ttl" : "enabled";
                \\      const params = { id: e.bridgeId }; params[field] = value;
                \\      const r = J.bridgeCall(op, params, null, false);
                \\      if (r.status !== 0) return r.status;
                \\    }
                \\    e.opts.set(key, value);
                \\    return 0;
                \\  }
                \\  function sockoptRead(e, level, optname) {
                \\    if (level === 1 && optname === 3) return e.kind === "udp" ? 2 : 1;
                \\    const v = e.opts.get(level + ":" + optname);
                \\    return (v === undefined) ? null : v;
                \\  }
                \\  __sa_store_i32(out_value, 0);
                \\  const e = J.netGet(__sa_num(handle));
                \\  if (!e || (e.kind !== "udp" && e.kind !== "tcp")) return 2;
                \\  const v = sockoptRead(e, __sa_num(level), __sa_num(optname));
                \\  if (v === null) return 8;
                \\  __sa_store_i32(out_value, v);
                \\  return 0;
                \\}
                \\
            );
            return;
        }
        if (std.mem.eql(u8, fsig.name, "sa_std_net_udp_recv_msg")) {
            try writer.writeAll(
                \\function sa_std_net_udp_recv_msg(socket, buf, cap, out_read, out_addr, out_dest_addr, out_ifindex, out_timestamp_ns, out_flags) {
                \\  const J = globalThis.__sa_jsnet;
                \\  // No pktinfo / SO_TIMESTAMP in Node: explicit UNSUPPORTED.
                \\  __sa_store_i64(out_read, 0n);
                \\  __sa_store_i64(out_addr, 0n);
                \\  __sa_store_i64(out_dest_addr, 0n);
                \\  __sa_store_i64(out_ifindex, 0n);
                \\  __sa_store_i64(out_timestamp_ns, 0n);
                \\  __sa_store_i64(out_flags, 0n);
                \\  const e = J.netGet(__sa_num(socket));
                \\  if (!e || e.kind !== "udp") return 2;
                \\  return 8;
                \\}
                \\
            );
            return;
        }
        if (std.mem.eql(u8, fsig.name, "sa_std_net_udp_recv_multi")) {
            try writer.writeAll(
                \\function sa_std_net_udp_recv_multi(socket, buf, buf_cap, slot_size, max_msgs, out_count, out_lens, out_addrs) {
                \\  const J = globalThis.__sa_jsnet;
                \\  // No recvmmsg in Node: explicit UNSUPPORTED.
                \\  __sa_store_i64(out_count, 0n);
                \\  const e = J.netGet(__sa_num(socket));
                \\  if (!e || e.kind !== "udp") return 2;
                \\  return 8;
                \\}
                \\
            );
            return;
        }
        if (std.mem.eql(u8, fsig.name, "sa_std_net_unix_datagram_peer_cred")) {
            try writer.writeAll(
                \\function sa_std_net_unix_datagram_peer_cred(socket, out_pid, out_uid, out_gid) {
                \\  const J = globalThis.__sa_jsnet;
                \\  // No peer-credentials API in Node: explicit UNSUPPORTED.
                \\  __sa_store_i64(out_pid, 0n);
                \\  __sa_store_i64(out_uid, 0n);
                \\  __sa_store_i64(out_gid, 0n);
                \\  const e = J.netGet(__sa_num(socket));
                \\  if (!e) return 2;
                \\  return 8;
                \\}
                \\
            );
            return;
        }
        if (std.mem.eql(u8, fsig.name, "sa_std_net_unix_stream_peer_cred")) {
            try writer.writeAll(
                \\function sa_std_net_unix_stream_peer_cred(stream, out_pid, out_uid, out_gid) {
                \\  const J = globalThis.__sa_jsnet;
                \\  // No peer-credentials API in Node: explicit UNSUPPORTED.
                \\  __sa_store_i64(out_pid, 0n);
                \\  __sa_store_i64(out_uid, 0n);
                \\  __sa_store_i64(out_gid, 0n);
                \\  const e = J.netGet(__sa_num(stream));
                \\  if (!e) return 2;
                \\  return 8;
                \\}
                \\
            );
            return;
        }
        if (std.mem.eql(u8, fsig.name, "sa_std_close")) {
            try writer.writeAll(
                \\function sa_std_close(handle) {
                \\  const J = globalThis.__sa_jsnet;
                \\  const e = J.netGet(__sa_num(handle));
                \\  if (!e) return 2;
                \\  if (e.bridgeId !== undefined && e.bridgeId !== null) J.bridgeCall("sock_close", { id: e.bridgeId }, null, false);
                \\  J.netDel(__sa_num(handle));
                \\  return 0;
                \\}
                \\
            );
            return;
        }
        if (std.mem.eql(u8, fsig.name, "sa_std_fd_into_raw")) {
            try writer.writeAll(
                \\function sa_std_fd_into_raw(handle, out_fd) {
                \\  const J = globalThis.__sa_jsnet;
                \\  __sa_store_i32(out_fd, 0);
                \\  const e = J.netGet(__sa_num(handle));
                \\  if (!e || e.kind !== "tcp") return 2;
                \\  // Detach: the SA handle is consumed; the bridge id moves to the
                \\  // detached table so start_tls can upgrade this socket in place.
                \\  const bid = e.bridgeId;
                \\  J.netDel(__sa_num(handle));
                \\  J.NET.detached.set(bid, true);
                \\  __sa_store_i32(out_fd, bid);
                \\  return 0;
                \\}
                \\
            );
            return;
        }
        if (std.mem.eql(u8, fsig.name, "sa_fs_read_buffer_data")) {
            try writer.writeAll(
                \\function sa_fs_read_buffer_data(buffer) {
                \\  const J = globalThis.__sa_jsnet;
                \\  const b = __sa_buf_get(buffer);
                \\  if (b === null) return 0;
                \\  const p = __sa_alloc(b.length);
                \\  __sa_u8.set(b, p);
                \\  return p;
                \\}
                \\
            );
            return;
        }
        if (std.mem.eql(u8, fsig.name, "sa_fs_read_buffer_len")) {
            try writer.writeAll(
                \\function sa_fs_read_buffer_len(buffer) {
                \\  const J = globalThis.__sa_jsnet;
                \\  const b = __sa_buf_get(buffer);
                \\  return b === null ? 0n : BigInt(b.length);
                \\}
                \\
            );
            return;
        }
        if (std.mem.eql(u8, fsig.name, "sa_fs_read_buffer_free")) {
            try writer.writeAll(
                \\function sa_fs_read_buffer_free(buffer) {
                \\  const J = globalThis.__sa_jsnet;
                \\  return __sa_buffers.delete(__sa_num(buffer)) ? 0 : 2;
                \\}
                \\
            );
            return;
        }
        if (std.mem.eql(u8, fsig.name, "sa_std_net_interface_addresses_json")) {
            try writer.writeAll(
                \\function sa_std_net_interface_addresses_json(out_handle) {
                \\  const J = globalThis.__sa_jsnet;
                \\  __sa_store_i64(out_handle, 0n);
                \\  const bytes = J.netinfoJson();
                \\  const h = __sa_buf_open(bytes);
                \\  __sa_store_i64(out_handle, h);
                \\  return 0;
                \\}
                \\
            );
            return;
        }
        // JS value-handle runtime builtins (see isJsHandleBuiltin).
        if (std.mem.eql(u8, fsig.name, "sa_js_value_release")) {
            try writer.writeAll(
                \\function sa_js_value_release(handle) {
                \\  return __sa_jsh_release(handle);
                \\}
                \\
            );
            return;
        }
        if (std.mem.eql(u8, fsig.name, "sa_js_make_callback")) {
            try writer.writeAll(
                \\function sa_js_make_callback(fn) {
                \\  return __sa_jsh_make_callback(fn);
                \\}
                \\
            );
            return;
        }
        if (std.mem.eql(u8, fsig.name, "sa_js_callback_poll")) {
            try writer.writeAll(
                \\function sa_js_callback_poll(fn_out, argc_out, args_out) {
                \\  return BigInt(__sa_jsh_cb_poll(fn_out, argc_out, args_out));
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
    // Error-context globals are per-build: they point into the current
    // build's verified module. Reset them at entry — a build that fails
    // before any function emission (e.g. in collectNpmImports) would
    // otherwise leave the cli error path printing a dangling slice
    // retained from a previous in-process build (observed as a
    // segfault in the js-matrix rejects test, which runs many builds
    // in one process).
    last_js_inst = "";
    last_js_func = "";
    var out: std.Io.Writer.Allocating = .init(allocator);
    errdefer out.deinit();
    const writer = &out.writer;
    // Indirect-call function table: every vtable slot target, deduped in order.
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
    // Emit the net runtime chunk once when the program declares any BP
    // net shim (cookie/tls/net-slice/netinfo). Programs without net
    // externs pay nothing for it.
    for (tasks) |task| {
        if (task.kind != .extern_decl) continue;
        const fsig = verified.function_sigs[task.fsig_index];
        if (isJsNetShim(fsig.name)) {
            try writer.writeAll(jsnet_runtime_js);
            try writer.writeAll("\n");
            break;
        }
    }
    // Emit the value-handle runtime chunk once when the program uses a
    // handle binding shape (ctor/method/get), a bytes-view modifier, a
    // string-out npm binding, or a handle runtime builtin.
    var need_handle_runtime = false;
    for (tasks) |task| {
        if (task.kind != .extern_decl) continue;
        const fsig = verified.function_sigs[task.fsig_index];
        if (isJsHandleBuiltin(fsig.name)) {
            need_handle_runtime = true;
            break;
        }
    }
    if (!need_handle_runtime) {
        outer: for (npm_imports) |item| {
            if (item.shape != .call or item.bytes_view != .none) {
                need_handle_runtime = true;
                break;
            }
            for (tasks) |task| {
                if (task.kind != .extern_decl) continue;
                const fsig = verified.function_sigs[task.fsig_index];
                if (std.mem.eql(u8, fsig.name, item.extern_name) and npmStrOut(fsig, item.shape)) {
                    need_handle_runtime = true;
                    break :outer;
                }
            }
        }
    }
    if (need_handle_runtime) {
        try writer.writeAll(jshandle_runtime_js);
        try writer.writeAll("\n");
    }

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
    var stub_emitted = std.StringHashMap(void).init(allocator);
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
        if (emitted.contains(fsig.name) or stub_emitted.contains(fsig.name)) continue;
        try emitOneFunction(writer, allocator, verified, task, &const_addrs, &fn_idx, js_opt, &retbase);
        try stub_emitted.put(fsig.name, {});
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
        var patched = std.array_list.Managed(u8).init(allocator);
        errdefer patched.deinit();
        try patched.appendSlice(final[0..pos]);
        try patched.print("{d}", .{mem_bytes});
        try patched.appendSlice(final[pos + needle.len ..]);
        const owned = try patched.toOwnedSlice();
        defer allocator.free(owned);
        const dir = std.fs.path.dirname(path);
        if (dir) |d| try sio.cwd().makePath(d);
        const f = try sio.cwd().createFile(path, .{});
        defer f.close();
        try f.writeAll(owned);
        return;
    }
    const dir = std.fs.path.dirname(path);
    if (dir) |d| try sio.cwd().makePath(d);
    const f = try sio.cwd().createFile(path, .{});
    defer f.close();
    try f.writeAll(final);
}

test "js ident sanitizes names" {
    var buf: [64]u8 = undefined;
    var fbs = std.Io.Writer.fixed(&buf);
    try jsIdent(&fbs, "hello-world.foo");
    try std.testing.expectEqualStrings("hello_world_foo", fbs.buffered());
}

test "js format parses esm and cjs" {
    try std.testing.expectEqual(JsFormat.esm, JsFormat.parse("esm").?);
    try std.testing.expectEqual(JsFormat.cjs, JsFormat.parse("cjs").?);
    try std.testing.expect(JsFormat.parse("bad") == null);
}
