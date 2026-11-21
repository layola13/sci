const std = @import("std");
const builtin = @import("builtin");
const sio = @import("sio");
const DirEntriesResource = @import("w01.zig").DirEntriesResource;
const DirEntryResource = @import("w01.zig").DirEntryResource;
const GetLastError = @import("w01.zig").GetLastError;
const JsonDocument = @import("w01.zig").JsonDocument;
const JsonNode = @import("w01.zig").JsonNode;
const JsonTokenizer = @import("w01.zig").JsonTokenizer;
const JsonWriter = @import("w01.zig").JsonWriter;
const NetAddrResource = @import("w01.zig").NetAddrResource;
const ProcessResource = @import("w01.zig").ProcessResource;
const SA_JSON_TOKEN_ALLOCATED_NUMBER = @import("w01.zig").SA_JSON_TOKEN_ALLOCATED_NUMBER;
const SA_JSON_TOKEN_ALLOCATED_STRING = @import("w01.zig").SA_JSON_TOKEN_ALLOCATED_STRING;
const SA_JSON_TOKEN_ARRAY_BEGIN = @import("w01.zig").SA_JSON_TOKEN_ARRAY_BEGIN;
const SA_JSON_TOKEN_ARRAY_END = @import("w01.zig").SA_JSON_TOKEN_ARRAY_END;
const SA_JSON_TOKEN_END_OF_DOCUMENT = @import("w01.zig").SA_JSON_TOKEN_END_OF_DOCUMENT;
const SA_JSON_TOKEN_FALSE = @import("w01.zig").SA_JSON_TOKEN_FALSE;
const SA_JSON_TOKEN_NULL = @import("w01.zig").SA_JSON_TOKEN_NULL;
const SA_JSON_TOKEN_NUMBER = @import("w01.zig").SA_JSON_TOKEN_NUMBER;
const SA_JSON_TOKEN_OBJECT_BEGIN = @import("w01.zig").SA_JSON_TOKEN_OBJECT_BEGIN;
const SA_JSON_TOKEN_OBJECT_END = @import("w01.zig").SA_JSON_TOKEN_OBJECT_END;
const SA_JSON_TOKEN_PARTIAL_NUMBER = @import("w01.zig").SA_JSON_TOKEN_PARTIAL_NUMBER;
const SA_JSON_TOKEN_PARTIAL_STRING = @import("w01.zig").SA_JSON_TOKEN_PARTIAL_STRING;
const SA_JSON_TOKEN_PARTIAL_STRING_ESCAPED_1 = @import("w01.zig").SA_JSON_TOKEN_PARTIAL_STRING_ESCAPED_1;
const SA_JSON_TOKEN_PARTIAL_STRING_ESCAPED_2 = @import("w01.zig").SA_JSON_TOKEN_PARTIAL_STRING_ESCAPED_2;
const SA_JSON_TOKEN_PARTIAL_STRING_ESCAPED_3 = @import("w01.zig").SA_JSON_TOKEN_PARTIAL_STRING_ESCAPED_3;
const SA_JSON_TOKEN_PARTIAL_STRING_ESCAPED_4 = @import("w01.zig").SA_JSON_TOKEN_PARTIAL_STRING_ESCAPED_4;
const SA_JSON_TOKEN_STRING = @import("w01.zig").SA_JSON_TOKEN_STRING;
const SA_JSON_TOKEN_TRUE = @import("w01.zig").SA_JSON_TOKEN_TRUE;
const SA_STD_ERR_ACCESS = @import("w01.zig").SA_STD_ERR_ACCESS;
const SA_STD_ERR_INVALID_ARGUMENT = @import("w01.zig").SA_STD_ERR_INVALID_ARGUMENT;
const SA_STD_ERR_INVALID_HANDLE = @import("w01.zig").SA_STD_ERR_INVALID_HANDLE;
const SA_STD_ERR_NOT_FOUND = @import("w01.zig").SA_STD_ERR_NOT_FOUND;
const SA_STD_ERR_NO_MEMORY = @import("w01.zig").SA_STD_ERR_NO_MEMORY;
const SA_STD_ERR_UNKNOWN = @import("w01.zig").SA_STD_ERR_UNKNOWN;
const SA_STD_OK = @import("w01.zig").SA_STD_OK;
const StreamKind = @import("w01.zig").StreamKind;
const UdpResource = @import("w01.zig").UdpResource;
const dir_entries_free_slots = @import("w02.zig").dir_entries_free_slots;
const dir_entries_handle_tag = @import("w01.zig").dir_entries_handle_tag;
const dir_entries_slots = @import("w02.zig").dir_entries_slots;
const dir_entry_free_slots = @import("w02.zig").dir_entry_free_slots;
const dir_entry_handle_tag = @import("w01.zig").dir_entry_handle_tag;
const dir_entry_slots = @import("w02.zig").dir_entry_slots;
const dynamic_library_free_slots = @import("w02.zig").dynamic_library_free_slots;
const dynamic_library_handle_tag = @import("w01.zig").dynamic_library_handle_tag;
const dynamic_library_mutex = @import("w02.zig").dynamic_library_mutex;
const dynamic_library_slots = @import("w02.zig").dynamic_library_slots;
const finish = @import("w02.zig").finish;
const formatIpv6Segments = @import("w13.zig").formatIpv6Segments;
const json_free_slots = @import("w02.zig").json_free_slots;
const json_handle_tag = @import("w01.zig").json_handle_tag;
const json_mutex = @import("w02.zig").json_mutex;
const json_slots = @import("w02.zig").json_slots;
const json_tokenizer_free_slots = @import("w02.zig").json_tokenizer_free_slots;
const json_tokenizer_handle_tag = @import("w01.zig").json_tokenizer_handle_tag;
const json_tokenizer_mutex = @import("w02.zig").json_tokenizer_mutex;
const json_tokenizer_slots = @import("w02.zig").json_tokenizer_slots;
const json_writer_free_slots = @import("w02.zig").json_writer_free_slots;
const json_writer_handle_tag = @import("w01.zig").json_writer_handle_tag;
const json_writer_mutex = @import("w02.zig").json_writer_mutex;
const json_writer_slots = @import("w02.zig").json_writer_slots;
const metadata_free_slots = @import("w02.zig").metadata_free_slots;
const metadata_handle_tag = @import("w01.zig").metadata_handle_tag;
const metadata_mutex = @import("w02.zig").metadata_mutex;
const metadata_slots = @import("w02.zig").metadata_slots;
const net_addr_free_slots = @import("w02.zig").net_addr_free_slots;
const net_addr_handle_tag = @import("w02.zig").net_addr_handle_tag;
const net_addr_list_free_slots = @import("w02.zig").net_addr_list_free_slots;
const net_addr_list_handle_tag = @import("w02.zig").net_addr_list_handle_tag;
const net_addr_list_mutex = @import("w02.zig").net_addr_list_mutex;
const net_addr_list_slots = @import("w02.zig").net_addr_list_slots;
const net_addr_mutex = @import("w02.zig").net_addr_mutex;
const net_addr_slots = @import("w02.zig").net_addr_slots;
const pathBytes = @import("w02.zig").pathBytes;
const process_free_slots = @import("w02.zig").process_free_slots;
const process_handle_tag = @import("w01.zig").process_handle_tag;
const process_mutex = @import("w02.zig").process_mutex;
const process_slots = @import("w02.zig").process_slots;
const stream_free_slots = @import("w02.zig").stream_free_slots;
const stream_handle_tag = @import("w01.zig").stream_handle_tag;
const stream_mutex = @import("w02.zig").stream_mutex;
const stream_slots = @import("w02.zig").stream_slots;
const taggedSlot = @import("w02.zig").taggedSlot;
const tcp_listener_free_slots = @import("w02.zig").tcp_listener_free_slots;
const tcp_listener_handle_tag = @import("w02.zig").tcp_listener_handle_tag;
const tcp_listener_slots = @import("w02.zig").tcp_listener_slots;
const tcp_mutex = @import("w02.zig").tcp_mutex;
const tcp_stream_free_slots = @import("w02.zig").tcp_stream_free_slots;
const tcp_stream_handle_tag = @import("w02.zig").tcp_stream_handle_tag;
const tcp_stream_slots = @import("w02.zig").tcp_stream_slots;
const udp_free_slots = @import("w02.zig").udp_free_slots;
const udp_handle_tag = @import("w02.zig").udp_handle_tag;
const udp_mutex = @import("w02.zig").udp_mutex;
const udp_slots = @import("w02.zig").udp_slots;

