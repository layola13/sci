const std = @import("std");
const call = @import("../referee/call.zig");
const referee = @import("../referee.zig");
const emit_options = @import("../emit_options.zig");
const flattener = @import("../flattener.zig");
const inst = @import("../common/instruction.zig");
const atomic = @import("../common/atomic.zig");
const sig = @import("../common/signature.zig");
const const_decl = @import("../common/const_decl.zig");
const upstream = @import("../common/upstream_loc.zig");
const sio = @import("sio");

const CConst = @import("sa_llvmc_free.zig").CConst;
const CFuncKind = @import("sa_llvmc_free.zig").CFuncKind;
const CFunction = @import("sa_llvmc_free.zig").CFunction;
const CModule = @import("sa_llvmc_free.zig").CModule;
const CVTable = @import("sa_llvmc_free.zig").CVTable;
const EmitOptions = @import("sa_llvmc_free.zig").EmitOptions;
const ParallelEmitContext = @import("assign_operand.zig").ParallelEmitContext;
const ParallelEmitJob = @import("assign_operand.zig").ParallelEmitJob;
const ParallelEmitTask = @import("assign_operand.zig").ParallelEmitTask;
const buildFunctionSigIndex = @import("atomic_rmw_op.zig").buildFunctionSigIndex;
const buildSharedEmitTables = @import("atomic_rmw_op.zig").buildSharedEmitTables;
const chooseEmitWorkerCount = @import("assign_operand.zig").chooseEmitWorkerCount;
const collectAnonStringConsts = @import("sa_llvmc_free.zig").collectAnonStringConsts;
const collectBodyDirectCallees = @import("atomic_rmw_op.zig").collectBodyDirectCallees;
const collectDceReachability = @import("atomic_rmw_op.zig").collectDceReachability;
const collectSelectedTestReachability = @import("atomic_rmw_op.zig").collectSelectedTestReachability;
const constBytesLen = @import("sa_llvmc_free.zig").constBytesLen;
const emitJobBackingAllocator = @import("assign_operand.zig").emitJobBackingAllocator;
const emitWorker = @import("assign_operand.zig").emitWorker;
const emittedFunctionName = @import("sa_llvmc_free.zig").emittedFunctionName;
const fillConstBytes = @import("sa_llvmc_free.zig").fillConstBytes;
const markReachableFunctionByName = @import("atomic_rmw_op.zig").markReachableFunctionByName;
const recordLlvmcError = @import("sa_llvmc_free.zig").recordLlvmcError;
const sa_llvmc_emit_module_artifacts = @import("sa_llvmc_free.zig").sa_llvmc_emit_module_artifacts;
const sa_llvmc_emit_module_bitcode = @import("sa_llvmc_free.zig").sa_llvmc_emit_module_bitcode;
const sa_llvmc_emit_module_object = @import("sa_llvmc_free.zig").sa_llvmc_emit_module_object;
const sa_llvmc_free = @import("sa_llvmc_free.zig").sa_llvmc_free;
const shouldPruneUnreachableFunction = @import("atomic_rmw_op.zig").shouldPruneUnreachableFunction;
const sourceDirName = @import("sa_llvmc_free.zig").sourceDirName;
const sourceFileName = @import("sa_llvmc_free.zig").sourceFileName;
const takeOwnedBitcode = @import("sa_llvmc_free.zig").takeOwnedBitcode;

