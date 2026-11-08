const std = @import("std");
const saasm = @import("saasm");
const sio = @import("sio");

// Finding D regression: repeated in-process `sa check --emit-sab` calls
// must not interfere with each other.
//
// The process-global verdict cache (incr_verify) keys streams by a
// content hash that excludes line numbers, so two programs with
// byte-identical bodies under different header comments are the same
// stream. The second call used to hit the cache, and the fast path's
// trusted shell repurposed the FlattenResult in place (reg operands
// localized to slots; symbols and function sigs moved out), after
// which the standalone SAB encode re-verified the mutated stream and
// trapped: "check: SAB encode failed: verification trap". One-shot CLI
// processes always miss the cache and were unaffected, so the failure
// only appeared in long-lived in-process harnesses (daemon, test
// suites) after an identical stream had been compiled once.
//
// The fix makes `check --emit-sab` bypass the verdict-cache fast path
// so the encoder always consumes a pristine flat. This test drives the
// exact js-matrix harness call form (saasm.cli.execute in-process) on
// the 965/974-shaped pair and asserts every call succeeds and every
// emitted .sab loads back cleanly.

const body =
    \\@extern sa_task_spawn(*entry: ptr, arg: ptr, &out_handle: ptr) -> i32
    \\@extern sa_task_join(handle: u64) -> i32
    \\@extern sa_fmt_u64(value: u64, base: u32) -> u64
    \\@extern sa_fmt_buffer_data(buffer: u64) -> &ptr
    \\@extern sa_fmt_buffer_len(buffer: u64) -> u64
    \\@extern sa_fmt_buffer_free(^buffer: u64) -> i32
    \\@extern sa_print_bytes(&msg: ptr, len: u64) -> void
    \\
    \\@const NL = utf8:"\n"
    \\@const W_VT = vtable { call = @worker }
    \\
    \\@print_u64(v: u64) -> void:
    \\L_ENTRY:
    \\    buf = call @sa_fmt_u64(v, 10)
    \\    p = call @sa_fmt_buffer_data(buf)
    \\    n = call @sa_fmt_buffer_len(buf)
    \\    call @sa_print_bytes(&p, n)
    \\    call @sa_print_bytes(&NL, 1)
    \\    st = call @sa_fmt_buffer_free(^buf)
    \\    !st
    \\    !n
    \\    !p
    \\    !v
    \\    return
    \\
    \\@worker(arg: ptr) -> void:
    \\L_ENTRY:
    \\    store arg+0, 42 as u64
    \\    !arg
    \\    return
    \\
    \\@ffi_wrapper main() -> i32:
    \\L_ENTRY:
    \\    cell = alloc 8
    \\    store cell+0, 0 as u64
    \\    hs = stack_alloc 8
    \\    vt = &W_VT
    \\    fncell = load vt+0 as ptr
    \\    raw = *fncell
    \\    safe = assume_safe raw
    \\    st = call @sa_task_spawn(*safe, cell, &hs)
    \\    handle = load hs+0 as u64
    \\    jst = call @sa_task_join(handle)
    \\    v = load cell+0 as u64
    \\    call @print_u64(v)
    \\    jv = zext jst as u64
    \\    call @print_u64(jv)
    \\    !st
    \\    !fncell
    \\    !vt
    \\    !raw
    \\    !safe
    \\    !handle
    \\    !jst
    \\    !v
    \\    !jv
    \\    !cell
    \\    return 0
    \\
;

const header_a =
    \\// Probe g1: sa_task_spawn + sa_task_join (plain surface).
    \\// Worker stores 42 into the arg cell; main spawns, joins.
    \\
;

const header_b =
    \\// Regression: the SAB form of this program made the JS
    \\// emitter resolve call destinations through the wrong id
    \\// space, failing with "InvalidOperand in print_u64".
    \\// The text form emits fine. Worker stores 42 into the arg
    \\// cell; main spawns, joins, prints the cell value and the
    \\// join status. Expected (native, and JS via both forms):
    \\//   42
    \\//   0
    \\
;

fn checkEmitSab(name: []const u8) !u8 {
    const src_name = try std.fmt.allocPrint(std.testing.allocator, "{s}.sa", .{name});
    defer std.testing.allocator.free(src_name);
    const sab_name = try std.fmt.allocPrint(std.testing.allocator, "{s}.sab", .{name});
    defer std.testing.allocator.free(sab_name);
    const argv = [_][]const u8{ "sa", "check", src_name, "--emit-sab", sab_name };
    // DEF-SUITE-LISTEN-STALL: never call cli.execute in-process from a
    // test. execute() writes "check ok: ..." to the real process stdout,
    // which under `zig build` is the std.zig.Server (--listen=-) protocol
    // channel; the plain text corrupts the framing and both sides block
    // on pipe reads forever. Capture through executeWithWriters instead
    // (same rule cli_smoke documents for its check --emit-sab call).
    var out = std.array_list.Managed(u8).init(std.testing.allocator);
    defer out.deinit();
    var err = std.array_list.Managed(u8).init(std.testing.allocator);
    defer err.deinit();
    const code = try saasm.cli.executeWithWriters(std.testing.allocator, argv[0..], sio.managedWriter(&out), sio.managedWriter(&err));
    if (code == 0) try std.testing.expect(std.mem.indexOf(u8, out.items, "check ok") != null);
    return code;
}

fn checkSab(name: []const u8) !u8 {
    const sab_name = try std.fmt.allocPrint(std.testing.allocator, "{s}.sab", .{name});
    defer std.testing.allocator.free(sab_name);
    const argv = [_][]const u8{ "sa", "check", sab_name };
    var out = std.array_list.Managed(u8).init(std.testing.allocator);
    defer out.deinit();
    var err = std.array_list.Managed(u8).init(std.testing.allocator);
    defer err.deinit();
    const code = try saasm.cli.executeWithWriters(std.testing.allocator, argv[0..], sio.managedWriter(&out), sio.managedWriter(&err));
    if (code == 0) try std.testing.expect(std.mem.indexOf(u8, out.items, "check ok") != null);
    return code;
}

test "check --emit-sab repeated in-process on identical streams (finding D)" {
    var original_cwd = try sio.cwd().openDir(".", .{});
    defer original_cwd.close();
    var tmp = std.testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();
    var tdir: sio.Dir = .{ .inner = tmp.dir };
    try tdir.setAsCwd();
    defer original_cwd.setAsCwd() catch {};

    try tdir.writeFile(.{ .sub_path = "prog_a.sa", .data = header_a ++ body });
    try tdir.writeFile(.{ .sub_path = "prog_b.sa", .data = header_b ++ body });

    // First call: cold stream, always worked.
    try std.testing.expectEqual(@as(u8, 0), try checkEmitSab("prog_a"));
    // Second call: same stream under a different header. Pre-fix this
    // was a verdict-cache hit and trapped in the SAB encode.
    try std.testing.expectEqual(@as(u8, 0), try checkEmitSab("prog_b"));
    // Third call: repeat of the first program in the same process.
    try std.testing.expectEqual(@as(u8, 0), try checkEmitSab("prog_a"));

    // Every emitted .sab is non-empty and loads back through check.
    for ([_][]const u8{ "prog_a.sab", "prog_b.sab" }) |sab_name| {
        const stat = try tdir.statFile(sab_name);
        try std.testing.expect(stat.size > 0);
    }
    try std.testing.expectEqual(@as(u8, 0), try checkSab("prog_a"));
    try std.testing.expectEqual(@as(u8, 0), try checkSab("prog_b"));
}
