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
uint64_t sa_deno_args_json(void);
uint64_t sa_deno_btoa(const uint8_t *data, uint64_t len);
uint64_t sa_deno_atob(const uint8_t *data_base64, uint64_t data_base64_len);
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
uint64_t sa_regex_group_count(uint64_t regex);
int32_t sa_regex_free(uint64_t regex);
int32_t sa_regex_match_free(uint64_t match);

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
int32_t sa_std_net_tcp_connect_timeout(const uint8_t *host, uint64_t host_len, uint32_t port, uint64_t timeout_ns, uint64_t *out_handle);
int32_t sa_std_net_tcp_connect_timeout_all(const uint8_t *host, uint64_t host_len, uint32_t port, uint64_t timeout_ns, uint64_t *out_handle);
int32_t sa_std_net_to_socket_addr_first(const uint8_t *host, uint64_t host_len, uint32_t port, uint64_t *out_handle);
int32_t sa_std_net_to_socket_addr_list(const uint8_t *host, uint64_t host_len, uint32_t port, uint64_t *out_handle);
int32_t sa_std_net_addr_list_next(uint64_t list, int32_t *out_ok, uint64_t *out_addr);
int32_t sa_std_net_addr_list_remaining(uint64_t list, uint64_t *out_remaining);
int32_t sa_std_net_addr_list_reset(uint64_t list);
int32_t sa_std_net_addr_list_free(uint64_t list);
int32_t sa_std_net_tcp_listen(const uint8_t *host, uint64_t host_len, uint32_t port, uint64_t *out_handle, uint32_t *out_bound_port);
int32_t sa_std_net_tcp_accept(uint64_t listener_handle, uint64_t *out_handle);
int32_t sa_std_net_tcp_listener_local_addr(uint64_t listener_handle, uint64_t *out_handle);
int32_t sa_std_net_tcp_stream_read(uint64_t stream_handle, uint8_t *out, uint64_t cap, uint64_t *out_read);
int32_t sa_std_net_tcp_stream_peek(uint64_t stream_handle, uint8_t *out, uint64_t cap, uint64_t *out_read);
int32_t sa_std_net_tcp_stream_write(uint64_t stream_handle, const uint8_t *buf, uint64_t len, uint64_t *out_written);
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

#ifdef __cplusplus
}
#endif

#endif
