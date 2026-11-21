const std = @import("std");
const sio = @import("sio");
const CompileOptions = @import("types.zig").CompileOptions;
const DiagnosticsMode = @import("types.zig").DiagnosticsMode;
const SkillSection = @import("types.zig").SkillSection;
const trap = @import("../common/trap.zig");
const SaStdSurface = @import("types.zig").SaStdSurface;
const SaPluginsSurface = @import("types.zig").SaPluginsSurface;
const plugins = @import("../plugins.zig");
const AgentSkillPaths = @import("types.zig").AgentSkillPaths;
const freeOwnedStringSlice = @import("compile.zig").freeOwnedStringSlice;
const writeJsonString = @import("json.zig").writeJsonString;
const stdRootFromEnv = @import("cache.zig").stdRootFromEnv;
const writeJsonStringArray = @import("json.zig").writeJsonStringArray;
const dirExistsAbsolute = @import("compile.zig").dirExistsAbsolute;
const build_options = @import("build_options");

pub fn skillsCommand(allocator: std.mem.Allocator, writer: anytype, json_mode: bool) !u8 {
    const base_sections = [_]SkillSection{
        .{ .name = "core diagnostics", .summary = "Agent-facing error handling and JSON reports", .items = &.{
            "stable trap names and trap codes",
            "structured JSON diagnostics with repair hints",
            "human and JSON output modes remain aligned",
        } },
        .{ .name = "cli toolchain", .summary = "Agent-first CLI entry points", .items = &.{
            "init [path]",
            "pkg install [identity]",
            "explain <code>",
            "fix --plan --json",
            "skills",
            "check <file>",
            "test --affected",
            "daemon",
        } },
        .{ .name = "project lifecycle", .summary = "Rust-like project setup and local builds", .items = &.{
            "init [path]",
            "pkg install",
            "build src/main.sa",
            "run src/main.sa",
            "test <file>",
        } },
        .{ .name = "std runtime", .summary = "Current Zig-backed facade surface", .items = &.{
            "Rust-style string/vec/slice/option/result/core helper macros",
            "fs/env/process/io/time/net/sync facades over the compiler runtime",
            "JSON DOM, regex, formatting, path, and terminal facades",
            "optional deno/http/node/db/plugin APIs stay outside compiler std",
        } },
    };
    var sections_list = std.array_list.Managed(SkillSection).init(allocator);
    errdefer sections_list.deinit();
    try sections_list.appendSlice(base_sections[0..]);
    // Diagnostic catalog: expose all verifier/flattener traps (name + stable
    // code) so Agents can discover the full diagnostic surface. Items live for
    // the function scope; sections are rendered before this list is freed.
    var trap_items = std.array_list.Managed([]const u8).init(allocator);
    defer {
        for (trap_items.items) |it| allocator.free(it);
        trap_items.deinit();
    }
    for (trap.allTraps()) |t| {
        const it = std.fmt.allocPrint(allocator, "{s} ({s})", .{ trap.trapName(t), trap.trapStableCode(t) }) catch continue;
        trap_items.append(it) catch continue;
    }
    try sections_list.append(.{ .name = "diagnostic catalog", .summary = "All verifier/flattener traps; use sa explain <name|code> for details", .items = trap_items.items });
    var plugin_runtime = try plugins.Runtime.initFromEnv(allocator);
    defer plugin_runtime.deinit();
    try plugin_runtime.appendSkills(&sections_list);
    const sections = try sections_list.toOwnedSlice();
    defer allocator.free(sections);

    if (json_mode) {
        try writeSkillsJson(writer, sections);
    } else {
        const std_root = try stdRootFromEnv(allocator);
        defer allocator.free(std_root);
        const surface = try collectSaStdSurface(allocator, std_root);
        defer surface.deinit(allocator);
        const plugins_surface = try collectOfficialSaPluginsSurface(allocator);
        defer plugins_surface.deinit(allocator);
        const skill_paths = try writeSaAgentSkills(allocator, std_root, sections, surface, plugins_surface);
        defer skill_paths.deinit(allocator);

        try writer.writeAll("agent-first toolchain\n");
        try writer.print("generated agent skills:\n- {s}\n- {s}\n- {s}\n- {s}\n", .{ skill_paths.sa_codex, skill_paths.sa_claude, skill_paths.plugins_codex, skill_paths.plugins_claude });
        try writer.print("std surface: {d} files, {d} macros, {d} extern/export declarations\n", .{ surface.files.len, surface.macros.len, surface.externs.len });
        try writer.print("official plugin catalog: {d} common plugins, {d} interface declarations; availability still depends on local installation\n", .{ plugins_surface.plugins.len, plugins_surface.declarations.len });
        for (sections) |section| {
            try writeSkillSectionText(writer, section.name, section.summary, section.items);
        }
    }
    return 0;
}

