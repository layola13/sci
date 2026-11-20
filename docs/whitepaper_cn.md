# SA 白皮书 v0.1

> 本文为英文原版 [whitepaper.md](./whitepaper.md) 的中文对照版。

SA（safe asm，安全汇编）是一门面向 LLM 时代的、完全独立的、面向行的仿射所有权语言。它产出原生可执行文件、WebAssembly 模块和可链接的目标文件——不依赖任何宿主语言运行时。

## 身份定位

- **不是 IR**：SA 是一门独立的语言，拥有自己的 CLI、解释器和系统原语。
- **不是依赖宿主的插件**：`sa run hello.sa` 直接执行。无需 Go、Rust、Zig 或 Python 运行时。
- **全平台**：原生（x86_64 / ARM64 / Windows / Linux / macOS）+ WASM（wasm32-wasi / wasm64）+ 可嵌入任意 C-ABI 项目的 `.o`。

## 当前交付内容（v0.1 基线）

| 命令 | 管线 | 产物 |
|---|---|---|
| `sa run <file>` | `.sa` → Flattener / `.sab` → SAB Decoder → Referee → Interpreter | stdout + 退出码 |
| `sa build-exe <file>` | `.sa` → Flattener / `.sab` → SAB Decoder → Referee → LLVM-C bitcode → `.sa.bc` → `zig cc` | 独立的 `.exe` |
| `sa build-wasm <file>` | `.sa` → Flattener / `.sab` → SAB Decoder → Referee → LLVM-C bitcode → `.sa.bc` → `zig cc -target wasm32-wasi` | `.wasm` 模块 |
| `sa build-obj <file>` | `.sa` → Flattener / `.sab` → SAB Decoder → Referee → LLVM-C bitcode → `.sa.bc` → `zig cc -c` | `.o`（可按 C-ABI 链接） |

不生成 Zig 源码。不构建 AST。没有隐藏的往返转换。

**Y 形输入架构**：编译器根据文件扩展名自动检测输入格式——`.sa` 文本（Flattener 路径，支持宏）或 `.sab` 二进制（SAB Decoder 路径，直接解码为 `Instruction[]`）。两条路径在 Referee 之前汇合。二进制格式规范见 `sab.zig`（magic `"SAB\x00"`，v4.0）。

## `sa_std` 归档的入库状态

面向 SA 的标准库模块（`io`、`fs`、`net`、`fmt`、`process`）在 SA 侧通过 `@import` 组装，并在各自的 `.sai` 文件中使用 `@extern` 声明。C/C++ 宿主示例仍然使用 `#include`，但仅限宿主代码。

标准库归档 `artifacts/sa_std/libsa_std.a` 是一个**构建产物**（可用 `zig build sa-std-static -Doptimize=Debug` 重新构建）；在当前 head 上并未签入仓库。实现源码位于 `src/runtime/sa_std.zig`；公开的 C 头文件位于 `src/runtime/sa_std.h`。

`sa_std` 现在还包含第一批面向可移植性的数据结构基础宏：
- 容器构造与字段访问：`STRUCT_NEW`、`FIELD_GET`、`FIELD_SET`、`STRUCT_FREE`、`PTR_FIELD`
- 结构拷贝与相等：`STRUCT_COPY_FIELD`、`STRUCT_COPY`、`STRUCT_EQ_FIELD`、`STRUCT_EQ4`
- Option 与 Result 便捷操作：`OPTION_MATCH_SOME_NONE`、`OPTION_UNWRAP_OR_RETURN`、`RESULT_MATCH_OK_ERR`、`RESULT_RETURN_ERR`、`RESULT_MAP_OK`、`RESULT_IS_OK`、`RESULT_IS_ERR`
- 循环与索引语法糖：`WHILE`、`WHILE_COND`、`FOR_RANGE`、`INDEX_LOOP`、`ARRAY_FOR_EACH`、`ARRAY_SCAN_MIN/MAX`、`SLICE_GET_U64`、`SLICE_GET_U64_AT`
- 位与掩码辅助：`BIT_MASK`、`BIT_SET`、`BIT_GET`、`BIT_CLEAR`、`BIT_TEST`、`BIT_INDEX_BYTE`、`BIT_INDEX_BIT`
- 哈希与探测辅助：`HASH_PTR`、`HASH_MIX`、`HASH_MOD`、`PROBE_START`、`PROBE_NEXT`、`MAP_LOOKUP`、`MAP_INSERT_OR_UPDATE`
- 清理语法糖：`DEFER`、`CLEANUP_ON_ERROR`、`WITH_TEMP`、`RETURN_CLEAN`、`FREE_AND_RETURN`
- 控制流语法糖：`MATCH_BOOL`、`ELIF`、`WHILE_LET`、`BREAK_IF`、`CONTINUE_IF`

