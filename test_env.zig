const std = @import("std");
pub fn main() void {
    std.posix.setenv("SA_STD_DIR", "foo") catch {};
}
