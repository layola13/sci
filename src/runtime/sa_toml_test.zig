const std = @import("std");
const ERR_HANDLE = @import("sa_toml.zig").ERR_HANDLE;
const ERR_INVALID = @import("sa_toml.zig").ERR_INVALID;
const ERR_NOT_FOUND = @import("sa_toml.zig").ERR_NOT_FOUND;
const KIND_DATETIME = @import("sa_toml.zig").KIND_DATETIME;
const KIND_FLOAT = @import("sa_toml.zig").KIND_FLOAT;
const OK = @import("sa_toml.zig").OK;
const sa_toml_array_get_string = @import("sa_toml.zig").sa_toml_array_get_string;
const sa_toml_array_len = @import("sa_toml.zig").sa_toml_array_len;
const sa_toml_array_push_bool = @import("sa_toml.zig").sa_toml_array_push_bool;
const sa_toml_array_push_datetime = @import("sa_toml.zig").sa_toml_array_push_datetime;
const sa_toml_array_push_f64 = @import("sa_toml.zig").sa_toml_array_push_f64;
const sa_toml_array_push_i64 = @import("sa_toml.zig").sa_toml_array_push_i64;
const sa_toml_array_push_string = @import("sa_toml.zig").sa_toml_array_push_string;
const sa_toml_array_push_table = @import("sa_toml.zig").sa_toml_array_push_table;
const sa_toml_free = @import("sa_toml.zig").sa_toml_free;
const sa_toml_get_bool = @import("sa_toml.zig").sa_toml_get_bool;
const sa_toml_get_datetime = @import("sa_toml.zig").sa_toml_get_datetime;
const sa_toml_get_f64 = @import("sa_toml.zig").sa_toml_get_f64;
const sa_toml_get_i64 = @import("sa_toml.zig").sa_toml_get_i64;
const sa_toml_get_string = @import("sa_toml.zig").sa_toml_get_string;
const sa_toml_kind = @import("sa_toml.zig").sa_toml_kind;
const sa_toml_last_error = @import("sa_toml.zig").sa_toml_last_error;
const sa_toml_new = @import("sa_toml.zig").sa_toml_new;
const sa_toml_parse = @import("sa_toml.zig").sa_toml_parse;
const sa_toml_remove = @import("sa_toml.zig").sa_toml_remove;
const sa_toml_set_bool = @import("sa_toml.zig").sa_toml_set_bool;
const sa_toml_set_datetime = @import("sa_toml.zig").sa_toml_set_datetime;
const sa_toml_set_f64 = @import("sa_toml.zig").sa_toml_set_f64;
const sa_toml_set_i64 = @import("sa_toml.zig").sa_toml_set_i64;
const sa_toml_set_string = @import("sa_toml.zig").sa_toml_set_string;
const sa_toml_set_table = @import("sa_toml.zig").sa_toml_set_table;
const sa_toml_stringify = @import("sa_toml.zig").sa_toml_stringify;
const sa_toml_table_key_at = @import("sa_toml.zig").sa_toml_table_key_at;
const sa_toml_table_len = @import("sa_toml.zig").sa_toml_table_len;

