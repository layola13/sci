const std = @import("std");
const AFT = @import("../sa_std.zig").AFT;
const MsghdrConstT = @import("sock_core.zig").MsghdrConstT;
const NetAddress = @import("../sa_std.zig").NetAddress;
const Resource = @import("../sa_std.zig").Resource;
const SockAddrIn6T = @import("../sa_std.zig").SockAddrIn6T;
const SockAddrInT = @import("../sa_std.zig").SockAddrInT;
pub const SockAddrT = @import("../sa_std.zig").SockAddrT;
pub const builtin = @import("../sa_std.zig").builtin;
const libc_socklen_t = @import("sock_core.zig").libc_socklen_t;
pub const policy = @import("../sa_std.zig").policy;
pub const policyBootstrap = @import("../sa_std.zig").policyBootstrap;
const sa_policy = @import("../sa_std.zig").sa_policy;
pub const sio = @import("../sa_std.zig").sio;

pub fn policyAllows(resource: sa_policy.Resource) bool {
    // On wasm there is no ELF-constructor guarantee, so the first gated
    // call installs the policy lazily (policyBootstrap is idempotent).
    if (comptime is_wasm) policyBootstrap();
    if (sa_policy.active_context == null) return true;
    const now_ns: i64 = @intCast(std.Io.Clock.awake.now(sio.io()).toNanoseconds());
    return sa_policy.gate(std.heap.page_allocator, resource, now_ns);
}


// wasm32-wasi compat (stage1: archive must compile; sockets/process/dlopen
// stubbed to UNSUPPORTED): SockAddrT/W/SIG are `void` on wasi, and
// std.os.linux has no wasm syscalls. Provide minimal layout-compatible
// aliases so signatures type-check; bodies return UNSUPPORTED via
// `if (comptime is_wasm)` guards.

pub const is_wasm = builtin.cpu.arch.isWasm();

pub const is_linux = builtin.os.tag == .linux;

// --- FreeBSD compat (zig 0.14 std leaves several POSIX surfaces
// unimplemented for freebsd: uname, TCP consts, if_nametoindex) ---

pub const fbsd_sys_nmln: usize = 256;

pub const SA_PLUGIN_DESCRIPTOR_SYMBOL: [:0]const u8 = "saasm_plugin_descriptor_v1";

const DEFAULT_CAPTURE_LIMIT: usize = 50 * 1024;

const empty_bytes: [0]u8 = .{};

pub const empty_mut_bytes: [0]u8 = .{};

pub fn addressHostText(allocator: std.mem.Allocator, address: NetAddress) ![]u8 {
    return switch (address.storage.family) {
        AFT.INET => blk: {
            const sin: *const SockAddrInT = @ptrCast(@alignCast(&address.storage));
            const ip: [4]u8 = @bitCast(sin.addr);
            break :blk try std.fmt.allocPrint(allocator, "{}.{}.{}.{}", .{ ip[0], ip[1], ip[2], ip[3] });
        },
        AFT.INET6 => blk: {
            const sin6: *const SockAddrIn6T = @ptrCast(@alignCast(&address.storage));
            var segbuf: [8]u16 = undefined;
            var i: usize = 0;
            while (i < 8) : (i += 1) {
                segbuf[i] = std.mem.readInt(u16, sin6.addr[i * 2 ..][0..2], .big);
            }
            var outbuf: [64]u8 = undefined;
            const text = try std.fmt.bufPrint(&outbuf, "{x}:{x}:{x}:{x}:{x}:{x}:{x}:{x}", .{
                segbuf[0], segbuf[1], segbuf[2], segbuf[3], segbuf[4], segbuf[5], segbuf[6], segbuf[7],
            });
            if (sin6.scope_id != 0) {
                const with_scope = try std.fmt.allocPrint(allocator, "{s}%{d}", .{ text, sin6.scope_id });
                break :blk with_scope;
            }
            break :blk try allocator.dupe(u8, text);
        },
        AFT.UNIX => try allocator.dupe(u8, address.unixPath()),
        else => try allocator.dupe(u8, ""),
    };
}


pub fn lenAsUsize(len: u64) !usize {
    if (len > @as(u64, @intCast(std.math.maxInt(usize)))) return error.InvalidArgument;
    return @as(usize, @intCast(len));
}

pub fn constBytes(ptr: ?[*]const u8, len: u64) ![]const u8 {
    const n = try lenAsUsize(len);
    if (n == 0) return &.{};
    const p = ptr orelse return error.InvalidArgument;
    return p[0..n];
}

