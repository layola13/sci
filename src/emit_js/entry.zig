const std = @import("std");
const call = @import("../referee/call.zig");
const FuncTask = @import("types.zig").FuncTask;
const inst = @import("../common/instruction.zig");
const sig = @import("../common/signature.zig");
const sio = @import("sio");
const types = @import("types.zig");
const jsFuncName = @import("ident.zig").jsFuncName;
const constBytesLen = @import("ident.zig").constBytesLen;
const fillConstBytes = @import("ident.zig").fillConstBytes;
const writeConstSlot = @import("ident.zig").writeConstSlot;
const JsEmitOptions = @import("types.zig").JsEmitOptions;
const JsEmitError = @import("types.zig").JsEmitError;
const RetBaseTable = @import("types.zig").RetBaseTable;
const provSolveBody = @import("prov.zig").provSolveBody;
const provAllReturnsProven = @import("prov.zig").provAllReturnsProven;
const npmStrOut = @import("npm.zig").npmStrOut;
const collectNpmImports = @import("npm.zig").collectNpmImports;
const npmImportFor = @import("npm.zig").npmImportFor;
const emitNpmWrapper = @import("npm.zig").emitNpmWrapper;
const isJsNetShim = @import("shim_names.zig").isJsNetShim;
const policy_runtime_js = @import("runtime_policy.zig").policy_runtime_js;
const jstask_runtime_js = @import("runtime_task.zig").jstask_runtime_js;
const jshandle_runtime_js = @import("runtime_handle.zig").jshandle_runtime_js;
const jsnet_runtime_js = @import("runtime_net_a.zig").jsnet_runtime_js_a ++ "\n" ++ @import("runtime_net_b.zig").jsnet_runtime_js_b;
const globals_runtime_js = @import("runtime_globals.zig").globals_runtime_js;
const emitOneFunction = @import("funcs.zig").emitOneFunction;
const emitBodyAsPcMachine = @import("funcs.zig").emitBodyAsPcMachine;

