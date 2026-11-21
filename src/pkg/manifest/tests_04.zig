const std = @import("std");
const Capability = @import("mergeworkspacememberset.zig").Capability;
const Manifest = @import("mergeworkspacememberset.zig").Manifest;
const ParseError = @import("mergeworkspacememberset.zig").ParseError;
const max_manifest_bytes = @import("mergeworkspacememberset.zig").max_manifest_bytes;
const mergeWorkspaceManifests = @import("mergeworkspacememberset.zig").mergeWorkspaceManifests;
const mergeWorkspaceMemberSet = @import("mergeworkspacememberset.zig").mergeWorkspaceMemberSet;
const packageDeclEqual = @import("mergeworkspacememberset.zig").packageDeclEqual;
const parseLock = @import("parsemanifestwithfile.zig").parseLock;
const parseManifest = @import("parsemanifestwithfile.zig").parseManifest;
const parseManifestWithFile = @import("parsemanifestwithfile.zig").parseManifestWithFile;
const parseSum = @import("parsemanifestwithfile.zig").parseSum;
const parseTextValue = @import("permissionsetbuilder.zig").parseTextValue;
const writeLock = @import("parsemanifestwithfile.zig").writeLock;
const writeManifest = @import("parsemanifestwithfile.zig").writeManifest;
const writeSum = @import("parsemanifestwithfile.zig").writeSum;


test "manifest parser preserves requires and mirrors" {
    const source =
        \\require github.com/xiaoming/sa-ecs @v1.2.0 sha256:0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef
        \\require github.com/org/sa-net @main sha256:fedcba9876543210fedcba9876543210fedcba9876543210fedcba9876543210 grants [net_tx, net_rx]
        \\
        \\[mirrors]
        \\github.com = gitlab.corp.local/mirror
    ;

    var manifest = try parseManifestWithFile(std.testing.allocator, source, "pkg/sa.mod");
    defer manifest.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 2), manifest.requires.len);
    try std.testing.expectEqual(@as(usize, 1), manifest.mirrors.len);
    try std.testing.expectEqualStrings("github.com/xiaoming/sa-ecs", manifest.requires[0].url);
    try std.testing.expectEqualStrings("v1.2.0", manifest.requires[0].ref);
    try std.testing.expectEqualStrings("pkg/sa.mod", manifest.requires[0].upstream_loc.file);
    try std.testing.expectEqual(@as(u32, 1), manifest.requires[0].upstream_loc.line);
    try std.testing.expectEqual(@as(u32, 1), manifest.requires[0].upstream_loc.col);
    try std.testing.expectEqual(@as(usize, 0), manifest.requires[0].grants.len);
    try std.testing.expectEqual(@as(usize, 2), manifest.requires[1].grants.len);
    try std.testing.expectEqual(Capability.net_tx, manifest.requires[1].grants[0]);
    try std.testing.expectEqual(Capability.net_rx, manifest.requires[1].grants[1]);

    var out = std.array_list.Managed(u8).init(std.testing.allocator);
    defer out.deinit();
    {
        var aw: std.Io.Writer.Allocating = .init(std.testing.allocator);
        defer aw.deinit();
        try writeManifest(&aw.writer, manifest);
        try out.appendSlice(aw.written());
    }

    var manifest2 = try parseManifestWithFile(std.testing.allocator, out.items, "pkg/sa.mod");
    defer manifest2.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(usize, 2), manifest2.requires.len);
    try std.testing.expectEqualStrings(manifest.requires[1].url, manifest2.requires[1].url);
}

test "manifest parser decodes escaped text and comma-containing lists" {
    const decoded = try parseTextValue(std.testing.allocator, "\"a,b\\n\\t\\\\\\\"\"");
    defer std.testing.allocator.free(decoded);
    try std.testing.expectEqualStrings("a,b\n\t\\\"", decoded);
    try std.testing.expectError(ParseError.InvalidFormat, parseTextValue(std.testing.allocator, "\"unterminated"));

    const source =
        \\package "quoted" # inline comment
        \\permission_set default {
        \\  env ["A,B", "C"]
        \\  read ["path with spaces", "other"]
        \\}
    ;
    var manifest = try parseManifestWithFile(std.testing.allocator, source, "pkg/sa.mod");
    defer manifest.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 1), manifest.permission_sets.len);
    try std.testing.expectEqualStrings("A,B", manifest.permission_sets[0].env[0]);
    try std.testing.expectEqualStrings("C", manifest.permission_sets[0].env[1]);
    try std.testing.expectEqualStrings("path with spaces", manifest.permission_sets[0].read[0]);
}

