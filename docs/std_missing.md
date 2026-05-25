# sa_std vs. Rust std: Interface Comparison Report

This document provides a 1:1 interface comparison between the current `sa_std` implementation in the `sci` project and the Rust standard library (`std`).

## Summary of Implementation Parity

`sa_std` uses a hybrid paradigm of `@extern` / `@export` functions and `[MACRO]` assembly macros, whereas Rust uses a high-level Trait, Struct, and Module system.

---

## 1. Partially Implemented Modules

### 1.1 Vector (`std::vec::Vec` vs `sa_std/vec.sa`)
*   **Implemented in `sa_std`**: `VEC_NEW` / `sa_vec_new`, `VEC_FREE` / `sa_vec_free`, `VEC_LEN`, `VEC_GET`, `VEC_PUSH`.
*   **Missing from Rust**: `with_capacity`, `capacity`, `reserve`, `reserve_exact`, `shrink_to_fit`, `shrink_to`, `truncate`, `as_slice`, `as_mut_slice`, `set_len`, `swap_remove`, `insert`, `remove`, `retain`, `retain_mut`, `dedup`, `dedup_by`, `pop`, `append`, `drain`, `clear`, `is_empty`, `split_off`, `resize`, `extend_from_slice`.
*   **Missing Infrastructure**: Iterator support (`IntoIterator`, `iter()`, `iter_mut()`).

### 1.2 Deque (`std::collections::VecDeque` vs `sa_std/vec_deque.sa`)
*   **Implemented in `sa_std`**: `NEW`, `FREE`, `LEN`, `GET`, `PUSH_BACK`, `PUSH_FRONT`, `TRY_POP_FRONT`, `TRY_POP_BACK`, `ROTATE_LEFT`, `ROTATE_RIGHT`.
*   **Missing from Rust**: `with_capacity`, `get_mut`, `swap`, `capacity`, `reserve`, `shrink_to_fit`, `truncate`, `iter`, `iter_mut`, `as_slices`, `as_mut_slices`, `is_empty`, `drain`, `clear`, `contains`, `front`, `front_mut`, `back`, `back_mut`, `pop_front`, `pop_back`, `swap_remove_front`, `swap_remove_back`, `insert`, `remove`, `split_off`, `append`, `retain`.

### 1.3 Hash Map (`std::collections::HashMap` vs `sa_std/hashmap.sa`)
*   **Implemented in `sa_std`**: `MAP_NEW`, `MAP_FREE`, `MAP_PUT`, `MAP_GET`, `MAP_DEL`.
*   **Missing from Rust**: `with_capacity`, `capacity`, `reserve`, `try_reserve`, `shrink_to_fit`, `keys`, `values`, `values_mut`, `iter`, `iter_mut`, `len`, `is_empty`, `drain`, `retain`, `clear`, `contains_key`, `get_mut`, `get_key_value`, `insert` (with old value return), `remove`, `remove_entry`, `entry` API (Vacant/Occupied).

### 1.4 Hash Set (`std::collections::HashSet` vs `sa_std/hashset.sa`)
*   **Implemented in `sa_std`**: `SET_NEW`, `SET_FREE`, `SET_INSERT`, `SET_CONTAINS`, `SET_REMOVE`.
*   **Missing from Rust**: `with_capacity`, `capacity`, `reserve`, `shrink_to_fit`, `iter`, `len`, `is_empty`, `drain`, `retain`, `clear`, `intersection`, `union`, `difference`, `symmetric_difference`, `is_disjoint`, `is_subset`, `is_superset`, `replace`, `get`, `take`.

### 1.5 B-Tree Map (`std::collections::BTreeMap` vs `sa_std/btree_map.sa`)
*   **Implemented in `sa_std`**: `NEW`, `FREE`, `LEN`, `GET`, `INSERT`.
*   **Missing from Rust**: `clear`, `get_mut`, `get_key_value`, `first_key_value`, `first_entry`, `last_key_value`, `last_entry`, `pop_first`, `pop_last`, `contains_key`, `remove`, `remove_entry`, `retain`, `append`, `range`, `range_mut`, `entry`, `split_off`, `into_keys`, `into_values`, `iter`, `iter_mut`, `keys`, `values`, `is_empty`.

