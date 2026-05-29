const std = @import("std");
const common = @import("std_smoke_common.zig");
const saasm = common.saasm;

fn flattenFixture(allocator: std.mem.Allocator, path: []const u8, source: []const u8) !saasm.flattener.FlattenResult {
    return try saasm.flattener.flattenFile(allocator, path, source);
}

test "sa_std core primitives are concrete and verifiable" {
    const slice_layout = try common.readFileAlloc(std.testing.allocator, "sa_std/core/slice.sal");
    defer std.testing.allocator.free(slice_layout);
    try std.testing.expectEqualStrings(
        "#def Slice_SIZE = 16\n#def Slice_ptr  = +0\n#def Slice_len  = +8\n",
        slice_layout,
    );

    const slice_src = try common.readFileAlloc(std.testing.allocator, "sa_std/core/slice.sa");
    defer std.testing.allocator.free(slice_src);
    try std.testing.expect(std.mem.containsAtLeast(u8, slice_src, 1, "[MACRO] SLICE_NEW"));
    try std.testing.expect(std.mem.containsAtLeast(u8, slice_src, 1, "[MACRO] SLICE_GET_PTR"));
    try std.testing.expect(std.mem.containsAtLeast(u8, slice_src, 1, "[MACRO] SLICE_GET_LEN"));

    var slice_flat = try saasm.flattener.flatten(std.testing.allocator, slice_src);
    defer slice_flat.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(usize, 0), slice_flat.instructions.len);
    try std.testing.expectEqual(@as(usize, 0), slice_flat.function_sigs.len);

    const mem_src = try common.readFileAlloc(std.testing.allocator, "sa_std/core/mem.sa");
    defer std.testing.allocator.free(mem_src);
    try std.testing.expect(std.mem.containsAtLeast(u8, mem_src, 1, "@export sa_mem_copy"));
    try std.testing.expect(std.mem.containsAtLeast(u8, mem_src, 1, "@export sa_mem_set"));
    try std.testing.expect(std.mem.containsAtLeast(u8, mem_src, 1, "[MACRO] BOX_NEW"));
    try std.testing.expect(std.mem.containsAtLeast(u8, mem_src, 1, "[MACRO] BOX_FREE"));
    try std.testing.expect(std.mem.containsAtLeast(u8, mem_src, 1, "ptr_add"));
    try std.testing.expect(std.mem.containsAtLeast(u8, mem_src, 1, "br done -> L_END, L_BODY"));
    try std.testing.expect(std.mem.containsAtLeast(u8, mem_src, 1, "stack_alloc 8"));
    try std.testing.expect(std.mem.containsAtLeast(u8, mem_src, 1, "store offset_slot+0, 0 as u64"));
    try std.testing.expect(std.mem.containsAtLeast(u8, mem_src, 1, "store remaining_slot+0, count as u64"));
    try std.testing.expect(std.mem.containsAtLeast(u8, mem_src, 1, "next_remaining = sub remaining, one"));
    try std.testing.expect(!std.mem.containsAtLeast(u8, mem_src, 1, "inttoptr"));
    try std.testing.expect(!std.mem.containsAtLeast(u8, mem_src, 1, "i = 0"));

    var mem_flat = try saasm.flattener.flatten(std.testing.allocator, mem_src);
    defer mem_flat.deinit(std.testing.allocator);
    const verified = try saasm.referee.verify(std.testing.allocator, mem_flat.instructions, mem_flat.const_decls);
    switch (verified) {
        .ok => |ok| {
            var owned = ok;
            defer owned.deinit(std.testing.allocator);
            try std.testing.expectEqual(@as(usize, 2), owned.function_sigs.len);
            try std.testing.expect(owned.annotated.len > 0);
        },
        .trap => |report| {
            std.debug.print("std smoke verifier trap: {s}\n", .{report.message});
            return error.TestUnexpectedResult;
        },
    }
}

test "sa_std package manifest parses as an empty package boundary" {
    const manifest_src = try common.readFileAlloc(std.testing.allocator, "sa_std/sa.mod");
    defer std.testing.allocator.free(manifest_src);

    var manifest_file = try saasm.pkg.manifest.parseManifestWithFile(std.testing.allocator, manifest_src, "sa_std/sa.mod");
    defer manifest_file.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 0), manifest_file.requires.len);
    try std.testing.expectEqual(@as(usize, 0), manifest_file.mirrors.len);
}

