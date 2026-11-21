const std = @import("std");
const builtin = @import("builtin");
const sio = @import("sio");
const JsonTokenizer = @import("w01.zig").JsonTokenizer;
const JsonWriter = @import("w01.zig").JsonWriter;
const SA_JSON_TOKEN_INVALID = @import("w01.zig").SA_JSON_TOKEN_INVALID;
const SA_JSON_WHITESPACE_INDENT_1 = @import("w01.zig").SA_JSON_WHITESPACE_INDENT_1;
const SA_JSON_WHITESPACE_INDENT_2 = @import("w01.zig").SA_JSON_WHITESPACE_INDENT_2;
const SA_JSON_WHITESPACE_INDENT_3 = @import("w01.zig").SA_JSON_WHITESPACE_INDENT_3;
const SA_JSON_WHITESPACE_INDENT_4 = @import("w01.zig").SA_JSON_WHITESPACE_INDENT_4;
const SA_JSON_WHITESPACE_INDENT_8 = @import("w01.zig").SA_JSON_WHITESPACE_INDENT_8;
const SA_JSON_WHITESPACE_INDENT_TAB = @import("w01.zig").SA_JSON_WHITESPACE_INDENT_TAB;
const SA_JSON_WHITESPACE_MINIFIED = @import("w01.zig").SA_JSON_WHITESPACE_MINIFIED;
const SA_STD_ERR_INVALID_ARGUMENT = @import("w01.zig").SA_STD_ERR_INVALID_ARGUMENT;
const SA_STD_ERR_INVALID_HANDLE = @import("w01.zig").SA_STD_ERR_INVALID_HANDLE;
const SA_STD_ERR_IO = @import("w01.zig").SA_STD_ERR_IO;
const SA_STD_ERR_TRUNCATED = @import("w01.zig").SA_STD_ERR_TRUNCATED;
const SA_STD_ERR_UNSUPPORTED = @import("w01.zig").SA_STD_ERR_UNSUPPORTED;
const SA_STD_OK = @import("w01.zig").SA_STD_OK;
const SaJsonToken = @import("w01.zig").SaJsonToken;
const SaProcessArgv = @import("w01.zig").SaProcessArgv;
const WaitForSingleObject = @import("w01.zig").WaitForSingleObject;
const acquireJsonNode = @import("w03.zig").acquireJsonNode;
const closeJsonHandle = @import("w03.zig").closeJsonHandle;
const closeJsonWriter = @import("w03.zig").closeJsonWriter;
const closeTokenizer = @import("w03.zig").closeTokenizer;
const constBytes = @import("w02.zig").constBytes;
const finish = @import("w02.zig").finish;
const finishErr = @import("w02.zig").finishErr;
const getenv = @import("w01.zig").getenv;
const jsonText = @import("w04.zig").jsonText;
const jsonTokenKind = @import("w03.zig").jsonTokenKind;
const jsonWriterSlotLocked = @import("w03.zig").jsonWriterSlotLocked;
const json_tokenizer_mutex = @import("w02.zig").json_tokenizer_mutex;
const json_tokenizer_slots = @import("w02.zig").json_tokenizer_slots;
const json_writer_mutex = @import("w02.zig").json_writer_mutex;
const json_writer_slots = @import("w02.zig").json_writer_slots;
const markWriterValue = @import("w03.zig").markWriterValue;
const pathBytes = @import("w02.zig").pathBytes;
const processSlotLocked = @import("w03.zig").processSlotLocked;
const process_mutex = @import("w02.zig").process_mutex;
const process_slots = @import("w02.zig").process_slots;
const registerBuffer = @import("w02.zig").registerBuffer;
const registerJsonWriter = @import("w03.zig").registerJsonWriter;
const registerTokenizer = @import("w03.zig").registerTokenizer;
const sa_env_buffer_data = @import("w05.zig").sa_env_buffer_data;
const sa_env_buffer_len = @import("w05.zig").sa_env_buffer_len;
const sa_std_close = @import("w10.zig").sa_std_close;
const sa_std_process_close = @import("w10.zig").sa_std_process_close;
const setTokenizerText = @import("w03.zig").setTokenizerText;
const spawnProcess = @import("w04.zig").spawnProcess;
const spawnProcessCwd = @import("w04.zig").spawnProcessCwd;
const spawnStreamProcess = @import("w04.zig").spawnStreamProcess;
const spawnStreamProcessCwd = @import("w04.zig").spawnStreamProcessCwd;
const tokenizerSlotLocked = @import("w03.zig").tokenizerSlotLocked;
const writerField = @import("w03.zig").writerField;
const writerForValue = @import("w03.zig").writerForValue;

pub export fn sa_json_string_ptr(handle: u64) ?[*]const u8 {
    const node = acquireJsonNode(handle) catch return null;
    defer node.release();
    return if (jsonText(node.value)) |value| value.ptr else null;
}

pub export fn sa_json_string_len(handle: u64) u64 {
    const node = acquireJsonNode(handle) catch return 0;
    defer node.release();
    return if (jsonText(node.value)) |value| @as(u64, @intCast(value.len)) else 0;
}

