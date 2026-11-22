//! Deno compatibility / JSON / text / status facades -- split from tests/std_smoke.zig (shared helpers: helpers.zig).
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

test "sa_std Deno compatibility facade covers HubProxy porting surface" {
    const deno_sai = try readFileAlloc(std.testing.allocator, "../sa_plugins/sa_plugin_deno/deno.sai");
    defer std.testing.allocator.free(deno_sai);
    try std.testing.expect(std.mem.containsAtLeast(u8, deno_sai, 1, "sa_deno_plugin_cwd"));
    try std.testing.expect(std.mem.containsAtLeast(u8, deno_sai, 1, "sa_deno_plugin_env_set"));
    try std.testing.expect(std.mem.containsAtLeast(u8, deno_sai, 1, "sa_deno_plugin_random_uuid"));
    try std.testing.expect(std.mem.containsAtLeast(u8, deno_sai, 1, "sa_deno_plugin_args_json"));
    try std.testing.expect(std.mem.containsAtLeast(u8, deno_sai, 1, "sa_deno_plugin_btoa"));
    try std.testing.expect(std.mem.containsAtLeast(u8, deno_sai, 1, "sa_deno_plugin_atob"));
    try std.testing.expect(std.mem.containsAtLeast(u8, deno_sai, 1, "sa_deno_plugin_text_encode"));
    try std.testing.expect(std.mem.containsAtLeast(u8, deno_sai, 1, "sa_deno_plugin_text_decode"));
    try std.testing.expect(std.mem.containsAtLeast(u8, deno_sai, 1, "sa_deno_plugin_chat_sse_to_responses"));
    try std.testing.expect(std.mem.containsAtLeast(u8, deno_sai, 1, "sa_deno_plugin_version_json"));
    try std.testing.expect(std.mem.containsAtLeast(u8, deno_sai, 1, "sa_deno_plugin_build_json"));
    try std.testing.expect(std.mem.containsAtLeast(u8, deno_sai, 1, "sa_deno_plugin_version_deno"));
    try std.testing.expect(std.mem.containsAtLeast(u8, deno_sai, 1, "sa_deno_plugin_build_os"));
    try std.testing.expect(std.mem.containsAtLeast(u8, deno_sai, 1, "sa_deno_plugin_build_platform_family"));
    try std.testing.expect(std.mem.containsAtLeast(u8, deno_sai, 1, "sa_deno_plugin_date_now_iso"));
    try std.testing.expect(std.mem.containsAtLeast(u8, deno_sai, 1, "DENO_HTTP_METHOD_POST"));
    try std.testing.expect(std.mem.containsAtLeast(u8, deno_sai, 1, "sa_http_client_req_send"));
    try std.testing.expect(std.mem.containsAtLeast(u8, deno_sai, 1, "sa_http_client_resp_get_header"));
    try std.testing.expect(std.mem.containsAtLeast(u8, deno_sai, 1, "sa_http_server_req_get_method"));
    try std.testing.expect(std.mem.containsAtLeast(u8, deno_sai, 1, "sa_http_server_resp_set_content_type"));
    try std.testing.expect(std.mem.containsAtLeast(u8, deno_sai, 1, "sa_http_server_resp_stream_write"));

    const deno_src = try readFileAlloc(std.testing.allocator, "../sa_plugins/sa_plugin_deno/deno.sal");
    defer std.testing.allocator.free(deno_src);
    try std.testing.expect(std.mem.containsAtLeast(u8, deno_src, 1, "[MACRO] DENO_ARGS_JSON"));
    try std.testing.expect(std.mem.containsAtLeast(u8, deno_src, 1, "[MACRO] DENO_ENV_GET"));
    try std.testing.expect(std.mem.containsAtLeast(u8, deno_src, 1, "[MACRO] DENO_ENV_SET"));
    try std.testing.expect(std.mem.containsAtLeast(u8, deno_src, 1, "[MACRO] DENO_CWD"));
    try std.testing.expect(std.mem.containsAtLeast(u8, deno_src, 1, "[MACRO] DENO_RANDOM_UUID"));
    try std.testing.expect(std.mem.containsAtLeast(u8, deno_src, 1, "[MACRO] DENO_CRYPTO_RANDOM_UUID"));
    try std.testing.expect(std.mem.containsAtLeast(u8, deno_src, 1, "[MACRO] DENO_BTOA"));
    try std.testing.expect(std.mem.containsAtLeast(u8, deno_src, 1, "[MACRO] DENO_ATOB"));
    try std.testing.expect(std.mem.containsAtLeast(u8, deno_src, 1, "[MACRO] DENO_TEXT_ENCODE"));
    try std.testing.expect(std.mem.containsAtLeast(u8, deno_src, 1, "[MACRO] DENO_TEXT_DECODE"));
    try std.testing.expect(std.mem.containsAtLeast(u8, deno_src, 1, "[MACRO] DENO_TEXT_ENCODER_ENCODE"));
    try std.testing.expect(std.mem.containsAtLeast(u8, deno_src, 1, "[MACRO] DENO_TEXT_DECODER_DECODE"));
    try std.testing.expect(std.mem.containsAtLeast(u8, deno_src, 1, "[MACRO] DENO_CHAT_SSE_TO_RESPONSES"));
    try std.testing.expect(std.mem.containsAtLeast(u8, deno_src, 1, "[MACRO] DENO_VERSION_JSON"));
    try std.testing.expect(std.mem.containsAtLeast(u8, deno_src, 1, "[MACRO] DENO_VERSION_DENO"));
    try std.testing.expect(std.mem.containsAtLeast(u8, deno_src, 1, "[MACRO] DENO_BUILD_JSON"));
    try std.testing.expect(std.mem.containsAtLeast(u8, deno_src, 1, "[MACRO] DENO_BUILD_OS"));
    try std.testing.expect(std.mem.containsAtLeast(u8, deno_src, 1, "[MACRO] DENO_BUILD_PLATFORM_FAMILY"));
    try std.testing.expect(std.mem.containsAtLeast(u8, deno_src, 1, "[MACRO] DENO_DATE_NOW_ISO"));
    try std.testing.expect(std.mem.containsAtLeast(u8, deno_src, 1, "[MACRO] DENO_NEW_DATE_TO_ISO_STRING"));
    try std.testing.expect(std.mem.containsAtLeast(u8, deno_src, 1, "[MACRO] DENO_JSON_PARSE"));
    try std.testing.expect(std.mem.containsAtLeast(u8, deno_src, 1, "[MACRO] DENO_JSON_STRINGIFY"));
    try std.testing.expect(std.mem.containsAtLeast(u8, deno_src, 1, "[MACRO] DENO_JSON_BUFFER_SLICE"));
    try std.testing.expect(std.mem.containsAtLeast(u8, deno_src, 1, "[MACRO] DENO_JSON_BUFFER_FREE"));
    try std.testing.expect(std.mem.containsAtLeast(u8, deno_src, 1, "[MACRO] DENO_JSON_FREE"));
    try std.testing.expect(std.mem.containsAtLeast(u8, deno_src, 1, "[MACRO] DENO_FREE_BUFFER"));
    try std.testing.expect(std.mem.containsAtLeast(u8, deno_src, 1, "[MACRO] DENO_STDOUT_WRITE"));
    try std.testing.expect(std.mem.containsAtLeast(u8, deno_src, 1, "[MACRO] DENO_STDERR_WRITE"));
    try std.testing.expect(std.mem.containsAtLeast(u8, deno_src, 1, "[MACRO] DENO_READ_TEXT_FILE"));
    try std.testing.expect(std.mem.containsAtLeast(u8, deno_src, 1, "[MACRO] DENO_READ_TEXT_FILE_SYNC"));
    try std.testing.expect(std.mem.containsAtLeast(u8, deno_src, 1, "[MACRO] DENO_READ_FILE"));
    try std.testing.expect(std.mem.containsAtLeast(u8, deno_src, 1, "[MACRO] DENO_READ_FILE_SYNC"));
    try std.testing.expect(std.mem.containsAtLeast(u8, deno_src, 1, "[MACRO] DENO_WRITE_TEXT_FILE"));
    try std.testing.expect(std.mem.containsAtLeast(u8, deno_src, 1, "[MACRO] DENO_WRITE_TEXT_FILE_SYNC"));
    try std.testing.expect(std.mem.containsAtLeast(u8, deno_src, 1, "[MACRO] DENO_WRITE_FILE"));
    try std.testing.expect(std.mem.containsAtLeast(u8, deno_src, 1, "[MACRO] DENO_WRITE_FILE_SYNC"));
    try std.testing.expect(std.mem.containsAtLeast(u8, deno_src, 1, "[MACRO] DENO_READ_FILE_BASE64"));
    try std.testing.expect(std.mem.containsAtLeast(u8, deno_src, 1, "[MACRO] DENO_WRITE_FILE_BASE64"));
    try std.testing.expect(std.mem.containsAtLeast(u8, deno_src, 1, "[MACRO] DENO_MKDIR_SYNC"));
    try std.testing.expect(std.mem.containsAtLeast(u8, deno_src, 1, "[MACRO] DENO_READ_DIR_JSON"));
    try std.testing.expect(std.mem.containsAtLeast(u8, deno_src, 1, "[MACRO] DENO_READ_DIR_SYNC_JSON"));
    try std.testing.expect(std.mem.containsAtLeast(u8, deno_src, 1, "[MACRO] DENO_READ_DIR"));
    try std.testing.expect(std.mem.containsAtLeast(u8, deno_src, 1, "[MACRO] DENO_READ_DIR_SYNC"));
    try std.testing.expect(std.mem.containsAtLeast(u8, deno_src, 1, "[MACRO] DENO_LSTAT_JSON"));
    try std.testing.expect(std.mem.containsAtLeast(u8, deno_src, 1, "[MACRO] DENO_LSTAT_SYNC_JSON"));
    try std.testing.expect(std.mem.containsAtLeast(u8, deno_src, 1, "[MACRO] DENO_LSTAT"));
    try std.testing.expect(std.mem.containsAtLeast(u8, deno_src, 1, "[MACRO] DENO_LSTAT_SYNC"));
    try std.testing.expect(std.mem.containsAtLeast(u8, deno_src, 1, "[MACRO] DENO_STAT_JSON"));
    try std.testing.expect(std.mem.containsAtLeast(u8, deno_src, 1, "[MACRO] DENO_STAT_SYNC_JSON"));
    try std.testing.expect(std.mem.containsAtLeast(u8, deno_src, 1, "[MACRO] DENO_STAT"));
    try std.testing.expect(std.mem.containsAtLeast(u8, deno_src, 1, "[MACRO] DENO_STAT_SYNC"));
    try std.testing.expect(std.mem.containsAtLeast(u8, deno_src, 1, "[MACRO] DENO_MAKE_TEMP_DIR"));
    try std.testing.expect(std.mem.containsAtLeast(u8, deno_src, 1, "[MACRO] DENO_MAKE_TEMP_DIR_SYNC"));
    try std.testing.expect(std.mem.containsAtLeast(u8, deno_src, 1, "[MACRO] DENO_MAKE_TEMP_FILE"));
    try std.testing.expect(std.mem.containsAtLeast(u8, deno_src, 1, "[MACRO] DENO_MAKE_TEMP_FILE_SYNC"));
    try std.testing.expect(std.mem.containsAtLeast(u8, deno_src, 1, "[MACRO] DENO_REMOVE_SYNC"));
    try std.testing.expect(std.mem.containsAtLeast(u8, deno_src, 1, "[MACRO] DENO_COPY_FILE_SYNC"));
    try std.testing.expect(std.mem.containsAtLeast(u8, deno_src, 1, "[MACRO] DENO_COMMAND_RUN"));
    try std.testing.expect(std.mem.containsAtLeast(u8, deno_src, 1, "[MACRO] DENO_COMMAND_EXEC"));
    try std.testing.expect(std.mem.containsAtLeast(u8, deno_src, 1, "[MACRO] DENO_COMMAND_OUTPUT"));
    try std.testing.expect(std.mem.containsAtLeast(u8, deno_src, 1, "[MACRO] DENO_COMMAND_SPAWN_STREAM"));
    try std.testing.expect(std.mem.containsAtLeast(u8, deno_src, 1, "[MACRO] DENO_COMMAND_READ_STDOUT"));
    try std.testing.expect(std.mem.containsAtLeast(u8, deno_src, 1, "[MACRO] DENO_NOW_MS"));
    try std.testing.expect(std.mem.containsAtLeast(u8, deno_src, 1, "[MACRO] DENO_DATE_NOW"));
    try std.testing.expect(std.mem.containsAtLeast(u8, deno_src, 1, "[MACRO] DENO_LISTEN_TCP"));
    try std.testing.expect(std.mem.containsAtLeast(u8, deno_src, 1, "[MACRO] DENO_CONNECT_TCP"));
    try std.testing.expect(std.mem.containsAtLeast(u8, deno_src, 1, "[MACRO] DENO_HTTP_CLIENT_NEW"));
    try std.testing.expect(std.mem.containsAtLeast(u8, deno_src, 1, "[MACRO] DENO_HTTP_REQUEST_NEW"));
    try std.testing.expect(std.mem.containsAtLeast(u8, deno_src, 1, "[MACRO] DENO_HTTP_REQUEST_SEND"));
    try std.testing.expect(std.mem.containsAtLeast(u8, deno_src, 1, "[MACRO] DENO_HTTP_RESPONSE_GET_HEADER"));
    try std.testing.expect(std.mem.containsAtLeast(u8, deno_src, 1, "[MACRO] DENO_HTTP_RESPONSE_READ_CHUNK"));
    try std.testing.expect(std.mem.containsAtLeast(u8, deno_src, 1, "[MACRO] DENO_REQUEST_NEW"));
    try std.testing.expect(std.mem.containsAtLeast(u8, deno_src, 1, "[MACRO] DENO_REQUEST_HEADERS_APPEND"));
    try std.testing.expect(std.mem.containsAtLeast(u8, deno_src, 1, "[MACRO] DENO_RESPONSE_HEADERS_GET"));
    try std.testing.expect(std.mem.containsAtLeast(u8, deno_src, 1, "[MACRO] DENO_SERVE_NEW"));
    try std.testing.expect(std.mem.containsAtLeast(u8, deno_src, 1, "[MACRO] DENO_SERVE_REQUEST_METHOD"));
    try std.testing.expect(std.mem.containsAtLeast(u8, deno_src, 1, "[MACRO] DENO_SERVE_RESPONSE_SET_CONTENT_TYPE"));
    try std.testing.expect(std.mem.containsAtLeast(u8, deno_src, 1, "[MACRO] DENO_SERVE_STREAM_WRITE"));

    var deno_flat = try flattenFixture(std.testing.allocator, "../sa_plugins/sa_plugin_deno/deno.sal", deno_src);
    defer deno_flat.deinit(std.testing.allocator);
    try std.testing.expect(deno_flat.function_sigs.len >= 60);
}

