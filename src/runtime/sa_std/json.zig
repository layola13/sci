const std = @import("std");
const Fallible = @import("../sa_std.zig").Fallible;
const JsonScannerHandle = @import("../sa_std.zig").JsonScannerHandle;
const JsonStreamHandle = @import("../sa_std.zig").JsonStreamHandle;
const JsonWriterHandle = @import("../sa_std.zig").JsonWriterHandle;
const SA_JSON_KIND_ARRAY = @import("../sa_std.zig").SA_JSON_KIND_ARRAY;
const SA_JSON_KIND_BOOL = @import("../sa_std.zig").SA_JSON_KIND_BOOL;
const SA_JSON_KIND_FLOAT = @import("../sa_std.zig").SA_JSON_KIND_FLOAT;
const SA_JSON_KIND_INTEGER = @import("../sa_std.zig").SA_JSON_KIND_INTEGER;
const SA_JSON_KIND_INVALID = @import("../sa_std.zig").SA_JSON_KIND_INVALID;
const SA_JSON_KIND_NULL = @import("../sa_std.zig").SA_JSON_KIND_NULL;
const SA_JSON_KIND_NUMBER_STRING = @import("../sa_std.zig").SA_JSON_KIND_NUMBER_STRING;
const SA_JSON_KIND_OBJECT = @import("../sa_std.zig").SA_JSON_KIND_OBJECT;
const SA_JSON_KIND_STRING = @import("../sa_std.zig").SA_JSON_KIND_STRING;
const SA_JSON_TOKEN_ARRAY_BEGIN = @import("../sa_std.zig").SA_JSON_TOKEN_ARRAY_BEGIN;
const SA_JSON_TOKEN_ARRAY_END = @import("../sa_std.zig").SA_JSON_TOKEN_ARRAY_END;
const SA_JSON_TOKEN_END_OF_DOCUMENT = @import("../sa_std.zig").SA_JSON_TOKEN_END_OF_DOCUMENT;
const SA_JSON_TOKEN_FALSE = @import("../sa_std.zig").SA_JSON_TOKEN_FALSE;
const SA_JSON_TOKEN_INVALID = @import("../sa_std.zig").SA_JSON_TOKEN_INVALID;
const SA_JSON_TOKEN_NULL = @import("../sa_std.zig").SA_JSON_TOKEN_NULL;
const SA_JSON_TOKEN_NUMBER = @import("../sa_std.zig").SA_JSON_TOKEN_NUMBER;
const SA_JSON_TOKEN_OBJECT_BEGIN = @import("../sa_std.zig").SA_JSON_TOKEN_OBJECT_BEGIN;
const SA_JSON_TOKEN_OBJECT_END = @import("../sa_std.zig").SA_JSON_TOKEN_OBJECT_END;
const SA_JSON_TOKEN_STRING = @import("../sa_std.zig").SA_JSON_TOKEN_STRING;
const SA_JSON_TOKEN_TRUE = @import("../sa_std.zig").SA_JSON_TOKEN_TRUE;
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
const jsonArrayGet = @import("../sa_std.zig").jsonArrayGet;
const jsonArrayPushLocked = @import("../sa_std.zig").jsonArrayPushLocked;
const jsonDocumentFromSlice = @import("../sa_std.zig").jsonDocumentFromSlice;
const jsonKindOf = @import("../sa_std.zig").jsonKindOf;
const jsonObjectGet = @import("../sa_std.zig").jsonObjectGet;
const jsonObjectKeyAt = @import("../sa_std.zig").jsonObjectKeyAt;
const jsonObjectRemoveLocked = @import("../sa_std.zig").jsonObjectRemoveLocked;
const jsonObjectSetLocked = @import("../sa_std.zig").jsonObjectSetLocked;
const jsonScannerFeed = @import("../sa_std.zig").jsonScannerFeed;
const jsonSerializeBuffer = @import("../sa_std.zig").jsonSerializeBuffer;
const jsonTextSlice = @import("../sa_std.zig").jsonTextSlice;
const jsonValueAsBool = @import("../sa_std.zig").jsonValueAsBool;
const jsonValueAsF64 = @import("../sa_std.zig").jsonValueAsF64;
const jsonValueAsI64 = @import("../sa_std.zig").jsonValueAsI64;
const jsonValueClone = @import("../sa_std.zig").jsonValueClone;
const jsonWriterObjectFieldLocked = @import("../sa_std.zig").jsonWriterObjectFieldLocked;
const markJsonWriterValueComplete = @import("../sa_std.zig").markJsonWriterValueComplete;
const ok = @import("../sa_std.zig").ok;
const registerJsonNode = @import("../sa_std.zig").registerJsonNode;
const registerResource = @import("../sa_std.zig").registerResource;
const registerResourceLocked = @import("../sa_std.zig").registerResourceLocked;
const sa_std = @import("../sa_std.zig");
const sa_std_close = @import("../sa_std.zig").sa_std_close;
const tokenTextBytes = @import("../sa_std.zig").tokenTextBytes;
const tokenTextSlice = @import("../sa_std.zig").tokenTextSlice;
const tokenTypeOf = @import("../sa_std.zig").tokenTypeOf;