### 1.6 Binary Heap (`std::collections::BinaryHeap` vs `sa_std/binary_heap.sa`)
*   **Implemented in `sa_std`**: `NEW`, `FREE`, `LEN`, `PEEK`, `PUSH`, `TRY_POP`.
*   **Missing from Rust**: `with_capacity`, `peek_mut`, `capacity`, `reserve`, `shrink_to_fit`, `into_vec`, `into_iter`, `iter`, `drain`, `clear`, `append`, `is_empty`.

### 1.7 Environment (`std::env` vs `sa_std/env.sa`)
*   **Implemented in `sa_std`**: `ENV_GET`, `ENV_HAS`, `ENV_BUFFER_DATA`, `ENV_BUFFER_LEN`, `ENV_BUFFER_FREE`.
*   **Missing from Rust**: `args`, `args_os`, `vars`, `vars_os`, `set_var`, `remove_var`, `join_paths`, `split_paths`, `current_dir`, `set_current_dir`, `current_exe`, `temp_dir`.

### 1.8 Formatting & String (`std::fmt` & `std::string` vs `sa_std/fmt.sa`, `sa_std/string.sa`)
*   **Implemented in `sa_std`**: `STRFMT_I64`, `U64`, `F64`, `BOOL`, `BYTES`, `STR_FROM_CONST`, `STR_LEN`, `STR_SLICE`, `STR_EQ`, `STR_CONCAT`, plus the macro-level formatting scaffold around `PRINTLN` / `PRINT` / `FORMAT`.
*   **Missing Infrastructure**: `Display`, `Debug`, `Formatter` traits; `format!` macro interpolation.
*   **Missing Methods**: `String::push_str`, `String::pop`, `String::insert`, `String::split_off`, `String::replace_range`; `str` methods like `chars`, `bytes`, `split`, `lines`, `trim`, `starts_with`, `ends_with`, `find`, `replace`.

### 1.9 File System (`std::fs` vs `sa_std/fs.sa`)
*   **Implemented in `sa_std`**: Handles (`open`, `create`, `close`, `read`, `read_exact`, `write`, `write_all`, `flush`, `seek`), Full-file IO (`read_file`, `write_file`), Metadata (`metadata`, `remove_file`, `rename`, `make_dir`, `remove_dir`).
*   **Missing from Rust**: `sync_all`, `sync_data`, `set_len`, `set_permissions`, fine-grained `OpenOptions`, expanded `Metadata` (`is_dir`, `modified`, etc.), `Permissions`, `FileType`, `DirBuilder`, `ReadDir` / `read_dir`, `copy`, `create_dir_all`, `hard_link`, `read_link`, `remove_dir_all`.

### 1.10 Input/Output (`std::io` vs `sa_std/io.sa`)
*   **Implemented in `sa_std`**: `stdin`, `stdout`, `stderr`, `PRINTLN`, `READ_LINE`, `read`, `write`, etc.
*   **Missing Infrastructure**: `Read`, `Write`, `Seek`, `BufRead` traits; `Cursor`, `Error`/`ErrorKind` system, `copy`, `empty`, `repeat`, `sink`, `read_to_end`, `read_to_string`, `bytes`, `chain`, `take`.

### 1.11 Networking (`std::net` vs `sa_std/net.sa`)
*   **Implemented in `sa_std`**: TCP Connect/Bind/Accept/IO, UDP Bind/SendTo/RecvFrom, Async Reactor macros.
*   **Missing from Rust**: `set_read_timeout`, `set_write_timeout`, `peek`, `set_nodelay`, `set_ttl`, `set_nonblocking`; `TcpListener::incoming` iterator; `UdpSocket::connect`, `set_broadcast`, multicast control; `Ipv4Addr`, `Ipv6Addr`, `SocketAddr` structs and parsing.

