#include "../src/runtime/sa_std.h"

#include <stddef.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>

/*
 * The default build is deliberately link-free with respect to UDP.  Define
 * SA_STD_WINDOWS_UDP_SUPPORTED when the Windows runtime exports the UDP
 * slice and the loopback/multicast tests below should be compiled.
 */

#if !defined(SA_STD_WINDOWS_UDP_SUPPORTED)

#if defined(__STDC_VERSION__) && __STDC_VERSION__ >= 201112L
_Static_assert(sizeof(uint64_t) == 8, "SA handles must be 64-bit");
_Static_assert(sizeof(sa_std_fallible_i32) == 8, "fallible i32 ABI size");
_Static_assert(offsetof(sa_std_fallible_i32, status) == 0, "fallible status offset");
_Static_assert(offsetof(sa_std_fallible_i32, value) == 4, "fallible value offset");
#else
typedef char sa_udp_handles_must_be_64_bit[(sizeof(uint64_t) == 8) ? 1 : -1];
typedef char sa_udp_fallible_i32_must_be_8_bytes[(sizeof(sa_std_fallible_i32) == 8) ? 1 : -1];
typedef char sa_udp_fallible_status_must_be_first
    [(offsetof(sa_std_fallible_i32, status) == 0) ? 1 : -1];
typedef char sa_udp_fallible_value_must_follow_status
    [(offsetof(sa_std_fallible_i32, value) == 4) ? 1 : -1];
#endif

int main(void) {
    puts("sa_std_windows_udp fixture compile-only mode ok");
    return 0;
}

#else

static int fail_at(int code, const char *what) {
    fprintf(stderr, "sa_std_windows_udp: %s (code=%d)\n", what, code);
    return code;
}

static int is_unsupported(int32_t status) {
    return status == SA_STD_ERR_UNSUPPORTED;
}

#define CHECK(n, expr) do { if (!(expr)) return fail_at((n), #expr); } while (0)

static int bind_loopback(uint64_t *out_socket) {
    static const uint8_t loopback[] = "127.0.0.1";
    int32_t status;

    *out_socket = UINT64_C(0xfeedface);
    status = sa_std_net_udp_bind(loopback, sizeof(loopback) - 1, 0, out_socket);
    if (is_unsupported(status)) {
        CHECK(10, *out_socket == 0);
        return SA_STD_ERR_UNSUPPORTED;
    }
    CHECK(11, status == SA_STD_OK);
    CHECK(12, *out_socket != 0);
    uint64_t clone = 0;
    CHECK(15, sa_std_net_udp_try_clone(*out_socket, &clone) == SA_STD_OK);
    CHECK(16, clone != 0);
    CHECK(17, sa_net_udp_close(clone) == SA_STD_OK);
    return SA_STD_OK;
}

static int close_udp(uint64_t *socket_handle) {
    int32_t status;

    if (*socket_handle == 0) return 0;
    status = sa_net_udp_close(*socket_handle);
    CHECK(13, status == SA_STD_OK);
    CHECK(14, sa_net_udp_close(*socket_handle) == SA_STD_ERR_INVALID_HANDLE);
    *socket_handle = 0;
    return 0;
}

