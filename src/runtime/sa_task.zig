//! sa_std goroutine runtime (sala 13_goroutine_runtime, phase 1).
//!
//! Go-style goroutines as an sa_std runtime core: the SA spec itself
//! is unchanged (frozen base); everything here is a library surface
//! of externs declared in sa_std/task.sai. Scope ruled by Jev
//! (2026-10-29, goroutine_scope_ruling.json):
//!   S1 virtual stacks + guard page + explicit trap on
//!      overflow; NO copying stack growth. DEF-R2 (2026-10-30,
//!      Jev def_r2_ruling: reserve_commit_grow 0.97): each task
//!      RESERVES a large virtual region (per-task cap, default
//!      64 MiB) and COMMITS pages on demand — when a running
//!      stack descends past its committed edge, the SIGSEGV
//!      handler commits the reserved span in place, so addresses
//!      never move and &local / out-param views stay valid.
//!      Exceeding the cap lands in the hard guard page and keeps
//!      the loud overflow abort.
//!   S2 cooperative preemption only: yield points are the explicit
//!      sa_task_yield extern plus every blocking runtime call; a
//!      compute-bound goroutine that never reaches a yield point
//!      can starve its carrier thread — documented, not silent.
//!   S5 x86_64 Linux only. Other targets return
//!      SA_STD_ERR_UNSUPPORTED from every entry point. wasm note:
//!      goroutines are possible on wasm in principle (Go's own wasm
//!      port proves it, via Asyncify / compiler stack transforms /
//!      stack-switching proposals), but this phase's mechanism —
//!      native stack-pointer switching — does not lower to wasm;
//!      wasm needs its own lowering track and reports UNSUPPORTED
//!      here. That is a mechanism difference, not a principled
//!      impossibility.
//!
//! Contracts registered explicitly (no silent degradation):
//!   - A blocking file syscall or a blocking FFI/extern call made
//!     inside a goroutine blocks its carrier OS thread for the
//!     duration. The scheduler does not compensate in this phase;
//!     callers that need many blocked threads must size carriers
//!     accordingly (SA_TASK_CARRIERS).
//!   - Network waits go through sa_task_net_wait, which parks the
//!     goroutine and lets the scheduler poll via the existing
//!     sa_std_net_poll_wait face; network I/O never needs to block
//!     a carrier.
//!   - Stack overflow is a loud trap: a SIGSEGV handler registered
//!     by the runtime first commits reserved pages on
//!     reserve-zone faults (DEF-R2 growth); a fault that reaches
//!     the hard guard page — the cap — is recognized, prints
//!     "sa_task: goroutine <id> stack overflow" and aborts. It is
//!     NOT boundary-recoverable in this phase (the stack is gone);
//!     boundary recover (below) covers runtime-raised traps only.
//!   - Deadlock guard: OFF by default, armed explicitly with
//!     sa_task_deadlock_guard_arm. Reason: threads that are not
//!     goroutines (e.g. a host main thread between API calls) are
//!     invisible to the scheduler, so an always-on detector could
//!     fire while an external participant is about to make
//!     progress. Arming is the program's declaration that all
//!     participants are goroutines or blocked inside a runtime
//!     call. When armed and the whole system is quiescent (live
//!     goroutines all parked, no timers, no net waiters, no
//!     external blocked callers) past the grace window, the
//!     runtime prints a deadlock trap and aborts — Go parity.
//!   - Goroutine structs are pooled and recycled by the registry;
//!     stacks (the expensive part) are unmapped at exit. A handle
//!     is (generation, slot) encoded; using a handle after its
//!     goroutine was reaped and the slot recycled returns
//!     SA_STD_ERR_INVALID_HANDLE.
//!
//! Boundary trap catch point (reserved for the SLA syntax batch's
//! goroutine-boundary panic/recover supervision semantics): every
//! goroutine runs under trampoline(), which arms a rescue context
//! (rescue_sp) before invoking user entry. Runtime-raised traps
//! (send on closed channel, negative WaitGroup counter, ...)
//! call raiseTrap(), which records {code, message} in the
//! Goroutine and switches back to the rescue context instead of
//! unwinding: the boundary then invokes the goroutine's trap
//! sink if one is registered, or performs the default process
//! trap (stderr + abort) when none is. The sink is a per-goroutine
//! function pointer (Goroutine.trap_sink) — settable from Zig
//! today (setTrapSink below, exercised by unit tests); the extern
//! registration surface (spawn-supervised + sa_task_trap_info
//! read-back after join) is the reserved API shape for the syntax
//! batch and lands with it, so the runtime does not need rework.
//!
//! Monitor reservation (Erlang-style exit notification, adopted
//! per Jev erl_candidates 0.81; runtime half reserved into v1 at
//! 0.58): goroutineExit() is the single convergence point of the
//! goroutine lifecycle — normal return and boundary trap both end
//! there, after the trap record is final and before join waiters
//! fire. That is the production point for exit notifications: a
//! monitor subscription registered on a goroutine would have its
//! notification (handle, exit kind, trap code) enqueued to the
//! subscriber's channel at exactly that point, deliverable through
//! ordinary channel/select waits. The delivery point needs no
//! scheduler surgery, so v1 only reserves the shape: the SLA
//! syntax batch adds the subscription surface (spawn-monitored +
//! a monitor registration extern mirroring the trap-sink shape);
//! no monitor extern ships in this phase.
//!
//! Context-style cancellation convention (std idiom over this
//! surface, no extra mechanism): a cancellation signal is an
//! ordinary sa_chan channel with capacity 0 that is closed to
//! broadcast "done"; closing wakes every blocked receiver and
//! every select case waiting on it, so a Done channel can be
//! selected on alongside work channels and passed down a call
//! chain. Cancellation is cooperative: receivers observe it at
//! channel/select points only.
//!
//! Status codes mirror sa_std.zig (SA_STD_*): OK=0,
//! INVALID_ARGUMENT=1, INVALID_HANDLE=2, NOT_FOUND=3,
//! NO_MEMORY=5, UNSUPPORTED=8, UNKNOWN=127. One task-local code:
//! SA_TASK_TRAPPED=100 is returned by sa_task_join when the
//! goroutine exited through the boundary trap with a sink
//! registered (details live in the goroutine's trap record).