## 核心符号（5 个所有权运算符 + 1 个逃逸）

| 符号 | 语义 | 状态效果 |
|---|---|---|
| `=` | 分配 / 绑定 | 目标 → Active |
| `&` | 借用（读或写由 Referee 动态判定） | 源 → Locked_Read/Locked_Mut，借用 → Active(BorrowView) |
| `^` | 移动 / 消费 | 源 → Consumed |
| `!` | 释放（借用 → 解锁源；所有权 → 物理释放） | 目标 → Consumed |
| `*` | 裸指针逃逸（仅限 `@ffi_wrapper` 内） | 产生 Untracked 寄存器 |
| `$...$` | 原生代码逃逸块 | 保守地消费被引用的寄存器 |

**语法中没有 `&mut`。** 共享与独占由 Referee 在验证时通过 `Locked_Read` / `Locked_Mut` 位掩码决定。

## 指令集（ISA）

### 内存
- `reg = alloc N` — 堆分配
- `reg = stack_alloc N` — 栈分配（生命周期绑定到函数，不可 `^` 逃逸）
- `dst = load src+offset [as T]` — 按字节偏移读取
- `store dst+offset, val [as T]` — 按字节偏移写入
- `dst = take src+offset` — 提取内部指针的所有权
- `dst = ptr_add base, offset` — 为路线图中的 InteriorPtr 派生保留

### 算术与逻辑
- 整数：`add / sub / mul / sdiv / udiv / srem / urem / neg`
- 位运算：`and / or / xor / shl / lshr / ashr / not`
- 整数比较：`eq / ne / slt / sle / sgt / sge / ult / ule / ugt / uge`
- 浮点：`fadd / fsub / fmul / fdiv / fneg`
- 浮点比较：`fcmp_eq / fcmp_ne / fcmp_lt / fcmp_le / fcmp_gt / fcmp_ge`
- 类型转换：`trunc / zext / sext / fptosi / sitofp / uitofp / fptrunc / fpext / bitcast`
- SIMD（精简）：`add.v128 / sub.v128 / mul.v128 / shuffle.v128 / extract_lane / insert_lane`

### 原子操作
- `dst = atomic_load src+offset [ordering]`
- `atomic_store dst+offset, val [ordering]`
- `dst, ok = cmpxchg target+offset, expected, new [success_ord] [failure_ord]`
- `dst = atomic_rmw_<OP> target+offset, val [ordering]` — OP ∈ {add, sub, and, or, xor, xchg, min, max, umin, umax}（`smin`/`smax` 是 `min`/`max` 可接受别名）
- `fence [ordering]`
- 序（ordering）：`relaxed / acquire / release / acq_rel / seq_cst`

### 控制流
- `jmp L_NAME` — 无条件跳转
- `br cond -> L_TRUE, L_FALSE` — 条件分支
- `br_null reg -> L_NULL, L_NOT_NULL` — 空值检查分支
- `call @f(args)` / `call_indirect func_ptr(args)`
- `return [reg]`

## 控制流与 Phi

- SA 保持控制流扁平：每个基本块都以 `jmp`、`br`、`br_null` 或 `return` 结束。
- Phi 一致性是前端的职责。如果两条入边对某个寄存器的 capability 掩码存在分歧，前端必须在发出汇合标签之前修复数据流。
- `libsa_scope` 是用于生成作用域退出与汇合点所需的显式 `!reg` 清理文本的可选辅助库。

### 错误传播
- `v = ? res` — 若 `res.status != 0` 则提前返回（Flattener 展开为 `br` + `return`）
- `panic(code)` — 不可恢复的终止
- `panic_msg(code, *str_ptr, str_len)` — 带消息的终止
- 函数后缀 `!` 标记可失败返回：`@f() -> i32!` → ABI `{u32 status, i32 value}`

### FFI 气闸舱（仅限 `@ffi_wrapper` 内）
- `raw = *safe` — 剥离 capability 掩码
- `safe = assume_safe raw` — 授予裸指针 Active 掩码
- `view = assume_borrow raw [, mut]` — 授予 FfiBorrow 视图（`!` 时不发生物理释放）

## 能力掩码（10 位，存储为 u16）

