const std = @import("std");
const sio = @import("sio");
const ERR_INVALID = @import("y01.zig").ERR_INVALID;
const ERR_NOT_FOUND = @import("y01.zig").ERR_NOT_FOUND;
const KIND_FLOAT = @import("y01.zig").KIND_FLOAT;
const KIND_NULL = @import("y01.zig").KIND_NULL;
const KIND_STRING = @import("y01.zig").KIND_STRING;
const OK = @import("y01.zig").OK;
const expectParse = @import("y05.zig").expectParse;
const getBool = @import("y05.zig").getBool;
const getF64 = @import("y05.zig").getF64;
const getI64 = @import("y05.zig").getI64;
const getString = @import("y05.zig").getString;
const kindOf = @import("y05.zig").kindOf;
const lastErrorText = @import("y05.zig").lastErrorText;
const sa_yaml_array_push_i64 = @import("y05.zig").sa_yaml_array_push_i64;
const sa_yaml_array_push_string = @import("y05.zig").sa_yaml_array_push_string;
const sa_yaml_array_push_table = @import("y05.zig").sa_yaml_array_push_table;
const sa_yaml_count_documents = @import("y04.zig").sa_yaml_count_documents;
const sa_yaml_free = @import("y04.zig").sa_yaml_free;
const sa_yaml_kind = @import("y04.zig").sa_yaml_kind;
const sa_yaml_new = @import("y05.zig").sa_yaml_new;
const sa_yaml_parse = @import("y04.zig").sa_yaml_parse;
const sa_yaml_parse_at = @import("y04.zig").sa_yaml_parse_at;
const sa_yaml_remove = @import("y05.zig").sa_yaml_remove;
const sa_yaml_set_bool = @import("y05.zig").sa_yaml_set_bool;
const sa_yaml_set_i64 = @import("y05.zig").sa_yaml_set_i64;
const sa_yaml_set_null = @import("y05.zig").sa_yaml_set_null;
const sa_yaml_set_string = @import("y05.zig").sa_yaml_set_string;
const sa_yaml_stringify = @import("y05.zig").sa_yaml_stringify;
const sa_yaml_to_json = @import("y05.zig").sa_yaml_to_json;

test "yaml: type inference" {
    const h = try expectParse(
        \\n1: ~
        \\n2: null
        \\n3:
        \\b1: true
        \\b2: FALSE
        \\s1: yes
        \\s2: on
        \\s3: Off
        \\i1: 42
        \\i2: -17
        \\i3: +12
        \\i4: 1_000
        \\i5: 0x1F
        \\i6: 0o17
        \\i7: 017
        \\i8: 0b101
        \\i9: 08
        \\f1: 1.5
        \\f2: .5
        \\f3: 5.
        \\f4: 1e3
        \\f5: -2.5e-2
        \\f6: .inf
        \\f7: -.inf
        \\s4: 2026-10-28
        \\s5: 1:30
        \\s6: 1.2.3
        \\s7: '42'
        \\big: 99999999999999999999999
    );
    defer _ = sa_yaml_free(h);
    try std.testing.expectEqual(KIND_NULL, try kindOf(h, "n1"));
    try std.testing.expectEqual(KIND_NULL, try kindOf(h, "n2"));
    try std.testing.expectEqual(KIND_NULL, try kindOf(h, "n3"));
    try std.testing.expectEqual(true, try getBool(h, "b1"));
    try std.testing.expectEqual(false, try getBool(h, "b2"));
    // YAML 1.1 booleans stay strings under the JSON-aligned rules.
    try std.testing.expectEqualStrings("yes", try getString(h, "s1"));
    try std.testing.expectEqualStrings("on", try getString(h, "s2"));
    try std.testing.expectEqualStrings("Off", try getString(h, "s3"));
    try std.testing.expectEqual(@as(i64, 42), try getI64(h, "i1"));
    try std.testing.expectEqual(@as(i64, -17), try getI64(h, "i2"));
    try std.testing.expectEqual(@as(i64, 12), try getI64(h, "i3"));
    try std.testing.expectEqual(@as(i64, 1000), try getI64(h, "i4"));
    try std.testing.expectEqual(@as(i64, 31), try getI64(h, "i5"));
    try std.testing.expectEqual(@as(i64, 15), try getI64(h, "i6"));
    try std.testing.expectEqual(@as(i64, 15), try getI64(h, "i7"));
    try std.testing.expectEqual(@as(i64, 5), try getI64(h, "i8"));
    try std.testing.expectEqual(@as(i64, 8), try getI64(h, "i9"));
    try std.testing.expectEqual(@as(f64, 1.5), try getF64(h, "f1"));
    try std.testing.expectEqual(@as(f64, 0.5), try getF64(h, "f2"));
    try std.testing.expectEqual(@as(f64, 5.0), try getF64(h, "f3"));
    try std.testing.expectEqual(@as(f64, 1000.0), try getF64(h, "f4"));
    try std.testing.expectEqual(@as(f64, -0.025), try getF64(h, "f5"));
    try std.testing.expect(std.math.isInf(try getF64(h, "f6")));
    try std.testing.expect(std.math.isInf(try getF64(h, "f7")));
    // Timestamps and sexagesimal numbers stay strings.
    try std.testing.expectEqualStrings("2026-10-28", try getString(h, "s4"));
    try std.testing.expectEqualStrings("1:30", try getString(h, "s5"));
    try std.testing.expectEqualStrings("1.2.3", try getString(h, "s6"));
    try std.testing.expectEqualStrings("42", try getString(h, "s7"));
    // i64 overflow becomes a float.
    try std.testing.expectEqual(KIND_FLOAT, try kindOf(h, "big"));
}

