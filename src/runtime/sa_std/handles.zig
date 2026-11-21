const std = @import("std");
const DirEntriesHandle = @import("dir_stat.zig").DirEntriesHandle;
const DynamicLibHandle = @import("dlopen.zig").DynamicLibHandle;
const JsonNodeHandle = @import("json_node.zig").JsonNodeHandle;
const JsonScannerHandle = @import("../sa_std.zig").JsonScannerHandle;
const JsonStreamHandle = @import("json_scan.zig").JsonStreamHandle;
const MetadataHandle = @import("../sa_std.zig").MetadataHandle;
pub const NetAddress = @import("../sa_std.zig").NetAddress;
const ProcessHandle = @import("proc_wait.zig").ProcessHandle;
const RegexBufferHandle = @import("regex_core.zig").RegexBufferHandle;
const RegexHandle = @import("../sa_std.zig").RegexHandle;
const RegexMatchHandle = @import("../sa_std.zig").RegexMatchHandle;
const RegexMatchListHandle = @import("regex_core.zig").RegexMatchListHandle;
const RegexSplitListHandle = @import("regex_core.zig").RegexSplitListHandle;
const UnixAddrHandle = @import("sock_core.zig").UnixAddrHandle;
pub const addressHostText = @import("../sa_std.zig").addressHostText;
pub const is_wasm = @import("../sa_std.zig").is_wasm;
pub const libc = @import("../sa_std.zig").libc;
const lxClose = @import("../sa_std.zig").lxClose;
const sio = @import("../sa_std.zig").sio;

pub const BufferHandle = struct {
    allocator: std.mem.Allocator,
    bytes: []u8,

    pub fn deinit(self: *BufferHandle) void {
        if (self.bytes.len != 0) self.allocator.free(self.bytes);
        self.bytes = &.{};
    }
};

const DirEntryHandle = struct {
    allocator: std.mem.Allocator,
    name: []u8,
    kind: u32,
    ino: u64,

    pub fn deinit(self: *DirEntryHandle) void {
        if (self.name.len != 0) self.allocator.free(self.name);
        self.name = &.{};
    }
};

pub const NetAddrHandle = struct {
    allocator: std.mem.Allocator,
    host: []u8,
    addr: NetAddress,

    pub fn deinit(self: *NetAddrHandle) void {
        if (self.host.len != 0) self.allocator.free(self.host);
        self.host = &.{};
    }

    pub fn init(allocator: std.mem.Allocator, address: NetAddress) !NetAddrHandle {
        const host = try addressHostText(allocator, address);
        return .{
            .allocator = allocator,
            .host = host,
            .addr = address,
        };
    }
};

const NetAddrListHandle = struct {
    allocator: std.mem.Allocator,
    addresses: []NetAddress,
    next_index: usize = 0,

    pub fn deinit(self: *NetAddrListHandle) void {
        if (self.addresses.len != 0) self.allocator.free(self.addresses);
        self.addresses = &.{};
        self.next_index = 0;
    }
};

const FmtHandle = struct {
    allocator: std.mem.Allocator,
    bytes: []u8,

    fn deinit(self: *FmtHandle) void {
        if (self.bytes.len != 0) self.allocator.free(self.bytes);
        self.bytes = &.{};
    }
};

// A JSON node handle addresses a value inside its document tree by PATH
// (object keys / array indices from the document root). Every acquire
// re-resolves the path against the live tree, so a mutation performed
// through any handle is visible through all other handles of the same
// document. Removing the exact key a handle points at (or an ancestor of
// it) detaches the handle: later operations fail with InvalidHandle
// instead of reading a stale snapshot.
// Returns a fully-owned copy of `base` with `segment` appended (key bytes
// duplicated with `allocator`).

pub const JsonBufferHandle = struct {
    allocator: std.mem.Allocator,
    bytes: []u8,

    pub fn deinit(self: *JsonBufferHandle) void {
        if (self.bytes.len != 0) self.allocator.free(self.bytes);
        self.bytes = &.{};
    }
};

pub const JsonWriterHandle = struct {
    allocator: std.mem.Allocator,
    aw: std.Io.Writer.Allocating,
    stream: std.json.Stringify,
    options: std.json.Stringify.Options,
    root_value_started: bool = false,
    root_value_complete: bool = false,
    open_depth: u32 = 0,
    result_buffer: ?u64 = null,

    pub fn init(allocator: std.mem.Allocator, options: std.json.Stringify.Options) !*JsonWriterHandle {
        const handle = try allocator.create(JsonWriterHandle);
        handle.* = .{
            .allocator = allocator,
            .aw = .init(allocator),
            .stream = undefined,
            .options = options,
            .root_value_started = false,
            .root_value_complete = false,
            .open_depth = 0,
            .result_buffer = null,
        };
        handle.stream = .{ .writer = &handle.aw.writer, .options = options };
        return handle;
    }

    pub fn deinit(self: *JsonWriterHandle) void {
        self.aw.deinit();
        self.allocator.destroy(self);
    }
};

