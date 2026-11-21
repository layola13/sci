const std = @import("std");
const builtin = @import("builtin");
const sio = @import("sio");
const call = @import("../referee/call.zig");
const cap = @import("../common/capability.zig");
const atomic = @import("../common/atomic.zig");
const gas = @import("../common/gas.zig");
const const_decl = @import("../common/const_decl.zig");
const inst = @import("../common/instruction.zig");
const pkg_manifest = @import("../pkg/manifest.zig");
const sig = @import("../common/signature.zig");
const trap = @import("../common/trap.zig");
const upstream = @import("../common/upstream_loc.zig");
const classifier = @import("../flattener/line_classifier.zig");
const symbol = @import("../flattener/symbol.zig");

const AnnotatedInstruction = @import("reg_state_change.zig").AnnotatedInstruction;
const CollectResult = @import("reg_state_change.zig").CollectResult;
const ParallelFunctionChunk = @import("reg_state_change.zig").ParallelFunctionChunk;
const ParallelVerifyContext = @import("reg_state_change.zig").ParallelVerifyContext;
const ParallelVerifyJob = @import("reg_state_change.zig").ParallelVerifyJob;
const ParallelVerifyWorker = @import("reg_state_change.zig").ParallelVerifyWorker;
const RegStateChange = @import("reg_state_change.zig").RegStateChange;
const SaxValidationContext = @import("reg_state_change.zig").SaxValidationContext;
const VerifyBodyResult = @import("reg_state_change.zig").VerifyBodyResult;
const VerifyOptions = @import("reg_state_change.zig").VerifyOptions;
const VerifyResult = @import("reg_state_change.zig").VerifyResult;
const VerifyStageReporter = @import("reg_state_change.zig").VerifyStageReporter;
const classifyInstructions = @import("reg_state_change.zig").classifyInstructions;
const cleanupParallelJobResults = @import("reg_state_change.zig").cleanupParallelJobResults;
const collectMetadata = @import("collect_metadata.zig").collectMetadata;
const collectPredecodedMetadata = @import("collect_metadata.zig").collectPredecodedMetadata;
const emptyRegStateDelta = @import("reg_state_change.zig").emptyRegStateDelta;
const freeAnnotated = @import("clear_borrow_ctx.zig").freeAnnotated;
const freeConstVtables = @import("clear_borrow_ctx.zig").freeConstVtables;
const freeFunctionStarts = @import("clear_borrow_ctx.zig").freeFunctionStarts;
const freeSigs = @import("clear_borrow_ctx.zig").freeSigs;
const isDecl = @import("const_trap.zig").isDecl;
const isExitLeakReport = @import("clear_borrow_ctx.zig").isExitLeakReport;
const metadataTrapHint = @import("collect_metadata.zig").metadataTrapHint;
const metadataTrapKind = @import("collect_metadata.zig").metadataTrapKind;
const metadataTrapMessage = @import("collect_metadata.zig").metadataTrapMessage;
const trapReportFromText = @import("sax_trap_report.zig").trapReportFromText;
const verifyBody = @import("verify_body.zig").verifyBody;

pub fn freeAnnotatedSlice(allocator: std.mem.Allocator, annotated: []AnnotatedInstruction) void {
    for (annotated) |item| {
        var owned = item;
        owned.deinit(allocator);
    }
    allocator.free(annotated);
}

pub fn buildVerifyChunks(
    allocator: std.mem.Allocator,
    instructions: []const inst.Instruction,
) ![]ParallelFunctionChunk {
    if (instructions.len == 0) {
        return try allocator.alloc(ParallelFunctionChunk, 0);
    }

    var chunks = std.array_list.Managed(ParallelFunctionChunk).init(allocator);
    errdefer chunks.deinit();

    var current_start: ?usize = null;
    var current_sig_index: usize = 0;
    var next_sig_index: usize = 0;
    var saw_decl = false;

    for (instructions, 0..) |item, idx| {
        if (isDecl(item.kind)) {
            saw_decl = true;
            if (current_start) |start| {
                try chunks.append(.{
                    .start = start,
                    .end = idx,
                    .sig_index = current_sig_index,
                });
            }
            current_start = idx;
            current_sig_index = next_sig_index;
            next_sig_index += 1;
            continue;
        }

        if (!saw_decl) {
            return try allocator.alloc(ParallelFunctionChunk, 0);
        }
    }

    if (current_start) |start| {
        try chunks.append(.{
            .start = start,
            .end = instructions.len,
            .sig_index = current_sig_index,
        });
    }

    return try chunks.toOwnedSlice();
}

