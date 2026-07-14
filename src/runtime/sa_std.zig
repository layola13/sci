const builtin = @import("builtin");

pub usingnamespace switch (builtin.os.tag) {
    .windows => @import("sa_std_windows.zig"),
    else => @import("sa_std_posix.zig"),
};