pub export fn sa_json_value_count(handle: u64, out_count: ?*u64) i32 {
    const output = out_count orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    output.* = 0;
    const node = acquireJsonNode(handle) catch |err| return finishErr(err);
    defer node.release();
    output.* = switch (node.value) {
        .array => |array| @as(u64, @intCast(array.items.len)),
        .object => |object| @as(u64, @intCast(object.count())),
        else => return finish(SA_STD_ERR_INVALID_ARGUMENT),
    };
    return finish(SA_STD_OK);
}

pub export fn sa_json_free(handle: u64) i32 {
    return closeJsonHandle(handle);
}

pub export fn sa_json_stringify(handle: u64, out_handle: ?*u64) i32 {
    const output = out_handle orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    output.* = 0;
    const node = acquireJsonNode(handle) catch |err| return finishErr(err);
    defer node.release();
    const bytes = std.json.Stringify.valueAlloc(std.heap.page_allocator, node.value, .{}) catch |err| return finishErr(err);
    output.* = registerBuffer(bytes) catch |err| {
        std.heap.page_allocator.free(bytes);
        return finishErr(err);
    };
    return finish(SA_STD_OK);
}

pub export fn sa_json_buffer_data(handle: u64) ?[*]u8 {
    return sa_env_buffer_data(handle);
}

pub export fn sa_json_buffer_len(handle: u64) u64 {
    return sa_env_buffer_len(handle);
}

pub export fn sa_json_buffer_free(handle: u64) i32 {
    return sa_std_close(handle);
}

pub export fn sa_json_writer_new(whitespace: u32, emit_null_optional_fields: u8, emit_strings_as_arrays: u8, escape_unicode: u8, emit_nonportable_numbers_as_strings: u8, out_handle: ?*u64) i32 {
    const output = out_handle orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    output.* = 0;
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
    const writer = JsonWriter.create(options) catch |err| return finishErr(err);
    output.* = registerJsonWriter(writer) catch |err| {
        writer.destroy();
        return finishErr(err);
    };
    return finish(SA_STD_OK);
}

pub export fn sa_json_writer_begin_object(handle: u64) i32 {
    while (!json_writer_mutex.tryLock()) { std.Thread.yield() catch {}; }
    defer json_writer_mutex.unlock();
    const writer = writerForValue(handle) catch |err| return finishErr(err);
    writer.stream.beginObject() catch |err| return finishErr(err);
    writer.depth += 1;
    writer.started = true;
    writer.complete = false;
    return finish(SA_STD_OK);
}

pub export fn sa_json_writer_end_object(handle: u64) i32 {
    while (!json_writer_mutex.tryLock()) { std.Thread.yield() catch {}; }
    defer json_writer_mutex.unlock();
    const idx = jsonWriterSlotLocked(handle) orelse return finish(SA_STD_ERR_INVALID_HANDLE);
    const writer = json_writer_slots.items[idx].?;
    if (writer.finished) return finish(SA_STD_ERR_INVALID_HANDLE);
    if (writer.depth == 0) return finish(SA_STD_ERR_INVALID_ARGUMENT);
    writer.stream.endObject() catch |err| return finishErr(err);
    writer.depth -= 1;
    writer.complete = writer.depth == 0;
    return finish(SA_STD_OK);
}

pub export fn sa_json_writer_begin_array(handle: u64) i32 {
    while (!json_writer_mutex.tryLock()) { std.Thread.yield() catch {}; }
    defer json_writer_mutex.unlock();
    const writer = writerForValue(handle) catch |err| return finishErr(err);
    writer.stream.beginArray() catch |err| return finishErr(err);
    writer.depth += 1;
    writer.started = true;
    writer.complete = false;
    return finish(SA_STD_OK);
}

pub export fn sa_json_writer_end_array(handle: u64) i32 {
    while (!json_writer_mutex.tryLock()) { std.Thread.yield() catch {}; }
    defer json_writer_mutex.unlock();
    const idx = jsonWriterSlotLocked(handle) orelse return finish(SA_STD_ERR_INVALID_HANDLE);
    const writer = json_writer_slots.items[idx].?;
    if (writer.finished) return finish(SA_STD_ERR_INVALID_HANDLE);
    if (writer.depth == 0) return finish(SA_STD_ERR_INVALID_ARGUMENT);
    writer.stream.endArray() catch |err| return finishErr(err);
    writer.depth -= 1;
    writer.complete = writer.depth == 0;
    return finish(SA_STD_OK);
}

pub export fn sa_json_writer_object_field(handle: u64, key_ptr: ?[*]const u8, key_len: u64) i32 {
    const key = constBytes(key_ptr, key_len) catch |err| return finishErr(err);
    while (!json_writer_mutex.tryLock()) { std.Thread.yield() catch {}; }
    defer json_writer_mutex.unlock();
    const writer = writerForValue(handle) catch |err| return finishErr(err);
    writerField(writer, key) catch |err| return finishErr(err);
    return finish(SA_STD_OK);
}

