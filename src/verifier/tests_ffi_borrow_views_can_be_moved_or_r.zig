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

const VerifyResult = @import("reg_state_change.zig").VerifyResult;
const verify = @import("free_annotated_slice.zig").verify;
const verifyWithOptions = @import("free_annotated_slice.zig").verifyWithOptions;

test "ffi borrow views can be moved or returned" {
    const move_source =
        \\@ffi_wrapper wrap(*raw: ptr) -> i32:
        \\view = assume_borrow raw
        \\^view
        \\return 0
    ;
    var move_flat = try @import("../flattener.zig").flatten(std.testing.allocator, move_source);
    defer move_flat.deinit(std.testing.allocator);

    const moved = try verify(std.testing.allocator, move_flat.instructions, move_flat.const_decls);
    switch (moved) {
        .ok => |ok| {
            var owned = ok;
            defer owned.deinit(std.testing.allocator);
            var saw_move = false;
            for (owned.annotated) |item| {
                if (item.base.kind == .move_) {
                    saw_move = true;
                }
            }
            try std.testing.expect(saw_move);
        },
        .trap => return error.TestUnexpectedResult,
    }

    const return_source =
        \\@ffi_wrapper wrap(*raw: ptr) -> &ptr:
        \\view = assume_borrow raw
        \\return view
    ;
    var return_flat = try @import("../flattener.zig").flatten(std.testing.allocator, return_source);
    defer return_flat.deinit(std.testing.allocator);

    const returned = try verify(std.testing.allocator, return_flat.instructions, return_flat.const_decls);
    switch (returned) {
        .ok => |ok| {
            var owned = ok;
            defer owned.deinit(std.testing.allocator);
            var saw_return = false;
            for (owned.annotated) |item| {
                if (item.base.kind == .return_ and item.base.operands[0] == .reg) {
                    saw_return = true;
                }
            }
            try std.testing.expect(saw_return);
        },
        .trap => return error.TestUnexpectedResult,
    }
}

test "immutable const data can be read and printed without leak traps" {
    var consts = [_]const_decl.ConstDecl{
        .{
            .source_line = 1,
            .expanded_line = 0,
            .raw_text = try std.testing.allocator.dupe(u8, "@const HELLO_MSG = utf8:\"hello, saasm\\n\""),
            .name = try std.testing.allocator.dupe(u8, "HELLO_MSG"),
            .literal_text = try std.testing.allocator.dupe(u8, "utf8:\"hello, saasm\\n\""),
            .value = .{
                .utf8 = .{
                    .kind = .utf8,
                    .bytes = try std.testing.allocator.dupe(u8, "hello, saasm\n"),
                    .repeat_count = null,
                    .repeat_byte = null,
                },
            },
        },
    };
    defer {
        for (&consts) |*decl| decl.deinit(std.testing.allocator);
    }

    const program = [_]inst.Instruction{
        .{
            .kind = .extern_decl,
            .source_line = 1,
            .expanded_line = 0,
            .operands = .{
                .{ .symbol = 2 },
                .{ .func = 1 },
                .{ .none = {} },
                .{ .none = {} },
            },
            .raw_text = "@extern sa_print_bytes(&msg: ptr, len: u64) -> void",
        },
        .{
            .kind = .func_decl,
            .source_line = 2,
            .expanded_line = 1,
            .operands = .{
                .{ .symbol = 0 },
                .{ .func = 0 },
                .{ .none = {} },
                .{ .none = {} },
            },
            .raw_text = "@main() -> i32:",
        },
        .{
            .kind = .label,
            .source_line = 3,
            .expanded_line = 2,
            .operands = .{
                .{ .symbol = 1 },
                .{ .label = 1 },
                .{ .none = {} },
                .{ .none = {} },
            },
            .raw_text = "L_ENTRY:",
        },
        .{
            .kind = .call,
            .source_line = 4,
            .expanded_line = 3,
            .operands = .{
                .{ .text = "call @sa_print_bytes(&HELLO_MSG, 13)" },
                .{ .none = {} },
                .{ .none = {} },
                .{ .none = {} },
            },
            .raw_text = "call @sa_print_bytes(&HELLO_MSG, 13)",
        },
        .{
            .kind = .return_,
            .source_line = 5,
            .expanded_line = 4,
            .operands = .{
                .{ .text = "0" },
                .{ .none = {} },
                .{ .none = {} },
                .{ .none = {} },
            },
            .raw_text = "return 0",
        },
    };

    const verified = try verify(std.testing.allocator, program[0..], consts[0..]);
    switch (verified) {
        .ok => |ok| {
            var owned = ok;
            defer owned.deinit(std.testing.allocator);
            try std.testing.expectEqual(@as(usize, 5), owned.annotated.len);
        },
        .trap => return error.TestUnexpectedResult,
    }
}

