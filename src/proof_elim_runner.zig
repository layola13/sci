// Temporary test runner for the proof-elimination module (dev only).
// `zig test` on a file treats its directory as the module root, so the
// module's own tests are run through this runner at src/ level, where
// the `../common/...` imports resolve.
pub const linear = @import("proof_elim/linear.zig");
pub const fm = @import("proof_elim/fm.zig");
pub const obligation = @import("proof_elim/obligation.zig");
pub const pass = @import("proof_elim/pass.zig");

test {
    _ = linear;
    _ = fm;
    _ = obligation;
    _ = pass;
}
