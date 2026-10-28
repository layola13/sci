#ifndef SA_STD_H
#define SA_STD_H

#include <stddef.h>
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
/* 10 is SA_STD_ERR_PERMISSION_DENIED (runtime policy; Zig-side define). */
#define SA_STD_ERR_ALREADY_EXISTS 11
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
int64_t sa_num_add_checked(int64_t a, int64_t b);
int64_t sa_num_sub_checked(int64_t a, int64_t b);
int64_t sa_num_mul_checked(int64_t a, int64_t b);
int32_t sa_std_last_error(void);
typedef struct sa_net_iov {
    uint8_t *base;
    size_t len;
} sa_net_iov;

int32_t sa_std_net_error_code_from_status(int32_t status);
int32_t sa_std_net_error_code_from_posix_errno(int32_t error);
int32_t sa_std_net_error_code_from_wsa_error(int32_t error);
int32_t sa_std_net_error_code_name(int32_t code, uint8_t *out, uint64_t out_cap, uint64_t *out_len);
int32_t sa_std_net_error_platform(void);
int32_t sa_std_net_error_code_from_native_error(int32_t error);
sa_std_fallible_i32 sa_test_fallible_i32_value(int32_t value);
int32_t sa_std_error_name(int32_t code, uint8_t *out, uint64_t out_cap, uint64_t *out_len);

int32_t sa_dl_open(const uint8_t *path, uint64_t path_len, uint64_t *out_handle);
int32_t sa_dl_sym(uint64_t handle, const uint8_t *symbol, uint64_t symbol_len, void **out_ptr);
int32_t sa_dl_close(uint64_t handle);
const uint8_t *sa_dl_error(void);

uint64_t sa_std_stdin(void);
uint64_t sa_std_stdout(void);
uint64_t sa_std_stderr(void);
uint64_t sa_io_stdin(void);
uint64_t sa_io_stdout(void);
uint64_t sa_io_stderr(void);

int32_t sa_std_fd_as_raw(uint64_t handle, int32_t *out_fd);
int32_t sa_std_fd_dup(uint64_t handle, uint64_t *out_handle);
int32_t sa_std_fd_dup_raw(int32_t fd, uint64_t *out_handle);
int32_t sa_std_fd_from_raw(int32_t fd, uint64_t *out_handle);
int32_t sa_std_fd_into_raw(uint64_t handle, int32_t *out_fd);
int32_t sa_std_fd_close_raw(int32_t fd);
int32_t sa_std_fd_is_terminal(uint64_t handle, uint8_t *out_flag);

int32_t sa_std_print(const uint8_t *data, uint64_t len);
int32_t sa_std_println(const uint8_t *data, uint64_t len);

uint64_t sa_deno_cwd(void);
int32_t sa_deno_chdir(const uint8_t *path, uint64_t path_len);
int32_t sa_deno_env_set(const uint8_t *key, uint64_t key_len, const uint8_t *value, uint64_t value_len);
int32_t sa_deno_env_delete(const uint8_t *key, uint64_t key_len);
uint64_t sa_deno_random_uuid(void);
int32_t sa_hmac_sha256_hex(const uint8_t *key, uint64_t key_len, const uint8_t *msg, uint64_t msg_len, uint8_t *out, uint64_t out_cap, uint64_t *out_len);
int32_t sa_hmac_sha1_hex(const uint8_t *key, uint64_t key_len, const uint8_t *msg, uint64_t msg_len, uint8_t *out, uint64_t out_cap, uint64_t *out_len);
int32_t sa_crypto_random_bytes(uint8_t *out, uint64_t len);
uint64_t sa_deno_args_json(void);
uint64_t sa_deno_btoa(const uint8_t *data, uint64_t len);
uint64_t sa_deno_atob(const uint8_t *data_base64, uint64_t data_base64_len);
uint64_t sa_b64dec_simd(const uint8_t *data_base64, uint64_t b64_len, uint8_t *out);
uint64_t sa_mfind_u8(const uint8_t *hay, uint64_t hay_len, const uint8_t *ndl, uint64_t ndl_len);
uint64_t sa_hexdec_simd(const uint8_t *data_hex, uint64_t hex_len, uint8_t *out);
uint64_t sa_deno_text_encode(const uint8_t *data, uint64_t len);
uint64_t sa_deno_text_decode(const uint8_t *data, uint64_t len);
uint64_t sa_deno_chat_sse_to_responses(const uint8_t *chat_body, uint64_t chat_body_len, const uint8_t *req_body, uint64_t req_body_len);
uint64_t sa_deno_chat_json_to_responses(const uint8_t *chat_body, uint64_t chat_body_len, const uint8_t *req_body, uint64_t req_body_len);
uint64_t sa_deno_responses_sse_normalize(const uint8_t *sse_body, uint64_t sse_body_len);
uint64_t sa_deno_responses_json_normalize(const uint8_t *body, uint64_t body_len);
uint64_t sa_deno_responses_request_normalize(const uint8_t *body, uint64_t body_len);
uint64_t sa_deno_responses_chat_fallback_request(const uint8_t *body, uint64_t body_len, const uint8_t *default_model, uint64_t default_model_len, uint8_t plan_mode_like);
uint64_t sa_deno_jsonrpc_params_string_literal(const uint8_t *body, uint64_t body_len, const uint8_t *key, uint64_t key_len, const uint8_t *fallback, uint64_t fallback_len, uint8_t emit_null_if_missing);
uint64_t sa_deno_version_json(void);
uint64_t sa_deno_build_json(void);
uint64_t sa_deno_version_deno(void);
uint64_t sa_deno_build_os(void);
uint64_t sa_deno_build_platform_family(void);
uint64_t sa_deno_date_now_iso(void);

uint32_t sa_http_client_resp_body_slice(void *resp, const uint8_t **out_body_ptr, uint64_t *out_body_len);

uint64_t sa_json_parse(const uint8_t *json_bytes, uint64_t len);
uint32_t sa_json_kind(uint64_t node);
int32_t sa_json_object_get(uint64_t node, const uint8_t *key, uint64_t key_len, uint64_t *out_handle);
int32_t sa_json_array_get(uint64_t node, uint64_t index, uint64_t *out_handle);
int32_t sa_json_object_key_at(uint64_t node, uint64_t index, const uint8_t **out_ptr, uint64_t *out_len);
int32_t sa_json_object_get_string(uint64_t node, const uint8_t *key, uint64_t key_len, const uint8_t **out_ptr, uint64_t *out_len);
int32_t sa_json_object_get_bool(uint64_t node, const uint8_t *key, uint64_t key_len, uint8_t *out_value);
int32_t sa_json_object_get_i64(uint64_t node, const uint8_t *key, uint64_t key_len, int64_t *out_value);
int32_t sa_json_object_get_f64(uint64_t node, const uint8_t *key, uint64_t key_len, double *out_value);
int32_t sa_json_as_f64(uint64_t node, double *out_value);
int32_t sa_json_as_i64(uint64_t node, int64_t *out_value);
int32_t sa_json_as_bool(uint64_t node, uint8_t *out_value);
const uint8_t *sa_json_string_ptr(uint64_t node);
uint64_t sa_json_string_len(uint64_t node);
int32_t sa_json_value_count(uint64_t node, uint64_t *out_count);
int32_t sa_json_object_set_string(uint64_t node, const uint8_t *key, uint64_t key_len, const uint8_t *data, uint64_t len);
int32_t sa_json_object_set_i64(uint64_t node, const uint8_t *key, uint64_t key_len, int64_t value);
int32_t sa_json_object_set_f64(uint64_t node, const uint8_t *key, uint64_t key_len, double value);
int32_t sa_json_object_set_bool(uint64_t node, const uint8_t *key, uint64_t key_len, uint8_t value);
int32_t sa_json_object_set_null(uint64_t node, const uint8_t *key, uint64_t key_len);
int32_t sa_json_object_set_node(uint64_t node, const uint8_t *key, uint64_t key_len, uint64_t child);
int32_t sa_json_object_remove(uint64_t node, const uint8_t *key, uint64_t key_len);
int32_t sa_json_array_push_string(uint64_t node, const uint8_t *data, uint64_t len);
int32_t sa_json_array_push_i64(uint64_t node, int64_t value);
int32_t sa_json_array_push_f64(uint64_t node, double value);
int32_t sa_json_array_push_bool(uint64_t node, uint8_t value);
int32_t sa_json_array_push_null(uint64_t node);
int32_t sa_json_array_push_node(uint64_t node, uint64_t child);

/* Global cells (2026-10-26): process-wide named state, the Rust-style
 * replacement for mutable globals. Statuses: NOT_FOUND (3) on unset
 * names; bytes_get reports TRUNCATED (9) with the required length in
 * out_len when the buffer is too small. */
int32_t sa_global_u64_set(const uint8_t *name, uint64_t name_len, uint64_t value);
int32_t sa_global_u64_get(const uint8_t *name, uint64_t name_len, uint64_t *out);
int32_t sa_global_u64_set_once(const uint8_t *name, uint64_t name_len, uint64_t value, uint64_t *out_already);
int32_t sa_global_u64_add(const uint8_t *name, uint64_t name_len, int64_t delta, uint64_t *out);
int32_t sa_global_bytes_set(const uint8_t *name, uint64_t name_len, const uint8_t *value, uint64_t value_len);
int32_t sa_global_bytes_get(const uint8_t *name, uint64_t name_len, uint8_t *buf, uint64_t cap, uint64_t *out_len);
int32_t sa_idmap_new(uint64_t *out_handle);
int32_t sa_idmap_free(uint64_t handle);
int32_t sa_idmap_set(uint64_t handle, uint64_t key, const uint8_t *value, uint64_t value_len);
int32_t sa_idmap_get(uint64_t handle, uint64_t key, uint8_t *buf, uint64_t cap, uint64_t *out_len);
int32_t sa_idmap_set_u64(uint64_t handle, uint64_t key, uint64_t value);
int32_t sa_idmap_get_u64(uint64_t handle, uint64_t key, uint64_t *out);
int32_t sa_idmap_has(uint64_t handle, uint64_t key, uint64_t *out);
int32_t sa_idmap_remove(uint64_t handle, uint64_t key);
int32_t sa_idmap_len(uint64_t handle, uint64_t *out);
int32_t sa_idmap_clear(uint64_t handle);
int32_t sa_idset_new(uint64_t *out_handle);
int32_t sa_idset_free(uint64_t handle);
int32_t sa_idset_add(uint64_t handle, uint64_t key);
int32_t sa_idset_has(uint64_t handle, uint64_t key, uint64_t *out);
int32_t sa_idset_remove(uint64_t handle, uint64_t key);
int32_t sa_idset_len(uint64_t handle, uint64_t *out);
int32_t sa_idset_clear(uint64_t handle);
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
int32_t sa_json_writer_field_string(uint64_t writer, const uint8_t *key, uint64_t key_len, const uint8_t *data, uint64_t len);
int32_t sa_json_writer_field_bool(uint64_t writer, const uint8_t *key, uint64_t key_len, uint8_t value);
int32_t sa_json_writer_field_i64(uint64_t writer, const uint8_t *key, uint64_t key_len, int64_t value);
int32_t sa_json_writer_field_f64(uint64_t writer, const uint8_t *key, uint64_t key_len, double value);
int32_t sa_json_writer_field_null(uint64_t writer, const uint8_t *key, uint64_t key_len);
int32_t sa_json_writer_field_node(uint64_t writer, const uint8_t *key, uint64_t key_len, uint64_t node);
int32_t sa_json_writer_write_bool(uint64_t writer, uint8_t value);
int32_t sa_json_writer_write_i64(uint64_t writer, int64_t value);
int32_t sa_json_writer_write_f64(uint64_t writer, double value);
int32_t sa_json_writer_write_string(uint64_t writer, const uint8_t *data, uint64_t len);
int32_t sa_json_writer_write_null(uint64_t writer);
int32_t sa_json_writer_write_node(uint64_t writer, uint64_t node);
int32_t sa_json_writer_finish(uint64_t writer, uint64_t *out_handle);
uint64_t sa_json_writer_finish_buffer(uint64_t writer);
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
uint64_t sa_regex_group_start(uint64_t match, uint32_t group_idx);
uint64_t sa_regex_group_count(uint64_t regex);
int32_t sa_regex_free(uint64_t regex);
int32_t sa_regex_match_free(uint64_t match);
uint64_t sa_regex_match_all(uint64_t regex, const uint8_t *text, uint64_t text_len);
uint64_t sa_regex_match_list_count(uint64_t list);
uint64_t sa_regex_match_list_at(uint64_t list, uint64_t index);
int32_t sa_regex_match_list_free(uint64_t list);
uint64_t sa_regex_replace(uint64_t regex, const uint8_t *text, uint64_t text_len, const uint8_t *replacement, uint64_t replacement_len);
uint64_t sa_regex_replace_all(uint64_t regex, const uint8_t *text, uint64_t text_len, const uint8_t *replacement, uint64_t replacement_len);
const uint8_t *sa_regex_buffer_data(uint64_t buffer);
uint64_t sa_regex_buffer_len(uint64_t buffer);
int32_t sa_regex_buffer_free(uint64_t buffer);
uint64_t sa_regex_split(uint64_t regex, const uint8_t *text, uint64_t text_len, uint64_t limit);
uint64_t sa_regex_split_count(uint64_t list);
const uint8_t *sa_regex_split_ptr(uint64_t list, uint64_t index);
uint64_t sa_regex_split_len(uint64_t list, uint64_t index);
int32_t sa_regex_split_free(uint64_t list);

