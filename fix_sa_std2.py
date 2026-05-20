import re

with open('src/runtime/sa_std.zig', 'r') as f:
    text = f.read()

# sa_json_free -> Fallible(i32)
text = re.sub(
    r'pub export fn sa_json_free\(node: u64\) i32 \{\n    return sa_std_close\(node\);\n\}',
    r'pub export fn sa_json_free(node: u64) Fallible(i32) {\n    const status = sa_std_close(node);\n    if (status != SA_STD_OK) return fail(i32, status);\n    return ok(i32, 0);\n}',
    text
)

# sa_json_buffer_free -> Fallible(i32)
text = re.sub(
    r'pub export fn sa_json_buffer_free\(buffer: u64\) i32 \{\n    return sa_std_close\(buffer\);\n\}',
    r'pub export fn sa_json_buffer_free(buffer: u64) Fallible(i32) {\n    const status = sa_std_close(buffer);\n    if (status != SA_STD_OK) return fail(i32, status);\n    return ok(i32, 0);\n}',
    text
)

# sa_json_stream_free -> Fallible(i32)
text = re.sub(
    r'pub export fn sa_json_stream_free\(stream: u64\) i32 \{\n    return sa_std_close\(stream\);\n\}',
    r'pub export fn sa_json_stream_free(stream: u64) Fallible(i32) {\n    const status = sa_std_close(stream);\n    if (status != SA_STD_OK) return fail(i32, status);\n    return ok(i32, 0);\n}',
    text
)

# sa_regex_free -> Fallible(i32)
text = re.sub(
    r'pub export fn sa_regex_free\(regex: u64\) i32 \{\n    return sa_std_close\(regex\);\n\}',
    r'pub export fn sa_regex_free(regex: u64) Fallible(i32) {\n    const status = sa_std_close(regex);\n    if (status != SA_STD_OK) return fail(i32, status);\n    return ok(i32, 0);\n}',
    text
)

# sa_regex_match_free -> Fallible(i32)
text = re.sub(
    r'pub export fn sa_regex_match_free\(match: u64\) i32 \{\n    return sa_std_close\(match\);\n\}',
    r'pub export fn sa_regex_match_free(match: u64) Fallible(i32) {\n    const status = sa_std_close(match);\n    if (status != SA_STD_OK) return fail(i32, status);\n    return ok(i32, 0);\n}',
    text
)

# sa_fmt_buffer_free -> Fallible(i32)
text = re.sub(
    r'pub export fn sa_fmt_buffer_free\(handle: u64\) i32 \{\n    return sa_std_close\(handle\);\n\}',
    r'pub export fn sa_fmt_buffer_free(handle: u64) Fallible(i32) {\n    const status = sa_std_close(handle);\n    if (status != SA_STD_OK) return fail(i32, status);\n    return ok(i32, 0);\n}',
    text
)

# sa_net_tcp_listener_bind -> Fallible(u64)
text = re.sub(
    r'pub export fn sa_net_tcp_listener_bind\(host_ptr: \?\[\*\]const u8, host_len: u64, port: u16\) i32 \{\n    var handle: u64 = 0;\n    const status = sa_std_net_tcp_listen\(host_ptr, host_len, port, &handle, null\);\n    if \(status != SA_STD_OK\) return status;\n    return @as\(i32, @intCast\(handle\)\);\n\}',
    r'pub export fn sa_net_tcp_listener_bind(host_ptr: ?[*]const u8, host_len: u64, port: u16) Fallible(u64) {\n    var handle: u64 = 0;\n    const status = sa_std_net_tcp_listen(host_ptr, host_len, port, &handle, null);\n    if (status != SA_STD_OK) return fail(u64, status);\n    return ok(u64, handle);\n}',
    text
)

# sa_net_tcp_listener_accept -> Fallible(u64)
text = re.sub(
    r'pub export fn sa_net_tcp_listener_accept\(listener: u64\) i32 \{\n    var handle: u64 = 0;\n    const status = sa_std_net_tcp_accept\(listener, &handle\);\n    if \(status != SA_STD_OK\) return status;\n    return @as\(i32, @intCast\(handle\)\);\n\}',
    r'pub export fn sa_net_tcp_listener_accept(listener: u64) Fallible(u64) {\n    var handle: u64 = 0;\n    const status = sa_std_net_tcp_accept(listener, &handle);\n    if (status != SA_STD_OK) return fail(u64, status);\n    return ok(u64, handle);\n}',
    text
)

