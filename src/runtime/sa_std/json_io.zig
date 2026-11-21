const std = @import("std");
const Fallible = @import("../sa_std.zig").Fallible;
const JsonScannerHandle = @import("../sa_std.zig").JsonScannerHandle;
const JsonStreamHandle = @import("../sa_std.zig").JsonStreamHandle;
const JsonWriterHandle = @import("../sa_std.zig").JsonWriterHandle;
const SA_JSON_TOKEN_INVALID = @import("../sa_std.zig").SA_JSON_TOKEN_INVALID;
const SA_JSON_WHITESPACE_INDENT_1 = @import("../sa_std.zig").SA_JSON_WHITESPACE_INDENT_1;
const SA_JSON_WHITESPACE_INDENT_2 = @import("../sa_std.zig").SA_JSON_WHITESPACE_INDENT_2;
const SA_JSON_WHITESPACE_INDENT_3 = @import("../sa_std.zig").SA_JSON_WHITESPACE_INDENT_3;
const SA_JSON_WHITESPACE_INDENT_4 = @import("../sa_std.zig").SA_JSON_WHITESPACE_INDENT_4;
const SA_JSON_WHITESPACE_INDENT_8 = @import("../sa_std.zig").SA_JSON_WHITESPACE_INDENT_8;
const SA_JSON_WHITESPACE_INDENT_TAB = @import("../sa_std.zig").SA_JSON_WHITESPACE_INDENT_TAB;
const SA_JSON_WHITESPACE_MINIFIED = @import("../sa_std.zig").SA_JSON_WHITESPACE_MINIFIED;
const SA_STD_ERR_INVALID_ARGUMENT = @import("../sa_std.zig").SA_STD_ERR_INVALID_ARGUMENT;
const SA_STD_ERR_INVALID_HANDLE = @import("../sa_std.zig").SA_STD_ERR_INVALID_HANDLE;
const SA_STD_ERR_TRUNCATED = @import("../sa_std.zig").SA_STD_ERR_TRUNCATED;
const SA_STD_OK = @import("../sa_std.zig").SA_STD_OK;
const SaJsonToken = @import("../sa_std.zig").SaJsonToken;
const acquireJsonNode = @import("../sa_std.zig").acquireJsonNode;
const acquireJsonWriterForWrite = @import("../sa_std.zig").acquireJsonWriterForWrite;
const constBytes = @import("../sa_std.zig").constBytes;
const fail = @import("../sa_std.zig").fail;
const finish = @import("../sa_std.zig").finish;
const finishErr = @import("../sa_std.zig").finishErr;
const getResourceLocked = @import("../sa_std.zig").getResourceLocked;
const jsonScannerFeed = @import("../sa_std.zig").jsonScannerFeed;
const jsonWriterObjectFieldLocked = @import("../sa_std.zig").jsonWriterObjectFieldLocked;
const markJsonWriterValueComplete = @import("../sa_std.zig").markJsonWriterValueComplete;
const ok = @import("../sa_std.zig").ok;
const registerResource = @import("../sa_std.zig").registerResource;
const registerResourceLocked = @import("../sa_std.zig").registerResourceLocked;
const sa_std = @import("../sa_std.zig");
const sa_std_close = @import("../sa_std.zig").sa_std_close;
const tokenTextBytes = @import("../sa_std.zig").tokenTextBytes;
const tokenTextSlice = @import("../sa_std.zig").tokenTextSlice;
const tokenTypeOf = @import("../sa_std.zig").tokenTypeOf;

pub export fn sa_json_scanner_new(out_handle: ?*u64) i32 {
    const handle_ptr = out_handle orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    handle_ptr.* = 0;
    const scanner_handle = JsonScannerHandle.init(std.heap.page_allocator) catch |err| return finishErr(err);
    const handle = registerResource(.{ .json_scanner = scanner_handle }) catch |err| {
        scanner_handle.destroy();
        return finishErr(err);
    };
    handle_ptr.* = handle;
    return finish(SA_STD_OK);
}