### 1.12 Process (`std::process` vs `sa_std/process.sa`)
*   **Implemented in `sa_std`**: `run`, `spawn`, `spawn_stream`, `wait`, `close`.
*   **Missing from Rust**: `Command` builder (`env`, `current_dir`, pipe redirection), `Output` struct, `Child::id()`, `kill()`, `try_wait()`, `process::abort`, `process::exit`, `process::id`.

### 1.13 Path (`std::path` vs `sa_std/path.sa`)
*   **Implemented in `sa_std`**: `PATH_MAKE_EMPTY`, `PATH_BASENAME`, `PATH_DIRNAME`, `PATH_STEM`, `PATH_EXT`.
*   **Missing from Rust**: Type-safe `Path` / `PathBuf` system; methods like `is_absolute`, `has_root`, `parent`, `strip_prefix`, `starts_with`, `join`, `with_file_name`, `components` iterator, `exists`, `is_file`, `is_dir`, `canonicalize`.

### 1.14 Time & Sync (`std::time`, `std::sync` vs `sa_std/time.sa`, `sa_std/sync/*`)
*   **Implemented in `sa_std`**: `Instant` / `Unix` timestamps, `Sleep`, `MPSC` channels, `Mutex` (spin), `Once`, `RwLock`, `Arc`, `RefCell` shared/exclusive borrow helpers, and the matching core macros in `sa_std/core/*`.
*   **Missing from Rust (Time)**: `duration_since`, `elapsed`, `checked_add/sub`, `subsec_nanos` and rigorous duration arithmetic.
*   **Missing from Rust (Sync)**: `Condvar`, `Barrier`, Atomic variables (`AtomicI32`, `AtomicBool`, etc.), RAII `MutexGuard`, `PoisonError`.

---

## 2. Completely Missing Modules (0% Coverage)

The following Rust `std` modules have no corresponding implementation or mapping in `sa_std`:

1.  **Memory & Data Abstraction**: `std::any`, `std::array`, `std::ascii`, `std::boxed`, `std::cell` (`Cell`, `RefCell`), `std::char`, `std::rc` (`Rc`), `std::ptr` (`NonNull`), `std::pin`.
2.  **Core Trait Paradigm**: `std::convert` (`From`/`Into`), `std::default`, `std::error`, `std::iter` (`Iterator` system), `std::marker` (`Send`/`Sync`/`Copy`), `std::ops` (Operator overloading/`Drop`), `std::cmp`.
3.  **FFI & Platform Specific**: `std::ffi` (`CString`, `OsString`), `std::os` (Unix/Windows extensions).
4.  **Concurrency Infrastructure**: `std::thread` (System thread management, `JoinHandle`), `std::future`, `std::task`.

## 4. Rust Core Minimal Closed Loop

The project now treats the following Rust core items as a **SA layout + macro contract**, not as native SA type-system features:

- `Option<T>`: represented by a tag + payload memory contract and helper macros in `sa_std/core/option.sa`.
- `Result<T, E>`: represented by a tag + ok/err payload memory contract and helper macros in `sa_std/core/result.sa`.
- `panic` / `panic_msg`: represented by wrapper macros in `sa_std/core/panic.sa` and lowered as builtin termination paths.
- `iter` / iterator-like traversal: represented by slice-backed cursor helpers in `sa_std/core/iter.sa`.

These helpers intentionally stop short of native Rust `trait` / `generic` semantics. In SA, those remain a frontend lowering concern: monomorphization, concrete ABI selection, and call-site rewriting belong in the compiler frontend, not in SA source.

This closed loop is already backed by concrete files and smoke coverage:

- `sa_std/core/option.sa` / `.sal`
- `sa_std/core/result.sa` / `.sal`
- `sa_std/core/panic.sa`
- `sa_std/core/iter.sa` / `.sal`
- `sa_std/rust_core.sa` / `.sal`
- `tests/rust_core_fixture.sa`

---

## 3. Common Macros Comparison

Rust relies heavily on declarative and procedural macros. `sa_std` provides functional parity for some through assembly `[MACRO]` definitions, but many are missing or limited.