const NpmImport = @import("npm.zig").NpmImport;
const jsIdent = @import("ident.zig").jsIdent;
const isJsPolicyShim = @import("shim_names.zig").isJsPolicyShim;
const isJsTaskShim = @import("shim_names.zig").isJsTaskShim;
const isJsGlobalsShim = @import("shim_names.zig").isJsGlobalsShim;
const isJsHandleBuiltin = @import("shim_names.zig").isJsHandleBuiltin;
const taskUsesGlobalRegIds = @import("funcs.zig").taskUsesGlobalRegIds;
pub fn emitJsToString(allocator: std.mem.Allocator, verified: anytype, source_path: []const u8, size_bits: u16, js_opt: JsEmitOptions, npm_binds: *const std.StringHashMap([]const u8)) ![]u8 {
    // Error-context globals are per-build: they point into the current
    // build's verified module. Reset them at entry — a build that fails
    // before any function emission (e.g. in collectNpmImports) would
    // otherwise leave the cli error path printing a dangling slice
    // retained from a previous in-process build (observed as a
    // segfault in the js-matrix rejects test, which runs many builds
    // in one process).
    types.last_js_inst = "";
    types.last_js_func = "";
    // Extern variadic batch: no variadic extern mechanism on the JS
    // target; reject loudly.
    for (verified.function_sigs) |fs| {
        if (fs.is_variadic) return error.UnsupportedVariadic;
    }
    var out: std.Io.Writer.Allocating = .init(allocator);
    errdefer out.deinit();
    const writer = &out.writer;
    // Indirect-call function table: every vtable slot target, deduped in order.
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
    // `#npm_bind` imports must precede the runtime header: ESM import
    // declarations live in the module prologue.
    const tasks = try collectFuncTasks(allocator, verified);
    defer allocator.free(tasks);
    const npm_imports = try collectNpmImports(allocator, verified, tasks, npm_binds);
    defer {
        for (npm_imports) |item| allocator.free(item.alias);
        allocator.free(npm_imports);
    }
    try writeRuntimeHeader(writer, js_opt, size_bits, npm_imports);
    // Emit the net runtime chunk once when the program declares any BP
    // net shim (cookie/tls/net-slice/netinfo). Programs without net
    // externs pay nothing for it.
    for (tasks) |task| {
        if (task.kind != .extern_decl) continue;
        const fsig = verified.function_sigs[task.fsig_index];
        if (isJsNetShim(fsig.name)) {
            try writer.writeAll(jsnet_runtime_js);
            try writer.writeAll("\n");
            break;
        }
    }
    // Emit the policy runtime chunk once when the program declares any
    // shim whose body consults it (time/random/deno-fs). It used to be
    // appended to every program's runtime header unconditionally.
    for (tasks) |task| {
        if (task.kind != .extern_decl) continue;
        const fsig = verified.function_sigs[task.fsig_index];
        if (isJsPolicyShim(fsig.name)) {
            try writer.writeAll(policy_runtime_js);
            try writer.writeAll("\n");
            break;
        }
    }
    // Emit the goroutine runtime chunk once when the program declares
    // any task/chan/sync/coop shim (sa_std/task.sai surface).
    for (tasks) |task| {
        if (task.kind != .extern_decl) continue;
        const fsig = verified.function_sigs[task.fsig_index];
        if (isJsTaskShim(fsig.name)) {
            try writer.writeAll(jstask_runtime_js);
            try writer.writeAll("\n");
            break;
        }
    }
    // Emit the global-cells runtime chunk once when the program
    // declares any sa_global_* shim (sa_std/globals.sai surface).
    for (tasks) |task| {
        if (task.kind != .extern_decl) continue;
        const fsig = verified.function_sigs[task.fsig_index];
        if (isJsGlobalsShim(fsig.name)) {
            try writer.writeAll(globals_runtime_js);
            try writer.writeAll("\n");
            break;
        }
    }
    // Emit the value-handle runtime chunk once when the program uses a
    // handle binding shape (ctor/method/get), a bytes-view modifier, a
    // string-out npm binding, or a handle runtime builtin.
    var need_handle_runtime = false;
    for (tasks) |task| {
        if (task.kind != .extern_decl) continue;
        const fsig = verified.function_sigs[task.fsig_index];
        if (isJsHandleBuiltin(fsig.name)) {
            need_handle_runtime = true;
            break;
        }
    }
    if (!need_handle_runtime) {
        outer: for (npm_imports) |item| {
            if (item.shape != .call or item.bytes_view != .none) {
                need_handle_runtime = true;
                break;
            }
            for (tasks) |task| {
                if (task.kind != .extern_decl) continue;
                const fsig = verified.function_sigs[task.fsig_index];
                if (std.mem.eql(u8, fsig.name, item.extern_name) and npmStrOut(fsig, item.shape)) {
                    need_handle_runtime = true;
                    break :outer;
                }
            }
        }
    }
    if (need_handle_runtime) {
        try writer.writeAll(jshandle_runtime_js);
        try writer.writeAll("\n");
    }

    try writer.print("// source: {s}\n", .{source_path});
    // Function table for call_indirect (boxed addresses, see vtable consts).
    try writer.writeAll("const __sa_ftable = [");
    for (fn_names.items, 0..) |fname, idx| {
        if (idx != 0) try writer.writeAll(", ");
        try jsFuncName(writer, fname);
    }
    try writer.writeAll("];\n");
    // Static consts: fixed linear-memory addresses below the bump region.
    var const_addrs = std.StringHashMap(usize).init(allocator);
    defer const_addrs.deinit();
    var const_cursor: usize = 4096;
    const bump_start: usize = 65536;
    for (verified.const_decls) |decl| {
        const len = constBytesLen(decl.value) catch 0;
        const aligned = std.mem.alignForward(usize, const_cursor, 8);
        if (decl.value == .vtable or len == 0) {
            // VTable slots hold boxed function addresses (u64 LE of
            // FN_BASE + table index) so call_indirect resolves at runtime.
            // Non-vtable empty consts reserve 8 zeroed bytes.
            const is_vt = decl.value == .vtable;
            const slots: usize = if (is_vt) decl.value.vtable.slots.len * 8 else 8;
            const a2 = std.mem.alignForward(usize, const_cursor, 8);
            if (a2 + slots > bump_start) return JsEmitError.Failed;
            try const_addrs.put(decl.name, a2);
            try writer.writeAll("const ");
            try writeConstSlot(writer, decl.name);
            try writer.print(" = {d}; // {s} ({d} bytes)\n", .{ a2, @tagName(decl.value), slots });
            if (is_vt) {
                var sidx: usize = 0;
                for (decl.value.vtable.slots) |vslot| {
                    const fidx = fn_idx.get(vslot.func_name) orelse return JsEmitError.UnknownFunction;
                    var le: [8]u8 = undefined;
                    std.mem.writeInt(u64, &le, 0x5341000000000000 + @as(u64, @intCast(fidx)), .little);
                    try writer.print("__sa_u8.set([", .{});
                    for (le, 0..) |b, bidx| {
                        if (bidx != 0) try writer.writeAll(",");
                        try writer.print("{d}", .{b});
                    }
                    try writer.print("], {d});\n", .{a2 + sidx * 8});
                    sidx += 1;
                }
            } else {
                try writer.print("__sa_u8.fill(0, {d}, {d});\n", .{ a2, a2 + slots });
            }
            const_cursor = a2 + slots;
            continue;
        }
        if (aligned + len > bump_start) return JsEmitError.Failed;
        try const_addrs.put(decl.name, aligned);
        const bytes = try allocator.alloc(u8, len);
        defer allocator.free(bytes);
        try fillConstBytes(bytes, decl.value);
        try writer.writeAll("const ");
        try writeConstSlot(writer, decl.name);
        try writer.print(" = {d}; // {s} ({d} bytes)\n", .{ aligned, @tagName(decl.value), len });
        try writer.print("__sa_u8.set([", .{});
        for (bytes, 0..) |b, idx| {
            if (idx != 0) try writer.writeAll(",");
            try writer.print("{d}", .{b});
        }
        try writer.print("], {d});\n", .{aligned});
        const_cursor = aligned + len;
    }
    // Non-extern function names: a same-module `@export` satisfies an
    // `@extern` declaration, so no trap stub is emitted for those (the
    // stub used to clobber the real body).
    var emitted = std.StringHashMap(void).init(allocator);
    defer emitted.deinit();
    // Must-return-base summary (increasing fixpoint from empty, hence sound
    // for recursion): alloc-class callees return fresh bases; param(i)-class
    // callees pass through one transparent (by_value/move) parameter.
    var retbase = RetBaseTable.init(allocator);
    defer retbase.deinit();
    {
        var iter: usize = 0;
        var stable = false;
        while (!stable and iter < 100) : (iter += 1) {
            stable = true;
            for (tasks) |task| {
                if (task.kind == .extern_decl) continue;
                const fsig = verified.function_sigs[task.fsig_index];
                if (retbase.contains(fsig.name)) continue;
                const ug = taskUsesGlobalRegIds(fsig, verified, task);
                var classified = false;
                {
                    var prov = try provSolveBody(allocator, verified, fsig, ug, task, &retbase, null);
                    defer prov.deinit();
                    if (try provAllReturnsProven(allocator, verified, fsig, ug, &prov, &retbase)) {
                        try retbase.put(fsig.name, .{ .alloc = {} });
                        classified = true;
                    }
                }
                if (!classified) {
                    for (fsig.param_ids, 0..) |pid, pi| {
                        const pseed = fsig.slotOf(pid) orelse continue;
                        var prov = try provSolveBody(allocator, verified, fsig, ug, task, &retbase, pseed);
                        defer prov.deinit();
                        if (try provAllReturnsProven(allocator, verified, fsig, ug, &prov, &retbase)) {
                            try retbase.put(fsig.name, .{ .param = pi });
                            classified = true;
                            break;
                        }
                    }
                }
                if (classified) stable = false;
            }
        }
    }
    var has_main = false;
    for (tasks) |task| {
        if (task.kind == .extern_decl) continue;
        try emitOneFunction(writer, allocator, verified, task, &const_addrs, &fn_idx, js_opt, &retbase);
        const fsig = verified.function_sigs[task.fsig_index];
        try emitted.put(fsig.name, {});
        if (std.mem.eql(u8, fsig.name, "main")) has_main = true;
    }
    var stub_emitted = std.StringHashMap(void).init(allocator);
    defer stub_emitted.deinit();
    // Extern-stub DCE (see collectReferencedJsNames): under
    // .std/.full an unbound extern that no emitted code references is
    // not emitted at all. Referenced unbound externs keep their trap
    // stub verbatim; bound externs (npm wrappers above, emitter shim
    // bodies below) are unaffected. Under .no every stub is emitted
    // (pre-DCE behavior) and the census is skipped entirely.
    var referenced_js_names: std.StringHashMap(void) = if (js_opt.dce != .no)
        try collectReferencedJsNames(allocator, verified, tasks, fn_names.items)
    else
        std.StringHashMap(void).init(allocator);
    defer {
        var kit = referenced_js_names.keyIterator();
        while (kit.next()) |k| allocator.free(k.*);
        referenced_js_names.deinit();
    }
    // extern stubs (so calls don't ReferenceError; they trap with name).
    // `#npm_bind` externs get a marshaling wrapper instead, unless a
    // same-module `@export` already satisfies the declaration.
    for (tasks) |task| {
        if (task.kind != .extern_decl) continue;
        const fsig = verified.function_sigs[task.fsig_index];
        if (npmImportFor(npm_imports, fsig.name)) |npm_item| {
            if (emitted.contains(fsig.name)) continue;
            types.last_js_func = fsig.name;
            try emitNpmWrapper(writer, fsig, npm_item, js_opt);
            try emitted.put(fsig.name, {});
            continue;
        }
        if (emitted.contains(fsig.name) or stub_emitted.contains(fsig.name)) continue;
        try stub_emitted.put(fsig.name, {});
        if (js_opt.dce == .no) {
            // --dce no: emit the stub (or emitter shim body) directly,
            // byte-identical to the pre-DCE emitter.
            try emitOneFunction(writer, allocator, verified, task, &const_addrs, &fn_idx, js_opt, &retbase);
            continue;
        }
        // Emit into a scratch buffer first: if the product is the trap
        // stub of an unreferenced extern, drop it (dce=full); anything
        // else (a referenced trap stub, or an emitter shim body) is
        // written through byte-identical to the pre-DCE output.
        var scratch: std.Io.Writer.Allocating = .init(allocator);
        defer scratch.deinit();
        try emitOneFunction(&scratch.writer, allocator, verified, task, &const_addrs, &fn_idx, js_opt, &retbase);
        const text = try scratch.toOwnedSlice();
        defer allocator.free(text);
        if (std.mem.indexOf(u8, text, "__sa_trap(\"extern not linked: ") != null) {
            const key = try jsNameKey(allocator, fsig.name);
            defer allocator.free(key);
            if (!referenced_js_names.contains(key)) continue;
        }
        try writer.writeAll(text);
    }
    // exports + main runner
    if (js_opt.format == .cjs) {
        try writer.writeAll("\nmodule.exports = { __sa_memory, __sa_view, __sa_u8, __sa_alloc, __sa_free, __sa_salloc, __sa_sfree, __sa_mem_used");
        for (tasks) |task| {
            if (task.kind == .extern_decl) continue;
            const fsig = verified.function_sigs[task.fsig_index];
            try writer.writeAll(", ");
            try jsFuncName(writer, fsig.name);
        }
        try writer.writeAll(" };\n");
        if (has_main) try writer.writeAll("if (require.main === module) { main(); }\n");
    } else {
        try writer.writeAll("\nexport { __sa_memory, __sa_view, __sa_u8, __sa_alloc, __sa_free, __sa_salloc, __sa_sfree, __sa_mem_used };\n");
        if (has_main) try writer.writeAll("if (typeof globalThis.process !== \"undefined\" && globalThis.process.argv && globalThis.process.argv[1] && /\\.(mjs|js|cjs)$/.test(globalThis.process.argv[1])) { try { main(); } catch (e) { globalThis.console.error(e); globalThis.process.exit(1); } }\n");
    }
    return out.toOwnedSlice();
}

