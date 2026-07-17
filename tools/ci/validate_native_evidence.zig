const std = @import("std");

const max_evidence_size = 64 * 1024;

const EvidenceKind = enum {
    smoke,
    runtime,
};

const Options = struct {
    kind: EvidenceKind,
    platform: []const u8,
    arch: []const u8,
    target: ?[]const u8 = null,
    github_sha: []const u8,
    github_run_id: []const u8,
    github_run_attempt: []const u8,
    path: []const u8,
};

fn usageAndExit() noreturn {
    std.debug.print(
        \\usage: validate_native_evidence --kind smoke|runtime --platform macos|windows --arch ARCH [--target TARGET] --github-sha SHA --github-run-id ID --github-run-attempt ATTEMPT PATH
        \\
    , .{});
    std.process.exit(2);
}

fn parseKind(value: []const u8) !EvidenceKind {
    if (std.mem.eql(u8, value, "smoke")) return .smoke;
    if (std.mem.eql(u8, value, "runtime")) return .runtime;
    return error.InvalidKind;
}

fn nextArg(args: []const []const u8, index: *usize) []const u8 {
    index.* += 1;
    if (index.* >= args.len) usageAndExit();
    return args[index.*];
}

fn parseOptions(args: []const []const u8) !Options {
    var kind: ?EvidenceKind = null;
    var platform: ?[]const u8 = null;
    var arch: ?[]const u8 = null;
    var target: ?[]const u8 = null;
    var github_sha: ?[]const u8 = null;
    var github_run_id: ?[]const u8 = null;
    var github_run_attempt: ?[]const u8 = null;
    var path: ?[]const u8 = null;

    var i: usize = 1;
    while (i < args.len) : (i += 1) {
        const arg = args[i];
        if (std.mem.eql(u8, arg, "--kind")) {
            kind = try parseKind(nextArg(args, &i));
        } else if (std.mem.eql(u8, arg, "--platform")) {
            platform = nextArg(args, &i);
        } else if (std.mem.eql(u8, arg, "--arch")) {
            arch = nextArg(args, &i);
        } else if (std.mem.eql(u8, arg, "--target")) {
            target = nextArg(args, &i);
        } else if (std.mem.eql(u8, arg, "--github-sha")) {
            github_sha = nextArg(args, &i);
        } else if (std.mem.eql(u8, arg, "--github-run-id")) {
            github_run_id = nextArg(args, &i);
        } else if (std.mem.eql(u8, arg, "--github-run-attempt")) {
            github_run_attempt = nextArg(args, &i);
        } else if (std.mem.startsWith(u8, arg, "--")) {
            usageAndExit();
        } else if (path == null) {
            path = arg;
        } else {
            usageAndExit();
        }
    }

    return Options{
        .kind = kind orelse usageAndExit(),
        .platform = platform orelse usageAndExit(),
        .arch = arch orelse usageAndExit(),
        .target = target,
        .github_sha = github_sha orelse usageAndExit(),
        .github_run_id = github_run_id orelse usageAndExit(),
        .github_run_attempt = github_run_attempt orelse usageAndExit(),
        .path = path orelse usageAndExit(),
    };
}

fn jsonObjectGet(root: std.json.Value, key: []const u8) !std.json.Value {
    if (root != .object) return error.ExpectedObject;
    return root.object.get(key) orelse error.MissingField;
}

fn jsonString(root: std.json.Value, key: []const u8) ![]const u8 {
    const value = try jsonObjectGet(root, key);
    if (value != .string) return error.ExpectedString;
    return value.string;
}

fn expectString(root: std.json.Value, key: []const u8, expected: []const u8) !void {
    const actual = try jsonString(root, key);
    if (!std.mem.eql(u8, actual, expected)) {
        std.debug.print("native evidence mismatch for {s}: expected '{s}', got '{s}'\n", .{ key, expected, actual });
        return error.EvidenceMismatch;
    }
}

fn expectedArchive(platform: []const u8, arch: []const u8) ![]const u8 {
    if (std.mem.eql(u8, platform, "macos")) {
        if (std.mem.eql(u8, arch, "x86_64")) return "sa-macos-x86_64.tar.gz";
        if (std.mem.eql(u8, arch, "arm64")) return "sa-macos-arm64.tar.gz";
        return error.UnsupportedArch;
    }
    if (std.mem.eql(u8, platform, "windows")) {
        if (std.mem.eql(u8, arch, "x86_64")) return "sa-windows-x86_64.zip";
        return error.UnsupportedArch;
    }
    return error.UnsupportedPlatform;
}

fn validateVersionString(value: []const u8) !void {
    if (!std.mem.startsWith(u8, value, "sa ")) return error.InvalidVersion;
    var rest = value[3..];
    rest = std.mem.trim(u8, rest, " \t\r\n");
    if (rest.len == 0) return error.InvalidVersion;
    if (std.mem.indexOfAny(u8, rest, " \t\r\n") != null) return error.InvalidVersion;
}