pub fn registerProcess(resource: *ProcessResource) !u64 {
    while (!process_mutex.tryLock()) { std.Thread.yield() catch {}; }
    defer process_mutex.unlock();
    while (process_free_slots.items.len != 0) {
        const idx = process_free_slots.pop().?;
        if (idx >= process_slots.items.len or process_slots.items[idx] != null) continue;
        process_slots.items[idx] = resource;
        return process_handle_tag | @as(u64, @intCast(idx + 1));
    }
    try process_slots.append(resource);
    return process_handle_tag | @as(u64, @intCast(process_slots.items.len));
}

pub fn processSlotLocked(handle: u64) ?usize {
    const idx = taggedSlot(handle, process_handle_tag) orelse return null;
    if (idx >= process_slots.items.len or process_slots.items[idx] == null) return null;
    return idx;
}

pub fn registerStreamKind(file: sio.File, kind: StreamKind) !u64 {
    while (!stream_mutex.tryLock()) { std.Thread.yield() catch {}; }
    defer stream_mutex.unlock();
    while (stream_free_slots.items.len != 0) {
        const idx = stream_free_slots.pop().?;
        if (idx >= stream_slots.items.len or stream_slots.items[idx] != null) continue;
        stream_slots.items[idx] = .{ .file = file, .kind = kind };
        return stream_handle_tag | @as(u64, @intCast(idx + 1));
    }
    try stream_slots.append(.{ .file = file, .kind = kind });
    return stream_handle_tag | @as(u64, @intCast(stream_slots.items.len));
}