test "toml: codex-style config values by dotted path" {
    const text =
        \\model = "gpt-cxu"
        \\temperature = 0.2
        \\max_turns = 42
        \\debug = true
        \\released = 2026-10-25T07:32:00Z
        \\
        \\[model_providers.cxu]
        \\base_url = "https://example.invalid/v1"
        \\wire_api = "responses"
        \\
        \\[mcp_servers.jex]
        \\command = "node"
        \\args = ["server.js", "--port", "8080"]
        \\env = { API_KEY = "redacted", RETRIES = 3 }
        \\
        \\[[servers]]
        \\host = "a.example"
        \\port = 8001
        \\
        \\[[servers]]
        \\host = "b.example"
        \\port = 8002
    ;
    const doc = sa_toml_parse(text.ptr, text.len);
    try std.testing.expect(doc != 0);
    defer _ = sa_toml_free(doc);

    var sp: ?[*]const u8 = null;
    var sl: u64 = 0;
    try std.testing.expectEqual(OK, sa_toml_get_string(doc, "model".ptr, 5, &sp, &sl));
    try std.testing.expectEqualStrings("gpt-cxu", sp.?[0..@intCast(sl)]);
    try std.testing.expectEqual(OK, sa_toml_get_string(doc, "model_providers.cxu.base_url".ptr, 28, &sp, &sl));
    try std.testing.expectEqualStrings("https://example.invalid/v1", sp.?[0..@intCast(sl)]);

    var iv: i64 = 0;
    try std.testing.expectEqual(OK, sa_toml_get_i64(doc, "max_turns".ptr, 9, &iv));
    try std.testing.expectEqual(@as(i64, 42), iv);
    try std.testing.expectEqual(OK, sa_toml_get_i64(doc, "mcp_servers.jex.env.RETRIES".ptr, 27, &iv));
    try std.testing.expectEqual(@as(i64, 3), iv);
    try std.testing.expectEqual(OK, sa_toml_get_i64(doc, "servers.1.port".ptr, 14, &iv));
    try std.testing.expectEqual(@as(i64, 8002), iv);

    var fv: f64 = 0;
    try std.testing.expectEqual(OK, sa_toml_get_f64(doc, "temperature".ptr, 11, &fv));
    try std.testing.expectApproxEqAbs(@as(f64, 0.2), fv, 0.000001);

    var bv: u32 = 0;
    try std.testing.expectEqual(OK, sa_toml_get_bool(doc, "debug".ptr, 5, &bv));
    try std.testing.expectEqual(@as(u32, 1), bv);

    var kind: u32 = 0;
    try std.testing.expectEqual(OK, sa_toml_kind(doc, "released".ptr, 8, &kind));
    try std.testing.expectEqual(KIND_DATETIME, kind);
    try std.testing.expectEqual(OK, sa_toml_get_datetime(doc, "released".ptr, 8, &sp, &sl));
    try std.testing.expectEqualStrings("2026-10-25T07:32:00Z", sp.?[0..@intCast(sl)]);

    var n: u64 = 0;
    try std.testing.expectEqual(OK, sa_toml_array_len(doc, "mcp_servers.jex.args".ptr, 20, &n));
    try std.testing.expectEqual(@as(u64, 3), n);
    try std.testing.expectEqual(OK, sa_toml_array_get_string(doc, "mcp_servers.jex.args".ptr, 20, 1, &sp, &sl));
    try std.testing.expectEqualStrings("--port", sp.?[0..@intCast(sl)]);
    try std.testing.expectEqual(OK, sa_toml_array_len(doc, "servers".ptr, 7, &n));
    try std.testing.expectEqual(@as(u64, 2), n);
    try std.testing.expectEqual(OK, sa_toml_table_len(doc, "mcp_servers.jex".ptr, 15, &n));
    try std.testing.expectEqual(@as(u64, 3), n);
    try std.testing.expectEqual(ERR_NOT_FOUND, sa_toml_get_string(doc, "missing.key".ptr, 11, &sp, &sl));
    try std.testing.expectEqual(ERR_INVALID, sa_toml_get_string(doc, "max_turns".ptr, 9, &sp, &sl));
}

test "toml: duplicate keys and redefined tables are hard errors" {
    const dup_key = "a = 1\na = 2\n";
    try std.testing.expectEqual(@as(u64, 0), sa_toml_parse(dup_key.ptr, dup_key.len));
    var sp: ?[*]const u8 = null;
    var sl: u64 = 0;
    try std.testing.expectEqual(OK, sa_toml_last_error(&sp, &sl));
    try std.testing.expect(std.mem.indexOf(u8, sp.?[0..@intCast(sl)], "duplicate") != null);

    const dup_table = "[t]\na = 1\n[t]\nb = 2\n";
    try std.testing.expectEqual(@as(u64, 0), sa_toml_parse(dup_table.ptr, dup_table.len));

    const dotted_then_header = "a.b = 1\n[a]\n";
    try std.testing.expectEqual(@as(u64, 0), sa_toml_parse(dotted_then_header.ptr, dotted_then_header.len));

    const bad_syntax = "a = \n";
    try std.testing.expectEqual(@as(u64, 0), sa_toml_parse(bad_syntax.ptr, bad_syntax.len));
}