int32_t sa_std_write(uint64_t handle, const uint8_t *data, uint64_t len, uint64_t *out_written);
int32_t sa_std_read(uint64_t handle, uint8_t *out, uint64_t out_cap, uint64_t *out_read);
int32_t sa_std_close(uint64_t handle);
void sa_print_bytes(const uint8_t *data, uint64_t len);
int32_t sa_fs_file_sync_data(uint64_t handle);
int32_t sa_fs_file_sync(uint64_t handle);
int32_t sa_fs_file_truncate(uint64_t handle, uint64_t new_size);
int32_t sa_std_fs_file_from_raw_fd(int32_t fd, uint64_t *out_handle);
int32_t sa_std_fs_file_read(uint64_t handle, uint8_t *out, uint64_t out_cap, uint64_t *out_read);
int32_t sa_std_fs_file_read_at(uint64_t handle, uint8_t *out, uint64_t out_cap, uint64_t offset, uint64_t *out_read);
int32_t sa_std_fs_file_read_exact_at(uint64_t handle, uint8_t *out, uint64_t len, uint64_t offset);
int32_t sa_std_fs_file_write(uint64_t handle, const uint8_t *data, uint64_t len, uint64_t *out_written);
int32_t sa_std_fs_file_write_at(uint64_t handle, const uint8_t *data, uint64_t len, uint64_t offset, uint64_t *out_written);
int32_t sa_std_fs_file_write_all_at(uint64_t handle, const uint8_t *data, uint64_t len, uint64_t offset);
int32_t sa_std_fs_file_seek(uint64_t handle, uint32_t whence, int64_t offset, uint64_t *out_pos);
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
int32_t sa_std_fs_open_options(const uint8_t *path, uint64_t path_len, uint32_t flags, uint32_t create_mode, uint32_t custom_flags, uint64_t *out_handle);
int32_t sa_std_fs_open_create_excl(const uint8_t *path, uint64_t path_len, uint64_t *out_handle);
int32_t sa_std_fs_remove(const uint8_t *path, uint64_t path_len);
int32_t sa_std_fs_exists(const uint8_t *path, uint64_t path_len);
int32_t sa_std_fs_try_exists(const uint8_t *path, uint64_t path_len, uint8_t *out_exists);
int32_t sa_std_fs_len(const uint8_t *path, uint64_t path_len, uint64_t *out_len);
int32_t sa_std_fs_read_file(const uint8_t *path, uint64_t path_len, uint64_t max_bytes, uint64_t *out_handle);
int32_t sa_std_fs_read_to_string(const uint8_t *path, uint64_t path_len, uint64_t max_bytes, uint64_t *out_handle);
int32_t sa_std_fs_read_file_base64(const uint8_t *path, uint64_t path_len, uint64_t max_bytes, uint64_t *out_handle);
int32_t sa_std_fs_read_dir_json(const uint8_t *path, uint64_t path_len, uint64_t max_entries, uint64_t *out_handle);
int32_t sa_std_fs_read_dir_entries(const uint8_t *path, uint64_t path_len, uint64_t max_entries, uint64_t *out_handle);
int32_t sa_std_fs_dir_entries_get(uint64_t handle, uint64_t index, uint64_t *out_entry_handle);
int32_t sa_std_fs_metadata(const uint8_t *path, uint64_t path_len, uint64_t *out_handle);
int32_t sa_std_fs_metadata_json(const uint8_t *path, uint64_t path_len, uint64_t *out_handle);
int32_t sa_std_fs_metadata_free(uint64_t handle);
int32_t sa_std_fs_canonicalize(const uint8_t *path, uint64_t path_len, uint64_t *out_handle);

sa_std_fallible_u64 sa_fs_read_file(const uint8_t *path, uint64_t path_len, uint64_t max_bytes);
sa_std_fallible_u64 sa_fs_read_to_string(const uint8_t *path, uint64_t path_len, uint64_t max_bytes);
int32_t sa_fs_write_file(const uint8_t *path, uint64_t path_len, const uint8_t *buf, uint64_t len);
uint8_t *sa_fs_read_buffer_data(uint64_t handle);
uint64_t sa_fs_read_buffer_len(uint64_t handle);
int32_t sa_fs_read_buffer_free(uint64_t handle);
sa_std_fallible_u64 sa_fs_read_file_base64(const uint8_t *path, uint64_t path_len, uint64_t max_bytes);
int32_t sa_fs_write_file_base64(const uint8_t *path, uint64_t path_len, const uint8_t *data_base64, uint64_t data_base64_len);
sa_std_fallible_u64 sa_fs_read_dir_json(const uint8_t *path, uint64_t path_len, uint64_t max_entries);
uint8_t *sa_fs_dir_buffer_data(uint64_t handle);
uint64_t sa_fs_dir_buffer_len(uint64_t handle);
int32_t sa_fs_dir_buffer_free(uint64_t handle);
sa_std_fallible_u64 sa_fs_read_dir_entries(const uint8_t *path, uint64_t path_len, uint64_t max_entries);
uint64_t sa_fs_dir_entries_len(uint64_t handle);
int32_t sa_fs_dir_entries_free(uint64_t handle);
uint8_t *sa_fs_dir_entry_name_ptr(uint64_t handle);
uint64_t sa_fs_dir_entry_name_len(uint64_t handle);
uint8_t *sa_fs_dir_entry_file_name_ptr(uint64_t handle);
uint64_t sa_fs_dir_entry_file_name_len(uint64_t handle);
uint32_t sa_fs_dir_entry_kind(uint64_t handle);
uint64_t sa_fs_dir_entry_ino(uint64_t handle);
int32_t sa_fs_dir_entry_free(uint64_t handle);
sa_std_fallible_u64 sa_fs_metadata(const uint8_t *path, uint64_t path_len);
sa_std_fallible_u64 sa_fs_metadata_json(const uint8_t *path, uint64_t path_len);
uint8_t sa_fs_metadata_is_file(uint64_t handle);
uint8_t sa_fs_metadata_is_directory(uint64_t handle);
uint8_t sa_fs_metadata_is_symlink(uint64_t handle);
uint8_t sa_fs_metadata_is_block_device(uint64_t handle);
uint8_t sa_fs_metadata_is_char_device(uint64_t handle);
uint8_t sa_fs_metadata_is_fifo(uint64_t handle);
uint8_t sa_fs_metadata_is_socket(uint64_t handle);
int64_t sa_fs_metadata_modified_ms(uint64_t handle);
int64_t sa_fs_metadata_created_ms(uint64_t handle);
int64_t sa_fs_metadata_accessed_ms(uint64_t handle);
int64_t sa_fs_metadata_changed_ms(uint64_t handle);
uint64_t sa_fs_metadata_len(uint64_t handle);
uint32_t sa_fs_metadata_mode(uint64_t handle);
uint32_t sa_fs_metadata_uid(uint64_t handle);
uint32_t sa_fs_metadata_gid(uint64_t handle);
uint64_t sa_fs_metadata_ino(uint64_t handle);
uint64_t sa_fs_metadata_dev(uint64_t handle);
uint64_t sa_fs_metadata_nlink(uint64_t handle);
uint64_t sa_fs_metadata_rdev(uint64_t handle);
uint64_t sa_fs_metadata_blksize(uint64_t handle);
uint64_t sa_fs_metadata_blocks(uint64_t handle);
uint64_t sa_fs_metadata_st_dev(uint64_t handle);
uint64_t sa_fs_metadata_st_ino(uint64_t handle);
uint32_t sa_fs_metadata_st_mode(uint64_t handle);
uint64_t sa_fs_metadata_st_nlink(uint64_t handle);
uint32_t sa_fs_metadata_st_uid(uint64_t handle);
uint32_t sa_fs_metadata_st_gid(uint64_t handle);
uint64_t sa_fs_metadata_st_rdev(uint64_t handle);
uint64_t sa_fs_metadata_st_size(uint64_t handle);
int64_t sa_fs_metadata_st_atime(uint64_t handle);
int64_t sa_fs_metadata_st_atime_nsec(uint64_t handle);
int64_t sa_fs_metadata_st_mtime(uint64_t handle);
int64_t sa_fs_metadata_st_mtime_nsec(uint64_t handle);
int64_t sa_fs_metadata_st_ctime(uint64_t handle);
int64_t sa_fs_metadata_st_ctime_nsec(uint64_t handle);
uint64_t sa_fs_metadata_st_blksize(uint64_t handle);
uint64_t sa_fs_metadata_st_blocks(uint64_t handle);
sa_std_fallible_i32 sa_fs_metadata_free(uint64_t handle);
int32_t sa_fs_remove_file(const uint8_t *path, uint64_t path_len);
int32_t sa_fs_rename(const uint8_t *from_path, uint64_t from_len, const uint8_t *to_path, uint64_t to_len);
int32_t sa_fs_make_dir(const uint8_t *path, uint64_t path_len);
int32_t sa_fs_make_dir_mode(const uint8_t *path, uint64_t path_len, uint32_t mode);
int32_t sa_fs_mkdir_p(const uint8_t *path, uint64_t path_len);
int32_t sa_fs_create_dir(const uint8_t *path, uint64_t path_len);
int32_t sa_fs_create_dir_mode(const uint8_t *path, uint64_t path_len, uint32_t mode);
int32_t sa_fs_remove_dir(const uint8_t *path, uint64_t path_len);
int32_t sa_fs_remove_dir_all(const uint8_t *path, uint64_t path_len);
int32_t sa_fs_remove_path(const uint8_t *path, uint64_t path_len);
int32_t sa_fs_copy_file(const uint8_t *from_path, uint64_t from_len, const uint8_t *to_path, uint64_t to_len);
int32_t sa_fs_set_permissions(const uint8_t *path, uint64_t path_len, uint32_t mode);
int32_t sa_fs_set_times_ms(const uint8_t *path, uint64_t path_len, int64_t accessed_ms, int64_t modified_ms);
int32_t sa_fs_hard_link(const uint8_t *from_path, uint64_t from_len, const uint8_t *to_path, uint64_t to_len);
int32_t sa_fs_symlink(const uint8_t *target_path, uint64_t target_len, const uint8_t *link_path, uint64_t link_len);
int32_t sa_fs_chown(const uint8_t *path, uint64_t path_len, uint32_t uid, uint32_t gid, uint32_t has_uid, uint32_t has_gid);
int32_t sa_fs_lchown(const uint8_t *path, uint64_t path_len, uint32_t uid, uint32_t gid, uint32_t has_uid, uint32_t has_gid);
int32_t sa_fs_fchown(uint64_t handle, uint32_t uid, uint32_t gid, uint32_t has_uid, uint32_t has_gid);
int32_t sa_fs_chroot(const uint8_t *path, uint64_t path_len);
int32_t sa_fs_mkfifo(const uint8_t *path, uint64_t path_len, uint32_t mode);
int32_t sa_std_fs_read_link(const uint8_t *path, uint64_t path_len, uint64_t *out_handle);

int32_t sa_std_net_tcp_connect(const uint8_t *host, uint64_t host_len, uint32_t port, uint64_t *out_handle);
int32_t sa_std_net_hostname(uint8_t *out, uint64_t out_cap, uint64_t *out_len);
int32_t sa_std_net_tcp_connect_timeout(const uint8_t *host, uint64_t host_len, uint32_t port, uint64_t timeout_ns, uint64_t *out_handle);
int32_t sa_std_net_tcp_connect_timeout_addr(uint64_t addr_handle, uint64_t timeout_ns, uint64_t *out_handle);
int32_t sa_std_net_tcp_connect_timeout_all(const uint8_t *host, uint64_t host_len, uint32_t port, uint64_t timeout_ns, uint64_t *out_handle);
int32_t sa_std_net_to_socket_addr_first(const uint8_t *host, uint64_t host_len, uint32_t port, uint64_t *out_handle);
int32_t sa_std_net_to_socket_addr_list(const uint8_t *host, uint64_t host_len, uint32_t port, uint64_t *out_handle);
int32_t sa_std_net_addr_list_next(uint64_t list, int32_t *out_ok, uint64_t *out_addr);
int32_t sa_std_net_addr_list_remaining(uint64_t list, uint64_t *out_remaining);
int32_t sa_std_net_addr_list_reset(uint64_t list);
int32_t sa_std_net_addr_list_free(uint64_t list);
int32_t sa_std_net_tcp_listen(const uint8_t *host, uint64_t host_len, uint32_t port, uint64_t *out_handle, uint32_t *out_bound_port);
int32_t sa_std_net_tcp_accept(uint64_t listener_handle, uint64_t *out_handle);
int32_t sa_std_net_tcp_accept_addr(uint64_t listener_handle, uint64_t *out_stream, uint64_t *out_addr);
int32_t sa_std_net_tcp_listener_local_addr(uint64_t listener_handle, uint64_t *out_handle);
int32_t sa_std_net_tcp_stream_read(uint64_t stream_handle, uint8_t *out, uint64_t cap, uint64_t *out_read);
int32_t sa_std_net_tcp_stream_peek(uint64_t stream_handle, uint8_t *out, uint64_t cap, uint64_t *out_read);
int32_t sa_std_net_tcp_stream_write(uint64_t stream_handle, const uint8_t *buf, uint64_t len, uint64_t *out_written);
int32_t sa_std_net_raw_socket(uint32_t domain, uint32_t sock_type, uint32_t protocol, uint64_t *out_handle);
int32_t sa_std_net_tcp_stream_send_file(uint64_t stream, uint64_t file, uint64_t offset, uint64_t count, uint64_t *out_sent, uint64_t *out_next_offset);
int32_t sa_std_net_tcp_stream_read_vectored(uint64_t stream_handle, const sa_net_iov *iovs, uint64_t iov_count, uint64_t *out_read);
int32_t sa_std_net_tcp_stream_write_vectored(uint64_t stream_handle, const sa_net_iov *iovs, uint64_t iov_count, uint64_t *out_written);
int32_t sa_std_net_tcp_stream_peer_addr(uint64_t stream_handle, uint64_t *out_handle);
int32_t sa_std_net_tcp_stream_local_addr(uint64_t stream_handle, uint64_t *out_handle);
int32_t sa_net_tcp_stream_peek(uint64_t stream_handle, uint8_t *out, uint64_t cap);
sa_std_fallible_i32 sa_net_tcp_stream_read_exact(uint64_t stream_handle, uint8_t *out, uint64_t len);
int32_t sa_std_net_tcp_stream_set_read_timeout(uint64_t stream_handle, uint64_t timeout_ns);
int32_t sa_std_net_tcp_stream_set_write_timeout(uint64_t stream_handle, uint64_t timeout_ns);
int32_t sa_std_net_tcp_stream_set_nonblocking(uint64_t stream_handle, int32_t enabled);
int32_t sa_std_net_tcp_stream_set_linger(uint64_t stream_handle, int32_t enabled, uint64_t timeout_ns);
int32_t sa_std_net_tcp_stream_linger(uint64_t stream_handle, int32_t *out_enabled, uint64_t *out_timeout_ns);
int32_t sa_std_net_tcp_stream_set_nodelay(uint64_t stream_handle, int32_t enabled);
int32_t sa_std_net_tcp_stream_set_keepalive(uint64_t stream_handle, int32_t enabled);
int32_t sa_std_net_tcp_stream_keepalive(uint64_t stream_handle, int32_t *out_enabled);
int32_t sa_std_net_tcp_stream_set_keepalive_params(uint64_t stream_handle, uint32_t idle_secs, uint32_t interval_secs, uint32_t count);
int32_t sa_std_net_tcp_stream_set_quickack(uint64_t stream_handle, int32_t enabled);
int32_t sa_std_net_tcp_stream_quickack(uint64_t stream_handle, int32_t *out_enabled);
int32_t sa_std_net_tcp_stream_set_deferaccept(uint64_t stream_handle, uint32_t seconds);
int32_t sa_std_net_tcp_stream_deferaccept(uint64_t stream_handle, uint32_t *out_seconds);
int32_t sa_std_net_tcp_stream_set_ttl(uint64_t stream_handle, uint32_t ttl);
int32_t sa_std_net_tcp_stream_read_timeout(uint64_t stream_handle, uint64_t *out_timeout_ns);
int32_t sa_std_net_tcp_stream_write_timeout(uint64_t stream_handle, uint64_t *out_timeout_ns);

int32_t sa_std_net_tcp_stream_set_recv_buffer_size(uint64_t stream_handle, uint32_t size);
int32_t sa_std_net_tcp_stream_recv_buffer_size(uint64_t stream_handle, uint32_t *out_size);
int32_t sa_std_net_tcp_stream_set_send_buffer_size(uint64_t stream_handle, uint32_t size);
int32_t sa_std_net_tcp_stream_send_buffer_size(uint64_t stream_handle, uint32_t *out_size);