pub fn emitJsToFile(allocator: std.mem.Allocator, verified: anytype, source_path: []const u8, size_bits: u16, js_opt: JsEmitOptions, npm_binds: *const std.StringHashMap([]const u8), path: []const u8) !void {
    const text = try emitJsToString(allocator, verified, source_path, size_bits, js_opt, npm_binds);
    defer allocator.free(text);
    // patch mem-bytes placeholder
    const mem_bytes: usize = @as(usize, js_opt.mem_pages) * 65536;
    var final = try allocator.dupe(u8, text);
    defer allocator.free(final);
    const needle = "__SA_MEM_BYTES_DECL__";
    if (std.mem.indexOf(u8, final, needle)) |pos| {
        var patched = std.array_list.Managed(u8).init(allocator);
        errdefer patched.deinit();
        try patched.appendSlice(final[0..pos]);
        try patched.print("{d}", .{mem_bytes});
        try patched.appendSlice(final[pos + needle.len ..]);
        const owned = try patched.toOwnedSlice();
        defer allocator.free(owned);
        const dir = std.fs.path.dirname(path);
        if (dir) |d| try sio.cwd().makePath(d);
        const f = try sio.cwd().createFile(path, .{});
        defer f.close();
        try f.writeAll(owned);
        if (js_opt.emit_dts) try emitDtsToFile(allocator, verified, source_path, js_opt, npm_binds, path);
        return;
    }
    const dir = std.fs.path.dirname(path);
    if (dir) |d| try sio.cwd().makePath(d);
    const f = try sio.cwd().createFile(path, .{});
    defer f.close();
    try f.writeAll(final);
    if (js_opt.emit_dts) try emitDtsToFile(allocator, verified, source_path, js_opt, npm_binds, path);
}

