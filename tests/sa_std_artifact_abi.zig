const std = @import("std");

const ArtifactFormat = enum {
    archive,
    coff_archive,
    elf_shared,
};

const compatibility_symbols = [_][]const u8{
    "dlclose",
    "dlopen",
    "dlsym",
    "fd_close",
    "fd_open",
    "fd_read",
    "mmap",
    "munmap",
    "pthread_drop",
    "pthread_join",
    "pthread_spawn",
    "pthread_spawn_detached",
    "signal",
    "sqlite3_finalize",
    "sqlite3_prepare",
    "sqlite3_step",
};

fn lessThan(_: void, lhs: []const u8, rhs: []const u8) bool {
    return std.mem.order(u8, lhs, rhs) == .lt;
}

fn isManagedSymbol(symbol: []const u8) bool {
    if (std.mem.startsWith(u8, symbol, "sa_")) {
        return !std.mem.startsWith(u8, symbol, "sa_host_pthread_");
    }
    for (compatibility_symbols) |compatibility_symbol| {
        if (std.mem.eql(u8, symbol, compatibility_symbol)) return true;
    }
    return false;
}

fn appendOwnedUnique(
    allocator: std.mem.Allocator,
    symbols: *std.ArrayList([]const u8),
    symbol: []const u8,
    duplicate_is_error: bool,
) !void {
    for (symbols.items) |existing| {
        if (!std.mem.eql(u8, existing, symbol)) continue;
        if (duplicate_is_error) return error.DuplicateBaselineSymbol;
        return;
    }
    try symbols.append(try allocator.dupe(u8, symbol));
}

fn collectBaselineSource(
    allocator: std.mem.Allocator,
    symbols: *std.ArrayList([]const u8),
    source: []const u8,
) !void {
    var lines = std.mem.splitScalar(u8, source, '\n');
    while (lines.next()) |line| {
        const symbol = std.mem.trim(u8, line, " \t\r");
        if (symbol.len == 0 or symbol[0] == '#') continue;
        if (std.mem.indexOfAny(u8, symbol, " \t") != null) return error.InvalidBaselineSymbol;
        if (!isManagedSymbol(symbol)) return error.UnmanagedBaselineSymbol;
        try appendOwnedUnique(allocator, symbols, symbol, true);
    }
}

fn normalizeNmSymbol(format: ArtifactFormat, symbol: []const u8) []const u8 {
    if (format != .coff_archive or symbol.len < 2 or symbol[0] != '_') return symbol;
    const undecorated = symbol[1..];
    return if (isManagedSymbol(undecorated)) undecorated else symbol;
}

fn collectNmOutput(
    allocator: std.mem.Allocator,
    format: ArtifactFormat,
    output: []const u8,
) !std.ArrayList([]const u8) {
    var symbols = std.ArrayList([]const u8).init(allocator);
    errdefer deinitSymbols(allocator, &symbols);

    var lines = std.mem.splitScalar(u8, output, '\n');
    while (lines.next()) |line| {
        var fields = std.mem.tokenizeAny(u8, line, " \t\r");
        const raw_symbol = fields.next() orelse continue;
        const kind = fields.next() orelse continue;
        if (kind.len != 1 or !std.ascii.isAlphabetic(kind[0])) continue;
        const symbol = normalizeNmSymbol(format, raw_symbol);
        if (!isManagedSymbol(symbol)) continue;
        try appendOwnedUnique(allocator, &symbols, symbol, false);
    }
    std.mem.sort([]const u8, symbols.items, {}, lessThan);
    return symbols;
}

fn deinitSymbols(allocator: std.mem.Allocator, symbols: *std.ArrayList([]const u8)) void {
    for (symbols.items) |symbol| allocator.free(symbol);
    symbols.deinit();
}

fn parseFormat(value: []const u8) !ArtifactFormat {
    if (std.mem.eql(u8, value, "archive")) return .archive;
    if (std.mem.eql(u8, value, "coff-archive")) return .coff_archive;
    if (std.mem.eql(u8, value, "elf-shared")) return .elf_shared;
    return error.InvalidArtifactFormat;
}

fn printSurfaceDiff(expected: []const []const u8, actual: []const []const u8) void {
    var expected_index: usize = 0;
    var actual_index: usize = 0;
    while (expected_index < expected.len or actual_index < actual.len) {
        if (expected_index == expected.len) {
            std.debug.print("  unexpected: {s}\n", .{actual[actual_index]});
            actual_index += 1;
            continue;
        }
        if (actual_index == actual.len) {
            std.debug.print("  missing:    {s}\n", .{expected[expected_index]});
            expected_index += 1;
            continue;
        }
        switch (std.mem.order(u8, expected[expected_index], actual[actual_index])) {
            .eq => {
                expected_index += 1;
                actual_index += 1;
            },
            .lt => {
                std.debug.print("  missing:    {s}\n", .{expected[expected_index]});
                expected_index += 1;
            },
            .gt => {
                std.debug.print("  unexpected: {s}\n", .{actual[actual_index]});
                actual_index += 1;
            },
        }
    }
}