int32_t sa_std_net_tcp_stream_nodelay(uint64_t stream_handle, int32_t *out_enabled);
int32_t sa_std_net_tcp_stream_ttl(uint64_t stream_handle, uint32_t *out_ttl);
int32_t sa_std_net_tcp_stream_take_error(uint64_t stream_handle, int32_t *out_error);
int32_t sa_net_tcp_stream_set_read_timeout(uint64_t stream_handle, uint64_t timeout_ns);
int32_t sa_net_tcp_stream_set_write_timeout(uint64_t stream_handle, uint64_t timeout_ns);
int32_t sa_net_tcp_stream_set_nonblocking(uint64_t stream_handle, int32_t enabled);
int32_t sa_net_tcp_stream_set_nodelay(uint64_t stream_handle, int32_t enabled);
int32_t sa_net_tcp_stream_set_ttl(uint64_t stream_handle, uint32_t ttl);
int32_t sa_std_net_tcp_listener_set_nonblocking(uint64_t listener_handle, int32_t enabled);
int32_t sa_std_net_tcp_listener_set_ttl(uint64_t listener_handle, uint32_t ttl);
int32_t sa_std_net_tcp_listener_ttl(uint64_t listener_handle, uint32_t *out_ttl);
int32_t sa_std_net_tcp_listener_take_error(uint64_t listener_handle, int32_t *out_error);
int32_t sa_std_net_tcp_listener_set_reuseaddr(uint64_t listener_handle, int32_t enabled);
int32_t sa_std_net_tcp_listener_set_reuseport(uint64_t listener_handle, int32_t enabled);
int32_t sa_std_net_tcp_listener_set_only_v6(uint64_t listener_handle, int32_t enabled);
int32_t sa_std_net_tcp_listener_only_v6(uint64_t listener_handle, int32_t *out_enabled);
int32_t sa_std_net_udp_set_only_v6(uint64_t socket, int32_t enabled);
int32_t sa_std_net_udp_only_v6(uint64_t socket, int32_t *out_enabled);
int32_t sa_std_net_tcp_listener_from_raw_fd(int32_t fd, uint64_t *out_handle);
int32_t sa_std_net_tcp_stream_from_raw_fd(int32_t fd, uint64_t *out_handle);
int32_t sa_std_net_tcp_stream_try_clone(uint64_t stream, uint64_t *out_handle);
int32_t sa_std_net_tcp_listener_try_clone(uint64_t listener, uint64_t *out_handle);
int32_t sa_std_net_udp_try_clone(uint64_t socket, uint64_t *out_handle);

int32_t sa_std_net_unix_listen(const uint8_t *path, uint64_t path_len, uint64_t *out_handle);
int32_t sa_std_net_unix_accept(uint64_t listener_handle, uint64_t *out_handle);
int32_t sa_std_net_unix_accept_addr(uint64_t listener_handle, uint64_t *out_stream, uint64_t *out_addr);
int32_t sa_std_net_unix_connect(const uint8_t *path, uint64_t path_len, uint64_t *out_handle);
int32_t sa_std_net_unix_pair(uint64_t *out_left, uint64_t *out_right);
int32_t sa_std_net_unix_addr_from_abstract_name(const uint8_t *name, uint64_t name_len, uint64_t *out_handle);
int32_t sa_std_net_unix_addr_from_pathname(const uint8_t *path, uint64_t path_len, uint64_t *out_handle);
int32_t sa_std_net_unix_listen_addr(uint64_t addr_handle, uint64_t *out_handle);
int32_t sa_std_net_unix_connect_addr(uint64_t addr_handle, uint64_t *out_handle);
int32_t sa_std_net_unix_listener_local_addr(uint64_t listener_handle, uint64_t *out_handle);
int32_t sa_std_net_unix_listener_try_clone(uint64_t listener_handle, uint64_t *out_handle);
int32_t sa_std_net_unix_listener_from_raw_fd(int32_t fd, uint64_t *out_handle);
int32_t sa_std_net_unix_stream_local_addr(uint64_t stream_handle, uint64_t *out_handle);
int32_t sa_std_net_unix_stream_try_clone(uint64_t stream_handle, uint64_t *out_handle);
int32_t sa_std_net_unix_stream_from_raw_fd(int32_t fd, uint64_t *out_handle);
int32_t sa_std_net_unix_stream_peer_addr(uint64_t stream_handle, uint64_t *out_handle);
int32_t sa_std_net_unix_stream_set_passcred(uint64_t stream_handle, int32_t enabled);
int32_t sa_std_net_unix_stream_passcred(uint64_t stream_handle, int32_t *out_enabled);
int32_t sa_std_net_unix_stream_set_mark(uint64_t stream_handle, uint32_t mark);
int32_t sa_std_net_unix_stream_peer_cred(uint64_t stream_handle, int32_t *out_pid, uint32_t *out_uid, uint32_t *out_gid);
int32_t sa_std_net_unix_datagram_unbound(uint64_t *out_handle);
int32_t sa_std_net_unix_datagram_bind(const uint8_t *path, uint64_t path_len, uint64_t *out_handle);
int32_t sa_std_net_unix_datagram_bind_addr(uint64_t addr_handle, uint64_t *out_handle);
int32_t sa_std_net_unix_datagram_pair(uint64_t *out_left, uint64_t *out_right);
int32_t sa_std_net_unix_datagram_connect(uint64_t socket_handle, const uint8_t *path, uint64_t path_len);
int32_t sa_std_net_unix_datagram_connect_addr(uint64_t socket_handle, uint64_t addr_handle);
int32_t sa_std_net_unix_datagram_try_clone(uint64_t socket_handle, uint64_t *out_handle);
int32_t sa_std_net_unix_datagram_from_raw_fd(int32_t fd, uint64_t *out_handle);
int32_t sa_std_net_unix_datagram_local_addr(uint64_t socket_handle, uint64_t *out_handle);
int32_t sa_std_net_unix_datagram_peer_addr(uint64_t socket_handle, uint64_t *out_handle);
int32_t sa_std_net_unix_datagram_set_passcred(uint64_t socket_handle, int32_t enabled);
int32_t sa_std_net_unix_datagram_passcred(uint64_t socket_handle, int32_t *out_enabled);
int32_t sa_std_net_unix_datagram_set_mark(uint64_t socket_handle, uint32_t mark);
int32_t sa_std_net_unix_datagram_shutdown(uint64_t socket_handle, uint32_t how);
int32_t sa_std_net_unix_datagram_send_to(uint64_t socket_handle, const uint8_t *buf, uint64_t len, const uint8_t *path, uint64_t path_len, uint64_t *out_written);
int32_t sa_std_net_unix_datagram_send_to_addr(uint64_t socket_handle, const uint8_t *buf, uint64_t len, uint64_t addr_handle, uint64_t *out_written);
int32_t sa_std_net_unix_datagram_recv_from(uint64_t socket_handle, uint8_t *out, uint64_t cap, uint64_t *out_read, uint64_t *out_addr);
int32_t sa_std_net_unix_datagram_peek_from(uint64_t socket_handle, uint8_t *out, uint64_t cap, uint64_t *out_read, uint64_t *out_addr);

int32_t sa_std_net_udp_bind(const uint8_t *host, uint64_t host_len, uint32_t port, uint64_t *out_handle);
int32_t sa_std_net_udp_local_addr(uint64_t socket_handle, uint64_t *out_handle);
int32_t sa_std_net_udp_peer_addr(uint64_t socket_handle, uint64_t *out_handle);
int32_t sa_std_net_udp_connect(uint64_t socket_handle, const uint8_t *host, uint64_t host_len, uint32_t port);
int32_t sa_std_net_udp_connect_addr(uint64_t socket_handle, uint64_t addr_handle);
int32_t sa_std_net_udp_set_read_timeout(uint64_t socket_handle, uint64_t timeout_ns);
int32_t sa_std_net_udp_set_write_timeout(uint64_t socket_handle, uint64_t timeout_ns);
int32_t sa_std_net_udp_set_nonblocking(uint64_t socket_handle, int32_t enabled);
int32_t sa_std_net_udp_set_broadcast(uint64_t socket_handle, int32_t enabled);
int32_t sa_std_net_udp_set_ttl(uint64_t socket_handle, uint32_t ttl);
int32_t sa_std_net_udp_set_multicast_loop_v4(uint64_t socket_handle, int32_t enabled);
int32_t sa_std_net_udp_set_multicast_ttl_v4(uint64_t socket_handle, uint32_t ttl);
int32_t sa_std_net_udp_set_multicast_loop_v6(uint64_t socket_handle, int32_t enabled);
int32_t sa_std_net_udp_set_multicast_hops_v6(uint64_t socket_handle, uint32_t hops);
int32_t sa_std_net_udp_read_timeout(uint64_t socket_handle, uint64_t *out_timeout_ns);
int32_t sa_std_net_udp_write_timeout(uint64_t socket_handle, uint64_t *out_timeout_ns);

int32_t sa_std_net_udp_set_recv_buffer_size(uint64_t socket_handle, uint32_t size);
int32_t sa_std_net_udp_recv_buffer_size(uint64_t socket_handle, uint32_t *out_size);
int32_t sa_std_net_udp_set_send_buffer_size(uint64_t socket_handle, uint32_t size);
int32_t sa_std_net_udp_send_buffer_size(uint64_t socket_handle, uint32_t *out_size);

int32_t sa_std_net_udp_broadcast(uint64_t socket_handle, int32_t *out_enabled);
int32_t sa_std_net_udp_ttl(uint64_t socket_handle, uint32_t *out_ttl);
int32_t sa_std_net_udp_multicast_loop_v4(uint64_t socket_handle, int32_t *out_enabled);
int32_t sa_std_net_udp_multicast_ttl_v4(uint64_t socket_handle, uint32_t *out_ttl);
int32_t sa_std_net_udp_multicast_loop_v6(uint64_t socket_handle, int32_t *out_enabled);
int32_t sa_std_net_udp_multicast_hops_v6(uint64_t socket_handle, uint32_t *out_hops);
int32_t sa_std_net_udp_set_multicast_if_v4(uint64_t socket_handle, const uint8_t *interface_addr);
int32_t sa_std_net_udp_multicast_if_v4(uint64_t socket_handle, uint8_t *out_interface_addr);
int32_t sa_std_net_udp_set_multicast_if_v6(uint64_t socket_handle, uint32_t interface_index);
int32_t sa_std_net_udp_multicast_if_v6(uint64_t socket_handle, uint32_t *out_interface_index);
int32_t sa_std_net_udp_take_error(uint64_t socket_handle, int32_t *out_error);
int32_t sa_std_net_udp_send(uint64_t socket_handle, const uint8_t *buf, uint64_t len, uint64_t *out_written);
int32_t sa_std_net_udp_recv(uint64_t socket_handle, uint8_t *out, uint64_t cap, uint64_t *out_read);
int32_t sa_std_net_udp_peek(uint64_t socket_handle, uint8_t *out, uint64_t cap, uint64_t *out_read);
int32_t sa_std_net_udp_send_to(uint64_t socket_handle, const uint8_t *buf, uint64_t len, const uint8_t *host, uint64_t host_len, uint32_t port, uint64_t *out_written);
int32_t sa_std_net_udp_send_vectored(uint64_t socket, const sa_net_iov *iovs, uint64_t iov_count, uint64_t *out_written);
int32_t sa_std_net_udp_send_to_vectored(uint64_t socket, const sa_net_iov *iovs, uint64_t iov_count, const uint8_t *host_ptr, uint64_t host_len, uint32_t port, uint64_t *out_written);
int32_t sa_std_net_udp_recv_from_vectored(uint64_t socket, const sa_net_iov *iovs, uint64_t iov_count, uint64_t *out_read, uint64_t *out_addr);
int32_t sa_std_net_udp_recv_from(uint64_t socket_handle, uint8_t *out, uint64_t cap, uint64_t *out_read, uint64_t *out_addr_handle);
int32_t sa_std_net_udp_peek_from(uint64_t socket_handle, uint8_t *out, uint64_t cap, uint64_t *out_read, uint64_t *out_addr_handle);
int32_t sa_std_net_udp_join_multicast_v4(uint64_t socket_handle, const uint8_t *multi_host, uint64_t multi_host_len, const uint8_t *interface_host, uint64_t interface_host_len);
int32_t sa_std_net_udp_leave_multicast_v4(uint64_t socket_handle, const uint8_t *multi_host, uint64_t multi_host_len, const uint8_t *interface_host, uint64_t interface_host_len);
int32_t sa_std_net_udp_join_multicast_v6(uint64_t socket_handle, const uint8_t *multi_host, uint64_t multi_host_len, uint32_t interface_index);
int32_t sa_std_net_udp_leave_multicast_v6(uint64_t socket_handle, const uint8_t *multi_host, uint64_t multi_host_len, uint32_t interface_index);
int32_t sa_net_udp_connect(uint64_t socket_handle, const uint8_t *host, uint64_t host_len, uint16_t port);
int32_t sa_net_udp_set_read_timeout(uint64_t socket_handle, uint64_t timeout_ns);
int32_t sa_net_udp_set_write_timeout(uint64_t socket_handle, uint64_t timeout_ns);
int32_t sa_net_udp_set_nonblocking(uint64_t socket_handle, int32_t enabled);
int32_t sa_net_udp_set_broadcast(uint64_t socket_handle, int32_t enabled);
int32_t sa_net_udp_set_ttl(uint64_t socket_handle, uint32_t ttl);
int32_t sa_net_udp_set_multicast_loop_v4(uint64_t socket_handle, int32_t enabled);
int32_t sa_net_udp_set_multicast_ttl_v4(uint64_t socket_handle, uint32_t ttl);
int32_t sa_net_udp_send(uint64_t socket_handle, const uint8_t *buf, uint64_t len);
int32_t sa_net_udp_recv(uint64_t socket_handle, uint8_t *out, uint64_t cap);
int32_t sa_net_udp_join_multicast_v4(uint64_t socket_handle, const uint8_t *multi_host, uint64_t multi_host_len, const uint8_t *interface_host, uint64_t interface_host_len);
int32_t sa_net_udp_leave_multicast_v4(uint64_t socket_handle, const uint8_t *multi_host, uint64_t multi_host_len, const uint8_t *interface_host, uint64_t interface_host_len);
int32_t sa_net_udp_join_multicast_v6(uint64_t socket_handle, const uint8_t *multi_host, uint64_t multi_host_len, uint32_t interface_index);
int32_t sa_net_udp_leave_multicast_v6(uint64_t socket_handle, const uint8_t *multi_host, uint64_t multi_host_len, uint32_t interface_index);
int32_t sa_net_udp_close(uint64_t socket_handle);