test "sa_std io and process interfaces match native resource ABI" {
    const io_iface = try common.readFileAlloc(std.testing.allocator, "sa_std/io.sai");
    defer std.testing.allocator.free(io_iface);
    try std.testing.expect(std.mem.containsAtLeast(u8, io_iface, 1, "@extern sa_io_stdin() -> u64"));
    try std.testing.expect(std.mem.containsAtLeast(u8, io_iface, 1, "@extern sa_io_read(handle: u64, &buf: ptr, cap: u64, &out_read: ptr) -> i32"));
    try std.testing.expect(std.mem.containsAtLeast(u8, io_iface, 1, "@extern sa_io_write(handle: u64, &buf: ptr, len: u64, &out_written: ptr) -> i32"));
    try std.testing.expect(std.mem.containsAtLeast(u8, io_iface, 1, "@extern sa_io_close(handle: u64) -> i32"));
    try std.testing.expect(!std.mem.containsAtLeast(u8, io_iface, 1, "@extern sa_io_read(handle: ptr, &buf: ptr, cap: u64) -> u64!"));
    try std.testing.expect(!std.mem.containsAtLeast(u8, io_iface, 1, "@extern sa_io_close(^handle: ptr) -> i32!"));

    const process_iface = try common.readFileAlloc(std.testing.allocator, "sa_std/process.sai");
    defer std.testing.allocator.free(process_iface);
    try std.testing.expect(std.mem.containsAtLeast(u8, process_iface, 1, "@extern sa_std_process_run(&argv: ptr, argv_len: u64, &out_handle: ptr) -> i32"));
    try std.testing.expect(std.mem.containsAtLeast(u8, process_iface, 1, "@extern sa_std_process_wait(handle: u64, &out_code: ptr) -> i32"));
    try std.testing.expect(std.mem.containsAtLeast(u8, process_iface, 1, "@extern sa_std_process_read_stdout(handle: u64, &buf: ptr, cap: u64, &out_read: ptr) -> i32"));
    try std.testing.expect(std.mem.containsAtLeast(u8, process_iface, 1, "@extern sa_std_process_read_stderr(handle: u64, &buf: ptr, cap: u64, &out_read: ptr) -> i32"));
    try std.testing.expect(std.mem.containsAtLeast(u8, process_iface, 1, "@extern sa_std_process_close(handle: u64) -> i32"));
    try std.testing.expect(!std.mem.containsAtLeast(u8, process_iface, 1, "sa_std_process_wait(handle: ptr"));
    try std.testing.expect(!std.mem.containsAtLeast(u8, process_iface, 1, "sa_std_process_close(^handle: ptr"));

    const io_src = try common.readFileAlloc(std.testing.allocator, "sa_std/io.sa");
    defer std.testing.allocator.free(io_src);
    try std.testing.expect(std.mem.containsAtLeast(u8, io_src, 1, "[MACRO] READ "));
    try std.testing.expect(std.mem.containsAtLeast(u8, io_src, 1, "[MACRO] WRITE_SOME"));
    var io_flat = try flattenFixture(std.testing.allocator, "sa_std/io.sa", io_src);
    defer io_flat.deinit(std.testing.allocator);
    try std.testing.expect(io_flat.function_sigs.len > 0);

    const buf_reader_src = try common.readFileAlloc(std.testing.allocator, "sa_std/io/buf_reader.sa");
    defer std.testing.allocator.free(buf_reader_src);
    try std.testing.expect(std.mem.containsAtLeast(u8, buf_reader_src, 1, "call @sa_io_read(%handle, &%buf, %cap, &__buf_reader_read_slot)"));
    try std.testing.expect(std.mem.containsAtLeast(u8, buf_reader_src, 1, "call @sa_io_close(%handle)"));
    var buf_reader_flat = try flattenFixture(std.testing.allocator, "sa_std/io/buf_reader.sa", buf_reader_src);
    defer buf_reader_flat.deinit(std.testing.allocator);
    try std.testing.expect(buf_reader_flat.function_sigs.len > 0);

    const buf_writer_src = try common.readFileAlloc(std.testing.allocator, "sa_std/io/buf_writer.sa");
    defer std.testing.allocator.free(buf_writer_src);
    try std.testing.expect(std.mem.containsAtLeast(u8, buf_writer_src, 1, "call @sa_io_write(%handle, &%buf, %len, &__buf_writer_write_slot)"));
    try std.testing.expect(std.mem.containsAtLeast(u8, buf_writer_src, 1, "call @sa_io_close(%handle)"));
    var buf_writer_flat = try flattenFixture(std.testing.allocator, "sa_std/io/buf_writer.sa", buf_writer_src);
    defer buf_writer_flat.deinit(std.testing.allocator);
    try std.testing.expect(buf_writer_flat.function_sigs.len > 0);
}

