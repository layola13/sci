const std = @import("std");
const sig = @import("../common/signature.zig");
const call = @import("../referee/call.zig");
const sio = @import("sio");
const CEmitOptions = @import("types.zig").CEmitOptions;
const TfFnCtx = @import("types.zig").TfFnCtx;
const bindingNeedsDispatcher = @import("helpers_util.zig").bindingNeedsDispatcher;
const bindingNeedsTaskEntry = @import("helpers_util.zig").bindingNeedsTaskEntry;
const bodyCallsFunction = @import("helpers_util.zig").bodyCallsFunction;
const buildTfProgram = @import("tf_scan.zig").buildTfProgram;
const cFuncName = @import("ident.zig").cFuncName;
const collectFuncTasks = @import("ident.zig").collectFuncTasks;
const collectUsedHelpers = @import("helpers_util.zig").collectUsedHelpers;
const constBytesLen = @import("ident.zig").constBytesLen;
const emitOneFunction = @import("emit_fn.zig").emitOneFunction;
const fillConstBytes = @import("ident.zig").fillConstBytes;
const fnIndexOf = @import("ident.zig").fnIndexOf;
const isStdlinkExtern = @import("helpers_util.zig").isStdlinkExtern;
const kRuntimeHelpers = @import("helpers.zig").kRuntimeHelpers;
const sigNormName = @import("ident.zig").sigNormName;
const sigReturnWidth = @import("dead_slots.zig").sigReturnWidth;
const taskIndexByName = @import("ident.zig").taskIndexByName;
const writeConstSym = @import("ident.zig").writeConstSym;
const writeExternBinding = @import("binding_emit.zig").writeExternBinding;
const writePreamble = @import("preamble.zig").writePreamble;
const writeTfHeader = @import("tf_emit.zig").writeTfHeader;
const writeTfMachinery = @import("tf_emit.zig").writeTfMachinery;