pub fn writeSaAgentSkills(
    allocator: std.mem.Allocator,
    std_root: []const u8,
    sections: []const SkillSection,
    surface: SaStdSurface,
    plugins_surface: SaPluginsSurface,
) !AgentSkillPaths {
    const sa_codex_dir = ".codex/skills/sa";
    const sa_claude_dir = ".claude/skills/sa";
    const plugins_codex_dir = ".codex/skills/sa_plugins";
    const plugins_claude_dir = ".claude/skills/sa_plugins";
    const sa_codex_path = ".codex/skills/sa/SKILL.md";
    const sa_claude_path = ".claude/skills/sa/SKILL.md";
    const plugins_codex_path = ".codex/skills/sa_plugins/SKILL.md";
    const plugins_claude_path = ".claude/skills/sa_plugins/SKILL.md";

    try sio.cwd().makePath(sa_codex_dir);
    try sio.cwd().makePath(sa_claude_dir);
    try sio.cwd().makePath(plugins_codex_dir);
    try sio.cwd().makePath(plugins_claude_dir);

    {
        var file = try sio.cwd().createFile(sa_codex_path, .{ .truncate = true });
        defer file.close();
        var fbuf: [8192]u8 = undefined;
        var fw = file.writer(&fbuf);
        try writeSaAgentSkillMarkdown(&fw.interface, "codex", std_root, sections, surface);
        try fw.interface.flush();
    }
    {
        var file = try sio.cwd().createFile(sa_claude_path, .{ .truncate = true });
        defer file.close();
        var fbuf: [8192]u8 = undefined;
        var fw = file.writer(&fbuf);
        try writeSaAgentSkillMarkdown(&fw.interface, "claude", std_root, sections, surface);
        try fw.interface.flush();
    }
    {
        var file = try sio.cwd().createFile(plugins_codex_path, .{ .truncate = true });
        defer file.close();
        var fbuf: [8192]u8 = undefined;
        var fw = file.writer(&fbuf);
        try writeSaPluginsAgentSkillMarkdown(&fw.interface, "codex", plugins_surface);
        try fw.interface.flush();
    }
    {
        var file = try sio.cwd().createFile(plugins_claude_path, .{ .truncate = true });
        defer file.close();
        var fbuf: [8192]u8 = undefined;
        var fw = file.writer(&fbuf);
        try writeSaPluginsAgentSkillMarkdown(&fw.interface, "claude", plugins_surface);
        try fw.interface.flush();
    }

    return .{
        .sa_codex = try allocator.dupe(u8, sa_codex_path),
        .sa_claude = try allocator.dupe(u8, sa_claude_path),
        .plugins_codex = try allocator.dupe(u8, plugins_codex_path),
        .plugins_claude = try allocator.dupe(u8, plugins_claude_path),
    };
}

pub const writeSaAgentSkillMarkdown = @import("skill_writer.zig").writeSaAgentSkillMarkdown;