pub export fn sa_json_scanner_feed(scanner: u64, input: ?[*]const u8, len: u64) i32 {
    while (!sa_std.registry_mutex.tryLock()) {
        std.Thread.yield() catch {};
    }
    defer sa_std.registry_mutex.unlock();
    const resource = getResourceLocked(scanner) orelse return finish(SA_STD_ERR_INVALID_HANDLE);
    const scanner_handle = switch (resource.*) {
        .json_scanner => |handle| handle,
        else => return finish(SA_STD_ERR_INVALID_HANDLE),
    };
    const bytes = constBytes(input, len) catch |err| return finishErr(err);
    jsonScannerFeed(scanner_handle, bytes, false) catch |err| return finishErr(err);
    return finish(SA_STD_OK);
}

pub export fn sa_json_scanner_end_input(scanner: u64) i32 {
    while (!sa_std.registry_mutex.tryLock()) {
        std.Thread.yield() catch {};
    }
    defer sa_std.registry_mutex.unlock();
    const resource = getResourceLocked(scanner) orelse return finish(SA_STD_ERR_INVALID_HANDLE);
    const scanner_handle = switch (resource.*) {
        .json_scanner => |handle| handle,
        else => return finish(SA_STD_ERR_INVALID_HANDLE),
    };
    scanner_handle.scanner.endInput();
    return finish(SA_STD_OK);
}

pub export fn sa_json_scanner_next(scanner: u64, out_token: ?*SaJsonToken) i32 {
    const token_ptr = out_token orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    token_ptr.* = .{ .kind = SA_JSON_TOKEN_INVALID, .text_ptr = null, .text_len = 0 };
    while (!sa_std.registry_mutex.tryLock()) {
        std.Thread.yield() catch {};
    }
    defer sa_std.registry_mutex.unlock();
    const resource = getResourceLocked(scanner) orelse return finish(SA_STD_ERR_INVALID_HANDLE);
    const scanner_handle = switch (resource.*) {
        .json_scanner => |handle| handle,
        else => return finish(SA_STD_ERR_INVALID_HANDLE),
    };

    scanner_handle.pending_text.clearRetainingCapacity();
    const token = scanner_handle.scanner.next() catch |err| switch (err) {
        error.BufferUnderrun => return finish(SA_STD_ERR_TRUNCATED),
        else => return finishErr(err),
    };
    token_ptr.kind = tokenTypeOf(token);
    if (tokenTextSlice(token)) |text| {
        token_ptr.text_ptr = text.ptr;
        token_ptr.text_len = @as(u64, @intCast(text.len));
    } else switch (token) {
        .allocated_number, .allocated_string, .partial_string_escaped_1, .partial_string_escaped_2, .partial_string_escaped_3, .partial_string_escaped_4 => {
            const text = tokenTextBytes(scanner_handle, token) catch |err| return finishErr(err);
            token_ptr.text_ptr = text.ptr;
            token_ptr.text_len = @as(u64, @intCast(text.len));
        },
        else => {},
    }
    return finish(SA_STD_OK);
}

pub export fn sa_json_scanner_free(scanner: u64) i32 {
    return sa_std_close(scanner);
}

pub export fn sa_json_stream_new(json_bytes: ?[*]const u8, len: u64) u64 {
    const input = constBytes(json_bytes, len) catch return 0;
    const stream_handle = JsonStreamHandle.init(std.heap.page_allocator, input) catch return 0;
    return registerResource(.{ .json_stream = stream_handle }) catch |err| {
        stream_handle.deinit();
        _ = finishErr(err);
        return 0;
    };
}

pub export fn sa_json_stream_next(stream: u64) u32 {
    while (!sa_std.registry_mutex.tryLock()) {
        std.Thread.yield() catch {};
    }
    defer sa_std.registry_mutex.unlock();
    const resource = getResourceLocked(stream) orelse return SA_JSON_TOKEN_INVALID;
    const stream_handle = switch (resource.*) {
        .json_stream => |handle| handle,
        else => return SA_JSON_TOKEN_INVALID,
    };
    stream_handle.scanner.pending_text.clearRetainingCapacity();
    const token = stream_handle.scanner.scanner.next() catch return SA_JSON_TOKEN_INVALID;
    stream_handle.last_token = tokenTypeOf(token);
    if (tokenTextSlice(token)) |text| {
        stream_handle.scanner.current_text = text;
    } else switch (token) {
        .allocated_number, .allocated_string, .partial_string_escaped_1, .partial_string_escaped_2, .partial_string_escaped_3, .partial_string_escaped_4 => {
            const text = tokenTextBytes(stream_handle.scanner, token) catch return SA_JSON_TOKEN_INVALID;
            stream_handle.scanner.current_text = text;
        },
        else => {
            stream_handle.scanner.current_text = null;
        },
    }
    stream_handle.scanner.current_token = stream_handle.last_token;
    return stream_handle.last_token;
}

