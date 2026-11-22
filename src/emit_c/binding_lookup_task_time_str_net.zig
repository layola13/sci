const std = @import("std");
const Binding = @import("binding_types.zig").Binding;

pub fn bindingForTaskTimeStrNet(name: []const u8) ?Binding {
    const all_void: u64 = ~@as(u64, 0);
    return     if (std.mem.eql(u8, name, "sa_task_spawn"))
        .{ .voids = all_void ^ 0b111, .tag = .task_spawn }
    else if (std.mem.eql(u8, name, "sa_task_spawn_supervised"))
        .{ .voids = all_void ^ 0b11111, .tag = .task_spawn_supervised }
    else if (std.mem.eql(u8, name, "sa_task_trap_info"))
        .{ .voids = all_void ^ 0b1111, .tag = .task_trap_info }
    else if (std.mem.eql(u8, name, "sa_task_monitor"))
        .{ .voids = all_void ^ 0b11, .tag = .task_handle_out1 }
    else if (std.mem.eql(u8, name, "sa_task_yield"))
        .{ .voids = all_void, .tag = .task_noargs_ret }
    else if (std.mem.eql(u8, name, "sa_task_sleep_ns"))
        .{ .voids = all_void ^ 0b1, .tag = .task_handle_ret }
    else if (std.mem.eql(u8, name, "sa_task_sleep_ms"))
        .{ .voids = all_void ^ 0b1, .tag = .task_handle_ret }
    else if (std.mem.eql(u8, name, "sa_task_join"))
        .{ .voids = all_void ^ 0b1, .tag = .task_handle_ret }
    else if (std.mem.eql(u8, name, "sa_task_detach"))
        .{ .voids = all_void ^ 0b1, .tag = .task_handle_ret }
    else if (std.mem.eql(u8, name, "sa_task_current"))
        .{ .voids = all_void ^ 0b1, .tag = .task_out0 }
    else if (std.mem.eql(u8, name, "sa_task_live_count"))
        .{ .voids = all_void ^ 0b1, .tag = .task_out0 }
    else if (std.mem.eql(u8, name, "sa_task_deadlock_guard_arm"))
        .{ .voids = all_void, .tag = .task_noargs_ret }
    else if (std.mem.eql(u8, name, "sa_task_net_wait"))
        .{ .voids = all_void ^ 0b1111, .tag = .task_net_wait }
    else if (std.mem.eql(u8, name, "sa_node_plugin_path_normalize"))
        .{ .voids = all_void ^ 0b1111, .tag = .node_path_normalize }
    else if (std.mem.eql(u8, name, "sa_node_plugin_path_dirname"))
        .{ .voids = all_void ^ 0b1111, .tag = .node_path_dirname }
    else if (std.mem.eql(u8, name, "sa_node_plugin_path_extname"))
        .{ .voids = all_void ^ 0b1111, .tag = .node_path_extname }
    else if (std.mem.eql(u8, name, "sa_node_plugin_path_is_absolute"))
        .{ .voids = all_void ^ 0b111, .tag = .node_path_is_absolute }
    else if (std.mem.eql(u8, name, "sa_node_plugin_path_join"))
        .{ .voids = all_void ^ 0b1111, .tag = .node_path_join }
    else if (std.mem.eql(u8, name, "sa_node_plugin_querystring_escape"))
        .{ .voids = all_void ^ 0b1111, .tag = .node_qs_escape }
    else if (std.mem.eql(u8, name, "sa_node_plugin_querystring_unescape"))
        .{ .voids = all_void ^ 0b1111, .tag = .node_qs_unescape }
    else if (std.mem.eql(u8, name, "sa_node_plugin_punycode_encode"))
        .{ .voids = all_void ^ 0b1111, .tag = .node_puny_encode }
    else if (std.mem.eql(u8, name, "sa_node_plugin_punycode_decode"))
        .{ .voids = all_void ^ 0b1111, .tag = .node_puny_decode }
    else if (std.mem.eql(u8, name, "sa_node_plugin_buffer_concat"))
        .{ .voids = all_void ^ 0b1111, .tag = .node_buf_concat }
    else if (std.mem.eql(u8, name, "sa_node_plugin_crypto_random_bytes"))
        .{ .voids = all_void ^ 0b11, .tag = .node_rand_bytes }
    else if (std.mem.eql(u8, name, "sa_node_plugin_crypto_hash"))
        .{ .voids = all_void ^ 0b111111, .tag = .node_crypto_hash }
    else if (std.mem.eql(u8, name, "sa_http_websocket_read"))
        .{ .voids = all_void ^ 0b11111, .tag = .hc_ws_read }
    else if (std.mem.eql(u8, name, "sa_http_websocket_write"))
        .{ .voids = all_void ^ 0b1111, .tag = .hc_ws_write }
    else if (std.mem.eql(u8, name, "sa_http_websocket_free"))
        .{ .voids = all_void ^ 0b1, .tag = .hc_ws_free }
    else if (std.mem.eql(u8, name, "sa_http_websocket_poll_v2"))
        .{ .voids = all_void ^ 0b1111, .tag = .hc2_ws_poll }
    else if (std.mem.eql(u8, name, "sa_http_websocket_read_v2"))
        .{ .voids = all_void ^ 0b11111, .tag = .hc2_ws_read }
    else if (std.mem.eql(u8, name, "sa_http_websocket_write_v2"))
        .{ .voids = all_void ^ 0b11111, .tag = .hc2_ws_write }
    else if (std.mem.eql(u8, name, "sa_http_websocket_close_v2"))
        .{ .voids = all_void ^ 0b1111, .tag = .hc2_ws_close }
    else if (std.mem.eql(u8, name, "sa_http_websocket_free_v2"))
        .{ .voids = all_void ^ 0b1, .tag = .hc_ws_free }
    else if (std.mem.eql(u8, name, "sa_chan_make"))
        .{ .voids = all_void ^ 0b11, .tag = .task_chan_make }
    else if (std.mem.eql(u8, name, "sa_chan_destroy"))
        .{ .voids = all_void ^ 0b1, .tag = .task_handle_ret }
    else if (std.mem.eql(u8, name, "sa_chan_close"))
        .{ .voids = all_void ^ 0b1, .tag = .task_handle_ret }
    else if (std.mem.eql(u8, name, "sa_chan_send"))
        .{ .voids = all_void ^ 0b11, .tag = .task_chan_send }
    else if (std.mem.eql(u8, name, "sa_chan_recv"))
        .{ .voids = all_void ^ 0b111, .tag = .task_chan_recv }
    else if (std.mem.eql(u8, name, "sa_chan_len"))
        .{ .voids = all_void ^ 0b11, .tag = .task_handle_out1 }
    else if (std.mem.eql(u8, name, "sa_chan_cap"))
        .{ .voids = all_void ^ 0b11, .tag = .task_handle_out1 }
    else if (std.mem.eql(u8, name, "sa_chan_select"))
        .{ .voids = all_void ^ 0b11111111, .tag = .task_select }
    else if (std.mem.eql(u8, name, "sa_math_floor"))
        .{ .voids = all_void ^ 0b1, .tag = .math_floor }
    else if (std.mem.eql(u8, name, "sa_math_ceil"))
        .{ .voids = all_void ^ 0b1, .tag = .math_ceil }
    else if (std.mem.eql(u8, name, "sa_math_sqrt"))
        .{ .voids = all_void ^ 0b1, .tag = .math_sqrt }
    else if (std.mem.eql(u8, name, "sa_math_sin"))
        .{ .voids = all_void ^ 0b1, .tag = .math_sin }
    else if (std.mem.eql(u8, name, "sa_math_cos"))
        .{ .voids = all_void ^ 0b1, .tag = .math_cos }
    else if (std.mem.eql(u8, name, "sa_math_pow"))
        .{ .voids = all_void ^ 0b11, .tag = .math_pow }
    else if (std.mem.eql(u8, name, "sa_math_random"))
        .{ .voids = all_void, .tag = .math_random }
    else if (std.mem.eql(u8, name, "sa_env_get"))
        .{ .voids = all_void ^ 0b11, .tag = .env_get }
    else if (std.mem.eql(u8, name, "sa_env_has"))
        .{ .voids = all_void ^ 0b11, .tag = .env_has }
    else if (std.mem.eql(u8, name, "sa_env_set_var"))
        .{ .voids = all_void ^ 0b1111, .tag = .env_set_var }
    else if (std.mem.eql(u8, name, "sa_env_remove_var"))
        .{ .voids = all_void ^ 0b11, .tag = .env_remove_var }
    else if (std.mem.eql(u8, name, "sa_env_buffer_data"))
        .{ .voids = all_void ^ 0b1, .tag = .env_buffer_data }
    else if (std.mem.eql(u8, name, "sa_env_buffer_len"))
        .{ .voids = all_void ^ 0b1, .tag = .env_buffer_len }
    else if (std.mem.eql(u8, name, "sa_env_buffer_free"))
        .{ .voids = all_void ^ 0b1, .tag = .env_buffer_free }
    else if (std.mem.eql(u8, name, "sa_deno_btoa"))
        .{ .voids = all_void ^ 0b11, .tag = .deno_btoa_handle }
    else if (std.mem.eql(u8, name, "sa_deno_plugin_btoa"))
        .{ .voids = all_void ^ 0b1111, .tag = .deno_btoa }
    else if (std.mem.eql(u8, name, "sa_deno_plugin_atob"))
        .{ .voids = all_void ^ 0b1111, .tag = .deno_atob }
    else if (std.mem.eql(u8, name, "sa_deno_plugin_read_text_file"))
        .{ .voids = all_void ^ 0b1111, .tag = .deno_read_file }
    else if (std.mem.eql(u8, name, "sa_deno_plugin_write_text_file"))
        .{ .voids = all_void ^ 0b1111, .tag = .deno_write_file }
    else if (std.mem.eql(u8, name, "sa_deno_plugin_remove"))
        .{ .voids = all_void, .tag = .deno_remove }
    else if (std.mem.eql(u8, name, "sa_deno_plugin_mkdir"))
        .{ .voids = all_void ^ 0b111, .tag = .deno_mkdir }
    else if (std.mem.eql(u8, name, "sa_time_unix_ms"))
        .{ .voids = all_void, .tag = .time_unix_ms }
    else if (std.mem.eql(u8, name, "sa_time_get_full_year"))
        .{ .voids = all_void ^ 0b1, .tag = .time_get_full_year }
    else if (std.mem.eql(u8, name, "sa_time_get_month"))
        .{ .voids = all_void ^ 0b1, .tag = .time_get_month }
    else if (std.mem.eql(u8, name, "sa_time_get_date"))
        .{ .voids = all_void ^ 0b1, .tag = .time_get_date }
    else if (std.mem.eql(u8, name, "sa_time_parse_iso"))
        .{ .voids = all_void ^ 0b111, .tag = .time_parse_iso }
    else if (std.mem.eql(u8, name, "sa_time_set_field"))
        .{ .voids = all_void ^ 0b111, .tag = .time_set_field }
    else if (std.mem.eql(u8, name, "sa_str_is_ascii"))
        .{ .voids = all_void ^ 0b11, .tag = .str_is_ascii }
    else if (std.mem.eql(u8, name, "sa_str_eq_ignore_ascii_case"))
        .{ .voids = all_void ^ 0b1111, .tag = .str_eq_ignore_ascii_case }
    else if (std.mem.eql(u8, name, "sa_str_trim_ascii_start_index"))
        .{ .voids = all_void ^ 0b11, .tag = .str_trim_ascii_start_index }
    else if (std.mem.eql(u8, name, "sa_str_trim_ascii_end_len"))
        .{ .voids = all_void ^ 0b11, .tag = .str_trim_ascii_end_len }
    else if (std.mem.eql(u8, name, "fd_open"))
        .{ .voids = all_void, .tag = .fd_open }
    else if (std.mem.eql(u8, name, "fd_close"))
        .{ .voids = all_void, .tag = .fd_close }
    else if (std.mem.eql(u8, name, "fd_read"))
        .{ .voids = all_void, .tag = .fd_read }
    else if (std.mem.eql(u8, name, "pthread_spawn"))
        .{ .voids = all_void ^ 0b11, .tag = .pthread_spawn }
    else if (std.mem.eql(u8, name, "pthread_join"))
        .{ .voids = all_void, .tag = .pthread_join }
    else if (std.mem.eql(u8, name, "pthread_drop"))
        .{ .voids = all_void, .tag = .pthread_drop }
    else if (std.mem.eql(u8, name, "sqlite3_prepare"))
        .{ .voids = all_void, .tag = .sqlite3_prepare }
    else if (std.mem.eql(u8, name, "sqlite3_step"))
        .{ .voids = all_void, .tag = .sqlite3_step }
    else if (std.mem.eql(u8, name, "sqlite3_finalize"))
        .{ .voids = all_void, .tag = .sqlite3_finalize }
    else if (std.mem.eql(u8, name, "sa_net_addr_family"))
        .{ .voids = all_void ^ 0b1, .tag = .na_family }
    else if (std.mem.eql(u8, name, "sa_net_addr_free"))
        .{ .voids = all_void ^ 0b1, .tag = .na_free }
    else if (std.mem.eql(u8, name, "sa_net_addr_port"))
        .{ .voids = all_void ^ 0b1, .tag = .na_port }
    else if (std.mem.eql(u8, name, "mmap"))
        .{ .voids = 0b1, .tag = .mmap }
    else if (std.mem.eql(u8, name, "munmap"))
        .{ .voids = all_void, .tag = .munmap }
    else
        null;
}
