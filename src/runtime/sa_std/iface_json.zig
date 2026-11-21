const std = @import("std");
extern fn freeifaddrs(ifa: ?*struct_ifaddrs) void;
extern fn getifaddrs(ifap: *?*struct_ifaddrs) c_int;
extern fn inet_ntop(af: c_int, src: ?*const anyopaque, dst: [*]u8, size: c_uint) ?[*:0]const u8;

pub fn buildInterfaceAddressesJson(allocator: std.mem.Allocator) ![]u8 {
    var ifap: ?*struct_ifaddrs = null;
    if (getifaddrs(&ifap) != 0) return error.GetifaddrsFailed;
    defer {
        if (ifap) |ptr| freeifaddrs(ptr);
    }

    var list = std.array_list.Managed(u8).init(allocator);
    errdefer list.deinit();
    try list.append('[');

    var first = true;
    var current = ifap;
    while (current) |ifa| : (current = ifa.ifa_next) {
        const addr_ptr = ifa.ifa_addr orelse continue;
        const family = addr_ptr.sa_family;
        if (family != 2 and family != 10) continue;
        const af: c_int = if (family == 2) 2 else 10;

        const addr_src = if (family == 2)
            @as(?*const anyopaque, @ptrCast(&@as(*align(1) const extern struct {
                sa_family: u16,
                sin_port: u16,
                sin_addr: [4]u8,
            }, @ptrCast(addr_ptr)).sin_addr))
        else
            @as(?*const anyopaque, @ptrCast(&@as(*align(1) const extern struct {
                sa_family: u16,
                sin6_port: u16,
                sin6_flowinfo: u32,
                sin6_addr: [16]u8,
                sin6_scope_id: u32,
            }, @ptrCast(addr_ptr)).sin6_addr));

        var addr_buf: [46]u8 = undefined;
        const addr_z = inet_ntop(af, addr_src, &addr_buf, addr_buf.len) orelse continue;
        const addr_text = std.mem.sliceTo(addr_z, 0);

        var mask_text: []const u8 = "";
        var prefix_len: u32 = 0;
        if (ifa.ifa_netmask) |mask_ptr| {
            const mask_src = if (family == 2)
                @as(?*const anyopaque, @ptrCast(&@as(*align(1) const extern struct {
                    sa_family: u16,
                    sin_port: u16,
                    sin_addr: [4]u8,
                }, @ptrCast(mask_ptr)).sin_addr))
            else
                @as(?*const anyopaque, @ptrCast(&@as(*align(1) const extern struct {
                    sa_family: u16,
                    sin6_port: u16,
                    sin6_flowinfo: u32,
                    sin6_addr: [16]u8,
                    sin6_scope_id: u32,
                }, @ptrCast(mask_ptr)).sin6_addr));
            var mask_buf: [46]u8 = undefined;
            if (inet_ntop(af, mask_src, &mask_buf, mask_buf.len)) |mask_z| {
                mask_text = std.mem.sliceTo(mask_z, 0);
            }
            if (family == 2) {
                const mask_bytes = @as(*align(1) const extern struct {
                    sa_family: u16,
                    sin_port: u16,
                    sin_addr: [4]u8,
                }, @ptrCast(mask_ptr)).sin_addr;
                for (mask_bytes) |b| prefix_len += @popCount(b);
            } else {
                const mask_bytes = @as(*align(1) const extern struct {
                    sa_family: u16,
                    sin6_port: u16,
                    sin6_flowinfo: u32,
                    sin6_addr: [16]u8,
                    sin6_scope_id: u32,
                }, @ptrCast(mask_ptr)).sin6_addr;
                for (mask_bytes) |b| prefix_len += @popCount(b);
            }
        }

        var broadcast_text: ?[]const u8 = null;
        var broadcast_buf: [46]u8 = undefined;
        // IFF_BROADCAST (0x2): ifa_ifu holds the broadcast address.
        // For point-to-point links it holds the peer address, which
        // this snapshot deliberately does not expose.
        if (ifa.ifa_flags & 0x2 != 0) {
            if (ifa.ifa_ifu.ifu_broadaddr) |dst_ptr| {
                const dst_src = if (family == 2)
                    @as(?*const anyopaque, @ptrCast(&@as(*align(1) const extern struct {
                        sa_family: u16,
                        sin_port: u16,
                        sin_addr: [4]u8,
                    }, @ptrCast(dst_ptr)).sin_addr))
                else
                    @as(?*const anyopaque, @ptrCast(&@as(*align(1) const extern struct {
                        sa_family: u16,
                        sin6_port: u16,
                        sin6_flowinfo: u32,
                        sin6_addr: [16]u8,
                        sin6_scope_id: u32,
                    }, @ptrCast(dst_ptr)).sin6_addr));
                if (inet_ntop(af, dst_src, &broadcast_buf, broadcast_buf.len)) |dst_z| {
                    broadcast_text = std.mem.sliceTo(dst_z, 0);
                }
            }
        }

        var scope_id: u32 = 0;
        if (family == 10) {
            scope_id = @as(*align(1) const extern struct {
                sa_family: u16,
                sin6_port: u16,
                sin6_flowinfo: u32,
                sin6_addr: [16]u8,
                sin6_scope_id: u32,
            }, @ptrCast(addr_ptr)).sin6_scope_id;
        }

        if (!first) try list.append(',');
        first = false;
        try list.appendSlice("{\"name\":");
        try appendJsonEscapedString(&list, std.mem.sliceTo(ifa.ifa_name, 0));
        var head_buf: [96]u8 = undefined;
        const head = std.fmt.bufPrint(&head_buf, ",\"family\":{d},\"address\":", .{family}) catch unreachable;
        try list.appendSlice(head);
        try appendJsonEscapedString(&list, addr_text);
        try list.appendSlice(",\"netmask\":");
        try appendJsonEscapedString(&list, mask_text);
        var tail_buf: [96]u8 = undefined;
        const tail = std.fmt.bufPrint(&tail_buf, ",\"prefix_len\":{d},\"broadcast\":", .{prefix_len}) catch unreachable;
        try list.appendSlice(tail);
        if (broadcast_text) |btext| {
            try appendJsonEscapedString(&list, btext);
        } else {
            try list.appendSlice("null");
        }
        var scope_buf: [48]u8 = undefined;
        const scope_text = std.fmt.bufPrint(&scope_buf, ",\"scope_id\":{d}}}", .{scope_id}) catch unreachable;
        try list.appendSlice(scope_text);
    }


    try list.append(']');
    return list.toOwnedSlice();
}

const struct_sockaddr = extern struct {
    sa_family: u16,
    sa_data: [14]u8,
};

pub const struct_ifaddrs = extern struct {
    ifa_next: ?*struct_ifaddrs,
    ifa_name: [*:0]const u8,
    ifa_flags: c_uint,
    ifa_addr: ?*struct_sockaddr,
    ifa_netmask: ?*struct_sockaddr,
    ifa_ifu: extern union {
        ifu_broadaddr: ?*struct_sockaddr,
        ifu_dstaddr: ?*struct_sockaddr,
    },
    ifa_data: ?*anyopaque,
};

fn appendJsonEscapedString(list: *std.array_list.Managed(u8), text: []const u8) !void {
    try list.append('"');
    for (text) |c| {
        switch (c) {
            '"' => try list.appendSlice("\\\""),
            '\\' => try list.appendSlice("\\\\"),
            else => {
                if (c < 0x20) {
                    var esc: [6]u8 = undefined;
                    const esc_text = std.fmt.bufPrint(&esc, "\\u{x:0>4}", .{c}) catch unreachable;
                    try list.appendSlice(esc_text);
                } else {
                    try list.append(c);
                }
            },
        }
    }
    try list.append('"');
}
