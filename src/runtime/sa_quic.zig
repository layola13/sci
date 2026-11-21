// QUIC + HTTP/3 runtime for the sci/sa_std platform layer.
//
// Real protocol machines, dlopen-bound (the pattern used by sa_http2.zig,
// sa_tls_server.zig, sa_tls_shaped.zig):
//   * QUIC transport: libngtcp2 (callbacks + versioned entry points,
//     ABI verified against ngtcp2 0.12 headers: struct sizes/offsets
//     measured with a C offsetof probe, not guessed).
//   * TLS 1.3 for QUIC: the ngtcp2 GnuTLS crypto backend
//     (libngtcp2_crypto_gnutls + libgnutls). This is the backend Ubuntu
//     ships; it needs no OpenSSL QUIC API (system OpenSSL 3.0 has none).
//   * HTTP/3: libnghttp3, glued to the QUIC streams below.
//
// Capability gating stays honest: sa_std_quic_supported reports 1 only
// when every required library AND symbol resolves at runtime. Hosts
// without the stack get UNSUPPORTED from the constructors, never a
// fabricated session.
//
// Driving model: connections are non-blocking and caller-pumped.
// sa_std_quic_conn_poll / sa_std_quic_server_poll drain datagrams, run
// ngtcp2 timers, and flush pending packets. One pump loop per endpoint
// is enough for a full handshake + HTTP/3 exchange (the loopback tests
// drive client and server from a single thread).

const std = @import("std");
const builtin = @import("builtin");
const sio = @import("sio");

const _q01 = @import("sa_quic/q01.zig");
const _q02 = @import("sa_quic/q02.zig");
const _q03 = @import("sa_quic/q03.zig");
const _q04 = @import("sa_quic/q04.zig");

pub const sa_std_quic_endpoint_create = @import("sa_quic/q02.zig").sa_std_quic_endpoint_create; pub const sa_std_quic_endpoint_destroy = @import("sa_quic/q02.zig").sa_std_quic_endpoint_destroy;
pub const sa_std_quic_client_connect = @import("sa_quic/q02.zig").sa_std_quic_client_connect; pub const sa_std_quic_server_listen = @import("sa_quic/q02.zig").sa_std_quic_server_listen;
pub const sa_std_quic_conn_close = @import("sa_quic/q02.zig").sa_std_quic_conn_close; pub const sa_std_quic_conn_handshake_completed = @import("sa_quic/q02.zig").sa_std_quic_conn_handshake_completed;
pub const sa_std_quic_server_poll = @import("sa_quic/q03.zig").sa_std_quic_server_poll; pub const sa_std_quic_server_accept = @import("sa_quic/q03.zig").sa_std_quic_server_accept;
pub const sa_std_quic_conn_poll = @import("sa_quic/q03.zig").sa_std_quic_conn_poll; pub const sa_std_quic_stream_open = @import("sa_quic/q03.zig").sa_std_quic_stream_open;
pub const sa_std_quic_stream_write = @import("sa_quic/q03.zig").sa_std_quic_stream_write; pub const sa_std_quic_stream_read = @import("sa_quic/q03.zig").sa_std_quic_stream_read;
pub const sa_std_http3_session_create = @import("sa_quic/q03.zig").sa_std_http3_session_create; pub const sa_std_http3_session_bind = @import("sa_quic/q03.zig").sa_std_http3_session_bind;
pub const sa_std_http3_session_destroy = @import("sa_quic/q03.zig").sa_std_http3_session_destroy; pub const sa_std_http3_submit_request = @import("sa_quic/q04.zig").sa_std_http3_submit_request;
pub const sa_std_http3_server_next_request = @import("sa_quic/q04.zig").sa_std_http3_server_next_request; pub const sa_std_http3_request_field = @import("sa_quic/q04.zig").sa_std_http3_request_field;
pub const sa_std_http3_submit_response = @import("sa_quic/q04.zig").sa_std_http3_submit_response; pub const sa_std_http3_response_status = @import("sa_quic/q04.zig").sa_std_http3_response_status;
pub const sa_std_http3_stream_read = @import("sa_quic/q04.zig").sa_std_http3_stream_read; pub const sa_std_quic_supported = @import("sa_quic/q04.zig").sa_std_quic_supported;
pub const sa_std_http3_supported = @import("sa_quic/q04.zig").sa_std_http3_supported; pub const sa_std_quic_buffer_data = @import("sa_quic/q04.zig").sa_std_quic_buffer_data;
pub const sa_std_quic_buffer_len = @import("sa_quic/q04.zig").sa_std_quic_buffer_len; pub const sa_std_quic_buffer_free = @import("sa_quic/q04.zig").sa_std_quic_buffer_free;
pub const sa_std_quic_capabilities_json = @import("sa_quic/q04.zig").sa_std_quic_capabilities_json; pub const sa_std_quic_constants_json = @import("sa_quic/q04.zig").sa_std_quic_constants_json;
pub const sa_std_http3_constants_json = @import("sa_quic/q04.zig").sa_std_http3_constants_json;