test "loop snapshots ignore stable extern calls that touch const data" {
    const source =
        \\@extern sa_print_bytes(&msg: ptr, len: u64) -> i32
        \\@const HELLO_MSG = utf8:"hello"
        \\@helper() -> i32:
        \\L_HELPER:
        \\printed = call @sa_print_bytes(&HELLO_MSG, 5)
        \\return printed
        \\@main(n: u64) -> i32:
        \\L_ENTRY:
        \\i_slot = stack_alloc 8
        \\store i_slot+0, 0 as u64
        \\jmp L_COND
        \\L_COND:
        \\i = load i_slot+0 as u64
        \\keep_going = ult i, n
        \\br keep_going -> L_BODY, L_EXIT
        \\L_BODY:
        \\printed = call @helper()
        \\next = add i, 1
        \\store i_slot+0, next as u64
        \\!next
        \\!printed
        \\!i
        \\!keep_going
        \\jmp L_COND
        \\L_EXIT:
        \\!i
        \\!keep_going
        \\!n
        \\return 0
    ;

    var flat = try @import("../flattener.zig").flatten(std.testing.allocator, source);
    defer flat.deinit(std.testing.allocator);

    const verified = try verify(std.testing.allocator, flat.instructions, flat.const_decls);
    switch (verified) {
        .ok => |ok| {
            var owned = ok;
            defer owned.deinit(std.testing.allocator);
            try std.testing.expect(owned.annotated.len > 0);
        },
        .trap => |report| {
            std.debug.print("trap={s} msg={s} line={} source_line={} source={s} register={s}\n", .{
                @tagName(report.trap),
                report.message,
                report.line,
                report.source_line,
                report.source_text orelse "",
                report.register orelse "",
            });
            return error.TestUnexpectedResult;
        },
    }
}

test "bodyless extern at end does not leak its signature parameters" {
    const source =
        \\@main() -> i32:
        \\L_ENTRY:
        \\return 0
        \\@extern sa_http_client_free(^client: ptr) -> u32
    ;

    var flat = try @import("../flattener.zig").flatten(std.testing.allocator, source);
    defer flat.deinit(std.testing.allocator);

    const serial = try verifyWithOptions(std.testing.allocator, flat.instructions, flat.const_decls, .{ .jobs = 1 });
    switch (serial) {
        .ok => |ok| {
            var owned = ok;
            defer owned.deinit(std.testing.allocator);
            try std.testing.expectEqual(@as(usize, 2), owned.function_sigs.len);
        },
        .trap => |report| {
            std.debug.print("serial trap={s} msg={s} source={s} register={s}\n", .{
                @tagName(report.trap),
                report.message,
                report.source_text orelse "",
                report.register orelse "",
            });
            return error.TestUnexpectedResult;
        },
    }

    const parallel = try verifyWithOptions(std.testing.allocator, flat.instructions, flat.const_decls, .{ .jobs = 2 });
    switch (parallel) {
        .ok => |ok| {
            var owned = ok;
            defer owned.deinit(std.testing.allocator);
            try std.testing.expectEqual(@as(usize, 2), owned.function_sigs.len);
        },
        .trap => |report| {
            std.debug.print("parallel trap={s} msg={s} source={s} register={s}\n", .{
                @tagName(report.trap),
                report.message,
                report.source_text orelse "",
                report.register orelse "",
            });
            return error.TestUnexpectedResult;
        },
    }
}

