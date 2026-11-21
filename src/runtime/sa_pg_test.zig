const std = @import("std");
const ALLOC = @import("sa_pg.zig").ALLOC;
const ERR_HANDLE = @import("sa_pg.zig").ERR_HANDLE;
const ERR_INVALID = @import("sa_pg.zig").ERR_INVALID;
const ERR_NOT_FOUND = @import("sa_pg.zig").ERR_NOT_FOUND;
const ERR_UNSUPPORTED = @import("sa_pg.zig").ERR_UNSUPPORTED;
const Field = @import("sa_pg.zig").Field;
const ScramState = @import("sa_pg.zig").ScramState;
const cleanTag = @import("sa_pg.zig").cleanTag;
const md5AuthResponse = @import("sa_pg.zig").md5AuthResponse;
const parseDataRow = @import("sa_pg.zig").parseDataRow;
const parseErrorBody = @import("sa_pg.zig").parseErrorBody;
const parseRowDescription = @import("sa_pg.zig").parseRowDescription;
const parseTagCount = @import("sa_pg.zig").parseTagCount;
const sa_pg_close = @import("sa_pg.zig").sa_pg_close;
const sa_pg_connect = @import("sa_pg.zig").sa_pg_connect;
const sa_pg_last_sqlstate = @import("sa_pg.zig").sa_pg_last_sqlstate;
const sa_pg_result_rows = @import("sa_pg.zig").sa_pg_result_rows;
const scramClientFinal = @import("sa_pg.zig").scramClientFinal;
const scramVerifyServerFinal = @import("sa_pg.zig").scramVerifyServerFinal;

test "pg md5 auth response matches reference vector" {
    var out: [35]u8 = undefined;
    md5AuthResponse("bob", "secret", &.{ 1, 2, 3, 4 }, &out);
    try std.testing.expectEqualStrings("md5f21dfe33ff3a9e03dbc3e008251fe5cc", &out);
}

test "pg scram-sha-256 client final and server verify" {
    var state = ScramState{
        .client_nonce = try ALLOC.dupe(u8, "ClientNonce123"),
        .client_first_bare = try ALLOC.dupe(u8, "n=alice,r=ClientNonce123"),
    };
    defer state.deinit();
    var expected_sig: [32]u8 = undefined;
    const server_first = "r=ClientNonce123ServerNonce,s=AAECAwQFBgcICQoLDA0ODw==,i=4096";
    const final_msg = try scramClientFinal(&state, "wonderland", server_first, &expected_sig);
    defer ALLOC.free(final_msg);
    try std.testing.expectEqualStrings(
        "c=biws,r=ClientNonce123ServerNonce,p=csb5CfCFSUvpkjN2wstfk95EFZMTN7Uv1LwkLTcNwh0=",
        final_msg,
    );
    try scramVerifyServerFinal(&expected_sig, "v=P4/PjPVdJBzd6HipXn8WldnX0faYBNTBHQLSg47Hsqw=");
    try std.testing.expectError(error.Protocol, scramVerifyServerFinal(&expected_sig, "v=AAAA/PjPVdJBzd6HipXn8WldnX0faYBNTBHQLSg47Hsqw="));
    // A server nonce that does not extend ours is a protocol error.
    var state2 = ScramState{
        .client_nonce = try ALLOC.dupe(u8, "ClientNonce123"),
        .client_first_bare = try ALLOC.dupe(u8, "n=alice,r=ClientNonce123"),
    };
    defer state2.deinit();
    var sig2: [32]u8 = undefined;
    try std.testing.expectError(error.Protocol, scramClientFinal(&state2, "wonderland", "r=OtherNonce,s=AAECAwQFBgcICQoLDA0ODw==,i=4096", &sig2));
}

