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

static int check_network_declarations(uint64_t handle) {
    const sa_std_fallible_i32 free_result = sa_net_addr_free(handle);
    return free_result.status +
        sa_std_net_tcp_stream_set_keepalive(handle, 1) +
        sa_std_net_tcp_stream_set_keepalive_params(handle, 60, 10, 5);
}

int main(void) {
    return check_network_declarations(0);
}
