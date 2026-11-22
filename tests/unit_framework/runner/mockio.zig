const std = @import("std");
const saasm = @import("saasm");
const sio = @import("sio");
const endSaFileLog = @import("util.zig").endSaFileLog;
const errorSaFileLog = @import("util.zig").errorSaFileLog;
const expectContains = @import("util.zig").expectContains;
const saTestJobsArg = @import("util.zig").saTestJobsArg;
const startSaFileLog = @import("util.zig").startSaFileLog;
const writeSource = @import("util.zig").writeSource;

test "native unit framework exposes standard mock io buffer" {
    var original_cwd = try sio.cwd().openDir(".", .{});
    defer original_cwd.close();
    const mock_io_path = try original_cwd.realpathAlloc(std.testing.allocator, "sa_std/testing/mock_io.sa");
    defer std.testing.allocator.free(mock_io_path);

    var tmp = std.testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();

    try std.process.setCurrentDir(std.testing.io, tmp.dir);
    defer original_cwd.setAsCwd() catch {};

    const source = try std.fmt.allocPrint(std.testing.allocator,
        \\@import "{s}"
        \\
        \\@const INPUT = utf8:"abcde"
        \\#def INPUT_LEN = 5
        \\
        \\@test "mock io buffer read write rewind"():
        \\L_ENTRY:
        \\    mock = alloc MockIo_SIZE
        \\    backing = alloc 4
        \\    EXPAND MOCK_IO_INIT mock, backing, 4
        \\    EXPAND MOCK_IO_WRITE written, mock, INPUT, INPUT_LEN
        \\    EXPAND MOCK_IO_LEN len0, mock
        \\    EXPAND MOCK_IO_REWIND mock
        \\    first = alloc 3
        \\    EXPAND MOCK_IO_READ read0, mock, first, 3
        \\    EXPAND MOCK_IO_POS pos0, mock
        \\    second = alloc 2
        \\    EXPAND MOCK_IO_READ read1, mock, second, 2
        \\    EXPAND MOCK_IO_POS pos1, mock
        \\    b0 = load first+0 as u8
        \\    b1 = load first+1 as u8
        \\    b2 = load first+2 as u8
        \\    b3 = load second+0 as u8
        \\    ok_written = eq written, 4
        \\    ok_len = eq len0, 4
        \\    ok_read0 = eq read0, 3
        \\    ok_pos0 = eq pos0, 3
        \\    ok_read1 = eq read1, 1
        \\    ok_pos1 = eq pos1, 4
        \\    ok_b0 = eq b0, 97
        \\    ok_b1 = eq b1, 98
        \\    ok_b2 = eq b2, 99
        \\    ok_b3 = eq b3, 100
        \\    ok01 = and ok_written, ok_len
        \\    ok02 = and ok01, ok_read0
        \\    ok03 = and ok02, ok_pos0
        \\    ok04 = and ok03, ok_read1
        \\    ok05 = and ok04, ok_pos1
        \\    ok06 = and ok05, ok_b0
        \\    ok07 = and ok06, ok_b1
        \\    ok08 = and ok07, ok_b2
        \\    ok = and ok08, ok_b3
        \\    !written
        \\    !len0
        \\    !read0
        \\    !pos0
        \\    !read1
        \\    !pos1
        \\    !b0
        \\    !b1
        \\    !b2
        \\    !b3
        \\    !ok_written
        \\    !ok_len
        \\    !ok_read0
        \\    !ok_pos0
        \\    !ok_read1
        \\    !ok_pos1
        \\    !ok_b0
        \\    !ok_b1
        \\    !ok_b2
        \\    !ok_b3
        \\    !ok01
        \\    !ok02
        \\    !ok03
        \\    !ok04
        \\    !ok05
        \\    !ok06
        \\    !ok07
        \\    !ok08
        \\    !mock
        \\    !backing
        \\    !first
        \\    !second
        \\    br ok -> L_OK, L_FAIL
        \\
        \\L_OK:
        \\    !ok
        \\    return
        \\
        \\L_FAIL:
        \\    !ok
        \\    panic(901)
        \\
    , .{mock_io_path});
    defer std.testing.allocator.free(source);
    try writeSource(tmp.dir, "mock_io_test.sa", source);

    const jobs_arg = try saTestJobsArg(std.testing.allocator);
    defer std.testing.allocator.free(jobs_arg);
    const start_ns = startSaFileLog("mock_io_test.sa", "in-process", jobs_arg, 0, 0);
    // NOTE(Zig 0.17): `errdefer |err|` payload capture was removed after 0.14;
    // inner function + explicit catch preserves the structured error log marker.
    mockIoInProcessInner(jobs_arg, start_ns) catch |err| {
        errorSaFileLog("mock_io_test.sa", "in-process", 0, 0, err);
        return err;
    };
}

pub fn mockIoInProcessInner(jobs_arg: []const u8, start_ns: i128) !void {
    var stdout_buffer = std.array_list.Managed(u8).init(std.testing.allocator);
    defer stdout_buffer.deinit();
    var stderr_buffer = std.array_list.Managed(u8).init(std.testing.allocator);
    defer stderr_buffer.deinit();

    const argv = [_][]const u8{ "sa", "test", "mock_io_test.sa", "--jobs", jobs_arg };
    const code = try saasm.cli.executeWithWriters(
        std.testing.allocator,
        argv[0..],
        sio.managedWriter(&stdout_buffer),
        sio.managedWriter(&stderr_buffer),
    );
    if (code != 0) {
        std.debug.print("stdout: {s}\n", .{stdout_buffer.items});
        std.debug.print("stderr: {s}\n", .{stderr_buffer.items});
    }
    try std.testing.expectEqual(@as(u8, 0), code);
    try expectContains(stdout_buffer.items, "[PASS] mock io buffer read write rewind");
    try expectContains(stdout_buffer.items, "test result: ok. 1 passed; 0 failed; 0 skipped");
    try std.testing.expectEqual(@as(usize, 0), stderr_buffer.items.len);
    endSaFileLog("mock_io_test.sa", "in-process", jobs_arg, 0, 0, start_ns, stdout_buffer.items.len, stderr_buffer.items.len);
}