test "function declaration operands do not pollute previous function scope" {
    const source =
        \\@first() -> i32:
        \\L_FIRST:
        \\left = add 1, 1
        \\!left
        \\return 0
        \\@second(&out_len: ptr) -> i32:
        \\L_SECOND:
        \\!out_len
        \\return 0
    ;

    var flat = try @import("../flattener.zig").flatten(std.testing.allocator, source);
    defer flat.deinit(std.testing.allocator);

    const verified = try verify(std.testing.allocator, flat.instructions, flat.const_decls);
    switch (verified) {
        .ok => |ok| {
            var owned = ok;
            defer owned.deinit(std.testing.allocator);
            try std.testing.expectEqual(@as(usize, 2), owned.function_sigs.len);
            for (owned.function_sigs[0].reg_ids) |reg_id| {
                const name = owned.symbols.lookupName(reg_id) orelse "";
                try std.testing.expect(!std.mem.eql(u8, name, "out_len"));
            }
        },
        .trap => |report| {
            std.debug.print("trap={s} msg={s} line={} source_line={} source={s} register={s}\n", .{
                @tagName(report.trap),
                report.message,
                report.line,
                report.source_line,
                report.source_text orelse "",
                report.register orelse "",
            });
            return error.TestUnexpectedResult;
        },
    }
}

test "verifier rejects call-site capability prefix mismatches" {
    const source =
        \\@extern sink(&p: ptr, ^q: ptr) -> i32
        \\@main() -> i32:
        \\left = alloc 8
        \\right = alloc 8
        \\value = call @sink(^left, ^right)
        \\!left
        \\return value
    ;
    var flat = try @import("../flattener.zig").flatten(std.testing.allocator, source);
    defer flat.deinit(std.testing.allocator);

    const verified = try verify(std.testing.allocator, flat.instructions, flat.const_decls);
    switch (verified) {
        .trap => |report| try std.testing.expectEqual(trap.Trap.capability_mismatch, report.trap),
        .ok => return error.TestUnexpectedResult,
    }
}

test "verifier preserves by-value ptr fallible extern capability across metadata" {
    const source =
        \\@extern free_like(buffer: ptr) -> i32!
        \\@extern consume_later(^owned: ptr) -> i32
        \\@helper(value: i32) -> i32:
        \\return value
        \\@main() -> i32:
        \\buffer = alloc 8
        \\result = call @free_like(buffer)
        \\!result
        \\!buffer
        \\return 0
    ;
    var flat = try @import("../flattener.zig").flatten(std.testing.allocator, source);
    defer flat.deinit(std.testing.allocator);

    const verified = try verify(std.testing.allocator, flat.instructions, flat.const_decls);
    switch (verified) {
        .trap => |report| {
            std.debug.print("trap={s} msg={s} source={s}\n", .{
                @tagName(report.trap),
                report.message,
                report.source_text orelse "",
            });
            return error.TestUnexpectedResult;
        },
        .ok => |ok| {
            var owned = ok;
            defer owned.deinit(std.testing.allocator);
            const free_like_sig = for (owned.function_sigs) |item| {
                if (std.mem.eql(u8, item.name, "free_like")) break item;
            } else return error.TestUnexpectedResult;
            try std.testing.expectEqual(@as(usize, 1), free_like_sig.params.len);
            try std.testing.expectEqual(inst.CapPrefix.by_value, free_like_sig.params[0].cap);
            try std.testing.expectEqual(sig.PrimType.ptr, free_like_sig.params[0].ty);
            try std.testing.expect(free_like_sig.return_fallible);
        },
    }
}

pub fn packageSourceHashForIdentity(instructions: []const inst.Instruction, identity: []const u8) ?[32]u8 {
    for (instructions) |item| {
        if (item.package_identity) |item_identity| {
            if (std.mem.eql(u8, item_identity, identity)) {
                if (item.package_source_sha256) |hash| return hash;
            }
        }
    }
    return null;
}

