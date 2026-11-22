// Thin shim (task 79 split): implementation moved to tests/std_smoke_containers/.
// Every submodule is comptime-imported below so its test blocks stay
// in the test build (task 28 lesson: unimported test files are lost).
comptime {
    _ = @import("std_smoke_containers/helpers.zig");
    _ = @import("std_smoke_containers/alloc.zig");
    _ = @import("std_smoke_containers/hashset.zig");
    _ = @import("std_smoke_containers/btree.zig");
    _ = @import("std_smoke_containers/deque_heap.zig");
}