test "yaml: anchors aliases and merge keys" {
    const h = try expectParse(
        \\defaults: &def
        \\  retries: 3
        \\  timeout: 30
        \\prod:
        \\  <<: *def
        \\  timeout: 60
        \\copy: *def
        \\scalar_anchor: &greeting hello
        \\use: *greeting
    );
    defer _ = sa_yaml_free(h);
    try std.testing.expectEqual(@as(i64, 3), try getI64(h, "prod.retries"));
    try std.testing.expectEqual(@as(i64, 60), try getI64(h, "prod.timeout"));
    try std.testing.expectEqual(@as(i64, 30), try getI64(h, "copy.timeout"));
    try std.testing.expectEqualStrings("hello", try getString(h, "use"));
    // The alias is a deep copy: mutating the source leaves it alone.
    try std.testing.expectEqual(OK, sa_yaml_set_i64(h, "defaults.timeout", 16, 99));
    try std.testing.expectEqual(@as(i64, 99), try getI64(h, "defaults.timeout"));
    try std.testing.expectEqual(@as(i64, 30), try getI64(h, "copy.timeout"));
    try std.testing.expectEqual(@as(i64, 60), try getI64(h, "prod.timeout"));
}

test "yaml: merge key sequence order" {
    const h = try expectParse(
        \\a: &a {x: 1, shared: from-a}
        \\b: &b {y: 2, shared: from-b}
        \\c:
        \\  <<: [*a, *b]
        \\  z: 3
    );
    defer _ = sa_yaml_free(h);
    try std.testing.expectEqualStrings("from-a", try getString(h, "c.shared"));
    try std.testing.expectEqual(@as(i64, 2), try getI64(h, "c.y"));
    try std.testing.expectEqual(@as(i64, 3), try getI64(h, "c.z"));
}

test "yaml: multi-document streams" {
    const text =
        \\%YAML 1.2
        \\---
        \\a: 1
        \\---
        \\b: 2
        \\...
    ;
    var count: u64 = 0;
    try std.testing.expectEqual(OK, sa_yaml_count_documents(text.ptr, text.len, &count));
    try std.testing.expectEqual(@as(u64, 2), count);
    const h0 = sa_yaml_parse_at(text.ptr, text.len, 0);
    defer _ = sa_yaml_free(h0);
    try std.testing.expect(h0 != 0);
    try std.testing.expectEqual(@as(i64, 1), try getI64(h0, "a"));
    const h1 = sa_yaml_parse_at(text.ptr, text.len, 1);
    defer _ = sa_yaml_free(h1);
    try std.testing.expect(h1 != 0);
    try std.testing.expectEqual(@as(i64, 2), try getI64(h1, "b"));
    // Out of range index fails loudly.
    try std.testing.expectEqual(@as(u64, 0), sa_yaml_parse_at(text.ptr, text.len, 2));
    try std.testing.expect(std.mem.indexOf(u8, lastErrorText(), "out of range") != null);
    // sa_yaml_parse reads document 0.
    const hd = try expectParse(text);
    defer _ = sa_yaml_free(hd);
    try std.testing.expectEqual(@as(i64, 1), try getI64(hd, "a"));
    // Empty input: zero documents, but parse yields a null document.
    try std.testing.expectEqual(OK, sa_yaml_count_documents("", 0, &count));
    try std.testing.expectEqual(@as(u64, 0), count);
    const he = try expectParse("");
    defer _ = sa_yaml_free(he);
    try std.testing.expectEqual(KIND_NULL, try kindOf(he, ""));
}

