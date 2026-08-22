const std = @import("std");

const SymbolSet = std.StringHashMap(void);

const ManifestStats = struct {
    entry_count: usize = 0,
    duplicate_entry_count: usize = 0,
    duplicate_symbols: std.StringHashMap(usize),
    domain_counts: std.StringHashMap(usize),

    fn init(allocator: std.mem.Allocator) ManifestStats {
        return .{
            .duplicate_symbols = std.StringHashMap(usize).init(allocator),
            .domain_counts = std.StringHashMap(usize).init(allocator),
        };
    }
};

const Config = struct {
    platform: []const u8 = "",
};

pub fn main() !void {
    var config = Config{};
    var args = try std.process.argsWithAllocator(std.heap.page_allocator);
    defer args.deinit();
    _ = args.next();
    while (args.next()) |arg| {
        if (std.mem.eql(u8, arg, "--platform")) {
            config.platform = args.next() orelse return usageError("--platform requires linux or windows");
        } else {
            return usageError("unknown argument");
        }
    }

    if (!std.mem.eql(u8, config.platform, "linux") and
        !std.mem.eql(u8, config.platform, "windows") and
        !std.mem.eql(u8, config.platform, "both"))
    {
        return usageError("--platform must be linux, windows, or both");
    }

    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const header = try std.fs.cwd().readFileAlloc(allocator, "src/runtime/sa_std.h", 8 * 1024 * 1024);
    const linux_source = try std.fs.cwd().readFileAlloc(allocator, "src/runtime/sa_std.zig", 32 * 1024 * 1024);
    const windows_source = try std.fs.cwd().readFileAlloc(allocator, "src/runtime/sa_std_windows.zig", 32 * 1024 * 1024);
    const unsupported_source = try std.fs.cwd().readFileAlloc(allocator, "docs/runtime_abi_windows_unsupported.txt", 1 * 1024 * 1024);
    const extra_source = try std.fs.cwd().readFileAlloc(allocator, "docs/runtime_abi_windows_extra.txt", 1 * 1024 * 1024);

    var header_symbols = SymbolSet.init(allocator);
    var linux_symbols = SymbolSet.init(allocator);
    var windows_symbols = SymbolSet.init(allocator);
    var unsupported_windows_symbols = SymbolSet.init(allocator);
    var extra_windows_symbols = SymbolSet.init(allocator);
    var unsupported_stats = ManifestStats.init(allocator);
    var extra_stats = ManifestStats.init(allocator);

    try collectHeaderSymbols(&header_symbols, header);
    try collectZigSymbols(&linux_symbols, linux_source);
    try collectZigSymbols(&windows_symbols, windows_source);
    try collectManifestSymbols(&unsupported_windows_symbols, unsupported_source, &unsupported_stats);
    try collectManifestSymbols(&extra_windows_symbols, extra_source, &extra_stats);

    reportManifestStats("unsupported", &unsupported_windows_symbols, &unsupported_stats);
    reportManifestStats("extra", &extra_windows_symbols, &extra_stats);

    var errors: usize = 0;
    if (std.mem.eql(u8, config.platform, "linux") or std.mem.eql(u8, config.platform, "both")) {
        errors += reportMissing("Linux runtime is missing public ABI symbols", &header_symbols, &linux_symbols);
    }

    if (std.mem.eql(u8, config.platform, "windows") or std.mem.eql(u8, config.platform, "both")) {
        errors += reportManifestMismatch(&header_symbols, &windows_symbols, &unsupported_windows_symbols, &extra_windows_symbols);
    }

    std.debug.print(
        "[runtime-abi] platform={s} header={d} linux={d} windows={d} windows_unsupported={d} windows_extra={d}\n",
        .{ config.platform, header_symbols.count(), linux_symbols.count(), windows_symbols.count(), unsupported_windows_symbols.count(), extra_windows_symbols.count() },
    );

    if (errors != 0) {
        std.debug.print("[runtime-abi] FAIL: {d} contract errors\n", .{errors});
        return error.RuntimeAbiMismatch;
    }

    std.debug.print(
        "[runtime-abi] PASS: {d} public symbols are covered for {s}\n",
        .{ header_symbols.count(), config.platform },
    );
}

