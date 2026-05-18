const std = @import("std");

pub const schema = @import("schema.zig");
pub const qmod = @import("qmod.zig");
pub const referee_db = @import("referee_db.zig");
pub const trap_db = @import("trap_db.zig");
pub const exec = @import("exec.zig");

test "db module exports real symbols" {
    _ = schema.Schema;
    _ = qmod.Qmod;
    _ = referee_db.scanForTrap;
    _ = trap_db.DbTrap.db_capability_escalation;
    _ = exec.trapUnknownHash;
    try std.testing.expect(true);
}