/// Adaptive serial dispatch (LINE-VERIFY-MERGE-REDISPATCH): the parallel
/// path pays a fixed per-chunk cost of ~0.22-0.34 ms (worker job setup
/// through the thread-safe DebugAllocator plus stream-merge bookkeeping,
/// measured on the function-size sweep, InstaBox main, 4 workers), so on
/// modules made of many small functions it loses to the serial path at
/// every tier (2.0-2.8x at mean chunk size <= ~410 instructions). The
/// parallel path only wins once chunks are large (measured crossover
/// band: mean chunk size ~800-1,100 instructions) or there are too few
/// chunks for the fixed cost to accumulate. Force serial in the proven
/// loss zone only: many chunks AND small mean chunk size. Everywhere
/// else the requested worker count stands. This can only ever downgrade
/// to serial, never upgrade past the requested count.
pub const adaptive_serial_min_chunks: usize = 256;
pub const adaptive_serial_max_mean_chunk_inst: usize = 1024;

pub fn chooseVerifyWorkerCount(requested_jobs: ?usize, chunk_count: usize, total_instructions: usize) usize {
    if (chunk_count < 2) return 1;
    if (chunk_count >= adaptive_serial_min_chunks and
        total_instructions / chunk_count < adaptive_serial_max_mean_chunk_inst)
    {
        return 1;
    }
    if (requested_jobs) |jobs| {
        return if (jobs <= 1) 1 else @min(jobs, chunk_count);
    }
    const cpu_count = std.Thread.getCpuCount() catch 1;
    return if (cpu_count <= 1) 1 else @min(cpu_count, chunk_count);
}

pub fn verifyWorker(context: *ParallelVerifyContext, worker_index: usize) void {
    defer _ = context.workers_done.fetchAdd(1, .release);
    const worker_allocator = context.workers[worker_index].allocator();
    while (true) {
        const chunk_index = context.next_chunk.fetchAdd(1, .monotonic);
        if (chunk_index >= context.chunks.len) return;

        const chunk = context.chunks[chunk_index];
        const job = &context.jobs[chunk_index];
        job.worker_index = worker_index;
        const result = verifyBody(
            worker_allocator,
            context.instructions[chunk.start..chunk.end],
            context.classified_lines[chunk.start..chunk.end],
            context.const_decls,
            context.metadata,
            chunk.sig_index,
            context.check_exit_leaks,
            context.package_grants,
            context.sax_context,
            context.default_immutable,
        ) catch |err| {
            job.err = err;
            job.state.store(3, .release);
            return;
        };
        job.result = result;
        job.state.store(switch (result) {
            .ok => 1,
            .trap => 2,
        }, .release);
    }
}

/// Merge one published chunk result into the final annotated list,
/// dup'ing per-instruction delta changes into `allocator`; the worker
/// copy is freed with the owning worker's allocator and the job is
/// marked consumed (state 4). Only called for .ok results.
pub fn mergeJobIntoList(
    allocator: std.mem.Allocator,
    workers: []ParallelVerifyWorker,
    job: *ParallelVerifyJob,
    annotated: *std.array_list.Managed(AnnotatedInstruction),
) !void {
    const ok = job.result.?.ok;
    defer {
        freeAnnotatedSlice(workers[job.worker_index].allocator(), ok.annotated);
        job.result = null;
        job.state.store(4, .release);
    }
    for (ok.annotated) |item| {
        const delta_changes = if (item.delta.changes.len == 0)
            emptyRegStateDelta().changes
        else
            try allocator.dupe(RegStateChange, item.delta.changes);
        var delta_owned = false;
        defer if (!delta_owned and delta_changes.len != 0) allocator.free(delta_changes);
        try annotated.append(.{
            .base = item.base,
            .delta = .{ .changes = delta_changes },
            .gas_step_cost = item.gas_step_cost,
        });
        delta_owned = true;
    }
}

