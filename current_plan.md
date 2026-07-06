# Current Plan

Date: 2026-07-06

## Objective

Continue the Linux-first `sa_std` parity climb in SCI. Complete source batches first, run focused/full tests, then sync install state once with `./tools/install.sh --no-shell`.

## Active Scope

1. Completed in the current batch:
   - `sa_std/os/fd` raw/owned fd facade.
   - `sa_std/fs` Unix/Linux metadata-ext fields.
   - `sa_std/thread` `current_id` / `yield_now`.
   - `sa_std/process` Unix raw wait-status / `ExitStatusExt` parsing.
   - `std::os::unix::fs::FileExt`: `read_at` / `write_at` and exact/all convenience macros.
   - `std::os::unix::fs::OpenOptionsExt`: `mode` / `custom_flags`.
   - `std::os::unix::fs::PermissionsExt`: `mode` / `set_mode` / `from_mode`.
   - `std::os::unix::fs::FileTypeExt`: `is_block_device` / `is_char_device` / `is_fifo` / `is_socket`.
   - `std::os::unix::fs::DirBuilderExt`: `mode` for single-level and recursive directory creation.
   - `std::os::unix::fs::DirEntryExt`: `ino`, backed by a real Linux `getdents64` directory-entry handle model.
   - `std::os::unix::fs::DirEntryExt2::file_name_ref`: named file-name reference facade over existing directory-entry name pointer/length storage.
   - `std::os::unix::fs::mkfifo`: named FIFO creation macro surface over existing Linux `sa_fs_mkfifo` runtime.
   - `std::os::unix::fs::{chown,lchown,fchown}`: Linux ownership helpers with explicit uid/gid presence flags and Rust raw sentinel macros.
   - `std::os::linux::fs::MetadataExt`: Rust-named `st_*` field surface for Linux stat parity.
   - `std::os::unix::process::parent_id`.
   - `std::os::unix::process::ChildExt::send_signal`.
   - `std::os::unix::net::UnixStream::pair`.
   - `std::os::unix::net::{UnixListener,UnixStream}` local/peer address queries with dedicated Unix socket address resources.
   - `std::os::unix::net::UnixStream::peer_cred` Linux subset: `SO_PEERCRED` peer pid/uid/gid scalar facade.
   - `std::os::unix::net::UnixStream::peek`: named macro surface over existing stream peek runtime with non-consuming read verification.
   - `std::os::unix::net::UnixStream::shutdown`: named macro surface over existing stream shutdown runtime with peer EOF verification.
   - `std::os::unix::net::{UnixStream,UnixListener}` option named surfaces: stream timeout/nonblocking/take_error and listener nonblocking/take_error aliases over existing fd-based runtime.
   - `std::os::unix::net::{UnixStream,UnixListener}::try_clone`: fd-dup clone facades preserving stream/listener resource kinds and independent close lifetimes.
   - `std::os::unix::net::UnixListener::accept`: address-returning `NET_UNIX_ACCEPT_ADDR` surface using the existing Unix addr handle model.
   - `std::os::unix::process::CommandExt` supportable spawn-config subset: `arg0`, `process_group`, and `setsid` across capture/inherit/stream process modes.
   - `std::os::linux::process` / pidfd-adjacent process-group signaling subset: `PROCESS_SEND_PROCESS_GROUP_SIGNAL` with effective PGID tracking.
   - `std::os::linux::process` pidfd subset: create-pidfd spawn path, process `pidfd` / `into_pidfd` extraction, and pidfd kill/send_signal/wait/try_wait raw and code helpers.
   - `std::os::unix::process::CommandExt::{uid,gid}`: child-side `setgid` / `setuid` spawn config plus current `PROCESS_USER_ID` / `PROCESS_GROUP_ID` facade.
   - `std::os::unix::process::CommandExt::groups`: child-side `setgroups` spawn config across capture/inherit/stream modes.
   - `std::os::unix::process::CommandExt::chroot`: child-side `chroot` spawn config across capture/inherit/stream modes.
   - `std::os::unix::process::CommandExt::exec`: in-place `execvpeZ` replacement with cwd/arg0/process_group/setsid/uid/gid/groups/chroot config.
   - `std::os::linux::net::SocketAddrExt` abstract Unix socket address subset: `from_abstract_name` / `as_abstract_name`-style address handles plus listen/connect by Unix addr handle.
   - `std::os::net::linux_ext::TcpStreamExt`: Linux `TCP_QUICKACK` and `TCP_DEFER_ACCEPT` set/get socket option surface.
   - `std::os::net::linux_ext::UnixSocketExt` UnixStream subset: Linux `SO_PASSCRED` set/get socket option surface.
   - `std::os::unix::process::ChildExt::kill_process_group`: Linux process-group `SIGKILL` convenience facade over the existing effective-PGID signal path.
