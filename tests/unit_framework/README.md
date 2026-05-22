# Unit Framework Suite

This directory groups the native unit-test corpus that summarizes the already
completed demo coverage into a single framework-focused suite.

## Feature buckets

| Bucket | Representative demos | Covered by |
| --- | --- | --- |
| Branching and control flow | `03_if_else`, `21_while_loop`, `23_nested_loops` | `03_if_else branch path` |
| Layout and pointer access | `05_struct`, `28_borrow_chains` | `05_struct field layout`, `28_borrow_chains repeated load` |
| Tagged dispatch | `06_enum_and_match`, `43_tagged_union` | `06_enum_and_match tag dispatch` |
| Module import | `41_module_imports`, `223_mod_visibility_private`, `237_mod_inline_submodule` | `41_module_imports helper import` |
| Panic handling | `178_panic_hook_override` | `178 panic hook path` |
| Ignored selection | native unit-test framework behavior | `framework ignored case` |

The sibling `runner.zig` file executes the suite through `sa test` and
checks default, `--ignored`, and `--include-ignored` behavior end to end.