pub fn makePackageGrant(
    allocator: std.mem.Allocator,
    url: []const u8,
    ref: []const u8,
    source_sha256: [32]u8,
    grants: []const pkg_manifest.Capability,
) !pkg_manifest.RequireEntry {
    return .{
        .url = try allocator.dupe(u8, url),
        .ref = try allocator.dupe(u8, ref),
        .source_sha256 = source_sha256,
        .grants = try allocator.dupe(pkg_manifest.Capability, grants),
        .upstream_loc = .{ .file = try allocator.dupe(u8, "sa.mod"), .line = 1, .col = 1 },
    };
}

pub fn verifyPackageIntrinsicProgram(
    allocator: std.mem.Allocator,
    package_body: []const u8,
    grant_caps: []const pkg_manifest.Capability,
    mismatch_hash: bool,
) !VerifyResult {
    const root_source = "@import \"github.com/example/pkg\"\n";

    var tmp = std.testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();
    var tdir: sio.Dir = .{ .inner = tmp.dir };

    try tdir.makePath("sa_vendor/github.com/example/pkg");

    var pkg_main = try tdir.createFile("sa_vendor/github.com/example/pkg/index.sa", .{ .truncate = true });
    try pkg_main.writeAll(package_body);
    pkg_main.close();

    var main_file = try tdir.createFile("main.sa", .{ .truncate = true });
    try main_file.writeAll(root_source);
    main_file.close();

    const source_text = try tdir.readFileAlloc(allocator, "main.sa", 4096);
    defer allocator.free(source_text);

    const path = try tdir.realpathAlloc(allocator, "main.sa");
    defer allocator.free(path);
    const project_root = try tdir.realpathAlloc(allocator, ".");
    defer allocator.free(project_root);

    var flat = try @import("../flattener.zig").flattenFileWithPackages(
        allocator,
        path,
        source_text,
        .{
            .options = .{ .project_root = project_root },
        },
    );
    defer flat.deinit(allocator);

    const package_hash = packageSourceHashForIdentity(flat.instructions, "github.com/example/pkg") orelse return error.TestUnexpectedResult;
    var grant_hash = package_hash;
    if (mismatch_hash) {
        grant_hash[0] ^= 0xFF;
    }

    var grants = [_]pkg_manifest.RequireEntry{
        try makePackageGrant(allocator, "github.com/example/pkg", "main", grant_hash, grant_caps),
    };
    defer grants[0].deinit(allocator);

    return try verifyWithOptions(allocator, flat.instructions, flat.const_decls, .{ .package_grants = grants[0..] });
}

test "verifier rejects ungranted sys file write for package instructions" {
    const result = try verifyPackageIntrinsicProgram(std.testing.allocator,
        \\@main() -> i32:
        \\L_ENTRY:
        \\path = alloc 8
        \\data = alloc 8
        \\value = call @sys_write_file(*path, 4, *data, 4)
        \\!path
        \\!data
        \\return value
    , &.{}, false);
    switch (result) {
        .trap => |report| try std.testing.expectEqual(trap.Trap.unauthorized_primitive, report.trap),
        .ok => return error.TestUnexpectedResult,
    }
}

test "verifier allows granted sys file write for package instructions" {
    const result = try verifyPackageIntrinsicProgram(std.testing.allocator,
        \\@main() -> i32:
        \\L_ENTRY:
        \\path = alloc 8
        \\data = alloc 8
        \\value = call @sys_write_file(*path, 4, *data, 4)
        \\!path
        \\!data
        \\return value
    , &.{.io_write}, false);
    switch (result) {
        .trap => return error.TestUnexpectedResult,
        .ok => |ok| {
            var owned = ok;
            defer owned.deinit(std.testing.allocator);
            try std.testing.expect(owned.annotated.len > 0);
        },
    }
}

test "verifier allows granted sys print for package instructions" {
    const result = try verifyPackageIntrinsicProgram(std.testing.allocator,
        \\@main() -> i32:
        \\L_ENTRY:
        \\msg = alloc 8
        \\call @sys_print(*msg, 5)
        \\!msg
        \\return 0
    , &.{.io_write}, false);
    switch (result) {
        .trap => return error.TestUnexpectedResult,
        .ok => |ok| {
            var owned = ok;
            defer owned.deinit(std.testing.allocator);
            try std.testing.expect(owned.annotated.len > 0);
        },
    }
}

