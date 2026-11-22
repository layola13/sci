const std = @import("std");
const sa_std = @import("../sa_std.zig");
pub const AFT = @import("../sa_std.zig").AFT;
pub const JsonWriterHandle = @import("../sa_std.zig").JsonWriterHandle;
pub const NetAddress = @import("../sa_std.zig").NetAddress;
const NetAddressList = @import("../sa_std.zig").NetAddressList;
const SA_STD_ERR_ACCESS = @import("consts.zig").SA_STD_ERR_ACCESS;
pub const SA_STD_ERR_ALREADY_EXISTS = @import("consts.zig").SA_STD_ERR_ALREADY_EXISTS;
pub const SA_STD_ERR_INVALID_ARGUMENT = @import("consts.zig").SA_STD_ERR_INVALID_ARGUMENT;
const SA_STD_ERR_INVALID_HANDLE = @import("consts.zig").SA_STD_ERR_INVALID_HANDLE;
pub const SA_STD_ERR_IO = @import("consts.zig").SA_STD_ERR_IO;
const SA_STD_ERR_NET = @import("../sa_std.zig").SA_STD_ERR_NET;
const SA_STD_ERR_NOT_FOUND = @import("consts.zig").SA_STD_ERR_NOT_FOUND;
const SA_STD_ERR_NO_MEMORY = @import("consts.zig").SA_STD_ERR_NO_MEMORY;
pub const SA_STD_ERR_PERMISSION_DENIED = @import("consts.zig").SA_STD_ERR_PERMISSION_DENIED;
pub const SA_STD_ERR_TRUNCATED = @import("consts.zig").SA_STD_ERR_TRUNCATED;
pub const SA_STD_ERR_UNSUPPORTED = @import("consts.zig").SA_STD_ERR_UNSUPPORTED;
pub const SA_STD_OK = @import("consts.zig").SA_STD_OK;
pub const TimeDate = @import("../sa_std.zig").TimeDate;
pub const addressHostText = @import("../sa_std.zig").addressHostText;
const builtin = @import("../sa_std.zig").builtin;
pub const constBytes = @import("../sa_std.zig").constBytes;
pub const finish = @import("../sa_std.zig").finish;
pub const finishErr = @import("../sa_std.zig").finishErr;
const getResourceLocked = @import("../sa_std.zig").getResourceLocked;
pub const lenAsUsize = @import("../sa_std.zig").lenAsUsize;
const lxKill = @import("../sa_std.zig").lxKill;
const policy = @import("../sa_std.zig").policy;
const sa_time_unix_ns = @import("time.zig").sa_time_unix_ns;
pub const sa_unicode_normalize = @import("../sa_std.zig").sa_unicode_normalize;
const sio = @import("../sa_std.zig").sio;
const writeHexLower = @import("../sa_std.zig").writeHexLower;
extern fn unorm2_getNFCInstance_74(err: *c_int) ?*anyopaque;
extern fn unorm2_getNFDInstance_74(err: *c_int) ?*anyopaque;
extern fn unorm2_getNFKCInstance_74(err: *c_int) ?*anyopaque;
extern fn unorm2_getNFKDInstance_74(err: *c_int) ?*anyopaque;

const Ipv6MreqC = extern struct {
    ipv6mr_multiaddr: [16]u8,
    ipv6mr_interface: u32,
};

pub fn addressSocketText(allocator: std.mem.Allocator, address: NetAddress) ![]u8 {
    return switch (address.storage.family) {
        AFT.INET, AFT.INET6 => blk: {
            const host = try addressHostText(allocator, address);
            defer allocator.free(host);
            if (address.storage.family == AFT.INET6) {
                break :blk try std.fmt.allocPrint(allocator, "[{s}]:{d}", .{ host, address.getPort() });
            }
            break :blk try std.fmt.allocPrint(allocator, "{s}:{d}", .{ host, address.getPort() });
        },
        else => try addressHostText(allocator, address),
    };
}

