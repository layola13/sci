//! Test entry point for pkg_core_tests (task 120-a2, defect ⑤).
//!
//! The real test root lives at src/pkg/pkg_core_tests.zig, but a test module
//! rooted there has module root src/pkg/, and src/pkg/resolver.zig imports
//! ../module_resolver/, which escapes that root (Zig 0.17 rejects it with
//! "import of file outside module path"). Rooting the test module here
//! (module root src/) keeps every relative import inside the module path.
//! The comptime block below pulls the real root file into the compilation
//! (same idea as the `test { _ = @import(...); }` aggregator in
//! src/flattener.zig, but as a comptime block so no extra test is counted).
comptime {
    _ = @import("pkg/pkg_core_tests.zig");
}