static int check_output_clearing(void) {
    uint8_t buffer[8] = {0};
    uint64_t output_addr = UINT64_C(0xfeedface);
    uint64_t output_read = UINT64_MAX;
    uint64_t output_timeout = UINT64_MAX;
    uint64_t output_written = UINT64_MAX;
    int32_t output_enabled = -1;
    uint32_t output_ttl = UINT32_MAX;
    int32_t status;

    status = sa_std_net_udp_local_addr(UINT64_C(0xfeedface), &output_addr);
    CHECK(20, status != SA_STD_OK);
    CHECK(21, output_addr == 0);

    output_addr = UINT64_C(0xfeedface);
    status = sa_std_net_udp_peer_addr(UINT64_C(0xfeedface), &output_addr);
    CHECK(22, status != SA_STD_OK);
    CHECK(23, output_addr == 0);

    status = sa_std_net_udp_recv(UINT64_C(0xfeedface), buffer, sizeof(buffer), &output_read);
    CHECK(24, status != SA_STD_OK);
    CHECK(25, output_read == 0);

    output_read = UINT64_MAX;
    output_addr = UINT64_C(0xfeedface);
    status = sa_std_net_udp_recv_from(
        UINT64_C(0xfeedface), buffer, sizeof(buffer), &output_read, &output_addr);
    CHECK(26, status != SA_STD_OK);
    CHECK(27, output_read == 0);
    CHECK(28, output_addr == 0);

    output_read = UINT64_MAX;
    output_addr = UINT64_C(0xfeedface);
    status = sa_std_net_udp_peek_from(
        UINT64_C(0xfeedface), buffer, sizeof(buffer), &output_read, &output_addr);
    CHECK(29, status != SA_STD_OK);
    CHECK(30, output_read == 0);
    CHECK(31, output_addr == 0);

    status = sa_std_net_udp_read_timeout(UINT64_C(0xfeedface), &output_timeout);
    CHECK(32, status != SA_STD_OK);
    CHECK(33, output_timeout == 0);

    output_timeout = UINT64_MAX;
    status = sa_std_net_udp_write_timeout(UINT64_C(0xfeedface), &output_timeout);
    CHECK(34, status != SA_STD_OK);
    CHECK(35, output_timeout == 0);

    status = sa_std_net_udp_broadcast(UINT64_C(0xfeedface), &output_enabled);
    CHECK(36, status != SA_STD_OK);
    CHECK(37, output_enabled == 0);

    output_enabled = -1;
    status = sa_std_net_udp_multicast_loop_v4(UINT64_C(0xfeedface), &output_enabled);
    CHECK(38, status != SA_STD_OK);
    CHECK(39, output_enabled == 0);

    status = sa_std_net_udp_ttl(UINT64_C(0xfeedface), &output_ttl);
    CHECK(40, status != SA_STD_OK);
    CHECK(41, output_ttl == 0);

    output_ttl = UINT32_MAX;
    status = sa_std_net_udp_multicast_ttl_v4(UINT64_C(0xfeedface), &output_ttl);
    CHECK(42, status != SA_STD_OK);
    CHECK(43, output_ttl == 0);

    status = sa_std_net_udp_send(
        UINT64_C(0xfeedface), buffer, sizeof(buffer), &output_written);
    CHECK(44, status != SA_STD_OK);
    CHECK(45, output_written == 0);

    return 0;
}

