const std = @import("std");
const flatten = @import("expandimportsinto.zig").flatten;


test "hygiene: nested macro expansion applies unique ids" {
    const source =
        \\[MACRO] INNER %x
        \\    _val = add %x, 1
        \\    return _val
        \\[END_MACRO]
        \\[MACRO] OUTER %y
        \\    _val = add %y, 2
        \\    EXPAND INNER _val
        \\[END_MACRO]
        \\
        \\@main() -> i32:
        \\L_ENTRY:
        \\    _out = alloc 8
        \\    EXPAND OUTER 5
    ;

    var result = try flatten(std.testing.allocator, source);
    defer result.deinit(std.testing.allocator);

    // OUTER's _val should be hygienified
    try std.testing.expect(result.symbols.contains("_val__sa_hyg1"));
    // INNER's _val should get a different hygiene id
    try std.testing.expect(result.symbols.contains("_val__sa_hyg2"));
    // Both expansions produced _val, but with different ids
    // Original _val should NOT appear
    try std.testing.expect(!result.symbols.contains("_val"));
}

test "hygiene: while-let macro with multiple expansions" {
    const source =
        \\#def Option_SIZE = 8
        \\
        \\[MACRO] UNWRAP_OR_ZERO %out, %opt_ptr
        \\    _tag = load %opt_ptr+0 as u32
        \\    _is_some = eq _tag, 1
        \\    !_tag
        \\    br _is_some -> L_SOME, L_NONE
        \\L_SOME:
        \\    !_is_some
        \\    %out = load %opt_ptr+4 as i32
        \\    !%opt_ptr
        \\    jmp L_END
        \\L_NONE:
        \\    !_is_some
        \\    !%opt_ptr
        \\    %out = add 0, 0
        \\L_END:
        \\[END_MACRO]
        \\
        \\@main() -> i32:
        \\L_ENTRY:
        \\    opt0 = alloc Option_SIZE
        \\    store opt0+0, 1 as u32
        \\    store opt0+4, 42 as i32
        \\    opt1 = alloc Option_SIZE
        \\    store opt1+0, 0 as u32
        \\    EXPAND UNWRAP_OR_ZERO v0, opt0
        \\    EXPAND UNWRAP_OR_ZERO v1, opt1
        \\    sum = add v0, v1
        \\    return sum
    ;

    var result = try flatten(std.testing.allocator, source);
    defer result.deinit(std.testing.allocator);

    // Labels should be hygienified - different per expansion
    try std.testing.expect(result.symbols.contains("L_SOME__sa_hyg1"));
    try std.testing.expect(result.symbols.contains("L_SOME__sa_hyg2"));
    try std.testing.expect(!result.symbols.contains("L_SOME"));

    // Internal names should be hygienified
    try std.testing.expect(result.symbols.contains("_tag__sa_hyg1"));
    try std.testing.expect(result.symbols.contains("_tag__sa_hyg2"));
    try std.testing.expect(!result.symbols.contains("_tag"));

    // Output params should NOT be hygienified
    try std.testing.expect(result.symbols.contains("v0"));
    try std.testing.expect(result.symbols.contains("v1"));
}
