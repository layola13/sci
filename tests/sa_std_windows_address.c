#include "../src/runtime/sa_std.h"

#include <stdint.h>
#include <stdio.h>
#include <string.h>

static int fail_at(int code, const char *what) {
    fprintf(stderr, "sa_std_windows_address: %s (code=%d)\n", what, code);
    return code;
}

#define CHECK(n, expr) do { if (!(expr)) return fail_at((n), #expr); } while (0)

/* sa_std.h exposes this legacy wrapper through the fallible i32 payload. */
static int32_t free_address(uint64_t handle) {
    return sa_net_addr_free(handle).status;
}

static int check_ipv4_parser(void) {
    static const uint8_t valid[] = "192.168.1.25";
    static const uint8_t minimum[] = "0.0.0.0";
    static const uint8_t maximum[] = "255.255.255.255";
    static const uint8_t invalid[] = "192.168.1.256";
    static const uint8_t trailing[] = "192.168.1.25x";
    uint8_t address[4] = {0xaa, 0xaa, 0xaa, 0xaa};

    CHECK(10, sa_net_ipv4_parse_ascii(valid, sizeof(valid) - 1, address) == 1);
    CHECK(11, memcmp(address, (const uint8_t[]){192, 168, 1, 25}, 4) == 0);

    memset(address, 0xaa, sizeof(address));
    CHECK(12, sa_net_ipv4_parse_ascii(minimum, sizeof(minimum) - 1, address) == 1);
    CHECK(13, memcmp(address, (const uint8_t[]){0, 0, 0, 0}, 4) == 0);

    memset(address, 0xaa, sizeof(address));
    CHECK(14, sa_net_ipv4_parse_ascii(maximum, sizeof(maximum) - 1, address) == 1);
    CHECK(15, memcmp(address, (const uint8_t[]){255, 255, 255, 255}, 4) == 0);

    CHECK(16, sa_net_ipv4_parse_ascii(invalid, sizeof(invalid) - 1, address) == 0);
    CHECK(17, memcmp(address, (const uint8_t[]){0, 0, 0, 0}, 4) == 0);

    memset(address, 0xaa, sizeof(address));
    CHECK(18, sa_net_ipv4_parse_ascii(trailing, sizeof(trailing) - 1, address) == 0);
    CHECK(19, memcmp(address, (const uint8_t[]){0, 0, 0, 0}, 4) == 0);

    memset(address, 0xaa, sizeof(address));
    CHECK(20, sa_net_ipv4_parse_ascii(NULL, 1, address) == 0);
    CHECK(21, memcmp(address, (const uint8_t[]){0, 0, 0, 0}, 4) == 0);

    memset(address, 0xaa, sizeof(address));
    CHECK(22, sa_net_ipv4_parse_ascii(valid, sizeof(valid) - 1, NULL) == 0);
    CHECK(23, sa_net_ipv4_parse_ascii(NULL, 0, address) == 0);
    CHECK(24, memcmp(address, (const uint8_t[]){0, 0, 0, 0}, 4) == 0);
    return 0;
}

static int check_socket_address_parser(void) {
    static const uint8_t valid[] = "127.0.0.1:8080";
    static const uint8_t maximum_port[] = "255.255.255.255:65535";
    static const uint8_t invalid_port[] = "127.0.0.1:65536";
    static const uint8_t invalid_shape[] = "127.0.0.1";
    static const uint8_t missing_host[] = ":80";
    static const uint8_t missing_port[] = "127.0.0.1:";
    static const uint8_t non_numeric_port[] = "127.0.0.1:80x";
    const uint8_t expected[] = {127, 0, 0, 1, 0x90, 0x1f, 0, 0};
    const uint8_t expected_maximum[] = {255, 255, 255, 255, 0xff, 0xff, 0, 0};
    uint8_t socket_address[8] = {0xaa, 0xaa, 0xaa, 0xaa, 0xaa, 0xaa, 0xaa, 0xaa};

    CHECK(30, sa_net_socket_addr_v4_parse_ascii(valid, sizeof(valid) - 1, socket_address) == 1);
    CHECK(31, memcmp(socket_address, expected, sizeof(expected)) == 0);

    memset(socket_address, 0xaa, sizeof(socket_address));
    CHECK(32, sa_net_socket_addr_v4_parse_ascii(
        maximum_port, sizeof(maximum_port) - 1, socket_address) == 1);
    CHECK(33, memcmp(socket_address, expected_maximum, sizeof(expected_maximum)) == 0);

    CHECK(34, sa_net_socket_addr_v4_parse_ascii(
        invalid_port, sizeof(invalid_port) - 1, socket_address) == 0);
    CHECK(35, memcmp(socket_address, (const uint8_t[8]){0}, 8) == 0);

    memset(socket_address, 0xaa, sizeof(socket_address));
    CHECK(36, sa_net_socket_addr_v4_parse_ascii(
        invalid_shape, sizeof(invalid_shape) - 1, socket_address) == 0);
    CHECK(37, memcmp(socket_address, (const uint8_t[8]){0}, 8) == 0);

    CHECK(38, sa_net_socket_addr_v4_parse_ascii(
        missing_host, sizeof(missing_host) - 1, socket_address) == 0);
    CHECK(39, memcmp(socket_address, (const uint8_t[8]){0}, 8) == 0);

    CHECK(40, sa_net_socket_addr_v4_parse_ascii(
        missing_port, sizeof(missing_port) - 1, socket_address) == 0);
    CHECK(41, memcmp(socket_address, (const uint8_t[8]){0}, 8) == 0);

    CHECK(42, sa_net_socket_addr_v4_parse_ascii(
        non_numeric_port, sizeof(non_numeric_port) - 1, socket_address) == 0);
    CHECK(43, memcmp(socket_address, (const uint8_t[8]){0}, 8) == 0);

    CHECK(44, sa_net_socket_addr_v4_parse_ascii(valid, sizeof(valid) - 1, NULL) == 0);
    CHECK(45, sa_net_socket_addr_v4_parse_ascii(NULL, 1, socket_address) == 0);
    CHECK(46, memcmp(socket_address, (const uint8_t[8]){0}, 8) == 0);
    return 0;
}

