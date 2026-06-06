# sa_std vs. Rust std: Interface Comparison Report

This document provides a 1:1 interface comparison between the current `sa_std` implementation in the `sci` project and the Rust standard library (`std`).

## Summary of Implementation Parity

`sa_std` uses a hybrid paradigm of `@extern` / `@export` functions and `[MACRO]` assembly macros, whereas Rust uses a high-level Trait, Struct, and Module system.

## Scope and Plugin Boundary

This report counts only the compiler-shipped standard library surface under `sa_std/` and the in-tree runtime ABI that those files import directly. External `sa_plugin_*` projects are intentionally excluded from `sa_std` parity, even when they expose familiar std-like APIs through `.sai` / `.sal` files.

Plugin capabilities are installable and uninstallable at any time, so they must not be used as evidence that a Rust `std` API is implemented by compiler std. When a capability has moved to a plugin, this document records it as a **plugin alternative** or **plugin-only** surface and keeps the corresponding Rust `std` gap open for `sa_std` unless an in-tree `sa_std/` module provides that API.

Current external capability buckets that should stay outside this report's `sa_std` implemented counts:

- `sa_plugin_deno`: Deno compatibility facade for env/args, fs, io, net, process, time, JSON/text/base64, and Responses/Chat compatibility helpers.
- `sa_plugin_http_client` / `sa_plugin_http_server`: HTTP request/response/client/server facade; Rust `std` has no high-level HTTP module, so these are ecosystem capabilities, not std parity.
- `sa_plugin_db`, `sa_plugin_sax`, `sa_plugin_wgpu`, `sa_plugin_3dengines`: database, XML/SAX, GPU, and 3D engine native capabilities; these are plugin domains, not compiler std.
- `sa_plugin_pkg`, `sa_plugin_bc2sa`, `sa_plugin_node`, `sa_plugin_ts`, `sa_plugin_vm`: package/toolchain/runtime integration plugins; these are host or ecosystem extensions, not `sa_std` APIs.

`sa_std` tests should therefore avoid reading `../sa_plugins/...` or depending on `$SA_PLUGINS_HOME` state. Plugin smoke coverage belongs with the plugin or plugin-host test suite.

---

## 1. Partially Implemented Modules

### 1.1 Vector (`std::vec::Vec` vs `sa_std/vec.sa`)
*   **Implemented in `sa_std`**: `VEC_NEW` / `sa_vec_new`, `VEC_WITH_CAPACITY`, `VEC_TRY_WITH_CAPACITY`, `VEC_FREE` / `sa_vec_free`, `VEC_LEN`, `VEC_CAPACITY`, `VEC_IS_EMPTY`, `VEC_AS_PTR`, `VEC_AS_MUT_PTR`, `VEC_AS_SLICE`, `VEC_AS_MUT_SLICE`, `VEC_GET`, `VEC_GET_U64`, `VEC_TRY_GET`, `VEC_TRY_GET_U64`, `VEC_FRONT`, `VEC_BACK`, `VEC_TRY_FRONT`, `VEC_TRY_FRONT_U64`, `VEC_TRY_BACK`, `VEC_TRY_BACK_U64`, `VEC_PUSH`, `VEC_PUSH_U64`, `VEC_PUSH_WITHIN_CAPACITY`, `VEC_PUSH_WITHIN_CAPACITY_U64`, `VEC_RESERVE`, `VEC_RESERVE_U64`, `VEC_RESERVE_EXACT`, `VEC_RESERVE_EXACT_U64`, `VEC_TRY_RESERVE`, `VEC_TRY_RESERVE_U64`, `VEC_TRY_RESERVE_EXACT`, `VEC_TRY_RESERVE_EXACT_U64`, `VEC_SHRINK_TO`, `VEC_SHRINK_TO_U64`, `VEC_TRY_SHRINK_TO`, `VEC_TRY_SHRINK_TO_U64`, `VEC_SHRINK_TO_FIT`, `VEC_SHRINK_TO_FIT_U64`, `VEC_TRY_SHRINK_TO_FIT`, `VEC_TRY_SHRINK_TO_FIT_U64`, `VEC_TRY_POP`, `VEC_TRY_POP_IF_U64`, `VEC_POP_IF_U64`, `VEC_POP`, `VEC_CLEAR`, `VEC_TRUNCATE`, `VEC_SET_LEN`, `VEC_CONTAINS_U64`, `VEC_STARTS_WITH_U64`, `VEC_ENDS_WITH_U64`, `VEC_TRY_STRIP_PREFIX_U64`, `VEC_TRY_STRIP_SUFFIX_U64`, `VEC_TRIM_PREFIX_U64`, `VEC_TRIM_SUFFIX_U64`, `VEC_TRY_SPLIT_AT_U64`, `VEC_EXTEND_FROM_SLICE`, `VEC_EXTEND_FROM_SLICE_U64`, `VEC_TRY_EXTEND_FROM_WITHIN_U64`, `VEC_EXTEND_FROM_WITHIN_U64`, `VEC_APPEND`, `VEC_APPEND_U64`, `VEC_TRY_INSERT`, `VEC_TRY_INSERT_U64`, `VEC_INSERT`, `VEC_INSERT_U64`, `VEC_TRY_SWAP_REMOVE`, `VEC_TRY_SWAP_REMOVE_U64`, `VEC_SWAP_REMOVE`, `VEC_SWAP_REMOVE_U64`, `VEC_TRY_REMOVE`, `VEC_TRY_REMOVE_U64`, `VEC_REMOVE`, `VEC_REMOVE_U64`, `VEC_TRY_SPLIT_OFF`, `VEC_TRY_SPLIT_OFF_U64`, `VEC_RESIZE`, `VEC_RESIZE_U64`, `VEC_DEDUP_U64`.
*   **Missing from Rust**: `retain`, `retain_mut`, `dedup_by`, `dedup_by_key`, `drain`, `splice`, `extract_if`, and `resize_with`.
*   **Scope note**: `VEC_APPEND*` appends by copying the source vector's current slice view into the destination and then clearing the source length. `VEC_EXTEND_FROM_SLICE*` copies from a caller-provided slice view. `VEC_TRY_EXTEND_FROM_WITHIN_U64` checks a concrete `(start, length)` range, reserves capacity before re-reading the source slice, and copies the in-range `u64` window. `VEC_TRY_POP_IF_U64` checks the current last `u64` with a caller-supplied predicate function and only pops when it returns nonzero. `VEC_SWAP_REMOVE*`, `VEC_TRY_INSERT*`, and `VEC_DEDUP_U64` currently target the concrete `u64`/8-byte element layout used by this SA vec surface.
*   **Missing Infrastructure**: Iterator support (`IntoIterator`, `iter()`, `iter_mut()`).
*   **Scope note**: `VEC_RESERVE_EXACT*` maps to the current exact-growth reserve implementation; the allocator may still choose physical allocation details outside the SA surface. The strip helpers return `u64` slice views over the vector data rather than allocating or copying.

