# SA 架构限制阻碍 Lua 编译器完成的完整清单

> 基于 `sa/` 仓库的实际开发经验和 EVALUATION.md 的分析。
> 当前状态：parser.sa = 322 个函数 / 17,479 条指令 / 35,280 token，仅覆盖 `local`/`return`/`if-return` 子集。

---

## 一、核心架构缺失（P0 — 直接阻塞扩展）

### 1. 缺少结构化 switch/match

**现状**：对 token kind 或 opcode 的多路分支只能用逐个 `eq` + `br` 链实现。
**影响**：每个 token 类型检查都是独立的 `eq` + `br`，无法表达 `switch(token.kind) { case NAME: ... case NUMBER: ... }`。
**证据**：`lua_lexer_next` (511 条指令) 的主循环就是一个 10+ 层的 `br` 链，每增加一个 token 类型就加一个分支。

### 2. 缺少共享清理 / epilogue 抽象

**现状**：每个函数的每个分支出口都必须手动释放所有活跃寄存器，用 `!reg` 逐个释放。
**影响**：分支越多，释放路径越多，代码量和出错概率呈二次增长。宏只能解决文本重复，无法解决语义层面的共享清理。
**证据**：`lua_parse_return_paren_expr` (351 条指令) 有 6 个出口，每个出口重复释放相同的 8-12 个寄存器。

### 3. 缺少安全有界循环抽象

**现状**：所有循环必须手写 `jmp L_HEAD` + 条件 `br`，且循环体内不能有 `stack_alloc`（会触发 PhiStateConflict）。
**影响**：scanner（词法扫描）、escape decoder（转义解码）、Pratt parser 等需要循环的场景都变成手写 goto 状态机。
**证据**：
- `lua_string_new_from_escaped_span` = 690 条指令（单字节逐个处理的 goto 状态机）
- `pratt_parse_expr` = 300 条指令
- `lua_lex_scan_string_close` = 80 条指令（仅处理 `]]` 长字符串结束标记）

### 4. 缺少高层表达式/AST 层

**现状**：parser 没有 AST，所有解析直接生成 bytecode。每种表达式组合都需要专用的 parse + compile 函数。
**影响**：这是当前最大的扩展瓶颈。每增加一种语法形式，parser 面积线性增长。
**证据**：152 个 parser 相关函数占总指令数的 60%。函数名呈现组合爆炸模式：
```
lua_parse_local_local_local_binary_return_integer    (509 ins)
lua_parse_local_local_return_binary_integer          (371 ins)
lua_parse_local_local_binary_return_integer          (348 ins)
lua_parse_local_const_binary_return_integer          (344 ins)
lua_parse_local_return_binary_integer                (235 ins)
lua_parse_local_binary_return_integer                (235 ins)
```
每增加一个维度（多一个 local、多一个 binary、多一个 return variant），就多一个 ~200-500 条指令的函数。

---

## 二、仿射类型系统的实际限制（P0/P1）

### 5. PhiStateConflict：分支内的 stack_alloc

**现状**：`stack_alloc` 的寄存器在 `br` 的一个分支内分配但不在另一个分支分配时，汇合点触发 `PhiStateConflict`。且 `stack_alloc` 无法显式释放（`stack_escape` trap）。
**影响**：必须在分支前 hoist `stack_alloc`，即使某个分支不需要它。这导致寄存器浪费和代码结构扭曲。
**证据**：`lua_parse_return_not_paren_expr` 中的 `string_start_slot`/`string_len_slot` 必须提到分支前分配。

### 6. 单次赋值的仿射约束

**现状**：每个寄存器只能使用一次。`return` 一个值后，该寄存器不能再用。
**影响**：无法写 `return call @fn(...)`，必须中间变量。无法在分支合并后重用寄存器，必须 `alloc` 新的。
**证据**：`return call @fn(...)` 语法不支持，flattener 将其解析为 `return register named "call @fn(...)"`，触发 `UnknownRegister`。

### 7. 分支间的 live register delta 诊断差

**现状**：当两个分支的活跃寄存器集合不同时，verifier 报错信息指向错误的寄存器名。
**影响**：调试分支相关错误极其困难，每个 bug 修正在编辑-编译-调试循环中需要多次迭代。
**证据**：`snapshotFirstMismatch` (verifier.zig:719) 使用 slot index 而非 globalId 查找寄存器名，导致报错的寄存器名与实际冲突的寄存器不匹配。

---

## 三、缺少注册表/符号表抽象（P1）

### 8. 无 scoped symbol table

**现状**：局部变量的名称解析使用手写的 per-function 环境（`lua_local_const_env_*`），每个作用域一层手动管理。
**影响**：无法实现嵌套作用域的名称遮蔽（shadowing）；每增加一种作用域类型就需要新的环境管理代码。
**证据**：`lua_local_const_env_store` (21 ins) + `lua_local_const_env_lookup_token` (73 ins) 是手写的专用 helper，不是可复用的 symbol table。