// Resolves the handle's slot under the registry lock for an in-place tree
// mutation. The caller must hold no other registry acquisition.

pub fn acquireJsonWriterForWrite(writer: u64) !*JsonWriterHandle {
    const resource = getResourceLocked(writer) orelse return error.InvalidHandle;
    const writer_handle = switch (resource.*) {
        .json_writer => |handle| handle,
        else => return error.InvalidHandle,
    };
    if (writer_handle.result_buffer != null) return error.InvalidHandle;
    if (writer_handle.root_value_complete and writer_handle.open_depth == 0) return error.InvalidArgument;
    return writer_handle;
}

pub const SaProcessArgv = extern struct {
    data: [*]const u8,
    len: u64,
};

pub fn mapError(err: anyerror) i32 {
    return switch (err) {
        error.InvalidArgument => SA_STD_ERR_INVALID_ARGUMENT,
        error.InvalidHandle => SA_STD_ERR_INVALID_HANDLE,
        error.OutOfMemory => SA_STD_ERR_NO_MEMORY,
        error.PathAlreadyExists => SA_STD_ERR_ALREADY_EXISTS,
        error.FileNotFound => SA_STD_ERR_NOT_FOUND,
        error.AccessDenied, error.PermissionDenied => SA_STD_ERR_ACCESS,
        error.WouldBlock => SA_STD_ERR_IO,
        error.NotATerminal, error.ProcessOrphaned => SA_STD_ERR_UNSUPPORTED,
        error.FileDescriptorAlreadyPresentInSet, error.OperationCausesCircularLoop => SA_STD_ERR_INVALID_ARGUMENT,
        error.FileDescriptorNotRegistered => SA_STD_ERR_INVALID_HANDLE,
        error.FileDescriptorIncompatibleWithEpoll => SA_STD_ERR_UNSUPPORTED,
        error.SyntaxError,
        error.UnexpectedEndOfInput,
        error.UnexpectedToken,
        error.InvalidNumber,
        error.DuplicateField,
        error.UnknownField,
        error.MissingField,
        error.LengthMismatch,
        error.InvalidEnumTag,
        error.ValueTooLong,
        error.BufferUnderrun,
        => SA_STD_ERR_INVALID_ARGUMENT,
        error.PolicyDenied => SA_STD_ERR_PERMISSION_DENIED,
        error.AlreadyConnected,
        error.ConnectionPending,
        error.SocketNotConnected,
        error.UnreachableAddress,
        error.NetworkSubsystemFailed,
        => SA_STD_ERR_NET,
        error.MessageTooBig, error.NoSpaceLeft => SA_STD_ERR_TRUNCATED,
        error.Unsupported, error.SystemResources, error.ProcessFdQuotaExceeded, error.SystemFdQuotaExceeded => SA_STD_ERR_UNSUPPORTED,
        error.ProcessNotFound, error.AlreadyTerminated => SA_STD_ERR_INVALID_HANDLE,
        error.NameTooLong,
        error.BadPathName,
        error.InvalidUtf8,
        error.InvalidWtf8,
        error.NotDir,
        error.IsDir,
        error.InvalidIPAddressFormat,
        error.InvalidCharacter,
        error.InvalidEnd,
        error.Incomplete,
        error.NonCanonical,
        error.InvalidIpv4Mapping,
        error.Overflow,
        => SA_STD_ERR_INVALID_ARGUMENT,
        error.RegexInvalidArgument,
        error.RegexNoMatch,
        error.RegexBadPattern,
        error.RegexOutOfMemory,
        error.UnknownHostName,
        error.TemporaryNameServerFailure,
        error.NameServerFailure,
        error.NetworkUnreachable,
        error.ConnectionRefused,
        error.ConnectionResetByPeer,
        error.ConnectionTimedOut,
        error.AddressInUse,
        error.AddressNotAvailable,
        error.HostLacksNetworkAddresses,
        error.ServiceUnavailable,
        => SA_STD_ERR_NET,
        else => SA_STD_ERR_IO,
    };
}

