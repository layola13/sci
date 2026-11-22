//! Deno chat SSE fallback -- split from tests/std_smoke.zig (shared helpers: helpers.zig).
const std = @import("std");
const saasm = @import("saasm");
const sio = @import("sio");
const helpers = @import("helpers.zig");

const repoRoot = helpers.repoRoot;
const readFileAlloc = helpers.readFileAlloc;
const writeSource = helpers.writeSource;
const runCommand = helpers.runCommand;
const runCommandWithEnvMap = helpers.runCommandWithEnvMap;
const runCommandAnyExit = helpers.runCommandAnyExit;
const NormalizedInstruction = helpers.NormalizedInstruction;
const normalizeInstruction = helpers.normalizeInstruction;
const expectFlattenEquivalent = helpers.expectFlattenEquivalent;
const dumpInstructionTexts = helpers.dumpInstructionTexts;
const flattenFixture = helpers.flattenFixture;

test "sa_std Deno chat SSE fallback splits thought tags across chunks" {
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
        \\#include <stdint.h>
        \\#include <stdio.h>
        \\#include <string.h>
        \\
        \\int main(void) {
        \\    const uint8_t chat[] =
        \\        "data: {\"choices\":[{\"delta\":{\"content\":\"<thou\"},\"finish_reason\":null}]}\n\n"
        \\        "data: {\"choices\":[{\"delta\":{\"content\":\"ght>split thought</th\"},\"finish_reason\":null}]}\n\n"
        \\        "data: {\"choices\":[{\"delta\":{\"content\":\"ought>Hello\"},\"finish_reason\":null}]}\n\n"
        \\        "data: {\"choices\":[{\"delta\":{},\"finish_reason\":\"stop\"}]}\n\n"
        \\        "data: [DONE]\n\n";
        \\    const uint8_t req[] = "{\"tools\":[{\"type\":\"function\",\"name\":\"exec_command\"}],\"input\":[{\"role\":\"user\",\"content\":\"hello\"}]}";
        \\    const uint8_t goal_req[] = "{\"tools\":[{\"type\":\"function\",\"name\":\"exec_command\"}],\"input\":[{\"role\":\"developer\",\"content\":\"<goal_context>Continue working.</goal_context>\"}]}";
        \\    const uint8_t default_mode_req[] = "{\"tools\":[{\"type\":\"function\",\"name\":\"exec_command\"}],\"input\":[{\"role\":\"developer\",\"content\":\"<collaboration_mode># Collaboration Mode: Default</collaboration_mode>\"}]}";
        \\    const uint8_t namespace_req[] = "{\"tools\":[{\"type\":\"namespace\",\"name\":\"mcp__code_index__\",\"tools\":[{\"type\":\"function\",\"name\":\"describe_index\"}]}]}";
        \\    const uint8_t tool_chat[] =
        \\        "data: {\"choices\":[{\"delta\":{\"tool_calls\":[{\"id\":\"call_read\",\"type\":\"function\",\"function\":{\"name\":\"read\",\"arguments\":\"{\\\"filePath\\\":\"},\"index\":0},{\"id\":\"call_cmd\",\"type\":\"function\",\"function\":{\"name\":\"exec_command\",\"arguments\":\"{\\\"command\\\":\"},\"index\":1}]},\"finish_reason\":null}]}\n\n"
        \\        "data: {\"choices\":[{\"delta\":{\"tool_calls\":[{\"type\":\"function\",\"function\":{\"arguments\":\"\\\"/tmp/demo.txt\\\"}\"},\"index\":0},{\"type\":\"function\",\"function\":{\"arguments\":\"\\\"deno check src/main.ts\\\"}\"},\"index\":1}]},\"finish_reason\":null}]}\n\n"
        \\        "data: {\"choices\":[{\"delta\":{},\"finish_reason\":\"tool_calls\"}]}\n\n"
        \\        "data: [DONE]\n\n";
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
        \\    uint64_t handle = sa_deno_chat_sse_to_responses(chat, sizeof(chat) - 1, req, sizeof(req) - 1);
        \\    uint64_t tool_handle = 0;
        \\    uint64_t env_handle = 0;
        \\    uint64_t namespace_handle = 0;
        \\    uint64_t progress_handle = 0;
        \\    uint64_t final_handle = 0;
        \\    uint64_t default_mode_handle = 0;
        \\    uint8_t *data = NULL;
        \\    uint64_t len = 0;
        \\    if (handle == 0) return 2;
        \\    data = sa_fs_read_buffer_data(handle);
        \\    len = sa_fs_read_buffer_len(handle);
        \\    if (data == NULL || len == 0) return 3;
        \\    if (memmem(data, len, "response.reasoning_summary_text.delta", 37) == NULL) return 4;
        \\    if (memmem(data, len, "split thought", 13) == NULL) return 5;
        \\    if (memmem(data, len, "\"delta\":\"Hello\"", 15) == NULL) return 6;
        \\    if (memmem(data, len, "<thought>", 9) != NULL) return 7;
        \\    if (memmem(data, len, "</thought>", 10) != NULL) return 8;
        \\    if (memmem(data, len, "\"choices\"", 9) != NULL) return 9;
        \\    if (memmem(data, len, "[DONE]", 6) != NULL) return 10;
        \\    if (sa_fs_read_buffer_free(handle) != SA_STD_OK) return 11;
        \\
        \\    tool_handle = sa_deno_chat_sse_to_responses(tool_chat, sizeof(tool_chat) - 1, req, sizeof(req) - 1);
        \\    if (tool_handle == 0) return 12;
        \\    data = sa_fs_read_buffer_data(tool_handle);
        \\    len = sa_fs_read_buffer_len(tool_handle);
        \\    if (data == NULL || len == 0) return 13;
        \\    if (memmem(data, len, "\"name\":\"exec_command\"", 21) == NULL) return 14;
        \\    if (memmem(data, len, "cat '/tmp/demo.txt'", 19) == NULL) return 15;
        \\    if (memmem(data, len, "deno check src/main.ts", 22) == NULL) return 16;
        \\    if (memmem(data, len, "\"name\":\"read\"", 13) != NULL) return 17;
        \\    if (memmem(data, len, "\"command\"", 9) != NULL) return 18;
        \\    if (memmem(data, len, "\"choices\"", 9) != NULL) return 19;
        \\    if (sa_fs_read_buffer_free(tool_handle) != SA_STD_OK) return 20;
        \\
        \\    env_handle = sa_deno_chat_sse_to_responses(env_chat, sizeof(env_chat) - 1, req, sizeof(req) - 1);
        \\    if (env_handle == 0) return 21;
        \\    data = sa_fs_read_buffer_data(env_handle);
        \\    len = sa_fs_read_buffer_len(env_handle);
        \\    if (data == NULL || len == 0) return 22;
        \\    if (memmem(data, len, "sed -E", 6) == NULL) return 23;
        \\    if (memmem(data, len, "<redacted>", 10) == NULL) return 24;
        \\    if (memmem(data, len, "/tmp/demo/.env.local", 20) == NULL) return 25;
        \\    if (memmem(data, len, "cat '/tmp/demo/.env.local'", 26) != NULL) return 26;
        \\    if (sa_fs_read_buffer_free(env_handle) != SA_STD_OK) return 27;
        \\
        \\    namespace_handle = sa_deno_chat_sse_to_responses(namespace_chat, sizeof(namespace_chat) - 1, namespace_req, sizeof(namespace_req) - 1);
        \\    if (namespace_handle == 0) return 28;
        \\    data = sa_fs_read_buffer_data(namespace_handle);
        \\    len = sa_fs_read_buffer_len(namespace_handle);
        \\    if (data == NULL || len == 0) return 29;
        \\    if (memmem(data, len, "\"namespace\":\"mcp__code_index__\"", 31) == NULL) return 30;
        \\    if (memmem(data, len, "\"name\":\"describe_index\"", 23) == NULL) return 31;
        \\    if (memmem(data, len, "\"output_kind\":\"function_call_output\"", 36) == NULL) return 32;
        \\    if (memmem(data, len, "\"name\":\"mcp__code_index__describe_index\"", 41) != NULL) return 33;
        \\    if (sa_fs_read_buffer_free(namespace_handle) != SA_STD_OK) return 34;
        \\
        \\    progress_handle = sa_deno_chat_sse_to_responses(progress_chat, sizeof(progress_chat) - 1, req, sizeof(req) - 1);
        \\    if (progress_handle == 0) return 35;
        \\    data = sa_fs_read_buffer_data(progress_handle);
        \\    len = sa_fs_read_buffer_len(progress_handle);
        \\    if (data == NULL || len == 0) return 36;
        \\    if (memmem(data, len, "Progress-only message received", 30) != NULL) return 37;
        \\    if (sa_fs_read_buffer_free(progress_handle) != SA_STD_OK) return 38;
        \\
        \\    progress_handle = sa_deno_chat_sse_to_responses(progress_chat, sizeof(progress_chat) - 1, goal_req, sizeof(goal_req) - 1);
        \\    if (progress_handle == 0) return 39;
        \\    data = sa_fs_read_buffer_data(progress_handle);
        \\    len = sa_fs_read_buffer_len(progress_handle);
        \\    if (data == NULL || len == 0) return 40;
        \\    if (memmem(data, len, "Progress-only message received", 30) == NULL) return 41;
        \\    if (sa_fs_read_buffer_free(progress_handle) != SA_STD_OK) return 42;
        \\
        \\    default_mode_handle = sa_deno_chat_sse_to_responses(progress_chat, sizeof(progress_chat) - 1, default_mode_req, sizeof(default_mode_req) - 1);
        \\    if (default_mode_handle == 0) return 43;
        \\    data = sa_fs_read_buffer_data(default_mode_handle);
        \\    len = sa_fs_read_buffer_len(default_mode_handle);
        \\    if (data == NULL || len == 0) return 44;
        \\    if (memmem(data, len, "Progress-only message received", 30) == NULL) return 45;
        \\    if (sa_fs_read_buffer_free(default_mode_handle) != SA_STD_OK) return 46;
        \\
        \\    final_handle = sa_deno_chat_sse_to_responses(final_chat, sizeof(final_chat) - 1, goal_req, sizeof(goal_req) - 1);
        \\    if (final_handle == 0) return 47;
        \\    data = sa_fs_read_buffer_data(final_handle);
        \\    len = sa_fs_read_buffer_len(final_handle);
        \\    if (data == NULL || len == 0) return 48;
        \\    if (memmem(data, len, "Progress-only message received", 30) != NULL) return 49;
        \\    if (sa_fs_read_buffer_free(final_handle) != SA_STD_OK) return 50;
        \\    puts("sa_std deno chat sse thought split ok");
        \\    return 0;
        \\}
        \\
    ;
    try writeSource(tmp.dir, "main.c", c_source);
    const build_lib_argv = [_][]const u8{
        "zig",
        "build-lib",
        runtime_source,
        pthread_host_source,
        "-O",
        "Debug",
        "-lc",
        "-femit-bin=libsa_std.a",
    };
    const build_lib_result = try runCommand(std.testing.allocator, build_lib_argv[0..]);
    defer std.testing.allocator.free(build_lib_result.stdout);
    defer std.testing.allocator.free(build_lib_result.stderr);
    try std.testing.expectEqual(@as(u8, 0), switch (build_lib_result.term) {
        .exited => |code| code,
        else => return error.TestUnexpectedResult,
    });

    const build_demo_argv = [_][]const u8{
        "zig",
        "cc",
        "-I",
        include_dir,
        "main.c",
        "libsa_std.a",
        "-lc",
        "-o",
        "sa_std_deno_chat_sse_demo",
    };
    const build_demo_result = try runCommand(std.testing.allocator, build_demo_argv[0..]);
    defer std.testing.allocator.free(build_demo_result.stdout);
    defer std.testing.allocator.free(build_demo_result.stderr);
    try std.testing.expectEqual(@as(u8, 0), switch (build_demo_result.term) {
        .exited => |code| code,
        else => return error.TestUnexpectedResult,
    });

    const run_result = try runCommand(std.testing.allocator, &.{"./sa_std_deno_chat_sse_demo"});
    defer std.testing.allocator.free(run_result.stdout);
    defer std.testing.allocator.free(run_result.stderr);
    try std.testing.expectEqual(@as(u8, 0), switch (run_result.term) {
        .exited => |code| code,
        else => return error.TestUnexpectedResult,
    });
    try std.testing.expectEqualStrings("sa_std deno chat sse thought split ok\n", run_result.stdout);
}
