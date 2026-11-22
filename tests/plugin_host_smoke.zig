// Thin shim for the plugin-host-smoke test root.
// The test blocks now live in tests/plugin_host_smoke/*.zig; the comptime
// imports below keep every submodule in the build graph so `zig build test`
// still compiles and runs all 21 tests.
comptime {
    _ = @import("plugin_host_smoke/helpers.zig");
    _ = @import("plugin_host_smoke/installer_core.zig");
    _ = @import("plugin_host_smoke/installer_rejects.zig");
    _ = @import("plugin_host_smoke/installer_remote.zig");
    _ = @import("plugin_host_smoke/broker_env.zig");
    _ = @import("plugin_host_smoke/cli_allow.zig");
    _ = @import("plugin_host_smoke/registry_cache.zig");
    _ = @import("plugin_host_smoke/workspace_commands.zig");
    _ = @import("plugin_host_smoke/project_verbs.zig");
    _ = @import("plugin_host_smoke/npm_installer.zig");
}
