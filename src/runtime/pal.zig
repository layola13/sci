const builtin = @import("builtin");

pub const sys = switch (builtin.os.tag) {
    .linux => @import("pal_linux.zig"),
    .macos => @import("pal_macos.zig"),
    .windows => @import("pal_windows.zig"),
    else => @compileError("Unsupported OS"),
};

pub const SaEvent = sys.SaEvent;