fn expectedRuntimeGates(platform: []const u8) ![]const []const u8 {
    if (std.mem.eql(u8, platform, "macos")) return &.{
        "plugin-host-smoke",
        "daemon-smoke",
        "test-runtime-basic",
        "test-runtime-pal",
        "test-runtime-netx",
        "test-runtime-darwin",
        "test-runtime-darwin-socket",
        "test-runtime-darwin-pty",
    };
    if (std.mem.eql(u8, platform, "windows")) return &.{
        "test-runtime-basic",
        "test-runtime-pal",
        "test-runtime-netx",
        "test-runtime-windows",
    };
    return error.UnsupportedPlatform;
}

fn validatePassedGates(root: std.json.Value, platform: []const u8) !void {
    const value = try jsonObjectGet(root, "passed_gates");
    if (value != .array) return error.ExpectedArray;
    const expected = try expectedRuntimeGates(platform);
    if (value.array.items.len != expected.len) {
        std.debug.print("native runtime evidence gate count mismatch: expected {}, got {}\n", .{ expected.len, value.array.items.len });
        return error.EvidenceMismatch;
    }
    for (expected, 0..) |expected_gate, index| {
        const item = value.array.items[index];
        if (item != .string or !std.mem.eql(u8, item.string, expected_gate)) {
            std.debug.print("native runtime evidence gate mismatch at {}: expected '{s}'\n", .{ index, expected_gate });
            return error.EvidenceMismatch;
        }
    }
}

fn validateEvidence(root: std.json.Value, options: Options) !void {
    try expectString(root, "platform", options.platform);
    try expectString(root, "arch", options.arch);
    try expectString(root, "github_sha", options.github_sha);
    try expectString(root, "github_run_id", options.github_run_id);
    try expectString(root, "github_run_attempt", options.github_run_attempt);

    switch (options.kind) {
        .smoke => {
            try expectString(root, "archive", try expectedArchive(options.platform, options.arch));
            try expectString(root, "native_smoke", "passed");
            try expectString(root, "wasm_magic", "0061736d");
            try validateVersionString(try jsonString(root, "staged_version"));
            try validateVersionString(try jsonString(root, "installed_version"));
        },
        .runtime => {
            try expectString(root, "target", options.target orelse return error.MissingTarget);
            try expectString(root, "runtime_evidence", "passed");
            try validatePassedGates(root, options.platform);
        },
    }
}

fn validateEvidenceSource(allocator: std.mem.Allocator, source: []const u8, options: Options) !void {
    var parsed = try std.json.parseFromSlice(std.json.Value, allocator, source, .{});
    defer parsed.deinit();
    try validateEvidence(parsed.value, options);
}

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const args = try std.process.argsAlloc(allocator);
    const options = parseOptions(args) catch |err| {
        std.debug.print("invalid native evidence validator arguments: {s}\n", .{@errorName(err)});
        usageAndExit();
    };
    const source = try std.fs.cwd().readFileAlloc(allocator, options.path, max_evidence_size);
    try validateEvidenceSource(allocator, source, options);
}

test "validates macOS runtime evidence" {
    const source =
        \\{
        \\  "arch": "arm64",
        \\  "github_run_attempt": "1",
        \\  "github_run_id": "99",
        \\  "github_sha": "abc",
        \\  "passed_gates": ["plugin-host-smoke", "daemon-smoke", "test-runtime-basic", "test-runtime-pal", "test-runtime-netx", "test-runtime-darwin", "test-runtime-darwin-socket", "test-runtime-darwin-pty"],
        \\  "platform": "macos",
        \\  "runtime_evidence": "passed",
        \\  "target": "aarch64-macos"
        \\}
    ;
    try validateEvidenceSource(std.testing.allocator, source, .{
        .kind = .runtime,
        .platform = "macos",
        .arch = "arm64",
        .target = "aarch64-macos",
        .github_sha = "abc",
        .github_run_id = "99",
        .github_run_attempt = "1",
        .path = "unused",
    });
}

test "validates Windows smoke evidence" {
    const source =
        \\{
        \\  "arch": "x86_64",
        \\  "archive": "sa-windows-x86_64.zip",
        \\  "github_run_attempt": "2",
        \\  "github_run_id": "100",
        \\  "github_sha": "def",
        \\  "installed_version": "sa 0.0.4",
        \\  "native_smoke": "passed",
        \\  "platform": "windows",
        \\  "staged_version": "sa 0.0.4",
        \\  "wasm_magic": "0061736d"
        \\}
    ;
    try validateEvidenceSource(std.testing.allocator, source, .{
        .kind = .smoke,
        .platform = "windows",
        .arch = "x86_64",
        .github_sha = "def",
        .github_run_id = "100",
        .github_run_attempt = "2",
        .path = "unused",
    });
}

test "rejects runtime gate drift" {
    const source =
        \\{
        \\  "arch": "x86_64",
        \\  "github_run_attempt": "1",
        \\  "github_run_id": "99",
        \\  "github_sha": "abc",
        \\  "passed_gates": ["test-runtime-basic", "test-runtime-windows"],
        \\  "platform": "windows",
        \\  "runtime_evidence": "passed",
        \\  "target": "native"
        \\}
    ;
    try std.testing.expectError(error.EvidenceMismatch, validateEvidenceSource(std.testing.allocator, source, .{
        .kind = .runtime,
        .platform = "windows",
        .arch = "x86_64",
        .target = "native",
        .github_sha = "abc",
        .github_run_id = "99",
        .github_run_attempt = "1",
        .path = "unused",
    }));
}