static int check_bind_and_address_ownership(void) {
    uint64_t socket_handle = 0;
    uint64_t first_addr = UINT64_C(0xfeedface);
    uint64_t second_addr = UINT64_C(0xfeedface);
    uint32_t family;
    uint32_t port;
    uint64_t scope;
    uint8_t *host;
    uint64_t host_len;
    int32_t status;

    status = bind_loopback(&socket_handle);
    if (is_unsupported(status)) {
        puts("udp bind/address ownership skipped: unsupported");
        return 0;
    }

    status = sa_std_net_udp_local_addr(socket_handle, &first_addr);
    CHECK(50, status == SA_STD_OK);
    CHECK(51, first_addr != 0);
    CHECK(52, sa_net_addr_host(first_addr) != NULL);
    CHECK(53, sa_net_addr_host_len(first_addr) != 0);

    host = sa_net_addr_host(first_addr);
    host_len = sa_net_addr_host_len(first_addr);
    family = sa_net_addr_family(first_addr);
    port = sa_net_addr_port(first_addr);
    scope = sa_net_addr_scope_id(first_addr);
    CHECK(54, host != NULL && host_len != 0);
    CHECK(55, family == 2 || family == 10);
    CHECK(56, port != 0);
    CHECK(57, family == 2 ? scope == 0 : 1);

    status = sa_std_net_udp_local_addr(socket_handle, &second_addr);
    CHECK(58, status == SA_STD_OK);
    CHECK(59, second_addr != 0 && second_addr != first_addr);

    /* Address handles own their host text and outlive their socket. */
    CHECK(60, close_udp(&socket_handle) == 0);
    CHECK(61, sa_net_addr_host(first_addr) != NULL);
    CHECK(62, sa_net_addr_host_len(first_addr) == host_len);
    CHECK(63, sa_net_addr_host(second_addr) != NULL);
    CHECK(64, sa_net_addr_host_len(second_addr) != 0);

    CHECK(65, sa_net_addr_free(first_addr).status == SA_STD_OK);
    CHECK(66, sa_net_addr_host(first_addr) == NULL);
    CHECK(67, sa_net_addr_host_len(first_addr) == 0);
    CHECK(68, sa_net_addr_port(first_addr) == 0);
    CHECK(69, sa_net_addr_family(first_addr) == 0);
    CHECK(70, sa_net_addr_scope_id(first_addr) == 0);
    CHECK(71, sa_net_addr_free(first_addr).status == SA_STD_ERR_INVALID_HANDLE);

    CHECK(72, sa_net_addr_host(second_addr) != NULL);
    CHECK(73, sa_net_addr_free(second_addr).status == SA_STD_OK);
    CHECK(74, sa_net_addr_free(second_addr).status == SA_STD_ERR_INVALID_HANDLE);
    CHECK(75, sa_net_addr_free(UINT64_C(0xfeedface)).status == SA_STD_ERR_INVALID_HANDLE);
    return 0;
}

static int check_options(void) {
    uint64_t socket_handle = 0;
    uint64_t timeout = UINT64_MAX;
    uint32_t ttl = UINT32_MAX;
    int32_t enabled = -1;
    int32_t error = -1;
    int32_t status;

    status = bind_loopback(&socket_handle);
    if (is_unsupported(status)) {
        puts("udp options skipped: unsupported");
        return 0;
    }

    CHECK(80, sa_std_net_udp_set_nonblocking(socket_handle, 1) == SA_STD_OK);
    CHECK(81, sa_std_net_udp_set_nonblocking(socket_handle, 0) == SA_STD_OK);

    /* Windows stores socket timeouts in milliseconds; the ABI takes ns. */
    CHECK(82, sa_std_net_udp_set_read_timeout(socket_handle, UINT64_C(1000001)) == SA_STD_OK);
    CHECK(83, sa_std_net_udp_read_timeout(socket_handle, &timeout) == SA_STD_OK);
    CHECK(84, timeout >= UINT64_C(1000000));

    timeout = UINT64_MAX;
    CHECK(85, sa_std_net_udp_set_write_timeout(socket_handle, UINT64_C(1000001)) == SA_STD_OK);
    CHECK(86, sa_std_net_udp_write_timeout(socket_handle, &timeout) == SA_STD_OK);
    CHECK(87, timeout >= UINT64_C(1000000));

    CHECK(88, sa_std_net_udp_set_broadcast(socket_handle, 1) == SA_STD_OK);
    CHECK(89, sa_std_net_udp_broadcast(socket_handle, &enabled) == SA_STD_OK);
    CHECK(90, enabled == 0 || enabled == 1);

    CHECK(91, sa_std_net_udp_set_ttl(socket_handle, 16) == SA_STD_OK);
    CHECK(92, sa_std_net_udp_ttl(socket_handle, &ttl) == SA_STD_OK);
    CHECK(93, ttl == 16);

    CHECK(94, sa_std_net_udp_take_error(socket_handle, &error) == SA_STD_OK);
    CHECK(95, error >= 0);
    return close_udp(&socket_handle);
}