pub fn registerStream(file: sio.File) !u64 {
    return registerStreamKind(file, .pipe);
}

pub fn registerFile(file: sio.File) !u64 {
    return registerStreamKind(file, .file);
}

pub fn streamSlotLocked(handle: u64) ?usize {
    const idx = taggedSlot(handle, stream_handle_tag) orelse return null;
    if (idx >= stream_slots.items.len or stream_slots.items[idx] == null) return null;
    return idx;
}

pub fn registerDynamicLibrary(module: std.os.windows.HMODULE) !u64 {
    while (!dynamic_library_mutex.tryLock()) { std.Thread.yield() catch {}; }
    defer dynamic_library_mutex.unlock();
    while (dynamic_library_free_slots.items.len != 0) {
        const idx = dynamic_library_free_slots.pop().?;
        if (idx >= dynamic_library_slots.items.len or dynamic_library_slots.items[idx] != null) continue;
        dynamic_library_slots.items[idx] = .{ .module = module };
        return dynamic_library_handle_tag | @as(u64, @intCast(idx + 1));
    }
    try dynamic_library_slots.append(.{ .module = module });
    return dynamic_library_handle_tag | @as(u64, @intCast(dynamic_library_slots.items.len));
}

pub fn dynamicLibrarySlotLocked(handle: u64) ?usize {
    const idx = taggedSlot(handle, dynamic_library_handle_tag) orelse return null;
    if (idx >= dynamic_library_slots.items.len or dynamic_library_slots.items[idx] == null) return null;
    return idx;
}

pub fn closeDynamicLibrary(handle: u64) i32 {
    while (!dynamic_library_mutex.tryLock()) { std.Thread.yield() catch {}; }
    defer dynamic_library_mutex.unlock();
    const idx = dynamicLibrarySlotLocked(handle) orelse return finish(SA_STD_ERR_INVALID_HANDLE);
    var resource = dynamic_library_slots.items[idx].?;
    resource.close();
    dynamic_library_slots.items[idx] = null;
    dynamic_library_free_slots.append(idx) catch return finish(SA_STD_ERR_NO_MEMORY);
    return finish(SA_STD_OK);
}

pub fn dynamicLibraryErrorStatus() i32 {
    return switch (@intFromEnum(GetLastError())) {
        2, 3, 126 => SA_STD_ERR_NOT_FOUND,
        5 => SA_STD_ERR_ACCESS,
        8 => SA_STD_ERR_NO_MEMORY,
        193 => SA_STD_ERR_INVALID_ARGUMENT,
        else => SA_STD_ERR_UNKNOWN,
    };
}

pub fn registerNetAddr(resource: NetAddrResource) !u64 {
    while (!net_addr_mutex.tryLock()) { std.Thread.yield() catch {}; }
    defer net_addr_mutex.unlock();
    while (net_addr_free_slots.items.len != 0) {
        const idx = net_addr_free_slots.pop().?;
        if (idx >= net_addr_slots.items.len or net_addr_slots.items[idx] != null) continue;
        net_addr_slots.items[idx] = resource;
        return net_addr_handle_tag | @as(u64, @intCast(idx + 1));
    }
    try net_addr_slots.append(resource);
    return net_addr_handle_tag | @as(u64, @intCast(net_addr_slots.items.len));
}

pub fn netAddrSlotLocked(handle: u64) ?usize {
    const idx = taggedSlot(handle, net_addr_handle_tag) orelse return null;
    if (idx >= net_addr_slots.items.len or net_addr_slots.items[idx] == null) return null;
    return idx;
}

