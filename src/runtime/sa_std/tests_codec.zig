const std = @import("std");
const sa_std = @import("../sa_std.zig");
const AFT = @import("../sa_std.zig").AFT;
const IPPROTOT = @import("../sa_std.zig").IPPROTOT;
const PthreadHandle = @import("../sa_std.zig").PthreadHandle;
const SA_REGEX_EXTENDED = @import("../sa_std.zig").SA_REGEX_EXTENDED;
const SA_STD_ERR_ACCESS = @import("../sa_std.zig").SA_STD_ERR_ACCESS;
const SA_STD_ERR_ALREADY_EXISTS = @import("../sa_std.zig").SA_STD_ERR_ALREADY_EXISTS;
const SA_STD_ERR_INVALID_ARGUMENT = @import("../sa_std.zig").SA_STD_ERR_INVALID_ARGUMENT;
const SA_STD_ERR_INVALID_HANDLE = @import("../sa_std.zig").SA_STD_ERR_INVALID_HANDLE;
const SA_STD_ERR_IO = @import("../sa_std.zig").SA_STD_ERR_IO;
const SA_STD_ERR_NET = @import("../sa_std.zig").SA_STD_ERR_NET;
const SA_STD_ERR_NOT_FOUND = @import("../sa_std.zig").SA_STD_ERR_NOT_FOUND;
const SA_STD_ERR_NO_MEMORY = @import("../sa_std.zig").SA_STD_ERR_NO_MEMORY;
const SA_STD_ERR_PERMISSION_DENIED = @import("../sa_std.zig").SA_STD_ERR_PERMISSION_DENIED;
const SA_STD_ERR_TRUNCATED = @import("../sa_std.zig").SA_STD_ERR_TRUNCATED;
const SA_STD_ERR_UNKNOWN = @import("../sa_std.zig").SA_STD_ERR_UNKNOWN;
const SA_STD_ERR_UNSUPPORTED = @import("../sa_std.zig").SA_STD_ERR_UNSUPPORTED;
const SA_STD_NET_POLL_MAX_HANDLES = @import("../sa_std.zig").SA_STD_NET_POLL_MAX_HANDLES;
const SA_STD_NET_POLL_READ = @import("../sa_std.zig").SA_STD_NET_POLL_READ;
const SA_STD_NET_POLL_WRITE = @import("../sa_std.zig").SA_STD_NET_POLL_WRITE;
const SA_STD_OK = @import("../sa_std.zig").SA_STD_OK;
const SOCKT = @import("../sa_std.zig").SOCKT;
const SOLT = @import("../sa_std.zig").SOLT;
const SOT = @import("../sa_std.zig").SOT;
const SaProcessArgv = @import("../sa_std.zig").SaProcessArgv;
const allocPthreadHandle = @import("../sa_std.zig").allocPthreadHandle;
const applySigpipeIgnore = @import("../sa_std.zig").applySigpipeIgnore;
const buildInterfaceAddressesJson = @import("../sa_std.zig").buildInterfaceAddressesJson;
const builtin = @import("../sa_std.zig").builtin;
const ensureSocketHandle = @import("../sa_std.zig").ensureSocketHandle;
const expectTimeoutRoundedUpWithin = @import("../sa_std.zig").expectTimeoutRoundedUpWithin;
const fail = @import("../sa_std.zig").fail;
const freePthreadHandle = @import("../sa_std.zig").freePthreadHandle;
const getSocketOptBool = @import("../sa_std.zig").getSocketOptBool;
const getSocketOptInt = @import("../sa_std.zig").getSocketOptInt;
const getSocketOptTimeval = @import("../sa_std.zig").getSocketOptTimeval;
const hostBytes = @import("../sa_std.zig").hostBytes;
const is_wasm = @import("../sa_std.zig").is_wasm;
const lxClose = @import("../sa_std.zig").lxClose;
const lxFcntl = @import("../sa_std.zig").lxFcntl;
const lxSocket = @import("../sa_std.zig").lxSocket;
const lxUnlink = @import("../sa_std.zig").lxUnlink;
const netErrorCodeName = @import("../sa_std.zig").netErrorCodeName;
const nsFromTimeval = @import("../sa_std.zig").nsFromTimeval;
const parseIp6FreebsdParts = @import("../sa_std.zig").parseIp6FreebsdParts;
const parseIpv6NumericFreebsd = @import("../sa_std.zig").parseIpv6NumericFreebsd;
const recv_msg_flag_pktinfo = @import("../sa_std.zig").recv_msg_flag_pktinfo;
const recv_msg_flag_timestamp = @import("../sa_std.zig").recv_msg_flag_timestamp;
const recv_multi_max_msgs = @import("../sa_std.zig").recv_multi_max_msgs;
const sa_b64dec_simd = @import("../sa_std.zig").sa_b64dec_simd;
const sa_crypto_random_bytes = @import("../sa_std.zig").sa_crypto_random_bytes;
const sa_deno_atob = @import("../sa_std.zig").sa_deno_atob;
const sa_deno_btoa = @import("../sa_std.zig").sa_deno_btoa;
const sa_deno_random_uuid = @import("../sa_std.zig").sa_deno_random_uuid;
const sa_fmt_buffer_data = @import("../sa_std.zig").sa_fmt_buffer_data;
const sa_fmt_buffer_free = @import("../sa_std.zig").sa_fmt_buffer_free;
const sa_fmt_buffer_len = @import("../sa_std.zig").sa_fmt_buffer_len;
const sa_fs_mkdir_p = @import("../sa_std.zig").sa_fs_mkdir_p;
const sa_hexdec_simd = @import("../sa_std.zig").sa_hexdec_simd;
const sa_hmac_sha1_hex = @import("../sa_std.zig").sa_hmac_sha1_hex;
const sa_hmac_sha256_hex = @import("../sa_std.zig").sa_hmac_sha256_hex;
const sa_mfind_u8 = @import("../sa_std.zig").sa_mfind_u8;
const sa_net_addr_family = @import("../sa_std.zig").sa_net_addr_family;
const sa_net_addr_free = @import("../sa_std.zig").sa_net_addr_free;
const sa_net_addr_host_len = @import("../sa_std.zig").sa_net_addr_host_len;
const sa_net_addr_port = @import("../sa_std.zig").sa_net_addr_port;
const sa_net_tcp_stream_peek = @import("../sa_std.zig").sa_net_tcp_stream_peek;
const sa_num_add_checked = @import("../sa_std.zig").sa_num_add_checked;
const sa_num_mul_checked = @import("../sa_std.zig").sa_num_mul_checked;
const sa_num_sub_checked = @import("../sa_std.zig").sa_num_sub_checked;
const sa_policy = @import("../sa_std.zig").sa_policy;
const sa_regex_buffer_data = @import("../sa_std.zig").sa_regex_buffer_data;
const sa_regex_buffer_free = @import("../sa_std.zig").sa_regex_buffer_free;
const sa_regex_buffer_len = @import("../sa_std.zig").sa_regex_buffer_len;
const sa_regex_compile = @import("../sa_std.zig").sa_regex_compile;
const sa_regex_free = @import("../sa_std.zig").sa_regex_free;
const sa_regex_group_len = @import("../sa_std.zig").sa_regex_group_len;
const sa_regex_group_ptr = @import("../sa_std.zig").sa_regex_group_ptr;
const sa_regex_group_start = @import("../sa_std.zig").sa_regex_group_start;
const sa_regex_match_all = @import("../sa_std.zig").sa_regex_match_all;
const sa_regex_match_free = @import("../sa_std.zig").sa_regex_match_free;
const sa_regex_match_list_at = @import("../sa_std.zig").sa_regex_match_list_at;
const sa_regex_match_list_count = @import("../sa_std.zig").sa_regex_match_list_count;
const sa_regex_match_list_free = @import("../sa_std.zig").sa_regex_match_list_free;
const sa_regex_replace = @import("../sa_std.zig").sa_regex_replace;
const sa_regex_replace_all = @import("../sa_std.zig").sa_regex_replace_all;
const sa_regex_split = @import("../sa_std.zig").sa_regex_split;
const sa_regex_split_count = @import("../sa_std.zig").sa_regex_split_count;
const sa_regex_split_free = @import("../sa_std.zig").sa_regex_split_free;
const sa_regex_split_len = @import("../sa_std.zig").sa_regex_split_len;
const sa_regex_split_ptr = @import("../sa_std.zig").sa_regex_split_ptr;
const sa_std_net_ja3_hash = @import("../sa_std.zig").sa_std_net_ja3_hash;
const sa_std_net_ja4_hash12 = @import("../sa_std.zig").sa_std_net_ja4_hash12;
const sa_std_net_sha256_hex = @import("../sa_std.zig").sa_std_net_sha256_hex;
const sa_unicode_normalize = @import("../sa_std.zig").sa_unicode_normalize;