test "sa_std Deno compatibility facade covers HubProxy porting surface" {
    const deno_sai = try common.readFileAlloc(std.testing.allocator, "sa_std/deno.sai");
    defer std.testing.allocator.free(deno_sai);
    try std.testing.expect(std.mem.containsAtLeast(u8, deno_sai, 1, "sa_deno_cwd"));
    try std.testing.expect(std.mem.containsAtLeast(u8, deno_sai, 1, "sa_deno_env_set"));
    try std.testing.expect(std.mem.containsAtLeast(u8, deno_sai, 1, "sa_deno_random_uuid"));
    try std.testing.expect(std.mem.containsAtLeast(u8, deno_sai, 1, "sa_deno_args_json"));
    try std.testing.expect(std.mem.containsAtLeast(u8, deno_sai, 1, "sa_deno_btoa"));
    try std.testing.expect(std.mem.containsAtLeast(u8, deno_sai, 1, "sa_deno_atob"));
    try std.testing.expect(std.mem.containsAtLeast(u8, deno_sai, 1, "sa_deno_text_encode"));
    try std.testing.expect(std.mem.containsAtLeast(u8, deno_sai, 1, "sa_deno_text_decode"));
    try std.testing.expect(std.mem.containsAtLeast(u8, deno_sai, 1, "sa_deno_chat_sse_to_responses"));
    try std.testing.expect(std.mem.containsAtLeast(u8, deno_sai, 1, "sa_deno_chat_json_to_responses"));
    try std.testing.expect(std.mem.containsAtLeast(u8, deno_sai, 1, "sa_deno_responses_sse_normalize"));
    try std.testing.expect(std.mem.containsAtLeast(u8, deno_sai, 1, "sa_deno_responses_request_normalize"));
    try std.testing.expect(std.mem.containsAtLeast(u8, deno_sai, 1, "sa_deno_responses_chat_fallback_request"));
    try std.testing.expect(std.mem.containsAtLeast(u8, deno_sai, 1, "sa_deno_jsonrpc_params_string_literal"));
    try std.testing.expect(std.mem.containsAtLeast(u8, deno_sai, 1, "sa_deno_version_json"));
    try std.testing.expect(std.mem.containsAtLeast(u8, deno_sai, 1, "sa_deno_build_json"));
    try std.testing.expect(std.mem.containsAtLeast(u8, deno_sai, 1, "sa_deno_version_deno"));
    try std.testing.expect(std.mem.containsAtLeast(u8, deno_sai, 1, "sa_deno_build_os"));
    try std.testing.expect(std.mem.containsAtLeast(u8, deno_sai, 1, "sa_deno_build_platform_family"));
    try std.testing.expect(std.mem.containsAtLeast(u8, deno_sai, 1, "sa_deno_date_now_iso"));
    try std.testing.expect(std.mem.containsAtLeast(u8, deno_sai, 1, "DENO_HTTP_METHOD_POST"));
    try std.testing.expect(std.mem.containsAtLeast(u8, deno_sai, 1, "sa_http_client_req_send"));
    try std.testing.expect(std.mem.containsAtLeast(u8, deno_sai, 1, "sa_http_client_resp_get_header"));
    try std.testing.expect(std.mem.containsAtLeast(u8, deno_sai, 1, "sa_http_client_resp_body_slice"));
    try std.testing.expect(std.mem.containsAtLeast(u8, deno_sai, 1, "sa_http_server_req_get_method"));
    try std.testing.expect(std.mem.containsAtLeast(u8, deno_sai, 1, "sa_http_server_resp_set_content_type"));
    try std.testing.expect(std.mem.containsAtLeast(u8, deno_sai, 1, "sa_http_server_resp_stream_write"));

    const deno_src = try common.readFileAlloc(std.testing.allocator, "sa_std/deno.sa");
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
    try std.testing.expect(std.mem.containsAtLeast(u8, deno_src, 1, "[MACRO] DENO_NEW_TEXT_ENCODER_ENCODE"));
    try std.testing.expect(std.mem.containsAtLeast(u8, deno_src, 1, "[MACRO] DENO_NEW_TEXT_DECODER_DECODE"));
    try std.testing.expect(std.mem.containsAtLeast(u8, deno_src, 1, "[MACRO] DENO_CHAT_SSE_TO_RESPONSES"));
    try std.testing.expect(std.mem.containsAtLeast(u8, deno_src, 1, "[MACRO] DENO_RESPONSES_SSE_NORMALIZE"));
    try std.testing.expect(std.mem.containsAtLeast(u8, deno_src, 1, "[MACRO] DENO_RESPONSES_REQUEST_NORMALIZE"));
    try std.testing.expect(std.mem.containsAtLeast(u8, deno_src, 1, "[MACRO] DENO_VERSION_JSON"));
    try std.testing.expect(std.mem.containsAtLeast(u8, deno_src, 1, "[MACRO] DENO_VERSION_DENO"));
    try std.testing.expect(std.mem.containsAtLeast(u8, deno_src, 1, "[MACRO] DENO_BUILD_JSON"));
    try std.testing.expect(std.mem.containsAtLeast(u8, deno_src, 1, "[MACRO] DENO_BUILD_OS"));
    try std.testing.expect(std.mem.containsAtLeast(u8, deno_src, 1, "[MACRO] DENO_BUILD_PLATFORM_FAMILY"));
    try std.testing.expect(std.mem.containsAtLeast(u8, deno_src, 1, "[MACRO] DENO_DATE_NOW_ISO"));
    try std.testing.expect(std.mem.containsAtLeast(u8, deno_src, 1, "[MACRO] DENO_DATE_TO_ISO_STRING"));
    try std.testing.expect(std.mem.containsAtLeast(u8, deno_src, 1, "[MACRO] DENO_JSON_PARSE"));
    try std.testing.expect(std.mem.containsAtLeast(u8, deno_src, 1, "[MACRO] DENO_JSON_PARSE_TEXT"));
    try std.testing.expect(std.mem.containsAtLeast(u8, deno_src, 1, "[MACRO] DENO_JSON_STRINGIFY"));
    try std.testing.expect(std.mem.containsAtLeast(u8, deno_src, 1, "[MACRO] DENO_JSON_STRINGIFY_NODE"));
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
    try std.testing.expect(std.mem.containsAtLeast(u8, deno_src, 1, "[MACRO] DENO_COMMAND_SPAWN_STREAM"));
    try std.testing.expect(std.mem.containsAtLeast(u8, deno_src, 1, "[MACRO] DENO_COMMAND_READ_STDOUT"));
    try std.testing.expect(std.mem.containsAtLeast(u8, deno_src, 1, "[MACRO] DENO_NOW_MS"));
    try std.testing.expect(std.mem.containsAtLeast(u8, deno_src, 1, "[MACRO] DENO_LISTEN_TCP"));
    try std.testing.expect(std.mem.containsAtLeast(u8, deno_src, 1, "[MACRO] DENO_CONNECT_TCP"));
    try std.testing.expect(std.mem.containsAtLeast(u8, deno_src, 1, "[MACRO] DENO_HTTP_CLIENT_NEW"));
    try std.testing.expect(std.mem.containsAtLeast(u8, deno_src, 1, "[MACRO] DENO_HTTP_REQUEST_NEW"));
    try std.testing.expect(std.mem.containsAtLeast(u8, deno_src, 1, "[MACRO] DENO_HTTP_REQUEST_SEND"));
    try std.testing.expect(std.mem.containsAtLeast(u8, deno_src, 1, "[MACRO] DENO_HTTP_RESPONSE_GET_HEADER"));
    try std.testing.expect(std.mem.containsAtLeast(u8, deno_src, 1, "[MACRO] DENO_HTTP_RESPONSE_BODY_SLICE"));
    try std.testing.expect(std.mem.containsAtLeast(u8, deno_src, 1, "[MACRO] DENO_HTTP_RESPONSE_READ_CHUNK"));
    try std.testing.expect(std.mem.containsAtLeast(u8, deno_src, 1, "[MACRO] DENO_SERVE_NEW"));
    try std.testing.expect(std.mem.containsAtLeast(u8, deno_src, 1, "[MACRO] DENO_SERVE_REQUEST_METHOD"));
    try std.testing.expect(std.mem.containsAtLeast(u8, deno_src, 1, "[MACRO] DENO_SERVE_RESPONSE_SET_CONTENT_TYPE"));
    try std.testing.expect(std.mem.containsAtLeast(u8, deno_src, 1, "[MACRO] DENO_SERVE_STREAM_WRITE"));
    try std.testing.expect(std.mem.containsAtLeast(u8, deno_src, 1, "[MACRO] DENO_FETCH_CLIENT_NEW"));
    try std.testing.expect(std.mem.containsAtLeast(u8, deno_src, 1, "[MACRO] DENO_FETCH_SEND"));
    try std.testing.expect(std.mem.containsAtLeast(u8, deno_src, 1, "[MACRO] DENO_HEADERS_APPEND"));
    try std.testing.expect(std.mem.containsAtLeast(u8, deno_src, 1, "[MACRO] DENO_HEADERS_GET"));
    try std.testing.expect(std.mem.containsAtLeast(u8, deno_src, 1, "[MACRO] DENO_HEADERS_HAS"));
    try std.testing.expect(std.mem.containsAtLeast(u8, deno_src, 1, "[MACRO] DENO_REQUEST_SET_BODY"));
    try std.testing.expect(std.mem.containsAtLeast(u8, deno_src, 1, "[MACRO] DENO_REQUEST_SEND"));
    try std.testing.expect(std.mem.containsAtLeast(u8, deno_src, 1, "[MACRO] DENO_REQUEST_FREE"));
    try std.testing.expect(std.mem.containsAtLeast(u8, deno_src, 1, "[MACRO] DENO_RESPONSE_STATUS"));
    try std.testing.expect(std.mem.containsAtLeast(u8, deno_src, 1, "[MACRO] DENO_RESPONSE_TEXT"));
    try std.testing.expect(std.mem.containsAtLeast(u8, deno_src, 1, "[MACRO] DENO_RESPONSE_JSON_PARSE"));
    try std.testing.expect(std.mem.containsAtLeast(u8, deno_src, 1, "[MACRO] DENO_RESPONSES_CHAT_FALLBACK_REQUEST"));
    try std.testing.expect(std.mem.containsAtLeast(u8, deno_src, 1, "[MACRO] DENO_JSONRPC_PARAMS_STRING_LITERAL"));

    var deno_flat = try flattenFixture(std.testing.allocator, "sa_std/deno.sa", deno_src);
    defer deno_flat.deinit(std.testing.allocator);
    try std.testing.expect(deno_flat.function_sigs.len >= 60);
}

