// Split from emit_llvm_llvmc.zig: thin re-export shim.
// Implementation lives in emit_llvm_llvmc/ (one module per chunk).

pub const LlvmcError = @import("emit_llvm_llvmc/sa_llvmc_free.zig").LlvmcError;
pub const EmitOptions = @import("emit_llvm_llvmc/sa_llvmc_free.zig").EmitOptions;
pub const lastErrorMessage = @import("emit_llvm_llvmc/sa_llvmc_free.zig").lastErrorMessage;
pub const emitLlvmc = @import("emit_llvm_llvmc/emit_llvmc_internal.zig").emitLlvmc;
pub const emitLlvmcToObject = @import("emit_llvm_llvmc/emit_llvmc_internal.zig").emitLlvmcToObject;
pub const emitLlvmcToArtifacts = @import("emit_llvm_llvmc/emit_llvmc_internal.zig").emitLlvmcToArtifacts;
pub const emitLlvmcToFile = @import("emit_llvm_llvmc/emit_llvmc_internal.zig").emitLlvmcToFile;
const _mod_atomic_rmw_op = @import("emit_llvm_llvmc/atomic_rmw_op.zig");
const _mod_assign_operand = @import("emit_llvm_llvmc/assign_operand.zig");
const _mod_tests_dce_modes_prune_std_and_user_funct = @import("emit_llvm_llvmc/tests_dce_modes_prune_std_and_user_funct.zig");
