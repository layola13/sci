const std = @import("std");

pub const IfAddrs = extern struct {
    ifa_next: ?*IfAddrs,
    ifa_name: [*:0]const u8,
    ifa_flags: c_uint,
    ifa_addr: ?*std.c.sockaddr,
    ifa_netmask: ?*std.c.sockaddr,
    ifa_ifu: extern union {
        ifu_broadaddr: ?*std.c.sockaddr,
        ifu_dstaddr: ?*std.c.sockaddr,
    },
    ifa_data: ?*anyopaque,
};

extern "c" fn getifaddrs(ifap: *?*IfAddrs) c_int;
extern "c" fn freeifaddrs(ifa: ?*IfAddrs) void;
extern "c" fn inet_ntop(af: c_int, src: *const anyopaque, dst: [*]u8, size: std.c.socklen_t) ?[*:0]const u8;

const NetworkInterfaceJson = struct {
    name: []const u8,
    family: []const u8,
    address: []const u8,
    netmask: []const u8,
    scopeid: ?u32,
    cidr: []const u8,
    mac: []const u8,
};

fn addressSource(addr: *const std.c.sockaddr, is_ipv4: bool) *const anyopaque {
    if (is_ipv4) {
        const inet: *align(1) const std.c.sockaddr.in = @ptrCast(addr);
        return @ptrCast(&inet.addr);
    }
    const inet6: *align(1) const std.c.sockaddr.in6 = @ptrCast(addr);
    return @ptrCast(&inet6.addr);
}

fn prefixLength(mask: *const std.c.sockaddr, is_ipv4: bool) u32 {
    var bits: u32 = 0;
    if (is_ipv4) {
        const inet: *align(1) const std.c.sockaddr.in = @ptrCast(mask);
        for (std.mem.asBytes(&inet.addr)) |byte| bits += @popCount(byte);
        return bits;
    }
    const inet6: *align(1) const std.c.sockaddr.in6 = @ptrCast(mask);
    for (inet6.addr) |byte| bits += @popCount(byte);
    return bits;
}

pub fn network_interfaces_json_from_ifaddrs(
    allocator: std.mem.Allocator,
    ifap: ?*IfAddrs,
    comptime mac_address: fn (?*IfAddrs, []const u8, *[32]u8) []const u8,
) ![]u8 {
    var list = std.ArrayList(u8).init(allocator);
    errdefer list.deinit();
    try list.append('[');

    var first = true;
    var current = ifap;
    while (current) |ifa| : (current = ifa.ifa_next) {
        const addr = ifa.ifa_addr orelse continue;
        const family: c_int = @intCast(addr.family);
        const is_ipv4 = family == std.c.AF.INET;
        if (!is_ipv4 and family != std.c.AF.INET6) continue;

        const name = std.mem.sliceTo(ifa.ifa_name, 0);
        var ip_buffer: [46]u8 = undefined;
        const ip_z = inet_ntop(family, addressSource(addr, is_ipv4), &ip_buffer, ip_buffer.len) orelse continue;
        const ip = std.mem.sliceTo(ip_z, 0);

        var mask_buffer: [46]u8 = undefined;
        var mask: []const u8 = "000.000.000.000";
        var prefix: u32 = 0;
        if (ifa.ifa_netmask) |netmask| {
            if (inet_ntop(family, addressSource(netmask, is_ipv4), &mask_buffer, mask_buffer.len)) |mask_z| {
                mask = std.mem.sliceTo(mask_z, 0);
            }
            prefix = prefixLength(netmask, is_ipv4);
        }

        var mac_buffer: [32]u8 = undefined;
        const mac = mac_address(ifap, name, &mac_buffer);
        var cidr_buffer: [64]u8 = undefined;
        const cidr = try std.fmt.bufPrint(&cidr_buffer, "{s}/{d}", .{ ip, prefix });

        if (!first) try list.append(',');
        first = false;
        try std.json.stringify(NetworkInterfaceJson{
            .name = name,
            .family = if (is_ipv4) "IPv4" else "IPv6",
            .address = ip,
            .netmask = mask,
            .scopeid = null,
            .cidr = cidr,
            .mac = mac,
        }, .{}, list.writer());
    }

    try list.append(']');
    return list.toOwnedSlice();
}

pub fn network_interfaces_json_alloc(
    allocator: std.mem.Allocator,
    comptime mac_address: fn (?*IfAddrs, []const u8, *[32]u8) []const u8,
) ![]u8 {
    var ifap: ?*IfAddrs = null;
    if (getifaddrs(&ifap) != 0) return error.Unexpected;
    defer freeifaddrs(ifap);
    return network_interfaces_json_from_ifaddrs(allocator, ifap, mac_address);
}
