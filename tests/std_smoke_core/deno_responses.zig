//! Deno native responses / request fallbacks -- split from tests/std_smoke_core.zig (shared helpers: helpers.zig).
const std = @import("std");
const common = @import("../std_smoke_common.zig");
const sio = @import("sio");
const saasm = common.saasm;
const flattenFixture = @import("helpers.zig").flattenFixture;

test "sa_std Deno native responses JSON preserves ordinary responses and normalizes thinking" {
    var original_cwd = try sio.cwd().openDir(".", .{});
    defer original_cwd.close();
    var tmp = std.testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();

    const runtime_source = try sio.cwd().realpathAlloc(std.testing.allocator, "src/runtime/sa_std.zig");
    defer std.testing.allocator.free(runtime_source);
    const pthread_host_source = try sio.cwd().realpathAlloc(std.testing.allocator, "src/runtime/sa_pthread_host.c");
    defer std.testing.allocator.free(pthread_host_source);
    const include_dir = try sio.cwd().realpathAlloc(std.testing.allocator, "src/runtime");
    defer std.testing.allocator.free(include_dir);

    try std.process.setCurrentDir(std.testing.io, tmp.dir);
    defer original_cwd.setAsCwd() catch {};

    const c_source =
        \\#include "sa_std.h"
        \\#include <stdint.h>
        \\#include <stdio.h>
        \\#include <string.h>
        \\
        \\static int has(uint8_t *data, uint64_t len, const char *needle) {
        \\    size_t nlen = strlen(needle);
        \\    if (nlen == 0) return 1;
        \\    if (len < nlen) return 0;
        \\    for (uint64_t i = 0; i <= len - nlen; i++) {
        \\        if (memcmp(data + i, needle, nlen) == 0) return 1;
        \\    }
        \\    return 0;
        \\}
        \\
        \\static int check(uint64_t h, const char *needle) {
        \\    uint8_t *data = sa_fs_read_buffer_data(h);
        \\    uint64_t len = sa_fs_read_buffer_len(h);
        \\    if (h == 0 || data == NULL || len == 0) return 0;
        \\    return has(data, len, needle);
        \\}
        \\
        \\int main(void) {
        \\    const uint8_t ordinary[] = "{\"output\":[],\"status\":\"completed\"}";
        \\    const uint8_t thinking[] = "{\"id\":\"resp_1\",\"output\":[{\"type\":\"message\",\"role\":\"assistant\",\"thinking\":\"private\",\"content\":[{\"type\":\"output_text\",\"text\":\"answer\"}]}],\"output_text\":\"answer\",\"status\":\"completed\"}";
        \\
        \\    uint64_t h = sa_deno_responses_json_normalize(ordinary, sizeof(ordinary) - 1);
        \\    if (!check(h, "\"output\":[]") || !check(h, "\"status\":\"completed\"")) return 2;
        \\    if (check(h, "\"output_text\":\"\"")) return 3;
        \\    if (sa_fs_read_buffer_free(h) != SA_STD_OK) return 4;
        \\
        \\    h = sa_deno_responses_json_normalize(thinking, sizeof(thinking) - 1);
        \\    if (!check(h, "\"type\":\"reasoning\"") || !check(h, "private") || !check(h, "\"output_text\":\"answer\"")) return 5;
        \\    if (sa_fs_read_buffer_free(h) != SA_STD_OK) return 6;
        \\
        \\    puts("sa_std deno responses json normalize ok");
        \\    return 0;
        \\}
        \\
    ;
    try common.writeSource(tmp.dir, "main.c", c_source);
    const build_lib_result = try common.runCommand(std.testing.allocator, &.{
        "zig",
        "build-lib",
        runtime_source,
        pthread_host_source,
        "-O",
        "Debug",
        "-lc",
        "-femit-bin=libsa_std.a",
    });
    defer std.testing.allocator.free(build_lib_result.stdout);
    defer std.testing.allocator.free(build_lib_result.stderr);
    try std.testing.expectEqual(@as(u8, 0), switch (build_lib_result.term) {
        .exited => |code| code,
        else => return error.TestUnexpectedResult,
    });

    const build_demo_result = try common.runCommand(std.testing.allocator, &.{
        "zig",
        "cc",
        "-I",
        include_dir,
        "main.c",
        "libsa_std.a",
        "-lc",
        "-o",
        "sa_std_deno_responses_json_normalize",
    });
    defer std.testing.allocator.free(build_demo_result.stdout);
    defer std.testing.allocator.free(build_demo_result.stderr);
    try std.testing.expectEqual(@as(u8, 0), switch (build_demo_result.term) {
        .exited => |code| code,
        else => return error.TestUnexpectedResult,
    });

    const run_result = try common.runCommand(std.testing.allocator, &.{"./sa_std_deno_responses_json_normalize"});
    defer std.testing.allocator.free(run_result.stdout);
    defer std.testing.allocator.free(run_result.stderr);
    try std.testing.expectEqual(@as(u8, 0), switch (run_result.term) {
        .exited => |code| code,
        else => return error.TestUnexpectedResult,
    });
    try std.testing.expectEqualStrings("sa_std deno responses json normalize ok\n", run_result.stdout);
}

