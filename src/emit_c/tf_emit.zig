const std = @import("std");
const sig = @import("../common/signature.zig");
const call = @import("../referee/call.zig");
const CBaseSet = @import("types.zig").CBaseSet;
const TfFnCtx = @import("types.zig").TfFnCtx;
const TfProgram = @import("types.zig").TfProgram;
const TfSyncInfo = @import("types.zig").TfSyncInfo;
const WidthMap = @import("types.zig").WidthMap;
const cFuncName = @import("ident.zig").cFuncName;
const cIdent = @import("ident.zig").cIdent;
const emitLinearInstruction = @import("linear.zig").emitLinearInstruction;
const resolveTextToC = @import("values.zig").resolveTextToC;
const resolveValueToC = @import("values.zig").resolveValueToC;
const sigNormName = @import("ident.zig").sigNormName;
const sigReturnWidth = @import("dead_slots.zig").sigReturnWidth;
const trackWidths = @import("widths.zig").trackWidths;

pub fn tfIdent(writer: anytype, fsig: sig.FunctionSig) !void {
    try cIdent(writer, sigNormName(fsig.name));
}

pub fn writeTfHeader(rw: anytype, verified: anytype, prog: *const TfProgram) !void {
    try rw.writeAll(
        \\/* ---- @gpu task-form machinery (TASKFORM_DESIGN.md) ---- */
        \\#define SA_TF_HDR 48
        \\#define SA_TF_OFF_FNID 0
        \\#define SA_TF_OFF_RESUME 4
        \\#define SA_TF_OFF_STATE 8
        \\#define SA_TF_OFF_JOIN 12
        \\#define SA_TF_OFF_PARENT 16
        \\#define SA_TF_OFF_RREG 24
        \\#define SA_TF_OFF_SIZE 28
        \\#define SA_TF_OFF_RESULT 32
        \\#define SA_TF_OFF_FREENEXT 40
        \\#define SA_TF_OFF_QNEXT 44
        \\#define SA_TF_REGOFF(i) (SA_TF_HDR + (sa_u64)(i) * 8ULL)
        \\#define SA_TF_NOREG 0xFFFFFFFFu
        \\#define SA_TF_STATE_RUNNING 0u
        \\#define SA_TF_STATE_SUSPENDED 1u
        \\#define SA_TF_STATE_DONE 2u
        \\#define SA_TF_NQ 1024
        \\#define SA_TF_DONATE_AT 32u
        \\#define SA_TF_DONATE_N 16u
        \\
    );
    try rw.print("#define SA_TF_NTF {d}\n", .{prog.count()});
    for (prog.fsig_of_fnid, 0..) |fidx, fid| {
        try rw.writeAll("#define SA_TF_FN_");
        try tfIdent(rw, verified.function_sigs[fidx]);
        try rw.print(" {d}\n", .{fid});
    }
    for (prog.fsig_of_fnid) |fidx| {
        try rw.writeAll("static void sa_tf_step_");
        try tfIdent(rw, verified.function_sigs[fidx]);
        try rw.writeAll("(sa_u64 fr);\n");
    }
    try rw.writeAll(
        \\static sa_u64 sa_tf_ld64(sa_u64 addr);
        \\static void sa_tf_st64(sa_u64 addr, sa_u64 v);
        \\static uint32_t sa_tf_ld32(sa_u64 addr);
        \\static void sa_tf_st32(sa_u64 addr, uint32_t v);
        \\static sa_u64 sa_tf_frame_new(uint32_t fnid, sa_u64 parent, uint32_t result_reg);
        \\static void sa_tf_queue_push(uint32_t fr);
        \\static void sa_tf_lq_push(uint32_t fr);
        \\static int sa_tf_sync_wait(sa_u64 fr);
        \\static void sa_tf_complete(sa_u64 fr, sa_u64 result);
        \\static void sa_tf_drive(void);
        \\static sa_u64 sa_tf_frame_result(sa_u64 fr);
        \\
    );
}

