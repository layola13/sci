const std = @import("std");
const Dir = @import("sa_io.zig").Dir;
const EnvMap = @import("sa_io.zig").EnvMap;
const File = @import("sa_io.zig").File;
const cwd = @import("sa_io.zig").cwd;
const getEnvMap = @import("sa_io.zig").getEnvMap;
const io = @import("sa_io.zig").io;

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
        // NOTE(Zig 0.17): the global/test-runner Io instances carry an EMPTY
        // environ, so a null env_map would spawn children with no environment
        // at all (0.14 inherited the live one; that broke `zig cc` links with
        // AppDataDirUnavailable). Snapshot the live environment per spawn; a
        // fresh snapshot (rather than a pointer cached at Io init) also
        // observes runtime setenv changes.
        var live_env: ?EnvMap = null;
        defer if (live_env) |*m| m.deinit();
        const env_map = self.env_map orelse blk: {
            live_env = try getEnvMap(self.allocator);
            break :blk &live_env.?;
        };
        var inner = try std.process.spawn(io(), .{
            .argv = self.argv,
            .cwd = self.spawnCwd(),
            .environ_map = env_map,
            .stdin = mapStdio(self.stdin_behavior),
            .stdout = mapStdio(self.stdout_behavior),
            .stderr = mapStdio(self.stderr_behavior),
        });
        errdefer inner.kill(io());
        // Transfer pipe ownership to the sio.File wrappers so the later
        // inner.kill() cleanup does not double-close fds the caller (or a
        // responder thread) already closed via those wrappers.
        if (self.stdin_behavior == .Pipe) {
            self.stdin = .{ .inner = inner.stdin.? };
            inner.stdin = null;
        }
        if (self.stdout_behavior == .Pipe) {
            self.stdout = .{ .inner = inner.stdout.? };
            inner.stdout = null;
        }
        if (self.stderr_behavior == .Pipe) {
            self.stderr = .{ .inner = inner.stderr.? };
            inner.stderr = null;
        }
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
        // NOTE(Zig 0.17): see spawn() — a null env_map must inherit the live
        // environment, not the Io instance's empty environ snapshot.
        var live_env: ?EnvMap = null;
        defer if (live_env) |*m| m.deinit();
        const env_map = options.env_map orelse blk: {
            live_env = try getEnvMap(options.allocator);
            break :blk &live_env.?;
        };
        const limit: std.Io.Limit = .limited(options.max_output_bytes);
        return try std.process.run(options.allocator, io(), .{
            .argv = options.argv,
            .cwd = child_cwd,
            .environ_map = env_map,
            .stdout_limit = limit,
            .stderr_limit = limit,
        });
    }
};