pub fn closeNetAddr(handle: u64) i32 {
    while (!net_addr_mutex.tryLock()) { std.Thread.yield() catch {}; }
    defer net_addr_mutex.unlock();
    const idx = netAddrSlotLocked(handle) orelse return finish(SA_STD_ERR_INVALID_HANDLE);
    var resource = net_addr_slots.items[idx].?;
    resource.close();
    net_addr_slots.items[idx] = null;
    net_addr_free_slots.append(idx) catch return finish(SA_STD_ERR_NO_MEMORY);
    return finish(SA_STD_OK);
}

pub fn dnsResolveList(allocator: std.mem.Allocator, host: []const u8, port: u16) ![]std.Io.net.IpAddress {
    // Numeric fast path (no DNS round trip).
    if (std.Io.net.IpAddress.resolve(sio.io(), host, port)) |addr| {
        const out = try allocator.alloc(std.Io.net.IpAddress, 1);
        out[0] = addr;
        return out;
    } else |_| {}
    const hn = try std.Io.net.HostName.init(host);
    var qbuf: [32]std.Io.net.HostName.LookupResult = undefined;
    var queue: std.Io.Queue(std.Io.net.HostName.LookupResult) = .init(&qbuf);
    try std.Io.net.HostName.lookup(hn, sio.io(), &queue, .{ .port = port });
    var list: std.array_list.Managed(std.Io.net.IpAddress) = .init(allocator);
    errdefer list.deinit();
    while (queue.getOne(sio.io())) |result| {
        switch (result) {
            .address => |addr| try list.append(addr),
            .canonical_name => {},
        }
    } else |err| switch (err) {
        error.Closed => {},
        else => |e| return e,
    }
    if (list.items.len == 0) return error.HostLacksNetworkAddresses;
    return try list.toOwnedSlice();
}

pub fn resolveOne(host: []const u8, port: u16) !std.Io.net.IpAddress {
    const addrs = try dnsResolveList(std.heap.page_allocator, host, port);
    defer std.heap.page_allocator.free(addrs);
    return addrs[0];
}

pub fn registerNetAddrList(host: []const u8, port: u16) !u64 {
    const addresses = try dnsResolveList(std.heap.page_allocator, host, port);
    errdefer std.heap.page_allocator.free(addresses);
    while (!net_addr_list_mutex.tryLock()) { std.Thread.yield() catch {}; }
    defer net_addr_list_mutex.unlock();
    while (net_addr_list_free_slots.items.len != 0) {
        const idx = net_addr_list_free_slots.pop().?;
        if (idx >= net_addr_list_slots.items.len or net_addr_list_slots.items[idx] != null) continue;
        net_addr_list_slots.items[idx] = .{ .addresses = addresses };
        return net_addr_list_handle_tag | @as(u64, @intCast(idx + 1));
    }
    try net_addr_list_slots.append(.{ .addresses = addresses });
    return net_addr_list_handle_tag | @as(u64, @intCast(net_addr_list_slots.items.len));
}

pub fn netAddrListSlotLocked(handle: u64) ?usize {
    const idx = taggedSlot(handle, net_addr_list_handle_tag) orelse return null;
    if (idx >= net_addr_list_slots.items.len or net_addr_list_slots.items[idx] == null) return null;
    return idx;
}

pub fn closeNetAddrList(handle: u64) i32 {
    while (!net_addr_list_mutex.tryLock()) { std.Thread.yield() catch {}; }
    defer net_addr_list_mutex.unlock();
    const idx = netAddrListSlotLocked(handle) orelse return finish(SA_STD_ERR_INVALID_HANDLE);
    var resource = net_addr_list_slots.items[idx].?;
    resource.close();
    net_addr_list_slots.items[idx] = null;
    net_addr_list_free_slots.append(idx) catch return finish(SA_STD_ERR_NO_MEMORY);
    return finish(SA_STD_OK);
}

pub fn registerTcpStreamLocked(stream: std.Io.net.Stream) !u64 {
    while (tcp_stream_free_slots.items.len != 0) {
        const idx = tcp_stream_free_slots.pop().?;
        if (idx >= tcp_stream_slots.items.len or tcp_stream_slots.items[idx] != null) continue;
        tcp_stream_slots.items[idx] = .{ .stream = stream };
        return tcp_stream_handle_tag | @as(u64, @intCast(idx + 1));
    }
    try tcp_stream_slots.append(.{ .stream = stream });
    return tcp_stream_handle_tag | @as(u64, @intCast(tcp_stream_slots.items.len));
}