fn usageError(message: []const u8) error{InvalidArguments} {
    std.debug.print("runtime_abi_check: {s}\n", .{message});
    std.debug.print("usage: zig run tools/runtime_abi_check.zig -- --platform linux|windows|both\n", .{});
    return error.InvalidArguments;
}

fn collectHeaderSymbols(symbols: *SymbolSet, contents: []const u8) !void {
    var index: usize = 0;
    while (index + 3 <= contents.len) {
        if (!std.mem.startsWith(u8, contents[index..], "sa_")) {
            index += 1;
            continue;
        }

        const start = index;
        index += 3;
        while (index < contents.len and isIdentifierByte(contents[index])) : (index += 1) {}
        const name = contents[start..index];
        var lookahead = index;
        while (lookahead < contents.len and isWhitespace(contents[lookahead])) : (lookahead += 1) {}
        if (lookahead < contents.len and contents[lookahead] == '(') {
            try symbols.put(name, {});
        }
    }
}

fn collectZigSymbols(symbols: *SymbolSet, contents: []const u8) !void {
    var index: usize = 0;
    while (index < contents.len) {
        if (contents[index] == '&') {
            var cursor = index + 1;
            while (cursor < contents.len and isWhitespace(contents[cursor])) : (cursor += 1) {}
            var last_start: usize = cursor;
            var last_end: usize = cursor;
            var saw_dot = false;
            while (cursor < contents.len) {
                const part_start = cursor;
                const part_end = identifierEnd(contents, part_start);
                if (part_end == part_start) break;
                last_start = part_start;
                last_end = part_end;
                cursor = part_end;
                if (cursor >= contents.len or contents[cursor] != '.') break;
                saw_dot = true;
                cursor += 1;
            }
            if (saw_dot and last_end > last_start and std.mem.startsWith(u8, contents[last_start..last_end], "sa_")) {
                try symbols.put(contents[last_start..last_end], {});
            }
            index = @max(cursor, index + 1);
            continue;
        }

        if (std.mem.startsWith(u8, contents[index..], "export fn")) {
            var name_start = index + "export fn".len;
            while (name_start < contents.len and isWhitespace(contents[name_start])) : (name_start += 1) {}
            const name_end = identifierEnd(contents, name_start);
            if (name_end > name_start and std.mem.startsWith(u8, contents[name_start..name_end], "sa_")) {
                try symbols.put(contents[name_start..name_end], {});
            }
            index = @max(name_end, index + 1);
            continue;
        }

        if (std.mem.startsWith(u8, contents[index..], ".name")) {
            var cursor = index + ".name".len;
            while (cursor < contents.len and isWhitespace(contents[cursor])) : (cursor += 1) {}
            if (cursor < contents.len and contents[cursor] == '=') cursor += 1;
            while (cursor < contents.len and isWhitespace(contents[cursor])) : (cursor += 1) {}
            if (cursor < contents.len and contents[cursor] == '"') {
                cursor += 1;
                const name_start = cursor;
                while (cursor < contents.len and contents[cursor] != '"') : (cursor += 1) {}
                if (cursor > name_start and std.mem.startsWith(u8, contents[name_start..cursor], "sa_")) {
                    try symbols.put(contents[name_start..cursor], {});
                }
                index = @max(cursor, index + 1);
                continue;
            }
        }

        index += 1;
    }
}

fn collectManifestSymbols(symbols: *SymbolSet, contents: []const u8, stats: *ManifestStats) !void {
    var lines = std.mem.splitScalar(u8, contents, '\n');
    while (lines.next()) |raw_line| {
        const line = std.mem.trim(u8, raw_line, " \t\r");
        if (line.len == 0 or line[0] == '#') continue;
        stats.entry_count += 1;
        if (!std.mem.startsWith(u8, line, "sa_")) {
            std.debug.print("[runtime-abi] invalid unsupported manifest line: {s}\n", .{line});
            return error.InvalidManifest;
        }
        for (line) |byte| {
            if (!isIdentifierByte(byte)) return error.InvalidManifest;
        }
        if (symbols.contains(line)) {
            stats.duplicate_entry_count += 1;
            const result = try stats.duplicate_symbols.getOrPut(line);
            if (!result.found_existing) result.value_ptr.* = 0;
            result.value_ptr.* += 1;
            continue;
        }

        try symbols.put(line, {});
        const domain = capabilityDomain(line);
        const domain_result = try stats.domain_counts.getOrPut(domain);
        if (!domain_result.found_existing) domain_result.value_ptr.* = 0;
        domain_result.value_ptr.* += 1;
    }
}