2. Next candidate scope:
   - Continue broader Linux std gap closure against `/home/vscode/projects/rust/library/std/src`.
   - Re-audit remaining Linux-only std facades that do not require Rust trait/lifetime machinery, now that the tracked CommandExt subset is closed.

## Acceptance

- `zig build unit-framework` passes. Done on 2026-07-05 after fixing the UDS setter compatibility path and a DNS macro-surface test leak.
- `zig build unit-framework --summary all` passes after the `DirEntryExt::ino` batch.
- `zig build unit-framework --summary all` passes after the Linux metadata/process extension batch (`6/6 steps succeeded; 5/5 tests passed`).
- `zig build unit-framework --summary all` passes after the Linux fs ownership batch (`6/6 steps succeeded; 5/5 tests passed`).
- `zig build unit-framework --summary all` passes after the Unix-domain socket completion batch (`6/6 steps succeeded; 5/5 tests passed`).
- `zig build unit-framework --summary all` passes after the CommandExt spawn-config batch (`6/6 steps succeeded; 5/5 tests passed`).
- `zig build unit-framework --summary all` passes after the process-group signal batch (`6/6 steps succeeded; 5/5 tests passed`).
- `zig build unit-framework --summary all` passes after the pidfd process batch (`6/6 steps succeeded; 5/5 tests passed`).
- `zig build unit-framework --summary all` passes after the CommandExt uid/gid batch (`6/6 steps succeeded; 5/5 tests passed`).
- `zig build unit-framework --summary all` passes after the CommandExt groups batch (`6/6 steps succeeded; 5/5 tests passed`).
- `zig build unit-framework --summary all` passes after the CommandExt chroot batch (`6/6 steps succeeded; 5/5 tests passed`).
- `zig build unit-framework --summary all` passes after the CommandExt in-place exec batch (`6/6 steps succeeded; 5/5 tests passed`).
- `zig build unit-framework --summary all` passes after the Linux abstract Unix socket address batch (`6/6 steps succeeded; 5/5 tests passed`).
- `zig build unit-framework --summary all` passes after the Linux TcpStreamExt quickack/deferaccept batch (`6/6 steps succeeded; 5/5 tests passed`).
- `zig build unit-framework --summary all` passes after the Linux UnixSocketExt passcred batch (`6/6 steps succeeded; 5/5 tests passed`).
- `zig build unit-framework --summary all` passes after the Linux ChildExt kill_process_group batch (`6/6 steps succeeded; 5/5 tests passed`).
- `zig build unit-framework --summary all` passes after the Unix DirEntryExt2 file_name_ref batch (`6/6 steps succeeded; 5/5 tests passed`).
- `zig build unit-framework --summary all` passes after the Unix fs mkfifo named surface batch (`6/6 steps succeeded; 5/5 tests passed`).
- `zig build unit-framework --summary all` passes after the Linux UnixStream peer_cred batch (`6/6 steps succeeded; 5/5 tests passed`).
- `zig build unit-framework --summary all` passes after the UnixStream peek named surface batch (`6/6 steps succeeded; 5/5 tests passed`).
- `zig build unit-framework --summary all` passes after the UnixStream shutdown named surface batch (`6/6 steps succeeded; 5/5 tests passed`).
- `zig build unit-framework --summary all` passes after the Unix socket option named surface batch (`6/6 steps succeeded; 5/5 tests passed`).
- `zig build unit-framework --summary all` passes after the Unix socket try_clone batch (`6/6 steps succeeded; 5/5 tests passed`).
- `zig build unit-framework --summary all` passes after the UnixListener accept_addr batch (`6/6 steps succeeded; 5/5 tests passed`).
- New macro-surface tests pass:
  - `std_os_fd_macro_surface.sa`
  - `std_fs_metadata_ext_macro_surface.sa`
  - `std_fs_unix_ext_macro_surface.sa`
  - `std_fs_dir_entry_ext_macro_surface.sa`
  - `std_thread_macro_surface.sa`