```
bit 0  (0x0001)  Active
bit 1  (0x0002)  Locked_Read
bit 2  (0x0004)  Locked_Mut
bit 3  (0x0008)  Consumed
bit 4  (0x0010)  BorrowView
bit 5  (0x0020)  FfiBorrow
bit 6  (0x0040)  Untracked
bit 7  (0x0080)  Fallible
bit 8  (0x0100)  Immutable
bit 9  (0x0200)  InteriorPtr
```

Referee 通过线性扫描 + 按位 AND/OR 来验证所有权。不使用图论。不回溯。

## 函数签名

| Rust 形式 | SA 签名 | 规则 |
|---|---|---|
| `fn f(x: i32)` | `@f(x: i32)` | 按值传递，仅限原生数值类型 |
| `fn f(r: &T)` / `fn f(r: &mut T)` | `@f(r: &ptr)` | 借用，ty 必须是 `ptr` |
| `fn f(d: T)`（移动） | `@f(^d: ptr)` | 移动，ty 必须是 `ptr` |
| `fn f() -> Box<T>` | `@f() -> ^ptr` | 移出 |
| `fn f() -> Result<T,E>` | `@f() -> i32!` | 可失败 ABI |
| `extern fn f(p: *T)` | `@extern f(*p: ptr)` | FFI 裸指针 |

**签名中不允许用户自定义类型名。** 布局仅存在于 `#def` 字典中。

## 预处理器

- `#def NAME = VALUE` — 文本替换 + 常量折叠（`+/-/*`）
- `#loc "file":line:col` — 上游源码映射（→ DWARF `!DILocation`）
- `[MACRO] NAME %p1, %p2 ... [END_MACRO]` — 参数化文本模板
- `[REP N] ... [END_REP]` — 带 `%i` 游标的编译期展开
- `EXPAND NAME arg1, arg2` — 宏调用
- `@const NAME = <literal>` — 全局只读数据（.rodata），无类型标注；已实现（见下方「全局常量」）

## 全局常量（`@const`）

```
@const HELLO_BYTES = utf8:"hello world"
@const ZEROS_256 = repeat:256 of 0x00
@const CIRCLE_VT = vtable { draw = @Circle_draw, drop = @Circle_drop }
```

无类型标注。字节长度从字面量推断。路线图特性：不可变掩码不可 `^`、`!` 或独占借用。

## 系统原语（`@sys_*`）

| 原语 | 原生映射 | WASM（WASI）映射 |
|---|---|---|
| `@sys_print(*msg, len)` | `write(1, ...)` | `fd_write` |
| `@sys_read_file(*path, plen, *out_len) -> *buf` | `open+read+close` | `path_open+fd_read` |
| `@sys_write_file(*path, plen, *data, dlen) -> i32` | `open+write+close` | `path_open+fd_write` |
| `@sys_exit(code)` | `_exit` | `proc_exit` |
| `@sys_argv(i) -> *str` / `@sys_argc() -> i32` | 进程参数 | `args_get` |

## FFI 气闸舱

- `@ffi_wrapper` 函数是 `*` / `assume_safe` / `assume_borrow` 唯一合法的出现位置。
- 普通 `@f` 使用这些操作 → `Trap: IllegalUnsafeContext`。
- FFI 内存仅通过 `assume_borrow` 进入沙箱（不向沙箱内转移所有权）。
- 对长生命周期的宿主对象使用 Handle/ID 模式。
- `@extern` 声明 C-ABI 符号；`@export` 以无名称修饰的方式暴露 C-ABI 符号。

## 构建模式

- 优化通过 `--release-fast` / `--release-small` 选择；没有 `--release` 标志，也没有默认的发布模式（测试构建默认 -O0）。所有所有权检查都在编译期完成，因此产物不携带 Referee 运行时。
- `-g` 启用 DWARF 与上游源码映射。
- `--no-debug` 剥离调试元数据。
- （已删除：早期草稿描述过 `--debug-gas` / `--debug-san` 模式——这些 CLI 标志并不存在。Gas 计量通过编译指标报告；`GasExceeded` 仍是仅存在于路线图中的 trap。）

## 前端合约（R20）

- 前端负责作用域退出：当作用域结束时，为每个仍然存活的寄存器发出显式 `!reg`。
- 前端负责 Phi 一致性：标签的每条入边都必须就 capability 掩码达成一致，否则前端必须在发出之前修复数据流。
- 前端负责降级：`match`、`async` 以及隐式 Drop 插入都是上游的职责，不属于 SA 语义。
- `libsa_scope` 是用于这些修复的可选辅助库；SA 本身不推断生命周期。

## Referee Trap 码