int32_t sa_std_net_udp_from_raw_fd(int32_t fd, uint64_t *out_handle);
uint8_t *sa_net_addr_host(uint64_t addr_handle);
uint64_t sa_net_addr_host_len(uint64_t addr_handle);
uint32_t sa_net_addr_port(uint64_t addr_handle);
uint32_t sa_net_addr_family(uint64_t addr_handle);
uint64_t sa_net_addr_scope_id(uint64_t addr_handle);
int32_t sa_std_net_addr_format(uint64_t addr_handle, uint8_t *out, uint64_t out_cap, uint64_t *out_len);
sa_std_fallible_i32 sa_net_addr_free(uint64_t addr_handle);
uint32_t sa_net_unix_addr_kind(uint64_t addr_handle);
uint8_t sa_net_unix_addr_is_unnamed(uint64_t addr_handle);
uint8_t *sa_net_unix_addr_path_ptr(uint64_t addr_handle);
uint64_t sa_net_unix_addr_path_len(uint64_t addr_handle);
uint8_t *sa_net_unix_addr_abstract_ptr(uint64_t addr_handle);
uint64_t sa_net_unix_addr_abstract_len(uint64_t addr_handle);
sa_std_fallible_i32 sa_net_unix_addr_free(uint64_t addr_handle);
int32_t sa_net_ipv4_parse_ascii(const uint8_t *text, uint64_t text_len, uint8_t *out_addr);
int32_t sa_net_socket_addr_v4_parse_ascii(const uint8_t *text, uint64_t text_len, uint8_t *out_socket_addr);
int32_t sa_net_ipv6_parse_ascii(const uint8_t *text, uint64_t text_len, uint8_t *out_addr);
int32_t sa_net_socket_addr_v6_parse_ascii(const uint8_t *text, uint64_t text_len, uint8_t *out_socket_addr);
int32_t sa_net_ipv4_format_ascii(const uint8_t *addr, uint8_t *out, uint64_t out_cap, uint64_t *out_len);
int32_t sa_net_ipv6_format_ascii(const uint8_t *addr, uint8_t *out, uint64_t out_cap, uint64_t *out_len);
int32_t sa_net_socket_addr_v4_format_ascii(const uint8_t *addr, uint8_t *out, uint64_t out_cap, uint64_t *out_len);
int32_t sa_net_socket_addr_v6_format_ascii(const uint8_t *addr, uint8_t *out, uint64_t out_cap, uint64_t *out_len);

int32_t sa_std_process_run(const SaProcessArgv *argv, uint64_t argv_len, uint64_t *out_handle);
int32_t sa_std_process_run_cwd(const SaProcessArgv *argv, uint64_t argv_len, const uint8_t *cwd, uint64_t cwd_len, uint64_t *out_handle);
int32_t sa_std_process_spawn(const SaProcessArgv *argv, uint64_t argv_len, uint64_t *out_handle);
int32_t sa_std_process_spawn_cwd(const SaProcessArgv *argv, uint64_t argv_len, const uint8_t *cwd, uint64_t cwd_len, uint64_t *out_handle);
int32_t sa_std_process_spawn_stream(const SaProcessArgv *argv, uint64_t argv_len, uint64_t *out_process, uint64_t *out_stdout, uint64_t *out_stderr);
int32_t sa_std_process_spawn_stream_cwd(const SaProcessArgv *argv, uint64_t argv_len, const uint8_t *cwd, uint64_t cwd_len, uint64_t *out_process, uint64_t *out_stdout, uint64_t *out_stderr);
int32_t sa_std_process_spawn_bidi(const SaProcessArgv *argv, uint64_t argv_len, uint64_t *out_process, uint64_t *out_stdin, uint64_t *out_stdout, uint64_t *out_stderr);
int32_t sa_std_process_spawn_bidi_cwd(const SaProcessArgv *argv, uint64_t argv_len, const uint8_t *cwd, uint64_t cwd_len, uint64_t *out_process, uint64_t *out_stdin, uint64_t *out_stdout, uint64_t *out_stderr);
int32_t sa_std_process_run_command_ext(const SaProcessArgv *argv, uint64_t argv_len, const uint8_t *cwd, uint64_t cwd_len, uint32_t has_cwd, const uint8_t *arg0, uint64_t arg0_len, uint32_t has_arg0, int32_t process_group, uint32_t has_process_group, uint32_t setsid, uint64_t *out_handle);
int32_t sa_std_process_spawn_command_ext(const SaProcessArgv *argv, uint64_t argv_len, const uint8_t *cwd, uint64_t cwd_len, uint32_t has_cwd, const uint8_t *arg0, uint64_t arg0_len, uint32_t has_arg0, int32_t process_group, uint32_t has_process_group, uint32_t setsid, uint64_t *out_handle);
int32_t sa_std_process_spawn_stream_command_ext(const SaProcessArgv *argv, uint64_t argv_len, const uint8_t *cwd, uint64_t cwd_len, uint32_t has_cwd, const uint8_t *arg0, uint64_t arg0_len, uint32_t has_arg0, int32_t process_group, uint32_t has_process_group, uint32_t setsid, uint64_t *out_process, uint64_t *out_stdout, uint64_t *out_stderr);
int32_t sa_std_process_run_command_ext_pidfd(const SaProcessArgv *argv, uint64_t argv_len, const uint8_t *cwd, uint64_t cwd_len, uint32_t has_cwd, const uint8_t *arg0, uint64_t arg0_len, uint32_t has_arg0, int32_t process_group, uint32_t has_process_group, uint32_t setsid, uint32_t create_pidfd, uint64_t *out_handle);
int32_t sa_std_process_spawn_command_ext_pidfd(const SaProcessArgv *argv, uint64_t argv_len, const uint8_t *cwd, uint64_t cwd_len, uint32_t has_cwd, const uint8_t *arg0, uint64_t arg0_len, uint32_t has_arg0, int32_t process_group, uint32_t has_process_group, uint32_t setsid, uint32_t create_pidfd, uint64_t *out_handle);
int32_t sa_std_process_spawn_stream_command_ext_pidfd(const SaProcessArgv *argv, uint64_t argv_len, const uint8_t *cwd, uint64_t cwd_len, uint32_t has_cwd, const uint8_t *arg0, uint64_t arg0_len, uint32_t has_arg0, int32_t process_group, uint32_t has_process_group, uint32_t setsid, uint32_t create_pidfd, uint64_t *out_process, uint64_t *out_stdout, uint64_t *out_stderr);
int32_t sa_std_process_run_command_ext_uid_gid(const SaProcessArgv *argv, uint64_t argv_len, const uint8_t *cwd, uint64_t cwd_len, uint32_t has_cwd, const uint8_t *arg0, uint64_t arg0_len, uint32_t has_arg0, int32_t process_group, uint32_t has_process_group, uint32_t setsid, uint32_t uid, uint32_t has_uid, uint32_t gid, uint32_t has_gid, uint64_t *out_handle);
int32_t sa_std_process_spawn_command_ext_uid_gid(const SaProcessArgv *argv, uint64_t argv_len, const uint8_t *cwd, uint64_t cwd_len, uint32_t has_cwd, const uint8_t *arg0, uint64_t arg0_len, uint32_t has_arg0, int32_t process_group, uint32_t has_process_group, uint32_t setsid, uint32_t uid, uint32_t has_uid, uint32_t gid, uint32_t has_gid, uint64_t *out_handle);
int32_t sa_std_process_spawn_stream_command_ext_uid_gid(const SaProcessArgv *argv, uint64_t argv_len, const uint8_t *cwd, uint64_t cwd_len, uint32_t has_cwd, const uint8_t *arg0, uint64_t arg0_len, uint32_t has_arg0, int32_t process_group, uint32_t has_process_group, uint32_t setsid, uint32_t uid, uint32_t has_uid, uint32_t gid, uint32_t has_gid, uint64_t *out_process, uint64_t *out_stdout, uint64_t *out_stderr);
int32_t sa_std_process_run_command_ext_groups(const SaProcessArgv *argv, uint64_t argv_len, const uint8_t *cwd, uint64_t cwd_len, uint32_t has_cwd, const uint8_t *arg0, uint64_t arg0_len, uint32_t has_arg0, int32_t process_group, uint32_t has_process_group, uint32_t setsid, const uint32_t *groups, uint64_t groups_len, uint32_t has_groups, uint64_t *out_handle);
int32_t sa_std_process_spawn_command_ext_groups(const SaProcessArgv *argv, uint64_t argv_len, const uint8_t *cwd, uint64_t cwd_len, uint32_t has_cwd, const uint8_t *arg0, uint64_t arg0_len, uint32_t has_arg0, int32_t process_group, uint32_t has_process_group, uint32_t setsid, const uint32_t *groups, uint64_t groups_len, uint32_t has_groups, uint64_t *out_handle);
int32_t sa_std_process_spawn_stream_command_ext_groups(const SaProcessArgv *argv, uint64_t argv_len, const uint8_t *cwd, uint64_t cwd_len, uint32_t has_cwd, const uint8_t *arg0, uint64_t arg0_len, uint32_t has_arg0, int32_t process_group, uint32_t has_process_group, uint32_t setsid, const uint32_t *groups, uint64_t groups_len, uint32_t has_groups, uint64_t *out_process, uint64_t *out_stdout, uint64_t *out_stderr);
int32_t sa_std_process_run_command_ext_chroot(const SaProcessArgv *argv, uint64_t argv_len, const uint8_t *cwd, uint64_t cwd_len, uint32_t has_cwd, const uint8_t *arg0, uint64_t arg0_len, uint32_t has_arg0, int32_t process_group, uint32_t has_process_group, uint32_t setsid, const uint8_t *chroot, uint64_t chroot_len, uint32_t has_chroot, uint64_t *out_handle);
int32_t sa_std_process_spawn_command_ext_chroot(const SaProcessArgv *argv, uint64_t argv_len, const uint8_t *cwd, uint64_t cwd_len, uint32_t has_cwd, const uint8_t *arg0, uint64_t arg0_len, uint32_t has_arg0, int32_t process_group, uint32_t has_process_group, uint32_t setsid, const uint8_t *chroot, uint64_t chroot_len, uint32_t has_chroot, uint64_t *out_handle);
int32_t sa_std_process_spawn_stream_command_ext_chroot(const SaProcessArgv *argv, uint64_t argv_len, const uint8_t *cwd, uint64_t cwd_len, uint32_t has_cwd, const uint8_t *arg0, uint64_t arg0_len, uint32_t has_arg0, int32_t process_group, uint32_t has_process_group, uint32_t setsid, const uint8_t *chroot, uint64_t chroot_len, uint32_t has_chroot, uint64_t *out_process, uint64_t *out_stdout, uint64_t *out_stderr);
int32_t sa_std_process_exec_command_ext(const SaProcessArgv *argv, uint64_t argv_len, const uint8_t *cwd, uint64_t cwd_len, uint32_t has_cwd, const uint8_t *arg0, uint64_t arg0_len, uint32_t has_arg0, int32_t process_group, uint32_t has_process_group, uint32_t setsid, uint32_t uid, uint32_t has_uid, uint32_t gid, uint32_t has_gid, const uint32_t *groups, uint64_t groups_len, uint32_t has_groups, const uint8_t *chroot, uint64_t chroot_len, uint32_t has_chroot);
uint32_t sa_std_process_id(void);
uint32_t sa_std_process_parent_id(void);
uint32_t sa_std_process_user_id(void);
uint32_t sa_std_process_group_id(void);
void sa_std_process_abort(void);
int32_t sa_std_process_child_id(uint64_t handle, uint32_t *out_pid);
int32_t sa_std_process_pidfd(uint64_t handle, uint64_t *out_pidfd);
int32_t sa_std_process_into_pidfd(uint64_t handle, uint64_t *out_pidfd);
int32_t sa_std_process_wait(uint64_t handle, uint32_t *out_code);
int32_t sa_std_process_wait_raw(uint64_t handle, int32_t *out_raw);
int32_t sa_std_process_try_wait(uint64_t handle, int32_t *out_ready, uint32_t *out_code);
int32_t sa_std_process_try_wait_raw(uint64_t handle, int32_t *out_ready, int32_t *out_raw);
int32_t sa_std_process_kill(uint64_t handle);
int32_t sa_std_process_send_signal(uint64_t handle, int32_t signal);
int32_t sa_std_process_send_process_group_signal(uint64_t handle, int32_t signal);
int32_t sa_std_process_kill_process_group(uint64_t handle);
int32_t sa_std_pidfd_kill(uint64_t handle);
int32_t sa_std_pidfd_send_signal(uint64_t handle, int32_t signal);
int32_t sa_std_pidfd_wait(uint64_t handle, uint32_t *out_code);
int32_t sa_std_pidfd_wait_raw(uint64_t handle, int32_t *out_raw);
int32_t sa_std_pidfd_try_wait(uint64_t handle, int32_t *out_ready, uint32_t *out_code);
int32_t sa_std_pidfd_try_wait_raw(uint64_t handle, int32_t *out_ready, int32_t *out_raw);
uint32_t sa_std_process_exit_status_code(int32_t raw);
int32_t sa_std_process_exit_status_signal(int32_t raw);
uint8_t sa_std_process_exit_status_core_dumped(int32_t raw);
int32_t sa_std_process_exit_status_stopped_signal(int32_t raw);
uint8_t sa_std_process_exit_status_continued(int32_t raw);
int32_t sa_std_process_read_stdout(uint64_t handle, uint8_t *out, uint64_t out_cap, uint64_t *out_read);
int32_t sa_std_process_read_stderr(uint64_t handle, uint8_t *out, uint64_t out_cap, uint64_t *out_read);
int32_t sa_std_process_exec_capture(const SaProcessArgv *argv, uint64_t argv_len, uint32_t *out_code, uint64_t *out_stdout, uint64_t *out_stderr);
int32_t sa_std_process_exec_capture_cwd(const SaProcessArgv *argv, uint64_t argv_len, const uint8_t *cwd, uint64_t cwd_len, uint32_t *out_code, uint64_t *out_stdout, uint64_t *out_stderr);
int32_t sa_std_process_close(uint64_t handle);

uint64_t sa_thread_current_id(void);
int32_t sa_thread_yield_now(void);
int32_t sa_thread_as_pthread_t(int32_t handle, uint64_t *out_raw);
int32_t sa_thread_into_pthread_t(int32_t handle, uint64_t *out_raw);
int32_t sa_thread_raw_pthread_join(uint64_t raw, uint8_t *out);

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
uint64_t sa_time_iso_from_unix_ms(int64_t ms);
int32_t sa_time_parse_iso(const uint8_t *iso, uint64_t len, int64_t *out_ms);
int64_t sa_time_get_full_year(int64_t ms);
int64_t sa_time_get_month(int64_t ms);
int64_t sa_time_get_date(int64_t ms);
int64_t sa_time_get_hours(int64_t ms);
int64_t sa_time_get_minutes(int64_t ms);
int64_t sa_time_get_seconds(int64_t ms);
int64_t sa_time_get_milliseconds(int64_t ms);
int64_t sa_time_get_day(int64_t ms);
int64_t sa_time_set_field(int64_t ms, uint64_t field, int64_t value);
uint64_t sa_time_format_utc(int64_t ms, uint64_t fmt);
int32_t sa_time_sleep_ns(uint64_t ns);
int32_t sa_time_sleep_ms(uint64_t ms);