pub fn writerFieldScalar(handle: u64, key: []const u8, value: anytype) i32 {
    while (!json_writer_mutex.tryLock()) { std.Thread.yield() catch {}; }
    defer json_writer_mutex.unlock();
    const writer = writerForValue(handle) catch |err| return finishErr(err);
    writerField(writer, key) catch |err| return finishErr(err);
    writer.stream.write(value) catch |err| return finishErr(err);
    markWriterValue(writer);
    return finish(SA_STD_OK);
}

pub export fn sa_json_writer_field_string(handle: u64, key_ptr: ?[*]const u8, key_len: u64, data_ptr: ?[*]const u8, len: u64) i32 {
    const key = constBytes(key_ptr, key_len) catch |err| return finishErr(err);
    const value = constBytes(data_ptr, len) catch |err| return finishErr(err);
    return writerFieldScalar(handle, key, value);
}

pub export fn sa_json_writer_field_bool(handle: u64, key_ptr: ?[*]const u8, key_len: u64, value: u8) i32 {
    const key = constBytes(key_ptr, key_len) catch |err| return finishErr(err);
    return writerFieldScalar(handle, key, value != 0);
}

pub export fn sa_json_writer_field_i64(handle: u64, key_ptr: ?[*]const u8, key_len: u64, value: i64) i32 {
    const key = constBytes(key_ptr, key_len) catch |err| return finishErr(err);
    return writerFieldScalar(handle, key, value);
}

pub export fn sa_json_writer_field_f64(handle: u64, key_ptr: ?[*]const u8, key_len: u64, value: f64) i32 {
    const key = constBytes(key_ptr, key_len) catch |err| return finishErr(err);
    return writerFieldScalar(handle, key, value);
}

pub export fn sa_json_writer_field_null(handle: u64, key_ptr: ?[*]const u8, key_len: u64) i32 {
    const key = constBytes(key_ptr, key_len) catch |err| return finishErr(err);
    return writerFieldScalar(handle, key, null);
}

pub export fn sa_json_writer_field_node(handle: u64, key_ptr: ?[*]const u8, key_len: u64, node_handle: u64) i32 {
    const key = constBytes(key_ptr, key_len) catch |err| return finishErr(err);
    const node = acquireJsonNode(node_handle) catch |err| return finishErr(err);
    defer node.release();
    return writerFieldScalar(handle, key, node.value);
}

pub fn writerScalar(handle: u64, value: anytype) i32 {
    while (!json_writer_mutex.tryLock()) { std.Thread.yield() catch {}; }
    defer json_writer_mutex.unlock();
    const writer = writerForValue(handle) catch |err| return finishErr(err);
    writer.stream.write(value) catch |err| return finishErr(err);
    markWriterValue(writer);
    return finish(SA_STD_OK);
}

pub export fn sa_json_writer_write_bool(handle: u64, value: u8) i32 {
    return writerScalar(handle, value != 0);
}

pub export fn sa_json_writer_write_i64(handle: u64, value: i64) i32 {
    return writerScalar(handle, value);
}

pub export fn sa_json_writer_write_f64(handle: u64, value: f64) i32 {
    return writerScalar(handle, value);
}

pub export fn sa_json_writer_write_string(handle: u64, data_ptr: ?[*]const u8, len: u64) i32 {
    const value = constBytes(data_ptr, len) catch |err| return finishErr(err);
    return writerScalar(handle, value);
}

pub export fn sa_json_writer_write_null(handle: u64) i32 {
    return writerScalar(handle, null);
}

pub export fn sa_json_writer_write_node(handle: u64, node_handle: u64) i32 {
    const node = acquireJsonNode(node_handle) catch |err| return finishErr(err);
    defer node.release();
    return writerScalar(handle, node.value);
}

pub export fn sa_json_writer_finish(handle: u64, out_handle: ?*u64) i32 {
    const output = out_handle orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    output.* = 0;
    while (!json_writer_mutex.tryLock()) { std.Thread.yield() catch {}; }
    const idx = jsonWriterSlotLocked(handle) orelse {
        json_writer_mutex.unlock();
        return finish(SA_STD_ERR_INVALID_HANDLE);
    };
    const writer = json_writer_slots.items[idx].?;
    if (writer.finished) {
        json_writer_mutex.unlock();
        return finish(SA_STD_ERR_INVALID_HANDLE);
    }
    if (!writer.started or !writer.complete or writer.depth != 0) {
        json_writer_mutex.unlock();
        return finish(SA_STD_ERR_INVALID_ARGUMENT);
    }
    const bytes = writer.out.toOwnedSlice() catch |err| {
        json_writer_mutex.unlock();
        return finishErr(err);
    };
    writer.finished = true;
    json_writer_mutex.unlock();
    output.* = registerBuffer(bytes) catch |err| {
        std.heap.page_allocator.free(bytes);
        return finishErr(err);
    };
    return finish(SA_STD_OK);
}

pub export fn sa_json_writer_finish_buffer(handle: u64) u64 {
    var output: u64 = 0;
    if (sa_json_writer_finish(handle, &output) != SA_STD_OK) return 0;
    return output;
}

pub export fn sa_json_writer_free(handle: u64) i32 {
    return closeJsonWriter(handle);
}