pub fn appendOfficialPluginInfo(
    allocator: std.mem.Allocator,
    plugins_list: *std.array_list.Managed([]const u8),
    declarations: *std.array_list.Managed([]const u8),
    notes: *std.array_list.Managed([]const u8),
    root_dir: sio.Dir,
    root_path: []const u8,
    dir_name: []const u8,
) !void {
    var plugin_dir = try root_dir.openDir(dir_name, .{ .iterate = true });
    defer plugin_dir.close();

    const manifest_source = plugin_dir.readFileAlloc(allocator, "sap.json", 1024 * 1024) catch |err| switch (err) {
        error.FileNotFound => return,
        else => return err,
    };
    defer allocator.free(manifest_source);
    var parsed = try std.json.parseFromSlice(std.json.Value, allocator, manifest_source, .{});
    defer parsed.deinit();
    const object = switch (parsed.value) {
        .object => |obj| obj,
        else => return,
    };
    const manifest_name = switch (object.get("name") orelse return) {
        .string => |s| s,
        else => return,
    };
    if (!isCommonOfficialPluginName(manifest_name) and !isCommonOfficialPluginName(dir_name)) return;

    const version = if (object.get("version")) |version_value| switch (version_value) {
        .string => |s| s,
        else => "unknown",
    } else "unknown";
    const doc_summary = try appendDocSummary(allocator, notes, plugin_dir);
    const skills = try appendJsonStringArrayToCsv(allocator, notes, object.get("skills"));
    const interfaces = try appendJsonInterfaceSummary(allocator, notes, object.get("interfaces"));
    const dependencies = try appendJsonObjectKeysToCsv(allocator, notes, object.get("dependencies"));
    const permissions = try appendPermissionSummary(allocator, notes, object.get("permissions"));
    const plugin_path = try std.fs.path.join(allocator, &.{ root_path, dir_name });
    defer allocator.free(plugin_path);

    try plugins_list.append(try std.fmt.allocPrint(
        allocator,
        "{s} ({s}) from `{s}`: {s} Skills: {s}. Interfaces: {s}. Dependencies: {s}. Permissions: {s}. Optional plugin: install before use with `SA_PLUGIN_DEV=1 sa plugin install --dev {s}`, then verify availability with `sa plugin list` or `sa skills --json`.",
        .{ manifest_name, version, dir_name, doc_summary, skills, interfaces, dependencies, permissions, plugin_path },
    ));

    try appendPluginDeclarations(allocator, declarations, manifest_name, dir_name, plugin_dir);
}

pub fn collectOfficialSaPluginsSurface(allocator: std.mem.Allocator) !SaPluginsSurface {
    var plugins_list = std.array_list.Managed([]const u8).init(allocator);
    var declarations = std.array_list.Managed([]const u8).init(allocator);
    var notes = std.array_list.Managed([]const u8).init(allocator);
    var plugins_slice: ?[]const []const u8 = null;
    var declarations_slice: ?[]const []const u8 = null;
    var notes_slice: ?[]const []const u8 = null;
    var root_owned: ?[]u8 = null;
    errdefer {
        if (root_owned) |root| allocator.free(root);
        if (plugins_slice) |items| freeOwnedStringSlice(allocator, items) else freeStringArrayListItems(allocator, &plugins_list);
        if (declarations_slice) |items| freeOwnedStringSlice(allocator, items) else freeStringArrayListItems(allocator, &declarations);
        if (notes_slice) |items| freeOwnedStringSlice(allocator, items) else freeStringArrayListItems(allocator, &notes);
    }

    root_owned = try officialPluginsRootFromEnv(allocator);
    if (root_owned) |root_path| {
        var root_dir = try sio.openDirAbsolute(root_path, .{ .iterate = true });
        defer root_dir.close();
        var it = root_dir.iterate();
        while (try it.next()) |entry| {
            if (entry.kind != .directory and entry.kind != .sym_link) continue;
            if (!std.mem.startsWith(u8, entry.name, "sa_plugin_")) continue;
            try appendOfficialPluginInfo(allocator, &plugins_list, &declarations, &notes, root_dir, root_path, entry.name);
        }
    }

    std.mem.sort([]const u8, plugins_list.items, {}, stringSliceLessThan);
    std.mem.sort([]const u8, declarations.items, {}, stringSliceLessThan);
    plugins_slice = try plugins_list.toOwnedSlice();
    declarations_slice = try declarations.toOwnedSlice();
    notes_slice = try notes.toOwnedSlice();

    const result = SaPluginsSurface{
        .root = root_owned,
        .plugins = plugins_slice.?,
        .declarations = declarations_slice.?,
        .notes = notes_slice.?,
    };
    root_owned = null;
    plugins_slice = null;
    declarations_slice = null;
    notes_slice = null;
    return result;
}

pub fn isCommonOfficialPluginName(name: []const u8) bool {
    const normalized = if (std.mem.startsWith(u8, name, "sa_plugin_")) name["sa_plugin_".len..] else name;
    for (common_official_plugins) |candidate| {
        if (std.mem.eql(u8, normalized, candidate)) return true;
        if (std.mem.eql(u8, name, candidate)) return true;
    }
    return false;
}