// ---------------------------------------------------------------------------
// 0.17 compat: linux-syscall wrappers (old std.posix throwing helpers removed)
// and socket-address compat (old net Address type removed).
// Verified against /opt/zig/.../lib/std/os/linux.zig + Io/net.zig via probes.
// ---------------------------------------------------------------------------

pub fn errnoToAny(e: anytype) anyerror {
    const n = @tagName(e);
    if (std.mem.eql(u8, n, "SUCCESS")) unreachable;
    if (std.mem.eql(u8, n, "INTR")) return error.Interrupted;
    if (std.mem.eql(u8, n, "AGAIN")) return error.WouldBlock;
    if (std.mem.eql(u8, n, "BADF")) return error.InvalidHandle;
    if (std.mem.eql(u8, n, "ACCES")) return error.AccessDenied;
    if (std.mem.eql(u8, n, "PERM")) return error.PermissionDenied;
    if (std.mem.eql(u8, n, "NOENT")) return error.FileNotFound;
    if (std.mem.eql(u8, n, "EXIST")) return error.PathAlreadyExists;
    if (std.mem.eql(u8, n, "NOTDIR")) return error.NotDir;
    if (std.mem.eql(u8, n, "ISDIR")) return error.IsDir;
    if (std.mem.eql(u8, n, "NAMETOOLONG")) return error.NameTooLong;
    if (std.mem.eql(u8, n, "NOSPC")) return error.NoSpaceLeft;
    if (std.mem.eql(u8, n, "MFILE")) return error.ProcessFdQuotaExceeded;
    if (std.mem.eql(u8, n, "NFILE")) return error.SystemFdQuotaExceeded;
    if (std.mem.eql(u8, n, "NOMEM")) return error.SystemResources;
    if (std.mem.eql(u8, n, "INVAL")) return error.InvalidArgument;
    if (std.mem.eql(u8, n, "SRCH")) return error.ProcessNotFound;
    if (std.mem.eql(u8, n, "CHILD")) return error.ProcessNotFound;
    if (std.mem.eql(u8, n, "TIMEDOUT")) return error.ConnectionTimedOut;
    if (std.mem.eql(u8, n, "INPROGRESS")) return error.ConnectionPending;
    if (std.mem.eql(u8, n, "ALREADY")) return error.AlreadyConnected;
    if (std.mem.eql(u8, n, "CONNREFUSED")) return error.ConnectionRefused;
    if (std.mem.eql(u8, n, "CONNRESET")) return error.ConnectionResetByPeer;
    if (std.mem.eql(u8, n, "CONNABORTED")) return error.ConnectionAborted;
    if (std.mem.eql(u8, n, "NOTCONN")) return error.SocketNotConnected;
    if (std.mem.eql(u8, n, "NETUNREACH")) return error.NetworkUnreachable;
    if (std.mem.eql(u8, n, "HOSTUNREACH")) return error.HostUnreachable;
    if (std.mem.eql(u8, n, "ADDRINUSE")) return error.AddressInUse;
    if (std.mem.eql(u8, n, "ADDRNOTAVAIL")) return error.AddressNotAvailable;
    if (std.mem.eql(u8, n, "MSGSIZE")) return error.MessageTooBig;
    if (std.mem.eql(u8, n, "NOTSOCK")) return error.NotSocket;
    if (std.mem.eql(u8, n, "OPNOTSUPP")) return error.OperationNotSupported;
    if (std.mem.eql(u8, n, "AFNOSUPPORT")) return error.AddressFamilyNotSupported;
    if (std.mem.eql(u8, n, "PROTONOSUPPORT")) return error.ProtocolNotSupported;
    if (std.mem.eql(u8, n, "PIPE")) return error.BrokenPipe;
    if (std.mem.eql(u8, n, "NOTTY")) return error.NotATerminal;
    if (std.mem.eql(u8, n, "FBIG")) return error.FileTooBig;
    if (std.mem.eql(u8, n, "ROFS")) return error.ReadOnlyFileSystem;
    if (std.mem.eql(u8, n, "LOOP")) return error.SymLinkLoop;
    if (std.mem.eql(u8, n, "FAULT")) return error.Unexpected;
    if (std.mem.eql(u8, n, "BUSY")) return error.FileBusy;
    if (std.mem.eql(u8, n, "XDEV")) return error.RenameAcrossMountPoints;
    if (std.mem.eql(u8, n, "TXTBSY")) return error.FileBusy;
    return error.Unexpected;
}

// --- libc fallbacks (macOS/FreeBSD) ---------------------------------------

