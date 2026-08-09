#include "../src/runtime/sa_std.h"

#include <stdint.h>
#include <stdio.h>
#include <string.h>

/*
 * Standalone Windows-first ABI fixture.
 *
 * This file deliberately has no build-system dependency.  The integrating
 * test may compile it with sa_std.h and the Windows runtime archive/import
 * library, then run the resulting executable on a Windows host.
 *
 * The first slice has two kinds of assertions:
 *   - portable value contracts (buffers, status decoding, IPv4 parsing);
 *   - Windows boundary contracts (dynamic loading uses the native Windows
 *     loader; optional POSIX fd/terminal probes are opt-in below).
 */

static int fail_at(int code, const char *what) {
    fprintf(stderr, "sa_std_windows_first_slice: %s (code=%d)\n", what, code);
    return code;
}

#define CHECK(n, expr) do { if (!(expr)) return fail_at((n), #expr); } while (0)

/*
 * These opt-in checks require ABI slices that are not part of the current
 * Windows runtime archive.  Keep them available for a future native build,
 * but never make the default smoke link against their declarations alone.
 */
#ifndef SA_STD_WINDOWS_FIRST_SLICE_ENABLE_NATIVE_PROCESS
#define SA_STD_WINDOWS_FIRST_SLICE_ENABLE_NATIVE_PROCESS 0
#endif

#ifndef SA_STD_WINDOWS_FIRST_SLICE_ENABLE_NATIVE_FD
#define SA_STD_WINDOWS_FIRST_SLICE_ENABLE_NATIVE_FD 0
#endif

#ifndef SA_STD_WINDOWS_FIRST_SLICE_ENABLE_NATIVE_TERMINAL
#define SA_STD_WINDOWS_FIRST_SLICE_ENABLE_NATIVE_TERMINAL 0
#endif

static int check_io_buffer_lifecycle(void) {
    uint8_t bytes[] = {'o', 'k', '\n'};
    SaIoBuffer buffer = {bytes, sizeof(bytes), sizeof(bytes)};

    CHECK(10, sa_io_buffer_data(&buffer) == bytes);
    CHECK(11, sa_io_buffer_len(&buffer) == sizeof(bytes));
    CHECK(12, sa_io_buffer_data(NULL) == NULL);
    CHECK(13, sa_io_buffer_len(NULL) == 0);
    CHECK(14, sa_io_buffer_free(&buffer) == SA_STD_OK);

    /* The C ABI accepts a NULL optional buffer pointer and must not crash. */
    CHECK(15, sa_io_buffer_free(NULL) == SA_STD_OK);
    return 0;
}

static int check_io_read_line_contract(void) {
    uint64_t line = UINT64_C(0xfeedface);
    int32_t status = sa_io_read_line(UINT64_C(0xfeedface), 128, &line);

    /* Windows runtime may implement this later; until then it is explicit. */
    CHECK(20, status == SA_STD_ERR_UNSUPPORTED || status == SA_STD_ERR_INVALID_HANDLE);
    CHECK(21, line == 0);
    CHECK(22, sa_io_read_line(UINT64_C(0xfeedface), 128, NULL) == SA_STD_ERR_INVALID_ARGUMENT);
    return 0;
}