### 1.1a Slice (`core::slice` vs `sa_std/core/slice.sa`)
*   **Implemented in `sa_std`**: `SLICE_NEW`, `SLICE_GET_PTR`, `SLICE_AS_PTR`, `SLICE_GET_LEN`, `SLICE_IS_EMPTY`, `SLICE_GET_U64`, `SLICE_GET_MUT_PTR_U64`, `SLICE_FIRST_U64`, `SLICE_FIRST_MUT_PTR_U64`, `SLICE_LAST_U64`, `SLICE_LAST_MUT_PTR_U64`, `SLICE_TRY_FIRST_U64`, `SLICE_TRY_LAST_U64`, `SLICE_TRY_GET_U64`, `SLICE_TRY_GET_MUT_PTR_U64`, `SLICE_TRY_FIRST_MUT_PTR_U64`, `SLICE_TRY_LAST_MUT_PTR_U64`, `SLICE_CONTAINS_U64`, `SLICE_STARTS_WITH_U64`, `SLICE_ENDS_WITH_U64`, `SLICE_TRY_STRIP_PREFIX_U64`, `SLICE_TRY_STRIP_SUFFIX_U64`, `SLICE_TRIM_PREFIX_U64`, `SLICE_TRIM_SUFFIX_U64`, `SLICE_TRY_SPLIT_AT_U64`, `SLICE_TRY_SPLIT_AT_MUT_U64`, `SLICE_TRY_RANGE_U64`, `SLICE_TRY_GET_RANGE_U64`, `SLICE_SWAP_U64`, `SLICE_TRY_SWAP_U64`, `SLICE_FILL_U64`, `SLICE_REVERSE_U64`, `SLICE_COPY_FROM_SLICE_U64`, `SLICE_CLONE_FROM_SLICE_U64`, `SLICE_COPY_WITHIN_U64`, `SLICE_TRY_BINARY_SEARCH_U64`.
*   **Missing from Rust**: generic element support, scoped Rust-reference `first_mut` / `last_mut` semantics, generic range-based `get`, split/chunk/window iterators, unchecked split variants, sorting, and iterator APIs.
*   **Scope note**: Current slice comparison, mutation, copy, range-view, split-view, and search helpers are concrete `u64` helpers. Mutable helpers return raw element pointers for verifier-friendly in-place updates; they intentionally do not pretend to be Rust's generic `[T]` trait surface or borrow-scoped reference semantics.

### 1.1b ASCII (`std::ascii` / `u8` ASCII methods vs `sa_std/ascii.sa`)
*   **Implemented in `sa_std`**: `ASCII_IS_ASCII`, `ASCII_IS_UPPERCASE`, `ASCII_IS_LOWERCASE`, `ASCII_IS_ALPHABETIC`, `ASCII_IS_ALPHANUMERIC`, `ASCII_IS_DIGIT`, `ASCII_IS_OCTDIGIT`, `ASCII_IS_HEXDIGIT`, `ASCII_IS_PUNCTUATION`, `ASCII_IS_GRAPHIC`, `ASCII_IS_WHITESPACE`, `ASCII_IS_CONTROL`, `ASCII_TO_UPPERCASE`, `ASCII_TO_LOWERCASE`, `ASCII_EQ_IGNORE_CASE`, `ASCII_BYTE_MAKE_UPPERCASE`, `ASCII_BYTE_MAKE_LOWERCASE`, `ASCII_SLICE_MAKE_UPPERCASE`, `ASCII_SLICE_MAKE_LOWERCASE`, `ASCII_SLICE_EQ_IGNORE_CASE`.
*   **Missing from Rust**: `std::ascii::Char` enum API, `escape_default` / `EscapeDefault` iterator, array/slice `as_ascii` typed views, Rust trait impls, char/str/OsStr owned allocation-returning conversions, and Unicode-aware non-ASCII case mapping.
*   **Scope note**: The SA ASCII facade is a byte-level contract over `u8` values and mutable `Slice` bytes. It follows Rust's ASCII ranges, including WhatWG ASCII whitespace (`TAB`, `LF`, `FF`, `CR`, `SPACE`) and no vertical tab. In-place slice helpers mutate caller-owned bytes and do not allocate owned `String` / `Vec` results.

