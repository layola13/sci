#define _DARWIN_C_SOURCE

#include "sa_std.h"

#include <fcntl.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <termios.h>
#include <unistd.h>

#ifndef __APPLE__
#error "runtime_darwin_pty_contract.c must only be built for Darwin"
#endif

#define CHECK(condition, code)                                                                    \
    do {                                                                                          \
        if (!(condition)) {                                                                       \
            fprintf(stderr, "runtime Darwin PTY contract failed at line %d (code %d)\n",      \
                    __LINE__, (code));                                                             \
            result = (code);                                                                      \
            goto cleanup;                                                                         \
        }                                                                                         \
    } while (0)

static int open_pty_pair(int *master, int *slave) {
    int master_fd = posix_openpt(O_RDWR | O_NOCTTY);
    if (master_fd < 0) return -1;
    if (grantpt(master_fd) != 0 || unlockpt(master_fd) != 0) {
        close(master_fd);
        return -1;
    }

    const char *slave_name = ptsname(master_fd);
    if (slave_name == NULL) {
        close(master_fd);
        return -1;
    }
    int slave_fd = open(slave_name, O_RDWR | O_NOCTTY);
    if (slave_fd < 0) {
        close(master_fd);
        return -1;
    }

    *master = master_fd;
    *slave = slave_fd;
    return 0;
}

static int termios_matches(const struct termios *expected, const struct termios *actual) {
    return expected->c_iflag == actual->c_iflag && expected->c_oflag == actual->c_oflag &&
           expected->c_cflag == actual->c_cflag && expected->c_lflag == actual->c_lflag &&
           memcmp(expected->c_cc, actual->c_cc, sizeof(expected->c_cc)) == 0 &&
           cfgetispeed(expected) == cfgetispeed(actual) &&
           cfgetospeed(expected) == cfgetospeed(actual);
}

static int termios_is_runtime_raw(const struct termios *value) {
    const tcflag_t disabled_input =
        IGNBRK | BRKINT | PARMRK | ISTRIP | INLCR | IGNCR | ICRNL | IXON | IXOFF;
    const tcflag_t disabled_local = ISIG | ICANON | ECHO | ECHONL | IEXTEN;
    return (value->c_iflag & disabled_input) == 0 && (value->c_oflag & OPOST) == 0 &&
           (value->c_lflag & disabled_local) == 0 && (value->c_cflag & CSIZE) == CS8 &&
           (value->c_cflag & PARENB) == 0 && (value->c_cflag & CREAD) != 0 &&
           value->c_cc[VMIN] == 1 && value->c_cc[VTIME] == 0;
}