test "pg row description and data row parsing" {
    // RowDescription body: 2 fields ("id" int4/23, "name" text/25).
    var body: std.array_list.Managed(u8) = .init(ALLOC);
    defer body.deinit();
    try body.appendSlice(&.{ 0, 2 });
    try body.appendSlice("id\x00");
    try body.appendSlice(&.{ 0, 0, 0, 0, 0, 0 }); // table oid + attnum
    try body.appendSlice(&.{ 0, 0, 0, 23, 0, 4, 0xff, 0xff, 0xff, 0xff, 0, 0 });
    try body.appendSlice("name\x00");
    try body.appendSlice(&.{ 0, 0, 0, 0, 0, 0 });
    try body.appendSlice(&.{ 0, 0, 0, 25, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0, 0 });

    var fields: std.array_list.Managed(Field) = .init(ALLOC);
    defer {
        for (fields.items) |f| ALLOC.free(f.name);
        fields.deinit();
    }
    try parseRowDescription(body.items, &fields);
    try std.testing.expectEqual(@as(usize, 2), fields.items.len);
    try std.testing.expectEqualStrings("id", fields.items[0].name);
    try std.testing.expectEqual(@as(u32, 23), fields.items[0].type_oid);
    try std.testing.expectEqualStrings("name", fields.items[1].name);
    try std.testing.expectEqual(@as(u32, 25), fields.items[1].type_oid);

    // DataRow body: "42", NULL, "hi".
    var dbody: std.array_list.Managed(u8) = .init(ALLOC);
    defer dbody.deinit();
    try dbody.appendSlice(&.{ 0, 3 });
    try dbody.appendSlice(&.{ 0, 0, 0, 2 });
    try dbody.appendSlice("42");
    try dbody.appendSlice(&.{ 0xff, 0xff, 0xff, 0xff });
    try dbody.appendSlice(&.{ 0, 0, 0, 2 });
    try dbody.appendSlice("hi");

    var row: std.array_list.Managed(?[]u8) = .init(ALLOC);
    defer {
        for (row.items) |c| if (c) |b| ALLOC.free(b);
        row.deinit();
    }
    try parseDataRow(dbody.items, &row);
    try std.testing.expectEqual(@as(usize, 3), row.items.len);
    try std.testing.expectEqualStrings("42", row.items[0].?);
    try std.testing.expect(row.items[1] == null);
    try std.testing.expectEqualStrings("hi", row.items[2].?);
}

test "pg error body and tag count parsing" {
    const fields = parseErrorBody("SERROR\x00VERROR\x00C42601\x00Msyntax error\x00Dnear \"x\"\x00\x00");
    try std.testing.expectEqualStrings("ERROR", fields.severity);
    try std.testing.expectEqualStrings("42601", fields.code);
    try std.testing.expectEqualStrings("syntax error", fields.message);
    try std.testing.expectEqualStrings("near \"x\"", fields.detail);

    try std.testing.expectEqual(@as(?u64, 3), parseTagCount("INSERT 0 3"));
    try std.testing.expectEqual(@as(?u64, 5), parseTagCount("SELECT 5"));
    // CommandComplete bodies are NUL-terminated on the wire.
    try std.testing.expectEqual(@as(?u64, 2), parseTagCount(cleanTag("INSERT 0 2\x00")));
    try std.testing.expectEqual(@as(?u64, null), parseTagCount(cleanTag("CREATE TABLE\x00")));
    try std.testing.expectEqual(@as(?u64, 0), parseTagCount("UPDATE 0"));
    try std.testing.expectEqual(@as(?u64, null), parseTagCount("CREATE TABLE"));
}

test "pg abi rejects invalid arguments and handles" {
    var handle: u64 = 77;
    try std.testing.expectEqual(ERR_INVALID, sa_pg_connect("", 0, 0, "u".ptr, 1, null, 0, "d".ptr, 1, 0, 0, &handle));
    try std.testing.expectEqual(ERR_UNSUPPORTED, sa_pg_connect("h".ptr, 1, 0, "u".ptr, 1, null, 0, "d".ptr, 1, 0, 2, &handle));
    try std.testing.expectEqual(ERR_HANDLE, sa_pg_close(987654321));
    var five: [5]u8 = undefined;
    try std.testing.expectEqual(ERR_HANDLE, sa_pg_last_sqlstate(987654321, &five));
    try std.testing.expectEqual(ERR_NOT_FOUND, sa_pg_result_rows(987654321, &handle));
}