pub export fn sa_json_parse(json_bytes: ?[*]const u8, len: u64) u64 {
    const input = constBytes(json_bytes, len) catch return 0;
    const document = jsonDocumentFromSlice(std.heap.page_allocator, input) catch return 0;
    return registerJsonNode(document, &.{}, false) catch return 0;
}

pub export fn sa_json_kind(node: u64) u32 {
    var node_value = acquireJsonNode(node) catch return SA_JSON_KIND_INVALID;
    defer node_value.deinit();
    return jsonKindOf(node_value.value);
}

pub export fn sa_json_object_get(node: u64, key_ptr: ?[*]const u8, key_len: u64, out_handle: ?*u64) i32 {
    const handle_ptr = out_handle orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    handle_ptr.* = 0;
    const key = constBytes(key_ptr, key_len) catch |err| return finishErr(err);
    if (key.len == 0) return finish(SA_STD_ERR_INVALID_ARGUMENT);
    var node_value = acquireJsonNode(node) catch |err| return finishErr(err);
    defer node_value.deinit();
    const child = jsonObjectGet(node_value, key) catch |err| return finishErr(err);
    const handle = registerJsonNode(child.document, child.path, true) catch |err| return finishErr(err);
    handle_ptr.* = handle;
    return finish(SA_STD_OK);
}

pub export fn sa_json_array_get(node: u64, index: u64, out_handle: ?*u64) i32 {
    const handle_ptr = out_handle orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    handle_ptr.* = 0;
    var node_value = acquireJsonNode(node) catch |err| return finishErr(err);
    defer node_value.deinit();
    const child = jsonArrayGet(node_value, index) catch |err| return finishErr(err);
    const handle = registerJsonNode(child.document, child.path, true) catch |err| return finishErr(err);
    handle_ptr.* = handle;
    return finish(SA_STD_OK);
}

pub export fn sa_json_object_key_at(node: u64, index: u64, out_ptr: ?*?[*]const u8, out_len: ?*u64) i32 {
    const ptr_slot = out_ptr orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    const len_slot = out_len orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    ptr_slot.* = null;
    len_slot.* = 0;
    var node_value = acquireJsonNode(node) catch |err| return finishErr(err);
    defer node_value.deinit();
    const key = jsonObjectKeyAt(node_value, index) catch |err| return finishErr(err);
    ptr_slot.* = key.ptr;
    len_slot.* = @as(u64, @intCast(key.len));
    return finish(SA_STD_OK);
}

pub export fn sa_json_object_get_string(node: u64, key_ptr: ?[*]const u8, key_len: u64, out_ptr: ?*?[*]const u8, out_len: ?*u64) i32 {
    const ptr_slot = out_ptr orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    const len_slot = out_len orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    ptr_slot.* = null;
    len_slot.* = 0;
    const key = constBytes(key_ptr, key_len) catch |err| return finishErr(err);
    if (key.len == 0) return finish(SA_STD_ERR_INVALID_ARGUMENT);
    var node_value = acquireJsonNode(node) catch |err| return finishErr(err);
    defer node_value.deinit();
    const child = jsonObjectGet(node_value, key) catch |err| return finishErr(err);
    const text = jsonTextSlice(child.value) orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    ptr_slot.* = text.ptr;
    len_slot.* = @as(u64, @intCast(text.len));
    return finish(SA_STD_OK);
}

pub export fn sa_json_object_get_bool(node: u64, key_ptr: ?[*]const u8, key_len: u64, out_value: ?*u8) i32 {
    const value_ptr = out_value orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    value_ptr.* = 0;
    const key = constBytes(key_ptr, key_len) catch |err| return finishErr(err);
    if (key.len == 0) return finish(SA_STD_ERR_INVALID_ARGUMENT);
    var node_value = acquireJsonNode(node) catch |err| return finishErr(err);
    defer node_value.deinit();
    const child = jsonObjectGet(node_value, key) catch |err| return finishErr(err);
    const parsed = jsonValueAsBool(child.value) catch |err| return finishErr(err);
    value_ptr.* = if (parsed) 1 else 0;
    return finish(SA_STD_OK);
}

pub export fn sa_json_object_get_i64(node: u64, key_ptr: ?[*]const u8, key_len: u64, out_value: ?*i64) i32 {
    const value_ptr = out_value orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    value_ptr.* = 0;
    const key = constBytes(key_ptr, key_len) catch |err| return finishErr(err);
    if (key.len == 0) return finish(SA_STD_ERR_INVALID_ARGUMENT);
    var node_value = acquireJsonNode(node) catch |err| return finishErr(err);
    defer node_value.deinit();
    const child = jsonObjectGet(node_value, key) catch |err| return finishErr(err);
    const parsed = jsonValueAsI64(child.value) catch |err| return finishErr(err);
    value_ptr.* = parsed;
    return finish(SA_STD_OK);
}