### 1.2 Deque (`std::collections::VecDeque` vs `sa_std/vec_deque.sa`)
*   **Implemented in `sa_std`**: `VEC_DEQUE_NEW`, `VEC_DEQUE_WITH_CAPACITY`, `VEC_DEQUE_TRY_WITH_CAPACITY`, `VEC_DEQUE_FREE`, `VEC_DEQUE_LEN`, `VEC_DEQUE_CAPACITY`, `VEC_DEQUE_IS_EMPTY`, `VEC_DEQUE_GET`, `VEC_DEQUE_TRY_GET`, `VEC_DEQUE_TRY_GET_U64`, `VEC_DEQUE_TRY_GET_MUT_PTR`, `VEC_DEQUE_TRY_FRONT_MUT_PTR`, `VEC_DEQUE_TRY_BACK_MUT_PTR`, `VEC_DEQUE_SET`, `VEC_DEQUE_CONTAINS_U64`, `VEC_DEQUE_SWAP`, `VEC_DEQUE_TRY_INSERT`, `VEC_DEQUE_INSERT`, `VEC_DEQUE_TRY_REMOVE`, `VEC_DEQUE_REMOVE`, `VEC_DEQUE_TRY_SWAP_REMOVE_FRONT`, `VEC_DEQUE_SWAP_REMOVE_FRONT`, `VEC_DEQUE_TRY_SWAP_REMOVE_BACK`, `VEC_DEQUE_SWAP_REMOVE_BACK`, `VEC_DEQUE_PUSH_BACK`, `VEC_DEQUE_PUSH_FRONT`, `VEC_DEQUE_TRY_POP_FRONT`, `VEC_DEQUE_TRY_POP_BACK`, `VEC_DEQUE_FRONT`, `VEC_DEQUE_TRY_FRONT`, `VEC_DEQUE_BACK`, `VEC_DEQUE_TRY_BACK`, `VEC_DEQUE_CLEAR`, `VEC_DEQUE_RESERVE`, `VEC_DEQUE_RESERVE_EXACT`, `VEC_DEQUE_TRY_RESERVE`, `VEC_DEQUE_TRY_RESERVE_EXACT`, `VEC_DEQUE_SHRINK_TO`, `VEC_DEQUE_SHRINK_TO_FIT`, `VEC_DEQUE_TRY_SHRINK_TO`, `VEC_DEQUE_TRY_SHRINK_TO_FIT`, `VEC_DEQUE_AS_SLICES`, `VEC_DEQUE_AS_MUT_SLICES`, `VEC_DEQUE_MAKE_CONTIGUOUS`, `VEC_DEQUE_TRUNCATE`, `VEC_DEQUE_ROTATE_LEFT`, `VEC_DEQUE_ROTATE_RIGHT`, `VEC_DEQUE_TRY_SPLIT_OFF`, `VEC_DEQUE_APPEND`.
*   **Missing from Rust**: generic element support, allocator-aware constructors, iterator APIs (`iter`, `iter_mut`, `into_iter`, `drain`, `splice`), `front_mut` / `back_mut` as scoped Rust references, `pop_front_if`, `pop_back_if`, `push_front_mut`, `push_back_mut`, `insert_mut`, `retain`, `retain_mut`, and true allocation-failure reporting for `try_*` capacity helpers.
*   **Scope note**: The SA deque remains a concrete `u64` circular-buffer facade. `AS_SLICES` / `AS_MUT_SLICES` expose one or two internal contiguous `Slice` views, `MAKE_CONTIGUOUS` reorders storage to `head == 0` when wrapped, and `TRY_*_MUT_PTR` returns raw slot pointers for verifier-friendly in-place updates. These are not Rust's borrow-scoped reference, generic, iterator, or allocator error semantics.

### 1.3 Hash Map (`std::collections::HashMap` vs `sa_std/hashmap.sa`)
*   **Implemented in `sa_std`**: `MAP_NEW`, `MAP_WITH_CAPACITY`, `MAP_TRY_WITH_CAPACITY`, `MAP_FREE`, `MAP_LEN`, `MAP_CAPACITY`, `MAP_RESERVE`, `MAP_TRY_RESERVE`, `MAP_SHRINK_TO`, `MAP_SHRINK_TO_FIT`, `MAP_IS_EMPTY`, `MAP_CONTAINS_KEY`, `MAP_CLEAR`, `MAP_PUT`, `MAP_GET`, `MAP_TRY_GET`, `MAP_GET_KEY_VALUE`, `MAP_GET_MUT_PTR`, `MAP_TRY_GET_DISJOINT_MUT_PTRS`, `MAP_INSERT`, `MAP_TRY_INSERT`, `MAP_DEL`, `MAP_REMOVE_ENTRY`, `MAP_KEYS`, `MAP_VALUES`, `MAP_VALUES_MUT_PTRS`, `MAP_LIT2`.
*   **Missing from Rust**: `iter`, `iter_mut`, `drain`, `retain`, `extract_if`, `entry` API (Vacant/Occupied), full N-key scoped `get_disjoint_mut`, owned `into_keys` / `into_values`, generic hash/build-hasher support, and allocator-aware constructors.
*   **Scope note**: The SA map remains a concrete pointer-key / pointer-value open-addressing map. `MAP_INSERT` returns an old-value flag plus old value, `MAP_TRY_INSERT` returns an inserted flag plus the stored value-slot pointer, `MAP_REMOVE_ENTRY` returns stored key/value pointers, `MAP_GET_MUT_PTR` returns the slot pointer containing the stored value pointer, and `MAP_TRY_GET_DISJOINT_MUT_PTRS` only covers two distinct pointer keys. `MAP_KEYS`, `MAP_VALUES`, and `MAP_VALUES_MUT_PTRS` materialize `Vec<u64>` views of key pointer bits, value pointer bits, or raw value-slot pointer bits; they are not Rust iterator or scoped borrow semantics.