pub export fn sa_json_stream_get_slice_ptr(stream: u64) ?[*]const u8 {
    while (!sa_std.registry_mutex.tryLock()) {
        std.Thread.yield() catch {};
    }
    defer sa_std.registry_mutex.unlock();
    const resource = getResourceLocked(stream) orelse return null;
    const stream_handle = switch (resource.*) {
        .json_stream => |handle| handle,
        else => return null,
    };
    return if (stream_handle.scanner.current_text) |text| text.ptr else null;
}

pub export fn sa_json_stream_get_slice_len(stream: u64) u64 {
    while (!sa_std.registry_mutex.tryLock()) {
        std.Thread.yield() catch {};
    }
    defer sa_std.registry_mutex.unlock();
    const resource = getResourceLocked(stream) orelse return 0;
    const stream_handle = switch (resource.*) {
        .json_stream => |handle| handle,
        else => return 0,
    };
    return if (stream_handle.scanner.current_text) |text| @as(u64, @intCast(text.len)) else 0;
}

pub export fn sa_json_stream_free(stream: u64) Fallible(i32) {
    const status = sa_std_close(stream);
    if (status != SA_STD_OK) return fail(i32, status);
    return ok(i32, 0);
}

pub export fn sa_json_writer_free(writer: u64) i32 {
    return sa_std_close(writer);
}

pub export fn sa_json_writer_new(whitespace: u32, emit_null_optional_fields: u8, emit_strings_as_arrays: u8, escape_unicode: u8, emit_nonportable_numbers_as_strings: u8, out_handle: ?*u64) i32 {
    const handle_ptr = out_handle orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    handle_ptr.* = 0;
    const options: std.json.Stringify.Options = .{
        .whitespace = switch (whitespace) {
            SA_JSON_WHITESPACE_MINIFIED => .minified,
            SA_JSON_WHITESPACE_INDENT_1 => .indent_1,
            SA_JSON_WHITESPACE_INDENT_2 => .indent_2,
            SA_JSON_WHITESPACE_INDENT_3 => .indent_3,
            SA_JSON_WHITESPACE_INDENT_4 => .indent_4,
            SA_JSON_WHITESPACE_INDENT_8 => .indent_8,
            SA_JSON_WHITESPACE_INDENT_TAB => .indent_tab,
            else => return finish(SA_STD_ERR_INVALID_ARGUMENT),
        },
        .emit_null_optional_fields = emit_null_optional_fields != 0,
        .emit_strings_as_arrays = emit_strings_as_arrays != 0,
        .escape_unicode = escape_unicode != 0,
        .emit_nonportable_numbers_as_strings = emit_nonportable_numbers_as_strings != 0,
    };
    const writer_handle = JsonWriterHandle.init(std.heap.page_allocator, options) catch |err| return finishErr(err);
    const handle = registerResource(.{ .json_writer = writer_handle }) catch |err| {
        writer_handle.deinit();
        return finishErr(err);
    };
    handle_ptr.* = handle;
    return finish(SA_STD_OK);
}

pub export fn sa_json_writer_begin_object(writer: u64) i32 {
    while (!sa_std.registry_mutex.tryLock()) {
        std.Thread.yield() catch {};
    }
    defer sa_std.registry_mutex.unlock();
    const resource = getResourceLocked(writer) orelse return finish(SA_STD_ERR_INVALID_HANDLE);
    const writer_handle = switch (resource.*) {
        .json_writer => |handle| handle,
        else => return finish(SA_STD_ERR_INVALID_HANDLE),
    };
    if (writer_handle.result_buffer != null) return finish(SA_STD_ERR_INVALID_HANDLE);
    if (writer_handle.root_value_complete and writer_handle.open_depth == 0) return finish(SA_STD_ERR_INVALID_ARGUMENT);
    writer_handle.stream.beginObject() catch |err| return finishErr(err);
    writer_handle.open_depth += 1;
    writer_handle.root_value_started = true;
    writer_handle.root_value_complete = false;
    return finish(SA_STD_OK);
}