- Updated directory-entry macro-surface test passes with DirEntryExt2 file_name_ref assertions:
  - `std_fs_dir_entry_ext_macro_surface.sa`
- Updated Unix fs macro-surface test passes with `FS_UNIX_MKFIFO` assertions:
  - `std_fs_unix_ext_macro_surface.sa`
- Updated process macro-surface test passes with raw wait-status assertions:
  - `std_process_macro_surface.sa`
- Updated process macro-surface test passes with CommandExt spawn-config assertions:
  - `std_process_macro_surface.sa`
- Updated process macro-surface test passes with process-group signal raw wait-status assertions:
  - `std_process_macro_surface.sa`
- Updated process macro-surface test passes with pidfd handle/wait/kill assertions:
  - `std_process_macro_surface.sa`
- Updated process macro-surface test passes with CommandExt uid/gid assertions:
  - `std_process_macro_surface.sa`
- Updated process macro-surface test passes with CommandExt groups assertions:
  - `std_process_macro_surface.sa`
- Updated process macro-surface test passes with CommandExt chroot assertions:
  - `std_process_macro_surface.sa`
- Updated process macro-surface test passes with CommandExt in-place exec assertions:
  - `std_process_macro_surface.sa`
- Updated Unix-domain socket macro-surface test passes with pair and address assertions:
  - `std_net_unix_macro_surface.sa`
- Updated Unix-domain socket macro-surface test passes with Linux `SO_PEERCRED` peer pid/uid/gid assertions:
  - `std_net_unix_macro_surface.sa`
- Updated Unix-domain socket macro-surface test passes with `NET_UNIX_STREAM_PEEK` non-consuming read assertions:
  - `std_net_unix_macro_surface.sa`
- Updated Unix-domain socket macro-surface test passes with `NET_UNIX_STREAM_SHUTDOWN` peer EOF assertions:
  - `std_net_unix_macro_surface.sa`
- Updated Unix-domain socket macro-surface test passes with UnixStream timeout/nonblocking/take_error and UnixListener nonblocking/take_error assertions:
  - `std_net_unix_macro_surface.sa`
- Updated Unix-domain socket macro-surface test passes with UnixStream and UnixListener try_clone assertions:
  - `std_net_unix_macro_surface.sa`
- Updated Unix-domain socket macro-surface test passes with `NET_UNIX_ACCEPT_ADDR` peer address assertions:
  - `std_net_unix_macro_surface.sa`
- Updated Unix-domain socket macro-surface test passes with Linux abstract address listen/connect assertions:
  - `std_net_unix_macro_surface.sa`
- Updated net macro-surface test passes with Linux `TCP_QUICKACK` / `TCP_DEFER_ACCEPT` assertions:
  - `std_net_macro_surface.sa`
- Updated Unix-domain socket macro-surface test passes with Linux `SO_PASSCRED` assertions:
  - `std_net_unix_macro_surface.sa`