### 1.4 Hash Set (`std::collections::HashSet` vs `sa_std/hashset.sa`)
*   **Implemented in `sa_std`**: `SET_NEW`, `SET_WITH_CAPACITY`, `SET_TRY_WITH_CAPACITY`, `SET_FREE`, `SET_LEN`, `SET_CAPACITY`, `SET_RESERVE`, `SET_TRY_RESERVE`, `SET_SHRINK_TO`, `SET_SHRINK_TO_FIT`, `SET_IS_EMPTY`, `SET_CLEAR`, `SET_INSERT`, `SET_CONTAINS`, `SET_GET`, `SET_REPLACE`, `SET_TAKE`, `SET_REMOVE`, `SET_IS_DISJOINT`, `SET_IS_SUBSET`, `SET_IS_SUPERSET`, `SET_UNION`, `SET_INTERSECTION`, `SET_DIFFERENCE`, `SET_SYMMETRIC_DIFFERENCE`, `SET_LIT2`.
*   **Missing from Rust**: `iter`, `drain`, `retain`, `extract_if`, entry/get-or-insert APIs, bit-operator set algebra adapters, generic hash/build-hasher support, and allocator-aware constructors.
*   **Scope note**: The SA set is the pointer-key subset implemented over `sa_std/hashmap.sa` with a sentinel value. `SET_GET`, `SET_TAKE`, and `SET_REPLACE` return stored key pointers; equality is pointer identity. Set relation helpers scan the current slot table and call `SET_CONTAINS` on the opposite set. `SET_UNION`, `SET_INTERSECTION`, `SET_DIFFERENCE`, and `SET_SYMMETRIC_DIFFERENCE` materialize new SA sets instead of returning Rust lazy iterator adapters.

### 1.5 B-Tree Map (`std::collections::BTreeMap` vs `sa_std/btree_map.sa`)
*   **Implemented in `sa_std`**: `BTREE_MAP_NEW`, `BTREE_MAP_FREE`, `BTREE_MAP_LEN`, `BTREE_MAP_IS_EMPTY`, `BTREE_MAP_GET`, `BTREE_MAP_TRY_GET`, `BTREE_MAP_GET_KEY_VALUE`, `BTREE_MAP_GET_MUT_PTR`, `BTREE_MAP_FIRST_ENTRY_MUT_PTR`, `BTREE_MAP_LAST_ENTRY_MUT_PTR`, `BTREE_MAP_TRY_GET_DISJOINT_MUT_PTRS`, `BTREE_MAP_FIRST_KEY_VALUE`, `BTREE_MAP_LAST_KEY_VALUE`, `BTREE_MAP_CONTAINS_KEY`, `BTREE_MAP_CLEAR`, `BTREE_MAP_REMOVE`, `BTREE_MAP_REMOVE_ENTRY`, `BTREE_MAP_INSERT`, `BTREE_MAP_INSERT_OLD`, `BTREE_MAP_TRY_INSERT`, `BTREE_MAP_KEYS`, `BTREE_MAP_VALUES`, `BTREE_MAP_VALUES_MUT_PTRS`, `BTREE_MAP_POP_FIRST`, `BTREE_MAP_POP_LAST`, `BTREE_MAP_APPEND`, `BTREE_MAP_SPLIT_OFF`, `BTREE_MAP_RANGE`.
*   **Missing from Rust**: `retain`, `range_mut`, full `entry` / `OccupiedEntry` APIs, `into_keys`, `into_values`, `iter`, `iter_mut`, lazy `keys` / `values` iterators, generic `Ord` support, allocator-aware constructors, and full mutable-reference borrow semantics.
*   **Scope note**: The SA BTreeMap is a concrete sorted-array map with `Slice` keys and `u64` values. `GET_MUT_PTR`, `FIRST_ENTRY_MUT_PTR`, `LAST_ENTRY_MUT_PTR`, and `TRY_GET_DISJOINT_MUT_PTRS` expose verifier-friendly raw value-slot pointers; `KEYS`, `VALUES`, `VALUES_MUT_PTRS`, and `RANGE` materialize concrete SA collections instead of Rust lazy iterators; `RANGE` is half-open `[start, end)`. `APPEND` copies entries from the source and clears it; `SPLIT_OFF` moves entries with keys greater than or equal to the split key into a new map. It does not model Rust's node tree internals, generics, scoped borrows, or entry object semantics.

### 1.5a B-Tree Set (`std::collections::BTreeSet` vs `sa_std/btree_set.sa`)
*   **Implemented in `sa_std`**: `BTREE_SET_NEW`, `BTREE_SET_FREE`, `BTREE_SET_LEN`, `BTREE_SET_IS_EMPTY`, `BTREE_SET_CONTAINS`, `BTREE_SET_GET`, `BTREE_SET_FIRST`, `BTREE_SET_LAST`, `BTREE_SET_CLEAR`, `BTREE_SET_INSERT`, `BTREE_SET_REPLACE`, `BTREE_SET_REMOVE`, `BTREE_SET_TAKE`, `BTREE_SET_POP_FIRST`, `BTREE_SET_POP_LAST`, `BTREE_SET_IS_DISJOINT`, `BTREE_SET_IS_SUBSET`, `BTREE_SET_IS_SUPERSET`, `BTREE_SET_APPEND`, `BTREE_SET_SPLIT_OFF`, `BTREE_SET_RANGE`, `BTREE_SET_UNION`, `BTREE_SET_INTERSECTION`, `BTREE_SET_DIFFERENCE`, `BTREE_SET_SYMMETRIC_DIFFERENCE`, `BTREE_SET_LIT2`.
*   **Missing from Rust**: iterator APIs, lazy `union` / `intersection` / `difference` / `symmetric_difference` adapters, bit-operator set algebra adapters, generic `Ord` support, allocator-aware constructors, and entry/get-or-insert style APIs.
*   **Scope note**: The SA facade reuses `BTreeMap` storage and comparison; it is a concrete string-slice-key subset, not Rust's generic `Ord`-driven implementation. `RANGE` is half-open `[start, end)`, and set algebra macros materialize new SA sets instead of returning Rust lazy adapters. Set relation helpers scan stored ordered entries and call `BTREE_SET_CONTAINS` on the opposite set.

