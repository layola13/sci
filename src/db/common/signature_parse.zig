const std = @import("std");
const FunctionKind = @import("signature.zig").FunctionKind;
const FunctionSig = @import("signature.zig").FunctionSig;
const HeaderSpec = @import("signature.zig").HeaderSpec;
const ParseError = @import("signature.zig").ParseError;
const PrimType = @import("signature.zig").PrimType;
const capText = @import("signature.zig").capText;
const instr = @import("signature.zig").instr;
const isIdentChar = @import("signature.zig").isIdentChar;
const isIdentStart = @import("signature.zig").isIdentStart;
const parseOptionalCap = @import("signature.zig").parseOptionalCap;
const parseParamList = @import("signature.zig").parseParamList;
const parsePrimType = @import("signature.zig").parsePrimType;
const parseTestModifiers = @import("signature.zig").parseTestModifiers;
const primTypeName = @import("signature.zig").primTypeName;
const testLLVMName = @import("signature.zig").testLLVMName;

pub fn parseFunctionHeader(
    allocator: std.mem.Allocator,
    text: []const u8,
    id: u32,
    entry_inst_idx: u32,
    kind: FunctionKind,
) ParseError!FunctionSig {
    const trimmed = std.mem.trim(u8, text, " \t\r");
    if (trimmed.len == 0) return ParseError.InvalidFunctionSig;

    const spec: HeaderSpec = switch (kind) {
        .normal => .{ .prefix = "@", .require_colon = true },
        .ffi_wrapper => .{ .prefix = "@ffi_wrapper", .require_colon = true },
        .external => .{ .prefix = "@extern", .require_colon = false },
        .exported => .{ .prefix = "@export", .require_colon = true },
        .test_func => .{ .prefix = "@test", .require_colon = true },
    };

    if (!std.mem.startsWith(u8, trimmed, spec.prefix)) return ParseError.InvalidFunctionSig;
    if (spec.require_colon and trimmed[trimmed.len - 1] != ':') return ParseError.InvalidFunctionSig;

    var body = if (spec.require_colon)
        trimmed[spec.prefix.len .. trimmed.len - 1]
    else
        std.mem.trimEnd(u8, trimmed[spec.prefix.len..], " :\t\r");

    var ignored = false;
    var should_panic = false;
    if (kind == .test_func) {
        const modifiers = try parseTestModifiers(body);
        body = modifiers.rest;
        ignored = modifiers.ignored;
        should_panic = modifiers.should_panic;
    }

    const after_name = std.mem.trimStart(u8, body, " \t");
    const open = std.mem.indexOfScalar(u8, after_name, '(') orelse return ParseError.InvalidFunctionSig;
    const close = std.mem.lastIndexOfScalar(u8, after_name, ')') orelse return ParseError.InvalidFunctionSig;
    if (close <= open) return ParseError.InvalidFunctionSig;

    const name_text = std.mem.trim(u8, after_name[0..open], " \t\r");
    if (name_text.len == 0) return ParseError.InvalidFunctionSig;

    // For @test functions, allow string literals as names
    if (kind == .test_func) {
        if (name_text[0] != '"') return ParseError.InvalidFunctionSig;
        const end_quote = std.mem.indexOfScalarPos(u8, name_text, 1, '"') orelse return ParseError.InvalidFunctionSig;
        if (end_quote != name_text.len - 1) return ParseError.InvalidFunctionSig;
    } else {
        if (!isIdentStart(name_text[0])) return ParseError.InvalidFunctionSig;
        for (name_text[1..]) |c| {
            if (!isIdentChar(c)) return ParseError.InvalidFunctionSig;
        }
    }

    const params_text = std.mem.trim(u8, after_name[open + 1 .. close], " \t\r");
    var tail = std.mem.trim(u8, after_name[close + 1 ..], " \t\r");

    var return_cap: ?instr.CapPrefix = null;
    var return_ty: PrimType = .void;
    var return_fallible = false;
    if (tail.len != 0) {
        if (!std.mem.startsWith(u8, tail, "->")) return ParseError.InvalidFunctionSig;
        var return_text = std.mem.trim(u8, tail[2..], " \t\r");
        if (return_text.len == 0) return ParseError.InvalidFunctionSig;
        if (return_text[return_text.len - 1] == '!') {
            return_fallible = true;
            return_text = std.mem.trimEnd(u8, return_text[0 .. return_text.len - 1], " \t\r");
            if (return_text.len == 0) return ParseError.InvalidFunctionSig;
        }
        const cap_split = parseOptionalCap(return_text);
        return_cap = cap_split.cap;
        const ty_text = std.mem.trimStart(u8, cap_split.rest, " \t\r");
        if (ty_text.len == 0) return ParseError.InvalidFunctionSig;
        if (ty_text.len != 0 and (ty_text[0] == '*' or ty_text[0] == '&' or ty_text[0] == '^')) {
            return_ty = .ptr;
        } else {
            return_ty = try parsePrimType(ty_text);
        }
    }

    const parsed_params = try parseParamList(allocator, params_text);
    errdefer {
        for (parsed_params.params) |param| allocator.free(param.name);
        allocator.free(parsed_params.params);
    }

    const name = try allocator.dupe(u8, name_text);
    errdefer allocator.free(name);
    const params = parsed_params.params;
    const llvm_name = if (kind == .test_func) try testLLVMName(allocator, id) else null;

    return .{
        .id = id,
        .name = name,
        .params = params,
        .kind = kind,
        .return_cap = return_cap,
        .return_ty = return_ty,
        .return_fallible = return_fallible,
        .entry_inst_idx = entry_inst_idx,
        .is_ffi_wrapper = kind == .ffi_wrapper,
        .is_variadic = parsed_params.is_variadic,
        .upstream_file = null,
        .upstream_loc = null,
        .llvm_name = llvm_name,
        .ignored = ignored,
        .should_panic = should_panic,
    };
}

