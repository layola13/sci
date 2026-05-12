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

typedef struct SaIoBuffer {
    uint8_t *ptr;
    uint64_t len;
    uint64_t cap;
} SaIoBuffer;

typedef struct SaFsReadBuffer {
    uint8_t *ptr;
    uint64_t len;
    uint64_t cap;
} SaFsReadBuffer;

typedef struct SaNetAddr {
    uint32_t family;
    uint32_t port;
    uint8_t *host_ptr;
    uint64_t host_len;
    uint64_t scope_id;
} SaNetAddr;

typedef struct SaProcessArgv {
    const uint8_t *data;
    uint64_t len;
} SaProcessArgv;

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

uint8_t *sa_io_buffer_data(const SaIoBuffer *buffer);
uint64_t sa_io_buffer_len(const SaIoBuffer *buffer);
int32_t sa_io_buffer_free(SaIoBuffer *buffer);

int32_t sa_std_fs_open_read(const uint8_t *path, uint64_t path_len, uint64_t *out_handle);
int32_t sa_std_fs_open_write(const uint8_t *path, uint64_t path_len, uint32_t truncate, uint64_t *out_handle);
int32_t sa_std_fs_remove(const uint8_t *path, uint64_t path_len);
int32_t sa_std_fs_exists(const uint8_t *path, uint64_t path_len);
int32_t sa_std_fs_len(const uint8_t *path, uint64_t path_len, uint64_t *out_len);

uint8_t *sa_fs_read_buffer_data(const SaFsReadBuffer *buffer);
uint64_t sa_fs_read_buffer_len(const SaFsReadBuffer *buffer);
int32_t sa_fs_read_buffer_free(SaFsReadBuffer *buffer);

int32_t sa_std_net_tcp_connect(const uint8_t *host, uint64_t host_len, uint32_t port, uint64_t *out_handle);
int32_t sa_std_net_tcp_listen(const uint8_t *host, uint64_t host_len, uint32_t port, uint64_t *out_handle, uint32_t *out_bound_port);
int32_t sa_std_net_tcp_accept(uint64_t listener_handle, uint64_t *out_handle);

uint8_t *sa_net_addr_host(const SaNetAddr *addr);
uint64_t sa_net_addr_host_len(const SaNetAddr *addr);
uint16_t sa_net_addr_port(const SaNetAddr *addr);
uint32_t sa_net_addr_family(const SaNetAddr *addr);
int32_t sa_net_addr_free(SaNetAddr *addr);

int32_t sa_std_process_run(const SaProcessArgv *argv, uint64_t argv_len, uint64_t *out_handle);
int32_t sa_std_process_spawn(const SaProcessArgv *argv, uint64_t argv_len, uint64_t *out_handle);
int32_t sa_std_process_wait(uint64_t handle, uint32_t *out_code);
int32_t sa_std_process_close(uint64_t handle);

uint8_t *sa_fmt_buffer_data(uint64_t buffer);
uint64_t sa_fmt_buffer_len(uint64_t buffer);
int32_t sa_fmt_buffer_write_to(uint64_t buffer, uint64_t writer);
int32_t sa_fmt_buffer_free(uint64_t buffer);
uint64_t sa_fmt_i64(int64_t value, uint32_t base);
uint64_t sa_fmt_u64(uint64_t value, uint32_t base);
uint64_t sa_fmt_f64(double value, uint32_t precision);
uint64_t sa_fmt_bool(uint8_t value);
uint64_t sa_fmt_bytes(const uint8_t *buf, uint64_t len);

#ifdef __cplusplus
}
#endif

#endif