pub fn emitLlvmcInternal(allocator: std.mem.Allocator, verified: anytype, def_dict: ?*const flattener.DefDict, loc_table: upstream.LocTable, source_path: []const u8, size_bits: u16, options: EmitOptions, obj_path: ?[]const u8, opt_level: u8) ![]const u8 {
    _ = def_dict;
    // Extern variadic batch: the shim's va_list layout is the x86_64
    // SysV __va_list_tag; the wasm target has a different va_list model
    // and stays loudly unsupported in this batch.
    if (options.wasm_compat) {
        for (verified.function_sigs) |fsig| {
            if (fsig.is_variadic) return error.UnsupportedVariadic;
        }
    }
    if (options.debug and loc_table.len != verified.annotated.len) return error.InvalidOperand;
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const module_source_file = try a.dupeSentinel(u8, sourceFileName(source_path), 0);
    const module_source_dir = try a.dupeSentinel(u8, sourceDirName(source_path), 0);
    var function_sig_index = try buildFunctionSigIndex(a, verified.function_sigs);

    var c_consts = std.array_list.Managed(CConst).init(a);
    var c_vtables = std.array_list.Managed(CVTable).init(a);
    var anon_string_names = std.StringHashMap([*:0]const u8).init(a);
    for (verified.const_decls) |decl| {
        switch (decl.value) {
            .vtable => |literal| {
                const funcs = try a.alloc([*:0]const u8, literal.slots.len);
                for (literal.slots, 0..) |slot, slot_idx| {
                    const sig_idx = function_sig_index.get(slot.func_name) orelse return error.UnknownFunction;
                    const fname = try a.dupeSentinel(u8, emittedFunctionName(verified.function_sigs[sig_idx]), 0);
                    funcs[slot_idx] = fname.ptr;
                }
                const name = try a.dupeSentinel(u8, decl.name, 0);
                try c_vtables.append(.{ .name = name.ptr, .funcs = funcs.ptr, .func_count = funcs.len });
            },
            else => {
                const len = try constBytesLen(decl.value);
                const bytes = try a.alloc(u8, len);
                try fillConstBytes(bytes, decl.value);
                const name = try a.dupeSentinel(u8, decl.name, 0);
                try c_consts.append(.{ .name = name.ptr, .data = bytes.ptr, .len = bytes.len });
            },
        }
    }
    try collectAnonStringConsts(a, &verified.symbols, verified.annotated, &anon_string_names, &c_consts);

    var referenced_functions = std.StringHashMap(void).init(a);
    const focused_test_prune = options.test_mode and options.selected_test_names.len != 0 and options.codegen_unit_index == null and options.function_task_index == null;
    var prune_unreachable = options.dce != .no and (!options.test_mode or focused_test_prune) and options.codegen_unit_index == null and options.function_task_index == null;
    if (focused_test_prune) {
        try collectSelectedTestReachability(a, verified, &function_sig_index, options.selected_test_names, &referenced_functions);
        prune_unreachable = referenced_functions.count() != 0;
    } else if (prune_unreachable) {
        try collectDceReachability(a, verified, &function_sig_index, source_path, options, &referenced_functions);
        prune_unreachable = referenced_functions.count() != 0;
    } else if (options.codegen_unit_index) |cgu_idx| {
        // Collect functions referenced in Trait vtables
        for (verified.const_decls) |decl| {
            switch (decl.value) {
                .vtable => |literal| {
                    for (literal.slots) |slot| {
                        _ = try markReachableFunctionByName(&referenced_functions, verified.function_sigs, &function_sig_index, slot.func_name);
                    }
                },
                else => {},
            }
        }

        // Collect functions called by functions in this CGU
        var sig_index: usize = 0;
        var idx: usize = 0;
        var task_idx: usize = 0;
        while (idx < verified.annotated.len) : (idx += 1) {
            const item = verified.annotated[idx].base;
            switch (item.kind) {
                .func_decl, .ffi_wrapper_decl, .extern_decl, .export_decl, .test_decl, .gpu_decl => {
                    if (sig_index >= verified.function_sigs.len) return error.UnknownFunction;
                    sig_index += 1;
                    var end = idx + 1;
                    while (end < verified.annotated.len and switch (verified.annotated[end].base.kind) {
                        .func_decl, .ffi_wrapper_decl, .extern_decl, .export_decl, .test_decl, .gpu_decl => false,
                        else => true,
                    }) : (end += 1) {}

                    if (task_idx % options.codegen_unit_count == cgu_idx) {
                        _ = try collectBodyDirectCallees(a, verified, &function_sig_index, idx + 1, end, &referenced_functions);
                    }
                    task_idx += 1;
                    idx = end - 1;
                },
                else => {},
            }
        }
    } else if (options.function_task_index) |wanted_task_idx| {
        var sig_index: usize = 0;
        var idx: usize = 0;
        var task_idx: usize = 0;
        while (idx < verified.annotated.len) : (idx += 1) {
            const item = verified.annotated[idx].base;
            switch (item.kind) {
                .func_decl, .ffi_wrapper_decl, .extern_decl, .export_decl, .test_decl, .gpu_decl => {
                    if (sig_index >= verified.function_sigs.len) return error.UnknownFunction;
                    sig_index += 1;
                    var end = idx + 1;
                    while (end < verified.annotated.len and switch (verified.annotated[end].base.kind) {
                        .func_decl, .ffi_wrapper_decl, .extern_decl, .export_decl, .test_decl, .gpu_decl => false,
                        else => true,
                    }) : (end += 1) {}

                    if (task_idx == wanted_task_idx) {
                        _ = try collectBodyDirectCallees(a, verified, &function_sig_index, idx + 1, end, &referenced_functions);
                    }
                    task_idx += 1;
                    idx = end - 1;
                },
                else => {},
            }
        }
    }

    var tasks = std.array_list.Managed(ParallelEmitTask).init(a);
    var sig_index: usize = 0;
    var idx: usize = 0;
    var task_idx: usize = 0;
    while (idx < verified.annotated.len) : (idx += 1) {
        const item = verified.annotated[idx].base;
        switch (item.kind) {
            .func_decl, .ffi_wrapper_decl, .extern_decl, .export_decl, .test_decl, .gpu_decl => {
                if (sig_index >= verified.function_sigs.len) return error.UnknownFunction;
                const fsig = verified.function_sigs[sig_index];
                sig_index += 1;
                var end = idx + 1;
                while (end < verified.annotated.len and switch (verified.annotated[end].base.kind) {
                    .func_decl, .ffi_wrapper_decl, .extern_decl, .export_decl, .test_decl, .gpu_decl => false,
                    else => true,
                }) : (end += 1) {}

                var c_kind: CFuncKind = switch (item.kind) {
                    .extern_decl => .external,
                    .export_decl => .exported,
                    .ffi_wrapper_decl => .exported,
                    .test_decl => .test_func,
                    else => .normal,
                };
                var emit_wrapper = !options.test_mode and fsig.kind == .normal and std.mem.eql(u8, fsig.name, "main") and fsig.params.len == 0;

                var should_include = true;
                if (options.function_task_index) |wanted_task_idx| {
                    if (task_idx == wanted_task_idx) {
                        // This task is emitted as a cached incremental object.
                    } else if (item.kind == .extern_decl or referenced_functions.contains(fsig.name)) {
                        c_kind = .external;
                        emit_wrapper = false;
                    } else {
                        should_include = false;
                    }
                } else if (options.codegen_unit_index) |cgu_idx| {
                    if (task_idx % options.codegen_unit_count == cgu_idx) {
                        // Belongs to this CGU, define it!
                    } else if (item.kind == .extern_decl or referenced_functions.contains(fsig.name)) {
                        // External declaration needed by this CGU
                        c_kind = .external;
                        emit_wrapper = false;
                    } else {
                        // Not needed at all, completely skip!
                        should_include = false;
                    }
                } else if (prune_unreachable and !referenced_functions.contains(fsig.name)) {
                    if (focused_test_prune or shouldPruneUnreachableFunction(options, fsig, source_path)) should_include = false;
                }

                if (should_include) {
                    try tasks.append(.{
                        .fsig = fsig,
                        .sig_idx = sig_index - 1,
                        .kind = c_kind,
                        .emit_main_wrapper = emit_wrapper,
                        .start_idx = idx,
                        .end_idx = end,
                        .decl_kind = if (c_kind == .external) .extern_decl else item.kind,
                    });
                }
                task_idx += 1;
                idx = end - 1;
            },
            else => {},
        }
    }

    var shared_tables = try buildSharedEmitTables(a, verified, tasks.items, &function_sig_index);
    const worker_count = chooseEmitWorkerCount(options.jobs, tasks.items.len);
    const jobs = try a.alloc(ParallelEmitJob, tasks.items.len);
    const job_backing_allocator = emitJobBackingAllocator(allocator, worker_count);
    for (jobs) |*job| {
        job.* = .{ .arena = std.heap.ArenaAllocator.init(job_backing_allocator) };
    }
    defer {
        for (jobs) |*job| job.arena.deinit();
    }

    const VerifiedType = @TypeOf(verified);
    var context = ParallelEmitContext(VerifiedType){
        .allocator = allocator,
        .verified = verified,
        .loc_table = loc_table,
        .source_path = source_path,
        .options = options,
        .anon_string_names = &anon_string_names,
        .function_sig_index = &function_sig_index,
        .shared_tables = &shared_tables,
        .tasks = tasks.items,
        .jobs = jobs,
        .next_task = std.atomic.Value(usize).init(0),
    };

    if (worker_count <= 1) {
        emitWorker(VerifiedType, &context);
    } else {
        const spawned_count = worker_count - 1;
        var threads = try a.alloc(std.Thread, spawned_count);
        var started_threads: usize = 0;
        errdefer {
            while (started_threads > 0) {
                started_threads -= 1;
                threads[started_threads].join();
            }
        }

        while (started_threads < spawned_count) : (started_threads += 1) {
            threads[started_threads] = try std.Thread.spawn(.{}, emitWorker, .{ VerifiedType, &context });
        }

        emitWorker(VerifiedType, &context);

        while (started_threads > 0) {
            started_threads -= 1;
            threads[started_threads].join();
        }
    }

    var c_funcs = std.array_list.Managed(CFunction).init(a);
    for (jobs) |job| {
        if (job.err) |err| return err;
        try c_funcs.append(job.result orelse return error.Failed);
    }

    const target_triple_z: ?[*:0]const u8 = if (options.target_triple) |t| (try a.dupeSentinel(u8, t, 0)).ptr else null;
    defer if (target_triple_z) |z| a.free(std.mem.span(z));

    const module = CModule{
        .size_bits = size_bits,
        .wasm_compat = options.wasm_compat,
        .test_mode = options.test_mode,
        .debug = options.debug,
        .is_cgu = options.codegen_unit_count > 1,
        .fast_math = options.fast_math,
        .source_file = if (options.debug) module_source_file.ptr else null,
        .source_dir = if (options.debug) module_source_dir.ptr else null,
        .consts = c_consts.items.ptr,
        .const_count = c_consts.items.len,
        .vtables = c_vtables.items.ptr,
        .vtable_count = c_vtables.items.len,
        .functions = c_funcs.items.ptr,
        .function_count = c_funcs.items.len,
        .target_triple = target_triple_z,
    };

    if (obj_path) |path| {
        const path_z = try a.dupeSentinel(u8, path, 0);
        var err_msg: ?[*:0]u8 = null;
        if (sa_llvmc_emit_module_object(&module, path_z.ptr, @intCast(opt_level), &err_msg) != 0) {
            if (err_msg) |msg| {
                recordLlvmcError("llvmc object emit", msg);
                sa_llvmc_free(msg);
            }
            return error.Failed;
        }
        return &[_]u8{};
    } else {
        var out_bytes: ?[*]u8 = null;
        var out_len: usize = 0;
        var err_msg: ?[*:0]u8 = null;
        if (sa_llvmc_emit_module_bitcode(&module, @intCast(options.opt_level), &out_bytes, &out_len, &err_msg) != 0) {
            if (err_msg) |msg| {
                recordLlvmcError("llvmc backend", msg);
                sa_llvmc_free(msg);
            }
            return error.Failed;
        }
        errdefer if (out_bytes) |ptr| sa_llvmc_free(ptr);
        return try takeOwnedBitcode(allocator, &out_bytes, &out_len);
    }
}