pub export fn sa_json_scanner_new(out_handle: ?*u64) i32 {
    const output = out_handle orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    output.* = 0;
    const tokenizer = JsonTokenizer.createStreaming() catch |err| return finishErr(err);
    output.* = registerTokenizer(tokenizer) catch |err| {
        tokenizer.destroy();
        return finishErr(err);
    };
    return finish(SA_STD_OK);
}

pub export fn sa_json_scanner_feed(handle: u64, input_ptr: ?[*]const u8, len: u64) i32 {
    const input = constBytes(input_ptr, len) catch |err| return finishErr(err);
    while (!json_tokenizer_mutex.tryLock()) { std.Thread.yield() catch {}; }
    defer json_tokenizer_mutex.unlock();
    const idx = tokenizerSlotLocked(handle) orelse return finish(SA_STD_ERR_INVALID_HANDLE);
    const tokenizer = json_tokenizer_slots.items[idx].?;
    if (tokenizer.is_stream) return finish(SA_STD_ERR_INVALID_HANDLE);
    if (tokenizer.input.len != 0) {
        if (tokenizer.scanner.cursor != tokenizer.scanner.input.len) return finish(SA_STD_ERR_INVALID_ARGUMENT);
        std.heap.page_allocator.free(tokenizer.input);
        tokenizer.input = &.{};
    }
    tokenizer.input = std.heap.page_allocator.dupe(u8, input) catch |err| return finishErr(err);
    tokenizer.scanner.feedInput(tokenizer.input);
    tokenizer.current_text = null;
    return finish(SA_STD_OK);
}

pub export fn sa_json_scanner_end_input(handle: u64) i32 {
    while (!json_tokenizer_mutex.tryLock()) { std.Thread.yield() catch {}; }
    defer json_tokenizer_mutex.unlock();
    const idx = tokenizerSlotLocked(handle) orelse return finish(SA_STD_ERR_INVALID_HANDLE);
    const tokenizer = json_tokenizer_slots.items[idx].?;
    if (tokenizer.is_stream) return finish(SA_STD_ERR_INVALID_HANDLE);
    tokenizer.scanner.endInput();
    return finish(SA_STD_OK);
}

pub export fn sa_json_scanner_next(handle: u64, out_token: ?*SaJsonToken) i32 {
    const output = out_token orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    output.* = .{ .kind = SA_JSON_TOKEN_INVALID, .text_ptr = null, .text_len = 0 };
    while (!json_tokenizer_mutex.tryLock()) { std.Thread.yield() catch {}; }
    defer json_tokenizer_mutex.unlock();
    const idx = tokenizerSlotLocked(handle) orelse return finish(SA_STD_ERR_INVALID_HANDLE);
    const tokenizer = json_tokenizer_slots.items[idx].?;
    if (tokenizer.is_stream) return finish(SA_STD_ERR_INVALID_HANDLE);
    const token = tokenizer.scanner.next() catch |err| switch (err) {
        error.BufferUnderrun => return finish(SA_STD_ERR_TRUNCATED),
        else => return finishErr(err),
    };
    setTokenizerText(tokenizer, token) catch |err| return finishErr(err);
    output.kind = jsonTokenKind(token);
    if (tokenizer.current_text) |text_value| {
        output.text_ptr = text_value.ptr;
        output.text_len = @as(u64, @intCast(text_value.len));
    }
    return finish(SA_STD_OK);
}

pub export fn sa_json_scanner_free(handle: u64) i32 {
    return closeTokenizer(handle);
}

pub export fn sa_json_stream_new(json_bytes: ?[*]const u8, len: u64) u64 {
    const input = constBytes(json_bytes, len) catch return 0;
    const tokenizer = JsonTokenizer.createComplete(input) catch return 0;
    return registerTokenizer(tokenizer) catch {
        tokenizer.destroy();
        return 0;
    };
}

pub export fn sa_json_stream_next(handle: u64) u32 {
    while (!json_tokenizer_mutex.tryLock()) { std.Thread.yield() catch {}; }
    defer json_tokenizer_mutex.unlock();
    const idx = tokenizerSlotLocked(handle) orelse return SA_JSON_TOKEN_INVALID;
    const tokenizer = json_tokenizer_slots.items[idx].?;
    if (!tokenizer.is_stream) return SA_JSON_TOKEN_INVALID;
    const token = tokenizer.scanner.next() catch return SA_JSON_TOKEN_INVALID;
    setTokenizerText(tokenizer, token) catch return SA_JSON_TOKEN_INVALID;
    return jsonTokenKind(token);
}

pub export fn sa_json_stream_get_slice_ptr(handle: u64) ?[*]const u8 {
    while (!json_tokenizer_mutex.tryLock()) { std.Thread.yield() catch {}; }
    defer json_tokenizer_mutex.unlock();
    const idx = tokenizerSlotLocked(handle) orelse return null;
    const tokenizer = json_tokenizer_slots.items[idx].?;
    if (!tokenizer.is_stream) return null;
    return if (tokenizer.current_text) |text_value| text_value.ptr else null;
}

