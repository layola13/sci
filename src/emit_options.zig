pub const EmitOptions = struct {
    debug: bool = false,
    wasm_compat: bool = false,
    jobs: ?usize = null,
    test_mode: bool = false,
    opt_level: u8 = 0,
    codegen_unit_index: ?usize = null,
    codegen_unit_count: usize = 1,
};
