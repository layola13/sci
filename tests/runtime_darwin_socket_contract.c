#include "sa_std.h"

#include <stdint.h>
#include <stdio.h>
#include <string.h>

#ifndef __APPLE__
#error "runtime_darwin_socket_contract.c must only be built for Darwin"
#endif

#define CONTRACT_TIMEOUT_NS 2000000000ull

#define CHECK(condition, code)                                                                        \
    do {                                                                                              \
        if (!(condition)) {                                                                           \
            fprintf(stderr, "runtime Darwin socket contract failed at line %d (code %d)\n",       \
                    __LINE__, (code));                                                                 \
            result = (code);                                                                           \
            goto cleanup;                                                                              \
        }                                                                                              \
    } while (0)

_Static_assert(sizeof(SaNetxTicket) == 24, "netx ticket ABI size changed");

static int write_all(uint64_t stream, const uint8_t *data, uint64_t len) {
    uint64_t offset = 0;
    while (offset < len) {
        uint64_t written = 0;
        if (sa_std_net_tcp_stream_write(stream, data + offset, len - offset, &written) !=
                SA_STD_OK ||
            written == 0) {
            return 0;
        }
        offset += written;
    }
    return 1;
}

static int read_exact(uint64_t stream, uint8_t *data, uint64_t len) {
    uint64_t offset = 0;
    while (offset < len) {
        uint64_t read_len = 0;
        if (sa_std_net_tcp_stream_read(stream, data + offset, len - offset, &read_len) !=
                SA_STD_OK ||
            read_len == 0) {
            return 0;
        }
        offset += read_len;
    }
    return 1;
}

static int timeout_matches(uint64_t actual) {
    const uint64_t tolerance = 100000000ull;
    return actual >= CONTRACT_TIMEOUT_NS - tolerance && actual <= CONTRACT_TIMEOUT_NS + tolerance;
}

static int unix_addr_matches_path(uint64_t addr, const char *path, uint64_t path_len) {
    const uint8_t *actual = sa_net_unix_addr_path_ptr(addr);
    return sa_net_unix_addr_kind(addr) == SA_NET_UNIX_ADDR_PATHNAME && actual != NULL &&
           sa_net_unix_addr_path_len(addr) == path_len &&
           memcmp(actual, path, (size_t)path_len) == 0;
}