test "sa_std Deno native responses SSE normalizes MCP events generically" {
    var original_cwd = try sio.cwd().openDir(".", .{});
    defer original_cwd.close();
    var tmp = std.testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();

    const runtime_source = try sio.cwd().realpathAlloc(std.testing.allocator, "src/runtime/sa_std.zig");
    defer std.testing.allocator.free(runtime_source);
    const pthread_host_source = try sio.cwd().realpathAlloc(std.testing.allocator, "src/runtime/sa_pthread_host.c");
    defer std.testing.allocator.free(pthread_host_source);
    const include_dir = try sio.cwd().realpathAlloc(std.testing.allocator, "src/runtime");
    defer std.testing.allocator.free(include_dir);

    try std.process.setCurrentDir(std.testing.io, tmp.dir);
    defer original_cwd.setAsCwd() catch {};

    const c_source =
        \\#include "sa_std.h"
        \\#include <stdint.h>
        \\#include <stdio.h>
        \\#include <string.h>
        \\
        \\static int has(uint8_t *data, uint64_t len, const char *needle) {
        \\    size_t nlen = strlen(needle);
        \\    if (nlen == 0) return 1;
        \\    if (len < nlen) return 0;
        \\    for (uint64_t i = 0; i <= len - nlen; i++) {
        \\        if (memcmp(data + i, needle, nlen) == 0) return 1;
        \\    }
        \\    return 0;
        \\}
        \\
        \\int main(void) {
        \\    const uint8_t sse[] =
        \\        "event: response.output_item.added\n"
        \\        "data: {\"type\":\"response.output_item.added\",\"item\":{\"id\":\"tc_search\",\"type\":\"function_call\",\"name\":\"mcp__code_index__search\",\"arguments\":\"{\\\"query\\\":\\\"hello\\\"}\"}}\n\n"
        \\        "event: response.output_item.done\n"
        \\        "data: {\"type\":\"response.output_item.done\",\"item\":{\"id\":\"tc_read\",\"type\":\"function_call\",\"name\":\"mcp__code_index__.read_mcp_resource\",\"arguments\":\"{\\\"server\\\":\\\"code_index\\\",\\\"uri\\\":\\\"file:///foo\\\"}\"}}\n\n"
        \\        "event: response.output_item.done\n"
        \\        "data: {\"type\":\"response.output_item.done\",\"item\":{\"id\":\"tc_custom\",\"type\":\"function_call\",\"name\":\"mcp__custom_tool__some_tool\",\"arguments\":\"{\\\"server\\\":\\\"mcp__custom_tool__\\\"}\"}}\n\n"
        \\        "event: response.completed\n"
        \\        "data: {\"type\":\"response.completed\",\"response\":{\"id\":\"resp\",\"status\":\"completed\"}}\n\n";
        \\    uint64_t h = sa_deno_responses_sse_normalize(sse, sizeof(sse) - 1);
        \\    uint8_t *data = sa_fs_read_buffer_data(h);
        \\    uint64_t len = sa_fs_read_buffer_len(h);
        \\    if (h == 0 || data == NULL || len == 0) return 2;
        \\    if (!has(data, len, "\"namespace\":\"mcp__code_index__\"")) return 3;
        \\    if (!has(data, len, "\"name\":\"search\"")) return 4;
        \\    if (!has(data, len, "\"name\":\"read_mcp_resource\"")) return 5;
        \\    if (!has(data, len, "\\\"server\\\":\\\"code-index\\\"")) return 6;
        \\    if (!has(data, len, "\"namespace\":\"mcp__custom_tool__\"")) return 7;
        \\    if (!has(data, len, "\"name\":\"some_tool\"")) return 8;
        \\    if (!has(data, len, "\\\"server\\\":\\\"custom-tool\\\"")) return 9;
        \\    if (!has(data, len, "\"output_kind\":\"function_call_output\"")) return 10;
        \\    if (has(data, len, "\"name\":\"mcp__code_index__search\"")) return 11;
        \\    if (has(data, len, "\"name\":\"mcp__custom_tool__some_tool\"")) return 12;
        \\    if (sa_fs_read_buffer_free(h) != SA_STD_OK) return 13;
        \\    puts("sa_std deno responses sse normalize ok");
        \\    return 0;
        \\}
        \\
    ;
    try common.writeSource(tmp.dir, "main.c", c_source);
    const build_lib_result = try common.runCommand(std.testing.allocator, &.{
        "zig",
        "build-lib",
        runtime_source,
        pthread_host_source,
        "-O",
        "Debug",
        "-lc",
        "-femit-bin=libsa_std.a",
    });
    defer std.testing.allocator.free(build_lib_result.stdout);
    defer std.testing.allocator.free(build_lib_result.stderr);
    try std.testing.expectEqual(@as(u8, 0), switch (build_lib_result.term) {
        .exited => |code| code,
        else => return error.TestUnexpectedResult,
    });

    const build_demo_result = try common.runCommand(std.testing.allocator, &.{
        "zig",
        "cc",
        "-I",
        include_dir,
        "main.c",
        "libsa_std.a",
        "-lc",
        "-o",
        "sa_std_deno_responses_sse_normalize",
    });
    defer std.testing.allocator.free(build_demo_result.stdout);
    defer std.testing.allocator.free(build_demo_result.stderr);
    try std.testing.expectEqual(@as(u8, 0), switch (build_demo_result.term) {
        .exited => |code| code,
        else => return error.TestUnexpectedResult,
    });

    const run_result = try common.runCommand(std.testing.allocator, &.{"./sa_std_deno_responses_sse_normalize"});
    defer std.testing.allocator.free(run_result.stdout);
    defer std.testing.allocator.free(run_result.stderr);
    try std.testing.expectEqual(@as(u8, 0), switch (run_result.term) {
        .exited => |code| code,
        else => return error.TestUnexpectedResult,
    });
    try std.testing.expectEqualStrings("sa_std deno responses sse normalize ok\n", run_result.stdout);
}

