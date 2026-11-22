const std = @import("std");

/// Emit the JS stub for a known extern shim in this group.
/// Returns true if `name` was handled (stub emitted), false otherwise.
pub fn emitShim(writer: anytype, name: []const u8) !bool {
    if (std.mem.eql(u8, name, "sa_cookie_value")) {
        try writer.writeAll(
            \\function sa_cookie_value(handle, out_ptr, out_len) {
            \\  const J = globalThis.__sa_jsnet;
            \\  const c = J.ckGet(__sa_num(handle));
            \\  if (!c) return 2;
            \\  return J.outStr(out_ptr, out_len, c.value);
            \\}
            \\
        );
        return true;
    }
    return false;
}