pub fn emitLlvmc(allocator: std.mem.Allocator, verified: anytype, def_dict: ?*const flattener.DefDict, loc_table: upstream.LocTable, source_path: []const u8, size_bits: u16, options: EmitOptions) ![]const u8 {
    return emitLlvmcInternal(allocator, verified, def_dict, loc_table, source_path, size_bits, options, null, 0);
}

pub fn emitLlvmcToObject(allocator: std.mem.Allocator, verified: anytype, def_dict: ?*const flattener.DefDict, loc_table: upstream.LocTable, source_path: []const u8, size_bits: u16, options: EmitOptions, obj_path: []const u8, opt_level: u8) !void {
    _ = try emitLlvmcInternal(allocator, verified, def_dict, loc_table, source_path, size_bits, options, obj_path, opt_level);
}

pub fn emitLlvmcToArtifacts(allocator: std.mem.Allocator, verified: anytype, def_dict: ?*const flattener.DefDict, loc_table: upstream.LocTable, source_path: []const u8, size_bits: u16, options: EmitOptions, bitcode_path: []const u8, object_path: []const u8, opt_level: u8) !void {
    _ = def_dict;
    if (options.debug and loc_table.len != verified.annotated.len) return error.InvalidOperand;
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const module_source_file = try a.dupeSentinel(u8, sourceFileName(source_path), 0);
    const module_source_dir = try a.dupeSentinel(u8, sourceDirName(source_path), 0);
    var function_sig_index = try buildFunctionSigIndex(a, verified.function_sigs);

    var c_consts = std.array_list.Managed(CConst).init(a);
    var c_vtables = std.array_list.Managed(CVTable).init(a);
    var anon_string_names = std.StringHashMap([*:0]const u8).init(a);
    for (verified.const_decls) |decl| {
        switch (decl.value) {
            .vtable => |literal| {
                const funcs = try a.alloc([*:0]const u8, literal.slots.len);
                for (literal.slots, 0..) |slot, slot_idx| {
                    const sig_idx = function_sig_index.get(slot.func_name) orelse return error.UnknownFunction;
                    const fname = try a.dupeSentinel(u8, emittedFunctionName(verified.function_sigs[sig_idx]), 0);
                    funcs[slot_idx] = fname.ptr;
                }
                const name = try a.dupeSentinel(u8, decl.name, 0);
                try c_vtables.append(.{ .name = name.ptr, .funcs = funcs.ptr, .func_count = funcs.len });
            },
            else => {
                const len = try constBytesLen(decl.value);
                const bytes = try a.alloc(u8, len);
                try fillConstBytes(bytes, decl.value);
                const name = try a.dupeSentinel(u8, decl.name, 0);
                try c_consts.append(.{ .name = name.ptr, .data = bytes.ptr, .len = bytes.len });
            },
        }
    }
    try collectAnonStringConsts(a, &verified.symbols, verified.annotated, &anon_string_names, &c_consts);

    var referenced_functions = std.StringHashMap(void).init(a);
    const focused_test_prune = options.test_mode and options.selected_test_names.len != 0 and options.codegen_unit_index == null and options.function_task_index == null;
    var prune_unreachable = options.dce != .no and (!options.test_mode or focused_test_prune) and options.codegen_unit_index == null and options.function_task_index == null;
    if (focused_test_prune) {
        try collectSelectedTestReachability(a, verified, &function_sig_index, options.selected_test_names, &referenced_functions);
        prune_unreachable = referenced_functions.count() != 0;
    } else if (prune_unreachable) {
        try collectDceReachability(a, verified, &function_sig_index, source_path, options, &referenced_functions);
        prune_unreachable = referenced_functions.count() != 0;
    } else if (options.codegen_unit_index) |cgu_idx| {
        for (verified.const_decls) |decl| {
            switch (decl.value) {
                .vtable => |literal| {
                    for (literal.slots) |slot| {
                        _ = try markReachableFunctionByName(&referenced_functions, verified.function_sigs, &function_sig_index, slot.func_name);
                    }
                },
                else => {},
            }
        }

        var sig_index: usize = 0;
        var idx: usize = 0;
        var task_idx: usize = 0;
        while (idx < verified.annotated.len) : (idx += 1) {
            const item = verified.annotated[idx].base;
            switch (item.kind) {
                .func_decl, .ffi_wrapper_decl, .extern_decl, .export_decl, .test_decl, .gpu_decl => {
                    if (sig_index >= verified.function_sigs.len) return error.UnknownFunction;
                    sig_index += 1;
                    var end = idx + 1;
                    while (end < verified.annotated.len and switch (verified.annotated[end].base.kind) {
                        .func_decl, .ffi_wrapper_decl, .extern_decl, .export_decl, .test_decl, .gpu_decl => false,
                        else => true,
                    }) : (end += 1) {}

                    if (task_idx % options.codegen_unit_count == cgu_idx) {
                        _ = try collectBodyDirectCallees(a, verified, &function_sig_index, idx + 1, end, &referenced_functions);
                    }
                    task_idx += 1;
                    idx = end - 1;
                },
                else => {},
            }
        }
    } else if (options.function_task_index) |wanted_task_idx| {
        var sig_index: usize = 0;
        var idx: usize = 0;
        var task_idx: usize = 0;
        while (idx < verified.annotated.len) : (idx += 1) {
            const item = verified.annotated[idx].base;
            switch (item.kind) {
                .func_decl, .ffi_wrapper_decl, .extern_decl, .export_decl, .test_decl, .gpu_decl => {
                    if (sig_index >= verified.function_sigs.len) return error.UnknownFunction;
                    sig_index += 1;
                    var end = idx + 1;
                    while (end < verified.annotated.len and switch (verified.annotated[end].base.kind) {
                        .func_decl, .ffi_wrapper_decl, .extern_decl, .export_decl, .test_decl, .gpu_decl => false,
                        else => true,
                    }) : (end += 1) {}

                    if (task_idx == wanted_task_idx) {
                        _ = try collectBodyDirectCallees(a, verified, &function_sig_index, idx + 1, end, &referenced_functions);
                    }
                    task_idx += 1;
                    idx = end - 1;
                },
                else => {},
            }
        }
    }

    var tasks = std.array_list.Managed(ParallelEmitTask).init(a);
    var sig_index: usize = 0;
    var idx: usize = 0;
    var task_idx: usize = 0;
    while (idx < verified.annotated.len) : (idx += 1) {
        const item = verified.annotated[idx].base;
        switch (item.kind) {
            .func_decl, .ffi_wrapper_decl, .extern_decl, .export_decl, .test_decl, .gpu_decl => {
                if (sig_index >= verified.function_sigs.len) return error.UnknownFunction;
                const fsig = verified.function_sigs[sig_index];
                sig_index += 1;
                var end = idx + 1;
                while (end < verified.annotated.len and switch (verified.annotated[end].base.kind) {
                    .func_decl, .ffi_wrapper_decl, .extern_decl, .export_decl, .test_decl, .gpu_decl => false,
                    else => true,
                }) : (end += 1) {}

                var c_kind: CFuncKind = switch (item.kind) {
                    .extern_decl => .external,
                    .export_decl => .exported,
                    .ffi_wrapper_decl => .exported,
                    .test_decl => .test_func,
                    else => .normal,
                };
                var emit_wrapper = !options.test_mode and fsig.kind == .normal and std.mem.eql(u8, fsig.name, "main") and fsig.params.len == 0;

                var should_include = true;
                if (options.function_task_index) |wanted_task_idx| {
                    if (task_idx == wanted_task_idx) {} else if (item.kind == .extern_decl or referenced_functions.contains(fsig.name)) {
                        c_kind = .external;
                        emit_wrapper = false;
                    } else {
                        should_include = false;
                    }
                } else if (options.codegen_unit_index) |cgu_idx| {
                    if (task_idx % options.codegen_unit_count == cgu_idx) {} else if (item.kind == .extern_decl or referenced_functions.contains(fsig.name)) {
                        c_kind = .external;
                        emit_wrapper = false;
                    } else {
                        should_include = false;
                    }
                } else if (prune_unreachable and !referenced_functions.contains(fsig.name)) {
                    if (focused_test_prune or shouldPruneUnreachableFunction(options, fsig, source_path)) should_include = false;
                }

                if (should_include) {
                    try tasks.append(.{
                        .fsig = fsig,
                        .sig_idx = sig_index - 1,
                        .kind = c_kind,
                        .emit_main_wrapper = emit_wrapper,
                        .start_idx = idx,
                        .end_idx = end,
                        .decl_kind = if (c_kind == .external) .extern_decl else item.kind,
                    });
                }
                task_idx += 1;
                idx = end - 1;
            },
            else => {},
        }
    }

    var shared_tables = try buildSharedEmitTables(a, verified, tasks.items, &function_sig_index);
    const worker_count = chooseEmitWorkerCount(options.jobs, tasks.items.len);
    const jobs = try a.alloc(ParallelEmitJob, tasks.items.len);
    const job_backing_allocator = emitJobBackingAllocator(allocator, worker_count);
    for (jobs) |*job| job.* = .{ .arena = std.heap.ArenaAllocator.init(job_backing_allocator) };
    defer for (jobs) |*job| job.arena.deinit();

    const VerifiedType = @TypeOf(verified);
    var context = ParallelEmitContext(VerifiedType){
        .allocator = allocator,
        .verified = verified,
        .loc_table = loc_table,
        .source_path = source_path,
        .options = options,
        .anon_string_names = &anon_string_names,
        .function_sig_index = &function_sig_index,
        .shared_tables = &shared_tables,
        .tasks = tasks.items,
        .jobs = jobs,
        .next_task = std.atomic.Value(usize).init(0),
    };

    if (worker_count <= 1) {
        emitWorker(VerifiedType, &context);
    } else {
        const spawned_count = worker_count - 1;
        var threads = try a.alloc(std.Thread, spawned_count);
        var started_threads: usize = 0;
        errdefer {
            while (started_threads > 0) {
                started_threads -= 1;
                threads[started_threads].join();
            }
        }

        while (started_threads < spawned_count) : (started_threads += 1) {
            threads[started_threads] = try std.Thread.spawn(.{}, emitWorker, .{ VerifiedType, &context });
        }

        emitWorker(VerifiedType, &context);

        while (started_threads > 0) {
            started_threads -= 1;
            threads[started_threads].join();
        }
    }

    var c_funcs = std.array_list.Managed(CFunction).init(a);
    for (jobs) |job| {
        if (job.err) |err| return err;
        try c_funcs.append(job.result orelse return error.Failed);
    }

    const target_triple_z: ?[*:0]const u8 = if (options.target_triple) |t| (try a.dupeSentinel(u8, t, 0)).ptr else null;
    defer if (target_triple_z) |z| a.free(std.mem.span(z));

    const module = CModule{
        .size_bits = size_bits,
        .wasm_compat = options.wasm_compat,
        .test_mode = options.test_mode,
        .debug = options.debug,
        .is_cgu = options.codegen_unit_count > 1,
        .fast_math = options.fast_math,
        .source_file = if (options.debug) module_source_file.ptr else null,
        .source_dir = if (options.debug) module_source_dir.ptr else null,
        .consts = c_consts.items.ptr,
        .const_count = c_consts.items.len,
        .vtables = c_vtables.items.ptr,
        .vtable_count = c_vtables.items.len,
        .functions = c_funcs.items.ptr,
        .function_count = c_funcs.items.len,
        .target_triple = target_triple_z,
    };

    const bc_z = try a.dupeSentinel(u8, bitcode_path, 0);
    const obj_z = try a.dupeSentinel(u8, object_path, 0);
    var err_msg: ?[*:0]u8 = null;
    if (sa_llvmc_emit_module_artifacts(&module, bc_z.ptr, obj_z.ptr, @intCast(opt_level), &err_msg) != 0) {
        if (err_msg) |msg| {
            recordLlvmcError("llvmc artifact emit", msg);
            sa_llvmc_free(msg);
        }
        return error.Failed;
    }
}

