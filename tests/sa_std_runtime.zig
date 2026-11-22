// Thin shim (task 79 split): implementation moved to tests/sa_std_runtime/.
// Every submodule is comptime-imported below so its test blocks stay
// in the test build (task 28 lesson: unimported test files are lost).
comptime {
    _ = @import("sa_std_runtime/helpers.zig");
    _ = @import("sa_std_runtime/network.zig");
    _ = @import("sa_std_runtime/c_abi.zig");
    _ = @import("sa_std_runtime/process.zig");
    _ = @import("sa_std_runtime/json.zig");
    _ = @import("sa_std_runtime/misc.zig");
}
