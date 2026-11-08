// Re-export shim: the decl_materialize implementation lives in
// src/decl_materialize.zig so that src/flattener.zig can consume the same
// module the build graph uses here. Keep this file a pure re-export so
// the two consumption points can never drift apart.
const impl = @import("../src/decl_materialize.zig");

pub const DeclTarget = impl.DeclTarget;
pub const MaterializeError = impl.MaterializeError;
pub const containsTargetBlocks = impl.containsTargetBlocks;
pub const materialize = impl.materialize;
pub const materializeFromFile = impl.materializeFromFile;
pub const materializeToFile = impl.materializeToFile;
pub const writeFileAbsolute = impl.writeFileAbsolute;
pub const writeFileAtomic = impl.writeFileAtomic;