pub fn emitLlvmcToFile(allocator: std.mem.Allocator, verified: anytype, def_dict: ?*const flattener.DefDict, loc_table: upstream.LocTable, source_path: []const u8, size_bits: u16, options: EmitOptions, path: []const u8) !void {
    const verified_bitcode = try emitLlvmc(allocator, verified, def_dict, loc_table, source_path, size_bits, options);
    defer allocator.free(verified_bitcode);
    var file = if (std.fs.path.isAbsolute(path)) try sio.createFileAbsolute(path, .{ .truncate = true }) else try sio.cwd().createFile(path, .{ .truncate = true });
    defer file.close();
    try file.writeAll(verified_bitcode);
}

test "function signature index preserves linear alias precedence" {
    const sigs = [_]sig.FunctionSig{
        .{ .id = 0, .name = "one", .params = &.{}, .kind = .normal, .return_cap = null, .return_ty = .void, .entry_inst_idx = 0, .is_ffi_wrapper = false, .llvm_name = "shared" },
        .{ .id = 1, .name = "shared", .params = &.{}, .kind = .normal, .return_cap = null, .return_ty = .void, .entry_inst_idx = 0, .is_ffi_wrapper = false },
        .{ .id = 2, .name = "main", .params = &.{}, .kind = .normal, .return_cap = null, .return_ty = .void, .entry_inst_idx = 0, .is_ffi_wrapper = false },
    };
    var index = try buildFunctionSigIndex(std.testing.allocator, sigs[0..]);
    defer index.deinit();

    try std.testing.expectEqual(@as(usize, 0), index.get("one").?);
    try std.testing.expectEqual(@as(usize, 0), index.get("shared").?);
    try std.testing.expectEqual(@as(usize, 2), index.get("main").?);
    try std.testing.expectEqual(@as(usize, 2), index.get("saasm_main").?);
}
