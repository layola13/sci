const std = @import("std");

pub fn lineAt(source: []const u8, target_line: u32) ?[]const u8 {
    if (target_line == 0) return null;
    var iter = std.mem.splitScalar(u8, source, '\n');
    var line_no: u32 = 1;
    while (iter.next()) |line| : (line_no += 1) {
        if (line_no == target_line) return line;
    }
    return null;
}

pub fn bufText(buf: []const u8) []const u8 {
    return buf[0..(std.mem.indexOfScalar(u8, buf, 0) orelse buf.len)];
}

pub fn textOrBuf(value: ?[]const u8, buf: []const u8) []const u8 {
    if (value) |text| return text;
    return bufText(buf);
}

pub fn copyTextBuf(dest: []u8, text: []const u8) void {
    const len = @min(dest.len, text.len);
    std.mem.copyForwards(u8, dest[0..len], text[0..len]);
}