test "sa_std Deno JSON facade runs from SA" {
    var tmp = std.testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();

    const deno_sal = try readFileAlloc(std.testing.allocator, "../sa_plugins/sa_plugin_deno/deno.sal");
    defer std.testing.allocator.free(deno_sal);
    const deno_sai = try readFileAlloc(std.testing.allocator, "../sa_plugins/sa_plugin_deno/deno.sai");
    defer std.testing.allocator.free(deno_sai);

    try writeSource(tmp.dir, "deno.sal", deno_sal);
    try writeSource(tmp.dir, "deno.sai", deno_sai);

    const source =
        \\@import "deno.sal"
        \\
        \\@const JSON_DOC = utf8:"{\"ok\":true,\"n\":7}"
        \\
        \\#def JSON_DOC_LEN = 17
        \\
        \\@main() -> i32:
        \\L_ENTRY:
        \\    EXPAND DENO_JSON_PARSE root, JSON_DOC, JSON_DOC_LEN
        \\    root_ok = ne root, 0
        \\    br root_ok -> L_STRINGIFY, L_FAIL_ROOT
        \\
        \\L_STRINGIFY:
        \\    !root_ok
        \\    EXPAND DENO_JSON_STRINGIFY stringify_status, json_buf, root
        \\    stringify_ok = eq stringify_status, 0
        \\    !stringify_status
        \\    br stringify_ok -> L_SLICE, L_FAIL_STRINGIFY
        \\
        \\L_SLICE:
        \\    !stringify_ok
        \\    EXPAND DENO_JSON_BUFFER_SLICE json_ptr, json_len, json_buf
        \\    len_ok = eq json_len, JSON_DOC_LEN
        \\    br len_ok -> L_CLEANUP, L_FAIL_LEN
        \\
        \\L_CLEANUP:
        \\    !len_ok
        \\    EXPAND DENO_JSON_BUFFER_FREE json_buf
        \\    EXPAND DENO_JSON_FREE root
        \\    !json_ptr
        \\    !json_len
        \\    return 0
        \\
        \\L_FAIL_ROOT:
        \\    !root_ok
        \\    return 63
        \\
        \\L_FAIL_STRINGIFY:
        \\    !stringify_ok
        \\    EXPAND DENO_JSON_FREE root
        \\    !json_buf
        \\    return 63
        \\
        \\L_FAIL_LEN:
        \\    !len_ok
        \\    EXPAND DENO_JSON_BUFFER_FREE json_buf
        \\    EXPAND DENO_JSON_FREE root
        \\    !json_ptr
        \\    !json_len
        \\    return 63
    ;
    try writeSource(tmp.dir, "deno_json_facade.sa", source);

    var original_cwd = try sio.cwd().openDir(".", .{});
    defer original_cwd.close();
    try std.process.setCurrentDir(std.testing.io, tmp.dir);
    defer original_cwd.setAsCwd() catch {};

    const build_exe_argv = [_][]const u8{ "sa", "build-exe", "deno_json_facade.sa", "-o", "deno_json_facade" };
    const exe_code = try saasm.cli.execute(std.testing.allocator, build_exe_argv[0..]);
    try std.testing.expectEqual(@as(u8, 0), exe_code);

    const run_result = try runCommandAnyExit(std.testing.allocator, &[_][]const u8{"./deno_json_facade"});
    defer std.testing.allocator.free(run_result.stdout);
    defer std.testing.allocator.free(run_result.stderr);
    switch (run_result.term) {
        .exited => |code| try std.testing.expectEqual(@as(u8, 0), code),
        else => return error.TestUnexpectedResult,
    }
}

