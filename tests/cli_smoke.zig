const std = @import("std");
const saasm = @import("saasm");

fn writeSource(dir: std.fs.Dir, path: []const u8, source: []const u8) !void {
    var file = try dir.createFile(path, .{ .truncate = true });
    defer file.close();
    try file.writeAll(source);
}

fn runCommand(allocator: std.mem.Allocator, argv: []const []const u8) ![]u8 {
    const result = try std.process.Child.run(.{
        .allocator = allocator,
        .argv = argv,
    });
    errdefer allocator.free(result.stdout);
    defer allocator.free(result.stderr);

    switch (result.term) {
        .Exited => |code| {
            if (code != 0) return error.TestUnexpectedResult;
        },
        else => return error.TestUnexpectedResult,
    }

    return result.stdout;
}

fn runCommandAnyExit(allocator: std.mem.Allocator, argv: []const []const u8) !std.process.Child.RunResult {
    return try std.process.Child.run(.{
        .allocator = allocator,
        .argv = argv,
    });
}

test "cli run/build-exe/build-wasm produce real artifacts" {
    const source =
        \\#loc "hello.rs":10:4
        \\@main() -> i32:
        \\node = alloc 8
        \\!node
        \\return 7
    ;

    var original_cwd = try std.fs.cwd().openDir(".", .{});
    defer original_cwd.close();
    var tmp = std.testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();

    try tmp.dir.setAsCwd();
    defer original_cwd.setAsCwd() catch {};

    try writeSource(tmp.dir, "sample.saasm", source);

    const run_argv = [_][]const u8{ "saasm", "run", "sample.saasm" };
    const run_code = try saasm.cli.execute(std.testing.allocator, run_argv[0..]);
    try std.testing.expectEqual(@as(u8, 7), run_code);

    const exe_path = "sample.out";
    const build_exe_argv = [_][]const u8{ "saasm", "build-exe", "sample.saasm", "-o", exe_path, "-g" };
    const exe_code = try saasm.cli.execute(std.testing.allocator, build_exe_argv[0..]);
    try std.testing.expectEqual(@as(u8, 0), exe_code);

    const exe = try tmp.dir.openFile(exe_path, .{});
    defer exe.close();
    const exe_bytes = try exe.readToEndAlloc(std.testing.allocator, 1 << 20);
    defer std.testing.allocator.free(exe_bytes);
    try std.testing.expect(exe_bytes.len > 0);

    const ll_path = "sample.out.saasm.ll";
    const ll = try tmp.dir.openFile(ll_path, .{});
    defer ll.close();
    const ll_bytes = try ll.readToEndAlloc(std.testing.allocator, 1 << 20);
    defer std.testing.allocator.free(ll_bytes);
    try std.testing.expect(std.mem.containsAtLeast(u8, ll_bytes, 1, "!llvm.dbg.cu"));
    try std.testing.expect(std.mem.containsAtLeast(u8, ll_bytes, 1, "!DILocation(line: 10, column: 4"));
    try std.testing.expect(std.mem.containsAtLeast(u8, ll_bytes, 1, "!DISubprogram(name: \"main\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, ll_bytes, 1, "store i32 %argc, ptr @saasm_argc, align 4, !dbg"));
    try std.testing.expect(std.mem.containsAtLeast(u8, ll_bytes, 1, "ret i32 %res, !dbg"));

    const obj_path = "sample.o";
    const build_obj_argv = [_][]const u8{ "saasm", "build-obj", "sample.saasm", "-o", obj_path };
    const obj_code = try saasm.cli.execute(std.testing.allocator, build_obj_argv[0..]);
    try std.testing.expectEqual(@as(u8, 0), obj_code);

    const obj = try tmp.dir.openFile(obj_path, .{});
    defer obj.close();
    const obj_bytes = try obj.readToEndAlloc(std.testing.allocator, 1 << 20);
    defer std.testing.allocator.free(obj_bytes);
    try std.testing.expect(obj_bytes.len > 0);

    const wasm_path = "sample.wasm";
    const build_wasm_argv = [_][]const u8{ "saasm", "build-wasm", "sample.saasm", "-o", wasm_path, "--target", "wasm32" };
    const wasm_code = try saasm.cli.execute(std.testing.allocator, build_wasm_argv[0..]);
    try std.testing.expectEqual(@as(u8, 0), wasm_code);

    const wasm = try tmp.dir.openFile(wasm_path, .{});
    defer wasm.close();
    const wasm_bytes = try wasm.readToEndAlloc(std.testing.allocator, 1 << 20);
    defer std.testing.allocator.free(wasm_bytes);
    try std.testing.expect(wasm_bytes.len > 8);
    try std.testing.expectEqualSlices(u8, &std.wasm.magic, wasm_bytes[0..4]);
    try std.testing.expectEqualSlices(u8, &std.wasm.version, wasm_bytes[4..8]);
}

test "panic builtins terminate through the interpreter" {
    const plain_source =
        \\@main() -> i32:
        \\panic(17)
    ;

    var original_cwd = try std.fs.cwd().openDir(".", .{});
    defer original_cwd.close();
    var tmp = std.testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();

    try tmp.dir.setAsCwd();
    defer original_cwd.setAsCwd() catch {};

    try writeSource(tmp.dir, "panic.saasm", plain_source);

    const plain_argv = [_][]const u8{ "saasm", "run", "panic.saasm" };
    const plain_code = try saasm.cli.execute(std.testing.allocator, plain_argv[0..]);
    try std.testing.expectEqual(@as(u8, 145), plain_code);

    const msg_source =
        \\@main() -> i32:
        \\buf = alloc 3
        \\store buf+0, 104 as i8
        \\store buf+1, 105 as i8
        \\store buf+2, 0 as i8
        \\panic_msg(23, *buf, 2)
    ;

    try writeSource(tmp.dir, "panic_msg.saasm", msg_source);

    const msg_argv = [_][]const u8{ "saasm", "run", "panic_msg.saasm" };
    const msg_code = try saasm.cli.execute(std.testing.allocator, msg_argv[0..]);
    try std.testing.expectEqual(@as(u8, 151), msg_code);
}

test "fallible ABI and ? propagation work end to end" {
    const source =
        \\@helper() -> i32!:
        \\return 7
        \\@main() -> i32!:
        \\tmp = call @helper()
        \\value = ? tmp
        \\return value
    ;

    var original_cwd = try std.fs.cwd().openDir(".", .{});
    defer original_cwd.close();
    var tmp = std.testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();

    try tmp.dir.setAsCwd();
    defer original_cwd.setAsCwd() catch {};
    try writeSource(tmp.dir, "fallible.saasm", source);

    const run_argv = [_][]const u8{ "saasm", "run", "fallible.saasm" };
    const run_code = try saasm.cli.execute(std.testing.allocator, run_argv[0..]);
    try std.testing.expectEqual(@as(u8, 0), run_code);

    const build_exe_argv = [_][]const u8{ "saasm", "build-exe", "fallible.saasm", "-o", "fallible.out" };
    const exe_code = try saasm.cli.execute(std.testing.allocator, build_exe_argv[0..]);
    try std.testing.expectEqual(@as(u8, 0), exe_code);

    const ll_file = try tmp.dir.openFile("fallible.out.saasm.ll", .{});
    defer ll_file.close();
    const ll_bytes = try ll_file.readToEndAlloc(std.testing.allocator, 1 << 20);
    defer std.testing.allocator.free(ll_bytes);
    try std.testing.expect(std.mem.containsAtLeast(u8, ll_bytes, 1, "define {i32, i32} @helper()"));
    try std.testing.expect(std.mem.containsAtLeast(u8, ll_bytes, 1, "call {i32, i32} @helper()"));
    try std.testing.expect(std.mem.containsAtLeast(u8, ll_bytes, 1, "extractvalue {i32, i32}"));

    const exe_result = try runCommandAnyExit(std.testing.allocator, &[_][]const u8{"./fallible.out"});
    defer std.testing.allocator.free(exe_result.stdout);
    defer std.testing.allocator.free(exe_result.stderr);
    switch (exe_result.term) {
        .Exited => |code| try std.testing.expectEqual(@as(u8, 0), code),
        else => return error.TestUnexpectedResult,
    }
}

test "const pointer stores survive load and print end to end" {
    const source =
        \\@import "../../../sa_std/io/print.saasm-iface"
        \\@const RESULT_OK = utf8:"OK\n"
        \\#def Box_SIZE = 8
        \\#def Box_ptr = +0
        \\@main() -> i32:
        \\box = alloc Box_SIZE
        \\store box+Box_ptr, &RESULT_OK as ptr
        \\loaded = load box+Box_ptr as ptr
        \\call @sa_print_bytes(&loaded, 3)
        \\!loaded
        \\!box
        \\return 0
    ;

    var original_cwd = try std.fs.cwd().openDir(".", .{});
    defer original_cwd.close();
    var tmp = std.testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();

    try tmp.dir.setAsCwd();
    defer original_cwd.setAsCwd() catch {};
    try writeSource(tmp.dir, "const_ptr_store.saasm", source);

    const build_exe_argv = [_][]const u8{ "saasm", "build-exe", "const_ptr_store.saasm", "-o", "const_ptr_store.out" };
    const exe_code = try saasm.cli.execute(std.testing.allocator, build_exe_argv[0..]);
    try std.testing.expectEqual(@as(u8, 0), exe_code);

    const exe_result = try runCommandAnyExit(std.testing.allocator, &[_][]const u8{"./const_ptr_store.out"});
    defer std.testing.allocator.free(exe_result.stdout);
    defer std.testing.allocator.free(exe_result.stderr);
    switch (exe_result.term) {
        .Exited => |code| try std.testing.expectEqual(@as(u8, 0), code),
        else => return error.TestUnexpectedResult,
    }
    try std.testing.expectEqualStrings("OK\n", exe_result.stdout);
}

test "vtable loads preserve indirect call provenance end to end" {
    const source =
        \\@import "../../../sa_std/io/print.saasm-iface"
        \\@const RESULT_OK = utf8:"OK\n"
        \\@const VTABLE = vtable { run = @slot_run }
        \\#def Obj_SIZE = 16
        \\#def Obj_DATA = +0
        \\#def Obj_VTABLE = +8
        \\#def VTable_run = +0
        \\@slot_run(&self: ptr) -> i32:
        \\L_ENTRY:
        \\    value = load self+Obj_DATA as i32
        \\    return value
        \\@invoke(&obj: ptr) -> i32:
        \\L_ENTRY:
        \\    vt = load obj+Obj_VTABLE as ptr
        \\    fn = load vt+VTable_run as ptr
        \\    value = call_indirect fn(&obj)
        \\    !fn
        \\    !vt
        \\    return value
        \\@main() -> i32:
        \\L_ENTRY:
        \\    obj = alloc Obj_SIZE
        \\    store obj+Obj_DATA, 77 as i32
        \\    store obj+Obj_VTABLE, &VTABLE as ptr
        \\    result = call @invoke(&obj)
        \\    ok = eq result, 77
        \\    !result
        \\    !obj
        \\    br ok -> L_OK, L_ERR
        \\L_OK:
        \\    !ok
        \\    call @sa_print_bytes(&RESULT_OK, 3)
        \\    return 0
        \\L_ERR:
        \\    !ok
        \\    return 1
    ;

    var original_cwd = try std.fs.cwd().openDir(".", .{});
    defer original_cwd.close();
    var tmp = std.testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();

    try tmp.dir.setAsCwd();
    defer original_cwd.setAsCwd() catch {};
    try writeSource(tmp.dir, "vtable_indirect.saasm", source);

    const build_exe_argv = [_][]const u8{ "saasm", "build-exe", "vtable_indirect.saasm", "-o", "vtable_indirect.out" };
    const exe_code = try saasm.cli.execute(std.testing.allocator, build_exe_argv[0..]);
    try std.testing.expectEqual(@as(u8, 0), exe_code);

    const exe_result = try runCommandAnyExit(std.testing.allocator, &[_][]const u8{"./vtable_indirect.out"});
    defer std.testing.allocator.free(exe_result.stdout);
    defer std.testing.allocator.free(exe_result.stderr);
    switch (exe_result.term) {
        .Exited => |code| try std.testing.expectEqual(@as(u8, 0), code),
        else => return error.TestUnexpectedResult,
    }
    try std.testing.expectEqualStrings("OK\n", exe_result.stdout);
}

test "import expansion keeps source paths alive end to end" {
    var original_cwd = try std.fs.cwd().openDir(".", .{});
    defer original_cwd.close();
    const source_path = try original_cwd.realpathAlloc(std.testing.allocator, "demos/rosetta/40_impl_block_state/main.saasm");
    defer std.testing.allocator.free(source_path);

    var tmp = std.testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();

    try tmp.dir.setAsCwd();
    defer original_cwd.setAsCwd() catch {};

    const build_exe_argv = [_][]const u8{ "saasm", "build-exe", source_path, "-o", "impl_block_state.out" };
    const exe_code = try saasm.cli.execute(std.testing.allocator, build_exe_argv[0..]);
    try std.testing.expectEqual(@as(u8, 0), exe_code);

    const exe_result = try runCommandAnyExit(std.testing.allocator, &[_][]const u8{"./impl_block_state.out"});
    defer std.testing.allocator.free(exe_result.stdout);
    defer std.testing.allocator.free(exe_result.stderr);
    switch (exe_result.term) {
        .Exited => |code| try std.testing.expectEqual(@as(u8, 0), code),
        else => return error.TestUnexpectedResult,
    }
    try std.testing.expectEqualStrings("15\n", exe_result.stdout);
}

test "atomic instructions work end to end and emit real LLVM" {
    const source =
        \\@main() -> i32:
        \\node = alloc 8
        \\atomic_store node+0, 5 seq_cst
        \\fence release
        \\x = atomic_load node+0 seq_cst
        \\old = atomic_rmw_add node+0, 3 seq_cst
        \\cmp_old, ok = cmpxchg node+0, 8, 11 acq_rel acquire
        \\y = atomic_load node+0 seq_cst
        \\^x
        \\^old
        \\^cmp_old
        \\^ok
        \\!node
        \\return y
    ;

    var original_cwd = try std.fs.cwd().openDir(".", .{});
    defer original_cwd.close();
    var tmp = std.testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();

    try tmp.dir.setAsCwd();
    defer original_cwd.setAsCwd() catch {};

    try writeSource(tmp.dir, "atomic.saasm", source);

    const run_argv = [_][]const u8{ "saasm", "run", "atomic.saasm" };
    const run_code = try saasm.cli.execute(std.testing.allocator, run_argv[0..]);
    try std.testing.expectEqual(@as(u8, 11), run_code);

    const build_exe_argv = [_][]const u8{ "saasm", "build-exe", "atomic.saasm", "-o", "atomic.out" };
    const exe_code = try saasm.cli.execute(std.testing.allocator, build_exe_argv[0..]);
    try std.testing.expectEqual(@as(u8, 0), exe_code);

    const ll_file = try tmp.dir.openFile("atomic.out.saasm.ll", .{});
    defer ll_file.close();
    const ll_bytes = try ll_file.readToEndAlloc(std.testing.allocator, 1 << 20);
    defer std.testing.allocator.free(ll_bytes);
    try std.testing.expect(std.mem.containsAtLeast(u8, ll_bytes, 1, "load atomic i64"));
    try std.testing.expect(std.mem.containsAtLeast(u8, ll_bytes, 1, "store atomic i64"));
    try std.testing.expect(std.mem.containsAtLeast(u8, ll_bytes, 1, "atomicrmw add"));
    try std.testing.expect(std.mem.containsAtLeast(u8, ll_bytes, 1, "cmpxchg ptr"));
    try std.testing.expect(std.mem.containsAtLeast(u8, ll_bytes, 1, "fence release"));

    const exe_result = try runCommandAnyExit(std.testing.allocator, &[_][]const u8{"./atomic.out"});
    defer std.testing.allocator.free(exe_result.stdout);
    defer std.testing.allocator.free(exe_result.stderr);
    switch (exe_result.term) {
        .Exited => |code| try std.testing.expectEqual(@as(u8, 11), code),
        else => return error.TestUnexpectedResult,
    }

    const build_wasm_argv = [_][]const u8{ "saasm", "build-wasm", "atomic.saasm", "-o", "atomic.wasm", "--target", "wasm32" };
    const wasm_code = try saasm.cli.execute(std.testing.allocator, build_wasm_argv[0..]);
    try std.testing.expectEqual(@as(u8, 0), wasm_code);

    const wasm_file = try tmp.dir.openFile("atomic.wasm", .{});
    defer wasm_file.close();
    const wasm_bytes = try wasm_file.readToEndAlloc(std.testing.allocator, 1 << 20);
    defer std.testing.allocator.free(wasm_bytes);
    try std.testing.expect(wasm_bytes.len > 8);
    try std.testing.expectEqualSlices(u8, &std.wasm.magic, wasm_bytes[0..4]);
    try std.testing.expectEqualSlices(u8, &std.wasm.version, wasm_bytes[4..8]);

    const build_obj_argv = [_][]const u8{ "saasm", "build-obj", "atomic.saasm", "-o", "atomic.o" };
    const obj_code = try saasm.cli.execute(std.testing.allocator, build_obj_argv[0..]);
    try std.testing.expectEqual(@as(u8, 0), obj_code);

    const obj_file = try tmp.dir.openFile("atomic.o", .{});
    defer obj_file.close();
    const obj_bytes = try obj_file.readToEndAlloc(std.testing.allocator, 1 << 20);
    defer std.testing.allocator.free(obj_bytes);
    try std.testing.expect(obj_bytes.len > 0);
}

test "ptr arithmetic lowers to gep and runs through the interpreter" {
    const source =
        \\@main() -> i32:
        \\node = alloc 8
        \\one_buf = alloc 8
        \\store one_buf+0, 1 as i64
        \\one = load one_buf+0 as i64
        \\p = ptr_add node, one
        \\store p+0, 65 as i32
        \\value = load p+0 as i32
        \\!p
        \\!one
        \\!one_buf
        \\!node
        \\return value
    ;

    var original_cwd = try std.fs.cwd().openDir(".", .{});
    defer original_cwd.close();
    var tmp = std.testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();

    try tmp.dir.setAsCwd();
    defer original_cwd.setAsCwd() catch {};

    try writeSource(tmp.dir, "ptr_add.saasm", source);

    const run_argv = [_][]const u8{ "saasm", "run", "ptr_add.saasm" };
    const run_code = try saasm.cli.execute(std.testing.allocator, run_argv[0..]);
    try std.testing.expectEqual(@as(u8, 65), run_code);

    const build_exe_argv = [_][]const u8{ "saasm", "build-exe", "ptr_add.saasm", "-o", "ptr_add.out" };
    const exe_code = try saasm.cli.execute(std.testing.allocator, build_exe_argv[0..]);
    try std.testing.expectEqual(@as(u8, 0), exe_code);

    const ll_file = try tmp.dir.openFile("ptr_add.out.saasm.ll", .{});
    defer ll_file.close();
    const ll_bytes = try ll_file.readToEndAlloc(std.testing.allocator, 1 << 20);
    defer std.testing.allocator.free(ll_bytes);
    try std.testing.expect(std.mem.containsAtLeast(u8, ll_bytes, 1, "define i32 @saasm_main()"));
    try std.testing.expect(std.mem.containsAtLeast(u8, ll_bytes, 1, "getelementptr i8, ptr"));

    const exe_result = try runCommandAnyExit(std.testing.allocator, &[_][]const u8{"./ptr_add.out"});
    defer std.testing.allocator.free(exe_result.stdout);
    defer std.testing.allocator.free(exe_result.stderr);
    switch (exe_result.term) {
        .Exited => |code| try std.testing.expectEqual(@as(u8, 65), code),
        else => return error.TestUnexpectedResult,
    }
}

test "invalid cmpxchg ordering is rejected by the flattener" {
    const source =
        \\@main() -> i32:
        \\node = alloc 8
        \\old, ok = cmpxchg node+0, 0, 1 acquire seq_cst
        \\return 0
    ;

    try std.testing.expectError(error.InvalidAtomicOrdering, saasm.flattener.flatten(std.testing.allocator, source));
}

test "atomic ordering mismatch is rejected by the verifier" {
    const source =
        \\@main() -> i32:
        \\node = alloc 8
        \\old = atomic_rmw_add node+0, 1 acquire
        \\old2 = atomic_rmw_sub node+0, 1 release
        \\return 0
    ;

    var flat = try saasm.flattener.flatten(std.testing.allocator, source);
    defer flat.deinit(std.testing.allocator);

    const verified = try saasm.referee.verify(std.testing.allocator, flat.instructions, flat.const_decls);
    switch (verified) {
        .ok => return error.TestUnexpectedResult,
        .trap => |report| {
            try std.testing.expectEqual(saasm.common.trap.Trap.atomic_ordering_mismatch, report.trap);
            try std.testing.expect(std.mem.containsAtLeast(u8, report.message, 1, "same-address RMW ordering combination"));
        },
    }
}

test "panic lowers to a real runtime call in emitted LLVM and native executables exit with that code" {
    const source =
        \\@helper() -> i32:
        \\panic(13)
        \\@main() -> i32:
        \\buf = alloc 3
        \\store buf+0, 104 as i8
        \\store buf+1, 105 as i8
        \\store buf+2, 0 as i8
        \\panic_msg(77, *buf, 2)
    ;

    var original_cwd = try std.fs.cwd().openDir(".", .{});
    defer original_cwd.close();
    var tmp = std.testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();

    try tmp.dir.setAsCwd();
    defer original_cwd.setAsCwd() catch {};

    try writeSource(tmp.dir, "panic_native.saasm", source);

    const build_exe_argv = [_][]const u8{ "saasm", "build-exe", "panic_native.saasm", "-o", "panic_native.out" };
    const exe_code = try saasm.cli.execute(std.testing.allocator, build_exe_argv[0..]);
    try std.testing.expectEqual(@as(u8, 0), exe_code);

    const ll_file = try tmp.dir.openFile("panic_native.out.saasm.ll", .{});
    defer ll_file.close();
    const ll_bytes = try ll_file.readToEndAlloc(std.testing.allocator, 1 << 20);
    defer std.testing.allocator.free(ll_bytes);
    try std.testing.expect(std.mem.containsAtLeast(u8, ll_bytes, 1, "define void @__sa_panic(i32 %code, ptr %msg, i64 %len)"));
    try std.testing.expect(std.mem.containsAtLeast(u8, ll_bytes, 1, "@__sa_panic("));
    try std.testing.expect(!std.mem.containsAtLeast(u8, ll_bytes, 1, "unreachable ; panic("));
    try std.testing.expect(!std.mem.containsAtLeast(u8, ll_bytes, 1, "unreachable ; panic_msg("));

    const exe_result = try runCommandAnyExit(std.testing.allocator, &[_][]const u8{"./panic_native.out"});
    defer std.testing.allocator.free(exe_result.stdout);
    defer std.testing.allocator.free(exe_result.stderr);
    switch (exe_result.term) {
        .Exited => |code| try std.testing.expectEqual(@as(u8, 205), code),
        else => return error.TestUnexpectedResult,
    }
    try std.testing.expect(std.mem.containsAtLeast(u8, exe_result.stderr, 1, "PANIC[77]: hi"));

    const build_wasm_argv = [_][]const u8{ "saasm", "build-wasm", "panic_native.saasm", "-o", "panic_native.wasm", "--target", "wasm32" };
    const wasm_code = try saasm.cli.execute(std.testing.allocator, build_wasm_argv[0..]);
    try std.testing.expectEqual(@as(u8, 0), wasm_code);

    const wasm = try tmp.dir.openFile("panic_native.wasm", .{});
    defer wasm.close();
    const wasm_bytes = try wasm.readToEndAlloc(std.testing.allocator, 1 << 20);
    defer std.testing.allocator.free(wasm_bytes);
    try std.testing.expect(wasm_bytes.len > 8);
    try std.testing.expectEqualSlices(u8, &std.wasm.magic, wasm_bytes[0..4]);
    try std.testing.expectEqualSlices(u8, &std.wasm.version, wasm_bytes[4..8]);
}

test "raw pointer escape is rejected outside ffi wrapper" {
    const source =
        \\@main() -> i32:
        \\node = alloc 8
        \\raw = *node
        \\return 0
    ;

    var flat = try saasm.flattener.flatten(std.testing.allocator, source);
    defer flat.deinit(std.testing.allocator);

    const verified = try saasm.referee.verify(std.testing.allocator, flat.instructions, flat.const_decls);
    switch (verified) {
        .ok => return error.TestUnexpectedResult,
        .trap => |report| {
            try std.testing.expectEqual(saasm.common.trap.Trap.illegal_unsafe_context, report.trap);
            try std.testing.expectEqual(@as(?bool, false), report.is_ffi_wrapper);
        },
    }
}

test "extern export ffi wrapper map to real declarations and symbols" {
    const source =
        \\@extern ext_add(lhs: i32, rhs: i32) -> i32
        \\@ffi_wrapper wrap(*raw: ptr) -> ptr:
        \\safe = assume_safe raw
        \\return safe
        \\@export exported() -> i32:
        \\jmp L_ENTRY
        \\L_ENTRY:
        \\value = call @ext_add(1, 2)
        \\return value
        \\@main() -> i32:
        \\return 7
    ;

    var original_cwd = try std.fs.cwd().openDir(".", .{});
    defer original_cwd.close();
    var tmp = std.testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();

    try tmp.dir.setAsCwd();
    defer original_cwd.setAsCwd() catch {};
    try writeSource(tmp.dir, "contracts.saasm", source);

    const build_obj_argv = [_][]const u8{ "saasm", "build-obj", "contracts.saasm", "-o", "contracts.o" };
    const code = try saasm.cli.execute(std.testing.allocator, build_obj_argv[0..]);
    try std.testing.expectEqual(@as(u8, 0), code);

    const ll_file = try tmp.dir.openFile("contracts.o.saasm.ll", .{});
    defer ll_file.close();
    const ll_bytes = try ll_file.readToEndAlloc(std.testing.allocator, 1 << 20);
    defer std.testing.allocator.free(ll_bytes);

    try std.testing.expect(std.mem.containsAtLeast(u8, ll_bytes, 1, "declare i32 @ext_add(i32, i32)"));
    try std.testing.expect(std.mem.containsAtLeast(u8, ll_bytes, 1, "define ptr @wrap(ptr %raw)"));
    try std.testing.expect(std.mem.containsAtLeast(u8, ll_bytes, 1, "define i32 @exported()"));
    try std.testing.expect(std.mem.containsAtLeast(u8, ll_bytes, 1, "L_ENTRY:"));
    try std.testing.expect(std.mem.containsAtLeast(u8, ll_bytes, 1, "define i32 @main(i32 %argc, ptr %argv)"));

    const nm_output = try runCommand(std.testing.allocator, &[_][]const u8{ "nm", "-g", "--defined-only", "contracts.o" });
    defer std.testing.allocator.free(nm_output);

    try std.testing.expect(std.mem.containsAtLeast(u8, nm_output, 1, " exported"));
    try std.testing.expect(std.mem.containsAtLeast(u8, nm_output, 1, " wrap"));
    try std.testing.expect(std.mem.containsAtLeast(u8, nm_output, 1, " saasm_main"));
    try std.testing.expect(std.mem.containsAtLeast(u8, nm_output, 1, " main"));
}

test "unknown sys intrinsic is rejected before emission" {
    const source =
        \\@main() -> i32:
        \\value = call @sys_not_supported()
        \\return value
    ;

    var original_cwd = try std.fs.cwd().openDir(".", .{});
    defer original_cwd.close();
    var tmp = std.testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();

    try tmp.dir.setAsCwd();
    defer original_cwd.setAsCwd() catch {};
    try writeSource(tmp.dir, "unsupported_sys.saasm", source);

    const build_exe_argv = [_][]const u8{ "saasm", "build-exe", "unsupported_sys.saasm", "-o", "unsupported_sys.out" };
    var stdout_buffer = std.ArrayList(u8).init(std.testing.allocator);
    defer stdout_buffer.deinit();
    var stderr_buffer = std.ArrayList(u8).init(std.testing.allocator);
    defer stderr_buffer.deinit();
    const code = try saasm.cli.executeWithWriters(
        std.testing.allocator,
        build_exe_argv[0..],
        stdout_buffer.writer(),
        stderr_buffer.writer(),
    );
    try std.testing.expectEqual(@as(u8, 1), code);
    try std.testing.expectError(error.FileNotFound, tmp.dir.openFile("unsupported_sys.out", .{}));
    try std.testing.expectError(error.FileNotFound, tmp.dir.openFile("unsupported_sys.out.saasm.ll", .{}));
    try std.testing.expect(std.mem.containsAtLeast(u8, stderr_buffer.items, 1, "\"trap\":\"UnsupportedSysIntrinsic\""));
}

test "v0.1 build-wasm rejects wasm64 target" {
    const source =
        \\@main() -> i32:
        \\return 0
    ;

    var original_cwd = try std.fs.cwd().openDir(".", .{});
    defer original_cwd.close();
    var tmp = std.testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();

    try tmp.dir.setAsCwd();
    defer original_cwd.setAsCwd() catch {};
    try writeSource(tmp.dir, "wasm64.saasm", source);

    const build_wasm_argv = [_][]const u8{ "saasm", "build-wasm", "wasm64.saasm", "-o", "wasm64.wasm", "--target", "wasm64" };
    try std.testing.expectError(error.InvalidTarget, saasm.cli.execute(std.testing.allocator, build_wasm_argv[0..]));
}

test "layout cli prints text and json outputs" {
    var stdout_buffer = std.ArrayList(u8).init(std.testing.allocator);
    defer stdout_buffer.deinit();
    var stderr_buffer = std.ArrayList(u8).init(std.testing.allocator);
    defer stderr_buffer.deinit();

    const text_argv = [_][]const u8{ "saasm", "layout", "--name", "Entity", "--fields", "id:u32, pos_x:f64, pos_y:f64, hp:i32" };
    const text_code = try saasm.cli.executeWithWriters(
        std.testing.allocator,
        text_argv[0..],
        stdout_buffer.writer(),
        stderr_buffer.writer(),
    );
    try std.testing.expectEqual(@as(u8, 0), text_code);
    try std.testing.expectEqualStrings(
        "#def Entity_SIZE  = 32\n#def Entity_id = +0\n// 4 bytes padding\n#def Entity_pos_x = +8\n#def Entity_pos_y = +16\n#def Entity_hp = +24\n// 4 bytes tail padding\n",
        stdout_buffer.items,
    );
    try std.testing.expectEqual(@as(usize, 0), stderr_buffer.items.len);

    stdout_buffer.clearRetainingCapacity();
    stderr_buffer.clearRetainingCapacity();

    const json_argv = [_][]const u8{ "saasm", "layout", "--name", "Pair", "--fields", "head:ptr, count:u32", "--format", "json", "--target", "32" };
    const json_code = try saasm.cli.executeWithWriters(
        std.testing.allocator,
        json_argv[0..],
        stdout_buffer.writer(),
        stderr_buffer.writer(),
    );
    try std.testing.expectEqual(@as(u8, 0), json_code);
    try std.testing.expectEqualStrings(
        "{\"name\":\"Pair\",\"size\":8,\"fields\":[{\"name\":\"head\",\"offset\":0,\"size\":4,\"ty\":\"ptr\"},{\"name\":\"count\",\"offset\":4,\"size\":4,\"ty\":\"u32\"}]}\n",
        stdout_buffer.items,
    );
    try std.testing.expectEqual(@as(usize, 0), stderr_buffer.items.len);
}