static int check_connected_loopback(void) {
    static const uint8_t loopback[] = "127.0.0.1";
    static const uint8_t message[] = "udp-connected";
    uint64_t server = 0;
    uint64_t client = 0;
    uint64_t server_addr = 0;
    uint64_t target_addr = 0;
    uint64_t peer_addr = 0;
    uint32_t port = 0;
    uint8_t peeked[64] = {0};
    uint8_t received[64] = {0};
    uint64_t written = 0;
    uint64_t read = 0;
    int32_t status;

    status = bind_loopback(&server);
    if (is_unsupported(status)) {
        puts("udp connected loopback skipped: unsupported");
        return 0;
    }

    CHECK(100, sa_std_net_udp_local_addr(server, &server_addr) == SA_STD_OK);
    port = sa_net_addr_port(server_addr);
    CHECK(101, port != 0);
    CHECK(102, sa_net_addr_free(server_addr).status == SA_STD_OK);
    server_addr = 0;

    CHECK(103, sa_std_net_udp_bind(loopback, sizeof(loopback) - 1, 0, &client) == SA_STD_OK);
    CHECK(104, sa_std_net_to_socket_addr_first(loopback, sizeof(loopback) - 1, port, &target_addr) == SA_STD_OK);
    CHECK(105, sa_std_net_udp_connect_addr(client, target_addr) == SA_STD_OK);
    CHECK(106, sa_net_addr_free(target_addr).status == SA_STD_OK);
    target_addr = 0;
    CHECK(107, sa_std_net_udp_peer_addr(client, &peer_addr) == SA_STD_OK);
    CHECK(108, sa_net_addr_family(peer_addr) == 2);
    CHECK(109, sa_net_addr_port(peer_addr) == port);
    CHECK(110, sa_net_addr_free(peer_addr).status == SA_STD_OK);
    peer_addr = 0;

    CHECK(111, sa_std_net_udp_set_read_timeout(server, UINT64_C(500000000)) == SA_STD_OK);
    CHECK(112, sa_std_net_udp_send(client, message, sizeof(message) - 1, &written) == SA_STD_OK);
    CHECK(113, written == sizeof(message) - 1);
    CHECK(114, sa_std_net_udp_peek(server, peeked, sizeof(peeked), &read) == SA_STD_OK);
    CHECK(115, read == sizeof(message) - 1);
    CHECK(116, memcmp(peeked, message, read) == 0);
    CHECK(117, sa_std_net_udp_recv(server, received, sizeof(received), &read) == SA_STD_OK);
    CHECK(118, read == sizeof(message) - 1);
    CHECK(119, memcmp(received, message, read) == 0);

    CHECK(120, close_udp(&client) == 0);
    return close_udp(&server);
}

static int check_send_to_recv_from(void) {
    static const uint8_t loopback[] = "127.0.0.1";
    static const uint8_t message[] = "udp-datagram";
    uint64_t receiver = 0;
    uint64_t sender = 0;
    uint64_t receiver_addr = 0;
    uint64_t source_addr = UINT64_C(0xfeedface);
    uint32_t port;
    uint8_t peeked[64] = {0};
    uint8_t received[64] = {0};
    uint64_t written = 0;
    uint64_t read = 0;
    int32_t status;

    status = bind_loopback(&receiver);
    if (is_unsupported(status)) {
        puts("udp send_to/recv_from/peek_from skipped: unsupported");
        return 0;
    }

    CHECK(120, sa_std_net_udp_local_addr(receiver, &receiver_addr) == SA_STD_OK);
    port = sa_net_addr_port(receiver_addr);
    CHECK(121, port != 0);
    CHECK(122, sa_net_addr_free(receiver_addr).status == SA_STD_OK);
    receiver_addr = 0;

    CHECK(123, sa_std_net_udp_bind(loopback, sizeof(loopback) - 1, 0, &sender) == SA_STD_OK);
    CHECK(124, sa_std_net_udp_set_read_timeout(receiver, UINT64_C(500000000)) == SA_STD_OK);
    CHECK(125, sa_std_net_udp_send_to(
        sender, message, sizeof(message) - 1, loopback, sizeof(loopback) - 1, port, &written)
        == SA_STD_OK);
    CHECK(126, written == sizeof(message) - 1);

    CHECK(127, sa_std_net_udp_peek_from(
        receiver, peeked, sizeof(peeked), &read, &source_addr) == SA_STD_OK);
    CHECK(128, read == sizeof(message) - 1);
    CHECK(129, memcmp(peeked, message, read) == 0);
    CHECK(130, source_addr != 0);
    CHECK(131, sa_net_addr_family(source_addr) == 2);
    CHECK(132, sa_net_addr_free(source_addr).status == SA_STD_OK);
    source_addr = 0;

    CHECK(133, sa_std_net_udp_recv_from(
        receiver, received, sizeof(received), &read, &source_addr) == SA_STD_OK);
    CHECK(134, read == sizeof(message) - 1);
    CHECK(135, memcmp(received, message, read) == 0);
    CHECK(136, source_addr != 0);
    CHECK(137, sa_net_addr_free(source_addr).status == SA_STD_OK);
    source_addr = 0;

    CHECK(138, close_udp(&sender) == 0);
    return close_udp(&receiver);
}