test "sa_std Deno text and base64 facade runs from SA" {
    var tmp = std.testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();

    const deno_sal = try readFileAlloc(std.testing.allocator, "../sa_plugins/sa_plugin_deno/deno.sal");
    defer std.testing.allocator.free(deno_sal);
    const deno_sai = try readFileAlloc(std.testing.allocator, "../sa_plugins/sa_plugin_deno/deno.sai");
    defer std.testing.allocator.free(deno_sai);

    try writeSource(tmp.dir, "deno.sal", deno_sal);
    try writeSource(tmp.dir, "deno.sai", deno_sai);

    const source =
        \\@import "deno.sal"
        \\@import "sa_std/fmt.sai"
        \\@import "sa_std/fs.sai"
        \\
        \\@const TEXT = utf8:"ok"
        \\@const ENCODED = utf8:"b2s="
        \\
        \\#def TEXT_LEN = 2
        \\#def ENCODED_LEN = 4
        \\
        \\@main() -> i32:
        \\L_ENTRY:
        \\    EXPAND DENO_BTOA btoa_buf, TEXT, TEXT_LEN
        \\    btoa_ptr = call @sa_fmt_buffer_data(btoa_buf)
        \\    btoa_len = call @sa_fmt_buffer_len(btoa_buf)
        \\    btoa_len_ok = eq btoa_len, 4
        \\    br btoa_len_ok -> L_DECODE, L_FAIL
        \\
        \\L_DECODE:
        \\    !btoa_len_ok
        \\    EXPAND DENO_ATOB atob_buf, ENCODED, ENCODED_LEN
        \\    atob_ptr = call @sa_fmt_buffer_data(atob_buf)
        \\    atob_len = call @sa_fmt_buffer_len(atob_buf)
        \\    atob_len_ok = eq atob_len, 2
        \\    br atob_len_ok -> L_TEXT_ENCODE, L_FAIL
        \\
        \\L_TEXT_ENCODE:
        \\    !atob_len_ok
        \\    EXPAND DENO_TEXT_ENCODE bytes_buf, TEXT, TEXT_LEN
        \\    bytes_ptr = call @sa_fs_read_buffer_data(bytes_buf)
        \\    bytes_len = call @sa_fs_read_buffer_len(bytes_buf)
        \\    bytes_len_ok = eq bytes_len, 2
        \\    br bytes_len_ok -> L_TEXT_DECODE, L_FAIL
        \\
        \\L_TEXT_DECODE:
        \\    !bytes_len_ok
        \\    EXPAND DENO_TEXT_DECODE text_buf, TEXT, TEXT_LEN
        \\    text_ptr = call @sa_fmt_buffer_data(text_buf)
        \\    text_len = call @sa_fmt_buffer_len(text_buf)
        \\    text_len_ok = eq text_len, 2
        \\    br text_len_ok -> L_VERSION, L_FAIL
        \\
        \\L_VERSION:
        \\    !text_len_ok
        \\    EXPAND DENO_VERSION_JSON version_buf
        \\    version_ptr = call @sa_fs_read_buffer_data(version_buf)
        \\    version_len = call @sa_fs_read_buffer_len(version_buf)
        \\    version_ok = gt version_len, 2
        \\    br version_ok -> L_BUILD, L_FAIL
        \\
        \\L_BUILD:
        \\    !version_ok
        \\    EXPAND DENO_BUILD_JSON build_buf
        \\    build_ptr = call @sa_fs_read_buffer_data(build_buf)
        \\    build_len = call @sa_fs_read_buffer_len(build_buf)
        \\    build_ok = gt build_len, 2
        \\    br build_ok -> L_CLEANUP, L_FAIL
        \\
        \\L_CLEANUP:
        \\    !build_ok
        \\    btoa_free = call @sa_fmt_buffer_free(^btoa_buf)
        \\    atob_free = call @sa_fmt_buffer_free(^atob_buf)
        \\    bytes_free = call @sa_fs_read_buffer_free(^bytes_buf)
        \\    text_free = call @sa_fmt_buffer_free(^text_buf)
        \\    version_free = call @sa_fs_read_buffer_free(^version_buf)
        \\    build_free = call @sa_fs_read_buffer_free(^build_buf)
        \\    !build_ptr
        \\    !version_ptr
        \\    !text_ptr
        \\    !bytes_ptr
        \\    !atob_ptr
        \\    !btoa_ptr
        \\    !build_free
        \\    !version_free
        \\    !text_free
        \\    !bytes_free
        \\    !atob_free
        \\    !btoa_free
        \\    return 0
        \\
        \\L_FAIL:
        \\    return 64
    ;
    try writeSource(tmp.dir, "deno_text_base64.sa", source);

    var original_cwd = try sio.cwd().openDir(".", .{});
    defer original_cwd.close();
    try std.process.setCurrentDir(std.testing.io, tmp.dir);
    defer original_cwd.setAsCwd() catch {};

    const build_exe_argv = [_][]const u8{ "sa", "build-exe", "deno_text_base64.sa", "-o", "deno_text_base64" };
    const exe_code = try saasm.cli.execute(std.testing.allocator, build_exe_argv[0..]);
    try std.testing.expectEqual(@as(u8, 0), exe_code);

    const run_result = try runCommandAnyExit(std.testing.allocator, &[_][]const u8{"./deno_text_base64"});
    defer std.testing.allocator.free(run_result.stdout);
    defer std.testing.allocator.free(run_result.stderr);
    switch (run_result.term) {
        .exited => |code| try std.testing.expectEqual(@as(u8, 0), code),
        else => return error.TestUnexpectedResult,
    }
}

