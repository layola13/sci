const std = @import("std");

pub const NetworkInterfaceJson = struct {
    name: []const u8,
    family: []const u8,
    address: []const u8,
    netmask: []const u8,
    scopeid: ?u32,
    cidr: []const u8,
    mac: []const u8,
};

pub fn prefixMask(out: []u8, prefix: u8) void {
    var remaining: usize = @min(@as(usize, prefix), out.len * 8);
    for (out) |*byte| {
        if (remaining >= 8) {
            byte.* = 0xff;
            remaining -= 8;
        } else if (remaining == 0) {
            byte.* = 0;
        } else {
            byte.* = @truncate(@as(u16, 0xff00) >> @intCast(remaining));
            remaining = 0;
        }
    }
}

pub fn formatMac(bytes: []const u8, out: []u8) []const u8 {
    const source = if (bytes.len == 0) &[_]u8{ 0, 0, 0, 0, 0, 0 } else bytes;
    var stream = std.io.fixedBufferStream(out);
    for (source, 0..) |byte, index| {
        if (index != 0) stream.writer().writeByte(':') catch return "00:00:00:00:00:00";
        stream.writer().print("{x:0>2}", .{byte}) catch return "00:00:00:00:00:00";
    }
    return stream.getWritten();
}

pub fn appendJson(
    list: *std.ArrayList(u8),
    first: *bool,
    value: NetworkInterfaceJson,
) !void {
    if (!first.*) try list.append(',');
    first.* = false;
    try std.json.stringify(value, .{}, list.writer());
}

test "Windows network prefix masks clamp and preserve leading bits" {
    var ipv4: [4]u8 = undefined;
    prefixMask(&ipv4, 20);
    try std.testing.expectEqualSlices(u8, &.{ 0xff, 0xff, 0xf0, 0x00 }, &ipv4);

    var ipv6: [16]u8 = undefined;
    prefixMask(&ipv6, 65);
    try std.testing.expectEqualSlices(u8, &([_]u8{0xff} ** 8 ++ [_]u8{0x80} ++ [_]u8{0x00} ** 7), &ipv6);

    prefixMask(&ipv4, 40);
    try std.testing.expectEqualSlices(u8, &.{ 0xff, 0xff, 0xff, 0xff }, &ipv4);
}

test "Windows network MAC formatting handles native and missing addresses" {
    var buffer: [32]u8 = undefined;
    try std.testing.expectEqualStrings(
        "01:23:45:67:89:ab",
        formatMac(&.{ 0x01, 0x23, 0x45, 0x67, 0x89, 0xab }, &buffer),
    );
    try std.testing.expectEqualStrings("00:00:00:00:00:00", formatMac(&.{}, &buffer));
}

test "Windows network JSON helper escapes interface names" {
    var list = std.ArrayList(u8).init(std.testing.allocator);
    defer list.deinit();
    try list.append('[');
    var first = true;
    try appendJson(&list, &first, .{
        .name = "Ethernet \"A\"",
        .family = "IPv4",
        .address = "192.0.2.1",
        .netmask = "255.255.255.0",
        .scopeid = null,
        .cidr = "192.0.2.1/24",
        .mac = "01:23:45:67:89:ab",
    });
    try list.append(']');
    try std.testing.expectEqualStrings(
        "[{\"name\":\"Ethernet \\\"A\\\"\",\"family\":\"IPv4\",\"address\":\"192.0.2.1\",\"netmask\":\"255.255.255.0\",\"scopeid\":null,\"cidr\":\"192.0.2.1/24\",\"mac\":\"01:23:45:67:89:ab\"}]",
        list.items,
    );
}