int32_t pthread_spawn(const uint8_t *entry, const uint8_t *arg);
int32_t pthread_spawn_detached(const uint8_t *entry, const uint8_t *arg);
int32_t pthread_join(int32_t handle, uint8_t *out);
void pthread_drop(int32_t handle);

uint8_t *sa_fmt_buffer_data(uint64_t buffer);
uint64_t sa_fmt_buffer_len(uint64_t buffer);
int32_t sa_fmt_buffer_write_to(uint64_t buffer, uint64_t writer);
int32_t sa_fmt_buffer_free(uint64_t buffer);
uint64_t sa_string_concat(const uint8_t *left, uint64_t left_len, const uint8_t *right, uint64_t right_len);
uint64_t sa_string_from_char_code(int32_t code);
int32_t sa_string_index_of(const uint8_t *hay_ptr, uint64_t hay_len, const uint8_t *ndl_ptr, uint64_t ndl_len, uint64_t from);
int32_t sa_string_last_index_of(const uint8_t *hay_ptr, uint64_t hay_len, const uint8_t *ndl_ptr, uint64_t ndl_len, uint64_t from);
int32_t sa_string_starts_with(const uint8_t *hay_ptr, uint64_t hay_len, const uint8_t *ndl_ptr, uint64_t ndl_len);
int32_t sa_string_ends_with(const uint8_t *hay_ptr, uint64_t hay_len, const uint8_t *ndl_ptr, uint64_t ndl_len);
uint64_t sa_string_to_lower_ascii(const uint8_t *ptr, uint64_t len);
uint64_t sa_string_to_upper_ascii(const uint8_t *ptr, uint64_t len);
double sa_parse_float(const uint8_t *ptr, uint64_t len);
uint64_t sa_string_repeat(const uint8_t *ptr, uint64_t len, uint64_t count);
uint64_t sa_string_pad_start(const uint8_t *ptr, uint64_t len, uint64_t target_len, const uint8_t *pad_ptr, uint64_t pad_len);
uint64_t sa_string_pad_end(const uint8_t *ptr, uint64_t len, uint64_t target_len, const uint8_t *pad_ptr, uint64_t pad_len);
uint64_t sa_string_replace(const uint8_t *hay_ptr, uint64_t hay_len, const uint8_t *ndl_ptr, uint64_t ndl_len, const uint8_t *rep_ptr, uint64_t rep_len, uint64_t all);
int32_t sa_string_code_point_at(const uint8_t *ptr, uint64_t len, uint64_t idx);
uint64_t sa_string_from_code_point(int32_t code);
int32_t sa_str_is_ascii(const uint8_t *ptr, uint64_t len);
int32_t sa_str_eq_ignore_ascii_case(const uint8_t *left, uint64_t left_len, const uint8_t *right, uint64_t right_len);
uint64_t sa_str_trim_ascii_start_index(const uint8_t *ptr, uint64_t len);
uint64_t sa_str_trim_ascii_end_len(const uint8_t *ptr, uint64_t len);
uint64_t sa_str_utf8_char_count(const uint8_t *ptr, uint64_t len);
int32_t sa_str_utf8_validate(const uint8_t *ptr, uint64_t len);
int32_t sa_str_utf8_char_at(const uint8_t *ptr, uint64_t len, uint64_t char_index, uint64_t *out_codepoint);
int32_t sa_str_utf8_char_at_byte(const uint8_t *ptr, uint64_t len, uint64_t byte_index, uint64_t *out_codepoint, uint64_t *out_len);
int32_t sa_str_utf8_lossy_next(const uint8_t *ptr, uint64_t len, uint64_t byte_index, uint64_t *out_codepoint, uint64_t *out_len);
int32_t sa_str_utf8_char_range_at(const uint8_t *ptr, uint64_t len, uint64_t char_index, uint64_t *out_start, uint64_t *out_len);
uint64_t sa_env_get(const uint8_t *key, uint64_t key_len);
int32_t sa_env_has(const uint8_t *key, uint64_t key_len);
int32_t sa_env_set_var(const uint8_t *key, uint64_t key_len, const uint8_t *value, uint64_t value_len);
int32_t sa_env_remove_var(const uint8_t *key, uint64_t key_len);
uint64_t sa_env_current_dir(void);
int32_t sa_env_set_current_dir(const uint8_t *path, uint64_t path_len);
uint64_t sa_env_temp_dir(void);
uint64_t sa_env_current_exe(void);
uint64_t sa_env_home_dir(void);
uint64_t sa_env_args_json(void);
uint64_t sa_env_vars_json(void);
uint64_t sa_env_split_paths_json(const uint8_t *path_list, uint64_t path_list_len);
uint64_t sa_env_join_paths_json(const uint8_t *paths_json, uint64_t paths_json_len);
uint64_t sa_env_xdg_data_home_dir(void);
uint64_t sa_env_xdg_config_home_dir(void);
uint64_t sa_env_xdg_state_home_dir(void);
uint64_t sa_env_xdg_cache_home_dir(void);
uint64_t sa_env_xdg_data_dirs(void);
uint64_t sa_env_xdg_config_dirs(void);
uint8_t *sa_env_buffer_data(uint64_t buffer);
uint64_t sa_env_buffer_len(uint64_t buffer);
int32_t sa_env_buffer_free(uint64_t buffer);
uint64_t sa_fmt_i64(int64_t value, uint32_t base);
double sa_math_floor(double x);
double sa_math_ceil(double x);
double sa_math_sqrt(double x);
double sa_math_sin(double x);
double sa_math_cos(double x);
double sa_math_pow(double base, double exp);
double sa_math_random(void);
uint64_t sa_fmt_u64(uint64_t value, uint32_t base);
uint64_t sa_fmt_f64(double value, uint32_t precision);
uint64_t sa_fmt_bool(uint8_t value);
uint64_t sa_fmt_bytes(const uint8_t *buf, uint64_t len);
int32_t sa_fmt_i64_into(int64_t value, uint32_t base, uint8_t *out, uint64_t out_cap, uint64_t *out_len);
void sa_test_debug_i64(const uint8_t *name, uint64_t name_len, int64_t value);
void sa_assert_eq_i64(int64_t actual, int64_t expected, int32_t code);
void sa_assert_eq_i64_at(int64_t actual, int64_t expected, int32_t code, const uint8_t *file, uint64_t file_len, uint32_t line, uint32_t col);
int32_t sa_fmt_u64_into(uint64_t value, uint32_t base, uint8_t *out, uint64_t out_cap, uint64_t *out_len);
int32_t sa_fmt_f64_into(double value, uint32_t precision, uint8_t *out, uint64_t out_cap, uint64_t *out_len);
int32_t sa_fmt_bool_into(uint8_t value, uint8_t *out, uint64_t out_cap, uint64_t *out_len);
int32_t sa_fmt_bytes_into(const uint8_t *buf, uint64_t len, uint8_t *out, uint64_t out_cap, uint64_t *out_len);

int32_t sa_std_http2_supported(uint32_t *out_supported);
int32_t sa_std_http2_client_request(const uint8_t *url, uint64_t url_len, const uint8_t *method, uint64_t method_len, const uint8_t *body, uint64_t body_len, uint64_t *out_handle);
int32_t sa_std_http2_nghttp2_version_json(uint64_t *out_handle);
int32_t sa_std_http2_status_json(uint64_t *out_handle);
int32_t sa_std_http2_constants_json(uint64_t *out_handle);
int32_t sa_std_http2_sensitive_headers(uint64_t *out_handle);
int32_t sa_std_http2_get_default_settings_json(uint64_t *out_handle);
int32_t sa_std_http2_get_packed_settings(const uint8_t *settings_json, uint64_t settings_json_len, uint64_t *out_handle);
int32_t sa_std_http2_get_unpacked_settings_json(const uint8_t *buf, uint64_t buf_len, uint64_t *out_handle);
int32_t sa_std_http2_perform_server_handshake(const uint8_t *input, uint64_t input_len, const uint8_t *settings_json, uint64_t settings_json_len, uint64_t *out_bytes, uint64_t *out_json);
const uint8_t *sa_std_http2_buffer_data(uint64_t handle);
uint64_t sa_std_http2_buffer_len(uint64_t handle);
int32_t sa_std_http2_buffer_free(uint64_t handle);

/* ABI expansion, 2026-10-28: the sections below declare the remaining
 * contract surface of the standard library. Every declaration was
 * verified against a matching export in the Linux runtime archive,
 * and signatures mirror the library contracts: status-code returns,
 * byte spans as pointer plus length, results through out parameters,
 * opaque handles as integers or pointers per contract. */

/* Compression. */
const uint8_t *sa_std_compress_buffer_data(uint64_t buffer);
int32_t sa_std_compress_buffer_free(uint64_t buffer);
uint64_t sa_std_compress_buffer_len(uint64_t buffer);
int32_t sa_std_compress_decode(uint32_t format, const uint8_t *data, uint64_t data_len, uint64_t *out_handle);
int32_t sa_std_compress_encode(uint32_t format, const uint8_t *data, uint64_t data_len, uint64_t *out_handle);
int32_t sa_std_compress_supported(uint32_t *out_flags);

/* Crypto additions: bcrypt password hashing and the OS keyring. */
int32_t sa_bcrypt_hash(const uint8_t *pw, uint64_t pw_len, uint32_t cost, uint8_t *out, uint64_t cap, uint64_t *out_len);
int32_t sa_bcrypt_verify(const uint8_t *pw, uint64_t pw_len, const uint8_t *hash, uint64_t hash_len, uint32_t *out_match);
uint32_t sa_keyring_available(void);
int32_t sa_keyring_get(const uint8_t *key, uint64_t key_len, uint8_t *out, uint64_t cap, uint64_t *out_len);
int32_t sa_keyring_remove(const uint8_t *key, uint64_t key_len);
int32_t sa_keyring_set(const uint8_t *collection, uint64_t collection_len, const uint8_t *key, uint64_t key_len, const uint8_t *secret, uint64_t secret_len);

/* DTLS. */
const uint8_t *sa_std_dtls_buffer_data(uint64_t buffer);
int32_t sa_std_dtls_buffer_free(uint64_t buffer);
uint64_t sa_std_dtls_buffer_len(uint64_t buffer);
int32_t sa_std_dtls_server_accept(uint64_t ctx, int32_t fd, uint64_t *out_ssl);
int32_t sa_std_dtls_server_close(uint64_t ssl);
int32_t sa_std_dtls_server_ctx_create(const uint8_t *cert_path, uint64_t cert_path_len, const uint8_t *key_path, uint64_t key_path_len, uint64_t *out_ctx);
int32_t sa_std_dtls_server_ctx_free(uint64_t ctx);
int32_t sa_std_dtls_server_read(uint64_t ssl, uint8_t *out, uint64_t cap, uint64_t *out_read);
int32_t sa_std_dtls_server_write(uint64_t ssl, const uint8_t *buf, uint64_t len, uint64_t *out_written);
int32_t sa_std_dtls_status_json(uint64_t *out_handle);
int32_t sa_std_dtls_supported(uint32_t *out_supported);

/* TOML reader. */
int32_t sa_toml_array_get_i64(uint64_t doc, const uint8_t *path, uint64_t path_len, uint64_t index, int64_t *out_value);
int32_t sa_toml_array_get_string(uint64_t doc, const uint8_t *path, uint64_t path_len, uint64_t index, const uint8_t **out_ptr, uint64_t *out_len);
int32_t sa_toml_array_len(uint64_t doc, const uint8_t *path, uint64_t path_len, uint64_t *out_len);
int32_t sa_toml_array_push_bool(uint64_t doc, const uint8_t *path, uint64_t path_len, uint32_t value);
int32_t sa_toml_array_push_datetime(uint64_t doc, const uint8_t *path, uint64_t path_len, const uint8_t *value, uint64_t value_len);
int32_t sa_toml_array_push_f64(uint64_t doc, const uint8_t *path, uint64_t path_len, double value);
int32_t sa_toml_array_push_i64(uint64_t doc, const uint8_t *path, uint64_t path_len, int64_t value);
int32_t sa_toml_array_push_string(uint64_t doc, const uint8_t *path, uint64_t path_len, const uint8_t *value, uint64_t value_len);
int32_t sa_toml_array_push_table(uint64_t doc, const uint8_t *path, uint64_t path_len);
int32_t sa_toml_free(uint64_t doc);
int32_t sa_toml_get_bool(uint64_t doc, const uint8_t *path, uint64_t path_len, uint32_t *out_value);
int32_t sa_toml_get_datetime(uint64_t doc, const uint8_t *path, uint64_t path_len, const uint8_t **out_ptr, uint64_t *out_len);
int32_t sa_toml_get_f64(uint64_t doc, const uint8_t *path, uint64_t path_len, double *out_value);
int32_t sa_toml_get_i64(uint64_t doc, const uint8_t *path, uint64_t path_len, int64_t *out_value);
int32_t sa_toml_get_string(uint64_t doc, const uint8_t *path, uint64_t path_len, const uint8_t **out_ptr, uint64_t *out_len);
int32_t sa_toml_kind(uint64_t doc, const uint8_t *path, uint64_t path_len, uint32_t *out_kind);
int32_t sa_toml_last_error(const uint8_t **out_ptr, uint64_t *out_len);
uint64_t sa_toml_new(void);
uint64_t sa_toml_parse(const uint8_t *toml_bytes, uint64_t len);
int32_t sa_toml_remove(uint64_t doc, const uint8_t *path, uint64_t path_len);
int32_t sa_toml_set_bool(uint64_t doc, const uint8_t *path, uint64_t path_len, uint32_t value);
int32_t sa_toml_set_datetime(uint64_t doc, const uint8_t *path, uint64_t path_len, const uint8_t *value, uint64_t value_len);
int32_t sa_toml_set_f64(uint64_t doc, const uint8_t *path, uint64_t path_len, double value);
int32_t sa_toml_set_i64(uint64_t doc, const uint8_t *path, uint64_t path_len, int64_t value);
int32_t sa_toml_set_string(uint64_t doc, const uint8_t *path, uint64_t path_len, const uint8_t *value, uint64_t value_len);
int32_t sa_toml_set_table(uint64_t doc, const uint8_t *path, uint64_t path_len);
int32_t sa_toml_stringify(uint64_t doc, const uint8_t **out_ptr, uint64_t *out_len);
int32_t sa_toml_table_key_at(uint64_t doc, const uint8_t *path, uint64_t path_len, uint64_t index, const uint8_t **out_ptr, uint64_t *out_len);
int32_t sa_toml_table_len(uint64_t doc, const uint8_t *path, uint64_t path_len, uint64_t *out_len);

