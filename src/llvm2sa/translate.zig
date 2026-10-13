// NOTE(Zig 0.17): `pub usingnamespace` is removed; re-export explicitly.
const src = @import("../llvm2sa.zig");
pub const TranslateError = src.TranslateError;
pub const translateBitcodeFile = src.translateBitcodeFile;
pub const translateIrSource = src.translateIrSource;
