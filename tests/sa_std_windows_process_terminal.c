#include "../src/runtime/sa_std.h"

#include <stdint.h>
#include <stdio.h>

/*
 * Windows process/terminal boundary fixture.
 *
 * This is intentionally a smoke fixture, not a claim that POSIX process
 * status or raw-fd semantics exist on Windows.  In particular, it never
 * calls sa_std_process_abort(), and it requires the POSIX-only status helpers
 * to remain explicitly unsupported at the runtime boundary.
 */

static int fail_at(int code, const char *what) {
    fprintf(stderr, "sa_std_windows_process_terminal: %s (code=%d)\n", what, code);
    return code;
}

#define CHECK(code, condition, text) \
    do { \
        if (!(condition)) return fail_at((code), (text)); \
    } while (0)

int main(void) {
    const uint64_t stdin_handle = sa_std_stdin();
    const uint64_t stdout_handle = sa_std_stdout();
    int32_t raw = INT32_C(0x13579bdf);
    uint64_t duplicate = UINT64_C(0xaaaaaaaaaaaaaaaa);
    uint8_t is_terminal = UINT8_C(0xa5);
    uint64_t session = UINT64_C(0xbbbbbbbbbbbbbbbb);
    SaTermWinsize size = {UINT16_C(0xaaaa), UINT16_C(0xbbbb), UINT16_C(0xcccc), UINT16_C(0xdddd)};
    SaTermEpollEvent event = {UINT32_C(0xffffffff), UINT64_C(0xcccccccccccccccc)};
    uint64_t count = UINT64_C(0xdddddddddddddddd);
    uint64_t unsupported_handle = UINT64_C(0xeeeeeeeeeeeeeeee);
    uint64_t http2_handle = UINT64_C(0x1111111111111111);
    uint64_t http2_bytes = UINT64_C(0x2222222222222222);
    uint64_t http2_json = UINT64_C(0x3333333333333333);
    uint32_t http2_supported = UINT32_C(0xffffffff);
    int32_t ready = INT32_C(0x12345678);
    int32_t raw_status = INT32_C(0x2468ace0);
    uint32_t code = UINT32_C(0xdeadbeef);

    /* Identity is the portable part of this boundary. */
    CHECK(1, sa_std_process_id() != 0, "process id must be nonzero");

    /* Parent id is observable on Windows; uid/gid remain synthetic. */
    CHECK(2, sa_std_process_parent_id() != 0, "parent id must be nonzero");
    CHECK(3, sa_std_process_user_id() == 0, "user id must remain unavailable");
    CHECK(4, sa_std_process_group_id() == 0, "group id must remain unavailable");

    /* Abort is a destructive boundary: symbol presence is compile-time API
     * coverage only.  Never invoke it from a smoke test. */
    (void)sa_std_process_abort;

    /* POSIX wait status is not a Windows exit-code adapter. */
    CHECK(10, sa_std_process_wait_raw(UINT64_C(0xfeedface), &raw_status) == SA_STD_ERR_UNSUPPORTED,
          "wait_raw must be unsupported");
    CHECK(11, raw_status == INT32_C(0x2468ace0), "wait_raw must not write output");
    CHECK(12, sa_std_process_try_wait_raw(UINT64_C(0xfeedface), &ready, &raw_status) == SA_STD_ERR_UNSUPPORTED,
          "try_wait_raw must be unsupported");
    CHECK(13, ready == INT32_C(0x12345678) && raw_status == INT32_C(0x2468ace0),
          "try_wait_raw must not write outputs");
    CHECK(14, sa_std_process_exit_status_code(INT32_C(42)) == UINT32_C(42),
          "Windows raw exit status must preserve the real exit code");
    CHECK(15, sa_std_process_exit_status_signal(INT32_C(42)) == 0,
          "signal decoder must remain unavailable");

    /* Raw fd conversion is not valid for Windows HANDLE/SOCKET values. */
    CHECK(20, sa_std_fd_as_raw(stdout_handle, &raw) == SA_STD_ERR_UNSUPPORTED,
          "fd_as_raw must be unsupported");
    CHECK(21, raw == INT32_C(-1), "fd_as_raw must initialize the unsupported output");
    CHECK(22, sa_std_fd_into_raw(stdout_handle, &raw) == SA_STD_ERR_UNSUPPORTED,
          "fd_into_raw must be unsupported");
    CHECK(23, sa_std_fd_dup(stdout_handle, &duplicate) == SA_STD_ERR_UNSUPPORTED,
          "fd_dup must be unsupported");
    CHECK(24, duplicate == UINT64_C(0), "fd_dup must initialize the unsupported output");
    CHECK(25, sa_std_fd_dup_raw(3, &duplicate) == SA_STD_ERR_UNSUPPORTED,
          "fd_dup_raw must be unsupported");
    CHECK(26, sa_std_fd_from_raw(3, &duplicate) == SA_STD_ERR_UNSUPPORTED,
          "fd_from_raw must be unsupported");
    CHECK(27, sa_std_fd_close_raw(3) == SA_STD_ERR_UNSUPPORTED,
          "fd_close_raw must be unsupported");
    CHECK(28, sa_std_fd_is_terminal(stdout_handle, &is_terminal) == SA_STD_ERR_UNSUPPORTED,
          "fd_is_terminal must be unsupported until console mapping exists");
    CHECK(29, is_terminal == UINT8_C(0), "fd_is_terminal must initialize the unsupported output");

    /* Raw terminal and epoll are distinct unsupported boundaries. */
    CHECK(30, sa_term_raw_enter(stdin_handle, &session) == SA_STD_ERR_UNSUPPORTED,
          "raw_enter must be unsupported");
    CHECK(31, session == UINT64_C(0xbbbbbbbbbbbbbbbb), "raw_enter must not write output");
    CHECK(32, sa_term_raw_leave(UINT64_C(0xfeedface)) == SA_STD_ERR_UNSUPPORTED,
          "raw_leave must be unsupported");
    CHECK(33, sa_term_winsize(stdin_handle, &size) == SA_STD_ERR_UNSUPPORTED,
          "winsize must be unsupported in the bootstrap boundary");
    CHECK(34, size.row == UINT16_C(0xaaaa) && size.col == UINT16_C(0xbbbb),
          "winsize must not write output");
    CHECK(35, sa_term_epoll_create(0, &unsupported_handle) == SA_STD_ERR_UNSUPPORTED,
          "epoll_create must be unsupported");
    CHECK(36, unsupported_handle == UINT64_C(0xeeeeeeeeeeeeeeee), "epoll_create must not write output");
    CHECK(37, sa_term_epoll_ctl(UINT64_C(0xfeedface), 1, stdout_handle, 1, 0) == SA_STD_ERR_UNSUPPORTED,
          "epoll_ctl must be unsupported");
    CHECK(38, sa_term_epoll_wait(UINT64_C(0xfeedface), &event, 1, 0, &count) == SA_STD_ERR_UNSUPPORTED,
          "epoll_wait must be unsupported");
    CHECK(39, count == UINT64_C(0xdddddddddddddddd), "epoll_wait must not write count");
    CHECK(40, sa_term_epoll_close(UINT64_C(0xfeedface)) == SA_STD_ERR_UNSUPPORTED,
          "epoll_close must be unsupported");

    /* HTTP/2 has a stable Windows ABI boundary even though nghttp2 is not
     * linked into the bootstrap runtime. */
    CHECK(50, sa_std_http2_supported(&http2_supported) == SA_STD_ERR_UNSUPPORTED,
          "http2_supported must be unsupported in the bootstrap runtime");
    CHECK(51, http2_supported == UINT32_C(0), "http2_supported must initialize its output");
    CHECK(52, sa_std_http2_status_json(&http2_handle) == SA_STD_ERR_UNSUPPORTED,
          "http2 status json must be unsupported");
    CHECK(53, http2_handle == UINT64_C(0), "http2 status json must initialize its handle");
    CHECK(54, sa_std_http2_perform_server_handshake(NULL, 0, NULL, 0, &http2_bytes, &http2_json) == SA_STD_ERR_UNSUPPORTED,
          "http2 handshake must be unsupported");
    CHECK(55, http2_bytes == UINT64_C(0) && http2_json == UINT64_C(0),
          "http2 handshake must initialize both output handles");
    CHECK(56, sa_std_http2_buffer_data(UINT64_C(1)) == NULL,
          "http2 buffer data must return null when unsupported");
    CHECK(57, sa_std_http2_buffer_len(UINT64_C(1)) == UINT64_C(0),
          "http2 buffer len must return zero when unsupported");
    CHECK(58, sa_std_http2_buffer_free(UINT64_C(1)) == SA_STD_ERR_UNSUPPORTED,
          "http2 buffer free must be unsupported");

    (void)code;
    return 0;
}
