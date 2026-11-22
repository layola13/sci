const std = @import("std");
const sio = @import("sio");
const copyRuntimeArchiveToCwd = @import("helpers.zig").copyRuntimeArchiveToCwd;
const expectSuccess = @import("helpers.zig").expectSuccess;
const icu_demo_link_args = @import("helpers.zig").icu_demo_link_args;
const runCommand = @import("helpers.zig").runCommand;
const writeSource = @import("helpers.zig").writeSource;

test "sa_std json exports are usable from C" {
    var original_cwd = try sio.cwd().openDir(".", .{});
    defer original_cwd.close();
    var tmp = std.testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();

    const runtime_source = try original_cwd.realpathAlloc(std.testing.allocator, "src/runtime/sa_std.zig");
    defer std.testing.allocator.free(runtime_source);
    const pthread_host_source = try original_cwd.realpathAlloc(std.testing.allocator, "src/runtime/sa_pthread_host.c");
    defer std.testing.allocator.free(pthread_host_source);
    const include_dir = try original_cwd.realpathAlloc(std.testing.allocator, "src/runtime");
    defer std.testing.allocator.free(include_dir);

    try std.process.setCurrentDir(std.testing.io, tmp.dir);
    defer original_cwd.setAsCwd() catch {};

    const c_source =
        \\#include "sa_std.h"
        \\
        \\#include <stdint.h>
        \\
        \\#include <stdio.h>
        \\
        \\#include <string.h>
        \\
        \\int main(void) {
        \\    const uint8_t json[] = "{\"name\":\"sci\",\"count\":7,\"active\":true,\"nested\":[1,2,3],\"schema\":{\"type\":\"object\"}}";
        \\    const uint8_t key_name[] = "name";
        \\    const uint8_t key_count[] = "count";
        \\    const uint8_t key_active[] = "active";
        \\    const uint8_t key_nested[] = "nested";
        \\    const uint8_t needle[] = "\"name\":\"sci\"";
        \\    uint64_t root = 0;
        \\    uint64_t child = 0;
        \\    uint64_t nested_item = 0;
        \\    uint64_t buffer = 0;
        \\    uint64_t writer = 0;
        \\    uint64_t writer_buffer = 0;
        \\    uint64_t count = 0;
        \\    int64_t first_nested_i64 = 0;
        \\    double count_f64 = 0.0;
        \\    int64_t count_i64 = 0;
        \\    int64_t count_i64_direct = 0;
        \\    double count_f64_direct = 0.0;
        \\    uint8_t active = 0;
        \\    uint8_t found = 0;
        \\    uint8_t writer_found = 0;
        \\    uint32_t kind = 0;
        \\    const uint8_t *name_ptr = NULL;
        \\    uint64_t name_len = 0;
        \\    const uint8_t *key_ptr = NULL;
        \\    uint64_t key_len = 0;
        \\    const uint8_t *json_text = NULL;
        \\    uint64_t json_len = 0;
        \\    const uint8_t *writer_text = NULL;
        \\    uint64_t writer_len = 0;
        \\    const uint8_t writer_prefix[] = "{\"name\":\"sci\",\"active\":true,\"count\":7,\"ratio\":";
        \\    const uint8_t writer_schema[] = "\"schema\":{\"type\":\"object\"}";
        \\
        \\    root = sa_json_parse(json, sizeof(json) - 1);
        \\    if (root == 0) return 2;
        \\    kind = sa_json_kind(root);
        \\    if (kind != SA_JSON_KIND_OBJECT) return 3;
        \\
        \\    if (sa_json_object_get(root, key_name, sizeof(key_name) - 1, &child) != SA_STD_OK) return 4;
        \\    if (child == 0) return 5;
        \\    kind = sa_json_kind(child);
        \\    if (kind != SA_JSON_KIND_STRING) return 6;
        \\    name_ptr = sa_json_string_ptr(child);
        \\    name_len = sa_json_string_len(child);
        \\    if (name_ptr == NULL || name_len != 3 || memcmp(name_ptr, "sci", 3) != 0) return 7;
        \\    if (sa_json_free(child) != SA_STD_OK) return 8;
        \\
        \\    if (sa_json_object_get_string(root, key_name, sizeof(key_name) - 1, &name_ptr, &name_len) != SA_STD_OK) return 34;
        \\    if (name_ptr == NULL || name_len != 3 || memcmp(name_ptr, "sci", 3) != 0) return 35;
        \\
        \\    if (sa_json_object_get(root, key_count, sizeof(key_count) - 1, &child) != SA_STD_OK) return 9;
        \\    if (sa_json_as_f64(child, &count_f64) != SA_STD_OK) return 10;
        \\    if (sa_json_as_i64(child, &count_i64) != SA_STD_OK) return 11;
        \\    if (count_f64 != 7.0 || count_i64 != 7) return 12;
        \\    if (sa_json_free(child) != SA_STD_OK) return 13;
        \\    if (sa_json_object_get_i64(root, key_count, sizeof(key_count) - 1, &count_i64_direct) != SA_STD_OK) return 50;
        \\    if (sa_json_object_get_f64(root, key_count, sizeof(key_count) - 1, &count_f64_direct) != SA_STD_OK) return 51;
        \\    if (count_i64_direct != 7 || count_f64_direct != 7.0) return 52;
        \\
        \\    if (sa_json_object_get(root, key_active, sizeof(key_active) - 1, &child) != SA_STD_OK) return 14;
        \\    if (sa_json_as_bool(child, &active) != SA_STD_OK) return 15;
        \\    if (active != 1) return 16;
        \\    if (sa_json_free(child) != SA_STD_OK) return 17;
        \\    active = 0;
        \\    if (sa_json_object_get_bool(root, key_active, sizeof(key_active) - 1, &active) != SA_STD_OK) return 36;
        \\    if (active != 1) return 37;
        \\
        \\    if (sa_json_object_get(root, key_nested, sizeof(key_nested) - 1, &child) != SA_STD_OK) return 18;
        \\    if (sa_json_value_count(child, &count) != SA_STD_OK) return 19;
        \\    if (count != 3) return 20;
        \\    if (sa_json_array_get(child, 0, &nested_item) != SA_STD_OK) return 21;
        \\    if (sa_json_as_i64(nested_item, &first_nested_i64) != SA_STD_OK) return 22;
        \\    if (first_nested_i64 != 1) return 23;
        \\    if (sa_json_free(nested_item) != SA_STD_OK) return 24;
        \\    if (sa_json_free(child) != SA_STD_OK) return 25;
        \\
        \\    if (sa_json_object_key_at(root, 0, &key_ptr, &key_len) != SA_STD_OK) return 26;
        \\    if (key_ptr == NULL || key_len != 4 || memcmp(key_ptr, "name", 4) != 0) return 27;
        \\
        \\    if (sa_json_stringify(root, &buffer) != SA_STD_OK) return 28;
        \\    if (buffer == 0) return 29;
        \\    json_text = sa_json_buffer_data(buffer);
        \\    json_len = sa_json_buffer_len(buffer);
        \\    if (json_text == NULL || json_len == 0) return 30;
        \\    if (json_len < sizeof(needle) - 1) return 31;
        \\    for (uint64_t i = 0; i + (uint64_t)(sizeof(needle) - 1) <= json_len; ++i) {
        \\        if (memcmp(json_text + i, needle, sizeof(needle) - 1) == 0) {
        \\            found = 1;
        \\            break;
        \\        }
        \\    }
        \\    if (!found) return 31;
        \\    if (sa_json_buffer_free(buffer) != SA_STD_OK) return 32;
        \\
        \\    if (sa_json_writer_new(SA_JSON_WHITESPACE_MINIFIED, 1, 0, 0, 0, &writer) != SA_STD_OK) return 38;
        \\    if (sa_json_writer_begin_object(writer) != SA_STD_OK) return 39;
        \\    if (sa_json_writer_field_string(writer, (const uint8_t *)"name", 4, (const uint8_t *)"sci", 3) != SA_STD_OK) return 53;
        \\    if (sa_json_writer_field_bool(writer, (const uint8_t *)"active", 6, 1) != SA_STD_OK) return 54;
        \\    if (sa_json_writer_field_i64(writer, (const uint8_t *)"count", 5, 7) != SA_STD_OK) return 55;
        \\    if (sa_json_writer_field_f64(writer, (const uint8_t *)"ratio", 5, 1.5) != SA_STD_OK) return 56;
        \\    if (sa_json_writer_field_null(writer, (const uint8_t *)"nothing", 7) != SA_STD_OK) return 57;
        \\    if (sa_json_object_get(root, (const uint8_t *)"schema", 6, &child) != SA_STD_OK) return 41;
        \\    if (sa_json_writer_field_node(writer, (const uint8_t *)"schema", 6, child) != SA_STD_OK) return 42;
        \\    if (sa_json_free(child) != SA_STD_OK) return 43;
        \\    if (sa_json_writer_end_object(writer) != SA_STD_OK) return 44;
        \\    if (sa_json_writer_finish(writer, &writer_buffer) != SA_STD_OK) return 45;
        \\    writer_text = sa_json_buffer_data(writer_buffer);
        \\    writer_len = sa_json_buffer_len(writer_buffer);
        \\    if (writer_text == NULL || writer_len < sizeof(writer_prefix) - 1) return 46;
        \\    if (memcmp(writer_text, writer_prefix, sizeof(writer_prefix) - 1) != 0) return 47;
        \\    for (uint64_t i = 0; i + (uint64_t)(sizeof(writer_schema) - 1) <= writer_len; ++i) {
        \\        if (memcmp(writer_text + i, writer_schema, sizeof(writer_schema) - 1) == 0) {
        \\            writer_found = 1;
        \\            break;
        \\        }
        \\    }
        \\    if (!writer_found) return 58;
        \\    if (sa_json_buffer_free(writer_buffer) != SA_STD_OK) return 48;
        \\    if (sa_json_writer_free(writer) != SA_STD_OK) return 49;
        \\
        \\    if (sa_json_free(root) != SA_STD_OK) return 33;
        \\    puts("sa_std json ok");
        \\    return 0;
        \\}
        \\
    ;
    try writeSource(tmp.dir, "json.c", c_source);

    try copyRuntimeArchiveToCwd();

    const build_demo_argv = [_][]const u8{
        "zig",
        "cc",
        "-I",
        include_dir,
        "json.c",
        "libsa_std.a",
        "-lc",
        "-o",
        "sa_std_json_demo",
    } ++ icu_demo_link_args;
    const build_demo_result = try runCommand(std.testing.allocator, build_demo_argv[0..]);
    defer std.testing.allocator.free(build_demo_result.stdout);
    defer std.testing.allocator.free(build_demo_result.stderr);
    try expectSuccess(build_demo_result);

    const run_result = try runCommand(std.testing.allocator, &.{"./sa_std_json_demo"});
    defer std.testing.allocator.free(run_result.stdout);
    defer std.testing.allocator.free(run_result.stderr);
    try expectSuccess(run_result);
    try std.testing.expect(std.mem.containsAtLeast(u8, run_result.stdout, 1, "sa_std json ok"));
}