test "sa_hexdec_simd clean mixed-case roundtrips" {
    const hex = "0123456789abcdefABCDEF";
    var out: [11]u8 = undefined;
    const w = sa_hexdec_simd(hex.ptr, hex.len, &out);
    try std.testing.expectEqual(@as(u64, 11), w);
    const wn: usize = @intCast(w);
    try std.testing.expectEqualSlices(u8, &.{ 0x01, 0x23, 0x45, 0x67, 0x89, 0xab, 0xcd, 0xef, 0xAB, 0xCD, 0xEF }, out[0..wn]);
}

test "sa_hexdec_simd vector block then scalar tail" {
    // 64 clean chars exercise two vector iterations; 66 exercise tail.
    const hex64 = "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef";
    var out64: [32]u8 = undefined;
    try std.testing.expectEqual(@as(u64, 32), sa_hexdec_simd(hex64.ptr, hex64.len, &out64));
    try std.testing.expectEqual(@as(u8, 0x01), out64[0]);
    try std.testing.expectEqual(@as(u8, 0xef), out64[31]);
    const hex66 = hex64 ++ "AB";
    var out66: [33]u8 = undefined;
    try std.testing.expectEqual(@as(u64, 33), sa_hexdec_simd(hex66.ptr, hex66.len, &out66));
    try std.testing.expectEqual(@as(u8, 0xAB), out66[32]);
}

