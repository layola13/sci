//! Deno JSON-RPC / chat SSE / chat JSON fallbacks -- split from tests/std_smoke_core.zig (shared helpers: helpers.zig).
const std = @import("std");
const common = @import("../std_smoke_common.zig");
const sio = @import("sio");
const saasm = common.saasm;
const flattenFixture = @import("helpers.zig").flattenFixture;

test "sa_std Deno JSON-RPC params string literal preserves escaped strings" {
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
        \\static int equals_and_free(uint64_t h, const char *expected) {
        \\    uint8_t *data = sa_fs_read_buffer_data(h);
        \\    uint64_t len = sa_fs_read_buffer_len(h);
        \\    size_t expected_len = strlen(expected);
        \\    int ok = h != 0 && data != NULL && len == expected_len && memcmp(data, expected, expected_len) == 0;
        \\    if (h != 0 && sa_fs_read_buffer_free(h) != SA_STD_OK) return 0;
        \\    return ok;
        \\}
        \\
        \\int main(void) {
        \\    const uint8_t body[] = "{\"jsonrpc\":\"2.0\",\"params\":{\"name\":\"env \\\"quoted\\\"\",\"path\":\"/tmp/a\\\\b\",\"note\":null}}";
        \\    const uint8_t invalid[] = "{\"jsonrpc\":\"2.0\",\"params\":";
        \\    const uint8_t fallback[] = "fallback \"value\"";
        \\    uint64_t h = 0;
        \\
        \\    h = sa_deno_jsonrpc_params_string_literal(body, sizeof(body) - 1, (const uint8_t *)"name", 4, (const uint8_t *)"", 0, 0);
        \\    if (!equals_and_free(h, "\"env \\\"quoted\\\"\"")) return 2;
        \\
        \\    h = sa_deno_jsonrpc_params_string_literal(body, sizeof(body) - 1, (const uint8_t *)"path", 4, (const uint8_t *)"", 0, 0);
        \\    if (!equals_and_free(h, "\"/tmp/a\\\\b\"")) return 3;
        \\
        \\    h = sa_deno_jsonrpc_params_string_literal(body, sizeof(body) - 1, (const uint8_t *)"missing", 7, fallback, sizeof(fallback) - 1, 0);
        \\    if (!equals_and_free(h, "\"fallback \\\"value\\\"\"")) return 4;
        \\
        \\    h = sa_deno_jsonrpc_params_string_literal(body, sizeof(body) - 1, (const uint8_t *)"missing", 7, fallback, sizeof(fallback) - 1, 1);
        \\    if (!equals_and_free(h, "null")) return 5;
        \\
        \\    h = sa_deno_jsonrpc_params_string_literal(body, sizeof(body) - 1, (const uint8_t *)"note", 4, fallback, sizeof(fallback) - 1, 0);
        \\    if (!equals_and_free(h, "\"fallback \\\"value\\\"\"")) return 6;
        \\
        \\    h = sa_deno_jsonrpc_params_string_literal(invalid, sizeof(invalid) - 1, (const uint8_t *)"name", 4, fallback, sizeof(fallback) - 1, 1);
        \\    if (!equals_and_free(h, "null")) return 7;
        \\
        \\    puts("sa_std deno jsonrpc params string literal ok");
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
        "sa_std_deno_jsonrpc_params",
    });
    defer std.testing.allocator.free(build_demo_result.stdout);
    defer std.testing.allocator.free(build_demo_result.stderr);
    try std.testing.expectEqual(@as(u8, 0), switch (build_demo_result.term) {
        .exited => |code| code,
        else => return error.TestUnexpectedResult,
    });

    const run_result = try common.runCommand(std.testing.allocator, &.{"./sa_std_deno_jsonrpc_params"});
    defer std.testing.allocator.free(run_result.stdout);
    defer std.testing.allocator.free(run_result.stderr);
    try std.testing.expectEqual(@as(u8, 0), switch (run_result.term) {
        .exited => |code| code,
        else => return error.TestUnexpectedResult,
    });
    try std.testing.expectEqualStrings("sa_std deno jsonrpc params string literal ok\n", run_result.stdout);
}