test "sa_std Deno fallible status macros compile and run" {
    var original_cwd = try sio.cwd().openDir(".", .{});
    defer original_cwd.close();
    var tmp = std.testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();

    const deno_sal = try readFileAlloc(std.testing.allocator, "../sa_plugins/sa_plugin_deno/deno.sal");
    defer std.testing.allocator.free(deno_sal);
    const deno_sai = try readFileAlloc(std.testing.allocator, "../sa_plugins/sa_plugin_deno/deno.sai");
    defer std.testing.allocator.free(deno_sai);

    try writeSource(tmp.dir, "deno.sal", deno_sal);
    try writeSource(tmp.dir, "deno.sai", deno_sai);

    try std.process.setCurrentDir(std.testing.io, tmp.dir);
    defer original_cwd.setAsCwd() catch {};

    const source =
        \\@import "deno.sal"
        \\
        \\@const DIR = utf8:"deno_macro_dir"
        \\@const TEXT_PATH = utf8:"deno_macro_dir/text.txt"
        \\@const B64_PATH = utf8:"deno_macro_dir/b64.txt"
        \\@const TEXT = utf8:"hello"
        \\@const B64 = utf8:"aGVsbG8="
        \\
        \\#def DIR_LEN = 14
        \\#def TEXT_PATH_LEN = 23
        \\#def B64_PATH_LEN = 22
        \\#def TEXT_LEN = 5
        \\#def B64_LEN = 8
        \\
        \\@main() -> i32:
        \\L_ENTRY:
        \\    EXPAND DENO_MKDIR mkdir_status, DIR, DIR_LEN
        \\    mkdir_ok = eq mkdir_status, 0
        \\    !mkdir_status
        \\    br mkdir_ok -> L_WRITE_TEXT, L_FAIL_MKDIR
        \\
        \\L_WRITE_TEXT:
        \\    !mkdir_ok
        \\    EXPAND DENO_WRITE_TEXT_FILE text_status, TEXT_PATH, TEXT_PATH_LEN, TEXT, TEXT_LEN
        \\    text_ok = eq text_status, 0
        \\    !text_status
        \\    br text_ok -> L_WRITE_B64, L_FAIL_TEXT
        \\
        \\L_WRITE_B64:
        \\    !text_ok
        \\    EXPAND DENO_WRITE_FILE_BASE64 b64_status, B64_PATH, B64_PATH_LEN, B64, B64_LEN
        \\    b64_ok = eq b64_status, 0
        \\    !b64_status
        \\    br b64_ok -> L_SLEEP, L_FAIL_B64
        \\
        \\L_SLEEP:
        \\    !b64_ok
        \\    EXPAND DENO_SLEEP_MS sleep_status, 0
        \\    sleep_ok = eq sleep_status, 0
        \\    !sleep_status
        \\    br sleep_ok -> L_PASS, L_FAIL_SLEEP
        \\
        \\L_PASS:
        \\    !sleep_ok
        \\    return 0
        \\
        \\L_FAIL_MKDIR:
        \\    !mkdir_ok
        \\    return 41
        \\
        \\L_FAIL_TEXT:
        \\    !text_ok
        \\    return 42
        \\
        \\L_FAIL_B64:
        \\    !b64_ok
        \\    return 43
        \\
        \\L_FAIL_SLEEP:
        \\    !sleep_ok
        \\    return 44
    ;
    try writeSource(tmp.dir, "deno_fallible_status.sa", source);

    const build_exe_argv = [_][]const u8{ "sa", "build-exe", "deno_fallible_status.sa", "-o", "deno_fallible_status" };
    const exe_code = try saasm.cli.execute(std.testing.allocator, build_exe_argv[0..]);
    try std.testing.expectEqual(@as(u8, 0), exe_code);

    const run_result = try runCommandAnyExit(std.testing.allocator, &[_][]const u8{"./deno_fallible_status"});
    defer std.testing.allocator.free(run_result.stdout);
    defer std.testing.allocator.free(run_result.stderr);
    switch (run_result.term) {
        .exited => |code| try std.testing.expectEqual(@as(u8, 0), code),
        else => return error.TestUnexpectedResult,
    }
}
