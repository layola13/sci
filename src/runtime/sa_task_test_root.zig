//! Standalone test root for the sa_task goroutine runtime.
//!
//! `zig test src/runtime/sa_task.zig` cannot link on its own:
//! sa_task declares `sa_std_net_poll_wait` as an extern, which
//! only sa_std.zig defines, and sa_std.zig is not part of a
//! standalone module test. This root imports sa_task (pulling
//! in all of its tests) and provides a stub definition of the
//! poll face so the standalone command links:
//!
//!   zig test src/runtime/sa_task_test_root.zig src/runtime/sa_task_ctx.s
//!
//! The stub is never the implementation under test: sa_task's
//! net tests install a deterministic fake through
//! sa_task.setPollHook before any net wait, and production
//! builds root at sa_std.zig, whose real export satisfies the
//! extern in the same compilation. If the stub ever IS reached
//! (a net wait with no hook installed in a standalone binary),
//! it answers SA_STD_ERR_UNSUPPORTED — loud, never a silent
//! park. This file is test scaffolding only; nothing in the
//! build graph imports it.

const sa_task = @import("sa_task.zig");

pub export fn sa_std_net_poll_wait(handles: ?[*]const u64, interests: ?[*]const u32, count: u64, timeout_ms: i32, ready: ?[*]u32, out_ready_count: ?*u64) i32 {
    _ = handles;
    _ = interests;
    _ = count;
    _ = timeout_ms;
    _ = ready;
    _ = out_ready_count;
    return 8; // SA_STD_ERR_UNSUPPORTED
}

test {
    _ = sa_task;
}