/* fs additions: file-object API and the filesystem watcher. */
int32_t sa_fs_file_close(uint64_t file);
int32_t sa_fs_file_create(const uint8_t *path, uint64_t path_len);
int32_t sa_fs_file_flush(uint64_t file);
int32_t sa_fs_file_open(const uint8_t *path, uint64_t path_len, uint32_t flags);
int32_t sa_fs_file_read(uint64_t file, uint8_t *buf, uint64_t cap);
int32_t sa_fs_file_read_exact(uint64_t file, uint8_t *buf, uint64_t len);
int32_t sa_fs_file_seek(uint64_t file, uint32_t whence, int64_t offset);
int32_t sa_fs_file_write(uint64_t file, const uint8_t *buf, uint64_t len);
int32_t sa_fs_file_write_all(uint64_t file, const uint8_t *buf, uint64_t len);
int32_t sa_fs_watch_add(uint64_t handle, const uint8_t *path, uint64_t path_len, uint32_t mask, int32_t *out_wd);
int32_t sa_fs_watch_close(uint64_t handle);
int32_t sa_fs_watch_create(uint64_t *out_handle);
int32_t sa_fs_watch_next(uint64_t handle, uint32_t *out_ready, int32_t *out_wd, uint32_t *out_mask, uint32_t *out_cookie, uint8_t *name, uint64_t name_cap, uint64_t *out_name_len);
int32_t sa_fs_watch_poll(uint64_t handle, int32_t timeout_ms, uint32_t *out_pending);
int32_t sa_fs_watch_remove(uint64_t handle, int32_t wd);

/* http2 addition. */
int32_t sa_std_http2_client_request_with_settings(const uint8_t *url, uint64_t url_len, const uint8_t *method, uint64_t method_len, const uint8_t *body, uint64_t body_len, const uint8_t *settings, uint64_t settings_len, uint64_t *out_handle);

/* HTTP client. Handles are opaque pointers; integer returns are status codes. */
uint32_t sa_http_client_async_cancel_v2(void *op);
uint32_t sa_http_client_async_free(void *op);
uint32_t sa_http_client_async_free_v2(void *op);
uint32_t sa_http_client_async_poll(void *op, uint8_t *out_ready);
uint32_t sa_http_client_async_poll_v2(void *op, uint32_t timeout_ms, uint8_t *out_ready);
uint32_t sa_http_client_async_take_response(void *op, void **out_resp);
uint32_t sa_http_client_async_take_response_v2(void *op, void **out_resp);
uint32_t sa_http_client_body_reader_free(void *reader);
uint32_t sa_http_client_free(void *client);
uint32_t sa_http_client_new(uint8_t use_tls, void **out_client);
uint32_t sa_http_client_new_v2(uint8_t use_tls, const uint8_t *ca_bundle_path, uint64_t ca_bundle_path_len, void **out_client);
uint32_t sa_http_client_req_add_header(void *req, const uint8_t *key, uint64_t key_len, const uint8_t *val, uint64_t val_len);
uint32_t sa_http_client_req_add_header_v2(void *req, const uint8_t *key, uint64_t key_len, const uint8_t *value, uint64_t value_len);
uint32_t sa_http_client_req_add_openai_auth(void *req, const uint8_t *key, uint64_t key_len);
uint32_t sa_http_client_req_free(void *req);
uint32_t sa_http_client_req_new(void *client, uint8_t method, const uint8_t *url, uint64_t url_len, void **out_req);
uint32_t sa_http_client_req_new_joined(void *client, uint8_t method, const uint8_t *target, uint64_t target_len, const uint8_t *path, uint64_t path_len, uint8_t preserve_base_path, void **out_req);
uint32_t sa_http_client_req_new_v2(void *client, uint8_t method, const uint8_t *url, uint64_t url_len, void **out_req);
uint32_t sa_http_client_req_send(void *req, void **out_resp);
uint32_t sa_http_client_req_send_async(void *req, void **out_op);
uint32_t sa_http_client_req_send_async_v2(void *req, void **out_op);
uint32_t sa_http_client_req_send_v2(void *req, void **out_resp);
uint32_t sa_http_client_req_set_body(void *req, const uint8_t *body, uint64_t body_len);
uint32_t sa_http_client_req_set_body_v2(void *req, const uint8_t *body, uint64_t body_len);
uint32_t sa_http_client_req_set_max_response_bytes_v2(void *req, uint64_t max_bytes);
uint32_t sa_http_client_req_set_timeout_v2(void *req, uint32_t timeout_ms);
uint32_t sa_http_client_req_websocket_connect_unix_v2(void *req, const uint8_t *socket_path, uint64_t socket_path_len, uint32_t timeout_ms, void **out_ws);
uint32_t sa_http_client_req_websocket_connect_v2(void *req, uint32_t timeout_ms, void **out_ws);
uint64_t sa_http_client_resp_body_len(void *resp);
const uint8_t *sa_http_client_resp_body_ptr(void *resp);
uint32_t sa_http_client_resp_body_reader(void *resp, void **out_reader);
uint32_t sa_http_client_resp_free(void *resp);
uint32_t sa_http_client_resp_get_header(void *resp, const uint8_t *key, uint64_t key_len, const uint8_t **out_val, uint64_t *out_len);
uint32_t sa_http_client_resp_read_chunk(void *reader, uint8_t *buf, uint64_t cap, uint64_t *out_len);
uint16_t sa_http_client_resp_status(void *resp);
uint32_t sa_http_client_sse_free(void *handle);
uint32_t sa_http_client_sse_poll(void *handle, uint8_t *out_done);
uint32_t sa_http_client_sse_post(const uint8_t *url, uint64_t url_len, const uint8_t *body, uint64_t body_len, const uint8_t *key, uint64_t key_len, void **out_handle);
uint32_t sa_http_client_sse_read(void *handle, uint8_t *buf, uint64_t buf_cap, uint64_t *out_len);
uint16_t sa_http_client_sse_status(void *handle);
uint32_t sa_http_client_sse_turn(const uint8_t *url, uint64_t url_len, const uint8_t *body, uint64_t body_len, const uint8_t *key, uint64_t key_len, uint64_t api_mode, uint8_t **out_text, uint64_t *out_text_len, uint8_t **out_calls, uint64_t *out_calls_len);
uint32_t sa_http_client_sse_turn_ex(const uint8_t *url, uint64_t url_len, const uint8_t *body, uint64_t body_len, const uint8_t *key, uint64_t key_len, uint64_t api_mode, uint8_t **out_text, uint64_t *out_text_len, uint8_t **out_calls, uint64_t *out_calls_len, uint8_t **out_usage, uint64_t *out_usage_len, uint8_t **out_reasoning, uint64_t *out_reasoning_len);
void sa_http_client_sse_turn_free(uint8_t *buf, uint64_t len);
uint32_t sa_http_client_sse_turn_free_all(uint8_t *text, uint64_t text_len, uint8_t *calls, uint64_t calls_len, uint8_t *usage, uint64_t usage_len, uint8_t *reasoning, uint64_t reasoning_len);
uint32_t sa_http_client_websocket_connect(void *client, const uint8_t *url, uint64_t url_len, void **out_ws);
uint32_t sa_http_client_websocket_connect_unix_v2(void *client, const uint8_t *socket_path, uint64_t socket_path_len, const uint8_t *url, uint64_t url_len, uint32_t timeout_ms, void **out_ws);
uint32_t sa_http_client_websocket_connect_v2(void *client, const uint8_t *url, uint64_t url_len, uint32_t timeout_ms, void **out_ws);
int32_t sa_http_fetch_bytes(const uint8_t *url, uint64_t url_len, uint8_t *buf, uint64_t cap, uint64_t *out_len);
uint32_t sa_http_websocket_close_v2(void *ws, uint16_t code, const uint8_t *reason, uint64_t reason_len);
uint32_t sa_http_websocket_free(void *ws);
uint32_t sa_http_websocket_free_v2(void *ws);
uint32_t sa_http_websocket_poll_v2(void *ws, uint32_t interests, uint32_t timeout_ms, uint32_t *out_events);
uint32_t sa_http_websocket_read(void *ws, uint64_t max_len, uint8_t *out_opcode, const uint8_t **out_ptr, uint64_t *out_len);
uint32_t sa_http_websocket_read_v2(void *ws, uint64_t max_len, uint8_t *out_opcode, const uint8_t **out_ptr, uint64_t *out_len);
uint32_t sa_http_websocket_write(void *ws, uint8_t opcode, const uint8_t *data, uint64_t data_len);
uint32_t sa_http_websocket_write_v2(void *ws, uint8_t opcode, const uint8_t *data, uint64_t data_len, uint64_t *out_written);

/* HTTP cookies: value layer, cookie jar, Netscape persistence. */
int32_t sa_cookie_clear_expiry(uint64_t handle);
int32_t sa_cookie_domain(uint64_t handle, const uint8_t **out_ptr, uint64_t *out_len);
int32_t sa_cookie_domain_match(const uint8_t *domain, uint64_t domain_len, const uint8_t *host, uint64_t host_len, int32_t *out_flag);
int32_t sa_cookie_expires(uint64_t handle, int64_t *out_unix);
int32_t sa_cookie_flags(uint64_t handle, int32_t *out_secure, int32_t *out_http_only, int32_t *out_partitioned);
int32_t sa_cookie_free(uint64_t handle);
uint64_t sa_cookie_header_pair_at(const uint8_t *bytes, uint64_t len, uint64_t index);
int32_t sa_cookie_header_pair_count(const uint8_t *bytes, uint64_t len, uint64_t *out_count);
int32_t sa_cookie_is_expired(uint64_t handle, int64_t now, int32_t *out_flag);
int32_t sa_cookie_is_host_only(uint64_t handle, int32_t *out_flag);
uint64_t sa_cookie_jar_at(uint64_t jar, uint64_t index);
int32_t sa_cookie_jar_clear(uint64_t jar);
int32_t sa_cookie_jar_count(uint64_t jar, uint64_t *out_count);
int32_t sa_cookie_jar_evict_expired(uint64_t jar, int64_t now, uint64_t *out_removed);
int32_t sa_cookie_jar_free(uint64_t jar);
int32_t sa_cookie_jar_header(uint64_t jar, const uint8_t *url, uint64_t url_len, int64_t now, const uint8_t **out_ptr, uint64_t *out_len);
int32_t sa_cookie_jar_load(uint64_t jar, const uint8_t *path, uint64_t path_len, uint64_t *out_loaded);
uint64_t sa_cookie_jar_new(void);
int32_t sa_cookie_jar_policy(uint64_t jar, uint32_t *out_policy);
int32_t sa_cookie_jar_request_header(uint64_t jar, const uint8_t *url, uint64_t url_len, const uint8_t **out_ptr, uint64_t *out_len);
int32_t sa_cookie_jar_save(uint64_t jar, const uint8_t *path, uint64_t path_len);
int32_t sa_cookie_jar_set_policy(uint64_t jar, uint32_t policy);
int32_t sa_cookie_jar_store(uint64_t jar, const uint8_t *url, uint64_t url_len, const uint8_t *set_cookie, uint64_t set_cookie_len, int64_t now, uint32_t *out_result);
int32_t sa_cookie_jar_store_response(uint64_t jar, const uint8_t *url, uint64_t url_len, const uint8_t *set_cookie, uint64_t set_cookie_len);
int32_t sa_cookie_last_error(const uint8_t **out_ptr, uint64_t *out_len);
int32_t sa_cookie_max_age(uint64_t handle, int64_t *out_secs);
int32_t sa_cookie_name(uint64_t handle, const uint8_t **out_ptr, uint64_t *out_len);
uint64_t sa_cookie_new(const uint8_t *name, uint64_t name_len, const uint8_t *value, uint64_t value_len);
uint64_t sa_cookie_parse_set_cookie(const uint8_t *bytes, uint64_t len);
int32_t sa_cookie_path(uint64_t handle, const uint8_t **out_ptr, uint64_t *out_len);
int32_t sa_cookie_path_match(const uint8_t *cookie_path, uint64_t cookie_path_len, const uint8_t *request_path, uint64_t request_path_len, int32_t *out_flag);
int32_t sa_cookie_same_site(uint64_t handle, uint32_t *out_mode);
int32_t sa_cookie_serialize(uint64_t handle, const uint8_t **out_ptr, uint64_t *out_len);
int32_t sa_cookie_serialize_pair(uint64_t handle, const uint8_t **out_ptr, uint64_t *out_len);
int32_t sa_cookie_set_domain(uint64_t handle, const uint8_t *bytes, uint64_t len);
int32_t sa_cookie_set_expires(uint64_t handle, int64_t unix_seconds);
int32_t sa_cookie_set_http_only(uint64_t handle, int32_t on);
int32_t sa_cookie_set_max_age(uint64_t handle, int64_t secs);
int32_t sa_cookie_set_partitioned(uint64_t handle, int32_t on);
int32_t sa_cookie_set_path(uint64_t handle, const uint8_t *bytes, uint64_t len);
int32_t sa_cookie_set_same_site(uint64_t handle, uint32_t mode);
int32_t sa_cookie_set_secure(uint64_t handle, int32_t on);
int32_t sa_cookie_value(uint64_t handle, const uint8_t **out_ptr, uint64_t *out_len);