test "sa_hexdec_simd stops at invalid char and odd tail" {
    const bad = "00zz00";
    var out_bad: [3]u8 = undefined;
    try std.testing.expectEqual(@as(u64, 1), sa_hexdec_simd(bad.ptr, bad.len, &out_bad));
    try std.testing.expectEqual(@as(u8, 0x00), out_bad[0]);
    // Invalid inside the second vector block falls back to scalar stop.
    const bad64 = "0123456789abcdef0123456789abcdef" ++ "zz" ++ "0123456789abcdef";
    var out_bad64: [34]u8 = undefined;
    try std.testing.expectEqual(@as(u64, 16), sa_hexdec_simd(bad64.ptr, bad64.len, &out_bad64));
    const odd = "ABC";
    var out_odd: [2]u8 = undefined;
    try std.testing.expectEqual(@as(u64, 1), sa_hexdec_simd(odd.ptr, odd.len, &out_odd));
    try std.testing.expectEqual(@as(u8, 0xAB), out_odd[0]);
    try std.testing.expectEqual(@as(u64, 0), sa_hexdec_simd(null, 10, &out_odd));
    try std.testing.expectEqual(@as(u64, 0), sa_hexdec_simd(odd.ptr, odd.len, null));
    try std.testing.expectEqual(@as(u64, 0), sa_hexdec_simd(odd.ptr, 0, &out_odd));
}

test "sa_b64dec_simd clean alphabet roundtrips" {
    const txt = "ABCDabcd01236789";
    var out: [12]u8 = undefined;
    const w = sa_b64dec_simd(txt.ptr, txt.len, &out);
    try std.testing.expectEqual(@as(u64, 12), w);
    const wn: usize = @intCast(w);
    try std.testing.expectEqualSlices(u8, &.{ 0, 16, 131, 105, 183, 29, 211, 93, 183, 235, 191, 61 }, out[0..wn]);
}

test "sa_b64dec_simd vector width then invalid stop" {
    const clean64 = "BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB";
    var out64: [48]u8 = undefined;
    try std.testing.expectEqual(@as(u64, 48), sa_b64dec_simd(clean64.ptr, clean64.len, &out64));
    try std.testing.expectEqual(@as(u8, 4), out64[0]);
    try std.testing.expectEqual(@as(u8, 16), out64[1]);
    try std.testing.expectEqual(@as(u8, 65), out64[2]);
    try std.testing.expectEqual(@as(u8, 65), out64[47]);
    const bad = "BBBB!!!!";
    var out_bad: [6]u8 = undefined;
    try std.testing.expectEqual(@as(u64, 3), sa_b64dec_simd(bad.ptr, bad.len, &out_bad));
    const bad40 = ("BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB") ++ "!!!!!!!!";
    var out_bad40: [30]u8 = undefined;
    try std.testing.expectEqual(@as(u64, 24), sa_b64dec_simd(bad40.ptr, bad40.len, &out_bad40));
    try std.testing.expectEqual(@as(u64, 0), sa_b64dec_simd(null, 8, &out_bad));
    try std.testing.expectEqual(@as(u64, 0), sa_b64dec_simd(bad.ptr, bad.len, null));
    try std.testing.expectEqual(@as(u64, 0), sa_b64dec_simd(bad.ptr, 0, &out_bad));
}

test "sa_b64dec_simd avx2 block invalid rewinds to scalar" {
    // 128B input, invalid byte inside the first 64B vector block: the AVX2
    // path must stop before it (scalar re-decode), exactly like the
    // portable path (peer_b64mid shape, wider).
    var mid: [128]u8 = @splat(@as(u8, 'B'));
    mid[5] = '!';
    var out_mid: [96]u8 = undefined;
    try std.testing.expectEqual(@as(u64, 3), sa_b64dec_simd(&mid, mid.len, &out_mid));
    try std.testing.expectEqual(@as(u8, 4), out_mid[0]);
    try std.testing.expectEqual(@as(u8, 16), out_mid[1]);
    try std.testing.expectEqual(@as(u8, 65), out_mid[2]);
    var clean128: [128]u8 = @splat(@as(u8, 'B'));
    var out128: [96]u8 = undefined;
    try std.testing.expectEqual(@as(u64, 96), sa_b64dec_simd(&clean128, clean128.len, &out128));
    try std.testing.expectEqual(@as(u8, 65), out128[95]);
}

test "base64: sa_deno_btoa -> sa_deno_atob roundtrip via fmt buffer handles" {
    const data = "hello, sa_std!";
    const enc = sa_deno_btoa(data.ptr, data.len);
    try std.testing.expect(enc != 0);
    defer _ = sa_fmt_buffer_free(enc);
    const enc_ptr = sa_fmt_buffer_data(enc) orelse return error.TestUnexpectedResult;
    const enc_len = sa_fmt_buffer_len(enc);
    try std.testing.expectEqualStrings("aGVsbG8sIHNhX3N0ZCE=", enc_ptr[0..@intCast(enc_len)]);

    const dec = sa_deno_atob(enc_ptr, enc_len);
    try std.testing.expect(dec != 0);
    defer _ = sa_fmt_buffer_free(dec);
    const dec_ptr = sa_fmt_buffer_data(dec) orelse return error.TestUnexpectedResult;
    const dec_len = sa_fmt_buffer_len(dec);
    try std.testing.expectEqualStrings(data, dec_ptr[0..@intCast(dec_len)]);

    // Invalid input is an explicit 0 handle, never a partial decode.
    try std.testing.expectEqual(@as(u64, 0), sa_deno_atob("!!!".ptr, 3));
}