static int check_invalid_handle_output_clearing(void) {
    const uint64_t invalid_socket = UINT64_C(0xfeedface);
    uint64_t output_addr = UINT64_C(0xfeedface);
    int32_t status;

    status = sa_std_net_udp_local_addr(invalid_socket, &output_addr);
    CHECK(50, status == SA_STD_ERR_INVALID_HANDLE);
    CHECK(51, output_addr == 0);

    output_addr = UINT64_C(0xfeedface);
    status = sa_std_net_udp_peer_addr(invalid_socket, &output_addr);
    CHECK(52, status == SA_STD_ERR_INVALID_HANDLE);
    CHECK(53, output_addr == 0);

    CHECK(54, sa_std_net_udp_local_addr(invalid_socket, NULL) == SA_STD_ERR_INVALID_ARGUMENT);
    CHECK(55, sa_std_net_udp_peer_addr(invalid_socket, NULL) == SA_STD_ERR_INVALID_ARGUMENT);
    return 0;
}

static int check_address_handle_abi(void) {
    static const uint8_t loopback[] = "127.0.0.1";
    uint64_t socket_handle = 0;
    uint64_t addr_handle = 0;
    uint8_t *host;
    uint64_t host_len;
    int32_t status;

    status = sa_std_net_udp_bind(loopback, sizeof(loopback) - 1, 0, &socket_handle);
    CHECK(40, status == SA_STD_OK);
    CHECK(41, socket_handle != 0);

    status = sa_std_net_udp_local_addr(socket_handle, &addr_handle);
    CHECK(42, status == SA_STD_OK);
    CHECK(43, addr_handle != 0);

    CHECK(44, sa_net_addr_family(addr_handle) == 2);
    CHECK(45, sa_net_addr_port(addr_handle) != 0);
    CHECK(46, sa_net_addr_scope_id(addr_handle) == 0);

    host = sa_net_addr_host(addr_handle);
    host_len = sa_net_addr_host_len(addr_handle);
    CHECK(47, host != NULL);
    CHECK(48, host_len != 0);
    CHECK(49, host_len == 9 && memcmp(host, loopback, 9) == 0);

    CHECK(60, free_address(addr_handle) == SA_STD_OK);
    CHECK(61, free_address(addr_handle) == SA_STD_ERR_INVALID_HANDLE);
    CHECK(62, sa_net_addr_host(addr_handle) == NULL);
    CHECK(63, sa_net_addr_host_len(addr_handle) == 0);
    CHECK(64, sa_net_addr_port(addr_handle) == 0);
    CHECK(65, sa_net_addr_family(addr_handle) == 0);
    CHECK(66, sa_net_addr_scope_id(addr_handle) == 0);

    CHECK(67, free_address(0xfeedfaceULL) == SA_STD_ERR_INVALID_HANDLE);
    CHECK(68, sa_net_udp_close(socket_handle) == SA_STD_OK);
    return 0;
}

int main(void) {
    int result;

    result = check_ipv4_parser();
    if (result != 0) return result;
    result = check_socket_address_parser();
    if (result != 0) return result;
    result = check_invalid_handle_output_clearing();
    if (result != 0) return result;
    result = check_address_handle_abi();
    if (result != 0) return result;
    return 0;
}
