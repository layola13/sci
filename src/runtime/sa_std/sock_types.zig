const std = @import("std");
const builtin = @import("../sa_std.zig").builtin;
pub const is_linux = @import("../sa_std.zig").is_linux;
pub const is_wasm = @import("../sa_std.zig").is_wasm;

const WasiSockAddrUn = extern struct { family: u16 = 0, path: [108]u8 = undefined };

const WasiSockAddrIn = extern struct { port: u16 = 0, addr: u32 = 0, zero: [8]u8 = undefined };

const WasiSockAddrIn6 = extern struct { port: u16 = 0, flowinfo: u32 = 0, addr: [16]u8 = undefined, scope_id: u32 = 0 };

const WasiSockAddrStorage = extern struct { family: u16 = 0, __pad: [126]u8 = undefined };

const WasiSockAddr = extern struct { family: u16 = 0, data: [14]u8 = undefined };

pub const SockAddrUnT = if (is_wasm) WasiSockAddrUn else std.posix.sockaddr.un;

pub const SockAddrInT = if (is_wasm) WasiSockAddrIn else std.posix.sockaddr.in;

pub const SockAddrIn6T = if (is_wasm) WasiSockAddrIn6 else std.posix.sockaddr.in6;

pub const SockAddrStorageT = if (is_wasm) WasiSockAddrStorage else std.posix.sockaddr.storage;

pub const SockAddrT = if (is_wasm) WasiSockAddr else std.posix.sockaddr;

pub const SockLenT = if (is_wasm) u32 else std.posix.socklen_t;

// wasi has no wait macros/signals (std.posix.W/SIG are void); dummies so
// status helpers type-check (callers stubbed to UNSUPPORTED on wasm).
// wasi-libc has no AF/SOL (void via std.c); Linux-value dummies for compile.

const WasiAF = struct {
    pub const UNIX: u16 = 1;
    pub const INET: u16 = 2;
    pub const INET6: u16 = 10;
};

pub const AFT = if (is_wasm) WasiAF else std.posix.AF;

pub const WasiSOL = struct {
    pub const SOCKET: u32 = 1;
};

const WasiSO = struct {
    pub const REUSEADDR: u32 = 2;
    pub const TYPE: u32 = 3;
    pub const ERROR: u32 = 4;
    pub const BROADCAST: u32 = 6;
    pub const SNDBUF: u32 = 7;
    pub const RCVBUF: u32 = 8;
    pub const KEEPALIVE: u32 = 9;
    pub const LINGER: u32 = 13;
    pub const REUSEPORT: u32 = 15;
    pub const PEERCRED: u32 = 17;
    pub const RCVTIMEO: u32 = 20;
    pub const SNDTIMEO: u32 = 21;
    pub const ACCEPTCONN: u32 = 30;
};

pub const SOT = if (is_wasm) WasiSO else std.posix.SO;

const WasiIPPROTO = struct {
    pub const IP: u32 = 0;
    pub const TCP: u32 = 6;
    pub const UDP: u32 = 17;
    pub const IPV6: u32 = 41;
};

pub const IPPROTOT = if (is_wasm) WasiIPPROTO else std.posix.IPPROTO;

const WasiSOCK = struct {
    pub const STREAM: u32 = 1;
    pub const DGRAM: u32 = 2;
    pub const NONBLOCK: u32 = 2048;
    pub const CLOEXEC: u32 = 524288;
};

pub const SOCKT = if (is_wasm) WasiSOCK else std.posix.SOCK;

// Linux-only socket options/constants fall back to neutral values elsewhere;
// the export functions that use them are compiled out of non-Linux builds.

pub const TCP_QUICKACK: u32 = if (is_linux) std.os.linux.TCP.QUICKACK else 0;

pub const TCP_DEFER_ACCEPT: u32 = if (is_linux) std.os.linux.TCP.DEFER_ACCEPT else 0;

pub const TCP_KEEPIDLE: u32 = if (is_linux) std.os.linux.TCP.KEEPIDLE else if (builtin.os.tag == .freebsd) 256 else std.posix.TCP.KEEPALIVE;

pub const TCP_KEEPINTVL: u32 = if (is_linux) std.os.linux.TCP.KEEPINTVL else std.posix.TCP.KEEPINTVL;

pub const TCP_KEEPCNT: u32 = if (is_linux) std.os.linux.TCP.KEEPCNT else std.posix.TCP.KEEPCNT;

pub const SO_PASSCRED: u32 = if (is_linux) std.os.linux.SO.PASSCRED else 0;

pub const InAddrC = extern struct {
    s_addr: u32,
};

// Mirrors C sa_net_iov in sa_std.h. Layout must stay { u8* base; usize len; }.
/// Cap on iovec entries accepted per vectored call. Matches POSIX IOV_MAX where
/// available and stays comfortably below common OS hard limits.

pub const IP_MULTICAST_TTL_OPT: u32 = 33;

pub const IP_MULTICAST_LOOP_OPT: u32 = 34;

pub const IP_MULTICAST_IF_OPT: u32 = 32;

pub const IP_ADD_MEMBERSHIP_OPT: u32 = 35;

pub const IP_DROP_MEMBERSHIP_OPT: u32 = 36;

pub const IPV6_JOIN_GROUP_OPT: u32 = 20;

pub const IPV6_LEAVE_GROUP_OPT: u32 = 21;

pub const IPV6_MULTICAST_HOPS_OPT: u32 = 18;

pub const IPV6_MULTICAST_LOOP_OPT: u32 = 19;

pub const IPV6_MULTICAST_IF_OPT: u32 = 17;

// Linux control-message numbers the parser keys on (asm-generic /
// in.h values; net.sla pins the SLA-facing names). std.os.linux
// does not name SO_TIMESTAMP, so the literal is spelled out here.

pub const cmsg_level_ip: i32 = 0; // IPPROTO_IP

pub const cmsg_level_ipv6: i32 = 41; // IPPROTO_IPV6

pub const cmsg_type_ip_pktinfo: i32 = 8; // IP_PKTINFO

pub const cmsg_type_ipv6_pktinfo: i32 = 50; // IPV6_PKTINFO

pub const cmsg_type_timestamp: i32 = 29; // SO_TIMESTAMP