test "sa_mfind_u8 hit/miss/edges match memmem contract" {
    const hay = "abcdefghabcdefghabcdefghabcdefghabcdefghabcdefghabcdefghabcdefgh";
    const hit0 = "abc";
    try std.testing.expectEqual(@as(u64, 0), sa_mfind_u8(hay.ptr, hay.len, hit0.ptr, hit0.len));
    const hitmid = "fgha";
    try std.testing.expectEqual(@as(u64, 5), sa_mfind_u8(hay.ptr, hay.len, hitmid.ptr, hitmid.len));
    const miss = "zzzzzzzz";
    try std.testing.expectEqual(@as(u64, hay.len), sa_mfind_u8(hay.ptr, hay.len, miss.ptr, miss.len));
    const empty = "";
    try std.testing.expectEqual(@as(u64, 0), sa_mfind_u8(hay.ptr, hay.len, empty.ptr, empty.len));
    const toolong = "abcdefghabcdefghabcdefghabcdefghabcdefghabcdefghabcdefghabcdefghabcdefgh";
    try std.testing.expectEqual(@as(u64, hay.len), sa_mfind_u8(hay.ptr, hay.len, toolong.ptr, toolong.len));
    var one: [1]u8 = .{0xFF};
    try std.testing.expectEqual(@as(u64, 8), sa_mfind_u8(null, 8, &one, 1));
    try std.testing.expectEqual(@as(u64, 8), sa_mfind_u8(hay.ptr, 8, null, 1));
}

test "unicode: normalize NFC/NFD/NFKC/NFKD vectors (JS oracle)" {
    const Case = struct { input: []const u8, form: i32, expected: []const u8 };
    const cases = [_]Case{
        .{ .input = "e\u{301}", .form = 0, .expected = "\u{e9}" },
        .{ .input = "e\u{301}", .form = 1, .expected = "e\u{301}" },
        .{ .input = "\u{e9}", .form = 1, .expected = "e\u{301}" },
        .{ .input = "\u{fb01}", .form = 3, .expected = "fi" },
        .{ .input = "\u{fb01}", .form = 2, .expected = "fi" },
        .{ .input = "\u{fb01}", .form = 0, .expected = "\u{fb01}" },
        .{ .input = "\u{b2}", .form = 3, .expected = "2" },
        .{ .input = "\u{b2}", .form = 0, .expected = "\u{b2}" },
        .{ .input = "\u{1100}\u{1161}", .form = 0, .expected = "\u{ac00}" },
        .{ .input = "\u{ac00}", .form = 1, .expected = "\u{1100}\u{1161}" },
        .{ .input = "\u{c5}", .form = 1, .expected = "A\u{30a}" },
        .{ .input = "\u{2126}", .form = 0, .expected = "\u{3a9}" },
        .{ .input = "", .form = 0, .expected = "" },
        .{ .input = "hello", .form = 3, .expected = "hello" },
        .{ .input = "caf\u{e9}", .form = 1, .expected = "cafe\u{301}" },
    };
    for (cases) |c| {
        const n = sa_unicode_normalize(c.input.ptr, c.input.len, c.form, null, 0);
        try std.testing.expectEqual(@as(i64, @intCast(c.expected.len)), n);
        var buf: [256]u8 = undefined;
        const m = sa_unicode_normalize(c.input.ptr, c.input.len, c.form, &buf, buf.len);
        try std.testing.expectEqual(@as(i64, @intCast(c.expected.len)), m);
        try std.testing.expectEqualStrings(c.expected, buf[0..@intCast(m)]);
    }
}

test "unicode: exact-fit buffers succeed (terminator warning is not failure)" {
    // Input exact fit: "hello" is 5 UTF-8 bytes -> 5 UTF-16 units in a
    // 5-unit buffer (ICU sets -124, content correct). Fill exact fit: a
    // 5-byte output buffer for a 5-byte result (same warning, must succeed).
    const input = "hello";
    const n = sa_unicode_normalize(input.ptr, input.len, 0, null, 0);
    try std.testing.expectEqual(@as(i64, 5), n);
    var buf: [5]u8 = undefined;
    const m = sa_unicode_normalize(input.ptr, input.len, 0, &buf, buf.len);
    try std.testing.expectEqual(@as(i64, 5), m);
    try std.testing.expectEqualStrings("hello", buf[0..@intCast(m)]);
}