### 3.1 Implemented in `sa_std` (Macro Parity)
| Rust Macro | `sa_std` Equivalent | Note |
| :--- | :--- | :--- |
| `println!` | `PRINTLN` | Limited to string/bytes, no complex interpolation. |
| `assert!` | `ASSERT_TRUE` | Basic boolean check. |
| `assert_eq!` | `ASSERT_EQ` | Basic equality check. |
| `assert_ne!` | `ASSERT_NE` | Basic inequality check. |
| `vec!` | `VEC_NEW` / `VEC_PUSH` | No literal initialization like `vec![1, 2, 3]`. |
| `concat!` | `STR_CONCAT` | Concatenates two slices. |

### 3.1a Newly landed base macros
These are now implemented as first-wave portability helpers rather than missing gaps:
- Container and field access: `STRUCT_NEW`, `FIELD_GET`, `FIELD_SET`, `STRUCT_FREE`, `PTR_FIELD`
- Structural copy and equality: `STRUCT_COPY_FIELD`, `STRUCT_COPY`, `STRUCT_EQ_FIELD`, `STRUCT_EQ4`
- Option / Result ergonomics: `OPTION_MATCH_SOME_NONE`, `OPTION_UNWRAP_OR_RETURN`, `RESULT_MATCH_OK_ERR`, `RESULT_RETURN_ERR`, `RESULT_MAP_OK`, `RESULT_IS_OK`, `RESULT_IS_ERR`
- Loop and index sugar: `WHILE`, `WHILE_COND`, `FOR_RANGE`, `INDEX_LOOP`, `ARRAY_FOR_EACH`, `ARRAY_SCAN_MIN/MAX`, `SLICE_GET_U64`, `SLICE_GET_U64_AT`
- Bit and mask helpers: `BIT_MASK`, `BIT_SET`, `BIT_GET`, `BIT_CLEAR`, `BIT_TEST`, `BIT_INDEX_BYTE`, `BIT_INDEX_BIT`
- Hash and probe helpers: `HASH_PTR`, `HASH_MIX`, `HASH_MOD`, `PROBE_START`, `PROBE_NEXT`, `MAP_LOOKUP`, `MAP_INSERT_OR_UPDATE`
- Cleanup sugar: `DEFER`, `CLEANUP_ON_ERROR`, `WITH_TEMP`, `RETURN_CLEAN`, `FREE_AND_RETURN`
- Control-flow sugar: `MATCH_BOOL`, `ELIF`, `WHILE_LET`, `BREAK_IF`, `CONTINUE_IF`

### 3.2 Missing or Partially Implemented (Gaps)
*   **Formatting & Printing**: 
    *   Missing `print!`, `eprint!`, `eprintln!`.
    *   Missing `format!` (No dynamic string interpolation/formatting macro).
    *   Missing `write!`, `writeln!` (No macro to write formatted data to a buffer/stream).
*   **Error Handling & Control Flow**:
    *   Missing `panic!` as a Rust macro surface; runtime panic behavior is available through `sa_std/core/panic.sa`.
    *   Missing `todo!`, `unimplemented!`, `unreachable!`.
    *   `MATCHES_OPTION` / `MATCHES_RESULT` cover the tag-checking subset of Rust `matches!` for `Option` / `Result` layouts.
    *   `?` / early-return lowering is handled in the SA frontend for core `Option` / `Result` flows; a general Rust `try!` macro surface is still missing.
*   **Compile-time & Metaprogramming**:
    *   `cfg!` is now covered by SA flattener macro expansion tests.
    *   `env!`, `option_env!` are now covered by SA flattener macro expansion tests.
    *   `include_str!` / `include_bytes!` are now covered by SA flattener macro expansion tests.
    *   `include!` is now covered by SA flattener macro expansion tests.
    *   `line!`, `file!`, `column!` are now covered by SA flattener macro expansion tests.
    *   `module_path!` is now covered by SA flattener macro expansion tests.
    *   Missing `stringify!` (Convert expression to string literal).
*   **Collection Initializers**:
    *   Missing literal initializers for all collections (e.g., no `hashmap!{...}`, `set!{...}`).