const std = @import("std");
const builtin = @import("builtin");

const _t01 = @import("sa_task/t01.zig");
const _t02 = @import("sa_task/t02.zig");
const _t03 = @import("sa_task/t03.zig");
const _t04 = @import("sa_task/t04.zig");
const _t05 = @import("sa_task/t05.zig");
const _t06 = @import("sa_task/t06.zig");
const _t07 = @import("sa_task/t07.zig");
const _t08 = @import("sa_task/t08.zig");
const _t09 = @import("sa_task/t09.zig");

pub const supported = @import("sa_task/t01.zig").supported; pub const SA_TASK_OK = @import("sa_task/t01.zig").SA_TASK_OK; pub const SA_TASK_TRAPPED = @import("sa_task/t01.zig").SA_TASK_TRAPPED;
pub const SA_TASK_TRAP_SEND_ON_CLOSED = @import("sa_task/t01.zig").SA_TASK_TRAP_SEND_ON_CLOSED; pub const SA_TASK_TRAP_WAITGROUP_NEGATIVE = @import("sa_task/t01.zig").SA_TASK_TRAP_WAITGROUP_NEGATIVE;
pub const SA_TASK_TRAP_INTERNAL = @import("sa_task/t01.zig").SA_TASK_TRAP_INTERNAL; pub const RescueFrame = @import("sa_task/t01.zig").RescueFrame;
pub const EntryFn = @import("sa_task/t01.zig").EntryFn; pub const TrapSinkFn = @import("sa_task/t01.zig").TrapSinkFn; pub const Slot = @import("sa_task/t01.zig").Slot;
pub const DEFAULT_STACK_USABLE_KIB = @import("sa_task/t01.zig").DEFAULT_STACK_USABLE_KIB; pub const DEFAULT_STACK_CAP_KIB = @import("sa_task/t01.zig").DEFAULT_STACK_CAP_KIB;
pub const GUARD_KIB = @import("sa_task/t01.zig").GUARD_KIB; pub const STACK_GROW_QUANTUM = @import("sa_task/t01.zig").STACK_GROW_QUANTUM; pub const raiseTrap = @import("sa_task/t03.zig").raiseTrap;
pub const setTrapSink = @import("sa_task/t03.zig").setTrapSink; pub const sa_task_spawn = @import("sa_task/t03.zig").sa_task_spawn;
pub const sa_task_spawn_supervised = @import("sa_task/t03.zig").sa_task_spawn_supervised; pub const sa_task_trap_info = @import("sa_task/t03.zig").sa_task_trap_info;
pub const sa_task_monitor = @import("sa_task/t04.zig").sa_task_monitor; pub const sa_task_yield = @import("sa_task/t04.zig").sa_task_yield;
pub const sa_task_sleep_ns = @import("sa_task/t04.zig").sa_task_sleep_ns; pub const sa_task_sleep_ms = @import("sa_task/t04.zig").sa_task_sleep_ms;
pub const sa_task_join = @import("sa_task/t04.zig").sa_task_join; pub const sa_task_detach = @import("sa_task/t04.zig").sa_task_detach;
pub const sa_task_current = @import("sa_task/t04.zig").sa_task_current; pub const sa_task_live_count = @import("sa_task/t04.zig").sa_task_live_count;
pub const sa_task_deadlock_guard_arm = @import("sa_task/t04.zig").sa_task_deadlock_guard_arm; pub const SA_CHAN_CLOSED = @import("sa_task/t04.zig").SA_CHAN_CLOSED;
pub const SA_TASK_TRAP_CLOSE_OF_CLOSED = @import("sa_task/t04.zig").SA_TASK_TRAP_CLOSE_OF_CLOSED; pub const SA_CHAN_OP_RECV = @import("sa_task/t04.zig").SA_CHAN_OP_RECV;
pub const SA_CHAN_OP_SEND = @import("sa_task/t04.zig").SA_CHAN_OP_SEND; pub const sa_chan_make = @import("sa_task/t05.zig").sa_chan_make;
pub const sa_chan_destroy = @import("sa_task/t05.zig").sa_chan_destroy; pub const sa_chan_close = @import("sa_task/t05.zig").sa_chan_close;
pub const sa_chan_send = @import("sa_task/t05.zig").sa_chan_send; pub const sa_chan_recv = @import("sa_task/t05.zig").sa_chan_recv; pub const sa_chan_len = @import("sa_task/t05.zig").sa_chan_len;
pub const sa_chan_cap = @import("sa_task/t05.zig").sa_chan_cap; pub const sa_chan_select = @import("sa_task/t06.zig").sa_chan_select;
pub const SA_TASK_NET_READ = @import("sa_task/t07.zig").SA_TASK_NET_READ; pub const SA_TASK_NET_WRITE = @import("sa_task/t07.zig").SA_TASK_NET_WRITE;
pub const SA_TASK_NET_ERROR = @import("sa_task/t07.zig").SA_TASK_NET_ERROR; pub const PollFn = @import("sa_task/t07.zig").PollFn; pub const setPollHook = @import("sa_task/t07.zig").setPollHook;
pub const sa_task_net_wait = @import("sa_task/t07.zig").sa_task_net_wait; pub const sa_sync_mutex_new = @import("sa_task/t08.zig").sa_sync_mutex_new;
pub const sa_sync_rwlock_new = @import("sa_task/t08.zig").sa_sync_rwlock_new; pub const sa_sync_waitgroup_new = @import("sa_task/t08.zig").sa_sync_waitgroup_new;
pub const sa_sync_once_new = @import("sa_task/t08.zig").sa_sync_once_new; pub const sa_sync_destroy = @import("sa_task/t08.zig").sa_sync_destroy;
pub const sa_sync_mutex_lock = @import("sa_task/t08.zig").sa_sync_mutex_lock; pub const sa_sync_mutex_try_lock = @import("sa_task/t08.zig").sa_sync_mutex_try_lock;
pub const sa_sync_mutex_unlock = @import("sa_task/t08.zig").sa_sync_mutex_unlock; pub const sa_sync_rwlock_rlock = @import("sa_task/t08.zig").sa_sync_rwlock_rlock;
pub const sa_sync_rwlock_runlock = @import("sa_task/t08.zig").sa_sync_rwlock_runlock; pub const sa_sync_rwlock_lock = @import("sa_task/t08.zig").sa_sync_rwlock_lock;
pub const sa_sync_rwlock_unlock = @import("sa_task/t08.zig").sa_sync_rwlock_unlock; pub const sa_sync_waitgroup_add = @import("sa_task/t08.zig").sa_sync_waitgroup_add;
pub const sa_sync_waitgroup_done = @import("sa_task/t08.zig").sa_sync_waitgroup_done; pub const sa_sync_waitgroup_wait = @import("sa_task/t08.zig").sa_sync_waitgroup_wait;
pub const sa_sync_once_do = @import("sa_task/t08.zig").sa_sync_once_do;
