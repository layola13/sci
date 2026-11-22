// Thin shim (task 79 split): implementation moved to tests/unit_framework/runner/.
// Every submodule is comptime-imported below so its test blocks stay
// in the test build (task 28 lesson: unimported test files are lost).
comptime {
    _ = @import("runner/util.zig");
    _ = @import("runner/queue.zig");
    _ = @import("runner/feature.zig");
    _ = @import("runner/diag.zig");
    _ = @import("runner/macro_data_a.zig");
    _ = @import("runner/macro_data_b.zig");
    _ = @import("runner/macro_data_c.zig");
    _ = @import("runner/macro_suite.zig");
    _ = @import("runner/mockio.zig");
}