test "sa_std json streaming scanner and writer are usable from C" {
    var original_cwd = try sio.cwd().openDir(".", .{});
    defer original_cwd.close();
    var tmp = std.testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();

    const runtime_source = try original_cwd.realpathAlloc(std.testing.allocator, "src/runtime/sa_std.zig");
    defer std.testing.allocator.free(runtime_source);
    const pthread_host_source = try original_cwd.realpathAlloc(std.testing.allocator, "src/runtime/sa_pthread_host.c");
    defer std.testing.allocator.free(pthread_host_source);
    const include_dir = try original_cwd.realpathAlloc(std.testing.allocator, "src/runtime");
    defer std.testing.allocator.free(include_dir);

    try std.process.setCurrentDir(std.testing.io, tmp.dir);
    defer original_cwd.setAsCwd() catch {};

    const c_source =
        \\#include "sa_std.h"
        \\
        \\#include <stdint.h>
        \\#include <stdio.h>
        \\#include <string.h>
        \\
        \\int main(void) {
        \\    const uint8_t chunk1[] = "{\"name\":\"s";
        \\    const uint8_t chunk2[] = "ci\",\"count\":";
        \\    const uint8_t chunk3[] = "7}";
        \\    uint64_t scanner = 0;
        \\    uint64_t writer = 0;
        \\    uint64_t buffer = 0;
        \\    SaJsonToken token = {0};
        \\    const uint8_t *json = NULL;
        \\    uint64_t json_len = 0;
        \\
        \\    if (sa_json_scanner_new(&scanner) != SA_STD_OK) return 2;
        \\    if (scanner == 0) return 3;
        \\    if (sa_json_scanner_feed(scanner, chunk1, sizeof(chunk1) - 1) != SA_STD_OK) return 4;
        \\    if (sa_json_scanner_next(scanner, &token) != SA_STD_OK || token.kind != SA_JSON_TOKEN_OBJECT_BEGIN) return 5;
        \\    if (sa_json_scanner_next(scanner, &token) != SA_STD_OK || token.kind != SA_JSON_TOKEN_STRING || token.text_len != 4 || memcmp(token.text_ptr, "name", 4) != 0) return 6;
        \\    if (sa_json_scanner_next(scanner, &token) != SA_STD_OK || token.kind != SA_JSON_TOKEN_PARTIAL_STRING || token.text_len != 1 || memcmp(token.text_ptr, "s", 1) != 0) return 7;
        \\    if (sa_json_scanner_feed(scanner, chunk2, sizeof(chunk2) - 1) != SA_STD_OK) return 8;
        \\    if (sa_json_scanner_next(scanner, &token) != SA_STD_OK || token.kind != SA_JSON_TOKEN_STRING || token.text_len != 2 || memcmp(token.text_ptr, "ci", 2) != 0) return 9;
        \\    if (sa_json_scanner_next(scanner, &token) != SA_STD_OK || token.kind != SA_JSON_TOKEN_STRING || token.text_len != 5 || memcmp(token.text_ptr, "count", 5) != 0) return 10;
        \\    if (sa_json_scanner_next(scanner, &token) != SA_STD_ERR_TRUNCATED) return 11;
        \\    if (sa_json_scanner_feed(scanner, chunk3, sizeof(chunk3) - 1) != SA_STD_OK) return 12;
        \\    if (sa_json_scanner_next(scanner, &token) != SA_STD_OK || token.kind != SA_JSON_TOKEN_NUMBER || token.text_len != 1 || memcmp(token.text_ptr, "7", 1) != 0) return 13;
        \\    if (sa_json_scanner_next(scanner, &token) != SA_STD_OK || token.kind != SA_JSON_TOKEN_OBJECT_END) return 14;
        \\    if (sa_json_scanner_end_input(scanner) != SA_STD_OK) return 15;
        \\    if (sa_json_scanner_next(scanner, &token) != SA_STD_OK || token.kind != SA_JSON_TOKEN_END_OF_DOCUMENT) return 16;
        \\    if (sa_json_scanner_free(scanner) != SA_STD_OK) return 17;
        \\
        \\    if (sa_json_writer_new(SA_JSON_WHITESPACE_MINIFIED, 1, 0, 0, 0, &writer) != SA_STD_OK) return 18;
        \\    if (writer == 0) return 19;
        \\    if (sa_json_writer_begin_object(writer) != SA_STD_OK) return 20;
        \\    if (sa_json_writer_object_field(writer, (const uint8_t *)"name", 4) != SA_STD_OK) return 21;
        \\    if (sa_json_writer_write_string(writer, (const uint8_t *)"sci", 3) != SA_STD_OK) return 22;
        \\    if (sa_json_writer_object_field(writer, (const uint8_t *)"count", 5) != SA_STD_OK) return 23;
        \\    if (sa_json_writer_write_i64(writer, 7) != SA_STD_OK) return 24;
        \\    if (sa_json_writer_end_object(writer) != SA_STD_OK) return 25;
        \\    if (sa_json_writer_finish(writer, &buffer) != SA_STD_OK) return 26;
        \\    if (buffer == 0) return 27;
        \\    json = sa_json_buffer_data(buffer);
        \\    json_len = sa_json_buffer_len(buffer);
        \\    if (json == NULL || json_len == 0) return 28;
        \\    if (memcmp(json, "{\"name\":\"sci\",\"count\":7}", json_len) != 0) return 29;
        \\    if (sa_json_writer_finish(writer, &buffer) != SA_STD_OK) return 30;
        \\    if (sa_json_buffer_free(buffer) != SA_STD_OK) return 31;
        \\    if (sa_json_writer_free(writer) != SA_STD_OK) return 32;
        \\    puts("sa_std json streaming ok");
        \\    return 0;
        \\}
        \\
    ;
    try writeSource(tmp.dir, "json_stream.c", c_source);

    try copyRuntimeArchiveToCwd();

    const build_demo_argv = [_][]const u8{
        "zig",
        "cc",
        "-I",
        include_dir,
        "json_stream.c",
        "libsa_std.a",
        "-lc",
        "-o",
        "sa_std_json_stream_demo",
    } ++ icu_demo_link_args;
    const build_demo_result = try runCommand(std.testing.allocator, build_demo_argv[0..]);
    defer std.testing.allocator.free(build_demo_result.stdout);
    defer std.testing.allocator.free(build_demo_result.stderr);
    try expectSuccess(build_demo_result);

    const run_result = try runCommand(std.testing.allocator, &.{"./sa_std_json_stream_demo"});
    defer std.testing.allocator.free(run_result.stdout);
    defer std.testing.allocator.free(run_result.stderr);
    try expectSuccess(run_result);
    try std.testing.expect(std.mem.containsAtLeast(u8, run_result.stdout, 1, "sa_std json streaming ok"));
}

