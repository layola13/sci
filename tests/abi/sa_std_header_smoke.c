#include "sa_std.h"

static int check_network_declarations(uint64_t handle) {
    const sa_std_fallible_i32 free_result = sa_net_addr_free(handle);
    return free_result.status +
        sa_std_net_tcp_stream_set_keepalive(handle, 1) +
        sa_std_net_tcp_stream_set_keepalive_params(handle, 60, 10, 5);
}

int main(void) {
    return check_network_declarations(0);
}