test "manifest parser accepts assignment separators and trailing list commas" {
    const source =
        \\package {
        \\  name = "assigned"
        \\  version: "0.2.0"
        \\  abi = 9
        \\  features: ["core", "windows",]
        \\}
        \\permission_set dev {
        \\  env: ["HOME",]
        \\  read = ["/tmp",]
        \\}
        \\require github.com/acme/lib @main sha256:0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef grants [net_tx,]
    ;

    var manifest = try parseManifestWithFile(std.testing.allocator, source, "pkg/sa.mod");
    defer manifest.deinit(std.testing.allocator);

    try std.testing.expectEqualStrings("assigned", manifest.package_decl.?.name);
    try std.testing.expectEqualStrings("0.2.0", manifest.package_decl.?.version.?);
    try std.testing.expectEqual(@as(u32, 9), manifest.package_decl.?.abi.?);
    try std.testing.expectEqual(@as(usize, 2), manifest.package_decl.?.features.len);
    try std.testing.expectEqual(@as(usize, 1), manifest.permission_sets.len);
    try std.testing.expectEqualStrings("HOME", manifest.permission_sets[0].env[0]);
    try std.testing.expectEqual(@as(usize, 1), manifest.requires[0].grants.len);
    try std.testing.expectEqual(Capability.net_tx, manifest.requires[0].grants[0]);
}

test "manifest parser rejects interior empty list elements" {
    try std.testing.expectError(ParseError.InvalidFormat, parseManifest(
        std.testing.allocator,
        "permission_set dev {\n  env [\"HOME\",,]\n}\n",
    ));
}

test "manifest parser preserves package and workspace declarations" {
    const source =
        \\package "root"
        \\
        \\workspace {
        \\  members ["crates/app", "crates/tool"]
        \\  default_member "app"
        \\}
        \\
        \\require github.com/org/sa-net @main sha256:fedcba9876543210fedcba9876543210fedcba9876543210fedcba9876543210
    ;

    var parsed = try parseManifestWithFile(std.testing.allocator, source, "pkg/sa.mod");
    defer parsed.deinit(std.testing.allocator);

    try std.testing.expect(parsed.package_decl != null);
    try std.testing.expectEqualStrings("root", parsed.package_decl.?.name);
    try std.testing.expect(parsed.workspace != null);
    try std.testing.expectEqual(@as(usize, 2), parsed.workspace.?.members.len);
    try std.testing.expectEqualStrings("crates/app", parsed.workspace.?.members[0]);
    try std.testing.expectEqualStrings("crates/tool", parsed.workspace.?.members[1]);
    try std.testing.expectEqualStrings("app", parsed.workspace.?.default_member.?);

    var out = std.array_list.Managed(u8).init(std.testing.allocator);
    defer out.deinit();
    {
        var aw: std.Io.Writer.Allocating = .init(std.testing.allocator);
        defer aw.deinit();
        try writeManifest(&aw.writer, parsed);
        try out.appendSlice(aw.written());
    }

    var reparsed = try parseManifestWithFile(std.testing.allocator, out.items, "pkg/sa.mod");
    defer reparsed.deinit(std.testing.allocator);
    try std.testing.expect(reparsed.package_decl != null);
    try std.testing.expect(reparsed.workspace != null);
    try std.testing.expectEqualStrings("root", reparsed.package_decl.?.name);
    try std.testing.expectEqualStrings("app", reparsed.workspace.?.default_member.?);
}

