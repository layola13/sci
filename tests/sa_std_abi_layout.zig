const std = @import("std");

const c = @cImport({
    @cInclude("sa_std.h");
});

const zig_abi = struct {
    const SaJsonToken = extern struct {
        kind: u32,
        text_ptr: ?[*]const u8,
        text_len: u64,
    };

    const SaJsonStringifyOptions = extern struct {
        whitespace: u32,
        emit_null_optional_fields: u8,
        emit_strings_as_arrays: u8,
        escape_unicode: u8,
        emit_nonportable_numbers_as_strings: u8,
    };

    const SaIoBuffer = extern struct {
        ptr: ?[*]u8,
        len: u64,
        cap: u64,
    };

    const SaFsReadBuffer = extern struct {
        ptr: ?[*]u8,
        len: u64,
        cap: u64,
    };

    const SaNetAddr = extern struct {
        family: u32,
        port: u32,
        host_ptr: ?[*]u8,
        host_len: u64,
        scope_id: u64,
    };

    const SaProcessArgv = extern struct {
        data: ?[*]const u8,
        len: u64,
    };

    const SaTermWinsize = extern struct {
        row: u16,
        col: u16,
        xpixel: u16,
        ypixel: u16,
    };

    const SaTermEpollEvent = extern struct {
        events: u32,
        data: u64,
    };

    const SaTimeDate = extern struct {
        unix_ms: i64,
        unix_ns: i64,
        year: u16,
        month: u8,
        day: u8,
        hour: u8,
        minute: u8,
        second: u8,
        millisecond: u16,
    };

    const FallibleU64 = extern struct {
        status: i32,
        value: u64,
    };

    const FallibleI32 = extern struct {
        status: i32,
        value: i32,
    };

    const SaRegexGroup = extern struct {
        ptr: ?[*]const u8,
        len: u64,
    };

    const SaRegexMatch = extern struct {
        matched: u32,
        group_count: u32,
        groups: ?[*]SaRegexGroup,
    };
};

fn expectLayout(
    comptime C: type,
    comptime Zig: type,
    comptime expected_size: usize,
    comptime expected_alignment: usize,
) !void {
    comptime {
        if (@sizeOf(C) != expected_size or @sizeOf(Zig) != expected_size) {
            @compileError(std.fmt.comptimePrint(
                "ABI size changed: C {s}={d}, Zig {s}={d}, expected={d}",
                .{ @typeName(C), @sizeOf(C), @typeName(Zig), @sizeOf(Zig), expected_size },
            ));
        }
        if (@alignOf(C) != expected_alignment or @alignOf(Zig) != expected_alignment) {
            @compileError(std.fmt.comptimePrint(
                "ABI alignment changed: C {s}={d}, Zig {s}={d}, expected={d}",
                .{ @typeName(C), @alignOf(C), @typeName(Zig), @alignOf(Zig), expected_alignment },
            ));
        }
    }
    try std.testing.expectEqual(expected_size, @sizeOf(C));
    try std.testing.expectEqual(expected_size, @sizeOf(Zig));
    try std.testing.expectEqual(expected_alignment, @alignOf(C));
    try std.testing.expectEqual(expected_alignment, @alignOf(Zig));
}

fn expectOffset(
    comptime C: type,
    comptime Zig: type,
    comptime field: []const u8,
    comptime expected_offset: usize,
) !void {
    comptime {
        if (@offsetOf(C, field) != expected_offset or @offsetOf(Zig, field) != expected_offset) {
            @compileError(std.fmt.comptimePrint(
                "ABI field offset changed: {s}.{s}={d}, {s}.{s}={d}, expected={d}",
                .{
                    @typeName(C),
                    field,
                    @offsetOf(C, field),
                    @typeName(Zig),
                    field,
                    @offsetOf(Zig, field),
                    expected_offset,
                },
            ));
        }
    }
    try std.testing.expectEqual(expected_offset, @offsetOf(C, field));
    try std.testing.expectEqual(expected_offset, @offsetOf(Zig, field));
}

