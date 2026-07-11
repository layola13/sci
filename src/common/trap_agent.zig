// GENERATED from src/common/trap.zig enum (authoritative). Do not hand-edit member set.
const std = @import("std");
const trapmod = @import("trap.zig");
pub const Trap = trapmod.Trap;
pub const trapName = trapmod.trapName;
pub const trapCode = trapmod.trapCode;

pub const TrapExplanation = struct {
    stable_code: []const u8,
    summary: []const u8,
    fix_hint: []const u8,
};

pub fn allTraps() []const Trap {
    return &.{
        .forbidden_syntax,
        .duplicate_def,
        .duplicate_label,
        .unsupported_type,
        .import_resolution_failed,
        .macro_recursion_limit,
        .register_redefinition,
        .unknown_register,
        .borrow_conflict,
        .use_after_move,
        .double_mutable_borrow,
        .read_write_conflict,
        .memory_leak,
        .capability_mismatch,
        .fallthrough_forbidden,
        .phi_state_conflict,
        .gas_exceeded,
        .arena_oom,
        .snapshot_version_mismatch,
        .illegal_unsafe_context,
        .ffi_ownership_violation,
        .unsupported_sys_intrinsic,
        .interior_ptr_escape,
        .const_mutation,
        .vtable_signature_mismatch,
        .stack_escape,
        .unauthorized_primitive,
        .upstream_sha_mismatch,
        .early_return_leak,
        .fallible_contract_mismatch,
        .invalid_atomic_ordering,
        .atomic_ordering_mismatch,
        .test_func_signature_mismatch,
        .db_capability_escalation,
        .db_memory_guard_violation,
        .db_blob_arena_oom,
        .db_concurrency_conflict,
        .db_schema_mismatch,
        .db_cursor_overflow,
        .db_column_type_mismatch,
        .db_query_hash_unknown,
        .db_blob_handle_invalid,
        .db_snapshot_corrupted,
        .db_duplicate_register,
        .db_forbidden_sql_string,
        .sax_state_leak,
        .sax_event_escape,
        .sax_render_outside_handler,
        .sax_invalid_interpolation,
        .sax_state_write_from_outside,
        .sax_unknown_tag,
        .sax_unknown_event,
        .machine_code_hash_mismatch,
        .blocked_risk_unconfirmed,
        .missing_tty_for_confirmation,
        .forbidden_global_config,
        .sum_hash_mismatch,
    };
}

pub fn trapStableCode(t: Trap) []const u8 {
    return switch (t) {
        .forbidden_syntax => "SA-FLAT-001",
        .duplicate_def => "SA-FLAT-002",
        .duplicate_label => "SA-FLAT-003",
        .unsupported_type => "SA-FLAT-004",
        .import_resolution_failed => "SA-FLAT-005",
        .macro_recursion_limit => "SA-FLAT-006",
        .register_redefinition => "SA-REF-001",
        .unknown_register => "SA-REF-002",
        .borrow_conflict => "SA-REF-003",
        .use_after_move => "SA-REF-004",
        .double_mutable_borrow => "SA-REF-005",
        .read_write_conflict => "SA-REF-006",
        .memory_leak => "SA-REF-007",
        .capability_mismatch => "SA-REF-008",
        .fallthrough_forbidden => "SA-REF-009",
        .phi_state_conflict => "SA-REF-010",
        .gas_exceeded => "SA-REF-011",
        .arena_oom => "SA-REF-012",
        .snapshot_version_mismatch => "SA-REF-013",
        .illegal_unsafe_context => "SA-REF-014",
        .ffi_ownership_violation => "SA-REF-015",
        .unsupported_sys_intrinsic => "SA-REF-016",
        .interior_ptr_escape => "SA-REF-017",
        .const_mutation => "SA-REF-018",
        .vtable_signature_mismatch => "SA-REF-019",
        .stack_escape => "SA-REF-020",
        .unauthorized_primitive => "SA-REF-021",
        .upstream_sha_mismatch => "SA-REF-022",
        .early_return_leak => "SA-REF-023",
        .fallible_contract_mismatch => "SA-REF-024",
        .invalid_atomic_ordering => "SA-REF-025",
        .atomic_ordering_mismatch => "SA-REF-026",
        .test_func_signature_mismatch => "SA-REF-027",
        .db_capability_escalation => "SA-DB-001",
        .db_memory_guard_violation => "SA-DB-002",
        .db_blob_arena_oom => "SA-DB-003",
        .db_concurrency_conflict => "SA-DB-004",
        .db_schema_mismatch => "SA-DB-005",
        .db_cursor_overflow => "SA-DB-006",
        .db_column_type_mismatch => "SA-DB-007",
        .db_query_hash_unknown => "SA-DB-008",
        .db_blob_handle_invalid => "SA-DB-009",
        .db_snapshot_corrupted => "SA-DB-010",
        .db_duplicate_register => "SA-DB-011",
        .db_forbidden_sql_string => "SA-DB-012",
        .sax_state_leak => "SA-SAX-001",
        .sax_event_escape => "SA-SAX-002",
        .sax_render_outside_handler => "SA-SAX-003",
        .sax_invalid_interpolation => "SA-SAX-004",
        .sax_state_write_from_outside => "SA-SAX-005",
        .sax_unknown_tag => "SA-SAX-006",
        .sax_unknown_event => "SA-SAX-007",
        .machine_code_hash_mismatch => "SA-SYS-001",
        .blocked_risk_unconfirmed => "SA-SYS-002",
        .missing_tty_for_confirmation => "SA-SYS-003",
        .forbidden_global_config => "SA-SYS-004",
        .sum_hash_mismatch => "SA-SYS-005",
    };
}

