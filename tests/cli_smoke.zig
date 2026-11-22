// Thin shim for tests/cli_smoke.zig (split 2026-11-22, task 79 agent B).
// The 140 tests now live in tests/cli_smoke/*.zig; this file only pulls
// them back into the build graph so every build.zig root_source_file
// reference keeps working. Do not add tests here.
comptime {
    _ = @import("cli_smoke/helpers.zig");
    _ = @import("cli_smoke/basic.zig");
    _ = @import("cli_smoke/cache_pkg.zig");
    _ = @import("cli_smoke/demos.zig");
    _ = @import("cli_smoke/std_demos.zig");
    _ = @import("cli_smoke/runtime_demos.zig");
    _ = @import("cli_smoke/sa_test.zig");
    _ = @import("cli_smoke/abi.zig");
    _ = @import("cli_smoke/bc2sa.zig");
    _ = @import("cli_smoke/codegen.zig");
    _ = @import("cli_smoke/wasm_db.zig");
    _ = @import("cli_smoke/agent_cli.zig");
    _ = @import("cli_smoke/pkg_mgr.zig");
    _ = @import("cli_smoke/diagnostics.zig");
}