static int check_dynamic_loading(void) {
    static const uint8_t missing[] = "sa_std_windows_missing_module.dll";
    static const uint8_t module[] = "kernel32.dll";
    static const uint8_t missing_symbol[] = "sa_std_windows_missing_symbol";
    static const uint8_t symbol[] = "GetCurrentProcessId";
    uint64_t handle = 0;
    void *address = (void *)UINTPTR_MAX;
    int32_t status;
    const uint8_t *error;

    status = sa_dl_open(missing, sizeof(missing) - 1, &handle);
    CHECK(30, status == SA_STD_ERR_NOT_FOUND || status == SA_STD_ERR_ACCESS);
    CHECK(31, handle == 0);
    error = sa_dl_error();
    CHECK(32, error != NULL && error[0] != 0);

#if defined(_WIN32)
    status = sa_dl_open(module, sizeof(module) - 1, &handle);
    CHECK(33, status == SA_STD_OK);
    CHECK(34, handle != 0);

    status = sa_dl_sym(handle, missing_symbol, sizeof(missing_symbol) - 1, &address);
    CHECK(35, status == SA_STD_ERR_NOT_FOUND);
    CHECK(36, address == NULL);

    status = sa_dl_sym(handle, symbol, sizeof(symbol) - 1, &address);
    CHECK(37, status == SA_STD_OK);
    CHECK(38, address != NULL);
    CHECK(39, sa_dl_close(handle) == SA_STD_OK);
    CHECK(40, sa_dl_close(handle) == SA_STD_ERR_INVALID_HANDLE);
#else
    status = sa_dl_open(module, sizeof(module) - 1, &handle);
    CHECK(33, status == SA_STD_ERR_UNSUPPORTED);
    CHECK(34, handle == 0);
#endif
    return 0;
}

#if SA_STD_WINDOWS_FIRST_SLICE_ENABLE_NATIVE_PROCESS
static int check_process_status_helpers(void) {
#if defined(_WIN32)
    CHECK(50, sa_std_process_exit_status_code(42) == 42u);
    CHECK(51, sa_std_process_exit_status_signal(42) == -1);
    CHECK(52, sa_std_process_exit_status_core_dumped(42) == 0);
    CHECK(53, sa_std_process_exit_status_stopped_signal(42) == -1);
    CHECK(54, sa_std_process_exit_status_continued(42) == 0);
    CHECK(55, sa_std_process_exit_status_code(-1) == UINT32_MAX);
#else
    /* The fixture is Windows-first; Linux keeps its wait(2) interpretation. */
    CHECK(50, sa_std_process_exit_status_signal(0) == -1);
#endif
    return 0;
}
#endif

static int check_ipv4_and_socket_address(void) {
    static const uint8_t ip[] = "192.168.1.25";
    static const uint8_t socket_text[] = "127.0.0.1:8080";
    static const uint8_t bad_ip[] = "192.168.1.999";
    static const uint8_t bad_socket[] = "127.0.0.1:70000";
    uint8_t address[4] = {0xaa, 0xaa, 0xaa, 0xaa};
    uint8_t socket_address[8] = {0xaa, 0xaa, 0xaa, 0xaa, 0xaa, 0xaa, 0xaa, 0xaa};

    CHECK(60, sa_net_ipv4_parse_ascii(ip, sizeof(ip) - 1, address) == 1);
    CHECK(61, memcmp(address, (const uint8_t[]){192, 168, 1, 25}, 4) == 0);
    CHECK(62, sa_net_ipv4_parse_ascii(bad_ip, sizeof(bad_ip) - 1, address) == 0);
    CHECK(63, memcmp(address, (const uint8_t[]){0, 0, 0, 0}, 4) == 0);

    CHECK(64, sa_net_socket_addr_v4_parse_ascii(socket_text, sizeof(socket_text) - 1, socket_address) == 1);
    CHECK(65, memcmp(socket_address, (const uint8_t[]){127, 0, 0, 1, 0x90, 0x1f, 0, 0}, 8) == 0);
    CHECK(66, sa_net_socket_addr_v4_parse_ascii(bad_socket, sizeof(bad_socket) - 1, socket_address) == 0);
    CHECK(67, memcmp(socket_address, (const uint8_t[]){0, 0, 0, 0, 0, 0, 0, 0}, 8) == 0);
    CHECK(68, sa_net_ipv4_parse_ascii(ip, sizeof(ip) - 1, NULL) == 0);
    return 0;
}