pub export fn sa_json_object_get_f64(node: u64, key_ptr: ?[*]const u8, key_len: u64, out_value: ?*f64) i32 {
    const value_ptr = out_value orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    value_ptr.* = 0;
    const key = constBytes(key_ptr, key_len) catch |err| return finishErr(err);
    if (key.len == 0) return finish(SA_STD_ERR_INVALID_ARGUMENT);
    var node_value = acquireJsonNode(node) catch |err| return finishErr(err);
    defer node_value.deinit();
    const child = jsonObjectGet(node_value, key) catch |err| return finishErr(err);
    const parsed = jsonValueAsF64(child.value) catch |err| return finishErr(err);
    value_ptr.* = parsed;
    return finish(SA_STD_OK);
}

pub export fn sa_json_as_f64(node: u64, out_value: ?*f64) i32 {
    const value_ptr = out_value orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    value_ptr.* = 0;
    var node_value = acquireJsonNode(node) catch |err| return finishErr(err);
    defer node_value.deinit();
    const parsed = jsonValueAsF64(node_value.value) catch |err| return finishErr(err);
    value_ptr.* = parsed;
    return finish(SA_STD_OK);
}

pub export fn sa_json_as_i64(node: u64, out_value: ?*i64) i32 {
    const value_ptr = out_value orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    value_ptr.* = 0;
    var node_value = acquireJsonNode(node) catch |err| return finishErr(err);
    defer node_value.deinit();
    const parsed = jsonValueAsI64(node_value.value) catch |err| return finishErr(err);
    value_ptr.* = parsed;
    return finish(SA_STD_OK);
}

pub export fn sa_json_as_bool(node: u64, out_value: ?*u8) i32 {
    const value_ptr = out_value orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    value_ptr.* = 0;
    var node_value = acquireJsonNode(node) catch |err| return finishErr(err);
    defer node_value.deinit();
    const parsed = jsonValueAsBool(node_value.value) catch |err| return finishErr(err);
    value_ptr.* = if (parsed) 1 else 0;
    return finish(SA_STD_OK);
}

pub export fn sa_json_string_ptr(node: u64) ?[*]const u8 {
    var node_value = acquireJsonNode(node) catch return null;
    defer node_value.deinit();
    return if (jsonTextSlice(node_value.value)) |text| text.ptr else null;
}

pub export fn sa_json_string_len(node: u64) u64 {
    var node_value = acquireJsonNode(node) catch return 0;
    defer node_value.deinit();
    return if (jsonTextSlice(node_value.value)) |text| @as(u64, @intCast(text.len)) else 0;
}

pub export fn sa_json_value_count(node: u64, out_count: ?*u64) i32 {
    const count_ptr = out_count orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    count_ptr.* = 0;
    var node_value = acquireJsonNode(node) catch |err| return finishErr(err);
    defer node_value.deinit();
    return switch (node_value.value) {
        .array => |array| {
            count_ptr.* = @as(u64, @intCast(array.items.len));
            return finish(SA_STD_OK);
        },
        .object => |object| {
            count_ptr.* = @as(u64, @intCast(object.count()));
            return finish(SA_STD_OK);
        },
        else => finish(SA_STD_ERR_INVALID_ARGUMENT),
    };
}

pub export fn sa_json_free(node: u64) Fallible(i32) {
    const status = sa_std_close(node);
    if (status != SA_STD_OK) return fail(i32, status);
    return ok(i32, 0);
}

pub export fn sa_json_stringify(node: u64, out_handle: ?*u64) i32 {
    const handle_ptr = out_handle orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    handle_ptr.* = 0;
    var node_value = acquireJsonNode(node) catch |err| return finishErr(err);
    defer node_value.deinit();
    const handle = jsonSerializeBuffer(std.heap.page_allocator, node_value.value) catch |err| return finishErr(err);
    handle_ptr.* = handle;
    return finish(SA_STD_OK);
}

pub export fn sa_json_object_set_string(node: u64, key_ptr: ?[*]const u8, key_len: u64, data_ptr: ?[*]const u8, data_len: u64) i32 {
    const key = constBytes(key_ptr, key_len) catch |err| return finishErr(err);
    if (key.len == 0) return finish(SA_STD_ERR_INVALID_ARGUMENT);
    const data = constBytes(data_ptr, data_len) catch |err| return finishErr(err);
    var node_value = acquireJsonNode(node) catch |err| return finishErr(err);
    defer node_value.deinit();
    const arena = node_value.document.parsed.arena.allocator();
    const owned = arena.dupe(u8, data) catch |err| return finishErr(err);
    jsonObjectSetLocked(node, key, .{ .string = owned }) catch |err| return finishErr(err);
    return finish(SA_STD_OK);
}

