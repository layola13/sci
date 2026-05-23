# SA-ASM P0 Register Scope Localization: Diagnostic & Actionable Recommendation Report

This document records historical P0 register-scope diagnostics. The old text LLVM emitter `src/emit_llvm.zig` has been removed from the mainline; normal build/run/test paths use `src/emit_llvm_llvmc.zig` and emit `.sa.bc` directly.

## 1. Issue 1: Legacy Text Emitter Removed (`src/emit_llvm.zig`)

The previous unused-parameter failure in the legacy text emitter is obsolete. The file is no longer part of the build graph, and the public root module no longer exports it. Future emitter fixes must target `src/emit_llvm_llvmc.zig`.

## 2. Issue 2: Empty Function Scope Trap in Legacy Unit Test (`src/lib.zig`)

### Symptom
`zig test` previously failed on a legacy unit test in `src/lib.zig` with:
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
1. **Empty State**: In the former `src/lib.zig` legacy unit test `test.root module imports common types`, a bare array of two instructions (`node = alloc 8` and `return node`) is verified directly without a function declaration header.
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