test "unicode: small output buffer reports needed length without writing" {
    const input = "e\u{301}";
    var buf: [1]u8 = .{0xAA};
    const n = sa_unicode_normalize(input.ptr, input.len, 0, &buf, buf.len);
    try std.testing.expectEqual(@as(i64, 2), n);
    try std.testing.expectEqual(@as(u8, 0xAA), buf[0]);
}

test "regex: replace expands group references" {
    const pat: []const u8 = "([a-z]+)@([a-z]+)";
    const re = sa_regex_compile(pat.ptr, pat.len, SA_REGEX_EXTENDED);
    try std.testing.expect(re != 0);
    defer _ = sa_regex_free(re);

    const text: []const u8 = "user@host";
    const repl: []const u8 = "$2/$1";
    const buf = sa_regex_replace(re, text.ptr, text.len, repl.ptr, repl.len);
    try std.testing.expect(buf != 0);
    defer _ = sa_regex_buffer_free(buf);
    const out = sa_regex_buffer_data(buf).?[0..@intCast(sa_regex_buffer_len(buf))];
    try std.testing.expectEqualStrings("host/user", out);

    // $& whole match, $$ literal dollar, $` prefix, $' suffix, and an
    // out-of-range $9 that must stay literal.
    const text2: []const u8 = "x user@host y";
    const repl2: []const u8 = "[$&|$$|$`|$'|$9]";
    const buf2 = sa_regex_replace(re, text2.ptr, text2.len, repl2.ptr, repl2.len);
    try std.testing.expect(buf2 != 0);
    defer _ = sa_regex_buffer_free(buf2);
    const out2 = sa_regex_buffer_data(buf2).?[0..@intCast(sa_regex_buffer_len(buf2))];
    try std.testing.expectEqualStrings("x [user@host|$|x | y|$9] y", out2);
}

test "regex: replace is first-only and replace_all is global" {
    const pat: []const u8 = "([a-z])([0-9])";
    const re = sa_regex_compile(pat.ptr, pat.len, SA_REGEX_EXTENDED);
    try std.testing.expect(re != 0);
    defer _ = sa_regex_free(re);
    const text: []const u8 = "a1 b2";
    const repl: []const u8 = "$2$1";

    const buf = sa_regex_replace(re, text.ptr, text.len, repl.ptr, repl.len);
    try std.testing.expect(buf != 0);
    defer _ = sa_regex_buffer_free(buf);
    try std.testing.expectEqualStrings("1a b2", sa_regex_buffer_data(buf).?[0..@intCast(sa_regex_buffer_len(buf))]);

    const buf2 = sa_regex_replace_all(re, text.ptr, text.len, repl.ptr, repl.len);
    try std.testing.expect(buf2 != 0);
    defer _ = sa_regex_buffer_free(buf2);
    try std.testing.expectEqualStrings("1a 2b", sa_regex_buffer_data(buf2).?[0..@intCast(sa_regex_buffer_len(buf2))]);

    const plain: []const u8 = "zz";
    const buf3 = sa_regex_replace_all(re, plain.ptr, plain.len, repl.ptr, repl.len);
    try std.testing.expect(buf3 != 0);
    defer _ = sa_regex_buffer_free(buf3);
    try std.testing.expectEqualStrings("zz", sa_regex_buffer_data(buf3).?[0..@intCast(sa_regex_buffer_len(buf3))]);
}

test "regex: replace_all expands empty matches like the JS global loop" {
    const pat: []const u8 = "x*";
    const re = sa_regex_compile(pat.ptr, pat.len, SA_REGEX_EXTENDED);
    try std.testing.expect(re != 0);
    defer _ = sa_regex_free(re);
    const text: []const u8 = "ab";
    const repl: []const u8 = "-";
    const buf = sa_regex_replace_all(re, text.ptr, text.len, repl.ptr, repl.len);
    try std.testing.expect(buf != 0);
    defer _ = sa_regex_buffer_free(buf);
    try std.testing.expectEqualStrings("-a-b-", sa_regex_buffer_data(buf).?[0..@intCast(sa_regex_buffer_len(buf))]);
}

test "regex: match_all collects matches with capture groups" {
    const pat: []const u8 = "([a-z])([0-9])";
    const re = sa_regex_compile(pat.ptr, pat.len, SA_REGEX_EXTENDED);
    try std.testing.expect(re != 0);
    defer _ = sa_regex_free(re);
    const text: []const u8 = "a1 b2 c";
    const list = sa_regex_match_all(re, text.ptr, text.len);
    try std.testing.expect(list != 0);
    defer _ = sa_regex_match_list_free(list);
    try std.testing.expectEqual(@as(u64, 2), sa_regex_match_list_count(list));

    const m0 = sa_regex_match_list_at(list, 0);
    try std.testing.expect(m0 != 0);
    defer _ = sa_regex_match_free(m0);
    try std.testing.expectEqual(@as(u64, 0), sa_regex_group_start(m0, 0));
    try std.testing.expectEqualStrings("a1", sa_regex_group_ptr(m0, 0).?[0..@intCast(sa_regex_group_len(m0, 0))]);
    try std.testing.expectEqualStrings("a", sa_regex_group_ptr(m0, 1).?[0..@intCast(sa_regex_group_len(m0, 1))]);
    try std.testing.expectEqualStrings("1", sa_regex_group_ptr(m0, 2).?[0..@intCast(sa_regex_group_len(m0, 2))]);

    const m1 = sa_regex_match_list_at(list, 1);
    try std.testing.expect(m1 != 0);
    defer _ = sa_regex_match_free(m1);
    try std.testing.expectEqual(@as(u64, 3), sa_regex_group_start(m1, 0));
    try std.testing.expectEqualStrings("b2", sa_regex_group_ptr(m1, 0).?[0..@intCast(sa_regex_group_len(m1, 0))]);

    try std.testing.expectEqual(@as(u64, 0), sa_regex_match_list_at(list, 2));
}

