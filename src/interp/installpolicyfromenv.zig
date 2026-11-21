const std = @import("std");
const referee = @import("../referee.zig");
const sio = @import("sio");
const sa_policy = @import("../runtime/sa_policy.zig");
const Interpreter = @import("interpreter.zig").Interpreter;
const RegValue = @import("memory.zig").RegValue;
const RunError = @import("memory.zig").RunError;
const runPrepared = @import("memory.zig").runPrepared;


pub fn runFunctionAtIndexWithBinaryArgs(
    allocator: std.mem.Allocator,
    program: *const referee.VerifyOk,
    sig_index: usize,
    arg_blob: []const u8,
    stdout: *std.Io.Writer,
    stderr: *std.Io.Writer,
) !u8 {
    if (program.function_sigs.len == 0) return 0;
    if (sig_index >= program.function_sigs.len) return RunError.InvalidFunction;

    var interp = try Interpreter.init(allocator, program, &.{}, stdout, stderr);
    defer interp.deinit();

    const args = try interp.decodeBinaryArgs(sig_index, arg_blob);
    defer allocator.free(args);

    return try runPrepared(&interp, sig_index, args);
}


// ---------------------------------------------------------------------
// Runtime policy for interpreted runs (16_policy phase 1, slice 3b).
// Mirrors the produced-binary bootstrap (sa_std.zig policyBootstrap):
// SA_POLICY_ALLOW_ALL > SA_POLICY_JSON > SA_POLICY_FILE, and
// SA_POLICY_REQUIRED refuses to run without a policy. The interpreter's
// gated surface is its intrinsic table: sys_read_file / sys_write_file
// and the five clock getters. Denied fs access aborts the run with
// RunError.PolicyDenied (the sys intrinsics have no status channel);
// denied clock reads return 0, like the native status-less getters.

var run_audit_path: ?[]const u8 = null;

fn runPolicyAuditSink(line: []const u8) void {
    const path = run_audit_path orelse return;
    const file = sio.cwd().createFile(path, .{ .truncate = false }) catch return;
    defer file.close();
    const end = file.getEndPos() catch return;
    file.seekTo(end) catch return;
    file.writeAll(line) catch {};
}

fn policyEnvOwned(allocator: std.mem.Allocator, name: []const u8) ?[]u8 {
    return sio.getEnvVarOwned(allocator, name) catch null;
}

fn policyEnvFlag(allocator: std.mem.Allocator, name: []const u8) bool {
    const value = policyEnvOwned(allocator, name) orelse return false;
    defer allocator.free(value);
    return std.mem.eql(u8, value, "1");
}

fn installRunPolicy(allocator: std.mem.Allocator, policy: sa_policy.Policy) !void {
    const context = try allocator.create(sa_policy.PolicyContext);
    context.* = sa_policy.PolicyContext.init(allocator, 1, policy);
    sa_policy.installContext(context);
    var audit_path: ?[]u8 = policyEnvOwned(allocator, "SA_AUDIT_FILE");
    if (audit_path == null) {
        if (policy.audit_sink) |sink| {
            if (std.mem.startsWith(u8, sink, "file://")) {
                audit_path = try allocator.dupe(u8, sink["file://".len..]);
            }
        }
    }
    if (audit_path) |path| {
        run_audit_path = path;
        sa_policy.installAuditSink(runPolicyAuditSink);
    }
}

fn installParsedPolicy(allocator: std.mem.Allocator, stderr: anytype, text: []const u8) !void {
    const policy = sa_policy.parsePolicyJson(allocator, text) catch |err| {
        stderr.print("[sa-policy] {s}\n", .{@errorName(err)}) catch {};
        return error.InvalidPolicy;
    };
    installRunPolicy(allocator, policy) catch return error.OutOfMemory;
}

/// Mints SA_POLICY_TOKENS_JSON specs into the installed context
/// (parity with the produced-binary bootstrap in sa_std.zig).
fn mintEnvTokens(allocator: std.mem.Allocator, stderr: anytype) !void {
    const text = policyEnvOwned(allocator, "SA_POLICY_TOKENS_JSON") orelse return;
    defer allocator.free(text);
    const context = sa_policy.active_context orelse {
        stderr.writeAll("[sa-policy] SA_POLICY_TOKENS_JSON is set but no policy was provided (tokens need a policy context to bind to)\n") catch {};
        return error.PolicyTokensWithoutPolicy;
    };
    const specs = sa_policy.parseTokenSpecsJson(allocator, text) catch |err| {
        stderr.print("[sa-policy] {s}\n", .{@errorName(err)}) catch {};
        return error.InvalidPolicy;
    };
    defer sa_policy.freeTokenSpecs(allocator, specs);
    const now_ns: i64 = @intCast(std.Io.Clock.awake.now(sio.io()).toNanoseconds());
    sa_policy.mintTokenSpecs(context, allocator, specs, now_ns) catch return error.OutOfMemory;
}