test "sa_std Deno JSON-RPC params string literal preserves escaped strings" {
    var original_cwd = try std.fs.cwd().openDir(".", .{});
    defer original_cwd.close();
    var tmp = std.testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();

    const runtime_source = try std.fs.cwd().realpathAlloc(std.testing.allocator, "src/runtime/sa_std.zig");
    defer std.testing.allocator.free(runtime_source);
    const include_dir = try std.fs.cwd().realpathAlloc(std.testing.allocator, "src/runtime");
    defer std.testing.allocator.free(include_dir);

    try tmp.dir.setAsCwd();
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
        "-O",
        "Debug",
        "-lc",
        "-femit-bin=libsa_std.a",
    });
    defer std.testing.allocator.free(build_lib_result.stdout);
    defer std.testing.allocator.free(build_lib_result.stderr);
    try std.testing.expectEqual(@as(u8, 0), switch (build_lib_result.term) {
        .Exited => |code| code,
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
        .Exited => |code| code,
        else => return error.TestUnexpectedResult,
    });

    const run_result = try common.runCommand(std.testing.allocator, &.{"./sa_std_deno_jsonrpc_params"});
    defer std.testing.allocator.free(run_result.stdout);
    defer std.testing.allocator.free(run_result.stderr);
    try std.testing.expectEqual(@as(u8, 0), switch (run_result.term) {
        .Exited => |code| code,
        else => return error.TestUnexpectedResult,
    });
    try std.testing.expectEqualStrings("sa_std deno jsonrpc params string literal ok\n", run_result.stdout);
}

test "sa_std Deno chat SSE fallback normalizes Deno proxy edge cases" {
    var original_cwd = try std.fs.cwd().openDir(".", .{});
    defer original_cwd.close();
    var tmp = std.testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();

    const runtime_source = try std.fs.cwd().realpathAlloc(std.testing.allocator, "src/runtime/sa_std.zig");
    defer std.testing.allocator.free(runtime_source);
    const include_dir = try std.fs.cwd().realpathAlloc(std.testing.allocator, "src/runtime");
    defer std.testing.allocator.free(include_dir);

    try tmp.dir.setAsCwd();
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
        "-O",
        "Debug",
        "-lc",
        "-femit-bin=libsa_std.a",
    });
    defer std.testing.allocator.free(build_lib_result.stdout);
    defer std.testing.allocator.free(build_lib_result.stderr);
    try std.testing.expectEqual(@as(u8, 0), switch (build_lib_result.term) {
        .Exited => |code| code,
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
        "sa_std_deno_chat_sse_edges",
    });
    defer std.testing.allocator.free(build_demo_result.stdout);
    defer std.testing.allocator.free(build_demo_result.stderr);
    try std.testing.expectEqual(@as(u8, 0), switch (build_demo_result.term) {
        .Exited => |code| code,
        else => return error.TestUnexpectedResult,
    });

    const run_result = try common.runCommand(std.testing.allocator, &.{"./sa_std_deno_chat_sse_edges"});
    defer std.testing.allocator.free(run_result.stdout);
    defer std.testing.allocator.free(run_result.stderr);
    try std.testing.expectEqual(@as(u8, 0), switch (run_result.term) {
        .Exited => |code| code,
        else => return error.TestUnexpectedResult,
    });
    try std.testing.expectEqualStrings("sa_std deno chat sse proxy edge cases ok\n", run_result.stdout);
}

test "sa_std Deno chat JSON fallback normalizes Deno proxy edge cases" {
    var original_cwd = try std.fs.cwd().openDir(".", .{});
    defer original_cwd.close();
    var tmp = std.testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();

    const runtime_source = try std.fs.cwd().realpathAlloc(std.testing.allocator, "src/runtime/sa_std.zig");
    defer std.testing.allocator.free(runtime_source);
    const include_dir = try std.fs.cwd().realpathAlloc(std.testing.allocator, "src/runtime");
    defer std.testing.allocator.free(include_dir);

    try tmp.dir.setAsCwd();
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
        "-O",
        "Debug",
        "-lc",
        "-femit-bin=libsa_std.a",
    });
    defer std.testing.allocator.free(build_lib_result.stdout);
    defer std.testing.allocator.free(build_lib_result.stderr);
    try std.testing.expectEqual(@as(u8, 0), switch (build_lib_result.term) {
        .Exited => |code| code,
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
        .Exited => |code| code,
        else => return error.TestUnexpectedResult,
    });

    const run_result = try common.runCommand(std.testing.allocator, &.{"./sa_std_deno_chat_json_edges"});
    defer std.testing.allocator.free(run_result.stdout);
    defer std.testing.allocator.free(run_result.stderr);
    try std.testing.expectEqual(@as(u8, 0), switch (run_result.term) {
        .Exited => |code| code,
        else => return error.TestUnexpectedResult,
    });
    try std.testing.expectEqualStrings("sa_std deno chat json proxy edge cases ok\n", run_result.stdout);
}

test "sa_std Deno native responses SSE normalizes MCP events generically" {
    var original_cwd = try std.fs.cwd().openDir(".", .{});
    defer original_cwd.close();
    var tmp = std.testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();

    const runtime_source = try std.fs.cwd().realpathAlloc(std.testing.allocator, "src/runtime/sa_std.zig");
    defer std.testing.allocator.free(runtime_source);
    const include_dir = try std.fs.cwd().realpathAlloc(std.testing.allocator, "src/runtime");
    defer std.testing.allocator.free(include_dir);

    try tmp.dir.setAsCwd();
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
        "-O",
        "Debug",
        "-lc",
        "-femit-bin=libsa_std.a",
    });
    defer std.testing.allocator.free(build_lib_result.stdout);
    defer std.testing.allocator.free(build_lib_result.stderr);
    try std.testing.expectEqual(@as(u8, 0), switch (build_lib_result.term) {
        .Exited => |code| code,
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
        .Exited => |code| code,
        else => return error.TestUnexpectedResult,
    });

    const run_result = try common.runCommand(std.testing.allocator, &.{"./sa_std_deno_responses_sse_normalize"});
    defer std.testing.allocator.free(run_result.stdout);
    defer std.testing.allocator.free(run_result.stderr);
    try std.testing.expectEqual(@as(u8, 0), switch (run_result.term) {
        .Exited => |code| code,
        else => return error.TestUnexpectedResult,
    });
    try std.testing.expectEqualStrings("sa_std deno responses sse normalize ok\n", run_result.stdout);
}

