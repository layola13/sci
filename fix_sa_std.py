import re

with open('src/runtime/sa_std.zig', 'r') as f:
    text = f.read()

# Make finish and finishErr return Fallible(i32)
text = re.sub(
    r'fn finish\(status: i32\) i32 \{.*?return status;\n\}',
    'fn finish(status: i32) Fallible(i32) {\n    last_error = status;\n    return .{ .status = status, .value = 0 };\n}',
    text, flags=re.DOTALL
)

text = re.sub(
    r'fn finishErr\(err: anyerror\) i32 \{.*?return finish\(mapError\(err\)\);\n\}',
    'fn finishErr(err: anyerror) Fallible(i32) {\n    return finish(mapError(err));\n}',
    text, flags=re.DOTALL
)

# Functions that return ^ptr! or u64! in SA, but i32 in Zig!
# They need to return Fallible(u64) and their body needs to be adjusted.
# Let's fix only the ones breaking the tests right now!
# The ones breaking tests:
# sa_fmt_buffer_free -> Fallible(i32)
# sa_net_tcp_listener_bind -> Fallible(u64)
# sa_net_tcp_listener_local_addr -> Fallible(u64)
# sa_net_tcp_listener_close -> Fallible(i32)
# sa_net_addr_host -> Not fallible, returns ptr
# sa_net_addr_host_len -> u64
# sa_net_addr_port -> u16
# sa_net_addr_family -> u32
# sa_net_addr_free -> Fallible(i32)

text = re.sub(
    r'pub export fn sa_fmt_buffer_free\(handle: u64\) i32 \{',
    r'pub export fn sa_fmt_buffer_free(handle: u64) Fallible(i32) {',
    text
)

text = re.sub(
    r'pub export fn sa_net_tcp_listener_close\(listener: u64\) i32 \{ return sa_std_close\(listener\); \}',
    r'pub export fn sa_net_tcp_listener_close(listener: u64) Fallible(i32) { return sa_std_close(listener); }',
    text
)

text = re.sub(
    r'pub export fn sa_net_tcp_stream_close\(stream: u64\) i32 \{ return sa_std_close\(stream\); \}',
    r'pub export fn sa_net_tcp_stream_close(stream: u64) Fallible(i32) { return sa_std_close(stream); }',
    text
)

text = re.sub(
    r'pub export fn sa_net_addr_free\(addr: u64\) i32 \{ return sa_std_close\(addr\); \}',
    r'pub export fn sa_net_addr_free(addr: u64) Fallible(i32) { return sa_std_close(addr); }',
    text
)

# sa_net_tcp_listener_bind -> Fallible(u64)
text = re.sub(
    r'pub export fn sa_net_tcp_listener_bind\(host_ptr: \?\[\*\]const u8, host_len: u64, port: u16\) i32 \{\n    var handle: u64 = 0;\n    const status = sa_std_net_tcp_listen\(host_ptr, host_len, port, &handle, null\);\n    if \(status != SA_STD_OK\) return status;\n    return @as\(i32, @intCast\(handle\)\);\n\}',
    r'pub export fn sa_net_tcp_listener_bind(host_ptr: ?[*]const u8, host_len: u64, port: u16) Fallible(u64) {\n    var handle: u64 = 0;\n    const status = sa_std_net_tcp_listen(host_ptr, host_len, port, &handle, null);\n    if (status != SA_STD_OK) return fail(u64, status);\n    return ok(u64, handle);\n}',
    text
)

# sa_net_tcp_listener_local_addr -> Fallible(u64)
text = re.sub(
    r'pub export fn sa_net_tcp_listener_local_addr\(listener: u64\) i32 \{',
    r'pub export fn sa_net_tcp_listener_local_addr(listener: u64) Fallible(u64) {',
    text
)
text = re.sub(
    r'return finish\(@as\(i32, @intCast\(handle\)\)\);',
    r'return ok(u64, handle);',
    text
)

# sa_net_tcp_connect -> Fallible(u64)
text = re.sub(
    r'pub export fn sa_net_tcp_connect\(host_ptr: \?\[\*\]const u8, host_len: u64, port: u16\) i32 \{\n    var handle: u64 = 0;\n    const status = sa_std_net_tcp_connect\(host_ptr, host_len, port, &handle\);\n    if \(status != SA_STD_OK\) return status;\n    return @as\(i32, @intCast\(handle\)\);\n\}',
    r'pub export fn sa_net_tcp_connect(host_ptr: ?[*]const u8, host_len: u64, port: u16) Fallible(u64) {\n    var handle: u64 = 0;\n    const status = sa_std_net_tcp_connect(host_ptr, host_len, port, &handle);\n    if (status != SA_STD_OK) return fail(u64, status);\n    return ok(u64, handle);\n}',
    text
)

# sa_net_tcp_listener_accept -> Fallible(u64)
text = re.sub(
    r'pub export fn sa_net_tcp_listener_accept\(listener: u64\) i32 \{\n    var handle: u64 = 0;\n    const status = sa_std_net_tcp_accept\(listener, &handle\);\n    if \(status != SA_STD_OK\) return status;\n    return @as\(i32, @intCast\(handle\)\);\n\}',
    r'pub export fn sa_net_tcp_listener_accept(listener: u64) Fallible(u64) {\n    var handle: u64 = 0;\n    const status = sa_std_net_tcp_accept(listener, &handle);\n    if (status != SA_STD_OK) return fail(u64, status);\n    return ok(u64, handle);\n}',
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

# sa_net_addr_host returns ptr (u64 in Zig)
text = re.sub(
    r'pub export fn sa_net_addr_host\(addr: u64\) \?\[\*\]const u8 \{',
    r'pub export fn sa_net_addr_host(addr: u64) ?[*]const u8 {',
    text
)


with open('src/runtime/sa_std.zig', 'w') as f:
    f.write(text)