pub export fn sa_json_stream_get_slice_len(handle: u64) u64 {
    while (!json_tokenizer_mutex.tryLock()) { std.Thread.yield() catch {}; }
    defer json_tokenizer_mutex.unlock();
    const idx = tokenizerSlotLocked(handle) orelse return 0;
    const tokenizer = json_tokenizer_slots.items[idx].?;
    if (!tokenizer.is_stream) return 0;
    return if (tokenizer.current_text) |text_value| @as(u64, @intCast(text_value.len)) else 0;
}

pub export fn sa_json_stream_free(handle: u64) i32 {
    return closeTokenizer(handle);
}

pub export fn sa_std_process_run(argv_ptr: ?[*]const SaProcessArgv, argv_len: u64, out_handle: ?*u64) i32 {
    const handle_ptr = out_handle orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    handle_ptr.* = 0;
    handle_ptr.* = spawnProcess(argv_ptr, argv_len, .capture) catch |err| return finishErr(err);
    return finish(SA_STD_OK);
}

pub export fn sa_std_process_run_cwd(argv_ptr: ?[*]const SaProcessArgv, argv_len: u64, cwd_ptr: ?[*]const u8, cwd_len: u64, out_handle: ?*u64) i32 {
    const handle_ptr = out_handle orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    handle_ptr.* = 0;
    const cwd = pathBytes(cwd_ptr, cwd_len) catch |err| return finishErr(err);
    handle_ptr.* = spawnProcessCwd(argv_ptr, argv_len, .capture, cwd, null) catch |err| return finishErr(err);
    return finish(SA_STD_OK);
}

pub export fn sa_std_process_spawn(argv_ptr: ?[*]const SaProcessArgv, argv_len: u64, out_handle: ?*u64) i32 {
    const handle_ptr = out_handle orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    handle_ptr.* = 0;
    handle_ptr.* = spawnProcess(argv_ptr, argv_len, .inherit) catch |err| return finishErr(err);
    return finish(SA_STD_OK);
}

pub export fn sa_std_process_spawn_cwd(argv_ptr: ?[*]const SaProcessArgv, argv_len: u64, cwd_ptr: ?[*]const u8, cwd_len: u64, out_handle: ?*u64) i32 {
    const handle_ptr = out_handle orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    handle_ptr.* = 0;
    const cwd = pathBytes(cwd_ptr, cwd_len) catch |err| return finishErr(err);
    handle_ptr.* = spawnProcessCwd(argv_ptr, argv_len, .inherit, cwd, null) catch |err| return finishErr(err);
    return finish(SA_STD_OK);
}

pub export fn sa_std_process_spawn_stream(argv_ptr: ?[*]const SaProcessArgv, argv_len: u64, out_process: ?*u64, out_stdout: ?*u64, out_stderr: ?*u64) i32 {
    const process_ptr = out_process orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    const stdout_ptr = out_stdout orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    const stderr_ptr = out_stderr orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    process_ptr.* = 0;
    stdout_ptr.* = 0;
    stderr_ptr.* = 0;
    spawnStreamProcess(argv_ptr, argv_len, process_ptr, stdout_ptr, stderr_ptr) catch |err| return finishErr(err);
    return finish(SA_STD_OK);
}

pub export fn sa_std_process_spawn_stream_cwd(argv_ptr: ?[*]const SaProcessArgv, argv_len: u64, cwd_ptr: ?[*]const u8, cwd_len: u64, out_process: ?*u64, out_stdout: ?*u64, out_stderr: ?*u64) i32 {
    const process_ptr = out_process orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    const stdout_ptr = out_stdout orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    const stderr_ptr = out_stderr orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    process_ptr.* = 0;
    stdout_ptr.* = 0;
    stderr_ptr.* = 0;
    const cwd = pathBytes(cwd_ptr, cwd_len) catch |err| return finishErr(err);
    spawnStreamProcessCwd(argv_ptr, argv_len, cwd, null, process_ptr, stdout_ptr, stderr_ptr) catch |err| return finishErr(err);
    return finish(SA_STD_OK);
}

pub export fn sa_std_process_run_command_ext(argv_ptr: ?[*]const SaProcessArgv, argv_len: u64, cwd_ptr: ?[*]const u8, cwd_len: u64, has_cwd: u32, arg0_ptr: ?[*]const u8, arg0_len: u64, has_arg0: u32, process_group: i32, has_process_group: u32, setsid: u32, out_handle: ?*u64) i32 {
    const handle_ptr = out_handle orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    handle_ptr.* = 0;
    _ = has_process_group;
    _ = setsid;
    _ = process_group;
    const arg0 = if (has_arg0 != 0) constBytes(arg0_ptr, arg0_len) catch |err| return finishErr(err) else null;
    const cwd = if (has_cwd != 0) pathBytes(cwd_ptr, cwd_len) catch |err| return finishErr(err) else null;
    if (getenv("SA_WINDOWS_PROCESS_DEBUG")) |_| {
        std.debug.print("run_command_ext has_arg0={} arg0_len={} arg0={s}\n", .{ has_arg0, arg0_len, arg0 orelse "" });
    }
    handle_ptr.* = spawnProcessCwd(argv_ptr, argv_len, .capture, cwd, arg0) catch |err| return finishErr(err);
    return finish(SA_STD_OK);
}