pub fn writeTfMachinery(rw: anytype, verified: anytype, prog: *const TfProgram) !void {
    // Atomic helpers and frame accessors come first: their host bodies
    // are single-line plain read/modify/write forms BY CONTRACT with
    // extract_device6.py (R13/R13b replace them, shape-asserted, in
    // the device TU). Do not reformat these lines.
    try rw.writeAll(
        \\/* ---- @gpu task-form machinery definitions ---- */
        \\static uint32_t sa_tf_at_add_u32(uint32_t *p, uint32_t v) { uint32_t o = *p; *p = (uint32_t)(o + v); return o; }
        \\static uint32_t sa_tf_at_exch_u32(uint32_t *p, uint32_t v) { uint32_t o = *p; *p = v; return o; }
        \\static uint32_t sa_tf_at_load_u32(uint32_t *p) { return *p; }
        \\static sa_u64 sa_tf_at_cas_u64(sa_u64 *p, sa_u64 c, sa_u64 v) { sa_u64 o = *p; if (o == c) *p = v; return o; }
        \\static sa_u64 sa_tf_at_load_u64(sa_u64 *p) { return *p; }
        \\static uint32_t sa_tf_at_add_m32(sa_u64 addr, uint32_t v) { uint32_t o = (uint32_t)sa_load_u32(addr); sa_store_u32(addr, o + v); return o; }
        \\static uint32_t sa_tf_at_exch_m32(sa_u64 addr, uint32_t v) { uint32_t o = (uint32_t)sa_load_u32(addr); sa_store_u32(addr, v); return o; }
        \\static uint32_t sa_tf_at_load_m32(sa_u64 addr) { return (uint32_t)sa_load_u32(addr); }
        \\static void sa_tf_at_store_m32(sa_u64 addr, uint32_t v) { sa_store_u32(addr, v); }
        \\static sa_u64 sa_tf_ld64(sa_u64 addr) { return sa_load_u64(addr); }
        \\static void sa_tf_st64(sa_u64 addr, sa_u64 v) { sa_store_u64(addr, v); }
        \\static uint32_t sa_tf_ld32(sa_u64 addr) { return (uint32_t)sa_load_u32(addr); }
        \\static void sa_tf_st32(sa_u64 addr, uint32_t v) { sa_store_u32(addr, v); }
        \\static uint32_t sa_tf_at_add_u32_lq(uint32_t *p, uint32_t v) { uint32_t o = *p; *p = (uint32_t)(o + v); return o; }
        \\static sa_u64 sa_tf_at_cas_u64_lq(sa_u64 *p, sa_u64 c, sa_u64 v) { sa_u64 o = *p; if (o == c) *p = v; return o; }
        \\static sa_u64 sa_tf_at_load_u64_lq(sa_u64 *p) { return *p; }
        \\static sa_u64 sa_tf_qtop_packed = 0;
        \\static uint32_t sa_tf_alive = 0;
        \\static sa_u64 sa_tf_free_head[SA_TF_NTF];
        \\static sa_u64 sa_tf_lq_packed[SA_TF_NQ];
        \\static uint32_t sa_tf_lq_len[SA_TF_NQ];
        \\static uint32_t sa_tf_qid_next = 0;
        \\
    );
    try rw.writeAll("static uint32_t sa_tf_fn_nregs(uint32_t fnid) {\n  switch (fnid) {\n");
    for (prog.fsig_of_fnid, 0..) |fidx, fid| {
        try rw.print("    case {d}: return {d};\n", .{ fid, verified.function_sigs[fidx].reg_ids.len });
    }
    try rw.writeAll("    default: sa_trap(\"sa_tf: bad fnid\"); return 0;\n  }\n}\n");
    try rw.writeAll(
        \\static sa_u64 sa_tf_frame_new(uint32_t fnid, sa_u64 parent, uint32_t result_reg) {
        \\  sa_u64 fr = 0;
        \\  for (;;) {
        \\    sa_u64 hd = sa_tf_at_load_u64(&sa_tf_free_head[fnid]);
        \\    uint32_t head = (uint32_t)hd;
        \\    sa_u64 nx;
        \\    if (head == 0) break;
        \\    nx = sa_tf_ld64((sa_u64)head + SA_TF_OFF_FREENEXT);
        \\    if (sa_tf_at_cas_u64(&sa_tf_free_head[fnid], hd, (((hd >> 32) + 1) << 32) | (nx & 0xFFFFFFFFULL)) == hd) { fr = (sa_u64)head; break; }
        \\  }
        \\  if (fr == 0) fr = sa_alloc(SA_TF_HDR + (sa_u64)sa_tf_fn_nregs(fnid) * 8ULL);
        \\  { uint32_t n = sa_tf_fn_nregs(fnid); uint32_t i; for (i = 0; i < n; i++) sa_tf_st64(fr + SA_TF_REGOFF(i), 0); }
        \\  sa_tf_st32(fr + SA_TF_OFF_FNID, fnid);
        \\  sa_tf_st32(fr + SA_TF_OFF_RESUME, 0);
        \\  sa_tf_at_store_m32(fr + SA_TF_OFF_STATE, SA_TF_STATE_RUNNING);
        \\  sa_tf_at_store_m32(fr + SA_TF_OFF_JOIN, 0);
        \\  sa_tf_st64(fr + SA_TF_OFF_PARENT, parent);
        \\  sa_tf_st32(fr + SA_TF_OFF_RREG, result_reg);
        \\  sa_tf_st32(fr + SA_TF_OFF_QNEXT, 0);
        \\  sa_tf_st32(fr + SA_TF_OFF_SIZE, SA_TF_HDR + sa_tf_fn_nregs(fnid) * 8u);
        \\  sa_tf_st64(fr + SA_TF_OFF_RESULT, 0);
        \\  if (parent != 0) (void)sa_tf_at_add_m32(parent + SA_TF_OFF_JOIN, 1);
        \\  (void)sa_tf_at_add_u32(&sa_tf_alive, 1);
        \\  return fr;
        \\}
        \\static void sa_tf_free_push(sa_u64 fr) {
        \\  uint32_t fnid = (uint32_t)sa_tf_ld32(fr + SA_TF_OFF_FNID);
        \\  for (;;) {
        \\    sa_u64 hd = sa_tf_at_load_u64(&sa_tf_free_head[fnid]);
        \\    sa_tf_st64(fr + SA_TF_OFF_FREENEXT, (sa_u64)(uint32_t)hd);
        \\    if (sa_tf_at_cas_u64(&sa_tf_free_head[fnid], hd, (((hd >> 32) + 1) << 32) | (fr & 0xFFFFFFFFULL)) == hd) break;
        \\  }
        \\}
        \\static void sa_tf_queue_push(uint32_t fr) {
        \\  for (;;) {
        \\    sa_u64 hd = sa_tf_at_load_u64(&sa_tf_qtop_packed);
        \\    sa_tf_st32(fr + SA_TF_OFF_QNEXT, (uint32_t)hd);
        \\    if (sa_tf_at_cas_u64(&sa_tf_qtop_packed, hd, (((hd >> 32) + 1) << 32) | (fr & 0xFFFFFFFFULL)) == hd) break;
        \\  }
        \\}
        \\static uint32_t sa_tf_queue_pop(void) {
        \\  for (;;) {
        \\    sa_u64 hd = sa_tf_at_load_u64(&sa_tf_qtop_packed);
        \\    uint32_t head = (uint32_t)hd;
        \\    uint32_t nx;
        \\    if (head == 0) return 0;
        \\    nx = (uint32_t)sa_tf_ld32((sa_u64)head + SA_TF_OFF_QNEXT);
        \\    if (sa_tf_at_cas_u64(&sa_tf_qtop_packed, hd, (((hd >> 32) + 1) << 32) | (nx & 0xFFFFFFFFULL)) == hd) return head;
        \\  }
        \\}
        \\static uint32_t sa_tf_qid(void) {
        \\  static __thread int32_t sa_tf_my_qid = -1;
        \\  if (sa_tf_my_qid < 0) sa_tf_my_qid = (int32_t)sa_tf_at_add_u32(&sa_tf_qid_next, 1u);
        \\  return (uint32_t)sa_tf_my_qid % SA_TF_NQ;
        \\}
        \\static void sa_tf_donate(uint32_t me) {
        \\  for (;;) {
        \\    sa_u64 hd = sa_tf_at_load_u64_lq(&sa_tf_lq_packed[me]);
        \\    uint32_t head = (uint32_t)hd;
        \\    uint32_t tail = 0;
        \\    uint32_t rest = 0;
        \\    uint32_t cur;
        \\    uint32_t k = 0;
        \\    if (head == 0) return;
        \\    cur = head;
        \\    while (k < SA_TF_DONATE_N) {
        \\      uint32_t nx = (uint32_t)sa_tf_ld32((sa_u64)cur + SA_TF_OFF_QNEXT);
        \\      k++;
        \\      tail = cur;
        \\      rest = nx;
        \\      if (nx == 0) break;
        \\      cur = nx;
        \\    }
        \\    if (sa_tf_at_cas_u64_lq(&sa_tf_lq_packed[me], hd, (((hd >> 32) + 1) << 32) | (rest & 0xFFFFFFFFULL)) == hd) {
        \\      for (;;) {
        \\        sa_u64 g = sa_tf_at_load_u64(&sa_tf_qtop_packed);
        \\        sa_tf_st32((sa_u64)tail + SA_TF_OFF_QNEXT, (uint32_t)g);
        \\        if (sa_tf_at_cas_u64(&sa_tf_qtop_packed, g, (((g >> 32) + 1) << 32) | (head & 0xFFFFFFFFULL)) == g) break;
        \\      }
        \\      (void)sa_tf_at_add_u32_lq(&sa_tf_lq_len[me], (uint32_t)(-(int32_t)k));
        \\      return;
        \\    }
        \\  }
        \\}
        \\static void sa_tf_lq_push(uint32_t fr) {
        \\  uint32_t me = sa_tf_qid();
        \\  for (;;) {
        \\    sa_u64 hd = sa_tf_at_load_u64_lq(&sa_tf_lq_packed[me]);
        \\    sa_tf_st32(fr + SA_TF_OFF_QNEXT, (uint32_t)hd);
        \\    if (sa_tf_at_cas_u64_lq(&sa_tf_lq_packed[me], hd, (((hd >> 32) + 1) << 32) | (fr & 0xFFFFFFFFULL)) == hd) break;
        \\  }
        \\  if (sa_tf_at_add_u32_lq(&sa_tf_lq_len[me], 1u) + 1u >= SA_TF_DONATE_AT) sa_tf_donate(me);
        \\}
        \\static uint32_t sa_tf_lq_pop(uint32_t me) {
        \\  for (;;) {
        \\    sa_u64 hd = sa_tf_at_load_u64_lq(&sa_tf_lq_packed[me]);
        \\    uint32_t head = (uint32_t)hd;
        \\    uint32_t nx;
        \\    if (head == 0) return 0;
        \\    nx = (uint32_t)sa_tf_ld32((sa_u64)head + SA_TF_OFF_QNEXT);
        \\    if (sa_tf_at_cas_u64_lq(&sa_tf_lq_packed[me], hd, (((hd >> 32) + 1) << 32) | (nx & 0xFFFFFFFFULL)) == hd) {
        \\      (void)sa_tf_at_add_u32_lq(&sa_tf_lq_len[me], (uint32_t)-1);
        \\      return head;
        \\    }
        \\  }
        \\}
        \\static int sa_tf_sync_wait(sa_u64 fr) {
        \\  if (sa_tf_at_load_m32(fr + SA_TF_OFF_JOIN) == 0) return 0;
        \\  (void)sa_tf_at_exch_m32(fr + SA_TF_OFF_STATE, SA_TF_STATE_SUSPENDED);
        \\  if (sa_tf_at_load_m32(fr + SA_TF_OFF_JOIN) == 0) {
        \\    if (sa_tf_at_exch_m32(fr + SA_TF_OFF_STATE, SA_TF_STATE_RUNNING) == SA_TF_STATE_SUSPENDED) return 0;
        \\    return 1;
        \\  }
        \\  return 1;
        \\}
        \\static void sa_tf_child_done(sa_u64 parent) {
        \\  uint32_t old = sa_tf_at_add_m32(parent + SA_TF_OFF_JOIN, (uint32_t)-1);
        \\  if (old == 1) {
        \\    if (sa_tf_at_exch_m32(parent + SA_TF_OFF_STATE, SA_TF_STATE_RUNNING) == SA_TF_STATE_SUSPENDED)
        \\      sa_tf_lq_push((uint32_t)parent);
        \\  }
        \\}
        \\static void sa_tf_complete(sa_u64 fr, sa_u64 result) {
        \\  sa_u64 parent = sa_tf_ld64(fr + SA_TF_OFF_PARENT);
        \\  uint32_t rreg = (uint32_t)sa_tf_ld32(fr + SA_TF_OFF_RREG);
        \\  sa_tf_st64(fr + SA_TF_OFF_RESULT, result);
        \\  sa_tf_at_store_m32(fr + SA_TF_OFF_STATE, SA_TF_STATE_DONE);
        \\  if (parent != 0) {
        \\    if (rreg != SA_TF_NOREG) sa_tf_st64(parent + SA_TF_REGOFF(rreg), result);
        \\    sa_tf_child_done(parent);
        \\  }
        \\  (void)sa_tf_at_add_u32(&sa_tf_alive, (uint32_t)-1);
        \\  if (parent != 0) sa_tf_free_push(fr);
        \\}
        \\static sa_u64 sa_tf_frame_result(sa_u64 fr) { return sa_tf_ld64(fr + SA_TF_OFF_RESULT); }
        \\
    );
    try rw.writeAll("static void sa_tf_dispatch(sa_u64 fr) {\n  switch ((uint32_t)sa_tf_ld32(fr + SA_TF_OFF_FNID)) {\n");
    for (prog.fsig_of_fnid) |fidx| {
        try rw.writeAll("    case SA_TF_FN_");
        try tfIdent(rw, verified.function_sigs[fidx]);
        try rw.writeAll(": sa_tf_step_");
        try tfIdent(rw, verified.function_sigs[fidx]);
        try rw.writeAll("(fr); return;\n");
    }
    try rw.writeAll(
        \\    default: sa_trap("sa_tf: bad fnid"); return;
        \\  }
        \\}
        \\static void sa_tf_drive(void) {
        \\  uint32_t me = sa_tf_qid();
        \\  while (sa_tf_at_load_u32(&sa_tf_alive) != 0) {
        \\    uint32_t fr = sa_tf_lq_pop(me);
        \\    if (fr == 0) fr = sa_tf_queue_pop();
        \\    if (fr != 0) sa_tf_dispatch(fr);
        \\  }
        \\}
        \\
    );
}

