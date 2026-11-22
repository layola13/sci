//! Thin shim: the 36 tests formerly in this file now live in
//! tests/std_smoke/*.zig. This file only pulls them back into the test
//! graph so coverage is unchanged.
//!
//! NOTE: this file is currently not a build.zig test root (the live
//! roots are tests/std_smoke_core.zig and tests/std_smoke_containers.zig);
//! the shim keeps it usable as a root if it is ever re-added.

comptime {
    _ = @import("std_smoke/core.zig");
    _ = @import("std_smoke/alloc.zig");
    _ = @import("std_smoke/formats_time_net.zig");
    _ = @import("std_smoke/sync.zig");
    _ = @import("std_smoke/io_string.zig");
    _ = @import("std_smoke/env_fs.zig");
    _ = @import("std_smoke/deno_sse.zig");
    _ = @import("std_smoke/containers_a.zig");
    _ = @import("std_smoke/containers_b.zig");
    _ = @import("std_smoke/deno_facade.zig");
    _ = @import("std_smoke/fixture.zig");
}
