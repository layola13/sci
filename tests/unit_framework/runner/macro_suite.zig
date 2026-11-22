const std = @import("std");
const builtin = @import("builtin");
const clearQueuedSaTestFiles = @import("queue.zig").clearQueuedSaTestFiles;
const runQueuedSaTestFiles = @import("queue.zig").runQueuedSaTestFiles;
const runSaTestFileAuto = @import("queue.zig").runSaTestFileAuto;
const suites_a = @import("macro_data_a.zig").suites;
const suites_b = @import("macro_data_b.zig").suites;
const suites_c = @import("macro_data_c.zig").suites;
const udpMulticastV6JoinPermitted = @import("util.zig").udpMulticastV6JoinPermitted;

pub fn runMacroSurfaceSuite(path: []const u8) !void {
    if (builtin.os.tag == .windows) {
        const base = std.fs.path.basename(path);
        const unix_only_tests = [_][]const u8{
            "std_process_macro_surface.sa",
            "std_process_as_fd_macro_surface.sa",
            "std_process_command_builder_pidfd_macro_surface.sa",
            "std_process_command_builder_uid_gid_macro_surface.sa",
            "std_process_command_builder_groups_macro_surface.sa",
            "std_process_command_builder_chroot_macro_surface.sa",
            "std_process_command_builder_exec_macro_surface.sa",
            "std_process_command_builder_stream_pidfd_macro_surface.sa",
            "std_process_command_builder_stream_uid_gid_macro_surface.sa",
            "std_process_command_builder_stream_groups_macro_surface.sa",
            "std_process_command_builder_stream_chroot_macro_surface.sa",
            "std_env_macro_surface.sa",
            "std_path_exists_macro_surface.sa",
            "std_path_is_dir_file_macro_surface.sa",
            "std_fs_unix_ext_macro_surface.sa",
            "std_fs_file_as_fd_macro_surface.sa",
            "std_net_as_fd_macro_surface.sa",
            "std_net_unix_macro_surface.sa",
            "std_net_unix_as_fd_macro_surface.sa",
            "std_os_fd_macro_surface.sa",
            "std_os_fd_as_fd_macro_surface.sa",
            "std_os_unix_ffi_hash_one_macro_surface.sa",
            "std_os_unix_ffi_macro_surface.sa",
            "std_path_macro_surface.sa",
            "std_path_ancestors_macro_surface.sa",
            "std_path_canonicalize_macro_surface.sa",
            "std_path_parent_macro_surface.sa",
            "std_path_relative_macro_surface.sa",
            "std_path_strip_prefix_macro_surface.sa",
            "std_path_join_macro_surface.sa",
            "std_path_file_stem_macro_surface.sa",
            "std_path_file_name_macro_surface.sa",
            "std_path_extension_macro_surface.sa",
            "std_path_buf_with_extension_macro_surface.sa",
            "std_path_buf_set_extension_macro_surface.sa",
            "std_path_buf_set_file_name_macro_surface.sa",
            "std_path_buf_macro_surface.sa",
            "std_path_with_capacity_macro_surface.sa",
            "std_path_ends_with_macro_surface.sa",
            "std_path_starts_with_macro_surface.sa",
            "std_path_components_macro_surface.sa",
            "std_path_has_root_macro_surface.sa",
            "std_path_is_absolute_macro_surface.sa",
            "std_path_is_relative_macro_surface.sa",
            "std_path_buf_pop_macro_surface.sa",
            "std_path_buf_push_macro_surface.sa",
            "std_binary_heap_contains_macro_surface.sa",
            "std_io_utility_macro_surface.sa",
            "std_fs_file_as_fd_macro_surface.sa",
            "std_fs_unix_ext_macro_surface.sa",
            "std_io_stdio_as_fd_macro_surface.sa",
            "std_net_as_fd_macro_surface.sa",
            "std_net_unix_macro_surface.sa",
            "std_net_unix_as_fd_macro_surface.sa",
            "std_os_fd_macro_surface.sa",
            "std_os_fd_as_fd_macro_surface.sa",
            "std_os_unix_ffi_hash_one_macro_surface.sa",
            "std_os_unix_ffi_macro_surface.sa",
            "std_process_as_fd_macro_surface.sa",
            "std_process_command_builder_chroot_macro_surface.sa",
            "std_process_command_builder_exec_macro_surface.sa",
            "std_process_command_builder_groups_macro_surface.sa",
            "std_process_command_builder_pidfd_macro_surface.sa",
            "std_process_command_builder_stream_chroot_macro_surface.sa",
            "std_process_command_builder_stream_groups_macro_surface.sa",
            "std_process_command_builder_stream_pidfd_macro_surface.sa",
            "std_process_command_builder_stream_uid_gid_macro_surface.sa",
            "std_process_command_builder_uid_gid_macro_surface.sa",
            "std_process_macro_surface.sa",
            "std_fs_macro_surface.sa",
            "std_fs_metadata_ext_macro_surface.sa",
            "std_net_macro_surface.sa",
            "std_process_windows_macro_surface.sa",
            "std_fs_dir_entry_ext_macro_surface.sa",
            "std_net_wsurl_macro_surface.sa",
            "std_netx_macro_surface.sa",
        };
        var skip = false;
        for (unix_only_tests) |skip_name| {
            if (std.mem.eql(u8, base, skip_name)) {
                skip = true;
                break;
            }
        }
        if (skip) return;
    }
    // IPv6 multicast needs a multicast-capable interface; without it the
    // v6 join fails with ENODEV (environment, not product). The v4 suite
    // above still verifies unconditionally.
    if (std.mem.eql(u8, path, "tests/unit_framework/std_net_multicast_v6_join_macro_surface.sa") and
        !udpMulticastV6JoinPermitted()) return;
    try runSaTestFileAuto(path);
}

test "native unit framework covers sa_std macro surface suites" {
    defer clearQueuedSaTestFiles();

    for (suites_a) |path| {
        try runMacroSurfaceSuite(path);
    }
    for (suites_b) |path| {
        try runMacroSurfaceSuite(path);
    }
    for (suites_c) |path| {
        try runMacroSurfaceSuite(path);
    }

    if (builtin.os.tag == .windows) {
        try runSaTestFileAuto("tests/unit_framework/std_process_windows_macro_surface.sa");
        try runSaTestFileAuto("tests/unit_framework/std_env_windows_macro_surface.sa");
    }

    try runQueuedSaTestFiles();
}
