const std = @import("std");
const sa_std = @import("../sa_std.zig");
const is_linux = @import("../sa_std.zig").is_linux;
const is_wasm = @import("../sa_std.zig").is_wasm;
const lxWrite = @import("../sa_std.zig").lxWrite;
const policyEnvOwned = @import("../sa_std.zig").policyEnvOwned;
const sa_policy = @import("../sa_std.zig").sa_policy;
const sio = @import("../sa_std.zig").sio;

var policy_context_storage: ?*sa_policy.PolicyContext = null;

fn policyBootstrapWriteStderr(text: []const u8) void {
    _ = lxWrite(2, text) catch {};
}

fn policyAuditSink(line: []const u8) void {
    const fd = policy_audit_fd orelse return;
    _ = lxWrite(fd, line) catch {};
}

fn policyBootstrapFail(message: []const u8, code: u8) noreturn {
    policyBootstrapWriteStderr("[sa-policy] ");
    policyBootstrapWriteStderr(message);
    policyBootstrapWriteStderr("\n");
    std.process.exit(code);
}

fn policyEnvFlag(allocator: std.mem.Allocator, name: []const u8) bool {
    const value = policyEnvOwned(allocator, name) orelse return false;
    defer allocator.free(value);
    return std.mem.eql(u8, value, "1");
}

fn installPolicyText(allocator: std.mem.Allocator, text: []const u8) void {
    const policy = sa_policy.parsePolicyJson(allocator, text) catch |err|
        policyBootstrapFail(@errorName(err), 2);

    var audit_path: ?[]u8 = policyEnvOwned(allocator, "SA_AUDIT_FILE");
    if (audit_path == null) {
        if (policy.audit_sink) |sink| {
            if (std.mem.startsWith(u8, sink, "file://")) {
                audit_path = allocator.dupe(u8, sink["file://".len..]) catch null;
            }
        }
    }
    if (audit_path) |path| {
        defer allocator.free(path);
        var open_flags: std.posix.O = .{};
        // WASI's O struct has no ACCMODE/APPEND fields (access mode and
        // append live in fd rights/fdflags there); std.posix.openat maps
        // what exists. Audit-sink open stays best-effort on every target.
        if (comptime !is_wasm) {
            open_flags.ACCMODE = .WRONLY;
            open_flags.APPEND = true;
        }
        open_flags.CREAT = true;
        if (std.posix.openat(std.posix.AT.FDCWD, path, open_flags, @as(std.posix.mode_t, 0o644))) |fd| {
            policy_audit_fd = fd;
            sa_policy.installAuditSink(policyAuditSink);
        } else |_| {}
    }

    const context = allocator.create(sa_policy.PolicyContext) catch
        policyBootstrapFail("out of memory", 2);
    context.* = sa_policy.PolicyContext.init(allocator, 1, policy);
    policy_context_storage = context;
    sa_policy.installContext(context);

    // One-time tokens delivered by the launcher (16_policy phase 1):
    // the host mints them after approval and hands them over through
    // SA_POLICY_TOKENS_JSON; they are minted into the root context
    // here, before main runs.
    if (policyEnvOwned(allocator, "SA_POLICY_TOKENS_JSON")) |tokens_text| {
        defer allocator.free(tokens_text);
        const specs = sa_policy.parseTokenSpecsJson(allocator, tokens_text) catch |err|
            policyBootstrapFail(@errorName(err), 2);
        defer sa_policy.freeTokenSpecs(allocator, specs);
        const now_ns: i64 = @intCast(std.Io.Clock.awake.now(sio.io()).toNanoseconds());
        sa_policy.mintTokenSpecs(context, allocator, specs, now_ns) catch
            policyBootstrapFail("out of memory", 2);
    }
}

var policy_bootstrap_attempted: bool = false;

var sigpipe_ignore_installed: bool = false;

pub fn applySigpipeIgnore() void {
    // NOTE: do NOT gate this on @hasDecl(std.posix.SIG, "PIPE") —
    // that is false on this Zig version (PIPE is an enum member, not
    // a declaration), which is exactly why the http server's earlier
    // attempt at this install (sa_http_server.zig) never took effect.
    if (comptime !is_linux) return;
    const act: std.posix.Sigaction = .{
        .handler = .{ .handler = std.posix.SIG.IGN },
        .mask = std.posix.sigemptyset(),
        .flags = 0,
    };
    std.posix.sigaction(std.posix.SIG.PIPE, &act, null);
}

fn installSigpipeIgnore() void {
    if (sigpipe_ignore_installed) return;
    sigpipe_ignore_installed = true;
    applySigpipeIgnore();
}

pub export fn sa_install_sigpipe_ignore() void {
    installSigpipeIgnore();
}

fn policyBootstrap() callconv(.c) void {
    installSigpipeIgnore();
    if (policy_bootstrap_attempted) return;
    policy_bootstrap_attempted = true;
    const allocator = std.heap.page_allocator;

    if (policyEnvFlag(allocator, "SA_POLICY_ALLOW_ALL")) {
        installPolicyText(allocator, "{\"permissions\":{\"net\":{\"mode\":\"allow\"},\"fs\":{\"mode\":\"allow\"},\"env\":{\"mode\":\"allow\"},\"run\":{\"mode\":\"allow\"},\"time\":{\"mode\":\"allow\"},\"random\":{\"mode\":\"allow\"}}}");
        policyBootstrapWriteStderr("[sa-policy] allow-all policy engaged via SA_POLICY_ALLOW_ALL (audit trace)\n");
        if (policy_audit_fd != null) {
            const now_ns: i64 = @intCast(std.Io.Clock.awake.now(sio.io()).toNanoseconds());
            const event = sa_policy.AuditEvent{ .context_id = 1, .category = .run, .resource = "SA_POLICY_ALLOW_ALL", .decision = "allow-all", .source = "env" };
            if (event.formatJsonLine(allocator, now_ns)) |line| {
                defer allocator.free(line);
                policyAuditSink(line);
            } else |_| {}
        }
        return;
    }

    if (policyEnvOwned(allocator, "SA_POLICY_JSON")) |json_text| {
        defer allocator.free(json_text);
        installPolicyText(allocator, json_text);
        return;
    }

    if (policyEnvOwned(allocator, "SA_POLICY_FILE")) |path| {
        defer allocator.free(path);
        var file = sio.cwd().openFile(path, .{}) catch
            policyBootstrapFail("SA_POLICY_FILE is set but cannot be opened", 2);
        defer file.close();
        const text = file.readToEndAlloc(allocator, 1 << 20) catch
            policyBootstrapFail("SA_POLICY_FILE cannot be read", 2);
        defer allocator.free(text);
        installPolicyText(allocator, text);
        return;
    }

    if (policyEnvFlag(allocator, "SA_POLICY_REQUIRED")) {
        policyBootstrapFail("SA_POLICY_REQUIRED is set but no policy was provided (set SA_POLICY_JSON, SA_POLICY_FILE, or SA_POLICY_ALLOW_ALL=1)", 1);
    }

    if (policyEnvOwned(allocator, "SA_POLICY_TOKENS_JSON")) |tokens_text| {
        allocator.free(tokens_text);
        policyBootstrapFail("SA_POLICY_TOKENS_JSON is set but no policy was provided (tokens need a policy context to bind to)", 1);
    }
}

var policy_bootstrap_init_entry: *const fn () callconv(.c) void align(8) linksection(".init_array") = &policyBootstrap;
