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

#define SA_JSON_KIND_INVALID 4294967295u
#define SA_JSON_KIND_NULL 0u
#define SA_JSON_KIND_BOOL 1u
#define SA_JSON_KIND_INTEGER 2u
#define SA_JSON_KIND_FLOAT 3u
#define SA_JSON_KIND_NUMBER_STRING 4u
#define SA_JSON_KIND_STRING 5u
#define SA_JSON_KIND_ARRAY 6u
#define SA_JSON_KIND_OBJECT 7u

#define SA_JSON_TOKEN_INVALID 4294967295u
#define SA_JSON_TOKEN_OBJECT_BEGIN 0u
#define SA_JSON_TOKEN_OBJECT_END 1u
#define SA_JSON_TOKEN_ARRAY_BEGIN 2u
#define SA_JSON_TOKEN_ARRAY_END 3u
#define SA_JSON_TOKEN_TRUE 4u
#define SA_JSON_TOKEN_FALSE 5u
#define SA_JSON_TOKEN_NULL 6u
#define SA_JSON_TOKEN_NUMBER 7u
#define SA_JSON_TOKEN_PARTIAL_NUMBER 8u
#define SA_JSON_TOKEN_STRING 9u
#define SA_JSON_TOKEN_PARTIAL_STRING 10u
#define SA_JSON_TOKEN_PARTIAL_STRING_ESCAPED_1 11u
#define SA_JSON_TOKEN_PARTIAL_STRING_ESCAPED_2 12u
#define SA_JSON_TOKEN_PARTIAL_STRING_ESCAPED_3 13u
#define SA_JSON_TOKEN_PARTIAL_STRING_ESCAPED_4 14u
#define SA_JSON_TOKEN_END_OF_DOCUMENT 15u
#define SA_JSON_TOKEN_ALLOCATED_NUMBER 16u
#define SA_JSON_TOKEN_ALLOCATED_STRING 17u

#define SA_JSON_WHITESPACE_MINIFIED 0u
#define SA_JSON_WHITESPACE_INDENT_1 1u
#define SA_JSON_WHITESPACE_INDENT_2 2u
#define SA_JSON_WHITESPACE_INDENT_3 3u
#define SA_JSON_WHITESPACE_INDENT_4 4u
#define SA_JSON_WHITESPACE_INDENT_8 5u
#define SA_JSON_WHITESPACE_INDENT_TAB 6u

typedef struct SaJsonToken {
    uint32_t kind;
    const uint8_t *text_ptr;
    uint64_t text_len;
} SaJsonToken;

typedef struct SaJsonStringifyOptions {
    uint32_t whitespace;
    uint8_t emit_null_optional_fields;
    uint8_t emit_strings_as_arrays;
    uint8_t escape_unicode;
    uint8_t emit_nonportable_numbers_as_strings;
} SaJsonStringifyOptions;

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

typedef struct SaTermWinsize {
    uint16_t row;
    uint16_t col;
    uint16_t xpixel;
    uint16_t ypixel;
} SaTermWinsize;

typedef struct SaTermEpollEvent {
    uint32_t events;
    uint64_t data;
} SaTermEpollEvent;

typedef struct SaTimeDate {
    int64_t unix_ms;
    int64_t unix_ns;
    uint16_t year;
    uint8_t month;
    uint8_t day;
    uint8_t hour;
    uint8_t minute;
    uint8_t second;
    uint16_t millisecond;
} SaTimeDate;

typedef struct sa_std_fallible_u64 {
    int32_t status;
    uint64_t value;
} sa_std_fallible_u64;

typedef struct sa_std_fallible_i32 {
    int32_t status;
    int32_t value;
} sa_std_fallible_i32;

uint32_t sa_std_version(void);
int32_t sa_std_last_error(void);
int32_t sa_std_error_name(int32_t code, uint8_t *out, uint64_t out_cap, uint64_t *out_len);

uint64_t sa_std_stdin(void);
uint64_t sa_std_stdout(void);
uint64_t sa_std_stderr(void);
uint64_t sa_io_stdin(void);
uint64_t sa_io_stdout(void);
uint64_t sa_io_stderr(void);

int32_t sa_std_print(const uint8_t *data, uint64_t len);
int32_t sa_std_println(const uint8_t *data, uint64_t len);

