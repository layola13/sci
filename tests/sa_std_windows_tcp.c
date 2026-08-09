#include "../src/runtime/sa_std.h"

#include <stdint.h>
#include <stddef.h>
#include <stdio.h>
#include <string.h>

/*
 * Windows TCP ABI smoke fixture.  Define SA_WINDOWS_TCP_EXPECT_SUPPORTED=1
 * when the Windows socket registry is enabled.  The default is an ABI-only
 * compile check: it intentionally emits no references to the TCP exports
 * that are not implemented by the Windows runtime yet.
 */
#ifndef SA_WINDOWS_TCP_EXPECT_SUPPORTED
#define SA_WINDOWS_TCP_EXPECT_SUPPORTED 0
#endif

#if SA_WINDOWS_TCP_EXPECT_SUPPORTED
typedef struct SaTcpFallibleI32 {
    int32_t status;
    int32_t value;
} SaTcpFallibleI32;

/* These convenience operations are declared in sa_std/net.sai, but are not
 * currently present in the public C header.  Keep their fallible layout
 * explicit so the fixture does not accidentally bless a plain int ABI. */
extern SaTcpFallibleI32 sa_net_tcp_stream_close(uint64_t stream_handle);
extern SaTcpFallibleI32 sa_net_tcp_listener_close(uint64_t listener_handle);
#endif

/*
 * sa_std/net.sai declares the legacy TCP close operations as i32!, which is
 * the two-word fallible ABI below.  The std-prefixed operations in the same
 * file return plain i32 and use explicit out parameters; the supported
 * template below follows that contract.
 */
_Static_assert(sizeof(sa_std_fallible_i32) == sizeof(int32_t) * 2,
               "fallible i32 ABI must contain status and value");
_Static_assert(offsetof(sa_std_fallible_i32, status) == 0,
               "fallible i32 status must be the first word");
_Static_assert(offsetof(sa_std_fallible_i32, value) == sizeof(int32_t),
               "fallible i32 value must be the second word");
_Static_assert(sizeof(uint64_t) == 8, "SA handles must be 64-bit");

#if SA_WINDOWS_TCP_EXPECT_SUPPORTED
static int fail_at(int code, const char *what) {
    fprintf(stderr, "sa_std_windows_tcp: %s (code=%d)\n", what, code);
    return code;
}

#define CHECK(n, expr) do { if (!(expr)) return fail_at((n), #expr); } while (0)

static int check_supported_loopback(void) {
    static const uint8_t host[] = "127.0.0.1";
    static const uint8_t request[] = "ping";
    static const uint8_t response[] = "pong";
    uint64_t listener = 0, client = 0, server = 0, addr = 0;
    uint32_t port = 0;
    uint64_t count = 0;
    uint8_t buffer[8] = {0};
    int32_t enabled = 0;
    uint64_t timeout = 0;
    SaTcpFallibleI32 close_result;

    CHECK(100, sa_std_net_tcp_listen(host, sizeof(host) - 1, 0, &listener, &port) == SA_STD_OK);
    CHECK(101, listener != 0 && port != 0);
    CHECK(102, sa_std_net_tcp_listener_local_addr(listener, &addr) == SA_STD_OK);
    CHECK(103, addr != 0);
    CHECK(104, sa_std_net_tcp_listener_set_nonblocking(listener, 0) == SA_STD_OK);
    CHECK(105, sa_std_net_tcp_listener_set_ttl(listener, 64) == SA_STD_OK);
    CHECK(106, sa_std_net_tcp_listener_ttl(listener, &((uint32_t){0})) == SA_STD_OK);

    CHECK(110, sa_std_net_tcp_connect(host, sizeof(host) - 1, port, &client) == SA_STD_OK);
    CHECK(111, client != 0);
    CHECK(112, sa_std_net_tcp_accept(listener, &server) == SA_STD_OK);
    CHECK(113, server != 0);
    CHECK(114, sa_std_net_tcp_stream_set_nonblocking(client, 0) == SA_STD_OK);
    CHECK(115, sa_std_net_tcp_stream_set_nodelay(client, 1) == SA_STD_OK);
    CHECK(116, sa_std_net_tcp_stream_nodelay(client, &enabled) == SA_STD_OK && enabled != 0);
    CHECK(117, sa_std_net_tcp_stream_set_read_timeout(client, 1000000000) == SA_STD_OK);
    CHECK(118, sa_std_net_tcp_stream_read_timeout(client, &timeout) == SA_STD_OK && timeout > 0);
    CHECK(119, sa_std_net_tcp_stream_set_write_timeout(client, 1000000000) == SA_STD_OK);
    CHECK(120, sa_std_net_tcp_stream_write_timeout(client, &timeout) == SA_STD_OK && timeout > 0);
    CHECK(121, sa_std_net_tcp_stream_write(client, request, sizeof(request) - 1, &count) == SA_STD_OK);
    CHECK(122, count == sizeof(request) - 1);
    CHECK(123, sa_std_net_tcp_stream_peek(server, buffer, sizeof(buffer), &count) == SA_STD_OK);
    CHECK(124, count == sizeof(request) - 1 && memcmp(buffer, request, count) == 0);
    CHECK(125, sa_std_net_tcp_stream_read(server, buffer, sizeof(buffer), &count) == SA_STD_OK);
    CHECK(126, count == sizeof(request) - 1 && memcmp(buffer, request, count) == 0);
    CHECK(127, sa_std_net_tcp_stream_write(server, response, sizeof(response) - 1, &count) == SA_STD_OK);
    CHECK(128, count == sizeof(response) - 1);
    CHECK(129, sa_std_net_tcp_stream_read(client, buffer, sizeof(buffer), &count) == SA_STD_OK);
    CHECK(130, count == sizeof(response) - 1 && memcmp(buffer, response, count) == 0);
    CHECK(131, sa_std_net_tcp_stream_peer_addr(client, &addr) == SA_STD_OK && addr != 0);
    CHECK(132, sa_std_net_tcp_stream_local_addr(client, &addr) == SA_STD_OK && addr != 0);

    close_result = sa_net_tcp_stream_close(client);
    CHECK(140, close_result.status == SA_STD_OK);
    CHECK(141, sa_net_tcp_stream_close(client).status == SA_STD_ERR_INVALID_HANDLE);
    close_result = sa_net_tcp_stream_close(server);
    CHECK(142, close_result.status == SA_STD_OK);
    close_result = sa_net_tcp_listener_close(listener);
    CHECK(143, close_result.status == SA_STD_OK);
    CHECK(144, sa_net_tcp_listener_close(listener).status == SA_STD_ERR_INVALID_HANDLE);
    return 0;
}

int main(void) {
    int result = 0;
#if SA_WINDOWS_TCP_EXPECT_SUPPORTED
    result = check_supported_loopback();
#endif
    if (result != 0) return result;
#if SA_WINDOWS_TCP_EXPECT_SUPPORTED
    puts("sa_std_windows_tcp ok");
#else
    puts("sa_std_windows_tcp ABI-only; define SA_WINDOWS_TCP_EXPECT_SUPPORTED=1 for loopback");
#endif
    return 0;
}
#else
int main(void) {
    puts("sa_std_windows_tcp ABI-only; define SA_WINDOWS_TCP_EXPECT_SUPPORTED=1 for loopback");
    return 0;
}
#endif
