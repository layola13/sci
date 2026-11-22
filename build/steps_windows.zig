const BuildCtx = @import("ctx.zig").BuildCtx;
const linkWindowsNetworkingToCompile = @import("llvm.zig").linkWindowsNetworkingToCompile;

/// build.zig lines 1053-1212.
pub fn buildWindowsTests(ctx: *BuildCtx) void {
    const b = ctx.b;
    const target = ctx.target;
    const optimize = ctx.optimize;
    const is_windows = ctx.is_windows;
    const repo_root_lazy = ctx.repo_root_lazy;
    const sio_module = ctx.sio_module;
    const sa_std_static = ctx.sa_std_static;
    const sync_sa_std_artifact = ctx.sync_sa_std_artifact;
    const install_sa_std_header = ctx.install_sa_std_header;
    const windows_runtime_step = ctx.windows_runtime_step;

    const windows_first_slice_step = b.step("windows-first-slice", "Compile and run the Windows-first C ABI smoke test");
    if (is_windows) {
        windows_first_slice_step.dependOn(&sync_sa_std_artifact.step);
        windows_first_slice_step.dependOn(&install_sa_std_header.step);

        const windows_first_slice_module = b.createModule(.{
            .target = target,
            .optimize = optimize,
            .link_libc = true,
        });
        windows_first_slice_module.addImport("sio", sio_module);
        windows_first_slice_module.addIncludePath(b.path("src/runtime"));
        windows_first_slice_module.addCSourceFile(.{
            .file = b.path("tests/sa_std_windows_first_slice.c"),
            .flags = &.{},
        });
        windows_first_slice_module.addObjectFile(sa_std_static.getEmittedBin());

        const windows_first_slice = b.addExecutable(.{
            .name = "sa_std_windows_first_slice",
            .root_module = windows_first_slice_module,
        });
        linkWindowsNetworkingToCompile(windows_first_slice, target.result.os.tag);
        const run_windows_first_slice = b.addRunArtifact(windows_first_slice);
        run_windows_first_slice.setCwd(repo_root_lazy);
        windows_first_slice_step.dependOn(&run_windows_first_slice.step);
    }

    const windows_native_address_step = b.step(
        "windows-native-address",
        "Compile and run the Windows address conversion ABI smoke test",
    );
    if (is_windows) {
        windows_native_address_step.dependOn(&sync_sa_std_artifact.step);
        windows_native_address_step.dependOn(&install_sa_std_header.step);

        const windows_native_address_module = b.createModule(.{
            .target = target,
            .optimize = optimize,
            .link_libc = true,
        });
        windows_native_address_module.addImport("sio", sio_module);
        windows_native_address_module.addIncludePath(b.path("src/runtime"));
        windows_native_address_module.addCSourceFile(.{
            .file = b.path("tests/sa_std_windows_address.c"),
            .flags = &.{},
        });
        windows_native_address_module.addObjectFile(sa_std_static.getEmittedBin());

        const windows_native_address = b.addExecutable(.{
            .name = "sa_std_windows_address",
            .root_module = windows_native_address_module,
        });
        linkWindowsNetworkingToCompile(windows_native_address, target.result.os.tag);
        const run_windows_native_address = b.addRunArtifact(windows_native_address);
        run_windows_native_address.setCwd(repo_root_lazy);
        windows_native_address_step.dependOn(&run_windows_native_address.step);
    }

    const windows_native_tcp_step = b.step(
        "windows-native-tcp",
        "Compile and run the Windows TCP ABI smoke test",
    );
    if (is_windows) {
        windows_native_tcp_step.dependOn(&sync_sa_std_artifact.step);
        windows_native_tcp_step.dependOn(&install_sa_std_header.step);

        const windows_native_tcp_module = b.createModule(.{
            .target = target,
            .optimize = optimize,
            .link_libc = true,
        });
        windows_native_tcp_module.addImport("sio", sio_module);
        windows_native_tcp_module.addIncludePath(b.path("src/runtime"));
        windows_native_tcp_module.addCSourceFile(.{
            .file = b.path("tests/sa_std_windows_tcp.c"),
            .flags = &.{"-DSA_WINDOWS_TCP_EXPECT_SUPPORTED=1"},
        });
        windows_native_tcp_module.addObjectFile(sa_std_static.getEmittedBin());

        const windows_native_tcp = b.addExecutable(.{
            .name = "sa_std_windows_tcp",
            .root_module = windows_native_tcp_module,
        });
        linkWindowsNetworkingToCompile(windows_native_tcp, target.result.os.tag);
        const run_windows_native_tcp = b.addRunArtifact(windows_native_tcp);
        run_windows_native_tcp.setCwd(repo_root_lazy);
        windows_native_tcp_step.dependOn(&run_windows_native_tcp.step);
    }

    const windows_native_udp_step = b.step(
        "windows-native-udp",
        "Compile and run the Windows UDP ABI smoke test",
    );
    if (is_windows) {
        windows_native_udp_step.dependOn(&sync_sa_std_artifact.step);
        windows_native_udp_step.dependOn(&install_sa_std_header.step);

        const windows_native_udp_module = b.createModule(.{
            .target = target,
            .optimize = optimize,
            .link_libc = true,
        });
        windows_native_udp_module.addImport("sio", sio_module);
        windows_native_udp_module.addIncludePath(b.path("src/runtime"));
        windows_native_udp_module.addCSourceFile(.{
            .file = b.path("tests/sa_std_windows_udp.c"),
            .flags = &.{"-DSA_STD_WINDOWS_UDP_SUPPORTED=1"},
        });
        windows_native_udp_module.addObjectFile(sa_std_static.getEmittedBin());

        const windows_native_udp = b.addExecutable(.{
            .name = "sa_std_windows_udp",
            .root_module = windows_native_udp_module,
        });
        linkWindowsNetworkingToCompile(windows_native_udp, target.result.os.tag);
        const run_windows_native_udp = b.addRunArtifact(windows_native_udp);
        run_windows_native_udp.setCwd(repo_root_lazy);
        windows_native_udp_step.dependOn(&run_windows_native_udp.step);
    }

    const windows_native_process_terminal_step = b.step(
        "windows-native-process-terminal",
        "Compile and run the Windows process and terminal ABI smoke test",
    );
    if (is_windows) {
        windows_native_process_terminal_step.dependOn(&sync_sa_std_artifact.step);
        windows_native_process_terminal_step.dependOn(&install_sa_std_header.step);

        const windows_native_process_terminal_module = b.createModule(.{
            .target = target,
            .optimize = optimize,
            .link_libc = true,
        });
        windows_native_process_terminal_module.addImport("sio", sio_module);
        windows_native_process_terminal_module.addIncludePath(b.path("src/runtime"));
        windows_native_process_terminal_module.addCSourceFile(.{
            .file = b.path("tests/sa_std_windows_process_terminal.c"),
            .flags = &.{},
        });
        windows_native_process_terminal_module.addObjectFile(sa_std_static.getEmittedBin());

        const windows_native_process_terminal = b.addExecutable(.{
            .name = "sa_std_windows_process_terminal",
            .root_module = windows_native_process_terminal_module,
        });
        linkWindowsNetworkingToCompile(windows_native_process_terminal, target.result.os.tag);
        const run_windows_native_process_terminal = b.addRunArtifact(windows_native_process_terminal);
        run_windows_native_process_terminal.setCwd(repo_root_lazy);
        windows_native_process_terminal_step.dependOn(&run_windows_native_process_terminal.step);
    }

    if (is_windows) {
        windows_runtime_step.dependOn(windows_first_slice_step);
        windows_runtime_step.dependOn(windows_native_address_step);
        windows_runtime_step.dependOn(windows_native_process_terminal_step);
        windows_runtime_step.dependOn(windows_native_tcp_step);
        windows_runtime_step.dependOn(windows_native_udp_step);
    }
}