pub export fn sa_json_object_set_i64(node: u64, key_ptr: ?[*]const u8, key_len: u64, value: i64) i32 {
    const key = constBytes(key_ptr, key_len) catch |err| return finishErr(err);
    if (key.len == 0) return finish(SA_STD_ERR_INVALID_ARGUMENT);
    jsonObjectSetLocked(node, key, .{ .integer = value }) catch |err| return finishErr(err);
    return finish(SA_STD_OK);
}

pub export fn sa_json_object_set_f64(node: u64, key_ptr: ?[*]const u8, key_len: u64, value: f64) i32 {
    const key = constBytes(key_ptr, key_len) catch |err| return finishErr(err);
    if (key.len == 0) return finish(SA_STD_ERR_INVALID_ARGUMENT);
    if (!std.math.isFinite(value)) return finish(SA_STD_ERR_INVALID_ARGUMENT);
    jsonObjectSetLocked(node, key, .{ .float = value }) catch |err| return finishErr(err);
    return finish(SA_STD_OK);
}

pub export fn sa_json_object_set_bool(node: u64, key_ptr: ?[*]const u8, key_len: u64, value: u8) i32 {
    const key = constBytes(key_ptr, key_len) catch |err| return finishErr(err);
    if (key.len == 0) return finish(SA_STD_ERR_INVALID_ARGUMENT);
    jsonObjectSetLocked(node, key, .{ .bool = value != 0 }) catch |err| return finishErr(err);
    return finish(SA_STD_OK);
}

pub export fn sa_json_object_set_null(node: u64, key_ptr: ?[*]const u8, key_len: u64) i32 {
    const key = constBytes(key_ptr, key_len) catch |err| return finishErr(err);
    if (key.len == 0) return finish(SA_STD_ERR_INVALID_ARGUMENT);
    jsonObjectSetLocked(node, key, .null) catch |err| return finishErr(err);
    return finish(SA_STD_OK);
}

pub export fn sa_json_object_set_node(node: u64, key_ptr: ?[*]const u8, key_len: u64, child: u64) i32 {
    const key = constBytes(key_ptr, key_len) catch |err| return finishErr(err);
    if (key.len == 0) return finish(SA_STD_ERR_INVALID_ARGUMENT);
    var node_value = acquireJsonNode(node) catch |err| return finishErr(err);
    defer node_value.deinit();
    var child_value = acquireJsonNode(child) catch |err| return finishErr(err);
    defer child_value.deinit();
    // Deep-copy the child into this document's arena: the stored value must
    // not alias the child document's tree.
    const arena = node_value.document.parsed.arena.allocator();
    const cloned = jsonValueClone(arena, child_value.value) catch |err| return finishErr(err);
    jsonObjectSetLocked(node, key, cloned) catch |err| return finishErr(err);
    return finish(SA_STD_OK);
}

pub export fn sa_json_object_remove(node: u64, key_ptr: ?[*]const u8, key_len: u64) i32 {
    const key = constBytes(key_ptr, key_len) catch |err| return finishErr(err);
    if (key.len == 0) return finish(SA_STD_ERR_INVALID_ARGUMENT);
    jsonObjectRemoveLocked(node, key) catch |err| return finishErr(err);
    return finish(SA_STD_OK);
}

pub export fn sa_json_array_push_string(node: u64, data_ptr: ?[*]const u8, data_len: u64) i32 {
    const data = constBytes(data_ptr, data_len) catch |err| return finishErr(err);
    var node_value = acquireJsonNode(node) catch |err| return finishErr(err);
    defer node_value.deinit();
    const arena = node_value.document.parsed.arena.allocator();
    const owned = arena.dupe(u8, data) catch |err| return finishErr(err);
    jsonArrayPushLocked(node, .{ .string = owned }) catch |err| return finishErr(err);
    return finish(SA_STD_OK);
}

pub export fn sa_json_array_push_i64(node: u64, value: i64) i32 {
    jsonArrayPushLocked(node, .{ .integer = value }) catch |err| return finishErr(err);
    return finish(SA_STD_OK);
}

pub export fn sa_json_array_push_f64(node: u64, value: f64) i32 {
    if (!std.math.isFinite(value)) return finish(SA_STD_ERR_INVALID_ARGUMENT);
    jsonArrayPushLocked(node, .{ .float = value }) catch |err| return finishErr(err);
    return finish(SA_STD_OK);
}

pub export fn sa_json_array_push_bool(node: u64, value: u8) i32 {
    jsonArrayPushLocked(node, .{ .bool = value != 0 }) catch |err| return finishErr(err);
    return finish(SA_STD_OK);
}