pub fn emitDtsToString(allocator: std.mem.Allocator, verified: anytype, source_path: []const u8, js_opt: JsEmitOptions, npm_binds: *const std.StringHashMap([]const u8)) ![]u8 {
    const tasks = try collectFuncTasks(allocator, verified);
    defer allocator.free(tasks);
    const npm_imports = try collectNpmImports(allocator, verified, tasks, npm_binds);
    defer {
        for (npm_imports) |item| allocator.free(item.alias);
        allocator.free(npm_imports);
    }
    var aliases = DtsAliases{};
    // Declarations follow task order; a later declaration whose
    // sanitized JS name collides with an earlier one replaces it
    // (mirrors JS function-declaration hoisting in the product).
    var order = std.array_list.Managed([]u8).init(allocator);
    defer {
        for (order.items) |n| allocator.free(n);
        order.deinit();
    }
    var decls = std.StringHashMap([]u8).init(allocator);
    defer {
        var vit = decls.valueIterator();
        while (vit.next()) |v| allocator.free(v.*);
        decls.deinit();
    }
    for (tasks) |task| {
        const fsig = verified.function_sigs[task.fsig_index];
        const is_wrapper = task.kind == .extern_decl;
        if (is_wrapper) {
            // Only #npm_bind externs get a product-visible wrapper;
            // host shims and trap stubs stay module-internal. The CJS
            // product does not export wrappers at all (SURFACE.md section 1).
            if (js_opt.format == .cjs) continue;
            if (npmImportFor(npm_imports, fsig.name) == null) continue;
        }
        const name = try dtsNameAlloc(allocator, fsig.name);
        errdefer allocator.free(name);
        var decl: std.Io.Writer.Allocating = .init(allocator);
        errdefer decl.deinit();
        try writeDtsDecl(&decl.writer, fsig, is_wrapper, &aliases);
        const text = try decl.toOwnedSlice();
        const gop = try decls.getOrPut(name);
        if (gop.found_existing) {
            allocator.free(gop.value_ptr.*);
            gop.value_ptr.* = text;
            allocator.free(name);
        } else {
            gop.value_ptr.* = text;
            try order.append(name);
        }
    }
    var body: std.Io.Writer.Allocating = .init(allocator);
    errdefer body.deinit();
    for (order.items) |name| try body.writer.writeAll(decls.get(name).?);
    // Runtime helpers, in the JS product's trailing export-list order.
    aliases.sa_ptr = true;
    try body.writer.writeAll("export declare const __sa_memory: ArrayBuffer;\n");
    try body.writer.writeAll("export declare const __sa_view: DataView;\n");
    try body.writer.writeAll("export declare const __sa_u8: Uint8Array;\n");
    try body.writer.writeAll("export declare function __sa_alloc(size: number): number;\n");
    try body.writer.writeAll("export declare function __sa_free(ptr: SaPtr): number;\n");
    try body.writer.writeAll("export declare function __sa_salloc(size: number): number;\n");
    try body.writer.writeAll("export declare function __sa_sfree(ptr: SaPtr): number;\n");
    try body.writer.writeAll("export declare function __sa_mem_used(): number;\n");
    const body_text = try body.toOwnedSlice();
    defer allocator.free(body_text);
    var out: std.Io.Writer.Allocating = .init(allocator);
    errdefer out.deinit();
    const w = &out.writer;
    try w.print("// Generated by `sa build-js --emit-dts` from {s}. Do not edit.\n", .{source_path});
    try w.writeAll("// SA void functions return 0 in the JS backend; i64/u64/ptr/handle\n");
    try w.writeAll("// values are `number | bigint` (measured, see DTS_EMIT_DESIGN.md).\n");
    if (aliases.sa_i64) try w.writeAll("export type SaI64 = number | bigint;\n");
    if (aliases.sa_u64) try w.writeAll("export type SaU64 = number | bigint;\n");
    if (aliases.sa_ptr) try w.writeAll("export type SaPtr = number | bigint;\n");
    if (aliases.sa_handle) try w.writeAll("export type SaHandle = number | bigint;\n");
    if (aliases.sa_fallible) try w.writeAll("export type SaFallible<T> = { s: number; v: T }; // v is meaningful only when s === 0\n");
    try w.writeAll(body_text);
    return out.toOwnedSlice();
}