test "64-bit desktop C and Zig v1 struct layouts remain stable" {
    try std.testing.expectEqual(@as(usize, 8), @sizeOf(usize));

    try expectLayout(c.SaJsonToken, zig_abi.SaJsonToken, 24, 8);
    try expectOffset(c.SaJsonToken, zig_abi.SaJsonToken, "kind", 0);
    try expectOffset(c.SaJsonToken, zig_abi.SaJsonToken, "text_ptr", 8);
    try expectOffset(c.SaJsonToken, zig_abi.SaJsonToken, "text_len", 16);

    try expectLayout(c.SaJsonStringifyOptions, zig_abi.SaJsonStringifyOptions, 8, 4);
    try expectOffset(c.SaJsonStringifyOptions, zig_abi.SaJsonStringifyOptions, "whitespace", 0);
    try expectOffset(c.SaJsonStringifyOptions, zig_abi.SaJsonStringifyOptions, "emit_null_optional_fields", 4);
    try expectOffset(c.SaJsonStringifyOptions, zig_abi.SaJsonStringifyOptions, "emit_strings_as_arrays", 5);
    try expectOffset(c.SaJsonStringifyOptions, zig_abi.SaJsonStringifyOptions, "escape_unicode", 6);
    try expectOffset(c.SaJsonStringifyOptions, zig_abi.SaJsonStringifyOptions, "emit_nonportable_numbers_as_strings", 7);

    try expectLayout(c.SaIoBuffer, zig_abi.SaIoBuffer, 24, 8);
    try expectOffset(c.SaIoBuffer, zig_abi.SaIoBuffer, "ptr", 0);
    try expectOffset(c.SaIoBuffer, zig_abi.SaIoBuffer, "len", 8);
    try expectOffset(c.SaIoBuffer, zig_abi.SaIoBuffer, "cap", 16);

    try expectLayout(c.SaFsReadBuffer, zig_abi.SaFsReadBuffer, 24, 8);
    try expectOffset(c.SaFsReadBuffer, zig_abi.SaFsReadBuffer, "ptr", 0);
    try expectOffset(c.SaFsReadBuffer, zig_abi.SaFsReadBuffer, "len", 8);
    try expectOffset(c.SaFsReadBuffer, zig_abi.SaFsReadBuffer, "cap", 16);

    try expectLayout(c.SaNetAddr, zig_abi.SaNetAddr, 32, 8);
    try expectOffset(c.SaNetAddr, zig_abi.SaNetAddr, "family", 0);
    try expectOffset(c.SaNetAddr, zig_abi.SaNetAddr, "port", 4);
    try expectOffset(c.SaNetAddr, zig_abi.SaNetAddr, "host_ptr", 8);
    try expectOffset(c.SaNetAddr, zig_abi.SaNetAddr, "host_len", 16);
    try expectOffset(c.SaNetAddr, zig_abi.SaNetAddr, "scope_id", 24);

    try expectLayout(c.SaProcessArgv, zig_abi.SaProcessArgv, 16, 8);
    try expectOffset(c.SaProcessArgv, zig_abi.SaProcessArgv, "data", 0);
    try expectOffset(c.SaProcessArgv, zig_abi.SaProcessArgv, "len", 8);

    try expectLayout(c.SaTermWinsize, zig_abi.SaTermWinsize, 8, 2);
    try expectOffset(c.SaTermWinsize, zig_abi.SaTermWinsize, "row", 0);
    try expectOffset(c.SaTermWinsize, zig_abi.SaTermWinsize, "col", 2);
    try expectOffset(c.SaTermWinsize, zig_abi.SaTermWinsize, "xpixel", 4);
    try expectOffset(c.SaTermWinsize, zig_abi.SaTermWinsize, "ypixel", 6);

    try expectLayout(c.SaTermEpollEvent, zig_abi.SaTermEpollEvent, 16, 8);
    try expectOffset(c.SaTermEpollEvent, zig_abi.SaTermEpollEvent, "events", 0);
    try expectOffset(c.SaTermEpollEvent, zig_abi.SaTermEpollEvent, "data", 8);

    try expectLayout(c.SaTimeDate, zig_abi.SaTimeDate, 32, 8);
    try expectOffset(c.SaTimeDate, zig_abi.SaTimeDate, "unix_ms", 0);
    try expectOffset(c.SaTimeDate, zig_abi.SaTimeDate, "unix_ns", 8);
    try expectOffset(c.SaTimeDate, zig_abi.SaTimeDate, "year", 16);
    try expectOffset(c.SaTimeDate, zig_abi.SaTimeDate, "month", 18);
    try expectOffset(c.SaTimeDate, zig_abi.SaTimeDate, "day", 19);
    try expectOffset(c.SaTimeDate, zig_abi.SaTimeDate, "hour", 20);
    try expectOffset(c.SaTimeDate, zig_abi.SaTimeDate, "minute", 21);
    try expectOffset(c.SaTimeDate, zig_abi.SaTimeDate, "second", 22);
    try expectOffset(c.SaTimeDate, zig_abi.SaTimeDate, "millisecond", 24);

    try expectLayout(c.sa_std_fallible_u64, zig_abi.FallibleU64, 16, 8);
    try expectOffset(c.sa_std_fallible_u64, zig_abi.FallibleU64, "status", 0);
    try expectOffset(c.sa_std_fallible_u64, zig_abi.FallibleU64, "value", 8);

    try expectLayout(c.sa_std_fallible_i32, zig_abi.FallibleI32, 8, 4);
    try expectOffset(c.sa_std_fallible_i32, zig_abi.FallibleI32, "status", 0);
    try expectOffset(c.sa_std_fallible_i32, zig_abi.FallibleI32, "value", 4);

    try expectLayout(c.SaRegexGroup, zig_abi.SaRegexGroup, 16, 8);
    try expectOffset(c.SaRegexGroup, zig_abi.SaRegexGroup, "ptr", 0);
    try expectOffset(c.SaRegexGroup, zig_abi.SaRegexGroup, "len", 8);

    try expectLayout(c.SaRegexMatch, zig_abi.SaRegexMatch, 16, 8);
    try expectOffset(c.SaRegexMatch, zig_abi.SaRegexMatch, "matched", 0);
    try expectOffset(c.SaRegexMatch, zig_abi.SaRegexMatch, "group_count", 4);
    try expectOffset(c.SaRegexMatch, zig_abi.SaRegexMatch, "groups", 8);
}

