# Current Plan

Date: 2026-07-09


## Active std parity batch (2026-07-16 socket AsFd aliases)

Completed supportable `std::net` / `std::os::unix::net` `AsFd` aliases:
- `NET_TCP_LISTENER_AS_FD`, `NET_TCP_STREAM_AS_FD`, `NET_UDP_AS_FD`, `NET_UNIX_LISTENER_AS_FD`, `NET_UNIX_STREAM_AS_FD`, and `NET_UNIX_DATAGRAM_AS_FD` expose Rust socket `as_fd` naming over existing socket raw-fd views.
- These helpers return the current SA borrowed raw-fd scalar representation and compose with `FD_BORROWED_*` helpers.
- This batch does not model Rust lifetime tracking, borrow checker rules, trait dispatch, or native `BorrowedFd<'_>` object layout.
- Test files `std_net_as_fd_macro_surface.sa` (panic ID 10697) and `std_net_unix_as_fd_macro_surface.sa` (panic ID 10698).

Focused validation only:
- `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_net_as_fd_macro_surface.sa --jobs 1 --trace-panic` -> `1 passed; 0 failed; 0 skipped`.
- `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_net_unix_as_fd_macro_surface.sa --jobs 1 --trace-panic` -> `1 passed; 0 failed; 0 skipped`.

Panic IDs next free: 10699+.
Still blocked without redesign: generic trait impl dispatch, Rust lifetime/borrow semantics, native `BorrowedFd<'_>` object layout, generic primitive/container trait dispatch, cross-width integer conversions, generic `NonZero<T>`, generic `Wrapping<T>` / `Saturating<T>`, `u128` / `i128` public primitive support, portable target-width `usize` / `isize` switching beyond the current explicit 64-bit ABI, missing concrete wrapper widths, Rust feature-gate modeling, Rust niche optimization, Rust unsafe UB enforcement, Rust panic message/object behavior, parser/formatter trait integration, allocator/drop/borrow semantics, randomized `RandomState`, SipHash compatibility, Rust iterator trait hierarchy, generic `Option` / `Result` / `ControlFlow`, generic `FromIterator`, `IntoIterator`, true format!, Condvar/Barrier, process env maps / Stdio redirection, path component iterators, pre_exec closure ABI, thread stack/name builder ABI, and stdio lock guard handle modeling.


## Active std parity batch (2026-07-16 process AsFd aliases)

Completed supportable `std::os::{linux,unix}::process` `AsFd` aliases:
- `PIDFD_AS_FD`, `PROCESS_CHILD_STDOUT_AS_FD`, and `PROCESS_CHILD_STDERR_AS_FD` expose Rust process fd `as_fd` naming over existing pidfd and child pipe raw-fd views.
- These helpers return the current SA borrowed raw-fd scalar representation and compose with `FD_BORROWED_*` helpers.
- This batch does not model `ChildStdin`, Rust lifetime tracking, borrow checker rules, trait dispatch, or native `BorrowedFd<'_>` object layout.
- Test file `std_process_as_fd_macro_surface.sa` (panic ID 10696).

Focused validation only:
- `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_process_as_fd_macro_surface.sa --jobs 1 --trace-panic` -> `1 passed; 0 failed; 0 skipped`.

Panic IDs next free: 10697+.
Still blocked without redesign: generic trait impl dispatch, Rust lifetime/borrow semantics, native `BorrowedFd<'_>` object layout, `ChildStdin` pipe wiring, generic primitive/container trait dispatch, cross-width integer conversions, generic `NonZero<T>`, generic `Wrapping<T>` / `Saturating<T>`, `u128` / `i128` public primitive support, portable target-width `usize` / `isize` switching beyond the current explicit 64-bit ABI, missing concrete wrapper widths, Rust feature-gate modeling, Rust niche optimization, Rust unsafe UB enforcement, Rust panic message/object behavior, parser/formatter trait integration, allocator/drop/borrow semantics, randomized `RandomState`, SipHash compatibility, Rust iterator trait hierarchy, generic `Option` / `Result` / `ControlFlow`, generic `FromIterator`, `IntoIterator`, true format!, Condvar/Barrier, process env maps / Stdio redirection, path component iterators, pre_exec closure ABI, thread stack/name builder ABI, and stdio lock guard handle modeling.


## Active std parity batch (2026-07-16 stdio AsFd aliases)

Completed supportable `std::io::{Stdin,Stdout,Stderr}` `AsFd` aliases:
- `IO_STDIN_AS_FD`, `IO_STDOUT_AS_FD`, and `IO_STDERR_AS_FD` expose Rust stdio `as_fd` naming over fixed stdio handles.
- These helpers return the current SA borrowed raw-fd scalar representation (`0`, `1`, `2`) and compose with `FD_BORROWED_*` helpers.
- This batch does not model Rust stdio lock guards, lifetime tracking, borrow checker rules, trait dispatch, or native `BorrowedFd<'_>` object layout.
- Test file `std_io_stdio_as_fd_macro_surface.sa` (panic ID 10695).

Focused validation only:
- `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_io_stdio_as_fd_macro_surface.sa --jobs 1 --trace-panic` -> `1 passed; 0 failed; 0 skipped`.

Panic IDs next free: 10696+.
Still blocked without redesign: generic trait impl dispatch, Rust lifetime/borrow semantics, native `BorrowedFd<'_>` object layout, generic primitive/container trait dispatch, cross-width integer conversions, generic `NonZero<T>`, generic `Wrapping<T>` / `Saturating<T>`, `u128` / `i128` public primitive support, portable target-width `usize` / `isize` switching beyond the current explicit 64-bit ABI, missing concrete wrapper widths, Rust feature-gate modeling, Rust niche optimization, Rust unsafe UB enforcement, Rust panic message/object behavior, parser/formatter trait integration, allocator/drop/borrow semantics, randomized `RandomState`, SipHash compatibility, Rust iterator trait hierarchy, generic `Option` / `Result` / `ControlFlow`, generic `FromIterator`, `IntoIterator`, true format!, Condvar/Barrier, process env maps / Stdio redirection, path component iterators, pre_exec closure ABI, thread stack/name builder ABI, and stdio lock guard handle modeling.


## Active std parity batch (2026-07-16 std::fs::File AsFd alias)

Completed supportable `std::fs::File` `AsFd` alias:
- `FS_FILE_AS_FD` exposes the Rust `File::as_fd` naming surface over the existing File handle raw-fd view.
- This returns the current SA borrowed raw-fd scalar representation and composes with `FD_BORROWED_*` helpers.
- This batch does not model Rust lifetime tracking, borrow checker rules, trait dispatch, or native `BorrowedFd<'_>` object layout.
- Test file `std_fs_file_as_fd_macro_surface.sa` (panic ID 10694).

Focused validation only:
- `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_fs_file_as_fd_macro_surface.sa --jobs 1 --trace-panic` -> `1 passed; 0 failed; 0 skipped`.

Panic IDs next free: 10695+.
Still blocked without redesign: generic trait impl dispatch, Rust lifetime/borrow semantics, native `BorrowedFd<'_>` object layout, generic primitive/container trait dispatch, cross-width integer conversions, generic `NonZero<T>`, generic `Wrapping<T>` / `Saturating<T>`, `u128` / `i128` public primitive support, portable target-width `usize` / `isize` switching beyond the current explicit 64-bit ABI, missing concrete wrapper widths, Rust feature-gate modeling, Rust niche optimization, Rust unsafe UB enforcement, Rust panic message/object behavior, parser/formatter trait integration, allocator/drop/borrow semantics, randomized `RandomState`, SipHash compatibility, Rust iterator trait hierarchy, generic `Option` / `Result` / `ControlFlow`, generic `FromIterator`, `IntoIterator`, true format!, Condvar/Barrier, process env maps / Stdio redirection, path component iterators, pre_exec closure ABI, and thread stack/name builder ABI.


## Active std parity batch (2026-07-16 std::os::fd AsFd aliases)

Completed supportable `std::os::fd::AsFd` aliases:
- `FD_OWNED_AS_FD` exposes the Rust `OwnedFd::as_fd` naming surface over the existing owned fd handle raw-fd view.
- `FD_BORROWED_AS_FD` exposes the Rust `BorrowedFd::as_fd` reflexive naming surface over the current SA borrowed raw-fd scalar representation.
- This batch does not model Rust lifetime tracking, borrow checker rules, trait dispatch, or native `BorrowedFd<'_>` object layout.
- Test file `std_os_fd_as_fd_macro_surface.sa` (panic ID 10693).

Focused validation only:
- `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_os_fd_as_fd_macro_surface.sa --jobs 1 --trace-panic` -> `1 passed; 0 failed; 0 skipped`.

Panic IDs next free: 10694+.
Still blocked without redesign: generic trait impl dispatch, Rust lifetime/borrow semantics, native `BorrowedFd<'_>` object layout, generic primitive/container trait dispatch, cross-width integer conversions, generic `NonZero<T>`, generic `Wrapping<T>` / `Saturating<T>`, `u128` / `i128` public primitive support, portable target-width `usize` / `isize` switching beyond the current explicit 64-bit ABI, missing concrete wrapper widths, Rust feature-gate modeling, Rust niche optimization, Rust unsafe UB enforcement, Rust panic message/object behavior, parser/formatter trait integration, allocator/drop/borrow semantics, randomized `RandomState`, SipHash compatibility, Rust iterator trait hierarchy, generic `Option` / `Result` / `ControlFlow`, generic `FromIterator`, `IntoIterator`, true format!, Condvar/Barrier, process env maps / Stdio redirection, path component iterators, pre_exec closure ABI, and thread stack/name builder ABI.


## Active std parity batch (2026-07-16 Process Command builder exec)

Completed supportable process Command builder exec wrapper:
- `PROCESS_COMMAND_BUILDER_EXEC` forwards the existing builder scalar state into the real `PROCESS_EXEC_COMMAND_EXT` runtime path.
- This helper preserves the current builder fields (`cwd`, `arg0`, `process_group`, `setsid`) and takes explicit `uid` / `gid` / `groups` / `chroot` values plus presence flags matching the existing lower-level in-place exec facade.
- This batch does not model env maps, pipe Stdio redirection wiring, full heap `Command` objects, or `pre_exec` closure integration.
- Test file `std_process_command_builder_exec_macro_surface.sa` (panic ID 10692). It covers the missing-executable failure path only because a successful `exec` replaces the test process.

Focused validation only:
- `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_process_command_builder_exec_macro_surface.sa --jobs 1 --trace-panic` -> `1 passed; 0 failed; 0 skipped`.

Panic IDs next free: 10693+.
Still blocked without redesign: generic primitive/container trait impl dispatch, cross-width integer conversions, generic `NonZero<T>`, generic `Wrapping<T>` / `Saturating<T>`, `u128` / `i128` public primitive support, portable target-width `usize` / `isize` switching beyond the current explicit 64-bit ABI, missing concrete wrapper widths, Rust feature-gate modeling, Rust niche optimization, Rust unsafe UB enforcement, Rust panic message/object behavior, parser/formatter trait integration, allocator/drop/borrow semantics, randomized `RandomState`, SipHash compatibility, Rust iterator trait hierarchy, generic `Option` / `Result` / `ControlFlow`, generic `FromIterator`, `IntoIterator`, true format!, Condvar/Barrier, process env maps / Stdio redirection, path component iterators, pre_exec closure ABI, and thread stack/name builder ABI.


## Active std parity batch (2026-07-16 Process Command builder stream pidfd)

Completed supportable process Command builder stream pidfd wrapper:
- `PROCESS_COMMAND_BUILDER_SPAWN_STREAM_PIDFD` forwards the existing builder scalar state into the real `PROCESS_SPAWN_STREAM_COMMAND_EXT_PIDFD` runtime path.
- This helper preserves the current builder fields (`cwd`, `arg0`, `process_group`, `setsid`) and adds an explicit `create_pidfd` flag matching the existing lower-level stream PIDFD facade.
- This batch does not model env maps, pipe Stdio redirection wiring, full heap `Command` objects, or capture-time CommandExt pidfd integration.
- Test file `std_process_command_builder_stream_pidfd_macro_surface.sa` (panic ID 10691).

Focused validation only:
- `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_process_command_builder_stream_pidfd_macro_surface.sa --jobs 1 --trace-panic` -> `1 passed; 0 failed; 0 skipped`.

Panic IDs next free: 10692+.
Still blocked without redesign: generic primitive/container trait impl dispatch, cross-width integer conversions, generic `NonZero<T>`, generic `Wrapping<T>` / `Saturating<T>`, `u128` / `i128` public primitive support, portable target-width `usize` / `isize` switching beyond the current explicit 64-bit ABI, missing concrete wrapper widths, Rust feature-gate modeling, Rust niche optimization, Rust unsafe UB enforcement, Rust panic message/object behavior, parser/formatter trait integration, allocator/drop/borrow semantics, randomized `RandomState`, SipHash compatibility, Rust iterator trait hierarchy, generic `Option` / `Result` / `ControlFlow`, generic `FromIterator`, `IntoIterator`, true format!, Condvar/Barrier, process env maps / Stdio redirection, path component iterators, and thread stack/name builder ABI.


## Active std parity batch (2026-07-16 Process Command builder stream chroot)

Completed supportable process Command builder stream chroot wrapper:
- `PROCESS_COMMAND_BUILDER_SPAWN_STREAM_CHROOT` forwards the existing builder scalar state into the real `PROCESS_SPAWN_STREAM_COMMAND_EXT_CHROOT` runtime path.
- This helper preserves the current builder fields (`cwd`, `arg0`, `process_group`, `setsid`) and adds an explicit chroot pointer, chroot length, and `has_chroot` flag matching the existing lower-level stream CommandExt facade.
- This batch does not model env maps, pipe Stdio redirection wiring, full heap `Command` objects, or capture-time CommandExt chroot integration.
- Test file `std_process_command_builder_stream_chroot_macro_surface.sa` (panic ID 10690).

Focused validation only:
- `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_process_command_builder_stream_chroot_macro_surface.sa --jobs 1 --trace-panic` -> `1 passed; 0 failed; 0 skipped`.

Panic IDs next free: 10691+.
Still blocked without redesign: generic primitive/container trait impl dispatch, cross-width integer conversions, generic `NonZero<T>`, generic `Wrapping<T>` / `Saturating<T>`, `u128` / `i128` public primitive support, portable target-width `usize` / `isize` switching beyond the current explicit 64-bit ABI, missing concrete wrapper widths, Rust feature-gate modeling, Rust niche optimization, Rust unsafe UB enforcement, Rust panic message/object behavior, parser/formatter trait integration, allocator/drop/borrow semantics, randomized `RandomState`, SipHash compatibility, Rust iterator trait hierarchy, generic `Option` / `Result` / `ControlFlow`, generic `FromIterator`, `IntoIterator`, true format!, Condvar/Barrier, process env maps / Stdio redirection, path component iterators, and thread stack/name builder ABI.


## Active std parity batch (2026-07-16 Process Command builder stream groups)

Completed supportable process Command builder stream groups wrapper:
- `PROCESS_COMMAND_BUILDER_SPAWN_STREAM_GROUPS` forwards the existing builder scalar state into the real `PROCESS_SPAWN_STREAM_COMMAND_EXT_GROUPS` runtime path.
- This helper preserves the current builder fields (`cwd`, `arg0`, `process_group`, `setsid`) and adds an explicit groups pointer, groups length, and `has_groups` flag matching the existing lower-level stream CommandExt facade.
- This batch does not model env maps, pipe Stdio redirection wiring, full heap `Command` objects, or capture-time CommandExt groups integration.
- Test file `std_process_command_builder_stream_groups_macro_surface.sa` (panic ID 10689).

Focused validation only:
- `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_process_command_builder_stream_groups_macro_surface.sa --jobs 1 --trace-panic` -> `1 passed; 0 failed; 0 skipped`.

Panic IDs next free: 10690+.
Still blocked without redesign: generic primitive/container trait impl dispatch, cross-width integer conversions, generic `NonZero<T>`, generic `Wrapping<T>` / `Saturating<T>`, `u128` / `i128` public primitive support, portable target-width `usize` / `isize` switching beyond the current explicit 64-bit ABI, missing concrete wrapper widths, Rust feature-gate modeling, Rust niche optimization, Rust unsafe UB enforcement, Rust panic message/object behavior, parser/formatter trait integration, allocator/drop/borrow semantics, randomized `RandomState`, SipHash compatibility, Rust iterator trait hierarchy, generic `Option` / `Result` / `ControlFlow`, generic `FromIterator`, `IntoIterator`, true format!, Condvar/Barrier, process env maps / Stdio redirection, path component iterators, and thread stack/name builder ABI.


## Active std parity batch (2026-07-16 Process Command builder stream uid/gid)

Completed supportable process Command builder stream uid/gid wrapper:
- `PROCESS_COMMAND_BUILDER_SPAWN_STREAM_UID_GID` forwards the existing builder scalar state into the real `PROCESS_SPAWN_STREAM_COMMAND_EXT_UID_GID` runtime path.
- This helper preserves the current builder fields (`cwd`, `arg0`, `process_group`, `setsid`) and adds explicit `uid` / `gid` values plus `has_uid` / `has_gid` flags matching the existing lower-level stream CommandExt facade.
- This batch does not model env maps, pipe Stdio redirection wiring, full heap `Command` objects, or capture-time CommandExt uid/gid integration.
- Test file `std_process_command_builder_stream_uid_gid_macro_surface.sa` (panic ID 10688).

Focused validation only:
- `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_process_command_builder_stream_uid_gid_macro_surface.sa --jobs 1 --trace-panic` -> `1 passed; 0 failed; 0 skipped`.

Panic IDs next free: 10689+.
Still blocked without redesign: generic primitive/container trait impl dispatch, cross-width integer conversions, generic `NonZero<T>`, generic `Wrapping<T>` / `Saturating<T>`, `u128` / `i128` public primitive support, portable target-width `usize` / `isize` switching beyond the current explicit 64-bit ABI, missing concrete wrapper widths, Rust feature-gate modeling, Rust niche optimization, Rust unsafe UB enforcement, Rust panic message/object behavior, parser/formatter trait integration, allocator/drop/borrow semantics, randomized `RandomState`, SipHash compatibility, Rust iterator trait hierarchy, generic `Option` / `Result` / `ControlFlow`, generic `FromIterator`, `IntoIterator`, true format!, Condvar/Barrier, process env maps / Stdio redirection, path component iterators, and thread stack/name builder ABI.


## Active std parity batch (2026-07-16 Process Command builder chroot)

Completed supportable process Command builder chroot wrappers:
- `PROCESS_COMMAND_BUILDER_STATUS_CHROOT` and `PROCESS_COMMAND_BUILDER_SPAWN_CHROOT` forward the existing builder scalar state into the real `PROCESS_*_COMMAND_EXT_CHROOT` runtime paths.
- These helpers preserve the current builder fields (`cwd`, `arg0`, `process_group`, `setsid`) and add an explicit chroot pointer, chroot length, and `has_chroot` flag matching the existing lower-level CommandExt facade.
- This batch does not model env maps, pipe Stdio redirection wiring, full heap `Command` objects, or capture-time CommandExt chroot integration.
- Test file `std_process_command_builder_chroot_macro_surface.sa` (panic ID 10687).

Focused validation only:
- `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_process_command_builder_chroot_macro_surface.sa --jobs 1 --trace-panic` -> `1 passed; 0 failed; 0 skipped`.

Panic IDs next free: 10688+.
Still blocked without redesign: generic primitive/container trait impl dispatch, cross-width integer conversions, generic `NonZero<T>`, generic `Wrapping<T>` / `Saturating<T>`, `u128` / `i128` public primitive support, portable target-width `usize` / `isize` switching beyond the current explicit 64-bit ABI, missing concrete wrapper widths, Rust feature-gate modeling, Rust niche optimization, Rust unsafe UB enforcement, Rust panic message/object behavior, parser/formatter trait integration, allocator/drop/borrow semantics, randomized `RandomState`, SipHash compatibility, Rust iterator trait hierarchy, generic `Option` / `Result` / `ControlFlow`, generic `FromIterator`, `IntoIterator`, true format!, Condvar/Barrier, process env maps / Stdio redirection, path component iterators, and thread stack/name builder ABI.


## Active std parity batch (2026-07-16 Process Command builder groups)

Completed supportable process Command builder groups wrappers:
- `PROCESS_COMMAND_BUILDER_STATUS_GROUPS` and `PROCESS_COMMAND_BUILDER_SPAWN_GROUPS` forward the existing builder scalar state into the real `PROCESS_*_COMMAND_EXT_GROUPS` runtime paths.
- These helpers preserve the current builder fields (`cwd`, `arg0`, `process_group`, `setsid`) and add an explicit groups pointer, groups length, and `has_groups` flag matching the existing lower-level CommandExt facade.
- This batch does not model env maps, pipe Stdio redirection wiring, full heap `Command` objects, or capture-time CommandExt groups integration.
- Test file `std_process_command_builder_groups_macro_surface.sa` (panic ID 10686).

Focused validation only:
- `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_process_command_builder_groups_macro_surface.sa --jobs 1 --trace-panic` -> `1 passed; 0 failed; 0 skipped`.

Panic IDs next free: 10687+.
Still blocked without redesign: generic primitive/container trait impl dispatch, cross-width integer conversions, generic `NonZero<T>`, generic `Wrapping<T>` / `Saturating<T>`, `u128` / `i128` public primitive support, portable target-width `usize` / `isize` switching beyond the current explicit 64-bit ABI, missing concrete wrapper widths, Rust feature-gate modeling, Rust niche optimization, Rust unsafe UB enforcement, Rust panic message/object behavior, parser/formatter trait integration, allocator/drop/borrow semantics, randomized `RandomState`, SipHash compatibility, Rust iterator trait hierarchy, generic `Option` / `Result` / `ControlFlow`, generic `FromIterator`, `IntoIterator`, true format!, Condvar/Barrier, process env maps / Stdio redirection, path component iterators, and thread stack/name builder ABI.


## Active std parity batch (2026-07-16 Process Command builder uid/gid)

Completed supportable process Command builder uid/gid wrappers:
- `PROCESS_COMMAND_BUILDER_STATUS_UID_GID` and `PROCESS_COMMAND_BUILDER_SPAWN_UID_GID` forward the existing builder scalar state into the real `PROCESS_*_COMMAND_EXT_UID_GID` runtime paths.
- These helpers preserve the current builder fields (`cwd`, `arg0`, `process_group`, `setsid`) and add explicit `uid` / `gid` values plus `has_uid` / `has_gid` flags matching the existing lower-level CommandExt facade.
- This batch does not model env maps, pipe Stdio redirection wiring, full heap `Command` objects, or capture-time CommandExt uid/gid integration.
- Test file `std_process_command_builder_uid_gid_macro_surface.sa` (panic ID 10685).

Focused validation only:
- `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_process_command_builder_uid_gid_macro_surface.sa --jobs 1 --trace-panic` -> `1 passed; 0 failed; 0 skipped`.

Panic IDs next free: 10686+.
Still blocked without redesign: generic primitive/container trait impl dispatch, cross-width integer conversions, generic `NonZero<T>`, generic `Wrapping<T>` / `Saturating<T>`, `u128` / `i128` public primitive support, portable target-width `usize` / `isize` switching beyond the current explicit 64-bit ABI, missing concrete wrapper widths, Rust feature-gate modeling, Rust niche optimization, Rust unsafe UB enforcement, Rust panic message/object behavior, parser/formatter trait integration, allocator/drop/borrow semantics, randomized `RandomState`, SipHash compatibility, Rust iterator trait hierarchy, generic `Option` / `Result` / `ControlFlow`, generic `FromIterator`, `IntoIterator`, true format!, Condvar/Barrier, process env maps / Stdio redirection, path component iterators, and thread stack/name builder ABI.


## Active std parity batch (2026-07-16 Process Command builder pidfd)

Completed supportable process Command builder pidfd wrappers:
- `PROCESS_COMMAND_BUILDER_STATUS_PIDFD` and `PROCESS_COMMAND_BUILDER_SPAWN_PIDFD` forward the existing builder scalar state into the real `PROCESS_*_COMMAND_EXT_PIDFD` runtime paths.
- These helpers preserve the current builder fields (`cwd`, `arg0`, `process_group`, `setsid`) and add an explicit `create_pidfd` flag matching the existing lower-level PIDFD facade.
- This batch does not model env maps, pipe Stdio redirection wiring, full heap `Command` objects, or capture-time CommandExt pidfd integration.
- Test file `std_process_command_builder_pidfd_macro_surface.sa` (panic ID 10684).

Focused validation only:
- `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_process_command_builder_pidfd_macro_surface.sa --jobs 1 --trace-panic` -> `1 passed; 0 failed; 0 skipped`.

Panic IDs next free: 10685+.
Still blocked without redesign: generic primitive/container trait impl dispatch, cross-width integer conversions, generic `NonZero<T>`, generic `Wrapping<T>` / `Saturating<T>`, `u128` / `i128` public primitive support, portable target-width `usize` / `isize` switching beyond the current explicit 64-bit ABI, missing concrete wrapper widths, Rust feature-gate modeling, Rust niche optimization, Rust unsafe UB enforcement, Rust panic message/object behavior, parser/formatter trait integration, allocator/drop/borrow semantics, randomized `RandomState`, SipHash compatibility, Rust iterator trait hierarchy, generic `Option` / `Result` / `ControlFlow`, generic `FromIterator`, `IntoIterator`, true format!, Condvar/Barrier, process env maps / Stdio redirection, path component iterators, and thread stack/name builder ABI.


## Active std parity batch (2026-07-16 Process Stdio value object)

Completed supportable `std::process::Stdio` value-object helpers:
- `ProcessStdio_*` layout constants record a local one-byte kind value for inherit, piped, and null.
- `PROCESS_STDIO_PIPED`, `PROCESS_STDIO_INHERIT`, `PROCESS_STDIO_NULL`, `PROCESS_STDIO_KIND`, and `PROCESS_STDIO_MAKES_PIPE` expose Rust `Stdio::{piped,inherit,null}` and `makes_pipe` naming over that local value.
- This batch does not wire Stdio values into `Command` spawn/capture redirection because the current process runtime ABI has no stdin/stdout/stderr configuration slots; env maps and full command objects remain blocked.
- Test file `std_process_stdio_macro_surface.sa` (panic ID 10683).

Focused validation only:
- `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_process_stdio_macro_surface.sa --jobs 1 --trace-panic` -> `1 passed; 0 failed; 0 skipped`.

Panic IDs next free: 10684+.
Still blocked without redesign: generic primitive/container trait impl dispatch, cross-width integer conversions, generic `NonZero<T>`, generic `Wrapping<T>` / `Saturating<T>`, `u128` / `i128` public primitive support, portable target-width `usize` / `isize` switching beyond the current explicit 64-bit ABI, missing concrete wrapper widths, Rust feature-gate modeling, Rust niche optimization, Rust unsafe UB enforcement, Rust panic message/object behavior, parser/formatter trait integration, allocator/drop/borrow semantics, randomized `RandomState`, SipHash compatibility, Rust iterator trait hierarchy, generic `Option` / `Result` / `ControlFlow`, generic `FromIterator`, `IntoIterator`, true format!, Condvar/Barrier, process env maps / Stdio redirection, and thread stack/name builder ABI.


## Active std parity batch (2026-07-16 SaturatingI64 arithmetic)

Completed supportable `SaturatingI64` arithmetic helpers:
- `SATURATING_I64_SET` stores the raw 64-bit wrapper value shape.
- `SATURATING_I64_ADD`, `SATURATING_I64_SUB`, and `SATURATING_I64_MUL` expose Rust `Saturating<i64>` add/sub/mul operator forwarding over the existing concrete wrapper layout.
- Helpers load wrapper inner fields as signed `i64`, reuse existing `NUM_I64_SATURATING_*` primitive helpers, and store the saturated result.
- This batch does not model generic `Saturating<T>`, assignment operator traits, missing wrapper widths, `i128`, or trait-level dispatch.
- Test file `std_num_saturating_i64_arithmetic_macro_surface.sa` (panic ID 10682).

Focused validation only:
- `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_num_saturating_i64_arithmetic_macro_surface.sa --jobs 1 --trace-panic` -> `1 passed; 0 failed; 0 skipped`.

Panic IDs next free: 10683+.
Still blocked without redesign: generic primitive/container trait impl dispatch, cross-width integer conversions, generic `NonZero<T>`, generic `Wrapping<T>` / `Saturating<T>`, `u128` / `i128` public primitive support, portable target-width `usize` / `isize` switching beyond the current explicit 64-bit ABI, missing concrete wrapper widths, Rust feature-gate modeling, Rust niche optimization, Rust unsafe UB enforcement, Rust panic message/object behavior, parser/formatter trait integration, allocator/drop/borrow semantics, randomized `RandomState`, SipHash compatibility, Rust iterator trait hierarchy, generic `Option` / `Result` / `ControlFlow`, generic `FromIterator`, `IntoIterator`, true format!, Condvar/Barrier, process env maps/Stdio objects, and thread stack/name builder ABI.


## Active std parity batch (2026-07-16 WrappingI64 arithmetic)

Completed supportable `WrappingI64` arithmetic helpers:
- `WRAPPING_I64_SET` stores the raw 64-bit wrapper value shape.
- `WRAPPING_I64_ADD`, `WRAPPING_I64_SUB`, and `WRAPPING_I64_MUL` expose Rust `Wrapping<i64>` add/sub/mul operator forwarding over the existing concrete wrapper layout.
- Helpers load wrapper inner fields as signed `i64`, reuse existing `NUM_I64_WRAPPING_*` primitive helpers, and store the 64-bit wrapping result.
- This batch does not model generic `Wrapping<T>`, assignment operator traits, missing wrapper widths, `i128`, or trait-level dispatch.
- Test file `std_num_wrapping_i64_arithmetic_macro_surface.sa` (panic ID 10681).

Focused validation only:
- `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_num_wrapping_i64_arithmetic_macro_surface.sa --jobs 1 --trace-panic` -> `1 passed; 0 failed; 0 skipped`.

Panic IDs next free: 10682+.
Still blocked without redesign: generic primitive/container trait impl dispatch, cross-width integer conversions, generic `NonZero<T>`, generic `Wrapping<T>` / `Saturating<T>`, `u128` / `i128` public primitive support, portable target-width `usize` / `isize` switching beyond the current explicit 64-bit ABI, missing concrete wrapper widths, Rust feature-gate modeling, Rust niche optimization, Rust unsafe UB enforcement, Rust panic message/object behavior, parser/formatter trait integration, allocator/drop/borrow semantics, randomized `RandomState`, SipHash compatibility, Rust iterator trait hierarchy, generic `Option` / `Result` / `ControlFlow`, generic `FromIterator`, `IntoIterator`, true format!, Condvar/Barrier, process env maps/Stdio objects, and thread stack/name builder ABI.


## Active std parity batch (2026-07-16 WrappingU32 arithmetic)

Completed supportable `WrappingU32` arithmetic helpers:
- `WRAPPING_U32_SET` stores raw values masked to the concrete 32-bit width.
- `WRAPPING_U32_ADD`, `WRAPPING_U32_SUB`, and `WRAPPING_U32_MUL` expose Rust `Wrapping<u32>` add/sub/mul operator forwarding over the existing concrete wrapper layout.
- Helpers load wrapper inner fields, reuse existing `NUM_U32_WRAPPING_*` primitive helpers, and store a masked `WrappingU32` result.
- This batch does not model generic `Wrapping<T>`, assignment operator traits, missing wrapper widths, `u128`, or trait-level dispatch.
- Test file `std_num_wrapping_u32_arithmetic_macro_surface.sa` (panic ID 10680).

Focused validation only:
- `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_num_wrapping_u32_arithmetic_macro_surface.sa --jobs 1 --trace-panic` -> `1 passed; 0 failed; 0 skipped`.

Panic IDs next free: 10681+.
Still blocked without redesign: generic primitive/container trait impl dispatch, cross-width integer conversions, generic `NonZero<T>`, generic `Wrapping<T>` / `Saturating<T>`, `u128` / `i128` public primitive support, portable target-width `usize` / `isize` switching beyond the current explicit 64-bit ABI, missing concrete wrapper widths, Rust feature-gate modeling, Rust niche optimization, Rust unsafe UB enforcement, Rust panic message/object behavior, parser/formatter trait integration, allocator/drop/borrow semantics, randomized `RandomState`, SipHash compatibility, Rust iterator trait hierarchy, generic `Option` / `Result` / `ControlFlow`, generic `FromIterator`, `IntoIterator`, true format!, Condvar/Barrier, process env maps/Stdio objects, and thread stack/name builder ABI.


## Active std parity batch (2026-07-16 usize saturating div alias)

Completed supportable `usize` saturating division helper:
- `NUM_USIZE_SATURATING_DIV` exposes the current 64-bit target `usize` alias over `NUM_U64_SATURATING_DIV`.
- The helper writes the quotient on checked-division success and `NUM_USIZE_MAX` on checked failure, including zero divisors.
- This batch follows the current SA `NUM_U64_SATURATING_DIV` surface shape; Rust unsigned `saturating_div` panics on zero divisors rather than returning MAX. It does not model portable target-width switching, Rust panic object/message identity, `u128`, or trait-level dispatch.
- Test file `std_num_usize_saturating_div_macro_surface.sa` (panic ID 10679).

Focused validation only:
- `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_num_usize_saturating_div_macro_surface.sa --jobs 1 --trace-panic` -> `1 passed; 0 failed; 0 skipped`.

Panic IDs next free: 10680+.
Still blocked without redesign: generic primitive/container trait impl dispatch, cross-width integer conversions, generic `NonZero<T>`, generic `Wrapping<T>` / `Saturating<T>`, `u128` / `i128` public primitive support, portable target-width `usize` / `isize` switching beyond the current explicit 64-bit ABI, missing concrete wrapper widths, Rust feature-gate modeling, Rust niche optimization, Rust unsafe UB enforcement, Rust panic message/object behavior, parser/formatter trait integration, allocator/drop/borrow semantics, randomized `RandomState`, SipHash compatibility, Rust iterator trait hierarchy, generic `Option` / `Result` / `ControlFlow`, generic `FromIterator`, `IntoIterator`, true format!, Condvar/Barrier, process env maps/Stdio objects, and thread stack/name builder ABI.


## Active std parity batch (2026-07-16 narrow unsigned primitive saturating div)

Completed supportable narrow unsigned primitive saturating division helpers:
- `NUM_U{8,16,32}_SATURATING_DIV` exposes direct saturating division helpers for narrow unsigned widths.
- Helpers reuse the existing narrow checked division paths, write the quotient on success, and write the matching unsigned MAX value on checked failure, including zero divisors or raw quotient values outside the declared narrow width.
- This batch follows the current SA `NUM_U64_SATURATING_DIV` surface shape; Rust unsigned `saturating_div` panics on zero divisors rather than returning MAX. It does not model Rust panic object/message identity, `u128`, or trait-level dispatch.
- Test file `std_num_narrow_unsigned_saturating_div_macro_surface.sa` (panic ID 10678).

Focused validation only:
- `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_num_narrow_unsigned_saturating_div_macro_surface.sa --jobs 1 --trace-panic` -> `1 passed; 0 failed; 0 skipped`.

Panic IDs next free: 10679+.
Still blocked without redesign: generic primitive/container trait impl dispatch, cross-width integer conversions, generic `NonZero<T>`, generic `Wrapping<T>` / `Saturating<T>`, `u128` / `i128` public primitive support, portable target-width `usize` / `isize` switching, missing concrete wrapper widths, Rust feature-gate modeling, Rust niche optimization, Rust unsafe UB enforcement, Rust panic message/object behavior, parser/formatter trait integration, allocator/drop/borrow semantics, randomized `RandomState`, SipHash compatibility, Rust iterator trait hierarchy, generic `Option` / `Result` / `ControlFlow`, generic `FromIterator`, `IntoIterator`, true format!, Condvar/Barrier, process env maps/Stdio objects, and thread stack/name builder ABI.


## Active std parity batch (2026-07-16 narrow signed primitive pow)

Completed supportable narrow signed primitive direct pow helpers:
- `NUM_I{8,16,32}_POW` exposes direct signed primitive pow helpers for narrow widths.
- Helpers sign-extend the base to the declared signed width, reuse the existing `i64` direct pow accumulator, and sign-extend the result back to the concrete narrow width.
- This batch models current SA direct pow / release-style wrapping result semantics, not Rust debug overflow panic object/message identity, `i128`, or trait-level dispatch.
- Test file `std_num_narrow_signed_pow_macro_surface.sa` (panic ID 10677).

Focused validation only:
- `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_num_narrow_signed_pow_macro_surface.sa --jobs 1 --trace-panic` -> `1 passed; 0 failed; 0 skipped`.

Panic IDs next free: 10678+.
Still blocked without redesign: generic primitive/container trait impl dispatch, cross-width integer conversions, generic `NonZero<T>`, generic `Wrapping<T>` / `Saturating<T>`, `u128` / `i128` public primitive support, portable target-width `usize` / `isize` switching, missing concrete wrapper widths, Rust feature-gate modeling, Rust niche optimization, Rust unsafe UB enforcement, Rust panic message/object behavior, parser/formatter trait integration, allocator/drop/borrow semantics, randomized `RandomState`, SipHash compatibility, Rust iterator trait hierarchy, generic `Option` / `Result` / `ControlFlow`, generic `FromIterator`, `IntoIterator`, true format!, Condvar/Barrier, process env maps/Stdio objects, and thread stack/name builder ABI.


## Active std parity batch (2026-07-16 narrow signed primitive ilog)

Completed supportable narrow signed primitive integer-log helpers:
- `NUM_I{8,16,32}_CHECKED_ILOG` and `NUM_I{8,16,32}_ILOG` expose arbitrary-base signed integer-log helpers for narrow widths.
- `NUM_I{8,16,32}_CHECKED_ILOG2` / `ILOG2` and `NUM_I{8,16,32}_CHECKED_ILOG10` / `ILOG10` expose the base-2 and base-10 variants.
- Helpers sign-extend values and bases to the declared signed width before delegating to the existing `i64` signed log implementation.
- Checked helpers return explicit `ok/value` pairs for nonpositive values or bases below 2; direct helpers write `0` on checked failure like the current SA direct `i64` surface.
- This batch models concrete result semantics, not Rust panic object/message identity, `i128`, or trait-level dispatch.
- Test file `std_num_narrow_signed_ilog_macro_surface.sa` (panic ID 10676).

Focused validation only:
- `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_num_narrow_signed_ilog_macro_surface.sa --jobs 1 --trace-panic` -> `1 passed; 0 failed; 0 skipped`.

Panic IDs next free: 10677+.
Still blocked without redesign: generic primitive/container trait impl dispatch, cross-width integer conversions, generic `NonZero<T>`, generic `Wrapping<T>` / `Saturating<T>`, `u128` / `i128` public primitive support, portable target-width `usize` / `isize` switching, missing concrete wrapper widths, Rust feature-gate modeling, Rust niche optimization, Rust unsafe UB enforcement, Rust panic message/object behavior, parser/formatter trait integration, allocator/drop/borrow semantics, randomized `RandomState`, SipHash compatibility, Rust iterator trait hierarchy, generic `Option` / `Result` / `ControlFlow`, generic `FromIterator`, `IntoIterator`, true format!, Condvar/Barrier, process env maps/Stdio objects, and thread stack/name builder ABI.


## Active std parity batch (2026-07-16 narrow signed primitive next-multiple)

Completed supportable narrow signed primitive next-multiple helpers:
- `NUM_I{8,16,32}_CHECKED_NEXT_MULTIPLE_OF` exposes checked next-multiple helpers for narrow signed widths.
- `NUM_I{8,16,32}_NEXT_MULTIPLE_OF` exposes matching direct helpers.
- Helpers sign-extend operands to the declared signed width, reuse the existing `i64` checked next-multiple implementation, and reject results outside each narrow signed range.
- This batch follows the current SA signed next-multiple subset where negative divisors use absolute magnitude, and direct helpers write `0` on checked failure. It does not model Rust panic object/message identity, `i128`, or trait-level dispatch.
- Test file `std_num_narrow_signed_next_multiple_macro_surface.sa` (panic ID 10675).

Focused validation only:
- `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_num_narrow_signed_next_multiple_macro_surface.sa --jobs 1 --trace-panic` -> `1 passed; 0 failed; 0 skipped`.

Panic IDs next free: 10676+.
Still blocked without redesign: generic primitive/container trait impl dispatch, cross-width integer conversions, generic `NonZero<T>`, generic `Wrapping<T>` / `Saturating<T>`, `u128` / `i128` public primitive support, portable target-width `usize` / `isize` switching, missing concrete wrapper widths, Rust feature-gate modeling, Rust niche optimization, Rust unsafe UB enforcement, Rust panic message/object behavior, parser/formatter trait integration, allocator/drop/borrow semantics, randomized `RandomState`, SipHash compatibility, Rust iterator trait hierarchy, generic `Option` / `Result` / `ControlFlow`, generic `FromIterator`, `IntoIterator`, true format!, Condvar/Barrier, process env maps/Stdio objects, and thread stack/name builder ABI.


## Active std parity batch (2026-07-16 narrow signed primitive div_ceil)

Completed supportable narrow signed primitive ceil-division helpers:
- `NUM_I{8,16,32}_CHECKED_DIV_CEIL` exposes Rust signed primitive checked ceil division for narrow widths.
- `NUM_I{8,16,32}_DIV_CEIL` exposes the matching direct helper shape for narrow widths.
- Helpers reuse each width's existing checked signed division, reject zero divisors and signed `MIN / -1`, and adjust the truncating quotient by `+1` only for same-sign operands with a nonzero remainder.
- This batch models concrete result semantics and current SA direct-helper failure shape, not Rust panic object/message identity, `i128`, or trait-level dispatch.
- Test file `std_num_narrow_signed_div_ceil_macro_surface.sa` (panic ID 10674).

Focused validation only:
- `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_num_narrow_signed_div_ceil_macro_surface.sa --jobs 1 --trace-panic` -> `1 passed; 0 failed; 0 skipped`.

Panic IDs next free: 10675+.
Still blocked without redesign: generic primitive/container trait impl dispatch, cross-width integer conversions, generic `NonZero<T>`, generic `Wrapping<T>` / `Saturating<T>`, `u128` / `i128` public primitive support, portable target-width `usize` / `isize` switching, missing concrete wrapper widths, Rust feature-gate modeling, Rust niche optimization, Rust unsafe UB enforcement, Rust panic message/object behavior, parser/formatter trait integration, allocator/drop/borrow semantics, randomized `RandomState`, SipHash compatibility, Rust iterator trait hierarchy, generic `Option` / `Result` / `ControlFlow`, generic `FromIterator`, `IntoIterator`, true format!, Condvar/Barrier, process env maps/Stdio objects, and thread stack/name builder ABI.


## Active std parity batch (2026-07-16 narrow signed primitive midpoint)

Completed supportable narrow signed primitive midpoint helpers:
- `NUM_I{8,16,32}_MIDPOINT` exposes Rust signed primitive midpoint helpers for narrow widths.
- Helpers sign-extend operands to the declared signed width, reuse the existing `i64` midpoint path, and sign-extend the result back to the concrete narrow width.
- This batch models concrete sufficiently-wide signed average semantics rounded toward zero, not Rust trait dispatch, `i128`, panic object identity, or generic numeric abstractions.
- Test file `std_num_narrow_signed_midpoint_macro_surface.sa` (panic ID 10673).

Focused validation only:
- `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_num_narrow_signed_midpoint_macro_surface.sa --jobs 1 --trace-panic` -> `1 passed; 0 failed; 0 skipped`.

Panic IDs next free: 10674+.
Still blocked without redesign: generic primitive/container trait impl dispatch, cross-width integer conversions, generic `NonZero<T>`, generic `Wrapping<T>` / `Saturating<T>`, `u128` / `i128` public primitive support, portable target-width `usize` / `isize` switching, missing concrete wrapper widths, Rust feature-gate modeling, Rust niche optimization, Rust unsafe UB enforcement, Rust panic message/object behavior, parser/formatter trait integration, allocator/drop/borrow semantics, randomized `RandomState`, SipHash compatibility, Rust iterator trait hierarchy, generic `Option` / `Result` / `ControlFlow`, generic `FromIterator`, `IntoIterator`, true format!, Condvar/Barrier, process env maps/Stdio objects, and thread stack/name builder ABI.


## Active std parity batch (2026-07-16 narrow signed direct Euclidean div/rem)

Completed supportable narrow signed direct Euclidean division/remainder helpers:
- `NUM_I{8,16,32}_DIV_EUCLID` exposes Rust signed primitive direct Euclidean quotient helpers for narrow widths.
- `NUM_I{8,16,32}_REM_EUCLID` exposes the matching direct least-nonnegative Euclidean remainder helpers.
- Helpers reuse the existing checked Euclidean paths and match the existing `i64` direct helper shape. Existing `STRICT_*_EUCLID` helpers remain the panic-control-flow surface.
- This batch models concrete success-result semantics for current signed widths, not Rust panic object/message identity, `i128`, or trait-level dispatch.
- Test file `std_num_narrow_signed_euclid_macro_surface.sa` (panic ID 10672).

Focused validation only:
- `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_num_narrow_signed_euclid_macro_surface.sa --jobs 1 --trace-panic` -> `1 passed; 0 failed; 0 skipped`.

Panic IDs next free: 10673+.
Still blocked without redesign: generic primitive/container trait impl dispatch, cross-width integer conversions, generic `NonZero<T>`, generic `Wrapping<T>` / `Saturating<T>`, `u128` / `i128` public primitive support, portable target-width `usize` / `isize` switching, missing concrete wrapper widths, Rust feature-gate modeling, Rust niche optimization, Rust unsafe UB enforcement, Rust panic message/object behavior, parser/formatter trait integration, allocator/drop/borrow semantics, randomized `RandomState`, SipHash compatibility, Rust iterator trait hierarchy, generic `Option` / `Result` / `ControlFlow`, generic `FromIterator`, `IntoIterator`, true format!, Condvar/Barrier, process env maps/Stdio objects, and thread stack/name builder ABI.


## Active std parity batch (2026-07-16 narrow signed primitive bit helpers)

Completed supportable narrow signed primitive bit-pattern helpers:
- `NUM_I{8,16,32}_COUNT_ONES`, `COUNT_ZEROS`, `LEADING_ZEROS`, `TRAILING_ZEROS`, `LEADING_ONES`, and `TRAILING_ONES` expose Rust signed primitive count/scan methods for narrow widths.
- `NUM_I{8,16,32}_ISOLATE_HIGHEST_ONE`, `ISOLATE_LOWEST_ONE`, `HIGHEST_ONE`, and `LOWEST_ONE` expose the signed primitive bit-isolation and bit-position helpers for narrow widths.
- Helpers reuse existing same-width unsigned bit helpers, then sign-extend isolate results back to the signed width where the Rust return type is signed.
- `highest_one` / `lowest_one` keep the existing explicit `ok/index` shape for Rust's `Option<u32>` result, returning `ok=0/index=0` for zero input.
- This batch models concrete same-width signed bit-pattern semantics, not Rust `Option` layout, `i128`, or trait-level dispatch.
- Test file `std_num_narrow_signed_bit_macro_surface.sa` (panic ID 10671).

Focused validation only:
- `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_num_narrow_signed_bit_macro_surface.sa --jobs 1 --trace-panic` -> `1 passed; 0 failed; 0 skipped`.

Panic IDs next free: 10672+.
Still blocked without redesign: generic primitive/container trait impl dispatch, cross-width integer conversions, generic `NonZero<T>`, generic `Wrapping<T>` / `Saturating<T>`, `u128` / `i128` public primitive support, portable target-width `usize` / `isize` switching, missing concrete wrapper widths, Rust feature-gate modeling, Rust niche optimization, Rust unsafe UB enforcement, Rust panic message/object behavior, parser/formatter trait integration, allocator/drop/borrow semantics, randomized `RandomState`, SipHash compatibility, Rust iterator trait hierarchy, generic `Option` / `Result` / `ControlFlow`, generic `FromIterator`, `IntoIterator`, true format!, Condvar/Barrier, process env maps/Stdio objects, and thread stack/name builder ABI.


## Active std parity batch (2026-07-16 isize primitive bit helpers)

Completed supportable 64-bit `isize` bit-pattern helper aliases:
- `NUM_ISIZE_COUNT_ONES`, `COUNT_ZEROS`, `LEADING_ZEROS`, `TRAILING_ZEROS`, `LEADING_ONES`, and `TRAILING_ONES` expose the signed primitive count/scan helpers through the current 64-bit SA `isize` ABI.
- `NUM_ISIZE_ISOLATE_HIGHEST_ONE`, `ISOLATE_LOWEST_ONE`, `HIGHEST_ONE`, and `LOWEST_ONE` expose the signed primitive bit-isolation and bit-position helpers through existing `i64` behavior.
- `highest_one` / `lowest_one` keep the existing explicit `ok/index` shape for Rust's `Option<u32>` result, returning `ok=0/index=0` for zero input.
- This batch models concrete 64-bit target semantics, not portable target-width switching, Rust `Option` layout, `i128`, or trait-level dispatch.
- Test file `std_num_isize_bit_macro_surface.sa` (panic ID 10670).

Focused validation only:
- `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_num_isize_bit_macro_surface.sa --jobs 1 --trace-panic` -> `1 passed; 0 failed; 0 skipped`.

Panic IDs next free: 10671+.
Still blocked without redesign: generic primitive/container trait impl dispatch, cross-width integer conversions, generic `NonZero<T>`, generic `Wrapping<T>` / `Saturating<T>`, `u128` / `i128` public primitive support, portable target-width `usize` / `isize` switching, missing concrete wrapper widths, Rust feature-gate modeling, Rust niche optimization, Rust unsafe UB enforcement, Rust panic message/object behavior, parser/formatter trait integration, allocator/drop/borrow semantics, randomized `RandomState`, SipHash compatibility, Rust iterator trait hierarchy, generic `Option` / `Result` / `ControlFlow`, generic `FromIterator`, `IntoIterator`, true format!, Condvar/Barrier, process env maps/Stdio objects, and thread stack/name builder ABI.


## Active std parity batch (2026-07-16 narrow unsigned primitive unchecked)

Completed supportable narrow unsigned primitive unchecked helpers:
- `NUM_U{8,16,32}_UNCHECKED_ADD`, `UNCHECKED_SUB`, and `UNCHECKED_MUL` expose Rust's unsigned primitive unchecked arithmetic shapes for narrow widths.
- `NUM_U{8,16,32}_UNCHECKED_DIV` and `UNCHECKED_REM` expose the matching unchecked division/remainder helpers.
- `NUM_U{8,16,32}_UNCHECKED_SHL` and `UNCHECKED_SHR` expose Rust's unchecked shift shapes for narrow widths.
- Helpers model caller-precondition lowering for legal inputs only, with no runtime UB enforcement. Narrow arithmetic/shift helpers mask results to the declared Rust width; division/remainder mask operands and still rely on the underlying operation for invalid zero-divisor traps.
- This batch models concrete result/control-flow semantics for valid inputs, not Rust unsafe UB enforcement, `u128`, or trait-level dispatch.
- Test file `std_num_narrow_unchecked_macro_surface.sa` (panic ID 10669).

Focused validation only:
- `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_num_narrow_unchecked_macro_surface.sa --jobs 1 --trace-panic` -> `1 passed; 0 failed; 0 skipped`.

Panic IDs next free: 10670+.
Still blocked without redesign: generic primitive/container trait impl dispatch, cross-width integer conversions, generic `NonZero<T>`, generic `Wrapping<T>` / `Saturating<T>`, `u128` / `i128` public primitive support, missing concrete wrapper widths, Rust feature-gate modeling, Rust niche optimization, Rust unsafe UB enforcement, Rust panic message/object behavior, parser/formatter trait integration, allocator/drop/borrow semantics, randomized `RandomState`, SipHash compatibility, Rust iterator trait hierarchy, generic `Option` / `Result` / `ControlFlow`, generic `FromIterator`, `IntoIterator`, true format!, Condvar/Barrier, process env maps/Stdio objects, and thread stack/name builder ABI.


## Active std parity batch (2026-07-16 unsigned primitive wrapping/euclidean division)

Completed supportable unsigned primitive wrapping and Euclidean division helpers:
- `NUM_U{8,16,32}_DIV_EUCLID` and `NUM_U{8,16,32}_REM_EUCLID` expose Rust's unsigned Euclidean division and remainder shapes for narrow widths.
- `NUM_U{8,16,32,64,SIZE}_WRAPPING_DIV_EUCLID` and `NUM_U{8,16,32,64,SIZE}_WRAPPING_REM_EUCLID` expose Rust's unsigned wrapping Euclidean aliases for every current unsigned width.
- `NUM_U{8,16,32,SIZE}_WRAPPING_DIV` and `NUM_U{8,16,32,SIZE}_WRAPPING_REM` fill the non-euclidean wrapping division/remainder aliases that were missing outside `u64`.
- Narrow helpers mask operands to the declared Rust width before ordinary unsigned division/remainder; `usize` aliases the current 64-bit SA ABI.
- This batch models concrete result/control-flow semantics, not Rust panic object identity, `u128`, or trait-level dispatch.
- Test file `std_num_unsigned_wrapping_div_macro_surface.sa` (panic ID 10668).

Focused validation only:
- `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_num_unsigned_wrapping_div_macro_surface.sa --jobs 1 --trace-panic` -> `1 passed; 0 failed; 0 skipped`.

Panic IDs next free: 10669+.
Still blocked without redesign: generic primitive/container trait impl dispatch, cross-width integer conversions, generic `NonZero<T>`, generic `Wrapping<T>` / `Saturating<T>`, `u128` / `i128` public primitive support, missing concrete wrapper widths, Rust feature-gate modeling, Rust niche optimization, Rust unsafe UB enforcement, Rust panic message/object behavior, parser/formatter trait integration, allocator/drop/borrow semantics, randomized `RandomState`, SipHash compatibility, Rust iterator trait hierarchy, generic `Option` / `Result` / `ControlFlow`, generic `FromIterator`, `IntoIterator`, true format!, Condvar/Barrier, process env maps/Stdio objects, and thread stack/name builder ABI.


## Active std parity batch (2026-07-16 narrow unsigned primitive ilog)

Completed supportable narrow unsigned primitive integer-log helpers:
- `NUM_U{8,16,32}_CHECKED_ILOG` and `NUM_U{8,16,32}_ILOG` expose Rust's arbitrary-base unsigned primitive integer-log shapes for narrow widths.
- `NUM_U{8,16,32}_CHECKED_ILOG2` / `ILOG2` and `NUM_U{8,16,32}_CHECKED_ILOG10` / `ILOG10` expose the base-2 and base-10 variants for the same widths.
- Narrow helpers mask values and arbitrary bases to the declared Rust width before reusing the existing `u64` floor-log implementation; current `usize` support was already present as a 64-bit alias.
- Checked helpers return explicit `ok/out` values for zero values or bases below 2, while direct helpers write `0` on checked failure like the existing SA direct `u64` surface.
- This batch models concrete result/control-flow semantics, not Rust panic object identity, `u128`, const/static-known optimization branches, or trait-level dispatch.
- Test file `std_num_narrow_ilog_macro_surface.sa` (panic ID 10667).

Focused validation only:
- `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_num_narrow_ilog_macro_surface.sa --jobs 1 --trace-panic` -> `1 passed; 0 failed; 0 skipped`.

Panic IDs next free: 10668+.
Still blocked without redesign: generic primitive/container trait impl dispatch, cross-width integer conversions, generic `NonZero<T>`, generic `Wrapping<T>` / `Saturating<T>`, `u128` / `i128` public primitive support, missing concrete wrapper widths, Rust feature-gate modeling, Rust niche optimization, Rust unsafe UB enforcement, Rust panic message/object behavior, parser/formatter trait integration, allocator/drop/borrow semantics, randomized `RandomState`, SipHash compatibility, Rust iterator trait hierarchy, generic `Option` / `Result` / `ControlFlow`, generic `FromIterator`, `IntoIterator`, true format!, Condvar/Barrier, process env maps/Stdio objects, and thread stack/name builder ABI.


## Active std parity batch (2026-07-16 narrow unsigned primitive multiples/ceil)

Completed supportable narrow unsigned primitive multiples and ceil helpers:
- `NUM_U{8,16,32}_IS_MULTIPLE_OF` exposes Rust's unsigned primitive multiple predicate for narrow widths.
- `NUM_U{8,16,32}_CHECKED_NEXT_MULTIPLE_OF` and `NUM_U{8,16,32}_NEXT_MULTIPLE_OF` expose checked and direct next-multiple shapes.
- `NUM_U{8,16,32}_DIV_CEIL` exposes unsigned ceil division for narrow widths.
- Narrow helpers mask inputs to the declared Rust width and reuse existing `u64` behavior where appropriate; current `usize` support was already present as a 64-bit alias.
- This batch models concrete result/control-flow semantics, not Rust panic object identity, `u128`, or trait-level dispatch.
- Test file `std_num_narrow_multiples_macro_surface.sa` (panic ID 10666).

Focused validation only:
- `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_num_narrow_multiples_macro_surface.sa --jobs 1 --trace-panic` -> `1 passed; 0 failed; 0 skipped`.

Panic IDs next free: 10667+.
Still blocked without redesign: generic primitive/container trait impl dispatch, cross-width integer conversions, generic `NonZero<T>`, generic `Wrapping<T>` / `Saturating<T>`, `u128` / `i128` public primitive support, missing concrete wrapper widths, Rust feature-gate modeling, Rust niche optimization, Rust unsafe UB enforcement, Rust panic message/object behavior, parser/formatter trait integration, allocator/drop/borrow semantics, randomized `RandomState`, SipHash compatibility, Rust iterator trait hierarchy, generic `Option` / `Result` / `ControlFlow`, generic `FromIterator`, `IntoIterator`, true format!, Condvar/Barrier, process env maps/Stdio objects, and thread stack/name builder ABI.


## Active std parity batch (2026-07-16 narrow unsigned primitive reverse bits)

Completed supportable narrow unsigned primitive reverse-bits helpers:
- `NUM_U{8,16,32,SIZE}_REVERSE_BITS` exposes Rust's unsigned primitive bit-reversal shape for the widths that were missing public SA macros.
- Narrow helpers mask inputs to the declared Rust width, reuse the existing `u64` reverse implementation, and shift the result back to the declared width.
- `usize` aliases the current 64-bit SA ABI.
- This batch models concrete result semantics, not compiler intrinsic selection, `u128`, or trait-level dispatch.
- Test file `std_num_narrow_reverse_bits_macro_surface.sa` (panic ID 10665).

Focused validation only:
- `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_num_narrow_reverse_bits_macro_surface.sa --jobs 1 --trace-panic` -> `1 passed; 0 failed; 0 skipped`.

Panic IDs next free: 10666+.
Still blocked without redesign: generic primitive/container trait impl dispatch, cross-width integer conversions, generic `NonZero<T>`, generic `Wrapping<T>` / `Saturating<T>`, `u128` / `i128` public primitive support, missing concrete wrapper widths, Rust feature-gate modeling, Rust niche optimization, Rust unsafe UB enforcement, Rust panic message/object behavior, parser/formatter trait integration, allocator/drop/borrow semantics, randomized `RandomState`, SipHash compatibility, Rust iterator trait hierarchy, generic `Option` / `Result` / `ControlFlow`, generic `FromIterator`, `IntoIterator`, true format!, Condvar/Barrier, process env maps/Stdio objects, and thread stack/name builder ABI.


## Active std parity batch (2026-07-16 narrow unsigned primitive rotate)

Completed supportable narrow unsigned primitive rotate helpers:
- `NUM_U{8,16,32,SIZE}_ROTATE_LEFT` exposes Rust's unsigned primitive left-rotate shape for the widths that were missing public SA macros.
- `NUM_U{8,16,32,SIZE}_ROTATE_RIGHT` exposes the matching right-rotate shape.
- Narrow helpers mask inputs to the declared Rust width and reduce shift amounts modulo the declared bit width; `usize` aliases the current 64-bit SA ABI.
- This batch models concrete result semantics, not compiler intrinsic selection, `u128`, or trait-level dispatch.
- Test file `std_num_narrow_rotate_macro_surface.sa` (panic ID 10664).

Focused validation only:
- `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_num_narrow_rotate_macro_surface.sa --jobs 1 --trace-panic` -> `1 passed; 0 failed; 0 skipped`.

Panic IDs next free: 10665+.
Still blocked without redesign: generic primitive/container trait impl dispatch, cross-width integer conversions, generic `NonZero<T>`, generic `Wrapping<T>` / `Saturating<T>`, `u128` / `i128` public primitive support, missing concrete wrapper widths, Rust feature-gate modeling, Rust niche optimization, Rust unsafe UB enforcement, Rust panic message/object behavior, parser/formatter trait integration, allocator/drop/borrow semantics, randomized `RandomState`, SipHash compatibility, Rust iterator trait hierarchy, generic `Option` / `Result` / `ControlFlow`, generic `FromIterator`, `IntoIterator`, true format!, Condvar/Barrier, process env maps/Stdio objects, and thread stack/name builder ABI.


## Active std parity batch (2026-07-16 narrow unsigned primitive bit positions)

Completed supportable narrow unsigned primitive bit-position helpers:
- `NUM_U{8,16,32,SIZE}_BIT_WIDTH` exposes Rust's unsigned primitive bit-width shape for the widths that were missing public SA macros.
- `NUM_U{8,16,32,SIZE}_ISOLATE_HIGHEST_ONE` and `NUM_U{8,16,32,SIZE}_ISOLATE_LOWEST_ONE` expose selected-bit value helpers.
- `NUM_U{8,16,32,SIZE}_HIGHEST_ONE` and `NUM_U{8,16,32,SIZE}_LOWEST_ONE` expose the matching optional bit-index shape as explicit `ok/index` outputs.
- Narrow helpers mask inputs to the declared Rust width; `usize` aliases the current 64-bit SA ABI.
- This batch models concrete result semantics, not Rust `Option` layout, compiler intrinsic selection, `u128`, or trait-level dispatch.
- Test file `std_num_narrow_bit_position_macro_surface.sa` (panic ID 10663).

Focused validation only:
- `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_num_narrow_bit_position_macro_surface.sa --jobs 1 --trace-panic` -> `1 passed; 0 failed; 0 skipped`.

Panic IDs next free: 10664+.
Still blocked without redesign: generic primitive/container trait impl dispatch, cross-width integer conversions, generic `NonZero<T>`, generic `Wrapping<T>` / `Saturating<T>`, `u128` / `i128` public primitive support, missing concrete wrapper widths, Rust feature-gate modeling, Rust niche optimization, Rust unsafe UB enforcement, Rust panic message/object behavior, parser/formatter trait integration, allocator/drop/borrow semantics, randomized `RandomState`, SipHash compatibility, Rust iterator trait hierarchy, generic `Option` / `Result` / `ControlFlow`, generic `FromIterator`, `IntoIterator`, true format!, Condvar/Barrier, process env maps/Stdio objects, and thread stack/name builder ABI.


## Active std parity batch (2026-07-16 narrow unsigned primitive bit counts)

Completed supportable narrow unsigned primitive bit count/zero-scan helpers:
- `NUM_U{8,16,32,SIZE}_{COUNT_ONES,COUNT_ZEROS,LEADING_ZEROS,TRAILING_ZEROS,LEADING_ONES,TRAILING_ONES}` exposes Rust's unsigned primitive bit count and zero/one scan shapes for the widths that were missing public SA macros.
- Narrow helpers mask inputs to the declared Rust width before counting.
- Leading/trailing zero and one counts use the declared Rust bit width for zero/all-one cases; `usize` aliases the current 64-bit SA ABI.
- This batch models concrete result semantics, not compiler intrinsic selection, `u128`, or trait-level dispatch.
- Test file `std_num_narrow_bit_counts_macro_surface.sa` (panic ID 10662).

Focused validation only:
- `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_num_narrow_bit_counts_macro_surface.sa --jobs 1 --trace-panic` -> `1 passed; 0 failed; 0 skipped`.

Panic IDs next free: 10663+.
Still blocked without redesign: generic primitive/container trait impl dispatch, cross-width integer conversions, generic `NonZero<T>`, generic `Wrapping<T>` / `Saturating<T>`, `u128` / `i128` public primitive support, missing concrete wrapper widths, Rust feature-gate modeling, Rust niche optimization, Rust unsafe UB enforcement, Rust panic message/object behavior, parser/formatter trait integration, allocator/drop/borrow semantics, randomized `RandomState`, SipHash compatibility, Rust iterator trait hierarchy, generic `Option` / `Result` / `ControlFlow`, generic `FromIterator`, `IntoIterator`, true format!, Condvar/Barrier, process env maps/Stdio objects, and thread stack/name builder ABI.


## Active std parity batch (2026-07-16 unsigned primitive checked/direct next power)

Completed supportable unsigned primitive checked/direct next-power helpers:
- `NUM_U{8,16,32,SIZE}_CHECKED_NEXT_POWER_OF_TWO` exposes Rust's stable unsigned primitive `checked_next_power_of_two` shape for the widths that were missing a public SA macro.
- `NUM_U{8,16,32,SIZE}_NEXT_POWER_OF_TWO` exposes the matching direct `next_power_of_two` helper shape, joining the existing `NUM_U64_*` support.
- Checked helpers return explicit `ok/out` values, while direct helpers reuse checked helpers and write `0` on overflow like the existing `NUM_U64_NEXT_POWER_OF_TWO` macro.
- Narrow helpers mask inputs to the declared Rust width; `usize` aliases the current 64-bit SA ABI.
- This batch models concrete result/control-flow semantics, not Rust `Option` layout, debug overflow panic object/message identity, `u128`, or trait-level dispatch.
- Test file `std_num_next_power_primitive_macro_surface.sa` (panic ID 10661).

Focused validation only:
- `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_num_next_power_primitive_macro_surface.sa --jobs 1 --trace-panic` -> `1 passed; 0 failed; 0 skipped`.

Panic IDs next free: 10662+.
Still blocked without redesign: generic primitive/container trait impl dispatch, cross-width integer conversions, generic `NonZero<T>`, generic `Wrapping<T>` / `Saturating<T>`, `u128` / `i128` public primitive support, missing concrete wrapper widths, Rust feature-gate modeling, Rust niche optimization, Rust unsafe UB enforcement, Rust panic message/object behavior, parser/formatter trait integration, allocator/drop/borrow semantics, randomized `RandomState`, SipHash compatibility, Rust iterator trait hierarchy, generic `Option` / `Result` / `ControlFlow`, generic `FromIterator`, `IntoIterator`, true format!, Condvar/Barrier, process env maps/Stdio objects, and thread stack/name builder ABI.


## Active std parity batch (2026-07-16 unsigned primitive wrapping next power)

Completed supportable unsigned primitive wrapping next-power helpers:
- `NUM_U{8,16,32,64,SIZE}_WRAPPING_NEXT_POWER_OF_TWO` exposes Rust's unstable unsigned primitive `wrapping_next_power_of_two` shape for every existing SA unsigned primitive width.
- Helpers return the smallest power of two greater than or equal to the input and return `0` when the result would exceed the concrete width.
- Narrow helpers mask inputs to the declared Rust width; `usize` aliases the current 64-bit SA ABI.
- This batch also removes the prior signed NonZero isqrt helper/test/docs because Rust's local `nonzero.rs` places `NonZero<T>::isqrt` in the unsigned-only branch.
- This batch models concrete result semantics, not Rust feature-gate plumbing, debug overflow panic differences, `u128`, or trait-level dispatch.
- Test file `std_num_wrapping_next_power_primitive_macro_surface.sa` (panic ID 10660).

Focused validation only:
- `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_num_wrapping_next_power_primitive_macro_surface.sa --jobs 1 --trace-panic` -> `1 passed; 0 failed; 0 skipped`.

Panic IDs next free: 10661+.
Still blocked without redesign: generic primitive/container trait impl dispatch, cross-width integer conversions, generic `NonZero<T>`, generic `Wrapping<T>` / `Saturating<T>`, `u128` / `i128` public primitive support, missing concrete wrapper widths, Rust feature-gate modeling, Rust niche optimization, Rust unsafe UB enforcement, Rust panic message/object behavior, parser/formatter trait integration, allocator/drop/borrow semantics, randomized `RandomState`, SipHash compatibility, Rust iterator trait hierarchy, generic `Option` / `Result` / `ControlFlow`, generic `FromIterator`, `IntoIterator`, true format!, Condvar/Barrier, process env maps/Stdio objects, and thread stack/name builder ABI.


## Active std parity batch (2026-07-16 signed primitive overflowing div/rem/euclid)

Completed supportable signed primitive overflowing div/rem/euclid helpers:
- `NUM_I{8,16,32,64,SIZE}_OVERFLOWING_DIV` exposes Rust's signed primitive overflowing division shape for every existing SA signed width.
- `NUM_I{8,16,32,64,SIZE}_OVERFLOWING_DIV_EUCLID`, `NUM_I{8,16,32,64,SIZE}_OVERFLOWING_REM`, and `NUM_I{8,16,32,64,SIZE}_OVERFLOWING_REM_EUCLID` expose the matching Euclidean division and remainder shapes.
- Div helpers return `(MIN, true)` for `MIN / -1`; rem helpers return `(0, true)` for `MIN % -1`. Ordinary Euclidean helpers adjust negative remainders using Rust's quotient/remainder rules.
- Zero divisors trap through the existing SA div/rem panic codes; this batch models concrete primitive result/control-flow semantics, not Rust tuple ABI, `i128`, panic message/object identity, or trait-level dispatch.
- Test file `std_num_signed_overflowing_div_rem_macro_surface.sa` (panic ID 10658).

Focused validation only:
- `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_num_signed_overflowing_div_rem_macro_surface.sa --jobs 1 --trace-panic` -> `1 passed; 0 failed; 0 skipped`.

Panic IDs next free: 10659+.
Still blocked without redesign: generic primitive/container trait impl dispatch, cross-width integer conversions, generic `NonZero<T>`, generic `Wrapping<T>` / `Saturating<T>`, `u128` / `i128` public primitive support, missing concrete wrapper widths, Rust feature-gate modeling, Rust niche optimization, Rust unsafe UB enforcement, Rust panic message/object behavior, parser/formatter trait integration, allocator/drop/borrow semantics, randomized `RandomState`, SipHash compatibility, Rust iterator trait hierarchy, generic `Option` / `Result` / `ControlFlow`, generic `FromIterator`, `IntoIterator`, true format!, Condvar/Barrier, process env maps/Stdio objects, and thread stack/name builder ABI.


## Active std parity batch (2026-07-16 signed primitive overflowing abs/pow)

Completed supportable signed primitive overflowing abs/pow helpers:
- `NUM_I{8,16,32,64,SIZE}_OVERFLOWING_ABS` exposes Rust's signed primitive overflowing absolute-value shape for every existing SA signed width.
- `NUM_I{8,16,32,64,SIZE}_OVERFLOWING_POW` exposes Rust's signed primitive overflowing exponentiation shape for the same widths.
- Abs helpers return the signed wrapping absolute value plus a bool-style overflow flag for `MIN`; pow helpers return signed wrapping exponentiation plus an overflow flag derived from checked pow.
- This batch models concrete primitive result semantics, not signed overflowing div/rem, Rust tuple ABI, `i128`, or trait-level dispatch.
- Test file `std_num_signed_overflowing_abs_pow_macro_surface.sa` (panic ID 10657).

Focused validation only:
- `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_num_signed_overflowing_abs_pow_macro_surface.sa --jobs 1 --trace-panic` -> `1 passed; 0 failed; 0 skipped`.

Panic IDs next free: 10658+.
Still blocked without redesign: generic primitive/container trait impl dispatch, cross-width integer conversions, generic `NonZero<T>`, generic `Wrapping<T>` / `Saturating<T>`, `u128` / `i128` public primitive support, missing concrete wrapper widths, Rust feature-gate modeling, Rust niche optimization, Rust unsafe UB enforcement, Rust panic message/object behavior, parser/formatter trait integration, allocator/drop/borrow semantics, randomized `RandomState`, SipHash compatibility, Rust iterator trait hierarchy, generic `Option` / `Result` / `ControlFlow`, generic `FromIterator`, `IntoIterator`, true format!, Condvar/Barrier, process env maps/Stdio objects, and thread stack/name builder ABI.


## Active std parity batch (2026-07-16 signed primitive overflowing neg/shift)

Completed supportable signed primitive overflowing neg/shift helpers:
- `NUM_I{8,16,32,64,SIZE}_OVERFLOWING_NEG` exposes Rust's signed primitive overflowing negation shape for every existing SA signed width.
- `NUM_I{8,16,32,64,SIZE}_OVERFLOWING_SHL` and `NUM_I{8,16,32,64,SIZE}_OVERFLOWING_SHR` expose Rust's signed primitive overflowing shift shape for the same widths.
- Neg helpers return the signed wrapping negation plus a bool-style overflow flag for `MIN`; shift helpers return the signed wrapping shift result plus `shift >= BITS` as the overflow flag.
- This batch models concrete primitive result semantics, not signed overflowing div/rem/abs/pow, Rust tuple ABI, `i128`, or trait-level dispatch.
- Test file `std_num_signed_overflowing_neg_shift_macro_surface.sa` (panic ID 10656).

Focused validation only:
- `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_num_signed_overflowing_neg_shift_macro_surface.sa --jobs 1 --trace-panic` -> `1 passed; 0 failed; 0 skipped`.

Panic IDs next free: 10657+.
Still blocked without redesign: generic primitive/container trait impl dispatch, cross-width integer conversions, generic `NonZero<T>`, generic `Wrapping<T>` / `Saturating<T>`, `u128` / `i128` public primitive support, missing concrete wrapper widths, Rust feature-gate modeling, Rust niche optimization, Rust unsafe UB enforcement, Rust panic message/object behavior, parser/formatter trait integration, allocator/drop/borrow semantics, randomized `RandomState`, SipHash compatibility, Rust iterator trait hierarchy, generic `Option` / `Result` / `ControlFlow`, generic `FromIterator`, `IntoIterator`, true format!, Condvar/Barrier, process env maps/Stdio objects, and thread stack/name builder ABI.


## Active std parity batch (2026-07-16 signed wide primitive overflowing add/sub/mul)

Completed supportable signed wide primitive overflowing helpers:
- `NUM_I64_OVERFLOWING_{ADD,SUB,MUL}` exposes Rust's signed primitive overflowing add/sub/mul shape for the 64-bit signed width.
- `NUM_ISIZE_OVERFLOWING_{ADD,SUB,MUL}` exposes the same shape through the current 64-bit SA `isize` ABI.
- Together with existing `NUM_I{8,16,32}_OVERFLOWING_{ADD,SUB,MUL}`, this completes current signed-width coverage for these three overflowing methods.
- Helpers return the signed wrapping result plus a bool-style overflow flag by pairing existing checked and wrapping paths. This batch models concrete primitive result semantics, not signed overflowing div/rem/shift/neg/abs/pow, Rust tuple ABI, `i128`, or trait-level dispatch.
- Test file `std_num_signed_wide_overflowing_macro_surface.sa` (panic ID 10655).

Focused validation only:
- `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_num_signed_wide_overflowing_macro_surface.sa --jobs 1 --trace-panic` -> `1 passed; 0 failed; 0 skipped`.

Panic IDs next free: 10656+.
Still blocked without redesign: generic primitive/container trait impl dispatch, cross-width integer conversions, generic `NonZero<T>`, generic `Wrapping<T>` / `Saturating<T>`, `u128` / `i128` public primitive support, missing concrete wrapper widths, Rust feature-gate modeling, Rust niche optimization, Rust unsafe UB enforcement, Rust panic message/object behavior, parser/formatter trait integration, allocator/drop/borrow semantics, randomized `RandomState`, SipHash compatibility, Rust iterator trait hierarchy, generic `Option` / `Result` / `ControlFlow`, generic `FromIterator`, `IntoIterator`, true format!, Condvar/Barrier, process env maps/Stdio objects, and thread stack/name builder ABI.


## Active std parity batch (2026-07-16 unsigned primitive overflowing pow)

Completed supportable unsigned primitive overflowing pow helpers:
- `NUM_U{8,16,32,64,SIZE}_OVERFLOWING_POW` exposes Rust's unsigned primitive `overflowing_pow` shape for every existing SA unsigned width.
- Helpers return the declared-width wrapping exponentiation result plus a bool-style overflow flag. The value reuses existing `POW` helpers; the overflow flag is derived from existing `CHECKED_POW` helpers.
- Covered Rust's documented `3^5`, `0^0`, and `3u8^6` cases, plus `2^BITS` width-boundary wrapping for u8/u16/u32/u64/usize.
- This batch models concrete primitive result semantics, not Rust tuple ABI, public `u128` / `i128` primitive support, generic trait dispatch, compiler intrinsic/static-known optimization branches, or feature-gate plumbing.
- Test file `std_num_overflowing_pow_macro_surface.sa` (panic ID 10654).

Focused validation only:
- `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_num_overflowing_pow_macro_surface.sa --jobs 1 --trace-panic` -> `1 passed; 0 failed; 0 skipped`.

Panic IDs next free: 10655+.
Still blocked without redesign: generic primitive/container trait impl dispatch, cross-width integer conversions, generic `NonZero<T>`, generic `Wrapping<T>` / `Saturating<T>`, `u128` / `i128` public primitive support, missing concrete wrapper widths, Rust feature-gate modeling, Rust niche optimization, Rust unsafe UB enforcement, Rust panic message/object behavior, parser/formatter trait integration, allocator/drop/borrow semantics, randomized `RandomState`, SipHash compatibility, Rust iterator trait hierarchy, generic `Option` / `Result` / `ControlFlow`, generic `FromIterator`, `IntoIterator`, true format!, Condvar/Barrier, process env maps/Stdio objects, and thread stack/name builder ABI.


## Active std parity batch (2026-07-16 unsigned primitive overflowing div/rem/euclid/neg)

Completed supportable unsigned primitive overflowing div/rem/euclid/neg helpers:
- `NUM_U{8,16,32,64,SIZE}_OVERFLOWING_DIV` and `OVERFLOWING_DIV_EUCLID` expose Rust's unsigned quotient-plus-overflow-flag shape for every existing SA unsigned width.
- `NUM_U{8,16,32,64,SIZE}_OVERFLOWING_REM` and `OVERFLOWING_REM_EUCLID` expose the matching remainder-plus-overflow-flag shape.
- `NUM_U{8,16,32,64,SIZE}_OVERFLOWING_NEG` exposes Rust's unsigned wrapping negation result and nonzero overflow flag.
- Nonzero div/rem helpers always return overflow flag `0`; divide-by-zero is left to the underlying operation rather than modeling Rust panic objects/messages. This batch does not cover `overflowing_pow`, Rust tuple ABI, `u128`, or trait-level dispatch.
- Test file `std_num_unsigned_overflowing_div_neg_macro_surface.sa` (panic ID 10653).

Focused validation only:
- `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_num_unsigned_overflowing_div_neg_macro_surface.sa --jobs 1 --trace-panic` -> `1 passed; 0 failed; 0 skipped`.

Panic IDs next free: 10654+.
Still blocked without redesign: generic primitive/container trait impl dispatch, cross-width integer conversions, generic `NonZero<T>`, generic `Wrapping<T>` / `Saturating<T>`, `u128` / `i128` public primitive support, missing concrete wrapper widths, Rust feature-gate modeling, Rust niche optimization, Rust unsafe UB enforcement, Rust panic message/object behavior, parser/formatter trait integration, allocator/drop/borrow semantics, randomized `RandomState`, SipHash compatibility, Rust iterator trait hierarchy, generic `Option` / `Result` / `ControlFlow`, generic `FromIterator`, `IntoIterator`, true format!, Condvar/Barrier, process env maps/Stdio objects, and thread stack/name builder ABI.


## Active std parity batch (2026-07-16 narrow unsigned primitive overflowing)

Completed supportable narrow unsigned primitive overflowing helpers:
- `NUM_U{8,16,32}_OVERFLOWING_{ADD,SUB,MUL}` exposes Rust's wrapping-result plus overflow-flag shape for narrow unsigned arithmetic.
- `NUM_U{8,16,32}_OVERFLOWING_{SHL,SHR}` exposes Rust's wrapping shift plus oversized-shift flag shape for narrow unsigned shifts.
- Together with existing `NUM_U64_OVERFLOWING_{ADD,SUB,MUL,SHL,SHR}` and matching `NUM_USIZE_*` aliases, this completes current unsigned-width coverage for these five overflowing methods.
- This batch models Rust's result semantics for concrete primitive widths, not overflowing div/rem/pow, Rust tuple ABI, `u128`, or trait-level dispatch.
- Test file `std_num_narrow_overflowing_macro_surface.sa` (panic ID 10652).

Focused validation only:
- `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_num_narrow_overflowing_macro_surface.sa --jobs 1 --trace-panic` -> `1 passed; 0 failed; 0 skipped`.

Panic IDs next free: 10653+.
Still blocked without redesign: generic primitive/container trait impl dispatch, cross-width integer conversions, generic `NonZero<T>`, generic `Wrapping<T>` / `Saturating<T>`, `u128` / `i128` public primitive support, missing concrete wrapper widths, Rust feature-gate modeling, Rust niche optimization, Rust unsafe UB enforcement, Rust panic message/object behavior, parser/formatter trait integration, allocator/drop/borrow semantics, randomized `RandomState`, SipHash compatibility, Rust iterator trait hierarchy, generic `Option` / `Result` / `ControlFlow`, generic `FromIterator`, `IntoIterator`, true format!, Condvar/Barrier, process env maps/Stdio objects, and thread stack/name builder ABI.


## Active std parity batch (2026-07-16 narrow unsigned primitive carrying add/borrowing sub)

Completed supportable narrow unsigned primitive carrying add/borrowing sub helpers:
- `NUM_U{8,16,32}_CARRYING_ADD` exposes Rust's `carrying_add` method shape for the narrow unsigned widths that were previously missing it.
- `NUM_U{8,16,32}_BORROWING_SUB` exposes Rust's `borrowing_sub` method shape for the same widths.
- Together with existing `NUM_U64_CARRYING_ADD` / `BORROWING_SUB` and `NUM_USIZE_CARRYING_ADD` / `BORROWING_SUB`, this completes the current unsigned-width coverage for these two bigint helpers.
- Helpers return the declared-width wrapped result and a bool-style carry/borrow flag. This batch models Rust's `unsigned_bigint_helpers` result semantics, not Rust tuple ABI, `const_unsigned_bigint_helpers` feature-gate plumbing, compiler intrinsic lowering, or trait-level dispatch.
- Test file `std_num_narrow_carry_borrow_macro_surface.sa` (panic ID 10651).

Focused validation only:
- `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_num_narrow_carry_borrow_macro_surface.sa --jobs 1 --trace-panic` -> `1 passed; 0 failed; 0 skipped`.

Panic IDs next free: 10652+.
Still blocked without redesign: generic primitive/container trait impl dispatch, cross-width integer conversions, generic `NonZero<T>`, generic `Wrapping<T>` / `Saturating<T>`, `u128` / `i128` public primitive support, missing concrete wrapper widths, Rust feature-gate modeling, Rust niche optimization, Rust unsafe UB enforcement, Rust panic message/object behavior, parser/formatter trait integration, allocator/drop/borrow semantics, randomized `RandomState`, SipHash compatibility, Rust iterator trait hierarchy, generic `Option` / `Result` / `ControlFlow`, generic `FromIterator`, `IntoIterator`, true format!, Condvar/Barrier, process env maps/Stdio objects, and thread stack/name builder ABI.


## Active std parity batch (2026-07-16 unsigned primitive carrying multiplication)

Completed supportable unsigned primitive carrying multiplication helpers:
- `NUM_U{8,16,32,64,SIZE}_CARRYING_MUL` exposes Rust's `carrying_mul` method for every existing SA unsigned width.
- `NUM_U{8,16,32,64,SIZE}_CARRYING_MUL_ADD` exposes Rust's `carrying_mul_add` method for the same widths.
- Helpers return low-order and high-order declared-width limbs for the full 2N-bit result of `lhs * rhs + carry (+ addend)`. Operands and outputs are masked to the declared width, and `usize` aliases the current 64-bit SA ABI.
- The shared implementation uses two-limb long multiplication and carry propagation, including full `u64` edge cases, without claiming a public `u128` scalar, Rust tuple ABI, `const_unsigned_bigint_helpers` feature-gate plumbing, compiler intrinsic lowering, or trait-level dispatch.
- Test file `std_num_carrying_mul_macro_surface.sa` (panic ID 10650).

Focused validation only:
- `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_num_carrying_mul_macro_surface.sa --jobs 1 --trace-panic` -> `1 passed; 0 failed; 0 skipped`.

Panic IDs next free: 10651+.
Still blocked without redesign: generic primitive/container trait impl dispatch, cross-width integer conversions, generic `NonZero<T>`, generic `Wrapping<T>` / `Saturating<T>`, `u128` / `i128` public primitive support, missing concrete wrapper widths, Rust feature-gate modeling, Rust niche optimization, Rust unsafe UB enforcement, Rust panic message/object behavior, parser/formatter trait integration, allocator/drop/borrow semantics, randomized `RandomState`, SipHash compatibility, Rust iterator trait hierarchy, generic `Option` / `Result` / `ControlFlow`, generic `FromIterator`, `IntoIterator`, true format!, Condvar/Barrier, process env maps/Stdio objects, and thread stack/name builder ABI.


## Active std parity batch (2026-07-16 unsigned primitive unchecked disjoint bit-or)

Completed supportable unsigned primitive unchecked disjoint bit-or helpers:
- `NUM_U{8,16,32,64,SIZE}_UNCHECKED_DISJOINT_BITOR` exposes Rust's `unchecked_disjoint_bitor` caller-precondition shape for every existing SA unsigned width.
- Helpers mask operands to the declared width and return bitwise OR. Callers must guarantee `(lhs & rhs) == 0`; under that precondition the result is also equal to declared-width addition.
- `usize` aliases the current 64-bit SA ABI. This batch models Rust's unstable `disjoint_bitor` result semantics for valid inputs, not immediate-UB enforcement, overlap validation, feature-gate plumbing, compiler intrinsic selection, `u128`, or trait-level dispatch.
- Test file `std_num_unchecked_disjoint_bitor_macro_surface.sa` (panic ID 10649).

Focused validation only:
- `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_num_unchecked_disjoint_bitor_macro_surface.sa --jobs 1 --trace-panic` -> `1 passed; 0 failed; 0 skipped`.

Panic IDs next free: 10650+.
Still blocked without redesign: generic primitive/container trait impl dispatch, cross-width integer conversions, generic `NonZero<T>`, generic `Wrapping<T>` / `Saturating<T>`, `u128` / `i128`, missing concrete wrapper widths, Rust feature-gate modeling, Rust niche optimization, Rust unsafe UB enforcement, Rust panic message/object behavior, parser/formatter trait integration, allocator/drop/borrow semantics, randomized `RandomState`, SipHash compatibility, Rust iterator trait hierarchy, generic `Option` / `Result` / `ControlFlow`, generic `FromIterator`, `IntoIterator`, true format!, Condvar/Barrier, process env maps/Stdio objects, and thread stack/name builder ABI.


## Active std parity batch (2026-07-16 unsigned primitive gather/scatter bits)

Completed supportable unsigned primitive gather/scatter bit helpers:
- `NUM_U{8,16,32,64,SIZE}_EXTRACT_BITS` exposes Rust's `extract_bits` method for every existing SA unsigned width, packing source bits selected by the mask into contiguous low result bits.
- `NUM_U{8,16,32,64,SIZE}_DEPOSIT_BITS` exposes Rust's `deposit_bits` method for the same widths, distributing successive source low bits into successive set-bit positions in the mask.
- Inputs, masks, and results are constrained to the declared width; excess source bits beyond the mask population count are ignored and `usize` aliases the current 64-bit SA ABI. This batch models Rust's unstable `uint_gather_scatter_bits` semantics, not feature-gate plumbing, hardware/compiler `pext` / `pdep` selection, `u128`, or trait-level dispatch.
- Test file `std_num_gather_scatter_bits_macro_surface.sa` (panic ID 10648).

Focused validation only:
- `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_num_gather_scatter_bits_macro_surface.sa --jobs 1 --trace-panic` -> `1 passed; 0 failed; 0 skipped`.

Panic IDs next free: 10649+.
Still blocked without redesign: generic primitive/container trait impl dispatch, cross-width integer conversions, generic `NonZero<T>`, generic `Wrapping<T>` / `Saturating<T>`, `u128` / `i128`, missing concrete wrapper widths, Rust feature-gate modeling, Rust niche optimization, Rust panic message/object behavior, parser/formatter trait integration, allocator/drop/borrow semantics, randomized `RandomState`, SipHash compatibility, Rust iterator trait hierarchy, generic `Option` / `Result` / `ControlFlow`, generic `FromIterator`, `IntoIterator`, true format!, Condvar/Barrier, process env maps/Stdio objects, and thread stack/name builder ABI.


## Active std parity batch (2026-07-16 unsigned primitive carryless multiplication)

Completed supportable unsigned primitive carryless multiplication helpers:
- `NUM_U{8,16,32,64,SIZE}_CARRYLESS_MUL` exposes Rust's `carryless_mul` method for every existing SA unsigned width.
- The shared implementation performs binary polynomial multiplication over GF(2), using XOR instead of addition and returning the declared-width low half.
- Inputs, each shifted LHS term, and the final result are masked to the declared width; `usize` aliases the current 64-bit SA ABI. This batch models Rust's unstable `uint_carryless_mul` behavior, not feature-gate plumbing, compiler intrinsic selection, `u128`, or trait-level dispatch.
- Test file `std_num_carryless_mul_macro_surface.sa` (panic ID 10647).

Focused validation only:
- `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_num_carryless_mul_macro_surface.sa --jobs 1 --trace-panic` -> `1 passed; 0 failed; 0 skipped`.

Panic IDs next free: 10648+.
Still blocked without redesign: generic primitive/container trait impl dispatch, cross-width integer conversions, generic `NonZero<T>`, generic `Wrapping<T>` / `Saturating<T>`, `u128` / `i128`, missing concrete wrapper widths, Rust feature-gate modeling, Rust niche optimization, Rust panic message/object behavior, parser/formatter trait integration, allocator/drop/borrow semantics, randomized `RandomState`, SipHash compatibility, Rust iterator trait hierarchy, generic `Option` / `Result` / `ControlFlow`, generic `FromIterator`, `IntoIterator`, true format!, Condvar/Barrier, process env maps/Stdio objects, and thread stack/name builder ABI.


## Active std parity batch (2026-07-16 unsigned primitive funnel shifts)

Completed supportable unsigned primitive funnel shift helpers:
- `NUM_U{8,16,32,64,SIZE}_FUNNEL_SHL` / `FUNNEL_SHR` expose Rust's safe funnel shift methods for every existing SA unsigned width.
- Matching `UNCHECKED_FUNNEL_SHL` / `UNCHECKED_FUNNEL_SHR` helpers expose the caller-precondition lowering shape without runtime validation.
- Left funnel shift combines `lhs << shift` with the high bits of `rhs`; right funnel shift combines `rhs >> shift` with the low bits shifted in from `lhs`. Zero shifts return `lhs` for left and `rhs` for right without evaluating a complementary full-width shift.
- Safe out-of-range shifts reuse SA `panic(2212)` / `panic(2213)`. Narrow results are masked and `usize` aliases the current 64-bit SA ABI. This batch models Rust's unstable `funnel_shifts` behavior, not unsafe UB enforcement, feature-gate plumbing, intrinsic lowering, `u128`, or trait-level dispatch.
- Test file `std_num_funnel_shift_macro_surface.sa` (panic ID 10646 for the ordinary assertion path).

Focused validation only:
- `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_num_funnel_shift_macro_surface.sa --jobs 1 --trace-panic` -> `3 passed; 0 failed; 0 skipped`.

Panic IDs next free: 10647+.
Still blocked without redesign: generic primitive/container trait impl dispatch, cross-width integer conversions, generic `NonZero<T>`, generic `Wrapping<T>` / `Saturating<T>`, `u128` / `i128`, missing concrete wrapper widths, Rust feature-gate modeling, Rust niche optimization, Rust panic message/object behavior, parser/formatter trait integration, allocator/drop/borrow semantics, randomized `RandomState`, SipHash compatibility, Rust iterator trait hierarchy, generic `Option` / `Result` / `ControlFlow`, generic `FromIterator`, `IntoIterator`, true format!, Condvar/Barrier, process env maps/Stdio objects, and thread stack/name builder ABI.


## Active std parity batch (2026-07-16 primitive floor division)

Completed supportable primitive floor division helpers:
- `NUM_U{8,16,32,64,SIZE}_DIV_FLOOR` exposes Rust's unsigned `div_floor` shape as ordinary division for every existing SA unsigned width.
- `NUM_I{8,16,32,64,SIZE}_DIV_FLOOR` computes the truncating quotient and remainder, then subtracts one when the remainder is nonzero and the operand signs differ, producing a quotient rounded toward negative infinity.
- Zero divisors and signed `MIN / -1` trap through existing SA `panic(2208)`. `usize` / `isize` alias the current 64-bit SA ABI. This batch models Rust's unstable `int_roundings` behavior, not panic message/object identity, feature-gate plumbing, `u128` / `i128`, or trait-level dispatch.
- Test file `std_num_div_floor_macro_surface.sa` (panic ID 10645 for the ordinary assertion path).

Focused validation only:
- `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_num_div_floor_macro_surface.sa --jobs 1 --trace-panic` -> `3 passed; 0 failed; 0 skipped`.

Panic IDs next free: 10646+.
Still blocked without redesign: generic primitive/container trait impl dispatch, cross-width integer conversions, generic `NonZero<T>`, generic `Wrapping<T>` / `Saturating<T>`, `u128` / `i128`, missing concrete wrapper widths, Rust feature-gate modeling, Rust niche optimization, Rust panic message/object behavior, parser/formatter trait integration, allocator/drop/borrow semantics, randomized `RandomState`, SipHash compatibility, Rust iterator trait hierarchy, generic `Option` / `Result` / `ControlFlow`, generic `FromIterator`, `IntoIterator`, true format!, Condvar/Barrier, process env maps/Stdio objects, and thread stack/name builder ABI.


## Active std parity batch (2026-07-16 primitive exact division)

Completed supportable primitive exact division helpers:
- `NUM_U{8,16,32,64,SIZE}_CHECKED_DIV_EXACT` and matching signed helpers expose explicit `ok/out` lowering for Rust's unstable `checked_div_exact`, returning failure for zero divisors, signed `MIN / -1`, or nonzero remainders.
- `NUM_U{8,16,32,64,SIZE}_DIV_EXACT` and matching signed helpers expose Rust `div_exact`'s mixed behavior: nonexact division returns `ok=0/out=0`, while zero divisors and signed overflow trap through existing SA `panic(2208)`.
- Matching `UNCHECKED_DIV_EXACT` helpers perform only declared-width division and rely on callers to uphold the positive-divisor, exact-divisibility, and no-overflow safety preconditions.
- Narrow unsigned outputs remain masked and narrow signed outputs remain sign-extended. `usize` / `isize` alias the current 64-bit SA ABI. This batch models behavior, not Rust `Option` object layout, unsafe UB enforcement, `exact_div` feature-gate plumbing, `u128` / `i128`, or trait-level dispatch.
- Test file `std_num_exact_division_macro_surface.sa` (panic IDs 10643 and 10644 for ordinary assertion paths).

Focused validation only:
- `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_num_exact_division_macro_surface.sa --jobs 1 --trace-panic` -> `4 passed; 0 failed; 0 skipped`.

Panic IDs next free: 10645+.
Still blocked without redesign: generic primitive/container trait impl dispatch, cross-width integer conversions, generic `NonZero<T>`, generic `Wrapping<T>` / `Saturating<T>`, `u128` / `i128`, missing concrete wrapper widths, Rust feature-gate modeling, Rust niche optimization, Rust panic message/object behavior, parser/formatter trait integration, allocator/drop/borrow semantics, randomized `RandomState`, SipHash compatibility, Rust iterator trait hierarchy, generic `Option` / `Result` / `ControlFlow`, generic `FromIterator`, `IntoIterator`, true format!, Condvar/Barrier, process env maps/Stdio objects, and thread stack/name builder ABI.


## Active std parity batch (2026-07-16 primitive exact shifts)

Completed supportable primitive exact shift helpers:
- `NUM_U{8,16,32,64,SIZE}_SHL_EXACT` / `SHR_EXACT` and matching signed helpers expose explicit `ok/out` lowering for Rust's unstable `shl_exact` / `shr_exact` methods.
- A shift succeeds only when its amount is below the declared bit width and reversing the result recovers the original declared-width value. Failure returns `ok=0/out=0`.
- `NUM_U{8,16,32,64,SIZE}_UNCHECKED_SHL_EXACT` / `UNCHECKED_SHR_EXACT` and matching signed helpers expose the corresponding caller-precondition lowering without runtime validation.
- Narrow unsigned helpers mask results; narrow signed helpers sign-extend results. `usize` / `isize` alias the current 64-bit SA ABI. This batch models behavior, not Rust `Option` object layout, unsafe UB enforcement, `exact_bitshifts` feature-gate plumbing, `u128` / `i128`, or trait-level dispatch.
- Test file `std_num_exact_shift_macro_surface.sa` (panic IDs 10641 and 10642).

Focused validation only:
- `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_num_exact_shift_macro_surface.sa --jobs 1 --trace-panic` -> `2 passed; 0 failed; 0 skipped`.

Panic IDs next free: 10643+.
Still blocked without redesign: generic primitive/container trait impl dispatch, cross-width integer conversions, generic `NonZero<T>`, generic `Wrapping<T>` / `Saturating<T>`, `u128` / `i128`, missing concrete wrapper widths, Rust feature-gate modeling, Rust niche optimization, Rust panic message/object behavior, parser/formatter trait integration, allocator/drop/borrow semantics, randomized `RandomState`, SipHash compatibility, Rust iterator trait hierarchy, generic `Option` / `Result` / `ControlFlow`, generic `FromIterator`, `IntoIterator`, true format!, Condvar/Barrier, process env maps/Stdio objects, and thread stack/name builder ABI.


## Active std parity batch (2026-07-16 primitive unbounded shifts)

Completed supportable primitive unbounded shift helpers:
- `NUM_U{8,16,32,64,SIZE}_UNBOUNDED_SHL` / `UNBOUNDED_SHR`: concrete Rust unsigned primitive unbounded shift shapes for the existing SA unsigned widths.
- `NUM_I{8,16,32,64,SIZE}_UNBOUNDED_SHL` / `UNBOUNDED_SHR`: matching signed primitive helpers.
- In-range operations preserve each declared width. Oversized left shifts and unsigned right shifts return zero; oversized signed right shifts return the sign fill value, matching Rust's effective `BITS - 1` arithmetic shift behavior.
- The helpers branch before executing an oversized shift and add no runtime panic codes. `usize` / `isize` alias the current 64-bit SA ABI. This batch does not model `u128` / `i128`, feature-gate plumbing, or trait-level dispatch.
- Test file `std_num_unbounded_shift_macro_surface.sa` (panic ID 10640).

Focused validation only:
- `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_num_unbounded_shift_macro_surface.sa --jobs 1 --trace-panic` -> `1 passed; 0 failed; 0 skipped`.

Panic IDs next free: 10641+.
Still blocked without redesign: generic primitive/container trait impl dispatch, cross-width integer conversions, generic `NonZero<T>`, generic `Wrapping<T>` / `Saturating<T>`, `u128` / `i128`, missing concrete wrapper widths, Rust feature-gate modeling, Rust niche optimization, Rust panic message/object behavior, parser/formatter trait integration, allocator/drop/borrow semantics, randomized `RandomState`, SipHash compatibility, Rust iterator trait hierarchy, generic `Option` / `Result` / `ControlFlow`, generic `FromIterator`, `IntoIterator`, true format!, Condvar/Barrier, process env maps/Stdio objects, and thread stack/name builder ABI.


## Active std parity batch (2026-07-16 primitive unsigned checked_signed_diff)

Completed supportable primitive unsigned checked signed-difference helpers:
- `NUM_U{8,16,32,64,SIZE}_CHECKED_SIGNED_DIFF`: concrete Rust unsigned primitive `checked_signed_diff` shape for the existing SA unsigned widths.
- Helpers expose explicit `ok/out` results instead of Rust `Option<SignedT>`. Positive differences are accepted only through the matching signed max, and negative differences are accepted through the matching signed min.
- `usize` aliases the current 64-bit SA ABI. This batch models Rust's checked result shape, not Rust `Option` object layout, `u128` / `i128`, feature-gate plumbing, or trait-level dispatch.
- Test file `std_num_checked_signed_diff_macro_surface.sa` (panic ID 10639).

Focused validation only:
- `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_num_checked_signed_diff_macro_surface.sa --jobs 1 --trace-panic` -> `1 passed; 0 failed; 0 skipped`.

Panic IDs next free: 10640+.
Still blocked without redesign: generic primitive/container trait impl dispatch, cross-width integer conversions, generic `NonZero<T>`, generic `Wrapping<T>` / `Saturating<T>`, `u128` / `i128`, missing concrete wrapper widths, Rust feature-gate modeling, Rust niche optimization, Rust panic message/object behavior, parser/formatter trait integration, allocator/drop/borrow semantics, randomized `RandomState`, SipHash compatibility, Rust iterator trait hierarchy, generic `Option` / `Result` / `ControlFlow`, generic `FromIterator`, `IntoIterator`, true format!, Condvar/Barrier, process env maps/Stdio objects, and thread stack/name builder ABI.


## Active std parity batch (2026-07-16 primitive mixed-sign checked/strict add/sub)

Completed supportable primitive mixed-sign checked and strict add/sub helpers:
- `NUM_U{8,16,32,64,SIZE}_CHECKED_ADD_SIGNED` / `STRICT_ADD_SIGNED`: concrete Rust unsigned primitive `*_add_signed` shape for the existing SA unsigned widths.
- `NUM_U{8,16,32,64,SIZE}_CHECKED_SUB_SIGNED` / `STRICT_SUB_SIGNED`: matching unsigned primitive `*_sub_signed` helpers.
- `NUM_I{8,16,32,64,SIZE}_CHECKED_ADD_UNSIGNED` / `STRICT_ADD_UNSIGNED`: concrete Rust signed primitive `*_add_unsigned` shape for the existing SA signed widths.
- `NUM_I{8,16,32,64,SIZE}_CHECKED_SUB_UNSIGNED` / `STRICT_SUB_UNSIGNED`: matching signed primitive `*_sub_unsigned` helpers.
- Checked helpers expose explicit `ok/out` results instead of Rust `Option<Self>`. Strict add-shaped failures reuse SA `panic(2205)` and strict sub-shaped failures reuse `panic(2206)`.
- `usize` / `isize` alias the current 64-bit SA ABI. This batch models Rust's checked result and strict panic control flow, not panic message/object identity, `u128` / `i128`, or trait-level dispatch.
- Test file `std_num_mixed_sign_add_sub_macro_surface.sa` (panic ID 10638 for the ordinary assertion path).

Focused validation only:
- `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_num_mixed_sign_add_sub_macro_surface.sa --jobs 1 --trace-panic` -> `7 passed; 0 failed; 0 skipped`.

Panic IDs next free: 10639+.
Still blocked without redesign: generic primitive/container trait impl dispatch, cross-width integer conversions, generic `NonZero<T>`, generic `Wrapping<T>` / `Saturating<T>`, `u128` / `i128`, missing concrete wrapper widths, Rust feature-gate modeling, Rust niche optimization, Rust panic message/object behavior, parser/formatter trait integration, allocator/drop/borrow semantics, randomized `RandomState`, SipHash compatibility, Rust iterator trait hierarchy, generic `Option` / `Result` / `ControlFlow`, generic `FromIterator`, `IntoIterator`, true format!, Condvar/Barrier, process env maps/Stdio objects, and thread stack/name builder ABI.


## Active std parity batch (2026-07-16 primitive checked/strict neg/abs)

Completed supportable primitive checked/strict negation and absolute-value helpers:
- `NUM_U{8,16,32,64,SIZE}_CHECKED_NEG`: concrete Rust unsigned primitive `checked_neg` shape for the existing SA unsigned widths, returning explicit `ok/out` values and succeeding only for zero.
- `NUM_U{8,16,32,64,SIZE}_STRICT_NEG`: concrete Rust unsigned primitive strict negation control-flow shape over checked negation.
- `NUM_I{8,16,32,64,SIZE}_STRICT_NEG` and `*_STRICT_ABS`: matching signed primitive strict negation and strict absolute value helpers over the existing checked helpers.
- Strict negation traps with SA `panic(2214)` on unsigned nonzero values or signed `MIN`; strict absolute value traps with `panic(2215)` on signed `MIN`.
- `usize` / `isize` alias the current 64-bit SA ABI. This batch models Rust's checked result and strict panic control flow, not panic message/object identity, `u128` / `i128`, unchecked neg, or trait-level dispatch.
- Test file `std_num_checked_strict_neg_abs_macro_surface.sa` (panic ID 10637 for the ordinary assertion path).

Focused validation only:
- `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_num_checked_strict_neg_abs_macro_surface.sa --jobs 1 --trace-panic` -> `4 passed; 0 failed; 0 skipped`.

Panic IDs next free: 10638+.
Still blocked without redesign: generic primitive/container trait impl dispatch, cross-width integer conversions, generic `NonZero<T>`, generic `Wrapping<T>` / `Saturating<T>`, `u128` / `i128`, missing concrete wrapper widths, Rust feature-gate modeling, Rust niche optimization, Rust panic message/object behavior, parser/formatter trait integration, allocator/drop/borrow semantics, randomized `RandomState`, SipHash compatibility, Rust iterator trait hierarchy, generic `Option` / `Result` / `ControlFlow`, generic `FromIterator`, `IntoIterator`, true format!, Condvar/Barrier, process env maps/Stdio objects, and thread stack/name builder ABI.


## Active std parity batch (2026-07-16 primitive strict shift)

Completed supportable primitive strict shift helpers:
- `NUM_U{8,16,32,64,SIZE}_STRICT_SHL` and `*_STRICT_SHR`: concrete Rust unsigned primitive strict shift operation shape for the existing SA widths.
- `NUM_I{8,16,32,64,SIZE}_STRICT_SHL` and `*_STRICT_SHR`: matching signed primitive strict shift helpers.
- Each helper reuses its declared-width checked shift operation and returns the computed value on success. Left-shift failure traps with SA `panic(2212)`, and right-shift failure traps with `panic(2213)` when the shift amount is greater than or equal to the declared bit width.
- `usize` / `isize` alias the current 64-bit SA ABI. This batch models Rust's strict shift panic control flow, not panic message/object identity, `u128` / `i128`, or trait-level dispatch.
- Test file `std_num_strict_shift_macro_surface.sa` (panic ID 10636 for the ordinary assertion path).

Focused validation only:
- `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_num_strict_shift_macro_surface.sa --jobs 1 --trace-panic` -> `5 passed; 0 failed; 0 skipped`.

Panic IDs next free: 10637+.
Still blocked without redesign: generic primitive/container trait impl dispatch, cross-width integer conversions, generic `NonZero<T>`, generic `Wrapping<T>` / `Saturating<T>`, `u128` / `i128`, missing concrete wrapper widths, Rust feature-gate modeling, Rust niche optimization, Rust panic message/object behavior, parser/formatter trait integration, allocator/drop/borrow semantics, randomized `RandomState`, SipHash compatibility, Rust iterator trait hierarchy, generic `Option` / `Result` / `ControlFlow`, generic `FromIterator`, `IntoIterator`, true format!, Condvar/Barrier, process env maps/Stdio objects, and thread stack/name builder ABI.


## Active std parity batch (2026-07-16 primitive checked/strict Euclidean div/rem)

Completed supportable primitive checked/strict Euclidean division/remainder helpers:
- `NUM_U{8,16,32,64,SIZE}_CHECKED_DIV_EUCLID` and `*_CHECKED_REM_EUCLID`: concrete Rust unsigned primitive checked Euclidean div/rem shape for the existing SA widths.
- `NUM_I{8,16,32,64,SIZE}_CHECKED_DIV_EUCLID` and `*_CHECKED_REM_EUCLID`: matching signed primitive checked Euclidean div/rem helpers.
- `NUM_U{8,16,32,64,SIZE}_STRICT_DIV_EUCLID`, `*_STRICT_REM_EUCLID`, and matching signed helpers: Rust primitive strict Euclidean control-flow shape over the checked helpers.
- Checked helpers expose explicit `ok/out` results instead of Rust `Option`. Unsigned helpers fail on zero divisors; signed helpers fail on zero divisors and signed `MIN / -1`. Strict Euclidean division traps with SA `panic(2210)`, and strict Euclidean remainder traps with `panic(2211)`.
- `usize` / `isize` alias the current 64-bit SA ABI. This batch models Rust's checked result and strict panic control flow, not panic message/object identity, `u128` / `i128`, or trait-level dispatch.
- Test file `std_num_checked_strict_euclid_macro_surface.sa` (panic ID 10635 for the ordinary assertion path).

Focused validation only:
- `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_num_checked_strict_euclid_macro_surface.sa --jobs 1 --trace-panic` -> `7 passed; 0 failed; 0 skipped`.

Panic IDs next free: 10636+.
Still blocked without redesign: generic primitive/container trait impl dispatch, cross-width integer conversions, generic `NonZero<T>`, generic `Wrapping<T>` / `Saturating<T>`, `u128` / `i128`, missing concrete wrapper widths, Rust feature-gate modeling, Rust niche optimization, Rust panic message/object behavior, parser/formatter trait integration, allocator/drop/borrow semantics, randomized `RandomState`, SipHash compatibility, Rust iterator trait hierarchy, generic `Option` / `Result` / `ControlFlow`, generic `FromIterator`, `IntoIterator`, true format!, Condvar/Barrier, process env maps/Stdio objects, and thread stack/name builder ABI.


## Active std parity batch (2026-07-16 primitive strict div/rem)

Completed supportable primitive strict division/remainder helpers:
- `NUM_U{8,16,32,64,SIZE}_STRICT_DIV` and `*_STRICT_REM`: concrete Rust unsigned primitive strict division/remainder operation shape for the existing SA widths.
- `NUM_I{8,16,32,64,SIZE}_STRICT_DIV` and `*_STRICT_REM`: matching signed primitive strict division/remainder helpers.
- Each helper reuses its declared-width checked division or remainder operation and returns the computed value on success. Division failure traps with SA `panic(2208)`, and remainder failure traps with `panic(2209)`.
- `usize` / `isize` alias the current 64-bit SA ABI. This batch models Rust's strict arithmetic panic control flow for division and remainder, not panic message/object identity, `u128` / `i128`, `strict_div_euclid` / `strict_rem_euclid`, or trait-level dispatch.
- Test file `std_num_strict_div_rem_macro_surface.sa` (panic ID 10634 for the ordinary assertion path).

Focused validation only:
- `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_num_strict_div_rem_macro_surface.sa --jobs 1 --trace-panic` -> `7 passed; 0 failed; 0 skipped`.

Panic IDs next free: 10635+.
Still blocked without redesign: generic primitive/container trait impl dispatch, cross-width integer conversions, generic `NonZero<T>`, generic `Wrapping<T>` / `Saturating<T>`, `u128` / `i128`, missing concrete wrapper widths, Rust feature-gate modeling, Rust niche optimization, Rust panic message/object behavior, parser/formatter trait integration, allocator/drop/borrow semantics, randomized `RandomState`, SipHash compatibility, Rust iterator trait hierarchy, generic `Option` / `Result` / `ControlFlow`, generic `FromIterator`, `IntoIterator`, true format!, Condvar/Barrier, process env maps/Stdio objects, and thread stack/name builder ABI.


## Active std parity batch (2026-07-15 primitive strict add/sub/mul)

Completed supportable primitive strict arithmetic helpers:
- `NUM_U{8,16,32,64,SIZE}_STRICT_ADD`, `*_STRICT_SUB`, and `*_STRICT_MUL`: concrete Rust unsigned primitive strict-overflow operation shape for the existing SA widths.
- `NUM_I{8,16,32,64,SIZE}_STRICT_ADD`, `*_STRICT_SUB`, and `*_STRICT_MUL`: matching signed primitive strict arithmetic helpers.
- Each helper reuses its declared-width checked operation and returns the computed value on success. Add overflow traps with SA `panic(2205)`, subtraction overflow/underflow with `panic(2206)`, and multiplication overflow with `panic(2207)`.
- `usize` / `isize` alias the current 64-bit SA ABI. This batch models Rust's strict-overflow panic control flow, not panic message/object identity, `u128` / `i128`, or trait-level dispatch.
- Test file `std_num_strict_arithmetic_macro_surface.sa` (panic ID 10633 for the ordinary assertion path).

Focused validation only:
- `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_num_strict_arithmetic_macro_surface.sa --jobs 1 --trace-panic` -> `7 passed; 0 failed; 0 skipped`.

Panic IDs next free: 10634+.
Still blocked without redesign: generic primitive/container trait impl dispatch, cross-width integer conversions, generic `NonZero<T>`, generic `Wrapping<T>` / `Saturating<T>`, `u128` / `i128`, missing concrete wrapper widths, Rust feature-gate modeling, Rust niche optimization, Rust panic message/object behavior, parser/formatter trait integration, allocator/drop/borrow semantics, randomized `RandomState`, SipHash compatibility, Rust iterator trait hierarchy, generic `Option` / `Result` / `ControlFlow`, generic `FromIterator`, `IntoIterator`, true format!, Condvar/Barrier, process env maps/Stdio objects, and thread stack/name builder ABI.


## Active std parity batch (2026-07-15 primitive checked/strict pow)

Completed supportable primitive checked and strict integer exponentiation helpers:
- `NUM_U8_CHECKED_POW`, `NUM_U16_CHECKED_POW`, `NUM_U32_CHECKED_POW`, `NUM_U64_CHECKED_POW`, and `NUM_USIZE_CHECKED_POW`: concrete Rust unsigned primitive `checked_pow` shape for the existing SA unsigned integer widths.
- `NUM_I8_CHECKED_POW`, `NUM_I16_CHECKED_POW`, `NUM_I32_CHECKED_POW`, `NUM_I64_CHECKED_POW`, and `NUM_ISIZE_CHECKED_POW`: matching signed primitive `checked_pow` shape for existing signed widths.
- `NUM_{U8,U16,U32,U64,USIZE,I8,I16,I32,I64,ISIZE}_STRICT_POW`: Rust primitive `strict_pow` control-flow shape over the checked helpers, trapping with SA `panic(2204)` on overflow.
- Checked helpers expose explicit `ok/out` results instead of Rust `Option`; arithmetic or declared-width overflow returns `ok=0/out=0`. `usize` / `isize` alias the current 64-bit SA ABI. This batch deliberately does not model Rust panic message/object identity, `u128` / `i128`, feature-gate enforcement, or trait-level dispatch.
- Test file `std_num_checked_strict_pow_macro_surface.sa` (panic ID 10632 for the ordinary assertion path).

Focused validation only:
- `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_num_checked_strict_pow_macro_surface.sa --jobs 1 --trace-panic` -> `3 passed; 0 failed; 0 skipped`.

Panic IDs next free: 10633+.
Still blocked without redesign: generic primitive/container trait impl dispatch, cross-width integer conversions, generic `NonZero<T>`, generic `Wrapping<T>` / `Saturating<T>`, `u128` / `i128`, missing concrete wrapper widths, Rust feature-gate modeling, Rust niche optimization, Rust panic message/object behavior, parser/formatter trait integration, allocator/drop/borrow semantics, randomized `RandomState`, SipHash compatibility, Rust iterator trait hierarchy, generic `Option` / `Result` / `ControlFlow`, generic `FromIterator`, `IntoIterator`, true format!, Condvar/Barrier, process env maps/Stdio objects, and thread stack/name builder ABI.


## Active std parity batch (2026-07-15 signed isqrt)

Completed supportable signed direct integer square-root helpers:
- `NUM_I8_ISQRT`, `NUM_I16_ISQRT`, `NUM_I32_ISQRT`, `NUM_I64_ISQRT`, and `NUM_ISIZE_ISQRT`: concrete Rust signed primitive `isqrt` shape for the existing SA signed integer widths.
- Nonnegative inputs delegate to the checked signed floor-root path and return the root directly; negative inputs trap with SA `panic(2203)`, modeling Rust's negative-argument panic control-flow.
- `isize` aliases the current 64-bit SA ABI. This batch deliberately does not model Rust panic message/object identity, `i128`, Rust feature-gate enforcement, or trait-level dispatch.
- Test file `std_num_signed_isqrt_macro_surface.sa` (panic ID 10631 for the ordinary assertion path).

Focused validation only:
- `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_num_signed_isqrt_macro_surface.sa --jobs 1 --trace-panic` -> `6 passed; 0 failed; 0 skipped`.

Panic IDs next free: 10632+.
Still blocked without redesign: generic primitive/container trait impl dispatch, cross-width integer conversions, generic `NonZero<T>`, generic `Wrapping<T>` / `Saturating<T>`, `u128` / `i128`, missing concrete wrapper widths, Rust feature-gate modeling, Rust niche optimization, Rust panic message/object behavior, parser/formatter trait integration, allocator/drop/borrow semantics, randomized `RandomState`, SipHash compatibility, Rust iterator trait hierarchy, generic `Option` / `Result` / `ControlFlow`, generic `FromIterator`, `IntoIterator`, true format!, Condvar/Barrier, process env maps/Stdio objects, and thread stack/name builder ABI.


## Active std parity batch (2026-07-15 primitive strict sign casts)

Completed supportable primitive strict same-width sign-cast helpers:
- `NUM_U{8,16,32,64,SIZE}_STRICT_CAST_SIGNED`: concrete Rust nightly `integer_cast_extras` shape for unsigned-to-signed strict conversion.
- `NUM_I{8,16,32,64,SIZE}_STRICT_CAST_UNSIGNED`: matching signed-to-unsigned strict conversion shape.
- Strict helpers reuse the checked conversion predicates and trap via SA panic codes for unrepresentable values: unsigned values above the same-width signed maximum panic with `2201`, and negative signed values panic with `2202`.
- `usize` / `isize` alias the current 64-bit SA ABI. This batch models Rust's panic control-flow shape, not Rust panic message/object identity, feature-gate enforcement, `u128` / `i128`, or trait-level dispatch.
- Test file `std_num_strict_sign_cast_macro_surface.sa` (panic ID 10630 for the ordinary assertion path).

Focused validation only:
- `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_num_strict_sign_cast_macro_surface.sa --jobs 1 --trace-panic` -> `3 passed; 0 failed; 0 skipped`.

Panic IDs next free: 10631+.
Still blocked without redesign: generic primitive/container trait impl dispatch, cross-width integer conversions, generic `NonZero<T>`, generic `Wrapping<T>` / `Saturating<T>`, `u128` / `i128`, missing concrete wrapper widths, Rust feature-gate modeling, Rust niche optimization, Rust panic message/object behavior, parser/formatter trait integration, allocator/drop/borrow semantics, randomized `RandomState`, SipHash compatibility, Rust iterator trait hierarchy, generic `Option` / `Result` / `ControlFlow`, generic `FromIterator`, `IntoIterator`, true format!, Condvar/Barrier, process env maps/Stdio objects, and thread stack/name builder ABI.


## Active std parity batch (2026-07-15 primitive checked/saturating sign casts)

Completed supportable primitive checked/saturating same-width sign-cast helpers:
- `NUM_U{8,16,32,64,SIZE}_CHECKED_CAST_SIGNED` and `*_SATURATING_CAST_SIGNED`: concrete Rust nightly `integer_cast_extras` shape for unsigned-to-signed conversion.
- `NUM_I{8,16,32,64,SIZE}_CHECKED_CAST_UNSIGNED` and `*_SATURATING_CAST_UNSIGNED`: matching signed-to-unsigned conversion shape.
- Checked helpers expose explicit `ok/out` results instead of Rust `Option`; unsigned values above the same-width signed maximum and negative signed values return `ok=0/out=0`. Saturating helpers clamp to the signed maximum or unsigned zero respectively.
- `usize` / `isize` alias the current 64-bit SA ABI. This batch deliberately does not expose strict panic casts, `u128` / `i128`, Rust feature-gate enforcement, Option object layout, or trait-level dispatch.
- Test file `std_num_checked_saturating_sign_cast_macro_surface.sa` (panic ID 10629).

Focused validation only:
- `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_num_checked_saturating_sign_cast_macro_surface.sa --jobs 1 --trace-panic` -> `1 passed; 0 failed; 0 skipped`.

Panic IDs next free: 10630+.
Still blocked without redesign: generic primitive/container trait impl dispatch, strict integer-cast panic behavior, cross-width integer conversions, generic `NonZero<T>`, generic `Wrapping<T>` / `Saturating<T>`, `u128` / `i128`, missing concrete wrapper widths, Rust feature-gate modeling, Rust niche optimization, Rust panic object behavior for invalid arithmetic, parser/formatter trait integration, allocator/drop/borrow semantics, randomized `RandomState`, SipHash compatibility, Rust iterator trait hierarchy, generic `Option` / `Result` / `ControlFlow`, generic `FromIterator`, `IntoIterator`, true format!, Condvar/Barrier, process env maps/Stdio objects, and thread stack/name builder ABI.


## Active std parity batch (2026-07-15 primitive sign casts)

Completed supportable primitive same-width sign-cast helpers:
- `NUM_U8_CAST_SIGNED`, `NUM_U16_CAST_SIGNED`, `NUM_U32_CAST_SIGNED`, `NUM_U64_CAST_SIGNED`, and `NUM_USIZE_CAST_SIGNED`: concrete Rust unsigned primitive `cast_signed` bit-pattern shape for existing SA unsigned integer widths.
- `NUM_I8_CAST_UNSIGNED`, `NUM_I16_CAST_UNSIGNED`, `NUM_I32_CAST_UNSIGNED`, `NUM_I64_CAST_UNSIGNED`, and `NUM_ISIZE_CAST_UNSIGNED`: matching Rust signed primitive `cast_unsigned` same-width shape.
- Narrow unsigned-to-signed casts sign-extend into SA's signed register shape; narrow signed-to-unsigned casts mask to the declared Rust width. `usize` / `isize` alias the current 64-bit SA ABI.
- This follows Rust's current primitive integer `integer_sign_cast` methods for existing concrete widths. It deliberately does not expose cross-width conversions, `u128` / `i128`, or trait-level dispatch.
- Test file `std_num_primitive_sign_cast_macro_surface.sa` (panic ID 10628).

Focused validation only:
- `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_num_primitive_sign_cast_macro_surface.sa --jobs 1 --trace-panic` -> `1 passed; 0 failed; 0 skipped`.

Panic IDs next free: 10629+.
Still blocked without redesign: generic primitive/container trait impl dispatch, cross-width integer conversions, generic `NonZero<T>`, generic `Wrapping<T>` / `Saturating<T>`, `u128` / `i128`, missing concrete wrapper widths, Rust feature-gate modeling, Rust niche optimization, Rust panic object behavior for invalid arithmetic, parser/formatter trait integration, allocator/drop/borrow semantics, randomized `RandomState`, SipHash compatibility, Rust iterator trait hierarchy, generic `Option` / `Result` / `ControlFlow`, generic `FromIterator`, `IntoIterator`, true format!, Condvar/Barrier, process env maps/Stdio objects, and thread stack/name builder ABI.


## Active std parity batch (2026-07-15 signed checked_isqrt)

Completed supportable signed checked integer square-root helpers:
- `NUM_I8_CHECKED_ISQRT`, `NUM_I16_CHECKED_ISQRT`, `NUM_I32_CHECKED_ISQRT`, `NUM_I64_CHECKED_ISQRT`, and `NUM_ISIZE_CHECKED_ISQRT`: concrete Rust signed primitive `checked_isqrt` Option-like shape for the existing SA signed integer widths.
- Nonnegative inputs delegate to the unsigned floor-root helper and return `ok=1`; negative inputs return `ok=0/out=0`. `isize` aliases the current 64-bit SA ABI.
- This follows Rust's current signed primitive `checked_isqrt` method. The direct panic-style signed `isqrt` helper is covered by the later signed-isqrt batch; this checked helper still does not expose `i128`, Rust `Option<Self>` object layout, panic objects, or trait-level dispatch.
- Test file `std_num_signed_checked_isqrt_macro_surface.sa` (panic ID 10627).

Focused validation only:
- `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_num_signed_checked_isqrt_macro_surface.sa --jobs 1 --trace-panic` -> `1 passed; 0 failed; 0 skipped`.

Panic IDs next free: 10628+.
Still blocked without redesign: generic primitive/container trait impl dispatch, generic `NonZero<T>`, generic `Wrapping<T>` / `Saturating<T>`, `u128` / `i128`, missing concrete wrapper widths, Rust feature-gate modeling, Rust niche optimization, Rust panic object behavior for invalid arithmetic, parser/formatter trait integration, allocator/drop/borrow semantics, randomized `RandomState`, SipHash compatibility, Rust iterator trait hierarchy, generic `Option` / `Result` / `ControlFlow`, generic `FromIterator`, `IntoIterator`, true format!, Condvar/Barrier, process env maps/Stdio objects, and thread stack/name builder ABI.


## Active std parity batch (2026-07-15 unsigned isqrt)

Completed supportable unsigned integer square-root helpers:
- `NUM_U8_ISQRT`, `NUM_U16_ISQRT`, `NUM_U32_ISQRT`, `NUM_U64_ISQRT`, and `NUM_USIZE_ISQRT`: concrete Rust unsigned primitive `isqrt` floor-result shape for the existing SA integer widths.
- `NONZERO_U8_ISQRT`, `NONZERO_U16_ISQRT`, `NONZERO_U32_ISQRT`, `NONZERO_U64_ISQRT`, and `NONZERO_USIZE_ISQRT`: matching Rust unsigned `NonZero<T>::isqrt` wrapper shape for existing concrete NonZero layouts.
- Narrow unsigned primitives mask to the declared Rust width before computing. `usize` / `NonZeroUsize` alias the current 64-bit SA ABI. NonZero outputs remain nonzero because unsigned nonzero inputs are at least 1.
- This follows Rust's current primitive unsigned and `core::num::NonZero` unsigned `isqrt` methods for the existing concrete widths. The signed primitive direct `isqrt` helper is covered by the later signed-isqrt batch; this unsigned batch still does not expose generic `NonZero<T>`, `u128`, Rust feature-gate modeling, niche optimization, or trait-level dispatch.
- Test file `std_num_isqrt_macro_surface.sa` (panic ID 10626).

Focused validation only:
- `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_num_isqrt_macro_surface.sa --jobs 1 --trace-panic` -> `1 passed; 0 failed; 0 skipped`.

Panic IDs next free: 10627+.
Still blocked without redesign: generic primitive/container trait impl dispatch, generic `NonZero<T>`, generic `Wrapping<T>` / `Saturating<T>`, `u128` / `i128`, missing concrete wrapper widths, Rust feature-gate modeling, Rust niche optimization, Rust panic object behavior for invalid arithmetic, parser/formatter trait integration, allocator/drop/borrow semantics, randomized `RandomState`, SipHash compatibility, Rust iterator trait hierarchy, generic `Option` / `Result` / `ControlFlow`, generic `FromIterator`, `IntoIterator`, true format!, Condvar/Barrier, process env maps/Stdio objects, and thread stack/name builder ABI.


## Active std parity batch (2026-07-15 NonZero sign casts)

Completed supportable NonZero same-width sign-cast helpers:
- `NONZERO_U8_CAST_SIGNED`, `NONZERO_U16_CAST_SIGNED`, `NONZERO_U32_CAST_SIGNED`, `NONZERO_U64_CAST_SIGNED`, and `NONZERO_USIZE_CAST_SIGNED`: concrete Rust `NonZero<unsigned>::cast_signed` bit-pattern shape for the existing SA unsigned NonZero layouts.
- `NONZERO_I8_CAST_UNSIGNED`, `NONZERO_I16_CAST_UNSIGNED`, `NONZERO_I32_CAST_UNSIGNED`, `NONZERO_I64_CAST_UNSIGNED`, and `NONZERO_ISIZE_CAST_UNSIGNED`: matching Rust `NonZero<signed>::cast_unsigned` same-width shape for existing signed NonZero layouts.
- Narrow unsigned-to-signed casts sign-extend into SA's signed register shape; narrow signed-to-unsigned casts mask to the declared Rust width. `usize` / `isize` alias the current 64-bit SA ABI.
- This follows Rust's current `core::num::NonZero` `integer_sign_cast` methods for the existing concrete widths. It deliberately does not expose generic `NonZero<T>`, cross-width integer conversions, `u128` / `i128`, Rust niche optimization, or trait-level dispatch.
- Test file `std_num_nonzero_sign_cast_macro_surface.sa` (panic ID 10625).

Focused validation only:
- `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_num_nonzero_sign_cast_macro_surface.sa --jobs 1 --trace-panic` -> `1 passed; 0 failed; 0 skipped`.

Panic IDs next free: 10626+.
Still blocked without redesign: generic primitive/container trait impl dispatch, generic `NonZero<T>`, generic `Wrapping<T>` / `Saturating<T>`, `u128` / `i128`, missing concrete wrapper widths, Rust feature-gate modeling, Rust niche optimization, Rust panic object behavior for invalid arithmetic, parser/formatter trait integration, allocator/drop/borrow semantics, randomized `RandomState`, SipHash compatibility, Rust iterator trait hierarchy, generic `Option` / `Result` / `ControlFlow`, generic `FromIterator`, `IntoIterator`, true format!, Condvar/Barrier, process env maps/Stdio objects, and thread stack/name builder ABI.


## Active std parity batch (2026-07-15 NonZero unsigned bit_width)

Completed supportable NonZero unsigned bit-width helpers:
- `NONZERO_U8_BIT_WIDTH_NZ_U32`, `NONZERO_U16_BIT_WIDTH_NZ_U32`, `NONZERO_U32_BIT_WIDTH_NZ_U32`, `NONZERO_U64_BIT_WIDTH_NZ_U32`, and `NONZERO_USIZE_BIT_WIDTH_NZ_U32`: concrete Rust `NonZero<unsigned>::bit_width -> NonZero<u32>` shape for the existing SA unsigned NonZero layouts.
- Narrow unsigned widths compute `BITS - leading_zeros()` with declared Rust primitive widths. `NonZeroU64` delegates to the existing primitive `NUM_U64_BIT_WIDTH`, and `NonZeroUsize` aliases the 64-bit `NonZeroU64` ABI.
- This follows Rust's current `core::num::NonZero` unsigned `bit_width` method for the existing concrete unsigned widths. It deliberately does not expose signed NonZero bit-width helpers, generic `NonZero<T>`, `u128`, Rust feature-gate modeling, niche optimization, or trait-level dispatch.
- Test file `std_num_nonzero_bit_width_macro_surface.sa` (panic ID 10624).

Focused validation only:
- `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_num_nonzero_bit_width_macro_surface.sa --jobs 1 --trace-panic` -> `1 passed; 0 failed; 0 skipped`.

Panic IDs next free: 10625+.
Still blocked without redesign: generic primitive/container trait impl dispatch, generic `NonZero<T>`, generic `Wrapping<T>` / `Saturating<T>`, `u128` / `i128`, missing concrete wrapper widths, Rust feature-gate modeling, Rust niche optimization, Rust panic object behavior for invalid arithmetic, parser/formatter trait integration, allocator/drop/borrow semantics, randomized `RandomState`, SipHash compatibility, Rust iterator trait hierarchy, generic `Option` / `Result` / `ControlFlow`, generic `FromIterator`, `IntoIterator`, true format!, Condvar/Barrier, process env maps/Stdio objects, and thread stack/name builder ABI.


## Active std parity batch (2026-07-15 Wrapping next power)

Completed supportable Wrapping unsigned next-power helpers:
- `WRAPPING_U64_NEXT_POWER_OF_TWO`: concrete Rust `Wrapping<u64>::next_power_of_two` forwarding shape, writing a destination wrapper and returning 0 on overflow.
- `WRAPPING_U32_NEXT_POWER_OF_TWO`: matching concrete `Wrapping<u32>` shape, masking the stored value to 32 bits before computing and returning 0 when the next power would exceed `u32::MAX`.
- This follows Rust's current `core::num::Wrapping` unsigned `next_power_of_two` method for the existing SA wrapper widths. It deliberately does not expose `Saturating` next-power helpers, signed wrapper next-power helpers, generic `Wrapping<T>`, `u128`, missing wrapper widths, Rust feature-gate modeling, or trait-level dispatch.
- Test file `std_num_wrapping_next_power_macro_surface.sa` (panic ID 10623).

Focused validation only:
- `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_num_wrapping_next_power_macro_surface.sa --jobs 1 --trace-panic` -> `1 passed; 0 failed; 0 skipped`.

Panic IDs next free: 10624+.
Still blocked without redesign: generic primitive/container trait impl dispatch, generic `Wrapping<T>` / `Saturating<T>`, `u128` / `i128`, missing concrete wrapper widths, Rust feature-gate modeling, Rust panic object behavior for invalid arithmetic, parser/formatter trait integration, allocator/drop/borrow semantics, randomized `RandomState`, SipHash compatibility, Rust iterator trait hierarchy, generic `Option` / `Result` / `ControlFlow`, generic `FromIterator`, `IntoIterator`, true format!, Condvar/Barrier, process env maps/Stdio objects, and thread stack/name builder ABI.


## Active std parity batch (2026-07-15 Wrapping/Saturating pow bits)

Completed supportable Wrapping/Saturating pow/BITS helpers:
- `WRAPPING_U64_BITS`, `WRAPPING_U32_BITS`, `WRAPPING_I64_BITS`, `SATURATING_U64_BITS`, and `SATURATING_I64_BITS`: concrete associated-constant aliases for the existing SA wrapper layouts.
- `WRAPPING_U64_POW`, `WRAPPING_U32_POW`, and `WRAPPING_I64_POW`: Rust `Wrapping<T>::pow` forwarding shape over the inner primitive, writing destination wrappers. `WrappingU32` preserves 32-bit masked results through the existing primitive helper.
- `WRAPPING_U64_IS_POWER_OF_TWO`, `WRAPPING_U32_IS_POWER_OF_TWO`, and `SATURATING_U64_IS_POWER_OF_TWO`: unsigned wrapper predicate helpers forwarding to primitive power-of-two checks, with `WrappingU32` masking to the concrete width.
- `SATURATING_U64_POW` and `SATURATING_I64_POW`: Rust `Saturating<T>::pow` / primitive `saturating_pow` shape, returning unsigned `MAX` on overflow and signed `MIN` only for negative bases with odd exponents.
- This follows Rust's current `core::num::{Wrapping,Saturating}` inherent method surface for the existing SA wrapper widths. It deliberately does not expose generic `Wrapping<T>` / `Saturating<T>`, `u128` / `i128`, missing wrapper widths, trait-level dispatch, formatting traits, or Rust panic object modeling.
- Test file `std_num_wrapping_saturating_pow_bits_macro_surface.sa` (panic ID 10622).

Focused validation only:
- `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_num_wrapping_saturating_pow_bits_macro_surface.sa --jobs 1 --trace-panic` -> `1 passed; 0 failed; 0 skipped`.

Panic IDs next free: 10623+.
Still blocked without redesign: generic primitive/container trait impl dispatch, generic `Wrapping<T>` / `Saturating<T>`, `u128` / `i128`, missing concrete wrapper widths, Rust feature-gate modeling, Rust panic object behavior for invalid arithmetic, parser/formatter trait integration, allocator/drop/borrow semantics, randomized `RandomState`, SipHash compatibility, Rust iterator trait hierarchy, generic `Option` / `Result` / `ControlFlow`, generic `FromIterator`, `IntoIterator`, true format!, Condvar/Barrier, process env maps/Stdio objects, and thread stack/name builder ABI.


## Active std parity batch (2026-07-15 Saturating operators)

Completed supportable Saturating operator helpers:
- `SATURATING_U64_DIV`, `SATURATING_U64_REM`, `SATURATING_U64_NOT`, `SATURATING_U64_BITAND`, `SATURATING_U64_BITOR`, and `SATURATING_U64_BITXOR`: concrete Rust `Saturating<u64>` operator-forwarding shape for SA's existing layout, writing destination wrappers.
- `SATURATING_I64_DIV`, `SATURATING_I64_REM`, `SATURATING_I64_NOT`, `SATURATING_I64_BITAND`, `SATURATING_I64_BITOR`, and `SATURATING_I64_BITXOR`: matching concrete Rust `Saturating<i64>` operator-forwarding shape, including the `MIN / -1 -> MAX` saturating division branch.
- This follows Rust's current `core::num::Saturating` operator impls for the existing SA wrapper widths. It deliberately does not expose generic `Saturating<T>`, `u128` / `i128`, missing wrapper widths, assignment operator traits, formatting traits, or Rust zero-divisor panic objects.
- Test file `std_num_saturating_operator_macro_surface.sa` (panic ID 10621).

Focused validation only:
- `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_num_saturating_operator_macro_surface.sa --jobs 1 --trace-panic` -> `1 passed; 0 failed; 0 skipped`.

Panic IDs next free: 10622+.
Still blocked without redesign: generic primitive/container trait impl dispatch, generic `Wrapping<T>` / `Saturating<T>`, `u128` / `i128`, missing concrete wrapper widths, Rust feature-gate modeling, Rust panic object behavior for zero divisors and invalid arithmetic, parser/formatter trait integration, allocator/drop/borrow semantics, randomized `RandomState`, SipHash compatibility, Rust iterator trait hierarchy, generic `Option` / `Result` / `ControlFlow`, generic `FromIterator`, `IntoIterator`, true format!, Condvar/Barrier, process env maps/Stdio objects, and thread stack/name builder ABI.


## Active std parity batch (2026-07-15 Wrapping/Saturating operators)

Completed supportable Wrapping/Saturating operator helpers:
- `WRAPPING_{U64,U32,I64}_DIV`, `*_REM`, `*_SHL`, `*_SHR`, `*_NOT`, `*_BITAND`, `*_BITOR`, and `*_BITXOR`: concrete Rust operator-forwarding shape for SA's existing wrapper layouts, loading inner values, applying the matching primitive wrapping or bit-pattern operation, and writing a destination wrapper.
- `WRAPPING_I64_NEG`, `WRAPPING_I64_ABS`, `WRAPPING_I64_SIGNUM`, `WRAPPING_I64_IS_POSITIVE`, and `WRAPPING_I64_IS_NEGATIVE`: concrete signed `Wrapping<i64>` unary/sign helper shape, forwarding to existing signed primitive helpers.
- `SATURATING_I64_NEG`, `SATURATING_I64_ABS`, `SATURATING_I64_SIGNUM`, `SATURATING_I64_IS_POSITIVE`, and `SATURATING_I64_IS_NEGATIVE`: concrete signed `Saturating<i64>` unary/sign helper shape, forwarding to existing signed saturating primitive helpers where relevant.
- `WrappingU32` masks operands/results to the concrete 32-bit width for division, remainder, shifts, and bitwise operations.
- This follows Rust's current `core::num::{Wrapping,Saturating}` operator/inherent method shapes for the existing SA wrapper widths. It deliberately does not expose generic `Wrapping<T>` / `Saturating<T>`, `u128` / `i128`, missing wrapper widths, Saturating div/rem panic behavior, assignment operator traits, formatting traits, or generic trait/type-level integration.
- Test file `std_num_wrapping_saturating_ops_macro_surface.sa` (panic ID 10620).

Focused validation only:
- `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_num_wrapping_saturating_ops_macro_surface.sa --jobs 1 --trace-panic` -> `1 passed; 0 failed; 0 skipped`.

Panic IDs next free: 10621+.
Still blocked without redesign: generic primitive/container trait impl dispatch, generic `Wrapping<T>` / `Saturating<T>`, `u128` / `i128`, missing concrete wrapper widths, Rust feature-gate modeling, Rust panic behavior for Saturating div/rem and invalid arithmetic, parser/formatter trait integration, allocator/drop/borrow semantics, randomized `RandomState`, SipHash compatibility, Rust iterator trait hierarchy, generic `Option` / `Result` / `ControlFlow`, generic `FromIterator`, `IntoIterator`, true format!, Condvar/Barrier, process env maps/Stdio objects, and thread stack/name builder ABI.


## Active std parity batch (2026-07-15 Wrapping/Saturating comparisons)

Completed supportable Wrapping/Saturating comparison helpers:
- `WRAPPING_{U64,U32,I64}_EQ`, `*_NE`, `*_CMP`, `*_PARTIAL_CMP`, `*_LT`, `*_LE`, `*_GT`, and `*_GE`: concrete Rust derived `PartialEq` / `Eq` / `PartialOrd` / `Ord` shape for SA's existing wrapper layouts, comparing the inner primitive values and returning direct bool/ordering scalars.
- `SATURATING_{U64,I64}_EQ`, `*_NE`, `*_CMP`, `*_PARTIAL_CMP`, `*_LT`, `*_LE`, `*_GT`, and `*_GE`: matching Rust derived comparison shape for the existing saturating wrapper layouts.
- `WrappingU32` masks both stored values to the concrete 32-bit width before equality/order comparisons. Signed `i64` wrappers use signed ordering, while `u64` / `u32` wrappers use unsigned ordering.
- This follows Rust's current `core::num::{Wrapping,Saturating}` derived comparison behavior for the existing SA wrapper widths. It deliberately does not expose generic `Wrapping<T>` / `Saturating<T>`, `u128` / `i128`, missing wrapper widths, Rust `Option<Ordering>` object modeling, or generic trait/type-level integration.
- Test file `std_num_wrapping_saturating_cmp_macro_surface.sa` (panic ID 10619).

Focused validation only:
- `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_num_wrapping_saturating_cmp_macro_surface.sa --jobs 1 --trace-panic` -> `1 passed; 0 failed; 0 skipped`.

Panic IDs next free: 10620+.
Still blocked without redesign: generic primitive/container trait impl dispatch, generic `Wrapping<T>` / `Saturating<T>`, `u128` / `i128`, missing concrete wrapper widths, Rust feature-gate modeling, parser/formatter trait integration, allocator/drop/borrow semantics, randomized `RandomState`, SipHash compatibility, Rust iterator trait hierarchy, generic `Option` / `Result` / `ControlFlow`, generic `FromIterator`, `IntoIterator`, true format!, Condvar/Barrier, process env maps/Stdio objects, and thread stack/name builder ABI.


## Active std parity batch (2026-07-15 Wrapping/Saturating bit transforms)

Completed supportable Wrapping/Saturating bit-transform helpers:
- `WRAPPING_{U64,U32,I64}_ROTATE_LEFT`, `*_ROTATE_RIGHT`, `*_REVERSE_BITS`, `*_SWAP_BYTES`, `*_TO_BE`, `*_FROM_BE`, `*_TO_LE`, and `*_FROM_LE`: concrete Rust `Wrapping<T>` inherent bit-transform/endian forwarding shape for SA's existing wrapper layouts, writing transformed inner primitive values into destination wrappers.
- `SATURATING_{U64,I64}_ROTATE_LEFT`, `*_ROTATE_RIGHT`, `*_REVERSE_BITS`, `*_SWAP_BYTES`, `*_TO_BE`, `*_FROM_BE`, `*_TO_LE`, and `*_FROM_LE`: matching Rust `Saturating<T>` inherent bit-transform/endian forwarding shape for the existing saturating wrapper layouts.
- `WrappingU32` masks and rotates/reverses within the concrete 32-bit storage width. Signed `i64` wrappers preserve Rust's two's-complement bit-pattern behavior through the existing primitive helper surface.
- This follows Rust's current `core::num::{Wrapping,Saturating}` forwarding methods for the existing SA wrapper widths. It deliberately does not expose generic `Wrapping<T>` / `Saturating<T>`, `u128` / `i128`, missing wrapper widths, nightly feature-gate modeling, or generic trait/type-level integration.
- Test file `std_num_wrapping_saturating_bit_transform_macro_surface.sa` (panic ID 10618).

Focused validation only:
- `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_num_wrapping_saturating_bit_transform_macro_surface.sa --jobs 1 --trace-panic` -> `1 passed; 0 failed; 0 skipped`.

Panic IDs next free: 10619+.
Still blocked without redesign: generic primitive/container trait impl dispatch, generic `Wrapping<T>` / `Saturating<T>`, `u128` / `i128`, missing concrete wrapper widths, Rust feature-gate modeling, parser/formatter trait integration, allocator/drop/borrow semantics, randomized `RandomState`, SipHash compatibility, Rust iterator trait hierarchy, generic `Option` / `Result` / `ControlFlow`, generic `FromIterator`, `IntoIterator`, true format!, Condvar/Barrier, process env maps/Stdio objects, and thread stack/name builder ABI.


## Active std parity batch (2026-07-15 Wrapping/Saturating bit counts)

Completed supportable Wrapping/Saturating bit-count helpers:
- `WRAPPING_{U64,U32,I64}_COUNT_ONES`, `*_COUNT_ZEROS`, `*_LEADING_ZEROS`, and `*_TRAILING_ZEROS`: concrete Rust `Wrapping<T>` inherent bit-count/zero-scan shape for SA's existing wrapper layouts, returning direct scalar counts from the inner primitive value.
- `SATURATING_{U64,I64}_COUNT_ONES`, `*_COUNT_ZEROS`, `*_LEADING_ZEROS`, and `*_TRAILING_ZEROS`: matching Rust `Saturating<T>` inherent bit-count/zero-scan shape for the existing saturating wrapper layouts.
- `WrappingU32` masks to the concrete 32-bit storage width before counting, including zero-input leading/trailing results of 32 rather than 64. The signed `i64` wrappers preserve Rust's two's-complement bit-pattern behavior through the existing primitive helper surface.
- This follows Rust's current `core::num::{Wrapping,Saturating}` forwarding methods for the existing SA wrapper widths. It deliberately does not expose generic `Wrapping<T>` / `Saturating<T>`, `u128` / `i128`, missing wrapper widths, nightly feature-gate modeling, or generic trait/type-level integration.
- Test file `std_num_wrapping_saturating_bit_count_macro_surface.sa` (panic ID 10617).

Focused validation only:
- `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_num_wrapping_saturating_bit_count_macro_surface.sa --jobs 1 --trace-panic` -> `1 passed; 0 failed; 0 skipped`.

Panic IDs next free: 10618+.
Still blocked without redesign: generic primitive/container trait impl dispatch, generic `Wrapping<T>` / `Saturating<T>`, `u128` / `i128`, missing concrete wrapper widths, Rust feature-gate modeling, parser/formatter trait integration, allocator/drop/borrow semantics, randomized `RandomState`, SipHash compatibility, Rust iterator trait hierarchy, generic `Option` / `Result` / `ControlFlow`, generic `FromIterator`, `IntoIterator`, true format!, Condvar/Barrier, process env maps/Stdio objects, and thread stack/name builder ABI.


## Active std parity batch (2026-07-15 NonZero count_ones NonZeroU32)

Completed supportable NonZero count_ones nonzero-result helpers:
- `NONZERO_{U8,U16,U32,U64,USIZE,I8,I16,I32,I64,ISIZE}_COUNT_ONES_NZ_U32`: concrete Rust `NonZero<T>::count_ones -> NonZero<u32>` shape for SA's existing NonZero integer layouts, writing the existing scalar count result into a `NonZeroU32` destination wrapper.
- This follows Rust's current `core::num::NonZero<T>` `count_ones` return shape for the existing SA integer widths while preserving the older scalar `*_COUNT_ONES` helper surface. It deliberately does not expose generic `NonZero<T>`, `u128` / `i128`, Rust niche optimization behavior, or generic trait/type-level integration.
- Test file `std_num_nonzero_count_ones_nz_macro_surface.sa` (panic ID 10616).

Focused validation only:
- `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_num_nonzero_count_ones_nz_macro_surface.sa --jobs 1 --trace-panic` -> `1 passed; 0 failed; 0 skipped`.

Panic IDs next free: 10617+.
Still blocked without redesign: generic primitive/container trait impl dispatch, generic `NonZero<T>`, `u128` / `i128` and their NonZero variants, Rust niche optimization semantics, parser/formatter trait integration, allocator/drop/borrow semantics, randomized `RandomState`, SipHash compatibility, Rust iterator trait hierarchy, generic `Option` / `Result` / `ControlFlow`, generic `FromIterator`, `IntoIterator`, true format!, Condvar/Barrier, process env maps/Stdio objects, and thread stack/name builder ABI.


## Active std parity batch (2026-07-15 NonZero checked/saturating pow)

Completed supportable NonZero checked/saturating pow helpers:
- `NONZERO_{U8,U16,U32,U64,USIZE,I8,I16,I32,I64,ISIZE}_CHECKED_POW`: concrete Rust `NonZero<T>::checked_pow` shape for SA's existing NonZero integer layouts, returning `ok/out` for representable nonzero pow results and `ok=0` on overflow.
- `NONZERO_{U8,U16,U32,U64,USIZE,I8,I16,I32,I64,ISIZE}_SATURATING_POW`: concrete Rust `NonZero<T>::saturating_pow` shape for the same wrappers, saturating to the matching unsigned max or signed min/max boundary.
- This follows Rust's current `core::num::NonZero<T>` inherent pow implementation shape for the existing SA integer widths. It deliberately does not expose generic `NonZero<T>`, `u128` / `i128`, Rust niche optimization behavior, or generic trait/type-level integration.
- Test file `std_num_nonzero_pow_macro_surface.sa` (panic ID 10615).

Focused validation only:
- `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_num_nonzero_pow_macro_surface.sa --jobs 1 --trace-panic` -> `1 passed; 0 failed; 0 skipped`.

Panic IDs next free: 10616+.
Still blocked without redesign: generic primitive/container trait impl dispatch, generic `NonZero<T>`, `u128` / `i128` and their NonZero variants, Rust niche optimization semantics, parser/formatter trait integration, allocator/drop/borrow semantics, randomized `RandomState`, SipHash compatibility, Rust iterator trait hierarchy, generic `Option` / `Result` / `ControlFlow`, generic `FromIterator`, `IntoIterator`, true format!, Condvar/Barrier, process env maps/Stdio objects, and thread stack/name builder ABI.


## Active std parity batch (2026-07-15 NonZero unsigned div_ceil)

Completed supportable NonZero unsigned div_ceil helpers:
- `NONZERO_{U8,U16,U32,U64,USIZE}_DIV_CEIL`: concrete Rust `NonZero<T>::div_ceil` shape for SA's existing unsigned NonZero integer layouts, writing the primitive unsigned ceil-division result of two nonzero wrappers into a destination wrapper.
- This follows Rust's current unsigned-only `core::num::NonZero<T>` inherent `div_ceil` implementation for the existing SA unsigned integer widths. It deliberately does not expose signed NonZero variants, generic `NonZero<T>`, `u128`, Rust niche optimization behavior, or generic trait/type-level integration.
- Test file `std_num_nonzero_div_ceil_macro_surface.sa` (panic ID 10614).

Focused validation only:
- `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_num_nonzero_div_ceil_macro_surface.sa --jobs 1 --trace-panic` -> `1 passed; 0 failed; 0 skipped`.

Panic IDs next free: 10615+.
Still blocked without redesign: generic primitive/container trait impl dispatch, generic `NonZero<T>`, `u128` / `i128` and their NonZero variants, Rust niche optimization semantics, parser/formatter trait integration, allocator/drop/borrow semantics, randomized `RandomState`, SipHash compatibility, Rust iterator trait hierarchy, generic `Option` / `Result` / `ControlFlow`, generic `FromIterator`, `IntoIterator`, true format!, Condvar/Barrier, process env maps/Stdio objects, and thread stack/name builder ABI.


## Active std parity batch (2026-07-15 NonZero unsigned midpoint)

Completed supportable NonZero unsigned midpoint helpers:
- `NONZERO_{U8,U16,U32,U64,USIZE}_MIDPOINT`: concrete Rust `NonZero<T>::midpoint` shape for SA's existing unsigned NonZero integer layouts, writing the primitive unsigned midpoint of two nonzero wrappers into a destination wrapper.
- This follows Rust's current unsigned `core::num::NonZero<T>` inherent midpoint implementation for the existing SA unsigned integer widths. It deliberately does not expose signed NonZero variants, generic `NonZero<T>`, `u128`, Rust niche optimization behavior, or generic trait/type-level integration.
- Test file `std_num_nonzero_midpoint_macro_surface.sa` (panic ID 10613).

Focused validation only:
- `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_num_nonzero_midpoint_macro_surface.sa --jobs 1 --trace-panic` -> `1 passed; 0 failed; 0 skipped`.

Panic IDs next free: 10614+.
Still blocked without redesign: generic primitive/container trait impl dispatch, generic `NonZero<T>`, `u128` / `i128` and their NonZero variants, Rust niche optimization semantics, parser/formatter trait integration, allocator/drop/borrow semantics, randomized `RandomState`, SipHash compatibility, Rust iterator trait hierarchy, generic `Option` / `Result` / `ControlFlow`, generic `FromIterator`, `IntoIterator`, true format!, Condvar/Barrier, process env maps/Stdio objects, and thread stack/name builder ABI.


## Active std parity batch (2026-07-15 NonZero unsigned ilog)

Completed supportable NonZero unsigned logarithm helpers:
- `NONZERO_{U8,U16,U32,U64,USIZE}_ILOG2`: concrete Rust `NonZero<T>::ilog2` shape for SA's existing unsigned NonZero integer layouts, returning the highest set-bit index as a direct scalar.
- `NONZERO_{U8,U16,U32,U64,USIZE}_ILOG10`: concrete Rust `NonZero<T>::ilog10` shape for the same unsigned wrappers, returning floor log10 as a direct scalar.
- This follows Rust's current unsigned `core::num::NonZero<T>` inherent logarithm implementation for the existing SA unsigned integer widths. It deliberately does not expose signed NonZero variants, generic `NonZero<T>`, `u128`, Rust niche optimization behavior, or generic trait/type-level integration.
- Test file `std_num_nonzero_ilog_macro_surface.sa` (panic ID 10612).

Focused validation only:
- `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_num_nonzero_ilog_macro_surface.sa --jobs 1 --trace-panic` -> `1 passed; 0 failed; 0 skipped`.

Panic IDs next free: 10613+.
Still blocked without redesign: generic primitive/container trait impl dispatch, generic `NonZero<T>`, `u128` / `i128` and their NonZero variants, Rust niche optimization semantics, parser/formatter trait integration, allocator/drop/borrow semantics, randomized `RandomState`, SipHash compatibility, Rust iterator trait hierarchy, generic `Option` / `Result` / `ControlFlow`, generic `FromIterator`, `IntoIterator`, true format!, Condvar/Barrier, process env maps/Stdio objects, and thread stack/name builder ABI.


## Active std parity batch (2026-07-15 NonZero unsigned checked next power)

Completed supportable NonZero unsigned checked-next-power helpers:
- `NONZERO_{U8,U16,U32,U64,USIZE}_CHECKED_NEXT_POWER_OF_TWO`: concrete Rust `NonZero<T>::checked_next_power_of_two` shape for SA's existing unsigned NonZero integer layouts, writing the smallest power of two greater than or equal to the source wrapper into a destination wrapper when representable.
- The helpers return `ok=1` for representable results and `ok=0` for Rust `None`, including narrow-width overflow such as `NonZeroU8::MAX.checked_next_power_of_two()`.
- This follows Rust's current unsigned `core::num::NonZero<T>` inherent checked-next-power implementation for the existing SA unsigned integer widths. It deliberately does not expose signed NonZero variants, panic-style `next_power_of_two`, generic `NonZero<T>`, `u128`, Rust niche optimization behavior, or generic trait/type-level integration.
- Test file `std_num_nonzero_checked_next_power_macro_surface.sa` (panic ID 10611).

Focused validation only:
- `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_num_nonzero_checked_next_power_macro_surface.sa --jobs 1 --trace-panic` -> `1 passed; 0 failed; 0 skipped`.

Panic IDs next free: 10612+.
Still blocked without redesign: panic-style integer overflow behavior for `next_power_of_two`, generic primitive/container trait impl dispatch, generic `NonZero<T>`, `u128` / `i128` and their NonZero variants, Rust niche optimization semantics, parser/formatter trait integration, allocator/drop/borrow semantics, randomized `RandomState`, SipHash compatibility, Rust iterator trait hierarchy, generic `Option` / `Result` / `ControlFlow`, generic `FromIterator`, `IntoIterator`, true format!, Condvar/Barrier, process env maps/Stdio objects, and thread stack/name builder ABI.


## Active std parity batch (2026-07-15 NonZero integer isolate one)

Completed supportable NonZero integer isolate-one helpers:
- `NONZERO_{U8,U16,U32,U64,USIZE,I8,I16,I32,I64,ISIZE}_ISOLATE_HIGHEST_ONE`: concrete Rust `NonZero<T>::isolate_highest_one` shape for SA's existing NonZero integer layouts, preserving only the most significant set bit of the stored primitive bit-pattern and writing the result into a destination wrapper.
- Matching `*_ISOLATE_LOWEST_ONE` helpers preserve only the least significant set bit for the same concrete wrappers.
- Narrow unsigned wrappers operate only on their declared primitive width. Narrow signed wrappers isolate within the declared bit width and sign-extend the result back to `i8` / `i16` / `i32` before reconstruction.
- This follows Rust's current `core::num::NonZero<T>` inherent isolate-one implementation shape for the existing SA integer widths. It deliberately does not model Rust nightly feature-gate handling, generic `NonZero<T>`, `u128` / `i128`, Rust niche optimization behavior, or generic trait/type-level integration.
- Test file `std_num_nonzero_isolate_one_macro_surface.sa` (panic ID 10610).

Focused validation only:
- `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_num_nonzero_isolate_one_macro_surface.sa --jobs 1 --trace-panic` -> `1 passed; 0 failed; 0 skipped`.

Panic IDs next free: 10611+.
Still blocked without redesign: Rust nightly feature-gate modeling, generic primitive/container trait impl dispatch, generic `NonZero<T>`, `u128` / `i128` and their NonZero variants, Rust niche optimization semantics, parser/formatter trait integration, allocator/drop/borrow semantics, randomized `RandomState`, SipHash compatibility, Rust iterator trait hierarchy, generic `Option` / `Result` / `ControlFlow`, generic `FromIterator`, `IntoIterator`, true format!, Condvar/Barrier, process env maps/Stdio objects, and thread stack/name builder ABI.


## Active std parity batch (2026-07-15 NonZero integer rotate)

Completed supportable NonZero integer rotate helpers:
- `NONZERO_{U8,U16,U32,U64,USIZE,I8,I16,I32,I64,ISIZE}_ROTATE_LEFT` and matching `*_ROTATE_RIGHT`: concrete Rust `NonZero<T>::rotate_left/right` shape for SA's existing NonZero integer layouts, rotating the stored primitive bit-pattern by `shift % BITS` and writing the result into a destination wrapper.
- Narrow unsigned wrappers rotate only their declared primitive width. Narrow signed wrappers rotate the declared bit width and sign-extend the result back to `i8` / `i16` / `i32` before reconstruction.
- This follows Rust's current `core::num::NonZero<T>` inherent rotate implementation shape for the existing SA integer widths. It deliberately does not model Rust nightly feature-gate handling, generic `NonZero<T>`, `u128` / `i128`, Rust niche optimization behavior, or generic trait/type-level integration.
- Test file `std_num_nonzero_rotate_macro_surface.sa` (panic ID 10609).

Focused validation only:
- `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_num_nonzero_rotate_macro_surface.sa --jobs 1 --trace-panic` -> `1 passed; 0 failed; 0 skipped`.

Panic IDs next free: 10610+.
Still blocked without redesign: Rust nightly feature-gate modeling, generic primitive/container trait impl dispatch, generic `NonZero<T>`, `u128` / `i128` and their NonZero variants, Rust niche optimization semantics, parser/formatter trait integration, allocator/drop/borrow semantics, randomized `RandomState`, SipHash compatibility, Rust iterator trait hierarchy, generic `Option` / `Result` / `ControlFlow`, generic `FromIterator`, `IntoIterator`, true format!, Condvar/Barrier, process env maps/Stdio objects, and thread stack/name builder ABI.


## Active std parity batch (2026-07-15 NonZero integer reverse_bits)

Completed supportable NonZero integer reverse_bits helpers:
- `NONZERO_{U8,U16,U32,U64,USIZE,I8,I16,I32,I64,ISIZE}_REVERSE_BITS`: concrete Rust `NonZero<T>::reverse_bits` shape for SA's existing NonZero integer layouts, reversing the stored primitive bit-pattern and writing the result into a destination wrapper.
- Narrow unsigned wrappers reverse only their declared primitive width. Narrow signed wrappers reverse the declared bit width and sign-extend the result back to `i8` / `i16` / `i32` before reconstruction.
- This follows Rust's current `core::num::NonZero<T>` inherent `reverse_bits` implementation shape for the existing SA integer widths. It deliberately does not model Rust nightly feature-gate handling, generic `NonZero<T>`, `u128` / `i128`, Rust niche optimization behavior, or generic trait/type-level integration.
- Test file `std_num_nonzero_reverse_bits_macro_surface.sa` (panic ID 10608).

Focused validation only:
- `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_num_nonzero_reverse_bits_macro_surface.sa --jobs 1 --trace-panic` -> `1 passed; 0 failed; 0 skipped`.

Panic IDs next free: 10609+.
Still blocked without redesign: Rust nightly feature-gate modeling, generic primitive/container trait impl dispatch, generic `NonZero<T>`, `u128` / `i128` and their NonZero variants, Rust niche optimization semantics, parser/formatter trait integration, allocator/drop/borrow semantics, randomized `RandomState`, SipHash compatibility, Rust iterator trait hierarchy, generic `Option` / `Result` / `ControlFlow`, generic `FromIterator`, `IntoIterator`, true format!, Condvar/Barrier, process env maps/Stdio objects, and thread stack/name builder ABI.


## Active std parity batch (2026-07-15 NonZero integer bit positions)

Completed supportable NonZero integer bit-position helpers:
- `NONZERO_{U8,U16,U32,U64,USIZE,I8,I16,I32,I64,ISIZE}_HIGHEST_ONE`: concrete Rust `NonZero<T>::highest_one` shape for SA's existing NonZero integer layouts, returning `BITS - 1 - leading_zeros()`.
- Matching `*_LOWEST_ONE` helpers return `trailing_zeros()` for the same concrete wrappers.
- This follows Rust's current `core::num::NonZero<T>` inherent bit-position methods only for the existing SA integer widths. It deliberately does not expose generic `NonZero<T>`, `u128` / `i128`, Rust niche optimization behavior, or generic trait/type-level integration.
- Test file `std_num_nonzero_bit_position_macro_surface.sa` (panic ID 10607).

Focused validation only:
- `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_num_nonzero_bit_position_macro_surface.sa --jobs 1 --trace-panic` -> `1 passed; 0 failed; 0 skipped`.

Panic IDs next free: 10608+.
Still blocked without redesign: generic primitive/container trait impl dispatch, generic `NonZero<T>`, `u128` / `i128` and their NonZero variants, Rust niche optimization semantics, parser/formatter trait integration, allocator/drop/borrow semantics, randomized `RandomState`, SipHash compatibility, Rust iterator trait hierarchy, generic `Option` / `Result` / `ControlFlow`, generic `FromIterator`, `IntoIterator`, true format!, Condvar/Barrier, process env maps/Stdio objects, and thread stack/name builder ABI.


## Active std parity batch (2026-07-15 NonZero integer min/max)

Completed supportable NonZero integer min/max helpers:
- `NONZERO_{U8,U16,U32,U64,USIZE,I8,I16,I32,I64,ISIZE}_MIN`: concrete Rust `NonZero<T>::min` shape for SA's existing NonZero integer layouts, choosing the smaller stored primitive value and writing it into a destination wrapper.
- Matching `*_MAX` helpers choose the larger stored primitive value with unsigned ordering for `U*` / `USIZE` and signed ordering for `I*` / `ISIZE`.
- This follows Rust's current `core::num::NonZero<T>` inherent min/max methods only for the existing SA integer widths. It deliberately does not expose `clamp` in this batch because Rust `Ord::clamp` has invalid-range panic semantics while the available concrete `CMP_CLAMP_*` helpers are non-panicking.
- Test file `std_num_nonzero_min_max_macro_surface.sa` (panic ID 10606).

Focused validation only:
- `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_num_nonzero_min_max_macro_surface.sa --jobs 1 --trace-panic` -> `1 passed; 0 failed; 0 skipped`.

Panic IDs next free: 10607+.
Still blocked without redesign: trait-level `Ord::clamp` panic modeling, generic primitive/container trait impl dispatch, generic `NonZero<T>`, `u128` / `i128` and their NonZero variants, Rust niche optimization semantics, parser/formatter trait integration, allocator/drop/borrow semantics, randomized `RandomState`, SipHash compatibility, Rust iterator trait hierarchy, generic `Option` / `Result` / `ControlFlow`, generic `FromIterator`, `IntoIterator`, true format!, Condvar/Barrier, process env maps/Stdio objects, and thread stack/name builder ABI.


## Active std parity batch (2026-07-15 NonZero integer comparison)

Completed supportable NonZero integer comparison helpers:
- `NONZERO_{U8,U16,U32,U64,USIZE,I8,I16,I32,I64,ISIZE}_EQ` and matching `*_NE`: concrete Rust `PartialEq` / `Eq` forwarding shape for SA's existing NonZero integer layouts, comparing each wrapper's stored primitive `get()` value.
- `*_CMP` and `*_PARTIAL_CMP`: concrete Rust `Ord` / `PartialOrd` forwarding shape for the same wrappers, using unsigned ordering for `U*` / `USIZE` and signed ordering for `I*` / `ISIZE`.
- `*_LT`, `*_LE`, `*_GT`, and `*_GE`: relation helpers matching Rust's `self.get() <op> other.get()` implementations for each concrete width.
- This follows Rust's current `core::num::NonZero<T>` comparison implementations only for the existing SA integer widths. It deliberately does not expose generic `NonZero<T>`, `u128` / `i128`, Rust niche optimization behavior, Rust `Option<Ordering>` object modeling, or generic trait dispatch.
- Test file `std_num_nonzero_cmp_macro_surface.sa` (panic ID 10605).

Focused validation only:
- `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_num_nonzero_cmp_macro_surface.sa --jobs 1 --trace-panic` -> `1 passed; 0 failed; 0 skipped`.

Panic IDs next free: 10606+.
Still blocked without redesign: trait-level `PartialEq` / `Eq` / `PartialOrd` / `Ord`, generic primitive/container trait impl dispatch, generic `NonZero<T>`, `u128` / `i128` and their NonZero variants, Rust niche optimization semantics, parser/formatter trait integration, `Ipv6Addr` / `SocketAddrV6` `u128::from_ne_bytes` hashing, `IpAddr` / `SocketAddr` enum trait hashing, allocator/drop/borrow semantics, randomized `RandomState`, SipHash compatibility, Rust iterator trait hierarchy, generic `Option` / `Result` / `ControlFlow`, generic `FromIterator`, `IntoIterator`, true format!, Condvar/Barrier, process env maps/Stdio objects, and thread stack/name builder ABI.


## Active std parity batch (2026-07-15 NonZero integer copy/clone)

Completed supportable NonZero integer copy/clone helpers:
- `NONZERO_{U8,U16,U32,U64,USIZE,I8,I16,I32,I64,ISIZE}_COPY`: concrete Rust `Copy` shape for SA's existing NonZero integer layouts, copying the stored primitive value to another wrapper slot.
- Matching `*_CLONE` and `*_CLONE_FROM` helpers lower Rust's `Clone::clone` and `clone_from` behavior for the same concrete wrappers by reusing the copy path.
- This follows Rust's current `core::num::NonZero<T>` transparent layout plus `Copy` and `Clone` implementations only for the existing SA integer widths. It deliberately does not expose `Default`, generic `NonZero<T>`, `u128` / `i128`, Rust niche optimization behavior, or generic trait dispatch.
- Test file `std_num_nonzero_clone_macro_surface.sa` (panic ID 10604).

Focused validation only:
- `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_num_nonzero_clone_macro_surface.sa --jobs 1 --trace-panic` -> `1 passed; 0 failed; 0 skipped`.

Panic IDs next free: 10605+.
Still blocked without redesign: trait-level `Default` / `Copy` / `Clone` / `PartialEq` / `Eq` / `PartialOrd` / `Ord`, generic primitive/container trait impl dispatch, generic `NonZero<T>`, `u128` / `i128` and their NonZero variants, Rust niche optimization semantics, parser/formatter trait integration, `Ipv6Addr` / `SocketAddrV6` `u128::from_ne_bytes` hashing, `IpAddr` / `SocketAddr` enum trait hashing, allocator/drop/borrow semantics, randomized `RandomState`, SipHash compatibility, Rust iterator trait hierarchy, generic `Option` / `Result` / `ControlFlow`, generic `FromIterator`, `IntoIterator`, true format!, Condvar/Barrier, process env maps/Stdio objects, and thread stack/name builder ABI.


## Active std parity batch (2026-07-15 Phantom marker extended traits)

Completed supportable `PhantomData` / `PhantomPinned` derived/explicit trait helpers:
- `DEFAULT_PHANTOM_DATA` and `DEFAULT_PHANTOM_PINNED` expose cross-module zero-token default aliases for the existing marker layouts.
- `PHANTOM_DATA_COPY` / `PHANTOM_PINNED_COPY` and `PHANTOM_DATA_CLONE_FROM` / `PHANTOM_PINNED_CLONE_FROM` recreate the zero token, matching the supportable ZST copy/clone shape.
- `PHANTOM_DATA_NE` / `PHANTOM_PINNED_NE`, `*_PARTIAL_CMP`, and `*_LT` / `*_LE` / `*_GT` / `*_GE` expose the always-equal ordering surface for these marker tokens.
- This follows Rust's current `core::marker::PhantomData<T>` explicit `Copy`, `Clone`, `Default`, `PartialEq`, `PartialOrd`, and `Ord` implementations and `PhantomPinned`'s matching derived implementations only as a concrete ZST token contract. It does not expose generic marker trait dispatch, drop-check/lifetime effects, full pinning semantics, or a Rust auto-trait solver.
- Test file `std_marker_traits_extended_macro_surface.sa` (panic ID 10603).

Focused validation only:
- `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_marker_traits_extended_macro_surface.sa --jobs 1 --trace-panic` -> `1 passed; 0 failed; 0 skipped`.

Panic IDs next free: 10604+.
Still blocked without redesign: trait-level `Default` / `Copy` / `Clone` / `PartialEq` / `Eq` / `PartialOrd` / `Ord`, generic marker trait dispatch, real marker trait solver / auto-trait inference, `PhantomData<T>` drop-check and ownership effects, full pinning semantics, `UnsafeUnpin`, `StructuralPartialEq`, `DiscriminantKind`, `Freeze`, generic primitive/container trait impl dispatch, allocator/drop/borrow semantics, randomized `RandomState`, SipHash compatibility, Rust iterator trait hierarchy, generic `Option` / `Result` / `ControlFlow`, generic `FromIterator`, `IntoIterator`, true format!, Condvar/Barrier, process env maps/Stdio objects, and thread stack/name builder ABI.


## Active std parity batch (2026-07-15 Wrapping/Saturating default/copy/clone)

Completed supportable numeric-wrapper derived helpers:
- `DEFAULT_WRAPPING_U32`, `DEFAULT_WRAPPING_I64`, and `DEFAULT_SATURATING_I64` complete the scalar zero-default aliases for all five existing wrapper layouts.
- `WRAPPING_U64_*`, `WRAPPING_U32_*`, `WRAPPING_I64_*`, `SATURATING_U64_*`, and `SATURATING_I64_*` now expose concrete `DEFAULT`, `COPY`, `CLONE`, and `CLONE_FROM` helpers.
- Default writes the inner primitive zero value; copy/clone helpers load the existing concrete wrapper field and store it into independent destination storage.
- This follows Rust's current `core::num::Wrapping<T>` and `core::num::Saturating<T>` `#[derive(PartialEq, Eq, PartialOrd, Ord, Clone, Copy, Default, Hash)]` declarations only for existing SA wrapper widths. It does not expose generic wrappers, generic trait dispatch, absent widths, or `Debug` formatting.
- Test file `std_num_wrapping_saturating_clone_default_macro_surface.sa` (panic ID 10602).

Focused validation only:
- `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_num_wrapping_saturating_clone_default_macro_surface.sa --jobs 1 --trace-panic` -> `1 passed; 0 failed; 0 skipped`.

Panic IDs next free: 10603+.
Still blocked without redesign: trait-level `Default` / `Copy` / `Clone`, generic primitive/container trait impl dispatch, generic `Wrapping<T>` / `Saturating<T>`, additional wrapper widths not present in current SA layouts, `u128` / `i128`, generic `NonZero<T>`, `Ipv6Addr` / `SocketAddrV6` `u128::from_ne_bytes` hashing, `IpAddr` / `SocketAddr` enum trait hashing, allocator/drop/borrow semantics, randomized `RandomState`, SipHash compatibility, Windows path prefixes/verbatim semantics, Rust platform encoding objects, true component iterator objects, Rust iterator trait hierarchy, generic `Try` residual/error object integration, generic `Option` / `Result` / `ControlFlow`, generic item/reference semantics, generic `FromIterator`, `IntoIterator`, true format!, Condvar/Barrier, process env maps/Stdio objects, and thread stack/name builder ABI.


## Active std parity batch (2026-07-15 Reverse default/clone)

Completed supportable `cmp::Reverse` derived helpers:
- `CMP_REVERSE_U64_DEFAULT` / `CMP_REVERSE_I64_DEFAULT`: concrete Rust derived `Default` shape for SA's existing `Reverse<u64>` and `Reverse<i64>` layouts.
- `CMP_REVERSE_U64_CLONE` / `CMP_REVERSE_I64_CLONE`: copy each inner primitive into independent destination storage, following Rust's explicit `Clone::clone` forwarding.
- `CMP_REVERSE_U64_CLONE_FROM` / `CMP_REVERSE_I64_CLONE_FROM`: overwrite existing destinations through the existing concrete `COPY` helpers, following Rust's explicit `clone_from` forwarding.
- This follows Rust's current `core::cmp::Reverse<T>` `#[derive(Copy, Debug, Hash)]`, `#[derive_const(PartialEq, Eq, Default)]`, and explicit `Clone` implementation only for the existing concrete primitive wrappers. It does not expose generic `Reverse<T>`, generic trait dispatch, or `Debug` formatting.
- Test file `std_cmp_reverse_clone_default_macro_surface.sa` (panic ID 10601).

Focused validation only:
- `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_cmp_reverse_clone_default_macro_surface.sa --jobs 1 --trace-panic` -> `1 passed; 0 failed; 0 skipped`.

Panic IDs next free: 10602+.
Still blocked without redesign: trait-level `Default` / `Copy` / `Clone` / `Debug`, generic primitive/container trait impl dispatch, generic `Reverse<T>`, real marker trait solver / auto-trait inference, `PhantomData<T>` drop-check and ownership effects, full pinning semantics, `u128` / `i128`, generic `NonZero<T>`, `Ipv6Addr` / `SocketAddrV6` `u128::from_ne_bytes` hashing, `IpAddr` / `SocketAddr` enum trait hashing, allocator/drop/borrow semantics, randomized `RandomState`, SipHash compatibility, Windows path prefixes/verbatim semantics, Rust platform encoding objects, true component iterator objects, Rust iterator trait hierarchy, generic `Try` residual/error object integration, generic `Option` / `Result` / `ControlFlow`, generic item/reference semantics, generic `FromIterator`, `IntoIterator`, true format!, Condvar/Barrier, process env maps/Stdio objects, and thread stack/name builder ABI.


## Active std parity batch (2026-07-15 ManuallyDrop default/copy/clone)

Completed supportable `ManuallyDrop` derived helpers:
- `MANUALLY_DROP_U64_DEFAULT`: concrete Rust derived `Default` shape for SA's existing `ManuallyDropU64` layout, writing the inner `u64` default value.
- `MANUALLY_DROP_U64_COPY` / `MANUALLY_DROP_U64_CLONE`: copy the concrete inner `u64` into independent destination storage.
- `MANUALLY_DROP_U64_CLONE_FROM`: overwrite an existing destination wrapper with the source's inner `u64`, matching the supportable primitive `clone_from` result.
- This follows Rust's current `core::mem::ManuallyDrop<T>` `#[derive(Copy, Clone, Debug, Default)]` declaration only for the concrete `u64` wrapper. It does not expose generic `ManuallyDrop<T>`, `MaybeUninit<T>` initialization validity, Rust drop-suppression safety semantics, generic trait dispatch, or `Debug` formatting.
- Test file `std_mem_manually_drop_clone_default_macro_surface.sa` (panic ID 10600).

Focused validation only:
- `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_mem_manually_drop_clone_default_macro_surface.sa --jobs 1 --trace-panic` -> `1 passed; 0 failed; 0 skipped`.

Panic IDs next free: 10601+.
Still blocked without redesign: trait-level `Default` / `Copy` / `Clone` / `Debug`, generic primitive/container trait impl dispatch, generic `ManuallyDrop<T>`, `MaybeUninit<T>` initialization validity, Rust drop-suppression safety semantics, generic `Reverse<T>` and comparison trait dispatch, real marker trait solver / auto-trait inference, `PhantomData<T>` drop-check and ownership effects, full pinning semantics, `u128` / `i128`, generic `NonZero<T>`, `Ipv6Addr` / `SocketAddrV6` `u128::from_ne_bytes` hashing, `IpAddr` / `SocketAddr` enum trait hashing, allocator/drop/borrow semantics, randomized `RandomState`, SipHash compatibility, Windows path prefixes/verbatim semantics, Rust platform encoding objects, true component iterator objects, Rust iterator trait hierarchy, generic `Try` residual/error object integration, generic `Option` / `Result` / `ControlFlow`, generic item/reference semantics, generic `FromIterator`, `IntoIterator`, true format!, Condvar/Barrier, process env maps/Stdio objects, and thread stack/name builder ABI.


## Active std parity batch (2026-07-15 ManuallyDrop comparison)

Completed supportable `ManuallyDrop` comparison macros:
- `MANUALLY_DROP_U64_EQ` / `MANUALLY_DROP_U64_NE`: concrete Rust `PartialEq` / `Eq` forwarding shape for SA's existing `ManuallyDropU64` layout, by comparing the inner `u64`.
- `MANUALLY_DROP_U64_CMP` / `MANUALLY_DROP_U64_PARTIAL_CMP`: concrete Rust `Ord` / `PartialOrd` forwarding shape for the same `ManuallyDropU64` subset.
- `MANUALLY_DROP_U64_LT`, `MANUALLY_DROP_U64_LE`, `MANUALLY_DROP_U64_GT`, and `MANUALLY_DROP_U64_GE`: relation helpers matching the supportable inner-value ordering shape.
- This follows Rust's current `core::mem::ManuallyDrop<T>` comparison implementations, which forward to `self.value.as_ref()`. It does not expose generic `ManuallyDrop<T>`, `MaybeUninit<T>` comparison, drop-suppression safety semantics, generic trait dispatch, or Rust `Option<Ordering>` object modeling.
- Test file `std_mem_manually_drop_cmp_macro_surface.sa` (panic ID 10599).

Focused validation only:
- `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_mem_manually_drop_cmp_macro_surface.sa --jobs 1 --trace-panic` -> `1 passed; 0 failed; 0 skipped`.

Panic IDs next free: 10600+.
Still blocked without redesign: trait-level `PartialEq` / `Eq` / `PartialOrd` / `Ord` / `Hash` / `Hasher` / `BuildHasher`, generic primitive/container trait impl dispatch, generic `ManuallyDrop<T>`, `MaybeUninit<T>` comparison/hash or initialization validity, Rust drop-suppression safety semantics, generic `Reverse<T>` and comparison trait dispatch, real marker trait solver / auto-trait inference, `PhantomData<T>` drop-check and ownership effects, full pinning semantics, `u128` / `i128`, generic `NonZero<T>`, `Ipv6Addr` / `SocketAddrV6` `u128::from_ne_bytes` hashing, `IpAddr` / `SocketAddr` enum trait hashing, allocator/drop/borrow semantics, randomized `RandomState`, SipHash compatibility, Windows path prefixes/verbatim semantics, Rust platform encoding objects, true component iterator objects, Rust iterator trait hierarchy, generic `Try` residual/error object integration, generic `Option` / `Result` / `ControlFlow`, generic item/reference semantics, generic `FromIterator`, `IntoIterator`, true format!, Condvar/Barrier, process env maps/Stdio objects, and thread stack/name builder ABI.


## Active std parity batch (2026-07-15 ManuallyDrop hash_one)

Completed supportable `ManuallyDrop` hash macros:
- `DEFAULT_HASHER_WRITE_MANUALLY_DROP_U64` / `MANUALLY_DROP_U64_HASH`: concrete Rust `Hash for ManuallyDrop<T>` forwarding shape for SA's existing `ManuallyDropU64` layout, by loading the inner `u64` and hashing it through the `u64` writer.
- `BUILD_HASHER_DEFAULT_HASH_ONE_MANUALLY_DROP_U64` and `RANDOM_STATE_HASH_ONE_MANUALLY_DROP_U64`: concrete `BuildHasher::hash_one` lowerings for the same `ManuallyDropU64` subset.
- This follows Rust's current `core::mem::ManuallyDrop<T>` `Hash` implementation (`self.value.as_ref().hash(state)`) for the concrete `u64` wrapper. It does not expose generic `ManuallyDrop<T>`, `MaybeUninit<T>` hashing, drop-suppression safety semantics, generic trait dispatch, randomized `RandomState`, or SipHash compatibility.
- Test file `std_mem_manually_drop_hash_one_macro_surface.sa` (panic ID 10598).

Focused validation only:
- `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_mem_manually_drop_hash_one_macro_surface.sa --jobs 1 --trace-panic` -> `1 passed; 0 failed; 0 skipped`.

Panic IDs next free: 10599+.
Still blocked without redesign: trait-level `Hash` / `Hasher` / `BuildHasher`, generic primitive/container `Hash` impl dispatch, generic `ManuallyDrop<T>`, `MaybeUninit<T>` hashing or initialization validity, Rust drop-suppression safety semantics, generic `Reverse<T>` and comparison trait dispatch, real marker trait solver / auto-trait inference, `PhantomData<T>` drop-check and ownership effects, full pinning semantics, `u128` / `i128`, generic `NonZero<T>`, `Ipv6Addr` / `SocketAddrV6` `u128::from_ne_bytes` hashing, `IpAddr` / `SocketAddr` enum trait hashing, allocator/drop/borrow semantics, randomized `RandomState`, SipHash compatibility, Windows path prefixes/verbatim semantics, Rust platform encoding objects, true component iterator objects, Rust iterator trait hierarchy, generic `Try` residual/error object integration, generic `Option` / `Result` / `ControlFlow`, generic item/reference semantics, generic `FromIterator`, `IntoIterator`, true format!, Condvar/Barrier, process env maps/Stdio objects, and thread stack/name builder ABI.


## Active std parity batch (2026-07-15 Reverse hash_one)

Completed supportable `cmp::Reverse` hash macros:
- `DEFAULT_HASHER_WRITE_CMP_REVERSE_U64` / `CMP_REVERSE_U64_HASH`: concrete Rust derived single-field `Hash` shape for SA's existing `Reverse<u64>` transparent layout, by loading the inner value and hashing it through the `u64` writer.
- `BUILD_HASHER_DEFAULT_HASH_ONE_CMP_REVERSE_U64` and `RANDOM_STATE_HASH_ONE_CMP_REVERSE_U64`: concrete `BuildHasher::hash_one` lowerings for the same `Reverse<u64>` subset.
- `DEFAULT_HASHER_WRITE_CMP_REVERSE_I64` / `CMP_REVERSE_I64_HASH`: concrete Rust derived single-field `Hash` shape for SA's existing `Reverse<i64>` transparent layout.
- `BUILD_HASHER_DEFAULT_HASH_ONE_CMP_REVERSE_I64` and `RANDOM_STATE_HASH_ONE_CMP_REVERSE_I64`: concrete `BuildHasher::hash_one` lowerings for the same `Reverse<i64>` subset.
- This follows Rust's current `core::cmp::Reverse<T>` `#[derive(Hash)]` and `#[repr(transparent)]` single-field wrapper shape. It does not expose generic `Reverse<T>`, generic trait dispatch, derived `Debug` formatting, randomized `RandomState`, or SipHash compatibility.
- Test file `std_cmp_reverse_hash_one_macro_surface.sa` (panic ID 10597).

Focused validation only:
- `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_cmp_reverse_hash_one_macro_surface.sa --jobs 1 --trace-panic` -> `1 passed; 0 failed; 0 skipped`.

Panic IDs next free: 10598+.
Still blocked without redesign: trait-level `Hash` / `Hasher` / `BuildHasher`, generic primitive/container `Hash` impl dispatch, generic `Reverse<T>` and comparison trait dispatch, real marker trait solver / auto-trait inference, `PhantomData<T>` drop-check and ownership effects, full pinning semantics, `u128` / `i128`, generic `NonZero<T>`, `Ipv6Addr` / `SocketAddrV6` `u128::from_ne_bytes` hashing, `IpAddr` / `SocketAddr` enum trait hashing, allocator/drop/borrow semantics, randomized `RandomState`, SipHash compatibility, Windows path prefixes/verbatim semantics, Rust platform encoding objects, true component iterator objects, Rust iterator trait hierarchy, generic `Try` residual/error object integration, generic `Option` / `Result` / `ControlFlow`, generic item/reference semantics, generic `FromIterator`, `IntoIterator`, true format!, Condvar/Barrier, process env maps/Stdio objects, and thread stack/name builder ABI.


## Active std parity batch (2026-07-15 Phantom marker hash_one)

Completed supportable `PhantomData` / `PhantomPinned` hash macros:
- `DEFAULT_HASHER_WRITE_PHANTOM_DATA` / `PHANTOM_DATA_HASH`: concrete Rust `Hash for PhantomData<T>` no-op shape for SA's existing zero-sized phantom token surface.
- `BUILD_HASHER_DEFAULT_HASH_ONE_PHANTOM_DATA` and `RANDOM_STATE_HASH_ONE_PHANTOM_DATA`: concrete `BuildHasher::hash_one` lowerings for the same no-op marker subset.
- `DEFAULT_HASHER_WRITE_PHANTOM_PINNED` / `PHANTOM_PINNED_HASH`: concrete Rust derived zero-field `Hash` shape for SA's existing `PhantomPinned` token surface.
- `BUILD_HASHER_DEFAULT_HASH_ONE_PHANTOM_PINNED` and `RANDOM_STATE_HASH_ONE_PHANTOM_PINNED`: concrete `BuildHasher::hash_one` lowerings for the same zero-sized marker subset.
- This follows Rust's current `core::marker::PhantomData<T>` explicit empty `Hash::hash` implementation and `PhantomPinned` zero-field derived `Hash`. It does not expose generic marker trait dispatch, drop-check/lifetime semantics, full pinning semantics, randomized `RandomState`, or SipHash compatibility.
- Test file `std_marker_hash_one_macro_surface.sa` (panic ID 10596).

Focused validation only:
- `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_marker_hash_one_macro_surface.sa --jobs 1 --trace-panic` -> `1 passed; 0 failed; 0 skipped`.

Panic IDs next free: 10597+.
Still blocked without redesign: trait-level `Hash` / `Hasher` / `BuildHasher`, generic primitive/container `Hash` impl dispatch, real marker trait solver / auto-trait inference, `PhantomData<T>` drop-check and ownership effects, full pinning semantics, `u128` / `i128`, generic `NonZero<T>`, `Ipv6Addr` / `SocketAddrV6` `u128::from_ne_bytes` hashing, `IpAddr` / `SocketAddr` enum trait hashing, allocator/drop/borrow semantics, randomized `RandomState`, SipHash compatibility, Windows path prefixes/verbatim semantics, Rust platform encoding objects, true component iterator objects, Rust iterator trait hierarchy, generic `Try` residual/error object integration, generic `Option` / `Result` / `ControlFlow`, generic item/reference semantics, generic `FromIterator`, `IntoIterator`, true format!, Condvar/Barrier, process env maps/Stdio objects, and thread stack/name builder ABI.


## Active std parity batch (2026-07-15 Wrapping/Saturating hash_one)

Completed supportable `Wrapping` / `Saturating` hash macros:
- `DEFAULT_HASHER_WRITE_WRAPPING_U64`, `DEFAULT_HASHER_WRITE_WRAPPING_U32`, and `DEFAULT_HASHER_WRITE_WRAPPING_I64` plus matching `WRAPPING_*_HASH`: concrete Rust derived single-field `Hash` shape for SA's existing transparent `Wrapping*` layouts, by loading the inner primitive and hashing through the matching primitive writer.
- `BUILD_HASHER_DEFAULT_HASH_ONE_WRAPPING_*` and `RANDOM_STATE_HASH_ONE_WRAPPING_*`: concrete `BuildHasher::hash_one` lowerings for the same `WrappingU64` / `WrappingU32` / `WrappingI64` subset.
- `DEFAULT_HASHER_WRITE_SATURATING_U64` and `DEFAULT_HASHER_WRITE_SATURATING_I64` plus matching `SATURATING_*_HASH`: concrete Rust derived single-field `Hash` shape for SA's existing transparent `Saturating*` layouts.
- `BUILD_HASHER_DEFAULT_HASH_ONE_SATURATING_*` and `RANDOM_STATE_HASH_ONE_SATURATING_*`: concrete `BuildHasher::hash_one` lowerings for the same `SaturatingU64` / `SaturatingI64` subset.
- This follows Rust's current `core::num::{Wrapping,Saturating}` transparent tuple structs, both deriving `Hash` over their single field. It does not expose generic `Wrapping<T>` / `Saturating<T>`, non-existing SA wrapper widths, generic trait dispatch, randomized `RandomState`, or SipHash compatibility.
- Test file `std_num_wrapping_saturating_hash_one_macro_surface.sa` (panic ID 10595).

Focused validation only:
- `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_num_wrapping_saturating_hash_one_macro_surface.sa --jobs 1 --trace-panic` -> `1 passed; 0 failed; 0 skipped`.

Panic IDs next free: 10596+.
Still blocked without redesign: trait-level `Hash` / `Hasher` / `BuildHasher`, generic primitive/container `Hash` impl dispatch, generic `Wrapping<T>` / `Saturating<T>`, additional wrapper widths not present in the current SA layouts, `u128` / `i128`, generic `NonZero<T>`, `Ipv6Addr` / `SocketAddrV6` `u128::from_ne_bytes` hashing, `IpAddr` / `SocketAddr` enum trait hashing, allocator/drop/borrow semantics, randomized `RandomState`, SipHash compatibility, Windows path prefixes/verbatim semantics, Rust platform encoding objects, true component iterator objects, Rust iterator trait hierarchy, generic `Try` residual/error object integration, generic `Option` / `Result` / `ControlFlow`, generic item/reference semantics, generic `FromIterator`, `IntoIterator`, true format!, Condvar/Barrier, process env maps/Stdio objects, and thread stack/name builder ABI.


## Active std parity batch (2026-07-15 CStr/CString hash_one)

Completed supportable `CStr` / `CString` hash macros:
- `DEFAULT_HASHER_WRITE_CSTR` / `CSTR_HASH`: concrete Rust derived `Hash for CStr` backing-byte shape for SA's borrowed C string view, by hashing `CSTR_TO_BYTES_WITH_NUL` through the existing deterministic `u8` slice hash path.
- `BUILD_HASHER_DEFAULT_HASH_ONE_CSTR` and `RANDOM_STATE_HASH_ONE_CSTR`: concrete `BuildHasher::hash_one` lowerings for the same borrowed C string subset.
- `DEFAULT_HASHER_WRITE_CSTRING` / `CSTRING_HASH`: concrete Rust derived `Hash for CString` backing-byte shape for SA's owned C string facade, by hashing `CSTRING_AS_BYTES_WITH_NUL` through the same slice path.
- `BUILD_HASHER_DEFAULT_HASH_ONE_CSTRING` and `RANDOM_STATE_HASH_ONE_CSTRING`: concrete `BuildHasher::hash_one` lowerings for the same owned C string subset.
- This follows Rust's current `CStr` derived `Hash` over its backing `[c_char]` and `CString` derived `Hash` over its backing `Box<[u8]>`, for SA's concrete bytes-with-trailing-NUL representation. It does not expose platform `c_char` signedness nuance, generic trait dispatch, allocator/drop/lifetime semantics, randomized `RandomState`, or SipHash compatibility.
- Test file `std_ffi_cstr_hash_one_macro_surface.sa` (panic ID 10594).

Focused validation only:
- `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_ffi_cstr_hash_one_macro_surface.sa --jobs 1 --trace-panic` -> `1 passed; 0 failed; 0 skipped`.

Panic IDs next free: 10595+.
Still blocked without redesign: trait-level `Hash` / `Hasher` / `BuildHasher`, generic primitive/container `Hash` impl dispatch, Rust platform `c_char` signedness and typed `[c_char]` hashing nuance beyond byte representation, allocator/drop/borrow semantics, randomized `RandomState`, SipHash compatibility, Windows path prefixes/verbatim semantics, Rust platform encoding objects, true component iterator objects, Rust iterator trait hierarchy, generic `Try` residual/error object integration, generic `Option` / `Result` / `ControlFlow`, generic item/reference semantics, generic `FromIterator`, `IntoIterator`, true format!, Condvar/Barrier, process env maps/Stdio objects, and thread stack/name builder ABI.


## Active std parity batch (2026-07-15 Instant/SystemTime hash_one)

Completed supportable `Instant` / `SystemTime` hash macros:
- `DEFAULT_HASHER_WRITE_UNIX_TIMESPEC_NS`: concrete Unix `Timespec` hashing shape for SA's existing non-negative nanosecond scalar time representation, by splitting `time_ns` into `tv_sec = ns / 1_000_000_000` and `tv_nsec = ns % 1_000_000_000`, then hashing `tv_sec` through `i64` and `tv_nsec` through `u32`.
- `DEFAULT_HASHER_WRITE_INSTANT` / `TIME_INSTANT_HASH` and `DEFAULT_HASHER_WRITE_SYSTEM_TIME` / `TIME_SYSTEM_TIME_HASH`: concrete Rust Unix `Hash` derived-field shape for SA `Instant` and `SystemTime` scalar facades.
- `BUILD_HASHER_DEFAULT_HASH_ONE_INSTANT`, `RANDOM_STATE_HASH_ONE_INSTANT`, `BUILD_HASHER_DEFAULT_HASH_ONE_SYSTEM_TIME`, and `RANDOM_STATE_HASH_ONE_SYSTEM_TIME`: concrete `BuildHasher::hash_one` lowerings for the same subset.
- This follows Rust's current Unix backend shape where `std::time::{Instant,SystemTime}` derive `Hash` through a `Timespec { tv_sec: i64, tv_nsec: Nanoseconds(u32) }`. It does not expose Rust's opaque/platform-varying time object storage, negative/pre-epoch `SystemTime`, monotonic clock guarantees, generic trait dispatch, randomized `RandomState`, or SipHash compatibility.
- Test file `std_time_instant_system_hash_one_macro_surface.sa` (panic ID 10593).

Focused validation only:
- `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_time_instant_system_hash_one_macro_surface.sa --jobs 1 --trace-panic` -> `1 passed; 0 failed; 0 skipped`.

Panic IDs next free: 10594+.
Still blocked without redesign: trait-level `Hash` / `Hasher` / `BuildHasher`, generic primitive/container `Hash` impl dispatch, Rust opaque/platform-varying `Instant` / `SystemTime` storage, negative/pre-epoch Unix `SystemTime`, non-Unix time hash storage, Rust typed two-field `Duration` storage and `Nanoseconds` niche type, `u128` / float / signed duration conversions, generic `NonZero<T>`, `u128` / `i128` and their NonZero variants, `Ipv6Addr` / `SocketAddrV6` `u128::from_ne_bytes` hashing, `IpAddr` / `SocketAddr` enum trait hashing, allocator/drop/borrow semantics, randomized `RandomState`, SipHash compatibility, Windows path prefixes/verbatim semantics, Rust platform encoding objects, true component iterator objects, Rust iterator trait hierarchy, generic `Try` residual/error object integration, generic `Option` / `Result` / `ControlFlow`, generic item/reference semantics, generic `FromIterator`, `IntoIterator`, true format!, Condvar/Barrier, process env maps/Stdio objects, and thread stack/name builder ABI.


## Active std parity batch (2026-07-15 Duration hash_one)

Completed supportable `Duration` hash macros:
- `DEFAULT_HASHER_WRITE_DURATION` / `TIME_DURATION_HASH`: concrete Rust `Hash for Duration` derived-field shape for SA's existing nanosecond scalar `Duration` representation, by splitting `duration_ns` into `secs = ns / 1_000_000_000` and `nanos = ns % 1_000_000_000`, then hashing `secs` through `u64` and `nanos` through `u32`.
- `BUILD_HASHER_DEFAULT_HASH_ONE_DURATION` and `RANDOM_STATE_HASH_ONE_DURATION`: concrete `BuildHasher::hash_one` lowerings for the same Duration subset.
- This follows Rust's current `core::time::Duration` derived `Hash` storage shape (`secs: u64`, `nanos: Nanoseconds(u32)`) for SA's concrete nanosecond value. It does not expose Rust's typed two-field `Duration` object, `Nanoseconds` niche type, `u128` duration constructors, generic trait dispatch, randomized `RandomState`, or SipHash compatibility.
- Test file `std_time_duration_hash_one_macro_surface.sa` (panic ID 10592).

Focused validation only:
- `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_time_duration_hash_one_macro_surface.sa --jobs 1 --trace-panic` -> `1 passed; 0 failed; 0 skipped`.

Panic IDs next free: 10593+.
Still blocked without redesign: trait-level `Hash` / `Hasher` / `BuildHasher`, generic primitive/container `Hash` impl dispatch, Rust typed two-field `Duration` storage and `Nanoseconds` niche type, `u128` / float / signed duration conversions, platform-specific `Instant` / `SystemTime` hash storage, generic `NonZero<T>`, `u128` / `i128` and their NonZero variants, `Ipv6Addr` / `SocketAddrV6` `u128::from_ne_bytes` hashing, `IpAddr` / `SocketAddr` enum trait hashing, allocator/drop/borrow semantics, randomized `RandomState`, SipHash compatibility, Windows path prefixes/verbatim semantics, Rust platform encoding objects, true component iterator objects, Rust iterator trait hierarchy, generic `Try` residual/error object integration, generic `Option` / `Result` / `ControlFlow`, generic item/reference semantics, generic `FromIterator`, `IntoIterator`, true format!, Condvar/Barrier, process env maps/Stdio objects, and thread stack/name builder ABI.


## Active std parity batch (2026-07-15 NonZero integer hash_one)

Completed supportable NonZero integer hash macros:
- `DEFAULT_HASHER_WRITE_NONZERO_{U8,U16,U32,U64,USIZE,I8,I16,I32,I64,ISIZE}` and matching `NONZERO_*_HASH`: concrete Rust `Hash for NonZero<T>` forwarding shape for SA's existing concrete NonZero integer layouts, by hashing `get()` through the matching primitive integer hash writer.
- `BUILD_HASHER_DEFAULT_HASH_ONE_NONZERO_*` and `RANDOM_STATE_HASH_ONE_NONZERO_*`: concrete `BuildHasher::hash_one` lowerings for the same NonZero integer subset.
- This follows Rust's generic `impl<T: Hash> Hash for NonZero<T>` implementation shape (`self.get().hash(state)`) for the concrete SA integer widths. It does not expose Rust's generic `NonZero<T>`, `u128` / `i128` nonzero integers, niche optimization semantics, generic trait dispatch, randomized `RandomState`, or SipHash compatibility.
- Test file `std_num_nonzero_hash_one_macro_surface.sa` (panic ID 10591).

Focused validation only:
- `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_num_nonzero_hash_one_macro_surface.sa --jobs 1 --trace-panic` -> `1 passed; 0 failed; 0 skipped`.

Panic IDs next free: 10592+.
Still blocked without redesign: trait-level `Hash` / `Hasher` / `BuildHasher`, generic primitive/container `Hash` impl dispatch, generic `NonZero<T>`, `u128` / `i128` and their NonZero variants, Rust niche optimization semantics, `Ipv6Addr` / `SocketAddrV6` `u128::from_ne_bytes` hashing, `IpAddr` / `SocketAddr` enum trait hashing, allocator/drop/borrow semantics, randomized `RandomState`, SipHash compatibility, Windows path prefixes/verbatim semantics, Rust platform encoding objects, true component iterator objects, Rust iterator trait hierarchy, generic `Try` residual/error object integration, generic `Option` / `Result` / `ControlFlow`, generic item/reference semantics, generic `FromIterator`, `IntoIterator`, true format!, Condvar/Barrier, process env maps/Stdio objects, and thread stack/name builder ABI.


## Active std parity batch (2026-07-15 SocketAddrV4 hash_one)

Completed supportable IPv4 socket-address hash macros:
- `DEFAULT_HASHER_WRITE_NET_SOCKET_ADDR_V4` / `NET_SOCKET_ADDR_V4_HASH`: concrete Rust derived `Hash for SocketAddrV4` shape for SA `NetSocketAddrV4`, by hashing the `ip` field through the existing `Ipv4Addr` hash path and then hashing the `port` field through the existing `u16` path.
- `BUILD_HASHER_DEFAULT_HASH_ONE_NET_SOCKET_ADDR_V4` and `RANDOM_STATE_HASH_ONE_NET_SOCKET_ADDR_V4`: concrete `BuildHasher::hash_one` lowerings for the same socket-address subset.
- This follows Rust's derived field order for `SocketAddrV4 { ip, port }`. It does not expose generic trait dispatch, randomized `RandomState`, SipHash compatibility, `SocketAddr` enum hashing, `SocketAddrV6` hashing, or IPv6 `u128` hashing.
- Test file `std_net_ip_hash_one_macro_surface.sa` (panic ID 10590).

Focused validation only:
- `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_net_ip_hash_one_macro_surface.sa --jobs 1 --trace-panic` -> `2 passed; 0 failed; 0 skipped`.

Panic IDs next free: 10591+.
Still blocked without redesign: trait-level `Hash` / `Hasher` / `BuildHasher`, generic primitive/container `Hash` impl dispatch, `Ipv6Addr` / `SocketAddrV6` `u128::from_ne_bytes` hashing, `IpAddr` / `SocketAddr` enum trait hashing, allocator/drop/borrow semantics, randomized `RandomState`, SipHash compatibility, Windows path prefixes/verbatim semantics, Rust platform encoding objects, true component iterator objects, Rust iterator trait hierarchy, generic `Try` residual/error object integration, generic `Option` / `Result` / `ControlFlow`, generic item/reference semantics, generic `FromIterator`, `IntoIterator`, true format!, Condvar/Barrier, process env maps/Stdio objects, and thread stack/name builder ABI.


## Active std parity batch (2026-07-15 Ipv4Addr hash_one)

Completed supportable IPv4 address hash macros:
- `DEFAULT_HASHER_WRITE_NET_IPV4` / `NET_IPV4_HASH`: concrete Rust `Hash for Ipv4Addr` shape for SA `NetIpv4Addr`, by loading the four octets as a native-endian `u32` and writing it through the existing `u32` hasher path.
- `BUILD_HASHER_DEFAULT_HASH_ONE_NET_IPV4` and `RANDOM_STATE_HASH_ONE_NET_IPV4`: concrete `BuildHasher::hash_one` lowerings for the same IPv4 address subset.
- This follows Rust's `Ipv4Addr` hash implementation for the current supportable target shape: `u32::from_ne_bytes(self.octets).hash(state)`. It intentionally differs from SA's network-order `NET_IPV4_TO_BITS` / `from_bits` helpers and does not expose generic trait dispatch, randomized `RandomState`, SipHash compatibility, `IpAddr` enum hashing, or IPv6 `u128` hashing.
- Test file `std_net_ip_hash_one_macro_surface.sa` (panic ID 10589).

Focused validation only:
- `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_net_ip_hash_one_macro_surface.sa --jobs 1 --trace-panic` -> `1 passed; 0 failed; 0 skipped`.

Panic IDs next free: 10590+.
Still blocked without redesign: trait-level `Hash` / `Hasher` / `BuildHasher`, generic primitive/container `Hash` impl dispatch, `Ipv6Addr` `u128::from_ne_bytes` hashing, `IpAddr` enum trait hashing, allocator/drop/borrow semantics, randomized `RandomState`, SipHash compatibility, Windows path prefixes/verbatim semantics, Rust platform encoding objects, true component iterator objects, Rust iterator trait hierarchy, generic `Try` residual/error object integration, generic `Option` / `Result` / `ControlFlow`, generic item/reference semantics, generic `FromIterator`, `IntoIterator`, true format!, Condvar/Barrier, process env maps/Stdio objects, and thread stack/name builder ABI.


## Active std parity batch (2026-07-15 Path hash_one)

Completed supportable POSIX Path hash macros:
- `DEFAULT_HASHER_WRITE_PATH` / `PATH_HASH`: concrete Rust `Hash for Path` shape for SA POSIX `Path` byte slices, by hashing normalized non-empty components with raw byte writes and a final `chunk_bits` `usize`.
- `BUILD_HASHER_DEFAULT_HASH_ONE_PATH` and `RANDOM_STATE_HASH_ONE_PATH`: concrete `BuildHasher::hash_one` lowerings for the same borrowed path subset.
- `DEFAULT_HASHER_WRITE_PATH_BUF` / `PATH_BUF_HASH`: concrete Rust `Hash for PathBuf` forwarding shape for SA `PathBuf`, by viewing the owned buffer as `Path`.
- `BUILD_HASHER_DEFAULT_HASH_ONE_PATH_BUF` and `RANDOM_STATE_HASH_ONE_PATH_BUF`: concrete `BuildHasher::hash_one` lowerings for the same owned path subset.
- This follows Rust's `Path` hash implementation for the supportable POSIX subset: repeated separators and ordinary `.` components are normalized away, component bytes are written without per-component length prefixes, and `chunk_bits` separates shapes such as `["foo", "bar"]` from `["foobar"]`. It does not expose Windows prefixes/verbatim paths, true component iterator objects, generic trait dispatch, randomized `RandomState`, or SipHash compatibility.
- Test file `std_path_hash_one_macro_surface.sa` (panic ID 10588).

Focused validation only:
- `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_path_hash_one_macro_surface.sa --jobs 1 --trace-panic` -> `1 passed; 0 failed; 0 skipped`.

Panic IDs next free: 10589+.
Still blocked without redesign: trait-level `Hash` / `Hasher` / `BuildHasher`, generic primitive/container `Hash` impl dispatch, Windows path prefixes/verbatim semantics, Rust platform encoding objects, true component iterator objects, allocator/drop/borrow semantics, randomized `RandomState`, SipHash compatibility, Rust iterator trait hierarchy, generic `Try` residual/error object integration, generic `Option` / `Result` / `ControlFlow`, generic item/reference semantics, generic `FromIterator`, `IntoIterator`, true format!, Condvar/Barrier, process env maps/Stdio objects, and thread stack/name builder ABI.


## Active std parity batch (2026-07-15 OsStr/OsString hash_one)

Completed supportable Unix platform-string hash macros:
- `DEFAULT_HASHER_WRITE_OS_STR` / `OS_STR_HASH`: concrete Rust `Hash for OsStr` shape for SA Unix `OsStr`, by hashing the encoded bytes through the existing `u8` slice hash path.
- `BUILD_HASHER_DEFAULT_HASH_ONE_OS_STR` and `RANDOM_STATE_HASH_ONE_OS_STR`: concrete `BuildHasher::hash_one` lowerings for the same borrowed platform-string subset.
- `DEFAULT_HASHER_WRITE_OS_STRING` / `OS_STRING_HASH`: concrete Rust `Hash for OsString` forwarding shape for SA Unix `OsString`, by viewing the owned bytes as `OsStr`.
- `BUILD_HASHER_DEFAULT_HASH_ONE_OS_STRING` and `RANDOM_STATE_HASH_ONE_OS_STRING`: concrete `BuildHasher::hash_one` lowerings for the same owned platform-string subset.
- This follows Rust's `OsStr` implementation by hashing `as_encoded_bytes()` and Rust's `OsString` implementation by forwarding to `OsStr`. It preserves non-UTF-8 bytes in the Unix byte facade and does not expose Windows WTF-8, generic trait dispatch, allocator/drop semantics, randomized `RandomState`, or SipHash compatibility.
- Test file `std_os_unix_ffi_hash_one_macro_surface.sa` (panic ID 10587).

Focused validation only:
- `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_os_unix_ffi_hash_one_macro_surface.sa --jobs 1 --trace-panic` -> `1 passed; 0 failed; 0 skipped`.

Panic IDs next free: 10588+.
Still blocked without redesign: trait-level `Hash` / `Hasher` / `BuildHasher`, generic primitive/container `Hash` impl dispatch, Windows WTF-8 platform strings, Rust platform encoding objects, allocator/drop/borrow semantics, randomized `RandomState`, SipHash compatibility, Rust iterator trait hierarchy, generic `Try` residual/error object integration, generic `Option` / `Result` / `ControlFlow`, generic item/reference semantics, generic `FromIterator`, `IntoIterator`, true format!, Condvar/Barrier, process env maps/Stdio objects, path component iterators, and thread stack/name builder ABI.


## Active std parity batch (2026-07-15 BTree str hash_one)

Completed supportable ordered BTree hash macros:
- `DEFAULT_HASHER_WRITE_BTREE_MAP_STR_U64` / `BTREE_MAP_HASH_STR_U64`: concrete Rust `Hash for BTreeMap<K, V>` shape for SA `BTreeMap<str, u64>`, by writing the map length prefix and then hashing sorted key/value entries in iteration order.
- `BUILD_HASHER_DEFAULT_HASH_ONE_BTREE_MAP_STR_U64` and `RANDOM_STATE_HASH_ONE_BTREE_MAP_STR_U64`: concrete `BuildHasher::hash_one` lowerings for the same map subset.
- `DEFAULT_HASHER_WRITE_BTREE_SET_STR` / `BTREE_SET_HASH_STR`: concrete Rust `Hash for BTreeSet<T>` shape for SA `BTreeSet<str>`, by writing the set length prefix and sorted keys in iteration order.
- `BUILD_HASHER_DEFAULT_HASH_ONE_BTREE_SET_STR` and `RANDOM_STATE_HASH_ONE_BTREE_SET_STR`: concrete `BuildHasher::hash_one` lowerings for the same set subset.
- This follows Rust's `BTreeMap` `Hash` implementation by hashing length then ordered iterator entries, and Rust's `BTreeSet` implementation by delegating to its backing map with a zero-sized set value. It does not expose generic `BTreeMap<K, V>` / `BTreeSet<T>`, allocator/node internals, lazy iterators, generic `Ord`, or SipHash compatibility.
- Test file `std_btree_hash_one_macro_surface.sa` (panic ID 10586).

Focused validation only:
- `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_btree_hash_one_macro_surface.sa --jobs 1 --trace-panic` -> `1 passed; 0 failed; 0 skipped`.

Panic IDs next free: 10587+.
Still blocked without redesign: trait-level `Hash` / `Hasher` / `BuildHasher`, generic primitive/container `Hash` impl dispatch, generic `BTreeMap<K, V>` / `BTreeSet<T>` trait wiring, allocator/drop/borrow semantics, Rust iterator trait hierarchy, randomized `RandomState`, SipHash compatibility, generic `Ord`, generic `Try` residual/error object integration, generic `Option` / `Result` / `ControlFlow`, generic item/reference semantics, generic `FromIterator`, `IntoIterator`, true format!, Condvar/Barrier, process env maps/Stdio objects, path component iterators, and thread stack/name builder ABI.


## Active std parity batch (2026-07-15 VecDeque u64 hash_one)

Completed supportable deque hash macros:
- `DEFAULT_HASHER_WRITE_VEC_DEQUE_U64`: concrete Rust `Hash for VecDeque<T>` shape for SA `VecDeque<u64>`, by forcing logical contents contiguous and writing the resulting slice through the existing `u64` slice hash path.
- `VEC_DEQUE_HASH_U64`: direct one-shot helper for the same concrete subset.
- `BUILD_HASHER_DEFAULT_HASH_ONE_VEC_DEQUE_U64` and `RANDOM_STATE_HASH_ONE_VEC_DEQUE_U64`: concrete `BuildHasher::hash_one` lowerings for `VecDeque<u64>` values.
- This follows Rust's `VecDeque` `Hash` implementation by hashing the deque length and then elements in logical front-to-back order. It intentionally avoids hashing the raw `as_slices` split because Rust documents that identical deques can have different split lengths.
- Test file `std_vec_deque_hash_one_macro_surface.sa` (panic ID 10585).

Focused validation only:
- `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_vec_deque_hash_one_macro_surface.sa --jobs 1 --trace-panic` -> `1 passed; 0 failed; 0 skipped`.

Panic IDs next free: 10586+.
Still blocked without redesign: trait-level `Hash` / `Hasher` / `BuildHasher`, generic primitive/container `Hash` impl dispatch, generic `VecDeque<T>` trait wiring, allocator/drop/borrow semantics, Rust iterator trait hierarchy, randomized `RandomState`, SipHash compatibility, const generics, generic `Try` residual/error object integration, generic `Option` / `Result` / `ControlFlow`, generic item/reference semantics, generic `FromIterator`, `IntoIterator`, true format!, Condvar/Barrier, process env maps/Stdio objects, path component iterators, and thread stack/name builder ABI.


## Active std parity batch (2026-07-15 Cow slice u64 hash_one)

Completed supportable clone-on-write slice hash macros:
- `DEFAULT_HASHER_WRITE_COW_SLICE_U64`: concrete Rust `Hash for Cow<'_, B>` forwarding shape for SA `CowSlice<u64>`, by viewing the Cow as a slice and writing it through the existing `u64` slice hash path.
- `COW_SLICE_HASH_U64`: direct one-shot helper for the same concrete subset.
- `BUILD_HASHER_DEFAULT_HASH_ONE_COW_SLICE_U64` and `RANDOM_STATE_HASH_ONE_COW_SLICE_U64`: concrete `BuildHasher::hash_one` lowerings for `CowSlice<u64>` values.
- This follows Rust's `Cow` `Hash` implementation by hashing `&**self`, without exposing generic `Cow<'a, B>`, clone-on-write allocation, `ToOwned`, lifetime semantics, or SipHash compatibility.
- Test file `std_cow_slice_hash_one_macro_surface.sa` (panic ID 10584).

Focused validation only:
- `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_cow_slice_hash_one_macro_surface.sa --jobs 1 --trace-panic` -> `1 passed; 0 failed; 0 skipped`.

Panic IDs next free: 10585+.
Still blocked without redesign: trait-level `Hash` / `Hasher` / `BuildHasher`, generic primitive/container `Hash` impl dispatch, generic `Cow<'a, B>` / `ToOwned` trait wiring, clone-on-write allocation/cloning, Rust lifetime/borrow integration, unsized pointer metadata hashing, `u128` / `i128` hasher write support, generic `RandomState` collection integration, real randomized SipHash keys, Rust `HashMap` trait wiring, real Rust iterator trait hierarchy, generic `Try` residual/error object integration, generic `Option` / `Result` / `ControlFlow`, generic item/reference semantics, generic `FromIterator`, `IntoIterator`, true format!, Condvar/Barrier, process env maps/Stdio objects, path component iterators, and thread stack/name builder ABI.


## Active std parity batch (2026-07-15 Vec u64 hash_one)

Completed supportable owned vector hash macros:
- `DEFAULT_HASHER_WRITE_VEC_U64`: concrete Rust `Hash for Vec<T>` forwarding shape for SA `Vec<u64>`, by viewing the owned vector as a slice and writing it through the existing `u64` slice hash path.
- `BUILD_HASHER_DEFAULT_HASH_ONE_VEC_U64` and `RANDOM_STATE_HASH_ONE_VEC_U64`: concrete `BuildHasher::hash_one` lowerings for owned `Vec<u64>` values.
- This follows Rust's `Vec<T>` `Hash` implementation by hashing `&**self`, without exposing generic `Vec<T>` trait dispatch, allocator parameters, Rust ownership/drop semantics, or SipHash compatibility.
- Test file `std_vec_hash_one_macro_surface.sa` (panic ID 10583).

Focused validation only:
- `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_vec_hash_one_macro_surface.sa --jobs 1 --trace-panic` -> `1 passed; 0 failed; 0 skipped`.

Panic IDs next free: 10584+.
Still blocked without redesign: trait-level `Hash` / `Hasher` / `BuildHasher`, generic primitive/container `Hash` impl dispatch, generic `Vec<T>` trait wiring, allocator-aware variants, Rust `Vec` ownership/drop integration, unsized pointer metadata hashing, `u128` / `i128` hasher write support, generic `RandomState` collection integration, real randomized SipHash keys, Rust `HashMap` trait wiring, real Rust iterator trait hierarchy, generic `Try` residual/error object integration, generic `Option` / `Result` / `ControlFlow`, generic item/reference semantics, generic `FromIterator`, `IntoIterator`, true format!, Condvar/Barrier, process env maps/Stdio objects, path component iterators, and thread stack/name builder ABI.


## Active std parity batch (2026-07-15 StringBuf hash_one)

Completed supportable owned string hash macros:
- `DEFAULT_HASHER_WRITE_STRING_BUF`: concrete Rust `Hash for String` forwarding shape for SA `StringBuf`, by viewing the owned buffer as `str` and writing it through the existing string hash path.
- `BUILD_HASHER_DEFAULT_HASH_ONE_STRING_BUF` and `RANDOM_STATE_HASH_ONE_STRING_BUF`: concrete `BuildHasher::hash_one` lowerings for owned `StringBuf` values.
- This follows Rust's `String` `Hash` implementation by hashing `**self`, without exposing generic `Hash` trait dispatch, allocator parameters, Rust `String` drop semantics, or SipHash compatibility.
- Test file `std_string_buf_hash_one_macro_surface.sa` (panic ID 10582).

Focused validation only:
- `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_string_buf_hash_one_macro_surface.sa --jobs 1 --trace-panic` -> `1 passed; 0 failed; 0 skipped`.

Panic IDs next free: 10583+.
Still blocked without redesign: trait-level `Hash` / `Hasher` / `BuildHasher`, generic primitive/container `Hash` impl dispatch, generic `String` / `Vec<T>` trait wiring, allocator-aware variants, Rust `String` ownership/drop integration, unsized pointer metadata hashing, `u128` / `i128` hasher write support, generic `RandomState` collection integration, real randomized SipHash keys, Rust `HashMap` trait wiring, real Rust iterator trait hierarchy, generic `Try` residual/error object integration, generic `Option` / `Result` / `ControlFlow`, generic item/reference semantics, generic `FromIterator`, `IntoIterator`, true format!, Condvar/Barrier, process env maps/Stdio objects, path component iterators, and thread stack/name builder ABI.


## Active std parity batch (2026-07-15 hash rc arc u64)

Completed supportable reference-counted value hash macros:
- `DEFAULT_HASHER_WRITE_RC_U64` / `DEFAULT_HASHER_WRITE_ARC_U64`: concrete Rust `Hash for Rc<T>` / `Hash for Arc<T>` forwarding shapes for `Rc<u64>` and `Arc<u64>` payloads, by loading the stored value and writing it through the existing `u64` path.
- `HASH_RC_U64` / `HASH_ARC_U64`: direct one-shot helpers for the same concrete subsets.
- `BUILD_HASHER_DEFAULT_HASH_ONE_RC_U64` / `ARC_U64` and `RANDOM_STATE_HASH_ONE_RC_U64` / `ARC_U64`: concrete `BuildHasher::hash_one` lowerings for reference-counted `u64` values.
- This follows Rust's `Rc<T>` / `Arc<T>` `Hash` implementations by hashing `**self`, without exposing generic `Rc<T>` / `Arc<T>`, allocator parameters, weak pointer hashing, unsized metadata, drop glue, or thread-safety semantics beyond the existing concrete Arc payload.
- Test file `std_hash_rc_arc_u64_macro_surface.sa` (panic ID 10581).

Focused validation only:
- `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_hash_rc_arc_u64_macro_surface.sa --jobs 1 --trace-panic` -> `1 passed; 0 failed; 0 skipped`.

Panic IDs next free: 10582+.
Still blocked without redesign: trait-level `Hash` / `Hasher` / `BuildHasher`, generic primitive/container `Hash` impl dispatch, generic `Rc<T>` / `Arc<T>` and allocator-aware variants, weak pointer hashing semantics, boxed/reference-counted `Hasher` trait forwarding, unsized pointer metadata hashing, `u128` / `i128` hasher write support, generic `RandomState` collection integration, real randomized SipHash keys, Rust `HashMap` trait wiring, real Rust iterator trait hierarchy, generic `Try` residual/error object integration, generic `Option` / `Result` / `ControlFlow`, generic item/reference semantics, generic `FromIterator`, `IntoIterator`, true format!, Condvar/Barrier, process env maps/Stdio objects, path component iterators, and thread stack/name builder ABI.


## Active std parity batch (2026-07-15 hash box u64)

Completed supportable boxed value hash macros:
- `DEFAULT_HASHER_WRITE_BOX_U64`: concrete Rust `Hash for Box<T>` forwarding shape for a `Box<u64>` payload, by loading the boxed value and writing it through the existing `u64` path.
- `HASH_BOX_U64`: direct one-shot helper for the same concrete `Box<u64>` subset.
- `BUILD_HASHER_DEFAULT_HASH_ONE_BOX_U64` and `RANDOM_STATE_HASH_ONE_BOX_U64`: concrete `BuildHasher::hash_one` lowerings for boxed `u64` values.
- This follows Rust's `Box<T>` `Hash` implementation by hashing `**self`, without exposing generic `Box<T>`, allocator parameters, unsized metadata, drop glue, or boxed `Hasher` trait forwarding.
- Test file `std_hash_box_u64_macro_surface.sa` (panic ID 10580).

Focused validation only:
- `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_hash_box_u64_macro_surface.sa --jobs 1 --trace-panic` -> `1 passed; 0 failed; 0 skipped`.

Panic IDs next free: 10581+.
Still blocked without redesign: trait-level `Hash` / `Hasher` / `BuildHasher`, generic primitive/container `Hash` impl dispatch, generic `Box<T>` and allocator-aware `Box<T, A>`, boxed `Hasher` trait forwarding, unsized pointer metadata hashing, `u128` / `i128` hasher write support, generic `RandomState` collection integration, real randomized SipHash keys, Rust `HashMap` trait wiring, real Rust iterator trait hierarchy, generic `Try` residual/error object integration, generic `Option` / `Result` / `ControlFlow`, generic item/reference semantics, generic `FromIterator`, `IntoIterator`, true format!, Condvar/Barrier, process env maps/Stdio objects, path component iterators, and thread stack/name builder ABI.


## Active std parity batch (2026-07-15 array hash_one u64)

Completed supportable array hash_one macros:
- `BUILD_HASHER_DEFAULT_HASH_ONE_ARRAY_U64`: concrete `BuildHasher::hash_one` lowering for a caller-provided `u64` array pointer and length.
- `RANDOM_STATE_HASH_ONE_ARRAY_U64`: concrete `RandomState::hash_one` lowering for the same `u64` array subset.
- These mirror Rust's `Hash for [T; N]` shape by hashing the array through the slice hashing path, matching the existing `ARRAY_HASH_U64` / `DEFAULT_HASHER_WRITE_ARRAY_U64` surface.
- Test file `std_array_hash_one_macro_surface.sa` (panic ID 10579).

Focused validation only:
- `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_array_hash_one_macro_surface.sa --jobs 1 --trace-panic` -> `1 passed; 0 failed; 0 skipped`.

Panic IDs next free: 10580+.
Still blocked without redesign: trait-level `Hash` / `Hasher` / `BuildHasher`, generic primitive/container `Hash` impl dispatch, generic arrays and const-generic trait dispatch beyond concrete `u64` pointer/length lowering, generic reference forwarding beyond concrete `u64` pointers, unsized pointer metadata hashing, `u128` / `i128` hasher write support, generic `RandomState` collection integration, real randomized SipHash keys, Rust `HashMap` trait wiring, real Rust iterator trait hierarchy, generic `Try` residual/error object integration, generic `Option` / `Result` / `ControlFlow`, generic item/reference semantics, generic `FromIterator`, `IntoIterator`, true format!, Condvar/Barrier, process env maps/Stdio objects, path component iterators, and thread stack/name builder ABI.


## Active std parity batch (2026-07-15 hash const ptr)

Completed supportable const raw pointer hash macros:
- `DEFAULT_HASHER_WRITE_CONST_PTR`: concrete Rust `Hash for *const T` sized-pointer lowering alias over the existing pointer-address writer.
- `HASH_CONST_PTR_VALUE`: direct one-shot helper for a sized const raw pointer value.
- `BUILD_HASHER_DEFAULT_HASH_ONE_CONST_PTR_VALUE` and `RANDOM_STATE_HASH_ONE_CONST_PTR_VALUE`: concrete `BuildHasher::hash_one` lowerings for the same const raw pointer subset.
- This mirrors Rust's `*const T` raw-pointer `Hash` shape for sized pointees by hashing the address and applying the same unit metadata no-op used by the existing pointer hash-one helper. It does not expose unsized pointer metadata hashing, provenance/lifetime semantics, or generic raw-pointer trait dispatch.
- Test file `std_hash_const_ptr_macro_surface.sa` (panic ID 10578).

Focused validation only:
- `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_hash_const_ptr_macro_surface.sa --jobs 1 --trace-panic` -> `1 passed; 0 failed; 0 skipped`.

Panic IDs next free: 10579+.
Still blocked without redesign: trait-level `Hash` / `Hasher` / `BuildHasher`, generic primitive/container `Hash` impl dispatch, generic reference forwarding beyond concrete `u64` pointers, unsized pointer metadata hashing, `u128` / `i128` hasher write support, generic `RandomState` collection integration, real randomized SipHash keys, Rust `HashMap` trait wiring, real Rust iterator trait hierarchy, generic `Try` residual/error object integration, generic `Option` / `Result` / `ControlFlow`, generic item/reference semantics, generic `FromIterator`, `IntoIterator`, true format!, Condvar/Barrier, process env maps/Stdio objects, path component iterators, and thread stack/name builder ABI.


## Active std parity batch (2026-07-15 hash mut ptr)

Completed supportable mutable raw pointer hash macros:
- `DEFAULT_HASHER_WRITE_MUT_PTR`: concrete Rust `Hash for *mut T` sized-pointer lowering alias over the existing pointer-address writer.
- `HASH_MUT_PTR_VALUE`: direct one-shot helper for a sized mutable raw pointer value.
- `BUILD_HASHER_DEFAULT_HASH_ONE_MUT_PTR_VALUE` and `RANDOM_STATE_HASH_ONE_MUT_PTR_VALUE`: concrete `BuildHasher::hash_one` lowerings for the same mutable raw pointer subset.
- This mirrors Rust's `*mut T` raw-pointer `Hash` shape for sized pointees by hashing the address and applying the same unit metadata no-op used by the existing pointer hash-one helper. It does not expose unsized pointer metadata hashing, provenance/lifetime semantics, or generic raw-pointer trait dispatch.
- Test file `std_hash_mut_ptr_macro_surface.sa` (panic ID 10577).

Focused validation only:
- `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_hash_mut_ptr_macro_surface.sa --jobs 1 --trace-panic` -> `1 passed; 0 failed; 0 skipped`.

Panic IDs next free: 10578+.
Still blocked without redesign: trait-level `Hash` / `Hasher` / `BuildHasher`, generic primitive/container `Hash` impl dispatch, generic reference forwarding beyond concrete `u64` pointers, unsized pointer metadata hashing, `u128` / `i128` hasher write support, generic `RandomState` collection integration, real randomized SipHash keys, Rust `HashMap` trait wiring, real Rust iterator trait hierarchy, generic `Try` residual/error object integration, generic `Option` / `Result` / `ControlFlow`, generic item/reference semantics, generic `FromIterator`, `IntoIterator`, true format!, Condvar/Barrier, process env maps/Stdio objects, path component iterators, and thread stack/name builder ABI.


## Active std parity batch (2026-07-15 hash ref u64)

Completed supportable reference forwarding hash macros:
- `DEFAULT_HASHER_WRITE_REF_U64` and `DEFAULT_HASHER_WRITE_REF_MUT_U64`: concrete Rust `Hash for &T` / `Hash for &mut T` forwarding shape for a `u64` pointee, by loading the referenced value and writing it through the existing `u64` path.
- `HASH_REF_U64` and `HASH_REF_MUT_U64`: direct one-shot helpers for concrete `u64` references.
- `BUILD_HASHER_DEFAULT_HASH_ONE_REF_U64` / `REF_MUT_U64` and `RANDOM_STATE_HASH_ONE_REF_U64` / `REF_MUT_U64`: concrete `BuildHasher::hash_one` lowerings for the same reference subset.
- This follows Rust's reference `Hash` forwarding implementation for one supportable concrete pointee shape, without exposing generic reference trait dispatch, borrow/lifetime semantics, or unsized pointee metadata.
- Test file `std_hash_ref_u64_macro_surface.sa` (panic ID 10576).

Focused validation only:
- `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_hash_ref_u64_macro_surface.sa --jobs 1 --trace-panic` -> `1 passed; 0 failed; 0 skipped`.

Panic IDs next free: 10577+.
Still blocked without redesign: trait-level `Hash` / `Hasher` / `BuildHasher`, generic primitive/container `Hash` impl dispatch, generic reference forwarding beyond concrete `u64` pointers, unsized pointer metadata hashing, `u128` / `i128` hasher write support, generic `RandomState` collection integration, real randomized SipHash keys, Rust `HashMap` trait wiring, real Rust iterator trait hierarchy, generic `Try` residual/error object integration, generic `Option` / `Result` / `ControlFlow`, generic item/reference semantics, generic `FromIterator`, `IntoIterator`, true format!, Condvar/Barrier, process env maps/Stdio objects, path component iterators, and thread stack/name builder ABI.


## Active std parity batch (2026-07-15 hash tuple12 u64)

Completed supportable tuple hash macros:
- `DEFAULT_HASHER_WRITE_TUPLE12_U64`: concrete `(u64, u64, u64, u64, u64, u64, u64, u64, u64, u64, u64, u64)` tuple `Hash` lowering that writes the twelve fields in order through the existing `write_u64` path.
- `HASH_TUPLE12_U64`: direct one-shot helper for a concrete twelve-`u64` tuple.
- `BUILD_HASHER_DEFAULT_HASH_ONE_TUPLE12_U64` and `RANDOM_STATE_HASH_ONE_TUPLE12_U64`: concrete `BuildHasher::hash_one` lowerings for the same tuple subset.
- This reaches Rust's current tuple `Hash` arity ceiling for one supportable concrete `u64` shape, without exposing generic tuple trait impls or non-`u64` elements.
- Test file `std_hash_tuple12_u64_macro_surface.sa` (panic ID 10575).

Focused validation only:
- `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_hash_tuple12_u64_macro_surface.sa --jobs 1 --trace-panic` -> `1 passed; 0 failed; 0 skipped`.

Panic IDs next free: 10576+.
Still blocked without redesign: trait-level `Hash` / `Hasher` / `BuildHasher`, generic primitive/container `Hash` impl dispatch, generic tuple `Hash` up to twelve elements, unsized pointer metadata hashing, reference forwarding, `u128` / `i128` hasher write support, generic `RandomState` collection integration, real randomized SipHash keys, Rust `HashMap` trait wiring, real Rust iterator trait hierarchy, generic `Try` residual/error object integration, generic `Option` / `Result` / `ControlFlow`, generic item/reference semantics, generic `FromIterator`, `IntoIterator`, true format!, Condvar/Barrier, process env maps/Stdio objects, path component iterators, and thread stack/name builder ABI.


## Active std parity batch (2026-07-15 hash tuple11 u64)

Completed supportable tuple hash macros:
- `DEFAULT_HASHER_WRITE_TUPLE11_U64`: concrete `(u64, u64, u64, u64, u64, u64, u64, u64, u64, u64, u64)` tuple `Hash` lowering that writes the eleven fields in order through the existing `write_u64` path.
- `HASH_TUPLE11_U64`: direct one-shot helper for a concrete eleven-`u64` tuple.
- `BUILD_HASHER_DEFAULT_HASH_ONE_TUPLE11_U64` and `RANDOM_STATE_HASH_ONE_TUPLE11_U64`: concrete `BuildHasher::hash_one` lowerings for the same tuple subset.
- This continues Rust tuple `Hash` field-order dispatch coverage for one supportable concrete shape, without exposing generic tuple trait impls, tuple arities beyond the concrete helpers, or non-`u64` elements.
- Test file `std_hash_tuple11_u64_macro_surface.sa` (panic ID 10574).

Focused validation only:
- `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_hash_tuple11_u64_macro_surface.sa --jobs 1 --trace-panic` -> `1 passed; 0 failed; 0 skipped`.

Panic IDs next free: 10575+.
Still blocked without redesign: trait-level `Hash` / `Hasher` / `BuildHasher`, generic primitive/container `Hash` impl dispatch, generic tuple `Hash` up to twelve elements, unsized pointer metadata hashing, reference forwarding, `u128` / `i128` hasher write support, generic `RandomState` collection integration, real randomized SipHash keys, Rust `HashMap` trait wiring, real Rust iterator trait hierarchy, generic `Try` residual/error object integration, generic `Option` / `Result` / `ControlFlow`, generic item/reference semantics, generic `FromIterator`, `IntoIterator`, true format!, Condvar/Barrier, process env maps/Stdio objects, path component iterators, and thread stack/name builder ABI.


## Active std parity batch (2026-07-15 hash tuple10 u64)

Completed supportable tuple hash macros:
- `DEFAULT_HASHER_WRITE_TUPLE10_U64`: concrete `(u64, u64, u64, u64, u64, u64, u64, u64, u64, u64)` tuple `Hash` lowering that writes the ten fields in order through the existing `write_u64` path.
- `HASH_TUPLE10_U64`: direct one-shot helper for a concrete ten-`u64` tuple.
- `BUILD_HASHER_DEFAULT_HASH_ONE_TUPLE10_U64` and `RANDOM_STATE_HASH_ONE_TUPLE10_U64`: concrete `BuildHasher::hash_one` lowerings for the same tuple subset.
- This continues Rust tuple `Hash` field-order dispatch coverage for one supportable concrete shape, without exposing generic tuple trait impls, tuple arities beyond the concrete helpers, or non-`u64` elements.
- Test file `std_hash_tuple10_u64_macro_surface.sa` (panic ID 10573).

Focused validation only:
- `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_hash_tuple10_u64_macro_surface.sa --jobs 1 --trace-panic` -> `1 passed; 0 failed; 0 skipped`.

Panic IDs next free: 10574+.
Still blocked without redesign: trait-level `Hash` / `Hasher` / `BuildHasher`, generic primitive/container `Hash` impl dispatch, generic tuple `Hash` up to twelve elements, unsized pointer metadata hashing, reference forwarding, `u128` / `i128` hasher write support, generic `RandomState` collection integration, real randomized SipHash keys, Rust `HashMap` trait wiring, real Rust iterator trait hierarchy, generic `Try` residual/error object integration, generic `Option` / `Result` / `ControlFlow`, generic item/reference semantics, generic `FromIterator`, `IntoIterator`, true format!, Condvar/Barrier, process env maps/Stdio objects, path component iterators, and thread stack/name builder ABI.


## Active std parity batch (2026-07-15 hash tuple9 u64)

Completed supportable tuple hash macros:
- `DEFAULT_HASHER_WRITE_TUPLE9_U64`: concrete `(u64, u64, u64, u64, u64, u64, u64, u64, u64)` tuple `Hash` lowering that writes the nine fields in order through the existing `write_u64` path.
- `HASH_TUPLE9_U64`: direct one-shot helper for a concrete nine-`u64` tuple.
- `BUILD_HASHER_DEFAULT_HASH_ONE_TUPLE9_U64` and `RANDOM_STATE_HASH_ONE_TUPLE9_U64`: concrete `BuildHasher::hash_one` lowerings for the same tuple subset.
- This continues Rust tuple `Hash` field-order dispatch coverage for one supportable concrete shape, without exposing generic tuple trait impls, tuple arities beyond the concrete helpers, or non-`u64` elements.
- Test file `std_hash_tuple9_u64_macro_surface.sa` (panic ID 10572).

Focused validation only:
- `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_hash_tuple9_u64_macro_surface.sa --jobs 1 --trace-panic` -> `1 passed; 0 failed; 0 skipped`.

Panic IDs next free: 10573+.
Still blocked without redesign: trait-level `Hash` / `Hasher` / `BuildHasher`, generic primitive/container `Hash` impl dispatch, generic tuple `Hash` up to twelve elements, unsized pointer metadata hashing, reference forwarding, `u128` / `i128` hasher write support, generic `RandomState` collection integration, real randomized SipHash keys, Rust `HashMap` trait wiring, real Rust iterator trait hierarchy, generic `Try` residual/error object integration, generic `Option` / `Result` / `ControlFlow`, generic item/reference semantics, generic `FromIterator`, `IntoIterator`, true format!, Condvar/Barrier, process env maps/Stdio objects, path component iterators, and thread stack/name builder ABI.


## Active std parity batch (2026-07-15 hash tuple8 u64)

Completed supportable tuple hash macros:
- `DEFAULT_HASHER_WRITE_TUPLE8_U64`: concrete `(u64, u64, u64, u64, u64, u64, u64, u64)` tuple `Hash` lowering that writes the eight fields in order through the existing `write_u64` path.
- `HASH_TUPLE8_U64`: direct one-shot helper for a concrete eight-`u64` tuple.
- `BUILD_HASHER_DEFAULT_HASH_ONE_TUPLE8_U64` and `RANDOM_STATE_HASH_ONE_TUPLE8_U64`: concrete `BuildHasher::hash_one` lowerings for the same tuple subset.
- This continues Rust tuple `Hash` field-order dispatch coverage for one supportable concrete shape, without exposing generic tuple trait impls, tuple arities beyond the concrete helpers, or non-`u64` elements.
- Test file `std_hash_tuple8_u64_macro_surface.sa` (panic ID 10571).

Focused validation only:
- `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_hash_tuple8_u64_macro_surface.sa --jobs 1 --trace-panic` -> `1 passed; 0 failed; 0 skipped`.

Panic IDs next free: 10572+.
Still blocked without redesign: trait-level `Hash` / `Hasher` / `BuildHasher`, generic primitive/container `Hash` impl dispatch, generic tuple `Hash` up to twelve elements, unsized pointer metadata hashing, reference forwarding, `u128` / `i128` hasher write support, generic `RandomState` collection integration, real randomized SipHash keys, Rust `HashMap` trait wiring, real Rust iterator trait hierarchy, generic `Try` residual/error object integration, generic `Option` / `Result` / `ControlFlow`, generic item/reference semantics, generic `FromIterator`, `IntoIterator`, true format!, Condvar/Barrier, process env maps/Stdio objects, path component iterators, and thread stack/name builder ABI.


## Active std parity batch (2026-07-15 hash tuple7 u64)

Completed supportable tuple hash macros:
- `DEFAULT_HASHER_WRITE_TUPLE7_U64`: concrete `(u64, u64, u64, u64, u64, u64, u64)` tuple `Hash` lowering that writes the seven fields in order through the existing `write_u64` path.
- `HASH_TUPLE7_U64`: direct one-shot helper for a concrete seven-`u64` tuple.
- `BUILD_HASHER_DEFAULT_HASH_ONE_TUPLE7_U64` and `RANDOM_STATE_HASH_ONE_TUPLE7_U64`: concrete `BuildHasher::hash_one` lowerings for the same tuple subset.
- This continues Rust tuple `Hash` field-order dispatch coverage for one supportable concrete shape, without exposing generic tuple trait impls, tuple arities beyond the concrete helpers, or non-`u64` elements.
- Test file `std_hash_tuple7_u64_macro_surface.sa` (panic ID 10570).

Focused validation only:
- `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_hash_tuple7_u64_macro_surface.sa --jobs 1 --trace-panic` -> `1 passed; 0 failed; 0 skipped`.

Panic IDs next free: 10571+.
Still blocked without redesign: trait-level `Hash` / `Hasher` / `BuildHasher`, generic primitive/container `Hash` impl dispatch, generic tuple `Hash` up to twelve elements, unsized pointer metadata hashing, reference forwarding, `u128` / `i128` hasher write support, generic `RandomState` collection integration, real randomized SipHash keys, Rust `HashMap` trait wiring, real Rust iterator trait hierarchy, generic `Try` residual/error object integration, generic `Option` / `Result` / `ControlFlow`, generic item/reference semantics, generic `FromIterator`, `IntoIterator`, true format!, Condvar/Barrier, process env maps/Stdio objects, path component iterators, and thread stack/name builder ABI.


## Active std parity batch (2026-07-15 hash tuple6 u64)

Completed supportable tuple hash macros:
- `DEFAULT_HASHER_WRITE_TUPLE6_U64`: concrete `(u64, u64, u64, u64, u64, u64)` tuple `Hash` lowering that writes the six fields in order through the existing `write_u64` path.
- `HASH_TUPLE6_U64`: direct one-shot helper for a concrete six-`u64` tuple.
- `BUILD_HASHER_DEFAULT_HASH_ONE_TUPLE6_U64` and `RANDOM_STATE_HASH_ONE_TUPLE6_U64`: concrete `BuildHasher::hash_one` lowerings for the same tuple subset.
- This continues Rust tuple `Hash` field-order dispatch coverage for one supportable concrete shape, without exposing generic tuple trait impls, tuple arities beyond the concrete helpers, or non-`u64` elements.
- Test file `std_hash_tuple6_u64_macro_surface.sa` (panic ID 10569).

Focused validation only:
- `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_hash_tuple6_u64_macro_surface.sa --jobs 1 --trace-panic` -> `1 passed; 0 failed; 0 skipped`.

Panic IDs next free: 10570+.
Still blocked without redesign: trait-level `Hash` / `Hasher` / `BuildHasher`, generic primitive/container `Hash` impl dispatch, generic tuple `Hash` up to twelve elements, unsized pointer metadata hashing, reference forwarding, `u128` / `i128` hasher write support, generic `RandomState` collection integration, real randomized SipHash keys, Rust `HashMap` trait wiring, real Rust iterator trait hierarchy, generic `Try` residual/error object integration, generic `Option` / `Result` / `ControlFlow`, generic item/reference semantics, generic `FromIterator`, `IntoIterator`, true format!, Condvar/Barrier, process env maps/Stdio objects, path component iterators, and thread stack/name builder ABI.


## Active std parity batch (2026-07-15 hash tuple5 u64)

Completed supportable tuple hash macros:
- `DEFAULT_HASHER_WRITE_TUPLE5_U64`: concrete `(u64, u64, u64, u64, u64)` tuple `Hash` lowering that writes the five fields in order through the existing `write_u64` path.
- `HASH_TUPLE5_U64`: direct one-shot helper for a concrete five-`u64` tuple.
- `BUILD_HASHER_DEFAULT_HASH_ONE_TUPLE5_U64` and `RANDOM_STATE_HASH_ONE_TUPLE5_U64`: concrete `BuildHasher::hash_one` lowerings for the same tuple subset.
- This continues Rust tuple `Hash` field-order dispatch coverage for one supportable concrete shape, without exposing generic tuple trait impls, tuple arities beyond the concrete helpers, or non-`u64` elements.
- Test file `std_hash_tuple5_u64_macro_surface.sa` (panic ID 10568).

Focused validation only:
- `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_hash_tuple5_u64_macro_surface.sa --jobs 1 --trace-panic` -> `1 passed; 0 failed; 0 skipped`.

Panic IDs next free: 10569+.
Still blocked without redesign: trait-level `Hash` / `Hasher` / `BuildHasher`, generic primitive/container `Hash` impl dispatch, generic tuple `Hash` up to twelve elements, unsized pointer metadata hashing, reference forwarding, `u128` / `i128` hasher write support, generic `RandomState` collection integration, real randomized SipHash keys, Rust `HashMap` trait wiring, real Rust iterator trait hierarchy, generic `Try` residual/error object integration, generic `Option` / `Result` / `ControlFlow`, generic item/reference semantics, generic `FromIterator`, `IntoIterator`, true format!, Condvar/Barrier, process env maps/Stdio objects, path component iterators, and thread stack/name builder ABI.


## Active std parity batch (2026-07-15 hash tuple4 u64)

Completed supportable tuple hash macros:
- `DEFAULT_HASHER_WRITE_TUPLE4_U64`: concrete `(u64, u64, u64, u64)` tuple `Hash` lowering that writes the four fields in order through the existing `write_u64` path.
- `HASH_TUPLE4_U64`: direct one-shot helper for a concrete four-`u64` tuple.
- `BUILD_HASHER_DEFAULT_HASH_ONE_TUPLE4_U64` and `RANDOM_STATE_HASH_ONE_TUPLE4_U64`: concrete `BuildHasher::hash_one` lowerings for the same tuple subset.
- This continues Rust tuple `Hash` field-order dispatch coverage for one supportable concrete shape, without exposing generic tuple trait impls, tuple arities beyond the concrete helpers, or non-`u64` elements.
- Test file `std_hash_tuple4_u64_macro_surface.sa` (panic ID 10567).

Focused validation only:
- `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_hash_tuple4_u64_macro_surface.sa --jobs 1 --trace-panic` -> `1 passed; 0 failed; 0 skipped`.

Panic IDs next free: 10568+.
Still blocked without redesign: trait-level `Hash` / `Hasher` / `BuildHasher`, generic primitive/container `Hash` impl dispatch, generic tuple `Hash` up to twelve elements, unsized pointer metadata hashing, reference forwarding, `u128` / `i128` hasher write support, generic `RandomState` collection integration, real randomized SipHash keys, Rust `HashMap` trait wiring, real Rust iterator trait hierarchy, generic `Try` residual/error object integration, generic `Option` / `Result` / `ControlFlow`, generic item/reference semantics, generic `FromIterator`, `IntoIterator`, true format!, Condvar/Barrier, process env maps/Stdio objects, path component iterators, and thread stack/name builder ABI.


## Active std parity batch (2026-07-15 hash tuple3 u64)

Completed supportable tuple hash macros:
- `DEFAULT_HASHER_WRITE_TUPLE3_U64`: concrete `(u64, u64, u64)` tuple `Hash` lowering that writes the three fields in order through the existing `write_u64` path.
- `HASH_TUPLE3_U64`: direct one-shot helper for a concrete three-`u64` tuple.
- `BUILD_HASHER_DEFAULT_HASH_ONE_TUPLE3_U64` and `RANDOM_STATE_HASH_ONE_TUPLE3_U64`: concrete `BuildHasher::hash_one` lowerings for the same tuple subset.
- This continues Rust tuple `Hash` field-order dispatch coverage for one supportable concrete shape, without exposing generic tuple trait impls, tuple arities beyond the concrete helpers, or non-`u64` elements.
- Test file `std_hash_tuple3_u64_macro_surface.sa` (panic ID 10566).

Focused validation only:
- `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_hash_tuple3_u64_macro_surface.sa --jobs 1 --trace-panic` -> `1 passed; 0 failed; 0 skipped`.

Panic IDs next free: 10567+.
Still blocked without redesign: trait-level `Hash` / `Hasher` / `BuildHasher`, generic primitive/container `Hash` impl dispatch, generic tuple `Hash` up to twelve elements, unsized pointer metadata hashing, reference forwarding, `u128` / `i128` hasher write support, generic `RandomState` collection integration, real randomized SipHash keys, Rust `HashMap` trait wiring, real Rust iterator trait hierarchy, generic `Try` residual/error object integration, generic `Option` / `Result` / `ControlFlow`, generic item/reference semantics, generic `FromIterator`, `IntoIterator`, true format!, Condvar/Barrier, process env maps/Stdio objects, path component iterators, and thread stack/name builder ABI.


## Active std parity batch (2026-07-15 hash tuple2 u64)

Completed supportable tuple hash macros:
- `DEFAULT_HASHER_WRITE_TUPLE2_U64`: concrete `(u64, u64)` tuple `Hash` lowering that writes the two fields in order through the existing `write_u64` path.
- `HASH_TUPLE2_U64`: direct one-shot helper for a concrete two-`u64` tuple.
- `BUILD_HASHER_DEFAULT_HASH_ONE_TUPLE2_U64` and `RANDOM_STATE_HASH_ONE_TUPLE2_U64`: concrete `BuildHasher::hash_one` lowerings for the same tuple subset.
- This mirrors Rust tuple `Hash` field-order dispatch for one supportable concrete shape, without exposing generic tuple trait impls, tuple arities beyond two, or non-`u64` elements.
- Test file `std_hash_tuple2_u64_macro_surface.sa` (panic ID 10565).

Focused validation only:
- `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_hash_tuple2_u64_macro_surface.sa --jobs 1 --trace-panic` -> `1 passed; 0 failed; 0 skipped`.

Panic IDs next free: 10566+.
Still blocked without redesign: trait-level `Hash` / `Hasher` / `BuildHasher`, generic primitive/container `Hash` impl dispatch, generic tuple `Hash` up to twelve elements, unsized pointer metadata hashing, reference forwarding, `u128` / `i128` hasher write support, generic `RandomState` collection integration, real randomized SipHash keys, Rust `HashMap` trait wiring, real Rust iterator trait hierarchy, generic `Try` residual/error object integration, generic `Option` / `Result` / `ControlFlow`, generic item/reference semantics, generic `FromIterator`, `IntoIterator`, true format!, Condvar/Barrier, process env maps/Stdio objects, path component iterators, and thread stack/name builder ABI.


## Active std parity batch (2026-07-15 hash_one pointer)

Completed supportable pointer `hash_one` macros:
- `BUILD_HASHER_DEFAULT_HASH_ONE_PTR_VALUE`: concrete `BuildHasher::hash_one` lowering for sized raw pointer values over the deterministic `BuildHasherDefault<DefaultHasher>` facade.
- `RANDOM_STATE_HASH_ONE_PTR_VALUE`: concrete `RandomState::hash_one` lowering for sized raw pointer values over the existing seeded deterministic `RandomState` facade.
- The helper writes the pointer address through `DEFAULT_HASHER_WRITE_PTR` and then applies the unit metadata no-op used by sized pointer `Hash` lowering; it does not model unsized pointer metadata or reference forwarding.
- Test file `std_hash_ptr_hash_one_macro_surface.sa` (panic ID 10564).

Focused validation only:
- `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_hash_ptr_hash_one_macro_surface.sa --jobs 1 --trace-panic` -> `1 passed; 0 failed; 0 skipped`.

Panic IDs next free: 10565+.
Still blocked without redesign: trait-level `Hash` / `Hasher` / `BuildHasher`, generic primitive/container `Hash` impl dispatch, tuple `Hash`, unsized pointer metadata hashing, reference forwarding, `u128` / `i128` hasher write support, generic `RandomState` collection integration, real randomized SipHash keys, Rust `HashMap` trait wiring, real Rust iterator trait hierarchy, generic `Try` residual/error object integration, generic `Option` / `Result` / `ControlFlow`, generic item/reference semantics, generic `FromIterator`, `IntoIterator`, true format!, Condvar/Barrier, process env maps/Stdio objects, path component iterators, and thread stack/name builder ABI.


## Active std parity batch (2026-07-15 hash unit)

Completed supportable unit hash macros:
- `DEFAULT_HASHER_WRITE_UNIT`: concrete no-op writer for Rust `Hash for ()`, taking an ignored placeholder unit value to fit SA macro invocation syntax.
- `HASH_UNIT`: direct one-shot hash helper for unit, finishing a fresh deterministic `DefaultHasher` without changing state.
- `BUILD_HASHER_DEFAULT_HASH_ONE_UNIT` and `RANDOM_STATE_HASH_ONE_UNIT`: concrete Rust `BuildHasher::hash_one(())` lowering over the existing deterministic builder surfaces.
- Test file `std_hash_unit_macro_surface.sa` (panic ID 10563).

Focused validation only:
- `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_hash_unit_macro_surface.sa --jobs 1 --trace-panic` -> `1 passed; 0 failed; 0 skipped`.

Panic IDs next free: 10564+.
Still blocked without redesign: trait-level `Hash` / `Hasher` / `BuildHasher`, generic primitive/container `Hash` impl dispatch, tuple `Hash`, `u128` / `i128` hasher write support, generic `RandomState` collection integration, real randomized SipHash keys, Rust `HashMap` trait wiring, real Rust iterator trait hierarchy, generic `Try` residual/error object integration, generic `Option` / `Result` / `ControlFlow`, generic item/reference semantics, generic `FromIterator`, `IntoIterator`, true format!, Condvar/Barrier, process env maps/Stdio objects, path component iterators, and thread stack/name builder ABI.


## Active std parity batch (2026-07-15 hash_one bool/char)

Completed supportable bool/char `hash_one` macros:
- `BUILD_HASHER_DEFAULT_HASH_ONE_BOOL` and `BUILD_HASHER_DEFAULT_HASH_ONE_CHAR`: concrete Rust `BuildHasher::hash_one` lowering over the deterministic `BuildHasherDefault<DefaultHasher>` facade.
- `RANDOM_STATE_HASH_ONE_BOOL` and `RANDOM_STATE_HASH_ONE_CHAR`: concrete Rust `RandomState::hash_one` lowering over the existing seeded deterministic `RandomState` facade.
- `BOOL` preserves the existing nonzero-to-true normalization for frontend-lowered booleans, and `CHAR` forwards a frontend-provided scalar through the existing `write_char` / `write_u32` path.
- Test file `std_hash_bool_char_hash_one_macro_surface.sa` (panic ID 10562).

Focused validation only:
- `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_hash_bool_char_hash_one_macro_surface.sa --jobs 1 --trace-panic` -> `1 passed; 0 failed; 0 skipped`.

Panic IDs next free: 10563+.
Still blocked without redesign: trait-level `Hash` / `Hasher` / `BuildHasher`, generic primitive/container `Hash` impl dispatch, `u128` / `i128` hasher write support, generic `RandomState` collection integration, real randomized SipHash keys, Rust `HashMap` trait wiring, real Rust iterator trait hierarchy, generic `Try` residual/error object integration, generic `Option` / `Result` / `ControlFlow`, generic item/reference semantics, generic `FromIterator`, `IntoIterator`, true format!, Condvar/Barrier, process env maps/Stdio objects, path component iterators, and thread stack/name builder ABI.


## Active std parity batch (2026-07-15 hash_one integer primitives)

Completed supportable integer primitive `hash_one` macros:
- `BUILD_HASHER_DEFAULT_HASH_ONE_U8`, `U16`, `U32`, `USIZE`, `I8`, `I16`, `I32`, `I64`, and `ISIZE`: concrete Rust `BuildHasher::hash_one` lowering over the deterministic `BuildHasherDefault<DefaultHasher>` facade.
- `RANDOM_STATE_HASH_ONE_U8`, `U16`, `U32`, `USIZE`, `I8`, `I16`, `I32`, `I64`, and `ISIZE`: concrete Rust `RandomState::hash_one` lowering over the existing seeded deterministic `RandomState` facade.
- This extends the existing `hash_one` surface from `u64` / `str` / slices to the supportable integer primitive writers, without exposing generic `Hash`, `u128` / `i128`, OS-random `RandomState`, collection integration, or SipHash-compatible output.
- Test file `std_hash_builder_integer_hash_one_macro_surface.sa` (panic ID 10561).

Focused validation only:
- `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_hash_builder_integer_hash_one_macro_surface.sa --jobs 1 --trace-panic` -> `1 passed; 0 failed; 0 skipped`.

Panic IDs next free: 10562+.
Still blocked without redesign: trait-level `Hash` / `Hasher` / `BuildHasher`, generic primitive/container `Hash` impl dispatch, `u128` / `i128` hasher write support, generic `RandomState` collection integration, real randomized SipHash keys, Rust `HashMap` trait wiring, real Rust iterator trait hierarchy, generic `Try` residual/error object integration, generic `Option` / `Result` / `ControlFlow`, generic item/reference semantics, generic `FromIterator`, `IntoIterator`, true format!, Condvar/Barrier, process env maps/Stdio objects, path component iterators, and thread stack/name builder ABI.


## Active std parity batch (2026-07-15 hash integer primitives)

Completed supportable integer primitive hash macros:
- `HASH_U8`, `HASH_U16`, `HASH_U32`: direct one-shot hash helpers for Rust unsigned primitive `Hash` lowering over the existing `DEFAULT_HASHER_WRITE_U*` paths.
- `HASH_I8`, `HASH_I16`, `HASH_I32`, `HASH_I64`, `HASH_ISIZE`: direct one-shot hash helpers for Rust signed primitive `Hash` lowering over the existing `DEFAULT_HASHER_WRITE_I*` / `WRITE_ISIZE` paths.
- This mirrors Rust's primitive `impl_write!` `Hash` dispatch shape for the supported deterministic SA hasher surface, without exposing generic `Hash` dispatch, endian-exact byte serialization, `u128` / `i128`, or SipHash-compatible output.
- Test file `std_hash_integer_primitives_macro_surface.sa` (panic ID 10560).

Focused validation only:
- `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_hash_integer_primitives_macro_surface.sa --jobs 1 --trace-panic` -> `1 passed; 0 failed; 0 skipped`.

Panic IDs next free: 10561+.
Still blocked without redesign: trait-level `Hash` / `Hasher` / `BuildHasher`, generic primitive/container `Hash` impl dispatch, `u128` / `i128` hasher write support, generic `RandomState` collection integration, real randomized SipHash keys, Rust `HashMap` trait wiring, real Rust iterator trait hierarchy, generic `Try` residual/error object integration, generic `Option` / `Result` / `ControlFlow`, generic item/reference semantics, generic `FromIterator`, `IntoIterator`, true format!, Condvar/Barrier, process env maps/Stdio objects, path component iterators, and thread stack/name builder ABI.


## Active std parity batch (2026-07-15 hash usize)

Completed supportable usize hash macro:
- `HASH_USIZE`: direct one-shot hash helper for Rust `usize` lowering over the existing `DEFAULT_HASHER_WRITE_USIZE` path.
- In this SA subset `write_usize` delegates to the current register-sized deterministic `u64` writer, matching the platform-width lowering contract already used by `DEFAULT_HASHER_WRITE_USIZE`.
- This mirrors Rust's primitive `Hash for usize` dispatch shape for the supported deterministic SA hasher surface, without exposing generic `Hash` dispatch, endian-exact byte serialization, or SipHash-compatible output.
- Test file `std_hash_usize_macro_surface.sa` (panic ID 10559).

Focused validation only:
- `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_hash_usize_macro_surface.sa --jobs 1 --trace-panic` -> `1 passed; 0 failed; 0 skipped`.

Panic IDs next free: 10560+.
Still blocked without redesign: trait-level `Hash` / `Hasher` / `BuildHasher`, generic primitive/container `Hash` impl dispatch, generic `RandomState` collection integration, real randomized SipHash keys, Rust `HashMap` trait wiring, real Rust iterator trait hierarchy, generic `Try` residual/error object integration, generic `Option` / `Result` / `ControlFlow`, generic item/reference semantics, generic `FromIterator`, `IntoIterator`, true format!, Condvar/Barrier, process env maps/Stdio objects, path component iterators, and thread stack/name builder ABI.


## Active std parity batch (2026-07-14 hash bool)

Completed supportable bool hash macro:
- `HASH_BOOL`: direct one-shot hash helper for Rust `bool` lowering over the existing `DEFAULT_HASHER_WRITE_BOOL` path.
- The helper normalizes nonzero inputs to true, matching the existing concrete bool writer contract for frontend-lowered booleans.
- This mirrors Rust's `impl Hash for bool { state.write_u8(*self as u8) }` shape for the supported deterministic SA hasher surface, without exposing generic `Hash` dispatch or SipHash-compatible output.
- Test file `std_hash_bool_macro_surface.sa` (panic ID 10558).

Focused validation only:
- `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_hash_bool_macro_surface.sa --jobs 1 --trace-panic` -> `1 passed; 0 failed; 0 skipped`.

Panic IDs next free: 10559+.
Still blocked without redesign: trait-level `Hash` / `Hasher` / `BuildHasher`, generic primitive/container `Hash` impl dispatch, generic `RandomState` collection integration, real randomized SipHash keys, Rust `HashMap` trait wiring, real Rust iterator trait hierarchy, generic `Try` residual/error object integration, generic `Option` / `Result` / `ControlFlow`, generic item/reference semantics, generic `FromIterator`, `IntoIterator`, true format!, Condvar/Barrier, process env maps/Stdio objects, path component iterators, and thread stack/name builder ABI.


## Active std parity batch (2026-07-14 hash char)

Completed supportable char hash macro:
- `DEFAULT_HASHER_WRITE_CHAR`: concrete `Hash for char` lowering that writes the scalar value through the existing `write_u32` path.
- `HASH_CHAR`: direct one-shot hash helper for a concrete character scalar.
- This mirrors Rust's `impl Hash for char { state.write_u32(*self as u32) }` shape for valid frontend-provided scalar values; it does not validate scalar ranges, expose generic `Hash`, or provide SipHash-compatible output.
- Test file `std_hash_char_macro_surface.sa` (panic ID 10557).

Focused validation only:
- `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_hash_char_macro_surface.sa --jobs 1 --trace-panic` -> `1 passed; 0 failed; 0 skipped`.

Panic IDs next free: 10558+.
Still blocked without redesign: trait-level `Hash` / `Hasher` / `BuildHasher`, generic primitive/container `Hash` impl dispatch, generic `RandomState` collection integration, real randomized SipHash keys, Rust `HashMap` trait wiring, real Rust iterator trait hierarchy, generic `Try` residual/error object integration, generic `Option` / `Result` / `ControlFlow`, generic item/reference semantics, generic `FromIterator`, `IntoIterator`, true format!, Condvar/Barrier, process env maps/Stdio objects, path component iterators, and thread stack/name builder ABI.


## Active std parity batch (2026-07-14 hash Hasher write)

Completed supportable Hasher write macro:
- `DEFAULT_HASHER_WRITE`: Rust-named `Hasher::write(&[u8])` lowering over SA's concrete `Slice<u8>` view.
- The macro delegates to the existing byte-slice state update path, intentionally without length-prefixing; callers that need prefix-free sequence hashing continue to use `DEFAULT_HASHER_WRITE_LENGTH_PREFIX` or the slice helpers.
- This is a concrete lowering surface only; it does not expose trait dispatch, Rust generic `Hash`, endian-exact primitive byte serialization, or SipHash output compatibility.
- Test file `std_hash_default_hasher_write_macro_surface.sa` (panic ID 10556).

Focused validation only:
- `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_hash_default_hasher_write_macro_surface.sa --jobs 1 --trace-panic` -> `1 passed; 0 failed; 0 skipped`.

Panic IDs next free: 10557+.
Still blocked without redesign: trait-level `Hash` / `Hasher` / `BuildHasher`, generic `RandomState` collection integration, real randomized SipHash keys, Rust `HashMap` trait wiring, real Rust iterator trait hierarchy, generic `Try` residual/error object integration, generic `Option` / `Result` / `ControlFlow`, generic item/reference semantics, generic `FromIterator`, `IntoIterator`, true format!, Condvar/Barrier, process env maps/Stdio objects, path component iterators, and thread stack/name builder ABI.


## Active std parity batch (2026-07-14 hash DefaultHasher clone)

Completed supportable DefaultHasher clone macro:
- `DEFAULT_HASHER_CLONE`: concrete `std::hash::DefaultHasher: Clone` lowering over SA's deterministic single-word hasher state.
- Cloning copies the current state into a distinct hasher object; later writes to either clone proceed independently, and writing the same value after cloning yields the same finished hash.
- This is a concrete lowering surface only; it does not expose Rust's hidden SipHasher state, `Debug` formatting, trait dispatch, or SipHash output compatibility.
- Test file `std_hash_default_hasher_clone_macro_surface.sa` (panic ID 10555).

Focused validation only:
- `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_hash_default_hasher_clone_macro_surface.sa --jobs 1 --trace-panic` -> `1 passed; 0 failed; 0 skipped`.

Panic IDs next free: 10556+.
Still blocked without redesign: trait-level `Hash` / `Hasher` / `BuildHasher`, generic `RandomState` collection integration, real randomized SipHash keys, Rust `HashMap` trait wiring, real Rust iterator trait hierarchy, generic `Try` residual/error object integration, generic `Option` / `Result` / `ControlFlow`, generic item/reference semantics, generic `FromIterator`, `IntoIterator`, true format!, Condvar/Barrier, process env maps/Stdio objects, path component iterators, and thread stack/name builder ABI.


## Active std parity batch (2026-07-14 hash RandomState)

Completed supportable RandomState macro surface:
- `RandomState` layout plus `RANDOM_STATE_NEW`, `RANDOM_STATE_DEFAULT`, `RANDOM_STATE_WITH_SEEDS`, `RANDOM_STATE_CLONE`, `RANDOM_STATE_BUILD`, and concrete `RANDOM_STATE_HASH_ONE_*` helpers for `u64`, `str`, `Slice<u8>`, and `Slice<u64>`.
- The macros model Rust's `RandomState` / `BuildHasher` shape over the existing deterministic SA `DefaultHasher`: cloned states build equivalent hashers, explicit seed pairs can build distinct hashers, and `hash_one` builds a fresh hasher, writes one concrete value, then finishes.
- This is a concrete lowering surface only; it does not expose OS randomness, Rust's per-thread randomized key evolution, SipHash output compatibility, generic `Hash`, or collection trait integration.
- Test file `std_hash_random_state_macro_surface.sa` (panic ID 10554).

Focused validation only:
- `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_hash_random_state_macro_surface.sa --jobs 1 --trace-panic` -> `1 passed; 0 failed; 0 skipped`.

Panic IDs next free: 10555+.
Still blocked without redesign: trait-level `Hash` / `Hasher` / `BuildHasher`, generic `RandomState` collection integration, real randomized SipHash keys, Rust `HashMap` trait wiring, real Rust iterator trait hierarchy, generic `Try` residual/error object integration, generic `Option` / `Result` / `ControlFlow`, generic item/reference semantics, generic `FromIterator`, `IntoIterator`, true format!, Condvar/Barrier, process env maps/Stdio objects, path component iterators, and thread stack/name builder ABI.


## Active std parity batch (2026-07-14 iter try_collect)

Completed supportable iterator try_collect macro:
- `ITER_TRY_COLLECT_U64`: concrete unstable Rust `Iterator::try_collect::<Vec<_>>()` shape over the slice-backed `u64` cursor.
- The macro uses a concrete `(value, out_value_ptr) -> ok` callback to model the supported part of `Try::branch`: successes are mapped into a `Vec<u64>`, the first failure is consumed and returns `ok=0`, and any later suffix remains available on the source cursor.
- This is a concrete lowering surface only; it does not expose Rust's generic `Try`, `Residual`, `ChangeOutputType`, outer `Option`/`Result`/`ControlFlow` objects, or generic `FromIterator`.
- Test file `std_iter_try_collect_macro_surface.sa` (panic ID 10553).

Focused validation only:
- `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_iter_try_collect_macro_surface.sa --jobs 1 --trace-panic` -> `1 passed; 0 failed; 0 skipped`.

Panic IDs next free: 10554+.
Still blocked without redesign: real Rust iterator trait hierarchy, generic `Try` residual/error object integration, `ChangeOutputType`, generic `Option` / `Result` / `ControlFlow`, generic item/reference semantics, generic `FromIterator`, `IntoIterator`, true format!, Condvar/Barrier, process env maps/Stdio objects, path component iterators, and thread stack/name builder ABI.


## Active std parity batch (2026-07-14 iter partition_in_place)

Completed supportable iterator partition_in_place macro:
- `ITER_PARTITION_IN_PLACE_U64`: concrete unstable Rust `Iterator::partition_in_place` shape over the slice-backed `u64` cursor's current mutable remaining window.
- The macro follows Rust's current swap-based partition shape: find the first predicate-false value from the front, find a predicate-true value from the back, swap them, and return the true partition length. It marks the source cursor consumed and does not preserve relative order.
- This is a concrete lowering surface only; it does not expose borrow-scoped `iter_mut`, `DoubleEndedIterator<Item = &mut T>` trait machinery, generic references, closure capture, or Rust panic/drop behavior around predicate calls.
- Test file `std_iter_partition_in_place_macro_surface.sa` (panic ID 10552).

Focused validation only:
- `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_iter_partition_in_place_macro_surface.sa --jobs 1 --trace-panic` -> `1 passed; 0 failed; 0 skipped`.

Panic IDs next free: 10553+.
Still blocked without redesign: real Rust iterator trait hierarchy, borrow-scoped mutable references, `DoubleEndedIterator<Item = &mut T>` semantics, generic item/reference semantics, generic closure capture, exact panic/drop behavior, generic `collect`, `IntoIterator`, true format!, Condvar/Barrier, process env maps/Stdio objects, path component iterators, and thread stack/name builder ABI.


## Active std parity batch (2026-07-14 iter map_windows collect)

Completed supportable iterator map_windows collect macro:
- `ITER_MAP_WINDOWS_COLLECT_U64`: concrete unstable Rust `Iterator::map_windows(...).collect::<Vec<_>>()` shape over the slice-backed `u64` cursor.
- The macro calls a concrete `(window_ptr, window_len) -> u64` mapper for each overlapping window and materializes mapped values into `Vec<u64>`. For nonzero window sizes it consumes the source cursor, including the short-input case that produces no mapped values; for zero window size it reports `ok=0` without consumption.
- This is a concrete lowering surface only; it does not expose a lazy `MapWindows` adapter object, const-generic array references, generic closure capture, non-fused resume-after-None behavior, or generic item/reference semantics.
- Test file `std_iter_map_windows_macro_surface.sa` (panic ID 10551).

Focused validation only:
- `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_iter_map_windows_macro_surface.sa --jobs 1 --trace-panic` -> `1 passed; 0 failed; 0 skipped`.

Panic IDs next free: 10552+.
Still blocked without redesign: real Rust iterator trait hierarchy, lazy `MapWindows` adapter identity, const-generic array reference returns, non-fused iterator resume-after-None state reset, generic item/reference semantics, generic closure capture, generic `collect`, `IntoIterator`, true format!, Condvar/Barrier, process env maps/Stdio objects, path component iterators, and thread stack/name builder ABI.


## Active std parity batch (2026-07-14 iter array_chunks collect)

Completed supportable iterator array_chunks collect macro:
- `ITER_ARRAY_CHUNKS_COLLECT_U64`: concrete Rust `Iterator::array_chunks::<N>().collect::<Vec<_>>()` shape over the slice-backed `u64` cursor.
- The macro materializes complete non-overlapping chunks into a flat `Vec<u64>` (`[1,2,3,4,5]` with chunk size 2 becomes `[1,2,3,4]`), reports `ok=0` without consumption for zero chunk size, and leaves any incomplete nonzero tail available in the source cursor.
- This is a concrete lowering surface only; it does not expose a lazy `ArrayChunks` adapter object, const-generic array item values, `IntoIter` remainder objects, or generic item/reference semantics.
- Test file `std_iter_array_chunks_macro_surface.sa` (panic ID 10550).

Focused validation only:
- `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_iter_array_chunks_macro_surface.sa --jobs 1 --trace-panic` -> `1 passed; 0 failed; 0 skipped`.

Panic IDs next free: 10551+.
Still blocked without redesign: real Rust iterator trait hierarchy, lazy `ArrayChunks` adapter identity, const-generic array item returns, Rust `into_remainder` object semantics, generic item/reference semantics, generic `collect`, `IntoIterator`, true format!, Condvar/Barrier, process env maps/Stdio objects, path component iterators, and thread stack/name builder ABI.


## Active std parity batch (2026-07-14 iter peekable)

Completed supportable iterator peekable macros:
- `ITER_TRY_PEEK_U64`: concrete `Peekable::peek`-style non-consuming peek over the slice-backed `u64` cursor, returning `(has, value)` instead of Rust `Option<&Item>`.
- `ITER_PEEKABLE_COLLECT_U64`: concrete Rust `Iterator::peekable().collect::<Vec<_>>()` shape over the same finite cursor.
- These macros expose the supportable behavior without introducing a lazy `Peekable` adapter object or reference lifetimes.
- Test file `std_iter_peekable_macro_surface.sa` (panic ID 10549).

Focused validation only:
- `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_iter_peekable_macro_surface.sa --jobs 1 --trace-panic` -> `1 passed; 0 failed; 0 skipped`.

Panic IDs next free: 10550+.
Still blocked without redesign: real Rust iterator trait hierarchy, lazy `Peekable` adapter identity, reference-returning `peek()` lifetime semantics, `peek_mut`, generic item/reference semantics, generic `collect`, `IntoIterator`, true format!, Condvar/Barrier, process env maps/Stdio objects, path component iterators, and thread stack/name builder ABI.


## Active std parity batch (2026-07-14 iter fuse collect)

Completed supportable iterator fuse collect macro:
- `ITER_FUSE_COLLECT_U64`: concrete Rust `Iterator::fuse().collect::<Vec<_>>()` shape over the finite slice-backed `u64` cursor.
- The macro delegates to `ITER_COLLECT_U64` because this cursor already has fused exhaustion behavior: after collection drains it, later `ITER_NEXT_U64` calls keep returning none-style `(has=0, value=0)`.
- Test file `std_iter_fuse_collect_macro_surface.sa` (panic ID 10548).

Focused validation only:
- `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_iter_fuse_collect_macro_surface.sa --jobs 1 --trace-panic` -> `1 passed; 0 failed; 0 skipped`.

Panic IDs next free: 10549+.
Still blocked without redesign: real Rust iterator trait hierarchy, lazy `Fuse` adapter identity, non-fused source iterator wrapping semantics, generic item/reference semantics, generic `collect`, `IntoIterator`, true format!, Condvar/Barrier, process env maps/Stdio objects, path component iterators, and thread stack/name builder ABI.


## Active std parity batch (2026-07-14 iter by_ref collect)

Completed supportable iterator by-ref collect macro:
- `ITER_BY_REF_COLLECT_U64`: concrete Rust `Iterator::by_ref().collect::<Vec<_>>()` shape over the slice-backed `u64` cursor.
- The macro delegates through `ITER_BY_REF` before collection, preserving the existing alias contract: the borrowed alias mutates the original cursor, while a prior `ITER_CLONE` remains independent.
- Test file `std_iter_by_ref_collect_macro_surface.sa` (panic ID 10547).

Focused validation only:
- `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_iter_by_ref_collect_macro_surface.sa --jobs 1 --trace-panic` -> `1 passed; 0 failed; 0 skipped`.

Panic IDs next free: 10548+.
Still blocked without redesign: real Rust iterator trait hierarchy, borrow/lifetime-checked `&mut self` semantics, generic item/reference semantics, generic `collect`, `IntoIterator`, lazy adapter identities, true format!, Condvar/Barrier, process env maps/Stdio objects, path component iterators, and thread stack/name builder ABI.


## Active std parity batch (2026-07-14 iter try_find)

Completed supportable iterator try-find macro:
- `ITER_TRY_FIND_U64`: concrete unstable Rust `Iterator::try_find` shape over the slice-backed `u64` cursor.
- The macro takes a concrete `(value, out_match_ptr) -> ok` callback, returns `(ok, has, value)`, reports callback failure as `ok=0`, reports successful miss as `ok=1, has=0`, consumes the matching or failing item, and preserves later suffix elements.
- Test file `std_iter_try_find_macro_surface.sa` (panic ID 10546).

Focused validation only:
- `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_iter_try_find_macro_surface.sa --jobs 1 --trace-panic` -> `1 passed; 0 failed; 0 skipped`.

Panic IDs next free: 10547+.
Still blocked without redesign: real Rust iterator trait hierarchy, generic `Try` residual/error object integration, generic `Option` / `Result`, generic item/reference semantics, generic `collect`, `IntoIterator`, true format!, Condvar/Barrier, process env maps/Stdio objects, path component iterators, and thread stack/name builder ABI.


## Active std parity batch (2026-07-14 iter comparator-by)

Completed supportable iterator comparator-by macros:
- `ITER_CMP_BY_U64`: concrete unstable Rust `Iterator::cmp_by` shape over two slice-backed `u64` cursors.
- `ITER_PARTIAL_CMP_BY_U64`: concrete unstable Rust `Iterator::partial_cmp_by` shape returning `(ok, ordering)` instead of Rust `Option<Ordering>`.
- `ITER_EQ_BY_U64`: concrete unstable Rust `Iterator::eq_by` shape over two slice-backed `u64` cursors.
- The macros preserve the existing lexicographic consumption model: compared pairs are consumed until a non-equal/None/mismatch/end result is determined, and suffix after a short-circuit remains available.
- Test file `std_iter_compare_by_macro_surface.sa` (panic ID 10545).

Focused validation only:
- `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_iter_compare_by_macro_surface.sa --jobs 1 --trace-panic` -> `1 passed; 0 failed; 0 skipped`.

Panic IDs next free: 10546+.
Still blocked without redesign: real Rust iterator trait hierarchy, generic item/reference semantics, generic `Option` / `Ordering` object integration, `IntoIterator`, true lazy adapters, generic `collect`, true format!, Condvar/Barrier, process env maps/Stdio objects, path component iterators, and thread stack/name builder ABI.


## Active std parity batch (2026-07-14 iter try_reduce)

Completed supportable iterator try-reduce macro:
- `ITER_TRY_REDUCE_U64`: concrete unstable Rust `Iterator::try_reduce` shape over the slice-backed `u64` cursor.
- The macro takes a concrete `(acc, value, out_next_ptr) -> ok` callback, uses the first remaining item as the accumulator, returns `(ok, has, value)`, reports empty input as success with `has=0`, and preserves suffix elements after the first failing item.
- Test file `std_iter_try_reduce_macro_surface.sa` (panic ID 10544).

Focused validation only:
- `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_iter_try_reduce_macro_surface.sa --jobs 1 --trace-panic` -> `1 passed; 0 failed; 0 skipped`.

Panic IDs next free: 10545+.
Still blocked without redesign: real Rust iterator trait hierarchy, generic `Try` residual/error object integration, generic `Option` / `Result`, generic item/reference semantics, generic `collect`, `IntoIterator`, true format!, Condvar/Barrier, process env maps/Stdio objects, path component iterators, and thread stack/name builder ABI.


## Active std parity batch (2026-07-14 iter intersperse collect)

Completed supportable iterator intersperse collect macros:
- `ITER_INTERSPERSE_COLLECT_U64`: concrete unstable Rust `Iterator::intersperse(separator).collect::<Vec<_>>()` lowering over the slice-backed `u64` cursor.
- `ITER_INTERSPERSE_WITH_COLLECT_U64`: concrete unstable Rust `Iterator::intersperse_with(separator_fn).collect::<Vec<_>>()` lowering where the separator callback is called once per gap.
- The macros materialize the first item, then separator/item pairs for later items, and do not call the separator callback for empty or single-item inputs.
- Test file `std_iter_intersperse_macro_surface.sa` (panic ID 10543).

Focused validation only:
- `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_iter_intersperse_macro_surface.sa --jobs 1 --trace-panic` -> `1 passed; 0 failed; 0 skipped`.

Panic IDs next free: 10544+.
Still blocked without redesign: real Rust iterator trait hierarchy, lazy `Intersperse` / `IntersperseWith` adapter identity, non-fused iterator resume-after-None semantics, generic `Clone` / closure state, generic item/reference semantics, generic `collect`, `IntoIterator`, true format!, Condvar/Barrier, process env maps/Stdio objects, path component iterators, and thread stack/name builder ABI.


## Active std parity batch (2026-07-14 iter cycle take collect)

Completed supportable bounded iterator cycle/take collect macro:
- `ITER_CYCLE_TAKE_COLLECT_U64`: concrete Rust `Iterator::cycle().take(n).collect::<Vec<_>>()` lowering over the slice-backed `u64` cursor.
- The macro uses the cursor's current remaining window as the cycle seed, materializes exactly `%count` values for nonempty input, returns an empty Vec for empty input or zero count, and marks the source cursor consumed only when a nonzero bounded cycle is materialized.
- Test file `std_iter_cycle_take_macro_surface.sa` (panic ID 10542).

Focused validation only:
- `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_iter_cycle_take_macro_surface.sa --jobs 1 --trace-panic` -> `1 passed; 0 failed; 0 skipped`.

Panic IDs next free: 10543+.
Still blocked without redesign: real Rust iterator trait hierarchy, lazy `Cycle` adapter identity, infinite iterator semantics beyond explicit bounded `take`, generic cloneable iterator state, generic item/reference semantics, generic `collect`, `IntoIterator`, true format!, Condvar/Barrier, process env maps/Stdio objects, path component iterators, and thread stack/name builder ABI.


## Active std parity batch (2026-07-14 iter copied/cloned collect)

Completed supportable iterator copied/cloned collect aliases:
- `ITER_COPIED_COLLECT_U64`: concrete Rust `Iterator::copied().collect::<Vec<_>>()` lowering over the slice-backed `u64` cursor.
- `ITER_CLONED_COLLECT_U64`: concrete Rust `Iterator::cloned().collect::<Vec<_>>()` lowering over the same value-copy subset.
- These are thin aliases over `ITER_COLLECT_U64` because the current cursor yields concrete `u64` values, not borrowed `&T` items; they do not claim Rust's lazy `Copied` / `Cloned` adapter identity, generic `Copy` / `Clone`, or lifetime semantics.
- Test file `std_iter_copied_cloned_macro_surface.sa` (panic ID 10541).

Focused validation only:
- `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_iter_copied_cloned_macro_surface.sa --jobs 1 --trace-panic` -> `1 passed; 0 failed; 0 skipped`.

Panic IDs next free: 10542+.
Still blocked without redesign: real Rust iterator trait hierarchy, lazy `Copied` / `Cloned` adapter identity, borrowed item and lifetime semantics, generic `Copy` / `Clone`, generic item/reference semantics, generic `collect`, `IntoIterator`, true format!, Condvar/Barrier, process env maps/Stdio objects, path component iterators, and thread stack/name builder ABI.


## Active std parity batch (2026-07-14 iter scan collect)

Completed supportable iterator scan collect macro:
- `ITER_SCAN_COLLECT_U64`: concrete Rust `Iterator::scan(...).collect::<Vec<_>>()` lowering over the slice-backed `u64` cursor.
- The macro keeps a concrete `u64` state slot, calls a `(state_ptr, value, out_mapped_ptr) -> ok` callback, pushes yielded values while ok is nonzero, consumes the first None-style stopping item without collecting it, and leaves later suffix items available.
- Test file `std_iter_scan_macro_surface.sa` (panic ID 10540).

Focused validation only:
- `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_iter_scan_macro_surface.sa --jobs 1 --trace-panic` -> `1 passed; 0 failed; 0 skipped`.

Panic IDs next free: 10541+.
Still blocked without redesign: real Rust iterator trait hierarchy, lazy `Scan` adapter identity, generic state/item/reference semantics, generic `Option` return and `collect`, `IntoIterator`, Rust `Try` residual/error object integration, true format!, Condvar/Barrier, process env maps/Stdio objects, path component iterators, and thread stack/name builder ABI.


## Active std parity batch (2026-07-14 iter inspect collect)

Completed supportable iterator inspect collect macro:
- `ITER_INSPECT_COLLECT_U64`: concrete Rust `Iterator::inspect(...).collect::<Vec<_>>()` lowering over the slice-backed `u64` cursor.
- The macro calls a `value -> u64` inspection callback for each consumed item, ignores the callback return value, preserves the original item in the output Vec, and consumes the cursor.
- Test file `std_iter_inspect_macro_surface.sa` (panic ID 10539).

Focused validation only:
- `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_iter_inspect_macro_surface.sa --jobs 1 --trace-panic` -> `1 passed; 0 failed; 0 skipped`.

Panic IDs next free: 10540+.
Still blocked without redesign: real Rust iterator trait hierarchy, lazy `Inspect` adapter identity, borrow-scoped `FnMut(&Item)` callback semantics, generic item/reference semantics, generic `collect`, `IntoIterator`, true format!, Condvar/Barrier, process env maps/Stdio objects, path component iterators, and thread stack/name builder ABI.


## Active std parity batch (2026-07-14 iter step_by collect)

Completed supportable iterator step-by collect macros:
- `ITER_TRY_STEP_BY_COLLECT_U64`: concrete Rust `Iterator::step_by(n).collect::<Vec<_>>()` lowering over the slice-backed `u64` cursor, returning `ok=0` without consuming when `step == 0`.
- `ITER_STEP_BY_COLLECT_U64`: non-try convenience wrapper for callers that already satisfy Rust's `step != 0` precondition.
- The macro collects the first item, then skips `step - 1` items between collected values, consuming skipped items through the finite cursor.
- Test file `std_iter_step_by_macro_surface.sa` (panic ID 10538).

Focused validation only:
- `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_iter_step_by_macro_surface.sa --jobs 1 --trace-panic` -> `1 passed; 0 failed; 0 skipped`.

Panic IDs next free: 10539+.
Still blocked without redesign: real Rust iterator trait hierarchy, lazy `StepBy` adapter identity, generic item/reference semantics, Rust panic integration for `step_by(0)`, generic `collect`, `IntoIterator`, Rust `Try` residual/error object integration, true format!, Condvar/Barrier, process env maps/Stdio objects, path component iterators, and thread stack/name builder ABI.


## Active std parity batch (2026-07-14 iter map_while collect)

Completed supportable iterator map-while collect macro:
- `ITER_MAP_WHILE_COLLECT_U64`: concrete Rust `Iterator::map_while(...).collect::<Vec<_>>()` lowering over the slice-backed `u64` cursor.
- The macro uses the existing `(value, out_mapped_ptr) -> ok` callback shape, consumes and maps items while the callback returns nonzero, consumes the first zero/None-style item without collecting it, and leaves later suffix items available, matching the Rust documented stopping-item behavior for this concrete eager collect subset.
- Test file `std_iter_map_while_macro_surface.sa` (panic ID 10537).

Focused validation only:
- `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_iter_map_while_macro_surface.sa --jobs 1 --trace-panic` -> `1 passed; 0 failed; 0 skipped`.

Panic IDs next free: 10538+.
Still blocked without redesign: real Rust iterator trait hierarchy, lazy `MapWhile` adapter identity, generic item/reference semantics, generic `Option` return and `collect`, `IntoIterator`, Rust `Try` residual/error object integration, true format!, Condvar/Barrier, process env maps/Stdio objects, path component iterators, and thread stack/name builder ABI.


## Active std parity batch (2026-07-14 iter collect_into)

Completed supportable iterator collect-into macro:
- `ITER_COLLECT_INTO_U64`: concrete unstable Rust `Iterator::collect_into` shape over the slice-backed `u64` cursor and existing `Vec<u64>` facade.
- The macro follows Rust's `collection.extend(self); collection` behavior by appending remaining cursor items into an existing Vec and consuming the cursor; it does not claim generic `Extend` or returned Rust `&mut E` semantics.
- Test file `std_iter_collect_into_macro_surface.sa` (panic ID 10536).

Focused validation only:
- `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_iter_collect_into_macro_surface.sa --jobs 1 --trace-panic` -> `1 passed; 0 failed; 0 skipped`.

Panic IDs next free: 10537+.
Still blocked without redesign: real Rust iterator trait hierarchy, lazy adapter objects, generic item/reference semantics, generic `Extend`/`collect`, `IntoIterator`, Rust `Try` residual/error object integration, true format!, Condvar/Barrier, process env maps/Stdio objects, path component iterators, and thread stack/name builder ABI.


## Active std parity batch (2026-07-14 iter is_partitioned)

Completed supportable iterator partition-check macro:
- `ITER_IS_PARTITIONED_U64`: concrete unstable Rust `Iterator::is_partitioned` shape over the slice-backed `u64` cursor.
- The macro follows Rust's default `all(predicate) || !any(predicate)` behavior, including short-circuit cursor consumption.
- Test file `std_iter_is_partitioned_macro_surface.sa` (panic ID 10535).

Focused validation only:
- `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_iter_is_partitioned_macro_surface.sa --jobs 1 --trace-panic` -> `1 passed; 0 failed; 0 skipped`.

Panic IDs next free: 10536+.
Still blocked without redesign: real Rust iterator trait hierarchy, lazy adapter objects, generic item/reference semantics, `IntoIterator`, Rust `Try` residual/error object integration, true format!, Condvar/Barrier, process env maps/Stdio objects, path component iterators, and thread stack/name builder ABI.


## Active std parity batch (2026-07-14 iter rfold)

Completed supportable reverse-fold macros:
- `ITER_RFOLD_U64`: concrete `DoubleEndedIterator::rfold` lowering over the slice-backed cursor using `ITER_NEXT_BACK_U64`.
- `ITER_TRY_RFOLD_U64`: concrete `DoubleEndedIterator::try_rfold` shape with `(acc, value, out_next_ptr) -> ok` callback, preserving not-yet-consumed front elements after early stop.
- Test file `std_iter_rfold_macro_surface.sa` (panic ID 10534).

Focused validation only:
- `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_iter_rfold_macro_surface.sa --jobs 1 --trace-panic` -> `1 passed; 0 failed; 0 skipped`.

Panic IDs next free: 10535+.
Still blocked without redesign: real Rust iterator trait hierarchy, lazy adapter objects, generic item/reference semantics, `IntoIterator`, Rust `Try` residual/error object integration, true format!, Condvar/Barrier, process env maps/Stdio objects, path component iterators, and thread stack/name builder ABI.


## Active std parity batch (2026-07-14 iter sorted)

Completed supportable iterator sortedness macros:
- `ITER_IS_SORTED_U64`: concrete `Iterator::is_sorted` lowering over the remaining slice-backed `u64` cursor.
- `ITER_IS_SORTED_BY_U64`: concrete `Iterator::is_sorted_by` lowering with a `(left, right) -> bool` callback.
- `ITER_IS_SORTED_BY_KEY_U64`: concrete `Iterator::is_sorted_by_key` lowering with a `value -> key` callback.
- These macros delegate to existing slice sortedness helpers and then mark the cursor empty, modeling Rust's consuming method shape for this concrete cursor facade.
- Test file `std_iter_sorted_macro_surface.sa` (panic ID 10533).

Focused validation only:
- `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_iter_sorted_macro_surface.sa --jobs 1 --trace-panic` -> `1 passed; 0 failed; 0 skipped`.

Panic IDs next free: 10534+.
Still blocked without redesign: real Rust iterator trait hierarchy, lazy adapter objects, generic item/reference semantics, `IntoIterator`, true `Option` / `Result` object integration, true format!, Condvar/Barrier, process env maps/Stdio objects, path component iterators, and thread stack/name builder ABI.


## Active std parity batch (2026-07-14 iter aliases)

Completed supportable iterator aliases/macros:
- `ITER_BY_REF`: borrowed cursor alias for Rust `Iterator::by_ref` lowering shape; consumes the same underlying SA cursor storage without claiming Rust reference/lifetime semantics.
- `ITER_EXACT_SIZE_LEN` / `ITER_EXACT_SIZE_IS_EMPTY`: Rust `ExactSizeIterator` naming aliases over the concrete slice-backed cursor's exact remaining length.
- `ITER_PARTIAL_EQ_U64` / `ITER_PARTIAL_CMP_U64`: concrete total-order `u64` iterator aliases over existing lexicographic equality/comparison helpers.
- Test file `std_iter_alias_macro_surface.sa` (panic ID 10532).

Focused validation only:
- `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_iter_alias_macro_surface.sa --jobs 1 --trace-panic` -> `1 passed; 0 failed; 0 skipped`.

Panic IDs next free: 10533+.
Still blocked without redesign: true format!, Condvar/Barrier, process env maps/Stdio objects, path component iterators, thread stack/name builder ABI, and real Rust iterator trait/lazy-adapter/generic-item parity.


## Active std parity batch (2026-07-13 n)

Completed supportable defaults/aliases/macros:
- OptionPairU64 layout constants in option.sal (24-byte pair struct: tag + value1 + value2).
- OPTION_ZIP_U64 macro in option.sa: zips two Options into OptionPairU64; both-some -> Some(pair), otherwise None.
- OPTION_UNZIP_TO_U64 macro: unzip OptionPairU64 back to separate Option layouts.
- CHAR_MIN = 0 constant in char.sal (Rust char::MIN).
- CMP_ORDERING_MIN = -1, CMP_ORDERING_MAX = 1 in cmp.sal (Rust 1.84+ stabilized Ordering::MIN/MAX).
- Test file std_option_zip_macro_surface.sa (panic IDs 10471/10472).

Panic IDs next free: 10473+.
Still blocked without redesign: true format!, Condvar/Barrier, process env maps/Stdio objects, path component iterators, thread stack/name builder ABI.

## Active std parity batch (2026-07-13 m)

Completed supportable defaults/aliases/macros:
- Infallible_SIZE = 0 and Infallible_ALIGN = 1 in convert.sal (Rust convert::Infallible never-error type).
- Complete CONVERT_* min/max coverage in convert.sal: CONVERT_U64_MIN/MAX, CONVERT_I64_MIN, CONVERT_USIZE_MIN/MAX, CONVERT_ISIZE_MIN/MAX, CONVERT_BOOL_MIN/MAX (9 new constants).
- 35 NonZero* associated constants in num.sal mirroring Rust 1.70+ stabilized constants: NONZERO_U8/U16/U32/U64/usize_MIN/MAX/ONE (15 unsigned: MIN=1, MAX=wrapping_max, ONE=1) and NONZERO_I8/I16/I32/I64/isize_MIN/MAX (10 signed: MIN=wrapping_min, MAX=wrapping_max).
- Test file std_convert_nonzero_macro_surface.sa (panic IDs 10469/10470) verifying all new constants against NUM_*_MAX/MIN constants.

Panic IDs next free: 10471+.
Still blocked without redesign: true format!, Condvar/Barrier, process env maps/Stdio objects, path component iterators, thread stack/name builder ABI.

## Active std parity batch (2026-07-13 e)

Completed supportable defaults/aliases/macros:
- CMP_ORDERING_DEFAULT_VALUE (.sal constant alias for Ordering::default = Equal)
- STRING_BUF_LIT1 / STRING_BUF_LIT2 / STRING_BUF_LIT3 (multi-slice StringBuf constructors)

Critical fix: discovered SA_STD_DIR=/home/vscode/.sa/std was pointing to a stale install (Jul 11 09:13). All previous-session edits to sa_std/ were invisible during testing because the test runner resolved imports from the stale system copy, not the project copy. Re-synced project sa_std/ to /home/vscode/.sa/std/ via rsync. This unblocks all [MACRO] and #def additions to existing std files.

Panic IDs next free: 10461+.
Still blocked without redesign: true format!, Condvar/Barrier, process env maps/Stdio objects, path component iterators, thread stack/name builder ABI.
## Active std parity batch (2026-07-13 f)

## Active std parity batch (2026-07-13 g)

Completed supportable defaults/aliases/macros:
- SLICE_DEFAULT (empty slice: ptr=0, len=0) in slice.sa
- OPTION_DEFAULT (alias for OPTION_NEW_NONE) in option.sa
- RANGE_U64_DEFAULT / RANGE_FULL_DEFAULT / BOUND_U64_DEFAULT / RANGE_FROM_U64_DEFAULT / RANGE_TO_U64_DEFAULT / RANGE_TO_INCLUSIVE_U64_DEFAULT in ops.sa

Panic IDs next free: 10464+.
Still blocked without redesign: true format!, Condvar/Barrier, process env maps/Stdio objects, path component iterators, thread stack/name builder ABI.

Completed supportable defaults/aliases/macros:
- FROM_* / TRY_FROM_* / SAT_FROM_* Rust naming aliases in convert.sa (56 macros wrapping existing CONVERT_*)
- NUM_*_DEFAULT = 0 constants in num.sal (10 integer type defaults)

Panic IDs next free: 10463+.
Still blocked without redesign: true format!, Condvar/Barrier, process env maps/Stdio objects, path component iterators, thread stack/name builder ABI.


## Active std parity batch (2026-07-13)

Completed supportable defaults/aliases/macros:
- CMP_ORDERING_DEFAULT_VALUE (.sal constant alias for Ordering::default = Equal)
- STRING_BUF_LIT1 / STRING_BUF_LIT2 / STRING_BUF_LIT3 (multi-slice StringBuf constructors)

Next supportable scan targets remain thin aliases/wrappers only; blocked: true format!, Condvar/Barrier, process env maps/Stdio objects, path component iterators, thread stack/name builder ABI.
Panic IDs next free: 10455+.

## Active std parity batch (2026-07-13 b)

Completed supportable defaults/aliases:
- NET_IPV4_DEFAULT / NET_IPV6_DEFAULT
- NET_SOCKET_ADDR_V4_DEFAULT / NET_SOCKET_ADDR_V6_DEFAULT
- PROCESS_EXIT_STATUS_DEFAULT
- REFCELL_U64_DEFAULT
- FS_PERMISSIONS_DEFAULT / FS_FILE_TIMES_DEFAULT

Panic IDs next free: 10459+.
Still blocked without redesign: true format!, Condvar/Barrier, process env maps/Stdio objects, path component iterators, thread stack/name builder ABI.

## Active std parity batch (2026-07-13 c)

Completed supportable defaults/aliases:
- RC_DEFAULT_U64 / WEAK_DEFAULT
- ARC_DEFAULT_U64 / ARC_WEAK_DEFAULT

Panic IDs next free: 10461+.

## Active std parity batch (2026-07-13 d)

Completed supportable defaults/aliases:
- DEFAULT_HASHER_DEFAULT
- BUILD_HASHER_DEFAULT_DEFAULT

Panic IDs next free: 10461+.

## Objective

Active follow-up: reduce the slowest full-test runtime owners and improve full-test log quality using the logged step runner, without returning to blind aggregate test runs. The previous compiler-performance slice reduced SCI `sa test --filter` / `--list` latency for large SAB artifacts generated by downstream `sla_ecs` to the target range and is installed. Optimization now proceeds step-by-step from the measured slowest owners, with logging good enough to identify long-running or stuck objects.

## Active Scope
1. Active full-test runtime optimization:
   - Checkpoint before this follow-up: `690d57f Add logged test step diagnostics`.
   - First completed feature: plugin installer failure preflight.
   - `src/plugins.zig` now runs interface-file checks, asset-file checks, and installed extern-symbol conflict checks before `buildPluginProject()`, so failure-only install tests no longer pay for temporary dynamic-library builds that cannot affect the failure result.
   - Artifact-dependent checks remain after build/copy: dynamic symbol smoke and artifact static policy.
   - `plugin-host-smoke` remains an isolated install-flow test. It uses `std.testing.tmpDir()` and sets `SA_PLUGINS_HOME` to the test-local `state` directory; ordinary unit testing does not install real user plugins.
   - Focused verification with the logged runner passed: `tools/test_steps_timed.sh --timeout 420 --log-dir logs/test_steps/plugin-opt-20260709T070747Z plugin-host-smoke`, `12/12 tests passed`, `elapsed=170.743s`.
   - Measured improvement against the previous full logged baseline: `209.569s -> 170.743s`, saving `38.826s` (`18.5%`) on the observed `plugin-host-smoke` step. Internal timing showed the duplicate extern failure paths as the clearest wins.
   - Second completed feature: `sa-std-runtime` reuses the build-system `sa_std` static archive instead of rebuilding `src/runtime/sa_std.zig` inside each C demo test.
   - `build.zig` wires the runtime integration test step to the archive refresh, and `tests/sa_std_runtime.zig` copies the refreshed archive into each temp test directory before linking each demo.
   - Focused verification passed: `tools/test_steps_timed.sh --timeout 420 --log-dir logs/test_steps/sa-std-runtime-opt-20260709T073000Z sa-std-runtime`, `14/14 tests passed`, `elapsed=33.532s`.
   - Measured improvement against the previous full logged baseline: `145.815s -> 33.532s`, saving `112.283s` (`77.0%`) on the observed `sa-std-runtime` step.
   - Overall progress estimate after this feature: `35%` of the full-test runtime optimization follow-up. Current observed cumulative savings are about `151.109s` across `plugin-host-smoke` and `sa-std-runtime`.
   - Third completed feature: full-test log quality improvement.
   - `tools/test_steps_timed.sh` now prints per-step heartbeats through `--heartbeat` / `SA_TEST_STEP_HEARTBEAT`, defaulting to 30s. Heartbeat lines include `index=current/total`, elapsed time, current log byte count, timestamp, and log path.
   - Failed and timed-out steps now print the last `--fail-tail-lines` / `SA_TEST_STEP_FAIL_TAIL_LINES` log lines into the console and `summary.log`, defaulting to 80 lines.
   - Each run now persists `results.tsv` and `environment.txt` next to `summary.log`, so post-run analysis does not require scraping mixed console output.
   - Focused verification completed without full-suite execution: syntax/list checks pass; `pkg-core-test` pass generated structured logs; an intentional invalid step preserved exit status `1` and printed a log tail; `sa-std-runtime` emitted a heartbeat at 5s and passed.
   - Overall progress estimate after this logging feature: `45%` of the full-test runtime/logging optimization follow-up.
   - Fourth completed feature: `unit-framework` file-level logging.
   - `tests/unit_framework/runner.zig` now prints `START` and `END` for each SA unit file it launches, including mode (`in-process` or `process`), jobs, elapsed time, stdout bytes, and stderr bytes.
   - Queued process-mode files include `index=current/total`, so parallel worker progress is visible inside the step log.
   - Per-file error exits now use `END status=error` rather than `[unit-framework] FAIL`, so the intentional queued-worker negative test does not make a passing `unit-framework` step look failed in broad log searches.
   - Focused verification completed with the single `unit-framework` build step only: `tools/test_steps_timed.sh --heartbeat 10 --timeout 240 --log-dir logs/test_steps/unit-framework-log2-20260709T082000Z unit-framework` passed, and grep confirmed file-level START/END lines plus no `[unit-framework] FAIL` marker.
   - Overall progress estimate after this feature: `55%` of the full-test runtime/logging optimization follow-up.
   - Follow-up consistency pass: `feature_suite.sa`, `assert_diag.sa`, and `mock_io_test.sa` now use the same START/END/error shape as the macro surface files.
   - Verification with `logs/test_steps/unit-framework-log3-20260709T083000Z` passed, and grep confirmed the old elapsed-only lines are gone.
   - Overall progress estimate after this consistency pass: `60%` of the full-test runtime/logging optimization follow-up.
   - Fifth completed feature: `wasm-matrix` slowest-demo and slowest-phase summary output.
   - `tests/wasm_matrix_smoke.zig` now records per-demo totals and per-phase timings for `build-exe`, `native-run`, `build-wasm`, and `wasm-run`, then prints aggregate phase totals plus top-10 slowest demo and phase rankings at the end of the step.
   - Focused verification passed with the single `wasm-matrix` step only: `tools/test_steps_timed.sh --heartbeat 15 --timeout 420 --log-dir logs/test_steps/wasm-matrix-summary2-20260709T084000Z wasm-matrix`, `1/1 tests passed`, `elapsed=146.982s`.
   - Observed matrix body summary: `demos=110 total_demo_ms=103970 build_exe_ms=93156 native_run_ms=502 build_wasm_ms=1711 wasm_run_ms=8188`. The slowest phases are all `build-exe`, so the next runtime work should target repeated SA native build cost rather than wasm execution.
   - Overall progress estimate after this feature: `65%` of the full-test runtime/logging optimization follow-up.
   - Sixth completed feature: default `wasm-matrix` now follows a WASM-fast validation shape and shares the repo cache root.
   - CLI compile options now accept `--project-root <dir>` / `--project-root=<dir>`, allowing direct compile callers to force package resolution and `.sa_cache` placement to a stable project root.
   - `wasm-matrix` now passes the repo root as `--project-root` and runs native `build-exe` only for a representative sanity subset by default. Full native equivalence remains opt-in with `SA_WASM_MATRIX_NATIVE_ALL=1`.
   - Focused verification only: cold shared-cache `wasm-matrix` passed in `212.385s`; hot shared-cache `wasm-matrix` passed in `59.623s`.
   - Measured improvement against the previous logged `wasm-matrix` run: `146.982s -> 59.623s`, saving `87.359s` (`59.4%`) on the hot-cache default path. The hot run summary was `demos=110 native_checked=6 total_demo_ms=57359 build_exe_ms=6255 build_wasm_ms=43033 wasm_run_ms=7754`.
   - Release metadata for this batch is prepared: `build.zig.zon` version `0.0.4`, plus `CHANGELOG.md` covering the `0.0.3 -> 0.0.4` changes.
   - Overall progress estimate after this feature: `75%` of the full-test runtime/logging optimization follow-up.
   - Next candidates after release merge: remaining `plugin-host-smoke`, `unit-framework`, and `std-smoke` runtime. Do not run a full suite until the next large milestone.

1. Active test logging/timeout diagnostics:
   - `tools/test_steps_timed.sh` is the new diagnostic entry point for the `zig build test` dependency set.
   - The runner executes named build steps one by one, with per-step START/PASS/FAIL/TIMEOUT logs, exact command, UTC timestamp, elapsed time, slowest-step ranking, and final summary.
   - Full output is persisted to log files so long runs can be inspected after terminal or CI truncation. Default path is `logs/test_steps/<utc timestamp>`; callers can override with `--log-dir` or `SA_TEST_STEP_LOG_DIR`. Each step gets a numbered log file and the run gets `summary.log`.
   - Default step list mirrors `build.zig` `test` dependencies through named steps. `std-smoke` covers the two std smoke artifacts, and `whitepaper-lint` covers the whitepaper smoke artifact without repeating std smoke through the aggregate `smoke` step.
   - Implemented controls: `--list`, `--continue`, `--timeout SEC`, `--jobs N`, `--log-dir DIR`, `--summary MODE`, plus `SA_TEST_STEP_TIMEOUT`, `SA_TEST_STEP_LOG_DIR`, `SA_ZIG_JOBS` / `ZIG_BUILD_JOBS`, and `SA_ZIG_SUMMARY`.
   - Focused verification completed:
     - `bash -n tools/test_steps_timed.sh`
     - `tools/test_steps_timed.sh --list`
     - `tools/test_steps_timed.sh --timeout 180 lib-root-smoke pkg-core-test`
     - `tools/test_steps_timed.sh --timeout 180 --log-dir /tmp/sci-test-steps-logs pkg-core-test`
     - invalid-step failure-path check with `--log-dir /tmp/sci-test-steps-fail-logs`
   - Observed focused run: `lib-root-smoke` passed in `50.989s`, `pkg-core-test` passed in `1.419s`, and the runner printed a slowest-step summary.
   - Persisted-log checks generated `summary.log` and per-step logs on both success and failure, while preserving the failing command exit status.
   - Heavy-step internal logging added:
     - `plugin-host-smoke` prints START/END and elapsed time around each Zig test body; focused validation passed in `230.858s` and exposed the slowest plugin tests at about `30s` each.
     - `wasm-matrix` prints START/END and elapsed time for every demo plus `build-exe`, `native-run`, `build-wasm`, and `wasm-run`; focused validation passed in `149.039s` and now identifies the exact demo/phase if the matrix hangs.
   - Milestone full validation used the logged runner instead of a blind aggregate command:
     - `tools/test_steps_timed.sh --continue --timeout 420 --log-dir logs/test_steps/full-20260709T060333Z`
     - Result: `passed=22 failed=0 timeout=0 total=22 elapsed=789.076s`.
     - Slowest steps: `plugin-host-smoke` `209.569s`, `sa-std-runtime` `145.815s`, `wasm-matrix` `121.868s`, `unit-framework` `57.407s`, `std-smoke` `57.155s`.
   - Active logging milestone is complete. Optional next optimization work is helper-level plugin timing and `sa-std-runtime` internals if those remain top blockers.

1. Active performance issue:
   - `docs/issue14_test_filter_large_sab_performance.md` records the current large-SAB performance blocker.
   - Small real SAB guard is already close to target: `parallel_table_erased-ab6b0062c772adb.sab` focused `--compile-only --filter ... --jobs 1 --no-incremental` is about `elapsed=1.28 maxrss=70252`, and focused `--list` is about `elapsed=0.33 maxrss=57136`.
   - Large real SAB is not close to target: `world_table_erased-5d5e95eb4646a2ce.sab` focused `--list --filter "table erased high k query combinations preserve entity order"` is about `elapsed=8.87 maxrss=385224`; focused `--compile-only --filter ... --jobs 1 --no-incremental` is about `elapsed=30.61 maxrss=465592`, and a cached/no explicit no-incremental repeat remained about `elapsed=33.51 maxrss=464808`.
   - Root cause in `src/cli.zig`: `executeTest()` calls `compileSource()` before `test_meta.collect()` and filter/list handling. For `.sab`, `compileSource()` decodes and verifies the whole module in `loadSabFlat()` + `referee.verifyWithOptions()`; therefore even `sa test large.sab --list --filter ...` does full decode/verify before listing one selected test.
   - Completed milestone: `.sab --list --filter` now uses metadata-only test signature decoding; selected `.sab --compile-only --filter` collects tests before compile, prunes to selected-test reachability, uses borrowed SAB symbol pools, trusts the selected SAB as preverified for compile-only, and skips the throwaway executable link after LLVM bitcode emit succeeds.
   - ReleaseFast focused gates with local `./zig-out/bin/sa`: large `world_table_erased --list --filter` `elapsed=0.05`; large `world_table_erased --compile-only --filter --no-incremental` `elapsed=0.82`; small `parallel_table_erased --compile-only --filter --no-incremental` `elapsed=0.17`.
   - Installed `/home/vscode/.sa/bin/sa` gates after `tools/install.sh --no-shell`: large list `elapsed=0.07`; large compile-only `elapsed=1.00`; small compile-only `elapsed=0.26`.
   - Full `timeout 600s zig build test --summary all` did not pass; blockers are recorded in `docs/issue15_full_test_suite_failures_20260709.md`.
   - Focused blockers fixed: `splitn aliases` source gate passes, and full `plugin-host-smoke` passes `12/12`.
   - 600s and 1200s full-suite reruns timed out without a final summary; single build-step reruns isolated `sa-std-unit`, then per-test output isolated `sa_net_uring.test.listen accept recv_ticket and outbound commands work end to end`.
   - `sa-std-unit` timeout fixed and now passes `63/63`.
   - All `zig build test` dependency steps have been rerun individually with explicit logs and passed.
   - Install completed with `tools/install.sh --no-shell`.
   - Installed focused performance gates pass: large SAB compile-only `0.75s`, large SAB list `0.04s`, small SAB compile-only `0.13s`.
   - Remaining follow-up is non-blocking future work: lazy/partial SAB instruction decode for selected run-mode and any future filtered linked-artifact cache semantics.

1. Completed in the current batch:
   - `str` / `String` / `STRING_BUF` char-pattern search aliases: `*_CONTAINS_CHAR`, `*_TRY_FIND_CHAR`/`*_FIND_CHAR`, `*_TRY_RFIND_CHAR`/`*_RFIND_CHAR`, and `*_COUNT_CHAR` families that lower a Unicode scalar `char` (`u64` codepoint) to its UTF-8 byte subsequence and reuse the existing slice-needle scan helpers, plus a new non-overlapping slice-needle `STR_COUNT`/`STRING_COUNT` count helper that the `*_COUNT_CHAR` macros delegate to.
   - `str`/`String`/`STRING_BUF` replace and limited-replace (replacen) helpers: `STRING_BUF_REPLACE_N`, `STR_REPLACE`/`STRING_REPLACE`, `STR_REPLACEN`/`STRING_REPLACEN`, the matching `*_CHAR` variants (`STRING_BUF_REPLACE_CHAR`/`STRING_BUF_REPLACE_N_CHAR`/`STR_REPLACE_CHAR`/`STRING_REPLACE_CHAR`/`STR_REPLACEN_CHAR`/`STRING_REPLACEN_CHAR`), and `STRING_BUF_REMOVE_MATCHES_CHAR`, all lowering a `char` needle via `STR_ENCODE_CHAR_SLICE` and reusing the existing slice-needle replace scan.
   - `str`/`String`/`STRING_BUF` slice-needle split and matches view helpers: `STR_SPLIT_NEEDLE_COUNT`/`STRING_SPLIT_NEEDLE_COUNT`/`STRING_BUF_SPLIT_NEEDLE_COUNT`, `STR_SPLIT_NEEDLE_TERM_COUNT`/`STRING_SPLIT_NEEDLE_TERM_COUNT`/`STRING_BUF_SPLIT_NEEDLE_TERM_COUNT`, `STR_MATCHES_NEEDLE_COUNT`/`STRING_MATCHES_NEEDLE_COUNT`/`STRING_BUF_MATCHES_NEEDLE_COUNT`, `STR_TRY_SPLIT_NEEDLE_AT`/`STRING_TRY_SPLIT_NEEDLE_AT`/`STRING_BUF_TRY_SPLIT_NEEDLE_AT`/`STR_SPLIT_NEEDLE_AT`/`STRING_SPLIT_NEEDLE_AT`/`STRING_BUF_SPLIT_NEEDLE_AT`, and `STR_TRY_MATCHES_NEEDLE_AT`/`STRING_TRY_MATCHES_NEEDLE_AT`/`STRING_BUF_TRY_MATCHES_NEEDLE_AT`/`STR_MATCHES_NEEDLE_AT`/`STRING_MATCHES_NEEDLE_AT`/`STRING_BUF_MATCHES_NEEDLE_AT`, all reusing the `STR_COUNT` non-overlapping scan and returning caller-indexed `Slice` views with `(ok, Slice)` shapes rather than Rust lazy iterator adapters.
   - `str`/`String`/`STRING_BUF` reverse slice-needle split and matches view helpers: `STR_RSPLIT_NEEDLE_COUNT`/`STRING_RSPLIT_NEEDLE_COUNT`/`STRING_BUF_RSPLIT_NEEDLE_COUNT`, `STR_RMATCHES_NEEDLE_COUNT`/`STRING_RMATCHES_NEEDLE_COUNT`/`STRING_BUF_RMATCHES_NEEDLE_COUNT`, `STR_TRY_RSPLIT_NEEDLE_AT`/`STRING_TRY_RSPLIT_NEEDLE_AT`/`STRING_BUF_TRY_RSPLIT_NEEDLE_AT`/`STR_RSPLIT_NEEDLE_AT`/`STRING_RSPLIT_NEEDLE_AT`/`STRING_BUF_RSPLIT_NEEDLE_AT`, and `STR_TRY_RMATCHES_NEEDLE_AT`/`STRING_TRY_RMATCHES_NEEDLE_AT`/`STRING_BUF_TRY_RMATCHES_NEEDLE_AT`/`STR_RMATCHES_NEEDLE_AT`/`STRING_RMATCHES_NEEDLE_AT`/`STRING_BUF_RMATCHES_NEEDLE_AT`, computing the corresponding forward caller index (`count - 1 - reverse_index`) and delegating to the existing forward `*_TRY_SPLIT_NEEDLE_AT` / `*_TRY_MATCHES_NEEDLE_AT` helpers with `(ok, Slice)` shapes rather than Rust lazy `RSplit` / `RMatches` iterator adapters.

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
   - `std::os::unix::fs::{symlink,chown,lchown,fchown}`: Rust-named Unix alias macros over existing symlink/ownership helpers.
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
   - `std::os::unix::net::{UnixStream,UnixListener}` raw-fd trait surface: stream/listener `as_raw_fd`, `into_raw_fd`, and `from_raw_fd` with `from_raw_fd` restoring the correct Unix stream/listener resource kind.
   - `std::os::fd::AsFd` socket aliases: TCP listener/stream, UDP socket, Unix listener/stream, and Unix datagram `as_fd` naming over the existing socket raw-fd facade.
   - `std::os::unix::net::{UnixStream,UnixListener}` owned-fd trait aliases: stream/listener `into_owned_fd` and `from_owned_fd` style macro surfaces over existing raw-fd and `sa_std/os/fd` owned-fd helpers.
   - `std::os::fd` / `std::os::unix::io` TCP stream/listener raw-fd trait surface: `TcpStream` / `TcpListener` `as_raw_fd`, `into_raw_fd`, and `from_raw_fd`, with `from_raw_fd` restoring the correct TCP stream/listener resource kind.
   - `std::os::fd::OwnedFd` TCP stream/listener conversion aliases: `TcpStream` / `TcpListener` `into_owned_fd` and `from_owned_fd` style macro surfaces over TCP raw-fd and `sa_std/os/fd` owned-fd helpers.
   - `std::os::fd` / `std::os::unix::io` UDP socket raw-fd trait surface: `UdpSocket` `as_raw_fd`, `into_raw_fd`, and `from_raw_fd`, with `from_raw_fd` restoring the existing UDP socket resource kind.
   - `std::os::fd::OwnedFd` UDP socket conversion aliases: `UdpSocket` `into_owned_fd` and `from_owned_fd` style macro surfaces over UDP raw-fd and `sa_std/os/fd` owned-fd helpers.
   - `std::os::fd` / `std::os::unix::io` stdio borrowed raw-fd trait surface: `Stdin` / `Stdout` / `Stderr` borrowed `as_raw_fd` style macros over fixed SA stdio handles.
   - `std::os::fd` / `std::os::unix::io` `std::fs::File` raw/owned fd trait surface: File `as_raw_fd`, `into_raw_fd`, `from_raw_fd`, `into_owned_fd`, and `from_owned_fd`, with `from_raw_fd` restoring the existing File resource kind.
   - `std::os::fd::OwnedFd` Rust-named raw-fd and clone aliases over the existing fd facade: `as_raw_fd`, `into_raw_fd`, `from_raw_fd`, and `try_clone` style macros.
   - `std::os::fd::{RawFd,BorrowedFd}` Rust-named facades: RawFd reflexive raw-fd traits and BorrowedFd borrow/as/try_clone_to_owned over raw fd duplication.
   - `StringBuf` / `Vec` Rust API parity audit: current facades are not full Rust API coverage; completed the supportable raw-parts subset with `VEC_INTO_RAW_PARTS`, `VEC_FROM_RAW_PARTS`, `STRING_BUF_INTO_RAW_PARTS`, and `STRING_BUF_FROM_RAW_PARTS`.
   - `StringBuf` / `Vec` Rust API parity continuation: completed supportable `Vec::push_mut` / `Vec::insert_mut` style mut-return macros and `String` replace-first/replace-last style macros.
   - `StringBuf` / `Vec` Rust API parity continuation: completed supportable `Vec::from_fn` style indexed generation macros and `String::remove_matches` style slice-pattern removal macro.
   - `Vec` Rust API parity continuation: completed supportable `Vec::as_non_null`, `Vec::into_parts`, and `Vec::from_parts` style NonNull parts macros over the existing `NonNull` facade.
   - `StringBuf` Rust API parity continuation: completed supportable `String::extend_from_within` style range-copy macros with UTF-8 boundary checks and self-copy reallocation protection.
   - `StringBuf` Rust API parity continuation: completed supportable `String::remove(idx)` style byte-index char removal macros plus `STR_TRY_CHAR_AT_BYTE` / `STRING_TRY_CHAR_AT_BYTE` UTF-8 helper surfaces.
   - `StringBuf` Rust API parity continuation: completed supportable `String::pop()` style char-aware tail-pop macros, distinct from existing byte-pop helpers.
   - `StringBuf` Rust API parity continuation: completed supportable `String::drain(range)` style eager range-drain macros returning a `StringBuf` with the removed range.
   - `StringBuf` Rust API parity correction: `STRING_BUF_TRY_SPLIT_OFF` / `STRING_BUF_SPLIT_OFF` now enforce Rust `String::split_off` UTF-8 char-boundary semantics before delegating to the Vec split path.
   - `StringBuf` Rust API parity continuation: completed supportable `String::retain` style codepoint-predicate retain macros that rebuild the buffer from retained UTF-8 scalar slices.
   - `StringBuf` Rust API parity correction: `STRING_BUF_TRY_PUSH_CHAR` / `STRING_BUF_TRY_INSERT_CHAR` now encode full Unicode scalar values, and `STRING_BUF_TRY_INSERT_STR` now enforces UTF-8 char-boundary insertion points.
   - `Vec` Rust API parity continuation: completed supportable `Vec::retain_mut` U64/function-pointer shape, where predicates receive mutable element pointers and retained values are compacted after possible mutation.
   - `Vec` Rust API parity continuation: completed supportable `Vec::peek_mut` U64/general element-size mutable-pointer shape, returning a pointer to the last element or null on empty Vec.
   - `Vec` Rust API parity continuation: completed supportable `Vec::from_elem` repeated-value constructor shape, constructing a Vec by pushing the same supplied value for the requested length.
   - `StringBuf` / `Vec` Rust API parity continuation: completed supportable `String::leak` / `Vec::leak` shape, consuming the owning wrapper and returning a mutable slice/string view without freeing the allocation.
   - `Vec` Rust API parity continuation: completed supportable `Vec::spare_capacity_mut` / `Vec::split_at_spare_mut` shape, and corrected `VEC_SET_LEN` to directly set length for Rust `set_len` parity.
   - `StringBuf` Rust API parity continuation: completed supportable `String::from_utf8` byte-slice constructor shape with full UTF-8 validation.
   - `StringBuf` Rust API parity continuation: completed supportable `String::into_chars` eager codepoint Vec shape, consuming the source StringBuf.
   - `StringBuf` Rust API parity continuation: completed supportable strict `String::from_utf16` U16-slice constructor shape with surrogate-pair decoding.
   - `StringBuf` Rust API parity continuation: completed supportable `String::from_utf16_lossy` U16-slice constructor shape with U+FFFD replacement for invalid surrogate units.
   - `StringBuf` Rust API parity continuation: completed supportable strict `String::from_utf16le` / `String::from_utf16be` endian byte-slice constructor shape.
   - `StringBuf` Rust API parity continuation: completed supportable `String::from_utf16le_lossy` / `String::from_utf16be_lossy` endian byte-slice constructor shape with U+FFFD replacement for invalid surrogate units and odd trailing bytes.
   - `StringBuf` Rust API parity continuation: completed supportable `String::from_utf8(Vec<u8>)` owned-Vec constructor shape with success zero-copy move and failure error-Vec preservation.
   - `StringBuf` Rust API parity continuation: completed supportable `String::from_utf8_lossy` owned-StringBuf constructor shape with U+FFFD replacement for invalid UTF-8 sequences.
   - `StringBuf` Rust API parity continuation: completed supportable `String::from_utf8_lossy_owned` owned-Vec constructor shape with valid zero-copy move and invalid lossy rebuild.
   - `StringBuf` Rust API parity correction: lossy UTF-8 decoding now consumes a contiguous invalid UTF-8 sequence as one replacement unit, matching Rust's `utf8_chunks` behavior for cases like `F0 90 80 W`.
   - `StringBuf` Rust API parity continuation: completed supportable `String::from_utf8_unchecked(Vec<u8>)` owned-Vec zero-copy constructor and `String::as_mut_str` mutable str-view naming surface.
   - `StringBuf` / `Vec` Rust API parity continuation: completed supportable clone/conversion surfaces: `STRING_BUF_FROM_STR`, `STRING_BUF_CLONE`, `STRING_BUF_CLONE_FROM`, `VEC_FROM_SLICE`, `VEC_CLONE`, and `VEC_CLONE_FROM`, plus U64 Vec convenience wrappers.
   - `StringBuf` / `Vec` Rust API parity continuation: completed supportable default/conversion/operator naming surfaces: `STRING_BUF_DEFAULT`, StringBuf AsRef/AsMut aliases, `STRING_BUF_FROM_CHAR`, `STRING_BUF_ADD_STR`, `STRING_BUF_ADD_ASSIGN_STR`, `VEC_DEFAULT`, `VEC_FROM_STR_BYTES`, `VEC_U8_FROM_STR`, and `VEC_FROM_STRING_BUF`.
   - `StringBuf` / `Vec` Rust API parity continuation: completed supportable reference conversion aliases: `STRING_BUF_FROM_MUT_STR`, `STRING_BUF_FROM_STRING_REF`, `STRING_BUF_TRY_FROM_VEC_U8`, and `STRING_BUF_TRY_FROM_BYTES_VEC`, with installed-state coverage for `VEC_FROM_STRING_BUF` ownership transfer.
   - `StringBuf` / `Vec` Rust API parity re-audit: confirmed current SA facades are not complete Rust API coverage; completed supportable Vec reference/array conversion aliases `VEC_FROM_MUT_SLICE`, `VEC_FROM_ARRAY`, and `VEC_FROM_MUT_ARRAY` plus U64 wrappers.
   - `StringBuf` / `Vec` Rust API parity re-audit: confirmed current SA facades are still not complete Rust API coverage; completed supportable Vec `AsRef<[T]>` / `AsMut<[T]>` / Deref-to-slice aliases and String `fmt::Write` `write_str` / `write_char` aliases.
   - `StringBuf` / `Vec` Rust API parity re-audit: confirmed current SA facades are still not complete Rust API coverage; completed supportable Vec `AsRef<Vec<T>>` borrowed metadata pointer alias plus String Deref/DerefMut-to-str and checked Index/IndexMut range aliases.
   - `StringBuf` / `Vec` Rust API parity re-audit: confirmed current SA facades are still not complete Rust API coverage; completed supportable String `Extend<str/char/String>` style aliases and Vec `Extend<T>` / `Extend<&T>` style aliases over existing append/push/slice-copy paths.
   - `StringBuf` Rust API parity re-audit: confirmed current SA facades are still not complete Rust API coverage; completed supportable `PartialEq<String, str, &str>` / `ne` style aliases over existing `STR_EQ` comparison.
   - `StringBuf` Rust API parity re-audit: confirmed current SA facades are still not complete Rust API coverage; completed supportable String/str lexicographic comparison aliases for `PartialOrd` / `Ord` style use cases over bytewise UTF-8 ordering.
   - `StringBuf` / `Vec` Rust API parity re-audit: confirmed current SA facades are still not complete Rust API coverage; completed supportable local `Hash` delegation aliases where StringBuf hashes through its str view and Vec U64 hashes through its slice view.
   - `StringBuf` Rust API parity re-audit: confirmed current SA facades are still not complete Rust API coverage; completed eager U64 codepoint-slice `FromIterator<char>` / `Extend<char>` style aliases with whole-slice Unicode scalar validation before mutation.
   - `StringBuf` Rust API parity re-audit: confirmed current SA facades are still not complete Rust API coverage; completed eager pointer-slice `FromIterator<&char>` / `Extend<&char>` style aliases with whole-slice Unicode scalar validation before mutation.
   - `StringBuf` Rust API parity re-audit: confirmed current SA facades are still not complete Rust API coverage; completed eager byte-slice and pointer-slice `FromIterator<core::ascii::Char>` / `Extend<core::ascii::Char>` style aliases with whole-slice ASCII validation before mutation.
   - `Vec` Rust API parity re-audit: confirmed current SA facades are still not complete Rust API coverage; completed eager slice-shaped `FromIterator<T>` / `Extend<T>` aliases over existing slice-copy construction and extension paths.
   - `Vec` Rust API parity re-audit: confirmed current SA facades are still not complete Rust API coverage; completed supportable U64 slice-delegated equality / inequality aliases for Vec-vs-slice, slice-vs-Vec, and Vec-vs-Vec comparisons.
   - `Vec` Rust API parity re-audit: confirmed current SA facades are still not complete Rust API coverage; completed supportable U64 slice-delegated lexicographic comparison aliases for Vec-vs-slice, slice-vs-Vec, and Vec-vs-Vec comparison plus bool ordering predicates.
   - `StringBuf` Rust API parity re-audit: confirmed current SA facades are still not complete Rust API coverage; completed eager Slice-of-Slice `FromIterator<&str>` / `Extend<&str>` style aliases over existing string append paths.
   - `StringBuf` Rust API parity re-audit: confirmed current SA facades are still not complete Rust API coverage; completed eager Slice-of-StringBuf metadata `FromIterator<String>` / `Extend<String>` style aliases that append each owned source string then drop its moved buffer in place, without claiming a lazy iterator object model.
   - `StringBuf` / `Vec` Rust API parity re-audit: confirmed current SA facades are still not complete Rust API coverage; completed supportable eager repeat aliases for `str::repeat` and slice/Vec repeat-style use cases, materializing new owned buffers by copying the source view `count` times.
   - `StringBuf` / `Vec` Rust API parity re-audit: confirmed current SA facades are still not complete Rust API coverage; completed supportable eager owned-copy conversion aliases for `ToOwned` / `ToString` / `to_vec` style use cases, reusing existing StringBuf/Vec clone and from-slice paths without claiming Cow/Box/trait-object coverage.
   - `StringBuf` / `Vec` Rust API parity re-audit: confirmed current SA facades are still not complete Rust API coverage; completed concrete primitive `to_string` aliases for char/bool/u64/i64 over existing StringBuf construction and SA formatter paths, without claiming generic `Display` / `ToString` trait-object coverage.
   - `StringBuf` / `Vec` Rust API parity re-audit: confirmed current SA facades are still not complete Rust API coverage; completed Vec `AsMut<Vec<T>>`-style metadata pointer alias `VEC_AS_MUT_VEC_PTR`, matching the existing local `AsRef<Vec<T>>` pointer shape without claiming full Rust whole-object mutable borrow semantics.
   - `StringBuf` / `Vec` Rust API parity re-audit: confirmed current SA facades are still not complete Rust API coverage; completed concrete smaller-integer and pointer-sized `to_string` aliases for u8/u16/u32/usize and i8/i16/i32/isize via existing u64/i64 formatter-backed StringBuf paths, without claiming `u128`/`i128`, float formatting, or generic `Display` coverage.
   - `StringBuf` / `Vec` Rust API parity re-audit: confirmed current SA facades are still not complete Rust API coverage; completed concrete String `FromStr` / parse-style aliases over existing `StringBuf` from-str copy construction, returning `ok=1` without claiming generic `FromStr` or error type modeling.
   - `StringBuf` Rust API parity re-audit: confirmed current SA facades are still not complete Rust API coverage; completed `String::as_bytes_mut`-style unsafe mutable byte-slice aliases `STRING_BUF_AS_MUT_BYTES` and `STRING_BUF_AS_MUT_REF_BYTES` over the existing Vec mutable-slice metadata facade, without claiming UTF-8 mutation invariant enforcement, `String::as_mut_vec`, or Rust borrow-checker semantics.
   - `str` / string slice Rust API parity re-audit: confirmed current SA facades are still not complete Rust API coverage; completed `str::as_bytes_mut`-style unsafe mutable byte-slice aliases `STR_AS_MUT_BYTES` and `STRING_AS_MUT_BYTES` over the existing Slice metadata view, without claiming UTF-8 mutation invariant enforcement, ownership provenance, or Rust borrow-checker semantics.
   - `StringBuf` / `Vec` / slice Rust API parity re-audit: confirmed current SA facades are still not complete Rust API coverage; completed `as_ptr_range` / `as_mut_ptr_range`-style start/end pointer output aliases for Slice, str/string, StringBuf, and Vec/U64 paths, without claiming Rust `Range<*const T>` / `Range<*mut T>` object layout or unsafe pointer-range reconstruction APIs.
   - `Vec` Rust API parity re-audit: confirmed current SA facades are still not complete Rust API coverage; completed supportable chunk/window access naming aliases `VEC_CHUNK_AT_U64`, `VEC_RCHUNK_AT_U64`, `VEC_RCHUNK_MUT_AT_U64`, `VEC_CHUNK_EXACT_AT_U64`, `VEC_CHUNK_EXACT_MUT_AT_U64`, `VEC_RCHUNK_EXACT_AT_U64`, `VEC_RCHUNK_EXACT_MUT_AT_U64`, and `VEC_WINDOW_AT_U64` over existing checked slice-view forms.
   - `Vec` Rust API parity re-audit: confirmed current SA facades are still not complete Rust API coverage; completed supportable Vec deref-to-slice copy aliases `VEC_COPY_FROM_SLICE_U64`, `VEC_CLONE_FROM_SLICE_U64`, and `VEC_COPY_WITHIN_U64` over existing mutable slice U64 copy machinery.
   - `Vec` Rust API parity re-audit: confirmed current SA facades are still not complete Rust API coverage; completed supportable Vec deref-to-slice select-nth aliases `VEC_SELECT_NTH_UNSTABLE_U64`, `VEC_SELECT_NTH_UNSTABLE_BY_U64`, and `VEC_SELECT_NTH_UNSTABLE_BY_KEY_U64` over existing mutable slice U64 partitioning machinery.
   - `Vec` Rust API parity re-audit: confirmed current SA facades are still not complete Rust API coverage; completed supportable Vec deref-to-slice binary search alias `VEC_BINARY_SEARCH_U64` over the existing U64 `(ok, index)` search result shape.
   - `StringBuf` / `str` Rust API parity re-audit: confirmed current SA facades are still not complete Rust API coverage; completed supportable split/strip naming aliases `STR_STRIP_PREFIX`, `STRING_STRIP_PREFIX`, `STR_STRIP_SUFFIX`, `STRING_STRIP_SUFFIX`, `STR_SPLIT_AT`, `STRING_SPLIT_AT`, `STR_SPLIT_AT_CHECKED`, `STRING_SPLIT_AT_CHECKED`, `STR_SPLIT_ONCE`, `STRING_SPLIT_ONCE`, `STR_RSPLIT_ONCE`, and `STRING_RSPLIT_ONCE` over existing checked `(ok, slice...)` forms.
   - `StringBuf` / `str` Rust API parity re-audit: confirmed current SA facades are still not complete Rust API coverage; completed supportable find/rfind naming aliases `STR_FIND`, `STRING_FIND`, `STR_RFIND`, and `STRING_RFIND` over existing checked `(ok, index)` forms.
   - `StringBuf` / `str` Rust API parity re-audit: confirmed current SA facades are still not complete Rust API coverage; completed supportable byte find/rfind naming aliases `STR_FIND_BYTE`, `STRING_FIND_BYTE`, `STR_RFIND_BYTE`, and `STRING_RFIND_BYTE` over existing checked `(ok, index)` byte-search forms.
   - `Vec` Rust API parity re-audit: confirmed current SA facades are still not complete Rust API coverage; completed supportable Vec deref-to-slice strip prefix/suffix aliases `VEC_STRIP_PREFIX_U64` and `VEC_STRIP_SUFFIX_U64` over existing checked U64 slice-view forms.
   - `StringBuf` / `str` Rust API parity re-audit: confirmed current SA facades are still not complete Rust API coverage; completed supportable checked range-view aliases `STR_GET_RANGE`, `STRING_GET_RANGE`, `STR_GET_PREFIX`, `STRING_GET_PREFIX`, `STR_GET_SUFFIX`, `STRING_GET_SUFFIX`, `STR_GET_RANGE_TO`, `STRING_GET_RANGE_TO`, `STR_GET_RANGE_FROM`, `STRING_GET_RANGE_FROM`, `STR_GET_RANGE_BETWEEN`, and `STRING_GET_RANGE_BETWEEN` over existing UTF-8 boundary checked `(ok, slice)` forms.
   - `Vec` Rust API parity re-audit: confirmed current SA facades are still not complete Rust API coverage; completed supportable split-off aliases `VEC_SPLIT_OFF` and `VEC_SPLIT_OFF_U64` over existing checked `(ok, Vec)` split-off forms.
   - `StringBuf` Rust API parity re-audit: confirmed current SA facades are still not complete Rust API coverage; completed supportable checked UTF-8 constructor aliases `STRING_BUF_FROM_UTF8`, `STRING_BUF_FROM_UTF8_VEC`, `STRING_BUF_FROM_VEC_U8`, and `STRING_BUF_FROM_BYTES_VEC` over existing strict UTF-8 `(ok, StringBuf[, err_vec])` forms.
   - `StringBuf` Rust API parity re-audit: confirmed current SA facades are still not complete Rust API coverage; completed supportable checked UTF-16 constructor aliases `STRING_BUF_FROM_UTF16_U16`, `STRING_BUF_FROM_UTF16LE`, and `STRING_BUF_FROM_UTF16BE` over existing strict UTF-16 `(ok, StringBuf)` forms.
   - `StringBuf` Rust API parity re-audit: confirmed current SA facades are still not complete Rust API coverage; completed closer Rust method-name UTF-16 aliases `STRING_BUF_FROM_UTF16` and `STRING_BUF_FROM_UTF16_LOSSY` over existing U16 slice strict/lossy decode forms.
   - `Vec` Rust API parity re-audit: confirmed current SA facades are still not complete Rust API coverage; completed supportable checked get_mut aliases `VEC_TRY_GET_MUT_PTR_U64` and `VEC_GET_MUT_U64` over the existing mutable-slice checked pointer helper.
   - `StringBuf` / `str` Rust API parity re-audit: confirmed current SA facades are still not complete Rust API coverage; completed supportable indexed split/line aliases `STR_SPLIT_BYTE_AT`, `STRING_SPLIT_BYTE_AT`, `STR_LINE_AT`, and `STRING_LINE_AT` over existing checked `(ok, slice)` view forms.
   - `StringBuf` / `str` Rust API parity re-audit: confirmed current SA facades are still not complete Rust API coverage; completed supportable slice-needle `trim_start_matches` / `trim_end_matches` / `trim_matches` aliases for `STR`, `STRING`, and `STRING_BUF`, returning borrowed `Slice` views and treating empty needles as no-op.
   - `StringBuf` / `str` Rust API parity re-audit: confirmed current SA facades are still not complete Rust API coverage; completed supportable `split_ascii_whitespace` count and caller-indexed token-view aliases for `STR`, `STRING`, and `STRING_BUF`, returning borrowed `Slice` views and collapsing ASCII whitespace without claiming Rust's lazy iterator object model.
   - `StringBuf` / `str` Rust API parity re-audit: confirmed current SA facades are still not complete Rust API coverage; completed supportable slice-needle `split_terminator` / `rsplit_terminator` count aliases and forward caller-indexed `split_terminator` aliases for `STR`, `STRING`, and `STRING_BUF`, returning borrowed `Slice` views without claiming Rust's lazy iterator object model.
   - `StringBuf` / `str` Rust API parity re-audit: confirmed current SA facades are still not complete Rust API coverage; completed supportable slice-needle `splitn` / `rsplitn` count aliases for `STR`, `STRING`, and `STRING_BUF`, plus `split_count == 0` and empty-needle consistency fixes for the existing caller-indexed limited split aliases.
   - `Vec` Rust API parity re-audit: confirmed current SA facades are still not complete Rust API coverage; completed supportable `push_within_capacity` checked aliases and mut-return pointer aliases, preserving local `(ok, ptr)` shapes without claiming Rust `Result<&mut T,T>` object layout or borrow-checker semantics.
   - `StringBuf` / `str` Rust API parity re-audit: confirmed current SA facades are still not complete Rust API coverage; completed supportable slice-needle `match_indices` / `rmatch_indices` count and caller-indexed aliases for `STR`, `STRING`, and `STRING_BUF`, returning local `(ok, byte_index, Slice)` results without claiming Rust's lazy iterator object model.
   - `StringBuf` / `str` Rust API parity re-audit: confirmed current SA facades are still not complete Rust API coverage; completed supportable slice-needle `split_inclusive` count and caller-indexed aliases for `STR`, `STRING`, and `STRING_BUF`, returning delimiter-retaining borrowed `Slice` views without claiming Rust's lazy iterator object model.
   - `StringBuf` / `str` Rust API parity re-audit: confirmed current SA facades are still not complete Rust API coverage; completed supportable char-pattern `split_inclusive` count and caller-indexed aliases for `STR`, `STRING`, and `STRING_BUF`, lowering valid Unicode scalar values to UTF-8 needle slices.
   - `StringBuf` / `str` Rust API parity re-audit: confirmed current SA facades are still not complete Rust API coverage; completed supportable char-pattern `starts_with` / `ends_with` / `strip_prefix` / `strip_suffix` aliases for `STR`, `STRING`, and `STRING_BUF`, lowering valid Unicode scalar values to UTF-8 needle slices and preserving local false / `(ok, Slice)` miss shapes.
   - `StringBuf` / `str` Rust API parity re-audit: confirmed current SA facades are still not complete Rust API coverage; completed supportable char-pattern `trim_start_matches` / `trim_end_matches` / `trim_matches` aliases for `STR`, `STRING`, and `STRING_BUF`, lowering valid Unicode scalar values to UTF-8 needle slices and treating invalid scalars as no-op borrowed views.
   - `StringBuf` / `str` Rust API parity re-audit: confirmed current SA facades are still not complete Rust API coverage; completed supportable `char_indices` count and caller-indexed aliases for `STR`, `STRING`, and `STRING_BUF`, returning local `(ok, byte_index, codepoint)` values without claiming Rust's lazy iterator object model.
   - `std::os::unix::xdg` supportable env-dir surface: `data_home_dir`, `config_home_dir`, `state_home_dir`, `cache_home_dir`, `data_dirs`, and `config_dirs` style macros with XDG empty-value fallback semantics.
   - `std::os::unix::fs::chroot`: current-process Linux `chroot(2)` facade with `FS_CHROOT` / `FS_UNIX_CHROOT` macro surfaces and safe `/`-only validation accepting root success or non-root permission denial.
   - `std::os::unix::net::UnixListener::accept`: address-returning `NET_UNIX_ACCEPT_ADDR` surface using the existing Unix addr handle model.
   - `std::os::unix::net::UnixListener::incoming`: named incoming iterator macro surface over the existing listener-backed incoming layout.
   - `std::os::unix::net::SocketAddr::{from_pathname,as_pathname}`: pathname Unix addr constructor and Rust-named pathname access aliases.
   - `std::os::linux::net::SocketAddrExt::as_abstract_name`: Rust-named abstract-name access aliases over existing Unix abstract addr accessors.
   - `std::os::unix::net::UnixDatagram` basic subset: unbound/pair, try_clone, raw/owned fd roundtrip, local/peer addr, passcred, timeout/nonblocking/take_error, send/recv/peek, shutdown, and close surfaces over AF_UNIX/SOCK_DGRAM handles.
   - `std::os::unix::net::UnixDatagram` pathname/abstract address paths: `bind`, `bind_addr`, `connect`, `connect_addr`, `send_to`, `send_to_addr`, `recv_from`, and `peek_from` over pathname and Unix addr handle resources.
   - `std::os::unix::ffi::{OsStrExt,OsStringExt}` Unix byte facade: `OsStr::from_bytes` / `as_bytes` slice views and `OsString::from_vec` / `into_vec` owned `Vec<u8>` move aliases.
   - `std::os::unix::thread::JoinHandleExt`: real raw `pthread_t` facade for `as_pthread_t` / `into_pthread_t`, with raw pthread join cleanup support for ownership-transfer validation.
   - `std::os::unix::process::CommandExt` supportable spawn-config subset: `arg0`, `process_group`, and `setsid` across capture/inherit/stream process modes.
   - `std::os::linux::process` / pidfd-adjacent process-group signaling subset: `PROCESS_SEND_PROCESS_GROUP_SIGNAL` with effective PGID tracking.
   - `std::os::linux::process` pidfd subset: create-pidfd spawn path, process `pidfd` / `into_pidfd` extraction, and pidfd kill/send_signal/wait/try_wait raw and code helpers.
   - `std::os::linux::process::PidFd` raw-fd trait aliases: `PIDFD_AS_RAW_FD`, `PIDFD_INTO_RAW_FD`, `PIDFD_FROM_RAW_FD`, and `PIDFD_CLOSE_RAW_FD` over the existing owned-fd facade.
   - `std::os::linux::process::PidFd` and `std::os::unix::process::{ChildStdout,ChildStderr}` AsFd aliases: `PIDFD_AS_FD`, `PROCESS_CHILD_STDOUT_AS_FD`, and `PROCESS_CHILD_STDERR_AS_FD` over the existing raw-fd facade.
   - `std::os::linux::process::PidFd` owned-fd trait aliases: `PIDFD_INTO_OWNED_FD` and `PIDFD_FROM_OWNED_FD` over the existing pidfd raw-fd and `sa_std/os/fd` owned-fd helpers.
   - `std::os::unix::process::{ChildStdout,ChildStderr}` raw-fd trait aliases over the existing owned-fd facade.
   - `std::os::unix::process::{ChildStdout,ChildStderr}` owned-fd trait aliases over the existing child pipe raw-fd and `sa_std/os/fd` owned-fd helpers.
   - `std::os::unix::process::CommandExt::{uid,gid}`: child-side `setgid` / `setuid` spawn config plus current `PROCESS_USER_ID` / `PROCESS_GROUP_ID` facade.
   - `std::os::unix::process::CommandExt::groups`: child-side `setgroups` spawn config across capture/inherit/stream modes.
   - `std::os::unix::process::CommandExt::chroot`: child-side `chroot` spawn config across capture/inherit/stream modes.
   - `std::os::unix::process::CommandExt::exec`: in-place `execvpeZ` replacement with cwd/arg0/process_group/setsid/uid/gid/groups/chroot config.
   - `std::os::linux::net::SocketAddrExt` abstract Unix socket address subset: `from_abstract_name` / `as_abstract_name`-style address handles plus listen/connect by Unix addr handle.
   - `std::os::net::linux_ext::TcpStreamExt`: Linux `TCP_QUICKACK` and `TCP_DEFER_ACCEPT` set/get socket option surface.
   - `std::os::net::linux_ext::UnixSocketExt` UnixStream subset: Linux `SO_PASSCRED` set/get socket option surface.
   - `std::os::net::linux_ext::UnixSocketExt` Unix stream/datagram subset: Linux `SO_MARK` set socket option surface for AF_UNIX stream and datagram handles.
   - `std::os::unix::process::ChildExt::kill_process_group`: Linux process-group `SIGKILL` convenience facade over the existing effective-PGID signal path.
2. Next candidate scope:
   - Continue String/Vec audit only for supportable gaps that can be expressed as SA macro/runtime surfaces and verified without misrepresenting Rust object models.
   - Re-audit remaining Linux-only `std` facade gaps against `/home/vscode/projects/rust/library/std/src/os/`.
   - Prioritize surfaces that can be expressed clearly as SA macros/runtime and verified with focused macro-surface tests.

## Acceptance

- `zig build unit-framework` passes. Done on 2026-07-05 after fixing the UDS setter compatibility path and a DNS macro-surface test leak.
- `zig build unit-framework --summary all` passes after the `DirEntryExt::ino` batch.
- `zig build unit-framework --summary all` passes after the Linux metadata/process extension batch (`6/6 steps succeeded; 5/5 tests passed`).
- `zig build unit-framework --summary all` passes after the Linux fs ownership batch (`6/6 steps succeeded; 5/5 tests passed`).
- `zig build unit-framework --summary all` passes after the Unix-domain socket completion batch (`6/6 steps succeeded; 5/5 tests passed`).
- `zig build unit-framework --summary all` passes after the CommandExt spawn-config batch (`6/6 steps succeeded; 5/5 tests passed`).
- `zig build unit-framework --summary all` passes after the process-group signal batch (`6/6 steps succeeded; 5/5 tests passed`).
- `zig build unit-framework --summary all` passes after the pidfd process batch (`6/6 steps succeeded; 5/5 tests passed`).
- `zig build unit-framework --summary all` passes after the PidFd raw-fd alias batch (`6/6 steps succeeded; 5/5 tests passed`).
- `zig build unit-framework --summary all` passes after the PidFd owned-fd alias batch (`6/6 steps succeeded; 5/5 tests passed`).
- `zig build unit-framework --summary all` passes after the Child stdout/stderr raw-fd alias batch (`6/6 steps succeeded; 5/5 tests passed`).
- `zig build unit-framework --summary all` passes after the Child stdout/stderr owned-fd alias batch (`6/6 steps succeeded; 5/5 tests passed`).
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
- `zig build unit-framework --summary all` passes after the Unix socket raw-fd trait batch (`6/6 steps succeeded; 5/5 tests passed`).
- `zig build unit-framework --summary all` passes after the Unix socket owned-fd alias batch (`6/6 steps succeeded; 5/5 tests passed`).
- `zig build unit-framework --summary all` passes after the UnixListener accept_addr batch (`6/6 steps succeeded; 5/5 tests passed`).
- `zig build unit-framework --summary all` passes after the UnixListener incoming named surface batch (`6/6 steps succeeded; 5/5 tests passed`).
- `zig build unit-framework --summary all` passes after the Unix SocketAddr pathname batch (`6/6 steps succeeded; 5/5 tests passed`).
- `zig build unit-framework --summary all` passes after the Unix SocketAddr as_abstract_name alias batch (`6/6 steps succeeded; 5/5 tests passed`).
- `zig build unit-framework --summary all` passes after the Unix fs symlink/chown alias batch (`6/6 steps succeeded; 5/5 tests passed`).
- `zig build unit-framework --summary all` passes after the TCP stream/listener raw-fd trait batch (`6/6 steps succeeded; 5/5 tests passed`).
- `zig build unit-framework --summary all` passes after the TCP stream/listener owned-fd alias batch (`6/6 steps succeeded; 5/5 tests passed`).
- `zig build unit-framework --summary all` passes after the UDP socket raw-fd trait batch (`6/6 steps succeeded; 5/5 tests passed`).
- `zig build unit-framework --summary all` passes after the UDP socket owned-fd alias batch (`6/6 steps succeeded; 5/5 tests passed`).
- `zig build unit-framework --summary all` passes after the stdio raw-fd alias batch (`6/6 steps succeeded; 5/5 tests passed`).
- `zig build unit-framework --summary all` passes after the File raw/owned fd facade batch (`6/6 steps succeeded; 5/5 tests passed`).
- `zig build unit-framework --summary all` passes after the OwnedFd named facade batch (`6/6 steps succeeded; 5/5 tests passed`).
- `zig build unit-framework --summary all` passes after the RawFd/BorrowedFd named facade batch (`6/6 steps succeeded; 5/5 tests passed`).
- `zig build unit-framework --summary all` passes after the StringBuf/Vec raw-parts facade batch (`6/6 steps succeeded; 5/5 tests passed`).
- `zig build unit-framework --summary all` passes after the StringBuf/Vec mut-return and replace facade batch (`6/6 steps succeeded; 5/5 tests passed`).
- `zig build unit-framework --summary all` passes after the StringBuf remove_matches and Vec from_fn facade batch (`6/6 steps succeeded; 5/5 tests passed`).
- `zig build unit-framework --summary all` passes after the Vec NonNull parts facade batch (`6/6 steps succeeded; 5/5 tests passed`).
- `zig build unit-framework --summary all` passes after the StringBuf extend_from_within facade batch (`6/6 steps succeeded; 5/5 tests passed`).
- `zig build unit-framework --summary all` passes after the StringBuf remove(idx) facade batch (`6/6 steps succeeded; 5/5 tests passed`).
- `zig build unit-framework --summary all` passes after the StringBuf pop() facade batch (`6/6 steps succeeded; 5/5 tests passed`).
- `zig build unit-framework --summary all` passes after the StringBuf drain(range) facade batch (`6/6 steps succeeded; 5/5 tests passed`).
- `zig build unit-framework --summary all` passes after the StringBuf split_off char-boundary parity batch (`6/6 steps succeeded; 5/5 tests passed`).
- `zig build unit-framework --summary all` passes after the StringBuf retain facade batch (`6/6 steps succeeded; 5/5 tests passed`).
- `zig build unit-framework --summary all` passes after the StringBuf Unicode push/insert char batch (`6/6 steps succeeded; 5/5 tests passed`).
- `zig build unit-framework --summary all` passes after the Vec retain_mut facade batch (`6/6 steps succeeded; 5/5 tests passed`).
- `zig build unit-framework --summary all` passes after the Vec peek_mut facade batch (`6/6 steps succeeded; 5/5 tests passed`).
- `zig build unit-framework --summary all` passes after the Vec from_elem facade batch (`6/6 steps succeeded; 5/5 tests passed`).
- `zig build unit-framework --summary all` passes after the StringBuf/Vec leak facade batch (`6/6 steps succeeded; 5/5 tests passed`).
- `zig build unit-framework --summary all` passes after the Vec spare capacity facade batch (`6/6 steps succeeded; 5/5 tests passed`).
- `zig build unit-framework --summary all` passes after the StringBuf from_utf8 facade batch (`6/6 steps succeeded; 5/5 tests passed`).
- `zig build unit-framework --summary all` passes after the StringBuf into_chars facade batch (`6/6 steps succeeded; 5/5 tests passed`).
- `zig build unit-framework --summary all` passes after the StringBuf from_utf16 facade batch (`6/6 steps succeeded; 5/5 tests passed`).
- `zig build unit-framework --summary all` passes after the StringBuf from_utf16_lossy facade batch (`6/6 steps succeeded; 5/5 tests passed`).
- `zig build unit-framework --summary all` passes after the StringBuf UTF-16 endian byte-slice facade batch (`6/6 steps succeeded; 5/5 tests passed`).
- `zig build unit-framework --summary all` passes after the StringBuf UTF-16 endian lossy byte-slice facade batch (`6/6 steps succeeded; 5/5 tests passed`).
- `zig build unit-framework --summary all` passes after the StringBuf from_utf8 Vec facade batch (`6/6 steps succeeded; 5/5 tests passed`).
- `zig build unit-framework --summary all` passes after the StringBuf from_utf8_lossy facade batch (`6/6 steps succeeded; 5/5 tests passed`).
- `zig build unit-framework --summary all` passes after the StringBuf from_utf8_lossy owned-Vec facade batch (`6/6 steps succeeded; 5/5 tests passed`).
- `zig build unit-framework --summary all` passes after the StringBuf from_utf8_lossy invalid-sequence correction batch (`6/6 steps succeeded; 5/5 tests passed`).
- `zig build unit-framework --summary all` passes after the StringBuf unchecked owned-Vec and as_mut_str facade batch (`6/6 steps succeeded; 5/5 tests passed`).
- `zig build unit-framework --summary all` passes after the Unix XDG env facade batch (`6/6 steps succeeded; 5/5 tests passed`).
- `zig build unit-framework --summary all` passes after the StringBuf/Vec clone and from-slice/from-str facade batch (`6/6 steps succeeded; 5/5 tests passed`).
- `zig build unit-framework --summary all` passes after the StringBuf/Vec default and conversion alias facade batch (`6/6 steps succeeded; 5/5 tests passed`).
- `zig build unit-framework --summary all` passes after the StringBuf/Vec reference conversion alias facade batch (`6/6 steps succeeded; 5/5 tests passed`).
- `zig build unit-framework --summary all` passes after the Unix fs chroot facade batch (`6/6 steps succeeded; 5/5 tests passed`).
- `zig build unit-framework --summary all` passes after the UnixDatagram basic facade batch (`6/6 steps succeeded; 5/5 tests passed`).
- `zig build unit-framework --summary all` passes after the UnixDatagram pathname/abstract address facade batch (`6/6 steps succeeded; 5/5 tests passed`).
- `zig build unit-framework --summary all` passes after the StringBuf/Vec naming alias audit batch (`6/6 steps succeeded; 5/5 tests passed`).
- `zig build unit-framework --summary all` passes after the Unix ffi OsStr/OsString facade batch (`6/6 steps succeeded; 5/5 tests passed`).
- `zig build unit-framework --summary all` passes after the Unix thread JoinHandleExt pthread facade batch (`6/6 steps succeeded; 5/5 tests passed`).
- `zig build unit-framework --summary all` passes after the Unix socket set_mark facade batch (`6/6 steps succeeded; 5/5 tests passed`).
- `zig build unit-framework --summary all` passes after the StringBuf/Vec Extend trait alias batch (`6/6 steps succeeded; 5/5 tests passed`).
- `zig build unit-framework --summary all` passes after the StringBuf char iterator alias batch (`6/6 steps succeeded; 5/5 tests passed`).
- `zig build unit-framework --summary all` passes after the Vec eager iterator alias batch (`6/6 steps succeeded; 5/5 tests passed`).
- `zig build unit-framework --summary all` passes after the StringBuf str iterator alias batch (`6/6 steps succeeded; 5/5 tests passed`).
- `zig build unit-framework --summary all` passes after the StringBuf char reference iterator alias batch (`6/6 steps succeeded; 5/5 tests passed`).
- `zig build unit-framework --summary all` passes after the StringBuf ASCII char iterator alias batch (`6/6 steps succeeded; 5/5 tests passed`).
- `zig build unit-framework --summary all` passes after the StringBuf equality alias batch (`6/6 steps succeeded; 5/5 tests passed`).
- `zig build unit-framework --summary all` passes after the StringBuf lexicographic comparison alias batch (`6/6 steps succeeded; 5/5 tests passed`).
- `zig build unit-framework --summary all` passes after the StringBuf/Vec hash delegation alias batch (`6/6 steps succeeded; 5/5 tests passed`).
- `zig build unit-framework --summary all` passes after the Vec U64 equality alias batch (`6/6 steps succeeded; 5/5 tests passed`).
- `zig build unit-framework --summary all` passes after the Vec U64 lexicographic comparison alias batch (`6/6 steps succeeded; 5/5 tests passed`).
- `zig build unit-framework --summary all` passes after the StringBuf owned String iterator alias batch and indirect-call signature provenance fix (`6/6 steps succeeded; 5/5 tests passed`).
- `zig build unit-framework --summary all` passes after the StringBuf/Vec repeat alias batch (`6/6 steps succeeded; 5/5 tests passed`).
- `zig build unit-framework --summary all` passes after the StringBuf/Vec owned conversion alias batch (`6/6 steps succeeded; 5/5 tests passed`).
- `zig build unit-framework --summary all` passes after the String primitive to_string alias batch (`6/6 steps succeeded; 5/5 tests passed`).
- `zig build unit-framework --summary all` passes after the Vec AsMut Vec pointer alias batch (`6/6 steps succeeded; 5/5 tests passed`).
- `zig build unit-framework --summary all` passes after the Integer primitive to_string alias batch (`6/6 steps succeeded; 5/5 tests passed`).
- `zig build unit-framework --summary all` passes after the String FromStr parse alias batch (`6/6 steps succeeded; 5/5 tests passed`).
- `zig build unit-framework --summary all` passes after the String mutable bytes alias batch (`6/6 steps succeeded; 5/5 tests passed`).
- `zig build unit-framework --summary all` passes after the str mutable bytes alias batch (`6/6 steps succeeded; 5/5 tests passed`).
- `zig build unit-framework --summary all` passes after the String/Vec pointer range alias batch (`6/6 steps succeeded; 5/5 tests passed`).
- `zig build unit-framework --summary all` passes after the Vec chunk/window access alias batch (`6/6 steps succeeded; 5/5 tests passed`).
- `zig build unit-framework --summary all` passes after the Vec copy alias batch (`6/6 steps succeeded; 5/5 tests passed`).
- `zig build unit-framework --summary all` passes after the Vec select_nth alias batch (`6/6 steps succeeded; 5/5 tests passed`).
- `zig build unit-framework --summary all` passes after the Vec binary_search alias batch (`6/6 steps succeeded; 5/5 tests passed`).
- Full test suites are skipped for the String/str split/strip alias batch by user instruction; only newly added focused source and installed-state tests were run.
- Full test suites are skipped for the String/str find alias batch by user instruction; only newly added focused source and installed-state tests were run.
- Full test suites are skipped for the String/str byte find alias batch by user instruction; only newly added focused source and installed-state tests were run.
- Full test suites are skipped for the Vec strip alias batch by user instruction; only newly added focused source and installed-state tests were run.
- Full test suites are skipped for the String/str get-range alias batch by user instruction; only newly added focused source and installed-state tests were run.
- Full test suites are skipped for the Vec split_off alias batch by user instruction; only newly added focused source and installed-state tests were run.
- Full test suites are skipped for the String UTF-8 constructor alias batch by user instruction; only newly added focused source and installed-state tests were run.
- Full test suites are skipped for the String UTF-16 constructor alias batch by user instruction; only newly added focused source and installed-state tests were run.
- Full test suites are skipped for the String exact UTF-16 alias batch by user instruction; only newly added focused source and installed-state tests were run.
- Full test suites are skipped for the Vec checked get_mut alias batch by user instruction; only newly added focused source and installed-state tests were run.
- Full test suites are skipped for the String split/line indexed alias batch by user instruction; only newly added focused source and installed-state tests were run.
- `zig build unit-framework --summary all` passes after the String trim_matches needle alias batch (`6/6 steps succeeded; 5/5 tests passed`).
- `zig build unit-framework --summary all` passes after the String split_ascii_whitespace alias batch (`6/6 steps succeeded; 5/5 tests passed`).
- `zig build unit-framework --summary all` passes after the String split_terminator needle alias batch (`6/6 steps succeeded; 5/5 tests passed`).
- `zig build unit-framework --summary all` passes after the String splitn count alias batch (`6/6 steps succeeded; 5/5 tests passed`).
- Full `zig build unit-framework --summary all` was attempted after the Vec push_within_capacity alias batch, stayed silent/idle for more than 6 minutes, and was interrupted; focused source, full Vec macro-surface, install sync, and installed-state focused tests passed.
- Full test suites are skipped for the String match_indices needle alias batch; focused source, full String macro-surface, install sync, and installed-state focused tests passed.
- Full test suites are skipped for the String split_inclusive needle alias batch; focused source, full String macro-surface, install sync, and installed-state focused tests passed.
- Full test suites are skipped for the String split_inclusive char alias batch; focused source, full String macro-surface, install sync, and installed-state focused tests passed.
- Full test suites are skipped for the String prefix/suffix char alias batch; focused source, full String macro-surface, install sync, and installed-state focused tests passed.
- Full test suites are skipped for the String trim-matches char alias batch; focused source, full String macro-surface, install sync, and installed-state focused tests passed.
- Full test suites are skipped for the String char_indices alias batch; focused source, full String macro-surface, install sync, and installed-state focused tests passed.
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
- Updated Unix fs macro-surface test passes with `FS_UNIX_SYMLINK` and `FS_UNIX_*CHOWN*` assertions:
  - `std_fs_unix_ext_macro_surface.sa`
- Updated process macro-surface test passes with raw wait-status assertions:
  - `std_process_macro_surface.sa`
- Updated process macro-surface test passes with CommandExt spawn-config assertions:
  - `std_process_macro_surface.sa`
- Updated process macro-surface test passes with process-group signal raw wait-status assertions:
  - `std_process_macro_surface.sa`
- Updated process macro-surface test passes with pidfd handle/wait/kill assertions:
  - `std_process_macro_surface.sa`
- Updated process macro-surface test passes with PidFd raw-fd alias assertions:
  - `std_process_macro_surface.sa`
- Updated process macro-surface test passes with PidFd owned-fd alias assertions:
  - `std_process_macro_surface.sa`
- Updated process macro-surface test passes with ChildStdout/ChildStderr raw-fd alias assertions:
  - `std_process_macro_surface.sa`
- Updated process macro-surface test passes with ChildStdout/ChildStderr owned-fd alias assertions:
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
- Updated Unix-domain socket macro-surface test passes with UnixStream and UnixListener raw-fd ownership roundtrip assertions:
  - `std_net_unix_macro_surface.sa`
- Updated Unix-domain socket macro-surface test passes with UnixStream and UnixListener owned-fd ownership roundtrip assertions:
  - `std_net_unix_macro_surface.sa`
- Updated Unix-domain socket macro-surface test passes with `NET_UNIX_ACCEPT_ADDR` peer address assertions:
  - `std_net_unix_macro_surface.sa`
- Updated Unix-domain socket macro-surface test passes with UnixListener incoming wrapper/next assertions:
  - `std_net_unix_macro_surface.sa`
- Updated Unix-domain socket macro-surface test passes with `NET_UNIX_ADDR_FROM_PATHNAME` and `NET_UNIX_ADDR_AS_PATHNAME_*` assertions:
  - `std_net_unix_macro_surface.sa`
- Updated Unix-domain socket macro-surface test passes with `NET_UNIX_ADDR_AS_ABSTRACT_NAME_*` assertions:
  - `std_net_unix_macro_surface.sa`
- Updated Unix-domain socket macro-surface test passes with Linux abstract address listen/connect assertions:
  - `std_net_unix_macro_surface.sa`
- Updated net macro-surface test passes with Linux `TCP_QUICKACK` / `TCP_DEFER_ACCEPT` assertions:
  - `std_net_macro_surface.sa`
- Updated net macro-surface test passes with TCP stream/listener raw-fd ownership roundtrip assertions:
  - `std_net_macro_surface.sa`
- Updated net macro-surface test passes with TCP stream/listener owned-fd ownership roundtrip assertions:
  - `std_net_macro_surface.sa`
- Updated net macro-surface test passes with UDP socket raw-fd ownership roundtrip assertions:
  - `std_net_macro_surface.sa`
- Updated net macro-surface test passes with UDP socket owned-fd ownership roundtrip assertions:
  - `std_net_macro_surface.sa`
- Updated io utility macro-surface test passes with stdio handle and borrowed raw-fd assertions:
  - `std_io_utility_macro_surface.sa`
- Updated os fd macro-surface test passes with File raw/owned fd roundtrip and File-only `read_at` assertions:
  - `std_os_fd_macro_surface.sa`
- Updated os fd macro-surface test passes with OwnedFd named raw-fd and clone assertions:
  - `std_os_fd_macro_surface.sa`
- Updated os fd macro-surface test passes with RawFd reflexive and BorrowedFd clone-to-owned assertions:
  - `std_os_fd_macro_surface.sa`
- Updated String/Vec macro-surface tests pass with raw-parts ownership roundtrip assertions:
  - `std_vec_macro_surface.sa`
  - `std_string_macro_surface.sa`
- Updated String/Vec macro-surface tests pass with Vec mut-return and String replace-first/last assertions:
  - `std_vec_macro_surface.sa`
  - `std_string_macro_surface.sa`
- Updated String/Vec macro-surface tests pass with Vec from_fn and String remove_matches assertions:
  - `std_vec_macro_surface.sa`
  - `std_string_macro_surface.sa`
- Updated Vec macro-surface tests pass with NonNull parts assertions:
  - `std_vec_macro_surface.sa`
- Updated String macro-surface tests pass with extend_from_within assertions:
  - `std_string_macro_surface.sa`
- Updated String macro-surface tests pass with byte-index UTF-8 decode and remove-char-at assertions:
  - `std_string_macro_surface.sa`
- Updated String macro-surface tests pass with char-aware pop assertions:
  - `std_string_macro_surface.sa`
- Updated String macro-surface tests pass with eager range-drain assertions:
  - `std_string_macro_surface.sa`
- Updated String macro-surface tests pass with split_off UTF-8 char-boundary assertions:
  - `std_string_macro_surface.sa`
- Updated String macro-surface tests pass with codepoint-predicate retain assertions:
  - `std_string_macro_surface.sa`
- Updated String macro-surface tests pass with Unicode char push/insert and insert boundary assertions:
  - `std_string_macro_surface.sa`
- Updated String macro-surface tests pass with trim_start_matches/trim_end_matches/trim_matches slice-needle assertions:
  - `std_string_macro_surface.sa`
- Updated String macro-surface tests pass with match_indices/rmatch_indices slice-needle byte-index assertions:
  - `std_string_macro_surface.sa`
- Updated String macro-surface tests pass with split_inclusive slice-needle delimiter-retaining assertions:
  - `std_string_macro_surface.sa`
- Updated String macro-surface tests pass with split_inclusive char-pattern delimiter-retaining assertions:
  - `std_string_macro_surface.sa`
- Updated String macro-surface tests pass with prefix/suffix char-pattern assertions:
  - `std_string_macro_surface.sa`
- Updated String macro-surface tests pass with trim_start_matches/trim_end_matches/trim_matches char-pattern assertions:
  - `std_string_macro_surface.sa`
- Updated String macro-surface tests pass with char_indices byte-offset/codepoint assertions:
  - `std_string_macro_surface.sa`
- Updated Vec macro-surface tests pass with retain_mut mutation and compaction assertions:
  - `std_vec_macro_surface.sa`
- Updated Vec macro-surface tests pass with peek_mut empty/null and mutable-last-element assertions:
  - `std_vec_macro_surface.sa`
- Updated Vec macro-surface tests pass with push_within_capacity checked and mut-return assertions:
  - `std_vec_macro_surface.sa`
- Updated Unix-domain socket macro-surface test passes with Linux `SO_PASSCRED` assertions:
  - `std_net_unix_macro_surface.sa`
- Updated process macro-surface test passes with ChildExt kill_process_group assertions:
  - `std_process_macro_surface.sa`
- Installed-state smoke passes for `std_fs_metadata_ext_macro_surface.sa`, `std_fs_unix_ext_macro_surface.sa`, and `std_process_macro_surface.sa` using `/home/vscode/.sa/std`.
- Installed-state smoke passes for `std_net_unix_macro_surface.sa` after install sync.
- Installed-state smoke passes for `std_process_macro_surface.sa` after the CommandExt spawn-config install sync.
- Installed-state smoke passes for `std_process_macro_surface.sa` after the process-group signal install sync.
- Installed-state smoke passes for `std_process_macro_surface.sa` after the pidfd process install sync.
- Installed-state smoke passes for `std_process_macro_surface.sa` after the PidFd raw-fd alias install sync.
- Installed-state smoke passes for `std_process_macro_surface.sa` after the PidFd owned-fd alias install sync.
- Installed-state smoke passes for `std_process_macro_surface.sa` after the Child stdout/stderr raw-fd alias install sync.
- Installed-state smoke passes for `std_process_macro_surface.sa` after the Child stdout/stderr owned-fd alias install sync.
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
- Installed-state smoke passes for `std_net_unix_macro_surface.sa` after the Unix socket raw-fd trait install sync.
- Installed-state smoke passes for `std_net_unix_macro_surface.sa` after the Unix socket owned-fd alias install sync.
- Installed-state smoke passes for `std_net_unix_macro_surface.sa` after the UnixListener accept_addr install sync.
- Installed-state smoke passes for `std_net_unix_macro_surface.sa` after the UnixListener incoming named surface install sync.
- Installed-state smoke passes for `std_net_unix_macro_surface.sa` after the Unix SocketAddr pathname install sync.
- Installed-state smoke passes for `std_net_unix_macro_surface.sa` after the Unix SocketAddr as_abstract_name alias install sync.
- Installed-state smoke passes for `std_fs_unix_ext_macro_surface.sa` after the Unix fs symlink/chown alias install sync.
- Installed-state smoke passes for `std_net_macro_surface.sa` after the TCP stream/listener raw-fd trait install sync.
- Installed-state smoke passes for `std_net_macro_surface.sa` after the TCP stream/listener owned-fd alias install sync.
- Installed-state smoke passes for `std_net_macro_surface.sa` after the UDP socket raw-fd trait install sync.
- Installed-state smoke passes for `std_net_macro_surface.sa` after the UDP socket owned-fd alias install sync.
- Installed-state smoke passes for `std_io_utility_macro_surface.sa` after the stdio raw-fd alias install sync.
- Installed-state smoke passes for `std_os_fd_macro_surface.sa` after the File raw/owned fd facade install sync.
- Installed-state smoke passes for `std_os_fd_macro_surface.sa` after the OwnedFd named facade install sync.
- Installed-state smoke passes for `std_os_fd_macro_surface.sa` after the RawFd/BorrowedFd named facade install sync.
- Installed-state focused String trim-matches alias test passes after install sync:
  - `std_string_macro_surface.sa --filter "trim matches aliases"`
- Installed-state focused String split-ascii-whitespace alias test passes after install sync:
  - `std_string_macro_surface.sa --filter "split ascii whitespace aliases"`
- Installed-state focused String split-terminator alias test passes after install sync:
  - `std_string_macro_surface.sa --filter "split terminator needle aliases"`
- Installed-state focused String splitn count alias test passes after install sync:
  - `std_string_macro_surface.sa --filter "splitn count aliases"`
- Installed-state focused String match-indices alias test passes after install sync:
  - `std_string_macro_surface.sa --filter "match indices needle aliases"`
- Installed-state focused String split-inclusive alias test passes after install sync:
  - `std_string_macro_surface.sa --filter "split inclusive needle aliases"`
- Installed-state focused String split-inclusive char alias test passes after install sync:
  - `std_string_macro_surface.sa --filter "split inclusive char aliases"`
- Installed-state focused String split/matches char alias test passes after install sync:
  - `std_string_macro_surface.sa --filter "split and matches char aliases"`
- Installed-state focused String match-indices char alias test passes after install sync:
  - `std_string_macro_surface.sa --filter "match indices char aliases"`
- Installed-state focused String split-terminator char alias test passes after install sync:
  - `std_string_macro_surface.sa --filter "split terminator char aliases"`
- Installed-state focused String splitn char alias test passes after install sync:
  - `std_string_macro_surface.sa --filter "splitn char aliases"`
- Installed-state focused String split-once char alias test passes after install sync:
  - `std_string_macro_surface.sa --filter "split once char aliases"`
- Installed-state focused String prefix/suffix char alias test passes after install sync:
  - `std_string_macro_surface.sa --filter "prefix suffix char aliases"`
- Installed-state focused String trim-matches char alias test passes after install sync:
  - `std_string_macro_surface.sa --filter "trim matches char aliases"`
- Installed-state focused String char_indices alias test passes after install sync:
  - `std_string_macro_surface.sa --filter "char indices aliases"`
- Installed-state focused Vec push-within-capacity alias test passes after install sync:
  - `std_vec_macro_surface.sa --filter "push within capacity aliases"`
- `src/runtime/sa_std.h`, `sa_std/*.sai`, `sa_std/*.sa`, and installed `/home/vscode/.sa/std` expose the same ABI after `./tools/install.sh --no-shell`.

## Current Status

- Source/facade/test changes are complete for the str/String/StringBuf slice-needle trim-match batch, the ASCII-whitespace split token-view batch, the char_indices caller-indexed batch, the split-once char-pattern batch, the prefix/suffix char-pattern batch, the trim-matches char-pattern batch, the split-terminator needle alias batch, the split_terminator/rsplit_terminator char-pattern batch, the splitn count/edge-case batch, the splitn/rsplitn char-pattern batch, the Vec push_within_capacity alias batch, the str/String/StringBuf match_indices/rmatch_indices slice-needle batch, the str/String/StringBuf split_inclusive slice-needle batch, the str/String/StringBuf split_inclusive char-pattern batch, the str/String/StringBuf split/matches char-pattern batch, and the str/String/StringBuf match_indices/rmatch_indices char-pattern batch.
- The Vec push_within_capacity batch adds `VEC_TRY_PUSH_WITHIN_CAPACITY`, `VEC_TRY_PUSH_WITHIN_CAPACITY_U64`, `VEC_TRY_PUSH_WITHIN_CAPACITY_MUT`, `VEC_TRY_PUSH_WITHIN_CAPACITY_MUT_U64`, `VEC_PUSH_WITHIN_CAPACITY_MUT`, and `VEC_PUSH_WITHIN_CAPACITY_MUT_U64`.
- The split-ascii-whitespace batch adds `STR_SPLIT_ASCII_WHITESPACE_COUNT`, `STR_TRY_SPLIT_ASCII_WHITESPACE_AT`, `STR_SPLIT_ASCII_WHITESPACE_AT`, and matching `STRING_*` / `STRING_BUF_*` aliases.
- The char_indices batch adds `STR_CHAR_INDICES_COUNT`, `STR_TRY_CHAR_INDICES_AT`, and `STR_CHAR_INDICES_AT`, plus matching `STRING_*` / `STRING_BUF_*` aliases.
- The split-once char-pattern batch adds `STR_TRY_SPLIT_ONCE_CHAR`, `STR_SPLIT_ONCE_CHAR`, `STR_TRY_RSPLIT_ONCE_CHAR`, and `STR_RSPLIT_ONCE_CHAR`, plus matching `STRING_*` / `STRING_BUF_*` aliases.
- The prefix/suffix char-pattern batch adds `STR_STARTS_WITH_CHAR`, `STR_ENDS_WITH_CHAR`, `STR_TRY_STRIP_PREFIX_CHAR`, `STR_STRIP_PREFIX_CHAR`, `STR_TRY_STRIP_SUFFIX_CHAR`, and `STR_STRIP_SUFFIX_CHAR`, plus matching `STRING_*` / `STRING_BUF_*` aliases.
- The trim-matches char-pattern batch adds `STR_TRIM_START_MATCHES_CHAR`, `STR_TRIM_END_MATCHES_CHAR`, and `STR_TRIM_MATCHES_CHAR`, plus matching `STRING_*` / `STRING_BUF_*` aliases.
- The split-terminator batch adds `STR_SPLIT_TERMINATOR_NEEDLE_COUNT`, `STR_RSPLIT_TERMINATOR_NEEDLE_COUNT`, `STR_TRY_SPLIT_TERMINATOR_NEEDLE_AT`, `STR_SPLIT_TERMINATOR_NEEDLE_AT`, and matching `STRING_*` / `STRING_BUF_*` aliases.
- The split-terminator char-pattern batch adds `STR_SPLIT_TERMINATOR_CHAR_COUNT`, `STR_RSPLIT_TERMINATOR_CHAR_COUNT`, `STR_TRY_SPLIT_TERMINATOR_CHAR_AT`, `STR_SPLIT_TERMINATOR_CHAR_AT`, `STR_TRY_RSPLIT_TERMINATOR_CHAR_AT`, and `STR_RSPLIT_TERMINATOR_CHAR_AT`, plus matching `STRING_*` / `STRING_BUF_*` aliases.
- The splitn count batch adds `STR_SPLIT_N_NEEDLE_COUNT`, `STR_RSPLIT_N_NEEDLE_COUNT`, and matching `STRING_*` / `STRING_BUF_*` aliases, and makes existing indexed splitn helpers return `ok=0` for `split_count == 0`.
- The splitn char-pattern batch adds `STR_SPLIT_N_CHAR_COUNT`, `STR_RSPLIT_N_CHAR_COUNT`, `STR_TRY_SPLIT_N_CHAR_AT`, `STR_SPLIT_N_CHAR_AT`, `STR_TRY_RSPLIT_N_CHAR_AT`, and `STR_RSPLIT_N_CHAR_AT`, plus matching `STRING_*` / `STRING_BUF_*` aliases.
- The match-indices batch adds `STR_MATCH_INDICES_NEEDLE_COUNT`, `STR_RMATCH_INDICES_NEEDLE_COUNT`, `STR_TRY_MATCH_INDICES_NEEDLE_AT`, `STR_MATCH_INDICES_NEEDLE_AT`, `STR_TRY_RMATCH_INDICES_NEEDLE_AT`, and `STR_RMATCH_INDICES_NEEDLE_AT`, plus matching `STRING_*` / `STRING_BUF_*` aliases.
- The split-inclusive batch adds `STR_SPLIT_INCLUSIVE_NEEDLE_COUNT`, `STR_TRY_SPLIT_INCLUSIVE_NEEDLE_AT`, and `STR_SPLIT_INCLUSIVE_NEEDLE_AT`, plus matching `STRING_*` / `STRING_BUF_*` aliases.
- The split-inclusive char-pattern batch adds `STR_SPLIT_INCLUSIVE_CHAR_COUNT`, `STR_TRY_SPLIT_INCLUSIVE_CHAR_AT`, and `STR_SPLIT_INCLUSIVE_CHAR_AT`, plus matching `STRING_*` / `STRING_BUF_*` aliases.
- The split/matches char-pattern batch adds `STR_SPLIT_CHAR_COUNT`, `STR_RSPLIT_CHAR_COUNT`, `STR_MATCHES_CHAR_COUNT`, `STR_RMATCHES_CHAR_COUNT`, `STR_TRY_SPLIT_CHAR_AT`, `STR_SPLIT_CHAR_AT`, `STR_TRY_RSPLIT_CHAR_AT`, `STR_RSPLIT_CHAR_AT`, `STR_TRY_MATCHES_CHAR_AT`, `STR_MATCHES_CHAR_AT`, `STR_TRY_RMATCHES_CHAR_AT`, and `STR_RMATCHES_CHAR_AT`, plus matching `STRING_*` / `STRING_BUF_*` aliases.
- The match-indices char-pattern batch adds `STR_MATCH_INDICES_CHAR_COUNT`, `STR_RMATCH_INDICES_CHAR_COUNT`, `STR_TRY_MATCH_INDICES_CHAR_AT`, `STR_MATCH_INDICES_CHAR_AT`, `STR_TRY_RMATCH_INDICES_CHAR_AT`, and `STR_RMATCH_INDICES_CHAR_AT`, plus matching `STRING_*` / `STRING_BUF_*` aliases.
- Focused source `zig build unit-framework --summary all` passes after the fs OpenOptions builder custom-flags members batch (`6/6 steps succeeded; 5/5 tests passed`); full-file `unit-framework` validation confirmed the new `@test` block (panic 952) coexists with the twelve pre-existing sibling `@test` blocks and that the latent `panic`-ID duplication (943/944/945 reused across tests) and `#`-comment / additive-operand flattener regressions were corrected.
- Focused source tests for `trim matches aliases`, `trim matches char aliases`, `char indices aliases`, `split ascii whitespace aliases`, `split once char aliases`, `prefix suffix char aliases`, `split terminator needle aliases`, `split terminator char aliases`, `splitn count aliases`, `splitn char aliases`, existing `splitn aliases`, `push within capacity aliases`, `match indices needle aliases`, `split inclusive needle aliases`, `split inclusive char aliases`, `split and matches char aliases`, and `match indices char aliases` pass; the full source `std_string_macro_surface.sa` passes (`72 passed`) and full source `std_vec_macro_surface.sa` passes (`29 passed`); install sync via `./tools/install.sh --no-shell` passes; installed focused splitn-count, splitn-char, split-once-char, prefix/suffix-char, trim-matches-char, char-indices, Vec push-within-capacity, String match-indices, String split-inclusive, String split-inclusive-char, String split/matches-char, String match-indices-char, and String split-terminator-char tests pass. The latest full `zig build unit-framework --summary all` attempt was interrupted after more than 6 minutes of silent/idle runtime, so it is not counted as a passing gate for the Vec batch.
- The match-indices char-pattern aliases encode a valid `u64` Unicode scalar into its UTF-8 byte sequence and delegate to the existing slice-needle match-index subsets. They return local `(ok, byte_index, Slice)` values, preserve forward byte offsets for reverse enumeration, and return `ok=0`, index `0`, and an empty slice for invalid scalars or missing indexes. This is a concrete char-pattern count/caller-indexed view subset, not Rust's full `Pattern` machinery, lazy iterator object model, or `Option<(usize, &str)>` layout.
- The char_indices aliases scan UTF-8 scalar positions and return local `(ok, byte_index, codepoint)` values for a caller-selected scalar ordinal. Missing ordinals or invalid decoding paths return `ok=0`, byte index `0`, and codepoint `0`. This is a concrete count/caller-indexed subset, not Rust's lazy `CharIndices` iterator object, tuple object layout, borrow-scoped lifetime model, or invalid-UTF-8 impossible-type invariant.
- The split-once char-pattern aliases encode a valid `u64` Unicode scalar into its UTF-8 byte sequence and delegate to the existing slice-needle split_once/rsplit_once subsets. They return the local `(ok, left, right)` `Slice` shape and return `ok=0` plus empty left/right views for invalid scalars or misses. This is a concrete char-pattern one-shot split subset, not Rust's full `Pattern` machinery, searcher internals, lazy iterator object model, or `Option<(&str, &str)>` layout.
- The prefix/suffix char-pattern aliases encode a valid `u64` Unicode scalar into its UTF-8 byte sequence and delegate to the existing slice-needle starts/ends/strip prefix/suffix subsets. Invalid scalar values return false for predicates or `ok=0` plus an empty slice for strip helpers, and misses preserve the same local empty-slice shape. This is a concrete char-pattern prefix/suffix subset, not Rust's full `Pattern` machinery, searcher internals, or `Option<&str>` layout.
- The trim-matches char-pattern aliases encode a valid `u64` Unicode scalar into its UTF-8 byte sequence and delegate to the existing slice-needle trim-match subsets. Valid scalars repeatedly strip exact UTF-8 scalar occurrences at the requested edge, and invalid scalar values return the original borrowed `Slice` view as a no-op. This is a concrete char-pattern trim subset, not Rust's full `Pattern` machinery, closure or slice-of-char patterns, searcher internals, or lazy iterator object model.
- The splitn char-pattern aliases encode a valid `u64` Unicode scalar into its UTF-8 byte sequence and delegate to the existing slice-needle splitn/rsplitn subsets. They preserve the current local splitn count/indexed behavior: `split_count == 0` returns zero entries or `ok=0`, positive counts cap the returned field count, current `rsplitn` aliases reverse-enumerate the local splitn field set, and invalid scalar values return zero entries or `ok=0` plus an empty slice. This is a concrete char-pattern count/caller-indexed view subset, not Rust's full `Pattern` machinery, lazy iterator object model, or full right-to-left `rsplitn` semantics.
- The split-terminator char-pattern aliases encode a valid `u64` Unicode scalar into its UTF-8 byte sequence and delegate to the existing slice-needle split_terminator/rsplit_terminator subsets. They reuse the existing terminator semantics that drop trailing terminator-produced empty fields, and invalid scalar values return zero entries or `ok=0` plus an empty slice. This is a concrete char-pattern count/caller-indexed view subset, not Rust's full `Pattern` machinery or lazy iterator object model.
- The split/matches char-pattern aliases encode a valid `u64` Unicode scalar into its UTF-8 byte sequence and delegate to the existing slice-needle split/matches subsets. Invalid scalar values return zero entries or `ok=0` plus an empty slice. This is a concrete char-pattern count/caller-indexed view subset, not Rust's full `Pattern` machinery or lazy iterator object model.
- The split-inclusive char-pattern aliases encode a valid `u64` Unicode scalar into its UTF-8 byte sequence and delegate to the split-inclusive needle subset. Invalid scalar values return zero entries or `ok=0` plus an empty slice. This is a concrete char-pattern count/caller-indexed view subset, not Rust's full `Pattern` machinery or lazy iterator object model.
- The split-inclusive aliases enumerate non-overlapping slice-needle split fields while retaining the matched delimiter at the end of delimiter-terminated fields. Empty haystacks and empty needles return zero entries, trailing delimiters do not produce a final empty entry, and missing indexes return `ok=0` plus an empty slice. This is a concrete count/caller-indexed view subset, not Rust's lazy `SplitInclusive` iterator object, generic `Pattern` machinery, `Option<&str>` layout, or borrow-checker lifetime model.
- The match-indices aliases enumerate non-overlapping slice-needle matches, preserve forward byte offsets for reverse enumeration, and return explicit `(ok, byte_index, Slice)` values. Empty needles and out-of-range caller indexes return `ok=0`, index `0`, and an empty slice. This is a concrete count/caller-indexed view subset, not Rust's lazy `MatchIndices` / `RMatchIndices` iterator object, generic `Pattern` machinery, `Option<(usize, &str)>` layout, or borrow-checker lifetime model.
- The split-ascii-whitespace aliases skip leading/trailing ASCII whitespace, collapse consecutive ASCII whitespace, return borrowed token `Slice` views, and return `ok=0` plus an empty slice for missing indexes. They use the existing `ASCII_IS_WHITESPACE` predicate and do not claim Rust's lazy `SplitAsciiWhitespace` iterator object or borrow-checker lifetime model.
- The split-terminator aliases reuse the existing terminator count semantics, dropping trailing terminator-produced empty fields, returning borrowed `Slice` views for present indexes, and returning `ok=0` plus an empty slice for out-of-range or empty-needle cases.
- The splitn aliases remain a concrete slice-needle subset. Empty needles intentionally follow the existing SA subset rather than Rust's full empty-pattern behavior: index `0` returns the whole haystack for positive split counts and later indexes miss.
- The trim-match aliases repeatedly strip non-empty `&str` needles at the requested edge and return borrowed `Slice` views; empty needles are explicit no-ops. This is a concrete slice-needle subset, not Rust's full `Pattern` trait, char/closure/slice-of-char variants, or lazy iterator/object model.
- The String/Vec audit still does not claim complete Rust API coverage; remaining unsupported areas include allocator-parametric APIs, Box/Cow conversions, lazy iterator object models, const-generic array ownership/extraction shapes, `Vec::into_chunks` / `into_flattened` / `recycle`, Vec whole-object mutable borrow beyond local metadata pointer facades / generic `T: PartialEq/Ord/Hash`, unsafe `String::as_mut_vec` metadata-level aliasing, `u128`/`i128`, float default formatting, Unicode whitespace/full-Pattern trim variants, and full generic trait-object coverage.
- The VecDeque u64 view aliases + extra_capacity batch adds `VEC_DEQUE_GET_U64`, `VEC_DEQUE_FRONT_U64`, `VEC_DEQUE_TRY_FRONT_U64`, `VEC_DEQUE_BACK_U64`, `VEC_DEQUE_TRY_BACK_U64`, and `VEC_DEQUE_EXTRA_CAPACITY`. The `_U64` aliases preserve the existing fallible/value front/back/get ABI contract and only expose explicit `u64`-typed Rust naming; `EXTRA_CAPACITY` returns `capacity - len` as a pure subtraction, does not allocate, and reports zero for a full or empty deque. None of these claim generic element support, scoped Rust `front_mut` / `back_mut` references, the lazy `drain` / `splice` range iterator semantics, or allocator-aware constructors that remain genuinely missing for `VecDeque`.
- The VecDeque resize / resize_with batch adds `VEC_DEQUE_RESIZE`, `VEC_DEQUE_RESIZE_U64`, `VEC_DEQUE_RESIZE_WITH`, and `VEC_DEQUE_RESIZE_WITH_U64`. `new_len <= len` shrinks through the existing `sa_vec_deque_truncate` ABI; `new_len > len` grows by repeatedly calling `sa_vec_deque_push_back` (with a fixed `u64` value for `RESIZE`, or a freshly-provided `() -> u64` generator return for `RESIZE_WITH`) until `len == new_len`, relying on the existing runtime auto-grow path for ring-buffer growth. The macros return an explicit `ok=1` status and, like Rust, do not model allocator-failure semantics; allocator-aware `try_resize*` variants, generic element support, scoped Rust references, and the lazy `splice` / drain-range iterator semantics remain genuinely missing for `VecDeque`.
- The VecDeque try_resize within capacity batch adds `VEC_DEQUE_TRY_RESIZE_WITHIN_CAPACITY`, `VEC_DEQUE_TRY_RESIZE_WITHIN_CAPACITY_U64`, `VEC_DEQUE_RESIZE_WITHIN_CAPACITY`, `VEC_DEQUE_RESIZE_WITHIN_CAPACITY_U64`, `VEC_DEQUE_TRY_RESIZE_WITH_WITHIN_CAPACITY`, `VEC_DEQUE_TRY_RESIZE_WITH_WITHIN_CAPACITY_U64`, `VEC_DEQUE_RESIZE_WITH_WITHIN_CAPACITY`, and `VEC_DEQUE_RESIZE_WITH_WITHIN_CAPACITY_U64`. The `new_len <= len` case shrinks via `sa_vec_deque_truncate`; the `new_len > len` case pre-checks `new_len <= cap`, returning `ok=0` with no mutation on insufficient capacity, and otherwise grows via `sa_vec_deque_push_back` (which can never hit the runtime auto-grow path because capacity was already validated). They do not claim Rust allocator growth, the strict allocator-aware `try_resize*` strict-failure variant, generic element support, scoped Rust references, or the lazy `splice` / drain-range iterator semantics that remain genuinely missing for `VecDeque`.
- The VecDeque try_extend_from_slice within capacity batch adds `VEC_DEQUE_TRY_EXTEND_FROM_SLICE_U64`, `VEC_DEQUE_EXTEND_FROM_SLICE_U64`, and `VEC_DEQUE_EXTEND_FROM_SLICE`. Total length is computed via plain `add` and capacity checked via `ule total <= cap`; on insufficient room it returns `ok=0` with no mutation, otherwise it appends each source element via `sa_vec_deque_push_back` (which can never hit the runtime auto-grow path because capacity was already validated). It does not claim Rust allocator growth, the lazy `extend` iterator, generic element support, scoped Rust references, allocator-aware `try_extend*` failures, or the lazy `splice` / drain-range iterator semantics that remain genuinely missing for `VecDeque`.
- The VecDeque try_extend_from_slice_n within capacity batch adds `VEC_DEQUE_TRY_EXTEND_FROM_SLICE_N_WITHIN_CAPACITY_U64` and `VEC_DEQUE_EXTEND_FROM_SLICE_N_WITHIN_CAPACITY_U64`. Total size is `mul src_len count`, then capacity-checked via `ule new_len <= cap`; on success it loops `count` times calling `VEC_DEQUE_TRY_EXTEND_FROM_SLICE_U64`, which itself reuses `sa_vec_deque_push_back` (which can never hit the runtime auto-grow path because capacity was validated up front). `count=0` / `src_len=0` succeed as no-ops, and insufficient room returns `ok=0` with no mutation. It does not claim Rust allocator growth, the lazy `extend` iterator, generic element support, scoped Rust references, allocator-aware `try_extend*` failures, or the lazy `splice` / drain-range iterator semantics that remain genuinely missing for `VecDeque`.
- The VecDeque push_n within capacity batch adds `VEC_DEQUE_TRY_PUSH_BACK_N_WITHIN_CAPACITY_U64`, `VEC_DEQUE_PUSH_BACK_N_WITHIN_CAPACITY_U64`, `VEC_DEQUE_TRY_PUSH_FRONT_N_WITHIN_CAPACITY_U64`, and `VEC_DEQUE_PUSH_FRONT_N_WITHIN_CAPACITY_U64`. Capacity is checked via `ule new_len <= cap`; insufficient room returns `ok=0` with no mutation, and the grow path loops `count` times calling `sa_vec_deque_push_back` / `sa_vec_deque_push_front`, which can never hit the runtime auto-grow branch because capacity was validated up front (front pushes wrap the head around the ring buffer correctly). `count=0` succeeds as a no-op. It does not claim Rust allocator growth, generic element support, scoped Rust references, or lazy iterator allocator-aware variants that remain genuinely missing for `VecDeque`.
- The VecDeque insert within capacity batch adds `VEC_DEQUE_TRY_INSERT_WITHIN_CAPACITY`, `VEC_DEQUE_TRY_INSERT_WITHIN_CAPACITY_U64`, `VEC_DEQUE_INSERT_WITHIN_CAPACITY`, and `VEC_DEQUE_INSERT_WITHIN_CAPACITY_U64`. Bounds and capacity are validated up front with `ule index <= len` and `ule new_len <= cap`; on out-of-bounds index or no room it returns `ok=0` with no mutation, and the success path delegates to `sa_vec_deque_try_insert`, whose internal `reserve(1)` becomes an integer no-op because the deque already had room. It does not claim Rust allocator growth, generic element support, slice-insert variants, scoped Rust references, or `try_insert*` strict-failure variants that remain genuinely missing for `VecDeque`.
- The VecDeque insert_n within capacity batch adds `VEC_DEQUE_TRY_INSERT_N_WITHIN_CAPACITY`, `VEC_DEQUE_TRY_INSERT_N_WITHIN_CAPACITY_U64`, `VEC_DEQUE_INSERT_N_WITHIN_CAPACITY`, and `VEC_DEQUE_INSERT_N_WITHIN_CAPACITY_U64`. Bounds and capacity are validated up front with `ule index <= len` and `ule new_len <= cap`; on out-of-bounds index or insufficient room it returns `ok=0` with no mutation, and the success path loops `count` times calling `VEC_DEQUE_TRY_INSERT_WITHIN_CAPACITY` at the advancing index `index + i`. `count=0` succeeds as a no-op, and each iteration's inner single-element insert can never run out of room because capacity was validated up front. It does not claim Rust allocator growth, generic element support, slice-insert variants, scoped Rust references, or allocator-aware `try_insert*` strict-failure variants that remain genuinely missing for `VecDeque`.
- The VecDeque insert_from_slice within capacity batch adds `VEC_DEQUE_TRY_INSERT_FROM_SLICE_WITHIN_CAPACITY`, `VEC_DEQUE_TRY_INSERT_FROM_SLICE_WITHIN_CAPACITY_U64`, `VEC_DEQUE_INSERT_FROM_SLICE_WITHIN_CAPACITY`, and `VEC_DEQUE_INSERT_FROM_SLICE_WITHIN_CAPACITY_U64`. Bounds and capacity are validated up front with `ule index <= len` and `ule new_len <= cap`; on out-of-bounds index or insufficient room it returns `ok=0` with no mutation, and the success path loops `src_len` times reading element `i` from the src slice and calling `VEC_DEQUE_TRY_INSERT_WITHIN_CAPACITY` at the advancing index `index + i`. An empty slice succeeds as a no-op, and each iteration's inner single-element insert can never run out of room because capacity was validated up front. It does not claim Rust allocator growth, generic element support, repeated-slice-insert variants, scoped Rust references, or allocator-aware `try_insert*` strict-failure variants that remain genuinely missing for `VecDeque`.
- The VecDeque insert_from_slice_n within capacity batch adds `VEC_DEQUE_TRY_INSERT_FROM_SLICE_N_WITHIN_CAPACITY`, `VEC_DEQUE_TRY_INSERT_FROM_SLICE_N_WITHIN_CAPACITY_U64`, `VEC_DEQUE_INSERT_FROM_SLICE_N_WITHIN_CAPACITY`, and `VEC_DEQUE_INSERT_FROM_SLICE_N_WITHIN_CAPACITY_U64`. Bounds and capacity are validated up front with `ule index <= len` and `ule new_len <= cap` where `new_len = len + src_len*count`; on out-of-bounds index or insufficient room it returns `ok=0` with no mutation, and the success path loops `count` times inserting a whole copy of the src slice at the advancing index `index + i*src_len` via `VEC_DEQUE_TRY_INSERT_FROM_SLICE_WITHIN_CAPACITY`. `count=0` and `src_len=0` both succeed as no-ops, and each iteration's inner slice insert can never run out of room because the full capacity was validated up front. It does not claim Rust allocator growth, generic element support, scoped Rust references, or allocator-aware `try_insert*` strict-failure variants that remain genuinely missing for `VecDeque`.
- The VecDeque extend_chars u64 aliases batch adds `VEC_DEQUE_TRY_EXTEND_CHARS_U64` and `VEC_DEQUE_EXTEND_CHARS_U64`, thin aliases over the existing non-allocating `VEC_DEQUE_TRY_EXTEND_FROM_SLICE_U64` capacity-checked, no-auto-grow family that treat a `Slice<u64>`'s elements as Unicode scalar-value codepoints. They pre-check `len + src_len <= cap`, return `ok=0` with no mutation on insufficient room, and otherwise loop `src_len` times calling `sa_vec_deque_push_back` with each codepoint. They do not perform Rust `char` validation (codepoints beyond U+10FFFF or surrogate codepoints pass through as `u64`), and do not claim Rust allocator growth, the lazy `extend` iterator, generic element support, scoped Rust references, or allocator-aware `try_extend*` strict-failure variants that remain genuinely missing for `VecDeque`.

## Next Priority

- Continue the highest-priority String/Vec Rust API parity audit with only newly added focused tests per batch.
- Started a parallel `VecDeque` Rust API parity audit.
- The VecDeque audit has now landed the first two batches: the u64 view aliases / `extra_capacity` batch and the `resize` / `resize_with` batch.
- The VecDeque audit has now landed the first three batches:
- The VecDeque audit has now landed the first four batches;
- The VecDeque audit has now landed the first five batches;
- The VecDeque audit has now landed the first six batches;
- The VecDeque audit has now landed the first seven batches;
- The VecDeque audit has now landed the first eleven batches; the latest adds the non-allocating `extend_chars` u64 codepoint aliases. Remaining supportable VecDeque candidates are essentially exhausted within the supportable macro-lowering surface: only a concrete `VEC_DEQUE_SPLICE` / drain-range subset remains, still gated on a ring-buffer aware runtime splice ABI; all intentionally avoid Rust lazy iterator/generic/scoped-reference semantics.
 the latest adds the non-allocating single-element `VEC_DEQUE_TRY_INSERT_WITHIN_CAPACITY` helpers. Remaining supportable VecDeque candidates include a concrete `VEC_DEQUE_SPLICE` / drain-range subset (still gated on a ring-buffer aware runtime splice ABI), a `VEC_DEQUE_TRY_INSERT_N_WITHIN_CAPACITY` repeated-value insert lowering, a `VEC_DEQUE_TRY_INSERT_FROM_SLICE_*_WITHIN_CAPACITY` slice-insert lowering, and a `VEC_DEQUE_EXTEND_CHARS_*` lowering; all intentionally avoid Rust lazy iterator/generic/scoped-reference semantics.
 the latest adds repeated `VEC_DEQUE_*_PUSH_N_WITHIN_CAPACITY_U64` helpers for the back and front edges (with ring-wrap ordering verified). Remaining supportable VecDeque candidates include a concrete `VEC_DEQUE_SPLICE` / drain-range subset (still gated on a ring-buffer aware runtime splice ABI), an `INSERT_*_WITHIN_CAPACITY` non-reallocating variant, and a `VEC_DEQUE_EXTEND_CHARS_*` lowering; all intentionally avoid Rust lazy iterator/generic/scoped-reference semantics.
 the latest adds the repeated `VEC_DEQUE_TRY_EXTEND_FROM_SLICE_N_WITHIN_CAPACITY_U64` helper. Remaining supportable VecDeque candidates include a concrete `VEC_DEQUE_SPLICE` / drain-range subset (still gated on a ring-buffer aware runtime splice ABI), a repeated-replace `with_capacity` lowering, and an `INSERT_*_WITHIN_CAPACITY` non-reallocating variant; all intentionally avoid Rust lazy iterator/generic/scoped-reference semantics.
 the latest adds a concrete `VecDeque::extend` within-capacity lowering `VEC_DEQUE_TRY_EXTEND_FROM_SLICE_U64` (plus `SKIP_START`/`VEC_DEQUE_EXTEND_FROM_SLICE_U64`/`_FROM_SLICE` aliases). Remaining supportable VecDeque candidates include a concrete `VEC_DEQUE_SPLICE` / drain-range subset (still gated on a ring-buffer aware runtime splice ABI), front/back push `WITHIN_CAPACITY` aliases, and an `INSERT_*_WITHIN_CAPACITY` non-reallocating variant; all intentionally avoid Rust lazy iterator/generic/scoped-reference semantics.
 the u64 view aliases / `extra_capacity` batch, the `resize` / `resize_with` batch, and the `try_resize` within-capacity batch. Remaining supportable VecDeque candidates include a concrete `VEC_DEQUE_SPLICE` / drain-range subset (still gated on a ring-buffer aware runtime splice ABI), front/back push `WITHIN_CAPACITY` aliases, and `VEC_DEQUE_INSERT_FROM_SLICE` / `INSERT_*_WITHIN_CAPACITY` non-reallocating variants; all intentionally avoid Rust lazy iterator/generic/scoped-reference semantics.
 Remaining supportable VecDeque candidates include a concrete `VEC_DEQUE_SPLICE` / drain-range subset (still gated on a ring-buffer aware runtime splice ABI), front/back `WITHIN_CAPACITY` push aliases, and `VEC_DEQUE_RESIZE_WITH_RESERVE*_WITHIN_CAPACITY` non-reallocating lowerings; all intentionally avoid Rust lazy iterator/generic/scoped-reference semantics.
 The first batch landed explicit `u64`-named utilities (`VEC_DEQUE_GET_U64`, `VEC_DEQUE_FRONT_U64`, `VEC_DEQUE_TRY_FRONT_U64`, `VEC_DEQUE_BACK_U64`, `VEC_DEQUE_TRY_BACK_U64`) plus `VEC_DEQUE_EXTRA_CAPACITY`. Remaining supportable VecDeque candidates include `VEC_DEQUE_RESIZE` / `RESIZE_WITH` concrete lowerings, a `VEC_DEQUE_SPLICE` / drain-range concrete subset, and front/back `WITHIN_CAPACITY` push aliases, all of which intentionally avoid Rust lazy iterator/generic/scoped-reference semantics.
 The str/String escape/encode_utf16/utf8_chunks/substr_range/get naming/get_mut/get_mut-range/get_mut-range-to-from batches, StringBuf set_len / try_truncate / push_str_within_capacity / push_byte_within_capacity / push_char_within_capacity / insert_within_capacity / extend_str_within_capacity / extend_string_within_capacity / extend_from_within_capacity / extend_char_within_capacity / extend_byte_within_capacity / extend_chars_within_capacity / extend_ascii_chars_within_capacity / extend_char_refs_within_capacity / extend_ascii_char_refs_within_capacity / replace_range_within_capacity / replace_first_within_capacity / replace_last_within_capacity / replace_first_char_within_capacity / replace_last_char_within_capacity / replace_range_char_within_capacity / replace_first_char / replace_last_char / replace_range_char / remove_matches_within_capacity / remove_matches_char_within_capacity / retain_within_capacity / drain_within_capacity / splice_within_capacity / pop_byte_if / pop_char_if / push_str_n_within_capacity / push_byte_n_within_capacity / push_char_n_within_capacity / extend_from_within_n_within_capacity / insert_str_n_within_capacity / insert_byte_n_within_capacity / insert_char_n_within_capacity helpers, Vec try_set_len / insert_within_capacity / extend_from_slice_within_capacity / append_within_capacity / extend_from_within_capacity / resize_within_capacity / splice_within_capacity / resize_with_within_capacity / extend_from_slice_n_within_capacity / push_n_within_capacity / extend_from_within_n_within_capacity / insert_n_within_capacity / insert_from_slice_within_capacity / insert_from_slice_n_within_capacity, and the Vec/StringBuf capacity-remaining/spare aliases are complete. Natural next candidates are remaining supportable capacity-preserving helpers or other concrete view subsets that can be represented as eager slice/Vec macros without claiming generic Rust trait-object semantics.
- The fs Rust API parity audit has now landed its first DirBuilder batch, adding `FS_DIR_BUILDER_NEW`, `FS_DIR_BUILDER_WITH_RECURSIVE`, `FS_DIR_BUILDER_WITH_MODE`, and `FS_DIR_BUILDER_CREATE`. The builder state is two propagating SSA `u64` values (a `recursive` bool 0/1 and a POSIX `mode`) rather than a heap-allocated builder object; `FS_DIR_BUILDER_NEW` initializes to `recursive=false` and `mode=0o755` (Rust's default), `FS_DIR_BUILDER_WITH_RECURSIVE` normalizes any nonzero flag to `1` and otherwise preserves the `mode`, `FS_DIR_BUILDER_WITH_MODE` sets the POSIX `mode` while preserving the `recursive` flag, and `FS_DIR_BUILDER_CREATE` branches on the `recursive` flag to dispatch the existing `FS_CREATE_DIR_MODE` (non-recursive) or `FS_CREATE_DIR_ALL_MODE` (recursive) lowering, so it adds no new FFI/syscall surface. It does not model Rust's owned `DirBuilder` value/move semantics, the `Permissions`/`metadata`-style builder methods on the returned handle, Windows ACL permission layers, or `create`-variants that return the directory handle. Remaining supportable fs candidates within the supportable macro-lowering surface include the fine-grained `OpenOptions` builder-object lowerings and the rich `Permissions` / `FileType` object models; typed `ReadDir` iterator entries beyond the existing JSON/buffer listing remain gated on a streaming iterator ABI, and the `FileTimes` builder object is intentionally not modeled.
- The fs Rust API parity audit has now landed its OpenOptions builder batch, adding `FS_OPEN_OPTIONS_BUILDER_NEW`, `FS_OPEN_OPTIONS_BUILDER_WITH_READ`, `FS_OPEN_OPTIONS_BUILDER_WITH_WRITE`, `FS_OPEN_OPTIONS_BUILDER_WITH_APPEND`, `FS_OPEN_OPTIONS_BUILDER_WITH_CREATE`, `FS_OPEN_OPTIONS_BUILDER_WITH_TRUNCATE`, `FS_OPEN_OPTIONS_BUILDER_WITH_MODE`, `FS_OPEN_OPTIONS_BUILDER_WITH_CUSTOM_FLAGS`, and `FS_OPEN_OPTIONS_BUILDER_OPEN`. Builder state is three propagating SSA `u64` values (`flags`, `create_mode`, `custom_flags`) rather than a heap-allocated builder object; each `WITH_READ` / `/WRITE` / `/APPEND` / `/CREATE` / `/TRUNCATE` macro normalizes any nonzero flag to set-bit OR (Rust `.x(true)` idiom; `.x(false)` clear-bit not lowered), `WITH_MODE` / `WITH_CUSTOM_FLAGS` set the full field, and `FS_OPEN_OPTIONS_BUILDER_OPEN` delegates to the existing `FS_OPEN_OPTIONS` FFI lowering (no new syscall/FFI surface). It does not model Rust's `create_new` (`O_CREAT|O_EXCL`) — the `O_EXCL` bit is not exposed by `SA_FS_CUSTOM_*` — cross-platform truncate/append on read-only opens, the `set_permissions`-equivalent builder method, Windows ACL fields, or owned builder move/build value semantics. The fs Rust API parity audit has now landed its Open_Options builder custom-flags members batch, adding `FS_OPEN_OPTIONS_BUILDER_WITH_SYNC`, `WITH_DSYNC`, `WITH_NONBLOCK`, `WITH_NOFOLLOW`, `WITH_DIRECT`, `WITH_DIRECTORY`, and `WITH_CLOEXEC`. Each takes the current `(flags, mode, custom)` triple and a `%flag`; non-zero `%flag` ORs the matching `SA_FS_CUSTOM_*` bit into the `custom_flags` slot, zero carries the triple through unchanged — Rust's `.x(true)` idiom; `.x(false)` clear-the-bit is not lowered. Note `SA_FS_CUSTOM_SYNC = 1052672` is synthetic and overlaps `SA_FS_CUSTOM_DSYNC = 4096`, so the surface test asserts OR-accumulated values, not simple sums. No new syscall/FFI surface. Remaining supportable fs candidates within the macro-lowering surface are now the rich `Permissions` / `FileType` object models; typed `ReadDir` iterator entries beyond the existing JSON/buffer listing remain gated on a streaming iterator ABI, and the `FileTimes` builder object is intentionally not modeled.

- The BinaryHeap u64/try_peek/pop/extra_capacity aliases batch adds `BINARY_HEAP_PUSH_U64`, `BINARY_HEAP_PEEK_U64`, `BINARY_HEAP_TRY_PEEK`, `BINARY_HEAP_TRY_PEEK_U64`, `BINARY_HEAP_POP`, `BINARY_HEAP_POP_U64`, and `BINARY_HEAP_EXTRA_CAPACITY`. The `_U64` aliases preserve the existing concrete `u64` max-heap ABI; `TRY_PEEK` returns a non-destructive `(ok,value)` view; `POP` is a value-only wrapper over try-pop; `EXTRA_CAPACITY` is a pure `capacity - len` subtraction. None of these claim generic ordering, iterator/drain adapters, scoped `PeekMut` guards, or true allocator-failure reporting that remain genuinely missing for `BinaryHeap`.
- The BinaryHeap audit has now landed a concrete u64-named / try-peek / pop / extra_capacity alias batch over the existing push/peek/try-pop/capacity primitives. Remaining supportable BinaryHeap candidates within the macro-lowering surface are essentially exhausted: only Rust lazy iterator/drain adapters, generic ordering, scoped PeekMut guards, and true allocator-failure reporting remain, all intentionally outside the SA facade.
- The fs Permissions object batch adds `FS_PERMISSIONS_NEW`, `FS_METADATA_PERMISSIONS`, `FS_PERMISSIONS_READONLY`, `FS_PERMISSIONS_SET_READONLY`, and `FS_SET_PERMISSIONS_OBJ` over the existing `SaFsPermissions` mode slot / `sa_fs_set_permissions` / metadata mode FFI. `readonly` treats absence of POSIX write bits (`0222`) as readonly; `set_readonly(false)` ORs owner-write (`0200`). Combined with the earlier `FS_FILE_TYPE_IS_*` aliases, the supportable Permissions/FileType object surface is now landed. Remaining fs gaps after Permissions/FileType/FileTimes are typed streaming `ReadDir` iterators and Windows ACL permissions, all intentionally outside the current Linux POSIX facade.
- The fs FileTimes object batch adds `FS_FILE_TIMES_NEW`, `FS_FILE_TIMES_WITH_ACCESSED`, `FS_FILE_TIMES_WITH_MODIFIED`, `FS_FILE_TIMES_SET`, and `FS_METADATA_FILE_TIMES` as a two-SSA-value builder over the existing path-based `FS_SET_TIMES_MS` / metadata accessed+modified millisecond queries. It does not model Rust optional leave-unchanged sentinels, `SystemTime` objects, open-`File` times mutation beyond the path helper, or birth/creation time mutation. Remaining supportable fs gaps within the Linux POSIX facade are now mainly typed streaming `ReadDir` iterators and Windows ACL permissions.
- The HashMap/BTreeMap entry helper batch adds `MAP_OR_INSERT`, `MAP_ENTRY_OR_DEFAULT`, `MAP_ENTRY_AND_MODIFY`, `BTREE_MAP_OR_INSERT`, `BTREE_MAP_ENTRY_OR_DEFAULT`, and `BTREE_MAP_ENTRY_AND_MODIFY` over the existing try-insert / get-mut-ptr contracts. These are concrete entry-style lowerings, not Rust entry objects; closure `or_insert_with`, generic defaults, and scoped entry borrows remain genuinely missing.
- The set/map alias batch adds `SET_ENTRY_GET_OR_INSERT`, `SET_OR_INSERT`, `SET_EXTRA_CAPACITY`, `BTREE_SET_ENTRY_GET_OR_INSERT`, `BTREE_SET_OR_INSERT`, and `MAP_EXTRA_CAPACITY` over existing get-or-insert / capacity primitives. Remaining supportable collection gaps are largely iterator/entry-object/generic-Ord/allocator surfaces intentionally outside the SA facade.
- The PathBuf owned-path batch adds `PATH_BUF_NEW` / `WITH_CAPACITY` / `FROM_PATH` / `PUSH` / `POP` / `SET_FILE_NAME` / `SET_EXTENSION` / `AS_PATH` and related capacity helpers as a concrete owned byte-buffer facade over `STRING_BUF` plus existing `PATH_*` Slice join/parent helpers. Remaining path gaps are true component iterators, Windows prefixes, and `OsStr`/`OsString` semantics.
- The collection literal arity batch adds `MAP_LIT1`/`MAP_LIT3`, `SET_LIT1`/`SET_LIT3`, `BTREE_MAP_LIT1`/`LIT2`/`LIT3`, and `BTREE_SET_LIT1`/`LIT3` as fixed-arity constructors over existing put/insert helpers. Remaining collection gaps are still true iterators, generic Ord/entry objects, and allocator-aware constructors.
- The OsString/OsStr owned byte-buffer batch expands `sa_std/os/unix_ffi.sa` with concrete `OS_STRING_NEW` / `FROM_STR` / `PUSH_*` / `AS_OS_STR` / `TO_STRING_CHECKED` and `OS_STR_LEN` / `TO_OS_STRING` / `TO_STR_CHECKED` helpers over `Vec<u8>`/`Slice`. Remaining platform-string gaps are Windows WTF-8, lossy display, and true OS-native encoding objects.
- The BinaryHeap from/lit constructor batch adds `BINARY_HEAP_LIT1`/`LIT2`/`LIT3`, `BINARY_HEAP_FROM_SLICE_U64`/`FROM_VEC_U64`, and `BINARY_HEAP_EXTEND_FROM_SLICE_U64`/`EXTEND_FROM_VEC_U64` over the concrete u64 push/heapify path. Remaining BinaryHeap gaps are still lazy iterators, generic Ord, PeekMut drop guards, and allocator-aware APIs.
- The VecDeque from/lit constructor batch adds `VEC_DEQUE_LIT1`/`LIT2`/`LIT3` and `VEC_DEQUE_FROM_SLICE_U64`/`FROM_VEC_U64` over the concrete u64 push_back path. Remaining VecDeque gaps are still lazy drain/splice iterators, generic elements, and scoped mut references.
- The Vec u64 literal constructor batch adds `VEC_LIT1_U64`/`LIT2_U64`/`LIT3_U64` over `VEC_NEW` + `VEC_PUSH_U64`. Remaining Vec gaps remain generic element support and lazy iterator adapters.
- The LazyLock alias batch adds `LAZY_LOCK_NEW` / `FORCE` / `GET` / `IS_READY` / `INTO_INNER` over the existing Once/OnceLock u64 cell. Remaining sync gaps are still Condvar/Barrier, unbounded mpsc, generic OnceLock/LazyLock type objects, and RAII lock guards.
- The AtomicU64 fetch_update + StringBuf LIT batch adds `ATOMIC_U64_FETCH_UPDATE` and `STRING_BUF_LIT1`/`LIT2`/`LIT3`. Remaining sync gaps still include Condvar/Barrier and generic atomic fetch_update across all widths; remaining string gaps are Pattern trait/iterator objects.
## Notes
- Thread builder SSA facade (`THREAD_BUILDER_*` detached-only), PathBuf `PUSH_PATH_BUF`/`JOIN*`, Env `SPLIT_PATHS_OS`/`JOIN_PATHS_OS`, and `CSTR_TO_STRING_LOSSY` landed. Remaining thread gaps: stack size/name builder fields and park/unpark. Remaining env/path gaps: true OsString iterators and component iterator objects.

- Net typed-address `format_ascii` helpers, PathBuf query aliases (`IS_ABSOLUTE`/`COMPONENT_COUNT`/`TRY_*`), and `ENV_ARGS_OS`/`ENV_VARS_OS` JSON aliases landed. Remaining net gaps: zero-compressed Display, u128 bits, lazy ToSocketAddrs iterators. Remaining env gaps: true OsString iterators/objects. Remaining path gaps: true component iterator objects and Windows prefixes.

- PathBuf/OsString conversion + lossy helpers landed: `PATH_BUF_AS_OS_STR` / `FROM_OS_STR` / `FROM_OS_STRING` / `INTO_OS_STRING` / `INTO_OS_STRING_MOVE`, `OS_STRING_TO_STRING_LOSSY` / `OS_STR_TO_STRING_LOSSY` / `OS_STRING_FROM_PATH`, and `CSTRING_TO_STRING_LOSSY`. These remain Unix byte-buffer facades over `STRING_BUF_FROM_UTF8_LOSSY` and do not claim Rust `Cow`/`Display`/`WTF-8`.

- The PathBuf/OsString lit+capacity-remaining batch and Env rust-named alias batch finished validation: `PATH_BUF_LIT1/2/3` + remaining-capacity aliases, `OS_STRING_LIT1/2/3` + remaining-capacity aliases, and `ENV_VAR` / `ENV_VAR_OS` / `ENV_ARGS` / `ENV_VARS` / `ENV_SPLIT_PATHS` / `ENV_JOIN_PATHS` / `ENV_HOME_DIR` over existing helpers. Env alias surface tests require addressable `stack_alloc Slice_SIZE` keys. Remaining env gaps are true `args_os`/`vars_os` iterators and OsString-native path join/split objects.
- The Process Command builder now also has `PROCESS_COMMAND_BUILDER_EXEC_CAPTURE` / `PROCESS_COMMAND_BUILDER_OUTPUT` over existing capture ABIs (cwd-only CommandExt subset on capture). Owned CString gained `CSTRING_DEFAULT` / `CSTRING_CLONE` / `CSTRING_LIT1`. Remaining process gaps are env maps, Stdio pipe objects, and full CommandExt on capture; remaining FFI gaps include lossy conversion and Windows/OsString parity.

- Atomic narrow-width `FETCH_UPDATE` + `FROM_PTR` aliases: Bool/U8/I8/U16/I16 fetch_update and `ATOMIC_*_FROM_PTR` renames over existing from_mut helpers.
- IPv6 parse_ascii batch: runtime `sa_net_ipv6_parse_ascii` / `sa_net_socket_addr_v6_parse_ascii`, macros `NET_IPV6_*_PARSE_ASCII` / `NET_SOCKET_ADDR_V6_*_PARSE_ASCII`, enum IpAddr/SocketAddr parse now V4-then-V6; added `NET_IP_ADDR_TO_IPV6`.
- Process Command builder SSA facade batch: added `PROCESS_COMMAND_BUILDER_*` scalar-flag builder over existing CommandExt run/spawn helpers (cwd/arg0/process_group/setsid only; no env/pipe objects).
- Multi-width atomic `FETCH_UPDATE` batch: added U32/I32/I64/USIZE/ISIZE/PTR helpers over existing cmpxchg loops; unit-framework diagnostic-code collisions in `std_fs_macro_surface.sa` and `std_net_unix_macro_surface.sa` fixed so assert codes no longer share sibling-test panic IDs.

- Linux/Unix fd facade behavior is acceptable for this batch.
- Keep edits scoped to source/runtime/std facade and test coverage; do not branch into wider trait/prelude work unless a Linux std gap directly requires it.
## Notes (2026-07-12 atomic nand + panic uniqueness)
- Landed signed atomic `FETCH_AND/OR/XOR` and multi-width `FETCH_NAND` (cmpxchg loop; no ISA nand RMW).
- Verified prior batch: atomic fetch_min/max, `THREAD_SLEEP_*`, `PATH_BUF_CLONE_FROM`.
- Renumbered cross-file duplicate unit-framework panic IDs to global uniqueness (kept first-seen; later IDs from 10026+; assert codes realigned in-block).
- Do not mark full Rust-std parity complete; remaining blocked: true format!, Condvar/Barrier, process env maps/Stdio objects, path component iterators, thread stack/name builder ABI.
## Notes (2026-07-12 time/io/path/once batch)
- Landed Instant/SystemTime naming aliases, `IO_COPY` handle loop, PathBuf FS query wrappers, and `ONCE_LOCK_*` aliases.
- Still blocked without redesign: true `format!`, Condvar/Barrier, process env maps/Stdio objects, path component iterators, thread stack/name builder ABI.
## Notes (2026-07-12 path fs-ops / defaults / env os / process pid)
- Landed Path/PathBuf filesystem op wrappers, MUTEX/RWLOCK/ONCE defaults, ENV_*_OS path aliases, PROCESS_PID/PPID/UID/GID aliases.
- Fixed env free-status assertion and cross-file diagnostic IDs 1006/1007 -> 10417/10418.
- Still blocked without redesign: true `format!`, Condvar/Barrier, process env maps/Stdio objects, path component iterators, thread stack/name builder ABI.


## Notes (2026-07-12 path rename/link + io handle batch)
- Landed Path/PathBuf rename/hard_link/symlink/read_to_string/create_dir_all/remove_dir_all/set_permissions/set_times_ms wrappers.
- Landed handle-level `IO_READ`/`READ_EXACT`/`WRITE`/`WRITE_ALL`/`FLUSH`/`CLOSE` status aliases.
- Still blocked without redesign: true `format!`, Condvar/Barrier, process env maps/Stdio objects, path component iterators, thread stack/name builder ABI.

## Notes (2026-07-12 path read_dir batch)
- Landed Path/PathBuf `READ_DIR_JSON`/`READ_DIR_ENTRIES` wrappers over existing FS dir listing handles.
- Still blocked without redesign: true `format!`, Condvar/Barrier, process env maps/Stdio objects, path component iterators, thread stack/name builder ABI.

## Notes (2026-07-12 thread/env naming + path read_dir)
- Landed `THREAD_CURRENT`/`THREAD_YIELD`, `ENV_SET_VAR_OS`/`ENV_REMOVE_VAR_OS`, and Path/PathBuf read_dir wrappers.
- Still blocked without redesign: true `format!`, Condvar/Barrier, process env maps/Stdio objects, path component iterators, thread stack/name builder ABI.


## Notes (2026-07-12 time defaults + OsString default)
- Landed `TIME_DURATION_DEFAULT`/`TIME_SYSTEM_TIME_UNIX_EPOCH`/`TIME_INSTANT_SATURATING_DURATION_SINCE` and `OS_STRING_DEFAULT`.
- Still blocked without redesign: true `format!`, Condvar/Barrier, process env maps/Stdio objects, path component iterators, thread stack/name builder ABI.


## Notes (2026-07-12 path DirBuilder/OpenOptions facades)
- Landed Path/PathBuf wrappers for FS DirBuilder create and OpenOptions builder open.
- Still blocked without redesign: true `format!`, Condvar/Barrier, process env maps/Stdio objects, path component iterators, thread stack/name builder ABI.


## Notes (2026-07-12 collections/atomic defaults + path perm/filetimes)
- Landed Default constructors for Map/Set/BTree/VecDeque/BinaryHeap and zero-init Atomic defaults; Path/PathBuf permissions-object and FileTimes set wrappers.
- Still blocked without redesign: true `format!`, Condvar/Barrier, process env maps/Stdio objects, path component iterators, thread stack/name builder ABI.

## Notes (2026-07-12 atomic signed/ptr defaults + path metadata/fs-size/remove/mode)
- Landed signed/ptr Atomic Default constructors and Path/PathBuf metadata_json, FS file-size, remove-entry/remove-any, create-dir-with-mode wrappers.
- Avoid macro names `PATH_LEN` and `PATH_CREATE_DIR_MODE` (compile hang / InvalidMacroInvocation prefix collisions); use `PATH_FS_SIZE` and `PATH_*_WITH_MODE`.
- Still blocked without redesign: true `format!`, Condvar/Barrier, process env maps/Stdio objects, path component iterators, thread stack/name builder ABI.

## Notes (2026-07-12 path base64/open-flags + env home_os + once defaults + process exit_code)
- Landed Path/PathBuf open-flags/options and base64 read/write wrappers; ENV_HOME_DIR_OS; ONCE_LOCK_DEFAULT/LAZY_LOCK_DEFAULT; PROCESS_EXIT_CODE alias.
- Still blocked without redesign: true `format!`, Condvar/Barrier, process env maps/Stdio objects, path component iterators, thread stack/name builder ABI.

## Notes (2026-07-12 path unix chown/mkfifo/make_dir + process success + thread sleep duration)
- Landed Path/PathBuf unix ownership/mkfifo/make_dir wrappers, PROCESS_SUCCESS, THREAD_SLEEP_DURATION_NS.
- Still blocked without redesign: true `format!`, Condvar/Barrier, process env maps/Stdio objects, path component iterators, thread stack/name builder ABI.

## Notes (2026-07-13 time defaults/sleep + process naming + IO_COPY_N)
- Landed TIME_SLEEP_DURATION_NS/INSTANT_DEFAULT/SYSTEM_TIME_DEFAULT, PROCESS_IS_SUCCESS/CODE/OUTPUT_STATUS, and IO_COPY_N bounded handle copy.
- Still blocked without redesign: true `format!`, Condvar/Barrier, process env maps/Stdio objects, path component iterators, thread stack/name builder ABI.


## Notes (2026-07-13 BOOL/F32/F64/CHAR Default constants + RESULT_DEFAULT)
- Landed `BOOL_DEFAULT`, `NUM_F32_DEFAULT`, `NUM_F64_DEFAULT` in `sa_std/num.sal`; `CHAR_DEFAULT` in `sa_std/char.sal`; `RESULT_DEFAULT` macro (Ok(0)) in `sa_std/core/result.sa`.
- Numeric defaults test extended to cover all four new constants; default types test extended to cover `RESULT_DEFAULT` (panic ID 10463 -> 10464); full suite green.
- Fixed `RESULT_DEFAULT` test: do NOT pre-alloc the register before calling the macro (it allocates internally, like `OPTION_DEFAULT`/`OPTION_NEW_NONE`).
- Still blocked without redesign: true `format!`, Condvar/Barrier, process env maps/Stdio objects, path component iterators, thread stack/name builder ABI.

## Notes (2026-07-13 INTO/TRY_INTO/SAT_INTO aliases + PTR_SWAP_NONOVERLAPPING_U64)
- Landed 56 `INTO_*` / `TRY_INTO_*` / `SAT_INTO_*` Rust-named aliases in `sa_std/convert.sa` as wrappers over existing `FROM_*` / `TRY_FROM_*` / `SAT_FROM_*` macros; `PTR_SWAP_NONOVERLAPPING_U64` in `sa_std/ptr.sa`.
- New test file `std_into_naming_macro_surface.sa` (2 tests, panic IDs 10465/10466); fully integrated into `macro_surface_suites` in `runner.zig`.
- Still blocked without redesign: true `format!`, Condvar/Barrier, process env maps/Stdio objects, path component iterators, thread stack/name builder ABI.

## Notes (2026-07-13 DEFAULT_F32/F64/CHAR + RANGE_INCLUSIVE_U64_DEFAULT)
- Landed `DEFAULT_F32`, `DEFAULT_F64`, `DEFAULT_CHAR` macros in `sa_std/default.sa`; `RANGE_INCLUSIVE_U64_DEFAULT` in `sa_std/ops.sa`.
- Numeric defaults and default types tests extended; focused tests passing.
- Still blocked without redesign: true `format!`, Condvar/Barrier, process env maps/Stdio objects, path component iterators, thread stack/name builder ABI.

## Notes (2026-07-13 CELL_DEFAULT + REFCELL_DEFAULT legacy aliases)
- Landed `CELL_DEFAULT` in `sa_std/core/cell.sa` (alias for `CELL_NEW`); `REFCELL_DEFAULT` in `sa_std/core/refcell.sa` (zero-init value + borrows).
- Focused temp tests passed individually; full suite build running.
- Still blocked without redesign: true `format!`, Condvar/Barrier, process env maps/Stdio objects, path component iterators, thread stack/name builder ABI.

## Notes (2026-07-13 IO_ERROR_KIND + ERROR_CODE + ERROR_REF_IS expansion)
- Landed 33 new `IO_ERROR_KIND_*` constants in `sa_std/io.sal` covering full Rust `io::ErrorKind` enum; 19 new `ERROR_CODE_*` constants in `sa_std/error.sal`; 19 new `ERROR_REF_IS_*` helper macros in `sa_std/error.sa`.
- New test file `std_io_error_kinds_macro_surface.sa` (2 tests, panic IDs 10467/10468), registered in `macro_surface_suites` in `runner.zig`.
- Still blocked without redesign: true `format!`, Condvar/Barrier, process env maps/Stdio objects, path component iterators, thread stack/name builder ABI.

## Active std parity batch (2026-07-13 o)

Completed supportable defaults/aliases/macros:
- 5 unsigned MIN constants in num.sal (NUM_U8/U16/U32/U64/usize_MIN = 0), mirroring Rust u*::MIN.
- 10 BYTES constants in num.sal (NUM_U8_BYTES=1 through NUM_ISIZE_BYTES=8), mirroring Rust 1.60+ stabilized <integer>::BYTES.
- 13 f32 associated constants as IEEE 754 bit patterns (INFINITY, NEG_INFINITY, NAN, ZERO, MINUS_ZERO, MIN_POSITIVE, MAX, MIN, EPSILON, MAX_SUBNORMAL, MIN_SUBNORMAL, BITS, BYTES).
- 13 f64 associated constants as IEEE 754 bit patterns (same set as f32 but 64-bit bit widths).
- WrappingU64/U32/I64 and SaturatingU64/I64 layout constants (8-byte transparent struct wrappers).
- DEFAULT_WRAPPING_U64 and DEFAULT_SATURATING_U64 zero-init macros in default.sa.
- Test file std_float_wrapping_macro_surface.sa (panic IDs 10473/10474).

Panic IDs next free: 10475+.
Still blocked without redesign: true format!, Condvar/Barrier, process env maps/Stdio objects, path component iterators, thread stack/name builder ABI.

## Active std parity batch (2026-07-13 p)

Completed supportable defaults/aliases/macros:
- 11 Wrapping/Saturating construction/access macros in num.sa (WRAPPING_U64_NEW/GET/SET, WRAPPING_U32_NEW/GET, WRAPPING_I64_NEW/GET, SATURATING_U64_NEW/GET/SET, SATURATING_I64_NEW/GET).
- 7 Range<usize>/Bound<usize> layout constants in ops.sal (RangeUsize_SIZE, RangeInclusiveUsize_SIZE, RangeFromUsize_SIZE, RangeToUsize_SIZE, RangeToInclusiveUsize_SIZE, BoundUsize_SIZE + field offsets).
- 11 RANGE_USIZE_* alias macros in ops.sa wrapping existing RANGE_U64_* macros.
- Test file std_wrapping_range_macro_surface.sa (panic IDs 10475/10476).

Panic IDs next free: 10477+.
Still blocked without redesign: true format!, Condvar/Barrier, process env maps/Stdio objects, path component iterators, thread stack/name builder ABI.

## Active std parity batch (2026-07-13 q)

Completed supportable defaults/aliases/macros:
- 8 new mem size/align constants in mem.sal (MEM_SIZE_F32/4, MEM_ALIGN_F32/4, MEM_SIZE_F64/8, MEM_ALIGN_F64/8, MEM_SIZE_PTR/8, MEM_ALIGN_PTR/8, MEM_SIZE_CHAR/4, MEM_ALIGN_CHAR/4).
- Test file std_mem_size_macro_surface.sa (panic ID 10477).

Panic IDs next free: 10478+.
Still blocked without redesign: true format!, Condvar/Barrier, process env maps/Stdio objects, path component iterators, thread stack/name builder ABI.

## Active std parity batch (2026-07-13 r)

Completed supportable defaults/aliases/macros:
- 12 f32/f64 Digits/Radix/Exp constants in num.sal (NUM_F32_DIGITS=6, NUM_F32_RADIX=2, NUM_F32_MIN_EXP=-125, NUM_F32_MAX_EXP=128, NUM_F32_MIN_10_EXP=-37, NUM_F32_MAX_10_EXP=38, plus matching NUM_F64_* for digits=15, radix=2, min_exp=-1021, max_exp=1024, min_10_exp=-307, max_10_exp=308).
- 8 MEM_SIZE_OF_* / MEM_ALIGN_OF_* macros in mem.sa for f32, f64, ptr, char.
- Test file std_float_constants_macro_surface.sa (panic ID 10478).

Panic IDs next free: 10479+.
Still blocked without redesign: true format!, Condvar/Barrier, process env maps/Stdio objects, path component iterators, thread stack/name builder ABI.

## Active std parity batch (2026-07-14 r confirmed)

Completed supportable defaults/aliases/macros:
- 14 f32/f64 associated constants in num.sal: MANTISSA_DIGITS (24/53), DIGITS (6/15), RADIX (2/2), MIN_EXP (-125/-1021), MAX_EXP (128/1024), MIN_10_EXP (-37/-307), MAX_10_EXP (38/308).
- 8 MEM_SIZE_OF_* / MEM_ALIGN_OF_* macros in mem.sa for f32, f64, ptr, char.
- Test file std_float_constants_macro_surface.sa (panic ID 10478).

Full `zig build unit-framework --summary all` passes: 6/6 steps, 5/5 tests passed.

Panic IDs next free: 10479+.
Still blocked without redesign: true format!, Condvar/Barrier, process env maps/Stdio objects, path component iterators, thread stack/name builder ABI.

## Active std parity batch (2026-07-14 s)

Completed supportable defaults/aliases/macros:
- 10 Wrapping/Saturating MIN/MAX constants in num.sal (WRAPPING_U64/U32/I64_MIN/MAX, SATURATING_U64/I64_MIN/MAX).
- 6 Wrapping/Saturating struct-aware arithmetic macros in num.sa (WRAPPING_U64_ADD/SUB/MUL, SATURATING_U64_ADD/SUB/MUL) that read/write through Wrapping/Saturating struct layouts.
- Test file std_wrapping_arith_macro_surface.sa (panic ID 10479).

Panic IDs next free: 10480+.
Still blocked without redesign: true format!, Condvar/Barrier, process env maps/Stdio objects, path component iterators, thread stack/name builder ABI.

## Active std parity batch (2026-07-14 t)

Completed supportable defaults/aliases/macros:
- 5 Atomic Ordering enum constants in sync/atomic.sal (RELAXED=0, RELEASE=1, ACQUIRE=2, ACQ_REL=3, SEQ_CST=4) mirroring Rust std::sync::atomic::Ordering.
- Test file std_atomic_ordering_macro_surface.sa (panic ID 10480).

Panic IDs next free: 10481+.
Still blocked without redesign: true format!, Condvar/Barrier, process env maps/Stdio objects, path component iterators, thread stack/name builder ABI.
## Active std parity batch (2026-07-14 w)

Completed supportable defaults/aliases/macros:
- OsStr/OsString layout constants in ffi.sal (6 constants, both = Slice_SIZE on Unix).
- OS_STR_FROM_BYTES_OK/INTERIOR_NUL/TO_STR_INVALID_UTF8 error codes in ffi.sal (3 constants).
- MutexGuard layout: SIZE/rwlock/data in sync/mutex.sal (3 constants).
- RwLockReadGuard and RwLockWriteGuard layout in sync/rwlock.sal (6 constants).
- Test file std_ffi_osstr_layout_macro_surface.sa (panic IDs 10483/10484).

Panic IDs next free: 10485+.
Still blocked without redesign: true format!, Condvar/Barrier, process env maps/Stdio objects, path component iterators, thread stack/name builder ABI.
## Active std parity batch (2026-07-14 x)

Completed supportable defaults/aliases/macros:
- Duration_SIZE/nanos/ZERO/MIN/MAX in time.sal (5 constants).
- Instant_SIZE/nanos, SystemTime_SIZE/nanos/UNIX_EPOCH in time.sal (5 constants).
- Test file std_time_duration_layout_macro_surface.sa (panic ID 10485).

Panic IDs next free: 10486+.
Still blocked without redesign: true format!, Condvar/Barrier, process env maps/Stdio objects, path component iterators, thread stack/name builder ABI.
## Active std parity batch (2026-07-14 y)

Completed supportable defaults/aliases/macros:
- 5 IntErrorKind enum constants in num.sal (EMPTY/INVALID_DIGIT/POS_OVERFLOW/NEG_OVERFLOW/ZERO).
- ParseIntError layout (SIZE/code/msg) in num.sal.
- Test file std_int_error_kind_macro_surface.sa (panic ID 10486).

Panic IDs next free: 10487+.
Still blocked without redesign: true format!, Condvar/Barrier, process env maps/Stdio objects, path component iterators, thread stack/name builder ABI.
## Active std parity batch (2026-07-14 z)

Completed supportable defaults/aliases/macros:
- TryFromIntError layout + POS/NEG overflow error codes in num.sal (4 constants).
- TryFromSliceError layout + LENGTH_MISMATCH error code in core/slice.sal (3 constants).
- Test file std_try_from_error_macro_surface.sa (panic ID 10487).

Panic IDs next free: 10488+.
Still blocked without redesign: true format!, Condvar/Barrier, process env maps/Stdio objects, path component iterators, thread stack/name builder ABI.
## Active std parity batch (2026-07-14 aa)

Completed supportable defaults/aliases/macros:
- 20 NonZero*::BITS/BYTES associated constants in num.sal mirroring Rust 1.80+.
- Test file std_nonzero_bits_macro_surface.sa (panic ID 10488) cross-checking against NUM_*_BITS.

Panic IDs next free: 10489+.
Still blocked without redesign: true format!, Condvar/Barrier, process env maps/Stdio objects, path component iterators, thread stack/name builder ABI.
## Active std parity batch (2026-07-14 ab)

Completed supportable defaults/aliases/macros:
- OnceLock layout + 3 state aliases in sync/once.sal (4 constants).
- LazyLock layout + 3 state aliases in sync/once.sal (4 constants).
- Test file std_once_lock_layout_macro_surface.sa (panic ID 10489) cross-checking OnceLock/LazyLock/Once sizes.

Panic IDs next free: 10490+.
Still blocked without redesign: true format!, Condvar/Barrier, process env maps/Stdio objects, path component iterators, thread stack/name builder ABI.
## Active std parity batch (2026-07-14 ac)

Completed supportable defaults/aliases/macros:
- New thread.sal with JoinHandle layout (SIZE/handle/result) and THREAD_DEFAULT_ID sentinel (4 constants).
- Test file std_joinhandle_layout_macro_surface.sa (panic ID 10490).

Panic IDs next free: 10491+.
Still blocked without redesign: true format!, Condvar/Barrier, process env maps/Stdio objects, path component iterators, thread stack/name builder ABI.

## Active std parity batch (2026-07-14 ad)

Completed supportable defaults/aliases/macros:
- char layout constants in char.sal (CHAR_SIZE=4, CHAR_ALIGN=4), cross-checking Rust char's u32-sized scalar representation.
- char associated constant aliases in char.sal: CHAR_REPLACEMENT_CHARACTER, CHAR_MAX_LEN_UTF8=4, and CHAR_MAX_LEN_UTF16=2.
- Test file std_char_constants_macro_surface.sa (panic ID 10491).

Panic IDs next free: 10492+.
Still blocked without redesign: true format!, Condvar/Barrier, process env maps/Stdio objects, path component iterators, thread stack/name builder ABI.

## Active std parity batch (2026-07-14 ae)

Completed supportable defaults/aliases/macros:
- char error layout constants in char.sal for ParseCharError, DecodeUtf16Error, CharTryFromError, and TryFromCharError.
- ParseCharError kind constants for EmptyString and TooManyChars, plus DecodeUtf16Error unpaired-surrogate payload offset.
- Test file std_char_error_layout_macro_surface.sa (panic ID 10492).

Panic IDs next free: 10493+.
Still blocked without redesign: true format!, Condvar/Barrier, process env maps/Stdio objects, path component iterators, thread stack/name builder ABI.

## Active std parity batch (2026-07-14 af)

Completed supportable defaults/aliases/macros:
- fmt Error zero-sized layout constants in fmt.sal (FmtError_SIZE=0, FmtError_ALIGN=1).
- fmt Result layout/tag aliases in fmt.sal over the existing Result layout, modeling std::fmt::Result as Result<(), Error> at the SA layout level.
- Test file std_fmt_layout_macro_surface.sa (panic ID 10493).

Panic IDs next free: 10494+.
Still blocked without redesign: true format!, Condvar/Barrier, process env maps/Stdio objects, path component iterators, thread stack/name builder ABI.

## Active std parity batch (2026-07-14 ag)

Completed supportable defaults/aliases/macros:
- FFI/string conversion error layout constants in ffi.sal for NulError, FromBytesWithNulError, Utf8Error, and IntoStringError.
- Error kind aliases connect FromBytesWithNulError variants to the existing CSTR_FROM_BYTES_* validation status codes.
- Test file std_ffi_error_layout_macro_surface.sa (panic ID 10494).

Panic IDs next free: 10495+.
Still blocked without redesign: true format!, Condvar/Barrier, process env maps/Stdio objects, path component iterators, thread stack/name builder ABI.

## Active std parity batch (2026-07-14 ah)

Completed supportable defaults/aliases/macros:
- RefCell borrow error zero-sized layout constants in core/refcell.sal for BorrowError and BorrowMutError.
- Test file std_refcell_error_layout_macro_surface.sa (panic ID 10495).

Panic IDs next free: 10496+.
Still blocked without redesign: true format!, Condvar/Barrier, process env maps/Stdio objects, path component iterators, thread stack/name builder ABI.

## Active std parity batch (2026-07-14 ai)

Completed supportable defaults/aliases/macros:
- Panic location layout constants in core/panic.sal for Rust `Location`: file fat-pointer view, line, and column offsets.
- AssertUnwindSafeU64 concrete wrapper layout constants in core/panic.sal.
- Test file std_panic_layout_macro_surface.sa (panic ID 10496).

Panic IDs next free: 10497+.
Still blocked without redesign: true format!, Condvar/Barrier, process env maps/Stdio objects, path component iterators, thread stack/name builder ABI.

## Active std parity batch (2026-07-14 aj)

Completed supportable defaults/aliases/macros:
- String/str conversion error layout constants in string.sal for FromUtf8Error, FromUtf16Error, and ParseBoolError.
- FromUtf8Error layout cross-checks the existing Vec and Utf8Error layouts; FromUtf16Error records strict UTF-16 failure kind values for lone surrogate and odd byte input.
- Test file std_string_error_layout_macro_surface.sa (panic ID 10497).

Panic IDs next free: 10498+.
Still blocked without redesign: true format!, Condvar/Barrier, process env maps/Stdio objects, path component iterators, thread stack/name builder ABI.

## Active std parity batch (2026-07-14 ak)

Completed supportable defaults/aliases/macros:
- Net address parse error layout constants in net.sal for Rust `AddrParseError`.
- AddrParseError kind constants cover Ip, Ipv4, Ipv6, Socket, SocketV4, and SocketV6 parser failure categories.
- Test file std_net_error_layout_macro_surface.sa (panic ID 10498).

Panic IDs next free: 10499+.
Still blocked without redesign: true format!, Condvar/Barrier, process env maps/Stdio objects, path component iterators, thread stack/name builder ABI.

## Active std parity batch (2026-07-14 al)

Completed supportable defaults/aliases/macros:
- Float parsing error layout constants in num.sal for Rust `ParseFloatError`.
- Float error kind constants cover Empty and Invalid parser failure categories from Rust's `FloatErrorKind`.
- Test file std_float_error_layout_macro_surface.sa (panic ID 10499).

Panic IDs next free: 10500+.
Still blocked without redesign: true format!, Condvar/Barrier, process env maps/Stdio objects, path component iterators, thread stack/name builder ABI.

## Active std parity batch (2026-07-14 am)

Completed supportable defaults/aliases/macros:
- Alloc layout constants in alloc/layout.sal for Rust `core::alloc::Layout` at the SA macro-layout level.
- Zero-sized LayoutError/LayoutErr and AllocError marker layout constants.
- Test file std_alloc_layout_macro_surface.sa (panic ID 10500).

Panic IDs next free: 10501+.
Still blocked without redesign: true format!, Condvar/Barrier, process env maps/Stdio objects, path component iterators, thread stack/name builder ABI.

## Active std parity batch (2026-07-14 an)

Completed supportable defaults/aliases/macros:
- MPSC error layout constants in sync/mpsc.sal for SendError<u64>, RecvError, TryRecvError, RecvTimeoutError, and TrySendError<u64>.
- Error kind constants cover Empty/Disconnected, Timeout/Disconnected, and Full/Disconnected categories from Rust `std::sync::mpsc`.
- Test file std_mpsc_error_layout_macro_surface.sa (panic ID 10501).

Panic IDs next free: 10502+.
Still blocked without redesign: true format!, Condvar/Barrier, process env maps/Stdio objects, path component iterators, thread stack/name builder ABI.

## Active std parity batch (2026-07-14 ao)

Completed supportable defaults/aliases/macros:
- SystemTimeError layout constants in time.sal, modeling Rust `std::time::SystemTimeError(Duration)` over the existing SA Duration layout.
- Test file std_time_error_layout_macro_surface.sa (panic ID 10502).

Panic IDs next free: 10503+.
Still blocked without redesign: true format!, Condvar/Barrier, process env maps/Stdio objects, path component iterators, thread stack/name builder ABI.

## Active std parity batch (2026-07-14 ap)

Completed supportable defaults/aliases/macros:
- Sync poison error layout constants in sync/poison.sal for PoisonError<u64> and TryLockError<u64>.
- TryLockError kind constants cover Poisoned and WouldBlock categories from Rust `std::sync`.
- Test file std_sync_poison_error_layout_macro_surface.sa (panic ID 10503).

Panic IDs next free: 10504+.
Still blocked without redesign: true format!, Condvar/Barrier, process env maps/Stdio objects, path component iterators, thread stack/name builder ABI.

## Active std parity batch (2026-07-14 aq)

Completed supportable defaults/aliases/macros:
- Collections try-reserve error layout constants in collections.sal for TryReserveErrorKind and TryReserveError.
- TryReserveError kind constants cover CapacityOverflow and AllocError, with AllocError carrying the existing AllocLayout payload.
- Test file std_collections_try_reserve_error_layout_macro_surface.sa (panic ID 10504).

Panic IDs next free: 10505+.
Still blocked without redesign: true format!, Condvar/Barrier, process env maps/Stdio objects, path component iterators, thread stack/name builder ABI.

## Active std parity batch (2026-07-14 ar)

Completed supportable defaults/aliases/macros:
- Ops ControlFlow concrete layout constants in ops.sal for ControlFlowU64 tag/value layout.
- ControlFlow Continue/Break kind constants and u64 constructor/query macros in ops.sa.
- Test file std_ops_control_flow_macro_surface.sa (panic ID 10505).

Panic IDs next free: 10506+.
Still blocked without redesign: true format!, Condvar/Barrier, process env maps/Stdio objects, path component iterators, thread stack/name builder ABI.

## Active std parity batch (2026-07-14 as)

Completed supportable defaults/aliases/macros:
- OnceState layout constants in sync/once.sal matching the local Rust Linux/futex backend view: poisoned byte plus set_state_to primitive.
- OnceState futex state constants for COMPLETE/RUNNING/POISONED/INCOMPLETE/QUEUED/MASK and query/update macros in sync/once.sa.
- Test file std_once_state_layout_macro_surface.sa (panic ID 10506).

Panic IDs next free: 10507+.
Still blocked without redesign: true format!, Condvar/Barrier, process env maps/Stdio objects, path component iterators, thread stack/name builder ABI.

## Active std parity batch (2026-07-14 at)

Completed supportable defaults/aliases/macros:
- AtomicOrdering layout constants in sync/atomic.sal for Rust std::sync::atomic::Ordering's one-byte enum view.
- Atomic ordering constructor/getter and load/store/failure/fence validation predicate macros in sync/atomic.sa.
- Test file std_atomic_ordering_layout_macro_surface.sa (panic ID 10507).

Panic IDs next free: 10508+.
Still blocked without redesign: true format!, Condvar/Barrier, process env maps/Stdio objects, path component iterators, thread stack/name builder ABI.

## Active std parity batch (2026-07-14 au)

Completed supportable defaults/aliases/macros:
- Bound<usize> discriminant aliases and constructor/access/default/contains macros in ops.sal and ops.sa, mirroring Rust core::ops::Bound's Included/Excluded/Unbounded variant order over the current 64-bit SA usize layout.
- Test file std_ops_bound_usize_macro_surface.sa (panic ID 10508).

Panic IDs next free: 10509+.
Still blocked without redesign: true format!, Condvar/Barrier, process env maps/Stdio objects, path component iterators, thread stack/name builder ABI.

## Active std parity batch (2026-07-14 av)

Completed supportable defaults/aliases/macros:
- Range<usize> finite cursor/count/slice-view aliases in ops.sa, plus RangeFrom/RangeTo/RangeInclusive/RangeToInclusive<usize> constructor/access/contains/slice-view aliases over the current 64-bit SA usize layout.
- Test file std_ops_range_usize_macro_surface.sa (panic ID 10509).

Panic IDs next free: 10510+.
Still blocked without redesign: true format!, Condvar/Barrier, process env maps/Stdio objects, path component iterators, thread stack/name builder ABI.

## Active std parity batch (2026-07-14 aw)

Completed supportable defaults/aliases/macros:
- RangeInclusive<u64> and RangeInclusive<usize> into_inner macros in ops.sa, mirroring Rust core::ops::RangeInclusive::into_inner over the existing concrete layouts.
- Test file std_ops_range_inclusive_inner_macro_surface.sa (panic ID 10510).

Panic IDs next free: 10511+.
Still blocked without redesign: true format!, Condvar/Barrier, process env maps/Stdio objects, path component iterators, thread stack/name builder ABI.

## Active std parity batch (2026-07-14 ax)

Completed supportable defaults/aliases/macros:
- Concrete RangeBounds/IntoBounds-style bound extraction macros for RangeFull, Range, RangeFrom, RangeTo, RangeInclusive, and RangeToInclusive over u64 and usize Bound layouts.
- RangeInclusive end-bound helpers mirror Rust's exhausted behavior by returning Excluded(end) once exhausted is set.
- Test file std_ops_range_bounds_macro_surface.sa (panic ID 10511).

Panic IDs next free: 10512+.
Still blocked without redesign: true format!, Condvar/Barrier, process env maps/Stdio objects, path component iterators, thread stack/name builder ABI.

## Active std parity batch (2026-07-14 ay)

Completed supportable defaults/aliases/macros:
- Bound<u64> and Bound<usize> copy/copied/cloned aliases plus concrete map helpers in ops.sa, mirroring Rust Bound::map's tag-preserving behavior for Included/Excluded and callback bypass for Unbounded.
- Test file std_ops_bound_map_macro_surface.sa (panic ID 10512).

Panic IDs next free: 10513+.
Still blocked without redesign: true format!, Condvar/Barrier, process env maps/Stdio objects, path component iterators, thread stack/name builder ABI.

## Active std parity batch (2026-07-14 az)

Completed supportable defaults/aliases/macros:
- Bound<u64> and Bound<usize> concrete range is_empty helpers in ops.sa, mirroring Rust RangeBounds::is_empty bound-pair rules for unbounded, inclusive, and exclusive endpoints.
- Test file std_ops_bound_range_empty_macro_surface.sa (panic ID 10513).

Panic IDs next free: 10514+.
Still blocked without redesign: true format!, Condvar/Barrier, process env maps/Stdio objects, path component iterators, thread stack/name builder ABI.

## Active std parity batch (2026-07-14 ba)

Completed supportable defaults/aliases/macros:
- Bound<u64> and Bound<usize> concrete start/end/range intersection helpers in ops.sa, mirroring Rust IntoBounds::intersect bound-selection rules over the existing concrete Bound layouts.
- Test file std_ops_bound_intersect_macro_surface.sa (panic ID 10514).

Panic IDs next free: 10515+.
Still blocked without redesign: true format!, Condvar/Barrier, process env maps/Stdio objects, path component iterators, thread stack/name builder ABI.

## Active std parity batch (2026-07-14 bb)

Completed supportable defaults/aliases/macros:
- BoundU64Ref and BoundUsizeRef concrete tag+pointer layouts in ops.sal for Rust Bound<&u64> / Bound<&usize> lowering.
- Bound<u64> and Bound<usize> as_ref/as_mut macros plus ref copied/cloned helpers in ops.sa, mirroring Rust Bound::as_ref/as_mut and Bound<&T>::copied/cloned at the concrete pointer-layout level.
- Test file std_ops_bound_ref_macro_surface.sa (panic ID 10515).

Panic IDs next free: 10516+.
Still blocked without redesign: true format!, Condvar/Barrier, process env maps/Stdio objects, path component iterators, thread stack/name builder ABI.

## Active std parity batch (2026-07-14 bc)

Completed supportable defaults/aliases/macros:
- ControlFlow<u64, u64> concrete value/result/map helpers in ops.sa: break_value, continue_value, break_ok, continue_ok, map_break, map_continue, and into_value.
- Test file std_ops_control_flow_methods_macro_surface.sa (panic ID 10516).

Panic IDs next free: 10517+.
Still blocked without redesign: true format!, Condvar/Barrier, process env maps/Stdio objects, path component iterators, thread stack/name builder ABI.

## Active std parity batch (2026-07-14 bd)

Completed supportable defaults/aliases/macros:
- Concrete primitive std::convert::identity lowering macros in convert.sa for u64, i64, usize, and bool, plus Rust-named IDENTITY_* aliases.
- Test file std_convert_identity_macro_surface.sa (panic ID 10517).

Panic IDs next free: 10518+.
Still blocked without redesign: true format!, Condvar/Barrier, process env maps/Stdio objects, path component iterators, thread stack/name builder ABI.

## Active std parity batch (2026-07-14 be)

Completed supportable defaults/aliases/macros:
- Concrete array rsplit helpers in array.sa: ARRAY_TRY_RSPLIT_ARRAY_REF_U64 and ARRAY_TRY_RSPLIT_ARRAY_MUT_U64, mirroring Rust rsplit_array_ref/rsplit_array_mut over existing Slice views.
- Test file std_array_rsplit_macro_surface.sa (panic ID 10518).

Panic IDs next free: 10519+.
Still blocked without redesign: true format!, Condvar/Barrier, process env maps/Stdio objects, path component iterators, thread stack/name builder ABI.

## Active std parity batch (2026-07-14 bf)

Completed supportable defaults/aliases/macros:
- Concrete array AsRef/AsMut/Borrow/BorrowMut slice-view aliases in array.sa for u64 arrays.
- Test file std_array_ref_borrow_macro_surface.sa (panic ID 10519).

Panic IDs next free: 10520+.
Still blocked without redesign: true format!, Condvar/Barrier, process env maps/Stdio objects, path component iterators, thread stack/name builder ABI.

## Active std parity batch (2026-07-14 bg)

Completed supportable defaults/aliases/macros:
- Concrete array TryFrom slice aliases in array.sa: ARRAY_TRY_FROM_SLICE_U64 and ARRAY_TRY_FROM_MUT_SLICE_U64, reusing same-length copy semantics.
- Test file std_array_try_from_slice_macro_surface.sa (panic ID 10520).

Panic IDs next free: 10521+.
Still blocked without redesign: true format!, Condvar/Barrier, process env maps/Stdio objects, path component iterators, thread stack/name builder ABI.

## Active std parity batch (2026-07-14 bh)

Completed supportable defaults/aliases/macros:
- Concrete array-ref TryFrom slice aliases in array.sa: ARRAY_REF_TRY_FROM_SLICE_U64 and ARRAY_MUT_REF_TRY_FROM_MUT_SLICE_U64, reusing exact-length Slice view checks.
- Test file std_array_ref_try_from_slice_macro_surface.sa (panic ID 10521).

Panic IDs next free: 10522+.
Still blocked without redesign: true format!, Condvar/Barrier, process env maps/Stdio objects, path component iterators, thread stack/name builder ABI.

## Active std parity batch (2026-07-14 bi)

Completed supportable defaults/aliases/macros:
- Concrete primitive array default fill helpers in array.sa for u64, i64, usize, and bool arrays, plus DEFAULT_ARRAY_* aliases.
- Test file std_array_default_macro_surface.sa (panic ID 10522).

Panic IDs next free: 10523+.
Still blocked without redesign: true format!, Condvar/Barrier, process env maps/Stdio objects, path component iterators, thread stack/name builder ABI.

## Active std parity batch (2026-07-14 bj)

Completed supportable defaults/aliases/macros:
- Concrete u64 array clone/copy aliases in array.sa: ARRAY_CLONE_U64, ARRAY_CLONE_FROM_U64, and ARRAY_COPY_FROM_U64.
- Test file std_array_clone_macro_surface.sa (panic ID 10523).

Panic IDs next free: 10524+.
Still blocked without redesign: true format!, Condvar/Barrier, process env maps/Stdio objects, path component iterators, thread stack/name builder ABI.

## Active std parity batch (2026-07-14 bk)

Completed supportable defaults/aliases/macros:
- Concrete u64 array equality aliases in array.sa: ARRAY_EQ_U64, ARRAY_NE_U64, and ARRAY_PARTIAL_EQ_U64.
- Test file std_array_eq_macro_surface.sa (panic ID 10524).

Panic IDs next free: 10525+.
Still blocked without redesign: true format!, Condvar/Barrier, process env maps/Stdio objects, path component iterators, thread stack/name builder ABI.

## Active std parity batch (2026-07-14 bl)

Completed supportable defaults/aliases/macros:
- Concrete u64 array ordering aliases in array.sa: ARRAY_CMP_U64, ARRAY_PARTIAL_CMP_U64, ARRAY_LT_U64, ARRAY_LE_U64, ARRAY_GT_U64, and ARRAY_GE_U64.
- Test file std_array_cmp_macro_surface.sa (panic ID 10525).

Panic IDs next free: 10526+.
Still blocked without redesign: true format!, Condvar/Barrier, process env maps/Stdio objects, path component iterators, thread stack/name builder ABI.

## Active std parity batch (2026-07-14 bm)

Completed supportable defaults/aliases/macros:
- Concrete u64 array Index/IndexMut aliases in array.sa: ARRAY_INDEX_U64 and ARRAY_INDEX_MUT_PTR_U64.
- Test file std_array_index_macro_surface.sa (panic ID 10526).

Panic IDs next free: 10527+.
Still blocked without redesign: true format!, Condvar/Barrier, process env maps/Stdio objects, path component iterators, thread stack/name builder ABI.

## Active std parity batch (2026-07-14 bn)

Completed supportable defaults/aliases/macros:
- Concrete u64 array iterator construction aliases in array.sa: ARRAY_ITER_U64, ARRAY_ITER_MUT_U64, ARRAY_REF_INTO_ITER_U64, and ARRAY_MUT_REF_INTO_ITER_U64.
- Test file std_array_iter_macro_surface.sa (panic ID 10527).

Panic IDs next free: 10528+.
Still blocked without redesign: true format!, Condvar/Barrier, process env maps/Stdio objects, path component iterators, thread stack/name builder ABI.

## Active std parity batch (2026-07-14 bo)

Completed supportable defaults/aliases/macros:
- Concrete u64 array hash aliases in array.sa: DEFAULT_HASHER_WRITE_ARRAY_U64 and ARRAY_HASH_U64.
- Test file std_array_hash_macro_surface.sa (panic ID 10528).

Panic IDs next free: 10529+.
Still blocked without redesign: true format!, Condvar/Barrier, process env maps/Stdio objects, path component iterators, thread stack/name builder ABI.

## Active std parity batch (2026-07-14 bp)

Completed supportable defaults/aliases/macros:
- Concrete BuildHasherDefault hash_one helpers in hash.sa for u64, str, u8 slices, and u64 slices.
- Test file std_hash_build_hasher_hash_one_macro_surface.sa (panic ID 10529).

Panic IDs next free: 10530+.
Still blocked without redesign: true format!, Condvar/Barrier, process env maps/Stdio objects, path component iterators, thread stack/name builder ABI.

## Active std parity batch (2026-07-14 bq)

Completed supportable defaults/aliases/macros:
- Concrete signed Hasher write aliases in hash.sa: DEFAULT_HASHER_WRITE_I8, DEFAULT_HASHER_WRITE_I16, DEFAULT_HASHER_WRITE_I32, and DEFAULT_HASHER_WRITE_ISIZE.
- Test file std_hash_signed_write_macro_surface.sa (panic ID 10530).

Panic IDs next free: 10531+.
Still blocked without redesign: true format!, Condvar/Barrier, process env maps/Stdio objects, path component iterators, thread stack/name builder ABI.

## Active std parity batch (2026-07-14 br)

Completed supportable defaults/aliases/macros:
- Concrete BuildHasherDefault zero-sized trait aliases in hash.sa: BUILD_HASHER_DEFAULT_CLONE, BUILD_HASHER_DEFAULT_COPY, BUILD_HASHER_DEFAULT_EQ, and BUILD_HASHER_DEFAULT_NE.
- Test file std_hash_build_hasher_default_traits_macro_surface.sa (panic ID 10531).

Panic IDs next free: 10532+.
Still blocked without redesign: true format!, Condvar/Barrier, process env maps/Stdio objects, path component iterators, thread stack/name builder ABI.

## Active std parity batch (2026-07-16 VecDeque push_mut aliases)

Completed supportable defaults/aliases/macros:
- Rust-named VecDeque mutating push aliases in vec_deque.sa: VEC_DEQUE_PUSH_BACK_MUT and VEC_DEQUE_PUSH_FRONT_MUT, forwarding to the existing raw-pointer slot helpers for Rust's push_back_mut / push_front_mut shape.
- Test file std_vec_deque_push_mut_alias_macro_surface.sa (panic ID 10699).

Panic IDs next free: 10700+.
Still blocked without redesign: scoped Rust mutable references/lifetimes, generic VecDeque<T>, lazy/range drain and splice iterator semantics, allocator-aware constructors, true format!, Condvar/Barrier, process env maps/Stdio objects, path component iterators, thread stack/name builder ABI.

## Active std parity batch (2026-07-16 VecDeque mut-slot aliases)

Completed supportable defaults/aliases/macros:
- Rust-named VecDeque mutable-slot aliases in vec_deque.sa: VEC_DEQUE_GET_MUT_PTR, VEC_DEQUE_GET_MUT, and VEC_DEQUE_INSERT_MUT, forwarding to the existing checked raw-pointer helpers for Rust's get_mut / insert_mut shapes.
- Test file std_vec_deque_mut_alias_macro_surface.sa (panic ID 10700).

Panic IDs next free: 10701+.
Still blocked without redesign: scoped Rust mutable references/lifetimes, generic VecDeque<T>, Rust Option/Panic object semantics, lazy/range drain and splice iterator semantics, allocator-aware constructors, true format!, Condvar/Barrier, process env maps/Stdio objects, path component iterators, thread stack/name builder ABI.

## Active std parity batch (2026-07-16 BinaryHeap pop_if helpers)

Completed supportable defaults/aliases/macros:
- Concrete BinaryHeap conditional-pop helpers in binary_heap.sa: BINARY_HEAP_TRY_POP_IF_U64 and BINARY_HEAP_POP_IF_U64, forwarding through try-peek and try-pop for Rust's unstable pop_if shape on the current u64 max-heap ABI.
- Test file std_binary_heap_pop_if_macro_surface.sa (panic ID 10701).

Panic IDs next free: 10702+.
Still blocked without redesign: generic BinaryHeap<T> ordering, Rust Option<T> object layout, scoped PeekMut guards/lifetimes, lazy iterator/drain adapters, allocator-aware constructors, true format!, Condvar/Barrier, process env maps/Stdio objects, path component iterators, thread stack/name builder ABI.

## Active std parity batch (2026-07-16 BinaryHeap iter helper)

Completed supportable defaults/aliases/macros:
- Concrete BinaryHeap shared iterator helper in binary_heap.sa: BINARY_HEAP_ITER_U64, constructing the existing slice-backed Iter cursor over the heap's internal array order.
- Test file std_binary_heap_iter_macro_surface.sa (panic ID 10702).

Panic IDs next free: 10703+.
Still blocked without redesign: generic BinaryHeap<T> ordering, Rust borrow/lifetime modeling, owned IntoIterator object semantics, scoped PeekMut guards, lazy drain adapters, allocator-aware constructors, true format!, Condvar/Barrier, process env maps/Stdio objects, path component iterators, thread stack/name builder ABI.

## Active std parity batch (2026-07-16 BinaryHeap iterator aliases)

Completed supportable defaults/aliases/macros:
- Concrete BinaryHeap iterator aliases in binary_heap.sa: BINARY_HEAP_REF_INTO_ITER_U64 for `IntoIterator for &BinaryHeap` style lowering, and BINARY_HEAP_ITER_DEFAULT_U64 for empty `binary_heap::Iter` default construction.
- Test file std_binary_heap_iter_alias_macro_surface.sa (panic ID 10703).

Panic IDs next free: 10704+.
Still blocked without redesign: generic BinaryHeap<T> ordering, Rust borrow/lifetime modeling, owned IntoIterator object semantics, scoped PeekMut guards, lazy drain adapters, allocator-aware constructors, true format!, Condvar/Barrier, process env maps/Stdio objects, path component iterators, thread stack/name builder ABI.

## Active std parity batch (2026-07-16 BinaryHeap into_iter helper)

Completed supportable defaults/aliases/macros:
- Concrete BinaryHeap consuming iterator helper in binary_heap.sa: BINARY_HEAP_INTO_ITER_U64, consuming the heap into an explicit backing Vec and returning a slice-backed Iter cursor over that Vec.
- Test file std_binary_heap_into_iter_macro_surface.sa (panic ID 10704).

Panic IDs next free: 10705+.
Still blocked without redesign: generic BinaryHeap<T> ordering, Rust owned IntoIter<T,A> object layout/drop glue, allocator-aware constructors, scoped PeekMut guards, lazy drain adapters, true format!, Condvar/Barrier, process env maps/Stdio objects, path component iterators, thread stack/name builder ABI.

## Active std parity batch (2026-07-16 BinaryHeap into_iter_sorted helper)

Completed supportable defaults/aliases/macros:
- Concrete BinaryHeap sorted consuming iterator helper in binary_heap.sa: BINARY_HEAP_INTO_ITER_SORTED_U64, consuming the heap and returning an explicit descending backing Vec plus slice-backed Iter cursor whose next values are greatest-first.
- Test file std_binary_heap_into_iter_sorted_macro_surface.sa (panic ID 10705).

Panic IDs next free: 10706+.
Still blocked without redesign: generic BinaryHeap<T> ordering, Rust IntoIterSorted<T,A> object layout/drop glue, lazy pop-on-next behavior, allocator-aware constructors, scoped PeekMut guards, lazy drain adapters, true format!, Condvar/Barrier, process env maps/Stdio objects, path component iterators, thread stack/name builder ABI.