/* HTTP server. Handles are opaque pointers; integer returns are status codes. */
uint32_t sa_http_server_accept(void *server, void **out_req);
uint32_t sa_http_server_accept_v2(void *server, uint32_t timeout_ms, void **out_req);
uint32_t sa_http_server_free(void *server);
uint32_t sa_http_server_free_v2(void *server);
uint32_t sa_http_server_new(void **out_server);
uint32_t sa_http_server_new_v2(void **out_server);
uint32_t sa_http_server_req_free(void *req);
uint32_t sa_http_server_req_free_v2(void *req);
uint32_t sa_http_server_req_get_body(void *req, const uint8_t **out_body, uint64_t *out_len);
uint32_t sa_http_server_req_get_header(void *req, const uint8_t *key, uint64_t key_len, const uint8_t **out_val, uint64_t *out_len);
uint32_t sa_http_server_req_get_method(void *req, const uint8_t **out_method, uint64_t *out_len);
uint32_t sa_http_server_req_get_path(void *req, const uint8_t **out_path, uint64_t *out_len);
uint32_t sa_http_server_resp_add_header_v2(void *resp, const uint8_t *name, uint64_t name_len, const uint8_t *value, uint64_t value_len);
uint32_t sa_http_server_resp_free(void *resp);
uint32_t sa_http_server_resp_free_v2(void *resp);
uint32_t sa_http_server_resp_new(void *req, uint16_t status, void **out_resp);
uint32_t sa_http_server_resp_new_v2(void *req, uint16_t status, void **out_resp);
uint32_t sa_http_server_resp_send(void *resp, const uint8_t *body, uint64_t body_len);
uint32_t sa_http_server_resp_send_v2(void *resp, const uint8_t *body, uint64_t body_len, uint32_t timeout_ms);
uint32_t sa_http_server_resp_send_head_v2(void *resp, uint64_t content_length, uint32_t timeout_ms);
uint32_t sa_http_server_req_peer_addr_v2(void *req, uint8_t *out, uint64_t out_cap, uint64_t *out_len, uint32_t *out_port);
uint32_t sa_http_server_resp_set_content_type(void *resp, const uint8_t *content_type, uint64_t content_type_len);
uint32_t sa_http_server_resp_stream_add_header_v2(void *resp, const uint8_t *name, uint64_t name_len, const uint8_t *value, uint64_t value_len);
uint32_t sa_http_server_resp_stream_end(void *resp);
uint32_t sa_http_server_resp_stream_end_v2(void *resp, uint32_t timeout_ms);
uint32_t sa_http_server_resp_stream_flush(void *resp);
uint32_t sa_http_server_resp_stream_flush_v2(void *resp);
uint32_t sa_http_server_resp_stream_free(void *resp);
uint32_t sa_http_server_resp_stream_free_v2(void *resp);
uint32_t sa_http_server_resp_stream_new(void *req, uint16_t status, void **out_resp);
uint32_t sa_http_server_resp_stream_new_v2(void *req, uint16_t status, void **out_resp);
uint32_t sa_http_server_resp_stream_write(void *resp, const uint8_t *body, uint64_t body_len);
uint32_t sa_http_server_resp_stream_write_v2(void *resp, const uint8_t *body, uint64_t body_len, uint32_t timeout_ms);
uint32_t sa_http_server_serve_threaded(void *server, uint32_t num_threads, void (*handler)(void *, void *), void *handler_ctx, uint64_t max_requests);
uint32_t sa_http_server_set_max_body_bytes(void *server, uint64_t max_bytes);
uint32_t sa_http_server_start(void *server, const uint8_t *host, uint64_t host_len, uint16_t port);
uint32_t sa_http_server_start_v2(void *server, const uint8_t *host, uint64_t host_len, uint16_t port);
uint32_t sa_http_server_stop_serving(void *server);
uint32_t sa_http_server_websocket_close_v2(void *ws, uint16_t code, const uint8_t *reason, uint64_t reason_len);
uint32_t sa_http_server_websocket_free(void *ws);
uint32_t sa_http_server_websocket_free_v2(void *ws);
uint32_t sa_http_server_websocket_poll_v2(void *ws, uint32_t interests, uint32_t timeout_ms, uint32_t *out_events);
uint32_t sa_http_server_websocket_read(void *ws, uint64_t max_len, uint8_t *out_opcode, const uint8_t **out_data, uint64_t *out_len);
uint32_t sa_http_server_websocket_read_v2(void *ws, uint64_t max_len, uint8_t *out_opcode, const uint8_t **out_data, uint64_t *out_len);
uint32_t sa_http_server_websocket_upgrade(void *req, void **out_ws);
uint32_t sa_http_server_websocket_upgrade_v2(void *req, void **out_ws);
uint32_t sa_http_server_websocket_write(void *ws, uint8_t opcode, const uint8_t *data, uint64_t data_len);
uint32_t sa_http_server_websocket_write_v2(void *ws, uint8_t opcode, const uint8_t *data, uint64_t data_len, uint64_t *out_written);

/* Module state slots. */
uint64_t sa_modstate_get_u64(uint64_t key);
int32_t sa_modstate_set_u64(uint64_t key, uint64_t value);

/* Multipart form data. */
const uint8_t *sa_std_multipart_buffer_data(uint64_t buffer);
int32_t sa_std_multipart_buffer_free(uint64_t buffer);
uint64_t sa_std_multipart_buffer_len(uint64_t buffer);
int32_t sa_std_multipart_builder_add_field(uint64_t handle, const uint8_t *name, uint64_t name_len, const uint8_t *value, uint64_t value_len);
int32_t sa_std_multipart_builder_add_file(uint64_t handle, const uint8_t *name, uint64_t name_len, const uint8_t *filename, uint64_t filename_len, const uint8_t *content_type, uint64_t content_type_len, const uint8_t *data, uint64_t data_len);
int32_t sa_std_multipart_builder_boundary(uint64_t handle, uint8_t *out, uint64_t cap, uint64_t *out_len);
int32_t sa_std_multipart_builder_content_type(uint64_t handle, uint8_t *out, uint64_t cap, uint64_t *out_len);
int32_t sa_std_multipart_builder_finish(uint64_t handle, uint64_t *out_handle);
int32_t sa_std_multipart_builder_free(uint64_t handle);
int32_t sa_std_multipart_builder_new(uint64_t *out_handle);
uint64_t sa_std_multipart_count(uint64_t handle);
int32_t sa_std_multipart_free(uint64_t handle);
int32_t sa_std_multipart_parse(const uint8_t *body, uint64_t body_len, const uint8_t *content_type, uint64_t content_type_len, uint64_t *out_handle);
int32_t sa_std_multipart_part_body(uint64_t handle, uint64_t index, const uint8_t **out_ptr, uint64_t *out_len);
int32_t sa_std_multipart_part_content_type(uint64_t handle, uint64_t index, uint8_t *out, uint64_t cap, uint64_t *out_len);
int32_t sa_std_multipart_part_filename(uint64_t handle, uint64_t index, uint8_t *out, uint64_t cap, uint64_t *out_len);
int32_t sa_std_multipart_part_header(uint64_t handle, uint64_t index, const uint8_t *name, uint64_t name_len, uint8_t *out, uint64_t cap, uint64_t *out_len);
int32_t sa_std_multipart_part_name(uint64_t handle, uint64_t index, uint8_t *out, uint64_t cap, uint64_t *out_len);

/* net additions: short-name aliases, socket option passthrough, datagram surface. */
sa_std_fallible_u64 sa_net_tcp_connect(const uint8_t *host, uint64_t host_len, uint32_t port);
sa_std_fallible_u64 sa_net_tcp_listener_accept(uint64_t listener);
sa_std_fallible_u64 sa_net_tcp_listener_bind(const uint8_t *host, uint64_t host_len, uint16_t port);
sa_std_fallible_i32 sa_net_tcp_listener_close(uint64_t listener);
sa_std_fallible_u64 sa_net_tcp_listener_local_addr(uint64_t listener);
sa_std_fallible_i32 sa_net_tcp_stream_close(uint64_t stream);
int32_t sa_net_tcp_stream_flush(uint64_t stream);
int32_t sa_net_tcp_stream_peer_addr(uint64_t stream);
sa_std_fallible_u64 sa_net_tcp_stream_read(uint64_t stream, uint8_t *buf, uint64_t cap);
int32_t sa_net_tcp_stream_shutdown(uint64_t stream, uint32_t how);
int32_t sa_net_tcp_stream_write(uint64_t stream, const uint8_t *buf, uint64_t len);
sa_std_fallible_i32 sa_net_tcp_stream_write_all(uint64_t stream, const uint8_t *buf, uint64_t len);
int32_t sa_net_udp_bind(const uint8_t *host, uint64_t host_len, uint16_t port);
int32_t sa_net_udp_local_addr(uint64_t socket);
int32_t sa_net_udp_peek(uint64_t socket, uint8_t *buf, uint64_t cap);
int32_t sa_net_udp_peek_from(uint64_t socket, uint8_t *buf, uint64_t cap, uint64_t *out_addr);
int32_t sa_net_udp_recv_from(uint64_t socket, uint8_t *buf, uint64_t cap, uint64_t *out_addr);
int32_t sa_net_udp_send_to(uint64_t socket, const uint8_t *buf, uint64_t len, const uint8_t *host, uint64_t host_len, uint16_t port);
int32_t sa_std_net_addr_reverse_lookup(uint64_t addr, uint8_t *out, uint64_t out_cap, uint64_t *out_len);
int32_t sa_std_net_ja3_hash(const uint8_t *ja3, uint64_t ja3_len, uint8_t *out, uint64_t out_cap, uint64_t *out_len);
int32_t sa_std_net_ja4_hash12(const uint8_t *data, uint64_t data_len, uint8_t *out, uint64_t out_cap, uint64_t *out_len);
int32_t sa_std_net_sha256_hex(const uint8_t *input, uint64_t input_len, uint8_t *out, uint64_t out_cap, uint64_t *out_len);
int32_t sa_std_net_socket_getsockopt(uint64_t handle, int32_t level, uint32_t optname, uint8_t *out, uint64_t out_cap, uint64_t *out_len);
int32_t sa_std_net_socket_getsockopt_int(uint64_t handle, int32_t level, uint32_t optname, int32_t *out_value);
int32_t sa_std_net_socket_setsockopt(uint64_t handle, int32_t level, uint32_t optname, const uint8_t *value, uint64_t value_len);
int32_t sa_std_net_socket_setsockopt_int(uint64_t handle, int32_t level, uint32_t optname, int32_t value);
int32_t sa_std_net_udp_recv_msg(uint64_t socket, uint8_t *buf, uint64_t cap, uint64_t *out_read, uint64_t *out_addr, uint64_t *out_dest_addr, uint32_t *out_ifindex, uint64_t *out_timestamp_ns, uint32_t *out_flags);
int32_t sa_std_net_udp_recv_multi(uint64_t socket, uint8_t *buf, uint64_t buf_cap, uint64_t slot_size, uint64_t max_msgs, uint64_t *out_count, uint64_t *out_lens, uint64_t *out_addrs);
int32_t sa_std_net_unix_datagram_peer_cred(uint64_t socket, int32_t *out_pid, uint32_t *out_uid, uint32_t *out_gid);
int32_t sa_std_url_parse(const uint8_t *url, uint64_t url_len, uint8_t *scheme_out, uint64_t scheme_cap, uint64_t *scheme_len, uint8_t *host_out, uint64_t host_cap, uint64_t *host_len, uint8_t *path_out, uint64_t path_cap, uint64_t *path_len, uint32_t *out_port);
int32_t sa_std_ws_accept_key(const uint8_t *key, uint64_t key_len, uint8_t *out, uint64_t out_cap, uint64_t *out_len);
int32_t sa_std_ws_frame_build(uint32_t opcode, uint32_t fin, const uint8_t *payload, uint64_t payload_len, const uint8_t *mask, uint8_t *out, uint64_t out_cap, uint64_t *out_len);
int32_t sa_std_ws_frame_build_unmasked(uint32_t opcode, uint32_t fin, const uint8_t *payload, uint64_t payload_len, uint8_t *out, uint64_t out_cap, uint64_t *out_len);
int32_t sa_std_ws_frame_parse(const uint8_t *data, uint64_t data_len, uint8_t *out_fin, uint8_t *out_opcode, uint8_t *out_masked, uint64_t *out_payload_offset, uint64_t *out_payload_len, uint64_t *out_frame_len, uint8_t *out_mask);
int32_t sa_std_ws_unmask(uint8_t *payload, uint64_t payload_len, const uint8_t *mask);

/* Network interface information. */
int32_t sa_std_net_interface_addresses_json(uint64_t *out_handle);

/* netx: io_uring reactor surface. */
typedef struct SaNetxTicket {
    uint32_t slot_id;
    uint16_t op_code;
    uint8_t proto;
    uint8_t flags;
    uint8_t *payload;
    uint32_t payload_len;
    uint32_t pad;
} SaNetxTicket;

int32_t sa_netx_broadcast(uint32_t reactor_id, const uint32_t *slot_ids, uint32_t n, const uint8_t *msg, uint32_t len);
int32_t sa_netx_close_slot(uint32_t slot_id);
int32_t sa_netx_init(uint64_t slot_capacity, uint32_t reactor_count);
int32_t sa_netx_listen(const uint8_t *host, uint64_t host_len, uint16_t port);
int32_t sa_netx_push_outbound(uint32_t reactor_id, uint32_t slot_id, const uint8_t *msg, uint32_t len);
int32_t sa_netx_recv_ticket(uint32_t reactor_id, SaNetxTicket *out_ticket);
int32_t sa_netx_shutdown(void);

/* QUIC and HTTP/3. */
int32_t sa_std_http3_constants_json(uint64_t *out_handle);
int32_t sa_std_http3_request_field(uint64_t session, int64_t stream_id, const uint8_t *name, uint64_t name_len, uint8_t *out, uint64_t out_cap, uint64_t *out_len);
int32_t sa_std_http3_response_status(uint64_t session, int64_t stream_id, uint32_t *out_status);
int32_t sa_std_http3_server_next_request(uint64_t session, int64_t *out_stream_id);
int32_t sa_std_http3_session_bind(uint64_t session, uint64_t quic_conn);
int32_t sa_std_http3_session_create(uint64_t *out_handle);
int32_t sa_std_http3_session_destroy(uint64_t session);
int32_t sa_std_http3_stream_read(uint64_t session, int64_t stream_id, uint8_t *out, uint64_t out_cap, uint64_t *out_read, uint32_t *out_fin);
int32_t sa_std_http3_submit_request(uint64_t session, const uint8_t *method, uint64_t method_len, const uint8_t *authority, uint64_t authority_len, const uint8_t *path, uint64_t path_len, const uint8_t *body, uint64_t body_len, int64_t *out_stream_id);
int32_t sa_std_http3_submit_response(uint64_t session, int64_t stream_id, uint32_t status, const uint8_t *body, uint64_t body_len);
int32_t sa_std_http3_supported(uint32_t *out_supported);
const uint8_t *sa_std_quic_buffer_data(uint64_t buffer);
int32_t sa_std_quic_buffer_free(uint64_t buffer);
uint64_t sa_std_quic_buffer_len(uint64_t buffer);
int32_t sa_std_quic_capabilities_json(uint64_t *out_handle);
int32_t sa_std_quic_client_connect(uint64_t endpoint, const uint8_t *host, uint64_t host_len, uint32_t port, const uint8_t *server_name, uint64_t server_name_len, const uint8_t *ca_file, uint64_t ca_file_len, const uint8_t *alpn, uint64_t alpn_len, uint64_t *out_conn);
int32_t sa_std_quic_conn_close(uint64_t conn);
int32_t sa_std_quic_conn_handshake_completed(uint64_t conn, uint32_t *out_done);
int32_t sa_std_quic_conn_poll(uint64_t conn, uint32_t timeout_ms);
int32_t sa_std_quic_constants_json(uint64_t *out_handle);
int32_t sa_std_quic_endpoint_create(uint64_t *out_handle);
int32_t sa_std_quic_endpoint_destroy(uint64_t endpoint);
int32_t sa_std_quic_server_accept(uint64_t endpoint, uint64_t *out_conn);
int32_t sa_std_quic_server_listen(uint64_t endpoint, uint32_t port, const uint8_t *cert_file, uint64_t cert_file_len, const uint8_t *key_file, uint64_t key_file_len);
int32_t sa_std_quic_server_poll(uint64_t endpoint, uint32_t timeout_ms);
int32_t sa_std_quic_stream_open(uint64_t conn, int64_t *out_stream_id);
int32_t sa_std_quic_stream_read(uint64_t conn, int64_t stream_id, uint8_t *out, uint64_t out_cap, uint64_t *out_read, uint32_t *out_fin);
int32_t sa_std_quic_stream_write(uint64_t conn, int64_t stream_id, const uint8_t *data, uint64_t data_len, uint32_t fin, uint64_t *out_written);
int32_t sa_std_quic_supported(uint32_t *out_supported);