test "toml: string forms and escapes" {
    const text =
        \\lit = 'C:\path\file'
        \\esc = "a\tb\u00e9"
        \\hex = 0xDEADBEEF
        \\under = 1_000_000
    ;
    const doc = sa_toml_parse(text.ptr, text.len);
    try std.testing.expect(doc != 0);
    defer _ = sa_toml_free(doc);
    var sp: ?[*]const u8 = null;
    var sl: u64 = 0;
    try std.testing.expectEqual(OK, sa_toml_get_string(doc, "lit".ptr, 3, &sp, &sl));
    try std.testing.expectEqualStrings("C:\\path\\file", sp.?[0..@intCast(sl)]);
    var iv: i64 = 0;
    try std.testing.expectEqual(OK, sa_toml_get_i64(doc, "hex".ptr, 3, &iv));
    try std.testing.expectEqual(@as(i64, 0xDEADBEEF), iv);
    try std.testing.expectEqual(OK, sa_toml_get_i64(doc, "under".ptr, 5, &iv));
    try std.testing.expectEqual(@as(i64, 1000000), iv);
}

test "toml: table key enumeration" {
    const text =
        \\name = "cxu"
        \\version = 3
        \\
        \\[owner]
        \\name = "layola13"
        \\id = 7
        \\
        \\[empty]
    ;
    const doc = sa_toml_parse(text.ptr, text.len);
    try std.testing.expect(doc != 0);
    defer _ = sa_toml_free(doc);

    var n: u64 = 0;
    try std.testing.expectEqual(OK, sa_toml_table_len(doc, "".ptr, 0, &n));
    try std.testing.expectEqual(@as(u64, 4), n);

    var kp: ?[*]const u8 = null;
    var kl: u64 = 0;
    try std.testing.expectEqual(OK, sa_toml_table_key_at(doc, "".ptr, 0, 0, &kp, &kl));
    try std.testing.expectEqualStrings("name", kp.?[0..@intCast(kl)]);
    try std.testing.expectEqual(OK, sa_toml_table_key_at(doc, "".ptr, 0, 3, &kp, &kl));
    try std.testing.expectEqualStrings("empty", kp.?[0..@intCast(kl)]);
    try std.testing.expectEqual(ERR_NOT_FOUND, sa_toml_table_key_at(doc, "".ptr, 0, 4, &kp, &kl));

    const owner = "owner";
    try std.testing.expectEqual(OK, sa_toml_table_len(doc, owner.ptr, owner.len, &n));
    try std.testing.expectEqual(@as(u64, 2), n);
    try std.testing.expectEqual(OK, sa_toml_table_key_at(doc, owner.ptr, owner.len, 1, &kp, &kl));
    try std.testing.expectEqualStrings("id", kp.?[0..@intCast(kl)]);

    const empty = "empty";
    try std.testing.expectEqual(OK, sa_toml_table_len(doc, empty.ptr, empty.len, &n));
    try std.testing.expectEqual(@as(u64, 0), n);
    try std.testing.expectEqual(ERR_NOT_FOUND, sa_toml_table_key_at(doc, empty.ptr, empty.len, 0, &kp, &kl));

    const not_table = "name";
    try std.testing.expectEqual(ERR_INVALID, sa_toml_table_key_at(doc, not_table.ptr, not_table.len, 0, &kp, &kl));
    const missing = "nope";
    try std.testing.expectEqual(ERR_NOT_FOUND, sa_toml_table_key_at(doc, missing.ptr, missing.len, 0, &kp, &kl));
    try std.testing.expectEqual(ERR_HANDLE, sa_toml_table_key_at(999999, "".ptr, 0, 0, &kp, &kl));
}