### 9. 无寄存器分配器

**现状**：所有寄存器使用手动 `alloc`/`!`，每个函数独立管理。
**影响**：`lua_funcstate_freereg` 是唯一的形式化 "寄存器分配"，但它是静态的（`maxstacksize`），不支持复用。
**证据**：每个 parser 函数的 cleanup tail 都是一长串 `!reg`，无法自动计算哪些寄存器在某个点仍然活跃。

---

## 四、VM/后端扩展限制（P1/P2）

### 10. 无结构化多路派发

**现状**：VM 的 opcode 派发是手写的 `br` 链，每个 opcode 一个标签。
**影响**：每增加一个 opcode，就增加一个分支 + 完整的 cleanup tail。VM 代码量与 opcode 数量成正比。
**证据**：`lua_vm_execute` = 2,269 条指令，57 个 `VM_NEXT` 宏调用（每个 opcode 一个）。

### 11. 无 peephole 优化

**现状**：编译器输出的 bytecode 不做任何优化（无常量折叠、无死代码消除、无寄存器复用）。
**影响**：`local x = 1; return x` 和 `return 1` 生成完全不同的 bytecode 路径，无法合并。
**证据**：当前有 ~20 个不同的 proto builder 函数（`lua_proto_new_*`），每个对应一种编译路径的输出。

### 12. 无共享 cleanup tail（尾合并）

**现状**：相同的 release/return 序列在每个分支出口重复出现，编译器无法识别和合并。
**影响**：parser 代码中 60% 的指令是 cleanup/return 代码，而非逻辑代码。
**证据**：`lua_parse_return_expr` = 295 条指令，其中约 60% 是各出口的 register release + return。

---

## 五、工具链/语言层缺失（P2）

### 13. `return call @fn(...)` 不支持

**现状**：flattener 将 `return call @fn(...)` 解析为返回一个名为 `call @fn(...)` 的寄存器。
**影响**：所有需要 `return call @foo(...)` 的地方都必须写两行：`result = call @foo(...); return result`。
**证据**：所有 322 个 parser 函数中没有任何一个使用 `return call @fn(...)`。

### 14. 宏不能定义 label

**现状**：`[MACRO]` 展开时所有行都被缩进，label（必须在第 0 列）无法在宏内定义。
**影响**：无法用宏封装 "check + two-way branch + label 定义" 这种常见模式。本次 SCAN_TWO_CHAR 宏尝试失败。
**证据**：lexer.sa 中 6 个完全相同的两字符扫描块（~30 行 × 6 = 180 行）无法宏化。

### 15. 宏不能引用后定义的常量

**现状**：宏体中的符号引用必须在 `@import` 该 `.sal` 文件时已定义。`#def` 在 `.sa` 文件中晚于 `@import` 的位置定义，宏展开时无法解析。
**影响**：宏只能使用 `.sal` 文件中定义的常量，不能使用调用者文件中 `#def` 的常量。
**证据**：`LEXER_SYMBOL_RETURN` 宏中的 `LUA_TOKEN_SYMBOL` 常量定义在 `lexer.sa` 的 `@import "lua/lexer.sal"` 之后。虽然当前可以工作（因为 EXPAND 在常量定义之后），但这依赖于展开顺序。

---

## 六、量化影响总表

| 限制 | 直接影响的 Lua 功能 | 受阻程度 |
|------|---------------------|----------|
| 缺少高层 AST/表达式层 | while、for、function、table、method 调用、嵌套表达式 | 🔴 阻塞 |
| 缺少有界循环 | while、for、repeat 循环体、完整字符串转义 | 🔴 阻塞 |
| PhiStateConflict | 复杂条件分支内的 stack_alloc | 🟡 需 workaround |
| 缺少共享清理 | 所有新函数的代码膨胀 | 🟡 倍增成本 |
| 缺少 switch/match | 更多 token 类型的 lexer/parser | 🟡 倍增成本 |
| 缺少 scoped symbol table | 嵌套作用域、闭包、函数参数 | 🟡 需 workaround |
| 无 register allocator | 所有新函数的手动寄存器管理 | 🟡 倍增成本 |
| VM 无结构化派发 | 更多 opcode 的 VM 扩展 | 🟠 线性增长 |
| 无 peephole 优化 | 编译输出质量 | 🟠 质量损失 |
| `return call` 不支持 | 所有直接返回调用结果的场景 | 🟢 有 workaround |
| 宏不能定义 label | 扫描器模式的宏化 | 🟢 有限影响 |
| Verifier 诊断差 | 调试分支相关错误 | 🟢 效率损失 |

**结论**：当前 SA 编译器覆盖了 Lua 的 `local`/`return`/`if-return` 子集（~322 个函数）。要扩展到 while、for、function、table、闭包等完整 Lua 子集，需要至少解决 P0 级别的 4 个限制。否则每增加一个语法特性，parser 面积将以 ~500-1000 条指令/特性 的速度增长。