test "network constants and declarations preserve v1 contracts" {
    try std.testing.expectEqual(@as(u32, 0), c.SA_NET_AF_UNSPEC);
    try std.testing.expectEqual(@as(u32, 4), c.SA_NET_AF_IPV4);
    try std.testing.expectEqual(@as(u32, 6), c.SA_NET_AF_IPV6);
    try std.testing.expectEqual(@as(u32, 2), c.SA_NET_AF_INET);
    try std.testing.expectEqual(@as(u32, 10), c.SA_NET_AF_INET6);
    try std.testing.expectEqual(@as(u32, 0), c.SA_NET_UNIX_ADDR_UNNAMED);
    try std.testing.expectEqual(@as(u32, 1), c.SA_NET_UNIX_ADDR_PATHNAME);
    try std.testing.expectEqual(@as(u32, 2), c.SA_NET_UNIX_ADDR_ABSTRACT);

    const addr_free = @typeInfo(@TypeOf(c.sa_net_addr_free)).@"fn";
    const unix_addr_free = @typeInfo(@TypeOf(c.sa_net_unix_addr_free)).@"fn";
    try std.testing.expect(addr_free.return_type.? == c.sa_std_fallible_i32);
    try std.testing.expect(unix_addr_free.return_type.? == c.sa_std_fallible_i32);
    try std.testing.expectEqual(@as(usize, 1), unix_addr_free.params.len);

    try std.testing.expect(@hasDecl(c, "sa_std_net_tcp_stream_set_keepalive"));
    try std.testing.expect(@hasDecl(c, "sa_std_net_tcp_stream_set_keepalive_params"));
    const set_keepalive = @typeInfo(@TypeOf(c.sa_std_net_tcp_stream_set_keepalive)).@"fn";
    const set_keepalive_params = @typeInfo(@TypeOf(c.sa_std_net_tcp_stream_set_keepalive_params)).@"fn";
    try std.testing.expectEqual(@as(usize, 2), set_keepalive.params.len);
    try std.testing.expectEqual(@as(usize, 4), set_keepalive_params.params.len);
    try std.testing.expect(set_keepalive.return_type.? == i32);
    try std.testing.expect(set_keepalive_params.return_type.? == i32);
}
