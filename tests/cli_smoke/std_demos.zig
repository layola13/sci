const std = @import("std");
const saasm = @import("saasm");
const builtin = @import("builtin");
const sio = @import("sio");

const helpers = @import("helpers.zig");
const assertRunStdout = helpers.assertRunStdout;
const assertBuildExeStdout = helpers.assertBuildExeStdout;
const assertBuildExeTrap = helpers.assertBuildExeTrap;
const assertCheckTrapWithArgs = helpers.assertCheckTrapWithArgs;
const assertCheckOkWithArgs = helpers.assertCheckOkWithArgs;

test "async await demo runs through sa run" {
    try assertRunStdout("demos/rosetta/09_async_await/main.sa", "2\n");
}

test "macro demo compiles and prints through build-exe" {
    try assertBuildExeStdout("demos/support/macro_print.sa", "macro ok\n");
}

test "sa_core macros compile and print through imported standard library macros" {
    try assertBuildExeStdout("demos/support/macro_core.sa", "macro core ok\n");
}

test "time demo compiles and prints through build-exe" {
    try assertBuildExeStdout("demos/support/time_probe.sa", "time ok\n");
}

test "time demo runs through sa run" {
    try assertRunStdout("demos/support/time_probe.sa", "time ok\n");
}

test "pthread vtable worker stores survive native join" {
    try assertBuildExeStdout("demos/support/pthread_vtable_store/main.sa", "ok\n");
}

test "mutex demo compiles and prints through build-exe" {
    try assertBuildExeStdout("demos/support/mutex_probe.sa", "mutex ok\n");
}

test "mutex demo runs through sa run" {
    try assertRunStdout("demos/support/mutex_probe.sa", "mutex ok\n");
}

test "once demo compiles and prints through build-exe" {
    try assertBuildExeStdout("demos/support/once_probe.sa", "once ok\n");
}

test "once demo runs through sa run" {
    try assertRunStdout("demos/support/once_probe.sa", "once ok\n");
}

test "mpsc demo compiles and prints through build-exe" {
    try assertBuildExeStdout("demos/support/mpsc_probe.sa", "mpsc ok\n");
}

test "mpsc demo runs through sa run" {
    try assertRunStdout("demos/support/mpsc_probe.sa", "mpsc ok\n");
}

test "io demo compiles and prints through build-exe" {
    try assertBuildExeStdout("demos/support/io_probe.sa", "alpha\n5\n");
}

test "hashmap demo compiles and prints through build-exe" {
    try assertBuildExeStdout("demos/support/hashmap_probe.sa", "alpha\nbravo\nmap ok\n");
}

test "hashset demo compiles and prints through build-exe" {
    try assertBuildExeStdout("demos/support/hashset_probe.sa", "set ok\n");
}

test "hashset demo runs through sa run" {
    try assertRunStdout("demos/support/hashset_probe.sa", "set ok\n");
}

test "sort demo compiles and prints through build-exe" {
    try assertBuildExeStdout("demos/support/sort_probe.sa", "sort ok\n");
}

test "use after move demo is rejected with structured trap output" {
    try assertBuildExeTrap("demos/support/use_after_move.sa", "use_after_move.out", "UseAfterMove", 1009, "moved value is no longer usable");
}

test "return after move demo is rejected with structured trap output" {
    try assertBuildExeTrap("demos/support/return_after_move.sa", "return_after_move.out", "UseAfterMove", 1009, "moved value is no longer usable");
}

test "borrow conflict demo is rejected with structured trap output" {
    try assertBuildExeTrap("demos/support/borrow_conflict.sa", "borrow_conflict.out", "BorrowConflict", 1008, "borrow rules reject this access");
}

test "double mutable borrow demo is rejected with structured trap output" {
    try assertBuildExeTrap("demos/support/mut_borrow_conflict.sa", "mut_borrow_conflict.out", "BorrowConflict", 1008, "borrow rules reject this access");
}

test "default immutable mode rejects a write without an exclusive borrow" {
    try assertCheckTrapWithArgs("demos/support/default_immutable_write.sa", &.{"--default-immutable"}, "ConstMutation", 1023, "immutable registers cannot be written, moved, or exclusively borrowed");
}

test "default immutable mode accepts the same program in the mutable mode" {
    try assertCheckOkWithArgs("demos/support/default_immutable_write.sa", &.{});
}

test "default immutable mode accepts an exclusive borrow" {
    try assertCheckOkWithArgs("demos/rosetta/962_mut_borrow_code/main.sa", &.{"--default-immutable"});
}

test "read write conflict demo is rejected with structured trap output" {
    try assertBuildExeTrap("demos/support/read_write_conflict.sa", "read_write_conflict.out", "ReadWriteConflict", 1011, "cannot write through a shared borrow");
}

test "illegal unsafe context demo is rejected with structured trap output" {
    try assertBuildExeTrap("demos/support/illegal_unsafe_context.sa", "illegal_unsafe_context.out", "IllegalUnsafeContext", 1019, "raw pointer and assume_* instructions are only legal inside @ffi_wrapper");
}