fn surfacesEqual(expected: []const []const u8, actual: []const []const u8) bool {
    if (expected.len != actual.len) return false;
    for (expected, actual) |expected_symbol, actual_symbol| {
        if (!std.mem.eql(u8, expected_symbol, actual_symbol)) return false;
    }
    return true;
}

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const args = try std.process.argsAlloc(allocator);
    if (args.len < 5) {
        std.debug.print(
            "usage: {s} <nm> <archive|coff-archive|elf-shared> <artifact> <baseline> [baseline ...]\n",
            .{args[0]},
        );
        return error.InvalidArguments;
    }

    const nm_path = args[1];
    const format = try parseFormat(args[2]);
    const artifact_path = args[3];

    var expected = std.ArrayList([]const u8).init(allocator);
    for (args[4..]) |baseline_path| {
        const source = try std.fs.cwd().readFileAlloc(allocator, baseline_path, 1024 * 1024);
        try collectBaselineSource(allocator, &expected, source);
    }
    std.mem.sort([]const u8, expected.items, {}, lessThan);

    var nm_argv = std.ArrayList([]const u8).init(allocator);
    try nm_argv.appendSlice(&.{
        nm_path,
        "--defined-only",
        "--extern-only",
        "--format=posix",
        "--no-demangle",
    });
    if (format == .elf_shared) try nm_argv.append("--dynamic");
    try nm_argv.append(artifact_path);

    const result = try std.process.Child.run(.{
        .allocator = allocator,
        .argv = nm_argv.items,
        .max_output_bytes = 8 * 1024 * 1024,
    });
    switch (result.term) {
        .Exited => |code| if (code != 0) {
            std.debug.print("{s} failed for {s} (exit {d}):\n{s}\n", .{ nm_path, artifact_path, code, result.stderr });
            return error.SymbolToolFailed;
        },
        else => {
            std.debug.print("{s} did not exit normally while reading {s}\n", .{ nm_path, artifact_path });
            return error.SymbolToolFailed;
        },
    }

    var actual = try collectNmOutput(allocator, format, result.stdout);
    defer actual.deinit();
    if (!surfacesEqual(expected.items, actual.items)) {
        std.debug.print(
            "managed ABI symbol mismatch for {s}: expected {d}, found {d}\n",
            .{ artifact_path, expected.items.len, actual.items.len },
        );
        printSurfaceDiff(expected.items, actual.items);
        return error.AbiSymbolMismatch;
    }
    std.debug.print("ABI symbols: {s}: {d} managed definitions\n", .{ artifact_path, actual.items.len });
}

test "managed symbol filter excludes toolchain and pthread host internals" {
    try std.testing.expect(isManagedSymbol("sa_std_version"));
    try std.testing.expect(isManagedSymbol("pthread_spawn"));
    try std.testing.expect(isManagedSymbol("sqlite3_finalize"));
    try std.testing.expect(!isManagedSymbol("sa_host_pthread_join"));
    try std.testing.expect(!isManagedSymbol("__addtf3"));
    try std.testing.expect(!isManagedSymbol("memcpy"));
}

test "nm parser handles archive headers and COFF decoration" {
    const output =
        \\archive.lib[member.obj]:
        \\_sa_std_version T 10 0
        \\_pthread_join T 20 0
        \\sa_host_pthread_join T 30 0
        \\__addtf3 W 40 0
        \\sa_std_version T 50 0
    ;
    var symbols = try collectNmOutput(std.testing.allocator, .coff_archive, output);
    defer deinitSymbols(std.testing.allocator, &symbols);
    try std.testing.expectEqual(@as(usize, 2), symbols.items.len);
    try std.testing.expectEqualStrings("pthread_join", symbols.items[0]);
    try std.testing.expectEqualStrings("sa_std_version", symbols.items[1]);
}

test "baseline parser rejects duplicate and unmanaged entries" {
    var symbols = std.ArrayList([]const u8).init(std.testing.allocator);
    defer deinitSymbols(std.testing.allocator, &symbols);

    try collectBaselineSource(std.testing.allocator, &symbols, "# comment\nsa_std_version\n");
    try std.testing.expectError(
        error.DuplicateBaselineSymbol,
        collectBaselineSource(std.testing.allocator, &symbols, "sa_std_version\n"),
    );
    try std.testing.expectError(
        error.UnmanagedBaselineSymbol,
        collectBaselineSource(std.testing.allocator, &symbols, "memcpy\n"),
    );
}