test "sa_std Deno responses request normalizes MCP server aliases generically" {
    var original_cwd = try std.fs.cwd().openDir(".", .{});
    defer original_cwd.close();
    var tmp = std.testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();

    const runtime_source = try std.fs.cwd().realpathAlloc(std.testing.allocator, "src/runtime/sa_std.zig");
    defer std.testing.allocator.free(runtime_source);
    const include_dir = try std.fs.cwd().realpathAlloc(std.testing.allocator, "src/runtime");
    defer std.testing.allocator.free(include_dir);

    try tmp.dir.setAsCwd();
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
        "-O",
        "Debug",
        "-lc",
        "-femit-bin=libsa_std.a",
    });
    defer std.testing.allocator.free(build_lib_result.stdout);
    defer std.testing.allocator.free(build_lib_result.stderr);
    try std.testing.expectEqual(@as(u8, 0), switch (build_lib_result.term) {
        .Exited => |code| code,
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
        .Exited => |code| code,
        else => return error.TestUnexpectedResult,
    });

    const run_result = try common.runCommand(std.testing.allocator, &.{"./sa_std_deno_responses_request_normalize"});
    defer std.testing.allocator.free(run_result.stdout);
    defer std.testing.allocator.free(run_result.stderr);
    try std.testing.expectEqual(@as(u8, 0), switch (run_result.term) {
        .Exited => |code| code,
        else => return error.TestUnexpectedResult,
    });
    try std.testing.expectEqualStrings("sa_std deno responses request normalize ok\n", run_result.stdout);
}

test "sa_std Deno responses chat fallback request builds chat body from Responses input arrays" {
    var original_cwd = try std.fs.cwd().openDir(".", .{});
    defer original_cwd.close();
    var tmp = std.testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();

    const runtime_source = try std.fs.cwd().realpathAlloc(std.testing.allocator, "src/runtime/sa_std.zig");
    defer std.testing.allocator.free(runtime_source);
    const include_dir = try std.fs.cwd().realpathAlloc(std.testing.allocator, "src/runtime");
    defer std.testing.allocator.free(include_dir);

    try tmp.dir.setAsCwd();
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
        "-O",
        "Debug",
        "-lc",
        "-femit-bin=libsa_std.a",
    });
    defer std.testing.allocator.free(build_lib_result.stdout);
    defer std.testing.allocator.free(build_lib_result.stderr);
    try std.testing.expectEqual(@as(u8, 0), switch (build_lib_result.term) {
        .Exited => |code| code,
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
        .Exited => |code| code,
        else => return error.TestUnexpectedResult,
    });

    const run_result = try common.runCommand(std.testing.allocator, &.{"./sa_std_deno_responses_chat_fallback_request"});
    defer std.testing.allocator.free(run_result.stdout);
    defer std.testing.allocator.free(run_result.stderr);
    try std.testing.expectEqual(@as(u8, 0), switch (run_result.term) {
        .Exited => |code| code,
        else => return error.TestUnexpectedResult,
    });
    try std.testing.expectEqualStrings("sa_std deno responses chat fallback request ok\n", run_result.stdout);
}

test "sa_std Deno response text facade links through installed HTTP plugin" {
    var tmp = std.testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();

    const source =
        \\@import "sa_std/deno.sa"
        \\
        \\@main() -> i32:
        \\L_ENTRY:
        \\    response = 0 as ptr
        \\    EXPAND DENO_RESPONSE_TEXT text_status, text_ptr, text_len, response
        \\    !text_status
        \\    !text_ptr
        \\    !text_len
        \\    !response
        \\    return 0
    ;
    try common.writeSource(tmp.dir, "deno_response_text_link.sa", source);

    var original_cwd = try std.fs.cwd().openDir(".", .{});
    defer original_cwd.close();
    try tmp.dir.setAsCwd();
    defer original_cwd.setAsCwd() catch {};

    const build_exe_argv = [_][]const u8{ "sa", "build-exe", "deno_response_text_link.sa", "-o", "deno_response_text_link" };
    const exe_code = try saasm.cli.execute(std.testing.allocator, build_exe_argv[0..]);
    try std.testing.expectEqual(@as(u8, 0), exe_code);
}