pub fn appendDocSummary(
    allocator: std.mem.Allocator,
    list: *std.array_list.Managed([]const u8),
    plugin_dir: sio.Dir,
) ![]const u8 {
    const doc_names = [_][]const u8{ "README.md", "api.md", "AGENTS.md" };
    for (doc_names) |doc_name| {
        const source = plugin_dir.readFileAlloc(allocator, doc_name, 128 * 1024) catch |err| switch (err) {
            error.FileNotFound => continue,
            else => return err,
        };
        defer allocator.free(source);
        var lines = std.mem.splitScalar(u8, source, '\n');
        while (lines.next()) |raw_line| {
            const line = std.mem.trim(u8, raw_line, " \t\r");
            if (line.len == 0) continue;
            if (std.mem.startsWith(u8, line, "#")) continue;
            if (std.mem.startsWith(u8, line, "---")) continue;
            if (std.mem.startsWith(u8, line, "```")) continue;
            const owned = try allocator.dupe(u8, line);
            try list.append(owned);
            return owned;
        }
    }
    const owned = try allocator.dupe(u8, "No README summary found; inspect the plugin manifest and interface files before using it.");
    try list.append(owned);
    return owned;
}

pub const common_official_plugins = [_][]const u8{
    "bc2sa",
    "db",
    "deno",
    "http-client",
    "http-server",
    "node",
    "pkg",
    "sax",
    "vm",
};

pub const writeFrontmatterField = @import("skill_writer.zig").writeFrontmatterField;

pub fn writeSkillsJson(writer: anytype, sections: []const SkillSection) !void {
    try writer.writeByte('{');
    try writer.writeAll("\"status\":\"ok\",\"skills\":[");
    for (sections, 0..) |section, idx| {
        if (idx != 0) try writer.writeByte(',');
        try writer.writeByte('{');
        try writer.writeAll("\"name\":");
        try writeJsonString(writer, section.name);
        try writer.writeAll(",\"summary\":");
        try writeJsonString(writer, section.summary);
        try writer.writeAll(",\"items\":");
        try writeJsonStringArray(writer, section.items);
        try writer.writeByte('}');
    }
    try writer.writeAll("]}\n");
}

pub const writeMarkdownCodeList = @import("skill_writer.zig").writeMarkdownCodeList;

pub fn appendJsonStringArrayToCsv(
    allocator: std.mem.Allocator,
    list: *std.array_list.Managed([]const u8),
    value: ?std.json.Value,
) ![]const u8 {
    var scratch = std.array_list.Managed([]const u8).init(allocator);
    defer scratch.deinit();
    if (value) |v| switch (v) {
        .array => |arr| {
            for (arr.items) |item| switch (item) {
                .string => |text| try scratch.append(text),
                else => {},
            };
        },
        else => {},
    };
    if (scratch.items.len == 0) {
        const owned = try allocator.dupe(u8, "none");
        try list.append(owned);
        return owned;
    }
    const owned = try std.mem.join(allocator, ", ", scratch.items);
    try list.append(owned);
    return owned;
}

