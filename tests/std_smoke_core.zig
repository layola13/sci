//! Thin shim: the 13 tests formerly in this file now live in
//! tests/std_smoke_core/*.zig. This file only pulls them back into the test
//! graph so coverage is unchanged.
//!
//! This file IS a build.zig test root (std_smoke_core test target);
//! the comptime imports below keep every test in the build graph.

comptime {
    _ = @import("std_smoke_core/primitives.zig");
    _ = @import("std_smoke_core/deno_chat.zig");
    _ = @import("std_smoke_core/deno_responses.zig");
    _ = @import("std_smoke_core/rust_core.zig");
}