pub fn fillUtcNow(out: *TimeDate) !void {
    const now_ts = std.Io.Clock.real.now(sio.io());
    const unix_ms = now_ts.toMilliseconds();
    const unix_s = @divFloor(unix_ms, std.time.ms_per_s);
    if (unix_s < 0) return error.Unsupported;

    const unix_ns_raw = now_ts.toNanoseconds();
    const unix_ns = std.math.cast(i64, unix_ns_raw) orelse return error.Overflow;
    const epoch_seconds = std.time.epoch.EpochSeconds{ .secs = @as(u64, @intCast(unix_s)) };
    const epoch_day = epoch_seconds.getEpochDay();
    const year_day = epoch_day.calculateYearDay();
    const month_day = year_day.calculateMonthDay();
    const day_seconds = epoch_seconds.getDaySeconds();

    out.* = .{
        .unix_ms = unix_ms,
        .unix_ns = unix_ns,
        .year = year_day.year,
        .month = @backingInt(month_day.month),
        .day = @as(u8, @intCast(month_day.day_index + 1)),
        .hour = day_seconds.getHoursIntoDay(),
        .minute = day_seconds.getMinutesIntoHour(),
        .second = day_seconds.getSecondsIntoMinute(),
        .millisecond = @as(u16, @intCast(@mod(unix_ms, std.time.ms_per_s))),
    };
}

pub fn monotonicNowNs() !u64 {
    // Raw monotonic-clock reading (ns since boot), the same contract
    // sa_time_unix_ns already uses for the wall clock: callers diff two
    // readings, and a reading of 0 is reserved for policy denial or
    // clock failure. (The previous origin-relative form returned
    // exactly 0 to the first caller in every process, which read as a
    // dead clock on every surface exposing the raw value:
    // Instant::now().raw_ns(), timer_now_ns, sched_now_ns.)
    const now_ns: i128 = std.Io.Clock.awake.now(sio.io()).toNanoseconds();
    if (now_ns <= 0) return 0;
    if (now_ns > std.math.maxInt(u64)) return std.math.maxInt(u64);
    return @intCast(now_ns);
}

pub fn makeIpv6Membership(multicast_addr: NetAddress, interface_index: u32) Ipv6MreqC {
    return .{
        .ipv6mr_multiaddr = multicast_addr.in6AddrBytes(),
        .ipv6mr_interface = interface_index,
    };
}

pub fn applyRawMode(term: *std.posix.termios) void {
    term.iflag.IGNBRK = false;
    term.iflag.BRKINT = false;
    term.iflag.PARMRK = false;
    term.iflag.ISTRIP = false;
    term.iflag.INLCR = false;
    term.iflag.IGNCR = false;
    term.iflag.ICRNL = false;
    term.iflag.IXON = false;
    term.iflag.IXOFF = false;
    term.oflag.OPOST = false;
    term.cflag.CSIZE = .CS8;
    term.cflag.PARENB = false;
    term.cflag.CREAD = true;
    term.lflag.ISIG = false;
    term.lflag.ICANON = false;
    term.lflag.ECHO = false;
    term.lflag.IEXTEN = false;
    term.cc[@backingInt(std.posix.V.MIN)] = 1;
    term.cc[@backingInt(std.posix.V.TIME)] = 0;
}

// DEF-R5: the registry mutex guards the handle table only; it
// must never be held across a syscall that can block. The data
// path classifies a handle under the lock, snapshots the OS fd
// (or notes an in-memory kind), drops the lock, and only then
// performs the blocking read/write -- the same snapshot pattern
// sa_std_close and sa_std_net_tcp_accept already use in this
// file. Before this split, one goroutine parked in a blocking
// sa_std_read held the registry mutex for the whole wait, so
// every other goroutine's net IO (and every other registry
// user: poll_wait validation, writes, accepts, closes) stalled
// or spun behind it: with >= 2 goroutines blocked in net reads
// only the mutex holder was ever serviced, regardless of
// carrier count (slaredis registration A). In-memory kinds
// (.buffer/.process) never block and keep the locked path.

