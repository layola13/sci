// SSA phi lowering through stack slots.
const std = @import("std");
const trim = @import("text.zig").trim;
const stripLlvmSigil = @import("text.zig").stripLlvmSigil;
const sanitizeIdent = @import("text.zig").sanitizeIdent;
const splitTopLevelComma = @import("text.zig").splitTopLevelComma;
const firstTypeToken = @import("types.zig").firstTypeToken;
const typeTokenToSa = @import("types.zig").typeTokenToSa;
const typeBytes = @import("types.zig").typeBytes;
const llvmTypedValueToValue = @import("values.zig").llvmTypedValueToValue;
const saValue = @import("values.zig").saValue;

pub fn isPhiInstruction(line: []const u8) bool {
    const eq = std.mem.indexOfScalar(u8, line, '=') orelse return false;
    var words = std.mem.tokenizeAny(u8, trim(line[eq + 1 ..]), " \t\r\n");
    return if (words.next()) |op| std.mem.eql(u8, op, "phi") else false;
}

pub fn parsePhi(allocator: std.mem.Allocator, line: []const u8) !struct { lhs: []const u8, ty: []const u8, incoming: []const []const u8 } {
    const eq = std.mem.indexOfScalar(u8, line, '=') orelse return error.InvalidIr;
    const lhs = trim(line[0..eq]);
    const rhs = trim(line[eq + 1 ..]);
    if (!std.mem.startsWith(u8, rhs, "phi ")) return error.UnsupportedPhi;
    const body = trim(rhs["phi ".len..]);
    const ty = firstTypeToken(body) orelse return error.UnsupportedPhi;
    const ty_idx = std.mem.indexOf(u8, body, ty) orelse return error.InvalidIr;
    const incoming = try splitTopLevelComma(allocator, trim(body[ty_idx + ty.len ..]));
    if (incoming.len == 0) {
        allocator.free(incoming);
        return error.UnsupportedPhi;
    }
    return .{ .lhs = lhs, .ty = ty, .incoming = incoming };
}

pub fn phiSlotName(allocator: std.mem.Allocator, lhs: []const u8) ![]u8 {
    const dst = try sanitizeIdent(allocator, lhs, "r");
    defer allocator.free(dst);
    return try std.fmt.allocPrint(allocator, "bc2sa_phi_slot_{s}", .{dst});
}

pub fn appendPhiSlots(out: *std.array_list.Managed(u8), allocator: std.mem.Allocator, phi_lines: []const []const u8) !void {
    for (phi_lines) |phi_line| {
        const phi = try parsePhi(allocator, phi_line);
        defer allocator.free(phi.incoming);
        const size = typeBytes(phi.ty) orelse return error.UnsupportedPhi;
        const slot = try phiSlotName(allocator, phi.lhs);
        defer allocator.free(slot);
        try out.print("  {s} = stack_alloc {d}\n", .{ slot, size });
    }
}

pub fn appendPhiLoad(out: *std.array_list.Managed(u8), allocator: std.mem.Allocator, line: []const u8) !void {
    const phi = try parsePhi(allocator, line);
    defer allocator.free(phi.incoming);
    const sa_ty = typeTokenToSa(phi.ty) orelse return error.UnsupportedPhi;
    const dst = try sanitizeIdent(allocator, phi.lhs, "r");
    defer allocator.free(dst);
    const slot = try phiSlotName(allocator, phi.lhs);
    defer allocator.free(slot);
    try out.print("  {s} = load {s}+0 as {s}\n", .{ dst, slot, sa_ty });
}

pub fn appendPhiStoresForBlock(out: *std.array_list.Managed(u8), allocator: std.mem.Allocator, phi_lines: []const []const u8, block: []const u8) !void {
    for (phi_lines) |phi_line| {
        const phi = try parsePhi(allocator, phi_line);
        defer allocator.free(phi.incoming);
        const sa_ty = typeTokenToSa(phi.ty) orelse return error.UnsupportedPhi;
        const slot = try phiSlotName(allocator, phi.lhs);
        defer allocator.free(slot);
        for (phi.incoming) |incoming_text| {
            const pair_text = trim(incoming_text);
            if (pair_text.len < 2 or pair_text[0] != '[' or pair_text[pair_text.len - 1] != ']') return error.UnsupportedPhi;
            const pair = try splitTopLevelComma(allocator, pair_text[1 .. pair_text.len - 1]);
            defer allocator.free(pair);
            if (pair.len != 2) return error.UnsupportedPhi;
            const incoming_block = stripLlvmSigil(llvmTypedValueToValue(pair[1]));
            if (!std.mem.eql(u8, trim(incoming_block), trim(block))) continue;
            const value = try saValue(allocator, pair[0]);
            defer allocator.free(value);
            try out.print("  store {s}+0, {s} as {s}\n", .{ slot, value, sa_ty });
        }
    }
}