pub fn writeSaPluginsAgentSkillMarkdown(
    writer: anytype,
    agent_name: []const u8,
    surface: SaPluginsSurface,
) !void {
    const description = if (std.mem.eql(u8, agent_name, "claude"))
        "Use the optional official SA plugin catalog from Claude without assuming plugins are installed."
    else
        "Use the optional official SA plugin catalog from Codex without assuming plugins are installed.";
    try writer.writeAll("---\n");
    try writeFrontmatterField(writer, "name", "sa_plugins");
    try writeFrontmatterField(writer, "description", description);
    try writeFrontmatterField(writer, "when_to_use", "Use when a task mentions optional SA plugins such as deno, http-client, http-server, node, pkg, db, sax, bc2sa, or vm. Always verify installation before using plugin APIs.");
    try writer.writeAll("---\n\n");

    try writer.writeAll("# SA Optional Plugins\n\n");
    try writer.writeAll("## Rules\n");
    try writer.writeAll("- This file is a catalog of common official plugins, not proof that any plugin is installed.\n");
    try writer.writeAll("- Run `sa plugin list` to inspect installed plugins before using plugin commands or imports.\n");
    try writer.writeAll("- Run `sa skills --json` to inspect capability sections exported by currently loaded plugins.\n");
    try writer.writeAll("- Install a needed local official plugin with `SA_PLUGIN_DEV=1 sa plugin install --dev <plugin-dir>`; plugin dependencies may need to be installed first or declared in `sap.json`.\n");
    try writer.writeAll("- Keep these APIs out of compiler `sa_std`; plugin availability is per environment and can change.\n\n");

    try writer.writeAll("## Source\n");
    if (surface.root) |root| {
        try writer.print("Generated from optional plugin workspace `{s}`.\n", .{root});
    } else {
        try writer.writeAll("No official plugin workspace was found. Set `SA_PLUGINS_WORKSPACE` or keep `/home/vscode/projects/sa_plugins` beside the compiler checkout to populate this catalog.\n");
    }
    try writer.print("- common plugins listed: `{d}`\n", .{surface.plugins.len});
    try writer.print("- interface declarations listed: `{d}`\n\n", .{surface.declarations.len});

    try writer.writeAll("## Common Official Plugins\n");
    try writeMarkdownTextList(writer, surface.plugins);
    try writer.writeAll("\n## Interface Declarations\n");
    try writeMarkdownCodeList(writer, surface.declarations);
}

pub fn collectSaStdSurface(allocator: std.mem.Allocator, std_root: []const u8) !SaStdSurface {
    var files = std.array_list.Managed([]const u8).init(allocator);
    var macros = std.array_list.Managed([]const u8).init(allocator);
    var externs = std.array_list.Managed([]const u8).init(allocator);
    var files_slice: ?[]const []const u8 = null;
    var macros_slice: ?[]const []const u8 = null;
    var externs_slice: ?[]const []const u8 = null;
    errdefer {
        if (files_slice) |items| freeOwnedStringSlice(allocator, items) else freeStringArrayListItems(allocator, &files);
        if (macros_slice) |items| freeOwnedStringSlice(allocator, items) else freeStringArrayListItems(allocator, &macros);
        if (externs_slice) |items| freeOwnedStringSlice(allocator, items) else freeStringArrayListItems(allocator, &externs);
    }

    var root = try sio.cwd().openDir(std_root, .{ .iterate = true });
    defer root.close();

    var walker = try root.walk(allocator);
    defer walker.deinit();
    while (try walker.next()) |entry| {
        if (entry.kind != .file) continue;
        if (!isSaStdSurfaceFile(entry.path)) continue;

        const rel_path = try normalizeSkillPathAlloc(allocator, entry.path);
        errdefer allocator.free(rel_path);
        try files.append(rel_path);

        const source = try root.readFileAlloc(allocator, entry.path, 16 * 1024 * 1024);
        defer allocator.free(source);
        try appendStdDeclarations(allocator, &macros, &externs, rel_path, source);
    }

    std.mem.sort([]const u8, files.items, {}, stringSliceLessThan);
    std.mem.sort([]const u8, macros.items, {}, stringSliceLessThan);
    std.mem.sort([]const u8, externs.items, {}, stringSliceLessThan);

    files_slice = try files.toOwnedSlice();
    macros_slice = try macros.toOwnedSlice();
    externs_slice = try externs.toOwnedSlice();

    const result = SaStdSurface{
        .files = files_slice.?,
        .macros = macros_slice.?,
        .externs = externs_slice.?,
    };
    files_slice = null;
    macros_slice = null;
    externs_slice = null;
    return result;
}