pub export fn sa_json_array_push_null(node: u64) i32 {
    jsonArrayPushLocked(node, .null) catch |err| return finishErr(err);
    return finish(SA_STD_OK);
}

pub export fn sa_json_array_push_node(node: u64, child: u64) i32 {
    var node_value = acquireJsonNode(node) catch |err| return finishErr(err);
    defer node_value.deinit();
    var child_value = acquireJsonNode(child) catch |err| return finishErr(err);
    defer child_value.deinit();
    const arena = node_value.document.parsed.arena.allocator();
    const cloned = jsonValueClone(arena, child_value.value) catch |err| return finishErr(err);
    jsonArrayPushLocked(node, cloned) catch |err| return finishErr(err);
    return finish(SA_STD_OK);
}

test "sa_json object set/get/enumerate/remove roundtrip" {
    const doc = "{\"a\":1,\"b\":\"x\"}";
    const root = sa_json_parse(doc.ptr, @intCast(doc.len));
    try std.testing.expect(root != 0);
    defer _ = sa_json_free(root);

    var count: u64 = 0;
    try std.testing.expectEqual(SA_STD_OK, sa_json_value_count(root, &count));
    try std.testing.expectEqual(@as(u64, 2), count);

    var key_ptr: ?[*]const u8 = null;
    var key_len: u64 = 0;
    try std.testing.expectEqual(SA_STD_OK, sa_json_object_key_at(root, 0, &key_ptr, &key_len));
    try std.testing.expectEqualStrings("a", key_ptr.?[0..@intCast(key_len)]);
    try std.testing.expectEqual(SA_STD_OK, sa_json_object_key_at(root, 1, &key_ptr, &key_len));
    try std.testing.expectEqualStrings("b", key_ptr.?[0..@intCast(key_len)]);

    try std.testing.expectEqual(SA_STD_OK, sa_json_object_set_string(root, "c", 1, "hello", 5));
    try std.testing.expectEqual(SA_STD_OK, sa_json_object_set_i64(root, "d", 1, 42));
    try std.testing.expectEqual(SA_STD_OK, sa_json_object_set_bool(root, "e", 1, 1));
    try std.testing.expectEqual(SA_STD_OK, sa_json_object_set_f64(root, "f", 1, 2.5));
    try std.testing.expectEqual(SA_STD_OK, sa_json_object_set_null(root, "g", 1));
    try std.testing.expectEqual(SA_STD_OK, sa_json_value_count(root, &count));
    try std.testing.expectEqual(@as(u64, 7), count);
    // Enumeration follows insertion order.
    try std.testing.expectEqual(SA_STD_OK, sa_json_object_key_at(root, 2, &key_ptr, &key_len));
    try std.testing.expectEqualStrings("c", key_ptr.?[0..@intCast(key_len)]);
    try std.testing.expectEqual(SA_STD_OK, sa_json_object_key_at(root, 6, &key_ptr, &key_len));
    try std.testing.expectEqualStrings("g", key_ptr.?[0..@intCast(key_len)]);

    var i64_out: i64 = 0;
    try std.testing.expectEqual(SA_STD_OK, sa_json_object_get_i64(root, "d", 1, &i64_out));
    try std.testing.expectEqual(@as(i64, 42), i64_out);
    var str_ptr: ?[*]const u8 = null;
    var str_len: u64 = 0;
    try std.testing.expectEqual(SA_STD_OK, sa_json_object_get_string(root, "c", 1, &str_ptr, &str_len));
    try std.testing.expectEqualStrings("hello", str_ptr.?[0..@intCast(str_len)]);
    var bool_out: u8 = 0;
    try std.testing.expectEqual(SA_STD_OK, sa_json_object_get_bool(root, "e", 1, &bool_out));
    try std.testing.expectEqual(@as(u8, 1), bool_out);
    var f64_out: f64 = 0;
    try std.testing.expectEqual(SA_STD_OK, sa_json_object_get_f64(root, "f", 1, &f64_out));
    try std.testing.expectEqual(@as(f64, 2.5), f64_out);
    var child: u64 = 0;
    try std.testing.expectEqual(SA_STD_OK, sa_json_object_get(root, "g", 1, &child));
    try std.testing.expectEqual(SA_JSON_KIND_NULL, sa_json_kind(child));
    _ = sa_json_free(child);

    // Overwriting an existing key keeps its count and position.
    try std.testing.expectEqual(SA_STD_OK, sa_json_object_set_i64(root, "a", 1, 7));
    try std.testing.expectEqual(SA_STD_OK, sa_json_value_count(root, &count));
    try std.testing.expectEqual(@as(u64, 7), count);
    try std.testing.expectEqual(SA_STD_OK, sa_json_object_key_at(root, 0, &key_ptr, &key_len));
    try std.testing.expectEqualStrings("a", key_ptr.?[0..@intCast(key_len)]);
    try std.testing.expectEqual(SA_STD_OK, sa_json_object_get_i64(root, "a", 1, &i64_out));
    try std.testing.expectEqual(@as(i64, 7), i64_out);

    // Removing a middle key preserves the order of the survivors.
    try std.testing.expectEqual(SA_STD_OK, sa_json_object_remove(root, "b", 1));
    try std.testing.expectEqual(SA_STD_OK, sa_json_value_count(root, &count));
    try std.testing.expectEqual(@as(u64, 6), count);
    try std.testing.expectEqual(SA_STD_OK, sa_json_object_key_at(root, 1, &key_ptr, &key_len));
    try std.testing.expectEqualStrings("c", key_ptr.?[0..@intCast(key_len)]);
    try std.testing.expect(sa_json_object_get_i64(root, "b", 1, &i64_out) != SA_STD_OK);
    try std.testing.expect(sa_json_object_remove(root, "b", 1) != SA_STD_OK);

    var buf: u64 = 0;
    try std.testing.expectEqual(SA_STD_OK, sa_json_stringify(root, &buf));
    defer _ = sa_json_buffer_free(buf);
    const text = sa_json_buffer_data(buf).?[0..@intCast(sa_json_buffer_len(buf))];
    try std.testing.expectEqualStrings("{\"a\":7,\"c\":\"hello\",\"d\":42,\"e\":true,\"f\":2.5,\"g\":null}", text);
}

