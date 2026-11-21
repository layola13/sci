//! sa_std built-in HTTP/1.1 client (+ WebSocket client + SSE streaming).
//!
//! Migrated from the sa_plugin_http_client plugin (2026-10-24) under the
//! "all foundational cores live in sa_std" doctrine: the plugin keeps
//! only framework-level wrapping. The extern surface is unchanged
//! (sa_http_client_* / sa_http_websocket_*), so existing .sai callers
//! link against libsa_std.a with no plugin installed.
//!
//! Transports: std.http.Client for the request/response paths, a curl
//! subprocess for the SSE POST path (proxy/TLS edge cases), and raw
//! streams for the WebSocket client. Response compression is disabled
//! by asking upstreams for `Accept-Encoding: identity` (the plugin's
//! long-standing strategy: always-safe bodies over negotiated ones).

// --- core.zig ---
pub const WebSocketFrame = @import("sa_http_client/core.zig").WebSocketFrame;
pub const websocketAccept = @import("sa_http_client/core.zig").websocketAccept;
pub const buildWebSocketFrame = @import("sa_http_client/core.zig").buildWebSocketFrame;
pub const readWebSocketFrameAlloc = @import("sa_http_client/core.zig").readWebSocketFrameAlloc;
pub const dialHost = @import("sa_http_client/core.zig").dialHost;
pub const SaHttpClientHandle = @import("sa_http_client/core.zig").SaHttpClientHandle;
pub const SaHttpRequestHandle = @import("sa_http_client/core.zig").SaHttpRequestHandle;
pub const SaHttpResponseHandle = @import("sa_http_client/core.zig").SaHttpResponseHandle;
pub const SaHttpBodyReaderHandle = @import("sa_http_client/core.zig").SaHttpBodyReaderHandle;
pub const HttpMethod = @import("sa_http_client/core.zig").HttpMethod;
pub const HttpClientConfig = @import("sa_http_client/core.zig").HttpClientConfig;
pub const HttpRequestConfig = @import("sa_http_client/core.zig").HttpRequestConfig;
pub const HttpClient = @import("sa_http_client/core.zig").HttpClient;
pub const HttpRequest = @import("sa_http_client/core.zig").HttpRequest;
// --- response.zig ---
pub const HttpResponse = @import("sa_http_client/response.zig").HttpResponse;
pub const HttpBodyReader = @import("sa_http_client/response.zig").HttpBodyReader;
pub const HttpRequestAsyncOp = @import("sa_http_client/response.zig").HttpRequestAsyncOp;
const exec = @import("sa_http_client/exec.zig");
// --- exports_v1.zig ---
pub const sa_http_client_new = @import("sa_http_client/exports_v1.zig").sa_http_client_new;
pub const sa_http_client_new_with_profile = @import("sa_http_client/exports_v1.zig").sa_http_client_new_with_profile;
pub const sa_http_client_new_with_proxy = @import("sa_http_client/exports_v1.zig").sa_http_client_new_with_proxy;
pub const sa_http_client_new_with_profile_proxy = @import("sa_http_client/exports_v1.zig").sa_http_client_new_with_profile_proxy;
pub const sa_http_client_req_new = @import("sa_http_client/exports_v1.zig").sa_http_client_req_new;
pub const sa_http_client_req_new_joined = @import("sa_http_client/exports_v1.zig").sa_http_client_req_new_joined;
pub const sa_http_client_req_add_header = @import("sa_http_client/exports_v1.zig").sa_http_client_req_add_header;
pub const sa_http_client_req_add_openai_auth = @import("sa_http_client/exports_v1.zig").sa_http_client_req_add_openai_auth;
pub const sa_http_client_req_set_body = @import("sa_http_client/exports_v1.zig").sa_http_client_req_set_body;
pub const sa_http_client_req_send = @import("sa_http_client/exports_v1.zig").sa_http_client_req_send;
pub const sa_http_client_req_send_async = @import("sa_http_client/exports_v1.zig").sa_http_client_req_send_async;
pub const sa_http_client_async_poll = @import("sa_http_client/exports_v1.zig").sa_http_client_async_poll;
pub const sa_http_client_async_take_response = @import("sa_http_client/exports_v1.zig").sa_http_client_async_take_response;
pub const sa_http_client_async_free = @import("sa_http_client/exports_v1.zig").sa_http_client_async_free;
pub const sa_http_client_resp_status = @import("sa_http_client/exports_v1.zig").sa_http_client_resp_status;
pub const sa_http_client_resp_get_header = @import("sa_http_client/exports_v1.zig").sa_http_client_resp_get_header;
pub const sa_http_client_resp_body_slice = @import("sa_http_client/exports_v1.zig").sa_http_client_resp_body_slice;
pub const sa_http_fetch_bytes = @import("sa_http_client/exports_v1.zig").sa_http_fetch_bytes;
pub const sa_http_client_resp_body_ptr = @import("sa_http_client/exports_v1.zig").sa_http_client_resp_body_ptr;
pub const sa_http_client_resp_body_len = @import("sa_http_client/exports_v1.zig").sa_http_client_resp_body_len;
pub const sa_http_client_resp_body_reader = @import("sa_http_client/exports_v1.zig").sa_http_client_resp_body_reader;
pub const sa_http_client_resp_read_chunk = @import("sa_http_client/exports_v1.zig").sa_http_client_resp_read_chunk;
pub const sa_http_client_resp_free = @import("sa_http_client/exports_v1.zig").sa_http_client_resp_free;
pub const sa_http_client_body_reader_free = @import("sa_http_client/exports_v1.zig").sa_http_client_body_reader_free;
pub const sa_http_client_free = @import("sa_http_client/exports_v1.zig").sa_http_client_free;
pub const sa_http_client_req_free = @import("sa_http_client/exports_v1.zig").sa_http_client_req_free;
// --- websocket.zig ---
pub const sa_http_websocket_read = @import("sa_http_client/websocket.zig").sa_http_websocket_read;
pub const sa_http_websocket_write = @import("sa_http_client/websocket.zig").sa_http_websocket_write;
pub const sa_http_websocket_free = @import("sa_http_client/websocket.zig").sa_http_websocket_free;
pub const sa_http_client_websocket_connect = @import("sa_http_client/websocket.zig").sa_http_client_websocket_connect;
// --- sse.zig ---
pub const sa_http_client_sse_post = @import("sa_http_client/sse.zig").sa_http_client_sse_post;
pub const sa_http_client_sse_read = @import("sa_http_client/sse.zig").sa_http_client_sse_read;
pub const sa_http_client_sse_poll = @import("sa_http_client/sse.zig").sa_http_client_sse_poll;
pub const sa_http_client_sse_status = @import("sa_http_client/sse.zig").sa_http_client_sse_status;
pub const sa_http_client_sse_free = @import("sa_http_client/sse.zig").sa_http_client_sse_free;
pub const sa_http_client_sse_turn = @import("sa_http_client/sse.zig").sa_http_client_sse_turn;
pub const sa_http_client_sse_turn_ex = @import("sa_http_client/sse.zig").sa_http_client_sse_turn_ex;
// --- sse_events.zig ---
pub const sa_http_client_sse_turn_free_all = @import("sa_http_client/sse_events.zig").sa_http_client_sse_turn_free_all;
pub const sa_http_client_sse_turn_free = @import("sa_http_client/sse_events.zig").sa_http_client_sse_turn_free;
// --- v2_core.zig ---
pub const max_v2_message_bytes = @import("sa_http_client/v2_core.zig").max_v2_message_bytes;
pub const default_v2_response_bytes = @import("sa_http_client/v2_core.zig").default_v2_response_bytes;
pub const NetworkStatus = @import("sa_http_client/v2_core.zig").NetworkStatus;
pub const PollEvent = @import("sa_http_client/v2_core.zig").PollEvent;
pub const sa_http_client_new_v2 = @import("sa_http_client/v2_core.zig").sa_http_client_new_v2;
pub const sa_http_client_req_new_v2 = @import("sa_http_client/v2_core.zig").sa_http_client_req_new_v2;
pub const sa_http_client_req_add_header_v2 = @import("sa_http_client/v2_core.zig").sa_http_client_req_add_header_v2;
pub const sa_http_client_req_set_body_v2 = @import("sa_http_client/v2_core.zig").sa_http_client_req_set_body_v2;
pub const sa_http_client_req_set_timeout_v2 = @import("sa_http_client/v2_core.zig").sa_http_client_req_set_timeout_v2;
pub const sa_http_client_req_set_max_response_bytes_v2 = @import("sa_http_client/v2_core.zig").sa_http_client_req_set_max_response_bytes_v2;
pub const sa_http_client_req_send_v2 = @import("sa_http_client/v2_core.zig").sa_http_client_req_send_v2;
// --- v2_websocket.zig ---
pub const sa_http_client_req_send_async_v2 = @import("sa_http_client/v2_websocket.zig").sa_http_client_req_send_async_v2;
pub const sa_http_client_async_poll_v2 = @import("sa_http_client/v2_websocket.zig").sa_http_client_async_poll_v2;
pub const sa_http_client_async_take_response_v2 = @import("sa_http_client/v2_websocket.zig").sa_http_client_async_take_response_v2;
pub const sa_http_client_async_cancel_v2 = @import("sa_http_client/v2_websocket.zig").sa_http_client_async_cancel_v2;
pub const sa_http_client_async_free_v2 = @import("sa_http_client/v2_websocket.zig").sa_http_client_async_free_v2;
pub const sa_http_client_websocket_connect_v2 = @import("sa_http_client/v2_websocket.zig").sa_http_client_websocket_connect_v2;
pub const sa_http_client_websocket_connect_unix_v2 = @import("sa_http_client/v2_websocket.zig").sa_http_client_websocket_connect_unix_v2;
pub const sa_http_client_req_websocket_connect_v2 = @import("sa_http_client/v2_websocket.zig").sa_http_client_req_websocket_connect_v2;
pub const sa_http_client_req_websocket_connect_unix_v2 = @import("sa_http_client/v2_websocket.zig").sa_http_client_req_websocket_connect_unix_v2;
// --- v2_frames.zig ---
pub const sa_http_websocket_poll_v2 = @import("sa_http_client/v2_frames.zig").sa_http_websocket_poll_v2;
pub const sa_http_websocket_read_v2 = @import("sa_http_client/v2_frames.zig").sa_http_websocket_read_v2;
pub const sa_http_websocket_write_v2 = @import("sa_http_client/v2_frames.zig").sa_http_websocket_write_v2;
pub const sa_http_websocket_close_v2 = @import("sa_http_client/v2_frames.zig").sa_http_websocket_close_v2;
pub const sa_http_websocket_free_v2 = @import("sa_http_client/v2_frames.zig").sa_http_websocket_free_v2;
const tests_server = @import("sa_http_client/tests_server.zig");
const tests_proxy = @import("sa_http_client/tests_proxy.zig");