test "regex: match_all reports the trailing empty match" {
    const pat: []const u8 = "a*";
    const re = sa_regex_compile(pat.ptr, pat.len, SA_REGEX_EXTENDED);
    try std.testing.expect(re != 0);
    defer _ = sa_regex_free(re);
    const text: []const u8 = "b";
    const list = sa_regex_match_all(re, text.ptr, text.len);
    try std.testing.expect(list != 0);
    defer _ = sa_regex_match_list_free(list);
    try std.testing.expectEqual(@as(u64, 2), sa_regex_match_list_count(list));
    const m0 = sa_regex_match_list_at(list, 0);
    try std.testing.expect(m0 != 0);
    defer _ = sa_regex_match_free(m0);
    try std.testing.expectEqual(@as(u64, 0), sa_regex_group_start(m0, 0));
    try std.testing.expectEqual(@as(u64, 0), sa_regex_group_len(m0, 0));
    const m1 = sa_regex_match_list_at(list, 1);
    try std.testing.expect(m1 != 0);
    defer _ = sa_regex_match_free(m1);
    try std.testing.expectEqual(@as(u64, 1), sa_regex_group_start(m1, 0));
    try std.testing.expectEqual(@as(u64, 0), sa_regex_group_len(m1, 0));
}

test "regex: split leading trailing and consecutive separators" {
    const pat: []const u8 = ",";
    const re = sa_regex_compile(pat.ptr, pat.len, SA_REGEX_EXTENDED);
    try std.testing.expect(re != 0);
    defer _ = sa_regex_free(re);

    const text: []const u8 = "a,,b,";
    const list = sa_regex_split(re, text.ptr, text.len, 0);
    try std.testing.expect(list != 0);
    defer _ = sa_regex_split_free(list);
    try std.testing.expectEqual(@as(u64, 4), sa_regex_split_count(list));
    try std.testing.expectEqualStrings("a", sa_regex_split_ptr(list, 0).?[0..@intCast(sa_regex_split_len(list, 0))]);
    try std.testing.expectEqualStrings("", sa_regex_split_ptr(list, 1).?[0..@intCast(sa_regex_split_len(list, 1))]);
    try std.testing.expectEqualStrings("b", sa_regex_split_ptr(list, 2).?[0..@intCast(sa_regex_split_len(list, 2))]);
    try std.testing.expectEqualStrings("", sa_regex_split_ptr(list, 3).?[0..@intCast(sa_regex_split_len(list, 3))]);

    const text2: []const u8 = ",a";
    const list2 = sa_regex_split(re, text2.ptr, text2.len, 0);
    try std.testing.expect(list2 != 0);
    defer _ = sa_regex_split_free(list2);
    try std.testing.expectEqual(@as(u64, 2), sa_regex_split_count(list2));
    try std.testing.expectEqualStrings("", sa_regex_split_ptr(list2, 0).?[0..@intCast(sa_regex_split_len(list2, 0))]);
    try std.testing.expectEqualStrings("a", sa_regex_split_ptr(list2, 1).?[0..@intCast(sa_regex_split_len(list2, 1))]);

    const text3: []const u8 = "abc";
    const list3 = sa_regex_split(re, text3.ptr, text3.len, 0);
    try std.testing.expect(list3 != 0);
    defer _ = sa_regex_split_free(list3);
    try std.testing.expectEqual(@as(u64, 1), sa_regex_split_count(list3));
    try std.testing.expectEqualStrings("abc", sa_regex_split_ptr(list3, 0).?[0..@intCast(sa_regex_split_len(list3, 0))]);

    const empty: []const u8 = "";
    const list4 = sa_regex_split(re, empty.ptr, empty.len, 0);
    try std.testing.expect(list4 != 0);
    defer _ = sa_regex_split_free(list4);
    try std.testing.expectEqual(@as(u64, 1), sa_regex_split_count(list4));
    try std.testing.expectEqual(@as(u64, 0), sa_regex_split_len(list4, 0));
}