test "toml: build a document and stringify round-trip" {
    const doc = sa_toml_new();
    try std.testing.expect(doc != 0);
    defer _ = sa_toml_free(doc);

    const title = "title";
    const cfg = "cfg.toml";
    try std.testing.expectEqual(OK, sa_toml_set_string(doc, title.ptr, title.len, cfg.ptr, cfg.len));
    const debug = "debug";
    try std.testing.expectEqual(OK, sa_toml_set_bool(doc, debug.ptr, debug.len, 1));
    const ratio = "ratio";
    try std.testing.expectEqual(OK, sa_toml_set_f64(doc, ratio.ptr, ratio.len, 1.0));
    const stamp = "stamp";
    const when = "2026-10-26T01:02:03Z";
    try std.testing.expectEqual(OK, sa_toml_set_datetime(doc, stamp.ptr, stamp.len, when.ptr, when.len));

    const host = "server.host";
    const hostv = "localhost";
    try std.testing.expectEqual(OK, sa_toml_set_string(doc, host.ptr, host.len, hostv.ptr, hostv.len));
    const port = "server.port";
    try std.testing.expectEqual(OK, sa_toml_set_i64(doc, port.ptr, port.len, 8080));
    const opts = "server.opts";
    try std.testing.expectEqual(OK, sa_toml_set_table(doc, opts.ptr, opts.len));
    // Ensuring a table that already exists is a no-op success.
    try std.testing.expectEqual(OK, sa_toml_set_table(doc, opts.ptr, opts.len));
    // ...but a scalar in the way is an error, never silently destroyed.
    try std.testing.expectEqual(ERR_INVALID, sa_toml_set_table(doc, title.ptr, title.len));

    const tags = "tags";
    const t1 = "alpha";
    const t2 = "beta";
    try std.testing.expectEqual(OK, sa_toml_array_push_string(doc, tags.ptr, tags.len, t1.ptr, t1.len));
    try std.testing.expectEqual(OK, sa_toml_array_push_string(doc, tags.ptr, tags.len, t2.ptr, t2.len));
    const nums = "nums";
    try std.testing.expectEqual(OK, sa_toml_array_push_i64(doc, nums.ptr, nums.len, 10));
    try std.testing.expectEqual(OK, sa_toml_array_push_f64(doc, nums.ptr, nums.len, 2.5));
    try std.testing.expectEqual(OK, sa_toml_array_push_bool(doc, nums.ptr, nums.len, 0));
    const stamps = "stamps";
    try std.testing.expectEqual(OK, sa_toml_array_push_datetime(doc, stamps.ptr, stamps.len, when.ptr, when.len));
    // A scalar push into an array of tables is rejected.
    const servers = "servers";
    try std.testing.expectEqual(OK, sa_toml_array_push_table(doc, servers.ptr, servers.len));
    try std.testing.expectEqual(ERR_INVALID, sa_toml_array_push_i64(doc, servers.ptr, servers.len, 1));
    try std.testing.expectEqual(OK, sa_toml_array_push_table(doc, servers.ptr, servers.len));
    const s0 = "servers.0.host";
    const h0 = "a.example";
    try std.testing.expectEqual(OK, sa_toml_set_string(doc, s0.ptr, s0.len, h0.ptr, h0.len));
    const s1 = "servers.1.host";
    const h1 = "b.example";
    try std.testing.expectEqual(OK, sa_toml_set_string(doc, s1.ptr, s1.len, h1.ptr, h1.len));
    const s1p = "servers.1.port";
    try std.testing.expectEqual(OK, sa_toml_set_i64(doc, s1p.ptr, s1p.len, 9001));
    // Array elements are addressed by explicit index only: the bare
    // form resolves neither on the read side nor on the write side.
    const slast = "servers.host";
    var chk: ?[*]const u8 = null;
    var chkl: u64 = 0;
    try std.testing.expectEqual(ERR_NOT_FOUND, sa_toml_get_string(doc, slast.ptr, slast.len, &chk, &chkl));
    try std.testing.expectEqual(ERR_INVALID, sa_toml_set_string(doc, slast.ptr, slast.len, h1.ptr, h1.len));

    var sp: ?[*]const u8 = null;
    var sl: u64 = 0;
    try std.testing.expectEqual(OK, sa_toml_stringify(doc, &sp, &sl));
    const text = sp.?[0..@intCast(sl)];
    try std.testing.expect(std.mem.indexOf(u8, text, "[server]") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "[[servers]]") != null);

    const doc2 = sa_toml_parse(text.ptr, text.len);
    try std.testing.expect(doc2 != 0);
    defer _ = sa_toml_free(doc2);
    var iv: i64 = 0;
    try std.testing.expectEqual(OK, sa_toml_get_i64(doc2, port.ptr, port.len, &iv));
    try std.testing.expectEqual(@as(i64, 8080), iv);
    var fv: f64 = 0;
    try std.testing.expectEqual(OK, sa_toml_get_f64(doc2, ratio.ptr, ratio.len, &fv));
    try std.testing.expectEqual(@as(f64, 1.0), fv);
    var kind: u32 = 0;
    try std.testing.expectEqual(OK, sa_toml_kind(doc2, ratio.ptr, ratio.len, &kind));
    try std.testing.expectEqual(KIND_FLOAT, kind);
    try std.testing.expectEqual(OK, sa_toml_kind(doc2, stamp.ptr, stamp.len, &kind));
    try std.testing.expectEqual(KIND_DATETIME, kind);
    var n: u64 = 0;
    try std.testing.expectEqual(OK, sa_toml_array_len(doc2, servers.ptr, servers.len, &n));
    try std.testing.expectEqual(@as(u64, 2), n);
    try std.testing.expectEqual(OK, sa_toml_get_string(doc2, s1.ptr, s1.len, &sp, &sl));
    try std.testing.expectEqualStrings("b.example", sp.?[0..@intCast(sl)]);
    try std.testing.expectEqual(OK, sa_toml_table_len(doc2, opts.ptr, opts.len, &n));
    try std.testing.expectEqual(@as(u64, 0), n);
    try std.testing.expectEqual(OK, sa_toml_array_get_string(doc2, tags.ptr, tags.len, 1, &sp, &sl));
    try std.testing.expectEqualStrings("beta", sp.?[0..@intCast(sl)]);
    try std.testing.expectEqual(OK, sa_toml_array_len(doc2, stamps.ptr, stamps.len, &n));
    try std.testing.expectEqual(@as(u64, 1), n);
}

