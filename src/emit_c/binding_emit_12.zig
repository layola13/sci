pub fn emitTaskChanMake(writer: anytype, name: []const u8, uniform_arity: usize, gas: bool) !void {
    try writer.writeAll(" { uint64_t v = 0; int32_t st = sa_chan_make((uint32_t)a0, &v); sa_store_u64(a1, v); return (sa_u64)(sa_i64)st; } }\n");
}

pub fn emitTaskChanSend(writer: anytype, name: []const u8, uniform_arity: usize, gas: bool) !void {
    try writer.writeAll(" return (sa_u64)(sa_i64)sa_chan_send(a0, sa_glue_mptr(a1, 16)); }\n");
}

pub fn emitTaskChanRecv(writer: anytype, name: []const u8, uniform_arity: usize, gas: bool) !void {
    try writer.writeAll(" { uint32_t cl = 0; int32_t st = sa_chan_recv(a0, sa_glue_mptr(a1, 16), &cl); sa_store_u32(a2, (sa_u64)cl); return (sa_u64)(sa_i64)st; } }\n");
}

pub fn emitTaskSelect(writer: anytype, name: []const u8, uniform_arity: usize, gas: bool) !void {
    // Guest case/op/slot arrays are copied into host scratch;
    // the slot array is copied back (recv cases write into
    // it). Slot contents stay guest values end to end.
    try writer.writeAll(" { uint64_t n = a3; size_t cb = (size_t)n * 8; size_t ob = (size_t)n * 4; size_t sb = (size_t)n * 16; uint8_t *buf = (uint8_t *)malloc(cb + ob + sb == 0 ? 1 : cb + ob + sb); uint64_t *cases_h = (uint64_t *)(void *)buf; uint32_t *ops_h = (uint32_t *)(void *)(buf + cb); uint8_t *slots_h = buf + cb + ob; int64_t idx = -1; uint32_t cl = 0; int32_t st;");
    try writer.writeAll(" if (n != 0) { memcpy(cases_h, sa_glue_mptr(a0, cb), cb); memcpy(ops_h, sa_glue_mptr(a1, ob), ob); memcpy(slots_h, sa_glue_mptr(a2, sb), sb); }");
    try writer.writeAll(" st = sa_chan_select(cases_h, ops_h, slots_h, n, (uint32_t)a4, (sa_i64)a5, &idx, &cl);");
    try writer.writeAll(" if (n != 0) { memcpy(sa_glue_mptr(a2, sb), slots_h, sb); }");
    try writer.writeAll(" sa_store_u64(a6, (sa_u64)idx); sa_store_u32(a7, (sa_u64)cl); free(buf); return (sa_u64)(sa_i64)st; } }\n");
}

pub fn emitPthreadSpawn(writer: anytype, name: []const u8, uniform_arity: usize, gas: bool) !void {
    // Run the entry synchronously via the dispatcher, then hand
    // out a joinable handle (single-threaded staged semantics,
    // mirrors JS). Trailing zeros pad to dispatcher arity.
    try writer.writeAll(" { sa_call_indirect(a0, a1");
    var zi: usize = 1;
    while (zi < uniform_arity) : (zi += 1) {
        try writer.writeAll(", 0");
    }
    try writer.writeAll(");");
    try writer.writeAll(" { static sa_u64 next_thr = 1; return next_thr++; } } }\n");
}

pub fn emitPthreadJoin(writer: anytype, name: []const u8, uniform_arity: usize, gas: bool) !void {
    // Entry already ran inside spawn; nothing to wait for.
    try writer.writeAll(" return 0; }\n");
}

pub fn emitPthreadDrop(writer: anytype, name: []const u8, uniform_arity: usize, gas: bool) !void {
    try writer.writeAll(" return 0; }\n");
}

pub fn emitSqlite3Prepare(writer: anytype, name: []const u8, uniform_arity: usize, gas: bool) !void {
    try writer.writeAll(" return 0; }\n");
}

pub fn emitSqlite3Step(writer: anytype, name: []const u8, uniform_arity: usize, gas: bool) !void {
    // SQLITE_ROW so the row-present branch is taken (mirrors JS).
    try writer.writeAll(" return 100; }\n");
}

pub fn emitSqlite3Finalize(writer: anytype, name: []const u8, uniform_arity: usize, gas: bool) !void {
    try writer.writeAll(" return 0; }\n");
}

pub fn emitNaFamily(writer: anytype, name: []const u8, uniform_arity: usize, gas: bool) !void {
    try writer.writeAll(" return (sa_u64)sa_net_addr_family(a0); }\n");
}

pub fn emitNaFree(writer: anytype, name: []const u8, uniform_arity: usize, gas: bool) !void {
    // Fallible extern: the SA-level value is the status half
    // of the fallible pair (0 = SA_STD_OK on success).
    try writer.writeAll(" { sa_std_fallible_i32 r = sa_net_addr_free(a0); return (sa_u64)(sa_i64)r.status; } }\n");
}

pub fn emitNaPort(writer: anytype, name: []const u8, uniform_arity: usize, gas: bool) !void {
    try writer.writeAll(" return (sa_u64)sa_net_addr_port(a0); }\n");
}

pub fn emitTaskTryLock(writer: anytype, name: []const u8, uniform_arity: usize, gas: bool) !void {
    try writer.writeAll(" { uint32_t r = 0; int32_t st = sa_sync_mutex_try_lock(a0, &r); sa_store_u32(a1, (sa_u64)r); return (sa_u64)(sa_i64)st; } }\n");
}

pub fn emitTaskWgAdd(writer: anytype, name: []const u8, uniform_arity: usize, gas: bool) !void {
    try writer.writeAll(" return (sa_u64)(sa_i64)sa_sync_waitgroup_add(a0, (sa_i64)a1); }\n");
}

pub fn emitTaskOnceDo(writer: anytype, name: []const u8, uniform_arity: usize, gas: bool) !void {
    // The entry trampoline frees the context record when the
    // once actually runs; if the once was already done, the
    // entry never runs and the tiny record leaks (host glue).
    try writer.writeAll(" { sa_glue_task_ctx *c = (sa_glue_task_ctx *)malloc(sizeof(sa_glue_task_ctx)); int32_t st; c->entry = a1; c->arg = a2; st = sa_sync_once_do(a0, sa_glue_task_entry, c); return (sa_u64)(sa_i64)st; } }\n");
}

pub fn emitMmap(writer: anytype, name: []const u8, uniform_arity: usize, gas: bool) !void {
    // Anonymous zero-filled mapping stands in for the host page
    // (a1 = len; a0 fd is staged). Negative lengths trap inside
    // sa_alloc via the OOM check.
    try writer.writeAll(" return sa_alloc(a1); }\n");
}

pub fn emitMunmap(writer: anytype, name: []const u8, uniform_arity: usize, gas: bool) !void {
    try writer.writeAll(" return 0; }\n");
}

pub fn emitMemFree(writer: anytype, name: []const u8, uniform_arity: usize, gas: bool) !void {
    try writer.writeAll(" { sa_free(a0); return 0; } }\n");
}

pub fn emitMemcpy(writer: anytype, name: []const u8, uniform_arity: usize, gas: bool) !void {
    try writer.writeAll(" { uint32_t x = sa_checked_addr(a0, (size_t)a2);");
    try writer.writeAll(" uint32_t y = sa_checked_addr(a1, (size_t)a2);");
    try writer.writeAll(" memcpy(&sa_mem[x], &sa_mem[y], (size_t)a2);");
    try writer.writeAll(" return a0; } }\n");
}