test "manifest parser preserves package metadata block" {
    const source =
        \\package {
        \\  name "sa_std"
        \\  version "0.1.0"
        \\  abi 7
        \\  features ["core", "with,comma"]
        \\}
    ;

    var parsed = try parseManifestWithFile(std.testing.allocator, source, "pkg/sa.mod");
    defer parsed.deinit(std.testing.allocator);
    try std.testing.expect(parsed.package_decl != null);
    try std.testing.expectEqualStrings("sa_std", parsed.package_decl.?.name);
    try std.testing.expectEqualStrings("0.1.0", parsed.package_decl.?.version.?);
    try std.testing.expectEqual(@as(?u32, 7), parsed.package_decl.?.abi);
    try std.testing.expectEqual(@as(usize, 2), parsed.package_decl.?.features.len);
    try std.testing.expectEqualStrings("with,comma", parsed.package_decl.?.features[1]);

    var out = std.array_list.Managed(u8).init(std.testing.allocator);
    defer out.deinit();
    {
        var aw: std.Io.Writer.Allocating = .init(std.testing.allocator);
        defer aw.deinit();
        try writeManifest(&aw.writer, parsed);
        try out.appendSlice(aw.written());
    }
    var reparsed = try parseManifestWithFile(std.testing.allocator, out.items, "pkg/sa.mod");
    defer reparsed.deinit(std.testing.allocator);
    try std.testing.expect(reparsed.package_decl != null);
    try std.testing.expect(packageDeclEqual(parsed.package_decl.?, reparsed.package_decl.?));
}

test "mergeWorkspaceManifests combines workspace root and member metadata" {
    const root_source =
        \\workspace {
        \\  members ["members/app"]
        \\  default_member "app"
        \\}
        \\
        \\require github.com/acme/shared @v1 sha256:1111111111111111111111111111111111111111111111111111111111111111
        \\require_plugin ../plugins/sa_plugin_demo @0.1.0 abi 1
        \\
        \\permission_set dev {
        \\  env [HOME]
        \\  read [/tmp]
        \\  write []
        \\  net [https://api.example.com]
        \\  run [/usr/bin/env]
        \\}
        \\
        \\[mirrors]
        \\github.com = mirror.local/github
    ;
    const member_source =
        \\package "app"
        \\
        \\require github.com/acme/app @v2 sha256:2222222222222222222222222222222222222222222222222222222222222222
    ;

    var root_manifest = try parseManifestWithFile(std.testing.allocator, root_source, "root/sa.mod");
    defer root_manifest.deinit(std.testing.allocator);
    var member_manifest = try parseManifestWithFile(std.testing.allocator, member_source, "root/members/app/sa.mod");
    defer member_manifest.deinit(std.testing.allocator);

    var merged = try mergeWorkspaceManifests(std.testing.allocator, &root_manifest, &member_manifest);
    defer merged.deinit(std.testing.allocator);

    try std.testing.expect(merged.package_decl != null);
    try std.testing.expectEqualStrings("app", merged.package_decl.?.name);
    try std.testing.expect(merged.workspace == null);
    try std.testing.expectEqual(@as(usize, 2), merged.requires.len);
    try std.testing.expectEqual(@as(usize, 1), merged.plugin_requires.len);
    try std.testing.expectEqual(@as(usize, 1), merged.permission_sets.len);
    try std.testing.expectEqual(@as(usize, 1), merged.mirrors.len);
}

test "mergeWorkspaceMemberSet deduplicates shared member dependencies for workspace install" {
    const root_source =
        \\workspace {
        \\  members ["members/app", "members/tool"]
        \\  default_member "app"
        \\}
        \\
        \\require github.com/acme/shared @v1 sha256:1111111111111111111111111111111111111111111111111111111111111111
        \\require_plugin ../plugins/shared @0.1.0 abi 1
    ;
    const app_source =
        \\package "app"
        \\
        \\require github.com/acme/common @v1 sha256:2222222222222222222222222222222222222222222222222222222222222222
        \\require_plugin ../plugins/shared @0.1.0 abi 1
    ;
    const tool_source =
        \\package "tool"
        \\
        \\require github.com/acme/common @v1 sha256:2222222222222222222222222222222222222222222222222222222222222222
        \\require github.com/acme/tool @v1 sha256:3333333333333333333333333333333333333333333333333333333333333333
    ;

    var root_manifest = try parseManifestWithFile(std.testing.allocator, root_source, "root/sa.mod");
    defer root_manifest.deinit(std.testing.allocator);
    var app_manifest = try parseManifestWithFile(std.testing.allocator, app_source, "root/members/app/sa.mod");
    defer app_manifest.deinit(std.testing.allocator);
    var tool_manifest = try parseManifestWithFile(std.testing.allocator, tool_source, "root/members/tool/sa.mod");
    defer tool_manifest.deinit(std.testing.allocator);

    const members = [_]*const Manifest{ &app_manifest, &tool_manifest };
    var merged = try mergeWorkspaceMemberSet(std.testing.allocator, &root_manifest, members[0..]);
    defer merged.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 3), merged.requires.len);
    try std.testing.expectEqual(@as(usize, 1), merged.plugin_requires.len);
    try std.testing.expectEqual(@as(usize, 0), merged.permission_sets.len);
}