pub fn emitCToString(allocator: std.mem.Allocator, verified: anytype, source_path: []const u8, size_bits: u16, c_opt: CEmitOptions) ![]u8 {
    // Extern variadic batch: the C emitter's uniform-arity model has no
    // C-ABI variadic call/define mechanism (externs resolve through a
    // hand-written binding catalogue). Reject loudly instead of falling
    // back to a trap stub.
    for (verified.function_sigs) |fs| {
        if (fs.is_variadic) return error.UnsupportedVariadic;
    }
    var out: std.Io.Writer.Allocating = .init(allocator);
    errdefer out.deinit();
    const writer = &out.writer;
    var fn_names = std.array_list.Managed([]const u8).init(allocator);
    defer fn_names.deinit();
    var fn_idx = std.StringHashMap(usize).init(allocator);
    defer fn_idx.deinit();
    for (verified.const_decls) |decl| {
        if (decl.value != .vtable) continue;
        for (decl.value.vtable.slots) |slot| {
            if (fn_idx.contains(slot.func_name)) continue;
            try fn_idx.put(slot.func_name, fn_names.items.len);
            try fn_names.append(slot.func_name);
        }
    }
    const tasks = try collectFuncTasks(allocator, verified);
    defer allocator.free(tasks);
    // Callee return-type map for width seeding (normalized names).
    var sigmap = std.StringHashMap(sig.PrimType).init(allocator);
    defer sigmap.deinit();
    for (verified.function_sigs) |fs| {
        const key = sigNormName(fs.name);
        if (!sigmap.contains(key)) try sigmap.put(key, fs.return_ty);
    }
    // Uniform arity: every emitted function takes exactly W params.
    var uniform_arity: usize = 1;
    for (tasks) |task| {
        uniform_arity = @max(uniform_arity, verified.function_sigs[task.fsig_index].params.len);
    }
    // The goroutine glue trampolines (emitted when a task-entry binding is
    // bound) call sa_call_indirect with up to five arguments (the trap
    // sink passes handle, code, message pointer/length and its context),
    // so the uniform arity must cover the glue itself. Text-form programs
    // usually mask this because std helpers inflate the max param count;
    // a program whose widest function takes fewer params (the SAB-form
    // lowering of the same source, for instance) would otherwise emit a
    // dispatcher too narrow for its own glue and fail C compilation.
    {
        var ti: usize = 0;
        var glue_found = false;
        while (ti < tasks.len and !glue_found) : (ti += 1) {
            var i: usize = tasks[ti].start_idx + 1;
            while (i < tasks[ti].end_idx) : (i += 1) {
                const base = verified.annotated[i].base;
                if (base.kind != .call) continue;
                if (call.parseInstructionCall(allocator, base, verified.symbols)) |*pc| {
                    var parsed = pc.*;
                    defer parsed.deinit(allocator);
                    if (!parsed.is_indirect and bindingNeedsTaskEntry(sigNormName(parsed.callee))) glue_found = true;
                } else |_| {}
            }
        }
        if (glue_found) uniform_arity = @max(uniform_arity, 5);
    }
    // Indirect dispatch is needed iff the IR contains a dynamic call
    // site. Vtable consts alone don't need the ftable: without a call
    // site it would be dead data plus an unused dispatcher.
    var need_indirect = false;
    {
        var ti: usize = 0;
        while (ti < tasks.len and !need_indirect) : (ti += 1) {
            var i: usize = tasks[ti].start_idx + 1;
            while (i < tasks[ti].end_idx) : (i += 1) {
                const base = verified.annotated[i].base;
                if (base.kind != .call and base.kind != .call_indirect) continue;
                if (call.parseInstructionCall(allocator, base, verified.symbols)) |*pc| {
                    var parsed = pc.*;
                    defer parsed.deinit(allocator);
                    if (parsed.is_indirect) need_indirect = true;
                } else |_| {}
            }
        }
    }
    // Host-side dispatch: some staged bindings (pthread_spawn) invoke
    // guest code via sa_call_indirect, so a program that calls them needs
    // the dispatcher+ftable even without a call_indirect instruction.
    // (Corner: a call inside otherwise-dead code still forces it; no demo
    // hits that, and the sweep guards -Wall cleanliness.)
    if (!need_indirect) {
        var ti: usize = 0;
        while (ti < tasks.len and !need_indirect) : (ti += 1) {
            var i: usize = tasks[ti].start_idx + 1;
            while (i < tasks[ti].end_idx) : (i += 1) {
                const base = verified.annotated[i].base;
                if (base.kind != .call) continue;
                if (call.parseInstructionCall(allocator, base, verified.symbols)) |*pc| {
                    var parsed = pc.*;
                    defer parsed.deinit(allocator);
                    if (!parsed.is_indirect and bindingNeedsDispatcher(sigNormName(parsed.callee))) need_indirect = true;
                } else |_| {}
            }
        }
    }
    // Reachable defined functions: BFS from entry points over static direct
    // calls, keyed by fsig_index. Unreachable definitions are skipped
    // entirely (emitting them trips -Wunused-function and they are dead
    // code to auditors). The only roots are `main` and, with indirect
    // dispatch, the vtable entries referenced by the ftable initializer.
    // NOTE: exports/tests are deliberately NOT roots: this backend emits a
    // linked program (`int main`), not a library, so an uncalled export is
    // dead code here. (A unit with no main at all keeps everything.)
    // A dynamically called function must hold a vtable slot (`.func`
    // operands resolve via fn_idx), so static reachability + fn_names is
    // exact: nothing reachable is ever skipped.
    var reachable = std.AutoHashMap(usize, void).init(allocator);
    defer reachable.deinit();
    {
        var has_entry = false;
        for (tasks) |task| {
            if (task.kind == .extern_decl) continue;
            const norm = sigNormName(verified.function_sigs[task.fsig_index].name);
            if (std.mem.eql(u8, norm, "main")) {
                try reachable.put(task.fsig_index, {});
                has_entry = true;
            }
        }
        if (need_indirect) {
            for (fn_names.items) |fname| {
                if (taskIndexByName(tasks, verified, sigNormName(fname))) |ci| {
                    try reachable.put(ci, {});
                }
                has_entry = true;
            }
        }
        if (!has_entry) {
            // Pure library unit (no entry point): keep everything.
            for (tasks) |task| {
                if (task.kind == .extern_decl) continue;
                try reachable.put(task.fsig_index, {});
            }
        } else {
            var queue = std.array_list.Managed(usize).init(allocator);
            defer queue.deinit();
            var rit = reachable.iterator();
            while (rit.next()) |e| try queue.append(e.key_ptr.*);
            var qi: usize = 0;
            while (qi < queue.items.len) : (qi += 1) {
                const cur = queue.items[qi];
                for (tasks) |task| {
                    if (task.kind == .extern_decl) continue;
                    if (task.fsig_index != cur) continue;
                    var i: usize = task.start_idx + 1;
                    while (i < task.end_idx) : (i += 1) {
                        const base = verified.annotated[i].base;
                        if (base.kind != .call and base.kind != .call_indirect) continue;
                        if (call.parseInstructionCall(allocator, base, verified.symbols)) |*pc| {
                            var parsed = pc.*;
                            defer parsed.deinit(allocator);
                            if (parsed.is_indirect) continue;
                            if (taskIndexByName(tasks, verified, sigNormName(parsed.callee))) |ci| {
                                if (!reachable.contains(ci)) {
                                    try reachable.put(ci, {});
                                    try queue.append(ci);
                                }
                            }
                        } else |_| {}
                    }
                }
            }
        }
    }
    // Task-formed @gpu set: the downward closure of the recursive
    // @gpu SCCs (empty for most programs). See TASKFORM_DESIGN.md.
    var tfprog = try buildTfProgram(allocator, verified, tasks, &reachable);
    defer tfprog.deinit(allocator);
    // Unanimous ftable return domain: every successful indirect call
    // lands on an ftable entry (bounds + null checked in the dispatcher),
    // so when all entries share one return domain the indirect result
    // domain is exact (e.g. single-callback tables returning f32).
    // Non-unanimous (or empty) tables keep the unknown default.
    var indirect_ret_width: ?u32 = null;
    if (need_indirect and fn_names.items.len > 0) {
        var acc: ?u32 = null;
        var unanimous = true;
        var first = true;
        for (fn_names.items) |fname| {
            const w = sigReturnWidth(sigmap, fname);
            if (first) {
                acc = w;
                first = false;
            } else if (!std.meta.eql(acc, w)) {
                unanimous = false;
                break;
            }
        }
        if (unanimous) indirect_ret_width = acc;
    }
    // Const address layout (pure; #defines are emitted in phase 2 after
    // the helper scan so the preamble comes first in the file).
    var const_addrs = std.StringHashMap(usize).init(allocator);
    defer const_addrs.deinit();
    var const_cursor: usize = 4096;
    const bump_start: usize = 65536;
    var has_const_bytes = false;
    for (verified.const_decls) |decl| {
        const len = constBytesLen(decl.value) catch 0;
        const aligned = std.mem.alignForward(usize, const_cursor, 8);
        if (decl.value == .vtable or len == 0) {
            const is_vt = decl.value == .vtable;
            const slots: usize = if (is_vt) decl.value.vtable.slots.len * 8 else 8;
            const a2 = std.mem.alignForward(usize, const_cursor, 8);
            if (a2 + slots > bump_start) return CEmitError.Failed;
            try const_addrs.put(decl.name, a2);
            const_cursor = a2 + slots;
            continue;
        }
        if (aligned + len > bump_start) return CEmitError.Failed;
        try const_addrs.put(decl.name, aligned);
        has_const_bytes = true;
        const_cursor = aligned + len;
    }
    var rest: std.Io.Writer.Allocating = .init(allocator);
    defer rest.deinit();
    const rw = &rest.writer;
    // Phase 1: const-init + function bodies go to a side buffer first so
    // phase 2 can scan the exact helper set referenced and emit only
    // those (no dead runtime helpers for Coverity/Semgrep to flag).
    // const init
    try rw.writeAll("static void sa_init_consts(void) {\n  static int done = 0; if (done) return; done = 1;\n");
    for (verified.const_decls) |decl| {
        const init_len = constBytesLen(decl.value) catch 0;
        if (decl.value == .vtable or init_len == 0) {
            if (decl.value == .vtable) {
                var sidx: usize = 0;
                for (decl.value.vtable.slots) |vslot| {
                    const fidx = fnIndexOf(fn_idx, vslot.func_name) orelse return CEmitError.UnknownFunction;
                    const addr = const_addrs.get(decl.name) orelse return CEmitError.InvalidOperand;
                    const le: u64 = 1000000 + @as(u64, @intCast(fidx));
                    try rw.print("  sa_store_u64({d}ULL, {d}ULL);\n", .{ addr + sidx * 8, le });
                    sidx += 1;
                }
            }
            continue;
        }
        const bytes = try allocator.alloc(u8, init_len);
        defer allocator.free(bytes);
        try fillConstBytes(bytes, decl.value);
        const addr = const_addrs.get(decl.name) orelse return CEmitError.InvalidOperand;
        try rw.print("  {{ static const uint8_t b[] = {{", .{});
        for (bytes, 0..) |b, idx| {
            if (idx != 0) try rw.writeAll(",");
            try rw.print("{d}", .{b});
        }
        try rw.print("}}; {{ size_t i; for (i = 0; i < {d}; i++) sa_mem[{d} + i] = b[i]; }} }}\n", .{ init_len, addr });
    }
    try rw.writeAll("}\n");
    if (tfprog.count() > 0) try writeTfHeader(rw, verified, &tfprog);
    var emitted = std.StringHashMap(void).init(allocator);
    defer emitted.deinit();
    for (tasks) |task| {
        if (task.kind == .extern_decl) continue;
        const efsig = verified.function_sigs[task.fsig_index];
        if (emitted.contains(efsig.name)) continue;
        // Unreachable definitions are dead code: skip (else
        // -Wunused-function). Reachability is exact (see above).
        if (reachable.get(task.fsig_index) == null) continue;
        const tfctx: ?TfFnCtx = if (tfprog.fnid_of_fsig.get(task.fsig_index)) |fid| TfFnCtx{ .prog = &tfprog, .fnid = fid } else null;
        try emitOneFunction(rw, allocator, verified, task, &const_addrs, &fn_idx, c_opt, &sigmap, uniform_arity, indirect_ret_width, tfctx);
        try emitted.put(efsig.name, {});
    }
    if (tfprog.count() > 0) try writeTfMachinery(rw, verified, &tfprog);
    // Phase 2: helper-use scan, then the file preamble (which must precede
    // any `sa_u64`-typed declaration in output order).
    const rest_text = try rest.toOwnedSlice();
    defer allocator.free(rest_text);
    var used = try collectUsedHelpers(allocator, rest_text);
    defer used.deinit();
    // Seed helper uses from extern binding bodies (emitted after the
    // preamble): render each called, known binding once and merge what
    // it references, so e.g. mmap pulls sa_alloc. Unknown externs keep
    // the trap stub, which needs only sa_trap (always present).
    // Rendering an sa_http_* binding also raises need_http for the
    // staged state tables.
    var need_http = false;
    var need_owned = false;
    var need_modstate = false;
    var need_regex = false;
    var need_time_clock = false;
    var need_json = false;
    var need_stdlink = false;
    var need_task_entry = false;
    var need_sys_stat = false;
    var need_mem_direct = false;
    for (tasks) |task| {
        if (task.kind != .extern_decl) continue;
        const efsig = verified.function_sigs[task.fsig_index];
        if (std.mem.eql(u8, sigNormName(efsig.name), "sa_print_bytes")) continue;
        if (!bodyCallsFunction(rest_text, efsig.name)) continue;
        var tmp: std.Io.Writer.Allocating = .init(allocator);
        defer tmp.deinit();
        if (!try writeExternBinding(&tmp.writer, efsig.name, uniform_arity, c_opt.gas)) continue;
        const rendered_norm = sigNormName(efsig.name);
        if (isStdlinkExtern(rendered_norm)) need_stdlink = true;
        if (bindingNeedsTaskEntry(rendered_norm)) need_task_entry = true;
        if (std.mem.startsWith(u8, rendered_norm, "sa_http_")) need_http = true;
        if (std.mem.indexOf(u8, tmp.writer.buffered(), "sa_owned_") != null) need_owned = true;
        if (std.mem.indexOf(u8, tmp.writer.buffered(), "sa_modstate_") != null) need_modstate = true;
        if (std.mem.indexOf(u8, tmp.writer.buffered(), "sa_regex_") != null) need_regex = true;
        if (std.mem.indexOf(u8, tmp.writer.buffered(), "clock_gettime") != null) need_time_clock = true;
        if (std.mem.indexOf(u8, tmp.writer.buffered(), "sa_json_") != null) need_json = true;
        if (std.mem.indexOf(u8, tmp.writer.buffered(), "sa_mkdir_wrap") != null or std.mem.indexOf(u8, tmp.writer.buffered(), "sa_access_wrap") != null) need_sys_stat = true;
        // Bindings touching sa_mem directly (not via helpers) still need
        // the memory itself (e.g. the JSON parser's hot loops).
        if (std.mem.indexOf(u8, tmp.writer.buffered(), "sa_mem[") != null) need_mem_direct = true;
        const t = try tmp.toOwnedSlice();
        defer allocator.free(t);
        // Self-check every rendered binding: unbalanced output fails the
        // build loudly instead of emitting broken C (covers all present
        // and future bindings with no list to keep in sync).
        if (!cBodyBalanced(t)) return CEmitError.Failed;
        // Same for unused params (voids-mask precision).
        if (!cParamsCovered(t, uniform_arity)) return CEmitError.Failed;
        var bu = try collectUsedHelpers(allocator, t);
        defer bu.deinit();
        var bit = bu.iterator();
        while (bit.next()) |e| try used.put(e.key_ptr.*, {});
    }
    if (!need_stdlink) {
        // The generated main unconditionally calls
        // sa_install_sigpipe_ignore (the startup anchor that pulls
        // the runtime archive into stdlink programs). A standalone
        // (non-stdlink) C file has no archive to pull from, so the
        // catalog definition above is emitted instead; stdlink
        // programs keep resolving the symbol from libsa_std.a.
        try used.put("sa_install_sigpipe_ignore", {});
    }
    if (need_stdlink) {
        // The sa_glue_* adapters emitted by the preamble call
        // these catalog helpers directly; pull them and
        // their dependency closure into the used set.
        try used.put("sa_addr", {});
        try used.put("sa_checked_addr", {});
        try used.put("sa_align", {});
        try used.put("sa_alloc", {});
        try used.put("sa_store_u32", {});
        try used.put("sa_store_u64", {});
    }
    // Linear memory is needed for const bytes or any mem-touching helper.
    // (sa_brk only travels with the allocator; sa_mem stays out entirely
    // for pure-compute programs.)
    var need_mem = has_const_bytes or need_mem_direct;
    if (!need_mem) {
        // Helpers touching sa_mem directly (not just via other helpers).
        for (kRuntimeHelpers) |h| {
            if (used.get(h.name) != null and std.mem.indexOf(u8, h.code, "sa_mem") != null) {
                need_mem = true;
                break;
            }
        }
    }
    if (!need_mem) {
        var uit = used.iterator();
        while (uit.next()) |e| {
            const n = e.key_ptr.*;
            if (std.mem.startsWith(u8, n, "sa_load_") or std.mem.startsWith(u8, n, "sa_store_") or std.mem.eql(u8, n, "sa_alloc") or std.mem.eql(u8, n, "sa_print_bytes")) {
                need_mem = true;
                break;
            }
        }
    }
    const need_brk = used.get("sa_alloc") != null;
    try writePreamble(writer, c_opt, size_bits, &used, need_mem, need_brk, need_http, need_owned, need_modstate, need_regex, need_time_clock, need_sys_stat, need_json, need_stdlink);
    try writer.print("/* source: {s} */\n", .{source_path});
    // const address defines
    for (verified.const_decls) |decl| {
        const addr = const_addrs.get(decl.name) orelse return CEmitError.InvalidOperand;
        try writer.writeAll("#define ");
        try writeConstSym(writer, decl.name);
        if (decl.value == .vtable) {
            try writer.print(" {d}UL /* vtable */\n", .{addr});
        } else {
            const def_len = constBytesLen(decl.value) catch 0;
            if (def_len == 0) {
                try writer.print(" {d}UL /* {s} */\n", .{ addr, @tagName(decl.value) });
            } else {
                try writer.print(" {d}UL\n", .{addr});
            }
        }
    }
    // forward decls (uniform arity); only for emitted functions, so no
    // decl is left without a definition (-Wunused-function).
    for (tasks) |task| {
        if (task.kind == .extern_decl) continue;
        if (reachable.get(task.fsig_index) == null) continue;
        const fsig = verified.function_sigs[task.fsig_index];
        try writer.writeAll("static sa_u64 ");
        try cFuncName(writer, fsig.name);
        try writer.writeAll("(");
        if (uniform_arity == 0) {
            try writer.writeAll("void");
        } else {
            for (0..uniform_arity) |pi| {
                if (pi != 0) try writer.writeAll(", ");
                try writer.writeAll("sa_u64");
            }
        }
        try writer.writeAll(");\n");
    }
    // Forward declaration for the indirect dispatcher (defined after all
    // functions so the ftable can reference them). Only when a dynamic
    // call site exists; otherwise it would be dead code.
    if (need_indirect) {
        try writer.writeAll("// NOLINTNEXTLINE(bugprone-easily-swappable-parameters): generated uniform calling convention\nstatic sa_u64 sa_call_indirect(sa_u64 f");
        for (0..uniform_arity) |k| {
            try writer.print(", sa_u64 a{d}", .{k});
        }
        try writer.writeAll(");\n");
    }
    // Goroutine glue trampolines (C1): the archive task runtime calls
    // host function pointers, while guest functions are ftable indices
    // here. The spawn / once_do bindings hand the runtime these
    // trampolines plus a small host-side record carrying the guest
    // entry index and the guest argument value. The plain entry
    // trampoline frees the record; the supervised path keeps it (the
    // trap sink may fire later and frees it there; a supervised task
    // that never traps leaks its one small record — host glue only).
    if (need_task_entry) {
        try writer.writeAll("typedef struct { sa_u64 entry; sa_u64 arg; sa_u64 sink; sa_u64 sink_ctx; } sa_glue_task_ctx;\n");
        try writer.writeAll("static void sa_glue_task_entry(void *p) { sa_glue_task_ctx *c = (sa_glue_task_ctx *)p; sa_u64 e = c->entry; sa_u64 a = c->arg; free(c); (void)sa_call_indirect(e, a");
        for (1..uniform_arity) |_| {
            try writer.writeAll(", 0");
        }
        try writer.writeAll("); }\n");
        try writer.writeAll("static void sa_glue_task_entry_keep(void *p) { sa_glue_task_ctx *c = (sa_glue_task_ctx *)p; (void)sa_call_indirect(c->entry, c->arg");
        for (1..uniform_arity) |_| {
            try writer.writeAll(", 0");
        }
        try writer.writeAll("); }\n");
        try writer.writeAll("static void sa_glue_trap_sink(sa_u64 h, int32_t code, const uint8_t *mp, sa_u64 ml, void *p) { sa_glue_task_ctx *c = (sa_glue_task_ctx *)p; sa_u64 g = 0; if (ml != 0 && mp != 0) { g = sa_alloc(ml); { uint32_t d = sa_checked_addr(g, (size_t)ml); memcpy(&sa_mem[d], mp, (size_t)ml); } } (void)sa_call_indirect(c->sink, h, (sa_u64)(sa_i64)code, g, ml, c->sink_ctx");
        if (uniform_arity > 5) {
            for (5..uniform_arity) |_| {
                try writer.writeAll(", 0");
            }
        }
        try writer.writeAll("); free(c); }\n");
    }
    // forward declarations for extern trap stubs (defined at the end):
    // without these, calls to externs hit implicit-declaration errors.
    // Only for called externs (a static decl without a definition or use
    // trips -Wunused-function).
    for (tasks) |task| {
        if (task.kind != .extern_decl) continue;
        const fsig = verified.function_sigs[task.fsig_index];
        if (std.mem.eql(u8, sigNormName(fsig.name), "sa_print_bytes")) continue;
        if (!bodyCallsFunction(rest_text, fsig.name)) continue;
        try writer.writeAll("static sa_u64 ");
        try cFuncName(writer, fsig.name);
        try writer.writeAll("(");
        if (uniform_arity == 0) {
            try writer.writeAll("void");
        } else {
            for (0..uniform_arity) |pi| {
                if (pi != 0) try writer.writeAll(", ");
                try writer.writeAll("sa_u64");
            }
        }
        try writer.writeAll(");\n");
    }
    // Fwd decls for vtable-referenced functions with no definition: only
    // needed alongside the ftable (dead otherwise).
    if (need_indirect) {
        for (fn_names.items) |fname| {
            var defined = false;
            for (tasks) |task| {
                if (task.kind == .extern_decl) continue;
                if (std.mem.eql(u8, verified.function_sigs[task.fsig_index].name, fname)) {
                    defined = true;
                    break;
                }
            }
            if (defined) continue;
            try writer.writeAll("static sa_u64 ");
            try cFuncName(writer, fname);
            try writer.writeAll("(");
            if (uniform_arity == 0) {
                try writer.writeAll("void");
            } else {
                for (0..uniform_arity) |pi| {
                    if (pi != 0) try writer.writeAll(", ");
                    try writer.writeAll("sa_u64");
                }
            }
            try writer.writeAll(");\n");
        }
    }
    try writer.writeAll(rest_text);
    for (tasks) |task| {
        if (task.kind != .extern_decl) continue;
        const fsig = verified.function_sigs[task.fsig_index];
        if (emitted.contains(fsig.name)) continue;
        if (std.mem.eql(u8, sigNormName(fsig.name), "sa_print_bytes")) continue; // runtime provides it
        // Only emit a stub when the body actually calls it: an unreferenced
        // static definition trips -Wunused-function (and reads as dead
        // code to auditors). Externs are only reachable via direct calls,
        // which render as `sa_fn_<name>(`, so a text scan is exact.
        if (!bodyCallsFunction(rest_text, fsig.name)) continue;
        // Known externs get staged host bindings; anything else keeps the
        // trap stub (uniform arity).
        if (try writeExternBinding(writer, fsig.name, uniform_arity, c_opt.gas)) {
            try emitted.put(fsig.name, {});
            continue;
        }
        // trap stub (uniform arity)
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
        try writer.writeAll(") {");
        for (0..uniform_arity) |pi| {
            try writer.print(" (void)a{d};", .{pi});
        }
        try writer.print(" sa_trap(\"extern {s}\"); return 0; }}\n", .{fsig.name});
        try emitted.put(fsig.name, {});
    }
    // Trap stubs for vtable-referenced functions with no definition.
    // Only with the ftable: every entry is referenced by its initializer,
    // so no stub is ever dead.
    if (need_indirect) {
        for (fn_names.items) |fname| {
            if (emitted.contains(fname)) continue;
            var found = false;
            for (tasks) |task| {
                if (std.mem.eql(u8, verified.function_sigs[task.fsig_index].name, fname)) {
                    found = true;
                    break;
                }
            }
            if (found) continue;
            try writer.writeAll("static sa_u64 ");
            try cFuncName(writer, fname);
            try writer.writeAll("(");
            if (uniform_arity == 0) {
                try writer.writeAll("void");
            } else {
                for (0..uniform_arity) |pi| {
                    if (pi != 0) try writer.writeAll(", ");
                    try writer.print("sa_u64 a{d}", .{pi});
                }
            }
            try writer.writeAll(") {");
            for (0..uniform_arity) |pi| {
                try writer.print(" (void)a{d};", .{pi});
            }
            try writer.print(" sa_trap(\"missing {s}\"); return 0; }}\n", .{fname});
            try emitted.put(fname, {});
        }
    }
    // Indirect dispatch: uniform signature makes a plain function-pointer
    // table exact (indices match fn_idx / vtable const encoding). Skipped
    // entirely without a dynamic call site (dead otherwise).
    if (need_indirect) {
        try writer.writeAll("typedef sa_u64 (*sa_fn_t)(");
        if (uniform_arity == 0) {
            try writer.writeAll("void");
        } else {
            for (0..uniform_arity) |pi| {
                if (pi != 0) try writer.writeAll(", ");
                try writer.writeAll("sa_u64");
            }
        }
        // A zero-length array is a GNU extension and makes the bounds check
        // tautological; pin a single NULL entry instead.
        if (fn_names.items.len == 0) {
            try writer.writeAll(");\nstatic sa_fn_t sa_ftable[1] = {0};\n");
        } else {
            try writer.writeAll(");\nstatic sa_fn_t sa_ftable[] = {");
            for (fn_names.items, 0..) |fname, fi| {
                if (fi != 0) try writer.writeAll(", ");
                try cFuncName(writer, fname);
            }
            try writer.writeAll("};\n");
        }
        try writer.writeAll("// NOLINTNEXTLINE(bugprone-easily-swappable-parameters): generated uniform calling convention\nstatic sa_u64 sa_call_indirect(sa_u64 f");
        for (0..uniform_arity) |k| {
            try writer.print(", sa_u64 a{d}", .{k});
        }
        // Lower-bound check first: `f - 1000000` wraps for f < 1000000, so
        // the old `uint64_t idx = f - 1000000; if (idx >= 0)` was always
        // true and trapped every indirect call.
        try writer.writeAll(") {\n  if (f < 1000000ULL) { sa_trap(\"bad indirect callee\"); }\n");
        try writer.writeAll("  { sa_u64 idx = f - 1000000ULL;\n");
        try writer.writeAll("    if (idx >= (sa_u64)(sizeof(sa_ftable) / sizeof(sa_ftable[0]))) { sa_trap(\"bad indirect callee\"); }\n");
        try writer.writeAll("    if (sa_ftable[idx] == 0) { sa_trap(\"null indirect callee\"); }\n");
        try writer.writeAll("    return sa_ftable[idx](");
        for (0..uniform_arity) |k| {
            if (k != 0) try writer.writeAll(", ");
            try writer.print("a{d}", .{k});
        }
        try writer.writeAll("); }\n}\n");
    }
    try writer.writeAll("int main(void) { extern void sa_install_sigpipe_ignore(void); sa_install_sigpipe_ignore(); sa_init_consts();\n");
    if (c_opt.gas) {
        // Keeps `sa_gas` referenced even for (degenerate) programs whose
        // functions were all elided; normally the SA_GAS_CHECKs do that.
        try writer.writeAll("  (void)sa_gas;\n");
    }
    // call sa main if present
    var found_main = false;
    for (tasks) |task| {
        if (task.kind == .extern_decl) continue;
        const fsig = verified.function_sigs[task.fsig_index];
        if (std.mem.eql(u8, fsig.name, "main")) {
            found_main = true;
            break;
        }
    }
    if (found_main) {
        try writer.writeAll("  sa_u64 rc = sa_fn_main(");
        for (0..uniform_arity) |k| {
            if (k != 0) try writer.writeAll(", ");
            try writer.writeAll("0");
        }
        try writer.writeAll(");\n  return (int)(rc & 0xFF);\n}\n");
    } else {
        try writer.writeAll("  return 0;\n}\n");
    }
    return out.toOwnedSlice();
}

pub fn emitCToFile(allocator: std.mem.Allocator, verified: anytype, source_path: []const u8, size_bits: u16, c_opt: CEmitOptions, path: []const u8) !void {
    const text = try emitCToString(allocator, verified, source_path, size_bits, c_opt);
    defer allocator.free(text);
    const dir = std.fs.path.dirname(path);
    if (dir) |d| try sio.cwd().makePath(d);
    const f = try sio.cwd().createFile(path, .{});
    defer f.close();
    try f.writeAll(text);
}