/// Declaration path for a JS product path: strip the trailing
/// extension and append `.d.ts` (`foo.mjs` -> `foo.d.ts`).
pub fn dtsPathForJsPath(allocator: std.mem.Allocator, js_path: []const u8) ![]u8 {
    const ext = std.fs.path.extension(js_path);
    const stem = if (ext.len == 0) js_path else js_path[0 .. js_path.len - ext.len];
    return std.fmt.allocPrint(allocator, "{s}.d.ts", .{stem});
}

pub fn emitDtsToFile(allocator: std.mem.Allocator, verified: anytype, source_path: []const u8, js_opt: JsEmitOptions, npm_binds: *const std.StringHashMap([]const u8), js_path: []const u8) !void {
    const text = try emitDtsToString(allocator, verified, source_path, js_opt, npm_binds);
    defer allocator.free(text);
    const dts_path = try dtsPathForJsPath(allocator, js_path);
    defer allocator.free(dts_path);
    const dir = std.fs.path.dirname(dts_path);
    if (dir) |d| try sio.cwd().makePath(d);
    const f = try sio.cwd().createFile(dts_path, .{});
    defer f.close();
    try f.writeAll(text);
}

pub fn collectFuncTasks(allocator: std.mem.Allocator, verified: anytype) ![]FuncTask {
    var tasks = std.array_list.Managed(FuncTask).init(allocator);
    errdefer tasks.deinit();
    var sig_index: usize = 0;
    var idx: usize = 0;
    while (idx < verified.annotated.len) : (idx += 1) {
        const k = verified.annotated[idx].base.kind;
        switch (k) {
            .func_decl, .ffi_wrapper_decl, .extern_decl, .export_decl, .test_decl, .gpu_decl => {
                sig_index += 1;
                var end = idx + 1;
                while (end < verified.annotated.len) {
                    const nk = verified.annotated[end].base.kind;
                    switch (nk) {
                        .func_decl, .ffi_wrapper_decl, .extern_decl, .export_decl, .test_decl, .gpu_decl => break,
                        else => end += 1,
                    }
                }
                try tasks.append(.{
                    .fsig_index = sig_index - 1,
                    .start_idx = idx,
                    .end_idx = end,
                    .kind = k,
                });
                idx = end - 1;
            },
            else => {},
        }
    }
    return tasks.toOwnedSlice();
}