- Updated process macro-surface test passes with ChildExt kill_process_group assertions:
  - `std_process_macro_surface.sa`
- Installed-state smoke passes for `std_fs_metadata_ext_macro_surface.sa`, `std_fs_unix_ext_macro_surface.sa`, and `std_process_macro_surface.sa` using `/home/vscode/.sa/std`.
- Installed-state smoke passes for `std_net_unix_macro_surface.sa` after install sync.
- Installed-state smoke passes for `std_process_macro_surface.sa` after the CommandExt spawn-config install sync.
- Installed-state smoke passes for `std_process_macro_surface.sa` after the process-group signal install sync.
- Installed-state smoke passes for `std_process_macro_surface.sa` after the pidfd process install sync.
- Installed-state smoke passes for `std_process_macro_surface.sa` after the CommandExt uid/gid install sync.
- Installed-state smoke passes for `std_process_macro_surface.sa` after the CommandExt groups install sync.
- Installed-state smoke passes for `std_process_macro_surface.sa` after the CommandExt chroot install sync.
- Installed-state smoke passes for `std_process_macro_surface.sa` after the CommandExt in-place exec install sync.
- Installed-state smoke passes for `std_net_unix_macro_surface.sa` after the abstract Unix socket address install sync.
- Installed-state smoke passes for `std_net_macro_surface.sa` after the TcpStreamExt quickack/deferaccept install sync.
- Installed-state smoke passes for `std_net_unix_macro_surface.sa` after the UnixSocketExt passcred install sync.
- Installed-state smoke passes for `std_process_macro_surface.sa` after the ChildExt kill_process_group install sync.
- Installed-state smoke passes for `std_fs_dir_entry_ext_macro_surface.sa` after the DirEntryExt2 file_name_ref install sync.
- Installed-state smoke passes for `std_fs_unix_ext_macro_surface.sa` after the Unix fs mkfifo named surface install sync.
- Installed-state smoke passes for `std_net_unix_macro_surface.sa` after the Linux UnixStream peer_cred install sync.
- Installed-state smoke passes for `std_net_unix_macro_surface.sa` after the UnixStream peek named surface install sync.
- Installed-state smoke passes for `std_net_unix_macro_surface.sa` after the UnixStream shutdown named surface install sync.
- Installed-state smoke passes for `std_net_unix_macro_surface.sa` after the Unix socket option named surface install sync.
- Installed-state smoke passes for `std_net_unix_macro_surface.sa` after the Unix socket try_clone install sync.
- Installed-state smoke passes for `std_net_unix_macro_surface.sa` after the UnixListener accept_addr install sync.
- `src/runtime/sa_std.h`, `sa_std/*.sai`, `sa_std/*.sa`, and installed `/home/vscode/.sa/std` expose the same ABI after `./tools/install.sh --no-shell`.

## Current Status

- Source/runtime/facade/test changes are complete for the UnixListener accept_addr batch.
- `zig build sa-std-static --summary all` passes.
- Focused source-std Unix socket `sa test` for `std_net_unix_macro_surface.sa --filter domain` passes (`1 passed`).
- Full source-std Unix socket `sa test` for `std_net_unix_macro_surface.sa` passes (`3 passed`).
- `zig build unit-framework --summary all` passes.
- Install sync completed once via `./tools/install.sh --no-shell`; no manual copy path used.
- Installed-state focused Unix socket smoke for `std_net_unix_macro_surface.sa --filter domain` passes (`1 passed`).
- Installed-state full Unix socket smoke for `std_net_unix_macro_surface.sa` passes (`3 passed`).
- `nm` confirms `sa_std_net_unix_accept_addr` is exported.

## Notes

- Linux-only behavior is acceptable for this batch.
- Keep edits scoped to source/runtime/std facade and test coverage; do not branch into wider trait/prelude work unless a Linux std gap directly requires it.