uint64_t sa_json_parse(const uint8_t *json_bytes, uint64_t len);
uint32_t sa_json_kind(uint64_t node);
int32_t sa_json_object_get(uint64_t node, const uint8_t *key, uint64_t key_len, uint64_t *out_handle);
int32_t sa_json_as_f64(uint64_t node, double *out_value);
int32_t sa_json_as_i64(uint64_t node, int64_t *out_value);
int32_t sa_json_as_bool(uint64_t node, uint8_t *out_value);
const uint8_t *sa_json_string_ptr(uint64_t node);
uint64_t sa_json_string_len(uint64_t node);
int32_t sa_json_value_count(uint64_t node, uint64_t *out_count);
int32_t sa_json_free(uint64_t node);
int32_t sa_json_stringify(uint64_t node, uint64_t *out_handle);
uint8_t *sa_json_buffer_data(uint64_t buffer);
uint64_t sa_json_buffer_len(uint64_t buffer);
int32_t sa_json_buffer_free(uint64_t buffer);
int32_t sa_json_scanner_new(uint64_t *out_handle);
int32_t sa_json_scanner_feed(uint64_t scanner, const uint8_t *input, uint64_t len);
int32_t sa_json_scanner_end_input(uint64_t scanner);
int32_t sa_json_scanner_next(uint64_t scanner, SaJsonToken *out_token);
int32_t sa_json_scanner_free(uint64_t scanner);
uint64_t sa_json_stream_new(const uint8_t *json_bytes, uint64_t len);
uint32_t sa_json_stream_next(uint64_t stream);
const uint8_t *sa_json_stream_get_slice_ptr(uint64_t stream);
uint64_t sa_json_stream_get_slice_len(uint64_t stream);
int32_t sa_json_stream_free(uint64_t stream);
int32_t sa_json_writer_new(uint32_t whitespace, uint8_t emit_null_optional_fields, uint8_t emit_strings_as_arrays, uint8_t escape_unicode, uint8_t emit_nonportable_numbers_as_strings, uint64_t *out_handle);
int32_t sa_json_writer_begin_object(uint64_t writer);
int32_t sa_json_writer_end_object(uint64_t writer);
int32_t sa_json_writer_begin_array(uint64_t writer);
int32_t sa_json_writer_end_array(uint64_t writer);
int32_t sa_json_writer_object_field(uint64_t writer, const uint8_t *key, uint64_t key_len);
int32_t sa_json_writer_write_bool(uint64_t writer, uint8_t value);
int32_t sa_json_writer_write_i64(uint64_t writer, int64_t value);
int32_t sa_json_writer_write_f64(uint64_t writer, double value);
int32_t sa_json_writer_write_string(uint64_t writer, const uint8_t *data, uint64_t len);
int32_t sa_json_writer_write_null(uint64_t writer);
int32_t sa_json_writer_finish(uint64_t writer, uint64_t *out_handle);
int32_t sa_json_writer_free(uint64_t writer);

#define SA_REGEX_EXTENDED 1
#define SA_REGEX_ICASE 2
#define SA_REGEX_NEWLINE 4
#define SA_REGEX_NOSUB 8
#define SA_REGEX_NOTBOL 1
#define SA_REGEX_NOTEOL 2
#define SA_REGEX_REG_NOERROR 0
#define SA_REGEX_REG_OK SA_REGEX_REG_NOERROR
#define SA_REGEX_REG_NOMATCH 1
#define SA_REGEX_REG_BADPAT 2
#define SA_REGEX_REG_ECOLLATE 3
#define SA_REGEX_REG_ECTYPE 4
#define SA_REGEX_REG_EESCAPE 5
#define SA_REGEX_REG_ESUBREG 6
#define SA_REGEX_REG_EBRACK 7
#define SA_REGEX_REG_EPAREN 8
#define SA_REGEX_REG_EBRACE 9
#define SA_REGEX_REG_BADBR 10
#define SA_REGEX_REG_ERANGE 11
#define SA_REGEX_REG_ESPACE 12
#define SA_REGEX_REG_BADRPT 13
#define SA_REGEX_REG_ENOSYS -1

typedef struct SaRegexGroup {
    const uint8_t *ptr;
    uint64_t len;
} SaRegexGroup;

typedef struct SaRegexMatch {
    uint32_t matched;
    uint32_t group_count;
    SaRegexGroup *groups;
} SaRegexMatch;