pub fn lockRegistry() void {
    while (!sa_std.registry_mutex.tryLock()) {
        std.Thread.yield() catch {};
    }
}

pub fn udpSocketFd(handle: u64) ?std.posix.fd_t {
    lockRegistry();
    defer sa_std.registry_mutex.unlock();
    const resource = getResourceLocked(handle) orelse return null;
    return switch (resource.*) {
        .udp_socket => |fd| fd,
        else => null,
    };
}

// Read once from a handle without holding the registry mutex
// across a blocking syscall (see the IoPlan note above).
/// Write to a handle without holding the registry mutex across
/// a blocking syscall. Per-kind semantics preserve the previous
/// locked implementation: fd writes are a single write(2),
/// while file writes write all bytes (sio.File.write is
/// writeAll).

fn statusFromTerm(term: sio.Child.Term) u32 {
    return switch (term) {
        .exited => |code| code,
        .signal => 128,
        .stopped => 130,
        .unknown => 127,
    };
}

fn argvFromBlob(allocator: std.mem.Allocator, blob: []const u8) ![]const []const u8 {
    var count: usize = 1;
    for (blob) |b| {
        if (b == 0) count += 1;
    }
    const args = try allocator.alloc([]const u8, count);
    errdefer allocator.free(args);

    var start: usize = 0;
    var index: usize = 0;
    while (start <= blob.len) {
        const end = std.mem.indexOfScalarPos(u8, blob, start, 0) orelse blob.len;
        if (end == start) {
            if (end == blob.len) break;
            start = end + 1;
            continue;
        }
        args[index] = blob[start..end];
        index += 1;
        if (end == blob.len) break;
        start = end + 1;
    }
    return args[0..index];
}

pub fn argvFromEntries(allocator: std.mem.Allocator, argv_ptr: ?[*]const SaProcessArgv, argv_len: u64) ![]const []const u8 {
    const count = try lenAsUsize(argv_len);
    if (count == 0) return error.InvalidArgument;
    const entries = argv_ptr orelse return error.InvalidArgument;
    const args = try allocator.alloc([]const u8, count);
    errdefer allocator.free(args);

    for (args, 0..) |*slot, index| {
        const entry = entries[index];
        const n = try lenAsUsize(entry.len);
        slot.* = if (n == 0) &.{} else entry.data[0..n];
    }
    return args;
}

pub fn waitStatusFromSiginfo(siginfo: std.posix.siginfo_t) u32 {
    if (comptime sa_std.is_wasm) return 0;
    const status = @as(u32, @intCast(siginfo.fields.common.second.sigchld.status));
    return switch (siginfo.code) {
        1 => (status & 0xff) << 8, // CLD_EXITED
        2 => status, // CLD_KILLED
        3 => status | 0x80, // CLD_DUMPED
        6 => 0xffff, // CLD_CONTINUED
        4, 5 => ((status & 0xff) << 8) | 0x7f, // CLD_TRAPPED / CLD_STOPPED
        else => 0,
    };
}

pub fn sendSignalToProcessGroup(pgid: std.posix.pid_t, signum: u8) !void {
    if (comptime sa_std.is_wasm) return error.Unsupported;
    const target: std.posix.pid_t = -pgid;
    var attempts: u8 = 0;
    while (true) : (attempts += 1) {
        lxKill(target, signum) catch |err| switch (err) {
            error.ProcessNotFound => {
                if (attempts >= 50) return err;
                sio.io().sleep(.fromNanoseconds(1 * std.time.ns_per_ms), .awake) catch {};
                continue;
            },
            else => return err,
        };
        return;
    }
}

fn errnoToSetupError(errno: std.posix.E) anyerror {
    return switch (errno) {
        .SUCCESS => unreachable,
        .INVAL => error.InvalidArgument,
        .PERM, .ACCES => error.PermissionDenied,
        .NOENT => error.FileNotFound,
        .NOMEM => error.OutOfMemory,
        .NOTDIR => error.NotDir,
        else => error.Unexpected,
    };
}