test "sa_std json streaming handle exposes stable slices from C" {
    var original_cwd = try sio.cwd().openDir(".", .{});
    defer original_cwd.close();
    var tmp = std.testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();

    const runtime_source = try original_cwd.realpathAlloc(std.testing.allocator, "src/runtime/sa_std.zig");
    defer std.testing.allocator.free(runtime_source);
    const pthread_host_source = try original_cwd.realpathAlloc(std.testing.allocator, "src/runtime/sa_pthread_host.c");
    defer std.testing.allocator.free(pthread_host_source);
    const include_dir = try original_cwd.realpathAlloc(std.testing.allocator, "src/runtime");
    defer std.testing.allocator.free(include_dir);

    try std.process.setCurrentDir(std.testing.io, tmp.dir);
    defer original_cwd.setAsCwd() catch {};

    const c_source =
        \\#include "sa_std.h"
        \\
        \\#include <stdint.h>
        \\#include <stdio.h>
        \\#include <string.h>
        \\
        \\int main(void) {
        \\    const uint8_t json[] = "{\"name\":\"sci\",\"count\":7}";
        \\    uint64_t stream = 0;
        \\    uint32_t token = 0;
        \\    const uint8_t *slice = NULL;
        \\    uint64_t slice_len = 0;
        \\
        \\    stream = sa_json_stream_new(json, sizeof(json) - 1);
        \\    if (stream == 0) return 2;
        \\    token = sa_json_stream_next(stream);
        \\    if (token != SA_JSON_TOKEN_OBJECT_BEGIN) return 3;
        \\    token = sa_json_stream_next(stream);
        \\    if (token != SA_JSON_TOKEN_STRING) return 4;
        \\    slice = sa_json_stream_get_slice_ptr(stream);
        \\    slice_len = sa_json_stream_get_slice_len(stream);
        \\    if (slice == NULL || slice_len != 4 || memcmp(slice, "name", 4) != 0) return 5;
        \\    token = sa_json_stream_next(stream);
        \\    if (token != SA_JSON_TOKEN_STRING) return 6;
        \\    slice = sa_json_stream_get_slice_ptr(stream);
        \\    slice_len = sa_json_stream_get_slice_len(stream);
        \\    if (slice == NULL || slice_len != 3 || memcmp(slice, "sci", 3) != 0) return 7;
        \\    token = sa_json_stream_next(stream);
        \\    if (token != SA_JSON_TOKEN_STRING) return 8;
        \\    slice = sa_json_stream_get_slice_ptr(stream);
        \\    slice_len = sa_json_stream_get_slice_len(stream);
        \\    if (slice == NULL || slice_len != 5 || memcmp(slice, "count", 5) != 0) return 9;
        \\    token = sa_json_stream_next(stream);
        \\    if (token != SA_JSON_TOKEN_NUMBER) return 10;
        \\    slice = sa_json_stream_get_slice_ptr(stream);
        \\    slice_len = sa_json_stream_get_slice_len(stream);
        \\    if (slice == NULL || slice_len != 1 || memcmp(slice, "7", 1) != 0) return 11;
        \\    token = sa_json_stream_next(stream);
        \\    if (token != SA_JSON_TOKEN_OBJECT_END) return 12;
        \\    token = sa_json_stream_next(stream);
        \\    if (token != SA_JSON_TOKEN_END_OF_DOCUMENT) return 13;
        \\    if (sa_json_stream_free(stream) != SA_STD_OK) return 14;
        \\    puts("sa_std json stream ok");
        \\    return 0;
        \\}
        \\
    ;
    try writeSource(tmp.dir, "json_stream_direct.c", c_source);

    try copyRuntimeArchiveToCwd();

    const build_demo_argv = [_][]const u8{
        "zig",
        "cc",
        "-I",
        include_dir,
        "json_stream_direct.c",
        "libsa_std.a",
        "-lc",
        "-o",
        "sa_std_json_stream_direct_demo",
    } ++ icu_demo_link_args;
    const build_demo_result = try runCommand(std.testing.allocator, build_demo_argv[0..]);
    defer std.testing.allocator.free(build_demo_result.stdout);
    defer std.testing.allocator.free(build_demo_result.stderr);
    try expectSuccess(build_demo_result);

    const run_result = try runCommand(std.testing.allocator, &.{"./sa_std_json_stream_direct_demo"});
    defer std.testing.allocator.free(run_result.stdout);
    defer std.testing.allocator.free(run_result.stderr);
    try expectSuccess(run_result);
    try std.testing.expect(std.mem.containsAtLeast(u8, run_result.stdout, 1, "sa_std json stream ok"));
}