pub fn writeRuntimeHeader(writer: anytype, js_opt: JsEmitOptions, size_bits: u16, npm_imports: []const NpmImport) !void {
    const mem_bytes: usize = @as(usize, js_opt.mem_pages) * 65536;
    try writer.print("// Generated by `sa build-js` (js backend, MVP). DO NOT EDIT.\n", .{});
    try writer.print("// size_bits={d} pages={d} ({d} bytes linear memory)\n", .{ size_bits, js_opt.mem_pages, mem_bytes });
    // Third-party/host ESM imports for `#npm_bind` externs (JS target only).
    // Grouped by specifier; one alias per bound export. Bare npm specifiers
    // resolve through the runner's node_modules; `node:` builtins need none.
    // Namespace bindings (`"spec#ns.member"`) get their own
    // `import * as` statement each.
    if (npm_imports.len != 0) {
        if (js_opt.format == .esm) {
            // Named imports, one statement per specifier.
            for (npm_imports, 0..) |item, idx| {
                if (item.member != null) continue;
                if (item.shape == .method or item.shape == .get) continue; // handle shapes import nothing
                var done = false;
                for (npm_imports[0..idx]) |prev| {
                    if (prev.member == null and std.mem.eql(u8, prev.spec, item.spec)) {
                        done = true;
                        break;
                    }
                }
                if (done) continue;
                try writer.writeAll("import { ");
                var first = true;
                for (npm_imports) |other| {
                    if (other.member != null or !std.mem.eql(u8, other.spec, item.spec)) continue;
                    if (!first) try writer.writeAll(", ");
                    first = false;
                    try writer.writeAll(other.export_name);
                    try writer.writeAll(" as ");
                    try writer.writeAll(other.alias);
                }
                try writer.print(" }} from \"{s}\";\n", .{item.spec});
            }
            // Namespace imports, one statement each.
            for (npm_imports) |item| {
                if (item.member == null) continue;
                try writer.print("import * as {s} from \"{s}\";\n", .{ item.alias, item.spec });
            }
        } else {
            for (npm_imports) |item| {
                if (item.member != null) continue;
                if (item.shape == .method or item.shape == .get) continue; // handle shapes import nothing
                try writer.print("const {{ {s}: {s} }} = require(\"{s}\");\n", .{ item.export_name, item.alias, item.spec });
            }
            for (npm_imports) |item| {
                if (item.member == null) continue;
                try writer.print("const {s} = require(\"{s}\");\n", .{ item.alias, item.spec });
            }
        }
    }
    try writer.writeAll(@import("runtime_header_a.zig").header_runtime_js_a);
    try writer.writeAll("\n");
    try writer.writeAll(@import("runtime_header_b.zig").header_runtime_js_b);
}