pub export fn sa_json_writer_end_object(writer: u64) i32 {
    while (!sa_std.registry_mutex.tryLock()) {
        std.Thread.yield() catch {};
    }
    defer sa_std.registry_mutex.unlock();
    const resource = getResourceLocked(writer) orelse return finish(SA_STD_ERR_INVALID_HANDLE);
    const writer_handle = switch (resource.*) {
        .json_writer => |handle| handle,
        else => return finish(SA_STD_ERR_INVALID_HANDLE),
    };
    if (writer_handle.result_buffer != null) return finish(SA_STD_ERR_INVALID_HANDLE);
    if (writer_handle.open_depth == 0) return finish(SA_STD_ERR_INVALID_ARGUMENT);
    writer_handle.stream.endObject() catch |err| return finishErr(err);
    writer_handle.open_depth -= 1;
    writer_handle.root_value_complete = writer_handle.open_depth == 0;
    return finish(SA_STD_OK);
}

pub export fn sa_json_writer_begin_array(writer: u64) i32 {
    while (!sa_std.registry_mutex.tryLock()) {
        std.Thread.yield() catch {};
    }
    defer sa_std.registry_mutex.unlock();
    const resource = getResourceLocked(writer) orelse return finish(SA_STD_ERR_INVALID_HANDLE);
    const writer_handle = switch (resource.*) {
        .json_writer => |handle| handle,
        else => return finish(SA_STD_ERR_INVALID_HANDLE),
    };
    if (writer_handle.result_buffer != null) return finish(SA_STD_ERR_INVALID_HANDLE);
    if (writer_handle.root_value_complete and writer_handle.open_depth == 0) return finish(SA_STD_ERR_INVALID_ARGUMENT);
    writer_handle.stream.beginArray() catch |err| return finishErr(err);
    writer_handle.open_depth += 1;
    writer_handle.root_value_started = true;
    writer_handle.root_value_complete = false;
    return finish(SA_STD_OK);
}

pub export fn sa_json_writer_end_array(writer: u64) i32 {
    while (!sa_std.registry_mutex.tryLock()) {
        std.Thread.yield() catch {};
    }
    defer sa_std.registry_mutex.unlock();
    const resource = getResourceLocked(writer) orelse return finish(SA_STD_ERR_INVALID_HANDLE);
    const writer_handle = switch (resource.*) {
        .json_writer => |handle| handle,
        else => return finish(SA_STD_ERR_INVALID_HANDLE),
    };
    if (writer_handle.result_buffer != null) return finish(SA_STD_ERR_INVALID_HANDLE);
    if (writer_handle.open_depth == 0) return finish(SA_STD_ERR_INVALID_ARGUMENT);
    writer_handle.stream.endArray() catch |err| return finishErr(err);
    writer_handle.open_depth -= 1;
    writer_handle.root_value_complete = writer_handle.open_depth == 0;
    return finish(SA_STD_OK);
}

pub export fn sa_json_writer_object_field(writer: u64, key: ?[*]const u8, key_len: u64) i32 {
    while (!sa_std.registry_mutex.tryLock()) {
        std.Thread.yield() catch {};
    }
    defer sa_std.registry_mutex.unlock();
    const field = constBytes(key, key_len) catch |err| return finishErr(err);
    const writer_handle = acquireJsonWriterForWrite(writer) catch |err| return finishErr(err);
    jsonWriterObjectFieldLocked(writer_handle, field) catch |err| return finishErr(err);
    return finish(SA_STD_OK);
}