pub fn verifyParallel(
    allocator: std.mem.Allocator,
    instructions: []const inst.Instruction,
    classified_lines: []const classifier.ClassifiedLine,
    const_decls: []const const_decl.ConstDecl,
    metadata: *const CollectResult,
    package_grants: []const pkg_manifest.RequireEntry,
    sax_context: ?SaxValidationContext,
    chunks: []const ParallelFunctionChunk,
    requested_jobs: ?usize,
    check_exit_leaks: bool,
    stage_reporter: ?VerifyStageReporter,
    default_immutable: bool,
) !VerifyBodyResult {
    const worker_count = chooseVerifyWorkerCount(requested_jobs, chunks.len, instructions.len);
    if (worker_count <= 1) {
        return verifyBody(allocator, instructions, classified_lines, const_decls, metadata, 0, check_exit_leaks, package_grants, sax_context, default_immutable);
    }

    if (stage_reporter) |reporter| reporter.report("parallel_start", worker_count, chunks.len);

    const jobs = try allocator.alloc(ParallelVerifyJob, chunks.len);
    for (jobs) |*job| {
        job.* = .{};
    }
    defer {
        allocator.free(jobs);
    }

    const workers = try allocator.alloc(ParallelVerifyWorker, worker_count);
    for (workers) |*worker| worker.* = .{};
    defer {
        for (workers) |*worker| worker.deinit();
        allocator.free(workers);
    }
    defer cleanupParallelJobResults(jobs, workers);
    if (stage_reporter) |reporter| reporter.report("parallel_after_worker_allocators", worker_count, chunks.len);

    var context = ParallelVerifyContext{
        .allocator = allocator,
        .instructions = instructions,
        .classified_lines = classified_lines,
        .const_decls = const_decls,
        .metadata = metadata,
        .package_grants = package_grants,
        .sax_context = sax_context,
        .chunks = chunks,
        .jobs = jobs,
        .workers = workers,
        .requested_jobs = requested_jobs,
        .check_exit_leaks = check_exit_leaks,
        .default_immutable = default_immutable,
        .next_chunk = std.atomic.Value(usize).init(0),
    };
    _ = context.allocator;
    _ = context.requested_jobs;

    const spawned_count = worker_count;
    var threads = try allocator.alloc(std.Thread, spawned_count);
    defer allocator.free(threads);
    var started_threads: usize = 0;
    errdefer {
        while (started_threads > 0) {
            started_threads -= 1;
            threads[started_threads].join();
        }
    }

    while (started_threads < spawned_count) : (started_threads += 1) {
        threads[started_threads] = try std.Thread.spawn(.{}, verifyWorker, .{ &context, started_threads });
    }

    var annotated = std.array_list.Managed(AnnotatedInstruction).init(allocator);
    errdefer freeAnnotated(allocator, &annotated);
    var gas_alloc_bytes: u64 = 0;
    var gas_steps: u64 = 0;
    var has_unbounded_loop = false;

    // STREAM-MERGE (LINE-OPT-VERIFY-STREAMMERGE): the calling thread
    // merges chunk results into the final annotated list in chunk
    // order at a watermark, freeing each worker-side copy as soon as
    // its chunk is consumed. Previously every chunk result stayed
    // resident in the workers' allocators until all bodies had
    // finished, and the merged copy was built only after the join, so
    // the verify in-body peak carried the full result payload plus
    // per-worker retained transients. Trap and error results are
    // never consumed here: the watermark stops at them, the workers
    // are joined, and the precedence scan below decides them exactly
    // as before; any chunk the stream did not reach is merged by the
    // tail loop after the join.
    var merged_count: usize = 0;
    stream: while (merged_count < jobs.len) {
        const job = &jobs[merged_count];
        switch (job.state.load(.acquire)) {
            1 => {
                const ok = job.result.?.ok;
                gas_alloc_bytes += ok.gas.max_alloc_bytes;
                switch (ok.gas.max_instruction_steps) {
                    .bounded => |steps| gas_steps += steps,
                    .unbounded => |unbounded| {
                        gas_steps += unbounded.bounded_prefix;
                        has_unbounded_loop = true;
                    },
                }
                if (ok.has_unbounded_loop) has_unbounded_loop = true;
                try mergeJobIntoList(allocator, workers, job, &annotated);
                merged_count += 1;
                if (stage_reporter) |reporter| {
                    if (merged_count == jobs.len or merged_count % 128 == 0) {
                        reporter.report("parallel_merge", merged_count, jobs.len);
                    }
                }
            },
            2, 3 => break :stream,
            else => {
                if (context.workers_done.load(.acquire) >= started_threads) break :stream;
                std.Thread.yield() catch {};
            },
        }
    }

    while (started_threads > 0) {
        started_threads -= 1;
        threads[started_threads].join();
    }
    if (stage_reporter) |reporter| reporter.report("parallel_after_body", chunks.len, chunks.len);

    // TRAP-PRECEDENCE (parallel path): chunks are single functions in
    // declaration order, so a plain first-trap merge lets an exit leak
    // in an early-declared callee pre-empt a trap that precedes it in
    // execution order (e.g. the call-site trap in its caller, verified
    // as a later chunk). Scan all chunk results first: the first
    // non-exit-leak trap wins; an exit leak is reported only when no
    // chunk raised anything else.
    {
        var deferred_leak: ?trap.TrapReport = null;
        for (jobs) |*job| {
            if (job.err) |err| return err;
            if (job.result == null) continue; // already consumed by the stream merge (was .ok)
            const result = job.result.?;
            switch (result) {
                .trap => |report| {
                    if (isExitLeakReport(report)) {
                        if (deferred_leak == null) deferred_leak = report;
                    } else {
                        freeAnnotated(allocator, &annotated);
                        return .{ .trap = report };
                    }
                },
                .ok => {},
            }
        }
        if (deferred_leak) |report| {
            freeAnnotated(allocator, &annotated);
            return .{ .trap = report };
        }
    }

    for (jobs, 0..) |*job, job_index| {
        if (job.err) |err| return err;
        const result = job.result orelse continue; // already consumed by the stream merge
        switch (result) {
            .trap => |report| {
                freeAnnotated(allocator, &annotated);
                return .{ .trap = report };
            },
            .ok => |ok| {
                defer {
                    freeAnnotatedSlice(workers[job.worker_index].allocator(), ok.annotated);
                    job.result = null;
                }
                for (ok.annotated) |item| {
                    const delta_changes = if (item.delta.changes.len == 0)
                        emptyRegStateDelta().changes
                    else
                        try allocator.dupe(RegStateChange, item.delta.changes);
                    var delta_owned = false;
                    defer if (!delta_owned and delta_changes.len != 0) allocator.free(delta_changes);
                    try annotated.append(.{
                        .base = item.base,
                        .delta = .{ .changes = delta_changes },
                        .gas_step_cost = item.gas_step_cost,
                    });
                    delta_owned = true;
                }
                gas_alloc_bytes += ok.gas.max_alloc_bytes;
                switch (ok.gas.max_instruction_steps) {
                    .bounded => |steps| gas_steps += steps,
                    .unbounded => |unbounded| {
                        gas_steps += unbounded.bounded_prefix;
                        has_unbounded_loop = true;
                    },
                }
                if (ok.has_unbounded_loop) {
                    has_unbounded_loop = true;
                }
            },
        }

        if (stage_reporter) |reporter| {
            const completed = job_index + 1;
            if (completed == jobs.len or completed % 128 == 0) {
                reporter.report("parallel_merge", completed, jobs.len);
            }
        }
    }

    const annotated_slice = try annotated.toOwnedSlice();
    return .{ .ok = .{
        .annotated = annotated_slice,
        .gas = .{
            .max_alloc_bytes = gas_alloc_bytes,
            .max_instruction_steps = if (has_unbounded_loop) .{ .unbounded = .{ .bounded_prefix = gas_steps } } else .{ .bounded = gas_steps },
            .call_depth = 0,
            .has_unbounded_loop = has_unbounded_loop,
        },
        .has_unbounded_loop = has_unbounded_loop,
    } };
}

