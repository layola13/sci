#include "sa_std.h"

_Static_assert(
    _Generic(&sa_io_read_line, int32_t (*)(uint64_t, uint64_t, uint64_t *): 1, default: 0),
    "sa_io_read_line signature changed"
);
_Static_assert(
    _Generic(&sa_io_buffer_data, uint8_t *(*)(const SaIoBuffer *): 1, default: 0),
    "sa_io_buffer_data signature changed"
);
_Static_assert(
    _Generic(&sa_io_buffer_len, uint64_t (*)(const SaIoBuffer *): 1, default: 0),
    "sa_io_buffer_len signature changed"
);
_Static_assert(
    _Generic(&sa_io_buffer_free, int32_t (*)(SaIoBuffer *): 1, default: 0),
    "sa_io_buffer_free signature changed"
);
_Static_assert(
    _Generic(&sa_event_loop_create, int32_t (*)(void **): 1, default: 0),
    "sa_event_loop_create signature changed"
);
_Static_assert(
    _Generic(&sa_event_loop_submit, int32_t (*)(void *, const SaEvent *): 1, default: 0),
    "sa_event_loop_submit signature changed"
);
_Static_assert(
    _Generic(&sa_event_loop_wait, int32_t (*)(void *, SaEvent *, uint32_t, int32_t): 1, default: 0),
    "sa_event_loop_wait signature changed"
);
_Static_assert(
    _Generic(&sa_event_loop_close, int32_t (*)(void *): 1, default: 0),
    "sa_event_loop_close signature changed"
);
_Static_assert(sizeof(SaNetxTicket) == 24, "SaNetxTicket layout size changed");
_Static_assert(
    _Generic(&sa_netx_init, int32_t (*)(uint64_t, uint32_t): 1, default: 0),
    "sa_netx_init signature changed"
);
_Static_assert(
    _Generic(&sa_netx_listen, int32_t (*)(const uint8_t *, uint64_t, uint16_t): 1, default: 0),
    "sa_netx_listen signature changed"
);
_Static_assert(
    _Generic(&sa_netx_recv_ticket, int32_t (*)(uint32_t, SaNetxTicket *): 1, default: 0),
    "sa_netx_recv_ticket signature changed"
);
_Static_assert(
    _Generic(&sa_netx_push_outbound, int32_t (*)(uint32_t, uint32_t, const uint8_t *, uint32_t): 1, default: 0),
    "sa_netx_push_outbound signature changed"
);
_Static_assert(
    _Generic(&sa_netx_broadcast, int32_t (*)(uint32_t, const uint32_t *, uint32_t, const uint8_t *, uint32_t): 1, default: 0),
    "sa_netx_broadcast signature changed"
);
_Static_assert(
    _Generic(&sa_netx_close_slot, int32_t (*)(uint32_t): 1, default: 0),
    "sa_netx_close_slot signature changed"
);
_Static_assert(
    _Generic(&sa_netx_shutdown, int32_t (*)(void): 1, default: 0),
    "sa_netx_shutdown signature changed"
);
_Static_assert(
    _Generic(&sa_std_ws_accept_key, int32_t (*)(const uint8_t *, uint64_t, uint8_t *, uint64_t, uint64_t *): 1, default: 0),
    "sa_std_ws_accept_key signature changed"
);
_Static_assert(
    _Generic(&sa_std_ws_frame_parse, int32_t (*)(const uint8_t *, uint64_t, uint8_t *, uint8_t *, uint8_t *, uint64_t *, uint64_t *, uint64_t *, uint8_t *): 1, default: 0),
    "sa_std_ws_frame_parse signature changed"
);
_Static_assert(
    _Generic(&sa_std_ws_unmask, int32_t (*)(uint8_t *, uint64_t, const uint8_t *): 1, default: 0),
    "sa_std_ws_unmask signature changed"
);
_Static_assert(
    _Generic(&sa_std_ws_frame_build, int32_t (*)(uint32_t, uint32_t, const uint8_t *, uint64_t, const uint8_t *, uint8_t *, uint64_t, uint64_t *): 1, default: 0),
    "sa_std_ws_frame_build signature changed"
);
_Static_assert(
    _Generic(&sa_std_ws_frame_build_unmasked, int32_t (*)(uint32_t, uint32_t, const uint8_t *, uint64_t, uint8_t *, uint64_t, uint64_t *): 1, default: 0),
    "sa_std_ws_frame_build_unmasked signature changed"
);
_Static_assert(
    _Generic(&sa_std_url_parse, int32_t (*)(const uint8_t *, uint64_t, uint8_t *, uint64_t, uint64_t *, uint8_t *, uint64_t, uint64_t *, uint8_t *, uint64_t, uint64_t *, uint32_t *): 1, default: 0),
    "sa_std_url_parse signature changed"
);

static int check_network_declarations(uint64_t handle) {
    const sa_std_fallible_i32 free_result = sa_net_addr_free(handle);
    return free_result.status +
        sa_std_net_tcp_stream_set_keepalive(handle, 1) +
        sa_std_net_tcp_stream_set_keepalive_params(handle, 60, 10, 5);
}

int main(void) {
    return check_network_declarations(0);
}