const EnvHandle = struct {
    allocator: std.mem.Allocator,
    bytes: []u8,

    fn deinit(self: *EnvHandle) void {
        if (self.bytes.len != 0) self.allocator.free(self.bytes);
        self.bytes = &.{};
    }
};

pub const TimeDate = extern struct {
    unix_ms: i64,
    unix_ns: i64,
    year: u16,
    month: u8,
    day: u8,
    hour: u8,
    minute: u8,
    second: u8,
    millisecond: u16,
};

pub const Timeval = std.posix.timeval;

pub const LingerOption = extern struct { onoff: i32, linger: i32 };

pub const Timespec = std.posix.timespec;

const OwnedFdHandle = struct {
    fd: std.posix.fd_t,

    fn deinit(self: *OwnedFdHandle) void {
        lxClose(self.fd);
        self.fd = -1;
    }
};

const TerminalSession = struct {
    fd: std.posix.fd_t,
    saved: std.posix.termios,

    fn deinit(self: *TerminalSession) !void {
        try std.posix.tcsetattr(self.fd, .FLUSH, self.saved);
    }
};

pub const TcpListener = struct {
    fd: std.posix.fd_t,
    addr: NetAddress,
};

pub const Resource = union(enum) {
    file: sio.File,
    dynamic_lib: *DynamicLibHandle,
    tcp_stream: std.posix.fd_t,
    tcp_listener: TcpListener,
    udp_socket: std.posix.socket_t,
    buffer: BufferHandle,
    metadata: MetadataHandle,
    dir_entries: DirEntriesHandle,
    dir_entry: DirEntryHandle,
    net_addr: NetAddrHandle,
    net_addr_list: NetAddrListHandle,
    unix_addr: UnixAddrHandle,
    fmt: FmtHandle,
    env: EnvHandle,
    json_node: JsonNodeHandle,
    json_buffer: JsonBufferHandle,
    json_scanner: *JsonScannerHandle,
    json_stream: *JsonStreamHandle,
    json_writer: *JsonWriterHandle,
    regex: *RegexHandle,
    regex_match: *RegexMatchHandle,
    regex_match_list: *RegexMatchListHandle,
    regex_split_list: *RegexSplitListHandle,
    regex_buffer: *RegexBufferHandle,
    owned_fd: OwnedFdHandle,
    terminal_session: TerminalSession,
    process: ProcessHandle,

    pub fn close(self: *Resource) !void {
        switch (self.*) {
            .file => |file| file.close(),
            .dynamic_lib => |handle| {
                handle.deinit();
                std.heap.page_allocator.destroy(handle);
            },
            .tcp_stream => |stream| lxClose(stream),
            .tcp_listener => |*server| lxClose(server.fd),
            .udp_socket => |fd| lxClose(fd),
            .buffer => |*buffer| buffer.deinit(),
            .metadata => |*metadata| metadata.deinit(),
            .dir_entries => |*entries| entries.deinit(),
            .dir_entry => |*entry| entry.deinit(),
            .net_addr => |*addr| addr.deinit(),
            .net_addr_list => |*list| list.deinit(),
            .unix_addr => |*addr| addr.deinit(),
            .fmt => |*fmt| fmt.deinit(),
            .env => |*env| env.deinit(),
            .json_node => |*node| node.deinit(),
            .json_buffer => |*buffer| buffer.deinit(),
            .json_scanner => |scanner| scanner.destroy(),
            .json_stream => |stream| stream.deinit(),
            .json_writer => |writer| writer.deinit(),
            .regex => |regex| regex.destroy(),
            .regex_match => |match| match.destroy(),
            .regex_match_list => |list| list.destroy(),
            .regex_split_list => |list| list.destroy(),
            .regex_buffer => |buffer| buffer.destroy(),
            .owned_fd => |*fd| fd.deinit(),
            .terminal_session => |*session| {
                // No terminal sessions can exist on WASI (raw_enter stubbed);
                // skip the tcsetattr restore, which wasi-libc does not provide.
                if (is_wasm) {} else try session.deinit();
            },
            .process => |*proc| proc.deinit(),
        }
        self.* = undefined;
    }
};