#if SA_STD_WINDOWS_FIRST_SLICE_ENABLE_NATIVE_FD
static int check_windows_fd_boundary(void) {
    uint64_t output_handle = sa_io_stdout();
    uint64_t duplicate = UINT64_C(0xfeedface);
    int32_t raw = 1234;
    uint8_t is_terminal = 1;

    CHECK(70, sa_std_fd_as_raw(output_handle, &raw) == SA_STD_ERR_UNSUPPORTED);
    CHECK(71, raw == 0);
    CHECK(72, sa_std_fd_dup(output_handle, &duplicate) == SA_STD_ERR_UNSUPPORTED);
    CHECK(73, duplicate == 0);
    CHECK(74, sa_std_fd_dup_raw(1234, &duplicate) == SA_STD_ERR_UNSUPPORTED);
    CHECK(75, duplicate == 0);
    CHECK(76, sa_std_fd_from_raw(1234, &duplicate) == SA_STD_ERR_UNSUPPORTED);
    CHECK(77, duplicate == 0);
    CHECK(78, sa_std_fd_into_raw(output_handle, &raw) == SA_STD_ERR_UNSUPPORTED);
    CHECK(79, raw == 0);
    CHECK(80, sa_std_fd_close_raw(1234) == SA_STD_ERR_UNSUPPORTED);
    CHECK(81, sa_std_fd_is_terminal(output_handle, &is_terminal) == SA_STD_ERR_UNSUPPORTED);
    CHECK(82, is_terminal == 0);
    return 0;
}
#endif

#if SA_STD_WINDOWS_FIRST_SLICE_ENABLE_NATIVE_TERMINAL
static int check_windows_terminal_boundary(void) {
    uint64_t output_handle = sa_io_stdout();
    uint64_t session = UINT64_C(0xfeedface);
    SaTermWinsize size;
    uint64_t epoll = UINT64_C(0xfeedface);
    uint64_t count = 1234;
    SaTermEpollEvent event;

    CHECK(83, sa_term_raw_enter(output_handle, &session) == SA_STD_ERR_UNSUPPORTED);
    CHECK(84, session == 0);
    memset(&size, 0xff, sizeof(size));
    CHECK(85, sa_term_winsize(output_handle, &size) == SA_STD_ERR_UNSUPPORTED);
    CHECK(86, memset(&size, 0, sizeof(size)) == &size);
    CHECK(87, sa_term_raw_leave(UINT64_C(0xfeedface)) == SA_STD_ERR_UNSUPPORTED);
    CHECK(88, sa_term_epoll_create(0, &epoll) == SA_STD_ERR_UNSUPPORTED);
    CHECK(89, epoll == 0);
    CHECK(90, sa_term_epoll_ctl(UINT64_C(0xfeedface), 1, output_handle, 1, 0) == SA_STD_ERR_UNSUPPORTED);
    CHECK(91, sa_term_epoll_wait(UINT64_C(0xfeedface), &event, 1, 0, &count) == SA_STD_ERR_UNSUPPORTED);
    CHECK(92, count == 0);
    CHECK(93, sa_term_epoll_close(UINT64_C(0xfeedface)) == SA_STD_ERR_UNSUPPORTED);
    return 0;
}
#endif

int main(void) {
    int result;

    result = check_io_buffer_lifecycle();
    if (result != 0) return result;
    result = check_io_read_line_contract();
    if (result != 0) return result;
    result = check_dynamic_loading();
    if (result != 0) return result;
#if SA_STD_WINDOWS_FIRST_SLICE_ENABLE_NATIVE_PROCESS
    result = check_process_status_helpers();
    if (result != 0) return result;
#endif
    result = check_ipv4_and_socket_address();
    if (result != 0) return result;
#if SA_STD_WINDOWS_FIRST_SLICE_ENABLE_NATIVE_FD
    result = check_windows_fd_boundary();
    if (result != 0) return result;
#endif
#if SA_STD_WINDOWS_FIRST_SLICE_ENABLE_NATIVE_TERMINAL
    result = check_windows_terminal_boundary();
    if (result != 0) return result;
#endif

    puts("sa_std_windows_first_slice ok");
    return 0;
}
