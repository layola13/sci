//! Zig 0.17 compatibility layer.
//!
//! This module preserves the Zig 0.14-era `std.fs` / `std.process` call shapes
//! used across this repository, reimplemented on top of `std.Io`.
//!
//! Usage: add `const sio = @import("sa_io.zig");` (adjust the relative path
//! for the importing file) and rename:
//!   `std.fs.cwd()`          -> `sio.cwd()`
//!   `std.fs.Dir`            -> `sio.Dir`
//!   `std.fs.File`           -> `sio.File`
//!   `std.fs.openFileAbsolute` (etc.) -> `sio.openFileAbsolute`
//!   `std.process.Child`     -> `sio.Child`
//!   `std.process.getEnvVarOwned` (etc.) -> `sio.getEnvVarOwned`
//!   (`std.fs.path.*` needs no change.)
//!
//! I/O runs on a process-global `std.Io.Threaded` instance. Inside unit tests
//! (`builtin.is_test`) the test runner's own instance (`std.testing.io`) is
//! reused so no second thread pool is created.

const std = @import("std");
const builtin = @import("builtin");

// ---------------------------------------------------------------------------
// Io plumbing
// ---------------------------------------------------------------------------

var global_threaded: ?std.Io.Threaded = null;
var global_mu: std.atomic.Mutex = .unlocked;

/// Process-global `Io`. In tests this is the test runner's instance.
pub fn io() std.Io {
    if (builtin.is_test) return std.testing.io;
    while (!global_mu.tryLock()) {
        std.Thread.yield() catch {};
    }
    defer global_mu.unlock();
    if (global_threaded) |*t| return t.io();
    global_threaded = std.Io.Threaded.init(std.heap.page_allocator, .{});
    return (&global_threaded.?).io();
}

// ---------------------------------------------------------------------------
// Dir (mirrors the 0.14 `std.fs.Dir` API used by this repo)
// ---------------------------------------------------------------------------

pub const Entry = std.Io.Dir.Entry;

pub const Iterator = struct {
    it: std.Io.Dir.Iterator,

    pub fn next(self: *Iterator) !?Entry {
        return try self.it.next(io());
    }
};

