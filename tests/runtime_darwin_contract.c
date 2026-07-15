#include "sa_std.h"

#include <stdint.h>
#include <stdio.h>
#include <string.h>

#ifndef __APPLE__
#error "runtime_darwin_contract.c must only be built for Darwin"
#endif

#define CHECK(condition, code)                                                                     \
    do {                                                                                           \
        if (!(condition)) {                                                                        \
            fprintf(stderr, "runtime Darwin contract failed at line %d (code %d)\n", __LINE__,   \
                    (code));                                                                       \
            result = (code);                                                                       \
            goto cleanup;                                                                          \
        }                                                                                          \
    } while (0)

typedef int32_t (*RuntimeFixtureFn)(void);

int main(int argc, char **argv) {
    const uint8_t child_arg[] = "--runtime-darwin-child";
    const uint8_t payload[] = "runtime-darwin-payload";
    char dir_path[160] = {0};
    char file_path[224] = {0};
    int dir_len = 0;
    int file_len = 0;
    int result = 0;
    int dir_created = 0;
    uint64_t metadata_handle = 0;
    uint64_t process_handle = 0;
    uint64_t exe_handle = 0;
    uint64_t dylib_handle = 0;

    if (argc == 2 && strcmp(argv[1], (const char *)child_arg) == 0) return 23;
    if (argc != 2) {
        fputs("runtime Darwin contract requires a fixture library path\n", stderr);
        return 100;
    }

    dir_len = snprintf(dir_path, sizeof(dir_path), ".zig-cache/runtime-darwin-%u",
                       (unsigned)sa_std_process_id());
    CHECK(dir_len > 0 && (size_t)dir_len < sizeof(dir_path), 101);
    file_len = snprintf(file_path, sizeof(file_path), "%s/data.txt", dir_path);
    CHECK(file_len > 0 && (size_t)file_len < sizeof(file_path), 102);
    (void)sa_fs_remove_dir_all((const uint8_t *)dir_path, (uint64_t)dir_len);
    CHECK(sa_fs_create_dir((const uint8_t *)dir_path, (uint64_t)dir_len) == SA_STD_OK, 103);
    dir_created = 1;
    CHECK(sa_fs_write_file((const uint8_t *)file_path, (uint64_t)file_len, payload,
                           sizeof(payload) - 1) == SA_STD_OK,
          104);

    {
        sa_std_fallible_u64 metadata =
            sa_fs_metadata((const uint8_t *)file_path, (uint64_t)file_len);
        CHECK(metadata.status == SA_STD_OK && metadata.value != 0, 105);
        metadata_handle = metadata.value;
        CHECK(sa_fs_metadata_st_size(metadata_handle) == sizeof(payload) - 1, 106);
        CHECK(sa_fs_metadata_st_mode(metadata_handle) != 0, 107);
        CHECK(sa_fs_metadata_st_atime(metadata_handle) > 0, 108);
        CHECK(sa_fs_metadata_st_mtime(metadata_handle) > 0, 109);
        CHECK(sa_fs_metadata_st_ctime(metadata_handle) > 0, 110);
        CHECK(sa_fs_metadata_st_atime_nsec(metadata_handle) >= 0 &&
                  sa_fs_metadata_st_atime_nsec(metadata_handle) < 1000000000,
              111);
        CHECK(sa_fs_metadata_st_mtime_nsec(metadata_handle) >= 0 &&
                  sa_fs_metadata_st_mtime_nsec(metadata_handle) < 1000000000,
              112);
        CHECK(sa_fs_metadata_st_ctime_nsec(metadata_handle) >= 0 &&
                  sa_fs_metadata_st_ctime_nsec(metadata_handle) < 1000000000,
              113);
        CHECK(sa_fs_metadata_free(metadata_handle).status == SA_STD_OK, 114);
        metadata_handle = 0;
    }

    exe_handle = sa_env_current_exe();
    CHECK(exe_handle != 0, 115);
    {
        const uint8_t *exe_path = sa_env_buffer_data(exe_handle);
        const uint64_t exe_path_len = sa_env_buffer_len(exe_handle);
        SaProcessArgv process_argv[2] = {
            {exe_path, exe_path_len},
            {child_arg, sizeof(child_arg) - 1},
        };
        int32_t raw_status = 0;
        CHECK(exe_path != NULL && exe_path_len != 0, 116);
        CHECK(sa_std_process_spawn(process_argv, 2, &process_handle) == SA_STD_OK, 117);
        CHECK(process_handle != 0, 118);
        CHECK(sa_std_process_wait_raw(process_handle, &raw_status) == SA_STD_OK, 119);
        CHECK(sa_std_process_exit_status_code(raw_status) == 23, 120);
        CHECK(sa_std_process_close(process_handle) == SA_STD_OK, 121);
        process_handle = 0;
    }
    CHECK(sa_env_buffer_free(exe_handle) == SA_STD_OK, 122);
    exe_handle = 0;

    CHECK(sa_dl_open((const uint8_t *)argv[1], (uint64_t)strlen(argv[1]), &dylib_handle) ==
              SA_STD_OK,
          123);
    {
        void *symbol = NULL;
        const uint8_t symbol_name[] = "sa_runtime_contract_fixture";
        CHECK(sa_dl_sym(dylib_handle, symbol_name, sizeof(symbol_name) - 1, &symbol) == SA_STD_OK,
              124);
        CHECK(symbol != NULL && ((RuntimeFixtureFn)symbol)() == 0x5a17, 125);
    }
    CHECK(sa_dl_close(dylib_handle) == SA_STD_OK, 126);
    dylib_handle = 0;

    CHECK(sa_fs_remove_file((const uint8_t *)file_path, (uint64_t)file_len) == SA_STD_OK, 127);
    CHECK(sa_fs_remove_dir((const uint8_t *)dir_path, (uint64_t)dir_len) == SA_STD_OK, 128);
    dir_created = 0;

cleanup:
    if (dylib_handle != 0) (void)sa_dl_close(dylib_handle);
    if (process_handle != 0) (void)sa_std_process_close(process_handle);
    if (exe_handle != 0) (void)sa_env_buffer_free(exe_handle);
    if (metadata_handle != 0) (void)sa_fs_metadata_free(metadata_handle);
    if (dir_created) (void)sa_fs_remove_dir_all((const uint8_t *)dir_path, (uint64_t)dir_len);
    if (result == 0) puts("runtime Darwin contract ok");
    return result;
}
