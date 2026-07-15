#include "sa_std.h"

#include <stdint.h>
#include <stdio.h>
#include <string.h>

#define CHECK(condition, code)                                                                    \
    do {                                                                                          \
        if (!(condition)) {                                                                       \
            fprintf(stderr, "runtime basic contract failed at line %d (code %d)\n", __LINE__,   \
                    (code));                                                                      \
            result = (code);                                                                      \
            goto cleanup;                                                                         \
        }                                                                                         \
    } while (0)

typedef int32_t (*RuntimeFixtureFn)(void);

static int repeated_byte_matches(const uint8_t *data, uint64_t len, uint8_t value) {
    if (data == NULL) return 0;
    for (uint64_t i = 0; i < len; i += 1) {
        if (data[i] != value) return 0;
    }
    return 1;
}

static int write_repeated(FILE *stream, char value, uint64_t len) {
    for (uint64_t i = 0; i < len; i += 1) {
        if (fputc(value, stream) == EOF) return 0;
    }
    return 1;
}

static int32_t thread_worker(uint8_t *arg) {
    int32_t *value = (int32_t *)arg;
    *value = 42;
    return 73;
}

int main(int argc, char **argv) {
    const uint8_t child_arg[] = "--runtime-basic-child";
    const uint8_t large_child_arg[] = "--runtime-basic-large-child";
    const uint8_t payload[] = "runtime-basic-payload";
    const uint8_t env_value[] = "runtime-basic-env";
    const uint64_t large_stdout_len = 20000;
    const uint64_t large_stderr_len = 17000;
    char dir_path[160] = {0};
    char file_path[224] = {0};
    char env_key[96] = {0};
    int dir_len = 0;
    int file_len = 0;
    int env_key_len = 0;
    int result = 0;
    int dir_created = 0;
    uint64_t file_handle = 0;
    uint64_t dir_entries = 0;
    uint64_t dir_entry = 0;
    uint64_t metadata_handle = 0;
    uint64_t env_handle = 0;
    uint64_t exe_handle = 0;
    uint64_t stdout_handle = 0;
    uint64_t stderr_handle = 0;
    uint64_t dylib_handle = 0;
    int32_t thread_handle = 0;
    int thread_live = 0;

    if (argc == 2 && strcmp(argv[1], (const char *)child_arg) == 0) {
        fputs("runtime-basic-out", stdout);
        fputs("runtime-basic-err", stderr);
        return 17;
    }
    if (argc == 2 && strcmp(argv[1], (const char *)large_child_arg) == 0) {
        if (!write_repeated(stdout, 'O', large_stdout_len)) return 125;
        if (!write_repeated(stderr, 'E', large_stderr_len)) return 126;
        return 19;
    }
    if (argc != 2) {
        fputs("runtime basic contract requires a fixture library path\n", stderr);
        return 100;
    }

    dir_len = snprintf(dir_path, sizeof(dir_path), ".zig-cache/runtime-basic-%u",
                       (unsigned)sa_std_process_id());
    CHECK(dir_len > 0 && (size_t)dir_len < sizeof(dir_path), 101);
    file_len = snprintf(file_path, sizeof(file_path), "%s/data.txt", dir_path);
    CHECK(file_len > 0 && (size_t)file_len < sizeof(file_path), 102);
    env_key_len = snprintf(env_key, sizeof(env_key), "SCI_RUNTIME_BASIC_%u",
                           (unsigned)sa_std_process_id());
    CHECK(env_key_len > 0 && (size_t)env_key_len < sizeof(env_key), 103);

    CHECK(sa_fs_make_dir((const uint8_t *)".zig-cache", sizeof(".zig-cache") - 1) == SA_STD_OK,
          171);
    (void)sa_fs_remove_dir_all((const uint8_t *)dir_path, (uint64_t)dir_len);
    CHECK(sa_fs_create_dir((const uint8_t *)dir_path, (uint64_t)dir_len) == SA_STD_OK, 104);
    dir_created = 1;

    CHECK(sa_std_fs_open_options(
              (const uint8_t *)file_path, (uint64_t)file_len,
              SA_FS_OPEN_READ | SA_FS_OPEN_WRITE | SA_FS_OPEN_CREATE | SA_FS_OPEN_TRUNCATE,
              SA_FS_OPEN_MODE_DEFAULT, 0, &file_handle) == SA_STD_OK,
          105);
    CHECK(file_handle != 0, 106);
    {
        uint64_t written = 0;
        uint64_t position = UINT64_MAX;
        uint64_t read_len = 0;
        uint8_t read_buffer[64] = {0};
        CHECK(sa_std_fs_file_write(file_handle, payload, sizeof(payload) - 1, &written) ==
                  SA_STD_OK,
              107);
        CHECK(written == sizeof(payload) - 1, 108);
        CHECK(sa_std_fs_file_seek(file_handle, SA_FS_SEEK_START, 0, &position) == SA_STD_OK,
              109);
        CHECK(position == 0, 110);
        CHECK(sa_std_fs_file_read(file_handle, read_buffer, sizeof(read_buffer), &read_len) ==
                  SA_STD_OK,
              111);
        CHECK(read_len == sizeof(payload) - 1, 112);
        CHECK(memcmp(read_buffer, payload, sizeof(payload) - 1) == 0, 113);
    }
    {
        const uint64_t closed_handle = file_handle;
        CHECK(sa_std_close(file_handle) == SA_STD_OK, 114);
        file_handle = 0;
        CHECK(sa_std_close(closed_handle) == SA_STD_ERR_INVALID_HANDLE, 115);
        CHECK(sa_std_fs_open_read((const uint8_t *)file_path, (uint64_t)file_len, &file_handle) ==
                  SA_STD_OK,
              116);
        CHECK(file_handle == closed_handle, 117);
        CHECK(sa_std_close(file_handle) == SA_STD_OK, 118);
        file_handle = 0;
    }

    {
        sa_std_fallible_u64 entries_result =
            sa_fs_read_dir_entries((const uint8_t *)dir_path, (uint64_t)dir_len, 16);
        int found_file = 0;
        CHECK(entries_result.status == SA_STD_OK && entries_result.value != 0, 119);
        dir_entries = entries_result.value;
        const uint64_t entry_count = sa_fs_dir_entries_len(dir_entries);
        CHECK(entry_count >= 1, 120);
        for (uint64_t index = 0; index < entry_count; index += 1) {
            CHECK(sa_std_fs_dir_entries_get(dir_entries, index, &dir_entry) == SA_STD_OK, 121);
            const uint8_t *name = sa_fs_dir_entry_name_ptr(dir_entry);
            const uint64_t name_len = sa_fs_dir_entry_name_len(dir_entry);
            if (name != NULL && name_len == sizeof("data.txt") - 1 &&
                memcmp(name, "data.txt", sizeof("data.txt") - 1) == 0) {
                CHECK(sa_fs_dir_entry_kind(dir_entry) == SA_FS_FILE_REGULAR, 122);
                found_file = 1;
            }
            CHECK(sa_fs_dir_entry_free(dir_entry) == SA_STD_OK, 123);
            dir_entry = 0;
        }
        CHECK(found_file, 124);
        CHECK(sa_fs_dir_entries_free(dir_entries) == SA_STD_OK, 125);
        dir_entries = 0;
    }

    {
        sa_std_fallible_u64 metadata =
            sa_fs_metadata((const uint8_t *)file_path, (uint64_t)file_len);
        CHECK(metadata.status == SA_STD_OK && metadata.value != 0, 126);
        metadata_handle = metadata.value;
        CHECK(sa_fs_metadata_is_file(metadata_handle) == 1, 127);
        CHECK(sa_fs_metadata_is_directory(metadata_handle) == 0, 128);
        CHECK(sa_fs_metadata_len(metadata_handle) == sizeof(payload) - 1, 129);
        CHECK(sa_fs_metadata_modified_ms(metadata_handle) > 0, 130);
        CHECK(sa_fs_metadata_free(metadata_handle).status == SA_STD_OK, 131);
        metadata_handle = 0;
    }

    (void)sa_env_remove_var((const uint8_t *)env_key, (uint64_t)env_key_len);
    CHECK(sa_env_set_var((const uint8_t *)env_key, (uint64_t)env_key_len, env_value,
                         sizeof(env_value) - 1) == SA_STD_OK,
          132);
    CHECK(sa_env_has((const uint8_t *)env_key, (uint64_t)env_key_len) == SA_STD_OK, 133);
    env_handle = sa_env_get((const uint8_t *)env_key, (uint64_t)env_key_len);
    CHECK(env_handle != 0, 134);
    CHECK(sa_env_buffer_len(env_handle) == sizeof(env_value) - 1, 135);
    CHECK(memcmp(sa_env_buffer_data(env_handle), env_value, sizeof(env_value) - 1) == 0, 136);
    {
        const uint64_t closed_env_handle = env_handle;
        CHECK(sa_env_buffer_free(env_handle) == SA_STD_OK, 137);
        env_handle = 0;
        CHECK(sa_env_buffer_free(closed_env_handle) == SA_STD_ERR_INVALID_HANDLE, 138);
    }
    CHECK(sa_env_remove_var((const uint8_t *)env_key, (uint64_t)env_key_len) == SA_STD_OK, 139);
    CHECK(sa_env_has((const uint8_t *)env_key, (uint64_t)env_key_len) == SA_STD_ERR_NOT_FOUND,
          140);

    {
        const uint64_t monotonic_before = sa_time_instant_ns();
        SaTimeDate utc_now = {0};
        CHECK(sa_time_sleep_ms(2) == SA_STD_OK, 141);
        CHECK(sa_time_instant_ns() > monotonic_before, 142);
        CHECK(sa_time_unix_ms() > 0, 143);
        CHECK(sa_time_utc_now(&utc_now) == SA_STD_OK, 144);
        CHECK(utc_now.year >= 2020 && utc_now.month >= 1 && utc_now.month <= 12, 145);
    }

    {
        int32_t thread_value = 0;
        int32_t thread_result = -1;
        thread_handle = pthread_spawn((const uint8_t *)(uintptr_t)&thread_worker,
                                      (const uint8_t *)&thread_value);
        CHECK(sa_std_last_error() == SA_STD_OK, 146);
        thread_live = 1;
        CHECK(pthread_join(thread_handle, (uint8_t *)&thread_result) == SA_STD_OK, 147);
        thread_live = 0;
        CHECK(thread_value == 42 && thread_result == 73, 148);
        thread_result = -1;
        CHECK(pthread_join(thread_handle, (uint8_t *)&thread_result) ==
                  SA_STD_ERR_INVALID_HANDLE,
              149);
        CHECK(thread_result == 0, 150);
        thread_handle = 0;
    }

    exe_handle = sa_env_current_exe();
    CHECK(exe_handle != 0, 151);
    {
        const uint8_t *exe_path = sa_env_buffer_data(exe_handle);
        const uint64_t exe_path_len = sa_env_buffer_len(exe_handle);
        SaProcessArgv process_argv[2] = {
            {exe_path, exe_path_len},
            {child_arg, sizeof(child_arg) - 1},
        };
        uint32_t exit_code = 0;
        CHECK(exe_path != NULL && exe_path_len != 0, 152);
        CHECK(sa_std_process_exec_capture(process_argv, 2, &exit_code, &stdout_handle,
                                          &stderr_handle) == SA_STD_OK,
              153);
        CHECK(exit_code == 17, 154);
        CHECK(sa_fs_read_buffer_len(stdout_handle) == sizeof("runtime-basic-out") - 1 &&
                  memcmp(sa_fs_read_buffer_data(stdout_handle), "runtime-basic-out",
                         sizeof("runtime-basic-out") - 1) == 0,
              155);
        CHECK(sa_fs_read_buffer_len(stderr_handle) == sizeof("runtime-basic-err") - 1 &&
                  memcmp(sa_fs_read_buffer_data(stderr_handle), "runtime-basic-err",
                         sizeof("runtime-basic-err") - 1) == 0,
              156);
    }
    CHECK(sa_fs_read_buffer_free(stdout_handle) == SA_STD_OK, 157);
    stdout_handle = 0;
    CHECK(sa_fs_read_buffer_free(stderr_handle) == SA_STD_OK, 158);
    stderr_handle = 0;

    {
        const uint8_t *exe_path = sa_env_buffer_data(exe_handle);
        const uint64_t exe_path_len = sa_env_buffer_len(exe_handle);
        SaProcessArgv process_argv[2] = {
            {exe_path, exe_path_len},
            {large_child_arg, sizeof(large_child_arg) - 1},
        };
        uint32_t exit_code = 0;
        CHECK(sa_std_process_exec_capture(process_argv, 2, &exit_code, &stdout_handle,
                                          &stderr_handle) == SA_STD_OK,
              172);
        CHECK(exit_code == 19, 173);
        CHECK(sa_fs_read_buffer_len(stdout_handle) == large_stdout_len &&
                  repeated_byte_matches(sa_fs_read_buffer_data(stdout_handle),
                                        large_stdout_len, 'O'),
              174);
        CHECK(sa_fs_read_buffer_len(stderr_handle) == large_stderr_len &&
                  repeated_byte_matches(sa_fs_read_buffer_data(stderr_handle),
                                        large_stderr_len, 'E'),
              175);
    }
    CHECK(sa_fs_read_buffer_free(stdout_handle) == SA_STD_OK, 176);
    stdout_handle = 0;
    CHECK(sa_fs_read_buffer_free(stderr_handle) == SA_STD_OK, 177);
    stderr_handle = 0;

    CHECK(sa_env_buffer_free(exe_handle) == SA_STD_OK, 159);
    exe_handle = 0;

    {
        const uint8_t missing_library[] = ".zig-cache/runtime-basic-missing-library";
        dylib_handle = UINT64_MAX;
        CHECK(sa_dl_open(missing_library, sizeof(missing_library) - 1, &dylib_handle) ==
                  SA_STD_ERR_NOT_FOUND,
              160);
        CHECK(dylib_handle == 0, 161);
    }
    CHECK(sa_dl_open((const uint8_t *)argv[1], (uint64_t)strlen(argv[1]), &dylib_handle) ==
              SA_STD_OK,
          162);
    CHECK(dylib_handle != 0, 163);
    {
        void *symbol = NULL;
        const uint8_t symbol_name[] = "sa_runtime_contract_fixture";
        CHECK(sa_dl_sym(dylib_handle, symbol_name, sizeof(symbol_name) - 1, &symbol) == SA_STD_OK,
              164);
        CHECK(symbol != NULL, 165);
        CHECK(((RuntimeFixtureFn)symbol)() == 0x5a17, 166);
    }
    {
        const uint64_t closed_dylib_handle = dylib_handle;
        CHECK(sa_dl_close(dylib_handle) == SA_STD_OK, 167);
        dylib_handle = 0;
        CHECK(sa_dl_close(closed_dylib_handle) == SA_STD_ERR_INVALID_HANDLE, 168);
    }

    CHECK(sa_fs_remove_file((const uint8_t *)file_path, (uint64_t)file_len) == SA_STD_OK, 169);
    CHECK(sa_fs_remove_dir((const uint8_t *)dir_path, (uint64_t)dir_len) == SA_STD_OK, 170);
    dir_created = 0;

cleanup:
    if (thread_live) pthread_drop(thread_handle);
    if (dylib_handle != 0) (void)sa_dl_close(dylib_handle);
    if (stdout_handle != 0) (void)sa_fs_read_buffer_free(stdout_handle);
    if (stderr_handle != 0) (void)sa_fs_read_buffer_free(stderr_handle);
    if (exe_handle != 0) (void)sa_env_buffer_free(exe_handle);
    if (env_handle != 0) (void)sa_env_buffer_free(env_handle);
    if (metadata_handle != 0) (void)sa_fs_metadata_free(metadata_handle);
    if (dir_entry != 0) (void)sa_fs_dir_entry_free(dir_entry);
    if (dir_entries != 0) (void)sa_fs_dir_entries_free(dir_entries);
    if (file_handle != 0) (void)sa_std_close(file_handle);
    (void)sa_env_remove_var((const uint8_t *)env_key, (uint64_t)(env_key_len > 0 ? env_key_len : 0));
    if (dir_created) (void)sa_fs_remove_dir_all((const uint8_t *)dir_path, (uint64_t)dir_len);
    if (result == 0) puts("runtime basic contract ok");
    return result;
}