pub export fn sa_std_process_spawn_command_ext(argv_ptr: ?[*]const SaProcessArgv, argv_len: u64, cwd_ptr: ?[*]const u8, cwd_len: u64, has_cwd: u32, arg0_ptr: ?[*]const u8, arg0_len: u64, has_arg0: u32, process_group: i32, has_process_group: u32, setsid: u32, out_handle: ?*u64) i32 {
    const handle_ptr = out_handle orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    handle_ptr.* = 0;
    if (has_process_group != 0 or setsid != 0) return finish(SA_STD_ERR_UNSUPPORTED);
    _ = process_group;
    const arg0 = if (has_arg0 != 0) constBytes(arg0_ptr, arg0_len) catch |err| return finishErr(err) else null;
    const cwd = if (has_cwd != 0) pathBytes(cwd_ptr, cwd_len) catch |err| return finishErr(err) else null;
    handle_ptr.* = spawnProcessCwd(argv_ptr, argv_len, .inherit, cwd, arg0) catch |err| return finishErr(err);
    return finish(SA_STD_OK);
}

pub export fn sa_std_process_spawn_stream_command_ext(argv_ptr: ?[*]const SaProcessArgv, argv_len: u64, cwd_ptr: ?[*]const u8, cwd_len: u64, has_cwd: u32, arg0_ptr: ?[*]const u8, arg0_len: u64, has_arg0: u32, process_group: i32, has_process_group: u32, setsid: u32, out_process: ?*u64, out_stdout: ?*u64, out_stderr: ?*u64) i32 {
    const process_ptr = out_process orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    const stdout_ptr = out_stdout orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    const stderr_ptr = out_stderr orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    process_ptr.* = 0;
    stdout_ptr.* = 0;
    stderr_ptr.* = 0;
    if (has_process_group != 0 or setsid != 0) return finish(SA_STD_ERR_UNSUPPORTED);
    _ = process_group;
    const arg0 = if (has_arg0 != 0) constBytes(arg0_ptr, arg0_len) catch |err| return finishErr(err) else null;
    const cwd = if (has_cwd != 0) pathBytes(cwd_ptr, cwd_len) catch |err| return finishErr(err) else null;
    spawnStreamProcessCwd(argv_ptr, argv_len, cwd, arg0, process_ptr, stdout_ptr, stderr_ptr) catch |err| return finishErr(err);
    return finish(SA_STD_OK);
}

pub export fn sa_std_process_run_command_ext_pidfd(argv_ptr: ?[*]const SaProcessArgv, argv_len: u64, cwd_ptr: ?[*]const u8, cwd_len: u64, has_cwd: u32, arg0_ptr: ?[*]const u8, arg0_len: u64, has_arg0: u32, process_group: i32, has_process_group: u32, setsid: u32, _: u32, out_handle: ?*u64) i32 {
    return sa_std_process_run_command_ext(argv_ptr, argv_len, cwd_ptr, cwd_len, has_cwd, arg0_ptr, arg0_len, has_arg0, process_group, has_process_group, setsid, out_handle);
}

pub export fn sa_std_process_spawn_command_ext_pidfd(argv_ptr: ?[*]const SaProcessArgv, argv_len: u64, cwd_ptr: ?[*]const u8, cwd_len: u64, has_cwd: u32, arg0_ptr: ?[*]const u8, arg0_len: u64, has_arg0: u32, process_group: i32, has_process_group: u32, setsid: u32, _: u32, out_handle: ?*u64) i32 {
    return sa_std_process_spawn_command_ext(argv_ptr, argv_len, cwd_ptr, cwd_len, has_cwd, arg0_ptr, arg0_len, has_arg0, process_group, has_process_group, setsid, out_handle);
}

pub export fn sa_std_process_spawn_stream_command_ext_pidfd(_: ?[*]const SaProcessArgv, _: u64, _: ?[*]const u8, _: u64, _: u32, _: ?[*]const u8, _: u64, _: u32, _: i32, _: u32, _: u32, _: u32, out_process: ?*u64, out_stdout: ?*u64, out_stderr: ?*u64) i32 {
    const process_ptr = out_process orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    const stdout_ptr = out_stdout orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    const stderr_ptr = out_stderr orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    process_ptr.* = 0;
    stdout_ptr.* = 0;
    stderr_ptr.* = 0;
    return finish(SA_STD_ERR_UNSUPPORTED);
}

pub export fn sa_std_process_run_command_ext_uid_gid(argv_ptr: ?[*]const SaProcessArgv, argv_len: u64, cwd_ptr: ?[*]const u8, cwd_len: u64, has_cwd: u32, arg0_ptr: ?[*]const u8, arg0_len: u64, has_arg0: u32, process_group: i32, has_process_group: u32, setsid: u32, _: u32, _: u32, _: u32, _: u32, out_handle: ?*u64) i32 {
    return sa_std_process_run_command_ext(argv_ptr, argv_len, cwd_ptr, cwd_len, has_cwd, arg0_ptr, arg0_len, has_arg0, process_group, has_process_group, setsid, out_handle);
}

