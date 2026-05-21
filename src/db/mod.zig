const std = @import("std");
pub const trap = @import("common/trap.zig");

pub const schema = @import("schema.zig");
pub const blob = @import("blob.zig");
pub const qmod = @import("qmod.zig");
pub const table = @import("table.zig");
pub const referee_db = @import("referee_db.zig");
pub const trap_db = @import("trap_db.zig");
pub const exec = @import("exec.zig");

test "db module exports real symbols" {
    _ = schema.Schema;
    _ = blob.BlobArena;
    _ = qmod.Qmod;
    _ = table.TableInfo;
    _ = referee_db.scanForTrap;
    _ = trap_db.DbTrap.capability_escalation;
    _ = exec.trapUnknownHash;
    try std.testing.expect(true);
}

fn writeFile(dir: std.fs.Dir, path: []const u8, bytes: []const u8) !void {
    var file = try dir.createFile(path, .{ .truncate = true });
    defer file.close();
    try file.writeAll(bytes);
}

test "db exec returns a trap for unknown hash" {
    const report = exec.trapUnknownHash();
    try std.testing.expectEqual(trap.Trap.db_query_hash_unknown, report.trap);
    try std.testing.expectEqualStrings("query hash is not registered", report.message);
}

test "db exec runs a registered query with binary params" {
    var original_cwd = try std.fs.cwd().openDir(".", .{});
    defer original_cwd.close();
    var tmp_dir = std.testing.tmpDir(.{ .iterate = true });
    defer tmp_dir.cleanup();

    try tmp_dir.dir.setAsCwd();
    defer original_cwd.setAsCwd() catch {};

    const qmod_path = "simple.query.saasm";
    const params_path = "params.bin";

    try writeFile(tmp_dir.dir, qmod_path,
        \\@main(id: u64, factor: u64) -> u64:
        \\L_ENTRY:
        \\total = add id, factor
        \\!id
        \\!factor
        \\return total
    );

    var result = try exec.registerQuery(std.testing.allocator, qmod_path, ".");
    defer result.deinit(std.testing.allocator);

    var params = std.ArrayList(u8).init(std.testing.allocator);
    defer params.deinit();
    try params.writer().writeInt(u64, 7, .little);
    try params.writer().writeInt(u64, 5, .little);
    try writeFile(tmp_dir.dir, params_path, params.items);

    var stdout_buf = std.ArrayList(u8).init(std.testing.allocator);
    defer stdout_buf.deinit();
    var stderr_buf = std.ArrayList(u8).init(std.testing.allocator);
    defer stderr_buf.deinit();

    const hex = std.fmt.bytesToHex(result.hash, .lower);
    var exec_result = try exec.execQuery(std.testing.allocator, ".", hex[0..], params_path, stdout_buf.writer().any(), stderr_buf.writer().any());
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

test "db exec runs an imported registered query with binary params" {
    var original_cwd = try std.fs.cwd().openDir(".", .{});
    defer original_cwd.close();
    var tmp_dir = std.testing.tmpDir(.{ .iterate = true });
    defer tmp_dir.cleanup();

    try tmp_dir.dir.setAsCwd();
    defer original_cwd.setAsCwd() catch {};

    const schema_path = "simple.sadb-schema";
    const qmod_path = "simple.query.saasm";
    const params_path = "params.bin";

    try writeFile(tmp_dir.dir, schema_path,
        \\#def MAX_ROWS = 10
        \\#def COL_ID_STRIDE = 8 // u64
        \\#def COL_FACTOR_STRIDE = 8 // u64
        \\#def TABLE_ROW_BYTES = 16
    );
    try writeFile(tmp_dir.dir, qmod_path,
        \\@import "simple.sadb-schema"
        \\grants [db_read:simple]
        \\@main(id: u64, factor: u64) -> u64:
        \\L_ENTRY:
        \\total = add id, factor
        \\!id
        \\!factor
        \\return total
    );

    var result = try exec.registerQuery(std.testing.allocator, qmod_path, ".");
    defer result.deinit(std.testing.allocator);

    var params = std.ArrayList(u8).init(std.testing.allocator);
    defer params.deinit();
    try params.writer().writeInt(u64, 7, .little);
    try params.writer().writeInt(u64, 5, .little);
    try writeFile(tmp_dir.dir, params_path, params.items);

    var stdout_buf = std.ArrayList(u8).init(std.testing.allocator);
    defer stdout_buf.deinit();
    var stderr_buf = std.ArrayList(u8).init(std.testing.allocator);
    defer stderr_buf.deinit();

    const hex = std.fmt.bytesToHex(result.hash, .lower);
    var exec_result = try exec.execQuery(std.testing.allocator, ".", hex[0..], params_path, stdout_buf.writer().any(), stderr_buf.writer().any());
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