### 1.6 Binary Heap (`std::collections::BinaryHeap` vs `sa_std/binary_heap.sa`)
*   **Implemented in `sa_std`**: `BINARY_HEAP_NEW`, `BINARY_HEAP_WITH_CAPACITY`, `BINARY_HEAP_TRY_WITH_CAPACITY`, `BINARY_HEAP_FREE`, `BINARY_HEAP_LEN`, `BINARY_HEAP_CAPACITY`, `BINARY_HEAP_RESERVE`, `BINARY_HEAP_RESERVE_EXACT`, `BINARY_HEAP_TRY_RESERVE`, `BINARY_HEAP_TRY_RESERVE_EXACT`, `BINARY_HEAP_SHRINK_TO`, `BINARY_HEAP_SHRINK_TO_FIT`, `BINARY_HEAP_AS_SLICE`, `BINARY_HEAP_AS_MUT_SLICE`, `BINARY_HEAP_INTO_VEC`, `BINARY_HEAP_INTO_SORTED_VEC`, `BINARY_HEAP_IS_EMPTY`, `BINARY_HEAP_PEEK`, `BINARY_HEAP_PUSH`, `BINARY_HEAP_TRY_POP`, `BINARY_HEAP_CLEAR`, `BINARY_HEAP_APPEND`.
*   **Missing from Rust**: `peek_mut`, `into_iter`, `iter`, `drain`, `retain`, generic ordering support, allocator-aware constructors, and true allocation-failure reporting for `try_reserve*`.
*   **Scope note**: The SA facade is a concrete `u64` max-heap. `AS_SLICE` / `AS_MUT_SLICE` expose the internal heap array order, `INTO_VEC` reinterprets the owned heap storage as a `Vec`-layout object, and `INTO_SORTED_VEC` consumes the heap and returns ascending `u64` values. It does not implement Rust's generic ordering, iterator, mutable peek, or allocator error semantics.

### 1.7 Environment (`std::env` vs `sa_std/env.sa`)
*   **Implemented in `sa_std`**: `ENV_GET`, `ENV_HAS`, `ENV_BUFFER_DATA`, `ENV_BUFFER_LEN`, `ENV_BUFFER_FREE`.
*   **Plugin alternative, not `sa_std`**: Deno facade env/args helpers live in `sa_plugin_deno`; they are intentionally not counted as compiler std coverage because plugins can be installed and removed independently.
*   **Missing from Rust**: `args_os`, `vars`, `vars_os`, `join_paths`, `split_paths`, `current_exe`, `temp_dir`.

### 1.8 Formatting & String (`std::fmt` & `std::string` vs `sa_std/fmt.sa`, `sa_std/string.sa`)
*   **Implemented in `sa_std`**: `STRFMT_I64`, `U64`, `F64`, `BOOL`, `BYTES`, `STR_FROM_CONST`, `STR_LEN`, `STRING_LEN`, `STR_PTR`, `STR_AS_PTR`, `STRING_AS_PTR`, `STR_AS_BYTES`, `STRING_AS_BYTES`, `STRING_AS_STR`, `STR_IS_EMPTY`, `STRING_IS_EMPTY`, `STRING_NEW`, `STR_EMPTY`, `STR_FROM_PARTS`, `STRING_FROM_PARTS`, `STR_SLICE`, `STR_EQ`, `STR_EQ_IGNORE_ASCII_CASE`, `STRING_EQ_IGNORE_ASCII_CASE`, `STR_CONTAINS`, `STRING_CONTAINS`, `STR_STARTS_WITH`, `STRING_STARTS_WITH`, `STR_ENDS_WITH`, `STRING_ENDS_WITH`, `STR_TRY_STRIP_PREFIX`, `STRING_TRY_STRIP_PREFIX`, `STR_TRY_STRIP_SUFFIX`, `STRING_TRY_STRIP_SUFFIX`, `STR_TRIM_PREFIX`, `STRING_TRIM_PREFIX`, `STR_TRIM_SUFFIX`, `STRING_TRIM_SUFFIX`, `STR_TRIM_ASCII_START`, `STRING_TRIM_ASCII_START`, `STR_TRIM_ASCII_END`, `STRING_TRIM_ASCII_END`, `STR_TRIM_ASCII`, `STRING_TRIM_ASCII`, `STR_TRY_SPLIT_AT`, `STRING_TRY_SPLIT_AT`, `STR_TRY_SPLIT_ONCE`, `STRING_TRY_SPLIT_ONCE`, `STR_TRY_RSPLIT_ONCE`, `STRING_TRY_RSPLIT_ONCE`, `STR_IS_ASCII`, `STRING_IS_ASCII`, `STR_CONCAT`, `STRING_SET_SLICE`, `STRING_CLEAR`, `STRING_TRUNCATE`, `STRING_PUSH_STR`, `STRING_PUSH`, `STRING_POP`, `STRING_TRY_SPLIT_OFF`, `STRING_SPLIT_OFF`, `STRING_TRY_INSERT_STR`, `STRING_INSERT_STR`, `STRING_TRY_INSERT`, `STRING_INSERT`, `STRING_TRY_REPLACE_RANGE`, `STRING_REPLACE_RANGE`, plus the macro-level formatting scaffold around `PRINTLN` / `PRINT` / `FORMAT`.
*   **Missing Infrastructure**: `Display`, `Debug`, `Formatter` traits; `format!` macro interpolation.
*   **Missing Methods**: `str` methods like `chars`, `bytes`, iterator-based `split`, `lines`, Unicode whitespace `trim`, `replace`, and UTF-8 boundary helpers. Rust's capacity-aware `String` allocation API (`with_capacity`, `reserve`, `shrink_to`, etc.) is still not modeled as an owned Rust `String` type.
*   **Rust-aligned byte-view helpers**: `STR_TRY_FIND` / `STRING_TRY_FIND`, `STR_TRY_RFIND` / `STRING_TRY_RFIND`, `STR_TRY_SPLIT_ONCE` / `STRING_TRY_SPLIT_ONCE`, and `STR_TRY_RSPLIT_ONCE` / `STRING_TRY_RSPLIT_ONCE` provide `find` / `rfind` / `split_once` / `rsplit_once` subsets over concrete byte slices, returning `(found, ...)` rather than Rust `Option<...>`.
*   **Scope note**: `STR_TRY_STRIP_PREFIX/SUFFIX`, `STR_TRIM_PREFIX/SUFFIX`, and `STR_TRY_SPLIT_AT` implement byte-slice view subsets. The `STRING_*` mutation helpers are byte-level `Slice` rewrites: `push_str`, `insert_str`, and `replace_range` materialize new concatenated byte buffers, `split_off` truncates the left view and returns the right view, and `pop` removes one trailing byte. They do not implement Rust's full `Pattern` machinery, UTF-8 boundary validation, allocator capacity semantics, or scoped ownership model beyond the caller-provided slice contract.