/* SSH: client, server, SFTP. */
int32_t sa_std_ssh_auth_keyfile(void *session, const uint8_t *user, uint64_t user_len, const uint8_t *pub_path, uint64_t pub_path_len, const uint8_t *priv_path, uint64_t priv_path_len, const uint8_t *passphrase, uint64_t passphrase_len);
int32_t sa_std_ssh_auth_password(void *session, const uint8_t *user, uint64_t user_len, const uint8_t *password, uint64_t password_len);
const uint8_t *sa_std_ssh_buffer_data(uint64_t buffer);
int32_t sa_std_ssh_buffer_free(uint64_t buffer);
uint64_t sa_std_ssh_buffer_len(uint64_t buffer);
int32_t sa_std_ssh_channel_close(void *channel);
int32_t sa_std_ssh_channel_read(void *channel, uint32_t stream, uint8_t *out, uint64_t cap, uint64_t *out_read);
int32_t sa_std_ssh_channel_send_exit(void *channel, int32_t exit_code);
int32_t sa_std_ssh_channel_write(void *channel, uint32_t stream, const uint8_t *data, uint64_t data_len, uint64_t *out_written);
int32_t sa_std_ssh_client_connect(const uint8_t *host, uint64_t host_len, uint32_t port, void **out_session);
int32_t sa_std_ssh_exec(void *session, const uint8_t *command, uint64_t command_len, uint64_t *out_stdout, uint64_t *out_stderr, int32_t *out_exit);
int32_t sa_std_ssh_hostkey_fingerprint(void *session, uint8_t *out, uint64_t cap, uint64_t *out_len);
int32_t sa_std_ssh_server_accept(void *bind, void **out_session);
int32_t sa_std_ssh_server_auth_accept(void *session);
int32_t sa_std_ssh_server_auth_deny(void *session);
int32_t sa_std_ssh_server_auth_next(void *session, uint32_t *out_kind, uint64_t *out_user, uint64_t *out_secret, int32_t *out_state);
int32_t sa_std_ssh_server_bind_close(void *bind);
int32_t sa_std_ssh_server_channel_accept(void *session, void **out_channel);
int32_t sa_std_ssh_server_channel_exec(void *session, uint32_t *out_kind, uint64_t *out_command);
int32_t sa_std_ssh_server_listen(const uint8_t *bind_addr, uint64_t bind_addr_len, uint32_t port, const uint8_t *hostkey_path, uint64_t hostkey_path_len, void **out_bind);
int32_t sa_std_ssh_server_session_close(void *session);
int32_t sa_std_ssh_session_close(void *session);
int32_t sa_std_ssh_sftp_read(void *session, const uint8_t *path, uint64_t path_len, uint64_t *out_handle);
int32_t sa_std_ssh_sftp_stat(void *session, const uint8_t *path, uint64_t path_len, uint64_t *out_size, uint32_t *out_is_dir);
int32_t sa_std_ssh_sftp_write(void *session, const uint8_t *path, uint64_t path_len, const uint8_t *data, uint64_t data_len);
int32_t sa_std_ssh_supported(uint32_t *out_flags);

/* Terminal additions: PTY surface. */
typedef struct SaPtyArgvEntry {
    const uint8_t *ptr;
    uint64_t len;
} SaPtyArgvEntry;

int32_t sa_pty_close(uint64_t handle);
int32_t sa_pty_kill(uint64_t handle, uint32_t sig);
int32_t sa_pty_pid(uint64_t handle, int32_t *out_pid);
int32_t sa_pty_poll(uint64_t handle, int32_t timeout_ms, uint32_t *out_events);
int32_t sa_pty_read(uint64_t handle, uint8_t *buf, uint64_t cap, uint64_t *out_read);
int32_t sa_pty_resize(uint64_t handle, uint16_t cols, uint16_t rows);
int32_t sa_pty_spawn(const uint8_t *file, uint64_t file_len, const SaPtyArgvEntry *argv, uint64_t argv_len, uint16_t cols, uint16_t rows, uint64_t *out_handle);
int32_t sa_pty_try_wait(uint64_t handle, uint32_t *out_done, int32_t *out_status);
int32_t sa_pty_winsize(uint64_t handle, uint16_t *out_cols, uint16_t *out_rows);
int32_t sa_pty_write(uint64_t handle, const uint8_t *buf, uint64_t len, uint64_t *out_written);

/* Thread-local slots. */
uint64_t *sa_thread_local_slot(uint64_t key);
int32_t sa_thread_local_supported(uint32_t *out_supported);

/* TLS client, including the shaped-profile surface. */
int32_t sa_std_tls_client_add_ca_file(const uint8_t *path, uint64_t path_len);
const uint8_t *sa_std_tls_client_buffer_data(uint64_t buffer);
int32_t sa_std_tls_client_buffer_free(uint64_t buffer);
uint64_t sa_std_tls_client_buffer_len(uint64_t buffer);
int32_t sa_std_tls_client_close(uint64_t handle);
int32_t sa_std_tls_client_config_add_ca_file(uint64_t config, const uint8_t *path, uint64_t path_len);
int32_t sa_std_tls_client_config_add_ca_memory(uint64_t config, const uint8_t *pem, uint64_t pem_len);
int32_t sa_std_tls_client_config_free(uint64_t config);
int32_t sa_std_tls_client_config_new(uint64_t *out_config);
int32_t sa_std_tls_client_config_set_insecure_no_verification(uint64_t config, uint32_t enabled);
int32_t sa_std_tls_client_config_set_server_name(uint64_t config, const uint8_t *name, uint64_t name_len);
int32_t sa_std_tls_client_config_set_verify_self_signed(uint64_t config, uint32_t enabled);
int32_t sa_std_tls_client_connect(const uint8_t *host, uint64_t host_len, uint32_t port, uint64_t *out_handle);
int32_t sa_std_tls_client_connect_config(const uint8_t *host, uint64_t host_len, uint32_t port, uint64_t config, uint64_t *out_handle);
int32_t sa_std_tls_client_peer_cert_json(uint64_t handle, uint64_t *out_handle);
int32_t sa_std_tls_client_read(uint64_t handle, uint8_t *buf, uint64_t cap, uint64_t *out_read);
int32_t sa_std_tls_client_start_tls(int32_t fd, const uint8_t *host, uint64_t host_len, uint64_t config, uint64_t *out_handle);
int32_t sa_std_tls_client_status_json(uint64_t *out_handle);
int32_t sa_std_tls_client_supported(uint32_t *out_supported);
int32_t sa_std_tls_client_write(uint64_t handle, const uint8_t *buf, uint64_t len, uint64_t *out_written);
const uint8_t *sa_std_tls_shaped_buffer_data(uint64_t buffer);
int32_t sa_std_tls_shaped_buffer_free(uint64_t buffer);
uint64_t sa_std_tls_shaped_buffer_len(uint64_t buffer);
int32_t sa_std_tls_shaped_close(uint64_t handle);
int32_t sa_std_tls_shaped_connect(const uint8_t *host, uint64_t host_len, uint32_t port, const uint8_t *profile, uint64_t profile_len, uint64_t *out_handle);
int32_t sa_std_tls_shaped_hello_ja3(uint64_t handle, uint8_t *out, uint64_t out_cap, uint64_t *out_len);
int32_t sa_std_tls_shaped_hello_ja3_string(uint64_t handle, uint8_t *out, uint64_t out_cap, uint64_t *out_len);
int32_t sa_std_tls_shaped_hello_ja4(uint64_t handle, uint8_t *out, uint64_t out_cap, uint64_t *out_len);
int32_t sa_std_tls_shaped_negotiated_json(uint64_t handle, uint64_t *out_handle);
int32_t sa_std_tls_shaped_peer_cert_chain_json(uint64_t handle, uint64_t *out_handle);
int32_t sa_std_tls_shaped_read(uint64_t handle, uint8_t *buf, uint64_t cap, uint64_t *out_read);
int32_t sa_std_tls_shaped_session_blob(uint64_t handle, uint64_t *out_handle);
int32_t sa_std_tls_shaped_start_tls(int32_t fd, const uint8_t *host, uint64_t host_len, const uint8_t *profile, uint64_t profile_len, uint64_t *out_handle);
int32_t sa_std_tls_shaped_supported(uint32_t *out_supported);
int32_t sa_std_tls_shaped_write(uint64_t handle, const uint8_t *buf, uint64_t len, uint64_t *out_written);

/* TLS server. */
int32_t sa_std_tls_server_accept(uint64_t ctx, int32_t fd, uint64_t *out_ssl);
const uint8_t *sa_std_tls_server_buffer_data(uint64_t buffer);
int32_t sa_std_tls_server_buffer_free(uint64_t buffer);
uint64_t sa_std_tls_server_buffer_len(uint64_t buffer);
int32_t sa_std_tls_server_close(uint64_t ssl);
int32_t sa_std_tls_server_ctx_create(const uint8_t *cert_path, uint64_t cert_path_len, const uint8_t *key_path, uint64_t key_path_len, uint64_t *out_ctx);
int32_t sa_std_tls_server_ctx_create_memory(const uint8_t *cert_pem, uint64_t cert_pem_len, const uint8_t *key_pem, uint64_t key_pem_len, uint64_t *out_ctx);
int32_t sa_std_tls_server_ctx_free(uint64_t ctx);
int32_t sa_std_tls_server_ctx_require_client_cert(uint64_t ctx, const uint8_t *ca_path, uint64_t ca_path_len);
int32_t sa_std_tls_server_ctx_set_alpn(uint64_t ctx, const uint8_t *protos, uint64_t protos_len);
int32_t sa_std_tls_server_ctx_set_version_bounds(uint64_t ctx, uint32_t min_version, uint32_t max_version);
int32_t sa_std_tls_server_negotiated_json(uint64_t ssl, uint64_t *out_handle);
int32_t sa_std_tls_server_peer_cert_chain_json(uint64_t ssl, uint64_t *out_handle);
int32_t sa_std_tls_server_read(uint64_t ssl, uint8_t *out, uint64_t cap, uint64_t *out_read);
int32_t sa_std_tls_server_session_verify_result(uint64_t ssl, uint32_t *out_code);
int32_t sa_std_tls_server_status_json(uint64_t *out_handle);
int32_t sa_std_tls_server_supported(uint32_t *out_supported);
int32_t sa_std_tls_server_write(uint64_t ssl, const uint8_t *buf, uint64_t len, uint64_t *out_written);

/* Tree-sitter. */
uint32_t sa_ts_available(void);
int32_t sa_ts_node_byte_range(uint64_t handle, uint32_t *out_start, uint32_t *out_end);
int32_t sa_ts_node_child(uint64_t handle, uint32_t index, uint32_t named, uint64_t *out_node);
int32_t sa_ts_node_child_by_field(uint64_t handle, const uint8_t *field, uint64_t field_len, uint64_t *out_node);
int32_t sa_ts_node_child_count(uint64_t handle, uint32_t *out_count);
int32_t sa_ts_node_end_point(uint64_t handle, uint32_t *out_row, uint32_t *out_col);
int32_t sa_ts_node_free(uint64_t handle);
int32_t sa_ts_node_has_error(uint64_t handle, uint32_t *out_flag);
int32_t sa_ts_node_is_missing(uint64_t handle, uint32_t *out_flag);
int32_t sa_ts_node_is_named(uint64_t handle, uint32_t *out_flag);
int32_t sa_ts_node_named_child_count(uint64_t handle, uint32_t *out_count);
int32_t sa_ts_node_parent(uint64_t handle, uint64_t *out_node);
int32_t sa_ts_node_start_point(uint64_t handle, uint32_t *out_row, uint32_t *out_col);
int32_t sa_ts_node_text(uint64_t handle, uint8_t *buf, uint64_t cap, uint64_t *out_len);
int32_t sa_ts_node_type(uint64_t handle, uint8_t *buf, uint64_t cap, uint64_t *out_len);
int32_t sa_ts_parse(uint64_t handle, const uint8_t *src, uint64_t src_len, uint64_t *out_tree);
int32_t sa_ts_parse_incremental(uint64_t handle, uint64_t old_tree, const uint8_t *src, uint64_t src_len, uint64_t *out_tree);
int32_t sa_ts_parser_free(uint64_t handle);
int32_t sa_ts_parser_new(uint64_t *out_handle);
int32_t sa_ts_parser_set_language(uint64_t handle, const uint8_t *name, uint64_t name_len);
int32_t sa_ts_query_capture_count(uint64_t handle, uint32_t *out_count);
int32_t sa_ts_query_capture_name(uint64_t handle, uint32_t index, uint8_t *buf, uint64_t cap, uint64_t *out_len);
int32_t sa_ts_query_cursor_free(uint64_t handle);
int32_t sa_ts_query_cursor_new(uint64_t *out_cursor);
int32_t sa_ts_query_exec(uint64_t cursor, uint64_t query, uint64_t node);
int32_t sa_ts_query_free(uint64_t handle);
int32_t sa_ts_query_match_capture(uint64_t cursor, uint32_t index, uint64_t *out_node, uint32_t *out_capture);
int32_t sa_ts_query_new(const uint8_t *lang, uint64_t lang_len, const uint8_t *src, uint64_t src_len, uint64_t *out_query, uint32_t *out_err_offset, uint32_t *out_err_kind);
int32_t sa_ts_query_next_match(uint64_t cursor, uint32_t *out_has, uint32_t *out_pattern, uint32_t *out_captures);
int32_t sa_ts_query_pattern_count(uint64_t handle, uint32_t *out_count);
int32_t sa_ts_tree_edit(uint64_t handle, uint32_t start_byte, uint32_t old_end_byte, uint32_t new_end_byte, uint32_t start_row, uint32_t start_col, uint32_t old_end_row, uint32_t old_end_col, uint32_t new_end_row, uint32_t new_end_col);
int32_t sa_ts_tree_free(uint64_t handle);
int32_t sa_ts_tree_root(uint64_t handle, uint64_t *out_node);
int32_t sa_ts_tree_sexp(uint64_t handle, uint8_t *buf, uint64_t cap, uint64_t *out_len);

/* WebSocket client. */
int32_t sa_std_ws_client_add_ca_file(const uint8_t *path, uint64_t path_len);
const uint8_t *sa_std_ws_client_buffer_data(uint64_t buffer);
int32_t sa_std_ws_client_buffer_free(uint64_t buffer);
uint64_t sa_std_ws_client_buffer_len(uint64_t buffer);
int32_t sa_std_ws_client_close(uint64_t handle, uint16_t code, const uint8_t *reason, uint64_t reason_len);
int32_t sa_std_ws_client_connect(const uint8_t *url, uint64_t url_len, uint64_t *out_handle);
int32_t sa_std_ws_client_ping(uint64_t handle, const uint8_t *buf, uint64_t len);
int32_t sa_std_ws_client_recv(uint64_t handle, uint32_t *out_opcode, uint64_t *out_buf_handle);
int32_t sa_std_ws_client_send_binary(uint64_t handle, const uint8_t *buf, uint64_t len);
int32_t sa_std_ws_client_send_text(uint64_t handle, const uint8_t *buf, uint64_t len);
int32_t sa_std_ws_client_status_json(uint64_t *out_handle);
int32_t sa_std_ws_client_supported(uint32_t *out_supported);

#ifdef __cplusplus
}
#endif

#endif
