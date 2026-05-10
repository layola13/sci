const std = @import("std");

fn lineCount(text: []const u8) usize {
    if (text.len == 0) return 0;
    var count: usize = 1;
    for (text) |c| {
        if (c == '\n') count += 1;
    }
    return count;
}

test "whitepaper files exist and stay under line limit" {
    const cwd = std.fs.cwd();
    const md_file = try cwd.openFile("docs/whitepaper.md", .{});
    defer md_file.close();
    const txt_file = try cwd.openFile("docs/whitepaper.txt", .{});
    defer txt_file.close();

    const md = try md_file.readToEndAlloc(std.testing.allocator, 1 << 20);
    defer std.testing.allocator.free(md);
    const txt = try txt_file.readToEndAlloc(std.testing.allocator, 1 << 20);
    defer std.testing.allocator.free(txt);

    try std.testing.expect(lineCount(md) <= 2000);
    try std.testing.expect(lineCount(txt) <= 2000);
    try std.testing.expect(std.mem.containsAtLeast(u8, md, 1, "SA-ASM"));
    try std.testing.expect(std.mem.containsAtLeast(u8, txt, 1, "SA-ASM"));
}
