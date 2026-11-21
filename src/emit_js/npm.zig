const std = @import("std");
const sig = @import("../common/signature.zig");
const FuncTask = @import("types.zig").FuncTask;
const JsEmitOptions = @import("types.zig").JsEmitOptions;
const JsEmitError = @import("types.zig").JsEmitError;
const jsIdent = @import("ident.zig").jsIdent;
const jsFuncName = @import("ident.zig").jsFuncName;

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
pub const NpmShape = enum { call, ctor, method, get };
pub const NpmBytesView = enum { none, u8, f32 };

pub const NpmImport = struct {
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
pub fn npmStrOut(fsig: sig.FunctionSig, shape: NpmShape) bool {
    if (shape == .ctor) return false;
    const params = fsig.params;
    if (params.len < 3) return false;
    const n = params.len;
    return params[n - 3].ty == .ptr and isNpmIntType(params[n - 2].ty) and
        params[n - 1].ty == .ptr and isNpmIntType(fsig.return_ty);
}

pub fn collectNpmImports(
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

pub fn npmImportFor(imports: []const NpmImport, extern_name: []const u8) ?NpmImport {
    for (imports) |item| {
        if (std.mem.eql(u8, item.extern_name, extern_name)) return item;
    }
    return null;
}

/// Export names land verbatim in the ESM prologue, so they must be plain
/// JS identifiers (rejects quotes/dots/slashes that would break out of
/// the import statement).
pub fn isNpmExportIdent(name: []const u8) bool {
    if (name.len == 0) return false;
    if (!std.ascii.isAlphabetic(name[0]) and name[0] != '_' and name[0] != '$') return false;
    for (name[1..]) |c| {
        if (!std.ascii.isAlphanumeric(c) and c != '_' and c != '$') return false;
    }
    return true;
}

pub fn isNpmIntType(ty: sig.PrimType) bool {
    return switch (ty) {
        .i8, .i16, .i32, .i64, .u8, .u16, .u32, .u64 => true,
        else => false,
    };
}

pub fn isNpmNumericType(ty: sig.PrimType) bool {
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
pub fn emitNpmWrapper(
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