pub fn netGetAddressList(allocator: std.mem.Allocator, host: []const u8, port: u16) !NetAddressList {
    if (std.Io.net.IpAddress.parse(host, port)) |ip| {
        const addrs = try allocator.alloc(NetAddress, 1);
        addrs[0] = NetAddress.fromIp(ip);
        return .{ .addrs = addrs, .allocator = allocator };
    } else |_| {}
    const hn = try std.Io.net.HostName.init(host);
    var qbuf: [16]std.Io.net.HostName.LookupResult = undefined;
    var q = std.Io.Queue(std.Io.net.HostName.LookupResult).init(&qbuf);
    hn.lookup(sio.io(), &q, .{ .port = port }) catch |err| switch (err) {
        error.UnknownHostName => return error.UnknownHostName,
        else => return err,
    };
    q.close(sio.io());
    var out: std.array_list.Managed(NetAddress) = .init(allocator);
    errdefer out.deinit();
    var drain: [16]std.Io.net.HostName.LookupResult = undefined;
    while (true) {
        const n = q.get(sio.io(), &drain, 0) catch |err| switch (err) {
            error.Closed => break,
            else => return err,
        };
        if (n == 0) break;
        for (drain[0..n]) |r| {
            if (r == .address) try out.append(NetAddress.fromIp(r.address));
        }
    }
    if (out.items.len == 0) {
        out.deinit();
        return error.HostLacksNetworkAddresses;
    }
    return .{ .addrs = try out.toOwnedSlice(), .allocator = allocator };
}

pub fn processArgsJsonAlloc(allocator: std.mem.Allocator) ![]u8 {
    if (builtin.os.tag == .linux) {
        const file = sio.openFileAbsolute("/proc/self/cmdline", .{}) catch |err| switch (err) {
            error.FileNotFound, error.AccessDenied => null,
            else => return err,
        };
        if (file) |cmdline_file| {
            defer cmdline_file.close();
            const cmdline = try cmdline_file.readToEndAlloc(allocator, 1024 * 1024);
            defer allocator.free(cmdline);

            var args = std.array_list.Managed([]const u8).init(allocator);
            defer args.deinit();
            var it = std.mem.splitScalar(u8, cmdline, 0);
            while (it.next()) |arg| {
                if (arg.len == 0) continue;
                try args.append(arg);
            }
            return std.json.Stringify.valueAlloc(allocator, args.items, .{});
        }
    }

    const args = try sio.argsAlloc(allocator);
    defer sio.argsFree(allocator, args);
    return std.json.Stringify.valueAlloc(allocator, args, .{});
}

pub fn unicodeNormalizerForForm(form: i32) ?*anyopaque {
    var err: c_int = 0;
    const inst = switch (form) {
        0 => unorm2_getNFCInstance_74(&err),
        1 => unorm2_getNFDInstance_74(&err),
        2 => unorm2_getNFKCInstance_74(&err),
        3 => unorm2_getNFKDInstance_74(&err),
        else => @panic("sa_unicode_normalize: invalid form code"),
    };
    if (err > 0 or inst == null) @panic("sa_unicode_normalize: ICU instance failed");
    return inst;
}

/// Shared civil split: i64 unix millis to (days since epoch, millis
/// within day, Hinnant y/m/d, h/mi/s/ms). Negative inputs fold via
/// floored division; field order matches the getters below.

const CivilParts = struct {
    year: i64,
    month: i64,
    day: i64,
    hour: i64,
    minute: i64,
    second: i64,
    milli: i64,
    days: i64,
};