### 1.9 File System (`std::fs` vs `sa_std/fs.sa`)
*   **Implemented in `sa_std`**: Handles (`open`, `create`, `close`, `read`, `read_exact`, `write`, `write_all`, `flush`, `seek`), Full-file IO (`read_file`, `write_file`), Metadata (`metadata`, `remove_file`, `rename`, `make_dir`, `remove_dir`).
*   **Plugin alternative, not `sa_std`**: Deno facade file helpers live in `sa_plugin_deno` and are not part of compiler std coverage.
*   **Missing from Rust**: `sync_all`, `sync_data`, `set_len`, `set_permissions`, fine-grained `OpenOptions`, expanded `Metadata` (`is_dir`, `modified`, etc.), `Permissions`, `FileType`, `DirBuilder`, `ReadDir` / `read_dir`, `copy`, `create_dir_all`, `hard_link`, `read_link`, `remove_dir_all`.

### 1.10 Input/Output (`std::io` vs `sa_std/io.sa`)
*   **Implemented in `sa_std`**: `stdin`, `stdout`, `stderr`, `PRINTLN`, `READ_LINE`, `read`, `write`, etc.
*   **Plugin alternative, not `sa_std`**: Deno facade stdio helpers live in `sa_plugin_deno` and are not part of compiler std coverage.
*   **Missing Infrastructure**: `Read`, `Write`, `Seek`, `BufRead` traits; `Cursor`, `Error`/`ErrorKind` system, `copy`, `empty`, `repeat`, `sink`, `read_to_end`, `read_to_string`, `bytes`, `chain`, `take`.

### 1.11 Networking (`std::net` vs `sa_std/net.sa`)
*   **Implemented in `sa_std`**: TCP Connect/Bind/Accept/IO, UDP Bind/SendTo/RecvFrom, Async Reactor macros.
*   **Plugin alternative, not `sa_std`**: Deno facade networking helpers live in `sa_plugin_deno`; HTTP client/server live in `sa_plugin_http_client` and `sa_plugin_http_server`. None of these count as compiler std coverage.
*   **Missing from Rust**: `set_read_timeout`, `set_write_timeout`, `peek`, `set_nodelay`, `set_ttl`, `set_nonblocking`; `TcpListener::incoming` iterator; `UdpSocket::connect`, `set_broadcast`, multicast control; `Ipv4Addr`, `Ipv6Addr`, `SocketAddr` structs and parsing.

### 1.12 Process (`std::process` vs `sa_std/process.sa`)
*   **Implemented in `sa_std`**: `run`, `spawn`, `spawn_stream`, `wait`, `close`.
*   **Plugin alternative, not `sa_std`**: Deno facade process helpers live in `sa_plugin_deno` and are not part of compiler std coverage.
*   **Missing from Rust**: `Command` builder (`env`, `current_dir`, pipe redirection), `Output` struct, `Child::id()`, `kill()`, `try_wait()`, `process::abort`, `process::id`.

### 1.13 Path (`std::path` vs `sa_std/path.sa`)
*   **Implemented in `sa_std`**: `PATH_MAKE_EMPTY`, `PATH_BASENAME`, `PATH_DIRNAME`, `PATH_STEM`, `PATH_EXT`, `PATH_IS_ABSOLUTE`, `PATH_HAS_ROOT`, `PATH_STARTS_WITH`, `PATH_TRY_STRIP_PREFIX`, `PATH_JOIN`, `PATH_PARENT`, `PATH_FILE_STEM`, `PATH_EXTENSION`, `PATH_WITH_FILE_NAME`.
*   **Missing from Rust**: Type-safe `Path` / `PathBuf` system, component iterator APIs (`components`, `iter`, `ancestors`), mutation APIs beyond `with_file_name`, filesystem-backed predicates (`exists`, `is_file`, `is_dir`), `canonicalize`, symlink handling, Windows prefix/root semantics, and owned `PathBuf` capacity/mutation behavior.
*   **Scope note**: The SA path facade is a POSIX-style byte-slice subset over `Slice`. `STARTS_WITH` and `TRY_STRIP_PREFIX` enforce a simple slash boundary, `JOIN` materializes a concatenated string slice through existing `STR_CONCAT`, and `PARENT` / `FILE_STEM` / `EXTENSION` are aliases over the concrete basename/dirname/stem/ext helpers. It does not model Rust's platform-specific `OsStr`, `PathBuf`, or component iterator semantics.