test "sa_std Deno chat SSE fallback normalizes Deno proxy edge cases" {
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
        \\static int count(uint8_t *data, uint64_t len, const char *needle) {
        \\    size_t nlen = strlen(needle);
        \\    int found = 0;
        \\    if (nlen == 0 || len < nlen) return 0;
        \\    for (uint64_t i = 0; i <= len - nlen; i++) {
        \\        if (memcmp(data + i, needle, nlen) == 0) {
        \\            found++;
        \\            i += nlen - 1;
        \\        }
        \\    }
        \\    return found;
        \\}
        \\
        \\int main(void) {
        \\    const uint8_t req[] = "{\"tools\":[{\"type\":\"function\",\"name\":\"exec_command\"}],\"input\":[{\"role\":\"user\",\"content\":\"hello\"}]}";
        \\    const uint8_t goal_req[] = "{\"tools\":[{\"type\":\"function\",\"name\":\"exec_command\"}],\"input\":[{\"role\":\"developer\",\"content\":\"<goal_context>Continue working.</goal_context>\"}]}";
        \\    const uint8_t default_req[] = "{\"tools\":[{\"type\":\"function\",\"name\":\"exec_command\"}],\"input\":[{\"role\":\"developer\",\"content\":\"<collaboration_mode># Collaboration Mode: Default</collaboration_mode>\"}]}";
        \\    const uint8_t namespace_req[] = "{\"tools\":[{\"type\":\"namespace\",\"name\":\"mcp__code_index__\",\"tools\":[{\"type\":\"function\",\"name\":\"describe_index\"}]}]}";
        \\    const uint8_t env_chat[] =
        \\        "data: {\"choices\":[{\"delta\":{\"tool_calls\":[{\"id\":\"call_read_env\",\"type\":\"function\",\"function\":{\"name\":\"read\",\"arguments\":\"{\\\"filePath\\\":\\\"/tmp/demo/.env.local\\\"}\"},\"index\":0}]},\"finish_reason\":null}]}\n\n"
        \\        "data: {\"choices\":[{\"delta\":{},\"finish_reason\":\"tool_calls\"}]}\n\n"
        \\        "data: [DONE]\n\n";
        \\    const uint8_t namespace_chat[] =
        \\        "data: {\"choices\":[{\"delta\":{\"tool_calls\":[{\"id\":\"call_mcp\",\"type\":\"function\",\"function\":{\"name\":\"mcp__code_index__describe_index\",\"arguments\":\"{}\"},\"index\":0}]},\"finish_reason\":null}]}\n\n"
        \\        "data: {\"choices\":[{\"delta\":{},\"finish_reason\":\"tool_calls\"}]}\n\n"
        \\        "data: [DONE]\n\n";
        \\    const uint8_t progress_chat[] =
        \\        "data: {\"choices\":[{\"delta\":{\"content\":\"Let me check the test failure details and the permission issue.\"},\"finish_reason\":null}]}\n\n"
        \\        "data: {\"choices\":[{\"delta\":{},\"finish_reason\":\"stop\"}]}\n\n"
        \\        "data: [DONE]\n\n";
        \\    const uint8_t final_chat[] =
        \\        "data: {\"choices\":[{\"delta\":{\"content\":\"我已完成评估，下面是结论。\"},\"finish_reason\":null}]}\n\n"
        \\        "data: {\"choices\":[{\"delta\":{},\"finish_reason\":\"stop\"}]}\n\n"
        \\        "data: [DONE]\n\n";
        \\    const uint8_t multi_visible_chat[] =
        \\        "data: {\"choices\":[{\"delta\":{\"reasoning_content\":\"think\"},\"finish_reason\":null}]}\n\n"
        \\        "data: {\"choices\":[{\"delta\":{\"content\":\"Hello\"},\"finish_reason\":null}]}\n\n"
        \\        "data: {\"choices\":[{\"delta\":{\"content\":\" world\"},\"finish_reason\":null}]}\n\n"
        \\        "data: {\"choices\":[{\"delta\":{},\"finish_reason\":\"stop\"}]}\n\n"
        \\        "data: [DONE]\n\n";
        \\    uint64_t h = sa_deno_chat_sse_to_responses(env_chat, sizeof(env_chat) - 1, req, sizeof(req) - 1);
        \\    uint8_t *data = sa_fs_read_buffer_data(h);
        \\    uint64_t len = sa_fs_read_buffer_len(h);
        \\    if (h == 0 || data == NULL || len == 0) return 2;
        \\    if (!has(data, len, "sed -E") || !has(data, len, "<redacted>") || !has(data, len, "/tmp/demo/.env.local")) return 3;
        \\    if (has(data, len, "cat '/tmp/demo/.env.local'")) return 4;
        \\    if (sa_fs_read_buffer_free(h) != SA_STD_OK) return 5;
        \\
        \\    h = sa_deno_chat_sse_to_responses(namespace_chat, sizeof(namespace_chat) - 1, namespace_req, sizeof(namespace_req) - 1);
        \\    data = sa_fs_read_buffer_data(h);
        \\    len = sa_fs_read_buffer_len(h);
        \\    if (h == 0 || data == NULL || len == 0) return 6;
        \\    if (!has(data, len, "\"namespace\":\"mcp__code_index__\"")) return 7;
        \\    if (!has(data, len, "\"name\":\"describe_index\"")) return 8;
        \\    if (!has(data, len, "\"output_kind\":\"function_call_output\"")) return 9;
        \\    if (has(data, len, "\"name\":\"mcp__code_index__describe_index\"")) return 10;
        \\    if (sa_fs_read_buffer_free(h) != SA_STD_OK) return 11;
        \\
        \\    h = sa_deno_chat_sse_to_responses(progress_chat, sizeof(progress_chat) - 1, req, sizeof(req) - 1);
        \\    data = sa_fs_read_buffer_data(h);
        \\    len = sa_fs_read_buffer_len(h);
        \\    if (h == 0 || data == NULL || len == 0) return 12;
        \\    if (has(data, len, "Progress-only message received")) return 13;
        \\    if (sa_fs_read_buffer_free(h) != SA_STD_OK) return 14;
        \\
        \\    h = sa_deno_chat_sse_to_responses(progress_chat, sizeof(progress_chat) - 1, goal_req, sizeof(goal_req) - 1);
        \\    data = sa_fs_read_buffer_data(h);
        \\    len = sa_fs_read_buffer_len(h);
        \\    if (h == 0 || data == NULL || len == 0) return 15;
        \\    if (!has(data, len, "Progress-only message received")) return 16;
        \\    if (sa_fs_read_buffer_free(h) != SA_STD_OK) return 17;
        \\
        \\    h = sa_deno_chat_sse_to_responses(progress_chat, sizeof(progress_chat) - 1, default_req, sizeof(default_req) - 1);
        \\    data = sa_fs_read_buffer_data(h);
        \\    len = sa_fs_read_buffer_len(h);
        \\    if (h == 0 || data == NULL || len == 0) return 18;
        \\    if (!has(data, len, "Progress-only message received")) return 19;
        \\    if (sa_fs_read_buffer_free(h) != SA_STD_OK) return 20;
        \\
        \\    h = sa_deno_chat_sse_to_responses(final_chat, sizeof(final_chat) - 1, goal_req, sizeof(goal_req) - 1);
        \\    data = sa_fs_read_buffer_data(h);
        \\    len = sa_fs_read_buffer_len(h);
        \\    if (h == 0 || data == NULL || len == 0) return 21;
        \\    if (has(data, len, "Progress-only message received")) return 22;
        \\    if (sa_fs_read_buffer_free(h) != SA_STD_OK) return 23;
        \\
        \\    h = sa_deno_chat_sse_to_responses(multi_visible_chat, sizeof(multi_visible_chat) - 1, req, sizeof(req) - 1);
        \\    data = sa_fs_read_buffer_data(h);
        \\    len = sa_fs_read_buffer_len(h);
        \\    if (h == 0 || data == NULL || len == 0) return 24;
        \\    if (!has(data, len, "\"item_id\":\"msg_chat_fb\"")) return 25;
        \\    if (!has(data, len, "\"content_index\":0")) return 26;
        \\    if (!has(data, len, "\"delta\":\"Hello\"") || !has(data, len, "\"delta\":\" world\"")) return 27;
        \\    if (count(data, len, "event: response.output_item.done\ndata: {\"type\":\"response.output_item.done\",\"output_index\":0,\"item\":{\"id\":\"think_chat_fb\"") != 1) return 28;
        \\    if (sa_fs_read_buffer_free(h) != SA_STD_OK) return 29;
        \\    puts("sa_std deno chat sse proxy edge cases ok");
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
    const exit_code = switch (build_lib_result.term) {
        .exited => |code| code,
        else => 99,
    };
    if (exit_code != 0) {
        std.debug.print("build-lib failed with code {d}:\nstdout: {s}\nstderr: {s}\n", .{ exit_code, build_lib_result.stdout, build_lib_result.stderr });
    }
    try std.testing.expectEqual(@as(u8, 0), exit_code);

    const build_demo_result = try common.runCommand(std.testing.allocator, &.{
        "zig",
        "cc",
        "-I",
        include_dir,
        "main.c",
        "libsa_std.a",
        "-lc",
        "-o",
        "sa_std_deno_chat_sse_edges",
    });
    defer std.testing.allocator.free(build_demo_result.stdout);
    defer std.testing.allocator.free(build_demo_result.stderr);
    try std.testing.expectEqual(@as(u8, 0), switch (build_demo_result.term) {
        .exited => |code| code,
        else => return error.TestUnexpectedResult,
    });

    const run_result = try common.runCommand(std.testing.allocator, &.{"./sa_std_deno_chat_sse_edges"});
    defer std.testing.allocator.free(run_result.stdout);
    defer std.testing.allocator.free(run_result.stderr);
    try std.testing.expectEqual(@as(u8, 0), switch (run_result.term) {
        .exited => |code| code,
        else => return error.TestUnexpectedResult,
    });
    try std.testing.expectEqualStrings("sa_std deno chat sse proxy edge cases ok\n", run_result.stdout);
}

test "sa_std Deno chat JSON fallback normalizes Deno proxy edge cases" {
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
        \\    const uint8_t req[] = "{\"tools\":[{\"type\":\"function\",\"name\":\"exec_command\"}],\"input\":[{\"role\":\"user\",\"content\":\"hello\"}]}";
        \\    const uint8_t goal_req[] = "{\"tools\":[{\"type\":\"function\",\"name\":\"exec_command\"}],\"input\":[{\"role\":\"developer\",\"content\":\"<goal_context>Continue working.</goal_context>\"}]}";
        \\    const uint8_t content_chat[] = "{\"choices\":[{\"message\":{\"content\":\"ok\"}}],\"usage\":{\"prompt_tokens\":1,\"completion_tokens\":2,\"total_tokens\":3}}";
        \\    const uint8_t thought_chat[] = "{\"choices\":[{\"message\":{\"content\":\"<thought>internal</thought>Hello\"}}]}";
        \\    const uint8_t reasoning_chat[] = "{\"choices\":[{\"message\":{\"reasoning_content\":\"json think\",\"content\":\"answer\"}}]}";
        \\    const uint8_t tool_chat[] = "{\"choices\":[{\"message\":{\"tool_calls\":[{\"id\":\"call_read\",\"type\":\"function\",\"function\":{\"name\":\"read\",\"arguments\":\"{\\\"filePath\\\":\\\"/tmp/demo/.env.local\\\"}\"}}]}}]}";
        \\    const uint8_t progress_chat[] = "{\"choices\":[{\"message\":{\"content\":\"Let me check the test failure details.\"}}]}";
        \\
        \\    uint64_t h = sa_deno_chat_json_to_responses(content_chat, sizeof(content_chat) - 1, req, sizeof(req) - 1);
        \\    if (!check(h, "\"output_text\":\"ok\"")) return 2;
        \\    if (!check(h, "\"input_tokens\":1") || !check(h, "\"output_tokens\":2") || !check(h, "\"total_tokens\":3")) return 3;
        \\    if (sa_fs_read_buffer_free(h) != SA_STD_OK) return 4;
        \\
        \\    h = sa_deno_chat_json_to_responses(thought_chat, sizeof(thought_chat) - 1, req, sizeof(req) - 1);
        \\    if (!check(h, "\"type\":\"reasoning\"") || !check(h, "internal") || !check(h, "\"output_text\":\"Hello\"")) return 5;
        \\    if (sa_fs_read_buffer_free(h) != SA_STD_OK) return 6;
        \\
        \\    h = sa_deno_chat_json_to_responses(reasoning_chat, sizeof(reasoning_chat) - 1, req, sizeof(req) - 1);
        \\    if (!check(h, "json think") || !check(h, "\"output_text\":\"answer\"")) return 7;
        \\    if (sa_fs_read_buffer_free(h) != SA_STD_OK) return 8;
        \\
        \\    h = sa_deno_chat_json_to_responses(tool_chat, sizeof(tool_chat) - 1, req, sizeof(req) - 1);
        \\    if (!check(h, "\"type\":\"function_call\"") || !check(h, "\"name\":\"exec_command\"")) return 9;
        \\    if (!check(h, "sed -E") || !check(h, "<redacted>")) return 10;
        \\    if (sa_fs_read_buffer_free(h) != SA_STD_OK) return 11;
        \\
        \\    h = sa_deno_chat_json_to_responses(progress_chat, sizeof(progress_chat) - 1, req, sizeof(req) - 1);
        \\    if (check(h, "Progress-only message received")) return 12;
        \\    if (sa_fs_read_buffer_free(h) != SA_STD_OK) return 13;
        \\
        \\    h = sa_deno_chat_json_to_responses(progress_chat, sizeof(progress_chat) - 1, goal_req, sizeof(goal_req) - 1);
        \\    if (!check(h, "Progress-only message received")) return 14;
        \\    if (sa_fs_read_buffer_free(h) != SA_STD_OK) return 15;
        \\
        \\    puts("sa_std deno chat json proxy edge cases ok");
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
        "sa_std_deno_chat_json_edges",
    });
    defer std.testing.allocator.free(build_demo_result.stdout);
    defer std.testing.allocator.free(build_demo_result.stderr);
    try std.testing.expectEqual(@as(u8, 0), switch (build_demo_result.term) {
        .exited => |code| code,
        else => return error.TestUnexpectedResult,
    });

    const run_result = try common.runCommand(std.testing.allocator, &.{"./sa_std_deno_chat_json_edges"});
    defer std.testing.allocator.free(run_result.stdout);
    defer std.testing.allocator.free(run_result.stderr);
    try std.testing.expectEqual(@as(u8, 0), switch (run_result.term) {
        .exited => |code| code,
        else => return error.TestUnexpectedResult,
    });
    try std.testing.expectEqualStrings("sa_std deno chat json proxy edge cases ok\n", run_result.stdout);
}