pub fn civilParts(ms: i64) CivilParts {
    const ms_per_day: i64 = 86400000;
    var days = @divFloor(ms, ms_per_day);
    var day_ms = @mod(ms, ms_per_day);
    if (day_ms < 0) {
        day_ms += ms_per_day;
        days -= 1;
    }
    const z: i64 = days + 719468;
    const era: i64 = if (z >= 0) @divFloor(z, 146097) else @divFloor(z - 146096, 146097);
    const doe: i64 = z - era * 146097;
    const yoe: i64 = @divFloor(doe - @divFloor(doe, 1460) + @divFloor(doe, 36524) - @divFloor(doe, 146096), 365);
    const y: i64 = yoe + era * 400;
    const doy: i64 = doe - (365 * yoe + @divFloor(yoe, 4) - @divFloor(yoe, 100));
    const mp: i64 = @divFloor(5 * doy + 2, 153);
    const month: i64 = if (mp < 10) mp + 3 else mp - 9;
    return .{
        .year = if (month <= 2) y + 1 else y,
        .month = month,
        .day = doy - @divFloor(153 * mp + 2, 5) + 1,
        .hour = @divFloor(day_ms, 3600000),
        .minute = @divFloor(@mod(day_ms, 3600000), 60000),
        .second = @divFloor(@mod(day_ms, 60000), 1000),
        .milli = @mod(day_ms, 1000),
        .days = days,
    };
}

pub fn signal(sig: i32, handler: ?[*]const u8) callconv(.c) i32 {
    _ = handler;
    sa_std.last_error = SA_STD_OK;
    return sig;
}

// md5 of the input, written as 32 lowercase hex chars into out (cap must be >= 32).
// This is exactly the JA3 hash given a pre-built JA3 string.
// sha256 of the input, written as 64 lowercase hex chars into out (cap must be >= 64).
// JA4 truncated hash: first 12 lowercase hex chars of sha256(input). JA4's `b`
// (cipher) and `c` (extension+sigalg) segments are defined as sha256 truncated
// to 12 hex chars. An all-zero / empty input segment conventionally maps to the
// literal "000000000000", which the caller can special-case; this returns the
// real truncated digest.
// HMAC-SHA-256 (RFC 2104, vectors in RFC 4231) of msg under key, written
// as 64 lowercase hex chars into out (cap must be >= 64). Same status
// model as sa_std_net_sha256_hex.

pub export fn sa_hmac_sha256_hex(key_ptr: ?[*]const u8, key_len: u64, msg_ptr: ?[*]const u8, msg_len: u64, out_ptr: ?[*]u8, out_cap: u64, out_len: ?*u64) i32 {
    const len_slot = out_len orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    len_slot.* = 0;
    if (out_cap < 64) return finish(SA_STD_ERR_TRUNCATED);
    const key = constBytes(key_ptr, key_len) catch |err| return finishErr(err);
    const msg = constBytes(msg_ptr, msg_len) catch |err| return finishErr(err);
    const out = out_ptr orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    var digest: [32]u8 = undefined;
    std.crypto.auth.hmac.sha2.HmacSha256.create(&digest, msg, key);
    writeHexLower(out[0..64], digest[0..]);
    len_slot.* = 64;
    return finish(SA_STD_OK);
}

// HMAC-SHA-1 (RFC 2104, vectors in RFC 2202) of msg under key, written
// as 40 lowercase hex chars into out (cap must be >= 40).

pub export fn sa_hmac_sha1_hex(key_ptr: ?[*]const u8, key_len: u64, msg_ptr: ?[*]const u8, msg_len: u64, out_ptr: ?[*]u8, out_cap: u64, out_len: ?*u64) i32 {
    const len_slot = out_len orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    len_slot.* = 0;
    if (out_cap < 40) return finish(SA_STD_ERR_TRUNCATED);
    const key = constBytes(key_ptr, key_len) catch |err| return finishErr(err);
    const msg = constBytes(msg_ptr, msg_len) catch |err| return finishErr(err);
    const out = out_ptr orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    var digest: [20]u8 = undefined;
    std.crypto.auth.hmac.HmacSha1.create(&digest, msg, key);
    writeHexLower(out[0..40], digest[0..]);
    len_slot.* = 40;
    return finish(SA_STD_OK);
}
