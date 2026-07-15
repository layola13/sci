const std = @import("std");

const baseline_path = "tests/abi/sa_std_symbols_v1.txt";
const posix_path = "src/runtime/sa_std_posix.zig";
const windows_path = "src/runtime/sa_std_windows.zig";

fn lessThan(_: void, lhs: []const u8, rhs: []const u8) bool {
    return std.mem.order(u8, lhs, rhs) == .lt;
}

fn collectBaseline(allocator: std.mem.Allocator, source: []const u8) ![][]const u8 {
    var symbols = std.ArrayList([]const u8).init(allocator);
    errdefer symbols.deinit();

    var lines = std.mem.splitScalar(u8, source, '\n');
    while (lines.next()) |line| {
        const symbol = std.mem.trim(u8, line, " \t\r");
        if (symbol.len == 0 or symbol[0] == '#') continue;
        try symbols.append(symbol);
    }
    std.mem.sort([]const u8, symbols.items, {}, lessThan);
    return symbols.toOwnedSlice();
}

fn collectBackendExports(allocator: std.mem.Allocator, source: []const u8) ![][]const u8 {
    const prefix = "pub export fn ";
    var symbols = std.ArrayList([]const u8).init(allocator);
    errdefer symbols.deinit();

    var lines = std.mem.splitScalar(u8, source, '\n');
    while (lines.next()) |line| {
        if (!std.mem.startsWith(u8, line, prefix)) continue;
        const rest = line[prefix.len..];
        const end = std.mem.indexOfScalar(u8, rest, '(') orelse return error.InvalidExportDeclaration;
        if (end == 0) return error.InvalidExportDeclaration;
        try symbols.append(rest[0..end]);
    }
    std.mem.sort([]const u8, symbols.items, {}, lessThan);
    return symbols.toOwnedSlice();
}

fn expectSurfaceMatchesBaseline(allocator: std.mem.Allocator, backend_path: []const u8) !void {
    const baseline_source = try std.fs.cwd().readFileAlloc(allocator, baseline_path, 1024 * 1024);
    defer allocator.free(baseline_source);
    const backend_source = try std.fs.cwd().readFileAlloc(allocator, backend_path, 4 * 1024 * 1024);
    defer allocator.free(backend_source);

    const expected = try collectBaseline(allocator, baseline_source);
    defer allocator.free(expected);
    const actual = try collectBackendExports(allocator, backend_source);
    defer allocator.free(actual);

    try std.testing.expectEqual(expected.len, actual.len);
    for (expected, actual) |expected_symbol, actual_symbol| {
        try std.testing.expectEqualStrings(expected_symbol, actual_symbol);
    }
}

test "POSIX backend preserves the v1 export surface" {
    try expectSurfaceMatchesBaseline(std.testing.allocator, posix_path);
}

test "Windows backend preserves the v1 export surface" {
    try expectSurfaceMatchesBaseline(std.testing.allocator, windows_path);
}