test "verifier allows granted sys exit for package instructions" {
    const result = try verifyPackageIntrinsicProgram(std.testing.allocator,
        \\@main() -> i32:
        \\L_ENTRY:
        \\code = call @sys_exit(0)
        \\return code
    , &.{.proc_exit}, false);
    switch (result) {
        .trap => return error.TestUnexpectedResult,
        .ok => |ok| {
            var owned = ok;
            defer owned.deinit(std.testing.allocator);
            try std.testing.expect(owned.annotated.len > 0);
        },
    }
}

test "verifier allows granted sys argc for package instructions" {
    const result = try verifyPackageIntrinsicProgram(std.testing.allocator,
        \\@main() -> i32:
        \\L_ENTRY:
        \\argc = call @sys_argc()
        \\return argc
    , &.{.proc_args}, false);
    switch (result) {
        .trap => return error.TestUnexpectedResult,
        .ok => |ok| {
            var owned = ok;
            defer owned.deinit(std.testing.allocator);
            try std.testing.expect(owned.annotated.len > 0);
        },
    }
}

test "verifier allows granted sys argv for package instructions" {
    const result = try verifyPackageIntrinsicProgram(std.testing.allocator,
        \\@main() -> i32:
        \\L_ENTRY:
        \\argv = call @sys_argv(0)
        \\return 0
    , &.{.proc_args}, false);
    switch (result) {
        .trap => return error.TestUnexpectedResult,
        .ok => |ok| {
            var owned = ok;
            defer owned.deinit(std.testing.allocator);
            try std.testing.expect(owned.annotated.len > 0);
        },
    }
}

test "verifier rejects package source hash mismatch for granted sys write" {
    const result = try verifyPackageIntrinsicProgram(std.testing.allocator,
        \\@main() -> i32:
        \\L_ENTRY:
        \\path = alloc 8
        \\data = alloc 8
        \\value = call @sys_write_file(*path, 4, *data, 4)
        \\!path
        \\!data
        \\return value
    , &.{.io_write}, true);
    switch (result) {
        .trap => |report| try std.testing.expectEqual(trap.Trap.upstream_sha_mismatch, report.trap),
        .ok => return error.TestUnexpectedResult,
    }
}

test "verifier call contract PBT traps on random prefix mismatches" {
    var prng = std.Random.DefaultPrng.init(0x5A5A_6121);
    const random = prng.random();
    const caps = [_]struct { text: []const u8, prefix: inst.CapPrefix }{
        .{ .text = "", .prefix = .by_value },
        .{ .text = "&", .prefix = .borrow },
        .{ .text = "^", .prefix = .move },
    };

    for (0..48) |iter| {
        const expected = if (random.boolean()) caps[1] else caps[2];
        var actual = caps[random.intRangeLessThan(usize, 0, caps.len)];
        if (actual.prefix == expected.prefix) {
            actual = caps[(random.intRangeLessThan(usize, 1, caps.len) + @intFromEnum(expected.prefix)) % caps.len];
            if (actual.prefix == expected.prefix) actual = caps[(@intFromEnum(expected.prefix) + 1) % caps.len];
        }

        const source = try std.fmt.allocPrint(std.testing.allocator,
            \\@extern sink({s}p: ptr) -> i32
            \\@main() -> i32:
            \\value = alloc 8
            \\ret = call @sink({s}value)
            \\!value
            \\return ret
        , .{ expected.text, actual.text });
        defer std.testing.allocator.free(source);

        var flat = try @import("../flattener.zig").flatten(std.testing.allocator, source);
        defer flat.deinit(std.testing.allocator);

        const verified = try verify(std.testing.allocator, flat.instructions, flat.const_decls);
        switch (verified) {
            .trap => |report| try std.testing.expectEqual(trap.Trap.capability_mismatch, report.trap),
            .ok => {
                _ = iter;
                return error.TestUnexpectedResult;
            },
        }
    }
}