权威 trap 目录：[`docs/errorcode.md`](/home/vscode/projects/sci/docs/errorcode.md)。
本节为面向读者的精简摘要，可能滞后于实时命名空间。

| Trap | 触发条件 |
|---|---|
| ForbiddenSyntax | 源码中出现 `{}` / `if` / `while` / `for` / `a.b.c` |
| DuplicateDef | `#def` 名称重复 |
| DuplicateLabel | 同一函数中两次出现相同的 `L_NAME:` |
| UnsupportedType | 类型标注不在 {i8..u64, f32, f64, ptr, v128} 中 |
| MacroRecursionLimit | 展开深度 > 256 |
| RegisterRedefinition | 宏展开产生重复的 Active 寄存器 |
| UnknownRegister | 引用从未赋值的寄存器 |
| BorrowConflict | 对 Locked_Mut 寄存器进行读/写/移动 |
| UseAfterMove | 访问 Consumed 寄存器 |
| DoubleMutableBorrow | 对同一源进行第二次独占借用 |
| ReadWriteConflict | 将 Locked_Read 升级为 Locked_Mut |
| MemoryLeak | 函数退出时仍有 Active/Locked 寄存器 |
| CapabilityMismatch | 调用点的 capability 前缀与签名不匹配 |
| FallthroughForbidden | 基本块未以 jmp/br/return 结束 |
| PhiStateConflict | 标签的入边掩码不兼容 |
| IllegalUnsafeContext | `@ffi_wrapper` 之外使用 `*`/`assume_*` |
| FfiOwnershipViolation | 对 FfiBorrow 寄存器执行 `^`/`!` |
| InteriorPtrEscape | InteriorPtr 被传入 `@extern` |
| StackEscape | `stack_alloc` 产物被 `^` 移动或返回 |
| ConstMutation | 对 `@const` 寄存器执行 `^`/`!`/独占借用 |
| EarlyReturnLeak | `?` 提前返回路径上存在未释放的 Active 寄存器 |
| InvalidAtomicOrdering | `cmpxchg` 的 failure_ord 强于 success_ord |
| VTableSignatureMismatch | `call_indirect` 参数与 vtable 槽签名不匹配（v0.3） |

## Panic 码字典（R18.6）

| 码 | 含义 |
|---|---|
| 100 | DivByZero |
| 101 | OutOfBounds |
| 102 | Unreachable |
| 103 | AssertionFailed |
| 104 | IntegerOverflow |
| 105 | NullDeref |
| 106 | MissingVariant |
| 107 | AllocFailed |
| 108–127 | Reserved |
| 128–255 | User-defined |

## 分布式编译（SAB 模块系统）

> **状态（2026-11-05）：设计提案——尚未实现。** 本节中的命令与缓存模型描述的是 `docs/sab_distributed_compilation.md` 中的目标设计。当前已有的能力是：`.sab` 输入被共享编译管线接受，且 `sa check <file> --emit-sab <path>` 可将已验证的程序写为 `.sab`。目前没有 `sa build --emit-sab`，`build-workspace` 也没有 `--distributed` / `--dry-run` 模式（它只构建所选的 workspace 成员），并且尚无跨模块 Referee 或 `.sa_cache/<module>.sab` 失效模型。

提议的设计：通过 `.sab` 二进制模块实现模块级分布式编译：

| 命令（提议） | 管线 | 产物 |
|---|---|---|
| `sa build --emit-sab <file>` | `.sa` → Flattener → SAB Encoder → `.sab` 缓存 | `<stem>.sab` |
| `sa build-workspace --distributed` | 依赖分析 → 并行 flatten → 并行 Referee → 跨模块验证 → 链接 | 最终二进制 |
| `sa build-workspace --dry-run` | 仅输出需重编译的模块列表 | 模块列表 |

**缓存模型**：`.sab` 文件是 Flattener 输出的持久化缓存。后续编译直接将 `.sab` 解码为 `Instruction[]`，从而跳过整个 Flattener（宏展开、`@import` 解析、文本解析）。

**并行性**：每个模块的 Flattener 和 Referee 独立运行。跨模块 `@export`/`@extern` 签名匹配在所有模块各自通过 Referee 之后才进行验证。

**增量**：通过 `SHA256(source + sa_mod_hash + compiler_version)` 实现模块级缓存失效。未变更的模块复用 `.sa_cache/<module>.sab`。

**JS/TS 类比**：`.sab` 之于 SA，正如 `.js` 之于 TypeScript——一种预编译的、自包含的、可分发的模块格式。`sa build-workspace --distributed` 就是 SA 的 webpack/esbuild。

完整设计见 `docs/sab_distributed_compilation.md`。