test "sa_std rust core helpers are concrete and verifiable" {
    const option_layout = try common.readFileAlloc(std.testing.allocator, "sa_std/core/option.sal");
    defer std.testing.allocator.free(option_layout);
    try std.testing.expectEqualStrings(
        "#def Option_SIZE = 16\n#def Option_tag = +0\n#def Option_value = +8\n#def Option_NONE = 0\n#def Option_SOME = 1\n",
        option_layout,
    );

    const result_layout = try common.readFileAlloc(std.testing.allocator, "sa_std/core/result.sal");
    defer std.testing.allocator.free(result_layout);
    try std.testing.expectEqualStrings(
        "#def Result_SIZE = 24\n#def Result_tag = +0\n#def Result_ok = +8\n#def Result_err = +16\n#def Result_OK = 0\n#def Result_ERR = 1\n",
        result_layout,
    );

    const iter_layout = try common.readFileAlloc(std.testing.allocator, "sa_std/core/iter.sal");
    defer std.testing.allocator.free(iter_layout);
    try std.testing.expectEqualStrings(
        "#def Iter_SIZE = 24\n#def Iter_ptr = +0\n#def Iter_len = +8\n#def Iter_index = +16\n",
        iter_layout,
    );

    const option_src = try common.readFileAlloc(std.testing.allocator, "sa_std/core/option.sa");
    defer std.testing.allocator.free(option_src);
    try std.testing.expect(std.mem.containsAtLeast(u8, option_src, 1, "[MACRO] OPTION_NEW_NONE"));
    try std.testing.expect(std.mem.containsAtLeast(u8, option_src, 1, "[MACRO] OPTION_NEW_SOME"));
    try std.testing.expect(std.mem.containsAtLeast(u8, option_src, 1, "[MACRO] OPTION_IS_SOME"));
    try std.testing.expect(std.mem.containsAtLeast(u8, option_src, 1, "[MACRO] OPTION_IS_NONE"));
    try std.testing.expect(std.mem.containsAtLeast(u8, option_src, 1, "[MACRO] OPTION_GET"));
    try std.testing.expect(std.mem.containsAtLeast(u8, option_src, 1, "[MACRO] OPTION_UNWRAP_OR"));
    try std.testing.expect(std.mem.containsAtLeast(u8, option_src, 1, "[MACRO] OPTION_UNWRAP_OR_RETURN"));
    try std.testing.expect(std.mem.containsAtLeast(u8, option_src, 1, "[MACRO] OPTION_UNWRAP"));
    try std.testing.expect(std.mem.containsAtLeast(u8, option_src, 1, "[MACRO] OPTION_MAP_OR"));
    try std.testing.expect(std.mem.containsAtLeast(u8, option_src, 1, "[MACRO] OPTION_MAP_OR_ELSE"));
    try std.testing.expect(std.mem.containsAtLeast(u8, option_src, 1, "[MACRO] OPTION_SET_NONE"));
    try std.testing.expect(std.mem.containsAtLeast(u8, option_src, 1, "[MACRO] OPTION_SET_SOME"));
    try std.testing.expect(std.mem.containsAtLeast(u8, option_src, 1, "[MACRO] OPTION_BRANCH"));
    try std.testing.expect(std.mem.containsAtLeast(u8, option_src, 1, "[MACRO] MATCHES_OPTION"));
    try std.testing.expect(std.mem.containsAtLeast(u8, option_src, 1, "[MACRO] MATCH_OPTION"));
    try std.testing.expect(std.mem.containsAtLeast(u8, option_src, 1, "[MACRO] OPTION_MATCH_SOME_NONE"));

    const result_src = try common.readFileAlloc(std.testing.allocator, "sa_std/core/result.sa");
    defer std.testing.allocator.free(result_src);
    try std.testing.expect(std.mem.containsAtLeast(u8, result_src, 1, "[MACRO] RESULT_NEW_OK"));
    try std.testing.expect(std.mem.containsAtLeast(u8, result_src, 1, "[MACRO] RESULT_NEW_ERR"));
    try std.testing.expect(std.mem.containsAtLeast(u8, result_src, 1, "[MACRO] RESULT_IS_OK"));
    try std.testing.expect(std.mem.containsAtLeast(u8, result_src, 1, "[MACRO] RESULT_IS_ERR"));
    try std.testing.expect(std.mem.containsAtLeast(u8, result_src, 1, "[MACRO] RESULT_GET_OK"));
    try std.testing.expect(std.mem.containsAtLeast(u8, result_src, 1, "[MACRO] RESULT_GET_ERR"));
    try std.testing.expect(std.mem.containsAtLeast(u8, result_src, 1, "[MACRO] RESULT_UNWRAP_OR"));
    try std.testing.expect(std.mem.containsAtLeast(u8, result_src, 1, "[MACRO] RESULT_RETURN_ERR"));
    try std.testing.expect(std.mem.containsAtLeast(u8, result_src, 1, "[MACRO] RESULT_MAP_OK"));
    try std.testing.expect(std.mem.containsAtLeast(u8, result_src, 1, "[MACRO] RESULT_UNWRAP"));
    try std.testing.expect(std.mem.containsAtLeast(u8, result_src, 1, "[MACRO] RESULT_UNWRAP_ERR"));
    try std.testing.expect(std.mem.containsAtLeast(u8, result_src, 1, "[MACRO] RESULT_MAP_OR"));
    try std.testing.expect(std.mem.containsAtLeast(u8, result_src, 1, "[MACRO] RESULT_MAP_OR_ELSE"));
    try std.testing.expect(std.mem.containsAtLeast(u8, result_src, 1, "[MACRO] RESULT_SET_OK"));
    try std.testing.expect(std.mem.containsAtLeast(u8, result_src, 1, "[MACRO] RESULT_SET_ERR"));
    try std.testing.expect(std.mem.containsAtLeast(u8, result_src, 1, "[MACRO] RESULT_BRANCH"));
    try std.testing.expect(std.mem.containsAtLeast(u8, result_src, 1, "[MACRO] MATCH_RESULT"));
    try std.testing.expect(std.mem.containsAtLeast(u8, result_src, 1, "[MACRO] MATCHES_RESULT"));
    try std.testing.expect(std.mem.containsAtLeast(u8, result_src, 1, "[MACRO] RESULT_MATCH_OK_ERR"));

    const stringify_src = try common.readFileAlloc(std.testing.allocator, "src/flattener.zig");
    defer std.testing.allocator.free(stringify_src);
    try std.testing.expect(std.mem.containsAtLeast(u8, stringify_src, 1, "STRINGIFY!"));

    const sa_core_src = try common.readFileAlloc(std.testing.allocator, "sa_std/core/sa_core.sa");
    defer std.testing.allocator.free(sa_core_src);
    try std.testing.expect(std.mem.containsAtLeast(u8, sa_core_src, 1, "[MACRO] CFG"));

    const panic_src = try common.readFileAlloc(std.testing.allocator, "sa_std/core/panic.sa");
    defer std.testing.allocator.free(panic_src);
    try std.testing.expect(std.mem.containsAtLeast(u8, panic_src, 1, "[MACRO] PANIC "));
    try std.testing.expect(std.mem.containsAtLeast(u8, panic_src, 1, "[MACRO] PANIC_MSG"));
    try std.testing.expect(std.mem.containsAtLeast(u8, panic_src, 1, "[MACRO] TODO"));
    try std.testing.expect(std.mem.containsAtLeast(u8, panic_src, 1, "[MACRO] UNIMPLEMENTED"));
    try std.testing.expect(std.mem.containsAtLeast(u8, panic_src, 1, "[MACRO] UNREACHABLE"));

    const iter_src = try common.readFileAlloc(std.testing.allocator, "sa_std/core/iter.sa");
    defer std.testing.allocator.free(iter_src);
    try std.testing.expect(std.mem.containsAtLeast(u8, iter_src, 1, "[MACRO] ITER_NEW"));
    try std.testing.expect(std.mem.containsAtLeast(u8, iter_src, 1, "[MACRO] ITER_FROM_SLICE"));
    try std.testing.expect(std.mem.containsAtLeast(u8, iter_src, 1, "[MACRO] ITER_IS_EMPTY"));
    try std.testing.expect(std.mem.containsAtLeast(u8, iter_src, 1, "[MACRO] ITER_HAS_NEXT"));
    try std.testing.expect(std.mem.containsAtLeast(u8, iter_src, 1, "[MACRO] ITER_REMAINING"));
    try std.testing.expect(std.mem.containsAtLeast(u8, iter_src, 1, "[MACRO] ITER_LEN"));
    try std.testing.expect(std.mem.containsAtLeast(u8, iter_src, 1, "[MACRO] ITER_PEEK_U64"));
    try std.testing.expect(std.mem.containsAtLeast(u8, iter_src, 1, "[MACRO] ITER_NEXT"));
    try std.testing.expect(std.mem.containsAtLeast(u8, iter_src, 1, "[MACRO] ITER_NEXT_U64"));

    const loop_src = try common.readFileAlloc(std.testing.allocator, "sa_std/core/loop.sa");
    defer std.testing.allocator.free(loop_src);
    try std.testing.expect(std.mem.containsAtLeast(u8, loop_src, 1, "[MACRO] WHILE"));
    try std.testing.expect(std.mem.containsAtLeast(u8, loop_src, 1, "[MACRO] WHILE_COND"));
    try std.testing.expect(std.mem.containsAtLeast(u8, loop_src, 1, "[MACRO] FOR_RANGE"));
    try std.testing.expect(std.mem.containsAtLeast(u8, loop_src, 1, "[MACRO] INDEX_LOOP"));
    try std.testing.expect(std.mem.containsAtLeast(u8, loop_src, 1, "[MACRO] ARRAY_SCAN_MIN"));
    try std.testing.expect(std.mem.containsAtLeast(u8, loop_src, 1, "[MACRO] ARRAY_SCAN_MAX"));

    const control_src = try common.readFileAlloc(std.testing.allocator, "sa_std/core/control.sa");
    defer std.testing.allocator.free(control_src);
    try std.testing.expect(std.mem.containsAtLeast(u8, control_src, 1, "[MACRO] MATCH_BOOL"));
    try std.testing.expect(std.mem.containsAtLeast(u8, control_src, 1, "[MACRO] ELIF"));
    try std.testing.expect(std.mem.containsAtLeast(u8, control_src, 1, "[MACRO] WHILE_LET"));
    try std.testing.expect(std.mem.containsAtLeast(u8, control_src, 1, "[MACRO] BREAK_IF"));
    try std.testing.expect(std.mem.containsAtLeast(u8, control_src, 1, "[MACRO] CONTINUE_IF"));

    const bit_src = try common.readFileAlloc(std.testing.allocator, "sa_std/core/bit.sa");
    defer std.testing.allocator.free(bit_src);
    try std.testing.expect(std.mem.containsAtLeast(u8, bit_src, 1, "[MACRO] BIT_MASK"));
    try std.testing.expect(std.mem.containsAtLeast(u8, bit_src, 1, "[MACRO] BIT_SET"));
    try std.testing.expect(std.mem.containsAtLeast(u8, bit_src, 1, "[MACRO] BIT_GET"));
    try std.testing.expect(std.mem.containsAtLeast(u8, bit_src, 1, "[MACRO] BIT_CLEAR"));
    try std.testing.expect(std.mem.containsAtLeast(u8, bit_src, 1, "[MACRO] BIT_TEST"));
    try std.testing.expect(std.mem.containsAtLeast(u8, bit_src, 1, "[MACRO] BIT_INDEX_BYTE"));
    try std.testing.expect(std.mem.containsAtLeast(u8, bit_src, 1, "[MACRO] BIT_INDEX_BIT"));

    const hash_src = try common.readFileAlloc(std.testing.allocator, "sa_std/core/hash.sa");
    defer std.testing.allocator.free(hash_src);
    try std.testing.expect(std.mem.containsAtLeast(u8, hash_src, 1, "[MACRO] HASH_PTR"));
    try std.testing.expect(std.mem.containsAtLeast(u8, hash_src, 1, "[MACRO] HASH_MIX"));
    try std.testing.expect(std.mem.containsAtLeast(u8, hash_src, 1, "[MACRO] HASH_MOD"));
    try std.testing.expect(std.mem.containsAtLeast(u8, hash_src, 1, "[MACRO] PROBE_START"));
    try std.testing.expect(std.mem.containsAtLeast(u8, hash_src, 1, "[MACRO] PROBE_NEXT"));
    try std.testing.expect(std.mem.containsAtLeast(u8, hash_src, 1, "[MACRO] MAP_LOOKUP"));
    try std.testing.expect(std.mem.containsAtLeast(u8, hash_src, 1, "[MACRO] MAP_INSERT_OR_UPDATE"));

    const cleanup_src = try common.readFileAlloc(std.testing.allocator, "sa_std/core/cleanup.sa");
    defer std.testing.allocator.free(cleanup_src);
    try std.testing.expect(std.mem.containsAtLeast(u8, cleanup_src, 1, "[MACRO] DEFER"));
    try std.testing.expect(std.mem.containsAtLeast(u8, cleanup_src, 1, "[MACRO] CLEANUP_ON_ERROR"));
    try std.testing.expect(std.mem.containsAtLeast(u8, cleanup_src, 1, "[MACRO] WITH_TEMP"));
    try std.testing.expect(std.mem.containsAtLeast(u8, cleanup_src, 1, "[MACRO] RETURN_CLEAN"));
    try std.testing.expect(std.mem.containsAtLeast(u8, cleanup_src, 1, "[MACRO] FREE_AND_RETURN"));

    const rust_core_src = try common.readFileAlloc(std.testing.allocator, "sa_std/rust_core.sa");
    defer std.testing.allocator.free(rust_core_src);
    try std.testing.expect(std.mem.containsAtLeast(u8, rust_core_src, 1, "@import \"core/option.sa\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, rust_core_src, 1, "@import \"core/result.sa\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, rust_core_src, 1, "@import \"core/panic.sa\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, rust_core_src, 1, "@import \"core/iter.sa\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, rust_core_src, 1, "@import \"core/cell.sa\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, rust_core_src, 1, "@import \"core/refcell.sa\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, rust_core_src, 1, "@import \"core/rc.sa\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, rust_core_src, 1, "@import \"core/weak.sa\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, rust_core_src, 1, "@import \"core/derive.sa\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, rust_core_src, 1, "@import \"core/loop.sa\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, rust_core_src, 1, "@import \"core/control.sa\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, rust_core_src, 1, "@import \"core/bit.sa\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, rust_core_src, 1, "@import \"core/hash.sa\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, rust_core_src, 1, "@import \"core/cleanup.sa\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, rust_core_src, 1, "@import \"sync/rwlock.sa\""));

    const cell_layout = try common.readFileAlloc(std.testing.allocator, "sa_std/core/cell.sal");
    defer std.testing.allocator.free(cell_layout);
    try std.testing.expectEqualStrings("#def Cell_SIZE = 4\n#def Cell_value = +0\n", cell_layout);

    const refcell_layout = try common.readFileAlloc(std.testing.allocator, "sa_std/core/refcell.sal");
    defer std.testing.allocator.free(refcell_layout);
    try std.testing.expectEqualStrings("#def RefCell_SIZE = 8\n#def RefCell_value = +0\n#def RefCell_borrows = +4\n", refcell_layout);

    const rc_layout = try common.readFileAlloc(std.testing.allocator, "sa_std/core/rc.sal");
    defer std.testing.allocator.free(rc_layout);
    try std.testing.expectEqualStrings("#def RcBox_SIZE = 24\n#def RcBox_strong = +0\n#def RcBox_weak = +8\n#def RcBox_data = +16\n", rc_layout);

    const weak_layout = try common.readFileAlloc(std.testing.allocator, "sa_std/core/weak.sal");
    defer std.testing.allocator.free(weak_layout);
    try std.testing.expectEqualStrings("#def WeakBox_SIZE = 24\n#def WeakBox_strong = +0\n#def WeakBox_weak = +8\n#def WeakBox_data = +16\n", weak_layout);

    const cell_src = try common.readFileAlloc(std.testing.allocator, "sa_std/core/cell.sa");
    defer std.testing.allocator.free(cell_src);
    try std.testing.expect(std.mem.containsAtLeast(u8, cell_src, 1, "[MACRO] CELL_NEW"));
    try std.testing.expect(std.mem.containsAtLeast(u8, cell_src, 1, "[MACRO] CELL_SET"));
    try std.testing.expect(std.mem.containsAtLeast(u8, cell_src, 1, "[MACRO] CELL_REPLACE"));

    const refcell_src = try common.readFileAlloc(std.testing.allocator, "sa_std/core/refcell.sa");
    defer std.testing.allocator.free(refcell_src);
    try std.testing.expect(std.mem.containsAtLeast(u8, refcell_src, 1, "[MACRO] REFCELL_NEW"));
    try std.testing.expect(std.mem.containsAtLeast(u8, refcell_src, 1, "[MACRO] REFCELL_BORROW"));
    try std.testing.expect(std.mem.containsAtLeast(u8, refcell_src, 1, "[MACRO] REFCELL_BORROW_MUT"));
    try std.testing.expect(std.mem.containsAtLeast(u8, refcell_src, 1, "[MACRO] REFCELL_RELEASE"));

    const derive_src = try common.readFileAlloc(std.testing.allocator, "sa_std/core/derive.sa");
    defer std.testing.allocator.free(derive_src);
    try std.testing.expect(std.mem.containsAtLeast(u8, derive_src, 1, "[MACRO] STRUCT_COPY"));
    try std.testing.expect(std.mem.containsAtLeast(u8, derive_src, 1, "[MACRO] STRUCT_EQ_FIELD"));
    try std.testing.expect(std.mem.containsAtLeast(u8, derive_src, 1, "[MACRO] STRUCT_EQ4"));

    const rc_src = try common.readFileAlloc(std.testing.allocator, "sa_std/core/rc.sa");
    defer std.testing.allocator.free(rc_src);
    try std.testing.expect(std.mem.containsAtLeast(u8, rc_src, 1, "[MACRO] RC_NEW"));
    try std.testing.expect(std.mem.containsAtLeast(u8, rc_src, 1, "[MACRO] RC_CLONE"));
    try std.testing.expect(std.mem.containsAtLeast(u8, rc_src, 1, "[MACRO] RC_DROP"));
    try std.testing.expect(std.mem.containsAtLeast(u8, rc_src, 1, "[MACRO] RC_DOWNGRADE"));
    try std.testing.expect(std.mem.containsAtLeast(u8, rc_src, 1, "[MACRO] WEAK_CLONE"));
    try std.testing.expect(std.mem.containsAtLeast(u8, rc_src, 1, "[MACRO] WEAK_DROP"));
    try std.testing.expect(std.mem.containsAtLeast(u8, rc_src, 1, "[MACRO] WEAK_UPGRADE"));

    const weak_src = try common.readFileAlloc(std.testing.allocator, "sa_std/core/weak.sa");
    defer std.testing.allocator.free(weak_src);
    try std.testing.expect(std.mem.containsAtLeast(u8, weak_src, 1, "@import \"weak.sal\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, weak_src, 1, "@import \"rc.sa\""));

    var option_flat = try flattenFixture(std.testing.allocator, "sa_std/core/option.sa", option_src);
    defer option_flat.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(usize, 0), option_flat.instructions.len);
    try std.testing.expectEqual(@as(usize, 0), option_flat.function_sigs.len);

    var result_flat = try flattenFixture(std.testing.allocator, "sa_std/core/result.sa", result_src);
    defer result_flat.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(usize, 0), result_flat.instructions.len);
    try std.testing.expectEqual(@as(usize, 0), result_flat.function_sigs.len);

    var panic_flat = try flattenFixture(std.testing.allocator, "sa_std/core/panic.sa", panic_src);
    defer panic_flat.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(usize, 0), panic_flat.instructions.len);
    try std.testing.expectEqual(@as(usize, 0), panic_flat.function_sigs.len);

    var iter_flat = try flattenFixture(std.testing.allocator, "sa_std/core/iter.sa", iter_src);
    defer iter_flat.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(usize, 0), iter_flat.instructions.len);
    try std.testing.expectEqual(@as(usize, 0), iter_flat.function_sigs.len);

    var rust_core_flat = try flattenFixture(std.testing.allocator, "sa_std/rust_core.sa", rust_core_src);
    defer rust_core_flat.deinit(std.testing.allocator);
    try std.testing.expect(rust_core_flat.instructions.len > 0);
    try std.testing.expect(rust_core_flat.function_sigs.len > 0);
    try std.testing.expect(rust_core_flat.instructions.len >= 1);
}