pub fn installPolicyFromEnv(allocator: std.mem.Allocator, stderr: anytype) !void {
    if (policyEnvFlag(allocator, "SA_POLICY_ALLOW_ALL")) {
        try installParsedPolicy(allocator, stderr, "{\"permissions\":{\"net\":{\"mode\":\"allow\"},\"fs\":{\"mode\":\"allow\"},\"env\":{\"mode\":\"allow\"},\"run\":{\"mode\":\"allow\"},\"time\":{\"mode\":\"allow\"},\"random\":{\"mode\":\"allow\"}}}");
        stderr.writeAll("[sa-policy] allow-all policy engaged via SA_POLICY_ALLOW_ALL (audit trace)\n") catch {};
        if (run_audit_path != null) {
            const now_ns: i64 = @intCast(std.Io.Clock.awake.now(sio.io()).toNanoseconds());
            const event = sa_policy.AuditEvent{ .context_id = 1, .category = .run, .resource = "SA_POLICY_ALLOW_ALL", .decision = "allow-all", .source = "env" };
            if (event.formatJsonLine(allocator, now_ns)) |line| {
                defer allocator.free(line);
                runPolicyAuditSink(line);
            } else |_| {}
        }
        try mintEnvTokens(allocator, stderr);
        return;
    }
    if (policyEnvOwned(allocator, "SA_POLICY_JSON")) |text| {
        defer allocator.free(text);
        try installParsedPolicy(allocator, stderr, text);
        try mintEnvTokens(allocator, stderr);
        return;
    }
    if (policyEnvOwned(allocator, "SA_POLICY_FILE")) |path| {
        defer allocator.free(path);
        var file = sio.cwd().openFile(path, .{}) catch {
            stderr.writeAll("[sa-policy] SA_POLICY_FILE is set but cannot be opened\n") catch {};
            return error.PolicyFileUnreadable;
        };
        defer file.close();
        const text = file.readToEndAlloc(allocator, 1 << 20) catch {
            stderr.writeAll("[sa-policy] SA_POLICY_FILE cannot be read\n") catch {};
            return error.PolicyFileUnreadable;
        };
        defer allocator.free(text);
        try installParsedPolicy(allocator, stderr, text);
        try mintEnvTokens(allocator, stderr);
        return;
    }
    if (policyEnvFlag(allocator, "SA_POLICY_REQUIRED")) {
        stderr.writeAll("[sa-policy] SA_POLICY_REQUIRED is set but no policy was provided (set SA_POLICY_JSON, SA_POLICY_FILE, or SA_POLICY_ALLOW_ALL=1)\n") catch {};
        return error.PolicyRequired;
    }
    if (policyEnvOwned(allocator, "SA_POLICY_TOKENS_JSON")) |text| {
        allocator.free(text);
        stderr.writeAll("[sa-policy] SA_POLICY_TOKENS_JSON is set but no policy was provided (tokens need a policy context to bind to)\n") catch {};
        return error.PolicyTokensWithoutPolicy;
    }
}

pub fn policyGateAllows(allocator: std.mem.Allocator, resource: sa_policy.Resource) bool {
    if (sa_policy.active_context == null) return true;
    const now_ns: i64 = @intCast(std.Io.Clock.awake.now(sio.io()).toNanoseconds());
    return sa_policy.gate(allocator, resource, now_ns);
}

pub fn runWithWriters(
    allocator: std.mem.Allocator,
    program: *const referee.VerifyOk,
    argv: []const []const u8,
    stdout: *std.Io.Writer,
    stderr: *std.Io.Writer,
) !u8 {
    const main_index = blk: {
        for (program.function_sigs, 0..) |fsig, idx| {
            if (fsig.kind == .normal and std.mem.eql(u8, fsig.name, "main")) break :blk idx;
        }
        if (program.function_sigs.len != 0) break :blk @as(usize, 0);
        return 0;
    };

    var interp = try Interpreter.init(allocator, program, argv, stdout, stderr);
    defer interp.deinit();

    const args = try allocator.alloc(RegValue, 0);
    defer allocator.free(args);

    return try runPrepared(&interp, main_index, args);
}

pub fn run(
    allocator: std.mem.Allocator,
    program: *const referee.VerifyOk,
    argv: []const []const u8,
) !u8 {
    // NOTE(Zig 0.17): writers are caller-buffered now; flush before return.
    var out_buf: [8192]u8 = undefined;
    var out_writer = sio.getStdOut().writer(&out_buf);
    var err_buf: [8192]u8 = undefined;
    var err_writer = sio.getStdErr().writer(&err_buf);
    defer out_writer.interface.flush() catch {};
    defer err_writer.interface.flush() catch {};
    return runWithWriters(
        allocator,
        program,
        argv,
        &out_writer.interface,
        &err_writer.interface,
    );
}

test "interpreter exports" {
    _ = run;
}