test "sa_std Deno responses request normalizes MCP server aliases generically" {
    var original_cwd = try sio.cwd().openDir(".", .{});
    defer original_cwd.close();
    var tmp = std.testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();

    const runtime_source = try sio.cwd().realpathAlloc(std.testing.allocator, "src/runtime/sa_std.zig");
    defer std.testing.allocator.free(runtime_source);
    const pthread_host_source = try sio.cwd().realpathAlloc(std.testing.allocator, "src/runtime/sa_pthread_host.c");
    defer std.testing.allocator.free(pthread_host_source);
    const include_dir = try sio.cwd().realpathAlloc(std.testing.allocator, "src/runtime");
    defer std.testing.allocator.free(include_dir);

    try std.process.setCurrentDir(std.testing.io, tmp.dir);
    defer original_cwd.setAsCwd() catch {};

    const c_source =
        \\#include "sa_std.h"
        \\#include <stdint.h>
        \\#include <stdio.h>
        \\#include <string.h>
        \\
        \\static int has(uint8_t *data, uint64_t len, const char *needle) {
        \\    size_t nlen = strlen(needle);
        \\    if (nlen == 0) return 1;
        \\    if (len < nlen) return 0;
        \\    for (uint64_t i = 0; i <= len - nlen; i++) {
        \\        if (memcmp(data + i, needle, nlen) == 0) return 1;
        \\    }
        \\    return 0;
        \\}
        \\
        \\int main(void) {
        \\    const uint8_t body[] =
        \\        "{\"model\":\"m\",\"input\":["
        \\        "{\"type\":\"function_call\",\"name\":\"read_mcp_resource\",\"arguments\":\"{\\\"server\\\":\\\"Code Index\\\",\\\"uri\\\":\\\"file:///one\\\"}\"},"
        \\        "{\"type\":\"function_call\",\"name\":\"read_mcp_resource\",\"arguments\":\"{\\\"server\\\":\\\"mcp__mcp_code_index___\\\",\\\"uri\\\":\\\"file:///two\\\"}\"},"
        \\        "{\"type\":\"function_call\",\"name\":\"read_mcp_resource\",\"arguments\":\"{\\\"server\\\":\\\"Mimir\\\",\\\"uri\\\":\\\"file:///three\\\"}\"},"
        \\        "{\"type\":\"function_call\",\"name\":\"read_mcp_resource\",\"arguments\":\"{\\\"server\\\":\\\"Custom Tool\\\",\\\"uri\\\":\\\"file:///four\\\"}\"},"
        \\        "{\"type\":\"message\",\"role\":\"user\",\"content\":[{\"type\":\"input_text\",\"text\":\"Code Index should remain visible text\"}]}"
        \\        "]}";
        \\    uint64_t h = sa_deno_responses_request_normalize(body, sizeof(body) - 1);
        \\    uint8_t *data = sa_fs_read_buffer_data(h);
        \\    uint64_t len = sa_fs_read_buffer_len(h);
        \\    if (h == 0 || data == NULL || len == 0) return 2;
        \\    if (!has(data, len, "\\\"server\\\":\\\"mcp__code_index__\\\"")) return 3;
        \\    if (!has(data, len, "\\\"server\\\":\\\"mcp__mimir__\\\"")) return 4;
        \\    if (!has(data, len, "\\\"server\\\":\\\"mcp__custom_tool__\\\"")) return 5;
        \\    if (!has(data, len, "Code Index should remain visible text")) return 6;
        \\    if (has(data, len, "mcp__mcp_code_index___")) return 7;
        \\    if (sa_fs_read_buffer_free(h) != SA_STD_OK) return 8;
        \\    puts("sa_std deno responses request normalize ok");
        \\    return 0;
        \\}
        \\
    ;
    try common.writeSource(tmp.dir, "main.c", c_source);
    const build_lib_result = try common.runCommand(std.testing.allocator, &.{
        "zig",
        "build-lib",
        runtime_source,
        pthread_host_source,
        "-O",
        "Debug",
        "-lc",
        "-femit-bin=libsa_std.a",
    });
    defer std.testing.allocator.free(build_lib_result.stdout);
    defer std.testing.allocator.free(build_lib_result.stderr);
    try std.testing.expectEqual(@as(u8, 0), switch (build_lib_result.term) {
        .exited => |code| code,
        else => return error.TestUnexpectedResult,
    });

    const build_demo_result = try common.runCommand(std.testing.allocator, &.{
        "zig",
        "cc",
        "-I",
        include_dir,
        "main.c",
        "libsa_std.a",
        "-lc",
        "-o",
        "sa_std_deno_responses_request_normalize",
    });
    defer std.testing.allocator.free(build_demo_result.stdout);
    defer std.testing.allocator.free(build_demo_result.stderr);
    try std.testing.expectEqual(@as(u8, 0), switch (build_demo_result.term) {
        .exited => |code| code,
        else => return error.TestUnexpectedResult,
    });

    const run_result = try common.runCommand(std.testing.allocator, &.{"./sa_std_deno_responses_request_normalize"});
    defer std.testing.allocator.free(run_result.stdout);
    defer std.testing.allocator.free(run_result.stderr);
    try std.testing.expectEqual(@as(u8, 0), switch (run_result.term) {
        .exited => |code| code,
        else => return error.TestUnexpectedResult,
    });
    try std.testing.expectEqualStrings("sa_std deno responses request normalize ok\n", run_result.stdout);
}