test "sa_json array push appends in order" {
    const doc = "[]";
    const root = sa_json_parse(doc.ptr, @intCast(doc.len));
    try std.testing.expect(root != 0);
    defer _ = sa_json_free(root);

    try std.testing.expectEqual(SA_STD_OK, sa_json_array_push_i64(root, 1));
    try std.testing.expectEqual(SA_STD_OK, sa_json_array_push_string(root, "two", 3));
    try std.testing.expectEqual(SA_STD_OK, sa_json_array_push_bool(root, 1));
    try std.testing.expectEqual(SA_STD_OK, sa_json_array_push_f64(root, 2.5));
    try std.testing.expectEqual(SA_STD_OK, sa_json_array_push_null(root));

    const doc2 = "{\"k\":true}";
    const node2 = sa_json_parse(doc2.ptr, @intCast(doc2.len));
    try std.testing.expect(node2 != 0);
    defer _ = sa_json_free(node2);
    try std.testing.expectEqual(SA_STD_OK, sa_json_array_push_node(root, node2));

    var count: u64 = 0;
    try std.testing.expectEqual(SA_STD_OK, sa_json_value_count(root, &count));
    try std.testing.expectEqual(@as(u64, 6), count);
    var elem: u64 = 0;
    try std.testing.expectEqual(SA_STD_OK, sa_json_array_get(root, 0, &elem));
    var i64_out: i64 = 0;
    try std.testing.expectEqual(SA_STD_OK, sa_json_as_i64(elem, &i64_out));
    try std.testing.expectEqual(@as(i64, 1), i64_out);
    _ = sa_json_free(elem);
    try std.testing.expectEqual(SA_STD_OK, sa_json_array_get(root, 5, &elem));
    try std.testing.expectEqual(SA_JSON_KIND_OBJECT, sa_json_kind(elem));
    _ = sa_json_free(elem);

    var buf: u64 = 0;
    try std.testing.expectEqual(SA_STD_OK, sa_json_stringify(root, &buf));
    defer _ = sa_json_buffer_free(buf);
    const text = sa_json_buffer_data(buf).?[0..@intCast(sa_json_buffer_len(buf))];
    try std.testing.expectEqualStrings("[1,\"two\",true,2.5,null,{\"k\":true}]", text);

    // Wrong-kind targets are explicit errors, never silent no-ops.
    try std.testing.expect(sa_json_array_push_i64(node2, 1) != SA_STD_OK);
    try std.testing.expect(sa_json_object_set_i64(root, "x", 1, 1) != SA_STD_OK);
}

