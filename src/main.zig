const std = @import("std");
const builtin = @import("builtin");
const cli = @import("cli.zig");
const cli_util = @import("cli_util.zig");
const sio = @import("sa_io.zig");

pub fn main(init: std.process.Init) !void {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();

    const allocator = gpa.allocator();

    var args_it: std.process.Args.Iterator = if (comptime builtin.os.tag == .windows)
        try std.process.Args.Iterator.initAllocator(init.minimal.args, allocator)
    else
        std.process.Args.Iterator.init(init.minimal.args);
    defer args_it.deinit();

    var argv_list: std.array_list.Managed([:0]u8) = .init(allocator);
    defer {
        for (argv_list.items) |s| allocator.free(s);
        argv_list.deinit();
    }
    while (args_it.next()) |arg| {
        try argv_list.append(try allocator.dupeSentinel(u8, arg, 0));
    }
    const argv = try argv_list.toOwnedSlice();
    defer sio.argsFree(allocator, argv);

    const code = cli.execute(allocator, argv) catch |err| {
        var err_buf: [4096]u8 = undefined;
        var err_writer = sio.getStdErr().writer(&err_buf);
        try cli_util.printCliError(&err_writer.interface, err, if (cli.hasJsonFlag(argv)) .json else .human);
        try err_writer.interface.flush();
        std.process.exit(1);
    };

    if (code != 0) std.process.exit(code);
}