pub fn registerTcpListenerLocked(server: std.Io.net.Server) !u64 {
    while (tcp_listener_free_slots.items.len != 0) {
        const idx = tcp_listener_free_slots.pop().?;
        if (idx >= tcp_listener_slots.items.len or tcp_listener_slots.items[idx] != null) continue;
        tcp_listener_slots.items[idx] = .{ .server = server };
        return tcp_listener_handle_tag | @as(u64, @intCast(idx + 1));
    }
    try tcp_listener_slots.append(.{ .server = server });
    return tcp_listener_handle_tag | @as(u64, @intCast(tcp_listener_slots.items.len));
}

pub fn tcpStreamSlotLocked(handle: u64) ?usize {
    const idx = taggedSlot(handle, tcp_stream_handle_tag) orelse return null;
    if (idx >= tcp_stream_slots.items.len or tcp_stream_slots.items[idx] == null) return null;
    return idx;
}

pub fn tcpListenerSlotLocked(handle: u64) ?usize {
    const idx = taggedSlot(handle, tcp_listener_handle_tag) orelse return null;
    if (idx >= tcp_listener_slots.items.len or tcp_listener_slots.items[idx] == null) return null;
    return idx;
}

pub fn duplicateWinSocket(socket: std.posix.socket_t) !std.posix.socket_t {
    const ws = std.os.windows.ws2_32;
    var info: ws.WSAPROTOCOL_INFOW = undefined;
    if (ws.WSADuplicateSocketW(socket, std.os.windows.GetCurrentProcessId(), &info) != 0) return error.NetworkSubsystemFailed;
    const duplicate = ws.WSASocketW(info.iAddressFamily, info.iSocketType, info.iProtocol, &info, 0, 0);
    if (duplicate == ws.INVALID_SOCKET) return error.NetworkSubsystemFailed;
    return duplicate;
}

pub fn closeTcpHandle(handle: u64) i32 {
    while (!tcp_mutex.tryLock()) { std.Thread.yield() catch {}; }
    defer tcp_mutex.unlock();
    if (tcpStreamSlotLocked(handle)) |idx| {
        var resource = tcp_stream_slots.items[idx].?;
        resource.close();
        tcp_stream_slots.items[idx] = null;
        tcp_stream_free_slots.append(idx) catch return finish(SA_STD_ERR_NO_MEMORY);
        return finish(SA_STD_OK);
    }
    if (tcpListenerSlotLocked(handle)) |idx| {
        var resource = tcp_listener_slots.items[idx].?;
        resource.close();
        tcp_listener_slots.items[idx] = null;
        tcp_listener_free_slots.append(idx) catch return finish(SA_STD_ERR_NO_MEMORY);
        return finish(SA_STD_OK);
    }
    return finish(SA_STD_ERR_INVALID_HANDLE);
}

pub fn addressHostText(address: std.Io.net.IpAddress) ![]u8 {
    switch (address) {
        .ip4 => |v| return try std.fmt.allocPrint(std.heap.page_allocator, "{d}.{d}.{d}.{d}", .{ v.bytes[0], v.bytes[1], v.bytes[2], v.bytes[3] }),
        .ip6 => |v| {
            var segments: [8]u16 = undefined;
            for (0..8) |i| segments[i] = std.mem.readInt(u16, v.bytes[i * 2 ..][0..2], .big);
            var buf: [64]u8 = undefined;
            const text = try formatIpv6Segments(&buf, &segments);
            return try std.heap.page_allocator.dupe(u8, text);
        },
    }
}

pub fn registerSocketAddress(address: std.Io.net.IpAddress) !u64 {
    return registerNetAddr(.{
        .host = try addressHostText(address),
        .family = switch (address) {
            .ip4 => 2,
            .ip6 => 10,
        },
        .port = address.getPort(),
        .scope_id = switch (address) {
            .ip4 => 0,
            .ip6 => |v| v.interface.index,
        },
    });
}

pub fn resolveSocketAddress(host_ptr: ?[*]const u8, host_len: u64, port: u32) !std.Io.net.IpAddress {
    const host = try pathBytes(host_ptr, host_len);
    if (port > std.math.maxInt(u16)) return error.InvalidArgument;
    return resolveOne(host, @intCast(port)) catch return error.InvalidArgument;
}

pub fn registerUdp(resource: UdpResource) !u64 {
    while (!udp_mutex.tryLock()) { std.Thread.yield() catch {}; }
    defer udp_mutex.unlock();
    while (udp_free_slots.items.len != 0) {
        const idx = udp_free_slots.pop().?;
        if (idx >= udp_slots.items.len or udp_slots.items[idx] != null) continue;
        udp_slots.items[idx] = resource;
        return udp_handle_tag | @as(u64, @intCast(idx + 1));
    }
    try udp_slots.append(resource);
    return udp_handle_tag | @as(u64, @intCast(udp_slots.items.len));
}