uint64_t sa_regex_compile(const uint8_t *pattern, uint64_t pattern_len, int32_t cflags);
uint64_t sa_regex_match(uint64_t regex, const uint8_t *text, uint64_t text_len);
const uint8_t *sa_regex_group_ptr(uint64_t match, uint32_t group_idx);
uint64_t sa_regex_group_len(uint64_t match, uint32_t group_idx);
uint64_t sa_regex_group_count(uint64_t regex);
int32_t sa_regex_free(uint64_t regex);
int32_t sa_regex_match_free(uint64_t match);

int32_t sa_std_write(uint64_t handle, const uint8_t *data, uint64_t len, uint64_t *out_written);
int32_t sa_std_read(uint64_t handle, uint8_t *out, uint64_t out_cap, uint64_t *out_read);
int32_t sa_std_close(uint64_t handle);
int32_t sa_io_read_line(uint64_t handle, uint64_t max_bytes, uint64_t *out_handle);
int32_t sa_io_read(uint64_t handle, uint8_t *out, uint64_t out_cap, uint64_t *out_read);
int32_t sa_io_read_exact(uint64_t handle, uint8_t *out, uint64_t len);
int32_t sa_io_write(uint64_t handle, const uint8_t *data, uint64_t len, uint64_t *out_written);
int32_t sa_io_write_all(uint64_t handle, const uint8_t *data, uint64_t len);
int32_t sa_io_flush(uint64_t handle);
int32_t sa_io_close(uint64_t handle);

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
int32_t sa_net_tcp_stream_peek(uint64_t stream_handle, uint8_t *out, uint64_t cap);
int32_t sa_std_net_tcp_stream_set_read_timeout(uint64_t stream_handle, uint64_t timeout_ns);
int32_t sa_std_net_tcp_stream_set_write_timeout(uint64_t stream_handle, uint64_t timeout_ns);
int32_t sa_std_net_tcp_stream_set_nonblocking(uint64_t stream_handle, int32_t enabled);
int32_t sa_std_net_tcp_stream_set_nodelay(uint64_t stream_handle, int32_t enabled);
int32_t sa_std_net_tcp_stream_set_ttl(uint64_t stream_handle, uint32_t ttl);
int32_t sa_net_tcp_stream_set_read_timeout(uint64_t stream_handle, uint64_t timeout_ns);
int32_t sa_net_tcp_stream_set_write_timeout(uint64_t stream_handle, uint64_t timeout_ns);
int32_t sa_net_tcp_stream_set_nonblocking(uint64_t stream_handle, int32_t enabled);
int32_t sa_net_tcp_stream_set_nodelay(uint64_t stream_handle, int32_t enabled);
int32_t sa_net_tcp_stream_set_ttl(uint64_t stream_handle, uint32_t ttl);

int32_t sa_std_net_udp_bind(const uint8_t *host, uint64_t host_len, uint32_t port, uint64_t *out_handle);
int32_t sa_std_net_udp_local_addr(uint64_t socket_handle, uint64_t *out_handle);
int32_t sa_std_net_udp_connect(uint64_t socket_handle, const uint8_t *host, uint64_t host_len, uint32_t port);
int32_t sa_std_net_udp_set_read_timeout(uint64_t socket_handle, uint64_t timeout_ns);
int32_t sa_std_net_udp_set_write_timeout(uint64_t socket_handle, uint64_t timeout_ns);
int32_t sa_std_net_udp_set_nonblocking(uint64_t socket_handle, int32_t enabled);
int32_t sa_std_net_udp_set_broadcast(uint64_t socket_handle, int32_t enabled);
int32_t sa_std_net_udp_set_ttl(uint64_t socket_handle, uint32_t ttl);
int32_t sa_std_net_udp_send(uint64_t socket_handle, const uint8_t *buf, uint64_t len, uint64_t *out_written);
int32_t sa_std_net_udp_recv(uint64_t socket_handle, uint8_t *out, uint64_t cap, uint64_t *out_read);
int32_t sa_std_net_udp_send_to(uint64_t socket_handle, const uint8_t *buf, uint64_t len, const uint8_t *host, uint64_t host_len, uint32_t port, uint64_t *out_written);
int32_t sa_std_net_udp_recv_from(uint64_t socket_handle, uint8_t *out, uint64_t cap, uint64_t *out_read, uint64_t *out_addr_handle);
int32_t sa_net_udp_connect(uint64_t socket_handle, const uint8_t *host, uint64_t host_len, uint16_t port);
int32_t sa_net_udp_set_read_timeout(uint64_t socket_handle, uint64_t timeout_ns);
int32_t sa_net_udp_set_write_timeout(uint64_t socket_handle, uint64_t timeout_ns);
int32_t sa_net_udp_set_nonblocking(uint64_t socket_handle, int32_t enabled);
int32_t sa_net_udp_set_broadcast(uint64_t socket_handle, int32_t enabled);
int32_t sa_net_udp_set_ttl(uint64_t socket_handle, uint32_t ttl);
int32_t sa_net_udp_send(uint64_t socket_handle, const uint8_t *buf, uint64_t len);
int32_t sa_net_udp_recv(uint64_t socket_handle, uint8_t *out, uint64_t cap);
int32_t sa_net_udp_close(uint64_t socket_handle);