pub export fn sa_json_writer_field_string(writer: u64, key: ?[*]const u8, key_len: u64, data: ?[*]const u8, len: u64) i32 {
    const field = constBytes(key, key_len) catch |err| return finishErr(err);
    const bytes = constBytes(data, len) catch |err| return finishErr(err);
    while (!sa_std.registry_mutex.tryLock()) {
        std.Thread.yield() catch {};
    }
    defer sa_std.registry_mutex.unlock();
    const writer_handle = acquireJsonWriterForWrite(writer) catch |err| return finishErr(err);
    jsonWriterObjectFieldLocked(writer_handle, field) catch |err| return finishErr(err);
    writer_handle.stream.write(bytes) catch |err| return finishErr(err);
    markJsonWriterValueComplete(writer_handle);
    return finish(SA_STD_OK);
}

pub export fn sa_json_writer_field_bool(writer: u64, key: ?[*]const u8, key_len: u64, value: u8) i32 {
    const field = constBytes(key, key_len) catch |err| return finishErr(err);
    while (!sa_std.registry_mutex.tryLock()) {
        std.Thread.yield() catch {};
    }
    defer sa_std.registry_mutex.unlock();
    const writer_handle = acquireJsonWriterForWrite(writer) catch |err| return finishErr(err);
    jsonWriterObjectFieldLocked(writer_handle, field) catch |err| return finishErr(err);
    writer_handle.stream.write(value != 0) catch |err| return finishErr(err);
    markJsonWriterValueComplete(writer_handle);
    return finish(SA_STD_OK);
}

pub export fn sa_json_writer_field_i64(writer: u64, key: ?[*]const u8, key_len: u64, value: i64) i32 {
    const field = constBytes(key, key_len) catch |err| return finishErr(err);
    while (!sa_std.registry_mutex.tryLock()) {
        std.Thread.yield() catch {};
    }
    defer sa_std.registry_mutex.unlock();
    const writer_handle = acquireJsonWriterForWrite(writer) catch |err| return finishErr(err);
    jsonWriterObjectFieldLocked(writer_handle, field) catch |err| return finishErr(err);
    writer_handle.stream.write(value) catch |err| return finishErr(err);
    markJsonWriterValueComplete(writer_handle);
    return finish(SA_STD_OK);
}

pub export fn sa_json_writer_field_f64(writer: u64, key: ?[*]const u8, key_len: u64, value: f64) i32 {
    const field = constBytes(key, key_len) catch |err| return finishErr(err);
    while (!sa_std.registry_mutex.tryLock()) {
        std.Thread.yield() catch {};
    }
    defer sa_std.registry_mutex.unlock();
    const writer_handle = acquireJsonWriterForWrite(writer) catch |err| return finishErr(err);
    jsonWriterObjectFieldLocked(writer_handle, field) catch |err| return finishErr(err);
    writer_handle.stream.write(value) catch |err| return finishErr(err);
    markJsonWriterValueComplete(writer_handle);
    return finish(SA_STD_OK);
}

pub export fn sa_json_writer_field_null(writer: u64, key: ?[*]const u8, key_len: u64) i32 {
    const field = constBytes(key, key_len) catch |err| return finishErr(err);
    while (!sa_std.registry_mutex.tryLock()) {
        std.Thread.yield() catch {};
    }
    defer sa_std.registry_mutex.unlock();
    const writer_handle = acquireJsonWriterForWrite(writer) catch |err| return finishErr(err);
    jsonWriterObjectFieldLocked(writer_handle, field) catch |err| return finishErr(err);
    writer_handle.stream.write(null) catch |err| return finishErr(err);
    markJsonWriterValueComplete(writer_handle);
    return finish(SA_STD_OK);
}

pub export fn sa_json_writer_field_node(writer: u64, key: ?[*]const u8, key_len: u64, node: u64) i32 {
    const field = constBytes(key, key_len) catch |err| return finishErr(err);
    var node_value = acquireJsonNode(node) catch |err| return finishErr(err);
    defer node_value.deinit();
    while (!sa_std.registry_mutex.tryLock()) {
        std.Thread.yield() catch {};
    }
    defer sa_std.registry_mutex.unlock();
    const writer_handle = acquireJsonWriterForWrite(writer) catch |err| return finishErr(err);
    jsonWriterObjectFieldLocked(writer_handle, field) catch |err| return finishErr(err);
    writer_handle.stream.write(node_value.value) catch |err| return finishErr(err);
    markJsonWriterValueComplete(writer_handle);
    return finish(SA_STD_OK);
}