test "toml: mutate a parsed document" {
    const text =
        \\model = "old"
        \\keep = 1
        \\
        \\[mcp_servers.jex]
        \\command = "node"
        \\args = ["a", "b", "c"]
        \\env = { API_KEY = "k1", RETRIES = 3 }
    ;
    const doc = sa_toml_parse(text.ptr, text.len);
    try std.testing.expect(doc != 0);
    defer _ = sa_toml_free(doc);

    const model = "model";
    const newv = "new";
    try std.testing.expectEqual(OK, sa_toml_set_string(doc, model.ptr, model.len, newv.ptr, newv.len));
    var sp: ?[*]const u8 = null;
    var sl: u64 = 0;
    try std.testing.expectEqual(OK, sa_toml_get_string(doc, model.ptr, model.len, &sp, &sl));
    try std.testing.expectEqualStrings("new", sp.?[0..@intCast(sl)]);

    // Descend into an inline table and replace a value inside it.
    const retries = "mcp_servers.jex.env.RETRIES";
    try std.testing.expectEqual(OK, sa_toml_set_i64(doc, retries.ptr, retries.len, 9));
    var iv: i64 = 0;
    try std.testing.expectEqual(OK, sa_toml_get_i64(doc, retries.ptr, retries.len, &iv));
    try std.testing.expectEqual(@as(i64, 9), iv);

    // A set whose parent path crosses a scalar is an invalid argument
    // and leaves the document untouched.
    const through = "keep.x";
    try std.testing.expectEqual(ERR_INVALID, sa_toml_set_i64(doc, through.ptr, through.len, 1));
    try std.testing.expectEqual(OK, sa_toml_get_i64(doc, "keep".ptr, 4, &iv));
    try std.testing.expectEqual(@as(i64, 1), iv);

    // Remove a key, then an array element (numeric final segment).
    const keep = "keep";
    try std.testing.expectEqual(OK, sa_toml_remove(doc, keep.ptr, keep.len));
    var kind: u32 = 0;
    try std.testing.expectEqual(ERR_NOT_FOUND, sa_toml_kind(doc, keep.ptr, keep.len, &kind));
    try std.testing.expectEqual(ERR_NOT_FOUND, sa_toml_remove(doc, keep.ptr, keep.len));

    const args0 = "mcp_servers.jex.args.0";
    try std.testing.expectEqual(OK, sa_toml_remove(doc, args0.ptr, args0.len));
    const args = "mcp_servers.jex.args";
    var n: u64 = 0;
    try std.testing.expectEqual(OK, sa_toml_array_len(doc, args.ptr, args.len, &n));
    try std.testing.expectEqual(@as(u64, 2), n);
    try std.testing.expectEqual(OK, sa_toml_array_get_string(doc, args.ptr, args.len, 0, &sp, &sl));
    try std.testing.expectEqualStrings("b", sp.?[0..@intCast(sl)]);

    // Stringify and reparse: the mutations survive the round trip.
    try std.testing.expectEqual(OK, sa_toml_stringify(doc, &sp, &sl));
    const out = sp.?[0..@intCast(sl)];
    const doc2 = sa_toml_parse(out.ptr, out.len);
    try std.testing.expect(doc2 != 0);
    defer _ = sa_toml_free(doc2);
    try std.testing.expectEqual(OK, sa_toml_get_i64(doc2, retries.ptr, retries.len, &iv));
    try std.testing.expectEqual(@as(i64, 9), iv);
    try std.testing.expectEqual(ERR_NOT_FOUND, sa_toml_kind(doc2, keep.ptr, keep.len, &kind));
    try std.testing.expectEqual(OK, sa_toml_get_string(doc2, model.ptr, model.len, &sp, &sl));
    try std.testing.expectEqualStrings("new", sp.?[0..@intCast(sl)]);
}