test "regex: split inserts capture groups and honors limit" {
    const pat: []const u8 = "([0-9])";
    const re = sa_regex_compile(pat.ptr, pat.len, SA_REGEX_EXTENDED);
    try std.testing.expect(re != 0);
    defer _ = sa_regex_free(re);
    const text: []const u8 = "a1b2c";

    const list = sa_regex_split(re, text.ptr, text.len, 0);
    try std.testing.expect(list != 0);
    defer _ = sa_regex_split_free(list);
    try std.testing.expectEqual(@as(u64, 5), sa_regex_split_count(list));
    try std.testing.expectEqualStrings("a", sa_regex_split_ptr(list, 0).?[0..@intCast(sa_regex_split_len(list, 0))]);
    try std.testing.expectEqualStrings("1", sa_regex_split_ptr(list, 1).?[0..@intCast(sa_regex_split_len(list, 1))]);
    try std.testing.expectEqualStrings("b", sa_regex_split_ptr(list, 2).?[0..@intCast(sa_regex_split_len(list, 2))]);
    try std.testing.expectEqualStrings("2", sa_regex_split_ptr(list, 3).?[0..@intCast(sa_regex_split_len(list, 3))]);
    try std.testing.expectEqualStrings("c", sa_regex_split_ptr(list, 4).?[0..@intCast(sa_regex_split_len(list, 4))]);

    const list2 = sa_regex_split(re, text.ptr, text.len, 3);
    try std.testing.expect(list2 != 0);
    defer _ = sa_regex_split_free(list2);
    try std.testing.expectEqual(@as(u64, 3), sa_regex_split_count(list2));
    try std.testing.expectEqualStrings("b", sa_regex_split_ptr(list2, 2).?[0..@intCast(sa_regex_split_len(list2, 2))]);

    // Empty input whose pattern matches at 0 splits to zero pieces (JS).
    const pat2: []const u8 = "a*";
    const re2 = sa_regex_compile(pat2.ptr, pat2.len, SA_REGEX_EXTENDED);
    try std.testing.expect(re2 != 0);
    defer _ = sa_regex_free(re2);
    const empty: []const u8 = "";
    const list3 = sa_regex_split(re2, empty.ptr, empty.len, 0);
    try std.testing.expect(list3 != 0);
    defer _ = sa_regex_split_free(list3);
    try std.testing.expectEqual(@as(u64, 0), sa_regex_split_count(list3));
}

test "ja3 hash matches reference md5 vector" {
    // Reference JA3 string and its canonical md5 (ja3er / Salesforce reference).
    const ja3 = "769,47-53-5-10-49161-49162-49171-49172-50-56-19-4,0-10-11,23-24-25,0";
    var out: [64]u8 = undefined;
    var out_len: u64 = 0;
    try std.testing.expectEqual(SA_STD_OK, sa_std_net_ja3_hash(ja3.ptr, ja3.len, &out, out.len, &out_len));
    try std.testing.expectEqual(@as(u64, 32), out_len);
    try std.testing.expectEqualStrings("ada70206e40642a3e4461f35503241d5", out[0..32]);
}

test "sha256 hex and ja4 truncation match" {
    // sha256("") = e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855
    var out: [64]u8 = undefined;
    var out_len: u64 = 0;
    try std.testing.expectEqual(SA_STD_OK, sa_std_net_sha256_hex("", 0, &out, out.len, &out_len));
    try std.testing.expectEqual(@as(u64, 64), out_len);
    try std.testing.expectEqualStrings("e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855", out[0..64]);

    // JA4 12-char truncation is the first 12 hex chars of the same digest.
    var out12: [12]u8 = undefined;
    var len12: u64 = 0;
    try std.testing.expectEqual(SA_STD_OK, sa_std_net_ja4_hash12("", 0, &out12, out12.len, &len12));
    try std.testing.expectEqual(@as(u64, 12), len12);
    try std.testing.expectEqualStrings("e3b0c4429 8fc"[0..0] ++ "e3b0c44298fc", out12[0..12]);
}

test "ja3/ja4 reject too-small output buffers" {
    var small: [8]u8 = undefined;
    var n: u64 = 0;
    try std.testing.expectEqual(SA_STD_ERR_TRUNCATED, sa_std_net_ja3_hash("x", 1, &small, small.len, &n));
    try std.testing.expectEqual(SA_STD_ERR_TRUNCATED, sa_std_net_sha256_hex("x", 1, &small, small.len, &n));
    try std.testing.expectEqual(SA_STD_ERR_TRUNCATED, sa_std_net_ja4_hash12("x", 1, &small, small.len, &n));
}

test "hmac sha256 matches RFC 4231 vectors" {
    var out: [64]u8 = undefined;
    var out_len: u64 = 0;

    // Test Case 1: key = 0x0b x 20, data = "Hi There".
    const key1: [20]u8 = @splat(0x0b);
    const data1 = "Hi There";
    try std.testing.expectEqual(SA_STD_OK, sa_hmac_sha256_hex(&key1, key1.len, data1.ptr, data1.len, &out, out.len, &out_len));
    try std.testing.expectEqual(@as(u64, 64), out_len);
    try std.testing.expectEqualStrings("b0344c61d8db38535ca8afceaf0bf12b881dc200c9833da726e9376c2e32cff7", out[0..64]);

    // Test Case 2: key = "Jefe", data = "what do ya want for nothing?".
    const key2 = "Jefe";
    const data2 = "what do ya want for nothing?";
    try std.testing.expectEqual(SA_STD_OK, sa_hmac_sha256_hex(key2.ptr, key2.len, data2.ptr, data2.len, &out, out.len, &out_len));
    try std.testing.expectEqualStrings("5bdcc146bf60754e6a042426089575c75a003f089d2739839dec58b964ec3843", out[0..64]);

    // Test Case 6: key = 0xaa x 131 (longer than the 64-byte block size,
    // so the key itself is hashed first).
    const key6: [131]u8 = @splat(0xaa);
    const data6 = "Test Using Larger Than Block-Size Key - Hash Key First";
    try std.testing.expectEqual(SA_STD_OK, sa_hmac_sha256_hex(&key6, key6.len, data6.ptr, data6.len, &out, out.len, &out_len));
    try std.testing.expectEqualStrings("60e431591ee0b67f0d8a26aacbf5b77f8e0bc6213728c5140546040f0ee37f54", out[0..64]);
}

