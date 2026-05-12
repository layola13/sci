#ifndef SA_STD_H
#define SA_STD_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

#define SA_STD_ABI_VERSION 1u

#define SA_STD_OK 0
#define SA_STD_ERR_INVALID_ARGUMENT 1
#define SA_STD_ERR_INVALID_HANDLE 2
#define SA_STD_ERR_NOT_FOUND 3
#define SA_STD_ERR_ACCESS 4
#define SA_STD_ERR_NO_MEMORY 5
#define SA_STD_ERR_IO 6
#define SA_STD_ERR_NET 7
#define SA_STD_ERR_UNSUPPORTED 8
#define SA_STD_ERR_TRUNCATED 9
#define SA_STD_ERR_UNKNOWN 127

#define SA_STD_STDIN 1ull
#define SA_STD_STDOUT 2ull
#define SA_STD_STDERR 3ull

uint32_t sa_std_version(void);
int32_t sa_std_last_error(void);
int32_t sa_std_error_name(int32_t code, uint8_t *out, uint64_t out_cap, uint64_t *out_len);

uint64_t sa_std_stdin(void);
uint64_t sa_std_stdout(void);
uint64_t sa_std_stderr(void);

int32_t sa_std_print(const uint8_t *data, uint64_t len);
int32_t sa_std_println(const uint8_t *data, uint64_t len);
int32_t sa_std_write(uint64_t handle, const uint8_t *data, uint64_t len, uint64_t *out_written);
int32_t sa_std_read(uint64_t handle, uint8_t *out, uint64_t out_cap, uint64_t *out_read);
int32_t sa_std_close(uint64_t handle);

int32_t sa_std_fs_open_read(const uint8_t *path, uint64_t path_len, uint64_t *out_handle);
int32_t sa_std_fs_open_write(const uint8_t *path, uint64_t path_len, uint32_t truncate, uint64_t *out_handle);
int32_t sa_std_fs_remove(const uint8_t *path, uint64_t path_len);
int32_t sa_std_fs_exists(const uint8_t *path, uint64_t path_len);
int32_t sa_std_fs_len(const uint8_t *path, uint64_t path_len, uint64_t *out_len);

int32_t sa_std_net_tcp_connect(const uint8_t *host, uint64_t host_len, uint32_t port, uint64_t *out_handle);
int32_t sa_std_net_tcp_listen(const uint8_t *host, uint64_t host_len, uint32_t port, uint64_t *out_handle, uint32_t *out_bound_port);
int32_t sa_std_net_tcp_accept(uint64_t listener_handle, uint64_t *out_handle);

#ifdef __cplusplus
}
#endif

#endif