pub fn udpSlotLocked(handle: u64) ?usize {
    const idx = taggedSlot(handle, udp_handle_tag) orelse return null;
    if (idx >= udp_slots.items.len or udp_slots.items[idx] == null) return null;
    return idx;
}

pub fn closeUdp(handle: u64) i32 {
    while (!udp_mutex.tryLock()) { std.Thread.yield() catch {}; }
    defer udp_mutex.unlock();
    const idx = udpSlotLocked(handle) orelse return finish(SA_STD_ERR_INVALID_HANDLE);
    var resource = udp_slots.items[idx].?;
    resource.close();
    udp_slots.items[idx] = null;
    udp_free_slots.append(idx) catch return finish(SA_STD_ERR_NO_MEMORY);
    return finish(SA_STD_OK);
}

pub fn parseIpv4Ascii(text: []const u8) ?[4]u8 {
    var parts: [4]u8 = undefined;
    var index: usize = 0;
    var part_index: usize = 0;

    while (part_index < 4) : (part_index += 1) {
        if (index >= text.len) return null;
        var value: u32 = 0;
        var digits: usize = 0;
        while (index < text.len and text[index] != '.') : (index += 1) {
            const byte = text[index];
            if (byte < '0' or byte > '9') return null;
            value = value * 10 + @as(u32, byte - '0');
            if (value > 255) return null;
            digits += 1;
        }
        if (digits == 0) return null;
        parts[part_index] = @as(u8, @intCast(value));
        if (part_index < 3) {
            if (index >= text.len or text[index] != '.') return null;
            index += 1;
        }
    }
    if (index != text.len) return null;
    return parts;
}

pub fn parsePortAscii(text: []const u8) ?u16 {
    if (text.len == 0) return null;
    var value: u32 = 0;
    for (text) |byte| {
        if (byte < '0' or byte > '9') return null;
        value = value * 10 + @as(u32, byte - '0');
        if (value > std.math.maxInt(u16)) return null;
    }
    return @as(u16, @intCast(value));
}

pub fn registerMetadata(stat: sio.Stat) !u64 {
    while (!metadata_mutex.tryLock()) { std.Thread.yield() catch {}; }
    defer metadata_mutex.unlock();
    while (metadata_free_slots.items.len != 0) {
        const idx = metadata_free_slots.pop().?;
        if (idx >= metadata_slots.items.len or metadata_slots.items[idx] != null) continue;
        metadata_slots.items[idx] = .{ .stat = stat };
        return metadata_handle_tag | @as(u64, @intCast(idx + 1));
    }
    try metadata_slots.append(.{ .stat = stat });
    return metadata_handle_tag | @as(u64, @intCast(metadata_slots.items.len));
}

pub fn metadataSlotLocked(handle: u64) ?usize {
    const idx = taggedSlot(handle, metadata_handle_tag) orelse return null;
    if (idx >= metadata_slots.items.len or metadata_slots.items[idx] == null) return null;
    return idx;
}

pub fn registerDirEntriesLocked(resource: DirEntriesResource) !u64 {
    while (dir_entries_free_slots.items.len != 0) {
        const idx = dir_entries_free_slots.pop().?;
        if (idx >= dir_entries_slots.items.len or dir_entries_slots.items[idx] != null) continue;
        dir_entries_slots.items[idx] = resource;
        return dir_entries_handle_tag | @as(u64, @intCast(idx + 1));
    }
    try dir_entries_slots.append(resource);
    return dir_entries_handle_tag | @as(u64, @intCast(dir_entries_slots.items.len));
}

pub fn dirEntriesSlotLocked(handle: u64) ?usize {
    const idx = taggedSlot(handle, dir_entries_handle_tag) orelse return null;
    if (idx >= dir_entries_slots.items.len or dir_entries_slots.items[idx] == null) return null;
    return idx;
}

pub fn registerDirEntryLocked(resource: DirEntryResource) !u64 {
    while (dir_entry_free_slots.items.len != 0) {
        const idx = dir_entry_free_slots.pop().?;
        if (idx >= dir_entry_slots.items.len or dir_entry_slots.items[idx] != null) continue;
        dir_entry_slots.items[idx] = resource;
        return dir_entry_handle_tag | @as(u64, @intCast(idx + 1));
    }
    try dir_entry_slots.append(resource);
    return dir_entry_handle_tag | @as(u64, @intCast(dir_entry_slots.items.len));
}

pub fn dirEntrySlotLocked(handle: u64) ?usize {
    const idx = taggedSlot(handle, dir_entry_handle_tag) orelse return null;
    if (idx >= dir_entry_slots.items.len or dir_entry_slots.items[idx] == null) return null;
    return idx;
}