test "hmac sha1 matches RFC 2202 vectors" {
    var out: [40]u8 = undefined;
    var out_len: u64 = 0;

    // Case 1: key = 0x0b x 20, data = "Hi There".
    const key1: [20]u8 = @splat(0x0b);
    const data1 = "Hi There";
    try std.testing.expectEqual(SA_STD_OK, sa_hmac_sha1_hex(&key1, key1.len, data1.ptr, data1.len, &out, out.len, &out_len));
    try std.testing.expectEqual(@as(u64, 40), out_len);
    try std.testing.expectEqualStrings("b617318655057264e28bc0b6fb378c8ef146be00", out[0..40]);

    // Case 2: key = "Jefe", data = "what do ya want for nothing?".
    const key2 = "Jefe";
    const data2 = "what do ya want for nothing?";
    try std.testing.expectEqual(SA_STD_OK, sa_hmac_sha1_hex(key2.ptr, key2.len, data2.ptr, data2.len, &out, out.len, &out_len));
    try std.testing.expectEqualStrings("effcdf6ae5eb2fa2d27416d5f184df9c259a7c79", out[0..40]);

    // Case 6: key = 0xaa x 80 (longer than the 64-byte block size).
    const key6: [80]u8 = @splat(0xaa);
    const data6 = "Test Using Larger Than Block-Size Key - Hash Key First";
    try std.testing.expectEqual(SA_STD_OK, sa_hmac_sha1_hex(&key6, key6.len, data6.ptr, data6.len, &out, out.len, &out_len));
    try std.testing.expectEqualStrings("aa4ae5e15272d00e95705637ce8a3b55ed402112", out[0..40]);
}

test "hmac hex rejects too-small output buffers" {
    var small: [16]u8 = undefined;
    var n: u64 = 0;
    try std.testing.expectEqual(SA_STD_ERR_TRUNCATED, sa_hmac_sha256_hex("k", 1, "x", 1, &small, small.len, &n));
    try std.testing.expectEqual(SA_STD_ERR_TRUNCATED, sa_hmac_sha1_hex("k", 1, "x", 1, &small, small.len, &n));
}

test "crypto random bytes fills the caller buffer" {
    var a: [32]u8 = undefined;
    var b: [32]u8 = undefined;
    try std.testing.expectEqual(SA_STD_OK, sa_crypto_random_bytes(&a, a.len));
    try std.testing.expectEqual(SA_STD_OK, sa_crypto_random_bytes(&b, b.len));
    // Two independent 32-byte draws colliding has probability 2^-256.
    try std.testing.expect(!std.mem.eql(u8, &a, &b));
    try std.testing.expectEqual(SA_STD_OK, sa_crypto_random_bytes(null, 0));
    try std.testing.expectEqual(SA_STD_ERR_INVALID_ARGUMENT, sa_crypto_random_bytes(null, 4));
}

test "deno random uuid returns well-formed v4 text" {
    const h1 = sa_deno_random_uuid();
    try std.testing.expect(h1 != 0);
    defer _ = sa_fmt_buffer_free(h1);
    const data = sa_fmt_buffer_data(h1) orelse return error.TestUnexpectedResult;
    try std.testing.expectEqual(@as(u64, 36), sa_fmt_buffer_len(h1));
    const text = data[0..36];
    // RFC 4122 layout: 8-4-4-4-12 lowercase hex, version 4, variant 10xx.
    try std.testing.expect(text[8] == '-' and text[13] == '-' and text[18] == '-' and text[23] == '-');
    try std.testing.expect(text[14] == '4');
    try std.testing.expect(text[19] == '8' or text[19] == '9' or text[19] == 'a' or text[19] == 'b');
    for (text, 0..) |c, i| {
        if (i == 8 or i == 13 or i == 18 or i == 23) continue;
        try std.testing.expect((c >= '0' and c <= '9') or (c >= 'a' and c <= 'f'));
    }
    const h2 = sa_deno_random_uuid();
    try std.testing.expect(h2 != 0);
    defer _ = sa_fmt_buffer_free(h2);
    const data2 = sa_fmt_buffer_data(h2) orelse return error.TestUnexpectedResult;
    try std.testing.expect(!std.mem.eql(u8, text, data2[0..36]));
}
