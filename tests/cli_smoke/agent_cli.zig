const std = @import("std");
const saasm = @import("saasm");
const builtin = @import("builtin");
const sio = @import("sio");

const helpers = @import("helpers.zig");
const writeSource = helpers.writeSource;

test "agent-first cli commands print explain fix and skills outputs" {
    var stdout_buffer = std.array_list.Managed(u8).init(std.testing.allocator);
    defer stdout_buffer.deinit();
    var stderr_buffer = std.array_list.Managed(u8).init(std.testing.allocator);
    defer stderr_buffer.deinit();

    const explain_argv = [_][]const u8{ "sa", "explain", "SA-CLI-001" };
    const explain_code = try saasm.cli.executeWithWriters(
        std.testing.allocator,
        explain_argv[0..],
        sio.managedWriter(&stdout_buffer),
        sio.managedWriter(&stderr_buffer),
    );
    try std.testing.expectEqual(@as(u8, 0), explain_code);
    try std.testing.expectEqual(@as(usize, 0), stderr_buffer.items.len);
    try std.testing.expect(std.mem.containsAtLeast(u8, stdout_buffer.items, 1, "code: SA-CLI-001"));
    try std.testing.expect(std.mem.containsAtLeast(u8, stdout_buffer.items, 1, "title: Missing required operand"));
    try std.testing.expect(std.mem.containsAtLeast(u8, stdout_buffer.items, 1, "fix: Pass the required file, path, or operand after the command."));

    stdout_buffer.clearRetainingCapacity();
    stderr_buffer.clearRetainingCapacity();

    const explain_json_argv = [_][]const u8{ "sa", "explain", "SA-CLI-001", "--json" };
    const explain_json_code = try saasm.cli.executeWithWriters(
        std.testing.allocator,
        explain_json_argv[0..],
        sio.managedWriter(&stdout_buffer),
        sio.managedWriter(&stderr_buffer),
    );
    try std.testing.expectEqual(@as(u8, 0), explain_json_code);
    try std.testing.expectEqual(@as(usize, 0), stderr_buffer.items.len);
    try std.testing.expect(std.mem.containsAtLeast(u8, stdout_buffer.items, 1, "\"status\":\"ok\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, stdout_buffer.items, 1, "\"codes\":[\"SA-CLI-001\"]"));

    stdout_buffer.clearRetainingCapacity();
    stderr_buffer.clearRetainingCapacity();

    const fix_argv = [_][]const u8{ "sa", "fix", "--plan", "SA-CLI-001", "--json" };
    const fix_code = try saasm.cli.executeWithWriters(
        std.testing.allocator,
        fix_argv[0..],
        sio.managedWriter(&stdout_buffer),
        sio.managedWriter(&stderr_buffer),
    );
    try std.testing.expectEqual(@as(u8, 0), fix_code);
    try std.testing.expectEqual(@as(usize, 0), stderr_buffer.items.len);
    try std.testing.expect(std.mem.containsAtLeast(u8, stdout_buffer.items, 1, "\"action\":\"add\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, stdout_buffer.items, 1, "\"plan\""));

    stdout_buffer.clearRetainingCapacity();
    stderr_buffer.clearRetainingCapacity();

    const skills_argv = [_][]const u8{ "sa", "skills", "--json" };
    const skills_code = try saasm.cli.executeWithWriters(
        std.testing.allocator,
        skills_argv[0..],
        sio.managedWriter(&stdout_buffer),
        sio.managedWriter(&stderr_buffer),
    );
    try std.testing.expectEqual(@as(u8, 0), skills_code);
    try std.testing.expectEqual(@as(usize, 0), stderr_buffer.items.len);
    try std.testing.expect(std.mem.containsAtLeast(u8, stdout_buffer.items, 1, "\"status\":\"ok\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, stdout_buffer.items, 1, "\"core diagnostics\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, stdout_buffer.items, 1, "\"std runtime\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, stdout_buffer.items, 1, "\"init [path]\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, stdout_buffer.items, 1, "\"pkg install [identity]\""));

    stdout_buffer.clearRetainingCapacity();
    stderr_buffer.clearRetainingCapacity();

    const skills_help_argv = [_][]const u8{ "sa", "skills", "--help" };
    const skills_help_code = try saasm.cli.executeWithWriters(
        std.testing.allocator,
        skills_help_argv[0..],
        sio.managedWriter(&stdout_buffer),
        sio.managedWriter(&stderr_buffer),
    );
    try std.testing.expectEqual(@as(u8, 0), skills_help_code);
    try std.testing.expectEqual(@as(usize, 0), stderr_buffer.items.len);
    try std.testing.expect(std.mem.containsAtLeast(u8, stdout_buffer.items, 1, "usage: sa skills [--json]"));
    try std.testing.expect(std.mem.containsAtLeast(u8, stdout_buffer.items, 1, "scans the current sa_std root"));
}

