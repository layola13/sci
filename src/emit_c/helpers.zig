const HelperDef = @import("types.zig").HelperDef;
const chunk_runtime_arith_convert = @import("helpers_runtime_arith_convert.zig").chunk_runtime_arith_convert;
const chunk_convert_http_multipart = @import("helpers_convert_http_multipart.zig").chunk_convert_http_multipart;
const chunk_hash_json_regex = @import("helpers_hash_json_regex.zig").chunk_hash_json_regex;
const chunk_regex_parse_path = @import("helpers_regex_parse_path.zig").chunk_regex_parse_path;
const std = @import("std");

pub const kRuntimeHelpers: []const HelperDef = &(chunk_runtime_arith_convert ++ chunk_convert_http_multipart ++ chunk_hash_json_regex ++ chunk_regex_parse_path);

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