/// GPU subset check (v1, spike): a function declared with kind `.gpu`
/// (@gpu) must stay inside the device-safe instruction subset. The rule
/// is a denylist; everything not listed is permitted (arithmetic/logic,
/// frame-local alloc/load/store, borrow/move/release, br/jmp, and calls
/// to other `.gpu` functions included):
///   - `call` to a function whose kind is not `.gpu` (host function,
///     @extern, @ffi_wrapper, plain @-function) — host calls cannot run
///     on a device;
///   - `call_indirect` — the target is not statically provable;
///   - `raw_cast` — the `*` raw-pointer downgrade leaves the verified
///     pointer model the device subset relies on;
///   - `native` — the $...$ native escape is host machine code by
///     definition;
///   - `panic` / `panic_msg` — the host trap path.
/// A callee that cannot be resolved to a declared signature is treated
/// as a host call (not provably a GPU function). Violations are
/// rejected with the named diagnostic GpuSubsetViolation (trap code
/// 1059). The check runs on the flattened instruction stream, so it
/// covers both the .sa text path and the SAB path (SAB decode
/// synthesizes call raw_text, see sab.zig synthesizeRawText).
pub fn checkGpuSubset(
    allocator: std.mem.Allocator,
    instructions: []const inst.Instruction,
    metadata: *const CollectResult,
) !?trap.TrapReport {
    const starts = metadata.function_starts.items;
    for (metadata.sigs.items, 0..) |gpu_sig, sig_idx| {
        if (gpu_sig.kind != .gpu) continue;
        const start = starts[sig_idx];
        const end = if (sig_idx + 1 < starts.len) starts[sig_idx + 1] else instructions.len;
        for (instructions[start..end]) |item| {
            const reason: ?[]const u8 = switch (item.kind) {
                .call_indirect => "indirect call target is not statically provable",
                .raw_cast => "raw pointer downgrade (*) leaves the GPU subset",
                .native => "native escape ($...$) is host-only",
                .panic, .panic_msg => "panic is a host trap path",
                .call => blk: {
                    // Structured form (same-module calls, and everything
                    // after a SAB round trip): operands[3] carries the
                    // callee as a .func symbol id. Text form: the callee
                    // is parsed out of the raw line.
                    var structured_name: ?[]const u8 = null;
                    if (item.operands[3] == .func) {
                        structured_name = metadata.symbols.lookupName(item.operands[3].func);
                    }
                    // SAB-decoded calls carry the call body as an operand
                    // text ("@pow2(m)"); the host check path does not
                    // synthesize raw_text for them, so read the callee
                    // straight from the body operand.
                    if (structured_name == null) {
                        for ([_]usize{ 1, 0 }) |op_idx| {
                            if (item.operands[op_idx] == .text) {
                                const body = std.mem.trim(u8, item.operands[op_idx].text, " \t");
                                if (body.len > 1 and body[0] == '@') {
                                    const open = std.mem.indexOfScalar(u8, body, '(') orelse body.len;
                                    structured_name = std.mem.trim(u8, body[1..open], " \t");
                                }
                            }
                            if (structured_name) |name| {
                                if (name.len != 0) break;
                                structured_name = null;
                            }
                        }
                    }
                    var parsed: ?call.ParsedCall = null;
                    defer if (parsed) |*p| p.deinit(allocator);
                    const callee_name: []const u8 = if (structured_name) |name|
                        name
                    else if (call.parseCall(allocator, item.raw_text)) |p| blk2: {
                        parsed = p;
                        break :blk2 p.callee;
                    } else |_| {
                        break :blk "call target could not be resolved to a @gpu function";
                    };
                    const callee_idx = metadata.sig_index_by_name.get(callee_name) orelse
                        break :blk "call target is not a declared @gpu function";
                    if (metadata.sigs.items[callee_idx].kind != .gpu)
                        break :blk "call target is not a @gpu function";
                    break :blk null;
                },
                else => null,
            };
            if (reason) |why| {
                return trapReportFromText(
                    .gpu_subset_violation,
                    item.expanded_line + 1,
                    item.source_line,
                    item.raw_text,
                    why,
                    "keep @gpu bodies to arithmetic, frame-local memory, branches, and calls to other @gpu functions",
                );
            }
        }
    }
    return null;
}