pub const libc = struct {
    extern "c" fn socket(domain: c_int, socket_type: c_int, protocol: c_int) c_int;
    extern "c" fn bind(fd: c_int, addr: *const SockAddrT, len: libc_socklen_t) c_int;
    extern "c" fn listen(fd: c_int, backlog: c_int) c_int;
    extern "c" fn accept(fd: c_int, addr: ?*SockAddrT, len: ?*libc_socklen_t) c_int;
    extern "c" fn connect(fd: c_int, addr: *const SockAddrT, len: libc_socklen_t) c_int;
    extern "c" fn shutdown(fd: c_int, how: c_int) c_int;
    extern "c" fn sendto(fd: c_int, buf: *const anyopaque, len: usize, flags: c_int, addr: ?*const SockAddrT, addrlen: libc_socklen_t) isize;
    extern "c" fn recvfrom(fd: c_int, buf: *anyopaque, len: usize, flags: c_int, addr: ?*SockAddrT, addrlen: ?*libc_socklen_t) isize;
    extern "c" fn sendmsg(fd: c_int, msg: *const MsghdrConstT, flags: c_int) isize;
    extern "c" fn getsockname(fd: c_int, addr: *SockAddrT, len: *libc_socklen_t) c_int;
    extern "c" fn getpeername(fd: c_int, addr: *SockAddrT, len: *libc_socklen_t) c_int;
    extern "c" fn getsockopt(fd: c_int, level: c_int, optname: c_int, optval: *anyopaque, optlen: *libc_socklen_t) c_int;
    extern "c" fn setsockopt(fd: c_int, level: c_int, optname: c_int, optval: *const anyopaque, optlen: libc_socklen_t) c_int;
    extern "c" fn close(fd: c_int) c_int;
    extern "c" fn read(fd: c_int, buf: *anyopaque, count: usize) isize;
    extern "c" fn write(fd: c_int, buf: *const anyopaque, count: usize) isize;
    extern "c" fn readv(fd: c_int, iov: [*]const std.posix.iovec, iovcnt: c_int) isize;
    extern "c" fn writev(fd: c_int, iov: [*]const std.posix.iovec_const, iovcnt: c_int) isize;
    extern "c" fn dup(fd: c_int) c_int;
    extern "c" fn dup2(old: c_int, new: c_int) c_int;
    extern "c" fn fork() c_int;
    extern "c" fn pipe(fds: *[2]c_int) c_int;
    extern "c" fn chdir(path: [*:0]const u8) c_int;
    extern "c" fn chroot(path: [*:0]const u8) c_int;
    extern "c" fn setgroups(count: c_int, groups: [*]const std.c.gid_t) c_int;
    extern "c" fn setsid() std.c.pid_t;
    extern "c" fn setgid(gid: std.c.gid_t) c_int;
    extern "c" fn setuid(uid: std.c.uid_t) c_int;
    extern "c" fn setpgid(pid: std.c.pid_t, pgid: std.c.pid_t) c_int;
    extern "c" fn fcntl(fd: c_int, cmd: c_int, ...) c_int;
    extern "c" fn unlink(path: [*:0]const u8) c_int;
    extern "c" fn mkdirat(dirfd: c_int, path: [*:0]const u8, mode: std.c.mode_t) c_int;
    extern "c" fn fchmodat(dirfd: c_int, path: [*:0]const u8, mode: std.c.mode_t, flags: c_int) c_int;
    extern "c" fn link(oldpath: [*:0]const u8, newpath: [*:0]const u8) c_int;
    extern "c" fn futimens(fd: c_int, times: *const [2]std.posix.timespec) c_int;
    extern "c" fn kill(pid: std.c.pid_t, sig: c_int) c_int;
    extern "c" fn waitpid(pid: std.c.pid_t, status: *c_int, options: c_int) std.c.pid_t;
    extern "c" fn execve(path: [*:0]const u8, argv: [*:null]const ?[*:0]const u8, envp: [*:null]const ?[*:0]const u8) c_int;
    extern "c" fn _exit(code: c_int) noreturn;
    extern "c" fn ioctl(fd: c_int, request: c_ulong, ...) c_int;
    extern "c" fn socketpair(domain: c_int, socket_type: c_int, protocol: c_int, sv: *[2]c_int) c_int;
    extern "c" fn chown(path: [*:0]const u8, owner: std.c.uid_t, group: std.c.gid_t) c_int;
    extern "c" fn lchown(path: [*:0]const u8, owner: std.c.uid_t, group: std.c.gid_t) c_int;
    extern "c" fn fchown(fd: c_int, owner: std.c.uid_t, group: std.c.gid_t) c_int;
    extern "c" fn mknod(path: [*:0]const u8, mode: std.c.mode_t, dev: std.c.dev_t) c_int;
};

pub const icu_err_overflow: c_int = 15;

pub const monthNames = [_][]const u8{ "Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec" };