test "sa skills writes Codex and Claude skill files for current project" {
    var original_cwd = try sio.cwd().openDir(".", .{});
    defer original_cwd.close();
    var tmp = std.testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();

    try tmp.dir.createDirPath(std.testing.io, "sa_plugins/sa_plugin_deno");
    try writeSource(tmp.dir, "sa_plugins/sa_plugin_deno/sap.json",
        \\{
        \\  "schema": "sa.plugin/1",
        \\  "name": "deno",
        \\  "version": "0.1.0",
        \\  "source": { "type": "local", "path": "." },
        \\  "abi": { "plugin": 1, "saasm": ">=0.4.0" },
        \\  "artifacts": { "linux-x86_64": { "path": "zig-out/lib/libdeno.so" } },
        \\  "interfaces": { "sai": { "path": "deno.sai" }, "sal": { "path": "deno.sal" } },
        \\  "skills": ["deno.sys", "deno.env"],
        \\  "permissions": {
        \\    "fs": [{ "op": "read", "path": "$PROJECT/**" }],
        \\    "net": [{ "url": "https://*", "methods": ["GET"] }],
        \\    "env": ["HOME", "SA_*"],
        \\    "process": { "spawn": false, "exec": [] }
        \\  },
        \\  "dependencies": {}
        \\}
        \\
    );
    try writeSource(tmp.dir, "sa_plugins/sa_plugin_deno/README.md",
        \\Deno compatibility facade for env, fs, process, and HTTP bridge workflows.
        \\
    );
    try writeSource(tmp.dir, "sa_plugins/sa_plugin_deno/deno.sai",
        \\@extern sa_deno_plugin_hostname(&out_ptr: ptr, &out_len: ptr) -> u32
        \\
    );
    try writeSource(tmp.dir, "sa_plugins/sa_plugin_deno/deno.sal",
        \\[MACRO] DENO_HOSTNAME %out_ptr, %out_len
        \\    %out_status = call @sa_deno_plugin_hostname(&%out_ptr, &%out_len)
        \\[END_MACRO]
        \\
    );
    try tmp.dir.createDirPath(std.testing.io, "sa_plugins/sa_plugin_3dengines");
    try writeSource(tmp.dir, "sa_plugins/sa_plugin_3dengines/README.md",
        \\Experimental 3D engine plugin should not be included in the common catalog.
        \\
    );

    try std.process.setCurrentDir(std.testing.io, tmp.dir);
    defer original_cwd.setAsCwd() catch {};

    var stdout_buffer = std.array_list.Managed(u8).init(std.testing.allocator);
    defer stdout_buffer.deinit();
    var stderr_buffer = std.array_list.Managed(u8).init(std.testing.allocator);
    defer stderr_buffer.deinit();

    const code = try saasm.cli.executeWithWriters(
        std.testing.allocator,
        &.{ "sa", "skills" },
        sio.managedWriter(&stdout_buffer),
        sio.managedWriter(&stderr_buffer),
    );
    try std.testing.expectEqual(@as(u8, 0), code);
    try std.testing.expectEqual(@as(usize, 0), stderr_buffer.items.len);
    try std.testing.expect(std.mem.containsAtLeast(u8, stdout_buffer.items, 1, "generated agent skills:"));
    try std.testing.expect(std.mem.containsAtLeast(u8, stdout_buffer.items, 1, ".codex/skills/sa/SKILL.md"));
    try std.testing.expect(std.mem.containsAtLeast(u8, stdout_buffer.items, 1, ".claude/skills/sa/SKILL.md"));
    try std.testing.expect(std.mem.containsAtLeast(u8, stdout_buffer.items, 1, ".codex/skills/sa_plugins/SKILL.md"));
    try std.testing.expect(std.mem.containsAtLeast(u8, stdout_buffer.items, 1, ".claude/skills/sa_plugins/SKILL.md"));
    try std.testing.expect(std.mem.containsAtLeast(u8, stdout_buffer.items, 1, "std surface:"));
    try std.testing.expect(std.mem.containsAtLeast(u8, stdout_buffer.items, 1, "official plugin catalog:"));
    try std.testing.expect(std.mem.containsAtLeast(u8, stdout_buffer.items, 1, "Rust-style string/vec/slice/option/result/core helper macros"));
    try std.testing.expect(std.mem.containsAtLeast(u8, stdout_buffer.items, 1, "optional deno/http/node/db/plugin APIs stay outside compiler std"));

    const codex_skill = try tmp.dir.readFileAlloc(std.testing.io, ".codex/skills/sa/SKILL.md", std.testing.allocator, .limited(16 * 1024 * 1024));
    defer std.testing.allocator.free(codex_skill);
    const claude_skill = try tmp.dir.readFileAlloc(std.testing.io, ".claude/skills/sa/SKILL.md", std.testing.allocator, .limited(16 * 1024 * 1024));
    defer std.testing.allocator.free(claude_skill);
    const codex_plugins_skill = try tmp.dir.readFileAlloc(std.testing.io, ".codex/skills/sa_plugins/SKILL.md", std.testing.allocator, .limited(16 * 1024 * 1024));
    defer std.testing.allocator.free(codex_plugins_skill);
    const claude_plugins_skill = try tmp.dir.readFileAlloc(std.testing.io, ".claude/skills/sa_plugins/SKILL.md", std.testing.allocator, .limited(16 * 1024 * 1024));
    defer std.testing.allocator.free(claude_plugins_skill);

    try std.testing.expect(std.mem.containsAtLeast(u8, codex_skill, 1, "name: \"sa\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, codex_skill, 1, "# SA Toolchain"));
    try std.testing.expect(std.mem.containsAtLeast(u8, codex_skill, 1, "`sa build <file>`"));
    try std.testing.expect(std.mem.containsAtLeast(u8, codex_skill, 1, "`sa test <file> --list`"));
    try std.testing.expect(std.mem.containsAtLeast(u8, codex_skill, 1, "Treat the `sa_std Surface` section below as authoritative"));
    try std.testing.expect(std.mem.containsAtLeast(u8, codex_skill, 1, "## Std Coverage Guide"));
    try std.testing.expect(std.mem.containsAtLeast(u8, codex_skill, 1, "Core macro families include string, vec, slice"));
    try std.testing.expect(std.mem.containsAtLeast(u8, codex_skill, 1, "Rust-style fs coverage includes create_dir"));
    try std.testing.expect(std.mem.containsAtLeast(u8, codex_skill, 1, "Rust-style net coverage includes owned address handles"));
    try std.testing.expect(std.mem.containsAtLeast(u8, codex_skill, 1, "Rust's full std::future/std::task poll"));
    try std.testing.expect(std.mem.containsAtLeast(u8, codex_skill, 1, "## sa_std Surface"));
    try std.testing.expect(std.mem.containsAtLeast(u8, codex_skill, 1, "sa.mod"));
    try std.testing.expect(std.mem.containsAtLeast(u8, codex_skill, 1, "core/slice.sa: [MACRO] SLICE_NEW"));
    try std.testing.expect(std.mem.containsAtLeast(u8, codex_skill, 1, "fs.sa: [MACRO] FS_CREATE_DIR"));
    try std.testing.expect(std.mem.containsAtLeast(u8, codex_skill, 1, "fs.sa: [MACRO] FS_READ_TO_STRING"));
    try std.testing.expect(std.mem.containsAtLeast(u8, codex_skill, 1, "fs.sa: [MACRO] FS_TRY_EXISTS"));
    try std.testing.expect(std.mem.containsAtLeast(u8, codex_skill, 1, "net.sa: [MACRO] NET_TO_SOCKET_ADDR_FIRST"));
    try std.testing.expect(std.mem.containsAtLeast(u8, codex_skill, 1, "env.sa: [MACRO] ENV_ARGS_JSON"));
    try std.testing.expect(std.mem.containsAtLeast(u8, codex_skill, 1, "process.sa: [MACRO] PROCESS_CHILD_ID"));
    try std.testing.expect(std.mem.containsAtLeast(u8, codex_skill, 1, "string.sa: [MACRO] STR_CHAR_COUNT"));
    try std.testing.expect(std.mem.containsAtLeast(u8, codex_skill, 1, "string.sa: [MACRO] STR_TRY_CHAR_AT"));
    try std.testing.expect(std.mem.containsAtLeast(u8, codex_skill, 1, "string.sa: [MACRO] STR_IS_UTF8"));
    try std.testing.expect(std.mem.containsAtLeast(u8, codex_skill, 1, "string.sai: @extern sa_str_utf8_char_at"));
    try std.testing.expect(std.mem.containsAtLeast(u8, codex_skill, 1, "string.sai: @extern sa_str_utf8_validate"));
    try std.testing.expect(std.mem.containsAtLeast(u8, codex_skill, 1, "ffi.sa: [MACRO] CSTR_TO_STR"));
    try std.testing.expect(std.mem.containsAtLeast(u8, codex_skill, 1, "io.sa: [MACRO] IO_CURSOR_READ_TO_END"));
    try std.testing.expect(std.mem.containsAtLeast(u8, codex_skill, 1, "io.sa: [MACRO] IO_CURSOR_READ_TO_STRING"));
    try std.testing.expect(std.mem.containsAtLeast(u8, codex_skill, 1, "io.sa: [MACRO] IO_TAKE_READ_TO_END"));
    try std.testing.expect(std.mem.containsAtLeast(u8, codex_skill, 1, "io.sa: [MACRO] IO_TAKE_READ_TO_STRING"));
    try std.testing.expect(std.mem.containsAtLeast(u8, codex_skill, 1, "path.sa: [MACRO] PATH_TRY_FILE_PREFIX"));
    try std.testing.expect(std.mem.containsAtLeast(u8, codex_skill, 1, "path.sa: [MACRO] PATH_TRY_TO_STR"));
    try std.testing.expect(std.mem.containsAtLeast(u8, codex_skill, 1, "mem.sa: [MACRO] MAYBE_UNINIT_U64_AS_BYTES"));
    try std.testing.expect(std.mem.containsAtLeast(u8, codex_skill, 1, "mem.sa: [MACRO] MANUALLY_DROP_U64_DEREF_MUT"));
    try std.testing.expect(std.mem.containsAtLeast(u8, codex_skill, 1, "ptr.sa: [MACRO] PTR_NULL"));
    try std.testing.expect(std.mem.containsAtLeast(u8, codex_skill, 1, "ptr.sa: [MACRO] PTR_EXPOSE_PROVENANCE"));
    try std.testing.expect(std.mem.containsAtLeast(u8, codex_skill, 1, "ptr.sa: [MACRO] NONNULL_OFFSET_FROM_UNSIGNED_U64"));
    try std.testing.expect(std.mem.containsAtLeast(u8, codex_skill, 1, "num.sa: [MACRO] NUM_U64_CHECKED_ADD"));
    try std.testing.expect(std.mem.containsAtLeast(u8, codex_skill, 1, "num.sa: [MACRO] NUM_U64_BIT_WIDTH"));
    try std.testing.expect(std.mem.containsAtLeast(u8, codex_skill, 1, "num.sa: [MACRO] NUM_I64_HIGHEST_ONE"));
    try std.testing.expect(std.mem.containsAtLeast(u8, codex_skill, 1, "any.sa: [MACRO] ANY_REF_NEW"));
    try std.testing.expect(std.mem.containsAtLeast(u8, codex_skill, 1, "io.sai: @extern"));
    try std.testing.expect(std.mem.containsAtLeast(u8, codex_skill, 1, "../sa_plugins/SKILL.md"));
    try std.testing.expect(std.mem.containsAtLeast(u8, claude_skill, 1, "Use the installed SA compiler"));
    try std.testing.expect(std.mem.containsAtLeast(u8, claude_skill, 1, "## CLI Skill Sections"));
    try std.testing.expect(std.mem.containsAtLeast(u8, codex_plugins_skill, 1, "name: \"sa_plugins\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, codex_plugins_skill, 1, "# SA Optional Plugins"));
    try std.testing.expect(std.mem.containsAtLeast(u8, codex_plugins_skill, 1, "not proof that any plugin is installed"));
    try std.testing.expect(std.mem.containsAtLeast(u8, codex_plugins_skill, 1, "sa plugin list"));
    try std.testing.expect(std.mem.containsAtLeast(u8, codex_plugins_skill, 1, "deno (0.1.0)"));
    try std.testing.expect(std.mem.containsAtLeast(u8, codex_plugins_skill, 1, "Optional plugin: install before use"));
    try std.testing.expect(std.mem.containsAtLeast(u8, codex_plugins_skill, 1, "deno/sa_plugin_deno/deno.sai: @extern sa_deno_plugin_hostname"));
    try std.testing.expect(std.mem.containsAtLeast(u8, codex_plugins_skill, 1, "deno/sa_plugin_deno/deno.sal: [MACRO] DENO_HOSTNAME"));
    try std.testing.expect(!std.mem.containsAtLeast(u8, codex_plugins_skill, 1, "3dengines"));
    try std.testing.expect(std.mem.containsAtLeast(u8, claude_plugins_skill, 1, "Use the optional official SA plugin catalog"));
}

test "cli audit dispatches through runtime package plugin" {
    var tmp = std.testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();

    try tmp.dir.createDirPath(std.testing.io, "pkg");
    try writeSource(tmp.dir, "pkg/index.sa",
        \\call @sys_print(*MSG, 2)
        \\
    );
    const pkg_root = try tmp.dir.realPathFileAlloc(std.testing.io, "pkg", std.testing.allocator);
    defer std.testing.allocator.free(pkg_root);

    var stdout_buffer = std.array_list.Managed(u8).init(std.testing.allocator);
    defer stdout_buffer.deinit();
    var stderr_buffer = std.array_list.Managed(u8).init(std.testing.allocator);
    defer stderr_buffer.deinit();

    const audit_argv = [_][]const u8{ "sa", "audit", "--format", "json", pkg_root };
    const audit_code = try saasm.cli.executeWithWriters(
        std.testing.allocator,
        audit_argv[0..],
        sio.managedWriter(&stdout_buffer),
        sio.managedWriter(&stderr_buffer),
    );
    try std.testing.expectEqual(@as(u8, 0), audit_code);
    try std.testing.expectEqual(@as(usize, 0), stderr_buffer.items.len);
    try std.testing.expect(std.mem.startsWith(u8, stdout_buffer.items, "{\"package\":"));
    try std.testing.expect(std.mem.containsAtLeast(u8, stdout_buffer.items, 1, "\"trust_score\":50"));
    try std.testing.expect(std.mem.containsAtLeast(u8, stdout_buffer.items, 1, "\"capability\":\"io_write\""));
    try std.testing.expect(!std.mem.containsAtLeast(u8, stdout_buffer.items, 1, "audit: "));
}

test "cli audit update-lock writes project lock through package flow" {
    var original_cwd = try sio.cwd().openDir(".", .{});
    defer original_cwd.close();
    var tmp = std.testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();

    try tmp.dir.createDirPath(std.testing.io, "zig-out");
    try tmp.dir.createDirPath(std.testing.io, "pkg");
    try writeSource(tmp.dir, "pkg/index.sa",
        \\@main() -> i32:
        \\return 0
        \\
    );

    try std.process.setCurrentDir(std.testing.io, tmp.dir);
    defer original_cwd.setAsCwd() catch {};

    var stdout_buffer = std.array_list.Managed(u8).init(std.testing.allocator);
    defer stdout_buffer.deinit();
    var stderr_buffer = std.array_list.Managed(u8).init(std.testing.allocator);
    defer stderr_buffer.deinit();

    const audit_argv = [_][]const u8{ "sa", "audit", "--update-lock", "--format", "json", "pkg" };
    const audit_code = try saasm.cli.executeWithWriters(
        std.testing.allocator,
        audit_argv[0..],
        sio.managedWriter(&stdout_buffer),
        sio.managedWriter(&stderr_buffer),
    );
    try std.testing.expectEqual(@as(u8, 0), audit_code);
    try std.testing.expectEqual(@as(usize, 0), stderr_buffer.items.len);
    try std.testing.expect(std.mem.startsWith(u8, stdout_buffer.items, "{\"package\":\"pkg\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, stdout_buffer.items, 1, "\"machine_code_sha256\":\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, stdout_buffer.items, 1, "\"created_entry\":true"));
    try std.testing.expect(std.mem.containsAtLeast(u8, stdout_buffer.items, 1, "\"changed\":true"));

    const lock_source = try tmp.dir.readFileAlloc(std.testing.io, "sa.lock", std.testing.allocator, .limited(1024 * 1024));
    defer std.testing.allocator.free(lock_source);
    var lock_file = try saasm.pkg.manifest.parseLock(std.testing.allocator, lock_source);
    defer lock_file.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(usize, 1), lock_file.entries.len);
    try std.testing.expectEqualStrings("pkg", lock_file.entries[0].url);
    try std.testing.expectEqualStrings("HEAD", lock_file.entries[0].ref);
    try std.testing.expectEqual(@as(usize, 1), lock_file.entries[0].approved_machine_code_hashes.count());

    stdout_buffer.clearRetainingCapacity();
    stderr_buffer.clearRetainingCapacity();
    const second_code = try saasm.cli.executeWithWriters(
        std.testing.allocator,
        audit_argv[0..],
        sio.managedWriter(&stdout_buffer),
        sio.managedWriter(&stderr_buffer),
    );
    try std.testing.expectEqual(@as(u8, 0), second_code);
    try std.testing.expectEqual(@as(usize, 0), stderr_buffer.items.len);
    try std.testing.expect(std.mem.containsAtLeast(u8, stdout_buffer.items, 1, "\"created_entry\":false"));
    try std.testing.expect(std.mem.containsAtLeast(u8, stdout_buffer.items, 1, "\"changed\":false"));
}