pub fn writeFunctionHeader(writer: anytype, sig: FunctionSig) !void {
    switch (sig.kind) {
        .normal => try writer.writeAll("@"),
        .ffi_wrapper => try writer.writeAll("@ffi_wrapper "),
        .external => try writer.writeAll("@extern "),
        .exported => try writer.writeAll("@export "),
        .test_func => {
            try writer.writeAll("@test ");
            if (sig.ignored) try writer.writeAll("ignored ");
            if (sig.should_panic) try writer.writeAll("should_panic ");
        },
    }
    if (sig.kind == .test_func and sig.name.len != 0 and sig.name[0] == '"') {
        try writer.writeAll(sig.name);
    } else {
        try writer.writeAll(sig.name);
    }
    try writer.writeByte('(');
    for (sig.params, 0..) |param, idx| {
        if (idx != 0) try writer.writeAll(", ");
        if (param.cap != .by_value) try writer.writeAll(capText(param.cap));
        try writer.print("{s}: {s}", .{ param.name, primTypeName(param.ty) });
    }
    // Extern variadic batch: the trailing marker is part of the shared
    // declaration surface; dropping it here would silently de-variadise
    // any signature that round-trips through its text form (the SAB
    // reader synthesises decl raw_text with this writer and the
    // verifier re-parses it).
    if (sig.is_variadic) {
        if (sig.params.len != 0) try writer.writeAll(", ");
        try writer.writeAll("...");
    }
    try writer.writeByte(')');
    if (sig.return_ty != .void) {
        try writer.writeAll(" -> ");
        if (sig.return_cap) |cap| try writer.writeAll(capText(cap));
        try writer.writeAll(primTypeName(sig.return_ty));
        if (sig.return_fallible) try writer.writeByte('!');
    }
    if (sig.kind != .external) try writer.writeByte(':');
}

fn expectSigEqual(expected: FunctionSig, actual: FunctionSig) !void {
    try std.testing.expectEqual(expected.id, actual.id);
    try std.testing.expectEqual(expected.kind, actual.kind);
    try std.testing.expectEqual(expected.return_cap, actual.return_cap);
    try std.testing.expectEqual(expected.return_ty, actual.return_ty);
    try std.testing.expectEqual(expected.return_fallible, actual.return_fallible);
    try std.testing.expectEqual(expected.entry_inst_idx, actual.entry_inst_idx);
    try std.testing.expectEqual(expected.is_ffi_wrapper, actual.is_ffi_wrapper);
    try std.testing.expectEqual(expected.ignored, actual.ignored);
    try std.testing.expectEqual(expected.should_panic, actual.should_panic);
    try std.testing.expectEqual(expected.is_variadic, actual.is_variadic);
    try std.testing.expectEqualStrings(expected.name, actual.name);
    try std.testing.expectEqual(expected.params.len, actual.params.len);
    for (expected.params, actual.params) |lhs, rhs| {
        try std.testing.expectEqual(lhs.ty, rhs.ty);
        try std.testing.expectEqual(lhs.cap, rhs.cap);
        try std.testing.expectEqualStrings(lhs.name, rhs.name);
    }
}