test "sa_json mutation is visible across handles; removed key detaches its handle" {
    const doc = "{\"outer\":{\"x\":1},\"list\":[]}";
    const root = sa_json_parse(doc.ptr, @intCast(doc.len));
    try std.testing.expect(root != 0);
    defer _ = sa_json_free(root);

    var outer: u64 = 0;
    try std.testing.expectEqual(SA_STD_OK, sa_json_object_get(root, "outer", 5, &outer));
    defer _ = sa_json_free(outer);
    try std.testing.expectEqual(SA_STD_OK, sa_json_object_set_string(outer, "y", 1, "z", 1));

    var list: u64 = 0;
    try std.testing.expectEqual(SA_STD_OK, sa_json_object_get(root, "list", 4, &list));
    defer _ = sa_json_free(list);
    try std.testing.expectEqual(SA_STD_OK, sa_json_array_push_i64(list, 7));
    try std.testing.expectEqual(SA_STD_OK, sa_json_array_push_string(list, "s", 1));

    const doc2 = "{\"n\":[1,2]}";
    const other = sa_json_parse(doc2.ptr, @intCast(doc2.len));
    try std.testing.expect(other != 0);
    defer _ = sa_json_free(other);
    try std.testing.expectEqual(SA_STD_OK, sa_json_object_set_node(root, "attached", 8, other));
    // set_node deep-copies: later mutation of the source document must not
    // leak into the attached copy.
    try std.testing.expectEqual(SA_STD_OK, sa_json_object_set_i64(other, "n", 1, 99));

    var buf: u64 = 0;
    try std.testing.expectEqual(SA_STD_OK, sa_json_stringify(root, &buf));
    const text = sa_json_buffer_data(buf).?[0..@intCast(sa_json_buffer_len(buf))];
    try std.testing.expectEqualStrings("{\"outer\":{\"x\":1,\"y\":\"z\"},\"list\":[7,\"s\"],\"attached\":{\"n\":[1,2]}}", text);
    _ = sa_json_buffer_free(buf);

    // Removing the key detaches the previously obtained child handle.
    try std.testing.expectEqual(SA_STD_OK, sa_json_object_remove(root, "outer", 5));
    try std.testing.expect(sa_json_object_set_string(outer, "q", 1, "v", 1) != SA_STD_OK);
    try std.testing.expectEqual(SA_JSON_KIND_INVALID, sa_json_kind(outer));
}

test "sa_json_kind returns the named SA_JSON_KIND values for each document kind" {
    // Locks the runtime kind values to the names published for
    // consumers (sa_std/encoding/json.sal for SA, sa_std.h for C, and
    // sa_std/encoding/json.sla for the SLA layer) so the layers cannot
    // drift apart. 1e999 is a NUMBER_STRING: the parser cannot
    // represent it as i64 or f64.
    const cases = .{
        .{ "null", SA_JSON_KIND_NULL },
        .{ "true", SA_JSON_KIND_BOOL },
        .{ "42", SA_JSON_KIND_INTEGER },
        .{ "1.5", SA_JSON_KIND_FLOAT },
        .{ "1e999", SA_JSON_KIND_NUMBER_STRING },
        .{ "\"s\"", SA_JSON_KIND_STRING },
        .{ "[1,2]", SA_JSON_KIND_ARRAY },
        .{ "{\"a\":1}", SA_JSON_KIND_OBJECT },
    };
    inline for (cases) |case| {
        const doc = sa_json_parse(case[0].ptr, @intCast(case[0].len));
        try std.testing.expect(doc != 0);
        defer _ = sa_json_free(doc);
        try std.testing.expectEqual(case[1], sa_json_kind(doc));
    }
    // An unknown handle reports INVALID, not a document kind.
    try std.testing.expectEqual(SA_JSON_KIND_INVALID, sa_json_kind(0));
}

test "sa_json_stream_next and writer whitespace return the named SA_JSON_TOKEN / SA_JSON_WHITESPACE values" {
    // Locks the stream token values and the writer whitespace
    // values to the names published for consumers
    // (sa_std/encoding/json.sal for SA, sa_std.h for C, and
    // sa_std/encoding/json.sla for the SLA layer) so the layers
    // cannot drift apart.
    const input = "{\"a\":[1,true,false,null,\"s\"]}";
    const stream = sa_json_stream_new(input.ptr, @intCast(input.len));
    try std.testing.expect(stream != 0);
    defer _ = sa_json_stream_free(stream);
    const expected = .{
        SA_JSON_TOKEN_OBJECT_BEGIN,
        SA_JSON_TOKEN_STRING,
        SA_JSON_TOKEN_ARRAY_BEGIN,
        SA_JSON_TOKEN_NUMBER,
        SA_JSON_TOKEN_TRUE,
        SA_JSON_TOKEN_FALSE,
        SA_JSON_TOKEN_NULL,
        SA_JSON_TOKEN_STRING,
        SA_JSON_TOKEN_ARRAY_END,
        SA_JSON_TOKEN_OBJECT_END,
        SA_JSON_TOKEN_END_OF_DOCUMENT,
    };
    inline for (expected) |want| {
        try std.testing.expectEqual(want, sa_json_stream_next(stream));
    }
    // An unknown stream handle reports INVALID, not a token kind.
    try std.testing.expectEqual(SA_JSON_TOKEN_INVALID, sa_json_stream_next(0));

    // Every named whitespace mode is accepted; anything else is
    // SA_STD_ERR_INVALID_ARGUMENT.
    const modes = .{
        SA_JSON_WHITESPACE_MINIFIED,
        SA_JSON_WHITESPACE_INDENT_1,
        SA_JSON_WHITESPACE_INDENT_2,
        SA_JSON_WHITESPACE_INDENT_3,
        SA_JSON_WHITESPACE_INDENT_4,
        SA_JSON_WHITESPACE_INDENT_8,
        SA_JSON_WHITESPACE_INDENT_TAB,
    };
    inline for (modes) |mode| {
        var writer: u64 = 0;
        try std.testing.expectEqual(SA_STD_OK, sa_json_writer_new(mode, 0, 0, 0, 0, &writer));
        try std.testing.expect(writer != 0);
        try std.testing.expectEqual(SA_STD_OK, sa_json_writer_free(writer));
    }
    var bad_writer: u64 = 0;
    try std.testing.expectEqual(SA_STD_ERR_INVALID_ARGUMENT, sa_json_writer_new(99, 0, 0, 0, 0, &bad_writer));
}

