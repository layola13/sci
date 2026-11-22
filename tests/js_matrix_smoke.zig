// JS backend equivalence matrix: `sa build-js` output executed with node
// must match the expected stdout of each demo (verified against native
// build-exe during development). Pure Zig backend: no LLVM required.
// Thin shim (task 79 split): implementation moved to tests/js_matrix_smoke/.
// Every submodule is comptime-imported below so its test blocks stay
// in the test build (task 28 lesson: unimported test files are lost).
comptime {
    _ = @import("js_matrix_smoke/helpers.zig");
    _ = @import("js_matrix_smoke/rosetta_a.zig");
    _ = @import("js_matrix_smoke/rosetta_b.zig");
    _ = @import("js_matrix_smoke/rosetta_c.zig");
    _ = @import("js_matrix_smoke/rosetta.zig");
    _ = @import("js_matrix_smoke/checks.zig");
    _ = @import("js_matrix_smoke/dts.zig");
}