pub fn verifyWithOptions(
    allocator: std.mem.Allocator,
    instructions: []const inst.Instruction,
    const_decls: []const const_decl.ConstDecl,
    options: VerifyOptions,
) !VerifyResult {
    if (options.stage_reporter) |reporter| reporter.report("start", 0, instructions.len);

    if (instructions.len == 0) {
        const symbols = symbol.SymbolTable.init(allocator);
        if (options.stage_reporter) |reporter| reporter.report("empty", 0, 0);
        return .{ .ok = .{
            .annotated = &.{},
            .function_sigs = &.{},
            .symbols = symbols,
            .const_decls = const_decls,
            .gas = .{
                .max_alloc_bytes = 0,
                .max_instruction_steps = .{ .bounded = 0 },
                .call_depth = 0,
                .has_unbounded_loop = false,
            },
        } };
    }

    const classified_lines = try classifyInstructions(allocator, instructions, options.predecoded_symbol_names);
    defer allocator.free(classified_lines);
    if (options.stage_reporter) |reporter| reporter.report("after_classify", classified_lines.len, instructions.len);

    const has_predecoded_metadata = options.predecoded_symbol_names.len != 0 or options.predecoded_function_sigs.len != 0;
    var metadata = (if (has_predecoded_metadata)
        collectPredecodedMetadata(allocator, options.predecoded_symbol_names, options.predecoded_function_sigs, const_decls)
    else
        collectMetadata(allocator, instructions, classified_lines, const_decls)) catch |err| {
        return .{ .trap = trapReportFromText(
            metadataTrapKind(err),
            1,
            1,
            instructions[0].raw_text,
            metadataTrapMessage(err),
            metadataTrapHint(err),
        ) };
    };
    defer freeSigs(allocator, &metadata.sigs);
    defer metadata.sig_index_by_name.deinit();
    defer freeConstVtables(allocator, &metadata.const_vtables);
    defer freeFunctionStarts(&metadata.function_starts);
    var symbols_moved = false;
    defer if (!symbols_moved) metadata.symbols.deinit();
    defer metadata.const_ids.deinit();
    if (options.stage_reporter) |reporter| reporter.report("after_metadata", metadata.sigs.items.len, instructions.len);

    if (try checkGpuSubset(allocator, instructions, &metadata)) |report| {
        return .{ .trap = report };
    }

    const chunks = try buildVerifyChunks(allocator, instructions);
    defer allocator.free(chunks);
    if (options.stage_reporter) |reporter| reporter.report("after_chunks", chunks.len, instructions.len);
    const worker_count = chooseVerifyWorkerCount(options.jobs, chunks.len, instructions.len);

    const body_result = if (worker_count > 1 and chunks.len > 0) blk: {
        const parallel = try verifyParallel(allocator, instructions, classified_lines, const_decls, &metadata, options.package_grants, options.sax_context, chunks, options.jobs, options.check_exit_leaks, options.stage_reporter, options.default_immutable);
        break :blk parallel;
    } else blk: {
        const serial = try verifyBody(allocator, instructions, classified_lines, const_decls, &metadata, 0, options.check_exit_leaks, options.package_grants, options.sax_context, options.default_immutable);
        if (options.stage_reporter) |reporter| reporter.report("after_body", instructions.len, instructions.len);
        break :blk serial;
    };

    switch (body_result) {
        .trap => |report| return .{ .trap = report },
        .ok => |body| {
            const owned_body = body;
            var finalized = false;
            defer if (!finalized) freeAnnotatedSlice(allocator, owned_body.annotated);
            const sigs_slice = try metadata.sigs.toOwnedSlice();
            errdefer {
                for (sigs_slice) |*item| item.deinit(allocator);
                allocator.free(sigs_slice);
            }

            symbols_moved = true;
            finalized = true;
            if (options.stage_reporter) |reporter| reporter.report("after_finalize", owned_body.annotated.len, instructions.len);
            return .{ .ok = .{
                .annotated = owned_body.annotated,
                .function_sigs = sigs_slice,
                .symbols = metadata.symbols,
                .const_decls = const_decls,
                .gas = body.gas,
            } };
        },
    }
}

pub fn verify(
    allocator: std.mem.Allocator,
    instructions: []const inst.Instruction,
    const_decls: []const const_decl.ConstDecl,
) !VerifyResult {
    return verifyWithOptions(allocator, instructions, const_decls, .{});
}