# sa_net_tcp_listener_local_addr -> Fallible(u64)
text = re.sub(
    r'pub export fn sa_net_tcp_listener_local_addr\(listener: u64\) i32 \{\n    registry_mutex\.lock\(\);\n    defer registry_mutex\.unlock\(\);\n    const resource = getResourceLocked\(listener\) orelse return finish\(SA_STD_ERR_INVALID_HANDLE\);\n    return switch \(resource\.\*\) \{\n        \.tcp_listener => \|server\| \{\n            var net_addr = NetAddrHandle\.init\(std\.heap\.page_allocator, server\.listen_address\) catch \|err\| return finishErr\(err\);\n            const handle = registerResourceLocked\(\{\n \.net_addr = net_addr \}\) catch \|err\| \{\n                net_addr\.deinit\(\);\n                return finishErr\(err\);\n            \};\n            return finish\(@as\(i32, @intCast\(handle\)\)\);\n        \},\n        else => finish\(SA_STD_ERR_INVALID_HANDLE\),\n    \};\n\}',
    r'pub export fn sa_net_tcp_listener_local_addr(listener: u64) Fallible(u64) {\n    registry_mutex.lock();\n    defer registry_mutex.unlock();\n    const resource = getResourceLocked(listener) orelse return fail(u64, SA_STD_ERR_INVALID_HANDLE);\n    return switch (resource.*) {\n        .tcp_listener => |server| {\n            var net_addr = NetAddrHandle.init(std.heap.page_allocator, server.listen_address) catch return fail(u64, SA_STD_ERR_NO_MEMORY);\n            const handle = registerResourceLocked(.{ .net_addr = net_addr }) catch {\n                net_addr.deinit();\n                return fail(u64, SA_STD_ERR_NO_MEMORY);\n            };\n            return ok(u64, handle);\n        },\n        else => fail(u64, SA_STD_ERR_INVALID_HANDLE),\n    };\n}',
    text
)

# sa_net_tcp_connect -> Fallible(u64)
text = re.sub(
    r'pub export fn sa_net_tcp_connect\(host_ptr: \?\[\*\]const u8, host_len: u64, port: u16\) i32 \{\n    var handle: u64 = 0;\n    const status = sa_std_net_tcp_connect\(host_ptr, host_len, port, &handle\);\n    if \(status != SA_STD_OK\) return status;\n    return @as\(i32, @intCast\(handle\)\);\n\}',
    r'pub export fn sa_net_tcp_connect(host_ptr: ?[*]const u8, host_len: u64, port: u16) Fallible(u64) {\n    var handle: u64 = 0;\n    const status = sa_std_net_tcp_connect(host_ptr, host_len, port, &handle);\n    if (status != SA_STD_OK) return fail(u64, status);\n    return ok(u64, handle);\n}',
    text
)

# sa_net_tcp_stream_read -> Fallible(u64)
text = re.sub(
    r'pub export fn sa_net_tcp_stream_read\(stream: u64, out: \?\[\*\]u8, cap: u64\) i32 \{ return sa_std_read\(stream, out, cap, null\); \}',
    r'pub export fn sa_net_tcp_stream_read(stream: u64, out: ?[*]u8, cap: u64) Fallible(u64) { var read: u64 = 0; const status = sa_std_read(stream, out, cap, &read); if (status != SA_STD_OK) return fail(u64, status); return ok(u64, read); }',
    text
)

# sa_net_tcp_stream_write_all -> Fallible(i32)
text = re.sub(
    r'pub export fn sa_net_tcp_stream_write_all\(stream: u64, out: \?\[\*\]const u8, len: u64\) i32 \{ return sa_io_write_all\(stream, out, len\); \}',
    r'pub export fn sa_net_tcp_stream_write_all(stream: u64, out: ?[*]const u8, len: u64) Fallible(i32) { const status = sa_io_write_all(stream, out, len); if (status != SA_STD_OK) return fail(i32, status); return ok(i32, 0); }',
    text
)

# sa_net_tcp_listener_close -> Fallible(i32)
text = re.sub(
    r'pub export fn sa_net_tcp_listener_close\(listener: u64\) i32 \{ return sa_std_close\(listener\); \}',
    r'pub export fn sa_net_tcp_listener_close(listener: u64) Fallible(i32) {\n    const status = sa_std_close(listener);\n    if (status != SA_STD_OK) return fail(i32, status);\n    return ok(i32, 0);\n}',
    text
)

# sa_net_tcp_stream_close -> Fallible(i32)
text = re.sub(
    r'pub export fn sa_net_tcp_stream_close\(stream: u64\) i32 \{ return sa_std_close\(stream\); \}',
    r'pub export fn sa_net_tcp_stream_close(stream: u64) Fallible(i32) {\n    const status = sa_std_close(stream);\n    if (status != SA_STD_OK) return fail(i32, status);\n    return ok(i32, 0);\n}',
    text
)

# sa_net_addr_free -> Fallible(i32)
text = re.sub(
    r'pub export fn sa_net_addr_free\(addr: u64\) i32 \{ return sa_std_close\(addr\); \}',
    r'pub export fn sa_net_addr_free(addr: u64) Fallible(i32) {\n    const status = sa_std_close(addr);\n    if (status != SA_STD_OK) return fail(i32, status);\n    return ok(i32, 0);\n}',
    text
)

# sa_net_addr_host
text = re.sub(
    r'pub export fn sa_net_addr_host\(addr: u64\) \?\[\*\]const u8 \{',
    r'pub export fn sa_net_addr_host(addr: u64) ?[*]const u8 {',
    text
)

# Check for JSON stringify since we saw that could be an issue too?
# We didn't change sa_json_stringify here. Is it needed?
# L_STRINGIFY in tests uses sa_json_stringify. But it didn't crash. Let's just write.
with open('src/runtime/sa_std.zig', 'w') as f:
    f.write(text)