pub const sa_json_scanner_new = @import("json_io.zig").sa_json_scanner_new;

pub const sa_json_scanner_feed = @import("json_io.zig").sa_json_scanner_feed;

pub const sa_json_scanner_end_input = @import("json_io.zig").sa_json_scanner_end_input;

pub const sa_json_scanner_next = @import("json_io.zig").sa_json_scanner_next;

pub const sa_json_scanner_free = @import("json_io.zig").sa_json_scanner_free;

pub const sa_json_stream_new = @import("json_io.zig").sa_json_stream_new;

pub const sa_json_stream_next = @import("json_io.zig").sa_json_stream_next;

pub const sa_json_stream_get_slice_ptr = @import("json_io.zig").sa_json_stream_get_slice_ptr;

pub const sa_json_stream_get_slice_len = @import("json_io.zig").sa_json_stream_get_slice_len;

pub const sa_json_stream_free = @import("json_io.zig").sa_json_stream_free;

pub const sa_json_writer_free = @import("json_io.zig").sa_json_writer_free;

pub const sa_json_writer_new = @import("json_io.zig").sa_json_writer_new;

pub const sa_json_writer_begin_object = @import("json_io.zig").sa_json_writer_begin_object;

pub const sa_json_writer_end_object = @import("json_io.zig").sa_json_writer_end_object;

pub const sa_json_writer_begin_array = @import("json_io.zig").sa_json_writer_begin_array;

pub const sa_json_writer_end_array = @import("json_io.zig").sa_json_writer_end_array;

pub const sa_json_writer_object_field = @import("json_io.zig").sa_json_writer_object_field;

pub const sa_json_writer_field_string = @import("json_io.zig").sa_json_writer_field_string;

pub const sa_json_writer_field_bool = @import("json_io.zig").sa_json_writer_field_bool;

pub const sa_json_writer_field_i64 = @import("json_io.zig").sa_json_writer_field_i64;

pub const sa_json_writer_field_f64 = @import("json_io.zig").sa_json_writer_field_f64;

pub const sa_json_writer_field_null = @import("json_io.zig").sa_json_writer_field_null;

pub const sa_json_writer_field_node = @import("json_io.zig").sa_json_writer_field_node;

pub const sa_json_writer_write_bool = @import("json_io.zig").sa_json_writer_write_bool;

pub const sa_json_writer_write_i64 = @import("json_io.zig").sa_json_writer_write_i64;

pub const sa_json_writer_write_f64 = @import("json_io.zig").sa_json_writer_write_f64;

pub const sa_json_writer_write_string = @import("json_io.zig").sa_json_writer_write_string;

pub const sa_json_writer_write_null = @import("json_io.zig").sa_json_writer_write_null;

pub const sa_json_writer_write_node = @import("json_io.zig").sa_json_writer_write_node;

pub const sa_json_writer_finish = @import("json_io.zig").sa_json_writer_finish;

pub const sa_json_writer_finish_buffer = @import("json_io.zig").sa_json_writer_finish_buffer;

pub export fn sa_json_buffer_data(buffer: u64) ?[*]u8 {
    while (!sa_std.registry_mutex.tryLock()) {
        std.Thread.yield() catch {};
    }
    defer sa_std.registry_mutex.unlock();
    const resource = getResourceLocked(buffer) orelse return null;
    return switch (resource.*) {
        .json_buffer => |*json_buffer| json_buffer.bytes.ptr,
        else => null,
    };
}

pub export fn sa_json_buffer_len(buffer: u64) u64 {
    while (!sa_std.registry_mutex.tryLock()) {
        std.Thread.yield() catch {};
    }
    defer sa_std.registry_mutex.unlock();
    const resource = getResourceLocked(buffer) orelse return 0;
    return switch (resource.*) {
        .json_buffer => |json_buffer| @as(u64, @intCast(json_buffer.bytes.len)),
        else => 0,
    };
}

pub export fn sa_json_buffer_free(buffer: u64) Fallible(i32) {
    const status = sa_std_close(buffer);
    if (status != SA_STD_OK) return fail(i32, status);
    return ok(i32, 0);
}