pub fn tfListHas(list: []const u32, v: u32) bool {
    for (list) |x| {
        if (x == v) return true;
    }
    return false;
}

pub fn tfListHasU64(list: []const u64, v: u64) bool {
    for (list) |x| {
        if (x == v) return true;
    }
    return false;
}


// Identity of a spawn argument for the R4 shared-argument rule: the
// caller slot when the argument is a plain register; otherwise a
// tagged FNV-1a hash of the argument text (deterministic, so equal
// texts always map to equal identities).
pub fn tfArgIdentity(symbols: anytype, fsig: sig.FunctionSig, arg_text: []const u8) u64 {
    const t = std.mem.trim(u8, arg_text, " \t");
    if (symbols.findId(t)) |id| {
        if (fsig.slotOf(id)) |slot| return @as(u64, slot);
    }
    var h: u64 = 14695981039346656037;
    for (t) |c| {
        h ^= c;
        h *= 1099511628211;
    }
    return h | (@as(u64, 1) << 63);
}

pub fn emitTfSyncBlock(writer: anytype, declared: []const u32, sinfo: TfSyncInfo) !void {
    // Save-before-mark discipline: the register save and the resume
    // point are published BEFORE sa_tf_sync_wait performs the atomic
    // RUNNING->SUSPENDED mark. Queueing of this frame can only happen
    // after that mark (the waker must win the exchange against it), so
    // a woken frame is always dispatched with a complete save — the
    // earlier save-after-verdict shape let the waker enqueue the frame
    // while this lane was still saving, and the late save could land
    // on a completed/recycled frame (host MT sim: sums biased low).
    try writer.print("SA_TF_SYNC_{d}:\n", .{sinfo.id});
    for (declared) |s| {
        // Outstanding result slots are owned by completing children
        // (they store into fr + REGOFF(dest) from sa_tf_complete);
        // the suspension save must never write them — a stale local
        // copy landing after a child's write-back would clobber the
        // result (found by the host MT sim: sums biased low under
        // concurrency). They are reloaded from the slots after the
        // sync passes (sinfo.reload), so skipping them is lossless.
        var is_result_slot = false;
        for (sinfo.reload) |rs| {
            if (rs == s) {
                is_result_slot = true;
                break;
            }
        }
        if (is_result_slot) continue;
        try writer.print("  sa_tf_st64(fr + SA_TF_REGOFF({d}), r{d});\n", .{ s, s });
    }
    try writer.print("  sa_tf_st32(fr + SA_TF_OFF_RESUME, {d});\n", .{sinfo.id});
    try writer.writeAll("  if (sa_tf_sync_wait(fr)) {\n    return;\n  }\n");
    for (sinfo.reload) |s| {
        try writer.print("  r{d} = sa_tf_ld64(fr + SA_TF_REGOFF({d}));\n", .{ s, s });
    }
}