pub const Dir = struct {
    inner: std.Io.Dir,

    pub fn openDir(self: Dir, sub_path: []const u8, options: std.Io.Dir.OpenOptions) !Dir {
        return .{ .inner = try self.inner.openDir(io(), sub_path, options) };
    }

    pub fn openFile(self: Dir, sub_path: []const u8, options: std.Io.Dir.OpenFileOptions) !File {
        return .{ .inner = try self.inner.openFile(io(), sub_path, options) };
    }

    pub fn createFile(self: Dir, sub_path: []const u8, options: std.Io.Dir.CreateFileOptions) !File {
        return .{ .inner = try self.inner.createFile(io(), sub_path, options) };
    }

    pub fn readFileAlloc(self: Dir, allocator: std.mem.Allocator, sub_path: []const u8, max_bytes: usize) ![]u8 {
        return try self.inner.readFileAlloc(io(), sub_path, allocator, .limited(max_bytes));
    }

    pub fn writeFile(self: Dir, options: std.Io.Dir.WriteFileOptions) !void {
        return try self.inner.writeFile(io(), options);
    }

    pub fn access(self: Dir, sub_path: []const u8, options: std.Io.Dir.AccessOptions) !void {
        return try self.inner.access(io(), sub_path, options);
    }

    pub fn statFile(self: Dir, sub_path: []const u8) !Stat {
        return try self.inner.statFile(io(), sub_path, .{});
    }

    pub fn stat(self: Dir) !Stat {
        return try self.inner.stat(io());
    }

    /// Old `makePath` (mkdir -p).
    pub fn makePath(self: Dir, sub_path: []const u8) !void {
        return try self.inner.createDirPath(io(), sub_path);
    }

    /// Old `makeDir` (single level; fails with PathAlreadyExists if present).
    pub fn makeDir(self: Dir, sub_path: []const u8) !void {
        return try self.inner.createDir(io(), sub_path, .default_dir);
    }

    pub fn deleteFile(self: Dir, sub_path: []const u8) !void {
        return try self.inner.deleteFile(io(), sub_path);
    }

    pub fn deleteTree(self: Dir, sub_path: []const u8) !void {
        return try self.inner.deleteTree(io(), sub_path);
    }

    pub fn deleteDir(self: Dir, sub_path: []const u8) !void {
        return try self.inner.deleteDir(io(), sub_path);
    }

    pub fn rename(self: Dir, old_sub_path: []const u8, new_dir: Dir, new_sub_path: []const u8) !void {
        return try self.inner.rename(old_sub_path, new_dir.inner, new_sub_path, io());
    }

    pub fn copyFile(
        self: Dir,
        source_path: []const u8,
        dest_dir: Dir,
        dest_path: []const u8,
        options: std.Io.Dir.CopyFileOptions,
    ) !void {
        return try self.inner.copyFile(source_path, dest_dir.inner, dest_path, io(), options);
    }

    pub fn symLink(self: Dir, target_path: []const u8, sym_link_path: []const u8, flags: std.Io.Dir.SymLinkFlags) !void {
        return try self.inner.symLink(io(), target_path, sym_link_path, flags);
    }

    pub fn readLink(self: Dir, sub_path: []const u8, buffer: []u8) ![]u8 {
        const n = try self.inner.readLink(io(), sub_path, buffer);
        return buffer[0..n];
    }

    pub fn realpath(self: Dir, sub_path: []const u8, out_buffer: []u8) ![]u8 {
        const n = try self.inner.realPathFile(io(), sub_path, out_buffer);
        return out_buffer[0..n];
    }

    pub fn realpathAlloc(self: Dir, allocator: std.mem.Allocator, sub_path: []const u8) ![]u8 {
        const z = try self.inner.realPathFileAlloc(io(), sub_path, allocator);
        defer allocator.free(z);
        return try allocator.dupe(u8, z);
    }

    pub fn iterate(self: Dir) Iterator {
        return .{ .it = self.inner.iterate() };
    }

    pub fn setAsCwd(self: Dir) !void {
        return try std.process.setCurrentDir(io(), self.inner);
    }

    pub fn close(self: Dir) void {
        self.inner.close(io());
    }

    /// Raw handle (old `dir.fd` was a field; use `dir.fd()` now).
    pub fn fd(self: Dir) std.posix.fd_t {
        return self.inner.handle;
    }
};

pub fn cwd() Dir {
    return .{ .inner = std.Io.Dir.cwd() };
}

// ---------------------------------------------------------------------------
// File (mirrors the 0.14 `std.fs.File` API used by this repo)
// ---------------------------------------------------------------------------

pub const Stat = std.Io.File.Stat;

