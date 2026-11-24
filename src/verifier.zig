// Split from verifier.zig: thin re-export shim.
// Implementation lives in verifier/ (one module per chunk).

pub const RegStateChange = @import("verifier/reg_state_change.zig").RegStateChange;
pub const AnnotatedInstruction = @import("verifier/reg_state_change.zig").AnnotatedInstruction;
pub const VerifyOk = @import("verifier/reg_state_change.zig").VerifyOk;
pub const VerifyResult = @import("verifier/reg_state_change.zig").VerifyResult;
pub const VerifyOptions = @import("verifier/reg_state_change.zig").VerifyOptions;
pub const VerifyStageReporter = @import("verifier/reg_state_change.zig").VerifyStageReporter;
pub const SaxValidationContext = @import("verifier/reg_state_change.zig").SaxValidationContext;
pub const populateTrustedRegScopes = @import("verifier/sax_trap_report.zig").populateTrustedRegScopes;
pub const verifyWithOptions = @import("verifier/free_annotated_slice.zig").verifyWithOptions;
pub const verify = @import("verifier/free_annotated_slice.zig").verify;
const _mod_const_trap = @import("verifier/const_trap.zig");
const _mod_snapshot_merge_state_in_scope = @import("verifier/snapshot_merge_state_in_scope.zig");
const _mod_collect_metadata = @import("verifier/collect_metadata.zig");
const _mod_clear_borrow_ctx = @import("verifier/clear_borrow_ctx.zig");
const _mod_verify_body = @import("verifier/verify_body.zig");
const _mod_tests_verifier_preclassifies_each_instru = @import("verifier/tests_verifier_preclassifies_each_instru.zig");
const _mod_tests_interior_pointers_are_consumed_whe = @import("verifier/tests_interior_pointers_are_consumed_whe.zig");
const _mod_tests_ffi_borrow_views_can_be_moved_or_r = @import("verifier/tests_ffi_borrow_views_can_be_moved_or_r.zig");
const _mod_tests_native_escape_conservatively_consu = @import("verifier/tests_native_escape_conservatively_consu.zig");
const _mod_tests_cfg_integrity_pbt_keeps_matching_b = @import("verifier/tests_cfg_integrity_pbt_keeps_matching_b.zig");
const _mod_tests_assume_safe_of_owned_alloc_still_t = @import("verifier/tests_assume_safe_of_owned_alloc_still_t.zig");
const _mod_tests_bfull_scalar_ownership = @import("verifier/tests_bfull_scalar_ownership.zig");
