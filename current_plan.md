# Current Plan

Date: 2026-07-05

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
   - `std::os::unix::fs::{chown,lchown,fchown}`: Linux ownership helpers with explicit uid/gid presence flags and Rust raw sentinel macros.
   - `std::os::linux::fs::MetadataExt`: Rust-named `st_*` field surface for Linux stat parity.
   - `std::os::unix::process::parent_id`.
   - `std::os::unix::process::ChildExt::send_signal`.
   - `std::os::unix::net::UnixStream::pair`.
   - `std::os::unix::net::{UnixListener,UnixStream}` local/peer address queries with dedicated Unix socket address resources.
2. Next candidate scope:
   - Continue broader Linux std gap closure against `/home/vscode/projects/rust/library/std/src`.
   - Prioritize supportable `CommandExt` child setup knobs, Linux pidfd/process-group pieces, and remaining Linux-only std facades that do not require Rust trait/lifetime machinery.

## Acceptance

- `zig build unit-framework` passes. Done on 2026-07-05 after fixing the UDS setter compatibility path and a DNS macro-surface test leak.
- `zig build unit-framework --summary all` passes after the `DirEntryExt::ino` batch.
- `zig build unit-framework --summary all` passes after the Linux metadata/process extension batch (`6/6 steps succeeded; 5/5 tests passed`).
- `zig build unit-framework --summary all` passes after the Linux fs ownership batch (`6/6 steps succeeded; 5/5 tests passed`).
- `zig build unit-framework --summary all` passes after the Unix-domain socket completion batch (`6/6 steps succeeded; 5/5 tests passed`).
- New macro-surface tests pass:
  - `std_os_fd_macro_surface.sa`
  - `std_fs_metadata_ext_macro_surface.sa`
  - `std_fs_unix_ext_macro_surface.sa`
  - `std_fs_dir_entry_ext_macro_surface.sa`
  - `std_thread_macro_surface.sa`
- Updated process macro-surface test passes with raw wait-status assertions:
  - `std_process_macro_surface.sa`
- Updated Unix-domain socket macro-surface test passes with pair and address assertions:
  - `std_net_unix_macro_surface.sa`
- Installed-state smoke passes for `std_fs_metadata_ext_macro_surface.sa`, `std_fs_unix_ext_macro_surface.sa`, and `std_process_macro_surface.sa` using `/home/vscode/.sa/std`.
- Installed-state smoke passes for `std_net_unix_macro_surface.sa` after install sync.
- `src/runtime/sa_std.h`, `sa_std/*.sai`, `sa_std/*.sa`, and installed `/home/vscode/.sa/std` expose the same ABI after `./tools/install.sh --no-shell`.

## Current Status

- Source/runtime/facade/test changes are complete for the Unix-domain socket completion batch.
- `zig build sa-std-static --summary all` passes.
- Focused source-std `sa test` for `std_net_unix_macro_surface.sa` passes (`2 passed`).
- `zig build unit-framework --summary all` passes.
- Install sync completed once via `./tools/install.sh --no-shell`; no manual copy path used.
- Installed-state UDS smoke passes (`2 passed`); pending now: commit.

## Notes

- Linux-only behavior is acceptable for this batch.
- Keep edits scoped to source/runtime/std facade and test coverage; do not branch into wider trait/prelude work unless a Linux std gap directly requires it.
