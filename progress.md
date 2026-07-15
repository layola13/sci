# SCI Progress

Scope: `/home/vscode/projects/sci` compiler std/runtime/CLI work.

## Completed: 2026-07-15 Hash tuple11 u64 macros

- Continued Rust `std::hash` macro-surface parity, referencing Rust's local tuple `Hash` implementation under `/home/vscode/projects/rust`.
- `sa_std/hash.sa`: added `DEFAULT_HASHER_WRITE_TUPLE11_U64`, `HASH_TUPLE11_U64`, `BUILD_HASHER_DEFAULT_HASH_ONE_TUPLE11_U64`, and `RANDOM_STATE_HASH_ONE_TUPLE11_U64`.
- The helper surface models `(u64, u64, u64, u64, u64, u64, u64, u64, u64, u64, u64)` tuple hashing by writing each field in order through the existing deterministic `u64` writer. It does not claim generic tuple trait dispatch, tuple arities beyond the concrete helpers, non-`u64` elements, or SipHash output compatibility.
- Test: `tests/unit_framework/std_hash_tuple11_u64_macro_surface.sa` - 1 test (panic ID 10574) covering direct/manual equivalence, order sensitivity, value sensitivity, `BuildHasherDefault::hash_one`, and `RandomState::hash_one`.
- Validation status:
  - Focused only: `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_hash_tuple11_u64_macro_surface.sa --jobs 1 --trace-panic` -> `1 passed; 0 failed; 0 skipped`.
  - Full tests intentionally not run because prior full runs caused memory pressure; this batch only runs the newly added focused test.
- Panic IDs next free: 10575+.

## Completed: 2026-07-15 Hash tuple10 u64 macros

- Continued Rust `std::hash` macro-surface parity, referencing Rust's local tuple `Hash` implementation under `/home/vscode/projects/rust`.
- `sa_std/hash.sa`: added `DEFAULT_HASHER_WRITE_TUPLE10_U64`, `HASH_TUPLE10_U64`, `BUILD_HASHER_DEFAULT_HASH_ONE_TUPLE10_U64`, and `RANDOM_STATE_HASH_ONE_TUPLE10_U64`.
- The helper surface models `(u64, u64, u64, u64, u64, u64, u64, u64, u64, u64)` tuple hashing by writing each field in order through the existing deterministic `u64` writer. It does not claim generic tuple trait dispatch, tuple arities beyond the concrete helpers, non-`u64` elements, or SipHash output compatibility.
- Test: `tests/unit_framework/std_hash_tuple10_u64_macro_surface.sa` - 1 test (panic ID 10573) covering direct/manual equivalence, order sensitivity, value sensitivity, `BuildHasherDefault::hash_one`, and `RandomState::hash_one`.
- Validation status:
  - Focused only: `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_hash_tuple10_u64_macro_surface.sa --jobs 1 --trace-panic` -> `1 passed; 0 failed; 0 skipped`.
  - Full tests intentionally not run because prior full runs caused memory pressure; this batch only runs the newly added focused test.
- Panic IDs next free: 10574+.

## Completed: 2026-07-15 Hash tuple9 u64 macros

- Continued Rust `std::hash` macro-surface parity, referencing Rust's local tuple `Hash` implementation under `/home/vscode/projects/rust`.
- `sa_std/hash.sa`: added `DEFAULT_HASHER_WRITE_TUPLE9_U64`, `HASH_TUPLE9_U64`, `BUILD_HASHER_DEFAULT_HASH_ONE_TUPLE9_U64`, and `RANDOM_STATE_HASH_ONE_TUPLE9_U64`.
- The helper surface models `(u64, u64, u64, u64, u64, u64, u64, u64, u64)` tuple hashing by writing each field in order through the existing deterministic `u64` writer. It does not claim generic tuple trait dispatch, tuple arities beyond the concrete helpers, non-`u64` elements, or SipHash output compatibility.
- Test: `tests/unit_framework/std_hash_tuple9_u64_macro_surface.sa` - 1 test (panic ID 10572) covering direct/manual equivalence, order sensitivity, value sensitivity, `BuildHasherDefault::hash_one`, and `RandomState::hash_one`.
- Validation status:
  - Focused only: `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_hash_tuple9_u64_macro_surface.sa --jobs 1 --trace-panic` -> `1 passed; 0 failed; 0 skipped`.
  - Full tests intentionally not run because prior full runs caused memory pressure; this batch only runs the newly added focused test.
- Panic IDs next free: 10573+.

## Completed: 2026-07-15 Hash tuple8 u64 macros

- Continued Rust `std::hash` macro-surface parity, referencing Rust's local tuple `Hash` implementation under `/home/vscode/projects/rust`.
- `sa_std/hash.sa`: added `DEFAULT_HASHER_WRITE_TUPLE8_U64`, `HASH_TUPLE8_U64`, `BUILD_HASHER_DEFAULT_HASH_ONE_TUPLE8_U64`, and `RANDOM_STATE_HASH_ONE_TUPLE8_U64`.
- The helper surface models `(u64, u64, u64, u64, u64, u64, u64, u64)` tuple hashing by writing each field in order through the existing deterministic `u64` writer. It does not claim generic tuple trait dispatch, tuple arities beyond the concrete helpers, non-`u64` elements, or SipHash output compatibility.
- Test: `tests/unit_framework/std_hash_tuple8_u64_macro_surface.sa` - 1 test (panic ID 10571) covering direct/manual equivalence, order sensitivity, value sensitivity, `BuildHasherDefault::hash_one`, and `RandomState::hash_one`.
- Validation status:
  - Focused only: `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_hash_tuple8_u64_macro_surface.sa --jobs 1 --trace-panic` -> `1 passed; 0 failed; 0 skipped`.
  - Full tests intentionally not run because prior full runs caused memory pressure; this batch only runs the newly added focused test.
- Panic IDs next free: 10572+.

## Completed: 2026-07-15 Hash tuple7 u64 macros

- Continued Rust `std::hash` macro-surface parity, referencing Rust's local tuple `Hash` implementation under `/home/vscode/projects/rust`.
- `sa_std/hash.sa`: added `DEFAULT_HASHER_WRITE_TUPLE7_U64`, `HASH_TUPLE7_U64`, `BUILD_HASHER_DEFAULT_HASH_ONE_TUPLE7_U64`, and `RANDOM_STATE_HASH_ONE_TUPLE7_U64`.
- The helper surface models `(u64, u64, u64, u64, u64, u64, u64)` tuple hashing by writing each field in order through the existing deterministic `u64` writer. It does not claim generic tuple trait dispatch, tuple arities beyond the concrete helpers, non-`u64` elements, or SipHash output compatibility.
- Test: `tests/unit_framework/std_hash_tuple7_u64_macro_surface.sa` - 1 test (panic ID 10570) covering direct/manual equivalence, order sensitivity, value sensitivity, `BuildHasherDefault::hash_one`, and `RandomState::hash_one`.
- Validation status:
  - Focused only: `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_hash_tuple7_u64_macro_surface.sa --jobs 1 --trace-panic` -> `1 passed; 0 failed; 0 skipped`.
  - Full tests intentionally not run because prior full runs caused memory pressure; this batch only runs the newly added focused test.
- Panic IDs next free: 10571+.

## Completed: 2026-07-15 Hash tuple6 u64 macros

- Continued Rust `std::hash` macro-surface parity, referencing Rust's local tuple `Hash` implementation under `/home/vscode/projects/rust`.
- `sa_std/hash.sa`: added `DEFAULT_HASHER_WRITE_TUPLE6_U64`, `HASH_TUPLE6_U64`, `BUILD_HASHER_DEFAULT_HASH_ONE_TUPLE6_U64`, and `RANDOM_STATE_HASH_ONE_TUPLE6_U64`.
- The helper surface models `(u64, u64, u64, u64, u64, u64)` tuple hashing by writing each field in order through the existing deterministic `u64` writer. It does not claim generic tuple trait dispatch, tuple arities beyond the concrete helpers, non-`u64` elements, or SipHash output compatibility.
- Test: `tests/unit_framework/std_hash_tuple6_u64_macro_surface.sa` - 1 test (panic ID 10569) covering direct/manual equivalence, order sensitivity, value sensitivity, `BuildHasherDefault::hash_one`, and `RandomState::hash_one`.
- Validation status:
  - Focused only: `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_hash_tuple6_u64_macro_surface.sa --jobs 1 --trace-panic` -> `1 passed; 0 failed; 0 skipped`.
  - Full tests intentionally not run because prior full runs caused memory pressure; this batch only runs the newly added focused test.
- Panic IDs next free: 10570+.

## Completed: 2026-07-15 Hash tuple5 u64 macros

- Continued Rust `std::hash` macro-surface parity, referencing Rust's local tuple `Hash` implementation under `/home/vscode/projects/rust`.
- `sa_std/hash.sa`: added `DEFAULT_HASHER_WRITE_TUPLE5_U64`, `HASH_TUPLE5_U64`, `BUILD_HASHER_DEFAULT_HASH_ONE_TUPLE5_U64`, and `RANDOM_STATE_HASH_ONE_TUPLE5_U64`.
- The helper surface models `(u64, u64, u64, u64, u64)` tuple hashing by writing each field in order through the existing deterministic `u64` writer. It does not claim generic tuple trait dispatch, tuple arities beyond the concrete helpers, non-`u64` elements, or SipHash output compatibility.
- Test: `tests/unit_framework/std_hash_tuple5_u64_macro_surface.sa` - 1 test (panic ID 10568) covering direct/manual equivalence, order sensitivity, value sensitivity, `BuildHasherDefault::hash_one`, and `RandomState::hash_one`.
- Validation status:
  - Focused only: `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_hash_tuple5_u64_macro_surface.sa --jobs 1 --trace-panic` -> `1 passed; 0 failed; 0 skipped`.
  - Full tests intentionally not run because prior full runs caused memory pressure; this batch only runs the newly added focused test.
- Panic IDs next free: 10569+.

## Completed: 2026-07-15 Hash tuple4 u64 macros

- Continued Rust `std::hash` macro-surface parity, referencing Rust's local tuple `Hash` implementation under `/home/vscode/projects/rust`.
- `sa_std/hash.sa`: added `DEFAULT_HASHER_WRITE_TUPLE4_U64`, `HASH_TUPLE4_U64`, `BUILD_HASHER_DEFAULT_HASH_ONE_TUPLE4_U64`, and `RANDOM_STATE_HASH_ONE_TUPLE4_U64`.
- The helper surface models `(u64, u64, u64, u64)` tuple hashing by writing each field in order through the existing deterministic `u64` writer. It does not claim generic tuple trait dispatch, tuple arities beyond the concrete helpers, non-`u64` elements, or SipHash output compatibility.
- Test: `tests/unit_framework/std_hash_tuple4_u64_macro_surface.sa` - 1 test (panic ID 10567) covering direct/manual equivalence, order sensitivity, value sensitivity, `BuildHasherDefault::hash_one`, and `RandomState::hash_one`.
- Validation status:
  - Focused only: `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_hash_tuple4_u64_macro_surface.sa --jobs 1 --trace-panic` -> `1 passed; 0 failed; 0 skipped`.
  - Full tests intentionally not run because prior full runs caused memory pressure; this batch only runs the newly added focused test.
- Panic IDs next free: 10568+.

## Completed: 2026-07-15 Hash tuple3 u64 macros

- Continued Rust `std::hash` macro-surface parity, referencing Rust's local tuple `Hash` implementation under `/home/vscode/projects/rust`.
- `sa_std/hash.sa`: added `DEFAULT_HASHER_WRITE_TUPLE3_U64`, `HASH_TUPLE3_U64`, `BUILD_HASHER_DEFAULT_HASH_ONE_TUPLE3_U64`, and `RANDOM_STATE_HASH_ONE_TUPLE3_U64`.
- The helper surface models `(u64, u64, u64)` tuple hashing by writing each field in order through the existing deterministic `u64` writer. It does not claim generic tuple trait dispatch, tuple arities beyond the concrete helpers, non-`u64` elements, or SipHash output compatibility.
- Test: `tests/unit_framework/std_hash_tuple3_u64_macro_surface.sa` - 1 test (panic ID 10566) covering direct/manual equivalence, order sensitivity, value sensitivity, `BuildHasherDefault::hash_one`, and `RandomState::hash_one`.
- Validation status:
  - Focused only: `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_hash_tuple3_u64_macro_surface.sa --jobs 1 --trace-panic` -> `1 passed; 0 failed; 0 skipped`.
  - Full tests intentionally not run because prior full runs caused memory pressure; this batch only runs the newly added focused test.
- Panic IDs next free: 10567+.

## Completed: 2026-07-15 Hash tuple2 u64 macros

- Continued Rust `std::hash` macro-surface parity, referencing Rust's local tuple `Hash` implementation under `/home/vscode/projects/rust`.
- `sa_std/hash.sa`: added `DEFAULT_HASHER_WRITE_TUPLE2_U64`, `HASH_TUPLE2_U64`, `BUILD_HASHER_DEFAULT_HASH_ONE_TUPLE2_U64`, and `RANDOM_STATE_HASH_ONE_TUPLE2_U64`.
- The helper surface models `(u64, u64)` tuple hashing by writing each field in order through the existing deterministic `u64` writer. It does not claim generic tuple trait dispatch, tuple arities beyond two, non-`u64` elements, or SipHash output compatibility.
- Test: `tests/unit_framework/std_hash_tuple2_u64_macro_surface.sa` - 1 test (panic ID 10565) covering direct/manual equivalence, order sensitivity, value sensitivity, `BuildHasherDefault::hash_one`, and `RandomState::hash_one`.
- Validation status:
  - Focused only: `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_hash_tuple2_u64_macro_surface.sa --jobs 1 --trace-panic` -> `1 passed; 0 failed; 0 skipped`.
  - Full tests intentionally not run because prior full runs caused memory pressure; this batch only runs the newly added focused test.
- Panic IDs next free: 10566+.

## Completed: 2026-07-15 Hash_one pointer macros

- Continued Rust `std::hash` macro-surface parity, referencing Rust's local raw pointer `Hash` implementations under `/home/vscode/projects/rust`.
- `sa_std/hash.sa`: added `BUILD_HASHER_DEFAULT_HASH_ONE_PTR_VALUE` and `RANDOM_STATE_HASH_ONE_PTR_VALUE`.
- The helper surface models sized raw pointer hashing by writing the pointer address through the existing concrete pointer writer and then applying unit metadata hashing as a no-op. It does not claim unsized pointer metadata hashing, reference forwarding, generic `Hash` trait dispatch, or SipHash output compatibility.
- Test: `tests/unit_framework/std_hash_ptr_hash_one_macro_surface.sa` - 1 test (panic ID 10564) covering `BuildHasherDefault` equivalence with direct `HASH_PTR_VALUE`, `RandomState` equivalence with manual `RANDOM_STATE_BUILD + DEFAULT_HASHER_WRITE_PTR`, and seeded-state difference.
- Validation status:
  - Focused only: `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_hash_ptr_hash_one_macro_surface.sa --jobs 1 --trace-panic` -> `1 passed; 0 failed; 0 skipped`.
  - Full tests intentionally not run because prior full runs caused memory pressure; this batch only runs the newly added focused test.
- Panic IDs next free: 10565+.

## Completed: 2026-07-15 Hash unit macros

- Continued Rust `std::hash` macro-surface parity, referencing Rust's local `Hash for ()` implementation under `/home/vscode/projects/rust`.
- `sa_std/hash.sa`: added `DEFAULT_HASHER_WRITE_UNIT`, `HASH_UNIT`, `BUILD_HASHER_DEFAULT_HASH_ONE_UNIT`, and `RANDOM_STATE_HASH_ONE_UNIT`.
- The helper surface models Rust unit hashing as a no-op on the current hasher. The macros take an ignored placeholder unit value because SA macro invocations require concrete argument syntax; that value is not mixed into the hasher state.
- Test: `tests/unit_framework/std_hash_unit_macro_surface.sa` - 1 test (panic ID 10563) covering default unit hash, direct one-shot hash, `BuildHasherDefault::hash_one`, `RandomState::hash_one`, and no-op behavior after a prior write.
- Validation status:
  - Focused only: `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_hash_unit_macro_surface.sa --jobs 1 --trace-panic` -> `1 passed; 0 failed; 0 skipped`.
  - Full tests intentionally not run because prior full runs caused memory pressure; this batch only runs the newly added focused test.
- Panic IDs next free: 10564+.

## Completed: 2026-07-15 Hash_one bool/char macros

- Continued Rust `std::hash` macro-surface parity, referencing Rust's local `BuildHasher::hash_one`, `Hash for bool`, and `Hash for char` implementations under `/home/vscode/projects/rust`.
- `sa_std/hash.sa`: added `BUILD_HASHER_DEFAULT_HASH_ONE_BOOL`, `BUILD_HASHER_DEFAULT_HASH_ONE_CHAR`, `RANDOM_STATE_HASH_ONE_BOOL`, and `RANDOM_STATE_HASH_ONE_CHAR`.
- The helper surface builds a fresh hasher, writes exactly one concrete bool/char value through the matching existing writer, and finishes it. It preserves the current bool normalization and frontend-valid char scalar contract without claiming generic `Hash` trait dispatch or SipHash output compatibility.
- Test: `tests/unit_framework/std_hash_bool_char_hash_one_macro_surface.sa` - 1 test (panic ID 10562) covering `BuildHasherDefault` equivalence with direct `HASH_BOOL` / `HASH_CHAR`, `RandomState` equivalence with manual `RANDOM_STATE_BUILD + DEFAULT_HASHER_WRITE_*`, bool normalization, and true/false distinction.
- Validation status:
  - Focused only: `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_hash_bool_char_hash_one_macro_surface.sa --jobs 1 --trace-panic` -> `1 passed; 0 failed; 0 skipped`.
  - Full tests intentionally not run because prior full runs caused memory pressure; this batch only runs the newly added focused test.
- Panic IDs next free: 10563+.

## Completed: 2026-07-15 Hash_one integer primitive macros

- Continued Rust `std::hash` macro-surface parity, referencing Rust's local `BuildHasher::hash_one` default implementation under `/home/vscode/projects/rust`.
- `sa_std/hash.sa`: added integer primitive `hash_one` variants for both deterministic `BuildHasherDefault` and `RandomState`: `U8`, `U16`, `U32`, `USIZE`, `I8`, `I16`, `I32`, `I64`, and `ISIZE`.
- The helper surface builds a fresh hasher, writes exactly one concrete primitive value through the matching existing writer, and finishes it. It does not claim generic `Hash` trait dispatch, `u128` / `i128`, OS-random `RandomState`, collection integration, or SipHash output compatibility.
- Test: `tests/unit_framework/std_hash_builder_integer_hash_one_macro_surface.sa` - 1 test (panic ID 10561) covering `BuildHasherDefault` equivalence with direct `HASH_*` helpers and `RandomState` equivalence with manual `RANDOM_STATE_BUILD + DEFAULT_HASHER_WRITE_*`.
- Validation status:
  - Focused only: `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_hash_builder_integer_hash_one_macro_surface.sa --jobs 1 --trace-panic` -> `1 passed; 0 failed; 0 skipped`.
  - Full tests intentionally not run because prior full runs caused memory pressure; this batch only runs the newly added focused test.
- Panic IDs next free: 10562+.

## Completed: 2026-07-15 Hash integer primitive macros

- Continued Rust `std::hash` macro-surface parity, referencing Rust's local primitive `impl_write!` `Hash` implementations under `/home/vscode/projects/rust`.
- `sa_std/hash.sa`: added `HASH_U8`, `HASH_U16`, `HASH_U32`, `HASH_I8`, `HASH_I16`, `HASH_I32`, `HASH_I64`, and `HASH_ISIZE`.
- The helper surface uses the existing concrete `DEFAULT_HASHER_WRITE_*` paths. Signed helpers preserve the current SA forwarding shape to their same-width unsigned/register-sized writers; this does not claim generic `Hash` trait dispatch, endian-exact byte serialization, `u128` / `i128`, or SipHash output compatibility.
- Test: `tests/unit_framework/std_hash_integer_primitives_macro_surface.sa` - 1 test (panic ID 10560) covering equivalence with each existing writer, signed/unsigned forwarding consistency on this SA target, distinct values, and direct one-shot hashing.
- Validation status:
  - Focused only: `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_hash_integer_primitives_macro_surface.sa --jobs 1 --trace-panic` -> `1 passed; 0 failed; 0 skipped`.
  - Full tests intentionally not run because prior full runs caused memory pressure; this batch only runs the newly added focused test.
- Panic IDs next free: 10561+.

## Completed: 2026-07-15 Hash usize macro

- Continued Rust `std::hash` macro-surface parity, referencing Rust's local primitive `Hash` implementations under `/home/vscode/projects/rust`.
- `sa_std/hash.sa`: added `HASH_USIZE`.
- The helper surface uses the existing concrete `DEFAULT_HASHER_WRITE_USIZE` path, which maps to the current deterministic register-sized `u64` hasher write. It does not claim generic `Hash` trait dispatch, endian-exact byte serialization, or SipHash output compatibility.
- Test: `tests/unit_framework/std_hash_usize_macro_surface.sa` - 1 test (panic ID 10559) covering equivalence with `WRITE_USIZE`, consistency with the current `u64` helper on this SA target, distinct values, and direct one-shot hashing.
- Validation status:
  - Focused only: `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_hash_usize_macro_surface.sa --jobs 1 --trace-panic` -> `1 passed; 0 failed; 0 skipped`.
  - Full tests intentionally not run because prior full runs caused memory pressure; this batch only runs the newly added focused test.
- Panic IDs next free: 10560+.

## Completed: 2026-07-14 Hash bool macro

- Continued Rust `std::hash` macro-surface parity, referencing Rust's local `impl Hash for bool` under `/home/vscode/projects/rust`.
- `sa_std/hash.sa`: added `HASH_BOOL`.
- The helper surface uses the existing concrete `DEFAULT_HASHER_WRITE_BOOL` path, normalizing nonzero values to true for frontend-lowered booleans. It does not claim generic `Hash` trait dispatch or SipHash output compatibility.
- Test: `tests/unit_framework/std_hash_bool_macro_surface.sa` - 1 test (panic ID 10558) covering equivalence with `WRITE_BOOL`, true/false distinction, nonzero normalization, and direct one-shot hashing.
- Validation status:
  - Focused only: `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_hash_bool_macro_surface.sa --jobs 1 --trace-panic` -> `1 passed; 0 failed; 0 skipped`.
  - Full tests intentionally not run because prior full runs caused memory pressure; this batch only runs the newly added focused test.
- Panic IDs next free: 10559+.

## Completed: 2026-07-14 Hash char macro

- Continued Rust `std::hash` macro-surface parity, referencing Rust's local `impl Hash for char` under `/home/vscode/projects/rust`.
- `sa_std/hash.sa`: added `DEFAULT_HASHER_WRITE_CHAR` and `HASH_CHAR`.
- The helper surface models Rust's concrete `char` hash shape by forwarding the scalar value through `DEFAULT_HASHER_WRITE_U32`. It assumes the frontend has already produced a valid Rust `char` scalar and does not claim generic `Hash` trait dispatch or SipHash output compatibility.
- Test: `tests/unit_framework/std_hash_char_macro_surface.sa` - 1 test (panic ID 10557) covering equivalence with `WRITE_U32`, direct `HASH_CHAR`, non-ASCII scalar hashing, and distinct scalar values.
- Validation status:
  - Focused only: `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_hash_char_macro_surface.sa --jobs 1 --trace-panic` -> `1 passed; 0 failed; 0 skipped`.
  - Full tests intentionally not run because prior full runs caused memory pressure; this batch only runs the newly added focused test.
- Panic IDs next free: 10558+.

## Completed: 2026-07-14 Hash Hasher write macro

- Continued Rust `std::hash` macro-surface parity, referencing Rust's local `Hasher::write(&[u8])` definition under `/home/vscode/projects/rust`.
- `sa_std/hash.sa`: added `DEFAULT_HASHER_WRITE` as the Rust-named concrete byte-slice write entry for SA's `DefaultHasher`.
- The helper delegates to the existing `DEFAULT_HASHER_WRITE_BYTES` state update path and intentionally does not add a length prefix, matching Rust's `Hasher::write` contract where sequence prefixing is the caller's responsibility.
- Test: `tests/unit_framework/std_hash_default_hasher_write_macro_surface.sa` - 1 test (panic ID 10556) covering alias equivalence with `WRITE_BYTES`, distinction from `WRITE_STR` domain separation, empty write no-op behavior, and nonempty state change.
- Validation status:
  - Focused only: `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_hash_default_hasher_write_macro_surface.sa --jobs 1 --trace-panic` -> `1 passed; 0 failed; 0 skipped`.
  - Full tests intentionally not run because prior full runs caused memory pressure; this batch only runs the newly added focused test.
- Panic IDs next free: 10557+.

## Completed: 2026-07-14 Hash DefaultHasher clone macro

- Continued Rust `std::hash` macro-surface parity, referencing Rust's local `DefaultHasher` definition under `/home/vscode/projects/rust`, where it derives `Clone`.
- `sa_std/hash.sa`: added `DEFAULT_HASHER_CLONE`.
- The helper copies SA's deterministic single-word `DefaultHasher` state into a separate hasher object. Clones then advance independently while preserving Rust's clone-from-current-state shape for this concrete subset.
- Test: `tests/unit_framework/std_hash_default_hasher_clone_macro_surface.sa` - 1 test (panic ID 10555) covering clone equality at the clone point, independent later writes, same-result continuation after same write, and default hasher clone.
- Validation status:
  - Focused only: `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_hash_default_hasher_clone_macro_surface.sa --jobs 1 --trace-panic` -> `1 passed; 0 failed; 0 skipped`.
  - Full tests intentionally not run because prior full runs caused memory pressure; this batch only runs the newly added focused test.
- Panic IDs next free: 10556+.

## Completed: 2026-07-14 Hash RandomState macros

- Continued Rust `std::hash` macro-surface parity, referencing Rust's local `std::hash::RandomState` and `BuildHasher::hash_one` implementation under `/home/vscode/projects/rust`.
- `sa_std/hash.sal`: added the concrete `RandomState` layout and deterministic default seed constants.
- `sa_std/hash.sa`: added `RANDOM_STATE_NEW`, `RANDOM_STATE_DEFAULT`, `RANDOM_STATE_WITH_SEEDS`, `RANDOM_STATE_CLONE`, `RANDOM_STATE_BUILD`, and concrete `RANDOM_STATE_HASH_ONE_U64` / `RANDOM_STATE_HASH_ONE_STR` / `RANDOM_STATE_HASH_ONE_SLICE_U8` / `RANDOM_STATE_HASH_ONE_SLICE_U64`.
- The helper surface models cloned state consistency, explicit seed-pair variation, and `BuildHasher::hash_one` over the existing deterministic `DefaultHasher`. It does not claim Rust's OS-random keys, per-thread key evolution, SipHash compatibility, generic `Hash`, or collection trait integration.
- Test: `tests/unit_framework/std_hash_random_state_macro_surface.sa` - 1 test (panic ID 10554) covering new/default/clone behavior, seeded-state difference, `build_hasher`, and concrete `hash_one` for `u64`, `str`, `Slice<u8>`, and `Slice<u64>`.
- Validation status:
  - Focused only: `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_hash_random_state_macro_surface.sa --jobs 1 --trace-panic` -> `1 passed; 0 failed; 0 skipped`.
  - Full tests intentionally not run because prior full runs caused memory pressure; this batch only runs the newly added focused test.
- Panic IDs next free: 10555+.

## Completed: 2026-07-14 Iterator try_collect macro

- Continued Rust `std::iter` macro-surface parity over the existing concrete slice-backed `Iter<u64>` cursor, referencing Rust's local `Iterator::try_collect` implementation under `/home/vscode/projects/rust`.
- `sa_std/core/iter.sa`: added `ITER_TRY_COLLECT_U64`.
- The helper models a concrete unstable `Iterator::try_collect::<Vec<_>>()` lowering for the supported `u64` cursor subset. It calls a `(value, out_value_ptr) -> ok` callback for each item, pushes mapped successes into a `Vec<u64>`, returns `ok=0` after consuming the first failing item, and leaves later suffix items available.
- Test: `tests/unit_framework/std_iter_try_collect_macro_surface.sa` - 1 test (panic ID 10553) covering success collection, failure short-circuit with suffix preservation, first-item failure, and empty input success.
- Validation status:
  - Focused only: `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_iter_try_collect_macro_surface.sa --jobs 1 --trace-panic` -> `1 passed; 0 failed; 0 skipped`.
  - Full tests intentionally not run because prior full runs caused memory pressure; this batch only runs the newly added focused test.
- Panic IDs next free: 10554+.

## Completed: 2026-07-14 Iterator partition_in_place macro

- Continued Rust `std::iter` macro-surface parity over the existing concrete slice-backed `Iter<u64>` cursor, referencing Rust's local `Iterator::partition_in_place` implementation under `/home/vscode/projects/rust`.
- `sa_std/core/iter.sa`: added `ITER_PARTITION_IN_PLACE_U64`.
- The helper models a concrete unstable `Iterator::partition_in_place` lowering for the supported mutable `u64` cursor subset. It partitions only the cursor's current remaining storage in place, returns the count of predicate-true items, does not preserve relative order, and marks the cursor consumed.
- Test: `tests/unit_framework/std_iter_partition_in_place_macro_surface.sa` - 1 test (panic ID 10552) covering in-place even/odd partitioning, partially consumed input preserving the already-consumed prefix, all-true input, all-false input, and empty input.
- Validation status:
  - Focused only: `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_iter_partition_in_place_macro_surface.sa --jobs 1 --trace-panic` -> `1 passed; 0 failed; 0 skipped`.
  - Full tests intentionally not run because prior full runs caused memory pressure; this batch only runs the newly added focused test.
- Panic IDs next free: 10553+.

## Completed: 2026-07-14 Iterator map_windows collect macro

- Continued Rust `std::iter` macro-surface parity over the existing concrete slice-backed `Iter<u64>` cursor, referencing Rust's local `core::iter::MapWindows` implementation under `/home/vscode/projects/rust`.
- `sa_std/core/iter.sa`: added `ITER_MAP_WINDOWS_COLLECT_U64`.
- The helper models a concrete unstable `Iterator::map_windows(...).collect::<Vec<_>>()` lowering for the supported `u64` cursor subset. It calls a concrete `(window_ptr, window_len) -> u64` mapper for each overlapping window, materializes mapped values into `Vec<u64>`, consumes the source cursor for nonzero window sizes, and reports `ok=0` without consuming for `window_size == 0`.
- Test: `tests/unit_framework/std_iter_map_windows_macro_surface.sa` - 1 test (panic ID 10551) covering overlapping windows, partially consumed input, short input consuming to empty, zero window no-consume behavior, and empty input.
- Validation status:
  - Focused only: `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_iter_map_windows_macro_surface.sa --jobs 1 --trace-panic` -> `1 passed; 0 failed; 0 skipped`.
  - Full tests intentionally not run because prior full runs caused memory pressure; this batch only runs the newly added focused test.
- Panic IDs next free: 10552+.

## Completed: 2026-07-14 Iterator array_chunks collect macro

- Continued Rust `std::iter` macro-surface parity over the existing concrete slice-backed `Iter<u64>` cursor, referencing Rust's local `core::iter::ArrayChunks` implementation under `/home/vscode/projects/rust`.
- `sa_std/core/iter.sa`: added `ITER_ARRAY_CHUNKS_COLLECT_U64`.
- The helper models a concrete `Iterator::array_chunks::<N>().collect::<Vec<_>>()` lowering for the supported `u64` cursor subset by materializing complete non-overlapping chunks into a flat `Vec<u64>`. It reports `ok=0` and leaves the cursor untouched for `chunk_size == 0`; for nonzero chunk sizes it consumes only complete chunks and leaves an incomplete tail available in the cursor.
- Test: `tests/unit_framework/std_iter_array_chunks_macro_surface.sa` - 1 test (panic ID 10550) covering short-tail retention, partially consumed input, exact division, chunk size larger than the remaining cursor, and zero chunk size.
- Validation status:
  - Focused only: `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_iter_array_chunks_macro_surface.sa --jobs 1 --trace-panic` -> `1 passed; 0 failed; 0 skipped`.
  - Full tests intentionally not run because prior full runs caused memory pressure; this batch only runs the newly added focused test.
- Panic IDs next free: 10551+.

## Completed: 2026-07-14 Iterator peekable macros

- Continued Rust `std::iter` macro-surface parity over the existing concrete slice-backed `Iter<u64>` cursor.
- `sa_std/core/iter.sa`: added `ITER_TRY_PEEK_U64` and `ITER_PEEKABLE_COLLECT_U64`.
- `ITER_TRY_PEEK_U64` models a concrete `Peekable::peek`-style surface by returning `(has, value)` without consuming the cursor, including a none-style result for empty/exhausted cursors. `ITER_PEEKABLE_COLLECT_U64` models a concrete `peekable().collect::<Vec<_>>()` lowering by collecting the current finite cursor remainder.
- Test: `tests/unit_framework/std_iter_peekable_macro_surface.sa` - 1 test (panic ID 10549) covering non-consuming peek, peek after advancing, peekable collect, post-collect empty peek, and empty input.
- Validation status:
  - Focused only: `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_iter_peekable_macro_surface.sa --jobs 1 --trace-panic` -> `1 passed; 0 failed; 0 skipped`.
  - Full tests intentionally not run because prior full runs caused memory pressure; this batch only runs the newly added focused test.
- Panic IDs next free: 10550+.

## Completed: 2026-07-14 Iterator fuse collect macro

- Continued Rust `std::iter` macro-surface parity over the existing concrete slice-backed `Iter<u64>` cursor.
- `sa_std/core/iter.sa`: added `ITER_FUSE_COLLECT_U64`.
- The helper models a concrete `Iterator::fuse().collect::<Vec<_>>()` lowering for the supported finite `u64` cursor subset. The current cursor is already fused after exhaustion, so the helper delegates to `ITER_COLLECT_U64` and keeps post-exhaustion `next()` calls returning none-style `(has=0, value=0)`.
- Test: `tests/unit_framework/std_iter_fuse_collect_macro_surface.sa` - 1 test (panic ID 10548) covering partial-consume then fuse-collect, repeated post-exhaustion `next()`, and empty input.
- Validation status:
  - Focused only: `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_iter_fuse_collect_macro_surface.sa --jobs 1 --trace-panic` -> `1 passed; 0 failed; 0 skipped`.
  - Full tests intentionally not run because prior full runs caused memory pressure; this batch only runs the newly added focused test.
- Panic IDs next free: 10549+.

## Completed: 2026-07-14 Iterator by_ref collect macro

- Continued Rust `std::iter` macro-surface parity over the existing concrete slice-backed `Iter<u64>` cursor.
- `sa_std/core/iter.sa`: added `ITER_BY_REF_COLLECT_U64`.
- The helper models a concrete `Iterator::by_ref().collect::<Vec<_>>()` lowering for the supported `u64` cursor subset: it takes the existing `ITER_BY_REF` alias to the original cursor and collects through that alias, so the original cursor is consumed while separately cloned cursors remain independent.
- Test: `tests/unit_framework/std_iter_by_ref_collect_macro_surface.sa` - 1 test (panic ID 10547) covering partially consumed by-ref collection, original cursor consumption, clone independence, and empty input.
- Validation status:
  - Focused only: `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_iter_by_ref_collect_macro_surface.sa --jobs 1 --trace-panic` -> `1 passed; 0 failed; 0 skipped`.
  - Full tests intentionally not run because prior full runs caused memory pressure; this batch only runs the newly added focused test.
- Panic IDs next free: 10548+.

## Completed: 2026-07-14 Iterator try_find macro

- Continued Rust `std::iter` macro-surface parity over the existing concrete slice-backed `Iter<u64>` cursor.
- `sa_std/core/iter.sa`: added `ITER_TRY_FIND_U64`.
- The helper models a concrete unstable `Iterator::try_find` lowering for the supported `u64` cursor subset: it calls a `(value, out_match_ptr) -> ok` callback, returns `(ok, has, value)`, reports successful misses as `ok=1, has=0`, consumes the first found or failing item, and leaves later suffix elements available.
- Test: `tests/unit_framework/std_iter_try_find_macro_surface.sa` - 1 test (panic ID 10546) covering successful find with suffix preservation, callback failure with suffix preservation, successful miss, and empty input.
- Validation status:
  - Focused only: `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_iter_try_find_macro_surface.sa --jobs 1 --trace-panic` -> `1 passed; 0 failed; 0 skipped`.
  - Full tests intentionally not run because prior full runs caused memory pressure; this batch only runs the newly added focused test.
- Panic IDs next free: 10547+.

## Completed: 2026-07-14 Iterator comparator-by macros

- Continued Rust `std::iter` macro-surface parity over the existing concrete slice-backed `Iter<u64>` cursor.
- `sa_std/core/iter.sa`: added `ITER_CMP_BY_U64`, `ITER_PARTIAL_CMP_BY_U64`, and `ITER_EQ_BY_U64`.
- The helpers model concrete unstable `Iterator::{cmp_by,partial_cmp_by,eq_by}` lowering shapes for the supported `u64` cursor subset. `cmp_by` uses `(left, right) -> Ordering`, `partial_cmp_by` uses `(left, right, out_order_ptr) -> ok`, and `eq_by` uses `(left, right) -> bool`, with lexicographic short-circuit consumption matching the existing cursor comparison model.
- Test: `tests/unit_framework/std_iter_compare_by_macro_surface.sa` — 1 test (panic ID 10545) covering callback equality, non-equal short-circuiting, length mismatch, `partial_cmp_by` Some ordering, and `partial_cmp_by` None short-circuit suffix preservation.
- Validation status:
  - Focused only: `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_iter_compare_by_macro_surface.sa --jobs 1 --trace-panic` -> `1 passed; 0 failed; 0 skipped`.
  - Full tests intentionally not run because prior full runs caused memory pressure; this batch only runs the newly added focused test.
- Panic IDs next free: 10546+.

## Completed: 2026-07-14 Iterator try_reduce macro

- Continued Rust `std::iter` macro-surface parity over the existing concrete slice-backed `Iter<u64>` cursor.
- `sa_std/core/iter.sa`: added `ITER_TRY_REDUCE_U64`.
- The helper models a concrete unstable `Iterator::try_reduce` lowering for the supported `u64` cursor subset: it uses the first remaining item as the accumulator, calls a `(acc, value, out_next_ptr) -> ok` callback for later items, returns `(ok, has, value)` so empty-input success is distinguishable, consumes the first failing item, and leaves later suffix items available.
- Test: `tests/unit_framework/std_iter_try_reduce_macro_surface.sa` — 1 test (panic ID 10544) covering short-circuit failure with suffix preservation, all-success reduction, partially consumed source windows, and empty-input success.
- Validation status:
  - Focused only: `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_iter_try_reduce_macro_surface.sa --jobs 1 --trace-panic` -> `1 passed; 0 failed; 0 skipped`.
  - Full tests intentionally not run because prior full runs caused memory pressure; this batch only runs the newly added focused test.
- Panic IDs next free: 10545+.

## Completed: 2026-07-14 Iterator intersperse collect macros

- Continued Rust `std::iter` macro-surface parity over the existing concrete slice-backed `Iter<u64>` cursor and `Vec<u64>` facade.
- `sa_std/core/iter.sa`: added `ITER_INTERSPERSE_COLLECT_U64` and `ITER_INTERSPERSE_WITH_COLLECT_U64`.
- The helpers model concrete eager `intersperse(...).collect::<Vec<_>>()` and `intersperse_with(...).collect::<Vec<_>>()` lowerings for the supported `u64` cursor subset by materializing item/separator/item ordering into a `Vec<u64>`.
- Test: `tests/unit_framework/std_iter_intersperse_macro_surface.sa` — 1 test (panic ID 10543) covering fixed separators, generated separators, partially consumed source windows, single-item input, and empty input.
- Validation status:
  - Focused only: `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_iter_intersperse_macro_surface.sa --jobs 1 --trace-panic` -> `1 passed; 0 failed; 0 skipped`.
  - Full tests intentionally not run because prior full runs caused memory pressure; this batch only runs the newly added focused test.
- Panic IDs next free: 10544+.

## Completed: 2026-07-14 Iterator cycle take collect macro

- Continued Rust `std::iter` macro-surface parity over the existing concrete slice-backed `Iter<u64>` cursor and `Vec<u64>` facade.
- `sa_std/core/iter.sa`: added `ITER_CYCLE_TAKE_COLLECT_U64`.
- The helper models a concrete eager `cycle().take(n).collect::<Vec<_>>()` lowering for the supported `u64` cursor subset by cycling over the cursor's current remaining window and materializing a bounded Vec.
- Test: `tests/unit_framework/std_iter_cycle_take_macro_surface.sa` — 1 test (panic ID 10542) covering repeated cycling, partially consumed source windows, empty input, and count-zero no-consume behavior.
- Validation status:
  - Focused only: `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_iter_cycle_take_macro_surface.sa --jobs 1 --trace-panic` -> `1 passed; 0 failed; 0 skipped`.
  - Full tests intentionally not run because prior full runs caused memory pressure; this batch only runs the newly added focused test.
- Panic IDs next free: 10543+.

## Completed: 2026-07-14 Iterator copied/cloned collect aliases

- Continued Rust `std::iter` macro-surface parity over the existing concrete slice-backed `Iter<u64>` cursor and `Vec<u64>` facade.
- `sa_std/core/iter.sa`: added `ITER_COPIED_COLLECT_U64` and `ITER_CLONED_COLLECT_U64`.
- The helpers model concrete eager `copied().collect::<Vec<_>>()` and `cloned().collect::<Vec<_>>()` lowerings for the supported `u64` value-copy cursor subset by delegating to `ITER_COLLECT_U64`.
- Test: `tests/unit_framework/std_iter_copied_cloned_macro_surface.sa` — 1 test (panic ID 10541) covering copied value collection, cloned collection from a partially consumed cursor, cursor consumption, and empty input.
- Validation status:
  - Focused only: `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_iter_copied_cloned_macro_surface.sa --jobs 1 --trace-panic` -> `1 passed; 0 failed; 0 skipped`.
  - Full tests intentionally not run because prior full runs caused memory pressure; this batch only runs the newly added focused test.
- Panic IDs next free: 10542+.

## Completed: 2026-07-14 Iterator scan collect macro

- Continued Rust `std::iter` macro-surface parity over the existing concrete slice-backed `Iter<u64>` cursor and `Vec<u64>` facade.
- `sa_std/core/iter.sa`: added `ITER_SCAN_COLLECT_U64`.
- The helper models a concrete eager `scan(...).collect::<Vec<_>>()` lowering: it keeps a `u64` state slot, calls a `(state_ptr, value, out_mapped_ptr) -> ok` callback, pushes yielded values while nonzero, consumes the first zero/None-style stopping item without collecting it, and leaves later suffix items in the cursor.
- Test: `tests/unit_framework/std_iter_scan_macro_surface.sa` — 1 test (panic ID 10540) covering state updates, yielded values, stopping-item consumption with suffix preservation, and empty input.
- Validation status:
  - Focused only: `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_iter_scan_macro_surface.sa --jobs 1 --trace-panic` -> `1 passed; 0 failed; 0 skipped`.
  - Full tests intentionally not run because prior full runs caused memory pressure; this batch only ran the newly added focused test.
- Panic IDs next free: 10541+.

## Completed: 2026-07-14 Iterator inspect collect macro

- Continued Rust `std::iter` macro-surface parity over the existing concrete slice-backed `Iter<u64>` cursor and `Vec<u64>` facade.
- `sa_std/core/iter.sa`: added `ITER_INSPECT_COLLECT_U64`.
- The helper models a concrete eager `inspect(...).collect::<Vec<_>>()` lowering: it calls a `value -> u64` inspection callback for each consumed item, ignores the callback return, pushes the original item unchanged, and consumes the cursor.
- Test: `tests/unit_framework/std_iter_inspect_macro_surface.sa` — 1 test (panic ID 10539) covering ignored callback return values, preserved output values, cursor consumption, and empty input.
- Validation status:
  - Focused only: `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_iter_inspect_macro_surface.sa --jobs 1 --trace-panic` -> `1 passed; 0 failed; 0 skipped`.
  - Full tests intentionally not run because prior full runs caused memory pressure; this batch only ran the newly added focused test.
- Panic IDs next free: 10540+.

## Completed: 2026-07-14 Iterator step_by collect macros

- Continued Rust `std::iter` macro-surface parity over the existing concrete slice-backed `Iter<u64>` cursor and `Vec<u64>` facade.
- `sa_std/core/iter.sa`: added `ITER_TRY_STEP_BY_COLLECT_U64` and `ITER_STEP_BY_COLLECT_U64`.
- The helpers model a concrete eager `step_by(n).collect::<Vec<_>>()` lowering by collecting the first cursor item, skipping `step - 1` elements between collected values, and consuming skipped elements. The try form reports `ok=0` and leaves the cursor untouched for `step == 0`; the non-try wrapper is for callers that have already met Rust's nonzero-step precondition.
- Test: `tests/unit_framework/std_iter_step_by_macro_surface.sa` — 1 test (panic ID 10538) covering step=2, tail-start step=3, step=1, cursor consumption, and invalid step no-consume behavior.
- Validation status:
  - Focused only: `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_iter_step_by_macro_surface.sa --jobs 1 --trace-panic` -> `1 passed; 0 failed; 0 skipped`.
  - Full tests intentionally not run because prior full runs caused memory pressure; this batch only ran the newly added focused test.
- Panic IDs next free: 10539+.

## Completed: 2026-07-14 Iterator map_while collect macro

- Continued Rust `std::iter` macro-surface parity over the existing concrete slice-backed `Iter<u64>` cursor and `Vec<u64>` facade.
- `sa_std/core/iter.sa`: added `ITER_MAP_WHILE_COLLECT_U64`.
- The helper models a concrete eager `map_while(...).collect::<Vec<_>>()` lowering: a `(value, out_mapped_ptr) -> ok` callback returns Some-style mapped values while nonzero, the first zero/None-style item is consumed but not collected, and later suffix items remain in the cursor.
- Test: `tests/unit_framework/std_iter_map_while_macro_surface.sa` — 1 test (panic ID 10537) covering mapped prefix collection, stopping-item consumption with suffix preservation, all-success consumption, and empty input.
- Validation status:
  - Focused only: `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_iter_map_while_macro_surface.sa --jobs 1 --trace-panic` -> `1 passed; 0 failed; 0 skipped`.
  - Full tests intentionally not run because prior full runs caused memory pressure; this batch only ran the newly added focused test.
- Panic IDs next free: 10538+.

## Completed: 2026-07-14 Iterator collect_into macro

- Continued Rust `std::iter` macro-surface parity over the existing concrete slice-backed `Iter<u64>` cursor and `Vec<u64>` facade.
- `sa_std/core/iter.sa`: added `ITER_COLLECT_INTO_U64`.
- The helper follows Rust's unstable `Iterator::collect_into` default shape (`collection.extend(self); collection`) for the concrete supported subset by appending remaining cursor items into an existing `Vec<u64>` and consuming the cursor.
- Test: `tests/unit_framework/std_iter_collect_into_macro_surface.sa` — 1 test (panic ID 10536) covering append-after-existing-elements, cursor consumption, and empty cursor no-op behavior.
- Validation status:
  - Focused only: `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_iter_collect_into_macro_surface.sa --jobs 1 --trace-panic` -> `1 passed; 0 failed; 0 skipped`.
  - Full tests intentionally not run because prior full runs caused memory pressure; this batch only ran the newly added focused test.
- Panic IDs next free: 10537+.

## Completed: 2026-07-14 Iterator is_partitioned macro

- Continued Rust `std::iter` macro-surface parity over the existing concrete slice-backed `Iter<u64>` cursor.
- `sa_std/core/iter.sa`: added `ITER_IS_PARTITIONED_U64`.
- The helper follows Rust's default `all(predicate) || !any(predicate)` shape, so it returns true for all-true and empty iterators, returns false after finding a later true item after the first false, and preserves any unchecked suffix left by that short-circuit.
- Test: `tests/unit_framework/std_iter_is_partitioned_macro_surface.sa` — 1 test (panic ID 10535) covering partitioned, non-partitioned, all-true, empty, and short-circuit cursor remainder behavior.
- Validation status:
  - Focused only: `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_iter_is_partitioned_macro_surface.sa --jobs 1 --trace-panic` -> `1 passed; 0 failed; 0 skipped`.
  - Full tests intentionally not run because prior full runs caused memory pressure; this batch only ran the newly added focused test.
- Panic IDs next free: 10536+.

## Completed: 2026-07-14 Iterator reverse-fold macros

- Continued Rust `std::iter` / `DoubleEndedIterator` macro-surface parity over the existing concrete slice-backed `Iter<u64>` cursor.
- `sa_std/core/iter.sa`: added `ITER_RFOLD_U64` and `ITER_TRY_RFOLD_U64`.
- `ITER_RFOLD_U64` consumes from the back with the existing `(acc, value) -> acc` callback shape. `ITER_TRY_RFOLD_U64` mirrors `ITER_TRY_FOLD_U64` but uses `ITER_NEXT_BACK_U64`, returning `(ok, acc)` and preserving not-yet-consumed front elements on early stop.
- Test: `tests/unit_framework/std_iter_rfold_macro_surface.sa` — 1 test (panic ID 10534) covering reverse fold order, successful and short-circuiting try reverse fold, remaining-front cursor state after early stop, and empty iterator identity values.
- Validation status:
  - Focused only: `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_iter_rfold_macro_surface.sa --jobs 1 --trace-panic` -> `1 passed; 0 failed; 0 skipped`.
  - Full tests intentionally not run because prior full runs caused memory pressure; this batch only ran the newly added focused test.
- Panic IDs next free: 10535+.

## Completed: 2026-07-14 Iterator sortedness macros

- Continued Rust `std::iter` macro-surface parity over the existing concrete slice-backed `Iter<u64>` cursor.
- `sa_std/core/iter.sa`: added `ITER_IS_SORTED_U64`, `ITER_IS_SORTED_BY_U64`, and `ITER_IS_SORTED_BY_KEY_U64`.
- These helpers check the cursor's remaining elements via existing concrete slice sortedness helpers and then consume the cursor by marking it empty.
- Test: `tests/unit_framework/std_iter_sorted_macro_surface.sa` — 1 test (panic ID 10533) covering sorted, unsorted, duplicate strict-comparator failure, key-sorted/key-unsorted paths, empty input, tail-only checking after one `next`, and cursor consumption after each check.
- Validation status:
  - Focused only: `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_iter_sorted_macro_surface.sa --jobs 1 --trace-panic` -> `1 passed; 0 failed; 0 skipped`.
  - Full tests intentionally not run because prior full runs caused memory pressure; this batch only ran the newly added focused test.
- Panic IDs next free: 10534+.

## Completed: 2026-07-14 Iterator Rust naming aliases

- Continued Rust `std::iter` macro-surface parity over the existing concrete slice-backed `Iter<u64>` cursor.
- `sa_std/core/iter.sa`: added `ITER_BY_REF`, `ITER_EXACT_SIZE_LEN`, `ITER_EXACT_SIZE_IS_EMPTY`, `ITER_PARTIAL_EQ_U64`, and `ITER_PARTIAL_CMP_U64`.
- Test: `tests/unit_framework/std_iter_alias_macro_surface.sa` — 1 test (panic ID 10532) covering borrowed cursor alias consumption, exact-size aliases, and total-order partial equality/comparison aliases.
- Validation status:
  - Focused only: `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_iter_alias_macro_surface.sa --jobs 1 --trace-panic` -> `1 passed; 0 failed; 0 skipped`.
  - Full tests intentionally not run because prior full runs caused memory pressure; this batch only ran the newly added focused test.
- Panic IDs next free: 10533+.

## Completed: 2026-07-13 IO_ERROR_KIND + ERROR_CODE + ERROR_REF_IS_* expanded

- `sa_std/io.sal`: 33 new `IO_ERROR_KIND_*` constants covering the full Rust `io::ErrorKind` enum (NotFound, PermissionDenied, ConnectionRefused, ConnectionReset, ConnectionAborted, NotConnected, AddrInUse, AddrNotAvailable, BrokenPipe, AlreadyExists, TimedOut, Unsupported, OutOfMemory, IsADirectory, DirectoryNotEmpty, RecursiveEntry, QuotaExceeded, FileTooLarge, FilesystemLoop, ExecutableFileBusy, CrossedDevices, NotSeekable, ReadOnlyFilesystem, ArgumentListTooLong, ResourceBusy, NameTooLong, TooManyLinks, HostUnreachable, NetworkUnreachable, NetworkDown, StaleNetworkFileHandle, FilesystemQuota, StorageFull, plus existing kinds).
- `sa_std/error.sal`: 19 new `ERROR_CODE_*` constants (ConnectionRefused through StorageFull, IDs 10-28).
- `sa_std/error.sa`: 19 new `ERROR_REF_IS_*` convenience helper macros covering the new error codes (ConnectionRefused, ConnectionReset, ConnectionAborted, NotConnected, AddrInUse, AddrNotAvailable, BrokenPipe, AlreadyExists, OutOfMemory, NetworkUnreachable, HostUnreachable, IsADirectory, DirectoryNotEmpty, ReadOnlyFilesystem, ResourceBusy, ArgumentListTooLong, NameTooLong, TooManyLinks, StorageFull).
- Test: `tests/unit_framework/std_io_error_kinds_macro_surface.sa` — 2 tests (panic IDs 10467/10468) covering all new IO_ERROR_KIND constants and ERROR_CODE constants + ERROR_REF_IS_* macros.
- Validation status:
  - Focused: `SA_STD_DIR=/home/vscode/.sa/std ./zig-out/bin/sa test tests/unit_framework/std_io_error_kinds_macro_surface.sa --jobs 1 --trace-panic` -> `2 passed; 0 failed; 0 skipped`.
  - Full `zig build unit-framework --summary all`: pass (`6/6 steps succeeded; 5/5 tests passed`).
- Panic IDs next free: 10469+.

## Completed: 2026-07-13 Default aliases for legacy Cell and legacy RefCell

- `sa_std/core/cell.sa`: `CELL_DEFAULT` — alias for `CELL_NEW` (zero-initialized 4-byte Cell, matching Rust `Cell::<i32>::default`).
- `sa_std/core/refcell.sa`: `REFCELL_DEFAULT` — zero-initialized legacy RefCell with value=0, borrows=0 (matching Rust `RefCell::default` where `T: Default`).
- Validation status:
  - Focused temp tests for CELL_DEFAULT and REFCELL_DEFAULT passed individually.
  - Full `zig build unit-framework --summary all`: pass (`6/6 steps succeeded; 5/5 tests passed`).

## Completed: 2026-07-13 DEFAULT_F32/F64/CHAR macros + RANGE_INCLUSIVE_U64_DEFAULT

- `sa_std/default.sa`: `DEFAULT_F32`, `DEFAULT_F64`, `DEFAULT_CHAR` macros (return 0, matching Rust `Default::default()` for `f32`, `f64`, `char`).
- `sa_std/ops.sa`: `RANGE_INCLUSIVE_U64_DEFAULT` macro (0..=0, exhausted=0).
- Extended `tests/unit_framework/std_from_into_default_macro_surface.sa` numeric defaults block to also test `DEFAULT_F32`, `DEFAULT_F64`, `DEFAULT_CHAR` macros.
- Validation status:
  - Focused: `SA_STD_DIR=/home/vscode/.sa/std ./zig-out/bin/sa test tests/unit_framework/std_from_into_default_macro_surface.sa --jobs 1 --trace-panic` -> `2 passed; 0 failed; 0 skipped`.

## Completed: 2026-07-13 RANGE_INCLUSIVE_U64_DEFAULT

- `sa_std/ops.sa`: `RANGE_INCLUSIVE_U64_DEFAULT` macro (0..=0, exhausted=0), matching Rust `RangeInclusive<u64>::default()`.
- Extended `tests/unit_framework/std_default_types_macro_surface.sa` to verify start=0, end=0, exhausted=0.
- Validation status:
  - Focused: `SA_STD_DIR=/home/vscode/.sa/std ./zig-out/bin/sa test tests/unit_framework/std_default_types_macro_surface.sa --jobs 1 --trace-panic` -> `1 passed; 0 failed; 0 skipped`.

## Completed: 2026-07-13 INTO/TRY_INTO/SAT_INTO naming aliases + PTR_SWAP_NONOVERLAPPING_U64

- Continued Rust std `Into` / `TryInto` / `SaturatingInto` naming parity with thin aliases over existing `FROM_*` / `TRY_FROM_*` / `SAT_FROM_*` macros (no new runtime/FFI). In Rust, `impl From<T> for U` implies `impl Into<U> for T`, and similarly for `TryInto`.
- `sa_std/convert.sa`: 56 new `INTO_*` / `TRY_INTO_*` / `SAT_INTO_*` Rust-named aliases wrapping existing `FROM_*` / `TRY_FROM_*` / `SAT_FROM_*` macros (168 total macros in convert.sa).
- `sa_std/ptr.sa`: `PTR_SWAP_NONOVERLAPPING_U64` — non-overlapping concrete `u64` pointer swap alias over `PTR_SWAP_U64` (matches Rust `ptr::swap_nonoverlapping` for typed `u64`).
- Tests: `tests/unit_framework/std_into_naming_macro_surface.sa` — 2 tests covering `INTO_*` / `TRY_INTO_*` / `SAT_INTO_*` aliases (panic ID 10465) and `PTR_SWAP_NONOVERLAPPING_U64` (panic ID 10466).
- Validation status:
  - Focused: `SA_STD_DIR=/home/vscode/.sa/std ./zig-out/bin/sa test tests/unit_framework/std_into_naming_macro_surface.sa --jobs 1 --trace-panic` -> `2 passed; 0 failed; 0 skipped`.
  - Full `zig build unit-framework --summary all`: pass (`6/6 steps succeeded; 5/5 tests passed`).
- Panic IDs next free: 10467+.

## Completed: 2026-07-13 BOOL/F32/F64/CHAR Default constants + RESULT_DEFAULT macro

- Continued Rust std `Default` parity with constant and macro additions over existing layouts (no new runtime/FFI).
- `sa_std/num.sal`: `BOOL_DEFAULT = 0`, `NUM_F32_DEFAULT = 0`, `NUM_F64_DEFAULT = 0` (Rust `Default::default() = 0` for bool and float types).
- `sa_std/char.sal`: `CHAR_DEFAULT = 0` (Rust `char::default()` = `'\0'`).
- `sa_std/core/result.sa`: `RESULT_DEFAULT` macro (constructs `Ok(0)` — tag=Result_OK, ok=0, err=0 — matching Rust `Result<T,E>::default()` where `T: Default`).
- Tests:
  - Extended `tests/unit_framework/std_from_into_default_macro_surface.sa` numeric defaults block (panic ID 10462) to cover `BOOL_DEFAULT`, `NUM_F32_DEFAULT`, `NUM_F64_DEFAULT`, `CHAR_DEFAULT`.
  - Extended `tests/unit_framework/std_default_types_macro_surface.sa` (panic ID updated 10463 -> 10464) to cover `RESULT_DEFAULT` tag/ok/err verification.
- Validation status:
  - Focused: `SA_STD_DIR=/home/vscode/.sa/std ./zig-out/bin/sa test tests/unit_framework/std_from_into_default_macro_surface.sa --jobs 1 --trace-panic` -> `2 passed; 0 failed; 0 skipped`.
  - Focused: `SA_STD_DIR=/home/vscode/.sa/std ./zig-out/bin/sa test tests/unit_framework/std_default_types_macro_surface.sa --jobs 1 --trace-panic` -> `1 passed; 0 failed; 0 skipped`.
  - Full `zig build unit-framework --summary all`: pass (`6/6 steps succeeded; 5/5 tests passed`).
- Panic IDs next free: 10465+.


## Completed: 2026-07-13 Slice/Option/Range/Bound Default macros

- Continued Rust std `Default` parity with thin Default-style macros over existing helpers (no new runtime/FFI).
- `sa_std/core/slice.sa`: `SLICE_DEFAULT` (empty slice: ptr=0, len=0).
- `sa_std/core/option.sa`: `OPTION_DEFAULT` (alias for `OPTION_NEW_NONE`, returns None).
- `sa_std/ops.sa`: `RANGE_U64_DEFAULT` (0..0), `RANGE_FULL_DEFAULT` (no-op for RangeFull, SIZE=0), `BOUND_U64_DEFAULT` (Unbounded, alias for `BOUND_U64_UNBOUNDED_NEW`), `RANGE_FROM_U64_DEFAULT` (0..), `RANGE_TO_U64_DEFAULT` (..0), `RANGE_TO_INCLUSIVE_U64_DEFAULT` (..=0).
- Tests: `tests/unit_framework/std_default_types_macro_surface.sa` (`10463`) covering all 8 new Default macros.
- Validation status:
  - Focused: `./zig-out/bin/sa test tests/unit_framework/std_default_types_macro_surface.sa --no-incremental` -> `1 passed`.
  - Focused: ops surface `1 passed`, option/result surface `5 passed`, slice/vec surface `20 passed`.
  - Full `zig build unit-framework --summary all`: pass (`6/6 steps succeeded; 5/5 tests passed`, EXIT:0).
- Panic IDs next free: 10464+.

## Completed: 2026-07-13 From/TryFrom/SaturatingFrom naming aliases + numeric Default constants

- Continued Rust std `From`/`TryFrom`/`SaturatingFrom` parity with thin naming aliases over existing `CONVERT_*`/`CONVERT_TRY_*`/`CONVERT_SAT_*` macros (no new runtime/FFI).
- `sa_std/convert.sa`: 56 new `FROM_*`/`TRY_FROM_*`/`SAT_FROM_*` Rust-named aliases wrapping existing conversion macros.
- `sa_std/num.sal`: 10 `NUM_*_DEFAULT = 0` constants for all integer types (Rust `Default::default() = 0`).
- Tests: `tests/unit_framework/std_from_into_default_macro_surface.sa` — 2 tests covering `From`/`TryFrom`/`SaturatingFrom` aliases (`10461`) and numeric defaults (`10462`).
- Validation status:
  - Focused: `./zig-out/bin/sa test tests/unit_framework/std_from_into_default_macro_surface.sa --no-incremental` -> `2 passed`.
  - Full `zig build unit-framework --summary all`: pass (`6/6 steps succeeded; 5/5 tests passed`, EXIT:0).
- Panic IDs next free: 10463+.

## Completed: 2026-07-13 CMP_ORDERING_DEFAULT_VALUE + STRING_BUF_LIT1/2/3 + SA_STD_DIR fix

- Discovered root cause of the previous session's "systemic flattener bug": `SA_STD_DIR=/home/vscode/.sa/std` was pointing to a stale install dated Jul 11 09:13. All edits to project `sa_std/` were invisible during testing because the test runner resolved imports from the stale system copy. Re-synced project `sa_std/` to `/home/vscode/.sa/std/` via rsync. Both `[MACRO]` additions to `.sa` files and `#def` additions to `.sal` files now work correctly.
- `sa_std/cmp.sal`: `CMP_ORDERING_DEFAULT_VALUE = CMP_ORDERING_EQUAL` (Ordering::default = Equal).
- `sa_std/string.sa`: `STRING_BUF_LIT1`, `STRING_BUF_LIT2`, `STRING_BUF_LIT3` multi-slice StringBuf constructors over `STRING_BUF_WITH_CAPACITY` + `STRING_BUF_PUSH_STR`.
- Tests: cmp test extended to verify `CMP_ORDERING_DEFAULT_VALUE` (`2 passed`), string_buf_lit test (`1 passed`), full string surface still `105 passed`.
- Validation status:
  - Focused: `./zig-out/bin/sa test tests/unit_framework/std_cmp_macro_surface.sa --no-incremental` -> `2 passed`.
  - Focused: `./zig-out/bin/sa test tests/unit_framework/std_string_buf_lit_macro_surface.sa --no-incremental` -> `1 passed`.
  - Full `zig build unit-framework --summary all`: pass (`6/6 steps succeeded; 5/5 tests passed`, EXIT:0).
- Both `[MACRO]` and `#def` additions to existing std files are now unblocked for future batches.
Current progress: 80% for the active full-test runtime/logging optimization follow-up; 100% for the initial test logging/timeout diagnostics milestone; the large-SAB `sa test --filter` compile-only/list performance slice remains complete, installed, and verified.

## Completed: 2026-07-13 Hash default constructor aliases

- Continued hash Rust API parity with thin Default-style aliases over existing concrete hasher constructors (no new runtime/FFI).
- `sa_std/hash.sa`: `DEFAULT_HASHER_DEFAULT`, `BUILD_HASHER_DEFAULT_DEFAULT`.
- Tests: extended existing hash surface test (`10041`) to cover default aliases.
- Validation status:
  - Full-file hash surface: pass (`1 passed`).
  - Full `zig build unit-framework --summary all`: attempted twice, but the Zig build runner remained active without spawning test children or flushing output; no failure output was produced before termination. Focused/full-file hash validation passed.

## Completed: 2026-07-13 Rc/Arc/Weak Default aliases

- Continued reference-counting Rust API parity with thin Default-style aliases over existing concrete `u64` constructors (no new runtime/FFI).
- `sa_std/core/rc.sa`: `RC_DEFAULT_U64`, `WEAK_DEFAULT`.
- `sa_std/core/arc.sa`: `ARC_DEFAULT_U64`, `ARC_WEAK_DEFAULT`.
- Tests: rc/weak defaults (`10459`), arc/weak defaults (`10460`).
- Validation status:
  - Focused tests: pass.
  - Full-file rc/weak surface: pass (`2 passed`).
  - Full-file arc/weak surface: pass (`2 passed`).
  - Full `zig build unit-framework --summary all`: pass (`6/6 steps succeeded; 5/5 tests passed`, EXIT:0).

## Completed: 2026-07-13 Typed net/fs/refcell/process Default aliases

- Continued net/fs/cell/process Rust API parity with thin Default-style aliases over existing helpers (no new runtime/FFI).
- `sa_std/net.sa`: `NET_IPV4_DEFAULT`, `NET_IPV6_DEFAULT`, `NET_SOCKET_ADDR_V4_DEFAULT`, `NET_SOCKET_ADDR_V6_DEFAULT`.
- `sa_std/process.sa`: `PROCESS_EXIT_STATUS_DEFAULT` (code 0 success status).
- `sa_std/core/refcell.sa`: `REFCELL_U64_DEFAULT` (value 0).
- `sa_std/fs.sa`: `FS_PERMISSIONS_DEFAULT`, `FS_FILE_TIMES_DEFAULT`.
- Tests: net typed defaults (`10455`), process exit_status default (`10456`), refcell default (`10457`), fs permissions/file_times defaults (`10458`).
- Validation status:
  - Focused tests: pass.
  - Full-file net typed address surface: pass (`4 passed`).
  - Full-file process surface: pass (`23 passed`).
  - Full-file refcell surface: pass (`2 passed`).
  - Full-file fs surface: pass (`15 passed`).
  - Full `zig build unit-framework --summary all`: pass (`6/6 steps succeeded; 5/5 tests passed`, EXIT:0).

## Completed: 2026-07-13 Net/process/io/env/mpsc defaults and aliases

- Continued net/process/io/env/sync Rust API parity with thin aliases/defaults over existing helpers (no new runtime/FFI).
- `sa_std/net.sa`: `NET_IP_ADDR_DEFAULT` (Ipv4 unspecified), `NET_SOCKET_ADDR_DEFAULT` (unspecified:0).
- `sa_std/process.sa`: `PROCESS_OUTPUT_SUCCESS`, `PROCESS_OUTPUT_CODE` over output status + success/code helpers.
- `sa_std/io.sa`: `IO_FLUSH_STDOUT`, `IO_FLUSH_STDERR` over stdout/stderr handles + `IO_FLUSH`.
- `sa_std/env.sa`: `ENV_XDG_*_OS` aliases for data/config/state/cache home dirs and data/config dirs.
- `sa_std/sync/mpsc.sa`: `MPSC_DEFAULT` over `MPSC_NEW` with capacity 16 (bounded facade, not unbounded mpsc).
- Tests: net defaults (`10450`), process output success/code (`10451`), io flush stdio (`10452`), env xdg os (`10453`), mpsc default (`10454`).
- Validation status:
  - Focused tests: pass.
  - Full-file net typed address surface: pass (`3 passed`).
  - Full-file process surface: pass (`22 passed`).
  - Full-file io utility surface: pass (`8 passed`).
  - Full-file env surface: pass (`17 passed`).
  - Full-file mpsc surface: pass (`2 passed`).
  - Full `zig build unit-framework --summary all`: pass (`6/6 steps succeeded; 5/5 tests passed`, EXIT:0).

## Completed: 2026-07-13 Time defaults/sleep + process naming + IO_COPY_N

- Continued time/process/io Rust API parity with thin aliases and a bounded copy helper over existing runtime (no new FFI).
- `sa_std/time.sa`: `TIME_SLEEP_DURATION_NS`, `TIME_INSTANT_DEFAULT`, `TIME_SYSTEM_TIME_DEFAULT`.
- `sa_std/process.sa`: `PROCESS_IS_SUCCESS`, `PROCESS_CODE`, `PROCESS_OUTPUT_STATUS`.
- `sa_std/io.sa`: `IO_COPY_N` (handle-to-handle copy with max-bytes bound over `sa_io_read`/`sa_io_write_all`).
- Tests: time defaults/sleep (`10447`), process is_success/code/output_status (`10448`), io copy_n (`10449`).
- Validation status:
  - Focused tests: pass.
  - Full-file time surface: pass (`6 passed`).
  - Full-file process surface: pass (`21 passed`).
  - Full-file io utility surface: pass (`7 passed`).
  - Full `zig build unit-framework --summary all`: pass (`6/6 steps succeeded; 5/5 tests passed`, EXIT:0).

## Completed: 2026-07-12 Path unix chown/mkfifo/make_dir + process success + thread sleep duration

- Continued path/process/thread Rust API parity with thin wrappers/aliases over existing helpers (no new runtime/FFI).
- `sa_std/path.sa`: `PATH_CHOWN`/`PATH_LCHOWN`/`PATH_CHROOT`/`PATH_MKFIFO`/`PATH_MAKE_DIR`/`PATH_MAKE_DIR_WITH_MODE` plus PathBuf wrappers.
- `sa_std/process.sa`: `PROCESS_SUCCESS` alias over `PROCESS_EXIT_STATUS_SUCCESS`.
- `sa_std/thread.sa`: `THREAD_SLEEP_DURATION_NS` alias over `THREAD_SLEEP_NS`.
- Tests: path unix chown/mkfifo/make_dir (`10444`), process success (`10445`), thread sleep duration_ns (`10446`).
- Validation status:
  - Focused tests: pass.
  - Full-file thread surface: pass (`6 passed`).
  - Full-file process surface: pass (`20 passed`).
  - Full-file path surface: pass (`20 passed`).
  - Full `zig build unit-framework --summary all`: pass (`6/6 steps succeeded; 5/5 tests passed`, EXIT:0).

## Completed: 2026-07-12 Path base64/open-flags + env home_os + once defaults + process exit_code

- Continued path/env/sync/process Rust API parity with thin wrappers/aliases over existing helpers (no new runtime/FFI).
- `sa_std/path.sa`: `PATH_OPEN_FLAGS`/`PATH_OPEN_WITH_OPTIONS`/`PATH_READ_FILE_BASE64`/`PATH_WRITE_FILE_BASE64` plus PathBuf wrappers.
- `sa_std/env.sa`: `ENV_HOME_DIR_OS` alias over `ENV_HOME_DIR`.
- `sa_std/sync/once.sa`: `ONCE_LOCK_DEFAULT`/`LAZY_LOCK_DEFAULT`.
- `sa_std/process.sa`: `PROCESS_EXIT_CODE` alias over `PROCESS_EXIT_STATUS_CODE`.
- Tests: path base64/open_flags (`10440`), once_lock/lazy_lock defaults (`10441`), env home_dir_os (`10442`), process exit_code (`10443`).
- Validation status:
  - Focused tests: pass.
  - Full-file once surface: pass (`5 passed`).
  - Full-file env surface: pass (`16 passed`).
  - Full-file path surface: pass (`19 passed`).
  - Full-file process surface: pass (`19 passed`).
  - Full `zig build unit-framework --summary all`: pass (`6/6 steps succeeded; 5/5 tests passed`, EXIT:0).

## Completed: 2026-07-12 Collections/Atomic Default aliases + Path permissions/FileTimes objects

- Continued collections/sync/path Rust API parity with thin Default-style constructors and Path object wrappers over existing helpers (no new runtime/FFI).
- Collections: `MAP_DEFAULT`, `SET_DEFAULT`, `BTREE_MAP_DEFAULT`, `BTREE_SET_DEFAULT`, `VEC_DEQUE_DEFAULT`, `BINARY_HEAP_DEFAULT`.
- Atomic zero-init defaults: `ATOMIC_BOOL_DEFAULT`, `ATOMIC_U8/U16/U32/U64/USIZE_DEFAULT`.
- `sa_std/path.sa`: `PATH_SET_PERMISSIONS_OBJ` / `PATH_FILE_TIMES_SET` plus PathBuf wrappers over existing FS permissions-object and FileTimes helpers.
- Tests: hashmap/set/btree/deque/heap defaults (`10431-10435`), atomic default init (`10436`), path permissions/file_times (`10437`).
- Validation status:
  - Focused default/path-object tests: pass.
  - Full-file hashmap/hashset/btree/deque/heap/atomic/path surfaces: pass.
  - Full `zig build unit-framework --summary all`: pass (`6/6 steps succeeded; 5/5 tests passed`, EXIT:0).

## Completed: 2026-07-12 Atomic signed/ptr defaults + Path metadata/file-size/remove/mode wrappers

- Continued sync/path Rust API parity with thin Default-style atomic constructors and Path/PathBuf filesystem wrappers over existing FS helpers (no new runtime/FFI).
- Atomic signed/ptr zero-init defaults: `ATOMIC_I8/I16/I32/I64/ISIZE_DEFAULT`, `ATOMIC_PTR_DEFAULT` (null pointer).
- `sa_std/path.sa`: `PATH_METADATA_JSON`/`PATH_FS_SIZE`/`PATH_REMOVE_ENTRY`/`PATH_REMOVE_ANY`/`PATH_CREATE_DIR_WITH_MODE`/`PATH_CREATE_DIR_ALL_WITH_MODE` plus PathBuf wrappers.
- Naming notes: avoid `PATH_LEN` (collides with PathBuf string-length macro expansion / hangs compile) and `PATH_CREATE_DIR_MODE` (prefix collision with `PATH_CREATE_DIR`); use `PATH_FS_SIZE` and `*_WITH_MODE`.
- Tests: atomic signed/ptr default init (`10438`), path PathBuf metadata_json/file-size/remove/mode (`10439`).
- Validation status:
  - Focused atomic signed/ptr default + path metadata/file-size/remove/mode tests: pass.
  - Full-file atomic surface: pass (`12 passed`).
  - Full-file path surface: pass (`18 passed`).
  - Full `zig build unit-framework --summary all`: pass (`6/6 steps succeeded; 5/5 tests passed`, EXIT:0).

## Completed: 2026-07-12 Path DirBuilder/OpenOptions slice facades

- Continued path Rust API parity by wrapping existing FS SSA builders with Path/PathBuf slice entrypoints (no new runtime/FFI).
- `sa_std/path.sa`: `PATH_DIR_BUILDER_CREATE`, `PATH_OPEN_OPTIONS_BUILDER_OPEN`, plus PathBuf wrappers.
- Test: path PathBuf dir_builder/open_options aliases (`10430`).
- Validation status:
  - Focused path builder test: pass.
  - Full-file path surface: pass.
  - Full `zig build unit-framework --summary all`: pass (`6/6 steps succeeded; 5/5 tests passed`, EXIT:0).

## Completed: 2026-07-12 Time Duration/SystemTime defaults + OsString default

- Continued time/ffi naming parity with thin aliases over existing helpers (no new runtime/FFI).
- `sa_std/time.sa`: `TIME_DURATION_DEFAULT`, `TIME_SYSTEM_TIME_UNIX_EPOCH`, `TIME_INSTANT_SATURATING_DURATION_SINCE`.
- `sa_std/os/unix_ffi.sa`: `OS_STRING_DEFAULT` over `OS_STRING_NEW`.
- Tests: time duration default/unix epoch (`10428`), path OsString default (`10429`).
- Validation status:
  - Focused time/osstring tests: pass.
  - Full-file time surface: pass.
  - Full-file path surface: pass.
  - Full `zig build unit-framework --summary all`: pass (`6/6 steps succeeded; 5/5 tests passed`, EXIT:0).

## Completed: 2026-07-12 Path read_dir aliases

- Continued path Rust API parity with directory listing wrappers over existing FS read-dir helpers (no new runtime/FFI).
- `sa_std/path.sa`: `PATH_READ_DIR_JSON`/`PATH_READ_DIR_ENTRIES` plus PathBuf wrappers `PATH_BUF_READ_DIR_JSON`/`PATH_BUF_READ_DIR_ENTRIES`.
- Test: path PathBuf read_dir aliases (`10425`).
- Also landed in the same continuation window:
  - `THREAD_CURRENT`/`THREAD_YIELD` aliases over current-id / yield_now.
  - `ENV_SET_VAR_OS`/`ENV_REMOVE_VAR_OS` aliases over set/remove var.
  - Tests: thread current/yield (`10426`), env set/remove os (`10427`).
- Validation status:
  - Focused path read_dir / thread current-yield / env set_var_os: pass.
  - Full-file path surface: pass.
  - Full-file env/thread surfaces: pass.
  - Full `zig build unit-framework --summary all`: pass (`6/6 steps succeeded; 5/5 tests passed`, EXIT:0).

## Completed: 2026-07-12 Path FS rename/link/symlink + IO handle aliases

- Continued path/io Rust API parity with thin wrappers over existing FS/IO runtime helpers (no new FFI).
- `sa_std/path.sa`: `PATH_READ_TO_STRING`/`PATH_CREATE_DIR_ALL`/`PATH_REMOVE_DIR_ALL`/`PATH_RENAME`/`PATH_HARD_LINK`/`PATH_SYMLINK`/`PATH_SET_PERMISSIONS`/`PATH_SET_TIMES_MS` plus PathBuf wrappers.
- `sa_std/io.sa`: `IO_READ`/`IO_READ_EXACT`/`IO_WRITE`/`IO_WRITE_ALL`/`IO_FLUSH`/`IO_CLOSE` handle-level status-returning aliases over `sa_io_*`.
- Tests: path PathBuf fs rename/link/symlink/read_to_string (`10423`), io handle read/write/flush/close (`10424`).
- Validation status:
  - Focused path more-ops + io handle tests: pass.
  - Full-file `std_path` surface: pass.
  - Full-file `std_io_utility` surface: pass.
  - Full `zig build unit-framework --summary all`: pass (`6/6 steps succeeded; 5/5 tests passed`, EXIT:0).

## Completed: 2026-07-12 Path FS ops + mutex/rwlock/once defaults + env path_os + process pid aliases

- Continued path/sync/env/process Rust API parity with thin naming aliases and Path filesystem wrappers over existing helpers (no new runtime/FFI).
- `sa_std/path.sa`: `PATH_OPEN_READ`/`PATH_OPEN_WRITE`/`PATH_CREATE`/`PATH_READ_FILE`/`PATH_WRITE_FILE`/`PATH_REMOVE_FILE`/`PATH_REMOVE_DIR`/`PATH_CREATE_DIR`/`PATH_COPY` plus PathBuf wrappers `PATH_BUF_OPEN_*`/`CREATE`/`READ_FILE`/`WRITE_FILE`/`REMOVE_*`/`CREATE_DIR`/`COPY`.
- `sa_std/sync/{mutex,rwlock,once}.sa`: `MUTEX_DEFAULT`, `RWLOCK_DEFAULT`, `ONCE_DEFAULT` aliases of existing constructors.
- `sa_std/env.sa`: `ENV_TEMP_DIR_OS`/`ENV_CURRENT_EXE_OS`/`ENV_CURRENT_DIR_OS`/`ENV_SET_CURRENT_DIR_OS`.
- `sa_std/process.sa`: `PROCESS_PID`/`PROCESS_PPID` aliases over `PROCESS_ID`/`PROCESS_PARENT_ID`; `PROCESS_UID`/`PROCESS_GID` over `PROCESS_USER_ID`/`PROCESS_GROUP_ID`.
- Fixed env temp/current path os test free-status checks to use `ENV_STATUS_IS_OK` (status `0`, not bool `1`).
- Fixed remaining unit-framework cross-file diagnostic collisions: net unix datagram assert codes `1006`/`1007` renumbered to `10417`/`10418` so they no longer share env panic IDs.
- New/extended surface tests: path PathBuf fs ops (`10414`), mutex default (`10415`), env temp/current path os (`10416`), process pid/ppid (`10419`), rwlock default (`10420`), once default (`10421`), process uid/gid (`10422`).
- Validation status:
  - Focused path/mutex/env/process/once/rwlock tests: pass.
  - Full-file path/env/mutex surfaces: pass.
  - Full `zig build unit-framework --summary all`: pass (`6/6 steps succeeded; 5/5 tests passed`, EXIT:0).

## Completed: 2026-07-12 Time SystemTime/Instant aliases + IO copy + PathBuf FS queries + OnceLock aliases

- Continued time/io/path/sync Rust API parity with thin naming aliases and one handle-copy utility over existing helpers (no new runtime/FFI).
- `sa_std/time.sa`: `TIME_INSTANT_NOW`, `TIME_SYSTEM_TIME_NOW`, `TIME_SYSTEM_TIME_FROM_UNIX_NS`, `TIME_SYSTEM_TIME_AS_UNIX_NS`, `TIME_SYSTEM_TIME_CHECKED_DURATION_SINCE`, `TIME_SYSTEM_TIME_DURATION_SINCE`, `TIME_SYSTEM_TIME_ELAPSED`, `TIME_SYSTEM_TIME_CHECKED_ADD`, `TIME_SYSTEM_TIME_CHECKED_SUB` over existing ns clocks / checked duration arithmetic. Instant uses monotonic `TIME_NOW_NS`; SystemTime uses unix-epoch `TIME_NOW_UNIX_NS`.
- `sa_std/io.sa`: `IO_COPY` handle-to-handle copy via fixed 4096-byte stack chunk + `sa_io_read` / `sa_io_write_all` loop (not trait-object `io::copy`).
- `sa_std/path.sa` PathBuf FS aliases: `PATH_BUF_TRY_EXISTS`, `PATH_BUF_METADATA`, `PATH_BUF_CANONICALIZE`, `PATH_BUF_READ_LINK`, `PATH_BUF_IS_SYMLINK` over `PATH_BUF_AS_PATH` + existing `PATH_*` helpers.
- `sa_std/sync/once.sa`: `ONCE_LOCK_*` aliases (`NEW`/`IS_READY`/`SET`/`TRY_GET`/`GET`/`GET_OR_INIT`/`TAKE`/`INTO_INNER`) over existing concrete Once/OnceLock u64 cell.
- Validation status:
  - Focused time/once/path/io tests: pass.
  - Full-file `std_time`/`std_once`/`std_path`/`std_io_utility` surfaces: pass.
  - Full `zig build unit-framework --summary all`: pass (`6/6 steps succeeded; 5/5 tests passed`, EXIT:0).

## Completed: 2026-07-12 Atomic signed bitwise + fetch_nand + global panic-id uniqueness

- Continued sync atomic Rust API parity with signed bitwise RMW and multi-width `fetch_nand` helpers over existing `atomic_rmw_*` / `cmpxchg` SSA ops (no new runtime/FFI).
- `sa_std/sync/atomic.sa`:
  - signed: `ATOMIC_{I8,I16,I32,I64,ISIZE}_FETCH_{AND,OR,XOR}`
  - all integer widths: `ATOMIC_{U8,U16,U32,U64,USIZE,I8,I16,I32,I64,ISIZE}_FETCH_NAND` via load/`and`/`xor -1`/cmpxchg loop (ISA has no native `atomic_rmw_nand`)
- Also documented/landed the previous unfinished verification batch already present in tree:
  - multi-width `ATOMIC_*_FETCH_{MIN,MAX,UMIN,UMAX}`
  - `THREAD_SLEEP_NS` / `THREAD_SLEEP_MS` aliases of `TIME_SLEEP_*`
  - `PATH_BUF_CLONE_FROM`
- Tests:
  - `std_atomic_macro_surface.sa` fetch_min/max + fetch_and/or/xor/nand blocks
  - `std_thread_macro_surface.sa` sleep
  - `std_path_macro_surface.sa` clone_from
- Fixed global duplicate `panic(N)` IDs across unit-framework SA surfaces (not only within-file): first occurrence kept, later collisions renumbered from `10026+`, and matching `@sa_assert_*` codes in the same `@test` block were realigned. Result: 932 unique panic codes across unit-framework suites (including `943/944/945` collisions).
- Validation status:
  - Focused atomic nand batch: pass.
  - Focused path clone_from / atomic min-max / thread sleep: pass.
  - Per-file `sa test` scan of feature_suite + all std_* macro surfaces after renumber/nand: all passed (string suite can exceed 180s under load; use >=300s timeout).
  - Full `zig build unit-framework --summary all`: pass (`6/6 steps succeeded; 5/5 tests passed`, EXIT:0).


## Completed: 2026-07-12 Thread builder + PathBuf push/join + Env path_os + CStr lossy

- Continued thread/path/env/ffi Rust API parity with thin builder and naming aliases over existing helpers (no new runtime/FFI except already-landed surfaces).
- `sa_std/thread.sa`: `THREAD_BUILDER_NEW`, `THREAD_BUILDER_WITH_DETACHED`, `THREAD_BUILDER_SPAWN` over `THREAD_SPAWN` / `THREAD_SPAWN_DETACHED` (detached flag only; no stack-size/name ABI).
- `sa_std/path.sa`: `PATH_BUF_PUSH_PATH_BUF`, `PATH_BUF_JOIN`, `PATH_BUF_JOIN_PATH_BUF`.
- `sa_std/env.sa`: `ENV_SPLIT_PATHS_OS`, `ENV_JOIN_PATHS_OS` over JSON path helpers.
- `sa_std/ffi.sa`: `CSTR_TO_STRING_LOSSY` over `CSTR_TO_BYTES` + `STRING_BUF_FROM_UTF8_LOSSY`.
- Validation status:
  - Focused `std_thread_macro_surface.sa --filter 'builder'`: pass.
  - Focused `std_path_macro_surface.sa --filter 'push/join'`: pass.
  - Focused `std_env_macro_surface.sa --filter 'split_paths_os'`: pass.
  - Focused `std_ffi_cstr_macro_surface.sa --filter 'cstr to_string_lossy'`: pass.

## Completed: 2026-07-12 Net format_ascii + PathBuf query aliases + Env args_os/vars_os

- Continued net/path/env Rust API parity with typed-address ASCII format helpers, PathBuf query facades, and Os-named env aliases over existing JSON buffers.
- Runtime (`src/runtime/sa_std.zig`): `sa_net_ipv4_format_ascii`, `sa_net_ipv6_format_ascii`, `sa_net_socket_addr_v4_format_ascii`, `sa_net_socket_addr_v6_format_ascii` writing into caller buffers with explicit `(ok,len)`.
- `sa_std/net.sai` / `sa_std/net.sa`: `NET_IPV4_FORMAT_ASCII`, `NET_IPV6_FORMAT_ASCII`, `NET_SOCKET_ADDR_V4_FORMAT_ASCII`, `NET_SOCKET_ADDR_V6_FORMAT_ASCII`, `NET_IP_ADDR_FORMAT_ASCII`, `NET_SOCKET_ADDR_FORMAT_ASCII`.
- Semantics: IPv4 dotted-decimal; IPv6 deterministic expanded lowercase hex segments (no zero-compression); socket V4 `ip:port`; socket V6 `[ip%scope]:port` with optional numeric scope. Not Rust `Display` traits / zero-compression / interface-name zones.
- `sa_std/path.sa` PathBuf query aliases: `PATH_BUF_IS_ABSOLUTE`, `PATH_BUF_IS_RELATIVE`, `PATH_BUF_HAS_ROOT`, `PATH_BUF_COMPONENT_COUNT`, `PATH_BUF_TRY_COMPONENT_AT`, `PATH_BUF_ANCESTOR_COUNT`, `PATH_BUF_TRY_ANCESTOR_AT`, `PATH_BUF_TRY_PARENT`, `PATH_BUF_TRY_FILE_NAME`, `PATH_BUF_TRY_FILE_STEM`, `PATH_BUF_TRY_EXTENSION` over `PATH_BUF_AS_PATH` + existing `PATH_*` helpers.
- `sa_std/env.sa`: `ENV_ARGS_OS`, `ENV_VARS_OS` aliases over `ENV_ARGS_JSON` / `ENV_VARS_JSON` (still JSON env-buffer handles, not true OsString iterators).
- Validation status:
  - Focused `std_net_typed_address_macro_surface.sa --filter 'format_ascii'`: pass.
  - Focused `std_path_macro_surface.sa --filter 'query aliases'`: pass.
  - Focused `std_env_macro_surface.sa --filter 'args_os'`: pass.
  - Rebuilt `sa-std-static` with new format symbols.

## Completed: 2026-07-12 PathBuf/OsString conversion + lossy string helpers

- Continued path/os/ffi Rust API parity with concrete Unix byte-buffer conversion and lossy UTF-8 materialization helpers over existing `STRING_BUF_FROM_UTF8_LOSSY` / owned buffer constructors (no new runtime/FFI).
- Added supportable macros:
  - `sa_std/path.sa`: `PATH_BUF_AS_OS_STR`, `PATH_BUF_FROM_OS_STR`, `PATH_BUF_FROM_OS_STRING`, `PATH_BUF_INTO_OS_STRING`, `PATH_BUF_INTO_OS_STRING_MOVE` (path now imports `os/unix_ffi.sa`)
  - `sa_std/os/unix_ffi.sa`: `OS_STRING_TO_STRING_LOSSY`, `OS_STR_TO_STRING_LOSSY`, `OS_STRING_FROM_PATH`
  - `sa_std/ffi.sa`: `CSTRING_TO_STRING_LOSSY`
- Semantics: conversions copy bytes between PathBuf (StringBuf) and OsString (Vec<u8>) facades. Lossy helpers always materialize owned `StringBuf` via existing UTF-8 lossy reconstruction; they do not model Rust `Cow<str>` or display adapters. `PATH_BUF_INTO_OS_STRING` copies then leaves PathBuf live; `*_MOVE` frees the PathBuf after copy.
- Validation status:
  - Focused `std_path_macro_surface.sa --filter 'os conversion'`: pass (`1 passed; 6 skipped`).
  - Focused `std_os_unix_ffi_macro_surface.sa --filter 'to_string_lossy'`: pass (`1 passed; 4 skipped`).
  - Focused `std_ffi_cstr_macro_surface.sa --filter 'to_string_lossy'`: pass (`1 passed; 3 skipped`).

## Completed: 2026-07-12 Process Command builder output + CString default/clone/lit

- Continued process/FFI Rust API parity with thin capture and owned-CString convenience helpers over existing runtime/macro surfaces (no new FFI).
- Added supportable `sa_std/process.sa` macros: `PROCESS_COMMAND_BUILDER_EXEC_CAPTURE`, `PROCESS_COMMAND_BUILDER_OUTPUT`.
- Semantics: builder `output`/`exec_capture` honor `has_cwd`/`cwd` only and lower through existing `PROCESS_EXEC_CAPTURE*` / `PROCESS_EXEC_CAPTURE_OUTPUT*`. `arg0` / process-group / setsid builder fields are accepted for API shape but not applied on capture paths (capture runtime ABI does not expose those CommandExt fields).
- Added supportable `sa_std/ffi.sa` macros: `CSTRING_DEFAULT`, `CSTRING_CLONE`, `CSTRING_LIT1`.
- Semantics: `DEFAULT` is `CSTRING_NEW` of an empty byte slice (owned empty C string with trailing NUL). `CLONE` revalidates/copies through `CSTRING_AS_BYTES_WITH_NUL` + `CSTRING_FROM_BYTES_WITH_NUL`. `LIT1` is a Rust-style single-slice constructor alias over `CSTRING_NEW`.
- Validation status:
  - Focused `std_ffi_cstr_macro_surface.sa --filter 'default/clone'`: pass (`1 passed; 2 skipped`).
  - Focused `std_process_macro_surface.sa --filter 'command builder output'`: pass (`1 passed; 15 skipped`).

## Completed: 2026-07-12 PathBuf/OsString lit+capacity remaining + Env rust-named aliases

- Continued path/os/env Rust API naming parity with thin aliases and multi-part literal constructors over existing owned byte-buffer helpers (no new runtime/FFI).
- Added supportable macros:
  - `sa_std/path.sa`: `PATH_BUF_CAPACITY_REMAINING`, `PATH_BUF_REMAINING_CAPACITY`, `PATH_BUF_EXTRA_CAPACITY`, `PATH_BUF_LIT1`, `PATH_BUF_LIT2`, `PATH_BUF_LIT3`
  - `sa_std/os/unix_ffi.sa`: `OS_STRING_CAPACITY_REMAINING`, `OS_STRING_REMAINING_CAPACITY`, `OS_STRING_EXTRA_CAPACITY`, `OS_STRING_LIT1`, `OS_STRING_LIT2`, `OS_STRING_LIT3`
  - `sa_std/env.sa`: Rust-named aliases `ENV_VAR`, `ENV_VAR_OS`, `ENV_ARGS`, `ENV_VARS`, `ENV_SPLIT_PATHS`, `ENV_JOIN_PATHS`, `ENV_HOME_DIR` over existing get/try/JSON/home helpers
- Semantics: capacity-remaining aliases report spare capacity on empty owned buffers. Path/OsString `LIT*` construct by `FROM_*` then sequential push. Env aliases preserve current buffer/JSON contracts rather than introducing true `args_os`/`vars_os` iterators or OsString-returning APIs.
- Validation status:
  - Focused `std_path_macro_surface.sa --filter 'lit/capacity'`: pass (`1 passed; 5 skipped`).
  - Focused `std_os_unix_ffi_macro_surface.sa --filter 'lit/capacity'`: pass (`1 passed; 3 skipped`).
  - Focused `std_env_macro_surface.sa --filter 'rust-named'`: pass after fixing the test to `stack_alloc Slice_SIZE` (and not explicitly free stack slices).
  - Full `zig build unit-framework --summary all`: pass (`6/6 steps succeeded; 5/5 tests passed`).

## Completed: 2026-07-12 Atomic narrow-width fetch_update + FROM_PTR aliases

- Continued sync Rust API parity by finishing remaining concrete `fetch_update` widths and adding Rust-named `from_ptr` aliases over existing transparent `from_mut` helpers.
- Added supportable `sa_std/sync/atomic.sa` macros:
  - `ATOMIC_BOOL_FETCH_UPDATE`, `ATOMIC_U8_FETCH_UPDATE`, `ATOMIC_I8_FETCH_UPDATE`, `ATOMIC_U16_FETCH_UPDATE`, `ATOMIC_I16_FETCH_UPDATE`
  - `ATOMIC_*_FROM_PTR` thin aliases for every existing `ATOMIC_*_FROM_MUT_PTR` surface (Bool/U8/I8/U16/I16/U32/I32/U64/I64/USIZE/ISIZE/PTR)
- Semantics: fetch_update remains a cmpxchg loop over a macro-level `T -> T` update function with eventual `ok=1`. `FROM_PTR` does not claim Rust strict provenance; it is an address-transparent layout alias of `FROM_MUT_PTR`.
- Validation status:
  - Focused `std_atomic_macro_surface.sa --filter 'fetch_update'`: pass (`3 passed; 5 skipped`).
  - Full `zig build unit-framework --summary all`: pass (`6/6 steps succeeded; 5/5 tests passed`).

## Completed: 2026-07-12 IPv6 parse_ascii + IpAddr/SocketAddr enum parse upgrade

- Continued net Rust API parity by adding concrete IPv6 / SocketAddrV6 ASCII parse helpers and upgrading enum parse paths to accept IPv4 or IPv6 text.
- Runtime (`src/runtime/sa_std.zig`): `sa_net_ipv6_parse_ascii`, `sa_net_socket_addr_v6_parse_ascii` over Zig `Ip6Address.parse` (bracketed `[ip]:port` for sockets; optional numeric `%scope` via Zig parser). Segment/port/scope stored in host little-endian layout matching SA `u16`/`u32` stores.
- `sa_std/net.sai`: declared both new externs.
- `sa_std/net.sa` macros: `NET_IPV6_TRY_PARSE_ASCII` / `NET_IPV6_PARSE_ASCII`, `NET_SOCKET_ADDR_V6_TRY_PARSE_ASCII` / `NET_SOCKET_ADDR_V6_PARSE_ASCII`, `NET_IP_ADDR_TO_IPV6`; upgraded `NET_IP_ADDR_TRY_PARSE_ASCII` and `NET_SOCKET_ADDR_TRY_PARSE_ASCII` to fall through V4→V6 without redefining the caller `ok` register mid-branch.
- Semantics: pure IPv6 text (e.g. `::1`, `2001:db8::1`); socket form requires brackets (`[::1]:8080`). Does not model Rust `AddrParseError` objects, interface-name zone resolution beyond Zig numeric scope digits, or native `u128` bit constructors.
- Validation status:
  - Focused `std_net_macro_surface.sa --filter 'parse_ascii'`: pass (`8 passed; 8 skipped`).
  - Full-file `std_net_macro_surface.sa`: pass (`16 passed`).
  - Full `zig build unit-framework --summary all`: pass (`6/6 steps succeeded; 5/5 tests passed`).

## Completed: 2026-07-12 Process Command builder SSA facade batch

- Continued process Rust API parity with a concrete Command-style SSA config builder over existing `PROCESS_*_COMMAND_EXT` helpers, requiring no new runtime/FFI surface.
- Added supportable `sa_std/process.sa` macros: `PROCESS_COMMAND_BUILDER_NEW`, `PROCESS_COMMAND_BUILDER_WITH_CURRENT_DIR`, `PROCESS_COMMAND_BUILDER_WITH_ARG0`, `PROCESS_COMMAND_BUILDER_WITH_PROCESS_GROUP`, `PROCESS_COMMAND_BUILDER_WITH_SETSID`, `PROCESS_COMMAND_BUILDER_STATUS`, `PROCESS_COMMAND_BUILDER_SPAWN`, `PROCESS_COMMAND_BUILDER_SPAWN_STREAM`.
- Semantics: builder state is propagating scalar flags/lengths only; callers still supply addressable cwd/arg0 buffers at status/spawn time (stack dummy when unused). Does not model env maps, Stdio pipe objects, heap Command values, or uid/gid/groups/chroot extensions.
- Validation status:
  - Focused `std_process_macro_surface.sa --filter 'command builder'`: pass (`1 passed; 14 skipped`).
  - Full `zig build unit-framework --summary all`: pass (`6/6 steps succeeded; 5/5 tests passed`).

## Completed: 2026-07-12 multi-width Atomic fetch_update + unit-framework diagnostic ID uniqueness

- Fixed latent unit-framework diagnostic-code collisions where assert codes reused panic IDs from sibling `@test` blocks inside the same surface file.
  - `tests/unit_framework/std_fs_macro_surface.sa`: aligned assert codes in hard-link/symlink/canonicalize/metadata/remove_dir_all/read_to_string/try_exists blocks to each block's unique panic ID (942..948).
  - `tests/unit_framework/std_net_unix_macro_surface.sa`: moved datagram pathname/abstract assert codes off shared 996/997 onto free 1006/1007.
- Continued sync Rust API parity by extending `fetch_update` beyond `AtomicU64`.
- Added supportable `sa_std/sync/atomic.sa` macros: `ATOMIC_U32_FETCH_UPDATE`, `ATOMIC_I32_FETCH_UPDATE`, `ATOMIC_I64_FETCH_UPDATE`, `ATOMIC_USIZE_FETCH_UPDATE`, `ATOMIC_ISIZE_FETCH_UPDATE`, `ATOMIC_PTR_FETCH_UPDATE`.
- Semantics: each helper is a cmpxchg loop over a concrete macro-level `T -> T` update function register and always reports `ok=1` on eventual success (no Rust `Option` abort path). `ATOMIC_PTR_FETCH_UPDATE` updates pointer values, not byte offsets.
- Validation status:
  - Focused `std_atomic_macro_surface.sa --filter 'fetch_update'`: pass (`2 passed; 5 skipped`).
  - Focused `std_fs_macro_surface.sa` / `std_net_unix_macro_surface.sa`: pass after diagnostic renumber.
  - Full `zig build unit-framework --summary all`: pass (`6/6 steps succeeded; 5/5 tests passed`).

## Completed: 2026-07-12 AtomicU64 fetch_update + StringBuf LIT constructors batch

- Continued sync/string Rust API parity with two small supportable batches, requiring no new runtime/FFI surface.
- Added `sa_std/sync/atomic.sa`: `ATOMIC_U64_FETCH_UPDATE` (cmpxchg loop over a macro-level `u64 -> u64` update function; always reports `ok=1` on eventual success, no Rust `Option` abort path).
- Added `sa_std/string.sa`: `STRING_BUF_LIT1`, `STRING_BUF_LIT2`, `STRING_BUF_LIT3` over `STRING_BUF_FROM_STR` + `STRING_BUF_PUSH_STR`.
- Semantics: fetch_update is a concrete AtomicU64 helper, not a generic closure/`Ordering` enum object. StringBuf lits concatenate fixed-arity `Slice` fragments into an owned buffer.
- Validation status:
  - Focused `std_atomic_macro_surface.sa --filter 'fetch_update'`: pass (`1 passed; 5 skipped`).
  - Dedicated `std_string_buf_lit_macro_surface.sa`: pass (`1 passed`).
  - Full `zig build unit-framework --summary all`: pass (`6/6 steps succeeded; 5/5 tests passed`).

## Completed: 2026-07-12 LazyLock aliases over Once/OnceLock batch

- Continued sync Rust API parity by adding concrete `LazyLock`-style naming aliases over the existing `Once`/`OnceLock` u64 cell helpers, requiring no new runtime/FFI surface.
- Added supportable `sa_std/sync/once.sa` macros: `LAZY_LOCK_NEW`, `LAZY_LOCK_FORCE`, `LAZY_LOCK_GET`, `LAZY_LOCK_IS_READY`, `LAZY_LOCK_INTO_INNER`.
- Semantics: `FORCE` is `ONCE_GET_OR_INIT` with an explicit init function register; `GET` is non-blocking `TRY_GET`. This does not model generic `LazyLock<T,F>` storage of a function object, poison, or auto-drop lifecycle.
- Validation status:
  - Full-file `std_once_macro_surface.sa`: pass (`2 passed`).
  - Full `zig build unit-framework --summary all`: pass (`6/6 steps succeeded; 5/5 tests passed`).

## Completed: 2026-07-12 Vec u64 literal constructors batch

- Continued Vec Rust API parity by adding fixed-arity u64 literal constructors over `VEC_NEW` + `VEC_PUSH_U64`, requiring no new runtime/FFI surface.
- Added supportable `sa_std/vec.sa` macros: `VEC_LIT1_U64`, `VEC_LIT2_U64`, `VEC_LIT3_U64`.
- Semantics: constructs a fresh Vec and pushes 1/2/3 concrete u64 values. Does not model generic element literals, array-to-vec From, or allocator-aware constructors.
- Validation status:
  - Focused `std_vec_macro_surface.sa --filter 'vec lit'`: pass (`1 passed; 44 skipped`).
  - Full `zig build unit-framework --summary all`: pass (`6/6 steps succeeded; 5/5 tests passed`).

## Completed: 2026-07-12 VecDeque from/lit constructor batch

- Continued VecDeque Rust API parity by adding fixed-arity constructors and from-slice/from-vec helpers over the concrete `u64` ring buffer push path, requiring no new runtime/FFI surface.
- Added supportable `sa_std/vec_deque.sa` macros:
  - literals: `VEC_DEQUE_LIT1`, `VEC_DEQUE_LIT2`, `VEC_DEQUE_LIT3`
  - from: `VEC_DEQUE_FROM_SLICE_U64`, `VEC_DEQUE_FROM_VEC_U64`
- Semantics: `FROM_*` constructs a fresh deque then push_back each source `u64` element (auto-growing). Slice length is an element count. These do not model generic element support, lazy iterators, or allocator-aware constructors.
- Validation status:
  - Focused `std_vec_deque_macro_surface.sa --filter 'from/lit'`: pass (`1 passed; 16 skipped`).
  - Full `zig build unit-framework --summary all`: pass (`6/6 steps succeeded; 5/5 tests passed`).

## Completed: 2026-07-12 BinaryHeap from/lit constructor batch

- Continued BinaryHeap Rust API parity by adding fixed-arity constructors and from/extend helpers over the concrete `u64` max-heap push path, requiring no new runtime/FFI surface.
- Added supportable `sa_std/binary_heap.sa` macros:
  - literals: `BINARY_HEAP_LIT1`, `BINARY_HEAP_LIT2`, `BINARY_HEAP_LIT3`
  - from/extend: `BINARY_HEAP_FROM_SLICE_U64`, `BINARY_HEAP_FROM_VEC_U64`, `BINARY_HEAP_EXTEND_FROM_SLICE_U64`, `BINARY_HEAP_EXTEND_FROM_VEC_U64`
- Semantics: each constructor/extend helper pushes source elements through the existing heapify path. Slice length is treated as a `u64` element count (not byte length). These do not model generic ordering, lazy iterator `extend`, or allocator-aware constructors.
- Validation status:
  - Focused `std_binary_heap_macro_surface.sa --filter 'from/lit'`: pass (`1 passed; 7 skipped`).
  - Full `zig build unit-framework --summary all`: pass (`6/6 steps succeeded; 5/5 tests passed`).

## Completed: 2026-07-12 OsString/OsStr owned byte-buffer facade batch

- Continued the Unix FFI / platform-string Rust API parity audit by expanding the concrete `OsStr`/`OsString` facade over existing `Slice` / `Vec<u8>` storage, requiring no new runtime/FFI surface.
- Added supportable `sa_std/os/unix_ffi.sa` macros:
  - OsString ownership/capacity: `OS_STRING_NEW`, `OS_STRING_WITH_CAPACITY`, `OS_STRING_FROM_STR`, `OS_STRING_FROM_OS_STR`, `OS_STRING_FREE`, `OS_STRING_CLEAR`, `OS_STRING_LEN`, `OS_STRING_CAPACITY`, `OS_STRING_IS_EMPTY`, `OS_STRING_RESERVE`, `OS_STRING_CLONE`
  - mutation/views: `OS_STRING_PUSH_STR`, `OS_STRING_PUSH_OS_STR`, `OS_STRING_PUSH_SLICE`, `OS_STRING_AS_OS_STR`, `OS_STRING_AS_SLICE`
  - conversions: `OS_STRING_TO_STRING_CHECKED`, `OS_STRING_INTO_STRING_CHECKED` (free source only on UTF-8 success)
  - OsStr helpers: `OS_STR_LEN`, `OS_STR_IS_EMPTY`, `OS_STR_TO_OS_STRING`, `OS_STR_TO_STR_CHECKED`
  - retained existing `OS_STR_FROM_BYTES*` / `OS_STR_AS_BYTES*` and `OS_STRING_FROM_VEC*` / `INTO_VEC*` aliases
- Semantics: Unix-only byte-buffer facade. Non-UTF-8 bytes are preserved in OsString/OsStr views; checked string conversions return `ok=0` instead of Rust `Result`/`OsString` error objects. It does not model Windows WTF-8/OsString, lossy display, or platform path encoding beyond raw bytes.
- Validation status:
  - Full-file `std_os_unix_ffi_macro_surface.sa`: pass (`3 passed`).
  - Focused owned-macros coverage included in that file: pass.
  - Full `zig build unit-framework --summary all`: pass (`6/6 steps succeeded; 5/5 tests passed`).

## Completed: 2026-07-12 collection literal arity (LIT1/LIT2/LIT3) batch

- Continued collection Rust API parity by adding fixed-arity collection literal helpers over existing insert/put constructors, requiring no new runtime/FFI surface.
- Added supportable macros:
  - `sa_std/hashmap.sa`: `MAP_LIT1`, `MAP_LIT2` (existing), `MAP_LIT3`
  - `sa_std/hashset.sa`: `SET_LIT1`, `SET_LIT2` (existing), `SET_LIT3`
  - `sa_std/btree_map.sa`: `BTREE_MAP_LIT1`, `BTREE_MAP_LIT2`, `BTREE_MAP_LIT3`
  - `sa_std/btree_set.sa`: `BTREE_SET_LIT1`, `BTREE_SET_LIT2` (existing), `BTREE_SET_LIT3`
- Semantics: each helper constructs a fresh collection then inserts 1/2/3 concrete entries via existing `MAP_PUT` / `SET_INSERT` / `BTREE_MAP_INSERT` / `BTREE_SET_INSERT` contracts. They do not model Rust `FromIterator` / array-literal sugar beyond fixed arity, generic key/value types, or fallible allocation reporting.
- Validation status:
  - Focused `std_hashmap_macro_surface.sa --filter 'literal arity'`: pass (`1 passed; 9 skipped`).
  - Focused `std_hashset_macro_surface.sa --filter 'literal arity'`: pass (`1 passed; 7 skipped`).
  - Focused `std_btree_macro_surface.sa --filter 'literal arity'`: pass (`1 passed; 9 skipped`).
  - Full `zig build unit-framework --summary all`: pass (`6/6 steps succeeded; 5/5 tests passed`).

## Completed: 2026-07-12 PathBuf owned path buffer macro surface batch

- Continued the parallel `path` Rust API parity audit by adding a concrete owned `PathBuf` facade over the existing `STRING_BUF` / `Vec<u8>` storage and the current POSIX `PATH_*` Slice helpers, requiring no new runtime/FFI surface.
- Added supportable `sa_std/path.sa` macros:
  - constructors: `PATH_BUF_NEW`, `PATH_BUF_DEFAULT`, `PATH_BUF_WITH_CAPACITY`, `PATH_BUF_TRY_WITH_CAPACITY`, `PATH_BUF_FROM_PATH`, `PATH_BUF_FROM_STR`
  - ownership/capacity: `PATH_BUF_FREE`, `PATH_BUF_CLEAR`, `PATH_BUF_LEN`, `PATH_BUF_CAPACITY`, `PATH_BUF_IS_EMPTY`, `PATH_BUF_RESERVE`, `PATH_BUF_CLONE`
  - views: `PATH_BUF_AS_PATH`, `PATH_BUF_AS_STR`
  - mutation: `PATH_BUF_PUSH` (delegates to `PATH_JOIN` then reloads owned bytes), `PATH_BUF_POP` (via `PATH_TRY_PARENT`), `PATH_BUF_SET_FILE_NAME`, `PATH_BUF_SET_EXTENSION`, `PATH_BUF_PUSH_TRAILING_SEPARATOR`
  - filesystem queries: `PATH_BUF_EXISTS`, `PATH_BUF_IS_FILE`, `PATH_BUF_IS_DIR`
- Semantics: `PathBuf` is a concrete owned UTF-8/byte path buffer, not Rust's platform `OsString`/`PathBuf` type. Absolute `push` replaces the buffer contents through `PATH_JOIN`. `pop` returns `ok=0` at roots/empty paths. Queries materialize temporary `PATH_*` Slice views and free them inside the helper. It does not model Windows prefixes, component iterators, or borrow-scoped path references.
- Validation status:
  - Source focused `std_path_macro_surface.sa --filter 'PathBuf owned'`: pass (`1 passed; 4 skipped`).
  - Full-file source focused `std_path_macro_surface.sa`: pass (`5 passed`).
  - Full `zig build unit-framework --summary all`: pass (`6/6 steps succeeded; 5/5 tests passed`).

## Completed: 2026-07-12 HashSet/BTreeSet entry aliases + HashMap/HashSet extra_capacity batch

- Continued collection Rust API parity by adding supportable entry-naming and capacity-remaining helpers over existing set/map primitives, requiring no new runtime/FFI surface.
- Added supportable macros:
  - `sa_std/hashset.sa`: `SET_ENTRY_GET_OR_INSERT`, `SET_OR_INSERT`, `SET_EXTRA_CAPACITY`
  - `sa_std/btree_set.sa`: `BTREE_SET_ENTRY_GET_OR_INSERT`, `BTREE_SET_OR_INSERT`
  - `sa_std/hashmap.sa`: `MAP_EXTRA_CAPACITY`
- Semantics: entry aliases are thin renames of existing `GET_OR_INSERT` contracts; `EXTRA_CAPACITY` is pure `capacity - len` subtraction. They do not model Rust entry objects, closure `or_insert_with`, generic defaults, or allocator-aware constructors.
- Validation status:
  - Focused hashset/hashmap/btree entry-or-capacity tests: pass.
  - Full-file hashset (`7 passed`), hashmap (`9 passed`), btree (`9 passed`) surfaces: pass.
  - Full `zig build unit-framework --summary all`: pass (`6/6 steps succeeded; 5/5 tests passed`).

## Completed: 2026-07-12 unit-framework panic ID uniqueness renumber

- Fixed pre-existing duplicate `panic(N)` IDs within individual unit-framework SA surface files so every panic code is unique inside its file.
- Files renumbered (duplicate first-seen IDs kept; later duplicates assigned free IDs above the file max): `feature_suite.sa`, `std_btree_macro_surface.sa`, `std_hashmap_macro_surface.sa`, `std_net_macro_surface.sa`, `std_net_unix_macro_surface.sa`, `std_num_macro_surface.sa`, `std_process_macro_surface.sa`, `std_slice_vec_macro_surface.sa`, `std_string_macro_surface.sa`, `std_vec_deque_macro_surface.sa`, `std_vec_macro_surface.sa`.
- Validation status:
  - Focused revalidation of renumbered surfaces: `std_vec_deque_macro_surface.sa` pass (`16 passed`), `std_vec_macro_surface.sa` pass (`44 passed`), plus the newly extended fs/binary_heap/hashmap/btree surfaces all pass.
  - Full `zig build unit-framework --summary all`: pass (`6/6 steps succeeded; 5/5 tests passed`).

## Completed: 2026-07-12 HashMap/BTreeMap entry and_modify/or_default aliases batch

- Continued the parallel map entry-API parity audit by adding concrete entry-style helpers over the existing try-insert / get-mut-ptr contracts for both `HashMap` and `BTreeMap`, requiring no new runtime/FFI surface.
- Added supportable `sa_std/hashmap.sa` macros:
  - `MAP_OR_INSERT` (thin alias of `MAP_ENTRY_OR_INSERT` / `MAP_TRY_INSERT`)
  - `MAP_ENTRY_OR_DEFAULT` (entry-or-insert with default null-pointer value `0`)
  - `MAP_ENTRY_AND_MODIFY` (if the key exists, overwrite the value slot through `sa_map_get_mut_ptr`; missing keys leave the map unchanged and return `ok=0`)
- Added supportable `sa_std/btree_map.sa` macros:
  - `BTREE_MAP_OR_INSERT` (thin alias of `BTREE_MAP_ENTRY_OR_INSERT`)
  - `BTREE_MAP_ENTRY_OR_DEFAULT` (entry-or-insert with default `u64` value `0`)
  - `BTREE_MAP_ENTRY_AND_MODIFY` (if the key exists, store the replacement `u64` through `sa_btree_map_get_mut_ptr`; missing keys return `ok=0`)
- Semantics: these are concrete entry-style lowerings, not Rust `OccupiedEntry` / `VacantEntry` objects. They do not model `or_insert_with` closures, generic defaults, scoped entry borrows, or full key/value ownership transfer variants that remain genuinely missing.
- Validation status:
  - Source focused hashmap `--filter 'entry and_modify'`: pass (`1 passed; 7 skipped`).
  - Full-file hashmap surface: pass (`8 passed; 0 failed; 0 skipped`).
  - Source focused btree `--filter 'entry and_modify'`: pass (`1 passed; 7 skipped`).
  - Full-file btree surface: pass (`8 passed; 0 failed; 0 skipped`).
  - Full `zig build unit-framework --summary all`: pass (`6/6 steps succeeded; 5/5 tests passed`).

## Completed: 2026-07-12 fs FileTimes object macro surface batch

- Continued the parallel `fs` Rust API parity audit by lowering a concrete `FileTimes` builder over the existing millisecond timestamp FFI (`sa_fs_set_times_ms` / metadata accessed+modified queries), requiring no new syscall surface.
- Added supportable `sa_std/fs.sa` macros:
  - `FS_FILE_TIMES_NEW` (initialize builder state as two propagating SSA `i64`/`u64` millisecond timestamps: accessed=0, modified=0)
  - `FS_FILE_TIMES_WITH_ACCESSED` / `FS_FILE_TIMES_WITH_MODIFIED` (functional updates of one timestamp while preserving the other)
  - `FS_FILE_TIMES_SET` (apply the final pair through the existing `FS_SET_TIMES_MS` lowering)
  - `FS_METADATA_FILE_TIMES` (extract `(accessed_ms, modified_ms)` from a metadata handle via the existing metadata time queries)
- Semantics: builder state is two propagating SSA values rather than a heap-allocated `FileTimes` object. `FS_FILE_TIMES_SET` adds no new FFI surface. It does not model Rust's `FileTimes` optional "leave unchanged" sentinel fields, nanosecond `SystemTime` objects, `set_times` on open `File` handles beyond the path-based helper, or platform-specific birth/creation time mutation.
- Validation status:
  - Source focused `std_fs_macro_surface.sa --filter 'FileTimes object'`: pass (`1 passed; 13 skipped`).
  - Full-file source focused `std_fs_macro_surface.sa`: pass (`14 passed; 0 failed; 0 skipped`).
  - Full `zig build unit-framework --summary all`: pass (`6/6 steps succeeded; 5/5 tests passed`).

## Completed: 2026-07-12 fs Permissions object macro surface batch

- Continued the parallel `fs` Rust API parity audit by completing a concrete `Permissions` object model over the existing POSIX mode slot (`SaFsPermissions`) and `sa_fs_set_permissions` / metadata mode FFI, requiring no new syscall surface.
- Added supportable `sa_std/fs.sal` constants:
  - `SA_FS_PERM_WRITE_BITS = 146` (`0222`) and `SA_FS_PERM_OWNER_WRITE = 128` (`0200`) for readonly checks/mutations.
- Added supportable `sa_std/fs.sa` macros:
  - `FS_PERMISSIONS_NEW` (zero-initialize a `SaFsPermissions` slot)
  - `FS_METADATA_PERMISSIONS` (copy `sa_fs_metadata_st_mode` into a `Permissions` slot)
  - `FS_PERMISSIONS_READONLY` (true when no POSIX write bits remain)
  - `FS_PERMISSIONS_SET_READONLY` (branchless clear-all-write-bits / set-owner-write mutation; labels avoided so repeated expansion does not collide)
  - `FS_SET_PERMISSIONS_OBJ` (apply a `Permissions` slot via the existing `sa_fs_set_permissions` FFI)
- Semantics: `Permissions` is a 4-byte mode object, not a Rust trait object. `readonly` mirrors the common Unix Rust interpretation of "no write bits". `set_readonly(true)` clears `0222`; `set_readonly(false)` ORs owner-write `0200`. Metadata-derived modes include file-type bits, so surface tests mask with `0777` (`511`) when comparing permission bits. It does not model Windows ACL permissions, portable `PermissionsExt` trait objects, or owned builder move semantics.
- Validation status:
  - Source focused `std_fs_macro_surface.sa --filter 'Permissions object'`: pass (`1 passed; 12 skipped`).
  - Full-file source focused `std_fs_macro_surface.sa`: pass (`13 passed; 0 failed; 0 skipped`).
  - Full `zig build unit-framework --summary all`: pass (`6/6 steps succeeded; 5/5 tests passed`).

## Completed: 2026-07-12 BinaryHeap u64/try_peek/pop/extra_capacity aliases batch

- Continued the parallel `BinaryHeap` Rust API parity audit by adding concrete u64-named and try/non-try value-form aliases over the existing push/peek/pop/capacity+len primitives, requiring no new syscall/FFI surface.
- Added supportable `sa_std/binary_heap.sa` macros:
  - `BINARY_HEAP_PUSH_U64` / `BINARY_HEAP_PEEK_U64` (thin aliases of `BINARY_HEAP_PUSH` / `BINARY_HEAP_PEEK`)
  - `BINARY_HEAP_TRY_PEEK` / `BINARY_HEAP_TRY_PEEK_U64` (fallible value view returning `(ok, value)`; empty heaps yield `ok=0,value=0`, non-empty heaps yield `ok=1` plus the current root without removing it)
  - `BINARY_HEAP_POP` / `BINARY_HEAP_POP_U64` (value-only wrappers around `sa_binary_heap_try_pop`; callers that need the empty-heap failure path keep using `BINARY_HEAP_TRY_POP`)
  - `BINARY_HEAP_EXTRA_CAPACITY` (returns `capacity - len` as a pure subtraction, mirroring Rust `BinaryHeap`/`VecDeque::extra_capacity` naming)
- Semantics: the `_U64` aliases preserve the existing concrete `u64` max-heap ABI and only expose explicit typed naming parity. `TRY_PEEK` is a non-destructive fallible value view, not Rust's scoped `PeekMut` guard. `POP` ignores the try-ok bit and returns the loaded slot value (empty-heap callers should use `TRY_POP`). `EXTRA_CAPACITY` never allocates and reports the full initial capacity for a fresh empty heap (`BinaryHeap_INITIAL_CAP=8`). None of these claim generic ordering, iterator/drain adapters, scoped mutable peek guards, or true allocator-failure reporting that remain genuinely missing.
- Validation notes / fixes in this batch:
  - Illegal `#` comment lines between macros in `sa_std/binary_heap.sa` were rewritten as `//` comments (the flattener rejects `#` lines as `.unknown line kind` / ForbiddenSyntax).
  - `BINARY_HEAP_POP` must not `!` its `stack_alloc` slot (StackEscape); only the temporary ok register is consumed.
  - Surface test uses `BinaryHeap_INITIAL_CAP` (from `binary_heap.sal`), not a non-existent `BINARY_HEAP_INITIAL_CAP` token, and avoids `!heap` after `BINARY_HEAP_FREE` (UseAfterMove).
- Validation status:
  - Source focused `std_binary_heap_macro_surface.sa --filter 'u64/try_peek/pop/extra_capacity'`: pass (`1 passed; 6 skipped`).
  - Full-file source focused `std_binary_heap_macro_surface.sa`: pass (`7 passed; 0 failed; 0 skipped`).
  - Full `zig build unit-framework --summary all`: pass (`6/6 steps succeeded; 5/5 tests passed`).

## Completed: 2026-07-12 fs OpenOptions builder custom-flags members macro surface batch

- Continued the parallel `fs` Rust API parity audit by lowering the per-bit `custom_flags` members of Rust's `std::fs::OpenOptions` builder onto the existing `FS_OPEN_OPTIONS` FFI lowering (via the already-landed `FS_OPEN_OPTIONS_BUILDER_WITH_CUSTOM_FLAGS` slot), requiring no new syscall/FFI surface.
- Added supportable `sa_std/fs.sa` macros:
  - `FS_OPEN_OPTIONS_BUILDER_WITH_SYNC` / `_WITH_DSYNC` / `_WITH_NONBLOCK` / `_WITH_NOFOLLOW` / `_WITH_DIRECT` / `_WITH_DIRECTORY` / `_WITH_CLOEXEC` (each takes the current `(flags, mode, custom)` triple and a `%flag`; when `%flag != 0` it ORs the corresponding `SA_FS_CUSTOM_SYNC` / `SA_FS_CUSTOM_DSYNC` / `SA_FS_CUSTOM_NONBLOCK` / `SA_FS_CUSTOM_NOFOLLOW` / `SA_FS_CUSTOM_DIRECT` / `SA_FS_CUSTOM_DIRECTORY` / `SA_FS_CUSTOM_CLOEXEC` bit into the builder's `custom_flags` slot, and when `%flag == 0` it carries all three state values through unchanged — matching Rust's `.x(true)` set-the-bit idiom; `.x(false)` clear-the-bit is intentionally not lowered).
- Semantics: builder state remains three propagating SSA `u64` register values rather than a heap-allocated builder object; each `WITH_*` produces an immutable updated triple (functional style). The seven new macros only OR individual `SA_FS_CUSTOM_*` bits into `custom_flags`, so they add no new syscall/FFI surface. Note that `SA_FS_CUSTOM_SYNC = 1052672 = 0b100000001000000000000` is a synthetic flag that has the `SA_FS_CUSTOM_DSYNC = 4096` bit as a strict subset (the synchronised-write semantics on Linux overlap with `O_DSYNC`), so `SYNC | DSYNC == 1052672` rather than `1056768`; the surface test asserts the OR-accumulated values (`1052672`, `1054720`, `1185792`, `1202176`, `1267712`, `1792000`) rather than simple sums. They do not model Rust's `create_new` (`O_CREAT|O_EXCL`; `O_EXCL` is not exposed by the `SA_FS_CUSTOM_*` table), `set_permissions`-equivalent builder method, Windows ACL fields, or owned builder move/build value semantics.
- Validation status:
  - Source focused `std_fs_macro_surface.sa --filter 'OpenOptions builder custom-flags members'`: pass (`1 passed; 11 skipped`).
  - Full-file source `zig build unit-framework --summary all`: pass (`6/6 steps succeeded; 5/5 tests passed`), confirming the new `@test` block (panic 952) does not disturb the twelve pre-existing sibling `@test` blocks and that the surface test passes alongside the rest of the unit-framework suite.
  - A prior intermediate version of this batch used `#`-comment lines inside `sa_std/fs.sa` and additive `SA_FS_CUSTOM_SYNC + ...` operands inside the test; both are unsupported by the SA flattener (comments between macros are rejected as `.unknown line kind`, and `+`-expressions are parsed as `[UnknownRegister]` operands), and both were removed before this validation entry.
- This batch also fixed two latent issues in `tests/unit_framework/std_fs_macro_surface.sa`: the prior `panic` IDs were renumbered 940..952 so every panic code in the file is unique (the old numbering reused 943/944/945 across distinct tests), and the regression surfaced by the new `@test` block exercising the `WITH_SYNC`/`WITH_DSYNC` path was corrected to use OR-accumulated expectations rather than simple sums.

## Completed: 2026-07-12 fs OpenOptions builder macro surface batch

- Continued the parallel `fs` Rust API parity audit by lowering Rust's `std::fs::OpenOptions` builder pattern onto the existing `FS_OPEN_OPTIONS` FFI lowering, requiring no new syscall/FFI surface.
- Added supportable `sa_std/fs.sa` macros:
  - `FS_OPEN_OPTIONS_BUILDER_NEW` (initialize builder state as three propagating SSA `u64`s: `flags=0`, `create_mode=SA_FS_OPEN_MODE_DEFAULT`, `custom_flags=0`, matching Rust's `OpenOptions::new()` defaults where all `bool` fields are `false`)
  - `FS_OPEN_OPTIONS_BUILDER_WITH_READ` / `_WRITE` / `_APPEND` / `_CREATE` / `_TRUNCATE` (each takes the current `(flags, mode, custom)` triple and a flag, normalizes any nonzero flag to set-bit OR, leaving the corresponding `SA_FS_OPEN_*` bit untouched when the supplied flag is zero — matching Rust's `.x(true)` set-the-bit idiom; `.x(false)` clear-the-bit is intentionally not lowered)
  - `FS_OPEN_OPTIONS_BUILDER_WITH_MODE` / `_WITH_CUSTOM_FLAGS` (set the full POSIX `create_mode` / `custom_flags` field while preserving the other two state values)
  - `FS_OPEN_OPTIONS_BUILDER_OPEN` (delegates to the existing `FS_OPEN_OPTIONS` FFI, producing `(status, file)`)
- Semantics: builder state is three propagating SSA `u64` register values rather than a heap-allocated builder object, each `WITH_*` produces an immutable updated triple (functional style). `FS_OPEN_OPTIONS_BUILDER_OPEN` adds no new syscall/FFI surface. It does not model Rust's `create_new` (`O_CREAT|O_EXCL`) — the `O_EXCL` bit is not exposed by the `SA_FS_CUSTOM_*` table — cross-platform `truncate`/`append` edges on read-only opens, the `set_permissions`-equivalent builder method, Windows ACL fields, or owned builder move/build value semantics.
- Validation status:
  - Source focused `std_fs_macro_surface.sa --filter 'OpenOptions'`: pass (`1 passed; 9 skipped`).
  - Full-file source focused `std_fs_macro_surface.sa`: pass (`10 passed; 0 failed; 0 skipped`), confirming the new `@test` block (panic 947) does not disturb the nine pre-existing sibling `@test` blocks.
  - Install sync via installed-std copy of `fs.sa`: pass.
  - Installed-state focused `std_fs_macro_surface.sa --filter 'OpenOptions'`: pass (`1 passed; 9 skipped`).

## Completed: 2026-07-12 fs DirBuilder macro surface batch

- Continued the parallel `fs` Rust API parity audit by lowering Rust's `std::fs::DirBuilder` builder pattern onto the existing non-recursive `FS_CREATE_DIR_MODE` and recursive `FS_CREATE_DIR_ALL_MODE` FFI helpers, requiring no new syscall/FFI surface.
- Added supportable `sa_std/fs.sa` macros:
  - `FS_DIR_BUILDER_NEW` (initialize builder state as two propagating SSA `u64`s: `recursive=false (0)` and `mode=0o755=493`, Rust's default)
  - `FS_DIR_BUILDER_WITH_RECURSIVE` (takes the current `(recursive, mode)` pair and a flag, normalizes any nonzero flag to `1`, preserves the `mode`; returns an updated pair)
  - `FS_DIR_BUILDER_WITH_MODE` (takes the current pair and a new `mode`, preserves the `recursive` flag; returns an updated pair)
  - `FS_DIR_BUILDER_CREATE` (takes the final `(recursive, mode)` pair and a path; branches on the `recursive` flag to dispatch the existing `FS_CREATE_DIR_MODE` (non-recursive) or `FS_CREATE_DIR_ALL_MODE` (recursive) lowering)
- Semantics: the builder state is two propagating SSA `u64` register values rather than a heap-allocated builder object, and each `WITH_*` produces an immutable updated pair (functional style). `FS_DIR_BUILDER_CREATE` adds no new FFI/syscall surface. It does not model Rust's owned `DirBuilder` value/move semantics, the `Permissions`/`metadata`-style builder methods on the returned handle, Windows ACL permission layers, or `create`-variants that return the directory handle.
- Validation status:
  - Source focused `std_fs_macro_surface.sa --filter 'DirBuilder'`: pass (`1 passed; 8 skipped`).
  - Full-file source focused `std_fs_macro_surface.sa`: pass (`9 passed; 0 failed; 0 skipped`), confirming the new `@test` block (panic 946) does not disturb the eight pre-existing sibling `@test` blocks.
  - Install sync via installed-std copy of `fs.sa`: pass.
  - Installed-state focused `std_fs_macro_surface.sa --filter 'DirBuilder'`: pass (`1 passed; 8 skipped`).

## Completed: 2026-07-12 VecDeque extend_chars u64 aliases batch

- Continued the parallel `VecDeque` Rust API parity audit by adding non-allocating `extend_chars` aliases that treat a `Slice<u64>`'s elements as UTF-32 / Unicode scalar-value codepoints, mirroring the existing Vec `_extend_chars` naming. The VecDeque is u64-typed, so a char codepoint is just the slice element as a `u64`.
- Added supportable, non-allocating helpers (thin aliases reusing the existing `VEC_DEQUE_TRY_EXTEND_FROM_SLICE_U64` capacity-checked, no-auto-grow family):
  - `VEC_DEQUE_TRY_EXTEND_CHARS_U64` (extend the back of the deque with the codepoint slice; behaves like `VEC_DEQUE_TRY_EXTEND_FROM_SLICE_U64`: pre-checks `len + src_len <= cap`, returns `ok=0` with no mutation on insufficient room, otherwise loops `src_len` times calling `sa_vec_deque_push_back` with each codepoint)
  - `VEC_DEQUE_EXTEND_CHARS_U64` (ok-ignoring alias)
- Semantics: same as `VEC_DEQUE_TRY_EXTEND_FROM_SLICE_U64` but named for the char-codepoint intent. It does not perform Rust `char`-validation (codepoints beyond U+10FFFF or surrogate codepoints are passed through as `u64`), does not claim Rust allocator growth, the lazy `extend` iterator, generic element support, scoped Rust references, or allocator-aware `try_extend*` strict-failure variants that remain genuinely missing for `VecDeque`.
- Validation status:
  - Source focused minimal harness `/tmp/vdeec_min.sa`: pass (`1 passed`), exercising a 6-cap deque extended by chars `[65,66,67]` then `[68,69]` to len 5, and a third extend attempt that returns `ok=0` (out of room) with no mutation.
  - Source focused `std_vec_deque_macro_surface.sa --filter 'extend_chars u64 helpers'`: pass (`1 passed; 15 skipped`).
  - Install sync via installed-std copy of `vec_deque.sa`: pass.
  - Installed-state focused min harness: pass (`1 passed`).

## Completed: 2026-07-12 VecDeque insert_from_slice_n within capacity batch

- Continued the parallel `VecDeque` Rust API parity audit by adding a non-allocating repeated-slice-insert within-capacity lowering, mirroring the existing Vec `insert_from_slice_n within capacity` lowerings.
- Added supportable, non-allocating helpers:
  - `VEC_DEQUE_TRY_INSERT_FROM_SLICE_N_WITHIN_CAPACITY` / `VEC_DEQUE_TRY_INSERT_FROM_SLICE_N_WITHIN_CAPACITY_U64` (insert a `Slice<u64>` of `src_len` elements `count` times in a row at a logical index: pre-checks `index <= len` and `len + src_len*count <= cap`, then loops `count` times; each outer iteration inserts one whole copy of the src slice at the advancing index `index + i*src_len` via `VEC_DEQUE_TRY_INSERT_FROM_SLICE_WITHIN_CAPACITY`)
  - `VEC_DEQUE_INSERT_FROM_SLICE_N_WITHIN_CAPACITY` / `VEC_DEQUE_INSERT_FROM_SLICE_N_WITHIN_CAPACITY_U64` (ok-ignoring aliases)
- Semantics: bounds and capacity are validated up front with `ule index <= len` and `ule new_len <= cap` (where `new_len = len + src_len*count`); on out-of-bounds index or insufficient room, returns `ok=0` with no mutation, otherwise loops `count` times inserting a whole copy of the src slice at the advancing index. `count=0` succeeds as a no-op, and `src_len=0` also succeeds as a no-op (each inner `insert_from_slice` hits its empty-slice path). Each iteration's inner `VEC_DEQUE_TRY_INSERT_FROM_SLICE_WITHIN_CAPACITY` can never run out of room because the full `len + src_len*count` capacity was validated up front. It does not claim Rust allocator growth, generic element support, scoped Rust references, or allocator-aware `try_insert*` strict-failure variants that remain genuinely missing for `VecDeque`.
- Validation status:
  - Source focused minimal harness `/tmp/vdeifsnwc_min.sa`: pass (`1 passed`), exercising a 2-element slice inserted twice at index 1 that fills an 8-cap deque to `[1,10,20,10,20,2,3,4]`, a `count=0` no-op, an empty-slice no-op over `count=3`, an out-of-capacity failure, and an out-of-bounds index failure.
  - Source focused `std_vec_deque_macro_surface.sa --filter 'insert_from_slice_n within capacity helpers'`: pass (`1 passed; 14 skipped`).
  - Install sync via installed-std copy of `vec_deque.sa`: pass.
  - Installed-state focused min harness: pass (`1 passed`).

## Completed: 2026-07-12 VecDeque insert_from_slice within capacity batch

- Continued the parallel `VecDeque` Rust API parity audit by adding a non-allocating slice-insert within-capacity lowering, mirroring the existing Vec `insert_from_slice within capacity` lowerings.
- Added supportable, non-allocating helpers:
  - `VEC_DEQUE_TRY_INSERT_FROM_SLICE_WITHIN_CAPACITY` / `VEC_DEQUE_TRY_INSERT_FROM_SLICE_WITHIN_CAPACITY_U64` (insert a `Slice<u64>` of `src_len` elements at a logical index: pre-checks `index <= len` and `len + src_len <= cap`, then loops `src_len` times reading element `i` from the src slice and calling `VEC_DEQUE_TRY_INSERT_WITHIN_CAPACITY` at the advancing index `index + i`)
  - `VEC_DEQUE_INSERT_FROM_SLICE_WITHIN_CAPACITY` / `VEC_DEQUE_INSERT_FROM_SLICE_WITHIN_CAPACITY_U64` (ok-ignoring aliases)
- Semantics: bounds and capacity are validated up front with `ule index <= len` and `ule new_len <= cap`; on out-of-bounds index or insufficient room, returns `ok=0` with no mutation, otherwise loops `src_len` times inserting each slice element at the advancing index. An empty slice succeeds as a no-op. Each iteration's inner `VEC_DEQUE_TRY_INSERT_WITHIN_CAPACITY` can never run out of room because capacity was validated up front. It does not claim Rust allocator growth, generic element support, repeated-slice-insert variants, scoped Rust references, or allocator-aware `try_insert*` strict-failure variants that remain genuinely missing for `VecDeque`.
- Validation status:
  - Source focused minimal harness `/tmp/vdeifswc_min.sa`: pass (`1 passed`), exercising a 3-element slice mid-insert that fills to capacity, an empty-slice no-op, an out-of-capacity failure, and an out-of-bounds index failure.
  - Source focused `std_vec_deque_macro_surface.sa --filter 'insert_from_slice within capacity helpers'`: pass (`1 passed; 13 skipped`).
  - Install sync via installed-std copy of `vec_deque.sa`: pass.
  - Installed-state focused min harness: pass (`1 passed`).

## Completed: 2026-07-12 VecDeque insert_n within capacity batch

- Continued the parallel `VecDeque` Rust API parity audit by adding a non-allocating repeated-value `VecDeque::insert` within-capacity lowering, mirroring the existing Vec `insert_n within capacity` lowerings.
- Added supportable, non-allocating helpers:
  - `VEC_DEQUE_TRY_INSERT_N_WITHIN_CAPACITY` / `VEC_DEQUE_TRY_INSERT_N_WITHIN_CAPACITY_U64` (repeatedly insert a single `u64` value at a logical index: pre-checks `index <= len` and `len + count <= cap`, then loops `count` times calling `VEC_DEQUE_TRY_INSERT_WITHIN_CAPACITY` at the advancing index `index + i`)
  - `VEC_DEQUE_INSERT_N_WITHIN_CAPACITY` / `VEC_DEQUE_INSERT_N_WITHIN_CAPACITY_U64` (ok-ignoring aliases)
- Semantics: bounds and capacity are validated up front with `ule index <= len` and `ule new_len <= cap`; on out-of-bounds index or insufficient room, returns `ok=0` with no mutation, otherwise loops `count` times inserting the same `u64` value at the advancing index. `count=0` succeeds as a no-op. Each iteration's inner `VEC_DEQUE_TRY_INSERT_WITHIN_CAPACITY` can never run out of room because capacity was validated up front. It does not claim Rust allocator growth, generic element support, slice-insert variants, scoped Rust references, or allocator-aware `try_insert*` strict-failure variants that remain genuinely missing for `VecDeque`.
- Validation status:
  - Source focused minimal harness `/tmp/vdeinwc_min.sa`: pass (`1 passed`), exercising a 3-element repeated insert that fills to capacity, a `count=0` no-op, an out-of-capacity failure, and an out-of-bounds index failure.
  - Source focused `std_vec_deque_macro_surface.sa --filter 'insert_n within capacity helpers'`: pass (`1 passed; 12 skipped`).
  - Install sync via installed-std copy of `vec_deque.sa`: pass.
  - Installed-state focused min harness: pass (`1 passed`).

## Completed: 2026-07-12 VecDeque insert within capacity batch

- Continued the parallel `VecDeque` Rust API parity audit by adding a non-allocating single-element `VecDeque::insert` within-capacity lowering.
- Added supportable, non-allocating helpers:
  - `VEC_DEQUE_TRY_INSERT_WITHIN_CAPACITY` / `VEC_DEQUE_TRY_INSERT_WITHIN_CAPACITY_U64` (non-allocating single-element insert at a byte/logical index: pre-checks `index <= len` and `len + 1 <= cap`, returning `ok=0` with no mutation on out-of-bounds index or no room; on success delegates to `sa_vec_deque_try_insert` whose internal `reserve(1)` becomes an integer no-op because capacity was already validated)
  - `VEC_DEQUE_INSERT_WITHIN_CAPACITY` / `VEC_DEQUE_INSERT_WITHIN_CAPACITY_U64` (ok-ignoring aliases)
- Semantics: bounds and capacity are validated up front with `ule index <= len` and `ule new_len <= cap`; on insufficient room or out-of-bounds index, returns `ok=0` with no mutation. The grow path delegates to `sa_vec_deque_try_insert` which performs a ring-buffer force-contiguous shift and slot store after its `reserve(1)` call (the reserve is an integer no-op because the deque already had a room slot). It does not claim Rust allocator growth, generic element support, slice-insert variants, scoped Rust references, or allocator-aware `try_insert*` strict-failure variants that remain genuinely missing for `VecDeque`.
- Validation status:
  - Source focused minimal harness `/tmp/vdeiwc_min.sa`: pass (`1 passed`), exercising a mid-deque insert, an end-of-deque insert that fills to capacity, an out-of-capacity failure, and an out-of-bounds index failure.
  - Source focused `std_vec_deque_macro_surface.sa --filter 'insert within capacity helpers'`: pass (`1 passed; 11 skipped`).
  - Install sync via installed-std copy of `vec_deque.sa`: pass.
  - Installed-state focused min harness: pass (`1 passed`).

## Completed: 2026-07-12 VecDeque push_n within capacity batch

- Continued the parallel `VecDeque` Rust API parity audit by adding concrete repeated push-within-capacity lowerings, mirroring the existing Vec `push_n within capacity` lowerings.
- Added supportable, non-allocating helpers:
  - `VEC_DEQUE_TRY_PUSH_BACK_N_WITHIN_CAPACITY_U64` / `VEC_DEQUE_PUSH_BACK_N_WITHIN_CAPACITY_U64` (repeatedly push a single `u64` value to the back up to `count` times when `len + count <= cap`)
  - `VEC_DEQUE_TRY_PUSH_FRONT_N_WITHIN_CAPACITY_U64` / `VEC_DEQUE_PUSH_FRONT_N_WITHIN_CAPACITY_U64` (same for the front; after N front pushes the head wraps correctly around the ring buffer)
- Semantics: capacity-checked via `ule new_len <= cap`; on insufficient room return `ok=0` with no mutation, otherwise loop `count` times calling `sa_vec_deque_push_back` / `sa_vec_deque_push_front` (which can never hit the runtime auto-grow branch because capacity was validated up front). `count=0` succeeds as a no-op. Failures return `ok=0` with no mutation. Does not claim Rust allocator growth, generic element support, scoped Rust references, or the lazy iterator allocator-aware variants that remain genuinely missing for `VecDeque`.
- Validation status:
  - Source focused minimal harness `/tmp/vdepbnwc_min.sa`: pass (`1 passed`), exercising back-grow, front-grow with ring-wrap ordering, out-of-capacity failure, and `count=0` no-op success.
  - Source focused `std_vec_deque_macro_surface.sa --filter 'push_back_n and push_front_n within capacity helpers'`: pass (`1 passed; 10 skipped`).
  - Install sync via installed-std copy of `vec_deque.sa`: pass.
  - Installed-state focused min harness: pass (`1 passed`).

## Completed: 2026-07-12 VecDeque try_extend_from_slice_n within capacity batch

- Continued the parallel `VecDeque` Rust API parity audit by adding a concrete repeated `VecDeque::extend`-shaped, capacity-preserving helper that appends a `Slice<u64>` `count` times without Rust-style allocator growth.
- Added supportable, non-allocating helpers:
  - `VEC_DEQUE_TRY_EXTEND_FROM_SLICE_N_WITHIN_CAPACITY_U64` (pre-check `src_len * count + len <= cap`, then loop `count` times calling `VEC_DEQUE_TRY_EXTEND_FROM_SLICE_U64`); on insufficient room or zero `count`, returns `ok=1` only when pre-check holds and acts as a no-op success for `count=0` (zero src_len or zero count succeeds without mutation)
  - `VEC_DEQUE_EXTEND_FROM_SLICE_N_WITHIN_CAPACITY_U64` (ok-ignoring alias)
- Semantics: total = `mul src_len count`; capacity-checked with plain `add`/`ule` consistent with the existing Vec `extend_from_slice_n` within-capacity lowerings; the grow path reuses `sa_vec_deque_push_back` per element, which can never trigger the runtime auto-grow branch because capacity was validated up front. Failures return `ok=0` with no mutation. Does not claim Rust allocator growth, generic element support, scoped Rust references, lazy `extend` iterator semantics, allocator-aware `try_extend*` failures, or the lazy `splice` / drain-range iterator semantics that remain genuinely missing for `VecDeque`.
- Validation status:
  - Source focused minimal harness `/tmp/vdeefsnwc_min.sa`: pass (`1 passed`), including a `count=0` no-op success path and an out-of-capacity failure path.
  - Source focused `std_vec_deque_macro_surface.sa --filter 'try_extend_from_slice_n within capacity helpers'`: pass (`1 passed; 9 skipped`).
  - Install sync via installed-std copy of `vec_deque.sa`: pass.
  - Installed-state focused min harness: pass (`1 passed`).

## Completed: 2026-07-12 VecDeque try_extend_from_slice within capacity batch

- Continued the parallel `VecDeque` Rust API parity audit by adding a concrete `VecDeque::extend_append_slice`-shaped, capacity-preserving extend from a `Slice<u64>`.
- Added supportable, non-allocating helpers:
  - `VEC_DEQUE_TRY_EXTEND_FROM_SLICE_U64` (Rust `VecDeque::extend` concrete within-capacity form: pre-checks `len + src_len <= cap`; on success appends each element via `sa_vec_deque_push_back`; on insufficient room returns `ok=0` with no mutation)
  - `VEC_DEQUE_EXTEND_FROM_SLICE_U64` / `VEC_DEQUE_EXTEND_FROM_SLICE` (ok-ignoring aliases)
- Semantics: total length is computed via plain `add` (consistent with the existing Vec capacity-check pattern), capacity checked via `ule total <= cap`, grow path appends via `sa_vec_deque_push_back` (which can never hit the runtime auto-grow branch because capacity was already validated). Zero source length succeeds as a no-op (`len <= cap`). They do not claim Rust allocator growth, generic element support, scoped Rust references, lazy `extend` iterator semantics, allocator-aware `try_extend*` failures, or the lazy `splice` / drain-range iterator semantics that remain genuinely missing for `VecDeque`.
- Validation status:
  - Source focused minimal harness `/tmp/vdeefswc_min.sa`: pass (`1 passed`), including an out-of-capacity failure assertion.
  - Source focused `std_vec_deque_macro_surface.sa --filter 'try_extend_from_slice within capacity helpers'`: pass (`1 passed; 8 skipped`).
  - Install sync via installed-std copy of `vec_deque.sa`: pass.
  - Installed-state focused min harness: pass (`1 passed`).

## Completed: 2026-07-12 VecDeque try_resize within capacity batch

- Continued the parallel `VecDeque` Rust API parity audit by adding non-reallocating `VecDeque::resize` / `resize_with` within-capacity lowerings to `sa_std/vec_deque.sa`.
- Added supportable, non-allocating helpers:
  - `VEC_DEQUE_TRY_RESIZE_WITHIN_CAPACITY` / `VEC_DEQUE_TRY_RESIZE_WITHIN_CAPACITY_U64` (Rust `VecDeque::resize` non-reallocating form: shrink via `truncate`, grow only when `new_len <= cap`, else `ok=0` no mutation)
  - `VEC_DEQUE_RESIZE_WITHIN_CAPACITY` / `VEC_DEQUE_RESIZE_WITHIN_CAPACITY_U64` (ok-ignoring aliases)
  - `VEC_DEQUE_TRY_RESIZE_WITH_WITHIN_CAPACITY` / `VEC_DEQUE_TRY_RESIZE_WITH_WITHIN_CAPACITY_U64` (Rust `VecDeque::resize_with` non-reallocating form; `() -> u64` generator invoked per added slot, `ok=0` on insufficient capacity)
  - `VEC_DEQUE_RESIZE_WITH_WITHIN_CAPACITY` / `VEC_DEQUE_RESIZE_WITH_WITHIN_CAPACITY_U64` (ok-ignoring aliases)
- Semantics: when `new_len <= len` shrink via the existing `sa_vec_deque_truncate` ABI (always `ok=1`); when `new_len > len` pre-check `new_len <= cap` and, on failure, return `ok=0` without mutation, otherwise grow by `push_back` (fixed value or freshly generated value). Grow path reuses `sa_vec_deque_push_back`, which can never hit the runtime auto-grow branch since capacity was already validated. No Rust allocator growth is claimed; allocator-aware `try_resize*` strict-failure variants, generic element support, scoped Rust references, and lazy `splice` / drain-range iterator semantics remain genuinely missing for `VecDeque`.
- Validation status:
  - Source focused minimal harness `/tmp/vdewc_min.sa`: pass (`1 passed`).
  - Source focused `std_vec_deque_macro_surface.sa --filter 'try_resize within capacity helpers'`: pass (`1 passed; 7 skipped`).
  - Install sync via installed-std copy of `vec_deque.sa`: pass.
  - Installed-state focused min harness: pass (`1 passed`).

## Completed: 2026-07-12 VecDeque resize / resize_with batch

- Continued the parallel `VecDeque` Rust API parity audit by adding concrete `VecDeque::resize` / `resize_with` eager lowerings to `sa_std/vec_deque.sa`.
- Added supportable helpers:
  - `VEC_DEQUE_RESIZE` / `VEC_DEQUE_RESIZE_U64` (Rust `VecDeque::resize(new_len, value)` lowering using existing `push_back` for growth and `truncate` for shrink)
  - `VEC_DEQUE_RESIZE_WITH` / `VEC_DEQUE_RESIZE_WITH_U64` (Rust `VecDeque::resize_with(new_len, generator)` lowering; the `() -> u64` generator callback is invoked per added slot)
- Semantics: `new_len <= len` shrinks via the existing truncate ABI; `new_len > len` grows by repeatedly calling `push_back` (with the value or a freshly generated value) until `len` reaches `new_len`, relying on the existing runtime auto-grow path for ring-buffer growth. The macros return an explicit `ok=1` status (no allocation failure path is modelled here; runtime `push_back` traps on OOM). They do not claim generic element support, scoped Rust references, the lazy `splice` / drain-range iterator semantics, or allocator-aware `try_resize*` variants that remain genuinely missing.
- Validation status:
  - Source focused minimal harness `/tmp/vderesize_min.sa`: pass (`1 passed`).
  - Source focused `std_vec_deque_macro_surface.sa --filter 'resize and resize_with helpers'`: pass (`1 passed; 6 skipped`).
  - Install sync via installed-std copy of `vec_deque.sa`: pass.
  - Installed-state focused min harness: pass (`1 passed`).

## Completed: 2026-07-12 VecDeque u64 view aliases + extra_capacity batch

- Continued the broader `sa_std` Rust API parity audit by adding explicit `u64`-named view aliases and the Rust 1.87 `VecDeque::extra_capacity` helper to `sa_std/vec_deque.sa`.
- Added supportable, non-allocating helpers:
  - `VEC_DEQUE_GET_U64`, `VEC_DEQUE_FRONT_U64`, `VEC_DEQUE_TRY_FRONT_U64`, `VEC_DEQUE_BACK_U64`, `VEC_DEQUE_TRY_BACK_U64` (Rust-named `u64` view aliases over the existing fallible/value front/back/get ABI)
  - `VEC_DEQUE_EXTRA_CAPACITY` (returns `capacity - len`, mirroring Rust's `VecDeque::extra_capacity`)
- Semantics: the `_U64` aliases preserve the existing `(ok, value)` and value-only contract of their non-`_U64` counterparts and only expose explicit `u64`-typed naming parity; `EXTRA_CAPACITY` is a pure `sub` of capacity minus length, never allocates, and reports zero for a full or empty deque. None of these claim generic element support, scoped Rust references, or iterator/`splice`/`drain`-range semantics that remain genuinely missing.
- Validation status:
  - Source focused minimal harness `/tmp/vdeu64_min.sa`: pass (`1 passed`).
  - Source focused `std_vec_deque_macro_surface.sa --filter 'u64 view aliases and extra capacity'`: pass (`1 passed; 5 skipped`).
  - Install sync via installed-std copy of `vec_deque.sa`: pass.
  - Installed-state focused min harness: pass (`1 passed`).

## Completed: 2026-07-12 Vec insert_from_slice_n within capacity batch

- Continued the `StringBuf` / `Vec` Rust API parity audit with String/Vec still treated as the active priority.
- Finding remains: current SA facades are broad but still not complete Rust API coverage.
- Added supportable capacity-preserving helper:
  - `VEC_TRY_INSERT_FROM_SLICE_N_WITHIN_CAPACITY` / `VEC_INSERT_FROM_SLICE_N_WITHIN_CAPACITY`
  - `VEC_TRY_INSERT_FROM_SLICE_N_WITHIN_CAPACITY_U64` / `VEC_INSERT_FROM_SLICE_N_WITHIN_CAPACITY_U64`
- Semantics: validate `index <= len` and remaining capacity for `src_len * count` first, then insert the same slice `count` times at successive positions starting at `index`. Zero source slices or zero counts succeed as no-ops; out-of-bounds indexes or insufficient room return `ok=0` with no mutation. Does not claim Rust allocator growth or partial insert.
- Validation status:
  - Source focused minimal harness `/tmp/ifsnwc_min.sa`: pass (`1 passed`).
  - Source focused `std_vec_macro_surface.sa --filter "insert_from_slice_n within capacity aliases"`: pass (`1 passed; 43 skipped`).
  - Install sync via installed-std copy of `vec.sa`: pass.
  - Installed-state focused min harness: pass (`1 passed`).

## Completed: 2026-07-12 Vec insert_from_slice within capacity batch

- Continued the `StringBuf` / `Vec` Rust API parity audit with String/Vec still treated as the active priority.
- Finding remains: current SA facades are broad but still not complete Rust API coverage.
- Added supportable capacity-preserving helper:
  - `VEC_TRY_INSERT_FROM_SLICE_WITHIN_CAPACITY` / `VEC_INSERT_FROM_SLICE_WITHIN_CAPACITY`
  - `VEC_TRY_INSERT_FROM_SLICE_WITHIN_CAPACITY_U64` / `VEC_INSERT_FROM_SLICE_WITHIN_CAPACITY_U64`
- Semantics: validate `index <= len` and remaining capacity for the whole source slice first, then right-shift the tail and copy the slice in place. Empty slices succeed as no-ops; out-of-bounds indexes or insufficient room return `ok=0` with no mutation. Does not claim Rust allocator growth or partial insert.
- Validation status:
  - Source focused minimal harness `/tmp/ifswc_min.sa`: pass (`1 passed`).
  - Source focused `std_vec_macro_surface.sa --filter "insert_from_slice within capacity aliases"`: pass (`1 passed; 42 skipped`).
  - Install sync via installed-std copy of `vec.sa`: pass.
  - Installed-state focused min harness: pass (`1 passed`).

## Completed: 2026-07-12 StringBuf insert_n within capacity batch

- Continued the `StringBuf` / `Vec` Rust API parity audit with String/Vec still treated as the active priority.
- Finding remains: current SA facades are broad but still not complete Rust API coverage.
- Added supportable capacity-preserving helpers:
  - `STRING_BUF_TRY_INSERT_STR_N_WITHIN_CAPACITY` / `STRING_BUF_INSERT_STR_N_WITHIN_CAPACITY`
  - `STRING_BUF_TRY_INSERT_BYTE_N_WITHIN_CAPACITY` / `STRING_BUF_INSERT_BYTE_N_WITHIN_CAPACITY`
  - `STRING_BUF_TRY_INSERT_CHAR_N_WITHIN_CAPACITY` / `STRING_BUF_INSERT_CHAR_N_WITHIN_CAPACITY`
- Semantics: validate char boundary and remaining capacity for `insert_len * count` first, then insert the same payload `count` times at successive positions starting at `index`. Byte/char variants lower to the str-n path after encoding. Zero counts succeed as no-ops; mid-scalar indexes, invalid scalars, or insufficient room return `ok=0` with no mutation. Does not claim Rust `repeat` allocator growth or partial insert.
- Validation status:
  - Source focused minimal harness `/tmp/isinwc_min.sa`: pass (`1 passed`).
  - Source focused `std_string_macro_surface.sa --filter "insert_n within capacity aliases"`: pass (`1 passed; 104 skipped`).
  - Install sync via installed-std copy of `string.sa`: pass.
  - Installed-state focused min harness: pass (`1 passed`).

## Completed: 2026-07-11 Vec insert_n within capacity batch

- Continued the `StringBuf` / `Vec` Rust API parity audit with String/Vec still treated as the active priority.
- Finding remains: current SA facades are broad but still not complete Rust API coverage.
- Added supportable capacity-preserving helper:
  - `VEC_TRY_INSERT_N_WITHIN_CAPACITY` / `VEC_INSERT_N_WITHIN_CAPACITY`
  - `VEC_TRY_INSERT_N_WITHIN_CAPACITY_U64` / `VEC_INSERT_N_WITHIN_CAPACITY_U64`
- Semantics: validate `index <= len` and `len + count <= cap` first, then insert the same value `count` times at successive positions starting at `index` via within-capacity insert. Zero counts succeed as no-ops; out-of-bounds indexes or insufficient room return `ok=0` with no mutation. Does not claim Rust `repeat` allocator growth or partial insert.
- Validation status:
  - Source focused minimal harness `/tmp/inwc_min.sa`: pass (`1 passed`).
  - Source focused `std_vec_macro_surface.sa --filter "insert_n within capacity aliases"`: pass (`1 passed; 41 skipped`).
  - Install sync via installed-std copy of `vec.sa`: pass.
  - Installed-state focused min harness: pass (`1 passed`).

## Completed: 2026-07-11 StringBuf extend_from_within_n within capacity batch

- Continued the `StringBuf` / `Vec` Rust API parity audit with String/Vec still treated as the active priority.
- Finding remains: current SA facades are broad but still not complete Rust API coverage.
- Added supportable capacity-preserving helper:
  - `STRING_BUF_TRY_EXTEND_FROM_WITHIN_N_WITHIN_CAPACITY` / `STRING_BUF_EXTEND_FROM_WITHIN_N_WITHIN_CAPACITY`
- Semantics: validate the source range once, compute total byte length as `length * count`, and only then append the range `count` times via within-capacity `extend_from_within`. Zero counts succeed as no-ops; invalid ranges or insufficient room return `ok=0` with no mutation. Does not claim Rust `repeat` allocator growth or partial append.
- Validation status:
  - Source focused minimal harness `/tmp/sefwnwc_min.sa`: pass (`1 passed`).
  - Source focused `std_string_macro_surface.sa --filter "extend_from_within_n within capacity aliases"`: pass (`1 passed; 103 skipped`).
  - Install sync via installed-std copy of `string.sa`: pass.
  - Installed-state focused min harness: pass (`1 passed`).

## Completed: 2026-07-11 Vec extend_from_within_n within capacity batch

- Continued the `StringBuf` / `Vec` Rust API parity audit with String/Vec still treated as the active priority.
- Finding remains: current SA facades are broad but still not complete Rust API coverage.
- Added supportable capacity-preserving helper:
  - `VEC_TRY_EXTEND_FROM_WITHIN_N_WITHIN_CAPACITY_U64` / `VEC_EXTEND_FROM_WITHIN_N_WITHIN_CAPACITY_U64`
- Semantics: validate the source range once, compute total length as `length * count`, and only then append the range `count` times via within-capacity `extend_from_within`. Zero counts succeed as no-ops; invalid ranges or insufficient room return `ok=0` with no mutation. Does not claim Rust `repeat` allocator growth or partial append.
- Validation status:
  - Source focused minimal harness `/tmp/efwnwc_min.sa`: pass (`1 passed`).
  - Source focused `std_vec_macro_surface.sa --filter "extend_from_within_n within capacity aliases"`: pass (`1 passed; 40 skipped`).
  - Install sync via installed-std copy of `vec.sa`: pass.
  - Installed-state focused min harness: pass (`1 passed`).

## Completed: 2026-07-11 StringBuf push_byte_n / push_char_n within capacity batch

- Continued the `StringBuf` / `Vec` Rust API parity audit with String/Vec still treated as the active priority.
- Finding remains: current SA facades are broad but still not complete Rust API coverage.
- Added supportable capacity-preserving helpers:
  - `STRING_BUF_TRY_PUSH_BYTE_N_WITHIN_CAPACITY` / `STRING_BUF_PUSH_BYTE_N_WITHIN_CAPACITY`
  - `STRING_BUF_TRY_PUSH_CHAR_N_WITHIN_CAPACITY` / `STRING_BUF_PUSH_CHAR_N_WITHIN_CAPACITY`
- Semantics: append the same byte or Unicode scalar `count` times only when remaining capacity covers the whole sequence. Byte path reuses Vec push_n within capacity; char path encodes once, checks total UTF-8 width * count, then reuses within-capacity push_str. Zero counts succeed as no-ops; invalid scalars or insufficient room return `ok=0` with no mutation. Does not claim Rust `repeat` allocator growth or partial append.
- Validation status:
  - Source focused minimal harness `/tmp/sbcnwc_min.sa`: pass (`1 passed`).
  - Source focused `std_string_macro_surface.sa --filter "push_byte_n and push_char_n within capacity aliases"`: pass (`1 passed; 102 skipped`).
  - Install sync via installed-std copy of `string.sa`/`vec.sa`: pass.
  - Installed-state focused min harness: pass (`1 passed`).

## Completed: 2026-07-11 Vec push_n within capacity batch

- Continued the `StringBuf` / `Vec` Rust API parity audit with String/Vec still treated as the active priority.
- Finding remains: current SA facades are broad but still not complete Rust API coverage.
- Added supportable capacity-preserving helper:
  - `VEC_TRY_PUSH_N_WITHIN_CAPACITY` / `VEC_PUSH_N_WITHIN_CAPACITY`
  - `VEC_TRY_PUSH_N_WITHIN_CAPACITY_U64` / `VEC_PUSH_N_WITHIN_CAPACITY_U64`
- Semantics: append the same value `count` times only when remaining capacity covers the whole sequence. Zero counts succeed as no-ops; insufficient room returns `ok=0` with no mutation. This reuses within-capacity `push` and does not claim Rust `repeat` allocator growth or partial append.
- Validation status:
  - Source focused minimal harness `/tmp/pnwc_min.sa`: pass (`1 passed`).
  - Source focused `std_vec_macro_surface.sa --filter "push_n within capacity aliases"`: pass (`1 passed; 39 skipped`).
  - Install sync via installed-std copy of `vec.sa`: pass.
  - Installed-state focused min harness: pass (`1 passed`).

## Completed: 2026-07-11 Vec extend_from_slice_n within capacity batch

- Continued the `StringBuf` / `Vec` Rust API parity audit with String/Vec still treated as the active priority.
- Finding remains: current SA facades are broad but still not complete Rust API coverage.
- Added supportable capacity-preserving helper:
  - `VEC_TRY_EXTEND_FROM_SLICE_N_WITHIN_CAPACITY_U64` / `VEC_EXTEND_FROM_SLICE_N_WITHIN_CAPACITY_U64`
- Semantics: compute total repeated slice length first and append `count` copies only when remaining capacity covers the whole sequence. Zero counts succeed as no-ops; insufficient room returns `ok=0` with no mutation. This reuses within-capacity `extend_from_slice` and does not claim Rust `repeat` allocator growth or partial append.
- Validation status:
  - Source focused minimal harness `/tmp/efsnwc_min.sa`: pass (`1 passed`).
  - Source focused `std_vec_macro_surface.sa --filter "extend_from_slice_n within capacity aliases"`: pass (`1 passed; 38 skipped`).
  - Install sync via installed-std copy of `vec.sa`: pass.
  - Installed-state focused min harness: pass (`1 passed`).

## Completed: 2026-07-11 StringBuf push_str_n within capacity batch

- Continued the `StringBuf` / `Vec` Rust API parity audit with String/Vec still treated as the active priority.
- Finding remains: current SA facades are broad but still not complete Rust API coverage.
- Added supportable capacity-preserving helper:
  - `STRING_BUF_TRY_PUSH_STR_N_WITHIN_CAPACITY` / `STRING_BUF_PUSH_STR_N_WITHIN_CAPACITY`
- Semantics: compute total repeated suffix length first and append `count` copies only when remaining capacity covers the whole sequence. Zero counts succeed as no-ops; insufficient room returns `ok=0` with no mutation. This reuses within-capacity `push_str` and does not claim Rust `repeat` allocator growth or partial append.
- Validation status:
  - Source focused minimal harness `/tmp/psnwc_min.sa`: pass (`1 passed`).
  - Source focused `std_string_macro_surface.sa --filter "push_str_n within capacity aliases"`: pass (`1 passed; 101 skipped`).
  - Install sync via installed-std copy of `string.sa`: pass.
  - Installed-state focused min harness: pass (`1 passed`).

## Completed: 2026-07-11 StringBuf pop_if aliases batch

- Continued the `StringBuf` / `Vec` Rust API parity audit with String/Vec still treated as the active priority.
- Finding remains: current SA facades are broad but still not complete Rust API coverage.
- Added supportable conditional pop helpers:
  - `STRING_BUF_TRY_POP_BYTE_IF` / `STRING_BUF_POP_BYTE_IF`
  - `STRING_BUF_TRY_POP_CHAR_IF` / `STRING_BUF_POP_CHAR_IF`
- Semantics: inspect the trailing byte or Unicode scalar with a caller predicate and pop only when the predicate is nonzero. Empty buffers, decode failure, and non-matching predicates return `ok=0` with no mutation. These helpers only shrink and do not claim Rust `pop_if` generic iterator adapters.
- Validation status:
  - Source focused minimal harness `/tmp/popif_min.sa`: pass (`1 passed`).
  - Source focused `std_string_macro_surface.sa --filter "pop_if aliases"`: pass (`1 passed; 100 skipped`).
  - Install sync via installed-std copy of `string.sa`: pass.
  - Installed-state focused min harness: pass (`1 passed`).

## Completed: 2026-07-11 StringBuf splice within capacity batch

- Continued the `StringBuf` / `Vec` Rust API parity audit with String/Vec still treated as the active priority.
- Finding remains: current SA facades are broad but still not complete Rust API coverage.
- Added supportable capacity-preserving helper:
  - `STRING_BUF_TRY_SPLICE_WITHIN_CAPACITY` / `STRING_BUF_SPLICE_WITHIN_CAPACITY`
- Semantics: validate char boundaries and remaining capacity first, copy the drained range into a new owned StringBuf, drop owner-borrowed views, then replace the range in place with the provided slice via within-capacity replace. Invalid ranges or insufficient capacity return `ok=0`, an empty drained buffer, and no owner mutation. Does not claim Rust lazy splice iterators.
- Validation status:
  - Source focused minimal harness `/tmp/spwc_min.sa`: pass (`1 passed`).
  - Source focused `std_string_macro_surface.sa --filter "splice within capacity aliases"`: pass (`1 passed; 99 skipped`).
  - Install sync via installed-std copy of `string.sa`: pass.
  - Installed-state focused min harness: pass (`1 passed`).

## Completed: 2026-07-11 StringBuf drain within capacity batch

- Continued the `StringBuf` / `Vec` Rust API parity audit with String/Vec still treated as the active priority.
- Finding remains: current SA facades are broad but still not complete Rust API coverage.
- Added supportable capacity-preserving helper:
  - `STRING_BUF_TRY_DRAIN_WITHIN_CAPACITY` / `STRING_BUF_DRAIN_WITHIN_CAPACITY`
- Semantics: copy the selected char-boundary range into a new owned StringBuf, then remove it from the owner via empty-slice `STRING_BUF_TRY_REPLACE_RANGE_WITHIN_CAPACITY`. Invalid ranges return `ok=0` with an empty drained buffer and no owner mutation. Because removal only shrinks, the owner capacity is preserved. This does not claim Rust lazy drain iterators.
- Validation status:
  - Source focused minimal harness `/tmp/drwc_min.sa`: pass (`1 passed`).
  - Source focused `std_string_macro_surface.sa --filter "drain within capacity aliases"`: pass (`1 passed; 98 skipped`).
  - Install sync via installed-std copy of `string.sa`: pass.
  - Installed-state focused min harness: pass (`1 passed`).

## Completed: 2026-07-11 Vec resize_with within capacity batch

- Continued the `StringBuf` / `Vec` Rust API parity audit with String/Vec still treated as the active priority.
- Finding remains: current SA facades are broad but still not complete Rust API coverage.
- Added supportable capacity-preserving helper:
  - `VEC_TRY_RESIZE_WITH_WITHIN_CAPACITY_U64` / `VEC_RESIZE_WITH_WITHIN_CAPACITY_U64`
- Semantics: shrink truncates length in place. Growth calls a generator for each newly exposed slot and pushes only while `new_len <= cap`; over-capacity growth returns `ok=0` and leaves length unchanged. This is a concrete `u64` subset and does not claim Rust allocator-parametric or generic `T` semantics.
- Validation status:
  - Source focused minimal harness `/tmp/rswwc_min.sa`: pass (`1 passed`).
  - Source focused `std_vec_macro_surface.sa --filter "resize_with within capacity aliases"`: pass (`1 passed; 37 skipped`).
  - Install sync via installed-std copy of `vec.sa`: pass.
  - Installed-state focused min harness: pass (`1 passed`).

## Completed: 2026-07-11 Vec splice + StringBuf retain within capacity batch

- Continued the `StringBuf` / `Vec` Rust API parity audit with String/Vec still treated as the active priority.
- Finding remains: current SA facades are broad but still not complete Rust API coverage.
- Added supportable capacity-preserving helpers:
  - `VEC_TRY_SPLICE_WITHIN_CAPACITY_U64` / `VEC_SPLICE_WITHIN_CAPACITY_U64`
  - `STRING_BUF_TRY_RETAIN_WITHIN_CAPACITY` / `STRING_BUF_RETAIN_WITHIN_CAPACITY`
- Semantics:
  - Vec splice within capacity drains the selected range into a new output Vec, stages replacement values in a temporary Vec for self-overlap safety, then right-shifts the suffix and copies replacements in place only when the final length fits in the existing capacity. Out-of-range ranges or insufficient capacity return `ok=0`, an empty drained Vec, and no mutation of the owner.
  - StringBuf retain within capacity walks UTF-8 scalars with a caller predicate and compacts kept scalar bytes in place. Decode failure returns `ok=0` with the original length preserved. Because retain only shrinks, the owner capacity is unchanged.
  - These helpers do not claim Rust lazy drain/splice iterators, generic `T` element support beyond the concrete `u64` Vec subset, or allocator-parametric APIs.
- Validation status:
  - Source focused minimal harnesses `/tmp/swc_min.sa` and `/tmp/rtwc_min.sa`: pass (`1 passed` each).
  - Source focused `std_vec_macro_surface.sa --filter "splice within capacity aliases"`: pass (`1 passed; 36 skipped`).
  - Source focused `std_string_macro_surface.sa --filter "retain within capacity aliases"`: pass (`1 passed; 97 skipped`).
  - Install sync via installed-std copy of `vec.sa` / `string.sa`: pass.
  - Installed-state focused min harnesses: pass (`1 passed` each).

## Completed: 2026-07-11 StringBuf remove_matches within capacity batch

- Continued the `StringBuf` / `Vec` Rust API parity audit with String/Vec still treated as the active priority.
- Finding remains: current SA facades are broad but still not complete Rust API coverage.
- Added supportable capacity-preserving remove helpers:
  - `STRING_BUF_TRY_REMOVE_MATCHES_WITHIN_CAPACITY` / `STRING_BUF_REMOVE_MATCHES_WITHIN_CAPACITY`
  - `STRING_BUF_TRY_REMOVE_MATCHES_CHAR_WITHIN_CAPACITY` / `STRING_BUF_REMOVE_MATCHES_CHAR_WITHIN_CAPACITY`
- Semantics: copy the needle into a temporary buffer for self-overlap safety, then compact non-matching bytes in place. Empty needles are successful no-ops. Char variants encode a Unicode scalar first; invalid scalars return `ok=0` with no mutation. Because removals only shrink, these helpers never reallocate the owner buffer.
- Validation status:
  - Source focused minimal harness `/tmp/rmwc_min.sa`: pass (`1 passed`).
  - Source focused `std_string_macro_surface.sa --filter "remove matches within capacity aliases"`: pass (`1 passed; 96 skipped`).
  - Install sync via installed-std copy of `string.sa`: pass.
  - Installed-state focused min harness: pass (`1 passed`).

## Completed: 2026-07-11 StringBuf replace char first/last/range aliases batch

- Continued the `StringBuf` / `Vec` Rust API parity audit with String/Vec still treated as the active priority.
- Finding remains: current SA facades are broad but still not complete Rust API coverage.
- Added supportable reallocating char-pattern replace helpers:
  - `STRING_BUF_TRY_REPLACE_FIRST_CHAR` / `STRING_BUF_REPLACE_FIRST_CHAR`
  - `STRING_BUF_TRY_REPLACE_LAST_CHAR` / `STRING_BUF_REPLACE_LAST_CHAR`
  - `STRING_BUF_TRY_REPLACE_RANGE_CHAR` / `STRING_BUF_REPLACE_RANGE_CHAR`
- Semantics: encode a Unicode scalar to UTF-8 via `STR_ENCODE_CHAR_SLICE`, then reuse the existing first/last/range replace helpers. Invalid scalars and missing needles/ranges return `ok=0` with no mutation. These helpers may reallocate through the non-within-capacity replace path and do not claim Rust `Pattern` trait coverage.
- Validation status:
  - Source focused minimal harness `/tmp/rcc_min.sa`: pass (`1 passed`).
  - Source focused `std_string_macro_surface.sa --filter "replace char first last range aliases"`: pass (`1 passed; 95 skipped`).
  - Install sync via installed-std copy of `string.sa`: pass.
  - Installed-state focused min harness: pass (`1 passed`).

## Completed: 2026-07-11 StringBuf replace_range char within capacity batch

- Continued the `StringBuf` / `Vec` Rust API parity audit with String/Vec still treated as the active priority.
- Finding remains: current SA facades are broad but still not complete Rust API coverage.
- Added supportable capacity-preserving char range-replace helpers:
  - `STRING_BUF_TRY_REPLACE_RANGE_CHAR_WITHIN_CAPACITY` / `STRING_BUF_REPLACE_RANGE_CHAR_WITHIN_CAPACITY`
- Semantics: encode a Unicode scalar to UTF-8 via `STR_ENCODE_CHAR_SLICE`, then reuse `STRING_BUF_TRY_REPLACE_RANGE_WITHIN_CAPACITY`. Invalid scalars, out-of-range/non-boundary ranges, and insufficient remaining capacity return `ok=0` with no mutation. These helpers do not claim Rust `Pattern` trait coverage or panic-on-capacity models.
- Validation status:
  - Source focused minimal harness `/tmp/rrcwc_min.sa`: pass (`1 passed`).
  - Source focused `std_string_macro_surface.sa --filter "replace_range char within capacity aliases"`: pass (`1 passed; 94 skipped`).
  - Install sync via installed-std copy of `string.sa`: pass.
  - Installed-state focused min harness: pass (`1 passed`).

## Completed: 2026-07-11 StringBuf extend char/ascii refs within capacity batch

- Continued the `StringBuf` / `Vec` Rust API parity audit with String/Vec still treated as the active priority.
- Finding remains: current SA facades are broad but still not complete Rust API coverage.
- Added supportable capacity-preserving ref-slice extend helpers:
  - `STRING_BUF_TRY_EXTEND_CHAR_REFS_WITHIN_CAPACITY_U64` / `STRING_BUF_EXTEND_CHAR_REFS_WITHIN_CAPACITY_U64`
  - `STRING_BUF_TRY_EXTEND_ASCII_CHAR_REFS_WITHIN_CAPACITY` / `STRING_BUF_EXTEND_ASCII_CHAR_REFS_WITHIN_CAPACITY`
- Semantics:
  - Char-ref within-capacity extend loads each `*u64` scalar through the ref slice, validates all scalars first, sums exact UTF-8 widths, and only appends when remaining capacity covers the whole sequence.
  - ASCII-ref within-capacity extend loads each `*u8` through the ref slice, validates all bytes as ASCII, and requires remaining capacity for the full source length before appending.
  - Invalid values or insufficient room return `ok=0` with no mutation. These helpers do not claim Rust iterator/Pattern adapters, partial append, or allocator-parametric APIs.
- Validation status:
  - Source focused minimal harness `/tmp/ecrawc_min.sa`: pass (`1 passed`).
  - Source focused `std_string_macro_surface.sa --filter "extend char ascii refs within capacity aliases"`: pass (`1 passed; 93 skipped`).
  - Install sync via installed-std copy of `string.sa`: pass.
  - Installed-state focused min harness: pass (`1 passed`).

## Completed: 2026-07-11 StringBuf extend chars/ascii within capacity batch

- Continued the `StringBuf` / `Vec` Rust API parity audit with String/Vec still treated as the active priority.
- Finding remains: current SA facades are broad but still not complete Rust API coverage.
- Added supportable capacity-preserving multi-char extend helpers:
  - `STRING_BUF_TRY_EXTEND_CHARS_WITHIN_CAPACITY_U64` / `STRING_BUF_EXTEND_CHARS_WITHIN_CAPACITY_U64`
  - `STRING_BUF_TRY_EXTEND_ASCII_CHARS_WITHIN_CAPACITY` / `STRING_BUF_EXTEND_ASCII_CHARS_WITHIN_CAPACITY`
- Semantics:
  - `extend_chars_within_capacity` validates all scalars first, sums exact UTF-8 widths, and only appends when remaining capacity covers the whole sequence. Invalid scalars or insufficient room return `ok=0` with no mutation.
  - `extend_ascii_chars_within_capacity` validates all bytes as ASCII and requires remaining capacity for the full source length before appending. Non-ASCII bytes or insufficient room return `ok=0` with no mutation.
  - These helpers do not claim Rust iterator/Pattern adapters, partial append, or allocator-parametric APIs.
- Validation status:
  - Source focused minimal harness `/tmp/ecawc_min.sa`: pass (`1 passed`).
  - Source focused `std_string_macro_surface.sa --filter "extend chars ascii within capacity aliases"`: pass (`1 passed; 92 skipped`).
  - Install sync via installed-std copy of `string.sa`: pass.
  - Installed-state focused min harness: pass (`1 passed`).

## Completed: 2026-07-11 StringBuf replace_first/last char within capacity batch

- Continued the `StringBuf` / `Vec` Rust API parity audit with String/Vec still treated as the active priority.
- Finding remains: current SA facades are broad but still not complete Rust API coverage.
- Added supportable capacity-preserving char-pattern replace helpers:
  - `STRING_BUF_TRY_REPLACE_FIRST_CHAR_WITHIN_CAPACITY` / `STRING_BUF_REPLACE_FIRST_CHAR_WITHIN_CAPACITY`
  - `STRING_BUF_TRY_REPLACE_LAST_CHAR_WITHIN_CAPACITY` / `STRING_BUF_REPLACE_LAST_CHAR_WITHIN_CAPACITY`
- Semantics: encode a Unicode scalar to its UTF-8 needle via `STR_ENCODE_CHAR_SLICE`, then reuse the existing within-capacity first/last replace helpers. Invalid scalars, missing needles, and insufficient remaining capacity return `ok=0` with no mutation. These helpers do not claim Rust `Pattern` trait coverage or panic-on-capacity models.
- Validation status:
  - Source focused minimal harness `/tmp/rflcwc_min.sa`: pass (`1 passed`).
  - Source focused `std_string_macro_surface.sa --filter "replace_first_last char within capacity aliases"`: pass (`1 passed; 91 skipped`).
  - Install sync via installed-std copy of `string.sa`: pass.
  - Installed-state focused min harness: pass (`1 passed`).

## Completed: 2026-07-11 StringBuf replace_first/last + Vec resize within capacity batch

- Continued the `StringBuf` / `Vec` Rust API parity audit with String/Vec still treated as the active priority.
- Finding remains: current SA facades are broad but still not complete Rust API coverage.
- Added supportable capacity-preserving helpers:
  - `STRING_BUF_TRY_REPLACE_FIRST_WITHIN_CAPACITY` / `STRING_BUF_REPLACE_FIRST_WITHIN_CAPACITY`
  - `STRING_BUF_TRY_REPLACE_LAST_WITHIN_CAPACITY` / `STRING_BUF_REPLACE_LAST_WITHIN_CAPACITY`
  - `VEC_TRY_RESIZE_WITHIN_CAPACITY` / `VEC_RESIZE_WITHIN_CAPACITY`
  - `VEC_TRY_RESIZE_WITHIN_CAPACITY_U64` / `VEC_RESIZE_WITHIN_CAPACITY_U64`
- Semantics:
  - String replace-first/last within capacity locate the first/last needle occurrence and then reuse `STRING_BUF_TRY_REPLACE_RANGE_WITHIN_CAPACITY`. Missing needles or insufficient remaining capacity return `ok=0` with no mutation.
  - Vec resize within capacity truncates immediately when shrinking. Growth succeeds only when `new_len <= cap`, filling newly exposed slots with the provided value via within-capacity push; over-capacity growth returns `ok=0` and leaves length unchanged.
  - These helpers do not claim Rust panic-on-capacity models, partial growth, or allocator-parametric APIs.
- Validation status:
  - Source focused minimal harness `/tmp/rfl_rswc_min.sa`: pass (`1 passed`).
  - Source focused `std_vec_macro_surface.sa --filter "resize within capacity aliases"`: pass (`1 passed; 35 skipped`).
  - Source focused `std_string_macro_surface.sa --filter "replace_first_last within capacity aliases"`: pass (`1 passed; 90 skipped`).
  - Install sync via installed-std copy of `string.sa` + `vec.sa`: pass.
  - Installed-state focused min harness: pass (`1 passed`).

## Completed: 2026-07-11 StringBuf replace_range within capacity batch

- Continued the `StringBuf` / `Vec` Rust API parity audit with String/Vec still treated as the active priority.
- Finding remains: current SA facades are broad but still not complete Rust API coverage.
- Added supportable capacity-preserving replace helpers:
  - `STRING_BUF_TRY_REPLACE_RANGE_WITHIN_CAPACITY` / `STRING_BUF_REPLACE_RANGE_WITHIN_CAPACITY`
- Semantics: replace a char-boundary range only when the resulting length fits in existing capacity. On success, the replacement is staged through a temporary buffer, the suffix is shifted in place (right for growth, left for shrink), and length is updated without reallocation. Out-of-bounds ranges, mid-scalar boundaries, or insufficient capacity return `ok=0` with no mutation. These helpers do not claim Rust panic-on-boundary models, partial writes, or allocator-parametric APIs.
- Validation status:
  - Source focused minimal harness `/tmp/rrwc_min.sa`: pass (`1 passed`).
  - Source focused `std_string_macro_surface.sa --filter "replace_range within capacity aliases"`: pass (`1 passed; 89 skipped`).
  - Install sync via installed-std copy of `string.sa`: pass.
  - Installed-state focused min harness: pass (`1 passed`).

## Completed: 2026-07-11 Vec extend_from_within + StringBuf extend char/byte within capacity batch

- Continued the `StringBuf` / `Vec` Rust API parity audit with String/Vec still treated as the active priority.
- Finding remains: current SA facades are broad but still not complete Rust API coverage.
- Added supportable capacity-preserving helpers:
  - `VEC_TRY_EXTEND_FROM_WITHIN_CAPACITY_U64` / `VEC_EXTEND_FROM_WITHIN_CAPACITY_U64`
  - `STRING_BUF_TRY_EXTEND_CHAR_WITHIN_CAPACITY` / `STRING_BUF_EXTEND_CHAR_WITHIN_CAPACITY`
  - `STRING_BUF_TRY_EXTEND_BYTE_WITHIN_CAPACITY` / `STRING_BUF_EXTEND_BYTE_WITHIN_CAPACITY`
- Semantics:
  - Vec extend-from-within capacity checks range bounds and remaining capacity first. On success it copies the selected range through a temporary Vec so self-overlap is safe, then appends without reallocation. Empty ranges succeed as no-ops; out-of-bounds or insufficient room returns `ok=0` with no mutation.
  - String extend char/byte within capacity are thin aliases over the existing non-reallocating push_char/push_byte within-capacity helpers.
  - These helpers do not claim Rust panic-on-capacity models, partial append, lazy iterators, or allocator-parametric APIs.
- Validation status:
  - Source focused minimal harness `/tmp/efwwc_min.sa`: pass (`1 passed`).
  - Source focused `std_vec_macro_surface.sa --filter "extend_from_within capacity aliases"`: pass (`1 passed; 34 skipped`).
  - Source focused `std_string_macro_surface.sa --filter "extend char byte within capacity aliases"`: pass (`1 passed; 88 skipped`).
  - Install sync via installed-std copy of `string.sa` + `vec.sa`: pass.
  - Installed-state focused min harness: pass (`1 passed`).

## Completed: 2026-07-11 StringBuf/Vec extend and append within capacity batch

- Continued the `StringBuf` / `Vec` Rust API parity audit with String/Vec still treated as the active priority.
- Finding remains: current SA facades are broad but still not complete Rust API coverage.
- Added supportable capacity-preserving extend/append helpers:
  - `STRING_BUF_TRY_EXTEND_STR_WITHIN_CAPACITY` / `STRING_BUF_EXTEND_STR_WITHIN_CAPACITY`
  - `STRING_BUF_TRY_EXTEND_STRING_WITHIN_CAPACITY` / `STRING_BUF_EXTEND_STRING_WITHIN_CAPACITY`
  - `STRING_BUF_TRY_EXTEND_FROM_WITHIN_CAPACITY` / `STRING_BUF_EXTEND_FROM_WITHIN_CAPACITY`
  - `VEC_TRY_APPEND_WITHIN_CAPACITY` / `VEC_APPEND_WITHIN_CAPACITY`
  - `VEC_TRY_APPEND_WITHIN_CAPACITY_U64` / `VEC_APPEND_WITHIN_CAPACITY_U64`
- Semantics:
  - String `extend_str`/`extend_string` within capacity alias the existing non-reallocating `push_str_within_capacity` path. `extend_string` views the source StringBuf and does **not** free or move it.
  - `extend_from_within_capacity` requires a valid char-boundary range and enough remaining capacity; it copies the selected range through a temporary buffer so self-overlap remains safe, then appends without reallocation.
  - Vec `append_within_capacity` extends destination from the source slice only when remaining capacity is sufficient for the full source length. On success it clears source `len` to 0 (consume-src append semantics matching `sa_vec_append`); on failure neither destination nor source is mutated.
  - These helpers do not claim Rust panic-on-capacity models, partial append, lazy iterators, or allocator-parametric APIs.
- Validation status:
  - Source focused minimal harness `/tmp/ext_append_wc_min.sa`: pass (`1 passed`).
  - Source focused owned extend-string min `/tmp/ext_string_owned_min.sa`: pass (`1 passed`).
  - Source focused `std_vec_macro_surface.sa --filter "append within capacity aliases"`: pass (`1 passed; 33 skipped`).
  - Source focused `std_string_macro_surface.sa --filter "extend within capacity aliases"`: pass (`1 passed; 87 skipped`).
  - Install sync via installed-std copy of `string.sa` + `vec.sa`: pass.
  - Installed-state focused min harnesses: pass (`1 passed` each).

## Completed: 2026-07-11 Vec extend_from_slice_within_capacity alias batch

- Continued the `StringBuf` / `Vec` Rust API parity audit with String/Vec still treated as the active priority.
- Finding remains: current SA facades are broad but still not complete Rust API coverage.
- Added supportable capacity-preserving extend helpers:
  - `VEC_TRY_EXTEND_FROM_SLICE_WITHIN_CAPACITY` / `VEC_EXTEND_FROM_SLICE_WITHIN_CAPACITY`
  - `VEC_TRY_EXTEND_FROM_SLICE_WITHIN_CAPACITY_U64` / `VEC_EXTEND_FROM_SLICE_WITHIN_CAPACITY_U64`
- Semantics: append a source slice only when remaining capacity is large enough for the full source length. On success, bytes/elements are copied in place without reallocation and length advances by the source length. Empty sources succeed as no-ops. Insufficient room returns `ok=0` with no mutation. These helpers do not claim Rust panic-on-capacity models, partial-append behavior, or allocator-parametric APIs.
- Validation status:
  - Source focused minimal harness: pass (`1 passed`).
  - Source focused `std_vec_macro_surface.sa --filter "extend_from_slice within capacity aliases"`: pass (`1 passed; 32 skipped`).
  - Install sync via installed-std copy of `vec.sa`: pass.
  - Installed-state focused min harness: pass (`1 passed`).

## Completed: 2026-07-11 Vec insert_within_capacity alias batch

- Continued the `StringBuf` / `Vec` Rust API parity audit with String/Vec still treated as the active priority.
- Finding remains: current SA facades are broad but still not complete Rust API coverage.
- Added supportable capacity-preserving Vec insert helpers:
  - `VEC_TRY_INSERT_WITHIN_CAPACITY` / `VEC_INSERT_WITHIN_CAPACITY`
  - `VEC_TRY_INSERT_WITHIN_CAPACITY_U64` / `VEC_INSERT_WITHIN_CAPACITY_U64`
- Semantics: insert only when `index <= len` and `len < cap`. On success, later elements shift right in place and the new value is stored without reallocation. Out-of-bounds indexes and full capacity return `ok=0` with no mutation. These helpers do not claim Rust panic-on-capacity models, generic `T` beyond the existing U64/element-size facade, or allocator-parametric behavior.
- Validation status:
  - Source focused minimal harness: pass (`1 passed`).
  - Source focused `std_vec_macro_surface.sa --filter "insert within capacity aliases"`: pass (`1 passed; 31 skipped`).
  - Install sync via installed-std copy of `vec.sa`: pass.
  - Installed-state focused min harness: pass (`1 passed`).

## Completed: 2026-07-11 StringBuf insert_within_capacity alias batch

- Continued the `StringBuf` / `Vec` Rust API parity audit with String/Vec still treated as the active priority.
- Finding remains: current SA facades are broad but still not complete Rust API coverage.
- Added supportable capacity-preserving insert helpers:
  - `STRING_BUF_TRY_INSERT_STR_WITHIN_CAPACITY` / `STRING_BUF_INSERT_STR_WITHIN_CAPACITY`
  - `STRING_BUF_TRY_INSERT_BYTE_WITHIN_CAPACITY` / `STRING_BUF_INSERT_BYTE_WITHIN_CAPACITY`
  - `STRING_BUF_TRY_INSERT_CHAR_WITHIN_CAPACITY` / `STRING_BUF_INSERT_CHAR_WITHIN_CAPACITY`
- Semantics: insert only when remaining capacity is large enough for the inserted bytes and the insert index is a UTF-8 char boundary. On success, bytes after the index are shifted right in place and the insertion is copied without reallocation. Empty inserts succeed as no-ops. Insufficient room, mid-scalar indices, and invalid scalar char encodings return `ok=0` with no mutation. These helpers do not claim Rust panic-on-capacity/boundary models, `Option` layouts, or allocator-parametric behavior.
- Validation status:
  - Source focused minimal harness: pass (`1 passed`).
  - Source focused `std_string_macro_surface.sa --filter "insert within capacity aliases"`: pass (`1 passed; 86 skipped`).
  - Install sync via installed-std copy of `string.sa`: pass.
  - Installed-state focused min harness: pass (`1 passed`).

## Completed: 2026-07-11 str/String get_mut range_to/from naming alias batch

- Continued the `StringBuf` / `Vec` Rust API parity audit with String/Vec still treated as the active priority.
- Finding remains: current SA facades are broad but still not complete Rust API coverage.
- Added supportable mutable range-to/from get naming aliases:
  - `STR_TRY_GET_RANGE_TO_MUT` / `STRING_TRY_GET_RANGE_TO_MUT` / `STRING_BUF_TRY_GET_RANGE_TO_MUT`
  - `STR_GET_RANGE_TO_MUT` / `STRING_GET_RANGE_TO_MUT` / `STRING_BUF_GET_RANGE_TO_MUT`
  - `STR_TRY_GET_RANGE_FROM_MUT` / `STRING_TRY_GET_RANGE_FROM_MUT` / `STRING_BUF_TRY_GET_RANGE_FROM_MUT`
  - `STR_GET_RANGE_FROM_MUT` / `STRING_GET_RANGE_FROM_MUT` / `STRING_BUF_GET_RANGE_FROM_MUT`
- Semantics: mutable range-to/from helpers reuse existing checked prefix/suffix helpers; `STRING_BUF_*` forms view through `STRING_BUF_AS_MUT_STR` so successful slices write back into the buffer. Bounds and UTF-8 char-boundary checks remain delegated to the existing helpers. These aliases do not claim Rust `Option<&mut str>` layout, exclusive mutable-reference borrow rules, or range-trait object coverage.
- Validation status:
  - Source focused minimal harness: pass (`1 passed`).
  - Source focused `std_string_macro_surface.sa --filter "get_mut range_to_from naming aliases"`: pass (`1 passed; 85 skipped`).
  - Install sync via installed-std copy of `string.sa`: pass.
  - Installed-state focused min harness: pass (`1 passed`).

## Completed: 2026-07-11 str/String get_mut range naming alias batch

- Continued the `StringBuf` / `Vec` Rust API parity audit with String/Vec still treated as the active priority.
- Finding remains: current SA facades are broad but still not complete Rust API coverage.
- Added supportable mutable range/prefix/suffix/between get naming aliases:
  - `STR_TRY_GET_RANGE_MUT` / `STRING_TRY_GET_RANGE_MUT` / `STRING_BUF_TRY_GET_RANGE_MUT`
  - `STR_GET_RANGE_MUT` / `STRING_GET_RANGE_MUT` / `STRING_BUF_GET_RANGE_MUT`
  - `STR_TRY_GET_PREFIX_MUT` / `STRING_TRY_GET_PREFIX_MUT` / `STRING_BUF_TRY_GET_PREFIX_MUT`
  - `STR_GET_PREFIX_MUT` / `STRING_GET_PREFIX_MUT` / `STRING_BUF_GET_PREFIX_MUT`
  - `STR_TRY_GET_SUFFIX_MUT` / `STRING_TRY_GET_SUFFIX_MUT` / `STRING_BUF_TRY_GET_SUFFIX_MUT`
  - `STR_GET_SUFFIX_MUT` / `STRING_GET_SUFFIX_MUT` / `STRING_BUF_GET_SUFFIX_MUT`
  - `STR_TRY_GET_RANGE_BETWEEN_MUT` / `STRING_TRY_GET_RANGE_BETWEEN_MUT` / `STRING_BUF_TRY_GET_RANGE_BETWEEN_MUT`
  - `STR_GET_RANGE_BETWEEN_MUT` / `STRING_GET_RANGE_BETWEEN_MUT` / `STRING_BUF_GET_RANGE_BETWEEN_MUT`
- Semantics: mutable range helpers reuse the existing checked get-range helpers; `STRING_BUF_*` forms view through `STRING_BUF_AS_MUT_STR` so successful slices write back into the buffer. Bounds and UTF-8 char-boundary checks remain delegated to the existing helpers. These aliases do not claim Rust `Option<&mut str>` layout, exclusive mutable-reference borrow rules, or range-trait object coverage.
- Validation status:
  - Source focused minimal harness: pass (`1 passed`).
  - Source focused `std_string_macro_surface.sa --filter "get_mut range naming aliases"`: pass (`1 passed; 84 skipped`).
  - Install sync via installed-std copy of `string.sa`: pass.
  - Installed-state focused min harness: pass (`1 passed`).

## Completed: 2026-07-11 StringBuf try_truncate alias batch

- Continued the `StringBuf` / `Vec` Rust API parity audit with String/Vec still treated as the active priority.
- Finding remains: current SA facades are broad but still not complete Rust API coverage.
- Added supportable checked truncate helper:
  - `STRING_BUF_TRY_TRUNCATE`
- Semantics: if `new_len > current len`, returns `ok=1` and leaves the buffer unchanged (Rust-like no-op truncate-up). If `new_len <= current len`, requires `STR_IS_CHAR_BOUNDARY` on the current string view and only then truncates; mid-scalar indices return `ok=0` with no mutation. This does not claim Rust panic-on-mid-scalar `truncate`, allocator traits, or generic Pattern machinery.
- Validation status:
  - Source focused minimal harness: pass (`1 passed`).
  - Source focused `std_string_macro_surface.sa --filter "try_truncate aliases"`: pass (`1 passed; 83 skipped`).
  - Install sync via installed-std copy of `string.sa`: pass.
  - Installed-state focused min harness: pass (`1 passed`).

## Completed: 2026-07-11 StringBuf push_byte/char_within_capacity + Vec try_set_len batch

- Continued the `StringBuf` / `Vec` Rust API parity audit with String/Vec still treated as the active priority.
- Finding remains: current SA facades are broad but still not complete Rust API coverage.
- Added supportable capacity-preserving push helpers and checked Vec length updates:
  - `STRING_BUF_TRY_PUSH_BYTE_WITHIN_CAPACITY` / `STRING_BUF_PUSH_BYTE_WITHIN_CAPACITY`
  - `STRING_BUF_TRY_PUSH_CHAR_WITHIN_CAPACITY` / `STRING_BUF_PUSH_CHAR_WITHIN_CAPACITY`
  - `VEC_TRY_SET_LEN` / `VEC_TRY_SET_LEN_U64`
- Semantics: push-byte-within-capacity reuses `VEC_TRY_PUSH_WITHIN_CAPACITY` with `elem_size=1`. push-char-within-capacity encodes a Unicode scalar to UTF-8 first, then appends only when remaining capacity is large enough for the encoded width; invalid scalars and insufficient room return `ok=0` without mutation and never reallocate. `VEC_TRY_SET_LEN` accepts `new_len <= cap` and returns `ok=0` without mutation when over capacity; it does not claim Rust unsafe `set_len` panic semantics, caller-initialized spare proofs, or generic allocator integration.
- Validation status:
  - Source focused minimal harness covering both families: pass (`1 passed`).
  - Source focused `std_string_macro_surface.sa --filter "push_byte and push_char within capacity aliases"`: pass (`1 passed; 82 skipped`).
  - Source focused `std_vec_macro_surface.sa --filter "try_set_len aliases"`: pass (`1 passed; 30 skipped`).
  - Install sync via installed-std copy of `string.sa` / `vec.sa`: pass.
  - Installed-state focused min harness: pass (`1 passed`).

## Completed: 2026-07-11 str/String get_mut + StringBuf push_str_within_capacity batch

- Continued the `StringBuf` / `Vec` Rust API parity audit with String/Vec still treated as the active priority.
- Finding remains: current SA facades are broad but still not complete Rust API coverage.
- Added supportable mutable get naming aliases and capacity-preserving `push_str` helpers:
  - `STR_TRY_GET_MUT` / `STRING_TRY_GET_MUT` / `STRING_BUF_TRY_GET_MUT`
  - `STR_GET_MUT` / `STRING_GET_MUT` / `STRING_BUF_GET_MUT`
  - `STR_TRY_GET_UNCHECKED_MUT` / `STRING_TRY_GET_UNCHECKED_MUT` / `STRING_BUF_TRY_GET_UNCHECKED_MUT`
  - `STR_GET_UNCHECKED_MUT` / `STRING_GET_UNCHECKED_MUT` / `STRING_BUF_GET_UNCHECKED_MUT`
  - `STRING_BUF_TRY_PUSH_STR_WITHIN_CAPACITY` / `STRING_BUF_PUSH_STR_WITHIN_CAPACITY`
- Semantics: mutable get aliases reuse the existing checked/unchecked get range helpers; `STRING_BUF_*` forms view through `STRING_BUF_AS_MUT_STR` so successful slices write back into the buffer. Unchecked mut forms remain bounds/order-only and skip char-boundary validation. `push_str_within_capacity` appends only when `remaining_capacity >= suffix_len`, returns `ok=0` without mutation when room is insufficient, and never reallocates. These helpers do not claim Rust `Option<&mut str>` layout, borrow-checker exclusive mutable reference rules, or allocator-parametric behavior.
- Validation status:
  - Source focused minimal harness covering get_mut + push_str_within_capacity: pass (`1 passed`).
  - Source focused `std_string_macro_surface.sa --filter "get_mut naming aliases"`: pass (`1 passed; 81 skipped`).
  - Source focused `std_string_macro_surface.sa --filter "push_str within capacity aliases"`: pass (`1 passed; 81 skipped`).
  - Install sync via installed-std copy of `string.sa`: pass.
  - Installed-state focused min harness: pass (`1 passed`).

## Completed: 2026-07-11 str/String get naming + StringBuf set_len batch

- Continued the `StringBuf` / `Vec` Rust API parity audit with String/Vec still treated as the active priority.
- Finding remains: current SA facades are broad but still not complete Rust API coverage.
- Added supportable Rust `str`/`String`/`StringBuf` get naming aliases and StringBuf `set_len` helpers:
  - `STR_TRY_GET` / `STRING_TRY_GET` / `STRING_BUF_TRY_GET`
  - `STR_GET` / `STRING_GET` / `STRING_BUF_GET`
  - `STR_TRY_GET_UNCHECKED` / `STRING_TRY_GET_UNCHECKED` / `STRING_BUF_TRY_GET_UNCHECKED`
  - `STR_GET_UNCHECKED` / `STRING_GET_UNCHECKED` / `STRING_BUF_GET_UNCHECKED`
  - `STRING_BUF_TRY_SET_LEN` / `STRING_BUF_SET_LEN`
- Semantics: checked get aliases are naming wrappers over existing `STR_TRY_GET_RANGE_BETWEEN` (bounds + UTF-8 char-boundary). Unchecked get aliases require only order/bounds (`end >= start` and `end <= len`) and intentionally skip char-boundary validation, returning an empty slice with `ok=0` on miss rather than claiming Rust panic/unsafe semantics. `STRING_BUF_TRY_SET_LEN` accepts `new_len <= cap`; shrink paths require `STR_IS_CHAR_BOUNDARY` on the current string view, while in-capacity extend paths are allowed under the caller-initialized spare contract. Over-capacity and mid-scalar shrink paths return `ok=0` without mutation. These helpers do not claim Rust `Option<&str>` layout, full unsafe panic models, or generic allocator/MaybeUninit object models.
- Validation status:
  - Source focused minimal harness covering get + set_len: pass (`1 passed`).
  - Source focused `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_string_macro_surface.sa --filter "get range naming aliases" --jobs 1 --trace-panic`: pass (`1 passed; 79 skipped`).
  - Source focused `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_string_macro_surface.sa --filter "set_len aliases" --jobs 1 --trace-panic`: pass (`1 passed; 79 skipped`).
  - Install sync via installed-std copy of `string.sa`: pass.
  - Installed-state focused min harnesses for get and set_len: pass (`1 passed` each).

## Completed: 2026-07-11 Vec/StringBuf capacity remaining alias batch

- Continued the `StringBuf` / `Vec` Rust API parity audit with String/Vec still treated as the active priority.
- Finding remains: current SA facades are broad but still not complete Rust API coverage.
- Added supportable capacity-remaining and StringBuf spare aliases:
  - `VEC_CAPACITY_REMAINING` / `VEC_REMAINING_CAPACITY`
  - `STRING_BUF_CAPACITY_REMAINING` / `STRING_BUF_REMAINING_CAPACITY`
  - `STRING_BUF_SPARE_CAPACITY_MUT` / `STRING_BUF_SPLIT_AT_SPARE_MUT`
- Semantics: remaining-capacity helpers return `cap - len` element/byte count without allocating. StringBuf spare helpers expose the uninitialized spare region as a mutable byte `Slice` (`elem_size=1`) and split initialized bytes from spare capacity, matching the existing Vec spare-capacity subset. These helpers do not claim Rust's generic `MaybeUninit` spare view object model, allocator trait integration, or full provenance semantics.
- Validation status:
  - Source focused minimal harness over the same macros: pass (`1 passed`).
  - Source focused `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_vec_macro_surface.sa --filter "capacity remaining aliases" --jobs 1 --trace-panic`: pass (`1 passed; 29 skipped`).
  - Source focused `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_string_macro_surface.sa --filter "capacity remaining and spare aliases" --jobs 1 --trace-panic`: pass (`1 passed; 77 skipped`).
  - Install sync via installed-std copy of `vec.sa` / `string.sa`: pass.
  - Installed-state focused `SA_STD_DIR=/home/vscode/.sa/std` minimal harness: pass (`1 passed`).

## Completed: 2026-07-11 str/String substr_range alias batch

- Continued the `StringBuf` / `Vec` Rust API parity audit with String/Vec still treated as the active priority.
- Finding remains: current SA facades are broad but still not complete Rust API coverage.
- Added supportable Rust `str`/`String`/`StringBuf` substr-range aliases:
  - `STR_TRY_SUBSTR_RANGE` / `STRING_TRY_SUBSTR_RANGE` / `STRING_BUF_TRY_SUBSTR_RANGE`
  - `STR_SUBSTR_RANGE` / `STRING_SUBSTR_RANGE` / `STRING_BUF_SUBSTR_RANGE`
- Semantics: recover the byte range of a borrowed sub-`Slice` inside a haystack `Slice` by pointer arithmetic. Success requires the sub-slice pointer to be inside the haystack address range and the sub length to fit; the result is `(ok, start, end)` where `end = start + sub_len`. Outside/non-overlapping subslices return `ok=0`, `start=0`, `end=0`. This remains a concrete pointer-range recovery subset rather than Rust's full `substr_range`/`substr_range_unchecked` panic/unsafe variants, lifetime proofs, or provenance model.
- Validation status:
  - Source focused minimal harness over the same macros: pass (`1 passed`).
  - Source focused `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_string_macro_surface.sa --filter "substr range aliases" --jobs 1 --trace-panic`: pass (`1 passed; 76 skipped`).
  - Install sync via installed-std copy of `string.sa`: pass.
  - Installed-state focused `SA_STD_DIR=/home/vscode/.sa/std ./zig-out/bin/sa test` over the same substr_range macros (minimal dedicated harness): pass (`1 passed; 0 failed; 0 skipped`).

## Completed: 2026-07-11 str/String escape_debug alias batch

- Continued the `StringBuf` / `Vec` Rust API parity audit with String/Vec still treated as the active priority.
- Finding remains: current SA facades are broad but still not complete Rust API coverage.
- Added supportable Rust `char`/`str`/`String`/`StringBuf` escape-debug aliases:
  - `CHAR_ESCAPE_DEBUG_WRITE`
  - `STR_ESCAPE_DEBUG` / `STRING_ESCAPE_DEBUG` / `STRING_BUF_ESCAPE_DEBUG`
- Semantics: `CHAR_ESCAPE_DEBUG_WRITE` mirrors the supportable `escape_default` special ASCII escapes (`\t`/`\n`/`\r`/`\\`/`\'`/`\"`), keeps printable ASCII as raw bytes, writes non-ASCII scalars as raw UTF-8, and falls back to lowercase `\u{...}` for non-printable ASCII controls. String aliases walk UTF-8 scalars with `STR_TRY_CHAR_AT_BYTE`, write each escaped form into a temporary buffer, and append into an owned `StringBuf`. Invalid UTF-8 paths panic in this concrete subset. This remains an eager owned-string / writer subset rather than Rust's lazy `EscapeDebug` iterator, full Unicode general-category graphic classification, or borrow-checker lifetime model.
- Validation status:
  - Source focused `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_char_macro_surface.sa --filter "escape_debug write" --jobs 1 --trace-panic`: pass (`1 passed; 4 skipped`).
  - Source focused `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_string_macro_surface.sa --filter "escape debug aliases" --jobs 1 --trace-panic`: pass (`1 passed; 75 skipped`).
  - Install sync via installed-std copy of `char.sa` / `string.sa`: pass.
  - Installed-state focused `SA_STD_DIR=/home/vscode/.sa/std ./zig-out/bin/sa test` over the same escape_debug macros (minimal dedicated harness): pass (`1 passed; 0 failed; 0 skipped`).

## Completed: 2026-07-11 str/String utf8_chunks alias batch

- Continued the `StringBuf` / `Vec` Rust API parity audit with String/Vec still treated as the active priority.
- Finding remains: current SA facades are broad but still not complete Rust API coverage.
- Added supportable Rust `str`/`String`/`StringBuf` utf8-chunks aliases:
  - `STR_UTF8_CHUNKS_COUNT` / `STRING_UTF8_CHUNKS_COUNT` / `STRING_BUF_UTF8_CHUNKS_COUNT`
  - `STR_TRY_UTF8_CHUNK_AT` / `STRING_TRY_UTF8_CHUNK_AT` / `STRING_BUF_TRY_UTF8_CHUNK_AT`
  - `STR_UTF8_CHUNK_AT` / `STRING_UTF8_CHUNK_AT` / `STRING_BUF_UTF8_CHUNK_AT`
- Semantics: walk haystack bytes with `@sa_str_utf8_lossy_next`, merge contiguous valid UTF-8 scalars into one valid chunk, and emit each invalid lossy unit as its own invalid chunk (`valid=0`). Count aliases return the number of such chunks; indexed aliases return `(ok, valid_flag, Slice)` for a caller-selected chunk ordinal and return `ok=0`, `valid=0`, plus an empty slice on misses. This remains a concrete count/caller-indexed view subset rather than Rust's lazy `Utf8Chunks` / `Utf8Chunk` iterator object model, borrow-scoped lifetimes, or full lossy-iterator adapter surface.
- Validation status:
  - Source focused `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_string_macro_surface.sa --filter "utf8 chunks aliases" --jobs 1 --trace-panic`: pass (`1 passed; 74 skipped`).
  - Install sync via installed-std copy of `string.sa`: pass.
  - Installed-state focused `SA_STD_DIR=/home/vscode/.sa/std ./zig-out/bin/sa test` over a minimal harness exercising the same utf8_chunks macros: pass (`1 passed; 0 failed; 0 skipped`).

## Completed: 2026-07-11 str/String encode_utf16 alias batch

- Continued the `StringBuf` / `Vec` Rust API parity audit with String/Vec still treated as the active priority.
- Finding remains: current SA facades are broad but still not complete Rust API coverage.
- Added supportable Rust `str`/`String`/`StringBuf` encode-utf16 aliases:
  - `STR_ENCODE_UTF16_LEN` / `STRING_ENCODE_UTF16_LEN` / `STRING_BUF_ENCODE_UTF16_LEN`
  - `STR_ENCODE_UTF16` / `STRING_ENCODE_UTF16` / `STRING_BUF_ENCODE_UTF16`
- Semantics: count aliases walk UTF-8 scalars and sum `CHAR_LEN_UTF16` units. Encode aliases build an owned `Vec` of `u16` units (`elem_size=2`) by encoding each scalar through `CHAR_TRY_ENCODE_UTF16`, including surrogate pairs for non-BMP characters such as `🙂`. Invalid UTF-8 paths panic in this concrete subset rather than modeling Rust lossy/Result objects. This remains an eager owned-buffer subset rather than Rust's lazy `EncodeUtf16` iterator, generic `Vec<u16>` trait object model, or borrow-checker lifetime model.
- Validation status:
  - Source focused `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_string_macro_surface.sa --filter "encode utf16 aliases" --jobs 1 --trace-panic`: pass (`1 passed; 73 skipped`).
  - Install sync via installed-std copy of `string.sa`: pass.
  - Installed-state focused `/home/vscode/.sa/bin/sa test tests/unit_framework/std_string_macro_surface.sa --filter "encode utf16 aliases" --jobs 1 --trace-panic`: pass (`1 passed; 73 skipped`).

## Completed: 2026-07-11 str/String escape_default/escape_unicode alias batch

- Continued the `StringBuf` / `Vec` Rust API parity audit with String/Vec still treated as the active priority.
- Finding remains: current SA facades are broad but still not complete Rust API coverage.
- Added supportable Rust `str`/`String`/`StringBuf` escape aliases:
  - `STR_ESCAPE_DEFAULT` / `STRING_ESCAPE_DEFAULT` / `STRING_BUF_ESCAPE_DEFAULT`
  - `STR_ESCAPE_UNICODE` / `STRING_ESCAPE_UNICODE` / `STRING_BUF_ESCAPE_UNICODE`
- Semantics: both builders walk UTF-8 scalars with `STR_TRY_CHAR_AT_BYTE`, write each escaped form through the existing char-level `CHAR_ESCAPE_DEFAULT_WRITE` / `CHAR_ESCAPE_UNICODE_WRITE` helpers into a temporary buffer, and append those bytes into an owned `StringBuf`. `escape_default` preserves printable ASCII (except quote/backslash control escapes) and uses special escapes such as `\n` / `\"`; non-printable scalars fall back to lowercase `\u{...}`. `escape_unicode` always emits lowercase `\u{...}` for every scalar. Invalid UTF-8 paths panic in this concrete subset rather than modeling Rust lossy or Result objects. This remains an eager owned-string subset rather than Rust's lazy escape iterators, full `Pattern` machinery, or borrow-checker lifetime model.
- Validation status:
  - Source focused `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_string_macro_surface.sa --filter "escape aliases" --jobs 1 --trace-panic`: pass (`1 passed; 72 skipped`).
  - Install sync via `./tools/install.sh --no-shell` or installed-std copy of `string.sa`: pass.
  - Installed-state focused `/home/vscode/.sa/bin/sa test tests/unit_framework/std_string_macro_surface.sa --filter "escape aliases" --jobs 1 --trace-panic`: pass (`1 passed; 72 skipped`).

## Completed: 2026-07-09 str/String char_indices alias batch

- Continued the `StringBuf` / `Vec` Rust API parity audit with a caller-indexed subset of Rust `str::char_indices`.
- Finding remains: current SA facades are broad but still not complete Rust API coverage.
- Added supportable Rust `str`/`String`/`StringBuf` char-index aliases:
  - `STR_CHAR_INDICES_COUNT` / `STRING_CHAR_INDICES_COUNT` / `STRING_BUF_CHAR_INDICES_COUNT`
  - `STR_TRY_CHAR_INDICES_AT` / `STRING_TRY_CHAR_INDICES_AT` / `STRING_BUF_TRY_CHAR_INDICES_AT`
  - `STR_CHAR_INDICES_AT` / `STRING_CHAR_INDICES_AT` / `STRING_BUF_CHAR_INDICES_AT`
- Semantics: count aliases reuse the existing UTF-8 scalar count, and caller-indexed aliases scan from the start of the slice to return the local `(ok, byte_index, codepoint)` result for a requested scalar ordinal. Missing ordinals or invalid UTF-8 decoding paths return `ok=0`, byte index `0`, and codepoint `0`. This remains a concrete count/caller-indexed subset rather than Rust's lazy `CharIndices` iterator object, tuple object layout, borrow-scoped lifetime model, or invalid-UTF-8 impossible-type invariant.
- Validation status:
  - Source focused `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_string_macro_surface.sa --filter "char indices aliases" --jobs 1 --trace-panic`: pass (`1 passed; 71 skipped`).
  - Full source `std_string_macro_surface.sa`: pass (`72 passed; 0 failed; 0 skipped`).
  - Install sync via `./tools/install.sh --no-shell`: pass.
  - Installed-state focused `/home/vscode/.sa/bin/sa test tests/unit_framework/std_string_macro_surface.sa --filter "char indices aliases" --jobs 1 --trace-panic`: pass (`1 passed; 71 skipped`).

## Completed: 2026-07-09 str/String trim_matches char alias batch

- Continued the `StringBuf` / `Vec` Rust API parity audit with char-pattern counterparts to the slice-needle trim-match aliases.
- Finding remains: current SA facades are broad but still not complete Rust API coverage.
- Added supportable Rust `str`/`String`/`StringBuf` char-pattern trim-match aliases:
  - `STR_TRIM_START_MATCHES_CHAR` / `STRING_TRIM_START_MATCHES_CHAR` / `STRING_BUF_TRIM_START_MATCHES_CHAR`
  - `STR_TRIM_END_MATCHES_CHAR` / `STRING_TRIM_END_MATCHES_CHAR` / `STRING_BUF_TRIM_END_MATCHES_CHAR`
  - `STR_TRIM_MATCHES_CHAR` / `STRING_TRIM_MATCHES_CHAR` / `STRING_BUF_TRIM_MATCHES_CHAR`
- Semantics: aliases encode a valid `u64` Unicode scalar as UTF-8 and delegate to the existing slice-needle `trim_start_matches` / `trim_end_matches` / `trim_matches` helpers. Valid scalars repeatedly strip exact UTF-8 scalar occurrences at the requested edge; invalid scalar values return the original borrowed `Slice` view as a no-op. This remains a concrete char-pattern subset rather than Rust's full generic `Pattern` machinery, closure or slice-of-char patterns, searcher internals, or borrow-checker lifetime model.
- Validation status:
  - Source focused `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_string_macro_surface.sa --filter "trim matches char aliases" --jobs 1 --trace-panic`: pass (`1 passed; 70 skipped`).
  - Full source `std_string_macro_surface.sa`: pass (`71 passed; 0 failed; 0 skipped`).
  - Install sync via `./tools/install.sh --no-shell`: pass.
  - Installed-state focused `/home/vscode/.sa/bin/sa test tests/unit_framework/std_string_macro_surface.sa --filter "trim matches char aliases" --jobs 1 --trace-panic`: pass (`1 passed; 70 skipped`).

## Completed: 2026-07-09 str/String prefix/suffix char alias batch

- Continued the `StringBuf` / `Vec` Rust API parity audit with char-pattern counterparts to `starts_with`, `ends_with`, `strip_prefix`, and `strip_suffix`.
- Finding remains: current SA facades are broad but still not complete Rust API coverage.
- Added supportable Rust `str`/`String`/`StringBuf` char-pattern prefix/suffix aliases:
  - `STR_STARTS_WITH_CHAR` / `STRING_STARTS_WITH_CHAR` / `STRING_BUF_STARTS_WITH_CHAR`
  - `STR_ENDS_WITH_CHAR` / `STRING_ENDS_WITH_CHAR` / `STRING_BUF_ENDS_WITH_CHAR`
  - `STR_TRY_STRIP_PREFIX_CHAR` / `STRING_TRY_STRIP_PREFIX_CHAR` / `STRING_BUF_TRY_STRIP_PREFIX_CHAR`
  - `STR_STRIP_PREFIX_CHAR` / `STRING_STRIP_PREFIX_CHAR` / `STRING_BUF_STRIP_PREFIX_CHAR`
  - `STR_TRY_STRIP_SUFFIX_CHAR` / `STRING_TRY_STRIP_SUFFIX_CHAR` / `STRING_BUF_TRY_STRIP_SUFFIX_CHAR`
  - `STR_STRIP_SUFFIX_CHAR` / `STRING_STRIP_SUFFIX_CHAR` / `STRING_BUF_STRIP_SUFFIX_CHAR`
- Semantics: aliases encode a valid `u64` Unicode scalar as UTF-8 and delegate to the existing slice-needle prefix/suffix helpers. Invalid scalar values return false for predicates or `ok=0` plus an empty `Slice` for strip helpers; misses use the same local `ok=0` empty-slice shape. This remains a concrete char-pattern subset rather than Rust's full generic `Pattern` machinery, `Option<&str>` layout, searcher internals, or borrow-checker lifetime model.
- Validation status:
  - Source focused `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_string_macro_surface.sa --filter "prefix suffix char aliases" --jobs 1 --trace-panic`: pass (`1 passed; 69 skipped`).
  - Full source `std_string_macro_surface.sa`: pass (`70 passed; 0 failed; 0 skipped`).
  - Install sync via `./tools/install.sh --no-shell`: pass.
  - Installed-state focused `/home/vscode/.sa/bin/sa test tests/unit_framework/std_string_macro_surface.sa --filter "prefix suffix char aliases" --jobs 1 --trace-panic`: pass (`1 passed; 69 skipped`).

## Completed: 2026-07-09 str/String split_once char alias batch

- Continued the `StringBuf` / `Vec` Rust API parity audit with a char-pattern counterpart to the split_once/rsplit_once slice-needle aliases.
- Finding remains: current SA facades are broad but still not complete Rust API coverage.
- Added supportable Rust `str`/`String`/`StringBuf` char-pattern split-once aliases:
  - `STR_TRY_SPLIT_ONCE_CHAR` / `STRING_TRY_SPLIT_ONCE_CHAR` / `STRING_BUF_TRY_SPLIT_ONCE_CHAR`
  - `STR_SPLIT_ONCE_CHAR` / `STRING_SPLIT_ONCE_CHAR` / `STRING_BUF_SPLIT_ONCE_CHAR`
  - `STR_TRY_RSPLIT_ONCE_CHAR` / `STRING_TRY_RSPLIT_ONCE_CHAR` / `STRING_BUF_TRY_RSPLIT_ONCE_CHAR`
  - `STR_RSPLIT_ONCE_CHAR` / `STRING_RSPLIT_ONCE_CHAR` / `STRING_BUF_RSPLIT_ONCE_CHAR`
- Semantics: aliases encode a valid `u64` Unicode scalar as UTF-8 and delegate to the existing slice-needle `split_once` / `rsplit_once` helpers. Caller results use the existing local `(ok, left, right)` `Slice` view shape; invalid scalar values or misses return `ok=0` plus empty left/right slices. This remains a concrete one-shot split subset rather than Rust's full generic `Pattern` machinery, `Option<(&str, &str)>` layout, searcher internals, or borrow-checker lifetime model.
- Validation status:
  - Source focused `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_string_macro_surface.sa --filter "split once char aliases" --jobs 1 --trace-panic`: pass (`1 passed; 68 skipped`).
  - Full source `std_string_macro_surface.sa`: pass (`69 passed; 0 failed; 0 skipped`).
  - Install sync via `./tools/install.sh --no-shell`: pass.
  - Installed-state focused `/home/vscode/.sa/bin/sa test tests/unit_framework/std_string_macro_surface.sa --filter "split once char aliases" --jobs 1 --trace-panic`: pass (`1 passed; 68 skipped`).

## Completed: 2026-07-09 str/String splitn char alias batch

- Continued the `StringBuf` / `Vec` Rust API parity audit with the char-pattern counterpart to the splitn/rsplitn slice-needle batch.
- Finding remains: current SA facades are broad but still not complete Rust API coverage.
- Added supportable Rust `str`/`String`/`StringBuf` char-pattern splitn aliases:
  - `STR_SPLIT_N_CHAR_COUNT` / `STRING_SPLIT_N_CHAR_COUNT` / `STRING_BUF_SPLIT_N_CHAR_COUNT`
  - `STR_RSPLIT_N_CHAR_COUNT` / `STRING_RSPLIT_N_CHAR_COUNT` / `STRING_BUF_RSPLIT_N_CHAR_COUNT`
  - `STR_TRY_SPLIT_N_CHAR_AT` / `STRING_TRY_SPLIT_N_CHAR_AT` / `STRING_BUF_TRY_SPLIT_N_CHAR_AT`
  - `STR_SPLIT_N_CHAR_AT` / `STRING_SPLIT_N_CHAR_AT` / `STRING_BUF_SPLIT_N_CHAR_AT`
  - `STR_TRY_RSPLIT_N_CHAR_AT` / `STRING_TRY_RSPLIT_N_CHAR_AT` / `STRING_BUF_TRY_RSPLIT_N_CHAR_AT`
  - `STR_RSPLIT_N_CHAR_AT` / `STRING_RSPLIT_N_CHAR_AT` / `STRING_BUF_RSPLIT_N_CHAR_AT`
- Semantics: aliases encode a valid `u64` Unicode scalar as UTF-8 and delegate to the existing slice-needle `splitn` / `rsplitn` helpers. They preserve the existing local split-count subset: `split_count == 0` returns zero entries or `ok=0`, positive counts cap the number of returned fields, and the current `rsplitn` subset reverse-enumerates the same local splitn field set. Invalid scalar values return zero counts or `ok=0` plus an empty slice. This remains a concrete count/caller-indexed `Slice` subset rather than Rust's lazy iterator objects, full generic `Pattern` machinery, `Option<&str>` layout, full right-to-left `rsplitn` pattern semantics, or borrow-checker lifetime model.
- Validation status:
  - Source focused `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_string_macro_surface.sa --filter "splitn char aliases" --jobs 1 --trace-panic`: pass (`1 passed; 68 skipped`).
  - Full source `std_string_macro_surface.sa`: pass (`68 passed; 0 failed; 0 skipped`).
  - Install sync via `./tools/install.sh --no-shell`: pass.
  - Installed-state focused `/home/vscode/.sa/bin/sa test tests/unit_framework/std_string_macro_surface.sa --filter "splitn char aliases" --jobs 1 --trace-panic`: pass (`1 passed; 68 skipped`).

## Completed: 2026-07-09 str/String split_terminator char alias batch

- Continued the `StringBuf` / `Vec` Rust API parity audit with the char-pattern counterpart to the split-terminator slice-needle batch.
- Finding remains: current SA facades are broad but still not complete Rust API coverage.
- Added supportable Rust `str`/`String`/`StringBuf` char-pattern split-terminator aliases:
  - `STR_SPLIT_TERMINATOR_CHAR_COUNT` / `STRING_SPLIT_TERMINATOR_CHAR_COUNT` / `STRING_BUF_SPLIT_TERMINATOR_CHAR_COUNT`
  - `STR_RSPLIT_TERMINATOR_CHAR_COUNT` / `STRING_RSPLIT_TERMINATOR_CHAR_COUNT` / `STRING_BUF_RSPLIT_TERMINATOR_CHAR_COUNT`
  - `STR_TRY_SPLIT_TERMINATOR_CHAR_AT` / `STRING_TRY_SPLIT_TERMINATOR_CHAR_AT` / `STRING_BUF_TRY_SPLIT_TERMINATOR_CHAR_AT`
  - `STR_SPLIT_TERMINATOR_CHAR_AT` / `STRING_SPLIT_TERMINATOR_CHAR_AT` / `STRING_BUF_SPLIT_TERMINATOR_CHAR_AT`
  - `STR_TRY_RSPLIT_TERMINATOR_CHAR_AT` / `STRING_TRY_RSPLIT_TERMINATOR_CHAR_AT` / `STRING_BUF_TRY_RSPLIT_TERMINATOR_CHAR_AT`
  - `STR_RSPLIT_TERMINATOR_CHAR_AT` / `STRING_RSPLIT_TERMINATOR_CHAR_AT` / `STRING_BUF_RSPLIT_TERMINATOR_CHAR_AT`
- Semantics: aliases encode a valid `u64` Unicode scalar as UTF-8 and delegate to the existing slice-needle `split_terminator` / `rsplit_terminator` helpers. They reuse the terminator count semantics that drop trailing terminator-produced empty fields; invalid scalar values return zero counts or `ok=0` plus an empty slice. This remains a concrete count/caller-indexed `Slice` subset rather than Rust's lazy iterator objects, full generic `Pattern` machinery, `Option<&str>` layout, or borrow-checker lifetime model.
- Validation status:
  - Source focused `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_string_macro_surface.sa --filter "split terminator char aliases" --jobs 1 --trace-panic`: pass (`1 passed; 66 skipped`).
  - Full source `std_string_macro_surface.sa`: pass (`67 passed; 0 failed; 0 skipped`).
  - Install sync via `./tools/install.sh --no-shell`: pass.
  - Installed-state focused `/home/vscode/.sa/bin/sa test tests/unit_framework/std_string_macro_surface.sa --filter "split terminator char aliases" --jobs 1 --trace-panic`: pass (`1 passed; 66 skipped`).

## Completed: 2026-07-09 str/String match_indices char alias batch

- Continued the `StringBuf` / `Vec` Rust API parity audit with the char-pattern counterpart to the match-indices slice-needle batch.
- Finding remains: current SA facades are broad but still not complete Rust API coverage.
- Added supportable Rust `str`/`String`/`StringBuf` char-pattern match-index aliases:
  - `STR_MATCH_INDICES_CHAR_COUNT` / `STRING_MATCH_INDICES_CHAR_COUNT` / `STRING_BUF_MATCH_INDICES_CHAR_COUNT`
  - `STR_RMATCH_INDICES_CHAR_COUNT` / `STRING_RMATCH_INDICES_CHAR_COUNT` / `STRING_BUF_RMATCH_INDICES_CHAR_COUNT`
  - `STR_TRY_MATCH_INDICES_CHAR_AT` / `STRING_TRY_MATCH_INDICES_CHAR_AT` / `STRING_BUF_TRY_MATCH_INDICES_CHAR_AT`
  - `STR_MATCH_INDICES_CHAR_AT` / `STRING_MATCH_INDICES_CHAR_AT` / `STRING_BUF_MATCH_INDICES_CHAR_AT`
  - `STR_TRY_RMATCH_INDICES_CHAR_AT` / `STRING_TRY_RMATCH_INDICES_CHAR_AT` / `STRING_BUF_TRY_RMATCH_INDICES_CHAR_AT`
  - `STR_RMATCH_INDICES_CHAR_AT` / `STRING_RMATCH_INDICES_CHAR_AT` / `STRING_BUF_RMATCH_INDICES_CHAR_AT`
- Semantics: aliases encode a valid `u64` Unicode scalar as UTF-8 and delegate to the existing slice-needle `match_indices` / `rmatch_indices` helpers. Caller-indexed aliases return local `(ok, byte_index, Slice)` values, reverse aliases preserve the original forward byte offset, and invalid scalar values or missing entries return `ok=0`, index `0`, and an empty slice. This remains a concrete count/caller-indexed subset rather than Rust's lazy iterator objects, full generic `Pattern` machinery, `Option<(usize, &str)>` layout, or borrow-checker lifetime model.
- Validation status:
  - Source focused `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_string_macro_surface.sa --filter "match indices char aliases" --jobs 1 --trace-panic`: pass (`1 passed; 65 skipped`).
  - Full source `std_string_macro_surface.sa`: pass (`66 passed; 0 failed; 0 skipped`).
  - Install sync via `./tools/install.sh --no-shell`: pass.
  - Installed-state focused `/home/vscode/.sa/bin/sa test tests/unit_framework/std_string_macro_surface.sa --filter "match indices char aliases" --jobs 1 --trace-panic`: pass (`1 passed; 65 skipped`).
  - Installed-state focused `/home/vscode/.sa/bin/sa test tests/unit_framework/std_string_macro_surface.sa --filter "split and matches char aliases" --jobs 1 --trace-panic`: pass (`1 passed; 65 skipped`).

## Completed: 2026-07-09 str/String split and matches char alias batch

- Continued the `StringBuf` / `Vec` Rust API parity audit with a concrete char-pattern follow-up to the slice-needle split/matches view batch.
- Finding remains: current SA facades are broad but still not complete Rust API coverage.
- Added supportable Rust `str`/`String`/`StringBuf` char-pattern aliases for basic split and matches families:
  - `STR_SPLIT_CHAR_COUNT` / `STRING_SPLIT_CHAR_COUNT` / `STRING_BUF_SPLIT_CHAR_COUNT`
  - `STR_RSPLIT_CHAR_COUNT` / `STRING_RSPLIT_CHAR_COUNT` / `STRING_BUF_RSPLIT_CHAR_COUNT`
  - `STR_MATCHES_CHAR_COUNT` / `STRING_MATCHES_CHAR_COUNT` / `STRING_BUF_MATCHES_CHAR_COUNT`
  - `STR_RMATCHES_CHAR_COUNT` / `STRING_RMATCHES_CHAR_COUNT` / `STRING_BUF_RMATCHES_CHAR_COUNT`
  - `STR_TRY_SPLIT_CHAR_AT` / `STRING_TRY_SPLIT_CHAR_AT` / `STRING_BUF_TRY_SPLIT_CHAR_AT`
  - `STR_SPLIT_CHAR_AT` / `STRING_SPLIT_CHAR_AT` / `STRING_BUF_SPLIT_CHAR_AT`
  - `STR_TRY_RSPLIT_CHAR_AT` / `STRING_TRY_RSPLIT_CHAR_AT` / `STRING_BUF_TRY_RSPLIT_CHAR_AT`
  - `STR_RSPLIT_CHAR_AT` / `STRING_RSPLIT_CHAR_AT` / `STRING_BUF_RSPLIT_CHAR_AT`
  - `STR_TRY_MATCHES_CHAR_AT` / `STRING_TRY_MATCHES_CHAR_AT` / `STRING_BUF_TRY_MATCHES_CHAR_AT`
  - `STR_MATCHES_CHAR_AT` / `STRING_MATCHES_CHAR_AT` / `STRING_BUF_MATCHES_CHAR_AT`
  - `STR_TRY_RMATCHES_CHAR_AT` / `STRING_TRY_RMATCHES_CHAR_AT` / `STRING_BUF_TRY_RMATCHES_CHAR_AT`
  - `STR_RMATCHES_CHAR_AT` / `STRING_RMATCHES_CHAR_AT` / `STRING_BUF_RMATCHES_CHAR_AT`
- Semantics: aliases encode a valid `u64` Unicode scalar as UTF-8 and delegate to the existing slice-needle `split`/`rsplit` and `matches`/`rmatches` helpers. Invalid scalar values return zero counts or `ok=0` plus an empty slice. Results remain concrete count/caller-indexed `Slice` views, not Rust's lazy iterator objects, full generic `Pattern` machinery, `Option<&str>` layout, or borrow-checker lifetime model.
- Validation status:
  - Source focused `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_string_macro_surface.sa --filter "split and matches char aliases" --jobs 1 --trace-panic`: pass (`1 passed; 64 skipped`).
  - Full source `std_string_macro_surface.sa`: pass (`65 passed; 0 failed; 0 skipped`).
  - Install sync via `./tools/install.sh --no-shell`: pass.
  - Installed-state focused `/home/vscode/.sa/bin/sa test tests/unit_framework/std_string_macro_surface.sa --filter "split and matches char aliases" --jobs 1 --trace-panic`: pass (`1 passed; 64 skipped`).

## Completed: 2026-07-09 str/String split_inclusive char alias batch

- Continued the `StringBuf` / `Vec` Rust API parity audit with a concrete char-pattern follow-up to the split-inclusive slice-needle batch.
- Finding remains: current SA facades are broad but still not complete Rust API coverage.
- Added supportable Rust `str`/`String`/`StringBuf` split-inclusive char-pattern aliases:
  - `STR_SPLIT_INCLUSIVE_CHAR_COUNT` / `STRING_SPLIT_INCLUSIVE_CHAR_COUNT` / `STRING_BUF_SPLIT_INCLUSIVE_CHAR_COUNT`
  - `STR_TRY_SPLIT_INCLUSIVE_CHAR_AT` / `STRING_TRY_SPLIT_INCLUSIVE_CHAR_AT` / `STRING_BUF_TRY_SPLIT_INCLUSIVE_CHAR_AT`
  - `STR_SPLIT_INCLUSIVE_CHAR_AT` / `STRING_SPLIT_INCLUSIVE_CHAR_AT` / `STRING_BUF_SPLIT_INCLUSIVE_CHAR_AT`
- Semantics: aliases encode a `u64` Unicode scalar as UTF-8 and delegate to the existing split-inclusive slice-needle subset. Valid char delimiters retain the encoded delimiter at the end of delimiter-terminated fields; trailing delimiters do not produce a final empty field. Invalid scalar values, empty haystacks, and missing indexes return the existing explicit miss shapes (`0` count or `ok=0` plus empty slice). This remains a concrete char-pattern/count-indexed subset rather than Rust's lazy `SplitInclusive` iterator object, generic `Pattern` machinery, `Option<&str>` layout, or borrow-checker lifetime model.
- Validation status:
  - Source focused `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_string_macro_surface.sa --filter "split inclusive char aliases" --jobs 1 --trace-panic`: pass (`1 passed; 63 skipped`).
  - Full source `std_string_macro_surface.sa`: pass (`64 passed; 0 failed; 0 skipped`).
  - Install sync via `./tools/install.sh --no-shell`: pass.
  - Installed-state focused `/home/vscode/.sa/bin/sa test tests/unit_framework/std_string_macro_surface.sa --filter "split inclusive char aliases" --jobs 1 --trace-panic`: pass (`1 passed; 63 skipped`).

## Completed: 2026-07-09 str/String split_inclusive needle alias batch

- Continued the `StringBuf` / `Vec` Rust API parity audit with a String/str slice-needle split family sub-batch.
- Finding remains: current SA facades are broad but still not complete Rust API coverage.
- Added supportable Rust `str`/`String`/`StringBuf` split-inclusive aliases:
  - `STR_SPLIT_INCLUSIVE_NEEDLE_COUNT` / `STRING_SPLIT_INCLUSIVE_NEEDLE_COUNT` / `STRING_BUF_SPLIT_INCLUSIVE_NEEDLE_COUNT`
  - `STR_TRY_SPLIT_INCLUSIVE_NEEDLE_AT` / `STRING_TRY_SPLIT_INCLUSIVE_NEEDLE_AT` / `STRING_BUF_TRY_SPLIT_INCLUSIVE_NEEDLE_AT`
  - `STR_SPLIT_INCLUSIVE_NEEDLE_AT` / `STRING_SPLIT_INCLUSIVE_NEEDLE_AT` / `STRING_BUF_SPLIT_INCLUSIVE_NEEDLE_AT`
- Semantics: aliases enumerate non-overlapping `&str`-needle split fields while retaining the matched delimiter at the end of each delimiter-terminated field. Empty haystacks and empty needles return zero entries, trailing delimiters do not produce a final empty entry, and missing caller indexes return `ok=0` plus an empty slice. This is a concrete count/caller-indexed `Slice` subset rather than Rust's lazy `SplitInclusive` iterator object, generic `Pattern` machinery, `Option<&str>` layout, or borrow-checker lifetime model.
- Validation status:
  - Source focused `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_string_macro_surface.sa --filter "split inclusive needle aliases" --jobs 1 --trace-panic`: pass (`1 passed; 62 skipped`).
  - Full source `std_string_macro_surface.sa`: pass (`63 passed; 0 failed; 0 skipped`).
  - Install sync via `./tools/install.sh --no-shell`: pass.
  - Installed-state focused `/home/vscode/.sa/bin/sa test tests/unit_framework/std_string_macro_surface.sa --filter "split inclusive needle aliases" --jobs 1 --trace-panic`: pass (`1 passed; 62 skipped`).

## Completed: 2026-07-09 str/String match_indices needle alias batch

- Continued the `StringBuf` / `Vec` Rust API parity audit with a String/str slice-needle naming parity sub-batch.
- Finding remains: current SA facades are broad but still not complete Rust API coverage.
- Added supportable Rust `str`/`String`/`StringBuf` match-index aliases:
  - `STR_MATCH_INDICES_NEEDLE_COUNT` / `STRING_MATCH_INDICES_NEEDLE_COUNT` / `STRING_BUF_MATCH_INDICES_NEEDLE_COUNT`
  - `STR_RMATCH_INDICES_NEEDLE_COUNT` / `STRING_RMATCH_INDICES_NEEDLE_COUNT` / `STRING_BUF_RMATCH_INDICES_NEEDLE_COUNT`
  - `STR_TRY_MATCH_INDICES_NEEDLE_AT` / `STRING_TRY_MATCH_INDICES_NEEDLE_AT` / `STRING_BUF_TRY_MATCH_INDICES_NEEDLE_AT`
  - `STR_MATCH_INDICES_NEEDLE_AT` / `STRING_MATCH_INDICES_NEEDLE_AT` / `STRING_BUF_MATCH_INDICES_NEEDLE_AT`
  - `STR_TRY_RMATCH_INDICES_NEEDLE_AT` / `STRING_TRY_RMATCH_INDICES_NEEDLE_AT` / `STRING_BUF_TRY_RMATCH_INDICES_NEEDLE_AT`
  - `STR_RMATCH_INDICES_NEEDLE_AT` / `STRING_RMATCH_INDICES_NEEDLE_AT` / `STRING_BUF_RMATCH_INDICES_NEEDLE_AT`
- Semantics: aliases enumerate non-overlapping `&str`-needle matches, return explicit `(ok, byte_index, Slice)` results for caller-selected entries, and return `ok=0`, index `0`, and an empty slice for absent entries or empty needles. Reverse aliases compute the corresponding forward caller index (`count - 1 - reverse_index`) and keep the original forward byte offset. This is a concrete eager/count-indexed subset rather than Rust's lazy `MatchIndices` / `RMatchIndices` iterator object, generic `Pattern` machinery, `Option<(usize, &str)>` layout, or borrow-checker lifetime model.
- Validation status:
  - Source focused `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_string_macro_surface.sa --filter "match indices needle aliases" --jobs 1 --trace-panic`: pass (`1 passed; 61 skipped`).
  - Full source `std_string_macro_surface.sa`: pass (`62 passed; 0 failed; 0 skipped`).
  - Install sync via `./tools/install.sh --no-shell`: pass.
  - Installed-state focused `/home/vscode/.sa/bin/sa test tests/unit_framework/std_string_macro_surface.sa --filter "match indices needle aliases" --jobs 1 --trace-panic`: pass (`1 passed; 61 skipped`).

## Completed: 2026-07-09 Vec push_within_capacity alias batch

- Continued the `StringBuf` / `Vec` Rust API parity audit with Vec-only naming parity as the active sub-batch.
- Finding remains: current SA facades are broad but still not complete Rust API coverage.
- Added supportable Vec checked push-within-capacity aliases:
  - `VEC_TRY_PUSH_WITHIN_CAPACITY` / `VEC_TRY_PUSH_WITHIN_CAPACITY_U64`
  - `VEC_TRY_PUSH_WITHIN_CAPACITY_MUT` / `VEC_TRY_PUSH_WITHIN_CAPACITY_MUT_U64`
  - `VEC_PUSH_WITHIN_CAPACITY_MUT` / `VEC_PUSH_WITHIN_CAPACITY_MUT_U64`
- Semantics: the `TRY` aliases reuse the existing no-grow capacity check. The mut-return forms insert only when spare capacity exists, return the inserted element pointer on success, and return `ok=0` plus a null pointer when full. This is a concrete local `(ok, ptr)` shape rather than Rust's `Result<&mut T, T>` object layout, generic `T` support, or borrow-checker alias/lifetime model.
- Validation status:
  - Source focused `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_vec_macro_surface.sa --filter "push within capacity aliases" --jobs 1 --trace-panic`: pass (`1 passed; 28 skipped`).
  - Full source `std_vec_macro_surface.sa`: pass (`29 passed; 0 failed; 0 skipped`).
  - Install sync via `./tools/install.sh --no-shell`: pass.
  - Installed-state focused `/home/vscode/.sa/bin/sa test tests/unit_framework/std_vec_macro_surface.sa --filter "push within capacity aliases" --jobs 1 --trace-panic`: pass (`1 passed; 28 skipped`).
  - Full `zig build unit-framework --summary all` was attempted, stayed silent/idle for more than 6 minutes, and was interrupted; it is not counted as a passing gate for this batch.

## Completed: 2026-07-09 str/String splitn count alias and edge-case batch

- Continued the `StringBuf` / `Vec` Rust API parity audit with String/Vec still treated as the active priority.
- Finding remains: current SA facades are broad but still not complete Rust API coverage.
- Added supportable Rust `str`/`String`/`StringBuf` limited split count aliases:
  - `STR_SPLIT_N_NEEDLE_COUNT` / `STRING_SPLIT_N_NEEDLE_COUNT` / `STRING_BUF_SPLIT_N_NEEDLE_COUNT`
  - `STR_RSPLIT_N_NEEDLE_COUNT` / `STRING_RSPLIT_N_NEEDLE_COUNT` / `STRING_BUF_RSPLIT_N_NEEDLE_COUNT`
- Corrected the existing caller-indexed limited split aliases so `split_count == 0` returns `ok=0` with an empty slice instead of subtracting one before checking the count.
- Aligned empty-needle behavior with the existing concrete slice-needle subset: for `split_count > 0`, index `0` returns the whole haystack and later indexes miss. This remains a concrete `&str` needle/count/indexed-view subset; it does not claim Rust's full empty-pattern semantics, generic `Pattern` machinery, lazy `SplitN` / `RSplitN` iterator objects, `Option<&str>` layout, or borrow-checker lifetime enforcement.
- Validation status:
  - Source focused `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_string_macro_surface.sa --filter "splitn count aliases" --jobs 1 --trace-panic`: pass (`1 passed; 60 skipped`).
  - Existing source focused `splitn aliases`: pass (`1 passed; 60 skipped`).
  - Full source `std_string_macro_surface.sa`: pass (`61 passed; 0 failed; 0 skipped`).
  - Install sync via `./tools/install.sh --no-shell`: pass.
  - Installed-state focused `/home/vscode/.sa/bin/sa test tests/unit_framework/std_string_macro_surface.sa --filter "splitn count aliases" --jobs 1 --trace-panic`: pass (`1 passed; 60 skipped`).
  - Full `zig build unit-framework --summary all`: pass (`6/6 steps succeeded; 5/5 tests passed`).

## Completed: 2026-07-09 str/String split_terminator needle alias batch

- Continued the `StringBuf` / `Vec` Rust API parity audit with String/Vec still treated as the active priority.
- Finding remains: current SA facades are broad but still not complete Rust API coverage.
- Added supportable Rust `str`/`String`/`StringBuf` slice-needle split-terminator aliases:
  - `STR_SPLIT_TERMINATOR_NEEDLE_COUNT` / `STRING_SPLIT_TERMINATOR_NEEDLE_COUNT` / `STRING_BUF_SPLIT_TERMINATOR_NEEDLE_COUNT`
  - `STR_RSPLIT_TERMINATOR_NEEDLE_COUNT` / `STRING_RSPLIT_TERMINATOR_NEEDLE_COUNT` / `STRING_BUF_RSPLIT_TERMINATOR_NEEDLE_COUNT`
  - `STR_TRY_SPLIT_TERMINATOR_NEEDLE_AT` / `STRING_TRY_SPLIT_TERMINATOR_NEEDLE_AT` / `STRING_BUF_TRY_SPLIT_TERMINATOR_NEEDLE_AT`
  - `STR_SPLIT_TERMINATOR_NEEDLE_AT` / `STRING_SPLIT_TERMINATOR_NEEDLE_AT` / `STRING_BUF_SPLIT_TERMINATOR_NEEDLE_AT`
- Semantics: count aliases delegate to the existing terminator count, which drops the trailing run of terminator-produced empty fields. Forward caller-indexed aliases return borrowed `Slice` views for indexes below that terminator count and return `ok=0` with an empty slice for out-of-range or empty-needle cases. Reverse count aliases share the same count as forward `split_terminator`. This is a concrete `&str` needle/count/indexed-view subset; it does not claim Rust's generic `Pattern` machinery, lazy `SplitTerminator` / `RSplitTerminator` iterator objects, `Option<&str>` layout, or borrow-checker lifetime enforcement.
- Validation status:
  - Source focused `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_string_macro_surface.sa --filter "split terminator needle aliases" --jobs 1 --trace-panic`: pass (`1 passed; 59 skipped`).
  - Full source `std_string_macro_surface.sa`: pass (`60 passed; 0 failed; 0 skipped`).
  - Install sync via `./tools/install.sh --no-shell`: pass.
  - Installed-state focused `/home/vscode/.sa/bin/sa test tests/unit_framework/std_string_macro_surface.sa --filter "split terminator needle aliases" --jobs 1 --trace-panic`: pass (`1 passed; 59 skipped`).
  - Full `zig build unit-framework --summary all`: pass (`6/6 steps succeeded; 5/5 tests passed`).

## Completed: 2026-07-09 str/String split_ascii_whitespace alias batch

- Continued the `StringBuf` / `Vec` Rust API parity audit with String/Vec still treated as the active priority.
- Finding remains: current SA facades are broad but still not complete Rust API coverage.
- Added supportable Rust `str`/`String`/`StringBuf` ASCII-whitespace token view aliases:
  - `STR_SPLIT_ASCII_WHITESPACE_COUNT` / `STRING_SPLIT_ASCII_WHITESPACE_COUNT` / `STRING_BUF_SPLIT_ASCII_WHITESPACE_COUNT`
  - `STR_TRY_SPLIT_ASCII_WHITESPACE_AT` / `STRING_TRY_SPLIT_ASCII_WHITESPACE_AT` / `STRING_BUF_TRY_SPLIT_ASCII_WHITESPACE_AT`
  - `STR_SPLIT_ASCII_WHITESPACE_AT` / `STRING_SPLIT_ASCII_WHITESPACE_AT` / `STRING_BUF_SPLIT_ASCII_WHITESPACE_AT`
- Semantics: leading/trailing ASCII whitespace is skipped, consecutive ASCII whitespace is collapsed, and each token result is a borrowed `Slice` view into the original string data. Missing indexes return `ok=0` and an empty slice. The implementation delegates whitespace classification to the existing `ASCII_IS_WHITESPACE` predicate, so vertical tab remains non-whitespace. This is a count/caller-indexed view subset, not Rust's lazy `SplitAsciiWhitespace` iterator object, generic pattern machinery, or borrow-checker lifetime model.
- Validation status:
  - Source focused `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_string_macro_surface.sa --filter "split ascii whitespace aliases" --jobs 1 --trace-panic`: pass (`1 passed; 58 skipped`).
  - Full source `std_string_macro_surface.sa`: pass (`59 passed; 0 failed; 0 skipped`).
  - Install sync via `./tools/install.sh --no-shell`: pass.
  - Installed-state focused `/home/vscode/.sa/bin/sa test tests/unit_framework/std_string_macro_surface.sa --filter "split ascii whitespace aliases" --jobs 1 --trace-panic`: pass (`1 passed; 58 skipped`).
  - Full `zig build unit-framework --summary all`: pass (`6/6 steps succeeded; 5/5 tests passed`).

## Completed: 2026-07-09 str/String trim_matches needle alias batch

- Continued the `StringBuf` / `Vec` Rust API parity audit with String/Vec still treated as the active priority.
- Finding remains: current SA facades are broad but still not complete Rust API coverage.
- Added supportable Rust `str`/`String`/`StringBuf` slice-needle trim-match aliases:
  - `STR_TRIM_START_MATCHES_NEEDLE` / `STRING_TRIM_START_MATCHES_NEEDLE` / `STRING_BUF_TRIM_START_MATCHES_NEEDLE`
  - `STR_TRIM_END_MATCHES_NEEDLE` / `STRING_TRIM_END_MATCHES_NEEDLE` / `STRING_BUF_TRIM_END_MATCHES_NEEDLE`
  - `STR_TRIM_MATCHES_NEEDLE` / `STRING_TRIM_MATCHES_NEEDLE` / `STRING_BUF_TRIM_MATCHES_NEEDLE`
- Semantics: non-empty `&str` needles are repeatedly stripped from the requested edge and return borrowed `Slice` views into the original string data. Empty needles return the original slice unchanged to avoid zero-length match loops. This batch does not claim Rust's generic `Pattern` machinery, closure/char/slice-of-char pattern variants, lazy iterator object models, or borrow-checker lifetime enforcement.
- Validation status:
  - Source focused `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_string_macro_surface.sa --filter "trim matches aliases" --jobs 1 --trace-panic`: pass (`1 passed; 57 skipped`).
  - Full source `std_string_macro_surface.sa`: pass (`58 passed; 0 failed; 0 skipped`).
  - Install sync via `./tools/install.sh --no-shell`: pass.
  - Installed-state focused `/home/vscode/.sa/bin/sa test tests/unit_framework/std_string_macro_surface.sa --filter "trim matches aliases" --jobs 1 --trace-panic`: pass (`1 passed; 57 skipped`).
  - Full `zig build unit-framework --summary all`: pass (`6/6 steps succeeded; 5/5 tests passed`).

## Active: 2026-07-09 full-test runtime optimization follow-up

- Feature completed: plugin installer failure preflight now runs pure checks before building temporary plugin dynamic libraries.
- `src/plugins.zig` now checks declared interface files, declared asset files, and installed extern-symbol conflicts before `buildPluginProject()`.
- Post-build validation still keeps artifact-dependent checks after the copy/build path: dynamic symbol smoke and artifact static policy.
- This preserves the intended `plugin-host-smoke` behavior: tests still exercise plugin install flows, but all installs are isolated under `std.testing.tmpDir()` with test-local `SA_PLUGINS_HOME=state`; they do not install into the real user plugin home.
- Focused verification:
  - `tools/test_steps_timed.sh --timeout 420 --log-dir logs/test_steps/plugin-opt-20260709T070747Z plugin-host-smoke`: pass, `12/12 tests passed`, `elapsed=170.743s`.
  - Previous logged full-pass baseline for the same step was `209.569s`, so the observed step-level improvement is `38.826s` (`18.5%`) despite this run also rebuilding the Zig test binary after `src/plugins.zig` changed.
  - Most visible internal wins: duplicate extern symbols across installed plugins about `33.936s -> 13.809s`; duplicate extern symbols inside installed plugin about `18.447s -> 0.007s`.
- Overall progress estimate after this feature: `15%` of the full-test runtime optimization follow-up. Remaining dominant steps are still `plugin-host-smoke`, `sa-std-runtime`, `wasm-matrix`, `unit-framework`, and `std-smoke`.
- Feature completed: `sa-std-runtime` now reuses the build-system `sa_std` static archive instead of rebuilding the same runtime library inside each C demo test.
- `build.zig` makes the `sa-std-runtime` step depend on the `artifacts/sa_std/libsa_std.a` refresh, and `tests/sa_std_runtime.zig` copies that archive into each temp test directory before linking each C demo.
- The C demo compile/link/run coverage is preserved; only 13 repeated `zig build-lib src/runtime/sa_std.zig ...` invocations were removed from the test body.
- Focused verification:
  - `tools/test_steps_timed.sh --timeout 420 --log-dir logs/test_steps/sa-std-runtime-opt-20260709T073000Z sa-std-runtime`: pass, `14/14 tests passed`, `elapsed=33.532s`.
  - Previous logged full-pass baseline for the same step was `145.815s`, so the observed step-level improvement is `112.283s` (`77.0%`).
- Overall progress estimate after this feature: `35%` of the full-test runtime optimization follow-up. Current observed cumulative savings versus the logged full-pass baseline are about `151.109s` across `plugin-host-smoke` and `sa-std-runtime`.
- Feature completed: full-test step logs now have better long-run visibility and failure triage.
- `tools/test_steps_timed.sh` now supports `--heartbeat SEC` / `SA_TEST_STEP_HEARTBEAT`, defaulting to 30s, and prints `RUNNING` lines with step index, elapsed time, log byte count, timestamp, and log path while a step is still active.
- The runner now supports `--fail-tail-lines N` / `SA_TEST_STEP_FAIL_TAIL_LINES`, defaulting to 80 lines, and prints the tail of a failed or timed-out step log directly into `summary.log` and the console.
- Each run now writes `results.tsv` for machine-readable per-step status and `environment.txt` with repo, git head/branch, dirty-line count, jobs, timeout, heartbeat, fail-tail, and log-dir metadata.
- START/PASS/FAIL/TIMEOUT lines now include `index=current/total`, which makes full-suite progress visible without counting manually.
- Focused verification, without running the full suite:
  - `bash -n tools/test_steps_timed.sh`: pass.
  - `tools/test_steps_timed.sh --list`: pass.
  - `tools/test_steps_timed.sh --heartbeat 1 --timeout 180 --log-dir logs/test_steps/log-quality-pkg-20260709T080000Z pkg-core-test`: pass, generated `results.tsv` and `environment.txt`.
  - intentional invalid step with `--fail-tail-lines 20`: exit status preserved as `1`, and summary printed the failing log tail.
  - `tools/test_steps_timed.sh --heartbeat 5 --timeout 180 --log-dir logs/test_steps/log-quality-heartbeat-20260709T080000Z sa-std-runtime`: pass, emitted a `RUNNING` heartbeat at 5s.
- Overall progress estimate after this feature: `45%` of the full-test runtime/logging optimization follow-up.
- Feature completed: `unit-framework` now emits file-level START/END/error logs for SA unit files instead of only printing elapsed time after a file finishes.
- `tests/unit_framework/runner.zig` now logs each macro surface file with mode, jobs, elapsed time, stdout byte count, and stderr byte count. Queued process-mode files include `index=current/total` so parallel worker progress is visible.
- Unexpected per-file errors now log `END status=error` rather than a bare `[unit-framework] FAIL`, avoiding false failure markers from the intentional queued-worker negative test while still making the errored file obvious.
- Focused verification, without running the full suite:
  - `tools/test_steps_timed.sh --heartbeat 10 --timeout 240 --log-dir logs/test_steps/unit-framework-log2-20260709T082000Z unit-framework`: pass, `5/5 tests passed`, `elapsed=96.501s` including Zig test rebuild.
  - Grep verified per-file `START`/`END` lines with `stdout_bytes` / `stderr_bytes`.
  - Grep verified no `[unit-framework] FAIL` line remained in the passing step log.
- Overall progress estimate after this feature: `55%` of the full-test runtime/logging optimization follow-up.
- Follow-up consistency pass: `feature_suite.sa`, `assert_diag.sa`, and `mock_io_test.sa` now use the same START/END/error log shape instead of legacy elapsed-only lines.
- Focused verification:
  - `tools/test_steps_timed.sh --heartbeat 10 --timeout 240 --log-dir logs/test_steps/unit-framework-log3-20260709T083000Z unit-framework`: pass, `5/5 tests passed`, `elapsed=101.646s` including Zig test rebuild.
  - Grep verified the three top-level SA execution paths now have START/END lines.
  - Grep verified the old `feature_suite.sa all modes elapsed`, `assert_diag.sa elapsed`, and `mock_io_test.sa elapsed` formats are absent from the log.
- Overall progress estimate after this feature: `60%` of the full-test runtime/logging optimization follow-up.
- Feature completed: `wasm-matrix` now prints an end-of-step summary ranking the slowest demos and slowest phases.
- `tests/wasm_matrix_smoke.zig` now accumulates `demo`, `build-exe`, `native-run`, `build-wasm`, and `wasm-run` timings for every demo and prints aggregate phase totals plus top-10 rankings.
- Focused verification:
  - `tools/test_steps_timed.sh --heartbeat 15 --timeout 420 --log-dir logs/test_steps/wasm-matrix-summary2-20260709T084000Z wasm-matrix`: pass, `1/1 tests passed`, `elapsed=146.982s` including Zig test rebuild.
  - Summary output: `demos=110 total_demo_ms=103970 build_exe_ms=93156 native_run_ms=502 build_wasm_ms=1711 wasm_run_ms=8188`.
  - The top slow phases were all `build-exe`, with the slowest examples at `2154ms` for `demos/rosetta/35_iterator_fold/main.sa` and `2106ms` for `demos/rosetta/81_kv_store/main.sa`.
- Overall progress estimate after this feature: `65%` of the full-test runtime/logging optimization follow-up. The next real runtime target is repeated `build-exe` cost inside `wasm-matrix`, not wasm execution.
- Feature completed: default `wasm-matrix` now follows the WASM-fast path and shares the project cache root.
- CLI compile options now accept `--project-root <dir>` / `--project-root=<dir>` so direct `build-exe`, `build-wasm`, `build-obj`, `run`, and `test` style commands can use an explicit package/cache root instead of deriving one from each source path.
- `tests/wasm_matrix_smoke.zig` now passes the repo root as `--project-root` and runs native `build-exe` only for a representative sanity subset by default. Full native equivalence remains available with `SA_WASM_MATRIX_NATIVE_ALL=1`.
- Focused verification:
  - Cold shared-cache run: `tools/test_steps_timed.sh --heartbeat 15 --timeout 420 --log-dir logs/test_steps/wasm-fast-default-20260709T091500Z wasm-matrix`: pass, `elapsed=212.385s`, `native_checked=6`, `build_exe_ms=18404`, `build_wasm_ms=138154`.
  - Hot shared-cache run: `tools/test_steps_timed.sh --heartbeat 10 --timeout 300 --log-dir logs/test_steps/wasm-fast-hot-20260709T092000Z wasm-matrix`: pass, `elapsed=59.623s`, `native_checked=6`, `build_exe_ms=6255`, `build_wasm_ms=43033`, `wasm_run_ms=7754`.
  - Compared with the previous logged `wasm-matrix` pass `146.982s`, the hot-cache default path saves `87.359s` (`59.4%`).
- Version metadata prepared for release: `build.zig.zon` now reports `0.0.4`, and `CHANGELOG.md` records the `0.0.3 -> 0.0.4` changes.
- Overall progress estimate after this feature: `75%` of the full-test runtime/logging optimization follow-up.
- Release workflow polish: `.githooks/pre-push` now runs heavy timed release checks only when the current push contains a tag ref. Branch-only pushes skip locally, while `git push origin main 0.0.4` still checks once because branch and tag are pushed in the same Git invocation.
- Focused verification only, no full suite: `bash -n .githooks/pre-push`; simulated branch-only push skipped; simulated tag push with `SA_PRE_PUSH_SKIP_CHECKS=1` took the tag path and skipped only at the self-test guard.
- Overall progress estimate after this feature: `78%` of the full-test runtime/logging optimization follow-up.
- GitHub Action cost reduction: `.github/workflows/release.yml` no longer uses the aggregate `zig build test -Drelease-safe` gate, because that implicitly runs the slow `wasm-matrix` step. The release core check now lists non-WASM build steps explicitly, adds Zig artifact caching, and uses workflow concurrency to cancel older runs for the same ref.
- Follow-up fix: GitHub Actions rejected the first cache key template at the cache step, so the workflow cache keys now use `github.sha` plus broad restore keys instead of `hashFiles(...)`. This avoids template-time failures before the non-WASM gate starts.
- Verification scope: static workflow inspection only; confirmed the release workflow no longer invokes `zig build test` or the `wasm-matrix` build step, and `git diff --check` passed after this cache-key fix. WASM matrix remains available for focused local runs through `zig build wasm-matrix`.
- Overall progress estimate after this feature: `80%` of the full-test runtime/logging optimization follow-up.

## Active: 2026-07-09 logged full-test step runner

- Added `tools/test_steps_timed.sh` as the diagnostic entry point for the `zig build test` dependency set.
- The runner prints per-step START/PASS/FAIL/TIMEOUT logs with UTC timestamps, command lines, elapsed time, per-step timeout, slowest-step ranking, and a final summary.
- The runner now also persists full logs:
  - default log directory: `logs/test_steps/<utc timestamp>`; this path is ignored by git.
  - override: `--log-dir <dir>` or `SA_TEST_STEP_LOG_DIR=<dir>`.
  - each step gets its own numbered log file plus `summary.log`, and console summary lines include `log=...` / `log_dir=...` paths.
- Default coverage mirrors the `build.zig` `test` dependency set through named steps:
  - `lib-root-smoke`, `plugin-host-smoke`, `pkg-core-test`, `wasm-matrix`, `bc2sa-smoke`, `workspace-smoke`, `trap-baseline`, `unit-framework`, runtime/std/network steps, `std-smoke`, `whitepaper-lint`, demos, and `hubproxy-test`.
  - `whitepaper-lint` is used instead of `smoke` for the whitepaper smoke artifact so the runner does not repeat the std-smoke artifacts hidden behind the `smoke` aggregate step.
- Validation completed without running the full suite:
  - `bash -n tools/test_steps_timed.sh`: pass.
  - `tools/test_steps_timed.sh --list`: pass.
  - `tools/test_steps_timed.sh --timeout 180 lib-root-smoke pkg-core-test`: pass; `lib-root-smoke` took `50.989s`, `pkg-core-test` took `1.419s`, and the runner printed the slowest-step summary.
  - `tools/test_steps_timed.sh --timeout 180 --log-dir /tmp/sci-test-steps-logs pkg-core-test`: pass; generated `summary.log` and `01-pkg-core-test.log`.
  - failure-path check with an invalid step preserved exit status `1` and generated both `summary.log` and a step log containing the Zig error output.
- Added deeper logs inside the known heavy Zig test binaries:
  - `tests/plugin_host_smoke.zig` now prints `[plugin-host-smoke] START/END test="..." elapsed=...ms` for each of its 12 Zig tests. Focused validation with `tools/test_steps_timed.sh --timeout 420 plugin-host-smoke` passed in `230.858s`; the runtime body exposed the slowest tests around duplicate extern checks and skills optional dependency checks at about `30s` each.
  - `tests/wasm_matrix_smoke.zig` now prints `[wasm-matrix] START/END demo=... phase=... elapsed=...ms` for each demo and for `build-exe`, `native-run`, `build-wasm`, and `wasm-run`. Focused validation with `tools/test_steps_timed.sh --timeout 420 wasm-matrix` passed in `149.039s`; output now separates the initial Zig test build cost from per-demo SA build/run cost.
- Milestone logged full dependency pass completed without invoking blind aggregate `zig build test`:
  - Command: `tools/test_steps_timed.sh --continue --timeout 420 --log-dir logs/test_steps/full-20260709T060333Z`
  - Result: `passed=22 failed=0 timeout=0 total=22 elapsed=789.076s`.
  - Slowest steps: `plugin-host-smoke` `209.569s`, `sa-std-runtime` `145.815s`, `wasm-matrix` `121.868s`, `unit-framework` `57.407s`, `std-smoke` `57.155s`.
  - Full logs are persisted under ignored `logs/test_steps/full-20260709T060333Z`, with `summary.log` plus one numbered step log per dependency.
- Remaining follow-up is optional optimization work, not required to complete the logging milestone: if more precision is needed later, add phase timing inside plugin installer helper paths and `sa-std-runtime` internals.

## Active: 2026-07-09 large SAB focused test performance

- Baseline was committed before starting this slice: `ee50937 Add extended string macro surfaces`.
- Checkpoint commit before this continuation: `94d841c Optimize SAB test listing path`.
- New issue record: `docs/issue14_test_filter_large_sab_performance.md`.
- Real downstream measurements from `/home/vscode/projects/sla_ecs/.sla-cache/sab` show the split:
  - Small `parallel_table_erased-ab6b0062c772adb.sab` focused compile-only is close to target: about `elapsed=1.28 maxrss=70252`; focused list is about `elapsed=0.33 maxrss=57136`.
  - Large `world_table_erased-5d5e95eb4646a2ce.sab` focused list is still about `elapsed=8.87 maxrss=385224`; focused compile-only is about `elapsed=30.61 maxrss=465592`, with a repeat around `elapsed=33.51 maxrss=464808`.
- Current root cause found in `src/cli.zig`: `executeTest()` compiles/verifies the full source before collecting `test_meta` or applying filters/list mode. For `.sab`, `compileSource()` calls `loadSabFlat()` and `referee.verifyWithOptions()` over the whole decoded module, so `--list --filter` still pays full large-module verification.
- Completed focused compile-only/list milestone:
  - `.sab --list --filter` now uses metadata-only test signature decoding and avoids full decode/verify.
  - `.sab + explicit test selection + --compile-only` now collects selected tests before compile, prunes the SAB to selected-test reachability, uses borrowed SAB symbol pools, trusts the selected SAB as preverified for compile-only, and skips linking the throwaway test executable after LLVM bitcode emit succeeds.
  - ReleaseFast real downstream gates with local `./zig-out/bin/sa`: large `world_table_erased --list --filter` `elapsed=0.05 maxrss=56576`; large `world_table_erased --compile-only --filter --no-incremental` `elapsed=0.82 maxrss=167528`; small `parallel_table_erased --compile-only --filter --no-incremental` `elapsed=0.17 maxrss=70104`.
  - Installed `/home/vscode/.sa/bin/sa` gates after `tools/install.sh --no-shell`: large list `elapsed=0.07 maxrss=56960`; large compile-only `elapsed=1.00 maxrss=168132`; small compile-only `elapsed=0.26 maxrss=70664`.
  - Large compile-only profile: `compile=496.834ms`, `emit=476.366ms`, `link=0.000ms`, `total=985.677ms`.
- Full test status: initial `timeout 600s zig build test --summary all` did not pass; failures are recorded in `docs/issue15_full_test_suite_failures_20260709.md`.
- Issue 15 focused fixes completed:
  - `sa_std/string.sa` splitn/rsplitn limited split aliases now pass the source focused gate with `SA_STD_DIR=/home/vscode/projects/sci/sa_std`.
  - `src/plugins.zig` formal runtime policy now blocks privileged dev-installed plugins outside `SA_PLUGIN_DEV`, and full `zig build plugin-host-smoke --summary all` passes (`12/12 tests passed`).
  - `src/runtime/sa_net_uring.zig` loopback netx test no longer hangs on client thread joins; focused netx test and `zig build sa-std-unit --summary all` pass (`63/63 tests passed`).
- Test gate status: each `zig build test` dependency was rerun individually with explicit step logging and passed; this avoids masking timeout ownership inside the monolithic full-suite command.
- Install/final focused gate status:
  - `tools/install.sh --no-shell` passed.
  - Installed large SAB compile-only focused gate: `elapsed=0.75 maxrss=167856`.
  - Installed large SAB list focused gate: `elapsed=0.04 maxrss=56960`.
  - Installed small SAB compile-only focused gate: `elapsed=0.13 maxrss=70912`.
- Remaining: run-mode selected SAB still verifies/links; full lazy/partial SAB instruction decode is still open.

## Completed: 2026-07-08 str/String reverse slice-needle split/matches batch

- Continued the `StringBuf` / `Vec` Rust API parity audit with String/Vec still treated as the active priority.
- Finding remains: current SA facades are broad but still not complete Rust API coverage.
- Added supportable Rust `str`/`String`/`STRING_BUF` reverse slice-needle (`&str` needle) split and matches view aliases:
  - `STR_RSPLIT_NEEDLE_COUNT` / `STRING_RSPLIT_NEEDLE_COUNT` / `STRING_BUF_RSPLIT_NEEDLE_COUNT`
  - `STR_RMATCHES_NEEDLE_COUNT` / `STRING_RMATCHES_NEEDLE_COUNT` / `STRING_BUF_RMATCHES_NEEDLE_COUNT`
  - `STR_TRY_RSPLIT_NEEDLE_AT` / `STRING_TRY_RSPLIT_NEEDLE_AT` / `STRING_BUF_TRY_RSPLIT_NEEDLE_AT` / `STR_RSPLIT_NEEDLE_AT` / `STRING_RSPLIT_NEEDLE_AT` / `STRING_BUF_RSPLIT_NEEDLE_AT`
  - `STR_TRY_RMATCHES_NEEDLE_AT` / `STRING_TRY_RMATCHES_NEEDLE_AT` / `STRING_BUF_TRY_RMATCHES_NEEDLE_AT` / `STR_RMATCHES_NEEDLE_AT` / `STRING_RMATCHES_NEEDLE_AT` / `STRING_BUF_RMATCHES_NEEDLE_AT`
- Semantics: reverse count aliases reuse the existing forward non-overlapping count. Reverse indexed helpers compute the corresponding forward index (`count - 1 - reverse_index`) and delegate to the existing forward caller-indexed `Slice` view helpers, so empty fields, trailing/consecutive needles, empty-needle split behavior, and empty-needle matches behavior stay aligned with the forward batch. These aliases return explicit `(ok, Slice)` shapes rather than Rust lazy `RSplit` / `RMatches` iterator adapters or Rust `Option<&str>` values. This batch does not claim Rust `Pattern` trait machinery, `&[u8]`-needle or closure pattern variants, `rsplit_terminator`, `splitn`/`rsplitn` limited-count variants, or borrow-scoped reference lifetimes.
- Validation status:
  - Source focused `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_string_macro_surface.sa --filter "split needle aliases"`: pass (`1 passed; 55 skipped`).
  - Install sync via `tools/install.sh --no-shell`: pass.
  - Installed-state focused `./zig-out/bin/sa test tests/unit_framework/std_string_macro_surface.sa --filter "split needle aliases"`: pass (`1 passed; 55 skipped`).
  - Full test suites intentionally not run for this batch per user instruction to test only newly added/narrow coverage.

## Completed: 2026-07-08 str/String slice-needle split/matches batch

- Continued the `StringBuf` / `Vec` Rust API parity audit with String/Vec still treated as the active priority.
- Finding remains: current SA facades are broad but still not complete Rust API coverage.
- Added supportable Rust `str`/`String`/`STRING_BUF` slice-needle (`&str` needle) split and matches view helpers over the existing `STR_COUNT` non-overlapping scan:
  - `STR_SPLIT_NEEDLE_COUNT` / `STRING_SPLIT_NEEDLE_COUNT` / `STRING_BUF_SPLIT_NEEDLE_COUNT` (matches-plus-one `split` count)
  - `STR_SPLIT_NEEDLE_TERM_COUNT` / `STRING_SPLIT_NEEDLE_TERM_COUNT` / `STRING_BUF_SPLIT_NEEDLE_TERM_COUNT` (`split_terminator` count, subtracting the trailing run of needle-terminated empty fields)
  - `STR_MATCHES_NEEDLE_COUNT` / `STRING_MATCHES_NEEDLE_COUNT` / `STRING_BUF_MATCHES_NEEDLE_COUNT` (count of non-overlapping needle matches)
  - `STR_TRY_SPLIT_NEEDLE_AT` / `STRING_TRY_SPLIT_NEEDLE_AT` / `STRING_BUF_TRY_SPLIT_NEEDLE_AT` / `STR_SPLIT_NEEDLE_AT` / `STRING_SPLIT_NEEDLE_AT` / `STRING_BUF_SPLIT_NEEDLE_AT` (caller-indexed `Slice` views over split fields, `ok=1`/`ok=0`)
  - `STR_TRY_MATCHES_NEEDLE_AT` / `STRING_TRY_MATCHES_NEEDLE_AT` / `STRING_BUF_TRY_MATCHES_NEEDLE_AT` / `STR_MATCHES_NEEDLE_AT` / `STRING_MATCHES_NEEDLE_AT` / `STRING_BUF_MATCHES_NEEDLE_AT` (caller-indexed `Slice` views over each matched needle occurrence)
- Semantics: the count helpers reuse the `STR_COUNT` non-overlapping slice scan. `STR_SPLIT_NEEDLE_COUNT` returns the field count (`matches + 1`) rather than modeling Rust's lazy `Split` iterator. `STR_SPLIT_NEEDLE_TERM_COUNT` computes the base `split` field count and then subtracts the trailing run of needle-terminated empty fields, so `"a:b::"` with `:` yields 2 terms; an empty string or an empty needle yields 0 terms. `STR_TRY_SPLIT_NEEDLE_AT` walks the haystack, splitting on non-overlapping needle matches, and returns the caller-indexed field as a borrowed `Slice` view with `ok=1` when present and `ok=0` with an empty `Slice` otherwise; empty needles yield the whole haystack at index 0 and absent thereafter. `STR_MATCHES_NEEDLE_COUNT` is the count of non-overlapping needle matches equivalent to Rust `str::matches().count()`, and `STR_TRY_MATCHES_NEEDLE_AT` returns the caller-indexed match occurrence as a `Slice` view; empty needles yield zero matches. The aliases return explicit `(ok, Slice)` shapes rather than Rust lazy `Split`/`RSplit`/`SplitTerminator`/`Matches` iterator adapters or Rust `Option<&str>` values. This batch does not claim Rust `Pattern` trait machinery, `&[u8]`-needle or closure pattern variants, the reverse (`rsplit`/`rsplitn`/`rmatches`/`rsplit_terminator`) view subsets, the `splitn`/`rsplitn` limited-count variants, or borrow-scoped reference lifetimes.
- Validation status:
  - Source focused `std_string_macro_surface.sa --filter "split needle aliases"`: pass (`1 passed; 55 skipped`).
  - Full source `std_string_macro_surface.sa`: pass (`56 passed; 0 failed; 0 skipped`).
  - Installed-state focused `std_string_macro_surface.sa --filter "split needle aliases"`: pass (`1 passed; 55 skipped`).
  - Install sync via `tools/install.sh --no-shell` completed; `/home/vscode/.sa/std/string.sa` exposes the new macros.

## Completed: 2026-07-08 str/String replace/replacen char-pattern batch
## Completed: 2026-07-08 str/String replace/replacen char-pattern batch

- Continued the `StringBuf` / `Vec` Rust API parity audit with String/Vec still treated as the active priority.
- Finding remains: current SA facades are broad but still not complete Rust API coverage.
- Added supportable Rust replace helpers over the existing `STRING_BUF_REPLACE` scan plus a new limited-replace scan:
  - `STRING_BUF_REPLACE_N` (limited non-overlapping slice-needle replace)
  - `STR_REPLACE` / `STRING_REPLACE` (borrowed `str`/`String` -> owned `StringBuf` alias of the full replace)
  - `STR_REPLACEN` / `STRING_REPLACEN` (limited replace)
  - `STRING_BUF_REPLACE_CHAR` / `STRING_BUF_REPLACE_N_CHAR` (char-pattern full/limited replace)
  - `STR_REPLACE_CHAR` / `STRING_REPLACE_CHAR` / `STR_REPLACEN_CHAR` / `STRING_REPLACEN_CHAR`
  - `STRING_BUF_REMOVE_MATCHES_CHAR` (char-pattern removal alias over `STRING_BUF_REMOVE_MATCHES`)
- Semantics: the shared `STR_ENCODE_CHAR_SLICE` helper encodes a `char` (`u64` codepoint) into its UTF-8 byte subsequence so the existing slice-needle replace scan is reused. `STRING_BUF_REPLACE_N` replaces at most `limit` non-overlapping matches; a zero `limit` skips matching and copies the source verbatim, mirroring `replacen`. The empty-needle path copies the source in place rather than modeling Rust's panic or the matches-of-empty interpolation. The borrowed `STR_REPLACE`/`STR_REPLACEN` aliases return an owned `StringBuf` rather than a Rust `String`, because SA does not introduce a distinct owned-`String` resource kind. This batch does not claim Rust `Result` object layout, generic `Pattern` trait machinery, `&[u8]`/closure pattern variants, panic behavior, borrow-checker alias/lifetime semantics, allocator-parametric behavior, or full trait-object coverage.
- Validation status:
  - Source focused `std_string_macro_surface.sa --filter "replace aliases"`: pass (`1 passed; 54 skipped`).
  - Full source `std_string_macro_surface.sa`: pass (`55 passed; 0 failed; 0 skipped`).
  - Installed-state focused `std_string_macro_surface.sa --filter "replace aliases"`: pass (`1 passed; 54 skipped`).
  - Installed-state focused `std_string_macro_surface.sa --filter "char pattern aliases"`: pass (`1 passed; 54 skipped`).

## Completed: 2026-07-08 str/String char-pattern find/count batch

- Continued the `StringBuf` / `Vec` Rust API parity audit with String/Vec still treated as the active priority.
- Finding remains: current SA facades are broad but still not complete Rust API coverage.
- Added supportable Rust `str`/`String` char-pattern search aliases that lower a single Unicode scalar (`char`, provided as a `u64` codepoint) to its UTF-8 byte subsequence and reuse the existing slice-needle scan helpers:
  - `STR_CONTAINS_CHAR` / `STRING_CONTAINS_CHAR` / `STRING_BUF_CONTAINS_CHAR`
  - `STR_TRY_FIND_CHAR` / `STR_FIND_CHAR` / `STRING_TRY_FIND_CHAR` / `STRING_FIND_CHAR` / `STRING_BUF_FIND_CHAR`
  - `STR_TRY_RFIND_CHAR` / `STR_RFIND_CHAR` / `STRING_TRY_RFIND_CHAR` / `STRING_RFIND_CHAR` / `STRING_BUF_RFIND_CHAR`
  - `STR_COUNT_CHAR` / `STRING_COUNT_CHAR` / `STRING_BUF_COUNT_CHAR`
- Added a new non-overlapping slice-needle count helper that the `*_CHAR` count macros delegate to, plus the matching borrowed surface:
  - `STR_COUNT` / `STRING_COUNT`
- Semantics: the shared `STR_ENCODE_CHAR_SLICE` helper encodes a `char` into a 4-byte stack buffer via `CHAR_TRY_ENCODE_UTF8` and wraps it as a borrowed `Slice`; invalid scalar values produce an empty `Slice` and the delegated scan reports `ok=0`. The search returns explicit `(ok, byte_index)` shapes for `find`/`rfind` and `(count)` for `count` rather than Rust `Option<usize>` values. Because the haystack is valid UTF-8, any `&str`/`char` subsequence match lands on a char boundary, so byte-index results match Rust's `find`/`rfind` byte offsets. The empty-needle case for `STR_COUNT` returns `0` rather than modeling Rust's `'a matches("".count())` returning `len+1`. This batch does not claim Rust `Option`/`Result` object layout, generic `Pattern` trait machinery, `&[u8]`/closure pattern variants, borrow-checker alias/lifetime semantics, allocator-parametric behavior, or full trait-object coverage.
- Validation status:
  - Source focused `std_string_macro_surface.sa --filter "char pattern aliases"`: pass (`1 passed; 53 skipped`).
  - Full source `std_string_macro_surface.sa`: pass (`54 passed; 0 failed; 0 skipped`).
  - Installed-state focused `std_string_macro_surface.sa --filter "char pattern aliases"`: pass (`1 passed; 53 skipped`).

## Completed: 2026-07-08 str/String from_utf8 view alias batch

- Continued the `StringBuf` / `Vec` Rust API parity audit with String/Vec still treated as the active priority.
- Finding remains: current SA facades are broad but still not complete Rust API coverage.
- Added supportable borrowed UTF-8 view aliases for Rust `str::from_utf8`, `str::from_utf8_mut`, and unchecked naming:
  - `STR_TRY_FROM_UTF8` / `STR_FROM_UTF8`
  - `STR_TRY_FROM_UTF8_MUT` / `STR_FROM_UTF8_MUT`
  - `STR_FROM_UTF8_UNCHECKED` / `STR_FROM_UTF8_UNCHECKED_MUT`
  - matching `STRING_*` aliases
- Semantics: checked forms return the local `(ok, Slice)` shape. Invalid UTF-8 returns `ok=0` and an empty `Slice`; unchecked forms preserve the input pointer and length. This does not claim Rust `Result<&str, Utf8Error>` / `Result<&mut str, Utf8Error>` object layout, unsafe type-state enforcement, borrow-checker alias/lifetime semantics, allocator-parametric behavior, or full trait-object coverage.
- Validation status:
  - Source focused `std_string_macro_surface.sa --filter "from_utf8 view aliases"`: pass.
  - Installed-state focused `std_string_macro_surface.sa --filter "from_utf8 view aliases"`: pass.
  - Full test suites intentionally not run for this batch per user instruction to test only newly added/narrow coverage.

## Completed: 2026-07-07 Vec peek_mut alias batch

- Continued the `StringBuf` / `Vec` Rust API parity audit with String/Vec still treated as the active priority.
- Finding remains: current SA facades are broad but still not complete Rust API coverage.
- Added supportable Vec `peek_mut` naming aliases for Rust's current nightly-only `vec_peek_mut` method:
  - `VEC_PEEK_MUT`
  - `VEC_PEEK_MUT_U64`
- Semantics: these aliases reuse the existing `VEC_TRY_PEEK_MUT*` raw-pointer helper and preserve the local `(ok, ptr)` result shape. Empty vectors return `ok=0` and a null pointer. This does not claim Rust `Option<&mut T>` object layout, peek guard behavior, generic `T` coverage, allocator-parametric behavior, or borrow-checker alias rules.
- Validation status:
  - Source focused `std_vec_macro_surface.sa --filter "peek_mut aliases"`: pass.
  - Installed-state focused `std_vec_macro_surface.sa --filter "peek_mut aliases"`: pass.
  - Full test suites intentionally not run for this batch per user instruction to test only newly added/narrow coverage.

## Completed: 2026-07-07 str/String as_mut_ptr alias batch

- Continued the `StringBuf` / `Vec` Rust API parity audit with String/Vec still treated as the active priority.
- Finding remains: current SA facades are broad but still not complete Rust API coverage.
- Added supportable `str` / `String` mutable pointer naming aliases:
  - `STR_AS_MUT_PTR`
  - `STRING_AS_MUT_PTR`
- Semantics: these aliases reuse the existing byte pointer view and return the same raw pointer shape as `STR_AS_PTR`. Owned `StringBuf` already exposes `STRING_BUF_AS_MUT_PTR` over its backing vector buffer. This does not claim Rust scoped `&mut str` borrow rules, alias guarantees, UTF-8 mutation invariant enforcement, allocator-parametric behavior, or full trait-object coverage.
- Validation status:
  - Source focused `std_string_macro_surface.sa --filter "as_mut_ptr aliases"`: pass.
  - Installed-state focused `std_string_macro_surface.sa --filter "as_mut_ptr aliases"`: pass.
  - Full test suites intentionally not run for this batch per user instruction to test only newly added/narrow coverage.

## Completed: 2026-07-07 str/String as_ascii alias batch

- Continued the `StringBuf` / `Vec` Rust API parity audit with String/Vec still treated as the active priority.
- Finding remains: current SA facades are broad but still not complete Rust API coverage.
- Added supportable `str` / `String` / `StringBuf` ASCII view naming aliases for Rust's current nightly-only `ascii_char` methods:
  - `STR_AS_ASCII` / `STRING_AS_ASCII`
  - `STR_AS_ASCII_UNCHECKED` / `STRING_AS_ASCII_UNCHECKED`
  - `STRING_BUF_AS_ASCII`
  - `STRING_BUF_AS_ASCII_UNCHECKED`
- Semantics: checked forms reuse the existing ASCII slice validation helper and return local `(ok, Slice)` views, failing with `ok=0` and an empty view for non-ASCII bytes. Unchecked forms preserve the original pointer/length and rely on the caller's ASCII precondition. This does not claim Rust `Option<&[AsciiChar]>` object layout, distinct typed ASCII slice references, unsafe type-state enforcement, allocator-parametric behavior, stable API status, or full trait-object coverage.
- Validation status:
  - Source focused `std_string_macro_surface.sa --filter "as_ascii aliases"`: pass.
  - Installed-state focused `std_string_macro_surface.sa --filter "as_ascii aliases"`: pass.
  - Full test suites intentionally not run for this batch per user instruction to test only newly added/narrow coverage.

## Completed: 2026-07-07 str/String split_at_mut alias batch

- Continued the `StringBuf` / `Vec` Rust API parity audit with String/Vec still treated as the active priority.
- Finding remains: current SA facades are broad but still not complete Rust API coverage.
- Added supportable `str` / `String` / `StringBuf` split-at mutable naming aliases:
  - `STR_SPLIT_AT_MUT` / `STRING_SPLIT_AT_MUT`
  - `STR_SPLIT_AT_MUT_CHECKED` / `STRING_SPLIT_AT_MUT_CHECKED`
  - `STR_TRY_SPLIT_AT_MUT_CHECKED` / `STRING_TRY_SPLIT_AT_MUT_CHECKED`
  - `STRING_BUF_SPLIT_AT_MUT`
  - `STRING_BUF_SPLIT_AT_MUT_CHECKED`
  - `STRING_BUF_TRY_SPLIT_AT_MUT_CHECKED`
- Semantics: these delegate to the existing UTF-8 char-boundary checked split helper and preserve the local `(ok, left, right)` result shape over `Slice` views. They do not claim Rust panic behavior, `Option` object layout, scoped `&mut str` borrow rules, allocator-parametric behavior, or full trait-object coverage.
- Validation status:
  - Source focused `std_string_macro_surface.sa --filter "split_at_mut aliases"`: pass.
  - Installed-state focused `std_string_macro_surface.sa --filter "split_at_mut aliases"`: pass.
  - Full test suites intentionally not run for this batch per user instruction to test only newly added/narrow coverage.

## Completed: 2026-07-07 str/String ASCII case conversion batch

- Continued the `StringBuf` / `Vec` Rust API parity audit with String/Vec still treated as the active priority.
- Finding remains: current SA facades are broad but still not complete Rust API coverage.
- Added supportable `str` / slice-string ASCII case mutation/copy helpers:
  - `STR_MAKE_ASCII_UPPERCASE` / `STRING_MAKE_ASCII_UPPERCASE`
  - `STR_MAKE_ASCII_LOWERCASE` / `STRING_MAKE_ASCII_LOWERCASE`
  - `STR_TO_ASCII_UPPERCASE` / `STRING_TO_ASCII_UPPERCASE`
  - `STR_TO_ASCII_LOWERCASE` / `STRING_TO_ASCII_LOWERCASE`
- Semantics: mutable helpers operate on a caller-provided mutable `Slice` view, and `to_ascii_*` helpers materialize an owned `StringBuf` copy. ASCII letters are converted and non-ASCII UTF-8 bytes are preserved. This does not claim Unicode case folding, locale behavior, borrow-checker alias rules, allocator-parametric behavior, or full trait-object coverage.
- Validation status:
  - Source focused `std_string_macro_surface.sa --filter "ascii case conversion"`: pass.
  - Installed-state focused `std_string_macro_surface.sa --filter "ascii case conversion"`: pass.
  - Full test suites intentionally not run for this batch per user instruction to test only newly added/narrow coverage.

## Completed: 2026-07-07 StringBuf ASCII case mutation batch

- Continued the `StringBuf` / `Vec` Rust API parity audit with String/Vec still treated as the active priority.
- Finding remains: current SA facades are broad but still not complete Rust API coverage.
- Added supportable StringBuf ASCII case mutation/copy helpers:
  - `STRING_BUF_MAKE_ASCII_UPPERCASE`
  - `STRING_BUF_MAKE_ASCII_LOWERCASE`
  - `STRING_BUF_TO_ASCII_UPPERCASE`
  - `STRING_BUF_TO_ASCII_LOWERCASE`
- Semantics: these reuse the existing ASCII slice case conversion helper over the StringBuf byte view. ASCII letters are changed in place or in a cloned copy; non-ASCII UTF-8 bytes are preserved. This does not claim Unicode case folding, locale behavior, borrow-checker alias rules, allocator-parametric behavior, or full trait-object coverage.
- Validation status:
  - Source focused `std_string_macro_surface.sa --filter "buffer ascii case alias"`: pass.
  - Installed-state focused `std_string_macro_surface.sa --filter "buffer ascii case alias"`: pass.
  - Full test suites intentionally not run for this batch per user instruction to test only newly added/narrow coverage.

## Completed: 2026-07-07 StringBuf parity documentation sync batch

- Continued the `StringBuf` / `Vec` Rust API parity audit with String/Vec still treated as the active priority.
- Finding remains: current SA facades are broad but still not complete Rust API coverage.
- Synced the stale StringBuf implemented-surface report in `docs/std_missing.md` with current `sa_std/string.sa` source facts:
  - Added current default/reference/deref conveniences.
  - Added pointer-range, raw-parts, leak, and mutable-view surfaces.
  - Added conversion/cloning, eager char/string extension and extraction, strict/lossy UTF constructor, retain/drain/remove, replace-first/last, and index-range categories already present in source and historical test coverage.
- Clarified by placement that these are concrete SA helper surfaces and still do not imply Rust trait objects, lazy iterator models, allocator-parametric behavior, full generic `Pattern`, or borrow-checker alias semantics.
- Validation status:
  - Runtime tests intentionally not run because this batch has no runtime or test source changes.
  - `git diff --check`: pass.

## Completed: 2026-07-07 StringBuf char mutation documentation sync batch

- Continued the `StringBuf` / `Vec` Rust API parity audit with String/Vec still treated as the active priority.
- Finding remains: current SA facades are broad but still not complete Rust API coverage.
- Synced the stale `docs/std_missing.md` String scope note for owned `StringBuf` char mutation helpers:
  - `STRING_BUF_TRY_PUSH_CHAR` / `STRING_BUF_PUSH_CHAR`
  - `STRING_BUF_TRY_INSERT_CHAR` / `STRING_BUF_INSERT_CHAR`
- Semantics: current source encodes any valid Unicode scalar value as UTF-8 before appending or inserting, and rejects invalid scalar values such as surrogate codepoints. Insert still goes through the existing checked insert path, so byte indexes must be in bounds and at a valid UTF-8 character boundary. This does not claim Rust `Pattern` machinery, borrow-checker alias rules, allocator-parametric behavior, or full trait-object coverage.
- Validation status:
  - Runtime tests intentionally not run because this batch has no runtime or test source changes.
  - `git diff --check`: pass.

## Completed: 2026-07-07 StringBuf try split-at documentation sync batch

- Continued the `StringBuf` / `Vec` Rust API parity audit with String/Vec still treated as the active priority.
- Finding remains: current SA facades are broad but still not complete Rust API coverage. Remaining unsupported or intentionally unclaimed areas include allocator-parametric APIs, Box/Cow conversions, real lazy iterator object models, const-generic array ownership/extraction shapes, `Vec::into_chunks` / `into_flattened` / `recycle`, Vec whole-object mutable borrow semantics beyond local metadata pointer facades / generic `T: PartialEq/Ord/Hash`, `String::as_mut_vec` Rust borrow-checker semantics and UTF-8 invariant enforcement, `u128`/`i128` formatting, float default-format parity, and full generic trait-object coverage.
- Current source already contains the supportable `String` deref-to-str split-at `TRY` alias, and this batch synced the parity documentation for it:
  - `STRING_BUF_TRY_SPLIT_AT`
- Semantics: this delegates through `STRING_BUF_SPLIT_AT`, which uses the existing UTF-8 char-boundary checked split helper, and preserves the local `(ok, left, right)` result shape. It does not claim Rust panic behavior, `Option` object layout, borrow-checker alias rules, allocator-parametric behavior, or full trait-object coverage.
- Validation status:
  - Source focused `std_string_macro_surface.sa --filter "buffer try split aliases"`: pass (`1 passed; 47 skipped`).
  - Full test suites intentionally not run for this batch per user instruction; no runtime or test source changed in this documentation-sync batch.
- Install sync status:
  - `./tools/install.sh --no-shell`: pass.
  - Installed-state focused `std_string_macro_surface.sa --filter "buffer try split aliases"`: pass (`1 passed; 47 skipped`).

## Completed: 2026-07-07 Vec parity documentation sync batch

- Continued the `StringBuf` / `Vec` Rust API parity audit with String/Vec still treated as the active priority.
- Finding remains: current SA facades are broad but still not complete Rust API coverage.
- Synced the stale Vec implemented-surface report in `docs/std_missing.md` with current `sa_std/vec.sa` source facts:
  - Added current default/reference/deref conveniences.
  - Added pointer-range, leak, raw-parts, NonNull parts, and spare-capacity surfaces.
  - Added conversion/cloning, mut-return, `retain_mut`, and explicit U64 alias categories that were already present in source and historical test coverage.
- Clarified the remaining Vec gap as generic `retain` / `retain_mut` beyond concrete U64 predicate forms, lazy `drain`/`splice` iterator semantics, and generic element support.
- Validation status:
  - Runtime tests intentionally not run because this batch has no runtime or macro implementation changes.
  - `git diff --check`: pass.

## Completed: 2026-07-07 Vec first/last U64 alias batch

- Continued the `StringBuf` / `Vec` Rust API parity audit with String/Vec still treated as the active priority.
- Finding remains: current SA facades are broad but still not complete Rust API coverage. Remaining unsupported or intentionally unclaimed areas include allocator-parametric APIs, Box/Cow conversions, real lazy iterator object models, const-generic array ownership/extraction shapes, `Vec::into_chunks` / `into_flattened` / `recycle`, Vec whole-object mutable borrow semantics beyond local metadata pointer facades / generic `T: PartialEq/Ord/Hash`, `String::as_mut_vec` Rust borrow-checker semantics and UTF-8 invariant enforcement, `u128`/`i128` formatting, float default-format parity, and full generic trait-object coverage.
- Added supportable Vec deref-to-slice first/last explicit U64 aliases:
  - `VEC_FIRST_U64`
  - `VEC_LAST_U64`
- Semantics: these delegate to the existing front/back helpers and preserve local scalar `u64` result shapes. They do not claim Rust `Option<&T>` object layout, generic `T` coverage, borrow-checker alias rules, allocator-parametric behavior, or full trait-object coverage.
- Validation status:
  - Source focused `std_vec_macro_surface.sa --filter "vec first last u64 aliases"`: pass (`1 passed; 26 skipped`).
  - Full test suites intentionally not run for this batch per user instruction to test only newly added coverage.
- Install sync status:
  - `./tools/install.sh --no-shell`: pass.
  - Installed-state focused `std_vec_macro_surface.sa --filter "vec first last u64 aliases"`: pass (`1 passed; 26 skipped`).

## Completed: 2026-07-07 StringBuf try split alias batch

- Continued the `StringBuf` / `Vec` Rust API parity audit with String/Vec still treated as the active priority.
- Finding remains: current SA facades are broad but still not complete Rust API coverage. Remaining unsupported or intentionally unclaimed areas include allocator-parametric APIs, Box/Cow conversions, real lazy iterator object models, const-generic array ownership/extraction shapes, `Vec::into_chunks` / `into_flattened` / `recycle`, Vec whole-object mutable borrow semantics beyond local metadata pointer facades / generic `T: PartialEq/Ord/Hash`, `String::as_mut_vec` Rust borrow-checker semantics and UTF-8 invariant enforcement, `u128`/`i128` formatting, float default-format parity, and full generic trait-object coverage.
- Added supportable `String` deref-to-str `TRY` split aliases:
  - `STRING_BUF_TRY_SPLIT_ONCE`
  - `STRING_BUF_TRY_RSPLIT_ONCE`
  - `STRING_BUF_TRY_SPLIT_AT_CHECKED`
- Semantics: these delegate through `STRING_BUF_AS_STR` to existing `str` helpers and preserve local `(ok, left, right)` result shapes. They do not claim Rust lazy searcher objects, generic `Pattern`, `Option<(&str, &str)>` object layout, panic behavior, borrow-checker alias rules, allocator-parametric behavior, or full trait-object coverage.
- Validation status:
  - Source focused `std_string_macro_surface.sa --filter "buffer try split aliases"`: pass (`1 passed; 47 skipped`).
  - Full test suites intentionally not run for this batch per user instruction to test only newly added coverage.
- Install sync status:
  - `./tools/install.sh --no-shell`: pass.
  - Installed-state focused `std_string_macro_surface.sa --filter "buffer try split aliases"`: pass (`1 passed; 47 skipped`).

## Completed: 2026-07-07 StringBuf ASCII case alias batch

- Continued the `StringBuf` / `Vec` Rust API parity audit with String/Vec still treated as the active priority.
- Finding remains: current SA facades are broad but still not complete Rust API coverage. Remaining unsupported or intentionally unclaimed areas include allocator-parametric APIs, Box/Cow conversions, real lazy iterator object models, const-generic array ownership/extraction shapes, `Vec::into_chunks` / `into_flattened` / `recycle`, Vec whole-object mutable borrow semantics beyond local metadata pointer facades / generic `T: PartialEq/Ord/Hash`, `String::as_mut_vec` Rust borrow-checker semantics and UTF-8 invariant enforcement, `u128`/`i128` formatting, float default-format parity, and full generic trait-object coverage.
- Added supportable `String` deref-to-str ASCII case-insensitive equality alias:
  - `STRING_BUF_EQ_IGNORE_ASCII_CASE`
- Semantics: this delegates through `STRING_BUF_AS_STR` to the existing `str` helper and preserves a local boolean result shape. It does not claim Rust Unicode case folding, borrow-checker alias rules, allocator-parametric behavior, or full trait-object coverage.
- Validation status:
  - Source focused `std_string_macro_surface.sa --filter "buffer ascii case alias"`: pass (`1 passed; 46 skipped`).
  - Full test suites intentionally not run for this batch per user instruction to test only newly added coverage.
- Install sync status:
  - `./tools/install.sh --no-shell`: pass.
  - Installed-state focused `std_string_macro_surface.sa --filter "buffer ascii case alias"`: pass (`1 passed; 46 skipped`).

## Completed: 2026-07-07 StringBuf find alias batch

- Continued the `StringBuf` / `Vec` Rust API parity audit with String/Vec still treated as the active priority.
- Finding remains: current SA facades are broad but still not complete Rust API coverage. Remaining unsupported or intentionally unclaimed areas include allocator-parametric APIs, Box/Cow conversions, real lazy iterator object models, const-generic array ownership/extraction shapes, `Vec::into_chunks` / `into_flattened` / `recycle`, Vec whole-object mutable borrow semantics beyond local metadata pointer facades / generic `T: PartialEq/Ord/Hash`, `String::as_mut_vec` Rust borrow-checker semantics and UTF-8 invariant enforcement, `u128`/`i128` formatting, float default-format parity, and full generic trait-object coverage.
- Added supportable `String` deref-to-str find aliases:
  - `STRING_BUF_TRY_FIND`
  - `STRING_BUF_TRY_RFIND`
  - `STRING_BUF_TRY_FIND_BYTE`
  - `STRING_BUF_FIND_BYTE`
  - `STRING_BUF_TRY_RFIND_BYTE`
  - `STRING_BUF_RFIND_BYTE`
- Semantics: these delegate through `STRING_BUF_AS_STR` to existing `str` helpers and preserve local `(ok, index)` result shapes. They do not claim Rust lazy searcher objects, generic `Pattern`, `Option<usize>` object layout, borrow-checker alias rules, allocator-parametric behavior, or full trait-object coverage.
- Validation status:
  - Source focused `std_string_macro_surface.sa --filter "buffer find aliases"`: pass (`1 passed; 45 skipped`).
  - Full test suites intentionally not run for this batch per user instruction to test only newly added coverage.
- Install sync status:
  - `./tools/install.sh --no-shell`: pass.
  - Installed-state focused `std_string_macro_surface.sa --filter "buffer find aliases"`: pass (`1 passed; 45 skipped`).

## Completed: 2026-07-07 StringBuf trim alias batch

- Continued the `StringBuf` / `Vec` Rust API parity audit with String/Vec still treated as the active priority.
- Finding remains: current SA facades are broad but still not complete Rust API coverage. Remaining unsupported or intentionally unclaimed areas include allocator-parametric APIs, Box/Cow conversions, real lazy iterator object models, const-generic array ownership/extraction shapes, `Vec::into_chunks` / `into_flattened` / `recycle`, Vec whole-object mutable borrow semantics beyond local metadata pointer facades / generic `T: PartialEq/Ord/Hash`, `String::as_mut_vec` Rust borrow-checker semantics and UTF-8 invariant enforcement, `u128`/`i128` formatting, float default-format parity, and full generic trait-object coverage.
- Added supportable `String` deref-to-str strip/trim aliases:
  - `STRING_BUF_TRY_STRIP_PREFIX`
  - `STRING_BUF_TRY_STRIP_SUFFIX`
  - `STRING_BUF_TRIM_PREFIX`
  - `STRING_BUF_TRIM_SUFFIX`
  - `STRING_BUF_TRIM_ASCII_START`
  - `STRING_BUF_TRIM_ASCII_END`
  - `STRING_BUF_TRIM_ASCII`
- Semantics: these delegate through `STRING_BUF_AS_STR` to existing `str` helpers and preserve local `(ok, slice)` or borrowed-slice result shapes. They do not claim Rust Unicode whitespace trim, generic `Pattern`, `Option<&str>` object layout, borrow-checker alias rules, allocator-parametric behavior, or full trait-object coverage.
- Validation status:
  - Source focused `std_string_macro_surface.sa --filter "buffer trim aliases"`: pass (`1 passed; 44 skipped`).
  - Full test suites intentionally not run for this batch per user instruction to test only newly added coverage.
- Install sync status:
  - `./tools/install.sh --no-shell`: pass.
  - Installed-state focused `std_string_macro_surface.sa --filter "buffer trim aliases"`: pass (`1 passed; 44 skipped`).

## Completed: 2026-07-07 StringBuf split line alias batch

- Continued the `StringBuf` / `Vec` Rust API parity audit with String/Vec still treated as the active priority.
- Finding remains: current SA facades are broad but still not complete Rust API coverage. Remaining unsupported or intentionally unclaimed areas include allocator-parametric APIs, Box/Cow conversions, real lazy iterator object models, const-generic array ownership/extraction shapes, `Vec::into_chunks` / `into_flattened` / `recycle`, Vec whole-object mutable borrow semantics beyond local metadata pointer facades / generic `T: PartialEq/Ord/Hash`, `String::as_mut_vec` Rust borrow-checker semantics and UTF-8 invariant enforcement, `u128`/`i128` formatting, float default-format parity, and full generic trait-object coverage.
- Added supportable `String` deref-to-str byte split / line view aliases:
  - `STRING_BUF_COUNT_BYTE`
  - `STRING_BUF_SPLIT_BYTE_COUNT`
  - `STRING_BUF_TRY_SPLIT_BYTE_AT`
  - `STRING_BUF_SPLIT_BYTE_AT`
  - `STRING_BUF_LINE_COUNT`
  - `STRING_BUF_TRY_LINE_AT`
  - `STRING_BUF_LINE_AT`
- Semantics: these delegate through `STRING_BUF_AS_STR` to existing `str` helpers and preserve local count or `(ok, slice)` result shapes. They do not claim Rust lazy iterator adapters, generic `Pattern`, `Option<&str>` object layout, borrow-checker alias rules, allocator-parametric behavior, or full trait-object coverage.
- Validation status:
  - Source focused `std_string_macro_surface.sa --filter "buffer split line aliases"`: pass (`1 passed; 43 skipped`).
  - Full test suites intentionally not run for this batch per user instruction to test only newly added coverage.
- Install sync status:
  - `./tools/install.sh --no-shell`: pass.
  - Installed-state focused `std_string_macro_surface.sa --filter "buffer split line aliases"`: pass (`1 passed; 43 skipped`).

## Completed: 2026-07-07 StringBuf UTF-8 view alias batch

- Continued the `StringBuf` / `Vec` Rust API parity audit with String/Vec still treated as the active priority.
- Finding remains: current SA facades are broad but still not complete Rust API coverage. Remaining unsupported or intentionally unclaimed areas include allocator-parametric APIs, Box/Cow conversions, real lazy iterator object models, const-generic array ownership/extraction shapes, `Vec::into_chunks` / `into_flattened` / `recycle`, Vec whole-object mutable borrow semantics beyond local metadata pointer facades / generic `T: PartialEq/Ord/Hash`, `String::as_mut_vec` Rust borrow-checker semantics and UTF-8 invariant enforcement, `u128`/`i128` formatting, float default-format parity, and full generic trait-object coverage.
- Added supportable `String` deref-to-str UTF-8 byte/char view aliases:
  - `STRING_BUF_BYTE_LEN`
  - `STRING_BUF_TRY_BYTE_AT`
  - `STRING_BUF_IS_UTF8`
  - `STRING_BUF_CHAR_COUNT`
  - `STRING_BUF_TRY_CHAR_AT`
  - `STRING_BUF_TRY_CHAR_AT_BYTE`
  - `STRING_BUF_TRY_CHAR_RANGE_AT`
- Semantics: these delegate through `STRING_BUF_AS_STR` to existing `str` helpers and preserve local boolean, count, codepoint, byte-length, or `(ok, slice)` result shapes. They do not claim Rust lazy iterator adapters, `Option` / `Result` object layouts, borrow-checker alias rules, allocator-parametric behavior, or full trait-object coverage.
- Validation status:
  - Source focused `std_string_macro_surface.sa --filter "buffer utf8 view aliases"`: pass (`1 passed; 42 skipped`).
  - Full test suites intentionally not run for this batch per user instruction to test only newly added coverage.
- Install sync status:
  - `./tools/install.sh --no-shell`: pass.
  - Installed-state focused `std_string_macro_surface.sa --filter "buffer utf8 view aliases"`: pass (`1 passed; 42 skipped`).

## Completed: 2026-07-07 StringBuf char-boundary alias batch

- Continued the `StringBuf` / `Vec` Rust API parity audit with String/Vec still treated as the active priority.
- Finding remains: current SA facades are broad but still not complete Rust API coverage. Remaining unsupported or intentionally unclaimed areas include allocator-parametric APIs, Box/Cow conversions, real lazy iterator object models, const-generic array ownership/extraction shapes, `Vec::into_chunks` / `into_flattened` / `recycle`, Vec whole-object mutable borrow semantics beyond local metadata pointer facades / generic `T: PartialEq/Ord/Hash`, `String::as_mut_vec` Rust borrow-checker semantics and UTF-8 invariant enforcement, `u128`/`i128` formatting, float default-format parity, and full generic trait-object coverage.
- Added supportable `String` deref-to-str ASCII / char-boundary aliases:
  - `STRING_BUF_IS_ASCII`
  - `STRING_BUF_IS_CHAR_BOUNDARY`
  - `STRING_BUF_FLOOR_CHAR_BOUNDARY`
  - `STRING_BUF_CEIL_CHAR_BOUNDARY`
- Semantics: these delegate through `STRING_BUF_AS_STR` to existing `str` helpers and preserve local boolean or scalar-index result shapes. They do not claim Rust iterator adapters, `Pattern`, borrow-checker alias rules, allocator-parametric behavior, or full trait-object coverage.
- Validation status:
  - Source focused `std_string_macro_surface.sa --filter "buffer char boundary aliases"`: pass (`1 passed; 41 skipped`).
  - Full test suites intentionally not run for this batch per user instruction to test only newly added coverage.
- Install sync status:
  - `./tools/install.sh --no-shell`: pass.
  - Installed-state focused `std_string_macro_surface.sa --filter "buffer char boundary aliases"`: pass (`1 passed; 41 skipped`).

## Completed: 2026-07-07 StringBuf try range alias batch

- Continued the `StringBuf` / `Vec` Rust API parity audit with String/Vec still treated as the active priority.
- Finding remains: current SA facades are broad but still not complete Rust API coverage. Remaining unsupported or intentionally unclaimed areas include allocator-parametric APIs, Box/Cow conversions, real lazy iterator object models, const-generic array ownership/extraction shapes, `Vec::into_chunks` / `into_flattened` / `recycle`, Vec whole-object mutable borrow semantics beyond local metadata pointer facades / generic `T: PartialEq/Ord/Hash`, `String::as_mut_vec` Rust borrow-checker semantics and UTF-8 invariant enforcement, `u128`/`i128` formatting, float default-format parity, and full generic trait-object coverage.
- Added supportable `String` deref-to-str checked range `TRY` aliases:
  - `STRING_BUF_TRY_GET_RANGE`
  - `STRING_BUF_TRY_GET_PREFIX`
  - `STRING_BUF_TRY_GET_SUFFIX`
  - `STRING_BUF_TRY_GET_RANGE_TO`
  - `STRING_BUF_TRY_GET_RANGE_FROM`
  - `STRING_BUF_TRY_GET_RANGE_BETWEEN`
- Semantics: these delegate through `STRING_BUF_AS_STR` to UTF-8 char-boundary checked `str` range helpers and preserve local `(ok, slice)` result shapes. They do not claim Rust `Option<&str>` object layout, borrow-checker alias rules, allocator-parametric behavior, or full trait-object coverage.
- Validation status:
  - Source focused `std_string_macro_surface.sa --filter "buffer try range aliases"`: pass (`1 passed; 40 skipped`).
  - Full test suites intentionally not run for this batch per user instruction to test only newly added coverage.
- Install sync status:
  - `./tools/install.sh --no-shell`: pass.
  - Installed-state focused `std_string_macro_surface.sa --filter "buffer try range aliases"`: pass (`1 passed; 40 skipped`).

## Completed: 2026-07-07 StringBuf range alias batch

- Continued the `StringBuf` / `Vec` Rust API parity audit with String/Vec still treated as the active priority.
- Finding remains: current SA facades are broad but still not complete Rust API coverage. Remaining unsupported or intentionally unclaimed areas include allocator-parametric APIs, Box/Cow conversions, real lazy iterator object models, const-generic array ownership/extraction shapes, `Vec::into_chunks` / `into_flattened` / `recycle`, Vec whole-object mutable borrow semantics beyond local metadata pointer facades / generic `T: PartialEq/Ord/Hash`, `String::as_mut_vec` Rust borrow-checker semantics and UTF-8 invariant enforcement, `u128`/`i128` formatting, float default-format parity, and full generic trait-object coverage.
- Added supportable `String` deref-to-str checked range aliases:
  - `STRING_BUF_GET_RANGE`
  - `STRING_BUF_GET_PREFIX`
  - `STRING_BUF_GET_SUFFIX`
  - `STRING_BUF_GET_RANGE_TO`
  - `STRING_BUF_GET_RANGE_FROM`
  - `STRING_BUF_GET_RANGE_BETWEEN`
- Semantics: these delegate through `STRING_BUF_AS_STR` to UTF-8 char-boundary checked `str` range helpers and preserve local `(ok, slice)` result shapes. They do not claim Rust `Option<&str>` object layout, borrow-checker alias rules, allocator-parametric behavior, or full trait-object coverage.
- Validation status:
  - Source focused `std_string_macro_surface.sa --filter "buffer range aliases"`: pass (`1 passed; 39 skipped`).
  - Full test suites intentionally not run for this batch per user instruction to test only newly added coverage.
- Install sync status:
  - `./tools/install.sh --no-shell`: pass.
  - Installed-state focused `std_string_macro_surface.sa --filter "buffer range aliases"`: pass (`1 passed; 39 skipped`).

## Completed: 2026-07-07 StringBuf split_at alias batch

- Continued the `StringBuf` / `Vec` Rust API parity audit with String/Vec still treated as the active priority.
- Finding remains: current SA facades are broad but still not complete Rust API coverage. Remaining unsupported or intentionally unclaimed areas include allocator-parametric APIs, Box/Cow conversions, real lazy iterator object models, const-generic array ownership/extraction shapes, `Vec::into_chunks` / `into_flattened` / `recycle`, Vec whole-object mutable borrow semantics beyond local metadata pointer facades / generic `T: PartialEq/Ord/Hash`, `String::as_mut_vec` Rust borrow-checker semantics and UTF-8 invariant enforcement, `u128`/`i128` formatting, float default-format parity, and full generic trait-object coverage.
- Added supportable `String` deref-to-str split-at aliases:
  - `STRING_BUF_SPLIT_AT`
  - `STRING_BUF_SPLIT_AT_CHECKED`
- Semantics: both delegate through `STRING_BUF_AS_STR` to UTF-8 char-boundary checked split helpers and preserve local `(ok, left, right)` result shapes. They do not claim Rust panic behavior, `Option` object layout, borrow-checker alias rules, allocator-parametric behavior, or full trait-object coverage.
- Validation status:
  - Source focused `std_string_macro_surface.sa --filter "buffer split_at aliases"`: pass (`1 passed; 38 skipped`).
  - Full test suites intentionally not run for this batch per user instruction to test only newly added coverage.
- Install sync status:
  - `./tools/install.sh --no-shell`: pass.
  - Installed-state focused `std_string_macro_surface.sa --filter "buffer split_at aliases"`: pass (`1 passed; 38 skipped`).

## Completed: 2026-07-07 StringBuf split-once alias batch

- Continued the `StringBuf` / `Vec` Rust API parity audit with String/Vec still treated as the active priority.
- Finding remains: current SA facades are broad but still not complete Rust API coverage. Remaining unsupported or intentionally unclaimed areas include allocator-parametric APIs, Box/Cow conversions, real lazy iterator object models, const-generic array ownership/extraction shapes, `Vec::into_chunks` / `into_flattened` / `recycle`, Vec whole-object mutable borrow semantics beyond local metadata pointer facades / generic `T: PartialEq/Ord/Hash`, `String::as_mut_vec` Rust borrow-checker semantics and UTF-8 invariant enforcement, `u128`/`i128` formatting, float default-format parity, and full generic trait-object coverage.
- Added supportable `String` deref-to-str split-once aliases:
  - `STRING_BUF_SPLIT_ONCE`
  - `STRING_BUF_RSPLIT_ONCE`
- Semantics: these delegate through `STRING_BUF_AS_STR` to the existing concrete str slice helpers and preserve local `(ok, left, right)` result shapes. They do not claim Rust generic `Pattern`, `Option<(&str, &str)>` object layout, searcher/iterator object semantics, borrow-checker alias rules, allocator-parametric behavior, or full trait-object coverage.
- Validation status:
  - Source focused `std_string_macro_surface.sa --filter "ascii and split once"`: pass (`1 passed; 37 skipped`).
  - Full test suites intentionally not run for this batch per user instruction to test only newly added coverage.
- Install sync status:
  - `./tools/install.sh --no-shell`: pass.
  - Installed-state focused `std_string_macro_surface.sa --filter "ascii and split once"`: pass (`1 passed; 37 skipped`).

## Completed: 2026-07-07 StringBuf strip alias batch

- Continued the `StringBuf` / `Vec` Rust API parity audit with String/Vec still treated as the active priority.
- Finding remains: current SA facades are broad but still not complete Rust API coverage. Remaining unsupported or intentionally unclaimed areas include allocator-parametric APIs, Box/Cow conversions, real lazy iterator object models, const-generic array ownership/extraction shapes, `Vec::into_chunks` / `into_flattened` / `recycle`, Vec whole-object mutable borrow semantics beyond local metadata pointer facades / generic `T: PartialEq/Ord/Hash`, `String::as_mut_vec` Rust borrow-checker semantics and UTF-8 invariant enforcement, `u128`/`i128` formatting, float default-format parity, and full generic trait-object coverage.
- Added supportable `String` deref-to-str strip aliases:
  - `STRING_BUF_STRIP_PREFIX`
  - `STRING_BUF_STRIP_SUFFIX`
- Semantics: these delegate through `STRING_BUF_AS_STR` to the existing concrete str slice helpers and preserve local `(ok, slice)` result shapes. They do not claim Rust generic `Pattern`, `Option<&str>` object layout, searcher/iterator object semantics, borrow-checker alias rules, allocator-parametric behavior, or full trait-object coverage.
- Validation status:
  - Source focused `std_string_macro_surface.sa --filter "string convenience"`: pass (`1 passed; 37 skipped`).
  - Full test suites intentionally not run for this batch per user instruction to test only newly added coverage.
- Install sync status:
  - `./tools/install.sh --no-shell`: pass.
  - Installed-state focused `std_string_macro_surface.sa --filter "string convenience"`: pass (`1 passed; 37 skipped`).

## Completed: 2026-07-07 StringBuf str predicate/search alias batch

- Continued the `StringBuf` / `Vec` Rust API parity audit with String/Vec still treated as the active priority.
- Finding remains: current SA facades are broad but still not complete Rust API coverage. Remaining unsupported or intentionally unclaimed areas include allocator-parametric APIs, Box/Cow conversions, real lazy iterator object models, const-generic array ownership/extraction shapes, `Vec::into_chunks` / `into_flattened` / `recycle`, Vec whole-object mutable borrow semantics beyond local metadata pointer facades / generic `T: PartialEq/Ord/Hash`, `String::as_mut_vec` Rust borrow-checker semantics and UTF-8 invariant enforcement, `u128`/`i128` formatting, float default-format parity, and full generic trait-object coverage.
- Added supportable `String` deref-to-str predicate/search aliases:
  - `STRING_BUF_CONTAINS`
  - `STRING_BUF_STARTS_WITH`
  - `STRING_BUF_ENDS_WITH`
  - `STRING_BUF_FIND`
  - `STRING_BUF_RFIND`
- Semantics: these delegate through `STRING_BUF_AS_STR` to the existing concrete str slice helpers and preserve local boolean or `(ok, index)` result shapes. They do not claim Rust generic `Pattern`, `Option<usize>` object layout, searcher/iterator object semantics, borrow-checker alias rules, allocator-parametric behavior, or full trait-object coverage.
- Validation status:
  - Source focused `std_string_macro_surface.sa --filter "string convenience"`: pass (`1 passed; 37 skipped`).
  - Full test suites intentionally not run for this batch per user instruction to test only newly added coverage.
- Install sync status:
  - `./tools/install.sh --no-shell`: pass.
  - Installed-state focused `std_string_macro_surface.sa --filter "string convenience"`: pass (`1 passed; 37 skipped`).

## Completed: 2026-07-07 StringBuf bytes alias batch

- Continued the `StringBuf` / `Vec` Rust API parity audit with String/Vec still treated as the active priority.
- Finding remains: current SA facades are broad but still not complete Rust API coverage. Remaining unsupported or intentionally unclaimed areas include allocator-parametric APIs, Box/Cow conversions, real lazy iterator object models, const-generic array ownership/extraction shapes, `Vec::into_chunks` / `into_flattened` / `recycle`, Vec whole-object mutable borrow semantics beyond local metadata pointer facades / generic `T: PartialEq/Ord/Hash`, `String::as_mut_vec` Rust borrow-checker semantics and UTF-8 invariant enforcement, `u128`/`i128` formatting, float default-format parity, and full generic trait-object coverage.
- Added supportable `String` deref-to-str byte-view alias:
  - `STRING_BUF_BYTES`
- Semantics: this delegates to the existing `STRING_BUF_AS_BYTES` view and returns a local byte `Slice` over the StringBuf backing storage. It does not claim Rust's lazy `str::Bytes` iterator object, borrow-checker alias rules, allocator-parametric behavior, or generic trait-object semantics.
- Validation status:
  - Source focused `std_string_macro_surface.sa --filter "string convenience"`: pass (`1 passed; 37 skipped`).
  - Full test suites intentionally not run for this batch per user instruction to test only newly added coverage.
- Install sync status:
  - `./tools/install.sh --no-shell`: pass.
  - Installed-state focused `std_string_macro_surface.sa --filter "string convenience"`: pass (`1 passed; 37 skipped`).

## Completed: 2026-07-07 String as_mut_vec pointer alias batch

- Continued the `StringBuf` / `Vec` Rust API parity audit with String/Vec still treated as the active priority.
- Finding remains: current SA facades are broad but still not complete Rust API coverage. Remaining unsupported or intentionally unclaimed areas include allocator-parametric APIs, Box/Cow conversions, real lazy iterator object models, const-generic array ownership/extraction shapes, `Vec::into_chunks` / `into_flattened` / `recycle`, Vec whole-object mutable borrow semantics beyond local metadata pointer facades / generic `T: PartialEq/Ord/Hash`, `String::as_mut_vec` Rust borrow-checker semantics and UTF-8 invariant enforcement, `u128`/`i128` formatting, float default-format parity, and full generic trait-object coverage.
- Added supportable unsafe `String::as_mut_vec`-style local metadata pointer alias:
  - `STRING_BUF_AS_MUT_VEC_PTR`
- Semantics: this returns a pointer to the existing StringBuf/Vec-shaped metadata so local SA code can inspect the backing pointer/len/cap through the same layout used by Vec. It does not enforce Rust's unsafe post-mutation UTF-8 invariant, Rust borrow-checker alias rules, allocator-parametric behavior, or generic trait-object semantics.
- Validation status:
  - Source focused `std_string_macro_surface.sa --filter "default add and from-char"`: pass (`1 passed; 37 skipped`).
  - Full test suites intentionally not run for this batch per user instruction to test only newly added coverage.
- Install sync status:
  - `./tools/install.sh --no-shell`: pass.
  - Installed-state focused `std_string_macro_surface.sa --filter "default add and from-char"`: pass (`1 passed; 37 skipped`).

## Completed: 2026-07-07 String split/line indexed alias batch

- Continued the `StringBuf` / `Vec` Rust API parity audit with String/Vec still treated as the active priority.
- Finding remains: current SA facades are broad but still not complete Rust API coverage. Remaining unsupported or intentionally unclaimed areas include allocator-parametric APIs, Box/Cow conversions, real lazy iterator object models, const-generic array ownership/extraction shapes, `Vec::into_chunks` / `into_flattened` / `recycle`, Vec whole-object mutable borrow semantics beyond local metadata pointer facades / generic `T: PartialEq/Ord/Hash`, unsafe `String::as_mut_vec` whole-metadata aliasing, `u128`/`i128` formatting, float default-format parity, and full generic trait-object coverage.
- Added supportable String/str indexed split and line aliases over existing checked view forms:
  - `STR_SPLIT_BYTE_AT`, `STRING_SPLIT_BYTE_AT`
  - `STR_LINE_AT`, `STRING_LINE_AT`
- Semantics: these aliases preserve the existing local `(ok, slice)` result shape used by the `TRY_` forms. They expose indexed eager access to split-byte parts and lines. This does not claim Rust lazy iterator object semantics, generic `Pattern`, Rust `Option<&str>` object layout, or borrow-checker behavior.
- Validation status:
  - Source focused `std_string_macro_surface.sa --filter "split byte view"`: pass (`1 passed; 37 skipped`).
  - Source focused `std_string_macro_surface.sa --filter "line view"`: pass (`1 passed; 37 skipped`).
  - Full test suites intentionally not run for this batch per user instruction to test only newly added coverage.
- Install sync status:
  - `./tools/install.sh --no-shell`: pass.
  - Installed-state focused `std_string_macro_surface.sa --filter "split byte view"`: pass (`1 passed; 37 skipped`).
  - Installed-state focused `std_string_macro_surface.sa --filter "line view"`: pass (`1 passed; 37 skipped`).

## Completed: 2026-07-07 Vec checked get_mut alias batch

- Continued the `StringBuf` / `Vec` Rust API parity audit with String/Vec still treated as the active priority.
- Finding remains: current SA facades are broad but still not complete Rust API coverage. Remaining unsupported or intentionally unclaimed areas include allocator-parametric APIs, Box/Cow conversions, real lazy iterator object models, const-generic array ownership/extraction shapes, `Vec::into_chunks` / `into_flattened` / `recycle`, Vec whole-object mutable borrow semantics beyond local metadata pointer facades / generic `T: PartialEq/Ord/Hash`, unsafe `String::as_mut_vec` whole-metadata aliasing, `u128`/`i128` formatting, float default-format parity, and full generic trait-object coverage.
- Added supportable Vec checked mutable get aliases over the existing mutable-slice checked pointer helper:
  - `VEC_TRY_GET_MUT_PTR_U64`
  - `VEC_GET_MUT_U64`
- Semantics: these aliases preserve a local `(ok, ptr)` result shape. Hit paths return a mutable pointer into the Vec allocation and tests verify write-back; misses return `ok=0` and null pointer. This does not claim Rust `Option<&mut T>` object layout, generic `T` coverage, or borrow-checker aliasing semantics.
- Validation status:
  - Source focused `std_vec_macro_surface.sa --filter "clone and from-slice"`: pass (`1 passed; 25 skipped`).
  - Full test suites intentionally not run for this batch per user instruction to test only newly added coverage.
- Install sync status:
  - `./tools/install.sh --no-shell`: pass.
  - Installed-state focused `std_vec_macro_surface.sa --filter "clone and from-slice"`: pass (`1 passed; 25 skipped`).

## Completed: 2026-07-07 String exact UTF-16 alias batch

- Continued the `StringBuf` / `Vec` Rust API parity audit with String/Vec still treated as the active priority.
- Finding remains: current SA facades are broad but still not complete Rust API coverage. Remaining unsupported or intentionally unclaimed areas include allocator-parametric APIs, Box/Cow conversions, real lazy iterator object models, const-generic array ownership/extraction shapes, `Vec::into_chunks` / `into_flattened` / `recycle`, Vec whole-object mutable borrow semantics beyond local metadata pointer facades / generic `T: PartialEq/Ord/Hash`, unsafe `String::as_mut_vec` whole-metadata aliasing, `u128`/`i128` formatting, float default-format parity, and full generic trait-object coverage.
- Added closer Rust method-name aliases over existing U16 slice UTF-16 constructors:
  - `STRING_BUF_FROM_UTF16`
  - `STRING_BUF_FROM_UTF16_LOSSY`
- Semantics: `STRING_BUF_FROM_UTF16` preserves the existing local `(ok, StringBuf)` strict decode result shape; `STRING_BUF_FROM_UTF16_LOSSY` preserves the existing eager lossy replacement behavior. This does not claim Rust `Result` object layout, allocator-parametric behavior, or full trait-object coverage.
- Validation status:
  - Source focused `std_string_macro_surface.sa --filter "from_utf16 macros"`: pass (`1 passed; 37 skipped`).
  - Source focused `std_string_macro_surface.sa --filter "from_utf16 lossy"`: pass (`1 passed; 37 skipped`).
  - Full test suites intentionally not run for this batch per user instruction to test only newly added coverage.
- Install sync status:
  - `./tools/install.sh --no-shell`: pass.
  - Installed-state focused `std_string_macro_surface.sa --filter "from_utf16 macros"`: pass (`1 passed; 37 skipped`).
  - Installed-state focused `std_string_macro_surface.sa --filter "from_utf16 lossy"`: pass (`1 passed; 37 skipped`).

## Completed: 2026-07-07 String UTF-16 constructor alias batch

- Continued the `StringBuf` / `Vec` Rust API parity audit with String/Vec still treated as the active priority.
- Finding remains: current SA facades are broad but still not complete Rust API coverage. Remaining unsupported or intentionally unclaimed areas include allocator-parametric APIs, Box/Cow conversions, real lazy iterator object models, const-generic array ownership/extraction shapes, `Vec::into_chunks` / `into_flattened` / `recycle`, Vec whole-object mutable borrow semantics beyond local metadata pointer facades / generic `T: PartialEq/Ord/Hash`, unsafe `String::as_mut_vec` whole-metadata aliasing, `u128`/`i128` formatting, float default-format parity, and full generic trait-object coverage.
- Added supportable checked UTF-16 constructor naming aliases over existing strict UTF-16 forms:
  - `STRING_BUF_FROM_UTF16_U16`
  - `STRING_BUF_FROM_UTF16LE`
  - `STRING_BUF_FROM_UTF16BE`
- Semantics: these aliases preserve the existing local `(ok, StringBuf)` result shape used by the `TRY_` forms. U16 input validates surrogate-pair structure; endian byte-slice input validates even byte length and then delegates to strict UTF-16 decoding. This does not claim Rust `Result` object layout, allocator-parametric behavior, or full trait-object coverage.
- Validation status:
  - Source focused `std_string_macro_surface.sa --filter "from_utf16 macros"`: pass (`1 passed; 37 skipped`).
  - Source focused `std_string_macro_surface.sa --filter "utf16 endian byte"`: pass (`1 passed; 37 skipped`).
  - Full test suites intentionally not run for this batch per user instruction to test only newly added coverage.
- Install sync status:
  - `./tools/install.sh --no-shell`: pass.
  - Installed-state focused `std_string_macro_surface.sa --filter "from_utf16 macros"`: pass (`1 passed; 37 skipped`).
  - Installed-state focused `std_string_macro_surface.sa --filter "utf16 endian byte"`: pass (`1 passed; 37 skipped`).

## Completed: 2026-07-07 String UTF-8 constructor alias batch

- Continued the `StringBuf` / `Vec` Rust API parity audit with String/Vec still treated as the active priority.
- Finding remains: current SA facades are broad but still not complete Rust API coverage. Remaining unsupported or intentionally unclaimed areas include allocator-parametric APIs, Box/Cow conversions, real lazy iterator object models, const-generic array ownership/extraction shapes, `Vec::into_chunks` / `into_flattened` / `recycle`, Vec whole-object mutable borrow semantics beyond local metadata pointer facades / generic `T: PartialEq/Ord/Hash`, unsafe `String::as_mut_vec` whole-metadata aliasing, `u128`/`i128` formatting, float default-format parity, and full generic trait-object coverage.
- Added supportable checked UTF-8 constructor naming aliases over existing strict UTF-8 forms:
  - `STRING_BUF_FROM_UTF8`
  - `STRING_BUF_FROM_UTF8_VEC`
  - `STRING_BUF_FROM_VEC_U8`
  - `STRING_BUF_FROM_BYTES_VEC`
- Semantics: these aliases preserve the existing local `(ok, StringBuf)` and `(ok, StringBuf, err_vec)` result shapes used by the `TRY_` forms. Valid owned-Vec input moves the Vec allocation into the `StringBuf`; invalid owned-Vec input returns the original Vec through the error slot. This does not claim Rust `Result` / `FromUtf8Error` object layout, allocator-parametric behavior, or full trait-object coverage.
- Validation status:
  - Source focused `std_string_macro_surface.sa --filter "owned buffer utf8 and replace"`: pass (`1 passed; 37 skipped`).
  - Source focused `std_string_macro_surface.sa --filter "from_utf8 Vec"`: pass (`1 passed; 37 skipped`).
  - Source focused `std_string_macro_surface.sa --filter "reference conversion"`: pass (`1 passed; 37 skipped`).
  - Full test suites intentionally not run for this batch per user instruction to test only newly added coverage.
- Install sync status:
  - `./tools/install.sh --no-shell`: pass.
  - Installed-state focused `std_string_macro_surface.sa --filter "owned buffer utf8 and replace"`: pass (`1 passed; 37 skipped`).
  - Installed-state focused `std_string_macro_surface.sa --filter "from_utf8 Vec"`: pass (`1 passed; 37 skipped`).
  - Installed-state focused `std_string_macro_surface.sa --filter "reference conversion"`: pass (`1 passed; 37 skipped`).

## Completed: 2026-07-07 Vec split_off alias batch

- Continued the `StringBuf` / `Vec` Rust API parity audit with String/Vec still treated as the active priority.
- Finding remains: current SA facades are broad but still not complete Rust API coverage. Remaining unsupported or intentionally unclaimed areas include allocator-parametric APIs, Box/Cow conversions, real lazy iterator object models, const-generic array ownership/extraction shapes, `Vec::into_chunks` / `into_flattened` / `recycle`, Vec whole-object mutable borrow semantics beyond local metadata pointer facades / generic `T: PartialEq/Ord/Hash`, unsafe `String::as_mut_vec` whole-metadata aliasing, `u128`/`i128` formatting, float default-format parity, and full generic trait-object coverage.
- Added supportable Vec split-off naming aliases over existing checked split-off forms:
  - `VEC_SPLIT_OFF`
  - `VEC_SPLIT_OFF_U64`
- Semantics: these aliases preserve the existing local `(ok, Vec)` result shape used by the `TRY_` split-off forms. Hit paths move the tail into a new Vec and shrink the source; misses return `ok=0`. This does not claim Rust panic behavior, allocator-parametric behavior, generic `T` coverage beyond the existing element-size/U64 surface, or borrow-checker semantics.
- Validation status:
  - Source focused `std_vec_macro_surface.sa --filter "vec convenience"`: pass (`1 passed; 25 skipped`).
  - Full test suites intentionally not run for this batch per user instruction to test only newly added coverage.
- Install sync status:
  - `./tools/install.sh --no-shell`: pass.
  - Installed-state focused `std_vec_macro_surface.sa --filter "vec convenience"`: pass (`1 passed; 25 skipped`).

## Completed: 2026-07-07 String/str get-range alias batch

- Continued the `StringBuf` / `Vec` Rust API parity audit with String/Vec still treated as the active priority.
- Finding remains: current SA facades are broad but still not complete Rust API coverage. Remaining unsupported or intentionally unclaimed areas include allocator-parametric APIs, Box/Cow conversions, real lazy iterator object models, const-generic array ownership/extraction shapes, `Vec::into_chunks` / `into_flattened` / `recycle`, Vec whole-object mutable borrow semantics beyond local metadata pointer facades / generic `T: PartialEq/Ord/Hash`, unsafe `String::as_mut_vec` whole-metadata aliasing, `u128`/`i128` formatting, float default-format parity, and full generic trait-object coverage.
- Added supportable String/str checked range-view naming aliases over existing UTF-8 boundary checked forms:
  - `STR_GET_RANGE`, `STRING_GET_RANGE`
  - `STR_GET_PREFIX`, `STRING_GET_PREFIX`
  - `STR_GET_SUFFIX`, `STRING_GET_SUFFIX`
  - `STR_GET_RANGE_TO`, `STRING_GET_RANGE_TO`
  - `STR_GET_RANGE_FROM`, `STRING_GET_RANGE_FROM`
  - `STR_GET_RANGE_BETWEEN`, `STRING_GET_RANGE_BETWEEN`
- Semantics: these aliases preserve the existing local `(ok, slice)` result shape used by the `TRY_` get-range forms. Bounds and UTF-8 char-boundary checks stay delegated to the existing helpers. This does not claim Rust `Option<&str>` object layout, range trait object coverage, Rust panic behavior, or borrow-checker semantics.
- Validation status:
  - Source focused `std_string_macro_surface.sa --filter "ascii and split once"`: pass (`1 passed; 37 skipped`).
  - Full test suites intentionally not run for this batch per user instruction to test only newly added coverage.
- Install sync status:
  - `./tools/install.sh --no-shell`: pass.
  - Installed-state focused `std_string_macro_surface.sa --filter "ascii and split once"`: pass (`1 passed; 37 skipped`).

## Completed: 2026-07-07 Vec strip alias batch

- Continued the `StringBuf` / `Vec` Rust API parity audit with String/Vec still treated as the active priority.
- Finding remains: current SA facades are broad but still not complete Rust API coverage. Remaining unsupported or intentionally unclaimed areas include allocator-parametric APIs, Box/Cow conversions, real lazy iterator object models, const-generic array ownership/extraction shapes, `Vec::into_chunks` / `into_flattened` / `recycle`, Vec whole-object mutable borrow semantics beyond local metadata pointer facades / generic `T: PartialEq/Ord/Hash`, unsafe `String::as_mut_vec` whole-metadata aliasing, `u128`/`i128` formatting, float default-format parity, and full generic trait-object coverage.
- Added supportable Vec deref-to-slice strip naming aliases over existing checked U64 slice-view forms:
  - `VEC_STRIP_PREFIX_U64`
  - `VEC_STRIP_SUFFIX_U64`
- Semantics: these aliases preserve the existing local `(ok, slice)` result shape used by the `TRY_` strip forms. Hit paths return the remaining slice view into the Vec allocation; misses return `ok=0` with an empty slice. This does not claim Rust `Option<&[T]>` object layout, generic `T: PartialEq`, Rust panic behavior, or borrow-checker semantics.
- Validation status:
  - Source focused `std_vec_macro_surface.sa --filter "vec convenience"`: pass (`1 passed; 25 skipped`).
  - Full test suites intentionally not run for this batch per user instruction to test only newly added coverage.
- Install sync status:
  - `./tools/install.sh --no-shell`: pass.
  - Installed-state focused `std_vec_macro_surface.sa --filter "vec convenience"`: pass (`1 passed; 25 skipped`).

## Completed: 2026-07-07 String/str byte find alias batch

- Continued the `StringBuf` / `Vec` Rust API parity audit with String/Vec still treated as the active priority.
- Finding remains: current SA facades are broad but still not complete Rust API coverage. Remaining unsupported or intentionally unclaimed areas include allocator-parametric APIs, Box/Cow conversions, real lazy iterator object models, const-generic array ownership/extraction shapes, `Vec::into_chunks` / `into_flattened` / `recycle`, Vec whole-object mutable borrow semantics beyond local metadata pointer facades / generic `T: PartialEq/Ord/Hash`, unsafe `String::as_mut_vec` whole-metadata aliasing, `u128`/`i128` formatting, float default-format parity, and full generic trait-object coverage.
- Added supportable String/str byte find naming aliases over existing checked byte find forms:
  - `STR_FIND_BYTE`, `STRING_FIND_BYTE`
  - `STR_RFIND_BYTE`, `STRING_RFIND_BYTE`
- Semantics: these aliases preserve the existing local `(ok, index)` result shape used by the `TRY_` byte forms. This models concrete byte search only; it does not claim generic `Pattern`, Unicode scalar search, Rust `Option<usize>` object layout, or iterator/searcher object semantics.
- Validation status:
  - Source focused `std_string_macro_surface.sa --filter "string byte scan"`: pass (`1 passed; 37 skipped`).
  - `git diff --check`: pass.
  - Full test suites intentionally not run for this batch per user instruction to test only newly added coverage.
- Install sync status:
  - `./tools/install.sh --no-shell`: pass.
  - Installed-state focused `std_string_macro_surface.sa --filter "string byte scan"`: pass (`1 passed; 37 skipped`).

## Completed: 2026-07-07 String/str find alias batch

- Continued the `StringBuf` / `Vec` Rust API parity audit with String/Vec still treated as the active priority.
- Finding remains: current SA facades are broad but still not complete Rust API coverage. Remaining unsupported or intentionally unclaimed areas include allocator-parametric APIs, Box/Cow conversions, real lazy iterator object models, const-generic array ownership/extraction shapes, `Vec::into_chunks` / `into_flattened` / `recycle`, Vec whole-object mutable borrow semantics beyond local metadata pointer facades / generic `T: PartialEq/Ord/Hash`, unsafe `String::as_mut_vec` whole-metadata aliasing, `u128`/`i128` formatting, float default-format parity, and full generic trait-object coverage.
- Added supportable String/str find naming aliases over existing checked find forms:
  - `STR_FIND`, `STRING_FIND`
  - `STR_RFIND`, `STRING_RFIND`
- Semantics: these aliases preserve the existing local `(ok, index)` result shape used by the `TRY_` forms. This does not claim Rust `Option<usize>` object layout, generic `Pattern` coverage beyond existing slice-pattern forms, or iterator/searcher object semantics.
- Validation status:
  - Source focused `std_string_macro_surface.sa --filter "string convenience"`: pass (`1 passed; 37 skipped`).
  - `git diff --check`: pass.
  - Full test suites intentionally not run for this batch per user instruction to test only newly added coverage.
- Install sync status:
  - `./tools/install.sh --no-shell`: pass.
  - Installed-state focused `std_string_macro_surface.sa --filter "string convenience"`: pass (`1 passed; 37 skipped`).

## Completed: 2026-07-07 String/str split/strip alias batch

- Continued the `StringBuf` / `Vec` Rust API parity audit with String/Vec still treated as the active priority.
- Finding remains: current SA facades are broad but still not complete Rust API coverage. Remaining unsupported or intentionally unclaimed areas include allocator-parametric APIs, Box/Cow conversions, real lazy iterator object models, const-generic array ownership/extraction shapes, `Vec::into_chunks` / `into_flattened` / `recycle`, Vec whole-object mutable borrow semantics beyond local metadata pointer facades / generic `T: PartialEq/Ord/Hash`, unsafe `String::as_mut_vec` whole-metadata aliasing, `u128`/`i128` formatting, float default-format parity, and full generic trait-object coverage.
- Added supportable String/str naming aliases over existing checked split/strip forms:
  - `STR_STRIP_PREFIX`, `STRING_STRIP_PREFIX`
  - `STR_STRIP_SUFFIX`, `STRING_STRIP_SUFFIX`
  - `STR_SPLIT_AT`, `STRING_SPLIT_AT`
  - `STR_SPLIT_AT_CHECKED`, `STRING_SPLIT_AT_CHECKED`
  - `STR_SPLIT_ONCE`, `STRING_SPLIT_ONCE`
  - `STR_RSPLIT_ONCE`, `STRING_RSPLIT_ONCE`
- Semantics: these aliases preserve the existing local `(ok, slice...)` result shapes used by the `TRY_` forms. They expose Rust method names where SA returns explicit success flags and empty slice metadata on misses. This does not claim Rust `Option`/tuple object layout, generic `Pattern` coverage beyond existing slice-pattern forms, panic behavior, or borrow-checker semantics.
- Validation status:
  - Source focused `std_string_macro_surface.sa --filter "string convenience"`: pass (`1 passed; 37 skipped`).
  - Source focused `std_string_macro_surface.sa --filter "ascii and split once"`: pass (`1 passed; 37 skipped`).
  - Source focused `std_string_macro_surface.sa --filter "utf8 byte and char view"`: pass (`1 passed; 37 skipped`).
  - Source focused `std_slice_vec_macro_surface.sa --filter "rust parity checked view"`: pass (`1 passed; 19 skipped`).
  - `git diff --check`: pass.
  - Full test suites intentionally not run for this batch per user instruction to test only newly added coverage.
- Install sync status:
  - `./tools/install.sh --no-shell`: pass.
  - Installed-state focused `std_string_macro_surface.sa --filter "string convenience"`: pass (`1 passed; 37 skipped`).
  - Installed-state focused `std_string_macro_surface.sa --filter "ascii and split once"`: pass (`1 passed; 37 skipped`).
  - Installed-state focused `std_string_macro_surface.sa --filter "utf8 byte and char view"`: pass (`1 passed; 37 skipped`).
  - Installed-state focused `std_slice_vec_macro_surface.sa --filter "rust parity checked view"`: pass (`1 passed; 19 skipped`).

## Completed: 2026-07-07 Vec binary_search alias batch

- Continued the `StringBuf` / `Vec` Rust API parity audit with String/Vec still treated as the active priority.
- Finding remains: current SA facades are broad but still not complete Rust API coverage. Remaining unsupported or intentionally unclaimed areas include allocator-parametric APIs, Box/Cow conversions, real lazy iterator object models, const-generic array ownership/extraction shapes, `Vec::into_chunks` / `into_flattened` / `recycle`, Vec whole-object mutable borrow semantics beyond local metadata pointer facades / generic `T: PartialEq/Ord/Hash`, unsafe `String::as_mut_vec` whole-metadata aliasing, `u128`/`i128` formatting, float default-format parity, and full generic trait-object coverage.
- Added supportable Vec deref-to-slice binary search naming alias over existing U64 slice machinery:
  - `VEC_BINARY_SEARCH_U64`
- Semantics: this alias preserves the existing local `(ok, index)` result shape used by `VEC_TRY_BINARY_SEARCH_U64`, where `ok=1` means a hit index and `ok=0` means the returned insertion point. This models the concrete U64 Vec/slice search path only; it does not claim Rust `Result<usize, usize>` object layout, generic `T: Ord`, comparator/key variants, or borrow-checker semantics.
- Validation status:
  - Source focused `std_vec_macro_surface.sa --filter "search wrappers"`: pass (`1 passed; 25 skipped`).
  - Source full `std_slice_vec_macro_surface.sa`: pass (`20 passed`).
  - Source full `std_vec_macro_surface.sa`: pass (`26 passed`).
  - Source full `std_string_macro_surface.sa`: pass (`38 passed`).
  - `git diff --check`: pass.
  - `zig build unit-framework --summary all`: pass (`6/6 steps succeeded; 5/5 tests passed`).
- Install sync status:
  - `./tools/install.sh --no-shell`: pass.
  - Installed-state full `std_slice_vec_macro_surface.sa`: pass (`20 passed`).
  - Installed-state full `std_vec_macro_surface.sa`: pass (`26 passed`).
  - Installed-state full `std_string_macro_surface.sa`: pass (`38 passed`).

## Completed: 2026-07-07 Vec select_nth alias batch

- Continued the `StringBuf` / `Vec` Rust API parity audit with String/Vec still treated as the active priority.
- Finding remains: current SA facades are broad but still not complete Rust API coverage. Remaining unsupported or intentionally unclaimed areas include allocator-parametric APIs, Box/Cow conversions, real lazy iterator object models, const-generic array ownership/extraction shapes, `Vec::into_chunks` / `into_flattened` / `recycle`, Vec whole-object mutable borrow semantics beyond local metadata pointer facades / generic `T: PartialEq/Ord/Hash`, unsafe `String::as_mut_vec` whole-metadata aliasing, `u128`/`i128` formatting, float default-format parity, and full generic trait-object coverage.
- Added supportable Vec deref-to-slice select-nth naming aliases over existing U64 slice machinery:
  - `VEC_SELECT_NTH_UNSTABLE_U64`
  - `VEC_SELECT_NTH_UNSTABLE_BY_U64`
  - `VEC_SELECT_NTH_UNSTABLE_BY_KEY_U64`
- Semantics: these aliases preserve the existing local `(ok, left-slice, pivot-ptr, right-slice)` result shape used by the `TRY_` forms. They expose concrete U64 Vec mutable-slice partitioning through the existing slice implementation and return `ok=0` for out-of-range indexes. This does not claim Rust panic behavior, generic `T: Ord`, comparator/key trait object parity, or borrow-checker semantics.
- Validation status:
  - Source focused `std_slice_vec_macro_surface.sa --filter "select_nth"`: pass (`1 passed; 19 skipped`).
  - Source full `std_slice_vec_macro_surface.sa`: pass (`20 passed`).
  - Source full `std_vec_macro_surface.sa`: pass (`26 passed`).
  - Source full `std_string_macro_surface.sa`: pass (`38 passed`).
  - `git diff --check`: pass.
  - `zig build unit-framework --summary all`: pass (`6/6 steps succeeded; 5/5 tests passed`).
- Install sync status:
  - `./tools/install.sh --no-shell`: pass.
  - Installed-state full `std_slice_vec_macro_surface.sa`: pass (`20 passed`).
  - Installed-state full `std_vec_macro_surface.sa`: pass (`26 passed`).
  - Installed-state full `std_string_macro_surface.sa`: pass (`38 passed`).

## Completed: 2026-07-07 Vec copy alias batch

- Continued the `StringBuf` / `Vec` Rust API parity audit with String/Vec still treated as the active priority.
- Finding remains: current SA facades are broad but still not complete Rust API coverage. Remaining unsupported or intentionally unclaimed areas include allocator-parametric APIs, Box/Cow conversions, real lazy iterator object models, const-generic array ownership/extraction shapes, `Vec::into_chunks` / `into_flattened` / `recycle`, Vec whole-object mutable borrow semantics beyond local metadata pointer facades / generic `T: PartialEq/Ord/Hash`, unsafe `String::as_mut_vec` whole-metadata aliasing, `u128`/`i128` formatting, float default-format parity, and full generic trait-object coverage.
- Added supportable Vec deref-to-slice copy aliases over existing U64 slice machinery:
  - `VEC_COPY_FROM_SLICE_U64`
  - `VEC_CLONE_FROM_SLICE_U64`
  - `VEC_COPY_WITHIN_U64`
- Semantics: these aliases expose concrete U64 Vec mutation through the existing mutable slice metadata path. `copy_from_slice` / `clone_from_slice` require equal lengths and return `ok=0` on mismatch. `copy_within` checks source and destination ranges, supports overlapping moves through the existing slice memmove-style implementation, and returns `ok=0` on invalid bounds. This does not claim generic `T`, Clone drop semantics, Rust panic behavior, or borrow-checker semantics.
- Validation status:
  - Source focused `std_slice_vec_macro_surface.sa --filter "vec copy aliases"`: pass (`1 passed; 19 skipped`).
  - Source full `std_slice_vec_macro_surface.sa`: pass (`20 passed`).
  - Source full `std_vec_macro_surface.sa`: pass (`26 passed`).
  - Source full `std_string_macro_surface.sa`: pass (`38 passed`).
  - `git diff --check`: pass.
  - `zig build unit-framework --summary all`: pass (`6/6 steps succeeded; 5/5 tests passed`).
- Install sync status:
  - `./tools/install.sh --no-shell`: pass.
  - Installed-state full `std_slice_vec_macro_surface.sa`: pass (`20 passed`).
  - Installed-state full `std_vec_macro_surface.sa`: pass (`26 passed`).
  - Installed-state full `std_string_macro_surface.sa`: pass (`38 passed`).

## Completed: 2026-07-07 Vec chunk/window access alias batch

- Continued the `StringBuf` / `Vec` Rust API parity audit with String/Vec still treated as the active priority.
- Finding remains: current SA facades are broad but still not complete Rust API coverage. Remaining unsupported or intentionally unclaimed areas include allocator-parametric APIs, Box/Cow conversions, real lazy iterator object models, const-generic array ownership/extraction shapes, `Vec::into_chunks` / `into_flattened` / `recycle`, Vec whole-object mutable borrow semantics beyond local metadata pointer facades / generic `T: PartialEq/Ord/Hash`, unsafe `String::as_mut_vec` whole-metadata aliasing, `u128`/`i128` formatting, float default-format parity, and full generic trait-object coverage.
- Added supportable Vec chunk/window access aliases over existing U64 try forms:
  - `VEC_CHUNK_AT_U64`
  - `VEC_RCHUNK_AT_U64`
  - `VEC_RCHUNK_MUT_AT_U64`
  - `VEC_CHUNK_EXACT_AT_U64`
  - `VEC_CHUNK_EXACT_MUT_AT_U64`
  - `VEC_RCHUNK_EXACT_AT_U64`
  - `VEC_RCHUNK_EXACT_MUT_AT_U64`
  - `VEC_WINDOW_AT_U64`
- Semantics: these aliases preserve the existing local `(ok, slice)` result shape used by the `TRY_` chunk/window access forms. Mut aliases return mutable slice metadata into the Vec allocation. Tests cover chunk/window, reverse chunk and mutable reverse chunk, exact chunk/reverse-exact chunk, miss paths, and mutable write-back; this does not claim lazy iterator objects, generic `T`, Rust panic behavior, or borrow-checker semantics.
- Validation status:
  - Source focused `std_slice_vec_macro_surface.sa --filter "chunk window"`: pass (`1 passed; 18 skipped`).
  - Source focused `std_slice_vec_macro_surface.sa --filter "rchunk macros"`: pass (`1 passed; 18 skipped`).
  - Source focused `std_slice_vec_macro_surface.sa --filter "exact chunk"`: pass (`1 passed; 18 skipped`).
  - Source full `std_slice_vec_macro_surface.sa`: pass (`19 passed`).
  - Source full `std_vec_macro_surface.sa`: pass (`26 passed`).
  - Source full `std_string_macro_surface.sa`: pass (`38 passed`).
  - `git diff --check`: pass.
  - `zig build unit-framework --summary all`: pass (`6/6 steps succeeded; 5/5 tests passed`).
- Install sync status:
  - `./tools/install.sh --no-shell`: pass.
  - Installed-state full `std_slice_vec_macro_surface.sa`: pass (`19 passed`).
  - Installed-state full `std_vec_macro_surface.sa`: pass (`26 passed`).
  - Installed-state full `std_string_macro_surface.sa`: pass (`38 passed`).

## Completed: 2026-07-07 Vec slice mutation alias batch

- Continued the `StringBuf` / `Vec` Rust API parity audit with String/Vec still treated as the active priority.
- Finding remains: current SA facades are broad but still not complete Rust API coverage. Remaining unsupported or intentionally unclaimed areas include allocator-parametric APIs, Box/Cow conversions, real lazy iterator object models, const-generic array ownership/extraction shapes, `Vec::into_chunks` / `into_flattened` / `recycle`, Vec whole-object mutable borrow semantics beyond local metadata pointer facades / generic `T: PartialEq/Ord/Hash`, unsafe `String::as_mut_vec` whole-metadata aliasing, `u128`/`i128` formatting, float default-format parity, and full generic trait-object coverage.
- Added supportable Vec deref-to-slice mutation aliases over existing U64 slice machinery:
  - `VEC_SWAP_U64`
  - `VEC_TRY_SWAP_U64`
  - `VEC_REVERSE_U64`
  - `VEC_ROTATE_LEFT_U64`
  - `VEC_ROTATE_RIGHT_U64`
  - `VEC_SWAP_WITH_SLICE_U64`
  - `VEC_FILL_U64`
- Semantics: these aliases expose concrete U64 Vec mutation through the existing mutable slice metadata path. Tests cover swap, try-swap miss, reverse, rotate-left/right, swap-with-slice hit/miss, and fill, then verify Vec and slice contents. This does not claim generic `T`, Rust panic behavior, allocator-parametric behavior, or borrow-checker semantics.
- Validation status:
  - Source focused `std_slice_vec_macro_surface.sa --filter "slice mutation aliases"`: pass (`1 passed; 18 skipped`).
  - Source full `std_slice_vec_macro_surface.sa`: pass (`19 passed`).
  - Source full `std_vec_macro_surface.sa`: pass (`26 passed`).
  - Source full `std_string_macro_surface.sa`: pass (`38 passed`).
  - `git diff --check`: pass.
  - `zig build unit-framework --summary all`: pass (`6/6 steps succeeded; 5/5 tests passed`).
- Install sync status:
  - `./tools/install.sh --no-shell`: pass.
  - Installed-state full `std_slice_vec_macro_surface.sa`: pass (`19 passed`).
  - Installed-state full `std_vec_macro_surface.sa`: pass (`26 passed`).
  - Installed-state full `std_string_macro_surface.sa`: pass (`38 passed`).

## Completed: 2026-07-07 Vec unchecked split/range alias batch

- Continued the `StringBuf` / `Vec` Rust API parity audit with String/Vec still treated as the active priority.
- Finding remains: current SA facades are broad but still not complete Rust API coverage. Remaining unsupported or intentionally unclaimed areas include allocator-parametric APIs, Box/Cow conversions, real lazy iterator object models, const-generic array ownership/extraction shapes, `Vec::into_chunks` / `into_flattened` / `recycle`, Vec whole-object mutable borrow semantics beyond local metadata pointer facades / generic `T: PartialEq/Ord/Hash`, unsafe `String::as_mut_vec` whole-metadata aliasing, `u128`/`i128` formatting, float default-format parity, and full generic trait-object coverage.
- Added supportable Vec unchecked split/range aliases over existing U64 slice unchecked machinery:
  - `VEC_SPLIT_AT_UNCHECKED_U64`
  - `VEC_SPLIT_AT_MUT_UNCHECKED_U64`
  - `VEC_RANGE_UNCHECKED_U64`
  - `VEC_GET_RANGE_UNCHECKED_U64`
  - `VEC_GET_RANGE_MUT_UNCHECKED_U64`
- Semantics: these aliases model the concrete unsafe Vec-to-slice unchecked view shape for callers that already know the split/range is in bounds. Mut aliases return mutable slice metadata into the Vec allocation and tests verify write-back. The tests intentionally cover only in-bounds behavior and do not claim out-of-bounds safety, Rust borrow-checker semantics, or generic `T` coverage.
- Validation status:
  - Source focused `std_slice_vec_macro_surface.sa --filter "unchecked split range"`: pass (`1 passed; 17 skipped`).
  - Source full `std_slice_vec_macro_surface.sa`: pass (`18 passed`).
  - Source full `std_vec_macro_surface.sa`: pass (`26 passed`).
  - Source full `std_string_macro_surface.sa`: pass (`38 passed`).
  - `git diff --check`: pass.
  - `zig build unit-framework --summary all`: pass (`6/6 steps succeeded; 5/5 tests passed`).
- Install sync status:
  - `./tools/install.sh --no-shell`: pass.
  - Installed-state full `std_slice_vec_macro_surface.sa`: pass (`18 passed`).
  - Installed-state full `std_vec_macro_surface.sa`: pass (`26 passed`).
  - Installed-state full `std_string_macro_surface.sa`: pass (`38 passed`).

## Completed: 2026-07-07 Vec split/range naming alias batch

- Continued the `StringBuf` / `Vec` Rust API parity audit with String/Vec still treated as the active priority.
- Finding remains: current SA facades are broad but still not complete Rust API coverage. Remaining unsupported or intentionally unclaimed areas include allocator-parametric APIs, Box/Cow conversions, real lazy iterator object models, const-generic array ownership/extraction shapes, `Vec::into_chunks` / `into_flattened` / `recycle`, Vec whole-object mutable borrow semantics beyond local metadata pointer facades / generic `T: PartialEq/Ord/Hash`, unsafe `String::as_mut_vec` whole-metadata aliasing, `u128`/`i128` formatting, float default-format parity, and full generic trait-object coverage.
- Added supportable Vec deref-to-slice split/range naming aliases over existing U64 slice machinery:
  - `VEC_SPLIT_AT_U64`
  - `VEC_TRY_SPLIT_AT_MUT_U64`
  - `VEC_SPLIT_AT_MUT_U64`
  - `VEC_SPLIT_AT_CHECKED_U64`
  - `VEC_SPLIT_AT_MUT_CHECKED_U64`
  - `VEC_RANGE_U64`
  - `VEC_GET_RANGE_U64`
  - `VEC_GET_RANGE_MUT_U64`
- Semantics: these aliases preserve the existing local `(ok, slice...)` shape. Mut aliases return mutable slice metadata into the Vec allocation and tests verify write-back through those slices. Miss paths return `ok=0` and empty slice metadata. This models concrete U64 Vec/slice views only; it does not claim Rust panic behavior, generic `T`, or borrow-checker semantics.
- Validation status:
  - Source focused `std_slice_vec_macro_surface.sa --filter "checked range"`: pass (`1 passed; 16 skipped`).
  - Source full `std_slice_vec_macro_surface.sa`: pass (`17 passed`).
  - Source full `std_vec_macro_surface.sa`: pass (`26 passed`).
  - Source full `std_string_macro_surface.sa`: pass (`38 passed`).
  - `git diff --check`: pass.
  - `zig build unit-framework --summary all`: pass (`6/6 steps succeeded; 5/5 tests passed`).
- Install sync status:
  - `./tools/install.sh --no-shell`: pass.
  - Installed-state full `std_slice_vec_macro_surface.sa`: pass (`17 passed`).
  - Installed-state full `std_vec_macro_surface.sa`: pass (`26 passed`).
  - Installed-state full `std_string_macro_surface.sa`: pass (`38 passed`).

## Completed: 2026-07-07 Vec chunk naming alias batch

- Continued the `StringBuf` / `Vec` Rust API parity audit with String/Vec still treated as the active priority.
- Finding remains: current SA facades are broad but still not complete Rust API coverage. Remaining unsupported or intentionally unclaimed areas include allocator-parametric APIs, Box/Cow conversions, real lazy iterator object models, const-generic array ownership/extraction shapes, `Vec::into_chunks` / `into_flattened` / `recycle`, Vec whole-object mutable borrow semantics beyond local metadata pointer facades / generic `T: PartialEq/Ord/Hash`, unsafe `String::as_mut_vec` whole-metadata aliasing, `u128`/`i128` formatting, float default-format parity, and full generic trait-object coverage.
- Added supportable Vec deref-to-slice chunk naming aliases over the existing U64 try forms:
  - `VEC_SPLIT_FIRST_CHUNK_U64`
  - `VEC_FIRST_CHUNK_U64`
  - `VEC_FIRST_CHUNK_MUT_U64`
  - `VEC_SPLIT_FIRST_CHUNK_MUT_U64`
  - `VEC_SPLIT_LAST_CHUNK_U64`
  - `VEC_SPLIT_LAST_CHUNK_MUT_U64`
  - `VEC_LAST_CHUNK_U64`
  - `VEC_LAST_CHUNK_MUT_U64`
- Semantics: these aliases preserve the existing local `(ok, slice...)` result shape used by the `TRY_` chunk forms. Mut aliases return mutable slice metadata into the Vec allocation. The tests cover hit, miss, zero-length chunk, and mutable write-back paths; this does not claim Rust const-generic array-reference layout, generic `T`, or borrow-checker semantics.
- Validation status:
  - Source focused `std_slice_vec_macro_surface.sa --filter "first last chunk"`: pass (`1 passed; 16 skipped`).
  - Source focused `std_slice_vec_macro_surface.sa --filter "split chunk"`: pass (`1 passed; 16 skipped`).
  - Source full `std_slice_vec_macro_surface.sa`: pass (`17 passed`).
  - Source full `std_vec_macro_surface.sa`: pass (`26 passed`).
  - Source full `std_string_macro_surface.sa`: pass (`38 passed`).
  - `git diff --check`: pass.
  - `zig build unit-framework --summary all`: pass (`6/6 steps succeeded; 5/5 tests passed`).
- Install sync status:
  - `./tools/install.sh --no-shell`: pass.
  - Installed-state full `std_slice_vec_macro_surface.sa`: pass (`17 passed`).
  - Installed-state full `std_vec_macro_surface.sa`: pass (`26 passed`).
  - Installed-state full `std_string_macro_surface.sa`: pass (`38 passed`).

## Completed: 2026-07-07 Vec unchecked alias batch

- Continued the `StringBuf` / `Vec` Rust API parity audit with String/Vec still treated as the active priority.
- Finding remains: current SA facades are broad but still not complete Rust API coverage. Remaining unsupported or intentionally unclaimed areas include allocator-parametric APIs, Box/Cow conversions, real lazy iterator object models, const-generic array ownership/extraction shapes, `Vec::into_chunks` / `into_flattened` / `recycle`, Vec whole-object mutable borrow semantics beyond local metadata pointer facades / generic `T: PartialEq/Ord/Hash`, unsafe `String::as_mut_vec` whole-metadata aliasing, `u128`/`i128` formatting, float default-format parity, and full generic trait-object coverage.
- Added supportable Vec unchecked U64 aliases over existing in-bounds pointer/value machinery:
  - `VEC_GET_UNCHECKED_U64`
  - `VEC_GET_UNCHECKED_MUT_PTR_U64`
- Semantics: these aliases model the concrete unsafe unchecked U64 value and mutable pointer access shape for callers that already know the index is in bounds. The tests verify only in-bounds behavior and do not claim out-of-bounds safety, Rust borrow-checker semantics, or generic `T` coverage.
- Validation status:
  - Source focused `std_vec_macro_surface.sa --filter "unchecked aliases"`: pass (`1 passed; 25 skipped`).
  - Source full `std_vec_macro_surface.sa`: pass (`26 passed`).
  - Source full `std_string_macro_surface.sa`: pass (`38 passed`).
  - `git diff --check`: pass.
  - `zig build unit-framework --summary all`: pass (`6/6 steps succeeded; 5/5 tests passed`).
- Install sync status:
  - `./tools/install.sh --no-shell`: pass.
  - Installed-state full `std_vec_macro_surface.sa`: pass (`26 passed`).
  - Installed-state full `std_string_macro_surface.sa`: pass (`38 passed`).

## Completed: 2026-07-07 Vec first_mut/last_mut alias batch

- Continued the `StringBuf` / `Vec` Rust API parity audit with String/Vec still treated as the active priority.
- Finding remains: current SA facades are broad but still not complete Rust API coverage. Remaining unsupported or intentionally unclaimed areas include allocator-parametric APIs, Box/Cow conversions, real lazy iterator object models, const-generic array ownership/extraction shapes, `Vec::into_chunks` / `into_flattened` / `recycle`, Vec whole-object mutable borrow semantics beyond local metadata pointer facades / generic `T: PartialEq/Ord/Hash`, unsafe `String::as_mut_vec` whole-metadata aliasing, `u128`/`i128` formatting, float default-format parity, and full generic trait-object coverage.
- Added supportable Vec deref-to-slice mutable endpoint aliases over U64 element pointers:
  - `VEC_TRY_FIRST_MUT_U64`
  - `VEC_FIRST_MUT_U64`
  - `VEC_TRY_LAST_MUT_U64`
  - `VEC_LAST_MUT_U64`
- Semantics: these aliases preserve the local `(ok, ptr)` shape used by other SA mutable element accessors. Empty Vec returns `ok=0` and a null pointer; non-empty Vec returns a pointer into the current allocation that can be written through. This models the concrete U64 pointer facade only; it does not claim generic `T` or borrow-checker semantics.
- Validation status:
  - Source focused `std_vec_macro_surface.sa --filter "peek_mut"`: pass (`1 passed; 24 skipped`).
  - Source full `std_vec_macro_surface.sa`: pass (`25 passed`).
  - Source full `std_string_macro_surface.sa`: pass (`38 passed`).
  - `git diff --check`: pass.
  - `zig build unit-framework --summary all`: pass (`6/6 steps succeeded; 5/5 tests passed`).
- Install sync status:
  - `./tools/install.sh --no-shell`: pass.
  - Installed-state full `std_vec_macro_surface.sa`: pass (`25 passed`).
  - Installed-state full `std_string_macro_surface.sa`: pass (`38 passed`).

## Completed: 2026-07-07 Vec split-first/last alias batch

- Continued the `StringBuf` / `Vec` Rust API parity audit with String/Vec still treated as the active priority.
- Finding remains: current SA facades are broad but still not complete Rust API coverage. Remaining unsupported or intentionally unclaimed areas include allocator-parametric APIs, Box/Cow conversions, real lazy iterator object models, const-generic array ownership/extraction shapes, `Vec::into_chunks` / `into_flattened` / `recycle`, Vec whole-object mutable borrow semantics beyond local metadata pointer facades / generic `T: PartialEq/Ord/Hash`, unsafe `String::as_mut_vec` whole-metadata aliasing, `u128`/`i128` formatting, float default-format parity, and full generic trait-object coverage.
- Added supportable Vec deref-to-slice split aliases over the existing U64 try forms:
  - `VEC_SPLIT_FIRST_U64`
  - `VEC_SPLIT_FIRST_MUT_U64`
  - `VEC_SPLIT_LAST_U64`
  - `VEC_SPLIT_LAST_MUT_U64`
- Semantics: these aliases preserve the existing `(ok, value-or-pointer, rest-slice)` shape. Mut aliases return a pointer into the Vec allocation and rest slice metadata; empty Vec returns `ok=0`, a zero value/null pointer, and an empty rest slice. This models the concrete U64 Vec/slice shape only; it does not claim generic `T` or borrow-checker semantics.
- Validation status:
  - Source focused `std_vec_macro_surface.sa --filter "split first last aliases"`: pass (`1 passed; 24 skipped`).
  - Source full `std_vec_macro_surface.sa`: pass (`25 passed`).
  - Source full `std_string_macro_surface.sa`: pass (`38 passed`).
  - `git diff --check`: pass.
  - `zig build unit-framework --summary all`: pass (`6/6 steps succeeded; 5/5 tests passed`).
- Install sync status:
  - `./tools/install.sh --no-shell`: pass.
  - Installed-state full `std_vec_macro_surface.sa`: pass (`25 passed`).
  - Installed-state full `std_string_macro_surface.sa`: pass (`38 passed`).

## Completed: 2026-07-07 Vec pop_if_mut alias batch

- Continued the `StringBuf` / `Vec` Rust API parity audit with String/Vec still treated as the active priority.
- Finding remains: current SA facades are broad but still not complete Rust API coverage. Remaining unsupported or intentionally unclaimed areas include allocator-parametric APIs, Box/Cow conversions, real lazy iterator object models, const-generic array ownership/extraction shapes, `Vec::into_chunks` / `into_flattened` / `recycle`, Vec whole-object mutable borrow semantics beyond local metadata pointer facades / generic `T: PartialEq/Ord/Hash`, unsafe `String::as_mut_vec` whole-metadata aliasing, `u128`/`i128` formatting, float default-format parity, and full generic trait-object coverage.
- Added supportable U64 mutable-tail predicate aliases for Rust `Vec::pop_if`-style use cases:
  - `VEC_TRY_POP_IF_MUT_U64`
  - `VEC_POP_IF_MUT_U64`
- Semantics: these aliases pass a mutable pointer to the current tail element into the predicate, preserve any predicate mutation when the element is kept, and return the post-mutation tail value when the predicate removes it. Empty Vec returns `ok=0` and `value=0`. This models the concrete U64 pointer-predicate shape only; it does not claim generic `T`, Rust closure traits, or borrow-checker semantics.
- Validation status:
  - Source full `std_vec_macro_surface.sa`: pass (`24 passed`).
  - Source full `std_string_macro_surface.sa`: pass (`38 passed`).
  - `git diff --check`: pass.
  - `zig build unit-framework --summary all`: pass (`6/6 steps succeeded; 5/5 tests passed`).
- Install sync status:
  - `./tools/install.sh --no-shell`: pass.
  - Installed-state full `std_vec_macro_surface.sa`: pass (`24 passed`).
  - Installed-state full `std_string_macro_surface.sa`: pass (`38 passed`).

## Completed: 2026-07-07 String/Vec pointer range alias batch

- Continued the `StringBuf` / `Vec` Rust API parity audit with String/Vec still treated as the active priority.
- Finding remains: current SA facades are broad but still not complete Rust API coverage. Remaining unsupported or intentionally unclaimed areas include allocator-parametric APIs, Box/Cow conversions, real lazy iterator object models, const-generic array ownership/extraction shapes, `Vec::into_chunks` / `into_flattened` / `recycle`, Vec whole-object mutable borrow semantics beyond local metadata pointer facades / generic `T: PartialEq/Ord/Hash`, unsafe `String::as_mut_vec` whole-metadata aliasing, `u128`/`i128` formatting, float default-format parity, and full generic trait-object coverage.
- Added supportable slice/String/Vec pointer-range aliases:
  - `SLICE_AS_PTR_RANGE`, `SLICE_AS_MUT_PTR_RANGE`, `SLICE_AS_PTR_RANGE_U64`, `SLICE_AS_MUT_PTR_RANGE_U64`
  - `STR_AS_PTR_RANGE`, `STR_AS_MUT_PTR_RANGE`, `STRING_AS_PTR_RANGE`, `STRING_AS_MUT_PTR_RANGE`
  - `STRING_BUF_AS_PTR_RANGE`, `STRING_BUF_AS_MUT_PTR_RANGE`
  - `VEC_AS_PTR_RANGE`, `VEC_AS_MUT_PTR_RANGE`, `VEC_AS_PTR_RANGE_U64`, `VEC_AS_MUT_PTR_RANGE_U64`
- Semantics: these aliases return explicit `start` and `end` pointer outputs, where `end = start + len * elem_size`. This models the supportable pointer-pair shape behind Rust `as_ptr_range` / `as_mut_ptr_range`; it does not claim Rust `Range<*const T>` / `Range<*mut T>` object layout or unsafe `slice::from_ptr_range` / `from_mut_ptr_range` reconstruction APIs.
- Validation status:
  - Source full `std_string_macro_surface.sa`: pass (`38 passed`).
  - Source full `std_vec_macro_surface.sa`: pass (`24 passed`).
  - `git diff --check`: pass.
  - `zig build unit-framework --summary all`: pass (`6/6 steps succeeded; 5/5 tests passed`).
- Install sync status:
  - `./tools/install.sh --no-shell`: pass.
  - Installed-state full `std_string_macro_surface.sa`: pass (`38 passed`).
  - Installed-state full `std_vec_macro_surface.sa`: pass (`24 passed`).

## Completed: 2026-07-07 str mutable bytes alias batch

- Continued the `StringBuf` / `Vec` Rust API parity audit with String/Vec still treated as the active priority.
- Finding remains: current SA facades are broad but still not complete Rust API coverage. Remaining unsupported or intentionally unclaimed areas include allocator-parametric APIs, Box/Cow conversions, real lazy iterator object models, const-generic array ownership/extraction shapes, `Vec::into_chunks` / `into_flattened` / `recycle`, Vec whole-object mutable borrow semantics beyond local metadata pointer facades / generic `T: PartialEq/Ord/Hash`, unsafe `String::as_mut_vec` whole-metadata aliasing, `u128`/`i128` formatting, float default-format parity, and full generic trait-object coverage.
- Added supportable unsafe byte-view aliases for Rust `str::as_bytes_mut` style use cases:
  - `STR_AS_MUT_BYTES`
  - `STRING_AS_MUT_BYTES`
- Semantics: these aliases expose a `str`/string slice as a mutable byte slice using the same Slice metadata shape as `STR_AS_BYTES`. They model the byte view only; they do not enforce Rust's unsafe UTF-8 invariant after mutation, ownership provenance, or borrow-checker semantics.
- Validation status:
  - Source full `std_string_macro_surface.sa`: pass (`38 passed`).
  - Source full `std_vec_macro_surface.sa`: pass (`24 passed`).
  - `git diff --check`: pass.
  - `zig build unit-framework --summary all`: pass (`6/6 steps succeeded; 5/5 tests passed`).
- Install sync status:
  - `./tools/install.sh --no-shell`: pass.
  - Installed-state full `std_string_macro_surface.sa`: pass (`38 passed`).
  - Installed-state full `std_vec_macro_surface.sa`: pass (`24 passed`).

## Completed: 2026-07-07 String mutable bytes alias batch

- Continued the `StringBuf` / `Vec` Rust API parity audit with String/Vec still treated as the active priority.
- Finding remains: current SA facades are broad but still not complete Rust API coverage. Remaining unsupported or intentionally unclaimed areas include allocator-parametric APIs, Box/Cow conversions, real lazy iterator object models, const-generic array ownership/extraction shapes, `Vec::into_chunks` / `into_flattened` / `recycle`, Vec whole-object mutable borrow semantics beyond local metadata pointer facades / generic `T: PartialEq/Ord/Hash`, unsafe `String::as_mut_vec` whole-metadata aliasing, `u128`/`i128` formatting, float default-format parity, and full generic trait-object coverage.
- Added supportable unsafe byte-view aliases for Rust `String::as_bytes_mut` style use cases:
  - `STRING_BUF_AS_MUT_BYTES`
  - `STRING_BUF_AS_MUT_REF_BYTES`
- Semantics: these aliases expose the current `StringBuf` allocation as a mutable byte slice through the existing Vec mutable-slice metadata facade. This models the byte view only; it does not enforce Rust's unsafe UTF-8 invariant after mutation and does not claim `String::as_mut_vec` or borrow-checker coverage.
- Validation status:
  - Source full `std_string_macro_surface.sa`: pass (`38 passed`).
  - Source full `std_vec_macro_surface.sa`: pass (`24 passed`).
  - `git diff --check`: pass.
  - `zig build unit-framework --summary all`: pass (`6/6 steps succeeded; 5/5 tests passed`).
- Install sync status:
  - `./tools/install.sh --no-shell`: pass.
  - Installed-state full `std_string_macro_surface.sa`: pass (`38 passed`).
  - Installed-state full `std_vec_macro_surface.sa`: pass (`24 passed`).

## Completed: 2026-07-07 String FromStr parse alias batch

- Continued the `StringBuf` / `Vec` Rust API parity audit with String/Vec still treated as the active priority.
- Finding remains: current SA facades are broad but still not complete Rust API coverage. Remaining unsupported or intentionally unclaimed areas include allocator-parametric APIs, Box/Cow conversions, real lazy iterator object models, const-generic array ownership/extraction shapes, `Vec::into_chunks` / `into_flattened` / `recycle`, Vec whole-object mutable borrow semantics beyond local metadata pointer facades / generic `T: PartialEq/Ord/Hash`, unsafe `String::as_mut_vec` metadata-level aliasing, `u128`/`i128` formatting, float default-format parity, and full generic trait-object coverage.
- Added concrete String `FromStr` / parse-style aliases:
  - `STRING_BUF_PARSE_FROM_STR`
  - `STR_PARSE_STRING_BUF`
- Semantics: these aliases copy a `&str` slice into an owned `StringBuf` and return `ok=1`, matching Rust's infallible `FromStr for String` shape for concrete strings. This does not claim generic `FromStr`, parser trait objects, or error type modeling.
- Validation status:
  - Source full `std_string_macro_surface.sa`: pass (`38 passed`).
  - Source full `std_vec_macro_surface.sa`: pass (`24 passed`).
  - `git diff --check`: pass.
  - `zig build unit-framework --summary all`: pass (`6/6 steps succeeded; 5/5 tests passed`).
- Install sync status:
  - `./tools/install.sh --no-shell`: pass.
  - Installed-state full `std_string_macro_surface.sa`: pass (`38 passed`).
  - Installed-state full `std_vec_macro_surface.sa`: pass (`24 passed`).

## Completed: 2026-07-07 Integer primitive to_string alias batch

- Continued the `StringBuf` / `Vec` Rust API parity audit with String/Vec still treated as the active priority.
- Finding remains: current SA facades are broad but still not complete Rust API coverage. Remaining unsupported or intentionally unclaimed areas include allocator-parametric APIs, Box/Cow conversions, real lazy iterator object models, const-generic array ownership/extraction shapes, `Vec::into_chunks` / `into_flattened` / `recycle`, Vec whole-object mutable borrow semantics beyond local metadata pointer facades / generic `T: PartialEq/Ord/Hash`, unsafe `String::as_mut_vec` metadata-level aliasing, `u128`/`i128` formatting, float default-format parity, and full generic `Display` / `ToString` coverage.
- Added concrete integer primitive `to_string` aliases over the existing u64/i64 formatter-backed paths:
  - `U8_TO_STRING`
  - `U16_TO_STRING`
  - `U32_TO_STRING`
  - `USIZE_TO_STRING`
  - `I8_TO_STRING`
  - `I16_TO_STRING`
  - `I32_TO_STRING`
  - `ISIZE_TO_STRING`
- Semantics: these aliases delegate to the existing decimal `U64_TO_STRING` / `I64_TO_STRING` StringBuf-producing paths. This models concrete SA integer values and does not claim Rust `u128`/`i128`, float formatting, or arbitrary `Display` trait coverage.
- Validation status:
  - Source full `std_string_macro_surface.sa`: pass (`37 passed`).
  - Source full `std_vec_macro_surface.sa`: pass (`24 passed`).
  - `git diff --check`: pass.
  - `zig build unit-framework --summary all`: pass (`6/6 steps succeeded; 5/5 tests passed`).
- Install sync status:
  - `./tools/install.sh --no-shell`: pass.
  - Installed-state full `std_string_macro_surface.sa`: pass (`37 passed`).
  - Installed-state full `std_vec_macro_surface.sa`: pass (`24 passed`).

## Completed: 2026-07-07 Vec AsMut Vec pointer alias batch

- Continued the `StringBuf` / `Vec` Rust API parity audit with String/Vec still treated as the active priority.
- Finding remains: current SA facades are broad but still not complete Rust API coverage. Remaining unsupported or intentionally unclaimed areas include allocator-parametric APIs, Box/Cow conversions, real lazy iterator object models, const-generic array ownership/extraction shapes, `Vec::into_chunks` / `into_flattened` / `recycle`, Vec whole-object mutable borrow semantics beyond local metadata pointer facades / generic `T: PartialEq/Ord/Hash`, unsafe `String::as_mut_vec` metadata-level aliasing, and full generic trait-object coverage.
- Added a supportable `AsMut<Vec<T>>`-style Vec metadata pointer alias:
  - `VEC_AS_MUT_VEC_PTR`
- Semantics: this is a local borrowed metadata pointer facade matching the existing `VEC_AS_REF_VEC_PTR` shape. It exposes the current Vec metadata pointer for macro composition but does not claim Rust borrow-checker enforcement or arbitrary whole-object mutation semantics.
- Validation status:
  - Source full `std_vec_macro_surface.sa`: pass (`24 passed`).
  - `git diff --check`: pass.
  - `zig build unit-framework --summary all`: pass (`6/6 steps succeeded; 5/5 tests passed`).
- Install sync status:
  - `./tools/install.sh --no-shell`: pass.
  - Installed-state full `std_vec_macro_surface.sa`: pass (`24 passed`).

## Completed: 2026-07-07 String primitive to_string alias batch

- Continued the `StringBuf` / `Vec` Rust API parity audit with String/Vec still treated as the active priority.
- Finding remains: current SA facades are broad but still not complete Rust API coverage. Remaining unsupported or intentionally unclaimed areas include allocator-parametric APIs, Box/Cow conversions, real lazy iterator object models, const-generic array ownership/extraction shapes, `Vec::into_chunks` / `into_flattened` / `recycle`, Vec whole-object mutable borrow / generic `T: PartialEq/Ord/Hash`, unsafe `String::as_mut_vec` metadata-level aliasing, and full generic `Display` / `ToString` coverage for arbitrary types.
- Added supportable concrete primitive `to_string` aliases over existing StringBuf and formatter paths:
  - `CHAR_TO_STRING`
  - `BOOL_TO_STRING`
  - `U64_TO_STRING`
  - `I64_TO_STRING`
- Semantics: `CHAR_TO_STRING` uses the existing Unicode scalar StringBuf constructor path, while bool/u64/i64 aliases format through the existing SA formatter and copy the formatted bytes into an owned `StringBuf`. This does not claim generic Rust `Display` / `ToString` trait-object coverage or float/default-format parity.
- Validation status:
  - Source full `std_string_macro_surface.sa`: pass (`37 passed`).
  - Source full `std_vec_macro_surface.sa`: pass (`24 passed`).
  - `git diff --check`: pass.
  - `zig build unit-framework --summary all`: pass (`6/6 steps succeeded; 5/5 tests passed`).
- Install sync status:
  - `./tools/install.sh --no-shell`: pass.
  - Installed-state full `std_string_macro_surface.sa`: pass (`37 passed`).
  - Installed-state full `std_vec_macro_surface.sa`: pass (`24 passed`).

## Completed: 2026-07-07 StringBuf/Vec owned conversion alias batch

- Continued the `StringBuf` / `Vec` Rust API parity audit with String/Vec still treated as the active priority.
- Finding remains: current SA facades are broad but still not complete Rust API coverage. Remaining unsupported or intentionally unclaimed areas include allocator-parametric APIs, Box/Cow conversions, real lazy iterator object models, const-generic array ownership/extraction shapes, `Vec::into_chunks` / `into_flattened` / `recycle`, Vec whole-object mutable borrow / generic `T: PartialEq/Ord/Hash`, and unsafe `String::as_mut_vec` metadata-level aliasing.
- Added supportable eager owned-copy aliases for Rust `ToOwned` / `ToString` / `to_vec` style use cases:
  - `STR_TO_OWNED`
  - `STR_TO_STRING`
  - `STRING_BUF_TO_OWNED`
  - `STRING_BUF_TO_STRING`
  - `SLICE_TO_VEC`
  - `SLICE_TO_OWNED_VEC`
  - `SLICE_TO_VEC_U64`
  - `SLICE_TO_OWNED_VEC_U64`
  - `VEC_TO_OWNED`
  - `VEC_TO_OWNED_U64`
- Semantics: these aliases allocate/copy into independent owned buffers through existing `StringBuf` clone/from-str and Vec from-slice/clone paths. Mutating the source after conversion does not mutate the owned result. This does not claim `Cow`, `Box`, allocator-parametric, trait-object, or full generic trait coverage.
- Validation status:
  - Source full `std_string_macro_surface.sa`: pass (`36 passed`).
  - Source full `std_vec_macro_surface.sa`: pass (`24 passed`).
  - `git diff --check`: pass.
  - `zig build unit-framework --summary all`: pass (`6/6 steps succeeded; 5/5 tests passed`).
- Install sync status:
  - `./tools/install.sh --no-shell`: pass.
  - Installed-state full `std_string_macro_surface.sa`: pass (`36 passed`).
  - Installed-state full `std_vec_macro_surface.sa`: pass (`24 passed`).

## Completed: 2026-07-07 StringBuf/Vec repeat alias batch

- Continued the `StringBuf` / `Vec` Rust API parity audit with String/Vec still treated as the active priority.
- Finding remains: current SA facades are broad but still not complete Rust API coverage. Remaining unsupported or intentionally unclaimed areas include allocator-parametric APIs, Box/Cow conversions, real lazy iterator object models, const-generic array ownership/extraction shapes, `Vec::into_chunks` / `into_flattened` / `recycle`, Vec whole-object mutable borrow / generic `T: PartialEq/Ord/Hash`, and unsafe `String::as_mut_vec` metadata-level aliasing.
- Added supportable eager repeat aliases for Rust `str::repeat` and slice/Vec repeat style use cases:
  - `STR_REPEAT`
  - `STRING_BUF_REPEAT`
  - `VEC_REPEAT`
  - `VEC_REPEAT_U64`
- Semantics: these aliases eagerly materialize a new `StringBuf` or Vec by copying the source str/slice `count` times. `count=0` returns an empty owned buffer. This does not claim allocator-parametric APIs, `Clone` for arbitrary `T`, or lazy iterator/object-model coverage.
- Validation status:
  - Source full `std_string_macro_surface.sa`: pass (`35 passed`).
  - Source full `std_vec_macro_surface.sa`: pass (`23 passed`).
  - `git diff --check`: pass.
  - `zig build unit-framework --summary all`: pass (`6/6 steps succeeded; 5/5 tests passed`).
- Install sync status:
  - `./tools/install.sh --no-shell`: pass.
  - Installed-state full `std_string_macro_surface.sa`: pass (`35 passed`).
  - Installed-state full `std_vec_macro_surface.sa`: pass (`23 passed`).

## Completed: 2026-07-07 StringBuf owned String iterator alias batch

- Continued the `StringBuf` / `Vec` Rust API parity audit with String/Vec still treated as the active priority.
- Finding remains: current SA facades are broad but still not complete Rust API coverage. Remaining unsupported or intentionally unclaimed areas include allocator-parametric APIs, Box/Cow conversions, real lazy iterator object models, const-generic array ownership/extraction shapes, `Vec::into_chunks` / `into_flattened` / `recycle`, Vec whole-object mutable borrow / generic `T: PartialEq/Ord/Hash`, and unsafe `String::as_mut_vec` metadata-level aliasing.
- Added supportable eager owned-String iterator aliases for Rust `FromIterator<String>` / `Extend<String>` style use cases:
  - `STRING_BUF_DROP_IN_PLACE`
  - `STRING_BUF_EXTEND_STRING_ITER`
  - `STRING_BUF_FROM_STRING_ITER`
- Semantics: these aliases accept an eager `Slice` whose elements are by-value `StringBuf` / Vec metadata entries. Each owned source StringBuf is appended through its `str` view, then its moved-from buffer allocation is dropped in place. This models a Slice-of-StringBuf metadata batch, not a real Rust lazy iterator object model.
- Compiler support: fixed LLVM-C lowering for indirect call signature provenance when a vtable slot load has a typed field prefix such as `SupportCfiFn_call`; the full unit-framework CFI test now passes instead of losing the indirect callee signature.
- Validation status:
  - Source full `std_string_macro_surface.sa`: pass (`34 passed`).
  - `git diff --check`: pass.
  - `zig build unit-framework --summary all`: pass (`6/6 steps succeeded; 5/5 tests passed`).
- Install sync status:
  - `./tools/install.sh --no-shell`: pass.
  - Installed-state full `std_string_macro_surface.sa`: pass (`34 passed`).

## Completed: 2026-07-07 StringBuf/Vec hash delegation alias batch

- Continued the `StringBuf` / `Vec` Rust API parity audit with String/Vec still treated as the active priority.
- Finding remains: current SA facades are broad but still not complete Rust API coverage. Remaining unsupported or intentionally unclaimed areas include allocator-parametric APIs, Box/Cow conversions, real lazy iterator object models, const-generic array ownership/extraction shapes, `Vec::into_chunks` / `into_flattened` / `recycle`, Vec whole-object mutable borrow / generic `T: PartialEq/Ord/Hash`, and unsafe `String::as_mut_vec` metadata-level aliasing.
- Added supportable local `Hash`-style delegation aliases:
  - `DEFAULT_HASHER_WRITE_BYTES`
  - `DEFAULT_HASHER_WRITE_STR`
  - `DEFAULT_HASHER_WRITE_SLICE_U8`
  - `DEFAULT_HASHER_WRITE_SLICE_U64`
  - `HASH_STR`
  - `HASH_SLICE_U8`
  - `SLICE_HASH_U64`
  - `STR_HASH`
  - `STRING_HASH`
  - `STRING_BUF_HASH`
  - `VEC_HASH_U64`
- Semantics: `StringBuf` hashes through its `str` view, and `Vec<u64>` hashes through its U64 slice view, matching Rust's trait delegation direction. The hashing algorithm is the existing SA `DefaultHasher` macro surface, not a claim of byte-for-byte Rust standard-library hasher parity or generic `T: Hash` coverage.
- Validation status:
  - Source focused `std_hash_macro_surface.sa`: pass (`1 passed`).
  - Source full `std_string_macro_surface.sa`: pass (`34 passed`).
  - Source full `std_vec_macro_surface.sa`: pass (`22 passed`).
  - `git diff --check`: pass.
  - `zig build unit-framework --summary all`: pass (`6/6 steps succeeded; 5/5 tests passed`).
- Install sync status:
  - `./tools/install.sh --no-shell`: pass.
  - Installed-state focused `std_hash_macro_surface.sa`: pass (`1 passed`).
  - Installed-state full `std_string_macro_surface.sa`: pass (`34 passed`).
  - Installed-state full `std_vec_macro_surface.sa`: pass (`22 passed`).

## Completed: 2026-07-07 StringBuf lexicographic comparison alias batch

- Continued the `StringBuf` / `Vec` Rust API parity audit with String/Vec still treated as the active priority.
- Finding remains: current SA facades are broad but still not complete Rust API coverage. Remaining unsupported or intentionally unclaimed areas include allocator-parametric APIs, Box/Cow conversions, real lazy iterator object models, const-generic array ownership/extraction shapes, `Vec::into_chunks` / `into_flattened` / `recycle`, Vec whole-object mutable borrow / generic `T: PartialEq/Ord`, and unsafe `String::as_mut_vec` metadata-level aliasing.
- Added supportable lexicographic comparison aliases for Rust `String` / `str` `PartialOrd` / `Ord` style use cases:
  - `STR_CMP`, `STR_LT`, `STR_LE`, `STR_GT`, `STR_GE`
  - `STRING_BUF_CMP_STR`, `STR_CMP_STRING_BUF`, `STRING_BUF_CMP_STRING`
  - `STRING_BUF_LT_STR`, `STRING_BUF_LE_STR`, `STRING_BUF_GT_STR`, `STRING_BUF_GE_STR`
  - `STR_LT_STRING_BUF`, `STR_LE_STRING_BUF`, `STR_GT_STRING_BUF`, `STR_GE_STRING_BUF`
  - `STRING_BUF_LT_STRING`, `STRING_BUF_LE_STRING`, `STRING_BUF_GT_STRING`, `STRING_BUF_GE_STRING`
- Semantics: these aliases compare UTF-8 strings by byte lexicographic order, returning `-1` / `0` / `1` for less/equal/greater and bool wrappers for ordering predicates, matching Rust string ordering without adding a new trait object model.
- Validation status:
  - Source full `std_string_macro_surface.sa`: pass (`34 passed`).
  - `git diff --check`: pass.
  - `zig build unit-framework --summary all`: pass (`6/6 steps succeeded; 5/5 tests passed`).
- Install sync status:
  - `./tools/install.sh --no-shell`: pass.
  - Installed-state full `std_string_macro_surface.sa`: pass (`34 passed`).

## Completed: 2026-07-07 Vec U64 lexicographic comparison alias batch

- Continued the `StringBuf` / `Vec` Rust API parity audit with String/Vec still treated as the active priority.
- Finding remains: current SA facades are broad but still not complete Rust API coverage. Remaining unsupported or intentionally unclaimed areas include allocator-parametric APIs, Box/Cow conversions, real lazy iterator object models, const-generic array ownership/extraction shapes, `Vec::into_chunks` / `into_flattened` / `recycle`, Vec whole-object mutable borrow / generic `T: PartialEq/Ord`, and unsafe `String::as_mut_vec` metadata-level aliasing.
- Added supportable U64 lexicographic comparison aliases for Rust slice-delegated `Vec<T>` `PartialOrd` / `Ord` style use cases:
  - `SLICE_CMP_U64`
  - `SLICE_LT_U64`
  - `SLICE_LE_U64`
  - `SLICE_GT_U64`
  - `SLICE_GE_U64`
  - `VEC_CMP_SLICE_U64`
  - `SLICE_CMP_VEC_U64`
  - `VEC_CMP_U64`
  - `VEC_LT_U64`
  - `VEC_LE_U64`
  - `VEC_GT_U64`
  - `VEC_GE_U64`
- Semantics: these aliases compare U64 slices lexicographically, returning `-1` / `0` / `1` for less/equal/greater and bool wrappers for ordering predicates, matching the supportable `Vec<u64>`/slice comparison subset without claiming generic `T: Ord` trait-object coverage.
- Validation status:
  - Source full `std_vec_macro_surface.sa`: pass (`22 passed`).
  - `git diff --check`: pass.
  - `zig build unit-framework --summary all`: pass (`6/6 steps succeeded; 5/5 tests passed`).
- Install sync status:
  - `./tools/install.sh --no-shell`: pass.
  - Installed-state full `std_vec_macro_surface.sa`: pass (`22 passed`).

## Completed: 2026-07-07 Vec U64 equality alias batch

- Continued the `StringBuf` / `Vec` Rust API parity audit with String/Vec still treated as the active priority.
- Finding remains: current SA facades are broad but still not complete Rust API coverage. Remaining unsupported or intentionally unclaimed areas include allocator-parametric APIs, Box/Cow conversions, real lazy iterator object models, const-generic array ownership/extraction shapes, `Vec::into_chunks` / `into_flattened`, Vec whole-object mutable borrow, and unsafe `String::as_mut_vec` metadata-level aliasing.
- Added supportable U64 equality aliases for Rust slice-delegated `Vec<T>` equality style use cases:
  - `SLICE_EQ_U64`
  - `SLICE_NE_U64`
  - `VEC_EQ_SLICE_U64`
  - `VEC_NE_SLICE_U64`
  - `SLICE_EQ_VEC_U64`
  - `SLICE_NE_VEC_U64`
  - `VEC_EQ_U64`
  - `VEC_NE_U64`
- Semantics: these aliases compare U64 slices element-by-element with length checks, matching the supportable `Vec<u64>`/slice equality subset without claiming generic `T: PartialEq` trait-object coverage.
- Validation status:
  - Source full `std_vec_macro_surface.sa`: pass (`22 passed`).
  - `zig build unit-framework --summary all`: pass (`6/6 steps succeeded; 5/5 tests passed`).
- Install sync status:
  - `./tools/install.sh --no-shell`: pass.
  - Installed-state full `std_vec_macro_surface.sa`: pass (`22 passed`).

## Completed: 2026-07-07 StringBuf equality alias batch

- Continued the `StringBuf` / `Vec` Rust API parity audit with String/Vec still treated as the active priority.
- Finding remains: current SA facades are broad but still not complete Rust API coverage. Remaining unsupported or intentionally unclaimed areas include allocator-parametric APIs, Box/Cow conversions, real lazy iterator object models, const-generic array ownership/extraction shapes, `Vec::into_chunks` / `into_flattened`, Vec whole-object mutable borrow, and unsafe `String::as_mut_vec` metadata-level aliasing.
- Added supportable `PartialEq` / `ne` style naming aliases over existing UTF-8 string view comparison:
  - `STRING_BUF_EQ_STR`
  - `STRING_BUF_NE_STR`
  - `STR_EQ_STRING_BUF`
  - `STR_NE_STRING_BUF`
  - `STRING_BUF_EQ_STRING`
  - `STRING_BUF_NE_STRING`
- Semantics: these aliases compare `StringBuf` values through `STRING_BUF_AS_STR` and the existing bytewise `STR_EQ`, matching Rust's `String`/`str` equality delegation without adding a new trait object model.
- Validation status:
  - Source full `std_string_macro_surface.sa`: pass (`34 passed`).
  - `zig build unit-framework --summary all`: pass (`6/6 steps succeeded; 5/5 tests passed`).
- Install sync status:
  - `./tools/install.sh --no-shell`: pass.
  - Installed-state full `std_string_macro_surface.sa`: pass (`34 passed`).

## Completed: 2026-07-07 StringBuf ASCII char iterator alias batch

- Continued the `StringBuf` / `Vec` Rust API parity audit with String/Vec still treated as the active priority.
- Finding remains: current SA facades are broad but still not complete Rust API coverage. Remaining unsupported or intentionally unclaimed areas include allocator-parametric APIs, Box/Cow conversions, real lazy iterator object models, const-generic array ownership/extraction shapes, `Vec::into_chunks` / `into_flattened`, Vec whole-object mutable borrow, and unsafe `String::as_mut_vec` metadata-level aliasing.
- Added supportable eager `core::ascii::Char` and `&core::ascii::Char` aliases for Rust `FromIterator` / `Extend` style use cases:
  - `STRING_BUF_TRY_EXTEND_ASCII_CHARS`
  - `STRING_BUF_EXTEND_ASCII_CHARS`
  - `STRING_BUF_TRY_FROM_ASCII_CHARS`
  - `STRING_BUF_FROM_ASCII_CHARS`
  - `STRING_BUF_TRY_EXTEND_ASCII_CHAR_REFS`
  - `STRING_BUF_EXTEND_ASCII_CHAR_REFS`
  - `STRING_BUF_TRY_FROM_ASCII_CHAR_REFS`
  - `STRING_BUF_FROM_ASCII_CHAR_REFS`
- Semantics: accepts eager byte-sized ASCII Char slices or pointer slices, validates every byte is ASCII before mutating, reserves one byte per item, then appends bytes directly. Invalid bytes return `ok=0` and leave the target StringBuf unchanged/empty.
- Validation status:
  - Source full `std_string_macro_surface.sa`: pass (`34 passed`).
  - `zig build unit-framework --summary all`: pass (`6/6 steps succeeded; 5/5 tests passed`).
- Install sync status:
  - `./tools/install.sh --no-shell`: pass.
  - Installed-state full `std_string_macro_surface.sa`: pass (`34 passed`).

## Completed: 2026-07-07 StringBuf char reference iterator alias batch

- Continued the `StringBuf` / `Vec` Rust API parity audit with String/Vec still treated as the active priority.
- Finding remains: current SA facades are broad but still not complete Rust API coverage. Remaining unsupported or intentionally unclaimed areas include allocator-parametric APIs, Box/Cow conversions, real lazy iterator object models, const-generic array ownership/extraction shapes, `Vec::into_chunks` / `into_flattened`, Vec whole-object mutable borrow, and unsafe `String::as_mut_vec` metadata-level aliasing.
- Added supportable eager `&char` aliases for Rust `FromIterator<&char>` / `Extend<&char>` style use cases:
  - `STRING_BUF_TRY_EXTEND_CHAR_REFS_U64`
  - `STRING_BUF_EXTEND_CHAR_REFS_U64`
  - `STRING_BUF_TRY_FROM_CHAR_REFS_U64`
  - `STRING_BUF_FROM_CHAR_REFS_U64`
- Semantics: accepts an eager `Slice` of pointers to U64 Unicode scalar values, validates every referenced scalar before mutating, reserves up to four UTF-8 bytes per scalar, then appends encoded UTF-8. Invalid scalar values such as surrogate codepoints return `ok=0` and leave the target StringBuf unchanged/empty.
- Validation status:
  - Source full `std_string_macro_surface.sa`: pass (`33 passed`).
  - `zig build unit-framework --summary all`: pass (`6/6 steps succeeded; 5/5 tests passed`).
- Install sync status:
  - `./tools/install.sh --no-shell`: pass.
  - Installed-state full `std_string_macro_surface.sa`: pass (`33 passed`).

## Completed: 2026-07-07 StringBuf str iterator alias batch

- Continued the `StringBuf` / `Vec` Rust API parity audit with String/Vec still treated as the active priority.
- Finding remains: current SA facades are broad but still not complete Rust API coverage. Remaining unsupported or intentionally unclaimed areas include allocator-parametric APIs, Box/Cow conversions, real lazy iterator object models, const-generic array ownership/extraction shapes, `Vec::into_chunks` / `into_flattened`, Vec whole-object mutable borrow, and unsafe `String::as_mut_vec` metadata-level aliasing.
- Added supportable eager `&str` sequence aliases for Rust `FromIterator<&str>` / `Extend<&str>` style use cases:
  - `STRING_BUF_EXTEND_STR_ITER`
  - `STRING_BUF_FROM_STR_ITER`
- Semantics: these aliases accept an eager `Slice` whose elements are `Slice` structs, modeling a Slice-of-Slice sequence of `&str` views, and append each view through the existing `STRING_BUF_PUSH_STR` path without claiming a real Rust lazy iterator object model.
- Validation status:
  - Source full `std_string_macro_surface.sa`: pass (`33 passed`).
  - `zig build unit-framework --summary all`: pass (`6/6 steps succeeded; 5/5 tests passed`).
- Install sync status:
  - `./tools/install.sh --no-shell`: pass.
  - Installed-state full `std_string_macro_surface.sa`: pass (`33 passed`).

## Completed: 2026-07-07 Vec eager iterator alias batch

- Continued the `StringBuf` / `Vec` Rust API parity audit with String/Vec still treated as the active priority.
- Finding remains: current SA facades are broad but still not complete Rust API coverage. Remaining unsupported or intentionally unclaimed areas include allocator-parametric APIs, Box/Cow conversions, real lazy iterator object models, const-generic array ownership/extraction shapes, `Vec::into_chunks` / `into_flattened`, Vec whole-object mutable borrow, and unsafe `String::as_mut_vec` metadata-level aliasing.
- Added supportable eager slice-shaped aliases for Rust `FromIterator<T>` / `Extend<T>` style use cases:
  - `VEC_FROM_ITER`
  - `VEC_FROM_ITER_U64`
  - `VEC_EXTEND_ITER`
  - `VEC_EXTEND_ITER_U64`
- Semantics: these aliases copy from an existing `Slice` into Vec storage or append slice contents to an existing Vec, reusing the existing slice-copy implementation without claiming a real Rust lazy iterator object model.
- Validation status:
  - Source full `std_vec_macro_surface.sa`: pass (`22 passed`).
  - `zig build unit-framework --summary all`: pass (`6/6 steps succeeded; 5/5 tests passed`).
- Install sync status:
  - `./tools/install.sh --no-shell`: pass.
  - Installed-state full `std_vec_macro_surface.sa`: pass (`22 passed`).

## Completed: 2026-07-07 StringBuf char iterator alias batch

- Continued the `StringBuf` / `Vec` Rust API parity audit with String/Vec still treated as the active priority.
- Finding remains: current SA facades are broad but still not complete Rust API coverage. Remaining unsupported or intentionally unclaimed areas include allocator-parametric APIs, Box/Cow conversions, real lazy iterator object models, const-generic array ownership/extraction shapes, `Vec::into_chunks` / `into_flattened`, Vec whole-object mutable borrow, and unsafe `String::as_mut_vec` metadata-level aliasing.
- Added supportable eager char-sequence aliases for Rust `FromIterator<char>` / `Extend<char>` style use cases:
  - `STRING_BUF_TRY_EXTEND_CHARS_U64`
  - `STRING_BUF_EXTEND_CHARS_U64`
  - `STRING_BUF_TRY_FROM_CHARS_U64`
  - `STRING_BUF_FROM_CHARS_U64`
- Semantics: accepts a `Slice` of U64 Unicode scalar values, validates the whole slice before mutating, reserves up to four UTF-8 bytes per scalar, then appends encoded UTF-8. Invalid scalar values such as surrogate codepoints return `ok=0` and leave the target StringBuf unchanged/empty.
- Validation status:
  - Source full `std_string_macro_surface.sa`: pass (`33 passed`).
  - `zig build unit-framework --summary all`: pass (`6/6 steps succeeded; 5/5 tests passed`).
- Install sync status:
  - `./tools/install.sh --no-shell`: pass.
  - Installed-state full `std_string_macro_surface.sa`: pass (`33 passed`).

## Completed: 2026-07-06 StringBuf/Vec Extend trait alias audit batch

- Re-audited `StringBuf` / `Vec` against Rust `alloc::string::String` and `alloc::vec::Vec` public APIs with String/Vec as the active priority.
- Finding remains: current SA facades are broad but still not complete Rust API coverage. Remaining unsupported or intentionally unclaimed areas include allocator-parametric APIs, Box/Cow conversions, lazy iterator object models, const-generic array ownership/extraction shapes, `Vec::into_chunks` / `into_flattened`, Vec whole-object mutable borrow, and unsafe `String::as_mut_vec` metadata-level aliasing.
- Added supportable trait-style aliases that do not require a new iterator object model:
  - `STRING_BUF_EXTEND_STR`
  - `STRING_BUF_TRY_EXTEND_CHAR`
  - `STRING_BUF_EXTEND_CHAR`
  - `STRING_BUF_EXTEND_STRING`
  - `VEC_EXTEND_ONE`
  - `VEC_EXTEND_ONE_U64`
  - `VEC_EXTEND_REF_SLICE`
  - `VEC_EXTEND_REF_SLICE_U64`
- Semantics: String aliases map to the existing append/Unicode-scalar push paths; `STRING_BUF_EXTEND_STRING` appends a source `StringBuf` view then frees the moved source. Vec aliases map to the existing push and copy-from-slice paths, matching the supportable `Extend<T>` / `Extend<&T>` shapes without claiming full Rust iterator semantics.
- Validation status:
  - Source full `std_string_macro_surface.sa`: pass (`32 passed`).
  - Source full `std_vec_macro_surface.sa`: pass (`22 passed`).
  - `zig build unit-framework --summary all`: pass (`6/6 steps succeeded; 5/5 tests passed`).
- Install sync status:
  - `./tools/install.sh --no-shell`: pass.
  - Installed-state full `std_string_macro_surface.sa`: pass (`32 passed`).
  - Installed-state full `std_vec_macro_surface.sa`: pass (`22 passed`).

## Completed: 2026-07-06 Unix socket set_mark facade batch

- Added supportable Linux `std::os::net::linux_ext::UnixSocketExt::set_mark` style facades for Unix stream and datagram sockets.
- Added macro surfaces:
  - `NET_UNIX_STREAM_SET_MARK`
  - `NET_UNIX_DATAGRAM_SET_MARK`
- Added runtime/export surfaces:
  - `sa_std_net_unix_stream_set_mark`
  - `sa_std_net_unix_datagram_set_mark`
- Semantics: Linux-only `SO_MARK` setter over AF_UNIX stream/datagram handles. The runtime validates the SA socket handle kind and AF_UNIX family before calling `setsockopt(SOL_SOCKET, SO_MARK, u32)`. Tests accept success, access denied, or unsupported because unprivileged environments may reject `SO_MARK`.
- Validation status:
  - `zig build sa-std-static --summary all`: pass (`5/5 steps succeeded`).
  - Source full `std_net_unix_macro_surface.sa`: pass (`7 passed`).
  - `zig build unit-framework --summary all`: pass (`6/6 steps succeeded; 5/5 tests passed`).
  - Runtime export check for new `sa_std_net_unix_*_set_mark` symbols: pass.
- Install sync status:
  - `./tools/install.sh --no-shell`: pass.
  - Installed-state full `std_net_unix_macro_surface.sa`: pass (`7 passed`).

## Completed: 2026-07-06 StringBuf/Vec Rust API self-reference and index alias audit batch

- Re-audited `StringBuf` / `Vec` against Rust `alloc::string::String` and `alloc::vec::Vec` public APIs with String/Vec as the active priority.
- Finding remains: current SA facades are broad but not complete Rust API coverage. Remaining unsupported or intentionally unclaimed areas still include allocator-parametric APIs, Box/Cow conversions, lazy iterator object models, const-generic array ownership/extraction shapes, `Vec::into_chunks` / `into_flattened`, Vec `AsMut<Vec<T>>` whole-object mutable borrow, and unsafe `String::as_mut_vec` metadata-level aliasing.
- Added supportable naming aliases:
  - `VEC_AS_REF_VEC_PTR`
  - `STRING_BUF_DEREF_STR`
  - `STRING_BUF_DEREF_MUT_STR`
  - `STRING_BUF_TRY_INDEX_RANGE`
  - `STRING_BUF_TRY_INDEX_RANGE_MUT`
- Semantics: the Vec self-reference alias returns a shared borrow pointer to the existing Vec metadata and does not copy or transfer ownership. String deref aliases return the existing str slice view shape, and index aliases reuse UTF-8 boundary checked range slicing.
- Validation status:
  - Source full `std_vec_macro_surface.sa`: pass (`21 passed`).
  - Source full `std_string_macro_surface.sa`: pass (`31 passed`).
  - `zig build unit-framework --summary all`: pass (`6/6 steps succeeded; 5/5 tests passed`).
- Install sync status:
  - `./tools/install.sh --no-shell`: pass.
  - Installed-state full `std_vec_macro_surface.sa`: pass (`21 passed`).
  - Installed-state full `std_string_macro_surface.sa`: pass (`31 passed`).

## Completed: 2026-07-06 Unix thread JoinHandleExt pthread facade batch

- Added supportable `std::os::unix::thread::JoinHandleExt` raw pthread facade backed by real runtime `pthread_t` values, not SA registry handle ids.
- Added macro surfaces:
  - `THREAD_AS_PTHREAD_T`
  - `THREAD_INTO_PTHREAD_T`
  - `THREAD_RAW_PTHREAD_JOIN_STATUS` for SA tests/callers that take ownership through `into_pthread_t` and need to join the transferred raw pthread.
- Added runtime/export surfaces:
  - `sa_thread_as_pthread_t`
  - `sa_thread_into_pthread_t`
  - `sa_thread_raw_pthread_join`
- Semantics: `as_pthread_t` reads the underlying raw pthread without consuming the SA join handle. `into_pthread_t` removes the SA join handle from the registry, transfers raw pthread ownership to the caller, and keeps task cleanup associated with the raw pthread join helper. `THREAD_JOIN_STATUS` was also corrected to pass its output buffer as a pointer according to the existing `pthread_join` ABI.
- Validation status:
  - `zig build sa-std-static --summary all`: pass (`5/5 steps succeeded`).
  - Source focused `std_thread_macro_surface.sa`: pass (`2 passed`).
  - Runtime export check for new `sa_thread_*pthread*` symbols: pass.
  - `zig build unit-framework --summary all`: pass (`6/6 steps succeeded; 5/5 tests passed`).
- Install sync status:
  - `./tools/install.sh --no-shell`: pass.
  - Installed-state focused `std_thread_macro_surface.sa`: pass (`2 passed`).
  - Installed-state runtime export check: pass.

## Completed: 2026-07-06 Unix ffi OsStr/OsString facade batch

- Added supportable `std::os::unix::ffi::{OsStrExt, OsStringExt}` macro facades.
- Added macro surfaces:
  - `OS_STR_FROM_BYTES`
  - `OS_STR_FROM_BYTES_SLICE`
  - `OS_STR_AS_BYTES`
  - `OS_STR_AS_BYTES_SLICE`
  - `OS_STRING_FROM_VEC`
  - `OS_STRING_FROM_VEC_U8`
  - `OS_STRING_INTO_VEC`
  - `OS_STRING_INTO_VEC_U8`
- Semantics: borrowed `OsStr` is represented as a byte `Slice` view, with `from_bytes` / `as_bytes` creating fresh Slice wrappers over the same pointer/length so the source view is not moved. Owned `OsString` is represented as the underlying `Vec<u8>` ownership shape, so `from_vec` / `into_vec` are move aliases.
- Validation status:
  - Source focused `std_os_unix_ffi_macro_surface.sa`: pass (`2 passed`).
  - `zig build unit-framework --summary all`: pass (`6/6 steps succeeded; 5/5 tests passed`), with `std_os_unix_ffi_macro_surface.sa` included in the runner list.
- Install sync status:
  - `./tools/install.sh --no-shell`: pass.
  - Installed-state focused `std_os_unix_ffi_macro_surface.sa`: pass (`2 passed`).

## Completed: 2026-07-06 StringBuf/Vec Rust API naming alias audit batch

- Re-audited `StringBuf` / `Vec` against Rust `alloc::string::String` and `alloc::vec::Vec` APIs after the latest conversion-alias work.
- Finding remains: the current SA facades are not complete Rust API coverage. Unsupported or intentionally unclaimed areas still include allocator-parametric constructors/accessors, Box/Cow conversions, lazy iterator object models, const-generic array ownership/array extraction, `Vec::into_chunks`/`into_flattened` object shapes, and unsafe `String::as_mut_vec` metadata-level aliasing.
- Added supportable naming aliases:
  - `VEC_AS_REF_SLICE`
  - `VEC_AS_MUT_REF_SLICE`
  - `VEC_DEREF_SLICE`
  - `VEC_DEREF_MUT_SLICE`
  - `STRING_BUF_WRITE_STR`
  - `STRING_BUF_WRITE_CHAR`
- Semantics: Vec aliases return the same slice view shape as existing `VEC_AS_SLICE` / `VEC_AS_MUT_SLICE`, matching Rust `AsRef<[T]>`, `AsMut<[T]>`, `Deref<Target=[T]>`, and `DerefMut` naming without pretending SA has a separate borrowed `Vec<T>` metadata reference object. String write aliases model `fmt::Write for String`: `write_str` appends and returns ok, while `write_char` reuses the existing Unicode scalar validation path.
- Validation status:
  - Source full `std_vec_macro_surface.sa`: pass (`21 passed`).
  - Source full `std_string_macro_surface.sa`: pass (`31 passed`).
  - `zig build unit-framework --summary all`: pass (`6/6 steps succeeded; 5/5 tests passed`).
- Install sync status:
  - `./tools/install.sh --no-shell`: pass.
  - Installed-state full `std_vec_macro_surface.sa`: pass (`21 passed`).
  - Installed-state full `std_string_macro_surface.sa`: pass (`31 passed`).

## Completed: 2026-07-06 UnixDatagram pathname/abstract address facade batch

- Continued `std::os::unix::net::UnixDatagram` parity with pathname and Unix `SocketAddr` handle address paths.
- Added macro surfaces:
  - `NET_UNIX_DATAGRAM_BIND`
  - `NET_UNIX_DATAGRAM_BIND_ADDR`
  - `NET_UNIX_DATAGRAM_CONNECT`
  - `NET_UNIX_DATAGRAM_CONNECT_ADDR`
  - `NET_UNIX_DATAGRAM_SEND_TO`
  - `NET_UNIX_DATAGRAM_SEND_TO_ADDR`
  - `NET_UNIX_DATAGRAM_RECV_FROM`
  - `NET_UNIX_DATAGRAM_PEEK_FROM`
- Added runtime/export surfaces: `sa_std_net_unix_datagram_bind`, `bind_addr`, `connect`, `connect_addr`, `send_to`, `send_to_addr`, `recv_from`, and `peek_from`.
- Semantics: pathname bind/connect/send-to use Rust-style Unix pathname addresses; address-handle variants reuse the existing pathname/abstract/unnamed Unix addr resource model. `peek_from` returns the sender address without consuming the datagram, and `recv_from` returns a Unix addr handle for the packet source.
- Validation status:
  - `zig build sa-std-static --summary all`: pass (`5/5 steps succeeded`).
  - Source focused UnixDatagram address tests: pass (`3 passed`).
  - Source full `std_net_unix_macro_surface.sa`: pass (`7 passed`).
  - `zig build unit-framework --summary all`: pass (`6/6 steps succeeded; 5/5 tests passed`).
  - Runtime export check for new `sa_std_net_unix_datagram_*` address symbols: pass.
- Install sync status:
  - `./tools/install.sh --no-shell`: pass.
  - Installed-state focused UnixDatagram address tests: pass (`3 passed`).
  - Installed-state full `std_net_unix_macro_surface.sa`: pass (`7 passed`).
  - Installed-state runtime export check: pass.

## Completed: 2026-07-06 Vec reference/array conversion alias facade batch

- Re-audited `StringBuf` / `Vec` macro surfaces against Rust `alloc::string::String` and `alloc::vec::Vec` APIs.
- Finding: current SA facades do not and cannot honestly claim complete Rust API coverage. Existing support covers the practical owned-buffer, UTF conversion, mutation, capacity, raw-parts, clone, and slice-view subsets; remaining gaps include allocator-parametric APIs, Box/Cow object conversions, const-generic array ownership, lazy iterator object models, and unsafe `String::as_mut_vec` metadata-level aliasing.
- Added supportable Vec conversion alias macro surfaces:
  - `VEC_FROM_MUT_SLICE` / `VEC_FROM_MUT_SLICE_U64`
  - `VEC_FROM_ARRAY` / `VEC_FROM_ARRAY_U64`
  - `VEC_FROM_MUT_ARRAY` / `VEC_FROM_MUT_ARRAY_U64`
- Semantics: these are Rust naming aliases over existing slice-copy construction. They copy the source elements into independent Vec storage, matching `From<&mut [T]>`, `From<&[T; N]>`, and `From<&mut [T; N]>` style behavior for SA slice-shaped inputs.
- Validation status:
  - Source focused Vec clone/from-slice test: pass (`1 passed`).
  - Source focused String owned-buffer test after rejecting the unsafe `as_mut_vec` alias approach: pass (`1 passed`).
  - Source full `std_vec_macro_surface.sa`: pass (`21 passed`).
  - Source full `std_string_macro_surface.sa`: pass (`31 passed`).
  - `zig build unit-framework --summary all`: pass (`6/6 steps succeeded; 5/5 tests passed`).
- Install sync status:
  - `./tools/install.sh --no-shell`: pass.
  - Installed-state focused Vec clone/from-slice test: pass (`1 passed`).
  - Installed-state full `std_vec_macro_surface.sa`: pass (`21 passed`).
  - Installed-state full `std_string_macro_surface.sa`: pass (`31 passed`).

## Completed: 2026-07-06 UnixDatagram basic facade batch

- Added supportable `std::os::unix::net::UnixDatagram` basic facade subset backed by AF_UNIX/SOCK_DGRAM handles.
- Added macro surfaces:
  - `NET_UNIX_DATAGRAM_UNBOUND`
  - `NET_UNIX_DATAGRAM_PAIR`
  - `NET_UNIX_DATAGRAM_TRY_CLONE`
  - `NET_UNIX_DATAGRAM_AS_RAW_FD` / `NET_UNIX_DATAGRAM_INTO_RAW_FD` / `NET_UNIX_DATAGRAM_FROM_RAW_FD`
  - `NET_UNIX_DATAGRAM_INTO_OWNED_FD` / `NET_UNIX_DATAGRAM_FROM_OWNED_FD`
  - `NET_UNIX_DATAGRAM_LOCAL_ADDR` / `NET_UNIX_DATAGRAM_PEER_ADDR`
  - `NET_UNIX_DATAGRAM_SET_PASSCRED` / `NET_UNIX_DATAGRAM_PASSCRED`
  - `NET_UNIX_DATAGRAM_SET_READ_TIMEOUT` / `NET_UNIX_DATAGRAM_READ_TIMEOUT`
  - `NET_UNIX_DATAGRAM_SET_WRITE_TIMEOUT` / `NET_UNIX_DATAGRAM_WRITE_TIMEOUT`
  - `NET_UNIX_DATAGRAM_SET_NONBLOCKING` / `NET_UNIX_DATAGRAM_TAKE_ERROR`
  - `NET_UNIX_DATAGRAM_SEND` / `NET_UNIX_DATAGRAM_RECV` / `NET_UNIX_DATAGRAM_PEEK`
  - `NET_UNIX_DATAGRAM_SHUTDOWN` / `NET_UNIX_DATAGRAM_CLOSE`
- Added runtime/export surfaces: `sa_std_net_unix_datagram_unbound`, `pair`, `try_clone`, `from_raw_fd`, `local_addr`, `peer_addr`, `set_passcred`, `passcred`, and `shutdown`.
- Semantics: UnixDatagram uses the existing owned fd-backed `udp_socket` resource kind while validating AF_UNIX/SOCK_DGRAM where handles are restored or queried as Unix datagrams. `pair` returns connected unnamed datagram sockets, `peek` is non-consuming, passcred maps to Linux `SO_PASSCRED`, and raw/owned fd conversions preserve Rust-style ownership transfer.
- Scope note: pathname/abstract `bind_addr`, `connect_addr`, `send_to_addr`, and address-returning `recv_from`/`peek_from` paths were completed in the follow-up address batch above.
- Validation status:
  - `zig build sa-std-static --summary all`: pass (`5/5 steps succeeded`).
  - Source focused UnixDatagram test: pass (`1 passed`).
  - Source full `std_net_unix_macro_surface.sa`: pass (`5 passed`).
  - `zig build unit-framework --summary all`: pass (`6/6 steps succeeded; 5/5 tests passed`).
  - Runtime export check for `sa_std_net_unix_datagram_*`: pass.
- Install sync status:
  - `./tools/install.sh --no-shell`: pass.
  - Installed-state focused UnixDatagram test: pass (`1 passed`).
  - Installed-state full `std_net_unix_macro_surface.sa`: pass (`5 passed`).

## Completed: 2026-07-06 Unix fs chroot facade batch

- Added supportable `std::os::unix::fs::chroot` current-process facade for Linux.
- Added macro surfaces:
  - `FS_CHROOT`
  - `FS_UNIX_CHROOT`
- Added runtime/export surface:
  - `sa_fs_chroot`
- Semantics: validates SA path input, calls Linux `chroot(2)` on the current process, and maps Linux errno values into existing SA runtime status codes. Test coverage uses `/` only, accepting success under root or permission denial under non-root, so it exercises the syscall path without moving the test process into an unsafe temporary root.
- Validation status:
  - `zig build sa-std-static --summary all`: pass (`5/5 steps succeeded`).
  - Source focused chroot test: pass (`1 passed`).
  - Source full `std_fs_unix_ext_macro_surface.sa`: pass (`7 passed`).
  - `zig build unit-framework --summary all`: pass (`6/6 steps succeeded; 5/5 tests passed`).
  - Runtime export check for `sa_fs_chroot`: pass.
- Install sync status:
  - `./tools/install.sh --no-shell`: pass.
  - Installed-state focused chroot test: pass (`1 passed`).
  - Installed-state full `std_fs_unix_ext_macro_surface.sa`: pass (`7 passed`).

## Completed: 2026-07-06 StringBuf/Vec reference conversion alias facade batch

- Continued String/Vec Rust API parity with remaining supportable reference/conversion aliases.
- Added StringBuf macro surfaces:
  - `STRING_BUF_FROM_MUT_STR`
  - `STRING_BUF_FROM_STRING_REF`
  - `STRING_BUF_TRY_FROM_VEC_U8`
  - `STRING_BUF_TRY_FROM_BYTES_VEC`
- Expanded Vec coverage for the existing `VEC_FROM_STRING_BUF` surface, matching Rust `From<String> for Vec<u8>` style ownership transfer.
- Semantics: `from_mut_str` copies the provided mutable str view just like `from_str`; `from_string_ref` clones the source StringBuf into independent backing storage; TryFrom byte-Vec aliases reuse strict UTF-8 validation and return the original byte Vec on failure.
- Scope note: `String::as_mut_vec`, Cow/Box conversions, allocator-parametric APIs, const-generic arrays, and lazy iterator object models remain outside the supportable SA surface for now.
- Validation status:
  - Source focused reference conversion tests: pass.
  - Source full `std_string_macro_surface.sa`: pass (`31 passed`).
  - Source full `std_vec_macro_surface.sa`: pass (`21 passed`).
  - `zig build unit-framework --summary all`: pass (`6/6 steps succeeded; 5/5 tests passed`).
- Install sync status:
  - `./tools/install.sh --no-shell`: pass.
  - Installed-state focused reference conversion tests: pass.
  - Installed-state full `std_string_macro_surface.sa`: pass (`31 passed`).
  - Installed-state full `std_vec_macro_surface.sa`: pass (`21 passed`).

## Completed: 2026-07-06 StringBuf/Vec default and conversion alias facade batch

- Continued String/Vec Rust API parity with supportable trait/conversion naming surfaces.
- Added Vec macro surfaces:
  - `VEC_DEFAULT`
  - `VEC_FROM_STR_BYTES` / `VEC_U8_FROM_STR`
  - `VEC_FROM_STRING_BUF`
- Added StringBuf macro surfaces:
  - `STRING_BUF_DEFAULT`
  - `STRING_BUF_AS_REF_STR` / `STRING_BUF_AS_MUT_REF_STR` / `STRING_BUF_AS_REF_BYTES`
  - `STRING_BUF_FROM_CHAR`
  - `STRING_BUF_ADD_STR` / `STRING_BUF_ADD_ASSIGN_STR`
- Semantics: default constructors produce empty buffers. `Vec<u8>` from str copies UTF-8 bytes. `StringBuf` add consumes/moves the left StringBuf and appends the right str slice; add-assign mutates in place; from-char encodes a Unicode scalar into UTF-8.
- Validation status:
  - Source focused default/conversion tests: pass.
  - Source full `std_vec_macro_surface.sa`: pass (`20 passed`).
  - Source full `std_string_macro_surface.sa`: pass (`30 passed`).
  - `zig build unit-framework --summary all`: pass (`6/6 steps succeeded; 5/5 tests passed`).
- Install sync status:
  - `./tools/install.sh --no-shell`: pass.
  - Installed-state focused default/conversion tests: pass.
  - Installed-state full `std_vec_macro_surface.sa`: pass (`20 passed`).
  - Installed-state full `std_string_macro_surface.sa`: pass (`30 passed`).

## Completed: 2026-07-06 StringBuf/Vec clone and from-slice/from-str facade batch

- Continued highest-priority String/Vec Rust API parity work with supportable clone/conversion surfaces.
- Added Vec macro surfaces:
  - `VEC_FROM_SLICE` / `VEC_FROM_SLICE_U64`
  - `VEC_CLONE` / `VEC_CLONE_U64`
  - `VEC_CLONE_FROM` / `VEC_CLONE_FROM_U64`
- Added StringBuf macro surfaces:
  - `STRING_BUF_FROM_STR`
  - `STRING_BUF_CLONE`
  - `STRING_BUF_CLONE_FROM`
- Semantics: Vec copies slice bytes for the supplied element size, with U64 convenience wrappers. StringBuf copies UTF-8 bytes from an existing str view. Clone and clone_from allocate/copy into independent backing storage rather than aliasing the source.
- Scope note: this covers Rust `Clone` / `clone_from` and `From<&[T]>` / `From<&str>` style shapes that SA can express today; it does not claim allocator-parametric, Cow, Box, const-generic array, or lazy iterator object-model APIs.
- Validation status:
  - Source focused clone tests: pass.
  - Source full `std_vec_macro_surface.sa`: pass (`19 passed`).
  - Source full `std_string_macro_surface.sa`: pass (`29 passed`).
  - `zig build unit-framework --summary all`: pass (`6/6 steps succeeded; 5/5 tests passed`).
- Install sync status:
  - `./tools/install.sh --no-shell`: pass.
  - Installed-state focused clone tests: pass.
  - Installed-state full `std_vec_macro_surface.sa`: pass (`19 passed`).
  - Installed-state full `std_string_macro_surface.sa`: pass (`29 passed`).

## Completed: 2026-07-06 Unix XDG env facade batch

- Added supportable `std::os::unix::xdg`-style environment directory facades.
- Added macro surfaces:
  - `ENV_XDG_DATA_HOME_DIR`
  - `ENV_XDG_CONFIG_HOME_DIR`
  - `ENV_XDG_STATE_HOME_DIR`
  - `ENV_XDG_CACHE_HOME_DIR`
  - `ENV_XDG_DATA_DIRS`
  - `ENV_XDG_CONFIG_DIRS`
- Semantics: non-empty XDG environment variables win; empty variables fall back. Home subdirs use `$HOME/.local/share`, `$HOME/.config`, `$HOME/.local/state`, and `$HOME/.cache`; empty `HOME` is treated as `/`. Directory lists fall back to `/usr/local/share/:/usr/share/` and `/etc/xdg`.
- Updated `std_env_macro_surface.sa` coverage for explicit XDG values plus empty/missing default fallbacks.
- Validation status:
  - Source full `std_env_macro_surface.sa`: pass (`10 passed`).
  - `zig build unit-framework --summary all`: pass (`6/6 steps succeeded; 5/5 tests passed`).
  - Runtime export check for `sa_env_xdg_*`: pass.
- Install sync status:
  - `./tools/install.sh --no-shell`: pass.
  - Installed-state focused XDG test: pass.
  - Installed-state full `std_env_macro_surface.sa`: pass (`10 passed`).

## Completed: 2026-07-06 StringBuf unchecked owned-Vec and as_mut_str facade batch

- Continued String Rust API parity work with supportable `String::from_utf8_unchecked(Vec<u8>)` and `String::as_mut_str` surfaces.
- Added macro surfaces:
  - `STRING_BUF_FROM_UTF8_UNCHECKED_VEC`
  - `STRING_BUF_FROM_UTF8_UNCHECKED_OWNED`
  - `STRING_BUF_AS_MUT_STR`
- Semantics: unchecked owned-Vec construction moves the byte Vec into `StringBuf` without validation, matching Rust's unsafe caller-obligation shape. `STRING_BUF_AS_MUT_STR` returns a mutable slice view over the StringBuf bytes.
- Updated `std_string_macro_surface.sa` coverage:
  - owned Vec containing `rust` moves into `StringBuf` while preserving the backing pointer.
  - `STRING_BUF_AS_MUT_STR` permits mutating the first ASCII byte and the StringBuf view observes `Rust`.
- Validation status:
  - Source focused `owned buffer utf8` test: pass.
  - Source full `std_string_macro_surface.sa`: pass (`28 passed`).
  - Source full `std_vec_macro_surface.sa`: pass (`18 passed`).
  - `zig build unit-framework --summary all`: pass (`6/6 steps succeeded; 5/5 tests passed`).
- Install sync status:
  - `./tools/install.sh --no-shell`: pass.
  - Installed-state focused `owned buffer utf8` test: pass.
  - Installed-state full `std_string_macro_surface.sa`: pass (`28 passed`).
  - Installed-state full `std_vec_macro_surface.sa`: pass (`18 passed`).

## Completed: 2026-07-06 StringBuf from_utf8_lossy invalid-sequence parity correction

- Tightened `STRING_BUF_FROM_UTF8_LOSSY` / owned-Vec lossy semantics to replace one invalid UTF-8 sequence with one U+FFFD, rather than replacing each invalid continuation byte independently.
- Added runtime helper logic to return the consumed invalid-sequence width for lossy decoding.
- Updated `std_string_macro_surface.sa` coverage with the Rust-doc-shaped sequence `F0 90 80 W`, which now decodes to `�W` for that invalid sequence plus following ASCII.
- Validation status:
  - Source focused `from_utf8 lossy` test: pass.
  - Source full `std_string_macro_surface.sa`: pass (`28 passed`).
  - Source full `std_vec_macro_surface.sa`: pass (`18 passed`).
  - Runtime export check for `sa_str_utf8_lossy_next`: pass.
  - `zig build unit-framework --summary all`: pass (`6/6 steps succeeded; 5/5 tests passed`).
- Install sync status:
  - `./tools/install.sh --no-shell`: pass.
  - Installed-state focused `from_utf8 lossy` test: pass.
  - Installed-state full `std_string_macro_surface.sa`: pass (`28 passed`).
  - Installed-state full `std_vec_macro_surface.sa`: pass (`18 passed`).

## Completed: 2026-07-06 StringBuf from_utf8_lossy owned-Vec facade batch

- Continued String Rust API parity work with the supportable `String::from_utf8_lossy_owned` subset.
- Added owned-Vec lossy UTF-8 constructor macro surfaces:
  - `STRING_BUF_FROM_UTF8_LOSSY_VEC`
  - `STRING_BUF_FROM_UTF8_LOSSY_OWNED`
- Semantics: consumes an owned byte Vec. Valid UTF-8 uses a zero-copy move into `StringBuf`; invalid UTF-8 builds a lossy `StringBuf` with U+FFFD replacement and frees the original Vec.
- Scope note: this is the SA owned-Vec constructor shape; it does not claim Rust's unstable feature gate or `Cow<'_, str>` API surface.
- Updated `std_string_macro_surface.sa` coverage:
  - valid owned Vec for `aé🙂z` round-trips and preserves the original buffer pointer.
  - invalid owned Vec with bytes `a`, `0xff`, `(`, and a truncated UTF-8 starter decodes to `a�(�`.
- Validation status:
  - Source focused `from_utf8 lossy` test: pass.
  - Source full `std_string_macro_surface.sa`: pass (`28 passed`).
  - Source full `std_vec_macro_surface.sa`: pass (`18 passed`).
  - `zig build unit-framework --summary all`: pass (`6/6 steps succeeded; 5/5 tests passed`).
- Install sync status:
  - `./tools/install.sh --no-shell`: pass.
  - Installed-state focused `from_utf8 lossy` test: pass.
  - Installed-state full `std_string_macro_surface.sa`: pass (`28 passed`).
  - Installed-state full `std_vec_macro_surface.sa`: pass (`18 passed`).

## Completed: 2026-07-06 StringBuf from_utf8_lossy facade batch

- Continued String Rust API parity work with the supportable `String::from_utf8_lossy` subset.
- Added owned lossy UTF-8 constructor macro surface:
  - `STRING_BUF_FROM_UTF8_LOSSY`
- Added runtime helper/export:
  - `sa_str_utf8_lossy_next`
- Semantics: scans a byte slice, appends valid UTF-8 codepoints unchanged, and appends U+FFFD for invalid UTF-8 sequences before continuing. The macro returns an owned `StringBuf`.
- Scope note: this is the SA owned-StringBuf shape; it does not claim Rust's `Cow<'_, str>` borrowed/owned object model.
- Updated `std_string_macro_surface.sa` coverage:
  - valid `aé🙂z` remains unchanged.
  - bytes `a`, `0xff`, `(`, and a truncated UTF-8 starter decode to `a�(�`.
- Validation status:
  - Source focused `from_utf8 lossy` test: pass.
  - Source full `std_string_macro_surface.sa`: pass (`28 passed`).
  - Source full `std_vec_macro_surface.sa`: pass (`18 passed`).
  - Runtime export check for `sa_str_utf8_lossy_next`: pass.
  - `zig build unit-framework --summary all`: pass (`6/6 steps succeeded; 5/5 tests passed`).
- Install sync status:
  - `./tools/install.sh --no-shell`: pass.
  - Installed-state focused `from_utf8 lossy` test: pass.
  - Installed-state full `std_string_macro_surface.sa`: pass (`28 passed`).
  - Installed-state full `std_vec_macro_surface.sa`: pass (`18 passed`).

## Completed: 2026-07-06 StringBuf from_utf8 Vec facade batch

- Continued String Rust API parity work with the supportable `String::from_utf8(Vec<u8>)` subset.
- Added owned-Vec UTF-8 constructor macro surface:
  - `STRING_BUF_TRY_FROM_UTF8_VEC`
- Semantics: validates an owned byte Vec as UTF-8. On success, moves the Vec buffer directly into the output `StringBuf` and returns an empty error Vec. On failure, returns `ok=0`, an empty `StringBuf`, and the original byte Vec as the error Vec for caller cleanup/inspection.
- Scope note: this is the SA owned-Vec result shape; it does not claim Rust's `FromUtf8Error` object type, but it preserves the original bytes on failure.
- Updated `std_string_macro_surface.sa` coverage:
  - a Vec containing the bytes for `aé🙂z` succeeds and round-trips through `STR_EQ`.
  - invalid bytes containing `0xff` fail, leave the output string empty, and return the original three bytes in the error Vec.
- Validation status:
  - Source focused `from_utf8 Vec` test: pass.
  - Source full `std_string_macro_surface.sa`: pass (`27 passed`).
  - Source full `std_vec_macro_surface.sa`: pass (`18 passed`).
  - `zig build unit-framework --summary all`: pass (`6/6 steps succeeded; 5/5 tests passed`).
- Install sync status:
  - `./tools/install.sh --no-shell`: pass.
  - Installed-state focused `from_utf8 Vec` test: pass.
  - Installed-state full `std_string_macro_surface.sa`: pass (`27 passed`).
  - Installed-state full `std_vec_macro_surface.sa`: pass (`18 passed`).

## Completed: 2026-07-06 StringBuf UTF-16 endian lossy byte-slice facade batch

- Continued String Rust API parity work with the supportable `String::from_utf16le_lossy` / `String::from_utf16be_lossy` subsets.
- Added endian lossy byte-slice constructor macro surfaces:
  - `STRING_BUF_FROM_UTF16_LOSSY_BYTES`
  - `STRING_BUF_FROM_UTF16LE_LOSSY`
  - `STRING_BUF_FROM_UTF16BE_LOSSY`
- Semantics: materializes full 2-byte units into a temporary U16 Vec in the requested endian order, decodes through `STRING_BUF_FROM_UTF16_LOSSY_U16`, and appends U+FFFD for a trailing odd byte.
- Scope note: this is the SA endian byte-slice lossy constructor shape; it does not claim Rust allocator/object model details.
- Updated `std_string_macro_surface.sa` coverage:
  - LE bytes with isolated high surrogate, `z`, isolated low surrogate, and odd trailing byte decode to `a�z��`.
  - BE bytes with the same code unit sequence decode to `a�z��`.
- Validation status:
  - Source focused `utf16 endian lossy` test: pass.
  - Source full `std_string_macro_surface.sa`: pass (`26 passed`).
  - Source full `std_vec_macro_surface.sa`: pass (`18 passed`).
  - `zig build unit-framework --summary all`: pass (`6/6 steps succeeded; 5/5 tests passed`).
- Install sync status:
  - `./tools/install.sh --no-shell`: pass.
  - Installed-state focused `utf16 endian lossy` test: pass.
  - Installed-state full `std_string_macro_surface.sa`: pass (`26 passed`).
  - Installed-state full `std_vec_macro_surface.sa`: pass (`18 passed`).

## Completed: 2026-07-06 StringBuf UTF-16 endian byte-slice facade batch

- Continued String Rust API parity work with the supportable `String::from_utf16le` / `String::from_utf16be` strict subsets.
- Added endian byte-slice constructor macro surfaces:
  - `STRING_BUF_TRY_FROM_UTF16_BYTES`
  - `STRING_BUF_TRY_FROM_UTF16LE`
  - `STRING_BUF_TRY_FROM_UTF16BE`
- Semantics: validates that the byte-slice length is even, materializes a temporary U16 Vec in the requested endian order, then reuses `STRING_BUF_TRY_FROM_UTF16_U16` for strict surrogate-pair decoding. Odd byte counts or invalid UTF-16 return `ok=0` with an empty `StringBuf`.
- Scope note: this batch covers strict endian byte-slice constructors; lossy endian byte-slice variants remain separate work.
- Updated `std_string_macro_surface.sa` coverage:
  - LE bytes for `aé🙂z` decode successfully.
  - BE bytes for `aé🙂z` decode successfully.
  - odd byte count fails and returns an empty output.
- Validation status:
  - Source focused `utf16 endian` test: pass.
  - Source full `std_string_macro_surface.sa`: pass (`25 passed`).
  - Source full `std_vec_macro_surface.sa`: pass (`18 passed`).
  - `zig build unit-framework --summary all`: pass (`6/6 steps succeeded; 5/5 tests passed`).
- Install sync status:
  - `./tools/install.sh --no-shell`: pass.
  - Installed-state focused `utf16 endian` test: pass.
  - Installed-state full `std_string_macro_surface.sa`: pass (`25 passed`).
  - Installed-state full `std_vec_macro_surface.sa`: pass (`18 passed`).

## Completed: 2026-07-06 StringBuf from_utf16_lossy facade batch

- Continued String Rust API parity work with the supportable `String::from_utf16_lossy` subset.
- Added lossy UTF-16 constructor macro surface:
  - `STRING_BUF_FROM_UTF16_LOSSY_U16`
- Semantics: decodes a U16 slice into a UTF-8 `StringBuf`, accepts BMP scalars and valid high/low surrogate pairs, replaces isolated high or low surrogate units with U+FFFD, and continues decoding subsequent units.
- Scope note: this is the SA U16-slice lossy constructor shape; it does not claim Rust's endian-specific byte-slice variants or allocation/error object model.
- Updated `std_string_macro_surface.sa` coverage:
  - valid U16 units for `aé🙂z` still decode exactly.
  - an isolated high surrogate followed by `z` is replaced and scanning continues.
  - an isolated low surrogate is replaced.
- Validation status:
  - Source focused `from_utf16 lossy` test: pass.
  - Source full `std_string_macro_surface.sa`: pass (`24 passed`).
  - Source full `std_vec_macro_surface.sa`: pass (`18 passed`).
  - `zig build unit-framework --summary all`: pass (`6/6 steps succeeded; 5/5 tests passed`).
- Install sync status:
  - `./tools/install.sh --no-shell`: pass.
  - Installed-state focused `from_utf16 lossy` test: pass.
  - Installed-state full `std_string_macro_surface.sa`: pass (`24 passed`).
  - Installed-state full `std_vec_macro_surface.sa`: pass (`18 passed`).

## Completed: 2026-07-06 StringBuf from_utf16 facade batch

- Continued String Rust API parity work with the supportable `String::from_utf16` subset.
- Added strict UTF-16 constructor macro surface:
  - `STRING_BUF_TRY_FROM_UTF16_U16`
- Semantics: decodes a U16 slice into a UTF-8 `StringBuf`, accepts BMP scalars and valid high/low surrogate pairs, and returns `ok=0` with an empty output for isolated high or low surrogate units.
- Scope note: this is the SA U16-slice constructor shape; it does not claim Rust's `FromUtf16Error` object model or lossy conversion variants.
- Updated `std_string_macro_surface.sa` coverage:
  - U16 units for `aé🙂z` decode to the existing UTF-8 string.
  - isolated trailing high surrogate fails with an empty output.
  - isolated low surrogate fails with an empty output.
- Validation status:
  - Source focused `from_utf16` test: pass.
  - Source full `std_string_macro_surface.sa`: pass (`23 passed`).
  - Source full `std_vec_macro_surface.sa`: pass (`18 passed`).
  - `zig build unit-framework --summary all`: pass (`6/6 steps succeeded; 5/5 tests passed`).
- Install sync status:
  - `./tools/install.sh --no-shell`: pass.
  - Installed-state focused `from_utf16` test: pass.
  - Installed-state full `std_string_macro_surface.sa`: pass (`23 passed`).
  - Installed-state full `std_vec_macro_surface.sa`: pass (`18 passed`).

## Completed: 2026-07-06 StringBuf into_chars facade batch

- Continued String Rust API parity work with the supportable `String::into_chars` subset.
- Added eager codepoint-vector macro surface:
  - `STRING_BUF_INTO_CHARS_U64`
- Semantics: consumes the `StringBuf`, decodes the UTF-8 string by Unicode scalar, pushes each codepoint into a returned U64 Vec, and frees the original StringBuf wrapper/allocation after the output Vec has been built.
- Scope note: this is an eager SA U64 codepoint Vec shape; it does not claim Rust's lazy `IntoChars` iterator object model.
- Updated `std_string_macro_surface.sa` coverage:
  - `aé🙂z` becomes `[97, 233, 128578, 122]`.
  - empty `StringBuf` becomes an empty Vec.
  - out-of-range get from the produced Vec returns `ok=0` and value `0`.
- Validation status:
  - Source focused `into_chars` test: pass.
  - Source full `std_string_macro_surface.sa`: pass (`22 passed`).
  - Source full `std_vec_macro_surface.sa`: pass (`18 passed`).
  - `zig build unit-framework --summary all`: pass (`6/6 steps succeeded; 5/5 tests passed`).
- Install sync status:
  - `./tools/install.sh --no-shell`: pass.
  - Installed-state focused `into_chars` test: pass.
  - Installed-state full `std_string_macro_surface.sa`: pass (`22 passed`).
  - Installed-state full `std_vec_macro_surface.sa`: pass (`18 passed`).

## Completed: 2026-07-06 StringBuf from_utf8 facade batch

- Continued String Rust API parity work with the supportable `String::from_utf8` subset.
- Added full UTF-8 validating constructor macro surface:
  - `STRING_BUF_TRY_FROM_UTF8`
- Semantics: constructs an empty `StringBuf`, validates the supplied byte slice with the existing UTF-8 validator, copies the bytes into the StringBuf on success, and returns `ok=0` with an empty StringBuf on invalid UTF-8.
- Scope note: this is the SA byte-slice constructor shape; it does not claim Rust's `FromUtf8Error` object model or zero-copy Vec ownership transfer.
- Updated `std_string_macro_surface.sa` coverage:
  - valid multi-byte UTF-8 `aé🙂z` succeeds and round-trips through `STR_EQ`.
  - invalid bytes containing `0xff` fail and leave the output empty.
  - existing ASCII-only constructor coverage remains intact.
- Validation status:
  - Source focused `utf8 and replace` test: pass.
  - Source full `std_string_macro_surface.sa`: pass (`21 passed`).
  - Source full `std_vec_macro_surface.sa`: pass (`18 passed`).
  - `zig build unit-framework --summary all`: pass (`6/6 steps succeeded; 5/5 tests passed`).
- Install sync status:
  - `./tools/install.sh --no-shell`: pass.
  - Installed-state focused `utf8 and replace` test: pass.
  - Installed-state full `std_string_macro_surface.sa`: pass (`21 passed`).
  - Installed-state full `std_vec_macro_surface.sa`: pass (`18 passed`).

## Completed: 2026-07-06 Vec spare capacity facade batch

- Continued Vec Rust API parity work with the supportable `Vec::spare_capacity_mut` / `Vec::split_at_spare_mut` subset.
- Added Vec spare-capacity macro surfaces:
  - `VEC_SPARE_CAPACITY_MUT`
  - `VEC_SPARE_CAPACITY_MUT_U64`
  - `VEC_SPLIT_AT_SPARE_MUT`
  - `VEC_SPLIT_AT_SPARE_MUT_U64`
- Corrected `VEC_SET_LEN` to match Rust's unsafe `Vec::set_len` shape by directly setting the Vec length instead of truncating only.
- Semantics: `VEC_SPARE_CAPACITY_MUT` returns a mutable Slice view over `cap - len` spare element slots; `VEC_SPLIT_AT_SPARE_MUT` returns the initialized mutable slice plus the spare mutable slice.
- Scope note: the spare slice is the SA slice view over uninitialized element slots; it does not model Rust's `MaybeUninit<T>` type directly.
- Updated `std_vec_macro_surface.sa` coverage:
  - creates a capacity-4 Vec with length 2.
  - writes two U64 values through the spare slice.
  - calls `VEC_SET_LEN` to expose the initialized spare elements.
  - verifies `split_at_spare_mut` initialized/spare lengths and mutation through the initialized slice.
- Validation status:
  - Source focused `spare capacity` test: pass.
  - Source full `std_vec_macro_surface.sa`: pass (`18 passed`).
  - Source full `std_string_macro_surface.sa`: pass (`21 passed`).
  - `zig build unit-framework --summary all`: pass (`6/6 steps succeeded; 5/5 tests passed`).
- Install sync status:
  - `./tools/install.sh --no-shell`: pass.
  - Installed-state focused `spare capacity` test: pass.
  - Installed-state full `std_vec_macro_surface.sa`: pass (`18 passed`).
  - Installed-state full `std_string_macro_surface.sa`: pass (`21 passed`).

## Completed: 2026-07-06 StringBuf/Vec leak facade batch

- Continued String/Vec Rust API parity work with the supportable `String::leak` / `Vec::leak` subset.
- Added leak macro surfaces:
  - `VEC_LEAK`
  - `STRING_BUF_LEAK`
- Semantics: consumes the owning Vec/StringBuf wrapper, moves the underlying allocation into a returned `Slice` view, clears the wrapper length/capacity, and intentionally does not free the allocation.
- Scope note: this is the SA mutable-slice/string-view shape; it does not claim Rust's full lifetime typing or boxed slice/string object model.
- Updated macro-surface coverage:
  - Vec leak returns a length-2 mutable slice with the original U64 values and permits mutation through the leaked slice pointer.
  - StringBuf leak returns a mutable string slice with the original bytes and permits mutation through the leaked pointer.
- Validation status:
  - Source focused Vec `leak` test: pass.
  - Source focused StringBuf `leak` test: pass.
  - Source full `std_vec_macro_surface.sa`: pass (`17 passed`).
  - Source full `std_string_macro_surface.sa`: pass (`21 passed`).
  - `zig build unit-framework --summary all`: pass (`6/6 steps succeeded; 5/5 tests passed`).
- Install sync status:
  - `./tools/install.sh --no-shell`: pass.
  - Installed-state focused Vec `leak` test: pass.
  - Installed-state focused StringBuf `leak` test: pass.
  - Installed-state full `std_vec_macro_surface.sa`: pass (`17 passed`).
  - Installed-state full `std_string_macro_surface.sa`: pass (`21 passed`).

## Completed: 2026-07-06 Vec from_elem facade batch

- Continued Vec Rust API parity work with the supportable `Vec::from_elem` subset.
- Added Vec repeated-value constructor macro surfaces:
  - `VEC_FROM_ELEM`
  - `VEC_FROM_ELEM_U64`
- Semantics: constructs a Vec with the requested capacity and pushes the supplied element value `length` times. A zero length returns an empty Vec.
- Scope note: this is the SA macro shape for repeated scalar/value construction; it does not claim Rust's full generic `Clone` trait dispatch or allocator-parametric surface.
- Updated `std_vec_macro_surface.sa` coverage:
  - `VEC_FROM_ELEM_U64 vec, 42, 3` returns length `3` with all three values set to `42`.
  - zero-length construction returns an empty Vec.
  - out-of-range get from the constructed Vec returns `ok=0` and value `0`.
- Validation status:
  - Source focused `from_elem` test: pass.
  - Source full `std_vec_macro_surface.sa`: pass (`16 passed`).
  - Source full `std_string_macro_surface.sa`: pass (`20 passed`).
  - `zig build unit-framework --summary all`: pass (`6/6 steps succeeded; 5/5 tests passed`).
- Install sync status:
  - `./tools/install.sh --no-shell`: pass.
  - Installed-state focused `from_elem` test: pass.
  - Installed-state full `std_vec_macro_surface.sa`: pass (`16 passed`).
  - Installed-state full `std_string_macro_surface.sa`: pass (`20 passed`).

## Completed: 2026-07-06 Vec peek_mut facade batch

- Continued Vec Rust API parity work with the supportable `Vec::peek_mut` U64 subset.
- Added Vec mutable-peek macro surfaces:
  - `VEC_TRY_PEEK_MUT`
  - `VEC_TRY_PEEK_MUT_U64`
- Semantics: returns `ok=1` and a mutable pointer to the last element when the Vec is non-empty; returns `ok=0` and a null pointer for an empty Vec.
- Scope note: this is the SA mutable-pointer shape for U64/general element size. It does not claim Rust's full `PeekMut` guard/drop object model.
- Implementation note: the macro reads `Vec_ptr` and `Vec_len` directly from the owned Vec wrapper so the returned pointer is not derived from a temporary slice view.
- Updated `std_vec_macro_surface.sa` coverage:
  - empty Vec returns failure/null pointer.
  - non-empty Vec returns a non-null pointer to the last element.
  - writing through the returned pointer updates `VEC_TRY_LAST_U64` while preserving length.
- Validation status:
  - Source focused `peek_mut` test: pass.
  - Source full `std_vec_macro_surface.sa`: pass (`15 passed`).
  - Source full `std_string_macro_surface.sa`: pass (`20 passed`).
  - `zig build unit-framework --summary all`: pass (`6/6 steps succeeded; 5/5 tests passed`).
- Install sync status:
  - `./tools/install.sh --no-shell`: pass.
  - Installed-state focused `peek_mut` test: pass.
  - Installed-state full `std_vec_macro_surface.sa`: pass (`15 passed`).
  - Installed-state full `std_string_macro_surface.sa`: pass (`20 passed`).

## Completed: 2026-07-06 Vec retain_mut facade batch

- Continued Vec Rust API parity work with the supportable `Vec::retain_mut` U64 subset.
- Added Vec mutable-retain macro surface:
  - `VEC_RETAIN_MUT_U64`
- Semantics: the predicate receives a pointer to each U64 element, may mutate that element in place, and returns a keep flag. If kept, the macro reloads the possibly mutated value from the read pointer before compacting it into the write position.
- Scope note: this is the SA function-pointer/U64 shape; it does not claim Rust's full generic closure and allocator-parametric surface.
- Updated `std_vec_macro_surface.sa` coverage:
  - predicate adds `10` to every visited element.
  - predicate keeps elements whose original value was odd.
  - vector `[1,2,3,4]` becomes `[11,13]`, validating both mutation and retain compaction.
- Validation status:
  - Source focused `retain_mut` test: pass.
  - Source full `std_vec_macro_surface.sa`: pass (`14 passed`).
  - Source full `std_string_macro_surface.sa`: pass (`20 passed`).
  - `zig build unit-framework --summary all`: pass (`6/6 steps succeeded; 5/5 tests passed`).
- Install sync status:
  - `./tools/install.sh --no-shell`: pass.
  - Installed-state focused `retain_mut` test: pass.
  - Installed-state full `std_vec_macro_surface.sa`: pass (`14 passed`).
  - Installed-state full `std_string_macro_surface.sa`: pass (`20 passed`).

## Completed: 2026-07-06 StringBuf Unicode push/insert char batch

- Continued String Rust API parity work by correcting `String::push(char)`, `String::insert(idx, char)`, and `String::insert_str(idx, str)` behavior.
- Behavior changes:
  - `STRING_BUF_TRY_PUSH_CHAR` / `STRING_BUF_PUSH_CHAR` now encode any valid Unicode scalar to UTF-8 before appending.
  - `STRING_BUF_TRY_INSERT_CHAR` / `STRING_BUF_INSERT_CHAR` now encode any valid Unicode scalar to UTF-8 before insertion.
  - `STRING_BUF_TRY_INSERT_STR` / `STRING_BUF_INSERT_STR` now require the byte index to be a UTF-8 char boundary, matching Rust `String::insert_str`.
  - invalid scalar values, including surrogate codepoints, are rejected without mutating the string.
- Implementation note: the macros reuse `CHAR_TRY_ENCODE_UTF8` from `sa_std/char.sa` and route encoded char insertion through `STRING_BUF_TRY_INSERT_STR` so char-boundary behavior is shared.
- Updated `std_string_macro_surface.sa` coverage:
  - ASCII push/insert still works.
  - pushing `é` succeeds.
  - inserting `🙂` succeeds.
  - invalid surrogate `55296` is rejected.
  - insertion at a continuation byte inside `🙂` fails and leaves the string unchanged.
- Validation status:
  - Source focused `unicode char` test: pass.
  - Source full `std_string_macro_surface.sa`: pass (`20 passed`).
  - Source full `std_vec_macro_surface.sa`: pass (`13 passed`).
  - `zig build unit-framework --summary all`: pass (`6/6 steps succeeded; 5/5 tests passed`).
- Install sync status:
  - `./tools/install.sh --no-shell`: pass.
  - Installed-state focused `unicode char` test: pass.
  - Installed-state full `std_string_macro_surface.sa`: pass (`20 passed`).
  - Installed-state full `std_vec_macro_surface.sa`: pass (`13 passed`).

## Completed: 2026-07-06 StringBuf retain facade batch

- Continued String Rust API parity work with the supportable `String::retain` subset.
- Added StringBuf predicate-retain macro surfaces:
  - `STRING_BUF_TRY_RETAIN`
  - `STRING_BUF_RETAIN`
- Semantics: the macro decodes the source by UTF-8 scalar, calls a user predicate with the Unicode codepoint, copies retained scalar slices into a new `StringBuf`, then replaces the original buffer. `TRY_RETAIN` returns `ok=0` and leaves the original unchanged if internal UTF-8 decoding fails.
- Scope note: this is the SA function-pointer predicate form; it does not claim Rust closure capture or full trait/iterator machinery.
- Updated `std_string_macro_surface.sa` coverage:
  - retain `aé` from `aé🙂z` by dropping `🙂` and `z`.
  - retain-none alias path empties the string and returns length `0`.
- Validation status:
  - Source focused `retain` test: pass.
  - Source full `std_string_macro_surface.sa`: pass (`20 passed`).
  - Source full `std_vec_macro_surface.sa`: pass (`13 passed`).
  - `zig build unit-framework --summary all`: pass (`6/6 steps succeeded; 5/5 tests passed`).
- Install sync status:
  - `./tools/install.sh --no-shell`: pass.
  - Installed-state focused `retain` test: pass.
  - Installed-state full `std_string_macro_surface.sa`: pass (`20 passed`).
  - Installed-state full `std_vec_macro_surface.sa`: pass (`13 passed`).

## Completed: 2026-07-06 StringBuf split_off boundary parity batch

- Continued String Rust API parity work by correcting existing `STRING_BUF_TRY_SPLIT_OFF` / `STRING_BUF_SPLIT_OFF` semantics to match Rust `String::split_off` char-boundary requirements.
- Behavior change: split indexes must now be UTF-8 char boundaries. Invalid/non-boundary indexes return `ok=0`, return an empty tail `StringBuf`, and leave the original buffer unchanged.
- Implementation note: the macro now checks `STR_IS_CHAR_BOUNDARY` on the current `StringBuf` view before delegating to the existing Vec split path.
- Updated `std_string_macro_surface.sa` coverage:
  - successful UTF-8 split at byte index `3` in `aé🙂z`, leaving `aé` and returning `🙂z`.
  - failed split at continuation byte index `2`, preserving the original string and returning an empty tail.
- Validation status:
  - Source focused `split_off char` test: pass.
  - Source full `std_string_macro_surface.sa`: pass (`19 passed`).
  - Source full `std_vec_macro_surface.sa`: pass (`13 passed`).
  - `zig build unit-framework --summary all`: pass (`6/6 steps succeeded; 5/5 tests passed`).
- Install sync status:
  - `./tools/install.sh --no-shell`: pass.
  - Installed-state focused `split_off char` test: pass.
  - Installed-state full `std_string_macro_surface.sa`: pass (`19 passed`).
  - Installed-state full `std_vec_macro_surface.sa`: pass (`13 passed`).

## Completed: 2026-07-06 StringBuf drain(range) facade batch

- Continued String Rust API parity work with the supportable `String::drain(range)` subset.
- Added StringBuf range-drain macro surfaces:
  - `STRING_BUF_TRY_DRAIN`
  - `STRING_BUF_DRAIN`
- Semantics: successful drain copies the selected UTF-8 range into a returned `StringBuf`, then removes that range from the original buffer. Invalid bounds or non-char-boundary ranges return `ok=0`, return an empty `StringBuf`, and leave the original buffer unchanged.
- Scope note: this is the SA macro-friendly eager range-drain shape; it does not claim Rust's lazy `Drain` iterator object model.
- Implementation note: the macro reuses `STR_TRY_GET_RANGE` for bounds and UTF-8 boundary checks, then `STRING_BUF_TRY_REPLACE_RANGE` with an empty replacement.
- Updated `std_string_macro_surface.sa` coverage:
  - UTF-8 drain of `é🙂` from `aé🙂z`, returning `é🙂` and leaving `az`.
  - alias drain of `-` from `rust-std`, returning `-` and leaving `ruststd`.
  - non-char-boundary drain failure returns empty output and leaves the source unchanged.
- Validation status:
  - Source focused `drain` test: pass.
  - Source full `std_string_macro_surface.sa`: pass (`18 passed`).
  - Source full `std_vec_macro_surface.sa`: pass (`13 passed`).
  - `zig build unit-framework --summary all`: pass (`6/6 steps succeeded; 5/5 tests passed`).
- Install sync status:
  - `./tools/install.sh --no-shell`: pass.
  - Installed-state focused `drain` test: pass.
  - Installed-state full `std_string_macro_surface.sa`: pass (`18 passed`).
  - Installed-state full `std_vec_macro_surface.sa`: pass (`13 passed`).

## Completed: 2026-07-06 StringBuf pop() facade batch

- Continued String Rust API parity work with the supportable `String::pop()` char-aware subset.
- Added StringBuf tail-pop macro surfaces:
  - `STRING_BUF_TRY_POP_CHAR`
  - `STRING_BUF_POP_CHAR`
- Semantics: successful pop returns the Unicode codepoint for the final UTF-8 scalar and truncates the buffer to that scalar's start byte; empty strings return `ok=0` and clear the codepoint output. This is distinct from the existing byte-level `STRING_BUF_TRY_POP_BYTE` / `STRING_BUF_POP_BYTE` helpers.
- Implementation note: the macro is runtime-free and reuses the previous batch's `STR_TRY_CHAR_AT_BYTE` helper plus `STR_FLOOR_CHAR_BOUNDARY`, then truncates in place.
- Updated `std_string_macro_surface.sa` coverage:
  - sequentially pops `z`, `🙂`, `é`, and `a` from `aé🙂z`.
  - verifies returned codepoints and intermediate string values.
  - verifies popping an empty buffer fails and leaves it empty.
- Validation status:
  - Source focused `pop char` test: pass.
  - Source full `std_string_macro_surface.sa`: pass (`17 passed`).
  - Source full `std_vec_macro_surface.sa`: pass (`13 passed`).
  - `zig build unit-framework --summary all`: pass (`6/6 steps succeeded; 5/5 tests passed`).
- Install sync status:
  - `./tools/install.sh --no-shell`: pass.
  - Installed-state focused `pop char` test: pass.
  - Installed-state full `std_string_macro_surface.sa`: pass (`17 passed`).
  - Installed-state full `std_vec_macro_surface.sa`: pass (`13 passed`).

## Completed: 2026-07-06 StringBuf remove(idx) facade batch

- Continued String Rust API parity work with the supportable `String::remove(idx)` byte-index subset.
- Added UTF-8 byte-index decode helper surfaces:
  - runtime export `sa_str_utf8_char_at_byte`
  - SA extern `sa_str_utf8_char_at_byte`
  - macros `STR_TRY_CHAR_AT_BYTE` and `STRING_TRY_CHAR_AT_BYTE`
- Added StringBuf remove-char macro surfaces:
  - `STRING_BUF_TRY_REMOVE_CHAR_AT`
  - `STRING_BUF_REMOVE_CHAR_AT`
- Semantics: successful removal returns the Unicode codepoint and removes the full UTF-8 scalar at the supplied byte index; out-of-bounds indexes and continuation-byte indexes return `ok=0`, clear the codepoint output, and leave the string unchanged.
- Updated `std_string_macro_surface.sa` coverage:
  - byte-index decode for `é` and `🙂`, including UTF-8 byte width.
  - removal of ASCII, 2-byte, 4-byte, and trailing ASCII chars from `aé🙂z`.
  - failure on continuation-byte and end indexes leaves the buffer unchanged.
- Validation status:
  - `zig build sa-std-static --summary all`: pass (`5/5 steps succeeded`).
  - `nm -g zig-out/lib/libsa_std.a artifacts/sa_std/libsa_std.a | rg 'sa_str_utf8_char_at_byte'`: pass, symbol exported in both libs.
  - Source focused remove-char test: pass.
  - Source focused UTF-8 byte/char helper test: pass.
  - Source full `std_string_macro_surface.sa`: pass (`16 passed`).
  - Source full `std_vec_macro_surface.sa`: pass (`13 passed`).
  - `zig build unit-framework --summary all`: pass (`6/6 steps succeeded; 5/5 tests passed`).
- Install sync status:
  - `./tools/install.sh --no-shell`: pass.
  - Installed-state focused remove-char test: pass.
  - Installed-state focused UTF-8 byte/char helper test: pass.
  - Installed-state full `std_string_macro_surface.sa`: pass (`16 passed`).
  - Installed-state full `std_vec_macro_surface.sa`: pass (`13 passed`).

## Completed: 2026-07-06 StringBuf extend_from_within facade batch

- Continued String Rust API parity work with the supportable `String::extend_from_within` subset.
- Added StringBuf range-copy macro surfaces:
  - `STRING_BUF_TRY_EXTEND_FROM_WITHIN`
  - `STRING_BUF_EXTEND_FROM_WITHIN`
- Implementation note: the macro first copies the selected range into a temporary `StringBuf`, then appends that temporary view back into the original buffer. This avoids dangling source slices if appending triggers reserve/reallocation on the original string.
- Range semantics reuse `STR_TRY_GET_RANGE`, so both bounds and UTF-8 char-boundary checks are enforced.
- Updated `std_string_macro_surface.sa` coverage:
  - normal range append.
  - alias wrapper append.
  - out-of-bounds miss leaves the string unchanged.
  - non-char-boundary UTF-8 range miss leaves the string unchanged.
- Validation status:
  - Source focused `extend_from_within` test: pass.
  - Source full `std_string_macro_surface.sa`: pass (`15 passed`).
  - Source full `std_vec_macro_surface.sa`: pass (`13 passed`).
  - `zig build unit-framework --summary all`: pass (`6/6 steps succeeded; 5/5 tests passed`).
- Install sync status:
  - `./tools/install.sh --no-shell`: pass.
  - Installed-state focused `extend_from_within` test: pass.
  - Installed-state full `std_string_macro_surface.sa`: pass (`15 passed`).
  - Installed-state full `std_vec_macro_surface.sa`: pass (`13 passed`).

## Completed: 2026-07-06 Vec NonNull parts facade batch

- Continued Vec Rust API parity work with the supportable NonNull parts subset.
- Added Vec NonNull/parts macro surfaces over the existing `NonNull` wrapper facade:
  - `VEC_AS_NON_NULL`
  - `VEC_INTO_PARTS`
  - `VEC_FROM_PARTS`
- Implementation note: `VEC_INTO_PARTS` transfers the Vec buffer pointer into a `NonNull` wrapper and zeros the consumed Vec wrapper; `VEC_FROM_PARTS` reloads the pointer and reconstitutes Vec ownership.
- Updated `std_vec_macro_surface.sa` coverage:
  - `VEC_AS_NON_NULL` returns a non-null view without consuming the Vec.
  - `VEC_INTO_PARTS` / `VEC_FROM_PARTS` roundtrip pointer/len/cap and preserve elements.
- Validation status:
  - Source focused `raw parts` test: pass.
  - Source focused `NonNull parts` test: pass.
  - Source full `std_vec_macro_surface.sa`: pass (`13 passed`).
  - Source full `std_string_macro_surface.sa`: pass (`14 passed`).
  - `zig build unit-framework --summary all`: pass (`6/6 steps succeeded; 5/5 tests passed`).
- Install sync status:
  - `./tools/install.sh --no-shell`: pass.
  - Installed-state focused `raw parts` and `NonNull parts` Vec tests: pass.
  - Installed-state full `std_vec_macro_surface.sa`: pass (`13 passed`).
  - Installed-state full `std_string_macro_surface.sa`: pass (`14 passed`).

## Completed: 2026-07-06 StringBuf remove_matches and Vec from_fn facade batch

- Continued String/Vec Rust API parity work with another supportable macro-only batch.
- Added Vec indexed generation macro surfaces corresponding to the supportable shape of Rust `Vec::from_fn`:
  - `VEC_FROM_FN`
  - `VEC_FROM_FN_U64`
- Added StringBuf slice-pattern removal surface corresponding to the supportable shape of Rust `String::remove_matches`:
  - `STRING_BUF_REMOVE_MATCHES`
- Scope note: `STRING_BUF_REMOVE_MATCHES` covers slice patterns via the existing `STRING_BUF_REPLACE` engine; it does not claim full Rust `Pattern` trait coverage.
- Updated macro-surface tests:
  - `std_vec_macro_surface.sa`: verifies generated values use ascending indexes and that zero-length generation returns an empty Vec.
  - `std_string_macro_surface.sa`: verifies match removal, overlapping-match behavior (`banana ana` / `ana`), and miss/no-op behavior.
- Validation status:
  - Source focused String remove-matches path: pass.
  - Source focused Vec from_fn path: pass.
  - Source full `std_string_macro_surface.sa`: pass (`14 passed`).
  - Source full `std_vec_macro_surface.sa`: pass (`12 passed`).
  - `zig build unit-framework --summary all`: pass (`6/6 steps succeeded; 5/5 tests passed`).
- Install sync status:
  - `./tools/install.sh --no-shell`: pass.
  - Installed-state focused String remove-matches and Vec from_fn tests: pass.
  - Installed-state full `std_string_macro_surface.sa`: pass (`14 passed`).
  - Installed-state full `std_vec_macro_surface.sa`: pass (`12 passed`).

## Completed: 2026-07-06 StringBuf/Vec mut-return and replace facade batch

- Continued the String/Vec Rust API parity audit after the raw-parts batch.
- Added Vec mut-return macro surfaces matching the supportable shape of Rust `Vec::push_mut` / `Vec::insert_mut`:
  - `VEC_PUSH_MUT`
  - `VEC_PUSH_MUT_U64`
  - `VEC_TRY_INSERT_MUT`
  - `VEC_TRY_INSERT_MUT_U64`
  - `VEC_INSERT_MUT`
  - `VEC_INSERT_MUT_U64`
- Added StringBuf first/last replacement macro surfaces over existing find/rfind and replace-range helpers:
  - `STRING_BUF_TRY_REPLACE_FIRST`
  - `STRING_BUF_REPLACE_FIRST`
  - `STRING_BUF_TRY_REPLACE_LAST`
  - `STRING_BUF_REPLACE_LAST`
- Implementation note: mut-return Vec macros read from the owned Vec fields directly, not through borrow views, so returned element pointers remain usable by the caller.
- Validation status:
  - Source focused String replace test: pass.
  - Source focused Vec mut-return test: pass.
  - Source full `std_string_macro_surface.sa`: pass (`14 passed`).
  - Source full `std_vec_macro_surface.sa`: pass (`11 passed`).
  - `zig build unit-framework --summary all`: pass (`6/6 steps succeeded; 5/5 tests passed`).
- Install sync status:
  - `./tools/install.sh --no-shell`: pass.
  - Installed-state focused String replace and Vec mut-return tests: pass.
  - Installed-state full `std_string_macro_surface.sa`: pass (`14 passed`).
  - Installed-state full `std_vec_macro_surface.sa`: pass (`11 passed`).

## Completed: 2026-07-06 StringBuf/Vec raw-parts facade batch

- Audited `sa_std/string.sa` and `sa_std/vec.sa` against Rust `alloc::string::String` and `alloc::vec::Vec` public APIs.
- Finding: current SA facades are broad but not full Rust API coverage; remaining gaps include larger iterator/drain/splice/leak/boxed/UTF conversion/trait surfaces that need separate supportable batches.
- Added raw-parts macro surfaces for the supportable ownership-transfer subset:
  - `VEC_INTO_RAW_PARTS`
  - `VEC_FROM_RAW_PARTS`
  - `STRING_BUF_INTO_RAW_PARTS`
  - `STRING_BUF_FROM_RAW_PARTS`
- Fixed the `Vec` raw-parts implementation to take `Vec_ptr` directly from the owned Vec instead of through a borrow view, so the returned raw pointer remains usable and can be re-owned by `from_raw_parts`.
- Updated macro-surface tests:
  - `tests/unit_framework/std_vec_macro_surface.sa`: raw pointer/len/cap extraction and Vec reconstruction preserves elements.
  - `tests/unit_framework/std_string_macro_surface.sa`: StringBuf raw-parts reconstruction preserves `rust-std` content.
- Validation status:
  - Source focused raw-parts String/Vec tests: pass.
  - Source full `std_vec_macro_surface.sa`: pass (`10 passed`).
  - Source full `std_string_macro_surface.sa`: pass (`14 passed`).
  - `zig build unit-framework --summary all`: pass (`6/6 steps succeeded; 5/5 tests passed`).
- Install sync status:
  - `./tools/install.sh --no-shell`: pass.
  - Installed-state focused raw-parts String/Vec tests: pass.
  - Installed-state full `std_vec_macro_surface.sa`: pass (`10 passed`).
  - Installed-state full `std_string_macro_surface.sa`: pass (`14 passed`).

## Completed: 2026-07-06 RawFd/BorrowedFd named facade batch

- Added Rust-named raw/borrowed fd macro surfaces over the existing fd facade:
  - `FD_RAW_AS_RAW_FD`
  - `FD_RAW_INTO_RAW_FD`
  - `FD_RAW_FROM_RAW_FD`
  - `FD_BORROWED_BORROW_RAW`
  - `FD_BORROWED_AS_RAW_FD`
  - `FD_BORROWED_TRY_CLONE_TO_OWNED`
- Added runtime/header/SA contract export for cloning a borrowed raw fd into an owned fd handle:
  - `sa_std_fd_dup_raw`
- Updated `tests/unit_framework/std_os_fd_macro_surface.sa` coverage:
  - raw fd reflexive macros preserve the fd value.
  - borrowed raw fd clone creates an owned fd that remains readable after closing the original File handle.
- Validation status:
  - `zig build sa-std-static --summary all`: pass (`5/5 steps succeeded`).
  - `nm -g zig-out/lib/libsa_std.a artifacts/sa_std/libsa_std.a | rg 'sa_std_fd_dup_raw'`: pass, symbol exported in both libs.
  - `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_os_fd_macro_surface.sa --filter "raw borrowed fd" --trace-panic --no-incremental`: pass (`1 passed`).
  - `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_os_fd_macro_surface.sa --trace-panic --no-incremental`: pass (`4 passed`).
  - `zig build unit-framework --summary all`: pass (`6/6 steps succeeded; 5/5 tests passed`).
- Install sync status:
  - `./tools/install.sh --no-shell`: pass.
  - Installed-state smoke with `SA_STD_DIR=/home/vscode/.sa/std /home/vscode/.sa/bin/sa test tests/unit_framework/std_os_fd_macro_surface.sa --filter "raw borrowed fd" --trace-panic --no-incremental`: pass (`1 passed`).
  - Installed-state smoke with `SA_STD_DIR=/home/vscode/.sa/std /home/vscode/.sa/bin/sa test tests/unit_framework/std_os_fd_macro_surface.sa --trace-panic --no-incremental`: pass (`4 passed`).

## Completed: 2026-07-06 OwnedFd named facade batch

- Added Rust-named `OwnedFd` macro aliases over the existing `sa_std/os/fd` raw/dup ABI:
  - `FD_OWNED_AS_RAW_FD`
  - `FD_OWNED_INTO_RAW_FD`
  - `FD_OWNED_FROM_RAW_FD`
  - `FD_OWNED_TRY_CLONE`
  - runtime behavior is unchanged; this batch does not add exported symbols.
- Updated `tests/unit_framework/std_os_fd_macro_surface.sa` coverage:
  - File is converted into an owned fd, then exercised through the `OwnedFd` named raw-fd and clone macros.
  - cloned owned fd is roundtripped through raw fd and closed while the original owned fd remains readable, validating independent close lifetime for the fd-dup path.
- Validation status:
  - `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_os_fd_macro_surface.sa --filter "owned fd named" --trace-panic --no-incremental`: pass (`1 passed`).
  - `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_os_fd_macro_surface.sa --trace-panic --no-incremental`: pass (`3 passed`).
  - `zig build unit-framework --summary all`: pass (`6/6 steps succeeded; 5/5 tests passed`).
- Install sync status:
  - `./tools/install.sh --no-shell`: pass.
  - Installed-state smoke with `SA_STD_DIR=/home/vscode/.sa/std /home/vscode/.sa/bin/sa test tests/unit_framework/std_os_fd_macro_surface.sa --filter "owned fd named" --trace-panic --no-incremental`: pass (`1 passed`).
  - Installed-state smoke with `SA_STD_DIR=/home/vscode/.sa/std /home/vscode/.sa/bin/sa test tests/unit_framework/std_os_fd_macro_surface.sa --trace-panic --no-incremental`: pass (`3 passed`).

## Completed: 2026-07-06 File raw/owned fd facade batch

- Added `std::fs::File` raw-fd and owned-fd trait-style macro surfaces:
  - `FS_FILE_AS_RAW_FD`
  - `FS_FILE_INTO_RAW_FD`
  - `FS_FILE_FROM_RAW_FD`
  - `FS_FILE_INTO_OWNED_FD`
  - `FS_FILE_FROM_OWNED_FD`
- Added runtime/header/SA contract export for the File-restoring path:
  - `sa_std_fs_file_from_raw_fd`
  - `as_raw_fd` and `into_raw_fd` reuse the existing `sa_std/os/fd` ABI.
- Runtime behavior:
  - validates non-negative raw fds.
  - registers valid raw fds back as the existing `.file` resource kind, so File-only APIs such as `FS_READ_AT` keep working after `from_raw_fd` / `from_owned_fd`.
- Updated `tests/unit_framework/std_os_fd_macro_surface.sa` coverage:
  - File handle roundtrips through `as_raw_fd`, `into_owned_fd` / `from_owned_fd`, and `into_raw_fd` / `from_raw_fd`.
  - rebound File handles are verified with `FS_READ_AT` before close and cleanup.
- Validation status:
  - `zig build sa-std-static --summary all`: pass (`5/5 steps succeeded`).
  - `nm -g zig-out/lib/libsa_std.a artifacts/sa_std/libsa_std.a | rg 'sa_std_fs_file_from_raw_fd'`: pass, symbol exported in both libs.
  - `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_os_fd_macro_surface.sa --filter "fs file raw owned fd" --trace-panic --no-incremental`: pass (`1 passed`).
  - `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_os_fd_macro_surface.sa --trace-panic --no-incremental`: pass (`2 passed`).
  - `zig build unit-framework --summary all`: pass (`6/6 steps succeeded; 5/5 tests passed`).
- Install sync status:
  - `./tools/install.sh --no-shell`: pass.
  - Installed-state smoke with `SA_STD_DIR=/home/vscode/.sa/std /home/vscode/.sa/bin/sa test tests/unit_framework/std_os_fd_macro_surface.sa --filter "fs file raw owned fd" --trace-panic --no-incremental`: pass (`1 passed`).
  - Installed-state smoke with `SA_STD_DIR=/home/vscode/.sa/std /home/vscode/.sa/bin/sa test tests/unit_framework/std_os_fd_macro_surface.sa --trace-panic --no-incremental`: pass (`2 passed`).

## Completed: 2026-07-06 stdio raw fd alias batch

- Added borrowed stdio handle and raw-fd macro surfaces over the fixed runtime stdio handles and existing `sa_std/os/fd` raw-fd facade:
  - `IO_STDIN`
  - `IO_STDOUT`
  - `IO_STDERR`
  - `IO_STDIN_AS_RAW_FD`
  - `IO_STDOUT_AS_RAW_FD`
  - `IO_STDERR_AS_RAW_FD`
- Scope note:
  - this batch intentionally exposes borrowed `as_raw_fd`-style access only for stdio; it does not add `into_raw_fd` or ownership-transfer semantics for the process stdio handles.
  - runtime continues to use the fixed stdio handles (`1/2/3`) and `handleToFd` mapping to OS fds (`0/1/2`), so this batch does not add exported symbols.
- Updated `tests/unit_framework/std_io_utility_macro_surface.sa` coverage:
  - stdio handle macros return the fixed SA stdio handles.
  - stdio raw-fd macros return `SA_IO_OK` and fds `0`, `1`, and `2`.
- Validation status:
  - `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_io_utility_macro_surface.sa --filter "stdio raw fd" --trace-panic --no-incremental`: pass (`1 passed`).
  - `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_io_utility_macro_surface.sa --trace-panic --no-incremental`: pass (`4 passed`).
  - `zig build unit-framework --summary all`: pass (`6/6 steps succeeded; 5/5 tests passed`).
- Install sync status:
  - `./tools/install.sh --no-shell`: pass.
  - Installed-state smoke with `SA_STD_DIR=/home/vscode/.sa/std /home/vscode/.sa/bin/sa test tests/unit_framework/std_io_utility_macro_surface.sa --filter "stdio raw fd" --trace-panic --no-incremental`: pass (`1 passed`).
  - Installed-state smoke with `SA_STD_DIR=/home/vscode/.sa/std /home/vscode/.sa/bin/sa test tests/unit_framework/std_io_utility_macro_surface.sa --trace-panic --no-incremental`: pass (`4 passed`).

## Completed: 2026-07-06 UDP socket owned fd alias batch

- Added UDP `UdpSocket` owned-fd conversion macro aliases over the UDP raw-fd facades and `sa_std/os/fd` owned-fd ABI:
  - `NET_UDP_INTO_OWNED_FD`
  - `NET_UDP_FROM_OWNED_FD`
  - runtime continues to use the UDP raw-fd restore export from the previous batch, so this batch does not add exported symbols.
- Updated `tests/unit_framework/std_net_macro_surface.sa` UDP fd coverage:
  - UDP socket now transfers ownership through an owned fd and rebinds before continuing through the existing raw-fd roundtrip, self-send, receive, and close path.
- Validation status:
  - `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_net_macro_surface.sa --filter "udp raw fd" --trace-panic --no-incremental`: pass (`1 passed`).
  - `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_net_macro_surface.sa --trace-panic --no-incremental`: pass (`12 passed`).
  - `zig build unit-framework --summary all`: pass (`6/6 steps succeeded; 5/5 tests passed`).
- Install sync status:
  - `./tools/install.sh --no-shell`: pass.
  - Installed-state smoke with `SA_STD_DIR=/home/vscode/.sa/std /home/vscode/.sa/bin/sa test tests/unit_framework/std_net_macro_surface.sa --filter "udp raw fd" --trace-panic --no-incremental`: pass (`1 passed`).
  - Installed-state smoke with `SA_STD_DIR=/home/vscode/.sa/std /home/vscode/.sa/bin/sa test tests/unit_framework/std_net_macro_surface.sa --trace-panic --no-incremental`: pass (`12 passed`).

## Completed: 2026-07-06 UDP socket raw fd trait batch

- Added UDP `UdpSocket` raw-fd trait-style macro surface:
  - `NET_UDP_AS_RAW_FD`
  - `NET_UDP_INTO_RAW_FD`
  - `NET_UDP_FROM_RAW_FD`
- Added runtime/header export for the ownership-restoring path:
  - `sa_std_net_udp_from_raw_fd`
  - `as_raw_fd` and `into_raw_fd` reuse the existing `sa_std/os/fd` ABI.
- Runtime behavior:
  - validates restored fds as AF_INET/AF_INET6 datagram sockets.
  - registers valid raw fds back as the existing `udp_socket` resource kind.
- Extended `tests/unit_framework/std_net_macro_surface.sa` coverage:
  - UDP socket handle roundtrips through `as_raw_fd` / `into_raw_fd` / `from_raw_fd`.
  - rebound socket sends a datagram to its own bound port and receives it back before close.
- Validation status:
  - `zig build sa-std-static --summary all`: pass.
  - `nm -g zig-out/lib/libsa_std.a artifacts/sa_std/libsa_std.a | rg 'sa_std_net_udp_from_raw_fd'`: pass, symbol exported in both libs.
  - `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_net_macro_surface.sa --filter "udp raw fd" --trace-panic --no-incremental`: pass (`1 passed`).
  - `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_net_macro_surface.sa --trace-panic --no-incremental`: pass (`12 passed`).
  - `zig build unit-framework --summary all`: pass (`6/6 steps succeeded; 5/5 tests passed`).
- Install sync status:
  - `./tools/install.sh --no-shell`: pass.
  - Installed-state smoke with `SA_STD_DIR=/home/vscode/.sa/std /home/vscode/.sa/bin/sa test tests/unit_framework/std_net_macro_surface.sa --filter "udp raw fd" --trace-panic --no-incremental`: pass (`1 passed`).
  - Installed-state smoke with `SA_STD_DIR=/home/vscode/.sa/std /home/vscode/.sa/bin/sa test tests/unit_framework/std_net_macro_surface.sa --trace-panic --no-incremental`: pass (`12 passed`).

## Completed: 2026-07-06 TCP stream/listener owned fd alias batch

- Added TCP `TcpStream` / `TcpListener` owned-fd conversion macro aliases over the TCP raw-fd facades and `sa_std/os/fd` owned-fd ABI:
  - `NET_TCP_STREAM_INTO_OWNED_FD`
  - `NET_TCP_STREAM_FROM_OWNED_FD`
  - `NET_TCP_LISTENER_INTO_OWNED_FD`
  - `NET_TCP_LISTENER_FROM_OWNED_FD`
  - runtime continues to use the TCP raw-fd restore exports from the previous batch, so this batch does not add exported symbols.
- Updated `tests/unit_framework/std_net_macro_surface.sa` TCP fd coverage:
  - listener, connected client stream, and accepted server stream now transfer ownership through an owned fd and rebind before continuing through the existing raw-fd roundtrip and byte exchange path.
- Validation status:
  - `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_net_macro_surface.sa --filter "tcp raw fd" --trace-panic --no-incremental`: pass (`1 passed`).
  - `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_net_macro_surface.sa --trace-panic --no-incremental`: pass (`11 passed`).
  - `zig build unit-framework --summary all`: pass (`6/6 steps succeeded; 5/5 tests passed`).
- Install sync status:
  - `./tools/install.sh --no-shell`: pass.
  - Installed-state smoke with `SA_STD_DIR=/home/vscode/.sa/std /home/vscode/.sa/bin/sa test tests/unit_framework/std_net_macro_surface.sa --filter "tcp raw fd" --trace-panic --no-incremental`: pass (`1 passed`).
  - Installed-state smoke with `SA_STD_DIR=/home/vscode/.sa/std /home/vscode/.sa/bin/sa test tests/unit_framework/std_net_macro_surface.sa --trace-panic --no-incremental`: pass (`11 passed`).

## Completed: 2026-07-06 TCP stream/listener raw fd trait batch

- Added TCP `TcpStream` / `TcpListener` raw-fd trait-style macro surface:
  - `NET_TCP_STREAM_AS_RAW_FD`
  - `NET_TCP_STREAM_INTO_RAW_FD`
  - `NET_TCP_STREAM_FROM_RAW_FD`
  - `NET_TCP_LISTENER_AS_RAW_FD`
  - `NET_TCP_LISTENER_INTO_RAW_FD`
  - `NET_TCP_LISTENER_FROM_RAW_FD`
- Added runtime/header exports for the ownership-restoring paths:
  - `sa_std_net_tcp_stream_from_raw_fd`
  - `sa_std_net_tcp_listener_from_raw_fd`
  - `as_raw_fd` and `into_raw_fd` reuse the existing `sa_std/os/fd` ABI.
- Runtime behavior:
  - validates restored fds as AF_INET/AF_INET6 stream sockets.
  - listener `from_raw_fd` requires `SO_ACCEPTCONN` and restores `std.net.Server.listen_address` from `getsockname`.
  - stream `from_raw_fd` rejects accepting/listener sockets and registers the fd as a TCP stream handle.
- Extended `tests/unit_framework/std_net_macro_surface.sa` coverage:
  - listener, connected client stream, and accepted server stream all roundtrip through `as_raw_fd` / `into_raw_fd` / `from_raw_fd`.
  - rebound client/server handles exchange bytes before both handles close.
- Validation status:
  - `zig build sa-std-static --summary all`: pass.
  - `nm -g zig-out/lib/libsa_std.a | rg 'sa_std_net_tcp_(stream|listener)_from_raw_fd'`: pass, both symbols exported.
  - `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_net_macro_surface.sa --filter "tcp raw fd" --trace-panic --no-incremental`: pass (`1 passed`).
  - `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_net_macro_surface.sa --trace-panic --no-incremental`: pass (`11 passed`).
  - `zig build unit-framework --summary all`: pass (`6/6 steps succeeded; 5/5 tests passed`).
- Install sync status:
  - `./tools/install.sh --no-shell`: pass.
  - Installed-state smoke with `SA_STD_DIR=/home/vscode/.sa/std /home/vscode/.sa/bin/sa test tests/unit_framework/std_net_macro_surface.sa --filter "tcp raw fd" --trace-panic --no-incremental`: pass (`1 passed`).
  - Installed-state smoke with `SA_STD_DIR=/home/vscode/.sa/std /home/vscode/.sa/bin/sa test tests/unit_framework/std_net_macro_surface.sa --trace-panic --no-incremental`: pass (`11 passed`).

## Completed: 2026-07-06 Child stdout/stderr owned fd alias batch

- Added Unix process child pipe owned-fd trait-style macro aliases over the existing raw-fd and `sa_std/os/fd` owned-fd facades:
  - `PROCESS_CHILD_STDOUT_INTO_OWNED_FD`
  - `PROCESS_CHILD_STDOUT_FROM_OWNED_FD`
  - `PROCESS_CHILD_STDERR_INTO_OWNED_FD`
  - `PROCESS_CHILD_STDERR_FROM_OWNED_FD`
  - runtime continues to use the existing fd ABI, so this batch does not add exported symbols.
- Updated `tests/unit_framework/std_process_macro_surface.sa` stream-spawn coverage:
  - stdout and stderr handles now transfer ownership through an owned fd and rebind before continuing through the existing raw-fd roundtrip, wait, and close path.
- Validation status:
  - `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_process_macro_surface.sa --filter "spawn modes" --trace-panic --no-incremental`: pass (`1 passed`).
  - `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_process_macro_surface.sa --trace-panic --no-incremental`: pass (`14 passed`).
  - `zig build unit-framework --summary all`: pass (`6/6 steps succeeded; 5/5 tests passed`).
- Install sync status:
  - `./tools/install.sh --no-shell`: pass.
  - Installed-state smoke with `SA_STD_DIR=/home/vscode/.sa/std /home/vscode/.sa/bin/sa test tests/unit_framework/std_process_macro_surface.sa --filter "spawn modes" --trace-panic --no-incremental`: pass (`1 passed`).
  - Installed-state smoke with `SA_STD_DIR=/home/vscode/.sa/std /home/vscode/.sa/bin/sa test tests/unit_framework/std_process_macro_surface.sa --trace-panic --no-incremental`: pass (`14 passed`).

## Completed: 2026-07-06 PidFd owned fd alias batch

- Added Linux `std::os::linux::process::PidFd` owned-fd trait-style macro aliases over the existing pidfd raw-fd and `sa_std/os/fd` owned-fd facades:
  - `PIDFD_INTO_OWNED_FD`
  - `PIDFD_FROM_OWNED_FD`
  - runtime continues to use the existing fd ABI, so this batch does not add exported symbols.
- Updated `tests/unit_framework/std_process_macro_surface.sa` pidfd coverage:
  - `PROCESS_INTO_PIDFD` coverage now transfers the pidfd through an owned fd and rebinds it before continuing through the existing raw-fd roundtrip, kill, and wait path.
- Validation status:
  - `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_process_macro_surface.sa --filter pidfd --trace-panic --no-incremental`: pass (`1 passed`).
  - `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_process_macro_surface.sa --trace-panic --no-incremental`: pass (`14 passed`).
  - `zig build unit-framework --summary all`: pass (`6/6 steps succeeded; 5/5 tests passed`).
- Install sync status:
  - `./tools/install.sh --no-shell`: pass.
  - Installed-state smoke with `SA_STD_DIR=/home/vscode/.sa/std /home/vscode/.sa/bin/sa test tests/unit_framework/std_process_macro_surface.sa --filter pidfd --trace-panic --no-incremental`: pass (`1 passed`).
  - Installed-state smoke with `SA_STD_DIR=/home/vscode/.sa/std /home/vscode/.sa/bin/sa test tests/unit_framework/std_process_macro_surface.sa --trace-panic --no-incremental`: pass (`14 passed`).

## Completed: 2026-07-06 Unix socket owned fd alias batch

- Added Unix `std::os::unix::net::{UnixStream,UnixListener}` owned-fd trait-style macro aliases over the existing raw-fd and `sa_std/os/fd` owned-fd facades:
  - `NET_UNIX_STREAM_INTO_OWNED_FD`
  - `NET_UNIX_STREAM_FROM_OWNED_FD`
  - `NET_UNIX_LISTENER_INTO_OWNED_FD`
  - `NET_UNIX_LISTENER_FROM_OWNED_FD`
  - runtime continues to use the existing fd ABI plus Unix stream/listener raw-fd restore paths, so this batch does not add exported symbols.
- Updated `tests/unit_framework/std_net_unix_macro_surface.sa` coverage:
  - listener clone coverage transfers the cloned listener through an owned fd and rebinds it before the existing raw-fd roundtrip/close path.
  - stream clone coverage transfers the cloned stream through an owned fd and rebinds it before the existing raw-fd roundtrip/write/read path.
- Validation status:
  - `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_net_unix_macro_surface.sa --filter domain --trace-panic --no-incremental`: pass (`1 passed`).
  - `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_net_unix_macro_surface.sa --filter pair --trace-panic --no-incremental`: pass (`1 passed`).
  - `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_net_unix_macro_surface.sa --trace-panic --no-incremental`: pass (`4 passed`).
  - `zig build unit-framework --summary all`: pass (`6/6 steps succeeded; 5/5 tests passed`).
- Install sync status:
  - `./tools/install.sh --no-shell`: pass.
  - Installed-state smoke with `SA_STD_DIR=/home/vscode/.sa/std /home/vscode/.sa/bin/sa test tests/unit_framework/std_net_unix_macro_surface.sa --filter domain --trace-panic --no-incremental`: pass (`1 passed`).
  - Installed-state smoke with `SA_STD_DIR=/home/vscode/.sa/std /home/vscode/.sa/bin/sa test tests/unit_framework/std_net_unix_macro_surface.sa --filter pair --trace-panic --no-incremental`: pass (`1 passed`).
  - Installed-state smoke with `SA_STD_DIR=/home/vscode/.sa/std /home/vscode/.sa/bin/sa test tests/unit_framework/std_net_unix_macro_surface.sa --trace-panic --no-incremental`: pass (`4 passed`).

## Completed: 2026-07-06 Child stdout/stderr raw fd alias batch

- Added Unix process child pipe raw-fd trait-style macro aliases over the existing `sa_std/os/fd` owned-fd facade:
  - `PROCESS_CHILD_STDOUT_AS_RAW_FD`
  - `PROCESS_CHILD_STDOUT_INTO_RAW_FD`
  - `PROCESS_CHILD_STDOUT_FROM_RAW_FD`
  - `PROCESS_CHILD_STDERR_AS_RAW_FD`
  - `PROCESS_CHILD_STDERR_INTO_RAW_FD`
  - `PROCESS_CHILD_STDERR_FROM_RAW_FD`
  - runtime continues to use the existing fd ABI, so this batch does not add exported symbols.
- Updated `tests/unit_framework/std_process_macro_surface.sa` stream-spawn coverage:
  - `PROCESS_SPAWN_STREAM_COMMAND_EXT` stdout/stderr handles now validate `as_raw_fd`.
  - both handles transfer ownership through `into_raw_fd`, rebind through `from_raw_fd`, then continue through the existing wait/close path.
- Validation status:
  - `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_process_macro_surface.sa --filter "spawn modes" --trace-panic --no-incremental`: pass (`1 passed`).
  - `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_process_macro_surface.sa --trace-panic --no-incremental`: pass (`14 passed`).
  - `zig build unit-framework --summary all`: pass (`6/6 steps succeeded; 5/5 tests passed`).
- Install sync status:
  - `./tools/install.sh --no-shell`: pass.
  - Installed-state smoke with `SA_STD_DIR=/home/vscode/.sa/std /home/vscode/.sa/bin/sa test tests/unit_framework/std_process_macro_surface.sa --filter "spawn modes" --trace-panic --no-incremental`: pass (`1 passed`).
  - Installed-state smoke with `SA_STD_DIR=/home/vscode/.sa/std /home/vscode/.sa/bin/sa test tests/unit_framework/std_process_macro_surface.sa --trace-panic --no-incremental`: pass (`14 passed`).

## Completed: 2026-07-06 Unix socket raw fd trait batch

- Added Unix `std::os::unix::net::{UnixStream,UnixListener}` raw-fd trait-style macro surface:
  - `NET_UNIX_STREAM_AS_RAW_FD`
  - `NET_UNIX_STREAM_INTO_RAW_FD`
  - `NET_UNIX_STREAM_FROM_RAW_FD`
  - `NET_UNIX_LISTENER_AS_RAW_FD`
  - `NET_UNIX_LISTENER_INTO_RAW_FD`
  - `NET_UNIX_LISTENER_FROM_RAW_FD`
- Added runtime/header exports for the ownership-restoring paths:
  - `sa_std_net_unix_stream_from_raw_fd`
  - `sa_std_net_unix_listener_from_raw_fd`
  - `as_raw_fd` and `into_raw_fd` continue to reuse the existing `sa_std/os/fd` ABI.
- Runtime behavior:
  - validates raw fds as AF_UNIX stream sockets before registering them.
  - listener `from_raw_fd` additionally requires `SO_ACCEPTCONN` and restores `std.net.Server.listen_address` from `getsockname`.
  - stream `from_raw_fd` rejects accepting/listener sockets and registers the fd as a stream handle.
- Updated `tests/unit_framework/std_net_unix_macro_surface.sa` coverage:
  - listener clone coverage transfers the cloned listener through raw fd ownership and rebinds it before close.
  - stream clone coverage transfers the cloned stream through raw fd ownership, rebinds it, and then writes through the rebound handle.
- Validation status:
  - `zig build sa-std-static --summary all`: pass.
  - `nm -g zig-out/lib/libsa_std.a | rg 'sa_std_net_unix_(stream|listener)_from_raw_fd'`: pass, both symbols exported.
  - `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_net_unix_macro_surface.sa --filter domain --trace-panic --no-incremental`: pass (`1 passed`).
  - `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_net_unix_macro_surface.sa --filter pair --trace-panic --no-incremental`: pass (`1 passed`).
  - `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_net_unix_macro_surface.sa --trace-panic --no-incremental`: pass (`4 passed`).
  - `zig build unit-framework --summary all`: pass (`6/6 steps succeeded; 5/5 tests passed`).
- Install sync status:
  - `./tools/install.sh --no-shell`: pass.
  - Installed-state smoke with `SA_STD_DIR=/home/vscode/.sa/std /home/vscode/.sa/bin/sa test tests/unit_framework/std_net_unix_macro_surface.sa --filter domain --trace-panic --no-incremental`: pass (`1 passed`).
  - Installed-state smoke with `SA_STD_DIR=/home/vscode/.sa/std /home/vscode/.sa/bin/sa test tests/unit_framework/std_net_unix_macro_surface.sa --filter pair --trace-panic --no-incremental`: pass (`1 passed`).
  - Installed-state smoke with `SA_STD_DIR=/home/vscode/.sa/std /home/vscode/.sa/bin/sa test tests/unit_framework/std_net_unix_macro_surface.sa --trace-panic --no-incremental`: pass (`4 passed`).

## Completed: 2026-07-06 PidFd raw fd alias batch

- Added Rust raw-fd trait-style pidfd macro aliases over the existing `sa_std/os/fd` owned-fd facade:
  - `PIDFD_AS_RAW_FD`
  - `PIDFD_INTO_RAW_FD`
  - `PIDFD_FROM_RAW_FD`
  - `PIDFD_CLOSE_RAW_FD`
  - runtime continues to use the existing fd ABI, so this batch does not add new exported symbols.
- Updated `tests/unit_framework/std_process_macro_surface.sa` pidfd coverage:
  - borrowed pidfd handles now validate `as_raw_fd`-style access and close the duplicate pidfd handle explicitly.
  - `into_pidfd` coverage now validates `as_raw_fd`, transfers the pidfd through `into_raw_fd`, rebinds it through `from_raw_fd`, then uses the rebound handle for kill/wait and explicit close.
- Validation status:
  - `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_process_macro_surface.sa --filter pidfd --trace-panic --no-incremental`: pass (`1 passed`).
  - `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_process_macro_surface.sa --trace-panic --no-incremental`: pass (`14 passed`).
  - `zig build unit-framework --summary all`: pass (`6/6 steps succeeded; 5/5 tests passed`).
- Install sync status:
  - `./tools/install.sh --no-shell`: pass.
  - Installed-state smoke with `SA_STD_DIR=/home/vscode/.sa/std /home/vscode/.sa/bin/sa test tests/unit_framework/std_process_macro_surface.sa --filter pidfd --trace-panic --no-incremental`: pass (`1 passed`).
  - Installed-state smoke with `SA_STD_DIR=/home/vscode/.sa/std /home/vscode/.sa/bin/sa test tests/unit_framework/std_process_macro_surface.sa --trace-panic --no-incremental`: pass (`14 passed`).

## Completed: 2026-07-06 Unix fs symlink/chown alias batch

- Added Rust-named Unix filesystem macro aliases over existing runtime helpers:
  - `FS_UNIX_SYMLINK`
  - `FS_UNIX_CHOWN`
  - `FS_UNIX_LCHOWN`
  - `FS_UNIX_FCHOWN`
  - `FS_UNIX_FCHOWN_RAW`
  - runtime continues to use the existing `sa_fs_symlink`, `sa_fs_chown`, `sa_fs_lchown`, and `sa_fs_fchown` exports, so this batch does not add new ABI symbols.
- Updated `tests/unit_framework/std_fs_unix_ext_macro_surface.sa` coverage:
  - chown test now creates the symlink and applies ownership helpers through the `FS_UNIX_*` names.
  - nofollow/symlink coverage now uses `FS_UNIX_SYMLINK`.
- Validation status:
  - `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_fs_unix_ext_macro_surface.sa --filter chown --trace-panic --no-incremental`: pass (`1 passed`).
  - `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_fs_unix_ext_macro_surface.sa --trace-panic --no-incremental`: pass (`6 passed`).
  - `zig build unit-framework --summary all`: pass (`6/6 steps succeeded; 5/5 tests passed`).
- Install sync status:
  - `./tools/install.sh --no-shell`: pass.
  - Installed-state smoke with `SA_STD_DIR=/home/vscode/.sa/std /home/vscode/.sa/bin/sa test tests/unit_framework/std_fs_unix_ext_macro_surface.sa --filter chown --trace-panic --no-incremental`: pass (`1 passed`).
  - Installed-state smoke with `SA_STD_DIR=/home/vscode/.sa/std /home/vscode/.sa/bin/sa test tests/unit_framework/std_fs_unix_ext_macro_surface.sa --trace-panic --no-incremental`: pass (`6 passed`).

## Completed: 2026-07-06 Unix SocketAddr as_abstract_name alias batch

- Added Linux `std::os::linux::net::SocketAddrExt::as_abstract_name`-style named macro aliases over the existing Unix abstract-name address accessors:
  - `NET_UNIX_ADDR_AS_ABSTRACT_NAME_PTR`
  - `NET_UNIX_ADDR_AS_ABSTRACT_NAME_LEN`
  - runtime continues to use the existing abstract pointer/length accessors, so this batch does not add new ABI symbols.
- Updated `tests/unit_framework/std_net_unix_macro_surface.sa` abstract address coverage:
  - abstract address construction now validates the original address and listener local address through the Rust-named `as_abstract_name` macros.
- Validation status:
  - `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_net_unix_macro_surface.sa --filter abstract --trace-panic --no-incremental`: pass (`1 passed`).
  - `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_net_unix_macro_surface.sa --trace-panic --no-incremental`: pass (`4 passed`).
  - `zig build unit-framework --summary all`: pass (`6/6 steps succeeded; 5/5 tests passed`).
- Install sync status:
  - `./tools/install.sh --no-shell`: pass.
  - Installed-state smoke with `SA_STD_DIR=/home/vscode/.sa/std /home/vscode/.sa/bin/sa test tests/unit_framework/std_net_unix_macro_surface.sa --filter abstract --trace-panic --no-incremental`: pass (`1 passed`).
  - Installed-state smoke with `SA_STD_DIR=/home/vscode/.sa/std /home/vscode/.sa/bin/sa test tests/unit_framework/std_net_unix_macro_surface.sa --trace-panic --no-incremental`: pass (`4 passed`).

## Completed: 2026-07-06 Unix SocketAddr pathname batch

- Added Unix `std::os::unix::net::SocketAddr::{from_pathname,as_pathname}`-style surface over the existing Unix address handle model:
  - runtime/header export `sa_std_net_unix_addr_from_pathname`
  - SA extern/macro wrapper `NET_UNIX_ADDR_FROM_PATHNAME`
  - Rust-named pathname access aliases `NET_UNIX_ADDR_AS_PATHNAME_PTR` and `NET_UNIX_ADDR_AS_PATHNAME_LEN` over the existing path pointer/length accessors.
- Runtime behavior:
  - validates pathname socket addresses with Zig's Unix socket address constructor before storing the pathname bytes.
  - registers a `SA_NET_UNIX_ADDR_PATHNAME` Unix address handle using the existing resource lifetime and `NET_UNIX_ADDR_FREE` cleanup path.
- Extended `tests/unit_framework/std_net_unix_macro_surface.sa` coverage:
  - added a pathname SocketAddr constructor test that validates kind, pathname length, pointer, first/last bytes, and cleanup.
- Validation status:
  - `zig build sa-std-static --summary all`: pass.
  - `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_net_unix_macro_surface.sa --filter pathname --trace-panic --no-incremental`: pass (`1 passed`).
  - `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_net_unix_macro_surface.sa --trace-panic --no-incremental`: pass (`4 passed`).
  - `zig build unit-framework --summary all`: pass (`6/6 steps succeeded; 5/5 tests passed`).
- Install sync status:
  - `./tools/install.sh --no-shell`: pass.
  - Installed-state smoke with `SA_STD_DIR=/home/vscode/.sa/std /home/vscode/.sa/bin/sa test tests/unit_framework/std_net_unix_macro_surface.sa --filter pathname --trace-panic --no-incremental`: pass (`1 passed`).
  - Installed-state smoke with `SA_STD_DIR=/home/vscode/.sa/std /home/vscode/.sa/bin/sa test tests/unit_framework/std_net_unix_macro_surface.sa --trace-panic --no-incremental`: pass (`4 passed`).
  - `nm` confirms `sa_std_net_unix_addr_from_pathname` is exported.

## Completed: 2026-07-06 UnixListener incoming named surface batch

- Added Unix `std::os::unix::net::UnixListener::incoming`-style named macro surface over the existing listener-backed incoming iterator layout:
  - `NET_UNIX_INCOMING_NEW`
  - `NET_UNIX_INCOMING_LISTENER`
  - `NET_UNIX_INCOMING_NEXT`
  - `NET_UNIX_LISTENER_INCOMING`
  - runtime continues to use the existing TCP incoming/listener accept path for Unix listener handles, so this batch does not add new ABI symbols.
- Extended `tests/unit_framework/std_net_unix_macro_surface.sa` coverage:
  - abstract Unix-domain socket roundtrip now wraps the listener through the Unix incoming macro surface.
  - verifies the incoming wrapper retains the listener handle and accepts the queued connection through `NET_UNIX_INCOMING_NEXT` before the existing stream I/O assertions.
- Validation status:
  - `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_net_unix_macro_surface.sa --filter abstract --trace-panic --no-incremental`: pass (`1 passed`).
  - `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_net_unix_macro_surface.sa --trace-panic --no-incremental`: pass (`3 passed`).
  - `zig build unit-framework --summary all`: pass (`6/6 steps succeeded; 5/5 tests passed`).
- Install sync status:
  - `./tools/install.sh --no-shell`: pass.
  - Installed-state smoke with `SA_STD_DIR=/home/vscode/.sa/std /home/vscode/.sa/bin/sa test tests/unit_framework/std_net_unix_macro_surface.sa --filter abstract --trace-panic --no-incremental`: pass (`1 passed`).
  - Installed-state smoke with `SA_STD_DIR=/home/vscode/.sa/std /home/vscode/.sa/bin/sa test tests/unit_framework/std_net_unix_macro_surface.sa --trace-panic --no-incremental`: pass (`3 passed`).

## Completed: 2026-07-06 UnixListener accept_addr batch

- Added Unix `std::os::unix::net::UnixListener::accept`-style address-returning surface:
  - runtime/header export `sa_std_net_unix_accept_addr`
  - SA extern/macro wrapper `NET_UNIX_ACCEPT_ADDR` returning both accepted stream and peer Unix socket address handle.
- Runtime behavior:
  - validates the listener handle is backed by an AF_UNIX listener socket.
  - calls `accept` with a `sockaddr_un` output buffer, registers the accepted fd as an existing stream resource, and registers the peer address through the existing Unix address handle model.
  - keeps the existing `NET_UNIX_ACCEPT` stream-only path intact.
- Extended `tests/unit_framework/std_net_unix_macro_surface.sa` coverage:
  - pathname Unix-domain roundtrip now accepts through `NET_UNIX_ACCEPT_ADDR`.
  - verifies the returned peer address handle is nonzero, has kind `SA_NET_UNIX_ADDR_UNNAMED`, and frees cleanly before the existing stream I/O continues.
- Validation status:
  - `zig build sa-std-static --summary all`: pass.
  - `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_net_unix_macro_surface.sa --filter "domain" --trace-panic --no-incremental`: pass (`1 passed`).
  - `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_net_unix_macro_surface.sa --trace-panic --no-incremental`: pass (`3 passed`).
  - `zig build unit-framework --summary all`: pass (`6/6 steps succeeded; 5/5 tests passed`).
- Install sync status:
  - `./tools/install.sh --no-shell`: pass.
  - Installed-state smoke with `SA_STD_DIR=/home/vscode/.sa/std /home/vscode/.sa/bin/sa test tests/unit_framework/std_net_unix_macro_surface.sa --filter "domain" --trace-panic --no-incremental`: pass (`1 passed`).
  - Installed-state smoke with `SA_STD_DIR=/home/vscode/.sa/std /home/vscode/.sa/bin/sa test tests/unit_framework/std_net_unix_macro_surface.sa --trace-panic --no-incremental`: pass (`3 passed`).
  - `nm` confirms `sa_std_net_unix_accept_addr` is exported.

## Completed: 2026-07-06 Unix socket try_clone batch

- Added Unix `std::os::unix::net::{UnixStream,UnixListener}::try_clone`-style facades over Linux/Unix fd duplication:
  - runtime/header exports `sa_std_net_unix_stream_try_clone` and `sa_std_net_unix_listener_try_clone`
  - SA extern/macro wrappers `NET_UNIX_STREAM_TRY_CLONE` and `NET_UNIX_LISTENER_TRY_CLONE`.
- Runtime behavior:
  - validates the source handle is backed by an AF_UNIX stream/listener socket.
  - duplicates the underlying fd with `dup` and registers the clone as the same SA resource kind (`tcp_stream` or `tcp_listener`), preserving existing close/read/write/accept paths.
  - cloned handles have independent close lifetimes while sharing kernel socket state, matching Rust `try_clone` semantics for this SA-facing subset.
- Extended `tests/unit_framework/std_net_unix_macro_surface.sa` coverage:
  - UnixStream pair test writes through a cloned stream handle, reads the bytes from the peer, closes the clone, then continues using the original stream.
  - UnixListener roundtrip test clones a listener and closes the clone while the original listener remains usable for the existing connect/accept flow.
- Validation status:
  - `zig build sa-std-static --summary all`: pass.
  - `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_net_unix_macro_surface.sa --filter pair --trace-panic --no-incremental`: pass (`1 passed`).
  - `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_net_unix_macro_surface.sa --trace-panic --no-incremental`: pass (`3 passed`).
  - `zig build unit-framework --summary all`: pass (`6/6 steps succeeded; 5/5 tests passed`).
- Install sync status:
  - `./tools/install.sh --no-shell`: pass.
  - Installed-state smoke with `SA_STD_DIR=/home/vscode/.sa/std /home/vscode/.sa/bin/sa test tests/unit_framework/std_net_unix_macro_surface.sa --filter pair --trace-panic --no-incremental`: pass (`1 passed`).
  - Installed-state smoke with `SA_STD_DIR=/home/vscode/.sa/std /home/vscode/.sa/bin/sa test tests/unit_framework/std_net_unix_macro_surface.sa --trace-panic --no-incremental`: pass (`3 passed`).
  - `nm` confirms `sa_std_net_unix_listener_try_clone` and `sa_std_net_unix_stream_try_clone` are exported.

## Completed: 2026-07-06 Unix socket option named surface batch

- Added Unix `std::os::unix::net::{UnixStream,UnixListener}`-style named macro surfaces over existing fd-based stream/listener runtime:
  - `NET_UNIX_STREAM_SET_READ_TIMEOUT`, `NET_UNIX_STREAM_SET_WRITE_TIMEOUT`, `NET_UNIX_STREAM_READ_TIMEOUT`, and `NET_UNIX_STREAM_WRITE_TIMEOUT`
  - `NET_UNIX_STREAM_SET_NONBLOCKING` and `NET_UNIX_STREAM_TAKE_ERROR`
  - `NET_UNIX_LISTENER_SET_NONBLOCKING` and `NET_UNIX_LISTENER_TAKE_ERROR`
  - runtime continues to use the existing TCP stream/listener option helpers for Unix stream/listener handles, so this batch does not add new ABI symbols.
- Extended `tests/unit_framework/std_net_unix_macro_surface.sa` coverage:
  - UnixStream pair test sets/reads read and write timeouts, toggles blocking mode, and checks `take_error` returns no pending socket error.
  - UnixListener roundtrip test toggles blocking mode and checks listener `take_error` returns no pending socket error.
- Validation status:
  - `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_net_unix_macro_surface.sa --filter pair --trace-panic --no-incremental`: pass (`1 passed`).
  - `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_net_unix_macro_surface.sa --trace-panic --no-incremental`: pass (`3 passed`).
  - `zig build unit-framework --summary all`: pass (`6/6 steps succeeded; 5/5 tests passed`).
- Install sync status:
  - `./tools/install.sh --no-shell`: pass.
  - Installed-state smoke with `SA_STD_DIR=/home/vscode/.sa/std /home/vscode/.sa/bin/sa test tests/unit_framework/std_net_unix_macro_surface.sa --filter pair --trace-panic --no-incremental`: pass (`1 passed`).
  - Installed-state smoke with `SA_STD_DIR=/home/vscode/.sa/std /home/vscode/.sa/bin/sa test tests/unit_framework/std_net_unix_macro_surface.sa --trace-panic --no-incremental`: pass (`3 passed`).

## Completed: 2026-07-06 UnixStream shutdown named surface batch

- Added Unix `std::os::unix::net::UnixStream::shutdown`-style named macro surface over existing stream shutdown runtime:
  - SA macro wrapper `NET_UNIX_STREAM_SHUTDOWN`
  - runtime continues to use the existing `sa_net_tcp_stream_shutdown` path for Unix stream handles, so this batch does not add a new ABI symbol.
- Extended `tests/unit_framework/std_net_unix_macro_surface.sa` pair coverage:
  - shuts down the writing half of one UnixStream with `SA_NET_SHUTDOWN_WRITE`.
  - verifies the peer stream reads successfully with length `0`, matching EOF behavior.
- Validation status:
  - `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_net_unix_macro_surface.sa --filter pair --trace-panic --no-incremental`: pass (`1 passed`).
  - `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_net_unix_macro_surface.sa --trace-panic --no-incremental`: pass (`3 passed`).
  - `zig build unit-framework --summary all`: pass (`6/6 steps succeeded; 5/5 tests passed`).
- Install sync status:
  - `./tools/install.sh --no-shell`: pass.
  - Installed-state smoke with `SA_STD_DIR=/home/vscode/.sa/std /home/vscode/.sa/bin/sa test tests/unit_framework/std_net_unix_macro_surface.sa --filter pair --trace-panic --no-incremental`: pass (`1 passed`).
  - Installed-state smoke with `SA_STD_DIR=/home/vscode/.sa/std /home/vscode/.sa/bin/sa test tests/unit_framework/std_net_unix_macro_surface.sa --trace-panic --no-incremental`: pass (`3 passed`).

## Completed: 2026-07-06 UnixStream peek named surface batch

- Added Unix `std::os::unix::net::UnixStream::peek`-style named macro surface over existing stream peek runtime:
  - SA macro wrapper `NET_UNIX_STREAM_PEEK`
  - runtime continues to use the existing `sa_std_net_tcp_stream_peek` path for Unix stream handles, so this batch does not add a new ABI symbol.
- Extended `tests/unit_framework/std_net_unix_macro_surface.sa` pair coverage:
  - writes `PAIR` across a UnixStream pair.
  - peeks from the receiving stream and validates `PAIR` is visible.
  - then reads from the same stream and validates `PAIR` is still present, proving peek does not consume data.
- Validation status:
  - `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_net_unix_macro_surface.sa --filter pair --trace-panic --no-incremental`: pass (`1 passed`).
  - `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_net_unix_macro_surface.sa --trace-panic --no-incremental`: pass (`3 passed`).
  - `zig build unit-framework --summary all`: pass (`6/6 steps succeeded; 5/5 tests passed`).
- Install sync status:
  - `./tools/install.sh --no-shell`: pass.
  - Installed-state smoke with `SA_STD_DIR=/home/vscode/.sa/std /home/vscode/.sa/bin/sa test tests/unit_framework/std_net_unix_macro_surface.sa --filter pair --trace-panic --no-incremental`: pass (`1 passed`).
  - Installed-state smoke with `SA_STD_DIR=/home/vscode/.sa/std /home/vscode/.sa/bin/sa test tests/unit_framework/std_net_unix_macro_surface.sa --trace-panic --no-incremental`: pass (`3 passed`).

## Completed: 2026-07-06 Linux UnixStream peer_cred batch

- Added Linux `std::os::unix::net::UnixStream::peer_cred`-style surface over existing Unix stream handles:
  - runtime/header export `sa_std_net_unix_stream_peer_cred`
  - SA extern/macro wrapper `NET_UNIX_STREAM_PEER_CRED`.
- Runtime behavior:
  - accepts only handles backed by AF_UNIX stream sockets.
  - uses Linux `getsockopt(SOL_SOCKET, SO_PEERCRED)` and returns peer `pid`, `uid`, and `gid` as scalar outputs.
  - intentionally avoids adding a separate Rust `UCred` object model for this SA-facing subset.
- Extended `tests/unit_framework/std_net_unix_macro_surface.sa` pair coverage:
  - verifies peer credentials on a UnixStream pair match the current process `pid`, `uid`, and `gid`.
- Validation status:
  - `zig build sa-std-static --summary all`: pass.
  - `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_net_unix_macro_surface.sa --filter pair --trace-panic --no-incremental`: pass (`1 passed`).
  - `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_net_unix_macro_surface.sa --trace-panic --no-incremental`: pass (`3 passed`).
  - `zig build unit-framework --summary all`: pass (`6/6 steps succeeded; 5/5 tests passed`).
- Install sync status:
  - `./tools/install.sh --no-shell`: pass.
  - Installed-state smoke with `SA_STD_DIR=/home/vscode/.sa/std /home/vscode/.sa/bin/sa test tests/unit_framework/std_net_unix_macro_surface.sa --filter pair --trace-panic --no-incremental`: pass (`1 passed`).
  - Installed-state smoke with `SA_STD_DIR=/home/vscode/.sa/std /home/vscode/.sa/bin/sa test tests/unit_framework/std_net_unix_macro_surface.sa --trace-panic --no-incremental`: pass (`3 passed`).
  - `nm` confirms `sa_std_net_unix_stream_peer_cred` is exported.

## Completed: 2026-07-06 Unix fs mkfifo named surface batch

- Added Rust-named `std::os::unix::fs::mkfifo` macro surface over the existing Linux FIFO runtime helper:
  - SA macro wrapper `FS_UNIX_MKFIFO`
  - runtime continues to use the existing `sa_fs_mkfifo` export, so this batch does not add a new ABI symbol.
- Updated `tests/unit_framework/std_fs_unix_ext_macro_surface.sa`:
  - the Unix file-type extension test now creates its FIFO through `FS_UNIX_MKFIFO` before checking `FS_METADATA_IS_FIFO`.
- Validation status:
  - `zig build sa-std-static --summary all`: pass.
  - `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_fs_unix_ext_macro_surface.sa --filter "file type" --trace-panic --no-incremental`: pass (`1 passed`).
  - `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_fs_unix_ext_macro_surface.sa --trace-panic --no-incremental`: pass (`6 passed`).
  - `zig build unit-framework --summary all`: pass (`6/6 steps succeeded; 5/5 tests passed`).
- Install sync status:
  - `./tools/install.sh --no-shell`: pass.
  - Installed-state smoke with `SA_STD_DIR=/home/vscode/.sa/std /home/vscode/.sa/bin/sa test tests/unit_framework/std_fs_unix_ext_macro_surface.sa --filter "file type" --trace-panic --no-incremental`: pass (`1 passed`).
  - Installed-state smoke with `SA_STD_DIR=/home/vscode/.sa/std /home/vscode/.sa/bin/sa test tests/unit_framework/std_fs_unix_ext_macro_surface.sa --trace-panic --no-incremental`: pass (`6 passed`).

## Completed: 2026-07-06 Linux DirEntryExt2 file_name_ref batch

- Added Unix `std::os::unix::fs::DirEntryExt2::file_name_ref`-style named facade over the existing SA directory-entry name view:
  - runtime/header exports `sa_fs_dir_entry_file_name_ptr` and `sa_fs_dir_entry_file_name_len`
  - SA extern/macro wrappers `FS_DIR_ENTRY_FILE_NAME_REF_PTR` and `FS_DIR_ENTRY_FILE_NAME_REF_LEN`.
- Runtime behavior:
  - reuses the existing directory-entry resource name pointer/length storage, so no new resource lifetime model is introduced.
  - keeps ownership tied to the directory-entry handle; callers must still free entries through `FS_DIR_ENTRY_FREE`.
- Updated `tests/unit_framework/std_fs_dir_entry_ext_macro_surface.sa`:
  - directory entry name matching now uses the new file-name-ref macros while retaining inode and kind assertions.
- Validation status:
  - `zig build sa-std-static --summary all`: pass.
  - `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_fs_dir_entry_ext_macro_surface.sa --trace-panic --no-incremental`: pass (`1 passed`).
  - `zig build unit-framework --summary all`: pass (`6/6 steps succeeded; 5/5 tests passed`).
- Install sync status:
  - `./tools/install.sh --no-shell`: pass.
  - Installed-state smoke with `SA_STD_DIR=/home/vscode/.sa/std /home/vscode/.sa/bin/sa test tests/unit_framework/std_fs_dir_entry_ext_macro_surface.sa --trace-panic --no-incremental`: pass (`1 passed`).
  - `nm` confirms `sa_fs_dir_entry_file_name_ptr` and `sa_fs_dir_entry_file_name_len` are exported.

## Completed: 2026-07-06 Linux ChildExt kill_process_group batch

- Added Linux `std::os::unix::process::ChildExt::kill_process_group`-style convenience surface over the existing process-group signal path:
  - runtime/header export `sa_std_process_kill_process_group`
  - SA extern/macro wrapper `PROCESS_KILL_PROCESS_GROUP`.
- Runtime behavior:
  - delegates to the existing effective-PGID-aware `sa_std_process_send_process_group_signal` helper with `SIGKILL`.
  - preserves the process-group validation and error mapping already used by the explicit signal facade.
- Extended `tests/unit_framework/std_process_macro_surface.sa` with a kill-process-group macro-surface test:
  - spawns `/bin/sleep` into a new process group.
  - kills the group through `PROCESS_KILL_PROCESS_GROUP`.
  - verifies raw wait-status signal decoding reports `SIGKILL`.
- Validation status:
  - `zig build sa-std-static --summary all`: pass.
  - `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_process_macro_surface.sa --filter "kill process group" --trace-panic --no-incremental`: pass (`1 passed`).
  - `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_process_macro_surface.sa --trace-panic --no-incremental`: pass (`14 passed`).
  - `zig build unit-framework --summary all`: pass (`6/6 steps succeeded; 5/5 tests passed`).
- Install sync status:
  - `./tools/install.sh --no-shell`: pass.
  - Installed-state smoke with `SA_STD_DIR=/home/vscode/.sa/std /home/vscode/.sa/bin/sa test tests/unit_framework/std_process_macro_surface.sa --filter "kill process group" --trace-panic --no-incremental`: pass (`1 passed`).
  - Installed-state smoke with `SA_STD_DIR=/home/vscode/.sa/std /home/vscode/.sa/bin/sa test tests/unit_framework/std_process_macro_surface.sa --trace-panic --no-incremental`: pass (`14 passed`).
  - `nm` confirms `sa_std_process_kill_process_group` is exported.

## Completed: 2026-07-06 Linux UnixSocketExt passcred batch

- Added Linux `std::os::net::linux_ext::UnixSocketExt`-style `SO_PASSCRED` option surface for existing Unix stream handles:
  - runtime/header exports `sa_std_net_unix_stream_set_passcred` and `sa_std_net_unix_stream_passcred`
  - SA macro wrappers `NET_UNIX_STREAM_SET_PASSCRED` and `NET_UNIX_STREAM_PASSCRED`.
- Runtime behavior:
  - accepts only handles backed by AF_UNIX stream sockets; non-Unix stream handles return invalid-handle status for this Unix-specific extension.
  - maps set/get directly to Linux `SO_PASSCRED` with boolean `setsockopt` / `getsockopt` semantics.
  - this batch intentionally covers the existing `UnixStream` resource model; Rust's `UnixDatagram` side remains a larger follow-up because SA does not yet have a Unix datagram handle model.
- Extended `tests/unit_framework/std_net_unix_macro_surface.sa` pair coverage:
  - verifies `passcred` enable reads back `1`, then disable reads back `0`, before the existing unnamed-address and pair I/O checks.
- Validation status:
  - `zig build sa-std-static --summary all`: pass.
  - `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_net_unix_macro_surface.sa --filter pair --trace-panic --no-incremental`: pass (`1 passed`).
  - `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_net_unix_macro_surface.sa --trace-panic --no-incremental`: pass (`3 passed`).
  - `zig build unit-framework --summary all`: pass (`6/6 steps succeeded; 5/5 tests passed`).
- Install sync status:
  - `./tools/install.sh --no-shell`: pass.
  - Installed-state smoke with `SA_STD_DIR=/home/vscode/.sa/std /home/vscode/.sa/bin/sa test tests/unit_framework/std_net_unix_macro_surface.sa --filter pair --trace-panic --no-incremental`: pass (`1 passed`).
  - Installed-state smoke with `SA_STD_DIR=/home/vscode/.sa/std /home/vscode/.sa/bin/sa test tests/unit_framework/std_net_unix_macro_surface.sa --trace-panic --no-incremental`: pass (`3 passed`).
  - `nm` confirms the two passcred Unix stream extension exports.

## Completed: 2026-07-06 Linux TcpStreamExt quickack/deferaccept batch

- Added Linux `std::os::net::linux_ext::TcpStreamExt` socket option surface over existing TCP stream handles:
  - runtime/header exports `sa_std_net_tcp_stream_set_quickack` and `sa_std_net_tcp_stream_quickack`
  - runtime/header exports `sa_std_net_tcp_stream_set_deferaccept` and `sa_std_net_tcp_stream_deferaccept`
  - SA macro wrappers `NET_TCP_STREAM_SET_QUICKACK`, `NET_TCP_STREAM_QUICKACK`, `NET_TCP_STREAM_SET_DEFERACCEPT`, and `NET_TCP_STREAM_DEFERACCEPT`.
- Runtime behavior:
  - `quickack` maps to Linux `TCP_QUICKACK` as a boolean socket option.
  - `deferaccept` maps to Linux `TCP_DEFER_ACCEPT` using whole seconds, matching the kernel option ABI.
  - Unix-domain stream handles that reuse the TCP stream resource kind return a successful neutral result for these TCP-only options, preserving existing UDS compatibility behavior.
- Extended `tests/unit_framework/std_net_macro_surface.sa` option coverage:
  - loopback TCP setup now verifies set/get for `quickack(false)` and `deferaccept(1)` alongside nodelay, ttl, timeout, and take_error.
- Validation status:
  - `zig build sa-std-static --summary all`: pass.
  - `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_net_macro_surface.sa --filter "option getter" --trace-panic --no-incremental`: pass (`1 passed`).
  - `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_net_macro_surface.sa --trace-panic --no-incremental`: pass (`10 passed`).
  - `zig build unit-framework --summary all`: pass (`6/6 steps succeeded; 5/5 tests passed`).
- Install sync status:
  - `./tools/install.sh --no-shell`: pass.
  - Installed-state smoke with `SA_STD_DIR=/home/vscode/.sa/std /home/vscode/.sa/bin/sa test tests/unit_framework/std_net_macro_surface.sa --filter "option getter" --trace-panic --no-incremental`: pass (`1 passed`).
  - Installed-state smoke with `SA_STD_DIR=/home/vscode/.sa/std /home/vscode/.sa/bin/sa test tests/unit_framework/std_net_macro_surface.sa --trace-panic --no-incremental`: pass (`10 passed`).
  - `nm` confirms the four quickack/deferaccept TCP stream extension exports.

## Completed: 2026-07-06 Linux Unix socket abstract address batch

- Added Linux `std::os::linux::net::SocketAddrExt`-style abstract Unix socket address construction on top of the existing Unix address handle model:
  - runtime/header export `sa_std_net_unix_addr_from_abstract_name`
  - SA macro wrapper `NET_UNIX_ADDR_FROM_ABSTRACT_NAME`
  - arbitrary abstract-name bytes are retained in a dedicated `SA_NET_UNIX_ADDR_ABSTRACT` Unix address handle and exposed through the existing kind/ptr/len accessors.
- Added Unix-domain bind/connect by address handle:
  - runtime/header exports `sa_std_net_unix_listen_addr` and `sa_std_net_unix_connect_addr`
  - SA macro wrappers `NET_UNIX_LISTEN_ADDR` and `NET_UNIX_CONNECT_ADDR`
  - pathname, unnamed, and abstract Unix address handles convert through one sockaddr builder path with Linux abstract-name length validation.
- Extended `tests/unit_framework/std_net_unix_macro_surface.sa` with an abstract address roundtrip test:
  - verifies abstract address kind, byte length, and byte accessors
  - listens on an abstract UDS name, checks listener local address returns the same abstract name, connects by address handle, accepts, writes `ABS!`, reads it back, and closes/frees all handles.
- Validation status:
  - `zig build sa-std-static --summary all`: pass.
  - `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_net_unix_macro_surface.sa --filter abstract --trace-panic --no-incremental`: pass (`1 passed`).
  - `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_net_unix_macro_surface.sa --trace-panic --no-incremental`: pass (`3 passed`).
  - `zig build unit-framework --summary all`: pass (`6/6 steps succeeded; 5/5 tests passed`).
- Install sync status:
  - `./tools/install.sh --no-shell`: pass.
  - Installed-state smoke with `SA_STD_DIR=/home/vscode/.sa/std /home/vscode/.sa/bin/sa test tests/unit_framework/std_net_unix_macro_surface.sa --filter abstract --trace-panic --no-incremental`: pass (`1 passed`).
  - Installed-state smoke with `SA_STD_DIR=/home/vscode/.sa/std /home/vscode/.sa/bin/sa test tests/unit_framework/std_net_unix_macro_surface.sa --trace-panic --no-incremental`: pass (`3 passed`).
  - `nm` confirms `sa_std_net_unix_addr_from_abstract_name`, `sa_std_net_unix_listen_addr`, and `sa_std_net_unix_connect_addr` are exported.

## Completed: 2026-07-06 Linux CommandExt in-place exec batch

- Added Linux `std::os::unix::process::CommandExt::exec`-style in-place process replacement over the existing CommandExt config model:
  - runtime/header export `sa_std_process_exec_command_ext`
  - SA macro wrapper `PROCESS_EXEC_COMMAND_EXT`
  - supports cwd, arg0, process_group, setsid, uid, gid, groups, and chroot configuration before `execvpeZ`.
- Extended `tests/unit_framework/std_process_macro_surface.sa` with exec macro-surface tests:
  - success path replaces the test child process with `/bin/true` and is accepted as exit code 0
  - failure path uses a missing executable and verifies the call returns an error instead of replacing the process.
- Validation status:
  - `zig build sa-std-static --summary all`: pass.
  - `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_process_macro_surface.sa --filter exec --trace-panic --no-incremental`: pass (`2 passed`).
  - `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_process_macro_surface.sa --trace-panic --no-incremental`: pass (`13 passed`).
  - `zig build unit-framework --summary all`: pass (`6/6 steps succeeded; 5/5 tests passed`).
- Install sync status:
  - `./tools/install.sh --no-shell`: pass.
  - Installed-state smoke with `SA_STD_DIR=/home/vscode/.sa/std /home/vscode/.sa/bin/sa test tests/unit_framework/std_process_macro_surface.sa --filter exec --trace-panic --no-incremental`: pass (`2 passed`).
  - Installed-state smoke with `SA_STD_DIR=/home/vscode/.sa/std /home/vscode/.sa/bin/sa test tests/unit_framework/std_process_macro_surface.sa --trace-panic --no-incremental`: pass (`13 passed`).
  - `nm` confirms the exported symbol for the in-place exec CommandExt helper.

## Completed: 2026-07-06 Linux CommandExt chroot batch

- Added Linux `std::os::unix::process::CommandExt::chroot`-style child root-directory configuration over the existing process spawn model:
  - runtime/header exports `sa_std_process_run_command_ext_chroot`, `sa_std_process_spawn_command_ext_chroot`, and `sa_std_process_spawn_stream_command_ext_chroot`
  - SA macro wrappers `PROCESS_RUN_COMMAND_EXT_CHROOT`, `PROCESS_SPAWN_COMMAND_EXT_CHROOT`, and `PROCESS_SPAWN_STREAM_COMMAND_EXT_CHROOT`
  - child setup applies `chroot` after identity/group setup and before chdir/exec; existing no-chroot cwd behavior is preserved.
- Extended `tests/unit_framework/std_process_macro_surface.sa` with a chroot macro-surface test:
  - uses `/` as the chroot path so capability-enabled environments can still exec `/bin/true`
  - exercises run, spawn, and stream CommandExt chroot entry points
  - accepts child exit code `0` for capability-enabled environments and `127` for non-root Linux environments where `chroot` is denied during child setup.
- Validation status:
  - `zig build sa-std-static --summary all`: pass.
  - `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_process_macro_surface.sa --filter chroot --trace-panic --no-incremental`: pass (`1 passed`).
  - `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_process_macro_surface.sa --trace-panic --no-incremental`: pass (`11 passed`).
  - `zig build unit-framework --summary all`: pass (`6/6 steps succeeded; 5/5 tests passed`).
- Install sync status:
  - `./tools/install.sh --no-shell`: pass.
  - Installed-state smoke with `SA_STD_DIR=/home/vscode/.sa/std /home/vscode/.sa/bin/sa test tests/unit_framework/std_process_macro_surface.sa --filter chroot --trace-panic --no-incremental`: pass (`1 passed`).
  - Installed-state smoke with `SA_STD_DIR=/home/vscode/.sa/std /home/vscode/.sa/bin/sa test tests/unit_framework/std_process_macro_surface.sa --trace-panic --no-incremental`: pass (`11 passed`).
  - `nm` confirms exported symbols for the chroot CommandExt helpers.

## Completed: 2026-07-06 Linux CommandExt groups batch

- Added Linux `std::os::unix::process::CommandExt::groups`-style supplementary group configuration over the existing process spawn model:
  - runtime/header exports `sa_std_process_run_command_ext_groups`, `sa_std_process_spawn_command_ext_groups`, and `sa_std_process_spawn_stream_command_ext_groups`
  - SA macro wrappers `PROCESS_RUN_COMMAND_EXT_GROUPS`, `PROCESS_SPAWN_COMMAND_EXT_GROUPS`, and `PROCESS_SPAWN_STREAM_COMMAND_EXT_GROUPS`
  - child setup applies `setgroups` before `setgid` / `setuid` and before exec, across capture/inherit/stream modes.
- Extended `tests/unit_framework/std_process_macro_surface.sa` with a groups macro-surface test:
  - passes the current gid as a one-element supplementary group list
  - exercises run, spawn, and stream CommandExt groups entry points
  - accepts child exit code `0` for capability-enabled environments and `127` for non-root Linux environments where `setgroups` is denied during child setup.
- Validation status:
  - `zig build sa-std-static --summary all`: pass.
  - `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_process_macro_surface.sa --filter groups --trace-panic --no-incremental`: pass (`1 passed`).
  - `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_process_macro_surface.sa --trace-panic --no-incremental`: pass (`10 passed`).
  - `zig build unit-framework --summary all`: pass (`6/6 steps succeeded; 5/5 tests passed`).
- Install sync status:
  - `./tools/install.sh --no-shell`: pass.
  - Installed-state smoke with `SA_STD_DIR=/home/vscode/.sa/std /home/vscode/.sa/bin/sa test tests/unit_framework/std_process_macro_surface.sa --filter groups --trace-panic --no-incremental`: pass (`1 passed`).
  - Installed-state smoke with `SA_STD_DIR=/home/vscode/.sa/std /home/vscode/.sa/bin/sa test tests/unit_framework/std_process_macro_surface.sa --trace-panic --no-incremental`: pass (`10 passed`).
  - `nm` confirms exported symbols for the groups CommandExt helpers.

## Completed: 2026-07-06 Linux CommandExt uid/gid batch

- Added Linux `std::os::unix::process::CommandExt::{uid,gid}`-style child identity configuration over the existing process spawn model:
  - runtime/header exports `sa_std_process_run_command_ext_uid_gid`, `sa_std_process_spawn_command_ext_uid_gid`, and `sa_std_process_spawn_stream_command_ext_uid_gid`
  - SA macro wrappers `PROCESS_RUN_COMMAND_EXT_UID_GID`, `PROCESS_SPAWN_COMMAND_EXT_UID_GID`, and `PROCESS_SPAWN_STREAM_COMMAND_EXT_UID_GID`
  - child setup applies `setgid` before `setuid` immediately before exec, across capture/inherit/stream modes.
- Added current identity helpers for non-root verification:
  - runtime/header exports `sa_std_process_user_id` and `sa_std_process_group_id`
  - SA macro wrappers `PROCESS_USER_ID` and `PROCESS_GROUP_ID`.
- Extended `tests/unit_framework/std_process_macro_surface.sa` with a non-root-safe uid/gid test:
  - formats the current uid/gid through `sa_fmt_u64_into`
  - runs `/bin/sh -c 'test $(id -u) = "$1" && test $(id -g) = "$2"'` through `PROCESS_RUN_COMMAND_EXT_UID_GID`
  - verifies the child exits successfully after setting uid/gid to the current process identity.
- Validation status:
  - `zig build sa-std-static --summary all`: pass.
  - `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_process_macro_surface.sa --filter "uid gid" --trace-panic --no-incremental`: pass (`1 passed`).
  - `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_process_macro_surface.sa --trace-panic --no-incremental`: pass (`9 passed`).
  - `zig build unit-framework --summary all`: pass (`6/6 steps succeeded; 5/5 tests passed`).
- Install sync status:
  - `./tools/install.sh --no-shell`: pass.
  - Installed-state smoke with `SA_STD_DIR=/home/vscode/.sa/std /home/vscode/.sa/bin/sa test tests/unit_framework/std_process_macro_surface.sa --filter "uid gid" --trace-panic --no-incremental`: pass (`1 passed`).
  - Installed-state smoke with `SA_STD_DIR=/home/vscode/.sa/std /home/vscode/.sa/bin/sa test tests/unit_framework/std_process_macro_surface.sa --trace-panic --no-incremental`: pass (`9 passed`).
  - `nm` confirms exported symbols for the uid/gid CommandExt and current identity helpers.

## Next Batch

- Continue the broader Linux std gap closure by re-auditing remaining Linux-only std facades that can be represented without Rust's trait/lifetime machinery.

## Completed: 2026-07-06 Linux pidfd process batch

- Added a Linux pidfd-capable process spawn path over the existing `CommandExt` facade:
  - runtime/header exports `sa_std_process_run_command_ext_pidfd`, `sa_std_process_spawn_command_ext_pidfd`, and `sa_std_process_spawn_stream_command_ext_pidfd`
  - SA macro wrappers `PROCESS_RUN_COMMAND_EXT_PIDFD`, `PROCESS_SPAWN_COMMAND_EXT_PIDFD`, and `PROCESS_SPAWN_STREAM_COMMAND_EXT_PIDFD`
  - process handles optionally retain a pidfd created after fork, and existing `wait` / `wait_raw` / `try_wait` / `try_wait_raw` / `kill` / `send_signal` paths use pidfd syscalls when available.
- Added pidfd handle extraction and standalone pidfd operations:
  - `PROCESS_PIDFD` duplicates the retained pidfd into an owned fd handle.
  - `PROCESS_INTO_PIDFD` transfers the retained pidfd into an owned fd handle.
  - `PIDFD_KILL`, `PIDFD_SEND_SIGNAL`, `PIDFD_WAIT`, `PIDFD_WAIT_RAW`, `PIDFD_TRY_WAIT`, and `PIDFD_TRY_WAIT_RAW` expose the Linux pidfd wait/signal subset.
- Fixed process lifecycle behavior when a borrowed/transferred pidfd wait has already reaped the child: closing the original process handle now treats `ECHILD` as an already-consumed child state instead of tripping Zig std's `waitpid` unreachable branch.
- Extended `tests/unit_framework/std_process_macro_surface.sa` with a pidfd macro-surface test that covers pending `try_wait`, pidfd kill + raw wait-status signal decoding, `PROCESS_PIDFD`, and `PROCESS_INTO_PIDFD`.
- Validation status:
  - `zig build sa-std-static --summary all`: pass.
  - `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_process_macro_surface.sa --filter pidfd --trace-panic --no-incremental`: pass (`1 passed`).
  - `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_process_macro_surface.sa --trace-panic --no-incremental`: pass (`8 passed`).
  - `zig build unit-framework --summary all`: pass (`6/6 steps succeeded; 5/5 tests passed`).
- Install sync status:
  - `./tools/install.sh --no-shell`: pass.
  - Installed-state smoke with `SA_STD_DIR=/home/vscode/.sa/std /home/vscode/.sa/bin/sa test tests/unit_framework/std_process_macro_surface.sa --filter pidfd --trace-panic --no-incremental`: pass (`1 passed`).
  - Installed-state smoke with `SA_STD_DIR=/home/vscode/.sa/std /home/vscode/.sa/bin/sa test tests/unit_framework/std_process_macro_surface.sa --trace-panic --no-incremental`: pass (`8 passed`).

## Completed: 2026-07-05 Linux std parity batch

- Tracking docs are now explicit: `tasks.md`, `progress.md`, and `current_plan.md` are the memory/acceptance set for this batch.
- Implementing Linux-focused `sa_std` gaps directly in SCI source, then syncing install state to `/home/vscode/.sa/std`.
- Targeted surface for this batch:
  - `sa_std/os/fd`: raw/owned fd facade (`as_raw`, `dup`, `from_raw`, `into_raw`, `close_raw`, `is_terminal`).
  - `sa_std/fs`: Unix metadata ext fields and richer metadata JSON.
  - `sa_std/thread`: `current_id` and `yield_now`.
  - `sa_std/process`: Unix `ExitStatusExt` raw wait-status preservation and parsing.
  - `sa_std/fs`: Linux `MetadataExt` Rust-named `st_*` field surface.
  - `sa_std/fs`: Unix `chown` / `lchown` / `fchown` ownership helpers.
  - `sa_std/process`: Unix `parent_id` and `ChildExt::send_signal` surface.
- Validation status:
  - `zig build sa-std-static --summary all`: pass.
  - `zig build unit-framework --summary all`: pass.
  - Focused local `sa test` also passes for `std_net_unix_macro_surface.sa`, `std_net_dns_macro_surface.sa`, `std_os_fd_macro_surface.sa`, `std_fs_metadata_ext_macro_surface.sa`, `std_fs_unix_ext_macro_surface.sa`, `std_process_macro_surface.sa`.
  - Installed-state smoke passes for `std_fs_metadata_ext_macro_surface.sa`, `std_fs_unix_ext_macro_surface.sa`, `std_process_macro_surface.sa`, and `std_net_unix_macro_surface.sa`.

- Install sync status:
  - `./tools/install.sh --no-shell`: pass.
  - Installed payload root: `/home/vscode/.sa/std`.

## Completed: 2026-07-05 Linux std parity batch

- Added Linux fd facade surface under `sa_std/os/fd` and wired runtime/header exports for raw/owned fd operations.
- Extended `sa_std/fs` metadata with Linux/Unix fields (`mode`, `uid`, `gid`, `dev`, `ino`, `nlink`, `rdev`, `blksize`, `blocks`, `accessedAtMs`, `changedAtMs`) and matching JSON output.
- Added `sa_std/thread` surface for `current_id` and `yield_now`.
- Extended `sa_std/process` with raw wait status retention plus `ExitStatusExt`-style parsing (`raw`, `signal`, `core_dumped`, `stopped_signal`, `continued`).
- Added macro-surface coverage for fd/thread/fs-metadata-ext.
- Updated process macro-surface coverage for killed-child raw wait status semantics.
- Fixed UDS test/runtime compatibility by treating TCP-only keepalive/reuse setters as successful no-ops on `AF_UNIX` sockets.
- Fixed the DNS hostname macro-surface regression caused by a leaked temporary host register in the SA test itself.
- Final install sync completed via `tools/install.sh --no-shell`; no manual copy path used for the accepted result.

## Completed: 2026-07-05 Linux fs unix-ext batch

- Added Linux `sa_std/fs` `FileExt`-style offset I/O surface:
  - runtime exports `sa_std_fs_file_read_at`, `sa_std_fs_file_read_exact_at`, `sa_std_fs_file_write_at`, `sa_std_fs_file_write_all_at`
  - macro layer `FS_READ_AT`, `FS_READ_EXACT_AT`, `FS_WRITE_AT`, `FS_WRITE_ALL_AT`
  - verification includes offset I/O preserving the shared file cursor and exact/all wrappers through SA macro tests
- Added Linux `sa_std/fs` `OpenOptionsExt`-style open surface:
  - runtime export `sa_std_fs_open_options(path, flags, create_mode, custom_flags, &out_handle)`
  - macro layer `FS_OPEN_OPTIONS` and `FS_OPEN_FLAGS`
  - fixed the old `append` gap by routing `sa_fs_file_open` through a real POSIX open path that applies `O_APPEND`
  - added Linux custom-flag defs for the immediately useful open bits (`NOFOLLOW`, `CLOEXEC`, `DIRECT`, `DSYNC`, `NONBLOCK`, `DIRECTORY`, `SYNC`)
- Added Linux `sa_std/fs` `PermissionsExt`-style convenience surface:
  - `SaFsPermissions` layout in `fs.sal`
  - macros `FS_PERMISSIONS_FROM_MODE`, `FS_PERMISSIONS_MODE`, `FS_PERMISSIONS_SET_MODE`
- Added `tests/unit_framework/std_fs_unix_ext_macro_surface.sa` covering:
  - file-offset read/write parity
  - `OpenOptionsExt::mode` create-mode propagation
  - `OpenOptionsExt::custom_flags` via `NOFOLLOW` failure on symlink open
  - `PermissionsExt` mode round-trip plus path-level apply
  - append-open semantics on Linux
- Validation status:
  - `zig build sa-std-static --summary all`: pass
  - `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_fs_unix_ext_macro_surface.sa --trace-panic`: pass
  - `zig build unit-framework --summary all`: pass

## Completed: 2026-07-05 Linux fs file-type/dir-builder batch

- Added Linux `sa_std/fs` `FileTypeExt`-style classification surface:
  - runtime exports `sa_fs_metadata_is_block_device`, `sa_fs_metadata_is_char_device`, `sa_fs_metadata_is_fifo`, `sa_fs_metadata_is_socket`
  - macro layer `FS_METADATA_IS_BLOCK_DEVICE`, `FS_METADATA_IS_CHAR_DEVICE`, `FS_METADATA_IS_FIFO`, `FS_METADATA_IS_SOCKET`
  - coverage uses stable Linux fixtures instead of synthetic device-node creation:
    - char device: `/dev/null`
    - block device: `/dev/loop0`
    - fifo: temporary `mkfifo`
    - socket: temporary Unix-domain listener path
- Added Linux `sa_std/fs` `DirBuilderExt`-style mode surface:
  - runtime exports `sa_fs_create_dir_mode`, `sa_fs_make_dir_mode`
  - macro layer `FS_CREATE_DIR_MODE`, `FS_MAKE_DIR_MODE`, `FS_CREATE_DIR_ALL_MODE`
  - verification checks both single-level create and recursive create preserve the requested mode bits through metadata
- Added Linux `mkfifo` helper surface to support FIFO parity testing:
  - runtime export `sa_fs_mkfifo`
  - macro `FS_MKFIFO`
- Expanded `tests/unit_framework/std_fs_unix_ext_macro_surface.sa` to 5 passing tests covering:
  - file-offset I/O
  - `OpenOptionsExt`
  - `PermissionsExt`
  - `FileTypeExt`
  - `DirBuilderExt`
- Validation status:
  - `zig build sa-std-static --summary all`: pass
  - `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_fs_unix_ext_macro_surface.sa --trace-panic`: pass
  - `zig build unit-framework --summary all`: pass

## Next Linux Batch

- Continue the broader Linux std audit. Next high-value gaps are remaining Linux-only facades that can be represented without Rust's trait/lifetime machinery.

## Completed: 2026-07-05 Linux process-group signal batch

- Added the Rust Linux process-group signal subset on top of existing SA process handles:
  - runtime export `sa_std_process_send_process_group_signal`
  - SA extern/macro `PROCESS_SEND_PROCESS_GROUP_SIGNAL`
  - process handles now remember the effective process group configured by `CommandExt::process_group`; `process_group(0)` resolves to the child pid.
  - parent process also performs best-effort `setpgid(child, pgid)` after `fork` to avoid immediate group-signal races.
  - negative `process_group` config returns invalid argument at runtime entry.
- Extended `tests/unit_framework/std_process_macro_surface.sa`:
  - starts `/bin/sleep 5` in a new process group.
  - terminates it with `PROCESS_SEND_PROCESS_GROUP_SIGNAL(..., SIGKILL)`.
  - verifies raw wait status decodes to signal 9.
- Validation status:
  - `zig build sa-std-static --summary all`: pass
  - `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_process_macro_surface.sa --trace-panic`: pass twice (`7 passed`)
  - `zig build unit-framework --summary all`: pass (`6/6 steps succeeded; 5/5 tests passed`; queued-fail output is expected negative-test coverage)
- Install sync status:
  - `./tools/install.sh --no-shell`: pass
  - installed-state smoke with `sa test tests/unit_framework/std_process_macro_surface.sa --trace-panic`: pass (`7 passed`)
  - installed compiler reports `sa 0.0.3.3`

## Completed: 2026-07-05 Linux CommandExt spawn-config batch

- Added a Linux `std::os::unix::process::CommandExt`-style spawn configuration subset over the existing SA process modes:
  - `arg0` support for overriding `argv[0]` while preserving the executable path.
  - `process_group` support via child-side `setpgid(0, pgroup)`; `0` gives Rust's “use child pid as PGID” behavior.
  - `setsid(true)` support via Linux `setsid` before exec.
  - capture, inherit, and stream process modes all have runtime/SA macro entry points.
- Added SA macro surface:
  - `PROCESS_RUN_COMMAND_EXT`, `PROCESS_SPAWN_COMMAND_EXT`, `PROCESS_SPAWN_STREAM_COMMAND_EXT`.
  - convenience wrappers `PROCESS_RUN_ARG0`, `PROCESS_RUN_PROCESS_GROUP`, `PROCESS_RUN_SETSID`.
- Extended `tests/unit_framework/std_process_macro_surface.sa`:
  - verifies `arg0` by checking shell `$0` output.
  - verifies `process_group(0)` by checking `/proc/$$/stat` PGID equals child pid.
  - verifies `setsid(true)` by checking `/proc/$$/stat` SID equals child pid.
  - verifies inherit and stream command-ext entry points compile, link, run, and close their handles.
- Validation status:
  - `zig build sa-std-static --summary all`: pass
  - `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_process_macro_surface.sa --trace-panic`: pass (`6 passed`)
  - `zig build unit-framework --summary all`: pass (`6/6 steps succeeded; 5/5 tests passed`; queued-fail output is expected negative-test coverage)
- Install sync status:
  - `./tools/install.sh --no-shell`: pass
  - installed-state smoke with `sa test tests/unit_framework/std_process_macro_surface.sa --trace-panic`: pass (`6 passed`)
  - installed compiler reports `sa 0.0.3.3`

## Completed: 2026-07-05 Linux unix-domain socket completion batch

- Added `std::os::unix::net`-style Unix stream/listener completeness on top of the existing UDS stream/listener model:
  - `NET_UNIX_PAIR` / `sa_std_net_unix_pair` for connected `UnixStream::pair` semantics.
  - `NET_UNIX_LISTENER_LOCAL_ADDR` / `sa_std_net_unix_listener_local_addr`.
  - `NET_UNIX_STREAM_LOCAL_ADDR` / `sa_std_net_unix_stream_local_addr`.
  - `NET_UNIX_STREAM_PEER_ADDR` / `sa_std_net_unix_stream_peer_addr`.
- Added a dedicated Unix socket address resource instead of forcing UDS addresses into IP `NetAddr`:
  - unnamed, pathname, and Linux abstract address kinds.
  - path/abstract pointer and length accessors.
  - explicit `NET_UNIX_ADDR_FREE` lifecycle.
- Extended `tests/unit_framework/std_net_unix_macro_surface.sa`:
  - listener local address verifies pathname kind and bytes for `/tmp/sa_uds_test.sock`.
  - pair test verifies connected stream roundtrip and unnamed local/peer addresses.
- Validation status:
  - `zig build sa-std-static --summary all`: pass
  - `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_net_unix_macro_surface.sa --trace-panic`: pass (`2 passed`)
  - `zig build unit-framework --summary all`: pass (`6/6 steps succeeded; 5/5 tests passed`; queued-fail output is expected negative-test coverage)
- Install sync status:
  - `./tools/install.sh --no-shell`: pass
  - installed-state smoke with `sa test tests/unit_framework/std_net_unix_macro_surface.sa --trace-panic`: pass (`2 passed`)
  - installed compiler reports `sa 0.0.3.3`

## Completed: 2026-07-05 Linux fs dir-entry batch

- Added a real Linux directory-entry resource model instead of the old JSON-compatible facade:
  - runtime resource variants for directory-entry collections and individual directory entries
  - Linux `getdents64`-backed directory reads
  - captured entry name, inode, and basic file kind (`regular`, `dir`, `symlink`, `other`)
- Added runtime/header exports for directory-entry traversal and lifecycle:
  - `sa_fs_read_dir_entries` / `sa_std_fs_read_dir_entries`
  - `sa_fs_dir_entries_len`
  - `sa_std_fs_dir_entries_get`
  - `sa_fs_dir_entries_free`
  - `sa_fs_dir_entry_name_ptr`
  - `sa_fs_dir_entry_name_len`
  - `sa_fs_dir_entry_kind`
  - `sa_fs_dir_entry_ino`
  - `sa_fs_dir_entry_free`
- Added `sa_std/fs` extern declarations and macro wrappers for the same surface, including `FS_DIR_ENTRY_INO` for `std::os::unix::fs::DirEntryExt::ino` parity.
- Added `tests/unit_framework/std_fs_dir_entry_ext_macro_surface.sa` and registered it in `tests/unit_framework/runner.zig`.
- Validation status:
  - `zig build sa-std-static --summary all`: pass
  - `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_fs_dir_entry_ext_macro_surface.sa --trace-panic`: pass
  - `zig build unit-framework --summary all`: pass
- Install sync status:
  - included in the later Linux metadata/process install sync via `./tools/install.sh --no-shell`.

## Completed: 2026-07-05 Linux metadata/process extension batch

- Added Rust-named Linux `std::os::linux::fs::MetadataExt` macro/runtime surface on top of the existing metadata resource:
  - `st_dev`, `st_ino`, `st_mode`, `st_nlink`, `st_uid`, `st_gid`, `st_rdev`, `st_size`
  - `st_atime`, `st_atime_nsec`, `st_mtime`, `st_mtime_nsec`, `st_ctime`, `st_ctime_nsec`
  - `st_blksize`, `st_blocks`
- Added Unix process extension surface:
  - `PROCESS_PARENT_ID` / `sa_std_process_parent_id` for `std::os::unix::process::parent_id`
  - `PROCESS_SEND_SIGNAL` / `sa_std_process_send_signal` for `ChildExt::send_signal`
  - dynamic signal delivery uses the Linux syscall errno path so invalid signals return `SA_STD_ERR_INVALID_ARGUMENT` instead of hitting Zig `std.posix.kill`'s `unreachable` invalid-signal branch.
- Extended unit-framework coverage:
  - `std_fs_metadata_ext_macro_surface.sa` verifies `st_*` aliases and timestamp seconds/nanoseconds macro surface.
  - `std_process_macro_surface.sa` verifies `parent_id` and `send_signal(0)` before the existing kill/wait raw-status path.
- Validation status:
  - `zig build sa-std-static --summary all`: pass
  - `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_fs_metadata_ext_macro_surface.sa --trace-panic`: pass
  - `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_process_macro_surface.sa --trace-panic`: pass
  - `zig build unit-framework --summary all`: pass (`6/6 steps succeeded; 5/5 tests passed`; queued-fail output is expected negative-test coverage)
- Install sync status:
  - `./tools/install.sh --no-shell`: pass
  - installed-state smoke with `sa test tests/unit_framework/std_fs_metadata_ext_macro_surface.sa --trace-panic`: pass
  - installed-state smoke with `sa test tests/unit_framework/std_process_macro_surface.sa --trace-panic`: pass
  - installed compiler reports `sa 0.0.3.3`

## Completed: 2026-07-05 Linux fs ownership batch

- Added Linux `std::os::unix::fs` ownership helper surface:
  - `FS_CHOWN` / `sa_fs_chown`
  - `FS_LCHOWN` / `sa_fs_lchown`
  - `FS_FCHOWN` / `sa_fs_fchown`
  - `FS_CHOWN_RAW`, `FS_LCHOWN_RAW`, and `FS_FCHOWN_RAW` for Rust's `u32::MAX` unchanged-sentinel口径.
- Runtime implementation uses Linux `fchownat` for path and symlink no-follow variants, and `fchown` for fd handles.
- Extended `tests/unit_framework/std_fs_unix_ext_macro_surface.sa` with a non-root-safe test that changes ownership to the file's current uid/gid and verifies metadata afterward.
- Validation status:
  - `zig build sa-std-static --summary all`: pass
  - `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_fs_unix_ext_macro_surface.sa --trace-panic`: pass (`6 passed`)
  - `zig build unit-framework --summary all`: pass (`6/6 steps succeeded; 5/5 tests passed`; queued-fail output is expected negative-test coverage)
- Install sync status:
  - `./tools/install.sh --no-shell`: pass
  - installed-state smoke with `sa test tests/unit_framework/std_fs_unix_ext_macro_surface.sa --trace-panic`: pass (`6 passed`)
  - installed compiler reports `sa 0.0.3.3`

## Completed SCI Features

- 2026-07-04: Added JA3/JA4 TLS-fingerprint hashing primitives to `sa_std/net` (Go proxy-fingerprint parity pass).
  - Motivation: audited two Go LLM-proxy projects (`~/projects/CLIProxyAPI`, `~/projects/sub2api/backend`) for the network primitives behind their URL/TLS fingerprinting. Both center on uTLS (`refraction-networking/utls`) to forge a Chrome/Node.js ClientHello and dodge Cloudflare's TLS-fingerprint wall; sub2api hardcodes concrete targets (JA3 `44f88fca...`, JA4 `t13d1714h1_...`). The full uTLS handshake-forgery is environment-blocked for the same reason as h2-over-TLS (Zig 0.14 std TLS has no ALPN / no ClientHello customization; OpenSSL symbols are versioned-only and unresolvable). But the fingerprint *hashing* itself is pure computation and was entirely missing from SA, which has no crypto primitives of its own.
  - Runtime (`src/runtime/sa_std.zig`): `sa_std_net_ja3_hash(ja3_str) -> 32-char MD5 hex` (JA3 is `MD5` of the comma/dash-joined ClientHello field string) and `sa_std_net_ja4_hash12(data) -> first 12 chars of SHA256 hex` (the JA4 `_b`/`_c` segments are truncated SHA256 digests of the sorted cipher/extension lists). Both write into a caller-provided buffer (same style as `sa_std_net_addr_format`), no handle lifecycle.
  - Contracts in `sa_std/net.sai`; macros `NET_JA3_HASH`/`NET_JA4_HASH12` in `sa_std/net.sa`.
  - Verification: ground-truth vectors generated independently via openssl/python (`JA3 769,47-53-...,0 -> ada70206e40642a3e4461f35503241d5`; JA4 sorted-cipher list `-> f4ad024020fe`). Zig inline tests in `sa_std.zig` assert both against those vectors (exit 0). New SA test `tests/unit_framework/std_net_fingerprint_macro_surface.sa` re-verifies through the macro layer. Full `zig build unit-framework` -> exit 0 across two consecutive runs.
  - Not implemented (documented as environment-blocked): live uTLS handshake forgery, ALPN negotiation, SOCKS5/CONNECT proxy tunneling before a forged TLS handshake, and HTTP/2 frame-layer (Akamai h2) fingerprinting. These need a TLS stack with ClientHello control, which Zig 0.14 std lacks and OpenSSL cannot provide here.

- 2026-07-03: Filled the codex-parity network gaps in `sa_std/net` (Unix domain sockets + socket-option setters); assessed h2-over-TLS as environment-blocked.
  - Motivation: audited `~/projects/codex`'s network primitives against `sci` + the `sa_plugins` layer. The plugins (`sa_plugin_http_client` via `std.http.Client`, `http_server`, `node`/`deno` with real `libnode`/`libdeno` fetch/websocket/tls_connect) already cover HTTPS client, SSE streaming, WebSocket client, and TLS client with real backends. The only genuinely missing lower-level primitives were Unix domain sockets (used by codex `app-server-transport`), a few socket-option setters, and h2-over-TLS.
  - Unix domain sockets: added `sa_std_net_unix_listen(path)`, `sa_std_net_unix_connect(path)`, and `sa_std_net_unix_accept(listener)` in `src/runtime/sa_std.zig`. They reuse the existing `tcp_stream`/`tcp_listener` `Resource` variants, so read/write/shutdown/close and the `NET_TCP_STREAM_*` macros work unchanged on UDS handles. `unix_listen` unlinks any stale socket node before `bind` (avoids `AddrInUse`) and constructs `std.net.Server` manually. Contracts in `sa_std/net.sai`, macros `NET_UNIX_LISTEN`/`NET_UNIX_CONNECT`/`NET_UNIX_ACCEPT` in `sa_std/net.sa`.
  - Socket-option setters (exposed to SA for the first time): `sa_std_net_tcp_stream_set_keepalive`, `sa_std_net_tcp_stream_set_keepalive_params` (idle/intvl/cnt via `TCP_KEEPIDLE/KEEPINTVL/KEEPCNT`), `sa_std_net_tcp_listener_set_reuseaddr`, `sa_std_net_tcp_listener_set_reuseport`. Macros `NET_TCP_STREAM_SET_KEEPALIVE`, `NET_TCP_STREAM_SET_KEEPALIVE_PARAMS`, `NET_TCP_LISTENER_SET_REUSEADDR`, `NET_TCP_LISTENER_SET_REUSEPORT`.
  - h2-over-TLS (`sa_std_http2_client_request` currently connects over plaintext TCP): assessed and intentionally NOT implemented, because both viable paths are blocked in this environment. (1) Zig 0.14's `std.crypto.tls.Client` has no ALPN support at all (0 hits for alpn in the std source), and gRPC/HTTP2-over-TLS requires ALPN negotiation of `h2`. (2) OpenSSL's `SSL_CTX_new`/`SSL_CTX_set_alpn_protos` are versioned-only symbols (`@@OPENSSL_3.0.0`) that Zig 0.14's `DynLib.lookup` cannot resolve — the same limitation that already forces `tls_server`/`dtls` to report `supported=0`. Implementing it now would only produce a handshake-that-fails, so it is left as environment-blocked rather than faked.
  - Verification: `zig build sa-std-unit` -> exit 0; standalone `sa test tests/unit_framework/std_net_unix_macro_surface.sa` -> `1 passed`; full `zig build unit-framework` -> exit 0. `nm` confirms the 7 new symbols are `T` in `libsa_std.{a,so}`. New SA test `tests/unit_framework/std_net_unix_macro_surface.sa` drives a full UDS `listen -> connect -> accept -> write -> read` roundtrip plus the keepalive/reuseaddr setters, registered in the runner suite list.

- 2026-07-03: Closed the two remaining `sa_std` network gaps (DNS hostname resolution + netx SA usability).
  - DNS: `sa_std_net_tcp_listen`, `sa_std_net_udp_bind`, `sa_std_net_udp_connect`, and `sa_std_net_udp_send_to` previously called `std.net.Address.resolveIp` (IP-literal only). Extracted a shared `resolveFirstAddressFromParts(host, port16)` helper (backed by `std.net.getAddressList`, i.e. real getaddrinfo; IP literals still take the numeric fast path) and routed all four through it. `sa_std_net_tcp_connect` already used `tcpConnectToHost` (DNS-capable). `parseIp4Address`/`parseIp6Address` intentionally keep `resolveIp` since their contract is IP-literal parsing. Error mapping already funnels `UnknownHostName`/`HostLacksNetworkAddresses`/`TemporaryNameServerFailure` into the `SA_NET_ERR_NET` family.
  - netx was not actually usable from SA: the 7 `sa_netx_*` functions in `src/runtime/sa_net_uring.zig` were `pub fn` (no C-ABI export), and `sa_net_uring.zig` was only ever compiled as a standalone test module — its symbols never entered the runtime library that SA programs link. Changed all 7 to `pub export fn` and added a comptime force-reference in `src/runtime/sa_std.zig` (same technique used for http2/tls_server/dtls/quic) so they emit into `libsa_std.{a,so}`. `nm` now shows `sa_netx_init/listen/recv_ticket/push_outbound/broadcast/close_slot/shutdown` as `T`.
  - Fixed `sa_std/netx.sai` return types from `i32!` to `i32` (the runtime returns plain status codes, not error-unions; the `!` form would have been decoded as a `Fallible` struct pointer).
  - Expanded `sa_std/netx.sal` with `SA_NETX_*` status codes, `NETX_OP_*` ticket op codes, and `NETX_FLAG_*` bits (mirroring `TicketOp`/`TicketFlag` in the runtime). Note: `.sal` files only accept `#def` directives — bare `#` comment lines trigger `ForbiddenSyntax`, so the section headers were dropped.
  - Authored the `sa_std/netx.sa` macro layer (previously just two `@import` lines): thin wrappers for all 7 externs (`NETX_INIT`/`NETX_LISTEN`/`NETX_SHUTDOWN`/`NETX_RECV_TICKET`/`NETX_PUSH_OUTBOUND`/`NETX_BROADCAST`/`NETX_CLOSE_SLOT`), Ticket field readers (`NETX_TICKET_SLOT_ID`/`OP_CODE`/`PROTO`/`FLAGS`/`PAYLOAD`/`PAYLOAD_LEN`), and convenience macros (`NETX_TICKET_HEADER`, `NETX_TICKET_IS_OP`).
  - Added `tests/unit_framework/std_netx_macro_surface.sa` (registered in `tests/unit_framework/runner.zig`) covering ticket-field macro reads on a hand-filled buffer. The live `init`/`shutdown` round-trip is left to the Zig end-to-end tests in `sa_net_uring.zig`: the in-process unit-framework harness cannot host a live io_uring reactor thread (thread crash), whereas a standalone `sa` process is isolated.
  - Verification: `zig build sa-std-unit` -> exit 0 (DNS changes); `zig build sa-net-uring-test` -> `1/1 tests passed` (after the export change); `zig build unit-framework` -> exit 0 (netx SA macro surface included); `nm zig-out/lib/libsa_std.so` -> all 7 `sa_netx_*` present as `T`.

- 2026-06-27: Added SAB v3 backend metadata preservation for plugin-generated SAB inputs.
  - SAB encoding now preserves raw instruction text plus full backend metadata needed by SA LLVM-C lowering: atomic expected/new operand text, native register names, package identity/source hash, upstream locations, and verifier-derived function register ids.
  - `plugin_bridge.encodeSabFromFlat` verifies flattened SA-compatible input before SAB encoding so decoded SAB carries function signature register metadata instead of relying on text headers.
  - Decoded instruction-owned metadata now has ownership compatible with both `sab.Module.deinit` and `flattener.FlattenResult.deinit`, fixing double-free diagnostics when plugin-generated SAB is loaded as a flat test input.
  - Verification used focused commands only: `timeout 120s zig test src/sab.zig --test-filter "sab v3 preserves instruction metadata required by SA backends"`, `timeout 120s zig test src/sab.zig --test-filter "sab borrow roundtrip preserves raw source text"`, `timeout 120s zig test src/sab.zig --test-filter "sab function signatures roundtrip without function header text"`, and `timeout 120s zig test src/plugin_bridge.zig --test-filter "encodeSabFromFlat writes verified register metadata"`.

- 2026-06-18: Audited rosetta package/module README provenance after the 188-260 cleanup batches.
  - Rechecked `demos/rosetta/201_pkg_manifest_basic` through `220_pkg_lib_dynamic`; the copied README template text is no longer present there.
  - Scanned `demos/rosetta/221_*` through `300_*` for the same stale provenance strings and found no remaining matches.
  - Remaining `main.rs` mentions in a few package READMEs describe the local reference file role, not the removed copied-from-`sci` boilerplate.
  - Verification: `rg -n 'This directory pairs the original Rust rosetta reference with a Sla companion|copied from sci|legacy reference translation only|legacy reference only' demos/rosetta -g 'readme.md'` now reports only the intentional `main.rs` reference notes in `201`-`205`.

- 2026-06-10: Closed the remaining low-risk issue7/issue8 core runtime/emitter items found during the final audit.
  - NetX tickets now copy payload bytes into queue-owned storage before publication, so `Ticket.payload` no longer points directly into mutable/reusable `ConnectionSlot.scratch`; ticket and slot capacity math now uses checked multiplication/power-of-two growth.
  - LLVM-C emitter lowering now builds one function-signature alias index and reuses it for direct calls, vtable resolution, reachability, and indirect-call signature inference instead of repeated linear scans by function name.
  - Test panic scalar diagnostics are protected by a mutex and handle oversized C-provided name lengths without `usize` cast traps.
  - Verification: `zig test src/runtime/sa_net_uring.zig -lc` -> `16/16 tests passed`; `zig test src/runtime/sa_std.zig -lc` -> `4/4 tests passed`; `zig build llvmc-test --summary all` -> `15/15 tests passed`; `zig build test --summary all` -> `116/116 tests passed`; `.git/hooks/pre-push origin https://github.com/layola13/sci.git` -> passed in full profile.

- 2026-06-10: Closed additional issue7 core safety/performance items without touching plugin repositories.
  - Resolver dependencies now carry manifest pinned `source_sha256`; local/global package resolution rejects mismatched package source with `UpstreamShaMismatch`, and `sa pkg install` checks fetched bytes against the manifest pin before continuing.
  - Package fetch rejects option-shaped identities/refs, inserts `--` before `git clone` positional args, and runs git with a small allowlisted environment plus noninteractive credential prompts.
  - Project lock updates now reject silent source-hash drift by default; explicit `allow_source_update` is required before stale target hashes are cleared for a changed package source.
  - Runtime pthread handles now reuse a free-slot stack instead of scanning the full slot table on each spawn, and network host inputs reject embedded NUL bytes before DNS/IP resolution.
  - Verification pending in the next batch: focused pkg/runtime tests, then full `zig build test` and pre-push hook.

- 2026-06-10: Implemented issue8 Tier-1 core performance indexes in the compiler kernel.
  - Replaced `parseOpKind` / `parseOpCode` string cascades with `std.StaticStringMap` lookups, keeping the same opcode and compatibility-alias coverage.
  - Added a verifier `sig_index_by_name` map during metadata collection so call-site signature checks and function-symbol argument checks stop scanning every function signature.
  - Moved interpreter per-function label maps and global-register slot maps into cached `FunctionRange` state built at interpreter initialization, removing repeated label-map rebuilds and hot `FunctionSig.slotOf` linear scans during execution.
  - Kept interpreter memory blocks sorted by base address and changed range lookup to binary search, preserving interior-pointer support while avoiding per-load/store linear scans over all blocks.
  - Added coverage for sorted/range-aware memory lookup after frees.
  - Verification: `zig test src/common/instruction.zig` -> `5/5 tests passed`; `zig test src/interp.zig` -> `159/159 tests passed`; `zig test src/verifier.zig` -> `153/153 tests passed`; `zig test src/cli.zig` -> `89/89 tests passed`.

- 2026-06-10: Finished low-risk issue8 compiler-kernel allocation and scan reductions.
  - Added a `VerifierBufferPool` so verifier per-function register state, flags, origins, lock state, consumed-reg flags, and interior-pointer arrays grow once per `verifyBody` worker and are reused by slicing and clearing on each function.
  - Removed now-dead verifier per-function buffer allocation/free helpers from the hot declaration path.
  - Reworked `DefDict.foldText` from a pre-scan plus replacement scan into a single lazy-output pass, preserving the zero-replacement fast path.
  - Preallocated `appendOwnedSource` capacity for imported source chunks plus the optional newline before appending.
  - Verification: `zig test src/verifier.zig` -> `153/153 tests passed`; `zig test src/interp.zig` -> `159/159 tests passed`; `zig test src/cli.zig` -> `89/89 tests passed`; `zig test src/flattener/def_dict.zig` -> `5/5 tests passed`; `zig test src/flattener.zig` -> `83/83 tests passed`.

- 2026-06-10: Hardened cached macro helper allocation-failure paths from the core flattener review.
  - Changed cached macro capture/restore ownership setup to clean up only initialized params/body lines on OOM, avoiding undefined frees and leaks in partially copied macro definitions.
  - Added allocation-failure injection coverage for the capture/restore helper path.
  - Verification: covered by `zig test src/interp.zig`, `zig test src/verifier.zig`, and `zig test src/cli.zig` flattener test imports above.

- 2026-06-10: Added tested cached-macro replay support for future frontend fragment reuse.
  - Extended `FlattenResult` ownership with `cached_macro_defs` so a flattened fragment can carry imported macro definitions alongside instructions, defs, consts, signatures, layout metadata, and package identities.
  - Changed macro collection to snapshot each macro body into owned `SourceLine` storage, so later expansion no longer depends on the original parent file `lines[start..end]` slice surviving or matching the same indices.
  - Updated macro expansion to use `macroDefBodyLines()` for hygiene name collection and recursive `emitRange` calls, fixing cached/imported macro replay and nested expansion under remapped fragment reuse.
  - Wired `appendFlattenFragment` to restore cached macro definitions into the target macro table and added regression coverage proving an imported macro fragment can still be expanded later in the parent file context.
  - Verification: `zig test src/flattener.zig` -> `82/82 tests passed`; `zig test src/cli.zig` -> `88/88 tests passed`.

- 2026-06-10: Added tested end-to-end fragment append helper and corrected `FunctionSig.id` remap semantics.
  - Added `appendFlattenFragment` to compose the existing clone/remap/merge helpers into one append step for `instructions`, `const_decls`, `function_sigs`, `test_sigs`, `defs`, `layout_versions`, `package_identities`, and `owned_text`.
  - Corrected `FunctionSig.id` handling so cached fragment replay treats it as a function-list index offset, not a `SymbolTable` id remap; test `llvm_name` values are regenerated from the new function id.
  - Made appended `test_sigs` own their own copied signatures instead of aliasing `function_sigs`, avoiding double-free and matching current `FlattenResult.deinit` ownership.
  - Added end-to-end coverage proving a fragment can be appended into a non-empty target container while preserving symbol remap, line offsets, function-id offsets, test metadata, layout metadata, package identities, and owned text independence.
  - Verification: `zig test src/flattener.zig` -> `81/81 tests passed`; `zig test src/cli.zig` -> `87/87 tests passed`.

- 2026-06-09: Added tested fragment metadata merge helpers for future cached frontend fragments.
  - Added `package_identities` merge coverage that skips duplicate package keys and deep-copies newly imported identities instead of aliasing source fragment storage.
  - Added `LayoutVersion` clone/merge helpers that skip identical `(path, version)` pairs, deep-copy new paths, and reject same-path/different-version conflicts.
  - This closes the remaining fragment-metadata merge prerequisite before cached `FlattenResult` fragments can be appended into a consumer result; production cache wiring and cache-on/off equivalence tests remain separate work.
  - Verification: `zig test src/flattener.zig` -> `80/80 tests passed`; `zig test src/cli.zig` -> `86/86 tests passed`.

- 2026-06-09: Added tested `Instruction` clone-remapping for future cached frontend fragments.
  - Added a helper to deep-clone instructions while remapping symbol/reg/label/function operands and applying source/expanded line offsets.
  - The clone path preserves and owns package identity, package source hash, upstream locations, raw text, text/native operands, atomic text fields, op/atomic metadata, and native register-name slices through the existing `owned_text` ownership model.
  - Added regression coverage for call-style symbol remapping, metadata deep-copy ownership, line offsets, and native instruction register-name slice rebuilding.
  - This closes the instruction-splicing prerequisite before cached `FlattenResult` fragments can be appended into a consumer result; production cache wiring and cache-on/off equivalence tests remain separate work.
  - Verification: `zig test src/flattener.zig` -> `78/78 tests passed`; `zig test src/cli.zig` -> `84/84 tests passed`.

- 2026-06-09: Added tested def/const merge helpers for future cached frontend fragments.
  - Added helper coverage for merging `DefDict` entries with identical duplicates skipped, new entries deep-copied, and same-name/different-value entries rejected.
  - Added deep clone and equality helpers for `ConstDecl` / `ConstValue`, including owned text, upstream locations, bytes literals, struct fields, and vtable slots.
  - Added const merge coverage proving cloned declarations get source/expanded line offsets, do not share owned buffers with the source fragment, skip identical duplicates, and reject conflicting duplicate names.
  - This closes the def/const merge prerequisite before cached `FlattenResult` fragments can be safely spliced into a consumer result; production cache wiring and cache-on/off equivalence tests remain separate work.
  - Verification: `zig test src/flattener.zig` -> `76/76 tests passed`; `zig test src/cli.zig` -> `82/82 tests passed`.

- 2026-06-09: Added tested full `FunctionSig` clone-remapping for future cached frontend fragments.
  - Added a helper to deep-clone function signatures while remapping `id`, `param_ids`, and `reg_ids`, preserving owned names, params, return shape, upstream location, test flags, llvm names, and applying an entry-instruction offset.
  - Added regression coverage for deep-copy ownership, upstream file/location preservation, entry index offsetting, remapped IDs, and invalid source IDs.
  - This closes another full IMP-1 prerequisite before cached `FlattenResult` fragments can be spliced into a consumer result.
  - Verification: `zig test src/flattener.zig` -> `74/74 tests passed`; `zig test src/cli.zig` -> `80/80 tests passed`.

- 2026-06-09: Added tested symbol-id slice remapping for future cached `FunctionSig` reconstruction.
  - Added `cloneRemappedSymbolIdSlice` so immutable `FunctionSig.param_ids` / `reg_ids`-style slices can be rebuilt under the caller allocator instead of mutated in place.
  - Added coverage for non-empty remaps, stable empty slices, copied storage, and invalid old ID rejection.
  - This completes the basic symbol ID remap primitives needed before cached `FlattenResult` fragments can be spliced into a consumer symbol table.
  - Verification: `zig test src/flattener.zig` -> `72/72 tests passed`; `zig test src/cli.zig` -> `78/78 tests passed`.

- 2026-06-09: Added tested symbol-id remap helpers for future per-module `FlattenResult` caching.
  - Added helper infrastructure to build a source-to-target `SymbolTable` ID map and remap `Instruction` operands of kind `reg`, `symbol`, `label`, and `func` while leaving text/immediate/type operands unchanged.
  - Added regression coverage proving remapped IDs change when the target symbol table already has entries, non-symbol operands are stable, and invalid old IDs are rejected.
  - This is a prerequisite for issue6 full IMP-1 `FlattenResult` fragment reuse; function signature ID slice remapping and raw-text/name collision strategy remain separate work.
  - Verification: `zig test src/flattener.zig` -> `71/71 tests passed`; `zig test src/cli.zig` -> `77/77 tests passed`.

- 2026-06-09: Added and hardened a conservative expanded-import fragment cache as an issue6 IMP-1 stepping stone.
  - Added a process-local cache for already expanded import text fragments, including line counts, transitive file mtime/size stats, layout version metadata, and LRU hooks via `SA_EXPANDED_IMPORT_CACHE_MAX_ENTRIES=N`.
  - Cache hits append the expanded fragment and mark all transitive files as seen, skipping recursive import expansion across repeated flatten calls while preserving import-cycle and duplicate-import fallback behavior.
  - The cache only stores fragments with null package identity/hash metadata, so package-context imports still use the original expansion path until full frontend IR remapping is implemented.
  - Added flattener coverage proving two entry files importing the same std fragment store on the first flatten and hit on the second, changed transitive imports invalidate cached fragments, and the opt-in one-entry LRU evicts older fragments.
  - Verification: `zig test src/flattener.zig` -> `69/69 tests passed`; `zig test src/cli.zig` -> `75/75 tests passed`; `zig build unit-framework --summary all` -> `6/6 steps succeeded; 4/4 tests passed`; `zig build smoke --summary all` -> `9/9 steps succeeded; 15/15 tests passed`.

- 2026-06-09: Added opt-in LRU bounds for the CLI source-tree hash cache for issue6 cache hygiene.
  - Added `SA_SOURCE_TREE_HASH_CACHE_MAX_ENTRIES=N` for long-lived consumers that need bounded source-tree digest cache maps; the default CLI path remains unbounded for short-lived command performance.
  - Source-tree digest cache hits now refresh LRU state, and stores evict the least-recently-used digest entry when the optional limit is exceeded.
  - Added CLI unit coverage proving a one-entry cache keeps the most recent tree digest hot and reloads an evicted older tree.
  - Verification: `zig test src/cli.zig` -> `72/72 tests passed`.

- 2026-06-09: Reduced flattener hot-path ArrayList growth for issue4 PERF-4.
  - Added exact source-line counting and preallocated `scanSource` output before classifying lines, avoiding repeated `SourceLine` array growth on large expanded inputs.
  - Preallocated import expansion output bytes and line metadata arrays per source/import chunk, reducing allocator churn while preserving all returned result ownership under the caller allocator.
  - Added unit coverage for line-count semantics matching `std.mem.splitScalar`, including empty and trailing-newline sources.
  - Verification: `zig test src/flattener.zig` -> `66/66 tests passed`; `zig test src/cli.zig` -> `71/71 tests passed`.

- 2026-06-09: Added opt-in LRU bounds for the process-local flattener import source cache for issue6 IMP-3.
  - Added `SA_IMPORT_CACHE_MAX_ENTRIES=N` for long-lived consumers that need bounded import cache maps; the default CLI path remains unbounded and keeps borrowed source hits for maximum short-lived performance.
  - When a max-entry limit is enabled, cache hits now return owned source clones instead of borrowed cache slices, making LRU eviction safe because evicted entries can free their source buffers without dangling callers.
  - Added LRU tick tracking and eviction of the least-recently-used import cache entry after stores exceed the configured limit.
  - Verification: `zig test src/flattener.zig` -> `65/65 tests passed`; `zig test src/cli.zig` -> `70/70 tests passed`; `zig build smoke --summary all` -> `15/15 tests passed`.

- 2026-06-09: Added source-tree test metadata caching as the first low-risk issue6 IMP-1 frontend-cache slice.
  - `.sa_cache/test/<key>` entries now include `test-metadata.json` with discovered SA test names, selector symbols, source locations, ignored flags, and should-panic flags.
  - `sa test` now computes the project test cache key before `compileSource`; when artifact/output/manifest/metadata are all valid, `--list`, `--compile-only`, and normal test execution reuse cached metadata and skip flatten+verify for discovery/filtering.
  - Old or incomplete test cache entries without metadata are treated as invalid and repaired through the existing recompilation path; cache clean now requires `test-metadata.json` for test cache completeness.
  - Verification: `zig test src/cli.zig` -> `69/69 tests passed`; `zig build bc2sa-smoke --summary all` -> `3/3 tests passed`; `zig build smoke --summary all` -> `15/15 tests passed`; `zig build unit-framework --summary all` -> `4/4 tests passed` with `feature_suite.sa all modes` down to about `9.7s` on the cached metadata path.

- 2026-06-09: Removed brittle hardcoded unit-framework expected test lists for issue6 TEST-4.
  - Added an SA test expectation builder in `tests/unit_framework/runner.zig` that parses `@test`, `@test should_panic`, and `@test ignored` declarations from each `.sa` suite, then generates `[PASS] ...` markers and the expected summary line automatically.
  - Replaced the 271-pass feature-suite hardcoded marker block with generated expectations, including automatic absent-marker checks for ignored tests.
  - Replaced per-suite std macro surface expected-name arrays and hand-maintained pass counts with a single macro-surface path table plus `runSaTestFileAuto`, so adding/removing `@test` cases in those source files no longer requires runner count/list edits.
  - Verification: `zig build unit-framework --summary all` -> `4/4 tests passed`; `zig build smoke --summary all` -> `15/15 tests passed`; `git diff --check` -> clean.

- 2026-06-09: Reused flattener import-source cache during project source-tree hashing for issue6 CACHE-2.
  - Exposed a narrow `readImportSourceFile` wrapper so cache-key hashing can resolve imported SA files through the same flattener import source cache used by the real flatten path.
  - Entry files still use the CLI `loadSource` path, while imported files pass their resolved source into recursive hashing, avoiding a second same-process source read/resolve for cacheable std and stable support imports.
  - Extended CLI cache coverage to prove the first source-tree hash warms the flattener import cache, the unchanged second hash uses the mtime/size digest fast path without another source load, and a dependency edit invalidates the digest.
  - Verification: `zig test src/flattener.zig` -> `64/64 tests passed`; `zig test src/cli.zig` -> `69/69 tests passed`; `zig build smoke --summary all` -> `15/15 tests passed`; `zig build unit-framework --summary all` -> `4/4 tests passed`.

- 2026-06-09: Split the large string/vec macro surface suite for issue6 TEST-3.
  - Replaced the single 38-test `std_string_vec_macro_surface.sa` scheduling unit with `std_string_macro_surface.sa` (13 tests), `std_slice_vec_macro_surface.sa` (17 tests), and `std_vec_macro_surface.sa` (8 tests), preserving the shared imports/constants/helpers in each split file.
  - Updated the unit-framework runner expectations to keep the same 38 tests covered while enabling file-level parallel scheduling of the former slowest macro surface group.
  - Updated `docs/test_performance.md` with the split files and latest visible timings: about 18.0s, 18.3s, and 9.8s respectively.
  - Verification: `zig build unit-framework --summary all` -> `4/4 tests passed`.

- 2026-06-09: Extended flattener import source caching to stable support roots for issue6 IMP-2.
  - Added `stable_import_roots` to resolver options and included them in the import source cache key.
  - The flattener now caches local imports whose resolved path is under an explicit stable root, while preserving the existing `sa_std` cache behavior and mtime/size invalidation.
  - CLI compile paths automatically mark `<project>/tests/unit_framework/support` as a stable import root when present, so shared SA test support files can reuse cached source in process-local test runs.
  - Verification: `zig test src/flattener.zig` -> `64/64 tests passed`; `zig test src/cli.zig` -> `69/69 tests passed`; `zig build unit-framework --summary all` -> `4/4 tests passed`.

- 2026-06-09: Added a source-tree mtime/size fast path for project build/test cache keys for issue6 CACHE-1.
  - `hashResolvedSourceTree` now computes a per-source-tree digest once, records the participating files' real paths, mtimes, and sizes, and reuses that digest on later same-process key calculations when only stat checks are needed.
  - The fallback path still performs the existing content hash, import classification, and import resolution when any participating file changes, preserving cache invalidation correctness.
  - Added CLI unit coverage proving the second unchanged tree hash does not call `loadSource` again and a dependency edit invalidates the fast path.
  - Verification: `zig test src/cli.zig` -> `68/68 tests passed`; `zig build smoke --summary all` -> `15/15 tests passed`.

- 2026-06-09: Aligned referee LOC lint scope with the real verifier core for issue5 ENG-1.
  - Changed `tools/referee_loc_lint.zig` to measure both `src/referee/` and `src/verifier.zig`, including the builtin fallback path used when `tokei` is unavailable.
  - Updated `tasks.md` task 6.27 from the old `src/referee/ <= 2500` scope to the honest `src/referee/ + src/verifier.zig <= 6500` scope, currently 5960 code lines by fallback count.
  - Verification: `zig build referee-loc-lint --summary all` -> PASS `5960 <= 6500`; `zig test src/cli.zig` -> `67/67 tests passed`.

- 2026-06-09: Improved `sa run` diagnostics for unsupported extern/plugin symbols for issue5 SEC-1 without changing plugin repositories.
  - Added a dedicated interpreter `UnsupportedExtern` path when `sa run` reaches an `@extern` declaration, printing the exact symbol name and explaining that native build may work with the providing plugin/library while the interpreter broker/FFI bridge is not implemented.
  - Suppressed the generic CLI error wrapper for this specific interpreter failure so users see one actionable diagnostic instead of a bare `InvalidInstruction` or duplicate error label.
  - Added CLI smoke coverage for a minimal extern call under `sa run` to assert the symbol name is reported.
  - Verification: `zig test src/interp.zig` -> `138/138 tests passed`; `zig test src/cli.zig` -> `67/67 tests passed`; `zig build bc2sa-smoke --summary all` -> `3/3 tests passed`.

- 2026-06-09: Cleaned main-repo generated artifacts for issue5 ENG-2 without touching the external plugin repository.
  - Removed root-level temporary Zig/SA scaffolding, `.tmp_plugin_check` build outputs, demo compiled binaries, and `tests/unit_framework/feature_suite.o` from Git tracking while leaving local working copies ignored.
  - Added ignore rules for root temp files and common compiled artifacts (`*.o`, `*.so`, `*.dll`, `*.dylib`, `*.a`, `*.exe`) so future generated outputs do not re-enter the repository.
  - Kept real source modules such as `src/test_runner.zig` / `src/test_executor.zig` tracked after reference scanning showed they are part of the SA test framework.
  - Verification: tracked temp/binary scan for the removed classes -> clean; `zig build smoke --summary all` -> `15/15 tests passed`.

- 2026-06-09: Tightened plugin network permission URL validation for issue5 SEC-3.
  - Replaced prefix-only permission URL acceptance with scheme/host parsing for install-time and runtime broker checks.
  - Remote `http://`, missing schemes, and non-loopback bare IP hosts are now rejected; loopback HTTP remains allowed for local development and HTTPS domain permissions remain allowed.
  - Kept broad HTTPS wildcard permissions install-compatible but now emits an installer warning so official/plugin manifests can be narrowed without silently granting broad intent.
  - Verification: `zig test src/plugins.zig` -> `1/1 tests passed`; `zig build plugin-host-smoke --summary all` -> `11/11 tests passed`.

- 2026-06-09: Added field-level mutable borrow checks for issue5 FUNC-2.
  - Extended verifier interior-pointer state with root object and static byte-offset metadata, including label snapshot/restore handling so branch joins preserve field identity.
  - Mutable borrow conflict checks now allow simultaneous borrows of distinct known static offsets from the same root while preserving conflicts for identical offsets, unknown offsets, and whole-object borrows.
  - Offset accumulation now uses checked arithmetic and falls back to conservative unknown-offset behavior on overflow.
  - Verification: `zig test src/verifier.zig` -> `133/133 tests passed`; `zig test src/cli.zig` -> `67/67 tests passed`; `zig build smoke --summary all` -> `15/15 tests passed`.

- 2026-06-09: Verified local plugin artifact hashes before runtime loading for issue5 SEC-2.
  - Parsed selected `sap.json` artifact sha256 into `SapManifest` and preserved backward compatibility for manifests that omit artifact hashes.
  - Added a pre-`dlopen` runtime check that compares the declared artifact sha256 against the dynamic library being loaded and records a diagnostic instead of loading mismatched code.
  - Added plugin-host smoke coverage for both matching and mismatched artifact hashes.
  - Verification: `zig build plugin-host-smoke --summary all` -> `11/11 tests passed`.

- 2026-06-09: Tightened verifier metadata diagnostics and audited empty catch blocks for issue5 FUNC-1/FUNC-3.
  - Replaced the metadata rebuild `else => .forbidden_syntax` catch-all with explicit trap mapping for unsupported types, OOM, test signature mismatches, invalid atomic ordering, invalid declaration/atomic syntax, and a non-forbidden unclassified metadata fallback.
  - Added verifier coverage for metadata error mapping and invalid atomic ordering trap codes.
  - Removed bare `catch {}` from `src/`; cleanup/diagnostic-only failures now carry explicit best-effort comments, cache clean delete failures propagate, and interpreter release-time memory free errors propagate.
  - Verification: `zig test src/verifier.zig` -> `130/130 tests passed`; `zig test src/cli.zig` -> `67/67 tests passed`; `zig build pkg-core-test --summary all` -> `33/33 tests passed`; `zig build smoke --summary all` -> `15/15 tests passed`.

- 2026-06-09: Removed repeated verifier leak-scan passes for issue5 PERF-2.
  - Replaced per-live-register `regConsumedLater` full-function scans with a per-function consumed-register bitset computed once when the function scope is created.
  - Preserved existing structured consumption semantics for `move`, `release`, `assign`, `return`, `try` / `early_return`, and `^reg` call/native text markers while making early-return and exit leak checks O(1) per candidate.
  - Added a verifier regression test proving an early-return leak still reports `EarlyReturnLeak` and the consumption scan runs once over function bodies rather than once per live leak candidate.
  - Verification: `zig test src/verifier.zig` -> `128/128 tests passed`.

- 2026-06-09: Reduced verifier line classification work for issue5 PERF-1.
  - `verifyWithOptions` now preclassifies the instruction stream once and shares that `ClassifiedLine` array with metadata collection, serial body verification, and parallel body verification chunks.
  - Removed the second per-instruction `classifyLine(item.raw_text)` pass from `verifyBody`; verifier classification now happens in one verifier-owned pass instead of metadata and body passes independently reparsing the same text.
  - Added a verifier regression test that counts test-build classifier calls and asserts one classification per instruction for a complete verify run.
  - Verification: `zig test src/verifier.zig` -> `127/127 tests passed`.

- 2026-06-09: Added process-isolated file-level parallelism for SA macro surface unit tests.
  - `unit-framework` now can run independent SA macro surface files through the freshly built `sa` binary when `SA_UNIT_FILE_JOBS` is greater than 1, avoiding shared in-process CLI state while allowing file-level concurrency.
  - The pre-push timing script now exports `SA_UNIT_FILE_JOBS` from the detected host job count and leaves per-file `SA_TEST_JOBS` unset by default; the runner uses `--jobs 1` inside each concurrent file unless the caller explicitly overrides it.
  - Verification: `zig build unit-framework --summary all` -> `4/4 tests passed`; `SA_UNIT_FILE_JOBS=4 zig build unit-framework --summary all` -> `4/4 tests passed`, run step about `1m` with macro surface files at `54.960s`.

- 2026-06-09: Reduced single-thread LLVM emitter arena page-allocator churn.
  - Added a shared emit-job backing allocator selector in `src/emit_llvm_llvmc.zig` so single-worker LLVM emission backs per-task arenas with the caller allocator instead of forcing `std.heap.page_allocator` for every job.
  - Preserved `std.heap.page_allocator` for parallel emission because the caller allocator is not guaranteed to be thread-safe across worker jobs.
  - Verification: `zig build llvmc-test --summary all` -> `1/1 tests passed`; `zig build smoke --summary all` -> `15/15 tests passed`.

- 2026-06-09: Hardened MPSC receive against damaged tail/head state.
  - Added an explicit `tail >= head` guard to `__mpsc_try_recv`; damaged `tail < head` state now returns failure before slot indexing or head movement can proceed.
  - Extended `tests/unit_framework/std_mpsc_macro_surface.sa` with a corrupted ring-state receive check and updated std smoke/source assertions.
  - Updated `docs/std_missing.md` sync safety notes to include receive-side MPSC damaged-state handling.

- 2026-06-09: Gated flattener import trace output.
  - Changed noisy `[IMPORT] resolved ...` debug printing to be disabled by default and enabled only with `SAASM_TRACE_IMPORTS=1`.
  - Preserved import resolution diagnostics for explicit tracing while removing routine stderr noise from smoke/unit runs.
  - Verification: `zig test src/flattener.zig` -> `63/63 tests passed` with no default `[IMPORT]` output.

- 2026-06-09: Reduced std import cache source cloning in the flattener.
  - Changed process-local std import cache hits to return borrowed source text from the cache instead of duplicating the full imported file into the caller allocator on every hit.
  - Kept invalidated cache source buffers alive for the process lifetime so concurrent or nested import expansion cannot observe dangling borrowed text while stale metadata is removed.
  - Added flattener coverage proving the first std import load owns source text while the second cache hit reuses borrowed source with `owned_source == null`.
  - Verification: `zig test src/flattener.zig` -> `63/63 tests passed`.

- 2026-06-09: Added manifest-backed project cache validation.
  - Build/test artifact cache entries now write `manifest.json` with cache kind, key, artifact size/hash, and output size/hash.
  - Cache hits validate the manifest before reuse and delete mismatched, stale, incomplete, or manually corrupted entries before recompiling.
  - `sa cache clean` now treats missing or invalid manifests as invalid cache state, so explicit cleanup removes old-format or damaged project cache entries instead of keeping them based only on non-empty files.
  - Verification: `zig test src/cli.zig` -> `66/66 tests passed`; `zig build smoke --summary all` -> `15/15 tests passed`.

- 2026-06-09: Reduced verifier state-delta allocation overhead.
  - Changed verifier state-delta construction to scan for actual register state changes before allocating, returning a shared empty delta for unchanged instructions.
  - Avoided duplicating empty deltas while merging parallel verifier worker results, reducing hot-path allocator churn without changing annotated instruction semantics.
  - Verification: `zig test src/verifier.zig` -> `125/125 tests passed`.

- 2026-06-09: Added project cache cleanup and SA test artifact cache repair.
  - Added core CLI support for `sa cache clean`, including `--dry-run` and `--max-age-days`, scoped only to the current project's `.sa_cache` so package/plugin caches remain separate.
  - Cache cleanup now scans `build-exe`, `build-obj`, `build-wasm`, `build-obj-incremental`, and `test` cache families, removes malformed hex keys, incomplete entries, empty artifacts, non-directory entries, and complete entries older than the configured age.
  - Build/test cache hits now validate cached `artifact.sa.bc` and `output.bin` before reuse; incomplete or damaged entries are deleted before the command falls back to recompilation.
  - `sa test` now stores no-plugin test compile/link artifacts under `.sa_cache/test`, so repeated `--compile-only` or repeated runs of the same test source can skip emit/link while still recompiling frontend metadata for selection/list accuracy.
  - Verification: focused CLI smoke filters for `cli cache clean removes invalid project cache entries` and `sa test compile-only reuses and repairs project test cache` both passed; `zig build bc2sa-smoke --summary all` -> `3/3 tests passed`; `zig build std-smoke unit-framework --summary all` -> `18/18 tests passed`; `./zig-out/bin/sa cache clean --max-age-days 0` -> `scanned=41 removed=0 kept=41`.

- 2026-06-09: Added seeded HashMap construction for hash-flooding hardening hooks.
  - Added a `HashMap_seed` field to the core HashMap layout, `sa_map_with_seed`, `sa_map_with_capacity_seed`, and matching `MAP_WITH_SEED` / `MAP_WITH_CAPACITY_SEED` macros.
  - Routed HashMap probe hashing through the stored seed while preserving the default zero-seed behavior for existing `MAP_NEW` / `MAP_WITH_CAPACITY` users.
  - Updated smoke layout/API assertions and extended `tests/unit_framework/std_hashmap_macro_surface.sa` with seeded constructor coverage for put/get/delete and capacity initialization.
  - Verification: `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_hashmap_macro_surface.sa --jobs 1 --trace-panic` -> `7 passed; 0 failed; 0 skipped`.

- 2026-06-09: Reduced unit-framework feature-suite duplicate execution.
  - Kept the full `tests/unit_framework/feature_suite.sa` matrix as the default large-suite coverage, still asserting `271 passed; 0 failed; 0 skipped; 1 ignored` and representative pass markers.
  - Moved `--ignored` and `--include-ignored` mode checks to a tiny generated fixture inside `tests/unit_framework/runner.zig`, avoiding two extra executions of the 271-test feature matrix.
  - Verification: `zig build unit-framework --summary all` -> `4/4 tests passed`; `feature_suite.sa all modes` timing dropped to about `23.204s` in the visible runner timing, with remaining slow files led by `std_string_vec_macro_surface.sa` (`48.007s`), `std_path_macro_surface.sa` (`24.850s`), and `std_net_addr_macro_surface.sa` (`14.801s`).

- 2026-06-09: Hardened package identity validation and low-level memory diagnostics.
  - Strengthened package identity validation in `src/pkg/fetch.zig` to reject absolute paths, backslashes, `.` segments, and `..` segments before package fetch/cache paths are constructed.
  - Added null-pointer guard traps to `sa_std/core/mem.sa` for `sa_mem_copy` when `count > 0`, while preserving zero-length copy no-op behavior.
  - Documented `sa_std/core/refcell.sa` as non-atomic and not thread-safe, matching Rust's `!Sync` shape for this concrete runtime cell.
  - Isolated filesystem macro surface test paths so `std_fs_macro_surface.sa` can run with `--jobs auto` instead of a runner-level single-thread special case.
  - Verification: `zig build pkg-core-test --summary all` -> `33/33 tests passed`; `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_fs_macro_surface.sa --jobs auto --trace-panic` -> `8 passed; 0 failed; 0 skipped`; `zig build unit-framework --summary all` -> `4/4 tests passed`.

- 2026-06-09: Hardened P0 std container and RwLock safety paths.
  - Added checked capacity arithmetic in `sa_std/alloc/vec.sa`, `sa_std/hashmap.sa`, and `sa_std/sync/mpsc.sa` before allocator-facing byte counts or clearing byte counts can wrap.
  - Changed Vec push growth from linear `cap + 1` to zero-case then checked doubling, reducing repeated push growth from O(n^2) reallocation behavior to amortized growth.
  - Reworked `sa_std/sync/rwlock.sa` reader/writer state to use atomic loads/stores, `atomic_rmw_add/sub`, and `cmpxchg` writer claims; reader acquisition rolls back if a writer appears after the reader count increment.
  - Added RwLock read-release underflow trap, Arc strong/weak refcount overflow traps, safe-by-default `VEC_GET` / `VEC_GET_U64`, and explicit `VEC_GET_UNCHECKED` for old unchecked indexing behavior.
  - Added bounded exponential backoff to `sa_std/sync/mutex.sa` and release stores for force-unlock paths.
  - Added `-Drelease-safe` build selection and a release workflow core-check job that gates packaging on release-safe tests plus package audit/perf checks.
  - Updated smoke assertions in `tests/std_smoke.zig` and `tests/std_smoke_containers.zig`, unit coverage for Vec checked access/growth expectations, plus `docs/std_missing.md` safety notes for Vec, HashMap, MPSC, Arc, Mutex, and RwLock.
  - Verification: focused SA unit tests for string/vec, hashmap, mpsc, arc, and rwlock all passed; `zig build std-smoke --summary all` -> `14/14 tests passed`; `zig build -Drelease-safe --summary all` -> `14/14 steps succeeded`.

- 2026-06-09: Added concrete Rust-style memory helper macros.
  - Added `MEM_SIZE_OF_VAL_U64`, `MEM_SIZE_OF_VAL_RAW_U64`, `MEM_ALIGN_OF_VAL_U64`, `MEM_ALIGN_OF_VAL_RAW_U64`, `MEM_DROP_U64`, `MEM_COPY_U64`, `MAYBE_UNINIT_U64_ASSUME_INIT_REF`, `MAYBE_UNINIT_U64_ASSUME_INIT_MUT`, `MAYBE_UNINIT_U64_ASSUME_INIT_DROP`, `MAYBE_UNINIT_U64_AS_BYTES`, `MAYBE_UNINIT_U64_AS_BYTES_MUT`, `MANUALLY_DROP_U64_DEREF`, and `MANUALLY_DROP_U64_DEREF_MUT` in `sa_std/mem.sa`.
  - Extended `tests/unit_framework/std_mem_macro_surface.sa` for concrete value layout, maybe-uninit reference/mutable pointer access, byte-slice views, drop-reset behavior, and manual-drop transparent deref pointers.
  - Updated `docs/std_missing.md` to count this concrete `u64` memory subset while keeping Rust's generic `MaybeUninit<T>`, `ManuallyDrop<T>`, drop glue, and type-driven reflection out of scope.
  - Verification: `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_mem_macro_surface.sa --jobs 1 --trace-panic` -> `3 passed; 0 failed; 0 skipped`; `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa skills` -> `3160 macros, 515 extern/export declarations`; `zig build cli-skills-smoke --summary all` -> `2/2 tests passed`; `git diff --check` -> clean.

- 2026-06-09: Added Rust-style pointer and NonNull method aliases.
  - Added transparent pointer cast/expose-provenance helpers, wrapping byte and concrete `u64` offset aliases, unsigned offset-from helpers, deterministic guaranteed-equality helpers, and matching `NonNull` alignment/offset/equality wrappers in `sa_std/ptr.sa`.
  - Extended `tests/unit_framework/std_ptr_macro_surface.sa` for raw pointer and `NonNull` address, cast, wrapping offset, unsigned offset, alignment, and guaranteed equality behavior.
  - Updated `docs/std_missing.md` to count the concrete pointer method-name subset while keeping strict provenance reconstruction, metadata/fat-pointer APIs, hardware volatile semantics, and Rust's compile-time unknown guaranteed-equality state out of scope.
  - Verification: `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_ptr_macro_surface.sa --jobs 1 --trace-panic` -> `2 passed; 0 failed; 0 skipped`; `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa skills` -> `3147 macros, 515 extern/export declarations`; `zig build cli-skills-smoke --summary all` -> `2/2 tests passed`; `git diff --check` -> clean.

- 2026-06-09: Added Rust-style numeric bit-position helper macros.
  - Added `NUM_U64_BIT_WIDTH`, `NUM_U64_ISOLATE_HIGHEST_ONE`, `NUM_U64_ISOLATE_LOWEST_ONE`, `NUM_U64_HIGHEST_ONE`, `NUM_U64_LOWEST_ONE`, and signed `i64` bit-pattern count/zero/one/isolate/highest/lowest helpers in `sa_std/num.sa`.
  - Extended `tests/unit_framework/std_num_macro_surface.sa` for zero and mixed unsigned bit positions, signed all-ones/negative bit scans, and `(ok, index)` behavior for zero/nonzero inputs.
  - Updated `docs/std_missing.md` to count the concrete numeric bit-position subset while keeping Rust's `Option<u32>` return type and generic integer trait surface out of scope.
  - Verification: `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_num_macro_surface.sa --jobs 1 --trace-panic` -> `18 passed; 0 failed; 0 skipped`; `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa skills` -> `3119 macros, 515 extern/export declarations`; `zig build cli-skills-smoke --summary all` -> `2/2 tests passed`; `git diff --check` -> clean.

- 2026-06-09: Added Rust-style concrete IO utility exact/write-all helper macros.
  - Added `IO_EMPTY_READ_EXACT`, `IO_REPEAT_READ_EXACT`, and `IO_SINK_WRITE_ALL` in `sa_std/io.sa` over the existing concrete empty/repeat/sink utility contracts.
  - Extended `tests/unit_framework/std_io_utility_macro_surface.sa` for empty exact-read zero-byte success and nonzero EOF, repeat exact-read buffer filling, and sink write-all success.
  - Updated `docs/std_missing.md`, `tests/std_smoke.zig`, and generated skills to count the concrete IO utility subset while keeping Rust IO traits and arbitrary reader/writer dispatch out of scope.
  - Verification: `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_io_utility_macro_surface.sa --jobs 1 --trace-panic` -> `3 passed; 0 failed; 0 skipped`; `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa skills` -> `3104 macros, 515 extern/export declarations`; `zig build cli-skills-smoke --summary all` -> `2/2 tests passed`; `zig build std-smoke --summary all` -> `14/14 tests passed`; `git diff --check` -> clean.

- 2026-06-09: Added Rust-style concrete IO Cursor helper macros.
  - Added `IO_CURSOR_READ_EXACT`, `IO_CURSOR_WRITE_ALL`, `IO_CURSOR_FILL_BUF`, and `IO_CURSOR_CONSUME` in `sa_std/io.sa` for Rust `Read`, `Write`, and `BufRead` method-name behavior over the existing concrete cursor layout.
  - Extended `tests/unit_framework/std_io_utility_macro_surface.sa` for exact-read success and EOF behavior, fill-buffer views, consume position changes, write-all success and short-write EOF behavior, and final buffer contents.
  - Updated `docs/std_missing.md` and `tests/std_smoke.zig` to count the concrete Cursor helper subset while keeping Rust `Read` / `Write` / `BufRead` trait objects, vectored IO, and allocation-appending helpers out of scope.
  - Verification: `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_io_utility_macro_surface.sa --jobs 1 --trace-panic` -> `3 passed; 0 failed; 0 skipped`; `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa skills` -> `3101 macros, 515 extern/export declarations`; `zig build cli-skills-smoke --summary all` -> `2/2 tests passed`; `zig build std-smoke --summary all` -> `14/14 tests passed`; `git diff --check` -> clean.

- 2026-06-09: Added Rust-style filesystem Path method wrappers.
  - Added `PATH_TRY_EXISTS`, `PATH_METADATA`, `PATH_CANONICALIZE`, and `PATH_READ_LINK` in `sa_std/path.sa` as thin `Slice` wrappers over existing `FS_*` handles for Rust `Path` method parity.
  - Extended `tests/unit_framework/std_path_macro_surface.sa` for `try_exists`, metadata handle classification/free, canonicalization buffer ownership, and read-link buffer ownership.
  - Updated `docs/std_missing.md` and `tests/std_smoke.zig` to count the new path filesystem method surface while keeping Rust `PathBuf`, `OsStr`, iterator, metadata object, and `io::Error` semantics out of scope.
  - Verification: `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_path_macro_surface.sa --jobs 1 --trace-panic` -> `4 passed; 0 failed; 0 skipped`; `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa skills` -> `3097 macros, 515 extern/export declarations`; `zig build cli-skills-smoke --summary all` -> `2/2 tests passed`; `zig build std-smoke --summary all` -> `14/14 tests passed`; `git diff --check` -> clean.

- 2026-06-09: Added IPv4-backed SocketAddr ASCII parsing for `std::net`.
  - Added `NET_SOCKET_ADDR_TRY_PARSE_ASCII` and `NET_SOCKET_ADDR_PARSE_ASCII` in `sa_std/net.sa` for Rust-style `SocketAddr::parse_ascii` lowering over the current `ipv4:port` parser subset.
  - Extended `tests/unit_framework/std_net_macro_surface.sa` for enum tag checks, port extraction, IP extraction through `IpAddr`, alias expansion, and IPv6-form rejection.
  - Updated `docs/std_missing.md` to count the IPv4-backed enum parser while keeping IPv6 socket parsing, `AddrParseError`, `FromStr`, and full trait conversions out of scope.
  - Verification: `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_net_macro_surface.sa --jobs 1 --trace-panic` -> `10 passed; 0 failed; 0 skipped`; `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa skills` -> `3093 macros, 515 extern/export declarations`; `zig build cli-skills-smoke --summary all` -> `2/2 tests passed`; `git diff --check` -> clean.

- 2026-06-09: Added concrete IPv4-backed IpAddr ASCII parsing for `std::net`.
  - Added `NET_IP_ADDR_TRY_PARSE_ASCII` and `NET_IP_ADDR_PARSE_ASCII` in `sa_std/net.sa` for Rust-style `IpAddr::parse_ascii` lowering over the current IPv4 dotted-decimal parser subset.
  - Extended `tests/unit_framework/std_net_macro_surface.sa` for IPv4 success, enum tag checks, `to_ipv4` extraction, alias expansion, and IPv6-form rejection.
  - Updated `docs/std_missing.md` to count the IPv4-backed IpAddr parser subset while keeping IPv6 parsing, `AddrParseError`, `FromStr`, and enum SocketAddr parser variants out of scope.
  - Verification: `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_net_macro_surface.sa --jobs 1 --trace-panic` -> `9 passed; 0 failed; 0 skipped`; `zig build cli-skills-smoke --summary all` -> `2/2 tests passed`; `git diff --check` -> clean.

- 2026-06-09: Added Rust method-name Duration arithmetic aliases.
  - Added `TIME_DURATION_CHECKED_ADD`, `TIME_DURATION_CHECKED_SUB`, `TIME_DURATION_CHECKED_MUL`, `TIME_DURATION_CHECKED_DIV`, `TIME_DURATION_SATURATING_ADD`, `TIME_DURATION_SATURATING_SUB`, `TIME_DURATION_SATURATING_MUL`, and `TIME_DURATION_ABS_DIFF` in `sa_std/time.sa` as Rust method-name aliases over the existing concrete nanosecond helpers.
  - Extended `tests/unit_framework/std_time_macro_surface.sa` with focused coverage for success, division-by-zero failure, saturation, and absolute-difference behavior through the new names.
  - Updated `docs/std_missing.md` to count the aliases while keeping Rust's typed `Duration`, u128/float conversions, and full overflow/panic semantics out of scope.
  - Verification: `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_time_macro_surface.sa --jobs 1 --trace-panic` -> `3 passed; 0 failed; 0 skipped`; `zig build cli-skills-smoke --summary all` -> `2/2 tests passed`; `git diff --check` -> clean.

- 2026-06-09: Added concrete SocketAddrV4 ASCII parsing for `std::net`.
  - Added `NET_SOCKET_ADDR_V4_TRY_PARSE_ASCII` and `NET_SOCKET_ADDR_V4_PARSE_ASCII` in `sa_std/net.sa`, backed by the `sa_net_socket_addr_v4_parse_ascii` runtime ABI, for Rust-style `SocketAddrV4::parse_ascii` lowering over borrowed `ipv4:port` bytes.
  - Extended `tests/unit_framework/std_net_macro_surface.sa` for successful parsing, max port acceptance, out-of-range port rejection, empty-port rejection, and IPv6-form rejection.
  - Updated `docs/std_missing.md` to count the concrete SocketAddrV4 parser subset while keeping Rust `AddrParseError`, `FromStr`, IPv6, IpAddr, and enum SocketAddr parser variants out of scope.
  - Verification: `zig build --summary all` -> `14/14 steps succeeded`; `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_net_macro_surface.sa --jobs 1 --trace-panic` -> `8 passed; 0 failed; 0 skipped`; `zig build cli-skills-smoke --summary all` -> `2/2 tests passed`; `git diff --check` -> clean.

- 2026-06-09: Added concrete IPv4 ASCII parsing for `std::net`.
  - Added `NET_IPV4_TRY_PARSE_ASCII` and `NET_IPV4_PARSE_ASCII` in `sa_std/net.sa`, backed by the `sa_net_ipv4_parse_ascii` runtime ABI, for Rust-style dotted-decimal `Ipv4Addr::parse_ascii` lowering over borrowed bytes.
  - Extended `tests/unit_framework/std_net_macro_surface.sa` for successful parsing, alias expansion, out-of-range octets, empty octets, and trailing-byte rejection.
  - Updated `docs/std_missing.md` to count the concrete IPv4 parse subset while keeping Rust `AddrParseError`, `FromStr`, IPv6 parsing, and socket-address parser traits out of scope.
  - Verification: `zig build --summary all` -> `14/14 steps succeeded`; `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_net_macro_surface.sa --jobs 1 --trace-panic` -> `7 passed; 0 failed; 0 skipped`; `zig build cli-skills-smoke --summary all` -> `2/2 tests passed`; `git diff --check` -> clean.

- 2026-06-09: Added concrete BTreeMap into key/value view helpers.
  - Added `BTREE_MAP_INTO_KEYS` and `BTREE_MAP_INTO_VALUES` in `sa_std/btree_map.sa` as Rust-named consuming-style aliases over the existing eager key-set/value-Vec materializers followed by `BTREE_MAP_CLEAR`.
  - Extended `tests/unit_framework/std_btree_macro_surface.sa` for key/value output membership and cleared-map state after each helper.
  - Updated `docs/std_missing.md` to remove `into_keys` / `into_values` from the concrete BTreeMap gap while keeping Rust iterator/ownership-transfer semantics out of scope.
  - Verification: `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_btree_macro_surface.sa --jobs 1 --trace-panic` -> `7 passed; 0 failed; 0 skipped`; `zig build cli-skills-smoke --summary all` -> `2/2 tests passed`; `git diff --check` -> clean.

- 2026-06-09: Added concrete HashSet key view helpers.
  - Added `SET_KEYS` and `SET_INTO_KEYS` in `sa_std/hashset.sa` for eager `Vec<u64>` materialization of pointer-key bits.
  - Extended `tests/unit_framework/std_hashset_macro_surface.sa` for non-consuming key views and consuming key views that clear the set.
  - Updated `docs/std_missing.md` to count the concrete key-view subset while keeping Rust lazy iterator and ownership semantics out of scope.
  - Verification: `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_hashset_macro_surface.sa --jobs 1 --trace-panic` -> `6 passed; 0 failed; 0 skipped`.

- 2026-06-09: Added concrete HashMap into key/value view helpers.
  - Added `MAP_INTO_KEYS` and `MAP_INTO_VALUES` in `sa_std/hashmap.sa` as Rust-named consuming-style aliases over the existing eager key/value Vec materializers followed by `MAP_CLEAR`.
  - Extended `tests/unit_framework/std_hashmap_macro_surface.sa` for key/value output membership and cleared-map state after each helper.
  - Updated `docs/std_missing.md` to remove `into_keys` / `into_values` from the concrete HashMap gap while keeping Rust iterator/ownership-transfer semantics out of scope.
  - Verification: `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_hashmap_macro_surface.sa --jobs 1 --trace-panic` -> `6 passed; 0 failed; 0 skipped`.

- 2026-06-09: Added VecDeque front/back mutable pointer aliases.
  - Added `VEC_DEQUE_FRONT_MUT_PTR` and `VEC_DEQUE_BACK_MUT_PTR` in `sa_std/vec_deque.sa` as Rust-named aliases over the existing fallible raw-pointer helpers.
  - Extended `tests/unit_framework/std_vec_deque_macro_surface.sa` so the aliases mutate front/back slots and the later deque operations observe the updated values.
  - Updated `docs/std_missing.md` to count the aliases while keeping Rust's scoped mutable-reference lifetime semantics out of scope.
  - Verification: `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_vec_deque_macro_surface.sa --jobs 1 --trace-panic` -> `5 passed; 0 failed; 0 skipped`.

- 2026-06-09: Added CString borrowed UTF-8 view helper.
  - Added `CSTRING_TO_STR` in `sa_std/ffi.sa` as a Rust-style borrowed `CString::to_str` lowering through the existing `CStr` view and UTF-8 validator.
  - Extended `tests/unit_framework/std_ffi_cstr_macro_surface.sa` for successful UTF-8 CString views and invalid-UTF-8 rejection with `CSTR_TO_STR_INVALID_UTF8`.
  - Updated `docs/std_missing.md` so `CSTR_TO_STR` and `CSTRING_TO_STR` are counted in the concrete FFI C string subset while platform strings and owned conversion/error objects remain out of scope.
  - Verification: `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_ffi_cstr_macro_surface.sa --jobs 1 --trace-panic` -> `2 passed; 0 failed; 0 skipped`.

- 2026-06-09: Added concrete Vec search wrappers.
  - Added `VEC_TRY_BINARY_SEARCH_U64`, `VEC_PARTITION_POINT_U64`, `VEC_LOWER_BOUND_U64`, `VEC_UPPER_BOUND_U64`, and `VEC_EQUAL_RANGE_U64` in `sa_std/vec.sa`.
  - The wrappers delegate to the existing concrete ascending-`u64` slice search helpers through `VEC_AS_SLICE`, preserving explicit `(ok, index)` and index-pair contracts.
  - Extended `tests/unit_framework/std_string_vec_macro_surface.sa` for Vec binary-search hit/miss insertion points, partition point, lower/upper bounds, and equal ranges.
  - Verification: `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_string_vec_macro_surface.sa --jobs 1 --trace-panic` -> `38 passed; 0 failed; 0 skipped`.

- 2026-06-09: Added concrete slice/vector cached-key sort aliases.
  - Added `SLICE_SORT_BY_CACHED_KEY_U64` in `sa_std/core/slice.sa` and `VEC_SORT_BY_CACHED_KEY_U64` in `sa_std/vec.sa`.
  - The helpers provide Rust-named `sort_by_cached_key` lowering for the concrete `u64` surface by delegating to the existing key-sort implementation; Rust's key caching/allocation/panic-drop optimization semantics remain documented as out of scope.
  - Extended `tests/unit_framework/std_string_vec_macro_surface.sa` for both slice and Vec cached-key ordering.
  - Verification: `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_string_vec_macro_surface.sa --jobs 1 --trace-panic` -> `37 passed; 0 failed; 0 skipped`.

- 2026-06-09: Added concrete slice/vector select-nth unstable helpers.
  - Added `SLICE_TRY_SELECT_NTH_UNSTABLE_U64`, `SLICE_TRY_SELECT_NTH_UNSTABLE_BY_U64`, and `SLICE_TRY_SELECT_NTH_UNSTABLE_BY_KEY_U64` in `sa_std/core/slice.sa`.
  - Added `VEC_TRY_SELECT_NTH_UNSTABLE_U64`, `VEC_TRY_SELECT_NTH_UNSTABLE_BY_U64`, and `VEC_TRY_SELECT_NTH_UNSTABLE_BY_KEY_U64` in `sa_std/vec.sa` as mutable-slice wrappers.
  - The helpers expose a concrete `(ok, left_slice, pivot_ptr, right_slice)` contract, return `ok=0` for out-of-range `nth`, and currently satisfy ordering by fully sorting the concrete `u64` slice instead of modeling Rust's optimized selection algorithm or scoped borrow tuple.
  - Extended `tests/unit_framework/std_string_vec_macro_surface.sa` for slice normal/by/by_key, out-of-range failure, and Vec wrappers.
  - Verification: `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_string_vec_macro_surface.sa --jobs 1 --trace-panic` -> `36 passed; 0 failed; 0 skipped`.

- 2026-06-09: Added concrete slice/vector unstable-sort aliases.
  - Added `SLICE_SORT_UNSTABLE_U64`, `SLICE_SORT_UNSTABLE_BY_U64`, and `SLICE_SORT_UNSTABLE_BY_KEY_U64` in `sa_std/core/slice.sa`.
  - Added `VEC_SORT_UNSTABLE_U64`, `VEC_SORT_UNSTABLE_BY_U64`, and `VEC_SORT_UNSTABLE_BY_KEY_U64` in `sa_std/vec.sa`.
  - The aliases satisfy Rust's sorted-result contract for the concrete `u64` surface while reusing the current adjacent-swap implementation; cached-key, selection/nth sorting, generic comparators, and panic/drop behavior remain documented as out of scope.
  - Extended `tests/unit_framework/std_string_vec_macro_surface.sa` so every new unstable-sort macro is expanded and checked.
  - Verification: `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_string_vec_macro_surface.sa --jobs 1 --trace-panic` -> `35 passed; 0 failed; 0 skipped`.

- 2026-06-09: Added concrete slice/vector sort helpers.
  - Added `SLICE_SORT_U64`, `SLICE_SORT_BY_U64`, and `SLICE_SORT_BY_KEY_U64` in `sa_std/core/slice.sa` for in-place concrete `u64` slice sorting.
  - Added `VEC_SORT_U64`, `VEC_SORT_BY_U64`, and `VEC_SORT_BY_KEY_U64` in `sa_std/vec.sa` as mutable-slice wrappers for common Rust `Vec::sort*` lowering shapes.
  - The helpers use stable adjacent-swap ordering over current storage and keep Rust's generic sort algorithms, panic/drop behavior, and unstable-sort families documented as out of scope.
  - Extended `tests/unit_framework/std_string_vec_macro_surface.sa` for ascending slice sort, comparator-based descending sort, key sort, empty slice no-op, and Vec wrappers.
  - Verification: `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_string_vec_macro_surface.sa --jobs 1 --trace-panic` -> `34 passed; 0 failed; 0 skipped`.

- 2026-06-08: Added checked comparison clamp helpers.
  - Added `CMP_TRY_CLAMP_U64` and `CMP_TRY_CLAMP_I64` in `sa_std/cmp.sa`.
  - The helpers return explicit `(ok, value)` results, clamp valid ranges through the existing primitive clamp macros, and report invalid `min > max` ranges with `ok=0` instead of relying on Rust's panic behavior.
  - Extended `tests/unit_framework/std_cmp_macro_surface.sa` for valid clamping and invalid-range rejection across unsigned and signed primitives.
  - Updated `docs/std_missing.md` to count the concrete checked-clamp subset while keeping Rust generics, trait dispatch, and panic semantics open.
  - Verification: `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_cmp_macro_surface.sa --jobs 1 --trace-panic` -> `2 passed; 0 failed; 0 skipped`.

- 2026-06-08: Added concrete BinaryHeap mutable-peek set helper.
  - Added `BINARY_HEAP_TRY_PEEK_MUT_SET_U64` and `BINARY_HEAP_PEEK_MUT_SET_U64` in `sa_std/binary_heap.sa`.
  - The helper lowers the common `peek_mut` mutation shape for the concrete `u64` max-heap by replacing the root value, returning the previous root, and immediately restoring heap order with `sift_down`; Rust's scoped `PeekMut` guard/drop object remains documented as out of scope.
  - Extended `tests/unit_framework/std_binary_heap_macro_surface.sa` for empty-heap failure, old-root reporting, root replacement, and reheapified pop order.
  - Updated `docs/std_missing.md` to count the concrete mutable-peek set subset while keeping Rust guard lifetimes, iterators, generics, and allocator behavior open.
  - Verification: `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_binary_heap_macro_surface.sa --jobs 1 --trace-panic` -> `6 passed; 0 failed; 0 skipped`.

- 2026-06-08: Added concrete BTreeMap/BTreeSet entry-style helpers.
  - Added `BTREE_MAP_ENTRY_OR_INSERT` in `sa_std/btree_map.sa` over the existing sorted-map try-insert value-slot pointer contract.
  - Added `BTREE_SET_GET_OR_INSERT` in `sa_std/btree_set.sa`, returning `(inserted, stored_key_slice)` for the concrete ordered slice-key set.
  - Extended `tests/unit_framework/std_btree_macro_surface.sa` for new/existing map entry insertion, returned value slots, set get-or-insert behavior, sorted-map values, key views, and pointer views.
  - Updated `docs/std_missing.md` to count these concrete ordered-collection subsets while keeping Rust's full entry objects, key ownership variants, generics, lazy iterators, and borrow semantics open.
  - Verification: `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_btree_macro_surface.sa --jobs 1 --trace-panic` -> `6 passed; 0 failed; 0 skipped`.

- 2026-06-08: Added concrete HashMap/HashSet entry-style helpers.
  - Added `MAP_ENTRY_OR_INSERT` in `sa_std/hashmap.sa` as a Rust-named entry-or-insert lowering over the existing stored value-slot pointer contract.
  - Added `SET_GET_OR_INSERT` in `sa_std/hashset.sa`, returning `(inserted, stored_key)` for pointer-key sets.
  - Extended `tests/unit_framework/std_hashmap_macro_surface.sa` and `tests/unit_framework/std_hashset_macro_surface.sa` for new-key insertion, existing-key preservation, returned slot/key values, and final collection length.
  - Updated `docs/std_missing.md` to count these concrete entry-style subsets while keeping Rust's full entry objects, generics, ownership variants, and lazy iterator semantics open.
  - Verification: `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_hashmap_macro_surface.sa --jobs 1 --trace-panic` -> `5 passed; 0 failed; 0 skipped`; `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_hashset_macro_surface.sa --jobs 1 --trace-panic` -> `5 passed; 0 failed; 0 skipped`.

- 2026-06-08: Added concrete VecDeque mutating insertion pointer helpers.
  - Added `VEC_DEQUE_PUSH_BACK_MUT_PTR`, `VEC_DEQUE_PUSH_FRONT_MUT_PTR`, `VEC_DEQUE_TRY_INSERT_MUT_PTR`, and `VEC_DEQUE_INSERT_MUT_PTR` in `sa_std/vec_deque.sa`.
  - The helpers return raw pointers to the newly inserted `u64` slot for verifier-friendly lowering of Rust's `push_back_mut`, `push_front_mut`, and `insert_mut` shapes without claiming scoped borrow or generic element semantics.
  - Extended `tests/unit_framework/std_vec_deque_macro_surface.sa` to mutate the returned slots and check out-of-range insertion returns `ok=0` plus a null pointer.
  - Verification: `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_vec_deque_macro_surface.sa --jobs 1 --trace-panic` -> `5 passed; 0 failed; 0 skipped`.

- 2026-06-08: Added concrete iterator next-chunk helper coverage.
  - Added `ITER_TRY_NEXT_CHUNK_U64` in `sa_std/core/iter.sa` for caller-buffer lowering of Rust's common `Iterator::next_chunk` shape.
  - The helper reports explicit `(ok, filled)`, succeeds only when exactly the requested count is copied, treats zero-count chunks as success without consuming, and leaves Rust const-generic arrays plus `Err(IntoIter<...>)` remainder objects documented as missing.
  - Extended `tests/unit_framework/std_iter_macro_surface.sa` for full chunk, short remainder, and zero-count behavior.
  - Verification: `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_iter_macro_surface.sa --jobs 1 --trace-panic` -> `10 passed; 0 failed; 0 skipped`.

- 2026-06-08: Added checked Rust-style duration constructor helpers.
  - Added `TIME_DURATION_CHECKED_NEW` plus checked `from_secs`, `from_millis`, `from_micros`, `from_nanos`, `from_mins`, `from_hours`, `from_days`, and `from_weeks` variants in `sa_std/time.sa`.
  - The helpers report explicit `(ok, ns)` results for SA's `u64` nanosecond representation and leave existing direct constructors unchanged for compatibility.
  - Updated `docs/std_missing.md` to count this concrete time subset while keeping Rust's typed `Duration`, `u128`, float/signed conversion, panic, and platform clock semantics open.
  - Verification: `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_time_macro_surface.sa --jobs 1 --trace-panic` -> `2 passed; 0 failed; 0 skipped`.

- 2026-06-08: Added Rust-style fallible array generation and mapping helpers.
  - Added `ARRAY_TRY_FROM_FN_U64` and `ARRAY_TRY_MAP_U64` in `sa_std/array.sa` for concrete `u64` lowering of fallible `std::array` construction/map shapes.
  - The helpers use callback-written output slots, stop at the first `ok=0`, and report a bool-style status while preserving already written elements.
  - Updated `docs/std_missing.md` to count this concrete array subset while keeping Rust const generics, generic `Try` residuals, cleanup/drop semantics, references, and iterator gaps open.
  - Verification: `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_array_macro_surface.sa --jobs 1 --trace-panic` -> `1 passed; 0 failed; 0 skipped`.

- 2026-06-08: Added Rust-style signed integer and NonZero `unsigned_abs` helpers.
  - Added `NUM_I8_UNSIGNED_ABS`, `NUM_I16_UNSIGNED_ABS`, `NUM_I32_UNSIGNED_ABS`, `NUM_I64_UNSIGNED_ABS`, and `NUM_ISIZE_UNSIGNED_ABS` in `sa_std/num.sa`.
  - Added `NONZERO_I8_UNSIGNED_ABS`, `NONZERO_I16_UNSIGNED_ABS`, `NONZERO_I32_UNSIGNED_ABS`, `NONZERO_I64_UNSIGNED_ABS`, and `NONZERO_ISIZE_UNSIGNED_ABS`, storing into the matching unsigned `NonZero` layouts.
  - The helpers preserve Rust's signed-minimum behavior by returning the unsigned magnitude bit pattern instead of failing or saturating.
  - Updated `docs/std_missing.md` to count this concrete primitive and NonZero numeric subset while keeping Rust trait, niche, conversion, parser, float, and `u128`/`i128` gaps open.
  - Verification: `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_num_macro_surface.sa --jobs 1 --trace-panic` -> `17 passed; 0 failed; 0 skipped`.

- 2026-06-08: Added signed NonZero checked and saturating neg numeric helpers.
  - Added `NONZERO_I8_CHECKED_NEG`, `NONZERO_I16_CHECKED_NEG`, `NONZERO_I32_CHECKED_NEG`, `NONZERO_I64_CHECKED_NEG`, and `NONZERO_ISIZE_CHECKED_NEG` in `sa_std/num.sa`.
  - Added matching `NONZERO_I8_SATURATING_NEG`, `NONZERO_I16_SATURATING_NEG`, `NONZERO_I32_SATURATING_NEG`, `NONZERO_I64_SATURATING_NEG`, and `NONZERO_ISIZE_SATURATING_NEG` helpers.
  - The checked helpers preserve the NonZero invariant and report primitive `MIN` negation overflow through `ok=0`; the saturating helpers store the corresponding max value for `MIN` inputs.
  - Updated `docs/std_missing.md` to count this concrete Rust-like signed NonZero unary subset while leaving Rust trait, niche, conversion, parser, float, and `u128`/`i128` gaps open.
  - Verification: `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_num_macro_surface.sa --jobs 1 --trace-panic` -> `16 passed; 0 failed; 0 skipped`.

- 2026-06-08: Added checked division/remainder numeric std coverage for narrow unsigned and NonZero primitives.
  - Added `NUM_U8_CHECKED_DIV`, `NUM_U16_CHECKED_DIV`, `NUM_U32_CHECKED_DIV`, `NUM_U8_CHECKED_REM`, `NUM_U16_CHECKED_REM`, and `NUM_U32_CHECKED_REM` in `sa_std/num.sa`.
  - Added `NONZERO_{U,I}{8,16,32,64}_CHECKED_DIV`, `NONZERO_{U,I}{8,16,32,64}_CHECKED_REM`, and the matching `NONZERO_{U,ISIZE}_CHECKED_DIV` / `CHECKED_REM` aliases.
  - The `NonZero` helpers preserve the invariant by returning `ok=0` when arithmetic fails or the computed result is zero, matching the existing checked add/sub/mul storage pattern.
  - Updated `docs/std_missing.md` so this concrete Rust-like numeric subset is counted while keeping Rust trait, niche, conversion, parser, float, and `u128`/`i128` gaps open.
  - Verification: `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_num_macro_surface.sa --jobs 1 --trace-panic` -> `15 passed; 0 failed; 0 skipped`.

- 2026-06-08: Added concrete iterator rev/take_while/skip_while Vec helpers.
  - Added `ITER_REV_COLLECT_U64`, `ITER_TAKE_WHILE_COLLECT_U64`, and `ITER_SKIP_WHILE_COLLECT_U64` in `sa_std/core/iter.sa` for concrete `u64` cursors.
  - The helpers materialize caller-owned `Vec<u64>` results for common Rust `rev`, `take_while`, and `skip_while` collect lowering without claiming lazy adapter or generic trait parity.
  - Updated `docs/std_missing.md` to count these concrete eager subsets while keeping Rust generic `Item`, lazy adapters, generic `collect`, and trait wiring open.
  - Verification: `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_iter_macro_surface.sa --jobs 1 --trace-panic` -> `10 passed; 0 failed; 0 skipped`.

- 2026-06-08: Added concrete iterator enumerate/zip/chain Vec helpers.
  - Added `ITER_ENUMERATE_COLLECT_U64`, `ITER_ZIP_COLLECT_U64`, and `ITER_CHAIN_COLLECT_U64` in `sa_std/core/iter.sa` for concrete `u64` cursors.
  - The pair-producing helpers materialize interleaved `Vec<u64>` fields instead of pretending to expose Rust tuple values or lazy adapter objects.
  - Updated `docs/std_missing.md` to count these concrete eager lowering subsets while keeping Rust tuple types, generic `Item`, lazy adapters, generic `collect`, and trait wiring open.
  - Verification: `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_iter_macro_surface.sa --jobs 1 --trace-panic` -> `9 passed; 0 failed; 0 skipped`.

- 2026-06-08: Added concrete iterator collect/take/skip Vec helpers.
  - Added `ITER_COLLECT_U64`, `ITER_TAKE_COLLECT_U64`, and `ITER_SKIP_COLLECT_U64` in `sa_std/core/iter.sa` for concrete `u64` slice cursors.
  - The helpers materialize caller-owned `Vec<u64>` outputs for practical `collect::<Vec<_>>()`, `take(n).collect::<Vec<_>>()`, and `skip(n).collect::<Vec<_>>()` lowering.
  - Updated `docs/std_missing.md` to count the concrete eager Vec subsets while keeping Rust lazy adapters, generic `Item`, generic `collect`, and trait wiring open.
  - Verification: `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_iter_macro_surface.sa --jobs 1 --trace-panic` -> `8 passed; 0 failed; 0 skipped`.

- 2026-06-08: Added eager iterator map/filter/partition collect helpers.
  - Added `ITER_MAP_COLLECT_U64`, `ITER_FILTER_COLLECT_U64`, and `ITER_PARTITION_U64` in `sa_std/core/iter.sa` for concrete `u64` slice cursors.
  - The helpers consume the cursor and materialize caller-owned `Vec<u64>` results, matching practical `map(...).collect::<Vec<_>>()`, `filter(...).collect::<Vec<_>>()`, and `partition` lowering shapes.
  - Updated `docs/std_missing.md` to count these concrete eager collect subsets while keeping Rust lazy adapter identity, generic `Item`, generic `collect`, and trait wiring open.
  - Verification: `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_iter_macro_surface.sa --jobs 1 --trace-panic` -> `7 passed; 0 failed; 0 skipped`.

- 2026-06-08: Added concrete iterator find_map and filter_map collect helpers.
  - Added `ITER_FIND_MAP_U64` and `ITER_FILTER_MAP_COLLECT_U64` in `sa_std/core/iter.sa` for concrete `u64` slice cursors.
  - The map callback writes through an output slot and returns an explicit has-value flag, avoiding sentinel ambiguity.
  - `ITER_FILTER_MAP_COLLECT_U64` materializes mapped values into a new `Vec<u64>` rather than pretending to be Rust's lazy `FilterMap` adapter or generic `collect`.
  - Updated `docs/std_missing.md` to count the concrete `find_map` / materialized `filter_map` subset while keeping lazy adapters, generic `Item`, and trait wiring open.
  - Verification: `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_iter_macro_surface.sa --jobs 1 --trace-panic` -> `6 passed; 0 failed; 0 skipped`.

- 2026-06-08: Added Rust-style iterator try adaptor helper subset.
  - Added `ITER_TRY_FOLD_U64` and `ITER_TRY_FOR_EACH_U64` in `sa_std/core/iter.sa` for concrete `u64` slice cursors.
  - `ITER_TRY_FOLD_U64` uses a callback with an output accumulator slot and explicit continue/fail status, avoiding sentinel ambiguity while keeping Rust's generic `Try` trait and residual conversions documented as missing.
  - Updated `docs/std_missing.md` to count the concrete try adaptor subset while leaving lazy adapters, generic items, `collect`, `find_map`, and full trait wiring open.
  - Added SA unit coverage in `tests/unit_framework/std_iter_macro_surface.sa` for all-success, early-stop, empty iterator, accumulator preservation, and remaining-length behavior.
  - Verification: `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_iter_macro_surface.sa --jobs 1 --trace-panic` -> `5 passed; 0 failed; 0 skipped`.

- 2026-06-08: Added Rust-style ASCII slice view helper subset.
  - Added `ASCII_SLICE_IS_ASCII`, `ASCII_SLICE_AS_ASCII`, `ASCII_SLICE_AS_ASCII_UNCHECKED`, and `ASCII_SLICE_AS_ASCII_MUT` in `sa_std/core/ascii.sa`.
  - The checked helpers return explicit `(ok, Slice)` transparent views instead of claiming Rust's full typed `&[ascii::Char]` / `&mut [ascii::Char]` reference semantics.
  - Updated `docs/std_missing.md` so the transparent slice-view subset is counted while true typed references, trait impls, and iterator objects remain open.
  - Added SA unit coverage in `tests/unit_framework/std_ascii_macro_surface.sa` for ASCII/non-ASCII validation, checked failure empty view, unchecked view preservation, and mutable checked view behavior.
  - Verification: `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_ascii_macro_surface.sa --jobs 1 --trace-panic` -> `6 passed; 0 failed; 0 skipped`.

- 2026-06-08: Expanded concrete owned `CString` with-NUL construction and view helpers.
  - Added `CSTRING_FROM_BYTES_WITH_NUL`, `CSTRING_FROM_BYTES_WITH_NUL_UNCHECKED`, `CSTRING_AS_PTR`, `CSTRING_COUNT_BYTES`, and `CSTRING_IS_EMPTY` in `sa_std/ffi.sa`.
  - The checked with-NUL constructor reuses `CSTR_FROM_BYTES_WITH_NUL` validation, copies the accepted bytes into owned storage, and leaves Rust error-object parity documented as missing.
  - Updated `docs/std_missing.md` to document the broader concrete `CString` subset while keeping `OsString`, platform strings, trait impls, and Rust drop/error semantics open.
  - Extended SA unit coverage in `tests/unit_framework/std_ffi_cstr_macro_surface.sa` for checked/unchecked with-NUL construction, missing/interior NUL failures, pointer view, count, and empty checks.
  - Verification: `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_ffi_cstr_macro_surface.sa --jobs 1 --trace-panic` -> `2 passed; 0 failed; 0 skipped`.

- 2026-06-08: Added concrete owned `CString` FFI helper coverage.
  - Added `CString` layout constants and `CSTRING_NEW`, `CSTRING_AS_CSTR`, `CSTRING_AS_BYTES`, `CSTRING_AS_BYTES_WITH_NUL`, `CSTRING_INTO_RAW`, `CSTRING_FROM_RAW`, and `CSTRING_FREE` in `sa_std/ffi.*`.
  - `CSTRING_NEW` rejects interior NUL bytes and appends one trailing NUL on success, matching the common Rust `CString::new` shape while keeping error objects and trait/drop semantics documented as missing.
  - Updated `docs/std_missing.md` so owned `CString` is no longer counted as wholly missing; `OsString`, platform strings, allocator-aware APIs, and Rust error object parity remain open.
  - Added SA unit coverage in `tests/unit_framework/std_ffi_cstr_macro_surface.sa` for success, empty string, interior NUL rejection, borrowed views, and `into_raw`/`from_raw` roundtrip.
  - Verification: `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_ffi_cstr_macro_surface.sa --jobs 1 --trace-panic` -> `2 passed; 0 failed; 0 skipped`.

- 2026-06-08: Added Rust-style `AtomicPtr` pointer arithmetic fetch helpers.
  - Added `ATOMIC_PTR_FETCH_BYTE_ADD`, `ATOMIC_PTR_FETCH_BYTE_SUB`, `ATOMIC_PTR_FETCH_U64_ADD`, and `ATOMIC_PTR_FETCH_U64_SUB` to `sa_std/sync/atomic.sa`.
  - Implemented the helpers with load/cmpxchg retry loops and concrete SA pointer offsets; `FETCH_U64_*` uses SA's 8-byte element layout rather than pretending to model Rust generics.
  - Updated `docs/std_missing.md` so `AtomicPtr` pointer arithmetic helpers are no longer counted as a sync gap; Rust provenance and `from_ptr` semantics remain missing.
  - Added SA unit coverage in `tests/unit_framework/std_atomic_macro_surface.sa` for byte and 8-byte element add/sub old-value and final-pointer behavior.
  - Verification: `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_atomic_macro_surface.sa --jobs 1 --trace-panic` -> `5 passed; 0 failed; 0 skipped`.

- 2026-06-08: Added Rust-style `AtomicPtr::swap` compiler-std coverage.
  - Added `ATOMIC_PTR_SWAP` to `sa_std/sync/atomic.sa` using a load/cmpxchg retry loop, because the current LLVM-C backend does not accept pointer-typed `atomicrmw xchg`.
  - Updated `docs/std_missing.md` so `AtomicPtr::swap` is no longer counted as a sync gap; pointer arithmetic helpers and Rust's full provenance model remain documented as missing.
  - Added SA unit coverage in `tests/unit_framework/std_atomic_macro_surface.sa` for old-pointer return and final pointer state.
  - Verification: `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_atomic_macro_surface.sa --jobs 1 --trace-panic` -> `5 passed; 0 failed; 0 skipped`.

- 2026-06-08: Improved unit-framework test parallelism and bottleneck diagnostics.
  - `tests/unit_framework/runner.zig` now uses `SA_TEST_JOBS`, `SA_ZIG_JOBS`, `ZIG_BUILD_JOBS`, or `auto` instead of hard-coding every `sa test` run to `--jobs 1`.
  - Added per-SA-suite elapsed time logging for the native unit framework runner.
  - Kept `std_fs_macro_surface.sa` serial because parallel execution exposed filesystem state races in the file IO tests.
  - `tools/pre_push_timed.sh` now exports `SA_TEST_JOBS` from the detected worker count and prints it next to the Zig job count.
  - Added `SA_PRE_PUSH_PROFILE=full|fast|legacy`; default `full` uses the new `whitepaper-lint` step instead of `smoke` to avoid rerunning std smoke artifacts, while `legacy` preserves the old duplicate stage list for comparison.
  - Saved bottleneck findings in `docs/test_performance.md`.
  - Verification: `SA_TEST_JOBS=auto zig build unit-framework --summary all` -> `4/4 tests passed`, run step about `3m`; `tools/pre_push_timed.sh whitepaper-lint cli-skills-smoke` -> both stages passed in `1.456s`.

- 2026-06-08: Added Rust-style `std::path` optional prefix and borrowed UTF-8 view helpers.
  - Added `PATH_TRY_FILE_PREFIX`, returning `ok=1` with the Rust-style first-dot file prefix when a file name is present, or `ok=0` and an empty slice for root/empty paths.
  - Added `PATH_TRY_TO_STR`, returning `ok=1` and a borrowed `Slice` view when path bytes are valid UTF-8, or `ok=0` and an empty slice for invalid UTF-8.
  - Reused the existing compiler-std UTF-8 runtime ABI through `string.sa`; no plugin APIs or platform `OsStr` model were introduced.
  - Updated `docs/std_missing.md` path coverage notes while keeping owned `PathBuf`, Windows prefixes, and platform-specific `OsStr` semantics documented as missing.
  - Added SA unit coverage in `tests/unit_framework/std_path_macro_surface.sa` for file-prefix option behavior plus valid, empty, and invalid UTF-8 path bytes.
  - Verification: `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_path_macro_surface.sa --jobs 1 --trace-panic` -> `4 passed; 0 failed; 0 skipped`.

- 2026-06-08: Added Rust-style string byte/UTF-8 scalar view helpers to compiler std.
  - Added `STR_BYTE_LEN` / `STRING_BYTE_LEN`, `STR_TRY_BYTE_AT` / `STRING_TRY_BYTE_AT`, `STR_CHAR_COUNT` / `STRING_CHAR_COUNT`, `STR_TRY_CHAR_AT` / `STRING_TRY_CHAR_AT`, and `STR_TRY_CHAR_RANGE_AT` / `STRING_TRY_CHAR_RANGE_AT`.
  - Backed UTF-8 scalar count/nth/range helpers with compiler runtime ABI instead of plugin APIs, keeping Deno/http/plugin-specific surfaces out of `sa_std`.
  - Updated `docs/std_missing.md` to count the new byte/scalar view helpers while still marking Rust lazy iterator objects, traits, grapheme handling, and full pattern APIs as missing.
  - Added SA unit coverage in `tests/unit_framework/std_string_vec_macro_surface.sa`; full verification is pending below in this run.

- 2026-06-08: Added Rust-style `std::io::Read` read-to-end buffer helpers for concrete SA cursors.
  - Added `IO_CURSOR_REMAINING_SLICE`, `IO_CURSOR_READ_TO_END`, and `IO_TAKE_READ_TO_END` to `sa_std/io.sa` without introducing runtime ABI or plugin dependencies.
  - The helpers expose the unread cursor tail as a borrowed view or copy it into caller-provided storage, advancing cursor/take state while staying explicit about capacity limits.
  - Updated `docs/std_missing.md` so `read_to_end` is no longer counted as fully missing, while Rust trait dispatch, Vec allocation/append, and UTF-8 `read_to_string` behavior remain documented gaps.
  - Added SA unit coverage in `tests/unit_framework/std_io_utility_macro_surface.sa`; focused verification is pending below in this run.

- 2026-06-08: Added UTF-8 validation for Rust-style string and FFI C string borrowed views.
  - Added runtime ABI `sa_str_utf8_validate` and string macros `STR_IS_UTF8` / `STRING_IS_UTF8`.
  - Added `CSTR_TO_STR`, returning a borrowed slice without the trailing NUL when UTF-8 validation succeeds, or `CSTR_TO_STR_INVALID_UTF8` plus an empty slice on invalid UTF-8.
  - Kept owned `CString`, `OsString`, lossy conversion, and Rust error-object semantics documented as missing rather than faking them in compiler std.
  - Added focused SA unit coverage in the string UTF-8 view test and FFI CStr borrowed view test.

- 2026-06-08: Added Rust-style `std::io::Read::read_to_string` buffer helpers for concrete SA cursors.
  - Added `IO_CURSOR_READ_TO_STRING` and `IO_TAKE_READ_TO_STRING`, reusing `sa_str_utf8_validate` to report invalid UTF-8 as `SA_IO_ERR_INVALID_DATA`.
  - Added `IO_ERROR_KIND_INVALID_DATA` mapping so UTF-8 data errors no longer collapse to generic `Other`.
  - Kept Rust trait dispatch and allocation-appending `String` behavior documented as missing; the SA helpers write into caller-provided storage and return borrowed `IoSlice` views.
  - Extended `std_io_utility_macro_surface.sa` coverage for valid UTF-8, invalid UTF-8, take limits, and error-kind mapping.

# SA DB Progress

Scope: `/home/vscode/projects/sa_plugins/sa_plugin_db` against `docs/database.md` / v0.6 DB goals.

Current progress: 90%

## Completed DB Features

- 2026-06-08: Treated missing registered qmod payloads as query-payload corruption.
  - `execQuery()` now maps a missing `.sa/db/qmods/<hash>.qmod` file to `ExecError.QueryPayloadCorrupted` instead of surfacing a generic file/path failure.
  - This closes the remaining gap in the qmod payload integrity boundary: both tampered payload bytes and deleted payload files now produce the same stable corruption diagnostic.
  - Reused the existing CLI payload-corruption diagnostic: `error[SA-DB-CLI]: DB query payload is corrupted` with a restore/re-register hint.
  - Added qmod coverage: `qmod exec rejects missing query payload`.
  - Verification: `/home/vscode/projects/sa_plugins/sa_plugin_db` `zig build test --summary all` -> `57/57 tests passed`; `zig build` passed; `SA_PLUGIN_DEV=1 sa plugin install --dev /home/vscode/projects/sa_plugins/sa_plugin_db` passed; real CLI deleting `.sa/db/qmods/<hash>.qmod` made `sa db exec <hash>` exit `1` with `DB query payload is corrupted`.

- 2026-06-08: Split corrupted table snapshot metadata from generic DB format failures.
  - Read and write qmod table loaders now treat malformed `simple.meta` JSON, bad table metadata magic/version, and table-name identity mismatches as `ExecError.SnapshotCorrupted` instead of collapsing them into generic `InvalidFormat`.
  - This extends the existing snapshot-corruption boundary from damaged segment files to damaged snapshot metadata headers, so qmod exec no longer misreports broken table metadata as a schema-format issue.
  - Reused the existing CLI corruption diagnostic: `error[SA-DB-CLI]: DB snapshot is corrupted` with verify/restore/rebuild guidance.
  - Added qmod coverage: `qmod exec rejects corrupted table snapshot metadata` and `qmod write rejects corrupted table snapshot metadata`.
  - Verification: `/home/vscode/projects/sa_plugins/sa_plugin_db` `zig build test --summary all` -> `56/56 tests passed`; `zig build` passed; `SA_PLUGIN_DEV=1 sa plugin install --dev /home/vscode/projects/sa_plugins/sa_plugin_db` passed; real CLI tamper test replacing `simple.meta` with malformed JSON made both read and write `sa db exec <hash>` paths exit `1` with `DB snapshot is corrupted`.

- 2026-06-08: Split corrupted qmod payloads from generic DB format failures.
  - Added `ExecError.QueryPayloadCorrupted` so tampered `.sa/db/qmods/<hash>.qmod` files no longer collapse into generic `InvalidFormat` during `sa db exec <hash>`.
  - `execQuery()` now treats a SHA-256 mismatch between the requested registered hash and the on-disk qmod payload as dedicated query-payload corruption.
  - Plugin CLI now reports `error[SA-DB-CLI]: DB query payload is corrupted` with a direct restore/re-register hint.
  - Added qmod coverage: `qmod exec rejects corrupted query payload`; added wrapper coverage: `db plugin wrapper renders corrupted query payload diagnostic`.
  - Verification: `/home/vscode/projects/sa_plugins/sa_plugin_db` `zig build test --summary all` -> `54/54 tests passed`; `zig build` passed; `SA_PLUGIN_DEV=1 sa plugin install --dev /home/vscode/projects/sa_plugins/sa_plugin_db` passed; real CLI tamper test overwriting `.sa/db/qmods/<hash>.qmod` made `sa db exec <hash>` exit `1` with `DB query payload is corrupted`.

- 2026-06-08: Hardened qmod registry metadata against hash-redirection tampering.
  - Added `ExecError.QueryRegistryCorrupted` so corrupted `.sa/db/qmods/<hash>.meta.json` entries no longer collapse into generic format failures.
  - `loadMeta()` now verifies registry self-consistency: the requested `<hash>` must match the metadata `hash`, the recorded `qmod_path` must match `.sa/db/qmods/<hash>.qmod`, `grants` must equal `grant_entries.len`, and `main` must be non-empty.
  - This closes a real integrity hole where replacing `<A>.meta.json` with `<B>.meta.json` could redirect `sa db exec <A>` or `sa db inspect <A>` toward another registered qmod.
  - Plugin CLI now reports `error[SA-DB-CLI]: DB query registry metadata is corrupted` with a direct repair/re-register hint.
  - Added qmod coverage: `qmod inspect rejects corrupted registry metadata` and `qmod exec rejects corrupted registry metadata`; added wrapper coverage: `db plugin wrapper renders corrupted registry metadata diagnostic`.
  - Verification: `/home/vscode/projects/sa_plugins/sa_plugin_db` `zig build test --summary all` -> `52/52 tests passed`; `zig build` passed; `SA_PLUGIN_DEV=1 sa plugin install --dev /home/vscode/projects/sa_plugins/sa_plugin_db` passed; real CLI tamper test replacing `<first_hash>.meta.json` with `<second_hash>.meta.json` made both `sa db inspect <first_hash>` and `sa db exec <first_hash>` exit `1` with `DB query registry metadata is corrupted`.

- 2026-06-08: Split malformed DB query hashes from unknown registered hashes.
  - Added `ExecError.InvalidQueryHash` so malformed `sa db exec <hash>` and qmod registry lookups no longer collapse into generic format failures.
  - `parseHashHex()` now rejects non-64-byte or non-hex hash text with the dedicated error, while valid-but-missing 64-hex hashes still return `QueryHashUnknown`.
  - Plugin CLI now reports `error[SA-DB-CLI]: invalid DB query hash` with a direct `64-character hexadecimal` hint.
  - `sa db inspect` now treats 64-character non-hex text as a malformed hash instead of falling through to table lookup.
  - Added qmod coverage: `qmod exec rejects malformed query hash text`, `qmod inspect rejects malformed query hash text`, and `qmod exec distinguishes unknown query hash from malformed hash`; added wrapper coverage: `db plugin wrapper renders invalid query hash diagnostic` and `db inspect rejects malformed 64-byte hash text before table lookup`.
  - Verification: `/home/vscode/projects/sa_plugins/sa_plugin_db` `zig build test --summary all` -> `49/49 tests passed`; `zig build` passed; `SA_PLUGIN_DEV=1 sa plugin install --dev /home/vscode/projects/sa_plugins/sa_plugin_db` passed; real CLI `sa db exec not-a-hash` exited `1` with `invalid DB query hash`, valid unknown 64-hex exited `1` with `DB query hash is unknown`, and `sa db inspect <64-char non-hex>` exited `1` with `invalid DB query hash`.

- 2026-06-08: Split corrupted snapshot segments from generic DB format failures.
  - Added `ExecError.SnapshotCorrupted` for qmod execution paths where segment file counts, byte lengths, or SHA-256 hashes no longer match table metadata.
  - Read and write table loaders now surface corrupted table segments through this dedicated runtime error instead of collapsing them into `InvalidFormat`.
  - Plugin CLI now reports `error[SA-DB-CLI]: DB snapshot is corrupted` with a direct verify/restore/rebuild hint.
  - Added wrapper coverage: `db plugin wrapper renders snapshot corrupted diagnostic`, plus qmod coverage: `qmod exec rejects corrupted table snapshot segment`.
  - Verification: `/home/vscode/projects/sa_plugins/sa_plugin_db` `zig build test --summary all` -> `44/44 tests passed`; `zig build` passed; `SA_PLUGIN_DEV=1 sa plugin install --dev /home/vscode/projects/sa_plugins/sa_plugin_db` passed; real CLI `sa db exec <hash>` after segment corruption exited `1` with `DB snapshot is corrupted`.

- 2026-06-08: Restricted `db_atomic_cursor` to `u64` columns with explicit type diagnostics.
  - Atomic cursor registration now rejects base or named cursor bindings unless the target DB column is exactly `u64` with 8-byte stride.
  - Added `ExecError.ColumnTypeMismatch` so atomic type failures no longer collapse into generic capability or format errors.
  - Plugin CLI now reports `error[SA-DB-CLI]: DB column type mismatch` with a direct `u64` column hint.
  - Added unit coverage for non-`u64` base and named atomic cursor bindings, plus wrapper coverage for the new diagnostic.
  - Verification: `/home/vscode/projects/sa_plugins/sa_plugin_db` `zig build test --summary all` -> `42/42 tests passed`; `zig build` passed; `SA_PLUGIN_DEV=1 sa plugin install --dev /home/vscode/projects/sa_plugins/sa_plugin_db` passed; real CLI `sa db register atomic_u32_base.query.sa` exited `1` with `DB column type mismatch`.

- 2026-06-08: Restricted `db_atomic_cursor` qmods to the single documented cursor slot.
  - Registration-time atomic validation now requires every `atomic_rmw_*` cursor address to use an explicit `+0` offset; nonzero constants and dynamic offset expressions are rejected as `DbCapabilityEscalation`.
  - Runtime atomic execution also defends this boundary and refuses any nonzero resolved cursor offset.
  - This aligns the implementation with the design doc's single `global_len` cursor model instead of allowing arbitrary byte offsets over the bound column.
  - Added unit coverage: `qmod register rejects atomic cursor nonzero offset` and `qmod register rejects atomic cursor dynamic offset expression`.
  - Verification: `/home/vscode/projects/sa_plugins/sa_plugin_db` `zig build test --summary all` -> `39/39 tests passed`; `zig build` passed; `SA_PLUGIN_DEV=1 sa plugin install --dev /home/vscode/projects/sa_plugins/sa_plugin_db` passed; real CLI `sa db register atomic_offset.query.sa` exited `1` with `DB query capability escalation`.

- 2026-06-08: Split schema-hash drift from generic DB format failures.
  - Added `ExecError.SchemaMismatch` for cases where the current table schema hash no longer matches the hash recorded in table metadata.
  - Read and write qmod table loaders now surface schema drift through this dedicated error instead of collapsing it into `InvalidFormat`.
  - Plugin CLI now reports `error[SA-DB-CLI]: DB schema hash mismatch` with a direct restore/refresh hint.
  - Added wrapper coverage: `db plugin wrapper renders schema mismatch diagnostic`, and updated qmod schema-drift coverage to expect the dedicated error.
  - Verification: `/home/vscode/projects/sa_plugins/sa_plugin_db` `zig build test --summary all` -> `37/37 tests passed`; `zig build` passed; `SA_PLUGIN_DEV=1 sa plugin install --dev /home/vscode/projects/sa_plugins/sa_plugin_db` passed; real CLI `sa db exec <hash>` after schema mutation exited `1` with `DB schema hash mismatch`.

- 2026-06-08: Tightened Referee DB grant binding to the actual entrypoint signature.
  - Registration-time read/write/atomic pointer validation now binds only to the effective qmod entrypoint, preferring explicit `@main` over helper functions.
  - Helper signatures can no longer smuggle `&col_*` or `&cursor*` pointers that satisfy grant checks while the real entrypoint omits them.
  - DB pointer params in the entrypoint must now be declared as `ptr`, or registration fails with `DbCapabilityEscalation`.
  - Fixed a related entrypoint bug in `findMainName()`: when `@main` exists later in the file, helper order no longer changes the registered/executed entrypoint.
  - Added unit coverage: `qmod register rejects load pointer smuggled through helper signature`, `qmod register rejects DB column pointer declared with non-ptr type`, and `qmod register rejects atomic cursor smuggled through helper signature`.
  - Verification: `/home/vscode/projects/sa_plugins/sa_plugin_db` `zig build test --summary all` -> `36/36 tests passed`; `zig build` passed; `SA_PLUGIN_DEV=1 sa plugin install --dev /home/vscode/projects/sa_plugins/sa_plugin_db` passed; real CLI `sa db register helper_pointer.query.sa` exited `1` with `DB query capability escalation`.

- 2026-06-08: Added duplicate-register guard for qmod registry metadata.
  - Re-registering the same qmod hash is now only allowed when the existing registry entry is fully identical, including source path, qmod path, imports, grants, entrypoint, and stored qmod bytes.
  - Reusing the same SHA-256 from a different source path or different registry metadata now fails with `ExecError.DuplicateRegister`, which aligns the registry with zero-trust hash locking instead of silently rewriting metadata.
  - Added unit coverage: `qmod register rejects duplicate hash from different source path` and `db plugin wrapper renders duplicate register diagnostic`.
  - Verification: `/home/vscode/projects/sa_plugins/sa_plugin_db` `zig build test --summary all` -> `33/33 tests passed`; `zig build` passed; `SA_PLUGIN_DEV=1 sa plugin install --dev /home/vscode/projects/sa_plugins/sa_plugin_db` passed; real CLI `sa db register first.query.sa` remained idempotent while `sa db register second.query.sa` exited `1` with `DB query hash is already registered with different metadata`.

- 2026-06-08: Split qmod params-layout failures from schema-format failures.
  - Added `ExecError.InvalidParams` so malformed or overlong `params.bin` payloads no longer collapse into the generic schema-format path.
  - Plugin CLI now reports `error[SA-DB-CLI]: invalid DB params format` with a direct `params.bin` layout/byte-length hint.
  - Added wrapper coverage: `db plugin wrapper renders invalid exec params diagnostic`.
  - Verification: `/home/vscode/projects/sa_plugins/sa_plugin_db` `zig build test --summary all` -> `31/31 tests passed`; `zig build` passed; `SA_PLUGIN_DEV=1 sa plugin install --dev /home/vscode/projects/sa_plugins/sa_plugin_db` passed; real CLI scalar and DB qmods both exited `1` with `invalid DB params format`.

- 2026-06-08: Enforced exact `params.bin` consumption for qmod execution.
  - Scalar qmods now require `params.bin` length to be exactly `param_count * 8`, instead of accepting trailing bytes.
  - DB qmods now consume params through a shared cursor and reject any trailing bytes across read, write, read-write, and atomic execution paths.
  - This closes a hidden layout ambiguity where concatenated or stale params could be silently ignored during qmod execution.
  - Added unit coverage: `qmod exec rejects trailing scalar params bytes` and `qmod exec rejects trailing DB params bytes`.
  - Verification: `/home/vscode/projects/sa_plugins/sa_plugin_db` `zig build test --summary all` -> `30/30 tests passed`; `zig build` passed; `SA_PLUGIN_DEV=1 sa plugin install --dev /home/vscode/projects/sa_plugins/sa_plugin_db` passed; real CLI scalar and DB qmods both rejected extra param bytes with exit code `1`.

- 2026-06-08: Added stale-metadata guard for qmod write commits.
  - Dirty qmod writes now re-read `<table>.meta` before writing segment files and committing metadata.
  - The guard verifies the loaded metadata is still current across epoch, row count, schema hash, lock state, columns, segments, and segment file hashes/byte sizes.
  - If another operation changed metadata after qmod execution loaded the table, commit returns `ExecError.StaleMetadata` before writing dirty segment files, avoiding stale hash/epoch overwrite.
  - Added unit coverage: `qmod write commit rejects stale table metadata`, which loads a writable table, mutates its pending buffer, ingests another segment to advance metadata, then confirms stale commit is rejected and original data remains intact.
  - Verification: `/home/vscode/projects/sa_plugins/sa_plugin_db` `zig build test --summary all` -> `28/28 tests passed`; `zig build` passed; `SA_PLUGIN_DEV=1 sa plugin install --dev /home/vscode/projects/sa_plugins/sa_plugin_db` passed; real CLI write regression returned `result_u64: 9`, `sa db verify simple` passed with `epoch: 2`, and follow-up read qmod returned `result_u64: 10`.

- 2026-06-08: Added explicit locked-table diagnostics for qmod write paths.
  - Write-capable qmod execution now returns `ExecError.Locked` when the target table metadata is locked, instead of falling back to `UnsupportedOperation`.
  - Plugin CLI maps the qmod lock error to `error[SA-DB-CLI]: DB table is locked` with the existing lock recovery hint.
  - Added unit coverage: `qmod exec rejects writes against locked tables`, covering both `db_write` and `db_atomic_cursor` qmods against a locked table.
  - Verification: `/home/vscode/projects/sa_plugins/sa_plugin_db` `zig build test --summary all` -> `27/27 tests passed`; `zig build` passed; `SA_PLUGIN_DEV=1 sa plugin install --dev /home/vscode/projects/sa_plugins/sa_plugin_db` passed; real CLI `SA_PLUGIN_DEV=1 sa db lock simple` followed by write qmod and atomic qmod exec both exited `1` with `DB table is locked`.

- 2026-06-08: Added explicit atomic cursor column binding.
  - `&cursor` remains supported as a compatibility binding to the authorized table's first column.
  - `&cursor_<column>` now requires `<column>` to exist in the authorized table schema at registration time and binds to that exact column at execution time.
  - Added unit coverage: `qmod exec atomic cursor targets named DB column`, which updates only `score` via `&cursor_score`, keeps `id=5`, changes `score` from `7` to `12`, and reads `id + score == 17`.
  - Verification: `/home/vscode/projects/sa_plugins/sa_plugin_db` `zig build test --summary all` -> `26/26 tests passed`; `zig build` passed; `SA_PLUGIN_DEV=1 sa plugin install --dev /home/vscode/projects/sa_plugins/sa_plugin_db` passed; real CLI `SA_PLUGIN_DEV=1 sa db exec <atomic_score_hash>` returned `result_u64: 7`, `SA_PLUGIN_DEV=1 sa db verify simple` passed with `epoch: 2`, and follow-up read qmod returned `result_u64: 17`.

- 2026-06-08: Added a narrow `db_atomic_cursor` qmod execution path.
  - Qmods with `db_atomic_cursor:<table>` can now execute `atomic_rmw_add cursor+offset, delta` over the authorized table's first column.
  - The operation returns the old value, writes back old plus delta, commits dirty segment bytes, recomputes SHA-256 metadata, and increments the table `epoch`.
  - Register-time cursor checks remain active: atomic bases must come from declared `&cursor: ptr` or `&cursor_<table>: ptr` parameters.
  - Added unit coverage: `qmod exec atomic cursor add updates u64 DB column`, which starts from `id=5`, returns old value `5`, verifies the table, then reads back `8`.
  - Verification: `/home/vscode/projects/sa_plugins/sa_plugin_db` `zig build test --summary all` -> `25/25 tests passed`; `zig build` passed; `SA_PLUGIN_DEV=1 sa plugin install --dev /home/vscode/projects/sa_plugins/sa_plugin_db` passed; real CLI `SA_PLUGIN_DEV=1 sa db exec <atomic_hash>` returned `result_u64: 5`, `SA_PLUGIN_DEV=1 sa db verify simple` passed with `epoch: 2`, and follow-up read qmod returned `result_u64: 8`.

- 2026-06-08: Added a narrow cross-table read/write qmod execution path.
  - Qmods can now declare `db_read:<src>` and `db_write:<dst>` for different tables when source and destination row counts match.
  - Register-time read validation now checks only actual `load` bases against the read table schema, and write validation checks only actual `store` bases against the write table schema. This allows `&col_id` to exist only in the source table and `&col_score` only in the destination table without weakening base-pointer checks.
  - Runtime loads source columns from a read-only table buffer and stores into destination dirty column segments; commit updates only destination SHA metadata and epoch.
  - Added unit coverage: `qmod exec cross-table read-writes u64 DB column segments`, which reads `src.id` row 1 value `2`, adds `10`, writes `12` into `dst.score`, verifies both tables, then reads `sum(dst.score) == 12`.
  - Verification: `/home/vscode/projects/sa_plugins/sa_plugin_db` `zig build test --summary all` -> `24/24 tests passed`; `zig build` passed; `SA_PLUGIN_DEV=1 sa plugin install --dev /home/vscode/projects/sa_plugins/sa_plugin_db` passed; real CLI `SA_PLUGIN_DEV=1 sa db exec <copy_hash> --params params.bin` returned `result_u64: 12`, `src` verify stayed at `epoch: 1`, `dst` verify reached `epoch: 2`, and follow-up read qmod returned `result_u64: 12`.

- 2026-06-08: Added a narrow read-modify-write qmod execution path.
  - Qmods can now declare `db_read:<table>` and `db_write:<table>` together when both grants name the same table.
  - The mixed evaluator reads from the writable column buffers with `load col_x+offset as u64`, computes with the existing arithmetic/comparison subset, writes back with `store col_x+offset, value as u64`, and commits through the same dirty-segment SHA/epoch update path as pure writes.
  - Added unit coverage: `qmod exec read-modify-writes u64 DB column segments`, which reads row 1 value `2`, adds delta `7`, writes `9`, verifies the table, then reads `sum(id) == 10`.
  - Verification: `/home/vscode/projects/sa_plugins/sa_plugin_db` `zig build test --summary all` -> `23/23 tests passed`; `zig build` passed; `SA_PLUGIN_DEV=1 sa plugin install --dev /home/vscode/projects/sa_plugins/sa_plugin_db` passed; real CLI `SA_PLUGIN_DEV=1 sa db exec <update_hash> --params params.bin` returned `result_u64: 9`, `SA_PLUGIN_DEV=1 sa db verify simple` passed with `epoch: 2`, and a follow-up read qmod returned `result_u64: 10`.

- 2026-06-08: Added a narrow persisted `db_write` qmod execution path.
  - Single-table `db_write:<table>` qmods can now execute `store col_x+offset, value as u64` with schema-validated column pointers, `len`, little-endian `u64` params, labels/branches/jumps, arithmetic, and comparisons.
  - Successful writes update dirty column segment files, recompute segment SHA-256 metadata, increment table `epoch`, and rewrite `<table>.meta` so `sa db verify <table>` remains valid.
  - Added unit coverage: `qmod exec writes u64 DB column segments`, which writes the second row from `2` to `9`, verifies the table, then reads `sum(id) == 10` through a read qmod.
  - Verification: `/home/vscode/projects/sa_plugins/sa_plugin_db` `zig build test --summary all` -> `22/22 tests passed`; `zig build` passed; `SA_PLUGIN_DEV=1 sa plugin install --dev /home/vscode/projects/sa_plugins/sa_plugin_db` passed; real CLI `SA_PLUGIN_DEV=1 sa db exec <write_hash> --params params.bin` returned `result_u64: 9`, `SA_PLUGIN_DEV=1 sa db verify simple` passed with `epoch: 2`, and a follow-up read qmod returned `result_u64: 10`.

- 2026-06-08: Added qmod execution-time schema hash drift protection.
  - `loadReadTable()` now rereads current `<table>.sadb-schema`, hashes it with SHA-256, and compares it against `<table>.meta` `schema_hash` before loading column segments.
  - Schema replacement or drift after ingest/register now fails `sa db exec <hash>` with `error[SA-DB-CLI]: invalid DB schema format` instead of reading with stale table metadata.
  - Added unit coverage: `qmod exec rejects table schema hash drift`.
  - Verification: `/home/vscode/projects/sa_plugins/sa_plugin_db` `zig build test --summary all` -> `21/21 tests passed`; `zig build` passed; `SA_PLUGIN_DEV=1 sa plugin install --dev /home/vscode/projects/sa_plugins/sa_plugin_db` passed; real CLI `SA_PLUGIN_DEV=1 sa db init/ingest/register`, mutate `simple.sadb-schema`, then `SA_PLUGIN_DEV=1 sa db exec <hash>` exited 1 with `invalid DB schema format`.

## DB Notes

- Percent is scoped to DB plugin progress, not total SA project progress.
- Remaining major DB gaps: full Referee DB grants, mmap/SIGSEGV guard, Blob Arena, cold/hot tiers, Zstd/S3, SQLite benchmark, and 12 DB Trap boundary coverage.

# SA Rust Std Progress

Scope: current `sa_std` Rust std supplementation pass, excluding optional plugins and full Rust trait/generic/type-system parity.

Current progress: 100%

## Completed Features

- 2026-06-08: Added Rust-style `std::process::abort` helper.
  - Added runtime export `sa_std_process_abort() noreturn`, C header declaration, SA interface declaration, and macro `PROCESS_ABORT`.
  - The helper lowers Rust's `std::process::abort()` into the platform abort path and intentionally never returns.
  - Updated `docs/std_missing.md` so `process::abort` is no longer counted as a process std gap.
  - Added SA process macro surface coverage without invoking the terminating macro in the unit runner, plus C runtime coverage that forks a child, calls `sa_std_process_abort()`, and verifies SIGABRT in the parent.
  - Verification: `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_process_macro_surface.sa --jobs 1 --trace-panic` -> `4 passed; 0 failed; 0 skipped`; `zig test tests/sa_std_runtime.zig --test-filter "sa_std fmt and process exports are usable from C"` -> `All 1 tests passed`; `zig build sa-std-static --summary all` -> `5/5 steps succeeded`; `zig build std-smoke --summary all` -> `7/7 steps succeeded; 14/14 tests passed`.

- 2026-06-08: Updated `sa skills` source generation for the expanded compiler std surface.
  - `sa skills --help` now states that generated skills scan the active `sa_std` root for `.sa`, `.sal`, and `.sai` macros plus extern/export declarations.
  - The generated SA skill now includes a source-level std coverage guide covering core macro families, runtime-backed std families, Rust-style fs/net highlights, async/future/task scope limits, and the plugin boundary.
  - The CLI `std runtime` skill section now reflects the broadened string/vec/slice/option/result/core, fs/env/process/io/time/net/sync, json/regex/fmt/path/term coverage instead of the older narrow facade wording.
  - Added CLI smoke assertions so the generated skill must include representative new std macros such as `FS_CREATE_DIR`, `FS_READ_TO_STRING`, `FS_TRY_EXISTS`, `NET_TO_SOCKET_ADDR_FIRST`, `ENV_ARGS_JSON`, `PROCESS_CHILD_ID`, `PTR_NULL`, `NUM_U64_CHECKED_ADD`, and `ANY_REF_NEW`.
  - Added focused build step `zig build cli-skills-smoke` so future SA skills source changes can be tested without running unrelated full gates.
  - Verification: `zig build cli-skills-smoke --summary all` -> `2/2 tests passed`; `zig build --summary all` -> `14/14 steps succeeded`; regenerated Codex/Claude skills from `/home/vscode/projects/sci/sa_std`.

- 2026-06-08: Added Rust-style `std::fs::try_exists` helper.
  - Added runtime export `sa_std_fs_try_exists(path, len, &out_exists)` and SA macro `FS_TRY_EXISTS`.
  - The helper distinguishes a missing path (`status=OK, exists=0`) from other filesystem errors, matching Rust's `try_exists` result shape more closely than legacy bool-only `FS_EXISTS`.
  - Kept `FS_EXISTS` as the existing compatibility helper.
  - Updated `docs/std_missing.md` and SA skills so `try_exists` is counted as filesystem std coverage.
  - Added focused SA unit coverage for missing and present path results, and extended smoke surface/header/C runtime checks.
  - Verification: `zig build sa-std-static` passed; `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_fs_macro_surface.sa --jobs 1 --trace-panic` -> `8 passed; 0 failed; 0 skipped`; `zig build std-smoke --summary all` -> `7/7 steps succeeded; 14/14 tests passed`.

- 2026-06-08: Added Rust-style `std::fs::read_to_string` helper.
  - Added runtime exports `sa_fs_read_to_string(path, len, max_bytes)` and `sa_std_fs_read_to_string(..., &out_handle)` plus SA macro `FS_READ_TO_STRING`.
  - The helper reuses the existing owned read-buffer contract but validates UTF-8 before returning, so invalid file bytes fail instead of being exposed as a string.
  - Updated `docs/std_missing.md` and SA skills so `read_to_string` is counted as filesystem std coverage rather than a missing gap.
  - Added focused SA unit coverage for valid UTF-8 success and invalid UTF-8 failure, and extended smoke surface/header/C runtime checks.
  - Verification: `zig build sa-std-static` passed; `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_fs_macro_surface.sa --jobs 1 --trace-panic` -> `7 passed; 0 failed; 0 skipped`; `zig build std-smoke --summary all` -> `7/7 steps succeeded; 14/14 tests passed`.

- 2026-06-08: Added Rust-style recursive `std::fs::remove_dir_all` helper and corrected `remove_dir` semantics.
  - Added runtime export `sa_fs_remove_dir_all(path, len)` and SA macro `FS_REMOVE_DIR_ALL` for explicit recursive delete-tree behavior.
  - Changed `sa_fs_remove_dir` / `FS_REMOVE_DIR` to non-recursive directory removal so it now fails on non-empty directories like Rust `std::fs::remove_dir`.
  - Kept `FS_REMOVE_PATH` as the broad recursive compatibility path and documented the difference in `docs/std_missing.md`.
  - Added focused SA unit coverage for non-empty `remove_dir` failure plus `remove_dir_all` success, and extended smoke surface/header/C runtime checks.
  - Verification: `zig build sa-std-static` passed; `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_fs_macro_surface.sa --jobs 1 --trace-panic` -> `6 passed; 0 failed; 0 skipped`; `zig build std-smoke --summary all` -> `7/7 steps succeeded; 14/14 tests passed`.

- 2026-06-08: Added Rust-style non-recursive `std::fs::create_dir` helper.
  - Added runtime export `sa_fs_create_dir(path, len)` and SA macro `FS_CREATE_DIR`.
  - Kept existing `FS_MAKE_DIR` / `FS_CREATE_DIR_ALL` recursive behavior unchanged while adding a Rust-aligned single-directory creation path that fails on existing directories or missing parents.
  - Updated `docs/std_missing.md` so filesystem directory creation coverage distinguishes non-recursive `create_dir` from recursive `create_dir_all`.
  - Extended focused SA unit coverage in `tests/unit_framework/std_fs_macro_surface.sa` and smoke surface/header/C runtime checks in `tests/std_smoke.zig`.
  - Verification: `zig build sa-std-static` passed; `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_fs_macro_surface.sa --jobs 1 --trace-panic` -> `5 passed; 0 failed; 0 skipped`; `zig build std-smoke --summary all` -> `7/7 steps succeeded; 14/14 tests passed`.

- 2026-06-08: Added Rust-style filesystem time mutation POSIX helper.
  - Added runtime export `sa_fs_set_times_ms(path, len, accessed_ms, modified_ms)` and SA macro `FS_SET_TIMES_MS`.
  - The helper lowers Rust's `FileTimes` mutation shape into explicit Unix-millisecond atime/mtime values and updates paths through POSIX `futimens`, staying inside compiler std.
  - Updated `docs/std_missing.md` so filesystem time mutation is no longer counted as completely missing; full Rust `FileTimes` object modeling, nanosecond builder semantics, and cross-platform timestamp behavior remain open.
  - Extended focused SA unit coverage in `tests/unit_framework/std_fs_macro_surface.sa` and smoke surface/header/C runtime checks in `tests/std_smoke.zig`.
  - Verification: `zig build sa-std-static` passed; `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_fs_macro_surface.sa --jobs 1 --trace-panic` -> `5 passed; 0 failed; 0 skipped`; `zig build std-smoke` passed.

- 2026-06-08: Added Rust-style `std::env::join_paths` POSIX JSON helper.
  - Added runtime export `sa_env_join_paths_json(paths_json, len)` and SA macros `ENV_JOIN_PATHS_JSON` / `ENV_JOIN_PATHS_JSON_PTR` using the existing owned env-buffer contract.
  - The helper accepts a JSON array of path strings and returns a POSIX `:`-joined path list for the default Linux platform without plugin platform assumptions.
  - Updated `docs/std_missing.md` so `join_paths` is no longer counted as completely missing; full platform-specific joining, OsString semantics, and Rust iterator/object parity remain open.
  - Added focused SA unit coverage in `tests/unit_framework/std_env_macro_surface.sa`, synchronized runner expectations, and extended env smoke/header checks in `tests/std_smoke.zig`.
  - Verification: `zig build sa-std-static` passed; `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_env_macro_surface.sa --jobs 1 --trace-panic` -> `9 passed; 0 failed; 0 skipped`; `zig build std-smoke` passed.

- 2026-06-08: Added Rust-style `std::env::split_paths` POSIX JSON helper.
  - Added runtime export `sa_env_split_paths_json(path_list, len)` and SA macros `ENV_SPLIT_PATHS_JSON` / `ENV_SPLIT_PATHS_JSON_PTR` using the existing owned env-buffer contract.
  - The helper returns a JSON array of POSIX `:`-split path segments for the default Linux platform without introducing plugin platform assumptions.
  - Updated `docs/std_missing.md` so `split_paths` is no longer counted as completely missing; full platform-specific splitting/joining, OsString semantics, and Rust iterator/object parity remain open.
  - Added focused SA unit coverage in `tests/unit_framework/std_env_macro_surface.sa`, synchronized runner expectations, and extended env smoke/header checks in `tests/std_smoke.zig`.
  - Verification: `zig build sa-std-static` passed; `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_env_macro_surface.sa --jobs 1 --trace-panic` -> `8 passed; 0 failed; 0 skipped`; `zig build std-smoke` passed.

- 2026-06-08: Added Rust-style `std::env::vars` JSON helper.
  - Added runtime export `sa_env_vars_json()` and SA macro `ENV_VARS_JSON` using the existing owned env-buffer contract.
  - The helper returns a JSON array of `{key,value}` records for current-process environment variables, covering a concrete `std::env::vars()` data path without adding Rust iterator/object semantics.
  - Updated `docs/std_missing.md` so `vars` is no longer counted as completely missing; iterator-returning vars, `vars_os`, `args_os`, path-list helpers, and OsString/platform semantics remain open.
  - Added focused SA unit coverage in `tests/unit_framework/std_env_macro_surface.sa`, synchronized runner expectations, and extended env smoke/header checks in `tests/std_smoke.zig`.
  - Verification: `zig build sa-std-static` passed; `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_env_macro_surface.sa --jobs 1 --trace-panic` -> `7 passed; 0 failed; 0 skipped`; `zig build std-smoke` passed.

- 2026-06-08: Added Rust-style `std::env::args` JSON helper.
  - Added runtime export `sa_env_args_json()` and SA macro `ENV_ARGS_JSON` using the existing owned env-buffer contract.
  - The helper returns a JSON array of process arguments and includes `argv[0]`, matching Rust `std::env::args()` rather than the Deno facade's compatibility argument shape.
  - Updated `docs/std_missing.md` so `args` is no longer counted as completely missing; iterator/object-returning args, `args_os`, `vars`, `vars_os`, path-list helpers, and OsString/platform semantics remain open.
  - Added focused SA unit coverage in `tests/unit_framework/std_env_macro_surface.sa`, synchronized runner expectations, and extended env smoke/header checks in `tests/std_smoke.zig`.
  - Verification: `zig build sa-std-static` passed; `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_env_macro_surface.sa --jobs 1 --trace-panic` -> `6 passed; 0 failed; 0 skipped`; `zig build std-smoke` passed.

- 2026-06-08: Added Rust-style `std::fs::set_permissions` POSIX-mode helper.
  - Added runtime export `sa_fs_set_permissions(path, len, mode)` and SA macro `FS_SET_PERMISSIONS`.
  - The helper lowers the common Rust path permission mutation into an explicit POSIX numeric mode (`u32`) and status result, staying inside compiler std and avoiding plugin assumptions.
  - Updated `docs/std_missing.md` so filesystem permission setting is no longer counted as completely missing; rich `Permissions` objects, readonly helpers, Windows ACL semantics, and time mutation remain open.
  - Extended focused SA unit coverage in `tests/unit_framework/std_fs_macro_surface.sa` and smoke surface/header checks in `tests/std_smoke.zig`.
  - Verification: `zig build sa-std-static` passed; `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_fs_macro_surface.sa --jobs 1 --trace-panic` -> `5 passed; 0 failed; 0 skipped`; `zig build std-smoke` passed.

- 2026-06-08: Added Rust-style `std::net::SocketAddr` display formatting for owned runtime addresses.
  - Added runtime export `sa_std_net_addr_format(addr, out, cap, &out_len)` and SA macro `NET_ADDR_FORMAT`.
  - The helper writes address text such as `127.0.0.1:80` into caller-owned storage and reports explicit `(status, len)`, avoiding a new string allocation ABI while covering a common Display-style diagnostic path.
  - Updated `docs/std_missing.md` so owned runtime `NetAddr` formatting is no longer counted as an address formatting gap, while full typed-address parser/display traits remain open.
  - Extended focused SA unit coverage in `tests/unit_framework/std_net_macro_surface.sa` and smoke surface/header checks in `tests/std_smoke.zig`.
  - Verification: `zig build sa-std-static` passed; `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_net_macro_surface.sa --jobs 1 --trace-panic` -> `6 passed; 0 failed; 0 skipped`; `zig build std-smoke` passed.

- 2026-06-08: Added a Rust-style `std::net::ToSocketAddrs` first-address helper.
  - Added runtime export `sa_std_net_to_socket_addr_first(host, len, port, &out_handle)` and SA macro `NET_TO_SOCKET_ADDR_FIRST`.
  - The helper resolves host/port through Zig's address-list resolver and returns the first address as the existing owned `NetAddr` handle, so callers use `NET_ADDR_HOST`, `NET_ADDR_PORT`, `NET_ADDR_FAMILY`, and `NET_ADDR_FREE` without plugin dependencies.
  - Kept the scope explicit: this is a concrete first-address subset, not Rust's iterator trait object or full parser/display surface.
  - Added focused SA unit coverage in `tests/unit_framework/std_net_macro_surface.sa`, synchronized runner expectations, and extended net smoke/header checks in `tests/std_smoke.zig`.
  - Verification: `zig build sa-std-static` passed; `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_net_macro_surface.sa --jobs 1 --trace-panic` -> `6 passed; 0 failed; 0 skipped`; `zig build std-smoke` passed.

- 2026-06-08: Added Rust-style `std::env::set_var` and `remove_var` helpers.
  - Added runtime exports `sa_env_set_var()` and `sa_env_remove_var()` plus SA macros `ENV_SET_VAR`, `ENV_SET_VAR_PTR`, `ENV_REMOVE_VAR`, and `ENV_REMOVE_VAR_PTR`.
  - Kept Deno compatibility names separate; compiler std now has its own env mutation surface instead of treating `sa_deno_env_*` as std coverage.
  - Updated `docs/std_missing.md` so environment mutation is no longer counted as a Rust std gap.
  - Added focused SA unit coverage in `tests/unit_framework/std_env_macro_surface.sa`, synchronized runner expectations, and extended the env C smoke path in `tests/std_smoke.zig`.
  - Verification: `zig build sa-std-static` passed; `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_env_macro_surface.sa --jobs 1 --trace-panic` -> `5 passed; 0 failed; 0 skipped`; `zig build std-smoke` passed.

- 2026-06-08: Added Rust-style `std::fs::canonicalize` helper.
  - Added runtime export `sa_std_fs_canonicalize(path, &out_handle)` and SA macro `FS_CANONICALIZE`.
  - The helper returns the existing owned buffer handle shape for canonical path bytes, matching the current `FS_READ_FILE` / `FS_READ_LINK` buffer access and free contract.
  - Updated `docs/std_missing.md` so filesystem canonicalization is no longer counted as a path/filesystem std gap.
  - Added focused SA unit coverage in `tests/unit_framework/std_fs_macro_surface.sa`, runner expectations in `tests/unit_framework/runner.zig`, and smoke surface/header checks in `tests/std_smoke.zig`.
  - Verification: `zig build sa-std-static` passed; `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_fs_macro_surface.sa --jobs 1 --trace-panic` -> `5 passed; 0 failed; 0 skipped`; `zig build std-smoke` passed.

- 2026-06-08: Added Rust-style filesystem symlink creation and `read_link` helpers.
  - Added runtime exports `sa_fs_symlink(target, link)` and `sa_std_fs_read_link(path, &out_handle)` plus SA macros `FS_SYMLINK` and `FS_READ_LINK`.
  - `FS_READ_LINK` returns the existing owned buffer handle shape, so callers use `FS_READ_BUFFER_DATA`, `FS_READ_BUFFER_LEN`, and `FS_READ_BUFFER_FREE` just like full-file reads.
  - Updated `docs/std_missing.md` so symlink creation and `read_link` are no longer counted as filesystem std gaps.
  - Added focused SA unit coverage in `tests/unit_framework/std_fs_macro_surface.sa`, runner expectations in `tests/unit_framework/runner.zig`, and smoke surface/header checks in `tests/std_smoke.zig`.
  - Verification: `zig build sa-std-static` passed; `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_fs_macro_surface.sa --jobs 1 --trace-panic` -> `4 passed; 0 failed; 0 skipped`; `zig build std-smoke` passed.

- 2026-06-08: Added Rust-style `std::fs::hard_link` helper.
  - Added runtime export `sa_fs_hard_link(from, to)` and SA macro `FS_HARD_LINK` over the POSIX hard-link backend.
  - Kept the API in the existing filesystem style: borrowed path bytes in, explicit `i32` status out, no plugin dependency.
  - Updated `docs/std_missing.md` so `hard_link` is no longer counted as a filesystem std gap.
  - Added focused SA unit coverage in `tests/unit_framework/std_fs_macro_surface.sa`, runner expectations in `tests/unit_framework/runner.zig`, and smoke surface/header checks in `tests/std_smoke.zig`.
  - Verification: `zig build sa-std-static` passed; `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_fs_macro_surface.sa --jobs 1 --trace-panic` -> `3 passed; 0 failed; 0 skipped`; `zig build std-smoke` passed.

- 2026-06-08: Added Rust-style `std::fs::File::sync_data` helper.
  - Added runtime export `sa_fs_file_sync_data(handle)` and SA macro `FS_SYNC_DATA` alongside the existing `FS_SYNC_ALL` surface.
  - Runtime uses `std.posix.fdatasync()` on the registered file handle, keeping the API as an explicit status-returning subset of Rust `File::sync_data()`.
  - Updated `docs/std_missing.md` so `sync_data` is no longer counted as a filesystem std gap.
  - Extended `tests/unit_framework/std_fs_macro_surface.sa` with `FS_SYNC_DATA` status assertions and diagnostic output, plus `tests/std_smoke.zig` surface/header checks.
  - Verification: `zig build sa-std-static` passed; `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_fs_macro_surface.sa --jobs 1 --trace-panic` -> `2 passed; 0 failed; 0 skipped`; `zig build std-smoke` passed.

- 2026-06-08: Added Rust-style `std::process::Child::id` helper.
  - Added runtime export `sa_std_process_child_id(handle, &out_pid)` and SA macro `PROCESS_CHILD_ID` to expose the pid associated with an existing child process handle.
  - Kept the helper read-only: it validates the opaque process handle, returns an explicit status, and does not wait, kill, close, or otherwise mutate process ownership.
  - Updated `docs/std_missing.md` process coverage so `Child::id()` is no longer counted as a compiler-std gap.
  - Added focused SA unit coverage in `tests/unit_framework/std_process_macro_surface.sa`, C ABI coverage in `tests/sa_std_runtime.zig`, and smoke surface assertions in `tests/std_smoke_core.zig`.
  - Verification: `zig build sa-std-static` passed; `zig test tests/sa_std_runtime.zig --test-filter "sa_std fmt and process exports are usable from C"` -> `All 1 tests passed`; `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_process_macro_surface.sa --jobs 1 --trace-panic` -> `3 passed; 0 failed; 0 skipped`; `zig build std-smoke` passed.

- 2026-06-08: Added Rust-style `std::process::Child::try_wait` and `Child::kill` helpers.
  - Added runtime exports `sa_std_process_try_wait()` and `sa_std_process_kill()` plus SA macros `PROCESS_TRY_WAIT`, `PROCESS_TRY_WAIT_EXIT_STATUS`, and `PROCESS_KILL`.
  - Refactored process exit finalization so blocking wait and nonblocking try-wait share captured stdout/stderr collection and exit-code normalization.
  - `PROCESS_TRY_WAIT` returns explicit `(status, ready, code)` outputs, and `PROCESS_KILL` force-kills the child and waits for the process handle to become exited before returning.
  - Updated `docs/std_missing.md` process coverage and corrected existing env coverage for `ENV_SET_CURRENT_DIR` / `ENV_TRY_HOME_DIR`.
  - Added focused SA unit coverage in `tests/unit_framework/std_process_macro_surface.sa`, runner expectations in `tests/unit_framework/runner.zig`, smoke interface assertions in `tests/std_smoke_core.zig`, and C ABI coverage in `tests/sa_std_runtime.zig`.
  - Verification: `zig build sa-std-static` passed; `zig test tests/sa_std_runtime.zig --test-filter "sa_std fmt and process exports are usable from C"` -> `All 1 tests passed`; `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_process_macro_surface.sa --jobs 1 --trace-panic` -> `3 passed; 0 failed; 0 skipped`; `zig build std-smoke` passed.

- 2026-06-08: Added Rust-style `std::net::TcpListener::incoming` adapter macros.
  - Added `NetTcpIncoming` layout constants in `sa_std/net.sal` and pure `sa_std/net.sa` macros `NET_TCP_LISTENER_INCOMING`, `NET_TCP_INCOMING_NEW`, `NET_TCP_INCOMING_LISTENER`, and `NET_TCP_INCOMING_NEXT` over the existing `accept` ABI.
  - Kept this as a concrete wrapper subset: it models Rust's `incoming().next()` entry point as explicit `status + ok + stream` outputs rather than trait iterator objects.
  - Updated `docs/std_missing.md` so `std::net` no longer lists `TcpListener::incoming` as a missing compiler-std gap.
  - Extended SA unit coverage in `tests/unit_framework/std_net_macro_surface.sa`, the unit runner expectations in `tests/unit_framework/runner.zig`, and smoke surface assertions in `tests/std_smoke.zig`.
  - Verification: `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_net_macro_surface.sa --jobs 1 --trace-panic` -> `5 passed; 0 failed; 0 skipped`.

- 2026-06-08: Added Rust-style `std::net` IPv6 multicast control helpers.
  - Added runtime exports `sa_std_net_udp_join_multicast_v6()` / `sa_std_net_udp_leave_multicast_v6()` and plain ABI wrappers `sa_net_udp_join_multicast_v6()` / `sa_net_udp_leave_multicast_v6()` using an in-tree `ipv6_mreq` layout and IPv6 address parsing in `src/runtime/sa_std.zig`.
  - Added `NET_UDP_JOIN_MULTICAST_V6` and `NET_UDP_LEAVE_MULTICAST_V6` in `sa_std/net.sa` plus matching declarations in `sa_std/net.sai` and `src/runtime/sa_std.h`.
  - Updated `docs/std_missing.md` so `std::net` no longer lists IPv6 multicast control as missing compiler-std surface.
  - Added focused SA unit coverage in `tests/unit_framework/std_net_multicast_macro_surface.sa` and extended the C runtime coverage in `tests/sa_std_runtime.zig` to exercise both IPv4 and IPv6 multicast join/leave paths.
  - Verification: `zig build sa-std-static` passed; `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_net_multicast_macro_surface.sa --jobs 1 --trace-panic` -> `2 passed; 0 failed; 0 skipped`; `zig test tests/sa_std_runtime.zig --test-filter "sa_std udp multicast helpers and scope id are usable from C"` -> `All 1 tests passed`.

- 2026-06-08: Added Rust-style `std::process` typed `ExitStatus` / `Output` wrapper macros.
  - Added `ProcessExitStatus` / `ProcessOutput` layout constants in `sa_std/process.sal`.
  - Added `PROCESS_EXIT_STATUS_*`, `PROCESS_OUTPUT_*`, `PROCESS_WAIT_EXIT_STATUS`, `PROCESS_EXEC_CAPTURE_OUTPUT`, and `PROCESS_EXEC_CAPTURE_OUTPUT_CWD` in `sa_std/process.sa` over the existing runtime process and owned read-buffer handles.
  - Kept this as a concrete layout/wrapper subset; `Command`, `Child`, `kill`, `try_wait`, and process-global APIs are still missing.
  - Updated `docs/std_missing.md` process coverage and macro summary.
  - Added SA unit coverage in `tests/unit_framework/std_process_macro_surface.sa`.
  - Verification: `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_process_macro_surface.sa --jobs 1 --trace-panic` -> `2 passed; 0 failed; 0 skipped`.

- 2026-06-08: Added Rust-style `std::path` filesystem query macros.
  - Added `PATH_EXISTS`, `PATH_IS_FILE`, `PATH_IS_DIR`, and `PATH_IS_SYMLINK` in `sa_std/path.sa` by lowering through the existing `sa_std/fs.sa` metadata helpers.
  - Kept this as a thin query subset: lookup failures collapse to `0` for the boolean-style predicates, matching Rust's practical `Path` query shape without exposing metadata handles.
  - Updated `docs/std_missing.md` path coverage and scope notes.
  - Extended SA unit coverage in `tests/unit_framework/std_path_macro_surface.sa` with real file/dir/missing-path checks.
  - Verification: `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_path_macro_surface.sa --jobs 1 --trace-panic` -> `4 passed; 0 failed; 0 skipped`.

- 2026-06-08: Added Rust-style `std::process::id()` lowering.
  - Added runtime export `sa_std_process_id()` and SA macro `PROCESS_ID` as a direct `u32` process-id query over the current host process.
  - Updated `sa_std/process.sai`, `sa_std/process.sa`, `src/runtime/sa_std.zig`, and `src/runtime/sa_std.h` so the SA/C ABI stays aligned.
  - Updated `docs/std_missing.md` process coverage and macro summary.
  - Extended SA unit coverage in `tests/unit_framework/std_process_macro_surface.sa` and smoke/runtime coverage in `tests/std_smoke_core.zig` and `tests/sa_std_runtime.zig`.
  - Verification: `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_process_macro_surface.sa --jobs 1 --trace-panic` -> `2 passed; 0 failed; 0 skipped`; `zig build sa-std-static` passed; `zig test tests/sa_std_runtime.zig` -> `14/14 tests passed`.

- 2026-06-08: Added Rust-style `std::env` path query helpers.
  - Added `ENV_CURRENT_DIR`, `ENV_TEMP_DIR`, and `ENV_CURRENT_EXE` in `sa_std/env.sa` / `sa_std/env.sai` using the existing owned `ENV_BUFFER_*` handle contract.
  - Added runtime exports `sa_env_current_dir()`, `sa_env_temp_dir()`, and `sa_env_current_exe()` backed by `getCwdAlloc`, the current temp-root fallback chain, and `selfExePathAlloc`.
  - Updated `src/runtime/sa_std.h`, `docs/std_missing.md`, and focused SA unit coverage in `tests/unit_framework/std_env_macro_surface.sa`.
  - Extended smoke coverage in `tests/std_smoke.zig` for the C ABI path queries.
  - Verification: `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_env_macro_surface.sa --jobs 1 --trace-panic` -> `3 passed; 0 failed; 0 skipped`; `zig build sa-std-static` passed.

- 2026-06-08: Synced `std_smoke_core` layout expectations with existing `CellU64` and `RefCellU64` std surface.
  - Updated the smoke assertions for `sa_std/core/cell.sal` and `sa_std/core/refcell.sal` to match the already-present `u64` layout contracts.
  - This was required to keep `std-smoke` aligned with the current `sa_std` surface after earlier std additions.
  - Verification: `zig build std-smoke` rerun completed the known process-id path and exposed only these outdated expectations; assertions were synchronized accordingly.

- 2026-06-08: Added diagnostic validation details for borrowed `std::ffi::CStr` byte views.
  - Added `CSTR_VALIDATE_WITH_NUL_DETAIL` and `CSTR_ERROR_POS_NONE` to report validation status plus first interior-NUL index, missing terminator position, or no-error sentinel.
  - Kept this as a borrowed byte-view helper; no `CString` ownership, allocation, OS string, runtime, or plugin APIs were added.
  - Updated `docs/std_missing.md` FFI coverage and macro summary.
  - Extended SA unit coverage in `tests/unit_framework/std_ffi_cstr_macro_surface.sa` for OK, empty, interior-NUL, and unterminated paths.
  - Verification: `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_ffi_cstr_macro_surface.sa --jobs 1 --trace-panic` -> `1 passed; 0 failed; 0 skipped`.

- 2026-06-08: Added Rust-style `std::net` `IpAddr` constants, copy, and family helpers.
  - Added `NET_IP_ADDR_V4_UNSPECIFIED`, `NET_IP_ADDR_V4_LOCALHOST`, `NET_IP_ADDR_V4_BROADCAST`, `NET_IP_ADDR_V6_UNSPECIFIED`, `NET_IP_ADDR_V6_LOCALHOST`, `NET_IP_ADDR_COPY`, `NET_IP_ADDR_FAMILY`, and `NET_SOCKET_ADDR_FAMILY`.
  - Kept the feature as pure typed-address layout macros using existing `SA_NET_AF_INET` / `SA_NET_AF_INET6` constants; no DNS, parser, runtime socket, HTTP, Deno, or plugin APIs were added.
  - Updated `docs/std_missing.md` net coverage and scope notes.
  - Extended SA unit coverage in `tests/unit_framework/std_net_addr_macro_surface.sa` for v4/v6 constants, enum copy, broadcast/loopback/unspecified predicates, and `IpAddr` / `SocketAddr` family dispatch.
  - Verification: `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_net_addr_macro_surface.sa --jobs 1 --trace-panic` -> `3 passed; 0 failed; 0 skipped`.

- 2026-06-08: Added concrete `std::cmp::Reverse` primitive helpers.
  - Added `CmpReverseU64` / `CmpReverseI64` layout constants and `CMP_REVERSE_*_{NEW,GET,SET,COPY,COMPARE,MIN_VALUE,MAX_VALUE}` macros.
  - Kept this as a concrete primitive lowering subset; generic `Reverse<T>` and trait forwarding remain frontend/type-system concerns.
  - Updated `docs/std_missing.md` comparison implemented/missing/scope notes and macro summary.
  - Added SA unit coverage in `tests/unit_framework/std_cmp_macro_surface.sa` for reversed `u64` / `i64` compare and min/max behavior.
  - Verification: `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_cmp_macro_surface.sa --jobs 1 --trace-panic` -> `2 passed; 0 failed; 0 skipped`.

- 2026-06-08: Added integer and `NonZero*` endian value transform coverage.
  - Added `NUM_{U,I}{8,16,32,64}_{SWAP_BYTES,TO_BE,FROM_BE,TO_LE,FROM_LE}` plus 64-bit `NUM_{U,ISIZE}_*` aliases.
  - Added matching `NONZERO_*_{SWAP_BYTES,TO_BE,FROM_BE,TO_LE,FROM_LE}` wrappers that preserve nonzero construction checks.
  - Updated `docs/std_missing.md` numeric implemented/missing/scope notes and macro summary.
  - Added SA unit coverage in `tests/unit_framework/std_num_macro_surface.sa` for primitive and `NonZero` endian value transform roundtrips.
  - Verification: `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_num_macro_surface.sa --jobs 1 --trace-panic` -> `14 passed; 0 failed; 0 skipped`.

- 2026-06-08: Added `NonZero*` numeric bit/byte helper coverage.
  - Added `NONZERO_{U,I}{8,16,32,64}` and `NONZERO_{U,ISIZE}` bit count / leading-zero / trailing-zero wrappers over the concrete primitive integer macros.
  - Added `NONZERO_*_WRITE_{BE,LE,NE}_BYTES` and `NONZERO_*_FROM_{BE,LE,NE}_BYTES` helpers for caller-owned byte buffers; decoded zero values return `ok=0`.
  - Kept the implementation inside `sa_std/num.sa` as pure macro wrappers over existing `NUM_*` helpers; no runtime or plugin APIs were added.
  - Updated `docs/std_missing.md` numeric implemented/missing/scope notes and macro summary.
  - Added SA unit coverage in `tests/unit_framework/std_num_macro_surface.sa` for wide/narrow signed/unsigned/platform `NonZero` bit scans and byte roundtrips.
  - Verification: `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_num_macro_surface.sa --jobs 1 --trace-panic` -> `12 passed; 0 failed; 0 skipped`.

- 2026-06-08: Added signed Rust-named numeric parity helpers.
  - Added checked/direct `NUM_I64_DIV_EUCLID`, `NUM_I64_REM_EUCLID`, `NUM_I64_DIV_CEIL`, `NUM_I64_NEXT_MULTIPLE_OF`, `NUM_I64_ILOG`, `NUM_I64_ILOG2`, and `NUM_I64_ILOG10` families.
  - Added matching 64-bit `NUM_ISIZE_*` aliases for the same signed helpers.
  - Signed checked helpers return explicit `(ok, value)` on division-by-zero, `MIN / -1`, invalid logarithm input/base, and positive next-multiple overflow paths.
  - Updated `docs/std_missing.md` numeric implemented/missing/scope notes and macro summary.
  - Added SA unit coverage in `tests/unit_framework/std_num_macro_surface.sa` for positive, negative, overflow, and invalid-input paths.
  - Verification: `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_num_macro_surface.sa --jobs 1 --trace-panic` -> `11 passed; 0 failed; 0 skipped`.

- 2026-06-08: Added `std::char` escape write helpers.
  - Added `CHAR_ESCAPE_UNICODE_WRITE` for Rust-style lowercase `\u{...}` output into caller storage.
  - Added `CHAR_ESCAPE_DEFAULT_WRITE` for Rust `char::escape_default` byte behavior: special ASCII escapes, printable ASCII pass-through, and Unicode fallback.
  - Updated `docs/std_missing.md` char coverage and macro parity notes.
  - Added SA unit coverage in `tests/unit_framework/std_char_macro_surface.sa`.
  - Verification: `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_char_macro_surface.sa --jobs 1 --trace-panic` -> `4 passed; 0 failed; 0 skipped`.
- 2026-06-08: Added Rust-style `std::net` typed address octet lowering helpers.
  - Added `NET_IPV4_AS_OCTETS_PTR`, `NET_IPV4_WRITE_OCTETS`, `NET_IPV6_WRITE_OCTETS`, `NET_IP_ADDR_OCTET_LEN`, and `NET_IP_ADDR_WRITE_OCTETS`.
  - Kept this purely in `sa_std/net.sa`; no plugin APIs or socket runtime behavior were added.
  - Updated `docs/std_missing.md` net typed-address coverage notes.
  - Added SA unit coverage in `tests/unit_framework/std_net_typed_address_macro_surface.sa`.
  - Verification: `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_net_typed_address_macro_surface.sa --jobs 1 --trace-panic` -> `1 passed; 0 failed; 0 skipped`.
- 2026-06-08: Added Rust `std::path` Option-style query lowering helpers.
  - Added `PATH_TRY_PARENT`, `PATH_TRY_FILE_NAME`, `PATH_TRY_FILE_STEM`, and `PATH_TRY_EXTENSION` so callers can distinguish absent path values from empty slices.
  - Preserved existing non-try path macros for compatibility.
  - Updated `docs/std_missing.md` path coverage notes.
  - Added SA unit coverage in `tests/unit_framework/std_path_macro_surface.sa`.
  - Verification: `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_path_macro_surface.sa --jobs 1 --trace-panic` -> `3 passed; 0 failed; 0 skipped`.
- 2026-06-08: Added Rust `std::env` optional lookup helpers.
  - Added `ENV_TRY_GET`, `ENV_TRY_GET_PTR`, `ENV_TRY_GET_SLICE`, and `ENV_TRY_GET_SLICE_PTR` for `var_os`-style present/missing lookup without fetching absent keys.
  - Missing keys return `ok=0`, buffer `0`, and an empty slice where applicable; present keys return owned env buffers that still require `ENV_BUFFER_FREE`.
  - Updated `docs/std_missing.md` env coverage and plugin boundary notes.
  - Added SA unit coverage in `tests/unit_framework/std_env_macro_surface.sa`.
  - Verification: `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_env_macro_surface.sa --jobs 1 --trace-panic` -> `2 passed; 0 failed; 0 skipped`.
- 2026-06-08: Added Rust `std::num` byte-array conversion helpers.
  - Added `NUM_U64_WRITE_BE_BYTES`, `NUM_U64_WRITE_LE_BYTES`, `NUM_U64_WRITE_NE_BYTES`, `NUM_U64_FROM_BE_BYTES`, `NUM_U64_FROM_LE_BYTES`, and `NUM_U64_FROM_NE_BYTES` for caller-owned 8-byte buffers.
  - Added `NUM_I64_*_BYTES` aliases that preserve the same two's-complement bit pattern.
  - Adjusted `NUM_I64_MIN` / `NUM_ISIZE_MIN` definitions to avoid flattener overflow when parsing minimum signed literals.
  - Updated `docs/std_missing.md` numeric coverage notes.
  - Added SA unit coverage in `tests/unit_framework/std_num_macro_surface.sa`.
  - Verification: `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_num_macro_surface.sa --jobs 1 --trace-panic` -> `9 passed; 0 failed; 0 skipped`.
- 2026-06-08: Completed `std::num` byte-array conversion width coverage.
  - Added `NUM_U8`, `NUM_U16`, and `NUM_U32` write/from byte helpers for BE, LE, and NE forms.
  - Added `NUM_I8`, `NUM_I16`, and `NUM_I32` signed byte helpers with two's-complement write behavior and sign-extended reads.
  - Updated `docs/std_missing.md` to describe full 8/16/32/64-bit primitive byte conversion coverage.
  - Added focused SA unit coverage in `tests/unit_framework/std_num_macro_surface.sa`.
  - Verification: `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_num_macro_surface.sa --jobs 1 --trace-panic` -> `10 passed; 0 failed; 0 skipped`.
- 2026-06-08: Added platform-sized numeric byte conversion aliases.
  - Added `NUM_USIZE_WRITE_{BE,LE,NE}_BYTES`, `NUM_USIZE_FROM_{BE,LE,NE}_BYTES`, `NUM_ISIZE_WRITE_{BE,LE,NE}_BYTES`, and `NUM_ISIZE_FROM_{BE,LE,NE}_BYTES` as explicit 64-bit platform-sized aliases.
  - Updated `docs/std_missing.md` numeric scope notes.
  - Added SA unit coverage in `tests/unit_framework/std_num_macro_surface.sa`.
  - Verification: `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_num_macro_surface.sa --jobs 1 --trace-panic` -> `10 passed; 0 failed; 0 skipped`.
- 2026-06-08: Added unsigned Rust-named numeric `div_ceil` and logarithm helpers.
  - Added `NUM_U64_DIV_CEIL`, `NUM_U64_CHECKED_ILOG`, `NUM_U64_ILOG`, `NUM_U64_CHECKED_ILOG2`, `NUM_U64_ILOG2`, `NUM_U64_CHECKED_ILOG10`, and `NUM_U64_ILOG10`.
  - Added matching 64-bit `NUM_USIZE_*` aliases for the same unsigned helpers.
  - Updated `docs/std_missing.md` numeric implemented/missing/scope notes.
  - Added SA unit coverage in `tests/unit_framework/std_num_macro_surface.sa`.
  - Verification: `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_num_macro_surface.sa --jobs 1 --trace-panic` -> `10 passed; 0 failed; 0 skipped`.

## Completed: 2026-07-13 Infallible + CONVERT_* min/max + NonZero* MIN/MAX/ONE constants (Batch m)

- `sa_std/convert.sal`: Added `Infallible_SIZE = 0` and `Infallible_ALIGN = 1` constants model Rust's never-error `convert::Infallible` type (an enum with no inhabitants).
- `sa_std/convert.sal`: Completed `CONVERT_*` min/max coverage with 9 new constants: `CONVERT_U64_MIN/MAX`, `CONVERT_I64_MIN`, `CONVERT_USIZE_MIN/MAX`, `CONVERT_ISIZE_MIN/MAX`, `CONVERT_BOOL_MIN/MAX`. Mirrors Rust std associated `MIN/MAX` constants.
- `sa_std/num.sal`: Added 35 `NonZero*` associated constants mirroring Rust 1.70+ stabilized constants: `NONZERO_U8/U16/U32/U64/usize_MIN/MAX/ONE` (15 unsigned: MIN is always 1 since 0 is excluded by definition, MAX equals wrapping type MAX, ONE is 1); `NONZERO_I8/I16/I32/I64/isize_MIN/MAX` (10 signed: MIN is the wrapping type MIN — which is nonzero for all signed types, MAX is the wrapping type MAX).
- Test: `tests/unit_framework/std_convert_nonzero_macro_surface.sa` — 2 tests (panic IDs 10469/10470) verifying all new `.sal` constants match expected values and the `NonZero*::MAX` constants equal the `NUM_*_MAX` constants.
- Validation status:
  - Focused: `SA_STD_DIR=/home/vscode/.sa/std ./zig-out/bin/sa test tests/unit_framework/std_convert_nonzero_macro_surface.sa --jobs 1 --trace-panic` -> `2 passed; 0 failed; 0 skipped`.
  - Full `zig build unit-framework --summary all`: pass (`6/6 steps succeeded; 5/5 tests passed`).
- Panic IDs next free: 10471+.

## Completed: 2026-07-13 Option zip/unzip, CHAR_MIN, CMP_ORDERING_MIN/MAX (Batch n)

- `sa_std/core/option.sal`: Added `OptionPairU64_SIZE`, `OptionPairU64_tag`, `OptionPairU64_value1`, `OptionPairU64_value2` layout constants modeling Rust 1.46+ `Option::zip` pair result layout (24-byte struct with tag + two u64 values).
- `sa_std/core/option.sa`: Added `OPTION_ZIP_U64` macro combining two Options into a single Some(pair) when both are Some, otherwise None. Handles all 4 input combinations with proper register release ordering per control-flow path.
- `sa_std/core/option.sa`: Added `OPTION_UNZIP_TO_U64` macro (Rust nightly `unzip`) extracting the two u64 values from an OptionPairU64 into separate Option layouts.
- `sa_std/char.sal`: Added `CHAR_MIN = 0` constant alias for Rust `char::MIN`.
- `sa_std/cmp.sal`: Added `CMP_ORDERING_MIN = -1` and `CMP_ORDERING_MAX = 1` mirroring Rust 1.84+ stabilized `Ordering::MIN`/`MAX` associated constants.
- Test: `tests/unit_framework/std_option_zip_macro_surface.sa` — 2 tests (panic IDs 10471/10472) verifying zip/unzip, both-some and none-edge cases, Plus new constants (OptionPairU64 layout, CHAR_MIN, CMP_ORDERING_MIN/MAX).
- Validation status:
  - Focused: `SA_STD_DIR=/home/vscode/.sa/std ./zig-out/bin/sa test tests/unit_framework/std_option_zip_macro_surface.sa --jobs 1 --trace-panic` -> `2 passed; 0 failed; 0 skipped`.
  - Full `zig build unit-framework --summary all`: pass (`6/6 steps succeeded; 5/5 tests passed`).
- Panic IDs next free: 10473+.

## Notes

- Percent is an implementation-progress estimate for the current std supplementation pass, not a claim of complete Rust std compatibility.
- Plugin-provided APIs remain outside `sa_std` progress.

## Completed: 2026-07-13 f32/f64 IEEE754 constants + Wrapping/Saturating layouts + unsigned MIN/BYTES (Batch o)

- `sa_std/num.sal`: Added 5 unsigned MIN constants (`NUM_U8_MIN`, `NUM_U16_MIN`, `NUM_U32_MIN`, `NUM_U64_MIN`, `NUM_USIZE_MIN` all = 0) mirroring Rust `u8::MIN = 0`, etc.
- `sa_std/num.sal`: Added 10 BYTES constants (`NUM_U8_BYTES = 1` through `NUM_ISIZE_BYTES = 8`) mirroring Rust 1.60+ stabilized `<integer>::BYTES`.
- `sa_std/num.sal`: Added 13 f32 associated constants as IEEE 754 bit patterns: `NUM_F32_BITS`, `NUM_F32_BYTES`, `NUM_F32_INFINITY`, `NUM_F32_NEG_INFINITY`, `NUM_F32_NAN`, `NUM_F32_ZERO`, `NUM_F32_MINUS_ZERO`, `NUM_F32_MIN_POSITIVE`, `NUM_F32_MAX`, `NUM_F32_MIN`, `NUM_F32_EPSILON`, `NUM_F32_MAX_SUBNORMAL`, `NUM_F32_MIN_SUBNORMAL`.
- `sa_std/num.sal`: Added 13 f64 associated constants as IEEE 754 bit patterns: `NUM_F64_BITS`, `NUM_F64_BYTES`, `NUM_F64_INFINITY`, `NUM_F64_NEG_INFINITY`, `NUM_F64_NAN`, `NUM_F64_ZERO`, `NUM_F64_MINUS_ZERO`, `NUM_F64_MIN_POSITIVE`, `NUM_F64_MAX`, `NUM_F64_MIN`, `NUM_F64_EPSILON`, `NUM_F64_MAX_SUBNORMAL`, `NUM_F64_MIN_SUBNORMAL`.
- `sa_std/num.sal`: Added Wrapping<T> layout constants: `WrappingU64_SIZE`, `WrappingU64_value`, `WrappingU32_SIZE`, `WrappingU32_value`, `WrappingI64_SIZE`, `WrappingI64_value`.
- `sa_std/num.sal`: Added Saturating<T> layout constants: `SaturatingU64_SIZE`, `SaturatingU64_value`, `SaturatingI64_SIZE`, `SaturatingI64_value`.
- `sa_std/default.sa`: `DEFAULT_WRAPPING_U64` and `DEFAULT_SATURATING_U64` macros (zero-init constructors).
- Test: `tests/unit_framework/std_float_wrapping_macro_surface.sa` — 2 tests (panic IDs 10473/10474) verifying all new constants, layout constants, and Wrapping/Saturating store/load semantics.
- Validation status:
  - Focused: `SA_STD_DIR=/home/vscode/.sa/std ./zig-out/bin/sa test tests/unit_framework/std_float_wrapping_macro_surface.sa --jobs 1 --trace-panic` -> `2 passed; 0 failed; 0 skipped`.
  - Full `zig build unit-framework --summary all`: pass (`6/6 steps succeeded; 5/5 tests passed`).
- Panic IDs next free: 10475+.

## Completed: 2026-07-13 Wrapping/Saturating construction macros + Range usize aliases (Batch p)

- `sa_std/num.sa`: Added 11 Wrapping/Saturating construction and access macros: `WRAPPING_U64_NEW`, `WRAPPING_U64_GET`, `WRAPPING_U64_SET`, `WRAPPING_U32_NEW`, `WRAPPING_U32_GET`, `WRAPPING_I64_NEW`, `WRAPPING_I64_GET`, `SATURATING_U64_NEW`, `SATURATING_U64_GET`, `SATURATING_U64_SET`, `SATURATING_I64_NEW`, `SATURATING_I64_GET`.
- `sa_std/ops.sal`: Added 7 `Range<usize>`/`RangeInclusive<usize>`/`RangeFrom<usize>`/`RangeTo<usize>`/`RangeToInclusive<usize>`/`Bound<usize>` layout constants as 64-bit platform aliases.
- `sa_std/ops.sa`: Added 11 `RANGE_USIZE_*` alias macros wrapping the existing `RANGE_U64_*` macros: `RANGE_USIZE_NEW`, `RANGE_USIZE_START`, `RANGE_USIZE_END`, `RANGE_USIZE_CONTAINS`, `RANGE_USIZE_IS_EMPTY`, `RANGE_USIZE_LEN`, `RANGE_USIZE_DEFAULT`, `RANGE_INCLUSIVE_USIZE_DEFAULT`, `RANGE_FROM_USIZE_DEFAULT`, `RANGE_TO_USIZE_DEFAULT`, `RANGE_TO_INCLUSIVE_USIZE_DEFAULT`, `RANGE_USIZE_FULL_DEFAULT`.
- Test: `tests/unit_framework/std_wrapping_range_macro_surface.sa` — 2 tests (panic IDs 10475/10476) verifying Wrapping/Saturating construction/access and Range usize layout/macros/defaults.
- Validation status:
  - Focused: `SA_STD_DIR=/home/vscode/.sa/std ./zig-out/bin/sa test tests/unit_framework/std_wrapping_range_macro_surface.sa --jobs 1 --trace-panic` -> `2 passed; 0 failed; 0 skipped`.
  - Full `zig build unit-framework --summary all`: pass (`6/6 steps succeeded; 5/5 tests passed`).
- Panic IDs next free: 10477+.

## Completed: 2026-07-13 mem size_of/align_of for float/ptr/char types (Batch q)

- `sa_std/mem.sal`: Added `MEM_SIZE_F32 = 4`, `MEM_ALIGN_F32 = 4`, `MEM_SIZE_F64 = 8`, `MEM_ALIGN_F64 = 8`, `MEM_SIZE_PTR = 8`, `MEM_ALIGN_PTR = 8`, `MEM_SIZE_CHAR = 4`, `MEM_ALIGN_CHAR = 4` mirroring Rust `mem::size_of`/`mem::align_of` for f32, f64, raw pointers, and char types.
- Test: `tests/unit_framework/std_mem_size_macro_surface.sa` — 1 test (panic ID 10477) verifying all new float/ptr/char size/align constants against known values and cross-checking `MEM_SIZE_F32` == `NUM_F32_BYTES`, `MEM_SIZE_F64` == `NUM_F64_BYTES`.
- Validation status:
  - Focused: `SA_STD_DIR=/home/vscode/.sa/std ./zig-out/bin/sa test tests/unit_framework/std_mem_size_macro_surface.sa --jobs 1 --trace-panic` -> `1 passed; 0 failed; 0 skipped`.
- Panic IDs next free: 10478+.

## Completed: 2026-07-14 f32/f64 Digits/Radix/Exp constants + mem float/ptr/char SIZE_OF/ALIGN_OF macros (Batch r)

- `sa_std/num.sal`: Added 12 f32/f64 numeric constants: `NUM_F32_DIGITS = 6`, `NUM_F32_RADIX = 2`, `NUM_F32_MIN_EXP = -125`, `NUM_F32_MAX_EXP = 128`, `NUM_F32_MIN_10_EXP = -37`, `NUM_F32_MAX_10_EXP = 38`, `NUM_F64_DIGITS = 15`, `NUM_F64_RADIX = 2`, `NUM_F64_MIN_EXP = -1021`, `NUM_F64_MAX_EXP = 1024`, `NUM_F64_MIN_10_EXP = -307`, `NUM_F64_MAX_10_EXP = 308`.
- `sa_std/mem.sa`: Added 8 `MEM_SIZE_OF_*` / `MEM_ALIGN_OF_*` macros for f32, f64, ptr, and char types (returning the new `MEM_SIZE_*` / `MEM_ALIGN_*` constants).
- Test: `tests/unit_framework/std_float_constants_macro_surface.sa` — 1 test (panic ID 10478) verifying f32/f64 digits/radix/exp constants.
- Validation status:
  - Focused: `SA_STD_DIR=/home/vscode/.sa/std ./zig-out/bin/sa test tests/unit_framework/std_float_constants_macro_surface.sa --jobs 1 --trace-panic` -> `1 passed; 0 failed; 0 skipped`.
  - All prior batch focused tests re-verified: `std_float_wrapping_macro_surface.sa` (2 passed), `std_wrapping_range_macro_surface.sa` (2 passed), `std_mem_size_macro_surface.sa` (1 passed).
- Panic IDs next free: 10479+.

## Completed: 2026-07-14 f32/f64 Mantissa Digits constants (Batch r final)

- `sa_std/num.sal`: Added `NUM_F32_MANTISSA_DIGITS = 24` and `NUM_F64_MANTISSA_DIGITS = 53` mirroring Rust `f32::MANTISSA_DIGITS` and `f64::MANTISSA_DIGITS`.
- `tests/unit_framework/std_float_constants_macro_surface.sa`: Extended test to cover mantissa digits alongside the previously-added Digits/Radix/Exp constants.
- `sa_std/mem.sa`: 8 new `MEM_SIZE_OF_*` / `MEM_ALIGN_OF_*` macros for f32/f64/ptr/char types.
- Validation status:
  - Focused: `SA_STD_DIR=/home/vscode/.sa/std ./zig-out/bin/sa test tests/unit_framework/std_float_constants_macro_surface.sa --jobs 1 --trace-panic` -> `1 passed; 0 failed; 0 skipped`.
  - All 4 new test files focused-verified: float_wrapping (2p), wrapping_range (2p), mem_size (1p), float_constants (1p).
  - Full `zig build unit-framework --summary all`: pass (`6/6 steps succeeded; 5/5 tests passed`).
- Panic IDs next free: 10479+.

## Completed: 2026-07-14 Wrapping/Saturating MIN/MAX constants + arithmetic macros (Batch s)

- `sa_std/num.sal`: Added 10 Wrapping/Saturating MIN/MAX constants: `WRAPPING_U64_MIN/MAX`, `WRAPPING_U32_MIN/MAX`, `WRAPPING_I64_MIN/MAX`, `SATURATING_U64_MIN/MAX`, `SATURATING_I64_MIN/MAX` mirroring Rust `Wrapping<T>` and `Saturating<T>` inherent constants.
- `sa_std/num.sa`: Added 6 Wrapping/Saturating arithmetic macros: `WRAPPING_U64_ADD`, `WRAPPING_U64_SUB`, `WRAPPING_U64_MUL`, `SATURATING_U64_ADD`, `SATURATING_U64_SUB`, `SATURATING_U64_MUL` that get both operands from Wrapping/Saturating struct layouts, call existing `NUM_U64_WRAPPING_*`/`NUM_U64_SATURATING_*` arithmetic, and set the result back.
- Test: `tests/unit_framework/std_wrapping_arith_macro_surface.sa` — 1 test (panic ID 10479) verifying all MIN/MAX constants plus wrapping add/sub/mul (100+200=300, 100-200 wrapps to 2^64-100, 100*200=20000) and saturating add/sub/mul (100-200 saturates to 0).
- Validation status:
  - Focused: `SA_STD_DIR=/home/vscode/.sa/std ./zig-out/bin/sa test tests/unit_framework/std_wrapping_arith_macro_surface.sa --jobs 1 --trace-panic` -> `1 passed; 0 failed; 0 skipped`.
- Panic IDs next free: 10480+.
  - Full `zig build unit-framework --summary all`: pass (`6/6 steps succeeded; 5/5 tests passed`, 15m elapsed).

## Completed: 2026-07-14 Atomic Ordering enum constants (Batch t)

- `sa_std/sync/atomic.sal`: Added 5 Rust `std::sync::atomic::Ordering` enum constants: `ATOMIC_ORDERING_RELAXED = 0`, `ATOMIC_ORDERING_RELEASE = 1`, `ATOMIC_ORDERING_ACQUIRE = 2`, `ATOMIC_ORDERING_ACQ_REL = 3`, `ATOMIC_ORDERING_SEQ_CST = 4`.
- Test: `tests/unit_framework/std_atomic_ordering_macro_surface.sa` — 1 test (panic ID 10480) verifying all 5 Ordering constants plus all atomic layout sizes (Bool/U8/U16/U32/U64/I64/Usize/Isize/Ptr).
- Validation status:
  - Focused: `SA_STD_DIR=/home/vscode/.sa/std ./zig-out/bin/sa test tests/unit_framework/std_atomic_ordering_macro_surface.sa --jobs 1 --trace-panic` -> `1 passed; 0 failed; 0 skipped`.
- Panic IDs next free: 10481+.

## Completed: 2026-07-14 f32/f64 bit masks and exponent bias (Batch u)

- `sa_std/num.sal`: Added 8 f32/f64 IEEE 754 bit manipulation constants: `NUM_F32_SIGN_BIT`, `NUM_F32_EXP_MASK`, `NUM_F32_MANT_MASK`, `NUM_F32_EXP_BIAS`, `NUM_F64_SIGN_BIT`, `NUM_F64_EXP_MASK`, `NUM_F64_MANT_MASK`, `NUM_F64_EXP_BIAS`.
- Test: `tests/unit_framework/std_float_bitmask_macro_surface.sa` — 1 test (panic ID 10481) verifying all bit masks, exponent biases, and cross-checking that `NUM_F32_INFINITY == NUM_F32_EXP_MASK` (INFINITY has all exponent bits set, zero mantissa).
- Validation status:
  - Focused: `SA_STD_DIR=/home/vscode/.sa/std ./zig-out/bin/sa test tests/unit_framework/std_float_bitmask_macro_surface.sa --jobs 1 --trace-panic` -> `1 passed; 0 failed; 0 skipped`.
- Panic IDs next free: 10482+.

## Completed: 2026-07-14 Path/PathBuf layout constants (Batch v)

- `sa_std/path.sal`: New file with `Path_SIZE`/`Path_ptr`/`Path_len`, `PathBuf_SIZE`/`PathBuf_ptr`/`PathBuf_cap` layout constants (both equal to `Slice_SIZE` on Unix), and `PATH_MAIN_SEPARATOR`/`PATH_MAIN_SEPARATOR_UNIX` constants (47 = ASCII `/`).
- Test: `tests/unit_framework/std_path_layout_macro_surface.sa` — 1 test (panic ID 10482) verifying Path/PathBuf layout matches Slice layout and Unix separator is `/`.
- Validation status:
  - Focused: `SA_STD_DIR=/home/vscode/.sa/std ./zig-out/bin/sa test tests/unit_framework/std_path_layout_macro_surface.sa --jobs 1 --trace-panic` -> `1 passed; 0 failed; 0 skipped`.
- Panic IDs next free: 10483+.

## Completed: 2026-07-14 OsStr/OsString + sync guard layout constants (Batch w)

- `sa_std/ffi.sal`: Added OsStr/OsString layout constants (`OsStr_SIZE`/`ptr`/`len`, `OsString_SIZE`/`ptr`/`cap`, both equal to `Slice_SIZE` on Unix) and 3 `OS_STR_*` conversion error codes mirroring `std::ffi::OsStr`/`OsString`.
- `sa_std/sync/mutex.sal`: Added `MutexGuard_SIZE`/`mutex`/`data` layout constants (pointer-sized guard holding a reference to the parent Mutex).
- `sa_std/sync/rwlock.sal`: Added `RwLockReadGuard_SIZE`/`rwlock`/`data` and `RwLockWriteGuard_SIZE`/`rwlock`/`data` layout constants.
- Test: `tests/unit_framework/std_ffi_osstr_layout_macro_surface.sa` — 2 tests (panic IDs 10483/10484) verifying all layout offsets and error code values.
- Validation status:
  - Focused: `SA_STD_DIR=/home/vscode/.sa/std ./zig-out/bin/sa test tests/unit_framework/std_ffi_osstr_layout_macro_surface.sa --jobs 1 --trace-panic` -> `2 passed; 0 failed; 0 skipped`.
- Panic IDs next free: 10485+.

## Completed: 2026-07-14 Duration/Instant/SystemTime layout constants (Batch x)

- `sa_std/time.sal`: Added `Duration_SIZE`/`nanos`/`ZERO`/`MIN`/`MAX`, `Instant_SIZE`/`nanos`, `SystemTime_SIZE`/`nanos`/`UNIX_EPOCH` layout constants mirroring `std::time` (all 8-byte ns in this codebase).
- Test: `tests/unit_framework/std_time_duration_layout_macro_surface.sa` — 1 test (panic ID 10485) verifying Duration/Instant/SystemTime sizes, offsets, the 7 named conversion constants (NS_PER_S/MS/US, MS_PER_S, S_PER_MIN/HOUR/DAY/WEEK), and the DURATION_ZERO/MIN + UNIX_EPOCH sentinels.
- Validation status:
  - Focused: `SA_STD_DIR=/home/vscode/.sa/std ./zig-out/bin/sa test tests/unit_framework/std_time_duration_layout_macro_surface.sa --jobs 1 --trace-panic` -> `1 passed; 0 failed; 0 skipped`.
- Panic IDs next free: 10486+.

## Completed: 2026-07-14 IntErrorKind + ParseIntError layout (Batch y)

- `sa_std/num.sal`: Added 5 `std::num::IntErrorKind` enum constants (`NUM_INT_ERROR_EMPTY`/`INVALID_DIGIT`/`POS_OVERFLOW`/`NEG_OVERFLOW`/`ZERO`) and `ParseIntError` layout (`SIZE`/`code`/`msg`).
- Test: `tests/unit_framework/std_int_error_kind_macro_surface.sa` — 1 test (panic ID 10486) verifying all 5 error code values and the ParseIntError layout.
- Validation status:
  - Focused: `SA_STD_DIR=/home/vscode/.sa/std ./zig-out/bin/sa test tests/unit_framework/std_int_error_kind_macro_surface.sa --jobs 1 --trace-panic` -> `1 passed; 0 failed; 0 skipped`.
- Panic IDs next free: 10487+.

## Completed: 2026-07-14 TryFromIntError + TryFromSliceError layout constants (Batch z)

- `sa_std/num.sal`: Added `TryFromIntError` layout (`SIZE`/`code`) and 2 error code constants (`TRY_FROM_INT_ERROR_POS_OVERFLOW`/`NEG_OVERFLOW`) mirroring `std::num::TryFromIntError`.
- `sa_std/core/slice.sal`: Added `TryFromSliceError` layout (`SIZE`/`code`) and 1 error code constant (`TRY_FROM_SLICE_ERROR_LENGTH_MISMATCH`) mirroring `std::array::TryFromSliceError`.
- Test: `tests/unit_framework/std_try_from_error_macro_surface.sa` — 1 test (panic ID 10487) verifying both layouts and all error code values.
- Validation status:
  - Focused: `SA_STD_DIR=/home/vscode/.sa/std ./zig-out/bin/sa test tests/unit_framework/std_try_from_error_macro_surface.sa --jobs 1 --trace-panic` -> `1 passed; 0 failed; 0 skipped`.
- Panic IDs next free: 10488+.

## Completed: 2026-07-14 NonZero BITS/BYTES constants (Batch aa)

- `sa_std/num.sal`: Added 20 `NonZero*::BITS`/`BYTES` constants (10 integer types × 2) mirroring Rust 1.80+ `NonZero*::BITS`/`BYTES` associated constants: U8/U16/U32/U64/usize/I8/I16/I32/I64/isize.
- Test: `tests/unit_framework/std_nonzero_bits_macro_surface.sa` — 1 test (panic ID 10488) verifying all 20 new constants plus cross-checking that `NONZERO_*_BITS == NUM_*_BITS` for all 10 integer types.
- Validation status:
  - Focused: `SA_STD_DIR=/home/vscode/.sa/std ./zig-out/bin/sa test tests/unit_framework/std_nonzero_bits_macro_surface.sa --jobs 1 --trace-panic` -> `1 passed; 0 failed; 0 skipped`.
- Panic IDs next free: 10489+.

## Completed: 2026-07-14 OnceLock and LazyLock layout constants (Batch ab)

- `sa_std/sync/once.sal`: Added `OnceLock` layout (`SIZE`/`state`/`value`) and 3 state constants aliasing the `Once` states, plus `LazyLock` layout (`SIZE`/`state`/`value`) and 3 state constants. Mirrors Rust 1.70+ `std::sync::OnceLock` and the `LazyLock` adapter (both share the same `Once`-style inner state machine).
- Test: `tests/unit_framework/std_once_lock_layout_macro_surface.sa` — 1 test (panic ID 10489) verifying both layouts, all 6 state aliases, and cross-checking that `OnceLock_SIZE == Once_SIZE` and `LazyLock_SIZE == Once_SIZE`.
- Validation status:
  - Focused: `SA_STD_DIR=/home/vscode/.sa/std ./zig-out/bin/sa test tests/unit_framework/std_once_lock_layout_macro_surface.sa --jobs 1 --trace-panic` -> `1 passed; 0 failed; 0 skipped`.
- Panic IDs next free: 10490+.

## Completed: 2026-07-14 JoinHandle layout constants (Batch ac)

- `sa_std/thread.sal`: New file with `JoinHandle_SIZE`/`handle`/`result` layout constants (16 bytes: i32 slot + pointer-sized result) mirroring Rust `std::thread::JoinHandle`, and `THREAD_DEFAULT_ID = 0` sentinel for the current-thread ID default.
- Test: `tests/unit_framework/std_joinhandle_layout_macro_surface.sa` — 1 test (panic ID 10490) verifying the JoinHandle layout and default thread id sentinel.
- Validation status:
  - Focused: `SA_STD_DIR=/home/vscode/.sa/std ./zig-out/bin/sa test tests/unit_framework/std_joinhandle_layout_macro_surface.sa --jobs 1 --trace-panic` -> `1 passed; 0 failed; 0 skipped`.
- Panic IDs next free: 10491+.

## Completed: 2026-07-14 char associated constants and layout aliases (Batch ad)

- `sa_std/char.sal`: Added `CHAR_SIZE = 4` and `CHAR_ALIGN = 4`, mirroring Rust `char`'s 32-bit Unicode scalar representation and matching the existing `MEM_SIZE_CHAR` / `MEM_ALIGN_CHAR` constants.
- `sa_std/char.sal`: Added `CHAR_REPLACEMENT_CHARACTER` as a Rust-named alias for `CHAR_REPLACEMENT`, plus `CHAR_MAX_LEN_UTF8 = 4` and `CHAR_MAX_LEN_UTF16 = 2`, matching Rust `char` associated constants.
- Test: `tests/unit_framework/std_char_constants_macro_surface.sa` — 1 test (panic ID 10491) verifying the new constants and cross-checking char layout against `mem.sal`.
- Validation status:
  - Focused: `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_char_constants_macro_surface.sa --jobs 1 --trace-panic` -> `1 passed; 0 failed; 0 skipped`.
- Panic IDs next free: 10492+.

## Completed: 2026-07-14 char error layout constants (Batch ae)

- `sa_std/char.sal`: Added `ParseCharError_SIZE` / `ParseCharError_kind` layout constants and `PARSE_CHAR_ERROR_EMPTY_STRING` / `PARSE_CHAR_ERROR_TOO_MANY_CHARS` kind constants.
- `sa_std/char.sal`: Added `DecodeUtf16Error_SIZE` / `DecodeUtf16Error_unpaired_surrogate` and zero-sized `CharTryFromError` / `TryFromCharError` layout constants.
- Test: `tests/unit_framework/std_char_error_layout_macro_surface.sa` — 1 test (panic ID 10492) verifying the new char error layout constants.
- Validation status:
  - Focused: `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_char_error_layout_macro_surface.sa --jobs 1 --trace-panic` -> `1 passed; 0 failed; 0 skipped`.
- Panic IDs next free: 10493+.

## Completed: 2026-07-14 fmt Error and Result layout constants (Batch af)

- `sa_std/fmt.sal`: Added `FmtError_SIZE = 0` and `FmtError_ALIGN = 1`, mirroring Rust `std::fmt::Error` as a zero-sized error marker.
- `sa_std/fmt.sal`: Added `FmtResult_*` layout/tag aliases over the existing `Result` layout, representing `std::fmt::Result` as `Result<(), Error>` at the SA macro-layout level.
- Test: `tests/unit_framework/std_fmt_layout_macro_surface.sa` — 1 test (panic ID 10493) verifying fmt Error, fmt Result, and existing `SaFmtBuffer` layout constants.
- Validation status:
  - Focused: `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_fmt_layout_macro_surface.sa --jobs 1 --trace-panic` -> `1 passed; 0 failed; 0 skipped`.
- Panic IDs next free: 10494+.

## Completed: 2026-07-14 FFI and UTF-8 error layout constants (Batch ag)

- `sa_std/ffi.sal`: Added `NulError`, `FromBytesWithNulError`, `Utf8Error`, and `IntoStringError` layout constants over the existing `Vec`, `CString`, and CStr/UTF-8 validation status surfaces.
- `sa_std/ffi.sal`: Added `FROM_BYTES_WITH_NUL_ERROR_NOT_NUL_TERMINATED` / `INTERIOR_NUL` aliases to the current `CSTR_FROM_BYTES_*` status codes, plus `UTF8_ERROR_LEN_NONE` as the no-error-length sentinel.
- Test: `tests/unit_framework/std_ffi_error_layout_macro_surface.sa` — 1 test (panic ID 10494) verifying the new error layout constants and cross-checking against `Vec_SIZE`, `CString_SIZE`, and existing validation statuses.
- Validation status:
  - Focused: `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_ffi_error_layout_macro_surface.sa --jobs 1 --trace-panic` -> `1 passed; 0 failed; 0 skipped`.
- Panic IDs next free: 10495+.

## Completed: 2026-07-14 RefCell borrow error layout constants (Batch ah)

- `sa_std/core/refcell.sal`: Added zero-sized `BorrowError` and `BorrowMutError` layout constants (`SIZE=0`, `ALIGN=1`) mirroring Rust `std::cell` borrow error marker structs.
- Test: `tests/unit_framework/std_refcell_error_layout_macro_surface.sa` — 1 test (panic ID 10495) verifying the new error layout constants and cross-checking the existing `RefCellU64` layout.
- Validation status:
  - Focused: `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_refcell_error_layout_macro_surface.sa --jobs 1 --trace-panic` -> `1 passed; 0 failed; 0 skipped`.
- Panic IDs next free: 10496+.

## Completed: 2026-07-14 Panic location layout constants (Batch ai)

- `sa_std/core/panic.sal`: Added `PanicLocation_*` constants for Rust `Location` layout: file fat-pointer view at offset 0, line at offset 16, and column at offset 20.
- `sa_std/core/panic.sal`: Added concrete `AssertUnwindSafeU64_*` layout constants for the single-field `AssertUnwindSafe<T>` wrapper shape over `u64`.
- Test: `tests/unit_framework/std_panic_layout_macro_surface.sa` — 1 test (panic ID 10496) verifying the new panic layout constants.
- Validation status:
  - Focused: `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_panic_layout_macro_surface.sa --jobs 1 --trace-panic` -> `1 passed; 0 failed; 0 skipped`.
- Panic IDs next free: 10497+.

## Completed: 2026-07-14 String conversion error layout constants (Batch aj)

- `sa_std/string.sal`: Added `FromUtf8Error` layout constants over the existing `Vec` + `Utf8Error` surfaces, including `bytes` and `error` offsets.
- `sa_std/string.sal`: Added `FromUtf16Error` layout constants and strict UTF-16 error kind values for lone surrogate and odd byte input, plus zero-sized `ParseBoolError` layout constants.
- Test: `tests/unit_framework/std_string_error_layout_macro_surface.sa` — 1 test (panic ID 10497) verifying the new string/str error layout constants and cross-checking `FromUtf8Error_SIZE == Vec_SIZE + Utf8Error_SIZE`.
- Validation status:
  - Focused: `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_string_error_layout_macro_surface.sa --jobs 1 --trace-panic` -> `1 passed; 0 failed; 0 skipped`.
- Panic IDs next free: 10498+.

## Completed: 2026-07-14 Net address parse error layout constants (Batch ak)

- `sa_std/net.sal`: Added `AddrParseError` layout constants and parser-kind constants for Ip, Ipv4, Ipv6, Socket, SocketV4, and SocketV6 parse failures, mirroring Rust `std::net::AddrParseError`'s internal `AddrKind` categories at the SA layout level.
- Test: `tests/unit_framework/std_net_error_layout_macro_surface.sa` — 1 test (panic ID 10498) verifying the new net error layout constants.
- Validation status:
  - Focused: `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_net_error_layout_macro_surface.sa --jobs 1 --trace-panic` -> `1 passed; 0 failed; 0 skipped`.
- Panic IDs next free: 10499+.

## Completed: 2026-07-14 Float parse error layout constants (Batch al)

- `sa_std/num.sal`: Added `ParseFloatError` layout constants and `NUM_FLOAT_ERROR_EMPTY` / `NUM_FLOAT_ERROR_INVALID` kind constants, mirroring Rust `core::num::ParseFloatError`'s two `FloatErrorKind` categories at the SA layout level.
- Test: `tests/unit_framework/std_float_error_layout_macro_surface.sa` — 1 test (panic ID 10499) verifying the new float error layout constants.
- Validation status:
  - Focused: `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_float_error_layout_macro_surface.sa --jobs 1 --trace-panic` -> `1 passed; 0 failed; 0 skipped`.
- Panic IDs next free: 10500+.

## Completed: 2026-07-14 Alloc layout and error marker constants (Batch am)

- `sa_std/alloc/layout.sal`: Added `AllocLayout` layout constants for Rust `core::alloc::Layout` plus zero-sized `LayoutError` / `LayoutErr` and `AllocError` marker layout constants.
- Test: `tests/unit_framework/std_alloc_layout_macro_surface.sa` — 1 test (panic ID 10500) verifying the new alloc layout constants and cross-checking the layout size/alignment against `mem.sal`.
- Validation status:
  - Focused: `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_alloc_layout_macro_surface.sa --jobs 1 --trace-panic` -> `1 passed; 0 failed; 0 skipped`.
- Panic IDs next free: 10501+.

## Completed: 2026-07-14 MPSC error layout constants (Batch an)

- `sa_std/sync/mpsc.sal`: Added layout constants for `SendError<u64>`, `RecvError`, `TryRecvError`, `RecvTimeoutError`, and `TrySendError<u64>`, plus Rust mpsc error kind constants for Empty/Timeout/Full and Disconnected categories.
- Test: `tests/unit_framework/std_mpsc_error_layout_macro_surface.sa` — 1 test (panic ID 10501) verifying the new mpsc error layout constants.
- Validation status:
  - Focused: `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_mpsc_error_layout_macro_surface.sa --jobs 1 --trace-panic` -> `1 passed; 0 failed; 0 skipped`.
- Panic IDs next free: 10502+.

## Completed: 2026-07-14 SystemTimeError layout constants (Batch ao)

- `sa_std/time.sal`: Added `SystemTimeError` layout constants over the existing `Duration` layout, matching Rust `std::time::SystemTimeError(Duration)` at the SA macro-layout level.
- Test: `tests/unit_framework/std_time_error_layout_macro_surface.sa` — 1 test (panic ID 10502) verifying the new time error layout constants.
- Validation status:
  - Focused: `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_time_error_layout_macro_surface.sa --jobs 1 --trace-panic` -> `1 passed; 0 failed; 0 skipped`.
- Panic IDs next free: 10503+.

## Completed: 2026-07-14 Sync poison error layout constants (Batch ap)

- `sa_std/sync/poison.sal`: Added layout constants for `PoisonError<u64>` and `TryLockError<u64>`, plus Rust sync try-lock error kind constants for Poisoned and WouldBlock categories.
- Test: `tests/unit_framework/std_sync_poison_error_layout_macro_surface.sa` — 1 test (panic ID 10503) verifying the new sync poison error layout constants.
- Validation status:
  - Focused: `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_sync_poison_error_layout_macro_surface.sa --jobs 1 --trace-panic` -> `1 passed; 0 failed; 0 skipped`.
- Panic IDs next free: 10504+.

## Completed: 2026-07-14 Collections try-reserve error layout constants (Batch aq)

- `sa_std/collections.sal`: Added `TryReserveErrorKind` and `TryReserveError` layout constants, plus CapacityOverflow and AllocError kind constants over the existing `AllocLayout` payload.
- Test: `tests/unit_framework/std_collections_try_reserve_error_layout_macro_surface.sa` — 1 test (panic ID 10504) verifying the new collections error layout constants.
- Validation status:
  - Focused: `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_collections_try_reserve_error_layout_macro_surface.sa --jobs 1 --trace-panic` -> `1 passed; 0 failed; 0 skipped`.
- Panic IDs next free: 10505+.

## Completed: 2026-07-14 Ops ControlFlow layout and u64 macros (Batch ar)

- `sa_std/ops.sal`: Added `ControlFlowU64` layout constants plus Continue/Break discriminant constants, matching Rust `ControlFlow`'s variant order at the concrete SA layout level.
- `sa_std/ops.sa`: Added `CONTROL_FLOW_CONTINUE_U64`, `CONTROL_FLOW_BREAK_U64`, `CONTROL_FLOW_TAG`, `CONTROL_FLOW_VALUE_U64`, `CONTROL_FLOW_IS_CONTINUE`, and `CONTROL_FLOW_IS_BREAK`.
- Test: `tests/unit_framework/std_ops_control_flow_macro_surface.sa` — 1 test (panic ID 10505) verifying the new ops ControlFlow layout and u64 macros.
- Validation status:
  - Focused: `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_ops_control_flow_macro_surface.sa --jobs 1 --trace-panic` -> `1 passed; 0 failed; 0 skipped`.
- Panic IDs next free: 10506+.

## Completed: 2026-07-14 OnceState layout and poison query macros (Batch as)

- `sa_std/sync/once.sal`: Added `OnceState` layout constants and Linux/futex state constants for COMPLETE/RUNNING/POISONED/INCOMPLETE/QUEUED/MASK, matching the local Rust source's `std::sync::OnceState` backend view at the SA macro-layout level.
- `sa_std/sync/once.sa`: Added `ONCE_STATE_NEW`, `ONCE_STATE_IS_POISONED`, `ONCE_STATE_POISON`, and `ONCE_STATE_SET_STATE_TO`.
- Test: `tests/unit_framework/std_once_state_layout_macro_surface.sa` — 1 test (panic ID 10506) verifying the new OnceState layout and poison query/update macros.
- Validation status:
  - Focused: `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_once_state_layout_macro_surface.sa --jobs 1 --trace-panic` -> `1 passed; 0 failed; 0 skipped`.
- Panic IDs next free: 10507+.

## Completed: 2026-07-14 AtomicOrdering layout and validation macros (Batch at)

- `sa_std/sync/atomic.sal`: Added `AtomicOrdering` layout constants for the one-byte Rust `std::sync::atomic::Ordering` enum view.
- `sa_std/sync/atomic.sa`: Added `ATOMIC_ORDERING_NEW`, `ATOMIC_ORDERING_GET`, and validation predicates for load, store, compare-exchange failure, and fence orderings.
- Test: `tests/unit_framework/std_atomic_ordering_layout_macro_surface.sa` — 1 test (panic ID 10507) verifying the new AtomicOrdering layout and validation macros.
- Validation status:
  - Focused: `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_atomic_ordering_layout_macro_surface.sa --jobs 1 --trace-panic` -> `1 passed; 0 failed; 0 skipped`.
- Panic IDs next free: 10508+.

## Completed: 2026-07-14 Bound usize layout and macros (Batch au)

- `sa_std/ops.sal`: Added `BOUND_USIZE_UNBOUNDED` / `INCLUDED` / `EXCLUDED` aliases for Rust `core::ops::Bound` variant order over the existing `BoundUsize` layout constants.
- `sa_std/ops.sa`: Added `BOUND_USIZE_UNBOUNDED_NEW`, `BOUND_USIZE_INCLUDED_NEW`, `BOUND_USIZE_EXCLUDED_NEW`, tag/value accessors, variant predicates, start/end/range contains helpers, and `BOUND_USIZE_DEFAULT`.
- Test: `tests/unit_framework/std_ops_bound_usize_macro_surface.sa` — 1 test (panic ID 10508) verifying the new Bound<usize> layout and macro surface.
- Validation status:
  - Focused: `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_ops_bound_usize_macro_surface.sa --jobs 1 --trace-panic` -> `1 passed; 0 failed; 0 skipped`.
- Panic IDs next free: 10509+.

## Completed: 2026-07-14 Range usize macro aliases (Batch av)

- `sa_std/ops.sa`: Added `RANGE_USIZE_NEXT`, `NEXT_BACK`, `NTH`, `COUNT`, and `TRY_GET_SLICE` over the existing finite `Range<usize>` layout.
- `sa_std/ops.sa`: Added `RangeFrom`, `RangeTo`, `RangeInclusive`, and `RangeToInclusive` usize constructor/access/contains/slice-view aliases, plus inclusive finite cursor/count helpers and `RANGE_FULL_CONTAINS_USIZE`.
- Test: `tests/unit_framework/std_ops_range_usize_macro_surface.sa` — 1 test (panic ID 10509) verifying the new Range<usize> macro surface.
- Validation status:
  - Focused: `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_ops_range_usize_macro_surface.sa --jobs 1 --trace-panic` -> `1 passed; 0 failed; 0 skipped`.
- Panic IDs next free: 10510+.

## Completed: 2026-07-14 RangeInclusive into_inner macros (Batch aw)

- `sa_std/ops.sa`: Added `RANGE_INCLUSIVE_U64_INTO_INNER` and `RANGE_INCLUSIVE_USIZE_INTO_INNER`, returning the stored start/end pair for concrete RangeInclusive layouts.
- Test: `tests/unit_framework/std_ops_range_inclusive_inner_macro_surface.sa` — 1 test (panic ID 10510) verifying both u64 and usize into_inner surfaces.
- Validation status:
  - Focused: `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_ops_range_inclusive_inner_macro_surface.sa --jobs 1 --trace-panic` -> `1 passed; 0 failed; 0 skipped`.
- Panic IDs next free: 10511+.

## Completed: 2026-07-14 RangeBounds concrete macros (Batch ax)

- `sa_std/ops.sa`: Added concrete RangeBounds/IntoBounds-style `START_BOUND`, `END_BOUND`, and `INTO_BOUNDS` macros for RangeFull, Range, RangeFrom, RangeTo, RangeInclusive, and RangeToInclusive over `BoundU64` and `BoundUsize`.
- `sa_std/ops.sa`: RangeInclusive end-bound helpers return `Included(end)` while active and `Excluded(end)` after exhaustion, matching Rust's `RangeBounds` / `IntoBounds` behavior for exhausted inclusive ranges.
- Test: `tests/unit_framework/std_ops_range_bounds_macro_surface.sa` — 1 test (panic ID 10511) verifying u64 and usize bound extraction surfaces.
- Validation status:
  - Focused: `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_ops_range_bounds_macro_surface.sa --jobs 1 --trace-panic` -> `1 passed; 0 failed; 0 skipped`.
- Panic IDs next free: 10512+.

## Completed: 2026-07-14 Bound map/copy macros (Batch ay)

- `sa_std/ops.sa`: Added `BOUND_U64_COPY`, `BOUND_U64_COPIED`, `BOUND_U64_CLONED`, and `BOUND_U64_MAP`.
- `sa_std/ops.sa`: Added matching `Bound<usize>` copy/copied/cloned/map helpers over the current 64-bit SA usize layout.
- Test: `tests/unit_framework/std_ops_bound_map_macro_surface.sa` — 1 test (panic ID 10512) verifying tag preservation, payload mapping, copy aliases, and Unbounded callback bypass.
- Validation status:
  - Focused: `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_ops_bound_map_macro_surface.sa --jobs 1 --trace-panic` -> `1 passed; 0 failed; 0 skipped`.
- Panic IDs next free: 10513+.

## Completed: 2026-07-14 Bound range is_empty macros (Batch az)

- `sa_std/ops.sa`: Added `BOUND_U64_RANGE_IS_EMPTY` and `BOUND_USIZE_RANGE_IS_EMPTY`, mirroring Rust `RangeBounds::is_empty` bound-pair rules for concrete SA bound layouts.
- Test: `tests/unit_framework/std_ops_bound_range_empty_macro_surface.sa` — 1 test (panic ID 10513) verifying unbounded endpoints, inclusive equal bounds, exclusive equal bounds, and reversed ranges.
- Validation status:
  - Focused: `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_ops_bound_range_empty_macro_surface.sa --jobs 1 --trace-panic` -> `1 passed; 0 failed; 0 skipped`.
- Panic IDs next free: 10514+.

## Completed: 2026-07-14 Bound intersect macros (Batch ba)

- `sa_std/ops.sa`: Added `BOUND_U64_INTERSECT_START`, `BOUND_U64_INTERSECT_END`, `BOUND_U64_INTERSECT_RANGE`, and matching `BOUND_USIZE_INTERSECT_*` aliases over the current 64-bit SA usize layout.
- Semantics: these helpers mirror Rust `IntoBounds::intersect` for concrete bound pairs by selecting the stricter/larger lower bound for starts and stricter/smaller upper bound for ends; equal-value Included/Excluded pairs keep Excluded as the stricter edge.
- Test: `tests/unit_framework/std_ops_bound_intersect_macro_surface.sa` — 1 test (panic ID 10514) covering Rust's documented intersect examples over concrete unsigned ranges plus a usize range pair.
- Validation status:
  - Focused: `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_ops_bound_intersect_macro_surface.sa --jobs 1 --trace-panic` -> `1 passed; 0 failed; 0 skipped`.
- Panic IDs next free: 10515+.

## Completed: 2026-07-14 Bound ref macros (Batch bb)

- `sa_std/ops.sal`: Added `BoundU64Ref` and `BoundUsizeRef` tag+pointer layout constants for concrete `Bound<&u64>` / `Bound<&usize>` lowering.
- `sa_std/ops.sa`: Added `BOUND_U64_AS_REF`, `BOUND_U64_AS_MUT`, `BOUND_U64_REF_TAG`, `BOUND_U64_REF_PTR`, `BOUND_U64_REF_COPIED`, `BOUND_U64_REF_CLONED`, and matching `BOUND_USIZE_*` aliases/helpers.
- Semantics: Included/Excluded ref bounds point at the original payload slot, Unbounded uses a null payload, and ref copied/cloned reads the pointed-to `u64` back into a value bound. These helpers do not model Rust borrow lifetimes or aliasing rules.
- Test: `tests/unit_framework/std_ops_bound_ref_macro_surface.sa` — 1 test (panic ID 10515) covering layout constants, `as_ref`, `as_mut`, ref copied/cloned, Unbounded null payload, and usize aliases.
- Validation status:
  - Focused: `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_ops_bound_ref_macro_surface.sa --jobs 1 --trace-panic` -> `1 passed; 0 failed; 0 skipped`.
- Panic IDs next free: 10516+.

## Completed: 2026-07-14 ControlFlow method macros (Batch bc)

- `sa_std/ops.sa`: Added concrete `ControlFlow<u64, u64>` method helpers: `CONTROL_FLOW_BREAK_VALUE_U64`, `CONTROL_FLOW_CONTINUE_VALUE_U64`, `CONTROL_FLOW_BREAK_OK_U64`, `CONTROL_FLOW_CONTINUE_OK_U64`, `CONTROL_FLOW_MAP_BREAK_U64`, `CONTROL_FLOW_MAP_CONTINUE_U64`, and `CONTROL_FLOW_INTO_VALUE_U64`.
- Semantics: value helpers write existing `Option` layouts, ok helpers write existing `Result` layouts, map helpers call a `u64 -> u64` callback only for the targeted variant, and `into_value` exposes the shared u64 payload for the same-payload concrete subset.
- Test: `tests/unit_framework/std_ops_control_flow_methods_macro_surface.sa` — 1 test (panic ID 10516) covering value/result conversion, map passthrough behavior, targeted callback behavior, and into_value.
- Validation status:
  - Focused: `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_ops_control_flow_methods_macro_surface.sa --jobs 1 --trace-panic` -> `1 passed; 0 failed; 0 skipped`.
- Panic IDs next free: 10517+.

## Completed: 2026-07-14 Convert identity macros (Batch bd)

- `sa_std/convert.sa`: Added concrete primitive `std::convert::identity` lowering macros for `u64`, `i64`, `usize`, and `bool`, plus Rust-named `IDENTITY_*` aliases.
- Semantics: helpers copy the input register to the output register unchanged for the concrete primitive subset; they do not claim Rust's generic `identity<T>` function item or trait wiring.
- Test: `tests/unit_framework/std_convert_identity_macro_surface.sa` — 1 test (panic ID 10517) covering direct `CONVERT_IDENTITY_*` macros and `IDENTITY_*` aliases.
- Validation status:
  - Focused: `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_convert_identity_macro_surface.sa --jobs 1 --trace-panic` -> `1 passed; 0 failed; 0 skipped`.
- Panic IDs next free: 10518+.

## Completed: 2026-07-14 Array rsplit macros (Batch be)

- `sa_std/array.sa`: Added `ARRAY_TRY_RSPLIT_ARRAY_REF_U64` and `ARRAY_TRY_RSPLIT_ARRAY_MUT_U64`, the right-split counterparts to the existing concrete split-array helpers.
- Semantics: helpers return `(ok, prefix_slice, suffix_slice)` over caller-owned `u64` storage, with suffix length chosen from the end. `suffix_len > length` returns `ok=0` and empty slice views instead of Rust's panic.
- Test: `tests/unit_framework/std_array_rsplit_macro_surface.sa` — 1 test (panic ID 10518) covering suffix lengths 0, 2, and full length, mutable suffix writes, and oversize failure.
- Validation status:
  - Focused: `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_array_rsplit_macro_surface.sa --jobs 1 --trace-panic` -> `1 passed; 0 failed; 0 skipped`.
- Panic IDs next free: 10519+.

## Completed: 2026-07-14 Array ref/borrow aliases (Batch bf)

- `sa_std/array.sa`: Added concrete u64 array slice-view aliases for Rust array `AsRef<[T]>`, `AsMut<[T]>`, `Borrow<[T]>`, and `BorrowMut<[T]>` lowering: `ARRAY_AS_REF_SLICE_U64`, `ARRAY_AS_MUT_REF_SLICE_U64`, `ARRAY_BORROW_SLICE_U64`, and `ARRAY_BORROW_MUT_SLICE_U64`.
- Semantics: aliases materialize the same `Slice` views as `ARRAY_AS_SLICE_U64` / `ARRAY_AS_MUT_SLICE_U64`; they do not implement generic trait dispatch or borrow lifetimes.
- Test: `tests/unit_framework/std_array_ref_borrow_macro_surface.sa` — 1 test (panic ID 10519) covering pointer/length preservation and mutable slice writes through AsMut/BorrowMut aliases.
- Validation status:
  - Focused: `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_array_ref_borrow_macro_surface.sa --jobs 1 --trace-panic` -> `1 passed; 0 failed; 0 skipped`.
- Panic IDs next free: 10520+.

## Completed: 2026-07-14 Array try_from slice aliases (Batch bg)

- `sa_std/array.sa`: Added concrete u64 array `TryFrom<&[T]>` / `TryFrom<&mut [T]>` copy aliases, `ARRAY_TRY_FROM_SLICE_U64` and `ARRAY_TRY_FROM_MUT_SLICE_U64`, over the existing same-length copy helper.
- Semantics: aliases copy the input slice into caller-owned array storage only when the slice length equals the requested array length; mismatches return `ok=0` instead of materializing Rust's `Result<_, TryFromSliceError>`.
- Test: `tests/unit_framework/std_array_try_from_slice_macro_surface.sa` — 1 test (panic ID 10520) covering immutable and mutable slice success plus short/long length mismatch failures.
- Validation status:
  - Focused: `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_array_try_from_slice_macro_surface.sa --jobs 1 --trace-panic` -> `1 passed; 0 failed; 0 skipped`.
- Panic IDs next free: 10521+.

## Completed: 2026-07-14 Array ref try_from slice aliases (Batch bh)

- `sa_std/array.sa`: Added concrete u64 array-reference `TryFrom<&[T]>` / `TryFrom<&mut [T]>` aliases, `ARRAY_REF_TRY_FROM_SLICE_U64` and `ARRAY_MUT_REF_TRY_FROM_MUT_SLICE_U64`, over the existing exact-length `Slice` view helpers.
- Semantics: aliases return `(ok, Slice)` views when the source slice length equals the requested array length; mismatches return `ok=0` and an empty view instead of Rust's `Result<_, TryFromSliceError>`.
- Test: `tests/unit_framework/std_array_ref_try_from_slice_macro_surface.sa` — 1 test (panic ID 10521) covering immutable and mutable exact-length views, mutable write-through, and length mismatch failures.
- Validation status:
  - Focused: `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_array_ref_try_from_slice_macro_surface.sa --jobs 1 --trace-panic` -> `1 passed; 0 failed; 0 skipped`.
- Panic IDs next free: 10522+.

## Completed: 2026-07-14 Array default macros (Batch bi)

- `sa_std/array.sa`: Added concrete primitive array default fill helpers for `u64`, `i64`, `usize`, and `bool` arrays, plus Rust-named `DEFAULT_ARRAY_*` aliases.
- Semantics: helpers fill caller-owned array storage with the concrete primitive default value (`0`), modeling the common `[T; N]::default()` lowering shape without implementing Rust's generic `Default for [T; N]` trait.
- Test: `tests/unit_framework/std_array_default_macro_surface.sa` — 1 test (panic ID 10522) covering direct `ARRAY_DEFAULT_*` helpers and `DEFAULT_ARRAY_*` aliases.
- Validation status:
  - Focused: `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_array_default_macro_surface.sa --jobs 1 --trace-panic` -> `1 passed; 0 failed; 0 skipped`.
- Panic IDs next free: 10523+.

## Completed: 2026-07-14 Array clone/copy aliases (Batch bj)

- `sa_std/array.sa`: Added concrete u64 array clone/copy aliases: `ARRAY_CLONE_U64`, `ARRAY_CLONE_FROM_U64`, and `ARRAY_COPY_FROM_U64`.
- Semantics: helpers copy caller-owned contiguous `u64` storage, modeling Rust array `Clone` / `Copy` lowering for trivially copied concrete elements without implementing generic trait dispatch.
- Test: `tests/unit_framework/std_array_clone_macro_surface.sa` — 1 test (panic ID 10523) covering clone, clone_from, and copy_from aliases.
- Validation status:
  - Focused: `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_array_clone_macro_surface.sa --jobs 1 --trace-panic` -> `1 passed; 0 failed; 0 skipped`.
- Panic IDs next free: 10524+.

## Completed: 2026-07-14 Array equality aliases (Batch bk)

- `sa_std/array.sa`: Added concrete u64 array equality aliases: `ARRAY_EQ_U64`, `ARRAY_NE_U64`, and `ARRAY_PARTIAL_EQ_U64`.
- Semantics: helpers compare equal-length caller-owned `u64` array storage through existing `Slice` equality, modeling Rust array `PartialEq` / `Eq` lowering for concrete arrays without generic trait dispatch.
- Test: `tests/unit_framework/std_array_eq_macro_surface.sa` — 1 test (panic ID 10524) covering equality, inequality, and partial-eq aliases.
- Validation status:
  - Focused: `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_array_eq_macro_surface.sa --jobs 1 --trace-panic` -> `1 passed; 0 failed; 0 skipped`.
- Panic IDs next free: 10525+.

## Completed: 2026-07-14 Array ordering aliases (Batch bl)

- `sa_std/array.sa`: Added concrete u64 array ordering aliases: `ARRAY_CMP_U64`, `ARRAY_PARTIAL_CMP_U64`, `ARRAY_LT_U64`, `ARRAY_LE_U64`, `ARRAY_GT_U64`, and `ARRAY_GE_U64`.
- Semantics: helpers compare equal-length caller-owned `u64` array storage lexicographically through existing `Slice` comparison, modeling Rust array `PartialOrd` / `Ord` lowering for concrete arrays without generic trait dispatch or `Option<Ordering>` object modeling.
- Test: `tests/unit_framework/std_array_cmp_macro_surface.sa` — 1 test (panic ID 10525) covering comparison ordering and boolean relation aliases.
- Validation status:
  - Focused: `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_array_cmp_macro_surface.sa --jobs 1 --trace-panic` -> `1 passed; 0 failed; 0 skipped`.
- Panic IDs next free: 10526+.

## Completed: 2026-07-14 Array index aliases (Batch bm)

- `sa_std/array.sa`: Added concrete u64 array `Index` / `IndexMut` aliases: `ARRAY_INDEX_U64` and `ARRAY_INDEX_MUT_PTR_U64`.
- Semantics: helpers delegate to the existing concrete element-load and mutable-pointer helpers, modeling Rust array indexing lowering to slice indexing for concrete `u64` arrays without generic index types, borrow lifetimes, or bounds-check panic modeling.
- Test: `tests/unit_framework/std_array_index_macro_surface.sa` — 1 test (panic ID 10526) covering immutable index reads and mutable index pointer writes.
- Validation status:
  - Focused: `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_array_index_macro_surface.sa --jobs 1 --trace-panic` -> `1 passed; 0 failed; 0 skipped`.
- Panic IDs next free: 10527+.

## Completed: 2026-07-14 Array iterator aliases (Batch bn)

- `sa_std/array.sa`: Added concrete u64 array iterator construction aliases: `ARRAY_ITER_U64`, `ARRAY_ITER_MUT_U64`, `ARRAY_REF_INTO_ITER_U64`, and `ARRAY_MUT_REF_INTO_ITER_U64`.
- Semantics: helpers wrap caller-owned `u64` array storage as slice views and construct the existing concrete value-yielding `Iter`, modeling Rust array-reference `IntoIterator` lowering to slice iterators without by-value `array::IntoIter`, reference item types, mutable item references, or lifetime semantics.
- Test: `tests/unit_framework/std_array_iter_macro_surface.sa` — 1 test (panic ID 10527) covering iter, iter_mut, ref into_iter, mut-ref into_iter, remaining slice, next, and next_back behavior.
- Validation status:
  - Focused: `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_array_iter_macro_surface.sa --jobs 1 --trace-panic` -> `1 passed; 0 failed; 0 skipped`.
- Panic IDs next free: 10528+.

## Completed: 2026-07-14 Array hash aliases (Batch bo)

- `sa_std/array.sa`: Added concrete u64 array hash aliases: `DEFAULT_HASHER_WRITE_ARRAY_U64` and `ARRAY_HASH_U64`.
- Semantics: helpers wrap caller-owned `u64` array storage as a slice and delegate to existing slice hashing, modeling Rust array `Hash` lowering to slice hashing for the deterministic SA `DefaultHasher` subset without generic `Hash` trait dispatch or randomized hasher behavior.
- Test: `tests/unit_framework/std_array_hash_macro_surface.sa` — 1 test (panic ID 10528) covering direct array hash, slice hash equivalence, and hasher-write equivalence.
- Validation status:
  - Focused: `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_array_hash_macro_surface.sa --jobs 1 --trace-panic` -> `1 passed; 0 failed; 0 skipped`.
- Panic IDs next free: 10529+.

## Completed: 2026-07-14 BuildHasher hash_one helpers (Batch bp)

- `sa_std/hash.sa`: Added concrete `BuildHasher::hash_one`-style helpers for the existing deterministic builder: `BUILD_HASHER_DEFAULT_HASH_ONE_U64`, `BUILD_HASHER_DEFAULT_HASH_ONE_STR`, `BUILD_HASHER_DEFAULT_HASH_ONE_SLICE_U8`, and `BUILD_HASHER_DEFAULT_HASH_ONE_SLICE_U64`.
- Semantics: helpers build a fresh SA `DefaultHasher`, write exactly one concrete value/slice using the same write path as the direct hash helper, and return `finish`, modeling Rust's default `BuildHasher::hash_one` shape without generic `Hash` dispatch or randomized hasher behavior.
- Test: `tests/unit_framework/std_hash_build_hasher_hash_one_macro_surface.sa` — 1 test (panic ID 10529) covering u64, str, u8 slice, u64 slice, and str-vs-byte-slice domain separation.
- Validation status:
  - Focused: `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_hash_build_hasher_hash_one_macro_surface.sa --jobs 1 --trace-panic` -> `1 passed; 0 failed; 0 skipped`.
- Panic IDs next free: 10530+.

## Completed: 2026-07-14 Hasher signed write aliases (Batch bq)

- `sa_std/hash.sa`: Added concrete signed `Hasher` write aliases: `DEFAULT_HASHER_WRITE_I8`, `DEFAULT_HASHER_WRITE_I16`, `DEFAULT_HASHER_WRITE_I32`, and `DEFAULT_HASHER_WRITE_ISIZE`.
- Semantics: aliases mirror Rust's default `Hasher::write_i8` / `write_i16` / `write_i32` / `write_isize` forwarding shape by delegating to the corresponding unsigned SA write helper, within the current deterministic register-sized hasher model.
- Test: `tests/unit_framework/std_hash_signed_write_macro_surface.sa` — 1 test (panic ID 10530) covering signed write aliases against matching unsigned write paths.
- Validation status:
  - Focused: `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_hash_signed_write_macro_surface.sa --jobs 1 --trace-panic` -> `1 passed; 0 failed; 0 skipped`.
- Panic IDs next free: 10531+.

## Completed: 2026-07-14 BuildHasherDefault trait aliases (Batch br)

- `sa_std/hash.sa`: Added concrete zero-sized `BuildHasherDefault` trait aliases: `BUILD_HASHER_DEFAULT_CLONE`, `BUILD_HASHER_DEFAULT_COPY`, `BUILD_HASHER_DEFAULT_EQ`, and `BUILD_HASHER_DEFAULT_NE`.
- Semantics: helpers model Rust's `Clone` and `PartialEq` / `Eq` behavior for the zero-sized `BuildHasherDefault<H>` marker by recreating the zero marker and treating any two concrete builders as equal; they do not model generic `H` type parameters or `Debug` formatting.
- Test: `tests/unit_framework/std_hash_build_hasher_default_traits_macro_surface.sa` — 1 test (panic ID 10531) covering clone/copy/default zero marker behavior, equality/inequality, and build consistency.
- Validation status:
  - Focused: `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_hash_build_hasher_default_traits_macro_surface.sa --jobs 1 --trace-panic` -> `1 passed; 0 failed; 0 skipped`.
- Panic IDs next free: 10532+.
