const std = @import("std");
const sio = @import("sio");
const dynlib = @import("../dynlib_compat.zig");
const pkg_manifest = @import("../pkg/manifest.zig");

const ArchiveFormat = @import("remote.zig").ArchiveFormat;
const InstallOptions = @import("install.zig").InstallOptions;
const RemotePluginSpec = @import("remote.zig").RemotePluginSpec;
const SapManifest = @import("install.zig").SapManifest;
const SapPluginKind = @import("install.zig").SapPluginKind;
const absolutePath = @import("manifest.zig").absolutePath;
const childExitedZero = @import("remote.zig").childExitedZero;
const collectAssetFiles = @import("manifest.zig").collectAssetFiles;
const collectInterfaceFiles = @import("manifest.zig").collectInterfaceFiles;
const collectManifestExternalUrls = @import("permissions.zig").collectManifestExternalUrls;
const collectPluginDependencies = @import("permissions.zig").collectPluginDependencies;
const collectStringArray = @import("permissions.zig").collectStringArray;
const dirExistsAbsolute = @import("util.zig").dirExistsAbsolute;
const fileExistsInProject = @import("util.zig").fileExistsInProject;
const jsonString = @import("manifest.zig").jsonString;
const parseAbiPlugin = @import("manifest.zig").parseAbiPlugin;
const pluginDevMode = @import("util.zig").pluginDevMode;
const readFileAbsoluteAlloc = @import("util.zig").readFileAbsoluteAlloc;
const remoteCacheKey = @import("remote.zig").remoteCacheKey;
const remoteCacheKeyForSpec = @import("remote.zig").remoteCacheKeyForSpec;
const selectArtifact = @import("manifest.zig").selectArtifact;
const sha256File = @import("util.zig").sha256File;
const validatePermissions = @import("permissions.zig").validatePermissions;
const validateProjectRelativePath = @import("manifest.zig").validateProjectRelativePath;