pub fn appendJsonInterfaceSummary(
    allocator: std.mem.Allocator,
    list: *std.array_list.Managed([]const u8),
    value: ?std.json.Value,
) ![]const u8 {
    var scratch = std.array_list.Managed([]const u8).init(allocator);
    defer scratch.deinit();
    if (value) |v| switch (v) {
        .object => |obj| {
            var it = obj.iterator();
            while (it.next()) |entry| {
                const key = entry.key_ptr.*;
                switch (entry.value_ptr.*) {
                    .string => |path| try scratch.append(try std.fmt.allocPrint(allocator, "{s}:{s}", .{ key, path })),
                    .object => |o| if (o.get("path")) |path_value| switch (path_value) {
                        .string => |path| try scratch.append(try std.fmt.allocPrint(allocator, "{s}:{s}", .{ key, path })),
                        else => {},
                    },
                    .array => |arr| for (arr.items) |item| switch (item) {
                        .string => |path| try scratch.append(try std.fmt.allocPrint(allocator, "{s}:{s}", .{ key, path })),
                        .object => |o| if (o.get("path")) |path_value| switch (path_value) {
                            .string => |path| try scratch.append(try std.fmt.allocPrint(allocator, "{s}:{s}", .{ key, path })),
                            else => {},
                        },
                        else => {},
                    },
                    else => {},
                }
            }
        },
        else => {},
    };
    defer {
        for (scratch.items) |item| allocator.free(item);
    }
    if (scratch.items.len == 0) {
        const owned = try allocator.dupe(u8, "CLI-only or native descriptor only");
        try list.append(owned);
        return owned;
    }
    std.mem.sort([]const u8, scratch.items, {}, stringSliceLessThan);
    const owned = try std.mem.join(allocator, ", ", scratch.items);
    try list.append(owned);
    return owned;
}

pub fn freeStringArrayListItems(allocator: std.mem.Allocator, list: *std.array_list.Managed([]const u8)) void {
    for (list.items) |item| allocator.free(item);
    list.deinit();
}

pub const writeSkillSectionText = @import("skill_writer.zig").writeSkillSectionText;

pub fn appendJsonObjectKeysToCsv(
    allocator: std.mem.Allocator,
    list: *std.array_list.Managed([]const u8),
    value: ?std.json.Value,
) ![]const u8 {
    var scratch = std.array_list.Managed([]const u8).init(allocator);
    defer scratch.deinit();
    if (value) |v| switch (v) {
        .object => |obj| {
            var it = obj.iterator();
            while (it.next()) |entry| try scratch.append(entry.key_ptr.*);
        },
        else => {},
    };
    if (scratch.items.len == 0) {
        const owned = try allocator.dupe(u8, "none");
        try list.append(owned);
        return owned;
    }
    std.mem.sort([]const u8, scratch.items, {}, stringSliceLessThan);
    const owned = try std.mem.join(allocator, ", ", scratch.items);
    try list.append(owned);
    return owned;
}

pub fn appendPermissionSummary(
    allocator: std.mem.Allocator,
    list: *std.array_list.Managed([]const u8),
    value: ?std.json.Value,
) ![]const u8 {
    const obj = if (value) |v| switch (v) {
        .object => |o| o,
        else => null,
    } else null;
    if (obj == null) {
        const owned = try allocator.dupe(u8, "no manifest permissions declared");
        try list.append(owned);
        return owned;
    }
    const o = obj.?;
    const fs_count = if (o.get("fs")) |fs_value| switch (fs_value) {
        .array => |arr| arr.items.len,
        else => 0,
    } else 0;
    const net_count = if (o.get("net")) |net_value| switch (net_value) {
        .array => |arr| arr.items.len,
        else => 0,
    } else 0;
    const env_count = if (o.get("env")) |env_value| switch (env_value) {
        .array => |arr| arr.items.len,
        else => 0,
    } else 0;
    const process_spawn = if (o.get("process")) |process_value| switch (process_value) {
        .object => |process_obj| if (process_obj.get("spawn")) |spawn_value| switch (spawn_value) {
            .bool => |b| b,
            else => false,
        } else false,
        else => false,
    } else false;
    const owned = try std.fmt.allocPrint(allocator, "fs:{d}, net:{d}, env:{d}, process_spawn:{s}", .{ fs_count, net_count, env_count, if (process_spawn) "yes" else "no" });
    try list.append(owned);
    return owned;
}

pub fn officialPluginsRootFromEnv(allocator: std.mem.Allocator) !?[]u8 {
    if (dirExistsCwd("sa_plugins")) {
        return try sio.cwd().realpathAlloc(allocator, "sa_plugins");
    }

    const env_root = sio.getEnvVarOwned(allocator, "SA_PLUGINS_WORKSPACE") catch |err| switch (err) {
        error.EnvironmentVariableNotFound => null,
        else => return err,
    };
    if (env_root) |root| {
        defer allocator.free(root);
        if (std.fs.path.isAbsolute(root)) {
            if (dirExistsAbsolute(root)) return try allocator.dupe(u8, root);
        } else if (dirExistsCwd(root)) {
            return try sio.cwd().realpathAlloc(allocator, root);
        }
    }

    if (std.fs.path.dirname(build_options.repo_root)) |parent| {
        const sibling = try std.fs.path.join(allocator, &.{ parent, "sa_plugins" });
        defer allocator.free(sibling);
        if (dirExistsAbsolute(sibling)) return try allocator.dupe(u8, sibling);
    }

    return null;
}

