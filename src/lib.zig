const std = @import("std");

pub const build_options = @import("build_options");

pub const common = struct {
    pub const instruction = @import("common/instruction.zig");
    pub const capability = @import("common/capability.zig");
    pub const trap = @import("common/trap.zig");
    pub const upstream_loc = @import("common/upstream_loc.zig");
    pub const gas = @import("common/gas.zig");
    pub const signature = @import("common/signature.zig");
};

pub const flattener = @import("flattener.zig");
pub const driver = @import("driver/zigcc.zig");
pub const emit_options = @import("emit_options.zig");
pub const emit_llvm_llvmc = @import("emit_llvm_llvmc.zig");
pub const interp = @import("interp.zig");
pub const layout = @import("layout.zig");
pub const llvm2sa = @import("llvm2sa.zig");
pub const plugins = @import("plugins.zig");
pub const test_executor = @import("test_executor.zig");
pub const test_formatter = @import("test_formatter.zig");
pub const test_meta = @import("test_meta.zig");
pub const test_result = @import("test_result.zig");
pub const test_runner = @import("test_runner.zig");
pub const pkg = struct {
    pub const audit = @import("pkg/audit.zig");
    pub const ci = @import("pkg/ci.zig");
    pub const confirm = @import("pkg/confirm.zig");
    pub const fetch = @import("pkg/fetch.zig");
    pub const lock = @import("pkg/lock.zig");
    pub const manifest = @import("pkg/manifest.zig");
    pub const mirror = @import("pkg/mirror.zig");
    pub const resolver = @import("pkg/resolver.zig");
    pub const sum = @import("pkg/sum.zig");
};
pub const libsa_scope = @import("libsa_scope.zig");
pub const runtime = struct {
    pub const sa_net_uring = @import("runtime/sa_net_uring.zig");
    pub const sa_std = @import("runtime/sa_std.zig");
};
pub const referee = @import("referee.zig");
pub const cli = @import("cli.zig");
