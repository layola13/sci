const std = @import("std");
const types = @import("types.zig");
const sig = @import("../common/signature.zig");
const JsEmitError = @import("types.zig").JsEmitError;
const jsIdent = @import("ident.zig").jsIdent;
const jsFuncName = @import("ident.zig").jsFuncName;

pub const DtsAliases = struct {
    sa_i64: bool = false,
    sa_u64: bool = false,
    sa_ptr: bool = false,
    sa_handle: bool = false,
    sa_fallible: bool = false,
};

/// SA PrimType -> TS type name under the DTS_EMIT_DESIGN.md mapping
/// table. Records alias usage so only used aliases are declared.
pub fn dtsTypeName(ty: sig.PrimType, aliases: *DtsAliases) JsEmitError![]const u8 {
    switch (ty) {
        .i1, .i8, .i16, .i32, .u8, .u16, .u32, .f32, .f64 => return "number",
        .i64 => {
            aliases.sa_i64 = true;
            return "SaI64";
        },
        .u64 => {
            aliases.sa_u64 = true;
            return "SaU64";
        },
        .ptr => {
            aliases.sa_ptr = true;
            return "SaPtr";
        },
        .blob_handle => {
            aliases.sa_handle = true;
            return "SaHandle";
        },
        .void, .v128 => return JsEmitError.UnsupportedDtsType,
    }
}

pub fn writeDtsReturnType(writer: anytype, fsig: sig.FunctionSig, is_wrapper: bool, aliases: *DtsAliases) !void {
    if (!is_wrapper and fsig.return_fallible) {
        if (fsig.return_ty == .void) {
            try writer.writeAll("{ s: number }");
            return;
        }
        const inner = try dtsTypeName(fsig.return_ty, aliases);
        aliases.sa_fallible = true;
        try writer.print("SaFallible<{s}>", .{inner});
        return;
    }
    if (fsig.return_ty == .void) {
        // Measured (SURFACE.md section 2): plain SA functions return 0 in the
        // JS backend; npm wrapper bodies end without a return
        // (undefined), which TS spells `void`.
        try writer.writeAll(if (is_wrapper) "void" else "number");
        return;
    }
    try writer.writeAll(try dtsTypeName(fsig.return_ty, aliases));
}

pub fn writeDtsDecl(writer: anytype, fsig: sig.FunctionSig, is_wrapper: bool, aliases: *DtsAliases) !void {
    for (fsig.params) |p| {
        if (p.ty == .v128 or p.ty == .void) {
            types.last_js_func = fsig.name;
            types.last_js_inst = if (p.ty == .v128)
                "v128 parameter has no JS representation (--emit-dts)"
            else
                "void parameter has no JS representation (--emit-dts)";
            return JsEmitError.UnsupportedDtsType;
        }
    }
    if (fsig.return_ty == .v128) {
        types.last_js_func = fsig.name;
        types.last_js_inst = "v128 return has no JS representation (--emit-dts)";
        return JsEmitError.UnsupportedDtsType;
    }
    try writer.writeAll("export declare function ");
    try jsFuncName(writer, fsig.name);
    try writer.writeAll("(");
    for (fsig.params, 0..) |p, idx| {
        if (idx != 0) try writer.writeAll(", ");
        try jsIdent(writer, p.name);
        try writer.writeAll(": ");
        try writer.writeAll(try dtsTypeName(p.ty, aliases));
    }
    try writer.writeAll("): ");
    try writeDtsReturnType(writer, fsig, is_wrapper, aliases);
    try writer.writeAll(";\n");
}

pub fn dtsNameAlloc(allocator: std.mem.Allocator, name: []const u8) ![]u8 {
    var out: std.Io.Writer.Allocating = .init(allocator);
    errdefer out.deinit();
    try jsFuncName(&out.writer, name);
    return out.toOwnedSlice();
}

test "dts type mapping follows measured boundary representations" {
    var aliases = DtsAliases{};
    try std.testing.expectEqualStrings("number", try dtsTypeName(.i32, &aliases));
    try std.testing.expectEqualStrings("number", try dtsTypeName(.f64, &aliases));
    try std.testing.expectEqualStrings("number", try dtsTypeName(.u32, &aliases));
    try std.testing.expectEqualStrings("SaI64", try dtsTypeName(.i64, &aliases));
    try std.testing.expect(aliases.sa_i64);
    try std.testing.expectEqualStrings("SaU64", try dtsTypeName(.u64, &aliases));
    try std.testing.expectEqualStrings("SaPtr", try dtsTypeName(.ptr, &aliases));
    try std.testing.expectEqualStrings("SaHandle", try dtsTypeName(.blob_handle, &aliases));
    try std.testing.expect(aliases.sa_handle);
    try std.testing.expectError(JsEmitError.UnsupportedDtsType, dtsTypeName(.v128, &aliases));
    try std.testing.expectError(JsEmitError.UnsupportedDtsType, dtsTypeName(.void, &aliases));
}