pub fn appendPluginDeclarations(
    allocator: std.mem.Allocator,
    declarations: *std.array_list.Managed([]const u8),
    plugin_name: []const u8,
    plugin_dir_name: []const u8,
    plugin_dir: sio.Dir,
) !void {
    var it = plugin_dir.iterate();
    while (try it.next()) |entry| {
        if (entry.kind != .file and entry.kind != .sym_link) continue;
        if (!pluginInterfaceFileCandidate(entry.name)) continue;
        const source = try plugin_dir.readFileAlloc(allocator, entry.name, 16 * 1024 * 1024);
        defer allocator.free(source);
        var lines = std.mem.splitScalar(u8, source, '\n');
        while (lines.next()) |raw_line| {
            const line = std.mem.trimEnd(u8, raw_line, "\r");
            if (std.mem.startsWith(u8, line, "[MACRO] ") or
                std.mem.startsWith(u8, line, "@extern ") or
                std.mem.startsWith(u8, line, "@export "))
            {
                try declarations.append(try std.fmt.allocPrint(allocator, "{s}/{s}/{s}: {s}", .{ plugin_name, plugin_dir_name, entry.name, line }));
            }
        }
    }
}

pub fn stringSliceLessThan(_: void, lhs: []const u8, rhs: []const u8) bool {
    return std.mem.order(u8, lhs, rhs) == .lt;
}

pub const writeMarkdownTextList = @import("skill_writer.zig").writeMarkdownTextList;

pub fn isSaStdSurfaceFile(path: []const u8) bool {
    if (std.mem.eql(u8, std.fs.path.basename(path), "sa.mod")) return true;
    const ext = std.fs.path.extension(path);
    return std.mem.eql(u8, ext, ".sa") or
        std.mem.eql(u8, ext, ".sal") or
        std.mem.eql(u8, ext, ".sai");
}

pub fn normalizeSkillPathAlloc(allocator: std.mem.Allocator, path: []const u8) ![]u8 {
    const out = try allocator.alloc(u8, path.len);
    for (path, 0..) |c, idx| {
        out[idx] = if (std.fs.path.isSep(c)) '/' else c;
    }
    return out;
}

pub fn dirExistsCwd(path: []const u8) bool {
    var dir = sio.cwd().openDir(path, .{}) catch return false;
    dir.close();
    return true;
}

pub fn pluginInterfaceFileCandidate(path: []const u8) bool {
    const base = std.fs.path.basename(path);
    if (std.mem.eql(u8, base, "expanded.sa")) return false;
    if (std.mem.startsWith(u8, base, "tmp_")) return false;
    if (std.mem.startsWith(u8, base, "_tmp")) return false;
    const ext = std.fs.path.extension(path);
    return std.mem.eql(u8, ext, ".sa") or
        std.mem.eql(u8, ext, ".sal") or
        std.mem.eql(u8, ext, ".sai");
}

pub fn appendStdDeclarations(
    allocator: std.mem.Allocator,
    macros: *std.array_list.Managed([]const u8),
    externs: *std.array_list.Managed([]const u8),
    rel_path: []const u8,
    source: []const u8,
) !void {
    var lines = std.mem.splitScalar(u8, source, '\n');
    while (lines.next()) |raw_line| {
        const line = std.mem.trimEnd(u8, raw_line, "\r");
        if (std.mem.startsWith(u8, line, "[MACRO] ")) {
            try macros.append(try std.fmt.allocPrint(allocator, "{s}: {s}", .{ rel_path, line }));
        } else if (std.mem.startsWith(u8, line, "@extern ") or std.mem.startsWith(u8, line, "@export ")) {
            try externs.append(try std.fmt.allocPrint(allocator, "{s}: {s}", .{ rel_path, line }));
        }
    }
}