test "sa_std Deno responses chat fallback request builds chat body from Responses input arrays" {
    var original_cwd = try sio.cwd().openDir(".", .{});
    defer original_cwd.close();
    var tmp = std.testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();

    const runtime_source = try sio.cwd().realpathAlloc(std.testing.allocator, "src/runtime/sa_std.zig");
    defer std.testing.allocator.free(runtime_source);
    const pthread_host_source = try sio.cwd().realpathAlloc(std.testing.allocator, "src/runtime/sa_pthread_host.c");
    defer std.testing.allocator.free(pthread_host_source);
    const include_dir = try sio.cwd().realpathAlloc(std.testing.allocator, "src/runtime");
    defer std.testing.allocator.free(include_dir);

    try std.process.setCurrentDir(std.testing.io, tmp.dir);
    defer original_cwd.setAsCwd() catch {};

    const c_source =
        \\#include "sa_std.h"
        \\#include <stdint.h>
        \\#include <stdio.h>
        \\#include <string.h>
        \\
        \\static int has(uint8_t *data, uint64_t len, const char *needle) {
        \\    size_t nlen = strlen(needle);
        \\    if (nlen == 0) return 1;
        \\    if (len < nlen) return 0;
        \\    for (uint64_t i = 0; i <= len - nlen; i++) {
        \\        if (memcmp(data + i, needle, nlen) == 0) return 1;
        \\    }
        \\    return 0;
        \\}
        \\
        \\int main(void) {
        \\    const uint8_t default_model[] = "fallback-model";
        \\    const uint8_t body[] =
        \\        "{\"model\":\"models/mimo-v2.5-pro\",\"stream\":false,"
        \\        "\"instructions\":\"follow instructions\","
        \\        "\"store\":false,\"prompt_cache_key\":\"drop-me\",\"include\":[\"reasoning.encrypted_content\"],\"reasoning\":{\"effort\":\"medium\"},"
        \\        "\"tools\":[{\"type\":\"namespace\",\"name\":\"mcp__code_index__\",\"tools\":[{\"type\":\"function\",\"name\":\"describe_index\",\"parameters\":{\"type\":\"object\"}}]}],"
        \\        "\"input\":["
        \\        "{\"type\":\"message\",\"role\":\"developer\",\"content\":[{\"type\":\"input_text\",\"text\":\"dev note\"}]},"
        \\        "{\"type\":\"message\",\"role\":\"user\",\"content\":[{\"type\":\"input_text\",\"text\":\"hello\"},{\"type\":\"text\",\"text\":\" world\"}]}"
        \\        "]}";
        \\    uint64_t h = sa_deno_responses_chat_fallback_request(body, sizeof(body) - 1, default_model, sizeof(default_model) - 1, 0);
        \\    uint8_t *data = sa_fs_read_buffer_data(h);
        \\    uint64_t len = sa_fs_read_buffer_len(h);
        \\    if (h == 0 || data == NULL || len == 0) return 2;
        \\    if (!has(data, len, "\"model\":\"models/mimo-v2.5-pro\"")) return 3;
        \\    if (!has(data, len, "\"role\":\"system\",\"content\":\"follow instructions\\n\\ndev note\"")) return 4;
        \\    if (!has(data, len, "\"role\":\"user\",\"content\":\"hello world\"")) return 5;
        \\    if (!has(data, len, "\"name\":\"mcp__code_index__describe_index\"")) return 6;
        \\    if (!has(data, len, "\"stream\":false")) return 7;
        \\    if (has(data, len, "prompt_cache_key") || has(data, len, "\"include\"") || has(data, len, "\"reasoning\"")) return 8;
        \\    if (sa_fs_read_buffer_free(h) != SA_STD_OK) return 9;
        \\    const uint8_t top_body[] =
        \\        "{\"model\":\"top-model\",\"stream\":false,\"instructions\":\"top sys\","
        \\        "\"input\":\"top input\",\"content\":\"leak content\",\"text\":\"leak text\",\"store\":false}";
        \\    h = sa_deno_responses_chat_fallback_request(top_body, sizeof(top_body) - 1, default_model, sizeof(default_model) - 1, 0);
        \\    data = sa_fs_read_buffer_data(h);
        \\    len = sa_fs_read_buffer_len(h);
        \\    if (h == 0 || data == NULL || len == 0) return 10;
        \\    if (!has(data, len, "\"model\":\"top-model\"")) return 11;
        \\    if (!has(data, len, "\"role\":\"system\",\"content\":\"top sys\"")) return 12;
        \\    if (!has(data, len, "\"role\":\"user\",\"content\":\"top input\"")) return 13;
        \\    if (has(data, len, "\"input\"") || has(data, len, "leak content") || has(data, len, "leak text") || has(data, len, "\"store\"")) return 14;
        \\    if (sa_fs_read_buffer_free(h) != SA_STD_OK) return 15;
        \\    const uint8_t tool_body[] =
        \\        "{\"model\":\"models/mimo-v2.5-pro\",\"stream\":false,"
        \\        "\"tools\":[{\"type\":\"function\",\"name\":\"exec_command\",\"parameters\":{\"type\":\"object\",\"properties\":{}}}],"
        \\        "\"input\":["
        \\        "{\"type\":\"function_call\",\"call_id\":\"call-1\",\"name\":\"exec_command\",\"arguments\":\"{\\\"cmd\\\":\\\"echo hi\\\"}\"},"
        \\        "{\"type\":\"function_call_output\",\"call_id\":\"call-1\",\"output\":\"ok\"}"
        \\        "]}";
        \\    h = sa_deno_responses_chat_fallback_request(tool_body, sizeof(tool_body) - 1, default_model, sizeof(default_model) - 1, 0);
        \\    data = sa_fs_read_buffer_data(h);
        \\    len = sa_fs_read_buffer_len(h);
        \\    if (h == 0 || data == NULL || len == 0) return 16;
        \\    if (!has(data, len, "\"role\":\"assistant\",\"content\":null,\"tool_calls\"")) return 17;
        \\    if (!has(data, len, "\"id\":\"call-1\",\"type\":\"function\",\"function\":{\"name\":\"exec_command\"")) return 18;
        \\    if (!has(data, len, "\"role\":\"tool\",\"content\":\"ok\",\"tool_call_id\":\"call-1\",\"name\":\"exec_command\"")) return 19;
        \\    if (!has(data, len, "\"tools\":[{\"type\":\"function\",\"function\":{\"name\":\"exec_command\",\"parameters\":{\"type\":\"object\",\"properties\":{}}}}]")) return 20;
        \\    if (sa_fs_read_buffer_free(h) != SA_STD_OK) return 21;
        \\    puts("sa_std deno responses chat fallback request ok");
        \\    return 0;
        \\}
        \\
    ;
    try common.writeSource(tmp.dir, "main.c", c_source);
    const build_lib_result = try common.runCommand(std.testing.allocator, &.{
        "zig",
        "build-lib",
        runtime_source,
        pthread_host_source,
        "-O",
        "Debug",
        "-lc",
        "-femit-bin=libsa_std.a",
    });
    defer std.testing.allocator.free(build_lib_result.stdout);
    defer std.testing.allocator.free(build_lib_result.stderr);
    try std.testing.expectEqual(@as(u8, 0), switch (build_lib_result.term) {
        .exited => |code| code,
        else => return error.TestUnexpectedResult,
    });

    const build_demo_result = try common.runCommand(std.testing.allocator, &.{
        "zig",
        "cc",
        "-I",
        include_dir,
        "main.c",
        "libsa_std.a",
        "-lc",
        "-o",
        "sa_std_deno_responses_chat_fallback_request",
    });
    defer std.testing.allocator.free(build_demo_result.stdout);
    defer std.testing.allocator.free(build_demo_result.stderr);
    try std.testing.expectEqual(@as(u8, 0), switch (build_demo_result.term) {
        .exited => |code| code,
        else => return error.TestUnexpectedResult,
    });

    const run_result = try common.runCommand(std.testing.allocator, &.{"./sa_std_deno_responses_chat_fallback_request"});
    defer std.testing.allocator.free(run_result.stdout);
    defer std.testing.allocator.free(run_result.stderr);
    try std.testing.expectEqual(@as(u8, 0), switch (run_result.term) {
        .exited => |code| code,
        else => return error.TestUnexpectedResult,
    });
    try std.testing.expectEqualStrings("sa_std deno responses chat fallback request ok\n", run_result.stdout);
}