const npm_default_registry = "https://registry.npmjs.org";
/// npm channel for plugin sources: `sa plugin install npm:<name>[@<version>]`.
///
/// The channel is inert by contract: the registry only ever drops
/// files here. The host resolves the package through registry
/// metadata, downloads the tarball, verifies it against the
/// registry-signed integrity digest (sha512 SRI; sha1 shasum as the
/// legacy fallback), extracts it, and hands the extracted source
/// tree to the regular install pipeline — building, permissions and
/// confirmation all stay with the host, exactly like a local path.
/// Packages carrying npm lifecycle scripts (preinstall / install /
/// postinstall) are refused outright: install-time code execution is
/// precisely what this channel must never enable, here or under npm
/// itself. The registry base defaults to registry.npmjs.org and can
/// be overridden with SA_NPM_REGISTRY (mirrors, local test servers).
const NpmPackageSpec = struct {
    name: []const u8,
    version: ?[]const u8,
};
fn parseNpmPackageSpec(spec_text: []const u8) !NpmPackageSpec {
    std.debug.assert(std.mem.startsWith(u8, spec_text, "npm:"));
    const body = spec_text["npm:".len..];
    if (body.len == 0) return error.InvalidNpmPackageSpec;
    // A scoped name starts with '@'; the version separator is the
    // last '@' that is not the scope marker.
    var name_end = body.len;
    if (std.mem.lastIndexOfScalar(u8, body, '@')) |idx| {
        if (idx != 0) name_end = idx;
    }
    const name = body[0..name_end];
    const version: ?[]const u8 = if (name_end < body.len) body[name_end + 1 ..] else null;
    if (version) |v| {
        if (v.len == 0) return error.InvalidNpmPackageSpec;
    }
    if (!validNpmPackageName(name)) return error.InvalidNpmPackageSpec;
    return .{ .name = name, .version = version };
}
fn validNpmPackageName(name: []const u8) bool {
    if (name.len == 0 or name.len > 214) return false;
    if (std.mem.indexOf(u8, name, "..") != null) return false;
    for (name) |ch| {
        const ok = (ch >= 'a' and ch <= 'z') or (ch >= '0' and ch <= '9') or
            ch == '-' or ch == '.' or ch == '_' or ch == '~' or ch == '/' or ch == '@';
        if (!ok) return false;
    }
    if (name[0] == '@') {
        const slash = std.mem.indexOfScalar(u8, name, '/') orelse return false;
        if (slash <= 1 or slash == name.len - 1) return false;
        if (std.mem.indexOfScalar(u8, name[slash + 1 ..], '/') != null) return false;
    } else {
        if (std.mem.indexOfScalar(u8, name, '/') != null) return false;
    }
    return true;
}
fn npmRegistryBase(allocator: std.mem.Allocator) ![]u8 {
    const value = sio.getEnvVarOwned(allocator, "SA_NPM_REGISTRY") catch
        return try allocator.dupe(u8, npm_default_registry);
    errdefer allocator.free(value);
    if (std.mem.trim(u8, value, " \t\r\n").len == 0) {
        allocator.free(value);
        return try allocator.dupe(u8, npm_default_registry);
    }
    return value;
}
fn npmEncodePackageName(allocator: std.mem.Allocator, name: []const u8) ![]u8 {
    if (name.len > 0 and name[0] == '@') {
        if (std.mem.indexOfScalar(u8, name, '/')) |slash| {
            return try std.fmt.allocPrint(allocator, "{s}%2f{s}", .{ name[0..slash], name[slash + 1 ..] });
        }
    }
    return try allocator.dupe(u8, name);
}
const NpmResolvedTarball = struct {
    version: []u8,
    tarball_url: []u8,
    integrity: ?[]u8,
    shasum: ?[]u8,

    pub fn deinit(self: *NpmResolvedTarball, allocator: std.mem.Allocator) void {
        allocator.free(self.version);
        allocator.free(self.tarball_url);
        if (self.integrity) |value| allocator.free(value);
        if (self.shasum) |value| allocator.free(value);
        self.* = undefined;
    }
};
fn jsonObjectValue(value: std.json.Value) ?std.json.ObjectMap {
    return switch (value) {
        .object => |object| object,
        else => null,
    };
}
fn resolveNpmTarball(allocator: std.mem.Allocator, metadata_text: []const u8, spec: NpmPackageSpec, stdout: anytype) !NpmResolvedTarball {
    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, metadata_text, .{});
    defer parsed.deinit();
    const root = jsonObjectValue(parsed.value) orelse return error.InvalidNpmRegistryResponse;

    const version_name: []const u8 = if (spec.version) |v| v else blk: {
        const tags_value = root.get("dist-tags") orelse return error.InvalidNpmRegistryResponse;
        const tags = jsonObjectValue(tags_value) orelse return error.InvalidNpmRegistryResponse;
        const latest = tags.get("latest") orelse return error.InvalidNpmRegistryResponse;
        break :blk try jsonString(latest);
    };

    const versions_value = root.get("versions") orelse return error.InvalidNpmRegistryResponse;
    const versions = jsonObjectValue(versions_value) orelse return error.InvalidNpmRegistryResponse;
    const version_value = versions.get(version_name) orelse {
        try stdout.print("npm package {s} has no version {s}\n", .{ spec.name, version_name });
        return error.NpmVersionNotFound;
    };
    const version_doc = jsonObjectValue(version_value) orelse return error.InvalidNpmRegistryResponse;
    const dist_value = version_doc.get("dist") orelse return error.InvalidNpmRegistryResponse;
    const dist = jsonObjectValue(dist_value) orelse return error.InvalidNpmRegistryResponse;
    const tarball_value = dist.get("tarball") orelse return error.InvalidNpmRegistryResponse;

    return .{
        .version = try allocator.dupe(u8, version_name),
        .tarball_url = try allocator.dupe(u8, try jsonString(tarball_value)),
        .integrity = if (dist.get("integrity")) |v| try allocator.dupe(u8, try jsonString(v)) else null,
        .shasum = if (dist.get("shasum")) |v| try allocator.dupe(u8, try jsonString(v)) else null,
    };
}
fn verifyNpmTarballIntegrity(allocator: std.mem.Allocator, tarball_path: []const u8, resolved: NpmResolvedTarball, stdout: anytype) !void {
    if (resolved.integrity) |integrity| {
        // SRI form: "<algorithm>-<base64 digest>". The public
        // registry issues sha512; anything else is refused rather
        // than silently trusted.
        if (!std.mem.startsWith(u8, integrity, "sha512-")) {
            try stdout.print("npm tarball integrity uses an unsupported algorithm: {s}\n", .{integrity});
            return error.NpmIntegrityMismatch;
        }
        const data = try readFileAbsoluteAlloc(allocator, tarball_path, 256 << 20);
        defer allocator.free(data);
        var digest: [64]u8 = undefined;
        std.crypto.hash.sha2.Sha512.hash(data, &digest, .{});
        var encoded_buf: [128]u8 = undefined;
        const encoded = std.base64.standard.Encoder.encode(&encoded_buf, &digest);
        if (!std.mem.eql(u8, encoded, integrity["sha512-".len..])) {
            try stdout.print("npm tarball integrity mismatch for {s}\n", .{resolved.tarball_url});
            return error.NpmIntegrityMismatch;
        }
        try stdout.print("npm tarball integrity verified (sha512)\n", .{});
        return;
    }
    if (resolved.shasum) |shasum| {
        const data = try readFileAbsoluteAlloc(allocator, tarball_path, 256 << 20);
        defer allocator.free(data);
        var digest: [20]u8 = undefined;
        std.crypto.hash.Sha1.hash(data, &digest, .{});
        const hex = std.fmt.bytesToHex(digest, .lower);
        if (!std.mem.eql(u8, hex[0..], shasum)) {
            try stdout.print("npm tarball integrity mismatch for {s}\n", .{resolved.tarball_url});
            return error.NpmIntegrityMismatch;
        }
        try stdout.print("npm tarball integrity verified (sha1)\n", .{});
        return;
    }
    try stdout.print("npm registry response carries no integrity digest for {s}; refusing unverifiable bytes\n", .{resolved.tarball_url});
    return error.NpmIntegrityMissing;
}
/// npm packages must be inert: files only, never install-time code.
/// sa itself never runs package scripts, but the same tarball
/// installed through npm elsewhere would — so a package carrying
/// lifecycle scripts is refused on this channel outright.
fn verifyNoNpmLifecycleScripts(allocator: std.mem.Allocator, root: []const u8, stdout: anytype) !void {
    const pkg_path = try std.fs.path.join(allocator, &.{ root, "package.json" });
    defer allocator.free(pkg_path);
    const text = readFileAbsoluteAlloc(allocator, pkg_path, 1 << 20) catch |err| switch (err) {
        error.FileNotFound => return,
        else => return err,
    };
    defer allocator.free(text);
    const parsed = std.json.parseFromSlice(std.json.Value, allocator, text, .{}) catch return;
    defer parsed.deinit();
    const root_obj = jsonObjectValue(parsed.value) orelse return;
    const scripts_value = root_obj.get("scripts") orelse return;
    const scripts = jsonObjectValue(scripts_value) orelse return;
    for ([_][]const u8{ "preinstall", "install", "postinstall" }) |key| {
        if (scripts.get(key) != null) {
            try stdout.print("refusing npm plugin package with lifecycle script \"{s}\": npm packages must be inert (files only, no install-time code execution)\n", .{key});
            return error.NpmLifecycleScriptsForbidden;
        }
    }
}
pub fn fetchNpmPluginSource(allocator: std.mem.Allocator, spec_text: []const u8, stdout: anytype, options: InstallOptions) ![]u8 {
    const spec = try parseNpmPackageSpec(spec_text);

    const registry_owned = try npmRegistryBase(allocator);
    defer allocator.free(registry_owned);
    const registry = std.mem.trimEnd(u8, registry_owned, "/");

    // Formal mode mirrors the other remote channels: a floating
    // version is a moving target, so an exact version is required,
    // and the registry target is confirmed like any remote URL. The
    // registry's integrity digest then pins the bytes themselves.
    if (!options.dev and !pluginDevMode(allocator)) {
        if (spec.version == null) {
            try stdout.print("refusing npm plugin install without an exact version: {s} (use npm:{s}@<version>)\n", .{ spec_text, spec.name });
            return error.RemotePluginRefRequired;
        }
        const page_url = try std.fmt.allocPrint(allocator, "{s}/{s}", .{ registry, spec.name });
        defer allocator.free(page_url);
        if (!try confirmExternalUrl(stdout, page_url)) return error.RemotePluginUrlNotConfirmed;
    }

    const home = try pluginsHome(allocator);
    defer allocator.free(home);
    const cache_root = try std.fs.path.join(allocator, &.{ home, "cache", "npm" });
    defer allocator.free(cache_root);
    try sio.cwd().makePath(cache_root);
    const cache_key = remoteCacheKey(spec_text);
    const cache_key_hex = std.fmt.bytesToHex(cache_key, .lower);
    const bundle_dir = try std.fs.path.join(allocator, &.{ cache_root, cache_key_hex[0..] });
    defer allocator.free(bundle_dir);
    if (dirExistsAbsolute(bundle_dir)) try sio.cwd().deleteTree(bundle_dir);
    try sio.cwd().makePath(bundle_dir);

    const encoded_name = try npmEncodePackageName(allocator, spec.name);
    defer allocator.free(encoded_name);
    const metadata_url = try std.fmt.allocPrint(allocator, "{s}/{s}", .{ registry, encoded_name });
    defer allocator.free(metadata_url);
    const metadata_path = try std.fs.path.join(allocator, &.{ bundle_dir, "metadata.json" });
    defer allocator.free(metadata_path);
    try downloadRemoteFile(allocator, metadata_url, metadata_path, stdout);
    const metadata_text = try readFileAbsoluteAlloc(allocator, metadata_path, 16 << 20);
    defer allocator.free(metadata_text);

    var resolved = try resolveNpmTarball(allocator, metadata_text, spec, stdout);
    defer resolved.deinit(allocator);
    try stdout.print("npm plugin {s}@{s} resolved from {s}\n", .{ spec.name, resolved.version, registry });

    const tarball_path = try std.fs.path.join(allocator, &.{ bundle_dir, "package.tgz" });
    defer allocator.free(tarball_path);
    try downloadRemoteFile(allocator, resolved.tarball_url, tarball_path, stdout);
    try verifyNpmTarballIntegrity(allocator, tarball_path, resolved, stdout);

    const extract_dir = try std.fs.path.join(allocator, &.{ bundle_dir, "extract" });
    defer allocator.free(extract_dir);
    try sio.cwd().makePath(extract_dir);
    try extractArchiveToDirectory(allocator, tarball_path, extract_dir, .tgz, stdout);

    const root = try findExtractedPluginRoot(allocator, extract_dir);
    errdefer allocator.free(root);
    try verifyNoNpmLifecycleScripts(allocator, root, stdout);
    return root;
}
pub fn fetchRemoteArchivePluginSource(allocator: std.mem.Allocator, spec: RemotePluginSpec, stdout: anytype) ![]u8 {
    std.debug.assert(spec.kind == .archive);
    const format = spec.archive_format orelse return error.InvalidRemotePluginSource;

    const home = try pluginsHome(allocator);
    defer allocator.free(home);
    const cache_root = try std.fs.path.join(allocator, &.{ home, "cache", "archive" });
    defer allocator.free(cache_root);
    try sio.cwd().makePath(cache_root);

    const cache_key = remoteCacheKeyForSpec(spec);
    const cache_key_hex = std.fmt.bytesToHex(cache_key, .lower);
    const bundle_dir = try std.fs.path.join(allocator, &.{ cache_root, cache_key_hex[0..] });
    defer allocator.free(bundle_dir);
    if (dirExistsAbsolute(bundle_dir)) try sio.cwd().deleteTree(bundle_dir);
    try sio.cwd().makePath(bundle_dir);

    const archive_path = try std.fs.path.join(allocator, &.{ bundle_dir, archiveFilename(format) });
    defer allocator.free(archive_path);
    try downloadRemoteFile(allocator, spec.url, archive_path, stdout);

    if (spec.archive_sha256) |expected| {
        const actual = try sha256File(allocator, archive_path);
        if (!std.mem.eql(u8, actual[0..], expected[0..])) {
            try stdout.print("remote plugin archive sha256 mismatch for {s}\n", .{spec.url});
            return error.RemotePluginArchiveShaMismatch;
        }
    }

    const extract_dir = try std.fs.path.join(allocator, &.{ bundle_dir, "extract" });
    defer allocator.free(extract_dir);
    try sio.cwd().makePath(extract_dir);
    try extractArchiveToDirectory(allocator, archive_path, extract_dir, format, stdout);
    return try findExtractedPluginRoot(allocator, extract_dir);
}
fn downloadRemoteFile(allocator: std.mem.Allocator, url: []const u8, dst_path: []const u8, stdout: anytype) !void {
    const curl_result = sio.Child.run(.{
        .allocator = allocator,
        .argv = &.{ "curl", "-L", "--fail", "--silent", "--show-error", "--noproxy", "127.0.0.1,localhost,::1", "-o", dst_path, url },
    }) catch |err| switch (err) {
        error.FileNotFound => {
            const wget_result = try sio.Child.run(.{
                .allocator = allocator,
                .argv = &.{ "wget", "-q", "-O", dst_path, url },
            });
            defer allocator.free(wget_result.stdout);
            defer allocator.free(wget_result.stderr);
            if (!childExitedZero(wget_result.term)) {
                try stdout.print("remote archive download failed for {s}\n{s}", .{ url, wget_result.stderr });
                return error.RemotePluginFetchFailed;
            }
            return;
        },
        else => return err,
    };
    defer allocator.free(curl_result.stdout);
    defer allocator.free(curl_result.stderr);
    if (!childExitedZero(curl_result.term)) {
        try stdout.print("remote archive download failed for {s}\n{s}", .{ url, curl_result.stderr });
        return error.RemotePluginFetchFailed;
    }
}
fn extractArchiveToDirectory(
    allocator: std.mem.Allocator,
    archive_path: []const u8,
    extract_dir: []const u8,
    format: ArchiveFormat,
    stdout: anytype,
) !void {
    const argv: []const []const u8 = switch (format) {
        // --no-same-owner: never restore uid/gid from the archive. GNU tar
        // defaults to --same-owner when run as root, which fails in
        // containers without chown permission (and would be a security
        // hole for remote archives anyway).
        .tar_gz, .tgz => &.{ "tar", "--no-same-owner", "-xzf", archive_path, "-C", extract_dir },
        .tar_xz => &.{ "tar", "--no-same-owner", "-xJf", archive_path, "-C", extract_dir },
        .tar_zst => &.{ "tar", "--no-same-owner", "--zstd", "-xf", archive_path, "-C", extract_dir },
    };
    const result = try sio.Child.run(.{
        .allocator = allocator,
        .argv = argv,
    });
    defer allocator.free(result.stdout);
    defer allocator.free(result.stderr);
    if (!childExitedZero(result.term)) {
        try stdout.print("remote plugin archive extraction failed for {s}\n{s}", .{ archive_path, result.stderr });
        return error.RemotePluginFetchFailed;
    }
}
fn findExtractedPluginRoot(allocator: std.mem.Allocator, extract_dir: []const u8) ![]u8 {
    if (fileExistsInProject(allocator, extract_dir, "sap.json")) return try allocator.dupe(u8, extract_dir);
    return try findUniqueSapRoot(allocator, extract_dir, 0);
}
fn findUniqueSapRoot(allocator: std.mem.Allocator, root: []const u8, depth: u8) anyerror![]u8 {
    if (depth > 4) return error.NoPluginManifestInArchive;
    var dir = try sio.openDirAbsolute(root, .{ .iterate = true });
    defer dir.close();

    var found: ?[]u8 = null;
    var it = dir.iterate();
    while (try it.next()) |entry| {
        if (entry.kind != .directory and entry.kind != .sym_link) continue;
        const child = try std.fs.path.join(allocator, &.{ root, entry.name });
        defer allocator.free(child);
        if (fileExistsInProject(allocator, child, "sap.json")) {
            if (found != null) return error.InvalidRemotePluginSource;
            found = try allocator.dupe(u8, child);
            continue;
        }
        const nested = findUniqueSapRoot(allocator, child, depth + 1) catch |err| switch (err) {
            error.FileNotFound, error.NotDir, error.NoPluginManifestInArchive => null,
            else => return err,
        };
        if (nested) |path| {
            if (found != null) {
                allocator.free(path);
                return error.InvalidRemotePluginSource;
            }
            found = path;
        }
    }
    return found orelse error.NoPluginManifestInArchive;
}
pub fn archiveFormatFromUrl(url: []const u8) ?ArchiveFormat {
    const path = urlPathForRemote(url);
    if (std.mem.endsWith(u8, path, ".tar.gz")) return .tar_gz;
    if (std.mem.endsWith(u8, path, ".tgz")) return .tgz;
    if (std.mem.endsWith(u8, path, ".tar.xz")) return .tar_xz;
    if (std.mem.endsWith(u8, path, ".tar.zst")) return .tar_zst;
    return null;
}
fn urlPathForRemote(url: []const u8) []const u8 {
    const query_idx = std.mem.indexOfScalar(u8, url, '?') orelse url.len;
    return url[0..query_idx];
}
pub fn parseArchiveSha256(text: []const u8) ![32]u8 {
    if (!std.mem.startsWith(u8, text, "sha256:")) return error.InvalidRemotePluginSource;
    return try parseSha256Text(text["sha256:".len..]);
}
fn parseSha256Text(body: []const u8) ![32]u8 {
    if (body.len != 64) return error.InvalidRemotePluginSource;
    var bytes: [32]u8 = undefined;
    _ = std.fmt.hexToBytes(bytes[0..], body) catch return error.InvalidRemotePluginSource;
    return bytes;
}
fn archiveFilename(format: ArchiveFormat) []const u8 {
    return switch (format) {
        .tar_gz => "plugin.tar.gz",
        .tgz => "plugin.tgz",
        .tar_xz => "plugin.tar.xz",
        .tar_zst => "plugin.tar.zst",
    };
}
pub fn stdinIsTty() bool {
    if (comptime @import("builtin").os.tag == .windows) return false;
    _ = std.posix.tcgetattr(std.posix.STDIN_FILENO) catch return false;
    return true;
}
pub const StdinLineReader = struct {
    inner: *std.Io.Reader,

    pub fn readUntilDelimiterOrEof(self: StdinLineReader, buf: []u8, delimiter: u8) !?[]u8 {
        var i: usize = 0;
        var eof = false;
        while (true) {
            const b = self.inner.takeByte() catch |err| switch (err) {
                error.EndOfStream => {
                    eof = true;
                    break;
                },
                else => return err,
            };
            if (b == delimiter) break;
            if (i >= buf.len) return error.StreamTooLong;
            buf[i] = b;
            i += 1;
        }
        if (i == 0 and eof) return null;
        return buf[0..i];
    }
};
pub fn confirmExternalUrl(stdout: anytype, url: []const u8) !bool {
    if (!stdinIsTty()) {
        try stdout.print("refusing remote plugin URL {s}: manual TTY confirmation is required\n", .{url});
        return false;
    }
    try stdout.print(
        \\SA PLUGIN REMOTE SOURCE REVIEW REQUIRED
        \\url: {s}
        \\Type the exact URL to fetch this plugin source: 
    , .{url});
    var buffer: [1024]u8 = undefined;
    var stdin_buf: [8192]u8 = undefined;
    var stdin_stream = sio.getStdIn().reader(&stdin_buf);
    var stdin_reader = StdinLineReader{ .inner = &stdin_stream.interface };
    const line = (try stdin_reader.readUntilDelimiterOrEof(&buffer, '\n')) orelse "";
    const answer = std.mem.trim(u8, line, " \t\r\n");
    if (!std.mem.eql(u8, answer, url)) {
        try stdout.writeAll("remote plugin install cancelled\n");
        return false;
    }
    return true;
}
pub fn defaultPluginsHome(allocator: std.mem.Allocator) ![]u8 {
    if (@import("builtin").os.tag == .windows) {
        const local_app_data = sio.getEnvVarOwned(allocator, "LOCALAPPDATA") catch |err| switch (err) {
            error.EnvironmentVariableNotFound => null,
            else => return err,
        };
        if (local_app_data) |root| {
            defer allocator.free(root);
            if (std.fs.path.isAbsolute(root)) return try std.fs.path.join(allocator, &.{ root, "sa_plugins" });
        }

        const user_profile = sio.getEnvVarOwned(allocator, "USERPROFILE") catch |err| switch (err) {
            error.EnvironmentVariableNotFound => null,
            else => return err,
        };
        if (user_profile) |root| {
            defer allocator.free(root);
            if (std.fs.path.isAbsolute(root)) return try std.fs.path.join(allocator, &.{ root, ".local", "share", "sa_plugins" });
        }

        const cwd = try sio.cwd().realpathAlloc(allocator, ".");
        defer allocator.free(cwd);
        return try std.fs.path.join(allocator, &.{ cwd, ".sa_plugins" });
    }

    const home = sio.getEnvVarOwned(allocator, "HOME") catch |err| switch (err) {
        error.EnvironmentVariableNotFound => {
            const cwd = try sio.cwd().realpathAlloc(allocator, ".");
            defer allocator.free(cwd);
            return try std.fs.path.join(allocator, &.{ cwd, ".sa_plugins" });
        },
        else => return err,
    };
    defer allocator.free(home);
    return try std.fs.path.join(allocator, &.{ home, ".local", "share", "sa_plugins" });
}
pub fn pluginsHomePath(allocator: std.mem.Allocator) ![]u8 {
    return try pluginsHome(allocator);
}
pub fn pluginsHome(allocator: std.mem.Allocator) ![]u8 {
    const configured = sio.getEnvVarOwned(allocator, "SA_PLUGINS_HOME") catch |err| switch (err) {
        error.EnvironmentVariableNotFound => return try defaultPluginsHome(allocator),
        else => return err,
    };
    defer allocator.free(configured);
    if (std.fs.path.isAbsolute(configured)) return try allocator.dupe(u8, configured);
    const cwd = try sio.cwd().realpathAlloc(allocator, ".");
    defer allocator.free(cwd);
    return try std.fs.path.join(allocator, &.{ cwd, configured });
}
pub fn parseSapManifest(allocator: std.mem.Allocator, input_path: []const u8) !SapManifest {
    const sap_path = if (std.mem.endsWith(u8, input_path, "sap.json"))
        try absolutePath(allocator, input_path)
    else blk: {
        const root = try absolutePath(allocator, input_path);
        defer allocator.free(root);
        break :blk try std.fs.path.join(allocator, &.{ root, "sap.json" });
    };
    errdefer allocator.free(sap_path);

    const root_dir = try allocator.dupe(u8, std.fs.path.dirname(sap_path) orelse ".");
    errdefer allocator.free(root_dir);

    const source = try readFileAbsoluteAlloc(allocator, sap_path, 1 << 20);
    defer allocator.free(source);
    var parsed = try std.json.parseFromSlice(std.json.Value, allocator, source, .{});
    defer parsed.deinit();
    const object = switch (parsed.value) {
        .object => |obj| obj,
        else => return error.InvalidSapManifest,
    };

    const schema = try jsonString(object.get("schema") orelse return error.InvalidSapManifest);
    if (!std.mem.eql(u8, schema, "sa.plugin/1")) return error.UnsupportedSapSchema;
    _ = object.get("permissions") orelse return error.PluginPermissionsMissing;
    var permission_info = try validatePermissions(allocator, object.get("permissions").?);
    defer permission_info.deinit(allocator);
    try collectManifestExternalUrls(allocator, object, &permission_info.urls);

    const name = try allocator.dupe(u8, try jsonString(object.get("name") orelse return error.InvalidSapManifest));
    errdefer allocator.free(name);
    const version = try allocator.dupe(u8, try jsonString(object.get("version") orelse return error.InvalidSapManifest));
    errdefer allocator.free(version);
    const abi_plugin = try parseAbiPlugin(object.get("abi"));
    const artifact = try selectArtifact(object.get("artifacts") orelse return error.InvalidSapManifest);
    const artifact_rel = try allocator.dupe(u8, artifact.path);
    errdefer allocator.free(artifact_rel);
    try validateProjectRelativePath(artifact_rel);
    const interface_files = try collectInterfaceFiles(allocator, object.get("interfaces"));
    errdefer {
        for (interface_files) |*iface| iface.deinit(allocator);
        allocator.free(interface_files);
    }
    const asset_files = try collectAssetFiles(allocator, object.get("assets"));
    errdefer {
        for (asset_files) |*asset| asset.deinit(allocator);
        allocator.free(asset_files);
    }
    const dependencies = try collectPluginDependencies(allocator, object.get("dependencies"));
    errdefer {
        for (dependencies) |*dep| dep.deinit(allocator);
        allocator.free(dependencies);
    }
    const kind: SapPluginKind = if (object.get("kind")) |kind_value| blk: {
        const kind_text = try jsonString(kind_value);
        if (std.mem.eql(u8, kind_text, "command")) break :blk .command;
        if (std.mem.eql(u8, kind_text, "language")) break :blk .language;
        return error.InvalidSapManifest;
    } else .command;
    const language_extensions = if (kind == .language)
        try collectStringArray(allocator, object.get("language_extensions"))
    else
        try allocator.alloc([]u8, 0);
    errdefer {
        for (language_extensions) |ext| allocator.free(ext);
        allocator.free(language_extensions);
    }
    const commands = try collectStringArray(allocator, object.get("commands"));
    errdefer {
        for (commands) |command| allocator.free(command);
        allocator.free(commands);
    }
    // A declared command is a single argv token: empty entries and
    // entries containing whitespace could never be dispatched to.
    for (commands) |command| {
        if (command.len == 0) return error.InvalidSapManifest;
        for (command) |ch| {
            if (ch == ' ' or ch == '\t' or ch == '/') return error.InvalidSapManifest;
        }
    }

    return .{
        .root_dir = root_dir,
        .sap_path = sap_path,
        .name = name,
        .version = version,
        .abi_plugin = abi_plugin,
        .artifact_rel = artifact_rel,
        .artifact_sha256 = artifact.sha256,
        .interface_files = interface_files,
        .asset_files = asset_files,
        .dependencies = dependencies,
        .env_permissions = try permission_info.env_permissions.toOwnedSlice(),
        .fs_permissions = try permission_info.fs_permissions.toOwnedSlice(),
        .net_permissions = try permission_info.net_permissions.toOwnedSlice(),
        .process_spawn = permission_info.process_spawn,
        .process_exec_permissions = try permission_info.process_exec_permissions.toOwnedSlice(),
        .native_link = try permission_info.native_link.toOwnedSlice(),
        .permission_digest = permission_info.digest,
        .external_urls = try permission_info.urls.toOwnedSlice(),
        .requires_sandbox = permission_info.requires_sandbox,
        .has_fs_permission = permission_info.has_fs_permission,
        .has_net_permission = permission_info.has_net_permission,
        .has_env_permission = permission_info.has_env_permission,
        .has_process_permission = permission_info.has_process_permission,
        .has_native_link_permission = permission_info.has_native_link_permission,
        .kind = kind,
        .language_extensions = language_extensions,
        .commands = commands,
    };
}
