const std = @import("std");
const cli = @import("cli.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    const allocator = gpa.allocator();
    const argv = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, argv);

    const code = cli.execute(allocator, argv) catch |err| {
        const stderr = std.io.getStdErr().writer();
        try cli.printCliError(stderr, err, if (cli.hasJsonFlag(argv)) .json else .human);
        std.process.exit(1);
    };

    if (code != 0) std.process.exit(code);
}