test "manifest parser rejects oversized source" {
    const source = try std.testing.allocator.alloc(u8, max_manifest_bytes + 1);
    defer std.testing.allocator.free(source);
    @memset(source, ' ');

    try std.testing.expectError(ParseError.InvalidFormat, parseManifestWithFile(std.testing.allocator, source, "pkg/sa.mod"));
}

test "lock parser preserves dependency blocks and target hashes" {
    const source =
        \\dependency "github.com/hacker/bad-lib" {
        \\    version: "v1.2.0"
        \\    source_sha: "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"
        \\    approved_machine_code_hashes {
        \\        x86_64-linux-gnu = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
        \\        default = "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
        \\    }
        \\    acknowledged_at_utc: 42
        \\    acknowledged_target_count: 2
        \\}
    ;

    var lock_file = try parseLock(std.testing.allocator, source);
    defer lock_file.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 1), lock_file.entries.len);
    const entry = lock_file.entries[0];
    try std.testing.expectEqualStrings("github.com/hacker/bad-lib", entry.url);
    try std.testing.expectEqualStrings("v1.2.0", entry.ref);
    try std.testing.expectEqual(@as(u8, 2), entry.acknowledged_target_count);
    try std.testing.expectEqual(@as(i64, 42), entry.acknowledged_at_utc);
    try std.testing.expectEqual(@as(usize, 2), entry.approved_machine_code_hashes.count());
    try std.testing.expect(entry.approved_machine_code_hashes.contains("x86_64-linux-gnu"));
    try std.testing.expect(entry.approved_machine_code_hashes.contains(""));

    var out = std.array_list.Managed(u8).init(std.testing.allocator);
    defer out.deinit();
    {
        var aw: std.Io.Writer.Allocating = .init(std.testing.allocator);
        defer aw.deinit();
        try writeLock(&aw.writer, lock_file);
        try out.appendSlice(aw.written());
    }

    var lock_file2 = try parseLock(std.testing.allocator, out.items);
    defer lock_file2.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(usize, 1), lock_file2.entries.len);
    try std.testing.expectEqualStrings(lock_file.entries[0].url, lock_file2.entries[0].url);
}

test "sum parser preserves depth and sha256" {
    const source =
        \\github.com/xiaoming/sa-ecs @v1.2.0 sha256:0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef
        \\github.com/transitive/dep @v0.1.0 sha256:fedcba9876543210fedcba9876543210fedcba9876543210fedcba9876543210 depth: 2
    ;

    var sum_file = try parseSum(std.testing.allocator, source);
    defer sum_file.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 2), sum_file.entries.len);
    try std.testing.expectEqual(@as(u32, 2), sum_file.entries[1].depth);

    var out = std.array_list.Managed(u8).init(std.testing.allocator);
    defer out.deinit();
    {
        var aw: std.Io.Writer.Allocating = .init(std.testing.allocator);
        defer aw.deinit();
        try writeSum(&aw.writer, sum_file);
        try out.appendSlice(aw.written());
    }

    var sum_file2 = try parseSum(std.testing.allocator, out.items);
    defer sum_file2.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(usize, 2), sum_file2.entries.len);
    try std.testing.expectEqual(@as(u32, 2), sum_file2.entries[1].depth);
}