static int check_multicast_options(void) {
    static const uint8_t multicast[] = "239.255.0.1";
    static const uint8_t any_interface[] = "0.0.0.0";
    uint64_t socket_handle = 0;
    int32_t loopback_enabled = -1;
    uint32_t ttl = UINT32_MAX;
    int32_t status;

    status = bind_loopback(&socket_handle);
    if (is_unsupported(status)) {
        puts("udp multicast skipped: unsupported");
        return 0;
    }

    CHECK(150, sa_std_net_udp_set_multicast_loop_v4(socket_handle, 1) == SA_STD_OK);
    CHECK(151, sa_std_net_udp_multicast_loop_v4(socket_handle, &loopback_enabled) == SA_STD_OK);
    CHECK(152, loopback_enabled == 0 || loopback_enabled == 1);
    CHECK(153, sa_std_net_udp_set_multicast_ttl_v4(socket_handle, 4) == SA_STD_OK);
    CHECK(154, sa_std_net_udp_multicast_ttl_v4(socket_handle, &ttl) == SA_STD_OK);
    CHECK(155, ttl == 4);

    status = sa_std_net_udp_join_multicast_v4(
        socket_handle, multicast, sizeof(multicast) - 1,
        any_interface, sizeof(any_interface) - 1);
    if (status == SA_STD_OK) {
        CHECK(156, sa_std_net_udp_leave_multicast_v4(
            socket_handle, multicast, sizeof(multicast) - 1,
            any_interface, sizeof(any_interface) - 1) == SA_STD_OK);
    } else {
        CHECK(157, status == SA_STD_ERR_UNSUPPORTED ||
            status == SA_STD_ERR_ACCESS || status == SA_STD_ERR_NET ||
            status == SA_STD_ERR_INVALID_ARGUMENT);
    }
    return close_udp(&socket_handle);
}

static int check_raw_fd_contract(void) {
    uint64_t output_handle = UINT64_C(0xfeedface);

    CHECK(160, sa_std_net_udp_from_raw_fd(1234, &output_handle) == SA_STD_ERR_UNSUPPORTED);
    CHECK(161, output_handle == 0);
    CHECK(162, sa_std_net_udp_from_raw_fd(1234, NULL) == SA_STD_ERR_INVALID_ARGUMENT);
    return 0;
}

int main(void) {
    int result;

    result = check_output_clearing();
    if (result != 0) return result;
    result = check_bind_and_address_ownership();
    if (result != 0) return result;
    result = check_options();
    if (result != 0) return result;
    result = check_connected_loopback();
    if (result != 0) return result;
    result = check_send_to_recv_from();
    if (result != 0) return result;
    result = check_multicast_options();
    if (result != 0) return result;
    result = check_raw_fd_contract();
    if (result != 0) return result;
    puts("sa_std_windows_udp fixture ok");
    return 0;
}

#endif