test "yaml: errors carry positions" {
    const cases = [_]struct { text: []const u8, needle: []const u8 }{
        .{ .text = "a: 1\na: 2\n", .needle = "duplicate key" },
        .{ .text = "a:\n\tb: 1\n", .needle = "tab character" },
        .{ .text = "a: 'unterminated\n", .needle = "unterminated quoted scalar" },
        .{ .text = "a: !!str 5\n", .needle = "unsupported" },
        .{ .text = "%TAG ! tag:example.com,2026:\na: 1\n", .needle = "unsupported" },
        .{ .text = "a: [1, 2\n", .needle = "unterminated flow" },
        .{ .text = "a: *missing\n", .needle = "unknown alias" },
        .{ .text = "a: 1\n  b: 2\n", .needle = "line 2" },
    };
    for (cases) |case| {
        const h = sa_yaml_parse(case.text.ptr, case.text.len);
        try std.testing.expectEqual(@as(u64, 0), h);
        const msg = lastErrorText();
        if (std.mem.indexOf(u8, msg, case.needle) == null) {
            std.debug.print("error case needle '{s}' not in '{s}'\n", .{ case.needle, msg });
            return error.TestUnexpectedResult;
        }
        try std.testing.expect(std.mem.indexOf(u8, msg, "line ") != null);
    }
    // The duplicate key error names the duplicate's own line.
    const dup = "one: 1\ntwo: 2\none: 3\n";
    try std.testing.expectEqual(@as(u64, 0), sa_yaml_parse(dup.ptr, dup.len));
    try std.testing.expect(std.mem.indexOf(u8, lastErrorText(), "line 3") != null);
}

test "yaml: build and stringify round trip" {
    const h = sa_yaml_new();
    try std.testing.expect(h != 0);
    defer _ = sa_yaml_free(h);
    try std.testing.expectEqual(OK, sa_yaml_set_string(h, "server.host", 11, "127.0.0.1", 9));
    try std.testing.expectEqual(OK, sa_yaml_set_i64(h, "server.port", 11, 9000));
    try std.testing.expectEqual(OK, sa_yaml_set_bool(h, "server.tls", 10, 1));
    try std.testing.expectEqual(OK, sa_yaml_set_null(h, "server.note", 11));
    try std.testing.expectEqual(OK, sa_yaml_array_push_string(h, "tags", 4, "one", 3));
    try std.testing.expectEqual(OK, sa_yaml_array_push_i64(h, "tags", 4, 2));
    try std.testing.expectEqual(OK, sa_yaml_array_push_table(h, "items", 5));
    try std.testing.expectEqual(OK, sa_yaml_set_string(h, "items.0.name", 12, "first", 5));
    var p: ?[*]const u8 = null;
    var l: u64 = 0;
    try std.testing.expectEqual(OK, sa_yaml_stringify(h, &p, &l));
    const text = p.?[0..@intCast(l)];
    const h2 = try expectParse(text);
    defer _ = sa_yaml_free(h2);
    try std.testing.expectEqualStrings("127.0.0.1", try getString(h2, "server.host"));
    try std.testing.expectEqual(@as(i64, 9000), try getI64(h2, "server.port"));
    try std.testing.expectEqual(true, try getBool(h2, "server.tls"));
    try std.testing.expectEqual(KIND_NULL, try kindOf(h2, "server.note"));
    try std.testing.expectEqualStrings("one", try getString(h2, "tags.0"));
    try std.testing.expectEqual(@as(i64, 2), try getI64(h2, "tags.1"));
    try std.testing.expectEqualStrings("first", try getString(h2, "items.0.name"));
    // Removal: a table key and an array element.
    try std.testing.expectEqual(OK, sa_yaml_remove(h, "server.tls", 10));
    var kk: u32 = 0;
    try std.testing.expectEqual(ERR_NOT_FOUND, sa_yaml_kind(h, "server.tls", 10, &kk));
    try std.testing.expectEqual(OK, sa_yaml_remove(h, "tags.0", 6));
    try std.testing.expectEqual(@as(i64, 2), try getI64(h, "tags.0"));
    // Pushing onto a scalar path is an explicit error.
    try std.testing.expectEqual(ERR_INVALID, sa_yaml_array_push_i64(h, "server.port", 11, 1));
}