int main(void) {
    static const uint8_t loopback[] = "127.0.0.1";
    static const uint8_t loopback_v6[] = "::1";
    static const uint8_t localhost[] = "localhost";
    static const uint8_t tcp_request[] = "darwin-tcp-request";
    static const uint8_t tcp_response[] = "darwin-tcp-response";
    static const uint8_t udp_request[] = "darwin-udp-request";
    static const uint8_t udp_response[] = "darwin-udp-response";
    static const uint8_t uds_request[] = "darwin-uds-request";
    char uds_path[96] = {0};
    uint8_t buffer[96] = {0};
    int uds_path_len = 0;
    int result = 0;
    int uds_path_created = 0;
    uint32_t tcp_port = 0;
    uint16_t udp_port_a = 0;
    uint16_t udp_port_b = 0;
    uint64_t dns_addr = 0;
    uint64_t tcp_listener = 0;
    uint64_t tcp_client = 0;
    uint64_t tcp_server = 0;
    uint64_t tcp_addr = 0;
    uint64_t udp_a = 0;
    uint64_t udp_b = 0;
    uint64_t udp_v6 = 0;
    uint64_t udp_addr_a = 0;
    uint64_t udp_addr_b = 0;
    uint64_t udp_recv_addr = 0;
    uint64_t uds_path_addr = 0;
    uint64_t uds_listener = 0;
    uint64_t uds_client = 0;
    uint64_t uds_server = 0;
    uint64_t uds_local_addr = 0;
    uint64_t uds_peer_addr = 0;
    uint64_t uds_accept_addr = 0;

    CHECK(sa_std_net_to_socket_addr_first(localhost, sizeof(localhost) - 1, 4242, &dns_addr) ==
              SA_STD_OK,
          101);
    CHECK(dns_addr != 0, 102);
    CHECK(sa_net_addr_host(dns_addr) != NULL && sa_net_addr_host_len(dns_addr) != 0, 103);
    CHECK(sa_net_addr_port(dns_addr) == 4242, 104);
    CHECK(sa_net_addr_family(dns_addr) == SA_NET_AF_INET ||
              sa_net_addr_family(dns_addr) == SA_NET_AF_INET6,
          105);
    CHECK(sa_net_addr_free(dns_addr).status == SA_STD_OK, 106);
    dns_addr = 0;

    CHECK(sa_std_net_tcp_listen(loopback, sizeof(loopback) - 1, 0, &tcp_listener, &tcp_port) ==
              SA_STD_OK,
          120);
    CHECK(tcp_listener != 0 && tcp_port != 0, 121);
    CHECK(sa_std_net_tcp_listener_local_addr(tcp_listener, &tcp_addr) == SA_STD_OK &&
              tcp_addr != 0,
          122);
    CHECK(sa_net_addr_family(tcp_addr) == SA_NET_AF_INET &&
              sa_net_addr_port(tcp_addr) == tcp_port,
          123);
    CHECK(sa_net_addr_free(tcp_addr).status == SA_STD_OK, 124);
    tcp_addr = 0;
    CHECK(sa_std_net_tcp_listener_set_ttl(tcp_listener, 47) == SA_STD_OK, 125);
    {
        uint32_t ttl = 0;
        int32_t socket_error = -1;
        CHECK(sa_std_net_tcp_listener_ttl(tcp_listener, &ttl) == SA_STD_OK && ttl == 47, 126);
        CHECK(sa_std_net_tcp_listener_take_error(tcp_listener, &socket_error) == SA_STD_OK &&
                  socket_error == 0,
              127);
    }
    CHECK(sa_std_net_tcp_connect(loopback, sizeof(loopback) - 1, tcp_port, &tcp_client) ==
              SA_STD_OK,
          128);
    CHECK(tcp_client != 0, 129);
    CHECK(sa_std_net_tcp_accept(tcp_listener, &tcp_server) == SA_STD_OK && tcp_server != 0, 130);
    CHECK(sa_std_net_tcp_stream_set_read_timeout(tcp_client, CONTRACT_TIMEOUT_NS) == SA_STD_OK,
          131);
    CHECK(sa_std_net_tcp_stream_set_write_timeout(tcp_client, CONTRACT_TIMEOUT_NS) == SA_STD_OK,
          132);
    CHECK(sa_std_net_tcp_stream_set_read_timeout(tcp_server, CONTRACT_TIMEOUT_NS) == SA_STD_OK,
          133);
    CHECK(sa_std_net_tcp_stream_set_write_timeout(tcp_server, CONTRACT_TIMEOUT_NS) == SA_STD_OK,
          134);
    {
        uint64_t timeout_ns = 0;
        int32_t enabled = 0;
        uint32_t ttl = 0;
        int32_t socket_error = -1;
        CHECK(sa_std_net_tcp_stream_read_timeout(tcp_client, &timeout_ns) == SA_STD_OK &&
                  timeout_matches(timeout_ns),
              135);
        timeout_ns = 0;
        CHECK(sa_std_net_tcp_stream_write_timeout(tcp_client, &timeout_ns) == SA_STD_OK &&
                  timeout_matches(timeout_ns),
              136);
        CHECK(sa_std_net_tcp_stream_set_nodelay(tcp_client, 1) == SA_STD_OK, 137);
        CHECK(sa_std_net_tcp_stream_nodelay(tcp_client, &enabled) == SA_STD_OK && enabled == 1,
              138);
        CHECK(sa_std_net_tcp_stream_set_ttl(tcp_client, 53) == SA_STD_OK, 139);
        CHECK(sa_std_net_tcp_stream_ttl(tcp_client, &ttl) == SA_STD_OK && ttl == 53, 140);
        CHECK(sa_std_net_tcp_stream_set_keepalive(tcp_client, 1) == SA_STD_OK, 141);
        CHECK(sa_std_net_tcp_stream_set_keepalive_params(tcp_client, 60, 10, 5) == SA_STD_OK,
              142);
        CHECK(sa_std_net_tcp_stream_take_error(tcp_client, &socket_error) == SA_STD_OK &&
                  socket_error == 0,
              143);
    }
    CHECK(sa_std_net_tcp_stream_peer_addr(tcp_client, &tcp_addr) == SA_STD_OK && tcp_addr != 0,
          144);
    CHECK(sa_net_addr_family(tcp_addr) == SA_NET_AF_INET &&
              sa_net_addr_port(tcp_addr) == tcp_port,
          145);
    CHECK(sa_net_addr_free(tcp_addr).status == SA_STD_OK, 146);
    tcp_addr = 0;
    CHECK(write_all(tcp_client, tcp_request, sizeof(tcp_request) - 1), 147);
    CHECK(read_exact(tcp_server, buffer, sizeof(tcp_request) - 1) &&
              memcmp(buffer, tcp_request, sizeof(tcp_request) - 1) == 0,
          148);
    memset(buffer, 0, sizeof(buffer));
    CHECK(write_all(tcp_server, tcp_response, sizeof(tcp_response) - 1), 149);
    CHECK(read_exact(tcp_client, buffer, sizeof(tcp_response) - 1) &&
              memcmp(buffer, tcp_response, sizeof(tcp_response) - 1) == 0,
          150);

    CHECK(sa_std_net_udp_bind(loopback, sizeof(loopback) - 1, 0, &udp_a) == SA_STD_OK &&
              udp_a != 0,
          180);
    CHECK(sa_std_net_udp_bind(loopback, sizeof(loopback) - 1, 0, &udp_b) == SA_STD_OK &&
              udp_b != 0,
          181);
    CHECK(sa_std_net_udp_local_addr(udp_a, &udp_addr_a) == SA_STD_OK && udp_addr_a != 0, 182);
    CHECK(sa_std_net_udp_local_addr(udp_b, &udp_addr_b) == SA_STD_OK && udp_addr_b != 0, 183);
    CHECK(sa_net_addr_family(udp_addr_a) == SA_NET_AF_INET &&
              sa_net_addr_family(udp_addr_b) == SA_NET_AF_INET,
          184);
    udp_port_a = (uint16_t)sa_net_addr_port(udp_addr_a);
    udp_port_b = (uint16_t)sa_net_addr_port(udp_addr_b);
    CHECK(udp_port_a != 0 && udp_port_b != 0, 185);
    CHECK(sa_std_net_udp_set_read_timeout(udp_a, CONTRACT_TIMEOUT_NS) == SA_STD_OK, 186);
    CHECK(sa_std_net_udp_set_write_timeout(udp_a, CONTRACT_TIMEOUT_NS) == SA_STD_OK, 187);
    CHECK(sa_std_net_udp_set_read_timeout(udp_b, CONTRACT_TIMEOUT_NS) == SA_STD_OK, 188);
    CHECK(sa_std_net_udp_set_write_timeout(udp_b, CONTRACT_TIMEOUT_NS) == SA_STD_OK, 189);
    {
        uint64_t timeout_ns = 0;
        int32_t enabled = 0;
        uint32_t ttl = 0;
        int32_t socket_error = -1;
        CHECK(sa_std_net_udp_read_timeout(udp_a, &timeout_ns) == SA_STD_OK &&
                  timeout_matches(timeout_ns),
              190);
        timeout_ns = 0;
        CHECK(sa_std_net_udp_write_timeout(udp_a, &timeout_ns) == SA_STD_OK &&
                  timeout_matches(timeout_ns),
              191);
        CHECK(sa_std_net_udp_set_broadcast(udp_a, 1) == SA_STD_OK, 192);
        CHECK(sa_std_net_udp_broadcast(udp_a, &enabled) == SA_STD_OK && enabled == 1, 193);
        CHECK(sa_std_net_udp_set_ttl(udp_a, 59) == SA_STD_OK, 194);
        CHECK(sa_std_net_udp_ttl(udp_a, &ttl) == SA_STD_OK && ttl == 59, 195);
        CHECK(sa_std_net_udp_set_ttl(udp_a, 0) == SA_STD_ERR_INVALID_ARGUMENT, 1941);
        CHECK(sa_std_net_udp_set_ttl(udp_a, 256) == SA_STD_ERR_INVALID_ARGUMENT, 1942);
        CHECK(sa_std_net_udp_set_multicast_loop_v4(udp_a, 1) == SA_STD_OK, 196);
        enabled = 0;
        CHECK(sa_std_net_udp_multicast_loop_v4(udp_a, &enabled) == SA_STD_OK && enabled == 1,
              197);
        CHECK(sa_std_net_udp_set_multicast_ttl_v4(udp_a, 7) == SA_STD_OK, 198);
        ttl = 0;
        CHECK(sa_std_net_udp_multicast_ttl_v4(udp_a, &ttl) == SA_STD_OK && ttl == 7, 199);
        CHECK(sa_std_net_udp_take_error(udp_a, &socket_error) == SA_STD_OK && socket_error == 0,
              200);
    }
    {
        uint64_t written = 0;
        uint64_t read_len = 0;
        CHECK(sa_std_net_udp_send_to(udp_a, udp_request, sizeof(udp_request) - 1, loopback,
                                     sizeof(loopback) - 1, udp_port_b, &written) == SA_STD_OK &&
                  written == sizeof(udp_request) - 1,
              201);
        memset(buffer, 0, sizeof(buffer));
        CHECK(sa_std_net_udp_recv_from(udp_b, buffer, sizeof(buffer), &read_len,
                                       &udp_recv_addr) == SA_STD_OK,
              202);
        CHECK(read_len == sizeof(udp_request) - 1 &&
                  memcmp(buffer, udp_request, sizeof(udp_request) - 1) == 0,
              203);
        CHECK(udp_recv_addr != 0 && sa_net_addr_family(udp_recv_addr) == SA_NET_AF_INET &&
                  sa_net_addr_port(udp_recv_addr) == udp_port_a,
              204);
        CHECK(sa_net_addr_free(udp_recv_addr).status == SA_STD_OK, 205);
        udp_recv_addr = 0;
    }
    CHECK(sa_std_net_udp_connect(udp_b, loopback, sizeof(loopback) - 1, udp_port_a) == SA_STD_OK,
          206);
    CHECK(sa_std_net_udp_peer_addr(udp_b, &udp_recv_addr) == SA_STD_OK && udp_recv_addr != 0,
          207);
    CHECK(sa_net_addr_family(udp_recv_addr) == SA_NET_AF_INET &&
              sa_net_addr_port(udp_recv_addr) == udp_port_a,
          208);
    CHECK(sa_net_addr_free(udp_recv_addr).status == SA_STD_OK, 209);
    udp_recv_addr = 0;
    {
        uint64_t written = 0;
        uint64_t read_len = 0;
        CHECK(sa_std_net_udp_send(udp_b, udp_response, sizeof(udp_response) - 1, &written) ==
                      SA_STD_OK &&
                  written == sizeof(udp_response) - 1,
              210);
        memset(buffer, 0, sizeof(buffer));
        CHECK(sa_std_net_udp_recv(udp_a, buffer, sizeof(buffer), &read_len) == SA_STD_OK, 211);
        CHECK(read_len == sizeof(udp_response) - 1 &&
                  memcmp(buffer, udp_response, sizeof(udp_response) - 1) == 0,
              212);
    }

    CHECK(sa_std_net_udp_bind(loopback_v6, sizeof(loopback_v6) - 1, 0, &udp_v6) == SA_STD_OK &&
              udp_v6 != 0,
          220);
    CHECK(sa_std_net_udp_set_ttl(udp_v6, 31) == SA_STD_OK, 221);
    {
        uint32_t ttl = 0;
        CHECK(sa_std_net_udp_ttl(udp_v6, &ttl) == SA_STD_OK && ttl == 31, 222);
        CHECK(sa_std_net_udp_set_ttl(udp_v6, 256) == SA_STD_ERR_INVALID_ARGUMENT, 223);
    }

    CHECK(sa_fs_make_dir((const uint8_t *)".zig-cache", sizeof(".zig-cache") - 1) == SA_STD_OK,
          240);
    uds_path_len = snprintf(uds_path, sizeof(uds_path), ".zig-cache/runtime-darwin-socket-%u.sock",
                            (unsigned)sa_std_process_id());
    CHECK(uds_path_len > 0 && (size_t)uds_path_len < sizeof(uds_path), 241);
    (void)sa_fs_remove_file((const uint8_t *)uds_path, (uint64_t)uds_path_len);
    CHECK(sa_std_net_unix_addr_from_pathname((const uint8_t *)uds_path, (uint64_t)uds_path_len,
                                             &uds_path_addr) == SA_STD_OK &&
              uds_path_addr != 0,
          242);
    CHECK(unix_addr_matches_path(uds_path_addr, uds_path, (uint64_t)uds_path_len), 243);
    CHECK(sa_std_net_unix_listen_addr(uds_path_addr, &uds_listener) == SA_STD_OK &&
              uds_listener != 0,
          244);
    uds_path_created = 1;
    CHECK(sa_std_net_unix_listener_local_addr(uds_listener, &uds_local_addr) == SA_STD_OK &&
              uds_local_addr != 0,
          245);
    CHECK(unix_addr_matches_path(uds_local_addr, uds_path, (uint64_t)uds_path_len), 246);
    CHECK(sa_net_unix_addr_free(uds_local_addr).status == SA_STD_OK, 247);
    uds_local_addr = 0;
    CHECK(sa_std_net_unix_connect_addr(uds_path_addr, &uds_client) == SA_STD_OK &&
              uds_client != 0,
          248);
    CHECK(sa_std_net_unix_stream_peer_addr(uds_client, &uds_peer_addr) == SA_STD_OK &&
              uds_peer_addr != 0,
          249);
    CHECK(unix_addr_matches_path(uds_peer_addr, uds_path, (uint64_t)uds_path_len), 250);
    CHECK(sa_net_unix_addr_free(uds_peer_addr).status == SA_STD_OK, 251);
    uds_peer_addr = 0;
    CHECK(sa_std_net_unix_accept_addr(uds_listener, &uds_server, &uds_accept_addr) == SA_STD_OK &&
              uds_server != 0 && uds_accept_addr != 0,
          252);
    CHECK(sa_net_unix_addr_kind(uds_accept_addr) == SA_NET_UNIX_ADDR_UNNAMED, 253);
    CHECK(sa_net_unix_addr_free(uds_accept_addr).status == SA_STD_OK, 254);
    uds_accept_addr = 0;
    CHECK(sa_std_net_tcp_stream_set_read_timeout(uds_server, CONTRACT_TIMEOUT_NS) == SA_STD_OK,
          255);
    CHECK(write_all(uds_client, uds_request, sizeof(uds_request) - 1), 256);
    memset(buffer, 0, sizeof(buffer));
    CHECK(read_exact(uds_server, buffer, sizeof(uds_request) - 1) &&
              memcmp(buffer, uds_request, sizeof(uds_request) - 1) == 0,
          257);

    {
        static const uint8_t abstract_name[] = "runtime-darwin-abstract";
        uint64_t abstract_addr = UINT64_MAX;
        int32_t quickack_enabled = 77;
        int32_t passcred_enabled = 77;
        int32_t datagram_passcred_enabled = 77;
        uint32_t seconds = 77;
        int32_t peer_pid = 77;
        uint32_t peer_uid = 77;
        uint32_t peer_gid = 77;
        uint64_t epoll_handle = UINT64_MAX;
        uint64_t pidfd_handle = UINT64_MAX;
        uint64_t pidfd_process = UINT64_MAX;
        uint64_t pidfd_stdout = UINT64_MAX;
        uint64_t pidfd_stderr = UINT64_MAX;
        int32_t pidfd_ready = 77;
        uint32_t pidfd_code = 77;
        uint64_t epoll_count = UINT64_MAX;
        SaTermEpollEvent epoll_event = {1, 2};
        uint8_t ticket_payload = 1;
        SaNetxTicket ticket = {1, 2, 3, 4, &ticket_payload, 5, 6};

        CHECK(sa_std_net_unix_addr_from_abstract_name(abstract_name,
                                                       sizeof(abstract_name) - 1,
                                                       &abstract_addr) ==
                      SA_STD_ERR_UNSUPPORTED &&
                  abstract_addr == 0,
              300);
        CHECK(sa_std_net_tcp_stream_set_quickack(tcp_client, 1) == SA_STD_ERR_UNSUPPORTED,
              301);
        CHECK(sa_std_net_tcp_stream_quickack(tcp_client, &quickack_enabled) ==
                      SA_STD_ERR_UNSUPPORTED &&
                  quickack_enabled == 0,
              302);
        CHECK(sa_std_net_tcp_stream_set_deferaccept(tcp_client, 1) == SA_STD_ERR_UNSUPPORTED,
              303);
        CHECK(sa_std_net_tcp_stream_deferaccept(tcp_client, &seconds) ==
                      SA_STD_ERR_UNSUPPORTED &&
                  seconds == 0,
              304);
        CHECK(sa_std_net_unix_stream_set_passcred(uds_client, 1) == SA_STD_ERR_UNSUPPORTED,
              305);
        CHECK(sa_std_net_unix_stream_passcred(uds_client, &passcred_enabled) ==
                      SA_STD_ERR_UNSUPPORTED &&
                  passcred_enabled == 0,
              306);
        CHECK(sa_std_net_unix_datagram_set_passcred(0, 1) == SA_STD_ERR_UNSUPPORTED, 307);
        CHECK(sa_std_net_unix_datagram_passcred(0, &datagram_passcred_enabled) ==
                      SA_STD_ERR_UNSUPPORTED &&
                  datagram_passcred_enabled == 0,
              308);
        CHECK(sa_std_net_unix_stream_set_mark(uds_client, 1) == SA_STD_ERR_UNSUPPORTED, 309);
        CHECK(sa_std_net_unix_stream_peer_cred(uds_client, &peer_pid, &peer_uid, &peer_gid) ==
                      SA_STD_ERR_UNSUPPORTED &&
                  peer_pid == 0 && peer_uid == 0 && peer_gid == 0,
              310);
        CHECK(sa_term_epoll_create(0, &epoll_handle) == SA_STD_ERR_UNSUPPORTED &&
                  epoll_handle == 0,
              311);
        CHECK(sa_term_epoll_wait(0, &epoll_event, 1, 0, &epoll_count) ==
                      SA_STD_ERR_UNSUPPORTED &&
                  epoll_count == 0,
              312);
        CHECK(sa_term_epoll_close(0) == SA_STD_ERR_UNSUPPORTED, 313);
        CHECK(sa_std_process_pidfd(0, &pidfd_handle) == SA_STD_ERR_UNSUPPORTED &&
                  pidfd_handle == 0,
              314);
        CHECK(sa_std_pidfd_try_wait(0, &pidfd_ready, &pidfd_code) ==
                      SA_STD_ERR_UNSUPPORTED &&
                  pidfd_ready == 0 && pidfd_code == 0,
              315);
        CHECK(sa_std_process_run_command_ext_pidfd(NULL, 0, NULL, 0, 0, NULL, 0, 0, 0, 0, 0,
                                                    1, &pidfd_process) ==
                      SA_STD_ERR_UNSUPPORTED &&
                  pidfd_process == 0,
              316);
        pidfd_process = UINT64_MAX;
        CHECK(sa_std_process_spawn_command_ext_pidfd(NULL, 0, NULL, 0, 0, NULL, 0, 0, 0, 0, 0,
                                                      1, &pidfd_process) ==
                      SA_STD_ERR_UNSUPPORTED &&
                  pidfd_process == 0,
              317);
        pidfd_process = UINT64_MAX;
        CHECK(sa_std_process_spawn_stream_command_ext_pidfd(
                  NULL, 0, NULL, 0, 0, NULL, 0, 0, 0, 0, 0, 1, &pidfd_process, &pidfd_stdout,
                  &pidfd_stderr) == SA_STD_ERR_UNSUPPORTED &&
                  pidfd_process == 0 && pidfd_stdout == 0 && pidfd_stderr == 0,
              318);
        CHECK(sa_netx_init(8, 1) == SA_STD_OK, 319);
        CHECK(sa_netx_recv_ticket(99, &ticket) == SA_STD_ERR_INVALID_HANDLE, 320);
        CHECK(sa_netx_shutdown() == SA_STD_OK, 321);
    }

cleanup:
    if (uds_accept_addr != 0) (void)sa_net_unix_addr_free(uds_accept_addr);
    if (uds_peer_addr != 0) (void)sa_net_unix_addr_free(uds_peer_addr);
    if (uds_local_addr != 0) (void)sa_net_unix_addr_free(uds_local_addr);
    if (uds_server != 0) (void)sa_std_close(uds_server);
    if (uds_client != 0) (void)sa_std_close(uds_client);
    if (uds_listener != 0) (void)sa_std_close(uds_listener);
    if (uds_path_addr != 0) (void)sa_net_unix_addr_free(uds_path_addr);
    if (uds_path_created) {
        (void)sa_fs_remove_file((const uint8_t *)uds_path, (uint64_t)uds_path_len);
    }
    if (udp_recv_addr != 0) (void)sa_net_addr_free(udp_recv_addr);
    if (udp_addr_b != 0) (void)sa_net_addr_free(udp_addr_b);
    if (udp_addr_a != 0) (void)sa_net_addr_free(udp_addr_a);
    if (udp_b != 0) (void)sa_std_close(udp_b);
    if (udp_a != 0) (void)sa_std_close(udp_a);
    if (udp_v6 != 0) (void)sa_std_close(udp_v6);
    if (tcp_addr != 0) (void)sa_net_addr_free(tcp_addr);
    if (tcp_server != 0) (void)sa_std_close(tcp_server);
    if (tcp_client != 0) (void)sa_std_close(tcp_client);
    if (tcp_listener != 0) (void)sa_std_close(tcp_listener);
    if (dns_addr != 0) (void)sa_net_addr_free(dns_addr);
    if (result == 0) puts("runtime Darwin socket contract ok");
    return result;
}