pub export fn sa_std_process_spawn_command_ext_uid_gid(argv_ptr: ?[*]const SaProcessArgv, argv_len: u64, cwd_ptr: ?[*]const u8, cwd_len: u64, has_cwd: u32, arg0_ptr: ?[*]const u8, arg0_len: u64, has_arg0: u32, process_group: i32, has_process_group: u32, setsid: u32, uid: u32, has_uid: u32, gid: u32, has_gid: u32, out_handle: ?*u64) i32 {
    _ = uid;
    _ = has_uid;
    _ = gid;
    _ = has_gid;
    return sa_std_process_spawn_command_ext(argv_ptr, argv_len, cwd_ptr, cwd_len, has_cwd, arg0_ptr, arg0_len, has_arg0, process_group, has_process_group, setsid, out_handle);
}

pub export fn sa_std_process_spawn_stream_command_ext_uid_gid(argv_ptr: ?[*]const SaProcessArgv, argv_len: u64, cwd_ptr: ?[*]const u8, cwd_len: u64, has_cwd: u32, arg0_ptr: ?[*]const u8, arg0_len: u64, has_arg0: u32, process_group: i32, has_process_group: u32, setsid: u32, uid: u32, has_uid: u32, gid: u32, has_gid: u32, out_process: ?*u64, out_stdout: ?*u64, out_stderr: ?*u64) i32 {
    _ = uid;
    _ = has_uid;
    _ = gid;
    _ = has_gid;
    return sa_std_process_spawn_stream_command_ext(argv_ptr, argv_len, cwd_ptr, cwd_len, has_cwd, arg0_ptr, arg0_len, has_arg0, process_group, has_process_group, setsid, out_process, out_stdout, out_stderr);
}

pub export fn sa_std_process_run_command_ext_groups(argv_ptr: ?[*]const SaProcessArgv, argv_len: u64, cwd_ptr: ?[*]const u8, cwd_len: u64, has_cwd: u32, arg0_ptr: ?[*]const u8, arg0_len: u64, has_arg0: u32, process_group: i32, has_process_group: u32, setsid: u32, _: ?[*]const u32, _: u64, _: u32, out_handle: ?*u64) i32 {
    return sa_std_process_run_command_ext(argv_ptr, argv_len, cwd_ptr, cwd_len, has_cwd, arg0_ptr, arg0_len, has_arg0, process_group, has_process_group, setsid, out_handle);
}

pub export fn sa_std_process_spawn_command_ext_groups(argv_ptr: ?[*]const SaProcessArgv, argv_len: u64, cwd_ptr: ?[*]const u8, cwd_len: u64, has_cwd: u32, arg0_ptr: ?[*]const u8, arg0_len: u64, has_arg0: u32, process_group: i32, has_process_group: u32, setsid: u32, _: ?[*]const u32, _: u64, _: u32, out_handle: ?*u64) i32 {
    return sa_std_process_spawn_command_ext(argv_ptr, argv_len, cwd_ptr, cwd_len, has_cwd, arg0_ptr, arg0_len, has_arg0, process_group, has_process_group, setsid, out_handle);
}

pub export fn sa_std_process_spawn_stream_command_ext_groups(argv_ptr: ?[*]const SaProcessArgv, argv_len: u64, cwd_ptr: ?[*]const u8, cwd_len: u64, has_cwd: u32, arg0_ptr: ?[*]const u8, arg0_len: u64, has_arg0: u32, process_group: i32, has_process_group: u32, setsid: u32, _: ?[*]const u32, _: u64, _: u32, out_process: ?*u64, out_stdout: ?*u64, out_stderr: ?*u64) i32 {
    return sa_std_process_spawn_stream_command_ext(argv_ptr, argv_len, cwd_ptr, cwd_len, has_cwd, arg0_ptr, arg0_len, has_arg0, process_group, has_process_group, setsid, out_process, out_stdout, out_stderr);
}

pub export fn sa_std_process_run_command_ext_chroot(argv_ptr: ?[*]const SaProcessArgv, argv_len: u64, cwd_ptr: ?[*]const u8, cwd_len: u64, has_cwd: u32, arg0_ptr: ?[*]const u8, arg0_len: u64, has_arg0: u32, process_group: i32, has_process_group: u32, setsid: u32, _: ?[*]const u8, _: u64, _: u32, out_handle: ?*u64) i32 {
    return sa_std_process_run_command_ext(argv_ptr, argv_len, cwd_ptr, cwd_len, has_cwd, arg0_ptr, arg0_len, has_arg0, process_group, has_process_group, setsid, out_handle);
}

pub export fn sa_std_process_spawn_command_ext_chroot(argv_ptr: ?[*]const SaProcessArgv, argv_len: u64, cwd_ptr: ?[*]const u8, cwd_len: u64, has_cwd: u32, arg0_ptr: ?[*]const u8, arg0_len: u64, has_arg0: u32, process_group: i32, has_process_group: u32, setsid: u32, _: ?[*]const u8, _: u64, _: u32, out_handle: ?*u64) i32 {
    return sa_std_process_spawn_command_ext(argv_ptr, argv_len, cwd_ptr, cwd_len, has_cwd, arg0_ptr, arg0_len, has_arg0, process_group, has_process_group, setsid, out_handle);
}

