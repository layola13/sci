// JS runtime chunk (moved from src/emit_js.zig).
// Pure data: the emitted JS source text for one runtime piece.
pub const jstask_runtime_js =
    \\// ---- sa task/chan/sync runtime (JS port of sa_task_coop.zig) ----
    \\// The goroutine surface of sa_std/task.sai (sa_task_*, sa_chan_*,
    \\// sa_sync_*, sa_coop_*) implemented as a single-threaded cooperative
    \\// scheduler, mirroring the wasm cooperative track's semantics and
    \\// status codes (OK=0, INVALID=1, INVALID_HANDLE=2, NOT_FOUND=3,
    \\// NO_MEMORY=5, UNSUPPORTED=8, UNKNOWN=127, TRAPPED=100).
    \\//
    \\// Two frame protocols share the one scheduler:
    \\//  - coop steps (programs lowered by the SLA plugin's CPS lowering,
    \\//    driven by sa_coop_run_main): a blocking extern registers the
    \\//    task's wait, marks it blocked and returns SA_COOP_BLOCKED
    \\//    (0x40000000); at wake the runtime writes the outputs through the
    \\//    captured pointers and the step collects the final status via
    \\//    sa_coop_take_result. The call is never re-executed.
    \\//  - plain frames (native-lowered programs, the shape `sa sla
    \\//    build-js` emits today): a plain JS function cannot unwind into a
    \\//    heap frame, so a blocking call registers the same wait record
    \\//    and then pumps the scheduler from its own frame until the wait
    \\//    completes; delivery likewise happens through the captured
    \\//    pointers, never by re-executing the call. Registered boundary of
    \\//    this track: a wait whose satisfaction requires an ANCESTOR frame
    \\//    on the pump stack to advance (e.g. joining a task that is
    \\//    blocked above you, or a mutex whose holder is blocked in a
    \\//    frame below the waiter) cannot complete in-frame and traps
    \\//    loudly as a deadlock instead of corrupting state. Waits
    \\//    satisfied by the caller's own scheduling subtree (children
    \\//    spawned and joined/received/waited on) or by timers are exact.
    \\// v1 registered limits, same as the wasm coop track: sa_task_net_wait
    \\// and sa_task_monitor return UNSUPPORTED; a trap inside any task
    \\// traps the whole program (no per-task trap isolation, supervised
    \\// sinks never fire, sa_task_trap_info always reports NOT_FOUND).
    \\const __sa_task = (() => {
    \\  const OK = 0, ERR_INVALID = 1, ERR_INVALID_HANDLE = 2, ERR_NOT_FOUND = 3,
    \\    ERR_NOMEM = 5, ERR_UNSUPPORTED = 8, ERR_UNKNOWN = 127;
    \\  const BLOCKED = 0x40000000;
    \\  const nowMs = () => (typeof performance !== "undefined" ? performance.now() : Date.now());
    \\  const __t0 = nowMs();
    \\  function nowNs() { return BigInt(Math.floor((nowMs() - __t0) * 1e6)); }
    \\  const __waitArr = (() => { try { return new Int32Array(new SharedArrayBuffer(4)); } catch (e) { return null; } })();
    \\  function hostWaitNs(ns) {
    \\    if (ns <= 0n) return;
    \\    const end = nowMs() + Number(ns) / 1e6;
    \\    if (__waitArr && typeof Atomics !== "undefined" && typeof Atomics.wait === "function") {
    \\      for (;;) {
    \\        const rem = end - nowMs();
    \\        if (rem <= 0) return;
    \\        try { Atomics.wait(__waitArr, 0, 0, Math.min(rem, 2147483647)); } catch (e) { break; }
    \\      }
    \\      return;
    \\    }
    \\    while (nowMs() < end) { /* spin fallback (no Atomics.wait here) */ }
    \\  }
    \\  function isNullPtr(p) { return p === 0 || p === 0n || p === null || p === undefined; }
    \\
    \\  // ---------------- tasks ----------------
    \\  const tasks = [], taskGens = [];
    \\  let current = null;      // task whose step/frame is executing
    \\  let rootTask = null;     // implicit plain-mode root (the main frame)
    \\  let driverActive = false;
    \\  let coopMode = false;
    \\  let suspendForbidden = 0;
    \\  const readyQ = [];
    \\  function readyPush(t) { readyQ.push(t); }
    \\  function readyPop() { return readyQ.length ? readyQ.shift() : null; }
    \\  function makeHandle(slot, gen) { return (BigInt(gen) << 32n) | BigInt(slot + 1); }
    \\  function taskFromHandle(h) {
    \\    if (isNullPtr(h)) return null;
    \\    let v; try { v = BigInt(h); } catch (e) { return null; }
    \\    const slotPlus = Number(v & 0xffffffffn);
    \\    if (slotPlus === 0) return null;
    \\    const slot = slotPlus - 1;
    \\    if (slot >= tasks.length) return null;
    \\    const t = tasks[slot];
    \\    if (!t || t.gen !== Number((v >> 32n) & 0xffffffffn)) return null;
    \\    return t;
    \\  }
    \\  function allocTask(entry, arg, kind) {
    \\    const mk = (slot, gen) => ({
    \\      slot, gen, entry, arg, kind, state: "ready", exitStatus: 0,
    \\      detached: false, joinDelivered: false, pending: null, joiners: [],
    \\      sink: null, sinkCtx: null, activeWaiter: null,
    \\    });
    \\    for (let i = 0; i < tasks.length; i++) {
    \\      if (tasks[i] === null) { taskGens[i] += 1; const t = mk(i, taskGens[i]); tasks[i] = t; return t; }
    \\    }
    \\    const t = mk(tasks.length, 1); tasks.push(t); taskGens.push(1); return t;
    \\  }
    \\  // The task a blocking extern was called from. Inside a step this is
    \\  // the stepped task; at plain top level it is the implicit root. On
    \\  // the coop track outside a step there is no current task (null).
    \\  function hostTask() {
    \\    if (current) return current;
    \\    if (driverActive) return null;
    \\    if (!rootTask) { rootTask = allocTask(null, null, "plain"); rootTask.state = "running"; }
    \\    return rootTask;
    \\  }
    \\  function newWaiter(task) { const w = { task, done: false, status: 0, sel: null, selIndex: 0, valuePtr: null, outValue: null, outClosed: null }; task.activeWaiter = w; return w; }
    \\  function completeWaiter(w, status) {
    \\    if (!w || w.done) return;
    \\    w.done = true; w.status = status;
    \\    const t = w.task;
    \\    if (t.kind === "coop") { t.pending = status; if (t.state === "blocked") { t.state = "ready"; readyPush(t); } }
    \\  }
    \\  function finishTask(t, status) {
    \\    if (t.state === "done") return;
    \\    t.state = "done"; t.exitStatus = status;
    \\    const js = t.joiners; t.joiners = [];
    \\    for (const w of js) completeWaiter(w, status);
    \\    if (js.length) t.joinDelivered = true;
    \\    reapIfReady(t);
    \\  }
    \\  function reapIfReady(t) {
    \\    if (t.state !== "done") return;
    \\    if (!t.detached && !t.joinDelivered) return;
    \\    if (t.joiners.length) return;
    \\    if (t.slot >= 0 && tasks[t.slot] === t) tasks[t.slot] = null;
    \\  }
    \\  function stepTask(t) {
    \\    const prev = current;
    \\    current = t; t.state = "running";
    \\    try { __sa_call_indirect(t.entry, t.arg); } finally { current = prev; }
    \\    if (t.kind === "coop") {
    \\      if (t.state === "running") __sa_trap("sa_task: coop step returned without blocking or finishing");
    \\    } else {
    \\      if (t.state === "running") finishTask(t, OK);
    \\      else if (t.state === "blocked") __sa_trap("sa_task: plain step returned while blocked");
    \\    }
    \\  }
    \\  function anyBlocked() { return tasks.some((t) => t && t.state === "blocked"); }
    \\  function anyBlockedSatisfied() {
    \\    return tasks.some((t) => t && t.state === "blocked" &&
    \\      ((t.activeWaiter && t.activeWaiter.done) || t.pending !== null));
    \\  }
    \\
    \\  // ---------------- timers ----------------
    \\  const timers = []; // sorted by deadline, FIFO among equals
    \\  function addTimer(deadline, sel, waiter) {
    \\    const tm = { deadline, sel, waiter };
    \\    let i = timers.length;
    \\    while (i > 0 && timers[i - 1].deadline > deadline) i--;
    \\    timers.splice(i, 0, tm);
    \\    return tm;
    \\  }
    \\  function promoteTimers() {
    \\    const now = nowNs();
    \\    while (timers.length && timers[0].deadline <= now) {
    \\      const tm = timers.shift();
    \\      if (tm.sel) fireSelect(tm.sel, -2, 0);
    \\      else if (tm.waiter) completeWaiter(tm.waiter, OK);
    \\    }
    \\  }
    \\  function earliestDeadline() { return timers.length ? timers[0].deadline : null; }
    \\
    \\  // ---------------- scheduler core ----------------
    \\  // Run the scheduler until cond() holds. Plain frames only; coop
    \\  // steps return BLOCKED to their driver instead (see suspend()).
    \\  function pumpUntil(cond) {
    \\    for (;;) {
    \\      if (cond()) return;
    \\      promoteTimers();
    \\      if (cond()) return;
    \\      const t = readyPop();
    \\      if (t) { if (t.state === "ready") stepTask(t); continue; }
    \\      const dl = earliestDeadline();
    \\      if (dl !== null) {
    \\        const delta = dl - nowNs();
    \\        if (delta > 0n) hostWaitNs(delta);
    \\        promoteTimers();
    \\        continue;
    \\      }
    \\      if (anyBlockedSatisfied()) {
    \\        __sa_trap("sa_task: deadlock: a blocked ancestor task's wait completed below a nested scheduling frame (plain-frame track cannot unwind a wait cycle that crosses the pump stack; the same program completes on the coop track)");
    \\      }
    \\      __sa_trap("sa_task: deadlock: no ready task and no pending timer, but tasks remain blocked");
    \\    }
    \\  }
    \\  // Suspend the calling task on waiter w (already registered by the
    \\  // caller). Coop steps get BLOCKED; plain frames pump until w
    \\  // completes and return its final status.
    \\  function suspend(w, me) {
    \\    if (suspendForbidden > 0) __sa_trap("sa_task: blocking call inside a once_do entry or host context that cannot suspend");
    \\    me.state = "blocked";
    \\    if (me.kind === "coop") return BLOCKED;
    \\    pumpUntil(() => w.done);
    \\    me.state = "running";
    \\    return w.status;
    \\  }
    \\
    \\  // ---------------- channels ----------------
    \\  const chans = [], chanGens = [];
    \\  function chanFromHandle(h) {
    \\    if (isNullPtr(h)) return null;
    \\    let v; try { v = BigInt(h); } catch (e) { return null; }
    \\    const slotPlus = Number(v & 0xffffffffn);
    \\    if (slotPlus === 0) return null;
    \\    const slot = slotPlus - 1;
    \\    if (slot >= chans.length) return null;
    \\    const ch = chans[slot];
    \\    if (!ch || ch.gen !== Number((v >> 32n) & 0xffffffffn) || ch.destroyed) return null;
    \\    return ch;
    \\  }
    \\  function readSlot(ptr) { const a = __sa_addr(ptr); return [__sa_load_i64(a), __sa_load_i64(a + 8)]; }
    \\  function writeSlot(ptr, v) { const a = __sa_addr(ptr); __sa_store_i64(a, v[0]); __sa_store_i64(a + 8, v[1]); }
    \\  function waiterLive(w) { return w.sel ? !w.sel.fired : true; }
    \\  function queuePopLive(q) { while (q.length) { const w = q.shift(); if (waiterLive(w)) return w; } return null; }
    \\  function queueHasLive(q) { return q.some(waiterLive); }
    \\  function trapSendOnClosed() { __sa_trap("send on closed channel"); }
    \\  function fireSelect(sel, index, closedFlag) {
    \\    if (sel.fired) return;
    \\    sel.fired = true;
    \\    __sa_store_i64(sel.outIndex, BigInt(index));
    \\    __sa_store_u32(sel.outClosed, closedFlag);
    \\    completeWaiter(sel.waiter, OK);
    \\  }
    \\  function completeSendWaiter(w) {
    \\    if (w.sel) fireSelect(w.sel, w.selIndex, 0);
    \\    else completeWaiter(w, OK);
    \\  }
    \\  function completeRecvWaiter(w, value, closedFlag) {
    \\    if (w.sel) {
    \\      if (w.outValue !== null) writeSlot(w.outValue, value);
    \\      fireSelect(w.sel, w.selIndex, closedFlag);
    \\    } else {
    \\      if (w.outValue !== null) writeSlot(w.outValue, value);
    \\      if (w.outClosed !== null) __sa_store_u32(w.outClosed, closedFlag);
    \\      completeWaiter(w, OK);
    \\    }
    \\  }
    \\  function bufPush(ch, value) { ch.buf[(ch.head + ch.count) % ch.buf.length] = value; ch.count += 1; }
    \\  function bufPop(ch) { const v = ch.buf[ch.head]; ch.head = (ch.head + 1) % ch.buf.length; ch.count -= 1; return v; }
    \\  function recvReady(ch) { return ch.count > 0 || queueHasLive(ch.sendQ) || ch.closed; }
    \\  function sendReady(ch) { return queueHasLive(ch.recvQ) || ch.count < ch.cap || ch.closed; }
    \\  function doRecvCore(ch) {
    \\    if (ch.count > 0) {
    \\      const v = bufPop(ch);
    \\      const w = queuePopLive(ch.sendQ);
    \\      if (w) { bufPush(ch, readSlot(w.valuePtr)); completeSendWaiter(w); }
    \\      return { value: v, closed: 0 };
    \\    }
    \\    const w = queuePopLive(ch.sendQ);
    \\    if (w) { const v = readSlot(w.valuePtr); completeSendWaiter(w); return { value: v, closed: 0 }; }
    \\    if (ch.closed) return { value: [0n, 0n], closed: 1 };
    \\    return null;
    \\  }
    \\  function doSendCore(ch, value) {
    \\    if (ch.closed) trapSendOnClosed();
    \\    const w = queuePopLive(ch.recvQ);
    \\    if (w) { completeRecvWaiter(w, value, 0); return true; }
    \\    if (ch.count < ch.cap) { bufPush(ch, value); return true; }
    \\    return false;
    \\  }
    \\  function chanMake(capacity, outHandle) {
    \\    if (isNullPtr(outHandle)) return ERR_INVALID;
    \\    __sa_store_i64(outHandle, 0n);
    \\    const cap = __sa_num(capacity) >>> 0;
    \\    const mk = (slot, gen) => ({ slot, gen, cap, buf: new Array(cap), head: 0, count: 0, closed: false, destroyed: false, recvQ: [], sendQ: [] });
    \\    for (let i = 0; i < chans.length; i++) {
    \\      if (chans[i] === null) { chanGens[i] += 1; const ch = mk(i, chanGens[i]); chans[i] = ch; __sa_store_i64(outHandle, makeHandle(i, ch.gen)); return OK; }
    \\    }
    \\    const ch = mk(chans.length, 1); chans.push(ch); chanGens.push(1);
    \\    __sa_store_i64(outHandle, makeHandle(ch.slot, 1));
    \\    return OK;
    \\  }
    \\  function chanDestroy(handle) {
    \\    const ch = chanFromHandle(handle); if (!ch) return ERR_INVALID_HANDLE;
    \\    ch.destroyed = true;
    \\    if (chans[ch.slot] === ch) chans[ch.slot] = null;
    \\    return OK;
    \\  }
    \\  function chanClose(handle) {
    \\    const ch = chanFromHandle(handle); if (!ch) return ERR_INVALID_HANDLE;
    \\    if (ch.closed) return OK;
    \\    ch.closed = true;
    \\    let w;
    \\    while ((w = queuePopLive(ch.recvQ)) !== null) completeRecvWaiter(w, [0n, 0n], 1);
    \\    if (queueHasLive(ch.sendQ)) trapSendOnClosed();
    \\    return OK;
    \\  }
    \\  function chanSend(handle, valuePtr) {
    \\    const ch = chanFromHandle(handle); if (!ch) return ERR_INVALID_HANDLE;
    \\    if (isNullPtr(valuePtr)) return ERR_INVALID;
    \\    if (ch.closed) trapSendOnClosed();
    \\    if (doSendCore(ch, readSlot(valuePtr))) return OK;
    \\    const me = hostTask(); if (!me) return ERR_INVALID;
    \\    const w = newWaiter(me); w.valuePtr = valuePtr;
    \\    ch.sendQ.push(w);
    \\    return suspend(w, me);
    \\  }
    \\  function chanRecv(handle, outValue, outClosed) {
    \\    const ch = chanFromHandle(handle); if (!ch) return ERR_INVALID_HANDLE;
    \\    if (isNullPtr(outValue) || isNullPtr(outClosed)) return ERR_INVALID;
    \\    __sa_store_u32(outClosed, 0);
    \\    const r = doRecvCore(ch);
    \\    if (r) { writeSlot(outValue, r.value); __sa_store_u32(outClosed, r.closed); return OK; }
    \\    const me = hostTask(); if (!me) return ERR_INVALID;
    \\    const w = newWaiter(me); w.outValue = outValue; w.outClosed = outClosed;
    \\    ch.recvQ.push(w);
    \\    return suspend(w, me);
    \\  }
    \\  function chanLen(handle, outLen) {
    \\    const ch = chanFromHandle(handle); if (!ch) return ERR_INVALID_HANDLE;
    \\    if (isNullPtr(outLen)) return ERR_INVALID;
    \\    __sa_store_i64(outLen, BigInt(ch.count));
    \\    return OK;
    \\  }
    \\  function chanCap(handle, outCap) {
    \\    const ch = chanFromHandle(handle); if (!ch) return ERR_INVALID_HANDLE;
    \\    if (isNullPtr(outCap)) return ERR_INVALID;
    \\    __sa_store_i64(outCap, BigInt(ch.cap));
    \\    return OK;
    \\  }
    \\  function chanSelect(casesPtr, opsPtr, slotsPtr, count, hasDefault, timeoutNs, outIndex, outClosed) {
    \\    if (isNullPtr(outIndex) || isNullPtr(outClosed)) return ERR_INVALID;
    \\    __sa_store_u32(outClosed, 0);
    \\    __sa_store_i64(outIndex, -3n);
    \\    const n = __sa_num(count);
    \\    if (n > 0 && (isNullPtr(casesPtr) || isNullPtr(opsPtr) || isNullPtr(slotsPtr))) return ERR_INVALID;
    \\    const caseChans = [], ops = [];
    \\    for (let i = 0; i < n; i++) {
    \\      const ch = chanFromHandle(__sa_load_i64(__sa_addr(casesPtr) + i * 8));
    \\      if (!ch) return ERR_INVALID_HANDLE;
    \\      caseChans.push(ch);
    \\      ops.push(__sa_load_u32(__sa_addr(opsPtr) + i * 4));
    \\    }
    \\    for (let i = 0; i < n; i++) {
    \\      const ch = caseChans[i];
    \\      if (ops[i] === 0) {
    \\        if (recvReady(ch)) {
    \\          const r = doRecvCore(ch);
    \\          writeSlot(__sa_addr(slotsPtr) + i * 16, r.value);
    \\          __sa_store_i64(outIndex, BigInt(i));
    \\          __sa_store_u32(outClosed, r.closed);
    \\          return OK;
    \\        }
    \\      } else if (sendReady(ch)) {
    \\        if (ch.closed) trapSendOnClosed();
    \\        doSendCore(ch, readSlot(__sa_addr(slotsPtr) + i * 16));
    \\        __sa_store_i64(outIndex, BigInt(i));
    \\        return OK;
    \\      }
    \\    }
    \\    if (__sa_num(hasDefault) !== 0) { __sa_store_i64(outIndex, -1n); return OK; }
    \\    const tns = BigInt(timeoutNs);
    \\    if (tns === 0n) { __sa_store_i64(outIndex, -2n); return OK; }
    \\    const me = hostTask(); if (!me) return ERR_INVALID;
    \\    const waiter = newWaiter(me);
    \\    const sel = { task: me, outIndex, outClosed, fired: false, waiter };
    \\    for (let i = 0; i < n; i++) {
    \\      const w = newWaiter(me); w.sel = sel; w.selIndex = i;
    \\      if (ops[i] === 0) { w.outValue = __sa_addr(slotsPtr) + i * 16; caseChans[i].recvQ.push(w); }
    \\      else { w.valuePtr = __sa_addr(slotsPtr) + i * 16; caseChans[i].sendQ.push(w); }
    \\    }
    \\    if (tns > 0n) addTimer(nowNs() + tns, sel, null);
    \\    return suspend(waiter, me);
    \\  }
    \\
    \\  // ---------------- task lifecycle ----------------
    \\  function spawnImpl(entry, arg, sink, sinkCtx, outHandle) {
    \\    if (isNullPtr(outHandle)) return ERR_INVALID;
    \\    __sa_store_i64(outHandle, 0n);
    \\    if (isNullPtr(entry)) return ERR_INVALID;
    \\    const t = allocTask(entry, arg, coopMode ? "coop" : "plain");
    \\    t.sink = sink; t.sinkCtx = sinkCtx;
    \\    t.state = "ready"; readyPush(t);
    \\    __sa_store_i64(outHandle, makeHandle(t.slot, t.gen));
    \\    return OK;
    \\  }
    \\  function spawn(entry, arg, outHandle) { return spawnImpl(entry, arg, null, null, outHandle); }
    \\  function spawnSupervised(entry, arg, sink, sinkCtx, outHandle) { return spawnImpl(entry, arg, sink, sinkCtx, outHandle); }
    \\  function trapInfo(handle, outCode, outMsgPtr, outMsgLen) {
    \\    const t = taskFromHandle(handle); if (!t) return ERR_INVALID_HANDLE;
    \\    if (t.detached) return ERR_INVALID_HANDLE;
    \\    // This track traps at process level: no per-task trap record
    \\    // ever exists, so a live record always reports NOT_FOUND.
    \\    return ERR_NOT_FOUND;
    \\  }
    \\  function monitor(handle, outChan) { return ERR_UNSUPPORTED; }
    \\  function yield_() {
    \\    const me = hostTask(); if (!me) return OK;
    \\    if (suspendForbidden > 0) __sa_trap("sa_task: yield inside a once_do entry");
    \\    if (me.kind === "coop") {
    \\      me.pending = OK;
    \\      me.state = "ready"; readyPush(me);
    \\      return BLOCKED;
    \\    }
    \\    // Plain frames: a bounded cooperative pass — promote timers,
    \\    // then run each currently-ready task one step. The yielding
    \\    // frame stays on the stack; stepped tasks run their own pumps.
    \\    promoteTimers();
    \\    let n = readyQ.length;
    \\    while (n-- > 0) {
    \\      const t = readyPop();
    \\      if (t && t.state === "ready") stepTask(t);
    \\    }
    \\    return OK;
    \\  }
    \\  function sleepNs(ns) {
    \\    const n = BigInt(ns);
    \\    if (n === 0n) return yield_();
    \\    if (!current && driverActive) { hostWaitNs(n); return OK; }
    \\    const me = hostTask(); if (!me) { hostWaitNs(n); return OK; }
    \\    const w = newWaiter(me);
    \\    addTimer(nowNs() + n, null, w);
    \\    return suspend(w, me);
    \\  }
    \\  function sleepMs(ms) {
    \\    const n = BigInt(ms) * 1000000n;
    \\    if (n > 0xffffffffffffffffn) return ERR_INVALID;
    \\    return sleepNs(n);
    \\  }
    \\  function join(handle) {
    \\    const t = taskFromHandle(handle); if (!t) return ERR_INVALID_HANDLE;
    \\    if (t.detached) return ERR_INVALID_HANDLE;
    \\    if (t.joinDelivered) return ERR_INVALID_HANDLE;
    \\    const me = hostTask(); if (!me) return ERR_INVALID;
    \\    if (me === t) return ERR_INVALID;
    \\    if (t.state === "done") {
    \\      const st = t.exitStatus;
    \\      t.joinDelivered = true;
    \\      reapIfReady(t);
    \\      return st;
    \\    }
    \\    const w = newWaiter(me);
    \\    t.joiners.push(w);
    \\    return suspend(w, me);
    \\  }
    \\  function detach(handle) {
    \\    const t = taskFromHandle(handle); if (!t) return ERR_INVALID_HANDLE;
    \\    if (t.state === "done" && t.joinDelivered) return ERR_INVALID_HANDLE;
    \\    t.detached = true;
    \\    reapIfReady(t);
    \\    return OK;
    \\  }
    \\  function current_(outHandle) {
    \\    if (isNullPtr(outHandle)) return ERR_INVALID;
    \\    const me = hostTask(); if (!me) return ERR_INVALID;
    \\    __sa_store_i64(outHandle, makeHandle(me.slot, me.gen));
    \\    return OK;
    \\  }
    \\  function liveCount(outCount) {
    \\    if (isNullPtr(outCount)) return ERR_INVALID;
    \\    let n = 0;
    \\    for (const t of tasks) if (t && t.state !== "done") n += 1;
    \\    __sa_store_i64(outCount, BigInt(n));
    \\    return OK;
    \\  }
    \\  function deadlockGuardArm() { return OK; }
    \\  function netWait(handle, interest, timeoutNs, outReady) { return ERR_UNSUPPORTED; }
    \\
    \\  // ---------------- sync family ----------------
    \\  const syncs = [], syncGens = [];
    \\  function syncFromHandle(h, kind) {
    \\    if (isNullPtr(h)) return null;
    \\    let v; try { v = BigInt(h); } catch (e) { return null; }
    \\    const slotPlus = Number(v & 0xffffffffn);
    \\    if (slotPlus === 0) return null;
    \\    const slot = slotPlus - 1;
    \\    if (slot >= syncs.length) return null;
    \\    const o = syncs[slot];
    \\    if (!o || o.gen !== Number((v >> 32n) & 0xffffffffn) || o.destroyed) return null;
    \\    if (kind && o.kind !== kind) return null;
    \\    return o;
    \\  }
    \\  function syncNew(kind, outHandle) {
    \\    if (isNullPtr(outHandle)) return ERR_INVALID;
    \\    __sa_store_i64(outHandle, 0n);
    \\    const mk = (slot, gen) => ({
    \\      slot, gen, kind, destroyed: false,
    \\      owner: null, queue: [], readers: 0, writer: null, rqueue: [], wqueue: [],
    \\      count: 0, done: false, running: false,
    \\    });
    \\    for (let i = 0; i < syncs.length; i++) {
    \\      if (syncs[i] === null) { syncGens[i] += 1; const o = mk(i, syncGens[i]); syncs[i] = o; __sa_store_i64(outHandle, makeHandle(i, o.gen)); return OK; }
    \\    }
    \\    const o = mk(syncs.length, 1); syncs.push(o); syncGens.push(1);
    \\    __sa_store_i64(outHandle, makeHandle(o.slot, 1));
    \\    return OK;
    \\  }
    \\  function syncDestroy(handle) {
    \\    const o = syncFromHandle(handle, null); if (!o) return ERR_INVALID_HANDLE;
    \\    o.destroyed = true;
    \\    if (syncs[o.slot] === o) syncs[o.slot] = null;
    \\    return OK;
    \\  }
    \\  function mutexLock(handle) {
    \\    const o = syncFromHandle(handle, "mutex"); if (!o) return ERR_INVALID_HANDLE;
    \\    const me = hostTask(); if (!me) return ERR_INVALID;
    \\    if (o.owner === null) { o.owner = me; return OK; }
    \\    const w = newWaiter(me);
    \\    o.queue.push(w);
    \\    return suspend(w, me);
    \\  }
    \\  function mutexTryLock(handle, outAcquired) {
    \\    const o = syncFromHandle(handle, "mutex"); if (!o) return ERR_INVALID_HANDLE;
    \\    if (isNullPtr(outAcquired)) return ERR_INVALID;
    \\    const me = hostTask(); if (!me) return ERR_INVALID;
    \\    if (o.owner === null) { o.owner = me; __sa_store_u32(outAcquired, 1); }
    \\    else __sa_store_u32(outAcquired, 0);
    \\    return OK;
    \\  }
    \\  function mutexUnlock(handle) {
    \\    const o = syncFromHandle(handle, "mutex"); if (!o) return ERR_INVALID_HANDLE;
    \\    const me = hostTask(); if (!me) return ERR_INVALID;
    \\    if (o.owner === null || o.owner !== me) return ERR_INVALID;
    \\    // Direct handoff: the head waiter becomes the owner before it
    \\    // wakes, so the lock is never unowned in between.
    \\    const w = o.queue.shift();
    \\    if (w) { o.owner = w.task; completeWaiter(w, OK); }
    \\    else o.owner = null;
    \\    return OK;
    \\  }
    \\  function rwlockRlock(handle) {
    \\    const o = syncFromHandle(handle, "rwlock"); if (!o) return ERR_INVALID_HANDLE;
    \\    const me = hostTask(); if (!me) return ERR_INVALID;
    \\    if (o.writer === null && o.wqueue.length === 0) { o.readers += 1; return OK; }
    \\    const w = newWaiter(me);
    \\    o.rqueue.push(w);
    \\    return suspend(w, me);
    \\  }
    \\  function rwlockRunlock(handle) {
    \\    const o = syncFromHandle(handle, "rwlock"); if (!o) return ERR_INVALID_HANDLE;
    \\    if (o.readers === 0) return ERR_INVALID;
    \\    o.readers -= 1;
    \\    if (o.readers === 0) {
    \\      const w = o.wqueue.shift();
    \\      if (w) { o.writer = w.task; completeWaiter(w, OK); }
    \\    }
    \\    return OK;
    \\  }
    \\  function rwlockLock(handle) {
    \\    const o = syncFromHandle(handle, "rwlock"); if (!o) return ERR_INVALID_HANDLE;
    \\    const me = hostTask(); if (!me) return ERR_INVALID;
    \\    if (o.writer === null && o.readers === 0 && o.wqueue.length === 0) { o.writer = me; return OK; }
    \\    const w = newWaiter(me);
    \\    o.wqueue.push(w);
    \\    return suspend(w, me);
    \\  }
    \\  function rwlockUnlock(handle) {
    \\    const o = syncFromHandle(handle, "rwlock"); if (!o) return ERR_INVALID_HANDLE;
    \\    const me = hostTask(); if (!me) return ERR_INVALID;
    \\    if (o.writer === null || o.writer !== me) return ERR_INVALID;
    \\    o.writer = null;
    \\    const w = o.wqueue.shift();
    \\    if (w) { o.writer = w.task; completeWaiter(w, OK); }
    \\    else {
    \\      let admitted = 0;
    \\      let r;
    \\      while ((r = o.rqueue.shift()) !== undefined) { admitted += 1; completeWaiter(r, OK); }
    \\      o.readers += admitted;
    \\    }
    \\    return OK;
    \\  }
    \\  function wgAdd(handle, delta) {
    \\    const o = syncFromHandle(handle, "waitgroup"); if (!o) return ERR_INVALID_HANDLE;
    \\    o.count += Number(BigInt(delta));
    \\    if (o.count < 0) __sa_trap("waitgroup counter went negative");
    \\    if (o.count === 0) { const ws = o.queue; o.queue = []; for (const w of ws) completeWaiter(w, OK); }
    \\    return OK;
    \\  }
    \\  function wgDone(handle) { return wgAdd(handle, -1); }
    \\  function wgWait(handle) {
    \\    const o = syncFromHandle(handle, "waitgroup"); if (!o) return ERR_INVALID_HANDLE;
    \\    if (o.count === 0) return OK;
    \\    const me = hostTask(); if (!me) return ERR_INVALID;
    \\    const w = newWaiter(me);
    \\    o.queue.push(w);
    \\    return suspend(w, me);
    \\  }
    \\  function onceDo(handle, entry, arg) {
    \\    const o = syncFromHandle(handle, "once"); if (!o) return ERR_INVALID_HANDLE;
    \\    if (o.done) return OK;
    \\    const me = hostTask(); if (!me) return ERR_INVALID;
    \\    if (o.running) {
    \\      const w = newWaiter(me);
    \\      o.queue.push(w);
    \\      return suspend(w, me);
    \\    }
    \\    if (isNullPtr(entry)) return ERR_INVALID;
    \\    o.running = true;
    \\    suspendForbidden += 1;
    \\    try { __sa_call_indirect(entry, arg); } finally { suspendForbidden -= 1; }
    \\    o.running = false;
    \\    o.done = true;
    \\    const ws = o.queue; o.queue = [];
    \\    for (const w of ws) completeWaiter(w, OK);
    \\    return OK;
    \\  }
    \\
    \\  // ---------------- coop protocol ----------------
    \\  function coopTakeResult(outStatus) {
    \\    if (isNullPtr(outStatus)) return 0;
    \\    const me = current; if (!me) return 0;
    \\    if (me.pending !== null) {
    \\      __sa_store_i32(outStatus, me.pending);
    \\      me.pending = null;
    \\      return 1;
    \\    }
    \\    return 0;
    \\  }
    \\  function coopFinish() {
    \\    const me = current;
    \\    if (!me) __sa_trap("sa_coop_finish outside a task step");
    \\    if (me.state === "done") return;
    \\    finishTask(me, OK);
    \\  }
    \\  function coopRunMain(entry, arg) {
    \\    if (driverActive) return ERR_INVALID;
    \\    if (isNullPtr(entry)) return ERR_INVALID;
    \\    coopMode = true;
    \\    driverActive = true;
    \\    const root = allocTask(entry, arg, "coop");
    \\    root.state = "ready"; readyPush(root);
    \\    try {
    \\      for (;;) {
    \\        promoteTimers();
    \\        if (root.state === "done") return OK;
    \\        const t = readyPop();
    \\        if (!t) {
    \\          const dl = earliestDeadline();
    \\          if (dl !== null) {
    \\            const delta = dl - nowNs();
    \\            if (delta > 0n) hostWaitNs(delta);
    \\            continue;
    \\          }
    \\          if (anyBlocked()) {
    \\            console.error("sa_coop: deadlock: no ready task and no pending timer, but tasks remain blocked");
    \\            return ERR_UNKNOWN;
    \\          }
    \\          console.error("sa_coop: driver stalled with the root task unfinished");
    \\          return ERR_UNKNOWN;
    \\        }
    \\        if (t.state === "ready") stepTask(t);
    \\      }
    \\    } finally {
    \\      driverActive = false;
    \\    }
    \\  }
    \\
    \\  return {
    \\    spawn, spawnSupervised, trapInfo, monitor, yield_, sleepNs, sleepMs,
    \\    join, detach, current_, liveCount, deadlockGuardArm, netWait,
    \\    chanMake, chanDestroy, chanClose, chanSend, chanRecv, chanLen, chanCap, chanSelect,
    \\    mutexNew: (out) => syncNew("mutex", out),
    \\    rwlockNew: (out) => syncNew("rwlock", out),
    \\    waitgroupNew: (out) => syncNew("waitgroup", out),
    \\    onceNew: (out) => syncNew("once", out),
    \\    syncDestroy, mutexLock, mutexTryLock, mutexUnlock,
    \\    rwlockRlock, rwlockRunlock, rwlockLock, rwlockUnlock,
    \\    wgAdd, wgDone, wgWait, onceDo,
    \\    coopTakeResult, coopFinish, coopRunMain,
    \\  };
    \\})();
    ;
