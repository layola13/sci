// Thin shim (task 28 split): the implementation lives in src/llvm2sa/*.zig.
// The public API is re-exported unchanged so existing imports keep working.
pub const TranslateError = @import("llvm2sa/translate.zig").TranslateError;
pub const translateIrSource = @import("llvm2sa/translate.zig").translateIrSource;
pub const translateBitcodeFile = @import("llvm2sa/translate.zig").translateBitcodeFile;

const llvm2sa_tests = @import("llvm2sa/tests.zig");