pub fn explainTrap(t: Trap) TrapExplanation {
    return switch (t) {
        .forbidden_syntax => .{ .stable_code = "SA-FLAT-001", .summary = "Flattener rejected the input before verification.", .fix_hint = "Lower the surface syntax into the accepted linear SA form." },
        .duplicate_def => .{ .stable_code = "SA-FLAT-002", .summary = "Flattener rejected the input before verification.", .fix_hint = "Lower the surface syntax into the accepted linear SA form." },
        .duplicate_label => .{ .stable_code = "SA-FLAT-003", .summary = "Flattener rejected the input before verification.", .fix_hint = "Lower the surface syntax into the accepted linear SA form." },
        .unsupported_type => .{ .stable_code = "SA-FLAT-004", .summary = "Flattener rejected the input before verification.", .fix_hint = "Lower the surface syntax into the accepted linear SA form." },
        .import_resolution_failed => .{ .stable_code = "SA-FLAT-005", .summary = "Flattener rejected the input before verification.", .fix_hint = "Lower the surface syntax into the accepted linear SA form." },
        .macro_recursion_limit => .{ .stable_code = "SA-FLAT-006", .summary = "Flattener rejected the input before verification.", .fix_hint = "Lower the surface syntax into the accepted linear SA form." },
        .register_redefinition => .{ .stable_code = "SA-REF-001", .summary = "The referee rejected the instruction stream during verification.", .fix_hint = "Fix the ownership/capability/borrow violation the verifier reported." },
        .unknown_register => .{ .stable_code = "SA-REF-002", .summary = "The referee rejected the instruction stream during verification.", .fix_hint = "Fix the ownership/capability/borrow violation the verifier reported." },
        .borrow_conflict => .{ .stable_code = "SA-REF-003", .summary = "The referee rejected the instruction stream during verification.", .fix_hint = "Fix the ownership/capability/borrow violation the verifier reported." },
        .use_after_move => .{ .stable_code = "SA-REF-004", .summary = "The referee rejected the instruction stream during verification.", .fix_hint = "Fix the ownership/capability/borrow violation the verifier reported." },
        .double_mutable_borrow => .{ .stable_code = "SA-REF-005", .summary = "The referee rejected the instruction stream during verification.", .fix_hint = "Fix the ownership/capability/borrow violation the verifier reported." },
        .read_write_conflict => .{ .stable_code = "SA-REF-006", .summary = "The referee rejected the instruction stream during verification.", .fix_hint = "Fix the ownership/capability/borrow violation the verifier reported." },
        .memory_leak => .{ .stable_code = "SA-REF-007", .summary = "The referee rejected the instruction stream during verification.", .fix_hint = "Fix the ownership/capability/borrow violation the verifier reported." },
        .capability_mismatch => .{ .stable_code = "SA-REF-008", .summary = "The referee rejected the instruction stream during verification.", .fix_hint = "Fix the ownership/capability/borrow violation the verifier reported." },
        .fallthrough_forbidden => .{ .stable_code = "SA-REF-009", .summary = "The referee rejected the instruction stream during verification.", .fix_hint = "Fix the ownership/capability/borrow violation the verifier reported." },
        .phi_state_conflict => .{ .stable_code = "SA-REF-010", .summary = "The referee rejected the instruction stream during verification.", .fix_hint = "Fix the ownership/capability/borrow violation the verifier reported." },
        .gas_exceeded => .{ .stable_code = "SA-REF-011", .summary = "The referee rejected the instruction stream during verification.", .fix_hint = "Fix the ownership/capability/borrow violation the verifier reported." },
        .arena_oom => .{ .stable_code = "SA-REF-012", .summary = "The referee rejected the instruction stream during verification.", .fix_hint = "Fix the ownership/capability/borrow violation the verifier reported." },
        .snapshot_version_mismatch => .{ .stable_code = "SA-REF-013", .summary = "The referee rejected the instruction stream during verification.", .fix_hint = "Fix the ownership/capability/borrow violation the verifier reported." },
        .illegal_unsafe_context => .{ .stable_code = "SA-REF-014", .summary = "The referee rejected the instruction stream during verification.", .fix_hint = "Fix the ownership/capability/borrow violation the verifier reported." },
        .ffi_ownership_violation => .{ .stable_code = "SA-REF-015", .summary = "The referee rejected the instruction stream during verification.", .fix_hint = "Fix the ownership/capability/borrow violation the verifier reported." },
        .unsupported_sys_intrinsic => .{ .stable_code = "SA-REF-016", .summary = "The referee rejected the instruction stream during verification.", .fix_hint = "Fix the ownership/capability/borrow violation the verifier reported." },
        .interior_ptr_escape => .{ .stable_code = "SA-REF-017", .summary = "The referee rejected the instruction stream during verification.", .fix_hint = "Fix the ownership/capability/borrow violation the verifier reported." },
        .const_mutation => .{ .stable_code = "SA-REF-018", .summary = "The referee rejected the instruction stream during verification.", .fix_hint = "Fix the ownership/capability/borrow violation the verifier reported." },
        .vtable_signature_mismatch => .{ .stable_code = "SA-REF-019", .summary = "The referee rejected the instruction stream during verification.", .fix_hint = "Fix the ownership/capability/borrow violation the verifier reported." },
        .stack_escape => .{ .stable_code = "SA-REF-020", .summary = "The referee rejected the instruction stream during verification.", .fix_hint = "Fix the ownership/capability/borrow violation the verifier reported." },
        .unauthorized_primitive => .{ .stable_code = "SA-REF-021", .summary = "The referee rejected the instruction stream during verification.", .fix_hint = "Fix the ownership/capability/borrow violation the verifier reported." },
        .upstream_sha_mismatch => .{ .stable_code = "SA-REF-022", .summary = "The referee rejected the instruction stream during verification.", .fix_hint = "Fix the ownership/capability/borrow violation the verifier reported." },
        .early_return_leak => .{ .stable_code = "SA-REF-023", .summary = "The referee rejected the instruction stream during verification.", .fix_hint = "Fix the ownership/capability/borrow violation the verifier reported." },
        .fallible_contract_mismatch => .{ .stable_code = "SA-REF-024", .summary = "The referee rejected the instruction stream during verification.", .fix_hint = "Fix the ownership/capability/borrow violation the verifier reported." },
        .invalid_atomic_ordering => .{ .stable_code = "SA-REF-025", .summary = "The referee rejected the instruction stream during verification.", .fix_hint = "Fix the ownership/capability/borrow violation the verifier reported." },
        .atomic_ordering_mismatch => .{ .stable_code = "SA-REF-026", .summary = "The referee rejected the instruction stream during verification.", .fix_hint = "Fix the ownership/capability/borrow violation the verifier reported." },
        .test_func_signature_mismatch => .{ .stable_code = "SA-REF-027", .summary = "The referee rejected the instruction stream during verification.", .fix_hint = "Fix the ownership/capability/borrow violation the verifier reported." },
        .db_capability_escalation => .{ .stable_code = "SA-DB-001", .summary = "The database capability layer rejected the operation.", .fix_hint = "Adjust the DB capability, schema, or query to satisfy the guard." },
        .db_memory_guard_violation => .{ .stable_code = "SA-DB-002", .summary = "The database capability layer rejected the operation.", .fix_hint = "Adjust the DB capability, schema, or query to satisfy the guard." },
        .db_blob_arena_oom => .{ .stable_code = "SA-DB-003", .summary = "The database capability layer rejected the operation.", .fix_hint = "Adjust the DB capability, schema, or query to satisfy the guard." },
        .db_concurrency_conflict => .{ .stable_code = "SA-DB-004", .summary = "The database capability layer rejected the operation.", .fix_hint = "Adjust the DB capability, schema, or query to satisfy the guard." },
        .db_schema_mismatch => .{ .stable_code = "SA-DB-005", .summary = "The database capability layer rejected the operation.", .fix_hint = "Adjust the DB capability, schema, or query to satisfy the guard." },
        .db_cursor_overflow => .{ .stable_code = "SA-DB-006", .summary = "The database capability layer rejected the operation.", .fix_hint = "Adjust the DB capability, schema, or query to satisfy the guard." },
        .db_column_type_mismatch => .{ .stable_code = "SA-DB-007", .summary = "The database capability layer rejected the operation.", .fix_hint = "Adjust the DB capability, schema, or query to satisfy the guard." },
        .db_query_hash_unknown => .{ .stable_code = "SA-DB-008", .summary = "The database capability layer rejected the operation.", .fix_hint = "Adjust the DB capability, schema, or query to satisfy the guard." },
        .db_blob_handle_invalid => .{ .stable_code = "SA-DB-009", .summary = "The database capability layer rejected the operation.", .fix_hint = "Adjust the DB capability, schema, or query to satisfy the guard." },
        .db_snapshot_corrupted => .{ .stable_code = "SA-DB-010", .summary = "The database capability layer rejected the operation.", .fix_hint = "Adjust the DB capability, schema, or query to satisfy the guard." },
        .db_duplicate_register => .{ .stable_code = "SA-DB-011", .summary = "The database capability layer rejected the operation.", .fix_hint = "Adjust the DB capability, schema, or query to satisfy the guard." },
        .db_forbidden_sql_string => .{ .stable_code = "SA-DB-012", .summary = "The database capability layer rejected the operation.", .fix_hint = "Adjust the DB capability, schema, or query to satisfy the guard." },
        .sax_state_leak => .{ .stable_code = "SA-SAX-001", .summary = "The SAX (UI) validation layer rejected the construct.", .fix_hint = "Correct the SAX handler/state/render usage." },
        .sax_event_escape => .{ .stable_code = "SA-SAX-002", .summary = "The SAX (UI) validation layer rejected the construct.", .fix_hint = "Correct the SAX handler/state/render usage." },
        .sax_render_outside_handler => .{ .stable_code = "SA-SAX-003", .summary = "The SAX (UI) validation layer rejected the construct.", .fix_hint = "Correct the SAX handler/state/render usage." },
        .sax_invalid_interpolation => .{ .stable_code = "SA-SAX-004", .summary = "The SAX (UI) validation layer rejected the construct.", .fix_hint = "Correct the SAX handler/state/render usage." },
        .sax_state_write_from_outside => .{ .stable_code = "SA-SAX-005", .summary = "The SAX (UI) validation layer rejected the construct.", .fix_hint = "Correct the SAX handler/state/render usage." },
        .sax_unknown_tag => .{ .stable_code = "SA-SAX-006", .summary = "The SAX (UI) validation layer rejected the construct.", .fix_hint = "Correct the SAX handler/state/render usage." },
        .sax_unknown_event => .{ .stable_code = "SA-SAX-007", .summary = "The SAX (UI) validation layer rejected the construct.", .fix_hint = "Correct the SAX handler/state/render usage." },
        .machine_code_hash_mismatch => .{ .stable_code = "SA-SYS-001", .summary = "A system/CLI-level guard refused the operation.", .fix_hint = "Resolve the environment/config/confirmation precondition." },
        .blocked_risk_unconfirmed => .{ .stable_code = "SA-SYS-002", .summary = "A system/CLI-level guard refused the operation.", .fix_hint = "Resolve the environment/config/confirmation precondition." },
        .missing_tty_for_confirmation => .{ .stable_code = "SA-SYS-003", .summary = "A system/CLI-level guard refused the operation.", .fix_hint = "Resolve the environment/config/confirmation precondition." },
        .forbidden_global_config => .{ .stable_code = "SA-SYS-004", .summary = "A system/CLI-level guard refused the operation.", .fix_hint = "Resolve the environment/config/confirmation precondition." },
        .sum_hash_mismatch => .{ .stable_code = "SA-SYS-005", .summary = "A system/CLI-level guard refused the operation.", .fix_hint = "Resolve the environment/config/confirmation precondition." },
    };
}

pub fn trapFromName(name: []const u8) ?Trap {
    for (allTraps()) |t| { if (std.mem.eql(u8, trapName(t), name)) return t; }
    return null;
}

pub fn trapFromStableCode(code: []const u8) ?Trap {
    for (allTraps()) |t| { if (std.mem.eql(u8, trapStableCode(t), code)) return t; }
    return null;
}

pub fn trapFromNumericCode(code: u32) ?Trap {
    for (allTraps()) |t| { if (trapCode(t) == code) return t; }
    return null;
}

test "all 57 traps have unique stable codes and resolve three ways" {
    var seen = std.AutoHashMap([]const u8, void).init(std.testing.allocator);
    defer seen.deinit();
    try std.testing.expectEqual(@as(usize, 57), allTraps().len);
    for (allTraps()) |t| {
        const sc = trapStableCode(t);
        try std.testing.expect(!seen.contains(sc));
        try seen.put(sc, {});
        try std.testing.expectEqual(t, trapFromName(trapName(t)).?);
        try std.testing.expectEqual(t, trapFromStableCode(sc).?);
        try std.testing.expectEqual(t, trapFromNumericCode(trapCode(t)).?);
    }
}