pub fn emitTfWrapper(writer: anytype, fsig: sig.FunctionSig, ctx: TfFnCtx, uniform_arity: usize) !void {
    try writer.writeAll("static sa_u64 ");
    try cFuncName(writer, fsig.name);
    try writer.writeAll("(");
    if (uniform_arity == 0) {
        try writer.writeAll("void");
    } else {
        for (0..uniform_arity) |pi| {
            if (pi != 0) try writer.writeAll(", ");
            try writer.print("sa_u64 a{d}", .{pi});
        }
    }
    try writer.writeAll(") {\n");
    try writer.print("  sa_u64 fr = sa_tf_frame_new({d}, 0, SA_TF_NOREG);\n", .{ctx.fnid});
    for (fsig.param_ids, 0..) |pid, pi| {
        if (pi >= fsig.params.len) break;
        if (fsig.slotOf(pid)) |slot| {
            try writer.print("  sa_tf_st64(fr + SA_TF_REGOFF({d}), a{d});\n", .{ slot, pi });
        }
    }
    for (0..uniform_arity) |pi| {
        try writer.print("  (void)a{d};\n", .{pi});
    }
    try writer.writeAll("  sa_tf_queue_push((uint32_t)fr);\n  sa_tf_drive();\n  return sa_tf_frame_result(fr);\n}\n");
}