pub fn jsonSlotLocked(handle: u64) ?usize {
    const idx = taggedSlot(handle, json_handle_tag) orelse return null;
    if (idx >= json_slots.items.len or json_slots.items[idx] == null) return null;
    return idx;
}

pub fn registerJsonNode(document: *JsonDocument, value: std.json.Value, retain: bool) !u64 {
    if (retain) document.retain();
    errdefer document.release();
    while (!json_mutex.tryLock()) { std.Thread.yield() catch {}; }
    defer json_mutex.unlock();
    while (json_free_slots.items.len != 0) {
        const idx = json_free_slots.pop().?;
        if (idx >= json_slots.items.len or json_slots.items[idx] != null) continue;
        json_slots.items[idx] = .{ .document = document, .value = value };
        return json_handle_tag | @as(u64, @intCast(idx + 1));
    }
    try json_slots.append(.{ .document = document, .value = value });
    return json_handle_tag | @as(u64, @intCast(json_slots.items.len));
}

pub fn acquireJsonNode(handle: u64) !JsonNode {
    while (!json_mutex.tryLock()) { std.Thread.yield() catch {}; }
    defer json_mutex.unlock();
    const idx = jsonSlotLocked(handle) orelse return error.InvalidHandle;
    const node = json_slots.items[idx].?;
    node.document.retain();
    return node;
}

pub fn closeJsonHandle(handle: u64) i32 {
    while (!json_mutex.tryLock()) { std.Thread.yield() catch {}; }
    const idx = jsonSlotLocked(handle) orelse {
        json_mutex.unlock();
        return finish(SA_STD_ERR_INVALID_HANDLE);
    };
    const node = json_slots.items[idx].?;
    json_slots.items[idx] = null;
    json_free_slots.append(idx) catch {
        json_mutex.unlock();
        node.release();
        return finish(SA_STD_ERR_NO_MEMORY);
    };
    json_mutex.unlock();
    node.release();
    return finish(SA_STD_OK);
}

pub fn jsonWriterSlotLocked(handle: u64) ?usize {
    const idx = taggedSlot(handle, json_writer_handle_tag) orelse return null;
    if (idx >= json_writer_slots.items.len or json_writer_slots.items[idx] == null) return null;
    return idx;
}

pub fn registerJsonWriter(writer: *JsonWriter) !u64 {
    while (!json_writer_mutex.tryLock()) { std.Thread.yield() catch {}; }
    defer json_writer_mutex.unlock();
    while (json_writer_free_slots.items.len != 0) {
        const idx = json_writer_free_slots.pop().?;
        if (idx >= json_writer_slots.items.len or json_writer_slots.items[idx] != null) continue;
        json_writer_slots.items[idx] = writer;
        return json_writer_handle_tag | @as(u64, @intCast(idx + 1));
    }
    try json_writer_slots.append(writer);
    return json_writer_handle_tag | @as(u64, @intCast(json_writer_slots.items.len));
}

pub fn closeJsonWriter(handle: u64) i32 {
    while (!json_writer_mutex.tryLock()) { std.Thread.yield() catch {}; }
    const idx = jsonWriterSlotLocked(handle) orelse {
        json_writer_mutex.unlock();
        return finish(SA_STD_ERR_INVALID_HANDLE);
    };
    const writer = json_writer_slots.items[idx].?;
    json_writer_slots.items[idx] = null;
    json_writer_free_slots.append(idx) catch {
        json_writer_mutex.unlock();
        writer.destroy();
        return finish(SA_STD_ERR_NO_MEMORY);
    };
    json_writer_mutex.unlock();
    writer.destroy();
    return finish(SA_STD_OK);
}

pub fn writerForValue(handle: u64) !*JsonWriter {
    const idx = jsonWriterSlotLocked(handle) orelse return error.InvalidHandle;
    const writer = json_writer_slots.items[idx].?;
    if (writer.finished) return error.InvalidHandle;
    if (writer.complete and writer.depth == 0) return error.InvalidArgument;
    return writer;
}

pub fn markWriterValue(writer: *JsonWriter) void {
    writer.started = true;
    writer.complete = writer.depth == 0;
}

pub fn writerField(writer: *JsonWriter, key: []const u8) !void {
    if (writer.depth == 0) return error.InvalidArgument;
    try writer.stream.objectField(key);
}

pub fn tokenizerSlotLocked(handle: u64) ?usize {
    const idx = taggedSlot(handle, json_tokenizer_handle_tag) orelse return null;
    if (idx >= json_tokenizer_slots.items.len or json_tokenizer_slots.items[idx] == null) return null;
    return idx;
}