### 1.14 Time & Sync (`std::time`, `std::sync` vs `sa_std/time.sa`, `sa_std/sync/*`)
*   **Implemented in `sa_std`**: `Instant` / `Unix` timestamps, `Sleep`, `Duration` nanosecond construction and conversion helpers, `duration_since` / `checked_duration_since` / `elapsed` macro subsets, checked add/sub helpers, `subsec_nanos` / `subsec_micros` / `subsec_millis`, MPSC channels, `Mutex` (spin), `Once`, `RwLock`, `Arc`, `RefCell` shared/exclusive borrow helpers, and the matching core macros in `sa_std/core/*`.
*   **Plugin alternative, not `sa_std`**: Deno facade time helpers live in `sa_plugin_deno` and are not part of compiler std coverage.
*   **Missing from Rust (Time)**: Rust's typed `Duration` / `Instant` / `SystemTime` structs, signed/float duration conversions, saturating arithmetic family, `SystemTimeError`, checked multiplication/division, platform-specific clock semantics, and rigorous overflow/error semantics beyond the current `(ok, value)` nanosecond macro subset.
*   **Missing from Rust (Sync)**: `Condvar`, `Barrier`, Atomic variables (`AtomicI32`, `AtomicBool`, etc.), RAII `MutexGuard`, `PoisonError`.

---

## 2. Missing Full Rust Module Parity

The following Rust `std` modules still lack full Rust-level parity in `sa_std`:

1.  **Memory & Data Abstraction**: `std::any`, `std::array`, full `std::ascii::Char` / escaping iterator APIs, `std::char`, `std::ptr` (`NonNull`), `std::pin`. `Box`, `Cell`, `RefCell`, `Rc`, `Arc`, `Weak`, and byte-level ASCII helpers have macro-level SA subsets under `sa_std/core/*`, but not full Rust module parity.
2.  **Core Trait Paradigm**: `std::convert` (`From`/`Into`), `std::default`, `std::error`, `std::iter` (`Iterator` system), `std::marker` (`Send`/`Sync`/`Copy`), `std::ops` (Operator overloading/`Drop`), `std::cmp`.
3.  **FFI & Platform Specific**: `std::ffi` (`CString`, `OsString`), `std::os` (Unix/Windows extensions).
4.  **Concurrency Infrastructure**: `std::thread` (System thread management, `JoinHandle`) and a bundled async runtime/reactor. `sa_std/core/waker.*` now models the Rust `std::task` waker ABI subset with `RawWaker`, `RawWakerVTable`, `Waker`, `LocalWaker`, and `Wake` layout/vtable helper macros. `sa_std/core/future.*` models `Poll`, `Poll<Result<..>>`, `Poll<Option<Result<..>>>`, `Context`, `ContextBuilder`, `Future::poll` vtable calls, ready/pending futures, poll_fn-style state, stateful `join2` pairs, and biased `select2` either results. `sa_std/core/task.*` provides `Task`, single-task executor polling, and ready-count batch polling. `sa_std/libsa_async.sa` remains the CPS/state-machine helper layer (`ASYNC_CTX_DEF`, `ASYNC_AWAIT_POINT`, etc.). SA intentionally does not provide native `async` / `await` syntax, Rust generics/traits/pin semantics, a hidden executor, or a bundled reactor.

## 4. Rust Core Minimal Closed Loop

The project now treats the following Rust core items as a **SA layout + macro contract**, not as native SA type-system features:

- `Option<T>`: represented by a tag + payload memory contract and helper macros in `sa_std/core/option.sa`.
- `Result<T, E>`: represented by a tag + ok/err payload memory contract and helper macros in `sa_std/core/result.sa`.
- `panic` / `panic_msg`: represented by wrapper macros in `sa_std/core/panic.sa` and lowered as builtin termination paths.
- `iter` / iterator-like traversal: represented by slice-backed cursor helpers in `sa_std/core/iter.sa`.
- ASCII byte classification and conversion: represented by byte/slice helper macros in `sa_std/core/ascii.sa` / `.sal` and re-exported through `sa_std/ascii.sa`.
- `Future` / `Poll` / `Context` / `Task`: represented by concrete layout contracts and vtable/helper macros in `sa_std/core/future.sa`, `sa_std/core/waker.sa`, and `sa_std/core/task.sa`. The covered async contract includes `RawWaker` / `RawWakerVTable` / `LocalWaker` / `Wake`, `ContextBuilder`, `Poll::map`, `Poll<Result>::map_ok/map_err`, `Poll<Option<Result>>::map_ok/map_err`, `ready` / `pending` state futures, `Future::poll` out-param ABI, stateful two-way `join` / `select` helpers, and executor ready-count polling.

The async coverage is deliberately a layout and macro contract. It is not native Rust `async fn` lowering, `.await` syntax, `Pin<&mut T>` enforcement, Rust trait objects/generics, or a scheduler/reactor implementation. Frontends should lower those higher-level semantics into the concrete SA ABI described above.

