// Split from sab.zig: thin re-export shim.
// Implementation lives in sab/ (one module per chunk).

pub const instruction = @import("sab/instruction.zig").instruction;
pub const signature = @import("sab/instruction.zig").signature;
pub const const_decl = @import("sab/instruction.zig").const_decl;
pub const magic = @import("sab/instruction.zig").magic;
pub const version_major = @import("sab/instruction.zig").version_major;
pub const version_minor = @import("sab/instruction.zig").version_minor;
pub const fragment_magic = @import("sab/instruction.zig").fragment_magic;
pub const isFragmentBytes = @import("sab/instruction.zig").isFragmentBytes;
pub const Error = @import("sab/instruction.zig").Error;
pub const Module = @import("sab/instruction.zig").Module;
pub const encodeUleb128 = @import("sab/instruction.zig").encodeUleb128;
pub const decodeUleb128 = @import("sab/instruction.zig").decodeUleb128;
pub const encodeSleb128 = @import("sab/instruction.zig").encodeSleb128;
pub const decodeSleb128 = @import("sab/instruction.zig").decodeSleb128;
pub const encodeProgramWithConsts = @import("sab/read_const_value.zig").encodeProgramWithConsts;
pub const encodeProgram = @import("sab/read_const_value.zig").encodeProgram;
pub const encodeModule = @import("sab/read_const_value.zig").encodeModule;
pub const decodeModule = @import("sab/read_const_value.zig").decodeModule;
pub const decodeFunctionSigsOnly = @import("sab/read_const_value.zig").decodeFunctionSigsOnly;
pub const decodeTestFunctionSigsOnly = @import("sab/read_const_value.zig").decodeTestFunctionSigsOnly;
pub const disasmModule = @import("sab/read_const_value.zig").disasmModule;
const _mod_write_disasm_instruction = @import("sab/write_disasm_instruction.zig");
