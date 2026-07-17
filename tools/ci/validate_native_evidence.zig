const std = @import("std");

const max_evidence_size = 64 * 1024;
const evidence_schema_version: i64 = 1;

const EvidenceKind = enum {
    smoke,
    runtime,
};

const Options = struct {
    kind: EvidenceKind,
    platform: []const u8,
    arch: []const u8,
    target: ?[]const u8 = null,
    zig_version: []const u8,
    llvm_version: []const u8,
    github_sha: []const u8,
    github_run_id: []const u8,
    github_run_attempt: []const u8,
    path: []const u8,
};

fn usageAndExit() noreturn {
    std.debug.print(
        \\usage: validate_native_evidence --kind smoke|runtime --platform macos|windows --arch ARCH [--target TARGET] --zig-version VERSION --llvm-version VERSION --github-sha SHA --github-run-id ID --github-run-attempt ATTEMPT PATH
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
    var zig_version: ?[]const u8 = null;
    var llvm_version: ?[]const u8 = null;
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
        } else if (std.mem.eql(u8, arg, "--zig-version")) {
            zig_version = nextArg(args, &i);
        } else if (std.mem.eql(u8, arg, "--llvm-version")) {
            llvm_version = nextArg(args, &i);
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
        .zig_version = zig_version orelse usageAndExit(),
        .llvm_version = llvm_version orelse usageAndExit(),
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

fn expectInteger(root: std.json.Value, key: []const u8, expected: i64) !void {
    const value = try jsonObjectGet(root, key);
    if (value != .integer) return error.ExpectedInteger;
    if (value.integer != expected) {
        std.debug.print("native evidence mismatch for {s}: expected {}, got {}\n", .{ key, expected, value.integer });
        return error.EvidenceMismatch;
    }
}

fn expectString(root: std.json.Value, key: []const u8, expected: []const u8) !void {
    const actual = try jsonString(root, key);
    if (!std.mem.eql(u8, actual, expected)) {
        std.debug.print("native evidence mismatch for {s}: expected '{s}', got '{s}'\n", .{ key, expected, actual });
        return error.EvidenceMismatch;
    }
}

fn validateRequiredEvidenceArgument(name: []const u8, value: []const u8) !void {
    const trimmed = std.mem.trim(u8, value, " \t\r\n");
    if (trimmed.len == 0 or std.ascii.eqlIgnoreCase(trimmed, "unknown")) {
        std.debug.print("native evidence argument {s} must be concrete, got '{s}'\n", .{ name, value });
        return error.InvalidEvidenceArgument;
    }
}

fn isHexDigit(byte: u8) bool {
    return (byte >= '0' and byte <= '9') or
        (byte >= 'a' and byte <= 'f') or
        (byte >= 'A' and byte <= 'F');
}

fn validateGitHubSha(value: []const u8) !void {
    if (value.len != 40) {
        std.debug.print("native evidence github_sha must be a 40-character commit SHA, got '{s}'\n", .{value});
        return error.InvalidEvidenceArgument;
    }
    for (value) |byte| {
        if (!isHexDigit(byte)) {
            std.debug.print("native evidence github_sha contains a non-hex character: '{s}'\n", .{value});
            return error.InvalidEvidenceArgument;
        }
    }
}

fn validateGitHubRunNumber(name: []const u8, value: []const u8) !void {
    if (value.len == 0) return error.InvalidEvidenceArgument;
    for (value) |byte| {
        if (byte < '0' or byte > '9') {
            std.debug.print("native evidence argument {s} must be a positive decimal integer, got '{s}'\n", .{ name, value });
            return error.InvalidEvidenceArgument;
        }
    }
    const parsed = std.fmt.parseUnsigned(u64, value, 10) catch {
        std.debug.print("native evidence argument {s} is too large: '{s}'\n", .{ name, value });
        return error.InvalidEvidenceArgument;
    };
    if (parsed == 0) {
        std.debug.print("native evidence argument {s} must be positive, got '{s}'\n", .{ name, value });
        return error.InvalidEvidenceArgument;
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

fn validateInstallerTransports(root: std.json.Value) !void {
    const value = try jsonObjectGet(root, "installer_transports");
    if (value != .array) return error.ExpectedArray;
    const expected = [_][]const u8{ "file", "http" };
    if (value.array.items.len != expected.len) {
        std.debug.print("native smoke evidence installer transport count mismatch: expected {}, got {}\n", .{ expected.len, value.array.items.len });
        return error.EvidenceMismatch;
    }
    for (expected, 0..) |expected_transport, index| {
        const item = value.array.items[index];
        if (item != .string or !std.mem.eql(u8, item.string, expected_transport)) {
            std.debug.print("native smoke evidence installer transport mismatch at {}: expected '{s}'\n", .{ index, expected_transport });
            return error.EvidenceMismatch;
        }
    }
}

fn validateEvidence(root: std.json.Value, options: Options) !void {
    try validateRequiredEvidenceArgument("zig_version", options.zig_version);
    try validateRequiredEvidenceArgument("llvm_version", options.llvm_version);
    try validateRequiredEvidenceArgument("github_sha", options.github_sha);
    try validateRequiredEvidenceArgument("github_run_id", options.github_run_id);
    try validateRequiredEvidenceArgument("github_run_attempt", options.github_run_attempt);
    try validateGitHubSha(options.github_sha);
    try validateGitHubRunNumber("github_run_id", options.github_run_id);
    try validateGitHubRunNumber("github_run_attempt", options.github_run_attempt);

    try expectInteger(root, "evidence_schema_version", evidence_schema_version);
    try expectString(root, "platform", options.platform);
    try expectString(root, "arch", options.arch);
    try expectString(root, "zig_version", options.zig_version);
    try expectString(root, "llvm_version", options.llvm_version);
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
            try validateVersionString(try jsonString(root, "http_installed_version"));
            try validateInstallerTransports(root);
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
        \\  "evidence_schema_version": 1,
        \\  "github_run_attempt": "1",
        \\  "github_run_id": "99",
        \\  "github_sha": "0123456789abcdef0123456789abcdef01234567",
        \\  "llvm_version": "14.0.6",
        \\  "passed_gates": ["plugin-host-smoke", "daemon-smoke", "test-runtime-basic", "test-runtime-pal", "test-runtime-netx", "test-runtime-darwin", "test-runtime-darwin-socket", "test-runtime-darwin-pty"],
        \\  "platform": "macos",
        \\  "runtime_evidence": "passed",
        \\  "target": "aarch64-macos",
        \\  "zig_version": "0.14.1"
        \\}
    ;
    try validateEvidenceSource(std.testing.allocator, source, .{
        .kind = .runtime,
        .platform = "macos",
        .arch = "arm64",
        .target = "aarch64-macos",
        .zig_version = "0.14.1",
        .llvm_version = "14.0.6",
        .github_sha = "0123456789abcdef0123456789abcdef01234567",
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
        \\  "evidence_schema_version": 1,
        \\  "github_run_attempt": "2",
        \\  "github_run_id": "100",
        \\  "github_sha": "fedcba9876543210fedcba9876543210fedcba98",
        \\  "http_installed_version": "sa 0.0.4",
        \\  "installed_version": "sa 0.0.4",
        \\  "installer_transports": ["file", "http"],
        \\  "llvm_version": "14.0.6",
        \\  "native_smoke": "passed",
        \\  "platform": "windows",
        \\  "staged_version": "sa 0.0.4",
        \\  "wasm_magic": "0061736d",
        \\  "zig_version": "0.14.1"
        \\}
    ;
    try validateEvidenceSource(std.testing.allocator, source, .{
        .kind = .smoke,
        .platform = "windows",
        .arch = "x86_64",
        .zig_version = "0.14.1",
        .llvm_version = "14.0.6",
        .github_sha = "fedcba9876543210fedcba9876543210fedcba98",
        .github_run_id = "100",
        .github_run_attempt = "2",
        .path = "unused",
    });
}

test "rejects runtime gate drift" {
    const source =
        \\{
        \\  "arch": "x86_64",
        \\  "evidence_schema_version": 1,
        \\  "github_run_attempt": "1",
        \\  "github_run_id": "99",
        \\  "github_sha": "0123456789abcdef0123456789abcdef01234567",
        \\  "llvm_version": "14.0.6",
        \\  "passed_gates": ["test-runtime-basic", "test-runtime-windows"],
        \\  "platform": "windows",
        \\  "runtime_evidence": "passed",
        \\  "target": "native",
        \\  "zig_version": "0.14.1"
        \\}
    ;
    try std.testing.expectError(error.EvidenceMismatch, validateEvidenceSource(std.testing.allocator, source, .{
        .kind = .runtime,
        .platform = "windows",
        .arch = "x86_64",
        .target = "native",
        .zig_version = "0.14.1",
        .llvm_version = "14.0.6",
        .github_sha = "0123456789abcdef0123456789abcdef01234567",
        .github_run_id = "99",
        .github_run_attempt = "1",
        .path = "unused",
    }));
}

test "rejects native evidence schema drift" {
    const source =
        \\{
        \\  "arch": "x86_64",
        \\  "archive": "sa-windows-x86_64.zip",
        \\  "evidence_schema_version": 2,
        \\  "github_run_attempt": "2",
        \\  "github_run_id": "100",
        \\  "github_sha": "fedcba9876543210fedcba9876543210fedcba98",
        \\  "http_installed_version": "sa 0.0.4",
        \\  "installed_version": "sa 0.0.4",
        \\  "installer_transports": ["file", "http"],
        \\  "llvm_version": "14.0.6",
        \\  "native_smoke": "passed",
        \\  "platform": "windows",
        \\  "staged_version": "sa 0.0.4",
        \\  "wasm_magic": "0061736d",
        \\  "zig_version": "0.14.1"
        \\}
    ;
    try std.testing.expectError(error.EvidenceMismatch, validateEvidenceSource(std.testing.allocator, source, .{
        .kind = .smoke,
        .platform = "windows",
        .arch = "x86_64",
        .zig_version = "0.14.1",
        .llvm_version = "14.0.6",
        .github_sha = "fedcba9876543210fedcba9876543210fedcba98",
        .github_run_id = "100",
        .github_run_attempt = "2",
        .path = "unused",
    }));
}

test "rejects weak required evidence arguments" {
    const source =
        \\{
        \\  "arch": "x86_64",
        \\  "archive": "sa-windows-x86_64.zip",
        \\  "evidence_schema_version": 1,
        \\  "github_run_attempt": "2",
        \\  "github_run_id": "100",
        \\  "github_sha": "fedcba9876543210fedcba9876543210fedcba98",
        \\  "http_installed_version": "sa 0.0.4",
        \\  "installed_version": "sa 0.0.4",
        \\  "installer_transports": ["file", "http"],
        \\  "llvm_version": "unknown",
        \\  "native_smoke": "passed",
        \\  "platform": "windows",
        \\  "staged_version": "sa 0.0.4",
        \\  "wasm_magic": "0061736d",
        \\  "zig_version": "0.14.1"
        \\}
    ;
    try std.testing.expectError(error.InvalidEvidenceArgument, validateEvidenceSource(std.testing.allocator, source, .{
        .kind = .smoke,
        .platform = "windows",
        .arch = "x86_64",
        .zig_version = "0.14.1",
        .llvm_version = "unknown",
        .github_sha = "fedcba9876543210fedcba9876543210fedcba98",
        .github_run_id = "100",
        .github_run_attempt = "2",
        .path = "unused",
    }));
    try std.testing.expectError(error.InvalidEvidenceArgument, validateEvidenceSource(std.testing.allocator, source, .{
        .kind = .smoke,
        .platform = "windows",
        .arch = "x86_64",
        .zig_version = "0.14.1",
        .llvm_version = "14.0.6",
        .github_sha = "fedcba9876543210fedcba9876543210fedcba98",
        .github_run_id = " \t",
        .github_run_attempt = "2",
        .path = "unused",
    }));
}

test "rejects malformed GitHub provenance arguments" {
    const source =
        \\{
        \\  "arch": "x86_64",
        \\  "archive": "sa-windows-x86_64.zip",
        \\  "evidence_schema_version": 1,
        \\  "github_run_attempt": "2",
        \\  "github_run_id": "100",
        \\  "github_sha": "fedcba9876543210fedcba9876543210fedcba98",
        \\  "http_installed_version": "sa 0.0.4",
        \\  "installed_version": "sa 0.0.4",
        \\  "installer_transports": ["file", "http"],
        \\  "llvm_version": "14.0.6",
        \\  "native_smoke": "passed",
        \\  "platform": "windows",
        \\  "staged_version": "sa 0.0.4",
        \\  "wasm_magic": "0061736d",
        \\  "zig_version": "0.14.1"
        \\}
    ;
    try std.testing.expectError(error.InvalidEvidenceArgument, validateEvidenceSource(std.testing.allocator, source, .{
        .kind = .smoke,
        .platform = "windows",
        .arch = "x86_64",
        .zig_version = "0.14.1",
        .llvm_version = "14.0.6",
        .github_sha = "not-a-full-sha",
        .github_run_id = "100",
        .github_run_attempt = "2",
        .path = "unused",
    }));
    try std.testing.expectError(error.InvalidEvidenceArgument, validateEvidenceSource(std.testing.allocator, source, .{
        .kind = .smoke,
        .platform = "windows",
        .arch = "x86_64",
        .zig_version = "0.14.1",
        .llvm_version = "14.0.6",
        .github_sha = "fedcba9876543210fedcba9876543210fedcba98",
        .github_run_id = "0",
        .github_run_attempt = "2",
        .path = "unused",
    }));
    try std.testing.expectError(error.InvalidEvidenceArgument, validateEvidenceSource(std.testing.allocator, source, .{
        .kind = .smoke,
        .platform = "windows",
        .arch = "x86_64",
        .zig_version = "0.14.1",
        .llvm_version = "14.0.6",
        .github_sha = "fedcba9876543210fedcba9876543210fedcba98",
        .github_run_id = "100",
        .github_run_attempt = "retry-2",
        .path = "unused",
    }));
}
