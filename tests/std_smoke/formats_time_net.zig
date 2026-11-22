//! json / time / net helpers -- split from tests/std_smoke.zig (shared helpers: helpers.zig).
const std = @import("std");
const saasm = @import("saasm");
const sio = @import("sio");
const helpers = @import("helpers.zig");

const repoRoot = helpers.repoRoot;
const readFileAlloc = helpers.readFileAlloc;
const writeSource = helpers.writeSource;
const runCommand = helpers.runCommand;
const runCommandWithEnvMap = helpers.runCommandWithEnvMap;
const runCommandAnyExit = helpers.runCommandAnyExit;
const NormalizedInstruction = helpers.NormalizedInstruction;
const normalizeInstruction = helpers.normalizeInstruction;
const expectFlattenEquivalent = helpers.expectFlattenEquivalent;
const dumpInstructionTexts = helpers.dumpInstructionTexts;
const flattenFixture = helpers.flattenFixture;

test "sa_std json helpers are concrete and verifiable" {
    const json_layout = try readFileAlloc(std.testing.allocator, "sa_std/encoding/json.sal");
    defer std.testing.allocator.free(json_layout);
    try std.testing.expect(std.mem.containsAtLeast(u8, json_layout, 1, "SA_JSON_KIND_OBJECT"));
    try std.testing.expect(std.mem.containsAtLeast(u8, json_layout, 1, "SA_JSON_KIND_NULL"));
    try std.testing.expect(std.mem.containsAtLeast(u8, json_layout, 1, "SA_JSON_TOKEN_OBJECT_BEGIN"));
    try std.testing.expect(std.mem.containsAtLeast(u8, json_layout, 1, "SA_JSON_WHITESPACE_MINIFIED"));

    const json_iface = try readFileAlloc(std.testing.allocator, "sa_std/encoding/json.sai");
    defer std.testing.allocator.free(json_iface);
    try std.testing.expect(std.mem.containsAtLeast(u8, json_iface, 1, "sa_json_parse"));
    try std.testing.expect(std.mem.containsAtLeast(u8, json_iface, 1, "sa_json_object_get"));
    try std.testing.expect(std.mem.containsAtLeast(u8, json_iface, 1, "sa_json_array_get"));
    try std.testing.expect(std.mem.containsAtLeast(u8, json_iface, 1, "sa_json_object_key_at"));
    try std.testing.expect(std.mem.containsAtLeast(u8, json_iface, 1, "sa_json_object_get_string"));
    try std.testing.expect(std.mem.containsAtLeast(u8, json_iface, 1, "sa_json_object_get_bool"));
    try std.testing.expect(std.mem.containsAtLeast(u8, json_iface, 1, "sa_json_object_get_i64"));
    try std.testing.expect(std.mem.containsAtLeast(u8, json_iface, 1, "sa_json_object_get_f64"));
    try std.testing.expect(std.mem.containsAtLeast(u8, json_iface, 1, "@extern sa_json_string_ptr(node: ptr) -> &ptr"));
    try std.testing.expect(std.mem.containsAtLeast(u8, json_iface, 1, "@extern sa_json_buffer_data(&buffer: ptr) -> &ptr"));
    try std.testing.expect(std.mem.containsAtLeast(u8, json_iface, 1, "@extern sa_json_stream_get_slice_ptr(stream: ptr) -> &ptr"));
    try std.testing.expect(std.mem.containsAtLeast(u8, json_iface, 1, "sa_json_stringify"));
    try std.testing.expect(std.mem.containsAtLeast(u8, json_iface, 1, "sa_json_buffer_free"));
    try std.testing.expect(std.mem.containsAtLeast(u8, json_iface, 1, "sa_json_scanner_next"));
    try std.testing.expect(std.mem.containsAtLeast(u8, json_iface, 1, "sa_json_stream_new"));
    try std.testing.expect(std.mem.containsAtLeast(u8, json_iface, 1, "sa_json_stream_next"));
    try std.testing.expect(std.mem.containsAtLeast(u8, json_iface, 1, "sa_json_stream_get_slice_ptr"));
    try std.testing.expect(std.mem.containsAtLeast(u8, json_iface, 1, "sa_json_stream_get_slice_len"));
    try std.testing.expect(std.mem.containsAtLeast(u8, json_iface, 1, "sa_json_stream_free"));
    try std.testing.expect(std.mem.containsAtLeast(u8, json_iface, 1, "sa_json_writer_write_node"));
    try std.testing.expect(std.mem.containsAtLeast(u8, json_iface, 1, "sa_json_writer_finish"));

    const json_src = try readFileAlloc(std.testing.allocator, "sa_std/encoding/json.sa");
    defer std.testing.allocator.free(json_src);
    try std.testing.expect(std.mem.containsAtLeast(u8, json_src, 1, "@import \"json.sal\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, json_src, 1, "@import \"json.sai\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, json_src, 1, "[MACRO] JSON_OBJECT_GET_STRING"));
    try std.testing.expect(std.mem.containsAtLeast(u8, json_src, 1, "[MACRO] JSON_OBJECT_GET_BOOL"));
    try std.testing.expect(std.mem.containsAtLeast(u8, json_src, 1, "[MACRO] JSON_OBJECT_GET_I64"));
    try std.testing.expect(std.mem.containsAtLeast(u8, json_src, 1, "[MACRO] JSON_AS_I64"));
    try std.testing.expect(std.mem.containsAtLeast(u8, json_src, 1, "[MACRO] JSON_IS_OBJECT"));
    try std.testing.expect(std.mem.containsAtLeast(u8, json_src, 1, "[MACRO] JSON_ARRAY_GET"));
    try std.testing.expect(std.mem.containsAtLeast(u8, json_src, 1, "[MACRO] JSON_STRING_PTR"));
    try std.testing.expect(std.mem.containsAtLeast(u8, json_src, 1, "[MACRO] JSON_ARRAY_LOOP_INIT"));
    try std.testing.expect(std.mem.containsAtLeast(u8, json_src, 1, "[MACRO] JSON_OBJECT_LOOP_INIT"));
    try std.testing.expect(std.mem.containsAtLeast(u8, json_src, 1, "[MACRO] JSON_WRITER_BEGIN_OBJECT"));
    try std.testing.expect(std.mem.containsAtLeast(u8, json_src, 1, "[MACRO] JSON_WRITER_FIELD_STRING"));
    try std.testing.expect(std.mem.containsAtLeast(u8, json_src, 1, "[MACRO] JSON_WRITER_FIELD_NODE"));
    try std.testing.expect(std.mem.containsAtLeast(u8, json_src, 1, "[MACRO] JSON_WRITER_WRITE_STRING"));
    try std.testing.expect(std.mem.containsAtLeast(u8, json_src, 1, "[MACRO] JSON_WRITER_WRITE_NODE"));

    const json_macro_fixture =
        \\@import "sa_std/encoding/json.sa"
        \\
        \\@const JSON_DOC = utf8:"{\"name\":\"sci\",\"active\":true,\"count\":7,\"ratio\":1.5,\"items\":[{\"type\":\"object\"}]}"
        \\@const K_NAME = utf8:"name"
        \\@const K_ACTIVE = utf8:"active"
        \\@const K_COUNT = utf8:"count"
        \\@const K_RATIO = utf8:"ratio"
        \\@const K_ITEMS = utf8:"items"
        \\@const K_FIRST = utf8:"first"
        \\@const K_NONE = utf8:"none"
        \\@const V_NAME = utf8:"sci"
        \\
        \\#def JSON_DOC_LEN = 78
        \\#def K_NAME_LEN = 4
        \\#def K_ACTIVE_LEN = 6
        \\#def K_COUNT_LEN = 5
        \\#def K_RATIO_LEN = 5
        \\#def K_ITEMS_LEN = 5
        \\#def K_FIRST_LEN = 5
        \\#def K_NONE_LEN = 4
        \\#def V_NAME_LEN = 3
        \\
        \\@main() -> i32:
        \\L_ENTRY:
        \\    EXPAND JSON_PARSE root, JSON_DOC, JSON_DOC_LEN
        \\    EXPAND JSON_OBJECT_GET items_status, items, root, K_ITEMS, K_ITEMS_LEN
        \\    EXPAND JSON_ARRAY_LOOP_INIT array_status, idx, item_count, items
        \\    EXPAND JSON_ARRAY_LOOP_HAS_NEXT has_item, idx, item_count
        \\    EXPAND JSON_ARRAY_GET item_status, item0, items, idx
        \\    EXPAND JSON_ARRAY_LOOP_NEXT next_idx, idx
        \\    EXPAND JSON_OBJECT_LOOP_INIT object_status, object_idx, object_count, root
        \\    EXPAND JSON_OBJECT_LOOP_HAS_NEXT has_key, object_idx, object_count
        \\    EXPAND JSON_OBJECT_KEY_AT key_status, key_ptr, key_len, root, object_idx
        \\    EXPAND JSON_OBJECT_LOOP_NEXT next_object_idx, object_idx
        \\    EXPAND JSON_OBJECT_GET_STRING name_status, name_ptr, name_len, root, K_NAME, K_NAME_LEN
        \\    EXPAND JSON_OBJECT_GET_BOOL active_status, active, root, K_ACTIVE, K_ACTIVE_LEN
        \\    EXPAND JSON_OBJECT_GET_I64 count_status, count_value, root, K_COUNT, K_COUNT_LEN
        \\    EXPAND JSON_OBJECT_GET_F64 ratio_status, ratio_value, root, K_RATIO, K_RATIO_LEN
        \\    EXPAND JSON_WRITER_NEW_MINIFIED writer_status, writer
        \\    EXPAND JSON_WRITER_BEGIN_OBJECT begin_status, writer
        \\    EXPAND JSON_WRITER_FIELD_STRING field_name_status, writer, K_NAME, K_NAME_LEN, V_NAME, V_NAME_LEN
        \\    EXPAND JSON_WRITER_FIELD_BOOL field_active_status, writer, K_ACTIVE, K_ACTIVE_LEN, active
        \\    EXPAND JSON_WRITER_FIELD_I64 field_count_status, writer, K_COUNT, K_COUNT_LEN, count_value
        \\    EXPAND JSON_WRITER_FIELD_F64 field_ratio_status, writer, K_RATIO, K_RATIO_LEN, ratio_value
        \\    EXPAND JSON_WRITER_FIELD_NULL field_none_status, writer, K_NONE, K_NONE_LEN
        \\    EXPAND JSON_WRITER_FIELD_NODE field_first_status, writer, K_FIRST, K_FIRST_LEN, item0
        \\    EXPAND JSON_WRITER_END_OBJECT end_status, writer
        \\    EXPAND JSON_WRITER_FINISH finish_status, buffer, writer
        \\    EXPAND JSON_BUFFER_SLICE buffer_ptr, buffer_len, buffer
        \\    EXPAND JSON_BUFFER_FREE buffer
        \\    EXPAND JSON_WRITER_FREE writer
        \\    EXPAND JSON_FREE item0
        \\    EXPAND JSON_FREE items
        \\    EXPAND JSON_FREE root
        \\
        \\    !items_status
        \\    !array_status
        \\    !idx
        \\    !item_count
        \\    !has_item
        \\    !item_status
        \\    !next_idx
        \\    !object_status
        \\    !object_idx
        \\    !object_count
        \\    !has_key
        \\    !key_status
        \\    !key_ptr
        \\    !key_len
        \\    !next_object_idx
        \\    !name_status
        \\    !name_ptr
        \\    !name_len
        \\    !active_status
        \\    !active
        \\    !count_status
        \\    !count_value
        \\    !ratio_status
        \\    !ratio_value
        \\    !writer_status
        \\    !begin_status
        \\    !field_name_status
        \\    !field_active_status
        \\    !field_count_status
        \\    !field_ratio_status
        \\    !field_none_status
        \\    !field_first_status
        \\    !end_status
        \\    !finish_status
        \\    !buffer_ptr
        \\    !buffer_len
        \\    return 0
    ;
    var json_macro_flat = try flattenFixture(std.testing.allocator, "tests/json_macro_fixture.sa", json_macro_fixture);
    defer json_macro_flat.deinit(std.testing.allocator);
    const json_macro_verified = try saasm.referee.verify(std.testing.allocator, json_macro_flat.instructions, json_macro_flat.const_decls);
    switch (json_macro_verified) {
        .ok => |ok| {
            var owned = ok;
            defer owned.deinit(std.testing.allocator);
        },
        .trap => |report| {
            std.debug.print("json macro verifier trap: {s}\n", .{report.message});
            return error.TestUnexpectedResult;
        },
    }

    const regex_layout = try readFileAlloc(std.testing.allocator, "sa_std/text/regex.sal");
    defer std.testing.allocator.free(regex_layout);
    try std.testing.expect(std.mem.containsAtLeast(u8, regex_layout, 1, "SA_REGEX_REG_NOERROR"));
    try std.testing.expect(std.mem.containsAtLeast(u8, regex_layout, 1, "SA_REGEX_REG_OK"));

    const regex_iface = try readFileAlloc(std.testing.allocator, "sa_std/text/regex.sai");
    defer std.testing.allocator.free(regex_iface);
    try std.testing.expect(std.mem.containsAtLeast(u8, regex_iface, 1, "sa_regex_compile"));
    try std.testing.expect(std.mem.containsAtLeast(u8, regex_iface, 1, "sa_regex_match"));
    try std.testing.expect(std.mem.containsAtLeast(u8, regex_iface, 1, "sa_regex_group_count"));
    try std.testing.expect(std.mem.containsAtLeast(u8, regex_iface, 1, "sa_regex_free"));
    try std.testing.expect(std.mem.containsAtLeast(u8, regex_iface, 1, "sa_regex_match_free"));

    const regex_src = try readFileAlloc(std.testing.allocator, "sa_std/text/regex.sa");
    defer std.testing.allocator.free(regex_src);
    try std.testing.expect(std.mem.containsAtLeast(u8, regex_src, 1, "@import \"regex.sal\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, regex_src, 1, "@import \"regex.sai\""));
}

test "sa_std time helpers are concrete and verifiable" {
    const time_layout = try readFileAlloc(std.testing.allocator, "sa_std/time.sal");
    defer std.testing.allocator.free(time_layout);
    try std.testing.expectEqualStrings(
        "#def Time_NS_PER_US = 1000\n#def Time_NS_PER_MS = 1000000\n#def Time_NS_PER_S  = 1000000000\n#def Time_MS_PER_S  = 1000\n#def TimeDate_SIZE = 32\n#def TimeDate_unix_ms = +0\n#def TimeDate_unix_ns = +8\n#def TimeDate_year = +16\n#def TimeDate_month = +18\n#def TimeDate_day = +19\n#def TimeDate_hour = +20\n#def TimeDate_minute = +21\n#def TimeDate_second = +22\n#def TimeDate_millisecond = +24\n",
        time_layout,
    );

    const time_iface = try readFileAlloc(std.testing.allocator, "sa_std/time.sai");
    defer std.testing.allocator.free(time_iface);
    try std.testing.expect(std.mem.containsAtLeast(u8, time_iface, 1, "sa_time_instant_ns"));
    try std.testing.expect(std.mem.containsAtLeast(u8, time_iface, 1, "sa_time_unix_ms"));
    try std.testing.expect(std.mem.containsAtLeast(u8, time_iface, 1, "sa_time_utc_now"));
    try std.testing.expect(std.mem.containsAtLeast(u8, time_iface, 1, "sa_time_sleep_ms"));

    const time_src = try readFileAlloc(std.testing.allocator, "sa_std/time.sa");
    defer std.testing.allocator.free(time_src);
    try std.testing.expect(std.mem.containsAtLeast(u8, time_src, 1, "[MACRO] TIME_NOW_NS"));
    try std.testing.expect(std.mem.containsAtLeast(u8, time_src, 1, "[MACRO] TIME_NOW_UNIX_MS"));
    try std.testing.expect(std.mem.containsAtLeast(u8, time_src, 1, "[MACRO] TIME_UTC_NOW"));
    try std.testing.expect(std.mem.containsAtLeast(u8, time_src, 1, "[MACRO] TIME_SLEEP_MS"));
    try std.testing.expect(std.mem.containsAtLeast(u8, time_src, 1, "[MACRO] TIME_DURATION_FROM_MS"));
    try std.testing.expect(std.mem.containsAtLeast(u8, time_src, 1, "[MACRO] TIME_DURATION_FROM_US"));
    try std.testing.expect(std.mem.containsAtLeast(u8, time_src, 1, "[MACRO] TIME_DURATION_FROM_NS"));
    try std.testing.expect(std.mem.containsAtLeast(u8, time_src, 1, "[MACRO] TIME_DURATION_ZERO"));
    try std.testing.expect(std.mem.containsAtLeast(u8, time_src, 1, "[MACRO] TIME_DURATION_MAX"));
    try std.testing.expect(std.mem.containsAtLeast(u8, time_src, 1, "[MACRO] TIME_DURATION_IS_ZERO"));
    try std.testing.expect(std.mem.containsAtLeast(u8, time_src, 1, "[MACRO] TIME_DURATION_SUBSEC_NANOS"));
    try std.testing.expect(std.mem.containsAtLeast(u8, time_src, 1, "[MACRO] TIME_CHECKED_ADD_NS"));
    try std.testing.expect(std.mem.containsAtLeast(u8, time_src, 1, "[MACRO] TIME_CHECKED_SUB_NS"));
    try std.testing.expect(std.mem.containsAtLeast(u8, time_src, 1, "[MACRO] TIME_SATURATING_MUL_NS"));
    try std.testing.expect(std.mem.containsAtLeast(u8, time_src, 1, "[MACRO] TIME_SATURATING_DIV_NS"));
    try std.testing.expect(std.mem.containsAtLeast(u8, time_src, 1, "[MACRO] TIME_DURATION_CHECKED_ADD_NS"));
    try std.testing.expect(std.mem.containsAtLeast(u8, time_src, 1, "[MACRO] TIME_DURATION_SATURATING_MUL_NS"));
    try std.testing.expect(std.mem.containsAtLeast(u8, time_src, 1, "[MACRO] TIME_DURATION_ABS_DIFF_NS"));
    try std.testing.expect(std.mem.containsAtLeast(u8, time_src, 1, "[MACRO] TIME_CHECKED_DURATION_SINCE"));
    try std.testing.expect(std.mem.containsAtLeast(u8, time_src, 1, "[MACRO] TIME_INSTANT_ELAPSED"));

    var time_flat = try flattenFixture(std.testing.allocator, "sa_std/time.sa", time_src);
    defer time_flat.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(usize, 7), time_flat.instructions.len);
    try std.testing.expectEqual(@as(usize, 7), time_flat.function_sigs.len);
}

test "sa_std net helpers are concrete and verifiable" {
    const net_layout = try readFileAlloc(std.testing.allocator, "sa_std/net.sal");
    defer std.testing.allocator.free(net_layout);
    try std.testing.expect(std.mem.containsAtLeast(u8, net_layout, 1, "SA_NET_OK"));
    try std.testing.expect(std.mem.containsAtLeast(u8, net_layout, 1, "SA_NET_AF_INET"));
    try std.testing.expect(std.mem.containsAtLeast(u8, net_layout, 1, "SA_NET_SOCKET_OPTION_ENABLE"));
    try std.testing.expect(std.mem.containsAtLeast(u8, net_layout, 1, "NetTcpIncoming_SIZE"));

    const net_iface = try readFileAlloc(std.testing.allocator, "sa_std/net.sai");
    defer std.testing.allocator.free(net_iface);
    const c_header = try readFileAlloc(std.testing.allocator, "src/runtime/sa_std.h");
    defer std.testing.allocator.free(c_header);
    try std.testing.expect(std.mem.containsAtLeast(u8, net_iface, 1, "sa_std_net_tcp_stream_peek"));
    try std.testing.expect(std.mem.containsAtLeast(u8, net_iface, 1, "sa_std_net_tcp_stream_peer_addr"));
    try std.testing.expect(std.mem.containsAtLeast(u8, net_iface, 1, "sa_std_net_tcp_stream_local_addr"));
    try std.testing.expect(std.mem.containsAtLeast(u8, net_iface, 1, "sa_std_net_tcp_stream_read_timeout"));
    try std.testing.expect(std.mem.containsAtLeast(u8, net_iface, 1, "sa_std_net_tcp_stream_take_error"));
    try std.testing.expect(std.mem.containsAtLeast(u8, net_iface, 1, "sa_std_net_tcp_listener_ttl"));
    try std.testing.expect(std.mem.containsAtLeast(u8, net_iface, 1, "sa_std_net_udp_local_addr"));
    try std.testing.expect(std.mem.containsAtLeast(u8, net_iface, 1, "sa_std_net_udp_peer_addr"));
    try std.testing.expect(std.mem.containsAtLeast(u8, net_iface, 1, "sa_std_net_udp_peek"));
    try std.testing.expect(std.mem.containsAtLeast(u8, net_iface, 1, "sa_std_net_udp_peek_from"));
    try std.testing.expect(std.mem.containsAtLeast(u8, net_iface, 1, "sa_std_net_udp_take_error"));
    try std.testing.expect(std.mem.containsAtLeast(u8, net_iface, 1, "sa_std_net_udp_recv_from"));
    try std.testing.expect(std.mem.containsAtLeast(u8, net_iface, 1, "sa_std_net_udp_set_multicast_loop_v4"));
    try std.testing.expect(std.mem.containsAtLeast(u8, net_iface, 1, "sa_std_net_udp_set_multicast_ttl_v4"));
    try std.testing.expect(std.mem.containsAtLeast(u8, net_iface, 1, "sa_std_net_udp_multicast_loop_v4"));
    try std.testing.expect(std.mem.containsAtLeast(u8, net_iface, 1, "sa_std_net_udp_multicast_ttl_v4"));
    try std.testing.expect(std.mem.containsAtLeast(u8, net_iface, 1, "sa_std_net_udp_join_multicast_v4"));
    try std.testing.expect(std.mem.containsAtLeast(u8, net_iface, 1, "sa_std_net_udp_leave_multicast_v4"));
    try std.testing.expect(std.mem.containsAtLeast(u8, net_iface, 1, "sa_std_net_udp_join_multicast_v6"));
    try std.testing.expect(std.mem.containsAtLeast(u8, net_iface, 1, "sa_std_net_udp_leave_multicast_v6"));
    try std.testing.expect(std.mem.containsAtLeast(u8, net_iface, 1, "sa_std_net_to_socket_addr_first"));
    try std.testing.expect(std.mem.containsAtLeast(u8, net_iface, 1, "sa_std_net_addr_format"));
    try std.testing.expect(std.mem.containsAtLeast(u8, net_iface, 1, "sa_net_addr_scope_id"));
    try std.testing.expect(std.mem.containsAtLeast(u8, c_header, 1, "sa_std_net_to_socket_addr_first"));
    try std.testing.expect(std.mem.containsAtLeast(u8, c_header, 1, "sa_std_net_addr_format"));

    const net_src = try readFileAlloc(std.testing.allocator, "sa_std/net.sa");
    defer std.testing.allocator.free(net_src);
    try std.testing.expect(std.mem.containsAtLeast(u8, net_src, 1, "[MACRO] NET_TCP_CONNECT"));
    try std.testing.expect(std.mem.containsAtLeast(u8, net_src, 1, "[MACRO] NET_TCP_LISTENER_BIND_PORT"));
    try std.testing.expect(std.mem.containsAtLeast(u8, net_src, 1, "[MACRO] NET_TCP_STREAM_PEEK"));
    try std.testing.expect(std.mem.containsAtLeast(u8, net_src, 1, "[MACRO] NET_TCP_STREAM_LOCAL_ADDR"));
    try std.testing.expect(std.mem.containsAtLeast(u8, net_src, 1, "[MACRO] NET_TCP_STREAM_SET_NODELAY"));
    try std.testing.expect(std.mem.containsAtLeast(u8, net_src, 1, "[MACRO] NET_TCP_STREAM_NODELAY"));
    try std.testing.expect(std.mem.containsAtLeast(u8, net_src, 1, "[MACRO] NET_TCP_STREAM_TAKE_ERROR"));
    try std.testing.expect(std.mem.containsAtLeast(u8, net_src, 1, "[MACRO] NET_TCP_LISTENER_SET_NONBLOCKING"));
    try std.testing.expect(std.mem.containsAtLeast(u8, net_src, 1, "[MACRO] NET_TCP_LISTENER_TAKE_ERROR"));
    try std.testing.expect(std.mem.containsAtLeast(u8, net_src, 1, "[MACRO] NET_TCP_INCOMING_NEW"));
    try std.testing.expect(std.mem.containsAtLeast(u8, net_src, 1, "[MACRO] NET_TCP_INCOMING_LISTENER"));
    try std.testing.expect(std.mem.containsAtLeast(u8, net_src, 1, "[MACRO] NET_TCP_INCOMING_NEXT"));
    try std.testing.expect(std.mem.containsAtLeast(u8, net_src, 1, "[MACRO] NET_TCP_LISTENER_INCOMING"));
    try std.testing.expect(std.mem.containsAtLeast(u8, net_src, 1, "[MACRO] NET_UDP_BIND"));
    try std.testing.expect(std.mem.containsAtLeast(u8, net_src, 1, "[MACRO] NET_UDP_PEER_ADDR"));
    try std.testing.expect(std.mem.containsAtLeast(u8, net_src, 1, "[MACRO] NET_UDP_PEEK"));
    try std.testing.expect(std.mem.containsAtLeast(u8, net_src, 1, "[MACRO] NET_UDP_PEEK_FROM"));
    try std.testing.expect(std.mem.containsAtLeast(u8, net_src, 1, "[MACRO] NET_UDP_TAKE_ERROR"));
    try std.testing.expect(std.mem.containsAtLeast(u8, net_src, 1, "[MACRO] NET_UDP_RECV_FROM"));
    try std.testing.expect(std.mem.containsAtLeast(u8, net_src, 1, "[MACRO] NET_UDP_SET_MULTICAST_LOOP_V4"));
    try std.testing.expect(std.mem.containsAtLeast(u8, net_src, 1, "[MACRO] NET_UDP_SET_MULTICAST_TTL_V4"));
    try std.testing.expect(std.mem.containsAtLeast(u8, net_src, 1, "[MACRO] NET_UDP_MULTICAST_LOOP_V4"));
    try std.testing.expect(std.mem.containsAtLeast(u8, net_src, 1, "[MACRO] NET_UDP_MULTICAST_TTL_V4"));
    try std.testing.expect(std.mem.containsAtLeast(u8, net_src, 1, "[MACRO] NET_UDP_JOIN_MULTICAST_V4"));
    try std.testing.expect(std.mem.containsAtLeast(u8, net_src, 1, "[MACRO] NET_UDP_LEAVE_MULTICAST_V4"));
    try std.testing.expect(std.mem.containsAtLeast(u8, net_src, 1, "[MACRO] NET_UDP_JOIN_MULTICAST_V6"));
    try std.testing.expect(std.mem.containsAtLeast(u8, net_src, 1, "[MACRO] NET_UDP_LEAVE_MULTICAST_V6"));
    try std.testing.expect(std.mem.containsAtLeast(u8, net_src, 1, "[MACRO] NET_TO_SOCKET_ADDR_FIRST"));
    try std.testing.expect(std.mem.containsAtLeast(u8, net_src, 1, "[MACRO] NET_ADDR_FORMAT"));
    try std.testing.expect(std.mem.containsAtLeast(u8, net_src, 1, "[MACRO] NET_ADDR_SCOPE_ID"));
    try std.testing.expect(std.mem.containsAtLeast(u8, net_src, 1, "[MACRO] NET_ADDR_IS_IPV4"));

    var net_flat = try flattenFixture(std.testing.allocator, "sa_std/net.sa", net_src);
    defer net_flat.deinit(std.testing.allocator);
    try std.testing.expect(net_flat.function_sigs.len >= 60);
}