int main(void) {
    int result = 0;
    int master_fd = -1;
    int slave_fd = -1;
    int runtime_fd = -1;
    int pipe_fds[2] = {-1, -1};
    uint64_t slave_handle = 0;
    uint64_t pipe_handle = 0;
    uint64_t session = 0;
    uint64_t closed_session = 0;
    uint8_t is_terminal = 0;
    struct termios configured;
    struct termios before;
    struct termios after;
    struct winsize requested_size = {
        .ws_row = 37,
        .ws_col = 113,
        .ws_xpixel = 640,
        .ws_ypixel = 480,
    };
    SaTermWinsize queried_size = {0};

    CHECK(open_pty_pair(&master_fd, &slave_fd) == 0, 101);
    CHECK(tcgetattr(slave_fd, &configured) == 0, 102);
    configured.c_iflag |= ICRNL | IXON;
    configured.c_oflag |= OPOST;
    configured.c_cflag &= ~CSIZE;
    configured.c_cflag |= CS8 | CREAD;
    configured.c_lflag |= ISIG | ICANON | ECHO | ECHONL | IEXTEN;
    configured.c_cc[VMIN] = 7;
    configured.c_cc[VTIME] = 3;
    CHECK(tcsetattr(slave_fd, TCSANOW, &configured) == 0, 103);
    CHECK(ioctl(slave_fd, TIOCSWINSZ, &requested_size) == 0, 104);
    CHECK(tcgetattr(slave_fd, &before) == 0, 105);

    CHECK(sa_std_fd_from_raw(slave_fd, &slave_handle) == SA_STD_OK && slave_handle != 0, 106);
    runtime_fd = slave_fd;
    slave_fd = -1;
    CHECK(sa_std_fd_is_terminal(slave_handle, &is_terminal) == SA_STD_OK && is_terminal == 1,
          107);
    CHECK(sa_term_winsize(slave_handle, &queried_size) == SA_STD_OK, 108);
    CHECK(queried_size.row == requested_size.ws_row &&
              queried_size.col == requested_size.ws_col &&
              queried_size.xpixel == requested_size.ws_xpixel &&
              queried_size.ypixel == requested_size.ws_ypixel,
          109);

    CHECK(sa_term_raw_enter(slave_handle, &session) == SA_STD_OK && session != 0, 110);
    CHECK(tcgetattr(runtime_fd, &after) == 0 && termios_is_runtime_raw(&after), 111);
    is_terminal = 0;
    CHECK(sa_std_fd_is_terminal(slave_handle, &is_terminal) == SA_STD_OK && is_terminal == 1,
          112);
    memset(&queried_size, 0, sizeof(queried_size));
    CHECK(sa_term_winsize(slave_handle, &queried_size) == SA_STD_OK, 113);
    CHECK(queried_size.row == requested_size.ws_row &&
              queried_size.col == requested_size.ws_col &&
              queried_size.xpixel == requested_size.ws_xpixel &&
              queried_size.ypixel == requested_size.ws_ypixel,
          114);
    closed_session = session;
    CHECK(sa_term_raw_leave(session) == SA_STD_OK, 115);
    session = 0;
    CHECK(tcgetattr(runtime_fd, &after) == 0 && termios_matches(&before, &after), 116);
    CHECK(sa_term_raw_leave(closed_session) == SA_STD_ERR_INVALID_HANDLE, 117);
    closed_session = 0;

    CHECK(sa_term_raw_enter(slave_handle, &session) == SA_STD_OK && session != 0, 118);
    CHECK(tcgetattr(runtime_fd, &after) == 0 && termios_is_runtime_raw(&after), 119);
    CHECK(sa_std_close(session) == SA_STD_OK, 120);
    session = 0;
    CHECK(tcgetattr(runtime_fd, &after) == 0 && termios_matches(&before, &after), 121);

    CHECK(pipe(pipe_fds) == 0, 122);
    CHECK(sa_std_fd_from_raw(pipe_fds[0], &pipe_handle) == SA_STD_OK && pipe_handle != 0, 123);
    pipe_fds[0] = -1;
    queried_size = (SaTermWinsize){.row = 1, .col = 2, .xpixel = 3, .ypixel = 4};
    CHECK(sa_term_winsize(pipe_handle, &queried_size) == SA_STD_ERR_UNSUPPORTED, 124);
    CHECK(queried_size.row == 0 && queried_size.col == 0 && queried_size.xpixel == 0 &&
              queried_size.ypixel == 0,
          125);
    CHECK(sa_std_close(pipe_handle) == SA_STD_OK, 126);
    pipe_handle = 0;

    CHECK(sa_std_close(slave_handle) == SA_STD_OK, 127);
    slave_handle = 0;
    runtime_fd = -1;

cleanup:
    if (session != 0) (void)sa_term_raw_leave(session);
    if (pipe_handle != 0) (void)sa_std_close(pipe_handle);
    if (slave_handle != 0) (void)sa_std_close(slave_handle);
    if (pipe_fds[0] >= 0) close(pipe_fds[0]);
    if (pipe_fds[1] >= 0) close(pipe_fds[1]);
    if (slave_fd >= 0) close(slave_fd);
    if (master_fd >= 0) close(master_fd);
    if (result == 0) puts("runtime Darwin PTY contract ok");
    return result;
}