pub export fn sa_json_writer_write_bool(writer: u64, value: u8) i32 {
    while (!sa_std.registry_mutex.tryLock()) {
        std.Thread.yield() catch {};
    }
    defer sa_std.registry_mutex.unlock();
    const resource = getResourceLocked(writer) orelse return finish(SA_STD_ERR_INVALID_HANDLE);
    const writer_handle = switch (resource.*) {
        .json_writer => |handle| handle,
        else => return finish(SA_STD_ERR_INVALID_HANDLE),
    };
    if (writer_handle.result_buffer != null) return finish(SA_STD_ERR_INVALID_HANDLE);
    if (writer_handle.root_value_complete and writer_handle.open_depth == 0) return finish(SA_STD_ERR_INVALID_ARGUMENT);
    writer_handle.stream.write(value != 0) catch |err| return finishErr(err);
    writer_handle.root_value_started = true;
    writer_handle.root_value_complete = writer_handle.open_depth == 0;
    return finish(SA_STD_OK);
}

pub export fn sa_json_writer_write_i64(writer: u64, value: i64) i32 {
    while (!sa_std.registry_mutex.tryLock()) {
        std.Thread.yield() catch {};
    }
    defer sa_std.registry_mutex.unlock();
    const resource = getResourceLocked(writer) orelse return finish(SA_STD_ERR_INVALID_HANDLE);
    const writer_handle = switch (resource.*) {
        .json_writer => |handle| handle,
        else => return finish(SA_STD_ERR_INVALID_HANDLE),
    };
    if (writer_handle.result_buffer != null) return finish(SA_STD_ERR_INVALID_HANDLE);
    if (writer_handle.root_value_complete and writer_handle.open_depth == 0) return finish(SA_STD_ERR_INVALID_ARGUMENT);
    writer_handle.stream.write(value) catch |err| return finishErr(err);
    writer_handle.root_value_started = true;
    writer_handle.root_value_complete = writer_handle.open_depth == 0;
    return finish(SA_STD_OK);
}

pub export fn sa_json_writer_write_f64(writer: u64, value: f64) i32 {
    while (!sa_std.registry_mutex.tryLock()) {
        std.Thread.yield() catch {};
    }
    defer sa_std.registry_mutex.unlock();
    const resource = getResourceLocked(writer) orelse return finish(SA_STD_ERR_INVALID_HANDLE);
    const writer_handle = switch (resource.*) {
        .json_writer => |handle| handle,
        else => return finish(SA_STD_ERR_INVALID_HANDLE),
    };
    if (writer_handle.result_buffer != null) return finish(SA_STD_ERR_INVALID_HANDLE);
    if (writer_handle.root_value_complete and writer_handle.open_depth == 0) return finish(SA_STD_ERR_INVALID_ARGUMENT);
    writer_handle.stream.write(value) catch |err| return finishErr(err);
    writer_handle.root_value_started = true;
    writer_handle.root_value_complete = writer_handle.open_depth == 0;
    return finish(SA_STD_OK);
}

pub export fn sa_json_writer_write_string(writer: u64, data: ?[*]const u8, len: u64) i32 {
    while (!sa_std.registry_mutex.tryLock()) {
        std.Thread.yield() catch {};
    }
    defer sa_std.registry_mutex.unlock();
    const resource = getResourceLocked(writer) orelse return finish(SA_STD_ERR_INVALID_HANDLE);
    const writer_handle = switch (resource.*) {
        .json_writer => |handle| handle,
        else => return finish(SA_STD_ERR_INVALID_HANDLE),
    };
    if (writer_handle.result_buffer != null) return finish(SA_STD_ERR_INVALID_HANDLE);
    if (writer_handle.root_value_complete and writer_handle.open_depth == 0) return finish(SA_STD_ERR_INVALID_ARGUMENT);
    const bytes = constBytes(data, len) catch |err| return finishErr(err);
    writer_handle.stream.write(bytes) catch |err| return finishErr(err);
    writer_handle.root_value_started = true;
    writer_handle.root_value_complete = writer_handle.open_depth == 0;
    return finish(SA_STD_OK);
}