// Task-form call emission: a direct call to a task-formed callee
// becomes frame_new + argument stores + queue_push (the callee runs
// as a task; the caller's dry walk placed suspension points so the
// sequential semantics are preserved). Any other call keeps the
// historical emission via emitLinearInstruction.
pub fn emitTfCall(writer: anytype, allocator: std.mem.Allocator, verified: anytype, fsig: sig.FunctionSig, use_global: bool, const_addrs: anytype, fn_idx: anytype, base: anytype, widths: *WidthMap, sigmap: anytype, uniform_arity: usize, indirect_ret_width: ?u32, dead: *const std.AutoHashMap(u32, void), bases: *CBaseSet, ctx: TfFnCtx) !void {
    const symbols = verified.symbols;
    if (base.kind == .call) {
        if (call.parseInstructionCall(allocator, base, symbols)) |*pc| {
            var parsed = pc.*;
            defer parsed.deinit(allocator);
            if (!parsed.is_indirect) {
                if (ctx.prog.fnid_by_name.get(sigNormName(parsed.callee))) |cfid| {
                    const cfsig = verified.function_sigs[ctx.prog.fsig_of_fnid[cfid]];
                    trackWidths(widths, allocator, symbols, fsig, use_global, base);
                    var dest_slot: ?u32 = null;
                    if (parsed.dest) |dname| {
                        if (symbols.findId(dname)) |did| {
                            if (fsig.slotOf(did)) |slot| {
                                if (dead.get(slot) == null) dest_slot = slot;
                            }
                        }
                    }
                    try writer.print("  {{ sa_u64 sa_tf_ch = sa_tf_frame_new({d}, fr, ", .{cfid});
                    if (dest_slot) |slot| {
                        try writer.print("{d}", .{slot});
                    } else {
                        try writer.writeAll("SA_TF_NOREG");
                    }
                    try writer.writeAll(");\n");
                    const lim = @min(@min(parsed.args.len, cfsig.params.len), cfsig.param_ids.len);
                    for (parsed.args[0..lim], 0..) |arg, j| {
                        if (cfsig.slotOf(cfsig.param_ids[j])) |pslot| {
                            var abuf: std.Io.Writer.Allocating = .init(allocator);
                            defer abuf.deinit();
                            try resolveTextToC(&abuf.writer, symbols, fsig, const_addrs, arg.text);
                            try writer.print("    sa_tf_st64(sa_tf_ch + SA_TF_REGOFF({d}), ({s}));\n", .{ pslot, abuf.writer.buffered() });
                        }
                    }
                    try writer.writeAll("    sa_tf_lq_push((uint32_t)sa_tf_ch); }\n");
                    // Mirror emitLinearInstruction's width sharpening
                    // for the call destination.
                    if (parsed.dest) |dname| {
                        if (symbols.findId(dname)) |did| {
                            if (fsig.slotOf(did)) |slot| {
                                if (sigReturnWidth(sigmap, parsed.callee)) |w| widths.put(slot, w) catch {};
                            }
                        }
                    }
                    return;
                }
            }
        } else |_| {}
    }
    try emitLinearInstruction(writer, allocator, symbols, fsig, use_global, const_addrs, fn_idx, base, widths, sigmap, uniform_arity, indirect_ret_width, dead, bases);
}

pub fn emitTfReturn(writer: anytype, allocator: std.mem.Allocator, symbols: anytype, fsig: sig.FunctionSig, use_global: bool, const_addrs: anytype, fn_idx: anytype, base: anytype, widths: *WidthMap) !void {
    // Mirror emitLinearInstruction's width tracking so the width
    // state evolves identically to the direct-form emission.
    trackWidths(widths, allocator, symbols, fsig, use_global, base);
    const operand = base.operands[0];
    if (fsig.return_fallible) {
        switch (operand) {
            .none => try writer.writeAll("  sa_tf_complete(fr, sa_ok_none()); return;\n"),
            else => {
                try writer.writeAll("  sa_tf_complete(fr, sa_ok_val((");
                try resolveValueToC(writer, symbols, fsig, use_global, const_addrs, fn_idx, operand);
                try writer.writeAll("))); return;\n");
            },
        }
    } else switch (operand) {
        .none => try writer.writeAll("  sa_tf_complete(fr, 0); return;\n"),
        else => {
            try writer.writeAll("  sa_tf_complete(fr, (");
            try resolveValueToC(writer, symbols, fsig, use_global, const_addrs, fn_idx, operand);
            try writer.writeAll(")); return;\n");
        },
    }
}