fn reportManifestStats(
    label: []const u8,
    symbols: *const SymbolSet,
    stats: *const ManifestStats,
) void {
    std.debug.print(
        "[runtime-abi] manifest={s} entries={d} unique={d} duplicate_entries={d} duplicate_symbols={d}\n",
        .{ label, stats.entry_count, symbols.count(), stats.duplicate_entry_count, stats.duplicate_symbols.count() },
    );

    if (stats.duplicate_symbols.count() != 0) {
        var names = std.ArrayList([]const u8).init(std.heap.page_allocator);
        defer names.deinit();
        var iterator = stats.duplicate_symbols.keyIterator();
        while (iterator.next()) |name| names.append(name.*) catch return;
        std.mem.sort([]const u8, names.items, {}, stringSliceLessThan);
        for (names.items) |name| {
            std.debug.print(
                "[runtime-abi] manifest={s} duplicate={s} additional_entries={d}\n",
                .{ label, name, stats.duplicate_symbols.get(name).? },
            );
        }
    }

    var domains = std.ArrayList([]const u8).init(std.heap.page_allocator);
    defer domains.deinit();
    var domain_iterator = stats.domain_counts.keyIterator();
    while (domain_iterator.next()) |domain| domains.append(domain.*) catch return;
    std.mem.sort([]const u8, domains.items, {}, stringSliceLessThan);
    for (domains.items) |domain| {
        std.debug.print(
            "[runtime-abi] manifest={s} domain={s} unique={d}\n",
            .{ label, domain, stats.domain_counts.get(domain).? },
        );
    }
}

fn capabilityDomain(symbol: []const u8) []const u8 {
    if (std.mem.startsWith(u8, symbol, "sa_regex_")) return "regex";
    if (std.mem.startsWith(u8, symbol, "sa_deno_")) return "deno";
    if (std.mem.startsWith(u8, symbol, "sa_http_")) return "http";
    if (std.mem.startsWith(u8, symbol, "sa_io_")) return "io";
    if (std.mem.startsWith(u8, symbol, "sa_dl_")) return "dynamic-loader";
    if (std.mem.startsWith(u8, symbol, "sa_term_")) return "terminal";
    if (std.mem.startsWith(u8, symbol, "sa_pidfd_") or std.mem.startsWith(u8, symbol, "sa_std_pidfd_")) return "process.pidfd";
    if (std.mem.startsWith(u8, symbol, "sa_std_process_") or std.mem.startsWith(u8, symbol, "sa_process_")) return "process";
    if (std.mem.startsWith(u8, symbol, "sa_std_fd_") or std.mem.startsWith(u8, symbol, "sa_fd_")) return "fd";
    if (std.mem.startsWith(u8, symbol, "sa_std_net_unix_") or std.mem.startsWith(u8, symbol, "sa_net_unix_")) return "net.unix";
    if (std.mem.startsWith(u8, symbol, "sa_std_net_tcp_") or std.mem.startsWith(u8, symbol, "sa_net_tcp_")) return "net.tcp";
    if (std.mem.startsWith(u8, symbol, "sa_std_net_udp_") or std.mem.startsWith(u8, symbol, "sa_net_udp_")) return "net.udp";
    if (std.mem.startsWith(u8, symbol, "sa_std_net_addr") or
        std.mem.startsWith(u8, symbol, "sa_net_addr") or
        std.mem.startsWith(u8, symbol, "sa_net_ipv")) return "net.address";
    if (std.mem.startsWith(u8, symbol, "sa_std_net_")) return "net.other";
    if (std.mem.startsWith(u8, symbol, "sa_net_")) return "net.other";
    if (std.mem.startsWith(u8, symbol, "sa_assert_") or std.mem.startsWith(u8, symbol, "sa_test_")) return "test";
    return "other";
}