pub const File = struct {
    inner: std.Io.File,

    pub fn close(self: File) void {
        self.inner.close(io());
    }

    pub fn stat(self: File) !Stat {
        return try self.inner.stat(io());
    }

    pub fn sync(self: File) !void {
        return try self.inner.sync(io());
    }

    pub fn length(self: File) !u64 {
        return try self.inner.length(io());
    }

    /// Old name for `length`.
    pub fn getEndPos(self: File) !u64 {
        return try self.inner.length(io());
    }

    pub fn seekTo(self: File, offset: u64) !void {
        // NOTE: `reader`/`writer` below are streaming (fd-offset based),
        // matching the old sequential semantics. `File.reader`/`writer`
        // default to positional (pwrite/pread) which does not advance the
        // fd offset, so successive fresh readers/writers would all start
        // at the same offset. Streaming must be used for all sequential I/O.
        //
        // Absolute seek via the vtable: `Reader.seekTo` on a fresh reader is
        // relative to the fd offset (`fileSeekBy`), which is only correct
        // right after open. This matches the old absolute `lseek` behavior.
        const my_io = io();
        try my_io.vtable.fileSeekTo(my_io.userdata, self.inner, offset);
    }

    pub fn read(self: File, buffer: []u8) !usize {
        // NOTE: single raw streaming read (no buffering layer), so a loop
        // of `read` calls can never strand over-read bytes in a dropped
        // reader. EOF maps to 0 per the old contract.
        return self.inner.readStreaming(io(), &.{buffer}) catch |err| switch (err) {
            error.EndOfStream => 0,
            else => |e| e,
        };
    }

    pub fn readAll(self: File, buffer: []u8) !void {
        // Loop of raw single reads: a buffered reader would strand
        // over-read bytes in a dropped buffer, skipping file content.
        var index: usize = 0;
        while (index != buffer.len) {
            const n = try self.read(buffer[index..]);
            if (n == 0) return error.EndOfStream;
            index += n;
        }
    }

    pub fn readByte(self: File) !u8 {
        var buf: [1]u8 = undefined;
        var r = self.inner.readerStreaming(io(), &buf);
        return try r.interface.takeByte();
    }

    pub fn readToEndAlloc(self: File, allocator: std.mem.Allocator, max_bytes: usize) ![]u8 {
        var buf: [8192]u8 = undefined;
        var r = self.inner.readerStreaming(io(), &buf);
        return try r.interface.allocRemaining(allocator, .limited(max_bytes));
    }

    pub fn write(self: File, bytes: []const u8) !usize {
        try self.writeAll(bytes);
        return bytes.len;
    }

    pub fn writeAll(self: File, bytes: []const u8) !void {
        var buf: [8192]u8 = undefined;
        var w = self.inner.writerStreaming(io(), &buf);
        try w.interface.writeAll(bytes);
        try w.interface.flush();
    }

    pub fn writeByte(self: File, byte: u8) !void {
        var buf: [8192]u8 = undefined;
        var w = self.inner.writerStreaming(io(), &buf);
        try w.interface.writeByte(byte);
        try w.interface.flush();
    }

    pub fn print(self: File, comptime fmt: []const u8, args: anytype) !void {
        var buf: [8192]u8 = undefined;
        var w = self.inner.writerStreaming(io(), &buf);
        try w.interface.print(fmt, args);
        try w.interface.flush();
    }

    /// Buffered reader over a caller-provided buffer. Remember to use
    /// `it.interface.*` for actual I/O, e.g.:
    /// `var rbuf: [4096]u8 = undefined; var r = file.reader(&rbuf);`
    pub fn reader(self: File, buffer: []u8) std.Io.File.Reader {
        return self.inner.readerStreaming(io(), buffer);
    }

    /// Buffered writer over a caller-provided buffer. Remember
    /// `it.interface.*` plus a final `flush()`.
    pub fn writer(self: File, buffer: []u8) std.Io.File.Writer {
        return self.inner.writerStreaming(io(), buffer);
    }
};

// ---------------------------------------------------------------------------
// Absolute-path free functions (mirrors old `std.fs.*Absolute`)
// ---------------------------------------------------------------------------

pub fn openFileAbsolute(path: []const u8, options: std.Io.Dir.OpenFileOptions) !File {
    return .{ .inner = try std.Io.Dir.openFileAbsolute(io(), path, options) };
}

pub fn openDirAbsolute(path: []const u8, options: std.Io.Dir.OpenOptions) !Dir {
    return .{ .inner = try std.Io.Dir.openDirAbsolute(io(), path, options) };
}

pub fn createFileAbsolute(path: []const u8, options: std.Io.Dir.CreateFileOptions) !File {
    return .{ .inner = try std.Io.Dir.createFileAbsolute(io(), path, options) };
}

pub fn renameAbsolute(old_path: []const u8, new_path: []const u8) !void {
    return try std.Io.Dir.renameAbsolute(old_path, new_path, io());
}

pub fn copyFileAbsolute(source_path: []const u8, dest_path: []const u8) !void {
    return try std.Io.Dir.copyFileAbsolute(source_path, dest_path, io(), .{});
}

