const std = @import("std");
const saasm = @import("saasm");

test "db exec returns a stable hash trap and runs binary params" {
    const trap_report = saasm.db.exec.trapUnknownHash();
    try std.testing.expectEqualStrings("query hash is not registered", trap_report.message);

    var original_cwd = try std.fs.cwd().openDir(".", .{});
    defer original_cwd.close();
    var tmp_dir = std.testing.tmpDir(.{ .iterate = true });
    defer tmp_dir.cleanup();

    try tmp_dir.dir.setAsCwd();
    defer original_cwd.setAsCwd() catch {};

    const schema_path = "flash_sale.sadb-schema";
    const qmod_path = "simple.query.sa";
    const params_path = "params.bin";

    {
        var file = try tmp_dir.dir.createFile(schema_path, .{ .truncate = true });
        defer file.close();
        try file.writeAll(
            \\#def MAX_ROWS = 10
            \\#def COL_ID_STRIDE = 8
            \\#def COL_PRICE_STRIDE = 4
        );
    }

    {
        var file = try tmp_dir.dir.createFile(qmod_path, .{ .truncate = true });
        defer file.close();
        try file.writeAll(
            \\@import "flash_sale.sadb-schema"
            \\grants [db_read:flash_sale]
            \\@main(id: u64, factor: u64) -> u64:
            \\L_ENTRY:
            \\total = add id, factor
            \\!id
            \\!factor
            \\return total
        );
    }

    var result = try saasm.db.exec.registerQuery(std.testing.allocator, qmod_path, ".");
    defer result.deinit(std.testing.allocator);

    var params = std.ArrayList(u8).init(std.testing.allocator);
    defer params.deinit();
    try params.writer().writeInt(u64, 7, .little);
    try params.writer().writeInt(u64, 5, .little);
    {
        var file = try tmp_dir.dir.createFile(params_path, .{ .truncate = true });
        defer file.close();
        try file.writeAll(params.items);
    }

    var stdout_buf = std.ArrayList(u8).init(std.testing.allocator);
    defer stdout_buf.deinit();
    var stderr_buf = std.ArrayList(u8).init(std.testing.allocator);
    defer stderr_buf.deinit();

    const hex = std.fmt.bytesToHex(result.hash, .lower);
    var exec_result = try saasm.db.exec.execQuery(std.testing.allocator, ".", hex[0..], params_path, stdout_buf.writer().any(), stderr_buf.writer().any());
    defer exec_result.deinit(std.testing.allocator);
    switch (exec_result) {
        .ok => |ok| {
            try std.testing.expectEqual(@as(u8, 12), ok.code);
            try std.testing.expectEqualStrings("main", ok.function_name);
        },
        .trap => return error.TestUnexpectedResult,
    }
    try std.testing.expectEqual(@as(usize, 0), stdout_buf.items.len);
    try std.testing.expectEqual(@as(usize, 0), stderr_buf.items.len);
}
