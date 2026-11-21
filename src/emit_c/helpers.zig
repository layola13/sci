const HelperDef = @import("types.zig").HelperDef;
const chunk_1 = @import("helpers_1.zig").chunk_1;
const chunk_2 = @import("helpers_2.zig").chunk_2;
const chunk_3 = @import("helpers_3.zig").chunk_3;
const chunk_4 = @import("helpers_4.zig").chunk_4;
const std = @import("std");

pub const kRuntimeHelpers: []const HelperDef = &(chunk_1 ++ chunk_2 ++ chunk_3 ++ chunk_4);

/// Emission order for the catalog, topologically sorted by deps at
/// comptime (Kahn's algorithm, stable by table order). Callees always
/// precede callers no matter where entries sit in the table, so adding
/// helpers can never reintroduce use-before-definition. Unknown deps
/// (sa_trap, always emitted) are treated as ready; any residual cycle
/// falls back to table order.
pub const kHelpersSorted: [kRuntimeHelpers.len]HelperDef = blk: {
    @setEvalBranchQuota(100000);
    var order: [kRuntimeHelpers.len]usize = undefined;
    var done: [kRuntimeHelpers.len]bool = std.mem.zeroes([kRuntimeHelpers.len]bool);
    var n: usize = 0;
    var progress = true;
    while (progress) {
        progress = false;
        for (kRuntimeHelpers, 0..) |h, i| {
            if (done[i]) continue;
            var ready = true;
            for (h.deps) |dep| {
                for (kRuntimeHelpers, 0..) |h2, j| {
                    if (std.mem.eql(u8, h2.name, dep)) {
                        if (!done[j]) ready = false;
                        break;
                    }
                }
                if (!ready) break;
            }
            if (ready) {
                order[n] = i;
                n += 1;
                done[i] = true;
                progress = true;
            }
        }
    }
    for (0..kRuntimeHelpers.len) |i| {
        if (!done[i]) {
            order[n] = i;
            n += 1;
            done[i] = true;
        }
    }
    var out: [kRuntimeHelpers.len]HelperDef = undefined;
    for (order, 0..) |idx, k| out[k] = kRuntimeHelpers[idx];
    break :blk out;
};