pub export fn sa_std_process_spawn_stream_command_ext_chroot(argv_ptr: ?[*]const SaProcessArgv, argv_len: u64, cwd_ptr: ?[*]const u8, cwd_len: u64, has_cwd: u32, arg0_ptr: ?[*]const u8, arg0_len: u64, has_arg0: u32, process_group: i32, has_process_group: u32, setsid: u32, _: ?[*]const u8, _: u64, _: u32, out_process: ?*u64, out_stdout: ?*u64, out_stderr: ?*u64) i32 {
    return sa_std_process_spawn_stream_command_ext(argv_ptr, argv_len, cwd_ptr, cwd_len, has_cwd, arg0_ptr, arg0_len, has_arg0, process_group, has_process_group, setsid, out_process, out_stdout, out_stderr);
}

pub export fn sa_std_process_exec_command_ext(argv_ptr: ?[*]const SaProcessArgv, argv_len: u64, cwd_ptr: ?[*]const u8, cwd_len: u64, has_cwd: u32, arg0_ptr: ?[*]const u8, arg0_len: u64, has_arg0: u32, process_group: i32, has_process_group: u32, setsid: u32, uid: u32, has_uid: u32, gid: u32, has_gid: u32, groups_ptr: ?[*]const u32, groups_len: u64, has_groups: u32, chroot_ptr: ?[*]const u8, chroot_len: u64, has_chroot: u32) i32 {
    _ = uid;
    _ = has_uid;
    _ = gid;
    _ = has_gid;
    _ = groups_ptr;
    _ = groups_len;
    _ = has_groups;
    _ = chroot_ptr;
    _ = chroot_len;
    _ = has_chroot;
    var handle: u64 = 0;
    const status = sa_std_process_run_command_ext(argv_ptr, argv_len, cwd_ptr, cwd_len, has_cwd, arg0_ptr, arg0_len, has_arg0, process_group, has_process_group, setsid, &handle);
    if (status != SA_STD_OK) return status;
    var code: u32 = 0;
    const wait_status = sa_std_process_wait(handle, &code);
    _ = wait_status;
    _ = sa_std_process_close(handle);
    // Exit with the child's code
    std.process.exit(@as(u8, @intCast(code & 0xFF)));
}

pub export fn sa_std_process_child_id(handle: u64, out_pid: ?*u32) i32 {
    const pid_ptr = out_pid orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    pid_ptr.* = 0;
    while (!process_mutex.tryLock()) { std.Thread.yield() catch {}; }
    defer process_mutex.unlock();
    const idx = processSlotLocked(handle) orelse return finish(SA_STD_ERR_INVALID_HANDLE);
    pid_ptr.* = process_slots.items[idx].?.pid;
    return finish(SA_STD_OK);
}

pub export fn sa_std_process_wait(handle: u64, out_code: ?*u32) i32 {
    const code_ptr = out_code orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    code_ptr.* = 0;
    while (!process_mutex.tryLock()) { std.Thread.yield() catch {}; }
    defer process_mutex.unlock();
    const idx = processSlotLocked(handle) orelse return finish(SA_STD_ERR_INVALID_HANDLE);
    const resource = process_slots.items[idx].?;
    resource.finishWait() catch |err| return finishErr(err);
    code_ptr.* = resource.code;
    return finish(SA_STD_OK);
}

pub export fn sa_std_process_try_wait(handle: u64, out_ready: ?*i32, out_code: ?*u32) i32 {
    const ready_ptr = out_ready orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    const code_ptr = out_code orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    ready_ptr.* = 0;
    code_ptr.* = 0;
    while (!process_mutex.tryLock()) { std.Thread.yield() catch {}; }
    defer process_mutex.unlock();
    const idx = processSlotLocked(handle) orelse return finish(SA_STD_ERR_INVALID_HANDLE);
    const resource = process_slots.items[idx].?;
    if (!resource.exited) {
        // NOTE: std.os.windows.WaitForSingleObjectEx has no 0.17 std
        // counterpart (verified); kept for the windows target, revisit.
        const inner = resource.child.inner orelse return finish(SA_STD_ERR_INVALID_HANDLE);
        const proc_handle = inner.id orelse return finish(SA_STD_ERR_INVALID_HANDLE);
        const wait_result = WaitForSingleObject(proc_handle, 0);
        if (wait_result == 0x102) return finish(SA_STD_OK);
        if (wait_result != 0) return finish(SA_STD_ERR_IO);
        resource.finishWait() catch |err| return finishErr(err);
    }
    ready_ptr.* = 1;
    code_ptr.* = resource.code;
    return finish(SA_STD_OK);
}

pub export fn sa_std_process_kill(handle: u64) i32 {
    while (!process_mutex.tryLock()) { std.Thread.yield() catch {}; }
    defer process_mutex.unlock();
    const idx = processSlotLocked(handle) orelse return finish(SA_STD_ERR_INVALID_HANDLE);
    const resource = process_slots.items[idx].?;
    if (!resource.exited) {
        resource.child.kill() catch |err| return finishErr(err);
        resource.finishWait() catch |err| return finishErr(err);
    }
    return finish(SA_STD_OK);
}