test "stack escape demo is rejected with structured trap output" {
    try assertBuildExeTrap("demos/support/stack_escape.sa", "stack_escape.out", "StackEscape", 1025, "stack allocation cannot be moved out of its function");
}

test "const mutation demo is rejected with structured trap output" {
    try assertBuildExeTrap("demos/support/const_mutation.sa", "const_mutation.out", "ConstMutation", 1023, "immutable registers cannot be released");
}

test "early return leak demo is rejected with structured trap output" {
    try assertBuildExeTrap("demos/support/early_return_leak.sa", "early_return_leak.out", "EarlyReturnLeak", 1026, "early return would leak live registers");
}

test "macro recursion demo is rejected with structured trap output" {
    try assertBuildExeTrap("demos/support/macro_recursion.sa", "macro_recursion.out", "MacroRecursionLimit", 1005, "macro recursion limit exceeded");
}

test "forbidden syntax demo is rejected with structured trap output" {
    try assertBuildExeTrap("demos/support/forbidden_syntax.sa", "forbidden_syntax.out", "ForbiddenSyntax", 1001, "forbidden syntax detected during flattening");
}

test "forbidden if demo is rejected with structured trap output" {
    try assertBuildExeTrap("demos/support/forbidden_if.sa", "forbidden_if.out", "ForbiddenSyntax", 1001, "forbidden syntax detected during flattening");
}

test "forbidden while demo is rejected with structured trap output" {
    try assertBuildExeTrap("demos/support/forbidden_while.sa", "forbidden_while.out", "ForbiddenSyntax", 1001, "forbidden syntax detected during flattening");
}

test "forbidden for demo is rejected with structured trap output" {
    try assertBuildExeTrap("demos/support/forbidden_for.sa", "forbidden_for.out", "ForbiddenSyntax", 1001, "forbidden syntax detected during flattening");
}

test "forbidden brace demo is rejected with structured trap output" {
    try assertBuildExeTrap("demos/support/forbidden_brace.sa", "forbidden_brace.out", "ForbiddenSyntax", 1001, "forbidden syntax detected during flattening");
}

test "forbidden property chain demo is rejected with structured trap output" {
    try assertBuildExeTrap("demos/support/forbidden_property_chain.sa", "forbidden_property_chain.out", "ForbiddenSyntax", 1001, "forbidden syntax detected during flattening");
}

test "memory leak after borrow demo is rejected with structured trap output" {
    try assertBuildExeTrap("demos/support/memory_leak_after_borrow.sa", "memory_leak_after_borrow.out", "MemoryLeak", 1012, "live registers remain at function exit");
}

test "memory leak partial release demo is rejected with structured trap output" {
    try assertBuildExeTrap("demos/support/memory_leak_partial_release.sa", "memory_leak_partial_release.out", "MemoryLeak", 1012, "live registers remain at function exit");
}

test "atomic ordering mismatch demo is rejected with structured trap output" {
    try assertBuildExeTrap("demos/support/atomic_ordering_mismatch.sa", "atomic_ordering_mismatch.out", "AtomicOrderingMismatch", 1029, "same-address RMW ordering combination is not allowed");
}

test "invalid atomic ordering demo is rejected with structured trap output" {
    try assertBuildExeTrap("demos/support/invalid_atomic_ordering.sa", "invalid_atomic_ordering.out", "InvalidAtomicOrdering", 1028, "invalid atomic ordering");
}

test "unknown register return demo is rejected with structured trap output" {
    try assertBuildExeTrap("demos/support/unknown_register_return.sa", "unknown_register_return.out", "UnknownRegister", 1007, "register is not declared in the current scope");
}

test "capability mismatch demo is rejected with structured trap output" {
    try assertBuildExeTrap("demos/support/capability_mismatch.sa", "capability_mismatch.out", "CapabilityMismatch", 1013, "call-site capability prefix does not match the callee contract");
}

test "package and module roadmap demos are rejected with structured trap output" {
    try assertBuildExeTrap("demos/rosetta/205_pkg_cyclic_dependency_reject/main.sa", "205_pkg_cyclic_dependency_reject.out", "ForbiddenSyntax", 1001, "import cycle detected during flattening");
    try assertBuildExeTrap("demos/rosetta/207_pkg_multiple_versions_conflict/main.sa", "207_pkg_multiple_versions_conflict.out", "DuplicateDef", 1002, "duplicate definition detected during flattening");
    try assertBuildExeTrap("demos/rosetta/226_mod_cyclic_import_detect/main.sa", "226_mod_cyclic_import_detect.out", "ForbiddenSyntax", 1001, "import cycle detected during flattening");
    try assertBuildExeTrap("demos/rosetta/227_mod_shadowing_prevention/main.sa", "227_mod_shadowing_prevention.out", "DuplicateDef", 1002, "duplicate definition detected during flattening");
    try assertBuildExeTrap("demos/rosetta/243_contract_sig_mismatch_link/main.sa", "243_contract_sig_mismatch_link.out", "CapabilityMismatch", 1013, "call-site capability prefix does not match the callee contract");
}
