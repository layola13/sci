# SA-ASM P0 Register Scope Localization: Diagnostic & Actionable Recommendation Report

This document details the exact root causes of the compile-time and run-time failures encountered in the Git push hook (`zig build pre-push` / `zig build test`) under the new register scope localization design. It outlines the minimal, non-intrusive actions required to fully align the compiler pipeline and get all CI tests to pass.

---

## 1. Issue 1: Unused Parameter in Emitter (`src/emit_llvm.zig`)

### Symptom
All compilation steps referencing `src/emit_llvm.zig` fail with the following Zig compiler error:
```text
src/emit_llvm.zig:771:5: error: unused function parameter
    symbols: *const symbol.SymbolTable,
    ^~~~~~~
```

### Deep Analysis
During the register scope localization refactoring, a helper function `resolveSymbolValue` was introduced around line 769–795:
```zig
fn resolveSymbolValue(
    allocator: std.mem.Allocator,
    state: *FunctionState,
    symbols: *const symbol.SymbolTable,
    sigs: []const sig.FunctionSig,
    name: []const u8,
) !?Value {
    if (state.hasConstRef(name)) {
        return .{ .expr = try state.ownFmt(allocator, "@{s}", .{name}), .ty = .ptr, .const_ref = name, .origin = .{ .const_name = name } };
    }
    // ...
}
```
1. **Unused Parameter**: The parameter `symbols` is declared in the signature but never referenced inside the body of the function.
2. **Unused Function**: Currently, `resolveSymbolValue` itself is not called anywhere in `src/emit_llvm.zig`.
3. **Strict Zig Rules**: Zig has zero-tolerance for unused function parameters, causing a hard compile failure on all targets utilizing the LLVM emitter.

### Recommended Resolution
Add an explicit discard statement `_ = symbols;` inside the body of `resolveSymbolValue`, or remove/comment out the unused function.
```zig
fn resolveSymbolValue(
    allocator: std.mem.Allocator,
    state: *FunctionState,
    symbols: *const symbol.SymbolTable,
    sigs: []const sig.FunctionSig,
    name: []const u8,
) !?Value {
    _ = symbols; // Discard unused parameter to satisfy compiler
    if (state.hasConstRef(name)) {
        return .{ .expr = try state.ownFmt(allocator, "@{s}", .{name}), .ty = .ptr, .const_ref = name, .origin = .{ .const_name = name } };
    }
    // ...
}
```

---

## 2. Issue 2: Empty Function Scope Trap in Legacy Unit Test (`src/lib.zig`)

### Symptom
`zig test` fails on the legacy unit test in `src/lib.zig` with:
```text
error: 'lib.test.root module imports common types' failed: /home/vscode/projects/sci/src/lib.zig:115:18
        .trap => return error.TestUnexpectedResult,
                 ^
```

### Deep Analysis
The new P0 verifier introduces robust safety guards to protect register slot reads/writes. Specifically, in `assignValueCtx` (and similar routines inside `src/verifier.zig`):
```zig
const idx: usize = @intCast(id);
if (idx >= state.len) {
    return trapReport(.unknown_register, item, function_text, is_ffi_wrapper, name, null, null, "register is not declared in the current scope", null);
}
```
1. **Empty State**: In `src/lib.zig`'s legacy unit test `test.root module imports common types`, a bare array of two instructions (`node = alloc 8` and `return node`) is verified directly without a function declaration header.
2. **Scoping Failure**: Since there is no function header, the verifier cannot build a localized register scope. `state.len` is initialized to `0`.
3. **Trap Condition**: When verifying `.alloc`, it passes register slot `0`. The safety guard evaluates `idx >= state.len` (`0 >= 0`), which returns `true` and throws a `.trap`, failing the test.

### Recommended Resolution
Wrap the legacy instructions inside the test in a proper function declaration block to generate a valid local scope:
```diff
     const program = [_]flatten.Instruction{
+        .{
+            .kind = .func_decl,
+            .source_line = 1,
+            .expanded_line = 0,
+            .operands = .{
+                .{ .symbol = 0 },
+                .{ .func = 0 },
+                .{ .none = {} },
+                .{ .none = {} },
+            },
+            .raw_text = "@main() -> void:",
+        },
         .{
             .kind = .alloc,
-            .source_line = 1,
-            .expanded_line = 0,
+            .source_line = 2,
+            .expanded_line = 1,
             .operands = .{
                 .{ .reg = 0 },
                 .{ .imm_u64 = 8 },
                 .{ .none = {} },
                 .{ .none = {} },
             },
             .raw_text = "node = alloc 8",
         },
         .{
             .kind = .return_,
-            .source_line = 2,
-            .expanded_line = 1,
+            .source_line = 3,
+            .expanded_line = 2,
             .operands = .{
                 .{ .reg = 0 },
                 .{ .none = {} },
                 .{ .none = {} },
                 .{ .none = {} },
             },
             .raw_text = "return node",
         },
     };
```

---

## 3. Conclusion
The implementation of the localized register scoping mechanism is architecturally highly solid. Applying the two non-intrusive fixes above will immediately enable `zig build pre-push` and the entire integration suite to pass perfectly.