pub fn readFileAbsoluteAlloc(allocator: std.mem.Allocator, path: []const u8, max_bytes: usize) ![]u8 {
    var file = try openFileAbsolute(path, .{});
    defer file.close();
    return try file.readToEndAlloc(allocator, max_bytes);
}

// ---------------------------------------------------------------------------
// Process / environment / args (mirrors old `std.process.*`)
// ---------------------------------------------------------------------------

pub const EnvMap = std.process.Environ.Map;

pub fn getEnvVarOwned(allocator: std.mem.Allocator, key: []const u8) ![]u8 {
    const zkey = try allocator.dupeSentinel(u8, key, 0);
    defer allocator.free(zkey);
    const value = std.c.getenv(zkey) orelse return error.EnvironmentVariableNotFound;
    return try allocator.dupe(u8, std.mem.span(value));
}

pub fn getCwdAlloc(allocator: std.mem.Allocator) ![]u8 {
    const z = try std.process.currentPathAlloc(io(), allocator);
    defer allocator.free(z);
    return try allocator.dupe(u8, z);
}

pub fn changeCurDir(path: []const u8) !void {
    return try std.process.setCurrentPath(io(), path);
}

pub fn selfExePathAlloc(allocator: std.mem.Allocator) ![]u8 {
    const z = try std.process.executablePathAlloc(io(), allocator);
    defer allocator.free(z);
    return try allocator.dupe(u8, z);
}

pub fn getStdOut() File {
    return .{ .inner = std.Io.File.stdout() };
}

pub fn getStdErr() File {
    return .{ .inner = std.Io.File.stderr() };
}

pub fn getStdIn() File {
    return .{ .inner = std.Io.File.stdin() };
}

pub const max_path_bytes = std.Io.Dir.max_path_bytes;

/// Wall-clock Unix seconds (old `std.time.timestamp`).
pub fn timestampSeconds() i64 {
    return std.Io.Clock.real.now(io()).toSeconds();
}

extern "kernel32" fn GetCommandLineW() callconv(.winapi) [*:0]u16;

/// Old `std.process.argsAlloc`: collect process argv without `Init`.
pub fn argsAlloc(allocator: std.mem.Allocator) ![][:0]u8 {
    switch (builtin.os.tag) {
        .linux => {
            const data = std.Io.Dir.openFileAbsolute(io(), "/proc/self/cmdline", .{}) catch
                return error.UnsupportedOs;
            defer data.close(io());
            var rbuf: [4096]u8 = undefined;
            var r = data.reader(io(), &rbuf);
            const raw = try r.interface.allocRemaining(allocator, .limited(1 << 20));
            defer allocator.free(raw);
            var list: std.array_list.Managed([:0]u8) = .init(allocator);
            errdefer {
                for (list.items) |s| allocator.free(s);
                list.deinit();
            }
            var it = std.mem.splitScalar(u8, raw, 0);
            while (it.next()) |arg| {
                if (arg.len == 0) continue;
                try list.append(try allocator.dupeSentinel(u8, arg, 0));
            }
            return try list.toOwnedSlice();
        },
        .windows => {
            const wcmd = GetCommandLineW();
            var len: usize = 0;
            while (wcmd[len] != 0) : (len += 1) {}
            var iter = try std.process.Args.Windows.init(allocator, wcmd[0..len]);
            var list: std.array_list.Managed([:0]u8) = .init(allocator);
            errdefer {
                for (list.items) |s| allocator.free(s);
                list.deinit();
                iter.deinit();
            }
            while (iter.next()) |arg| {
                // `next` returns slices owned by the iterator buffer; dupe them
                // before `deinit` releases that buffer.
                try list.append(try allocator.dupeSentinel(u8, arg, 0));
            }
            iter.deinit();
            return try list.toOwnedSlice();
        },
        else => return error.UnsupportedOs,
    }
}

