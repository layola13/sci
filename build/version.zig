const std = @import("std");

pub fn latestGitTag(allocator: std.mem.Allocator, io: std.Io) ?[]const u8 {
    const argv = [_][]const u8{ "git", "tag", "--sort=-v:refname" };
    const result = std.process.run(allocator, io, .{
        .argv = argv[0..],
    }) catch return null;
    defer allocator.free(result.stderr);

    switch (result.term) {
        .exited => |code| if (code != 0) {
            allocator.free(result.stdout);
            return null;
        },
        else => {
            allocator.free(result.stdout);
            return null;
        },
    }

    const trimmed = std.mem.trim(u8, result.stdout, " \t\r\n");
    if (trimmed.len == 0) {
        allocator.free(result.stdout);
        return null;
    }
    // Skip non-release tags (e.g. zig-0.14.1-freebsd toolchain assets):
    // the embedded version must be a numeric release like 0.1.6.
    var it = std.mem.splitScalar(u8, trimmed, '\n');
    while (it.next()) |line| {
        const tag = std.mem.trim(u8, line, " \t\r");
        if (tag.len == 0) continue;
        const body = if (tag[0] == 'v' and tag.len > 1) tag[1..] else tag;
        if (body.len == 0) continue;
        if (body[0] < '0' or body[0] > '9') continue;
        const owned = allocator.dupe(u8, tag) catch {
            allocator.free(result.stdout);
            return null;
        };
        allocator.free(result.stdout);
        return owned;
    }
    allocator.free(result.stdout);
    return null;
}