test "toml: stringify escapes, float forms and quoted keys" {
    const doc = sa_toml_new();
    try std.testing.expect(doc != 0);
    defer _ = sa_toml_free(doc);

    const tricky = "tricky";
    const raw = "a\"b\\c\nd\te";
    try std.testing.expectEqual(OK, sa_toml_set_string(doc, tricky.ptr, tricky.len, raw.ptr, raw.len));
    const half = "half";
    try std.testing.expectEqual(OK, sa_toml_set_f64(doc, half.ptr, half.len, 0.5));
    const neg = "neg";
    try std.testing.expectEqual(OK, sa_toml_set_f64(doc, neg.ptr, neg.len, -3.25));
    const spaced = "\"my key\"";
    const v = "v";
    try std.testing.expectEqual(OK, sa_toml_set_string(doc, spaced.ptr, spaced.len, v.ptr, v.len));

    var sp: ?[*]const u8 = null;
    var sl: u64 = 0;
    try std.testing.expectEqual(OK, sa_toml_stringify(doc, &sp, &sl));
    const out = sp.?[0..@intCast(sl)];
    try std.testing.expect(std.mem.indexOf(u8, out, "\"my key\"") != null);

    const doc2 = sa_toml_parse(out.ptr, out.len);
    try std.testing.expect(doc2 != 0);
    defer _ = sa_toml_free(doc2);
    try std.testing.expectEqual(OK, sa_toml_get_string(doc2, tricky.ptr, tricky.len, &sp, &sl));
    try std.testing.expectEqualStrings(raw, sp.?[0..@intCast(sl)]);
    var fv: f64 = 0;
    try std.testing.expectEqual(OK, sa_toml_get_f64(doc2, half.ptr, half.len, &fv));
    try std.testing.expectEqual(@as(f64, 0.5), fv);
    var kind: u32 = 0;
    try std.testing.expectEqual(OK, sa_toml_kind(doc2, neg.ptr, neg.len, &kind));
    try std.testing.expectEqual(KIND_FLOAT, kind);
    try std.testing.expectEqual(OK, sa_toml_get_string(doc2, spaced.ptr, spaced.len, &sp, &sl));
    try std.testing.expectEqualStrings("v", sp.?[0..@intCast(sl)]);
}