pub fn argsFree(allocator: std.mem.Allocator, argv: []const [:0]u8) void {
    for (argv) |s| allocator.free(s);
    allocator.free(argv);
}

// ---------------------------------------------------------------------------
// Child (mirrors the 0.14 `std.process.Child` API used by this repo)
// ---------------------------------------------------------------------------

pub const Child = struct {
    pub const Term = std.process.Child.Term;
    pub const RunResult = std.process.RunResult;

    pub const StdIo = enum {
        Inherit,
        Ignore,
        Pipe,
    };

    argv: []const []const u8,
    allocator: std.mem.Allocator,
    stdin_behavior: StdIo = .Inherit,
    stdout_behavior: StdIo = .Inherit,
    stderr_behavior: StdIo = .Inherit,
    cwd: ?[]const u8 = null,
    cwd_dir: ?Dir = null,
    env_map: ?*const EnvMap = null,

    stdin: ?File = null,
    stdout: ?File = null,
    stderr: ?File = null,
    inner: ?std.process.Child = null,

    pub fn init(argv: []const []const u8, allocator: std.mem.Allocator) Child {
        return .{ .argv = argv, .allocator = allocator };
    }

    fn mapStdio(behavior: StdIo) std.process.SpawnOptions.StdIo {
        return switch (behavior) {
            .Inherit => .inherit,
            .Ignore => .ignore,
            .Pipe => .pipe,
        };
    }

    fn spawnCwd(self: *const Child) std.process.Child.Cwd {
        if (self.cwd_dir) |d| return .{ .dir = d.inner };
        if (self.cwd) |p| return .{ .path = p };
        return .inherit;
    }

    pub fn spawn(self: *Child) !void {
        std.debug.assert(self.inner == null);
        var inner = try std.process.spawn(io(), .{
            .argv = self.argv,
            .cwd = self.spawnCwd(),
            .environ_map = self.env_map,
            .stdin = mapStdio(self.stdin_behavior),
            .stdout = mapStdio(self.stdout_behavior),
            .stderr = mapStdio(self.stderr_behavior),
        });
        errdefer inner.kill(io());
        if (self.stdin_behavior == .Pipe) self.stdin = .{ .inner = inner.stdin.? };
        if (self.stdout_behavior == .Pipe) self.stdout = .{ .inner = inner.stdout.? };
        if (self.stderr_behavior == .Pipe) self.stderr = .{ .inner = inner.stderr.? };
        self.inner = inner;
    }

    pub fn spawnAndWait(self: *Child) !Term {
        try self.spawn();
        return try self.wait();
    }

    /// No-op: spawning is synchronous in 0.17.
    pub fn waitForSpawn(self: *Child) !void {
        _ = self;
    }

    pub fn wait(self: *Child) !Term {
        if (self.inner) |*inner| return try inner.wait(io());
        return error.ChildNotSpawned;
    }

    /// Always succeeds; kept fallible so `catch` at call sites still compiles.
    pub fn kill(self: *Child) !void {
        if (self.inner) |*inner| inner.kill(io());
    }

    pub const RunOptions = struct {
        allocator: std.mem.Allocator,
        argv: []const []const u8,
        cwd: ?[]const u8 = null,
        cwd_dir: ?Dir = null,
        env_map: ?*const EnvMap = null,
        max_output_bytes: usize = 10 * 1024 * 1024,
    };

    /// Old `std.process.Child.run` shape (allocator inside options).
    pub fn run(options: RunOptions) !RunResult {
        const child_cwd: std.process.Child.Cwd = if (options.cwd_dir) |d|
            .{ .dir = d.inner }
        else if (options.cwd) |p|
            .{ .path = p }
        else
            .inherit;
        const limit: std.Io.Limit = .limited(options.max_output_bytes);
        return try std.process.run(options.allocator, io(), .{
            .argv = options.argv,
            .cwd = child_cwd,
            .environ_map = options.env_map,
            .stdout_limit = limit,
            .stderr_limit = limit,
        });
    }
};