## 版本路线图

| 版本 | 重点 |
|---|---|
| v0.1 | 闭环：Flattener + Referee + LLVM bitcode + CLI（14 周） |
| v0.2 | 自研 WASM emitter + `#mode compact` 中缀语法糖 ~~（已由外部 SLA 插件 `sa_plugin_sla` 替代）~~ |
| v0.3 | 性能：VTable 签名检查 + `libsa_async` 宏 + `--debug-san` |
| v0.4 | 并行开发：`.sai` + `.sal` + 增量编译 |
| v0.5 | 生态：`sa.pkg` 包管理器 + `#tag` 布局标记 + `sa_std` |
| v0.6 | 认证：Referee 形式化证明（Coq/Lean4）+ FPGA 硬件 Referee |
| v0.7b | 分布式编译：`--emit-sab` + `build-workspace --distributed` + 模块级并行 Referee |
| v1.0+ | 自托管（用 SA 编写 SA 编译器） |

## 设计原则

1. **零 AST**——扁平数组 + u32 索引。没有树，没有图。
2. **线性扫描**——所有阶段都是单向单遍。不回溯。
3. **O(1) 位掩码**——所有权转换就是 u16 上的 AND/OR。不使用约束求解器。
4. **五符号合约**——`= & ^ ! *` 覆盖全部所有权语义。
5. **前端负责**——Drop 插入、Phi 一致性、单态化都是上游的职责。
6. **上游可追溯**——`#loc` → DWARF `!DILocation` → 在原始源码上命中 gdb/lldb 断点。
7. **显式优于隐式**——没有 GC、没有隐藏的 Drop、没有异常展开、没有 async 魔法。
8. **气闸舱隔离**——所有不安全的指针操作在物理上都被限制在 `@ffi_wrapper` 函数内。
9. **完全独立**——SA 独立运行。与 Rust/Go/Zig/C++ 的互操作是可选的，通过 C-ABI 实现。

## 互操作性

SA 通过标准 C-ABI 与任何语言互操作：
- `@export` 产出无名称修饰的符号，可被 C/C++/Rust/Go/Zig 调用。
- `@extern` 声明由任意 C-ABI 库提供的外部符号。
- `sa build-obj` 产出可与 `zig cc`、`gcc`、`clang` 或 `cargo` 链接的 `.o` 文件。
- FFI 内存安全由气闸舱强制保证：外部指针仅通过 `assume_borrow` 进入。

## 测试模型

- `sa run test.sa` + 退出码 0/非零表示通过/失败。
- `sa_core.sa` 中的 `ASSERT_EQ` / `ASSERT_TRUE` 宏。
- 必须 trap 的测试：验证 Referee 能正确拒绝非法代码。
- `@export` + 外部测试框架（Zig test / Rust #[test] / Google Test）。
- 基于属性的测试：32 条属性 × 100+ 次随机迭代。

## Rust -> SA -> LLVM Bitcode 示例

| 案例 | Rust | SA | LLVM bitcode 形态 |
|---|---|---|---|
| 结构体字段访问 | `v.x + v.y` | `#def Vec3_x = +0`, `#def Vec3_y = +4`, `x = load v+Vec3_x as f32` | `getelementptr` + `load` |
| Option + `?` | `let x = read()?;` | `res = call @read(...); x = ? res` | `extractvalue` + `icmp` + `br` |
| dyn Trait + VTable | `obj.draw()` | `@const VT = vtable { draw = @draw }; call_indirect draw_fn(obj_data)` | `load ptr` + 间接调用 |
| async 单次 poll | `fetch().await?;` | `ctx state labels + poll fn + pending path` | 标签分发 + 分支 |
| Rc clone + drop | `a.clone(); drop(b)` | 对 `Rc_strong` 执行 `atomic_rmw_add` / `atomic_rmw_sub` | `atomicrmw add/sub` |

## 试点协议

- 生成 30 条零样本提示：10 个基础用例 × 每个 3 个变体。
- 针对 GPT-4o、Claude Opus 和 DeepSeek-Coder 运行这些提示。
- 将首过 Referee 通过率记录为观测基线；不预先声明 KPI。
- 如果基线低于 50%，重新审视项目是否应在 MVP 冻结前增加一个文本级的伪嵌套前端，并将该决策纳入 MVP 之后的路线图。

## 状态

本文档反映当前 v0.1 的实现状态。Flattener、Referee、LLVM-C bitcode Emitter、Interpreter、CLI 和布局生成器均已可用。剩余的路线图项在 `tasks.md` 中跟踪。