test "yaml: stringify stability and to_json" {
    const text =
        \\server:
        \\  port: 8080
        \\  ratio: 1.5
        \\  host: example.com
        \\  secure: true
        \\  note: null
        \\  tags:
        \\    - a
        \\    - b
    ;
    const h = try expectParse(text);
    defer _ = sa_yaml_free(h);
    var p: ?[*]const u8 = null;
    var l: u64 = 0;
    try std.testing.expectEqual(OK, sa_yaml_to_json(h, &p, &l));
    try std.testing.expectEqualStrings(
        "{\"server\":{\"port\":8080,\"ratio\":1.5,\"host\":\"example.com\",\"secure\":true,\"note\":null,\"tags\":[\"a\",\"b\"]}}",
        p.?[0..@intCast(l)],
    );
    try std.testing.expectEqual(OK, sa_yaml_stringify(h, &p, &l));
    const once = try std.testing.allocator.dupe(u8, p.?[0..@intCast(l)]);
    defer std.testing.allocator.free(once);
    const h2 = try expectParse(once);
    defer _ = sa_yaml_free(h2);
    try std.testing.expectEqual(OK, sa_yaml_stringify(h2, &p, &l));
    try std.testing.expectEqualStrings(once, p.?[0..@intCast(l)]);
}

test "yaml: scalar and empty roots" {
    const hs = try expectParse("just a string");
    defer _ = sa_yaml_free(hs);
    try std.testing.expectEqual(KIND_STRING, try kindOf(hs, ""));
    const hi = try expectParse("42");
    defer _ = sa_yaml_free(hi);
    try std.testing.expectEqual(@as(i64, 42), try getI64(hi, ""));
    const ha = try expectParse("- 1\n- 2\n");
    defer _ = sa_yaml_free(ha);
    try std.testing.expectEqual(@as(i64, 2), try getI64(ha, "1"));
    const hn = try expectParse("---\n");
    defer _ = sa_yaml_free(hn);
    try std.testing.expectEqual(KIND_NULL, try kindOf(hn, ""));
}

test "yaml: gateway-shaped config corpus" {
    const h = try expectParse(
        \\# sub2api-shaped gateway configuration (structure-equivalent,
        \\# secrets replaced)
        \\server:
        \\  host: "0.0.0.0"
        \\  port: 8080
        \\  mode: release
        \\database:
        \\  driver: postgres
        \\  dsn: postgres://user:pass@db.internal:5432/sub2api?sslmode=require
        \\  max_open_conns: 50
        \\redis:
        \\  addr: redis.internal:6379
        \\  db: 0
        \\  pool_size: 100
        \\jwt:
        \\  secret: "replace-me"
        \\  expire_hours: 24
        \\defaults: &defaults
        \\  rate_multiplier: 1.0
        \\  enabled: true
        \\groups:
        \\  - name: default
        \\    <<: *defaults
        \\  - name: vip
        \\    <<: *defaults
        \\    rate_multiplier: 0.8
        \\notes: |
        \\  first line
        \\  second line
    );
    defer _ = sa_yaml_free(h);
    try std.testing.expectEqualStrings("postgres", try getString(h, "database.driver"));
    try std.testing.expectEqualStrings("postgres://user:pass@db.internal:5432/sub2api?sslmode=require", try getString(h, "database.dsn"));
    try std.testing.expectEqual(@as(i64, 50), try getI64(h, "database.max_open_conns"));
    try std.testing.expectEqual(@as(i64, 100), try getI64(h, "redis.pool_size"));
    try std.testing.expectEqual(@as(i64, 24), try getI64(h, "jwt.expire_hours"));
    try std.testing.expectEqual(@as(f64, 1.0), try getF64(h, "groups.0.rate_multiplier"));
    try std.testing.expectEqual(true, try getBool(h, "groups.0.enabled"));
    try std.testing.expectEqual(@as(f64, 0.8), try getF64(h, "groups.1.rate_multiplier"));
    try std.testing.expectEqualStrings("first line\nsecond line\n", try getString(h, "notes"));
    // The whole document survives a YAML -> JSON view conversion.
    var p: ?[*]const u8 = null;
    var l: u64 = 0;
    try std.testing.expectEqual(OK, sa_yaml_to_json(h, &p, &l));
    try std.testing.expect(std.mem.indexOf(u8, p.?[0..@intCast(l)], "\"driver\":\"postgres\"") != null);
}