const DtsAliases = @import("dts.zig").DtsAliases;

const dtsTypeName = @import("dts.zig").dtsTypeName;

const writeDtsReturnType = @import("dts.zig").writeDtsReturnType;

const writeDtsDecl = @import("dts.zig").writeDtsDecl;

const dtsNameAlloc = @import("dts.zig").dtsNameAlloc;


/// dce=full reference census for extern stubs: the set of rendered JS
/// names that emitted code can still reference.
///  (A) direct `.call` callees in every emitted (non-extern) body --
///      the same parse the call emitters use; calls that fail to parse
///      or are flagged indirect emit trap text / resolve through the
///      function table, never a bare name reference;
///  (B) every vtable slot name -- the `__sa_ftable` prologue references
///      them all by name, and `.func` operands / `call_indirect` can
///      only resolve through that table (a name outside it is a build
///      error today).
/// Runtime chunks and emitter shim bodies never call SA-level
/// functions by name (audited: they use `__sa_*` helpers and their own
/// nested helpers only), and there is no eval / Function() / dynamic
/// global lookup anywhere in this backend, so (A) + (B) is the
/// complete reference surface.
pub fn collectReferencedJsNames(
    allocator: std.mem.Allocator,
    verified: anytype,
    tasks: []const FuncTask,
    fn_names: []const []const u8,
) !std.StringHashMap(void) {
    var set = std.StringHashMap(void).init(allocator);
    errdefer {
        var kit = set.keyIterator();
        while (kit.next()) |k| allocator.free(k.*);
        set.deinit();
    }
    for (fn_names) |fname| try putJsNameKey(&set, allocator, fname);
    for (tasks) |task| {
        if (task.kind == .extern_decl) continue;
        var i = task.start_idx;
        while (i < task.end_idx) : (i += 1) {
            const base = verified.annotated[i].base;
            if (base.kind != .call) continue;
            var parsed = call.parseInstructionCall(allocator, base, verified.symbols) catch continue;
            defer parsed.deinit(allocator);
            if (parsed.is_indirect) continue;
            try putJsNameKey(&set, allocator, parsed.callee);
        }
    }
    return set;
}

/// Render a function name exactly as the emitter writes it into JS
/// (`jsFuncName`: quote/@ stripping + identifier sanitization) as an
/// owned key. Reference sets are keyed by these rendered names so the
/// callee spelling, the vtable slot spelling and the signature name
/// compare equal whenever they would emit the same JS identifier.
pub fn jsNameKey(allocator: std.mem.Allocator, name: []const u8) ![]u8 {
    var out: std.Io.Writer.Allocating = .init(allocator);
    errdefer out.deinit();
    try jsFuncName(&out.writer, name);
    return out.toOwnedSlice();
}

pub fn putJsNameKey(set: *std.StringHashMap(void), allocator: std.mem.Allocator, name: []const u8) !void {
    const key = try jsNameKey(allocator, name);
    errdefer allocator.free(key);
    const gop = try set.getOrPut(key);
    if (gop.found_existing) allocator.free(key);
}