pub export fn sa_json_writer_write_null(writer: u64) i32 {
    while (!sa_std.registry_mutex.tryLock()) {
        std.Thread.yield() catch {};
    }
    defer sa_std.registry_mutex.unlock();
    const resource = getResourceLocked(writer) orelse return finish(SA_STD_ERR_INVALID_HANDLE);
    const writer_handle = switch (resource.*) {
        .json_writer => |handle| handle,
        else => return finish(SA_STD_ERR_INVALID_HANDLE),
    };
    if (writer_handle.result_buffer != null) return finish(SA_STD_ERR_INVALID_HANDLE);
    if (writer_handle.root_value_complete and writer_handle.open_depth == 0) return finish(SA_STD_ERR_INVALID_ARGUMENT);
    writer_handle.stream.write(null) catch |err| return finishErr(err);
    writer_handle.root_value_started = true;
    writer_handle.root_value_complete = writer_handle.open_depth == 0;
    return finish(SA_STD_OK);
}

pub export fn sa_json_writer_write_node(writer: u64, node: u64) i32 {
    var node_value = acquireJsonNode(node) catch |err| return finishErr(err);
    defer node_value.deinit();
    while (!sa_std.registry_mutex.tryLock()) {
        std.Thread.yield() catch {};
    }
    defer sa_std.registry_mutex.unlock();
    const resource = getResourceLocked(writer) orelse return finish(SA_STD_ERR_INVALID_HANDLE);
    const writer_handle = switch (resource.*) {
        .json_writer => |handle| handle,
        else => return finish(SA_STD_ERR_INVALID_HANDLE),
    };
    if (writer_handle.result_buffer != null) return finish(SA_STD_ERR_INVALID_HANDLE);
    if (writer_handle.root_value_complete and writer_handle.open_depth == 0) return finish(SA_STD_ERR_INVALID_ARGUMENT);
    writer_handle.stream.write(node_value.value) catch |err| return finishErr(err);
    writer_handle.root_value_started = true;
    writer_handle.root_value_complete = writer_handle.open_depth == 0;
    return finish(SA_STD_OK);
}

pub export fn sa_json_writer_finish(writer: u64, out_handle: ?*u64) i32 {
    const handle_ptr = out_handle orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    handle_ptr.* = 0;
    while (!sa_std.registry_mutex.tryLock()) {
        std.Thread.yield() catch {};
    }
    defer sa_std.registry_mutex.unlock();
    const resource = getResourceLocked(writer) orelse return finish(SA_STD_ERR_INVALID_HANDLE);
    const writer_handle = switch (resource.*) {
        .json_writer => |handle| handle,
        else => return finish(SA_STD_ERR_INVALID_HANDLE),
    };
    if (writer_handle.result_buffer) |existing| {
        const existing_resource = getResourceLocked(existing) orelse return finish(SA_STD_ERR_INVALID_HANDLE);
        switch (existing_resource.*) {
            .json_buffer => {},
            else => return finish(SA_STD_ERR_INVALID_HANDLE),
        }
        handle_ptr.* = existing;
        return finish(SA_STD_OK);
    }
    if (!writer_handle.root_value_started or !writer_handle.root_value_complete or writer_handle.open_depth != 0) {
        return finish(SA_STD_ERR_INVALID_ARGUMENT);
    }
    const bytes = writer_handle.aw.toOwnedSlice() catch |err| return finishErr(err);
    errdefer std.heap.page_allocator.free(bytes);
    const buffer_handle = registerResourceLocked(.{ .json_buffer = .{ .allocator = std.heap.page_allocator, .bytes = bytes } }) catch |err| {
        std.heap.page_allocator.free(bytes);
        return finishErr(err);
    };
    writer_handle.result_buffer = buffer_handle;
    handle_ptr.* = buffer_handle;
    return finish(SA_STD_OK);
}

pub export fn sa_json_writer_finish_buffer(writer: u64) u64 {
    var handle: u64 = 0;
    const status = sa_json_writer_finish(writer, &handle);
    if (status != SA_STD_OK) return 0;
    return handle;
}