uint8_t *sa_net_addr_host(uint64_t addr_handle);
uint64_t sa_net_addr_host_len(uint64_t addr_handle);
uint16_t sa_net_addr_port(uint64_t addr_handle);
uint32_t sa_net_addr_family(uint64_t addr_handle);
int32_t sa_net_addr_free(uint64_t addr_handle);

int32_t sa_std_process_run(const SaProcessArgv *argv, uint64_t argv_len, uint64_t *out_handle);
int32_t sa_std_process_spawn(const SaProcessArgv *argv, uint64_t argv_len, uint64_t *out_handle);
int32_t sa_std_process_spawn_stream(const SaProcessArgv *argv, uint64_t argv_len, uint64_t *out_process, uint64_t *out_stdout, uint64_t *out_stderr);
int32_t sa_std_process_wait(uint64_t handle, uint32_t *out_code);
int32_t sa_std_process_close(uint64_t handle);

int32_t sa_term_raw_enter(uint64_t handle, uint64_t *out_session);
int32_t sa_term_raw_leave(uint64_t session);
int32_t sa_term_winsize(uint64_t handle, SaTermWinsize *out_size);
int32_t sa_term_epoll_create(uint32_t flags, uint64_t *out_handle);
int32_t sa_term_epoll_ctl(uint64_t epoll_handle, uint32_t op, uint64_t target_handle, uint32_t events, uint64_t data);
int32_t sa_term_epoll_wait(uint64_t epoll_handle, SaTermEpollEvent *out_events, uint64_t max_events, int32_t timeout_ms, uint64_t *out_count);
int32_t sa_term_epoll_close(uint64_t handle);

uint64_t sa_time_instant_ns(void);
int64_t sa_time_unix_s(void);
int64_t sa_time_unix_ms(void);
int64_t sa_time_unix_ns(void);
int32_t sa_time_utc_now(SaTimeDate *out_date);
int32_t sa_time_sleep_ns(uint64_t ns);
int32_t sa_time_sleep_ms(uint64_t ms);

uint8_t *sa_fmt_buffer_data(uint64_t buffer);
uint64_t sa_fmt_buffer_len(uint64_t buffer);
int32_t sa_fmt_buffer_write_to(uint64_t buffer, uint64_t writer);
int32_t sa_fmt_buffer_free(uint64_t buffer);
uint64_t sa_string_concat(const uint8_t *left, uint64_t left_len, const uint8_t *right, uint64_t right_len);
uint64_t sa_env_get(const uint8_t *key, uint64_t key_len);
int32_t sa_env_has(const uint8_t *key, uint64_t key_len);
uint8_t *sa_env_buffer_data(uint64_t buffer);
uint64_t sa_env_buffer_len(uint64_t buffer);
int32_t sa_env_buffer_free(uint64_t buffer);
uint64_t sa_fmt_i64(int64_t value, uint32_t base);
uint64_t sa_fmt_u64(uint64_t value, uint32_t base);
uint64_t sa_fmt_f64(double value, uint32_t precision);
uint64_t sa_fmt_bool(uint8_t value);
uint64_t sa_fmt_bytes(const uint8_t *buf, uint64_t len);
int32_t sa_fmt_i64_into(int64_t value, uint32_t base, uint8_t *out, uint64_t out_cap, uint64_t *out_len);
int32_t sa_fmt_u64_into(uint64_t value, uint32_t base, uint8_t *out, uint64_t out_cap, uint64_t *out_len);
int32_t sa_fmt_f64_into(double value, uint32_t precision, uint8_t *out, uint64_t out_cap, uint64_t *out_len);
int32_t sa_fmt_bool_into(uint8_t value, uint8_t *out, uint64_t out_cap, uint64_t *out_len);
int32_t sa_fmt_bytes_into(const uint8_t *buf, uint64_t len, uint8_t *out, uint64_t out_cap, uint64_t *out_len);

#ifdef __cplusplus
}
#endif

#endif