These helpers intentionally stop short of native Rust `trait` / `generic` semantics. In SA, those remain a frontend lowering concern: monomorphization, concrete ABI selection, and call-site rewriting belong in the compiler frontend, not in SA source.

This closed loop is already backed by concrete files and smoke coverage:

- `sa_std/core/option.sa` / `.sal`
- `sa_std/core/result.sa` / `.sal`
- `sa_std/core/panic.sa`
- `sa_std/core/iter.sa` / `.sal`
- `sa_std/core/ascii.sa` / `.sal`
- `sa_std/core/future.sa` / `.sal`
- `sa_std/core/task.sa` / `.sal`
- `sa_std/rust_core.sa` / `.sal`
- `tests/rust_core_fixture.sa`
- `tests/unit_framework/std_future_task_macro_surface.sa`

---

## 3. Common Macros Comparison

Rust relies heavily on declarative and procedural macros. `sa_std` provides functional parity for some through assembly `[MACRO]` definitions, but many are missing or limited.

### 3.1 Implemented in `sa_std` (Macro Parity)
| Rust Macro | `sa_std` Equivalent | Note |
| :--- | :--- | :--- |
| `print!` / `println!` | `PRINT` / `PRINTLN` | Limited to string/bytes, no complex interpolation. |
| `eprint!` / `eprintln!` | `EPRINT` / `EPRINTLN` | Limited to string/bytes through stderr. |
| `assert!` | `ASSERT_TRUE` | Basic boolean check. |
| `assert_eq!` | `ASSERT_EQ` | Basic equality check. |
| `assert_ne!` | `ASSERT_NE` | Basic inequality check. |
| `vec!` | `VEC_NEW` / `VEC_PUSH` | No literal initialization like `vec![1, 2, 3]`. |
| `concat!` | `STR_CONCAT` | Concatenates two slices. |
| `stringify!` | `STRINGIFY!` | Flattener macro emits a source-text slice. |

### 3.1a Newly landed base macros
These are now implemented as first-wave portability helpers rather than missing gaps:
- Container and field access: `STRUCT_NEW`, `FIELD_GET`, `FIELD_SET`, `STRUCT_FREE`, `PTR_FIELD`
- Structural copy and equality: `STRUCT_COPY_FIELD`, `STRUCT_COPY`, `STRUCT_EQ_FIELD`, `STRUCT_EQ4`
- Option / Result ergonomics: `OPTION_MATCH_SOME_NONE`, `OPTION_UNWRAP_OR_RETURN`, `TRY_OPTION`, `TRY_OPTION_RETURN`, `RESULT_MATCH_OK_ERR`, `RESULT_RETURN_ERR`, `TRY_RESULT`, `TRY_RESULT_RETURN`, `RESULT_MAP_OK`, `RESULT_IS_OK`, `RESULT_IS_ERR`
- Loop and index sugar: `WHILE`, `WHILE_COND`, `FOR_RANGE`, `INDEX_LOOP`, `ARRAY_FOR_EACH`, `ARRAY_SCAN_MIN/MAX`, `SLICE_GET_U64`, `SLICE_GET_U64_AT`
- Bit and mask helpers: `BIT_MASK`, `BIT_SET`, `BIT_GET`, `BIT_CLEAR`, `BIT_TEST`, `BIT_INDEX_BYTE`, `BIT_INDEX_BIT`
- Hash and probe helpers: `HASH_PTR`, `HASH_MIX`, `HASH_MOD`, `PROBE_START`, `PROBE_NEXT`, `MAP_LOOKUP`, `MAP_INSERT_OR_UPDATE`
- Cleanup sugar: `DEFER`, `CLEANUP_ON_ERROR`, `WITH_TEMP`, `RETURN_CLEAN`, `FREE_AND_RETURN`
- Control-flow sugar: `MATCH_BOOL`, `ELIF`, `WHILE_LET`, `BREAK_IF`, `CONTINUE_IF`

### 3.2 Missing or Partially Implemented (Gaps)
*   **Formatting & Printing**:
    *   Missing `format!` (No dynamic string interpolation/formatting macro).
    *   `WRITE` / `WRITELN` cover raw byte writes to a handle, but Rust-style formatted `write!` / `writeln!` interpolation is still missing.
*   **Error Handling & Control Flow**:
    *   `PANIC`, `PANIC_MSG`, `TODO`, `UNIMPLEMENTED`, and `UNREACHABLE` cover the basic panic-style macro paths, but not Rust's full formatting payload surface.
    *   `MATCHES_OPTION` / `MATCHES_RESULT` cover the tag-checking subset of Rust `matches!` for `Option` / `Result` layouts.
    *   `TRY_OPTION` and `TRY_RESULT` provide Zig-style explicit early-return helpers over SA's concrete `Option` / `Result` memory layouts. SA still does not provide Rust's generic `Try` trait, `FromResidual` conversion, or a fully generic `try!` macro surface.
*   **Compile-time & Metaprogramming**:
    *   `cfg!` is now covered by SA flattener macro expansion tests.
    *   `env!`, `option_env!` are now covered by SA flattener macro expansion tests.
    *   `include_str!` / `include_bytes!` are now covered by SA flattener macro expansion tests.
    *   `include!` is now covered by SA flattener macro expansion tests.
    *   `line!`, `file!`, `column!` are now covered by SA flattener macro expansion tests.
    *   `module_path!` is now covered by SA flattener macro expansion tests.
    *   `stringify!` is now covered by SA flattener macro expansion tests.
*   **Collection Initializers**:
    *   Missing literal initializers for all collections (e.g., no `hashmap!{...}`, `set!{...}`).
