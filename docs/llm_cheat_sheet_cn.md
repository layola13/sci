# SA-ASM（线性所有权汇编）LLM 速查表

> 本文为英文原版 [SA-ASM (Linear Ownership Assembly) LLM Cheat Sheet](./llm_cheat_sheet.md) 的中文对照版。

**系统背景**：SA（safe asm，安全汇编）是一种面向行的仿射所有权汇编语言。它无需 GC 即可实现内存安全。

## 1. 核心 5 符号所有权契约
- `=` **（绑定 / Bind）**：`r = alloc N` → `r` 变为 `Active`。
- `&` **（借用 / Borrow）**：`b = &r` → `r` 变为 `Locked`（Read/Mut），`b` 变为 `BorrowView`。
- `^` **（移动 / Move）**：`call @consume(^r)` → `r` 变为 `Consumed`（若被访问则 UseAfterMove）。
- `!` **（释放 / Release）**：`!b` 解锁父级；`!r` 物理释放堆分配。
- `*` **（逃逸 / Escape）**：`raw = *safe` → 仅在 `@ffi_wrapper` 函数中允许。

## 2. 函数签名与 ABI
- **按值（By-value）**：`@f(x: i32)`（仅限基本类型）。
- **借用（Borrow）**：`@f(r: &ptr)`（必须是 `ptr` 类型）。
- **移动（Move）**：`@f(^d: ptr)`（必须是 `ptr` 类型）。
- **可失败返回（Return Fallible）**：`@f() -> i32!`（ABI 映射为 `{u32 status, T value}`）。
- **外部/导出（Extern/Export）**：`@extern f(*p: ptr)`（C-ABI 兼容）。

## 3. 基本语法与操作
- **无嵌套块**：控制流严格扁平（`jmp`、`br`、`br_null`、`return`）。每个块必须以跳转/分支/返回结束。
- **偏移/结构体**：通过预处理器模拟。`#def Vec_len = +0`，`load ptr+Vec_len as u32`。
- **错误传播（`?`）**：`res = call @f()`；`val = ? res`。展平为 `br_ok + L_early_return`。
- **气闸（Airlock / FFI）**：不安全的指针转换（`assume_safe`、`assume_borrow`、`*`）在 `@ffi_wrapper` 之外严格禁止。
- **系统调用**：`@sys_print`、`@sys_exit`、`@sys_read_file` 等是原生内建函数。

## 4. 关键 LLM 生成规则（Referee/裁判检查）
1. **MemoryLeak 陷阱**：所有 `Active` 和 `BorrowView` 寄存器在 `return` 之前必须显式释放（`!`）。编译器不会替你插入 drop。
2. **Phi 一致性**：如果从多个分支跳转到标签 `L_NAME:`，每个寄存器的所有权掩码在所有入边上必须完全相同。
3. **DoubleMutableBorrow 陷阱**：不能进行两次独占借用。
4. **UseAfterMove 陷阱**：寄存器被移动（`^`）之后不要触碰它。
5. **EarlyReturnLeak**：如果使用 `?` 且发生错误，提前返回路径绝不能泄漏内存。调用 `!` 函数时如果你有活跃分配，`?` 会触发陷阱。你必须手动处理错误或在 `?` 之前释放内存。

## 5. ISA 速查
- **Mem（内存）**：`alloc`、`stack_alloc`、`load`、`store`、`take`。
- **Math（数学）**：`add`、`sub`、`mul`、`sdiv`、`udiv`、`neg`...
- **Cmp（比较）**：`eq`、`ne`、`slt`、`sle`、`sgt`、`sge`、`ult`、`ule`、`ugt`、`uge`...
- **Cast（转换）**：`trunc`、`zext`、`sext`、`bitcast`...
- **Atomic（原子）**：`atomic_load`、`atomic_store`、`cmpxchg`、`fence`。
- **Types（类型）**：`i8`、`i16`、`i32`、`i64`、`u8`、`u16`、`u32`、`u64`、`f32`、`f64`、`ptr`、`v128`。

*（生成 `.sa` 代码时，严格遵守扁平控制流、严谨的显式清理，以及精确的关键字集合）。*
