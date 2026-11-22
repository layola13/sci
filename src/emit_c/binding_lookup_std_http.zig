const std = @import("std");
const Binding = @import("binding_types.zig").Binding;

pub fn bindingForStdHttp(name: []const u8) ?Binding {
    const all_void: u64 = ~@as(u64, 0);
    return     if (std.mem.eql(u8, name, "sa_std_fs_exists"))
        .{ .voids = all_void ^ 0b11, .tag = .std_fs_exists }
    else if (std.mem.eql(u8, name, "sa_std_compress_supported"))
        .{ .voids = all_void ^ 0b1, .tag = .nb_compress_supported }
    else if (std.mem.eql(u8, name, "sa_std_compress_encode"))
        .{ .voids = all_void ^ 0b1111, .tag = .nb_compress_encode }
    else if (std.mem.eql(u8, name, "sa_std_compress_decode"))
        .{ .voids = all_void ^ 0b1111, .tag = .nb_compress_decode }
    else if (std.mem.eql(u8, name, "sa_std_compress_buffer_data"))
        .{ .voids = all_void ^ 0b1, .tag = .nb_buf_data }
    else if (std.mem.eql(u8, name, "sa_std_compress_buffer_len"))
        .{ .voids = all_void ^ 0b1, .tag = .nb_buf_len }
    else if (std.mem.eql(u8, name, "sa_std_compress_buffer_free"))
        .{ .voids = all_void ^ 0b1, .tag = .nb_buf_free }
    else if (std.mem.eql(u8, name, "sa_std_multipart_parse"))
        .{ .voids = all_void ^ 0b11111, .tag = .mp_parse }
    else if (std.mem.eql(u8, name, "sa_std_multipart_free"))
        .{ .voids = all_void ^ 0b1, .tag = .mp_free }
    else if (std.mem.eql(u8, name, "sa_std_multipart_count"))
        .{ .voids = all_void ^ 0b1, .tag = .mp_count }
    else if (std.mem.eql(u8, name, "sa_std_multipart_part_name"))
        .{ .voids = all_void ^ 0b11111, .tag = .mp_part_name }
    else if (std.mem.eql(u8, name, "sa_std_multipart_part_filename"))
        .{ .voids = all_void ^ 0b11111, .tag = .mp_part_filename }
    else if (std.mem.eql(u8, name, "sa_std_multipart_part_content_type"))
        .{ .voids = all_void ^ 0b11111, .tag = .mp_part_content_type }
    else if (std.mem.eql(u8, name, "sa_std_multipart_part_header"))
        .{ .voids = all_void ^ 0b1111111, .tag = .mp_part_header }
    else if (std.mem.eql(u8, name, "sa_std_multipart_part_body"))
        .{ .voids = all_void ^ 0b1111, .tag = .mp_part_body }
    else if (std.mem.eql(u8, name, "sa_std_multipart_builder_new"))
        .{ .voids = all_void ^ 0b1, .tag = .mp_builder_new }
    else if (std.mem.eql(u8, name, "sa_std_multipart_builder_free"))
        .{ .voids = all_void ^ 0b1, .tag = .mp_builder_free }
    else if (std.mem.eql(u8, name, "sa_std_multipart_builder_add_field"))
        .{ .voids = all_void ^ 0b11111, .tag = .mp_builder_add_field }
    else if (std.mem.eql(u8, name, "sa_std_multipart_builder_add_file"))
        .{ .voids = all_void ^ 0b111111111, .tag = .mp_builder_add_file }
    else if (std.mem.eql(u8, name, "sa_std_multipart_builder_boundary"))
        .{ .voids = all_void ^ 0b1111, .tag = .mp_builder_boundary }
    else if (std.mem.eql(u8, name, "sa_std_multipart_builder_content_type"))
        .{ .voids = all_void ^ 0b1111, .tag = .mp_builder_content_type }
    else if (std.mem.eql(u8, name, "sa_std_multipart_builder_finish"))
        .{ .voids = all_void ^ 0b11, .tag = .mp_builder_finish }
    else if (std.mem.eql(u8, name, "sa_std_multipart_buffer_data"))
        .{ .voids = all_void ^ 0b1, .tag = .nb_buf_data }
    else if (std.mem.eql(u8, name, "sa_std_multipart_buffer_len"))
        .{ .voids = all_void ^ 0b1, .tag = .nb_buf_len }
    else if (std.mem.eql(u8, name, "sa_std_multipart_buffer_free"))
        .{ .voids = all_void ^ 0b1, .tag = .nb_buf_free }
    else if (std.mem.eql(u8, name, "sa_std_ssh_supported"))
        .{ .voids = all_void ^ 0b1, .tag = .ssh_supported }
    else if (std.mem.eql(u8, name, "sa_std_ssh_buffer_data"))
        .{ .voids = all_void ^ 0b1, .tag = .ssh_buf_data }
    else if (std.mem.eql(u8, name, "sa_std_ssh_buffer_len"))
        .{ .voids = all_void ^ 0b1, .tag = .ssh_buf_len }
    else if (std.mem.eql(u8, name, "sa_std_ssh_buffer_free"))
        .{ .voids = all_void ^ 0b1, .tag = .ssh_buf_free }
    else if (std.mem.eql(u8, name, "sa_std_ssh_client_connect"))
        .{ .voids = all_void ^ 0b1111, .tag = .net_unsupported8 }
    else if (std.mem.eql(u8, name, "sa_std_ssh_hostkey_fingerprint"))
        .{ .voids = all_void ^ 0b1111, .tag = .net_unsupported8 }
    else if (std.mem.eql(u8, name, "sa_std_ssh_auth_password"))
        .{ .voids = all_void ^ 0b11111, .tag = .net_unsupported8 }
    else if (std.mem.eql(u8, name, "sa_std_ssh_auth_keyfile"))
        .{ .voids = all_void ^ 0b111111111, .tag = .net_unsupported8 }
    else if (std.mem.eql(u8, name, "sa_std_ssh_exec"))
        .{ .voids = all_void ^ 0b111111, .tag = .net_unsupported8 }
    else if (std.mem.eql(u8, name, "sa_std_ssh_sftp_read"))
        .{ .voids = all_void ^ 0b1111, .tag = .net_unsupported8 }
    else if (std.mem.eql(u8, name, "sa_std_ssh_sftp_write"))
        .{ .voids = all_void ^ 0b11111, .tag = .net_unsupported8 }
    else if (std.mem.eql(u8, name, "sa_std_ssh_sftp_stat"))
        .{ .voids = all_void ^ 0b11111, .tag = .net_unsupported8 }
    else if (std.mem.eql(u8, name, "sa_std_ssh_session_close"))
        .{ .voids = all_void ^ 0b1, .tag = .net_unsupported8 }
    else if (std.mem.eql(u8, name, "sa_std_ssh_server_listen"))
        .{ .voids = all_void ^ 0b111111, .tag = .net_unsupported8 }
    else if (std.mem.eql(u8, name, "sa_std_ssh_server_bind_close"))
        .{ .voids = all_void ^ 0b1, .tag = .net_unsupported8 }
    else if (std.mem.eql(u8, name, "sa_std_ssh_server_accept"))
        .{ .voids = all_void ^ 0b11, .tag = .net_unsupported8 }
    else if (std.mem.eql(u8, name, "sa_std_ssh_server_auth_next"))
        .{ .voids = all_void ^ 0b11111, .tag = .net_unsupported8 }
    else if (std.mem.eql(u8, name, "sa_std_ssh_server_auth_accept"))
        .{ .voids = all_void ^ 0b1, .tag = .net_unsupported8 }
    else if (std.mem.eql(u8, name, "sa_std_ssh_server_auth_deny"))
        .{ .voids = all_void ^ 0b1, .tag = .net_unsupported8 }
    else if (std.mem.eql(u8, name, "sa_std_ssh_server_channel_accept"))
        .{ .voids = all_void ^ 0b11, .tag = .net_unsupported8 }
    else if (std.mem.eql(u8, name, "sa_std_ssh_server_channel_exec"))
        .{ .voids = all_void ^ 0b111, .tag = .net_unsupported8 }
    else if (std.mem.eql(u8, name, "sa_std_ssh_channel_write"))
        .{ .voids = all_void ^ 0b11111, .tag = .net_unsupported8 }
    else if (std.mem.eql(u8, name, "sa_std_ssh_channel_read"))
        .{ .voids = all_void ^ 0b11111, .tag = .net_unsupported8 }
    else if (std.mem.eql(u8, name, "sa_std_ssh_channel_send_exit"))
        .{ .voids = all_void ^ 0b11, .tag = .net_unsupported8 }
    else if (std.mem.eql(u8, name, "sa_std_ssh_channel_close"))
        .{ .voids = all_void ^ 0b1, .tag = .net_unsupported8 }
    else if (std.mem.eql(u8, name, "sa_std_ssh_server_session_close"))
        .{ .voids = all_void ^ 0b1, .tag = .net_unsupported8 }
    else if (std.mem.eql(u8, name, "sa_std_tls_client_config_new"))
        .{ .voids = all_void ^ 0b1, .tag = .tlscfg_new }
    else if (std.mem.eql(u8, name, "sa_std_tls_client_config_free"))
        .{ .voids = all_void ^ 0b1, .tag = .tlscfg_free }
    else if (std.mem.eql(u8, name, "sa_std_tls_client_config_set_server_name"))
        .{ .voids = all_void ^ 0b111, .tag = .tlscfg_set_server_name }
    else if (std.mem.eql(u8, name, "sa_std_tls_client_config_add_ca_file"))
        .{ .voids = all_void ^ 0b111, .tag = .tlscfg_add_ca_file }
    else if (std.mem.eql(u8, name, "sa_std_tls_client_config_add_ca_memory"))
        .{ .voids = all_void ^ 0b111, .tag = .tlscfg_add_ca_memory }
    else if (std.mem.eql(u8, name, "sa_std_tls_client_config_set_insecure_no_verification"))
        .{ .voids = all_void ^ 0b11, .tag = .tlscfg_set_insecure }
    else if (std.mem.eql(u8, name, "sa_std_tls_client_config_set_verify_self_signed"))
        .{ .voids = all_void ^ 0b11, .tag = .tlscfg_set_verify_self_signed }
    else if (std.mem.eql(u8, name, "sa_std_tls_client_peer_cert_json"))
        .{ .voids = all_void ^ 0b11, .tag = .tls_peer_cert_json }
    else if (std.mem.eql(u8, name, "sa_std_tls_shaped_supported"))
        .{ .voids = all_void ^ 0b1, .tag = .tls_shaped_supported }
    else if (std.mem.eql(u8, name, "sa_std_tls_shaped_connect"))
        .{ .voids = all_void ^ 0b111111, .tag = .tls_shaped_connect }
    else if (std.mem.eql(u8, name, "sa_std_tls_client_buffer_data"))
        .{ .voids = all_void ^ 0b1, .tag = .tls_cbuf_data }
    else if (std.mem.eql(u8, name, "sa_std_tls_client_buffer_len"))
        .{ .voids = all_void ^ 0b1, .tag = .tls_cbuf_len }
    else if (std.mem.eql(u8, name, "sa_std_tls_client_buffer_free"))
        .{ .voids = all_void ^ 0b1, .tag = .tls_cbuf_free }
    else if (std.mem.eql(u8, name, "sa_std_net_addr_format"))
        .{ .voids = all_void ^ 0b1111, .tag = .na_format }
    else if (std.mem.eql(u8, name, "sa_std_net_socket_getsockopt"))
        .{ .voids = all_void ^ 0b111111, .tag = .sk_get }
    else if (std.mem.eql(u8, name, "sa_std_net_socket_getsockopt_int"))
        .{ .voids = all_void ^ 0b1111, .tag = .sk_get_int }
    else if (std.mem.eql(u8, name, "sa_std_net_socket_setsockopt"))
        .{ .voids = all_void ^ 0b11111, .tag = .sk_set }
    else if (std.mem.eql(u8, name, "sa_std_net_socket_setsockopt_int"))
        .{ .voids = all_void ^ 0b1111, .tag = .sk_set_int }
    else if (std.mem.eql(u8, name, "sa_std_net_to_socket_addr_first"))
        .{ .voids = all_void ^ 0b1111, .tag = .na_to_first }
    else if (std.mem.eql(u8, name, "sa_std_net_udp_bind"))
        .{ .voids = all_void ^ 0b1111, .tag = .udp_bind_h }
    else if (std.mem.eql(u8, name, "sa_std_net_udp_broadcast"))
        .{ .voids = all_void ^ 0b11, .tag = .udp_broadcast_h }
    else if (std.mem.eql(u8, name, "sa_std_net_udp_connect_addr"))
        .{ .voids = all_void ^ 0b11, .tag = .udp_connect_addr_h }
    else if (std.mem.eql(u8, name, "sa_std_net_udp_local_addr"))
        .{ .voids = all_void ^ 0b11, .tag = .udp_local_addr_h }
    else if (std.mem.eql(u8, name, "sa_std_net_udp_recv_msg"))
        .{ .voids = all_void ^ 0b111111111, .tag = .udp_recv_msg_h }
    else if (std.mem.eql(u8, name, "sa_std_net_udp_recv_multi"))
        .{ .voids = all_void ^ 0b11111111, .tag = .udp_recv_multi_h }
    else if (std.mem.eql(u8, name, "sa_std_net_udp_send"))
        .{ .voids = all_void ^ 0b1111, .tag = .udp_send_h }
    else if (std.mem.eql(u8, name, "sa_std_net_udp_set_read_timeout"))
        .{ .voids = all_void ^ 0b11, .tag = .udp_set_read_timeout_h }
    else if (std.mem.eql(u8, name, "sa_std_net_udp_ttl"))
        .{ .voids = all_void ^ 0b11, .tag = .udp_ttl_h }
    else if (std.mem.eql(u8, name, "sa_std_net_unix_datagram_pair"))
        .{ .voids = all_void ^ 0b11, .tag = .unix_pair_h }
    else if (std.mem.eql(u8, name, "sa_std_net_unix_datagram_peer_cred"))
        .{ .voids = all_void ^ 0b1111, .tag = .unix_peer_cred_h }
    else if (std.mem.eql(u8, name, "sa_std_net_unix_datagram_unbound"))
        .{ .voids = all_void ^ 0b1, .tag = .unix_unbound_h }
    else if (std.mem.eql(u8, name, "sa_std_process_id"))
        .{ .voids = all_void, .tag = .proc_id }
    else if (std.mem.eql(u8, name, "sa_std_process_user_id"))
        .{ .voids = all_void, .tag = .proc_user_id }
    else if (std.mem.eql(u8, name, "sa_http_client_new"))
        .{ .voids = all_void ^ 0b11, .tag = .http_client_new }
    else if (std.mem.eql(u8, name, "sa_http_client_req_new"))
        .{ .voids = all_void ^ 0b11101, .tag = .http_client_req_new }
    else if (std.mem.eql(u8, name, "sa_http_client_req_add_header"))
        .{ .voids = all_void ^ 0b11111, .tag = .http_client_req_add_header }
    else if (std.mem.eql(u8, name, "sa_http_client_req_set_body"))
        .{ .voids = all_void ^ 0b111, .tag = .http_client_req_set_body }
    else if (std.mem.eql(u8, name, "sa_http_client_req_send"))
        .{ .voids = all_void ^ 0b11, .tag = .http_client_req_send }
    else if (std.mem.eql(u8, name, "sa_http_client_resp_status"))
        .{ .voids = all_void ^ 0b1, .tag = .http_client_resp_status }
    else if (std.mem.eql(u8, name, "sa_http_client_resp_body_reader"))
        .{ .voids = all_void ^ 0b11, .tag = .http_client_resp_body_reader }
    else if (std.mem.eql(u8, name, "sa_http_client_resp_read_chunk"))
        .{ .voids = all_void ^ 0b1111, .tag = .http_client_resp_read_chunk }
    else if (std.mem.eql(u8, name, "sa_http_client_resp_free"))
        .{ .voids = all_void ^ 0b1, .tag = .http_client_resp_free }
    else if (std.mem.eql(u8, name, "sa_http_client_body_reader_free"))
        .{ .voids = all_void ^ 0b1, .tag = .http_client_body_reader_free }
    else if (std.mem.eql(u8, name, "sa_http_client_req_free"))
        .{ .voids = all_void ^ 0b1, .tag = .http_client_req_free }
    else if (std.mem.eql(u8, name, "sa_http_client_free"))
        .{ .voids = all_void ^ 0b1, .tag = .http_client_free }
    else if (std.mem.eql(u8, name, "sa_http_client_req_new_joined"))
        .{ .voids = all_void ^ 0b11111111, .tag = .hc_req_new_joined }
    else if (std.mem.eql(u8, name, "sa_http_client_req_add_openai_auth"))
        .{ .voids = all_void ^ 0b111, .tag = .hc_req_openai_auth }
    else if (std.mem.eql(u8, name, "sa_http_client_req_send_async"))
        .{ .voids = all_void ^ 0b11, .tag = .hc_send_async }
    else if (std.mem.eql(u8, name, "sa_http_client_async_poll"))
        .{ .voids = all_void ^ 0b11, .tag = .hc_op_poll }
    else if (std.mem.eql(u8, name, "sa_http_client_async_take_response"))
        .{ .voids = all_void ^ 0b11, .tag = .hc_op_take }
    else if (std.mem.eql(u8, name, "sa_http_client_async_free"))
        .{ .voids = all_void ^ 0b1, .tag = .hc_op_free }
    else if (std.mem.eql(u8, name, "sa_http_client_resp_get_header"))
        .{ .voids = all_void ^ 0b11111, .tag = .hc_resp_get_header }
    else if (std.mem.eql(u8, name, "sa_http_client_resp_body_slice"))
        .{ .voids = all_void ^ 0b111, .tag = .hc_resp_body_slice }
    else if (std.mem.eql(u8, name, "sa_http_client_resp_body_ptr"))
        .{ .voids = all_void ^ 0b1, .tag = .hc_resp_body_ptr }
    else if (std.mem.eql(u8, name, "sa_http_client_resp_body_len"))
        .{ .voids = all_void ^ 0b1, .tag = .hc_resp_body_len }
    else if (std.mem.eql(u8, name, "sa_http_client_websocket_connect"))
        .{ .voids = all_void ^ 0b1111, .tag = .hc_ws_connect }
    else if (std.mem.eql(u8, name, "sa_http_client_new_v2"))
        .{ .voids = all_void ^ 0b1111, .tag = .hc2_client_new }
    else if (std.mem.eql(u8, name, "sa_http_client_req_new_v2"))
        .{ .voids = all_void ^ 0b11111, .tag = .hc2_req_new }
    else if (std.mem.eql(u8, name, "sa_http_client_req_add_header_v2"))
        .{ .voids = all_void ^ 0b11111, .tag = .hc2_add_header }
    else if (std.mem.eql(u8, name, "sa_http_client_req_set_body_v2"))
        .{ .voids = all_void ^ 0b111, .tag = .hc2_set_body }
    else if (std.mem.eql(u8, name, "sa_http_client_req_set_timeout_v2"))
        .{ .voids = all_void ^ 0b11, .tag = .hc2_set_timeout }
    else if (std.mem.eql(u8, name, "sa_http_client_req_set_max_response_bytes_v2"))
        .{ .voids = all_void ^ 0b11, .tag = .hc2_set_max }
    else if (std.mem.eql(u8, name, "sa_http_client_req_send_v2"))
        .{ .voids = all_void ^ 0b11, .tag = .hc2_send }
    else if (std.mem.eql(u8, name, "sa_http_client_req_send_async_v2"))
        .{ .voids = all_void ^ 0b11, .tag = .hc2_send_async }
    else if (std.mem.eql(u8, name, "sa_http_client_async_poll_v2"))
        .{ .voids = all_void ^ 0b111, .tag = .hc2_poll }
    else if (std.mem.eql(u8, name, "sa_http_client_async_take_response_v2"))
        .{ .voids = all_void ^ 0b11, .tag = .hc2_take }
    else if (std.mem.eql(u8, name, "sa_http_client_async_cancel_v2"))
        .{ .voids = all_void ^ 0b1, .tag = .hc2_cancel }
    else if (std.mem.eql(u8, name, "sa_http_client_async_free_v2"))
        .{ .voids = all_void ^ 0b1, .tag = .hc2_free_obj }
    else if (std.mem.eql(u8, name, "sa_http_client_websocket_connect_v2"))
        .{ .voids = all_void ^ 0b11111, .tag = .hc2_ws_connect4 }
    else if (std.mem.eql(u8, name, "sa_http_client_websocket_connect_unix_v2"))
        .{ .voids = all_void ^ 0b1111111, .tag = .hc2_ws_connect6 }
    else if (std.mem.eql(u8, name, "sa_http_client_req_websocket_connect_v2"))
        .{ .voids = all_void ^ 0b111, .tag = .hc2_ws_connect2 }
    else if (std.mem.eql(u8, name, "sa_http_client_req_websocket_connect_unix_v2"))
        .{ .voids = all_void ^ 0b11111, .tag = .hc2_ws_connect4 }
    else if (std.mem.eql(u8, name, "sa_http_client_sse_post"))
        .{ .voids = all_void ^ 0b1111111, .tag = .hc_sse_post }
    else if (std.mem.eql(u8, name, "sa_http_client_sse_read"))
        .{ .voids = all_void ^ 0b1111, .tag = .hc_sse_read }
    else if (std.mem.eql(u8, name, "sa_http_client_sse_poll"))
        .{ .voids = all_void ^ 0b11, .tag = .hc_sse_poll }
    else if (std.mem.eql(u8, name, "sa_http_client_sse_status"))
        .{ .voids = all_void ^ 0b1, .tag = .hc_sse_status }
    else if (std.mem.eql(u8, name, "sa_http_client_sse_free"))
        .{ .voids = all_void ^ 0b1, .tag = .hc_op_free }
    else if (std.mem.eql(u8, name, "sa_http_client_sse_turn"))
        .{ .voids = all_void ^ 0b11111111111, .tag = .hc_sse_turn }
    else if (std.mem.eql(u8, name, "sa_http_client_sse_turn_free"))
        .{ .voids = all_void ^ 0b11, .tag = .hc_sse_turn_free }
    else if (std.mem.eql(u8, name, "sa_http_server_req_get_method"))
        .{ .voids = all_void ^ 0b111, .tag = .hs_req_get_method }
    else if (std.mem.eql(u8, name, "sa_http_server_resp_new"))
        .{ .voids = all_void ^ 0b111, .tag = .hs_resp_new }
    else if (std.mem.eql(u8, name, "sa_http_server_resp_set_content_type"))
        .{ .voids = all_void ^ 0b111, .tag = .hs_check0 }
    else if (std.mem.eql(u8, name, "sa_http_server_resp_send"))
        .{ .voids = all_void ^ 0b111, .tag = .hs_resp_send }
    else if (std.mem.eql(u8, name, "sa_http_server_resp_free"))
        .{ .voids = all_void ^ 0b1, .tag = .hs_free }
    else if (std.mem.eql(u8, name, "sa_http_server_websocket_upgrade"))
        .{ .voids = all_void ^ 0b11, .tag = .hs_ws_upgrade }
    else if (std.mem.eql(u8, name, "sa_http_server_websocket_read"))
        .{ .voids = all_void ^ 0b11111, .tag = .hc_ws_read }
    else if (std.mem.eql(u8, name, "sa_http_server_websocket_write"))
        .{ .voids = all_void ^ 0b1111, .tag = .hc_ws_write }
    else if (std.mem.eql(u8, name, "sa_http_server_websocket_free"))
        .{ .voids = all_void ^ 0b1, .tag = .hc_ws_free }
    else if (std.mem.eql(u8, name, "sa_http_server_serve_threaded"))
        .{ .voids = all_void ^ 0b11111, .tag = .hs_serve_threaded }
    else if (std.mem.eql(u8, name, "sa_http_server_stop_serving"))
        .{ .voids = all_void ^ 0b1, .tag = .hs_check0 }
    else if (std.mem.eql(u8, name, "sa_http_server_set_max_body_bytes"))
        .{ .voids = all_void ^ 0b11, .tag = .hs_check0 }
    else if (std.mem.eql(u8, name, "sa_http_server_new_v2"))
        .{ .voids = all_void ^ 0b1, .tag = .hs2_new }
    else if (std.mem.eql(u8, name, "sa_http_server_start_v2"))
        .{ .voids = all_void ^ 0b1111, .tag = .hs_check0 }
    else if (std.mem.eql(u8, name, "sa_http_server_accept_v2"))
        .{ .voids = all_void ^ 0b111, .tag = .hs2_accept }
    else if (std.mem.eql(u8, name, "sa_http_server_req_free_v2"))
        .{ .voids = all_void ^ 0b1, .tag = .hs_free }
    else if (std.mem.eql(u8, name, "sa_http_server_resp_new_v2"))
        .{ .voids = all_void ^ 0b111, .tag = .hs_resp_new }
    else if (std.mem.eql(u8, name, "sa_http_server_resp_add_header_v2"))
        .{ .voids = all_void ^ 0b11111, .tag = .hs_check0 }
    else if (std.mem.eql(u8, name, "sa_http_server_resp_send_v2"))
        .{ .voids = all_void ^ 0b1111, .tag = .hs_resp_send }
    else if (std.mem.eql(u8, name, "sa_http_server_resp_free_v2"))
        .{ .voids = all_void ^ 0b1, .tag = .hs_free }
    else if (std.mem.eql(u8, name, "sa_http_server_resp_stream_new_v2"))
        .{ .voids = all_void ^ 0b111, .tag = .hs_resp_new }
    else if (std.mem.eql(u8, name, "sa_http_server_resp_stream_add_header_v2"))
        .{ .voids = all_void ^ 0b11111, .tag = .hs_check0 }
    else if (std.mem.eql(u8, name, "sa_http_server_resp_stream_write_v2"))
        .{ .voids = all_void ^ 0b1111, .tag = .hs_resp_send }
    else if (std.mem.eql(u8, name, "sa_http_server_resp_stream_flush_v2"))
        .{ .voids = all_void ^ 0b1, .tag = .hs_check0 }
    else if (std.mem.eql(u8, name, "sa_http_server_resp_stream_end_v2"))
        .{ .voids = all_void ^ 0b11, .tag = .hs_check0 }
    else if (std.mem.eql(u8, name, "sa_http_server_resp_stream_free_v2"))
        .{ .voids = all_void ^ 0b1, .tag = .hs_free }
    else if (std.mem.eql(u8, name, "sa_http_server_free_v2"))
        .{ .voids = all_void ^ 0b1, .tag = .hs_free }
    else if (std.mem.eql(u8, name, "sa_http_server_websocket_upgrade_v2"))
        .{ .voids = all_void ^ 0b11, .tag = .hs_ws_upgrade }
    else if (std.mem.eql(u8, name, "sa_http_server_websocket_poll_v2"))
        .{ .voids = all_void ^ 0b1111, .tag = .hs2_ws_poll }
    else if (std.mem.eql(u8, name, "sa_http_server_websocket_read_v2"))
        .{ .voids = all_void ^ 0b11111, .tag = .hs2_ws_read }
    else if (std.mem.eql(u8, name, "sa_http_server_websocket_write_v2"))
        .{ .voids = all_void ^ 0b11111, .tag = .hs2_ws_write }
    else if (std.mem.eql(u8, name, "sa_http_server_websocket_close_v2"))
        .{ .voids = all_void ^ 0b1111, .tag = .hs2_ws_close }
    else if (std.mem.eql(u8, name, "sa_http_server_websocket_free_v2"))
        .{ .voids = all_void ^ 0b1, .tag = .hc_ws_free }
    else if (std.mem.eql(u8, name, "sa_http_server_new"))
        .{ .voids = all_void ^ 0b1, .tag = .http_server_new }
    else if (std.mem.eql(u8, name, "sa_http_server_start"))
        .{ .voids = all_void ^ 0b111, .tag = .http_server_start }
    else if (std.mem.eql(u8, name, "sa_http_server_accept"))
        .{ .voids = all_void ^ 0b11, .tag = .http_server_accept }
    else if (std.mem.eql(u8, name, "sa_http_server_req_get_path"))
        .{ .voids = all_void ^ 0b111, .tag = .http_server_req_get_path }
    else if (std.mem.eql(u8, name, "sa_http_server_req_get_header"))
        .{ .voids = all_void ^ 0b11111, .tag = .http_server_req_get_header }
    else if (std.mem.eql(u8, name, "sa_http_server_req_get_body"))
        .{ .voids = all_void ^ 0b111, .tag = .http_server_req_get_body }
    else if (std.mem.eql(u8, name, "sa_http_server_resp_stream_new"))
        .{ .voids = all_void ^ 0b101, .tag = .http_server_resp_stream_new }
    else if (std.mem.eql(u8, name, "sa_http_server_resp_stream_write"))
        .{ .voids = all_void ^ 0b111, .tag = .http_server_resp_stream_write }
    else if (std.mem.eql(u8, name, "sa_http_server_resp_stream_flush"))
        .{ .voids = all_void ^ 0b1, .tag = .http_server_resp_stream_flush }
    else if (std.mem.eql(u8, name, "sa_http_server_resp_stream_end"))
        .{ .voids = all_void ^ 0b1, .tag = .http_server_resp_stream_end }
    else if (std.mem.eql(u8, name, "sa_http_server_resp_stream_free"))
        .{ .voids = all_void ^ 0b1, .tag = .http_server_resp_stream_free }
    else if (std.mem.eql(u8, name, "sa_http_server_req_free"))
        .{ .voids = all_void ^ 0b1, .tag = .http_server_req_free }
    else if (std.mem.eql(u8, name, "sa_http_server_free"))
        .{ .voids = all_void ^ 0b1, .tag = .http_server_free }
    else if (std.mem.eql(u8, name, "sa_modstate_get_u64"))
        .{ .voids = all_void ^ 0b1, .tag = .modstate_get_u64 }
    else if (std.mem.eql(u8, name, "sa_modstate_set_u64"))
        .{ .voids = all_void ^ 0b11, .tag = .modstate_set_u64 }
    else
        null;
}