fn stringSliceLessThan(_: void, lhs: []const u8, rhs: []const u8) bool {
    return std.mem.lessThan(u8, lhs, rhs);
}

fn reportMissing(message: []const u8, expected: *const SymbolSet, actual: *const SymbolSet) usize {
    var errors: usize = 0;
    var iterator = expected.keyIterator();
    while (iterator.next()) |name| {
        if (!actual.contains(name.*)) {
            std.debug.print("[runtime-abi] {s}: {s}\n", .{ message, name.* });
            errors += 1;
        }
    }
    return errors;
}

fn reportManifestMismatch(header: *const SymbolSet, actual: *const SymbolSet, unsupported: *const SymbolSet, extra: *const SymbolSet) usize {
    var errors: usize = 0;

    var unsupported_iterator = unsupported.keyIterator();
    while (unsupported_iterator.next()) |name| {
        if (!header.contains(name.*)) {
            std.debug.print("[runtime-abi] Windows unsupported manifest names unknown ABI symbol: {s}\n", .{name.*});
            errors += 1;
        } else if (actual.contains(name.*)) {
            std.debug.print("[runtime-abi] Windows unsupported symbol is exported: {s}\n", .{name.*});
            errors += 1;
        }
    }

    var header_iterator = header.keyIterator();
    while (header_iterator.next()) |name| {
        if (actual.contains(name.*)) continue;
        if (!unsupported.contains(name.*)) {
            std.debug.print("[runtime-abi] Windows missing symbol is not documented unsupported: {s}\n", .{name.*});
            errors += 1;
        }
    }

    var actual_iterator = actual.keyIterator();
    while (actual_iterator.next()) |name| {
        if (header.contains(name.*)) continue;
        if (!extra.contains(name.*)) {
            std.debug.print("[runtime-abi] Windows extra export is not documented: {s}\n", .{name.*});
            errors += 1;
        }
    }

    return errors;
}

fn identifierEnd(contents: []const u8, start: usize) usize {
    var end = start;
    while (end < contents.len and isIdentifierByte(contents[end])) : (end += 1) {}
    return end;
}

fn isIdentifierByte(byte: u8) bool {
    return std.ascii.isAlphanumeric(byte) or byte == '_';
}

fn isWhitespace(byte: u8) bool {
    return byte == ' ' or byte == '\t' or byte == '\r' or byte == '\n';
}

test "capability domains classify ABI families" {
    try std.testing.expectEqualStrings("net.tcp", capabilityDomain("sa_std_net_tcp_stream_read"));
    try std.testing.expectEqualStrings("net.udp", capabilityDomain("sa_net_udp_send"));
    try std.testing.expectEqualStrings("net.unix", capabilityDomain("sa_std_net_unix_pair"));
    try std.testing.expectEqualStrings("process.pidfd", capabilityDomain("sa_std_pidfd_wait"));
    try std.testing.expectEqualStrings("regex", capabilityDomain("sa_regex_match"));
    try std.testing.expectEqualStrings("other", capabilityDomain("sa_unknown_feature"));
}

test "manifest collection counts duplicates without changing symbol set" {
    var symbols = SymbolSet.init(std.testing.allocator);
    defer symbols.deinit();
    var stats = ManifestStats.init(std.testing.allocator);
    defer stats.duplicate_symbols.deinit();
    defer stats.domain_counts.deinit();

    try collectManifestSymbols(&symbols, "# comment\nsa_net_udp_send\nsa_net_udp_send\nsa_regex_match\n", &stats);

    try std.testing.expectEqual(@as(usize, 3), stats.entry_count);
    try std.testing.expectEqual(@as(usize, 1), stats.duplicate_entry_count);
    try std.testing.expectEqual(@as(usize, 2), symbols.count());
    try std.testing.expectEqual(@as(usize, 1), stats.duplicate_symbols.count());
    try std.testing.expectEqual(@as(usize, 1), stats.duplicate_symbols.get("sa_net_udp_send").?);
    try std.testing.expectEqual(@as(usize, 1), stats.domain_counts.get("net.udp").?);
    try std.testing.expectEqual(@as(usize, 1), stats.domain_counts.get("regex").?);
}