pub fn registerTokenizer(tokenizer: *JsonTokenizer) !u64 {
    while (!json_tokenizer_mutex.tryLock()) { std.Thread.yield() catch {}; }
    defer json_tokenizer_mutex.unlock();
    while (json_tokenizer_free_slots.items.len != 0) {
        const idx = json_tokenizer_free_slots.pop().?;
        if (idx >= json_tokenizer_slots.items.len or json_tokenizer_slots.items[idx] != null) continue;
        json_tokenizer_slots.items[idx] = tokenizer;
        return json_tokenizer_handle_tag | @as(u64, @intCast(idx + 1));
    }
    try json_tokenizer_slots.append(tokenizer);
    return json_tokenizer_handle_tag | @as(u64, @intCast(json_tokenizer_slots.items.len));
}

pub fn closeTokenizer(handle: u64) i32 {
    while (!json_tokenizer_mutex.tryLock()) { std.Thread.yield() catch {}; }
    const idx = tokenizerSlotLocked(handle) orelse {
        json_tokenizer_mutex.unlock();
        return finish(SA_STD_ERR_INVALID_HANDLE);
    };
    const tokenizer = json_tokenizer_slots.items[idx].?;
    json_tokenizer_slots.items[idx] = null;
    json_tokenizer_free_slots.append(idx) catch {
        json_tokenizer_mutex.unlock();
        tokenizer.destroy();
        return finish(SA_STD_ERR_NO_MEMORY);
    };
    json_tokenizer_mutex.unlock();
    tokenizer.destroy();
    return finish(SA_STD_OK);
}

pub fn jsonTokenKind(token: std.json.Token) u32 {
    return switch (token) {
        .object_begin => SA_JSON_TOKEN_OBJECT_BEGIN,
        .object_end => SA_JSON_TOKEN_OBJECT_END,
        .array_begin => SA_JSON_TOKEN_ARRAY_BEGIN,
        .array_end => SA_JSON_TOKEN_ARRAY_END,
        .true => SA_JSON_TOKEN_TRUE,
        .false => SA_JSON_TOKEN_FALSE,
        .null => SA_JSON_TOKEN_NULL,
        .number => SA_JSON_TOKEN_NUMBER,
        .partial_number => SA_JSON_TOKEN_PARTIAL_NUMBER,
        .allocated_number => SA_JSON_TOKEN_ALLOCATED_NUMBER,
        .string => SA_JSON_TOKEN_STRING,
        .partial_string => SA_JSON_TOKEN_PARTIAL_STRING,
        .partial_string_escaped_1 => SA_JSON_TOKEN_PARTIAL_STRING_ESCAPED_1,
        .partial_string_escaped_2 => SA_JSON_TOKEN_PARTIAL_STRING_ESCAPED_2,
        .partial_string_escaped_3 => SA_JSON_TOKEN_PARTIAL_STRING_ESCAPED_3,
        .partial_string_escaped_4 => SA_JSON_TOKEN_PARTIAL_STRING_ESCAPED_4,
        .allocated_string => SA_JSON_TOKEN_ALLOCATED_STRING,
        .end_of_document => SA_JSON_TOKEN_END_OF_DOCUMENT,
    };
}

pub fn setTokenizerText(tokenizer: *JsonTokenizer, token: std.json.Token) !void {
    tokenizer.pending_text.clearRetainingCapacity();
    tokenizer.current_text = null;
    switch (token) {
        .number, .partial_number, .string, .partial_string => |slice| {
            try tokenizer.pending_text.appendSlice(slice);
            tokenizer.current_text = tokenizer.pending_text.items;
        },
        .partial_string_escaped_1 => |slice| {
            try tokenizer.pending_text.appendSlice(slice[0..]);
            tokenizer.current_text = tokenizer.pending_text.items;
        },
        .partial_string_escaped_2 => |slice| {
            try tokenizer.pending_text.appendSlice(slice[0..]);
            tokenizer.current_text = tokenizer.pending_text.items;
        },
        .partial_string_escaped_3 => |slice| {
            try tokenizer.pending_text.appendSlice(slice[0..]);
            tokenizer.current_text = tokenizer.pending_text.items;
        },
        .partial_string_escaped_4 => |slice| {
            try tokenizer.pending_text.appendSlice(slice[0..]);
            tokenizer.current_text = tokenizer.pending_text.items;
        },
        .allocated_number, .allocated_string => |slice| {
            defer std.heap.page_allocator.free(slice);
            try tokenizer.pending_text.appendSlice(slice);
            tokenizer.current_text = tokenizer.pending_text.items;
        },
        else => {},
    }
}
